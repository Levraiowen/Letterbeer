-- ============================================================
-- Migration 33 — une fiche publiée est une canette PROUVÉE
--
-- ⚠️ DEUX BLOCS, À LANCER SÉPARÉMENT, avec une étape à la main entre les
--    deux. Ne pas tout coller d'un coup : le bloc 2 échouerait.
--
-- ⚠️ POUSSER index.html AVANT de lancer le bloc 2. L'ordre habituel du
--    projet, et ici il est structurant : le bloc 2 pose une contrainte que
--    l'ancien code de modération viole systématiquement.
--
--
-- CE QU'ON A TROUVÉ
--
-- Mesuré en base le 26 août 2026 : **14 fiches publiées avec container à
-- NULL**. Toutes portent la description « Contenant non confirmé par Open
-- Food Facts » — elles sont donc arrivées en 'pending' par l'import, puis
-- ont été validées à la main depuis l'écran de modération.
--
-- La cause est dans `Store.moderate()` (index.html) :
--
--     .update({ status: ok ? 'approved' : 'rejected' })
--
-- Il posait `status`, jamais `container`. Or valider une fiche, c'est
-- précisément trancher son contenant sur la photo : c'est la seule raison
-- d'être de cet écran. Le geste avait lieu, le verdict n'était écrit nulle
-- part.
--
-- Conséquence : l'invariant que défendent les migrations 12, 13 et 32 —
-- publiée donc canette prouvée — devenait un peu plus faux à chaque
-- modération. Rien ne cassait à l'écran, et c'est bien le problème. Aucune
-- des 14 n'a de volume suspect : c'est la PREUVE qui manque, pas
-- nécessairement la canette.
--
--
-- POURQUOI ON NE MET PAS SIMPLEMENT container = 'canette'
--
-- Parce que ce serait exactement l'erreur de la migration 31 : écrire un
-- contenant qu'on n'a pas vérifié, en supposant que ça ira. La règle du
-- projet est absolue — « ne jamais écrire container = 'canette' à la
-- main ». Le fait qu'un humain ait cliqué « valider » il y a deux jours
-- n'est pas une preuve consultable aujourd'hui.
--
-- Les 14 repassent donc en validation, avec leur photo. Le code corrigé
-- enregistrera le verdict cette fois. C'est deux minutes de clics, et
-- c'est le seul chemin honnête. Même raisonnement que la migration 32.
--
--
-- CE QUE ÇA COÛTE PENDANT L'OPÉRATION
--
-- La règle `b_read` ne rend une fiche non publiée qu'à son auteur et aux
-- administrateurs. Sur les 14, une seule porte un avis et une entrée de
-- journal (compté en agrégat, sans regarder qui). Son avis cessera donc
-- de s'afficher pour les autres, le temps de la revalidation.
--
-- Ça ne casse rien : `revHTML()` sort par `if(!b) return ''` — le cas est
-- déjà prévu et commenté dans index.html. L'avis n'est pas supprimé, il
-- redevient visible dès que la fiche est revalidée. Fais les deux blocs
-- dans la foulée et la fenêtre dure le temps de regarder 14 photos.
-- ============================================================


-- ------------------------------------------------------------
-- BLOC 1 — renvoyer les fiches sans preuve à la validation.
-- À lancer SEUL. Puis ouvrir « Fiches à valider » dans l'app et
-- trancher les 14 sur leur photo, avec le code corrigé.
-- ------------------------------------------------------------

update beers
   set status = 'pending'
 where status = 'approved'
   and container is null;

-- Contrôle : doit renvoyer 0 publiée sans contenant, et 14 à valider.
select
  count(*) filter (where status = 'approved' and container is null) as publiees_sans_preuve,
  count(*) filter (where status = 'pending')                        as a_valider
from beers;


-- ============================================================
-- ⏸  ARRÊT. Va valider les fiches dans l'app avant la suite.
--    Le bloc 2 échoue tant qu'il reste une publiée sans contenant —
--    c'est voulu, c'est son rôle de garde.
-- ============================================================


-- ------------------------------------------------------------
-- BLOC 2 — rendre l'invariant structurel.
--
-- Jusqu'ici « publiée donc canette » était une convention tenue par le
-- code d'import, et le code de modération l'a contournée pendant deux
-- jours sans que personne le voie. Une convention que rien ne vérifie
-- finit par être fausse : c'est la troisième fois sur ce même sujet
-- (migrations 12, 13, 32).
--
-- La base refuse désormais. Ce n'est plus rattrapable par oubli.
--
-- Note : la contrainte autorise container NULL tant que la fiche n'est
-- pas publiée — le doute a le droit d'exister, il n'a pas le droit
-- d'être publié.
--
--
-- ⚠️ LE COALESCE N'EST PAS DÉCORATIF — vérifié sur les données réelles.
--
-- La version évidente serait :
--
--     check (status <> 'approved' or container = 'canette')
--
-- Elle ne sert à RIEN. Sur une fiche publiée dont container vaut NULL,
-- `container = 'canette'` vaut NULL, donc `false or NULL` vaut NULL — et
-- un CHECK PostgreSQL **accepte** ce qui vaut NULL : il ne refuse que ce
-- qui vaut FALSE explicitement.
--
-- Mesuré sur la base le 26 août 2026, avant de poser quoi que ce soit :
-- l'expression naïve rend « indéterminé » sur les 14 fiches fautives et
-- n'en refuse aucune. La contrainte aurait été purement décorative, et
-- on aurait cru le problème réglé — le pire des deux mondes.
--
-- Avec coalesce, les mêmes 14 sont refusées. C'est cette version-là qui
-- est posée. Toute retouche de cette ligne doit refaire ce contrôle.
-- ------------------------------------------------------------

alter table beers
  add constraint beers_publiee_est_canette
  check (status <> 'approved' or coalesce(container, '') = 'canette');

comment on constraint beers_publiee_est_canette on beers is
  'Une fiche publiée est une canette prouvée. Le contenant se prouve sur '
  'les données d''emballage d''Open Food Facts ou sur la photo, jamais par '
  'le volume. Posée le 26 août 2026 après 14 fiches publiées sans preuve.';


-- Contrôle final — doit renvoyer 0 partout sauf la dernière colonne.
select
  count(*) filter (where status = 'approved' and container is null)         as publiees_sans_preuve,
  count(*) filter (where status = 'approved' and container <> 'canette')    as publiees_non_canettes,
  count(*) filter (where status = 'approved')                              as publiees_ok
from beers;
