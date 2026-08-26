import {
  refereeClientMetadata,
  refereeError,
  refereeJson,
  refereeRecord,
  refereeSession,
  refereeUuidPattern,
  refereeWriteGate,
  requireRefereeOrigin,
} from "../referees/_shared";
import { refereeFeeModes } from "../../referee-assignment-contract";

export {
  refereeError,
  refereeJson,
  refereeRecord,
  refereeSession,
  refereeUuidPattern,
  refereeWriteGate,
  requireRefereeOrigin,
};

function text(input: Record<string, unknown>, key: string, maximum = 1200) {
  const value = typeof input[key] === "string" ? input[key].trim() : "";
  if (value.length > maximum) throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
  return value;
}

function uuid(input: Record<string, unknown>, key: string, optional = false) {
  const value = text(input, key, 80);
  if (optional && !value) return "";
  if (!refereeUuidPattern.test(value)) throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
  return value;
}

function integer(value: unknown, minimum: number, maximum: number, optional = false) {
  if (optional && (value === "" || value == null)) return "";
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
  }
  return parsed;
}

function timestamp(input: Record<string, unknown>, key: string, optional = false) {
  const value = text(input, key, 80);
  if (optional && !value) return "";
  if (!value || Number.isNaN(Date.parse(value))) throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
  return new Date(value).toISOString();
}

function reason(input: Record<string, unknown>, fallback: string) {
  return text(input, "reason", 120) || fallback;
}

function feeMode(input: Record<string, unknown>) {
  const value = (text(input, "feeMode", 20) || "FREE").toUpperCase();
  if (!(refereeFeeModes as readonly string[]).includes(value)) {
    throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
  }
  return value;
}

export function refereeAssignmentPayload(action: string, input: Record<string, unknown>) {
  if (action === "assignment.propose") {
    const requesterKind = text(input, "requesterKind", 20).toUpperCase();
    const sourceKind = text(input, "sourceKind", 40).toLowerCase();
    if (!new Set(["TEAM", "CLUB", "COMPETITION"]).has(requesterKind)
        || !new Set(["group_match", "open_match", "external_match", "team_challenge", "competition_generated"]).has(sourceKind)) {
      throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
    }
    return {
      assignmentRole: "MAIN_REFEREE",
      currency: (text(input, "currency", 3) || "EUR").toUpperCase(),
      feeMode: feeMode(input),
      message: text(input, "message", 800),
      privateTermsNote: text(input, "privateTermsNote", 1200),
      proposedFeeCents: integer(input.proposedFeeCents, 0, 10_000_000, true),
      reason: reason(input, action),
      refereeProfileId: uuid(input, "refereeProfileId"),
      requesterId: uuid(input, "requesterId"),
      requesterKind,
      responseDeadline: timestamp(input, "responseDeadline", true),
      sourceGroupId: uuid(input, "sourceGroupId", true),
      sourceId: text(input, "sourceId", 180),
      sourceKind,
      travelIncluded: input.travelIncluded === true,
    };
  }
  if (new Set([
    "assignment.accept", "assignment.decline", "assignment.confirm",
    "assignment.reconfirm", "terms.accept", "terms.decline",
  ]).has(action)) return { reason: reason(input, action) };
  if (action === "assignment.cancel") return {
    reason: reason(input, action),
    reasonCode: text(input, "reasonCode", 80) || "cancelled",
    reasonText: text(input, "reasonText", 800),
  };
  if (action === "assignment.replace") return {
    feeMode: feeMode(input),
    message: text(input, "message", 800),
    newAssignmentId: uuid(input, "newAssignmentId"),
    newRefereeProfileId: uuid(input, "newRefereeProfileId"),
    privateTermsNote: text(input, "privateTermsNote", 1200),
    proposedFeeCents: integer(input.proposedFeeCents, 0, 10_000_000, true),
    reason: reason(input, action),
    responseDeadline: timestamp(input, "responseDeadline", true),
    travelIncluded: input.travelIncluded === true,
  };
  if (action === "terms.counter") return {
    counterFeeCents: integer(input.counterFeeCents, 0, 10_000_000),
    privateTermsNote: text(input, "privateTermsNote", 1200),
    reason: reason(input, action),
    travelIncluded: input.travelIncluded === true,
  };
  throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
}

export function refereeOfficiatingPayload(action: string, input: Record<string, unknown>) {
  if (action === "result.observe") return {
    awayScore: integer(input.awayScore, 0, 99),
    homeScore: integer(input.homeScore, 0, 99),
    privateNote: text(input, "privateNote", 1200),
  };
  if (action === "discipline.record") {
    const context = text(input, "context", 30).toLowerCase() || "in_match";
    if (!new Set(["pre_match", "in_match", "interval", "post_match", "venue"]).has(context)) {
      throw new Error("INVALID_REFEREE_OFFICIATING_COMMAND");
    }
    const evidenceRefs = Array.isArray(input.evidenceRefs) ? input.evidenceRefs : [];
    if (evidenceRefs.length > 20 || evidenceRefs.some((value) => typeof value !== "string" || value.length > 1000)) {
      throw new Error("INVALID_REFEREE_OFFICIATING_COMMAND");
    }
    return {
      cardTypeCode: text(input, "cardTypeCode", 30).toUpperCase(),
      context,
      evidenceRefs,
      minute: integer(input.minute, 0, 300, context !== "in_match"),
      period: text(input, "period", 30),
      playerProfileId: uuid(input, "playerProfileId"),
      privateNotes: text(input, "privateNotes", 4000),
      publicReasonCategory: text(input, "publicReasonCategory", 120),
      publicSummary: text(input, "publicSummary", 500),
    };
  }
  throw new Error("INVALID_REFEREE_OFFICIATING_COMMAND");
}

export function refereePublicFeePayload(action: string, input: Record<string, unknown>) {
  if (action === "public_fee.configure") {
    const mode = feeMode(input);
    const fromCents = integer(input.fromCents, 0, 10_000_000, true);
    if (mode === "FIXED" && fromCents === "") throw new Error("INVALID_REFEREE_PUBLIC_FEE_COMMAND");
    if (new Set(["FREE", "VOLUNTEER"]).has(mode) && fromCents !== "") throw new Error("INVALID_REFEREE_PUBLIC_FEE_COMMAND");
    return { currency: (text(input, "currency", 3) || "EUR").toUpperCase(), feeMode: mode, fromCents };
  }
  if (action === "public_fee.publish") return {
    informationCorrect: input.informationCorrect === true,
    outOfPlatformPaymentAcknowledged: input.outOfPlatformPaymentAcknowledged === true,
  };
  if (action === "public_fee.unpublish") return {};
  throw new Error("INVALID_REFEREE_PUBLIC_FEE_COMMAND");
}

export function refereeAssignmentMetadata(request: Request, surface: string) {
  return refereeClientMetadata(request, surface);
}

export function refereeAssignmentEnvelope(value: unknown) {
  const body = refereeRecord(value);
  const action = typeof body.action === "string" ? body.action.trim().toLowerCase() : "";
  const operationId = typeof body.operationId === "string" ? body.operationId : "";
  const aggregateId = typeof body.aggregateId === "string" ? body.aggregateId : "";
  const expectedRevision = Number(body.expectedRevision);
  if (!refereeUuidPattern.test(operationId) || !refereeUuidPattern.test(aggregateId)
      || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0) {
    throw new Error("INVALID_REFEREE_ASSIGNMENT_COMMAND");
  }
  return { action, aggregateId, body, expectedRevision, operationId };
}
