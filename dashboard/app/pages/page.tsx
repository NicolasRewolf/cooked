import { redirect } from "next/navigation";
import { hrefWithPeriod, parsePeriod } from "@/lib/period";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ period?: string }> };

/** Ancienne route — redirige vers Croisement. */
export default async function PagesRedirect({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  redirect(hrefWithPeriod("/croisement", period));
}
