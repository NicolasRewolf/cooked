"use client";

import { usePathname } from "next/navigation";
import { Nav } from "./Nav";

export function Header() {
  const pathname = usePathname();
  if (pathname.startsWith("/login") || pathname.startsWith("/auth")) return null;

  return (
    <header className="sticky top-0 z-10 border-b border-neutral-200 bg-white/80 backdrop-blur dark:border-neutral-800 dark:bg-neutral-950/80">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3">
        <div className="flex items-baseline gap-2">
          <span className="text-sm font-semibold text-neutral-900 dark:text-neutral-100">Cooked</span>
          <span className="text-xs text-neutral-400">Articles ressources</span>
        </div>
        <Nav />
        <form action="/auth/signout" method="post">
          <button
            type="submit"
            className="text-xs text-neutral-500 hover:text-neutral-800 dark:hover:text-neutral-200"
          >
            Déconnexion
          </button>
        </form>
      </div>
    </header>
  );
}
