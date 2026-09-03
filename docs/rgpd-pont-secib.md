# RGPD — pont prospects ↔ dossiers SECIB

> Rédigé le **10/08/2026**, jour de mise en service de la capture d'identité
> (form-webhook v13 + backfill des 795 soumissions Wix historiques).
>
> ⚠️ **Ce document n'est pas un avis juridique.** Il rassemble les textes à
> publier et les décisions à prendre. Le responsable de traitement est le
> cabinet ; Me Plouton, avocat, valide avant publication.

---

## Le traitement en une phrase

Le cabinet rapproche les demandes de contact reçues via le site web des
dossiers effectivement ouverts et facturés dans SECIB, afin de savoir quels
canaux et quels contenus produisent de vrais dossiers, par matière.

**Décision produit du 10/08/2026** : le rapprochement se fait sur l'identité
**en clair** (nom, prénom, email, téléphone). Le hachage a été proposé et
écarté au profit de la lisibilité du rapprochement.

### Faits techniques établis (utiles au registre)

| Élément | Réalité vérifiée le 10/08/2026 |
|---|---|
| Tables portant la PII | `crm_prospects`, `secib_dossiers` — **uniquement** |
| Protection | RLS deny-all (aucune policy) + REVOKE anon/authenticated → accès clé de service seule |
| Hébergement | Supabase région **`eu-west-1` (Irlande, UE)** — pas de transfert hors UE |
| Analytics | `events` / `events_human` et toutes les RPC restent **sans PII** (invariant testé en CI) |
| Texte libre | Le message du formulaire n'est **jamais** importé |
| Volume au 10/08/2026 | 796 prospects (795 historiques 03/2025→08/2026 + 1 test) |

---

## 1. À publier sur le site

Bloc à insérer dans les mentions légales / la politique de confidentialité.

> **Données collectées via les formulaires de contact**
>
> Lorsque vous adressez une demande au cabinet via l'un des formulaires du
> site, nous collectons les informations que vous y renseignez : nom, prénom,
> adresse électronique, numéro de téléphone, objet de votre demande et les
> précisions que vous choisissez d'y ajouter.
>
> Ces données sont utilisées à deux fins :
>
> 1. **Répondre à votre demande** et, le cas échéant, préparer la relation
>    contractuelle avec le cabinet — traitement nécessaire à l'exécution de
>    mesures précontractuelles prises à votre demande (article 6.1.b du RGPD).
> 2. **Mesurer la pertinence de notre information en ligne** : le cabinet
>    rapproche les demandes reçues via le site des dossiers effectivement
>    ouverts, afin d'identifier quels contenus et quels canaux répondent
>    réellement aux besoins des personnes qui le consultent. Ce traitement à
>    finalité statistique repose sur l'intérêt légitime du cabinet
>    (article 6.1.f du RGPD) à améliorer la qualité et l'accessibilité de son
>    information juridique.
>
> **Destinataires.** Ces données sont accessibles aux seuls avocats et
> personnels du cabinet ainsi qu'à son prestataire technique, l'agence REWOLF
> (Bordeaux), qui intervient en qualité de sous-traitant au sens de
> l'article 28 du RGPD et est tenue à une obligation de confidentialité. Elles
> ne sont ni vendues, ni cédées, ni exploitées à des fins publicitaires.
>
> **Hébergement.** Le site est hébergé par Wix.com Ltd. Les données issues des
> formulaires sont enregistrées sur une infrastructure Supabase située dans
> l'Union européenne (Irlande). Aucun transfert hors de l'Union européenne
> n'est effectué dans le cadre de ce traitement.
>
> **Durée de conservation.** Les données issues des formulaires sont
> conservées 24 mois à compter de votre dernier contact avec le cabinet, puis
> supprimées. Lorsque votre demande donne lieu à l'ouverture d'un dossier, les
> données de ce dossier relèvent des règles d'archivage propres au cabinet et
> sont couvertes par le secret professionnel de l'avocat.
>
> **Vos droits.** Vous disposez d'un droit d'accès, de rectification,
> d'effacement, de limitation et de portabilité de vos données, ainsi que d'un
> **droit d'opposition** au traitement statistique décrit au point 2. Pour
> l'exercer, écrivez à accueil@jplouton-avocat.fr ou au Cabinet d'Avocats
> Julien Plouton, 15 Pl. Sainte-Eulalie, 33000 Bordeaux. Vous pouvez également
> introduire une réclamation auprès de la CNIL (www.cnil.fr).

