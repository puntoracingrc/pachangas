import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "search.read");
    const query = new URL(request.url).searchParams.get("q")?.trim() ?? "";
    if (query.length < 2) return platformJson({ items: [] });
    const result = await session.client.rpc("search_pachanga_platform_v1", {
      result_limit: 20,
      search_text: query.slice(0, 120),
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ items: Array.isArray(result.data) ? result.data : [] });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
