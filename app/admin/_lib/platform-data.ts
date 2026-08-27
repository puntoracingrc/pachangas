import "server-only";

import type { SupabaseClient } from "@supabase/supabase-js";
import { FREE_TRIAL_MATCH_LIMIT } from "../../api/billing/_shared";
import { platformServiceClient, type VerifiedPlatformSession } from "./platform-auth";

type JsonRecord = Record<string, unknown>;

export type PlatformPage = {
  page: number;
  pageSize: number;
  total: number;
};

function asRecord(value: unknown): JsonRecord {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function asArray(value: unknown) {
  return Array.isArray(value) ? value : [];
}

function boundedInteger(value: string | null | undefined, fallback: number, minimum: number, maximum: number) {
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) ? Math.min(Math.max(parsed, minimum), maximum) : fallback;
}

export function paginationFromSearchParams(params: URLSearchParams, defaultPageSize = 30) {
  return {
    page: boundedInteger(params.get("page"), 1, 1, 100000),
    pageSize: boundedInteger(params.get("pageSize"), defaultPageSize, 10, 100),
  };
}

function safeSearch(value: string | null | undefined) {
  return (value ?? "").trim().slice(0, 120).replace(/[,%()]/g, " ");
}

async function rpcOrThrow<T>(client: SupabaseClient, name: string, args?: JsonRecord) {
  const result = await client.rpc(name, args);
  if (result.error) throw new Error(result.error.message);
  return result.data as T;
}

export async function getPlatformOverview(session: VerifiedPlatformSession, period: string) {
  const supported = new Set(["today", "7d", "30d", "season"]);
  return rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_overview_v1", {
    selected_period: supported.has(period) ? period : "today",
  });
}

async function userSummaries(session: VerifiedPlatformSession, userIds: string[]) {
  if (!userIds.length) return {} as Record<string, JsonRecord>;
  const result = await rpcOrThrow<unknown>(session.client, "get_pachanga_platform_user_summaries_v1", {
    target_user_ids: userIds,
  });
  return asRecord(result) as Record<string, JsonRecord>;
}

export async function listPlatformUsers(
  session: VerifiedPlatformSession,
  input: { createdFrom?: string; createdTo?: string; page: number; pageSize: number; query?: string; sort?: string; status?: string },
) {
  const allowedStatus = new Set(["active", "all", "banned", "suspended"]);
  const allowedSort = new Set(["created_asc", "created_desc", "last_sign_in_desc", "name_asc"]);
  const date = (value?: string) => /^\d{4}-\d{2}-\d{2}$/.test(value ?? "") ? value : null;
  const data = await rpcOrThrow<JsonRecord>(session.client, "list_pachanga_platform_users_v1", {
    created_from: date(input.createdFrom),
    created_to: date(input.createdTo),
    page_offset: (input.page - 1) * input.pageSize,
    page_size: input.pageSize,
    search_text: safeSearch(input.query),
    sort_key: allowedSort.has(input.sort ?? "created_desc") ? input.sort ?? "created_desc" : "created_desc",
    status_filter: allowedStatus.has(input.status ?? "all") ? input.status ?? "all" : "all",
  });
  const items = asArray(data.items).map((value) => {
    const row = asRecord(value);
    return {
      activeRestrictionCount: Number(row.activeRestrictionCount) || 0,
      authSyncState: String(row.authSyncState ?? "confirmed"),
      createdAt: typeof row.createdAt === "string" ? row.createdAt : null,
      email: typeof row.email === "string" ? row.email : null,
      id: String(row.id ?? ""),
      lastSignInAt: typeof row.lastSignInAt === "string" ? row.lastSignInAt : null,
      name: String(row.name ?? "Usuario"),
      ownedTeamCount: Number(row.ownedTeamCount) || 0,
      platformRole: typeof row.platformRole === "string" ? row.platformRole : null,
      profileId: typeof row.profileId === "string" ? row.profileId : null,
      status: String(row.status ?? "active"),
      statusExpiresAt: typeof row.statusExpiresAt === "string" ? row.statusExpiresAt : null,
      statusRevision: Number(row.statusRevision) || 0,
      teamCount: Number(row.teamCount) || 0,
    };
  });
  return { items, page: input.page, pageSize: input.pageSize, total: Number(data.total) || 0 };
}

