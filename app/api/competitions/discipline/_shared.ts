import { createClient } from "@supabase/supabase-js";
import { platformUserClient } from "../../../admin/_lib/platform-auth";
import {
  disciplineRecord,
  isCompetitionDisciplineAction,
  type CompetitionDisciplineAction,
  type CompetitionDisciplineJson,
} from "../../../competition-discipline-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export { disciplineRecord };

export const disciplineUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const actionKeys: Record<CompetitionDisciplineAction, readonly string[]> = {
  "appeal.submit": ["statement"],
  "appeal.transition": ["modifiedUnits", "privateReason", "publicResolution", "status"],
  "appeal.withdraw": [],
  "counter.rebuild": ["playerProfileId"],
  "cycle.reset": ["effectiveFrom"],
  "event.annul": ["correctionReason", "evidenceRefs", "privateNotes"],
  "event.correct": ["cardTypeCode", "context", "correctionReason", "evidenceRefs", "minute", "period", "playerProfileId", "privateNotes", "publicReasonCategory", "publicSummary"],
  "event.record": ["cardTypeCode", "context", "evidenceRefs", "minute", "period", "playerProfileId", "privateNotes", "publicReasonCategory", "publicSummary"],
  "sanction.decide": ["decisionOutcome", "evidenceRefs", "privateReason", "publicReasonCategory", "publicSummary", "ruleArticle", "units"],
  "service.record": [],
  "service.reverse": ["privateReason", "serviceEventId"],
};

const uuidKeys = new Set(["canonicalMatchId", "playerProfileId", "serviceEventId"]);
const shortTextKeys = new Set(["cardTypeCode", "context", "decisionOutcome", "period", "publicReasonCategory", "ruleArticle", "status"]);
const longTextKeys = new Map([
  ["correctionReason", 1200],
  ["privateNotes", 4000],
  ["privateReason", 4000],
  ["publicResolution", 1000],
  ["publicSummary", 500],
  ["statement", 4000],
]);

export function disciplineJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function cleanText(value: unknown, maximum: number) {
  if (value == null || value === "") return "";
  if (typeof value !== "string") throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
  const clean = value.trim();
  if (clean.length > maximum) throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
  return clean;
}

function cleanEvidence(value: unknown) {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > 20) throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
  const refs = value.map((item) => cleanText(item, 500)).filter(Boolean);
  if (new TextEncoder().encode(JSON.stringify(refs)).length > 16_000) {
    throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
  }
  return refs;
}

export function disciplineCommandPayload(action: CompetitionDisciplineAction, input: CompetitionDisciplineJson) {
  const allowed = new Set(actionKeys[action]);
  if (Object.keys(input).some((key) => !allowed.has(key))) {
    throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
  }
  const output: CompetitionDisciplineJson = {};
  for (const [key, value] of Object.entries(input)) {
    if (key === "evidenceRefs") {
      output[key] = cleanEvidence(value);
    } else if (uuidKeys.has(key)) {
      const parsed = cleanText(value, 40);
      if (parsed && !disciplineUuidPattern.test(parsed)) throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
      if (parsed) output[key] = parsed;
    } else if (key === "minute") {
      if (value == null || value === "") continue;
      const parsed = Number(value);
      if (!Number.isInteger(parsed) || parsed < 0 || parsed > 300) throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
      output[key] = parsed;
    } else if (key === "modifiedUnits" || key === "units") {
      if (value == null || value === "") continue;
      const parsed = Number(value);
      if (!Number.isInteger(parsed) || parsed < 0 || parsed > 999) throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
      output[key] = parsed;
    } else if (key === "effectiveFrom") {
      const parsed = cleanText(value, 60);
      if (parsed && Number.isNaN(Date.parse(parsed))) throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
      if (parsed) output[key] = new Date(parsed).toISOString();
    } else if (shortTextKeys.has(key)) {
      const parsed = cleanText(value, key === "ruleArticle" ? 160 : 80);
      if (parsed) output[key] = parsed;
    } else if (longTextKeys.has(key)) {
      output[key] = cleanText(value, longTextKeys.get(key) ?? 4000);
    }
  }
  return output;
}

export function disciplineClientMetadata(request: Request, surface: string) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface,
  };
}

export async function disciplineSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, token, user: userResult.data.user };
}

export function disciplinePublicClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim();
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || !key) throw new Error("COMPETITION_DISCIPLINE_INTEGRATION_NOT_CONFIGURED");
  return createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
}

export function requireDisciplineOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("COMPETITION_DISCIPLINE_ORIGIN_REQUIRED");
}

export function disciplineWriteGate(request: Request) {
  return clientWriteGateResponse(request);
}

export function parseDisciplineAction(value: unknown) {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isCompetitionDisciplineAction(action)) throw new Error("INVALID_COMPETITION_DISCIPLINE_COMMAND");
  return action;
}

export function disciplineError(error: unknown) {
  const detail = error instanceof Error ? error.message : "COMPETITION_DISCIPLINE_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|DUPLICATE|ALREADY|LOCKED|REVERSAL_REQUIRED/i.test(detail) ? 409
      : /FORBIDDEN|DENIED|REQUIRED|42501|DISABLED|NOT_AUTHORIZED/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /FEATURE_NOT_AVAILABLE|0A000|POLICY|OUTSIDE|INVALID|NOT_(APPEALABLE|SERVICEABLE|ELIGIBLE)/i.test(detail) ? 422
              : 400;
  return disciplineJson({ error: "COMPETITION_DISCIPLINE_REQUEST_REJECTED", message: detail }, status);
}
