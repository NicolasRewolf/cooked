# Cooked — suite du socle éditorial

Référence du **04/11/2026**. Le périmètre retenu est décrit dans [SIMPLIFICATION.md](SIMPLIFICATION.md). Les anciens tickets CPI, CRM/SECIB, DataForSEO, GBP, maths et dashboard ne constituent plus une liste de fonctionnalités à relancer.

## Étape produit retenue

Une seule page privée liste toutes les URL publiées avec leurs vues, y compris zéro. L’extension autorisée ajoute les entrées, contacts observés par téléphone/formulaire, leur union et son taux, la comparaison avec la période précédente et le détail Google d’une page. Ses lecteurs SQL sont déployés ; les vérifications de l’implémentation sont suivies dans le [changelog](../CHANGELOG.md).

Une vue reste un événement humain `pageview` ; les affichages répétés comptent plusieurs fois. La période est de 30, 60 ou 90 jours Paris clos, avec 90 jours par défaut, comparée à une fenêtre précédente de même durée. Le détail Google se charge à la demande, avec ses propres dates et sa couverture.

Les filtres sont Toutes, Expertises (pages et hubs d’expertise), Articles (hors ressources) et Ressources et notions juridiques. Articles et Ressources sont disjoints ; les autres pages restent dans Toutes. Une période incomplète reste signalée.

L’intérêt d’un sujet pour le cabinet reste jugé par Nicolas. Le tableau lit les sources existantes sans nouveau stockage ni recalcul planifié.

Les contacts restent des actions observées : aucun appel abouti, prospect qualifié, dossier signé ou revenu n’est déduit des clics et formulaires. Les anciens scores, intégrations retirées et analyses de lecture ne font pas partie de la suite implicite. Tout ajout au-delà du périmètre autorisé demande une nouvelle décision de Nicolas.

## Exploitation courante

Maintenir les sources conservées et leurs contrôles : réception des événements, inventaire Wix complet, lots GSC à deux grains et rapprochement agrégé des formulaires. Les incidents réels se traitent à partir de leur run et de leurs dates, pas d’une ancienne case de roadmap.

La qualification du traitement pseudonyme, les informations publiées et les durées restent des sujets distincts de la suppression des fonctions. Lire [SECURITY.md](../SECURITY.md) sans déduire une conformité de la seule réussite des tests.

Les changements livrés sont consignés dans [CHANGELOG.md](../CHANGELOG.md).
