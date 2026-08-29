import {
  organizerAccessError,
  organizerAccessJson,
  organizerAccessSession,
  organizerAccessUuidPattern,
} from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

type Params = Promise<{ applicationId: string }>;

export async function GET(request: Request, { params }: { params: Params }) {
  try {
    const { applicationId } = await params;
    if (!organizerAccessUuidPattern.test(applicationId)) throw new Error("ORGANIZER_ACCESS_APPLICATION_NOT_FOUND");
    const { client } = await organizerAccessSession(request);
    const result = await client.rpc("get_pachanga_organizer_access_application_v1", {
      target_application_id: applicationId,
    });
    if (result.error) throw new Error(result.error.message);
    return organizerAccessJson({ canonical: result.data });
  } catch (error) {
    return organizerAccessError(error);
  }
}
