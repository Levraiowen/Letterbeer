-- ============================================================
-- Migration 23 — une bio courte sur le profil
-- À coller et Run SEUL dans le SQL Editor.
--
-- 250 signes, pas 500 : sur un téléphone, au-dessus de 250 la bio pousse
-- les vraies informations du profil — les repères, la semaine, les avis —
-- sous la ligne de flottaison. Une contrainte courte pousse aussi à écrire
-- quelque chose plutôt qu'à remplir un formulaire.
--
-- ⚠️ LE PIÈGE DE LA MIGRATION 19 : depuis qu'on filtre par colonne, une
--    colonne ajoutée sans être déclarée dans le grant reste INVISIBLE de
--    l'app, silencieusement. D'où le grant explicite ci-dessous. C'est
--    exactement ce que le README annonce comme prix du cloisonnement.
--
-- ORDRE : indifférent. L'app demande la colonne bio, mais si elle n'existe
--    pas encore elle recharge les profils sans, en le signalant dans la
--    console. Le champ reste simplement invisible jusqu'à cette migration.
--    Il aurait été intenable d'exiger « migration avant déploiement » ici
--    quand la 19 exige exactement l'inverse.
-- ============================================================

alter table profiles add column if not exists bio text
  check (bio is null or char_length(bio) <= 250);

comment on column profiles.bio is
  'Présentation libre, 250 signes maximum. Publique, facultative.';

-- sans cette ligne, l'app ne verrait jamais la colonne
grant select (bio) on profiles to authenticated;


-- ------------------------------------------------------------
-- Contrôle — bio doit apparaître dans la liste des colonnes lisibles,
-- qui passe ainsi de 9 à 10.
-- ------------------------------------------------------------
select count(*) as colonnes_lisibles,
       string_agg(column_name, ', ' order by column_name) as detail
from information_schema.column_privileges
where grantee = 'authenticated'
  and privilege_type = 'SELECT'
  and table_name = 'profiles';
