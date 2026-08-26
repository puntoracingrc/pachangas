import { configurationError, configurationJson, configurationSession, configurationUuidPattern } from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await context.params;
    if (!configurationUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const { client } = await configurationSession(request);
    const result = await client.rpc("get_pachanga_competition_configuration_v1", { target_competition_id: competitionId });
    if (result.error) throw new Error(result.error.message);
    return configurationJson(result.data);
  } catch (error) {
    return configurationError(error);
  }
}
