import { noStoreHeaders } from "../../../client-policy/_contract";
import { getPublicClubBySlug } from "../../../../public-product-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(_request: Request, context: { params: Promise<{ slug: string }> }) {
  const { slug } = await context.params;
  const club = await getPublicClubBySlug(slug);
  if (!club) return Response.json({ error: "CLUB_NOT_FOUND" }, { headers: noStoreHeaders, status: 404 });
  return Response.json({ club }, { headers: noStoreHeaders });
}
