#!/usr/bin/env python3
"""
P2Pme Unified Release Automation Engine
Single-command release process guaranteeing Zero Platform Disparity.
Usage:
    python scripts/release.py <version> "<release_notes>"
Example:
    python scripts/release.py 1.0.7 "Enhanced background replication and UI stability."
"""

import sys
import os
import re
import json
import time
import shutil
import hashlib
import zipfile
import io
import subprocess
import urllib.request

def log(msg):
    print(f"\n[RELEASE-ENGINE] >>> {msg}", flush=True)

def error(msg):
    print(f"\n[RELEASE-ERROR] ❌ {msg}", file=sys.stderr, flush=True)
    sys.exit(1)

def run(cmd, shell=True, check=True):
    log(f"Executing: {cmd}")
    res = subprocess.run(cmd, shell=shell, text=True, capture_output=True)
    if check and res.returncode != 0:
        error(f"Command failed with exit code {res.returncode}:\nStdout: {res.stdout}\nStderr: {res.stderr}")
    return res.stdout.strip()

def get_git_token():
    try:
        p = subprocess.Popen(['git', 'credential', 'fill'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        out, _ = p.communicate('protocol=https\nhost=github.com\n\n')
        for line in out.splitlines():
            if line.startswith('password='):
                return line.split('=', 1)[1]
    except Exception as e:
        error(f"Failed to retrieve git credentials from credential manager: {e}")
    error("No password/token found in git credential manager.")

def main():
    if len(sys.argv) < 3:
        error("Usage: python scripts/release.py <version> \"<release_notes>\"\nExample: python scripts/release.py 1.0.7 \"Release description\"")

    new_version = sys.argv[1].strip().lstrip('v')
    release_notes = sys.argv[2].strip()

    log(f"Initiating full cross-platform release for P2Pme v{new_version}...")

    # 1. Inspect existing version code
    with open('web-pwa/version.json', 'r', encoding='utf-8') as f:
        v_data = json.load(f)
    old_version = v_data.get('version', '1.0.0')
    if old_version == new_version:
        new_version_code = int(v_data.get('version_code', 1))
    else:
        new_version_code = int(v_data.get('version_code', 1)) + 1
    log(f"Bumping version: {old_version} -> {new_version} (buildCode: {new_version_code})")

    # 2. Update app/pubspec.yaml
    log("Updating app/pubspec.yaml...")
    with open('app/pubspec.yaml', 'r', encoding='utf-8') as f:
        pub_content = f.read()
    pub_content = re.sub(r'version:\s*\S+', f'version: {new_version}+{new_version_code}', pub_content)
    with open('app/pubspec.yaml', 'w', encoding='utf-8') as f:
        f.write(pub_content)

    # 3. Update app/lib/main.dart
    log("Updating app/lib/main.dart version constants...")
    with open('app/lib/main.dart', 'r', encoding='utf-8') as f:
        dart_content = f.read()
    dart_content = re.sub(r"int _currentVersionCode = \d+;", f"int _currentVersionCode = {new_version_code};", dart_content)
    dart_content = re.sub(r"String _currentVersionName = '[^']+';", f"String _currentVersionName = '{new_version}';", dart_content)
    with open('app/lib/main.dart', 'w', encoding='utf-8') as f:
        f.write(dart_content)

    # 4. Build Android APK locally
    log("Building Android release APK (split-per-abi)...")
    run("cd app && flutter build apk --split-per-abi --android-skip-build-dependency-validation")
    src_apk = "app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    if not os.path.exists(src_apk):
        error(f"Compiled APK not found at: {src_apk}")
    
    dst_apk_v = f"web-pwa/downloads/P2Pme-v{new_version}.apk"
    dst_apk_m = "web-pwa/downloads/P2Pme.apk"
    shutil.copyfile(src_apk, dst_apk_v)
    shutil.copyfile(src_apk, dst_apk_m)

    with open(dst_apk_v, 'rb') as f:
        apk_hash = hashlib.sha256(f.read()).hexdigest()
    log(f"Generated Android APK: {apk_hash}")

    # 5. Update web-pwa/version.json
    log("Updating web-pwa/version.json...")
    v_data['version'] = new_version
    v_data['version_code'] = new_version_code
    v_data['release_date'] = time.strftime('%Y-%m-%d')
    v_data['release_notes'] = release_notes
    v_data['apk_url'] = f"https://p2pme.pages.dev/downloads/P2Pme-v{new_version}.apk"
    v_data['apk_sha256'] = apk_hash
    v_data['ipa_url'] = f"https://p2pme.pages.dev/downloads/P2Pme-v{new_version}.ipa"
    with open('web-pwa/version.json', 'w', encoding='utf-8') as f:
        json.dump(v_data, f, indent=2)

    # 6. Update web-pwa/index.html download links
    log("Updating web-pwa/index.html download card labels & URLs...")
    with open('web-pwa/index.html', 'r', encoding='utf-8') as f:
        html = f.read()
    html = re.sub(r'P2Pme-v\d+\.\d+\.\d+\.apk', f'P2Pme-v{new_version}.apk', html)
    html = re.sub(r'P2Pme-v\d+\.\d+\.\d+\.ipa', f'P2Pme-v{new_version}.ipa', html)
    html = re.sub(r'Download Android App \(v\d+\.\d+\.\d+ APK\)', f'Download Android App (v{new_version} APK)', html)
    html = re.sub(r'Download Windows App \(v\d+\.\d+\.\d+ Portable\)', f'Download Windows App (v{new_version} Portable)', html)
    html = re.sub(r'⚡ Install with AltStore \(v\d+\.\d+\.\d+\)', f'⚡ Install with AltStore (v{new_version})', html)
    html = re.sub(r'📲 Install with SideStore \(v\d+\.\d+\.\d+\)', f'📲 Install with SideStore (v{new_version})', html)
    html = re.sub(r'Download Raw P2Pme-v\d+\.\d+\.\d+\.ipa', f'Download Raw P2Pme-v{new_version}.ipa', html)
    with open('web-pwa/index.html', 'w', encoding='utf-8') as f:
        f.write(html)

    # 7. Git commit, tag, and push
    log("Committing changes and pushing tag to trigger macOS cloud runner...")
    run("git add -A")
    c_res = subprocess.run(f'git commit -m "chore(release): v{new_version}"', shell=True, text=True, capture_output=True)
    if c_res.returncode != 0 and 'nothing to commit' not in c_res.stdout:
        error(f"Commit failed with exit code {c_res.returncode}:\nStdout: {c_res.stdout}\nStderr: {c_res.stderr}")
    
    subprocess.run(f"git tag -d v{new_version}", shell=True, capture_output=True)
    run(f'git tag -a v{new_version} -m "Release v{new_version}: {release_notes}"')
    run("git push origin main --tags --force")

    # 8. Get genuine macOS cloud runner build
    token = get_git_token()
    headers = {
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Mozilla/5.0'
    }

    dst_ipa_v = f"web-pwa/downloads/P2Pme-v{new_version}.ipa"
    dst_ipa_m = "web-pwa/downloads/P2Pme.ipa"

    if os.path.exists(dst_ipa_v) and os.path.getsize(dst_ipa_v) > 7000000:
        log(f"Found existing genuine macOS iOS IPA locally: {dst_ipa_v}")
        with open(dst_ipa_v, 'rb') as f:
            ipa_bytes = f.read()
        ipa_sz = len(ipa_bytes)
        ipa_hash = hashlib.sha256(ipa_bytes).hexdigest()
        shutil.copyfile(dst_ipa_v, dst_ipa_m)
        log(f"Genuine macOS iOS IPA verified: size={ipa_sz}, sha256={ipa_hash}")
    else:
        log(f"Waiting for GitHub Actions macOS runner to build genuine iOS IPA for tag v{new_version}...")
        ipa_artifact_id = None
        for attempt in range(80): # up to ~13 minutes
            time.sleep(10)
            req = urllib.request.Request('https://api.github.com/repos/MizopaRalte/p2pme/actions/runs', headers=headers)
            runs_data = json.loads(urllib.request.urlopen(req).read().decode('utf-8'))
            matching_runs = [
                r for r in runs_data.get('workflow_runs', [])
                if (r.get('head_branch') == f'v{new_version}' or r.get('head_commit', {}).get('message', '').startswith(f'chore(release): v{new_version}'))
                and (r.get('status') != 'completed' or r.get('conclusion') == 'success')
            ]
            
            if not matching_runs:
                print(f"Waiting for workflow run to register... ({attempt+1}/40)")
                continue

            run_obj = matching_runs[0]
            run_id = run_obj['id']
            run_status = run_obj['status']
            print(f"Run {run_id}: status={run_status}")

            # Check artifacts as soon as they become available
            try:
                art_req = urllib.request.Request(f'https://api.github.com/repos/MizopaRalte/p2pme/actions/runs/{run_id}/artifacts', headers=headers)
                art_data = json.loads(urllib.request.urlopen(art_req).read().decode('utf-8'))
                for a in art_data.get('artifacts', []):
                    if a['name'] == 'p2pme-ios-ipa':
                        ipa_artifact_id = a['id']
                        break
            except Exception as e:
                print(f"Error checking artifacts: {e}")

            if ipa_artifact_id:
                log(f"Found macOS-compiled iOS IPA artifact (ID: {ipa_artifact_id})!")
                break

            if run_status == 'completed':
                break

        if not ipa_artifact_id:
            error("Timed out waiting for macOS cloud runner to produce p2pme-ios-ipa artifact.")

        # 9. Download and unpack genuine iOS IPA
        log(f"Downloading p2pme-ios-ipa (artifact ID: {ipa_artifact_id})...")
        class NoRedirectHandler(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        opener = urllib.request.build_opener(NoRedirectHandler)
        dl_req = urllib.request.Request(f'https://api.github.com/repos/MizopaRalte/p2pme/actions/artifacts/{ipa_artifact_id}/zip', headers=headers)
        try:
            opener.open(dl_req)
            blob_url = dl_req.full_url
        except urllib.error.HTTPError as e:
            if e.code in (301, 302, 303, 307):
                blob_url = e.headers['Location']
            else:
                raise

        blob_req = urllib.request.Request(blob_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(blob_req) as resp:
            zip_bytes = resp.read()

        art_zip = zipfile.ZipFile(io.BytesIO(zip_bytes))
        ipa_bytes = art_zip.read('P2Pme.ipa')

        with open(dst_ipa_v, 'wb') as f:
            f.write(ipa_bytes)
        shutil.copyfile(dst_ipa_v, dst_ipa_m)

        ipa_sz = len(ipa_bytes)
        ipa_hash = hashlib.sha256(ipa_bytes).hexdigest()
        log(f"Genuine macOS iOS IPA acquired: size={ipa_sz}, sha256={ipa_hash}")

    # 10. Update altstore-source.json with matching version & hashes
    log("Updating web-pwa/altstore-source.json...")
    with open('web-pwa/altstore-source.json', 'r', encoding='utf-8') as f:
        alt_data = json.load(f)
    
    new_ver_entry = {
        "version": new_version,
        "buildVersion": str(new_version_code),
        "date": time.strftime('%Y-%m-%d'),
        "localizedDescription": release_notes,
        "downloadURL": f"https://p2pme.pages.dev/downloads/P2Pme-v{new_version}.ipa",
        "size": ipa_sz,
        "sha256": ipa_hash,
        "minOSVersion": "15.0",
        "appPermissions": alt_data['apps'][0]['versions'][0].get('appPermissions', {})
    }
    if alt_data['apps'][0]['versions'] and alt_data['apps'][0]['versions'][0]['version'] == new_version:
        alt_data['apps'][0]['versions'][0] = new_ver_entry
    else:
        alt_data['apps'][0]['versions'].insert(0, new_ver_entry)
    with open('web-pwa/altstore-source.json', 'w', encoding='utf-8') as f:
        json.dump(alt_data, f, indent=2)

    # Update version.json with final IPA sha256
    with open('web-pwa/version.json', 'r', encoding='utf-8') as f:
        v_data = json.load(f)
    v_data['ipa_sha256'] = ipa_hash
    with open('web-pwa/version.json', 'w', encoding='utf-8') as f:
        json.dump(v_data, f, indent=2)

    # 11. Deploy to Cloudflare Pages
    log("Deploying all assets to Cloudflare Pages edge...")
    run("npx wrangler pages deploy web-pwa --project-name p2pme --commit-dirty=true")

    # 12. Publish or update GitHub Release with all assets
    log(f"Publishing official GitHub Release v{new_version}...")
    rel_req = urllib.request.Request(f'https://api.github.com/repos/MizopaRalte/p2pme/releases/tags/v{new_version}', headers=headers)
    rel_id = None
    try:
        rel_obj = json.loads(urllib.request.urlopen(rel_req).read().decode('utf-8'))
        rel_id = rel_obj['id']
    except urllib.error.HTTPError as e:
        if e.code == 404:
            create_payload = {
                'tag_name': f'v{new_version}',
                'name': f'v{new_version}',
                'body': f"## P2Pme v{new_version}\n\n{release_notes}",
                'draft': False,
                'prerelease': False
            }
            create_req = urllib.request.Request(
                'https://api.github.com/repos/MizopaRalte/p2pme/releases',
                data=json.dumps(create_payload).encode('utf-8'),
                headers={**headers, 'Content-Type': 'application/json'}
            )
            rel_obj = json.loads(urllib.request.urlopen(create_req).read().decode('utf-8'))
            rel_id = rel_obj['id']

    # Upload all release assets
    upload_url_base = f'https://uploads.github.com/repos/MizopaRalte/p2pme/releases/{rel_id}/assets'
    assets_req = urllib.request.Request(f'https://api.github.com/repos/MizopaRalte/p2pme/releases/{rel_id}/assets', headers=headers)
    existing_assets = {a['name']: a['id'] for a in json.loads(urllib.request.urlopen(assets_req).read().decode('utf-8'))}

    apk_sha_content = f"{apk_hash}  P2Pme.apk\n"
    ipa_sha_content = f"{ipa_hash}  P2Pme.ipa\n"

    release_files = [
        (f'P2Pme-v{new_version}.apk', dst_apk_v, 'application/vnd.android.package-archive'),
        ('P2Pme.apk', dst_apk_m, 'application/vnd.android.package-archive'),
        (f'P2Pme-v{new_version}.ipa', dst_ipa_v, 'application/octet-stream'),
        ('P2Pme.ipa', dst_ipa_m, 'application/octet-stream'),
        ('P2Pme-Windows.zip', 'web-pwa/downloads/P2Pme-Windows.zip', 'application/zip'),
    ]

    for fname, fpath, mime in release_files:
        if fname in existing_assets:
            log(f"Replacing existing asset on GitHub Release: {fname}...")
            try:
                del_req = urllib.request.Request(f'https://api.github.com/repos/MizopaRalte/p2pme/releases/assets/{existing_assets[fname]}', headers=headers, method='DELETE')
                urllib.request.urlopen(del_req)
            except Exception as e:
                print(f"Warning deleting old asset: {e}")
        log(f"Uploading asset to GitHub Release: {fname}...")
        with open(fpath, 'rb') as f:
            fdata = f.read()
        up_req = urllib.request.Request(f'{upload_url_base}?name={fname}', data=fdata, headers={**headers, 'Content-Type': mime})
        urllib.request.urlopen(up_req)

    for sname, scontent in [(f'P2Pme.apk.sha256', apk_sha_content), (f'P2Pme.ipa.sha256', ipa_sha_content)]:
        if sname in existing_assets:
            log(f"Replacing existing checksum asset on GitHub Release: {sname}...")
            try:
                del_req = urllib.request.Request(f'https://api.github.com/repos/MizopaRalte/p2pme/releases/assets/{existing_assets[sname]}', headers=headers, method='DELETE')
                urllib.request.urlopen(del_req)
            except Exception as e:
                print(f"Warning deleting old checksum: {e}")
        up_req = urllib.request.Request(f'{upload_url_base}?name={sname}', data=scontent.encode('utf-8'), headers={**headers, 'Content-Type': 'text/plain'})
        urllib.request.urlopen(up_req)

    # 13. Final commit and push of metadata
    log("Committing final release metadata...")
    run("git add -A")
    c_res = subprocess.run('git commit -m "chore(release): finalize release metadata and checksums"', shell=True, text=True, capture_output=True)
    if c_res.returncode != 0 and 'nothing to commit' not in c_res.stdout:
        error(f"Commit failed: {c_res.stdout}")
    run("git push origin main")

    # 14. Verification
    log("Running automated release verification check...")
    run("python scripts/verify-release.py")

    log("=" * 60)
    log(f"🎉 RELEASE v{new_version} COMPLETED WITH ZERO PLATFORM DISPARITY!")
    log("=" * 60)

if __name__ == '__main__':
    main()
