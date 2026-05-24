"use client";

import Link from "next/link";
import { hrefWithPeriod } from "@/lib/period";
import { usePeriodFromUrl } from "@/lib/use-period-from-url";

const LINKS: { href: string; label: string }[] = [
  { href: "/", label: "Vue d'ensemble" },
  { href: "/pages", label: "Pages" },
  { href: "/queries", label: "Requêtes" },
  { href: "/health", label: "Pipeline" },
];

export function NavLinks() {
  const period = usePeriodFromUrl();

  return (
    <div className="flex items-center gap-6 text-sm text-muted-foreground">
      {LINKS.map(({ href, label }) => (
        <Link
          key={href}
          href={hrefWithPeriod(href, period)}
          className="hover:text-foreground transition-colors"
        >
          {label}
        </Link>
      ))}
    </div>
  );
}
