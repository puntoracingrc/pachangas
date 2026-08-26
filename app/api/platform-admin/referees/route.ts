import { clientWriteGateResponse } from "../../client-policy/_contract";
import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getPlatformReferee, getPlatformRefereeHealth, getPlatformReferees } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const flagsAggregateId = "00000000-0000-0000-0000-00000000a3f3";
const assignmentFlagsAggregateId = "00000000-0000-0000-0000-00000000a4f4";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function record(value: unknown) { return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {}; }
function bounded(value: string | null, fallback: number, maximum: number) { const parsed = Number.parseInt(value ?? "", 10); return Number.isInteger(parsed) ? Math.min(Math.max(parsed, 1), maximum) : fallback; }
function reason(payload: Record<string, unknown>) { const value = typeof payload.reason === "string" ? payload.reason.trim() : ""; if (value.length < 3 || value.length > 1200) throw new Error("Invalid referee reason"); return value; }

function payloadFor(action: string, input: Record<string, unknown>) {
  if (action === "referee_flags.set") {
    const payload: Record<string, unknown> = { reason: reason(input) };
    for (const key of ["foundationEnabled", "selfServiceEnabled", "publicProfilesEnabled", "marketplaceEnabled", "clubRelationshipsEnabled", "assignmentsEnabled"] as const) {
      if (typeof input[key] === "boolean") payload[key] = input[key];
    }
    if (Object.keys(payload).length === 1) throw new Error("Invalid empty referee flag update");
    return payload;
  }
  if (action === "assignment_beta.flags.set") {
    const payload: Record<string, unknown> = { reason: reason(input) };
    for (const key of ["assignmentPrivateBetaEnabled", "assignmentsEnabled"] as const) {
      if (typeof input[key] === "boolean") payload[key] = input[key];
    }
    if (Object.keys(payload).length === 1) throw new Error("Invalid empty referee assignment flag update");
    return payload;
  }
  if (new Set(["profile.activate", "profile.suspend", "profile.restore", "verification.pending", "verification.approve", "verification.reject", "verification.revoke", "stats.rebuild", "assignment.completion.void", "assignment.reconcile"]).has(action)) {
    return { reason: reason(input) };
  }
  throw new Error("Invalid referee platform action");
}

function metadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface: "platform_control_center_referees",
    writeId: request.headers.get("x-pachangas-write-id"),
  };
}

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "referees.read");
    const url = new URL(request.url);
    const profileId = url.searchParams.get("profile") ?? "";
    if (profileId) {
      if (!uuidPattern.test(profileId)) throw new Error("Invalid referee profile");
      return platformJson(await getPlatformReferee(session, profileId));
    }
    if (url.searchParams.get("health") === "1") return platformJson(await getPlatformRefereeHealth(session));
    return platformJson(await getPlatformReferees(session, {
      area: url.searchParams.get("area")?.slice(0, 120) ?? "",
      marketplace: url.searchParams.get("marketplace")?.slice(0, 30) ?? "",
      modality: url.searchParams.get("modality")?.slice(0, 30) ?? "",
      query: url.searchParams.get("q")?.slice(0, 120) ?? "",
      status: url.searchParams.get("status")?.slice(0, 30) ?? "",
      verification: url.searchParams.get("verification")?.slice(0, 30) ?? "",
    }, bounded(url.searchParams.get("page"), 1, 100_000), bounded(url.searchParams.get("pageSize"), 30, 100)));
  } catch (error) { return platformErrorResponse(error); }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const gated = clientWriteGateResponse(request);
    if (gated) return gated;
    const session = await requirePlatformRequest(request, "referees.manage");
    const body = record(await request.json());
    const action = typeof body.action === "string" ? body.action.trim() : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    const aggregateId = action === "referee_flags.set" ? flagsAggregateId : action === "assignment_beta.flags.set" ? assignmentFlagsAggregateId : typeof body.aggregateId === "string" ? body.aggregateId : "";
    if (!uuidPattern.test(operationId) || !uuidPattern.test(aggregateId) || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) throw new Error("Invalid referee operation envelope");
    const payload = payloadFor(action, record(body.payload));
    const result = action === "assignment.reconcile"
      ? await session.client.rpc("reconcile_pachanga_referee_assignment_v1", {
          client_metadata: metadata(request), expected_revision: expectedRevision,
          operation_id: operationId, target_assignment_id: aggregateId,
        })
      : action === "assignment_beta.flags.set"
      ? await session.client.rpc("command_pachanga_referee_assignment_beta_admin_v1", {
          client_metadata: metadata(request), command_action: action,
          command_payload: payload, expected_revision: expectedRevision, operation_id: operationId,
        })
      : await session.client.rpc("command_pachanga_referee_platform_admin_v1", {
          aggregate_id: aggregateId, client_metadata: metadata(request), command_action: action,
          command_payload: payload, expected_revision: expectedRevision, operation_id: operationId,
        });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) { return platformErrorResponse(error); }
}
