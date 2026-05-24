/**
 * lib/cooked.ts — Single point of contact with the Cooked Supabase backend.
 *
 * ⚠️ READ-ONLY, SERVER-ONLY ⚠️
 */
import "server-only";

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { PeriodKind } from "@/lib/period";

const SUPABASE_URL =
  process.env.SUPABASE_URL ?? "https://mxycmjkeotrycyneacje.supabase.co";
const SUPABASE_SECRET_KEY = process.env.SUPABASE_SECRET_KEY;

if (!SUPABASE_SECRET_KEY) {
  throw new Error(
    "SUPABASE_SECRET_KEY env var missing. Set it in .env.local (server-only, never NEXT_PUBLIC_)."
  );
}

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
// Types — alignés sur les signatures RPCs Cooked (Sprint 33+)
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
  dfs_last_synced_at: string | null;
  dfs_row_count: number;
  dfs_sync_age_hours: number | null;
  issues: string[];
};

export type TopContactPageRow = {
  path: string;
  cooked_contacts: number;
  cooked_phone_clicks: number;
  cooked_form_submits: number;
  gsc_clicks: number;
  cooked_sessions: number;
};

export type PagesOverviewRow = {
  path: string;
  gsc_clicks: number;
  gsc_impressions: number;
  gsc_position_avg: number | null;
  gsc_ctr_pct: number | null;
  cooked_sessions: number;
  cooked_dwell_avg_s: number | null;
  cooked_bounce_rate: number | null;
  cooked_phone_clicks: number;
  cooked_form_submits: number;
  cooked_contacts: number;
  cooked_booking_intent: number;
  cooked_pogo_rate: number | null;
  has_cooked_data: boolean;
};

export type GscPagePerformance = {
  path: string;
  gsc_clicks: number;
  gsc_impressions: number;
  gsc_position_avg: number | null;
  gsc_ctr_pct: number | null;
  cooked_sessions: number;
  cooked_views: number;
  cooked_unique_visitors: number;
  cooked_bounce_rate: number | null;
  cooked_dwell_avg_s: number | null;
  cooked_scroll_median: number | null;
  cooked_phone_clicks: number;
  cooked_form_submits: number;
  cooked_contacts: number;
  cooked_booking_intent: number;
  cooked_pogo_rate: number | null;
  cooked_google_sessions: number;
  lcp_p75_ms: number | null;
  inp_p75_ms: number | null;
  cls_p75: number | null;
  top_referrer: string | null;
  device_split: Record<string, number> | null;
};

export type GscTopQueryRow = {
  query: string;
  clicks: number;
  impressions: number;
  position_avg: number | null;
  ctr_pct: number | null;
  days_in_period: number;
};

export type SiteSeoFunnel = {
  period_start: string;
  period_end: string;
  impressions: number;
  clicks: number;
  google_sessions: number;
  macro_contacts: number;
  impr_to_click_pct: number | null;
  click_to_session_pct: number | null;
  session_to_contact_pct: number | null;
  overall_impr_to_contact_pct: number | null;
};

export type GscGlobalQueryRow = {
  query: string;
  clicks: number;
  impressions: number;
  position_avg: number | null;
  ctr_pct: number | null;
  nb_pages_targeted: number;
  top_page: string | null;
  top_page_clicks: number | null;
  volume_fr: number | null;
  cpc: number | null;
  click_yield_pct: number | null;
};

export type GscDfsOpportunityRow = {
  query: string;
  our_position: number;
  our_clicks: number;
  our_impressions: number;
  our_ctr_pct: number | null;
  volume_fr: number;
  cpc: number | null;
  estimated_ctr_pos_1: number;
  lost_potential: number;
  top_page: string | null;
};

export type SiteContextRow = {
  sessions_28d: number;
  bounce_rate_28d: number | null;
  sessions_vs_prev: number | null;
  bounce_vs_prev: number | null;
  top_sources: Record<string, unknown>;
};

export type PulseQuadrant =
  | "up_up"
  | "up_down"
  | "down_up"
  | "down_down"
  | "neutral"
  | "no_signal";

export type PagePulseRow = {
  path: string;
  gsc_clicks_n: number;
  gsc_clicks_prev: number;
  gsc_delta_pct: number | null;
  cooked_sessions_n: number;
  cooked_sessions_prev: number | null;
  cooked_sessions_delta_pct: number | null;
  quadrant: PulseQuadrant;
};

export type GscDailyPoint = { day: string; clicks: number };
export type CookedDailyPoint = { day: string; sessions: number };

export type SitePulse = {
  period_kind: string;
  period_label_fr: string;
  gsc_period_start: string;
  gsc_period_end: string;
  cooked_period_start: string;
  cooked_period_end: string;
  gsc_clicks_n: number;
  gsc_clicks_prev: number;
  gsc_delta_pct: number | null;
  cooked_sessions_n: number;
  cooked_sessions_prev: number | null;
  cooked_sessions_delta_pct: number | null;
  quadrant: PulseQuadrant;
};

