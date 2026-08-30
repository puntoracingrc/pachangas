import { platformErrorResponse, platformJson, requirePlatformRequest, requireSameOriginMutation } from "../../../../admin/_lib/platform-auth";
import { getPlatformTeamDetail } from "../../../../admin/_lib/platform-data";
import { isTeamOperationalPlatformAction, teamOperationalRecord } from "../../../../team-operational-contract";
import {
  teamOperationalClientMetadata,
  teamOperationalCommandPayload,
  teamOperationalUuidPattern,
  teamOperationalWriteGate,
} from "../../../team-operational/_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request, context: { params: Promise<{ teamId: string }> }) {
  try {
    const session = await requirePlatformRequest(request, "teams.read");
    const { teamId } = await context.params;
    return platformJson(await getPlatformTeamDetail(session, teamId));
  } catch (error) { return platformErrorResponse(error); }
}

export async function POST(request: Request, context: { params: Promise<{ teamId: string }> }) {
  try {
    requireSameOriginMutation(request);
    const gated = teamOperationalWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 24_000) throw new Error("Invalid operation payload");
    const session = await requirePlatformRequest(request, "teams.operational.read");
    const { teamId } = await context.params;
    const body = teamOperationalRecord(await request.json());
    const action = body.action;
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!teamOperationalUuidPattern.test(teamId)
      || !teamOperationalUuidPattern.test(operationId)
      || !isTeamOperationalPlatformAction(action)
      || !Number.isSafeInteger(expectedRevision)
      || expectedRevision < 1) {
      throw new Error("Invalid Team operational command");
    }
    const result = await session.client.rpc("command_pachanga_team_operational_state_v1", {
      action,
      client_metadata: teamOperationalClientMetadata(request, "platform_control_center_team_operational"),
      expected_revision: expectedRevision,
      operation_id: operationId,
      payload: teamOperationalCommandPayload(action, teamOperationalRecord(body.payload), true),
      target_group_id: teamId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
