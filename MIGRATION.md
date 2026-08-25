# Passage en application

Liste des travaux à mener au moment de sortir du site web pour un APK, puis
pour les stores. **Tenue à jour au fil du développement** — ce qui est décidé
maintenant mais reporté atterrit ici, pour ne pas être redécouvert dans six
mois.

Dernière révision : 25 août 2026 (audit sécurité).

---

## Avant de fabriquer le premier APK

### Notifications
Tout le système reste à construire. Trois briques, toutes gratuites :

- **Web Push** — API standard, ni service tiers ni abonnement. Nécessite une
  paire de clés VAPID et une table d'abonnements.
- **Edge Function Supabase** pour l'envoi. Offre gratuite : 500 000
  invocations par mois, très au-delà du besoin.
- **`pg_cron`** pour la vérification quotidienne. L'extension est disponible
  sur l'offre gratuite.

Deux cas d'usage déjà identifiés :
1. **Baisse de prix** sur une bière suivie — la table `beer_watchers` existe
   et est déjà alimentée par le bouton « Suivre le prix ».
2. **Avis d'un ami** — la table `follows` fournit déjà la liste des personnes
   à notifier.

> En attendant, l'interface ne promet **aucune** alerte : elle propose une
> liste de prix suivis, consultable depuis le Compte. Ne pas réintroduire de
> formulation qui laisserait croire à une notification.

**Limite iOS** : les notifications web n'arrivent que si la PWA est installée
sur l'écran d'accueil, à partir d'iOS 16.4. Dans une app Capacitor, on passe
par les notifications natives.

### Scan de code-barres
Faisable dès le web via `BarcodeDetector`, disponible sur Chrome Android mais
absent de Safari. En Capacitor, un module natif couvre les deux plateformes.

La logique de recherche `code-barres → table beers` est identique dans les deux
cas : seule la capture caméra change.

### Photo de sa propre canette
Le bucket `beers` est créé et ses règles posées, mais rien ne l'utilise.

- N'autoriser l'envoi **que sur une fiche en cours de proposition**, jamais sur
  une fiche déjà validée : sinon l'image d'une bière publique pourrait être
  remplacée après coup, en contournant la modération.
- Réutiliser `shrink()`, la fonction des avatars : elle redimensionne et
  surtout **efface les métadonnées EXIF**, donc les coordonnées GPS.
- Aucune modération supplémentaire à écrire : une fiche proposée est déjà
  `pending`, et l'écran de validation affiche les photos.

### Multi-devises
Tout est en euros et en centilitres, en dur. À reprendre seulement si l'app
sort de France.

---

## Fabrication de l'APK

| | |
|---|---|
| Outil recommandé | **Capacitor** — plus de travail que Bubblewrap, mais donne accès à l'appareil photo, donc au scan |
| Alternative rapide | **Bubblewrap** — emballe la PWA telle quelle, sans accès natif |
| Nom de domaine | ~12 €/an, simplifie la vérification et fait plus sérieux qu'une adresse en `github.io` |
| Prérequis | Le service worker est en place depuis la v3.3 |

---

## Publication sur Google Play

- **~23 €**, frais d'inscription unique, pas d'abonnement.
- **Classification 18+** à cause du contenu alcool.
- **Formulaire « sécurité des données »** et lien public vers la politique de
  confidentialité. L'écran À propos est derrière l'authentification : il en
  faudra une copie en page web ordinaire.
- **Suppression de compte accessible aussi depuis le web**, pas seulement dans
  l'app. Exigence Google depuis 2024. La fonction `delete_my_account` existe
  déjà, il manque la page publique qui l'appelle.

> **Le piège de calendrier** : un compte développeur personnel récent doit
> réunir **12 testeurs pendant 14 jours consécutifs** en test fermé avant de
> pouvoir demander la production. Non contournable. La phase de test entre
> amis peut compter — d'où la consigne de viser 12 personnes, pas 5.

---

## Publication sur l'App Store

- **~92 €/an**, seul poste réellement récurrent.
- Nécessite un **Mac** pour compiler et soumettre, ou un service de location.
- À ne faire que si les utilisateurs iPhone le réclament : en attendant, ils
  installent la PWA depuis Safari, gratuitement.

---

## Dette technique à solder au passage

- **Réponses imbriquées** — le fil est volontairement plat, avec des
  mentions plutôt que des niveaux. À rediscuter seulement si des
  conversations à plus de vingt messages apparaissent, ce qui est peu
  probable entre amis.

