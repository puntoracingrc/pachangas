import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../../../admin/_lib/platform-auth";
import { isPlatformRole } from "../../../../../admin/_lib/platform-contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export async function POST(request: Request, context: { params: Promise<{ userId: string }> }) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "roles.manage");
    const { userId } = await context.params;
    const body = record(await request.json());
    const role = body.role;
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!uuidPattern.test(userId) || !uuidPattern.test(operationId) || !isPlatformRole(role)) throw new Error("Invalid role request");
    if (!Number.isInteger(expectedRevision) || expectedRevision < 0 || typeof body.active !== "boolean") throw new Error("Invalid role revision");
    if (reason.length < 3 || reason.length > 1200) throw new Error("A reason is required");
    const result = await session.client.rpc("set_pachanga_platform_role_v1", {
      expected_revision: expectedRevision,
      next_active: body.active,
      next_role: role,
      operation_id: operationId,
      reason,
      target_user_id: userId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
