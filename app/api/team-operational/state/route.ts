import { isTeamOperationalOwnerAction, teamOperationalRecord } from "../../../team-operational-contract";
import {
  requireTeamOperationalOrigin,
  teamOperationalClientMetadata,
  teamOperationalCommandPayload,
  teamOperationalError,
  teamOperationalJson,
  teamOperationalSession,
  teamOperationalUuidPattern,
  teamOperationalWriteGate,
} from "../_shared";

export const dynamic = "force-dynamic";
export const revalidate = 0;

export async function GET(request: Request) {
  try {
    const groupId = new URL(request.url).searchParams.get("groupId") ?? "";
    if (!teamOperationalUuidPattern.test(groupId)) throw new Error("TEAM_OPERATIONAL_COMMAND_INVALID");
    const { client } = await teamOperationalSession(request);
    const result = await client.rpc("get_pachanga_team_operational_state_v1", { target_group_id: groupId });
    if (result.error) throw new Error(result.error.message);
    return teamOperationalJson({ canonical: result.data });
  } catch (error) {
    return teamOperationalError(error);
  }
}

export async function POST(request: Request) {
  try {
    requireTeamOperationalOrigin(request);
    const gated = teamOperationalWriteGate(request);
    if (gated) return gated;
    if (Number(request.headers.get("content-length") ?? 0) > 24_000) {
      return teamOperationalJson({ error: "TEAM_OPERATIONAL_PAYLOAD_TOO_LARGE" }, 413);
    }
    const { client } = await teamOperationalSession(request);
    const body = teamOperationalRecord(await request.json());
    const action = body.action;
    const groupId = typeof body.groupId === "string" ? body.groupId : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!isTeamOperationalOwnerAction(action)
      || !teamOperationalUuidPattern.test(groupId)
      || !teamOperationalUuidPattern.test(operationId)
      || !Number.isSafeInteger(expectedRevision)
      || expectedRevision < 1) {
      throw new Error("TEAM_OPERATIONAL_COMMAND_INVALID");
    }
    const result = await client.rpc("command_pachanga_team_operational_state_v1", {
      action,
      client_metadata: teamOperationalClientMetadata(request, "team_operational_owner"),
      expected_revision: expectedRevision,
      operation_id: operationId,
      payload: teamOperationalCommandPayload(action, teamOperationalRecord(body.payload)),
      target_group_id: groupId,
    });
    if (result.error) throw new Error(result.error.message);
    return teamOperationalJson({ canonical: result.data });
  } catch (error) {
    return teamOperationalError(error);
  }
}
