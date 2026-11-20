use anyhow::Result;
use rusqlite::{params, Connection};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::Path;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TrackedFile {
    pub relative_path: String,
    pub content_hash: [u8; 32],
    pub file_size: u64,
    pub mtime_ns: u64,
    pub is_directory: bool,
    pub sync_status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Tombstone {
    pub folder_id: String,
    pub relative_path: String,
    pub deleted_hash: [u8; 32],
    pub deleted_at: u64,
    pub deleted_by_node: String,
}

pub struct StateCatalog {
    conn: Connection,
}

impl StateCatalog {
    pub fn new<P: AsRef<Path>>(db_path: P) -> Result<Self> {
        let conn = Connection::open(db_path)?;
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA synchronous = NORMAL;

             CREATE TABLE IF NOT EXISTS tracked_files (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 folder_id TEXT NOT NULL,
                 relative_path TEXT NOT NULL,
                 content_hash BLOB NOT NULL,
                 file_size INTEGER NOT NULL,
                 mtime_ns INTEGER NOT NULL,
                 is_directory BOOLEAN NOT NULL DEFAULT 0,
                 sync_status TEXT NOT NULL DEFAULT 'synced',
                 updated_at INTEGER NOT NULL,
                 UNIQUE(folder_id, relative_path)
             );

             CREATE TABLE IF NOT EXISTS tombstones (
                 folder_id TEXT NOT NULL,
                 relative_path TEXT NOT NULL,
                 deleted_hash BLOB NOT NULL,
                 deleted_at INTEGER NOT NULL,
                 deleted_by_node TEXT NOT NULL,
                 PRIMARY KEY (folder_id, relative_path)
             );

             CREATE TABLE IF NOT EXISTS known_peers (
                 node_id TEXT PRIMARY KEY,
                 device_name TEXT NOT NULL,
                 last_seen_address TEXT,
                 last_handshake INTEGER,
                 connection_type TEXT
             );",
        )?;

        Ok(Self { conn })
    }

    pub fn in_memory() -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        conn.execute_batch(
            "CREATE TABLE tracked_files (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 folder_id TEXT NOT NULL,
                 relative_path TEXT NOT NULL,
                 content_hash BLOB NOT NULL,
                 file_size INTEGER NOT NULL,
                 mtime_ns INTEGER NOT NULL,
                 is_directory BOOLEAN NOT NULL DEFAULT 0,
                 sync_status TEXT NOT NULL DEFAULT 'synced',
                 updated_at INTEGER NOT NULL,
                 UNIQUE(folder_id, relative_path)
             );
             CREATE TABLE tombstones (
                 folder_id TEXT NOT NULL,
                 relative_path TEXT NOT NULL,
                 deleted_hash BLOB NOT NULL,
                 deleted_at INTEGER NOT NULL,
                 deleted_by_node TEXT NOT NULL,
                 PRIMARY KEY (folder_id, relative_path)
             );",
        )?;
        Ok(Self { conn })
    }

    /// Scan a physical directory on disk and update the catalog
    pub fn scan_directory<P: AsRef<Path>>(
        &mut self,
        folder_id: &str,
        base_dir: P,
    ) -> Result<Vec<TrackedFile>> {
        // Automatically prune old tombstones (> 30 days) to prevent unbounded DB growth
        self.prune_expired_tombstones(30 * 86400).ok();

        let base = base_dir.as_ref();
        let mut found_paths = HashSet::new();
        let mut scanned_files = Vec::new();

        let walker = walkdir::WalkDir::new(base).min_depth(1);
        for entry in walker.into_iter().filter_map(|e| e.ok()) {
            let path = entry.path();
            let rel_path = path
                .strip_prefix(base)?
                .to_string_lossy()
                .replace('\\', "/");

            found_paths.insert(rel_path.clone());

            let metadata = entry.metadata()?;
            let is_dir = metadata.is_dir();
            let size = if is_dir { 0 } else { metadata.len() };
            let mtime_ns = metadata
                .modified()?
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos() as u64;

            let hash = if is_dir {
                [0u8; 32]
            } else {
                // Check if existing catalog entry has identical mtime and size to skip expensive re-hashing
                let cached = self.conn.query_row(
                    "SELECT content_hash, mtime_ns, file_size FROM tracked_files WHERE folder_id = ?1 AND relative_path = ?2",
                    params![folder_id, &rel_path],
                    |row| {
                        let hash_blob: Vec<u8> = row.get(0)?;
                        let mut h = [0u8; 32];
                        h.copy_from_slice(&hash_blob);
                        let m: u64 = row.get(1)?;
                        let s: u64 = row.get(2)?;
                        Ok((h, m, s))
                    },
                ).ok();

                if let Some((cached_hash, cached_mtime, cached_size)) = cached {
                    if cached_mtime == mtime_ns && cached_size == size {
                        cached_hash
                    } else {
                        let manifest = crate::storage::chunker::Chunker::create_manifest(
                            base,
                            &rel_path,
                            crate::storage::chunker::DEFAULT_CHUNK_SIZE,
                        )?;
                        manifest.file_hash
                    }
                } else {
                    let manifest = crate::storage::chunker::Chunker::create_manifest(
                        base,
                        &rel_path,
                        crate::storage::chunker::DEFAULT_CHUNK_SIZE,
                    )?;
                    manifest.file_hash
                }
            };

            let now = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs();

            // Clear any old tombstone if this file is recreated
            self.conn.execute(
                "DELETE FROM tombstones WHERE folder_id = ?1 AND relative_path = ?2",
                params![folder_id, rel_path],
            )?;

            self.conn.execute(
                "INSERT INTO tracked_files (folder_id, relative_path, content_hash, file_size, mtime_ns, is_directory, sync_status, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, 'synced', ?7)
                 ON CONFLICT(folder_id, relative_path) DO UPDATE SET
                     content_hash = excluded.content_hash,
                     file_size = excluded.file_size,
                     mtime_ns = excluded.mtime_ns,
                     updated_at = excluded.updated_at",
                params![folder_id, rel_path, &hash[..], size, mtime_ns, is_dir, now],
            )?;

            scanned_files.push(TrackedFile {
                relative_path: rel_path,
                content_hash: hash,
                file_size: size,
                mtime_ns,
                is_directory: is_dir,
                sync_status: "synced".to_string(),
            });
        }

        // Detect locally deleted files and create tombstones
        let mut existing_stmt = self.conn.prepare(
            "SELECT relative_path, content_hash FROM tracked_files WHERE folder_id = ?1",
        )?;
        let rows = existing_stmt.query_map(params![folder_id], |row| {
            let path: String = row.get(0)?;
            let hash_blob: Vec<u8> = row.get(1)?;
            let mut hash = [0u8; 32];
            hash.copy_from_slice(&hash_blob);
            Ok((path, hash))
        })?;

        let mut to_delete = Vec::new();
        for item in rows.flatten() {
            if !found_paths.contains(&item.0) {
                to_delete.push(item);
            }
        }

        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        for (deleted_path, deleted_hash) in to_delete {
            self.conn.execute(
                "INSERT OR REPLACE INTO tombstones (folder_id, relative_path, deleted_hash, deleted_at, deleted_by_node)
                 VALUES (?1, ?2, ?3, ?4, 'local')",
                params![folder_id, deleted_path, &deleted_hash[..], now],
            )?;
            self.conn.execute(
                "DELETE FROM tracked_files WHERE folder_id = ?1 AND relative_path = ?2",
                params![folder_id, deleted_path],
            )?;
        }

        Ok(scanned_files)
    }

    /// List all tracked files for a folder
    pub fn list_files(&self, folder_id: &str) -> Result<Vec<TrackedFile>> {
        let mut stmt = self.conn.prepare(
            "SELECT relative_path, content_hash, file_size, mtime_ns, is_directory, sync_status
             FROM tracked_files WHERE folder_id = ?1 ORDER BY relative_path ASC",
        )?;

        let rows = stmt.query_map(params![folder_id], |row| {
            let hash_blob: Vec<u8> = row.get(1)?;
            let mut content_hash = [0u8; 32];
            content_hash.copy_from_slice(&hash_blob);

            Ok(TrackedFile {
                relative_path: row.get(0)?,
                content_hash,
                file_size: row.get(2)?,
                mtime_ns: row.get(3)?,
                is_directory: row.get(4)?,
                sync_status: row.get(5)?,
            })
        })?;

        let mut list = Vec::new();
        for r in rows {
            list.push(r?);
        }
        Ok(list)
    }

    /// List all active tombstones for a folder
    pub fn list_tombstones(&self, folder_id: &str) -> Result<Vec<Tombstone>> {
        let mut stmt = self.conn.prepare(
            "SELECT folder_id, relative_path, deleted_hash, deleted_at, deleted_by_node
             FROM tombstones WHERE folder_id = ?1",
        )?;

        let rows = stmt.query_map(params![folder_id], |row| {
            let hash_blob: Vec<u8> = row.get(2)?;
            let mut deleted_hash = [0u8; 32];
            deleted_hash.copy_from_slice(&hash_blob);

            Ok(Tombstone {
                folder_id: row.get(0)?,
                relative_path: row.get(1)?,
                deleted_hash,
                deleted_at: row.get(3)?,
                deleted_by_node: row.get(4)?,
            })
        })?;

        let mut list = Vec::new();
        for r in rows {
            list.push(r?);
        }
        Ok(list)
    }

    /// Prune tombstones older than max_age_secs (default 30 days) to prevent unbounded DB growth
    pub fn prune_expired_tombstones(&mut self, max_age_secs: u64) -> Result<usize> {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();
        let cutoff = now.saturating_sub(max_age_secs);
        let pruned = self.conn.execute(
            "DELETE FROM tombstones WHERE deleted_at < ?1",
            params![cutoff],
        )?;
        Ok(pruned)
    }

    /// Apply an incoming tombstone from a remote peer (delete file locally if present and hash matches)
    pub fn apply_remote_tombstone<P: AsRef<Path>>(
        &mut self,
        base_dir: P,
        tombstone: &Tombstone,
    ) -> Result<()> {
        let full_path = base_dir.as_ref().join(&tombstone.relative_path);

        // Verification Gate (Finding C-4): Only delete if local file hash matches the tombstone hash
        let local_record = self.conn.query_row(
            "SELECT content_hash FROM tracked_files WHERE folder_id = ?1 AND relative_path = ?2",
            params![tombstone.folder_id, tombstone.relative_path],
            |row| {
                let hash_blob: Vec<u8> = row.get(0)?;
                let mut hash = [0u8; 32];
                hash.copy_from_slice(&hash_blob);
                Ok(hash)
            },
        ).ok();

        if let Some(local_hash) = local_record {
            if local_hash != tombstone.deleted_hash {
                tracing::warn!(
                    "Tombstone hash mismatch for {}: local content does not match deleted version. Preserving local file.",
                    tombstone.relative_path
                );
                return Ok(());
            }
        }

        if full_path.exists() {
            if full_path.is_file() {
                std::fs::remove_file(&full_path).ok();
            } else if full_path.is_dir() {
                std::fs::remove_dir_all(&full_path).ok();
            }
        }

        self.conn.execute(
            "INSERT OR REPLACE INTO tombstones (folder_id, relative_path, deleted_hash, deleted_at, deleted_by_node)
             VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                tombstone.folder_id,
                tombstone.relative_path,
                &tombstone.deleted_hash[..],
                tombstone.deleted_at,
                tombstone.deleted_by_node
            ],
        )?;

        self.conn.execute(
            "DELETE FROM tracked_files WHERE folder_id = ?1 AND relative_path = ?2",
            params![tombstone.folder_id, tombstone.relative_path],
        )?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_catalog_scan_and_tombstone() {
        let dir = tempdir().unwrap();
        let folder_id = "test-folder";

        // Create sample file
        let file1 = dir.path().join("doc.txt");
        std::fs::write(&file1, b"hello world").unwrap();

        let mut catalog = StateCatalog::in_memory().unwrap();
        let scanned = catalog.scan_directory(folder_id, dir.path()).unwrap();
        assert_eq!(scanned.len(), 1);
        assert_eq!(scanned[0].relative_path, "doc.txt");

        // Now delete doc.txt
        std::fs::remove_file(&file1).unwrap();
        catalog.scan_directory(folder_id, dir.path()).unwrap();

        let files = catalog.list_files(folder_id).unwrap();
        assert_eq!(files.len(), 0);

        let tombstones = catalog.list_tombstones(folder_id).unwrap();
        assert_eq!(tombstones.len(), 1);
        assert_eq!(tombstones[0].relative_path, "doc.txt");
    }

    #[test]
    fn test_tombstone_hash_mismatch_preserves_file() {
        let dir = tempdir().unwrap();
        let folder_id = "test-folder-security";

        let file = dir.path().join("safe.txt");
        std::fs::write(&file, b"valuable data").unwrap();

        let mut catalog = StateCatalog::in_memory().unwrap();
        let scanned = catalog.scan_directory(folder_id, dir.path()).unwrap();
        assert_eq!(scanned.len(), 1);
        let actual_hash = scanned[0].content_hash;

        // An attacker or stale peer tries to send a tombstone with an incorrect deleted_hash
        let rogue_tombstone = Tombstone {
            folder_id: folder_id.to_string(),
            relative_path: "safe.txt".to_string(),
            deleted_hash: [0xEEu8; 32], // Mismatched hash
            deleted_at: 123456789,
            deleted_by_node: "rogue_node".to_string(),
        };

        catalog.apply_remote_tombstone(dir.path(), &rogue_tombstone).unwrap();

        // Verification Gate: The local file MUST NOT be deleted!
        assert!(file.exists(), "Local file must be preserved on tombstone hash mismatch");
        let tracked = catalog.list_files(folder_id).unwrap();
        assert_eq!(tracked.len(), 1, "Tracked file entry must remain");
        assert_eq!(tracked[0].content_hash, actual_hash);
    }
}
