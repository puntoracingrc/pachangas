import {
  PlatformAccessError,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getPlatformPublicCompetitions } from "../../../admin/_lib/platform-data";
import {
  publicCompetitionNumber,
  publicCompetitionRecord,
  publicCompetitionText,
} from "../../../public-competition-contract";
import { clientWriteGateResponse } from "../../client-policy/_contract";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const moderationActions = new Set([
  "publication.approve", "publication.reject", "publication.request_changes",
  "publication.publish", "publication.suspend", "publication.restore",
  "publication.archive", "publication.organizer.verify", "report.review",
  "report.resolve", "report.dismiss",
]);
const safeFlags = new Set([
  "foundation", "publication", "discovery", "registrationRequests", "waitlist",
  "calendar", "results", "standings", "bracket", "exceptionStatus", "referees",
]);

function metadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface: "platform_control_center_public_competitions",
  };
}

function safeReason(value: unknown, maximum: number, fallback = "") {
  return typeof value === "string" ? value.trim().slice(0, maximum) : fallback;
}

function errorResponse(error: unknown) {
  if (error instanceof PlatformAccessError) {
    return platformJson({ error: "ADMIN_ACCESS_DENIED" }, { status: error.status });
  }
  const message = error instanceof Error ? error.message : "";
  if (/STALE_REVISION|IDEMPOTENCY_KEY_REUSED|_STATE_INVALID|_CONFLICT|ACTIVE_REGISTRATION/i.test(message)) {
    return platformJson({ error: "ADMIN_STALE_REVISION", message: "El estado cambió. Recarga los datos antes de repetir la acción." }, { status: 409 });
  }
  if (/AUTHENTICATION_REQUIRED|ACCESS_REQUIRED|CAPABILITY_REQUIRED|PERMISSION_DENIED|SELF_REVIEW_FORBIDDEN|CURRENT_CONSENT_REQUIRED|UNSAFE_FLAG_DISABLED/i.test(message)) {
    return platformJson({ error: "ADMIN_ACCESS_DENIED", message: "La operación no está permitida." }, { status: 403 });
  }
  if (/NOT_FOUND/i.test(message)) return platformJson({ error: "ADMIN_NOT_FOUND", message: "El recurso ya no existe." }, { status: 404 });
  if (/INVALID|REQUIRED|FORBIDDEN/i.test(message)) return platformJson({ error: "ADMIN_INVALID_REQUEST", message: "La solicitud no cumple el contrato." }, { status: 400 });
  return platformJson({ error: "ADMIN_REQUEST_FAILED", message: "La operación administrativa no pudo completarse." }, { status: 500 });
}

export async function GET(request: Request) {
  try {
    const url = new URL(request.url);
    const session = await requirePlatformRequest(request, "competitions.read");
    return platformJson(await getPlatformPublicCompetitions(
      session,
      url.searchParams.get("publicationStatus") ?? undefined,
      url.searchParams.get("reportStatus") ?? undefined,
    ));
  } catch (error) {
    return errorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const gated = clientWriteGateResponse(request);
    if (gated) return gated;
    const body = publicCompetitionRecord(await request.json());
    const action = publicCompetitionText(body.action);
    const operationId = publicCompetitionText(body.operationId);
    const expectedRevision = publicCompetitionNumber(body.expectedRevision);
    if (!uuidPattern.test(operationId) || !Number.isInteger(expectedRevision) || expectedRevision < 1) {
      throw new Error("INVALID_PUBLIC_COMPETITION_PLATFORM_ENVELOPE");
    }

    if (action === "flags.set") {
      const session = await requirePlatformRequest(request, "flags.write");
      const source = publicCompetitionRecord(body.payload);
      const patch: Record<string, boolean> = {};
      for (const [key, value] of Object.entries(publicCompetitionRecord(source.patch))) {
        if (!safeFlags.has(key) || typeof value !== "boolean") throw new Error("PUBLIC_COMPETITION_FLAG_FIELD_FORBIDDEN");
        patch[key] = value;
      }
      if (!Object.keys(patch).length) throw new Error("INVALID_PUBLIC_COMPETITION_FLAG_COMMAND");
      const reason = safeReason(source.reason, 1200);
      if (reason.length < 3) throw new Error("PUBLIC_COMPETITION_FLAG_REASON_REQUIRED");
      const result = await session.client.rpc("set_pachanga_public_competition_flags_v1", {
        client_metadata: metadata(request), expected_revision: expectedRevision,
        flag_patch: patch, operation_id: operationId, reason,
      });
      if (result.error) throw new Error(result.error.message);
      return platformJson({ canonical: result.data });
    }

    if (!moderationActions.has(action)) throw new Error("INVALID_PUBLIC_COMPETITION_MODERATION_ACTION");
    const aggregateId = publicCompetitionText(body.aggregateId);
    if (!uuidPattern.test(aggregateId)) throw new Error("INVALID_PUBLIC_COMPETITION_MODERATION_TARGET");
    const session = await requirePlatformRequest(request, action.startsWith("report.") ? "moderation.write" : "competitions.manage");
    const source = publicCompetitionRecord(body.payload);
    const result = await session.client.rpc("command_pachanga_public_competition_moderation_v1", {
      aggregate_id: aggregateId,
      client_metadata: metadata(request),
      command_action: action,
      command_payload: {
        privateReason: safeReason(source.privateReason, 1200),
        publicReason: safeReason(source.publicReason, 500),
        reason: safeReason(source.reason, 120, action),
      },
      expected_revision: expectedRevision,
      operation_id: operationId,
    });
    if (result.error) throw new Error(result.error.message);
    return platformJson({ canonical: result.data });
  } catch (error) {
    return errorResponse(error);
  }
}
