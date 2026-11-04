# CLAUDE.md — travailler sur Cooked

**Référence du 04/11/2026.** Cooked est le socle de mesure éditoriale de `jplouton-avocat.fr`, maintenu par Nicolas. Le besoin est de comprendre quelles pages attirent des visites, quelles entrées produisent des contacts observés et quelles requêtes Google évoluent. La simplification remplace les anciennes recettes CPI, CRM et snapshots. Voir [SIMPLIFICATION.md](docs/SIMPLIFICATION.md).

## Périmètre produit

La cible de lecture est un tableau des pages publiées et le détail Google d’une page, avec 90 jours comparés aux 90 précédents et une période modifiable. La refonte UI reste séparée ; `dashboard/` ne contient désormais que l’accès authentifié et une page de transition.

Nicolas décide de l’intérêt d’un sujet pour le cabinet et des actions éditoriales. Ne pas lui demander de renseigner cet intérêt dans Cooked, ajouter de score automatique, rétablir le CPI ou greffer une nouvelle intégration. Une page à fort volume et une page de niche à fort taux peuvent toutes deux être utiles.

## Autonomie

Dans le périmètre demandé, l’agent peut prendre les décisions techniques sur le tracker, le proxy Velo, les deux Edge Functions, le schéma et ses migrations, les imports GSC et Wix, les contrats, la documentation et les analyses. Le projet Supabase est `mxycmjkeotrycyneacje`.

Une validation explicite de Nicolas est requise pour une nouvelle décision business/produit, une suppression de données irrécupérable ou un changement de coût significatif. Une autorisation déjà donnée dans la session reste valable : ne pas la redemander. Respecter les propriétaires de fichiers et les modifications des autres agents.

Le backup externe a été décliné le 02/07/2026 ; ne pas le reproposer avant juin 2027 sans demande nouvelle. Le numéro traçable sur la fiche Google a été décliné le 28/07/2026. Ne pas transformer ces décisions en tâches automatiques de la roadmap.

## Avant de produire des chiffres

```sql
SELECT * FROM alerts WHERE NOT acked;
SELECT * FROM refresh_pipeline_health();
SELECT * FROM latest_rpc_health();
SELECT gsc_last_data_day();
SELECT status, day_start, day_end, completed_at
FROM gsc_ingest_batches ORDER BY batch_no DESC LIMIT 1;
```

Vérifier les dates, les sources et la couverture. Traiter ou expliquer les incidents pertinents avant d’interpréter les chiffres. Une alerte historique ne démontre pas une panne actuelle ; l’acquitter signifie qu’elle a été examinée, pas qu’une correction a été prouvée. Ne jamais vider globalement le stock.

Tout chiffre appuyant une décision doit être contre-vérifié : décomposer un agrégat par page, requête, canal ou jour ; recouper des sources sur des fenêtres explicites lorsqu’elles décrivent un phénomène comparable. Les clics GSC et les visites Cooked sont des mesures différentes, sans égalité attendue. Si la vérification manque, le dire.

Présenter les données observées, les calculs et les hypothèses séparément. Un passage de tests locaux ne prouve ni une livraison en production ni le fonctionnement sur des utilisateurs réels.

## Invariants métier

- **Filtrage commun.** Pour les analyses ad hoc, lire `events_human`, jamais `events` brut. Les exceptions sont l’audit du filtrage et le diagnostic d’ingestion, à annoncer. Les vues `events_main` et `events_no_bots` participent au même filtre du site principal.
- **Visite observée.** `cooked_visit_events` utilise la couture d’identité et coupe après plus de 30 minutes sans activité observable. `web_vitals` ne prolonge pas une visite. La première page vue est l’entrée, même si elle précède la fenêtre de lecture.
- **Attribution prudente.** Aucun événement futur ni simple proximité temporelle ne crée de lien avec un formulaire. Les contacts sans amont connu restent dans le total site, explicitement non attribués.
- **Contacts métier.** Clic téléphone et formulaire éligible seulement. Les candidatures « nous rejoindre » sont exclues. Le clic « prendre RDV » reste une intention ; lecture et engagement ne sont pas des contacts. Un clic téléphone ne prouve pas un appel réel, une soumission ne prouve pas une personne ni un dossier signé.
- **Grain explicite.** Les événements, visites et personnes ne sont pas interchangeables. `page_visits` déduplique les visites ayant contacté ; téléphone et formulaire se recouvrent et ne s’additionnent pas pour obtenir l’union.
- **Cohorte d’entrée.** Les taux par page portent sur les visites commencées sur cette page dans la période, avec actions observées avant sa clôture. Sans entrée, le taux est inconnu. Les nombres accompagnent les taux.
- **Zéro et couverture.** Une page publiée sans ligne de mesure devient zéro seulement si la couverture permet cette lecture. Un trou de collecte ou une période partielle reste explicite ; pas de delta présenté comme complet.
- **Temps.** Jours clos Paris pour Cooked ; utiliser `paris_today()`, `paris_date()` et les helpers de bornes. Éviter les casts directs et `current_date` dans les nouveaux calculs. GSC conserve ses dates source ; ne pas les présenter comme des jours Paris parfaitement superposables.
- **Affichage.** Dates en JJ/MM/AAAA, heures Paris, bornes visibles. ISO reste permis dans SQL, code et noms de fichiers. Une colonne `*_pct` vaut 0–100 ; `*_rate`, 0–1.
- **Google.** Garder les deux grains page et requête × page distincts. Pondérer les positions par les impressions. Les requêtes masquées sont inconnues ; aucune attribution individuelle requête → formulaire n’est démontrée.
- **Petits volumes.** Conserver les nombres et les limites. Une baisse de clics à position stable n’établit pas que l’article est mauvais ; une corrélation ne prouve pas la cause.

