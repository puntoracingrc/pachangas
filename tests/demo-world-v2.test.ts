import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { buildServiceWorkerSource } from "../app/service-worker-source";
import {
  DEMO_WORLD_V2_SEED,
  assertDemoWorldV2Snapshot,
  computeDemoWorldV2Standings,
  demoWorldV2IntegrityErrors,
  type DemoWorldV2Snapshot,
} from "../app/demo-world/demo-world-v2-contract";
import {
  demoWorldV2TabFromSearch,
  loadDemoWorldV2Core,
  loadDemoWorldV2Snapshot,
} from "../app/demo-world/demo-world-v2-client-state";
import {
  assertDemoWorldV2AuthorityProof,
  loadDemoWorldV2AuthorityProof,
} from "../scripts/demo-world/demo-world-v2-authority";
import { generateDemoWorldV2 } from "../scripts/demo-world/generate-demo-world-v2";

const root = process.cwd();
const publicRoot = path.join(root, "public/demo-world/v2");

async function jsonFile<T>(name: string): Promise<T> {
  return JSON.parse(await readFile(path.join(publicRoot, name), "utf8")) as T;
}

async function committedSnapshot(): Promise<DemoWorldV2Snapshot> {
  const [activity, clubsReferees, competitions, core, manifest, matches, players] = await Promise.all([
    jsonFile<DemoWorldV2Snapshot["activity"]>("activity.json"),
    jsonFile<DemoWorldV2Snapshot["clubsReferees"]>("clubs-referees.json"),
    jsonFile<DemoWorldV2Snapshot["competitions"]>("competitions.json"),
    jsonFile<DemoWorldV2Snapshot["core"]>("core.json"),
    jsonFile<DemoWorldV2Snapshot["manifest"]>("manifest.json"),
    jsonFile<DemoWorldV2Snapshot["matches"]>("matches.json"),
    jsonFile<DemoWorldV2Snapshot["players"]>("players.json"),
  ]);
  return { activity, clubsReferees, competitions, core, manifest, matches, players };
}

test("Demo World V2 is deterministic and the committed snapshot matches its hash", async () => {
  const committed = await committedSnapshot();
  const generated = generateDemoWorldV2();
  assert.deepEqual(committed, generated);
  const payload = {
    activity: committed.activity,
    clubsReferees: committed.clubsReferees,
    competitions: committed.competitions,
    core: committed.core,
    matches: committed.matches,
    players: committed.players,
  };
  assert.equal(createHash("sha256").update(JSON.stringify(payload)).digest("hex"), committed.manifest.hash);
  assert.equal(committed.manifest.hash, "f68d9279271275afc262b144cb7784957b5a9606e5fd74df02907ef45f5c1886");
  assert.equal(committed.manifest.seed, DEMO_WORLD_V2_SEED);
  assert.deepEqual(demoWorldV2IntegrityErrors(committed), []);
});

test("the committed authority proof comes from deterministic PostgreSQL operations", async () => {
  const proof = assertDemoWorldV2AuthorityProof(loadDemoWorldV2AuthorityProof());
  const world = await committedSnapshot();
  assert.equal(proof.authorityHash, "0ca037a292e643bebd9738e1ae072f776e7e1ecc29da776f9291435b7b35fa6b");
  assert.equal(proof.authorityHash, world.competitions.provenance.authorityHash);
  assert.equal(proof.database, "temporary-local-postgresql");
  assert.equal(proof.migrationCount, 146);
  assert.equal(proof.remoteWrites, 0);
  assert.deepEqual(proof.rpcFamilies, ["R1", "R4A", "R4B", "R4C", "R4D", "R5"]);
  assert.deepEqual(proof.operationReceipts, {
    discipline: 33,
    matchOperations: 266,
    operationalExceptions: 13,
    scheduling: 5,
  });
  assert.equal(proof.matches.length, world.competitions.matches.length);
  assert.deepEqual(
    proof.standings.map(({ entryNumber, ...row }) => ({ ...row, entryId: `demo_league_entry_${String(entryNumber).padStart(3, "0")}` })),
    world.competitions.standingSnapshot.rows.map((row) => ({
      draws: row.draws,
      effectivePoints: row.effectivePoints,
      entryId: row.entryId,
      goalDifference: row.goalDifference,
      goalsAgainst: row.goalsAgainst,
      goalsFor: row.goalsFor,
      losses: row.losses,
      played: row.played,
      position: row.position,
      wins: row.wins,
    })),
  );
});

