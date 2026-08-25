-- ============================================================
-- Migration 26 — refermer beer_ratings aux visiteurs sans compte
-- À coller et Run SEUL dans le SQL Editor.
--
-- ⚠️ LIRE AVANT DE « CORRIGER » L'ALERTE SUPABASE ⚠️
--
-- Le Security Advisor signale beer_ratings en « Security Definer View ».
-- Le correctif que tout le monde applique par réflexe — poser
-- security_invoker = true — CASSERAIT L'APPLICATION. Ne le faites pas.
--
-- POURQUOI LA VUE EST « SECURITY DEFINER », ET POURQUOI C'EST VOULU
--
-- En PostgreSQL, une vue s'exécute par défaut avec les droits de son
-- PROPRIÉTAIRE, pas de celui qui l'interroge. beer_ratings appartient au
-- rôle qui a passé les migrations, lequel contourne le RLS : c'est
-- exactement ce qui permet de calculer la note moyenne d'une bière à
-- partir de logs, une table par ailleurs strictement privée.
--
-- Avec security_invoker = true, la vue s'exécuterait avec les droits de
-- l'appelant. La règle l_all (« user_id = auth.uid() ») s'appliquerait
-- alors, et chacun n'agrégerait plus que SON PROPRE journal : la note
-- publique deviendrait sa note personnelle, et toute bière qu'on n'a pas
-- notée soi-même n'afficherait plus rien du tout.
--
-- L'agrégation à travers le RLS est donc le but de cette vue, pas un
-- accident. L'alerte est une heuristique ; ici, l'exception est délibérée.
--
-- CE QUI ÉTAIT RÉELLEMENT UN PROBLÈME
--
-- La vue avait gardé le droit de lecture accordé par défaut au rôle anon.
-- Vérifié à la main : avec la seule clé publique, sans aucun compte, elle
-- rendait ses lignes — alors que TOUTES les autres tables du projet
-- renvoient zéro ligne à un visiteur anonyme, leurs règles étant posées
-- « to authenticated ». C'était le seul endroit du schéma par où des
-- données dérivées du journal sortaient sans authentification.
--
-- Ce qui sortait restait agrégé — identifiant de bière, moyenne, nombre de
-- notes — sans jamais d'identité. Mais c'était incohérent avec la posture
-- du reste de l'app, et c'est la même famille d'oubli que expire_prices
-- en migration 20 : un droit par défaut jamais retiré.
--
-- L'app est toujours authentifiée quand elle lit cette vue : rien ne change
-- pour elle.
-- ============================================================

revoke select on beer_ratings from anon;
grant  select on beer_ratings to authenticated;


-- ------------------------------------------------------------
-- On laisse la trace de l'intention dans la base elle-même, pour que la
-- prochaine personne qui verra l'alerte tombe d'abord sur l'explication.
-- ------------------------------------------------------------
comment on view beer_ratings is
  'Notes moyennes par bière. S''exécute volontairement avec les droits de '
  'son propriétaire pour agréger logs, qui est privée : NE PAS poser '
  'security_invoker, cela ferait disparaître les notes publiques. '
  'Lecture réservée aux comptes connectés (migration 26).';


-- ------------------------------------------------------------
-- Contrôle — anon doit être à false, authenticated à true.
-- ------------------------------------------------------------
select has_table_privilege('anon',          'beer_ratings', 'select') as anon_peut_lire,
       has_table_privilege('authenticated', 'beer_ratings', 'select') as connecte_peut_lire;
