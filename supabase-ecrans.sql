-- ============================================================
-- Ce qu'il manquait derrière les écrans du Compte
-- À coller et Run SEUL dans le SQL Editor.
-- ============================================================

-- ------------------------------------------------------------
-- Liste d'envies — le bouton « + À goûter » n'écrivait nulle part
--
-- Volontairement distincte de beer_watchers, qui sert au suivi de
-- prix : vouloir goûter une bière et surveiller son prix sont deux
-- intentions différentes.
-- ------------------------------------------------------------
create table if not exists wishlist (
  user_id    uuid not null references profiles(id) on delete cascade,
  beer_id    uuid not null references beers(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, beer_id)
);

alter table wishlist enable row level security;

drop policy if exists wl_own on wishlist;
create policy wl_own on wishlist for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());


-- ------------------------------------------------------------
-- Signalements — la table existait, sans personne pour les lire
--
-- L'auteur voit les siens, l'administrateur voit tout et peut les
-- clore. Sans ces règles, un signalement partait dans le vide.
-- ------------------------------------------------------------
drop policy if exists rp_read on reports;
create policy rp_read on reports for select to authenticated
  using (reporter_id = auth.uid() or is_admin());

drop policy if exists rp_resolve on reports;
create policy rp_resolve on reports for update to authenticated
  using (is_admin()) with check (is_admin());


-- ------------------------------------------------------------
-- Infos perso — pseudo et ville modifiables
--
-- La politique de mise à jour existait déjà, et le déclencheur posé
-- précédemment gèle id, age_ok et is_admin : seuls le pseudo, la
-- ville, l'avatar et la confidentialité restent modifiables.
-- On ajoute juste la contrainte de format sur le pseudo, qui n'était
-- vérifiée que dans le navigateur.
-- ------------------------------------------------------------
alter table profiles drop constraint if exists profiles_handle_format;
alter table profiles add constraint profiles_handle_format
  check (handle ~ '^[a-z0-9_.]{3,20}$');
