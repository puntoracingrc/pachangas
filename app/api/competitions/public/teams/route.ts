import { publicCompetitionError, publicCompetitionJson, publicCompetitionSession } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const { client, user } = await publicCompetitionSession(request);
    const result = await client.from("pachanga_groups")
      .select("id,name,team_code,payload_revision")
      .eq("owner_id", user.id)
      .order("name", { ascending: true })
      .limit(100);
    if (result.error) throw new Error(result.error.message);
    return publicCompetitionJson({ items: result.data ?? [] });
  } catch (error) { return publicCompetitionError(error); }
}
