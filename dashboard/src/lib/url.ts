// M2 — synchronise l'état de vue (filtres, tri) avec l'URL SANS navigation, via
// window.history.replaceState natif (supporté par Next 16, s'intègre au routeur).
// C'EST le point clé perf : router.replace re-déclencherait le rendu SERVEUR de la
// page force-dynamic (tempête de refetchs à chaque frappe) ; replaceState ne le fait
// PAS. On préserve les params existants (ex. `period`, géré ailleurs) et on retire
// les clés à `null`/"" pour garder des URLs propres.
export function replaceUrlParams(updates: Record<string, string | null>) {
  if (typeof window === "undefined") return;
  const sp = new URLSearchParams(window.location.search);
  for (const [k, v] of Object.entries(updates)) {
    if (v == null || v === "") sp.delete(k);
    else sp.set(k, v);
  }
  const qs = sp.toString();
  const url = qs ? `${window.location.pathname}?${qs}` : window.location.pathname;
  window.history.replaceState(window.history.state, "", url);
}
