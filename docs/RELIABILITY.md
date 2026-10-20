# Fiabilité — corrections du 20/10/2026

Cette page décrit les contrats techniques et leur état de livraison, sans
reproduire les données métier de l'audit. Le dépôt, le déploiement et les
données reçues sont trois preuves distinctes.

## État de livraison

| Composant | Source | État vérifié le 20/10/2026, après livraison et recalcul |
|---|---|---|
| Tracker Wix | `sprint43`, tests source et minifié ; contexte SPA et CWV document | Custom Code enregistré à 11:50 Paris ; HTML public vérifié identique au minifié, avec et sans cache ; événements sprint43 reçus en production |
| Edge track | v31, classement iPhone/iPad iOS corrigé | Déployé à 11:49 Paris, Supabase 41 ACTIVE |
| Edge form-webhook | v16, livraison idempotente et diagnostics sans identité | Déployé à 11:49 Paris, Supabase 25 ACTIVE |
| SQL / CPI | Migration `20261020094908`, définition CPI 2.2.6 | Migration appliquée et miroirs régénérés ; snapshots du 20/10 en 2.2.6, recalcul complet terminé à 13:25 Paris |
| Dashboard | Diagnostics et agrégats corrigés, dépendances mises à niveau | PR #152 fusionnée ; Vercel READY sur `2ac95ad`, servi sur data.rewolf.studio ; navigation et redirections contrôlées |
| GSC | Ingestion `all`, protocole begin/complete/fail | Lot des trois tables clôturé à 11:55 Paris ; cinq étapes aval réussies, aucun lot en attente de refresh |
| Rapprochement Wix | Workflow quotidien, agrégats sur 28 jours Paris clos | Premier run réussi sur les 28 jours du 22/09 au 19/10 ; permission Forms et égalité des comptes vérifiées |

