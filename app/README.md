# P2Pme Flutter Application (Mobile & Desktop Shell)

The official Flutter-based user interface and platform binding layer for **P2Pme**. It provides an intuitive Google Photos-inspired design aesthetic across Android, iOS, and Windows.

---

## 1. Architecture & Tab Design

The application implements a streamlined **3-Tab Architecture**:

1. **🚀 Transfer Tab (`lib/main.dart`):**
   * **1-Tap Nearby Beam:** Local subnet discovery of active P2Pme nodes over Wi-Fi and direct USB tethering.
   * **Internet PIN Drop:** Ephemeral 6-digit PIN transfers over WAN with automatic RFC 5389 STUN socket discovery and Cloudflare Pages edge rendezvous (`/api/drop/announce` & `/api/drop/resolve`).
   * **Receiver Destination Picker:** Allows selecting internal or custom directories before receiving files, with default path persistence.
   * **Decoupled PIN Protection:** PINs are never embedded into QR codes or serialized tickets.

2. **🔄 Backup Tab:**
   * **Continuous Folder Replication:** Background synchronization for camera rolls, WhatsApp media, and custom user folders.
   * **Storage-Saver Archive Mode:** Local deletion of backed-up photos while safely retaining copies on the 24/7 hub.
   * **Mtime-Cached Hashing:** Eliminates redundant BLAKE3 recalculation on unmodified files using filesystem metadata cache in SQLite.
   * **Bidirectional Telemetry:** Real-time transfer speed, batch volume, file counters, and sender-controlled pause/resume controls.

3. **🖥️ Server Tab:**
   * **24/7 Dedicated Hub & Receiver:** Runs a dedicated local HTTP/WebSocket ingestion service on port `45455`.
   * **Unified Master Switch:** Persistent server state with automated background wakelock and Wi-Fi lock acquisition.
   * **Multi-Stream Session Isolation:** Handles concurrent uploads from multiple household devices in thread-isolated receiver sessions.
   * **Storage Telemetry & Protection:** Exposes real-time free disk capacity to senders and defends against storage exhaustion (`HTTP 507 Insufficient Storage`).
   * **256-Bit Hub Key Rotation:** 1-tap regeneration of Server Hub secret keys, immediately revoking all previously issued QR codes and browser links.

---

## 2. Platform Integrations

### Android (`android/`)
* **Foreground Service (`P2PmeSyncService.kt`):** Runs continuous replication tasks with persistent notification and OS priority.
* **Power Management:** Holds `PARTIAL_WAKE_LOCK` and `WIFI_MODE_FULL_HIGH_PERF` to prevent the OS from throttling transfers when the screen turns off.
* **Scoped Storage & SAF:** Native permission gating for Android 11+ (`MANAGE_EXTERNAL_STORAGE`) when custom external directories are targeted.
* **USB Interface Discovery:** Dynamically detects active CDC-NCM and RNDIS network interfaces for direct USB cable transfers.

### iOS (`ios/`)
* **PhotoKit Integration:** Queries system assets while automatically filtering out screenshots and screen recordings (`PHAssetMediaSubtype.photoScreenshot` and `videoScreenRecording`).
* **Dynamic Hardware Identity:** Uses `UIDevice.current.name` to identify peer devices seamlessly without placeholder labels.
* **Background Fetch:** Integrates with iOS background task scheduling for opportunistic photo replication.

### Windows (`windows/`)
* **Window Management:** Frameless window controls, ergonomic sizing, and desktop centering via `window_manager`.
* **Daemon Integration:** Communicates with the native Rust core (`p2pme.exe`) via Dart FFI and local loopback RPC.

---

## 3. Development & Build Instructions

### Prerequisites
* Flutter SDK (3.13+)
* Dart SDK (3.1+)
* Android SDK (API 34) & Java 17 (for Android builds)
* Xcode (for iOS builds, macOS only)
* Visual Studio C++ toolchain (for Windows desktop builds)

### Development Commands
```powershell
# Fetch dependencies
flutter pub get

# Run static analysis
flutter analyze

# Launch on connected device or desktop
flutter run

# Build split Android release APKs
flutter build apk --split-per-abi

# Build Windows desktop bundle
flutter build windows --release
```

### Automated Release
Releases are automated via the root release pipeline:
```powershell
python ../scripts/release.py <version> "<release_notes>"
```
