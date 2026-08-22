import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "search.read");
    const query = new URL(request.url).searchParams.get("q")?.trim() ?? "";
    if (query.length < 2) return platformJson({ items: [] });
    const [result, refereeResult] = await Promise.all([
      session.client.rpc("search_pachanga_platform_v1", { result_limit: 20, search_text: query.slice(0, 120) }),
      session.access.capabilities.includes("referees.read")
        ? session.client.rpc("search_pachanga_platform_referees_v1", { target_limit: 8, target_query: query.slice(0, 120) })
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (result.error) throw new Error(result.error.message);
    if (refereeResult.error) throw new Error(refereeResult.error.message);
    const refereeItems = (Array.isArray(refereeResult.data) ? refereeResult.data : []).map((value) => {
      const item = value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
      return { ...item, secondary: item.subtitle, type: "referee" };
    });
    return platformJson({ items: [...(Array.isArray(result.data) ? result.data : []), ...refereeItems].slice(0, 20) });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
