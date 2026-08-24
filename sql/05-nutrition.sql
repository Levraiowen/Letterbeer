-- ============================================================
-- Migration : nutrition et allergènes
-- À coller et Run SEUL dans le SQL Editor.
--
-- kcal_100ml est stocké pour 100 ml et non par canette : c'est
-- le format d'Open Food Facts, et ça reste juste même si le
-- volume de la fiche est corrigé plus tard.
-- ============================================================

alter table beers add column if not exists kcal_100ml  numeric
  check (kcal_100ml >= 0 and kcal_100ml <= 200);
alter table beers add column if not exists allergens   text;
alter table beers add column if not exists ingredients text;

-- d'où vient la valeur : relevée sur la fiche produit, ou estimée
-- à partir du degré et du volume. L'app l'affiche différemment.
alter table beers add column if not exists kcal_source text
  check (kcal_source in ('off','estimated'));
