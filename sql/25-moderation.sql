-- ============================================================
-- Migration 25 — de quoi modérer pour de vrai
-- À coller et Run SEUL dans le SQL Editor.
--
-- L'écran d'administration n'avait qu'un pouvoir : changer le statut d'une
-- fiche bière. Les signalements pouvaient être lus et clos, mais rien ne
-- permettait d'agir sur ce qu'ils dénonçaient — ni retirer un avis, ni
-- retirer une réponse, ni supprimer une fiche. Un signalement traité ne
-- pouvait donc que disparaître de la liste sans que rien ne change.
--
-- CE QUI REND LA CHOSE INCASSABLE
--
-- Le fait de cacher l'onglet dans le navigateur ne protège RIEN : n'importe
-- qui peut forcer l'affichage depuis la console. La seule barrière qui
-- compte est ici. Chaque règle ci-dessous exige is_admin(), une fonction
-- « security definer » qui lit profiles.is_admin pour auth.uid() seulement.
--
-- Et cette colonne n'est pas atteignable depuis le navigateur :
--   · le déclencheur profiles_freeze (migrations 08 et 14) remet is_admin
--     à son ancienne valeur dès que auth.uid() n'est pas NULL, donc pour
--     toute écriture venue de l'app — impossible de se promouvoir ;
--   · depuis la migration 19, la colonne n'est même plus lisible.
-- On ne se donne les droits que depuis le SQL Editor, où auth.uid() est NULL.
--
-- Conséquence : quelqu'un qui forcerait l'écran verrait une page vide et
-- se prendrait un refus à chaque geste. C'est le comportement voulu.
-- ============================================================


-- ------------------------------------------------------------
-- Supprimer une fiche bière — mais JAMAIS l'historique de quelqu'un
--
-- La migration 13 posait déjà le principe à la main : « On ne touche pas
-- aux fiches que quelqu'un a déjà bues ou commentées : les effacer ferait
-- disparaître des notes sans prévenir personne. » beers cascade en effet
-- sur logs et reviews.
--
-- Ce principe cesse d'être une consigne pour devenir une garantie : la
-- règle refuse la suppression dès qu'une entrée de journal ou un avis
-- existe. Pour ces fiches-là, il reste le passage en 'rejected', qui les
-- retire de la circulation sans rien effacer.
-- ------------------------------------------------------------
drop policy if exists b_delete on beers;
create policy b_delete on beers for delete to authenticated
  using (
    is_admin()
    and not exists (select 1 from logs    l where l.beer_id = beers.id)
    and not exists (select 1 from reviews r where r.beer_id = beers.id)
  );


-- ------------------------------------------------------------
-- Retirer un avis ou une réponse signalés
--
-- Les règles existantes ne laissent effacer que ce qu'on a écrit soi-même,
-- ou une réponse sous son propre avis. Sans celles-ci, un signalement pour
-- propos haineux n'aboutissait à rien.
-- ------------------------------------------------------------
drop policy if exists r_delete_admin on reviews;
create policy r_delete_admin on reviews for delete to authenticated
  using (is_admin());

drop policy if exists y_delete_admin on replies;
create policy y_delete_admin on replies for delete to authenticated
  using (is_admin());


-- ------------------------------------------------------------
-- Retirer un relevé de prix signalé
--
-- prices n'avait aucune règle de suppression, pour personne. Un relevé
-- fantaisiste ne pouvait donc pas partir, et il pèse sur le « meilleur
-- prix » affiché à tout le monde.
-- ------------------------------------------------------------
drop policy if exists pr_delete_admin on prices;
create policy pr_delete_admin on prices for delete to authenticated
  using (is_admin());


-- ------------------------------------------------------------
-- La liste des signalements se lit par date, en commençant par ce qui
-- n'est pas encore traité.
-- ------------------------------------------------------------
create index if not exists reports_ouverts_idx
  on reports (resolved, created_at desc);


-- ------------------------------------------------------------
-- Contrôle — les cinq règles d'administration doivent être là.
-- ------------------------------------------------------------
select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and policyname in ('b_moderate','b_delete','r_delete_admin','y_delete_admin','pr_delete_admin')
order by tablename, policyname;
