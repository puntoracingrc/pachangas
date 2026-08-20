import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ announcementId: string }> }) {
  try {
    const session = await requirePlatformRequest(request, "notifications.send");
    const { announcementId } = await context.params;
    const result = await session.client.rpc("preview_pachanga_platform_announcement_v1", { target_announcement_id: announcementId });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ preview: result.data });
  } catch (error) { return platformErrorResponse(error); }
}
