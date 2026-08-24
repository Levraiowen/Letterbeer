-- ============================================================
-- Correctifs d'audit — à coller et Run SEUL dans le SQL Editor.
-- Couvre le constat C2 et la nouvelle règle « une note par bière ».
-- ============================================================

-- ------------------------------------------------------------
-- C2 — la suppression de compte échouait
--
-- La colonne était « not null » ET « on delete set null » : les deux
-- ne peuvent pas être vrais en même temps, donc PostgreSQL annulait
-- toute la suppression dès que l'utilisateur avait relevé un prix.
-- On la rend nullable : le relevé reste en base — il sert aux autres —
-- mais il est anonymisé. L'app affiche déjà « anonyme » dans ce cas.
-- ------------------------------------------------------------
alter table prices alter column user_id drop not null;

-- ------------------------------------------------------------
-- Une seule note par personne et par bière
--
-- Jusqu'ici, boire trois fois la même canette insérait trois notes,
-- qui pesaient trois fois dans la moyenne publique. Désormais la note
-- vit sur une seule ligne, et les fois suivantes sont des « +1 » :
-- des entrées de journal sans note, qui comptent dans le volume, les
-- unités, les calories et les dépenses, mais pas dans la moyenne.
--
-- On commence par convertir l'historique : on garde la note la plus
-- récente pour chaque couple (personne, bière) et on transforme les
-- précédentes en simples +1. Sans cette étape, l'index refuserait
-- de se créer sur des données déjà en double.
-- ------------------------------------------------------------
with ranked as (
  select id, row_number() over (
           partition by user_id, beer_id order by drunk_at desc, id
         ) as rn
  from logs
  where rating is not null
)
update logs set rating = null
 where id in (select id from ranked where rn > 1);

create unique index if not exists logs_one_rating_per_beer
  on logs (user_id, beer_id)
  where rating is not null;
