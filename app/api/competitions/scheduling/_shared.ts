import { createClient } from "@supabase/supabase-js";
import { platformUserClient } from "../../../admin/_lib/platform-auth";
import {
  isLeagueSchedulingAction,
  scheduleRecord,
  type LeagueSchedulingAction,
  type LeagueSchedulingJson,
} from "../../../league-scheduling-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export { scheduleRecord };

export const scheduleUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const datePattern = /^\d{4}-\d{2}-\d{2}$/;
const localTimePattern = /^([01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/;

export function scheduleJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function assertOnlyKeys(input: LeagueSchedulingJson, keys: readonly string[]) {
  const allowed = new Set(keys);
  if (Object.keys(input).some((key) => !allowed.has(key))) {
    throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  }
}

function text(input: LeagueSchedulingJson, key: string, maximum = 1200) {
  const value = typeof input[key] === "string" ? input[key].trim() : "";
  if (value.length > maximum) throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  return value;
}

function requiredText(input: LeagueSchedulingJson, key: string, maximum = 1200) {
  const value = text(input, key, maximum);
  if (!value) throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  return value;
}

function uuid(input: LeagueSchedulingJson, key: string, optional = false) {
  const value = text(input, key, 40);
  if (optional && !value) return "";
  if (!scheduleUuidPattern.test(value)) throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  return value;
}

function integer(input: LeagueSchedulingJson, key: string, minimum: number, maximum: number) {
  const value = Number(input[key]);
  if (!Number.isInteger(value) || value < minimum || value > maximum) {
    throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  }
  return value;
}

function timestamp(input: LeagueSchedulingJson, key: string) {
  const value = requiredText(input, key, 50);
  if (Number.isNaN(Date.parse(value))) throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  return new Date(value).toISOString();
}

function date(input: LeagueSchedulingJson, key: string) {
  const value = requiredText(input, key, 10);
  if (!datePattern.test(value) || Number.isNaN(Date.parse(`${value}T00:00:00Z`))) {
    throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  }
  return value;
}

function common(input: LeagueSchedulingJson, action: string) {
  return {
    reason: text(input, "reason", 1200) || action,
    reasonCode: text(input, "reasonCode", 120) || action,
  };
}

function venue(input: LeagueSchedulingJson) {
  return {
    resourceKey: text(input, "resourceKey", 160),
    venueId: uuid(input, "venueId", true),
    venueLabel: text(input, "venueLabel", 160),
  };
}

const commonKeys = ["reason", "reasonCode"] as const;

export function scheduleCommandPayload(action: LeagueSchedulingAction, input: LeagueSchedulingJson) {
  if (action === "schedule_plan.create") {
    assertOnlyKeys(input, [...commonKeys, "categoryId", "divisionId", "groupId", "legs", "ruleRevisionId"]);
    return {
      ...common(input, action),
      categoryId: uuid(input, "categoryId"),
      divisionId: uuid(input, "divisionId", true),
      groupId: uuid(input, "groupId", true),
      legs: integer(input, "legs", 1, 2),
      ruleRevisionId: uuid(input, "ruleRevisionId"),
    };
  }
  if (action === "schedule_slot.create" || action === "schedule_slot.update") {
    assertOnlyKeys(input, [...commonKeys, "endsAt", "resourceKey", "slotId", "startsAt", "timezone", "venueId", "venueLabel"]);
    return {
      ...common(input, action),
      ...venue(input),
      endsAt: timestamp(input, "endsAt"),
      ...(action === "schedule_slot.update" ? { slotId: uuid(input, "slotId") } : {}),
      startsAt: timestamp(input, "startsAt"),
      timezone: requiredText(input, "timezone", 100),
    };
  }
  if (action === "schedule_slot.bulk_create") {
    assertOnlyKeys(input, [...commonKeys, "durationMinutes", "endDate", "localTime", "resourceKey", "startDate", "timezone", "venueId", "venueLabel", "weekdays"]);
    const weekdays = Array.isArray(input.weekdays) ? input.weekdays.map(Number) : [];
    if (weekdays.length < 1 || weekdays.length > 7 || new Set(weekdays).size !== weekdays.length
        || weekdays.some((value) => !Number.isInteger(value) || value < 1 || value > 7)) {
      throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
    }
    const localTime = requiredText(input, "localTime", 8);
    if (!localTimePattern.test(localTime)) throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
    return {
      ...common(input, action),
      ...venue(input),
      durationMinutes: integer(input, "durationMinutes", 1, 600),
      endDate: date(input, "endDate"),
      localTime,
      startDate: date(input, "startDate"),
      timezone: requiredText(input, "timezone", 100),
      weekdays: [...weekdays].sort((left, right) => left - right),
    };
  }
  if (action === "schedule_slot.retire") {
    assertOnlyKeys(input, [...commonKeys, "slotId"]);
    return { ...common(input, action), slotId: uuid(input, "slotId") };
  }
  if (action === "schedule.generate" || action === "schedule.regenerate") {
    assertOnlyKeys(input, [...commonKeys, "seed"]);
    return { ...common(input, action), seed: text(input, "seed", 160) };
  }
  if (action === "schedule_item.move_slot") {
    assertOnlyKeys(input, [...commonKeys, "itemId", "slotId"]);
    return { ...common(input, action), itemId: uuid(input, "itemId"), slotId: uuid(input, "slotId") };
  }
  if (action === "schedule_item.swap_slot") {
    assertOnlyKeys(input, [...commonKeys, "itemId", "otherItemId"]);
    return { ...common(input, action), itemId: uuid(input, "itemId"), otherItemId: uuid(input, "otherItemId") };
  }
  if (action === "schedule_item.swap_home_away") {
    assertOnlyKeys(input, [...commonKeys, "itemId"]);
    return { ...common(input, action), itemId: uuid(input, "itemId") };
  }
  if (action === "round.rename") {
    assertOnlyKeys(input, [...commonKeys, "displayName", "roundId"]);
    return {
      ...common(input, action),
      displayName: requiredText(input, "displayName", 120),
      roundId: uuid(input, "roundId"),
    };
  }
  if (["schedule.validate", "schedule.publish", "schedule.cancel"].includes(action)) {
    assertOnlyKeys(input, commonKeys);
    return common(input, action);
  }
  throw new Error("FEATURE_NOT_AVAILABLE");
}

export function scheduleClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export async function scheduleSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: userResult.data.user };
}

export function schedulePublicClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !key) throw new Error("LEAGUE_SCHEDULING_INTEGRATION_NOT_CONFIGURED");
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

export function requireScheduleOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("LEAGUE_SCHEDULING_ORIGIN_REQUIRED");
}

export function scheduleWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function parseScheduleAction(value: unknown) {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isLeagueSchedulingAction(action)) throw new Error("INVALID_LEAGUE_SCHEDULING_COMMAND");
  return action;
}

export function scheduleError(error: unknown) {
  const detail = error instanceof Error ? error.message : "LEAGUE_SCHEDULING_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|DUPLICATE|ALREADY|UNSATISFIABLE/i.test(detail) ? 409
      : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /FEATURE_NOT_AVAILABLE|0A000|CAPACITY_EXCEEDED/i.test(detail) ? 422
              : 400;
  return scheduleJson({ error: "LEAGUE_SCHEDULING_REQUEST_REJECTED", message: detail }, status);
}