export async function getPlatformUserDetail(session: VerifiedPlatformSession, userId: string) {
  const service = platformServiceClient();
  const canReadBilling = session.access.capabilities.includes("billing.read");
  const canReadPii = session.access.capabilities.includes("users.pii.read");
  const authResult = await service.auth.admin.getUserById(userId);
  if (authResult.error || !authResult.data.user) throw new Error("User not found");
  const user = authResult.data.user;
  const [profileResult, memberResult, ownedResult, summaries] = await Promise.all([
    service.from("pachanga_player_profiles")
      .select("id,user_id,display_name,avatar,birth_date,goalkeeper_only,injured,inactive,position,outfield_position,market_enabled,profile_version,rating_domain,base_facets,calibrated_facets,current_facets,base_overall,calibrated_overall,current_overall,rating_reliability,rating_evaluator_count,rating_engine_version,rating_recalculated_at,created_at,updated_at")
      .eq("user_id", userId)
      .maybeSingle(),
    service.from("pachanga_group_members")
      .select("group_id,role,display_name,created_at,role_changed_at,pachanga_groups(id,name,team_code,billing_status)")
      .eq("user_id", userId)
      .order("created_at", { ascending: false }),
    service.from("pachanga_groups")
      .select("id,name,team_code,billing_status,billing_interval,stripe_customer_id,stripe_subscription_id,created_at,updated_at")
      .eq("owner_id", userId)
      .order("created_at", { ascending: false }),
    userSummaries(session, [userId]),
  ]);
  if (profileResult.error) throw new Error(profileResult.error.message);
  if (memberResult.error) throw new Error(memberResult.error.message);
  if (ownedResult.error) throw new Error(ownedResult.error.message);

  const profile = profileResult.data as JsonRecord | null;
  const profileId = typeof profile?.id === "string" ? profile.id : null;
  const [achievementResult, rewardResult, inventoryResult, notificationResult, matchResult] = await Promise.all([
    profileId
      ? service.from("pachanga_achievement_grants").select("id,state,metric_value,awarded_at,occurred_at,group_id", { count: "exact" }).eq("subject_id", profileId).order("awarded_at", { ascending: false }).limit(20)
      : Promise.resolve({ data: [], error: null, count: 0 }),
    profileId
      ? service.from("pachanga_reward_grants").select("id,reward_kind,reward_key,state,granted_at,group_id", { count: "exact" }).eq("player_profile_id", profileId).order("granted_at", { ascending: false }).limit(20)
      : Promise.resolve({ data: [], error: null, count: 0 }),
    profileId
      ? service.from("pachanga_player_reward_inventory").select("reward_kind,reward_key,state,unlocked_at,revision", { count: "exact" }).eq("player_profile_id", profileId).order("unlocked_at", { ascending: false }).limit(30)
      : Promise.resolve({ data: [], error: null, count: 0 }),
    service.from("pachanga_user_notifications").select("id,kind,title,category,priority,read_at,created_at", { count: "exact" }).eq("recipient_user_id", userId).order("server_sequence", { ascending: false }).limit(20),
    profileId
      ? service.from("pachanga_match_rating_participants").select("group_id,match_id,team_side,attendance_confirmed,was_reserve,card_snapshot,created_at").eq("player_profile_id", profileId).order("created_at", { ascending: false }).limit(30)
      : Promise.resolve({ data: [], error: null }),
  ]);
  for (const result of [achievementResult, rewardResult, inventoryResult, notificationResult, matchResult]) {
    if (result.error) throw new Error(result.error.message);
  }
  const summary = summaries[userId] ?? {};
  const safeProfile = profile
    ? { ...profile, birth_date: canReadPii ? profile.birth_date ?? null : null }
    : null;
  const safeOwnedTeams = (ownedResult.data ?? []).map((team) => ({
    ...team,
    stripe_customer_id: canReadBilling ? team.stripe_customer_id : null,
    stripe_subscription_id: canReadBilling ? team.stripe_subscription_id : null,
  }));
  return {
    auth: {
      bannedUntil: user.banned_until ?? null,
      createdAt: user.created_at,
      email: canReadPii ? user.email ?? null : null,
      id: user.id,
      lastSignInAt: user.last_sign_in_at ?? null,
      providers: canReadPii ? user.app_metadata?.providers ?? [] : [],
    },
    achievements: { count: achievementResult.count ?? 0, items: achievementResult.data ?? [] },
    groups: memberResult.data ?? [],
    matches: matchResult.data ?? [],
    notifications: { count: notificationResult.count ?? 0, items: notificationResult.data ?? [] },
    ownedTeams: safeOwnedTeams,
    profile: safeProfile,
    rewards: {
      grants: rewardResult.data ?? [],
      grantCount: rewardResult.count ?? 0,
      inventory: inventoryResult.data ?? [],
      inventoryCount: inventoryResult.count ?? 0,
    },
    state: summary,
  };
}

