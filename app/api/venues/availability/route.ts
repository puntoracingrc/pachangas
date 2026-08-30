import { noStoreHeaders } from "../../client-policy/_contract";
import { getPublicVenueAvailability } from "../../../public-product-data";
import { venueUuidPattern } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  const url = new URL(request.url);
  const pitchId = url.searchParams.get("pitchId") ?? "";
  const startsAt = url.searchParams.get("startsAt") ?? "";
  const endsAt = url.searchParams.get("endsAt") ?? "";
  const modality = (url.searchParams.get("modality") ?? "").toUpperCase();
  if (!venueUuidPattern.test(pitchId) || Number.isNaN(Date.parse(startsAt)) || Number.isNaN(Date.parse(endsAt))
      || !new Set(["F5", "F7", "F11", "FUTSAL"]).has(modality)) {
    return Response.json({ error: "VENUE_AVAILABILITY_FILTER_INVALID" }, { headers: noStoreHeaders, status: 400 });
  }
  const result = await getPublicVenueAvailability(pitchId, startsAt, endsAt, modality);
  if (!result) {
    return Response.json({ error: "VENUE_AVAILABILITY_UNAVAILABLE" }, { headers: noStoreHeaders, status: 503 });
  }
  return Response.json(result, { headers: noStoreHeaders });
}
