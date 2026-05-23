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

export type PagesOverviewRow = {
  path: string;
  gsc_clicks_28d: number;
  gsc_impressions_28d: number;
  gsc_position_avg_28d: number | null;
  gsc_ctr_pct_28d: number | null;
  cooked_sessions_28d: number;
  cooked_dwell_avg_s_28d: number | null;
  cooked_bounce_rate_28d: number | null;
  /** Macro = vrai contact établi : clic tel: + formulaire soumis */
  cooked_phone_clicks_28d: number;
  cooked_form_submits_28d: number;
  cooked_contacts_28d: number;
  /** Micro = intent déclaré : clic « Prendre RDV » (cta_booking_click) */
  cooked_booking_intent_28d: number;
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
  /** Macro = vrai contact établi : clic tel: + formulaire soumis */
  cooked_phone_clicks_28d: number;
  cooked_form_submits_28d: number;
  cooked_contacts_28d: number;
  /** Micro = intent déclaré : clic « Prendre RDV » */
  cooked_booking_intent_28d: number;
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
  /** DataForSEO enrichments (null si keyword pas encore syncé) */
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

/** Quadrant Pulse cross-source — cf migration 20260524160000_pages_pulse.sql */
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
 * Top pages 28j — univers exhaustif (snapshot Cooked 365j ∪ GSC 90j),
 * ordonné par sessions Cooked. Inclut les pages mortes (0 partout).
 * RPC : public.pages_overview_unified(max_rows int)
 *
 * Sprint 33+ v3 (24/05/2026) : contacts macro corrects (phone + form_submit),
 * booking_intent séparé. Voir CLAUDE.md cooked pour la taxonomie macro/micro.
 */
export async function pagesOverviewUnified(
  maxRows = 1000
): Promise<PagesOverviewRow[]> {
  const { data, error } = await client().rpc("pages_overview_unified", {
    max_rows: maxRows,
  });
  if (error) throw new Error(`pages_overview_unified: ${error.message}`);
  return (data ?? []) as PagesOverviewRow[];
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
 * Pulse cross-source par path — grille 2×2 (GSC 28v28 × Cooked 7v7).
 * Permet d'induire "progression / régression" malgré l'historique court
 * de Cooked en s'appuyant sur GSC long terme.
 * RPC : public.pages_pulse(gsc_period, cooked_period, delta_threshold_pct)
 */
export async function pagesPulse(
  gscPeriod = 28,
  cookedPeriod = 7,
  deltaThresholdPct = 5.0
): Promise<PagePulseRow[]> {
  const { data, error } = await client().rpc("pages_pulse", {
    gsc_period: gscPeriod,
    cooked_period: cookedPeriod,
    delta_threshold_pct: deltaThresholdPct,
  });
  if (error) throw new Error(`pages_pulse: ${error.message}`);
  return (data ?? []) as PagePulseRow[];
}

/**
 * Funnel SEO site-wide : Impressions → Clics GSC → Visites Google
 * Cooked → Contacts macro, avec drop-off entre chaque étape.
 * RPC : public.site_seo_funnel(period_days)
 */
export async function siteSeoFunnel(
  periodDays = 28
): Promise<SiteSeoFunnel> {
  const { data, error } = await client().rpc("site_seo_funnel", {
    period_days: periodDays,
  });
  if (error) throw new Error(`site_seo_funnel: ${error.message}`);
  const rows = (data ?? []) as SiteSeoFunnel[];
  if (!rows[0]) throw new Error("site_seo_funnel returned no rows");
  return rows[0];
}

/**
 * Top N requêtes Google du site sur N jours avec attribution page
 * + enrichissement DataForSEO (volume FR, CPC, click yield %).
 * RPC v2 : public.gsc_top_queries_global(days_back, max_rows)
 */
export async function gscTopQueriesGlobal(
  daysBack = 28,
  maxRows = 100
): Promise<GscGlobalQueryRow[]> {
  const { data, error } = await client().rpc("gsc_top_queries_global", {
    days_back: daysBack,
    max_rows: maxRows,
  });
  if (error) throw new Error(`gsc_top_queries_global: ${error.message}`);
  return (data ?? []) as GscGlobalQueryRow[];
}

/**
 * Opportunités SEO : requêtes en position 5-15 avec volume DFS suffisant.
 * Lost potential = clics manqués si on était en position 1.
 * RPC : public.gsc_x_dfs_opportunities(min_volume, pos_min, pos_max, days_back, max_rows)
 */
export async function gscXDfsOpportunities(
  minVolume = 100,
  positionMin = 5,
  positionMax = 15,
  daysBack = 28,
  maxRows = 30
): Promise<GscDfsOpportunityRow[]> {
  const { data, error } = await client().rpc("gsc_x_dfs_opportunities", {
    min_volume: minVolume,
    position_min: positionMin,
    position_max: positionMax,
    days_back: daysBack,
    max_rows: maxRows,
  });
  if (error) throw new Error(`gsc_x_dfs_opportunities: ${error.message}`);
  return (data ?? []) as GscDfsOpportunityRow[];
}

/**
 * Série quotidienne clics GSC pour une page (sparkline fiche page).
 * RPC : public.gsc_page_daily_series(target_path, days_back)
 */
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

/**
 * Série quotidienne visites Cooked pour une page (sparkline fiche page).
 * RPC : public.cooked_page_daily_series(target_path, days_back)
 */
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

/**
 * Pulse cross-source site-wide : totaux GSC 28v28 + Cooked 7v7 + quadrant.
 * RPC : public.site_pulse(gsc_period, cooked_period, delta_threshold_pct)
 */
export async function sitePulse(
  gscPeriod = 28,
  cookedPeriod = 7,
  deltaThresholdPct = 5.0
): Promise<SitePulse> {
  const { data, error } = await client().rpc("site_pulse", {
    gsc_period: gscPeriod,
    cooked_period: cookedPeriod,
    delta_threshold_pct: deltaThresholdPct,
  });
  if (error) throw new Error(`site_pulse: ${error.message}`);
  const rows = (data ?? []) as SitePulse[];
  if (!rows[0]) throw new Error("site_pulse returned no rows");
  return rows[0];
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
