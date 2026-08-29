import { organizerAccessError, organizerAccessJson, organizerAccessSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client } = await organizerAccessSession(request);
    const result = await client.rpc("get_my_pachanga_organizer_access_v1");
    if (result.error) throw new Error(result.error.message);
    return organizerAccessJson({ canonical: result.data });
  } catch (error) {
    return organizerAccessError(error);
  }
}