test("the protagonist League has the complete canonical R1-R5 graph", async () => {
  const world = assertDemoWorldV2Snapshot(await committedSnapshot());
  const league = world.competitions;
  assert.equal(league.competition.name, "LIGA BARRIOS IQ 2026/27");
  assert.equal(league.entries.length, 6);
  assert.equal(league.delegates.length, 6);
  assert.equal(league.rosters.length, 6);
  assert.equal(league.rounds.length, 5);
  assert.equal(league.matches.length, 15);
  assert.equal(new Set(league.matches.map(({ canonicalMatchId }) => canonicalMatchId)).size, 15);
  assert.deepEqual(league.rounds.map(({ matchIds }) => matchIds.length), [3, 3, 3, 3, 3]);
  const originalRoundWindows = league.rounds.map((round) => {
    const starts = league.matches
      .filter(({ roundNumber }) => roundNumber === round.number)
      .map(({ originalScheduledStart }) => Date.parse(originalScheduledStart));
    return { maximum: Math.max(...starts), minimum: Math.min(...starts) };
  });
  assert.ok(originalRoundWindows.every((window, index) => (
    index === 0 || originalRoundWindows[index - 1]!.maximum < window.minimum
  )));
  assert.deepEqual(league.provenance.rpcFamilies, ["R1", "R4A", "R4B", "R4C", "R4D", "R5"]);
  assert.equal(league.provenance.verified, true);
  assert.equal(league.provenance.migrations, 146);
  assert.equal(league.competition.refereeAssignmentsEnabled, false);
});

test("R5 discipline is canonical, sparse, calendar-aware and public-safe", async () => {
  const world = await committedSnapshot();
  const proof = loadDemoWorldV2AuthorityProof();
  const discipline = world.competitions.disciplinePreview;
  const events = discipline.events as Array<Record<string, unknown>>;
  const sanctions = discipline.sanctions as Array<Record<string, unknown>>;
  const serviceEvents = discipline.serviceEvents as Array<Record<string, unknown>>;
  const cardCounts = events.reduce<Record<string, number>>((counts, event) => {
    const code = String(event.cardTypeCode);
    counts[code] = (counts[code] ?? 0) + 1;
    return counts;
  }, {});
  assert.deepEqual(cardCounts, { BLUE: 2, RED: 2, YELLOW: 16 });
  assert.equal(sanctions.length, 4);
  assert.equal(serviceEvents.length, 2);
  assert.deepEqual(discipline.appeals, []);
  assert.equal(events.filter((event) => Number(event.revisionVersion) > 1).length, 1);
  assert.ok(sanctions.some((sanction) => sanction.status === "served" && sanction.totalUnits === 1 && sanction.remainingUnits === 0));
  assert.ok(sanctions.some((sanction) => sanction.status === "active" && sanction.publicSummary === "Sanción confirmada"));
  assert.deepEqual(
    (discipline.eligibilityTimeline as Array<Record<string, unknown>>).map(({ primaryAvailable, selectedSlot }) => ({ primaryAvailable, selectedSlot })),
    [
      { primaryAvailable: true, selectedSlot: "primary" },
      { primaryAvailable: true, selectedSlot: "primary" },
      { primaryAvailable: true, selectedSlot: "primary" },
      { primaryAvailable: false, selectedSlot: "alternate" },
      { primaryAvailable: true, selectedSlot: "primary" },
    ],
  );
  assert.deepEqual(proof.discipline.appeals.map(({ status }) => status), ["modified", "upheld"]);
  assert.ok(Object.values(world.competitions.matchDisciplinePreviews).every((preview) => (
    Array.isArray(preview.events) && Array.isArray(preview.sanctions)
      && Array.isArray(preview.appeals) && preview.appeals.length === 0
  )));
  assert.doesNotMatch(JSON.stringify(discipline), /privateReason|evidenceRefs|appellant|decisionFactors|operationId/i);
});

