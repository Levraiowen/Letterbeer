/**
 * LETTERBEER — combler les styles manquants du catalogue
 *
 *   export SUPABASE_URL="https://ton-projet.supabase.co"
 *   export SUPABASE_SERVICE_KEY="ta-cle-service-role"
 *
 *   node enrich-styles.mjs                 # simulation : n'écrit RIEN
 *   node enrich-styles.mjs --limite 20     # simulation sur vingt fiches
 *   node enrich-styles.mjs --ecrire        # écrit pour de bon
 *
 * POURQUOI
 *
 * 42 % des fiches n'ont aucun style (133 sur 318 à la dernière mesure). Le
 * tri par famille du premier lancement ne couvre donc que 58 % du catalogue,
 * et un profil « brunes + costaudes » n'a que trois canettes à proposer.
 * PROJET.md §4 tranche : « la seule vraie solution est d'enrichir les
 * données, pas d'améliorer l'heuristique ». C'est ce que fait ce script.
 *
 * D'OÙ VIENT LE STYLE
 *
 * Des catégories d'Open Food Facts, et de rien d'autre — pas du nom de la
 * bière. `beers.style` est une donnée relevée, jamais une supposition de
 * notre part (PROJET.md §7). L'app a déjà le droit de deviner une FAMILLE
 * depuis le nom, à l'affichage, sans toucher à la colonne : c'est
 * classerTexte() dans index.html. La déduction reste là-bas.
 *
 * Conséquence assumée : ce script laisse des fiches sans style. « Jupiler »
 * ou « Skoll » dont OFF ne dit que `en:beers` ressortent inchangées. C'est
 * le bon résultat. Le compte final le dit explicitement plutôt que de le
 * masquer derrière un taux de réussite.
 *
 * CE QU'IL NE TOUCHE JAMAIS
 *
 * Ni `status`, ni `container`. Une fiche en attente de validation le reste :
 * lui trouver un style ne prouve rien sur son contenant, et c'est
 * exactement le glissement qui a motivé la migration 32.
 *
 * Données sous licence ODbL : l'attribution est dans l'écran À propos.
 */

import { createClient } from '@supabase/supabase-js';
import { COULEURS, styleDepuisCategories } from './styles.mjs';

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY  = process.env.SUPABASE_SERVICE_KEY;
const UA = 'Letterbeer/0.2 (contact: ton.email@exemple.fr)';

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("Il manque SUPABASE_URL ou SUPABASE_SERVICE_KEY dans l'environnement.");
  process.exit(1);
}

/* La simulation est le défaut, l'écriture s'assume. Ce projet a déjà écrit
   cinq fiches en base sans preuve (migration 31) ; un script qui écrit dès
   qu'on le lance referait la même erreur en plus gros. */
const ECRIRE = process.argv.includes('--ecrire');
const iLim   = process.argv.indexOf('--limite');
const LIMITE = iLim >= 0 ? parseInt(process.argv[iLim + 1], 10) || 0 : 0;

const sb = createClient(SUPABASE_URL, SERVICE_KEY);
const PAUSE = 1200;                       // ms entre deux appels : on reste poli
const sleep = ms => new Promise(r => setTimeout(r, ms));

/* Le gris de « Non précisé ». Une fiche qui le porte encore n'a jamais eu de
   couleur choisie : on peut la remplacer. Une autre teinte veut dire que
   quelqu'un est passé derrière, et on n'écrase pas un choix humain. */
const GRIS = COULEURS['Non précisé'];

/* ---------- lecture d'une fiche Open Food Facts ----------
   OFF renvoie une page HTML quand il limite le débit. On contrôle le premier
   caractère plutôt que de laisser JSON.parse lever une erreur illisible —
   même piège que dans import-beers.mjs. */
async function fetchOFF(barcode) {
  const url = `https://world.openfoodfacts.org/api/v2/product/${barcode}`
            + `?fields=categories_tags,labels_tags,product_name`;
  for (let essai = 1; essai <= 3; essai++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': UA } });
      const txt = await res.text();
      if (!txt.trim().startsWith('{')) { await sleep(6000 * essai); continue; }
      const json = JSON.parse(txt);
      return json?.status === 1 ? json.product : null;   // 0 = code-barres inconnu
    } catch (e) {
      await sleep(3000 * essai);
    }
  }
  return undefined;                       // undefined = on n'a pas pu savoir
}

