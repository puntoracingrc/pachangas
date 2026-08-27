import {
  tournamentError,
  tournamentJson,
  tournamentRecord,
  tournamentSession,
  tournamentUuidPattern,
} from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await context.params;
    if (!tournamentUuidPattern.test(competitionId)) throw new Error("TOURNAMENT_NOT_FOUND");
    const { client } = await tournamentSession(request);
    const hub = await client.rpc("get_pachanga_tournament_group_hub_v1", {
      competition_id: competitionId,
    });
    if (!hub.error) return tournamentJson(hub.data);
    if (!/TOURNAMENT_GROUP_STAGE_NOT_PREPARED/i.test(hub.error.message)) {
      throw new Error(hub.error.message);
    }
    const source = await client.rpc("get_pachanga_tournament_snapshot_v1", {
      competition_id: competitionId,
    });
    if (source.error) throw new Error(source.error.message);
    const snapshot = tournamentRecord(source.data);
    const competition = tournamentRecord(snapshot.competition);
    return tournamentJson({
      capabilities: snapshot.capabilities,
      competition,
      drawPlans: snapshot.drawPlans,
      expectedRevision: competition.tournamentRevision,
      kind: "TournamentGroupStageSetup",
      setup: {
        message: "El sorteo está publicado. La fase de grupos todavía no se ha preparado.",
        status: "NOT_PREPARED",
      },
    });
  } catch (error) {
    return tournamentError(error);
  }
}
