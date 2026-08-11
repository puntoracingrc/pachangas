import { platformErrorResponse, platformJson, requirePlatformRequest, requireSameOriginMutation } from "../../../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export async function POST(request: Request, context: { params: Promise<{ announcementId: string }> }) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "notifications.send");
    const { announcementId } = await context.params;
    const body = record(await request.json());
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!uuidPattern.test(announcementId) || !uuidPattern.test(operationId) || !Number.isInteger(expectedRevision) || expectedRevision < 1 || reason.length < 3 || reason.length > 1200) throw new Error("Invalid announcement confirmation");
    const result = await session.client.rpc("send_pachanga_platform_announcement_v1", { expected_revision: expectedRevision, operation_id: operationId, reason, target_announcement_id: announcementId });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) { return platformErrorResponse(error); }
}
