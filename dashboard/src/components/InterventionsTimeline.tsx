import { SectionTitle } from "./ui";
import { dayShort } from "@/lib/annotations";
import type { Annotation } from "@/lib/types";

// B1 — mini-timeline sobre des interventions, sous les graphes de la fiche.
// Masquée si vide. Reçoit des données plates (pas de fonction).
export function InterventionsTimeline({ items }: { items: Annotation[] }) {
  if (!items.length) return null;
  return (
    <section>
      <SectionTitle>interventions [{items.length}]</SectionTitle>
      <ul className="divide-y divide-line border border-line bg-panel">
        {items.map((it, i) => (
          <li key={i} className="flex items-baseline gap-2.5 px-4 py-2">
            <span
              className={it.kind === "site_change" ? "text-accent" : "text-info"}
              style={{ fontSize: "8px", lineHeight: 1 }}
              aria-hidden
            >
              ▲
            </span>
            <span className="w-10 shrink-0 font-mono text-[10.5px] text-dim">{dayShort(it.day)}</span>
            <span className="text-[11.5px] text-[#45423c]">{it.label}</span>
          </li>
        ))}
      </ul>
    </section>
  );
}