test("the independent standings oracle reconstructs the official snapshot", async () => {
  const world = await committedSnapshot();
  const teamById = new Map(world.core.teams.map((team) => [team.id, team.name]));
  const oracle = computeDemoWorldV2Standings(
    world.competitions.entries,
    world.competitions.matches,
    (teamId) => teamById.get(teamId) ?? teamId,
  );
  assert.deepEqual(oracle, world.competitions.standingSnapshot.rows);
  assert.equal(oracle.reduce((sum, row) => sum + row.played, 0), 30);
  assert.equal(oracle.reduce((sum, row) => sum + row.goalsFor, 0), oracle.reduce((sum, row) => sum + row.goalsAgainst, 0));
  assert.equal(world.competitions.standingSnapshot.computedResults, 15);
  assert.equal(world.competitions.standingsPreview.snapshot?.checksum, world.competitions.standingSnapshot.checksum);
});

test("R4D stories are sparse, canonical and preserve lineage", async () => {
  const matches = (await committedSnapshot()).competitions.matches;
  const counts = matches.reduce<Record<string, number>>((result, match) => {
    result[match.exceptionType] = (result[match.exceptionType] ?? 0) + 1;
    return result;
  }, {});
  assert.deepEqual(counts, { none: 11, no_show: 1, postponed: 1, suspended_resumed: 1, venue_changed: 1 });
  const delayed = matches.filter(({ lateArrivalStatus }) => lateArrivalStatus === "arrived_within_policy");
  assert.equal(delayed.length, 1);
  assert.equal(delayed[0]!.exceptionType, "none");
  const postponed = matches.find(({ exceptionType }) => exceptionType === "postponed")!;
  assert.notEqual(postponed.originalScheduledStart, postponed.scheduledStart);
  assert.deepEqual(postponed.lineage.map(({ type }) => type), ["postponement", "fixture_change", "official_result"]);
  const noShow = matches.find(({ exceptionType }) => exceptionType === "no_show")!;
  assert.deepEqual(noShow.result, { away: 0, home: 3 });
  assert.equal(noShow.officialDecision.outcome, "NO_SHOW");
  const suspension = matches.find(({ exceptionType }) => exceptionType === "suspended_resumed")!;
  assert.equal(suspension.partialResult?.minute, 38);
  assert.deepEqual(suspension.lineage.map(({ type }) => type), ["suspension", "resumption", "official_result"]);
  assert.ok(matches.every((match) => match.scorers.reduce((sum, scorer) => sum + scorer.goals, 0) === match.result.home + match.result.away));
});

test("Clubs and referee profiles form a public relationship graph without assignments", async () => {
  const world = await committedSnapshot();
  assert.equal(world.clubsReferees.clubs.length, 3);
  assert.equal(world.clubsReferees.referees.length, 8);
  assert.equal(world.clubsReferees.refereeAssignmentsEnabled, false);
  assert.equal(world.clubsReferees.relationships.filter(({ type }) => type === "club_team").length, 6);
  assert.ok(world.clubsReferees.relationships.filter(({ type }) => type === "club_referee").length >= 8);
  assert.ok(world.clubsReferees.clubs.every((club) => club.teamIds.length === 2 && Object.keys(club.publicProfile).length > 0));
  assert.ok(world.clubsReferees.referees.every((referee) => referee.marketplaceStatus === "listed" && referee.publicBio.length > 10));
});

