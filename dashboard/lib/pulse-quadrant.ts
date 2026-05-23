/**
 * Constantes visuelles partagées pour le Pulse cross-source.
 *
 * Source unique de vérité pour :
 *   - les libellés humains de chaque quadrant
 *   - les couleurs de fond / texte / ligne (sparkline)
 *
 * Importé par : site-pulse-card.tsx, page-trend-panel.tsx,
 * quadrant-badge.tsx. À utiliser pour toute nouvelle surface Pulse.
 */
import type { PulseQuadrant } from "@/lib/cooked";

export const QUADRANT_HEADLINE: Record<PulseQuadrant, string> = {
  up_up: "La machine tourne",
  up_down: "Trafic ↗ mais engagement ↘",
  down_up: "Audience plus qualifiée",
  down_down: "Perte de vitesse",
  neutral: "Période stable",
  no_signal: "Pas assez de signal",
};

/** Variante orientée "fiche page" (singulier) — sémantique identique */
export const QUADRANT_HEADLINE_PAGE: Record<PulseQuadrant, string> = {
  up_up: "La page performe",
  up_down: "Trafic ↗ mais engagement ↘",
  down_up: "Audience plus qualifiée",
  down_down: "Page en perte de vitesse",
  neutral: "Stable",
  no_signal: "Pas assez de signal",
};

/** Classe Tailwind pour le fond + bordure d'une carte Pulse */
export const QUADRANT_STYLE: Record<PulseQuadrant, string> = {
  up_up: "border-success/30 bg-success/5",
  up_down: "border-warning/30 bg-warning/5",
  down_up: "border-info/30 bg-info/5",
  down_down: "border-danger/30 bg-danger/5",
  neutral: "border-border bg-surface",
  no_signal: "border-border bg-surface",
};

/** Classe Tailwind pour le texte (titre/icône) selon le quadrant */
export const QUADRANT_TEXT: Record<PulseQuadrant, string> = {
  up_up: "text-success",
  up_down: "text-warning",
  down_up: "text-info",
  down_down: "text-danger",
  neutral: "text-muted-foreground",
  no_signal: "text-muted-foreground",
};

/** Couleur CSS (variable) pour la stroke d'une sparkline Recharts */
export const QUADRANT_LINE: Record<PulseQuadrant, string> = {
  up_up: "var(--success)",
  up_down: "var(--warning)",
  down_up: "var(--info)",
  down_down: "var(--danger)",
  neutral: "var(--muted-foreground)",
  no_signal: "var(--muted-foreground)",
};
