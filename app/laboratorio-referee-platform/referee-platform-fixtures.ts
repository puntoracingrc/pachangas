import type { RefereeJson } from "../referee-platform-contract";

const modalities: RefereeJson[] = [
  { active: true, modality: "FOOTBALL_7" },
  { active: true, modality: "FUTSAL" },
];

const areas: RefereeJson[] = [
  { countryCode: "ES", generalArea: "Barcelona", municipality: "Barcelona", province: "Barcelona", status: "active", travelRadiusKm: 28 },
  { countryCode: "ES", generalArea: "Vallès Occidental", municipality: "Sabadell", province: "Barcelona", status: "active", travelRadiusKm: 20 },
];

const clubs: RefereeJson[] = [
  { clubName: "Atlètic Nord", id: "00000000-0000-0000-0000-00000000c311", initiatedBy: "club", relationshipType: "PREFERRED", revision: 4, showOnRefereeProfile: true, status: "active" },
  { clubName: "Club Esportiu Raval", id: "00000000-0000-0000-0000-00000000c312", initiatedBy: "referee", relationshipType: "COLLABORATOR", revision: 2, showOnRefereeProfile: true, status: "active" },
];

const windows: RefereeJson[] = [
  { endLocalTime: "22:30", publicVisible: true, startLocalTime: "18:00", status: "active", timezone: "Europe/Madrid", weekday: 3 },
  { endLocalTime: "20:00", publicVisible: true, startLocalTime: "09:00", status: "active", timezone: "Europe/Madrid", weekday: 6 },
];

export const refereePublicFixture: RefereeJson = {
  areas,
  availabilityStatus: "AVAILABLE",
  availabilityWindows: windows,
  avatar: "",
  bio: "Árbitra de fútbol 7 y fútbol sala con experiencia en ligas sociales y torneos de Club.",
  clubs: clubs.map((club) => ({ name: club.clubName, relationshipType: club.relationshipType, slug: String(club.clubName).toLowerCase().replaceAll(" ", "-") })),
  displayName: "Laura Martínez",
  experienceSinceYear: 2018,
  experienceSummary: "Gestión cercana del partido, comunicación clara y disponibilidad en Barcelona y Vallès.",
  marketplaceStatus: "listed",
  modalities,
  operationalStatus: "active",
  refereeProfileId: "00000000-0000-0000-0000-00000000f301",
  slug: "laura-martinez",
  statistics: { disciplineStatsStatus: "NOT_AVAILABLE", matchesCompleted: 86, revision: 14 },
  verificationStatus: "verified",
  visibility: "public",
};

const secondPublicFixture: RefereeJson = {
  ...refereePublicFixture,
  areas: [areas[0]],
  availabilityStatus: "LIMITED",
  displayName: "Marc Vidal",
  experienceSinceYear: 2021,
  refereeProfileId: "00000000-0000-0000-0000-00000000f302",
  slug: "marc-vidal",
  statistics: { disciplineStatsStatus: "NOT_AVAILABLE", matchesCompleted: 31, revision: 8 },
  verificationStatus: "pending",
};

const thirdPublicFixture: RefereeJson = {
  ...refereePublicFixture,
  areas: [areas[1]],
  availabilityStatus: "AVAILABLE",
  displayName: "Nuria Soler",
  experienceSinceYear: 2015,
  modalities: [{ active: true, modality: "FOOTBALL_11" }, { active: true, modality: "FOOTBALL_7" }],
  refereeProfileId: "00000000-0000-0000-0000-00000000f303",
  slug: "nuria-soler",
  statistics: { disciplineStatsStatus: "NOT_AVAILABLE", matchesCompleted: 142, revision: 22 },
};

export const refereeMarketFixtures = [refereePublicFixture, secondPublicFixture, thirdPublicFixture];

export function refereePrivateFixture(status: "confirmed" | "proposed" = "proposed"): RefereeJson {
  const assignment: RefereeJson = {
    assignmentRole: "MAIN_REFEREE",
    bindingStatus: "active",
    canonicalMatchId: "00000000-0000-0000-0000-00000000c301",
    homeTeamName: "Atlètic Nord",
    id: "00000000-0000-0000-0000-00000000a301",
    matchTitle: "Atlètic Nord vs Raval United",
    modality: "FOOTBALL_7",
    requesterKind: "TEAM",
    requesterName: "Atlètic Nord",
    revision: status === "confirmed" ? 3 : 1,
    scheduledEnd: "2026-08-26T20:30:00.000Z",
    scheduledStart: "2026-08-26T19:00:00.000Z",
    sourceKind: "group_match",
    status,
    timezone: "Europe/Madrid",
    venueName: "Can Caralleu",
    zone: "Barcelona",
  };

  return {
    flags: {
      assignmentsEnabled: true,
      clubRelationshipsEnabled: true,
      foundationEnabled: true,
      marketplaceEnabled: true,
      publicProfilesEnabled: true,
      selfServiceEnabled: true,
    },
    pendingInvitations: [],
    profile: {
      areas,
      assignments: [assignment],
      availabilityExceptions: [],
      availabilityWindows: windows,
      modalities,
      profile: {
        ...refereePublicFixture,
        availableForAssignments: true,
        id: refereePublicFixture.refereeProfileId,
        revision: 14,
        shareRecurringAvailability: true,
      },
      relationships: clubs,
      statistics: refereePublicFixture.statistics,
    },
  };
}
