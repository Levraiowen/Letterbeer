-- =====================================================================
-- LETTERBEER — schéma phase 1 (test entre amis)
-- À coller dans Supabase → SQL Editor → Run
-- =====================================================================

create extension if not exists pg_trgm;

-- ---------------------------------------------------------------- profils
create table profiles (
  id            uuid primary key references auth.users on delete cascade,
  handle        text unique not null check (char_length(handle) between 3 and 20),
  avatar_url    text,
  city          text,
  private_stats boolean not null default false,
  age_ok        boolean not null default false,
  created_at    timestamptz not null default now()
);

-- création automatique du profil à l'inscription
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, handle, age_ok)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'handle', 'buveur_' || substr(new.id::text,1,6)),
    coalesce((new.raw_user_meta_data->>'age_ok')::boolean, false)
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users for each row execute function handle_new_user();

-- ---------------------------------------------------------------- bières
create table beers (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 2 and 80),
  brewery      text not null,
  style        text,
  abv          numeric check (abv >= 0 and abv <= 20),
  volume_cl    int not null default 33 check (volume_cl between 10 and 200),
  country      text,
  description  text,
  image_url    text,
  barcode      text unique,
  color        text default '#FF7A2F',
  status       text not null default 'pending'
               check (status in ('pending','approved','rejected')),
  submitted_by uuid references profiles(id) on delete set null,
  created_at   timestamptz not null default now()
);
create unique index beers_name_brewery_uniq on beers (lower(name), lower(brewery));
create index beers_search_idx on beers using gin ((name || ' ' || brewery || ' ' || coalesce(style,'')) gin_trgm_ops);
create index beers_status_idx on beers (status);

-- ---------------------------------------------------------------- journal de conso
create table logs (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  beer_id    uuid not null references beers(id) on delete cascade,
  rating     int check (rating between 1 and 5),
  liked      boolean not null default false,
  price_paid numeric check (price_paid >= 0 and price_paid <= 999),
  shop       text,
  drunk_at   timestamptz not null default now()
);
create index logs_user_idx on logs (user_id, drunk_at desc);
create index logs_beer_idx on logs (beer_id);

-- ---------------------------------------------------------------- avis
create table reviews (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references profiles(id) on delete cascade,
  beer_id       uuid not null references beers(id) on delete cascade,
  rating        int check (rating between 1 and 5),
  liked         boolean not null default false,
  body          text not null check (char_length(body) between 1 and 2000),
  cheers_count  int not null default 0,
  bofs_count    int not null default 0,   -- JAMAIS exposé sauf à l'auteur
  created_at    timestamptz not null default now(),
  unique (user_id, beer_id)
);
create index reviews_beer_idx on reviews (beer_id);
create index reviews_pop_idx on reviews (cheers_count desc);

create table reactions (
  user_id    uuid not null references profiles(id) on delete cascade,
  review_id  uuid not null references reviews(id) on delete cascade,
  kind       text not null check (kind in ('cheer','bof','pass')),
  created_at timestamptz not null default now(),
  primary key (user_id, review_id, kind)
);

-- compteurs dénormalisés
create or replace function bump_review_counts() returns trigger
language plpgsql security definer set search_path = public as $$
declare d int; k text; r uuid;
begin
  if tg_op = 'INSERT' then d := 1; k := new.kind; r := new.review_id;
  else d := -1; k := old.kind; r := old.review_id; end if;
  if k = 'cheer' then update reviews set cheers_count = cheers_count + d where id = r;
  elsif k = 'bof' then update reviews set bofs_count = bofs_count + d where id = r; end if;
  return null;
end $$;

create trigger reactions_count
  after insert or delete on reactions for each row execute function bump_review_counts();

create table replies (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  review_id  uuid not null references reviews(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 500),
  created_at timestamptz not null default now()
);
create index replies_review_idx on replies (review_id);

-- ---------------------------------------------------------------- prix
create table prices (
  id            uuid primary key default gen_random_uuid(),
  beer_id       uuid not null references beers(id) on delete cascade,
  user_id       uuid not null references profiles(id) on delete set null,
  shop          text not null,
  city          text,
  price         numeric not null check (price > 0 and price < 200),
  reported_at   timestamptz not null default now(),
  confirmed_at  timestamptz not null default now(),
  confirmations int not null default 0,
  status        text not null default 'fresh' check (status in ('fresh','stale','flagged'))
);
create index prices_beer_idx on prices (beer_id, price);