async function main() {
  console.log(ECRIRE
    ? '\n/!\\  MODE ÉCRITURE — les fiches vont être modifiées en base.\n'
    : '\n> Simulation. Rien ne sera écrit. Ajoute --ecrire pour appliquer.\n');

  /* `style` vaut tantôt NULL, tantôt la chaîne « Non précisé » selon la
     génération de l'import : les deux veulent dire « on ne sait pas ». */
  let q = sb.from('beers')
    .select('id,name,brewery,barcode,style,color,status,abv')
    .or('style.is.null,style.eq.Non précisé')
    .order('name');
  if (LIMITE) q = q.limit(LIMITE);

  const { data: fiches, error } = await q;
  if (error) { console.error('Lecture impossible :', error.message); process.exit(1); }

  console.log(`${fiches.length} fiche(s) sans style.\n`);
  if (!fiches.length) return;

  const trouves = new Map();              // style -> nombre
  let sansCodeBarres = 0, inconnuOFF = 0, tropGenerique = 0, injoignable = 0, ecrites = 0;

  for (const b of fiches) {
    if (!b.barcode) {
      sansCodeBarres++;
      console.log(`  .  ${b.name} — pas de code-barres, rien à interroger`);
      continue;
    }

    const p = await fetchOFF(b.barcode);
    await sleep(PAUSE);

    if (p === undefined) {
      injoignable++;
      console.log(`  ?  ${b.name} — Open Food Facts injoignable`);
      continue;
    }
    if (p === null) {
      inconnuOFF++;
      console.log(`  .  ${b.name} — code-barres absent d'Open Food Facts`);
      continue;
    }

    /* abv vient de NOTRE base, pas d'OFF : c'est lui qui a raison contre une
       catégorie `en:non-alcoholic-beers` posée sur une bière à 5,5°. */
    const style = styleDepuisCategories(p.categories_tags, p.labels_tags, b.abv);
    if (!style) {
      tropGenerique++;
      const cats = (p.categories_tags || []).join(' ') || '(aucune)';
      console.log(`  .  ${b.name} — catégories trop générales : ${cats}`);
      continue;
    }

    trouves.set(style, (trouves.get(style) || 0) + 1);

    /* La couleur ne suit que si personne ne l'a choisie. */
    const patch = { style };
    if (!b.color || b.color.toLowerCase() === GRIS.toLowerCase())
      patch.color = COULEURS[style] || GRIS;

    if (!ECRIRE) {
      console.log(`  ->  ${b.name} — ${style}${patch.color ? ' · ' + patch.color : ''}`);
      continue;
    }

    const { error: upErr } = await sb.from('beers').update(patch).eq('id', b.id);
    if (upErr) { console.warn(`  !  ${b.name} : ${upErr.message}`); continue; }
    ecrites++;
    console.log(`  ok  ${b.name} — ${style}`);
  }

  /* ---------- le compte ---------- */
  const total    = fiches.length;
  const combles  = [...trouves.values()].reduce((a, b) => a + b, 0);
  const restants = total - combles;

  console.log('\n' + '-'.repeat(56));
  console.log(`${combles} style(s) trouvé(s) sur ${total} fiche(s) examinée(s).`);
  if (ECRIRE) console.log(`${ecrites} fiche(s) réellement modifiée(s) en base.`);

  if (trouves.size) {
    console.log('\nRépartition :');
    [...trouves.entries()].sort((a, b) => b[1] - a[1])
      .forEach(([s, n]) => console.log(`  ${String(n).padStart(4)}  ${s}`));
  }

  console.log(`\n${restants} fiche(s) restent sans style, et c'est normal :`);
  console.log(`  ${String(tropGenerique).padStart(4)}  catégories OFF trop générales (en:beers et rien d'autre)`);
  console.log(`  ${String(inconnuOFF).padStart(4)}  code-barres absent d'Open Food Facts`);
  console.log(`  ${String(sansCodeBarres).padStart(4)}  fiche sans code-barres (ajoutée à la main)`);
  console.log(`  ${String(injoignable).padStart(4)}  Open Food Facts injoignable — relancer plus tard`);
  console.log('\nOn ne devine pas un style depuis le nom : la colonne reste une');
  console.log("donnée relevée. L'app comble ce qu'elle peut à l'affichage.");

  if (!ECRIRE && combles)
    console.log('\nPour appliquer : node enrich-styles.mjs --ecrire');
}

main().catch(console.error);
