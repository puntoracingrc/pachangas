import { platformUserClient } from "../../../admin/_lib/platform-auth";
import {
  isPublicCompetitionPublicationAction,
  isPublicCompetitionRegistrationAction,
  publicCompetitionRecord,
  type PublicCompetitionAction,
  type PublicCompetitionJson,
} from "../../../public-competition-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export const publicCompetitionUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const publicCompetitionSlugPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function publicCompetitionJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

export function publicCompetitionCacheJson(data: unknown, status = 200, maxAge = 60) {
  return Response.json(data, {
    headers: {
      "Cache-Control": `public, max-age=${Math.min(maxAge, 300)}, stale-while-revalidate=300`,
      "CDN-Cache-Control": `public, s-maxage=${Math.min(maxAge, 300)}, stale-while-revalidate=600`,
      "Vary": "Accept-Encoding",
    },
    status,
  });
}

function boundedText(value: unknown, maximum: number, required = false) {
  if (value == null) return "";
  if (typeof value !== "string") throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  const normalized = value.trim();
  if (normalized.length > maximum || (required && normalized.length < 3)) {
    throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  }
  return normalized;
}

function uuid(value: unknown, required = true) {
  const normalized = boundedText(value, 36);
  if ((required || normalized) && !publicCompetitionUuidPattern.test(normalized)) {
    throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  }
  return normalized;
}

function timestamp(value: unknown) {
  const normalized = boundedText(value, 40);
  if (normalized && Number.isNaN(Date.parse(normalized))) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  return normalized ? new Date(normalized).toISOString() : "";
}

function reason(input: PublicCompetitionJson, fallback: string) {
  return boundedText(input.reason, 120) || fallback;
}

function publicationProfile(value: unknown) {
  const source = publicCompetitionRecord(value);
  const result: PublicCompetitionJson = {};
  const limits: Record<string, number> = {
    badge: 16,
    description: 2400,
    format: 120,
    generalArea: 160,
    imageUrl: 2048,
    municipality: 120,
    name: 120,
    publicVenue: 240,
    rulesSummary: 1000,
  };
  if (Object.keys(source).some((key) => !(key in limits))) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  Object.entries(limits).forEach(([key, maximum]) => {
    if (key in source) result[key] = boundedText(source[key], maximum);
  });
  return result;
}

function publicationSections(value: unknown) {
  const source = publicCompetitionRecord(value);
  const allowed = ["teams", "calendar", "results", "standings", "bracket", "referees", "venueDetail", "discipline"];
  if (Object.keys(source).some((key) => !allowed.includes(key))) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  const result: PublicCompetitionJson = {};
  allowed.forEach((key) => { if (typeof source[key] === "boolean") result[key] = source[key]; });
  if (result.discipline === true) throw new Error("PUBLIC_COMPETITION_DISCIPLINE_DISABLED");
  return result;
}

export function parsePublicCompetitionAction(value: unknown): PublicCompetitionAction {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isPublicCompetitionPublicationAction(action) && !isPublicCompetitionRegistrationAction(action)) {
    throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  }
  return action;
}

export function publicCompetitionCommandPayload(action: PublicCompetitionAction, input: PublicCompetitionJson) {
  if (action === "publication.prepare" || action === "publication.update") {
    const visibility = boundedText(input.visibility, 16).toLowerCase();
    const slug = boundedText(input.slug, 80);
    if (visibility && !["private", "unlisted", "public"].includes(visibility)) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
    if (slug && !publicCompetitionSlugPattern.test(slug)) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
    const payload: PublicCompetitionJson = { reason: reason(input, action) };
    if (action === "publication.prepare" || input.editionId != null) payload.editionId = uuid(input.editionId);
    if (action === "publication.prepare" || input.categoryId != null) payload.categoryId = uuid(input.categoryId);
    if (action === "publication.prepare" || slug) payload.slug = slug;
    if (action === "publication.prepare" || visibility) payload.visibility = visibility;
    if (input.publicProfile != null) payload.publicProfile = publicationProfile(input.publicProfile);
    if (input.publicSections != null) payload.publicSections = publicationSections(input.publicSections);
    return payload;
  }
  if (action === "publication.consent") {
    const statements = publicCompetitionRecord(input.statements);
    const keys = ["authorizedRepresentative", "informationAccurate", "teamAssetsAuthorized", "indexingAccepted"];
    if (Object.keys(statements).some((key) => !keys.includes(key))) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
    return {
      purpose: boundedText(input.purpose, 500),
      reason: reason(input, action),
      statements: Object.fromEntries(keys.map((key) => [key, statements[key] === true])),
    };
  }
  if (["publication.submit", "publication.withdraw", "publication.unpublish"].includes(action)) {
    return { reason: reason(input, action) };
  }
  if (action === "registration.configure") {
    const mode = boundedText(input.mode, 24).toUpperCase();
    if (!["INVITE_ONLY", "REQUEST_APPROVAL", "CLOSED"].includes(mode)) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
    return { closesAt: timestamp(input.closesAt), mode, opensAt: timestamp(input.opensAt), reason: reason(input, action) };
  }
  if (action === "registration.submit") return {
    message: boundedText(input.message, 1000),
    reason: reason(input, action),
    teamId: uuid(input.teamId),
  };
  if (action === "registration.message.update") return {
    message: boundedText(input.message, 1000), reason: reason(input, action),
  };
  if (action === "registration.withdraw" || action === "registration.under_review") {
    return { reason: reason(input, action) };
  }
  if (action === "registration.waitlist" || action === "registration.accept" || action === "registration.reject") {
    return {
      privateReason: boundedText(input.privateReason, 1200),
      publicReason: boundedText(input.publicReason, 500, action === "registration.reject"),
      reason: reason(input, action),
    };
  }
  if (action === "waitlist.reorder") {
    const position = Number(input.position);
    if (!Number.isSafeInteger(position) || position < 1) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
    return { position, privateReason: boundedText(input.privateReason, 1200), reason: reason(input, action) };
  }
  const category = boundedText(input.category, 24).toUpperCase() || "OTHER";
  if (!["MISLEADING", "IMPERSONATION", "PRIVACY", "ABUSE", "OTHER"].includes(category)) throw new Error("INVALID_PUBLIC_COMPETITION_COMMAND");
  return { category, reason: reason(input, action), summary: boundedText(input.summary, 1000, true) };
}

export async function publicCompetitionSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, user: userResult.data.user };
}

export function requirePublicCompetitionOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("PUBLIC_COMPETITION_ORIGIN_REQUIRED");
}

export function publicCompetitionWriteGate(request: Request) { return clientWriteGateResponse(request); }

export function publicCompetitionClientMetadata(request: Request, surface = "public_competitions") {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export function publicCompetitionError(error: unknown) {
  const detail = error instanceof Error ? error.message : "PUBLIC_COMPETITION_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|ALREADY|CAPACITY|STATE_INVALID|NOT_CHANGED/i.test(detail) ? 409
      : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED|MANAGER|OWNER/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /NOT_AVAILABLE|0A000/i.test(detail) ? 422
              : 400;
  return publicCompetitionJson({ error: "PUBLIC_COMPETITION_REQUEST_REJECTED", message: detail }, status);
}