-- péremption à 21 jours (à appeler par cron quotidien)
create or replace function expire_prices() returns void
language sql security definer set search_path = public as $$
  update prices set status = 'stale'
  where status = 'fresh' and confirmed_at < now() - interval '21 days';
$$;

create table beer_watchers (
  user_id uuid not null references profiles(id) on delete cascade,
  beer_id uuid not null references beers(id) on delete cascade,
  primary key (user_id, beer_id)
);

-- ---------------------------------------------------------------- abonnements
create table follows (
  follower_id uuid not null references profiles(id) on delete cascade,
  followee_id uuid not null references profiles(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);

-- ---------------------------------------------------------------- signalements
create table reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid references profiles(id) on delete set null,
  target_type text not null check (target_type in ('beer','review','price','profile')),
  target_id   uuid not null,
  reason      text,
  resolved    boolean not null default false,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------- notes moyennes
create view beer_ratings as
  select beer_id,
         round(avg(rating)::numeric, 1) as avg_rating,
         count(*) as rating_count
  from logs where rating is not null group by beer_id;

-- =====================================================================
-- RLS — à activer AVANT d'ouvrir à qui que ce soit
-- =====================================================================
alter table profiles      enable row level security;
alter table beers         enable row level security;
alter table logs          enable row level security;
alter table reviews       enable row level security;
alter table reactions     enable row level security;
alter table replies       enable row level security;
alter table prices        enable row level security;
alter table follows       enable row level security;
alter table beer_watchers enable row level security;
alter table reports       enable row level security;

-- profils : lisibles par tous les connectés, modifiables par soi seul
create policy p_read   on profiles for select to authenticated using (true);
create policy p_update on profiles for update to authenticated using (id = auth.uid());

-- bières : validées visibles par tous, en attente visibles par leur auteur
create policy b_read on beers for select to authenticated
  using (status = 'approved' or submitted_by = auth.uid());
create policy b_insert on beers for insert to authenticated
  with check (submitted_by = auth.uid() and status = 'pending');

-- journal : STRICTEMENT privé. Les dépenses ne sortent jamais.
create policy l_all on logs for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- avis : publics en lecture, écriture par soi seul
create policy r_read   on reviews for select to authenticated using (true);
create policy r_write  on reviews for insert to authenticated with check (user_id = auth.uid());
create policy r_update on reviews for update to authenticated using (user_id = auth.uid());
create policy r_delete on reviews for delete to authenticated using (user_id = auth.uid());

-- réactions : tu ne vois QUE les tiennes. Le bof ne fuit pas.
create policy x_own on reactions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy y_read  on replies for select to authenticated using (true);
create policy y_write on replies for insert to authenticated with check (user_id = auth.uid());

create policy pr_read   on prices for select to authenticated using (true);
create policy pr_write  on prices for insert to authenticated with check (user_id = auth.uid());
create policy pr_update on prices for update to authenticated using (true);

create policy f_read  on follows for select to authenticated using (true);
create policy f_write on follows for all to authenticated
  using (follower_id = auth.uid()) with check (follower_id = auth.uid());

create policy w_own on beer_watchers for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy rp_write on reports for insert to authenticated with check (reporter_id = auth.uid());

-- =====================================================================
-- Stats publiques d'un profil : fonction filtrée, pas d'accès direct
-- Ne renvoie JAMAIS les dépenses, même si le profil est public.
-- =====================================================================
create or replace function public_stats(target uuid)
returns table (cans bigint, avg_rating numeric, week_cans bigint, top_style text)
language sql security definer set search_path = public as $$
  select
    count(*),
    round(avg(l.rating)::numeric, 1),
    count(*) filter (where l.drunk_at > now() - interval '7 days'),
    (select b.style from logs l2 join beers b on b.id = l2.beer_id
      where l2.user_id = target group by b.style order by count(*) desc limit 1)
  from logs l
  where l.user_id = target
    and not (select private_stats from profiles where id = target);
$$;

-- =====================================================================
-- Bucket photos : Storage → New bucket « avatars » et « beers », publics
-- =====================================================================
