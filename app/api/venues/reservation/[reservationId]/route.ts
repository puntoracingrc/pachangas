import { venueApiError, venueApiJson, venueApiSession, venueUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ reservationId: string }> }) {
  try {
    const { reservationId } = await params;
    if (!venueUuidPattern.test(reservationId)) throw new Error("VENUE_RESERVATION_NOT_FOUND");
    const { client } = await venueApiSession(request);
    const result = await client.rpc("get_pachanga_venue_reservation_v1", { target_reservation_id: reservationId });
    if (result.error) throw result.error;
    return venueApiJson(result.data);
  } catch (error) {
    return venueApiError(error);
  }
}
