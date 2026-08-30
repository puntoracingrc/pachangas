import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {
  DEMO_WORLD_V32_VERSION,
  SYNTHETIC_SEASON_SEED,
  syntheticSeasonIntegrityErrors,
  syntheticSeasonPrivacyFindings,
} from "../app/demo-world/demo-world-v3-2-contract";
import { buildServiceWorkerSource } from "../app/service-worker-source";
import { generateDemoWorldV2 } from "../scripts/demo-world/generate-demo-world-v2";
import { generateDemoWorldV32 } from "../scripts/demo-world/generate-demo-world-v3-2";
import {
  buildSyntheticSeason,
  syntheticSeasonAuthorityMigrationLedger,
  syntheticSeasonDerivedInvariants,
} from "../simulation/synthetic-season/engine";
import {
  PACHANGAS_PRODUCTION_PROJECT_REF,
  SYNTHETIC_SEASON_CONFIRMATION,
  syntheticSeasonEnvironmentErrors,
} from "../simulation/synthetic-season/environment";
import {
  syntheticSeasonBracketLineageErrors,
  syntheticSeasonMatchSheetErrors,
  syntheticSeasonOracleReport,
} from "../simulation/synthetic-season/oracles";

const root = path.resolve(import.meta.dirname, "..");

function legacyWeekDate(week: number, slot: number) {
  const date = new Date("2026-09-07T18:00:00.000Z");
  date.setUTCDate(date.getUTCDate() + week * 7 + slot % 6);
  date.setUTCHours(18 + slot % 4, slot % 2 ? 30 : 0, 0, 0);
  return date.toISOString();
}

function testHashNumber(value: string) {
  return Number.parseInt(createHash("sha256").update(JSON.stringify(value)).digest("hex").slice(0, 8), 16);
}

test("Synthetic Operations Season V1 is deterministic and stays inside the contracted size", () => {
  const first = buildSyntheticSeason();
  const second = buildSyntheticSeason();
  assert.equal(first.index.proof.authorityHash, second.index.proof.authorityHash);
  assert.equal(first.index.proof.publicSnapshotHash, second.index.proof.publicSnapshotHash);
  assert.deepEqual(first.index.proof.checkpointHashes, second.index.proof.checkpointHashes);
  assert.deepEqual(first.index.proof.counts, {
    challenges: 16,
    checkpoints: 9,
    clubs: 6,
    competitions: 4,
    disciplineEvents: 70,
    faultInjections: 12,
    leagues: 2,
    matchSheets: 256,
    matches: 128,
    notifications: 66,
    organizerApplications: 8,
    organizerGrants: 3,
    organizers: 8,
    players: 480,
    refereeAssignments: 115,
    referees: 12,
    registrationRequests: 38,
    sanctions: 5,
    teams: 32,
    tournaments: 2,
    waitlists: 4,
    weeks: 16,
  });
  assert.deepEqual(syntheticSeasonIntegrityErrors(first.index, first.checkpoints), []);
});

