import { createClient } from "@supabase/supabase-js";
import { leagueError, leagueJson, leagueUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(_request: Request, { params }: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await params;
    if (!leagueUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
    const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
    if (!url || !key) throw new Error("LEAGUE_INTEGRATION_NOT_CONFIGURED");
    const client = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
    const result = await client.rpc("get_pachanga_league_public_registration_v1", {
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueJson(result.data);
  } catch (error) {
    return leagueError(error);
  }
}
