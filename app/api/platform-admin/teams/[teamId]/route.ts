import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../../admin/_lib/platform-auth";
import { getPlatformTeamDetail } from "../../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ teamId: string }> }) {
  try {
    const session = await requirePlatformRequest(request, "teams.read");
    const { teamId } = await context.params;
    return platformJson(await getPlatformTeamDetail(session, teamId));
  } catch (error) { return platformErrorResponse(error); }
}
