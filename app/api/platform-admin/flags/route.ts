import { platformErrorResponse, platformJson, requirePlatformRequest, requireSameOriginMutation } from "../../../admin/_lib/platform-auth";
import { getPlatformFlags } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export async function GET(request: Request) {
  try { return platformJson(await getPlatformFlags(await requirePlatformRequest(request, "flags.read"))); }
  catch (error) { return platformErrorResponse(error); }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "flags.write");
    const body = record(await request.json());
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const flagKey = typeof body.flagKey === "string" ? body.flagKey : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!uuidPattern.test(operationId) || !Number.isInteger(expectedRevision) || expectedRevision < 1 || typeof body.enabled !== "boolean" || reason.length < 3 || reason.length > 1200) throw new Error("Invalid flag change");
    const result = await session.client.rpc("set_pachanga_platform_flag_v1", { expected_revision: expectedRevision, flag_key: flagKey, next_enabled: body.enabled, operation_id: operationId, reason });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) { return platformErrorResponse(error); }
}
