-- ============================================================
-- Canettes uniquement — purge des bouteilles déjà importées
-- À coller et Run SEUL dans le SQL Editor.
--
-- Elles étaient entrées à cause du filtre qui cherchait « metal » dans
-- l'emballage : une capsule de bouteille est en métal.
--
-- ⚠️ Passe d'abord le bloc 1 pour VOIR ce qui va partir. Ne lance le
--    bloc 2 qu'une fois la liste vérifiée : la suppression est
--    définitive et emporte les notes et avis associés.
-- ============================================================


-- ------------------------------------------------------------
-- BLOC 1 — inventaire, ne supprime rien. Lance-le seul d'abord.
-- ------------------------------------------------------------
select
  case
    when volume_cl > 56 then 'bouteille certaine (volume)'
    when container = 'bouteille' then 'bouteille étiquetée'
    when container = 'canette' then 'canette confirmée'
    else 'contenant inconnu'
  end as verdict,
  count(*) as fiches,
  count(*) filter (where id in (select beer_id from logs))   as dont_deja_bues,
  count(*) filter (where id in (select beer_id from reviews)) as dont_commentees
from beers
group by 1
order by 2 desc;


-- ------------------------------------------------------------
-- BLOC 2 — la purge. À lancer SEULEMENT après avoir lu le bloc 1.
--
-- On ne touche pas aux fiches que quelqu'un a déjà bues ou commentées :
-- les effacer ferait disparaître des notes sans prévenir personne. Elles
-- basculent en 'rejected', donc invisibles des autres, mais leur
-- historique reste cohérent.
-- ------------------------------------------------------------

-- 2a. les bouteilles sans aucun historique : suppression sèche
delete from beers
 where volume_cl > 56
   and id not in (select beer_id from logs)
   and id not in (select beer_id from reviews);

-- 2b. celles qui ont un historique : retirées de la circulation
update beers set status = 'rejected'
 where volume_cl > 56
   and status <> 'rejected';

-- 2c. tout ce qui reste et tient dans un format canette est considéré
--     comme canette : la base n'a plus vocation à contenir autre chose
update beers set container = 'canette'
 where container is null and volume_cl <= 56;


-- ------------------------------------------------------------
-- BLOC 3 — contrôle. Doit ne renvoyer que des volumes ≤ 56.
-- ------------------------------------------------------------
select volume_cl, count(*) as fiches
from beers
where status = 'approved'
group by volume_cl
order by volume_cl;
