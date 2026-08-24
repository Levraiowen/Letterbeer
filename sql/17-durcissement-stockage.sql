-- ============================================================
-- Migration 17 — resserrer le dépôt de fichiers
-- À coller et Run SEUL dans le SQL Editor.
--
-- La règle d'envoi sur le bucket « beers » autorisait n'importe quel
-- utilisateur connecté à déposer n'importe quel fichier, n'importe où
-- dans le bucket, sans possibilité de savoir qui l'avait mis. Comme
-- rien ne l'utilise encore, autant refermer avant d'ouvrir.
-- ============================================================

-- ------------------------------------------------------------
-- Chacun dépose dans son propre dossier, comme pour les avatars.
-- On sait ainsi toujours qui a envoyé quoi, et personne ne peut
-- écraser le fichier d'un autre.
-- ------------------------------------------------------------
drop policy if exists "write_beers" on storage.objects;
create policy "write_beers" on storage.objects for insert to authenticated
  with check (
    bucket_id = 'beers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "update_beers" on storage.objects;
create policy "update_beers" on storage.objects for update to authenticated
  using (
    bucket_id = 'beers'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "delete_beers" on storage.objects;
create policy "delete_beers" on storage.objects for delete to authenticated
  using (
    bucket_id = 'beers'
    and ((storage.foldername(name))[1] = auth.uid()::text or is_admin())
  );


-- ------------------------------------------------------------
-- Taille et types de fichiers acceptés
--
-- Ces limites vivent dans storage.buckets et se posent donc en SQL,
-- inutile de les chercher dans l'interface.
--
-- Sans elles, rien n'empêche d'envoyer un fichier de plusieurs centaines
-- de mégaoctets, ni un fichier qui n'est pas une image. Le
-- redimensionnement côté navigateur ne protège pas : il suffit d'appeler
-- l'API directement pour le contourner.
--
-- 2 Mo est large : une photo redimensionnée par l'app pèse autour de
-- cent kilooctets.
-- ------------------------------------------------------------
update storage.buckets
   set file_size_limit    = 2097152,                                  -- 2 Mo
       allowed_mime_types = array['image/jpeg','image/png','image/webp']
 where id in ('avatars','beers');


-- ------------------------------------------------------------
-- Contrôle : deux lignes, chacune à 2097152 et trois types autorisés.
-- ------------------------------------------------------------
select id, file_size_limit, allowed_mime_types
from storage.buckets
where id in ('avatars','beers')
order by id;
