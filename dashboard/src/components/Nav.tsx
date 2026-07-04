"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { cn } from "@/lib/cn";

const links = [
  { href: "/", label: "Articles Ressources" },
  { href: "/expertises", label: "Expertises" },
  { href: "/seo", label: "SEO · requêtes" },
];

// M2 — la Nav ne propage QUE `period` d'un onglet à l'autre (sauf défaut rolling_90).
export function Nav() {
  const pathname = usePathname();
  const periodQ = useSearchParams().get("period") === "rolling_28" ? "?period=rolling_28" : "";
  return (
    <nav className="flex h-14 items-stretch gap-1">
      {links.map((l) => {
        const active = pathname === l.href;
        return (
          <Link
            key={l.href}
            href={`${l.href}${periodQ}`}
            className={cn(
              "inline-flex items-center border-b-2 px-3.5 text-[13px] font-semibold transition-colors",
              active ? "border-accent text-ink" : "border-transparent text-faint hover:text-ink",
            )}
          >
            {l.label}
          </Link>
        );
      })}
    </nav>
  );
}
