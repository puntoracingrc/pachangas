import { venueApiError, venueApiJson, venueApiSession, venueUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ canonicalMatchId: string }> }) {
  try {
    const { canonicalMatchId } = await params;
    if (!venueUuidPattern.test(canonicalMatchId)) throw new Error("VENUE_MATCH_NOT_FOUND");
    const { client } = await venueApiSession(request);
    const result = await client.rpc("get_pachanga_match_venue_v1", { target_canonical_match_id: canonicalMatchId });
    if (result.error) throw result.error;
    return venueApiJson(result.data);
  } catch (error) {
    return venueApiError(error);
  }
}
