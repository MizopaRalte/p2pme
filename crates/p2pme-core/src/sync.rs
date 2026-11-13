use crate::net::protocol::WireMessage;
use crate::net::QuicTransport;
use crate::storage::{Chunker, StateCatalog};
use crate::ticket::SyncMode;
use anyhow::Result;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing::info;

pub struct SyncSession {
    pub folder_id: String,
    pub base_dir: PathBuf,
    pub catalog: Arc<Mutex<StateCatalog>>,
    pub sync_mode: SyncMode,
}

impl SyncSession {
    pub fn new<P: AsRef<Path>>(
        folder_id: String,
        base_dir: P,
        catalog: Arc<Mutex<StateCatalog>>,
        sync_mode: SyncMode,
    ) -> Self {
        Self {
            folder_id,
            base_dir: base_dir.as_ref().to_path_buf(),
            catalog,
            sync_mode,
        }
    }

    /// Handle an incoming RPC stream on the server side
    pub async fn handle_rpc(
        &self,
        request: WireMessage,
        expected_token: &str,
    ) -> Result<WireMessage> {
        match request {
            WireMessage::Hello {
                node_id,
                folder_id,
                auth_token,
            } => {
                if folder_id != self.folder_id {
                    return Ok(WireMessage::HelloAck {
                        accepted: false,
                        reason: Some("Folder ID mismatch".to_string()),
                    });
                }
                if auth_token != expected_token {
                    return Ok(WireMessage::HelloAck {
                        accepted: false,
                        reason: Some("Invalid authentication token".to_string()),
                    });
                }
                info!("Peer {} authenticated for folder {}", node_id, folder_id);
                Ok(WireMessage::HelloAck {
                    accepted: true,
                    reason: None,
                })
            }

            WireMessage::RequestManifest { folder_id } => {
                let mut cat = self.catalog.lock().await;
                cat.scan_directory(&folder_id, &self.base_dir)?;
                let files = cat.list_files(&folder_id)?;
                let tombstones = cat.list_tombstones(&folder_id)?;
                Ok(WireMessage::ManifestResponse {
                    folder_id,
                    files,
                    tombstones,
                })
            }

            WireMessage::RequestChunkPlan {
                folder_id: _,
                relative_path,
            } => {
                let manifest = Chunker::create_manifest(
                    &self.base_dir,
                    &relative_path,
                    crate::storage::chunker::DEFAULT_CHUNK_SIZE,
                )
                .ok();
                Ok(WireMessage::ChunkPlanResponse { manifest })
            }

            WireMessage::RequestChunk {
                folder_id: _,
                relative_path,
                chunk_index,
            } => {
                let manifest = Chunker::create_manifest(
                    &self.base_dir,
                    &relative_path,
                    crate::storage::chunker::DEFAULT_CHUNK_SIZE,
                )?;
                if let Some(chunk) = manifest.chunks.get(chunk_index as usize) {
                    let full_path = self.base_dir.join(&relative_path);
                    let data = Chunker::read_chunk(&full_path, chunk)?;
                    Ok(WireMessage::ChunkData {
                        folder_id: self.folder_id.clone(),
                        relative_path,
                        chunk_index,
                        data,
                    })
                } else {
                    anyhow::bail!("Requested chunk index out of bounds");
                }
            }

            WireMessage::NotifyTombstone { tombstone } => {
                if self.sync_mode != SyncMode::Archive {
                    let mut cat = self.catalog.lock().await;
                    cat.apply_remote_tombstone(&self.base_dir, &tombstone)?;
                } else {
                    info!("Archive mode active: Remote deletion tombstone ignored");
                }
                Ok(WireMessage::HelloAck {
                    accepted: true,
                    reason: None,
                })
            }

            _ => anyhow::bail!("Unexpected request type"),
        }
    }

