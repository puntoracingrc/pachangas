import { createClient } from "@supabase/supabase-js";
import { platformUserClient } from "../../../admin/_lib/platform-auth";
import {
  isLeagueOperationalExceptionAction,
  leagueOperationalRecord,
  type LeagueOperationalExceptionAction,
  type LeagueOperationalJson,
} from "../../../league-operational-exceptions-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export { leagueOperationalRecord };

export const leagueOperationalUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const baseKeys = ["evidenceRefs", "publicSummary", "reasonCode", "reasonText"] as const;
const actionKeys: Record<LeagueOperationalExceptionAction, readonly string[]> = {
  "administrative_decision.annul": [...baseKeys, "decisionId"],
  "administrative_decision.publish": [...baseKeys, "cancellationOutcome", "decisionType", "noShowIncidentId", "resumeMinute", "scheduledEnd", "scheduledStart", "suspensionId", "timezone", "venueId", "venueLabel", "venueStatus"],
  "administrative_decision.supersede": [...baseKeys, "cancellationOutcome", "decisionType", "noShowIncidentId", "previousDecisionId", "resumeMinute", "scheduledEnd", "scheduledStart", "suspensionId", "timezone", "venueId", "venueLabel", "venueStatus"],
  "fixture.cancel": [...baseKeys, "cancellationOutcome"],
  "fixture.change_venue": [...baseKeys, "venueId", "venueLabel", "venueStatus"],
  "fixture.reschedule": [...baseKeys, "scheduledEnd", "scheduledStart", "timezone"],
  "late_arrival.confirm_arrival": [...baseKeys, "incidentId"],
  "late_arrival.escalate": [...baseKeys, "incidentId"],
  "late_arrival.report": [...baseKeys, "responsibleEntryId"],
  "no_show.confirm": [...baseKeys, "incidentId"],
  "no_show.reject": [...baseKeys, "incidentId"],
  "no_show.report": [...baseKeys, "responsibleEntryId"],
  "no_show.resolve": [...baseKeys, "incidentId"],
  "postponement.expire": [...baseKeys, "requestId"],
  "postponement.request": [...baseKeys, "proposedEnd", "proposedStart", "proposedTimezone", "proposedVenueId", "proposedVenueLabel", "proposedVenueStatus", "requestingEntryId"],
  "postponement.respond": [...baseKeys, "proposedEnd", "proposedStart", "proposedTimezone", "proposedVenueId", "proposedVenueLabel", "proposedVenueStatus", "requestId", "responseKind"],
  "postponement.withdraw": [...baseKeys, "requestId"],
  "suspension.cancel": [...baseKeys, "cancellationOutcome", "suspensionId"],
  "suspension.confirm": [...baseKeys, "suspensionId"],
  "suspension.order_replay": [...baseKeys, "scheduledEnd", "scheduledStart", "suspensionId", "timezone", "venueId", "venueLabel", "venueStatus"],
  "suspension.report": [...baseKeys, "partialScoreAway", "partialScoreHome", "reportedMinute", "reportingEntryId"],
  "suspension.resolve": [...baseKeys, "resolutionType", "suspensionId"],
  "suspension.resume": [...baseKeys, "suspensionId"],
  "suspension.schedule_resume": [...baseKeys, "resumeMinute", "scheduledEnd", "scheduledStart", "suspensionId", "timezone", "venueId", "venueLabel", "venueStatus"],
};

const uuidKeys = new Set([
  "decisionId", "incidentId", "noShowIncidentId", "previousDecisionId",
  "proposedVenueId", "reportingEntryId", "requestId", "requestingEntryId",
  "responsibleEntryId", "suspensionId", "venueId",
]);
const timestampKeys = new Set(["proposedEnd", "proposedStart", "scheduledEnd", "scheduledStart"]);
const integerKeys = new Set(["partialScoreAway", "partialScoreHome", "reportedMinute", "resumeMinute"]);
const shortTextKeys = new Set([
  "cancellationOutcome", "decisionType", "proposedTimezone", "proposedVenueStatus",
  "reasonCode", "resolutionType", "responseKind", "timezone", "venueStatus",
]);

export function leagueOperationalJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function cleanText(value: unknown, maximum: number) {
  if (value == null || value === "") return "";
  if (typeof value !== "string") throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
  const clean = value.trim();
  if (clean.length > maximum) throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
  return clean;
}

function cleanEvidence(value: unknown) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 20) throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
  const refs = value.map((item) => cleanText(item, 500)).filter(Boolean);
  if (new TextEncoder().encode(JSON.stringify(refs)).length > 16_000) {
    throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
  }
  return refs;
}

export function leagueOperationalCommandPayload(action: LeagueOperationalExceptionAction, input: LeagueOperationalJson) {
  const allowed = new Set(actionKeys[action]);
  if (Object.keys(input).some((key) => !allowed.has(key))) {
    throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
  }
  const output: LeagueOperationalJson = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === "evidenceRefs") {
      output[key] = cleanEvidence(value);
    } else if (uuidKeys.has(key)) {
      const parsed = cleanText(value, 40);
      if (parsed && !leagueOperationalUuidPattern.test(parsed)) throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
      if (parsed) output[key] = parsed;
    } else if (timestampKeys.has(key)) {
      const parsed = cleanText(value, 60);
      if (parsed && Number.isNaN(Date.parse(parsed))) throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
      if (parsed) output[key] = new Date(parsed).toISOString();
    } else if (integerKeys.has(key)) {
      if (value == null || value === "") continue;
      const parsed = Number(value);
      const maximum = key.startsWith("partialScore") ? 99 : 180;
      if (!Number.isInteger(parsed) || parsed < 0 || parsed > maximum) throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
      output[key] = parsed;
    } else if (key === "publicSummary") {
      output[key] = cleanText(value, 500);
    } else if (key === "reasonText") {
      output[key] = cleanText(value, 4000);
    } else if (key === "proposedVenueLabel" || key === "venueLabel") {
      output[key] = cleanText(value, 160);
    } else if (shortTextKeys.has(key)) {
      output[key] = cleanText(value, key === "reasonCode" ? 120 : 80);
    }
  }
  return output;
}

export function leagueOperationalClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export async function leagueOperationalSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: userResult.data.user };
}

export function leagueOperationalPublicClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !key) throw new Error("LEAGUE_OPERATIONAL_EXCEPTIONS_INTEGRATION_NOT_CONFIGURED");
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

export function requireLeagueOperationalOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("LEAGUE_OPERATIONAL_EXCEPTIONS_ORIGIN_REQUIRED");
}

export function leagueOperationalWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function parseLeagueOperationalAction(value: unknown) {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isLeagueOperationalExceptionAction(action)) throw new Error("INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND");
  return action;
}

export function leagueOperationalError(error: unknown) {
  const detail = error instanceof Error ? error.message : "LEAGUE_OPERATIONAL_EXCEPTIONS_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|DUPLICATE|ALREADY|LOCKED|NOT_(PENDING|EDITABLE|CONFIRMABLE|REVIEWABLE|RESOLVABLE|EXPIRABLE|REPORTABLE)|WINDOW_CLOSED|DEADLINE/i.test(detail) ? 409
      : /FORBIDDEN|DENIED|REQUIRED|42501|DISABLED|NOT_AUTHORIZED/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /FEATURE_NOT_AVAILABLE|0A000|POLICY|OUTSIDE|OVERLAP|INVALID|FORBIDDEN_FIELD/i.test(detail) ? 422
              : 400;
  return leagueOperationalJson({ error: "LEAGUE_OPERATIONAL_EXCEPTIONS_REQUEST_REJECTED", message: detail }, status);
}
