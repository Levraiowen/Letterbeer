-- ============================================================
-- Migration 22 — détourer les noms restés sales
-- À coller et Run SEUL dans le SQL Editor.
--
-- Dix fiches approuvées portent une espace en trop ou double :
--   « 8.6 Red  », « Kronenbourg  », « Elephant  », « LA BETE  »,
--   « Alhambra Beer   Premium Lager »…
-- Ça ressort partout, jusque dans les messages de confirmation
-- (« 8.6 Red  · 3★ enregistrée »).
--
-- POURQUOI ELLES SONT LÀ, ET POURQUOI ÇA REVIENDRA
--
-- Le nettoyage vit dans la migration 03, qui n'a tourné qu'une fois.
-- import-beers.mjs, lui, n'a aucune règle de nettoyage : chaque nouvel
-- import réintroduit des noms bruts d'Open Food Facts. Cette migration
-- rattrape l'existant ; la vraie correction serait de porter le
-- nettoyage dans le script d'import, ou dans un déclencheur d'insertion.
--
-- L'app détoure désormais aussi à l'affichage, donc l'écran est propre
-- même si cette migration n'est pas passée. Elle sert à ce que l'export
-- CSV, la recherche et la détection de doublons travaillent sur du net.
-- ============================================================

update beers
   set name = regexp_replace(btrim(name), '\s{2,}', ' ', 'g')
 where name <> regexp_replace(btrim(name), '\s{2,}', ' ', 'g');

update beers
   set brewery = regexp_replace(btrim(brewery), '\s{2,}', ' ', 'g')
 where brewery <> regexp_replace(btrim(brewery), '\s{2,}', ' ', 'g');


-- ------------------------------------------------------------
-- Contrôle — doit renvoyer 0 pour les deux colonnes.
-- ------------------------------------------------------------
select
  count(*) filter (where name    <> regexp_replace(btrim(name),    '\s{2,}', ' ', 'g')) as noms_sales,
  count(*) filter (where brewery <> regexp_replace(btrim(brewery), '\s{2,}', ' ', 'g')) as brasseries_sales
from beers;
