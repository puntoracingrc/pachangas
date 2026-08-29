import { platformUserClient } from "../../admin/_lib/platform-auth";
import {
  isOrganizerAccessAction,
  isOrganizerAccessPlatformAction,
  organizerAccessRecord,
  type OrganizerAccessAction,
  type OrganizerAccessJson,
  type OrganizerAccessPlatformAction,
} from "../../organizer-access-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../client-policy/_contract";

export const organizerAccessUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const applicationFields = [
  "area", "competitionType", "fieldRelationship", "intent", "municipality",
  "reason", "summary", "targetStartDate", "teamCount",
] as const;

const actionFields: Record<OrganizerAccessAction | OrganizerAccessPlatformAction, ReadonlySet<string>> = {
  "application.create": new Set(["organizerKind", "planCode", ...applicationFields]),
  "application.reconsider": new Set(["reason"]),
  "application.respond_information": new Set(["consent", "message", ...applicationFields]),
  "application.submit": new Set(["consent", ...applicationFields]),
  "application.update": new Set(applicationFields),
  "application.withdraw": new Set(["reason"]),
  "competition.launch": new Set(["launcherKind", "launcherPayload", "reason"]),
  "onboarding.refresh": new Set(["reason"]),
  "rate_limit.override": new Set(["actionPattern", "organizerId", "organizerKind", "reason", "validUntil"]),
  "review.approve": new Set(["decisionCode", "grantPlanCode", "grantSource", "message", "privateNote", "reason", "validFrom", "validUntil"]),
  "review.expire": new Set(["decisionCode", "message", "privateNote", "reason"]),
  "review.reject": new Set(["decisionCode", "message", "privateNote", "reason"]),
  "review.request_information": new Set(["message", "privateNote", "reason"]),
  "review.start": new Set(["reason"]),
  "settings.flags": new Set([
    "applicationsEnabled", "demoWorldV30Enabled", "firstCompetitionLauncherEnabled",
    "onboardingEnabled", "partnershipApprovalEnabled", "reason", "reviewEnabled", "submissionEnabled",
  ]),
};

const serverFields = new Set([
  "accessGrantId", "actorId", "assignedReviewer", "confirmedAt", "confirmedRevision",
  "contentFingerprint", "createdBy", "decidedBy", "grantedBy", "onboardingId",
  "privateNoteVisible", "resultingAccessGrantId", "serverSequence", "submittedBy",
]);

function boundedText(value: unknown, maximum: number) {
  if (value == null) return "";
  if (typeof value !== "string" || value.length > maximum) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
  return value.trim();
}

function optionalDate(value: unknown) {
  const raw = boundedText(value, 40);
  if (!raw) return "";
  if (Number.isNaN(Date.parse(raw))) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
  return raw.length === 10 ? raw : new Date(raw).toISOString();
}

function safeNested(value: unknown, depth = 0): unknown {
  if (depth > 4) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
  if (value == null || typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
    return value;
  }
  if (typeof value === "string") return boundedText(value, 2400);
  if (Array.isArray(value)) {
    if (value.length > 40) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
    return value.map((item) => safeNested(item, depth + 1));
  }
  const record = organizerAccessRecord(value);
  if (Object.keys(record).length > 40 || Object.keys(record).some((key) => serverFields.has(key))) {
    throw new Error("ORGANIZER_ACCESS_SERVER_FIELDS_FORBIDDEN");
  }
  return Object.fromEntries(Object.entries(record).map(([key, item]) => [key, safeNested(item, depth + 1)]));
}

export function organizerAccessCommandPayload(
  action: OrganizerAccessAction | OrganizerAccessPlatformAction,
  raw: OrganizerAccessJson,
) {
  const allowed = actionFields[action];
  if (Object.keys(raw).some((key) => !allowed.has(key) || serverFields.has(key))) {
    throw new Error("ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED");
  }
  const payload = safeNested(raw) as OrganizerAccessJson;
  for (const key of ["area", "fieldRelationship", "message", "municipality", "privateNote", "reason", "summary"] as const) {
    if (key in payload) payload[key] = boundedText(payload[key], key === "summary" || key === "message" ? 2000 : key === "privateNote" ? 4000 : key === "fieldRelationship" ? 500 : 160);
  }
  for (const key of ["targetStartDate", "validFrom", "validUntil"] as const) {
    if (key in payload) payload[key] = optionalDate(payload[key]);
  }
  if ("teamCount" in payload && payload.teamCount !== "" && payload.teamCount != null) {
    const count = Number(payload.teamCount);
    if (!Number.isInteger(count) || count < 2 || count > 10_000) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
    payload.teamCount = count;
  }
  if (action === "application.create") {
    const kind = boundedText(payload.organizerKind, 8).toUpperCase();
    const planCode = boundedText(payload.planCode, 64).toUpperCase();
    if (!new Set(["CLUB", "TEAM"]).has(kind) || !/^[A-Z][A-Z0-9_]{2,63}$/.test(planCode)) {
      throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
    }
    payload.organizerKind = kind;
    payload.planCode = planCode;
  }
  for (const key of ["competitionType", "intent"] as const) {
    if (key in payload) {
      const value = boundedText(payload[key], 20).toUpperCase();
      if (!new Set(["BOTH", "LEAGUE", "TOURNAMENT"]).has(value)) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
      payload[key] = value;
    }
  }
  if (action === "competition.launch") {
    const kind = boundedText(payload.launcherKind, 16).toUpperCase();
    if (!new Set(["LEAGUE", "TOURNAMENT"]).has(kind)) throw new Error("ORGANIZER_ACCESS_COMMAND_INVALID");
    payload.launcherKind = kind;
    payload.launcherPayload = safeNested(payload.launcherPayload);
  }
  if (JSON.stringify(payload).length > 32_000) throw new Error("ORGANIZER_ACCESS_PAYLOAD_TOO_LARGE");
  return payload;
}

export function parseOrganizerAccessAction(value: unknown) {
  if (!isOrganizerAccessAction(value)) throw new Error("ORGANIZER_ACCESS_ACTION_NOT_ALLOWED");
  return value;
}

export function parseOrganizerAccessPlatformAction(value: unknown) {
  if (!isOrganizerAccessPlatformAction(value)) throw new Error("ORGANIZER_ACCESS_ACTION_NOT_ALLOWED");
  return value;
}

export function organizerAccessJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

export async function organizerAccessSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const result = await client.auth.getUser(token);
  if (result.error || !result.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: result.data.user };
}

export function requireOrganizerAccessOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("ORGANIZER_ACCESS_ORIGIN_REQUIRED");
}

export function organizerAccessWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function organizerAccessClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    displayMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    sessionId: request.headers.get("x-pachangas-write-id"),
    surface,
  };
}

export function organizerAccessError(error: unknown) {
  const detail = error instanceof Error ? error.message : "ORGANIZER_ACCESS_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|ALREADY|DUPLICATE/i.test(detail) ? 409
      : /RATE_LIMIT|PT429/i.test(detail) ? 429
        : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED|OWNER/i.test(detail) ? 403
          : /NOT_FOUND|P0002/i.test(detail) ? 404
            : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
              : /NOT_AVAILABLE|0A000/i.test(detail) ? 422
                : 400;
  const safeMessage = /Missing [A-Z0-9_]+/.test(detail)
    ? "La integración del servidor no está configurada."
    : detail;
  return organizerAccessJson({ error: "ORGANIZER_ACCESS_REQUEST_REJECTED", message: safeMessage }, status);
}
