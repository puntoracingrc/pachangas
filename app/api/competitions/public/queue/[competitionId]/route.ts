import { publicCompetitionError, publicCompetitionJson, publicCompetitionSession, publicCompetitionUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!publicCompetitionUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const { client } = await publicCompetitionSession(request);
    const status = new URL(request.url).searchParams.get("status")?.trim() || null;
    const result = await client.rpc("get_pachanga_competition_registration_queue_v1", {
      page_offset: 0,
      page_size: 200,
      status_filter: status,
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return publicCompetitionJson(result.data);
  } catch (error) { return publicCompetitionError(error); }
}
