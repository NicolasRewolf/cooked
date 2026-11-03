import { useEffect, useId, useRef, useState } from "react";
import type { LabBand, LabMarker } from "@/data/lab-view-models";
import { buildLinePath, indexFromPointerX, xScaleIndex, yScale, type ChartBox } from "@/lib/chart-geometry";
import { dateFr, dayDiff, jjmm } from "@/lib/dates";
import { num } from "@/lib/format";

interface LabChartProps {
  weeks: string[];
  bands: LabBand[];
  markers: LabMarker[];
  mode: "volume" | "share";
  weekIndex: number;
  onWeekChange: (index: number) => void;
}

const monthYear = new Intl.DateTimeFormat("fr-FR", {
  month: "short", year: "2-digit", timeZone: "UTC",
});

function volumeAxis(peak: number) {
  const roughStep = Math.max(1, peak / 4);
  const power = 10 ** Math.floor(Math.log10(roughStep));
  const step = ([1, 2, 5, 10].find((factor) => factor * power >= roughStep) ?? 10) * power;
  const intervals = Math.max(1, Math.ceil(peak / step));
  return Array.from({ length: intervals + 1 }, (_, i) => i * step);
}

// Une semaine absente interrompt le tracé. Une semaine présente à zéro reste
// un point sur la courbe de volume, mais n'a pas de répartition définie.
function weekRuns(offsets: number[], totals?: number[]) {
  const runs: number[][] = [];
  let run: number[] = [];
  for (let i = 0; i < offsets.length; i++) {
    if (totals?.[i] === 0 || (i > 0 && offsets[i] !== offsets[i - 1] + 1)) {
      if (run.length) runs.push(run);
      run = [];
    }
    if (totals?.[i] !== 0) run.push(i);
  }
  if (run.length) runs.push(run);
  return runs;
}

function shareAreas(bands: LabBand[], offsets: number[], x: (index: number) => number, y: (value: number) => number, box: ChartBox) {
  const totals = offsets.map((_, i) => bands.reduce((sum, band) => sum + band.clicks[i], 0));
  const runs = weekRuns(offsets, totals);
  const cumulative = offsets.map(() => 0);
  const halfWeek = (box.w - box.pl - box.pr) / (2 * Math.max(1, offsets[offsets.length - 1]));
  return bands.map(band => {
    const paths = runs.map(run => {
      const top: string[] = [];
      const bottom: string[] = [];
      for (const i of run) {
        const low = y(100 * cumulative[i] / totals[i]);
        cumulative[i] += band.clicks[i];
        const high = y(100 * cumulative[i] / totals[i]);
        const positions = run.length === 1
          ? [Math.max(box.pl, x(i) - halfWeek), Math.min(box.w - box.pr, x(i) + halfWeek)]
          : [x(i)];
        for (const px of positions) {
          top.push(`${px.toFixed(1)} ${high.toFixed(1)}`);
          bottom.push(`${px.toFixed(1)} ${low.toFixed(1)}`);
        }
      }
      return `M${top.join(" L")} L${bottom.reverse().join(" L")} Z`;
    });
    return { key: band.key, path: paths.join(" ") };
  });
}

