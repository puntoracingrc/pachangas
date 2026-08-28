import { publicCompetitionError, publicCompetitionJson, publicCompetitionSession, publicCompetitionUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!publicCompetitionUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const { client } = await publicCompetitionSession(request);
    const [result, editionResult] = await Promise.all([
      client.rpc("get_my_pachanga_competition_publication_v1", { target_competition_id: competitionId }),
      client.from("pachanga_competition_editions")
        .select("id,name,status,revision")
        .eq("competition_id", competitionId)
        .neq("status", "cancelled")
        .order("server_sequence", { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);
    if (result.error) throw new Error(result.error.message);
    if (editionResult.error) throw new Error(editionResult.error.message);
    const edition = editionResult.data;
    const categoryResult = edition
      ? await client.from("pachanga_competition_categories")
        .select("id,name,sport_format,level_label,revision")
        .eq("edition_id", edition.id)
        .order("server_sequence", { ascending: true })
      : { data: [], error: null };
    if (categoryResult.error) throw new Error(categoryResult.error.message);
    const authority = result.data && typeof result.data === "object" && !Array.isArray(result.data)
      ? result.data as Record<string, unknown>
      : { snapshot: null, reviews: [] };
    return publicCompetitionJson({ ...authority, scope: { categories: categoryResult.data ?? [], edition } });
  } catch (error) { return publicCompetitionError(error); }
}
