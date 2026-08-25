# Letterbeer — état du projet

> **À lire en premier, et à tenir à jour.**
>
> Ce fichier existe pour qu'une conversation neuve — humaine ou IA — comprenne
> le projet sans avoir à relire 4 000 lignes de code et 25 migrations. Il n'est
> utile que s'il reste vrai.
>
> **Règle de mise à jour :** toute décision structurante, tout problème découvert,
> tout arbitrage produit se consigne ici **dans la foulée**, pas « plus tard ».
> Un point corrigé se déplace de « à traiter » vers « décidé et fait », avec sa
> raison. Un point abandonné se note comme abandonné, avec sa raison — sinon il
> sera reproposé dans six mois.
>
> Les sections sont **pondérées** : `🔴 structurant`, `🟠 important`,
> `🟡 secondaire`. La pondération dit où porter l'attention quand le temps manque.
>
> Dernière mise à jour : 25 août 2026 · app en `v4.4` · 25 migrations, toutes passées.

---

## 1. Le projet en trois phrases

**Letterbeer est un carnet de canettes.** On y note les bières qu'on boit, on
suit ses repères de consommation, on compare avec ses amis.

C'est un **projet personnel testé en petit comité** — une dizaine de personnes
— pas un produit lancé. Les données peuvent être réinitialisées.

Le fil directeur, qui explique la plupart des choix : **c'est une app liée à
l'alcool, en France.** Elle ne récompense donc jamais la quantité, met en avant
les jours sans, affiche la mention Évin, et compare la consommation aux repères
de Santé publique France. Ce n'est pas un vernis : c'est la contrainte qui
structure le produit, le design et le modèle économique.

