-- ============================================================
-- Migration 21 — cesser de raccourcir les pseudos en silence
-- À coller et Run SEUL dans le SQL Editor.
--
-- Le formulaire d'inscription annonce « 3 à 20 caractères » et accepte
-- bien 20. Le déclencheur, lui, faisait « left(base_handle, 16) » avant
-- même de chercher une collision : un pseudo de 17 à 20 signes était donc
-- accepté à l'écran puis raccourci sans que personne n'en soit averti.
-- Vérifié : « oooooooooooooooooooo » (20) devenait « oooooooooooooooo » (16).
--
-- Les 16 caractères servaient à garder la place du suffixe « _2 » à
-- « _999 » ajouté en cas de collision, qui doit tenir dans les 20 signes
-- autorisés par profiles_handle_format. On ne raccourcit donc plus que
-- dans ce cas-là, qui est le seul où c'est nécessaire.
--
-- La normalisation du jeu de caractères, posée en migration 20, ne bouge pas.
-- ============================================================

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base_handle  text;
  final_handle text;
  n int := 1;
begin
  base_handle := lower(coalesce(trim(new.raw_user_meta_data->>'handle'), ''));
  base_handle := regexp_replace(base_handle, '\s+', '_', 'g');
  base_handle := regexp_replace(base_handle, '[^a-z0-9_.]', '', 'g');

  -- trop court après nettoyage, ou vide au départ : on retombe sur
  -- l'identifiant, qui est de l'hexadécimal donc toujours valide
  if char_length(base_handle) < 3 then
    base_handle := 'buveur_' || substr(new.id::text, 1, 6);
  end if;

  -- le pseudo demandé est gardé tel quel, jusqu'aux 20 signes autorisés
  final_handle := left(base_handle, 20);

  -- ce n'est qu'en cas de collision qu'il faut réserver la place du suffixe
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
  return new;
end $$;


-- ------------------------------------------------------------
-- Contrôle — la fonction doit contenir « left(base_handle, 20) ».
-- Les pseudos déjà raccourcis ne sont pas rattrapés : on ne renomme
-- pas quelqu'un dans son dos. Chacun peut corriger le sien depuis
-- l'écran Compte.
-- ------------------------------------------------------------
select case
         when prosrc like '%left(base_handle, 20)%' then '✅ pseudo gardé jusqu''à 20 signes'
         else '❌ ancienne version encore en place'
       end as etat
from pg_proc where proname = 'handle_new_user';
