-- ============================================================
-- Durcissement — étapes 6, 7, 9, 10 et 11 du plan d'audit.
-- À coller et Run SEUL dans le SQL Editor.
-- ============================================================


-- ------------------------------------------------------------
-- M3 — collision de pseudo à l'inscription
--
-- Le déclencheur insérait le pseudo tel quel dans une colonne unique :
-- deux personnes qui choisissaient le même nom, et la seconde recevait
-- une erreur base brute au lieu d'un compte. On suffixe désormais
-- jusqu'à trouver un pseudo libre.
-- ------------------------------------------------------------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base_handle text;
  final_handle text;
  n int := 1;
begin
  base_handle := coalesce(
    nullif(trim(new.raw_user_meta_data->>'handle'), ''),
    'buveur_' || substr(new.id::text, 1, 6)
  );
  base_handle := left(base_handle, 16);
  final_handle := base_handle;

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
-- M6 — public_stats était appelable sans être connecté
-- ------------------------------------------------------------
revoke all on function public_stats(uuid) from public, anon;
grant execute on function public_stats(uuid) to authenticated;


-- ------------------------------------------------------------
-- F2 — les stats de tous les profils en une seule requête
--
-- L'app appelait public_stats une fois par membre. Cette version
-- renvoie tout d'un coup, en appliquant les mêmes filtres : rien
-- ne sort d'un profil qui a coché « stats privées », et jamais
-- la moindre dépense.
-- ------------------------------------------------------------
create or replace function all_public_stats()
returns table (user_id uuid, cans bigint, avg_rating numeric,
               week_cans bigint, top_style text)
language sql security definer set search_path = public stable as $$
  select p.id,
         count(l.id),
         round(avg(l.rating)::numeric, 1),
         count(l.id) filter (where l.drunk_at > now() - interval '7 days'),
         (select b.style from logs l2 join beers b on b.id = l2.beer_id
           where l2.user_id = p.id group by b.style order by count(*) desc limit 1)
  from profiles p
  left join logs l on l.user_id = p.id
  where not p.private_stats
  group by p.id;
$$;

revoke all on function all_public_stats() from public, anon;
grant execute on function all_public_stats() to authenticated;


-- ------------------------------------------------------------
-- M5 — la vérification d'âge se contournait
--
-- age_ok venait des métadonnées fournies par le client, et rien
-- n'empêchait ensuite de le modifier. On le gèle par déclencheur,
-- et on exige la majorité déclarée pour écrire quoi que ce soit.
-- ------------------------------------------------------------
create or replace function freeze_sensitive_profile_fields() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- ces colonnes ne se modifient pas depuis le navigateur
  new.id       := old.id;
  new.age_ok   := old.age_ok;
  new.is_admin := old.is_admin;
  return new;
end $$;

drop trigger if exists profiles_freeze on profiles;
create trigger profiles_freeze
  before update on profiles for each row
  execute function freeze_sensitive_profile_fields();

create or replace function is_adult() returns boolean
language sql security definer set search_path = public stable as $$
  select coalesce((select age_ok from profiles where id = auth.uid()), false);
$$;
grant execute on function is_adult() to authenticated;

-- on referme les écritures sur la majorité déclarée
drop policy if exists l_all on logs;
create policy l_all on logs for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and is_adult());

drop policy if exists r_write on reviews;
create policy r_write on reviews for insert to authenticated
  with check (user_id = auth.uid() and is_adult());


-- ------------------------------------------------------------
-- Étape 10 — modération des fiches proposées
--
-- Un drapeau administrateur, et le droit de changer le statut d'une
-- bière. Le reste du monde ne peut toujours qu'insérer en 'pending'.
-- ------------------------------------------------------------
alter table profiles add column if not exists is_admin boolean not null default false;

create or replace function is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false);
$$;
grant execute on function is_admin() to authenticated;

drop policy if exists b_read on beers;
create policy b_read on beers for select to authenticated
  using (status = 'approved' or submitted_by = auth.uid() or is_admin());

drop policy if exists b_moderate on beers;
create policy b_moderate on beers for update to authenticated
  using (is_admin()) with check (is_admin());

-- ⚠️ À FAIRE À LA MAIN : donne-toi les droits, en remplaçant l'adresse.
-- update profiles set is_admin = true
--  where id = (select id from auth.users where email = 'ton.email@exemple.fr');


-- ------------------------------------------------------------
-- M4 — la table des articles n'existait pas
--
-- L'app l'interrogeait déjà : l'erreur était avalée et l'onglet
-- restait vide sans explication. L'onglet ne s'affiche désormais
-- que s'il y a des articles publiés, et la table est prête pour
-- le jour où l'agrégateur tournera.
-- ------------------------------------------------------------
create table if not exists articles (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  summary      text not null,
  url          text,
  source       text,
  color        text default '#FF5A1F',
  status       text not null default 'pending'
               check (status in ('pending','published','rejected')),
  published_at timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists articles_status_idx on articles (status, published_at desc);

alter table articles enable row level security;

drop policy if exists a_read on articles;
create policy a_read on articles for select to authenticated
  using (status = 'published' or is_admin());

drop policy if exists a_write on articles;
create policy a_write on articles for all to authenticated
  using (is_admin()) with check (is_admin());
