"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { cn } from "@/lib/cn";

const links = [
  { href: "/", label: "Articles Ressources" },
  { href: "/expertises", label: "Expertises" },
  { href: "/seo", label: "SEO · requêtes" },
  { href: "/lab", label: "Lab" },
];

// M2 — la Nav ne propage QUE `period` d'un onglet à l'autre (sauf défaut rolling_90).
export function Nav() {
  const pathname = usePathname();
  const periodQ = useSearchParams().get("period") === "rolling_28" ? "?period=rolling_28" : "";
  return (
    <nav aria-label="Navigation principale" className="order-last col-span-2 flex h-11 max-w-full items-stretch overflow-x-auto lg:order-none lg:h-14 lg:gap-1">
      {links.map((l) => {
        const active = pathname === l.href;
        return (
          <Link
            key={l.href}
            href={`${l.href}${periodQ}`}
            aria-current={active ? "page" : undefined}
            className={cn(
              "inline-flex shrink-0 items-center whitespace-nowrap border-b-2 px-2 text-xs font-semibold transition-colors sm:px-3.5 sm:text-[13px]",
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
