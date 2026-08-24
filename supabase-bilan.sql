-- ============================================================
-- BILAN — état de la base après import et modération.
-- Ne modifie rien. Les quatre blocs se lancent d'un coup.
-- ============================================================


-- ---- 1. Combien de fiches, et dans quel état ----
select status as etat,
       count(*) as fiches,
       count(*) filter (where image_url is not null) as avec_photo,
       count(*) filter (where kcal_source = 'off')   as kcal_relevees,
       count(*) filter (where kcal_source is null)   as sans_nutrition,
       count(*) filter (where allergens is not null) as avec_allergenes
from beers
group by status
order by fiches desc;


-- ---- 2. Répartition des volumes parmi les fiches en ligne ----
-- Une canette normale fait 25, 33, 44 ou 50 cl. Tout autre volume
-- mérite un coup d'œil : c'est souvent une bouteille qui a survécu.
select volume_cl,
       count(*) as fiches,
       case when volume_cl in (25, 33, 44, 50) then 'format canette courant'
            else '⚠ à vérifier' end as remarque
from beers
where status = 'approved'
group by volume_cl
order by volume_cl;


-- ---- 3. Les fiches en ligne aux volumes inhabituels ----
-- Ouvre-les dans l'app pour vérifier la photo. Si c'est une bouteille,
-- rejette-la depuis « Fiches à valider » → « Déjà validées ».
select name, brewery, volume_cl, abv, country
from beers
where status = 'approved'
  and volume_cl not in (25, 33, 44, 50)
order by volume_cl desc, name
limit 40;


-- ---- 4. Ce qu'il reste à enrichir ----
-- Si la ligne renvoie plus de zéro, relance : node enrich-beers.mjs
select count(*) as fiches_sans_calories
from beers
where status = 'approved' and kcal_100ml is null;
