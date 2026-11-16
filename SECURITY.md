# Security Policy & Architecture

## Security Overview

**P2Pme** is designed from the ground up on the principle of **Zero Cloud Custody**. No user data, metadata, file directories, or encryption keys ever transit through or reside on third-party servers.

---

## 1. Cryptographic Primitives

* **Network Encryption:** Transport Layer Security (**TLS 1.3**) over **QUIC** (UDP) via the `quinn` Rust stack. Mutual authentication with ephemeral self-signed X.509 certificates generated per node session.
* **Content Addressing & Integrity:** **BLAKE3** cryptographic tree hashing. Every 256 KB block is verified independently upon receipt to guarantee zero data corruption or tampering.
* **Ephemeral Secrets:** 128-bit cryptographically random tokens generated via system CSPRNG (`getrandom` / `Random.secure()`).

---

## 2. Threat Model & Mitigations

### A. Local Network & Wi-Fi Protection
* **Risk:** Unauthorized clients on the same Wi-Fi (e.g. coffee shop, airport) port-scanning port 45455 to upload unauthorized files.
* **Mitigation:**
  * **128-Bit Dynamic Session Token:** The embedded local receiver requires a dynamic token (`?token=<SECRET>`) passed in the query or header. Requests without this token receive an immediate `403 Forbidden`.
  * **Token Invalidation:** Users can cycle the token instantly with the refresh button `↻`, immediately invalidating any open sessions.

### B. Brute-Force PIN Attacks
* **Risk:** An attacker guessing 6-digit drop PINs (1,000,000 combinations).
* **Mitigation:**
  * **3-Attempt Self-Destruct:** If a connecting peer enters an incorrect PIN 3 times, the in-memory session is permanently destroyed.
  * **10-Minute TTL:** All ephemeral drop sessions automatically expire after 10 minutes.

