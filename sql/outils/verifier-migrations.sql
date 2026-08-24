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
)
select ordre,
       quoi,
       case when ok then '✅ OK' else '❌ MANQUE' end as etat,
       case when ok then '' else fichier end as a_lancer
from controles
order by ordre;
