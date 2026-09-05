import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  ASSESSMENT_INITIAL_QUESTION_GROUPS,
  ASSESSMENT_INITIAL_STEP_COUNT,
  ASSESSMENT_MODE_OPTIONS,
  assessmentInitialIsComplete,
  assessmentSharesFromSelectedModes,
} from "../app/player-assessment-flow-contract";
import {
  INITIAL_TECHNICAL_QUESTIONS,
  calculateApplicableAdvancedQuestions,
  calculateInitialRatings,
  type InitialRatingInput,
} from "../app/laboratorio-ficha-jugador/_engine/player-rating-engine";
import {
  canonicalAdvancedAssessmentInput,
  canonicalInitialAssessmentInput,
} from "../app/rating-assessment-contract";

const profile = readFileSync(new URL("../app/perfil/profile-client.tsx", import.meta.url), "utf8");
const cosmetics = readFileSync(new URL("../app/personalizar-carta/page.tsx", import.meta.url), "utf8");
const onboarding = readFileSync(new URL("../app/perfil/test-inicial/page.tsx", import.meta.url), "utf8");
const onboardingStyles = readFileSync(new URL("../app/perfil/test-inicial/page.module.css", import.meta.url), "utf8");
const route = readFileSync(new URL("../app/api/ratings/assessment/route.ts", import.meta.url), "utf8");
const home = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const serviceWorker = readFileSync(new URL("../app/service-worker-source.ts", import.meta.url), "utf8");
const migration = readFileSync(
  new URL("../supabase/migrations/20260905084509_restore_initial_assessment_profile_onboarding_v1.sql", import.meta.url),
  "utf8",
);
const staging = readFileSync(
  new URL("./initial-assessment-profile-onboarding-v1-staging-e2e.mjs", import.meta.url),
  "utf8",
);

function completeInput(): InitialRatingInput {
  return {
    primaryPosition: "central_midfielder",
    secondaryPositions: [],
    modeShares: assessmentSharesFromSelectedModes(["futsal_5", "football_7", "football_11"]),
    experienceLevel: "regular_pachangas",
    yearsSinceLevel: 0,
    frequency: "weekly",
    answers: Object.fromEntries(INITIAL_TECHNICAL_QUESTIONS.map((question) => [question.id, 3])) as InitialRatingInput["answers"],
    calculatedAt: "2026-09-05T08:00:00.000Z",
  };
}

test("Perfil exposes the real initial assessment instead of looping through cosmetics", () => {
  assert.match(profile, /Hacer test inicial y crear mi carta/);
  assert.match(profile, /href=\{initialAssessmentComplete \? "\/personalizar-carta" : "\/perfil\/test-inicial"\}/);
  assert.match(profile, /assessmentCompleted\(profile, "initial"\)/);
  assert.match(profile, /Mejorar precisión de mi ficha/);
  assert.match(cosmetics, /href="\/perfil\/test-inicial">Hacer test inicial y crear mi carta/);
  assert.doesNotMatch(cosmetics, /missingProfile \? <Link href="\/\?mobile=perfil"/);
});

test("the dedicated onboarding reuses every existing initial question and mode", () => {
  assert.deepEqual(ASSESSMENT_MODE_OPTIONS.map((option) => option.mode), ["futsal_5", "football_7", "football_11"]);
  assert.equal(ASSESSMENT_INITIAL_QUESTION_GROUPS.length, 10);
  assert.equal(ASSESSMENT_INITIAL_STEP_COUNT, 15);
  assert.deepEqual(
    ASSESSMENT_INITIAL_QUESTION_GROUPS.flatMap((group) => group.questionIds),
    INITIAL_TECHNICAL_QUESTIONS.map((question) => question.id),
  );
  assert.equal(assessmentInitialIsComplete(completeInput()), true);
  assert.match(onboardingStyles, /orientation:landscape\) and \(max-height:560px\)/);
  assert.match(onboardingStyles, /max-height:calc\(100% - 30px\);overflow-x:hidden;overflow-y:auto/);
  assert.match(onboardingStyles, /player-assessment-title>button\)\{grid-column:2;grid-row:1\/span 2\}/);
});

test("the server canonicalizes answers and ignores client timestamps or extra fields", () => {
  const input = completeInput();
  const canonical = canonicalInitialAssessmentInput({
    ...input,
    calculatedAt: "1999-01-01T00:00:00.000Z",
    email: "must-not-persist@example.test",
    answers: { ...input.answers, injected: 5 },
  });
  assert.equal("calculatedAt" in canonical, false);
  assert.equal("email" in canonical, false);
  assert.deepEqual(Object.keys(canonical.answers), INITIAL_TECHNICAL_QUESTIONS.map((question) => question.id));
  assert.throws(() => canonicalInitialAssessmentInput({ ...input, frequency: "forged" }), /Invalid frequency/);

  const applicable = calculateApplicableAdvancedQuestions(calculateInitialRatings(canonical));
  const advanced = canonicalAdvancedAssessmentInput({
    answers: Object.fromEntries(applicable.map((question) => [question.id, 3])),
    evaluatorUserId: "forged",
  }, canonical);
  assert.deepEqual(Object.keys(advanced.answers), applicable.map((question) => question.id));
  assert.equal("evaluatorUserId" in advanced, false);
});

