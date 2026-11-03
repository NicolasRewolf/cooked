import { dayShort } from "@/lib/annotations";
import { dec } from "@/lib/format";
import { cn } from "@/lib/cn";
import type { InterventionEffect } from "@/lib/types";

// B2 — avant/après observé sous la timeline, un par intervention site_change.
// Données PLATES (l'objet effect est un jsonb sérialisé, pas de fonction).

function signedPct(n: number): string {
  return `${n > 0 ? "+" : ""}${n} %`;
}

function EffectLine({ e }: { e: InterventionEffect }) {
  // Trop tôt : aucun pourcentage.
  if (e.confidence === "trop_tot") {
    return (
      <span className="text-dim">
        J+{e.days_post} — recul insuffisant : première comparaison à partir de 7 jours de données
      </span>
    );
  }
  // Base pré-intervention insuffisante.
  if (e.base_trop_faible) {
    return (
      <span className="text-dim">base pré-intervention trop faible pour un avant/après chiffré</span>
    );
  }
  if (e.clics_pct == null || e.effet_net_pct == null || e.maree_pct == null) {
    return (
      <span className="text-dim">comparaison indisponible : données de page ou du site insuffisantes</span>
    );
  }
  // Variation observée, ajustée de la variation globale du site.
  const net = e.effet_net_pct;
  const netCls = net > 0 ? "text-up" : net < 0 ? "text-down" : "text-faint";
  return (
    <span className="text-ink-2">
      clics/jour <b className="font-semibold">{signedPct(e.clics_pct)}</b> avant/après · site{" "}
      {signedPct(e.maree_pct)} → variation relative au site{" "}
      <b className={cn("font-semibold", netCls)}>≈ {signedPct(net)}</b>
      {e.pos_pre != null && e.pos_post != null ? (
        <>
          {" "}
          · position {dec(e.pos_pre, 1)} → {dec(e.pos_post, 1)}
        </>
      ) : null}{" "}
      · recul de {e.days_post} j
      {e.article_jeune ? (
        <span className="text-warn">
          {" "}
          ⚠ article récent ({e.age_gsc_jours} j) — son âge peut aussi contribuer à son évolution
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
      <p className="font-mono text-[11px] leading-relaxed text-muted">
        Cet avant/après compare la page à l’évolution globale du site. Il ne démontre pas
        que l’intervention a causé la variation ; le recul indique seulement la durée observée.
      </p>
    </section>
  );
}
