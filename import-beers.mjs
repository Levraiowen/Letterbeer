/**
 * LETTERBEER — import des bières en canette depuis Open Food Facts
 *
 *   npm install @supabase/supabase-js
 *   node import-beers.mjs
 *
 * Données sous licence ODbL, photos en CC-BY-SA : l'attribution
 * « Données © Open Food Facts, sous licence ODbL » est obligatoire dans l'app.
 *
 * Open Food Facts demande un User-Agent explicite et de ne pas marteler
 * l'API. Ce script pagine doucement. Pour plus de quelques centaines de
 * produits, passer par les exports JSONL plutôt que par l'API live.
 */

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY; // clé service_role, jamais côté navigateur
const UA = 'Letterbeer/0.1 (contact: ton.email@exemple.fr)';

const sb = createClient(SUPABASE_URL, SERVICE_KEY);

const PAGES = 8;          // 8 x 100 = 800 produits balayés
const PAUSE = 1500;       // ms entre deux appels, on reste poli

const FIELDS = [
  'code','product_name','brands','quantity','packaging_tags','categories_tags',
  'countries_tags','image_front_url','image_front_small_url','nutriments','labels_tags'
].join(',');

/* ---------- déduction du style à partir des catégories et du nom ---------- */
const STYLES = [
  [/neipa|hazy|new.?england/i,        'NEIPA'],
  [/session.?ipa/i,                    'Session IPA'],
  [/\bipa\b|india.?pale/i,             'IPA'],
  [/imperial.?stout|russian.?imperial/i,'Imperial Stout'],
  [/\bstout\b/i,                       'Stout'],
  [/\bporter\b/i,                      'Porter'],
  [/gose/i,                            'Gose'],
  [/sour|berliner|lambic|gueuze|kriek/i,'Sour'],
  [/saison|farmhouse/i,                'Saison'],
  [/pils|pilsner|pilsener/i,           'Pils'],
  [/blanche|witbier|weizen|weisse|wheat/i,'Blanche'],
  [/triple|tripel/i,                   'Triple'],
  [/double|dubbel/i,                   'Double'],
  [/ambree|amber|rousse/i,             'Ambrée'],
  [/brune|brown|dunkel/i,              'Brune'],
  [/blonde|helles|lager|biere.?blonde/i,'Blonde'],
  [/sans.?alcool|alcohol.?free|0[.,]0/i,'Sans alcool']
];
const guessStyle = (name, cats) => {
  const hay = `${name} ${cats.join(' ')}`;
  for (const [re, label] of STYLES) if (re.test(hay)) return label;
  return 'Non précisé';
};

/* ---------- couleur du bandeau, dérivée du style ---------- */
const COLORS = {
  'NEIPA':'#FF7A2F','IPA':'#FFB020','Session IPA':'#5FC9E8','Imperial Stout':'#8A6244',
  'Stout':'#9B8B7A','Porter':'#A08670','Gose':'#7FD1D9','Sour':'#FF5D8F','Saison':'#C9E265',
  'Pils':'#E8DFA0','Blanche':'#EFE3C8','Triple':'#F0C97A','Double':'#D89A5A','Ambrée':'#E0603A',
  'Brune':'#8C6A4F','Blonde':'#F2D06B','Sans alcool':'#9FD8C0','Non précisé':'#B0B0B8'
};

/* ---------- volume : on ne garde que les canettes ---------- */
const parseCl = q => {
  if (!q) return null;
  const s = q.toLowerCase().replace(',', '.');
  let m = s.match(/([\d.]+)\s*cl/);        if (m) return Math.round(+m[1]);
  m = s.match(/([\d.]+)\s*ml/);            if (m) return Math.round(+m[1] / 10);
  m = s.match(/([\d.]+)\s*l\b/);           if (m) return Math.round(+m[1] * 100);
  return null;
};
const isCan = p => {
  const tags = (p.packaging_tags || []).join(' ');
  return /canette|can\b|boite-metal|metal|aluminium|cannette/i.test(tags);
};

/* ---------- filtre qualité : on rejette les fiches creuses ---------- */
function clean(p) {
  const name = (p.product_name || '').trim();
  const brand = (p.brands || '').split(',')[0].trim();
  const cl = parseCl(p.quantity);
  const abv = p.nutriments?.alcohol_value ?? p.nutriments?.alcohol_100g ?? null;
  const img = p.image_front_url || p.image_front_small_url || null;

  if (name.length < 2 || name.length > 80) return null;
  if (!brand) return null;
  if (!cl || cl < 10 || cl > 200) return null;
  if (abv === null || abv < 0 || abv > 20) return null;
  if (!img) return null;                       // pas de photo, pas de fiche
  if (!isCan(p)) return null;                  // canettes uniquement
  if (/^\d+$/.test(name)) return null;         // noms bidons

  const cats = p.categories_tags || [];
  const style = guessStyle(name, cats);
  const country = (p.countries_tags || []).some(t => /france/.test(t)) ? 'France' : 'Autre';

  return {
    barcode: p.code,
    name,
    brewery: brand,
    style,
    abv: Math.round(abv * 10) / 10,
    volume_cl: cl,
    country,
    image_url: img,
    color: COLORS[style] || '#B0B0B8',
    description: `${style} de ${brand}, ${abv}°, canette ${cl} cl. Fiche importée d'Open Food Facts — complète-la si tu en sais plus.`,
    status: 'approved'          // source fiable : validé d'office
  };
}

/* ---------- boucle d'import ---------- */
async function run() {
  const seen = new Set();
  const batch = [];

  for (let page = 1; page <= PAGES; page++) {
    const url = 'https://world.openfoodfacts.org/api/v2/search'
      + '?categories_tags_en=beers'
      + '&countries_tags_en=france'
      + '&fields=' + FIELDS
      + '&page_size=100&page=' + page;

    process.stdout.write(`Page ${page}… `);
    const res = await fetch(url, { headers: { 'User-Agent': UA } });

    if (res.status === 503) { console.log('rate-limité, on attend 30 s'); await sleep(30000); page--; continue; }
    if (!res.ok) { console.log('erreur HTTP ' + res.status); break; }

    const { products = [] } = await res.json();
    if (!products.length) { console.log('plus rien'); break; }

    let kept = 0;
    for (const p of products) {
      const b = clean(p);
      if (!b) continue;
      const key = (b.name + b.brewery).toLowerCase().replace(/[^a-z0-9]/g, '');
      if (seen.has(key)) continue;
      seen.add(key);
      batch.push(b);
      kept++;
    }
    console.log(`${products.length} produits, ${kept} canettes retenues`);
    await sleep(PAUSE);
  }

  console.log(`\n${batch.length} bières prêtes à insérer.`);
  if (!batch.length) return;

  // insertion par paquets de 50, on ignore les doublons de code-barres
  for (let i = 0; i < batch.length; i += 50) {
    const chunk = batch.slice(i, i + 50);
    const { error } = await sb.from('beers').upsert(chunk, { onConflict: 'barcode' });
    if (error) console.error('Erreur insertion :', error.message);
    else console.log(`Insérées ${i + chunk.length}/${batch.length}`);
  }

  console.log('\nTerminé. Pense à afficher l\'attribution Open Food Facts dans l\'app.');
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
run().catch(console.error);
