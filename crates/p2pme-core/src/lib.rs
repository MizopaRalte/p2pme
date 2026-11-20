pub mod drop;
pub mod net;
pub mod storage;
pub mod sync;
pub mod ticket;

pub use drop::*;

use anyhow::Result;
use net::protocol::WireMessage;
use net::QuicTransport;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use storage::StateCatalog;
use sync::SyncSession;
use ticket::{AccessMode, PairingTicket};
use tokio::sync::{Mutex, RwLock};
use tracing::{info, warn};

pub struct P2PNode {
    pub node_id: String,
    pub transport: Arc<QuicTransport>,
    pub db_dir: PathBuf,
    pub drop_manager: Arc<DropManager>,
    pub sync_sessions: Arc<RwLock<HashMap<String, (Arc<SyncSession>, String)>>>,
}

impl P2PNode {
    /// Initialize a new P2P node with random or specified Node ID
    pub async fn new<P: AsRef<Path>>(db_dir: P, bind_port: u16) -> Result<Self> {
        let db_dir = db_dir.as_ref().to_path_buf();
        std::fs::create_dir_all(&db_dir)?;

        let node_id_file = db_dir.join("node_id.txt");
        let node_id = if node_id_file.exists() {
            std::fs::read_to_string(&node_id_file)?.trim().to_string()
        } else {
            // 128-bit CSPRNG hex string (37 chars, valid DNS label length <= 63)
            let id = format!("node_{}", &blake3::hash(&rand::random::<[u8; 32]>()).to_hex()[..32]);
            std::fs::write(&node_id_file, &id)?;
            id
        };

        let transport = Arc::new(QuicTransport::bind(bind_port, node_id.clone()).await?);
        let drop_manager = Arc::new(DropManager::new());
        let sync_sessions: Arc<RwLock<HashMap<String, (Arc<SyncSession>, String)>>> =
            Arc::new(RwLock::new(HashMap::new()));

        info!("P2Pme node initialized: ID={} port={}", node_id, transport.listening_port);

        // Central incoming connection listener multiplexing Sync and Quick Drop RPCs
        {
            let incoming_transport = transport.clone();
            let dm = drop_manager.clone();
            let sess = sync_sessions.clone();

            tokio::spawn(async move {
                while let Some(incoming) = incoming_transport.endpoint.accept().await {
                    let dm = dm.clone();
                    let sess = sess.clone();
                    tokio::spawn(async move {
                        match incoming.await {
                            Ok(connection) => {
                                while let Ok((mut send, mut recv)) = connection.accept_bi().await {
                                    if let Ok(request) = QuicTransport::read_message(&mut recv).await {
                                        match &request {
                                            WireMessage::DropHello { .. }
                                            | WireMessage::DropRequestChunk { .. }
                                            | WireMessage::DropComplete { .. } => {
                                                if let Ok(resp) = dm.handle_drop_rpc(request).await {
                                                    QuicTransport::write_message(&mut send, &resp).await.ok();
                                                }
                                            }
                                            _ => {
                                                // Extract folder_id from message
                                                let folder_id = match &request {
                                                    WireMessage::Hello { folder_id, .. } => Some(folder_id.clone()),
                                                    WireMessage::RequestManifest { folder_id } => Some(folder_id.clone()),
                                                    WireMessage::RequestChunkPlan { folder_id, .. } => Some(folder_id.clone()),
                                                    WireMessage::RequestChunk { folder_id, .. } => Some(folder_id.clone()),
                                                    _ => None,
                                                };

                                                if let Some(fid) = folder_id {
                                                    let session_info = {
                                                        let map = sess.read().await;
                                                        map.get(&fid).cloned()
                                                    };

                                                    if let Some((session, auth_token)) = session_info {
                                                        if let Ok(resp) = session.handle_rpc(request, &auth_token).await {
                                                            QuicTransport::write_message(&mut send, &resp).await.ok();
                                                        }
                                                    } else {
                                                        let err_resp = WireMessage::HelloAck {
                                                            accepted: false,
                                                            reason: Some("Folder not found on peer".to_string()),
                                                        };
                                                        QuicTransport::write_message(&mut send, &err_resp).await.ok();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Err(e) => {
                                warn!("Failed to establish incoming peer connection: {:?}", e);
                            }
                        }
                    });
                }
            });
        }

        Ok(Self {
            node_id,
            transport,
            db_dir,
            drop_manager,
            sync_sessions,
        })
    }

    /// Share a local folder and generate a pairing ticket
    pub async fn share_folder<P: AsRef<Path>>(
        &self,
        folder_path: P,
        folder_id: &str,
        access: AccessMode,
        sync_mode: ticket::SyncMode,
        auth_token: &str,
    ) -> Result<PairingTicket> {
        let path = folder_path.as_ref();
        let db_file = self.db_dir.join(format!("{}.db", folder_id));
        let catalog = Arc::new(Mutex::new(StateCatalog::new(&db_file)?));

        // Initial scan
        {
            let mut cat = catalog.lock().await;
            cat.scan_directory(folder_id, path)?;
        }

        let session = Arc::new(SyncSession::new(
            folder_id.to_string(),
            path,
            catalog,
            sync_mode,
        ));

        // Register session in active lookup table
        {
            let mut map = self.sync_sessions.write().await;
            map.insert(folder_id.to_string(), (session, auth_token.to_string()));
        }

        // Start LAN discovery beacon
        net::start_lan_beacon_sender(
            self.node_id.clone(),
            self.transport.listening_port,
            folder_id.to_string(),
        )
        .await?;

        // Determine candidate direct addresses (LAN IPs + STUN Public WAN socket + Localhost fallback)
        let mut candidate_addrs = discover_local_addrs(self.transport.listening_port);
        if let Some(public_addr) = net::stun::discover_public_address(self.transport.listening_port).await {
            if !candidate_addrs.contains(&public_addr) {
                candidate_addrs.push(public_addr);
            }
        }

        let ticket = PairingTicket::new(
            self.node_id.clone(),
            folder_id.to_string(),
            access,
            sync_mode,
            candidate_addrs,
            auth_token.to_string(),
            86400, // 24 hour default expiration
        );

        Ok(ticket)
    }

    /// Connect to a remote peer using a ticket and synchronize
    pub async fn sync_folder<P: AsRef<Path>>(
        &self,
        folder_path: P,
        ticket: &PairingTicket,
    ) -> Result<sync::SyncStats> {
        let path = folder_path.as_ref();
        std::fs::create_dir_all(path)?;

        let db_file = self.db_dir.join(format!("{}.db", ticket.folder_id));
        let catalog = Arc::new(Mutex::new(StateCatalog::new(&db_file)?));
        let session = SyncSession::new(
            ticket.folder_id.clone(),
            path,
            catalog,
            ticket.sync_mode,
        );

        // Try direct addresses
        let mut last_err = None;
        for &addr in &ticket.direct_addresses {
            info!("Attempting connection to peer at {}", addr);
            match self.transport.connect(addr, &ticket.node_id).await {
                Ok(conn) => {
                    info!("Connected to peer at {}", addr);
                    return session.pull_from_peer(&conn, &self.node_id, &ticket.auth_token).await;
                }
                Err(e) => {
                    warn!("Failed to connect to {}: {:?}", addr, e);
                    last_err = Some(e);
                }
            }
        }

        Err(last_err.unwrap_or_else(|| anyhow::anyhow!("No reachable direct address")))
    }

    /// Create an ephemeral single-use Quick Drop session
    pub async fn create_drop(&self, file_paths: Vec<PathBuf>) -> Result<DropTicket> {
        let mut candidate_addrs = discover_local_addrs(self.transport.listening_port);
        if let Some(public_addr) = net::stun::discover_public_address(self.transport.listening_port).await {
            if !candidate_addrs.contains(&public_addr) {
                candidate_addrs.push(public_addr);
            }
        }
        let ticket = self.drop_manager.create_drop(file_paths, candidate_addrs, &self.node_id).await?;

        // Start local discovery beacon so nearby peers can claim with just the 6-digit PIN
        net::start_drop_lan_beacon(
            self.node_id.clone(),
            self.transport.listening_port,
            ticket.drop_id.clone(),
        )
        .await
        .ok();

        Ok(ticket)
    }

    /// Connect to sender using DropTicket and download files safely
    pub async fn receive_drop<P: AsRef<Path>>(
        &self,
        ticket: &DropTicket,
        pin: Option<&str>,
        target_dir: P,
    ) -> Result<drop::DropReceiveStats> {
        DropManager::receive_drop(&self.transport, ticket, pin, target_dir).await
    }

    /// Receive a Quick Drop on the local network using only the 6-digit PIN
    pub async fn receive_drop_by_pin<P: AsRef<Path>>(
        &self,
        pin_code: &str,
        target_dir: P,
    ) -> Result<drop::DropReceiveStats> {
        let peers = net::discover_lan_drops(std::time::Duration::from_millis(1500)).await?;
        if peers.is_empty() {
            anyhow::bail!("No active Quick Drop senders found on your local Wi-Fi. Ensure both devices are on the same network or use the Drop Ticket / QR code.");
        }

        let mut last_err = None;
        for peer in peers {
            let synthetic_ticket = DropTicket {
                version: 1,
                drop_id: peer.drop_id,
                pin_code: pin_code.to_string(),
                auth_token: String::new(),
                node_id: peer.node_id,
                direct_addresses: vec![peer.addr],
                files: Vec::new(),
                expires_at: 0,
            };

            match DropManager::receive_drop(&self.transport, &synthetic_ticket, Some(pin_code), target_dir.as_ref()).await {
                Ok(stats) => return Ok(stats),
                Err(e) => {
                    last_err = Some(e);
                }
            }
        }

        Err(last_err.unwrap_or_else(|| anyhow::anyhow!("PIN verification failed on discovered peers")))
    }
}

/// Discover candidate local IPv4 addresses for direct LAN connections
pub fn discover_local_addrs(port: u16) -> Vec<SocketAddr> {
    let mut addrs = Vec::new();

    // 1. Probe outbound routing table via UDP connection to well-known IP (no packets sent)
    if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if socket.connect("8.8.8.8:80").is_ok() {
            if let Ok(local_sock) = socket.local_addr() {
                if !local_sock.ip().is_loopback() && !local_sock.ip().is_unspecified() {
                    addrs.push(SocketAddr::new(local_sock.ip(), port));
                }
            }
        }
    }

    // 2. Localhost loopback as fallback for same-machine connections
    let loopback = SocketAddr::new(
        std::net::IpAddr::V4(std::net::Ipv4Addr::LOCALHOST),
        port,
    );
    if !addrs.contains(&loopback) {
        addrs.push(loopback);
    }

    addrs
}
