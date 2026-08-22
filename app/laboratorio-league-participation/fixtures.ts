import type { LeagueJson } from "../league-participation-contract";

const competitionId = "00000000-0000-4000-8000-00000000a401";
const editionId = "00000000-0000-4000-8000-00000000a402";
const categoryId = "00000000-0000-4000-8000-00000000a403";
const entryId = "00000000-0000-4000-8000-00000000a404";
const rosterId = "00000000-0000-4000-8000-00000000a405";

export const leagueLabIds = { categoryId, competitionId, editionId, entryId, rosterId };

export const leaguePublicFixture: LeagueJson = {
  acceptedTeams: 7,
  categories: [
    { acceptedTeams: 7, description: "Categoría abierta con aprobación del organizador.", id: categoryId, levelLabel: "Intermedio", name: "Open", revision: 3, sportFormat: "Fútbol 7" },
    { acceptedTeams: 4, description: "Edad calculada en la fecha de referencia congelada.", id: "00000000-0000-4000-8000-00000000a413", levelLabel: "+35", name: "Veteranos QA", revision: 2, sportFormat: "Fútbol 7" },
  ],
  competition: { id: competitionId, name: "Liga Metropolitana 2027", slug: "liga-metropolitana-2027", type: "LEAGUE" },
  edition: { id: editionId, name: "Temporada 2027", registrationClosesAt: "2027-02-15T22:59:00Z", registrationMode: "PUBLIC_APPROVAL", seasonLabel: "2027", status: "registration_open" },
  rulesSummary: { roster: "12-18 jugadores", review: "Aprobación manual" },
  serverSequence: 4401,
};

const entryItems = [
  { categoryName: "Open", competitionId, competitionName: "Liga Metropolitana 2027", editionName: "Temporada 2027", eligibilityHealth: { eligible: 11, pending: 1 }, id: entryId, memberCount: 12, revision: 5, rosterStatus: "submitted", serverSequence: 4410, source: "PUBLIC_APPLICATION", status: "submitted", teamId: "00000000-0000-4000-8000-00000000b401", teamName: "Atlètic Nord", updatedAt: "2026-08-22T15:30:00Z" },
  { categoryName: "Open", competitionId, competitionName: "Liga Metropolitana 2027", editionName: "Temporada 2027", eligibilityHealth: { eligible: 14 }, id: "00000000-0000-4000-8000-00000000a414", memberCount: 14, revision: 4, rosterStatus: "approved", serverSequence: 4409, source: "ORGANIZER_INVITATION", status: "accepted", teamId: "00000000-0000-4000-8000-00000000b402", teamName: "Raval United", updatedAt: "2026-08-22T15:15:00Z" },
  { categoryName: "Veteranos QA", competitionId, competitionName: "Liga Metropolitana 2027", editionName: "Temporada 2027", eligibilityHealth: {}, id: "00000000-0000-4000-8000-00000000a415", memberCount: 0, revision: 2, rosterStatus: "draft", serverSequence: 4408, source: "PUBLIC_APPLICATION", status: "rejected", teamId: "00000000-0000-4000-8000-00000000b403", teamName: "Marina 35", updatedAt: "2026-08-22T15:00:00Z" },
];

export const leagueDeskFixture: LeagueJson = {
  competitionId,
  counts: { accepted: 1, rejected: 1, submitted: 1 },
  items: entryItems,
  total: 3,
};

export const leagueMineFixture: LeagueJson = {
  items: entryItems.map((item, index) => ({ ...item, actorScope: index === 0 ? "TEAM_OWNER" : "PRIMARY_DELEGATE", categoryId, editionId, registrationClosesAt: "2027-02-15T22:59:00Z" })),
  total: 3,
};

export const leagueEntryFixture: LeagueJson = {
  actorScope: "TEAM_OWNER",
  availabilityConstraints: [{ endLocalTime: "22:30", id: "00000000-0000-4000-8000-00000000a421", startLocalTime: "20:00", weekday: 1 }],
  category: { id: categoryId, name: "Open", sportFormat: "Fútbol 7" },
  competition: { id: competitionId, name: "Liga Metropolitana 2027", type: "LEAGUE" },
  delegates: [
    { displayName: "Marta Ruiz", id: "00000000-0000-4000-8000-00000000a422", role: "PRIMARY_DELEGATE", status: "active" },
    { displayName: "David León", id: "00000000-0000-4000-8000-00000000a423", role: "ROSTER_MANAGER", status: "active" },
  ],
  edition: { id: editionId, name: "Temporada 2027", seasonLabel: "2027" },
  entry: { id: entryId, revision: 5, status: "accepted", teamId: "00000000-0000-4000-8000-00000000b401", teamName: "Atlètic Nord" },
  nextActions: ["manage_delegates", "manage_roster", "withdraw"],
  roster: { eligibilityHealth: { eligible: 11, pending: 1 }, id: rosterId, memberCount: 12, revision: 5, status: "submitted" },
  schedulePreferences: [{ endLocalTime: "19:30", id: "00000000-0000-4000-8000-00000000a424", startLocalTime: "16:00", weekday: 6, weight: 80 }],
  stageMembership: { divisionName: "División 1", groupName: "Grupo A", stageName: "Liga regular" },
};

export const leagueRosterFixture: LeagueJson = {
  actorScope: "ORGANIZER",
  currentRevision: { eligibilitySummary: { eligible: 3, pending: 1 }, id: "00000000-0000-4000-8000-00000000a431", memberCount: 4, revisionNumber: 5, status: "submitted" },
  history: [
    { id: "00000000-0000-4000-8000-00000000a431", revisionNumber: 5, status: "submitted" },
    { id: "00000000-0000-4000-8000-00000000a432", revisionNumber: 4, status: "draft" },
  ],
  kits: [{ id: "00000000-0000-4000-8000-00000000a433", primaryColor: "#1B8B55", secondaryColor: "#F3F5F7", type: "HOME" }],
  members: [
    { credential: { status: "verified" }, eligibilityStatus: "eligible", id: "00000000-0000-4000-8000-00000000a441", jerseyNumber: 1, player: { displayName: "Álex Mora", position: "POR" } },
    { credential: { status: "verified" }, eligibilityStatus: "eligible", id: "00000000-0000-4000-8000-00000000a442", jerseyNumber: 4, player: { displayName: "Bruno Costa", position: "DEF" } },
    { credential: { status: "verified" }, eligibilityStatus: "eligible", id: "00000000-0000-4000-8000-00000000a443", jerseyNumber: 8, player: { displayName: "Marta Ruiz", position: "MC" } },
    { credential: { status: "pending" }, eligibilityStatus: "pending", id: "00000000-0000-4000-8000-00000000a444", jerseyNumber: 11, player: { displayName: "Izan Gil", position: "DEL" } },
  ],
  roster: { entryId, id: rosterId, revision: 5, status: "submitted" },
};
