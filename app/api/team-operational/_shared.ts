import { platformUserClient } from "../../admin/_lib/platform-auth";
import {
  isTeamOperationalOwnerAction,
  teamOperationalRecord,
  type TeamOperationalAction,
  type TeamOperationalJson,
} from "../../team-operational-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../client-policy/_contract";

export const teamOperationalUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const ownerFields: Record<TeamOperationalAction, ReadonlySet<string>> = {
  "team.lifecycle.archive": new Set(["confirm", "continuityPolicy", "publicMessage", "reasonCode"]),
  "team.lifecycle.restore": new Set(["confirm", "publicMessage", "reasonCode"]),
  "team.appeal.create": new Set(["restrictionId", "requestedOutcome", "message", "reasonCode"]),
  "team.appeal.submit": new Set(["appealId", "message", "reasonCode"]),
  "team.appeal.withdraw": new Set(["appealId", "message", "reasonCode"]),
  "team.review.open": new Set(),
  "team.review.close": new Set(),
  "team.restriction.apply": new Set(),
  "team.restriction.modify": new Set(),
  "team.restriction.lift": new Set(),
  "team.suspend": new Set(),
  "team.restore": new Set(),
  "team.continuity.set": new Set(),
  "team.appeal.review": new Set(),
  "team.appeal.resolve": new Set(),
};

const platformFields: Record<TeamOperationalAction, ReadonlySet<string>> = {
  ...ownerFields,
  "team.review.open": new Set(["reasonCode", "safeMessage", "privateNote", "evidence", "assignedReviewer"]),
  "team.review.close": new Set(["reviewId", "outcome", "safeMessage", "privateNote", "reasonCode"]),
  "team.restriction.apply": new Set(["confirm", "preset", "scopes", "continuityPolicy", "reasonCode", "publicMessage", "privateNote", "evidence", "effectiveFrom", "effectiveUntil"]),
  "team.restriction.modify": new Set(["confirm", "preset", "scopes", "continuityPolicy", "reasonCode", "publicMessage", "privateNote", "evidence", "effectiveFrom", "effectiveUntil"]),
  "team.restriction.lift": new Set(["confirm", "scopes", "reasonCode", "publicMessage", "privateNote"]),
  "team.suspend": new Set(["confirm", "preset", "scopes", "continuityPolicy", "reasonCode", "publicMessage", "privateNote", "evidence", "effectiveFrom", "effectiveUntil"]),
  "team.restore": new Set(["confirm", "scopes", "reasonCode", "publicMessage", "privateNote"]),
  "team.continuity.set": new Set(["competitionId", "policy", "reasonCode", "publicMessage", "privateNote", "effectiveUntil"]),
  "team.appeal.review": new Set(["appealId", "deadlineAt", "safeMessage", "privateNote", "reasonCode"]),
  "team.appeal.resolve": new Set(["appealId", "resolution", "safeMessage", "privateNote", "reasonCode", "preset", "scopes", "continuityPolicy", "effectiveUntil"]),
};

const forbiddenServerFields = new Set([
  "actorId", "confirmedAt", "confirmedRevision", "createdBy", "effectiveStatus",
  "enforcement", "lifecycle", "operationId", "revision", "serverSequence", "updatedAt",
]);

function safeValue(value: unknown, depth = 0): unknown {
  if (depth > 3) throw new Error("TEAM_OPERATIONAL_COMMAND_INVALID");
  if (value == null || typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("TEAM_OPERATIONAL_COMMAND_INVALID");
    return value;
  }
  if (typeof value === "string") {
    if (value.length > 4000) throw new Error("TEAM_OPERATIONAL_COMMAND_INVALID");
    return value.trim();
  }
  if (Array.isArray(value)) {
    if (value.length > 20) throw new Error("TEAM_OPERATIONAL_COMMAND_INVALID");
    return value.map((item) => safeValue(item, depth + 1));
  }
  const record = teamOperationalRecord(value);
  if (Object.keys(record).length > 30 || Object.keys(record).some((key) => forbiddenServerFields.has(key))) {
    throw new Error("TEAM_OPERATIONAL_SERVER_FIELDS_FORBIDDEN");
  }
  return Object.fromEntries(Object.entries(record).map(([key, item]) => [key, safeValue(item, depth + 1)]));
}

export function teamOperationalCommandPayload(action: TeamOperationalAction, raw: TeamOperationalJson, platform = false) {
  if (!platform && !isTeamOperationalOwnerAction(action)) throw new Error("TEAM_OPERATIONAL_ACTION_NOT_ALLOWED");
  const allowed = (platform ? platformFields : ownerFields)[action];
  if (Object.keys(raw).some((key) => forbiddenServerFields.has(key) || !allowed.has(key))) {
    throw new Error("TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED");
  }
  const payload = safeValue(raw) as TeamOperationalJson;
  if (JSON.stringify(payload).length > 20_000) throw new Error("TEAM_OPERATIONAL_PAYLOAD_TOO_LARGE");
  return payload;
}

export function teamOperationalJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

export async function teamOperationalSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const result = await client.auth.getUser(token);
  if (result.error || !result.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, user: result.data.user };
}

export function requireTeamOperationalOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("TEAM_OPERATIONAL_ORIGIN_REQUIRED");
}

export function teamOperationalWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function teamOperationalClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    sessionId: request.headers.get("x-pachangas-write-id"),
    surface,
  };
}

export function teamOperationalError(error: unknown) {
  const detail = error instanceof Error ? error.message : "TEAM_OPERATIONAL_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|OPERATION_ID_REUSED/i.test(detail) ? 409
      : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED|OWNER/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : 400;
  return teamOperationalJson({ error: "TEAM_OPERATIONAL_REQUEST_REJECTED", message: detail }, status);
}
