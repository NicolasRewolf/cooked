// Types dashboard — dérivés des schémas Zod (C4) + types UI purs.

export type {
  Annotation,
  ArticleDetail,
  AssistedQuarter,
  AssistedRow,
  CohortsResult,
  ExpertiseKpis,
  ExpertiseRow,
  HonorairesFunnel,
  InterventionEffect,
  Period,
  ResourceKpis,
  ResourceRow,
  ResourcesTrend,
  SeoKpis,
  SeoQueryRow,
} from "@/data/rpc-schemas";

// Marqueur PLAT pour TrendChart — JAMAIS de fonction dans les props (frontière RSC serveur→client).
export interface TrendMarker {
  index: number;
  label: string;
  kind: string;
}

// Alias historiques (cohortes).
export type Cohort = import("@/data/rpc-schemas").CohortsResult["cohorts"][number];
