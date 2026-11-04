"use client";

import { usePathname } from "next/navigation";

export function Header() {
  const pathname = usePathname();
  if (pathname.startsWith("/login") || pathname.startsWith("/auth")) return null;

  return (
    <header className="border-b border-line bg-panel">
      <div className="mx-auto flex h-16 max-w-[1440px] items-center justify-between gap-4 px-4 sm:px-8 lg:px-10">
        <div className="flex min-w-0 items-center gap-3">
          <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-accent" aria-hidden="true">
            <svg viewBox="0 0 24 24" fill="none" className="size-5 text-white">
              <path d="M6 16V11M12 16V6M18 16V9" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
            </svg>
          </span>
          <span className="text-lg font-semibold tracking-tight">Cooked</span>
          <span aria-hidden="true" className="mx-1 hidden h-5 w-px bg-line sm:block" />
          <span className="hidden truncate text-sm text-muted sm:block">jplouton-avocat.fr</span>
        </div>
        <form action="/auth/signout" method="post">
          <button type="submit" className="inline-flex min-h-10 items-center gap-2 rounded-lg px-3 text-sm text-muted transition-colors duration-150 hover:bg-paper hover:text-ink">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="size-4" aria-hidden="true">
              <path d="M9 4H5v16h4M14 8l4 4-4 4M9 12h9" />
            </svg>
            Déconnexion
          </button>
        </form>
      </div>
    </header>
  );
}
