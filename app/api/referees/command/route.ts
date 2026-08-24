import {
  refereeClientMetadata,
  refereeCommandPayload,
  refereeError,
  refereeJson,
  refereeRecord,
  refereeSession,
  refereeUuidPattern,
  refereeWriteGate,
  requireRefereeOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireRefereeOrigin(request);
    const gated = refereeWriteGate(request);
    if (gated) return gated;
    const contentLength = Number(request.headers.get("content-length") ?? 0);
    if (contentLength > 40_000) return refereeJson({ error: "REFEREE_PAYLOAD_TOO_LARGE" }, 413);
    const { client } = await refereeSession(request);
    const body = refereeRecord(await request.json());
    const action = typeof body.action === "string" ? body.action.trim() : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!refereeUuidPattern.test(operationId) || !refereeUuidPattern.test(aggregateId)
        || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_REFEREE_COMMAND");
    }
    const payload = refereeCommandPayload(action, refereeRecord(body.payload));
    const result = action === "publication.consent"
      ? await client.rpc("command_pachanga_publication_consent_v1", {
          client_metadata: refereeClientMetadata(request, "referee_profile"),
          confirmations: payload,
          expected_revision: expectedRevision,
          operation_id: operationId,
          subject_id: aggregateId,
          subject_kind: "REFEREE_PROFILE",
        })
      : await client.rpc("command_pachanga_referee_platform_v1", {
          aggregate_id: aggregateId,
          client_metadata: refereeClientMetadata(request, "referee_profile"),
          command_action: action,
          command_payload: payload,
          expected_revision: expectedRevision,
          operation_id: operationId,
        });
    if (result.error) throw new Error(result.error.message);
    return refereeJson({ canonical: result.data });
  } catch (error) {
    return refereeError(error);
  }
}
