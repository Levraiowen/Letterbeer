# Letterbeer

**Le carnet de canettes.** Note les bières que tu bois, suis tes repères de
consommation, compare avec tes potes.

→ [levraiowen.github.io/Letterbeer](https://levraiowen.github.io/Letterbeer/)

Projet personnel, testé en petit comité. Les données peuvent être
réinitialisées sans préavis.

---

## Ce que ça fait

- **Noter une canette** de 0,5 à 5 étoiles, une seule note par bière et par
  personne, modifiable à tout moment.
- **Distinguer noter et boire.** On peut noter de mémoire sans que la canette
  compte dans les volumes, les unités d'alcool, les calories et les dépenses.
- **Suivre ses repères** : volume, unités, calories, dépenses, répartition des
  notes, styles préférés — le tout comparé aux recommandations de Santé
  publique France.
- **Lire et écrire des avis**, y réagir, y répondre.
- **Relever les prix** en magasin, avec péremption automatique à 21 jours.
- **Récupérer ou effacer ses données** depuis l'application, sans formulaire.

Le journal et les dépenses ne sortent jamais du compte de leur auteur, même
quand le profil est public. Ce cloisonnement est appliqué par la base, pas par
l'interface.

## Comment c'est fait

| | |
|---|---|
| Interface | un seul fichier HTML, sans framework ni étape de compilation |
| Données | Supabase — PostgreSQL, authentification, stockage de fichiers |
| Hébergement | GitHub Pages |
| Catalogue | [Open Food Facts](https://world.openfoodfacts.org/), sous licence ODbL |

Il n'y a pas de serveur applicatif. Le navigateur parle directement à Supabase
avec la clé publique `anon`, et **toute la sécurité repose sur les règles RLS**
définies dans [`sql/01-schema.sql`](sql/01-schema.sql). Une requête qui ne
devrait pas aboutir est refusée par la base, jamais seulement masquée à
l'écran.

### Les fichiers

```
index.html                  toute l'application — style, structure, logique
sw.js                       cache hors ligne de la coque et des photos
manifest.webmanifest        installation sur l'écran d'accueil
logo.svg, icon-*.png        la marque ; make-icons.py régénère les PNG

import-beers.mjs            importe les canettes depuis Open Food Facts
enrich-beers.mjs            complète calories et allergènes
make-icons.py               redessine les icônes d'application

sql/                        migrations, à passer dans l'ordre des numéros
sql/outils/                 requêtes de contrôle, ne modifient rien
```

## Installer une instance

**1. Créer le projet Supabase**, région Europe.

**2. Passer les migrations** dans le SQL Editor, **une par une, dans l'ordre
des numéros**. L'éditeur exécute tout le contenu collé comme un seul lot : si
une ligne échoue, l'ensemble est annulé sans rien appliquer.

```
sql/01-schema.sql              tables, vues, règles RLS, fonctions
sql/02-storage-policies.sql    droits sur les images
sql/03-nettoyage-noms.sql      dégrossit les noms importés
sql/04-demi-etoiles.sql        notes au demi-cran
sql/05-nutrition.sql           calories et allergènes
sql/06-rgpd.sql                suppression de compte
sql/07-correctifs.sql          une note par bière, prix anonymisables
sql/08-durcissement.sql        modération, majorité, accès aux fonctions
sql/09-journal.sql             contenu de l'onglet Journal
sql/10-notes-sans-conso.sql    noter sans compter la canette
sql/11-ecrans-compte.sql       liste d'envies, signalements
sql/12-contenant.sql           canette ou bouteille
sql/13-canettes-uniquement.sql purge des bouteilles — lire les blocs !
sql/14-correctif-admin.sql     droits d'administrateur
```

`sql/outils/verifier-migrations.sql` dit à tout moment lesquelles sont déjà
passées. Il ne modifie rien.

**3. Créer deux buckets publics** dans Storage : `avatars` et `beers`.

**4. Renseigner l'URL et la clé** en tête du `<script>` d'`index.html`. La clé
`anon` est publique par conception — c'est le rôle des règles RLS de la rendre
inoffensive. La clé `service_role`, elle, ne doit jamais quitter le serveur.

**5. Déposer le dossier** sur n'importe quel hébergeur statique. Le service
worker exige HTTPS ; en ouvrant le fichier en local il reste simplement
inactif.

## Remplir le catalogue

Les deux scripts ont besoin de la clé `service_role`, à passer par
l'environnement et jamais dans un fichier :

```bash
export SUPABASE_URL="https://votre-projet.supabase.co"
export SUPABASE_SERVICE_KEY="cle-service-role"

node import-beers.mjs     # importe les canettes
node enrich-beers.mjs     # complète calories et allergènes
```

L'import classe les produits en trois catégories. Les canettes **certaines**
sont publiées ; les fiches **ambiguës** attendent dans l'écran de modération de
l'application ; les **bouteilles** sont écartées.

Cette étape manuelle est incontournable : Open Food Facts ne renseigne
l'emballage que sur environ 5 % de ses fiches bières. La photo est le seul
élément qui permette de trancher, et aucune règle automatique ne remplace un
coup d'œil.

## Modifier le code

Deux règles, à respecter sans exception :

**Toute donnée affichée passe par `esc()`, `safeColor()` ou `safeUrl()`.** Le
rendu se fait par `innerHTML` : un avis ou un pseudo inséré brut suffit à
exécuter du code chez ceux qui l'affichent, ce que les règles RLS n'empêchent
pas puisque le code tourne avec la session de la victime.

**Toute écriture vérifie l'erreur renvoyée avant de toucher au cache local.**
Sinon l'écran annonce un succès que la base n'a pas enregistré, et la perte
n'apparaît qu'au rechargement suivant.

## Licences et attribution

Les fiches bières proviennent d'Open Food Facts : **données sous licence ODbL,
photographies en CC-BY-SA**. L'attribution figure dans l'écran À propos de
l'application, comme la licence l'impose.

Les brèves de l'onglet Journal sont des résumés écrits pour Letterbeer, jamais
des extraits, et chacune renvoie au média d'origine.

---

*L'abus d'alcool est dangereux pour la santé. À consommer avec modération.*
