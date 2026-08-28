import { getPublicCompetitionBySlug } from "../../../../public-product-data";
import { publicCompetitionCacheJson, publicCompetitionSlugPattern } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!publicCompetitionSlugPattern.test(slug)) return publicCompetitionCacheJson({ error: "PUBLIC_COMPETITION_NOT_FOUND" }, 404, 10);
  const result = await getPublicCompetitionBySlug(slug);
  return result
    ? publicCompetitionCacheJson(result, 200, 60)
    : publicCompetitionCacheJson({ error: "PUBLIC_COMPETITION_NOT_FOUND" }, 404, 10);
}
