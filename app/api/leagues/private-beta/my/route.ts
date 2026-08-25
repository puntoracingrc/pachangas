import { leagueBetaError, leagueBetaJson, leagueBetaSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await leagueBetaSession(request);
    const result = await client.rpc("get_my_pachanga_league_private_beta_v1");
    if (result.error) throw new Error(result.error.message);
    return leagueBetaJson(result.data);
  } catch (error) {
    return leagueBetaError(error);
  }
}
