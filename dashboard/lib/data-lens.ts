/** Aligné sur cooked_period_bounds(period_kind, data_lens) Postgres. */
export type DataLens = "live" | "gsc" | "cross";

export const DATA_LENSES: DataLens[] = ["live", "gsc", "cross"];
