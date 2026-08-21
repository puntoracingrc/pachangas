import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getPlatformClub, getPlatformClubs } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const flagsAggregateId = "00000000-0000-0000-0000-00000000c101";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const statuses = new Set(["draft", "pending_review", "active", "suspended", "rejected", "archived"]);
const verificationStatuses = new Set(["unverified", "pending", "verified", "rejected", "revoked"]);
const partnershipStatuses = new Set(["none", "candidate", "active", "paused", "ended"]);

function record(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function boundedInteger(value: string | null, fallback: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback;
}

function reasonFrom(payload: Record<string, unknown>) {
  const reason = typeof payload.reason === "string" ? payload.reason.trim() : "";
  if (reason.length < 3 || reason.length > 1200) throw new Error("Invalid operational reason");
  return reason;
}

function optionalTimestamp(value: unknown) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) throw new Error("Invalid date");
  return new Date(value).toISOString();
}

function statusPayload(input: Record<string, unknown>, allowed: Set<string>) {
  const status = typeof input.status === "string" ? input.status.trim().toLowerCase() : "";
  if (!allowed.has(status)) throw new Error("Invalid Club status");
  return { reason: reasonFrom(input), status };
}

function commandPayload(action: string, input: Record<string, unknown>) {
  if (action === "club_flags.set") {
    const payload: Record<string, unknown> = { reason: reasonFrom(input) };
    for (const key of [
      "foundationEnabled",
      "selfServiceCreationEnabled",
      "teamRelationshipsEnabled",
      "publicProfilesEnabled",
      "competitionOrganizerEnabled",
    ] as const) {
      if (typeof input[key] === "boolean") payload[key] = input[key];
    }
    if (Object.keys(payload).length === 1) throw new Error("Invalid empty flag update");
    return payload;
  }
  if (action === "club.status.set") return statusPayload(input, statuses);
  if (action === "club.verification.set") return statusPayload(input, verificationStatuses);
  if (action === "club.partnership.set") return statusPayload(input, partnershipStatuses);
  if (action === "club.entitlement.grant") {
    const source = input.source === "partnership" ? "partnership" : "platform_grant";
    return {
      capability: "competition_create",
      expiresAt: optionalTimestamp(input.expiresAt),
      reason: reasonFrom(input),
      source,
      validFrom: optionalTimestamp(input.validFrom),
    };
  }
  if (action === "club.entitlement.revoke") {
    const entitlementId = typeof input.entitlementId === "string" ? input.entitlementId : "";
    if (!uuidPattern.test(entitlementId)) throw new Error("Invalid entitlement");
    return { entitlementId, reason: reasonFrom(input) };
  }
  throw new Error("Invalid Club platform action");
}

function aggregateIdFor(action: string, value: unknown) {
  if (action === "club_flags.set") return flagsAggregateId;
  const aggregateId = typeof value === "string" ? value : "";
  if (!uuidPattern.test(aggregateId)) throw new Error("Invalid Club");
  return aggregateId;
}

function clientMetadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface: "platform_control_center_clubs",
  };
}

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const session = await requirePlatformRequest(request, "clubs.read");
    const clubId = url.searchParams.get("club");
    if (clubId) {
      if (!uuidPattern.test(clubId)) throw new Error("Invalid Club");
      return platformJson(await getPlatformClub(session, clubId));
    }
    const page = boundedInteger(url.searchParams.get("page"), 1, 100000);
    const pageSize = boundedInteger(url.searchParams.get("pageSize"), 30, 100);
    return platformJson(await getPlatformClubs(session, page, pageSize));
  } catch (error) {
    return platformErrorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "clubs.manage");
    const body = record(await request.json());
    const action = typeof body.action === "string" ? body.action : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!uuidPattern.test(operationId) || !Number.isInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("Invalid operation envelope");
    }
    const result = await session.client.rpc("command_pachanga_club_platform_v1", {
      aggregate_id: aggregateIdFor(action, body.aggregateId),
      client_metadata: clientMetadata(request),
      command_action: action,
      command_payload: commandPayload(action, record(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
