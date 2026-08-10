import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { TEAM_SHIELD_COSMETIC_PROTOTYPES, TEAM_SHIELD_COSMETIC_V1_CANDIDATES } from "../app/team-shield-cosmetics-catalog";
import { TEAM_SHIELD_PREMIUM_BALL_FRAMES, TEAM_SHIELD_PREMIUM_BALL_KEY } from "../app/team-shield-premium-assets";
import {
  advancePremiumOrientationPipeline,
  applyPremiumDeadZone,
  INITIAL_PREMIUM_ORIENTATION_STATE,
  mapPremiumOrientationToViewport,
  normalizePremiumScreenAngle,
  resetPremiumOrientationCalibration,
  resolvePremiumMotionStatus,
  selectPremiumBallFrame,
  smoothPremiumValue,
  STATIC_PREMIUM_BALL_VISUAL,
} from "../app/team-shield-premium-motion";
import { TEAM_SHIELD_DEFAULT_CONFIG, teamShieldSportingChecksum } from "../app/team-shield-contract";

const root = process.cwd();
const source = (relativePath: string) => readFile(path.join(root, relativePath), "utf8");

test("orientation mapping follows screen rotation in portrait and landscape", () => {
  const sample = { beta: 30, gamma: 10 };
  assert.deepEqual(mapPremiumOrientationToViewport(sample, 0), { x: 10, y: 30 });
  assert.deepEqual(mapPremiumOrientationToViewport(sample, 90), { x: 30, y: -10 });
  assert.deepEqual(mapPremiumOrientationToViewport(sample, 180), { x: -10, y: -30 });
  assert.deepEqual(mapPremiumOrientationToViewport(sample, 270), { x: -30, y: 10 });
  assert.equal(normalizePremiumScreenAngle(-90), 270);
  assert.equal(normalizePremiumScreenAngle(94), 90);
});

test("the current device posture becomes neutral and jitter stays still", () => {
  let state = advancePremiumOrientationPipeline(INITIAL_PREMIUM_ORIENTATION_STATE, { beta: 47, gamma: 8 }, 0);
  assert.deepEqual(state.visual, STATIC_PREMIUM_BALL_VISUAL);
  for (const jitter of [-1, -0.5, 0, 0.5, 1, -0.4, 0.3]) {
    const previous = state;
    state = advancePremiumOrientationPipeline(state, { beta: 47 + jitter, gamma: 8 - jitter }, 0);
    assert.equal(state, previous);
  }
  assert.equal(state.visual.frame, STATIC_PREMIUM_BALL_VISUAL.frame);
  assert.equal(state.visual.tiltX, 0);
  assert.equal(state.visual.tiltY, 0);
  assert.equal(applyPremiumDeadZone(1), 0);
});

test("clamp, smoothing and hysteresis keep extreme readings controlled", () => {
  assert.equal(smoothPremiumValue(0, 6), 1.08);
  assert.equal(selectPremiumBallFrame(0.1, 4), 4);
  let state = advancePremiumOrientationPipeline(INITIAL_PREMIUM_ORIENTATION_STATE, { beta: 45, gamma: 0 }, 0);
  for (let index = 0; index < 80; index += 1) {
    state = advancePremiumOrientationPipeline(state, { beta: 180, gamma: 90 }, 0);
  }
  assert.ok(Math.abs(state.visual.tiltX) <= 6);
  assert.ok(Math.abs(state.visual.tiltY) <= 6);
  assert.ok(state.visual.frame >= 0 && state.visual.frame <= 7);
  const unchanged = advancePremiumOrientationPipeline(state, { beta: null, gamma: null }, 0);
  assert.equal(unchanged, state);
  assert.equal(resetPremiumOrientationCalibration(state.visual).neutral, null);
});

test("permission denial and reduced motion resolve to a static premium state", () => {
  assert.equal(resolvePremiumMotionStatus({ enabled: false, permission: "denied", reduced: false }), "denied");
  assert.equal(resolvePremiumMotionStatus({ enabled: true, permission: "granted", reduced: true }), "reduced");
  assert.equal(resolvePremiumMotionStatus({ enabled: false, permission: "unavailable", reduced: false }), "unavailable");
  assert.equal(resolvePremiumMotionStatus({ enabled: true, permission: "granted", reduced: false }), "active");
});

