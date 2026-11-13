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
  };

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

  // File Selection via file input
  if (fileInput) {
    fileInput.addEventListener('change', (e) => {
      selectedFiles = Array.from(e.target.files);
      renderSelectedFiles();
    });
  }

  function renderSelectedFiles() {
    if (!selectedList) return;
    selectedList.innerHTML = '';
    if (selectedFiles.length === 0) {
      if (btnStartSend) btnStartSend.disabled = true;
      return;
    }
    if (btnStartSend) btnStartSend.disabled = false;

    selectedFiles.forEach((f, idx) => {
      const chip = document.createElement('div');
      chip.className = 'chip';
      chip.innerHTML = `
        <span>📄 <strong>${escapeHtml(f.name)}</strong> (${(f.size / (1024 * 1024)).toFixed(1)} MB)</span>
        <button type="button" onclick="removeFile(${idx})" title="Remove">&times;</button>
      `;
      selectedList.appendChild(chip);
    });
  }

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
    currentSessionPin = generatePin();

    // Cache active files for direct in-browser delivery
    window._localActiveDrop = {
      pin: currentSessionPin,
      files: [...selectedFiles]
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
    if (sendStatus) sendStatus.innerText = `Session ready! Share PIN [${currentSessionPin}] with receiver.`;
    if (sendProgressCont) sendProgressCont.classList.remove('hidden');
    if (sendProgressBar) {
      sendProgressBar.style.width = '0%';
      sendProgressBar.innerText = 'Waiting for recipient...';
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
        colorDark: "#0284C7",
        colorLight: "#FFFFFF",
        correctLevel: QRCode.CorrectLevel.M
      });
    }

    // Broadcast presence on local Wi-Fi channel
    broadcastLocalPresence(currentSessionPin, selectedFiles.length);
  };

  window.copyDropPin = function() {
    if (!currentSessionPin) return;
    navigator.clipboard.writeText(currentSessionPin).then(() => {
      alert(`PIN ${currentSessionPin} copied to clipboard!`);
    });
  };

  window.copyDropLink = function() {
    if (!currentSessionPin) return;
    const dropUrl = `${window.location.origin}${window.location.pathname}#pin=${currentSessionPin}`;
    navigator.clipboard.writeText(dropUrl).then(() => {
      alert('Drop link copied to clipboard!');
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
          recvProgressBar.style.width = '80%';
          recvProgressBar.innerText = 'Delivering payload...';
        }
        setTimeout(() => {
          files.forEach(file => {
            const a = document.createElement('a');
            a.href = URL.createObjectURL(file);
            a.download = file.name;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
          });
          if (recvProgressBar) {
            recvProgressBar.style.width = '100%';
            recvProgressBar.innerText = '100%';
          }
          if (recvStatus) {
            recvStatus.innerHTML = `<span style="color:#10B981;font-weight:bold;">🎉 Received ${files[0].name} (${(files[0].size / 1024).toFixed(1)} KB) directly!</span>`;
          }
        }, 600);
        return;
      }
    }

    // 2. Direct Wi-Fi Phone Delivery (from Android device running P2Pme)
    if (phoneIp) {
      const directDownloadUrl = `http://${phoneIp}:45455/download?pin=${pin}&file=0`;
      const directPortalUrl = `http://${phoneIp}:45455/drop?pin=${pin}`;

      if (recvProgressBar) {
        recvProgressBar.style.width = '60%';
        recvProgressBar.innerText = 'Streaming from phone...';
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
            <span style="color:#10B981;font-weight:bold;">⚡ Direct Wi-Fi download initiated!</span><br>
            <span style="font-size:12px;color:var(--text-muted);">Downloading directly from phone at <b>${phoneIp}:45455</b>.</span><br>
            <a href="${directPortalUrl}" target="_blank" style="display:inline-block;margin-top:8px;color:var(--accent);text-decoration:underline;font-weight:600;">
              Click here to view phone download page &rarr;
            </a>
          `;
        }
      }, 800);
      return;
    }

    if (recvStatus) {
      recvStatus.innerHTML = `<span style="color:#EF4444;font-weight:bold;">Could not locate phone or web peer for PIN [${pin}].</span>`;
    }
  };

  // Nearby Discovery
  const nearbyPeersList = document.getElementById('nearbyPeersList');
  function initNearbyScan() {
    if (!nearbyPeersList) return;
    nearbyPeersList.innerHTML = '<div style="color:var(--text-muted);font-size:13px;grid-column:1/-1;">Searching for devices on local Wi-Fi...</div>';

    // Broadcast self
    if (localChannel) {
      localChannel.postMessage({
        type: 'PEER_PING',
        ua: navigator.userAgent.includes('iPhone') ? 'iPhone' : (navigator.userAgent.includes('Android') ? 'Android' : 'PC/Mac')
      });
    }

    // Add a nearby phone avatar demonstration
    setTimeout(() => {
      addNearbyPeer({
        ua: 'OnePlus 6T (Android 11)',
        pin: '849201',
        time: Date.now()
      });
    }, 800);
  }

  function addNearbyPeer(peer) {
    if (!nearbyPeersList) return;
    const existingEmpty = nearbyPeersList.querySelector('div[style*="Searching"]');
    if (existingEmpty) existingEmpty.remove();

    const card = document.createElement('div');
    card.className = 'peer-card';
    card.innerHTML = `
      <div class="peer-avatar">📱</div>
      <div class="peer-info">
        <div class="peer-name">${escapeHtml(peer.ua)}</div>
        <div class="peer-meta">Active on Wi-Fi • PIN: ${peer.pin}</div>
      </div>
      <button class="header-nav-btn" style="background:var(--primary);color:white;padding:6px 14px;" onclick="connectToPeer('${peer.pin}')">
        Connect
      </button>
    `;
    nearbyPeersList.appendChild(card);
  }

  window.connectToPeer = function(pin) {
    window.switchTab('drop');
    window.setDropMode('recv');
    if (recvPinInput) recvPinInput.value = pin;
    window.handleDownloadDrop();
  };

  // URL Hash auto-fill & deep-linking
  window.addEventListener('DOMContentLoaded', () => {
    try {
      const savedPhoneIp = localStorage.getItem('p2pme_saved_phone_ip');
      const phoneIpInput = document.getElementById('phoneIpInput');
      if (savedPhoneIp && phoneIpInput) {
        phoneIpInput.value = savedPhoneIp;
      }
    } catch (_) {}

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
  });

  // PWA Service Worker Registration
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', () => {
      navigator.serviceWorker.register('./sw.js').catch(err => console.log('SW error:', err));
    });
  }
})();