    /// Execute a synchronization pull/reconciliation with a remote peer
    pub async fn pull_from_peer(
        &self,
        connection: &quinn::Connection,
        local_node_id: &str,
        auth_token: &str,
    ) -> Result<SyncStats> {
        // 1. Handshake
        let hello = WireMessage::Hello {
            node_id: local_node_id.to_string(),
            folder_id: self.folder_id.clone(),
            auth_token: auth_token.to_string(),
        };
        let ack = QuicTransport::send_rpc(connection, &hello).await?;
        match ack {
            WireMessage::HelloAck { accepted: true, .. } => {}
            WireMessage::HelloAck { accepted: false, reason } => {
                anyhow::bail!("Handshake rejected: {:?}", reason);
            }
            _ => anyhow::bail!("Unexpected response to Hello"),
        }

        // 2. Scan local folder first to ensure up to date catalog
        {
            let mut cat = self.catalog.lock().await;
            cat.scan_directory(&self.folder_id, &self.base_dir)?;
        }

        // 3. Request remote manifest
        let manifest_req = WireMessage::RequestManifest {
            folder_id: self.folder_id.clone(),
        };
        let resp = QuicTransport::send_rpc(connection, &manifest_req).await?;
        let (remote_files, remote_tombstones) = match resp {
            WireMessage::ManifestResponse {
                files, tombstones, ..
            } => (files, tombstones),
            _ => anyhow::bail!("Unexpected response to RequestManifest"),
        };

        let mut stats = SyncStats::default();

        // 4. Apply remote tombstones (ignored in Archive mode to protect local storage)
        if self.sync_mode != SyncMode::Archive {
            let mut cat = self.catalog.lock().await;
            for tomb in remote_tombstones {
                cat.apply_remote_tombstone(&self.base_dir, &tomb)?;
                stats.files_deleted += 1;
            }
        } else {
            info!(
                "Archive mode active: Skipping {} remote tombstones to retain local files",
                remote_tombstones.len()
            );
        }

        // 5. Reconcile files
        let local_files = {
            let cat = self.catalog.lock().await;
            cat.list_files(&self.folder_id)?
        };

        for r_file in remote_files {
            if r_file.is_directory {
                std::fs::create_dir_all(self.base_dir.join(&r_file.relative_path))?;
                continue;
            }

            let needs_download = match local_files.iter().find(|l| l.relative_path == r_file.relative_path) {
                Some(local) => local.content_hash != r_file.content_hash,
                None => true,
            };

            if needs_download {
                info!("Downloading {}...", r_file.relative_path);
                // Request chunk plan
                let plan_req = WireMessage::RequestChunkPlan {
                    folder_id: self.folder_id.clone(),
                    relative_path: r_file.relative_path.clone(),
                };
                let plan_resp = QuicTransport::send_rpc(connection, &plan_req).await?;
                let file_manifest = match plan_resp {
                    WireMessage::ChunkPlanResponse { manifest: Some(m) } => m,
                    _ => anyhow::bail!("Failed to get chunk plan for {}", r_file.relative_path),
                };

                let target_path = self.base_dir.join(&r_file.relative_path);

                // Fetch each chunk
                for chunk in &file_manifest.chunks {
                    let chunk_req = WireMessage::RequestChunk {
                        folder_id: self.folder_id.clone(),
                        relative_path: r_file.relative_path.clone(),
                        chunk_index: chunk.index,
                    };
                    let chunk_resp = QuicTransport::send_rpc(connection, &chunk_req).await?;
                    match chunk_resp {
                        WireMessage::ChunkData { data, .. } => {
                            Chunker::write_chunk(&target_path, chunk, &data)?;
                            stats.bytes_transferred += data.len() as u64;
                        }
                        _ => anyhow::bail!("Failed to download chunk {}", chunk.index),
                    }
                }

                stats.files_transferred += 1;
            }
        }

        // Update local catalog after transfer
        {
            let mut cat = self.catalog.lock().await;
            cat.scan_directory(&self.folder_id, &self.base_dir)?;
        }

        Ok(stats)
    }
}

#[derive(Debug, Default, Clone)]
pub struct SyncStats {
    pub files_transferred: usize,
    pub files_deleted: usize,
    pub bytes_transferred: u64,
}
