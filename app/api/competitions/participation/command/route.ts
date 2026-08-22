import {
  leagueClientMetadata,
  leagueCommandPayload,
  leagueError,
  leagueJson,
  leagueRecord,
  leagueSession,
  leagueUuidPattern,
  leagueWriteGate,
  parseLeagueAction,
  requireLeagueOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireLeagueOrigin(request);
    const gated = leagueWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 40_000) {
      return leagueJson({ error: "LEAGUE_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await leagueSession(request);
    const body = leagueRecord(await request.json());
    const action = parseLeagueAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!leagueUuidPattern.test(operationId) || !leagueUuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_LEAGUE_COMMAND");
    }
    const result = await client.rpc("command_pachanga_league_participation_v1", {
      aggregate_id: aggregateId,
      client_metadata: leagueClientMetadata(request, "league_participation"),
      command_action: action,
      command_payload: leagueCommandPayload(action, leagueRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueJson({ canonical: result.data });
  } catch (error) {
    return leagueError(error);
  }
}
