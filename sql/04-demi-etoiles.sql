-- ============================================================
-- Migration : autoriser les demi-étoiles (0,5 → 5)
-- À coller et Run SEUL dans le SQL Editor.
--
-- rating est aujourd'hui un "int", il rejetterait 3,5.
-- La vue beer_ratings dépend de la colonne : Postgres refuse de
-- changer le type tant qu'elle existe, donc on la supprime et on
-- la recrée à l'identique après.
-- ============================================================

drop view if exists beer_ratings;

-- ---- journal ----
alter table logs drop constraint if exists logs_rating_check;
alter table logs alter column rating type numeric(2,1);
alter table logs add constraint logs_rating_check
  check (rating >= 0.5 and rating <= 5 and rating * 2 = floor(rating * 2));

-- ---- avis ----
alter table reviews drop constraint if exists reviews_rating_check;
alter table reviews alter column rating type numeric(2,1);
alter table reviews add constraint reviews_rating_check
  check (rating >= 0.5 and rating <= 5 and rating * 2 = floor(rating * 2));

-- ---- on remet la vue ----
create view beer_ratings as
  select beer_id,
         round(avg(rating)::numeric, 1) as avg_rating,
         count(*) as rating_count
  from logs where rating is not null group by beer_id;
