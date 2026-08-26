export const leaguePrivateBetaActions = [
  "wizard.create",
  "wizard.mode.set",
  "wizard.preset.apply",
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
export const leaguePrivateBetaCacheVersion = 2;
export const leaguePrivateBetaRealtimeTable = "pachanga_league_private_beta_invalidations";

export const leaguePrivateBetaPresets = [
  { key: "LEAGUE_F7_STANDARD", label: "Liga F7 amateur estándar" },
  { key: "LEAGUE_F5_QUICK", label: "Liga F5 rápida" },
  { key: "LEAGUE_F11", label: "Liga F11" },
  { key: "LEAGUE_FUTSAL", label: "Liga de fútbol sala" },
] as const;

export const leaguePrivateBetaSteps = [
  { id: 1, label: "Identidad" },
  { id: 2, label: "Modalidad" },
  { id: 3, label: "Edición y fechas" },
  { id: 4, label: "Formato y equipos" },
  { id: 5, label: "Plantillas y elegibilidad" },
  { id: 6, label: "Partidos y puntuación" },
  { id: 7, label: "Horarios, sedes y descanso" },
  { id: 8, label: "Resultados y desempates" },
  { id: 9, label: "Aplazamientos y no-show" },
  { id: 10, label: "Disciplina" },
  { id: 11, label: "Árbitros" },
  { id: 12, label: "Resumen y publicación" },
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
