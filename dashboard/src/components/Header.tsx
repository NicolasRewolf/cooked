"use client";

import { Suspense } from "react";
import { usePathname } from "next/navigation";
import { Nav } from "./Nav";

export function Header() {
  const pathname = usePathname();
  if (pathname.startsWith("/login") || pathname.startsWith("/auth")) return null;

  return (
    <header className="sticky top-0 z-40 border-b border-line-strong bg-white/90 backdrop-blur">
      <div className="mx-auto grid max-w-[1240px] grid-cols-[minmax(0,1fr)_auto] items-center gap-x-3 px-4 pt-2 lg:flex lg:h-14 lg:justify-between lg:gap-6 lg:px-8 lg:pt-0">
        <div className="flex items-center gap-3">
          {/* marque rewolf : « R » inversé (rewolf = flower à l'envers) */}
          <span
            className="inline-flex h-[26px] w-[26px] items-center justify-center border-[1.5px] border-accent font-mono text-[13px] font-bold text-accent"
            style={{ transform: "scaleX(-1)" }}
            aria-hidden
          >
            R
          </span>
          <span className="text-[15px] font-semibold tracking-[-0.01em]">Cooked</span>
          <span className="font-mono text-[11px] text-faint">jplouton-avocat.fr</span>
        </div>

        {/* Nav lit useSearchParams (period) → Suspense requis (build prod). */}
        <Suspense fallback={<nav className="order-last col-span-2 h-11 lg:order-none lg:h-14" aria-hidden />}>
          <Nav />
        </Suspense>

        <form action="/auth/signout" method="post">
          <button type="submit" className="text-xs text-faint transition-colors hover:text-ink">
            Déconnexion
          </button>
        </form>
      </div>
      <p className="border-t border-line bg-warn-tint px-4 py-2 text-center text-xs text-ink-2">
        Actualisation des anciens indicateurs suspendue le 4 novembre 2026.
        Les dates affichées restent celles des derniers calculs. La collecte continue.
      </p>
    </header>
  );
}
