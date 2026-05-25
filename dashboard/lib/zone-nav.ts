import type { DataLens } from "@/lib/data-lens";

export const ZONES = [
  { href: "/activite", label: "Activité du site", lens: "live" as const },
  { href: "/google", label: "Google", lens: "gsc" as const },
  { href: "/croisement", label: "Croisement", lens: "cross" as const },
] as const;

/** Onglet zone actif (requêtes et fiches page rattachées à Google / Croisement). */
export function activeZonePath(pathname: string): string {
  if (pathname.startsWith("/activite")) return "/activite";
  if (
    pathname.startsWith("/google") ||
    pathname.startsWith("/queries")
  ) {
    return "/google";
  }
  if (pathname.startsWith("/croisement") || pathname.startsWith("/p/")) {
    return "/croisement";
  }
  return "";
}

export function lensForPath(pathname: string): DataLens | null {
  const z = activeZonePath(pathname);
  const found = ZONES.find((x) => x.href === z);
  return found?.lens ?? null;
}
