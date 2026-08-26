-- ============================================================
-- Migration 31 — cinq canettes ajoutées à la main
-- À coller et Run SEUL dans le SQL Editor.
--
-- POURQUOI LES PHOTOS VIENNENT D'OPEN FOOD FACTS, ET DE NULLE PART AILLEURS
--
-- La politique de sécurité du contenu, en tête d'index.html, n'autorise les
-- images que depuis Supabase et *.openfoodfacts.org / .net. Une photo prise
-- ailleurs — site de brasserie, moteur de recherche — serait tout simplement
-- refusée par le navigateur, et la fiche s'afficherait sans image.
--
-- C'est aussi ce qui règle la licence : les photos d'Open Food Facts sont en
-- CC-BY-SA, et l'attribution figure déjà dans l'écran À propos.
--
-- Les cinq adresses ci-dessous ont été vérifiées une par une : HTTP 200,
-- image/jpeg, entre 14 et 42 ko.
--
-- CE QUE J'AI CORRIGÉ PAR RAPPORT À OPEN FOOD FACTS
--
-- Les fiches d'origine portent des noms de rayon plutôt que des noms de
-- bière (« Cherry » seul, « Bière premium au citron pressé »), et des
-- quantités de PACK (« 6x33cl », « 4x50 cl ») là où il faut le volume d'UNE
-- canette. Les volumes ci-dessous sont donc ceux de l'unité.
--
-- ⚠️ UNE VALEUR MANQUE, ET ELLE N'EST PAS ANODINE
--
-- L'Amsterdam Navigator n'a pas de degré dans Open Food Facts, et je ne
-- l'invente pas : le degré alimente le calcul des unités d'alcool, donc les
-- repères de consommation. Un chiffre approximatif y fausserait un suivi de
-- santé. La fiche est insérée avec abv NULL — elle affichera « ?° » — et se
-- complète en deux secondes depuis l'écran de modération, la canette en main.
--
-- ⚠️ LA 8.6 BLACK N'EST PAS LÀ
--
-- Elle n'existe dans aucune fiche d'Open Food Facts, sous aucune écriture.
-- Sans photo autorisée par la CSP, l'ajouter donnerait une fiche muette. Deux
-- sorties, dans le fichier de session : voir PROJET.md.
-- ============================================================

insert into beers (name, brewery, style, abv, volume_cl, country, container,
                   image_url, color, description, status, barcode)
values
  ('8.6 Cherry', 'Bavaria', 'Blonde', 7.2, 50, 'Pays-Bas', 'canette',
   'https://images.openfoodfacts.org/images/products/871/480/005/0098/front_en.10.400.jpg',
   '#C1272D',
   'La 8.6 dans sa version cerise. Ajoutée à la main.',
   'approved', '8714800050098'),

  ('Maximator', 'Augustiner-Bräu', 'Bock', 7.5, 50, 'Allemagne', 'canette',
   'https://images.openfoodfacts.org/images/products/410/525/002/7503/front_de.3.400.jpg',
   '#6B3A1F',
   'Doppelbock munichoise, brune et maltée. Ajoutée à la main.',
   'approved', '4105250027503'),

  ('La bière du Démon', 'Goudale', 'Blonde', 12, 33, 'France', 'canette',
   'https://images.openfoodfacts.org/images/products/326/157/000/0136/front_en.65.400.jpg',
   '#D4A017',
   'Blonde française de 12 degrés, parmi les plus fortes du rayon. Ajoutée à la main.',
   'approved', '3261570000136'),

  -- degré volontairement NULL : voir l'avertissement en entête
  ('Amsterdam Navigator', 'Amsterdam', 'Lager', null, 50, 'Pays-Bas', 'canette',
   'https://images.openfoodfacts.org/images/products/871/670/000/6144/front_fr.8.400.jpg',
   '#E8A33D',
   'Lager forte néerlandaise. Degré à compléter depuis l''écran de modération.',
   'approved', '8716700006144'),

  ('Flying Fish Citron', 'Flying Fish', 'Blonde', 5.9, 33, 'Belgique', 'canette',
   'https://images.openfoodfacts.org/images/products/541/022/833/2145/front_en.8.400.jpg',
   '#EFD24B',
   'Bière au citron pressé, légère et acidulée. Ajoutée à la main.',
   'approved', '5410228332145')

-- le code-barres est unique : relancer la migration ne crée pas de doublon
on conflict (barcode) do nothing;


-- ------------------------------------------------------------
-- Contrôle — cinq lignes, dont une sans degré, toutes avec photo.
-- ------------------------------------------------------------
select name, brewery,
       coalesce(abv::text, '— à compléter') as degre,
       volume_cl, status,
       case when image_url like 'https://images.openfoodfacts.org/%' then 'photo OFF ✅' else '⚠️ hors CSP' end as photo
from beers
where barcode in ('8714800050098','4105250027503','3261570000136','8716700006144','5410228332145')
order by name;
