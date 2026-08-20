import { platformServiceClient } from "../../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const maxDuration = 60;
export const runtime = "nodejs";

const headers = { "Cache-Control": "no-store, max-age=0" };

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret) return Response.json({ error: "RANKING_REFRESH_NOT_CONFIGURED" }, { headers, status: 503 });
  if (request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "RANKING_REFRESH_FORBIDDEN" }, { headers, status: 403 });
  }

  const result = await platformServiceClient().rpc("process_pachanga_ranking_refresh_queue_v1", {
    maximum_operations: 25,
  });
  if (result.error) {
    return Response.json({ error: "RANKING_REFRESH_FAILED" }, { headers, status: 500 });
  }
  return Response.json({ data: result.data }, { headers });
}
