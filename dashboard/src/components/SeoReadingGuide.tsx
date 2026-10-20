// Les volumes nationaux ne mesurent pas l'audience accessible à un article.
// Le tableau conserve les observations sans transformer une formule top 3 en
// gain prédit ou en priorité éditoriale.
export function SeoReadingGuide() {
  return (
    <aside className="border border-line bg-panel px-4 py-3">
      <h2 className="text-[12px] font-semibold text-ink">Lire les requêtes</h2>
      <p className="mt-1 text-[12px] leading-relaxed text-muted">
        Les clics, impressions et positions décrivent la présence observée dans Google.
        Le volume DataForSEO est une estimation nationale mensuelle, pas un gain de clics
        accessible à cette page. Avant de prioriser une requête, vérifier son intention,
        sa pertinence pour le cabinet et les pages réellement affichées.
      </p>
      <p className="mt-1 font-mono text-[10.5px] text-dim">
        Le filtre position 5–15 / volume ≥ 100 sert à explorer les données ; il ne valide
        ni une opportunité ni une recommandation éditoriale.
      </p>
    </aside>
  );
}
