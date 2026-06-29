// Formatage fr-FR centralisé (un seul endroit pour les nombres, %, dates, deltas).

const nf = new Intl.NumberFormat("fr-FR");

export function num(n: number | null | undefined): string {
  if (n == null) return "—";
  return nf.format(n);
}

export function pct(n: number | null | undefined, digits = 1): string {
  if (n == null) return "—";
  return `${n.toFixed(digits).replace(".", ",")} %`;
}

export function dec(n: number | null | undefined, digits = 1): string {
  if (n == null) return "—";
  return n.toFixed(digits).replace(".", ",");
}

export function seconds(n: number | null | undefined): string {
  if (n == null) return "—";
  return `${Math.round(n)} s`;
}

export function euros(n: number | null | undefined): string {
  if (n == null) return "—";
  return `${n.toFixed(2).replace(".", ",")} €`;
}

// "2026-06-29" -> "29/06/2026"
export function dateFr(iso: string | null | undefined): string {
  if (!iso) return "—";
  const [y, m, d] = iso.slice(0, 10).split("-");
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

export interface Delta {
  pct: number | null; // variation en %
  dir: "up" | "down" | "flat" | "na"; // na = pas de base de comparaison
  label: string; // ex "+12 %", "—"
}

// Delta N vs N-1. dir 'na' quand prev=0 (pas de base fiable, ex. tracker trop jeune).
export function delta(n: number, prev: number): Delta {
  if (prev <= 0) return { pct: null, dir: "na", label: "—" };
  const p = ((n - prev) / prev) * 100;
  const dir = Math.abs(p) < 1 ? "flat" : p > 0 ? "up" : "down";
  const sign = p > 0 ? "+" : "";
  return { pct: p, dir, label: `${sign}${p.toFixed(0)} %` };
}

// Slug d'article -> libellé lisible (fallback quand pas de titre).
export function prettyPath(path: string): string {
  const slug = path.replace(/^\/post\//, "").replace(/^\//, "");
  const words = slug.replace(/-/g, " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}
