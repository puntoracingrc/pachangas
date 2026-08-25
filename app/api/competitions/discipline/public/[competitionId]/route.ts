import { disciplineError, disciplineJson, disciplinePublicClient, disciplineUuidPattern } from "../../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(_request: Request, context: { params: Promise<{ competitionId: string }> }) {
  try {
    const { competitionId } = await context.params;
    if (!disciplineUuidPattern.test(competitionId)) throw new Error("COMPETITION_NOT_FOUND");
    const result = await disciplinePublicClient().rpc("get_pachanga_public_competition_discipline_v1", {
      target_competition_id: competitionId,
    });
    if (result.error) throw new Error(result.error.message);
    return disciplineJson(result.data);
  } catch (error) {
    return disciplineError(error);
  }
}
