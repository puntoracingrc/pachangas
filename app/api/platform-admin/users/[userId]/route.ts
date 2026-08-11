import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../../admin/_lib/platform-auth";
import { getPlatformUserDetail } from "../../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ userId: string }> }) {
  try {
    const session = await requirePlatformRequest(request, "users.read");
    const { userId } = await context.params;
    return platformJson(await getPlatformUserDetail(session, userId));
  } catch (error) { return platformErrorResponse(error); }
}
