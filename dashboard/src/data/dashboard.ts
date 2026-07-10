import "server-only";

import { callRpc } from "@/data/call-rpc";
import {
  annotationRowsSchema,
  articleDetailSchema,
  assistedQuarterSchema,
  assistedRowsSchema,
  cohortsResultSchema,
  expertiseKpisSchema,
  expertiseRowsSchema,
  interventionEffectSchema,
  resourceKpisSchema,
  resourceRowsSchema,
  seoKpisSchema,
  seoQueryRowsSchema,
  type Annotation,
  type ArticleDetail,
  type AssistedQuarter,
  type AssistedRow,
  type CohortsResult,
  type ExpertiseKpis,
  type ExpertiseRow,
  type InterventionEffect,
  type Period,
  type ResourceKpis,
  type ResourceRow,
  type SeoKpis,
  type SeoQueryRow,
} from "@/data/rpc-schemas";

export async function getResourcesOverview(period: Period): Promise<ResourceRow[]> {
  return callRpc("dashboard_resources_overview", { period_kind: period, max_rows: 100 }, resourceRowsSchema);
}

export async function getResourcesKpis(period: Period): Promise<ResourceKpis | null> {
  return callRpc("dashboard_resources_kpis", { period_kind: period }, resourceKpisSchema);
}

export async function getExpertisesOverview(period: Period): Promise<ExpertiseRow[]> {
  return callRpc("dashboard_expertises_overview", { period_kind: period, max_rows: 100 }, expertiseRowsSchema);
}

export async function getExpertisesKpis(period: Period): Promise<ExpertiseKpis | null> {
  return callRpc("dashboard_expertises_kpis", { period_kind: period }, expertiseKpisSchema);
}

export async function getSeoByQuery(
  period: Period,
  opts: { minVolume?: number; maxRows?: number } = {},
): Promise<SeoQueryRow[]> {
  return callRpc(
    "dashboard_seo_by_query",
    {
      period_kind: period,
      scope: "ressource",
      min_volume: opts.minVolume ?? 0,
      max_rows: opts.maxRows ?? 200,
    },
    seoQueryRowsSchema,
  );
}

export async function getSeoKpis(period: Period): Promise<SeoKpis | null> {
  return callRpc(
    "dashboard_seo_kpis",
    { period_kind: period, scope: "ressource" },
    seoKpisSchema,
  );
}

export async function getResourcesAssisted(period: Period): Promise<AssistedRow[]> {
  return callRpc("dashboard_resources_assisted", { period_kind: period }, assistedRowsSchema);
}

export async function getArticleDetail(path: string, period: Period): Promise<ArticleDetail | null> {
  const detail = await callRpc(
    "dashboard_article_detail",
    { p_path: path, period_kind: period },
    articleDetailSchema.nullable(),
  );
  return detail;
}

export async function getAnnotations(period: Period): Promise<Annotation[]> {
  return callRpc("dashboard_annotations", { period_kind: period }, annotationRowsSchema);
}

export async function getInterventionEffect(path: string, day: string): Promise<InterventionEffect> {
  return callRpc("dashboard_intervention_effect", { p_path: path, p_day: day }, interventionEffectSchema);
}

export async function getInterventionEffects(
  path: string,
  interventions: { day: string; label: string }[],
): Promise<{ day: string; label: string; effect: InterventionEffect }[]> {
  return Promise.all(
    interventions.map(async (it) => ({
      label: it.label,
      day: it.day,
      effect: await getInterventionEffect(path, it.day),
    })),
  );
}

export async function getResourcesCohorts(): Promise<CohortsResult> {
  return callRpc("dashboard_resources_cohorts", undefined, cohortsResultSchema);
}

export async function getAssistedQuarter(): Promise<AssistedQuarter> {
  return callRpc("dashboard_assisted_quarter", undefined, assistedQuarterSchema);
}
