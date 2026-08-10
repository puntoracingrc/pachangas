import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { TEAM_SHIELD_COSMETIC_V1_CANDIDATES } from "../app/team-shield-cosmetics-catalog";
import { TEAM_SHIELD_PREMIUM_BORDER_TEXTURES } from "../app/team-shield-premium-border-assets";
import { TEAM_SHIELD_DEFAULT_CONFIG, teamShieldSportingChecksum } from "../app/team-shield-contract";

const root = process.cwd();
const source = (relativePath: string) => readFile(path.join(root, relativePath), "utf8");

test("only Copper, Silver and Gold use the static premium border pipeline", () => {
  const approved = ["copper", "silver", "gold"] as const;
  for (const material of approved) {
    const item = TEAM_SHIELD_COSMETIC_V1_CANDIDATES.find(({ key }) => key === `team.shield.border.${material}`);
    assert.equal(item?.render.premiumBorder, "prerender-material-v1");
    assert.equal(item?.render.premiumTexture, TEAM_SHIELD_PREMIUM_BORDER_TEXTURES[material]);
  }
  assert.equal(
    TEAM_SHIELD_COSMETIC_V1_CANDIDATES.filter(({ render }) => render.premiumBorder === "prerender-material-v1").length,
    3,
  );
});

test("premium border assets are content-hashed, immutable and compact", async () => {
  const config = await source("next.config.ts");
  assert.match(config, /team-shield-premium-v1\/\:path\*/);
  assert.match(config, /max-age=31536000, immutable/);

  for (const asset of Object.values(TEAM_SHIELD_PREMIUM_BORDER_TEXTURES)) {
    assert.match(asset, /\.[0-9a-f]{8}\.webp$/);
    const details = await stat(path.join(root, "public", asset.replace(/^\//, "")));
    assert.ok(details.size > 30_000 && details.size < 40_000);
  }
});

test("renderer keeps 24px and 32px on the lightweight fallback", async () => {
  const [renderer, styles] = await Promise.all([
    source("app/_components/team-shield-view.tsx"),
    source("app/_components/team-shield-view.module.css"),
  ]);
  assert.match(renderer, /size !== 24/);
  assert.match(renderer, /size !== 32/);
  assert.match(renderer, /data-premium-border=\{premiumBorderEnabled\}/);
  assert.match(styles, /data-premium-border="true"/);
  assert.doesNotMatch(renderer, /ball_premium|DeviceOrientation|premiumBallMotion|from ["']three["']|@react-three/i);
});

test("the border migration has no rewards, grants, sensors or sporting mutations", async () => {
  const migration = await source("supabase/migrations/20260810221436_team_shield_premium_borders_v1.sql");
  assert.equal((migration.match(/'team\.shield\.border\.(?:copper|silver|gold)'/g) ?? []).length, 3);
  assert.doesNotMatch(migration, /ball_premium|deviceorientation|three\.js|\.glb/i);
  assert.doesNotMatch(migration, /insert into public\.pachanga_(?:reward|team_cosmetic_inventory)/i);
  assert.doesNotMatch(migration, /pachanga_player_profiles|rating_evidence|season_score|calibrated_facets/i);
  assert.doesNotMatch(migration, /team_cosmetics_enabled\s*=\s*true|team_cosmetic_rewards_enabled\s*=\s*true/i);
});

test("equipping a premium border leaves sporting data byte-identical", () => {
  const sporting = {
    facets: [{ key: "pace", value: 76 }, { key: "defending", value: 71 }],
    rating: 74,
    seasonScore: 391,
    tops: [{ key: "province", value: 8 }],
  };
  const checksum = teamShieldSportingChecksum(sporting);
  const equipped = { ...TEAM_SHIELD_DEFAULT_CONFIG, borderKey: "team.shield.border.gold" };
  assert.equal(equipped.borderKey, "team.shield.border.gold");
  assert.equal(teamShieldSportingChecksum(sporting), checksum);
});
