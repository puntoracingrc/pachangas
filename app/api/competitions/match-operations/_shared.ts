import { createClient } from "@supabase/supabase-js";
import { platformUserClient } from "../../../admin/_lib/platform-auth";
import {
  isLeagueMatchOperationsAction,
  leagueMatchRecord,
  type LeagueMatchOperationsAction,
  type LeagueMatchOperationsJson,
} from "../../../league-match-operations-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export { leagueMatchRecord };

export const leagueMatchUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const checksumPattern = /^[0-9a-f]{64}$/i;

export function leagueMatchJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function assertOnlyKeys(input: LeagueMatchOperationsJson, keys: readonly string[]) {
  const allowed = new Set(keys);
  if (Object.keys(input).some((key) => !allowed.has(key))) {
    throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
  }
}

function text(input: LeagueMatchOperationsJson, key: string, maximum = 1200) {
  const value = typeof input[key] === "string" ? input[key].trim() : "";
  if (value.length > maximum) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
  return value;
}

function uuid(input: LeagueMatchOperationsJson, key: string) {
  const value = text(input, key, 40);
  if (!leagueMatchUuidPattern.test(value)) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
  return value;
}

function integer(input: LeagueMatchOperationsJson, key: string, minimum: number, maximum: number, optional = false) {
  if (optional && (input[key] == null || input[key] === "")) return undefined;
  const value = Number(input[key]);
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
  }
  return value;
}

function reason(input: LeagueMatchOperationsJson, fallback: string) {
  return text(input, "reason") || fallback;
}

function scorers(input: LeagueMatchOperationsJson) {
  if (input.scorers == null) return undefined;
  if (!Array.isArray(input.scorers) || input.scorers.length > 40) {
    throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
  }
  return input.scorers.map((raw) => {
    const item = leagueMatchRecord(raw);
    assertOnlyKeys(item, ["displayName", "goals", "rosterMemberId", "unknownSlot"]);
    const rosterMemberId = text(item, "rosterMemberId", 40);
    const unknownSlot = integer(item, "unknownSlot", 1, 40, true);
    if ((rosterMemberId ? 1 : 0) + (unknownSlot == null ? 0 : 1) !== 1) {
      throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    }
    if (rosterMemberId && !leagueMatchUuidPattern.test(rosterMemberId)) {
      throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    }
    return {
      displayName: text(item, "displayName", 120),
      goals: integer(item, "goals", 1, 99),
      ...(rosterMemberId ? { rosterMemberId } : { unknownSlot }),
    };
  });
}

function entryPayload(action: string, input: LeagueMatchOperationsJson) {
  assertOnlyKeys(input, ["entryId", "reason"]);
  return { entryId: uuid(input, "entryId"), reason: reason(input, action) };
}

function resultPayload(action: string, input: LeagueMatchOperationsJson, allowOptionalScores = false) {
  assertOnlyKeys(input, ["entryId", "reason", "scoreAway", "scoreHome", "scorers"]);
  const parsedScorers = scorers(input);
  return {
    entryId: uuid(input, "entryId"),
    reason: reason(input, action),
    scoreAway: integer(input, "scoreAway", 0, 99, allowOptionalScores),
    scoreHome: integer(input, "scoreHome", 0, 99, allowOptionalScores),
    ...(parsedScorers === undefined ? {} : { scorers: parsedScorers }),
  };
}

