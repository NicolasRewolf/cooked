import Link from "next/link";
import { Suspense } from "react";
import { NavLinks } from "@/components/nav-links";
import { NavLogo } from "@/components/nav-logo";
import { PeriodSelector } from "@/components/period-selector";

export function Nav() {
  return (
    <nav className="border-b border-border bg-surface/80 backdrop-blur supports-[backdrop-filter]:bg-surface/60">
      <div className="mx-auto flex max-w-6xl flex-col gap-3 px-6 py-3">
        <div className="flex h-10 items-center justify-between">
          <Suspense fallback={null}>
            <NavLogo />
          </Suspense>
          <Suspense fallback={null}>
            <NavLinks />
          </Suspense>
        </div>
        <Suspense fallback={null}>
          <PeriodSelector />
        </Suspense>
      </div>
    </nav>
  );
}
