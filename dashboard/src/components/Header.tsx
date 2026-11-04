"use client";

import { usePathname } from "next/navigation";

export function Header() {
  const pathname = usePathname();
  if (pathname.startsWith("/login") || pathname.startsWith("/auth")) return null;

  return (
    <header className="border-b border-line bg-panel">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-5 py-4 sm:px-8">
        <span className="text-sm font-semibold tracking-tight">Cooked</span>
        <form action="/auth/signout" method="post">
          <button type="submit" className="text-sm text-muted transition-colors hover:text-ink">
            Déconnexion
          </button>
        </form>
      </div>
    </header>
  );
}
