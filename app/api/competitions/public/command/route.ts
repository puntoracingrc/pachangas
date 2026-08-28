import {
  parsePublicCompetitionAction,
  publicCompetitionClientMetadata,
  publicCompetitionCommandPayload,
  publicCompetitionError,
  publicCompetitionJson,
  publicCompetitionSession,
  publicCompetitionUuidPattern,
  publicCompetitionWriteGate,
  requirePublicCompetitionOrigin,
} from "../_shared";
import { isPublicCompetitionPublicationAction, publicCompetitionRecord } from "../../../../public-competition-contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requirePublicCompetitionOrigin(request);
    const gated = publicCompetitionWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 64_000) return publicCompetitionJson({ error: "PUBLIC_COMPETITION_PAYLOAD_TOO_LARGE" }, 413);
    const { client } = await publicCompetitionSession(request);
    const body = publicCompetitionRecord(await request.json());
    const action = parsePublicCompetitionAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!publicCompetitionUuidPattern.test(operationId) || !publicCompetitionUuidPattern.test(aggregateId)
      || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
    }
    const args = {
      aggregate_id: aggregateId,
      client_metadata: publicCompetitionClientMetadata(request),
      command_action: action,
      command_payload: publicCompetitionCommandPayload(action, publicCompetitionRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    };
    const result = isPublicCompetitionPublicationAction(action)
      ? await client.rpc("command_pachanga_competition_publication_v1", args)
      : await client.rpc("command_pachanga_competition_registration_request_v1", args);
    if (result.error) throw new Error(result.error.message);
    return publicCompetitionJson({ canonical: result.data });
  } catch (error) {
    return publicCompetitionError(error);
  }
}
