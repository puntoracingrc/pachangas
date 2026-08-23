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
  demoWorldMatchPaneForRole,
  demoWorldMatchAdminActions,
  demoWorldForbiddenPaths,
  demoWorldIntegrityErrors,
  isDemoWorldRemoteWrite,
  type DemoWorldSnapshot,
} from "../app/demo-world/demo-world-contract";
import {
  demoWorldTabFromSearch,
  loadDemoWorldCore,
  loadDemoWorldSnapshot,
  readDemoWorldSession,
  readInitialDemoWorldSession,
  resetDemoWorldSession,
  writeDemoWorldSession,
} from "../app/demo-world/demo-world-client-state";
import { PROVINCIAL_RANKING_REASON_LABELS } from "../app/ranking/provincial-ranking-contract";
import { buildServiceWorkerSource } from "../app/service-worker-source";
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
  assert.equal(committed.manifest.hash, "34158b4f56a3011c9010b0952f74043435e9f896f0b7ea5fd90e0dfacdfac3ae");
  assert.equal(committed.manifest.mode, DEMO_WORLD_MODE);
  for (const chunk of Object.values(committed.manifest.chunks)) {
    assert.match(chunk, new RegExp(`\\?h=${committed.manifest.hash.slice(0, 16)}$`));
  }
});

test("snapshot has a believable navigable world within the V1 size budget", async () => {
  const world = assertDemoWorldSnapshot(await committedSnapshot());
  assert.equal(world.core.teams.length, 30);
  assert.equal(world.players.players.length, 331);
  assert.equal(world.matches.matches.length, 128);
  assert.equal(world.matches.challenges.length, 48);
  assert.equal(world.core.stories.length, 12);
  assert.equal(world.activity.notifications.length, 12);
  assert.equal(world.core.perspectives.length, 3);
  assert.deepEqual(new Set(world.core.perspectives.map(({ id }) => id)), new Set(["admin", "player", "free-agent"]));
  assert.ok(world.matches.matches.some(({ status }) => status === "scheduled"));
  assert.ok(world.matches.matches.some(({ status }) => status === "finalized"));
  assert.ok(world.matches.matches.some(({ scope }) => scope === "internal"));
  assert.ok(world.matches.matches.some(({ scope }) => scope === "challenge"));
  assert.ok(new Set(world.core.teams.map(({ territory }) => territory)).size >= 4);
  assert.ok(world.players.players.filter(({ market }) => market.openToGuest).length >= 30);
  assert.ok(world.players.players.filter(({ market }) => market.openToGuest).length <= 60);
  assert.ok(Buffer.byteLength(JSON.stringify({ activity: world.activity, core: world.core, matches: world.matches, players: world.players })) < 700_000);
  assert.ok(Buffer.byteLength(JSON.stringify(world.core)) < 100_000);
});

