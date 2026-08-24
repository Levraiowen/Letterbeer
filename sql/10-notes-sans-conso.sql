-- ============================================================
-- Dissocier « noter » et « avoir bu »
-- À coller et Run SEUL dans le SQL Editor.
--
-- Jusqu'ici, noter une bière créait forcément une entrée de journal :
-- impossible de noter de mémoire sans gonfler ses volumes, ses unités,
-- ses calories et ses dépenses. On ajoute un drapeau : une entrée non
-- comptée porte la note, mais ne compte pas comme une canette bue.
--
-- La note reste unique par personne et par bière, comptée ou non :
-- l'index posé précédemment continue de s'appliquer.
-- ============================================================

alter table logs add column if not exists counted boolean not null default true;

comment on column logs.counted is
  'false = note saisie sans avoir bu (de mémoire). Exclue des volumes, unités, calories et dépenses.';


-- ------------------------------------------------------------
-- Les stats publiques doivent suivre la même règle, sinon les
-- autres verraient des canettes que leur auteur n''a jamais bues.
-- ------------------------------------------------------------
create or replace function public_stats(target uuid)
returns table (cans bigint, avg_rating numeric, week_cans bigint, top_style text)
language sql security definer set search_path = public stable as $$
  select
    count(*) filter (where l.counted),
    round(avg(l.rating)::numeric, 1),
    count(*) filter (where l.counted and l.drunk_at > now() - interval '7 days'),
    (select b.style from logs l2 join beers b on b.id = l2.beer_id
      where l2.user_id = target and l2.counted
      group by b.style order by count(*) desc limit 1)
  from logs l
  where l.user_id = target
    and not (select private_stats from profiles where id = target);
$$;
revoke all on function public_stats(uuid) from public, anon;
grant execute on function public_stats(uuid) to authenticated;


create or replace function all_public_stats()
returns table (user_id uuid, cans bigint, avg_rating numeric,
               week_cans bigint, top_style text)
language sql security definer set search_path = public stable as $$
  select p.id,
         count(l.id) filter (where l.counted),
         round(avg(l.rating)::numeric, 1),
         count(l.id) filter (where l.counted and l.drunk_at > now() - interval '7 days'),
         (select b.style from logs l2 join beers b on b.id = l2.beer_id
           where l2.user_id = p.id and l2.counted
           group by b.style order by count(*) desc limit 1)
  from profiles p
  left join logs l on l.user_id = p.id
  where not p.private_stats
  group by p.id;
$$;
revoke all on function all_public_stats() from public, anon;
grant execute on function all_public_stats() to authenticated;
