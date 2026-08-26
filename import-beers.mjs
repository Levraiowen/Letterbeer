/**
 * LETTERBEER — import des bières EN CANETTE depuis Open Food Facts
 *
 *   npm install @supabase/supabase-js
 *   export SUPABASE_URL="https://ton-projet.supabase.co"
 *   export SUPABASE_SERVICE_KEY="ta-cle-service-role"
 *   node import-beers.mjs
 *
 * Stratégie, après mesure du fonds réel d'Open Food Facts :
 *
 *   12 151  bières dans le monde
 *      559  avec un emballage « canette » renseigné
 *      634  avec un matériau « aluminium »
 *      407  avec une forme « canette »
 *
 * Autrement dit, le champ emballage n'est rempli que sur environ 5 % des
 * fiches. S'y fier seul plafonnerait la base bien en dessous de 500 après
 * les filtres qualité. On procède donc en deux temps :
 *
 *   1. les facettes emballage donnent des canettes CERTAINES  → approved
 *   2. un balayage large donne des candidates AMBIGUËS        → pending
 *
 * Les ambiguës atterrissent dans l'écran « Fiches à valider » de l'app :
 * une bière douteuse se tranche à l'œil en deux secondes sur sa photo,
 * là où aucune règle automatique ne s'en sortirait. Tout ce qui porte un
 * signal bouteille, ou dépasse 56 cl, est écarté sans passer par la case
 * modération — c'est ce laxisme qui avait rempli la base de 75 cl.
 *
 * Données sous licence ODbL, photos en CC-BY-SA : l'attribution
 * « Données © Open Food Facts, sous licence ODbL » figure dans l'app.
 */

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY;
const UA = 'Letterbeer/0.2 (contact: ton.email@exemple.fr)';

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("Il manque SUPABASE_URL ou SUPABASE_SERVICE_KEY dans l'environnement.");
  process.exit(1);
}

const sb = createClient(SUPABASE_URL, SERVICE_KEY);
const PAUSE = 1500;
const sleep = ms => new Promise(r => setTimeout(r, ms));

const FIELDS = [
  'code','product_name','brands','quantity','packaging_tags','packaging_materials_tags',
  'packaging_shapes_tags','categories_tags','countries_tags','image_front_url',
  'image_front_small_url','nutriments','labels_tags'
].join(',');

/* Les trois facettes d'abord : elles rapportent des canettes sûres.
   Le balayage large ensuite, pour les candidates à trancher à la main. */
const RECHERCHES = [
  /* Les plus scannées d'abord. C'est la source qui rapporte les canettes que
     tout le monde connaît — 1664, Desperados, Grimbergen, Leffe — là où le
     balayage large remonte surtout des références confidentielles.
     Elle passe par l'API HISTORIQUE et non par la v2 : seule la première
     accepte sort_by=popularity_key, vérifié. */
  { nom:'France, les plus connues',   q:'countries_tags=france',  pages:12, sur:false, pop:true },
  { nom:'Belgique, les plus connues', q:'countries_tags=belgium', pages:5,  sur:false, pop:true },

  { nom:'emballage canette',  q:'packaging_tags=en:can',                  pages:8,  sur:true  },
  { nom:'matériau aluminium', q:'packaging_materials_tags=en:aluminium',  pages:8,  sur:true  },
  { nom:'forme canette',      q:'packaging_shapes_tags=en:can',           pages:6,  sur:true  },
  { nom:'France, large',      q:'countries_tags_en=france',               pages:25, sur:false },
  { nom:'Belgique, large',    q:'countries_tags_en=belgium',              pages:8,  sur:false },
  { nom:'Monde, large',       q:'',                                       pages:25, sur:false }
];

