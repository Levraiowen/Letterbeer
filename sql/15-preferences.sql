-- ============================================================
-- Migration 15 — préférences de goût et premier lancement
-- À coller et Run SEUL dans le SQL Editor.
--
-- Deux questions posées à l'inscription, pour que la première ouverture
-- ne soit pas un catalogue de plusieurs centaines de canettes sans
-- aucune note. Les réponses servent à trier, rien de plus : il n'y a
-- pas de moteur de recommandation derrière, juste un filtre.
-- ============================================================

alter table profiles add column if not exists pref_familles text;
alter table profiles add column if not exists pref_degre    text
  check (pref_degre in ('leger','moyen','fort','tout'));
alter table profiles add column if not exists onboarded     boolean not null default false;

comment on column profiles.pref_familles is
  'Familles de styles préférées, séparées par des virgules : blondes, ipa, brunes, tout.';
comment on column profiles.onboarded is
  'Vrai dès que le premier lancement a été vu, qu''il ait été rempli ou passé.';

-- ------------------------------------------------------------
-- Les comptes déjà créés ne doivent pas revoir le premier lancement :
-- ils ont dépassé ce stade, leur reposer les questions serait absurde.
-- ------------------------------------------------------------
update profiles set onboarded = true where created_at < now();
