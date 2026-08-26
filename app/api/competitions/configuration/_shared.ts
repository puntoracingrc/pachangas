import { platformUserClient } from "../../../admin/_lib/platform-auth";
import { leagueBetaCommandPayload, leagueBetaClientMetadata } from "../../../api/leagues/private-beta/_shared";
import {
  isCompetitionConfigurationAction,
  configurationRecord,
  type CompetitionConfigurationAction,
  type CompetitionConfigurationJson,
} from "../../../competition-configuration-contract";
import { clientWriteGateResponse, noStoreHeaders } from "../../client-policy/_contract";

export const configurationUuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function configurationJson(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function boundedText(value: unknown, maximum: number) {
  if (value == null) return "";
  if (typeof value !== "string" || value.length > maximum) throw new Error("INVALID_COMPETITION_CONFIGURATION_COMMAND");
  return value.trim();
}

function reason(input: CompetitionConfigurationJson, fallback: string) {
  return boundedText(input.reason, 120) || fallback;
}

export function parseConfigurationAction(value: unknown) {
  const action = typeof value === "string" ? value.trim() : "";
  if (!isCompetitionConfigurationAction(action)) throw new Error("INVALID_COMPETITION_CONFIGURATION_COMMAND");
  return action;
}

export function configurationCommandPayload(action: CompetitionConfigurationAction, input: CompetitionConfigurationJson) {
  if (action === "draft.create" || action === "draft.clone") {
    const authoringMode = boundedText(input.authoringMode, 16).toUpperCase() || "SIMPLE";
    const presetKey = boundedText(input.presetKey, 32).toUpperCase();
    const editionId = boundedText(input.editionId, 36);
    const sourceRuleRevisionId = boundedText(input.sourceRuleRevisionId, 36);
    if (!["SIMPLE", "ADVANCED"].includes(authoringMode)) throw new Error("COMPETITION_CONFIGURATION_MODE_INVALID");
    if (presetKey && !["LEAGUE_F5_QUICK", "LEAGUE_F7_STANDARD", "LEAGUE_F11", "LEAGUE_FUTSAL"].includes(presetKey)) throw new Error("COMPETITION_CONFIGURATION_PRESET_INVALID");
    if (editionId && !configurationUuidPattern.test(editionId)) throw new Error("COMPETITION_EDITION_NOT_FOUND");
    if (sourceRuleRevisionId && !configurationUuidPattern.test(sourceRuleRevisionId)) throw new Error("RULE_REVISION_NOT_FOUND");
    return { authoringMode, editionId, presetKey, reason: reason(input, action), sourceRuleRevisionId };
  }
  if (action === "draft.mode.set") {
    const mode = boundedText(input.mode, 16).toUpperCase();
    if (!["SIMPLE", "ADVANCED"].includes(mode)) throw new Error("COMPETITION_CONFIGURATION_MODE_INVALID");
    return { mode, reason: reason(input, action) };
  }
  if (action === "draft.preset.apply") {
    const presetKey = boundedText(input.presetKey, 32).toUpperCase();
    if (!["LEAGUE_F5_QUICK", "LEAGUE_F7_STANDARD", "LEAGUE_F11", "LEAGUE_FUTSAL"].includes(presetKey)) throw new Error("COMPETITION_CONFIGURATION_PRESET_INVALID");
    return { presetKey, reason: reason(input, action) };
  }
  if (action === "draft.section.save") {
    const step = Number(input.step);
    const normalized = leagueBetaCommandPayload("wizard.step.save", { data: input.data, reason: reason(input, action), step });
    return { data: normalized.data, reason: normalized.reason, step: normalized.step };
  }
  if (action === "draft.validate") {
    const effectiveFrom = boundedText(input.effectiveFrom, 40);
    const effectiveScope = boundedText(input.effectiveScope, 24).toUpperCase() || "FUTURE_ONLY";
    if (effectiveFrom && Number.isNaN(Date.parse(effectiveFrom))) throw new Error("COMPETITION_CONFIGURATION_EFFECTIVE_DATE_INVALID");
    if (!["FUTURE_ONLY", "FUTURE_STAGE"].includes(effectiveScope)) throw new Error("COMPETITION_CONFIGURATION_SCOPE_INVALID");
    return { effectiveFrom, effectiveScope, reason: reason(input, action) };
  }
  if (action === "draft.publish") return {
    confirmImpact: input.confirmImpact === true,
    confirmRuleSummary: input.confirmRuleSummary === true,
    reason: reason(input, action),
  };
  return { reason: reason(input, action) };
}

export async function configurationSession(request: Request) {
  const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  if (!token) throw new Error("AUTHENTICATION_REQUIRED");
  const client = platformUserClient(token);
  const userResult = await client.auth.getUser(token);
  if (userResult.error || !userResult.data.user) throw new Error("AUTHENTICATION_REQUIRED");
  return { client, user: userResult.data.user };
}

export function requireConfigurationOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) throw new Error("COMPETITION_CONFIGURATION_ORIGIN_REQUIRED");
}

export function configurationWriteGate(request: Request) { return clientWriteGateResponse(request); }
export function configurationClientMetadata(request: Request) { return leagueBetaClientMetadata(request, "competition_configuration_center"); }

export function configurationError(error: unknown) {
  const detail = error instanceof Error ? error.message : "COMPETITION_CONFIGURATION_REQUEST_FAILED";
  const status = /AUTHENTICATION_REQUIRED/i.test(detail) ? 401
    : /STALE_REVISION|PT409|CONFLICT|ACTIVE_DRAFT/i.test(detail) ? 409
      : /FORBIDDEN|REQUIRED|42501|DISABLED|NOT_AUTHORIZED|MANAGER/i.test(detail) ? 403
        : /NOT_FOUND|P0002/i.test(detail) ? 404
          : /PAYLOAD_TOO_LARGE/i.test(detail) ? 413
            : /NOT_AVAILABLE|0A000/i.test(detail) ? 422
              : 400;
  return configurationJson({ error: "COMPETITION_CONFIGURATION_REQUEST_REJECTED", message: detail }, status);
}

export function configurationBody(value: unknown) { return configurationRecord(value); }
