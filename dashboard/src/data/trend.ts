import "server-only";
import { admin } from "@/lib/supabase-admin";
import type { Period } from "@/lib/types";

// Séries journalières pour les sparklines KPI + le graphe principal « oscilloscope ».
// Shape attendue : 1 ligne avec un tableau de valeurs / jour par métrique,
// ordonné du plus ancien au plus récent, sur la fenêtre `period`.
export interface ResourcesTrend {
  visitors_daily: number[];
  pageviews_daily: number[];
  contacts_daily: number[];
  gsc_clicks_daily: number[];
  gsc_impressions_daily: number[];
}

// Résultat discriminé : on distingue « pas de série » (data:null sans erreur —
// visuels masqués, normal) d'une VRAIE panne du RPC (error:true) pour qu'une
// régression backend soit visible dans l'UI au lieu d'être avalée en série vide.
export interface TrendResult {
  data: ResourcesTrend | null;
  error: boolean;
}

export async function getResourcesTrend(period: Period): Promise<TrendResult> {
  try {
    const { data, error } = await admin.rpc("dashboard_resources_trend", { period_kind: period });
    if (error) {
      console.error(`RPC dashboard_resources_trend a échoué:`, error.message);
      return { data: null, error: true };
    }
    const row = Array.isArray(data) ? data[0] : data;
    return { data: (row as ResourcesTrend) ?? null, error: false };
  } catch (cause) {
    console.error(`RPC dashboard_resources_trend a levé:`, cause);
    return { data: null, error: true };
  }
}

export async function getExpertisesTrend(period: Period): Promise<TrendResult> {
  try {
    const { data, error } = await admin.rpc("dashboard_expertises_trend", { period_kind: period });
    if (error) {
      console.error(`RPC dashboard_expertises_trend a échoué:`, error.message);
      return { data: null, error: true };
    }
    const row = Array.isArray(data) ? data[0] : data;
    return { data: (row as ResourcesTrend) ?? null, error: false };
  } catch (cause) {
    console.error(`RPC dashboard_expertises_trend a levé:`, cause);
    return { data: null, error: true };
  }
}