test("V2 chunks stay lazy, GET-only and converge to the validated snapshot", async () => {
  const world = await committedSnapshot();
  const requested: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async (input, init) => {
    assert.equal(init?.method, "GET");
    const url = String(input);
    requested.push(url);
    const name = url.replace(/^.*\/v2\//, "").replace(/\?.*$/, "");
    return new Response(JSON.stringify(await jsonFile(name)), { status: 200 });
  }) as typeof fetch;
  try {
    const core = await loadDemoWorldV2Core(world.manifest);
    assert.equal(requested.length, 1);
    assert.match(requested[0]!, /core\.json/);
    const loaded = await loadDemoWorldV2Snapshot(world.manifest, core);
    assert.deepEqual(loaded, world);
    assert.equal(requested.length, 6);
    assert.ok(requested.every((url) => /\?h=[0-9a-f]{16}$/.test(url)));
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("the public Demo uses production renderers in one shell and exposes all V2 tabs", async () => {
  const [appSource, disciplineSource, disciplineStyles, scheduleSource, matchSource, clubSource, demoStyles] = await Promise.all([
    readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8"),
    readFile(path.join(root, "app/_components/competition-discipline-client.tsx"), "utf8"),
    readFile(path.join(root, "app/_components/competition-discipline-client.module.css"), "utf8"),
    readFile(path.join(root, "app/_components/league-scheduling-client.tsx"), "utf8"),
    readFile(path.join(root, "app/_components/league-match-operations-client.tsx"), "utf8"),
    readFile(path.join(root, "app/clubes/[slug]/public-club-profile.tsx"), "utf8"),
    readFile(path.join(root, "app/demo-world/demo-world.module.css"), "utf8"),
  ]);
  for (const label of ["Liga", "Clasificación", "Jornadas", "Disciplina", "Club", "Árbitros"]) assert.match(appSource, new RegExp(`label: "${label}"`));
  assert.match(appSource, /LeagueSchedulingClient embedded/);
  assert.match(appSource, /onOpenMatch=\{\(canonicalMatchId\)/);
  assert.match(appSource, /entry\.canonicalMatchId === canonicalMatchId/);
  assert.match(appSource, /LeagueMatchOperationsClient embedded/);
  assert.match(appSource, /CompetitionDisciplineClient competitionId=.*embedded.*surface="public"/);
  assert.match(appSource, /disciplinePreviewData=\{selectedLeagueMatchDisciplinePreview\}/);
  assert.match(matchSource, /disciplineAvailable=\{Boolean\(props\.disciplinePreviewData\)\}/);
  assert.match(matchSource, /disciplineAvailable \? "Disciplina R5" : "Disciplina oficial"/);
  assert.doesNotMatch(matchSource, /no disponible hasta R5/);
  assert.match(appSource, /PublicClubProfile club=.*embedded/);
  assert.match(appSource, /RefereeProfileCard compact/);
  assert.doesNotMatch(appSource, /DemoLeagueTable|DemoLeagueMatch/);
  assert.match(scheduleSource, /embedded \? content : <OfficialProductShellV2/);
  assert.match(matchSource, /embedded[\s\S]*\? content/);
  assert.match(disciplineSource, /preview=\{Boolean\(previewData\)\}/);
  assert.match(disciplineStyles, /\.eventRows article \{ grid-template-columns: 16px minmax\(0, 1fr\) minmax\(86px, auto\); \}/);
  assert.match(disciplineStyles, /\.eventRows article > span:nth-of-type\(3\) \{ display: none; \}/);
  assert.doesNotMatch(disciplineStyles, /span:nth-of-type\(2\),\s*\n\s*\.eventRows article > span:nth-of-type\(3\)/);
  assert.match(clubSource, /embedded \? content/);
  assert.match(demoStyles, /\.leagueHero \{ min-height: calc\(100dvh - var\(--game-nav-height, 48px\) - 36px\)/);
  assert.match(demoStyles, /\.demoProductView \{[\s\S]*--official-text: #f1f6f2;/);
  assert.match(demoStyles, /\.demoProductView \.demoDomainHeading h1 \{[\s\S]*color: var\(--official-text\);/);
  assert.equal(demoWorldV2TabFromSearch("?tab=clasificacion"), "clasificacion");
  assert.equal(demoWorldV2TabFromSearch("?tab=disciplina"), "disciplina");
  assert.equal(demoWorldV2TabFromSearch("?tab=desconocido"), "inicio");
});

test("the V2 public bundle contains no PII, remote write path or product mutation", async () => {
  const world = await committedSnapshot();
  const serialized = JSON.stringify(world).toLowerCase();
  for (const forbidden of ["@example", "service_role", "access_token", "refresh_token", "phone", "telephone", "private_address"]) {
    assert.doesNotMatch(serialized, new RegExp(forbidden));
  }
  const sources = await Promise.all([
    readFile(path.join(root, "app/demo-world/demo-world-v2-client-state.ts"), "utf8"),
    readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8"),
  ]).then((parts) => parts.join("\n"));
  assert.doesNotMatch(sources, /\.rpc\(|service_role|method:\s*["'](?:POST|PUT|PATCH|DELETE)/);
  assert.match(sources, /method:\s*"GET"/);
  assert.match(sources, /sessionStorage/);
});

test("the Service Worker precaches V2 and caches every immutable versioned Demo chunk", () => {
  const source = buildServiceWorkerSource("demo-world-v2-test");
  assert.match(source, /"\/demo-world\/v2\/manifest\.json"/);
  assert.match(source, /\^\\\/demo-world\\\/v\\d\+\\\//);
  assert.match(source, /request\.method !== "GET"/);
  assert.match(source, /isImmutableDemoChunk/);
});
