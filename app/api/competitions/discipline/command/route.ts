import {
  disciplineClientMetadata,
  disciplineCommandPayload,
  disciplineError,
  disciplineJson,
  disciplineRecord,
  disciplineSession,
  disciplineUuidPattern,
  disciplineWriteGate,
  parseDisciplineAction,
  requireDisciplineOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireDisciplineOrigin(request);
    const gated = disciplineWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 50_000) {
      return disciplineJson({ error: "COMPETITION_DISCIPLINE_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await disciplineSession(request);
    const body = disciplineRecord(await request.json());
    const action = parseDisciplineAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const competitionId = typeof body.competitionId === "string" ? body.competitionId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (![operationId, competitionId, aggregateId].every((value) => disciplineUuidPattern.test(value))
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
    }
    const result = await client.rpc("command_pachanga_competition_discipline_v1", {
      aggregate_id: aggregateId,
      client_metadata: disciplineClientMetadata(request, "competition_discipline"),
      command_action: action,
      command_payload: disciplineCommandPayload(action, disciplineRecord(body.payload)),
      competition_id: competitionId,
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return disciplineJson({ canonical: result.data });
  } catch (error) {
    return disciplineError(error);
  }
}