Mettre à jour cette table uniquement avec une preuve correspondante.
L'absence d'erreur locale ne suffit pas à marquer une ligne « déployée ».
Preuves publiques : [PR #152](https://github.com/NicolasRewolf/cooked/pull/152)
et [rapprochement Wix](https://github.com/NicolasRewolf/cooked/actions/runs/39414716394).
La CI de la PR a aussi validé le miroir SQL et les contrats RPC contre la production.

Le 20/10, le HTML canonique public contenait le script exact de 14 460 caractères
(SHA-256 `3296d3bb0f759a9898b4ce672ef61cdf986eddf4e4a624b23a2eab35eeb60a40`).
À 13:17 Paris, les réponses du cache et d'une URL avec paramètre de contrôle
contenaient `sprint43` sans occurrence `sprint42`. Aucun brouillon Wix n'a été
publié et aucune purge n'a été nécessaire. Les onglets ouverts avant cette
mise à jour peuvent continuer à émettre l'ancienne version.

## Mesures et sorties corrigées

| Défaut | Contrat corrigé |
|---|---|
| Sortie de A envoyée avec le chemin de B après navigation SPA | Contexte URL figé par route ; fin de A avant le pageview B, pour pushState, replaceState et popstate. Les transitions rapprochées ne se fusionnent pas. |
| CWV arrêtés au premier masquage ou rejoués sur une autre route | Observers attachés une fois au document. Valeurs conservées sur sa route initiale ; `measurement_id` et `revision` permettent de retenir la dernière valeur par métrique avant percentile. |
| Lectures sans referrer exclues des médianes Ressources | Les NULL sont conservés ; le filtre Facebook/LinkedIn demeure explicite. |
| Position de fiche calculée par moyenne simple | Pondération par impressions pour les valeurs descriptives et les requêtes de fiche. |
| Diagnostic CTR calculé à partir d'une position moyenne | Attente non justifiée retirée (`ctr_expected` nullable) ; CTR observé affiché sans couleur ni prescription titre/méta automatique. |
| Intention de rendez-vous assimilée à un contact dans `convertit` | Badge réservé aux contacts macro organiques directs ou assistés. La contribution pondérée des intentions dans le score reste séparée. |
| Bookings hors fenêtre CPI rattachés par une session présente dans la fenêtre | Bornes de la fenêtre canonique appliquées aussi à l'horodatage du booking ; poids 0,25 inchangé. |
| Visiteurs distincts additionnés dans le footer | Total visiteurs retiré ; un distinct de périmètre ne se déduit pas de la somme des lignes. |
| Badge de source dérivé de clics GSC / visiteurs Cooked | Badge retiré ; ce ratio de deux unités ne devient pas une attribution de canal. |
| Historique CPI reliant plusieurs définitions | `cpi_version` transmis ; graphique limité à la dernière séquence consécutive de la définition courante, masqué si la version manque ou si la série est trop courte. |
| Projection de gain SEO appliquée à un volume national non qualifié | Podium et gains théoriques retirés. Les observations GSC et volumes DFS restent des éléments à qualifier, avec un guide de lecture. |
| Expertises oubliant les identifiants publicitaires URL | URL conservée par le driver et transmise à `classify_channel`, notamment pour gclid/gbraid/wbraid. |
| Ancien funnel mélangeant contacts tous canaux et trafic Google | `site_seo_funnel` refuse explicitement l'appel et oriente vers `seo_to_contact_funnel`. |
| Filtre prefetch pouvant supprimer une action intentionnelle | Présence d'une action volontaire conservée dans les critères d'exclusion du bruit. |
| Âge Google figé à la création du snapshot | Retard recalculé à partir du dernier jour de données et du jour Paris courant. |

La définition CPI 2.2.6 et son annotation matérialisent la rupture technique.
Les snapshots historiques ne sont pas réécrits. Le correctif du tracker
modifie les événements futurs ; il ne reconstitue pas avec certitude les
durées qui avaient été attribuées au mauvais chemin.

Le grain CWV choisi est le document de navigation initial, y compris sa
reprise bfcache. Les anciennes mesures sans `measurement_id` gardent leur
grain historique. Le champ historiquement nommé INP reste un maximum
Event Timing ; il ne constitue pas une implémentation complète de l'INP
standard ni une reproduction de CrUX.

## Ingestion, sécurité et exploitation

**GSC.** `all` publie un lot complet seulement après les trois tables.
Un échec ou une ingestion partielle bloque le refresh ; un timestamp récent
dans la seule table pages n'est plus suffisant. Begin/refresh partagent un
verrou ; après un arrêt brutal, vérifier l'absence de processus actif avant
de déclarer le lot en échec et relancer un lot complet.

**Formulaires.** Un identifiant stable est requis avant écriture. HTTP 200
atteste que la ligne analytics et l'identité extraite ont chacune été
enregistrées ou reconnues comme doublon. Sinon HTTP 503, y compris après
une réponse réseau incertaine. Réessayer est idempotent grâce aux index
uniques ; la politique effective de retry Wix reste à vérifier. Le
rapprochement quotidien compare les comptes confirmés par jour, sans
contenu personnel ni réimport automatique.

**Accès dashboard.** Le callback rejette les caractères de contrôle et
vérifie l'origine de l'URL résolue. L'allowlist et la lecture serveur restent
nécessaires. Les dépendances sont mises à niveau avec audit, tests, lint et
build ; les avis doivent être relus à chaque livraison, en distinguant
runtime, outillage et conditions d'exploitation.

**Traçabilité production.** La migration du 19/09 déjà appliquée doit être
publiée telle quelle dans l'historique, sans rejouer le backfill. Un run
`prod-drift` complet est nécessaire après alignement. Les échantillons RPC
doivent provenir de la production puis être confrontés aux schémas.

**GBP.** Une réauthentification Google et la reprise de l'ingestion sont
nécessaires lorsque les credentials expirent. Un secret remplacé ne prouve
pas le rattrapage : vérifier le succès du workflow, le dernier jour et la
continuité de la période manquante. Des données périmées ne sont pas des zéros. Le 20/10, OAuth a été renouvelé mais
l’appel Performance confirme un quota projet égal à zéro : Google doit approuver
l’accès API de base du projet appelant. Le diagnostic distingue ce cas d’une
expiration OAuth et ne recommande plus une réauthentification sans preuve.
La migration `20261020112802` aligne aussi les conseils du registre de fraîcheur :
quota nul et authentification ont des remèdes distincts ; la reprise GSC doit
porter sur les trois tables et être suivie du refresh complet. La demande Google
d'accès API de base reste à envoyer ; aucun rattrapage GBP n'est confirmé.

**Taxonomie et alertes.** Une page sans catégorie nécessite une vérification
du chemin, d'une éventuelle redirection et de la source Wix. Le contrôle du
20/10 trouve une réponse 404 pour le chemin signalé : il ne faut pas inventer
une catégorie pour lever l'alerte. Le diagnostic ne conclut plus
automatiquement à un secret manquant. Un historique d'alertes non acquittées
n'est pas un nombre d'incidents simultanés.

**SECIB.** L'ingestion en environnement production reste bloquée tant
qu'une synchronisation complète et le traitement des dossiers anciens
modifiés ne sont pas validés. Changer les credentials ou signer un devis
ne lève pas ce garde-fou. En test, un export financier borné ne devient pas
un cumul de facturation persisté ; le probe compare uniquement des codes de
dossiers facturés, sans agrégation de montant. La complétude de l'export reste
à valider.

## Validation et limites

Les tests tracker simulent navigation, horloge, visibilité, bfcache et
PerformanceObserver. Les tests de livraison simulent échecs DB, réponses
perdues, doublons et indisponibilité des alertes. Les tests SQL utilisent
des jeux synthétiques ; les tests dashboard incluent les contrats de sortie.
Ils protègent les régressions identifiées, sans se substituer aux contrôles
de production et de navigateur après publication.

Les jours Google sont en heure du Pacifique ; les événements Cooked en
heure de Paris. Un clic sur un téléphone n'atteste pas un appel abouti.
SECIB reste en environnement test au dernier contrôle. Les identifiants
persistants sont pseudonymes, avec possibilité de couture CRM : aucune
exemption de consentement ni publication de texte juridique n'est
déduite de ces corrections. Voir [SECURITY.md](../SECURITY.md),
[OPERATIONS.md](OPERATIONS.md) et [rgpd-pont-secib.md](rgpd-pont-secib.md).
La catégorie Wix `ESSENTIAL` préexistante a été conservée lors du remplacement
technique du tracker, puis confirmée par Nicolas le 20/10 pour préserver la
qualité de mesure. Le maintien de la collecte est explicite ; l'exemption de
consentement et la conformité du traitement restent à établir.