/* ---------- style ---------- */
const STYLES = [
  [/neipa|hazy|new.?england/i,          'NEIPA'],
  [/session.?ipa/i,                      'Session IPA'],
  [/\bipa\b|india.?pale/i,               'IPA'],
  [/imperial.?stout|russian.?imperial/i, 'Imperial Stout'],
  [/\bstout\b/i,                         'Stout'],
  [/\bporter\b/i,                        'Porter'],
  [/gose/i,                              'Gose'],
  [/sour|berliner|lambic|gueuze|kriek/i, 'Sour'],
  [/saison|farmhouse/i,                  'Saison'],
  [/pils|pilsner|pilsener/i,             'Pils'],
  [/blanche|witbier|weizen|weisse|wheat/i,'Blanche'],
  [/triple|tripel/i,                     'Triple'],
  [/double|dubbel/i,                     'Double'],
  [/ambree|amber|rousse/i,               'Ambrée'],
  [/brune|brown|dunkel/i,                'Brune'],
  [/blonde|helles|lager|biere.?blonde/i, 'Blonde'],
  [/sans.?alcool|alcohol.?free|0[.,]0/i, 'Sans alcool']
];
const guessStyle = (name, cats) => {
  const hay = `${name} ${cats.join(' ')}`;
  for (const [re, label] of STYLES) if (re.test(hay)) return label;
  return 'Non précisé';
};

const COLORS = {
  'NEIPA':'#FF7A2F','IPA':'#FFB020','Session IPA':'#5FC9E8','Imperial Stout':'#8A6244',
  'Stout':'#9B8B7A','Porter':'#A08670','Gose':'#7FD1D9','Sour':'#FF5D8F','Saison':'#C9E265',
  'Pils':'#E8DFA0','Blanche':'#EFE3C8','Triple':'#F0C97A','Double':'#D89A5A','Ambrée':'#E0603A',
  'Brune':'#8C6A4F','Blonde':'#F2D06B','Sans alcool':'#9FD8C0','Non précisé':'#B0B0B8'
};

/* ---------- volume ---------- */
const parseCl = q => {
  if (!q) return null;
  const s = q.toLowerCase().replace(',', '.');
  let m = s.match(/([\d.]+)\s*cl/);  if (m) return Math.round(+m[1]);
  m = s.match(/([\d.]+)\s*ml/);      if (m) return Math.round(+m[1] / 10);
  m = s.match(/([\d.]+)\s*l\b/);     if (m) return Math.round(+m[1] * 100);
  return null;
};

/* ---------- canette, bouteille, ou à trancher ? ----------
 *
 * L'ancienne version cherchait « metal » dans les emballages. Une capsule
 * de bouteille est en métal : toutes les bouteilles passaient. D'où les
 * 75 cl et 150 cl arrivés dans une base censée n'avoir que des canettes.
 */
const SIGNAL_CANETTE   = /\bcanette\b|\bcannette\b|\bcan\b|boite-boisson|\baluminium\b|\balu\b/i;
const SIGNAL_BOUTEILLE = /bouteille|bottle|\bverre\b|\bglass\b|\bbottiglia\b/i;

function classer(p) {
  const cl = parseCl(p.quantity);

  // aucune canette n'existe au-delà de 56 cl : le volume tranche seul
  if (cl && cl > 56) return 'bouteille';

  const tags = [
    ...(p.packaging_tags || []),
    ...(p.packaging_materials_tags || []),
    ...(p.packaging_shapes_tags || [])
  ].join(' ');
  const quantite = (p.quantity || '');

  const canette   = SIGNAL_CANETTE.test(tags)   || SIGNAL_CANETTE.test(quantite);
  const bouteille = SIGNAL_BOUTEILLE.test(tags) || SIGNAL_BOUTEILLE.test(quantite);

  if (bouteille && !canette) return 'bouteille';
  if (canette && !bouteille) return 'canette';
  return null;                                   // à trancher à l'œil
}

/* ---------- nettoyage des noms ----------
 *
 * Ces règles vivaient dans sql/03-nettoyage-noms.sql, une migration qui n'a
 * tourné qu'une fois. Le script d'import, lui, n'en avait aucune : chaque
 * passage réintroduisait des noms bruts d'Open Food Facts. D'où les « 8.6 Red »
 * suivis d'une espace, et les « Alhambra Beer   Premium Lager » retrouvés en
 * base longtemps après. Leur place est ici, à l'entrée, pas dans un rattrapage.
 *
 * Un écart volontaire avec la migration 03 : elle remplaçait la brasserie par
 * « Inconnue » quand elle valait le nom, mais faisait ce test AVANT de nettoyer
 * le nom. « Jupiler 33cl » ne déclenchait donc rien, puis devenait « Jupiler » —
 * d'où la quinzaine de fiches qui affichent « Jupiler · Jupiler ». On compare
 * ici au nom brut, ce que la règle visait réellement : une brasserie qui n'est
 * que le nom du produit recopié.
 */