test("sensor permission is gesture driven and every listener is cleaned up", async () => {
  const hook = await source("app/_components/use-team-shield-premium-motion.ts");
  assert.match(hook, /const activate = useCallback\(async \(\) =>/);
  assert.match(hook, /constructor\.requestPermission \? await constructor\.requestPermission\(\)/);
  assert.match(hook, /window\.addEventListener\("deviceorientation"/);
  assert.match(hook, /window\.removeEventListener\("deviceorientation"/);
  assert.match(hook, /document\.addEventListener\("visibilitychange"/);
  assert.match(hook, /document\.removeEventListener\("visibilitychange"/);
  assert.match(hook, /IntersectionObserver/);
  assert.match(hook, /event\.timeStamp - lastSensorUpdateRef\.current < 16/);
  assert.doesNotMatch(hook, /devicemotion|DeviceMotion/);
  assert.doesNotMatch(hook, /localStorage|sessionStorage|supabase|fetch\(|sendBeacon/i);
  assert.doesNotMatch(hook, /requestAnimationFrame/);
});

test("premium LOD uses 2D at 24/32 and multiview only at visible larger sizes", async () => {
  const [renderer, styles, preview] = await Promise.all([
    source("app/_components/team-shield-view.tsx"),
    source("app/_components/team-shield-view.module.css"),
    source("app/_components/team-shield-premium-preview.tsx"),
  ]);
  assert.match(renderer, /size === 24 \|\| size === 32/);
  assert.match(renderer, /data-premium-lod="simplified-2d"/);
  assert.match(renderer, /data-frame-count=\{TEAM_SHIELD_PREMIUM_BALL_FRAMES\.length\}/);
  assert.match(renderer, /prerender-static/);
  assert.match(styles, /data-premium-border="true"/);
  assert.match(styles, /prefers-reduced-motion: reduce/);
  assert.match(preview, /Activar movimiento/);
  assert.match(preview, /Permiso denegado · versión estática/);
});

test("catalog promotes only Premium Ball and Copper/Silver/Gold premium materials", () => {
  const premiumBall = TEAM_SHIELD_COSMETIC_PROTOTYPES.find((item) => item.key === TEAM_SHIELD_PREMIUM_BALL_KEY);
  assert.equal(premiumBall?.decision, "MANTENER");
  assert.equal(premiumBall?.render.premiumPipeline, "multiview-8-v1");
  for (const material of ["copper", "silver", "gold"]) {
    const item = TEAM_SHIELD_COSMETIC_V1_CANDIDATES.find((candidate) => candidate.key === `team.shield.border.${material}`);
    assert.equal(item?.render.premiumBorder, "prerender-material-v1");
  }
  assert.equal(TEAM_SHIELD_COSMETIC_PROTOTYPES.find((item) => item.key === "team.shield.border.chrome")?.prototype, true);
  assert.equal(TEAM_SHIELD_COSMETIC_PROTOTYPES.find((item) => item.key === "team.shield.symbol.crown_iq")?.prototype, true);
});

test("content-hashed assets are immutable, reproducible and small", async () => {
  const config = await source("next.config.ts");
  const preparation = await source("scripts/team-shield-premium-3d/prepare-v1-assets.mjs");
  assert.match(config, /team-shield-premium-v1\/\:path\*/);
  assert.match(config, /max-age=31536000, immutable/);
  assert.match(preparation, /createHash\("sha256"\)/);
  for (const asset of TEAM_SHIELD_PREMIUM_BALL_FRAMES) {
    assert.match(asset, /\.[0-9a-f]{8}\.webp$/);
    const details = await stat(path.join(root, "public", asset.replace(/^\//, "")));
    assert.ok(details.size > 4_000 && details.size < 40_000);
  }
});

test("the incremental catalog migration has no reward mapping or sporting mutation", async () => {
  const migration = await source("supabase/migrations/20260810201451_team_shield_premium_3d_v1_catalog.sql");
  assert.match(migration, /team\.shield\.symbol\.ball_premium/);
  assert.match(migration, /team\.shield\.border\.gold/);
  assert.match(migration, /on conflict \(cosmetic_key\) do update/);
  assert.doesNotMatch(migration, /insert into public\.pachanga_(?:reward|team_cosmetic_inventory)/i);
  assert.doesNotMatch(migration, /pachanga_player_profiles|rating_evidence|season_score|calibrated_facets/i);
  assert.doesNotMatch(migration, /team_cosmetics_enabled\s*=\s*true|team_cosmetic_rewards_enabled\s*=\s*true/i);
});

test("premium equipment leaves every sporting checksum byte-identical", () => {
  const sporting = {
    facets: [{ key: "pace", value: 76 }, { key: "defending", value: 71 }],
    rating: 74,
    seasonScore: 391,
    tops: [{ key: "province", value: 8 }],
  };
  const checksum = teamShieldSportingChecksum(sporting);
  const equipped = {
    ...TEAM_SHIELD_DEFAULT_CONFIG,
    borderKey: "team.shield.border.gold",
    primarySymbolKey: TEAM_SHIELD_PREMIUM_BALL_KEY,
  };
  assert.equal(equipped.primarySymbolKey, TEAM_SHIELD_PREMIUM_BALL_KEY);
  assert.equal(teamShieldSportingChecksum(sporting), checksum);
});
