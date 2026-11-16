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

---

## 3. Reporting a Vulnerability

If you discover a security issue or vulnerability in P2Pme, please report it privately via GitHub Security Advisories or by emailing the project maintainers.

