# P2Pme System Architecture

## 1. Executive Overview

**P2Pme** is a high-performance, decentralized, end-to-end encrypted peer-to-peer data replication and transfer system. It connects devices directly across local networks (LAN) and the global internet (WAN) with zero third-party data custody.

---

## 2. System Architecture Layers

```mermaid
flowchart TD
    subgraph UI_Layer ["Surface Layer (Flutter Mobile & Desktop Shell)"]
        Tab1["🚀 Transfer Tab\n(1-Time Nearby Beam & Internet PIN Drop)"]
        Tab2["🔄 Backup Tab\n(Resilio-Style Continuous Sync & Folder Watchers)"]
        Tab3["🖥️ Server Tab\n(24/7 Dedicated Hub & Custom Destination Picker)"]
        FGS["Android Foreground Service (Keep-Alive & Battery Whitelist)"]
        Tab2 --> FGS
        Tab3 --> FGS
    end

    subgraph FFI_Bridge ["FFI & Binding Layer"]
        UniFFI["UniFFI / Dart FFI Native Bindings"]
        CLI["P2Pme CLI Daemon (p2pme.exe)"]
        UI_Layer --> UniFFI
        CLI --> Core
        UniFFI --> Core
    end

    subgraph Core_Engine ["P2Pme Core Native Engine (Rust)"]
        Core["P2Pme Node Controller"]
        
        subgraph Net_Stack ["Network & Transport Engine"]
            QUIC["QUIC Protocol (UDP)"]
            MagicSock["Endpoint Switcher (MagicSocket)"]
            mDNS["Local Discovery (mDNS & Subnet Probe)"]
            STUN["STUN & UDP Hole-Puncher"]
            DERP["Zero-Knowledge Encrypted Relay Client"]
            
            MagicSock --> mDNS
            MagicSock --> STUN
            MagicSock --> DERP
            QUIC --> MagicSock
        end

        subgraph Transfer_Engine ["Replication & Storage Engine"]
            Chunker["BLAKE3 / Bao Tree Streaming Chunker"]
            Catalog[("SQLite Local State Catalog\n(tracked_files, tombstones, chunks)")]
            Watcher["Filesystem Event Monitor (notify)"]
            
            Core --> Chunker
            Core --> Catalog
            Core --> Watcher
        end

        Core --> Net_Stack
    end
```

---

## 3. The 4-Tier Multi-Network Transport

To guarantee 100% connectivity between any two devices globally, P2Pme uses an adaptive multi-tier transport hierarchy:

| Tier | Network Path | Mechanism | Latency / Speed | Offline? |
| :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | **Direct LAN** | mDNS + Multicast UDP discovery | Sub-millisecond / Full LAN wire-speed (1–10 Gbps) | **Yes** (100% offline) |
| **Tier 2** | **Direct WAN (Router)** | UPnP / NAT-PMP port mapping | Internet ping / Full ISP line speed | No |
| **Tier 3** | **Direct WAN (Punched)** | STUN + UDP Hole Punching | Direct UDP path / Full ISP line speed | No |
| **Tier 4** | **Encrypted Relay** | DERP packet forwarder | Proxied / Bandwidth capped by relay | No |

### Connection Fallback Lifecycle
1. When two devices pair via an authentication ticket or QR code, both nodes announce themselves to the local subnet via mDNS while simultaneously contacting STUN.
2. If both peers are on the same Wi-Fi, the connection locks to the LAN address for maximum bandwidth.
3. If peers are on separate networks, STUN probes public IP/port candidates and initiates simultaneous UDP hole punching.
4. If a carrier-grade symmetric NAT (such as mobile 5G) blocks the direct hole punch, both peers establish encrypted sessions with a DERP relay node. The relay sees only encrypted bytes (TLS 1.3 / Noise protocol) and cannot inspect content.

---

## 4. Storage, Chunking & State Reconciliation

### A. BLAKE3 & Bao-Tree Verified Streaming
* Large files are partitioned into verified content-addressed blocks.
* Each block is hashed using **BLAKE3**, offering hashing speeds exceeding 4 GB/s.
* Out-of-order block streaming allows receiving devices to verify each block's cryptographic proof immediately upon arrival, enabling parallelized multi-stream downloads directly into pre-allocated sparse storage.

