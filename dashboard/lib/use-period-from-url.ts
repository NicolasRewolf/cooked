"use client";

import { useSearchParams } from "next/navigation";
import {
  DEFAULT_PERIOD,
  isPeriodKind,
  type PeriodKind,
} from "@/lib/period";

export function usePeriodFromUrl(): PeriodKind {
  const searchParams = useSearchParams();
  const raw = searchParams.get("period");
  return raw && isPeriodKind(raw) ? raw : DEFAULT_PERIOD;
}
