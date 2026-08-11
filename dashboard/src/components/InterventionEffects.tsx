import { dayShort } from "@/lib/annotations";
import { dec } from "@/lib/format";
import { cn } from "@/lib/cn";
import type { InterventionEffect } from "@/lib/types";

// B2 — panneau « effet mesuré » sous la timeline, un par intervention site_change.
// Données PLATES (l'objet effect est un jsonb sérialisé, pas de fonction).

const CONF_LABEL: Record<string, string> = {
  indicatif: "lecture indicative",
  fiable: "lecture fiable",
  verdict: "verdict complet",
};

function signedPct(n: number): string {
  return `${n > 0 ? "+" : ""}${n} %`;
}

function EffectLine({ e }: { e: InterventionEffect }) {
  // Trop tôt : aucun pourcentage.
  if (e.confidence === "trop_tot") {
    return (
      <span className="text-dim">
        J+{e.days_post} — trop tôt pour mesurer (verdict à partir de J+7, complet à J+28)
      </span>
    );
  }
  // Base pré-intervention insuffisante.
  if (e.base_trop_faible || e.clics_pct == null || e.effet_net_pct == null) {
    return (
      <span className="text-dim">base pré-intervention trop faible pour un avant/après chiffré</span>
    );
  }
  // Mesuré.
  const net = e.effet_net_pct;
  const netCls = net > 0 ? "text-up" : net < 0 ? "text-down" : "text-faint";
  return (
    <span className="text-ink-2">
      clics <b className="font-semibold">{signedPct(e.clics_pct)}</b> vs sa trajectoire · marée site{" "}
      {signedPct(e.maree_pct ?? 0)} → effet net{" "}
      <b className={cn("font-semibold", netCls)}>≈ {signedPct(net)}</b>
      {e.pos_pre != null && e.pos_post != null ? (
        <>
          {" "}
          · position {dec(e.pos_pre, 1)} → {dec(e.pos_post, 1)}
        </>
      ) : null}{" "}
      · fenêtre {e.days_post} j — {CONF_LABEL[e.confidence] ?? e.confidence}
      {e.article_jeune ? (
        <span className="text-warn">
          {" "}
          ⚠ article en croissance naturelle ({e.age_gsc_jours} j) — effet partiellement confondu
        </span>
      ) : null}
    </span>
  );
}

export function InterventionEffects({
  items,
}: {
  items: { label: string; day: string; effect: InterventionEffect }[];
}) {
  if (!items.length) return null;
  return (
    <section className="space-y-2">
      {items.map((it, i) => (
        <div key={i} className="border border-line bg-panel px-4 py-2.5 font-mono text-[11px] leading-relaxed">
          <span className="font-semibold text-ink">{it.label}</span>
          <span className="text-dim"> — {dayShort(it.day)}</span>
          <span className="text-faint"> · </span>
          <EffectLine e={it.effect} />
        </div>
      ))}
    </section>
  );
}
