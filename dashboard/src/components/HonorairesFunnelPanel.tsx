import { num, pct, dateFr } from "@/lib/format";
import type { HonorairesFunnel } from "@/data/rpc-schemas";
import { Info } from "@/components/Info";

/** Tunnel intent RDV → formulaire — le goulot documenté sur /honoraires-rendez-vous. */
export function HonorairesFunnelPanel({ funnel }: { funnel: HonorairesFunnel }) {
  const rate = funnel.rate_booking_to_form;
  return (
    <section className="border border-line bg-panel px-4 py-3.5">
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <div className="flex items-center gap-1.5">
          <h2 className="text-[13px] font-semibold tracking-[-0.01em] text-ink">
            Tunnel RDV → formulaire
          </h2>
          <Info>
            Clics « Prendre rendez-vous » puis formulaire envoyé dans les 6 h (même
            session). Le taux bas = goulot sur /honoraires-rendez-vous, pas un manque
            de trafic.
          </Info>
        </div>
        <div className="font-mono text-[10px] text-faint">
          {dateFr(funnel.cooked_start)} → {dateFr(funnel.cooked_end)}
        </div>
      </div>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <Step
          n={funnel.booking_sessions}
          label="Clics intent RDV"
          hint="sessions avec cta_booking_click"
        />
        <Step
          n={funnel.booking_then_honoraires}
          label="Arrivés honoraires"
          hint="ont vu /honoraires-rendez-vous"
        />
        <Step
          n={funnel.forms_after_booking_6h}
          label="Formulaires liés"
          hint="form dans les 6 h après le clic"
        />
        <div className="flex flex-col justify-center">
          <div className="font-mono text-[22px] font-semibold tracking-[-0.03em] text-ink">
            {rate != null ? pct(rate) : "—"}
          </div>
          <div className="mt-0.5 text-[11px] text-muted">taux booking → form</div>
          <div className="font-mono text-[10px] text-faint">
            {num(funnel.forms_on_honoraires)} forms page honoraires · {num(funnel.forms_macro_total)}{" "}
            forms site
          </div>
        </div>
      </div>
    </section>
  );
}

function Step({ n, label, hint }: { n: number; label: string; hint: string }) {
  return (
    <div>
      <div className="font-mono text-[22px] font-semibold tracking-[-0.03em] text-ink">{num(n)}</div>
      <div className="mt-0.5 text-[11px] text-muted">{label}</div>
      <div className="font-mono text-[10px] text-faint">{hint}</div>
    </div>
  );
}
