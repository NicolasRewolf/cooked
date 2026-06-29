// Contrat typé des RPC dashboard (cf. migration 20260629112816_dashboard_v1_rpcs.sql).
// Le dashboard ne consomme que ces 3 fonctions service_role — on type leur retour
// à la main plutôt que de générer tout le schéma (lean + découplé).
// PostgREST renvoie bigint/numeric en number, date/text en string.

export type Period = "week" | "month" | "rolling_28" | "rolling_90";

export interface ResourceRow {
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
}

export interface ResourceKpis {
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
  volume_fr: number | null;
  cpc: number | null;
  competition_level: string | null;
  capture_pct: number | null;
  is_quick_win: boolean;
  gsc_start: string;
  gsc_end: string;
}
