import { tournamentError, tournamentJson, tournamentSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await tournamentSession(request);
    const result = await client.rpc("get_pachanga_tournament_home_v1");
    if (result.error) throw new Error(result.error.message);
    return tournamentJson(result.data);
  } catch (error) {
    return tournamentError(error);
  }
}
