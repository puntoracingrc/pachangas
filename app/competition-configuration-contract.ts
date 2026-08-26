import { leagueBetaArray, leagueBetaBoolean, leagueBetaNumber, leagueBetaRecord, leagueBetaText, type LeaguePrivateBetaJson } from "./league-private-beta-contract";

export const competitionConfigurationActions = [
  "draft.create",
  "draft.clone",
  "draft.mode.set",
  "draft.preset.apply",
  "draft.section.save",
  "draft.validate",
  "draft.publish",
  "draft.cancel",
] as const;

export type CompetitionConfigurationAction = typeof competitionConfigurationActions[number];
export type CompetitionConfigurationJson = LeaguePrivateBetaJson;

export const competitionConfigurationRealtimeTable = "pachanga_competition_configuration_invalidations";
export const competitionConfigurationCacheVersion = 1;

const actions = new Set<string>(competitionConfigurationActions);

export function isCompetitionConfigurationAction(value: string): value is CompetitionConfigurationAction {
  return actions.has(value);
}

export {
  leagueBetaArray as configurationArray,
  leagueBetaBoolean as configurationBoolean,
  leagueBetaNumber as configurationNumber,
  leagueBetaRecord as configurationRecord,
  leagueBetaText as configurationText,
};

export function configurationHealthTone(value: unknown): "danger" | "info" | "neutral" | "success" | "warning" {
  const status = leagueBetaText(value).toLowerCase();
  if (["complete", "published", "frozen", "validated"].includes(status)) return "success";
  if (["invalid", "cancelled"].includes(status)) return "danger";
  if (["incomplete", "registration_open", "registration_closed", "schedule_published"].includes(status)) return "warning";
  if (["draft"].includes(status)) return "info";
  return "neutral";
}
