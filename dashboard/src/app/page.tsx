import { PageViewsTable } from "@/components/PageViewsTable";
import { getPageViews } from "@/lib/page-views";
import { parseFilters } from "@/lib/page-view-filters";

export const dynamic = "force-dynamic";

export default async function Page({ searchParams }: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { days } = parseFilters(await searchParams);
  const data = await getPageViews(days);
  return <PageViewsTable key={`${data.period_start}:${data.period_end}`} data={data} />;
}
