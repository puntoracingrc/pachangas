const v1WriteRpcNames = new Set([
  "accept_pachanga_admin_invite",
  "append_pachanga_player_rating",
  "complete_pachanga_player_advanced_assessment",
  "complete_pachanga_player_initial_assessment",
  "create_pachanga_admin_invite",
  "create_pachanga_group_backup",
  "finalize_pachanga_match_if_current",
  "join_pachanga_team",
  "patch_pachanga_match_lineup_state",
  "patch_pachanga_match_player_paid",
  "patch_pachanga_match_player_status",
  "patch_pachanga_match_scorers",
  "patch_pachanga_player_profile",
  "request_pachanga_open_match",
  "restore_pachanga_group_backup",
  "review_pachanga_open_match_request",
  "save_pachanga_payload_if_current",
  "set_pachanga_member_role",
  "sync_pachanga_market_profile",
  "sync_pachanga_open_match",
  "update_pachanga_member_name",
  "upsert_pachanga_own_player_profile",
]);

const v2WriteRpcNames = new Set([
  "accept_pachanga_admin_invite_authoritative_v1",
  "appeal_pachanga_conduct_action_v1",
  "cancel_pachanga_external_match_v1",
  "cancel_my_pachanga_open_match_request_v1",
  "cancel_pachanga_match_invitation_v1",
  "complete_pachanga_external_scorers_v1",
  "command_pachanga_club_foundation_v1",
  "command_pachanga_club_referee_invite_by_profile_v1",
  "command_pachanga_club_platform_v1",
  "command_pachanga_competition_foundation_v1",
  "command_pachanga_competition_foundation_v2",
  "command_pachanga_competition_configuration_v1",
  "command_pachanga_competition_discipline_platform_v1",
  "command_pachanga_competition_discipline_v1",
  "command_pachanga_competition_platform_v1",
  "command_pachanga_league_participation_platform_v1",
  "command_pachanga_league_participation_v1",
  "command_pachanga_league_match_operations_platform_v1",
  "command_pachanga_league_match_operations_v1",
  "command_pachanga_league_operational_exceptions_platform_v1",
  "command_pachanga_league_operational_exceptions_v1",
  "command_pachanga_league_private_beta_platform_v1",
  "command_pachanga_league_private_beta_r5_bundle_upgrade_v1",
  "command_pachanga_league_private_beta_v1",
  "command_pachanga_league_scheduling_platform_v1",
  "command_pachanga_league_scheduling_v1",
  "command_pachanga_referee_platform_v1",
  "command_pachanga_referee_platform_admin_v1",
  "command_pachanga_referee_assignment_beta_admin_v1",
  "command_pachanga_referee_assignment_beta_v1",
  "command_pachanga_referee_officiating_v1",
  "command_pachanga_referee_incident_observation_v1",
  "command_pachanga_referee_public_fee_v1",
  "command_pachanga_publication_consent_v1",
  "command_pachanga_club_referee_manager_v1",
  "close_pachanga_post_match_attendance_v1",
  "confirm_pachanga_external_result_v1",
  "create_pachanga_team_challenge_authoritative",
  "create_pachanga_match_link_invitation_v1",
  "create_pachanga_match_invitation_v1",
  "ensure_pachanga_external_team_authoritative_v2",
  "finalize_pachanga_match_authoritative_v2",
  "issue_pachanga_guest_rating_token_authoritative_v2",
  "link_pachanga_registered_opponent_authoritative_v2",
  "patch_pachanga_match_lineup_authoritative_v2",
  "patch_pachanga_match_player_paid_authoritative_v2",
  "patch_pachanga_match_player_status_authoritative_v2",
  "patch_pachanga_match_scorers_authoritative_v2",
  "patch_pachanga_player_profile_authoritative_v2",
  "leave_pachanga_guest_match_v1",
  "leave_pachanga_group_authoritative_v1",
  "mark_pachanga_notification_read_v1",
  "mark_pachanga_player_cosmetics_seen_v1",
  "mark_pachanga_team_cosmetics_seen_v1",
  "merge_pachanga_conduct_cases_v1_1",
  "moderate_pachanga_conduct_case_v1",
  "open_pachanga_reward_v1",
  "open_pachanga_reward_box_v2",
  "propose_pachanga_external_result_change_v1",
  "publish_pachanga_external_result_v1",
  "publish_pachanga_team_crest_v1",
  "reconcile_pachanga_referee_assignment_v1",
  "record_pachanga_global_rating_authoritative_v2",
  "record_pachanga_guest_team_rating_token_v2",
  "record_pachanga_individual_rating_authoritative_v2",
  "request_pachanga_open_match_authoritative_v2",
  "remove_pachanga_group_member_authoritative_v1",
  "resolve_pachanga_attendance_review_v1",
  "resolve_pachanga_conduct_appeal_v1",
  "respond_pachanga_post_match_attendance_v1",
  "respond_pachanga_team_challenge_authoritative",
  "reconcile_pachanga_team_challenge_expiry_v1",
  "respond_pachanga_match_link_invitation_v1",
  "respond_pachanga_match_invitation_v1",
  "reject_pachanga_external_result_change_v1",
  "review_pachanga_guest_withdrawal_v1",
  "review_pachanga_open_match_request_authoritative_v2",
  "save_pachanga_payload_authoritative_v2",
  "save_pachanga_player_cosmetic_loadout_v1",
  "save_pachanga_team_shield_loadout_v1",
  "save_pachanga_team_crest_draft_v1",
  "set_pachanga_group_ratings_enabled_authoritative_v2",
  "sync_pachanga_market_profile_authoritative_v2",
  "sync_pachanga_open_match_authoritative_v2",
  "transfer_pachanga_group_ownership_authoritative_v1",
  "submit_pachanga_conduct_report_v1",
  "equip_pachanga_player_cosmetic_from_box_v1",
  "split_pachanga_conduct_case_v1_1",
  "upsert_pachanga_challengeable_team_profile_authoritative",
  "upsert_pachanga_own_player_profile_authoritative_v2",
]);

