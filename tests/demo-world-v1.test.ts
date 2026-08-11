import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import {
  DEFAULT_DEMO_WORLD_SESSION,
  DEMO_WORLD_BLOCKED_REMOTE_OPERATIONS,
  DEMO_WORLD_MODE,
  DEMO_WORLD_TEAM_REWARD_MAPPINGS,
  assertDemoWorldLocalIntent,
  assertDemoWorldSnapshot,
  canDemoWorldInvite,
  demoWorldMatchAdminActions,
  demoWorldForbiddenPaths,
  demoWorldIntegrityErrors,
  isDemoWorldRemoteWrite,
  type DemoWorldSnapshot,
} from "../app/demo-world/demo-world-contract";
import {
  demoWorldTabFromSearch,
  readDemoWorldSession,
  readInitialDemoWorldSession,
  resetDemoWorldSession,
  writeDemoWorldSession,
} from "../app/demo-world/demo-world-client-state";
import { PLAYER_COSMETIC_CATALOG } from "../app/player-cosmetics-catalog";
import { RATING_SYSTEM_V2_ENGINE_VERSION } from "../app/rating-system-v2";
import { TEAM_SHIELD_RENDER_CATALOG } from "../app/team-shield-cosmetics-catalog";
import { generateDemoWorld } from "../scripts/demo-world/generate-demo-world";
import { TEAM_COSMETIC_REWARD_MAPPINGS_V1 } from "../simulation/synthetic-world/scripts/team-cosmetic-rewards-v1";

const root = process.cwd();
const publicRoot = path.join(root, "public/demo-world/v1");

async function committedSnapshot(): Promise<DemoWorldSnapshot> {
  const [activity, core, manifest, matches, players] = await Promise.all([
    readFile(path.join(publicRoot, "activity.json"), "utf8").then(JSON.parse),
    readFile(path.join(publicRoot, "core.json"), "utf8").then(JSON.parse),
    readFile(path.join(publicRoot, "manifest.json"), "utf8").then(JSON.parse),
    readFile(path.join(publicRoot, "matches.json"), "utf8").then(JSON.parse),
    readFile(path.join(publicRoot, "players.json"), "utf8").then(JSON.parse),
  ]);
  return { activity, core, manifest, matches, players };
}

test("Demo World V1 is deterministic and committed chunks match its recorded hash", async () => {
  const generated = generateDemoWorld();
  const committed = await committedSnapshot();
  assert.deepEqual(committed, generated);
  const payload = { activity: committed.activity, core: committed.core, matches: committed.matches, players: committed.players };
  assert.equal(createHash("sha256").update(JSON.stringify(payload)).digest("hex"), committed.manifest.hash);
  assert.equal(committed.manifest.hash, "cef767f201a00f9f36fdaad8b27a195e9c767147651153717dabf043b71d16d3");
  assert.equal(committed.manifest.mode, DEMO_WORLD_MODE);
  for (const chunk of Object.values(committed.manifest.chunks)) {
    assert.match(chunk, new RegExp(`\\?h=${committed.manifest.hash.slice(0, 16)}$`));
  }
});

test("snapshot has a believable navigable world within the V1 size budget", async () => {
  const world = assertDemoWorldSnapshot(await committedSnapshot());
  assert.equal(world.core.teams.length, 28);
  assert.equal(world.players.players.length, 365);
  assert.equal(world.matches.matches.length, 128);
  assert.equal(world.matches.challenges.length, 26);
  assert.equal(world.core.stories.length, 10);
  assert.equal(world.activity.notifications.length, 12);
  assert.equal(world.core.perspectives.length, 3);
  assert.deepEqual(new Set(world.core.perspectives.map(({ id }) => id)), new Set(["admin", "player", "free-agent"]));
  assert.ok(world.matches.matches.some(({ status }) => status === "scheduled"));
  assert.ok(world.matches.matches.some(({ status }) => status === "finalized"));
  assert.ok(world.matches.matches.some(({ scope }) => scope === "internal"));
  assert.ok(world.matches.matches.some(({ scope }) => scope === "challenge"));
  assert.ok(new Set(world.core.teams.map(({ territory }) => territory)).size >= 4);
  assert.ok(Buffer.byteLength(JSON.stringify({ activity: world.activity, core: world.core, matches: world.matches, players: world.players })) < 700_000);
});

