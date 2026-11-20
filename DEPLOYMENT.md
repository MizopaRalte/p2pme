# Deployment & Release Guide: P2Pme Across All Platforms

This guide documents the architecture and operational procedures for deploying **P2Pme** to Cloudflare Pages, GitHub Releases, and across all target platforms with **Zero Platform Disparity**.

---

## 1. Architecture & Hosting Overview

P2Pme operates with **Zero Cloud Custody** and requires no central database or hosted server backend:

* **Edge CDN & Web PWA:** Hosted globally on [Cloudflare Pages](https://pages.cloudflare.com/) (`https://p2pme.pages.dev`). Serves the standalone PWA, edge signaling functions, and binary download assets.
* **Edge Signaling Functions:** Serverless edge functions located in `functions/` (`api/drop/announce`, `api/drop/resolve`, `api/hub/register`, `api/hub/resolve`) providing transient zero-custody STUN and PIN rendezvous routing.
* **Binary Distribution:** Official GitHub Releases host signed Android APKs, genuine macOS-compiled iOS IPAs, and Windows portable ZIPs with cryptographic SHA-256 checksums.
* **iOS AltStore Source:** Published at `https://p2pme.pages.dev/altstore-source.json` for 1-tap installation and automated background refresh via AltStore and SideStore.

---

## 2. Cloudflare Pages Configuration

### Option A: Automated Git Integration
1. In Cloudflare Dashboard, navigate to **Workers & Pages** &rarr; **Create application** &rarr; **Pages** &rarr; **Connect to Git**.
2. Select the `MizopaRalte/p2pme` repository.
3. Build Settings:
   * **Project name:** `p2pme`
   * **Production branch:** `main`
   * **Framework preset:** `None`
   * **Build command:** *(leave empty)*
   * **Build output directory:** `web-pwa`
4. The root `functions/` directory is automatically detected and compiled as Cloudflare Pages Functions.

### Option B: Terminal Edge Deployment via Wrangler
Deploying directly from local machine:
```powershell
npx wrangler pages deploy web-pwa --project-name p2pme --branch main --commit-dirty=true
```

---

## 3. Mandatory One-Command Release Pipeline

In accordance with project engineering rules (`AGENTS.md` / `GEMINI.md`), **manual, piecemeal release steps are strictly prohibited**. All releases must be executed via the unified automation script:

```powershell
python scripts/release.py <version> "<release_notes>"
```

### Example:
```powershell
python scripts/release.py 1.3.3 "Security hardening & global internet P2P transfer via STUN and edge signaling"
```

### What the Pipeline Enforces Sequentially:
1. **Version Code Synchronization:** Bumps version strings and increments build codes in `pubspec.yaml`, `app/lib/main.dart`, `web-pwa/version.json`, and `web-pwa/index.html`.
2. **Android Release Compilation:** Compiles signed split-per-abi release APKs (`cd app && flutter build apk --split-per-abi`). Generates SHA-256 checksums and places them in `web-pwa/downloads/`.
3. **Synchronous Git Tagging:** Commits all version updates, creates an annotated Git tag (`vX.Y.Z`), and force-pushes `main` and tags to GitHub.
4. **macOS Cloud Runner Orchestration:** The push triggers GitHub Actions workflow `.github/workflows/build-release.yml` on a `macos-latest` cloud runner with Xcode and Flutter.
5. **iOS IPA Retrieval & Verification:** The script polls GitHub Actions, downloads the genuine macOS-compiled `p2pme-ios-ipa` artifact, validates its file size and SHA-256 checksum, and places it into `web-pwa/downloads/P2Pme-v<version>.ipa` and `P2Pme.ipa`.
6. **AltStore Source & Version API Sync:** Updates `web-pwa/altstore-source.json` and `web-pwa/version.json` with matching version codes, release dates, exact byte counts, and SHA-256 hashes.
7. **Cloudflare Pages Edge Deployment:** Deploys all static assets and the compiled `functions/` bundle to Cloudflare Pages edge via Wrangler.
8. **Official GitHub Release Publication:** Creates or updates GitHub Release `vX.Y.Z` and attaches all 7 mandatory release assets:
   - `P2Pme-v<version>.apk`
   - `P2Pme.apk`
   - `P2Pme-v<version>.ipa`
   - `P2Pme.ipa`
   - `P2Pme-Windows.zip`
   - `P2Pme.apk.sha256`
   - `P2Pme.ipa.sha256`
9. **Final Metadata Commit:** Commits the finalized `altstore-source.json` and `version.json` to `main`.
10. **Automated Online Verification Gate:** Runs `scripts/verify-release.py` to test remote HTTP endpoints and verify zero platform disparity.

---

## 4. Post-Release Verification (`scripts/verify-release.py`)

Run at any time to verify remote CDN and GitHub parity:
```powershell
python scripts/verify-release.py
```

Checks performed:
- `https://p2pme.pages.dev/version.json` matches target version code.
- `https://p2pme.pages.dev/altstore-source.json` matches version code and IPA SHA-256.
- GitHub Release `vX.Y.Z` contains all 7 mandatory assets with matching filenames.

---

## 5. End-User Installation Guide

### Android
* Download `P2Pme.apk` from [p2pme.pages.dev](https://p2pme.pages.dev) or the GitHub Release.
* Tap to install. Android 11+ users granting custom folder backup paths will be guided through Scoped Storage settings.

### iOS (iPhone & iPad)
1. **AltStore & SideStore (Recommended):**
   * Add AltStore Source: `https://p2pme.pages.dev/altstore-source.json`.
   * Tap install to sideload `P2Pme.ipa`. SideStore provides automated on-device Wi-Fi refreshes without requiring a PC.
2. **Permanent Installation (TrollStore):**
   * On iOS 14.0–17.0 devices supporting TrollStore (CoreTrust vulnerability), open `P2Pme.ipa` in TrollStore for permanent install with zero 7-day expiration.
3. **Sideloadly (PC & Mac):**
   * Drag `P2Pme.ipa` into Sideloadly and enable automatic Wi-Fi refresh.
4. **Instant Safari Web PWA:**
   * Open `https://p2pme.pages.dev` in Safari.
   * Tap **Share** &rarr; **Add to Home Screen**. Full-screen photo browsing and 1-tap backup with zero install.

### Windows Desktop (Portable)
* Download `P2Pme-Windows.zip` from [p2pme.pages.dev](https://p2pme.pages.dev).
* Extract the folder.
* Double-click `Launch_P2Pme.cmd` or `p2pme_app.exe` for the Flutter desktop UI, or run `p2pme.exe` in PowerShell for the native CLI daemon.
