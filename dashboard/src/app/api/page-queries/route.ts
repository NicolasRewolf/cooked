import { unstable_rethrow } from "next/navigation";
import { getPageQueries, pageQueryParamsSchema } from "@/lib/page-views";

export const dynamic = "force-dynamic";
const headers = { "Cache-Control": "private, no-store" };

export async function GET(request: Request) {
  const search = new URL(request.url).searchParams;
  const params = pageQueryParamsSchema.safeParse(Object.fromEntries(search));
  if (!params.success || search.getAll("path").length !== 1 || search.getAll("days").length !== 1) {
    return Response.json({ error: "Paramètres invalides." }, { status: 400, headers });
  }
  try {
    return Response.json(await getPageQueries(params.data.path, params.data.days), { headers });
  } catch (error) {
    unstable_rethrow(error);
    return Response.json({ error: "Les données Google sont indisponibles. Réessaie dans un moment." }, { status: 503, headers });
  }
}
