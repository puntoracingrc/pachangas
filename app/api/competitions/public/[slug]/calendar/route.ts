import { getPublicCompetitionCalendar } from "../../../../../public-product-data";
import { publicCompetitionCacheJson, publicCompetitionSlugPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!publicCompetitionSlugPattern.test(slug)) return publicCompetitionCacheJson({ error: "PUBLIC_CALENDAR_NOT_FOUND" }, 404, 10);
  const url = new URL(request.url);
  const result = await getPublicCompetitionCalendar(slug, bounded(url.searchParams.get("page"), 1, 100_000), bounded(url.searchParams.get("pageSize"), 50, 100));
  return result
    ? publicCompetitionCacheJson(result, 200, 60)
    : publicCompetitionCacheJson({ error: "PUBLIC_CALENDAR_NOT_FOUND" }, 404, 10);
}