export async function listPlatformTeams(
  session: VerifiedPlatformSession,
  input: {
    activity?: string;
    billing?: string;
    createdFrom?: string;
    createdTo?: string;
    locality?: string;
    market?: string;
    maximumLevel?: string;
    minimumLevel?: string;
    owner?: string;
    page: number;
    pageSize: number;
    query?: string;
    social?: string;
    sort?: string;
  },
) {
  const allowedBilling = new Set(["active", "all", "canceled", "incomplete", "past_due", "trial", "trialing", "unpaid"]);
  const allowedMarket = new Set(["all", "disabled", "enabled"]);
  const allowedActivity = new Set(["active", "all", "inactive"]);
  const allowedSocial = new Set(["all", "clean", "restricted"]);
  const allowedSort = new Set(["created_desc", "level_desc", "name_asc", "updated_desc"]);
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const owner = input.owner?.trim() ?? "";
  const numericLevel = (value?: string) => {
    if (!value?.trim()) return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : null;
  };
  const date = (value?: string) => /^\d{4}-\d{2}-\d{2}$/.test(value ?? "") ? value : null;
  const data = await rpcOrThrow<JsonRecord>(session.client, "list_pachanga_platform_teams_v1", {
    activity_filter: allowedActivity.has(input.activity ?? "all") ? input.activity ?? "all" : "all",
    billing_filter: allowedBilling.has(input.billing ?? "all") ? input.billing ?? "all" : "all",
    created_from: date(input.createdFrom),
    created_to: date(input.createdTo),
    locality_filter: safeSearch(input.locality),
    market_filter: allowedMarket.has(input.market ?? "all") ? input.market ?? "all" : "all",
    maximum_level: numericLevel(input.maximumLevel),
    minimum_level: numericLevel(input.minimumLevel),
    owner_filter: uuidPattern.test(owner) ? owner : null,
    page_offset: (input.page - 1) * input.pageSize,
    page_size: input.pageSize,
    search_text: safeSearch(input.query),
    social_filter: allowedSocial.has(input.social ?? "all") ? input.social ?? "all" : "all",
    sort_key: allowedSort.has(input.sort ?? "updated_desc") ? input.sort ?? "updated_desc" : "updated_desc",
  });
  const items = asArray(data.items).map((value) => {
    const row = asRecord(value);
    return {
      active: Boolean(row.active),
      activeRestrictionCount: Number(row.activeRestrictionCount) || 0,
      billing_interval: typeof row.billingInterval === "string" ? row.billingInterval : null,
      billing_status: typeof row.billingStatus === "string" ? row.billingStatus : "trial",
      billing_trial_finalized_matches: Number(row.billingTrialFinalizedMatches) || 0,
      created_at: typeof row.createdAt === "string" ? row.createdAt : null,
      externally_calibrated_level: Number.isFinite(Number(row.level)) ? Number(row.level) : null,
      id: String(row.id ?? ""),
      market: row.market && typeof row.market === "object" ? asRecord(row.market) : null,
      memberCount: Number(row.memberCount) || 0,
      name: String(row.name ?? "Equipo"),
      owner_id: String(row.ownerId ?? ""),
      ownerName: String(row.ownerName ?? "Owner"),
      ratings_enabled: Boolean(row.ratingsEnabled),
      team_code: typeof row.teamCode === "string" ? row.teamCode : null,
      trialRemaining: Math.max(0, FREE_TRIAL_MATCH_LIMIT - (Number(row.billingTrialFinalizedMatches) || 0)),
      updated_at: typeof row.updatedAt === "string" ? row.updatedAt : null,
    };
  });
  return { items, page: input.page, pageSize: input.pageSize, total: Number(data.total) || 0 };
}

