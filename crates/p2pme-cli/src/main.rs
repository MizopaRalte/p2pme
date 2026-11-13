use anyhow::Result;
use clap::{Parser, Subcommand};
use p2pme_core::ticket::{AccessMode, PairingTicket};
use p2pme_core::P2PNode;
use std::path::PathBuf;
use tracing_subscriber::EnvFilter;

#[derive(Parser)]
#[command(name = "p2pme", about = "Decentralized P2P data replication and streaming engine")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand, Clone)]
enum Commands {
    /// Show or initialize local node identity
    Init {
        #[arg(short, long, default_value = ".p2pme")]
        db_dir: PathBuf,
    },
    /// Share a local directory and output pairing ticket / QR code
    Share {
        /// Path to the directory to share
        path: PathBuf,
        /// Optional folder ID (defaults to folder directory name)
        #[arg(short, long)]
        folder_id: Option<String>,
        /// Share as Read-Only
        #[arg(long)]
        ro: bool,
        /// Share in Archive mode (storage-saver: deletions on sender leave receiver files untouched)
        #[arg(long)]
        archive: bool,
        /// Share in Camera Backup mode (send-only to peers)
        #[arg(long)]
        backup: bool,
        /// Port to bind QUIC transport
        #[arg(short, long, default_value_t = 0)]
        port: u16,
        #[arg(short, long, default_value = ".p2pme")]
        db_dir: PathBuf,
    },
    /// Join a shared folder using a pairing ticket
    Join {
        /// Encoded pairing ticket string
        ticket: String,
        /// Path where the folder should be synchronized
        destination: PathBuf,
        /// Port to bind QUIC transport
        #[arg(short, long, default_value_t = 0)]
        port: u16,
        #[arg(short, long, default_value = ".p2pme")]
        db_dir: PathBuf,
    },
    /// One-time secure quick drop: send selected files to a peer with PIN / QR code
    Drop {
        /// Files to send
        files: Vec<PathBuf>,
        /// Port to bind QUIC transport
        #[arg(short, long, default_value_t = 0)]
        port: u16,
        #[arg(short, long, default_value = ".p2pme")]
        db_dir: PathBuf,
    },
    /// Receive a one-time secure quick drop using ticket payload and optional PIN
    Receive {
        /// Drop ticket payload
        ticket: String,
        /// Optional 6-digit PIN override
        #[arg(long)]
        pin: Option<String>,
        /// Destination directory to save received files
        #[arg(short, long, default_value = ".")]
        destination: PathBuf,
        /// Port to bind QUIC transport
        #[arg(short, long, default_value_t = 0)]
        port: u16,
        #[arg(short, long, default_value = ".p2pme")]
        db_dir: PathBuf,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env().add_directive(tracing::Level::INFO.into()))
        .init();

    let cli = Cli::parse();

    match cli.command {
        Some(cmd) => execute_command(cmd).await,
        None => run_interactive().await,
    }
}

