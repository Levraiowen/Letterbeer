/**
 * LETTERBEER — les contrats du catalogue, vérifiés
 *
 *   npm test
 *
 * Deux contrats, et rien d'autre. Ce ne sont pas des tests de couverture :
 * chaque témoin vient d'un incident réel, daté, consigné dans PROJET.md.
 * Un témoin qui casse dit qu'on est en train de refaire une erreur connue.
 *
 *   1. classer()               — canette, bouteille, ou à trancher
 *   2. styleDepuisCategories() — le style ne s'invente pas
 *
 * POURQUOI CE FICHIER EXISTE
 *
 * PROJET.md §4 et le commit 6ad9fe0 affirmaient tous deux que le contrat de
 * classer() était « vérifié par test unitaire ». Il ne l'était pas : la
 * vérification avait eu lieu une fois, à la main, et aucun fichier de test
 * n'était suivi par git. Sur la règle la plus dangereuse du projet, c'était
 * une garantie qui n'en était pas une.
 */

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { classer } from './import-beers.mjs';
import { styleDepuisCategories, guessStyle, COULEURS } from './styles.mjs';

/* ================================================================
   1. classer() — LA règle du projet

   « Ne jamais écrire container = 'canette' ni status = 'approved' à la
   main. » Le doute ne publie jamais : il part en validation manuelle, où
   la photo tranche en deux secondes.
   ================================================================ */

const produit = (o = {}) => ({
  product_name: '', quantity: '', packaging_tags: [],
  packaging_materials_tags: [], packaging_shapes_tags: [], ...o
});

test('canette : un signal d\'emballage positif, sans contre-indice', () => {
  assert.equal(classer(produit({
    product_name: 'Amsterdam Navigator', quantity: '50 cl',
    packaging_tags: ['en:drink-can']
  })), 'canette');

  assert.equal(classer(produit({
    quantity: '33 cl', packaging_materials_tags: ['en:aluminium']
  })), 'canette');
});

test('bouteille : le volume tranche seul au-delà de 56 cl', () => {
  // l'erreur d'origine : des 75 cl dans une base censée n'avoir que des
  // canettes, d'où les migrations 12 et 13
  assert.equal(classer(produit({
    quantity: '75 cl', packaging_tags: ['en:drink-can']
  })), 'bouteille', 'même étiquetée canette, une 75 cl est une bouteille');

  assert.equal(classer(produit({ quantity: '1,5 l' })), 'bouteille');
});

test('bouteille : le verre l\'emporte sur le reste', () => {
  // « La bière du Démon » — insérée en canette par la migration 31 alors
  // qu'OFF disait en:glass en:bottle. Réparée par la migration 32.
  assert.equal(classer(produit({
    product_name: 'La bière du Démon', quantity: '33 cl',
    packaging_tags: ['en:glass', 'en:bottle']
  })), 'bouteille');
});

test('« BTE » dans le NOM empêche la publication directe', () => {
  // « BTE 50CL BIERE 5% HEINEKEN » portait en:drink-can et passait en
  // publication directe. BTE abrège bouteille en grande distribution.
  //
  // ⚠ DIVERGENCE CONNUE, à trancher — voir PROJET.md §4.
  //
  // Trois sources disent trois choses de ce cas précis :
  //
  //   PROJET.md §4  « bte dans les tags, la quantité OU LE NOM
  //                   → bouteille, JAMAIS INSÉRÉE »
  //   le commentaire de classer()  « c'est le nom qui a raison »
  //   le code                      renvoie null → 'pending', donc INSÉRÉE
  //
  // Le code fait `if (bouteille && !canette)` : un signal de chaque côté
  // s'annule et part en validation manuelle. Ce n'est pas dangereux — rien
  // n'est publié, la photo tranchera — mais ce n'est pas ce que les deux
  // autres sources annoncent. Rendre le nom dominant rejetterait aussi de
  // vraies canettes dont le libellé contient « glass » ou « verre » : c'est
  // un arbitrage rendement/prudence, pas une correction évidente.
  //
  // Ce test asserte donc ce sur quoi les trois sources s'accordent — jamais
  // de publication directe — et laisse la décision ouverte.
  const heineken = produit({
    product_name: 'BTE 50CL BIERE 5% HEINEKEN', quantity: '50 cl',
    packaging_tags: ['en:drink-can']
  });
  assert.notEqual(classer(heineken), 'canette');
  assert.equal(classer(heineken), null, 'état actuel : validation manuelle');

  const leffe = produit({
    product_name: 'BTL 33CL LEFFE', quantity: '33 cl',
    packaging_tags: ['en:can']
  });
  assert.notEqual(classer(leffe), 'canette');
});