export async function getPlatformTeamDetail(session: VerifiedPlatformSession, groupId: string) {
  const service = platformServiceClient();
  const canReadBilling = session.access.capabilities.includes("billing.read");
  const groupResult = await service.from("pachanga_groups")
    .select("id,owner_id,name,team_code,billing_status,billing_interval,billing_trial_finalized_matches,stripe_customer_id,stripe_subscription_id,stripe_price_id,stripe_current_period_end,payload_revision,created_at,updated_at,ratings_enabled,externally_calibrated_level,external_calibrated_at")
    .eq("id", groupId).single();
  if (groupResult.error || !groupResult.data) throw new Error("Team not found");
  const memberResult = await service.from("pachanga_group_members")
    .select("user_id,role,display_name,created_at,role_changed_at")
    .eq("group_id", groupId).order("created_at");
  if (memberResult.error) throw new Error(memberResult.error.message);
  const memberUserIds = [...new Set((memberResult.data ?? []).map((member) => member.user_id))];
  const [sourceProfilesResult, memberProfilesResult, matchResult, sentChallengeResult, receivedChallengeResult, achievementResult, cosmeticResult, marketResult] = await Promise.all([
    service.from("pachanga_player_profiles").select("id,user_id,display_name,avatar,current_overall,rating_reliability,injured,inactive,market_enabled,position,updated_at").eq("source_group_id", groupId).order("display_name"),
    memberUserIds.length
      ? service.from("pachanga_player_profiles").select("id,user_id,display_name,avatar,current_overall,rating_reliability,injured,inactive,market_enabled,position,updated_at").in("user_id", memberUserIds).order("display_name")
      : Promise.resolve({ data: [], error: null }),
    service.from("pachanga_match_read_model").select("match_id,match_state,match_version,configured,lineup_closed,finalized,target_players,reserve_limit,score_a,score_b,updated_at").eq("group_id", groupId).order("updated_at", { ascending: false }).limit(50),
    service.from("pachanga_team_challenges").select("id,receiver_group_id,status,revision,scheduled_at,modality,field_name,created_at,updated_at").eq("sender_group_id", groupId).order("updated_at", { ascending: false }).limit(30),
    service.from("pachanga_team_challenges").select("id,sender_group_id,status,revision,scheduled_at,modality,field_name,created_at,updated_at").eq("receiver_group_id", groupId).order("updated_at", { ascending: false }).limit(30),
    service.from("pachanga_achievement_grants").select("id,state,metric_value,awarded_at,occurred_at", { count: "exact" }).eq("group_id", groupId).order("awarded_at", { ascending: false }).limit(20),
    service.from("pachanga_team_cosmetic_inventory").select("cosmetic_key,state,unlocked_at,revision,source_kind,server_sequence", { count: "exact" }).eq("group_id", groupId).order("server_sequence", { ascending: false }).limit(40),
    service.from("pachanga_challengeable_team_profiles").select("enabled,zone_label,travel_radius_km,min_opponent_level,max_opponent_level,modalities,revision,updated_at").eq("group_id", groupId).maybeSingle(),
  ]);
  for (const result of [sourceProfilesResult, memberProfilesResult, matchResult, sentChallengeResult, receivedChallengeResult, achievementResult, cosmeticResult, marketResult]) {
    if (result.error) throw new Error(result.error.message);
  }
  const players = [...(sourceProfilesResult.data ?? []), ...(memberProfilesResult.data ?? [])]
    .filter((profile, index, all) => all.findIndex((candidate) => candidate.id === profile.id) === index)
    .sort((left, right) => left.display_name.localeCompare(right.display_name, "es"));
  const safeGroup = {
    ...groupResult.data,
    stripe_customer_id: canReadBilling ? groupResult.data.stripe_customer_id : null,
    stripe_price_id: canReadBilling ? groupResult.data.stripe_price_id : null,
    stripe_subscription_id: canReadBilling ? groupResult.data.stripe_subscription_id : null,
    stripe_current_period_end: canReadBilling ? groupResult.data.stripe_current_period_end : null,
  };
  return {
    achievements: { count: achievementResult.count ?? 0, items: achievementResult.data ?? [] },
    challenges: [...(sentChallengeResult.data ?? []).map((row) => ({ ...row, direction: "sent" })), ...(receivedChallengeResult.data ?? []).map((row) => ({ ...row, direction: "received" }))]
      .sort((left, right) => String(right.updated_at).localeCompare(String(left.updated_at))),
    cosmetics: { count: cosmeticResult.count ?? 0, items: cosmeticResult.data ?? [] },
    group: safeGroup,
    market: marketResult.data,
    matches: matchResult.data ?? [],
    members: memberResult.data ?? [],
    players,
    trial: {
      limit: FREE_TRIAL_MATCH_LIMIT,
      remaining: Math.max(0, FREE_TRIAL_MATCH_LIMIT - (groupResult.data.billing_trial_finalized_matches ?? 0)),
      used: groupResult.data.billing_trial_finalized_matches ?? 0,
    },
  };
}

function matchMetadata(payload: unknown, matchId: string) {
  const match = asArray(asRecord(payload).matches).map(asRecord).find((item) => item.id === matchId);
  return match ? {
    date: typeof match.date === "string" ? match.date : null,
    kind: typeof match.kind === "string" ? match.kind : null,
    place: typeof match.place === "string" ? match.place : null,
    title: typeof match.title === "string" ? match.title : `Partido ${matchId}`,
  } : { date: null, kind: null, place: null, title: `Partido ${matchId}` };
}

export async function listPlatformMatches(
  session: VerifiedPlatformSession,
  input: {
    dateFrom?: string;
    dateTo?: string;
    groupId?: string;
    page: number;
    pageSize: number;
    query?: string;
    scope?: string;
    sort?: string;
    state?: string;
    type?: string;
  },
) {
  const allowedScope = new Set(["all", "challenge", "internal"]);
  const allowedSort = new Set(["date_asc", "date_desc", "state_asc", "updated_desc"]);
  const allowedState = new Set([
    "all", "annulled", "auto_confirmed", "cancelled", "change_proposed", "confirmed",
    "disputed", "draft", "finalized", "historical", "lineup_closed", "lineup_open",
    "needs_scorer_fix", "pending_rival", "played", "published", "unverified",
  ]);
  const allowedType = new Set(["all", "futbol11", "futbol7", "sala"]);
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const date = (value?: string) => /^\d{4}-\d{2}-\d{2}$/.test(value ?? "") ? value : null;
  const data = await rpcOrThrow<JsonRecord>(session.client, "list_pachanga_platform_matches_v1", {
    date_from: date(input.dateFrom),
    date_to: date(input.dateTo),
    page_offset: (input.page - 1) * input.pageSize,
    page_size: input.pageSize,
    scope_filter: allowedScope.has(input.scope ?? "all") ? input.scope ?? "all" : "all",
    search_text: safeSearch(input.query),
    sort_key: allowedSort.has(input.sort ?? "date_asc") ? input.sort ?? "date_asc" : "date_asc",
    state_filter: allowedState.has(input.state ?? "all") ? input.state ?? "all" : "all",
    team_filter: uuidPattern.test(input.groupId ?? "") ? input.groupId : null,
    type_filter: allowedType.has(input.type ?? "all") ? input.type ?? "all" : "all",
  });
  const items = asArray(data.items).map((value) => {
    const row = asRecord(value);
    return {
      challenge_id: typeof row.challengeId === "string" ? row.challengeId : null,
      date: typeof row.date === "string" ? row.date : null,
      group_id: String(row.groupId ?? ""),
      groupName: String(row.groupName ?? "Equipo"),
      lineup_closed: Boolean(row.lineupClosed),
      match_id: String(row.matchId ?? ""),
      match_state: String(row.state ?? "draft"),
      match_version: Number(row.revision) || 0,
      modality: typeof row.modality === "string" ? row.modality : null,
      place: typeof row.place === "string" ? row.place : null,
      scope: String(row.scope ?? "internal"),
      score_a: row.scoreA == null ? null : Number(row.scoreA),
      score_b: row.scoreB == null ? null : Number(row.scoreB),
      secondaryGroupId: typeof row.secondaryGroupId === "string" ? row.secondaryGroupId : null,
      secondaryGroupName: typeof row.secondaryGroupName === "string" ? row.secondaryGroupName : null,
      teamCode: typeof row.teamCode === "string" ? row.teamCode : null,
      title: String(row.title ?? "Partido"),
      updated_at: typeof row.updatedAt === "string" ? row.updatedAt : null,
    };
  });
  return {
    items,
    page: input.page,
    pageSize: input.pageSize,
    total: Number(data.total) || 0,
  };
}

