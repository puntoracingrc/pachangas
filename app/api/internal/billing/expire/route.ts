import { platformServiceClient } from "../../../../admin/_lib/platform-auth";
import { noStoreHeaders } from "../../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const maxDuration = 60;
export const runtime = "nodejs";

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret) return Response.json({ error: "BILLING_EXPIRATION_NOT_CONFIGURED" }, { headers: noStoreHeaders, status: 503 });
  if (request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "BILLING_EXPIRATION_FORBIDDEN" }, { headers: noStoreHeaders, status: 403 });
  }
  const result = await platformServiceClient().rpc("process_pachanga_billing_expirations_service_v1", {
    batch_size: 100,
    operation_id: crypto.randomUUID(),
  });
  if (result.error) return Response.json({ error: "BILLING_EXPIRATION_FAILED" }, { headers: noStoreHeaders, status: 500 });
  const reminders = await platformServiceClient().rpc("process_pachanga_organizer_access_expiry_notifications_v1", {
    batch_size: 100,
    operation_id: crypto.randomUUID(),
  });
  if (reminders.error) return Response.json({ error: "ORGANIZER_ACCESS_REMINDERS_FAILED" }, { headers: noStoreHeaders, status: 500 });
  return Response.json({ canonical: result.data, organizerAccessReminders: reminders.data }, { headers: noStoreHeaders });
}
