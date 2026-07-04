"use client";

import { Suspense } from "react";
import { usePathname } from "next/navigation";
import { Nav } from "./Nav";

export function Header() {
  const pathname = usePathname();
  if (pathname.startsWith("/login") || pathname.startsWith("/auth")) return null;

  return (
    <header className="sticky top-0 z-40 border-b border-line-strong bg-white/90 backdrop-blur">
      <div className="mx-auto flex h-14 max-w-[1240px] items-center justify-between gap-6 px-8">
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
        <Suspense fallback={<nav className="flex h-14 items-stretch gap-1" aria-hidden />}>
          <Nav />
        </Suspense>

        <form action="/auth/signout" method="post">
          <button type="submit" className="text-xs text-faint transition-colors hover:text-ink">
            Déconnexion
          </button>
        </form>
      </div>
    </header>
  );
}
