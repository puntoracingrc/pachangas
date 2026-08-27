import { platformUserClient } from "../../admin/_lib/platform-auth";
import {
  isTournamentDrawAction,
  tournamentRecord,
  type TournamentDrawAction,
  type TournamentJson,
} from "../../tournament-draw-contract";
import {
  isTournamentGroupStageAction,
  type TournamentGroupStageAction,
} from "../../tournament-group-stage-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../client-policy/_contract";

export { tournamentRecord };

export const tournamentUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const serverFields = new Set([
  "actorId", "actor_id", "algorithmVersion", "confirmedAt", "confirmedRevision",
  "inputChecksum", "placements", "publishedAt", "quality", "result",
  "resultChecksum", "seedResult", "serverSequence",
]);

const actionKeys: Record<TournamentDrawAction, readonly string[]> = {
  "tournament.create": ["organizerKind", "name", "slug", "description", "generalArea", "modality", "editionName", "seasonLabel", "startsAt", "endsAt", "participantCap", "groupCount", "qualifiersPerGroup", "drawTarget", "drawMode", "registrationClosesAt", "authoringMode", "sourcePresetKey", "discipline", "referees", "reason"],
  "tournament.authoring.save": ["name", "slug", "description", "generalArea", "modality", "editionName", "seasonLabel", "startsAt", "endsAt", "participantCap", "groupCount", "qualifiersPerGroup", "drawTarget", "drawMode", "registrationClosesAt", "authoringMode", "sourcePresetKey", "discipline", "referees", "reason"],
  "tournament.cancel": ["reason"],
  "participant.invite": ["teamId", "reason"],
  "participant.accept": ["entryId", "reason"],
  "participant.decline": ["entryId", "reason"],
  "participant.withdraw": ["entryId", "reason"],
  "draw_plan.create": ["editionId", "stageId", "ruleRevisionId", "targetType", "mode", "groupCount", "slotCount", "qualifiersPerGroup", "reason"],
  "participants.freeze": ["planId", "reason"],
  "participants.unfreeze": ["planId", "reason"],
  "draw_pot.create": ["planId", "potNumber", "label", "capacity", "entryIds", "seedingPolicy", "reason"],
  "draw_pot.update": ["planId", "potId", "label", "capacity", "entryIds", "seedingPolicy", "reason"],
  "draw_constraint.create": ["planId", "constraintType", "strength", "weight", "scope", "parameters", "reason", "publicAttribution"],
  "draw_constraint.update": ["planId", "constraintId", "strength", "weight", "scope", "parameters", "reason", "publicAttribution"],
  "draw_constraint.remove": ["planId", "constraintId", "reason"],
  "draw.generate": ["planId", "seedMode", "publicSeed", "reason"],
  "draw.regenerate": ["planId", "seedMode", "publicSeed", "reason"],
  "draw.entry.place": ["planId", "entryId", "groupNumber", "slotNumber", "seedNumber", "reason"],
  "draw.entry.move": ["planId", "entryId", "groupNumber", "slotNumber", "seedNumber", "reason"],
  "draw.entry.swap": ["planId", "entryId", "otherEntryId", "reason"],
  "draw.entry.remove": ["planId", "entryId", "reason"],
  "draw.lock.create": ["planId", "lockType", "entryId", "relatedEntryId", "groupNumber", "slotNumber", "half", "potNumber", "reason"],
  "draw.lock.remove": ["planId", "lockId", "reason"],
  "draw.validate": ["planId", "reason"],
  "draw.publish": ["planId", "reason"],
  "draw.cancel": ["planId", "reason"],
};

const uuidKeys = new Set([
  "constraintId", "editionId", "entryId", "lockId", "otherEntryId", "planId",
  "potId", "relatedEntryId", "ruleRevisionId", "stageId", "teamId",
]);

const integerBounds: Record<string, readonly [number, number]> = {
  capacity: [1, 64],
  groupCount: [1, 16],
  groupNumber: [1, 64],
  half: [1, 2],
  participantCap: [4, 64],
  potNumber: [1, 64],
  qualifiersPerGroup: [1, 16],
  seedNumber: [1, 128],
  slotCount: [1, 128],
  slotNumber: [1, 128],
  weight: [0, 1000],
};

function validateNested(value: unknown, depth = 0): unknown {
  if (depth > 5) throw new Error("INVALID_TOURNAMENT_COMMAND");
  if (value == null || typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("INVALID_TOURNAMENT_COMMAND");
    return value;
  }
  if (typeof value === "string") {
    if (value.length > 2400) throw new Error("INVALID_TOURNAMENT_COMMAND");
    return value.trim();
  }
  if (Array.isArray(value)) {
    if (value.length > 64) throw new Error("INVALID_TOURNAMENT_COMMAND");
    return value.map((item) => validateNested(item, depth + 1));
  }
  const record = tournamentRecord(value);
  if (Object.keys(record).length > 40) throw new Error("INVALID_TOURNAMENT_COMMAND");
  if (Object.keys(record).some((key) => serverFields.has(key))) {
    throw new Error("TOURNAMENT_SERVER_FIELDS_FORBIDDEN");
  }
  return Object.fromEntries(Object.entries(record).map(([key, item]) => [key, validateNested(item, depth + 1)]));
}

