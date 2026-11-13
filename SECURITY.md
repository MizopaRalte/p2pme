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

---

## 3. Reporting a Vulnerability

If you discover a security issue or vulnerability in P2Pme, please report it privately via GitHub Security Advisories or by emailing the project maintainers.