### B. SQLite Metadata Catalog
The local catalog tracks state persistently using SQLite with Write-Ahead Logging (WAL):
* `tracked_files`: Records file path, content hash, size, modification timestamp (`mtime`), and synchronization state.
* `tombstones`: Records deletions. When a file is removed, its tombstone propagates across peers so the file is deleted on other devices instead of being treated as missing and re-downloaded.
* `block_manifest`: Maps individual block ranges to hashes for delta-level transfers.

---

## 5. Security Model

1. **Cryptographic Identity:**
   Every device generates an ed25519 keypair on first run. The public key serves as the permanent Device Node ID.
2. **End-to-End Encryption:**
   All wire communications are encrypted using mutual TLS 1.3 / Noise protocol over QUIC. No plaintext headers or metadata leave the device.
3. **Capability-Based Access:**
   * **Read-Write Ticket:** Full permission to push and pull modifications.
   * **Read-Only Ticket:** Can receive data and updates, but cannot sign or push file modifications.
   * **Pairing Expiration:** Temporary pairing codes / QR codes with configurable timeouts.

---

## 6. Distribution, Updates & Deployment Model

P2Pme is architected to operate without mandatory app store monopolies, supporting frictionless peer distribution and transparent updates:

### A. Web PWA (iOS & Desktop Browsers)
* **Hosting:** Cloudflare Pages edge network (`https://p2pme.pages.dev`).
* **Auto-Updates:** Service Worker (`sw.js`) with `self.skipWaiting()` and `self.clients.claim()` using a **Network-First** caching strategy. When a user opens the web app or iOS Home Screen PWA, updated assets are retrieved instantly in the background without user intervention.

### B. Windows Portable Application
* **Zero-Installation Architecture:** Distributed as a standalone zip archive (`P2Pme-Windows.zip`) containing `p2pme_app.exe` (Flutter desktop shell), `p2pme.exe` (Rust native engine daemon), and required runtime DLLs.
* **No Elevated Privileges:** Runs entirely in user space without requiring administrator permissions, registry modification, or system hooks.
* **Responsive Desktop Viewport:** Optimized desktop layout centered to 880px content width with ergonomic navigation.

### C. Android Native Application
* **Distribution:** Direct release APK (`P2Pme.apk` targeted at `arm64-v8a` and universal ABI).
* **In-App Update Checker:** On startup or user request, the application queries `https://p2pme.pages.dev/version.json`. If a higher `version_code` is detected, a non-intrusive banner notifies the user with a 1-tap download and update link.

---

## 7. Nearby Wi-Fi Discovery & Pairing

```mermaid
sequenceDiagram
    autonumber
    participant Phone as Mobile / Sender (Android/iOS)
    participant Subnet as Local Wi-Fi Subnet (Broadcast)
    participant Desktop as Computer / Receiver (Windows)

    Note over Phone,Desktop: Both devices connected to same Wi-Fi
    Desktop->>Subnet: UDP Broadcast on Port 42424 (P2Pme Beacon)
    Note over Subnet: Payload: { p2pme: true, name: "PC", http_port: 45455, token: "..." }
    Phone->>Subnet: Listen / Announce on Port 42424
    Phone->>Desktop: Direct LAN HTTP Connection (Direct Drop / Folder Sync)
    Desktop-->>Phone: TLS/Token Verified Transfer Stream
```

1. **UDP Broadcast Beacon:** Nodes on the local Wi-Fi subnet broadcast discovery packets on UDP port `42424` containing node name, endpoint, and dynamic session token.
2. **Immediate 1-Tap Connection:** Nearby devices appear instantly in the UI with signal and IP metadata. Tapping connects directly via LAN wire-speed.
3. **Dynamic IP Tolerance:** Device IP addresses (e.g., `192.168.x.x`) assigned by DHCP can change dynamically; the beacon protocol re-advertises new network endpoints automatically without requiring manual re-configuration.


