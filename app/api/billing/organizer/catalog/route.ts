import { publicSupabaseClient } from "../../_shared";
import { organizerBillingError, organizerBillingJson } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET() {
  try {
    const result = await publicSupabaseClient().rpc("get_pachanga_organizer_plan_catalog_v1");
    if (result.error) throw new Error(result.error.message);
    return organizerBillingJson({ canonical: result.data });
  } catch (error) {
    return organizerBillingError(error);
  }
}
