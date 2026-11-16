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
* **6-Digit PIN & WebDrop Over Internet:** Send to any device worldwide with a 6-digit PIN code or zero-install browser link (`https://p2pme.pages.dev`).
* **Self-Destructing Ephemeral Security:** 3 incorrect PIN attempts wipe the session instantly; sessions automatically expire in 10 minutes.

### 🔄 2. Backup Tab: Continuous Background Sync
* **Instant Camera QR Server Pairing:** 1-tap connection to your 24/7 Server Hub. Tap "Scan Server QR Code" on your sending phone (e.g. iPhone) and point at the Server Hub screen (e.g. Android phone or PC). Automatically parses IP, port, remote WAN address, and 256-bit CSPRNG security tokens for instantaneous zero-typing pairing.
* **Multi-Transport Connection Tiers:**
  * **⚡ Tier 1 (Direct USB Cable):** Hardware wire speed (35–400+ MB/s) with 0% packet loss and zero Wi-Fi required via USB tethering / USB-to-USB link.
  * **📶 Tier 2 (Local Wi-Fi Direct):** Full wire-speed LAN socket streaming (80–110 MB/s) on home Wi-Fi.
  * **🌐 Tier 3 (Internet Mesh / WAN):** Automatic fallback to Tailscale mesh (`100.x.x.x`) or remote IP when away from home on 5G/cellular data.
* **Persistent Server State (Zero Disappearing Hubs):** Remembers paired servers across app restarts and network switches. Displays high-contrast status badges (`✓ Live (Wi-Fi)`, `⚡ Live (USB Cable)`, `🌐 Live (Remote Mesh)`, `⏳ Waiting for connection / Cellular`) with manual Reconnect/Ping and safe Unpair confirmation.
* **Unlimited Camera Roll Scanning:** Removed the artificial 500-photo ceiling. Full PhotoKit and Android DCIM indexing processes libraries of any size (596+ items) with zero truncation.
* **Real-time Wire-Speed Telemetry:** Live throughput monitoring directly on the backup card displaying real-time speed in `MB/s` alongside current file progress.
* **1-Tap Pause & Resume:** Pause active backup transfers on demand at any time to preserve battery or bandwidth, and resume when ready without losing progress.
* **1-Tap Camera Roll Auto-Backup:** Automatically tracks and replicates your photos/videos directly to your computer or backup server in full original quality.
* **Storage-Saver Archive Mode:** Free up storage on your phone by deleting local photos—synced copies on your PC/server remain safe and untouched.
* **Folder Management & Instant Deletion:** Easily add folders (Camera Roll, WhatsApp Media, or any custom folder) and remove them from sync with 1 tap without losing local files.
* **Folder QR & Ticket Sharing:** View and share pairing tickets or QR codes for any synced folder to pair directly with Windows (`p2pme join <ticket>`) or another phone.
* **1-Tap Ticket Regeneration & Revocation:** Securely revoke and generate a brand-new BLAKE3 folder pairing ticket with a single tap, instantly retiring older tickets to guarantee zero conflict.

### 🖥️ 3. Server Tab: 24/7 Backup Hub & Receiver
* **Turn Any Device into a Server:** Toggle 24/7 Backup Server mode to accept incoming drops and continuous backups with background keep-alive.
* **Dual-Endpoint Pairing (LAN + Remote/WAN):** Configure an optional Remote / WAN Endpoint (e.g. Tailscale IP or domain). QR code embeds `&wan=...` for seamless zero-config pairing across both LAN and internet.
* **⚡ Direct USB Cable Interface Detection:** Automatically discovers active USB tethering interfaces (`rndis`, `usb`, `ncm`, `cdc`) and exposes them for direct cable backup.
* **Live Ingestion Telemetry & Speed Meter:** Displays real-time incoming transfer speeds (`MB/s`), active receiving file names, and dynamic progress bars for both server and sender.
* **Custom Save Destination Folder:** Choose exactly where received files and folder backups land on disk (e.g. internal storage, external SD card, or desktop path).
* **Direct Server Ticket & Dynamic QR Code:** Connect new client devices to your hub using a master server pairing code or direct LAN socket (`http://<ip>:45455`).
* **1-Tap Zero-Conflict Key Regeneration:** Rotate your Server Hub Secret Key (256-bit CSPRNG) on demand with 1 tap. Immediately revokes older QR codes and browser links with zero server collisions.
* **Battery Optimization Management:** Visual indicator and 1-tap shortcut to disable OS battery throttling on Android for uninterrupted background replication.

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