export async function listPlatformChallenges(
  session: VerifiedPlatformSession,
  input: {
    dateFrom?: string;
    dateTo?: string;
    groupId?: string;
    page: number;
    pageSize: number;
    query?: string;
    sort?: string;
    status?: string;
  },
) {
  const allowedSort = new Set(["created_desc", "date_asc", "date_desc", "updated_desc"]);
  const allowedStatus = new Set(["accepted", "all", "cancelled", "changes_proposed", "expired", "proposed", "rejected"]);
  const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const date = (value?: string) => /^\d{4}-\d{2}-\d{2}$/.test(value ?? "") ? value : null;
  const data = await rpcOrThrow<JsonRecord>(session.client, "list_pachanga_platform_challenges_v1", {
    date_from: date(input.dateFrom),
    date_to: date(input.dateTo),
    page_offset: (input.page - 1) * input.pageSize,
    page_size: input.pageSize,
    search_text: safeSearch(input.query),
    sort_key: allowedSort.has(input.sort ?? "updated_desc") ? input.sort ?? "updated_desc" : "updated_desc",
    status_filter: allowedStatus.has(input.status ?? "all") ? input.status ?? "all" : "all",
    team_filter: uuidPattern.test(input.groupId ?? "") ? input.groupId : null,
  });
  const items = asArray(data.items).map((value) => {
    const row = asRecord(value);
    const sender = asRecord(row.sender);
    const receiver = asRecord(row.receiver);
    return {
      accepted_at: row.acceptedAt,
      cancelled_at: row.cancelledAt,
      created_at: row.createdAt,
      expired_at: row.expiredAt,
      field_name: row.fieldName,
      id: String(row.id ?? ""),
      last_proposed_by_group_id: row.lastProposedByGroupId,
      modality: row.modality,
      proposal_number: Number(row.proposalNumber) || 0,
      receiver: { id: receiver.id, name: receiver.name, team_code: receiver.teamCode },
      receiver_group_id: String(row.receiverGroupId ?? ""),
      rejected_at: row.rejectedAt,
      revision: Number(row.revision) || 0,
      scheduled_at: row.scheduledAt,
      sender: { id: sender.id, name: sender.name, team_code: sender.teamCode },
      sender_group_id: String(row.senderGroupId ?? ""),
      status: String(row.status ?? "proposed"),
      updated_at: row.updatedAt,
    };
  });
  return {
    items,
    page: input.page,
    pageSize: input.pageSize,
    total: Number(data.total) || 0,
  };
}

function sanitizedNotificationRows(rows: unknown[] | null) {
  return (rows ?? []).map((value) => {
    const row = asRecord(value);
    return {
      category: row.category,
      created_at: row.created_at,
      id: row.id,
      kind: row.kind,
      priority: row.priority,
      read_at: row.read_at,
      server_sequence: row.server_sequence,
      title: row.title,
    };
  });
}

