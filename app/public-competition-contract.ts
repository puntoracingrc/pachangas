export type PublicCompetitionJson = Record<string, unknown>;

export const publicCompetitionPublicationActions = [
  "publication.prepare",
  "publication.update",
  "publication.consent",
  "publication.submit",
  "publication.withdraw",
  "publication.unpublish",
  "registration.configure",
] as const;

export const publicCompetitionRegistrationActions = [
  "registration.submit",
  "registration.message.update",
  "registration.withdraw",
  "registration.under_review",
  "registration.waitlist",
  "registration.accept",
  "registration.reject",
  "waitlist.reorder",
  "competition.report",
] as const;

export const publicCompetitionModerationActions = [
  "publication.approve",
  "publication.reject",
  "publication.request_changes",
  "publication.publish",
  "publication.suspend",
  "publication.restore",
  "publication.archive",
  "publication.organizer.verify",
  "report.review",
  "report.resolve",
  "report.dismiss",
] as const;

export type PublicCompetitionPublicationAction = typeof publicCompetitionPublicationActions[number];
export type PublicCompetitionRegistrationAction = typeof publicCompetitionRegistrationActions[number];
export type PublicCompetitionModerationAction = typeof publicCompetitionModerationActions[number];
export type PublicCompetitionAction = PublicCompetitionPublicationAction | PublicCompetitionRegistrationAction;

const publicationActions = new Set<string>(publicCompetitionPublicationActions);
const registrationActions = new Set<string>(publicCompetitionRegistrationActions);
const moderationActions = new Set<string>(publicCompetitionModerationActions);

export const publicCompetitionCacheVersion = 1;
export const publicCompetitionRealtimeTable = "pachanga_competition_invalidations";

export function publicCompetitionRecord(value: unknown): PublicCompetitionJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as PublicCompetitionJson
    : {};
}

export function publicCompetitionArray(value: unknown) {
  return Array.isArray(value) ? value.map(publicCompetitionRecord) : [];
}

export function publicCompetitionText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function publicCompetitionNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function publicCompetitionBoolean(value: unknown) {
  return value === true;
}

export function isPublicCompetitionPublicationAction(value: string): value is PublicCompetitionPublicationAction {
  return publicationActions.has(value);
}

export function isPublicCompetitionRegistrationAction(value: string): value is PublicCompetitionRegistrationAction {
  return registrationActions.has(value);
}

export function isPublicCompetitionModerationAction(value: string): value is PublicCompetitionModerationAction {
  return moderationActions.has(value);
}

export function publicCompetitionTypeLabel(value: unknown) {
  return publicCompetitionText(value).toUpperCase() === "TOURNAMENT" ? "Torneo" : "Liga";
}

export function publicCompetitionSportLabel(value: unknown) {
  const labels: Record<string, string> = {
    FOOTBALL_5: "Fútbol 5",
    FOOTBALL_7: "Fútbol 7",
    FOOTBALL_11: "Fútbol 11",
    FUTBOL_5: "Fútbol 5",
    FUTBOL_7: "Fútbol 7",
    FUTBOL_11: "Fútbol 11",
    FUTSAL: "Fútbol sala",
  };
  const key = publicCompetitionText(value).toUpperCase();
  return labels[key] ?? (publicCompetitionText(value).replaceAll("_", " ") || "Fútbol");
}

export function publicCompetitionStateLabel(value: unknown) {
  const labels: Record<string, string> = {
    UPCOMING: "Próximamente",
    REGISTRATION_OPEN: "Inscripción abierta",
    IN_PROGRESS: "En curso",
    FINISHED: "Finalizada",
  };
  const key = publicCompetitionText(value).toUpperCase();
  return labels[key] ?? (publicCompetitionText(value).replaceAll("_", " ") || "Publicada");
}
