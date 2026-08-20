import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

async function source(path: string) {
  return readFile(new URL(path, root), "utf8");
}

const migrationPaths = [
  "supabase/migrations/20260820075321_ranking_productization_r1_contract_persistence.sql",
  "supabase/migrations/20260820075323_ranking_productization_r2_refresh_read_model.sql",
  "supabase/migrations/20260820075324_ranking_productization_r3_integrity_eligibility.sql",
  "supabase/migrations/20260820075326_ranking_productization_r4_provincial_product.sql",
  "supabase/migrations/20260820182038_ranking_productization_r5_http_conflicts.sql",
  "supabase/migrations/20260820184126_ranking_productization_r6_legacy_surface_hardening.sql",
  "supabase/migrations/20260820204159_ranking_productization_r7_empty_publication.sql",
] as const;

test("Season Score V3 is frozen with the approved product formula", async () => {
  const migration = await source(migrationPaths[0]);
  assert.match(migration, /'weights', jsonb_build_object\('quality', 55, 'competition', 30, 'opposition', 15\)/);
  assert.match(migration, /'volumeModel', 'recent_30'/);
  assert.match(migration, /'ratingConfidenceModel', 'full'/);
  assert.match(migration, /'opponentDecay', jsonb_build_array\(1, 1, 0\.5, 0\.25, 0\)/);
  assert.match(migration, /'minimumValidChallenges', 15/);
  assert.match(migration, /'minimumLogicalOpponents', 6/);
  assert.match(migration, /'minimumRatingReliability', 0\.45/);
  assert.match(migration, /'minimumMatchCompetitiveConfidence', 0\.72/);
  assert.match(migration, /'minimumNetworkDiversity', 0\.68/);
  assert.match(migration, /'scorePenalty', false/);
  assert.match(migration, /'awardsEnabled', false/);
  assert.match(migration, /pachanga_protect_season_score_formula_v1/);
  assert.match(migration, /Season Score formula versions are immutable/);
});

test("the canonical calculator reads Rating V2 and never mutates protected systems", async () => {
  const migration = await source(migrationPaths[1]);
  const calculator = migration.match(
    /create or replace function private\.pachanga_calculate_season_score_v1[\s\S]*?(?=create or replace function)/,
  )?.[0] ?? "";
  assert.match(calculator, /from public\.pachanga_player_profiles profiles/);
  assert.match(calculator, /from public\.pachanga_player_rating_snapshots snapshots/);
  assert.match(calculator, /rating_overall \* \(0\.72 \+ rating_reliability \* 0\.28\)/);
  assert.match(calculator, /quality_value \* 5\.5/);
  assert.match(calculator, /competition_value \* 3/);
  assert.match(calculator, /opposition_value \* 1\.5/);
  assert.doesNotMatch(calculator, /update public\.pachanga_player_profiles/i);
  assert.doesNotMatch(calculator, /insert into public\.pachanga_(?:individual_rating|rating_vote|achievement|reward)/i);
  assert.doesNotMatch(calculator, /conduct|no_show|sanction|achievement|reward|cosmetic/i);
});

test("all ranking writes are revisioned, idempotent and serialized by operationId", async () => {
  const migrations = await Promise.all(migrationPaths.map(source));
  const combined = migrations.join("\n");
  assert.match(combined, /pachanga_lock_ranking_operation_v1/);
  assert.match(combined, /ranking-operation:/);
  assert.match(combined, /operationId already belongs to a different ranking action/);
  assert.match(combined, /using errcode = '40001'/);
  assert.match(combined, /replace\(definition, '''40001''', '''PT409'''\)/);
  assert.match(combined, /for update skip locked/);
  assert.match(combined, /with ordered as materialized/);
  assert.match(combined, /expected_season_revision/);
  assert.match(combined, /server_sequence/);
  assert.match(combined, /snapshot_revision desc, snapshots\.server_sequence desc, snapshots\.id desc/);
  for (const migration of migrations) {
    assert.match(migration, /set lock_timeout = '5s'/);
    assert.match(migration, /set statement_timeout = '5min'/);
  }
});

