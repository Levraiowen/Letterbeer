-- ============================================================
-- Migration 19 — refermer trois colonnes que tout le monde lisait
-- À coller et Run SEUL dans le SQL Editor.
--
-- Le RLS filtre des LIGNES, jamais des COLONNES. Trois données étaient
-- donc lisibles par n'importe quel compte connecté, d'une simple requête,
-- alors que le schéma et l'écran promettaient l'inverse :
--
--   reviews.bofs_count  « JAMAIS exposé sauf à l'auteur » dit le schéma,
--                       « personne d'autre ne le voit » dit l'écran.
--                       L'app masquait le compteur à l'affichage, mais
--                       select('*') le rapportait pour tous les avis.
--   profiles.is_admin   désignait le compte administrateur à tout le
--                       monde — donc lequel attaquer.
--   profiles.age_ok     n'a jamais eu de raison de sortir.
--
-- Qui a mis un « bof » restait bien protégé : la table reactions est
-- correctement cloisonnée. C'est l'agrégat qui fuyait.
--
-- Le seul mécanisme qui filtre par colonne est le droit SQL. On retire
-- donc le SELECT de table, et on le rend colonne par colonne.
--
-- ⚠️ CONSÉQUENCE À RETENIR : une colonne ajoutée plus tard à profiles ou
--    à reviews devra être ajoutée au grant ci-dessous ET à COL_PROFILS /
--    COL_AVIS en tête du chargement dans index.html. Sans ça l'app ne la
--    verra pas. C'est le prix du filtrage par colonne en PostgreSQL.
--
-- ⚠️ ORDRE DE DÉPLOIEMENT : mettre le nouvel index.html en ligne AVANT
--    de passer cette migration.
--
--    En PostgreSQL, « select * » exige le droit de lire la table entière :
--    des droits par colonne ne suffisent pas. L'ancien index.html, qui
--    demande « * » sur profiles et reviews, tombe donc en erreur dès que
--    cette migration est passée. Le nouveau nomme ses colonnes, et toutes
--    existent déjà : il fonctionne avant comme après.
--
--    Ordre sans fenêtre de casse :
--      1. index.html + sw.js en ligne
--      2. cette migration
--      3. la migration 20
--
--    Entre 1 et 2, le seul écart est cosmétique : mes_bofs() n'existe pas
--    encore, donc le compteur de « bof » de tes propres avis affiche 0.
-- ============================================================


-- ------------------------------------------------------------
-- Les avis
-- ------------------------------------------------------------
revoke select on reviews from authenticated, anon;

grant select (id, user_id, beer_id, rating, liked, body, cheers_count, created_at)
  on reviews to authenticated;

-- L'auteur doit continuer de voir le compte de bofs de ses propres avis,
-- comme avant. La fonction ne répond que pour l'appelant : la colonne,
-- elle, ne sort plus de la base.
create or replace function mes_bofs()
returns table (review_id uuid, bofs int)
language sql security definer set search_path = public stable as $$
  select id, bofs_count from reviews where user_id = auth.uid();
$$;

revoke all on function mes_bofs() from public, anon;
grant execute on function mes_bofs() to authenticated;


-- ------------------------------------------------------------
-- Les profils
--
-- is_admin() existe depuis la migration 08 et ne répond que pour
-- l'appelant : l'app s'en sert désormais à la place de la colonne.
-- age_ok n'était lu par personne côté navigateur.
-- ------------------------------------------------------------
revoke select on profiles from authenticated, anon;

grant select (id, handle, avatar_url, city, private_stats, created_at,
              pref_familles, pref_degre, onboarded)
  on profiles to authenticated;


-- ------------------------------------------------------------
-- Ce qui continue de fonctionner, et pourquoi
--
--   · les mises à jour de profil : UPDATE est un droit distinct de
--     SELECT, il n'est pas touché. Le filtre .eq('id', …) ne demande
--     que la colonne id, qui reste lisible.
--   · les clés étrangères vers profiles(id) : PostgreSQL vérifie
--     l'intégrité référentielle sans passer par les droits de lecture.
--   · public_stats(), all_public_stats(), is_adult(), is_admin() et
--     delete_my_account() : toutes en « security definer », donc
--     exécutées avec les droits de leur propriétaire.
--   · le SQL Editor et les scripts d'import : ils passent par postgres
--     et service_role, dont on n'a rien retiré.
-- ------------------------------------------------------------


-- ------------------------------------------------------------
-- Contrôle, en une seule requête
--
-- L'éditeur SQL n'affiche que le résultat de la DERNIÈRE instruction du
-- lot : les contrôles sont donc réunis ici, pour tenir dans un seul
-- tableau de résultats.
--
-- Attendu, trois lignes :
--   colonnes lisibles sur profiles → 9 noms, sans age_ok ni is_admin
--   colonnes lisibles sur reviews  → 8 noms, sans bofs_count
--   mes_bofs() répond              → « N avis » (0 est normal si tu
--                                     n'en as pas encore écrit)
-- ------------------------------------------------------------
select 'colonnes lisibles sur ' || table_name as controle,
       string_agg(column_name, ', ' order by column_name) as resultat
from information_schema.column_privileges
where grantee = 'authenticated'
  and privilege_type = 'SELECT'
  and table_name in ('reviews','profiles')
group by table_name

union all
select 'mes_bofs() répond', count(*)::text || ' avis' from mes_bofs()

order by 1;
