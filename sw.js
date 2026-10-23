/* Offline support for the installed app: the page itself is fetched fresh when online (so updates
   arrive) and served from cache when offline; libraries and fonts are cached after first use. */
const CACHE='thief-village-v14';
const SHELL=['./','./index.html','./manifest.webmanifest','./lib/three.min.js','./lib/peerjs.min.js','./privacy.html','./fonts/fonts.css','./fonts/lalezar.woff','./fonts/readexpro-400.woff','./fonts/readexpro-600.woff','./icons/icon-192.png','./icons/icon-512.png'];
self.addEventListener('install',e=>{ e.waitUntil(caches.open(CACHE).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{}))))); self.skipWaiting(); });
self.addEventListener('activate',e=>{ e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k))))); self.clients.claim(); });
self.addEventListener('fetch',e=>{
  const r=e.request; if(r.method!=='GET') return;
  const u=new URL(r.url);
  if(u.origin===self.location.origin){
    e.respondWith(fetch(r).then(res=>{ if(res.ok){ const cp=res.clone(); caches.open(CACHE).then(c=>c.put(r,cp)); } return res; })
      .catch(()=>caches.match(r).then(m=>m||caches.match('./index.html'))));
  } else if(/(^|\.)(cdnjs\.cloudflare\.com|cdn\.jsdelivr\.net|unpkg\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)$/.test(u.hostname)){
    e.respondWith(caches.match(r).then(m=>m||fetch(r).then(res=>{ if(res.ok||res.type==='opaque'){ const cp=res.clone(); caches.open(CACHE).then(c=>c.put(r,cp)); } return res; })));
  }
});
