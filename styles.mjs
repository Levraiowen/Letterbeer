/**
 * LETTERBEER — le vocabulaire des styles, en un seul endroit
 *
 * Ces tables vivaient dans import-beers.mjs. Elles en sortent parce que
 * enrich-styles.mjs en a besoin aussi, et qu'une COULEUR qui diverge entre
 * deux scripts donne deux teintes pour le même style selon la fiche par
 * laquelle il est arrivé — un défaut invisible en relecture, criant à l'écran.
 *
 * Le vocabulaire est FERMÉ : dix-sept valeurs, pas une de plus. Elles sont
 * calibrées sur MOTIFS_FAMILLE dans index.html, qui range chaque style dans
 * ipa / brunes / blondes pour le tri du premier lancement. Un style inventé
 * ici — « Fruitée », « Panaché », « Abbaye » — ne tomberait dans aucune
 * famille et sortirait la canette du tri. Si le besoin s'en fait sentir,
 * c'est MOTIFS_FAMILLE qu'il faut ouvrir d'abord, pas cette liste.
 */

/* 1,2 % vol. est le seuil légal français au-dessus duquel une boisson ne
   peut plus être présentée comme sans alcool. Les deux fonctions de ce
   fichier s'y réfèrent — voir le garde-fou détaillé plus bas. */
const SEUIL_SANS_ALCOOL = 1.2;

/* Le style DÉCLARÉ, lu dans le texte. Sert à l'import, où la fiche OFF est
   entière sous la main. L'ordre compte : « Session IPA » avant « IPA »,
   « Imperial Stout » avant « Stout ». */
