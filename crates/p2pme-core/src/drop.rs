use crate::net::protocol::{DropFileInfo, WireMessage};
use crate::net::QuicTransport;
use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::io::{Read, Seek, SeekFrom};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::{info, warn};

pub const DROP_CHUNK_SIZE: usize = 1024 * 1024; // 1 MB high-speed streaming chunk size
pub const MAX_FAILED_ATTEMPTS: u32 = 3;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DropTicket {
    pub version: u32,
    pub drop_id: String,
    pub pin_code: String,
    pub auth_token: String,
    pub node_id: String,
    pub direct_addresses: Vec<SocketAddr>,
    pub files: Vec<DropFileInfo>,
    pub expires_at: u64,
}

impl DropTicket {
    pub fn to_string_payload(&self) -> Result<String, serde_json::Error> {
        let json = serde_json::to_string(self)?;
        Ok(data_encoding::BASE64URL_NOPAD.encode(json.as_bytes()))
    }

    pub fn from_string_payload(payload: &str) -> Result<Self> {
        let decoded = data_encoding::BASE64URL_NOPAD
            .decode(payload.as_bytes())
            .map_err(|e| anyhow!("Invalid base64url drop ticket: {}", e))?;
        let ticket: Self = serde_json::from_slice(&decoded)?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        if ticket.expires_at > 0 && now > ticket.expires_at {
            bail!("Drop ticket has expired");
        }
        Ok(ticket)
    }
}

pub struct ActiveDrop {
    pub drop_id: String,
    pub pin_code: String,
    pub auth_token: String,
    pub local_files: Vec<PathBuf>,
    pub file_infos: Vec<DropFileInfo>,
    pub failed_attempts: AtomicU32,
    pub expires_at: u64,
}

#[derive(Clone, Default)]
pub struct DropManager {
    pub drops: Arc<Mutex<HashMap<String, Arc<ActiveDrop>>>>,
}

