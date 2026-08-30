import { venueApiError, venueApiJson, venueApiSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await venueApiSession(request);
    const result = await client.rpc("get_pachanga_my_venue_reservations_v1");
    if (result.error) throw result.error;
    return venueApiJson(result.data);
  } catch (error) {
    return venueApiError(error);
  }
}
