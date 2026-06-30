"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { useTransition } from "react";
import { PERIODS } from "@/lib/periods";
import { cn } from "@/lib/cn";
import type { Period } from "@/lib/types";

// Contrôle segmenté « instrument » : 28 j / 90 j.
const SHORT: Record<Period, string> = { rolling_28: "28 j", rolling_90: "90 j" };

export function PeriodSelector({ value }: { value: Period }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [pending, startTransition] = useTransition();

  function set(next: string) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("period", next);
    startTransition(() => router.push(`${pathname}?${params.toString()}`));
  }

  return (
    <div className={cn("inline-flex border border-line-strong", pending && "opacity-60")}>
      {PERIODS.map((p) => {
        const active = p.value === value;
        return (
          <button
            key={p.value}
            type="button"
            onClick={() => set(p.value)}
            disabled={pending}
            title={p.label}
            className={cn(
              "px-3 py-1.5 font-mono text-[11px] transition-colors",
              active ? "border-b-2 border-accent bg-white text-ink" : "text-faint hover:text-ink",
            )}
          >
            {SHORT[p.value] ?? p.label}
          </button>
        );
      })}
    </div>
  );
}
