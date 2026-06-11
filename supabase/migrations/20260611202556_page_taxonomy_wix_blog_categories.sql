-- Sprint 38 reprise (11/06/2026) — catégorie Wix Blog enfin renseignée.
-- Source : API Wix Blog (ListPosts filtré sur la catégorie
-- « Ressources et notions juridiques », id 9477320f-5902-40e9-ace3-b0e3b6b8b51f,
-- site Cabinet Plouton 0870235c-b92d-4a69-a2f4-25a976ae5f0c) — 55 posts au
-- 11/06/2026 sur 411 publiés. Remplace l'ancien plan « scraper le hub
-- /comprendre-le-droit » (item P2 roadmap).
-- Convention : un post multi-catégories qui contient « Ressources » est
-- 'ressource' ; tout autre post publié observé dans le trafic est 'classique'.
-- ⚠️ La colonne source reste la provenance du THEME (slug_heuristic/manual) ;
-- la provenance de category est toujours wix_api (documenté ici et CLAUDE.md).

WITH res(slug) AS (VALUES
('echelle-de-glasgow'),('arnaque-en-ligne-victime-escroquerie-recours'),('indemnisation-vaccin-effets-indesirables-graves-oniam'),('indemnisation-accident-moto-motard'),('chirurgie-esthetique-ratee-indemnisation'),('prestation-compensatoire-comment-est-elle-calculée-guide-complet'),('responsabilité-du-fait-des-choses-quels-recours-en-cas-de-chute-d-objet-tombé-ou-d-équipement-déf'),('ma-procédure-judiciaire-n-avance-pas-puis-je-obtenir-une-indemnisation-pour-ce-délai-déraisonnable'),('auto-entrepreneur-victime-d-un-accident-comment-justifier-une-perte-de-revenus-ou-d-exploitation'),('que-faire-en-cas-d-arnaque-au-contrat-de-leasing-d-un-photocopieur-caisse-enregistreuse'),('comment-assigner-l-état-en-responsabilité-pour-faute-lourde'),('accident-voyage-organise-etranger-responsabilite-agence'),('proposition-de-loi-inceste-et-imprescriptibilité-le-cabinet-plouton-au-cœur-des-avancées-législati'),('sarvi-ou-civi-indemnisation-victimes'),('accident-médical-oniam-dans-quels-cas-pouvez-vous-être-indemnisé'),('accident-médical-oniam'),('au-cœur-de-la-justice-restaurative-retour-sur-une-journée-d-étude-à-bordeaux'),('feminicide-saint-raphael-edith-verite'),('contrôle-coercitif-reconnaître-agir'),('plaidoirie-pour-chahinez'),('mis-en-cause-temoin-assiste-prevenu-accuse-differences'),('bail-commercial-la-révision-du-loyer-comment-est-ce-que-cela-fonctionne'),('demander-une-ordonnance-de-protection-en-2025'),('l-assignation-à-résidence-sous-surveillance-électronique-arse-comprendre'),('la-détention-domiciliaire-sous-surveillance-électronique-ddse-comprendre'),('l-interdiction-de-gérer-une-sanction-professionnelle-pour-dirigeants-d-entreprises-en-difficulté'),('abandon-de-poste-quels-risques'),('sarvi-comment-récupérer-vos-dommages-et-intérêts-après-une-condamnation-pénale'),('itt-pénale-définition-en-2025'),('loi-badinter-85-comprendre-vos-droits-à-indemnisation-après-un-accident-de-la-route'),('dépôt-de-plainte-en-france-comment-porter-plainte-efficacement'),('durée-de-la-garde-à-vue-24h-48h-96h-combien-de-temps-maximum'),('la-préméditation-en-droit-pénal-français-définition-et-conséquences-juridiques'),('garde-à-vue-ou-audition-libre-différences-essentielles-à-connaître'),('indemnisation-civi-2025-guide-complet-pour-les-victimes-d-infractions'),('mes-droits-en-garde-a-vue'),('l-abus-de-confiance-en-droit-français-ce-que-vous-devez-savoir-en-2025'),('que-se-passe-t-il-après-une-garde-à-vue'),('sinistre-automobile-mon-assurance-de-véhicule-me-réclame-la-preuve-achat'),('comprendre-et-prévenir-la-responsabilité-pénale-du-dirigeant'),('casier-judiciaire-comprendre-et-effacer'),('qu-est-ce-qu-une-période-de-sureté'),('la-garde-à-vue-définition-droits-et-conséquences'),('qu-est-ce-que-le-bracelet-anti-rapprochement'),('garde-à-vue-et-casier-judiciaire-quelles-traces-sont-conservées'),('comment-bien-préparer-mon-dossier-médical'),('accident-médical-responsabilité-médicale-et-aléa-thérapeutique'),('piéton-renversé-quel-est-le-montant-de-l-indemnisation'),('le-pretium-doloris-guide-complet-pour-les-victimes-d-accidents'),('l-aménagement-de-peine-comment-peut-il-s-appliquer'),('traumatisme-cranien-accident-voiture'),('qu-est-ce-que-la-comparution-immédiate'),('quelles-sont-les-principales-infractions-en-droit-pénal-des-affaires'),('bail-commercial-recours-exercer-preneur-a-lencontre-bailleur-cas-loyer-eleve'),('réforme-de-la-prescription-pénale-comprendre-les-délais-et-les-nouvelles-règles'),('accident-du-travail-comment-obtenir-votre-indemnisation')
)
INSERT INTO public.page_taxonomy (path, category, source)
SELECT '/post/' || slug, 'ressource', 'wix_api' FROM res
ON CONFLICT (path) DO UPDATE
  SET category = 'ressource', updated_at = now();

-- Tout autre post publié vu dans le trafic = classique (par différence).
INSERT INTO public.page_taxonomy (path, category, source)
SELECT DISTINCT e.path, 'classique', 'wix_api'
FROM public.events_human e
WHERE e.path LIKE '/post/%'
  AND NOT EXISTS (SELECT 1 FROM public.page_taxonomy pt
                  WHERE pt.path = e.path AND pt.category IS NOT NULL)
ON CONFLICT (path) DO UPDATE
  SET category = 'classique', updated_at = now()
  WHERE page_taxonomy.category IS NULL;
