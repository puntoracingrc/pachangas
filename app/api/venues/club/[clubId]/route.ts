import { venueApiError, venueApiJson, venueApiSession, venueUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ clubId: string }> }) {
  try {
    const { clubId } = await params;
    if (!venueUuidPattern.test(clubId)) throw new Error("VENUE_CLUB_NOT_FOUND");
    const { client } = await venueApiSession(request);
    const result = await client.rpc("get_pachanga_club_venue_desk_v1", { target_club_id: clubId });
    if (result.error) throw result.error;
    return venueApiJson(result.data);
  } catch (error) {
    return venueApiError(error);
  }
}