async fn execute_command(cmd: Commands) -> Result<()> {
    match cmd {
        Commands::Init { db_dir } => {
            let node = P2PNode::new(&db_dir, 0).await?;
            println!("========================================================");
            println!("P2Pme Node Initialized");
            println!("Node ID: {}", node.node_id);
            println!("Listening Port: {}", node.transport.listening_port);
            println!("Database: {:?}", node.db_dir);
            println!("========================================================");
        }

        Commands::Share {
            path,
            folder_id,
            ro,
            archive,
            backup,
            port,
            db_dir,
        } => {
            let folder_name = folder_id.unwrap_or_else(|| {
                path.file_name()
                    .unwrap_or_default()
                    .to_string_lossy()
                    .to_string()
            });

            let access = if ro {
                AccessMode::ReadOnly
            } else {
                AccessMode::ReadWrite
            };

            let sync_mode = if archive {
                p2pme_core::ticket::SyncMode::Archive
            } else if backup {
                p2pme_core::ticket::SyncMode::CameraBackup
            } else {
                p2pme_core::ticket::SyncMode::TwoWay
            };

            let node = P2PNode::new(&db_dir, port).await?;
            let token = format!("tok_{}", &blake3::hash(&rand::random::<[u8; 16]>()).to_hex()[..12]);

            let ticket = node.share_folder(&path, &folder_name, access, sync_mode, &token).await?;
            let payload = ticket.to_string_payload()?;

            println!("\n========================================================");
            println!("FOLDER SHARED: {}", folder_name);
            println!("Local Path: {:?}", std::fs::canonicalize(&path).unwrap_or(path));
            println!("Listening on port: {}", node.transport.listening_port);
            println!("Access: {:?}", ticket.access);
            println!("Sync Mode: {:?}", ticket.sync_mode);
            println!("========================================================");
            println!("\nPairing Ticket:\n{}\n", payload);

            // Display terminal QR code for phone scanning
            if let Ok(code) = qrcode::QrCode::new(payload.as_bytes()) {
                let string = code
                    .render::<qrcode::render::unicode::Dense1x2>()
                    .dark_color(qrcode::render::unicode::Dense1x2::Dark)
                    .light_color(qrcode::render::unicode::Dense1x2::Light)
                    .build();
                println!("Scan with P2Pme mobile app:\n{}", string);
            }

            println!("Hosting... Press Ctrl+C to exit.");
            tokio::signal::ctrl_c().await?;
            println!("\nStopping share.");
        }

        Commands::Join {
            ticket,
            destination,
            port,
            db_dir,
        } => {
            let parsed_ticket = PairingTicket::from_string_payload(&ticket)?;
            println!("\nConnecting to peer: {}", parsed_ticket.node_id);
            println!("Folder: {}", parsed_ticket.folder_id);
            println!("Access: {:?}", parsed_ticket.access);
            println!("Candidate Addresses: {:?}", parsed_ticket.direct_addresses);

            let node = P2PNode::new(&db_dir, port).await?;
            println!("Synchronizing into {:?}", destination);

            let stats = node.sync_folder(&destination, &parsed_ticket).await?;
            println!("\n========================================================");
            println!("SYNCHRONIZATION COMPLETE");
            println!("Files Transferred: {}", stats.files_transferred);
            println!("Files Deleted:     {}", stats.files_deleted);
            println!("Bytes Transferred: {} bytes", stats.bytes_transferred);
            println!("========================================================");
        }

        Commands::Drop {
            files,
            port,
            db_dir,
        } => {
            if files.is_empty() {
                anyhow::bail!("No files specified to drop. Usage: p2pme drop <file1> <file2>...");
            }

            let node = P2PNode::new(&db_dir, port).await?;
            let ticket = node.create_drop(files).await?;
            let payload = ticket.to_string_payload()?;
            let total_bytes: u64 = ticket.files.iter().map(|f| f.size).sum();

            println!("\n========================================================");
            println!("ONE-TIME SECURE QUICK DROP CREATED");
            println!("PIN Code:         [ {} ]", ticket.pin_code);
            println!("Drop ID:          {}", ticket.drop_id);
            println!("Files Included:   {}", ticket.files.len());
            println!("Total Size:       {} bytes", total_bytes);
            println!("Security:         TLS 1.3 QUIC + BLAKE3 + 3-attempt lockout");
            println!("Lifetime:         10 minutes (Ephemeral, self-destructs on delivery)");
            println!("========================================================");
            println!("\nDrop Ticket Payload:\n{}\n", payload);

            // Terminal QR Code
            if let Ok(code) = qrcode::QrCode::new(payload.as_bytes()) {
                let string = code
                    .render::<qrcode::render::unicode::Dense1x2>()
                    .dark_color(qrcode::render::unicode::Dense1x2::Dark)
                    .light_color(qrcode::render::unicode::Dense1x2::Light)
                    .build();
                println!("Scan with P2Pme mobile app:\n{}", string);
            }

            println!("Waiting for recipient to claim drop... (Press Ctrl+C to abort)");

            // Poll until the ephemeral drop is fulfilled and removed from memory
            let drop_id = ticket.drop_id.clone();
            let dm = node.drop_manager.clone();
            loop {
                tokio::time::sleep(tokio::time::Duration::from_millis(500)).await;
                let active = {
                    let map = dm.drops.lock().await;
                    map.contains_key(&drop_id)
                };
                if !active {
                    println!("\n========================================================");
                    println!("QUICK DROP COMPLETE: Files securely transferred!");
                    println!("Session self-destructed from memory.");
                    println!("========================================================");
                    break;
                }
            }
        }

        Commands::Receive {
            ticket,
            pin,
            destination,
            port,
            db_dir,
        } => {
            let drop_ticket = p2pme_core::DropTicket::from_string_payload(&ticket)?;
            let pin_to_use = pin.as_deref().unwrap_or(&drop_ticket.pin_code);

            println!("\nConnecting for One-Time Quick Drop: ID={}", drop_ticket.drop_id);
            println!("Direct Candidates: {:?}", drop_ticket.direct_addresses);
            println!("Files: {}", drop_ticket.files.len());
            for f in &drop_ticket.files {
                println!("  - {} ({} bytes, blake3: {})", f.name, f.size, &f.blake3_hash[..8]);
            }

            let node = P2PNode::new(&db_dir, port).await?;
            println!("\nDownloading to directory: {:?}", destination);

            let stats = node.receive_drop(&drop_ticket, Some(pin_to_use), &destination).await?;

            println!("\n========================================================");
            println!("QUICK DROP DOWNLOAD COMPLETED & VERIFIED");
            println!("Files Verified:    {}", stats.files_transferred);
            println!("Bytes Transferred: {} bytes", stats.bytes_transferred);
            println!("Integrity:         BLAKE3 cryptographic verification PASSED");
            println!("========================================================");
        }
    }

    Ok(())
}

