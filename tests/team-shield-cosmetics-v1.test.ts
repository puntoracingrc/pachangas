import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";
import {
  TEAM_SHIELD_BASE_CATALOG,
  TEAM_SHIELD_COSMETIC_PROTOTYPES,
  TEAM_SHIELD_COSMETIC_V1_CANDIDATES,
} from "../app/team-shield-cosmetics-catalog";
import {
  TEAM_SHIELD_COSMETIC_SLOTS,
  TEAM_SHIELD_DEFAULT_CONFIG,
  normalizeTeamShieldConfig,
  teamShieldEquippedKeys,
  teamShieldSportingChecksum,
} from "../app/team-shield-contract";
import { runTeamShieldSyntheticWorld } from "../simulation/synthetic-world/scripts/team-shield-cosmetics-v1";

const migration = readFileSync(
  new URL("../supabase/migrations/20260810151241_team_shield_cosmetics_v1.sql", import.meta.url),
  "utf8",
);
const registeredUserHardening = readFileSync(
  new URL("../supabase/migrations/20260810152852_team_shield_registered_user_hardening.sql", import.meta.url),
  "utf8",
);
const foreignKeyIndexes = readFileSync(
  new URL("../supabase/migrations/20260810153058_team_shield_cosmetic_fk_indexes.sql", import.meta.url),
  "utf8",
);
const shieldLab = readFileSync(new URL("../app/laboratorio-cosmeticos-escudo/page.tsx", import.meta.url), "utf8");
const shieldLabStyles = readFileSync(new URL("../app/laboratorio-cosmeticos-escudo/page.module.css", import.meta.url), "utf8");
const sharedEditorStyles = readFileSync(new URL("../app/_components/cosmetics-editor.module.css", import.meta.url), "utf8");

test("the new base library is complete before rewards and the lab selects 16 V1 candidates", () => {
  assert.equal(TEAM_SHIELD_BASE_CATALOG.length, 28);
  assert.equal(TEAM_SHIELD_COSMETIC_PROTOTYPES.length, 28);
  assert.equal(TEAM_SHIELD_COSMETIC_V1_CANDIDATES.length, 16);
  assert.equal(new Set(TEAM_SHIELD_BASE_CATALOG.map(({ key }) => key)).size, 28);
  assert.equal(new Set(TEAM_SHIELD_COSMETIC_V1_CANDIDATES.map(({ key }) => key)).size, 16);
  assert.equal(TEAM_SHIELD_BASE_CATALOG.filter(({ slot }) => slot === "shape").length, 8);
  assert.equal(TEAM_SHIELD_BASE_CATALOG.filter(({ key }) => key.startsWith("team.shield.color.")).length, 6);
  assert.ok(TEAM_SHIELD_BASE_CATALOG.filter(({ key }) => key.startsWith("team.shield.color.")).every(({ slot }) => slot === null));
  assert.deepEqual(new Set(TEAM_SHIELD_COSMETIC_SLOTS), new Set([
    "shape", "background", "pattern", "primary_symbol", "secondary_symbol",
    "border", "top_ornament", "side_ornament", "bottom_ornament", "effect",
  ]));
});

test("TeamShieldConfig V1 rejects legacy payloads and normalizes bounded visual controls", () => {
  assert.equal(normalizeTeamShieldConfig({ shapeKey: "shape.classic", initials: "OLD" }), null);
  const normalized = normalizeTeamShieldConfig({
    ...TEAM_SHIELD_DEFAULT_CONFIG,
    foundationYear: "20x26",
    initials: " pi q ",
    primarySymbolRotation: 90,
    primarySymbolScale: 4,
  });
  assert.ok(normalized);
  assert.equal(normalized.initials, "PIQ");
  assert.equal(normalized.foundationYear, "2026");
  assert.equal(normalized.primarySymbolRotation, 12);
  assert.equal(normalized.primarySymbolScale, 1.2);
  assert.ok(teamShieldEquippedKeys(normalized).every((key) => key.startsWith("team.shield.")));
});

