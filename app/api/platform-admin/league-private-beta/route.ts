import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getPlatformLeaguePrivateBeta } from "../../../admin/_lib/platform-data";
import {
  isLeaguePrivateBetaPlatformAction,
  leagueBetaRecord,
  leaguePrivateBetaFlagsAggregateId,
} from "../../../league-private-beta-contract";
import { clientWriteGateResponse } from "../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function bounded(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

function reason(input: Record<string, unknown>) {
  const value = typeof input.reason === "string" ? input.reason.trim() : "";
  if (value.length < 3 || value.length > 1200) throw new Error("LEAGUE_BETA_REASON_REQUIRED");
  return value;
}

function optionalTimestamp(value: unknown) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) throw new Error("INVALID_LEAGUE_BETA_DATE");
  return new Date(value).toISOString();
}

function platformPayload(action: string, input: Record<string, unknown>) {
  const base = { reason: reason(input) };
  if (action === "beta.flags.set") {
    const allowed = new Set(["creationEnabled", "enabled", "publicDiscoveryEnabled", "reason"]);
    if (Object.keys(input).some((key) => !allowed.has(key))) throw new Error("INVALID_LEAGUE_BETA_FLAG");
    return {
      ...base,
      ...(typeof input.enabled === "boolean" ? { enabled: input.enabled } : {}),
      ...(typeof input.creationEnabled === "boolean" ? { creationEnabled: input.creationEnabled } : {}),
      publicDiscoveryEnabled: false,
    };
  }
  if (action === "beta.kill_switch") return base;
  const organizerKind = typeof input.organizerKind === "string" ? input.organizerKind.toUpperCase() : "";
  if (!['TEAM', 'CLUB'].includes(organizerKind)) throw new Error("INVALID_LEAGUE_BETA_ORGANIZER");
  if (action === "beta.bundle.grant") {
    const maxTeams = Number(input.maxTeams);
    if (!Number.isInteger(maxTeams) || maxTeams < 4 || maxTeams > 20) throw new Error("BETA_CAPACITY_LIMIT");
    return {
      ...base,
      capacityOverride: maxTeams > 12 && input.capacityOverride === true,
      expiresAt: optionalTimestamp(input.expiresAt),
      maxTeams,
      organizerKind,
      validFrom: optionalTimestamp(input.validFrom),
    };
  }
  const bundleId = typeof input.bundleId === "string" ? input.bundleId : "";
  if (!uuidPattern.test(bundleId)) throw new Error("LEAGUE_BETA_BUNDLE_REQUIRED");
  return { ...base, bundleId, organizerKind };
}

function metadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface: "platform_control_center_league_private_beta",
  };
}

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const page = bounded(url.searchParams.get("page"), 1, 100000);
    const pageSize = bounded(url.searchParams.get("pageSize"), 30, 100);
    const search = (url.searchParams.get("search") ?? "").trim().slice(0, 160);
    const session = await requirePlatformRequest(request, "competitions.read");
    return platformJson(await getPlatformLeaguePrivateBeta(session, search, page, pageSize));
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
    const body = leagueBetaRecord(await request.json());
    const action = typeof body.action === "string" ? body.action.trim() : "";
    if (!isLeaguePrivateBetaPlatformAction(action)) throw new Error("INVALID_LEAGUE_BETA_PLATFORM_COMMAND");
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    const aggregateId = action === "beta.flags.set" || action === "beta.kill_switch"
      ? leaguePrivateBetaFlagsAggregateId
      : typeof body.aggregateId === "string" ? body.aggregateId : "";
    if (!uuidPattern.test(operationId) || !uuidPattern.test(aggregateId)
      || !Number.isInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("INVALID_LEAGUE_BETA_PLATFORM_ENVELOPE");
    }
    const result = await session.client.rpc("command_pachanga_league_private_beta_platform_v1", {
      aggregate_id: aggregateId,
      client_metadata: metadata(request),
      command_action: action,
      command_payload: platformPayload(action, leagueBetaRecord(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
