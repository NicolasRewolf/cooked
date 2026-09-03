// T-13 (mission 02/09/2026, #114) — les schémas Zod sont confrontés au contrat des RPC dashboard
// tel que la PROD le publie (contracts/dashboard_rpc_columns.json, généré par
// scripts/generate_dashboard_contracts.py). Sans base : clés et nullabilité. Avec
// DASHBOARD_RPC_SAMPLES=<fichier> (prod-drift.yml) : parse d'un appel réel par RPC.
import { existsSync, readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { z } from "zod";
import contract from "../../../contracts/dashboard_rpc_columns.json";
import {
  annotationSchema,
  annotationRowsSchema,
  articleDetailSchema,
  assistedQuarterSchema,
  assistedRowSchema,
  assistedRowsSchema,
  cohortsResultSchema,
  expertiseKpisSchema,
  expertiseRowSchema,
  expertiseRowsSchema,
  honorairesFunnelSchema,
  interventionEffectSchema,
  labGscWeeklySchema,
  resourceKpisSchema,
  resourceRowSchema,
  resourceRowsSchema,
  resourcesTrendRowSchema,
  resourcesTrendRpcSchema,
  seoKpisSchema,
  seoQueryRowSchema,
  seoQueryRowsSchema,
} from "./rpc-schemas";

type Entry = {
  kind: "table" | "setof" | "jsonb";
  columns?: string[];
  not_null?: string[];
  relation?: string;
  sample_call: string | null;
};
const CONTRACT = contract as Record<string, Entry>;

/** Schéma « ligne » (objet) et schéma « réponse » (ce que callRpc parse) par RPC. */
const SCHEMAS: Record<string, { row: z.ZodType; response: z.ZodType }> = {
  dashboard_annotations: { row: annotationSchema, response: annotationRowsSchema },
  dashboard_article_detail: { row: articleDetailSchema, response: articleDetailSchema.nullable() },
  dashboard_assisted_quarter: { row: assistedQuarterSchema, response: assistedQuarterSchema },
  dashboard_expertises_kpis: { row: expertiseKpisSchema, response: expertiseKpisSchema },
  dashboard_expertises_overview: { row: expertiseRowSchema, response: expertiseRowsSchema },
  dashboard_expertises_trend: { row: resourcesTrendRowSchema, response: resourcesTrendRpcSchema },
  dashboard_honoraires_funnel: { row: honorairesFunnelSchema, response: honorairesFunnelSchema },
  dashboard_intervention_effect: { row: interventionEffectSchema, response: interventionEffectSchema },
  dashboard_lab_gsc_weekly: { row: labGscWeeklySchema, response: labGscWeeklySchema },
  dashboard_resources_assisted: { row: assistedRowSchema, response: assistedRowsSchema },
  dashboard_resources_cohorts: { row: cohortsResultSchema, response: cohortsResultSchema },
  dashboard_resources_kpis: { row: resourceKpisSchema, response: resourceKpisSchema },
  dashboard_resources_overview: { row: resourceRowSchema, response: resourceRowsSchema },
  dashboard_resources_trend: { row: resourcesTrendRowSchema, response: resourcesTrendRpcSchema },
  dashboard_seo_by_query: { row: seoQueryRowSchema, response: seoQueryRowsSchema },
  dashboard_seo_kpis: { row: seoKpisSchema, response: seoKpisSchema },
};

// ── Introspection Zod v4 : descend array / pipe (transform) / nullable / optional jusqu'à l'objet.
type Def = { type: string; shape?: Record<string, z.ZodType>; element?: z.ZodType; in?: z.ZodType; innerType?: z.ZodType };
function def(s: z.ZodType): Def {
  return (s as unknown as { _zod: { def: Def } })._zod.def;
}
function toObject(s: z.ZodType): z.ZodObject | null {
  const d = def(s);
  if (d.type === "object") return s as z.ZodObject;
  if (d.type === "array" && d.element) return toObject(d.element);
  if (d.type === "pipe" && d.in) return toObject(d.in);
  if ((d.type === "nullable" || d.type === "optional") && d.innerType) return toObject(d.innerType);
  return null;
}
function fieldInfo(s: z.ZodType): { optional: boolean; nullable: boolean } {
  let optional = false;
  let nullable = false;
  let cur: z.ZodType | undefined = s;
  while (cur) {
    const d = def(cur);
    if (d.type === "optional") optional = true;
    else if (d.type === "nullable") nullable = true;
    else if (d.type === "pipe" && d.in) {
      cur = d.in;
      continue;
    } else break;
    cur = d.innerType;
  }
  return { optional, nullable };
}

describe("contrat RPC dashboard ↔ schémas Zod (T-13, I8)", () => {
  it("chaque RPC dashboard de la prod a un schéma Zod, et réciproquement", () => {
    expect(Object.keys(SCHEMAS).sort()).toEqual(Object.keys(CONTRACT).sort());
  });

  for (const [rpc, entry] of Object.entries(CONTRACT)) {
    const obj = toObject(SCHEMAS[rpc].row);
    it(`${rpc} : clés Zod = colonnes prod (${entry.kind})`, () => {
      expect(obj, "schéma ligne introspectable").not.toBeNull();
      const shape = obj!.shape as Record<string, z.ZodType>;
      const zodKeys = Object.keys(shape);
      const required = zodKeys.filter((k) => !fieldInfo(shape[k]).optional);
      const columns = entry.columns ?? [];
      // Toute clé Zod obligatoire doit exister en prod.
      expect(required.filter((k) => !columns.includes(k))).toEqual([]);
      // Toute colonne prod doit être connue du Zod (obligatoire ou optionnelle).
      expect(columns.filter((c) => !zodKeys.includes(c))).toEqual([]);
    });

    if (entry.kind === "setof") {
      it(`${rpc} : un champ Zod non nullable est une colonne NOT NULL de ${entry.relation}`, () => {
        const shape = obj!.shape as Record<string, z.ZodType>;
        const notNull = new Set(entry.not_null ?? []);
        const offenders = Object.keys(shape).filter((k) => {
          const info = fieldInfo(shape[k]);
          return !info.optional && !info.nullable && !notNull.has(k);
        });
        expect(offenders).toEqual([]);
      });
    }
  }
});

// ── Échantillons prod (CI prod-drift.yml). Ignoré sans fichier.
const samplesPath = process.env.DASHBOARD_RPC_SAMPLES;
const hasSamples = !!samplesPath && existsSync(samplesPath);
describe.skipIf(!hasSamples)("réponses prod réelles parsées par les schémas Zod (T-13, I8)", () => {
  const samples = hasSamples
    ? (JSON.parse(readFileSync(samplesPath!, "utf8")) as Record<string, unknown>)
    : {};
  for (const rpc of Object.keys(SCHEMAS)) {
    it(`${rpc} : l'appel réel passe le contrat Zod`, () => {
      expect(rpc in samples, `échantillon présent pour ${rpc}`).toBe(true);
      const parsed = SCHEMAS[rpc].response.safeParse(samples[rpc]);
      expect(parsed.success, parsed.success ? "" : JSON.stringify(parsed.error.issues.slice(0, 3))).toBe(true);
    });
  }
});
