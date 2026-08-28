import { searchPublicCompetitions } from "../../../../public-product-data";
import { publicCompetitionCacheJson } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const page = bounded(url.searchParams.get("page"), 1, 100_000);
  const pageSize = bounded(url.searchParams.get("pageSize"), 24, 60);
  const result = await searchPublicCompetitions({
    area: url.searchParams.get("area")?.slice(0, 160) ?? "",
    registration: url.searchParams.get("registration")?.slice(0, 24) ?? "",
    search: url.searchParams.get("search")?.slice(0, 160) ?? "",
    sportFormat: url.searchParams.get("sportFormat")?.slice(0, 32) ?? "",
    state: url.searchParams.get("state")?.slice(0, 32) ?? "",
    type: url.searchParams.get("type")?.slice(0, 24) ?? "",
  }, page, pageSize);
  if (!result) return publicCompetitionCacheJson({ error: "PUBLIC_COMPETITION_DIRECTORY_UNAVAILABLE" }, 503, 10);
  return publicCompetitionCacheJson({ ...(result as Record<string, unknown>), page }, 200, 45);
}
