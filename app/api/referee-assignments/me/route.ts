import { refereeError, refereeJson, refereeSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await refereeSession(request);
    const result = await client.rpc("get_my_pachanga_referee_assignments_v1");
    if (result.error) return refereeError(result.error);
    return refereeJson(result.data);
  } catch (error) {
    return refereeError(error);
  }
}
