import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";
import { listPlatformUsers, paginationFromSearchParams } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "users.read");
    const params = new URL(request.url).searchParams;
    const pagination = paginationFromSearchParams(params);
    return platformJson(await listPlatformUsers(session, {
      ...pagination,
      createdFrom: params.get("createdFrom") ?? "",
      createdTo: params.get("createdTo") ?? "",
      query: params.get("q") ?? "",
      sort: params.get("sort") ?? "created_desc",
      status: params.get("status") ?? "all",
    }));
  } catch (error) { return platformErrorResponse(error); }
}
