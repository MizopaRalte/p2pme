// P2Pme Service Worker - 100% Offline PWA Support (v20)
const CACHE_NAME = 'p2pme-v20';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './app.js',
  './qrcode.min.js',
  './icon-192.png',
  './icon-512.png'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(ASSETS).catch(() => {});
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) return caches.delete(key);
        })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Bypass service worker cache for dynamic upload and API endpoints
  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/upload') || url.pathname.includes('/downloads/')) {
    return;
  }

  // Cache-First with Stale-While-Revalidate for static app assets
  event.respondWith(
    caches.match(event.request).then((cached) => {
      const networkFetch = fetch(event.request).then((response) => {
        if (response && response.status === 200 && response.type === 'basic') {
          const toCache = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, toCache));
        }
        return response;
      }).catch(() => cached);

      return cached || networkFetch;
    })
  );
});
