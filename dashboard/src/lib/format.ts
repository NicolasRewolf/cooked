// Formatage fr-FR centralisé (nombres, %, deltas). Dates → lib/dates.ts.

export { dateFr } from "@/lib/dates";

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

export interface Delta {
  pct: number | null;
  dir: "up" | "down" | "flat" | "na";
  label: string;
}

export function delta(n: number, prev: number): Delta {
  if (prev <= 0) return { pct: null, dir: "na", label: "—" };
  const p = ((n - prev) / prev) * 100;
  const dir = Math.abs(p) < 1 ? "flat" : p > 0 ? "up" : "down";
  const sign = p > 0 ? "+" : "";
  return { pct: p, dir, label: `${sign}${p.toFixed(0)} %` };
}

export function prettyPath(path: string): string {
  const slug = path.replace(/^\/post\//, "").replace(/^\//, "");
  const words = slug.replace(/-/g, " ").trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
}
