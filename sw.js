const CACHE='manzoomat-v54';
self.addEventListener('install',e=>{ self.skipWaiting(); });
self.addEventListener('activate',e=>{ e.waitUntil((async()=>{ const ks=await caches.keys(); await Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k))); await self.clients.claim(); })()); });
self.addEventListener('message',e=>{ if(e.data==='SKIP_WAITING') self.skipWaiting(); });
self.addEventListener('fetch',e=>{ const req=e.request; const u=new URL(req.url); if(u.hostname.includes('supabase')) return;
  const isDoc = req.mode==='navigate' || u.pathname.endsWith('/') || u.pathname.endsWith('index.html');
  if(isDoc){ e.respondWith((async()=>{ try{ const net=await fetch(req,{cache:'no-store'}); const c=await caches.open(CACHE); c.put('./index.html', net.clone()); return net; }catch(_){ return (await caches.match('./index.html'))||(await caches.match(req))||Response.error(); } })()); return; }
  e.respondWith(caches.match(req).then(r=> r || fetch(req).then(res=>{ const cp=res.clone(); caches.open(CACHE).then(c=>c.put(req,cp)); return res; }).catch(()=>caches.match('./index.html')))); });
