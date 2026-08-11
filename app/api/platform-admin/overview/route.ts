import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";
import { getPlatformOverview } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "overview.read");
    const period = new URL(request.url).searchParams.get("period") ?? "today";
    return platformJson(await getPlatformOverview(session, period));
  } catch (error) { return platformErrorResponse(error); }
}
