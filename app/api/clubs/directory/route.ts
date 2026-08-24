import { noStoreHeaders } from "../../client-policy/_contract";
import { searchPublicClubs } from "../../../public-product-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const booleanFilter = (name: string) => {
    const value = url.searchParams.get(name);
    return value === "true" || value === "false" ? value : "";
  };
  const filters = {
    clubType: url.searchParams.get("type")?.slice(0, 40) ?? "",
    municipality: url.searchParams.get("municipality")?.slice(0, 120) ?? "",
    partner: booleanFilter("partner"),
    query: url.searchParams.get("query")?.slice(0, 160) ?? "",
    verified: booleanFilter("verified"),
    zone: url.searchParams.get("zone")?.slice(0, 160) ?? "",
  };
  const result = await searchPublicClubs(
    filters,
    bounded(url.searchParams.get("page"), 1, 100_000),
    bounded(url.searchParams.get("pageSize"), 24, 60),
  );
  if (!result) {
    return Response.json({ error: "CLUB_DIRECTORY_UNAVAILABLE" }, { headers: noStoreHeaders, status: 503 });
  }
  return Response.json(result, { headers: noStoreHeaders });
}
