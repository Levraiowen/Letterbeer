-- ============================================================
-- VÉRIFICATION — ne modifie RIEN, tu peux le lancer sans risque.
--
-- Il te dit quelles migrations sont déjà passées et lesquelles
-- manquent encore. Lance-le, lis la colonne « état », et va
-- chercher les fichiers listés en face des lignes « MANQUE ».
-- ============================================================

with controles as (

  select 1 as ordre, 'Demi-étoiles' as quoi,
    exists (select 1 from information_schema.columns
            where table_schema='public' and table_name='logs'
              and column_name='rating' and data_type='numeric') as ok,
    'sql/04-demi-etoiles.sql' as fichier

  union all select 2, 'Calories et allergènes',
    exists (select 1 from information_schema.columns
            where table_schema='public' and table_name='beers' and column_name='kcal_100ml'),
    'sql/05-nutrition.sql'

  union all select 3, 'Suppression de compte',
    exists (select 1 from pg_proc where proname='delete_my_account'),
    'sql/06-rgpd.sql'

  union all select 4, 'Prix anonymisables',
    exists (select 1 from information_schema.columns
            where table_schema='public' and table_name='prices'
              and column_name='user_id' and is_nullable='YES'),
    'sql/07-correctifs.sql'

  union all select 5, 'Une note par bière',
    exists (select 1 from pg_indexes
            where schemaname='public' and indexname='logs_one_rating_per_beer'),
    'sql/07-correctifs.sql'

  union all select 6, 'Modération et durcissement',
    exists (select 1 from information_schema.columns
            where table_schema='public' and table_name='profiles' and column_name='is_admin'),
    'sql/08-durcissement.sql'

  union all select 7, 'Table des articles',
    exists (select 1 from information_schema.tables
            where table_schema='public' and table_name='articles'),
    'sql/08-durcissement.sql'

  union all select 8, 'Brèves du Journal',
    exists (select 1 from articles where status='published'),
    'sql/09-journal.sql'

  union all select 9, 'Noter sans avoir bu',
    exists (select 1 from information_schema.columns
            where table_schema='public' and table_name='logs' and column_name='counted'),
    'sql/10-notes-sans-conso.sql'

  union all select 10, 'Liste d''envies',
    exists (select 1 from information_schema.tables
            where table_schema='public' and table_name='wishlist'),
    'sql/11-ecrans-compte.sql'

  union all select 11, 'Contenant des bières',
    exists (select 1 from information_schema.columns
            where table_schema='public' and table_name='beers' and column_name='container'),
    'sql/12-contenant.sql'

  union all select 12, 'Tu es administrateur',
    exists (select 1 from profiles where is_admin),
    'sql/14-correctif-admin.sql'

  union all select 13, 'Goûts et premier lancement',
    exists (select 1 from information_schema.columns
            where table_schema='public' and table_name='profiles' and column_name='onboarded'),
    'sql/15-preferences.sql'

  union all select 14, 'Effacer sa propre réponse',
    exists (select 1 from pg_policies
            where schemaname='public' and tablename='replies' and policyname='y_delete'),
    'sql/16-reponses.sql'

  union all select 15, 'Stockage : dossier par personne',
    exists (select 1 from storage.buckets
            where id='avatars' and file_size_limit is not null),
    'sql/17-durcissement-stockage.sql'

  -- C'est ce contrôle-là qui manquait : sans lui, rien ne disait que la
  -- migration 18 n'était passée qu'à moitié.
  union all select 16, 'Relevés de prix figés',
    exists (select 1 from pg_trigger where tgname='prices_figer'),
    'sql/18-durcissement-ecritures.sql'

  union all select 17, 'Colonnes privées (bofs, is_admin, age_ok)',
    exists (select 1 from pg_proc where proname='mes_bofs'),
    'sql/19-colonnes-privees.sql'

  union all select 18, 'Compteurs d''avis figés',
    exists (select 1 from pg_trigger where tgname='reviews_figer'),
    'sql/20-correctifs-audit.sql'

  union all select 19, 'expire_prices refermée',
    not has_function_privilege('anon', 'expire_prices()', 'execute'),
    'sql/20-correctifs-audit.sql'

  union all select 20, 'Stockage non énumérable sans compte',
    not exists (select 1 from pg_policies
                where schemaname='storage' and tablename='objects'
                  and policyname in ('read_avatars','read_beers')
                  and roles::text like '%public%'),
    'sql/20-correctifs-audit.sql'

  union all select 21, 'Pseudo gardé jusqu''à 20 signes',
    exists (select 1 from pg_proc
            where proname='handle_new_user' and prosrc like '%left(base_handle, 20)%'),
    'sql/21-pseudo-non-tronque.sql'

  union all select 22, 'Bio du profil',
    exists (select 1 from information_schema.column_privileges
            where grantee='authenticated' and privilege_type='SELECT'
              and table_name='profiles' and column_name='bio'),
    'sql/23-bio.sql'
)
select ordre,
       quoi,
       case when ok then '✅ OK' else '❌ MANQUE' end as etat,
       case when ok then '' else fichier end as a_lancer
from controles
order by ordre;
