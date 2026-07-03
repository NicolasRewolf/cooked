import { cn } from "@/lib/cn";
import { Badge, ConfidenceBadge, SectionTitle } from "./ui";
import { Sparkline } from "./Sparkline";
import { num } from "@/lib/format";
import type { ArticleDetail } from "@/lib/types";

// Les 4 composantes du CPI traduites en français d'action — « le CPI trie,
// les quatre z diagnostiquent » (docs/cpi-cooked-page-index.md).
const AXES: {
  key: "zc" | "zr" | "zl" | "zv";
  label: string;
  good: string;
  bad: string;
  mid: string;
  lever: string;
}[] = [
  {
    key: "zc",
    label: "Capture",
    good: "capte plus de clics que ce que Google lui offre",
    mid: "capte à peu près ce que Google lui offre",
    bad: "capte moins de clics que ce que Google lui offre",
    lever: "levier : titre & méta-description",
  },
  {
    key: "zr",
    label: "Rétention",
    good: "retient ses lecteurs mieux que les pages comparables",
    mid: "retient ses lecteurs dans la moyenne",
    bad: "perd ses lecteurs plus vite que les pages comparables",
    lever: "levier : introduction & promesse tenue",
  },
  {
    key: "zl",
    label: "Lecture",
    good: "fait lire en profondeur plus que ses pairs",
    mid: "profondeur de lecture dans la moyenne",
    bad: "fait moins lire en profondeur que ses pairs",
    lever: "levier : structure & maillage interne",
  },
  {
    key: "zv",
    label: "Conversion",
    good: "contribue aux contacts plus que ses pairs",
    mid: "contribution aux contacts dans la moyenne",
    bad: "contribue moins aux contacts que ses pairs",
    lever: "levier : pont vers le contact dans le corps",
  },
];

function AxisRow({ label, z, good, mid, bad, lever }: { label: string; z: number | null } & Omit<(typeof AXES)[number], "key">) {
  if (z == null) return null;
  const tone = z >= 0.5 ? "good" : z <= -0.5 ? "bad" : "mid";
  const text = tone === "good" ? good : tone === "bad" ? bad : mid;
  const dot = tone === "good" ? "bg-up" : tone === "bad" ? "bg-alert" : "bg-faint";
  // jauge -3..+3 → 0..100 %
  const pctPos = Math.round(((Math.max(-3, Math.min(3, z)) + 3) / 6) * 100);
  return (
    <div className="flex items-center gap-3 py-1.5">
      <span className="w-[86px] shrink-0 font-mono text-[10.5px] uppercase tracking-[0.04em] text-faint">
        {label}
      </span>
      <div className="relative h-[5px] w-[110px] shrink-0 bg-[#efefec]" title={`z = ${z.toFixed(1)} (vs pages du même type)`}>
        <span className="absolute top-[-2px] h-[9px] w-[2px] bg-line-strong" style={{ left: "50%" }} />
        <span className={cn("absolute top-[-2px] h-[9px] w-[9px] rounded-full", dot)} style={{ left: `calc(${pctPos}% - 4px)` }} />
      </div>
      <span className="text-[12px] text-[#45423c]">
        {text} <span className="font-mono text-[10px] text-dim">· {lever}</span>
      </span>
    </div>
  );
}

export function CpiHealthPanel({ detail }: { detail: ArticleDetail }) {
  const c = detail.cpi;
  const series = detail.cpi_series.map((p) => p.cpi);
  return (
    <section className="border border-line bg-panel px-4 py-3.5">
      <div className="flex items-start justify-between gap-4">
        <SectionTitle>santé (CPI)</SectionTitle>
        {c && (
          <div className="flex items-center gap-2">
            <span className="font-mono text-[18px] font-semibold text-ink" title="Score CPI 0-100 (dernier snapshot)">
              {c.cpi}
            </span>
            <ConfidenceBadge grade={c.grade} />
            {c.momentum != null && (
              <Badge tone={c.momentum >= 1.05 ? "good" : c.momentum <= 0.95 ? "warn" : "neutral"}>
                {c.momentum >= 1.15 ? "↗ monte" : c.momentum <= 0.87 ? "↘ ralentit" : "→ stable"}
              </Badge>
            )}
          </div>
        )}
      </div>
      {!c ? (
        <p className="text-[12px] leading-relaxed text-muted">
          Pas de score aujourd&apos;hui : trop peu de trafic organique pour un verdict fiable
          (l&apos;article est sous les seuils d&apos;inclusion du CPI). C&apos;est normal pour un
          article jeune ou de niche — pas un signal négatif.
        </p>
      ) : (
        <>
          <div className="divide-y divide-[#f2f2f0]">
            {AXES.map((a) => (
              <AxisRow key={a.key} label={a.label} z={c[a.key]} good={a.good} mid={a.mid} bad={a.bad} lever={a.lever} />
            ))}
          </div>
          <div className="mt-2.5 flex flex-wrap items-center gap-x-5 gap-y-1 font-mono text-[10.5px] text-dim">
            {c.clics_perdus != null && c.clics_perdus > 0 && (
              <span title="Clics Google estimés perdus vs le CTR attendu du site à ces positions">
                ≈ {num(c.clics_perdus)} clics perdus / 28 j
              </span>
            )}
            {c.n_org != null && <span>{num(c.n_org)} entrées organiques (base du verdict)</span>}
            {c.couv_gsc_pct != null && (
              <span title="Part des impressions dont Google révèle la requête">
                couverture requêtes {c.couv_gsc_pct} %
              </span>
            )}
            {series.length >= 5 && (
              <span className="inline-flex items-baseline gap-1.5">
                trajectoire
                <span className="inline-block w-[120px]">
                  <Sparkline series={series} height={16} />
                </span>
              </span>
            )}
          </div>
          <p className="mt-2 font-mono text-[10px] leading-relaxed text-dim">
            Chaque axe compare l&apos;article aux pages du même type (● au centre = dans la
            moyenne). Grade C = hypothèse, pas verdict.
          </p>
        </>
      )}
    </section>
  );
}
