"use client";

// D6 — machine d'état de vue partagée des tableaux : tri (+ filtres optionnels)
// initialisés DEPUIS l'URL (reload = état restauré), puis reflétés dans l'URL via
// replaceUrlParams (AUCUN refetch serveur — voir lib/url.ts). Init lazy : lu une
// seule fois ; le remount sur changement de route/période le relit. Le bouton
// Retour du navigateur restaure la vue car on revient sur une entrée d'historique
// porteuse de ces params (une fiche est une AUTRE route → remount → ré-init).
// Couvre le cas complet (Resources : filtres + tri, débounce 300 ms pour la
// recherche) et le sous-ensemble (Expertises : tri seul, écriture immédiate).

import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { replaceUrlParams } from "@/lib/url";

/** Lecture minimale des params d'URL — satisfait ReadonlyURLSearchParams (Next)
 *  et URLSearchParams (tests). */
export interface UrlParamsReader {
  get(name: string): string | null;
}

export type SortDir = "asc" | "desc";

/** Init du tri depuis l'URL : `sort` absent → clé par défaut ; `dir` ≠ "asc" → desc. */
export function initSortFromUrl(
  sp: UrlParamsReader,
  defaultSortKey: string,
): { sortKey: string; sortDir: SortDir } {
  return {
    sortKey: sp.get("sort") ?? defaultSortKey,
    sortDir: sp.get("dir") === "asc" ? "asc" : "desc",
  };
}

/** Sérialisation du tri → URL : les valeurs par défaut sont omises (null = retiré). */
export function sortParamsToUrl(
  sortKey: string,
  sortDir: SortDir,
  defaultSortKey: string,
): Record<string, string | null> {
  return {
    sort: sortKey === defaultSortKey ? null : sortKey,
    dir: sortDir === "desc" ? null : sortDir,
  };
}

export interface FiltersSpec<F> {
  /** Lit l'état initial des filtres depuis l'URL (fonction de portée MODULE :
   *  son identité doit être stable entre les rendus). */
  init: (sp: UrlParamsReader) => F;
  /** Sérialise les filtres → params d'URL ; null/"" = valeur par défaut, retirée
   *  (fonction de portée module, identité stable). */
  toUrl: (f: F) => Record<string, string | null>;
}

export function useTableViewState<F = Record<string, never>>(opts: {
  defaultSortKey: string;
  filters?: FiltersSpec<F>;
  /** > 0 ⇒ écriture URL débouncée (recherche au clavier) ; absent ⇒ immédiate. */
  debounceMs?: number;
}) {
  const { defaultSortKey, debounceMs } = opts;
  const filtersToUrl = opts.filters?.toUrl;
  const searchParams = useSearchParams();

  const [filters, setFilters] = useState<F>(() =>
    opts.filters ? opts.filters.init(searchParams) : ({} as F),
  );
  const [sortKey, setSortKey] = useState(() => initSortFromUrl(searchParams, defaultSortKey).sortKey);
  const [sortDir, setSortDir] = useState<SortDir>(
    () => initSortFromUrl(searchParams, defaultSortKey).sortDir,
  );

  // État de vue → URL. On saute le 1er run (l'URL reflète déjà l'init).
  const firstRun = useRef(true);
  useEffect(() => {
    if (firstRun.current) {
      firstRun.current = false;
      return;
    }
    const write = () =>
      replaceUrlParams({
        ...(filtersToUrl ? filtersToUrl(filters) : {}),
        ...sortParamsToUrl(sortKey, sortDir, defaultSortKey),
      });
    if (!debounceMs) {
      write();
      return;
    }
    const t = setTimeout(write, debounceMs);
    return () => clearTimeout(t);
  }, [filters, sortKey, sortDir, filtersToUrl, defaultSortKey, debounceMs]);

  function setFilter<K extends keyof F>(key: K, value: F[K]) {
    setFilters((f) => ({ ...f, [key]: value }));
  }

  function onSortChange(key: string, dir: SortDir) {
    setSortKey(key);
    setSortDir(dir);
  }

  return { sortKey, sortDir, onSortChange, filters, setFilter };
}
