import { organizerAccessRecord } from "../../../organizer-access-contract";
import {
  organizerAccessClientMetadata,
  organizerAccessCommandPayload,
  organizerAccessError,
  organizerAccessJson,
  organizerAccessSession,
  organizerAccessUuidPattern,
  organizerAccessWriteGate,
  parseOrganizerAccessAction,
  requireOrganizerAccessOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireOrganizerAccessOrigin(request);
    const gated = organizerAccessWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 40_000) {
      return organizerAccessJson({ error: "ORGANIZER_ACCESS_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await organizerAccessSession(request);
    const body = organizerAccessRecord(await request.json());
    const action = parseOrganizerAccessAction(body.action);
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!organizerAccessUuidPattern.test(aggregateId)
      || !organizerAccessUuidPattern.test(operationId)
      || !Number.isSafeInteger(expectedRevision)
      || expectedRevision < 0) {
      throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
    }
    const result = await client.rpc("command_pachanga_organizer_access_application_v1", {
      aggregate_id: aggregateId,
      client_metadata: organizerAccessClientMetadata(request, "organizer_access"),
      command_action: action,
      command_payload: organizerAccessCommandPayload(action, organizerAccessRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return organizerAccessJson({ canonical: result.data });
  } catch (error) {
    return organizerAccessError(error);
  }
}
