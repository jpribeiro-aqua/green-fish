/* Service worker do app RAS Multitanques: guarda o app para abrir sem internet.
   Ao publicar uma versão nova do index.html, aumente o número em VERSAO. */
const VERSAO = "ras-v58";
const BASE = ["./", "index.html", "config.js", "manifest.webmanifest", "icon-192.png", "icon-512.png", "maskable-512.png", "apple-touch-icon.png", "favicon-64.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(VERSAO).then(c => c.addAll(BASE)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== VERSAO).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const r = e.request, u = new URL(r.url);
  if (r.method !== "GET") return;
  if (/supabase\.co$/.test(u.hostname)) return;                 // login e dados: sempre pela rede
  const mesmo = u.origin === self.location.origin;
  if (mesmo && (r.mode === "navigate" || /\.(html|js|webmanifest)$/.test(u.pathname))) {
    // app: tenta a rede (pega versões novas) e cai para a cópia guardada se estiver sem internet
    // cache: "no-store" fura o cache do navegador (o GitHub Pages guarda o index por 10 min)
    e.respondWith(fetch(r.url, { cache: "no-store", credentials: "same-origin" }).then(res => { if (res.ok) { const c = res.clone(); caches.open(VERSAO).then(k => k.put(r, c)); } return res; })
      .catch(() => caches.match(r).then(x => x || caches.match("index.html"))));
    return;
  }
  if (mesmo || /fonts\.(googleapis|gstatic)\.com$|cdn\.jsdelivr\.net$/.test(u.hostname)) {
    // ícones, fontes e biblioteca de login: usa a cópia guardada e atualiza em segundo plano
    e.respondWith(caches.match(r).then(x => { const f = fetch(r).then(res => { if (res.ok || res.type === "opaque") { const c = res.clone(); caches.open(VERSAO).then(k => k.put(r, c)); } return res; }).catch(() => x); return x || f; }));
  }
});
