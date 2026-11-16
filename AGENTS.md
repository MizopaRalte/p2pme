# P2Pme Project Rules & Quality Standards

This document defines the mandatory engineering and operational rules for developing, maintaining, and releasing P2Pme across all supported platforms. Every agent, contributor, and automated workflow MUST strictly adhere to these principles.

---

## 1. Cross-Platform Parity Rule (Zero Platform Disparity)

1. **All Platforms Must Reflect All Changes:**
   * Every new feature, UI redesign, architectural improvement, or bug fix must be implemented and synchronized across **all supported platforms**:
     - **Android Native** (`app/android/`, APK releases)
     - **iOS Native & Sideloading** (`app/ios/`, AltStore Source, IPA releases)
     - **Windows Desktop** (`crates/p2pme-cli/`, Flutter desktop shell, portable zip)
     - **Web PWA** (`web-pwa/`, Cloudflare Pages edge distribution)
   * **Partial platform updates are strictly prohibited.** Releasing an update on Android while leaving iOS or Web PWA on older compiled binaries creates state conflicts, confuses users, and breaks cross-platform pairing.

2. **Genuine Binary Compilation for iOS:**
   * iOS Mach-O binaries (`App.framework`) cannot be compiled on Windows or Linux — Apple strictly requires macOS and Xcode.
   * Whenever Dart/Flutter changes are made, the code must be pushed to GitHub (`git push origin main`) to trigger the automated macOS cloud runner (`.github/workflows/build-release.yml`).
   * The resulting macOS-compiled `p2pme-ios-ipa` artifact must be downloaded, verified, and placed into `web-pwa/downloads/` alongside updated `altstore-source.json` and `version.json` metadata before deployment.

---

## 2. Mandatory Verification Gates: Security, Performance & UI/UX

Before any release or feature is declared complete, it must pass all three verification gates:

### Gate A: Security Verification
* **Cryptographic Strength:**
  - Ephemeral transfer tokens: Minimum 128-bit CSPRNG.
  - Server Hub secret keys: Minimum 256-bit CSPRNG (`crypto.getRandomValues()` / `Random.secure()`).
  - Folder pairing tickets: BLAKE3 cryptographic hash derivation with timestamped nonces.
* **Zero-Conflict & Revocation Guarantee:**
  - When a user regenerates a Server Secret Key or Folder Ticket, all previously issued links, QR codes, and cached credentials must be immediately invalidated.
  - Incoming requests using stale or revoked keys must be rejected with HTTP 403 Forbidden.
* **Network & Header Hardening:**
  - All WebRTC and QUIC data channels must use DTLS 1.2 / TLS 1.3 with forward secrecy.
  - Web PWA headers (`_headers`) must enforce `Content-Security-Policy`, `X-Content-Type-Options: nosniff`, and `Strict-Transport-Security`.

### Gate B: Performance Verification
* **Wire-Speed Throughput:** Local Wi-Fi direct transfers must sustain 80 – 110+ MB/s over native QUIC and 30 – 50 MB/s over WebRTC.
* **Zero Main-Thread Blocking:** File hashing (BLAKE3), filesystem scanning, and network discovery must run on background isolates or worker threads, ensuring the UI maintains a constant 60+ FPS.
* **Streaming & Low Memory Footprint:** Files must be transferred in verified 256 KB streaming chunks. Large files (e.g. 10 GB+ 4K video) must never be loaded entirely into RAM.

### Gate C: UI/UX & Accessibility Verification
* **Consistent Design System:** Follow the Google Photos minimalist design aesthetic (primary colors: `#1A73E8` Blue, `#1E8E3E` Green, `#F9AB00` Yellow, `#D93025` Red; clean rounded cards; high-contrast labels).
* **Streamlined 3-Tab Architecture:**
  - **Tab 1 (Transfer):** One-time 1-tap beam to nearby devices or 6-digit PIN over internet.
  - **Tab 2 (Backup):** Continuous background folder sync, camera roll auto-backup, and folder pairing tickets.
  - **Tab 3 (Server):** 24/7 dedicated hub, custom destination folder picker, master pairing QR, and battery optimization settings.
* **Safe User Safeguards:** Destructive actions (such as removing a synchronized folder or regenerating keys) must always prompt the user with clear confirmation dialogs explaining the consequence.
* **Mobile & Desktop Ergonomics:** Touch targets must be at least 48x48 dp. Desktop layouts must center content with appropriate max-width constraints.

---

## 3. Synchronous Documentation Rule

Whenever code, architecture, wire protocols, UI layouts, or version numbers change, the following documents MUST be updated synchronously in the same commit:

1. **`README.md`**: Update feature descriptions, tab workflows, platform matrix, and quick-start instructions.
2. **`ARCHITECTURE.md`**: Update layer diagrams (Mermaid), network transport tiers, and distribution models.
3. **`PROTOCOL.md`**: Update ticket schemas, SQLite catalog definitions, and wire communication sequences.
4. **`SECURITY.md`**: Document cryptographic primitives, revocation lifecycles, and threat mitigations.
5. **In-App Help & Web Help**: Keep the in-app help modal and the Web PWA help cards updated with accurate instructions matching the live UI.

---

## 4. Online Verification Standard (Definition of Done)

A task or release is **ONLY COMPLETE** when:
1. Code is tested locally and verified against edge cases.
2. Android APK and iOS IPA packages are genuinely compiled and placed in `web-pwa/downloads/`.
3. `version.json` and `altstore-source.json` contain matching version strings, build numbers, file sizes, and SHA-256 checksums.
4. All assets are deployed live to Cloudflare Pages (`https://p2pme.pages.dev`).
5. Live endpoints have been fetched via HTTP to verify that the remote CDN serves the exact expected content without stale caching.
6. The official Git release tag (`vX.Y.Z`) is created and pushed to GitHub (`git push origin vX.Y.Z`), and the official GitHub Release is published with all binary assets (APK, IPA, Windows zip, and SHA-256 checksums).
