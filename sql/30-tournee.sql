-- ============================================================
-- Migration 30 — « ma tournée » : trois canettes épinglées au profil
-- À coller et Run SEUL dans le SQL Editor.
--
-- L'idée vient du « top 4 » de Letterboxd, mais elle est retournée.
--
-- TROIS ET NON QUATRE. Le quatre est leur signature, et trois est la
-- largeur de la grille de l'app : ça s'intègre sans rien inventer. Un cran
-- de moins rend aussi le choix plus difficile, donc plus parlant.
--
-- « TOURNÉE » ET NON « FAVORITES ». Une tournée, c'est ce qu'on offre à la
-- table. Le mot déplace la fonctionnalité de « mon panthéon » — statique,
-- tourné vers soi — vers « ce que je te ferais goûter ». C'est le bon
-- registre pour une app qui se lit entre amis.
--
-- POURQUOI UN TABLEAU ET NON UNE TABLE
--
-- Trois éléments ordonnés par personne : une table coûterait une jointure
-- et une gestion de positions pour rien. Le revers assumé est qu'un
-- tableau ne porte pas de clé étrangère — si une fiche disparaît, son
-- identifiant reste dans la tournée de quelqu'un. L'app l'ignore
-- silencieusement, comme elle le fait déjà partout où une fiche peut
-- manquer.
--
-- ⚠️ Le grant est obligatoire : depuis la migration 19, une colonne non
--    déclarée reste invisible de l'app, en silence.
--
-- ORDRE : indifférent. Tant que la migration n'est pas passée, la colonne
-- n'existe pas, la section ne s'affiche pas, et le reste ne bouge pas.
-- ============================================================

alter table profiles add column if not exists tournee uuid[] not null default '{}';

alter table profiles drop constraint if exists profiles_tournee_max;
alter table profiles add constraint profiles_tournee_max
  check (array_length(tournee, 1) is null or array_length(tournee, 1) <= 3);

comment on column profiles.tournee is
  'Jusqu''à trois canettes épinglées au profil, dans l''ordre choisi. '
  'Publique. Pas de clé étrangère : un tableau n''en porte pas, l''app '
  'ignore les identifiants devenus caducs.';

grant select (tournee) on profiles to authenticated;


-- ------------------------------------------------------------
-- Contrôle — dix colonnes lisibles désormais, dont tournee.
-- ------------------------------------------------------------
select count(*) as colonnes_lisibles,
       string_agg(column_name, ', ' order by column_name) as detail
from information_schema.column_privileges
where grantee = 'authenticated'
  and privilege_type = 'SELECT'
  and table_name = 'profiles';
