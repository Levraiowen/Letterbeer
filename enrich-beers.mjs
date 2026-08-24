/**
 * LETTERBEER — enrichissement nutrition des bières déjà en base
 *
 *   node supabase-nutrition.sql  (à passer d'abord dans le SQL Editor)
 *
 *   export SUPABASE_URL="https://ton-projet.supabase.co"
 *   export SUPABASE_SERVICE_KEY="ta-cle-service-role"
 *   node enrich-beers.mjs
 *
 * Aucune clé d'IA, aucun service payant : tout vient d'Open Food Facts,
 * via le code-barres déjà stocké sur chaque fiche. Les bières sans
 * code-barres, ou dont la fiche OFF n'a pas de nutrition, reçoivent une
 * estimation calculée depuis le degré — marquée comme telle.
 *
 * Données sous licence ODbL : l'attribution est déjà dans l'écran À propos.
 */

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY;
const UA = 'Letterbeer/0.1 (contact: ton.email@exemple.fr)';

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('Il manque SUPABASE_URL ou SUPABASE_SERVICE_KEY dans l\'environnement.');
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SERVICE_KEY);
const PAUSE = 1200;                       // ms entre deux appels : on reste poli
const sleep = ms => new Promise(r => setTimeout(r, ms));

/* ------------------------------------------------------------------
   Estimation des calories quand Open Food Facts ne les donne pas.

   L'alcool pèse 7,1 kcal/g et sa densité est 0,789 : un degré d'alcool
   apporte donc ~5,6 kcal par 100 ml. On y ajoute ~14 kcal de glucides
   résiduels, valeur moyenne d'une bière. À ~10 % près sur du vrai.
     5 %  -> 42 kcal/100ml -> 139 kcal la canette de 33 cl
     8,5% -> 62 kcal/100ml -> 203 kcal la canette de 33 cl
------------------------------------------------------------------- */
const estimateKcal100 = abv => Math.round(((+abv || 0) * 5.6 + 14) * 10) / 10;

/* ---------- lecture d'une fiche Open Food Facts ---------- */
async function fetchOFF(barcode) {
  const url = `https://world.openfoodfacts.org/api/v2/product/${barcode}`
            + `?fields=nutriments,allergens_tags,ingredients_text_fr,ingredients_text,traces_tags`;
  const res = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!res.ok) return null;
  const json = await res.json();
  return json?.status === 1 ? json.product : null;
}

/* ---------- nettoyage des tags allergènes : "en:gluten" -> "Gluten" ---------- */
const FR = {
  gluten:'Gluten', 'sulphur-dioxide-and-sulphites':'Sulfites', sulphites:'Sulfites',
  milk:'Lait', eggs:'Œufs', soybeans:'Soja', nuts:'Fruits à coque',
  celery:'Céleri', mustard:'Moutarde', sesame:'Sésame', fish:'Poisson',
  crustaceans:'Crustacés', molluscs:'Mollusques', peanuts:'Arachides', lupin:'Lupin'
};
const cleanTags = tags => [...new Set(
  (tags || []).map(t => {
    const key = String(t).replace(/^[a-z]{2}:/, '');
    return FR[key] || key.replace(/-/g, ' ').replace(/^./, c => c.toUpperCase());
  })
)].join(', ');

/* ---------- extraction des kcal pour 100 ml ---------- */
function kcalFrom(nutriments) {
  if (!nutriments) return null;
  // OFF donne parfois les kcal, parfois seulement les kJ (1 kcal = 4,184 kJ)
  const kcal = nutriments['energy-kcal_100g'] ?? nutriments['energy-kcal_value'];
  if (kcal != null && +kcal > 0 && +kcal < 200) return Math.round(+kcal * 10) / 10;
  const kj = nutriments['energy_100g'] ?? nutriments['energy-kj_100g'];
  if (kj != null && +kj > 0) {
    const v = Math.round((+kj / 4.184) * 10) / 10;
    if (v > 0 && v < 200) return v;
  }
  return null;
}

/* ---------- boucle ---------- */
async function main() {
  const { data: beers, error } = await sb
    .from('beers')
    .select('id,name,barcode,abv,kcal_100ml,allergens')
    .is('kcal_100ml', null);

  if (error) { console.error('Lecture impossible :', error.message); process.exit(1); }
  console.log(`${beers.length} bière(s) sans nutrition.\n`);

  let fromOFF = 0, estimated = 0, withAllerg = 0;

  for (const b of beers) {
    let kcal = null, allergens = null, ingredients = null, source = 'estimated';

    if (b.barcode) {
      try {
        const p = await fetchOFF(b.barcode);
        if (p) {
          kcal = kcalFrom(p.nutriments);
          if (kcal != null) source = 'off';
          const al = cleanTags([...(p.allergens_tags || []), ...(p.traces_tags || [])]);
          if (al) allergens = al;
          ingredients = (p.ingredients_text_fr || p.ingredients_text || '').trim() || null;
        }
      } catch (e) {
        console.warn(`  ! ${b.name} : ${e.message}`);
      }
      await sleep(PAUSE);
    }

    if (kcal == null) kcal = estimateKcal100(b.abv);

    const patch = { kcal_100ml: kcal, kcal_source: source };
    if (allergens)   { patch.allergens = allergens; withAllerg++; }
    if (ingredients) patch.ingredients = ingredients;

    const { error: upErr } = await sb.from('beers').update(patch).eq('id', b.id);
    if (upErr) { console.warn(`  ! ${b.name} : ${upErr.message}`); continue; }

    source === 'off' ? fromOFF++ : estimated++;
    console.log(`  ${source === 'off' ? '✓' : '≈'} ${b.name} — ${kcal} kcal/100ml${allergens ? ' · ' + allergens : ''}`);
  }

  console.log(`\nTerminé. ${fromOFF} relevée(s) sur Open Food Facts, ${estimated} estimée(s), `
            + `${withAllerg} avec allergènes.`);
}

main();