- **Péremption des prix** — `expire_prices()` existe mais n'est branchée à
  aucun `pg_cron`, et l'app ne lit jamais `prices.status` : la péremption est
  calculée à l'affichage, depuis `confirmed_at`. Le comportement visible est
  le bon, la fonction dort. À brancher le jour où `pg_cron` sera de toute
  façon posé pour les notifications, ou à supprimer.
- **Descriptions des bières** — toutes portent le même texte généré à
  l'import. Trois phrases écrites sur les cinquante fiches les plus consultées
  valent mieux que cinq cents fiches identiques.
- **Vérification d'âge** — déclaration sur l'honneur, gelée en base depuis la
  migration 08. Suffisant pour un usage privé ; à revoir si l'audience sort du
  cercle d'amis.
- **En-têtes HTTP de sécurité** — la politique de sécurité du contenu est
  posée en balise `meta`, ce qui couvre l'essentiel. Mais `frame-ancestors`,
  `Strict-Transport-Security` et `X-Content-Type-Options` n'existent qu'en
  en-tête HTTP, que GitHub Pages ne permet pas de définir. Un hébergeur qui
  autorise les en-têtes, ou la coque native, réglera ça.
- **Limitation du débit d'écriture** — rien n'empêche aujourd'hui de publier
  mille avis en une minute. Sans effet entre amis, à prévoir avant toute
  ouverture publique.
- **Empreinte de la bibliothèque** — la version de `supabase-js` est épinglée
  et son empreinte vérifiée. À recalculer à chaque montée de version, sinon
  le navigateur refusera de la charger.
- **Rapports de plantage** — aucun moyen de savoir ce qui casse chez les
  autres. La sortie honnête est un bouton « Signaler un problème » qui envoie
  **le message écrit par l'utilisateur**, et rien d'autre : la promesse
  « aucun traceur » de l'écran À propos doit tenir.

---

## Décidé et déjà fait

Pour mémoire, afin de ne pas le refaire :

- Service worker et fonctionnement hors ligne — v3.3
- Manifeste, icônes et installation sur l'écran d'accueil
- Mention sanitaire loi Évin sur les écrans exposés
- Suppression de compte et export des données dans l'app
- Écran de modération des fiches, avec photos
- Invitation d'un ami par lien, sans envoi d'e-mail
- Premier lancement en deux questions, avec tri du catalogue
- Récap de semaine partageable en image
- Conversation sous un avis : fil à plat, mentions, suppression de sa
  propre réponse

### Audit du 25 août 2026 — corrigé

- **XSS stocké par le nom de bière.** Le libellé du bouton « Signaler »
  transitait par l'attribut `onclick`, où `esc()` ne protège de rien : il
  produit `&#39;`, que le parseur HTML redécode avant que le JavaScript soit
  compilé. Toute bière au nom contenant une apostrophe cassait déjà le bouton
  en silence ; un nom fabriqué — et les fiches viennent d'Open Food Facts,
  un wiki public — exécutait ce qu'il voulait dans la session de qui cliquait.
  Les attributs d'événement ne reçoivent plus que des identifiants. Règle
  ajoutée en tête d'`index.html` et au README.
- **`bofs_count` et `is_admin` lisibles par tous** — masqués à l'écran, pas
  en base. Migration 19 : droits par colonne, plus `mes_bofs()`.
- **Bucket `avatars` énumérable sans compte**, et anciennes photos jamais
  effacées. Migration 20 pour la règle de lecture, `setPhoto()` fait le
  ménage de ses propres envois.
- **`expire_prices()` appelable sans être connecté** — oubliée par les
  révocations de la migration 08.
- **Compteurs d'avis falsifiables par leur auteur** — déclencheur de gel,
  sur le modèle de `prices_figer`, avec `pg_trigger_depth()` pour laisser
  passer l'écriture légitime de `bump_review_counts()`.
- **Pagination** — les onze requêtes de `hydrate()` sont paginées et triées
  sur une clé unique. Le plafond silencieux des mille lignes ne tronque plus
  ni le catalogue ni les prix.
- **Erreurs de chargement avalées** — `hydrate()` ne regardait aucune des
  onze erreurs : un écran vide sans explication remplaçait le catalogue.
- Majorité déclarée étendue aux quatre écritures qui l'avaient oubliée,
  pseudo normalisé à l'inscription, `emailRedirectTo` corrigé, N+1 de
  l'activité des copains supprimé.
