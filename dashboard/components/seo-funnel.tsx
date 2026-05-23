import { ChevronRight } from "lucide-react";
import { InfoLabel } from "@/components/info-label";
import { formatInt, formatPct } from "@/lib/format";
import type { SiteSeoFunnel } from "@/lib/cooked";
import { cn } from "@/lib/utils";

/**
 * Funnel SEO site-wide en 4 étapes.
 *
 * Layout : 4 cartes côte à côte sur desktop, empilées sur mobile.
 * Chaque carte a une largeur de barre proportionnelle au volume relatif
 * à l'étape la plus large (impressions). Les taux de conversion entre
 * étapes sont affichés en chevrons intermédiaires (desktop) ou en
 * étiquettes (mobile).
 */
export function SeoFunnel({ funnel }: { funnel: SiteSeoFunnel }) {
  const max = Math.max(funnel.impressions, 1);
  const steps: Step[] = [
    {
      label: "Impressions",
      hint: "Apparitions du site dans les résultats Google sur la fenêtre.",
      value: funnel.impressions,
    },
    {
      label: "Clics Google",
      hint: "Clics depuis Google Search Console.",
      value: funnel.clicks,
      drop: funnel.impr_to_click_pct,
      dropLabel: "CTR moyen",
    },
    {
      label: "Visites Google",
      hint: "Sessions Cooked dont le referrer ou les utm pointent Google. Doit être ≈ clics GSC (gros écart = trou tracker).",
      value: funnel.google_sessions,
      drop: funnel.click_to_session_pct,
      dropLabel: "Clics → visites",
    },
    {
      label: "Contacts",
      hint: "Macro = appels + formulaires soumis (toutes sources, pas que Google).",
      value: funnel.macro_contacts,
      drop: funnel.session_to_contact_pct,
      dropLabel: "Visites Google → contacts",
    },
  ];

  return (
    <div className="rounded-lg border border-border bg-surface p-5 shadow-xs">
      <div className="mb-4 flex items-baseline justify-between">
        <h2 className="font-heading text-base font-medium tracking-tight">
          <InfoLabel
            label="Funnel SEO"
            hint="Parcours acquisition Google : impressions → clics → visites Cooked attribuées à Google → contacts business. Les chiffres sont du site entier (les contacts incluent toutes sources, pas que Google) — utile pour situer la friction principale."
          />
        </h2>
        <span className="font-mono text-xs text-muted-foreground">
          {funnel.overall_impr_to_contact_pct != null
            ? `${formatPct(funnel.overall_impr_to_contact_pct, 3)} bout en bout`
            : "—"}
        </span>
      </div>

      <div className="grid gap-3 md:grid-cols-[1fr_auto_1fr_auto_1fr_auto_1fr] md:items-stretch">
        {steps.map((step, i) => (
          <Fragment key={step.label}>
            {i > 0 && <StepArrow drop={step.drop} label={step.dropLabel} />}
            <FunnelStep step={step} max={max} />
          </Fragment>
        ))}
      </div>
    </div>
  );
}

type Step = {
  label: string;
  hint: string;
  value: number;
  drop?: number | null;
  dropLabel?: string;
};

function FunnelStep({ step, max }: { step: Step; max: number }) {
  const widthPct = Math.max(2, (step.value / max) * 100);
  return (
    <div className="rounded-md border border-border bg-surface-subtle/40 p-3">
      <div className="font-mono text-[10px] uppercase tracking-wide text-muted-foreground">
        <InfoLabel label={step.label} hint={step.hint} />
      </div>
      <div className="mt-1 font-mono text-2xl tabular-nums tracking-tight text-foreground">
        {formatInt(step.value)}
      </div>
      <div className="mt-2 h-1.5 w-full overflow-hidden rounded-full bg-border">
        <div
          className="h-full rounded-full bg-foreground"
          style={{ width: `${widthPct}%` }}
        />
      </div>
    </div>
  );
}

function StepArrow({
  drop,
  label,
}: {
  drop: number | null | undefined;
  label?: string;
}) {
  return (
    <div className="flex items-center justify-center md:flex-col md:gap-1">
      <ChevronRight
        className={cn(
          "h-5 w-5 text-muted-foreground",
          drop != null && drop < 1 && "text-warning"
        )}
        aria-hidden="true"
      />
      <div className="text-center font-mono">
        <div
          className={cn(
            "text-xs tabular-nums",
            drop == null
              ? "text-muted-foreground"
              : drop < 1
                ? "text-warning"
                : "text-foreground"
          )}
        >
          {drop == null ? "—" : formatPct(drop, drop < 10 ? 2 : 1)}
        </div>
        {label && (
          <div className="text-[9px] uppercase tracking-wide text-muted-foreground">
            {label}
          </div>
        )}
      </div>
    </div>
  );
}

// Petit fragment pour éviter un import React.Fragment alourdi
function Fragment({ children }: { children: React.ReactNode }) {
  return <>{children}</>;
}
