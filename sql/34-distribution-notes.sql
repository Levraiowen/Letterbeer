-- ============================================================
-- Migration 34 — la répartition des notes dans beer_ratings
-- À coller et Run SEUL dans le SQL Editor.
--
-- Ordre de déploiement habituel : `git push` D'ABORD, cette migration
-- ensuite. Le code sait vivre sans ces colonnes — la répartition se masque
-- simplement, exactement comme `week_count` avant la migration 24.
--
--
-- POURQUOI
--
-- La fiche d'une bière affiche sa moyenne et son nombre de notes. Elle ne
-- dit pas COMMENT ces notes se répartissent. Or « 3,5 sur douze notes »
-- recouvre deux réalités opposées : douze personnes tièdes, ou six qui
-- adorent et six qui détestent. C'est précisément ce qu'on veut lire sur
-- une canette qui a de l'historique.
--
-- Ça ne peut pas se calculer côté navigateur : `logs` est strictement
-- privé par RLS, chacun n'y voit que ses propres lignes. L'agrégat doit
-- donc venir de la base, par la vue qui fait déjà exactement ça pour la
-- moyenne. Même mécanisme, pas un second.
--
--
-- CE QUE ÇA EXPOSE — et ce que ça n'expose pas
--
-- Rien de nouveau, et c'est le point à vérifier avant d'ajouter la moindre
-- colonne dérivée du journal.
--
-- Ces colonnes sont des COMPTES, jamais des identités : elles disent « deux
-- personnes ont mis 5 », jamais lesquelles. Et l'information marginale est
-- nulle sur le cas sensible : quand une bière n'a qu'UNE note, `avg_rating`
-- la donne déjà exactement. La répartition n'ajoute rien qui ne sorte
-- aujourd'hui.
--
-- L'app ne l'affiche d'ailleurs qu'à partir de trois notes — pas pour des
-- raisons de confidentialité, mais parce qu'un histogramme à deux barres ne
-- raconte rien.
--
-- La vue reste SECURITY DEFINER, et c'est voulu : c'est ce qui permet
-- d'agréger `logs` à travers le RLS. Ne pas « corriger » l'alerte du
-- Security Advisor — tout est expliqué en tête de la migration 26.
--
--
-- LES DEMI-NOTES
--
-- `rating` est un numeric(2,1) de 0,5 à 5 depuis la migration 04. On
-- regroupe sur l'étoile SUPÉRIEURE : 4,5 compte dans les 5. C'est déjà la
-- convention de l'histogramme du profil dans index.html — « les demi-notes
-- sont regroupées sur l'étoile supérieure ». Deux conventions différentes
-- pour le même geste donneraient deux histogrammes contradictoires dans la
-- même app.
--
--
-- ⚠️ L'ORDRE DES COLONNES N'EST PAS LIBRE
--
-- `create or replace view` n'accepte d'ajouter des colonnes qu'À LA FIN, et
-- interdit de renommer ou réordonner les existantes. n1..n5 viennent donc
-- après `week_count`, dans cet ordre. Le piège est déjà documenté dans la
-- migration 24, qui s'est heurtée à la même contrainte.
-- ============================================================

create or replace view beer_ratings as
  select beer_id,
         round(avg(rating)::numeric, 1) as avg_rating,
         count(*)                       as rating_count,
         count(*) filter (where drunk_at > now() - interval '7 days') as week_count,
         count(*) filter (where ceil(rating) = 1) as n1,
         count(*) filter (where ceil(rating) = 2) as n2,
         count(*) filter (where ceil(rating) = 3) as n3,
         count(*) filter (where ceil(rating) = 4) as n4,
         count(*) filter (where ceil(rating) = 5) as n5
  from logs
  where rating is not null
  group by beer_id;


-- ------------------------------------------------------------
-- Contrôle 1 — les droits ont-ils survécu au remplacement ?
--
-- `create or replace view` conserve les privilèges, mais la migration 26
-- avait justement dû retirer un droit oublié au rôle anon : on vérifie
-- plutôt que de supposer. Attendu : `authenticated` présent, `anon` absent.
-- ------------------------------------------------------------
select grantee, privilege_type
from information_schema.role_table_grants
where table_name = 'beer_ratings'
order by grantee;


-- ------------------------------------------------------------
-- Contrôle 2 — la somme des cinq colonnes doit valoir rating_count.
-- Si une ligne remonte ici, une note est tombée hors des cinq seaux et
-- l'histogramme mentirait. Attendu : zéro ligne.
-- ------------------------------------------------------------
select beer_id, rating_count, n1 + n2 + n3 + n4 + n5 as somme_seaux
from beer_ratings
where n1 + n2 + n3 + n4 + n5 <> rating_count;


-- ------------------------------------------------------------
-- Contrôle 3 — un aperçu lisible, sur les bières qui ont de l'historique.
-- ------------------------------------------------------------
select b.name, r.avg_rating, r.rating_count,
       r.n1 || ' · ' || r.n2 || ' · ' || r.n3 || ' · ' || r.n4 || ' · ' || r.n5
         as repartition_1_a_5
from beer_ratings r
join beers b on b.id = r.beer_id
where r.rating_count >= 3
order by r.rating_count desc, b.name
limit 20;