test('à trancher : aucune donnée d\'emballage ne publie rien', () => {
  // les trois indéterminées de la migration 31 : 8.6 Cherry, Maximator,
  // Flying Fish Citron. OFF ne disait rien. Elles ne devaient pas être
  // publiées, et surtout pas déduites du volume.
  for (const q of ['33 cl', '50 cl', '25 cl']) {
    assert.equal(classer(produit({ quantity: q })), null,
      `${q} sans donnée d'emballage doit partir en validation, pas être publiée`);
  }
});

test('à trancher : un signal des DEUX côtés ne publie pas non plus', () => {
  assert.equal(classer(produit({
    quantity: '33 cl',
    packaging_tags: ['en:can', 'en:glass']
  })), null);
});

test('AUCUN indice de bouteille ne donne une publication directe', () => {
  // le contrat, énoncé tel quel dans le commit 6ad9fe0. On le balaie
  // sur les trois canaux : les tags, la quantité, le nom.
  const indices = ['bouteille', 'bottle', 'verre', 'glass', 'bte', 'btl', 'bottiglia'];
  for (const i of indices) {
    assert.notEqual(classer(produit({ product_name: `${i} 33cl`, quantity: '33 cl' })),
      'canette', `« ${i} » dans le nom ne doit jamais publier`);
    assert.notEqual(classer(produit({ quantity: `33 cl ${i}` })),
      'canette', `« ${i} » dans la quantité ne doit jamais publier`);
    assert.notEqual(classer(produit({ quantity: '33 cl', packaging_tags: [`en:${i}`] })),
      'canette', `« ${i} » dans les tags ne doit jamais publier`);
  }
});

/* ================================================================
   2. styleDepuisCategories() — le style ne s'invente pas
   ================================================================ */

test('le style vient des catégories, jamais du nom', () => {
  // « Punk IPA » sans catégorie IPA : on ne devine pas. L'app comblera
  // la FAMILLE à l'affichage, via classerTexte(), sans toucher la colonne.
  assert.equal(styleDepuisCategories(['en:beers'], [], 5.4), null);
  // avec la catégorie, en revanche, c'est une donnée relevée
  assert.equal(styleDepuisCategories(['en:beers', 'en:india-pale-ales'], [], 5.4), 'IPA');
});

test('les catégories génériques ne disent rien', () => {
  const generiques = ['en:beverages', 'en:alcoholic-beverages', 'en:beers',
                      'en:beverages-and-beverages-preparations'];
  assert.equal(styleDepuisCategories(generiques, [], 5), null);
});

test('MOTS ENTIERS : « flavored-beers » n\'est pas une « red-beer »', () => {
  // Le bug du 26 août 2026. Cherché en sous-chaîne, `red-beer` matchait
  // « flavo·red-beer·s » et rangeait toute la famille Desperados en
  // Ambrée — 13 fiches fausses. Même piège que « La Chouffe » masquant
  // « Achouffe » dans brasserieUtile().
  assert.equal(styleDepuisCategories(['en:beers', 'en:flavored-beers'], [], 5.9), null);
  // pendant qu'une VRAIE red ale reste reconnue
  assert.equal(styleDepuisCategories(['en:beers', 'en:red-ales'], [], 6), 'Ambrée');
});

test('« alcoholic-beverages » ne déclenche pas « non alcoholic »', () => {
  // ce tag est sur toutes les bières du monde
  assert.notEqual(styleDepuisCategories(['en:alcoholic-beverages', 'en:lagers'], [], 5),
    'Sans alcool');
  assert.equal(styleDepuisCategories(['en:alcoholic-beverages', 'en:lagers'], [], 5), 'Blonde');
});

