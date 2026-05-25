"use client";

import Link from "next/link";
import { hrefWithPeriod } from "@/lib/period";
import { usePeriodFromUrl } from "@/lib/use-period-from-url";

export function NavLogo() {
  const period = usePeriodFromUrl();

  return (
    <Link
      href={hrefWithPeriod("/activite", period)}
      className="font-mono text-sm tracking-tight text-foreground"
    >
      cooked<span className="text-muted-foreground">/dashboard</span>
    </Link>
  );
}
