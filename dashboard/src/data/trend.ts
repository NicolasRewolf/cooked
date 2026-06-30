import "server-only";
import { admin } from "@/lib/supabase-admin";
import type { Period } from "@/lib/types";

// Séries journalières pour les sparklines KPI + le graphe principal « oscilloscope ».
// ⚠ NÉCESSITE un RPC backend (non encore présent) — voir HANDOFF.md §3.
//    Shape attendue : 1 ligne avec un tableau de valeurs / jour par métrique,
//    ordonné du plus ancien au plus récent, sur la fenêtre `period`.
// En l'absence du RPC (ou en cas d'erreur), renvoie null → les visuels sont
// simplement masqués ; le reste du dashboard fonctionne avec les RPC actuels.
export interface ResourcesTrend {
  visitors_daily: number[];
  pageviews_daily: number[];
  contacts_daily: number[];
  gsc_clicks_daily: number[];
  gsc_impressions_daily: number[];
}

export async function getResourcesTrend(period: Period): Promise<ResourcesTrend | null> {
  try {
    const { data, error } = await admin.rpc("dashboard_resources_trend", { period_kind: period });
    if (error || !data) return null;
    const row = Array.isArray(data) ? data[0] : data;
    return (row as ResourcesTrend) ?? null;
  } catch {
    return null;
  }
}
