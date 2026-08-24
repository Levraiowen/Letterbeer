-- ============================================================
-- BLOC 2 / 2 — à coller et Run SEUL, dans une requête à part
-- (une fois que supabase-storage-policies.sql a tourné sans erreur)
-- Nettoyage des bières importées d'Open Food Facts
-- ============================================================

-- 0) Retire complètement les fiches "pack" ("6x25cl", "6X25CL"…).
--    Leur volume_cl est souvent celui du pack entier (ex: 150 pour
--    un 6x25cl), pas celui d'une canette — la donnée est fausse en
--    plus du nom sale, donc autant supprimer que corriger à moitié.
delete from beers where name ~* '\d+\s*[x×]\s*\d+([.,]\d+)?\s*(cl|ml)';

-- 1) Brasserie qui n'est en fait que le nom du produit recopié
update beers set brewery = 'Inconnue' where lower(brewery) = lower(name);

-- 2) volume simple : "33cl", "25 cl", "50CL"
update beers set name = trim(regexp_replace(name, '\s*\d+([.,]\d+)?\s*(cl|ml)\b', '', 'gi'));

-- 3) degré en toutes lettres ou avec "°" : "6.5 DEGRE ALCOOL", "8°"
update beers set name = trim(regexp_replace(name, '\s*\d+([.,]\d+)?\s*(°|degre|degré)\s*(alcool)?', '', 'gi'));

-- 4) degré en "%", collé à un marqueur explicite : "8%V", "9% vol."
update beers set name = trim(regexp_replace(name, '\s*\d+([.,]\d+)?\s*%\s*v(ol)?\.?\b', '', 'gi'));

-- 5) degré en "%" tout court : "6,8% Ch'ti Blonde", "4,9% Blc"
update beers set name = trim(regexp_replace(name, '\s*\d+([.,]\d+)?\s*%(?!\w)', '', 'gi'));

-- 6) retire le nom de la brasserie s'il est répété dans le nom
update beers set name = trim(replace(name, brewery, ''))
  where position(brewery in name) > 0 and name <> brewery;

-- 7) espaces multiples et ponctuation qui traîne en bout de chaîne
update beers set name = trim(regexp_replace(name, '\s{2,}', ' ', 'g'));
update beers set name = trim(regexp_replace(name, '[\s\-\.,]+$', ''));

-- 8) casse propre si le nom était tout en majuscules
update beers set name = initcap(lower(name)) where name = upper(name);

-- 9) supprime les fiches devenues trop pauvres après nettoyage
delete from beers where char_length(trim(name)) < 3;