export function LabChart({ weeks, bands, markers, mode, weekIndex, onWeekChange }: LabChartProps) {
  const id = useId();
  const svg = useRef<SVGSVGElement>(null);
  const [width, setWidth] = useState(760);
  useEffect(() => {
    const element = svg.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => {
      if (entry.contentRect.width > 0) setWidth(Math.round(entry.contentRect.width));
    });
    observer.observe(element);
    return () => observer.disconnect();
  }, [weeks.length, bands.length]);

  const count = weeks.length;
  if (!count || !bands.length) return null;
  const box: ChartBox = { w: width, h: 238, pl: 47, pr: 12, pt: 26, pb: 30 };
  const offsets = weeks.map(week => dayDiff(weeks[0], week) / 7);
  const calendarWeeks = offsets[count - 1] + 1;
  const calendarX = xScaleIndex(box, Math.max(2, calendarWeeks));
  const x = (i: number) => count === 1 ? (box.pl + width - box.pr) / 2 : calendarX(offsets[i]);
  const runs = weekRuns(offsets);
  const isShare = mode === "share";
  const ticks = isShare ? [0, 25, 50, 75, 100] : volumeAxis(Math.max(...bands.map(band => Math.max(...band.clicks))));
  const y = yScale(box, 0, ticks[ticks.length - 1]);
  const selected = Math.min(Math.max(weekIndex, 0), count - 1);
  const noteWeeks = [...new Set(markers.map(marker => marker.index))].sort((a, b) => a - b);
  const unit = isShare ? "Part des clics des catégories visibles (%)" : "Clics par semaine";
  const xTicks = [0];
  for (let i = 1; i < count - 1; i++) {
    const newMonth = weeks[i].slice(0, 7) !== weeks[i - 1].slice(0, 7);
    if ((count <= 12 || newMonth) && x(i) - x(xTicks[xTicks.length - 1]) >= 76 && x(count - 1) - x(i) >= 76) {
      xTicks.push(i);
    }
  }
  if (count > 1) xTicks.push(count - 1);

  return (
    <div className="min-w-0 px-3 py-3 sm:px-5 sm:py-4">
      <p className="mb-1 font-mono text-[11px] uppercase tracking-[0.055em] text-muted">{unit}</p>
      <svg ref={svg} viewBox={`0 0 ${width} ${box.h}`} preserveAspectRatio="none"
        className="block h-[238px] w-full touch-pan-y cursor-crosshair" role="img" aria-labelledby={`${id}-title ${id}-detail`}
        onClick={(event) => {
          const marker = event.target instanceof Element && event.target.closest("[data-marker-week]");
          if (marker) {
            onWeekChange(Number(marker.getAttribute("data-marker-week")));
            return;
          }
          const rect = event.currentTarget.getBoundingClientRect();
          const offset = indexFromPointerX(event.clientX - rect.left, rect.width, box, calendarWeeks);
          const index = offset === null ? -1 : offsets.indexOf(offset);
          if (index >= 0) onWeekChange(index);
        }}>
        <title id={`${id}-title`}>{unit}</title>
        <desc id={`${id}-detail`}>{count} semaines du {dateFr(weeks[0])} au lundi {dateFr(weeks[count - 1])}. Le curseur sous le graphique permet de lire chaque semaine.</desc>
        {ticks.map(tick => (
          <g key={tick}>
            <line x1={box.pl} x2={width - box.pr} y1={y(tick)} y2={y(tick)}
              stroke={tick === 0 ? "var(--color-line-strong)" : "var(--color-line)"} strokeDasharray={tick === 0 ? undefined : "3 4"} />
            <text x={box.pl - 7} y={y(tick) + 4} textAnchor="end" fontSize="10.5" className="fill-muted font-mono">
              {isShare ? `${tick} %` : num(tick)}
            </text>
          </g>
        ))}
        {isShare ? shareAreas(bands, offsets, x, y, box).map(area => (
          <path key={area.key} d={area.path} fill={`var(--color-lab-${area.key})`} stroke="var(--color-panel)" strokeWidth="0.75" />
        )) : bands.map(band => (
          <g key={band.key} stroke={`var(--color-lab-${band.key})`}>
            {runs.map(run => run.length === 1 ? (
              <circle key={run[0]} cx={x(run[0])} cy={y(band.clicks[run[0]])} r="2" fill={`var(--color-lab-${band.key})`} />
            ) : (
              <path key={run[0]} d={buildLinePath(run.map(i => band.clicks[i]), i => x(run[i]), y)} fill="none"
                strokeWidth={band.key === "ressource" ? 2.8 : 2}
                strokeDasharray={band.key === "divers" ? "7 3" : band.key === "expertise" ? "2 3" : undefined}
                strokeLinejoin="round" strokeLinecap="round" />
            ))}
          </g>
        ))}
        {xTicks.map((index, rank) => (
          <text key={index} x={x(index)} y={box.h - 9} fontSize="10.5" className="fill-muted font-mono"
            textAnchor={xTicks.length === 1 ? "middle" : rank === 0 ? "start" : rank === xTicks.length - 1 ? "end" : "middle"}>
            {count <= 12 ? jjmm(weeks[index]) : monthYear.format(new Date(`${weeks[index]}T00:00:00Z`))}
          </text>
        ))}
        {noteWeeks.map(index => (
          <g key={index} data-marker-week={index}>
            <title>{markers.filter(marker => marker.index === index).map(marker => `${dateFr(marker.day)} · ${marker.label}`).join(" / ")}</title>
            <line x1={x(index)} x2={x(index)} y1={box.pt - 7} y2={y(0)}
              stroke="var(--color-alert)" strokeOpacity=".45" strokeDasharray="2 5" />
            <path d={`M ${x(index) - 3} ${box.pt - 12} l 3 -4 l 3 4 l -3 4 Z`} fill="var(--color-alert)" />
          </g>
        ))}
        <line x1={x(selected)} x2={x(selected)} y1={box.pt} y2={y(0)}
          stroke="var(--color-ink)" strokeWidth="1" strokeDasharray="4 3" />
        {!isShare && bands.map(band => (
          <circle key={band.key} cx={x(selected)} cy={y(band.clicks[selected])} r="3.6"
            fill={`var(--color-lab-${band.key})`} stroke="var(--color-panel)" strokeWidth="1.4" />
        ))}
      </svg>
      <label className="mt-1 flex min-h-8 items-center gap-3 font-mono text-[11px] text-muted">
        <span className="shrink-0">Semaine lue</span>
        <input type="range" min="0" max={count - 1} step="1" value={selected}
          aria-valuetext={`Semaine du ${dateFr(weeks[selected])}`} disabled={count === 1}
          onChange={event => onWeekChange(event.currentTarget.valueAsNumber)}
          className="h-6 min-w-0 flex-1 cursor-pointer accent-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink" />
      </label>
    </div>
  );
}
