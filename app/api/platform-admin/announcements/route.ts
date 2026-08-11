import { platformErrorResponse, platformJson, requirePlatformRequest, requireSameOriginMutation } from "../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "notifications.send");
    const body = record(await request.json());
    const audienceId = typeof body.audienceId === "string" ? body.audienceId : "";
    const audienceType = typeof body.audienceType === "string" ? body.audienceType : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const title = typeof body.title === "string" ? body.title.trim() : "";
    const announcementBody = typeof body.body === "string" ? body.body.trim() : "";
    const actionUrl = typeof body.actionUrl === "string" && body.actionUrl.trim() ? body.actionUrl.trim() : null;
    if (!uuidPattern.test(audienceId) || !uuidPattern.test(operationId) || !new Set(["user", "team", "team_admins"]).has(audienceType)) throw new Error("Invalid announcement audience");
    if (title.length < 3 || title.length > 120 || announcementBody.length < 3 || announcementBody.length > 1000 || reason.length < 3 || reason.length > 1200) throw new Error("Invalid announcement content");
    if (actionUrl && (!actionUrl.startsWith("/") || actionUrl.startsWith("//") || actionUrl.length > 500)) throw new Error("Action URL must be internal");
    const result = await session.client.rpc("create_pachanga_platform_announcement_v1", { announcement_action_url: actionUrl, announcement_body: announcementBody, announcement_title: title, audience_id: audienceId, audience_type: audienceType, operation_id: operationId, reason });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) { return platformErrorResponse(error); }
}
