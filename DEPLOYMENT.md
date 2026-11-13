# Deployment Guide: P2Pme on Cloudflare Pages & GitHub Releases

This guide walks through hosting **P2Pme** completely free of charge without managing cloud servers or submitting to app stores.

---

## 1. Push Repository to GitHub

### Step 1: Create a GitHub Repository
1. Log into your [GitHub Account](https://github.com/).
2. Click **New Repository**.
3. Name it `P2Pme` (choose Public or Private).
4. Do NOT initialize with a README (we already have one).
5. Click **Create repository**.

### Step 2: Initialize & Push from Local Machine
Open your terminal in `e:\P2Pme`:
```powershell
cd e:\P2Pme

# Initialize git
git init -b main

# Add all files
git add .

# Create initial commit
git commit -m "feat: initial commit of P2Pme core engine, Flutter app, and Cloudflare Web PWA"

# Link to your remote GitHub repo
git remote add origin https://github.com/MizopaRalte/p2pme.git

# Push to main branch
git push -u origin main
```

---

## 2. Deploy Web PWA to Cloudflare Pages (100% Free)

Cloudflare Pages provides global HTTPS hosting, instant updates on every Git push, and 0 server maintenance.

### Option A: Via Cloudflare Dashboard (Recommended)
1. Go to the [Cloudflare Dashboard](https://dash.cloudflare.com/) and navigate to **Workers & Pages**.
2. Click **Create application** &rarr; Select the **Pages** tab &rarr; Click **Connect to Git**.
3. Authorize GitHub and select the **P2Pme** repository.
4. Set the following build configuration:
   * **Project name:** `p2pme`
   * **Production branch:** `main`
   * **Framework preset:** `None`
   * **Build command:** *(leave empty)*
   * **Build output directory:** `web-pwa`
5. Click **Save and Deploy**.
6. Cloudflare will deploy your site and provide a permanent global URL:
   👉 **`https://p2pme.pages.dev`**
7. *(Optional)* Add your own custom domain (e.g. `p2pme.app` or `drop.yourdomain.com`) under **Custom domains** in Cloudflare.

### Option B: Via Wrangler CLI
If you prefer deploying directly from your terminal:
```powershell
cd e:\P2Pme\web-pwa
npx wrangler pages deploy . --project-name p2pme
```

---

## 3. Host Android APK & Windows EXE on GitHub Releases

To give friends, family, and yourself a 1-tap download link for the native APK and Windows binary:

### Step 1: Prepare the Compiled Files
1. **Android APK:** Located at `app/build/app/outputs/flutter-apk/app-debug.apk` (rename to `P2Pme.apk`).
2. **Windows Desktop Binary:** Located at `target/release/p2pme.exe`.

### Step 2: Create a GitHub Release
1. In your GitHub repository, click **Releases** &rarr; **Draft a new release**.
2. Set **Tag version** to `v1.0.0`.
3. Set **Release title** to `P2Pme v1.0.0 - Native Android & Windows Release`.
4. Drag and drop:
   * `P2Pme.apk`
   * `p2pme.exe`
5. Click **Publish release**.

### Step 3: Direct Download Links
Your friends and family can now download the apps directly:
* **Android APK:** `https://github.com/MizopaRalte/p2pme/releases/latest/download/P2Pme.apk`
* **Windows PC:** `https://github.com/MizopaRalte/p2pme/releases/latest/download/p2pme.exe`

These direct links can also be pasted directly into `web-pwa/index.html` on the **Native Apps** tab.

---

## 4. How iPhone Users Access P2Pme

iPhone users do **not** need the App Store:
1. Send them your Cloudflare Pages URL (e.g. `https://p2pme.pages.dev`).
2. They open the link in Safari.
3. They tap the **Share** button (the square with an arrow pointing up) &rarr; tap **Add to Home Screen**.
4. P2Pme appears as a standalone app icon on their iPhone home screen, working full-screen with offline support!