test("initial navigation loads only the compact core and secondary domains stay lazy", async () => {
  const world = await committedSnapshot();
  const chunks = new Map([
    [world.manifest.chunks.activity, world.activity],
    [world.manifest.chunks.core, world.core],
    [world.manifest.chunks.matches, world.matches],
    [world.manifest.chunks.players, world.players],
  ]);
  const calls: string[] = [];
  const originalFetch = globalThis.fetch;
  globalThis.fetch = (async (input: string | URL | Request) => {
    const target = typeof input === "string" ? input : input instanceof URL ? input.toString() : input.url;
    calls.push(target);
    const payload = chunks.get(target);
    return payload
      ? new Response(JSON.stringify(payload), { status: 200 })
      : new Response("not found", { status: 404 });
  }) as typeof fetch;
  try {
    const core = await loadDemoWorldCore(world.manifest);
    assert.deepEqual(core, world.core);
    assert.deepEqual(calls, [world.manifest.chunks.core]);
    await loadDemoWorldSnapshot(world.manifest, core);
    assert.deepEqual(new Set(calls.slice(1)), new Set([
      world.manifest.chunks.activity,
      world.manifest.chunks.matches,
      world.manifest.chunks.players,
    ]));
    assert.equal(calls.includes(world.manifest.chunks.core, 1), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
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
  assert.ok(world.core.stories.some(({ type }) => type === "attendance"));
  assert.ok(world.core.stories.some(({ type }) => type === "ranking"));
  assert.ok(world.core.stories.some(({ type }) => type === "reward"));
});

test("provincial ranking mirrors Season Score V3 without activating awards", async () => {
  const world = await committedSnapshot();
  const provincial = world.core.provincialRanking;
  assert.equal(provincial.awardsEnabled, false);
  assert.deepEqual(provincial.formula.weights, { competition: 0.3, opposition: 0.15, quality: 0.55 });
  assert.equal(provincial.formula.minimumValidChallenges, 15);
  assert.equal(provincial.formula.minimumLogicalOpponents, 6);
  assert.equal(provincial.formula.minimumRatingReliability, 0.45);
  assert.equal(provincial.formula.activityWindowWeeks, 12);
  assert.equal(provincial.ranking.items.length, 10);
  assert.equal(provincial.ranking.pagination?.total, 32);
  for (const item of provincial.ranking.items) {
    const calculated = Number((item.components.quality * 0.55 + item.components.competition * 0.3 + item.components.opposition * 0.15).toFixed(2));
    assert.equal(item.score, calculated);
  }
  assert.equal(provincial.showcases["my-rank"].position, 27);
  assert.equal(provincial.showcases["my-rank"].entryKey, "demo_ranking_entry_27");
  assert.equal(provincial.showcases["my-rank"].eligibilityState, "eligible");
  assert.equal(provincial.showcases.ineligible.eligibilityState, "ineligible");
  assert.equal(provincial.showcases.provisional.eligibilityState, "provisional");
  assert.equal(provincial.showcases["pending-review"].eligibilityState, "pending_integrity_review");
  assert.deepEqual(provincial.showcases["pending-review"].reasonCodes, ["ranking_review_pending"]);
  assert.equal(PROVINCIAL_RANKING_REASON_LABELS.ranking_review_pending, "Pendiente de verificación.");
  const rankingStory = world.core.stories.find(({ id }) => id === "demo_story_012")!;
  assert.deepEqual(rankingStory.referenceIds, ["demo_player_006", "demo_ranking_entry_27"]);
});

test("attendance history distinguishes played, justified absence, late cancellation and no-show", async () => {
  const world = await committedSnapshot();
  assert.ok(world.matches.attendance.length >= 120);
  assert.deepEqual(
    new Set(world.matches.attendance.map(({ status }) => status)),
    new Set(["played", "excused_absence", "late_cancellation", "unexcused_no_show"]),
  );
  const matches = new Map(world.matches.matches.map((match) => [match.id, match]));
  for (const record of world.matches.attendance) {
    assert.equal(matches.get(record.matchId)?.status, "finalized");
  }
});

test("hat-trick reward supports the local NEW and equip lifecycle", async () => {
  const world = await committedSnapshot();
  const perspective = world.core.perspectives.find(({ id }) => id === "player")!;
  const achievement = world.activity.achievements.find(({ key, subjectId }) => key === "player.all.hat_tricks.001" && subjectId === perspective.playerId)!;
  const box = world.activity.rewardBoxes.find(({ achievementId }) => achievementId === achievement.id)!;
  assert.equal(box.state, "pending");
  assert.equal(box.rewardCosmeticKey, "player.frame.barrio.copper");
  assert.match(achievement.evidence, /3 goles confirmados/);
  const source = await readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8");
  assert.match(source, /newCosmeticKeys/);
  assert.match(source, /equippedCosmeticKeys/);
  assert.match(source, /Equipar/);
});

test("the PWA caches Demo World navigation and immutable hashed chunks without offline writes", () => {
  const source = buildServiceWorkerSource("demo-world-test");
  assert.match(source, /"\/demo"/);
  assert.match(source, /\/demo-world\/v1\/manifest\.json/);
  assert.match(source, /isImmutableDemoChunk/);
  assert.match(source, /url\.searchParams\.has\("h"\)/);
  assert.match(source, /request\.method !== "GET"/);
  assert.match(source, /url\.search \? await cache\.match\(url\.pathname\)/);
  assert.match(source, /cachedPage \|\| cachedRoute \|\| cache\.match\(APP_SHELL_URL\)/);
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
    equippedCosmeticKeys: ["player.frame.barrio.copper"],
    inventoryCosmeticKeys: ["player.frame.barrio.copper"],
    newCosmeticKeys: [],
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
      equippedCosmeticKeys: [],
      inventoryCosmeticKeys: [],
      newCosmeticKeys: [],
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

test("leaving the admin perspective restores a visible match pane", () => {
  assert.equal(demoWorldMatchPaneForRole("admin", "player"), "proximo");
  assert.equal(demoWorldMatchPaneForRole("admin", "visitor"), "proximo");
  assert.equal(demoWorldMatchPaneForRole("admin", "admin"), "admin");
  assert.equal(demoWorldMatchPaneForRole("alineacion", "player"), "alineacion");
});

test("the player market is progressively revealed instead of rendering an endless initial list", async () => {
  const source = await readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8");
  assert.match(source, /DEMO_WORLD_MARKET_PAGE_SIZE = 12/);
  assert.match(source, /marketPlayers\.slice\(0, visiblePlayerCount\)/);
  assert.match(source, /Mostrar más/);
});

test("game mode keeps perspective switching reachable from Profile", async () => {
  const appSource = await readFile(path.join(root, "app/demo-world/demo-world-app.tsx"), "utf8");
  const styles = await readFile(path.join(root, "app/demo-world/demo-world.module.css"), "utf8");
  assert.match(appSource, /Perspectiva en modo juego/);
  assert.match(appSource, /onPerspective=\{choosePerspective\}/);
  assert.match(styles, /\.gamePerspectiveSelect\s*\{\s*display:\s*none/);
  assert.match(styles, /\.gamePerspectiveSelect\s*\{\s*display:\s*grid/);
});

test("game landscape keeps the team identity in its own viewport row", async () => {
  const styles = await readFile(path.join(root, "app/demo-world/demo-world.module.css"), "utf8");
  const landscape = styles.slice(styles.indexOf("@media (orientation: landscape)"));

  assert.match(
    landscape,
    /\.identityBand\s*\{\s*min-height:\s*calc\(100dvh - var\(--game-nav-height, 48px\)\)/,
  );
  assert.doesNotMatch(landscape, /\.identityBand\s*\{\s*min-height:\s*100%/);
});

test("Demo World honors the explicit product theme over the system preference", async () => {
  const styles = await readFile(path.join(root, "app/demo-world/demo-world.module.css"), "utf8");
  assert.match(styles, /:global\(:root\[data-theme="light"\]\) \.shell/);
  assert.match(styles, /:global\(:root:not\(\[data-theme="dark"\]\)\) \.shell/);
});

test("legacy demo entry redirects to the isolated public Demo World", async () => {
  const [homeSource, styles] = await Promise.all([
    readFile(path.join(root, "app/page.tsx"), "utf8"),
    readFile(path.join(root, "app/globals.css"), "utf8"),
  ]);
  assert.match(homeSource, /window\.location\.replace\(`\/demo/);
  assert.match(homeSource, /window\.location\.assign\("\/demo"\)/);
  assert.match(homeSource, /if \(isDemoMode\) \{[\s\S]*data-product-entry="no-team"/);
  assert.match(homeSource, /href="\/demo">Probar Mundo Demo<\/Link>/);
  assert.match(homeSource, /Mundo Demo/);
  assert.doesNotMatch(homeSource, /Lo que ves son datos de ejemplo/);
  assert.doesNotMatch(homeSource, /Crear mi grupo limpio/);
  assert.ok(homeSource.indexOf('data-product-entry="no-team"') < homeSource.indexOf("data-mobile-tab={activeMobileTab}"));
  assert.match(styles, /@media \(orientation: landscape\) and \(max-height: 560px\)[\s\S]*\.demo-world-entry-shell \.hero/);
  assert.match(styles, /\.demo-world-entry-shell > \.demo-world-entry/);
});