test("TeamShieldView is the only renderer and has no legacy design adapter", () => {
  const renderer = readFileSync(new URL("../app/_components/team-shield-view.tsx", import.meta.url), "utf8");
  const identity = readFileSync(new URL("../app/equipo/identidad/page.tsx", import.meta.url), "utf8");
  assert.match(renderer, /export function TeamShieldView/);
  assert.match(renderer, /config: TeamShieldConfig/);
  assert.doesNotMatch(renderer, /design\?: TeamShieldConfig|legacy|CrestPreview/);
  assert.match(identity, /<TeamShieldView/);
  assert.doesNotMatch(identity, /function CrestPreview|save_pachanga_team_crest_draft_v1|publish_pachanga_team_crest_v1/);
  assert.match(shieldLab, /item\.slot \? item\.slot\.replaceAll\("_", " "\) : "palette"/);
  assert.match(sharedEditorStyles, /var\(--cosmetics-editor-landscape-offset, 88px\)/);
  assert.match(shieldLabStyles, /--cosmetics-editor-landscape-offset: 108px/);
});

test("the migration creates an independent authoritative shield model and closes legacy writes", () => {
  for (const table of [
    "pachanga_team_shield_state",
    "pachanga_team_shield_loadouts",
    "pachanga_team_shield_versions",
    "pachanga_team_shield_public",
    "pachanga_team_shield_events",
    "pachanga_team_shield_operation_receipts",
  ]) assert.match(migration, new RegExp(`create table if not exists public\\.${table}`));
  assert.match(migration, /team_cosmetics_enabled boolean not null default false/);
  assert.match(migration, /team_cosmetic_rewards_enabled boolean not null default false/);
  assert.match(migration, /raise exception 'Team shield revision is newer[^']*' using errcode = 'PT409'/);
  assert.match(migration, /drop function if exists public\.save_pachanga_team_shield_loadout_v1/);
  assert.match(migration, /revoke execute on function public\.save_pachanga_team_crest_draft_v1/);
  assert.match(migration, /revoke execute on function public\.publish_pachanga_team_crest_v1/);
  assert.match(migration, /grant execute on function public\.grant_pachanga_team_cosmetic_v1[^;]+to service_role/s);
  assert.doesNotMatch(migration, /grant execute on function public\.grant_pachanga_team_cosmetic_v1[^;]+to authenticated/s);
  assert.doesNotMatch(migration, /update public\.pachanga_player_profiles|insert into public\.pachanga_rating_evidence|calibrated_facets\s*=/i);
});

test("public read models hide inventory metadata and every client write crosses the PWA bridge", () => {
  assert.match(migration, /'acquiredAt', case when can_manage then inventory\.unlocked_at else null end/);
  assert.match(migration, /'serverSequence', case when can_manage then coalesce\(inventory\.server_sequence, 0\) else 0 end/);
  assert.equal(classifySupabaseWrite("https://demo.supabase.co/rest/v1/rpc/save_pachanga_team_shield_loadout_v1", { method: "POST" }), "rpc:save_pachanga_team_shield_loadout_v1");
  assert.equal(classifySupabaseWrite("https://demo.supabase.co/rest/v1/rpc/mark_pachanga_team_cosmetics_seen_v1", { method: "POST" }), "rpc:mark_pachanga_team_cosmetics_seen_v1");
  assert.equal(classifySupabaseWrite("https://demo.supabase.co/rest/v1/rpc/get_pachanga_team_shield_snapshot_v1", { method: "POST" }), null);
  assert.match(registeredUserHardening, /not public\.is_registered_pachanga_user\(\)/);
  assert.match(registeredUserHardening, /using \(public\.is_registered_pachanga_user\(\) and public\.is_pachanga_group_member\(group_id\)\)/);
  assert.match(registeredUserHardening, /revoke all on function public\.save_pachanga_team_shield_loadout_v1_impl[^;]+from public, anon, authenticated/s);
  assert.equal((foreignKeyIndexes.match(/create index if not exists/g) ?? []).length, 10);
});

test("shield cosmetics cannot affect sporting data", () => {
  const sporting = {
    facets: [{ key: "defending", value: 73 }],
    rating: 72,
    seasonScore: 314,
    tops: [{ key: "province", value: 4 }],
  };
  const before = teamShieldSportingChecksum(sporting);
  const config = { ...TEAM_SHIELD_DEFAULT_CONFIG, effectKey: "team.shield.effect.glint" };
  assert.equal(config.effectKey, "team.shield.effect.glint");
  assert.equal(teamShieldSportingChecksum(sporting), before);
});

test("Synthetic World exercises 50 teams, duplicates, late admins and revision races", () => {
  const summary = runTeamShieldSyntheticWorld(50);
  assert.deepEqual(summary, {
    currencyGranted: 0,
    duplicateGrants: 50,
    inventories: 100,
    lateAdminsWithoutHistoricalNew: 50,
    ratingChanges: 0,
    staleConflicts: 50,
    teamCount: 50,
    uniqueOperationReceipts: 200,
  });
});
