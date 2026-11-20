use anyhow::{anyhow, Result};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};
use std::time::Duration;
use tokio::net::UdpSocket;
use tracing::{debug, warn};

const STUN_MAGIC_COOKIE: u32 = 0x2112A442;
const BINDING_REQUEST: u16 = 0x0001;
const BINDING_RESPONSE: u16 = 0x0101;
const ATTR_MAPPED_ADDRESS: u16 = 0x0001;
const ATTR_XOR_MAPPED_ADDRESS: u16 = 0x0020;

const DEFAULT_STUN_SERVERS: &[&str] = &[
    "stun.l.google.com:19302",
    "stun1.l.google.com:19302",
    "stun2.l.google.com:19302",
];

/// Query a public STUN server to discover this node's external public WAN address
pub async fn discover_public_address(local_port: u16) -> Option<SocketAddr> {
    for &server in DEFAULT_STUN_SERVERS {
        match tokio::time::timeout(
            Duration::from_millis(1500),
            query_stun_server(server, local_port),
        )
        .await
        {
            Ok(Ok(addr)) => {
                debug!("STUN discovery success via {}: {}", server, addr);
                return Some(addr);
            }
            Ok(Err(e)) => {
                debug!("STUN query to {} failed: {}", server, e);
            }
            Err(_) => {
                debug!("STUN query to {} timed out", server);
            }
        }
    }
    warn!("All STUN discovery attempts failed or timed out");
    None
}

async fn query_stun_server(server_host_port: &str, target_port: u16) -> Result<SocketAddr> {
    // Resolve STUN server address
    let mut server_addrs = tokio::net::lookup_host(server_host_port).await?;
    let server_addr = server_addrs
        .next()
        .ok_or_else(|| anyhow!("Failed to resolve STUN server {}", server_host_port))?;

    // Bind ephemeral UDP socket for probing
    let socket = UdpSocket::bind("0.0.0.0:0").await?;

    // Build STUN Binding Request header (20 bytes)
    let mut req = [0u8; 20];
    req[0..2].copy_from_slice(&BINDING_REQUEST.to_be_bytes());
    req[2..4].copy_from_slice(&0u16.to_be_bytes()); // Length: 0
    req[4..8].copy_from_slice(&STUN_MAGIC_COOKIE.to_be_bytes());

    let tx_id = rand::random::<[u8; 12]>();
    req[8..20].copy_from_slice(&tx_id);

    socket.send_to(&req, server_addr).await?;

    let mut buf = [0u8; 512];
    let (len, _) = socket.recv_from(&mut buf).await?;
    if len < 20 {
        return Err(anyhow!("STUN response too short ({} bytes)", len));
    }

    let resp_type = u16::from_be_bytes([buf[0], buf[1]]);
    if resp_type != BINDING_RESPONSE {
        return Err(anyhow!("Unexpected STUN response type: 0x{:04x}", resp_type));
    }

    let cookie = u32::from_be_bytes([buf[4], buf[5], buf[6], buf[7]]);
    if cookie != STUN_MAGIC_COOKIE {
        return Err(anyhow!("STUN magic cookie mismatch"));
    }

    if &buf[8..20] != &tx_id {
        return Err(anyhow!("STUN transaction ID mismatch"));
    }

    let msg_len = u16::from_be_bytes([buf[2], buf[3]]) as usize;
    let end = 20 + msg_len.min(len - 20);

    let mut offset = 20;
    while offset + 4 <= end {
        let attr_type = u16::from_be_bytes([buf[offset], buf[offset + 1]]);
        let attr_len = u16::from_be_bytes([buf[offset + 2], buf[offset + 3]]) as usize;
        offset += 4;

        if offset + attr_len > end {
            break;
        }

        let attr_val = &buf[offset..offset + attr_len];

        if attr_type == ATTR_XOR_MAPPED_ADDRESS && attr_len >= 8 {
            let family = attr_val[1];
            if family == 0x01 {
                // IPv4
                let raw_port = u16::from_be_bytes([attr_val[2], attr_val[3]]);
                let xor_port = raw_port ^ ((STUN_MAGIC_COOKIE >> 16) as u16);

                let raw_ip = u32::from_be_bytes([attr_val[4], attr_val[5], attr_val[6], attr_val[7]]);
                let xor_ip = raw_ip ^ STUN_MAGIC_COOKIE;
                let ip = Ipv4Addr::from(xor_ip);

                // Use the port if target_port is 0, otherwise prioritize the actual service port
                let mapped_port = if target_port > 0 { target_port } else { xor_port };
                return Ok(SocketAddr::V4(SocketAddrV4::new(ip, mapped_port)));
            }
        } else if attr_type == ATTR_MAPPED_ADDRESS && attr_len >= 8 {
            let family = attr_val[1];
            if family == 0x01 {
                // IPv4
                let port = u16::from_be_bytes([attr_val[2], attr_val[3]]);
                let ip = Ipv4Addr::new(attr_val[4], attr_val[5], attr_val[6], attr_val[7]);
                let mapped_port = if target_port > 0 { target_port } else { port };
                return Ok(SocketAddr::V4(SocketAddrV4::new(ip, mapped_port)));
            }
        }

        // STUN attributes are padded to 4-byte boundaries
        let padded_len = (attr_len + 3) & !3;
        offset += padded_len;
    }

    Err(anyhow!("No mapped address attribute found in STUN response"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_stun_discovery_live() {
        // Query public STUN server with a dummy port
        if let Some(addr) = discover_public_address(45454).await {
            assert_eq!(addr.port(), 45454);
            assert!(!addr.ip().is_loopback());
            println!("STUN discovered public address: {}", addr);
        } else {
            println!("Skipping STUN assertion (offline or restricted UDP network)");
        }
    }
}
