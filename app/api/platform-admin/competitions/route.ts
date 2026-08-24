import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getPlatformCompetitionFoundation, getPlatformLeagueMatchOperations, getPlatformLeagueParticipation, getPlatformLeagueScheduling } from "../../../admin/_lib/platform-data";
import { clientWriteGateResponse } from "../../client-policy/_contract";
import { leagueMatchOperationsFlagsAggregateId } from "../../../league-match-operations-contract";
import { leagueParticipationFlagsAggregateId } from "../../../league-participation-contract";
import { leagueSchedulingFlagsAggregateId } from "../../../league-scheduling-contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const flagsAggregateId = "00000000-0000-0000-0000-00000000c001";
const registryAggregateId = "00000000-0000-0000-0000-00000000c002";
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const capabilities = new Set([
  "competition_create",
  "competition_manage",
  "competition_staff",
  "competition_rules",
]);

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
  if (reason.length < 3 || reason.length > 1200) throw new Error("Motivo operativo no válido");
  return reason;
}

function optionalTimestamp(value: unknown) {
  if (value == null || value === "") return "";
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) throw new Error("Fecha no válida");
  return new Date(value).toISOString();
}

function commandPayload(action: string, input: Record<string, unknown>) {
  if (action === "league_match_operations_flags.set") {
    const allowed = new Set([
      "attendanceEnabled",
      "foundationEnabled",
      "officialResultsEnabled",
      "publicStandingsEnabled",
      "reason",
      "resultConfirmationEnabled",
      "sportingResultsEnabled",
      "squadsEnabled",
      "standingsEnabled",
    ]);
    if (Object.keys(input).some((key) => !allowed.has(key))) throw new Error("Flag R4C no permitido");
    const payload: Record<string, unknown> = { reason: reasonFrom(input) };
    for (const key of [
      "attendanceEnabled",
      "foundationEnabled",
      "officialResultsEnabled",
      "publicStandingsEnabled",
      "resultConfirmationEnabled",
      "sportingResultsEnabled",
      "squadsEnabled",
      "standingsEnabled",
    ] as const) {
      if (typeof input[key] === "boolean") payload[key] = input[key];
    }
    if (Object.keys(payload).length === 1) throw new Error("No hay cambios de flags R4C");
    return payload;
  }
  if (action === "league_scheduling_flags.set") {
    const allowed = new Set([
      "canonicalFixtureCreationEnabled",
      "editingEnabled",
      "foundationEnabled",
      "generationEnabled",
      "publicCalendarEnabled",
      "publicationEnabled",
      "reason",
    ]);
    if (Object.keys(input).some((key) => !allowed.has(key))) throw new Error("Flag R4B no permitido");
    const payload: Record<string, unknown> = { reason: reasonFrom(input) };
    for (const key of [
      "canonicalFixtureCreationEnabled",
      "editingEnabled",
      "foundationEnabled",
      "generationEnabled",
      "publicCalendarEnabled",
      "publicationEnabled",
    ] as const) {
      if (typeof input[key] === "boolean") payload[key] = input[key];
    }
    if (Object.keys(payload).length === 1) throw new Error("No hay cambios de flags R4B");
    return payload;
  }
  if (action === "league_participation_flags.set") {
    const payload: Record<string, unknown> = { reason: reasonFrom(input) };
    for (const key of [
      "foundationEnabled",
      "registrationEnabled",
      "publicRegistrationEnabled",
      "delegatesEnabled",
      "rostersEnabled",
      "schedulePreferencesEnabled",
    ] as const) {
      if (typeof input[key] === "boolean") payload[key] = input[key];
    }
    if (Object.keys(payload).length === 1) throw new Error("No hay cambios de flags R4A");
    return payload;
  }
  if (action === "foundation_flags.set") {
    const payload: Record<string, unknown> = { reason: reasonFrom(input) };
    for (const key of ["foundationEnabled", "creationEnabled", "contextBindingEnabled"] as const) {
      if (typeof input[key] === "boolean") payload[key] = input[key];
    }
    if (Object.keys(payload).length === 1) throw new Error("No hay cambios de flags");
    return payload;
  }
  if (action === "entitlement.grant") {
    const capability = typeof input.capability === "string" ? input.capability : "";
    if (!capabilities.has(capability)) throw new Error("Capacidad no válida");
    return {
      capability,
      expiresAt: optionalTimestamp(input.expiresAt),
      reason: reasonFrom(input),
      validFrom: optionalTimestamp(input.validFrom),
    };
  }
  if (action === "entitlement.revoke") {
    const entitlementId = typeof input.entitlementId === "string" ? input.entitlementId : "";
    if (!uuidPattern.test(entitlementId)) throw new Error("Entitlement no válido");
    return { entitlementId, reason: reasonFrom(input) };
  }
  if (action === "canonical.backfill") return { reason: reasonFrom(input) };
  throw new Error("Acción de competición no permitida");
}

