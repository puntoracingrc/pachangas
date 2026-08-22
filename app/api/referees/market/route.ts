import { refereeError, refereeJson, refereeSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request) {
  try {
    const { client } = await refereeSession(request);
    const url = new URL(request.url);
    const filters = {
      availabilityStatus: url.searchParams.get("availability")?.slice(0, 24) ?? "",
      clubId: url.searchParams.get("club")?.slice(0, 40) ?? "",
      endTime: url.searchParams.get("endTime")?.slice(0, 5) ?? "",
      minExperienceYear: url.searchParams.get("experienceSince")?.slice(0, 4) ?? "",
      modality: url.searchParams.get("modality")?.slice(0, 30) ?? "",
      municipality: url.searchParams.get("municipality")?.slice(0, 120) ?? "",
      province: url.searchParams.get("province")?.slice(0, 120) ?? "",
      startTime: url.searchParams.get("startTime")?.slice(0, 5) ?? "",
      verified: url.searchParams.get("verified")?.slice(0, 5) ?? "",
      weekday: url.searchParams.get("weekday")?.slice(0, 1) ?? "",
      zone: url.searchParams.get("zone")?.slice(0, 160) ?? "",
    };
    const result = await client.rpc("search_pachanga_referee_market_v1", {
      target_filters: filters,
      target_page: bounded(url.searchParams.get("page"), 1, 100_000),
      target_page_size: bounded(url.searchParams.get("pageSize"), 24, 60),
    });
    if (result.error) throw new Error(result.error.message);
    return refereeJson(result.data);
  } catch (error) {
    return refereeError(error);
  }
}
