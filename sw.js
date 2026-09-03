// SPINPRO Portal — service worker (required for PWA installability).
// Network-only: always loads the freshest content, never serves stale cache.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', (e) => {
  // A fetch handler must exist for the app to be installable, but it must NOT
  // intercept auth/API traffic — a stalled passthrough here can make Supabase's
  // signInWithPassword() POST never settle (button stuck on 'Processing...').
  // Only ever touch same-origin GET navigations; let everything else (the
  // Supabase auth POST, all cross-origin requests) go straight to the network.
  try {
    const url = new URL(e.request.url);
    if (e.request.method !== 'GET' || url.origin !== self.location.origin) return;
  } catch (_) { return; }
  e.respondWith(fetch(e.request));
});
