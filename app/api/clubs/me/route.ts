import { noStoreHeaders } from "../../client-policy/_contract";
import { platformUserClient } from "../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) return Response.json({ error: "AUTHENTICATION_REQUIRED" }, { headers: noStoreHeaders, status: 401 });
  const client = platformUserClient(token);
  const user = await client.auth.getUser(token);
  if (user.error || !user.data.user) {
    return Response.json({ error: "AUTHENTICATION_REQUIRED" }, { headers: noStoreHeaders, status: 401 });
  }
  const result = await client.rpc("get_my_pachanga_clubs_beta_v1");
  if (result.error) {
    return Response.json({ error: "CLUB_READ_REJECTED", message: result.error.message }, { headers: noStoreHeaders, status: 400 });
  }
  return Response.json(result.data, { headers: noStoreHeaders });
}