test("public snapshot rejects PII, private moderation and unsafe identifiers", async () => {
  const world = await committedSnapshot();
  assert.deepEqual(demoWorldForbiddenPaths(world), []);
  assert.deepEqual(demoWorldIntegrityErrors(world), []);
  assert.ok(world.core.teams.every(({ id }) => id.startsWith("demo_team_")));
  assert.ok(world.players.players.every(({ id }) => id.startsWith("demo_player_")));

  const contaminated = structuredClone(world) as unknown as Record<string, unknown>;
  contaminated.email = "someone@example.test";
  assert.deepEqual(demoWorldForbiddenPaths(contaminated), ["snapshot.email"]);
  assert.throws(() => assertDemoWorldSnapshot(contaminated as unknown as DemoWorldSnapshot), /Forbidden public field/);
});

test("all field cards are Rating V2 read models and goalkeeper overall stays explicitly unresolved", async () => {
  const world = await committedSnapshot();
  const fieldPlayers = world.players.players.filter(({ rating }) => rating.domain === "field");
  const goalkeepers = world.players.players.filter(({ rating }) => rating.domain === "goalkeeper_legacy");
  assert.ok(fieldPlayers.length > 300);
  assert.ok(goalkeepers.length >= 28);
  assert.ok(fieldPlayers.every(({ rating }) => rating.engineVersion === RATING_SYSTEM_V2_ENGINE_VERSION));
  assert.ok(fieldPlayers.every(({ rating }) => Number.isFinite(rating.currentOverall) && Number(rating.currentOverall) >= 0 && Number(rating.currentOverall) <= 100));
  assert.ok(goalkeepers.every(({ rating }) => rating.currentOverall === null));

  const generatorSource = await readFile(path.join(root, "scripts/demo-world/generate-demo-world.ts"), "utf8");
  assert.match(generatorSource, /calculateRatingCardLayers/);
  assert.doesNotMatch(generatorSource, /function calculateOverall/);
  assert.doesNotMatch(generatorSource, /Date\.now\(|new Date\(\)/);
});

test("cosmetics only use the active player catalog and approved team render catalog", async () => {
  const world = await committedSnapshot();
  const playerKeys = new Set(PLAYER_COSMETIC_CATALOG.map(({ key }) => key));
  const teamKeys = new Set(TEAM_SHIELD_RENDER_CATALOG.filter(({ prototype }) => !prototype).map(({ key }) => key));
  for (const player of world.players.players) {
    for (const key of [player.cosmetics.accentKey, player.cosmetics.backgroundKey, player.cosmetics.effectKey, player.cosmetics.frameKey, player.cosmetics.titleKey]) {
      if (key) assert.ok(playerKeys.has(key), key);
    }
  }
  for (const team of world.core.teams) {
    for (const key of [team.shield.shapeKey, team.shield.backgroundKey, team.shield.patternKey, team.shield.primaryColorKey, team.shield.secondaryColorKey, team.shield.primarySymbolKey, team.shield.borderKey, team.shield.bottomOrnamentKey, team.shield.sideOrnamentKey, team.shield.effectKey]) {
      if (key) assert.ok(teamKeys.has(key), key);
    }
  }
  const serialized = JSON.stringify(world).toLowerCase();
  assert.doesNotMatch(serialized, /premium[._ -]?ball/);
  assert.doesNotMatch(serialized, /prototype\./);
  assert.ok(new Set(world.core.teams.map(({ shield }) => JSON.stringify(shield))).size >= 20);
  assert.ok(new Set(world.players.players.map(({ cosmetics }) => JSON.stringify(cosmetics))).size >= 20);
});

test("the five team reward mappings remain exact and every displayed grant has evidence", async () => {
  const world = await committedSnapshot();
  assert.deepEqual(world.activity.teamRewardMappings, DEMO_WORLD_TEAM_REWARD_MAPPINGS.map((entry) => ({ ...entry })));
  assert.deepEqual(
    DEMO_WORLD_TEAM_REWARD_MAPPINGS.map((mapping) => ({
      achievementKey: mapping.achievementKey,
      cosmeticKey: mapping.cosmeticKey,
      firstOccurrenceOnly: mapping.firstOccurrenceOnly,
      mappingKey: mapping.mappingKey,
    })),
    TEAM_COSMETIC_REWARD_MAPPINGS_V1,
  );
  for (const mapping of DEMO_WORLD_TEAM_REWARD_MAPPINGS) {
    const grants = world.activity.achievements.filter(({ key, subjectType }) => subjectType === "team" && key === mapping.achievementKey);
    assert.ok(grants.length > 0, mapping.mappingKey);
    assert.ok(grants.every(({ evidence }) => evidence.trim().length > 8));
    assert.ok(world.activity.rewardBoxes.some(({ achievementId, rewardCosmeticKey }) => grants.some(({ id }) => id === achievementId) && rewardCosmeticKey === mapping.cosmeticKey));
  }
});

test("stories, scorers, challenges, rewards and rankings resolve to canonical entities", async () => {
  const world = await committedSnapshot();
  assert.deepEqual(demoWorldIntegrityErrors(world), []);
  const matchIds = new Set(world.matches.matches.map(({ id }) => id));
  assert.ok(world.matches.challenges.some(({ status }) => status === "completed"));
  assert.ok(world.matches.challenges.some(({ status }) => status === "countered"));
  assert.ok(world.matches.challenges.some(({ status }) => status === "rejected"));
  assert.ok(world.matches.challenges.some(({ status }) => status === "cancelled"));
  assert.ok(world.matches.challenges.filter(({ matchId }) => matchId).every(({ matchId }) => matchIds.has(matchId!)));
  for (const challenge of world.matches.challenges) {
    const match = challenge.matchId ? world.matches.matches.find(({ id }) => id === challenge.matchId) : null;
    if (challenge.status === "accepted") assert.equal(match?.status, "scheduled");
    else if (challenge.status === "completed") assert.equal(match?.status, "finalized");
    else assert.equal(match, null);
  }
  const challengeById = new Map(world.matches.challenges.map((challenge) => [challenge.id, challenge]));
  assert.equal(challengeById.get(world.activity.notifications.find(({ title }) => title === "Reto aceptado")!.targetId!)?.status, "accepted");
  assert.equal(challengeById.get(world.activity.notifications.find(({ title }) => title === "Contrapropuesta recibida")!.targetId!)?.status, "countered");
  assert.equal(challengeById.get(world.activity.notifications.find(({ title }) => title === "Resultado confirmado")!.targetId!)?.status, "completed");
  assert.equal(challengeById.get(world.core.stories.find(({ id }) => id === "demo_story_004")!.referenceIds[0]!)?.status, "countered");
  assert.equal(challengeById.get(world.core.stories.find(({ id }) => id === "demo_story_009")!.referenceIds[0]!)?.status, "rejected");
  assert.deepEqual(world.core.rankings.map(({ position }) => position), Array.from({ length: world.core.teams.length }, (_, index) => index + 1));
  assert.ok(world.activity.achievements.every(({ evidence }) => evidence.trim().length > 0));
});

test("Demo World has no remote mutation capability and all simulated state stays in session storage", async () => {
  for (const operation of DEMO_WORLD_BLOCKED_REMOTE_OPERATIONS) {
    const [kind, value] = operation.split(":");
    const input = kind === "fetch" ? { method: value } : { operation };
    assert.equal(isDemoWorldRemoteWrite(input), true);
    assert.throws(() => assertDemoWorldLocalIntent(input), /DEMO_WORLD_REMOTE_WRITE_BLOCKED/);
  }
  assert.equal(isDemoWorldRemoteWrite({ method: "GET", operation: "load-public-snapshot" }), false);
  assert.doesNotThrow(() => assertDemoWorldLocalIntent({ method: "GET", operation: "load-public-snapshot" }));

  const sources = await Promise.all([
    readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8"),
    readFile(path.join(root, "app/demo-world/demo-world-client-state.ts"), "utf8"),
  ]).then((parts) => parts.join("\n"));
  assert.doesNotMatch(sources, /supabaseClient|\.rpc\(|service_role|credentials:\s*["']include/);
  assert.doesNotMatch(sources, /method:\s*["'](?:POST|PUT|PATCH|DELETE)/);
  assert.match(sources, /sessionStorage/);
  assert.match(sources, /credentials:\s*["']same-origin/);
  assert.doesNotMatch(sources, /credentials:\s*["']omit/);
});

test("ephemeral session round-trips and reset restores the frozen default", () => {
  const values = new Map<string, string>();
  const storage = {
    getItem: (key: string) => values.get(key) ?? null,
    removeItem: (key: string) => { values.delete(key); },
    setItem: (key: string, value: string) => { values.set(key, value); },
  };
  const changed = {
    attendanceByMatch: { demo_match_121: "voy" as const },
    openedBoxIds: ["demo_reward_box_001"],
    perspectiveId: "admin" as const,
    readNotificationIds: ["demo_notification_001"],
  };
  writeDemoWorldSession(storage, changed);
  assert.deepEqual(readDemoWorldSession(storage), changed);
  assert.deepEqual(resetDemoWorldSession(storage), DEFAULT_DEMO_WORLD_SESSION);
  assert.deepEqual(readDemoWorldSession(storage), DEFAULT_DEMO_WORLD_SESSION);
});

test("URL and sessionStorage initialize once with URL precedence", () => {
  const storage = {
    getItem: () => JSON.stringify({
      attendanceByMatch: {},
      openedBoxIds: [],
      perspectiveId: "player",
      readNotificationIds: [],
    }),
  };
  assert.equal(demoWorldTabFromSearch("?tab=mercado"), "mercado");
  assert.equal(demoWorldTabFromSearch("?tab=desconocido"), "inicio");
  assert.equal(readInitialDemoWorldSession("?perspective=admin", storage).perspectiveId, "admin");
  assert.equal(readInitialDemoWorldSession("", storage).perspectiveId, "player");
});

test("historical match administration cannot expose active-match tools", () => {
  assert.deepEqual(demoWorldMatchAdminActions("finalized"), ["Borrar partido"]);
  assert.deepEqual(demoWorldMatchAdminActions("scheduled"), [
    "Cerrar alineación",
    "Abrir al Mercado",
    "Invitar jugador",
    "Editar campo",
    "Crear nuevo partido",
    "Borrar partido",
  ]);
});

test("only the demo admin perspective can simulate invitations", () => {
  assert.equal(canDemoWorldInvite("admin"), true);
  assert.equal(canDemoWorldInvite("player"), false);
  assert.equal(canDemoWorldInvite("visitor"), false);
});

test("Demo World honors the explicit product theme over the system preference", async () => {
  const styles = await readFile(path.join(root, "app/demo-world/demo-world.module.css"), "utf8");
  assert.match(styles, /:global\(:root\[data-theme="light"\]\) \.shell/);
  assert.match(styles, /:global\(:root:not\(\[data-theme="dark"\]\)\) \.shell/);
});

test("legacy demo entry redirects to the isolated public Demo World", async () => {
  const homeSource = await readFile(path.join(root, "app/page.tsx"), "utf8");
  assert.match(homeSource, /window\.location\.replace\(`\/demo/);
  assert.match(homeSource, /window\.location\.assign\("\/demo"\)/);
  assert.match(homeSource, /Mundo Demo/);
});