test('le sans-alcool se lit aussi dans les LABELS', () => {
  // Tourtel Twist : catégorie lager, label en:no-alcohol
  assert.equal(styleDepuisCategories(['en:beers', 'en:lagers'], ['en:no-alcohol'], 0),
    'Sans alcool');
});

test('GARDE-FOU : une bière à 5,5° ne peut pas être « Sans alcool »', () => {
  // Mesuré le 26 août 2026 : « Grimbergen Pale Ale 5.5 DEGRE ALCOOL » est
  // rangée en:non-alcoholic-beers par OFF. La donnée d'OFF est fausse ; abv
  // alimente les unités d'alcool, donc les repères de santé. On refuse le
  // style plutôt que d'écrire la contradiction.
  const cats = ['en:beers', 'en:non-alcoholic-beverages', 'en:non-alcoholic-beers'];
  assert.notEqual(styleDepuisCategories(cats, [], 5.5), 'Sans alcool');
  // sous le seuil légal de 1,2 %, en revanche, c'est cohérent
  assert.equal(styleDepuisCategories(cats, [], 0), 'Sans alcool');
  assert.equal(styleDepuisCategories(cats, [], 1.2), 'Sans alcool');
  // degré inconnu : on ne bloque pas sur une absence
  assert.equal(styleDepuisCategories(cats, [], null), 'Sans alcool');
});

test('le garde-fou vaut aussi pour l\'import', () => {
  assert.notEqual(guessStyle('Bière sans alcool', ['en:beers'], 5.5), 'Sans alcool');
  assert.equal(guessStyle('Bière sans alcool', ['en:beers'], 0), 'Sans alcool');
  // sans abv, comportement d'origine inchangé
  assert.equal(guessStyle('Bière sans alcool', ['en:beers']), 'Sans alcool');
});

test('l\'ordre va du plus précis au plus vague', () => {
  assert.equal(styleDepuisCategories(['en:imperial-stouts'], [], 9), 'Imperial Stout');
  assert.equal(styleDepuisCategories(['en:pale-lagers'], [], 5), 'Blonde');
  assert.equal(styleDepuisCategories(['en:session-ipas'], [], 4), 'Session IPA');
});

test('les orthographes qu\'OFF emploie vraiment', () => {
  // « pilsener » s'écrit avec un e : un motif `pilsn?ers?` trop malin le
  // ratait, alors que les deux graphies existent dans OFF
  for (const t of ['en:pilsner', 'en:pilsners', 'en:pilsener', 'en:pilseners'])
    assert.equal(styleDepuisCategories([t], [], 5), 'Pils', t);

  // les tags francophones sont fréquents et arrivent au pluriel
  assert.equal(styleDepuisCategories(['fr:bieres-ambrees'], [], 6), 'Ambrée');
  assert.equal(styleDepuisCategories(['fr:bieres-brunes'], [], 6), 'Brune');
  assert.equal(styleDepuisCategories(['fr:bieres-blanches'], [], 5), 'Blanche');
});

test('tout style produit a une couleur', () => {
  // une couleur manquante donnerait du gris « Non précisé » sur une fiche
  // qui a pourtant un style — incohérence invisible en relecture
  const echantillons = [
    ['en:india-pale-ales'], ['en:stouts'], ['en:porters'], ['en:lambics'],
    ['en:saisons'], ['en:pilsners'], ['en:white-beers'], ['en:tripels'],
    ['en:dubbels'], ['en:red-ales'], ['en:brown-ales'], ['en:lagers'],
    ['en:imperial-stouts'], ['en:session-ipas'], ['en:goses'],
    ['en:new-england-ipas'], ['en:non-alcoholic-beers']
  ];
  for (const cats of echantillons) {
    const s = styleDepuisCategories(cats, [], 0);
    assert.ok(s, `${cats} devrait donner un style`);
    assert.ok(COULEURS[s], `le style « ${s} » n'a pas de couleur`);
  }
});
