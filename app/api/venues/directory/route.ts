import { noStoreHeaders } from "../../client-policy/_contract";
import { searchPublicVenues } from "../../../public-product-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const date = url.searchParams.get("date")?.slice(0, 10) ?? "";
  const startTime = url.searchParams.get("startTime")?.slice(0, 5) ?? "";
  const endTime = url.searchParams.get("endTime")?.slice(0, 5) ?? "";
  const timezone = url.searchParams.get("timezone")?.slice(0, 80) || "Europe/Madrid";
  let startsAt = "";
  let endsAt = "";
  if (date && startTime && endTime) {
    const start = new Date(date + "T" + startTime + ":00");
    const end = new Date(date + "T" + endTime + ":00");
    if (!Number.isNaN(start.valueOf()) && !Number.isNaN(end.valueOf()) && end > start) {
      startsAt = start.toISOString();
      endsAt = end.toISOString();
    }
  }
  const booleanFilter = (name: string) => url.searchParams.get(name) === "true";
  const filters = {
    accessible: booleanFilter("accessible"),
    changingRooms: booleanFilter("changingRooms"),
    clubId: url.searchParams.get("clubId")?.slice(0, 40) ?? "",
    endsAt,
    environment: url.searchParams.get("environment")?.slice(0, 30) ?? "",
    lighting: booleanFilter("lighting"),
    modality: url.searchParams.get("modality")?.slice(0, 20) ?? "",
    municipality: url.searchParams.get("municipality")?.slice(0, 120) ?? "",
    startsAt,
    surface: url.searchParams.get("surface")?.slice(0, 40) ?? "",
    timezone,
  };
  const result = await searchPublicVenues(
    filters,
    bounded(url.searchParams.get("page"), 1, 100_000),
    bounded(url.searchParams.get("pageSize"), 24, 60),
  );
  if (!result) {
    return Response.json({ error: "VENUE_DIRECTORY_UNAVAILABLE" }, { headers: noStoreHeaders, status: 503 });
  }
  return Response.json(result, { headers: noStoreHeaders });
}
