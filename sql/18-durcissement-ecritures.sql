-- ============================================================
-- Migration 18 — resserrer deux règles d'écriture trop larges
-- À coller et Run SEUL dans le SQL Editor.
--
-- Aucune fonctionnalité ne change : ce qui marchait continue de marcher.
-- On retire seulement la marge de manœuvre dont personne n'a besoin.
-- ============================================================


-- ------------------------------------------------------------
-- Les relevés de prix
--
-- La règle disait « using (true) » : tout utilisateur connecté pouvait
-- modifier n'importe quelle ligne, donc réécrire le prix, le magasin ou
-- l'auteur de n'importe quel relevé. La fonctionnalité visée était
-- seulement le bouton « Toujours ce prix ».
--
-- Le filtrage par colonne n'existe pas en RLS : on passe par un
-- déclencheur, qui remet en place tout ce que l'auteur seul aurait le
-- droit de changer.
-- ------------------------------------------------------------
create or replace function figer_releve_prix() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- l'auteur du relevé, et lui seul, peut corriger ce qu'il a saisi
  if auth.uid() is null or old.user_id = auth.uid() then
    return new;
  end if;

  -- pour tous les autres, seule la confirmation est permise
  new.id       := old.id;
  new.beer_id  := old.beer_id;
  new.user_id  := old.user_id;
  new.price    := old.price;
  new.shop     := old.shop;
  new.city     := old.city;
  new.reported_at := old.reported_at;
  return new;
end $$;

drop trigger if exists prices_figer on prices;
create trigger prices_figer
  before update on prices for each row
  execute function figer_releve_prix();


-- ------------------------------------------------------------
-- Le profil
--
-- La règle de mise à jour avait un « using » mais pas de « with check » :
-- elle vérifiait la ligne d'origine, jamais la ligne résultante. Le
-- déclencheur posé en migration 08 empêchait déjà de déplacer un profil
-- vers quelqu'un d'autre, mais autant que la règle le dise aussi.
-- ------------------------------------------------------------
drop policy if exists p_update on profiles;
create policy p_update on profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());


-- ------------------------------------------------------------
-- Contrôle : les deux déclencheurs de gel doivent être présents.
-- ------------------------------------------------------------
select tgname as declencheur,
       (select relname from pg_class where oid = tgrelid) as sur_table
from pg_trigger
where tgname in ('prices_figer','profiles_freeze')
order by 1;
