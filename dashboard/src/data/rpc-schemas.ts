import { z } from "zod";

// Primitives partagés — contrat runtime des RPC dashboard_* (C4).

export const periodSchema = z.enum(["rolling_28", "rolling_90"]);
export type Period = z.infer<typeof periodSchema>;

const gradeSchema = z.enum(["S", "A", "B", "C"]);
const isoDate = z.string();
const num = z.number();
const numNull = z.number().nullable();

const boundsSchema = z.object({
  cooked_start: isoDate,
  cooked_end: isoDate,
  gsc_start: isoDate,
  gsc_end: isoDate,
});

export const resourceRowSchema = z.object({
  window_kind: z.string().optional(),
  path: z.string(),
  theme: z.string().nullable(),
  unique_visitors: num,
  pageviews: num,
  dwell_median_s: numNull,
  scroll_median: numNull,
  gsc_clicks: num,
  gsc_impressions: num,
  gsc_position_avg: numNull,
  gsc_ctr_pct: numNull,
  best_query: z.string().nullable(),
  best_query_clicks: numNull,
  best_query_volume_fr: numNull,
  best_query_cpc: numNull,
  contacts: num,
  booking_intent: num,
  first_impression_day: isoDate.nullable(),
  first_tracker_day: isoDate.nullable(),
  days_live: numNull,
  confidence: gradeSchema,
  unique_visitors_prev: num,
  gsc_clicks_prev: num,
  cpi: numNull,
  cpi_grade: gradeSchema.nullable(),
  momentum: numNull,
  potentiel: numNull,
  convertit: z.boolean().nullable(),
  ctr_expected: numNull,
  assisted_contacts: num.optional(),
  assisted_prev: num.optional(),
  cooked_start: isoDate,
  cooked_end: isoDate,
  gsc_start: isoDate,
  gsc_end: isoDate,
  refreshed_at: z.string().optional(),
});
export type ResourceRow = z.infer<typeof resourceRowSchema>;

export const resourceKpisSchema = z
  .array(
    z.object({
      window_kind: z.string().optional(),
      label_fr: z.string(),
      cooked_start: isoDate,
      cooked_end: isoDate,
      gsc_start: isoDate,
      gsc_end: isoDate,
      gsc_last_day: isoDate.nullable(),
      lag_days: numNull,
      is_partial: z.boolean(),
      visitors_n: num,
      visitors_prev: num,
      pageviews_n: num,
      pageviews_prev: num,
      contacts_n: num,
      contacts_prev: num,
      gsc_clicks_n: num,
      gsc_clicks_prev: num,
      gsc_impressions_n: num,
      gsc_impressions_prev: num,
      refreshed_at: z.string(),
      current_day_partial: z.boolean(),
      no_prev_baseline: z.boolean(),
    }),
  )
  .transform((rows) => rows[0] ?? null);
export type ResourceKpis = NonNullable<z.infer<typeof resourceKpisSchema>>;

export const expertiseRowSchema = resourceRowSchema.extend({
  paid_share_pct: numNull,
});
export type ExpertiseRow = z.infer<typeof expertiseRowSchema>;

export const expertiseKpisSchema = z
  .array(
    z.object({
      window_kind: z.string().optional(),
      label_fr: z.string(),
      cooked_start: isoDate,
      cooked_end: isoDate,
      gsc_start: isoDate,
      gsc_end: isoDate,
      gsc_last_day: isoDate.nullable(),
      lag_days: numNull,
      is_partial: z.boolean(),
      visitors_n: num,
      visitors_prev: num,
      pageviews_n: num,
      pageviews_prev: num,
      contacts_n: num,
      contacts_prev: num,
      gsc_clicks_n: num,
      gsc_clicks_prev: num,
      gsc_impressions_n: num,
      gsc_impressions_prev: num,
      refreshed_at: z.string(),
      current_day_partial: z.boolean(),
      no_prev_baseline: z.boolean(),
      paid_entries_n: num,
      organic_entries_n: num,
      total_entries_n: num,
    }),
  )
  .transform((rows) => rows[0] ?? null);
export type ExpertiseKpis = NonNullable<z.infer<typeof expertiseKpisSchema>>;

export const seoQueryRowSchema = z.object({
  query: z.string(),
  clicks: num,
  impressions: num,
  position_avg: numNull,
  ctr_pct: numNull,
  nb_pages: num,
  top_page: z.string().nullable(),
  top_page_clicks: numNull,
  top_page_theme: z.string().nullable(),
  volume_fr: numNull,
  cpc: numNull,
  competition_level: z.string().nullable(),
  capture_pct: numNull,
  is_quick_win: z.boolean(),
  clicks_prev: num,
  position_prev: numNull,
  ctr_expected: numNull,
  opportunity_clicks: numNull,
  gsc_start: isoDate,
  gsc_end: isoDate,
});
export type SeoQueryRow = z.infer<typeof seoQueryRowSchema>;

export const seoKpisSchema = z
  .array(
    z.object({
      total_queries: num,
      total_quick_wins: num,
      clicks_named_nonbranded: num,
      clicks_path_total: num,
      impressions_path_total: num,
      gsc_start: isoDate,
      gsc_end: isoDate,
    }),
  )
  .transform((rows) => rows[0] ?? null);
export type SeoKpis = NonNullable<z.infer<typeof seoKpisSchema>>;

