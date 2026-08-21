import { createClient } from "@supabase/supabase-js";
import { clientWriteGateResponse, noStoreHeaders } from "../client-policy/_contract";
import { platformUserClient } from "../../admin/_lib/platform-auth";
import { refereeAvailabilityStatuses, refereeModalities } from "../../referee-platform-contract";

export const refereeUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const slugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function refereeJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

export function refereeRecord(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function string(input: Record<string, unknown>, key: string, maximum = 1200) {
  const value = typeof input[key] === "string" ? input[key].trim() : "";
  if (value.length > maximum) throw new Error("INVALID_REFEREE_COMMAND");
  return value;
}

function uuid(input: Record<string, unknown>, key: string, optional = false) {
  const value = string(input, key, 40);
  if (optional && !value) return "";
  if (!refereeUuidPattern.test(value)) throw new Error("INVALID_REFEREE_COMMAND");
  return value;
}

function timestamp(input: Record<string, unknown>, key: string) {
  const value = string(input, key, 50);
  if (!value) return "";
  if (Number.isNaN(Date.parse(value))) throw new Error("INVALID_REFEREE_COMMAND");
  return new Date(value).toISOString();
}

function integer(value: unknown, minimum: number, maximum: number, optional = false) {
  if (optional && (value === "" || value == null)) return "";
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) throw new Error("INVALID_REFEREE_COMMAND");
  return parsed;
}

function boolean(input: Record<string, unknown>, key: string, fallback = false) {
  return typeof input[key] === "boolean" ? input[key] : fallback;
}

function slug(input: Record<string, unknown>) {
  const value = string(input, "slug", 80).toLowerCase();
  if (!slugPattern.test(value)) throw new Error("INVALID_REFEREE_COMMAND");
  return value;
}

function reason(input: Record<string, unknown>, fallback: string) {
  return string(input, "reason", 1200) || fallback;
}

function profilePayload(action: string, input: Record<string, unknown>) {
  const output: Record<string, unknown> = { reason: reason(input, action) };
  if (action === "profile.create" || "slug" in input) output.slug = slug(input);
  if (action === "profile.create" || "bio" in input) output.bio = string(input, "bio", 1200);
  if (action === "profile.create" || "experienceSummary" in input) output.experienceSummary = string(input, "experienceSummary", 1200);
  if (action === "profile.create" || "experienceSinceYear" in input) {
    output.experienceSinceYear = integer(input.experienceSinceYear, 1950, new Date().getUTCFullYear(), true);
  }
  if (action === "profile.create" || "availabilityStatus" in input) {
    const status = string(input, "availabilityStatus", 24).toUpperCase();
    if (!(refereeAvailabilityStatuses as readonly string[]).includes(status)) throw new Error("INVALID_REFEREE_COMMAND");
    output.availabilityStatus = status;
  }
  if (action === "profile.update") {
    if ("visibility" in input) {
      const visibility = string(input, "visibility", 20).toLowerCase();
      if (!new Set(["private", "unlisted", "public"]).has(visibility)) throw new Error("INVALID_REFEREE_COMMAND");
      output.visibility = visibility;
    }
    if ("availableForAssignments" in input) output.availableForAssignments = boolean(input, "availableForAssignments");
    if ("shareRecurringAvailability" in input) output.shareRecurringAvailability = boolean(input, "shareRecurringAvailability");
  }
  return output;
}

function modalitiesPayload(input: Record<string, unknown>) {
  if (!Array.isArray(input.modalities) || input.modalities.length > 10) throw new Error("INVALID_REFEREE_COMMAND");
  const modalities = input.modalities.map((value) => {
    const item = refereeRecord(value);
    const modality = string(item, "modality", 30).toUpperCase();
    if (!(refereeModalities as readonly string[]).includes(modality)) throw new Error("INVALID_REFEREE_COMMAND");
    return {
      experienceSinceYear: integer(item.experienceSinceYear, 1950, new Date().getUTCFullYear(), true),
      modality,
      note: string(item, "note", 240),
    };
  });
  if (new Set(modalities.map((item) => item.modality)).size !== modalities.length) throw new Error("INVALID_REFEREE_COMMAND");
  return { modalities, reason: reason(input, "profile_modalities_replace") };
}

function areasPayload(input: Record<string, unknown>) {
  if (!Array.isArray(input.areas) || input.areas.length > 20) throw new Error("INVALID_REFEREE_COMMAND");
  return {
    areas: input.areas.map((value) => {
      const item = refereeRecord(value);
      const generalArea = string(item, "generalArea", 160);
      if (generalArea.length < 2) throw new Error("INVALID_REFEREE_COMMAND");
      return {
        countryCode: string(item, "countryCode", 2).toUpperCase() || "ES",
        generalArea,
        municipality: string(item, "municipality", 120),
        province: string(item, "province", 120),
        travelRadiusKm: integer(item.travelRadiusKm, 0, 500, true),
      };
    }),
    reason: reason(input, "profile_areas_replace"),
  };
}

