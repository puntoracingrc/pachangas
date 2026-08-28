import { organizerBillingError, organizerBillingJson, organizerBillingSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await organizerBillingSession(request);
    const result = await client.rpc("get_my_pachanga_billing_organizers_v1");
    if (result.error) throw new Error(result.error.message);
    return organizerBillingJson({ canonical: result.data });
  } catch (error) {
    return organizerBillingError(error);
  }
}
