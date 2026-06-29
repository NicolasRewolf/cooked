// Contrat typé des RPC dashboard (cf. migrations supabase/migrations/2026062911*..2026062913*).
// Le dashboard ne consomme que ces RPC service_role — on type leur retour à la main
// (lean + découplé). PostgREST renvoie bigint/numeric en number, date/text en string.

export type Period = "rolling_28" | "rolling_90";

export interface ResourceRow {
  window_kind?: string;
  path: string;
  theme: string | null;
  unique_visitors: number;
  pageviews: number;
  dwell_median_s: number | null;
  scroll_median: number | null;
  gsc_clicks: number;
  gsc_impressions: number;
  gsc_position_avg: number | null;
  gsc_ctr_pct: number | null;
  best_query: string | null;
  best_query_clicks: number | null;
  best_query_volume_fr: number | null;
  best_query_cpc: number | null;
  contacts: number;
  booking_intent: number;
  first_impression_day: string | null;
  first_tracker_day: string | null;
  days_live: number | null;
  confidence: "A" | "B" | "C";
  cooked_start: string;
  cooked_end: string;
  gsc_start: string;
  gsc_end: string;
  refreshed_at?: string;
}

export interface ResourceKpis {
  window_kind?: string;
  label_fr: string;
  cooked_start: string;
  cooked_end: string;
  gsc_start: string;
  gsc_end: string;
  gsc_last_day: string | null;
  lag_days: number | null;
  is_partial: boolean;
  visitors_n: number;
  visitors_prev: number;
  pageviews_n: number;
  pageviews_prev: number;
  contacts_n: number;
  contacts_prev: number;
  gsc_clicks_n: number;
  gsc_clicks_prev: number;
  gsc_impressions_n: number;
  gsc_impressions_prev: number;
  refreshed_at: string;
  current_day_partial: boolean;
  no_prev_baseline: boolean;
}

export interface SeoQueryRow {
  query: string;
  clicks: number;
  impressions: number;
  position_avg: number | null;
  ctr_pct: number | null;
  nb_pages: number;
  top_page: string | null;
  top_page_clicks: number | null;
  top_page_theme: string | null;
  volume_fr: number | null;
  cpc: number | null;
  competition_level: string | null;
  capture_pct: number | null;
  is_quick_win: boolean;
  gsc_start: string;
  gsc_end: string;
}

// KPI SEO calculés côté SQL (indépendants du cap de lignes du tableau).
export interface SeoKpis {
  total_queries: number;
  total_quick_wins: number;
  clicks_named_nonbranded: number; // clics requêtes connues, marque exclue
  clicks_path_total: number; // clics niveau page, toutes requêtes (marque incluse)
  impressions_path_total: number;
  gsc_start: string;
  gsc_end: string;
}
