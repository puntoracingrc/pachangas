import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";
import {
  TEAM_SOCIAL_CACHE_MAX_AGE_MS,
  normalizeTeamSocialSnapshot,
  readTeamSocialCache,
  teamChallengeModalityLabel,
  teamChallengeStatusLabel,
  teamSocialCacheKey,
  writeTeamSocialCache,
} from "../app/team-social-contract";

class MemoryStorage {
  readonly values = new Map<string, string>();

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }
}

function canonicalSnapshot() {
  return {
    canManage: true,
    challenges: [{
      acceptedAt: null,
      cancelledAt: null,
      createdAt: "2026-08-03T10:00:00.000Z",
      direction: "incoming",
      field: {
        address: "Carrer de la Prova, 1",
        mapsUrl: "https://www.google.com/maps/place/?q=place_id:test",
        name: "Camp Central",
        placeId: "test",
      },
      id: "challenge-1",
      lastProposedBy: "opponent",
      message: "Partido amistoso",
      modality: "futbol7",
      opponent: { groupId: "group-2", name: "Rivales", teamCode: "RIVAL1" },
      proposalNumber: 1,
      rejectedAt: null,
      revision: 2,
      scheduledAt: "2026-08-10T19:00:00.000Z",
      status: "changes_proposed",
      updatedAt: "2026-08-03T10:01:00.000Z",
    }],
    confirmedRevision: 8,
    group: { groupId: "group-1", name: "Locales", teamCode: "LOCAL1" },
    knownOpponents: [{
      firstEncounterAt: "2026-07-01T19:00:00.000Z",
      groupId: "group-2",
      lastEncounterAt: "2026-08-01T19:00:00.000Z",
      lastMatchId: "match-7",
      matchesPlayed: 3,
      name: "Rivales",
      revision: 2,
      teamCode: "RIVAL1",
    }],
    serverSequence: 42,
    socialRevision: 8,
    updatedAt: "2026-08-03T10:01:00.000Z",
  };
}

test("normalizes the canonical social snapshot returned by the server", () => {
  const normalized = normalizeTeamSocialSnapshot(canonicalSnapshot());
  assert.ok(normalized);
  assert.equal(normalized.group.groupId, "group-1");
  assert.equal(normalized.socialRevision, 8);
  assert.equal(normalized.serverSequence, 42);
  assert.equal(normalized.challenges[0]?.revision, 2);
  assert.equal(normalized.knownOpponents[0]?.matchesPlayed, 3);
  assert.equal(normalizeTeamSocialSnapshot({ challenges: [] }), null);
});

test("local social cache is scoped by user and team and expires without becoming authority", () => {
  const storage = new MemoryStorage();
  const snapshot = normalizeTeamSocialSnapshot(canonicalSnapshot());
  assert.ok(snapshot);
  writeTeamSocialCache(storage, "user-a", "group-1", snapshot, 1_000);

  assert.equal(readTeamSocialCache(storage, "user-b", "group-1", 1_001), null);
  assert.equal(readTeamSocialCache(storage, "user-a", "group-2", 1_001), null);
  assert.equal(readTeamSocialCache(storage, "user-a", "group-1", 1_001)?.serverSequence, 42);
  assert.equal(
    readTeamSocialCache(storage, "user-a", "group-1", 1_000 + TEAM_SOCIAL_CACHE_MAX_AGE_MS + 1),
    null,
  );
  assert.match(teamSocialCacheKey("user-a", "group-1"), /user-a:group-1$/);
});

test("challenge labels stay explicit and compact", () => {
  assert.equal(teamChallengeStatusLabel("changes_proposed"), "Cambios propuestos");
  assert.equal(teamChallengeStatusLabel("accepted"), "Aceptado");
  assert.equal(teamChallengeModalityLabel("sala"), "Fútbol sala");
  assert.equal(teamChallengeModalityLabel("futbol11"), "Fútbol 11");
});

