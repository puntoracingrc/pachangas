import { anonymousRefereeClient, refereeError, refereeJson } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  try {
    const { slug } = await params;
    const normalized = slug.trim().toLowerCase();
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(normalized) || normalized.length > 80) {
      return refereeJson({ profile: null }, 404);
    }
    const result = await anonymousRefereeClient().rpc("get_pachanga_public_referee_v1", { target_slug: normalized });
    if (result.error) throw new Error(result.error.message);
    return result.data ? refereeJson({ profile: result.data }) : refereeJson({ profile: null }, 404);
  } catch (error) {
    return refereeError(error);
  }
}
