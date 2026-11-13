use p2pme_core::net::protocol::WireMessage;
use p2pme_core::net::QuicTransport;
use p2pme_core::P2PNode;
use std::fs::File;
use std::io::Write;
use tempfile::tempdir;

#[tokio::test]
async fn test_secure_quick_drop_and_pin_verification() {
    let send_dir = tempdir().unwrap();
    let recv_dir = tempdir().unwrap();
    let node_a_db = tempdir().unwrap();
    let node_b_db = tempdir().unwrap();

    // Create test files to send
    let doc_path = send_dir.path().join("secure_contract.pdf");
    let mut doc_file = File::create(&doc_path).unwrap();
    let doc_data = b"CONFIDENTIAL AGREEMENT: One-time peer-to-peer drop without persistence.";
    doc_file.write_all(doc_data).unwrap();
    let doc_hash = blake3::hash(doc_data).to_hex().to_string();

    let img_path = send_dir.path().join("test_image.png");
    let mut img_file = File::create(&img_path).unwrap();
    let img_data = vec![0xABu8; 1024 * 512]; // 512 KB (multiple 256KB chunks)
    img_file.write_all(&img_data).unwrap();
    let img_hash = blake3::hash(&img_data).to_hex().to_string();

    // Initialize two distinct P2P nodes
    let node_a = P2PNode::new(node_a_db.path(), 0).await.unwrap();
    let node_b = P2PNode::new(node_b_db.path(), 0).await.unwrap();

    // Node A creates a Quick Drop session
    let drop_ticket = node_a
        .create_drop(vec![doc_path.clone(), img_path.clone()])
        .await
        .unwrap();

    assert_eq!(drop_ticket.files.len(), 2);
    assert_eq!(drop_ticket.pin_code.len(), 6);
    println!(
        "Created Quick Drop: ID={} PIN={}",
        drop_ticket.drop_id, drop_ticket.pin_code
    );

    // Node B receives the drop using the ticket and the 6-digit PIN
    let stats = node_b
        .receive_drop(&drop_ticket, Some(&drop_ticket.pin_code), recv_dir.path())
        .await
        .unwrap();

    assert_eq!(stats.files_transferred, 2);
    assert_eq!(stats.bytes_transferred, (doc_data.len() + img_data.len()) as u64);

    // Verify downloaded files on Node B disk
    let recv_doc = recv_dir.path().join("secure_contract.pdf");
    let recv_img = recv_dir.path().join("test_image.png");

    assert!(recv_doc.exists());
    assert!(recv_img.exists());

    let recv_doc_bytes = std::fs::read(&recv_doc).unwrap();
    let recv_img_bytes = std::fs::read(&recv_img).unwrap();

    assert_eq!(blake3::hash(&recv_doc_bytes).to_hex().to_string(), doc_hash);
    assert_eq!(blake3::hash(&recv_img_bytes).to_hex().to_string(), img_hash);

    // Verify sender's ephemeral session has self-destructed upon completion
    let drops = node_a.drop_manager.drops.lock().await;
    assert!(
        drops.get(&drop_ticket.drop_id).is_none(),
        "Active drop session must self-destruct immediately after receipt"
    );
}