impl DropManager {
    pub fn new() -> Self {
        Self {
            drops: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    /// Create an ephemeral single-use drop session for a set of files
    pub async fn create_drop(
        &self,
        file_paths: Vec<PathBuf>,
        direct_addresses: Vec<SocketAddr>,
        node_id: &str,
    ) -> Result<DropTicket> {
        let mut file_infos = Vec::new();
        let mut valid_paths = Vec::new();

        for path in file_paths {
            if !path.is_file() {
                continue;
            }
            let name = path
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "file".to_string());
            let size = std::fs::metadata(&path)?.len();

            // Compute BLAKE3 content hash
            let mut file = std::fs::File::open(&path)?;
            let mut hasher = blake3::Hasher::new();
            let mut buffer = vec![0u8; 64 * 1024];
            loop {
                let n = file.read(&mut buffer)?;
                if n == 0 {
                    break;
                }
                hasher.update(&buffer[..n]);
            }
            let blake3_hash = hasher.finalize().to_hex().to_string();

            let chunk_count = if size == 0 {
                1
            } else {
                ((size + DROP_CHUNK_SIZE as u64 - 1) / DROP_CHUNK_SIZE as u64) as u32
            };

            file_infos.push(DropFileInfo {
                name,
                size,
                blake3_hash,
                chunk_count,
            });
            valid_paths.push(path);
        }

        if valid_paths.is_empty() {
            bail!("No valid files provided for quick drop");
        }

        let drop_id = format!(
            "drop_{}",
            &blake3::hash(&rand::random::<[u8; 16]>()).to_hex()[..12]
        );
        let pin_code = format!("{:06}", rand::random::<u32>() % 1_000_000);
        let auth_token = format!(
            "tok_{}",
            &blake3::hash(&rand::random::<[u8; 16]>()).to_hex()[..16]
        );
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let expires_at = now + 600; // 10 minutes TTL

        let active_drop = Arc::new(ActiveDrop {
            drop_id: drop_id.clone(),
            pin_code: pin_code.clone(),
            auth_token: auth_token.clone(),
            local_files: valid_paths,
            file_infos: file_infos.clone(),
            failed_attempts: AtomicU32::new(0),
            expires_at,
        });

        {
            let mut map = self.drops.lock().await;
            map.insert(drop_id.clone(), active_drop);
        }

        info!("Created Quick Drop: ID={} PIN={}", drop_id, pin_code);

        Ok(DropTicket {
            version: 1,
            drop_id,
            pin_code,
            auth_token,
            node_id: node_id.to_string(),
            direct_addresses,
            files: file_infos,
            expires_at,
        })
    }

    /// Handle server-side RPC for incoming drop connections
    pub async fn handle_drop_rpc(&self, request: WireMessage) -> Result<WireMessage> {
        match request {
            WireMessage::DropHello {
                drop_id,
                auth_token,
                pin_code,
            } => {
                let drop_opt = {
                    let map = self.drops.lock().await;
                    map.get(&drop_id).cloned()
                };

                let drop = match drop_opt {
                    Some(d) => d,
                    None => {
                        return Ok(WireMessage::DropHelloAck {
                            accepted: false,
                            files: vec![],
                            reason: Some("Quick Drop session not found or already completed".to_string()),
                        });
                    }
                };

                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs();
                if now > drop.expires_at {
                    let mut map = self.drops.lock().await;
                    map.remove(&drop_id);
                    return Ok(WireMessage::DropHelloAck {
                        accepted: false,
                        files: vec![],
                        reason: Some("Quick Drop session has expired".to_string()),
                    });
                }

                // Verify cryptographic token OR 6-digit PIN
                let token_valid = auth_token == drop.auth_token;
                let pin_valid = pin_code == drop.pin_code;

                if !token_valid && !pin_valid {
                    let attempts = drop.failed_attempts.fetch_add(1, Ordering::SeqCst) + 1;
                    warn!(
                        "Quick Drop authentication failed for {}: attempt {}/{}",
                        drop_id, attempts, MAX_FAILED_ATTEMPTS
                    );
                    if attempts >= MAX_FAILED_ATTEMPTS {
                        // Rate limit exceeded: Self-destruct session immediately
                        let mut map = self.drops.lock().await;
                        map.remove(&drop_id);
                        return Ok(WireMessage::DropHelloAck {
                            accepted: false,
                            files: vec![],
                            reason: Some("Too many failed attempts. Session destroyed.".to_string()),
                        });
                    }
                    return Ok(WireMessage::DropHelloAck {
                        accepted: false,
                        files: vec![],
                        reason: Some("Invalid PIN or auth token".to_string()),
                    });
                }

                info!("Quick Drop peer authenticated: ID={}", drop_id);
                Ok(WireMessage::DropHelloAck {
                    accepted: true,
                    files: drop.file_infos.clone(),
                    reason: None,
                })
            }

            WireMessage::DropRequestChunk {
                drop_id,
                file_index,
                chunk_index,
            } => {
                let drop_opt = {
                    let map = self.drops.lock().await;
                    map.get(&drop_id).cloned()
                };

                let drop = match drop_opt {
                    Some(d) => d,
                    None => bail!("Quick drop session not found"),
                };

                let path = match drop.local_files.get(file_index as usize) {
                    Some(p) => p,
                    None => bail!("File index out of bounds"),
                };

                let mut file = std::fs::File::open(path)?;
                let offset = chunk_index as u64 * DROP_CHUNK_SIZE as u64;
                file.seek(SeekFrom::Start(offset))?;

                let mut buffer = vec![0u8; DROP_CHUNK_SIZE];
                let bytes_read = file.read(&mut buffer)?;
                buffer.truncate(bytes_read);

                Ok(WireMessage::DropChunkData {
                    drop_id,
                    file_index,
                    chunk_index,
                    data: buffer,
                })
            }

            WireMessage::DropComplete { drop_id } => {
                info!("Quick Drop completed by recipient: self-destructing ID={}", drop_id);
                let mut map = self.drops.lock().await;
                map.remove(&drop_id);
                Ok(WireMessage::HelloAck {
                    accepted: true,
                    reason: None,
                })
            }

            _ => bail!("Unexpected drop wire message"),
        }
    }

    /// Client-side receive function: connect to sender and download files safely
    pub async fn receive_drop<P: AsRef<Path>>(
        transport: &QuicTransport,
        ticket: &DropTicket,
        pin: Option<&str>,
        target_dir: P,
    ) -> Result<DropReceiveStats> {
        let dest = target_dir.as_ref();
        std::fs::create_dir_all(dest)?;

        let auth_token = ticket.auth_token.clone();
        let pin_code = pin.unwrap_or(&ticket.pin_code).to_string();

        let mut connection = None;
        let mut last_err = None;

        for &addr in &ticket.direct_addresses {
            info!("Attempting connection for Quick Drop to {}", addr);
            match transport.connect(addr, &ticket.node_id).await {
                Ok(conn) => {
                    connection = Some(conn);
                    break;
                }
                Err(e) => {
                    last_err = Some(e);
                }
            }
        }

        let conn = connection
            .ok_or_else(|| last_err.unwrap_or_else(|| anyhow!("No reachable direct address")))?;

        // Handshake
        let hello = WireMessage::DropHello {
            drop_id: ticket.drop_id.clone(),
            auth_token,
            pin_code,
        };
        let ack = QuicTransport::send_rpc(&conn, &hello).await?;
        let files = match ack {
            WireMessage::DropHelloAck {
                accepted: true,
                files,
                ..
            } => files,
            WireMessage::DropHelloAck {
                accepted: false,
                reason,
                ..
            } => {
                bail!("Quick Drop rejected: {:?}", reason);
            }
            _ => bail!("Unexpected response to DropHello"),
        };

        let mut stats = DropReceiveStats::default();

        for (file_idx, file_info) in files.iter().enumerate() {
            // Path traversal protection: sanitize filename
            let safe_name = Path::new(&file_info.name)
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| format!("file_{}", file_idx));

            let out_path = resolve_unique_file_path(dest, &safe_name);
            let mut out_file = std::fs::File::create(&out_path)?;

            let mut file_hasher = blake3::Hasher::new();

            for chunk_idx in 0..file_info.chunk_count {
                let req = WireMessage::DropRequestChunk {
                    drop_id: ticket.drop_id.clone(),
                    file_index: file_idx as u32,
                    chunk_index: chunk_idx,
                };
                let resp = QuicTransport::send_rpc(&conn, &req).await?;
                match resp {
                    WireMessage::DropChunkData { data, .. } => {
                        use std::io::Write;
                        out_file.write_all(&data)?;
                        file_hasher.update(&data);
                        stats.bytes_transferred += data.len() as u64;
                    }
                    _ => bail!("Failed to download chunk {} for {}", chunk_idx, safe_name),
                }
            }

            // Cryptographic verification
            let downloaded_hash = file_hasher.finalize().to_hex().to_string();
            if downloaded_hash != file_info.blake3_hash {
                std::fs::remove_file(&out_path).ok();
                bail!(
                    "Integrity check failed for {}: hash mismatch",
                    safe_name
                );
            }

            stats.files_transferred += 1;
            info!("Received and verified: {} ({} bytes)", safe_name, file_info.size);
        }

        // Notify completion so sender immediately destroys ephemeral state
        let complete = WireMessage::DropComplete {
            drop_id: ticket.drop_id.clone(),
        };
        QuicTransport::send_rpc(&conn, &complete).await.ok();

        Ok(stats)
    }
}

#[derive(Debug, Default, Clone)]
pub struct DropReceiveStats {
    pub files_transferred: usize,
    pub bytes_transferred: u64,
}


pub fn resolve_unique_file_path(dest: &Path, original_name: &str) -> PathBuf {
    let candidate = dest.join(original_name);
    if !candidate.exists() {
        return candidate;
    }

    let p = Path::new(original_name);
    let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or(original_name);
    let ext = p.extension().and_then(|s| s.to_str());

    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let candidate_name = match ext {
        Some(e) => format!("{}_{}.{}", stem, now_secs, e),
        None => format!("{}_{}", stem, now_secs),
    };
    let mut candidate = dest.join(&candidate_name);

    let mut counter = 1;
    while candidate.exists() {
        let candidate_name = match ext {
            Some(e) => format!("{}_{}_{}.{}", stem, now_secs, counter, e),
            None => format!("{}_{}_{}", stem, now_secs, counter),
        };
        candidate = dest.join(&candidate_name);
        counter += 1;
    }

    candidate
}
