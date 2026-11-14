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

**P2Pme** is a high-performance, decentralized data replication and drop engine. It combines two core workflows in a single, kid-friendly system:

1. **Persistent Automatic Sync:** Continuous two-way synchronization, automated camera roll backups, and Storage-Saver Archive Mode across Windows, Mac, Linux, and Android.
2. **Nearby Wi-Fi 1-Tap Pairing:** Discovers phones and PCs on the same Wi-Fi network instantly without scanning QR codes on monitors or typing tickets.
3. **One-Time Ephemeral Quick Drop:** Single-use, direct device-to-device transfers using 6-digit PIN codes or dynamic QR codes. Drops self-destruct immediately upon receipt without persistent directory tracking.
4. **Portable Windows Desktop App:** Zero installation required. Simply download, extract, and launch `p2pme_app.exe` (or `Launch_P2Pme.cmd`) for full desktop GUI and background replication.
5. **Zero-Install WebDrop & PWA:** Built-in local upload portal and standalone Cloudflare Pages Web PWA. Any iPhone, iPad, PC, or guest can send/receive files over Wi-Fi simply by opening the web app—**zero app installation required** and **auto-updates on every launch**.

---

## Key Features

### 📸 1. One-Time Secure Quick Drop
* **6-Digit PIN & Dynamic QR Code:** Share a simple 6-digit PIN or let nearby devices scan the on-screen QR code.
* **Brute-Force Self-Destruct Lockout:** 3 incorrect PIN attempts automatically wipes the in-memory session.
* **Instant Self-Destruction:** Session and ephemeral cryptographic secrets vanish the moment files are downloaded.
* **10-Minute TTL:** Unclaimed drop sessions automatically expire.

### 🔄 2. Persistent Auto-Sync Folders
* **Two-Way Synchronization:** Real-time delta replication using content-addressed BLAKE3 block chunking.
* **1-Tap Camera Backup:** Backs up `/DCIM/Camera` in Read-Only mode to your PC, NAS, or hard drive.
* **Storage-Saver Archive Mode:** Deleting photos/files on your phone to free up space does **not** delete them from your backup node.
* **Android 24/7 Foreground Service:** Keeps sync active when the phone screen is locked or the app is minimized, with 0% battery usage when toggled OFF.

### 🌐 3. Zero-Install WebDrop & Cloudflare Pages PWA
* **iPhone & Guest Friendly:** Friends and family on iOS can point their native camera at your screen's QR code to send or receive files directly in Safari.
* **128-Bit Ephemeral Security Token:** Protects your local Wi-Fi receiver against LAN port scanning and unauthorized uploads (`403 Forbidden` on untrusted requests).
* **Installable PWA:** Tap Safari **Share &rarr; Add to Home Screen** on iOS or Android to install P2Pme as a standalone web app with zero app store downloads.

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
| **iOS (iPhone/iPad)** | ✅ (PWA "Add to Home Screen") | ✅ (Native Camera + Safari) | Opportunistic |
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
* **Mutual TLS 1.3 Encryption:** All QUIC network streams are encrypted end-to-end with forward secrecy.
* **BLAKE3 Content Integrity:** Every 256 KB chunk is cryptographically hashed and verified against bit rot and tampering.
* **128-Bit Ephemeral Tokens:** Dynamic one-time secrets prevent local network port scanning or unauthorized uploads.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