export async function getPlatformMatchDetail(
  _session: VerifiedPlatformSession,
  groupId: string,
  matchId: string,
) {
  const service = platformServiceClient();
  const [matchResult, groupResult, participantsResult, scorersResult, ratingResult, ratingParticipantsResult, factResult, notificationResult] = await Promise.all([
    service.from("pachanga_match_read_model")
      .select("group_id,match_id,match_state,match_version,configured,lineup_closed,finalized,target_players,reserve_limit,payer_player_id,score_a,score_b,source_payload_revision,updated_at")
      .eq("group_id", groupId).eq("match_id", matchId).maybeSingle(),
    service.from("pachanga_groups").select("id,name,team_code,payload,payload_revision").eq("id", groupId).maybeSingle(),
    service.from("pachanga_match_participants").select("player_id,status,seat_kind,joined_at,paid,updated_at").eq("group_id", groupId).eq("match_id", matchId).order("joined_at", { ascending: true }),
    service.from("pachanga_match_scorers").select("player_id,goals,updated_at").eq("group_id", groupId).eq("match_id", matchId).order("goals", { ascending: false }),
    service.from("pachanga_match_rating_snapshots").select("group_level,lineup_a_level,lineup_b_level,engine_version,state,voided_at,void_reason,finalized_at").eq("group_id", groupId).eq("match_id", matchId).maybeSingle(),
    service.from("pachanga_match_rating_participants").select("local_player_id,player_profile_id,guest_identity_id,team_side,attendance_confirmed,was_reserve,card_snapshot,created_at").eq("group_id", groupId).eq("match_id", matchId).order("created_at", { ascending: true }),
    service.from("pachanga_progression_match_facts").select("id,source_kind,source_match_id,source_revision,source_event_id,match_scope,outcome,goals_for,goals_against,clean_sheet,close_win,big_win,scoreless_draw,player_facts_complete,state,server_sequence,played_at,applied_at,revoked_at,revoked_reason").eq("group_id", groupId).eq("source_match_id", matchId).order("server_sequence", { ascending: false }).limit(1),
    service.from("pachanga_user_notifications").select("id,kind,title,category,priority,read_at,server_sequence,created_at").contains("payload", { groupId, matchId }).order("server_sequence", { ascending: false }).limit(40),
  ]);
  for (const result of [matchResult, groupResult, participantsResult, scorersResult, ratingResult, ratingParticipantsResult, factResult, notificationResult]) {
    if (result.error) throw new Error(result.error.message);
  }
  if (!matchResult.data || !groupResult.data) throw new Error("Match not found");
  const fact = factResult.data?.[0] ?? null;
  const achievementResult = fact
    ? await service.from("pachanga_achievement_grants").select("id,definition_id,subject_type,subject_id,metric_value,state,awarded_at,occurred_at,is_first,sequence_count").eq("origin_match_fact_id", fact.id).order("awarded_at", { ascending: true })
    : { data: [], error: null };
  if (achievementResult.error) throw new Error(achievementResult.error.message);
  const grantIds = (achievementResult.data ?? []).map((row) => row.id);
  const rewardResult = grantIds.length
    ? await service.from("pachanga_reward_grants").select("id,achievement_grant_id,reward_kind,reward_key,group_id,player_profile_id,state,granted_at,revoked_at").in("achievement_grant_id", grantIds).order("granted_at", { ascending: true })
    : { data: [], error: null };
  if (rewardResult.error) throw new Error(rewardResult.error.message);
  return {
    achievements: achievementResult.data ?? [],
    group: { id: groupResult.data.id, name: groupResult.data.name, payload_revision: groupResult.data.payload_revision, team_code: groupResult.data.team_code },
    match: { ...matchResult.data, ...matchMetadata(groupResult.data.payload, matchId) },
    notifications: sanitizedNotificationRows(notificationResult.data),
    participants: participantsResult.data ?? [],
    progressionFact: fact,
    ratingParticipants: ratingParticipantsResult.data ?? [],
    ratingSnapshot: ratingResult.data,
    rewards: rewardResult.data ?? [],
    scorers: scorersResult.data ?? [],
  };
}

function sanitizeChallengeSnapshot(value: unknown) {
  const snapshot = asRecord(value);
  return {
    fieldName: typeof snapshot.fieldName === "string" ? snapshot.fieldName : null,
    modality: typeof snapshot.modality === "string" ? snapshot.modality : null,
    proposalNumber: Number(snapshot.proposalNumber) || null,
    scheduledAt: typeof snapshot.scheduledAt === "string" ? snapshot.scheduledAt : null,
    status: typeof snapshot.status === "string" ? snapshot.status : null,
  };
}

