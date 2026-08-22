export const leagueParticipationActions = [
  "category.create",
  "category.activate",
  "category.close",
  "category.archive",
  "registration.open",
  "registration.notify_closing",
  "registration.close",
  "registration.close_and_expire_pending",
  "entry.submit",
  "entry.invite",
  "entry.accept",
  "entry.reject",
  "entry.withdraw",
  "entry.decline",
  "delegate.invite",
  "delegate.accept",
  "delegate.decline",
  "delegate.revoke",
  "delegate.primary.transfer",
  "delegate.transfer",
  "roster.create",
  "roster.member.add",
  "roster.member.remove",
  "roster.submit",
  "roster.request_changes",
  "roster.reopen",
  "roster.approve",
  "roster.lock",
  "roster.amend",
  "credential.review",
  "eligibility.waive",
  "kit.set",
  "jersey.assign",
  "stage_membership.assign",
  "availability.set",
  "preference.set",
] as const;

export type LeagueParticipationAction = typeof leagueParticipationActions[number];
export type LeagueJson = Record<string, unknown>;

export const leagueParticipationFlagsAggregateId = "00000000-0000-0000-0000-00000000c4a1";
export const leagueParticipationCacheVersion = 1;
export const leagueParticipationRealtimeTable = "pachanga_competition_invalidations";

const actionSet = new Set<string>(leagueParticipationActions);

export function isLeagueParticipationAction(value: string): value is LeagueParticipationAction {
  return actionSet.has(value);
}

export function leagueRecord(value: unknown): LeagueJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as LeagueJson
    : {};
}

export function leagueArray(value: unknown): LeagueJson[] {
  return Array.isArray(value) ? value.map(leagueRecord) : [];
}

export function leagueText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function leagueNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function leagueStatusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = leagueText(value).toLowerCase();
  if (["accepted", "active", "approved", "eligible", "locked", "verified", "waived"].includes(status)) return "success";
  if (["archived", "declined", "expired", "ineligible", "rejected", "revoked", "withdrawn"].includes(status)) return "danger";
  if (["changes_requested", "invited", "pending", "review_required", "submitted"].includes(status)) return "warning";
  if (["draft", "registration_open"].includes(status)) return "info";
  return "neutral";
}

export function leagueNextActionLabel(value: string) {
  const labels: Record<string, string> = {
    assign_stage: "Asignar fase",
    accept_invitation: "Aceptar invitacion",
    decline_invitation: "Declinar invitacion",
    manage_delegates: "Delegados",
    manage_roster: "Editar plantilla",
    review_entry: "Resolver solicitud",
    review_roster: "Revisar plantilla",
    withdraw: "Retirar inscripción",
  };
  return labels[value] ?? value.replaceAll("_", " ");
}