const PACK = /\d+\s*[x×]\s*\d+([.,]\d+)?\s*(cl|ml)/i;

function nettoyerNom(nom, brasserie) {
  let n = nom;
  n = n.replace(/\s*\d+([.,]\d+)?\s*(cl|ml)\b/gi, '');                 // « 33cl », « 25 cl »
  n = n.replace(/\s*\d+([.,]\d+)?\s*(°|degrés?|degres?)\s*(alcool)?/gi, ''); // « 8° », « 6.5 DEGRE ALCOOL »
  n = n.replace(/\s*\d+([.,]\d+)?\s*%\s*v(ol)?\.?\b/gi, '');           // « 8%V », « 9% vol. »
  n = n.replace(/\s*\d+([.,]\d+)?\s*%(?!\w)/gi, '');                   // « 6,8% »

  // la brasserie répétée à l'intérieur du nom
  if (brasserie) {
    const i = n.toLowerCase().indexOf(brasserie.toLowerCase());
    if (i >= 0 && n.trim().toLowerCase() !== brasserie.toLowerCase())
      n = n.slice(0, i) + n.slice(i + brasserie.length);
  }

  n = n.replace(/\s{2,}/g, ' ').trim();
  n = n.replace(/[\s\-.,]+$/, '').trim();

  // casse propre si le nom était tout en majuscules
  if (n && n === n.toUpperCase() && /[A-ZÀ-Ý]/.test(n))
    n = n.toLowerCase().replace(/(^|[\s'’\-])([a-zà-ÿ])/g, (_, a, b) => a + b.toUpperCase());

  return n;
}

/* ---------- filtre qualité ---------- */
function clean(p) {
  const nomBrut = (p.product_name || '').trim();

  // Un pack : le volume annoncé est celui du pack entier, pas d'une canette.
  // La donnée est fausse en plus du nom sale, donc on écarte plutôt que de
  // corriger à moitié.
  if (PACK.test(nomBrut)) return null;

  let brand = (p.brands || '').split(',')[0].trim();
  if (brand && brand.toLowerCase() === nomBrut.toLowerCase()) brand = 'Inconnue';

  const name  = nettoyerNom(nomBrut, brand === 'Inconnue' ? '' : brand);
  const cl    = parseCl(p.quantity);
  const abv   = p.nutriments?.alcohol_value ?? p.nutriments?.alcohol_100g ?? null;
  const img   = p.image_front_url || p.image_front_small_url || null;

  // 3 et non 2 : en dessous, ce qui reste après nettoyage n'est plus un nom
  if (name.length < 3 || name.length > 80) return null;
  if (!brand) return null;
  if (!cl || cl < 10 || cl > 56) return null;    // au-delà, ce n'est plus une canette
  if (abv === null || abv < 0 || abv > 20) return null;
  if (!img) return null;
  if (/^\d+$/.test(name)) return null;

  const verdict = classer(p);
  if (verdict === 'bouteille') return null;      // écartée, sans discussion

  const cats    = p.categories_tags || [];
  const style   = guessStyle(name, cats);
  const country = (p.countries_tags || []).some(t => /france/.test(t)) ? 'France' : 'Autre';
  const sure    = verdict === 'canette';

  return {
    barcode: p.code,
    name,
    brewery: brand,
    style,
    abv: Math.round(abv * 10) / 10,
    volume_cl: cl,
    container: sure ? 'canette' : null,
    country,
    image_url: img,
    color: COLORS[style] || '#B0B0B8',
    description: `${style} de ${brand}, ${abv}°, canette ${cl} cl. `
      + (sure ? "Fiche importée d'Open Food Facts — complète-la si tu en sais plus."
              : "Contenant non confirmé par Open Food Facts : à vérifier sur la photo."),
    // certaine → visible tout de suite ; douteuse → écran de modération
    status: sure ? 'approved' : 'pending'
  };
}

/* Tri par popularité : seule l'API historique le propose. Elle renvoie une
   page HTML quand elle limite le débit, d'où le contrôle sur le premier
   caractère — un JSON.parse direct lèverait une erreur illisible. */
async function pagePopulaire(q, n) {
  const url = 'https://world.openfoodfacts.org/cgi/search.pl'
            + '?action=process&json=1&sort_by=popularity_key&page_size=100&page=' + n
            + '&tagtype_0=categories&tag_contains_0=contains&tag_0=beers'
            + '&' + q.replace('countries_tags=', 'tagtype_1=countries&tag_contains_1=contains&tag_1=')
            + '&fields=' + FIELDS;
  for (let essai = 1; essai <= 4; essai++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      const txt = await res.text();
      if (txt.trim().startsWith('{')) return JSON.parse(txt).products || [];
      process.stdout.write('(débit limité, pause) ');
      await sleep(8000 * essai);
    } catch (e) {
      console.warn('  ! ' + e.message);
      await sleep(4000 * essai);
    }
  }
  return [];
}

/* ---------- API, avec reprise sur 503 ---------- */
async function page(q, n) {
  const url = 'https://world.openfoodfacts.org/api/v2/search'
            + '?categories_tags_en=beers' + (q ? '&' + q : '')
            + '&fields=' + FIELDS + '&page_size=100&page=' + n;
  for (let essai = 1; essai <= 4; essai++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA, 'Accept': 'application/json' } });
      if (res.ok) return (await res.json()).products || [];
      if (res.status === 503 || res.status === 429) {
        process.stdout.write(`(serveur occupé, pause) `);
        await sleep(6000 * essai);
        continue;
      }
      console.warn(`  ! HTTP ${res.status}`);
      return [];
    } catch (e) {
      await sleep(3000 * essai);
    }
  }
  return [];
}

