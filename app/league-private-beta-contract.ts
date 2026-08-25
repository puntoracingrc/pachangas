export const leaguePrivateBetaActions = [
  "wizard.create",
  "wizard.step.save",
  "wizard.cancel",
  "wizard.finalize",
] as const;

export const leaguePrivateBetaPlatformActions = [
  "beta.flags.set",
  "beta.kill_switch",
  "beta.bundle.grant",
  "beta.bundle.revoke",
] as const;

export type LeaguePrivateBetaAction = typeof leaguePrivateBetaActions[number];
export type LeaguePrivateBetaPlatformAction = typeof leaguePrivateBetaPlatformActions[number];
export type LeaguePrivateBetaJson = Record<string, unknown>;

export const leaguePrivateBetaFlagsAggregateId = "00000000-0000-0000-0000-00000000b201";
export const leaguePrivateBetaCacheVersion = 1;
export const leaguePrivateBetaRealtimeTable = "pachanga_league_private_beta_invalidations";

export const leaguePrivateBetaSteps = [
  { id: 1, label: "Identidad" },
  { id: 2, label: "Modalidad" },
  { id: 3, label: "Edición y fechas" },
  { id: 4, label: "Equipos y registro" },
  { id: 5, label: "Plantillas" },
  { id: 6, label: "Partido y puntuación" },
  { id: 7, label: "Calendario" },
  { id: 8, label: "Resultados" },
  { id: 9, label: "Incidencias" },
  { id: 10, label: "Revisión final" },
] as const;

const actionSet = new Set<string>(leaguePrivateBetaActions);
const platformActionSet = new Set<string>(leaguePrivateBetaPlatformActions);

export function isLeaguePrivateBetaAction(value: string): value is LeaguePrivateBetaAction {
  return actionSet.has(value);
}

export function isLeaguePrivateBetaPlatformAction(value: string): value is LeaguePrivateBetaPlatformAction {
  return platformActionSet.has(value);
}

export function leagueBetaRecord(value: unknown): LeaguePrivateBetaJson {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as LeaguePrivateBetaJson
    : {};
}

export function leagueBetaArray(value: unknown): LeaguePrivateBetaJson[] {
  return Array.isArray(value) ? value.map(leagueBetaRecord) : [];
}

export function leagueBetaText(value: unknown) {
  return typeof value === "string" ? value : "";
}

export function leagueBetaNumber(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

export function leagueBetaBoolean(value: unknown) {
  return value === true;
}

export function leagueBetaStatusTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = leagueBetaText(value).toLowerCase();
  if (["active", "completed", "registration_open", "scheduled"].includes(status)) return "success";
  if (["cancelled", "expired", "incomplete", "revoked"].includes(status)) return "danger";
  if (["registration_closed", "suspended"].includes(status)) return "warning";
  if (["draft", "not_granted"].includes(status)) return "info";
  return "neutral";
}

export function leagueBetaNextActionLabel(value: unknown) {
  const key = leagueBetaText(value);
  const labels: Record<string, string> = {
    configure_registration: "Configurar inscripciones",
    open_league: "Abrir Liga",
    open_match_hub: "Abrir partidos",
    prepare_schedule: "Preparar calendario",
    review_entries: "Revisar equipos",
    review_incidents: "Resolver incidencias",
  };
  return labels[key] ?? "Abrir Liga";
}
