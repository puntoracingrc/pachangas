import { venueApiError, venueApiJson, venueApiSession } from "../_shared";

export async function GET(request: Request) {
  try {
    const { client } = await venueApiSession(request);
    const [venueResult, seasonResult] = await Promise.all([
      client.rpc("get_pachanga_venue_home_status_v1"),
      client.rpc("get_pachanga_season_venue_home_status_v1"),
    ]);
    if (venueResult.error) throw new Error(venueResult.error.message);
    return venueApiJson({
      ...(venueResult.data && typeof venueResult.data === "object" ? venueResult.data : {}),
      seasonVenue: seasonResult.error ? null : seasonResult.data,
    });
  } catch (error) {
    return venueApiError(error);
  }
}
