# Cooked

Cooked mesure le site [jplouton-avocat.fr](https://www.jplouton-avocat.fr) pour aider Nicolas à choisir les contenus à améliorer, développer ou retirer. Le socle retenu le **04/11/2026** réunit les pages publiées, les visites observées, les clics téléphone, les formulaires et les requêtes Google.

## Le besoin retenu

Le futur tableau devra montrer toutes les pages publiées, y compris celles sans visite : visites ayant consulté chaque page, visites commencées dessus, puis nombre et taux de ces entrées ayant produit un clic téléphone ou un formulaire. Le détail d’une page comparera les clics de ses requêtes Google et leur position moyenne. La période de départ sera de 90 jours comparés aux 90 précédents, modifiable.

**Cette interface reste un chantier séparé.** `dashboard/` conserve l’authentification et une page de transition ; les anciens écrans et leurs indicateurs sont retirés. L’intérêt du sujet pour le cabinet reste une décision de Nicolas, sans score ni classement automatique.

## Le socle conservé

| Source | Ce qu’elle permet de mesurer |
|---|---|
| Événements du tracker et webhook Wix | Pages vues, activité observable, clics téléphone et formulaires |
| Inventaire publié Wix | Toutes les pages, indépendamment du trafic |
| Google Search Console par page | Clics et impressions totaux de la page |
| Google Search Console par requête et page | Requêtes révélées, clics, impressions et position |

Les données conservées passent par les mêmes filtres bots/bruit et la même définition de visite. Le catalogue cible comprend **13 tables, trois vues et 60 routines** publiques, dont 56 Cooked et quatre fonctions de l’extension `unaccent`. Les compteurs de référence sont dans [contracts/doc_constants.json](contracts/doc_constants.json).

Le CPI, les copies de l’ancien dashboard, les modèles mathématiques, DataForSEO, Google Business Profile et le pont CRM/SECIB sortent du produit. Leurs anciens guides restent dans [l’historique Git](https://github.com/NicolasRewolf/cooked/tree/b6aa6370b9041763814bc0b1253182ece2694772/docs) ; le dépôt courant décrit uniquement le socle maintenu.

## Ce que les chiffres signifient

- Une visite regroupe l’activité observable d’un même navigateur, avec une coupure après plus de 30 minutes d’inactivité. Sa première page vue est son entrée.
- Un clic téléphone ne prouve pas un appel abouti. Un formulaire ne prouve pas un prospect unique. Les candidatures « nous rejoindre » sont exclues des contacts métier.
- Une visite avec téléphone et formulaire compte une fois dans leur union. Les nombres restent visibles à côté des taux.
- Un contact sans amont connu reste compté comme non attribué. Aucun parcours n’est inventé pour le rattacher à une page.
- Une collecte incomplète n’est pas un zéro. Les dates, la couverture et la part attribuable doivent accompagner la comparaison.
- Google masque des requêtes : leur somme ne reconstitue pas tous les clics de la page et ne permet pas d’attribuer une soumission à une requête individuelle.

Définitions : [CONTEXT.md](CONTEXT.md). Méthode d’analyse : [playbook](docs/PLAYBOOK-analyse-seo.md).

## Travailler sur Cooked

Lire [AGENTS.md](AGENTS.md), puis [CLAUDE.md](CLAUDE.md), [CONTRIBUTING.md](CONTRIBUTING.md), [OPERATIONS.md](docs/OPERATIONS.md) et [SECURITY.md](SECURITY.md). `make check` exécute les vérifications locales ; les tests locaux ne prouvent pas un déploiement ni la santé de la production.

Les événements restent pseudonymes. Aucun secret, contenu de formulaire ou identité ne doit entrer dans le dépôt, les rapports ou les logs. Le webhook v17 n’écrit plus dans un CRM ; cette simplification ne démontre pas l’anonymat des autres données.

[État de la simplification](docs/SIMPLIFICATION.md) · [Documentation](docs/README.md) · [Roadmap](docs/ROADMAP.md) · [Changelog](CHANGELOG.md)
