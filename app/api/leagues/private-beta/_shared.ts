import { platformUserClient } from "../../../admin/_lib/platform-auth";
import {
  isLeaguePrivateBetaAction,
  leagueBetaRecord,
  type LeaguePrivateBetaAction,
  type LeaguePrivateBetaJson,
} from "../../../league-private-beta-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export const leagueBetaUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const stepKeys: Record<number, ReadonlySet<string>> = {
  1: new Set(["description", "generalArea", "imageUrl", "name", "slug"]),
  2: new Set(["modality"]),
  3: new Set(["editionName", "endsAt", "seasonLabel", "startsAt", "timezone"]),
  4: new Set(["legs", "registrationClosesAt", "registrationMode", "teamCap"]),
  5: new Set(["closeRequiresApprovedRosters", "credentialRequired", "jerseyRequired", "maximumRosterSize", "minimumRosterSize"]),
  6: new Set(["autoOfficialAfterConfirmation", "matchDurationMinutes", "pointsForDraw", "pointsForLoss", "pointsForWin", "requiredBufferMinutes", "responseDeadlineHours"]),
  7: new Set(["allowTbd", "minimumRestMinutes", "useDivision", "venueRequired", "weeklyPattern"]),
  8: new Set(["allowSharedPositions", "allowUnknownScorer", "scorerDetailPolicy", "tieBreakCriteria"]),
  9: new Set(["gracePeriodMinutes", "maximumMatchDurationMinutes", "minimumRestHours", "noShowLoserScore", "noShowOutcome", "noShowWinnerScore", "postponementDeadlinePolicy", "postponementResponseDeadlineHours"]),
  10: new Set(["acknowledgeUnavailableFeatures", "consent"]),
};

export function leagueBetaJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function boundedText(value: unknown, maximum: number) {
  if (value == null) return "";
  if (typeof value !== "string" || value.length > maximum) throw new Error("INVALID_LEAGUE_BETA_COMMAND");
  return value.trim();
}

function reason(input: LeaguePrivateBetaJson, fallback: string) {
  return boundedText(input.reason, 1200) || fallback;
}

function safeStepData(step: number, value: unknown) {
  const data = leagueBetaRecord(value);
  const allowed = stepKeys[step];
  if (!allowed || Object.keys(data).some((key) => !allowed.has(key))) {
    throw new Error("INVALID_LEAGUE_BETA_STEP");
  }
  const encoded = JSON.stringify(data);
  if (encoded.length > 24_000) throw new Error("LEAGUE_BETA_PAYLOAD_TOO_LARGE");
  if (step === 7) {
    if (!Array.isArray(data.weeklyPattern) || data.weeklyPattern.length > 14) {
      throw new Error("INVALID_LEAGUE_BETA_STEP");
    }
  }
  if (step === 8) {
    if (!Array.isArray(data.tieBreakCriteria) || data.tieBreakCriteria.length > 8) {
      throw new Error("INVALID_LEAGUE_BETA_STEP");
    }
  }
  return data;
}

export function leagueBetaCommandPayload(action: LeaguePrivateBetaAction, input: LeaguePrivateBetaJson) {
  if (action === "wizard.create") {
    const organizerKind = boundedText(input.organizerKind, 8).toUpperCase();
    if (!['TEAM', 'CLUB'].includes(organizerKind)) throw new Error("INVALID_LEAGUE_BETA_ORGANIZER");
    return { organizerKind, reason: reason(input, action) };
  }
  if (action === "wizard.step.save") {
    const step = Number(input.step);
    if (!Number.isInteger(step) || step < 1 || step > 10) throw new Error("INVALID_LEAGUE_BETA_STEP");
    return { data: safeStepData(step, input.data), reason: reason(input, action), step };
  }
  return { reason: reason(input, action) };
}

export function leagueBetaClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export async function leagueBetaSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: userResult.data.user };
}

export function requireLeagueBetaOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("LEAGUE_BETA_ORIGIN_REQUIRED");
}

export function leagueBetaWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function parseLeagueBetaAction(value: unknown) {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isLeaguePrivateBetaAction(action)) throw new Error("INVALID_LEAGUE_BETA_COMMAND");
  return action;
}

export function leagueBetaError(error: unknown) {
  const detail = error instanceof Error ? error.message : "LEAGUE_BETA_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|LIMIT/i.test(detail) ? 409
      : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED|OWNER_REQUIRED/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /NOT_AVAILABLE|0A000/i.test(detail) ? 422
              : 400;
  return leagueBetaJson({ error: "LEAGUE_BETA_REQUEST_REJECTED", message: detail }, status);
}