#[tokio::test]
async fn test_drop_brute_force_lockout() {
    let send_dir = tempdir().unwrap();
    let node_a_db = tempdir().unwrap();

    let secret_path = send_dir.path().join("secret.txt");
    let mut f = File::create(&secret_path).unwrap();
    f.write_all(b"SUPER_SECRET").unwrap();

    let node_a = P2PNode::new(node_a_db.path(), 0).await.unwrap();
    let drop_ticket = node_a
        .create_drop(vec![secret_path])
        .await
        .unwrap();

    let peer_addr = drop_ticket.direct_addresses[0];
    let client_transport = QuicTransport::bind(0, "attacker_node".to_string()).await.unwrap();
    let conn = client_transport.connect(peer_addr, &drop_ticket.node_id).await.unwrap();

    // Attempt 1: Invalid PIN
    let req1 = WireMessage::DropHello {
        drop_id: drop_ticket.drop_id.clone(),
        auth_token: "invalid_tok".to_string(),
        pin_code: "000000".to_string(),
    };
    let resp1 = QuicTransport::send_rpc(&conn, &req1).await.unwrap();
    match resp1 {
        WireMessage::DropHelloAck { accepted, reason, .. } => {
            assert!(!accepted);
            assert_eq!(reason.as_deref(), Some("Invalid PIN or auth token"));
        }
        _ => panic!("Expected DropHelloAck"),
    }

    // Attempt 2: Invalid PIN
    let req2 = WireMessage::DropHello {
        drop_id: drop_ticket.drop_id.clone(),
        auth_token: "invalid_tok".to_string(),
        pin_code: "111111".to_string(),
    };
    let resp2 = QuicTransport::send_rpc(&conn, &req2).await.unwrap();
    match resp2 {
        WireMessage::DropHelloAck { accepted, reason, .. } => {
            assert!(!accepted);
            assert_eq!(reason.as_deref(), Some("Invalid PIN or auth token"));
        }
        _ => panic!("Expected DropHelloAck"),
    }

    // Attempt 3: Invalid PIN - triggers lockout and self-destruct
    let req3 = WireMessage::DropHello {
        drop_id: drop_ticket.drop_id.clone(),
        auth_token: "invalid_tok".to_string(),
        pin_code: "222222".to_string(),
    };
    let resp3 = QuicTransport::send_rpc(&conn, &req3).await.unwrap();
    match resp3 {
        WireMessage::DropHelloAck { accepted, reason, .. } => {
            assert!(!accepted);
            assert_eq!(
                reason.as_deref(),
                Some("Too many failed attempts. Session destroyed.")
            );
        }
        _ => panic!("Expected DropHelloAck lockout"),
    }

    // Attempt 4: Even with the CORRECT PIN, session no longer exists!
    let req4 = WireMessage::DropHello {
        drop_id: drop_ticket.drop_id.clone(),
        auth_token: drop_ticket.auth_token.clone(),
        pin_code: drop_ticket.pin_code.clone(),
    };
    let resp4 = QuicTransport::send_rpc(&conn, &req4).await.unwrap();
    match resp4 {
        WireMessage::DropHelloAck { accepted, reason, .. } => {
            assert!(!accepted);
            assert_eq!(
                reason.as_deref(),
                Some("Quick Drop session not found or already completed")
            );
        }
        _ => panic!("Expected DropHelloAck not found"),
    }
}

#[tokio::test]
async fn test_big_file_transfer_speed_and_throughput() {
    let send_dir = tempdir().unwrap();
    let recv_dir = tempdir().unwrap();
    let node_a_db = tempdir().unwrap();
    let node_b_db = tempdir().unwrap();

    // Create 16 MB big video test file (64 chunks of 256KB)
    let file_size_bytes: usize = 16 * 1024 * 1024;
    let big_path = send_dir.path().join("4k_vacation_video.mp4");
    let mut big_file = File::create(&big_path).unwrap();
    let big_data = vec![0x37u8; file_size_bytes];
    big_file.write_all(&big_data).unwrap();

    let node_a = P2PNode::new(node_a_db.path(), 0).await.unwrap();
    let node_b = P2PNode::new(node_b_db.path(), 0).await.unwrap();

    let start_create = std::time::Instant::now();
    let drop_ticket = node_a.create_drop(vec![big_path.clone()]).await.unwrap();
    let create_time = start_create.elapsed();

    let start_transfer = std::time::Instant::now();
    let stats = node_b
        .receive_drop(&drop_ticket, Some(&drop_ticket.pin_code), recv_dir.path())
        .await
        .unwrap();
    let transfer_time = start_transfer.elapsed();

    let mb = (file_size_bytes as f64) / (1024.0 * 1024.0);
    let speed_mb_s = mb / transfer_time.as_secs_f64();

    println!("\n=== BIG FILE THROUGHPUT BENCHMARK ===");
    println!("Payload Size:        {:.2} MB ({} bytes)", mb, file_size_bytes);
    println!("BLAKE3 Chunking:     {:.2?}", create_time);
    println!("QUIC Transfer Time:  {:.2?}", transfer_time);
    println!("Throughput Speed:    {:.2} MB/s", speed_mb_s);
    println!("Chunks Verified:     {} chunks (256 KB each)", stats.bytes_transferred / (256 * 1024));
    println!("======================================\n");

    assert_eq!(stats.files_transferred, 1);
    assert_eq!(stats.bytes_transferred, file_size_bytes as u64);

    let recv_big = recv_dir.path().join("4k_vacation_video.mp4");
    assert!(recv_big.exists());
    assert_eq!(std::fs::metadata(recv_big).unwrap().len(), file_size_bytes as u64);
}

