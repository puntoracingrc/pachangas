import {
  organizerBillingError,
  organizerBillingJson,
  organizerBillingMode,
  organizerBillingRecord,
  organizerBillingSession,
  organizerBillingUuidPattern,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const params = new URL(request.url).searchParams;
    const organizerKind = (params.get("organizerKind") ?? "").trim().toUpperCase();
    const organizerId = (params.get("organizerId") ?? "").trim();
    if (!["CLUB", "TEAM"].includes(organizerKind) || !organizerBillingUuidPattern.test(organizerId)) {
      throw new Error("BILLING_INVALID_ORGANIZER");
    }
    const { client } = await organizerBillingSession(request);
    const [snapshot, usage] = await Promise.all([
      client.rpc("get_my_pachanga_organizer_billing_v1", {
        target_organizer_id: organizerId,
        target_organizer_kind: organizerKind,
      }),
      client.rpc("get_my_pachanga_organizer_usage_v1", {
        target_organizer_id: organizerId,
        target_organizer_kind: organizerKind,
      }),
    ]);
    if (snapshot.error) throw new Error(snapshot.error.message);
    if (usage.error) throw new Error(usage.error.message);
    const canonical = organizerBillingRecord(snapshot.data);
    const mode = organizerBillingMode();
    const accounts = Array.isArray(canonical.accounts) ? canonical.accounts.map(organizerBillingRecord) : [];
    const writeAccount = accounts.find((account) => account.mode === mode);
    return organizerBillingJson({
      canonical,
      usage: usage.data,
      write: {
        mode,
        revision: typeof writeAccount?.revision === "number" ? writeAccount.revision : 0,
      },
    });
  } catch (error) {
    return organizerBillingError(error);
  }
}
