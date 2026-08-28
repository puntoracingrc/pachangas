import {
  parseTournamentKnockoutAction,
  requireTournamentOrigin,
  tournamentClientMetadata,
  tournamentError,
  tournamentJson,
  tournamentKnockoutCommandPayload,
  tournamentRecord,
  tournamentSession,
  tournamentUuidPattern,
  tournamentWriteGate,
} from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireTournamentOrigin(request);
    const gated = tournamentWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 16_000) {
      return tournamentJson({ error: "TOURNAMENT_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await tournamentSession(request);
    const body = tournamentRecord(await request.json());
    const action = parseTournamentKnockoutAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!tournamentUuidPattern.test(operationId) || !tournamentUuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_TOURNAMENT_KNOCKOUT_COMMAND");
    }
    const result = await client.rpc("command_pachanga_tournament_knockout_v1", {
      aggregate_id: aggregateId,
      client_metadata: tournamentClientMetadata(request, "tournament_knockout"),
      command_action: action,
      command_payload: tournamentKnockoutCommandPayload(action, tournamentRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return tournamentJson({ canonical: result.data });
  } catch (error) {
    return tournamentError(error);
  }
}
