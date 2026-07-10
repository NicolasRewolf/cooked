import "server-only";

import { z } from "zod";
import { admin } from "@/lib/supabase-admin";
import type { Period } from "@/data/rpc-schemas";
import { resourcesTrendRpcSchema, type ResourcesTrend } from "@/data/rpc-schemas";

export class RpcError extends Error {
  constructor(
    public readonly rpc: string,
    cause: unknown,
  ) {
    const message =
      cause && typeof cause === "object" && "message" in cause
        ? String((cause as { message: unknown }).message)
        : String(cause);
    super(`RPC ${rpc} a échoué: ${message}`);
    this.name = "RpcError";
  }
}

export class RpcValidationError extends Error {
  constructor(
    public readonly rpc: string,
    public readonly zodError: z.ZodError,
  ) {
    super(`RPC ${rpc} : réponse invalide — ${zodError.issues[0]?.message ?? "contrat Zod"}`);
    this.name = "RpcValidationError";
  }
}

function logRpcFailure(rpc: string, detail: string) {
  console.error(`RPC ${rpc} : ${detail}`);
}

export async function callRpc<T>(
  rpc: string,
  args: Record<string, unknown> | undefined,
  schema: z.ZodType<T>,
): Promise<T> {
  const { data, error } = await admin.rpc(rpc, args ?? {});
  if (error) throw new RpcError(rpc, error);

  const parsed = schema.safeParse(data);
  if (!parsed.success) throw new RpcValidationError(rpc, parsed.error);
  return parsed.data;
}

export interface TrendResult {
  data: ResourcesTrend | null;
  error: boolean;
}

/** Politique « soft » pour les tendances : distingue panne RPC vs série vide. */
export async function callRpcTrend(rpc: string, period: Period): Promise<TrendResult> {
  try {
    const { data, error } = await admin.rpc(rpc, { period_kind: period });
    if (error) {
      logRpcFailure(rpc, error.message);
      return { data: null, error: true };
    }
    if (data == null) return { data: null, error: false };

    const parsed = resourcesTrendRpcSchema.safeParse(data);
    if (!parsed.success) {
      logRpcFailure(rpc, `réponse invalide — ${parsed.error.issues[0]?.message}`);
      return { data: null, error: true };
    }
    return { data: parsed.data, error: false };
  } catch (cause) {
    logRpcFailure(rpc, `exception — ${String(cause)}`);
    return { data: null, error: true };
  }
}
