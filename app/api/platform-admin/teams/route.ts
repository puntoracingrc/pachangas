import { platformErrorResponse, platformJson, requirePlatformRequest } from "../../../admin/_lib/platform-auth";
import { listPlatformTeams, paginationFromSearchParams } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "teams.read");
    const params = new URL(request.url).searchParams;
    const pagination = paginationFromSearchParams(params);
    return platformJson(await listPlatformTeams(session, {
      ...pagination,
      activity: params.get("activity") ?? "all",
      billing: params.get("billing") ?? "all",
      createdFrom: params.get("createdFrom") ?? "",
      createdTo: params.get("createdTo") ?? "",
      locality: params.get("locality") ?? "",
      market: params.get("market") ?? "all",
      maximumLevel: params.get("maximumLevel") ?? "",
      minimumLevel: params.get("minimumLevel") ?? "",
      owner: params.get("owner") ?? "",
      query: params.get("q") ?? "",
      social: params.get("social") ?? "all",
      sort: params.get("sort") ?? "updated_desc",
    }));
  } catch (error) { return platformErrorResponse(error); }
}
