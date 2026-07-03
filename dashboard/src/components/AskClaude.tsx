"use client";

import { useState } from "react";

// « Creuser avec Claude » : copie une question prête à coller dans une session
// Cooked (Claude Code). Le dashboard est la carte, la conversation le véhicule.
export function AskClaude({ path, period }: { path: string; period: string }) {
  const [copied, setCopied] = useState(false);
  const prompt =
    `Cooked : analyse l'article ${path} (fenêtre ${period === "rolling_90" ? "90 j" : "28 j"}). ` +
    `Je regarde sa fiche dashboard — explique-moi ce que je vois : trajectoire, requêtes, ` +
    `composantes santé, et dis-moi s'il y a UNE action à faire (ou laisser mûrir).`;

  async function copy() {
    try {
      await navigator.clipboard.writeText(prompt);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard indisponible : silencieux */
    }
  }

  return (
    <button
      type="button"
      onClick={copy}
      className="border border-line bg-panel px-3 py-1.5 font-mono text-[11px] text-muted transition-colors hover:border-accent hover:text-accent"
      title="Copie une question prête à coller dans ta session Claude Code"
    >
      {copied ? "✓ question copiée" : "⌘ creuser avec Claude"}
    </button>
  );
}
