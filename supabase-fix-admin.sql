-- ============================================================
-- CORRECTIF — le déclencheur bloquait aussi le SQL Editor
-- À coller et Run SEUL dans le SQL Editor.
--
-- Le déclencheur qui empêche un utilisateur de se donner les droits
-- depuis le navigateur remettait is_admin à son ancienne valeur pour
-- TOUTE mise à jour, y compris celle lancée ici. D'où un « update »
-- qui semblait passer mais ne changeait rien.
--
-- On ne gèle désormais les colonnes sensibles que lorsqu'un
-- utilisateur connecté est à l'origine de la modification. Depuis le
-- SQL Editor ou un script à clé service_role, auth.uid() est NULL :
-- la modification passe.
-- ============================================================

create or replace function freeze_sensitive_profile_fields() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- l'identifiant ne bouge jamais, quelle que soit l'origine
  new.id := old.id;

  -- majorité et droits d'admin : verrouillés côté navigateur seulement
  if auth.uid() is not null then
    new.age_ok   := old.age_ok;
    new.is_admin := old.is_admin;
  end if;

  return new;
end $$;


-- ------------------------------------------------------------
-- Maintenant, donne-toi les droits. Remplace l'adresse si besoin.
-- ------------------------------------------------------------
update profiles set is_admin = true
 where id = (select id from auth.users where email = 'owen.charp44@gmail.com');


-- ------------------------------------------------------------
-- Contrôle : doit renvoyer une ligne avec is_admin = true.
-- Si c'est vide, l'adresse ne correspond à aucun compte.
-- ------------------------------------------------------------
select p.handle, p.is_admin, u.email
from profiles p join auth.users u on u.id = p.id
where p.is_admin;
