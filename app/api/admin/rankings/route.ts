import {
  platformErrorResponse,
  platformJson,
  requirePlatformRequest,
  requireSameOriginMutation,
} from "../../../admin/_lib/platform-auth";
import { getRankingAdminOverview } from "../../../admin/_lib/platform-data";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

type JsonRecord = Record<string, unknown>;

function record(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function requiredText(value: unknown, label: string) {
  const normalized = typeof value === "string" ? value.trim() : "";
  if (!normalized) throw new Error(`Invalid ${label}`);
  return normalized;
}

function requiredNumber(value: unknown, label: string) {
  const normalized = Number(value);
  if (!Number.isFinite(normalized)) throw new Error(`Invalid ${label}`);
  return normalized;
}

async function rpc(session: Awaited<ReturnType<typeof requirePlatformRequest>>, name: string, args: JsonRecord) {
  const result = await session.client.rpc(name, args);
  if (result.error) throw new Error(result.error.message);
  return result.data;
}

export async function GET(request: Request) {
  try {
    const session = await requirePlatformRequest(request, "rankings.read");
    return platformJson({ data: await getRankingAdminOverview(session) });
  } catch (error) {
    return platformErrorResponse(error);
  }
}

export async function POST(request: Request) {
  try {
    requireSameOriginMutation(request);
    const session = await requirePlatformRequest(request, "rankings.write");
    const body = record(await request.json());
    const action = requiredText(body.action, "ranking action");
    const operationId = requiredText(body.operationId, "operationId");
    const reason = requiredText(body.reason, "reason");
    let data: unknown;

    if (action === "createSeason") {
      const provinceCodes = Array.isArray(body.provinceCodes) ? body.provinceCodes.map(String) : [];
      data = await rpc(session, "create_pachanga_ranking_season_v1", {
        ends_at: requiredText(body.endsAt, "season end"),
        province_codes: provinceCodes,
        reason,
        requested_operation_id: operationId,
        season_key: requiredText(body.seasonKey, "season key"),
        season_label: requiredText(body.seasonLabel, "season label"),
        starts_at: requiredText(body.startsAt, "season start"),
      });
    } else if (action === "transition") {
      data = await rpc(session, "transition_pachanga_ranking_season_v1", {
        expected_revision: requiredNumber(body.expectedRevision, "season revision"),
        next_status: requiredText(body.nextStatus, "next status"),
        reason,
        requested_operation_id: operationId,
        target_season_id: requiredText(body.seasonId, "season id"),
      });
    } else if (action === "mapVenue") {
      data = await rpc(session, "map_pachanga_ranking_venue_v1", {
        confidence: 1,
        evidence: { confirmedBy: "platform_control_center" },
        expected_mapping_revision: requiredNumber(body.expectedMappingRevision, "mapping revision"),
        reason,
        requested_operation_id: operationId,
        target_place_id: requiredText(body.placeId, "place id"),
        target_province_code: requiredText(body.provinceCode, "province code"),
      });
    } else if (action === "rebuild") {
      data = await rpc(session, "rebuild_pachanga_provincial_ranking_v1", {
        expected_season_revision: requiredNumber(body.expectedRevision, "season revision"),
        reason,
        requested_operation_id: operationId,
        target_season_id: requiredText(body.seasonId, "season id"),
      });
    } else if (action === "publish") {
      data = await rpc(session, "publish_pachanga_provincial_ranking_v1", {
        expected_candidate_checksum: requiredText(body.candidateChecksum, "candidate checksum"),
        expected_season_revision: requiredNumber(body.expectedRevision, "season revision"),
        reason,
        requested_operation_id: operationId,
        target_rebuild_id: requiredText(body.rebuildId, "rebuild id"),
      });
    } else if (action === "resolveIntegrity") {
      data = await rpc(session, "resolve_pachanga_ranking_integrity_v1", {
        expected_revision: requiredNumber(body.expectedRevision, "integrity revision"),
        reason,
        requested_operation_id: operationId,
        target_resolution: requiredText(body.resolution, "integrity resolution"),
        target_review_id: requiredText(body.reviewId, "review id"),
      });
    } else if (action === "processQueue") {
      data = await rpc(session, "process_pachanga_ranking_refresh_queue_admin_v1", {
        expected_settings_revision: requiredNumber(body.expectedSettingsRevision, "settings revision"),
        maximum_operations: requiredNumber(body.maximumOperations, "maximum operations"),
        reason,
        requested_operation_id: operationId,
      });
    } else {
      throw new Error("Invalid ranking action");
    }

    return platformJson({ data });
  } catch (error) {
    return platformErrorResponse(error);
  }
}
