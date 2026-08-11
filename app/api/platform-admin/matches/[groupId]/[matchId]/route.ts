import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../../../admin/_lib/platform-auth";
import { getPlatformMatchDetail } from "../../../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ groupId: string; matchId: string }> }) {
  try {
    const session = await requirePlatformRequest(request, "matches.read");
    const { groupId, matchId } = await context.params;
    if (!/^[0-9a-f-]{36}$/i.test(groupId) || !matchId || matchId.length > 160) throw new Error("Invalid match request");
    return platformJson(await getPlatformMatchDetail(session, groupId, decodeURIComponent(matchId)));
  } catch (error) { return platformErrorResponse(error); }
}
