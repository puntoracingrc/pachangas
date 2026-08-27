import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getPlatformTournamentControl } from "../../../admin/_lib/platform-data";
import {
  isTournamentPlatformAction,
  tournamentRecord,
} from "../../../tournament-draw-contract";
import { clientWriteGateResponse } from "../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const flagsAggregateId = "00000000-0000-0000-0000-00000000c6a1";
const groupStageFlagsAggregateId = "00000000-0000-0000-0000-00000000c6b1";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function reason(input: Record<string, unknown>) {
  const value = typeof input.reason === "string" ? input.reason.trim() : "";
  if (value.length < 3 || value.length > 1100) throw new Error("TOURNAMENT_PLATFORM_REASON_REQUIRED");
  return value;
}

function optionalTimestamp(value: unknown) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) throw new Error("INVALID_TOURNAMENT_DATE");
  return new Date(value).toISOString();
}

function platformPayload(action: string, input: Record<string, unknown>) {
  const base = { reason: reason(input) };
  if (action === "tournament.kill_switch") return base;
  if (action === "tournament.flags.set") return {
    ...base,
    automaticEnabled: input.automaticEnabled === true,
    creationEnabled: input.creationEnabled === true,
    drawEnabled: input.drawEnabled === true,
    foundationEnabled: input.foundationEnabled === true,
    hybridEnabled: input.hybridEnabled === true,
    manualEnabled: input.manualEnabled === true,
    privateBetaEnabled: input.privateBetaEnabled === true,
    publishEnabled: input.publishEnabled === true,
  };
  if (action === "tournament.group_stage.flags.set") return {
    ...base,
    bracketTemplateEnabled: input.bracketTemplateEnabled === true,
    groupMatchGenerationEnabled: input.groupMatchGenerationEnabled === true,
    groupSchedulingEnabled: input.groupSchedulingEnabled === true,
    groupStageEnabled: input.groupStageEnabled === true,
    groupStandingsEnabled: input.groupStandingsEnabled === true,
    groupTrackingEnabled: input.groupTrackingEnabled === true,
    qualificationEnabled: input.qualificationEnabled === true,
  };
  const organizerKind = typeof input.organizerKind === "string" ? input.organizerKind.toUpperCase() : "";
  if (!['TEAM', 'CLUB'].includes(organizerKind)) throw new Error("INVALID_TOURNAMENT_ORGANIZER");
  if (action === "tournament.beta_bundle.grant") {
    const maxTeams = Number(input.maxTeams);
    if (!Number.isInteger(maxTeams) || maxTeams < 4 || maxTeams > 64) throw new Error("TOURNAMENT_CAPACITY_LIMIT");
    return {
      ...base,
      capacityOverride: maxTeams > 32 && input.capacityOverride === true,
      expiresAt: optionalTimestamp(input.expiresAt),
      maxTeams,
      organizerKind,
      validFrom: optionalTimestamp(input.validFrom),
    };
  }
  const bundleId = typeof input.bundleId === "string" ? input.bundleId : "";
  if (!uuidPattern.test(bundleId)) throw new Error("TOURNAMENT_BETA_BUNDLE_REQUIRED");
  return { ...base, bundleId, organizerKind };
}

function metadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface: "platform_control_center_tournaments",
  };
}

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "competitions.read");
    return platformJson(await getPlatformTournamentControl(session));
  } catch (error) {
    return platformErrorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const gated = clientWriteGateResponse(request);
    if (gated) return gated;
    const session = await requirePlatformRequest(request, "competitions.manage");
    const body = tournamentRecord(await request.json());
    const action = body.action;
    if (!isTournamentPlatformAction(action)) throw new Error("INVALID_TOURNAMENT_PLATFORM_COMMAND");
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    const aggregateId = action === "tournament.flags.set" || action === "tournament.kill_switch"
      ? flagsAggregateId : action === "tournament.group_stage.flags.set" ? groupStageFlagsAggregateId
      : typeof body.aggregateId === "string" ? body.aggregateId : "";
    if (!uuidPattern.test(operationId) || !uuidPattern.test(aggregateId)
        || !Number.isInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_TOURNAMENT_PLATFORM_ENVELOPE");
    }
    const result = await session.client.rpc(
      action === "tournament.group_stage.flags.set"
        ? "command_pachanga_tournament_group_stage_platform_v1"
        : "command_pachanga_tournament_platform_v1",
      {
      aggregate_id: aggregateId,
      client_metadata: metadata(request),
      command_action: action,
      command_payload: platformPayload(action, tournamentRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
      },
    );
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
