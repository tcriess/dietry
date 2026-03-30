// Dietry Service Worker
// Bump CACHE_VERSION on every production deploy to invalidate old caches.
const CACHE_VERSION = 'v2';
const CACHE_NAME = `dietry-${CACHE_VERSION}`;

// Only truly static assets that never change between deploys.
const STATIC_ASSETS = [
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/favicon.png',
  '/manifest.json',
];

// Install: cache only static icons/manifest, then take over immediately.
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

// Activate: delete all old caches, then claim all clients.
// Claiming causes open pages to fire 'controllerchange', which triggers
// an automatic reload (see index.html).
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Auth & API requests: always network, never cache.
  if (url.hostname.includes('neonauth') || url.hostname.includes('neon.tech')) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Flutter app files (.js, .wasm, .html, /): network-first so new builds
  // are always picked up, fall back to cache only when offline.
  if (
    url.pathname === '/' ||
    url.pathname.endsWith('.html') ||
    url.pathname.endsWith('.js') ||
    url.pathname.endsWith('.wasm')
  ) {
    event.respondWith(
      fetch(event.request).catch(() => caches.match(event.request))
    );
    return;
  }

  // Static icons/manifest: cache-first.
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request))
  );
});
