export type CanonicalContract = {
  area: string;
  classification: "implemented" | "implemented_lab" | "not_implemented" | "partially_implemented";
  execution: "product_rpc" | "product_table_rls" | "product_trigger" | "synthetic_adapter" | "unavailable";
  flow: string;
  route: string | null;
  timeInjectable: boolean;
};

export const CANONICAL_CONTRACTS: CanonicalContract[] = [
  { area: "teams", classification: "implemented", execution: "product_table_rls", flow: "team.create", route: "pachanga_groups.insert", timeInjectable: false },
  { area: "teams", classification: "implemented", execution: "product_rpc", flow: "team.join", route: "join_pachanga_team", timeInjectable: false },
  { area: "teams", classification: "implemented", execution: "product_rpc", flow: "team.admin_invite", route: "create_pachanga_admin_invite", timeInjectable: false },
  { area: "teams", classification: "not_implemented", execution: "unavailable", flow: "team.leave", route: null, timeInjectable: false },
  { area: "market", classification: "implemented", execution: "product_rpc", flow: "market.player_profile", route: "sync_pachanga_market_profile_authoritative_v2", timeInjectable: false },
  { area: "market", classification: "implemented", execution: "product_rpc", flow: "market.open_match", route: "sync_pachanga_open_match_authoritative_v2", timeInjectable: false },
  { area: "challenges", classification: "implemented", execution: "product_rpc", flow: "challenge.create", route: "create_pachanga_team_challenge_authoritative", timeInjectable: false },
  { area: "challenges", classification: "implemented", execution: "product_rpc", flow: "challenge.respond", route: "respond_pachanga_team_challenge_authoritative", timeInjectable: false },
  { area: "challenges", classification: "not_implemented", execution: "unavailable", flow: "challenge.expire", route: null, timeInjectable: false },
  { area: "matches", classification: "implemented", execution: "product_rpc", flow: "match.attendance", route: "patch_pachanga_match_player_status_authoritative_v2", timeInjectable: false },
  { area: "matches", classification: "implemented", execution: "product_rpc", flow: "match.lineup", route: "patch_pachanga_match_lineup_authoritative_v2", timeInjectable: false },
  { area: "matches", classification: "implemented", execution: "product_rpc", flow: "match.finalize", route: "finalize_pachanga_match_authoritative_v2", timeInjectable: false },
  { area: "attendance", classification: "implemented", execution: "product_trigger", flow: "attendance.joined_notification", route: "private.pachanga_notify_attendance_event_v1", timeInjectable: false },
  { area: "attendance", classification: "implemented", execution: "product_trigger", flow: "attendance.cancelled_notification", route: "private.pachanga_notify_attendance_event_v1", timeInjectable: false },
  { area: "attendance", classification: "implemented", execution: "product_trigger", flow: "attendance.injury_notification", route: "private.pachanga_notify_player_availability_v1", timeInjectable: false },
  { area: "attendance", classification: "implemented", execution: "product_trigger", flow: "attendance.recovery_notification", route: "private.pachanga_notify_player_availability_v1", timeInjectable: false },
  { area: "attendance", classification: "implemented", execution: "product_rpc", flow: "attendance.no_show", route: "close_pachanga_match_attendance_v1", timeInjectable: false },
  { area: "attendance", classification: "implemented", execution: "product_rpc", flow: "attendance.no_show_response", route: "respond_pachanga_attendance_fact_v1", timeInjectable: false },
  { area: "attendance", classification: "implemented", execution: "product_rpc", flow: "attendance.no_show_review", route: "resolve_pachanga_attendance_review_v1", timeInjectable: false },
  { area: "conduct", classification: "implemented", execution: "product_rpc", flow: "conduct.guest_withdrawal", route: "leave_pachanga_guest_match_v1", timeInjectable: false },
  { area: "conduct", classification: "implemented", execution: "product_rpc", flow: "conduct.guest_withdrawal.review", route: "review_pachanga_guest_withdrawal_v1", timeInjectable: false },
  { area: "conduct", classification: "implemented", execution: "product_rpc", flow: "conduct.player_report", route: "submit_pachanga_conduct_report_v1", timeInjectable: false },
  { area: "conduct", classification: "implemented", execution: "product_rpc", flow: "conduct.moderation", route: "moderate_pachanga_conduct_case_v1", timeInjectable: false },
  { area: "conduct", classification: "implemented", execution: "product_rpc", flow: "conduct.appeal", route: "appeal_pachanga_conduct_action_v1", timeInjectable: false },
  { area: "conduct", classification: "implemented", execution: "product_rpc", flow: "conduct.social_sanction", route: "moderate_pachanga_conduct_case_v1", timeInjectable: false },
  { area: "results", classification: "implemented", execution: "product_rpc", flow: "result.publish", route: "publish_pachanga_external_result_v1", timeInjectable: false },
  { area: "results", classification: "implemented", execution: "product_rpc", flow: "result.confirm", route: "confirm_pachanga_external_result_v1", timeInjectable: false },
  { area: "results", classification: "implemented", execution: "product_rpc", flow: "result.reject", route: "reject_pachanga_external_result_change_v1", timeInjectable: false },
  { area: "results", classification: "implemented", execution: "product_rpc", flow: "result.counter", route: "propose_pachanga_external_result_change_v1", timeInjectable: false },
  { area: "results", classification: "partially_implemented", execution: "product_rpc", flow: "result.auto_confirm", route: "run_pachanga_external_result_expiry_v1", timeInjectable: false },
  { area: "rating", classification: "implemented", execution: "product_rpc", flow: "rating.assessment", route: "persist_pachanga_player_assessment_authoritative_v2", timeInjectable: false },
  { area: "rating", classification: "implemented", execution: "product_rpc", flow: "rating.peer", route: "record_pachanga_individual_rating_authoritative_v2", timeInjectable: false },
  { area: "achievements", classification: "implemented", execution: "product_trigger", flow: "achievement.evaluate", route: "pachanga_evaluate_achievements_v1", timeInjectable: false },
  { area: "rewards", classification: "implemented", execution: "product_rpc", flow: "reward.open_box", route: "open_pachanga_reward_box_v2", timeInjectable: false },
  { area: "notifications", classification: "implemented", execution: "product_rpc", flow: "notification.read", route: "mark_pachanga_notification_read_v1", timeInjectable: false },
  { area: "notifications", classification: "implemented", execution: "product_rpc", flow: "notification.preferences", route: "update_pachanga_notification_preferences_v1", timeInjectable: false },
  { area: "ranking", classification: "implemented_lab", execution: "synthetic_adapter", flow: "ranking.season_score_v3", route: "evaluateV3Ranking", timeInjectable: true },
  { area: "integrity", classification: "implemented_lab", execution: "synthetic_adapter", flow: "integrity.exclusion_and_hold", route: "enrichCompetitiveEvidence", timeInjectable: true },
];

export function canonicalContract(flow: string) {
  return CANONICAL_CONTRACTS.find((contract) => contract.flow === flow) ?? null;
}
