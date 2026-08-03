import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import {
  CHALLENGEABLE_PROFILE_CACHE_MAX_AGE_MS,
  CHALLENGEABLE_SEARCH_CACHE_MAX_AGE_MS,
  challengeableProfileCacheKey,
  challengeableSearchCacheKey,
  normalizeChallengeableTeamProfileSnapshot,
  normalizeChallengeableTeamSearchSnapshot,
  readChallengeableProfileCache,
  readChallengeableSearchCache,
  type ChallengeableTeamSearchFilters,
  writeChallengeableProfileCache,
  writeChallengeableSearchCache,
} from "../app/challengeable-team-contract";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";

class MemoryStorage {
  readonly values = new Map<string, string>();

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }
}

const filters: ChallengeableTeamSearchFilters = {
  day: 4,
  end: "22:00",
  maxDistanceKm: 30,
  maxTeamLevel: 75,
  minTeamLevel: 45,
  modality: "futbol7",
  start: "20:00",
  zoneLabel: "Barcelona",
  zoneLat: 41.3874,
  zoneLng: 2.1686,
};

const profilePayload = {
  canManage: true,
  confirmedRevision: 3,
  group: { groupId: "group-a", name: "Pachangas A", teamCode: "TEAM-A" },
  levelRevision: 2,
  ownLevel: 63.4,
  profile: {
    availability: [{ day: 4, start: "20:00", end: "22:00" }],
    enabled: true,
    maxOpponentLevel: 80,
    minOpponentLevel: 45,
    modalities: ["futbol7"],
    travelRadiusKm: 30,
    zone: { label: "Barcelona", lat: 41.3874, lng: 2.1686, placeId: "own-zone" },
  },
  profileRevision: 3,
  searchRevision: 9,
  serverSequence: 14,
  updatedAt: "2026-08-03T12:00:00.000Z",
};

const searchPayload = {
  confirmedRevision: 9,
  hasMore: false,
  items: [{
    availability: [{ day: 4, start: "20:00", end: "22:00" }],
    distanceKm: 4.8,
    exactAddress: "Must not survive",
    groupId: "group-b",
    levelCompatibility: "compatible",
    maxOpponentLevel: 78,
    minOpponentLevel: 50,
    modalities: ["futbol7"],
    name: "Pachangas B",
    placeId: "private-place",
    profileRevision: 4,
    teamCode: "PRIVATE-CODE",
    teamLevel: 66,
    travelRadiusKm: 20,
    updatedAt: "2026-08-03T12:00:00.000Z",
    zoneLabel: "Sant Adrià de Besòs",
    zoneLat: 41.43,
    zoneLng: 2.21,
  }],
  page: 1,
  pageSize: 12,
  requesterLevel: 63.4,
  requestingGroupId: "group-a",
  searchRevision: 9,
  serverSequence: 14,
  updatedAt: "2026-08-03T12:00:00.000Z",
};

test("normalizes the private manager snapshot but strips unknown public result fields", () => {
  const profile = normalizeChallengeableTeamProfileSnapshot(profilePayload);
  assert.ok(profile);
  assert.equal(profile.profileRevision, 3);
  assert.equal(profile.profile.zone.placeId, "own-zone");

  const search = normalizeChallengeableTeamSearchSnapshot(searchPayload);
  assert.ok(search);
  assert.equal(search.items.length, 1);
  assert.equal(search.items[0].zoneLabel, "Sant Adrià de Besòs");
  const serializedPublicItem = JSON.stringify(search.items[0]);
  assert.doesNotMatch(serializedPublicItem, /exactAddress|placeId|teamCode|zoneLat|zoneLng|PRIVATE-CODE|private-place/);
});

