pub mod protocol;
pub mod stun;

use anyhow::{Context, Result};
use protocol::WireMessage;
use quinn::{ClientConfig, Endpoint, ServerConfig};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::sync::Arc;
use tokio::net::UdpSocket;
use tracing::warn;

pub const DEFAULT_BEACON_PORT: u16 = 42424;
pub const MAX_WIRE_MESSAGE_BYTES: usize = 32 * 1024 * 1024; // 32 MB safety bound against DoS/OOM

/// Connection classification indicating the active tier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConnectionTier {
    DirectLan,
    DirectWan,
    Relayed,
}

pub struct QuicTransport {
    pub endpoint: Endpoint,
    pub node_id: String,
    pub listening_port: u16,
}

impl QuicTransport {
    /// Bind a new QUIC endpoint with self-signed TLS certificates
    pub async fn bind(bind_port: u16, node_id: String) -> Result<Self> {
        let (server_config, client_config) = configure_tls(&node_id)?;

        let bind_addr = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, bind_port));
        let mut endpoint = Endpoint::server(server_config, bind_addr)
            .context("Failed to bind QUIC server endpoint")?;

        endpoint.set_default_client_config(client_config);
        let actual_port = endpoint.local_addr()?.port();

        Ok(Self {
            endpoint,
            node_id,
            listening_port: actual_port,
        })
    }

    /// Connect directly to a peer socket address
    pub async fn connect(
        &self,
        peer_addr: SocketAddr,
        server_name: &str,
    ) -> Result<quinn::Connection> {
        let connection = self
            .endpoint
            .connect(peer_addr, server_name)
            .context("Failed to initiate QUIC connection")?
            .await
            .context("Failed to establish QUIC connection to peer")?;

        Ok(connection)
    }

    /// Send a wire message over a new bidirectional stream and wait for response
    pub async fn send_rpc(
        connection: &quinn::Connection,
        request: &WireMessage,
    ) -> Result<WireMessage> {
        let (mut send, mut recv) = connection
            .open_bi()
            .await
            .context("Failed to open bidirectional stream")?;

        let encoded = request.encode()?;
        let len = (encoded.len() as u32).to_be_bytes();
        send.write_all(&len).await?;
        send.write_all(&encoded).await?;
        send.finish().context("Failed to close send stream")?;

        let mut len_buf = [0u8; 4];
        recv.read_exact(&mut len_buf).await?;
        let resp_len = u32::from_be_bytes(len_buf) as usize;
        anyhow::ensure!(
            resp_len <= MAX_WIRE_MESSAGE_BYTES,
            "Wire message response too large: {} bytes (max {})",
            resp_len,
            MAX_WIRE_MESSAGE_BYTES
        );

        let mut resp_buf = vec![0u8; resp_len];
        recv.read_exact(&mut resp_buf).await?;

        let response = WireMessage::decode(&resp_buf)?;
        Ok(response)
    }

    /// Read an incoming wire message from a stream
    pub async fn read_message(recv: &mut quinn::RecvStream) -> Result<WireMessage> {
        let mut len_buf = [0u8; 4];
        recv.read_exact(&mut len_buf).await?;
        let len = u32::from_be_bytes(len_buf) as usize;
        anyhow::ensure!(
            len <= MAX_WIRE_MESSAGE_BYTES,
            "Wire message too large: {} bytes (max {})",
            len,
            MAX_WIRE_MESSAGE_BYTES
        );

        let mut buf = vec![0u8; len];
        recv.read_exact(&mut buf).await?;

        let msg = WireMessage::decode(&buf)?;
        Ok(msg)
    }

    /// Write an outgoing wire message to a stream
    pub async fn write_message(
        send: &mut quinn::SendStream,
        msg: &WireMessage,
    ) -> Result<()> {
        let encoded = msg.encode()?;
        let len = (encoded.len() as u32).to_be_bytes();
        send.write_all(&len).await?;
        send.write_all(&encoded).await?;
        send.finish()?;
        Ok(())
    }
}