Définitions détaillées : [CONTEXT.md](CONTEXT.md). Recette de lecture : [PLAYBOOK-analyse-seo.md](docs/PLAYBOOK-analyse-seo.md).

## Règles techniques et sécurité

Aucun secret ni donnée personnelle dans le dépôt public, les réponses, les logs, les issues ou les PR. Ne jamais imprimer les valeurs d’environnement, URLs authentifiées ou payloads de formulaires. Lire [SECURITY.md](SECURITY.md) pour les données, accès et limites du socle conservé.

Les événements restent pseudonymes. L’absence de cookies ne démontre pas l’anonymat ou une exemption de consentement. Le webhook v17 conserve uniquement l’événement filtré ; son authentification n’a pas changé.

Toute migration créant/remplaçant une fonction métier ferme son accès à `PUBLIC`, `anon` et `authenticated`, puis accorde l’exécution aux rôles nécessaires. RLS et vues `security_invoker` restent contrôlées. `alert_rule_exposure()` et la CI surveillent les expositions ; une exposition inattendue est un incident.

Un correctif SQL laisse une migration exacte dans `supabase/migrations/`. Les miroirs `supabase/rpcs.sql`, `supabase/views.sql` et métadonnées sont régénérés après livraison, jamais maquillés à la main. Les constantes documentaires suivent `contracts/doc_constants.json` ; les objets retirés sortent des guides actifs.

Préserver le constructeur commun d’événements, la canonicalisation SQL/Edge/Python, les tests de dates et les contrôles de déduplication. La profondeur historique vient de `page_exit.max_scroll` ([ADR-0001](docs/adr/0001-source-unique-profondeur-lecture.md)). Les Web Vitals restent au grain document ; une révision ne devient pas une nouvelle mesure indépendante. Ces événements conservés ne justifient pas de rétablir les anciens scores.

Ne pas charger plusieurs grosses requêtes simultanément en production. Les délais et une annulation côté client ne prouvent pas l’arrêt du statement serveur. Vérifier une livraison sur son périmètre réel, sans envoyer de fausse soumission métier.

## Git et vérification

Branche `codex/<sujet>` → changements ciblés → `make check` → PR selon l’autorisation de la session. Pas de commit, push ou déploiement si la mission les exclut. Ne pas rétablir les modifications d’autres intervenants.

Les migrations appliquées portent leur timestamp réel dans la même PR. Après une livraison SQL, contrôler les résultats utiles et les advisors sans répéter des sondes lourdes déjà validées. Pour le tracker, comparer le minifié au HTML public ; ne pas publier des brouillons Wix sans rapport avec la tâche.

## Références

[AGENTS.md](AGENTS.md) oriente l’entrée ; [CONTRIBUTING.md](CONTRIBUTING.md) décrit la CI ; [OPERATIONS.md](docs/OPERATIONS.md) les sources et les déploiements. [docs/README.md](docs/README.md) indexe les guides maintenus et les ADR. [CHANGELOG.md](CHANGELOG.md) suit les changements du socle ; les anciennes recettes restent dans l’historique Git, les migrations appliquées dans le dépôt.

Les issues et PRD vivent dans GitHub Issues ; leurs conventions sont dans [CONTRIBUTING.md](CONTRIBUTING.md). Lire les ADR qui concernent le changement avant de contredire une décision existante.
