import { noStoreHeaders } from "../../client-policy/_contract";
import { platformUserClient } from "../../../admin/_lib/platform-auth";

export const dynamic = "force-dynamic";
export const revalidate = 0;

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const clubTypes = new Set(["FOOTBALL_CLUB", "SPORTS_CENTER", "ASSOCIATION", "INDEPENDENT_ORGANIZER", "OTHER"]);
const clubRoles = new Set(["club_owner", "club_admin", "club_competition_manager", "club_viewer"]);
const relationshipTypes = new Set(["MEMBER", "AFFILIATED", "HOSTED"]);
const visibilityValues = new Set(["private", "unlisted", "public"]);

function json(data: unknown, status = 200) {
  return Response.json(data, { headers: noStoreHeaders, status });
}

function record(value: unknown) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function string(input: Record<string, unknown>, key: string, maximum = 1200) {
  const value = typeof input[key] === "string" ? input[key].trim() : "";
  if (value.length > maximum) throw new Error("INVALID_CLUB_COMMAND");
  return value;
}

function uuid(input: Record<string, unknown>, key: string, optional = false) {
  const value = string(input, key, 40);
  if (optional && !value) return "";
  if (!uuidPattern.test(value)) throw new Error("INVALID_CLUB_COMMAND");
  return value;
}

function reason(input: Record<string, unknown>, fallback: string) {
  const value = string(input, "reason");
  return value || fallback;
}

function timestamp(input: Record<string, unknown>, key: string) {
  const value = string(input, key, 40);
  if (!value) return "";
  if (Number.isNaN(Date.parse(value))) throw new Error("INVALID_CLUB_COMMAND");
  return new Date(value).toISOString();
}

function clubProfile(input: Record<string, unknown>, partial: boolean) {
  const output: Record<string, unknown> = {};
  const copy = (key: string, maximum: number) => {
    if (!partial || key in input) output[key] = string(input, key, maximum);
  };
  copy("name", 120);
  copy("slug", 80);
  copy("description", 2000);
  copy("countryCode", 2);
  copy("province", 120);
  copy("municipality", 120);
  copy("generalArea", 160);
  copy("placeId", 240);
  copy("websiteUrl", 500);
  copy("logoAsset", 500);
  if (!partial || "clubType" in input) {
    const clubType = string(input, "clubType", 40).toUpperCase();
    if (!clubTypes.has(clubType)) throw new Error("INVALID_CLUB_COMMAND");
    output.clubType = clubType;
  }
  if (!partial || "visibility" in input) {
    const visibility = string(input, "visibility", 20).toLowerCase();
    if (!visibilityValues.has(visibility)) throw new Error("INVALID_CLUB_COMMAND");
    output.visibility = visibility;
  }
  output.reason = reason(input, partial ? "club_profile_update" : "club_create");
  return output;
}