function availabilityPayload(input: Record<string, unknown>) {
  const windows = Array.isArray(input.windows) ? input.windows : [];
  const exceptions = Array.isArray(input.exceptions) ? input.exceptions : [];
  if (windows.length > 40 || exceptions.length > 40) throw new Error("INVALID_REFEREE_COMMAND");
  return {
    exceptions: exceptions.map((value) => {
      const item = refereeRecord(value);
      return {
        reason: string(item, "reason", 500),
        unavailableFrom: timestamp(item, "unavailableFrom"),
        unavailableUntil: timestamp(item, "unavailableUntil"),
      };
    }),
    reason: reason(input, "profile_availability_replace"),
    windows: windows.map((value) => {
      const item = refereeRecord(value);
      const timePattern = /^([01]\d|2[0-3]):[0-5]\d$/;
      const startLocalTime = string(item, "startLocalTime", 5);
      const endLocalTime = string(item, "endLocalTime", 5);
      const timezone = string(item, "timezone", 100);
      if (!timePattern.test(startLocalTime) || !timePattern.test(endLocalTime) || !timezone) throw new Error("INVALID_REFEREE_COMMAND");
      return {
        endLocalTime,
        publicVisible: boolean(item, "publicVisible"),
        startLocalTime,
        timezone,
        weekday: integer(item.weekday, 1, 7),
      };
    }),
  };
}

export function refereeCommandPayload(action: string, input: Record<string, unknown>) {
  if (action === "profile.create" || action === "profile.update") return profilePayload(action, input);
  if (action === "profile.modalities.replace") return modalitiesPayload(input);
  if (action === "profile.areas.replace") return areasPayload(input);
  if (action === "profile.availability.replace") return availabilityPayload(input);
  if (new Set(["profile.activate", "profile.archive", "marketplace.list", "marketplace.pause", "marketplace.unlist"]).has(action)) {
    return { reason: reason(input, action) };
  }
  if (action === "relationship.invite") {
    const targetKind = string(input, "targetKind", 30);
    if (!new Set(["registered_user", "email_target"]).has(targetKind)) throw new Error("INVALID_REFEREE_COMMAND");
    return {
      clubId: uuid(input, "clubId"),
      expiresAt: timestamp(input, "expiresAt"),
      reason: reason(input, action),
      relationshipType: string(input, "relationshipType", 30).toUpperCase() || "REGULAR",
      targetEmail: targetKind === "email_target" ? string(input, "targetEmail", 320).toLowerCase() : "",
      targetKind,
      targetUserId: targetKind === "registered_user" ? uuid(input, "targetUserId") : "",
    };
  }
  if (action === "relationship.request") return {
    clubId: uuid(input, "clubId"), reason: reason(input, action),
    relationshipType: string(input, "relationshipType", 30).toUpperCase() || "REGULAR",
  };
  if (action === "relationship.accept" || action === "relationship.reject") {
    const token = string(input, "token", 64);
    if (token && !/^[0-9a-f]{64}$/i.test(token)) throw new Error("INVALID_REFEREE_COMMAND");
    return { reason: reason(input, action), token };
  }
  if (new Set(["relationship.cancel", "relationship.end"]).has(action)) return { reason: reason(input, action) };
  if (action === "relationship.visibility.set") {
    const side = string(input, "side", 20).toLowerCase();
    if (!new Set(["club", "referee"]).has(side)) throw new Error("INVALID_REFEREE_COMMAND");
    return { reason: reason(input, action), side, visible: boolean(input, "visible") };
  }
  if (action === "assignment.propose") return {
    assignmentRole: "MAIN_REFEREE",
    message: string(input, "message", 800),
    reason: reason(input, action),
    refereeProfileId: uuid(input, "refereeProfileId"),
    requesterId: uuid(input, "requesterId"),
    requesterKind: string(input, "requesterKind", 10).toUpperCase(),
    responseDeadline: timestamp(input, "responseDeadline"),
    sourceGroupId: uuid(input, "sourceGroupId", true),
    sourceId: string(input, "sourceId", 180),
    sourceKind: string(input, "sourceKind", 40),
  };
  if (new Set(["assignment.accept", "assignment.decline", "assignment.confirm"]).has(action)) return { reason: reason(input, action) };
  if (action === "assignment.cancel") return {
    reason: reason(input, action), reasonCode: string(input, "reasonCode", 80), reasonText: string(input, "reasonText", 800),
  };
  if (action === "assignment.replace") return {
    message: string(input, "message", 800), newAssignmentId: uuid(input, "newAssignmentId"),
    newRefereeProfileId: uuid(input, "newRefereeProfileId"), reason: reason(input, action),
    responseDeadline: timestamp(input, "responseDeadline"),
  };
  throw new Error("INVALID_REFEREE_COMMAND");
}

export function refereeClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
    writeId: request.headers.get("x-pachangas-write-id"),
  };
}

export async function refereeSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: userResult.data.user };
}

export function anonymousRefereeClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !key) throw new Error("REFEREE_INTEGRATION_NOT_CONFIGURED");
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

export function requireRefereeOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("REFEREE_ORIGIN_REQUIRED");
}

export function refereeWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function refereeError(error: unknown) {
  const message = error instanceof Error ? error.message : "REFEREE_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(message) ? 401
    : /STALE_REVISION|PT409|CONFLICT|ALREADY|SCHEDULE_CHANGED|SLOT_TAKEN/i.test(message) ? 409
      : /REQUIRED|FORBIDDEN|42501|NOT_AUTHORIZED|NOT_ALLOWED/i.test(message) ? 403
        : /NOT_FOUND|P0002/i.test(message) ? 404
          : /RATE_LIMIT|PT429/i.test(message) ? 429
            : 400;
  const safeMessage = /REFEREE_INTEGRATION_NOT_CONFIGURED/.test(message)
    ? "La plataforma arbitral no está configurada en este entorno."
    : message;
  return refereeJson({ error: "REFEREE_REQUEST_REJECTED", message: safeMessage }, status);
}
