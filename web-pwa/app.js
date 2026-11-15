// P2Pme Web PWA Engine (WebRTC P2P + Responsive Navigation)
(function() {
  'use strict';

  // State
  let currentTab = 'drop'; // 'drop' | 'nearby' | 'apps'
  let dropMode = 'send';  // 'send' | 'recv'
  let selectedFiles = [];
  let currentSessionPin = null;

  // DOM Elements
  const tabDropHeader = document.getElementById('tabDropHeader');
  const tabNearbyHeader = document.getElementById('tabNearbyHeader');
  const tabAppsHeader = document.getElementById('tabAppsHeader');

  const tabDropMobile = document.getElementById('tabDropMobile');
  const tabNearbyMobile = document.getElementById('tabNearbyMobile');
  const tabAppsMobile = document.getElementById('tabAppsMobile');

  const viewDrop = document.getElementById('viewDrop');
  const viewNearby = document.getElementById('viewNearby');
  const viewApps = document.getElementById('viewApps');

  const btnModeSend = document.getElementById('btnModeSend');
  const btnModeRecv = document.getElementById('btnModeRecv');
  const panelSend = document.getElementById('panelSend');
  const panelRecv = document.getElementById('panelRecv');

  const fileInput = document.getElementById('fileInput');
  const dropArea = document.getElementById('dropArea');
  const selectedList = document.getElementById('selectedList');
  const btnStartSend = document.getElementById('btnStartSend');
  const sendActiveBox = document.getElementById('sendActiveBox');
  const pinDisplay = document.getElementById('pinDisplay');
  const sendProgressCont = document.getElementById('sendProgressCont');
  const sendProgressBar = document.getElementById('sendProgressBar');
  const sendStatus = document.getElementById('sendStatus');

  const recvPinInput = document.getElementById('recvPinInput');
  const btnStartRecv = document.getElementById('btnStartRecv');
  const recvProgressCont = document.getElementById('recvProgressCont');
  const recvProgressBar = document.getElementById('recvProgressBar');
  const recvStatus = document.getElementById('recvStatus');

  // Tab Switching
  window.switchTab = function(tab) {
    currentTab = tab;
    const headerBtns = [tabDropHeader, tabNearbyHeader, tabAppsHeader];
    const mobileBtns = [tabDropMobile, tabNearbyMobile, tabAppsMobile];
    const views = [viewDrop, viewNearby, viewApps];

    headerBtns.forEach(btn => btn?.classList.remove('active'));
    mobileBtns.forEach(btn => btn?.classList.remove('active'));
    views.forEach(v => v?.classList.add('hidden'));

    if (tab === 'drop') {
      tabDropHeader?.classList.add('active');
      tabDropMobile?.classList.add('active');
      viewDrop?.classList.remove('hidden');
    } else if (tab === 'nearby') {
      tabNearbyHeader?.classList.add('active');
      tabNearbyMobile?.classList.add('active');
      viewNearby?.classList.remove('hidden');
      initNearbyScan();
    } else if (tab === 'apps') {
      tabAppsHeader?.classList.add('active');
      tabAppsMobile?.classList.add('active');
      viewApps?.classList.remove('hidden');
    }

    try {
      if (tab === 'drop' && !window.location.hash.includes('pin=') && !window.location.hash.includes('mode=')) {
        history.replaceState(null, '', window.location.pathname);
      } else if (tab !== 'drop') {
        history.replaceState(null, '', `${window.location.pathname}#tab=${tab}`);
      }
    } catch (_) {}

    try {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    } catch (_) {}
  };

  // Reliable navigation bindings without system gesture conflicts
  function bindNavTarget(el, tab) {
    if (!el) return;
    el.addEventListener('click', (e) => {
      e.preventDefault();
      window.switchTab(tab);
    });
  }

  bindNavTarget(tabDropHeader, 'drop');
  bindNavTarget(tabNearbyHeader, 'nearby');
  bindNavTarget(tabAppsHeader, 'apps');
  bindNavTarget(tabDropMobile, 'drop');
  bindNavTarget(tabNearbyMobile, 'nearby');
  bindNavTarget(tabAppsMobile, 'apps');

  // Drop Mode Switching (Send vs Receive)
  window.setDropMode = function(mode) {
    dropMode = mode;
    if (mode === 'send') {
      btnModeSend?.classList.add('active');
      btnModeRecv?.classList.remove('active');
      panelSend?.classList.remove('hidden');
      panelRecv?.classList.add('hidden');
    } else {
      btnModeRecv?.classList.add('active');
      btnModeSend?.classList.remove('active');
      panelRecv?.classList.remove('hidden');
      panelSend?.classList.add('hidden');
    }
  };

  // Drag and Drop Handling
  if (dropArea) {
    ['dragenter', 'dragover'].forEach(eventName => {
      dropArea.addEventListener(eventName, (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropArea.classList.add('dragover');
      }, false);
    });

    ['dragleave', 'drop'].forEach(eventName => {
      dropArea.addEventListener(eventName, (e) => {
        e.preventDefault();
        e.stopPropagation();
        dropArea.classList.remove('dragover');
      }, false);
    });

    dropArea.addEventListener('drop', (e) => {
      const dt = e.dataTransfer;
      if (dt && dt.files && dt.files.length) {
        selectedFiles = Array.from(dt.files);
        renderSelectedFiles();
      }
    });
  }

  // Screen Wake Lock & Keep-Alive for large iOS transfers
  let screenWakeLock = null;
  const wakeLockStatus = document.getElementById('wakeLockStatus');

  async function acquireWakeLock() {
    if ('wakeLock' in navigator) {
      try {
        screenWakeLock = await navigator.wakeLock.request('screen');
        if (wakeLockStatus) wakeLockStatus.style.display = 'inline';
        screenWakeLock.addEventListener('release', () => {
          screenWakeLock = null;
          if (wakeLockStatus) wakeLockStatus.style.display = 'none';
        });
      } catch (err) {
        console.warn('Wake Lock error:', err);
      }
    }
  }

  function releaseWakeLock() {
    if (screenWakeLock) {
      screenWakeLock.release().catch(() => {});
      screenWakeLock = null;
    }
    if (wakeLockStatus) wakeLockStatus.style.display = 'none';
  }

  document.addEventListener('visibilitychange', async () => {
    if (document.visibilityState === 'visible' && currentSessionPin) {
      await acquireWakeLock();
    }
  });

  // Persistent Backup Ledger (Tracks what has already been backed up to prevent re-sending)
  const BACKUP_LEDGER_KEY = 'p2pme_backed_up_files';
  function getBackupLedger() {
    try {
      return JSON.parse(localStorage.getItem(BACKUP_LEDGER_KEY) || '{}');
    } catch (_) {
      return {};
    }
  }

  function markFilesBackedUp(files) {
    const ledger = getBackupLedger();
    files.forEach(f => {
      const key = `${f.name}_${f.size}`;
      ledger[key] = Date.now();
    });
    try {
      localStorage.setItem(BACKUP_LEDGER_KEY, JSON.stringify(ledger));
    } catch (_) {}
  }

  let skipAlreadyBackedUp = true;
  window.toggleSkipBackedUp = function(checked) {
    skipAlreadyBackedUp = checked;
    renderSelectedFiles();
  };

  // File Selection via file input, camera roll input & folder picker
  const cameraInput = document.getElementById('cameraInput');
  const folderInput = document.getElementById('folderInput');

  if (cameraInput) {
    cameraInput.addEventListener('change', (e) => {
      const files = e.target.files ? Array.from(e.target.files) : [];
      if (files.length === 0) return;
      if (selectedList) {
        selectedList.innerHTML = '<div style="font-size: 12px; color: var(--text-muted); text-align: center; padding: 10px;">Processing selected photos...</div>';
      }
      setTimeout(() => {
        selectedFiles = files;
        renderSelectedFiles();
      }, 50);
    });
  }

  if (folderInput) {
    folderInput.addEventListener('change', (e) => {
      const files = e.target.files ? Array.from(e.target.files) : [];
      if (files.length === 0) return;
      if (selectedList) {
        selectedList.innerHTML = '<div style="font-size: 12px; color: var(--text-muted); text-align: center; padding: 10px;">Scanning folder items...</div>';
      }
      setTimeout(() => {
        selectedFiles = files;
        renderSelectedFiles();
      }, 50);
    });
  }

  if (fileInput) {
    fileInput.addEventListener('change', (e) => {
      const files = e.target.files ? Array.from(e.target.files) : [];
      if (files.length === 0) return;
      if (selectedList) {
        selectedList.innerHTML = '<div style="font-size: 12px; color: var(--text-muted); text-align: center; padding: 10px;">Processing selected files...</div>';
      }
      setTimeout(() => {
        selectedFiles = files;
        renderSelectedFiles();
      }, 50);
    });
  }

  function renderSelectedFiles() {
    if (!selectedList) return;
    selectedList.innerHTML = '';
    if (selectedFiles.length === 0) {
      if (btnStartSend) btnStartSend.disabled = true;
      return;
    }

    const ledger = getBackupLedger();
    let alreadyBackedUpCount = 0;
    const newFiles = [];
    selectedFiles.forEach(f => {
      const key = `${f.name}_${f.size}`;
      if (ledger[key]) {
        alreadyBackedUpCount++;
      } else {
        newFiles.push(f);
      }
    });

    const effectiveFiles = (skipAlreadyBackedUp && alreadyBackedUpCount > 0) ? newFiles : selectedFiles;

    if (btnStartSend) {
      btnStartSend.disabled = (effectiveFiles.length === 0);
    }

    // Update 1-Tap Home Hub Quick Send Card
    if (homeHubQuickCard) {
      const hubs = getSavedHubs();
      if (hubs.length > 0 && effectiveFiles.length > 0) {
        const hub = hubs[0];
        if (homeHubCardName) homeHubCardName.innerText = hub.name;
        if (homeHubCardAddr) homeHubCardAddr.innerText = `${hub.host}:${hub.port}`;
        if (btnSendToHub) {
          btnSendToHub.innerHTML = `<span>🚀</span> Send ${effectiveFiles.length} item(s) to ${escapeHtml(hub.name)} (No PIN)`;
        }
        homeHubQuickCard.style.display = 'block';
      } else {
        homeHubQuickCard.style.display = 'none';
      }
    }

    // High volume batch (e.g. > 6 photos or folder selection): Show compact summary card with deduplication status
    if (selectedFiles.length > 6) {
      const totalMb = (effectiveFiles.reduce((sum, f) => sum + (f.size || 0), 0) / (1024 * 1024)).toFixed(1);
      const summaryBox = document.createElement('div');
      summaryBox.style.cssText = 'background: #303134; border: 1px solid var(--card-border); border-radius: 14px; padding: 14px 16px; margin-bottom: 12px;';
      summaryBox.innerHTML = `
        <div style="display: flex; align-items: center; justify-content: space-between;">
          <div>
            <div style="font-weight: 600; font-size: 14px; color: #E8EAED;">📷 ${selectedFiles.length} items in selection</div>
            <div style="font-size: 12px; color: var(--text-muted); margin-top: 2px;">
              ${alreadyBackedUpCount > 0 ? `<span style="color:#34A853;">✓ ${alreadyBackedUpCount} already backed up</span> • ` : ''}
              <strong>${effectiveFiles.length} to send</strong> (~${totalMb} MB)
            </div>
          </div>
          <button type="button" onclick="clearSelectedFiles()" style="background: rgba(234,67,53,0.15); color: #EA4335; border: 1px solid rgba(234,67,53,0.3); border-radius: 16px; padding: 5px 12px; font-size: 12px; cursor: pointer; font-weight: 500;">Clear all</button>
        </div>
        ${alreadyBackedUpCount > 0 ? `
          <label style="display: flex; align-items: center; gap: 8px; margin-top: 10px; font-size: 12px; color: #E8EAED; cursor: pointer; user-select: none;">
            <input type="checkbox" ${skipAlreadyBackedUp ? 'checked' : ''} onchange="toggleSkipBackedUp(this.checked)" style="accent-color: var(--google-blue); width: 15px; height: 15px;">
            Skip already backed up photos (avoid duplicate transfers)
          </label>
        ` : ''}
      `;
      selectedList.appendChild(summaryBox);
      return;
    }

    selectedFiles.forEach((f, idx) => {
      const isDone = ledger[`${f.name}_${f.size}`];
      const chip = document.createElement('div');
      chip.className = 'chip';
      chip.innerHTML = `
        <span>${isDone ? '✓ ' : '📄 '}<strong>${escapeHtml(f.name)}</strong> (${(f.size / (1024 * 1024)).toFixed(1)} MB)${isDone ? ' (Backed Up)' : ''}</span>
        <button type="button" onclick="removeFile(${idx})" title="Remove">&times;</button>
      `;
      selectedList.appendChild(chip);
    });
  }

  window.clearSelectedFiles = function() {
    selectedFiles = [];
    if (cameraInput) cameraInput.value = '';
    if (folderInput) folderInput.value = '';
    if (fileInput) fileInput.value = '';
    renderSelectedFiles();
  };

  window.removeFile = function(idx) {
    selectedFiles.splice(idx, 1);
    renderSelectedFiles();
  };

  function escapeHtml(str) {
    return str.replace(/[&<>'"]/g, tag => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      "'": '&#39;',
      '"': '&quot;'
    }[tag] || tag));
  }

  function generatePin() {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  // Handle Send Drop
  window.handleCreateDrop = async function() {
    if (selectedFiles.length === 0) return;

    const ledger = getBackupLedger();
    let toSend = selectedFiles;
    if (skipAlreadyBackedUp) {
      const filtered = selectedFiles.filter(f => !ledger[`${f.name}_${f.size}`]);
      if (filtered.length > 0) {
        toSend = filtered;
      }
    }

    if (toSend.length === 0) {
      alert('All selected files have already been backed up.');
      return;
    }

    currentSessionPin = generatePin();
    await acquireWakeLock();

    // Cache active files for direct in-browser delivery
    window._localActiveDrop = {
      pin: currentSessionPin,
      files: [...toSend]
    };

    // Render PIN digits
    if (pinDisplay) {
      pinDisplay.innerHTML = '';
      currentSessionPin.split('').forEach(d => {
        const box = document.createElement('div');
        box.className = 'pin-digit';
        box.innerText = d;
        pinDisplay.appendChild(box);
      });
    }

    if (sendActiveBox) sendActiveBox.classList.remove('hidden');
    if (sendStatus) sendStatus.innerText = `Enter PIN ${currentSessionPin} on recipient device (${toSend.length} items ready)`;
    if (sendProgressCont) sendProgressCont.classList.remove('hidden');
    if (sendProgressBar) {
      sendProgressBar.style.width = '0%';
      sendProgressBar.innerText = 'Screen kept awake • Waiting for recipient...';
    }

    // Render QR Code
    const qrContainer = document.getElementById('sendQrContainer');
    if (qrContainer && window.QRCode) {
      qrContainer.innerHTML = '';
      const dropUrl = `${window.location.origin}${window.location.pathname}#pin=${currentSessionPin}`;
      new QRCode(qrContainer, {
        text: dropUrl,
        width: 140,
        height: 140,
        colorDark: "#1A73E8",
        colorLight: "#FFFFFF",
        correctLevel: QRCode.CorrectLevel.M
      });
    }

    // Broadcast presence on local Wi-Fi channel
    broadcastLocalPresence(currentSessionPin, toSend.length);
  };

  window.copyDropPin = function() {
    if (!currentSessionPin) return;
    navigator.clipboard.writeText(currentSessionPin).then(() => {
      alert(`PIN ${currentSessionPin} copied`);
    });
  };

  window.copyDropLink = function() {
    if (!currentSessionPin) return;
    const dropUrl = `${window.location.origin}${window.location.pathname}#pin=${currentSessionPin}`;
    navigator.clipboard.writeText(dropUrl).then(() => {
      alert('Link copied');
    });
  };

  // Broadcast presence
  let localChannel = null;
  try {
    localChannel = new BroadcastChannel('p2pme_local_mesh');
    localChannel.onmessage = (event) => {
      const msg = event.data;
      if (msg && msg.type === 'PEER_ANNOUNCE') {
        addNearbyPeer(msg);
      }
    };
  } catch (_) {}

  function broadcastLocalPresence(pin, fileCount) {
    if (localChannel) {
      localChannel.postMessage({
        type: 'PEER_ANNOUNCE',
        pin: pin,
        files: fileCount,
        ua: navigator.userAgent.includes('iPhone') ? 'iPhone' : (navigator.userAgent.includes('Android') ? 'Android' : 'Desktop PC/Mac'),
        time: Date.now()
      });
    }
  }

  // Handle Receive Drop
  window.handleDownloadDrop = async function() {
    const pin = recvPinInput.value.trim();
    if (pin.length !== 6) {
      alert('Please enter a valid 6-Digit PIN.');
      return;
    }

    const phoneIpInput = document.getElementById('phoneIpInput');
    const phoneIp = (phoneIpInput ? phoneIpInput.value.trim() : '') || '192.168.178.35';
    if (phoneIp && phoneIpInput) {
      try { localStorage.setItem('p2pme_saved_phone_ip', phoneIp); } catch (_) {}
    }

    if (recvStatus) recvStatus.innerText = `Connecting to sender with PIN [${pin}]...`;
    if (recvProgressCont) recvProgressCont.classList.remove('hidden');
    if (recvProgressBar) {
      recvProgressBar.style.width = '30%';
      recvProgressBar.innerText = 'Connecting...';
    }

    // 1. Direct Web-to-Web Active Drop (Same machine / in-memory / local tab)
    if (window._localActiveDrop && window._localActiveDrop.pin === pin) {
      const files = window._localActiveDrop.files;
      if (files && files.length > 0) {
        if (recvProgressBar) {
          recvProgressBar.style.width = '30%';
          recvProgressBar.innerText = `Receiving 1 of ${files.length}...`;
        }
        setTimeout(async () => {
          for (let i = 0; i < files.length; i++) {
            const file = files[i];
            const a = document.createElement('a');
            const blobUrl = URL.createObjectURL(file);
            a.href = blobUrl;
            a.download = file.name;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(blobUrl);
            if (recvProgressBar) {
              const pct = Math.round(((i + 1) / files.length) * 100);
              recvProgressBar.style.width = `${pct}%`;
              recvProgressBar.innerText = `${i + 1}/${files.length} (${pct}%)`;
            }
            if (files.length > 1) {
              await new Promise(r => setTimeout(r, 100));
            }
          }
          markFilesBackedUp(files);
          releaseWakeLock();
          if (recvProgressBar) {
            recvProgressBar.style.width = '100%';
            recvProgressBar.innerText = '100%';
          }
          if (recvStatus) {
            recvStatus.innerHTML = `<span style="color:#34A853;font-weight:500;">✓ Successfully saved ${files.length} file(s)</span>`;
          }
        }, 300);
        return;
      }
    }

    // 2. Direct Wi-Fi Phone Delivery (from Android device running P2Pme)
    if (phoneIp) {
      const directDownloadUrl = `http://${phoneIp}:45455/download?pin=${pin}&file=0`;
      const directPortalUrl = `http://${phoneIp}:45455/drop?pin=${pin}`;

      if (recvProgressBar) {
        recvProgressBar.style.width = '60%';
        recvProgressBar.innerText = 'Transferring...';
      }

      // Initiate actual file download link
      const a = document.createElement('a');
      a.href = directDownloadUrl;
      a.setAttribute('download', '');
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);

      setTimeout(() => {
        if (recvProgressBar) {
          recvProgressBar.style.width = '100%';
          recvProgressBar.innerText = '100%';
        }
        if (recvStatus) {
          recvStatus.innerHTML = `
            <span style="color:#34A853;font-weight:500;">Download started</span><br>
            <span style="font-size:12px;color:var(--text-muted);">Transferring directly over local Wi-Fi</span><br>
            <a href="${directPortalUrl}" target="_blank" style="display:inline-block;margin-top:8px;color:var(--accent);text-decoration:underline;font-weight:500;">
              Open direct download link &rarr;
            </a>
          `;
        }
      }, 800);
      return;
    }

    if (recvStatus) {
      recvStatus.innerHTML = `<span style="color:#EA4335;font-weight:500;">Device not found. Make sure both devices are on the same Wi-Fi.</span>`;
    }
  };

  // Nearby Discovery
  const nearbyPeersList = document.getElementById('nearbyPeersList');
  function initNearbyScan() {
    if (!nearbyPeersList) return;
    nearbyPeersList.innerHTML = '';

    const phoneIpInput = document.getElementById('phoneIpInput');
    const phoneIp = (phoneIpInput ? phoneIpInput.value.trim() : '') || localStorage.getItem('p2pme_saved_phone_ip') || '192.168.178.35';

    // Show local Wi-Fi transfer portal card
    const portalCard = document.createElement('div');
    portalCard.className = 'peer-card';
    portalCard.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:12px;padding:16px;background:var(--card-bg);border:1px solid var(--card-border);border-radius:16px;margin-bottom:12px;';
    portalCard.innerHTML = `
      <div style="display:flex;align-items:center;gap:12px;">
        <div style="width:40px;height:40px;border-radius:20px;background:var(--google-surface);display:flex;align-items:center;justify-content:center;font-size:20px;">
          📱
        </div>
        <div style="text-align:left;">
          <div style="font-weight:600;font-size:14px;color:var(--text);">Android Device (${phoneIp})</div>
          <div style="font-size:12px;color:var(--text-muted);margin-top:2px;">Local Wi-Fi portal • Port 45455</div>
        </div>
      </div>
      <div style="display:flex;gap:8px;">
        <a href="http://${phoneIp}:45455/" target="_blank" class="header-nav-btn" style="background:var(--google-blue);color:white;padding:8px 16px;border-radius:20px;text-decoration:none;font-size:13px;font-weight:500;">
          Send Photos &rarr;
        </a>
      </div>
    `;
    nearbyPeersList.appendChild(portalCard);

    // Tip box explaining how it connects
    const infoBox = document.createElement('div');
    infoBox.style.cssText = 'background:rgba(26,115,232,0.08);border:1px solid rgba(26,115,232,0.2);border-radius:12px;padding:14px;font-size:12px;color:var(--text);line-height:1.5;text-align:left;margin-top:12px;';
    infoBox.innerHTML = `
      <div style="font-weight:600;margin-bottom:6px;color:var(--accent);">How to transfer between iOS and Android:</div>
      <div>&bull; <strong>Send from iPhone to Android:</strong> Open the app on Android &rarr; tap <strong>Receive</strong> &rarr; scan the QR code (or tap <strong>Send Photos &rarr;</strong> above).</div>
      <div style="margin-top:4px;">&bull; <strong>Send from Android to iPhone:</strong> On Android, select photos &rarr; tap <strong>Send with PIN</strong> &rarr; enter the 6-digit PIN on this screen under <strong>Receive</strong>.</div>
    `;
    nearbyPeersList.appendChild(infoBox);

    // Broadcast self on local channel
    if (localChannel) {
      localChannel.postMessage({
        type: 'PEER_PING',
        ua: navigator.userAgent.includes('iPhone') ? 'iPhone' : (navigator.userAgent.includes('Android') ? 'Android' : 'PC/Mac')
      });
    }
  }

  function addNearbyPeer(peer) {
    if (!nearbyPeersList) return;
    const card = document.createElement('div');
    card.className = 'peer-card';
    card.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px;background:var(--card-bg);border:1px solid var(--card-border);border-radius:16px;margin-bottom:10px;';
    card.innerHTML = `
      <div style="display:flex;align-items:center;gap:12px;">
        <div style="width:36px;height:36px;border-radius:18px;background:var(--google-surface);display:flex;align-items:center;justify-content:center;font-size:18px;">📱</div>
        <div style="text-align:left;">
          <div style="font-weight:600;font-size:14px;color:var(--text);">${escapeHtml(peer.ua)}</div>
          <div style="font-size:12px;color:var(--text-muted);">Active on Wi-Fi • PIN: ${peer.pin}</div>
        </div>
      </div>
      <button class="header-nav-btn" style="background:var(--google-blue);color:white;padding:7px 16px;border-radius:20px;font-size:13px;font-weight:500;" onclick="connectToPeer('${peer.pin}')">
        Connect
      </button>
    `;
    nearbyPeersList.prepend(card);
  }

  window.connectToPeer = function(pin) {
    window.switchTab('drop');
    window.setDropMode('recv');
    if (recvPinInput) recvPinInput.value = pin;
    window.handleDownloadDrop();
  };

  // ==========================================
  // Known 24/7 Home Hubs (Trusted Devices)
  // ==========================================
  const knownHubsList = document.getElementById('knownHubsList');
  const homeHubQuickCard = document.getElementById('homeHubQuickCard');
  const homeHubCardName = document.getElementById('homeHubCardName');
  const homeHubCardAddr = document.getElementById('homeHubCardAddr');
  const btnSendToHub = document.getElementById('btnSendToHub');
  const hubModal = document.getElementById('hubModal');
  const modalHubName = document.getElementById('modalHubName');
  const modalHubHost = document.getElementById('modalHubHost');
  const modalHubPort = document.getElementById('modalHubPort');
  const modalHubToken = document.getElementById('modalHubToken');

  function getSavedHubs() {
    try {
      const data = localStorage.getItem('p2pme_saved_hubs');
      if (data) return JSON.parse(data);
    } catch (_) {}

    // Default initialization
    const fallbackHost = localStorage.getItem('p2pme_saved_phone_ip') || '192.168.178.35';
    const defaultHubs = [
      {
        id: 'hub_home_default',
        name: 'Home Android Hub',
        host: fallbackHost,
        port: 45455,
        addedAt: Date.now()
      }
    ];
    try {
      localStorage.setItem('p2pme_saved_hubs', JSON.stringify(defaultHubs));
    } catch (_) {}
    return defaultHubs;
  }

  function saveHubsList(hubs) {
    try {
      localStorage.setItem('p2pme_saved_hubs', JSON.stringify(hubs));
    } catch (_) {}
    renderSavedHubs();
  }

  function renderSavedHubs() {
    const hubs = getSavedHubs();

    // 1. Render in Quick Drop Send Panel
    if (homeHubQuickCard) {
      if (hubs.length > 0) {
        const primaryHub = hubs[0];
        if (homeHubCardName) homeHubCardName.innerText = primaryHub.name;
        if (homeHubCardAddr) homeHubCardAddr.innerText = `${primaryHub.host}:${primaryHub.port}`;
        if (selectedFiles && selectedFiles.length > 0) {
          homeHubQuickCard.style.display = 'block';
          if (btnSendToHub) {
            btnSendToHub.innerHTML = `<span>🚀</span> Send ${selectedFiles.length} item(s) to ${escapeHtml(primaryHub.name)} (No PIN)`;
          }
        } else {
          homeHubQuickCard.style.display = 'none';
        }
      } else {
        homeHubQuickCard.style.display = 'none';
      }
    }

    // 2. Render in Nearby Tab
    if (!knownHubsList) return;
    knownHubsList.innerHTML = '';

    if (hubs.length === 0) {
      knownHubsList.innerHTML = `
        <div style="background: rgba(255,255,255,0.03); border: 1px dashed var(--card-border); border-radius: 14px; padding: 18px; text-align: center; color: var(--text-muted); font-size: 13px;">
          No 24/7 Home Hubs saved yet. Tap <strong>+ Add Hub</strong> above to save your Android phone as a permanent receiver.
        </div>
      `;
      return;
    }

    hubs.forEach(hub => {
      const card = document.createElement('div');
      card.className = 'peer-card';
      card.style.cssText = 'display:flex;align-items:center;justify-content:space-between;gap:12px;padding:14px;background:rgba(255,255,255,0.03);border:1px solid var(--card-border);border-radius:16px;margin-bottom:10px;flex-wrap:wrap;';
      card.innerHTML = `
        <div style="display:flex;align-items:center;gap:12px;">
          <div style="width:42px;height:42px;border-radius:21px;background:rgba(26,115,232,0.18);display:flex;align-items:center;justify-content:center;font-size:22px;">
            🏠
          </div>
          <div style="text-align:left;">
            <div style="font-weight:700;font-size:14px;color:var(--text);display:flex;align-items:center;gap:6px;">
              ${escapeHtml(hub.name)}
              <span style="font-size:10px;padding:2px 6px;border-radius:10px;background:rgba(52,168,83,0.15);color:#34A853;border:1px solid rgba(52,168,83,0.3);font-weight:600;">24/7 SERVER</span>
            </div>
            <div style="font-size:12px;color:var(--text-muted);font-family:monospace;margin-top:2px;">
              ${escapeHtml(hub.host)}:${hub.port}
            </div>
          </div>
        </div>
        <div style="display:flex;gap:8px;align-items:center;">
          <button class="header-nav-btn" style="background:var(--google-blue);color:white;padding:7px 16px;border-radius:20px;font-size:13px;font-weight:600;cursor:pointer;" onclick="quickSendToHub('${hub.id}')">
            Send Photos &rarr;
          </button>
          <button class="header-nav-btn" style="background:transparent;border:1px solid rgba(234,67,53,0.3);color:#EA4335;padding:7px 12px;border-radius:20px;font-size:12px;cursor:pointer;" onclick="removeHub('${hub.id}')" title="Forget Device">
            ✕
          </button>
        </div>
      `;
      knownHubsList.appendChild(card);
    });
  }

  window.showAddHubModal = function() {
    if (hubModal) hubModal.classList.remove('hidden');
  };

  window.hideAddHubModal = function() {
    if (hubModal) hubModal.classList.add('hidden');
  };

  window.saveHubFromModal = function() {
    const name = modalHubName ? modalHubName.value.trim() : 'Home Android Hub';
    const host = modalHubHost ? modalHubHost.value.trim() : '192.168.178.35';
    const port = modalHubPort ? parseInt(modalHubPort.value.trim()) || 45455 : 45455;
    const token = modalHubToken ? modalHubToken.value.trim() : '';

    if (!host) {
      alert('Please enter a valid IP address or domain');
      return;
    }

    const hubs = getSavedHubs();
    const newHub = {
      id: `hub_${Date.now()}`,
      name: name || 'Home Android Hub',
      host: host,
      port: port,
      token: token,
      addedAt: Date.now()
    };
    hubs.unshift(newHub);
    saveHubsList(hubs);

    try {
      localStorage.setItem('p2pme_saved_phone_ip', host);
    } catch (_) {}

    hideAddHubModal();
  };

  // Hub Info & Guidance Modal Handlers
  window.showHubInfoModal = function() {
    const modal = document.getElementById('hubInfoModal');
    if (modal) modal.classList.remove('hidden');
  };

  window.hideHubInfoModal = function() {
    const modal = document.getElementById('hubInfoModal');
    if (modal) modal.classList.add('hidden');
  };

  window.switchInfoTab = function(idx) {
    const tabs = [1, 2, 3, 4, 5];
    tabs.forEach(t => {
      const btn = document.getElementById('infoTabBtn' + t);
      const content = document.getElementById('infoTabContent' + t);
      if (btn) {
        btn.style.background = 'transparent';
        btn.style.color = 'var(--text-muted)';
        btn.style.fontWeight = '600';
      }
      if (content) content.style.display = 'none';
    });

    const activeBtn = document.getElementById('infoTabBtn' + idx);
    const activeContent = document.getElementById('infoTabContent' + idx);
    if (activeBtn) {
      if (idx === 1) activeBtn.style.background = '#1A73E8';
      else if (idx === 2) activeBtn.style.background = '#34A853';
      else if (idx === 3) activeBtn.style.background = '#0284C7';
      else if (idx === 4) activeBtn.style.background = '#EA4335';
      else if (idx === 5) activeBtn.style.background = '#5F6368';
      activeBtn.style.color = 'white';
      activeBtn.style.fontWeight = '700';
    }
    if (activeContent) activeContent.style.display = 'block';
  };

  // iOS Sideloading & 7-Day Auto-Refresh Modal Handlers
  window.showIosSideloadModal = function() {
    const modal = document.getElementById('iosSideloadModal');
    if (modal) modal.classList.remove('hidden');
  };

  window.hideIosSideloadModal = function() {
    const modal = document.getElementById('iosSideloadModal');
    if (modal) modal.classList.add('hidden');
  };

  window.switchIosTab = function(idx) {
    const tabs = [1, 2, 3, 4];
    tabs.forEach(t => {
      const btn = document.getElementById('iosTabBtn' + t);
      const content = document.getElementById('iosTabContent' + t);
      if (btn) {
        btn.style.background = 'transparent';
        btn.style.color = 'var(--text-muted)';
        btn.style.fontWeight = '600';
      }
      if (content) content.style.display = 'none';
    });

    const activeBtn = document.getElementById('iosTabBtn' + idx);
    const activeContent = document.getElementById('iosTabContent' + idx);
    if (activeBtn) {
      if (idx === 1) activeBtn.style.background = '#1A73E8';
      else if (idx === 2) activeBtn.style.background = '#0284C7';
      else if (idx === 3) activeBtn.style.background = '#34A853';
      else if (idx === 4) activeBtn.style.background = '#5F6368';
      activeBtn.style.color = 'white';
      activeBtn.style.fontWeight = '700';
    }
    if (activeContent) activeContent.style.display = 'block';
  };

  window.removeHub = function(id) {
    if (!confirm('Forget this saved 24/7 Home Hub?')) return;
    const hubs = getSavedHubs().filter(h => h.id !== id);
    saveHubsList(hubs);
  };

  window.quickSendToHub = function(hubId) {
    const hubs = getSavedHubs();
    const hub = hubs.find(h => h.id === hubId) || hubs[0];
    if (!hub) return;

    window.switchTab('drop');
    window.setDropMode('send');

    if (selectedFiles.length === 0) {
      if (cameraInput) cameraInput.click();
    } else {
      window.sendSelectedToHub(hubId);
    }
  };

  window.sendSelectedToHub = async function(hubId) {
    if (!selectedFiles || selectedFiles.length === 0) {
      if (cameraInput) cameraInput.click();
      return;
    }

    const hubs = getSavedHubs();
    const hub = (hubId ? hubs.find(h => h.id === hubId) : null) || hubs[0];
    if (!hub) {
      alert('No 24/7 Home Hub configured. Please add one under Nearby & Saved Hubs.');
      return;
    }

    await acquireWakeLock();

    if (sendProgressCont) sendProgressCont.classList.remove('hidden');
    if (sendStatus) {
      sendStatus.innerHTML = `<span style="color:#8AB4F8;">Connecting to ${escapeHtml(hub.name)} (${hub.host}:${hub.port})...</span>`;
    }

    let successCount = 0;
    const totalFiles = selectedFiles.length;
    const uploadUrlBase = `http://${hub.host}:${hub.port}/upload`;

    for (let i = 0; i < totalFiles; i++) {
      const file = selectedFiles[i];
      const pct = Math.round(((i) / totalFiles) * 100);
      if (sendProgressBar) {
        sendProgressBar.style.width = `${Math.max(5, pct)}%`;
        sendProgressBar.innerText = `Sending ${i + 1}/${totalFiles}: ${file.name} (${pct}%)`;
      }

      try {
        const hubToken = hub.token || localStorage.getItem('p2pme_hub_token') || '';
        const uploadUrl = `${uploadUrlBase}?name=${encodeURIComponent(file.name)}&token=${encodeURIComponent(hubToken)}`;
        const res = await fetch(uploadUrl, {
          method: 'POST',
          body: file,
          mode: 'cors',
          headers: {
            'Content-Type': file.type || 'application/octet-stream',
            'x-p2pme-token': hubToken
          }
        });

        if (res.ok) {
          successCount++;
        } else {
          throw new Error(`Server returned status ${res.status}`);
        }
      } catch (err) {
        console.warn(`Direct fetch to ${uploadUrlBase} failed, offering direct portal link:`, err);
        if (sendProgressBar) {
          sendProgressBar.style.width = '100%';
          sendProgressBar.innerText = 'Direct LAN Portal Available';
        }
        if (sendStatus) {
          sendStatus.innerHTML = `
            <div style="background:rgba(26,115,232,0.12);border:1px solid rgba(26,115,232,0.3);border-radius:14px;padding:14px;text-align:left;margin-top:10px;">
              <div style="font-weight:600;color:#8AB4F8;margin-bottom:6px;">🚀 Direct Local Transfer:</div>
              <div style="font-size:12px;color:var(--text-muted);margin-bottom:10px;">
                Browser HTTPS security policy: To stream files directly over Wi-Fi without cloud servers, tap to open the local portal on your phone:
              </div>
              <a href="http://${hub.host}:${hub.port}/" target="_blank" style="display:inline-block;background:var(--google-blue);color:white;padding:8px 18px;border-radius:20px;text-decoration:none;font-size:13px;font-weight:600;">
                Open ${escapeHtml(hub.name)} Direct Portal &rarr;
              </a>
            </div>
          `;
        }
        releaseWakeLock();
        return;
      }
    }

    if (sendProgressBar) {
      sendProgressBar.style.width = '100%';
      sendProgressBar.innerText = '100% Complete';
    }

    if (sendStatus) {
      sendStatus.innerHTML = `
        <span style="color:#34A853;font-weight:700;font-size:14px;">
          ✓ Successfully delivered ${successCount} photo(s) to ${escapeHtml(hub.name)}!
        </span><br>
        <span style="font-size:12px;color:var(--text-muted);">
          Saved directly into Android gallery without cloud storage custody.
        </span>
      `;
    }

    markFilesBackedUp(selectedFiles);
    releaseWakeLock();
    selectedFiles = [];
    renderSelectedFiles();
  };

  // URL Hash auto-fill & deep-linking
  function handleHashRoute() {
    try {
      const savedPhoneIp = localStorage.getItem('p2pme_saved_phone_ip');
      const phoneIpInput = document.getElementById('phoneIpInput');
      if (savedPhoneIp && phoneIpInput) {
        phoneIpInput.value = savedPhoneIp;
      }
    } catch (_) {}

    renderSavedHubs();

    const hash = window.location.hash;
    if (hash.includes('tab=nearby')) {
      window.switchTab('nearby');
    } else if (hash.includes('tab=apps')) {
      window.switchTab('apps');
    } else if (hash.includes('mode=recv')) {
      window.switchTab('drop');
      window.setDropMode('recv');
    }

    if (hash.includes('pin=')) {
      const pin = hash.split('pin=')[1].substring(0, 6);
      window.switchTab('drop');
      window.setDropMode('recv');
      if (recvPinInput) recvPinInput.value = pin;
    }
  }

  if (document.readyState === 'loading') {
    window.addEventListener('DOMContentLoaded', handleHashRoute);
  } else {
    handleHashRoute();
  }
  window.addEventListener('hashchange', handleHashRoute);

  // PWA Service Worker Registration & Background Auto-Update
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('./sw.js').then((reg) => {
        // Silently check for PWA updates when returning to tab
        window.addEventListener('focus', () => {
          reg.update().catch(() => {});
        });
        // Silently check every 30 minutes in the background
        setInterval(() => {
          reg.update().catch(() => {});
        }, 30 * 60 * 1000);
      }).catch((err) => console.log('SW error:', err));

      let refreshing = false;
      navigator.serviceWorker.addEventListener('controllerchange', () => {
        if (!refreshing) {
          refreshing = true;
          showWebUpdateToast();
        }
      });
    });
  }

  function showWebUpdateToast() {
    if (document.getElementById('webUpdateToast')) return;
    const toast = document.createElement('div');
    toast.id = 'webUpdateToast';
    toast.style.cssText = `
      position: fixed;
      top: 18px;
      left: 50%;
      transform: translateX(-50%);
      background: rgba(36, 38, 46, 0.96);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255, 255, 255, 0.22);
      border-radius: 28px;
      padding: 10px 18px;
      display: flex;
      align-items: center;
      gap: 12px;
      z-index: 9999;
      box-shadow: 0 12px 32px rgba(0,0,0,0.6);
      font-size: 13px;
      color: #E8EAED;
      font-weight: 600;
      animation: fadeInToast 0.3s ease;
    `;
    toast.innerHTML = `
      <span>⚡ New version available</span>
      <button onclick="window.location.reload()" style="
        background: #1A73E8;
        color: white;
        border: none;
        border-radius: 14px;
        padding: 5px 12px;
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
      ">Refresh</button>
    `;
    document.body.appendChild(toast);
  }
})();