test("the PWA bridge classifies challenge mutations and leaves reads available", () => {
  const endpoint = "https://demo.supabase.co/rest/v1/rpc/";
  assert.equal(
    classifySupabaseWrite(`${endpoint}create_pachanga_team_challenge_authoritative`, { method: "POST" }),
    "rpc:create_pachanga_team_challenge_authoritative",
  );
  assert.equal(
    classifySupabaseWrite(`${endpoint}respond_pachanga_team_challenge_authoritative`, { method: "POST" }),
    "rpc:respond_pachanga_team_challenge_authoritative",
  );
  assert.equal(classifySupabaseWrite(`${endpoint}get_pachanga_team_social_snapshot`, { method: "POST" }), null);
  assert.equal(classifySupabaseWrite(`${endpoint}lookup_pachanga_team_by_code`, { method: "POST" }), null);
});

test("SQL keeps challenges server-authoritative, private, idempotent and revisioned", () => {
  const sql = readFileSync(
    new URL("../supabase/migrations/20260803110628_private_team_challenges_foundation.sql", import.meta.url),
    "utf8",
  );

  assert.match(sql, /create table if not exists public\.pachanga_team_challenges/);
  assert.match(sql, /create table if not exists public\.pachanga_team_challenge_events/);
  assert.match(sql, /create table if not exists public\.pachanga_team_social_operation_receipts/);
  assert.match(sql, /operation_id uuid not null unique/);
  assert.match(sql, /stored_group is distinct from target_group_id/);
  assert.match(sql, /stored_operation_type is distinct from target_operation_type/);
  assert.match(sql, /pg_advisory_xact_lock\(hashtextextended\('team-social-operation:'/);
  assert.match(sql, /expected_revision bigint/);
  assert.match(sql, /using errcode = 'PT409'/);
  assert.match(sql, /for update;/);
  assert.match(sql, /server_sequence bigint not null default nextval\('public\.pachanga_team_social_sequence'/);
  assert.match(sql, /challenges\.updated_at desc,\s*challenges\.id desc/);

  assert.match(sql, /revoke all on table public\.pachanga_team_challenges from public, anon, authenticated/);
  assert.match(sql, /revoke all on table public\.pachanga_team_challenge_events from public, anon, authenticated/);
  assert.match(sql, /grant execute on function public\.create_pachanga_team_challenge_authoritative[\s\S]*to authenticated/);
  assert.match(sql, /grant execute on function public\.respond_pachanga_team_challenge_authoritative[\s\S]*to authenticated/);
  assert.match(sql, /public\.is_pachanga_group_admin\(target_group_id\)/);
  assert.match(sql, /created_by uuid not null references auth\.users/);
  assert.match(sql, /actor_user_id uuid not null references auth\.users/);

  assert.match(sql, /alter publication supabase_realtime add table public\.pachanga_team_social_state/);
  assert.doesNotMatch(sql, /alter publication supabase_realtime add table public\.pachanga_team_challenges/);
  assert.doesNotMatch(sql, /grant (select|insert|update|delete|all) on table public\.pachanga_team_challenges to authenticated/i);
});

test("known opponents derive only from finalized server snapshots without changing Rating V2", () => {
  const sql = readFileSync(
    new URL("../supabase/migrations/20260803110628_private_team_challenges_foundation.sql", import.meta.url),
    "utf8",
  );

  assert.match(sql, /join public\.pachanga_match_rating_snapshots snapshots/);
  assert.match(sql, /snapshots\.state = 'active'/);
  assert.match(sql, /order by snapshots\.finalized_at desc, opponents\.host_group_id, opponents\.match_id/);
  assert.match(sql, /create table if not exists public\.pachanga_known_opponents/);
  assert.doesNotMatch(sql, /update public\.pachanga_player_profiles/i);
  assert.doesNotMatch(sql, /update public\.pachanga_rating_evidence/i);
  assert.doesNotMatch(sql, /calibrated_facets\s*=/i);
  assert.doesNotMatch(sql, /externally_calibrated_level\s*=/i);
});
