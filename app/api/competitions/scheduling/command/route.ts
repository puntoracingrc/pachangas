import {
  parseScheduleAction,
  requireScheduleOrigin,
  scheduleClientMetadata,
  scheduleCommandPayload,
  scheduleError,
  scheduleJson,
  scheduleRecord,
  scheduleSession,
  scheduleUuidPattern,
  scheduleWriteGate,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireScheduleOrigin(request);
    const gated = scheduleWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 40_000) {
      return scheduleJson({ error: "LEAGUE_SCHEDULING_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await scheduleSession(request);
    const body = scheduleRecord(await request.json());
    const action = parseScheduleAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!scheduleUuidPattern.test(operationId) || !scheduleUuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
    }
    const result = await client.rpc("command_pachanga_league_scheduling_v1", {
      aggregate_id: aggregateId,
      client_metadata: scheduleClientMetadata(request, "league_scheduling"),
      command_action: action,
      command_payload: scheduleCommandPayload(action, scheduleRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return scheduleJson({ canonical: result.data });
  } catch (error) {
    return scheduleError(error);
  }
}
