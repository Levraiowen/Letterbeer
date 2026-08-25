-- ============================================================
-- Migration 24 — « Populaires cette semaine » l'est vraiment
-- À coller et Run SEUL dans le SQL Editor.
--
-- La section triait sur rating_count, c'est-à-dire le nombre total de
-- notes DEPUIS TOUJOURS. Le titre promettait une fenêtre de temps que le
-- code n'appliquait nulle part : une canette notée vingt fois il y a six
-- mois restait « populaire cette semaine » indéfiniment, et le classement
-- ne bougeait jamais.
--
-- On ajoute donc le compte des sept derniers jours à la vue existante.
--
-- POURQUOI SUR LES NOTES, ET PAS SUR TOUTES LES ENTRÉES DE JOURNAL
--
-- Compter toutes les canettes bues aurait été plus juste, mais aurait fait
-- sortir du journal une donnée qui n'en sort pas aujourd'hui : les entrées
-- sans note — les « +1 » — sont du pur journal privé. beer_ratings, elle,
-- n'agrège que les notes, qui alimentent déjà la moyenne publique. On reste
-- donc exactement sur le même périmètre d'exposition qu'avant, avec une
-- fenêtre de temps en plus. Rien de nouveau ne quitte le journal.
--
-- ORDRE : indifférent. Tant que la migration n'est pas passée, la colonne
-- n'existe pas, la section se masque toute seule, et le reste de l'accueil
-- ne bouge pas.
-- ============================================================

-- « create or replace » n'accepte d'ajouter des colonnes qu'À LA FIN :
-- week_count vient donc après rating_count, et pas ailleurs.
create or replace view beer_ratings as
  select beer_id,
         round(avg(rating)::numeric, 1) as avg_rating,
         count(*)                       as rating_count,
         count(*) filter (where drunk_at > now() - interval '7 days') as week_count
  from logs
  where rating is not null
  group by beer_id;


-- ------------------------------------------------------------
-- Contrôle — trois colonnes attendues, dont week_count, et un aperçu
-- des canettes notées ces sept derniers jours. Zéro ligne dans la
-- seconde requête veut simplement dire que personne n'a noté cette
-- semaine : ce n'est pas une erreur.
-- ------------------------------------------------------------
select column_name
from information_schema.columns
where table_name = 'beer_ratings'
order by ordinal_position;
