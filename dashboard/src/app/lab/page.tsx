import { LabExplorer } from "@/components/LabExplorer";
import { getLabGscWeekly } from "@/data/dashboard";
import { buildLabGscView } from "@/data/lab-view-models";
import { requireUser } from "@/lib/auth";
import { dateFr } from "@/lib/dates";

export const dynamic = "force-dynamic";
export const metadata = { title: "Lab éditorial · Cooked" };

export default async function LabPage() {
  await requireUser();
  const view = buildLabGscView(await getLabGscWeekly(70));

  return (
    <main className="mx-auto max-w-[1240px] px-4 pb-14 sm:px-8">
      <header className="pt-7 pb-5 sm:pt-10 sm:pb-7">
        <p className="font-mono text-[11px] font-semibold tracking-[0.12em] text-alert uppercase">
          Lab / Observatoire éditorial
        </p>
        <h1 className="mt-2 mb-3 text-[clamp(36px,4.6vw,62px)] leading-none font-semibold tracking-[-0.055em]">
          Les clics Google<span className="text-accent" aria-hidden="true">.</span>
        </h1>
        <p className="text-[15px] text-muted">
          Par type de page · Google Search Console
          {view.weeks.length > 0 && (
            <> · {view.weeks.length} {view.weeks.length === 1 ? "semaine close" : "semaines closes"}, du {dateFr(view.windowStart)} au {dateFr(view.windowEnd)}.</>
          )}
        </p>
      </header>
      {view.weeks.length > 0 ? (
        <LabExplorer key={view.windowEnd} view={view} />
      ) : (
        <p className="border-t border-line-strong py-6">Aucune semaine de clics disponible pour cette période.</p>
      )}
    </main>
  );
}
