"use client";

import { useState } from "react";
import { buildArticleAnalysisPrompt, type ArticleAnalysisContext } from "@/lib/analysis-prompt";

// « Creuser avec Claude » : copie une question prête à coller dans une session
// Cooked (Claude Code). Le dashboard est la carte, la conversation le véhicule.
export function AskClaude(context: ArticleAnalysisContext) {
  const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle");
  const prompt = buildArticleAnalysisPrompt(context);

  async function copy() {
    try {
      await navigator.clipboard.writeText(prompt);
      setCopyState("copied");
      setTimeout(() => setCopyState("idle"), 2000);
    } catch {
      setCopyState("failed");
    }
  }

  return (
    <button
      type="button"
      onClick={copy}
      className="border border-line bg-panel px-3 py-1.5 font-mono text-[11px] text-muted transition-colors hover:border-accent hover:text-accent"
      title="Copie une question prête à coller dans ta session Claude Code"
      aria-live="polite"
    >
      {copyState === "copied" ? "✓ question copiée" : copyState === "failed" ? "copie impossible · réessayer" : "copier pour Claude"}
    </button>
  );
}
