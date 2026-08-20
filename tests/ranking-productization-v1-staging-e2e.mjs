import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

import { createClient } from "@supabase/supabase-js";

const url = process.env.RANKING_STAGING_URL;
const publishableKey = process.env.RANKING_STAGING_PUBLISHABLE_KEY;
const ownerEmail = process.env.RANKING_STAGING_OWNER_EMAIL;
const ownerPassword = process.env.RANKING_STAGING_OWNER_PASSWORD;
const playerEmail = process.env.RANKING_STAGING_PLAYER_EMAIL;
const playerPassword = process.env.RANKING_STAGING_PLAYER_PASSWORD;
const outsiderEmail = process.env.RANKING_STAGING_OUTSIDER_EMAIL;
const outsiderPassword = process.env.RANKING_STAGING_OUTSIDER_PASSWORD;

const required = {
  RANKING_STAGING_OUTSIDER_EMAIL: outsiderEmail,
  RANKING_STAGING_OUTSIDER_PASSWORD: outsiderPassword,
  RANKING_STAGING_OWNER_EMAIL: ownerEmail,
  RANKING_STAGING_OWNER_PASSWORD: ownerPassword,
  RANKING_STAGING_PLAYER_EMAIL: playerEmail,
  RANKING_STAGING_PLAYER_PASSWORD: playerPassword,
  RANKING_STAGING_PUBLISHABLE_KEY: publishableKey,
  RANKING_STAGING_URL: url,
};

for (const [name, value] of Object.entries(required)) {
  if (!value) throw new Error(`${name} is required`);
}

function client() {
  return createClient(url, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    realtime: { params: { eventsPerSecond: 20 } },
  });
}

async function signIn(email, password) {
  const supabase = client();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  assert.ok(data.user?.id);
  return supabase;
}

async function rpc(supabase, name, args = {}) {
  const result = await supabase.rpc(name, args);
  if (result.error) throw result.error;
  return result.data;
}

function waitForSubscription(channel) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Realtime subscription timed out")), 12_000);
    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        clearTimeout(timeout);
        resolve();
      }
      if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        clearTimeout(timeout);
        reject(new Error(`Realtime subscription failed: ${status}`));
      }
    });
  });
}

function waitForPublication(register) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Ranking publication event timed out")), 12_000);
    register((payload) => {
      clearTimeout(timeout);
      resolve(payload);
    });
  });
}

const ownerDesktop = await signIn(ownerEmail, ownerPassword);
const ownerMobile = await signIn(ownerEmail, ownerPassword);
const player = await signIn(playerEmail, playerPassword);
const outsider = await signIn(outsiderEmail, outsiderPassword);
const anonymous = client();

async function normalizePreviousStagingRun(supabase) {
  let overview = await rpc(supabase, "get_pachanga_ranking_admin_overview_v1");
  const previousSeasons = overview.seasons.filter(
    (season) => String(season.key).startsWith("ranking-staging-")
      && ["open", "frozen", "closed"].includes(season.status),
  );
  for (const season of previousSeasons) {
    if (season.publishedRevision < 1) {
      throw new Error(`Synthetic season ${season.id} is live without a publication`);
    }
    let current = season;
    const nextStatusByCurrent = { closed: "archived", frozen: "closed", open: "frozen" };
    while (nextStatusByCurrent[current.status]) {
      const nextStatus = nextStatusByCurrent[current.status];
      current = await rpc(supabase, "transition_pachanga_ranking_season_v1", {
        expected_revision: current.revision,
        next_status: nextStatus,
        reason: "Archive the previous completed staging QA season",
        requested_operation_id: randomUUID(),
        target_season_id: season.id,
      });
    }
  }

  overview = await rpc(supabase, "get_pachanga_ranking_admin_overview_v1");
  if (overview.settings.provincialRankingsEnabled) {
    await rpc(supabase, "set_pachanga_platform_flag_v1", {
      expected_revision: overview.settings.revision,
      flag_key: "provincial_rankings",
      next_enabled: false,
      operation_id: randomUUID(),
      reason: "Reset provincial rankings before staging QA",
    });
    overview = await rpc(supabase, "get_pachanga_ranking_admin_overview_v1");
  }
  if (overview.settings.seasonScoreEnabled) {
    await rpc(supabase, "set_pachanga_platform_flag_v1", {
      expected_revision: overview.settings.revision,
      flag_key: "season_score_v3",
      next_enabled: false,
      operation_id: randomUUID(),
      reason: "Reset Season Score before staging QA",
    });
    overview = await rpc(supabase, "get_pachanga_ranking_admin_overview_v1");
  }
  return overview;
}

const initialOverview = await normalizePreviousStagingRun(ownerDesktop);
assert.equal(initialOverview.settings.seasonScoreEnabled, false);
assert.equal(initialOverview.settings.provincialRankingsEnabled, false);
assert.equal(initialOverview.settings.provincialAwardsEnabled, false);

