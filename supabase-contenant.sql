-- ============================================================
-- Canette ou bouteille : dire la vérité sur ce qu'on stocke
-- À coller et Run SEUL dans le SQL Editor.
--
-- L'import filtrait sur le mot « metal » dans les emballages. Une
-- capsule de bouteille étant en métal, toutes les bouteilles passaient :
-- d'où les 75 cl et 150 cl dans une base censée n'avoir que des canettes.
--
-- On garde les deux — refuser les bouteilles amputerait la base de
-- l'essentiel du catalogue français — mais on les étiquette.
-- ============================================================

alter table beers add column if not exists container text
  check (container in ('canette','bouteille'));

comment on column beers.container is
  'Contenant réel. NULL quand Open Food Facts est trop imprécis pour trancher.';

-- ------------------------------------------------------------
-- Rattrapage sur l'existant, uniquement là où c'est certain.
-- Aucune canette n'existe au-delà de 56 cl : le volume suffit à
-- classer les grands formats. En dessous, on ne devine pas.
-- ------------------------------------------------------------
update beers set container = 'bouteille'
 where container is null and volume_cl > 56;

-- les formats typiquement canette, quand la description le confirme
update beers set container = 'canette'
 where container is null
   and volume_cl in (25, 33, 44, 50)
   and description ilike '%canette%';

-- index utile dès qu'un filtre « canettes seulement » existe
create index if not exists beers_container_idx on beers (container)
  where container is not null;
