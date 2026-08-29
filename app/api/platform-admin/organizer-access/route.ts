import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { organizerAccessRecord } from "../../../organizer-access-contract";
import { clientWriteGateResponse } from "../../client-policy/_contract";
import {
  organizerAccessClientMetadata,
  organizerAccessCommandPayload,
  organizerAccessUuidPattern,
  parseOrganizerAccessPlatformAction,
} from "../../organizer-access/_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

function boundedLimit(value: string | null) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), 200) : 50;
}

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "organizer_access.read");
    const url = new URL(request.url);
    const result = await session.client.rpc("get_pachanga_platform_organizer_access_v1", {
      target_limit: boundedLimit(url.searchParams.get("limit")),
      target_search: url.searchParams.get("search")?.trim() || null,
      target_status: url.searchParams.get("status")?.trim() || null,
    });
    if (result.error) throw new Error(result.error.message);
    const health = await session.client.rpc("get_pachanga_organizer_access_health_v1");
    if (health.error) throw new Error(health.error.message);
    return platformJson({ canonical: result.data, health: health.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const gated = clientWriteGateResponse(request);
    if (gated) return gated;
    const session = await requirePlatformRequest(request, "organizer_access.read");
    const body = organizerAccessRecord(await request.json());
    const action = parseOrganizerAccessPlatformAction(body.action);
    const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!organizerAccessUuidPattern.test(aggregateId)
      || !organizerAccessUuidPattern.test(operationId)
      || !Number.isSafeInteger(expectedRevision)
      || expectedRevision < 0) {
      throw new Error("Invalid organizer access command envelope");
    }
    const result = await session.client.rpc("command_pachanga_organizer_access_application_v1", {
      aggregate_id: aggregateId,
      client_metadata: organizerAccessClientMetadata(request, "platform_organizer_access"),
      command_action: action,
      command_payload: organizerAccessCommandPayload(action, organizerAccessRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
