-- ============================================================
-- Migration 28 — bloquer quelqu'un
-- À coller et Run SEUL dans le SQL Editor.
--
-- Bloquer, c'est le geste minimal qui rend un espace social vivable. Sans
-- lui, la seule issue face à quelqu'un qu'on ne veut plus lire est de
-- supprimer son compte.
--
-- LE MODÈLE RETENU, CELUI DE TWITTER
--
-- Le blocage est SYMÉTRIQUE pour la visibilité : si tu bloques quelqu'un,
-- ni toi ne vois ses avis, ni lui ne voit les tiens. Un blocage à sens
-- unique laisserait l'autre continuer à te lire et à te répondre, ce qui
-- ne règle qu'une moitié du problème.
--
-- Il délie aussi les abonnements, dans les deux sens : rester abonné à
-- quelqu'un qu'on vient de bloquer n'a aucun sens.
--
-- CE QUI RESTE VISIBLE, ET POURQUOI
--
-- Le PROFIL d'une personne bloquée reste lisible — pseudo, photo, ville.
-- Deux raisons : l'app affiche des pseudos un peu partout (auteurs d'avis
-- déjà chargés, listes d'abonnés, relevés de prix), et les faire disparaître
-- ferait apparaître des « undefined » à l'écran plutôt qu'un vrai blocage.
-- Et surtout, ces colonnes ne sont pas le problème : ce qu'on veut ne plus
-- lire, ce sont les AVIS et les RÉPONSES.
--
-- Le filtrage se fait par la base, pas par l'interface. Une personne bloquée
-- ne peut pas retrouver tes avis en interrogeant l'API directement.
-- ============================================================

create table if not exists blocks (
  blocker_id uuid not null references profiles(id) on delete cascade,
  blocked_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table blocks enable row level security;

-- chacun ne voit et ne gère que SES propres blocages : savoir qui t'a
-- bloqué n'apporte rien de bon
drop policy if exists bl_own on blocks;
create policy bl_own on blocks for all to authenticated
  using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());


-- ------------------------------------------------------------
-- Le test de blocage, dans les deux sens.
--
-- Il DOIT être « security definer » : une politique RLS qui interrogerait
-- blocks directement n'y verrait que les lignes visibles de l'appelant,
-- c'est-à-dire ses propres blocages. Le sens « il m'a bloqué » serait donc
-- ignoré, et le blocage ne fonctionnerait qu'à moitié.
-- ------------------------------------------------------------
create or replace function est_bloque(autre uuid) returns boolean
language sql security definer set search_path = public stable as $$
  select exists (
    select 1 from blocks
    where (blocker_id = auth.uid() and blocked_id = autre)
       or (blocker_id = autre        and blocked_id = auth.uid())
  );
$$;

revoke all on function est_bloque(uuid) from public, anon;
grant execute on function est_bloque(uuid) to authenticated;


-- ------------------------------------------------------------
-- Bloquer délie les abonnements, dans les deux sens.
-- Le déclencheur est « security definer » pour pouvoir supprimer aussi
-- l'abonnement de l'autre, qui ne lui appartient pas.
-- ------------------------------------------------------------
create or replace function delier_au_blocage() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  delete from follows
   where (follower_id = new.blocker_id and followee_id = new.blocked_id)
      or (follower_id = new.blocked_id and followee_id = new.blocker_id);
  return new;
end $$;

drop trigger if exists blocks_delie on blocks;
create trigger blocks_delie
  after insert on blocks for each row
  execute function delier_au_blocage();


-- ------------------------------------------------------------
-- Les avis et les réponses disparaissent des deux côtés.
-- ------------------------------------------------------------
drop policy if exists r_read on reviews;
create policy r_read on reviews for select to authenticated
  using (not est_bloque(user_id));

drop policy if exists y_read on replies;
create policy y_read on replies for select to authenticated
  using (not est_bloque(user_id));


create index if not exists blocks_blocked_idx on blocks (blocked_id);


-- ------------------------------------------------------------
-- Contrôle — la table, la fonction, le déclencheur et les deux règles.
-- ------------------------------------------------------------
select 'table blocks' as quoi,
       (select count(*)::text from information_schema.tables
        where table_schema='public' and table_name='blocks') as etat
union all
select 'fonction est_bloque',
       (select count(*)::text from pg_proc where proname='est_bloque')
union all
select 'déclencheur blocks_delie',
       (select count(*)::text from pg_trigger where tgname='blocks_delie')
union all
select 'règles filtrées par le blocage',
       (select count(*)::text from pg_policies
        where schemaname='public' and policyname in ('r_read','y_read')
          and qual like '%est_bloque%');
