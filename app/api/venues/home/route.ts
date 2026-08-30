import { venueApiError, venueApiJson, venueApiSession } from "../_shared";

export async function GET(request: Request) {
  try {
    const { client } = await venueApiSession(request);
    const result = await client.rpc("get_pachanga_venue_home_status_v1");
    if (result.error) throw new Error(result.error.message);
    return venueApiJson(result.data);
  } catch (error) {
    return venueApiError(error);
  }
}
