import { leagueError, leagueJson, leagueSession, leagueUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ entryId: string }> }) {
  try {
    const { entryId } = await params;
    if (!leagueUuidPattern.test(entryId)) throw new Error("ENTRY_NOT_FOUND");
    const { client } = await leagueSession(request);
    const result = await client.rpc("get_pachanga_competition_entry_v1", { target_entry_id: entryId });
    if (result.error) throw new Error(result.error.message);
    return leagueJson(result.data);
  } catch (error) {
    return leagueError(error);
  }
}
