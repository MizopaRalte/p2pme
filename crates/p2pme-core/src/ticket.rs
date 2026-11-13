use serde::{Deserialize, Serialize};
use std::net::SocketAddr;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum AccessMode {
    ReadWrite,
    ReadOnly,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Default)]
pub enum SyncMode {
    #[default]
    TwoWay,        // Standard bi-directional replication (additions, modifications, and deletions replicate)
    CameraBackup,  // Phone sends photos/files. Peers cannot modify or delete sender files.
    Archive,       // Storage-saver: Receiver permanently retains files even if sender deletes them to free space.
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingTicket {
    pub version: u32,
    pub node_id: String,
    pub folder_id: String,
    pub access: AccessMode,
    #[serde(default)]
    pub sync_mode: SyncMode,
    pub direct_addresses: Vec<SocketAddr>,
    pub auth_token: String,
    pub expires_at: u64,
}

impl PairingTicket {
    pub fn new(
        node_id: String,
        folder_id: String,
        access: AccessMode,
        sync_mode: SyncMode,
        direct_addresses: Vec<SocketAddr>,
        auth_token: String,
        ttl_seconds: u64,
    ) -> Self {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        Self {
            version: 1,
            node_id,
            folder_id,
            access,
            sync_mode,
            direct_addresses,
            auth_token,
            expires_at: now + ttl_seconds,
        }
    }

    pub fn to_string_payload(&self) -> Result<String, serde_json::Error> {
        let json = serde_json::to_string(self)?;
        Ok(data_encoding::BASE64URL_NOPAD.encode(json.as_bytes()))
    }

    pub fn from_string_payload(payload: &str) -> Result<Self, anyhow::Error> {
        let decoded_bytes = data_encoding::BASE64URL_NOPAD
            .decode(payload.as_bytes())
            .map_err(|e| anyhow::anyhow!("Invalid base64url ticket: {}", e))?;
        let ticket: Self = serde_json::from_slice(&decoded_bytes)?;
        
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        if ticket.expires_at > 0 && now > ticket.expires_at {
            anyhow::bail!("Pairing ticket has expired");
        }

        Ok(ticket)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ticket_roundtrip() {
        let addr: SocketAddr = "192.168.1.50:42424".parse().unwrap();
        let ticket = PairingTicket::new(
            "node12345".to_string(),
            "folder-abc".to_string(),
            AccessMode::ReadWrite,
            SyncMode::Archive,
            vec![addr],
            "secret_token_123".to_string(),
            3600,
        );

        let encoded = ticket.to_string_payload().unwrap();
        let decoded = PairingTicket::from_string_payload(&encoded).unwrap();

        assert_eq!(ticket.node_id, decoded.node_id);
        assert_eq!(ticket.folder_id, decoded.folder_id);
        assert_eq!(ticket.access, decoded.access);
        assert_eq!(ticket.sync_mode, decoded.sync_mode);
        assert_eq!(ticket.direct_addresses, decoded.direct_addresses);
    }
}