const seasonKey = `ranking-staging-${Date.now()}-${randomUUID().slice(0, 8)}`;
const createOperationId = randomUUID();
const createArgs = {
  ends_at: new Date(Date.now() + 30 * 86_400_000).toISOString(),
  province_codes: ["08"],
  reason: "Ranking Productization V1 authenticated staging QA",
  requested_operation_id: createOperationId,
  season_key: seasonKey,
  season_label: "Ranking staging QA",
  starts_at: new Date(Date.now() - 60 * 86_400_000).toISOString(),
};
const concurrentCreate = await Promise.all([
  ownerDesktop.rpc("create_pachanga_ranking_season_v1", createArgs),
  ownerMobile.rpc("create_pachanga_ranking_season_v1", createArgs),
]);
for (const result of concurrentCreate) assert.equal(result.error, null);
assert.deepEqual(concurrentCreate[0].data, concurrentCreate[1].data);
const seasonId = concurrentCreate[0].data.seasonId;
assert.equal(concurrentCreate[0].data.revision, 1);

const currentVenueMapping = initialOverview.venueMappings.find(
  (mapping) => mapping.placeId === "ranking-place-barcelona",
);
await rpc(ownerDesktop, "map_pachanga_ranking_venue_v1", {
  confidence: 1,
  evidence: { fixture: "ranking-productization-v1-staging" },
  expected_mapping_revision: currentVenueMapping?.revision ?? 0,
  reason: "Map the synthetic Barcelona venue",
  requested_operation_id: randomUUID(),
  target_place_id: "ranking-place-barcelona",
  target_province_code: "08",
});

const transitionResults = await Promise.all([
  ownerDesktop.rpc("transition_pachanga_ranking_season_v1", {
    expected_revision: 1,
    next_status: "open",
    reason: "Open staging ranking season from desktop",
    requested_operation_id: randomUUID(),
    target_season_id: seasonId,
  }),
  ownerMobile.rpc("transition_pachanga_ranking_season_v1", {
    expected_revision: 1,
    next_status: "open",
    reason: "Open staging ranking season from mobile",
    requested_operation_id: randomUUID(),
    target_season_id: seasonId,
  }),
]);
assert.equal(transitionResults.filter(({ error }) => !error).length, 1);
assert.equal(transitionResults.filter(({ error }) => error).length, 1);
const rejectedTransition = transitionResults.find(({ error }) => error)?.error;
assert.equal(rejectedTransition?.code, "PT409");
assert.match(rejectedTransition?.message ?? "", /revision mismatch/i);

const rebuildOperationId = randomUUID();
const rebuildArgs = {
  expected_season_revision: 2,
  reason: "Concurrent deterministic staging rebuild",
  requested_operation_id: rebuildOperationId,
  target_season_id: seasonId,
};
const concurrentRebuild = await Promise.all([
  ownerDesktop.rpc("rebuild_pachanga_provincial_ranking_v1", rebuildArgs),
  ownerMobile.rpc("rebuild_pachanga_provincial_ranking_v1", rebuildArgs),
]);
for (const result of concurrentRebuild) assert.equal(result.error, null);
assert.deepEqual(concurrentRebuild[0].data, concurrentRebuild[1].data);
assert.match(concurrentRebuild[0].data.candidateChecksum, /^[0-9a-f]{64}$/);

const publication = await rpc(ownerDesktop, "publish_pachanga_provincial_ranking_v1", {
  expected_candidate_checksum: concurrentRebuild[0].data.candidateChecksum,
  expected_season_revision: 2,
  reason: "Publish verified staging candidate",
  requested_operation_id: randomUUID(),
  target_rebuild_id: concurrentRebuild[0].data.rebuildId,
});
assert.equal(publication.awardsGranted, 0);
assert.equal(publication.rewardsGranted, 0);

const scoreFlag = await rpc(ownerDesktop, "set_pachanga_platform_flag_v1", {
  expected_revision: initialOverview.settings.revision,
  flag_key: "season_score_v3",
  next_enabled: true,
  operation_id: randomUUID(),
  reason: "Activate Season Score only in staging QA",
});
const provinceFlag = await rpc(ownerDesktop, "set_pachanga_platform_flag_v1", {
  expected_revision: scoreFlag.revision,
  flag_key: "provincial_rankings",
  next_enabled: true,
  operation_id: randomUUID(),
  reason: "Activate provincial ranking only in staging QA",
});
assert.equal(provinceFlag.enabled, true);

const forbiddenAwards = await ownerDesktop.rpc("set_pachanga_platform_flag_v1", {
  expected_revision: provinceFlag.revision,
  flag_key: "provincial_awards",
  next_enabled: true,
  operation_id: randomUUID(),
  reason: "This staging operation must be rejected",
});
assert.ok(forbiddenAwards.error);

