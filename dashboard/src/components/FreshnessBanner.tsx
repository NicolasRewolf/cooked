import { cn } from "@/lib/cn";
import { jjmm, jjmmHeure } from "@/lib/dates";
import { freshnessState } from "@/lib/freshness";
import { Info } from "./Info";

const GLOW: Record<string, string> = {
  "bg-up": "var(--color-up-tint)",
  "bg-warn": "var(--color-warn-tint)",
  "bg-alert": "var(--color-down-tint)",
};

export function FreshnessBanner({
  gscLastDay,
  lagDays,
  cookedEnd,
  refreshedAt,
  noPrevBaseline = false,
  live = false,
}: {
  gscLastDay: string | null;
  lagDays: number | null;
  cookedEnd?: string;
  refreshedAt?: string | null;
  noPrevBaseline?: boolean;
  live?: boolean;
}) {
  // Server Component : horloge lue une fois ; la logique de niveau est pure (lib/freshness, testée).
  const state = freshnessState({ gscLastDay, lagDays, cookedEnd, refreshedAt, live, now: new Date() });
  const { lag, ageHours, cookedGap } = state;

  let dot: string;
  let boxClass: string;
  let sentence: React.ReactNode;
  if (state.reason === "stale_snapshot") {
    dot = "bg-alert";
    boxClass = "border-alert/40 bg-alert/5";
    sentence = (
      <>
        ⚠ Les chiffres n&apos;ont pas été rafraîchis depuis {ageHours} h — vérifier
        l&apos;ingestion et le traitement des instantanés.
      </>
    );
  } else if (state.reason === "cooked_end_late") {
    dot = "bg-warn";
    boxClass = "border-warn/40 bg-warn/5";
    sentence = (
      <>
        ⚠ Données site arrêtées au {jjmm(cookedEnd)} (il y a {cookedGap} j) — la mise à jour qui suit
        l&apos;ingestion Google n&apos;est pas encore visible dans cet instantané.
      </>
    );
  } else if (state.reason === "gsc_late") {
    dot = "bg-warn";
    boxClass = "border-warn/40 bg-warn/5";
    sentence = (
      <>
        ⚠ Les données Google disponibles s&apos;arrêtent au {jjmm(gscLastDay)} (J-{lag}) — vérifier
        la fraîcheur de la source et de l&apos;ingestion.
      </>
    );
  } else if (state.reason === "gsc_missing") {
    dot = "bg-warn";
    boxClass = "border-warn/40 bg-warn/5";
    sentence = <>⚠ Date de fin des données Google indisponible — fraîcheur non vérifiée.</>;
  } else {
    dot = "bg-up";
    boxClass = "border-line bg-panel";
    sentence = live ? (
      <>Données Google à J-{lag} ({jjmm(gscLastDay)}, délai normal).</>
    ) : cookedGap != null && cookedGap >= 2 ? (
      <>
        Données site jusqu&apos;au {jjmm(cookedEnd)} (il y a {cookedGap} j) · Google à J-{lag} (
        {jjmm(gscLastDay)}, délai normal).
      </>
    ) : (
      <>
        Données site à jour d&apos;hier ({jjmm(cookedEnd)}) · Google à J-{lag} ({jjmm(gscLastDay)},
        délai normal).
      </>
    );
  }

  const suffix = state.level === "ok" && !live && noPrevBaseline
    ? " · comparaisons N-1 indisponibles (historique trop court)"
    : "";

  const tech = live
    ? `Google : jusqu'au ${jjmm(gscLastDay)} (écart de dates ${lag ?? "inconnu"} j à Paris). Journées Google en heure du Pacifique. Les journées en cours ne sont pas comptées.`
    : `Site : données jusqu'au ${jjmm(cookedEnd)} (jours Paris) · Google : jusqu'au ${jjmm(gscLastDay)} (jours Pacifique ; écart de dates ${lag ?? "inconnu"} j à Paris) · instantané calculé le ${jjmmHeure(refreshedAt)}. Les deux sources ne couvrent pas exactement les mêmes heures.`;

  return (
    <div className={cn("inline-flex items-center gap-2.5 border px-3 py-2", boxClass)}>
      <span
        className={cn("h-1.5 w-1.5 shrink-0 rounded-full", dot)}
        style={{ boxShadow: `0 0 0 3px ${GLOW[dot]}` }}
      />
      <span className="font-mono text-[11px] leading-snug text-muted">
        {sentence}
        {suffix ? <span className="text-dim">{suffix}</span> : null}
      </span>
      <Info>{tech}</Info>
    </div>
  );
}
