-- ============================================================
-- QUALITÉ DU CATALOGUE — de quoi arrêter de citer 133/318 de mémoire.
--
-- Ne modifie RIEN. Les blocs se lancent d'un coup ; l'éditeur SQL de
-- Supabase n'affichera que le dernier, donc les lancer un par un pour
-- tout voir (piège documenté en PROJET.md §8).
--
-- Écrit le 26 août 2026, parce que le chiffre « 42 % des fiches n'ont
-- aucun style » circulait dans PROJET.md, dans index.html et dans une
-- conversation, sans que rien ne permette de le revérifier.
-- ============================================================


-- ---- 1. La couverture du style, le chiffre qui pilote tout ----
-- « Non précisé » et NULL veulent dire la même chose : on ne sait pas.
select
  count(*)                                                    as fiches,
  count(*) filter (where style is not null
                     and style <> 'Non précisé')              as avec_style,
  round(100.0 * count(*) filter (where style is not null
                                   and style <> 'Non précisé')
        / nullif(count(*), 0))                                as pct_avec_style
from beers
where status = 'approved';


-- ---- 2. La couverture par FAMILLE — le vrai critère produit ----
-- C'est ce que voit quelqu'un qui choisit « brunes » au premier lancement.
-- La logique reproduit MOTIFS_FAMILLE d'index.html : le style d'abord,
-- le nom en repli. Si ce bloc et l'app divergent un jour, c'est l'app
-- qui fait foi — elle est la seule à s'afficher.
with classe as (
  select
    name,
    case
      when coalesce(style, '') || ' ' || name ~* '\yn?e?ipa\y|\ypale\s*ale\y|\ysour\y|\ygose\y|acidul'
        then 'ipa'
      when coalesce(style, '') || ' ' || name ~* '\ybrunes?\y|\ystout\y|\yporter\y|\yambr[ée]e?\y|\ytriple\y|\ydouble\y|\ybrown\y|\ydark\y|\ybock\y|\ynoire?\y'
        then 'brunes'
      when coalesce(style, '') || ' ' || name ~* '\yblondes?\y|\yblanche\y|\ypils(e?n(er)?)?\y|\ylager\y|\ywit\y|\yweiss\y|\yhell(es)?\y|\yradler\y|sans\s*alcool|\y0[.,]0\y'
        then 'blondes'
      else null
    end as famille
  from beers
  where status = 'approved'
)
select coalesce(famille, '— aucune famille') as famille,
       count(*) as canettes,
       round(100.0 * count(*) / sum(count(*)) over ()) as pct
from classe
group by famille
order by canettes desc;


-- ---- 3. Les intrus ----
-- PROJET.md en cite deux : « GT-Mobility - Tankstelle, KFZ-Service » (une
-- station-service) et « BTE 50CL DESPERADOS » (BTE = bouteille). Ce bloc
-- les cherche par motif plutôt que par nom, pour attraper les suivants.
-- À traiter depuis l'écran de modération, jamais en SQL direct.
select name, brewery, volume_cl, status,
       case
         when name ~* '\y(bte|btl)\y'                    then 'nom = bouteille'
         when name ~* 'tankstelle|service|station|kfz'   then 'pas une bière'
         when brewery ~* 'tankstelle|service|kfz'        then 'brasserie douteuse'
         when volume_cl > 56                             then 'volume de bouteille'
         when name !~ '[a-zA-ZÀ-ÿ]{3}'                   then 'nom sans mot'
       end as motif
from beers
where name ~* '\y(bte|btl)\y'
   or name ~* 'tankstelle|service|station|kfz'
   or brewery ~* 'tankstelle|service|kfz'
   or volume_cl > 56
   or name !~ '[a-zA-ZÀ-ÿ]{3}'
order by status, name;


-- ---- 4. Les descriptions jumelles ----
-- Toutes générées à l'import, sur le même gabarit. PROJET.md : « trois
-- phrases sur les cinquante fiches les plus consultées valent mieux que
-- cinq cents fiches jumelles. » Ce bloc dit combien de fiches partagent
-- exactement le même squelette, une fois les variables retirées.
select count(*) as fiches,
       count(distinct regexp_replace(
         coalesce(description, ''),
         '[0-9]+([.,][0-9]+)?', 'N', 'g')) as gabarits_distincts
from beers
where status = 'approved';


-- ---- 5. Ce que l'enrichissement peut encore aller chercher ----
-- Les fiches sans style QUI ONT un code-barres : ce sont les seules que
-- enrich-styles.mjs peut interroger. Les autres ne bougeront jamais tout
-- seules — elles se complètent la canette en main.
select
  count(*) filter (where barcode is not null) as interrogeables,
  count(*) filter (where barcode is null)     as sans_code_barres,
  count(*)                                    as total_sans_style
from beers
where (style is null or style = 'Non précisé');


-- ---- 6. Les fiches en attente de validation ----
-- Le doute ne publie jamais : il atterrit ici. Une file qui grossit sans
-- être vidée est le vrai coût du principe.
select count(*) filter (where status = 'pending')  as a_valider,
       count(*) filter (where status = 'rejected') as rejetees,
       count(*) filter (where status = 'pending'
                          and image_url is null)   as a_valider_sans_photo
from beers;
