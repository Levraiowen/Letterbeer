-- ============================================================
-- Migration : suppression de compte (RGPD, droit à l'effacement)
-- À coller et Run SEUL dans le SQL Editor.
--
-- Le navigateur ne peut pas supprimer une ligne de auth.users : ça
-- demande la clé service_role, qui ne doit jamais sortir du serveur.
-- On passe donc par une fonction "security definer" : elle s'exécute
-- avec les droits de son propriétaire, mais ne peut effacer que la
-- ligne de l'appelant, puisqu'elle filtre sur auth.uid().
--
-- Supprimer auth.users cascade sur profiles, qui cascade lui-même sur
-- logs, reviews, reactions, replies, follows et beer_watchers — tout
-- est déjà déclaré "on delete cascade" dans schema.sql.
-- ============================================================

create or replace function delete_my_account() returns void
language plpgsql security definer set search_path = public, auth, storage as $$
declare me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Aucun utilisateur connecté.';
  end if;

  -- les fichiers du bucket ne sont pas cascadés : on retire les lignes
  -- restantes au cas où la suppression côté navigateur aurait échoué
  delete from storage.objects
   where bucket_id = 'avatars' and (storage.foldername(name))[1] = me::text;

  delete from auth.users where id = me;
end $$;

-- personne d'autre qu'un utilisateur connecté ne peut l'appeler
revoke all on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;

-- ------------------------------------------------------------
-- Il manquait la permission d'effacer sa propre photo de profil :
-- sans elle, l'app ne peut pas nettoyer le bucket avant la
-- suppression du compte.
-- ------------------------------------------------------------
drop policy if exists "delete_avatars" on storage.objects;
create policy "delete_avatars" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
