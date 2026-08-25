-- ============================================================
-- Migration 27 — l'invitation ne dépend plus du navigateur
-- À coller et Run SEUL dans le SQL Editor.
--
-- LE PROBLÈME
--
-- Le lien ?inv=<identifiant> était rangé dans le localStorage au moment du
-- clic, puis relu après l'inscription pour créer l'abonnement. Tout tenait
-- donc à ce que le MÊME navigateur serve du début à la fin. Or cette chaîne
-- casse dans des cas parfaitement ordinaires :
--
--   · on ouvre le lien sur son téléphone et on finit l'inscription ailleurs ;
--   · le lien de confirmation d'e-mail s'ouvre dans le navigateur intégré de
--     Gmail, qui n'a pas le localStorage du navigateur d'origine ;
--   · navigation privée, ou stockage vidé entre-temps.
--
-- Résultat constaté : on n'était pas amis à l'arrivée. C'est pourtant le
-- chemin exact par lequel arrivent tous les testeurs.
--
-- LA CORRECTION
--
-- L'identifiant du parrain voyage désormais dans les métadonnées de
-- l'inscription elle-même, et c'est ce déclencheur — déjà chargé de créer le
-- profil — qui pose l'abonnement. Plus aucun navigateur dans la boucle.
--
-- Le bloc d'exception n'est pas décoratif : sans lui, un parrain dont le
-- compte a été supprimé entre l'envoi du lien et l'inscription ferait échouer
-- la clé étrangère, donc ANNULER TOUTE L'INSCRIPTION. Une invitation ratée ne
-- doit jamais coûter un compte.
--
-- L'ancien chemin par localStorage reste en place comme filet, pour les liens
-- déjà distribués. Il ne vide plus sa clé avant d'avoir réussi.
-- ============================================================

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base_handle  text;
  final_handle text;
  parrain      uuid;
  n int := 1;
begin
  base_handle := lower(coalesce(trim(new.raw_user_meta_data->>'handle'), ''));
  base_handle := regexp_replace(base_handle, '\s+', '_', 'g');
  base_handle := regexp_replace(base_handle, '[^a-z0-9_.]', '', 'g');

  if char_length(base_handle) < 3 then
    base_handle := 'buveur_' || substr(new.id::text, 1, 6);
  end if;

  final_handle := left(base_handle, 20);

  while exists (select 1 from profiles where handle = final_handle) loop
    n := n + 1;
    final_handle := left(base_handle, 16) || '_' || n;
    if n > 999 then
      final_handle := 'buveur_' || substr(new.id::text, 1, 8);
      exit;
    end if;
  end loop;

  insert into profiles (id, handle, age_ok)
  values (new.id, final_handle,
          coalesce((new.raw_user_meta_data->>'age_ok')::boolean, false));

  -- ---- l'invitation ----
  -- L'invité suit son parrain, jamais l'inverse : personne ne doit pouvoir
  -- décider qui suit qui. Le parrain reçoit un abonné, et suit en retour
  -- s'il le souhaite.
  begin
    parrain := nullif(new.raw_user_meta_data->>'parrain', '')::uuid;
    if parrain is not null and parrain <> new.id then
      insert into follows (follower_id, followee_id)
      select new.id, p.id from profiles p where p.id = parrain
      on conflict do nothing;
    end if;
  exception when others then
    -- parrain inconnu, identifiant illisible, compte supprimé entre-temps :
    -- on laisse tomber l'abonnement, jamais l'inscription
    null;
  end;

  return new;
end $$;


-- ------------------------------------------------------------
-- Contrôle — la fonction doit désormais mentionner le parrain.
-- ------------------------------------------------------------
select case
         when prosrc like '%parrain%' and prosrc like '%left(base_handle, 20)%'
           then '✅ invitation côté serveur, pseudo toujours gardé à 20 signes'
         else '❌ version incomplète'
       end as etat
from pg_proc where proname = 'handle_new_user';