const publicRanking = await rpc(anonymous, "get_pachanga_provincial_ranking_v1", {
  page_offset: 0,
  page_size: 10,
  target_province_code: "08",
});
assert.equal(publicRanking.available, true);
assert.ok(publicRanking.items.length > 0 && publicRanking.items.length <= 10);
assert.equal(publicRanking.items[0].position, 1);
assert.match(publicRanking.items[0].entryKey, /^[0-9a-f]{64}$/);
assert.ok(Number.isInteger(publicRanking.publication?.revision));
assert.doesNotMatch(JSON.stringify(publicRanking), /playerProfileId|networkDiversity|competitiveConfidence|trophyReadiness|ratingReliability|integrity_details|evidence_input|reason_codes/);

const ownRank = await rpc(ownerDesktop, "get_my_pachanga_provincial_rank_v1", {
  target_season_id: seasonId,
});
assert.equal(ownRank.available, true);
assert.equal(ownRank.eligibilityState, "eligible");
assert.equal("playerProfileId" in ownRank, false);

const pendingRank = await rpc(player, "get_my_pachanga_provincial_rank_v1", {
  target_season_id: seasonId,
});
assert.notEqual(pendingRank.eligibilityState, "eligible");

const outsiderRank = await rpc(outsider, "get_my_pachanga_provincial_rank_v1", {
  target_season_id: seasonId,
});
assert.equal(outsiderRank.available, false);
assert.equal(outsiderRank.reason, "PLAYER_PROFILE_REQUIRED");

const forbiddenAdmin = await player.rpc("get_pachanga_ranking_admin_overview_v1");
assert.ok(forbiddenAdmin.error);
const forbiddenLegacyFlagRead = await ownerDesktop.rpc("get_pachanga_platform_flags_pre_ranking_v1");
assert.ok(forbiddenLegacyFlagRead.error);
const forbiddenLegacyFlagWrite = await ownerDesktop.rpc("set_pachanga_platform_flag_pre_ranking_v1", {
  expected_revision: 0,
  flag_key: "attendance",
  next_enabled: false,
  operation_id: randomUUID(),
  reason: "Legacy surface must be unreachable",
});
assert.ok(forbiddenLegacyFlagWrite.error);
const forbiddenDirectRead = await ownerDesktop
  .from("pachanga_provincial_ranking_entries")
  .select("id")
  .limit(1);
assert.ok(forbiddenDirectRead.error);

let publicationResolver;
const realtimePublication = waitForPublication((resolve) => {
  publicationResolver = resolve;
});
const realtimeChannel = ownerMobile
  .channel(`ranking-staging-${randomUUID()}`)
  .on("postgres_changes", {
    event: "*",
    filter: "province_code=eq.08",
    schema: "public",
    table: "pachanga_provincial_ranking_publications",
  }, (payload) => publicationResolver?.(payload));
await waitForSubscription(realtimeChannel);
await new Promise((resolve) => setTimeout(resolve, 1_000));

const secondRebuild = await rpc(ownerDesktop, "rebuild_pachanga_provincial_ranking_v1", {
  expected_season_revision: 2,
  reason: "Rebuild for Realtime publication QA",
  requested_operation_id: randomUUID(),
  target_season_id: seasonId,
});
const secondPublication = await rpc(ownerDesktop, "publish_pachanga_provincial_ranking_v1", {
  expected_candidate_checksum: secondRebuild.candidateChecksum,
  expected_season_revision: 2,
  reason: "Publish Realtime staging candidate",
  requested_operation_id: randomUUID(),
  target_rebuild_id: secondRebuild.rebuildId,
});
assert.ok(Number.isInteger(secondPublication.publishedRevision));
assert.ok(secondPublication.publishedRevision > publicRanking.publication.revision);
const realtimeEvent = await realtimePublication;
assert.ok(realtimeEvent && typeof realtimeEvent === "object");
const revalidatedRanking = await rpc(anonymous, "get_pachanga_provincial_ranking_v1", {
  page_offset: 0,
  page_size: 10,
  target_province_code: "08",
});
assert.equal(revalidatedRanking.publication?.revision, secondPublication.publishedRevision);

const finalOverview = await rpc(ownerDesktop, "get_pachanga_ranking_admin_overview_v1");
assert.equal(finalOverview.settings.provincialAwardsEnabled, false);
assert.equal(finalOverview.health.status, "OK");
assert.equal(finalOverview.invariants.ratingV2ReadOnly, true);
assert.equal(finalOverview.invariants.rewardsAffectScore, false);
assert.equal(finalOverview.invariants.conductAffectsScore, false);

await ownerMobile.removeChannel(realtimeChannel);
for (const supabase of [ownerDesktop, ownerMobile, player, outsider]) {
  await supabase.auth.signOut({ scope: "local" });
}

console.log(JSON.stringify({
  awardsRemainDisabled: true,
  idempotentCreateConverged: true,
  idempotentRebuildConverged: true,
  ordinaryUserDeniedAdmin: true,
  ownEligiblePosition: ownRank.position,
  publicEntries: publicRanking.items.length,
  publicRevision: secondPublication.publishedRevision,
  realtimeInvalidation: true,
  seasonId,
  staleRevisionRejected: true,
}));
