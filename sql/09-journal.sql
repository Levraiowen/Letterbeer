-- ============================================================
-- Contenu de l'onglet Journal — 10 brèves sur la canette.
-- À coller et Run SEUL, APRÈS supabase-durcissement.sql
-- (qui crée la table articles).
--
-- Chaque brève est un résumé écrit de zéro, jamais un extrait :
-- le titre, le lien et le chiffre clé renvoient au média, qui garde
-- le trafic. Aucune image n'est reprise — les photos de presse
-- appartiennent aux médias et aux agences.
-- ============================================================

-- le chiffre clé remplace la photo : c'est notre visuel, pas le leur
alter table articles add column if not exists stat       text;
alter table articles add column if not exists stat_label text;

-- on repart d'une base propre si le script est relancé
delete from articles where source in (
  'Mundolatas','Bière Actu','BeerMyself','La French Mousse',
  'Une Bière et Hop','Packaging Dive','Towards Packaging','BofA Global Research'
);

insert into articles (title, summary, url, source, color, stat, stat_label, status, published_at) values

('La canette accélère pendant que le reste stagne',
 'Les ventes en canette ont progressé de 5,8 % en volume en 2025, quand l''ensemble du marché des boissons se contentait de +0,3 %. La canette pèse désormais 27,7 % des volumes, et la bière y monte à 28,5 %. Sur la même période, le plastique recule de 3 %.',
 'https://mundolatas.com/fr/la-canette-accelere-sa-croissance-en-france-en-2025/',
 'Mundolatas', '#FF5A1F', '+5,8 %', 'volumes en canette, 2025',
 'published', '2026-07-30'),

('Une bière sur trois bientôt vendue en canette ?',
 'Les ventes de bière en canette ont gagné 4,6 % en 2025, nettement au-dessus de la croissance du marché. Longtemps collée à l''entrée de gamme, la canette est en train de se défaire de cette réputation.',
 'https://biere-actu.fr/une-biere-sur-trois-bientot-vendue-en-canette-en-france/',
 'Bière Actu', '#FFB020', '27,7 %', 'part de la canette, toutes boissons',
 'published', '2026-04-01'),

('Ninkasi passe au 44 cl et entre en grande surface',
 'Le lyonnais sort deux canettes de 44 cl : une Triple à 8,4° et une Rosée pêche-hibiscus à 4°, autour de 2,85 €. Sa Blonde, meilleure pilsner de France en 2024, arrive pour la première fois en grande distribution. Le format 44-50 cl progresse de 4,7 % sur l''année.',
 'https://biere-actu.fr/en-2026-ninkasi-lance-trois-nouveaux-formats/',
 'Bière Actu', '#C9E265', '44 cl', 'le nouveau format du lyonnais',
 'published', '2026-01-26'),

('Parallèle sort une IPA sans alcool 100 % française',
 'La brasserie de Floirac passe à la canette avec « Excuse my French », une IPA sans alcool en 33 cl. La recette n''utilise que des ingrédients français : houblon Sorachi Ace du Lot-et-Garonne, feuille de figuier corse, verjus de Dordogne.',
 'https://biere-actu.fr/la-brasserie-parallele-lance-sa-premiere-canette/',
 'Bière Actu', '#9FD8C0', '0,0°', 'une IPA sans alcool, entièrement française',
 'published', '2026-04-20'),

('Quand la canette devient un support d''exposition',
 'Retour sur la collaboration entre la brasserie Parallèle et Jibé, street artist bordelais dont les personnages naissent des bonshommes de passage piéton. La canette y est traitée comme une œuvre, dévoilée pendant quatre jours de vernissage à la galerie Art''Gentiers plutôt qu''en lancement produit.',
 'https://www.beer-myself.com/articles/parallele-jibe',
 'BeerMyself', '#FF5D8F', '4 jours', 'de vernissage, pas un lancement',
 'published', '2026-05-21'),

('Les styles à suivre en 2026',
 'IPA fruitées et NEIPA douces continuent de dominer, aux côtés d''un retour des lagers houblonnées et des bières vieillies en fût. Côté usages, 74 % des bars constataient déjà une demande croissante de sans-alcool, et une bière sur quatre vendue en France l''est en canette.',
 'https://lafrenchmousse.fr/actualite/les-tendances-biere-a-suivre-en-2026-ipa-fruitee-neipa-douce/',
 'La French Mousse', '#7FD1D9', '74 %', 'des bars voient grimper le sans-alcool',
 'published', '2026-01-21'),

('Pourquoi la canette protège mieux ta bière',
 'Quatre arguments : une opacité totale qui met la bière à l''abri de la lumière, un recyclage plus rapide que celui du verre, un refroidissement bien plus véloce, et une surface d''expression graphique plus généreuse. Le fameux goût de métal y est présenté comme une idée reçue.',
 'https://unebiereethop.com/la-biere-en-canette/',
 'Une Bière et Hop', '#B07A4F', '100 %', 'opaque : zéro lumière sur la bière',
 'published', null),

('Aux États-Unis, l''aluminium commence à plafonner',
 'L''aluminium représente 78 % des volumes de bière artisanale conditionnée en 2025, contre 69 % en 2022. Mais la bascule ralentit : l''économiste de la Brewers Association ne table plus que sur un à deux points supplémentaires. Le Rhode Island culmine à 92 %, le Mississippi reste sous les 58 %.',
 'https://www.packagingdive.com/news/craft-beer-packaging-trends-aluminum-glass/814339/',
 'Packaging Dive', '#5FC9E8', '78 %', 'de la bière artisanale conditionnée, USA',
 'published', '2026-03-11'),

('Le marché mondial de la canette à bière',
 'Estimé à 13,85 milliards de dollars en 2025, le marché est projeté à 20,76 milliards en 2035, soit 4,13 % de croissance annuelle. Le format 330 ml reste de loin le plus vendu, et l''Asie-Pacifique domine le volume.',
 'https://www.towardspackaging.com/insights/beer-cans-market-sizing',
 'Towards Packaging', '#8FD14F', '20,8 Md$', 'de marché projeté en 2035',
 'published', '2026-06-24'),

('La canette, format le mieux placé pour 2026',
 'Pour BofA, environ la moitié des nouveaux lancements de boissons se font en canette, et la Coupe du monde aux États-Unis devrait doper les volumes. Une nuance qui nous concerne directement : la bière traditionnelle et les hard seltzers, eux, reculent.',
 'https://business.bofa.com/en-us/content/canned-beverages-george-staphos.html',
 'BofA Global Research', '#F0C97A', '1 sur 2', 'des nouveaux lancements de boissons',
 'published', '2026-01-16');
