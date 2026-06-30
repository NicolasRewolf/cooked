"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/cn";

const links = [
  { href: "/", label: "Synthèse" },
  { href: "/seo", label: "SEO · requêtes" },
];

export function Nav() {
  const pathname = usePathname();
  return (
    <nav className="flex h-14 items-stretch gap-1">
      {links.map((l) => {
        const active = pathname === l.href;
        return (
          <Link
            key={l.href}
            href={l.href}
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