export const STYLES = [
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

export const COULEURS = {
  'NEIPA':'#FF7A2F','IPA':'#FFB020','Session IPA':'#5FC9E8','Imperial Stout':'#8A6244',
  'Stout':'#9B8B7A','Porter':'#A08670','Gose':'#7FD1D9','Sour':'#FF5D8F','Saison':'#C9E265',
  'Pils':'#E8DFA0','Blanche':'#EFE3C8','Triple':'#F0C97A','Double':'#D89A5A','Ambrée':'#E0603A',
  'Brune':'#8C6A4F','Blonde':'#F2D06B','Sans alcool':'#9FD8C0','Non précisé':'#B0B0B8'
};

/* `abv` est facultatif, et sert au seul garde-fou du sans-alcool décrit plus
   bas : une fiche à 5,5° ne doit jamais ressortir « Sans alcool », d'où que
   vienne l'indice. Sans `abv`, comportement inchangé. */
export const guessStyle = (name, cats, abv = null) => {
  const hay = `${name} ${cats.join(' ')}`;
  for (const [re, label] of STYLES) {
    if (!re.test(hay)) continue;
    if (label === 'Sans alcool' && abv != null && +abv > SEUIL_SANS_ALCOOL) continue;
    return label;
  }
  return 'Non précisé';
};

/* ------------------------------------------------------------------
   Le style depuis les CATÉGORIES d'Open Food Facts, et rien d'autre.
   ------------------------------------------------------------------

   Sert à enrich-styles.mjs, qui repasse sur des fiches DÉJÀ en base pour
   combler leur style manquant. La différence avec guessStyle() n'est pas
   technique, elle est de principe :

     guessStyle()          lit le nom ET les catégories
     styleDepuisCategories() ne lit QUE les catégories

   Parce que « beers.style reste la donnée d'Open Food Facts, jamais une
   supposition de notre part » (PROJET.md §7). Écrire « IPA » en base parce
   que la canette s'appelle « Punk IPA » serait une déduction de notre part
   posée là où l'app promet une donnée relevée. L'app a déjà le droit de
   deviner une FAMILLE depuis le nom — c'est classerTexte() dans index.html,
   qui ne touche pas à la colonne. La déduction reste à l'affichage ; la
   colonne reste factuelle.

   ON COMPARE DES MOTS ENTIERS, JAMAIS UNE SOUS-CHAÎNE.

   Première version : `red-beer` cherché en sous-chaîne dans la liste jointe.
   Mesuré le 26 août 2026 sur les 200 bières les plus scannées en France,
   il rangeait TOUTE la famille Desperados en « Ambrée » — parce que
   `en:flavored-beers` contient « flavo·red-beer·s ». Treize fiches fausses
   sur dix-huit gains annoncés.

   C'est le piège que PROJET.md documente déjà pour brasserieUtile(), où
   une sous-chaîne faisait masquer « Achouffe » par « La Chouffe ». Deux
   fonctions, la même erreur, à deux mois d'écart.

   D'où la normalisation : `en:non-alcoholic-beers` devient
   « en non alcoholic beers », et tous les motifs s'ancrent sur `\b`. Un
   motif écrit avec un trait d'union ne matchera plus RIEN — les espaces
   sont volontaires.

   L'ordre compte, du plus précis au plus vague : `en:imperial-stouts`
   contient `stout`, et `en:pale-lagers` contient `lager`.

   Les tags GÉNÉRIQUES (`en:beers`, `en:alcoholic-beverages`) n'apparaissent
   volontairement nulle part : ils sont sur presque toutes les fiches et ne
   disent rien. Idem pour `en:flavored-beers`, `en:beers-with-fruits` et
   `en:abbey-ales`, très fréquents mais sans équivalent dans le vocabulaire
   fermé. Une fiche qui n'a qu'eux ressort sans style — c'est le bon
   résultat, pas un échec du script.
*/
const normaliser = tags => ' ' + tags.join(' ').toLowerCase().replace(/[:_-]+/g, ' ') + ' ';

const CATEGORIES_OFF = [
  [/\bnew england\b|\bhazy\b|\bneipas?\b/,                       'NEIPA'],
  [/\bsession ipas?\b/,                                          'Session IPA'],
  [/\bindia pale\b|\bipas?\b/,                                   'IPA'],
  [/\bimperial stouts?\b|\brussian imperial\b/,                  'Imperial Stout'],
  [/\bstouts?\b/,                                                'Stout'],
  [/\bporters?\b/,                                               'Porter'],
  [/\bgoses?\b/,                                                 'Gose'],
  [/\blambics?\b|\bgueuzes?\b|\bgeuze\b|\bkrieks?\b|\bsour beers?\b|\bbieres acides\b/, 'Sour'],
  [/\bsaisons?\b|\bfarmhouse\b/,                                 'Saison'],
  [/\btriples?\b|\btripels?\b/,                                  'Triple'],
  [/\bdoubles?\b|\bdubbels?\b/,                                  'Double'],
  [/\bblanches?\b|\bwitbiers?\b|\bweissbier\b|\bweizen\b|\bwhite beers?\b|\bwheat beers?\b/, 'Blanche'],
  [/\bpilsners?\b|\bpilseners?\b|\bpils\b/,                      'Pils'],
  [/\bambrees?\b|\bamber beers?\b|\brousses?\b|\bred beers?\b|\bred ales?\b/, 'Ambrée'],
  [/\bbrunes?\b|\bbrown beers?\b|\bbrown ales?\b|\bdark beers?\b|\bdunkel\b|\bnoires?\b/, 'Brune'],
  [/\bblondes?\b|\bhelles\b|\bpale lagers?\b|\blagers?\b|\bpale ales?\b/, 'Blonde'],
];

/* Le sans-alcool se lit d'abord, et sur les LABELS autant que sur les
   catégories : OFF le range souvent en `en:alcohol-free`, un label, pendant
   que la catégorie reste `en:lagers`. Sans ce passage en premier, une
   Tourtel ressortirait « Blonde » — vrai sur la couleur, faux sur ce qui
   compte, et l'app calcule des unités d'alcool avec.

   Mots entiers ici aussi, et sur la chaîne normalisée : « en:alcoholic-
   beverages » est sur toutes les bières du monde et ne doit surtout pas
   déclencher « non alcoholic ». */
const SANS_ALCOOL = /\balcohol free\b|\bnon alcoholic\b|\bsans alcool\b|\balcoholfree\b|\bno alcohol\b|\b0 0\b/;

/* ------------------------------------------------------------------
   Le garde-fou du sans-alcool — vérifié sur données réelles.

   Mesuré le 26 août 2026 sur les 189 bières les plus scannées en France :
   « Grimbergen 25 cl Grimbergen Pale Ale 5.5 DEGRE ALCOOL » porte les
   catégories `en:non-alcoholic-beverages en:non-alcoholic-beers`. Open Food
   Facts est un wiki : la donnée est fausse, et notre lecture était juste.

   Sur presque n'importe quelle app, écrire « Sans alcool » sur cette fiche
   serait une coquille. Ici c'est plus grave : la même fiche porte abv = 5.5,
   qui alimente les unités d'alcool et donc les repères de Santé publique
   France. Une fiche qui se contredit à l'écran est le début d'un compteur
   qui ment.

   1,2 % vol. est le seuil légal français au-dessus duquel une boisson ne
   peut plus être présentée comme sans alcool. Au-delà, on refuse le style
   plutôt que d'écrire la contradiction : la fiche ressort sans style, ce
   qui est honnête, et l'écran de modération reste le recours.

   `abv` inconnu (null) laisse passer : on ne bloque pas sur une absence.
------------------------------------------------------------------- */
const diraitSansAlcool = (cats, labels, abv) => {
  if (!SANS_ALCOOL.test(cats) && !SANS_ALCOOL.test(labels)) return false;
  return abv == null || +abv <= SEUIL_SANS_ALCOOL;
};

export function styleDepuisCategories(categoriesTags = [], labelsTags = [], abv = null) {
  const cats   = normaliser(categoriesTags);
  const labels = normaliser(labelsTags);

  if (diraitSansAlcool(cats, labels, abv)) return 'Sans alcool';
  for (const [re, label] of CATEGORIES_OFF) if (re.test(cats)) return label;
  return null;                       // OFF ne dit rien : on n'invente pas
}