export type SiteKpisCompare = {
  period_kind: string;
  period_label_fr: string;
  period_n_start: string;
  period_n_end: string;
  tracker_first_seen: string | null;
  is_partial_period: boolean;
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
// Wrappers RPCs
// ============================================================

export async function topContactPages(
  periodKind: PeriodKind = "rolling_28",
  maxRows = 10
): Promise<TopContactPageRow[]> {
  const { data, error } = await client().rpc("top_contact_pages", {
    p_period_kind: periodKind,
    max_rows: maxRows,
  });
  if (error) throw new Error(`top_contact_pages: ${error.message}`);
  return (data ?? []) as TopContactPageRow[];
}

export async function pagesOverviewUnified(
  periodKind: PeriodKind = "rolling_28",
  maxRows = 1000
): Promise<PagesOverviewRow[]> {
  const { data, error } = await client().rpc("pages_overview_unified", {
    period_kind: periodKind,
    max_rows: maxRows,
  });
  if (error) throw new Error(`pages_overview_unified: ${error.message}`);
  return (data ?? []) as PagesOverviewRow[];
}

export async function gscPagePerformance(
  targetPath: string,
  periodKind: PeriodKind = "rolling_28"
): Promise<GscPagePerformance | null> {
  const { data, error } = await client().rpc("gsc_page_performance", {
    target_path: targetPath,
    period_kind: periodKind,
  });
  if (error) throw new Error(`gsc_page_performance: ${error.message}`);
  const rows = (data ?? []) as GscPagePerformance[];
  return rows[0] ?? null;
}

export async function gscTopQueriesForPath(
  targetPath: string,
  periodKind: PeriodKind = "rolling_28",
  maxRows = 20
): Promise<GscTopQueryRow[]> {
  const { data, error } = await client().rpc("gsc_top_queries_for_path", {
    target_path: targetPath,
    p_period_kind: periodKind,
    max_rows: maxRows,
  });
  if (error) throw new Error(`gsc_top_queries_for_path: ${error.message}`);
  return (data ?? []) as GscTopQueryRow[];
}

export async function pipelineHealth(): Promise<PipelineHealth> {
  const { data, error } = await client().rpc("refresh_pipeline_health");
  if (error) throw new Error(`refresh_pipeline_health: ${error.message}`);
  const rows = (data ?? []) as PipelineHealth[];
  if (!rows[0]) throw new Error("refresh_pipeline_health returned no rows");
  return rows[0];
}

export async function siteContext(): Promise<SiteContextRow | null> {
  const { data, error } = await client().rpc("site_context_export");
  if (error) throw new Error(`site_context_export: ${error.message}`);
  const rows = (data ?? []) as SiteContextRow[];
  return rows[0] ?? null;
}

export async function pagesPulse(
  periodKind: PeriodKind = "rolling_28",
  deltaThresholdPct = 5.0
): Promise<PagePulseRow[]> {
  const { data, error } = await client().rpc("pages_pulse", {
    period_kind: periodKind,
    delta_threshold_pct: deltaThresholdPct,
  });
  if (error) throw new Error(`pages_pulse: ${error.message}`);
  return (data ?? []) as PagePulseRow[];
}

export async function siteSeoFunnel(
  periodKind: PeriodKind = "rolling_28"
): Promise<SiteSeoFunnel> {
  const { data, error } = await client().rpc("site_seo_funnel", {
    period_kind: periodKind,
  });
  if (error) throw new Error(`site_seo_funnel: ${error.message}`);
  const rows = (data ?? []) as SiteSeoFunnel[];
  if (!rows[0]) throw new Error("site_seo_funnel returned no rows");
  return rows[0];
}

export async function gscTopQueriesGlobal(
  periodKind: PeriodKind = "rolling_28",
  maxRows = 100
): Promise<GscGlobalQueryRow[]> {
  const { data, error } = await client().rpc("gsc_top_queries_global", {
    period_kind: periodKind,
    max_rows: maxRows,
  });
  if (error) throw new Error(`gsc_top_queries_global: ${error.message}`);
  return (data ?? []) as GscGlobalQueryRow[];
}

export async function gscXDfsOpportunities(
  periodKind: PeriodKind = "rolling_28",
  minVolume = 100,
  positionMin = 5,
  positionMax = 15,
  maxRows = 30
): Promise<GscDfsOpportunityRow[]> {
  const { data, error } = await client().rpc("gsc_x_dfs_opportunities", {
    min_volume: minVolume,
    position_min: positionMin,
    position_max: positionMax,
    period_kind: periodKind,
    max_rows: maxRows,
  });
  if (error) throw new Error(`gsc_x_dfs_opportunities: ${error.message}`);
  return (data ?? []) as GscDfsOpportunityRow[];
}

export async function gscPageDailySeries(
  targetPath: string,
  daysBack = 56
): Promise<GscDailyPoint[]> {
  const { data, error } = await client().rpc("gsc_page_daily_series", {
    target_path: targetPath,
    days_back: daysBack,
  });
  if (error) throw new Error(`gsc_page_daily_series: ${error.message}`);
  return (data ?? []) as GscDailyPoint[];
}

export async function cookedPageDailySeries(
  targetPath: string,
  daysBack = 14
): Promise<CookedDailyPoint[]> {
  const { data, error } = await client().rpc("cooked_page_daily_series", {
    target_path: targetPath,
    days_back: daysBack,
  });
  if (error) throw new Error(`cooked_page_daily_series: ${error.message}`);
  return (data ?? []) as CookedDailyPoint[];
}

export async function sitePulse(
  periodKind: PeriodKind = "rolling_28",
  deltaThresholdPct = 5.0
): Promise<SitePulse> {
  const { data, error } = await client().rpc("site_pulse", {
    p_period_kind: periodKind,
    delta_threshold_pct: deltaThresholdPct,
  });
  if (error) throw new Error(`site_pulse: ${error.message}`);
  const rows = (data ?? []) as SitePulse[];
  if (!rows[0]) throw new Error("site_pulse returned no rows");
  return rows[0];
}

export async function siteKpisCompare(
  periodKind: PeriodKind = "rolling_28"
): Promise<SiteKpisCompare> {
  const { data, error } = await client().rpc("site_kpis_compare", {
    p_period_kind: periodKind,
  });
  if (error) throw new Error(`site_kpis_compare: ${error.message}`);
  const rows = (data ?? []) as SiteKpisCompare[];
  if (!rows[0]) throw new Error("site_kpis_compare returned no rows");
  return rows[0];
}
