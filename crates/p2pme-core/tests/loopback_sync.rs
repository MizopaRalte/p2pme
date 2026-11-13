use p2pme_core::ticket::{AccessMode, SyncMode};
use p2pme_core::P2PNode;
use tempfile::tempdir;

#[tokio::test]
async fn test_full_loopback_replication_and_tombstones() {
    let source_dir = tempdir().unwrap();
    let dest_dir = tempdir().unwrap();
    let db1_dir = tempdir().unwrap();
    let db2_dir = tempdir().unwrap();

    // 1. Create files in source directory
    let file_a = source_dir.path().join("document.txt");
    std::fs::write(&file_a, b"High performance P2P replication test").unwrap();

    let sub_dir = source_dir.path().join("subfolder");
    std::fs::create_dir_all(&sub_dir).unwrap();
    let file_b = sub_dir.join("photo.dat");
    let large_payload: Vec<u8> = (0..(500 * 1024)).map(|i| (i % 255) as u8).collect();
    std::fs::write(&file_b, &large_payload).unwrap();

    // 2. Start Source Node on random port
    let source_node = P2PNode::new(db1_dir.path(), 0).await.unwrap();
    let folder_id = "test_sync_folder";
    let token = "test_auth_token_secret";

    let ticket = source_node
        .share_folder(
            source_dir.path(),
            folder_id,
            AccessMode::ReadWrite,
            SyncMode::TwoWay,
            token,
        )
        .await
        .unwrap();

    // 3. Start Destination Node on random port
    let dest_node = P2PNode::new(db2_dir.path(), 0).await.unwrap();

    // 4. Perform initial sync
    let stats = dest_node.sync_folder(dest_dir.path(), &ticket).await.unwrap();
    assert_eq!(stats.files_transferred, 2);

    // Verify files arrived intact on dest_dir
    let dest_file_a = dest_dir.path().join("document.txt");
    assert_eq!(
        std::fs::read(&dest_file_a).unwrap(),
        b"High performance P2P replication test"
    );

    let dest_file_b = dest_dir.path().join("subfolder").join("photo.dat");
    assert_eq!(std::fs::read(&dest_file_b).unwrap(), large_payload);

    // 5. Test Two-Way Deletion Tombstone propagation
    std::fs::remove_file(&file_a).unwrap();

    // Resync
    let stats2 = dest_node.sync_folder(dest_dir.path(), &ticket).await.unwrap();
    assert_eq!(stats2.files_deleted, 1);
    assert!(!dest_file_a.exists());
    assert!(dest_file_b.exists());
}

#[tokio::test]
async fn test_archive_mode_preserves_files_when_source_deleted() {
    let source_dir = tempdir().unwrap();
    let dest_dir = tempdir().unwrap();
    let db1_dir = tempdir().unwrap();
    let db2_dir = tempdir().unwrap();

    // 1. Create a photo on source phone
    let photo = source_dir.path().join("IMG_20261113.jpg");
    std::fs::write(&photo, b"Raw camera image data bytes").unwrap();

    // 2. Start Source Node sharing in ARCHIVE mode
    let source_node = P2PNode::new(db1_dir.path(), 0).await.unwrap();
    let folder_id = "camera_photos_archive";
    let token = "tok_archive_secret";

    let ticket = source_node
        .share_folder(
            source_dir.path(),
            folder_id,
            AccessMode::ReadOnly,
            SyncMode::Archive,
            token,
        )
        .await
        .unwrap();

    assert_eq!(ticket.sync_mode, SyncMode::Archive);

    // 3. Destination node (PC / NAS) syncs initially
    let dest_node = P2PNode::new(db2_dir.path(), 0).await.unwrap();
    let stats = dest_node.sync_folder(dest_dir.path(), &ticket).await.unwrap();
    assert_eq!(stats.files_transferred, 1);

    let dest_photo = dest_dir.path().join("IMG_20261113.jpg");
    assert!(dest_photo.exists());
    assert_eq!(std::fs::read(&dest_photo).unwrap(), b"Raw camera image data bytes");

    // 4. Phone user DELETES the photo to free up phone storage space!
    std::fs::remove_file(&photo).unwrap();
    assert!(!photo.exists());

    // 5. Resynchronize
    let stats2 = dest_node.sync_folder(dest_dir.path(), &ticket).await.unwrap();
    assert_eq!(stats2.files_deleted, 0); // No deletions performed!

    // Crucial check: Destination PC STILL has the photo preserved!
    assert!(dest_photo.exists(), "Archived photo must be preserved on receiver when sender deletes it");
    assert_eq!(std::fs::read(&dest_photo).unwrap(), b"Raw camera image data bytes");
}
