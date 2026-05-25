import { redirect } from "next/navigation";
import { parsePeriod } from "@/lib/period";
import { hrefWithPeriod } from "@/lib/period";

export const dynamic = "force-dynamic";

type Props = { searchParams: Promise<{ period?: string }> };

export default async function RootRedirect({ searchParams }: Props) {
  const period = parsePeriod(await searchParams);
  redirect(hrefWithPeriod("/activite", period));
}
