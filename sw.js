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

const VERSION = 'lb-v3.6.0';
const COQUE   = VERSION + '-coque';
const PHOTOS  = VERSION + '-photos';

// tout est relatif : le site vit dans un sous-dossier sur GitHub Pages
const COQUE_FICHIERS = [
  './',
  './index.html',
  './logo.svg',
  './icon-192.png',
  './icon-512.png',
  './manifest.webmanifest',
  // sans la bibliothèque Supabase, le script ne démarre pas du tout :
  // elle doit être disponible hors ligne comme le reste de la coque
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.112.3/dist/umd/supabase.js'
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

  // Navigation : réseau d'abord, cache en secours.
  //
  // La version précédente servait le cache en premier. Sur une app qui
  // change tous les jours, ça bloquait les gens sur une version périmée
  // pendant un ou deux rechargements — avec des symptômes déroutants,
  // du genre mise en page cassée par un CSS d'une autre version.
  // Le cache reste là pour le hors-ligne, mais il ne passe plus devant.
  if (request.mode === 'navigate') {
    e.respondWith(
      fetch(request)
        .then(res => {
          if (res.ok) {
            const copie = res.clone();
            caches.open(COQUE).then(c => c.put('./index.html', copie));
          }
          return res;
        })
        .catch(() => caches.match('./index.html').then(hit => hit || caches.match('./')))
    );
    return;
  }

  // Le reste : cache d'abord, réseau en secours.
  //
  // La version précédente ne mettait en cache que les fichiers de notre
  // propre domaine. Or la bibliothèque Supabase et les polices viennent
  // de CDN externes : hors ligne, elles ne se chargeaient pas, la
  // bibliothèque manquait, et le script mourait sur une page blanche.
  // Ces adresses sont figées et versionnées : les garder est sans risque.
  e.respondWith(
    caches.match(request).then(hit => {
      if (hit) return hit;
      return fetch(request).then(res => {
        // opaque = réponse sans en-têtes CORS ; on la garde quand même,
        // elle reste rejouable telle quelle
        if (res && (res.ok || res.type === 'opaque')) {
          const copie = res.clone();
          caches.open(COQUE).then(c => c.put(request, copie)).catch(()=>{});
        }
        return res;
      }).catch(() => {
        // hors ligne et pas en cache : on rend une réponse vide plutôt
        // qu'une promesse rejetée, qui remonterait en erreur réseau brute
        return new Response('', { status: 504, statusText: 'hors ligne' });
      });
    })
  );
});