export const assistedRowSchema = z.object({
  path: z.string(),
  assisted_contacts: num,
  assisted_prev: num,
});
export type AssistedRow = z.infer<typeof assistedRowSchema>;

export const annotationSchema = z.object({
  day: isoDate,
  kind: z.string(),
  label: z.string(),
  paths: z.array(z.string()).nullable(),
});
export type Annotation = z.infer<typeof annotationSchema>;

// Lab — clics/impressions GSC par semaine ISO close et par type de page (RPC dashboard_lab_gsc_weekly).
export const labGscWeekSchema = z.object({
  week_start: isoDate,
  c_ressource: num,
  c_classique: num,
  c_expertise: num,
  c_divers: num,
  i_ressource: num,
  i_classique: num,
  i_expertise: num,
  i_divers: num,
});
export type LabGscWeek = z.infer<typeof labGscWeekSchema>;

export const labGscWeeklySchema = z.object({
  gsc_end: isoDate,
  window_start: isoDate,
  window_end: isoDate,
  weeks: z.array(labGscWeekSchema),
  annotations: z.array(annotationSchema),
});
export type LabGscWeekly = z.infer<typeof labGscWeeklySchema>;

export const interventionEffectSchema = z.object({
  path: z.string(),
  day: isoDate,
  gsc_last: isoDate,
  days_post: num,
  confidence: z.enum(["trop_tot", "indicatif", "fiable", "verdict"]),
  base_trop_faible: z.boolean(),
  article_jeune: z.boolean(),
  age_gsc_jours: numNull,
  pre_total_clics: num,
  page_clics_jour_pre: num,
  page_clics_jour_post: numNull,
  pos_pre: numNull,
  pos_post: numNull,
  clics_pct: numNull,
  maree_pct: numNull,
  effet_net_pct: numNull,
});
export type InterventionEffect = z.infer<typeof interventionEffectSchema>;

export const cohortsResultSchema = z.object({
  gsc_last: isoDate,
  cohorts: z.array(
    z.object({
      month: z.string(),
      n_articles: num,
      benjamin_age: num,
      series: z.array(num),
    }),
  ),
});
export type CohortsResult = z.infer<typeof cohortsResultSchema>;

export const assistedQuarterSchema = z.object({
  quarter: z.string(),
  quarter_start: isoDate,
  value: num,
  target: numNull,
});
export type AssistedQuarter = z.infer<typeof assistedQuarterSchema>;

export const articleDetailSchema = z.object({
  path: z.string(),
  meta: z
    .object({
      theme: z.string().nullable(),
      category: z.string().nullable(),
      naissance_google: isoDate.nullable(),
      first_tracker_day: isoDate.nullable(),
      age_jours: numNull,
    })
    .nullable(),
  gsc: z
    .object({
      clicks: num,
      impressions: num,
      position: numNull,
      ctr_pct: numNull,
      ctr_expected: numNull,
      clicks_prev: num,
    })
    .nullable(),
  gsc_daily: z.array(z.object({ d: isoDate, clicks: num, impressions: num })),
  visitors_daily: z.array(z.object({ d: isoDate, v: num })),
  top_queries: z.array(
    z.object({
      query: z.string(),
      clicks: num,
      impressions: num,
      position: num,
      volume_fr: numNull,
      cpc: numNull,
    }),
  ),
  cpi: z
    .object({
      day: isoDate,
      grade: gradeSchema,
      cpi: num,
      momentum: numNull,
      zc: numNull,
      zr: numNull,
      zl: numNull,
      zv: numNull,
      clics_perdus: numNull,
      n_org: numNull,
      couv_gsc_pct: numNull,
    })
    .nullable(),
  cpi_series: z.array(z.object({ d: isoDate, cpi: num })),
  assisted: z.object({ n: num, prev: num }).nullable(),
  bounds: boundsSchema,
});
export type ArticleDetail = z.infer<typeof articleDetailSchema>;

export const resourcesTrendRowSchema = z.object({
  visitors_daily: z.array(num),
  pageviews_daily: z.array(num),
  contacts_daily: z.array(num),
  gsc_clicks_daily: z.array(num),
  gsc_impressions_daily: z.array(num),
});
export type ResourcesTrend = z.infer<typeof resourcesTrendRowSchema>;

export const resourcesTrendRpcSchema = z
  .union([resourcesTrendRowSchema, z.array(resourcesTrendRowSchema).min(1)])
  .transform((v) => (Array.isArray(v) ? v[0] : v));

export const resourceRowsSchema = z.array(resourceRowSchema);
export const expertiseRowsSchema = z.array(expertiseRowSchema);
export const seoQueryRowsSchema = z.array(seoQueryRowSchema);
export const assistedRowsSchema = z.array(assistedRowSchema);
export const annotationRowsSchema = z.array(annotationSchema);

/** Funnel intent RDV → form (live, lens live_j1). */
export const honorairesFunnelSchema = z
  .array(
    z.object({
      booking_sessions: num,
      honoraires_sessions: num,
      booking_then_honoraires: num,
      forms_after_booking_6h: num,
      forms_on_honoraires: num,
      forms_macro_total: num,
      rate_booking_to_form: z.coerce.number().nullable(),
      cooked_start: isoDate,
      cooked_end: isoDate,
    }),
  )
  .transform((rows) => rows[0] ?? null);
export type HonorairesFunnel = NonNullable<z.infer<typeof honorairesFunnelSchema>>;
