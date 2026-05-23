/**
 * Liste des paths d'articles appartenant à la catégorie
 * "Ressources et notions juridiques" — sous-ensemble de /post/*.
 *
 * Source de vérité : la page hub /comprendre-le-droit (maintenue
 * manuellement par Nicolas). Cooked ne stocke pas cette info en base,
 * cf. CLAUDE.md du repo cooked.
 *
 * ⚠️ La catégorie Wix Blog /blog/categories/ressources-et-notions-juridiques
 * ne contient qu'un sous-ensemble (~20 articles). NE PAS l'utiliser.
 *
 * Liste générée depuis l'export Wix Posts.csv du 23/05/2026 (51 entrées,
 * langue fr). Filtre : Main Category = 67db2299545b100e876895bd
 * (catégorie "Ressources et notions juridiques") OU présence dans la
 * page hub.
 *
 * Maintenance :
 *   1. Aller sur https://www.jplouton-avocat.fr/comprendre-le-droit
 *   2. (ou exporter Wix Posts → CSV, filtrer Main Category)
 *   3. Mettre à jour ce Set ci-dessous.
 *   4. Commit + push.
 *
 * Format : chaque entrée doit commencer par "/post/" et matcher exactement
 * le path stocké dans events.path (post-canonical_path : decode + NFC,
 * sans slash final). Validé : tous les paths ci-dessous matchent
 * gsc_path_daily.path et events.path en base au 23/05/2026.
 */

export const RESOURCE_PATHS: ReadonlySet<string> = new Set([
  "/post/abandon-de-poste-quels-risques",
  "/post/accident-du-travail-comment-obtenir-votre-indemnisation",
  "/post/accident-médical-oniam-dans-quels-cas-pouvez-vous-être-indemnisé",
  "/post/accident-médical-responsabilité-médicale-et-aléa-thérapeutique",
  "/post/accident-voyage-organise-etranger-responsabilite-agence",
  "/post/au-cœur-de-la-justice-restaurative-retour-sur-une-journée-d-étude-à-bordeaux",
  "/post/auto-entrepreneur-victime-d-un-accident-comment-justifier-une-perte-de-revenus-ou-d-exploitation",
  "/post/bail-commercial-la-révision-du-loyer-comment-est-ce-que-cela-fonctionne",
  "/post/bail-commercial-recours-exercer-preneur-a-lencontre-bailleur-cas-loyer-eleve",
  "/post/casier-judiciaire-comprendre-et-effacer",
  "/post/chirurgie-esthetique-ratee-indemnisation",
  "/post/comment-assigner-l-état-en-responsabilité-pour-faute-lourde",
  "/post/comment-bien-préparer-mon-dossier-médical",
  "/post/comprendre-et-prévenir-la-responsabilité-pénale-du-dirigeant",
  "/post/contrôle-coercitif-reconnaître-agir",
  "/post/demander-une-ordonnance-de-protection-en-2025",
  "/post/durée-de-la-garde-à-vue-24h-48h-96h-combien-de-temps-maximum",
  "/post/dépôt-de-plainte-en-france-comment-porter-plainte-efficacement",
  "/post/feminicide-saint-raphael-edith-verite",
  "/post/garde-à-vue-et-casier-judiciaire-quelles-traces-sont-conservées",
  "/post/garde-à-vue-ou-audition-libre-différences-essentielles-à-connaître",
  "/post/indemnisation-civi-2025-guide-complet-pour-les-victimes-d-infractions",
  "/post/itt-pénale-définition-en-2025",
  "/post/l-abus-de-confiance-en-droit-français-ce-que-vous-devez-savoir-en-2025",
  "/post/l-aménagement-de-peine-comment-peut-il-s-appliquer",
  "/post/l-assignation-à-résidence-sous-surveillance-électronique-arse-comprendre",
  "/post/l-interdiction-de-gérer-une-sanction-professionnelle-pour-dirigeants-d-entreprises-en-difficulté",
  "/post/la-détention-domiciliaire-sous-surveillance-électronique-ddse-comprendre",
  "/post/la-garde-à-vue-définition-droits-et-conséquences",
  "/post/la-préméditation-en-droit-pénal-français-définition-et-conséquences-juridiques",
  "/post/le-pretium-doloris-guide-complet-pour-les-victimes-d-accidents",
  "/post/loi-badinter-85-comprendre-vos-droits-à-indemnisation-après-un-accident-de-la-route",
  "/post/ma-procédure-judiciaire-n-avance-pas-puis-je-obtenir-une-indemnisation-pour-ce-délai-déraisonnable",
  "/post/mes-droits-en-garde-a-vue",
  "/post/mis-en-cause-temoin-assiste-prevenu-accuse-differences",
  "/post/piéton-renversé-quel-est-le-montant-de-l-indemnisation",
  "/post/plaidoirie-pour-chahinez",
  "/post/prestation-compensatoire-comment-est-elle-calculée-guide-complet",
  "/post/proposition-de-loi-inceste-et-imprescriptibilité-le-cabinet-plouton-au-cœur-des-avancées-législati",
  "/post/qu-est-ce-qu-une-période-de-sureté",
  "/post/qu-est-ce-que-la-comparution-immédiate",
  "/post/qu-est-ce-que-le-bracelet-anti-rapprochement",
  "/post/que-faire-en-cas-d-arnaque-au-contrat-de-leasing-d-un-photocopieur-caisse-enregistreuse",
  "/post/que-se-passe-t-il-après-une-garde-à-vue",
  "/post/quelles-sont-les-principales-infractions-en-droit-pénal-des-affaires",
  "/post/responsabilité-du-fait-des-choses-quels-recours-en-cas-de-chute-d-objet-tombé-ou-d-équipement-déf",
  "/post/réforme-de-la-prescription-pénale-comprendre-les-délais-et-les-nouvelles-règles",
  "/post/sarci-ou-civi-indemnisation-victimes",
  "/post/sarvi-comment-récupérer-vos-dommages-et-intérêts-après-une-condamnation-pénale",
  "/post/sinistre-automobile-mon-assurance-de-véhicule-me-réclame-la-preuve-achat",
  "/post/traumatisme-cranien-accident-voiture",
]);

export function isResourcePath(path: string): boolean {
  return RESOURCE_PATHS.has(path);
}
