import { cn } from "@/lib/cn";
import { Info } from "./Info";

// M3 — bandeau de fraîcheur : UNE phrase calme + un point d'état + un ⓘ pour le détail
// technique brut. Priorité des états : instantané périmé (>36 h) > Google en retard
// (>3 j) > tout va bien. Le `live` (page /seo) ne parle que de Google (pas de snapshot).
const GSC_LAG_MAX_DAYS = 3;

// "2026-07-02" → "02/07"
function jjmm(iso?: string | null): string {
  if (!iso) return "—";
  const [, m, d] = iso.slice(0, 10).split("-");
  return m && d ? `${d}/${m}` : iso;
}
// timestamptz ISO → "02/07 à 14:30" (heure de Paris)
function jjmmHeure(iso?: string | null): string {
  if (!iso) return "—";
  const d = new Date(iso);
  const date = d.toLocaleDateString("fr-FR", { timeZone: "Europe/Paris", day: "2-digit", month: "2-digit" });
  const heure = d.toLocaleTimeString("fr-FR", { timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit" });
  return `${date} à ${heure}`;
}
// Jour calendaire courant en Europe/Paris (Vercel tourne en UTC → JAMAIS new Date()
// nu pour la date du jour : on passe par Intl). Renvoie "YYYY-MM-DD".
function parisTodayISO(): string {
  // eslint-disable-next-line react-hooks/purity -- Server Component rendu à la requête : jour lu une fois
  return new Date().toLocaleDateString("en-CA", { timeZone: "Europe/Paris" });
}
// Écart en jours entiers entre deux dates ISO (parse à minuit UTC → pas de DST).
function dayGap(fromISO: string, toISO: string): number {
  const a = Date.parse(`${fromISO.slice(0, 10)}T00:00:00Z`);
  const b = Date.parse(`${toISO.slice(0, 10)}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

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
    // eslint-disable-next-line react-hooks/purity -- Server Component rendu à la requête : heure courante lue une fois
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
    // « hier » dynamique : écart cooked_end ↔ aujourd'hui (Europe/Paris). Écart 1 →
    // « à jour d'hier » ; écart ≥ 2 → phrase neutre « jusqu'au X (il y a N j) » (un
    // écart de 2 avant le refresh de 10:15 est normal chaque matin ; les vraies
    // pannes sont couvertes par l'état « périmé > 36 h »).
    const cookedGap = cookedEnd ? dayGap(cookedEnd, parisTodayISO()) : null;
    sentence = live ? (
      <>
        Données Google à J-{lag} ({jjmm(gscLastDay)}, délai normal).
      </>
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

  // Suffixe conditionnel (état non-périmé). current_day_partial RETIRÉ : depuis l'ancrage
  // J-1 (T-16) les fenêtres finissent à hier, la journée en cours n'est jamais comptée →
  // le flag est structurellement toujours faux (confirmé sur le snapshot du jour).
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
