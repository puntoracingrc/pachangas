import { teamOperationalError, teamOperationalJson, teamOperationalSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await teamOperationalSession(request);
    const result = await client.rpc("get_my_pachanga_team_operational_states_v1");
    if (result.error) throw new Error(result.error.message);
    return teamOperationalJson({ canonical: result.data });
  } catch (error) {
    return teamOperationalError(error);
  }
}