function aggregateIdFor(action: string, body: Record<string, unknown>) {
  if (action === "league_match_operations_flags.set") return leagueMatchOperationsFlagsAggregateId;
  if (action === "league_scheduling_flags.set") return leagueSchedulingFlagsAggregateId;
  if (action === "league_participation_flags.set") return leagueParticipationFlagsAggregateId;
  if (action === "foundation_flags.set") return flagsAggregateId;
  if (action === "canonical.backfill") return registryAggregateId;
  const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
  if (!uuidPattern.test(aggregateId)) throw new Error("Organizador no válido");
  return aggregateId;
}

function clientMetadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface: "platform_control_center_competitions",
  };
}

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const page = boundedInteger(url.searchParams.get("page"), 1, 100000);
    const pageSize = boundedInteger(url.searchParams.get("pageSize"), 30, 100);
    const session = await requirePlatformRequest(request, "competitions.read");
    const [foundation, leagueParticipation, leagueScheduling, leagueMatchOperations] = await Promise.all([
      getPlatformCompetitionFoundation(session, page, pageSize),
      getPlatformLeagueParticipation(session, page, pageSize),
      getPlatformLeagueScheduling(session, page, pageSize),
      getPlatformLeagueMatchOperations(session, page, pageSize),
    ]);
    return platformJson({ ...foundation, leagueMatchOperations, leagueParticipation, leagueScheduling });
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
    const body = record(await request.json());
    const action = typeof body.action === "string" ? body.action : "";
    const operationId = typeof body.operationId === "string" ? body.operationId : "";
    const expectedRevision = Number(body.expectedRevision);
    if (!uuidPattern.test(operationId) || !Number.isInteger(expectedRevision) || expectedRevision < 0) {
      throw new Error("Envelope de operación no válido");
    }
    const aggregateId = aggregateIdFor(action, body);
    const payload = commandPayload(action, record(body.payload));
    const result = action === "league_match_operations_flags.set"
      ? await session.client.rpc("command_pachanga_league_match_operations_platform_v1", {
        aggregate_id: aggregateId,
        client_metadata: clientMetadata(request),
        command_payload: payload,
        expected_revision: expectedRevision,
        operation_id: operationId,
      })
      : action === "league_scheduling_flags.set"
      ? await session.client.rpc("command_pachanga_league_scheduling_platform_v1", {
        aggregate_id: aggregateId,
        client_metadata: clientMetadata(request),
        command_payload: payload,
        expected_revision: expectedRevision,
        operation_id: operationId,
      })
      : action === "league_participation_flags.set"
        ? await session.client.rpc("command_pachanga_league_participation_platform_v1", {
        aggregate_id: aggregateId,
        client_metadata: clientMetadata(request),
        command_payload: payload,
        expected_revision: expectedRevision,
        operation_id: operationId,
      })
        : await session.client.rpc("command_pachanga_competition_platform_v1", {
        aggregate_id: aggregateId,
        client_metadata: clientMetadata(request),
        command_action: action,
        command_payload: payload,
        expected_revision: expectedRevision,
        operation_id: operationId,
        });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
