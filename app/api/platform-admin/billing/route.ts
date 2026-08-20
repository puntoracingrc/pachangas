import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";
import { getPlatformSection } from "../../../admin/_lib/platform-data";
import { getStripeHealth } from "../../../admin/_lib/platform-external";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "billing.read");
    const force = new URL(request.url).searchParams.get("refresh") === "1";
    const [local, stripe] = await Promise.all([getPlatformSection(session, "billing", 1, 50), getStripeHealth(force)]);
    return platformJson({ local, stripe });
  } catch (error) { return platformErrorResponse(error); }
}
