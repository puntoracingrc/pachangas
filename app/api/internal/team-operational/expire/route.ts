import { platformServiceClient } from "../../../../admin/_lib/platform-auth";
import { noStoreHeaders } from "../../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const maxDuration = 60;
export const runtime = "nodejs";

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret) return Response.json({ error: "TEAM_OPERATIONAL_EXPIRY_NOT_CONFIGURED" }, { headers: noStoreHeaders, status: 503 });
  if (request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "TEAM_OPERATIONAL_EXPIRY_FORBIDDEN" }, { headers: noStoreHeaders, status: 403 });
  }
  const result = await platformServiceClient().rpc("expire_pachanga_team_operational_states_v1", {
    batch_size: 100,
    operation_namespace: crypto.randomUUID(),
  });
  if (result.error) return Response.json({ error: "TEAM_OPERATIONAL_EXPIRY_FAILED" }, { headers: noStoreHeaders, status: 500 });
  return Response.json({ canonical: result.data }, { headers: noStoreHeaders });
}