test("read caches are scoped and expire without becoming a second source of truth", () => {
  const storage = new MemoryStorage();
  const now = 1_000_000;
  const profile = normalizeChallengeableTeamProfileSnapshot(profilePayload);
  const search = normalizeChallengeableTeamSearchSnapshot(searchPayload);
  assert.ok(profile && search);

  writeChallengeableProfileCache(storage, "user-a", "group-a", profile, now);
  writeChallengeableSearchCache(storage, "user-a", "group-a", filters, 1, search, now);

  assert.deepEqual(readChallengeableProfileCache(storage, "user-a", "group-a", now + 1), profile);
  assert.deepEqual(readChallengeableSearchCache(storage, "user-a", "group-a", filters, 1, now + 1), search);
  assert.equal(readChallengeableProfileCache(storage, "user-b", "group-a", now + 1), null);
  assert.equal(readChallengeableSearchCache(storage, "user-a", "group-b", filters, 1, now + 1), null);
  assert.equal(readChallengeableProfileCache(storage, "user-a", "group-a", now + CHALLENGEABLE_PROFILE_CACHE_MAX_AGE_MS + 1), null);
  assert.equal(readChallengeableSearchCache(storage, "user-a", "group-a", filters, 1, now + CHALLENGEABLE_SEARCH_CACHE_MAX_AGE_MS + 1), null);

  assert.notEqual(
    challengeableSearchCacheKey("user-a", "group-a", filters, 1),
    challengeableSearchCacheKey("user-a", "group-a", { ...filters, modality: "sala" }, 1),
  );
  assert.notEqual(challengeableProfileCacheKey("user-a", "group-a"), challengeableProfileCacheKey("user-b", "group-a"));
});

test("the PWA bridge blocks only the authoritative profile mutation", () => {
  const endpoint = (rpc: string) => `https://demo.supabase.co/rest/v1/rpc/${rpc}`;
  assert.equal(
    classifySupabaseWrite(endpoint("upsert_pachanga_challengeable_team_profile_authoritative"), { method: "POST" }),
    "rpc:upsert_pachanga_challengeable_team_profile_authoritative",
  );
  for (const rpc of [
    "get_pachanga_challengeable_team_profile",
    "search_pachanga_challengeable_teams",
    "lookup_pachanga_challengeable_team_for_challenge",
  ]) {
    assert.equal(classifySupabaseWrite(endpoint(rpc), { method: "POST" }), null);
  }
});

test("SQL keeps private profile data behind RPCs and pages public results on the server", () => {
  const sql = readFileSync(
    new URL("../supabase/migrations/20260803124125_challengeable_team_profiles.sql", import.meta.url),
    "utf8",
  );
  const searchSql = sql.slice(
    sql.indexOf("create or replace function public.search_pachanga_challengeable_teams"),
    sql.indexOf("create or replace function public.lookup_pachanga_challengeable_team_for_challenge"),
  );

  assert.match(sql, /revoke all on table public\.pachanga_challengeable_team_profiles from public, anon, authenticated/);
  assert.match(sql, /revoke all on table public\.pachanga_challengeable_team_availability from public, anon, authenticated/);
  assert.match(sql, /grant select on table public\.pachanga_challengeable_team_profile_state to authenticated/);
  assert.match(sql, /grant select on table public\.pachanga_challengeable_team_search_state to authenticated/);
  assert.doesNotMatch(sql, /grant select on table public\.pachanga_challengeable_team_profiles to authenticated/i);

  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\('challengeable-team-operation:'/);
  assert.match(sql, /current_revision is distinct from expected_revision/);
  assert.match(sql, /using errcode = 'PT409'/);
  assert.match(sql, /on conflict \(operation_id\) do nothing/);
  assert.match(sql, /profileRevision'[\s\S]*confirmedRevision'[\s\S]*serverSequence'/);

  assert.match(searchSql, /target_page_size integer default 12/);
  assert.match(searchSql, /safe_page_size > 24/);
  assert.match(searchSql, /offset \(safe_page - 1\) \* safe_page_size/);
  assert.match(searchSql, /limit safe_page_size \+ 1/);
  assert.match(searchSql, /6371\.0 \* 2\.0 \* asin/);
  assert.doesNotMatch(searchSql, /'zoneLat'|'zoneLng'|'placeId'|'teamCode'|'address'/);

  assert.match(sql, /public\.pachanga_group_level_v2\(target_group_id, clock_timestamp\(\)\)/);
  assert.match(sql, /refresh_challengeable_level_after_match_snapshot_update/);
  assert.match(sql, /refresh_challengeable_level_after_participant_update/);
  assert.doesNotMatch(sql, /update public\.pachanga_player_profiles/i);
  assert.doesNotMatch(sql, /update public\.pachanga_individual_rating_evidence/i);

  assert.match(sql, /alter publication supabase_realtime add table public\.pachanga_challengeable_team_profile_state/);
  assert.match(sql, /alter publication supabase_realtime add table public\.pachanga_challengeable_team_search_state/);
  assert.doesNotMatch(sql, /alter publication supabase_realtime add table public\.pachanga_challengeable_team_profiles/);
  assert.doesNotMatch(sql, /alter publication supabase_realtime add table public\.pachanga_challengeable_team_profile_events/);
});