const clientWriteRpcNames = new Set([...v1WriteRpcNames, ...v2WriteRpcNames]);

const writeMethods = new Set(["DELETE", "PATCH", "POST", "PUT"]);
const v1DirectTableWriteOperations = new Set([
  "table:pachanga_group_members:post",
  "table:pachanga_groups:delete",
  "table:pachanga_groups:post",
]);
const v1ApplicationWriteOperations = new Set([
  "api:billing-checkout",
  "api:billing-portal",
]);
const v2ApplicationWriteOperations = new Set([
  "api:club-foundation-command",
  "api:competition-discipline-command",
  "api:competition-configuration-command",
  "api:league-participation-command",
  "api:league-match-operations-command",
  "api:league-operational-exceptions-command",
  "api:league-scheduling-command",
  "api:league-private-beta-command",
  "api:ratings-assessment",
  "api:platform-admin-clubs",
  "api:platform-admin-competitions",
  "api:platform-admin-league-private-beta",
  "api:platform-admin-referees",
  "api:referee-command",
  "api:referee-assignment-command",
  "api:referee-officiating-command",
  "api:referee-public-fee-command",
]);
const clientApplicationWriteOperations = new Set([
  ...v1ApplicationWriteOperations,
  ...v2ApplicationWriteOperations,
]);

export function requestMethod(input: RequestInfo | URL, init?: RequestInit) {
  if (init?.method) return init.method.toUpperCase();
  if (typeof Request !== "undefined" && input instanceof Request) return input.method.toUpperCase();
  return "GET";
}

export function classifySupabaseWrite(input: RequestInfo | URL, init?: RequestInit) {
  const method = requestMethod(input, init);
  if (!writeMethods.has(method)) return null;

  const rawUrl = typeof input === "string" || input instanceof URL ? String(input) : input.url;
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return null;
  }

  const rpcPrefix = "/rest/v1/rpc/";
  if (url.pathname.startsWith(rpcPrefix)) {
    const rpcName = decodeURIComponent(url.pathname.slice(rpcPrefix.length));
    return clientWriteRpcNames.has(rpcName) ? `rpc:${rpcName}` : null;
  }

  const tablePrefix = "/rest/v1/";
  if (!url.pathname.startsWith(tablePrefix)) return null;
  const tableName = decodeURIComponent(url.pathname.slice(tablePrefix.length)).split("/")[0];
  return tableName ? `table:${tableName}:${method.toLowerCase()}` : null;
}

export function knownV1WriteRpcNames() {
  return [...v1WriteRpcNames].sort();
}

export function knownClientWriteRpcNames() {
  return [...clientWriteRpcNames].sort();
}

export function isKnownClientWriteOperation(operation: string) {
  if (operation.startsWith("rpc:")) return clientWriteRpcNames.has(operation.slice(4));
  return v1DirectTableWriteOperations.has(operation) || clientApplicationWriteOperations.has(operation);
}