export async function getPlatformChallengeDetail(_session: VerifiedPlatformSession, challengeId: string) {
  const service = platformServiceClient();
  const challengeResult = await service.from("pachanga_team_challenges")
    .select("id,sender_group_id,receiver_group_id,status,revision,proposal_number,scheduled_at,modality,field_name,field_address,field_maps_url,last_proposed_by_group_id,accepted_at,rejected_at,cancelled_at,expired_at,created_at,updated_at")
    .eq("id", challengeId).maybeSingle();
  if (challengeResult.error) throw new Error(challengeResult.error.message);
  if (!challengeResult.data) throw new Error("Challenge not found");
  const challenge = challengeResult.data;
  const [groupsResult, timelineResult, externalMatchResult, notificationResult] = await Promise.all([
    service.from("pachanga_groups").select("id,name,team_code").in("id", [challenge.sender_group_id, challenge.receiver_group_id]),
    service.from("pachanga_team_challenge_events").select("id,operation_id,actor_group_id,event_type,challenge_revision,server_sequence,created_at,snapshot").eq("challenge_id", challengeId).order("server_sequence", { ascending: true }),
    service.from("pachanga_external_matches").select("id,home_group_id,away_group_id,scheduled_at,modality,state,revision,active_version,official_version,proposed_by_group_id,pending_response_from_group_id,initial_proposal_at,response_deadline,reminder_sent_at,auto_confirmation_blocked,canonical_score_home,canonical_score_away,canonical_unassigned_home,canonical_unassigned_away,official_at,disputed_at,cancelled_at,server_sequence,created_at,updated_at").eq("challenge_id", challengeId).maybeSingle(),
    service.from("pachanga_user_notifications").select("id,kind,title,category,priority,read_at,server_sequence,created_at").contains("payload", { challengeId }).order("server_sequence", { ascending: false }).limit(40),
  ]);
  for (const result of [groupsResult, timelineResult, externalMatchResult, notificationResult]) if (result.error) throw new Error(result.error.message);
  const externalMatch = externalMatchResult.data;
  const [versionsResult, resultEventsResult, attestationsResult, progressionResult] = externalMatch ? await Promise.all([
    service.from("pachanga_external_result_versions").select("version,previous_version,proposal_kind,proposed_by_group_id,score_home,score_away,operation_id,created_at").eq("external_match_id", externalMatch.id).order("version", { ascending: true }),
    service.from("pachanga_external_result_events").select("id,operation_id,actor_group_id,event_type,match_revision,result_version,server_sequence,created_at").eq("external_match_id", externalMatch.id).order("server_sequence", { ascending: true }),
    service.from("pachanga_external_result_attestations").select("id,result_version,group_id,decision,operation_id,participant_count,scorer_total,created_at").eq("external_match_id", externalMatch.id).order("created_at", { ascending: true }).order("id", { ascending: true }),
    service.from("pachanga_progression_match_facts").select("id,source_kind,source_match_id,source_revision,outcome,goals_for,goals_against,state,server_sequence,played_at,applied_at,revoked_at").eq("source_match_id", externalMatch.id).order("server_sequence", { ascending: false }),
  ]) : [{ data: [], error: null }, { data: [], error: null }, { data: [], error: null }, { data: [], error: null }];
  for (const result of [versionsResult, resultEventsResult, attestationsResult, progressionResult]) if (result.error) throw new Error(result.error.message);
  const groups = new Map((groupsResult.data ?? []).map((group) => [String(group.id), group]));
  return {
    attestations: attestationsResult.data ?? [],
    challenge,
    externalMatch,
    groups: {
      receiver: groups.get(challenge.receiver_group_id) ?? null,
      sender: groups.get(challenge.sender_group_id) ?? null,
    },
    notifications: sanitizedNotificationRows(notificationResult.data),
    progression: progressionResult.data ?? [],
    resultEvents: resultEventsResult.data ?? [],
    timeline: (timelineResult.data ?? []).map((event) => ({ ...event, snapshot: sanitizeChallengeSnapshot(event.snapshot) })),
    versions: versionsResult.data ?? [],
  };
}

export async function getPlatformSection(session: VerifiedPlatformSession, section: string, page: number, pageSize: number) {
  return rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_section_v1", {
    page_offset: (page - 1) * pageSize,
    page_size: pageSize,
    section_key: section,
  });
}

export async function getPlatformFlags(session: VerifiedPlatformSession) {
  const result = await rpcOrThrow<unknown>(session.client, "get_pachanga_platform_flags_v1");
  return asArray(result).map(asRecord);
}

export async function getPlatformDatabaseHealth(session: VerifiedPlatformSession) {
  return rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_database_health_v1");
}

export async function getRankingAdminOverview(session: VerifiedPlatformSession) {
  return rpcOrThrow<JsonRecord>(session.client, "get_pachanga_ranking_admin_overview_v1");
}

export async function getPlatformCompetitionFoundation(
  session: VerifiedPlatformSession,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_competition_foundation_v2",
    {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
    },
  );
  return {
    bindingHealth: asRecord(data.bindingHealth),
    entitlements: asArray(data.entitlements).map(asRecord),
    events: asArray(data.events).map(asRecord),
    flags: asRecord(data.flags),
    items: asArray(data.items).map(asRecord),
    metrics: asRecord(data.metrics),
    page,
    pageSize,
    reviews: asArray(data.reviews).map(asRecord),
    total: Number(data.total) || 0,
  };
}

export async function getPlatformTournamentControl(session: VerifiedPlatformSession) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_tournament_control_v1",
  );
  return {
    flags: asRecord(data.flags),
    grants: asArray(data.grants).map(asRecord),
    health: asRecord(data.health),
    metrics: asRecord(data.metrics),
    recentPlans: asArray(data.recentPlans).map(asRecord),
    updatedAt: typeof data.updatedAt === "string" ? data.updatedAt : null,
  };
}

export async function getPlatformLeagueParticipation(
  session: VerifiedPlatformSession,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_league_participation_v1",
    {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
    },
  );
  return {
    errors: asArray(data.errors).map(asRecord),
    events: asArray(data.events).map(asRecord),
    flags: asRecord(data.flags),
    items: asArray(data.items).map(asRecord),
    metrics: asRecord(data.metrics),
    page,
    pageSize,
    total: Number(data.total) || 0,
  };
}

