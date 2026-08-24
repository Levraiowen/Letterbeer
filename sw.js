/**
 * LETTERBEER — service worker
 *
 * Objectif : qu'une app installée qui perd le réseau affiche quelque chose
 * plutôt qu'un écran vide. On ne prétend pas fonctionner hors ligne pour de
 * bon — les données vivent chez Supabase et dépendent de la session — mais
 * la coque et les photos déjà vues restent disponibles.
 *
 * Trois stratégies, selon ce qui est demandé :
 *   coque      → cache d'abord, on met à jour en arrière-plan
 *   photos     → cache d'abord, elles ne changent jamais
 *   API/auth   → réseau uniquement, jamais de données périmées ni de jeton en cache
 */

const VERSION = 'lb-v3.2.1';
const COQUE   = VERSION + '-coque';
const PHOTOS  = VERSION + '-photos';

// tout est relatif : le site vit dans un sous-dossier sur GitHub Pages
const COQUE_FICHIERS = [
  './',
  './index.html',
  './logo.svg',
  './icon-192.png',
  './icon-512.png',
  './manifest.webmanifest'
];

const MAX_PHOTOS = 400;   // ~25 Mo, largement sous les quotas navigateur

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(COQUE)
      // addAll échoue en bloc si un seul fichier manque : on tolère les absents
      .then(c => Promise.allSettled(COQUE_FICHIERS.map(f => c.add(f))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(noms => Promise.all(
        noms.filter(n => !n.startsWith(VERSION)).map(n => caches.delete(n))
      ))
      .then(() => self.clients.claim())
  );
});

/* Le cache des photos n'a pas de purge automatique : on le borne à la main,
   en retirant les plus anciennes entrées quand il déborde. */
async function bornerCache(nom, max) {
  const c = await caches.open(nom);
  const cles = await c.keys();
  if (cles.length <= max) return;
  await Promise.all(cles.slice(0, cles.length - max).map(k => c.delete(k)));
}

self.addEventListener('fetch', e => {
  const { request } = e;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Supabase : données et authentification, jamais mises en cache.
  // Une réponse périmée vaudrait pire qu'une erreur franche.
  if (url.hostname.endsWith('.supabase.co')) return;

  // Photos de bières et d'avatars : elles ne changent pas, cache d'abord.
  const estPhoto = /\.(jpe?g|png|webp|avif)$/i.test(url.pathname)
                || url.hostname.includes('openfoodfacts');
  if (estPhoto) {
    e.respondWith(
      caches.match(request).then(hit => hit || fetch(request).then(res => {
        if (res.ok || res.type === 'opaque') {
          const copie = res.clone();
          caches.open(PHOTOS)
            .then(c => c.put(request, copie))
            .then(() => bornerCache(PHOTOS, MAX_PHOTOS));
        }
        return res;
      }).catch(() => hit))
    );
    return;
  }

  // Navigation : on sert la coque en cache immédiatement, et on rafraîchit
  // en arrière-plan pour que la version suivante soit à jour.
  if (request.mode === 'navigate') {
    e.respondWith(
      caches.match('./index.html').then(hit => {
        const reseau = fetch(request).then(res => {
          if (res.ok) caches.open(COQUE).then(c => c.put('./index.html', res.clone()));
          return res;
        }).catch(() => hit);
        return hit || reseau;
      })
    );
    return;
  }

  // Le reste (polices, script Supabase) : cache d'abord, réseau en secours.
  e.respondWith(
    caches.match(request).then(hit => hit || fetch(request).then(res => {
      if (res.ok && url.origin === self.location.origin) {
        const copie = res.clone();
        caches.open(COQUE).then(c => c.put(request, copie));
      }
      return res;
    }))
  );
});
