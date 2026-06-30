# Cooked

**Cooked est le système de mesure du site [jplouton-avocat.fr](https://www.jplouton-avocat.fr).
Il existe pour répondre à une seule question, déclinée à l'infini :
qu'est-ce qui amène réellement des clients au cabinet — et que faut-il
faire ensuite ?**

Pas de cookies, pas de bandeau de consentement, pas d'échantillonnage,
pas de gros tableau de bord BI. Une base de données qu'on possède, un traceur écrit
sur mesure, Google Search Console ingéré dans la même base, un score de
santé par page, et une IA qui interroge le tout en langage naturel.

---

## Pourquoi Cooked existe

**Constat 1 — la mesure classique est cassée.** Google Analytics exige
un bandeau de consentement : une part importante des visiteurs refuse ou
ignore, et tout ce trafic disparaît de la mesure. Ce qui reste est
échantillonné, conservé 14 mois, enfermé dans l'outil de Google. On
finit par prendre des décisions sur un échantillon biaisé qu'on ne
contrôle pas.

**Constat 2 — les dashboards ne répondent pas aux questions.** Un
dashboard affiche ce qu'on a pensé à y mettre au moment où on l'a
construit. Les vraies questions arrivent après, et elles sont toutes
différentes : « cet article vaut-il la peine d'être réécrit ? »,
« d'où viennent les contacts de la semaine ? », « pourquoi cette page
perd-elle des clics alors qu'elle est toujours bien positionnée ? ».
Ce repo a hébergé un dashboard généraliste pendant trois jours (Sprint
33-34, mai 2026), puis l'a supprimé : personne ne pose ses questions à un
tableau de bord généraliste. (Un dashboard **focalisé** en lecture seule a
depuis été rebâti — suivi des articles ressources, `dashboard/`, live sur
data.rewolf.studio depuis le 29/06/2026 — il complète le Q/R, il ne le
remplace pas.)

**Constat 3 — acquisition et comportement vivent séparés.** Search
Console sait ce que Google montre (requêtes, impressions, clics,
positions). L'analytics sait ce que les visiteurs font sur les pages
(lecture, parcours, conversions). Le cabinet sait qui appelle. Tant que
ces trois mondes ne partagent pas la même base, la question la plus
importante — *cette requête Google finit-elle en client ?* — n'a pas de
réponse.

**Le parti pris.** Tout mesurer soi-même, proprement, dans une seule
base SQL ; et remplacer le dashboard par une IA. Nicolas pose une
question en français à Claude ; Claude appelle des fonctions SQL
publiées, documentées et testées (les « RPCs ») ; la réponse revient
avec ses chiffres, sa fenêtre temporelle et ses réserves. L'interface
du système, c'est la conversation.

---

## Ce que fait le système

**1. Mesurer — sans cookies, sans bandeau, sans trous.**
Un traceur maison (~15 Ko dans le `<head>` Wix) capture chaque visite :
pages vues, profondeur de lecture (scroll, temps actif), performance
technique (Web Vitals), clics sortants et internes, et les trois
niveaux de conversion — appels téléphone, soumissions de formulaire
(captées côté serveur, donc infalsifiables), intentions de rendez-vous.
L'identité du visiteur est un identifiant aléatoire local, jamais une
donnée personnelle : c'est le modèle « mesure d'audience exemptée »
de la CNIL, le même que Plausible ou Fathom. Et comme il n'y a pas de
bandeau, on mesure **tout le monde**, pas seulement ceux qui cliquent
« accepter ».

**2. Nettoyer — la donnée brute ment.** Les bots, les crawlers SEO,
les sessions de préchargement, les clics dupliqués par un bug
d'intégration : tout cela gonfle les chiffres de 15 à 20 %. Cooked
filtre ce bruit dans une couche dédiée (`events_human`) et **toutes**
les analyses lisent cette couche. Quand un chiffre a été corrigé
rétroactivement (ça arrive — exemple : les contacts téléphone 28j sont
passés de 110 à 95 en corrigeant un double-comptage), la correction est
nommée, datée et expliquée : c'est un *restatement*, pas une baisse.

**3. Croiser — la boucle complète, de la requête au client.** Google
Search Console est ingéré chaque matin dans la même base (16 mois
d'historique, 3 granularités, dont la brique critique requête × page),
complété par les volumes de recherche DataForSEO. La chaîne entière
devient interrogeable d'un seul tenant : **requête Google → impression
→ clic → page d'atterrissage → lecture → parcours → contact**.

**4. Noter — un score de santé par page.** Le CPI (*Cooked Page Index*)
résume en un nombre de 0 à 100 ce qu'une page vaut vraiment : capte-t-elle
les clics que Google lui offre (comparé à la courbe de clics propre au
site, requête par requête) ? Retient-elle ses lecteurs ? Les fait-elle
lire en profondeur ? Contribue-t-elle aux contacts, directement ou en
appui d'autres pages ? Le score est ajusté par la dynamique de la page
*relative au site* (une marée qui baisse partout ne punit personne) et
par sa vitesse mobile. Chaque score porte un **grade de confiance**
(A/B/C) : un champion vu 12 fois est une hypothèse, pas un résultat.
Le score est archivé chaque matin — sa trajectoire devient elle-même
un signal d'alerte précoce.

**5. Se surveiller — un chiffre produit pendant un incident est un
chiffre faux.** Le pipeline se diagnostique tout seul : alertes horaires
(ingestion morte, attribution dégradée, retard Google, chute brutale du
score d'une page fiable), tests de contrat sur les fonctions publiées,
bilan de santé en début de chaque session d'analyse. L'agent qui ouvre
une session commence par `SELECT * FROM alerts WHERE NOT acked` — et
traite l'alerte avant de produire le moindre chiffre.

---

## Comment il pense

Ces règles sont nées d'erreurs réelles, chacune a coûté une fausse
conclusion. Elles sont encodées dans les fonctions SQL et documentées
dans le [playbook d'analyse](docs/PLAYBOOK-analyse-seo.md) :

- **Trois niveaux de conversion, jamais mélangés.** Macro = téléphone +
  formulaire (LA métrique business, celle qu'on remonte au cabinet).
  Micro = intention de rendez-vous. Engagement = lecture profonde.
  Annoncer « 157 conversions » en mélangeant tout, c'est l'erreur du
  15/05/2026 — il y en avait 37 vraies.
- **Toute métrique de lecture se décompose par canal.** Le temps de
  lecture global d'une page mélange les visiteurs Google (45 s) et les
  passages éclair des réseaux sociaux (1 s) : il ment. On juge une page
  sur ses entrées organiques.
- **La position moyenne Google est un piège.** Elle est pondérée par
  les impressions et mélange des requêtes incomparables. Le CTR attendu
  se calcule requête par requête, sur la courbe du site lui-même.
- **Marée ≠ déclin.** Des clics qui baissent à position constante,
  c'est la demande ou la page de résultats qui change — pas la page.
  Réécrire une page pour ça, c'est soigner le mauvais malade.
- **Le branded (« plouton ») est exclu** de toute mesure de capture :
  sinon la home triche.
- **Petits volumes = hypothèses.** Lissage statistique (empirical
  Bayes) et grades de confiance partout. Sous ~30 entrées organiques,
  on émet des pistes, pas des verdicts.
- **Heure de Paris partout, dates JJ/MM/AAAA, fenêtres explicites.**
  Un « aujourd'hui » calculé en UTC perd deux heures de conversions
  chaque matin.
- **Un fix = une migration nommée.** Aucune modification de la base
  sans trace versionnée dans le repo. La prod et le repo ne divergent
  jamais (vérifié par tests de contrat et alertes).

---

## Comment c'est construit

```
Navigateur (Wix)          Wix Automations (server-side)
  tracker.html               formulaires
      ↓ same-origin              ↓ webhook signé
  Proxy Velo                     ↓
      ↓ clé injectée côté serveur
  Edge Function track       Edge Function form-webhook     GSC + DataForSEO
      ↓                          ↓                          (crons quotidien/hebdo)
  ┌─────────────────────── Postgres (Supabase) ───────────────────────┐
  │  events (brut)  →  events_human (sans bots ni bruit)              │
  │  gsc_path_daily / gsc_query_daily / gsc_query_page_daily          │
  │  snapshots nocturnes · CPI quotidien · alertes horaires           │
  │  ~55 fonctions SQL publiées = l'API du système                    │
  └───────────────────────────────────────────────────────────────────┘
      ↓
  Claude Code (MCP Supabase) — Nicolas pose des questions, en français
```

Six briques, aucune exotique : un traceur JavaScript artisanal (testé,
versionné, minifié sous la limite Wix de 15 000 caractères), deux
fonctions serveur Deno, une base Postgres managée (Supabase), deux
ingestions planifiées (GitHub Actions), et Claude comme interface.
Le détail opérationnel — events captés, déploiement, crons, sécurité,
dépannage — vit dans [docs/OPERATIONS.md](docs/OPERATIONS.md).

---

## Ce qu'on lui demande, concrètement

| Question posée | Ce qui répond |
|---|---|
| « Combien de contacts cette semaine, et d'où ? » | `site_macro_counts` + `conversion_journeys` |
| « Quelles pages vont mal ? Lesquelles réparer d'abord ? » | `cooked_page_index(28)` — tri par CPI, grades A/B |
| « Cette page chute — c'est la SERP ou c'est elle ? » | momentum relatif + `cpi_movers` (la dérivée du score) + alerte `cpi_drop` (vrai decay) |
| « Cet article est-il bon ? » | `gsc_page_performance` + lecture décomposée par canal |
| « Le SEO rapporte-t-il des clients ? » | `seo_to_contact_funnel` — requête → landing → contact |
| « Quoi écrire ensuite ? Quels quick wins ? » | `content_performance` + `gsc_x_dfs_opportunities` |
| « Quelles pages ont du trafic mais ne convertissent pas ? » | `cpi_gisement` — potentiel vs conversion réalisée |
| « Le système va bien ? » | `alerts` + `refresh_pipeline_health()` |

---

## Où en est le système (30/06/2026)

**En production depuis le 06/05/2026.** Tracker navigateur `sprint38`
(batching, garde anti-double-embed, attribution des formulaires par champs
cachés Wix) ; Edge Function `track` en **v22**. ~390 000+ événements bruts,
~2 millions de lignes Search Console (16 mois), ~190 pages scorées par le CPI
chaque matin.

**Sprint 39 (15-18/06) — l'outil passe en prod opérationnelle.**
- **CPI v2.2** : momentum à transition continue + lissage empirical Bayes
  dynamique par type (corr 0,9855 avec v2.1, aucun verdict fiable déplacé).
- Vue **`cpi_gisement`** : sépare le *potentiel* d'une page (capture +
  rétention + lecture) de sa *conversion réalisée* → pointe les pages à fort
  trafic qui ne convertissent pas encore — le gisement à « ponter » vers le
  contact.
- Alertes recalibrées (`cpi_drop` = vrai decay uniquement) ; bug P1
  `click_internal.target_path` résolu (Edge v22 + backfill).
- 3 revues d'experts externes du CPI passées au crible → verdict : l'outil est
  suffisant, on ne le complexifie pas, **le levier est désormais l'action sur
  le site**, plus le modèle.

**Fin juin — une UI ciblée et un pipeline durci.**
- **Dashboard V1 (29/06)** : une sous-app Next.js 16 isolée (`dashboard/`),
  lecture seule, live sur **[data.rewolf.studio](https://data.rewolf.studio)** —
  suivi des articles « ressources » (comportement Cooked + SEO par requête,
  volume DataForSEO en référence). Il *complète* le question/réponse, il ne le
  remplace pas.
- **Fiabilité du pipeline (30/06)** : plusieurs crons nocturnes échouaient en
  silence (dépassements de `statement_timeout` à mesure que la donnée grossit).
  Diagnostiqués et corrigés — snapshot CPI dégelé et protégé, filtres anti-bruit
  durcis (`TRUNCATE`→`DELETE`, fin des deadlocks), et le rebuild du snapshot SEO
  **optimisé de 671 s à 210 s** (matérialisation d'`events_human` en table
  temporaire). La fonction d'auto-diagnostic ne crashe plus pendant un incident.

**Repère 10/06/2026** (premier snapshot CPI) : CPI moyen pondéré trafic
**32/100**, ~446 clics Google « perdus »/mois — marge chiffrée page par page.

**Prochaine échéance — validation prédictive le 08/07/2026** : le CPI prédit-il
les contacts des 28 jours suivants ? Protocole prêt
([scripts/cpi_validation_j28.sql](scripts/cpi_validation_j28.sql)). S'il échoue,
on recalibre les poids — on ne masque pas le résultat.

---

## Limites assumées

- **Un seul site, un seul tenant.** Cooked est construit pour
  jplouton-avocat.fr. La méthode est généralisable, le code ne prétend
  pas l'être (pas de multi-tenancy tant que ce n'est pas une décision
  business).
- **Wix contraint le traceur** : 15 000 caractères maximum dans le
  Custom Code, d'où minification et arbitrages permanents.
- **Search Console arrive avec 2-3 jours de retard** et anonymise
  jusqu'à ~94 % des requêtes d'une page — les totaux viennent toujours
  de `gsc_path_daily`, l'attribution requête → page reste partielle
  par construction.
- **Les volumes sont petits** (~130 contacts/mois) : le système
  préfère dire « hypothèse » que sur-interpréter. C'est un choix.

---

## La documentation

| Besoin | Fichier |
|---|---|
| Comprendre l'ambition et le système | ce fichier |
| Opérer : déploiement, events, crons, dépannage | [docs/OPERATIONS.md](docs/OPERATIONS.md) |
| Mener une analyse SEO sans tomber dans les pièges | [docs/PLAYBOOK-analyse-seo.md](docs/PLAYBOOK-analyse-seo.md) |
| Comprendre et utiliser le score CPI | [docs/cpi-cooked-page-index.md](docs/cpi-cooked-page-index.md) |
| Le dashboard de lecture (articles ressources) | [dashboard/README.md](dashboard/README.md) |
| Ce qui reste à faire (P0/P1/P2) | [docs/ROADMAP-sprint38-handoff.md](docs/ROADMAP-sprint38-handoff.md) |
| Fiabilité des données (audits) | [docs/data-quality-audit-2026-06-10.md](docs/data-quality-audit-2026-06-10.md) |
| Chronologie des sprints | [docs/HISTORY-sprints.md](docs/HISTORY-sprints.md) |
| Règles de l'agent Claude Code (lu automatiquement) | [CLAUDE.md](CLAUDE.md) |