⚠️ Le **droit d'opposition** est la contrepartie obligatoire de l'intérêt
légitime : s'il est exercé, supprimer la ligne correspondante de
`crm_prospects` (et ne pas la ré-importer au prochain export Wix).

---

## 2. Corrections sur les mentions légales existantes

Constaté sur `/mentions-legales` le 10/08/2026 :

1. **« Ce site Web est en cours de déclaration auprès de la CNIL » → à
   supprimer.** La déclaration préalable a été abolie par le RGPD le
   25/05/2018. La mention date d'avant et n'a plus d'objet.
2. **Hébergeur du site non nommé** — obligation LCEN, distincte du RGPD :
   Wix.com Ltd., 40 Namal Tel Aviv St., Tel Aviv 6350671, Israël.
3. **REWOLF y figure comme « agence de design »** : le bloc ci-dessus la
   requalifie en sous-traitant, ce qui implique un **contrat de
   sous-traitance écrit** (article 28) entre le cabinet et REWOLF —
   **à établir** (voir actions ouvertes).

---

## 3. Fiche pour le registre des traitements (interne, hors site)

| Champ | Contenu |
|---|---|
| Traitement | Mesure de la performance des canaux d'acquisition du site |
| Responsable | Cabinet d'Avocats Julien Plouton, 15 Pl. Sainte-Eulalie, 33000 Bordeaux |
| Sous-traitant | Agence REWOLF (Bordeaux) — outil « Cooked » |
| Finalité | Rapprocher les demandes de contact web des dossiers ouverts et facturés, par matière et par canal |
| Base légale | Intérêt légitime (art. 6.1.f) — finalité compatible avec la collecte initiale (art. 6.4) |
| Personnes concernées | Visiteurs ayant soumis un formulaire de contact ; clients du cabinet pour la partie dossiers |
| Données | Identité (nom, prénom), coordonnées (email, téléphone), objet de la demande, page et canal d'origine ; côté dossier : matière, dates, montant facturé |
| Destinataires | Cabinet + REWOLF (sous-traitant) |
| Hébergement | Supabase, Irlande (UE) — pas de transfert hors UE |
| Conservation | 24 mois après le dernier contact |
| Sécurité | Tables isolées (RLS deny-all), accès clé de service uniquement, aucune exposition publique ni dans le tableau de bord, PII absente des statistiques de fréquentation |
| Date de mise en œuvre | 10/08/2026 |

---

## 4. Actions ouvertes

| # | Action | Qui | Statut au 10/08/2026 — **inchangé au 03/09/2026** (`crm_prospects` : 858 lignes, dernier ajout 03/09 13:28) |
|---|---|---|---|
| 1 | Publier le bloc §1 + corriger les 3 points §2 | Nicolas, après relecture de Julien | à faire |
| 2 | Ajouter la fiche §3 au registre du cabinet | Cabinet | à faire |
| 3 | **Contrat de sous-traitance cabinet ↔ REWOLF** (art. 28) | Nicolas + Julien | manquant — le plus concret |
| 4 | **Confirmer la durée de conservation** (24 mois proposés) | Nicolas | à trancher — la purge automatique sera câblée ensuite |
| 5 | **Arbitrage « objet de la demande »** (voir ci-dessous) | **Julien** | à trancher |

### Le point §5 en détail

`crm_prospects.objet` stocke l'objet du formulaire (« Droit pénal »,
« Accidents de la route »…) **à côté du nom**. Associée à une personne
identifiée, cette information touche aux données de l'article 9 (santé) voire
de l'article 10 (infractions) du RGPD, et croise le secret professionnel.

Deux positions défendables, au choix de Julien :

- **Garder l'objet** — utile pour analyser les demandes qui *ne* deviennent
  pas des dossiers (le sujet qui n'accroche pas), et cohérent avec ce que le
  cabinet traite déjà par ailleurs.
- **Le retirer de `crm_prospects`** et ne lire la matière que du côté SECIB
  (`secib_dossiers.matiere_libelle`) — on perd alors la matière des
  non-convertis. Coût technique : quelques minutes.

---

## Liens

- Décision produit et architecture : `CLAUDE.md`, section « 10/08/2026 — Pont SECIB »
- Schéma et vue de lecture : migration `20260810082433_secib_pont_fondations`
- Capture : `supabase/functions/_shared/form_row.ts` (v13)
- Import historique : `scripts/wix_forms_import.py`