function commandPayload(action: string, input: Record<string, unknown>) {
  if (action === "club.create") return clubProfile(input, false);
  if (action === "club.profile.update") return clubProfile(input, true);
  if (action === "club.review.submit") return { reason: reason(input, action) };
  if (action === "club.primary_owner.transfer") return {
    reason: reason(input, action),
    retainPreviousOwner: input.retainPreviousOwner !== false,
    targetUserId: uuid(input, "targetUserId"),
  };
  if (action === "membership.invite") {
    const targetKind = string(input, "targetKind", 30);
    const role = string(input, "role", 40);
    if (!new Set(["registered_user", "email_target"]).has(targetKind) || !clubRoles.has(role)) {
      throw new Error("INVALID_CLUB_COMMAND");
    }
    return {
      expiresAt: timestamp(input, "expiresAt"),
      reason: reason(input, action),
      role,
      targetEmail: targetKind === "email_target" ? string(input, "targetEmail", 320).toLowerCase() : "",
      targetKind,
      targetUserId: targetKind === "registered_user" ? uuid(input, "targetUserId") : "",
    };
  }
  if (action === "membership.accept" || action === "membership.decline") {
    const token = string(input, "token", 64);
    if (!/^[0-9a-f]{64}$/i.test(token)) throw new Error("INVALID_CLUB_COMMAND");
    return { reason: reason(input, action), token };
  }
  if (action === "membership.invitation.revoke" || action === "membership.revoke") {
    return { reason: reason(input, action) };
  }
  if (action === "team_relationship.invite" || action === "team_relationship.request") {
    const relationshipType = string(input, "relationshipType", 20).toUpperCase();
    if (!relationshipTypes.has(relationshipType)) throw new Error("INVALID_CLUB_COMMAND");
    return { groupId: uuid(input, "groupId"), reason: reason(input, action), relationshipType };
  }
  if (new Set(["team_relationship.accept", "team_relationship.reject", "team_relationship.cancel", "team_relationship.end"]).has(action)) {
    return { reason: reason(input, action) };
  }
  if (action === "team_relationship.visibility.set") {
    if (typeof input.showOnClubProfile !== "boolean") throw new Error("INVALID_CLUB_COMMAND");
    return { reason: reason(input, action), showOnClubProfile: input.showOnClubProfile };
  }
  if (action === "competition.create") {
    const competitionType = string(input, "competitionType", 20).toUpperCase();
    if (!new Set(["LEAGUE", "TOURNAMENT"]).has(competitionType)) throw new Error("INVALID_CLUB_COMMAND");
    const visibility = string(input, "visibility", 20).toLowerCase();
    if (!new Set(["private", "internal"]).has(visibility)) throw new Error("INVALID_CLUB_COMMAND");
    return {
      competitionType,
      editionName: string(input, "editionName", 120),
      endsAt: string(input, "endsAt", 10),
      name: string(input, "name", 120),
      reason: reason(input, action),
      ruleSetName: string(input, "ruleSetName", 120),
      seasonLabel: string(input, "seasonLabel", 120),
      slug: string(input, "slug", 80).toLowerCase(),
      startsAt: string(input, "startsAt", 10),
      visibility,
    };
  }
  throw new Error("INVALID_CLUB_COMMAND");
}

function metadata(request: Request) {
  return {
    clientVersion: request.headers.get("x-pachangas-client-version"),
    installedMode: request.headers.get("x-pachangas-display-mode"),
    serviceWorkerVersion: request.headers.get("x-pachangas-service-worker-version"),
    surface: "club_foundation_lab",
  };
}

export async function POST(request: Request) {
  try {
    const origin = request.headers.get("origin");
    if (!origin || origin !== new URL(request.url).origin) return json({ error: "CLUB_ORIGIN_REQUIRED" }, 403);
    const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "AUTHENTICATION_REQUIRED" }, 401);
    const client = platformUserClient(token);
    const user = await client.auth.getUser(token);
    if (user.error || !user.data.user) return json({ error: "AUTHENTICATION_REQUIRED" }, 401);
    const body = record(await request.json());
    const action = string(body, "action", 80);
    const operationId = uuid(body, "operationId");
    const aggregateId = uuid(body, "aggregateId");
    const expectedRevision = Number(body.expectedRevision);
    if (!Number.isInteger(expectedRevision) || expectedRevision < 0) throw new Error("INVALID_CLUB_COMMAND");
    const args = {
      aggregate_id: aggregateId,
      client_metadata: metadata(request),
      command_action: action,
      command_payload: commandPayload(action, record(body.payload)),
      expected_revision: expectedRevision,
      operation_id: operationId,
    };
    const result = action === "competition.create"
      ? await client.rpc("command_pachanga_competition_foundation_v2", { ...args, organizer_kind: "CLUB" })
      : await client.rpc("command_pachanga_club_foundation_v1", args);
    if (result.error) {
      const status = /STALE_REVISION|PT409|CONFLICT/i.test(result.error.message) ? 409
        : /REQUIRED|FORBIDDEN|42501/i.test(result.error.message) ? 403
          : /DISABLED|FEATURE_NOT_AVAILABLE|0A000/i.test(result.error.message) ? 409
            : 400;
      return json({ error: "CLUB_COMMAND_REJECTED", message: result.error.message }, status);
    }
    return json({ canonical: result.data });
  } catch (error) {
    return json({
      error: "INVALID_CLUB_COMMAND",
      message: error instanceof Error && error.message !== "INVALID_CLUB_COMMAND" ? error.message : "La intención no es válida.",
    }, 400);
  }
}
