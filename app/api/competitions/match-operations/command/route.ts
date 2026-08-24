import {
  leagueMatchClientMetadata,
  leagueMatchCommandPayload,
  leagueMatchError,
  leagueMatchJson,
  leagueMatchRecord,
  leagueMatchSession,
  leagueMatchUuidPattern,
  leagueMatchWriteGate,
  parseLeagueMatchAction,
  requireLeagueMatchOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireLeagueMatchOrigin(request);
    const gated = leagueMatchWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 40_000) {
      return leagueMatchJson({ error: "LEAGUE_MATCH_OPERATIONS_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await leagueMatchSession(request);
    const body = leagueMatchRecord(await request.json());
    const action = parseLeagueMatchAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!leagueMatchUuidPattern.test(operationId) || !leagueMatchUuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    }
    const result = await client.rpc("command_pachanga_league_match_operations_v1", {
      action,
      aggregate_id: aggregateId,
      client_metadata: leagueMatchClientMetadata(request, "league_match_operations"),
      command_payload: leagueMatchCommandPayload(action, leagueMatchRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueMatchJson({ canonical: result.data });
  } catch (error) {
    return leagueMatchError(error);
  }
}
