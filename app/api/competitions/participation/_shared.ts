import { platformUserClient } from "../../../admin/_lib/platform-auth";
import {
  isLeagueParticipationAction,
  leagueRecord,
  type LeagueJson,
  type LeagueParticipationAction,
} from "../../../league-participation-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export { leagueRecord };

export const leagueUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const timePattern = /^([01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/;
const colorPattern = /^#[0-9a-f]{6}$/i;

export function leagueJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function text(input: LeagueJson, key: string, maximum = 1200) {
  const value = typeof input[key] === "string" ? input[key].trim() : "";
  if (value.length > maximum) throw new Error("INVALID_LEAGUE_COMMAND");
  return value;
}

function requiredText(input: LeagueJson, key: string, maximum = 1200) {
  const value = text(input, key, maximum);
  if (!value) throw new Error("INVALID_LEAGUE_COMMAND");
  return value;
}

function uuid(input: LeagueJson, key: string, optional = false) {
  const value = text(input, key, 40);
  if (optional && !value) return "";
  if (!leagueUuidPattern.test(value)) throw new Error("INVALID_LEAGUE_COMMAND");
  return value;
}

function integer(input: LeagueJson, key: string, minimum: number, maximum: number, optional = false) {
  if (optional && (input[key] === "" || input[key] == null)) return "";
  const parsed = Number(input[key]);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) throw new Error("INVALID_LEAGUE_COMMAND");
  return parsed;
}

function timestamp(input: LeagueJson, key: string, optional = false) {
  const value = text(input, key, 50);
  if (optional && !value) return "";
  if (!value || Number.isNaN(Date.parse(value))) throw new Error("INVALID_LEAGUE_COMMAND");
  return new Date(value).toISOString();
}

function date(input: LeagueJson, key: string, optional = false) {
  const value = text(input, key, 10);
  if (optional && !value) return "";
  if (!datePattern.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) throw new Error("INVALID_LEAGUE_COMMAND");
  return value;
}

function time(input: LeagueJson, key: string) {
  const value = text(input, key, 8);
  if (!timePattern.test(value)) throw new Error("INVALID_LEAGUE_COMMAND");
  return value;
}

function enumValue(input: LeagueJson, key: string, values: readonly string[], optional = false) {
  const value = text(input, key, 120).toUpperCase();
  if (optional && !value) return "";
  if (!values.includes(value)) throw new Error("INVALID_LEAGUE_COMMAND");
  return value;
}

function reason(input: LeagueJson, action: string) {
  return text(input, "reason", 1200) || action;
}

function reasonCode(input: LeagueJson, action: string) {
  return text(input, "reasonCode", 120) || action;
}

function common(input: LeagueJson, action: string) {
  return { reason: reason(input, action), reasonCode: reasonCode(input, action) };
}

function schedulePayload(input: LeagueJson, action: string, preference: boolean) {
  const output: LeagueJson = {
    ...common(input, action),
    endLocalTime: time(input, "endLocalTime"),
    startLocalTime: time(input, "startLocalTime"),
    timezone: requiredText(input, "timezone", 100),
    weekday: integer(input, "weekday", 1, 7),
  };
  if (preference) {
    output.preferredArea = text(input, "preferredArea", 160);
    output.venueReference = text(input, "venueReference", 500);
    output.weight = integer(input, "weight", 1, 100);
  } else {
    output.validFromDate = date(input, "validFromDate", true);
    output.validUntilDate = date(input, "validUntilDate", true);
  }
  return output;
}

export function leagueCommandPayload(action: LeagueParticipationAction, input: LeagueJson) {
  if (action === "category.create") {
    const slug = requiredText(input, "slug", 80).toLowerCase();
    if (!slugPattern.test(slug)) throw new Error("INVALID_LEAGUE_COMMAND");
    const policy = leagueRecord(input.eligibilityPolicy);
    return {
      ...common(input, action),
      ageReferenceDate: date(input, "ageReferenceDate", true),
      description: text(input, "description", 1200),
      eligibilityPolicy: typeof policy.credentialRequired === "boolean"
        ? { credentialRequired: policy.credentialRequired }
        : {},
      levelLabel: text(input, "levelLabel", 80),
      maximumAge: integer(input, "maximumAge", 0, 120, true),
      minimumAge: integer(input, "minimumAge", 0, 120, true),
      name: requiredText(input, "name", 120),
      ruleRevisionId: uuid(input, "ruleRevisionId"),
      slug,
      sportFormat: requiredText(input, "sportFormat", 40),
      visibility: enumValue(input, "visibility", ["PRIVATE", "INTERNAL", "PUBLIC"]).toLowerCase(),
    };
  }
  if (["category.activate", "category.close", "category.archive", "registration.notify_closing", "registration.close", "registration.close_and_expire_pending", "entry.accept", "entry.reject", "entry.withdraw", "entry.decline", "delegate.accept", "delegate.decline", "delegate.revoke", "roster.create", "roster.submit", "roster.request_changes", "roster.reopen", "roster.approve", "roster.lock", "roster.amend"].includes(action)) {
    return common(input, action);
  }
  if (action === "registration.open") return {
    ...common(input, action),
    closesAt: timestamp(input, "closesAt"),
    opensAt: timestamp(input, "opensAt", true),
    registrationMode: enumValue(input, "registrationMode", ["PUBLIC_APPROVAL", "INVITE_ONLY"]),
    ruleRevisionId: uuid(input, "ruleRevisionId"),
  };
  if (action === "entry.submit" || action === "entry.invite") return {
    ...common(input, action),
    expiresAt: action === "entry.invite" ? timestamp(input, "expiresAt", true) : "",
    teamId: uuid(input, "teamId"),
  };
  if (action === "delegate.invite") return {
    ...common(input, action),
    role: enumValue(input, "role", ["PRIMARY_DELEGATE", "ROSTER_MANAGER", "VIEWER"]),
    userId: uuid(input, "userId"),
    validUntil: timestamp(input, "validUntil", true),
  };
  if (action === "delegate.primary.transfer" || action === "delegate.transfer") return {
    ...common(input, action),
    targetDelegateId: uuid(input, "targetDelegateId"),
  };
  if (action === "roster.member.add" || action === "roster.member.remove") return {
    ...common(input, action), playerProfileId: uuid(input, "playerProfileId"),
  };
  if (action === "jersey.assign") return {
    ...common(input, action),
    number: integer(input, "number", 0, 999),
    playerProfileId: uuid(input, "playerProfileId"),
  };
  if (action === "credential.review") return {
    ...common(input, action),
    evidenceReference: text(input, "evidenceReference", 500),
    expiresAt: timestamp(input, "expiresAt", true),
    status: enumValue(input, "status", ["PENDING", "VERIFIED", "EXPIRED", "REJECTED", "REVOKED"]).toLowerCase(),
    verificationMethod: requiredText(input, "verificationMethod", 80),
  };
  if (action === "eligibility.waive") return {
    ...common(input, action), validUntil: timestamp(input, "validUntil", true),
  };
  if (action === "kit.set") {
    const primaryColor = requiredText(input, "primaryColor", 7);
    const secondaryColor = requiredText(input, "secondaryColor", 7);
    if (!colorPattern.test(primaryColor) || !colorPattern.test(secondaryColor)) throw new Error("INVALID_LEAGUE_COMMAND");
    return {
      ...common(input, action),
      assetReference: text(input, "assetReference", 500),
      kitType: enumValue(input, "kitType", ["HOME", "AWAY", "ALTERNATE"]),
      pattern: text(input, "pattern", 80),
      primaryColor,
      secondaryColor,
    };
  }
  if (action === "stage_membership.assign") return {
    ...common(input, action),
    divisionId: uuid(input, "divisionId", true),
    groupId: uuid(input, "groupId", true),
    stageId: uuid(input, "stageId"),
  };
  if (action === "availability.set") return schedulePayload(input, action, false);
  if (action === "preference.set") return schedulePayload(input, action, true);
  throw new Error("INVALID_LEAGUE_COMMAND");
}

export function leagueClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export async function leagueSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: userResult.data.user };
}

export function requireLeagueOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("LEAGUE_ORIGIN_REQUIRED");
}

export function leagueWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function parseLeagueAction(value: unknown) {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isLeagueParticipationAction(action)) throw new Error("INVALID_LEAGUE_COMMAND");
  return action;
}

export function leagueError(error: unknown) {
  const detail = error instanceof Error ? error.message : "LEAGUE_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|DUPLICATE|ALREADY/i.test(detail) ? 409
      : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /FEATURE_NOT_AVAILABLE|0A000/i.test(detail) ? 422
              : 400;
  return leagueJson({ error: "LEAGUE_REQUEST_REJECTED", message: detail }, status);
}
