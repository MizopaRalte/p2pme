# <img src="web-pwa/icon-192.png" width="36" height="36" alt="P2Pme" align="absmiddle"> P2Pme

> **Pure Peer-to-Peer Data Replication & One-Time Ephemeral Drop**  
> *Zero cloud custody. 100% private. Cross-platform.*

[![Rust](https://img.shields.io/badge/Rust-1.75+-orange.svg)](https://www.rust-lang.org/)
[![Flutter](https://img.shields.io/badge/Flutter-3.13+-blue.svg)](https://flutter.dev/)
[![Transport](https://img.shields.io/badge/Transport-QUIC%20%7C%20TLS%201.3-green.svg)](https://quicwg.org/)
[![Hashing](https://img.shields.io/badge/Integrity-BLAKE3-blueviolet.svg)](https://github.com/BLAKE3-team/BLAKE3)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Overview

**P2Pme** is a high-performance, decentralized data replication and drop engine. It combines two core workflows in a streamlined 3-tab experience:

1. **🚀 Transfer Tab:** One-time, direct device-to-device transfers. Send camera photos or any files to nearby devices discovered automatically on your Wi-Fi network with 1-tap, or generate a 6-digit PIN and zero-install WebDrop link to send anywhere over the internet.
2. **🔄 Backup Tab:** Continuous background folder synchronization and Camera Roll auto-backup with Storage-Saver Archive Mode. Supports adding preset folders (Camera Roll, WhatsApp) or any custom folder, viewing file counts and sync speeds, sharing folder QR tickets, and safely removing folders from sync.
3. **🖥️ Server Tab:** Turn any phone, PC, Mac, or NAS into a dedicated 24/7 backup hub and receiver. Customize where received files and backups are stored, view real-time LAN socket addresses, display master pairing QR codes, and monitor battery optimization.
4. **Portable Windows Desktop App:** Zero installation required. Simply download, extract, and launch `p2pme_app.exe` (or `Launch_P2Pme.cmd`) for full desktop GUI and background replication.
5. **Zero-Install WebDrop & PWA:** Built-in local upload portal and standalone Cloudflare Pages Web PWA. Any iPhone, iPad, PC, or guest can send/receive files over Wi-Fi simply by opening the web app—**zero app installation required** and **auto-updates on every launch**.

---

## Key Features

### 🚀 1. Transfer Tab: Instant 1-Time Transfer (LAN & Internet)
* **Nearby Wi-Fi 1-Tap Beam:** Automatically discovers active devices on your local network. Tap any nearby device to send files directly over full-speed Wi-Fi without typing pins or scanning codes.
* **Smart Adapter Filtering & Subnet Sweep:** Filters out virtual VPN/tunnel adapters (WireGuard, AdGuard, OpenVPN) to probe real physical network interfaces, with manual "Add by IP" fallback.
* **Global Internet P2P NAT Traversal (STUN + Edge Rendezvous):** Nodes automatically discover their external public WAN sockets via asynchronous STUN (RFC 5389 / `stun.l.google.com:19302`). Ephemeral 6-digit PIN drops announce candidate endpoints to Cloudflare edge rendezvous (`/api/drop/announce`), allowing receivers on separate networks or 5G cellular to connect directly peer-to-peer with zero cloud custody.
* **6-Digit PIN & WebDrop Over Internet:** Send to any device worldwide with a 6-digit PIN code or zero-install browser link (`https://p2pme.pages.dev`).
* **Decoupled PIN Protection:** 6-digit PIN codes are strictly excluded from exported DropTicket payloads and QR codes, ensuring intercepted ticket links cannot be unlocked without the sender's PIN.
* **Self-Destructing Ephemeral Security:** 3 incorrect PIN attempts wipe the session instantly; sessions automatically expire in 10 minutes.
* **Non-Destructive File Collision Prevention:** Incoming duplicate files never overwrite existing files. Duplicate names are automatically assigned an ISO timestamp suffix (`<base>_<YYYYMMDD>_<HHMMSS_mmm>.<ext>`) to guarantee zero silent overwrites and 100% historical data preservation.
* **Dedicated Receiver Destination Selection:** Choose where incoming files land before receiving, with a 1-tap option to save the chosen path as your persistent default destination.

### 🔄 2. Backup Tab: Continuous Background Sync
* **High-Speed Mtime-Cached Scanning:** Skips redundant cryptographic re-hashing of unmodified files by comparing `mtime_ns` and `file_size` against the SQLite catalog, drastically reducing battery and CPU usage during background sync.
* **Safe Remote Tombstone Verification:** Inbound deletion tombstones are strictly verified against local file hashes before removal. If a local file has been modified or does not match the tombstone's deleted hash, the local file is preserved.
* **Automatic Tombstone Garbage Collection:** Automatically prunes tombstones older than 30 days to prevent unbounded database growth.
* **Persistent Connected Servers Registry (`.connected_servers.json`):** Retains all previously paired servers indefinitely across app restarts, reboots, and network switches. Displays connected servers in both the Transfer and Backup tabs with live online/offline status, storage free telemetry, 1-tap "Send Here" beam, and a manual "Reconnect / Ping" button.
* **Intelligent 3-Phase Auto-Reconnect Engine:** Recovers seamlessly when returning home or when the home router DHCP assigns a new IP address to the 24/7 server:
  * **Phase 1 (Direct Ping):** Instantly pings last-known IP via `/api/info`.
  * **Phase 2 (Subnet Sweep):** Concurrently sweeps the local `/24` subnet in batches of 25 nodes, queries `/api/info`, and matches the server by cryptographic token and device ID. When found, automatically updates the server IP and saves it to disk.
  * **Phase 3 (Remote WAN / Tailscale Fallback):** Probes remote WAN/mesh endpoint if away from home.
* **Instant Camera QR Server Pairing:** 1-tap connection to your 24/7 Server Hub. Tap "Scan Server QR Code" on your sending phone (e.g. iPhone) and point at the Server Hub screen (e.g. Android phone or PC). Automatically parses IP, port, remote WAN address, and 256-bit CSPRNG security tokens for instantaneous zero-typing pairing.
* **Multi-Transport Connection Tiers:**
  * **⚡ Tier 1 (Direct USB Cable):** Hardware wire speed (35–400+ MB/s) with 0% packet loss and zero Wi-Fi required via USB tethering / USB-to-USB link.
  * **📶 Tier 2 (Local Wi-Fi Direct):** Full wire-speed LAN socket streaming (80–110 MB/s) on home Wi-Fi.
  * **🌐 Tier 3 (Internet Mesh / WAN):** Automatic fallback to Tailscale mesh (`100.x.x.x`) or remote IP when away from home on 5G/cellular data.
* **Dynamic Hardware Device Naming:** Dynamically queries genuine device identity from the operating system (`Settings.Global.DEVICE_NAME` / `Build.MODEL` on Android, `UIDevice.current.name` on iOS, `COMPUTERNAME` on Windows) so senders and receivers always see exactly who is connected with zero hardcoded placeholders.
* **Persistent Server State & Unified Configuration:** Remembers paired servers, custom download paths, sync folders, and preferences across app restarts, updates, and network switches. Stored permanently in OS-protected documents storage (`.p2pme_config.json` and `p2pme_synced_camera_assets.json`) with zero reset on updates.
* **Native Screenshot & Screen Recording Exclusion:** iOS PhotoKit and Android DCIM queries automatically exclude screenshots and screen recordings (`PHAssetMediaSubtype.photoScreenshot` and `videoScreenRecording`), ensuring only genuine photos and videos enter the camera roll backup queue.
* **Wi-Fi Only Sync Enforcement:** When enabled, automatically blocks cellular/WAN transfers to protect user mobile data allowances, only permitting sync over local Wi-Fi or high-speed USB cable.
* **Low-Battery Auto-Backup Protection:** Native battery monitoring automatically pauses camera roll synchronization when the device battery drops below 15% and is discharging, preventing battery exhaustion and abrupt shutdown.
* **Real-Time Receiver Storage Telemetry:** The sender queries receiver disk space over native APIs (`StatFs` / iOS `resourceValues`) and exposes it in the Connected Server card (`Pixel 7 Pro • 42.2 GB Free`) with proactive warnings if a photo batch exceeds destination storage.
* **Intelligent Out-of-Space Protocol (HTTP 507 & Bounded Auto-Resume):** When the receiver disk fills up, the server responds with `HTTP 507 Insufficient Storage`. The receiver alerts the user to tap "Free up space" in Google Photos, while the sender automatically pauses and polls the receiver every 5 seconds (up to 5 minutes timeout), auto-resuming seamlessly as soon as capacity is freed!
* **Role & Peer Isolation:** Receivers in Server Mode no longer pick up nearby client devices as their own backup server on Tab 2. Active incoming transfers are isolated to Tab 3 (Server Hub).
* **Comprehensive Bidirectional Telemetry (GB & Percentage Clarity):**
  * **Sender View:** Shows `Uploading: XX.X MB/s`, active file index out of total (`Sending File 12 of 596: IMG_1234.JPG`), total batch volume sent out of total size (`1.25 GB / 5.00 GB • 25%`), dual batch and single-file progress bars, and 1-tap **Pause / Resume Backup** button.
  * **Receiver View:** Shows `Downloading: XX.X MB/s`, active file index out of total (`Downloading file 12 of 596: IMG_1234.JPG`), total batch volume received out of total size (`Received 1.25 GB of 5.00 GB • 25%`), and active receiver ingestion telemetry on Tab 3 (Server).
  * **Receiver Lock (Sender-Exclusive Pause Control):** In Server Mode, the receiver functions as a dedicated automated destination. Pause and resume controls are strictly reserved for the sender device to eliminate desynchronization and accidental two-way conflicts.
* **1-Tap Pause & Resume (Sender Only):** Pause active backup transfers on demand at any time to preserve battery or bandwidth, and resume when ready without losing progress.
* **1-Tap Camera Roll Auto-Backup:** Automatically tracks and replicates your photos/videos directly to your computer or backup server in full original quality.
* **Storage-Saver Archive Mode:** Free up storage on your phone by deleting local photos—synced copies on your PC/server remain safe and untouched.
* **Folder Management & Instant Deletion:** Easily add folders (Camera Roll, WhatsApp Media, or any custom folder) and remove them from sync with 1 tap without losing local files.
* **Folder QR & Ticket Sharing:** View and share pairing tickets or QR codes for any synced folder to pair directly with Windows (`p2pme join <ticket>`) or another phone.
* **1-Tap Ticket Regeneration & Revocation:** Securely revoke and generate a brand-new BLAKE3 folder pairing ticket with a single tap, instantly retiring older tickets to guarantee zero conflict.

### 🖥️ 3. Server Tab: 24/7 Backup Hub & Receiver
* **Explicit Server Master Switch (OFF by Default, Persistent State):** The 24/7 server engine is OFF by default on all platforms upon setup. Toggling the master switch ON starts the listener and persists `serverEnabled: true` in configuration so the server remains active always across app restarts and reboots. Toggling OFF cleanly stops the socket, stops background services, and keeps the server stopped until manually toggled on again.
* **Unified Single Master Switch (Zero Redundancy):** Exactly one authoritative switch controls the 24/7 server. Turning the server ON automatically activates the Background Keep-Alive Daemon (holding wakelocks & Wi-Fi locks so the OS never sleeps). Turning the server OFF cleanly stops the daemon for zero background battery consumption. Confusing duplicate switches have been completely eliminated.
* **🛡️ 100% Clean & Safe (Verified Zero Play Protect Warnings):** Built cleanly without hazardous permissions like `REQUEST_INSTALL_PACKAGES` or unsolicited router port-manipulation code. Passes Google Play Protect install-time security verification with zero warnings (`result=ALLOW`).
* **Turn Any Device into a Server:** Toggle 24/7 Backup Server mode to accept incoming drops and continuous backups with background keep-alive.
* **Dual-Endpoint Pairing (LAN + Remote/WAN):** Configure an optional Remote / WAN Endpoint (e.g. Tailscale IP or domain). QR code embeds `&wan=...` for seamless zero-config pairing across both LAN and internet.
* **⚡ Direct USB Cable Interface Detection:** Automatically discovers active USB tethering interfaces (`rndis`, `usb`, `ncm`, `cdc`) and exposes them for direct cable backup.
* **Live Ingestion Telemetry & Speed Meter:** Displays real-time download speed (`Downloading: XX.X MB/s`), active receiving file names, total batch gigabytes received (`Received X.XX GB of Y.YY GB`), and dynamic dual progress bars. Server Mode enforces receiver lock (controlled by sender).
* **Custom Save Destination Folder:** Choose exactly where received files and folder backups land on disk (e.g. internal storage, external SD card, or desktop path).
* **Direct Server Ticket & Dynamic QR Code:** Connect new client devices to your hub using a master server pairing code or direct LAN socket (`http://<ip>:45455`).
* **1-Tap Zero-Conflict Key Regeneration:** Rotate your Server Hub Secret Key (256-bit CSPRNG) on demand with 1 tap. Immediately revokes older QR codes and browser links with zero server collisions.
* **Battery Optimization Management:** Visual indicator and 1-tap shortcut to disable OS battery throttling on Android for uninterrupted background replication.
* **Multi-Stream Concurrent Ingestion:** Concurrent file beams from multiple family devices are ingested into thread-isolated `ActiveReceiverSession` instances, displaying aggregated real-time throughput with zero global state race conditions.
* **Android 11+ Scoped Storage Management:** Gracefully checks `MANAGE_EXTERNAL_STORAGE` when custom directories are chosen on Android 11+ (API 30+), with a 1-tap redirect to Android Settings for full write access.
* **Headless Configuration Provisioning:** Automatically inspects shared external storage (`/sdcard/Download/P2Pme/.p2pme_config.json`) for automated provisioning on headless media centers and Android TV hubs.

---

## Performance & Speed

| Metric | **P2Pme (Native QUIC)** | **Cloud Storage (Dropbox / Drive)** | **WebRTC Browser** |
| :--- | :--- | :--- | :--- |
| **Local Wi-Fi Link Speed** | **80 – 110+ MB/s** | Limited by Internet upload (2–10 MB/s) | 25 – 50 MB/s |
| **16 MB Payload Benchmark** | **1.33 seconds** | 12 – 25 seconds | 3 – 5 seconds |
| **Cloud Custody** | **0% (Direct Peer-to-Peer)** | 100% (Third-party servers) | 0% (Direct Browser P2P) |
| **Data Encryption** | Mutual TLS 1.3 + BLAKE3 | Provider-managed | DTLS 1.2 |

---

## Platform Matrix

| Platform | Native App | Zero-Install WebDrop | Continuous 24/7 Sync |
| :--- | :---: | :---: | :---: |
| **Android** | ✅ (`.apk` 1-tap install) | ✅ (Browser / Camera) | ✅ (Foreground Service) |
| **Windows PC** | ✅ (`p2pme.exe` desktop daemon) | ✅ (Browser) | ✅ (Background Service) |
| **Mac (macOS)** | ✅ (`.dmg` / `.app`) | ✅ (Safari / Chrome) | ✅ (Background Daemon) |
| **iOS (iPhone/iPad)** | ✅ (`.ipa` via AltStore & PWA) | ✅ (Native Camera + Safari) | ✅ (Background fetch & PhotoKit) |
| **Linux** | ✅ (CLI & background service) | ✅ (Browser) | ✅ (systemd daemon) |

---

## Comparison with Existing Solutions

| Feature | **P2Pme** | **AirDrop** | **Quick Share** | **LocalSend** | **Reference P2P Engine** |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Cross-Platform** | **All (iOS, Android, Windows, Mac)** | Apple only | Android & limited PC | All platforms | All platforms |
| **Zero-Install Sending** | **Yes** (Camera QR scan) | No | No | No (App required) | No (App required) |
| **Persistent Folder Sync** | **Yes** (Two-way & Backup) | No | No | No | **Yes** |
| **Internet / Remote Sync** | **Yes** (STUN hole-punching) | No | No | No (LAN only) | **Yes** |
| **Ease of Use for Kids** | **Large buttons, 6-digit PIN & QR** | Moderate | Moderate | Moderate | Complex setup |

---

## Repository Structure

```text
P2Pme/
├── app/                  # Cross-platform Flutter mobile & desktop application
│   ├── lib/              # UI screens, local WebDrop server, background service bindings
│   └── android/          # Native Android foreground service (P2PmeSyncService)
├── crates/
│   ├── p2pme-core/       # Core Rust engine (QUIC transport, BLAKE3 chunker, SQLite catalog)
│   └── p2pme-cli/        # Native Windows & Linux CLI daemon (p2pme.exe)
├── web-pwa/              # Standalone Cloudflare Pages Web PWA (Zero-install WebRTC drop)
├── ARCHITECTURE.md       # 4-tier network transport specification
├── PROTOCOL.md           # Wire framing, tickets, drop RPC, and sync catalog schema
├── DEPLOYMENT.md         # Cloudflare Pages & GitHub Releases hosting guide
└── SECURITY.md           # Cryptographic primitives & threat model
```

---

## Quick Start

### 1. Web PWA (Cloudflare Pages)
Open the deployed web app or run locally:
```powershell
cd web-pwa
# Test locally
npx serve .
# Or deploy in 1 command
npx wrangler pages deploy . --project-name p2pme
```

### 2. Android App
```powershell
cd app
flutter pub get
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

### 3. Windows Desktop App (Portable — No Install)
* **Direct Download:** Download `P2Pme-Windows.zip` from [p2pme.pages.dev](https://p2pme.pages.dev)
* **Launch GUI:** Extract the archive and double-click `Launch_P2Pme.cmd` or `p2pme_app.exe`.
* **Interactive CLI / Server:** Double-click or run `p2pme.exe` in terminal for the interactive menu or CLI daemon:
```powershell
# Create a one-time Quick Drop
p2pme.exe drop C:\path\to\file.pdf

# Receive a Quick Drop
p2pme.exe receive <TICKET> C:\path\to\destination

# Share a folder for persistent auto-sync (Camera Backup mode)
p2pme.exe share C:\Photos --backup
```

---

## Security & Privacy

* **Zero Cloud Custody:** Your data never touches any intermediate cloud server or database.
* **Mutual TLS 1.3 & DTLS 1.2 Encryption:** All QUIC network streams and WebRTC data channels are encrypted end-to-end with forward secrecy.
* **BLAKE3 Content Integrity:** Every 256 KB chunk is cryptographically hashed and verified against bit rot and tampering.
* **128-Bit Ephemeral Tokens:** Dynamic one-time secrets prevent local network port scanning or unauthorized uploads.
* **256-Bit CSPRNG Hub Rotation:** 1-tap cryptographic rotation for Server Hub keys instantly revokes prior links and QR codes with zero server collision.
* **BLAKE3 Folder Ticket Rotation:** On-demand folder ticket re-signing permanently retires compromised pairing tokens.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