fn prompt_line(prompt: &str) -> String {
    use std::io::{self, Write};
    print!("{}", prompt);
    let _ = io::stdout().flush();
    let mut input = String::new();
    match io::stdin().read_line(&mut input) {
        Ok(0) => "0".to_string(), // EOF: exit cleanly
        Ok(_) => input.trim().to_string(),
        Err(_) => "0".to_string(),
    }
}

fn press_enter_to_exit() {
    use std::io::{self, Write};
    print!("\nPress Enter to exit...");
    let _ = io::stdout().flush();
    let mut input = String::new();
    let _ = io::stdin().read_line(&mut input);
}

fn find_gui_executable() -> Option<PathBuf> {
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            let candidate = dir.join("p2pme_app.exe");
            if candidate.exists() {
                return Some(candidate);
            }
        }
    }
    let candidate = PathBuf::from("p2pme_app.exe");
    if candidate.exists() {
        return Some(candidate);
    }
    let runner_candidate = PathBuf::from("app/build/windows/x64/runner/Release/p2pme_app.exe");
    if runner_candidate.exists() {
        return Some(runner_candidate);
    }
    None
}

async fn run_interactive() -> Result<()> {
    println!("========================================================");
    println!("  P2Pme - Secure Direct Photo & Folder Sync");
    println!("  Decentralized P2P replication engine");
    println!("========================================================");

    let gui_path = find_gui_executable();
    if let Some(ref path) = gui_path {
        println!("Desktop GUI detected: {:?}", path);
    }

    loop {
        println!("\nSelect an action:");
        println!("  1) Launch Desktop GUI (p2pme_app.exe)");
        println!("  2) Share a folder (Generate Pairing Ticket & QR code)");
        println!("  3) Join a shared folder (Sync with phone or PC)");
        println!("  4) Quick Drop files (One-time transfer with PIN)");
        println!("  5) Receive Quick Drop files");
        println!("  6) Show Node Identity");
        println!("  0) Exit");

        let choice = prompt_line("\nEnter choice [0-6]: ");
        match choice.as_str() {
            "1" => {
                if let Some(ref path) = gui_path {
                    println!("Launching P2Pme Desktop GUI...");
                    let _ = std::process::Command::new(path).spawn();
                    println!("Application started. This console will now close.");
                    tokio::time::sleep(tokio::time::Duration::from_millis(800)).await;
                    return Ok(());
                } else {
                    println!("\nP2Pme Desktop GUI (p2pme_app.exe) was not found in the current directory.");
                    println!("You can download the full Windows package with GUI from https://p2pme.pages.dev");
                }
            }
            "2" => {
                let path_str = prompt_line("Enter folder path to share: ");
                if path_str.is_empty() {
                    println!("Folder path cannot be empty.");
                    continue;
                }
                let path = PathBuf::from(path_str);
                let mode_str = prompt_line("Mode [1=Two-Way, 2=Read-Only, 3=Archive (Storage Saver)]: ");
                let (ro, archive) = match mode_str.as_str() {
                    "2" => (true, false),
                    "3" => (false, true),
                    _ => (false, false),
                };
                let cmd = Commands::Share {
                    path,
                    folder_id: None,
                    ro,
                    archive,
                    backup: false,
                    port: 0,
                    db_dir: PathBuf::from(".p2pme"),
                };
                if let Err(e) = execute_command(cmd).await {
                    eprintln!("Error sharing folder: {}", e);
                }
                press_enter_to_exit();
                return Ok(());
            }
            "3" => {
                let ticket = prompt_line("Paste Pairing Ticket: ");
                if ticket.is_empty() {
                    println!("Ticket cannot be empty.");
                    continue;
                }
                let dest_str = prompt_line("Destination folder [default: ./P2PmeSync]: ");
                let destination = if dest_str.is_empty() {
                    PathBuf::from("P2PmeSync")
                } else {
                    PathBuf::from(dest_str)
                };
                let cmd = Commands::Join {
                    ticket,
                    destination,
                    port: 0,
                    db_dir: PathBuf::from(".p2pme"),
                };
                if let Err(e) = execute_command(cmd).await {
                    eprintln!("Error synchronizing folder: {}", e);
                }
                press_enter_to_exit();
                return Ok(());
            }
            "4" => {
                let files_str = prompt_line("Enter file path(s) to send (separated by comma): ");
                let files: Vec<PathBuf> = files_str
                    .split(',')
                    .map(|s| PathBuf::from(s.trim()))
                    .filter(|p| !p.as_os_str().is_empty())
                    .collect();
                if files.is_empty() {
                    println!("No files provided.");
                    continue;
                }
                let cmd = Commands::Drop {
                    files,
                    port: 0,
                    db_dir: PathBuf::from(".p2pme"),
                };
                if let Err(e) = execute_command(cmd).await {
                    eprintln!("Error creating drop: {}", e);
                }
                press_enter_to_exit();
                return Ok(());
            }
            "5" => {
                let ticket = prompt_line("Enter Drop Ticket or PIN: ");
                let dest_str = prompt_line("Destination folder [default: .]: ");
                let destination = if dest_str.is_empty() {
                    PathBuf::from(".")
                } else {
                    PathBuf::from(dest_str)
                };
                let cmd = Commands::Receive {
                    ticket,
                    pin: None,
                    destination,
                    port: 0,
                    db_dir: PathBuf::from(".p2pme"),
                };
                if let Err(e) = execute_command(cmd).await {
                    eprintln!("Error receiving drop: {}", e);
                }
                press_enter_to_exit();
                return Ok(());
            }
            "6" => {
                let cmd = Commands::Init {
                    db_dir: PathBuf::from(".p2pme"),
                };
                if let Err(e) = execute_command(cmd).await {
                    eprintln!("Error initializing node: {}", e);
                }
            }
            "0" | "exit" | "q" => {
                println!("Exiting P2Pme.");
                return Ok(());
            }
            _ => {
                println!("Invalid option. Please enter 0-6.");
            }
        }
    }
}
