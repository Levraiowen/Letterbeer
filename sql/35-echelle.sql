-- ============================================================
-- Migration 35 — les corrections d'échelle mécaniques
-- Issue de l'audit du 27 août 2026.
--
-- ⚠️ TROIS BLOCS. Les lancer SÉPARÉMENT, dans l'ordre, et lire le
--    contrôle de chacun avant de passer au suivant.
--
-- Aucun changement de COMPORTEMENT : après cette migration, l'app fait
-- exactement ce qu'elle faisait avant, en moins de travail pour la base.
-- Elle ne nécessite aucun déploiement d'index.html, et peut donc être
-- passée quand tu veux, avant ou après un `git push`.
--
--
-- POURQUOI MAINTENANT
--
-- Les trois problèmes réglés ici sont invisibles à onze comptes et
-- deviennent structurants à mille. Ils ne se voient pas venir : rien ne se
-- dégrade progressivement, ça marche jusqu'au jour où ça ne marche plus.
-- Autant les régler pendant qu'ils ne coûtent rien.
-- ============================================================


-- ============================================================
-- BLOC 1 — ne plus rappeler auth.uid() à chaque ligne
--
-- Une politique écrite `user_id = auth.uid()` fait appeler la fonction pour
-- CHAQUE LIGNE examinée. Écrite `user_id = (select auth.uid())`, PostgreSQL
-- l'évalue une seule fois par requête et réutilise le résultat (InitPlan).
--
-- Invisible sur les 462 lignes d'aujourd'hui. Sur 100 000 entrées de
-- journal, c'est 100 000 appels de fonction par lecture.
--
-- Même traitement pour is_admin() et is_adult(), qui sont dans le même cas :
-- des fonctions sans argument, STABLE, qu'on peut hisser hors de la boucle.
-- Le conseiller Supabase ne les signale pas — il ne regarde que `auth.*` —
-- mais le gain est identique et le risque nul.
--
-- Les définitions ci-dessous sont RECOPIÉES à l'identique depuis la base le
-- 27 août 2026, pas réécrites de mémoire. Seuls les appels de fonction sont
-- enveloppés. Le lot est transactionnel : si une ligne échoue, rien n'est
-- appliqué et aucune table ne se retrouve sans politique.
-- ============================================================

-- ---- beer_watchers ----
drop policy if exists w_own on beer_watchers;
create policy w_own on beer_watchers for all to authenticated
  using       (user_id = (select auth.uid()))
  with check  (user_id = (select auth.uid()));

-- ---- beers ----
drop policy if exists b_read on beers;
create policy b_read on beers for select to authenticated
  using (status = 'approved'
      or submitted_by = (select auth.uid())
      or (select is_admin()));

drop policy if exists b_insert on beers;
create policy b_insert on beers for insert to authenticated
  with check (submitted_by = (select auth.uid())
          and status = 'pending'
          and (select is_adult()));

-- ---- blocks ----
drop policy if exists bl_own on blocks;
create policy bl_own on blocks for all to authenticated
  using       (blocker_id = (select auth.uid()))
  with check  (blocker_id = (select auth.uid()));

-- ---- follows ----
drop policy if exists f_write on follows;
create policy f_write on follows for all to authenticated
  using       (follower_id = (select auth.uid()))
  with check  (follower_id = (select auth.uid()));

-- ---- logs — le journal privé, la politique la plus lue de l'app ----
drop policy if exists l_all on logs;
create policy l_all on logs for all to authenticated
  using       (user_id = (select auth.uid()))
  with check  (user_id = (select auth.uid()) and (select is_adult()));

-- ---- prices ----
drop policy if exists pr_write on prices;
create policy pr_write on prices for insert to authenticated
  with check (user_id = (select auth.uid()) and (select is_adult()));

-- ---- profiles ----
drop policy if exists p_update on profiles;
create policy p_update on profiles for update to authenticated
  using       (id = (select auth.uid()))
  with check  (id = (select auth.uid()));

-- ---- reactions ----
drop policy if exists x_own on reactions;
create policy x_own on reactions for all to authenticated
  using       (user_id = (select auth.uid()))
  with check  (user_id = (select auth.uid()) and (select is_adult()));

-- ---- replies ----
drop policy if exists y_write on replies;
create policy y_write on replies for insert to authenticated
  with check (user_id = (select auth.uid()) and (select is_adult()));

