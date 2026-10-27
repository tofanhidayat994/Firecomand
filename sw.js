/* Service worker Fire Command: aplikasi tetap terbuka tanpa sinyal.
   Naikkan VERSI setiap kali file aplikasi diubah agar HP memuat versi baru. */
const VERSI = 'fc-v1';
const INTI = ['./', 'index.html', 'config.js', 'manifest.webmanifest',
  'vendor/supabase.js', 'vendor/exceljs.min.js',
  'vendor/fonts/barlow-latin-400-normal.woff2', 'vendor/fonts/barlow-latin-500-normal.woff2', 'vendor/fonts/barlow-latin-600-normal.woff2',
  'vendor/fonts/barlow-condensed-latin-600-normal.woff2', 'vendor/fonts/barlow-condensed-latin-700-normal.woff2',
  'icons/icon-192.png', 'icons/icon-512.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSI).then(c => c.addAll(INTI)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(k => Promise.all(k.filter(n => n !== VERSI).map(n => caches.delete(n)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== 'GET' || u.origin !== location.origin) return;   // API Supabase tidak pernah di-cache
  const statis = /\/(vendor|icons)\//.test(u.pathname);
  e.respondWith((async () => {
    const c = await caches.open(VERSI);
    if (statis) {
      const hit = await c.match(r); if (hit) return hit;
      const res = await fetch(r); if (res.ok) c.put(r, res.clone()); return res;
    }
    try {   // jaringan dulu supaya versi terbaru terpakai, cadangan dari cache saat offline
      const res = await fetch(r);
      if (res.ok) c.put(r.mode === 'navigate' ? 'index.html' : r, res.clone());
      return res;
    } catch (err) {
      const hit = await c.match(r.mode === 'navigate' ? 'index.html' : r, { ignoreSearch: true });
      if (hit) return hit;
      throw err;
    }
  })());
});
