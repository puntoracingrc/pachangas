import {
  organizerBillingError,
  organizerBillingJson,
  organizerBillingSession,
  organizerBillingUuidPattern,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const operationId = new URL(request.url).searchParams.get("operationId")?.trim() ?? "";
    if (!organizerBillingUuidPattern.test(operationId)) throw new Error("BILLING_OPERATION_ID_REQUIRED");
    const { client } = await organizerBillingSession(request);
    const result = await client.rpc("get_pachanga_organizer_checkout_status_v1", { operation_id: operationId });
    if (result.error) throw new Error(result.error.message);
    return organizerBillingJson({ canonical: result.data });
  } catch (error) {
    return organizerBillingError(error);
  }
}
