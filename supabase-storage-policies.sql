-- ============================================================
-- BLOC 1 / 2 — à coller et Run SEUL, en premier
-- Policies de storage : sans elles, tout upload est refusé
-- (buckets "avatars" et "beers" doivent déjà exister, publics)
-- ============================================================

drop policy if exists "read_avatars" on storage.objects;
create policy "read_avatars" on storage.objects for select to public
  using (bucket_id = 'avatars');

drop policy if exists "write_avatars" on storage.objects;
create policy "write_avatars" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "update_avatars" on storage.objects;
create policy "update_avatars" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "read_beers" on storage.objects;
create policy "read_beers" on storage.objects for select to public
  using (bucket_id = 'beers');

drop policy if exists "write_beers" on storage.objects;
create policy "write_beers" on storage.objects for insert to authenticated
  with check (bucket_id = 'beers');