export function leagueMatchCommandPayload(action: LeagueMatchOperationsAction, input: LeagueMatchOperationsJson) {
  if (action === "squad.create" || action === "attendance.close") return entryPayload(action, input);
  if (action === "squad.member.add") {
    assertOnlyKeys(input, ["isCaptain", "memberRole", "positionOrder", "reason", "rosterMemberId", "shirtNumber", "squadId"]);
    const memberRole = text(input, "memberRole", 20).toUpperCase();
    if (!new Set(["STARTER", "SUBSTITUTE"]).has(memberRole)) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    if (input.isCaptain != null && typeof input.isCaptain !== "boolean") throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    return {
      isCaptain: input.isCaptain === true,
      memberRole,
      positionOrder: integer(input, "positionOrder", 0, 99, true) ?? 0,
      reason: reason(input, action),
      rosterMemberId: uuid(input, "rosterMemberId"),
      shirtNumber: integer(input, "shirtNumber", 1, 99, true),
      squadId: uuid(input, "squadId"),
    };
  }
  if (action === "squad.member.remove") {
    assertOnlyKeys(input, ["reason", "rosterMemberId", "squadId"]);
    return { reason: reason(input, action), rosterMemberId: uuid(input, "rosterMemberId"), squadId: uuid(input, "squadId") };
  }
  if (["squad.submit", "squad.validate", "squad.reject", "squad.lock"].includes(action)) {
    assertOnlyKeys(input, ["reason", "squadId"]);
    const parsedReason = reason(input, action);
    if (action === "squad.reject" && parsedReason === action) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    return { reason: parsedReason, squadId: uuid(input, "squadId") };
  }
  if (action === "attendance.set") {
    assertOnlyKeys(input, ["entryId", "reason", "rosterMemberId", "status"]);
    const status = text(input, "status", 20);
    if (!new Set(["going", "not_going", "pending"]).has(status)) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    return { entryId: uuid(input, "entryId"), reason: reason(input, action), rosterMemberId: uuid(input, "rosterMemberId"), status };
  }
  if (["match.mark_ready", "match.start", "match.mark_played", "round.complete", "round.lock"].includes(action)) {
    assertOnlyKeys(input, ["reason"]);
    return { reason: reason(input, action) };
  }
  if (action === "sporting_result.submit" || action === "sporting_result.propose_change") {
    return resultPayload(action, input);
  }
  if (action === "sporting_result.accept") {
    assertOnlyKeys(input, ["entryId", "reason", "scorers"]);
    const parsedScorers = scorers(input);
    return { entryId: uuid(input, "entryId"), reason: reason(input, action), ...(parsedScorers === undefined ? {} : { scorers: parsedScorers }) };
  }
  if (action === "sporting_result.dispute") return resultPayload(action, input, true);
  if (["official_result.publish", "official_result.supersede", "official_result.annul"].includes(action)) {
    assertOnlyKeys(input, ["outcome", "pointsAdjustments", "privateEvidence", "publicExplanation", "reasonCode", "scoreAway", "scoreHome"]);
    if (input.pointsAdjustments != null && (!Array.isArray(input.pointsAdjustments) || input.pointsAdjustments.length > 0)) {
      throw new Error("FEATURE_NOT_AVAILABLE");
    }
    const privateEvidence = leagueMatchRecord(input.privateEvidence);
    assertOnlyKeys(privateEvidence, ["evidenceReference", "privateReason"]);
    return {
      outcome: action === "official_result.annul" ? "ANNULLED" : text(input, "outcome", 60) || (action === "official_result.publish" ? "MIRROR_SPORTING_RESULT" : "CORRECTED_EFFECTIVE_SCORE"),
      pointsAdjustments: [],
      privateEvidence: {
        evidenceReference: text(privateEvidence, "evidenceReference", 500),
        privateReason: text(privateEvidence, "privateReason", 1200),
      },
      publicExplanation: text(input, "publicExplanation", 600),
      reasonCode: text(input, "reasonCode", 120) || action,
      scoreAway: integer(input, "scoreAway", 0, 99, true),
      scoreHome: integer(input, "scoreHome", 0, 99, true),
    };
  }
  if (action === "standings.rebuild") {
    assertOnlyKeys(input, ["reason", "rebuildKind"]);
    const rebuildKind = text(input, "rebuildKind", 30).toUpperCase() || "FULL_AUDIT";
    if (!new Set(["FULL_AUDIT", "INCREMENTAL"]).has(rebuildKind)) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    return { reason: reason(input, action), rebuildKind };
  }
  if (action === "standings.draw_lot.confirm") {
    assertOnlyKeys(input, ["candidateEntryIds", "reason", "seed", "tieGroupKey"]);
    const candidates = Array.isArray(input.candidateEntryIds) ? input.candidateEntryIds : [];
    if (candidates.length < 2 || candidates.length > 32 || candidates.some((value) => typeof value !== "string" || !leagueMatchUuidPattern.test(value))) {
      throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    }
    const tieGroupKey = text(input, "tieGroupKey", 64);
    const seed = text(input, "seed", 160);
    if (!checksumPattern.test(tieGroupKey) || !seed) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
    return { candidateEntryIds: [...new Set(candidates)].sort(), reason: reason(input, action), seed, tieGroupKey };
  }
  throw new Error("FEATURE_NOT_AVAILABLE");
}

export function leagueMatchClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export async function leagueMatchSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: userResult.data.user };
}

export function leagueMatchPublicClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !key) throw new Error("LEAGUE_MATCH_OPERATIONS_INTEGRATION_NOT_CONFIGURED");
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

export function requireLeagueMatchOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("LEAGUE_MATCH_OPERATIONS_ORIGIN_REQUIRED");
}

export function leagueMatchWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function parseLeagueMatchAction(value: unknown) {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isLeagueMatchOperationsAction(action)) throw new Error("INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND");
  return action;
}

export function leagueMatchError(error: unknown) {
  const detail = error instanceof Error ? error.message : "LEAGUE_MATCH_OPERATIONS_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|DUPLICATE|ALREADY|LOCKED|NOT_EDITABLE/i.test(detail) ? 409
      : /FORBIDDEN|DENIED|REQUIRED|42501|DISABLED|NOT_AUTHORIZED/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /FEATURE_NOT_AVAILABLE|0A000|POLICY_VIOLATION|TIE_REQUIRES/i.test(detail) ? 422
              : 400;
  return leagueMatchJson({ error: "LEAGUE_MATCH_OPERATIONS_REQUEST_REJECTED", message: detail }, status);
}