→ [levraiowen.github.io/Letterbeer](https://levraiowen.github.io/Letterbeer/)
→ dépôt `Levraiowen/Letterbeer`, branche `main`, public

---

## 2. 🔴 Architecture — ce qu'il faut comprendre avant de toucher au code

| | |
|---|---|
| Interface | **un seul fichier `index.html`**, ~4 000 lignes, sans framework ni build |
| Données | Supabase — PostgreSQL, auth, stockage fichiers |
| Hébergement | GitHub Pages, dépôt public |
| Catalogue | Open Food Facts (ODbL), importé par script |
| Déploiement | `git push` — voir les pièges en §8 |

**Il n'y a pas de serveur applicatif.** Le navigateur parle directement à
Supabase avec la clé `anon`, qui est publique par conception et visible dans le
source. **Toute la sécurité repose donc sur les règles RLS de PostgreSQL.**

C'est le point le plus important du projet. Une conséquence directe : *masquer
une donnée à l'écran ne la protège pas*. Si l'app ne doit pas la montrer, c'est
la base qui doit refuser de la rendre.

### Les quatre règles non négociables

Elles sont aussi en tête d'`index.html` et dans le README. Elles viennent
chacune d'un vrai incident, pas d'un principe abstrait.

1. **Toute donnée affichée passe par `esc()`, `safeColor()` ou `safeUrl()`.**
   Le rendu se fait par `innerHTML`.

2. **Dans un attribut d'événement, `esc()` ne protège de rien.** Il produit
   `&#39;` pour une apostrophe, et le parseur HTML redécode les entités *avant*
   que le JavaScript soit compilé. On ne passe à un `onclick` qu'un
   identifiant ; le libellé se relit dans la fonction appelée.
   *Origine : une XSS stockée exploitable par le nom d'une bière, les fiches
   venant d'Open Food Facts qui est un wiki public.*

3. **Toute écriture vérifie l'erreur avant de toucher au cache local.** Et un
   refus RLS arrive sous forme de **zéro ligne affectée, pas d'erreur** : une
   suppression doit vérifier le nombre de lignes réellement retirées.

4. **Le RLS filtre des lignes, jamais des colonnes.** Une donnée réservée à son
   propriétaire passe par `grant select (…)` et une fonction `security definer`.
   Une colonne ajoutée à `profiles` ou `reviews` doit être déclarée **à la fois**
   dans le grant de la migration et dans `COL_PROFILS` / `COL_AVIS`.

### Le modèle de données, en bref

- `profiles` — pseudo, ville, avatar, bio, goûts, `is_admin`, `age_ok`
- `beers` — catalogue ; `status` ∈ pending / approved / rejected
- `logs` — **le journal, strictement privé.** Porte la note. `counted=false` =
  noté de mémoire, sans avoir bu
- `reviews` — avis publics, un par personne et par bière
- `reactions` — trinque / bof / passe, **privées, on ne voit que les siennes**
- `replies` — fil plat sous un avis
- `prices` — relevés en magasin, publics
- `follows`, `wishlist`, `beer_watchers`, `reports`, `articles`

---

## 3. 🟠 Ce que l'app fait — par ordre d'importance

**Le cœur.** Noter une canette de 0,5 à 5 étoiles, une seule note par bière et
par personne, modifiable. **Distinguer noter et boire** : on peut noter de
mémoire sans que la canette compte dans les volumes, unités, calories et
dépenses. C'est la fonctionnalité qui distingue Letterbeer d'un simple carnet.

**Les repères de consommation.** Volume, unités d'alcool, calories, dépenses,
comparés aux recommandations de Santé publique France (10 verres/semaine max).
Les formules sont vérifiées : 33 cl à 5 % = 1,30 unité, 139 kcal.

**Le récap de semaine.** Le seul mécanisme de retour régulier qui tienne sur un
produit lié à l'alcool : il met en avant **les jours sans**, jamais le nombre de
canettes. Partageable en image, sans pseudo ni lien.

**Le social.** Avis publics, réactions, fil de réponses à plat avec mentions,
abonnements, invitation par lien. Les « bof » sont privés et ne pèsent sur aucun
classement — les faire compter les rendrait déductibles.

**Les prix.** Relevés en magasin, péremption à 21 jours à l'affichage, bouton
« Toujours ce prix », liste de prix suivis.

**Le compte.** Export CSV du journal, suppression de compte (RGPD), stats
privées, goûts modifiables, bio.

**La modération.** Écran de validation des fiches proposées, écran de
signalements, édition et suppression de fiches — réservé aux administrateurs
**par la base**, pas par l'écran.

---

## 4. 🔴 Problèmes à traiter — par priorité

### Bloquants avant toute ouverture au-delà du cercle d'amis

- **Limitation du débit d'écriture** — rien n'empêche de publier mille avis en
  une minute. Sans effet entre amis, inacceptable en public.
- **En-têtes HTTP de sécurité** — `frame-ancestors`, `Strict-Transport-Security`,
  `X-Content-Type-Options` n'existent qu'en en-tête HTTP, que GitHub Pages ne
  permet pas de poser. La CSP en balise `meta` couvre le reste. Réglé par un
  hébergeur qui autorise les en-têtes, ou par la coque native.
- **Vérification d'âge** — déclaration sur l'honneur, gelée en base. Suffisant
  en privé ; à revoir si l'audience sort du cercle.
- **Rapports de plantage** — aucun moyen de savoir ce qui casse chez les autres.
  La sortie honnête est un bouton « Signaler un problème » qui n'envoie **que**
  le message écrit par l'utilisateur : la promesse « aucun traceur » doit tenir.

### Qualité du catalogue — le vrai frein aujourd'hui

- **42 % des fiches n'ont aucun style** (133 sur 318). Conséquence mesurée : le
  tri par famille du premier lancement ne couvre que 58 % du catalogue, et un
  profil « brunes + costaudes » n'a que **3 canettes** à proposer. La déduction
  par le nom (v3.9) ne récupère que 15 fiches — le reste s'appelle « Jupiler »,
  « Skoll », « Cerveza », qu'aucune règle ne peut classer honnêtement.
  **La seule vraie solution est d'enrichir les données**, pas d'améliorer
  l'heuristique.
- **Le catalogue contient des intrus** : `GT-Mobility - Tankstelle, KFZ-Service`
  (une station-service allemande), `BTE 50CL DESPERADOS` (« BTE » = bouteille).
  À traiter depuis l'écran de modération.
- **15 fiches affichent « Jupiler · Jupiler »** — la brasserie répète le nom.
  Corrigé à l'import pour l'avenir ; l'existant reste. Correction propre :
  masquer la brasserie quand elle répète le nom (touche 8 points d'affichage).
- **Descriptions toutes identiques**, générées à l'import. Trois phrases sur les
  cinquante fiches les plus consultées valent mieux que cinq cents fiches
  jumelles.

### Accessibilité — mesuré, pas supposé

- **`--dimmer` (#5C5C63) est à 2,98:1 sur le fond**, sous le seuil AA de
  4,5:1 et même sous celui du grand texte (3:1). Il sert aux libellés de
  section (« 7 derniers jours », « selon tes goûts ») et aux étoiles vides,
  **à 11 px**. Correctif chiffré, teinte bleutée conservée : `#78787F` donne
  4,51:1, `#808087` donne 5,04:1. `--dim`, `--text` et `--accent` passent tous.
  *Décision en attente : ça touche la direction artistique.*
- **Les sous-onglets « Bières / Avis / Journal » font 29 px de haut**, contre
  44 px recommandés. C'est la navigation la plus utilisée de l'app, au pouce.
  *Décision en attente, même raison.*

### Dette technique assumée

- **Fichiers orphelins dans le stockage** après suppression de compte —
  `delete_my_account` retire les lignes `storage.objects` mais pas les octets.
  Inatteignable depuis SQL.
- **`expire_prices()` dort** — la péremption des prix est calculée à
  l'affichage ; la fonction n'est branchée à aucun `pg_cron`. À brancher le jour
  où `pg_cron` sera posé pour les notifications, ou à supprimer.
- **`store-supabase.js`** — 361 lignes mortes, non référencées, **absentes du
  dépôt distant** mais présentes en local. Décision en attente.
- **Réponses imbriquées** — le fil est volontairement plat. À rediscuter
  seulement si des conversations de plus de vingt messages apparaissent.

---

## 5. 🟠 Le passage en vraie app

Le détail vit dans **[MIGRATION.md](MIGRATION.md)** — ne pas le dupliquer ici.
Ce qu'il faut en retenir :

**Avant le premier APK** : notifications (Web Push + Edge Function + `pg_cron`,
tout dans les offres gratuites ; les tables `beer_watchers` et `follows` sont
déjà alimentées), scan de code-barres, photo de sa propre canette.

**Outil** : Capacitor plutôt que Bubblewrap, pour l'accès caméra donc au scan.

**Le piège de calendrier**, à connaître très à l'avance : un compte développeur
personnel récent doit réunir **12 testeurs pendant 14 jours consécutifs** en test
fermé avant de pouvoir demander la production sur Google Play. Non contournable.
**D'où la consigne de viser 12 amis testeurs, pas 5.**

**iOS** : ~92 €/an et un Mac. À ne faire que sur demande réelle ; en attendant,
la PWA s'installe depuis Safari gratuitement.

---

## 6. 🟠 Mini business plan idéal

### La contrainte qui commande tout : la loi Évin

**C'est le point que personne ne voit venir et qui plafonne toutes les options.**
En France, la publicité pour les boissons alcoolisées est strictement encadrée :
support, contenu et forme du message sont limités par la loi, et toute
communication doit porter la mention sanitaire.

Conséquences concrètes, à ne pas découvrir trop tard :

- **L'affiliation vers des vendeurs d'alcool est une zone rouge.** C'est le
  réflexe monétisation n°1 d'une app de ce type, et c'est précisément celui qui
  expose le plus.
- **Vendre de l'espace publicitaire à des brasseries** revient à diffuser de la
  publicité pour l'alcool : même encadrement.
- **Le contenu éditorial** (l'onglet Journal) doit rester du résumé qui renvoie
  au média, jamais de la promotion.
- **Classification 18+** obligatoire sur les stores, et mention sanitaire
  partout où l'app est exposée.

**Traduction en une phrase : le modèle publicitaire classique est fermé.** Le
plan réaliste n'est donc pas « lever de l'audience puis monétiser », c'est
« couvrir ses coûts sans jamais dépendre de l'alcool comme annonceur ».

### Structure de coûts réelle

| Poste | Coût | Quand |
|---|---|---|
| GitHub Pages | 0 € | maintenant |
| Supabase, offre gratuite | 0 € | jusqu'à ~500 Mo de base, 1 Go de fichiers, 50 000 comptes |
| Nom de domaine | ~12 €/an | au moment de l'APK |
| Google Play, inscription | ~23 € une fois | APK |
| App Store | ~92 €/an | seulement si des iPhone le réclament |
| Supabase Pro | ~25 $/mois | **seulement** si l'offre gratuite casse |

**Le premier poste qui cassera l'offre gratuite est le stockage de fichiers**,
le jour où chacun envoie des photos de ses canettes — pas la base, pas l'auth.
`shrink()` (redimensionnement + effacement de l'EXIF) et la limite de 2 Mo par
fichier posée en migration 17 repoussent l'échéance.

### Le plan, par paliers

**Palier 0 — aujourd'hui. Coût : 0 €.** Une dizaine d'amis, hébergement gratuit.
*Objectif : que l'app soit agréable et juste. Rien d'autre.*

**Palier 1 — l'APK. Coût : ~35 € la première année.** 12 testeurs pendant
14 jours, domaine, inscription Google Play. *Objectif : franchir la barrière
Play, qui est administrative, pas technique.*

**Palier 2 — quelques centaines d'utilisateurs. Coût : toujours ~0 €/mois.**
L'offre gratuite Supabase tient largement. *Objectif : vérifier que l'app tient
sans toi — c'est là que la limitation de débit et les rapports de plantage
deviennent indispensables.*

**Palier 3 — si ça décolle vraiment.** Le seul moment où la question de l'argent
se pose. Options **classées par compatibilité avec Évin** :

1. **Soutien volontaire** (tip jar, « offre-moi une bière »). Zéro contrainte
   légale, zéro dette envers un annonceur, cohérent avec la promesse « aucun
   traceur ». **C'est l'option recommandée.**
2. **Fonctions payantes sans rapport avec l'alcool** — historique étendu,
   statistiques avancées, export enrichi, thèmes. On vend un outil, pas une
   boisson.
3. **Partenariats non alcoolisés** — verrerie, accessoires. Prudence : la
   frontière est mince et l'appréciation revient au juge.
4. **Publicité et affiliation alcool.** ❌ À écarter, sauf conseil juridique
   explicite.

### Ce que le projet ne doit pas devenir

À garder en tête à chaque arbitrage produit, parce que la pente est glissante :

- **Pas de classement qui récompense la quantité.** Déjà refusé une fois, dans
  le récap de semaine. Ça reste vrai partout.
- **Pas de notification qui pousse à consommer.** Les deux cas d'usage prévus —
  baisse de prix sur une bière suivie, avis d'un ami — sont volontairement
  passifs.
- **Pas de traceur.** L'écran À propos le promet. Cette promesse a déjà servi à
  trancher la conception des rapports de plantage.
- **Pas de revente de données.** Le journal est cloisonné par la base, pas par
  l'interface. C'est une garantie technique, pas une politique.

---

## 7. 🟡 Décisions déjà prises — ne pas les reproposer

Chacune a une raison. La rouvrir sans raison nouvelle fait perdre du temps.

- **Fil de réponses à plat**, avec mentions plutôt que niveaux. Imbriquer est
  illisible sur téléphone et n'apporte rien à l'échelle d'un groupe d'amis.
- **Les « bof » sont privés et hors classement.** Les faire peser les rendrait
  déductibles en observant les mouvements de la liste.
- **Une seule note par personne et par bière.** Les fois suivantes sont des
  « +1 » qui comptent dans les volumes, pas dans la moyenne.
- **Le prix laissé vide est estimé** au meilleur relevé communautaire. C'est
  voulu — pour avoir un ordre de grandeur — et l'interface le dit désormais.
- **La péremption des prix est calculée à l'affichage**, pas par un cron.
- **Le tri des avis diffère selon l'écran** : classement « chaud » dans l'onglet
  Avis (ce qui intéresse le groupe), ordre de publication chez les copains (ce
  qu'ils ont écrit depuis la dernière fois).
- **Le Top de l'année utilise une moyenne bayésienne** plus un bonus
  d'engagement plafonné à ~0,25 point. Une canette notée 5 par une personne ne
  doit pas devancer une 4,8 notée par douze.
- **« Cette semaine » a deux définitions assumées** : sept jours calendaires
  dans le récap (l'écran parle de jours), fenêtre glissante de 168 h ailleurs
  (c'est ce que calcule `all_public_stats`, et passer en jours calendaires y
  introduirait un décalage de fuseau serveur/téléphone).
- **La déduction de famille ne touche pas `beers.style`.** Le style reste la
  donnée d'Open Food Facts, jamais une supposition de notre part.

---

## 8. 🔴 Pièges connus — lire avant de déployer

- **Ordre de déploiement : `git push` d'abord, migrations Supabase ensuite.**
  Contre-intuitif. En PostgreSQL, `select *` exige le droit de lire la table
  entière : un ancien `index.html` tombe en erreur dès qu'une migration retire
  un droit de colonne. Le code récent nomme ses colonnes et fonctionne avant
  comme après. *Les migrations qui ajoutent une colonne ont un repli explicite
  pour que l'ordre reste indifférent — voir `chargerProfils()`.*
- **L'éditeur SQL de Supabase n'affiche que le résultat de la dernière
  instruction** d'un lot, et annule tout si une ligne échoue. Les migrations qui
  ont un contrôle préalable sont découpées en blocs à lancer séparément.
- **Après un déploiement, la première ouverture sert encore la version
  précédente.** Le document a été chargé avant la bascule du service worker. Un
  rechargement suffit, mais tes amis verront l'ancienne version une fois de plus.
  Penser à bumper `APP_VERSION` **et** `VERSION` dans `sw.js`.
- **GitHub Pages met 2 à 5 minutes** à publier, avec un cache CDN par-dessus.
- **`is_admin` ne se donne que depuis le SQL Editor**, où `auth.uid()` vaut
  `NULL`. Le déclencheur `profiles_freeze` bloque toute promotion venue du
  navigateur — c'est voulu, et c'est ce qui rend la modération incassable.
- **`sql/outils/verifier-migrations.sql`** dit à tout moment quelles migrations
  sont passées. Il ne modifie rien. **Le lancer avant de conclure qu'un bug est
  dans le code** : il a déjà évité une fausse piste.

---

## 9. 🟡 Comment travailler sur ce projet

- **Ne jamais créer d'avis ni de relevé de prix de test** sur la base réelle
  sans les retirer : ils sont publics et vus par de vraies personnes. Le journal,
  les réactions, la liste d'envies sont privés et réversibles — c'est là qu'on
  teste.
- **Vérifier avant d'affirmer.** Plusieurs « bugs » de ce projet se sont révélés
  être des artefacts de mesure : un rendu mobile jugé cassé n'était qu'une
  capture en DPR 2, des bières « sans degré » étaient des sans-alcool. Mesurer
  la géométrie, pas la capture d'écran.
- **Le contrôle de syntaxe** se fait en extrayant le `<script>` d'`index.html`
  et en passant `node --check` dessus.
- **Une correction dans l'app ne dispense pas de la migration**, et
  réciproquement. Les deux moitiés vont ensemble.

---

## 10. Journal des sessions

*À compléter à chaque session — une ligne par sujet traité, la raison compte
plus que le détail.*

**25 août 2026 — audit de sécurité et campagne de correction (v3.6 → v4.3)**

- XSS stockée par le nom d'une bière dans un attribut `onclick` : corrigée,
  règle n°2 ajoutée au projet.
- Trois colonnes lisibles par tous (`bofs_count`, `is_admin`, `age_ok`) :
  refermées par droits colonne par colonne (migration 19).
- Bucket `avatars` énumérable sans compte, `expire_prices()` appelable sans
  être connecté, compteurs d'avis falsifiables : corrigés (migration 20).
- « -1 jour sans alcool sur sept » dans le récap — reproduit en conditions
  réelles, corrigé en jours calendaires.
- Suppression d'un avis : n'existait pas alors que la base l'autorisait
  depuis le premier schéma.
- « Connexion impossible » au lancement : régression introduite par l'audit
  lui-même — `hydrate()` rendu strict transformait un échec passager en mur.
  Réessais avec rafraîchissement de session.
- Modération : écran de signalements, édition et suppression de fiches, avec
  garantie base qu'une fiche ayant un historique ne peut pas être effacée.
- Goûts rendus modifiables et visibles ; bio de 250 signes.
- Recherche insensible aux accents et aux apostrophes.
- Nettoyage des noms porté de la migration 03 vers `import-beers.mjs`, là où
  il aurait dû être : une migration ne tourne qu'une fois, un import revient.

**25 août 2026 — test complet en session authentifiée (v4.3 → v4.4)**

- Parcours vérifiés de bout en bout : note de mémoire, « +1 », liste d'envies,
  suivi de prix, bio, goûts, abonnement, avis, réponse, suppression, récap,
  image partagée, export CSV, filtres, tris, états vides. Aucune erreur
  console, aucun `undefined` à l'écran.
- **Confirmé en production** : le classement bayésien place « 8.6 IPA »
  (4,5 sur 2 notes) devant « 8.6 Originale » (5,0 sur 1 note) — c'était le
  but. « Populaires cette semaine » remonte 6 canettes sur une vraie fenêtre
  de 7 jours. Le récap affiche « 6 jours sans » sur 19→25 août.
- Formatage français terminé : l'en-tête de fiche et le récap gardaient des
  points décimaux. Accords au singulier corrigés (« 1 notes », « 1 brasseries »)
  — invisibles avec un jeu de données fourni, d'où un test sur un compte à
  exactement une note.
- Contraste et cibles tactiles mesurés, reportés ci-dessus, non corrigés :
  ils touchent la direction artistique.
