import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../../admin/_lib/platform-auth";
import { getPlatformChallengeDetail } from "../../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ challengeId: string }> }) {
  try {
    const session = await requirePlatformRequest(request, "challenges.read");
    const { challengeId } = await context.params;
    if (!/^[0-9a-f-]{36}$/i.test(challengeId)) throw new Error("Invalid challenge request");
    return platformJson(await getPlatformChallengeDetail(session, challengeId));
  } catch (error) { return platformErrorResponse(error); }
}