export async function getPlatformLeagueScheduling(
  session: VerifiedPlatformSession,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_league_scheduling_v1",
    {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
    },
  );
  return {
    flags: asRecord(data.flags),
    items: asArray(data.items).map(asRecord),
    legacyCanonicalHealth: asRecord(data.legacyCanonicalHealth),
    metrics: asRecord(data.metrics),
    page,
    pageSize,
    total: Number(data.total) || 0,
  };
}

export async function getPlatformLeagueMatchOperations(
  session: VerifiedPlatformSession,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_league_match_operations_v1",
    {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
    },
  );
  return {
    counts: asRecord(data.counts),
    flags: asRecord(data.flags),
    matches: asArray(data.matches).map(asRecord),
    recentRebuilds: asArray(data.recentRebuilds).map(asRecord),
    standingsHealth: asArray(data.standingsHealth).map(asRecord),
  };
}

export async function getPlatformLeagueOperationalExceptions(
  session: VerifiedPlatformSession,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_league_operational_exceptions_v1",
    {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
    },
  );
  return {
    counts: asRecord(data.counts),
    flags: asRecord(data.flags),
    health: asRecord(data.health),
    recent: asArray(data.recent).map(asRecord),
  };
}

export async function getPlatformLeaguePrivateBeta(
  session: VerifiedPlatformSession,
  search: string,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_league_private_beta_v1",
    {
      page_offset: (page - 1) * pageSize,
      page_size: pageSize,
      search_text: search,
    },
  );
  return {
    bundles: asArray(data.bundles).map(asRecord),
    competitions: asArray(data.competitions).map(asRecord),
    events: asArray(data.events).map(asRecord),
    flags: asRecord(data.flags),
    foundation: asRecord(data.foundation),
    metrics: asRecord(data.metrics),
    organizers: asArray(data.organizers).map(asRecord),
    page,
    pageSize,
    total: Number(data.total) || 0,
  };
}

export async function getPlatformCompetitionConfiguration(session: VerifiedPlatformSession) {
  const data = await rpcOrThrow<JsonRecord>(
    session.client,
    "get_pachanga_platform_competition_configuration_v1",
  );
  return {
    drafts: asArray(data.drafts).map(asRecord),
    events: asArray(data.events).map(asRecord),
    flags: asRecord(data.flags),
    metrics: asRecord(data.metrics),
    revisions: asArray(data.revisions).map(asRecord),
    unavailable: asArray(data.unavailable).map(String),
  };
}

export async function getPlatformClubs(
  session: VerifiedPlatformSession,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_clubs_v1", {
    page_offset: (page - 1) * pageSize,
    page_size: pageSize,
  });
  return {
    events: asArray(data.recentEvents).map(asRecord),
    flags: asRecord(data.flags),
    items: asArray(data.items).map(asRecord),
    metrics: asRecord(data.metrics),
    page,
    pageSize,
    total: Number(data.total) || 0,
  };
}

export async function getPlatformClub(session: VerifiedPlatformSession, clubId: string) {
  const data = await rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_club_v1", {
    target_club_id: clubId,
  });
  return {
    capabilities: asRecord(data.capabilities),
    club: asRecord(data.club),
    competitions: asArray(data.competitions).map(asRecord),
    entitlements: asRecord(data.entitlements),
    memberships: asArray(data.memberships).map(asRecord),
    pendingInvitations: asArray(data.pendingInvitations).map(asRecord),
    recentEvents: asArray(data.recentEvents).map(asRecord),
    teamRelationships: asArray(data.teamRelationships).map(asRecord),
  };
}

export async function getPlatformReferees(
  session: VerifiedPlatformSession,
  filters: JsonRecord,
  page: number,
  pageSize: number,
) {
  const data = await rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_referees_v1", {
    target_filters: filters,
    target_page: page,
    target_page_size: pageSize,
  });
  return {
    flags: asRecord(data.flags),
    items: asArray(data.items).map(asRecord),
    page: Number(data.page) || page,
    pageSize: Number(data.pageSize) || pageSize,
    total: Number(data.total) || 0,
  };
}

export async function getPlatformReferee(session: VerifiedPlatformSession, profileId: string) {
  const data = await rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_referee_v1", {
    target_profile_id: profileId,
  });
  return {
    areas: asArray(data.areas).map(asRecord),
    assignments: asArray(data.assignments).map(asRecord),
    availability: asRecord(data.availability),
    capabilities: asRecord(data.capabilities),
    events: asArray(data.events).map(asRecord),
    modalities: asArray(data.modalities).map(asRecord),
    profile: asRecord(data.profile),
    relationships: asArray(data.relationships).map(asRecord),
    statistics: asRecord(data.statistics),
  };
}

export async function getPlatformRefereeHealth(session: VerifiedPlatformSession) {
  return rpcOrThrow<JsonRecord>(session.client, "get_pachanga_platform_referee_health_v1");
}
