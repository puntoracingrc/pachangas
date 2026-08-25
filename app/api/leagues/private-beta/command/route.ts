import { leagueBetaRecord } from "../../../../league-private-beta-contract";
import {
  leagueBetaClientMetadata,
  leagueBetaCommandPayload,
  leagueBetaError,
  leagueBetaJson,
  leagueBetaSession,
  leagueBetaUuidPattern,
  leagueBetaWriteGate,
  parseLeagueBetaAction,
  requireLeagueBetaOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireLeagueBetaOrigin(request);
    const gated = leagueBetaWriteGate(request);
    if (gated) return gated;
    const { client } = await leagueBetaSession(request);
    const body = leagueBetaRecord(await request.json());
    const action = parseLeagueBetaAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!leagueBetaUuidPattern.test(operationId)
      || !leagueBetaUuidPattern.test(aggregateId)
      || !Number.isInteger(expectedRevision)
      || expectedRevision < 0) {
      throw new Error("INVALID_LEAGUE_BETA_ENVELOPE");
    }
    const result = await client.rpc("command_pachanga_league_private_beta_v1", {
      aggregate_id: aggregateId,
      client_metadata: leagueBetaClientMetadata(request, "league_private_beta_wizard"),
      command_action: action,
      command_payload: leagueBetaCommandPayload(action, leagueBetaRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueBetaJson({ canonical: result.data });
  } catch (error) {
    return leagueBetaError(error);
  }
}