drop policy if exists y_delete on replies;
create policy y_delete on replies for delete to authenticated
  using (user_id = (select auth.uid()));

-- l'auteur de l'avis peut retirer une réponse sous SON avis
drop policy if exists y_delete_hote on replies;
create policy y_delete_hote on replies for delete to authenticated
  using (review_id in (select id from reviews where user_id = (select auth.uid())));

-- ---- reports ----
drop policy if exists rp_read on reports;
create policy rp_read on reports for select to authenticated
  using (reporter_id = (select auth.uid()) or (select is_admin()));

drop policy if exists rp_write on reports;
create policy rp_write on reports for insert to authenticated
  with check (reporter_id = (select auth.uid()));

-- ---- reviews ----
drop policy if exists r_write on reviews;
create policy r_write on reviews for insert to authenticated
  with check (user_id = (select auth.uid()) and (select is_adult()));

drop policy if exists r_update on reviews;
create policy r_update on reviews for update to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists r_delete on reviews;
create policy r_delete on reviews for delete to authenticated
  using (user_id = (select auth.uid()));

-- ---- wishlist ----
drop policy if exists wl_own on wishlist;
create policy wl_own on wishlist for all to authenticated
  using       (user_id = (select auth.uid()))
  with check  (user_id = (select auth.uid()));