export function tournamentCommandPayload(action: TournamentDrawAction, raw: TournamentJson) {
  const allowed = new Set(actionKeys[action]);
  if (Object.keys(raw).some((key) => !allowed.has(key) || serverFields.has(key))) {
    throw new Error("TOURNAMENT_PAYLOAD_FIELD_NOT_ALLOWED");
  }
  const payload = validateNested(raw) as TournamentJson;
  for (const [key, value] of Object.entries(payload)) {
    if (uuidKeys.has(key) && value !== "" && (!value || !tournamentUuidPattern.test(String(value)))) {
      throw new Error("INVALID_TOURNAMENT_COMMAND");
    }
    const bounds = integerBounds[key];
    if (bounds && value != null && value !== "") {
      const parsed = Number(value);
      if (!Number.isInteger(parsed) || parsed < bounds[0] || parsed > bounds[1]) {
        throw new Error("INVALID_TOURNAMENT_COMMAND");
      }
      payload[key] = parsed;
    }
  }
  if (payload.entryIds != null) {
    if (!Array.isArray(payload.entryIds)
        || payload.entryIds.some((entryId) => !tournamentUuidPattern.test(String(entryId)))) {
      throw new Error("INVALID_TOURNAMENT_COMMAND");
    }
  }
  if (JSON.stringify(payload).length > 30_000) throw new Error("TOURNAMENT_PAYLOAD_TOO_LARGE");
  return payload;
}

export function tournamentJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

export async function tournamentSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const result = await client.auth.getUser(token);
  if (result.error || !result.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, user: result.data.user };
}

export function requireTournamentOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("TOURNAMENT_ORIGIN_REQUIRED");
}

export function tournamentWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function parseTournamentAction(value: unknown) {
  if (!isTournamentDrawAction(value)) throw new Error("INVALID_TOURNAMENT_COMMAND");
  return value;
}

export function parseTournamentGroupStageAction(value: unknown) {
  if (!isTournamentGroupStageAction(value)) throw new Error("INVALID_TOURNAMENT_GROUP_STAGE_COMMAND");
  return value;
}

export function tournamentGroupStageCommandPayload(action: TournamentGroupStageAction, raw: TournamentJson) {
  const allowed = action === "group_schedule.create"
    ? new Set(["groupId", "reason", "slots"])
    : new Set(["reason"]);
  if (Object.keys(raw).some((key) => !allowed.has(key) || serverFields.has(key))) {
    throw new Error("TOURNAMENT_GROUP_STAGE_PAYLOAD_FIELD_NOT_ALLOWED");
  }
  const payload = validateNested(raw) as TournamentJson;
  if (action !== "group_schedule.create") {
    if (payload.reason != null && (typeof payload.reason !== "string" || String(payload.reason).length > 1100)) {
      throw new Error("INVALID_TOURNAMENT_GROUP_STAGE_COMMAND");
    }
    return payload;
  }
  if (!tournamentUuidPattern.test(String(payload.groupId ?? "")) || !Array.isArray(payload.slots)
      || payload.slots.length < 1 || payload.slots.length > 1000) {
    throw new Error("INVALID_TOURNAMENT_GROUP_STAGE_COMMAND");
  }
  payload.slots = payload.slots.map((value) => {
    const slot = tournamentRecord(value);
    const slotKeys = new Set(["endsAt", "startsAt", "timezone", "venueId", "venueLabel"]);
    if (Object.keys(slot).some((key) => !slotKeys.has(key) || serverFields.has(key))) {
      throw new Error("TOURNAMENT_GROUP_SLOT_FIELD_NOT_ALLOWED");
    }
    const startsAt = typeof slot.startsAt === "string" ? slot.startsAt : "";
    const endsAt = typeof slot.endsAt === "string" ? slot.endsAt : "";
    const timezone = typeof slot.timezone === "string" ? slot.timezone.trim() : "";
    const venueId = typeof slot.venueId === "string" ? slot.venueId : "";
    const venueLabel = typeof slot.venueLabel === "string" ? slot.venueLabel.trim() : "";
    if (!Number.isFinite(Date.parse(startsAt)) || !Number.isFinite(Date.parse(endsAt))
        || Date.parse(endsAt) <= Date.parse(startsAt) || !timezone || timezone.length > 80
        || (venueId && !tournamentUuidPattern.test(venueId)) || venueLabel.length > 160) {
      throw new Error("INVALID_TOURNAMENT_GROUP_STAGE_COMMAND");
    }
    return {
      endsAt,
      startsAt,
      timezone,
      ...(venueId ? { venueId } : {}),
      ...(venueLabel ? { venueLabel } : {}),
    };
  });
  if (JSON.stringify(payload).length > 200_000) throw new Error("TOURNAMENT_PAYLOAD_TOO_LARGE");
  return payload;
}

export function tournamentClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export function tournamentError(error: unknown) {
  const detail = error instanceof Error ? error.message : "TOURNAMENT_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|DUPLICATE|ALREADY/i.test(detail) ? 409
      : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /UNSATISFIABLE|PT422|NOT_AVAILABLE|0A000/i.test(detail) ? 422
              : 400;
  return tournamentJson({ error: "TOURNAMENT_REQUEST_REJECTED", message: detail }, status);
}