### C. Directory Escape & Path Traversal
* **Risk:** A malicious sender providing filenames such as `../../etc/passwd` or `..\..\Windows\System32`.
* **Mitigation:**
  * Incoming filenames are stripped of all directory separators (`/`, `\`), null bytes, and non-printable characters.
  * Files are strictly written to the designated destination directory.
  * Executable file types (`.exe`, `.apk`, `.sh`, `.bat`) are blocked over browser upload portals.

### D. OTA Updates & Software Supply Chain Security
* **Risk:** Tampering with update packages or man-in-the-middle attacks on the update check.
* **Mitigation:**
  * **HTTPS Edge Delivery:** Update metadata (`version.json`) and release packages are delivered over TLS 1.3 via Cloudflare Pages edge network with HSTS enabled.
  * **Origin Pinning:** The mobile and desktop clients strictly validate the update source against the official `https://p2pme.pages.dev` origin.
  * **Zero Remote Execution:** The update checker only downloads the standalone APK or zip binary and never executes arbitrary remote scripts or dynamic code.

### E. UDP Local Beacon Privacy
* **Risk:** Sniffing UDP broadcast beacons on port 42424 on shared Wi-Fi networks.
* **Mitigation:**
  * Broadcast beacons contain only node display names and ephemeral receiver session tokens.
  * No file names, folder structures, or device private keys are ever transmitted over broadcast beacons.
  * Any transfer connection requires the ephemeral token and mutual user acceptance or pairing ticket verification.

### F. Key Rotation & Zero-Conflict Revocation
* **Risk:** A client retaining an old QR code or WebDrop URL and continuing to access a Server Hub or synchronized folder after permissions should have expired.
* **Mitigation:**
  * **256-Bit CSPRNG Server Hub Secrets:** Hub secret keys are generated using system CSPRNG (`crypto.getRandomValues()` / `Random.secure()`).
  * **1-Tap Dynamic Rotation:** Users can rotate the secret key on demand from Tab 3. Rotating the key updates the in-memory and persistent secret immediately, rendering all previously shared QR codes and browser links (`?key=...`) completely unusable (HTTP 403 Forbidden).
  * **BLAKE3 Folder Ticket Invalidation:** Regenerating folder tickets re-derives the ticket with a new timestamp nonce, retiring older tickets to guarantee zero conflict.

### G. Camera QR Code & Authorization Boundaries
* **Risk:** Malicious or malformed QR codes scanned by the client camera causing injection attacks, unauthorized server connection, or credential theft.
* **Mitigation:**
  * **Strict URI Parsing & Host Sanitization:** Scanned QR payloads are strictly validated using RFC-compliant URI parsers. Non-HTTP and non-P2Pme schemes are rejected. Hostnames and IP addresses are sanitized before network sockets are opened.
  * **Authorization Isolation:** Server Hub secret tokens extracted from QR codes are scoped exclusively to the target peer and never leaked across other network interfaces or third-party servers.
  * **Zero Cloud Intermediaries:** Device pairing handshakes occur directly over the local network via peer-to-peer HTTP/WebSockets with zero telemetry or cloud logging.

### H. Direct USB Cable & Link-Local Network Isolation
* **Risk:** Connecting untrusted hardware over USB tethering or exposing services to hostile interfaces.
* **Mitigation:**
  * **Cryptographic Token Enforcement on All Adapters:** P2Pme binds to wildcard sockets to service USB CDC-NCM / RNDIS links, but enforces the exact same 256-bit CSPRNG authorization secret on USB connections as on Wi-Fi and WAN.
  * **Isolated Subnet Sandboxing:** USB tethering assigns private link-local subnets (e.g. `192.168.42.0/24` or `172.20.10.0/28`) that do not bridge to wide area networks or route external traffic without explicit host forwarding.
  * **Physical Wire Guarantee:** Cable transfers are physically shielded from airborne radio sniffing and packet interception.

### I. Remote WAN & Encrypted Mesh (Tailscale/WireGuard) Boundaries
* **Risk:** Exposure of server endpoints when configuring external WAN URLs or operating across public cellular networks.
* **Mitigation:**
  * **Encrypted Mesh Overlays:** P2Pme strongly recommends overlay networks (Tailscale, WireGuard, Netbird) where all packets are end-to-end encrypted with Noise/ChaCha20-Poly1305 before leaving the device.
  * **Strict Key Authentication:** WAN requests require the identical 256-bit server token (`?key=...` or `X-P2Pme-Key`). Unauthenticated probes are dropped immediately with 403 Forbidden without exposing filesystem paths.
  * **Constant-Time Verification:** Server token matching is performed using constant-time string comparisons to eliminate timing side-channel exploits.

### J. Storage Boundaries, Persistence & Disk-Full DoS Prevention
* **Risk:** Ingestion stream exhausting device storage (`ENOSPC`) causing OS crashes, database corruption, or app instability; or OS cache cleaners purging pairing state on updates.
* **Mitigation:**
  * **Permanent Documents Sandbox:** Synced asset index records (`p2pme_synced_camera_assets.json`) and configuration profiles (`.p2pme_config.json`) are stored strictly within OS-protected persistent documents directories (`$HOME/Documents` on iOS and `/data/data/.../files` on Android), guaranteeing survival across OS cache purges and app updates.
  * **Storage Pre-Flight Protection:** Prior to writing incoming file streams, the server verifies remaining disk capacity via native APIs (`StatFs` on Android, `volumeAvailableCapacityForImportantUsageKey` on iOS). Ingestion is rejected with `HTTP 507 Insufficient Storage` if free space is below safety margins (< 50 MB).
  * **Atomic Cleanup on Exception:** If an out-of-space event occurs mid-stream, partial file handles are closed and immediately unlinked/deleted from disk, preventing rogue disk consumption and allowing the client to gracefully auto-pause and auto-resume once space is cleared.

### K. Zero Key Leakage in Discovery & Polling Safety
* **Risk:** Information disclosure of cryptographic material via unauthenticated discovery endpoints; client battery and network exhaustion during extended disk-full events.
* **Mitigation:**
  * **Complete Secret Key Isolation:** The unauthenticated `/api/info` discovery probe returns boolean configuration flags (`hub_configured: true`) only. All partial key hints (`hub_key_hint`) have been completely eradicated, preventing LAN attackers from reducing cryptographic entropy.
  * **Bounded Polling Windows:** Storage retry loops on HTTP 507 are bounded to 60 iterations (5 minutes maximum), terminating cleanly with persistent user feedback rather than hanging in infinite network polling loops.


---

## 3. Reporting a Vulnerability

If you discover a security issue or vulnerability in P2Pme, please report it privately via GitHub Security Advisories or by emailing the project maintainers.

