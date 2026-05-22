/**
 * lib/cooked.ts — Single point of contact with the Cooked Supabase backend.
 *
 * ⚠️ READ-ONLY, SERVER-ONLY ⚠️
 *
 * Garde-fous silo (cf. brief Nicolas) :
 *  1. `import "server-only"` empêche l'import depuis un Client Component
 *     ou n'importe quel code qui finirait dans le bundle navigateur.
 *  2. Toutes les requêtes passent par .rpc() sur des fonctions Postgres
 *     déjà publiées et figées côté Cooked. Aucun INSERT/UPDATE/DELETE,
 *     aucun DDL, aucune migration depuis ce dashboard.
 *  3. Pas d'export du client Supabase brut — seulement des wrappers
 *     nommés, typés et limités en surface.
 */
import "server-only";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const SUPABASE_URL =
  process.env.SUPABASE_URL ?? "https://mxycmjkeotrycyneacje.supabase.co";
const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY;

if (!SUPABASE_SECRET_KEY) {
  throw new Error(
    "SUPABASE_SECRET_KEY env var missing. Set it in .env.local (server-only, never NEXT_PUBLIC_)."
  );
}

// Singleton — pas de session persistante, pas d'auth refresh : on est en
// service_role direct, server-side, par requête.
let _client: SupabaseClient | null = null;
function client(): SupabaseClient {
  if (_client) return _client;
  _client = createClient(SUPABASE_URL, SUPABASE_SECRET_KEY!, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  return _client;
}

// ============================================================
// Types — alignés sur les signatures RPCs Cooked (Sprint 33)
// ============================================================

export type PipelineHealth = {
  status: "healthy" | "degraded" | "critical";
  snapshot_refreshed_at: string | null;
  snapshot_age_hours: number | null;
  cron_last_status: string | null;
  cron_last_run: string | null;
  cron_age_hours: number | null;
  last_event_at: string | null;
  last_event_age_minutes: number | null;
  events_last_60min: number;
  gsc_last_day: string | null;
  gsc_data_age_days: number | null;
  gsc_last_ingest: string | null;
  gsc_ingest_age_hours: number | null;
  issues: string[];
};

export type GscPagesOverviewRow = {
  path: string;
  gsc_clicks_28d: number;
  gsc_impressions_28d: number;
  gsc_position_avg_28d: number | null;
  gsc_ctr_pct_28d: number | null;
  cooked_sessions_28d: number;
  cooked_dwell_avg_s_28d: number | null;
  cooked_bounce_rate_28d: number | null;
  cooked_conversions_28d: number;
  cooked_pogo_rate_28d: number | null;
  has_cooked_data: boolean;
};

export type GscPagePerformance = {
  path: string;
  gsc_clicks_28d: number;
  gsc_impressions_28d: number;
  gsc_position_avg_28d: number | null;
  gsc_ctr_pct_28d: number | null;
  cooked_sessions_28d: number;
  cooked_views_28d: number;
  cooked_unique_visitors_28d: number;
  cooked_bounce_rate_28d: number | null;
  cooked_dwell_avg_s_28d: number | null;
  cooked_scroll_median_28d: number | null;
  cooked_phone_clicks_28d: number;
  cooked_booking_clicks_28d: number;
  cooked_pogo_rate_28d: number | null;
  cooked_google_sessions_28d: number;
  lcp_p75_ms: number | null;
  inp_p75_ms: number | null;
  cls_p75: number | null;
  top_referrer_28d: string | null;
  device_split_28d: Record<string, number> | null;
};

export type GscTopQueryRow = {
  query: string;
  clicks: number;
  impressions: number;
  position_avg: number | null;
  ctr_pct: number | null;
  days_in_period: number;
};

export type SiteContextRow = {
  sessions_28d: number;
  bounce_rate_28d: number | null;
  sessions_vs_prev: number | null;
  bounce_vs_prev: number | null;
  top_sources: Record<string, unknown>;
};

export type SiteKpisCompare = {
  period_n_start: string;
  period_n_end: string;
  sessions_n: number;
  pageviews_n: number;
  phone_clicks_n: number;
  form_submits_n: number;
  macro_conversions_n: number;
  period_prev_start: string;
  period_prev_end: string;
  sessions_prev: number;
  pageviews_prev: number;
  phone_clicks_prev: number;
  form_submits_prev: number;
  macro_conversions_prev: number;
  sessions_delta_pct: number | null;
  pageviews_delta_pct: number | null;
  phone_clicks_delta_pct: number | null;
  form_submits_delta_pct: number | null;
  macro_conversions_delta_pct: number | null;
};

// ============================================================
// Wrappers RPCs — chaque fonction = 1 RPC Cooked publiée
// ============================================================

/**
 * Top pages SEO 28j × comportement Cooked.
 * RPC : public.gsc_pages_overview(max_rows int)
 */
export async function gscPagesOverview(
  maxRows = 30
): Promise<GscPagesOverviewRow[]> {
  const { data, error } = await client().rpc("gsc_pages_overview", {
    max_rows: maxRows,
  });
  if (error) throw new Error(`gsc_pages_overview: ${error.message}`);
  return (data ?? []) as GscPagesOverviewRow[];
}

/**
 * Fiche complète d'une page (GSC + Cooked + CWV) sur 28j.
 * RPC : public.gsc_page_performance(target_path text)
 */
export async function gscPagePerformance(
  targetPath: string
): Promise<GscPagePerformance | null> {
  const { data, error } = await client().rpc("gsc_page_performance", {
    target_path: targetPath,
  });
  if (error) throw new Error(`gsc_page_performance: ${error.message}`);
  const rows = (data ?? []) as GscPagePerformance[];
  return rows[0] ?? null;
}

/**
 * Top requêtes GSC qui amènent sur une page.
 * RPC : public.gsc_top_queries_for_path(target_path text, days_back int, max_rows int)
 */
export async function gscTopQueriesForPath(
  targetPath: string,
  daysBack = 28,
  maxRows = 20
): Promise<GscTopQueryRow[]> {
  const { data, error } = await client().rpc("gsc_top_queries_for_path", {
    target_path: targetPath,
    days_back: daysBack,
    max_rows: maxRows,
  });
  if (error) throw new Error(`gsc_top_queries_for_path: ${error.message}`);
  return (data ?? []) as GscTopQueryRow[];
}

/**
 * État de santé du pipeline (4 axes : snapshot, cron, ingestion events, GSC).
 * RPC : public.refresh_pipeline_health()
 */
export async function pipelineHealth(): Promise<PipelineHealth> {
  const { data, error } = await client().rpc("refresh_pipeline_health");
  if (error) throw new Error(`refresh_pipeline_health: ${error.message}`);
  const rows = (data ?? []) as PipelineHealth[];
  if (!rows[0]) throw new Error("refresh_pipeline_health returned no rows");
  return rows[0];
}

/**
 * Contexte site-wide 28j.
 * RPC : public.site_context_export()
 */
export async function siteContext(): Promise<SiteContextRow | null> {
  const { data, error } = await client().rpc("site_context_export");
  if (error) throw new Error(`site_context_export: ${error.message}`);
  const rows = (data ?? []) as SiteContextRow[];
  return rows[0] ?? null;
}

/**
 * KPIs business N vs N-1 (sessions, pageviews, phone, form_submit, macro).
 * RPC : public.site_kpis_compare(period_days int)
 */
export async function siteKpisCompare(
  periodDays = 28
): Promise<SiteKpisCompare> {
  const { data, error } = await client().rpc("site_kpis_compare", {
    period_days: periodDays,
  });
  if (error) throw new Error(`site_kpis_compare: ${error.message}`);
  const rows = (data ?? []) as SiteKpisCompare[];
  if (!rows[0]) throw new Error("site_kpis_compare returned no rows");
  return rows[0];
}
