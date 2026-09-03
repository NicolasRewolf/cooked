// T-19 (mission 02/09/2026, b-07) — compteur ingest_drops agrégé côté Edge.
// Avant : un aller-retour DB (rpc record_ingest_drop) PAR requête de bot — 3,6 M appels / 28 j.
// Ici : compteurs en mémoire d'isolat, vidés en un seul appel quand ≥ FLUSH_EVERY drops ou quand
// FLUSH_AFTER_MS se sont écoulées depuis le dernier vidage. Un isolat recyclé perd au plus une
// fenêtre de comptage (60 s) — le compteur est un instrument d'audit, pas un chiffre business.

export const FLUSH_EVERY = 100;
export const FLUSH_AFTER_MS = 60_000;

export type DropFlush = (reason: string, n: number) => Promise<void>;

export class IngestDropBuffer {
  private counts = new Map<string, number>();
  private pending = 0;
  private lastFlush: number;

  constructor(private readonly flush: DropFlush, private readonly now: () => number = Date.now) {
    this.lastFlush = now();
  }

  /** Ajoute n drops pour `reason` ; vide si le seuil ou le délai est atteint. Retourne true si vidé. */
  async add(reason: string, n: number): Promise<boolean> {
    if (n <= 0) return false;
    this.counts.set(reason, (this.counts.get(reason) ?? 0) + n);
    this.pending += n;
    if (this.pending >= FLUSH_EVERY || this.now() - this.lastFlush >= FLUSH_AFTER_MS) {
      await this.drain();
      return true;
    }
    return false;
  }

  async drain(): Promise<void> {
    const snapshot = [...this.counts.entries()];
    this.counts.clear();
    this.pending = 0;
    this.lastFlush = this.now();
    for (const [reason, n] of snapshot) {
      try {
        await this.flush(reason, n);
      } catch (e) {
        console.error("[track] ingest_drops flush error:", (e as Error)?.message ?? e);
      }
    }
  }

  get size(): number {
    return this.pending;
  }
}
