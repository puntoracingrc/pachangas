import { publicCompetitionError, publicCompetitionJson, publicCompetitionSession, publicCompetitionUuidPattern } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await publicCompetitionSession(request);
    const url = new URL(request.url);
    const teamId = url.searchParams.get("teamId")?.trim() ?? "";
    if (teamId && !publicCompetitionUuidPattern.test(teamId)) throw new Error("INVALID_PUBLIC_COMPETITION_TEAM");
    const result = await client.rpc("get_my_pachanga_competition_registration_requests_v1", {
      page_offset: 0,
      page_size: 100,
      target_team_id: teamId || null,
    });
    if (result.error) throw new Error(result.error.message);
    return publicCompetitionJson(result.data);
  } catch (error) { return publicCompetitionError(error); }
}
