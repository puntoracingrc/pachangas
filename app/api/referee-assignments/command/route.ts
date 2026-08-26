import {
  refereeAssignmentEnvelope,
  refereeAssignmentMetadata,
  refereeAssignmentPayload,
  refereeError,
  refereeJson,
  refereeRecord,
  refereeSession,
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
    const { client } = await refereeSession(request);
    const envelope = refereeAssignmentEnvelope(await request.json());
    const payload = refereeAssignmentPayload(envelope.action, refereeRecord(envelope.body.payload));
    const result = await client.rpc("command_pachanga_referee_assignment_beta_v1", {
      aggregate_id: envelope.aggregateId,
      client_metadata: refereeAssignmentMetadata(request, "referee_assignment_beta"),
      command_action: envelope.action,
      command_payload: payload,
      expected_revision: envelope.expectedRevision,
      operation_id: envelope.operationId,
    });
    if (result.error) return refereeError(result.error);
    return refereeJson({ canonical: result.data });
  } catch (error) {
    return refereeError(error);
  }
}
