-- ============================================================
-- Migration 29 — une modération automatique, volontairement faible
-- À coller et Run SEUL dans le SQL Editor.
--
-- LE PARTI PRIS : TRÈS PERMISSIF
--
-- L'app est réservée aux majeurs et se lit entre amis. On ne filtre donc ni
-- les gros mots, ni la vulgarité, ni l'humour douteux : ce serait à la fois
-- pénible et hors sujet. Le filtre ne vise que ce qu'aucun avis sur une
-- canette n'a de raison de contenir — les insultes racistes et homophobes,
-- et rien d'autre.
--
-- Le reste passe, et c'est le système de signalement qui prend le relais.
-- C'est le modèle des grandes plateformes : publier librement, modérer sur
-- signalement. Un filtre serré produirait surtout des faux positifs et
-- donnerait l'impression d'une app qui surveille ses utilisateurs.
--
-- POURQUOI LA LISTE VIT DANS LA BASE, ET PAS DANS LE DÉPÔT
--
-- Le dépôt est public. Y committer une liste d'insultes serait à la fois
-- désagréable à lire pour qui parcourt le projet, et contre-productif :
-- la liste serait consultable par tout le monde, donc contournable en un
-- coup d'œil. Dans la base, elle n'est lisible que par un administrateur,
-- et s'enrichit sans passer par une migration.
--
-- POURQUOI UN DÉCLENCHEUR ET PAS UN CONTRÔLE DANS LE NAVIGATEUR
--
-- Un filtre côté navigateur se contourne en appelant l'API directement,
-- et publierait la liste par la même occasion. Ici le refus vient de
-- PostgreSQL : il vaut quel que soit le chemin emprunté.
-- ============================================================

create table if not exists mots_bloques (
  mot        text primary key,
  ajoute_le  timestamptz not null default now()
);

alter table mots_bloques enable row level security;

-- personne ne lit cette liste à part un administrateur : une liste
-- consultable est une liste contournable
drop policy if exists mb_admin on mots_bloques;
create policy mb_admin on mots_bloques for all to authenticated
  using (is_admin()) with check (is_admin());


-- ------------------------------------------------------------
-- Le contrôle.
--
-- On normalise avant de comparer — minuscules, accents retirés — pour que
-- « CONNARD » et « connard » soient traités pareil. On ne cherche pas à
-- déjouer les contournements élaborés : le mot doit apparaître en entier,
-- entre deux frontières de mot. Chercher des sous-chaînes attraperait des
-- innocents, et c'est exactement le faux positif qu'on veut éviter.
-- ------------------------------------------------------------
create or replace function moderer_texte() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  nettoye text;
  trouve  text;
begin
  nettoye := lower(coalesce(new.body, ''));
  nettoye := translate(nettoye,
    'àâäáãåçéèêëíìîïñóòôöõúùûüýÿœæ',
    'aaaaaaceeeeiiiinooooouuuuyyea');

  select mot into trouve
    from mots_bloques
   where nettoye ~ ('\m' || mot || '\M')
   limit 1;

  if trouve is not null then
    -- le mot fautif n'est PAS renvoyé : ce serait confirmer à l'auteur
    -- quel terme figure dans la liste, donc l'aider à la cartographier
    raise exception 'moderation'
      using hint = 'Ce message contient un terme que l''application refuse.';
  end if;

  return new;
end $$;

drop trigger if exists reviews_moderation on reviews;
create trigger reviews_moderation
  before insert or update of body on reviews
  for each row execute function moderer_texte();

drop trigger if exists replies_moderation on replies;
create trigger replies_moderation
  before insert or update of body on replies
  for each row execute function moderer_texte();


-- ------------------------------------------------------------
-- Amorce.
--
-- Volontairement minuscule : seulement des insultes racistes et homophobes
-- sans usage légitime possible dans un avis sur une bière. Pas un mot de
-- vulgarité ordinaire — « putain de bonne bière » doit passer, et passe.
--
-- À enrichir depuis l'écran d'administration au fil de ce que tu constates.
-- Les termes sont normalisés comme le texte contrôlé : minuscules, sans
-- accent, et interprétés comme des expressions régulières — d'où le « e? »
-- qui couvre le féminin sans dupliquer les entrées.
-- ------------------------------------------------------------
insert into mots_bloques (mot) values
  ('negre'), ('negresse'), ('bougnoule'), ('bicot'),
  ('youpin'), ('youpine'), ('pede'), ('tarlouze'), ('tapette'),
  ('sale juif'), ('sale arabe'), ('sale noir')
on conflict (mot) do nothing;


-- ------------------------------------------------------------
-- Contrôle — les deux déclencheurs, et la taille de la liste.
-- ------------------------------------------------------------
select 'déclencheurs posés' as quoi,
       (select count(*)::text from pg_trigger
        where tgname in ('reviews_moderation','replies_moderation')) as etat
union all
select 'termes dans la liste',
       (select count(*)::text from mots_bloques);
