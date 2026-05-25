import { Suspense } from "react";
import { NavLinks } from "@/components/nav-links";
import { NavLogo } from "@/components/nav-logo";

/** Barre haute : marque + choix de la zone (pas de période ici). */
export function Nav() {
  return (
    <nav className="border-b border-border bg-surface/80 backdrop-blur supports-[backdrop-filter]:bg-surface/60">
      <div className="mx-auto flex h-12 max-w-6xl items-center justify-between px-6">
        <Suspense fallback={null}>
          <NavLogo />
        </Suspense>
        <Suspense fallback={null}>
          <NavLinks />
        </Suspense>
      </div>
    </nav>
  );
}
