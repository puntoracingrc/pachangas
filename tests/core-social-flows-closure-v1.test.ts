import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { classifySupabaseWrite } from "../app/pwa-write-classifier";
import { teamChallengeStatusLabel } from "../app/team-social-contract";
import { CORE_SOCIAL_V2_FLOWS, createCoreSocialV2Clone } from "../simulation/synthetic-world/src/core-social-v2";
import { createSyntheticWorld } from "../simulation/synthetic-world/src/generator";

const migrationPath = "supabase/migrations/20260809214500_core_social_flows_closure_v1.sql";

test("Core Social V2 clones the world and covers every requested product flow", () => {
  const source = createSyntheticWorld({ mode: "ephemeral", seed: 20260809 });
  source.revision = 313;
  source.state.eventSequence = 69_458;
  const before = structuredClone(source);
  const { audit, clone } = createCoreSocialV2Clone(source, 20260820);

  assert.deepEqual(source, before, "the V1 source world must remain byte-for-byte unchanged in memory");
  assert.notEqual(clone.id, source.id);
  assert.equal(audit.source.revision, 313);
  assert.equal(audit.source.sequence, 69_458);
  assert.equal(audit.coverage.length, CORE_SOCIAL_V2_FLOWS.length);
  assert.ok(audit.coverage.every(({ status, timesExecuted }) => status === "PASS" && timesExecuted > 0));
  assert.ok(Object.values(audit.preserved).every(Boolean));
  assert.equal(audit.stories.length, 10);
  assert.deepEqual(
    audit.stories.filter(({ id }) => [
      "challenge-guest-lineup-disputed-result",
      "conduct-state-survives-team-change",
      "counterproposal-at-expiry-boundary",
      "leave-with-active-market-and-rejoin",
    ].includes(id)).map(({ id }) => id).sort(),
    [
      "challenge-guest-lineup-disputed-result",
      "conduct-state-survives-team-change",
      "counterproposal-at-expiry-boundary",
      "leave-with-active-market-and-rejoin",
    ],
  );
  assert.deepEqual(audit.newGaps.map(({ flow }) => flow).sort(), ["challenge.proposal_ttl", "team.admin_invite.revoke"]);
  assert.ok(clone.state.incidents.filter(({ operation }) => operation === "challenge.proposal_ttl" || operation === "team.admin_invite.revoke").every(({ actual }) => typeof actual.reason === "string" && actual.reason.length > 0));

  const expired = clone.state.challenges.find(({ state }) => state === "expired");
  assert.ok(expired);
  assert.equal(clone.state.matches.some(({ id }) => id === expired.id), false, "expiry must not manufacture a match");
  const expiryEvent = clone.state.events.find(({ flow }) => flow === "challenge.expire");
  assert.deepEqual(
    { achievementsGranted: expiryEvent?.payload.achievementsGranted, knownOpponentCreated: expiryEvent?.payload.knownOpponentCreated, seasonScoreEvidence: expiryEvent?.payload.seasonScoreEvidence },
    { achievementsGranted: 0, knownOpponentCreated: false, seasonScoreEvidence: 0 },
  );

  const disputedMatch = clone.state.matches.find((candidate) => candidate.state === "disputed" && clone.state.events.some(({ entityIds, eventType }) => eventType === "challenge_guest_joined" && entityIds.includes(candidate.id)));
  assert.ok(disputedMatch);
  assert.ok(clone.state.events.some(({ entityIds, flow }) => flow === "match.lineup" && entityIds.includes(disputedMatch.id)));
  assert.ok(clone.state.events.some(({ entityIds, flow }) => flow === "result.counter" && entityIds.includes(disputedMatch.id)));
  assert.ok(clone.state.events.some(({ eventType, payload }) => eventType === "team_member_left" && payload.marketParticipantAccessRevoked === true));
  assert.ok(clone.state.events.some(({ eventType, payload }) => eventType === "team_member_rejoined" && payload.conductHistoryPreserved === true && payload.socialRestrictionDatabaseRegression === true));
  assert.ok(clone.state.events.some(({ eventType, payload }) => eventType === "challenge_counterproposal_won_expiry_race" && payload.expiryTransitionApplied === false));
});

test("the PWA bridge classifies every new Core Social mutation while reads remain reads", () => {
  const endpoint = "https://demo.supabase.co/rest/v1/rpc/";
  for (const rpc of [
    "accept_pachanga_admin_invite_authoritative_v1",
    "leave_pachanga_group_authoritative_v1",
    "remove_pachanga_group_member_authoritative_v1",
    "transfer_pachanga_group_ownership_authoritative_v1",
    "reconcile_pachanga_team_challenge_expiry_v1",
  ]) {
    assert.equal(classifySupabaseWrite(`${endpoint}${rpc}`, { method: "POST" }), `rpc:${rpc}`);
  }
  assert.equal(classifySupabaseWrite(`${endpoint}get_pachanga_team_social_snapshot`, { method: "POST" }), null);
  assert.equal(teamChallengeStatusLabel("expired"), "Caducado");
});

test("the migration keeps authority central, RLS closed and sporting systems isolated", () => {
  const sql = readFileSync(migrationPath, "utf8");
  const app = readFileSync("app/page.tsx", "utf8");

  assert.match(sql, /create or replace function public\.leave_pachanga_group_authoritative_v1/);
  assert.match(sql, /create or replace function public\.remove_pachanga_group_member_authoritative_v1/);
  assert.match(sql, /create or replace function public\.transfer_pachanga_group_ownership_authoritative_v1/);
  assert.match(sql, /create or replace function public\.accept_pachanga_admin_invite_authoritative_v1/);
  assert.match(sql, /create or replace function public\.reconcile_pachanga_team_challenge_expiry_v1/);
  assert.match(sql, /private\.pachanga_reconcile_open_match_lifecycle_v1/);
  assert.match(sql, /pg_advisory_xact_lock/);
  assert.match(sql, /expected_revision bigint/);
  assert.match(sql, /using errcode = 'PT409'/);
  assert.match(sql, /revoke all on function private\.pachanga_depart_group_member_v1[\s\S]*from public, anon, authenticated/);
  assert.doesNotMatch(sql, /grant\s+(delete|update|insert)\s+on\s+public\.pachanga_group_members\s+to\s+authenticated/i);
  assert.doesNotMatch(sql, /update\s+public\.pachanga_player_profiles\s+set/i);
  assert.doesNotMatch(sql, /update\s+public\.pachanga_(player_achievements|reward_boxes|season_scores|rating_evidence)\s+set/i);
  assert.doesNotMatch(sql, /service_role[^;]*(NEXT_PUBLIC|client_metadata)/i);

  assert.match(app, /leave_pachanga_group_authoritative_v1/);
  assert.match(app, /transfer_pachanga_group_ownership_authoritative_v1/);
  assert.match(app, /remove_pachanga_group_member_authoritative_v1/);
  assert.match(app, /accept_pachanga_admin_invite_authoritative_v1/);
});
