import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { knownClientWriteRpcNames } from "../app/pwa-write-classifier";
import { normalizeCanonicalSocialProfile } from "../app/social-team-core-contract";

const source = (path: string) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("free-agent market state is part of the canonical social profile", () => {
  const profile = normalizeCanonicalSocialProfile({
    approximateTime: "20:00-22:00",
    confirmedRevision: 4,
    displayName: "Jugador libre",
    generalArea: "Barcelona",
    marketPublished: true,
    preferredModality: "futbol7",
    primaryPosition: "Mediocentro / pivote",
    revision: 4,
    serverSequence: 42,
    updatedAt: "2026-09-05T06:00:00Z",
    usualDays: ["M", "J"],
  });
  assert.equal(profile?.marketPublished, true);
  assert.equal(profile?.confirmedRevision, 4);

  const legacyCache = normalizeCanonicalSocialProfile({
    approximateTime: "20:00-22:00",
    displayName: "Copia antigua",
    generalArea: "Barcelona",
    preferredModality: "futbol7",
    primaryPosition: "Defensa central",
    revision: 2,
    usualDays: ["S"],
  });
  assert.equal(legacyCache?.marketPublished, false);
});

test("free-agent Mercado uses one classified server command and no optimistic authority", async () => {
  const [profileClient, marketplaceClient, classifier] = await Promise.all([
    source("app/perfil/profile-client.tsx"),
    source("app/mercado/marketplace-client.tsx"),
    source("app/pwa-write-classifier.ts"),
  ]);
  assert.ok(knownClientWriteRpcNames().includes("command_pachanga_free_agent_market_v1"));
  assert.match(classifier, /command_pachanga_free_agent_market_v1/);
  assert.match(profileClient, /rpc\("command_pachanga_free_agent_market_v1"/);
  assert.match(profileClient, /expected_revision:\s*socialProfile\.confirmedRevision/);
  assert.match(profileClient, /operation_id:\s*crypto\.randomUUID\(\)/);
  assert.match(profileClient, /payload:\s*\{\}/);
  assert.match(profileClient, /normalizeCanonicalSocialProfile\(result\.data\)/);
  assert.match(profileClient, /Sin conexión: tu perfil no se ha publicado ni retirado/);
  assert.doesNotMatch(profileClient, /\.from\("pachanga_market_profiles"\)\.(?:insert|update|upsert|delete)/);
  assert.match(marketplaceClient, /table:\s*"pachanga_market_invalidations_v1"/);
  assert.match(marketplaceClient, /\.from\("pachanga_market_profiles"\)/);
  assert.match(marketplaceClient, /\.eq\("id", profileId\)/);
  assert.match(marketplaceClient, /normalizeProfile\(profileResult\.data as MarketRow\)/);
  assert.doesNotMatch(marketplaceClient, /normalizeProfile\(event\.new/);
  assert.doesNotMatch(marketplaceClient, /invalidation\.active/);
});

test("free-agent Mercado migration derives the projection and preserves Rating V2", async () => {
  const sql = await source("supabase/migrations/20260905061857_controlled_pilot_free_agent_market_authority_v1.sql");
  assert.match(sql, /action_name not in \('market\.publish', 'market\.unpublish'\)/);
  assert.match(sql, /body <> '\{\}'::jsonb/);
  assert.match(sql, /FREE_AGENT_MARKET_REQUIRES_NO_TEAM/);
  assert.match(sql, /current_profile\.display_name/);
  assert.match(sql, /current_profile\.general_area/);
  assert.match(sql, /current_profile\.usual_days/);
  assert.match(sql, /current_profile\.preferred_modality/);
  assert.match(sql, /pachanga_social_request_hash_v1/);
  assert.match(sql, /pachanga_social_replay_v1/);
  assert.match(sql, /pachanga_social_record_evidence_v1/);
  assert.match(sql, /marketPublished', exists/);
  assert.match(sql, /create table if not exists public\.pachanga_market_invalidations_v1/);
  assert.match(sql, /pachanga_market_invalidations_registered_read_v1/);
  assert.match(sql, /alter publication supabase_realtime\s+add table public\.pachanga_market_invalidations_v1/s);
  assert.match(sql, /pachanga_social_profile_sync_free_agent_market_v1/);
  assert.match(sql, /pachanga_membership_pause_free_agent_market_v1/);
  assert.match(sql, /grant execute on function public\.command_pachanga_free_agent_market_v1/);
  assert.doesNotMatch(sql, /update\s+public\.pachanga_player_profiles/i);
  assert.doesNotMatch(sql, /insert\s+into\s+public\.pachanga_player_profiles/i);
  assert.doesNotMatch(sql, /current_facets\s*=|current_overall\s*=|rating\s*=/i);
});
