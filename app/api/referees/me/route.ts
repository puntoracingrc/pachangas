import { refereeError, refereeJson, refereeSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await refereeSession(request);
    const result = await client.rpc("get_my_pachanga_referee_platform_v1");
    if (result.error) throw new Error(result.error.message);
    return refereeJson(result.data);
  } catch (error) {
    return refereeError(error);
  }
}