-- ------------------------------------------------------------
-- Contrôle du bloc 1 — attendu : ZÉRO ligne.
-- Toute politique qui appelle encore auth.uid() « nu » ressort ici.
-- ------------------------------------------------------------
select c.relname as tbl, p.polname as police_a_corriger
from pg_policy p join pg_class c on c.oid = p.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and (coalesce(pg_get_expr(p.polqual, p.polrelid), '') ~ '[^(]auth\.uid\(\)'
    or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') ~ '[^(]auth\.uid\(\)')
order by c.relname, p.polname;


-- ============================================================
-- BLOC 2 — les huit clés étrangères sans index
--
-- PostgreSQL n'indexe PAS automatiquement le côté « enfant » d'une clé
-- étrangère. Conséquence : à chaque suppression du parent, il balaie la
-- table entière pour vérifier qu'aucun enfant ne pointe dessus.
--
-- delete_my_account() en déclenche cinq d'un coup. Sur 462 lignes c'est
-- gratuit ; sur 100 000, c'est une suppression de compte qui expire.
--
-- Pas de CONCURRENTLY : il est interdit dans une transaction, et l'éditeur
-- SQL de Supabase en ouvre une. Sur ces volumes, la pose est instantanée.
-- À reconsidérer seulement si un jour ces tables font des millions de lignes.
-- ============================================================

-- celui qui sert le PLUS souvent : « qui me suit », et les suggestions
-- « À découvrir » qui remontent d'abord ceux qui te suivent sans réciprocité
create index if not exists follows_followee_idx    on follows       (followee_id);

-- les suivants servent aux cascades de suppression
create index if not exists reactions_review_idx    on reactions     (review_id);
create index if not exists replies_user_idx        on replies       (user_id);
create index if not exists prices_user_idx         on prices        (user_id);
create index if not exists beers_submitted_by_idx  on beers         (submitted_by)
  where submitted_by is not null;   -- partiel : la quasi-totalité du catalogue vient de l'import
create index if not exists wishlist_beer_idx       on wishlist      (beer_id);
create index if not exists beer_watchers_beer_idx  on beer_watchers (beer_id);
create index if not exists reports_reporter_idx    on reports       (reporter_id);


-- ------------------------------------------------------------
-- Contrôle du bloc 2 — attendu : ZÉRO ligne.
-- ------------------------------------------------------------
with fk as (
  select c.conrelid as reloid, c.conrelid::regclass::text as tbl, a.attname as colonne
  from pg_constraint c
  join pg_namespace n on n.oid = c.connamespace
  join lateral unnest(c.conkey) k(att) on true
  join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.att
  where c.contype = 'f' and n.nspname = 'public' and array_length(c.conkey,1) = 1
)
select fk.tbl, fk.colonne
from fk
where not exists (
  select 1 from pg_index i
  join pg_attribute ia on ia.attrelid = i.indrelid and ia.attnum = i.indkey[0]
  where i.indrelid = fk.reloid and ia.attname = fk.colonne
)
order by fk.tbl, fk.colonne;


-- ============================================================
-- BLOC 3 — refermer les fonctions exposées sans compte
--
-- Sept fonctions `security definer` sont appelables par le rôle `anon` via
-- /rest/v1/rpc/…, sans être connecté.
--
-- SOYONS PRÉCIS SUR LE RISQUE : il est faible. Ce sont toutes des fonctions
-- de DÉCLENCHEUR, et PostgreSQL refuse de les exécuter hors déclencheur
-- (« trigger functions can only be called as triggers »). Personne ne peut
-- en tirer quoi que ce soit aujourd'hui.
--
-- Ce qui compte, c'est le MOTIF. C'est exactement la famille d'oubli qui
-- avait rendu expire_prices() appelable sans compte, corrigée en migration
-- 20 : un droit accordé par défaut à la création, jamais retiré. Le cas
-- avait été traité une fois, pas balayé. On balaie.
--
-- is_admin() et is_adult() sont retirées à `anon` aussi. Elles rendent
-- `false` à un visiteur non connecté, donc rien ne fuite — mais une fonction
-- qui répond à qui n'a pas de compte n'a aucune raison d'être exposée.
-- `authenticated` les garde : les politiques RLS s'en servent.
-- ============================================================

-- fonctions de déclencheur : personne ne doit les appeler directement
revoke execute on function public.handle_new_user()                  from anon, public;
revoke execute on function public.bump_review_counts()               from anon, public;
revoke execute on function public.figer_compteurs_avis()             from anon, public;
revoke execute on function public.figer_releve_prix()                from anon, public;
revoke execute on function public.freeze_sensitive_profile_fields()  from anon, public;
revoke execute on function public.moderer_texte()                    from anon, public;
revoke execute on function public.delier_au_blocage()                from anon, public;

-- aides des politiques : réservées aux comptes connectés
revoke execute on function public.is_admin()   from anon, public;
revoke execute on function public.is_adult()   from anon, public;
grant  execute on function public.is_admin()   to authenticated;
grant  execute on function public.is_adult()   to authenticated;


-- ------------------------------------------------------------
-- Contrôle du bloc 3 — attendu : aucune ligne avec grantee = 'anon'
-- pour les fonctions de déclencheur.
--
-- ⚠️ Puis, dans l'app : créer un compte, écrire un avis, relever un prix,
-- bloquer quelqu'un. Ces quatre gestes exercent les quatre déclencheurs dont
-- on vient de retirer les droits — si un `revoke` était de trop, c'est là
-- que ça se verrait. Les déclencheurs s'exécutent avec les droits du
-- PROPRIÉTAIRE de la fonction, pas de l'appelant : ils ne devraient rien
-- remarquer. On vérifie quand même.
-- ------------------------------------------------------------
select p.proname as fonction, r.grantee, r.privilege_type
from information_schema.routine_privileges r
join pg_proc p on p.proname = r.routine_name
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and r.routine_schema = 'public'
  and p.proname in ('handle_new_user','bump_review_counts','figer_compteurs_avis',
                    'figer_releve_prix','freeze_sensitive_profile_fields',
                    'moderer_texte','delier_au_blocage','is_admin','is_adult')
order by p.proname, r.grantee;


-- ============================================================
-- CE QUE CETTE MIGRATION NE FAIT PAS, VOLONTAIREMENT
--
-- - Elle ne touche pas à beer_ratings. Le Security Advisor la signale en
--   CRITICAL ; c'est un faux positif documenté en tête de la migration 26,
--   et « corriger » l'alerte casserait la note moyenne de toute l'app.
--
-- - Elle ne supprime pas beers_search_idx, que le conseiller dit inutilisé.
--   Il l'est parce que la recherche se fait dans le navigateur — et il
--   redeviendra nécessaire le jour où la recherche passera côté base, ce
--   que le premier bloquant de l'audit rendra inévitable. Le garder coûte
--   quelques kilo-octets ; le reposer plus tard coûterait une migration.
--
-- - Elle ne touche pas aux « multiple permissive policies » signalées sur
--   articles, follows, replies et reviews. Fusionner deux politiques en une
--   les rendrait plus difficiles à relire, pour un gain nul à cette échelle.
--   À revoir seulement si ces tables deviennent chaudes.
-- ============================================================
