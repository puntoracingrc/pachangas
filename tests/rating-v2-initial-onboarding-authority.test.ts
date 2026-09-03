import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { calculateSharedAssessmentResult } from "../app/rating-assessment-contract";
import {
  INITIAL_TECHNICAL_QUESTIONS,
  type InitialRatingInput,
} from "../app/laboratorio-ficha-jugador/_engine/player-rating-engine";

const page = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const route = readFileSync(new URL("../app/api/ratings/assessment/route.ts", import.meta.url), "utf8");
const migration = readFileSync(
  new URL("../supabase/migrations/20260903211715_rating_v2_atomic_initial_assessment_onboarding.sql", import.meta.url),
  "utf8",
);
const stagingRunner = readFileSync(
  new URL("./rating-v2-initial-onboarding-staging-e2e.mjs", import.meta.url),
  "utf8",
);

function initialInput(): InitialRatingInput {
  return {
    age: 31,
    heightCm: 178,
    weightKg: 76,
    primaryPosition: "central_midfielder",
    secondaryPositions: ["attacking_midfielder"],
    modeShares: [
      { mode: "futsal_5", percentage: 10 },
      { mode: "football_7", percentage: 70 },
      { mode: "football_11", percentage: 20 },
    ],
    experienceLevel: "social_league",
    yearsSinceLevel: 0,
    frequency: "weekly",
    answers: Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, 3])) as InitialRatingInput["answers"],
    calculatedAt: "2026-09-03T20:00:00.000Z",
  };
}

test("initial onboarding uses one server-authoritative assessment request", () => {
  const start = page.indexOf("async function completeInitialPlayerAssessment()");
  const end = page.indexOf("async function completeAdvancedPlayerAssessment()", start);
  const implementation = page.slice(start, end);

  assert.ok(start >= 0 && end > start);
  assert.equal((implementation.match(/persistSharedEngineAssessment\s*\(/g) ?? []).length, 1);
  assert.doesNotMatch(implementation, /upsert_pachanga_own_player_profile/);
  assert.match(implementation, /ownPlayerFromCommit\(result, player\.id\)/);
  assert.match(implementation, /No hay conexión con el servidor para crear la ficha/);
});

test("assessment API derives the actor and calculation on the server", () => {
  assert.doesNotMatch(route, /actorUserId\??:/);
  assert.match(route, /const \{ client, user \} = await authedSupabaseClient\(request\)/);
  assert.match(route, /calculateSharedAssessmentResult\(/);
  assert.match(route, /p_actor_user_id: user\.id/);
  assert.match(route, /serviceSupabaseClient\(\)\.rpc\("persist_pachanga_player_assessment_authoritative_v2"/);
  assert.match(route, /Cache-Control": "private, no-store"/);
});

test("shared Rating V2 calculation remains unchanged for the deterministic baseline", () => {
  const result = calculateSharedAssessmentResult({ initialInput: initialInput(), kind: "initial" }).persisted;

  assert.equal(result.engineVersion, "football-rating-v1");
  assert.equal(result.questionnaireVersion, "initial-test-v1");
  assert.equal(result.position, "Mediocentro / pivote");
  assert.ok(Math.abs(result.rating - 5.5) < 1e-9);
  assert.equal(result.reliability, 41.5625);
  for (const value of Object.values(result.v2Facets)) assert.ok(Math.abs(value - 55) < 1e-9);
});

test("migration keeps the profile guard and closes all internal helpers", () => {
  const assessmentInsert = migration.indexOf("insert into public.pachanga_player_assessments");
  const guardedProfileUpsert = migration.indexOf("perform public.upsert_pachanga_own_player_profile", assessmentInsert);

  assert.ok(assessmentInsert >= 0);
  assert.ok(guardedProfileUpsert > assessmentInsert);
  assert.doesNotMatch(migration, /disable trigger/i);
  assert.doesNotMatch(migration, /grant\s+(insert|update|delete)/i);
  assert.match(
    migration,
    /revoke all on function public\.persist_pachanga_player_assessment_v2[\s\S]*from public, anon, authenticated, service_role/,
  );
  assert.match(
    migration,
    /revoke all on function public\.persist_pachanga_player_assessment_authoritative_v2_impl[\s\S]*from public, anon, authenticated, service_role/,
  );
});

test("payload-bound replay is checked again after the group lock", () => {
  const lock = migration.indexOf("for update;", migration.indexOf("persist_pachanga_player_assessment_authoritative_v2_impl"));
  const replayBefore = migration.lastIndexOf("pachanga_operation_replay_v2", lock);
  const replayAfter = migration.indexOf("pachanga_operation_replay_v2", lock);

  assert.ok(replayBefore >= 0);
  assert.ok(replayAfter > lock);
  assert.match(migration, /assessmentRequestFingerprint/);
  assert.match(migration, /using errcode = 'PT409'/);
});

test("staging E2E is synthetic, production-blocked and checks canonical convergence", () => {
  assert.match(stagingRunner, /RATING_V2_ISSUE_165_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(stagingRunner, /env\.projectRef === PRODUCTION_REF/);
  assert.match(stagingRunner, /auth\.admin\.createUser/);
  assert.match(stagingRunner, /Promise\.all\(\[/);
  assert.match(stagingRunner, /pachanga_group_events/);
  assert.match(stagingRunner, /canonicalRows/);
  assert.match(stagingRunner, /EPHEMERAL_BRANCH_DESTRUCTION_REQUIRED/);
});