test("public ranking reads are minimized and direct internal reads remain closed", async () => {
  const migration = await source(migrationPaths[3]);
  const publicReader = migration.match(
    /create or replace function public\.get_pachanga_provincial_ranking_v1[\s\S]*?(?=create or replace function public\.get_my_pachanga_provincial_rank_v1)/,
  )?.[0] ?? "";
  assert.match(migration, /revoke all on table public\.pachanga_provincial_ranking_entries from public, anon, authenticated/);
  assert.doesNotMatch(migration, /grant select on table public\.pachanga_provincial_ranking_entries to authenticated/);
  assert.match(publicReader, /'entryKey', encode\(extensions\.digest/);
  assert.match(publicReader, /'displayName'/);
  assert.match(publicReader, /'components'/);
  assert.doesNotMatch(publicReader, /'playerProfileId'|'networkDiversity'|'competitiveConfidence'|'trophyReadiness'/);
  assert.match(migration, /grant select on table public\.pachanga_provincial_ranking_publications to authenticated/);
});

test("legacy pre-ranking flag RPCs are unreachable from clients", async () => {
  const hardening = await source(migrationPaths[5]);
  assert.match(hardening, /revoke all on function public\.get_pachanga_platform_flags_pre_ranking_v1\(\)/);
  assert.match(hardening, /revoke all on function public\.set_pachanga_platform_flag_pre_ranking_v1/);
  assert.match(hardening, /from public, anon, authenticated, service_role/);
  assert.match(hardening, /has_function_privilege/);
});

test("the browser consumes canonical snapshots and invalidates only by publication revision", async () => {
  const [page, api, cron] = await Promise.all([
    source("app/ranking/provincial-ranking-product.tsx"),
    source("app/api/admin/rankings/route.ts"),
    source("app/api/internal/rankings/refresh/route.ts"),
  ]);
  assert.match(page, /get_pachanga_provincial_ranking_v1/);
  assert.match(page, /get_my_pachanga_provincial_rank_v1/);
  assert.match(page, /pachangas:ranking:v1:/);
  assert.match(page, /publication\.revision/);
  assert.match(page, /pachanga_provincial_ranking_publications/);
  assert.doesNotMatch(page, /quality\s*\*\s*0\.55|competition\s*\*\s*0\.30|opposition\s*\*\s*0\.15/);
  assert.doesNotMatch(api, /SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(api, /requireSameOriginMutation/);
  assert.match(cron, /platformServiceClient/);
  assert.match(cron, /CRON_SECRET/);
  assert.match(cron, /process_pachanga_ranking_refresh_queue_v1/);
});

test("product flags start disabled and provincial awards cannot be activated", async () => {
  const [contract, product] = await Promise.all([
    source(migrationPaths[0]),
    source(migrationPaths[3]),
  ]);
  assert.match(contract, /season_score_product_enabled boolean not null default false/);
  assert.match(contract, /provincial_rankings_product_enabled boolean not null default false/);
  assert.match(contract, /provincial_awards_enabled boolean not null default false/);
  assert.match(product, /Provincial awards remain disabled in Ranking Productization V1/);
  assert.match(product, /'awardsGranted', 0/);
  assert.match(product, /'rewardsGranted', 0/);
});

test("Control Center exposes fail-closed operational ranking health", async () => {
  const product = await source(migrationPaths[3]);
  assert.match(product, /pachanga_ranking_operational_health_v1/);
  assert.match(product, /'UNKNOWN'|'CRITICAL'|'WARNING'|'OK'/);
  assert.match(product, /FORMULA_CHECKSUM_MISMATCH/);
  assert.match(product, /RANKING_REFRESH_STUCK/);
  assert.match(product, /RANKING_QUEUE_GROWING/);
  assert.match(product, /RANKING_REBUILD_DIFF_PENDING/);
  assert.match(product, /RANKING_INTEGRITY_BACKLOG/);
  assert.match(product, /PILOT_PUBLICATION_MISSING/);
});

test("an empty pilot still publishes a canonical territorial revision", async () => {
  const migration = await source(migrationPaths[6]);
  assert.match(migration, /insert into public\.pachanga_provincial_ranking_publications/);
  assert.match(migration, /from private\.pachanga_ranking_season_territories territories/);
  assert.match(migration, /territories\.product_enabled/);
  assert.match(migration, /pachanga_ranking_json_checksum_v1\('\[\]'::jsonb\)/);
  assert.match(migration, /entry_count, ranked_count/);
  assert.match(migration, /Private ranking publisher became client executable/);
});
