import type { AssistedQuarter } from "@/lib/types";

// B3 — un seul cap, sobre, au-dessus des KPI. Cible absente → « à fixer » (dim) :
// jamais de valeur inventée (Nicolas la posera dans cooked_config).
export function ObjectiveLine({ q }: { q: AssistedQuarter }) {
  return (
    <div className="font-mono text-[11.5px] text-muted">
      <span className="uppercase tracking-[0.04em] text-faint">Contacts nourris par les articles</span>
      {" — "}
      {q.quarter} : <span className="font-semibold text-ink">{q.value}</span>
      {" / objectif "}
      {q.target != null ? (
        <span className="font-semibold text-ink">{q.target}</span>
      ) : (
        <span className="text-dim">à fixer</span>
      )}
    </div>
  );
}