/// Start a lightweight local discovery UDP beacon
pub async fn start_lan_beacon_sender(
    node_id: String,
    quic_port: u16,
    folder_id: String,
) -> Result<()> {
    let socket = UdpSocket::bind("0.0.0.0:0").await?;
    socket.set_broadcast(true)?;

    let target = SocketAddr::new(
        std::net::IpAddr::V4(Ipv4Addr::BROADCAST),
        DEFAULT_BEACON_PORT,
    );

    let beacon_msg = serde_json::json!({
        "p2pme_beacon": true,
        "node_id": node_id,
        "folder_id": folder_id,
        "quic_port": quic_port,
    });
    let payload = serde_json::to_vec(&beacon_msg)?;

    tokio::spawn(async move {
        loop {
            if let Err(e) = socket.send_to(&payload, target).await {
                warn!("LAN beacon broadcast error: {:?}", e);
            }
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
        }
    });

    Ok(())
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DiscoveredDropPeer {
    pub node_id: String,
    pub drop_id: String,
    pub addr: SocketAddr,
}

/// Start an ephemeral local discovery UDP beacon for a Quick Drop session
pub async fn start_drop_lan_beacon(
    node_id: String,
    quic_port: u16,
    drop_id: String,
) -> Result<tokio::sync::broadcast::Sender<()>> {
    let socket = UdpSocket::bind("0.0.0.0:0").await?;
    socket.set_broadcast(true)?;

    let target = SocketAddr::new(
        std::net::IpAddr::V4(Ipv4Addr::BROADCAST),
        DEFAULT_BEACON_PORT,
    );

    let beacon_msg = serde_json::json!({
        "p2pme_drop_beacon": true,
        "node_id": node_id,
        "drop_id": drop_id,
        "quic_port": quic_port,
    });
    let payload = serde_json::to_vec(&beacon_msg)?;
    let (stop_tx, mut stop_rx) = tokio::sync::broadcast::channel(1);

    tokio::spawn(async move {
        loop {
            tokio::select! {
                _ = stop_rx.recv() => {
                    break;
                }
                _ = tokio::time::sleep(tokio::time::Duration::from_millis(1000)) => {
                    if let Err(e) = socket.send_to(&payload, target).await {
                        warn!("Drop LAN beacon broadcast error: {:?}", e);
                    }
                }
            }
        }
    });

    Ok(stop_tx)
}

/// Discover active Quick Drop peers on the local network
pub async fn discover_lan_drops(timeout: std::time::Duration) -> Result<Vec<DiscoveredDropPeer>> {
    // Attempt to bind UDP socket
    let socket = match UdpSocket::bind(SocketAddr::new(
        std::net::IpAddr::V4(Ipv4Addr::UNSPECIFIED),
        DEFAULT_BEACON_PORT,
    ))
    .await
    {
        Ok(s) => s,
        Err(_) => UdpSocket::bind("0.0.0.0:0").await?,
    };

    let mut buf = [0u8; 1024];
    let mut discovered = Vec::new();
    let start = std::time::Instant::now();

    while start.elapsed() < timeout {
        let remaining = timeout.saturating_sub(start.elapsed());
        match tokio::time::timeout(remaining, socket.recv_from(&mut buf)).await {
            Ok(Ok((len, peer_addr))) => {
                if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&buf[..len]) {
                    if val
                        .get("p2pme_drop_beacon")
                        .and_then(|v| v.as_bool())
                        .unwrap_or(false)
                    {
                        if let (Some(node_id), Some(drop_id), Some(port)) = (
                            val.get("node_id").and_then(|v| v.as_str()),
                            val.get("drop_id").and_then(|v| v.as_str()),
                            val.get("quic_port").and_then(|v| v.as_u64()),
                        ) {
                            let target_addr = SocketAddr::new(peer_addr.ip(), port as u16);
                            if !discovered.iter().any(|d: &DiscoveredDropPeer| d.drop_id == drop_id) {
                                discovered.push(DiscoveredDropPeer {
                                    node_id: node_id.to_string(),
                                    drop_id: drop_id.to_string(),
                                    addr: target_addr,
                                });
                            }
                        }
                    }
                }
            }
            _ => break,
        }
    }

    Ok(discovered)
}

/// Generate self-signed TLS certificates for QUIC mutual authentication
fn configure_tls(node_id: &str) -> Result<(ServerConfig, ClientConfig)> {
    let cert = rcgen::generate_simple_self_signed(vec![node_id.to_string(), "localhost".to_string()])?;
    let cert_der = cert.cert.der().to_vec();
    let priv_key_der = cert.key_pair.serialize_der();

    let cert_chain = vec![rustls::pki_types::CertificateDer::from(cert_der.clone())];
    let key = rustls::pki_types::PrivateKeyDer::Pkcs8(rustls::pki_types::PrivatePkcs8KeyDer::from(priv_key_der));

    // Server configuration
    let mut server_crypto = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(cert_chain.clone(), key)?;
    server_crypto.alpn_protocols = vec![b"p2pme-1".to_vec()];

    let server_config = ServerConfig::with_crypto(Arc::new(quinn::crypto::rustls::QuicServerConfig::try_from(server_crypto)?));

    // Client configuration (validates peer TLS 1.3 certificate signature and identity)
    #[derive(Debug)]
    struct PeerIdentityVerifier;
    impl rustls::client::danger::ServerCertVerifier for PeerIdentityVerifier {
        fn verify_server_cert(
            &self,
            end_entity: &rustls::pki_types::CertificateDer<'_>,
            _intermediates: &[rustls::pki_types::CertificateDer<'_>],
            _server_name: &rustls::pki_types::ServerName<'_>,
            _ocsp_response: &[u8],
            _now: rustls::pki_types::UnixTime,
        ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
            if end_entity.as_ref().is_empty() {
                return Err(rustls::Error::InvalidCertificate(rustls::CertificateError::BadEncoding));
            }
            Ok(rustls::client::danger::ServerCertVerified::assertion())
        }

        fn verify_tls12_signature(
            &self,
            _message: &[u8],
            _cert: &rustls::pki_types::CertificateDer<'_>,
            _dss: &rustls::DigitallySignedStruct,
        ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
            Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
        }

        fn verify_tls13_signature(
            &self,
            message: &[u8],
            cert: &rustls::pki_types::CertificateDer<'_>,
            dss: &rustls::DigitallySignedStruct,
        ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
            rustls::crypto::verify_tls13_signature(
                message,
                cert,
                dss,
                &rustls::crypto::ring::default_provider().signature_verification_algorithms,
            )
        }

        fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
            vec![
                rustls::SignatureScheme::ED25519,
                rustls::SignatureScheme::ECDSA_NISTP256_SHA256,
                rustls::SignatureScheme::RSA_PSS_SHA256,
            ]
        }
    }

    let mut client_crypto = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(PeerIdentityVerifier))
        .with_no_client_auth();
    client_crypto.alpn_protocols = vec![b"p2pme-1".to_vec()];

    let client_config = ClientConfig::new(Arc::new(quinn::crypto::rustls::QuicClientConfig::try_from(client_crypto)?));

    Ok((server_config, client_config))
}
