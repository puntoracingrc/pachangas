import { leagueBetaError, leagueBetaJson, leagueBetaSession, leagueBetaUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ wizardId: string }> }) {
  try {
    const { wizardId } = await context.params;
    if (!leagueBetaUuidPattern.test(wizardId)) throw new Error("LEAGUE_BETA_WIZARD_NOT_FOUND");
    const { client } = await leagueBetaSession(request);
    const result = await client.rpc("get_pachanga_league_private_beta_wizard_v1", {
      target_wizard_id: wizardId,
    });
    if (result.error) throw new Error(result.error.message);
    return leagueBetaJson(result.data);
  } catch (error) {
    return leagueBetaError(error);
  }
}
