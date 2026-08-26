-- ============================================================
-- Migration 32 — réparer les cinq fiches de la migration 31
-- À coller et Run SEUL dans le SQL Editor.
--
-- CE QUI S'EST PASSÉ
--
-- La migration 31 a inséré cinq canettes à la main, toutes en 'approved'
-- avec container = 'canette'. Or RIEN ne prouvait qu'il s'agissait de
-- canettes : le contenant a été déduit du volume, exactement le raccourci
-- qui avait rempli la base de bouteilles de 75 cl et motivé les migrations
-- 12 et 13.
--
-- Vérification faite après coup sur les données d'emballage d'Open Food
-- Facts, fiche par fiche :
--
--   Amsterdam Navigator  en:drink-can              → canette CONFIRMÉE
--   La bière du Démon    en:glass en:bottle        → BOUTEILLE, formellement
--   8.6 Cherry           aucune donnée             → indéterminé
--   Maximator            aucune donnée             → indéterminé
--   Flying Fish Citron   aucune donnée             → indéterminé
--
-- CE QUE FAIT CETTE MIGRATION
--
-- La bouteille sort de la circulation. Les trois indéterminées passent en
-- 'pending' avec container à NULL : elles rejoignent l'écran « Fiches à
-- valider », où leur photo permet de trancher en deux secondes — c'est le
-- parcours que l'app prévoit pour le doute, et qui a été court-circuité.
-- La canette confirmée reste publiée.
--
-- On ne SUPPRIME pas la bouteille : quelqu'un a pu la noter entre-temps, et
-- l'effacer emporterait sa note. Le rejet la retire de la circulation sans
-- rien détruire — même principe que la migration 13.
-- ============================================================

-- 1. la bouteille avérée sort de la circulation
update beers
   set status = 'rejected', container = 'bouteille'
 where barcode = '3261570000136';

-- 2. les trois sans preuve retournent à la validation manuelle
update beers
   set status = 'pending', container = null,
       description = 'Contenant non confirmé par Open Food Facts : à vérifier sur la photo.'
 where barcode in ('8714800050098', '4105250027503', '5410228332145');

-- 3. la seule confirmée reste telle quelle — rien à faire, on le note


-- ------------------------------------------------------------
-- Contrôle — une publiée, une rejetée, trois à valider.
-- ------------------------------------------------------------
select name, status, coalesce(container, '— à trancher') as contenant
from beers
where barcode in ('8714800050098','4105250027503','3261570000136','8716700006144','5410228332145')
order by status, name;
