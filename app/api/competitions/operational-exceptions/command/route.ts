import {
  leagueOperationalClientMetadata,
  leagueOperationalCommandPayload,
  leagueOperationalError,
  leagueOperationalJson,
  leagueOperationalRecord,
  leagueOperationalSession,
  leagueOperationalUuidPattern,
  leagueOperationalWriteGate,
  parseLeagueOperationalAction,
  requireLeagueOperationalOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireLeagueOperationalOrigin(request);
    const gated = leagueOperationalWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 50_000) {
      return leagueOperationalJson({ error: "LEAGUE_OPERATIONAL_EXCEPTIONS_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await leagueOperationalSession(request);
    const body = leagueOperationalRecord(await request.json());
    const action = parseLeagueOperationalAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!leagueOperationalUuidPattern.test(operationId) || !leagueOperationalUuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
    }
    const result = await client.rpc("command_pachanga_league_operational_exceptions_v1", {
      action,
      aggregate_id: aggregateId,
      client_metadata: leagueOperationalClientMetadata(request, "league_operational_exceptions"),
      command_payload: leagueOperationalCommandPayload(action, leagueOperationalRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueOperationalJson({ canonical: result.data });
  } catch (error) {
    return leagueOperationalError(error);
  }
}
