use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;

pub const DEFAULT_CHUNK_SIZE: usize = 256 * 1024; // 256 KB chunk size

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ChunkInfo {
    pub index: u32,
    pub offset: u64,
    pub length: u32,
    pub hash: [u8; 32],
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FileManifest {
    pub relative_path: String,
    pub total_size: u64,
    pub file_hash: [u8; 32],
    pub chunk_size: u32,
    pub chunks: Vec<ChunkInfo>,
}

pub struct Chunker;

impl Chunker {
    /// Compute total BLAKE3 file hash and chunk manifest
    pub fn create_manifest<P: AsRef<Path>>(
        base_dir: P,
        rel_path: &str,
        chunk_size: usize,
    ) -> Result<FileManifest> {
        let full_path = base_dir.as_ref().join(rel_path);
        let mut file = File::open(&full_path)
            .with_context(|| format!("Failed to open file for chunking: {:?}", full_path))?;
        
        let metadata = file.metadata()?;
        let total_size = metadata.len();

        let mut file_hasher = blake3::Hasher::new();
        let mut chunks = Vec::new();

        let mut buffer = vec![0u8; chunk_size];
        let mut offset = 0u64;
        let mut index = 0u32;

        loop {
            let bytes_read = file.read(&mut buffer)?;
            if bytes_read == 0 {
                break;
            }

            let slice = &buffer[..bytes_read];
            file_hasher.update(slice);

            let chunk_hash = blake3::hash(slice);
            chunks.push(ChunkInfo {
                index,
                offset,
                length: bytes_read as u32,
                hash: *chunk_hash.as_bytes(),
            });

            offset += bytes_read as u64;
            index += 1;
        }

        // Handle empty files
        if total_size == 0 {
            let chunk_hash = blake3::hash(&[]);
            chunks.push(ChunkInfo {
                index: 0,
                offset: 0,
                length: 0,
                hash: *chunk_hash.as_bytes(),
            });
        }

        let file_hash = *file_hasher.finalize().as_bytes();

        Ok(FileManifest {
            relative_path: rel_path.to_string(),
            total_size,
            file_hash,
            chunk_size: chunk_size as u32,
            chunks,
        })
    }

    /// Read a specific chunk directly from a file
    pub fn read_chunk<P: AsRef<Path>>(
        file_path: P,
        chunk: &ChunkInfo,
    ) -> Result<Vec<u8>> {
        let mut file = File::open(file_path)?;
        file.seek(SeekFrom::Start(chunk.offset))?;
        let mut buffer = vec![0u8; chunk.length as usize];
        file.read_exact(&mut buffer)?;

        let computed_hash = blake3::hash(&buffer);
        if computed_hash.as_bytes() != &chunk.hash {
            anyhow::bail!("Chunk {} data corruption: hash mismatch", chunk.index);
        }

        Ok(buffer)
    }

    /// Write an incoming verified chunk to disk at its designated offset
    pub fn write_chunk<P: AsRef<Path>>(
        target_path: P,
        chunk: &ChunkInfo,
        data: &[u8],
    ) -> Result<()> {
        if data.len() != chunk.length as usize {
            anyhow::bail!(
                "Invalid chunk length: expected {}, got {}",
                chunk.length,
                data.len()
            );
        }

        let computed_hash = blake3::hash(data);
        if computed_hash.as_bytes() != &chunk.hash {
            anyhow::bail!("Incoming chunk {} hash mismatch", chunk.index);
        }

        let target = target_path.as_ref();
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let mut file = std::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .open(target)?;

        file.seek(SeekFrom::Start(chunk.offset))?;
        file.write_all(data)?;
        file.flush()?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_chunk_and_reassemble() {
        let dir = tempdir().unwrap();
        let test_file = dir.path().join("sample.bin");

        // Write 700 KB of data (spanning ~3 chunks at 256KB)
        let sample_data: Vec<u8> = (0..(700 * 1024)).map(|i| (i % 256) as u8).collect();
        std::fs::write(&test_file, &sample_data).unwrap();

        let manifest = Chunker::create_manifest(dir.path(), "sample.bin", DEFAULT_CHUNK_SIZE).unwrap();
        assert_eq!(manifest.chunks.len(), 3);
        assert_eq!(manifest.total_size, 700 * 1024);

        // Reassemble in a destination file chunk by chunk
        let dest_file = dir.path().join("reassembled.bin");
        for chunk in &manifest.chunks {
            let data = Chunker::read_chunk(&test_file, chunk).unwrap();
            Chunker::write_chunk(&dest_file, chunk, &data).unwrap();
        }

        let reassembled_data = std::fs::read(&dest_file).unwrap();
        assert_eq!(sample_data, reassembled_data);
    }
}

