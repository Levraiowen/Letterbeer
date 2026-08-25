-- ============================================================
-- Migration 20 — cinq correctifs relevés à l'audit
-- À coller et Run SEUL dans le SQL Editor.
--
-- Aucune fonctionnalité ne change : ce qui marchait continue de marcher.
-- On referme des marges de manœuvre dont personne ne se sert.
--
-- ⚠️ Ce fichier se passe en DEUX temps. L'éditeur SQL exécute tout le
--    contenu collé comme un seul lot et n'affiche que le résultat de la
--    dernière instruction : le contrôle préalable serait donc invisible
--    s'il partait avec le reste. Colle le BLOC 0 seul, lis-le, puis
--    colle le BLOC 1.
-- ============================================================


-- ============================================================
-- BLOC 0 — contrôle préalable. À COLLER ET RUN SEUL, EN PREMIER.
--          Ne modifie rien.
--
-- Le point 3 du bloc suivant étend is_adult() aux écritures qui
-- l'avaient oublié. Si cette requête renvoie autre chose que 0, les
-- comptes concernés ne pourront plus répondre, relever un prix ni
-- réagir — mais ils ne pouvaient DÉJÀ ni noter ni écrire d'avis, la
-- migration 08 l'exigeant depuis longtemps sur logs et reviews. Un
-- compte créé par l'app a toujours age_ok = true, donc 0 est attendu.
-- ============================================================

select count(*) as comptes_sans_majorite_declaree
from profiles where not age_ok;


-- ============================================================
-- BLOC 1 — la migration. À coller et Run une fois le bloc 0 lu.
-- ============================================================


-- ------------------------------------------------------------
-- 1. expire_prices() était appelable SANS ÊTRE CONNECTÉ
--
-- La migration 08 avait révoqué public_stats et all_public_stats, la 06
-- delete_my_account. Celle-ci a été oubliée. PostgreSQL accorde EXECUTE
-- à PUBLIC par défaut sur toute nouvelle fonction : elle était donc
-- exposée en POST /rest/v1/rpc/expire_prices, avec la clé anon, qui est
-- publique par conception. N'importe qui pouvait déclencher un UPDATE de
-- masse sur la table des prix, en boucle.
--
-- Personne ne l'appelle depuis le navigateur : elle est faite pour un
-- cron, qui tourne en tant que postgres et n'a pas besoin de ce droit.
-- ------------------------------------------------------------
revoke all on function expire_prices() from public, anon, authenticated;


-- ------------------------------------------------------------
-- 2. Les compteurs d'un avis étaient modifiables par son auteur
--
-- La policy r_update laisse l'auteur modifier SA ligne — le filtrage par
-- colonne n'existant pas en RLS, cela incluait cheers_count. Un update
-- direct à 9999 plaçait l'avis en tête du classement « chauds ».
--
-- Même remède que pour prices (migration 18) et profiles (14) : un
-- déclencheur qui remet en place ce que le navigateur n'a pas à toucher.
--
-- La subtilité est la profondeur de déclencheur. Les compteurs sont
-- légitimement écrits par bump_review_counts(), lui-même un déclencheur
-- posé sur reactions. Tester auth.uid() comme ailleurs annulerait cette
-- écriture-là et casserait les trinques : bump_review_counts s'exécute
-- avec la session de celui qui réagit. pg_trigger_depth() distingue les
-- deux sans ambiguïté — 1 pour un update reçu de l'API, 2 pour un update
-- émis depuis un autre déclencheur.
-- ------------------------------------------------------------
create or replace function figer_compteurs_avis() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- écriture venue d'un autre déclencheur (bump_review_counts) : on laisse
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  -- écriture reçue de l'API : seuls la note, le cœur et le texte bougent
  new.id           := old.id;
  new.user_id      := old.user_id;
  new.beer_id      := old.beer_id;
  new.cheers_count := old.cheers_count;
  new.bofs_count   := old.bofs_count;
  new.created_at   := old.created_at;
  return new;
end $$;

drop trigger if exists reviews_figer on reviews;
create trigger reviews_figer
  before update on reviews for each row
  execute function figer_compteurs_avis();


-- ------------------------------------------------------------
-- 3. La majorité déclarée n'était exigée que sur deux tables
--
-- La migration 08 l'a posée sur logs et reviews, et s'est arrêtée là.
-- Répondre, relever un prix, réagir ou proposer une fiche n'en demandait
-- rien. On aligne les quatre autres.
-- ------------------------------------------------------------
drop policy if exists y_write on replies;
create policy y_write on replies for insert to authenticated
  with check (user_id = auth.uid() and is_adult());

drop policy if exists pr_write on prices;
create policy pr_write on prices for insert to authenticated
  with check (user_id = auth.uid() and is_adult());

