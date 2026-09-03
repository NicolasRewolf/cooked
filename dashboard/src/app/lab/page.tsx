import { requireUser } from "@/lib/auth";
import { getLabGscWeekly } from "@/data/dashboard";
import { buildLabGscView } from "@/data/lab-view-models";
import { StreamRibbon } from "@/components/StreamRibbon";
import { dateFr, jjmm } from "@/lib/dates";
import { num, pct } from "@/lib/format";

export const dynamic = "force-dynamic";

// Lab — graphes éditoriaux (grammaire Lieflat : une conclusion par graphe, unités
// réelles, rivière monochrome, notes de marge). Hors navigation « période » : la
// fenêtre est celle des données Google (semaines ISO closes).
export default async function LabPage() {
  await requireUser();
  const data = await getLabGscWeekly(70);
  const view = buildLabGscView(data);

  return (
    <main className="mx-auto max-w-[1240px] px-8 py-[30px] pb-16">
      <div className="mb-[18px]">
        <div className="font-mono text-[11px] uppercase tracking-[0.08em] text-faint">
          Lab · graphes éditoriaux
        </div>
        <h1 className="mt-2 text-[25px] font-semibold tracking-[-0.02em]">Seize mois de clics Google, par type de page</h1>
        <p className="mt-2 max-w-[820px] text-[13px] leading-relaxed text-muted">
          Totaux <span className="font-mono">gsc_path_daily</span> (tous clics, marque incluse), semaines ISO closes
          du {dateFr(view.windowStart)} au {dateFr(view.windowEnd)}. Un article sans ligne de taxonomie tombe dans
          « cabinet &amp; divers ». Les triangles sont les annotations du journal.
        </p>
      </div>

      <StreamRibbon view={view} />

      {/* Notes de marge : chiffres réels par bande, deux blocs de 4 semaines closes. */}
      <section className="mt-[18px] grid grid-cols-1 gap-px border border-line bg-line sm:grid-cols-2 lg:grid-cols-4">
        {view.bands.map((b) => {
          const ratio = b.ref4 > 0 ? b.last4 / b.ref4 - 1 : null;
          return (
            <div key={b.key} className="bg-panel px-4 py-3">
              <div className="flex items-center gap-2 font-mono text-[10.5px] uppercase tracking-[0.08em] text-faint">
                <span className="inline-block h-[8px] w-[8px]" style={{ background: `var(--color-${b.tone})` }} aria-hidden />
                {b.label}
              </div>
              <div className="mt-2 font-mono text-[20px] font-semibold tabular-nums text-ink">
                {num(Math.round(b.last4))}
                <span className="ml-1 text-[11px] font-normal text-faint">clics / sem.</span>
              </div>
              <div className="mt-1 font-mono text-[10.5px] leading-relaxed text-muted">
                4 dern. sem. · il y a 8 sem. : {num(Math.round(b.ref4))}
                {ratio !== null && (
                  <span className={ratio < -0.15 ? "text-down" : ratio > 0.15 ? "text-up" : "text-muted"}>
                    {" "}
                    ({ratio >= 0 ? "+" : ""}
                    {Math.round(ratio * 100)} %)
                  </span>
                )}
                <br />
                CTR {b.ctrLast4Pct === null ? "—" : pct(b.ctrLast4Pct, 2)} · il y a 8 sem. :{" "}
                {b.ctrRef4Pct === null ? "—" : pct(b.ctrRef4Pct, 2)}
                <br />
                pic {num(b.peak)} (sem. du {jjmm(b.peakWeek)})
              </div>
            </div>
          );
        })}
      </section>

      <p className="mt-[11px] max-w-[920px] font-mono text-[10.5px] leading-relaxed text-dim">
        ⚠ Un clic GSC n&apos;est pas une visite Cooked (sous-comptage ×2,4 mesuré le 11/06/2026). Clics en baisse à
        impressions constantes = la page de résultats bouge, pas le classement (piège n°4 du playbook) — le CTR des
        notes de marge est là pour ça. Lecture Lieflat F16 « Stream Ribbon », rendue avec les tokens Cooked.
      </p>
    </main>
  );
}
