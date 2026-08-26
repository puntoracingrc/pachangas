import {
  configurationBody,
  configurationClientMetadata,
  configurationCommandPayload,
  configurationError,
  configurationJson,
  configurationSession,
  configurationUuidPattern,
  configurationWriteGate,
  parseConfigurationAction,
  requireConfigurationOrigin,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function POST(request: Request) {
  try {
    requireConfigurationOrigin(request);
    const gated = configurationWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 60_000) return configurationJson({ error: "COMPETITION_CONFIGURATION_PAYLOAD_TOO_LARGE" }, 413);
    const { client } = await configurationSession(request);
    const body = configurationBody(await request.json());
    const action = parseConfigurationAction(body.action);
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!configurationUuidPattern.test(operationId) || !configurationUuidPattern.test(aggregateId)
      || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_COMPETITION_CONFIGURATION_COMMAND");
    }
    const result = await client.rpc("command_pachanga_competition_configuration_v1", {
      aggregate_id: aggregateId,
      client_metadata: configurationClientMetadata(request),
      command_action: action,
      command_payload: configurationCommandPayload(action, configurationBody(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return configurationJson({ canonical: result.data });
  } catch (error) {
    return configurationError(error);
  }
}