test("the client stores only a draft and waits for the canonical response", () => {
  assert.match(onboarding, /pachangas-player-assessment-draft-v1/);
  assert.match(onboarding, /clientWriteFetch\("api:ratings-assessment", "\/api\/ratings\/assessment"/);
  assert.match(onboarding, /if \(!response\.ok\)/);
  assert.match(onboarding, /normalizeSnapshot\(payload\)/);
  assert.match(onboarding, /setSnapshot\(canonical\)/);
  assert.match(onboarding, /removeItem\(draftKey\(userId, flow\.kind\)\)/);
  assert.match(onboarding, /Sin conexión: ninguna ficha se ha confirmado/);
  assert.match(onboarding, /postgres_changes/);
  assert.match(onboarding, /table: "pachanga_social_invalidations_v1"/);
  assert.match(onboarding, /event\.new\?\.entity_type === "rating_profile"/);
  assert.match(onboarding, /table: "pachanga_group_events"/);
  assert.match(onboarding, /window\.addEventListener\("online", refreshCanonical\)/);
  assert.match(serviceWorker, /"\/perfil\/test-inicial"/);
  assert.doesNotMatch(onboarding, /from\("pachanga_player_profiles"\)\.(insert|update|upsert)/);
});

test("the API derives actor, membership, player and calculations on the server", () => {
  assert.match(route, /const \{ client, user \} = await authedSupabaseClient\(request\)/);
  assert.match(route, /\.from\("pachanga_group_members"\)/);
  assert.match(route, /ownedPlayer = players\.find\(\(player\) => player\.ownerUserId === userId\)/);
  assert.match(route, /calculateSharedAssessmentResult\(/);
  assert.match(route, /p_actor_user_id: user\.id/);
  assert.match(route, /persist_pachanga_player_assessment_self_authoritative_v1/);
  assert.match(route, /export async function GET/);
  assert.match(route, /Cache-Control": "private, no-store"/);
  assert.doesNotMatch(route, /assessmentResult\??:/);
  assert.doesNotMatch(route, /service_role/i);
});

test("the standalone authority is private, idempotent, revisioned and auditable", () => {
  assert.match(migration, /private\.pachanga_player_assessment_self_receipts_v1/);
  assert.match(migration, /private\.pachanga_player_assessment_self_events_v1/);
  assert.match(migration, /pachanga_player_assessment_self_sequence_v1/);
  assert.match(migration, /pachanga_player_assessment_self_evidence_immutable_v1/);
  assert.match(migration, /pachanga_player_assessment_self_events_profile_sequence_idx/);
  assert.match(migration, /'rating_profile'/);
  assert.match(migration, /insert into public\.pachanga_social_invalidations_v1/);
  assert.match(migration, /request_fingerprint/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /profile_version, 0\) <> p_expected_revision/);
  assert.match(migration, /using errcode = 'PT409'/);
  assert.match(migration, /pachanga_recalculate_player_rating_v2\(current_profile\.id, null, null, 'assessment'\)/);
  assert.match(migration, /sync_pachanga_player_profile_to_groups\(current_profile\.id\)/);
  assert.match(migration, /revoke all on function public\.persist_pachanga_player_assessment_self_authoritative_v1[\s\S]*from public, anon, authenticated, service_role/);
  assert.match(migration, /grant execute on function public\.persist_pachanga_player_assessment_self_authoritative_v1[\s\S]*to service_role/);
  assert.match(migration, /revoke all on table private\.pachanga_player_assessment_self_receipts_v1 from public, anon, authenticated, service_role/);
  assert.doesNotMatch(migration, /grant all on table private\.pachanga_player_assessment_self/);
  assert.doesNotMatch(migration, /grant\s+(insert|update|delete)\s+on\s+public/i);
});

test("team onboarding remains available while no-team entry redirects to the universal flow", () => {
  assert.match(home, /if \(!hasRealTeam\) \{\s*window\.location\.assign\(`\/perfil\/test-inicial/);
  assert.match(route, /groupContext\s*\? await service\.rpc\("persist_pachanga_player_assessment_authoritative_v2"/);
});

test("staging certification covers all five onboarding states and fails closed", () => {
  for (const state of ["FLOW_A_NO_TEAM", "FLOW_B_TEAM", "FLOW_C_INVITED", "FLOW_D_INITIAL", "FLOW_E_ADVANCED"]) {
    assert.match(staging, new RegExp(state));
  }
  assert.match(staging, /const args = \[\s*"curl"/);
  assert.match(staging, /spawn\("vercel", args/);
  assert.match(staging, /persist_pachanga_player_assessment_self_authoritative_v1/);
  assert.match(staging, /RATING_PROFILE_ONBOARDING_STAGING_PRODUCTION_TARGET_FORBIDDEN/);
  assert.match(staging, /RATING_PROFILE_ONBOARDING_REALTIME_EVENT_TIMEOUT/);
  assert.match(staging, /FAIL_CLOSED/);
  assert.doesNotMatch(staging, /qonbngfrnrqgmxbdfbea\.supabase\.co/);
});
