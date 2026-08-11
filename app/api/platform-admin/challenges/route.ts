import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";
import { listPlatformChallenges, paginationFromSearchParams } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "challenges.read");
    const params = new URL(request.url).searchParams;
    const pagination = paginationFromSearchParams(params);
    return platformJson(await listPlatformChallenges(session, {
      ...pagination,
      dateFrom: params.get("dateFrom") ?? "",
      dateTo: params.get("dateTo") ?? "",
      groupId: params.get("groupId") ?? "",
      query: params.get("q") ?? "",
      sort: params.get("sort") ?? "updated_desc",
      status: params.get("status") ?? "all",
    }));
  } catch (error) { return platformErrorResponse(error); }
}