test("hosted reduced season is production guarded and composes the canonical engines", async () => {
  const runner = await readFile(
    path.join(root, "tests/synthetic-operations-season-v1-staging-e2e.mjs"),
    "utf8",
  );
  assert.match(runner, /SYNTHETIC_SEASON_EPHEMERAL_ONLY/);
  assert.match(runner, /qonbngfrnrqgmxbdfbea/);
  assert.match(runner, /SYNTHETIC_SEASON_STAGING_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(runner, /assert\.deepEqual\(initial\.migrations, localMigrationVersions\)/);
  assert.match(runner, /canonicalMatches: 50/);
  assert.match(runner, /clubs: 3/);
  assert.match(runner, /teams: 12/);
  assert.match(runner, /players: 120/);
  assert.match(runner, /referees: 6/);
  assert.match(runner, /leagueMatches: 30/);
  assert.match(runner, /tournamentGroupMatches: 12/);
  assert.match(runner, /tournamentKnockoutMatches: 8/);
  assert.match(runner, /participantCap\\\":16\", \"participantCap\\\":12\", 3, \"participant-cap\"/);
  assert.match(runner, /expectMarker\(source, "generate_series\(1, 6\) slot_number", 1, "three-round-rest-safe-slots"\)/);
  assert.doesNotMatch(runner, /generate_series\(1, 6\) slot_number", "generate_series\(1, 3\) slot_number/);
  assert.match(runner, /"if match_row\.ordinal = 11 then", "if match_row\.ordinal = 5 then", 1, "reduced-suspension-scenario"/);
  assert.match(runner, /"if match_row\.ordinal = 14 then", "if match_row\.ordinal = 6 then", 1, "reduced-dispute-scenario"/);
  assert.match(runner, /psql\(\["-v", "DEMO_WORLD_V2_PERSIST=1"\], "operate twelve-team Tournament group stage"/);
  assert.match(runner, /\["DW00004", "DW00005", 1, "discipline-source-team"\]/);
  assert.match(runner, /\["demo-world-v2-5-player-profile-4-1", "demo-world-v2-5-player-profile-5-1", 4, "discipline-source-player"\]/);
  assert.match(runner, /W8C_STAGING_REALTIME_TIMEOUT:\$\{label\}`\)\), 35_000/);
  assert.match(runner, /stage: "realtime-subscription"/);
  assert.match(runner, /stage: "realtime-invalidation"/);
  assert.match(runner, /stage: "realtime-reconnect"/);
  assert.match(runner, /maximumAttempts = 3/);
  assert.match(runner, /W8C_STAGING_REALTIME_RECONNECT_EXHAUSTED/);
  assert.match(runner, /W8C_STAGING_REALTIME_DELIVERY_MISSING/);
  assert.match(runner, /Promise\.allSettled\(\[realtimeA\.event, realtimeB\.event\]\)/);
  assert.match(runner, /const deliveredEvents = realtimeResults\.filter/);
  assert.match(runner, /canonicalDevices: 2/);
  assert.match(runner, /reconnectedA\.groupStage\.revision, afterA\.groupStage\.revision/);
  assert.match(runner, /setTimeout\(resolvePromise, 2_000\)/);
  assert.match(runner, /000000000012', 'competition_director'/);
  assert.match(runner, /000000000011', 'competition_schedule_manager'/);
  assert.doesNotMatch(runner, /000000000012', 'competition_schedule_manager'/);
  assert.match(runner, /wave8c_actor\('64010000-0000-4000-8000-000000000011'\)/);
  assert.match(runner, /pachanga_league_private_beta_capabilities_v1\(\)/);
  assert.match(runner, /W8C_STAGING_SCHEDULE_MANAGER_NOT_AUTHORIZED/);
  assert.match(runner, /W8C_STAGING_UNAUTHORIZED_SCHEDULE_ACCEPTED/);
  assert.match(runner, /COMPETITION_SCHEDULE_MANAGER_REQUIRED/);
  assert.match(runner, /W8C_STAGING_LEAGUE_OFFICIAL_DECISION_COUNT_INVALID/);
  assert.doesNotMatch(runner, /'official', 'official_result\.publish'/);
  assert.match(runner, /users\.id=notifications\.recipient_user_id/);
  assert.doesNotMatch(runner, /users\.id=notifications\.user_id/);
  assert.match(runner, /where contexts\.status <> 'retired'/);
  assert.match(runner, /retiredLineageMatches/);
  assert.match(runner, /brackets\.current_completion_snapshot_id/);
  assert.match(runner, /completionSnapshotLineage/);
  assert.doesNotMatch(runner, /snapshots\.status='PUBLISHED'/);
  assert.match(runner, /leagueDistinctActiveStaff/);
  assert.match(runner, /leagueBundleCapabilities/);
  assert.match(runner, /leagueOfficialDecisionMatches/);
  assert.match(runner, /\.slice\(-12_000\)/);
  assert.match(runner, /WAVE8C_REDUCED_AUTHENTICATED_SEASON_FAIL/);
  assert.match(runner, /enterStage\("tournament-group-stage"\)/);
  assert.match(runner, /ONE_WINNER_ONE_STALE/);
  assert.match(runner, /POSTGRES_CHANGES_RECEIVED_AND_CANONICAL_REFETCHED/);
  assert.doesNotMatch(runner, /NEXT_PUBLIC[^\n]*SERVICE_ROLE|process\.env\.NEXT_PUBLIC[^\n]*SERVICE_ROLE/);
});

test("League schedules use the production engine and canonical matches are unique", () => {
  const { index } = buildSyntheticSeason();
  assert.equal(index.proof.authorityAnchors.leagueSchedulingEngineVersion, "league-round-robin-v1");
  assert.equal(index.matches.filter(({ competitionId }) => competitionId === "synthetic_league_a").length, 45);
  assert.equal(index.matches.filter(({ competitionId }) => competitionId === "synthetic_league_b").length, 28);
  assert.equal(index.matches.filter(({ competitionId, kind }) => competitionId === "synthetic_tournament_a" && kind === "TOURNAMENT_GROUP").length, 24);
  assert.equal(index.matches.filter(({ competitionId, kind }) => competitionId === "synthetic_tournament_a" && kind === "TOURNAMENT_KNOCKOUT").length, 8);
  assert.equal(index.matches.filter(({ competitionId }) => competitionId === "synthetic_tournament_b").length, 7);
  assert.equal(new Set(index.matches.map(({ canonicalMatchId }) => canonicalMatchId)).size, 128);
});

test("Main referee assignments cannot overlap at the same kickoff", () => {
  const { index } = buildSyntheticSeason();
  const actualAssignments = new Map<string, string[]>();
  const legacyAssignments = new Map<string, string[]>();
  for (const match of index.matches) {
    if (!match.refereeAssignmentId || !match.refereeId) continue;
    const actualKey = `${match.refereeId}|${match.scheduledAt}`;
    actualAssignments.set(actualKey, [...(actualAssignments.get(actualKey) ?? []), match.canonicalMatchId]);

    const matchNumber = Number(match.canonicalMatchId.slice(-3));
    const legacyRefereeId = `synthetic_referee_${String(matchNumber % 12 + 1).padStart(3, "0")}`;
    const legacyKey = `${legacyRefereeId}|${legacyWeekDate(match.week, matchNumber)}`;
    legacyAssignments.set(legacyKey, [...(legacyAssignments.get(legacyKey) ?? []), match.canonicalMatchId]);
  }
  assert.equal([...legacyAssignments.values()].filter((matches) => matches.length > 1).length, 26);
  assert.equal([...actualAssignments.values()].filter((matches) => matches.length > 1).length, 0);
  assert.equal(index.proof.invariants.noOverlappingMainReferees, true);
});

test("Teams cannot be scheduled in two competitions at the same kickoff", () => {
  const { index } = buildSyntheticSeason();
  const actualAppearances = new Map<string, string[]>();
  const legacyAppearances = new Map<string, string[]>();
  for (const match of index.matches) {
    const matchNumber = Number(match.canonicalMatchId.slice(-3));
    for (const teamId of [match.homeTeamId, match.awayTeamId]) {
      const actualKey = `${teamId}|${match.scheduledAt}`;
      actualAppearances.set(actualKey, [...(actualAppearances.get(actualKey) ?? []), match.canonicalMatchId]);
      const legacyKey = `${teamId}|${legacyWeekDate(match.week, matchNumber)}`;
      legacyAppearances.set(legacyKey, [...(legacyAppearances.get(legacyKey) ?? []), match.canonicalMatchId]);
    }
  }
  assert.equal([...legacyAppearances.values()].filter((matches) => matches.length > 1).length, 6);
  assert.equal([...actualAppearances.values()].filter((matches) => matches.length > 1).length, 0);
  assert.equal(index.proof.invariants.noOverlappingTeams, true);
});

test("Referees must support the canonical match modality", () => {
  const { index } = buildSyntheticSeason();
  const competitionModalities = new Map(index.competitions.map(({ id, modality }) => [id, modality]));
  const refereeProfiles = new Map(index.referees.map((referee) => [referee.id, referee]));
  const previousAssignments = new Map<string, Set<string>>();
  let previousMismatchCount = 0;
  for (const match of [...index.matches].sort((left, right) => left.scheduledAt.localeCompare(right.scheduledAt)
    || left.canonicalMatchId.localeCompare(right.canonicalMatchId))) {
    if (!match.refereeAssignmentId) continue;
    const used = previousAssignments.get(match.scheduledAt) ?? new Set<string>();
    const preferred = testHashNumber(`${SYNTHETIC_SEASON_SEED}:referee:${match.canonicalMatchId}`) % 12;
    let previousRefereeId = "";
    for (let offset = 0; offset < 12; offset += 1) {
      const candidate = `synthetic_referee_${String((preferred + offset) % 12 + 1).padStart(3, "0")}`;
      if (used.has(candidate)) continue;
      previousRefereeId = candidate;
      used.add(candidate);
      previousAssignments.set(match.scheduledAt, used);
      break;
    }
    const modality = match.competitionId ? competitionModalities.get(match.competitionId) : "FOOTBALL_7";
    if (!modality || !refereeProfiles.get(previousRefereeId)?.modalities.includes(modality)) previousMismatchCount += 1;
  }

  const currentMismatches = index.matches.filter((match) => {
    if (!match.refereeId) return false;
    const modality = match.competitionId ? competitionModalities.get(match.competitionId) : "FOOTBALL_7";
    return !modality || !refereeProfiles.get(match.refereeId)?.modalities.includes(modality);
  });
  assert.equal(previousMismatchCount, 45);
  assert.equal(currentMismatches.length, 0);
  assert.equal(index.proof.invariants.refereeModalitiesVerified, true);
});

test("The match distribution remains predominantly normal without hiding operational cases", () => {
  const { index } = buildSyntheticSeason();
  const counts = Object.groupBy(index.matches, ({ anomaly }) => anomaly);
  assert.equal(counts.NORMAL?.length, 107);
  assert.equal(counts.POSTPONED?.length, 7);
  assert.equal(counts.VENUE_CHANGED?.length, 3);
  assert.equal(counts.DISPUTED?.length, 5);
  assert.equal(counts.NO_SHOW?.length, 3);
  assert.equal(counts.SUSPENDED?.length, 3);
  assert.ok(107 / 128 >= 0.75 && 107 / 128 <= 0.85);
});

test("Independent standings, bracket, discipline, referee and operational oracles converge", () => {
  const season = buildSyntheticSeason();
  const oracle = syntheticSeasonOracleReport({
    checkpoints: season.checkpoints,
    disciplineEvents: season.disciplineEvents,
    index: season.index,
    sanctions: season.sanctions,
  });
  assert.equal(oracle.passed, true, oracle.errors.join("\n"));
  assert.deepEqual(oracle.hashes, season.index.proof.oracleHashes);
});

test("Every completed tournament has one champion and reconstructible bracket lineage", () => {
  const season = buildSyntheticSeason();
  assert.deepEqual(syntheticSeasonBracketLineageErrors(season.index.matches), []);
  assert.equal(season.index.proof.invariants.oneChampionPerTournament, true);
  const finals = season.index.matches.filter(({ stage }) => stage === "FINAL");
  assert.deepEqual(finals.map(({ competitionId }) => competitionId).sort(), ["synthetic_tournament_a", "synthetic_tournament_b"]);
  assert.ok(finals.every(({ result }) => result.winnerTeamId));

  const broken = season.index.matches.map((match) => match.competitionId === "synthetic_tournament_a" && match.stage === "SEMIFINAL" && match.round === 1
    ? { ...match, homeTeamId: "synthetic_team_outsider" }
    : match);
  assert.ok(syntheticSeasonBracketLineageErrors(broken).includes("BRACKET_QUARTERFINAL_LINEAGE_DIVERGED:synthetic_tournament_a"));
});

test("Every fault race has one canonical winner and one stale, rejected or idempotent loser", () => {
  const faults = buildSyntheticSeason().index.proof.faultInjection;
  assert.equal(faults.length, 12);
  assert.equal(new Set(faults.map(({ name }) => name)).size, faults.length);
  assert.ok(faults.every(({ canonicalWinner, loserOutcome, regressionVerified }) => canonicalWinner && ["IDEMPOTENT", "REJECTED", "STALE"].includes(loserOutcome) && regressionVerified));
  assert.equal(faults.find(({ name }) => name === "pwa_offline_write")?.canonicalWinner, "server_confirmation_required");
  assert.equal(faults.find(({ name }) => name === "realtime_reconnect")?.loserOutcome, "IDEMPOTENT");
});

test("Operational restrictions do not rewrite competition continuity, Rating or billing", () => {
  const { index } = buildSyntheticSeason();
  const socialOnly = index.teams.find(({ restrictionPreset }) => restrictionPreset === "SOCIAL_ONLY")!;
  const newActivityOnly = index.teams.find(({ restrictionPreset }) => restrictionPreset === "NEW_ACTIVITY_ONLY")!;
  const billingInactive = index.teams.find(({ billingState }) => billingState === "INACTIVE")!;
  assert.equal(socialOnly.marketplaceAllowed, false);
  assert.equal(socialOnly.challengesAllowed, false);
  assert.equal(socialOnly.competitionContinuity, true);
  assert.equal(newActivityOnly.competitionContinuity, true);
  assert.equal(billingInactive.state, "ACTIVE");
  assert.equal(index.proof.invariants.ratingUnchangedByRestrictions, true);
  assert.equal(index.proof.invariants.rewardGrantsIdempotent, true);
});

test("Proof invariants are derived and fail when canonical evidence is corrupted", () => {
  const season = buildSyntheticSeason();
  const input = {
    checkpoints: season.checkpoints,
    competitions: season.index.competitions,
    disciplineEvents: season.disciplineEvents,
    matches: season.index.matches,
    matchSheets: season.index.matchSheets,
    players: season.index.players,
    referees: season.index.referees,
    sanctions: season.sanctions,
    teams: season.index.teams,
  };
  assert.ok(Object.values(syntheticSeasonDerivedInvariants(input)).every(Boolean));

  const lastCheckpoint = season.checkpoints.at(-1)!;
  const firstCompetition = season.index.competitions[0]!.id;
  const corruptedRows = lastCheckpoint.standings[firstCompetition]!.map((row, index) => index === 0
    ? { ...row, points: row.points + 1 }
    : row);
  const corruptedCheckpoints = season.checkpoints.map((checkpoint) => checkpoint.checkpoint === lastCheckpoint.checkpoint
    ? { ...checkpoint, standings: { ...checkpoint.standings, [firstCompetition]: corruptedRows } }
    : checkpoint);
  assert.equal(syntheticSeasonDerivedInvariants({ ...input, checkpoints: corruptedCheckpoints }).standingsReconstructible, false);

  const corruptedDiscipline = season.disciplineEvents.map((event, index) => index === 0
    ? { ...event, canonicalMatchId: "unknown_match" }
    : event);
  assert.equal(syntheticSeasonDerivedInvariants({ ...input, disciplineEvents: corruptedDiscipline }).disciplineReconstructible, false);

  const corruptedTeams = season.index.teams.map((team) => team.restrictionPreset === "SOCIAL_ONLY"
    ? { ...team, marketplaceAllowed: true }
    : team);
  assert.equal(syntheticSeasonDerivedInvariants({ ...input, teams: corruptedTeams }).operationalScopesVerified, false);

  const assignedMatch = season.index.matches.find(({ refereeId }) => Boolean(refereeId))!;
  const corruptedMatches = season.index.matches.map((match) => match.canonicalMatchId === assignedMatch.canonicalMatchId
    ? { ...match, refereeId: "unknown_referee" }
    : match);
  assert.equal(syntheticSeasonDerivedInvariants({ ...input, matches: corruptedMatches }).refereeStatsReconstructible, false);
  assert.equal(syntheticSeasonAuthorityMigrationLedger(), 212);
  assert.throws(() => syntheticSeasonAuthorityMigrationLedger(211), /SYNTHETIC_SEASON_AUTHORITY_LEDGER_MISMATCH:211/);
});

test("Discipline lineage and fulfilled sanctions are reconstructible", () => {
  const season = buildSyntheticSeason();
  for (const event of season.disciplineEvents) {
    const match = season.index.matches.find(({ canonicalMatchId }) => canonicalMatchId === event.canonicalMatchId)!;
    if (!match.refereeId) continue;
    assert.equal(event.refereeAssignmentId, match.refereeAssignmentId);
    assert.equal(event.reportingRefereeId, match.refereeId);
  }
  assert.ok(season.disciplineEvents.some(({ card }) => card === "BLUE"));
  assert.ok(season.disciplineEvents.some(({ card }) => card === "RED"));
  assert.ok(season.disciplineEvents.some(({ card }) => card === "SECOND_YELLOW"));
  assert.ok(season.sanctions.every(({ fulfilledAtWeek, imposedAtWeek, status }) => status === "FULFILLED" && fulfilledAtWeek > imposedAtWeek));
});

test("Attendance and match sheets exclude active sanctions and distinguish no-shows", () => {
  const season = buildSyntheticSeason();
  assert.equal(season.index.matchSheets.length, 256);
  assert.deepEqual(syntheticSeasonMatchSheetErrors(season.index, season.sanctions), []);
  assert.equal(season.index.matchSheets.filter(({ attendance }) => attendance === "NO_SHOW").length, 3);
  assert.equal(season.index.proof.invariants.sanctionedPlayersExcludedFromSquads, true);

  const sanction = season.sanctions[0]!;
  const player = season.index.players.find(({ id }) => id === sanction.playerId)!;
  const activeMatch = season.index.matches.find((match) => (
    (match.homeTeamId === player.teamId || match.awayTeamId === player.teamId)
    && match.week > sanction.imposedAtWeek
    && match.week <= sanction.fulfilledAtWeek
  ))!;
  const brokenSheets = season.index.matchSheets.map((sheet) => sheet.canonicalMatchId === activeMatch.canonicalMatchId && sheet.teamId === player.teamId
    ? { ...sheet, starterPlayerIds: [...sheet.starterPlayerIds, player.id] }
    : sheet);
  assert.ok(syntheticSeasonMatchSheetErrors({ ...season.index, matchSheets: brokenSheets }, season.sanctions)
    .includes(`MATCH_SHEET_SANCTIONED_PLAYER:sheet_${activeMatch.canonicalMatchId}_${player.teamId}`));
});

test("Notification sink, privacy and external-service scans are fail closed", () => {
  const { index, notifications } = buildSyntheticSeason();
  assert.ok(notifications.every(({ recipientId, sink }) => recipientId.startsWith("synthetic_actor_") && sink === "SYNTHETIC_NOTIFICATION_SINK"));
  assert.deepEqual(index.proof.notificationScan, { externalDeliveries: 0, invalidRecipients: 0, sinkOnly: true });
  assert.ok(Object.values(index.proof.privacyScan).every((value) => value === 0));
  assert.equal(index.proof.stripeTouched, false);
  assert.equal(index.remoteWrites, 0);
});

test("Every published V3.2 JSON chunk passes a real serialized privacy scan", async () => {
  generateDemoWorldV32();
  const rootDirectory = path.join(root, "public/demo-world/v3-2");
  const queue = [rootDirectory];
  const findings: Array<{ file: string; labels: string[] }> = [];
  while (queue.length) {
    const directory = queue.pop()!;
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const target = path.join(directory, entry.name);
      if (entry.isDirectory()) queue.push(target);
      else if (entry.name.endsWith(".json")) {
        const labels = syntheticSeasonPrivacyFindings(await readFile(target, "utf8"));
        if (labels.length) findings.push({ file: path.relative(rootDirectory, target), labels });
      }
    }
  }
  assert.deepEqual(findings, []);
  assert.deepEqual(syntheticSeasonPrivacyFindings('{"leak":"sk_test_1234567890"}'), ["SERVICE_SECRET"]);
});

test("Anti-production guard requires the seed, namespace, ledger and ephemeral target", () => {
  const safe = {
    SYNTHETIC_SEASON_CONFIRM: SYNTHETIC_SEASON_CONFIRMATION,
    SYNTHETIC_SEASON_DATABASE_URL: "postgresql://localhost:55322/postgres",
    SYNTHETIC_SEASON_MIGRATION_LEDGER: "212",
    SYNTHETIC_SEASON_NAMESPACE: "synthetic-season-v1-local",
    SYNTHETIC_SEASON_NON_SYNTHETIC_USERS: "0",
    SYNTHETIC_SEASON_SEED,
  } as NodeJS.ProcessEnv;
  assert.deepEqual(syntheticSeasonEnvironmentErrors(safe), []);
  assert.ok(syntheticSeasonEnvironmentErrors({ ...safe, SYNTHETIC_SEASON_CONFIRM: "" }).includes("SYNTHETIC_SEASON_CONFIRMATION_REQUIRED"));
  assert.ok(syntheticSeasonEnvironmentErrors({ ...safe, SYNTHETIC_SEASON_DATABASE_URL: `postgresql://${PACHANGAS_PRODUCTION_PROJECT_REF}.supabase.co/postgres` }).includes("SYNTHETIC_SEASON_PRODUCTION_TARGET_BLOCKED"));
  assert.ok(syntheticSeasonEnvironmentErrors({ ...safe, NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY: "blocked" }).includes("SYNTHETIC_SEASON_PUBLIC_SECRET_DETECTED"));
  assert.ok(syntheticSeasonEnvironmentErrors({ ...safe, STRIPE_SECRET_KEY: "blocked" }).includes("SYNTHETIC_SEASON_STRIPE_ENV_BLOCKED"));
  assert.ok(syntheticSeasonEnvironmentErrors({ ...safe, SYNTHETIC_SEASON_NON_SYNTHETIC_USERS: "1" }).includes("SYNTHETIC_SEASON_NON_SYNTHETIC_USERS_PRESENT"));
});

test("Demo World V3.2 publishes immutable checkpoints without rewriting historical snapshots", async () => {
  const generated = generateDemoWorldV32();
  assert.equal(generated.snapshot.manifest.version, DEMO_WORLD_V32_VERSION);
  assert.equal(generated.snapshot.manifest.seed, SYNTHETIC_SEASON_SEED);
  assert.equal(generated.snapshot.manifest.counts.teams, 32);
  assert.equal(generated.snapshot.manifest.counts.players, 481);
  assert.equal(generated.snapshot.manifest.counts.canonicalMatches, 128);
  assert.equal(generated.snapshot.manifest.checkpoints.length, 9);
  assert.ok(generated.snapshot.manifest.checkpoints.every(({ path }) => path.startsWith("/demo-world/v3-2/checkpoints/") && path.includes("?h=")));
  const historical = JSON.parse(await readFile(path.join(root, "public/demo-world/v3/manifest.json"), "utf8"));
  assert.equal(historical.version, 3.1);
  assert.equal(historical.seed, "pachangas-iq-demo-world-v3-1-2026-27");
  assert.equal(generateDemoWorldV2().manifest.hash, historical.hash);
});

test("PWA caches v3-2 hashed chunks, keeps demo read-only and excludes private services", () => {
  const source = buildServiceWorkerSource("8.2.0+synthetic-season");
  assert.match(source, /\/demo-world\/v3-2\/manifest\.json/);
  assert.match(source, /v\\d\+\(\?:-\\d\+\)\*/);
  assert.match(source, /request\.method !== "GET"/);
  assert.match(source, /isSensitivePath/);
  assert.match(source, /isLiveServiceUrl/);
  assert.match(source, /supabase\.co/);
  assert.match(source, /stripe\.com/);
  const immutablePath = /^\/demo-world\/v\d+(?:-\d+)*\//;
  assert.equal(immutablePath.test("/demo-world/v3-2/checkpoints/checkpoint-8.json"), true);
});

test("Demo V3.2 UI exposes timeline, all product views and game landscape without a second shell", async () => {
  const [app, view, css, page, controlCenter] = await Promise.all([
    readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8"),
    readFile(path.join(root, "app/demo-world/demo-world-v3-2-view.tsx"), "utf8"),
    readFile(path.join(root, "app/demo-world/demo-world-v3-2-view.module.css"), "utf8"),
    readFile(path.join(root, "app/demo/page.tsx"), "utf8"),
    readFile(path.join(root, "app/laboratorio-synthetic-season/page.tsx"), "utf8"),
  ]);
  assert.match(app, /id: "temporada", label: "Temporada"/);
  assert.match(app, /<SyntheticSeasonView index=\{snapshot\.season\}/);
  for (const label of ["Resumen", "Ligas", "Torneos", "Jornadas", "Partidos", "Clasificaciones", "Cuadros", "Disciplina", "Árbitros", "Equipos", "Clubs", "Mercado", "Retos", "Organización", "Incidencias", "Timeline"]) assert.match(view, new RegExp(label));
  assert.match(view, /Reproducir temporada/);
  assert.match(css, /grid-template-columns: 124px minmax\(0, 1fr\) 200px/);
  assert.match(css, /prefers-reduced-motion: reduce/);
  assert.match(page, /public\/demo-world\/v3-2\/manifest\.json/);
  assert.match(controlCenter, /robots: \{ follow: false, index: false \}/);
  assert.doesNotMatch(controlCenter, /execute|run simulation|POST/i);
});
