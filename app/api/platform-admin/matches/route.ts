import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";
import { listPlatformMatches, paginationFromSearchParams } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "matches.read");
    const params = new URL(request.url).searchParams;
    const pagination = paginationFromSearchParams(params);
    return platformJson(await listPlatformMatches(session, {
      ...pagination,
      dateFrom: params.get("dateFrom") ?? "",
      dateTo: params.get("dateTo") ?? "",
      groupId: params.get("groupId") ?? "",
      query: params.get("q") ?? "",
      scope: params.get("scope") ?? "all",
      sort: params.get("sort") ?? "date_asc",
      state: params.get("state") ?? "all",
      type: params.get("type") ?? "all",
    }));
  } catch (error) { return platformErrorResponse(error); }
}
