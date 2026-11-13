use crate::storage::{FileManifest, Tombstone, TrackedFile};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum WireMessage {
    Hello {
        node_id: String,
        folder_id: String,
        auth_token: String,
    },
    HelloAck {
        accepted: bool,
        reason: Option<String>,
    },
    RequestManifest {
        folder_id: String,
    },
    ManifestResponse {
        folder_id: String,
        files: Vec<TrackedFile>,
        tombstones: Vec<Tombstone>,
    },
    RequestChunkPlan {
        folder_id: String,
        relative_path: String,
    },
    ChunkPlanResponse {
        manifest: Option<FileManifest>,
    },
    RequestChunk {
        folder_id: String,
        relative_path: String,
        chunk_index: u32,
    },
    ChunkData {
        folder_id: String,
        relative_path: String,
        chunk_index: u32,
        data: Vec<u8>,
    },
    NotifyTombstone {
        tombstone: Tombstone,
    },
    // Ephemeral One-Time Quick Drop Protocol
    DropHello {
        drop_id: String,
        auth_token: String,
        pin_code: String,
    },
    DropHelloAck {
        accepted: bool,
        files: Vec<DropFileInfo>,
        reason: Option<String>,
    },
    DropRequestChunk {
        drop_id: String,
        file_index: u32,
        chunk_index: u32,
    },
    DropChunkData {
        drop_id: String,
        file_index: u32,
        chunk_index: u32,
        data: Vec<u8>,
    },
    DropComplete {
        drop_id: String,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DropFileInfo {
    pub name: String,
    pub size: u64,
    pub blake3_hash: String,
    pub chunk_count: u32,
}

impl WireMessage {
    pub fn encode(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec(self)
    }

    pub fn decode(bytes: &[u8]) -> Result<Self, serde_json::Error> {
        serde_json::from_slice(bytes)
    }
}

