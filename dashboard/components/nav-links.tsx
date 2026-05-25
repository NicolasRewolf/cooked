"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { hrefWithPeriod } from "@/lib/period";
import { usePeriodFromUrl } from "@/lib/use-period-from-url";
import { activeZonePath, ZONES } from "@/lib/zone-nav";
import { cn } from "@/lib/utils";

const UTILITY_LINKS = [{ href: "/health", label: "Pipeline" }] as const;

export function NavLinks() {
  const pathname = usePathname();
  const period = usePeriodFromUrl();
  const active = activeZonePath(pathname);

  return (
    <div className="flex items-center gap-2">
      <div
        className="flex items-center gap-0.5 rounded-md border border-border bg-canvas/60 p-0.5"
        role="tablist"
        aria-label="Source de données"
      >
        {ZONES.map(({ href, label }) => (
          <Link
            key={href}
            href={hrefWithPeriod(href, period)}
            role="tab"
            aria-selected={active === href}
            className={cn(
              "rounded px-3 py-1.5 text-sm transition-colors",
              active === href
                ? "bg-surface font-medium text-foreground shadow-xs"
                : "text-muted-foreground hover:text-foreground"
            )}
          >
            {label}
          </Link>
        ))}
      </div>
      {UTILITY_LINKS.map(({ href, label }) => (
        <Link
          key={href}
          href={href}
          className={cn(
            "px-2 py-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground",
            pathname.startsWith(href) && "font-medium text-foreground"
          )}
        >
          {label}
        </Link>
      ))}
    </div>
  );
}