drop policy if exists x_own on reactions;
create policy x_own on reactions for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and is_adult());

drop policy if exists b_insert on beers;
create policy b_insert on beers for insert to authenticated
  with check (submitted_by = auth.uid() and status = 'pending' and is_adult());


-- ------------------------------------------------------------
-- 4. Le bucket avatars s'énumérait SANS COMPTE
--
-- La règle de lecture était « to public » : le rôle anon la satisfait,
-- donc l'appel list() répondait sans authentification. On récupérait
-- l'arborescence complète {identifiant}/{horodatage}.jpg — soit
-- l'identifiant de chaque membre ayant une photo, et toutes ses photos,
-- y compris celles qu'il avait cru remplacer.
--
-- L'app ne liste jamais que son propre dossier (nettoyage de la photo
-- précédente, et vidage du bucket avant suppression du compte) : on peut
-- donc refermer complètement sans rien casser.
--
-- ⚠️ L'AFFICHAGE DES PHOTOS N'EST PAS CONCERNÉ. Les deux buckets sont
--    publics : les images passent par /storage/v1/object/public/…, une
--    route qui ne consulte pas le RLS. C'est getPublicUrl() qui fabrique
--    ces adresses, et elles continuent de fonctionner à l'identique.
--    Si des avatars disparaissaient malgré tout, revenir en une ligne :
--      create policy "read_avatars" on storage.objects for select
--        to public using (bucket_id = 'avatars');
-- ------------------------------------------------------------
drop policy if exists "read_avatars" on storage.objects;
create policy "read_avatars" on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Le bucket beers n'est encore utilisé par rien, mais il s'énumérait de
-- la même façon. On le referme aux connectés ; le dossier par personne
-- est déjà imposé à l'écriture depuis la migration 17.
drop policy if exists "read_beers" on storage.objects;
create policy "read_beers" on storage.objects for select to authenticated
  using (bucket_id = 'beers');


-- ------------------------------------------------------------
-- 5. Un pseudo hors format faisait échouer toute l'inscription
--
-- Le déclencheur reprenait le pseudo des métadonnées sans en vérifier le
-- jeu de caractères. La contrainte profiles_handle_format (migration 11)
-- n'accepte que [a-z0-9_.] : une inscription passée directement par l'API
-- d'authentification, sans passer par l'app, échouait donc sur une erreur
-- base illisible — exactement le symptôme que la migration 08 cherchait à
-- supprimer pour les collisions de pseudo.
--
-- On normalise au lieu de refuser. Le reste du déclencheur est inchangé.
-- ------------------------------------------------------------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  base_handle  text;
  final_handle text;
  n int := 1;
begin
  base_handle := lower(coalesce(trim(new.raw_user_meta_data->>'handle'), ''));
  base_handle := regexp_replace(base_handle, '\s+', '_', 'g');
  base_handle := regexp_replace(base_handle, '[^a-z0-9_.]', '', 'g');

  -- trop court après nettoyage, ou vide au départ : on retombe sur
  -- l'identifiant, qui est de l'hexadécimal donc toujours valide
  if char_length(base_handle) < 3 then
    base_handle := 'buveur_' || substr(new.id::text, 1, 6);
  end if;

  base_handle  := left(base_handle, 16);
  final_handle := base_handle;

  while exists (select 1 from profiles where handle = final_handle) loop
    n := n + 1;
    final_handle := base_handle || '_' || n;
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
-- Contrôle, en une seule requête — c'est la dernière instruction du
-- lot, donc la seule dont l'éditeur affichera le résultat.
--
-- Attendu :
--   · quatre lignes « déclencheur » : prices_figer et profiles_freeze
--     (posés en 18 et 14), reactions_count (01) et reviews_figer (ici)
--   · expire_prices exécutable par anon        → false
--   · expire_prices exécutable par un connecté → false
--   · les six règles de storage, dont read_avatars et read_beers qui
--     ne doivent plus mentionner le rôle « public »
-- ------------------------------------------------------------
select 'déclencheur' as controle,
       tgname || ' sur ' || (select relname from pg_class where oid = tgrelid) as resultat
from pg_trigger
where tgname in ('prices_figer','profiles_freeze','reviews_figer','reactions_count')

union all
select 'expire_prices exécutable par anon',
       has_function_privilege('anon', 'expire_prices()', 'execute')::text

union all
select 'expire_prices exécutable par un connecté',
       has_function_privilege('authenticated', 'expire_prices()', 'execute')::text

union all
select 'règle storage · ' || policyname, cmd || ' pour ' || roles::text
from pg_policies
where schemaname = 'storage' and tablename = 'objects'

order by 1, 2;
