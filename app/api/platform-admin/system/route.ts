import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";
import { getPlatformDatabaseHealth, getPlatformSection } from "../../../admin/_lib/platform-data";
import { getPlatformExternalHealth } from "../../../admin/_lib/platform-external";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "system.read");
    const force = new URL(request.url).searchParams.get("refresh") === "1";
    const [database, external, errors] = await Promise.all([getPlatformDatabaseHealth(session), getPlatformExternalHealth(force), getPlatformSection(session, "errors", 1, 50)]);
    return platformJson({ database, errors, external });
  } catch (error) { return platformErrorResponse(error); }
}