/* ---------- boucle ---------- */
async function run() {
  const vus = new Set();     // codes-barres déjà traités
  const gardees = new Map(); // barcode -> fiche

  for (const r of RECHERCHES) {
    console.log(`\n▸ ${r.nom}`);
    for (let n = 1; n <= r.pages; n++) {
      const produits = r.pop ? await pagePopulaire(r.q, n) : await page(r.q, n);
      if (!produits.length) { console.log(`  page ${n} : plus rien`); break; }

      let neufs = 0;
      for (const p of produits) {
        if (!p.code || vus.has(p.code)) continue;
        vus.add(p.code);
        const b = clean(p);
        if (b) { gardees.set(p.code, b); neufs++; }
      }
      const sures = [...gardees.values()].filter(b => b.status === 'approved').length;
      console.log(`  page ${n} : +${neufs} retenues · total ${gardees.size} (${sures} sûres)`);
      // l'API historique limite plus sévèrement que la v2
      await sleep(r.pop ? Math.max(PAUSE, 4000) : PAUSE);
    }
  }

  const lot = [...gardees.values()];
  const sures  = lot.filter(b => b.status === 'approved');
  const douteuses = lot.filter(b => b.status === 'pending');
  console.log(`\n${lot.length} fiches prêtes : ${sures.length} canettes confirmées, `
            + `${douteuses.length} à valider à la main.`);
  if (!lot.length) return;

  // ignoreDuplicates : on n'écrase jamais une fiche déjà nettoyée à la main
  for (let i = 0; i < lot.length; i += 50) {
    const paquet = lot.slice(i, i + 50);
    const { error } = await sb.from('beers')
      .upsert(paquet, { onConflict: 'barcode', ignoreDuplicates: true });
    if (error) console.error('Erreur insertion :', error.message);
    else console.log(`  traitées ${i + paquet.length}/${lot.length}`);
  }

  console.log(`\nTerminé. Les fiches déjà présentes n'ont pas été touchées.`);
  console.log(`Ouvre « Fiches à valider » dans l'app pour trancher les ${douteuses.length} douteuses.`);
  console.log(`Puis lance enrich-beers.mjs pour les calories et les allergènes.`);
}

run().catch(console.error);
