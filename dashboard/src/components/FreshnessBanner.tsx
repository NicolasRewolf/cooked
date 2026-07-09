import { cn } from "@/lib/cn";
import { dayGap, jjmm, jjmmHeure, parisTodayISO } from "@/lib/dates";
import { Info } from "./Info";

const GSC_LAG_MAX_DAYS = 3;

const GLOW: Record<string, string> = {
  "bg-up": "rgba(47,122,82,.14)",
  "bg-warn": "rgba(199,122,30,.14)",
  "bg-alert": "rgba(194,65,12,.16)",
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
  const lag = lagDays ?? 0;
  const ageHours = refreshedAt
    // eslint-disable-next-line react-hooks/purity -- Server Component : heure courante lue une fois
    ? Math.floor((Date.now() - new Date(refreshedAt).getTime()) / 3_600_000)
    : null;
  const staleSnapshot = !live && ageHours != null && ageHours > 36;
  const gscLate = lag > GSC_LAG_MAX_DAYS;

  let dot: string;
  let boxClass: string;
  let sentence: React.ReactNode;
  if (staleSnapshot) {
    dot = "bg-alert";
    boxClass = "border-alert/40 bg-alert/5";
    sentence = (
      <>
        ⚠ Les chiffres n&apos;ont pas été rafraîchis depuis {ageHours} h — un traitement de nuit a
        probablement échoué. À signaler à Claude.
      </>
    );
  } else if (gscLate) {
    dot = "bg-warn";
    boxClass = "border-warn/40 bg-warn/5";
    sentence = (
      <>
        ⚠ Google n&apos;a rien livré depuis {lag} jours (dernier : {jjmm(gscLastDay)}) — les colonnes
        clics et affichages s&apos;arrêtent à cette date.
      </>
    );
  } else {
    dot = "bg-up";
    boxClass = "border-line bg-panel";
  // eslint-disable-next-line react-hooks/purity -- Server Component : jour Paris lu une fois
    const cookedGap = cookedEnd ? dayGap(cookedEnd, parisTodayISO()) : null;
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

  const suffix = !staleSnapshot && !live && noPrevBaseline
    ? " · comparaisons N-1 indisponibles (historique trop court)"
    : "";

  const tech = live
    ? `Google : jusqu'au ${jjmm(gscLastDay)} (lag ${lag} j) · fenêtres ancrées sur hier (les journées en cours ne sont jamais comptées).`
    : `Site : données jusqu'au ${jjmm(cookedEnd)} · Google : jusqu'au ${jjmm(gscLastDay)} (lag ${lag} j) · instantané calculé le ${jjmmHeure(refreshedAt)} · fenêtres ancrées sur hier (les journées en cours ne sont jamais comptées).`;

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
