\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table ranking_invariants_before as
select
  (select count(*) from public.pachanga_individual_rating_evidence) as rating_evidence,
  (select count(*) from public.pachanga_player_rating_snapshots) as rating_snapshots,
  (select count(*) from private.pachanga_conduct_reports) as conduct_reports,
  (select count(*) from public.pachanga_achievement_grants) as achievements,
  (select count(*) from public.pachanga_reward_grants) as rewards,
  (select count(*) from public.pachanga_player_reward_inventory) as player_inventory,
  (select count(*) from public.pachanga_team_cosmetic_inventory) as team_inventory;

insert into auth.users(id, email, created_at, updated_at)
select private.pachanga_ranking_stable_uuid_v1('ranking-user:' || value::text),
  'ranking-' || value::text || '@example.test',
  clock_timestamp() - interval '2 years',
  clock_timestamp() - interval '2 years'
from generate_series(1, 50) value;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (private.pachanga_ranking_stable_uuid_v1('ranking-user:1'), 'platform_owner', true);

insert into public.pachanga_groups(
  id, owner_id, name, team_code, invite_token, payload, created_at, updated_at
)
select private.pachanga_ranking_stable_uuid_v1('ranking-group:' || team_number::text),
  private.pachanga_ranking_stable_uuid_v1('ranking-user:' || ((team_number - 1) * 7 + 1)::text),
  'Ranking Team ' || team_number,
  'RNK' || lpad(team_number::text, 3, '0'),
  private.pachanga_ranking_stable_uuid_v1('ranking-invite:' || team_number::text),
  '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb,
  clock_timestamp() - interval '2 years',
  clock_timestamp() - interval '2 years'
from generate_series(1, 7) team_number;

insert into public.pachanga_group_members(group_id, user_id, role, display_name, created_at)
select private.pachanga_ranking_stable_uuid_v1('ranking-group:' || team_number::text),
  private.pachanga_ranking_stable_uuid_v1('ranking-user:' || user_number::text),
  case when player_number = 1 then 'owner' else 'player' end,
  'Ranking Player ' || user_number,
  clock_timestamp() - interval '2 years'
from generate_series(1, 7) team_number
cross join generate_series(1, 7) player_number
cross join lateral (
  select ((team_number - 1) * 7 + player_number)::integer as user_number
) users;

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name,
  calibrated_overall, current_overall, calibrated_facets, current_facets,
  rating_reliability, rating_evaluator_count, rating_engine_version,
  rating_recalculated_at, profile_version, created_at, updated_at
)
select private.pachanga_ranking_stable_uuid_v1('ranking-profile:' || user_number::text),
  private.pachanga_ranking_stable_uuid_v1('ranking-user:' || user_number::text),
  private.pachanga_ranking_stable_uuid_v1('ranking-group:' || team_number::text),
  'ranking-local-' || user_number,
  'Ranking Player ' || user_number,
  case when user_number = 1 then 80 else 75 end,
  case when user_number = 1 then 80 else 75 end,
  jsonb_build_object('pace',75,'shooting',75,'passing',75,'dribbling',75,'defending',75,'physical',75),
  jsonb_build_object('pace',75,'shooting',75,'passing',75,'dribbling',75,'defending',75,'physical',75),
  case when user_number = 1 then 80 else 70 end,
  5,
  'pachangas-rating-v2',
  clock_timestamp() - interval '1 day',
  3,
  clock_timestamp() - interval '2 years',
  clock_timestamp() - interval '1 day'
from generate_series(1, 7) team_number
cross join generate_series(1, 7) player_number
cross join lateral (
  select ((team_number - 1) * 7 + player_number)::integer as user_number
) users;

insert into public.pachanga_player_rating_snapshots(
  id, player_profile_id, snapshot_kind, base_facets, calibrated_facets,
  current_facets, base_overall, calibrated_overall, current_overall,
  reliability, evaluator_count, engine_version, created_at
)
select private.pachanga_ranking_stable_uuid_v1('ranking-rating-snapshot:' || user_number::text),
  private.pachanga_ranking_stable_uuid_v1('ranking-profile:' || user_number::text),
  'recalculation',
  jsonb_build_object('pace',75,'shooting',75,'passing',75,'dribbling',75,'defending',75,'physical',75),
  jsonb_build_object('pace',75,'shooting',75,'passing',75,'dribbling',75,'defending',75,'physical',75),
  jsonb_build_object('pace',75,'shooting',75,'passing',75,'dribbling',75,'defending',75,'physical',75),
  case when user_number = 1 then 80 else 75 end,
  case when user_number = 1 then 80 else 75 end,
  case when user_number = 1 then 80 else 75 end,
  case when user_number = 1 then 80 else 70 end,
  5,
  'pachangas-rating-v2',
  clock_timestamp() - interval '1 day'
from generate_series(1, 49) user_number;

with source_snapshot as (
  select snapshots.*
  from public.pachanga_player_rating_snapshots snapshots
  where snapshots.player_profile_id = private.pachanga_ranking_stable_uuid_v1('ranking-profile:1')
  order by snapshots.created_at desc, snapshots.id desc
  limit 1
), shared_clock as (
  select clock_timestamp() as created_at
)
insert into public.pachanga_player_rating_snapshots(
  id, player_profile_id, snapshot_kind, base_facets, calibrated_facets,
  current_facets, base_overall, calibrated_overall, current_overall,
  reliability, evaluator_count, engine_version, created_at
)
select private.pachanga_ranking_stable_uuid_v1('ranking-rating-tied:' || tied.value),
  source_snapshot.player_profile_id, source_snapshot.snapshot_kind,
  source_snapshot.base_facets, source_snapshot.calibrated_facets,
  source_snapshot.current_facets, source_snapshot.base_overall,
  source_snapshot.calibrated_overall, source_snapshot.current_overall,
  source_snapshot.reliability, source_snapshot.evaluator_count,
  source_snapshot.engine_version, shared_clock.created_at
from source_snapshot
cross join shared_clock
cross join (values ('a'), ('b')) tied(value);

do $$
declare
  match_number integer;
  opponent_team integer;
  challenge_id uuid;
  external_match_id uuid;
  result_operation_id uuid;
  home_group_id uuid := private.pachanga_ranking_stable_uuid_v1('ranking-group:1');
  away_group_id uuid;
  away_user_start integer;
  player_number integer;
begin
  for match_number in 1..15 loop
    opponent_team := 2 + ((match_number - 1) % 6);
    away_group_id := private.pachanga_ranking_stable_uuid_v1('ranking-group:' || opponent_team::text);
    away_user_start := (opponent_team - 1) * 7;
    challenge_id := private.pachanga_ranking_stable_uuid_v1('ranking-challenge:' || match_number::text);
    external_match_id := private.pachanga_ranking_stable_uuid_v1('ranking-match:' || match_number::text);
    result_operation_id := private.pachanga_ranking_stable_uuid_v1('ranking-result:' || match_number::text);

    insert into public.pachanga_team_challenges(
      id, sender_group_id, receiver_group_id, status, scheduled_at, modality,
      field_name, field_address, field_place_id, last_proposed_by_group_id,
      created_by, updated_by, accepted_at, created_at, updated_at
    ) values (
      challenge_id, home_group_id, away_group_id, 'accepted',
      clock_timestamp() - make_interval(days => 31 - match_number),
      'futbol7', 'Ranking Ground', 'Barcelona test ground', 'ranking-place-barcelona',
      home_group_id, private.pachanga_ranking_stable_uuid_v1('ranking-user:1'),
      private.pachanga_ranking_stable_uuid_v1('ranking-user:1'), clock_timestamp(),
      clock_timestamp() - make_interval(days => 40 - match_number), clock_timestamp()
    );
    insert into public.pachanga_external_matches(
      id, challenge_id, home_group_id, away_group_id, scheduled_at, modality,
      field_snapshot, home_level_snapshot, away_level_snapshot, state, revision,
      active_version, official_version, canonical_score_home, canonical_score_away,
      official_at
    ) values (
      external_match_id, challenge_id, home_group_id, away_group_id,
      clock_timestamp() - make_interval(days => 31 - match_number),
      'futbol7', jsonb_build_object(
        'name','Ranking Ground','address','Barcelona test ground','placeId','ranking-place-barcelona'
      ), 75, 75, 'confirmed', 2, 1, 1, 1, 1, clock_timestamp()
    );
    insert into public.pachanga_external_result_versions(
      external_match_id, version, proposal_kind, proposed_by_group_id,
      score_home, score_away, operation_id, created_by
    ) values (
      external_match_id, 1, 'initial', home_group_id, 1, 1,
      result_operation_id, private.pachanga_ranking_stable_uuid_v1('ranking-user:1')
    );
    for player_number in 1..7 loop
      insert into public.pachanga_external_match_participants(
        external_match_id, result_version, group_id, local_player_id,
        player_profile_id, display_name_snapshot, card_snapshot, participant_order
      ) values (
        external_match_id, 1, home_group_id, 'home-' || player_number,
        private.pachanga_ranking_stable_uuid_v1('ranking-profile:' || player_number::text),
        'Ranking Player ' || player_number,
        jsonb_build_object('currentOverall', case when player_number = 1 then 80 else 75 end),
        player_number
      ), (
        external_match_id, 1, away_group_id, 'away-' || player_number,
        private.pachanga_ranking_stable_uuid_v1(
          'ranking-profile:' || (away_user_start + player_number)::text
        ),
        'Ranking Player ' || (away_user_start + player_number),
        jsonb_build_object('currentOverall', 75), player_number
      );
    end loop;
    insert into public.pachanga_external_result_attestations(
      external_match_id, result_version, group_id, actor_user_id, decision,
      operation_id, participant_count, scorer_total
    ) values (
      external_match_id, 1, away_group_id,
      private.pachanga_ranking_stable_uuid_v1('ranking-user:' || (away_user_start + 1)::text),
      'accepted', private.pachanga_ranking_stable_uuid_v1('ranking-attestation:' || match_number::text),
      14, 2
    );
  end loop;
end;
$$;

select
  private.pachanga_ranking_stable_uuid_v1('ranking-user:1') as owner_user_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-season-create') as season_create_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-map-venue') as venue_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-season-open') as season_open_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-rebuild-1') as rebuild_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-publish-1') as publish_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-flag-score') as score_flag_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-flag-province') as province_flag_operation_id
\gset

select set_config('request.jwt.claim.sub', :'owner_user_id', true);
set local role authenticated;
select public.create_pachanga_ranking_season_v1(
  'ranking-product-v1-test', 'Ranking Product V1 Test',
  clock_timestamp() - interval '60 days', clock_timestamp() + interval '30 days',
  array['08']::text[],
  :'season_create_operation_id'::uuid,
  'Canonical ranking product regression'
) as season_response \gset
reset role;

select (:'season_response'::jsonb ->> 'seasonId')::uuid as season_id \gset

set local role authenticated;
select public.map_pachanga_ranking_venue_v1(
  'ranking-place-barcelona', '08', 1, 0,
  :'venue_operation_id'::uuid,
  'Verified fixture venue for ranking regression',
  '{"fixture":true}'::jsonb
) as venue_response \gset
select public.transition_pachanga_ranking_season_v1(
  :'season_id'::uuid, 'open', 1,
  :'season_open_operation_id'::uuid,
  'Open controlled ranking season'
) as open_response \gset
reset role;

select (:'open_response'::jsonb ->> 'revision')::bigint as open_revision \gset

set local role authenticated;
select public.rebuild_pachanga_provincial_ranking_v1(
  :'season_id'::uuid, :open_revision,
  :'rebuild_operation_id'::uuid,
  'Initial deterministic pilot rebuild'
) as rebuild_response \gset
select public.rebuild_pachanga_provincial_ranking_v1(
  :'season_id'::uuid, :open_revision,
  :'rebuild_operation_id'::uuid,
  'Initial deterministic pilot rebuild'
) as rebuild_replay \gset
reset role;

select pg_temp.assert_true(:'rebuild_response'::jsonb = :'rebuild_replay'::jsonb,
  'Rebuild operation must replay idempotently');
select (:'rebuild_response'::jsonb ->> 'rebuildId')::uuid as rebuild_id,
  :'rebuild_response'::jsonb ->> 'candidateChecksum' as candidate_checksum \gset
select pg_temp.assert_true(:'candidate_checksum' ~ '^[0-9a-f]{64}$',
  'Candidate checksum must be deterministic SHA-256');
select pg_temp.assert_true((
  select eligibility_state = 'eligible' and valid_challenges = 15 and logical_opponents = 6
  from private.pachanga_season_score_snapshots
  where season_id = :'season_id'::uuid
    and player_profile_id = private.pachanga_ranking_stable_uuid_v1('ranking-profile:1')
  order by snapshot_revision desc, server_sequence desc, id desc limit 1
), 'Ranking thresholds must be evaluated from canonical evidence');
select pg_temp.assert_true((
  select abs(raw_score - (quality_component + competition_component + opposition_component)) < 0.000001
  from private.pachanga_season_score_snapshots
  where season_id = :'season_id'::uuid
    and player_profile_id = private.pachanga_ranking_stable_uuid_v1('ranking-profile:1')
  order by snapshot_revision desc, server_sequence desc, id desc limit 1
), 'Season Score must equal 55/30/15 contributions without hidden penalty');
select pg_temp.assert_true((
  select abs((quality_component / 5.5) - 75.52) < 0.000001
    and abs(quality_component - 415.36) < 0.000001
  from private.pachanga_season_score_snapshots
  where season_id = :'season_id'::uuid
    and player_profile_id = private.pachanga_ranking_stable_uuid_v1('ranking-profile:1')
  order by snapshot_revision desc, server_sequence desc, id desc limit 1
), 'Quality must apply Rating V2 reliability exactly before the 55 percent contribution');
select pg_temp.assert_true((
  select snapshots.rating_snapshot_id = (
    select rating_snapshots.id
    from public.pachanga_player_rating_snapshots rating_snapshots
    where rating_snapshots.player_profile_id = snapshots.player_profile_id
    order by rating_snapshots.created_at desc, rating_snapshots.id desc
    limit 1
  )
  from private.pachanga_season_score_snapshots snapshots
  where snapshots.season_id = :'season_id'::uuid
    and snapshots.player_profile_id = private.pachanga_ranking_stable_uuid_v1('ranking-profile:1')
  order by snapshots.snapshot_revision desc, snapshots.server_sequence desc, snapshots.id desc limit 1
), 'Same-created-at Rating V2 snapshots must resolve by stable identifier');
select pg_temp.assert_true((
  select count(*) = 2
  from public.pachanga_player_rating_snapshots snapshots
  where snapshots.player_profile_id = private.pachanga_ranking_stable_uuid_v1('ranking-profile:1')
    and snapshots.created_at = (
      select max(latest.created_at)
      from public.pachanga_player_rating_snapshots latest
      where latest.player_profile_id = snapshots.player_profile_id
    )
), 'The stable latest-snapshot regression must contain a real timestamp tie');

select private.pachanga_build_player_ranking_candidate_v1(
  :'season_id'::uuid,
  private.pachanga_ranking_stable_uuid_v1('ranking-profile:1'),
  :open_revision,
  private.pachanga_ranking_stable_uuid_v1('ranking-incremental-compare'),
  :'owner_user_id'::uuid,
  'Compare incremental candidate with a full rebuild'
) as incremental_rebuild_id \gset
select candidate_checksum as incremental_checksum
from private.pachanga_ranking_rebuilds
where id = :'incremental_rebuild_id'::uuid \gset
select private.pachanga_ranking_stable_uuid_v1('ranking-full-compare') as full_compare_operation_id \gset

set local role authenticated;
select public.rebuild_pachanga_provincial_ranking_v1(
  :'season_id'::uuid, :open_revision,
  :'full_compare_operation_id'::uuid,
  'Compare full candidate with incremental state'
) as comparison_full_response \gset
reset role;
select (:'comparison_full_response'::jsonb ->> 'rebuildId')::uuid as comparison_rebuild_id,
  :'comparison_full_response'::jsonb ->> 'candidateChecksum' as comparison_checksum \gset
select pg_temp.assert_true(:'incremental_checksum' = :'comparison_checksum',
  'Incremental and full rebuilds of the same canonical state must have the same checksum');

do $$
declare
  stale_rebuild private.pachanga_ranking_rebuilds%rowtype;
  selected_season private.pachanga_ranking_seasons%rowtype;
begin
  select * into stale_rebuild
  from private.pachanga_ranking_rebuilds rebuilds
  where rebuilds.operation_id = private.pachanga_ranking_stable_uuid_v1('ranking-rebuild-1');
  select * into selected_season
  from private.pachanga_ranking_seasons seasons
  where seasons.season_key = 'ranking-product-v1-test';
  perform public.publish_pachanga_provincial_ranking_v1(
    stale_rebuild.id, selected_season.revision, stale_rebuild.candidate_checksum,
    private.pachanga_ranking_stable_uuid_v1('ranking-stale-publish'),
    'Reject stale ranking publication'
  );
  raise exception 'Stale ranking publication should have failed';
exception when sqlstate 'PT409' then
  null;
end;
$$;

select :'comparison_rebuild_id'::uuid as rebuild_id,
  :'comparison_checksum'::text as candidate_checksum \gset

do $$
begin
  update private.pachanga_season_score_formula_registry formulas
  set configuration = formulas.configuration || '{"tamper":true}'::jsonb
  where formulas.formula_key = 'season_score_v3' and formulas.formula_version = 1;
  raise exception 'Formula registry update should have failed';
exception when others then
  if sqlerrm = 'Formula registry update should have failed' then raise; end if;
end;
$$;

do $$
begin
  delete from private.pachanga_season_score_formula_registry formulas
  where formulas.formula_key = 'season_score_v3' and formulas.formula_version = 1;
  raise exception 'Formula registry delete should have failed';
exception when others then
  if sqlerrm = 'Formula registry delete should have failed' then raise; end if;
end;
$$;

do $$
begin
  update private.pachanga_season_score_snapshots snapshots
  set visible_score = snapshots.visible_score
  where snapshots.season_id = (
    select seasons.id from private.pachanga_ranking_seasons seasons
    where seasons.season_key = 'ranking-product-v1-test'
  );
  raise exception 'Season score snapshot update should have failed';
exception when others then
  if sqlerrm = 'Season score snapshot update should have failed' then raise; end if;
end;
$$;

do $$
begin
  perform public.transition_pachanga_ranking_season_v1(
    (select seasons.id from private.pachanga_ranking_seasons seasons
      where seasons.season_key = 'ranking-product-v1-test'),
    'frozen', 1,
    private.pachanga_ranking_stable_uuid_v1('ranking-stale-season-transition'),
    'Reject stale season revision'
  );
  raise exception 'Stale season revision should have failed';
exception when sqlstate 'PT409' then
  null;
end;
$$;
do $$
begin
  perform public.transition_pachanga_ranking_season_v1(
    (select seasons.id from private.pachanga_ranking_seasons seasons
      where seasons.season_key = 'ranking-product-v1-test'),
    'closed',
    (select seasons.revision from private.pachanga_ranking_seasons seasons
      where seasons.season_key = 'ranking-product-v1-test'),
    private.pachanga_ranking_stable_uuid_v1('ranking-invalid-season-transition'),
    'Reject invalid lifecycle transition'
  );
  raise exception 'Invalid season lifecycle should have failed';
exception when others then
  if sqlerrm = 'Invalid season lifecycle should have failed' then raise; end if;
end;
$$;
select pg_temp.assert_true((
  select status = 'open' and revision = :open_revision
  from private.pachanga_ranking_seasons where id = :'season_id'::uuid
), 'Rejected lifecycle operations must leave canonical season state unchanged');

set local role authenticated;
select public.publish_pachanga_provincial_ranking_v1(
  :'rebuild_id'::uuid, :open_revision, :'candidate_checksum',
  :'publish_operation_id'::uuid,
  'Publish verified pilot candidate'
) as publish_response \gset
reset role;

select pg_temp.assert_true((:'publish_response'::jsonb ->> 'awardsGranted')::integer = 0,
  'Ranking publication must not grant awards');
select pg_temp.assert_true((:'publish_response'::jsonb ->> 'rewardsGranted')::integer = 0,
  'Ranking publication must not grant rewards');

set local role authenticated;
select public.set_pachanga_platform_flag_v1(
  'season_score_v3', true, 1,
  :'score_flag_operation_id'::uuid,
  'Activate verified Season Score product'
) as score_flag \gset
select public.set_pachanga_platform_flag_v1(
  'provincial_rankings', true,
  (:'score_flag'::jsonb ->> 'revision')::bigint,
  :'province_flag_operation_id'::uuid,
  'Activate verified provincial ranking product'
) as province_flag \gset
reset role;

set local role anon;
select public.get_pachanga_provincial_ranking_v1('08', 0, 10) as public_ranking \gset
reset role;
select pg_temp.assert_true((:'public_ranking'::jsonb ->> 'available')::boolean,
  'Published provincial ranking must be publicly readable after activation');
select pg_temp.assert_true(jsonb_array_length(:'public_ranking'::jsonb -> 'items') > 0,
  'Public Top must contain ranked players');
select pg_temp.assert_true(not (:'public_ranking'::jsonb::text ~
  'playerProfileId|networkDiversity|competitiveConfidence|trophyReadiness|ratingReliability|integrity_details|evidence_input|reason_codes'),
  'Public ranking must not expose private lineage or integrity evidence');
select pg_temp.assert_true((:'public_ranking'::jsonb -> 'items' -> 0 ->> 'entryKey') ~ '^[0-9a-f]{64}$',
  'Public ranking must expose only an opaque stable entry key');
select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_provincial_ranking_entries', 'select'),
  'Authenticated clients must not have direct SELECT on the internal ranking read model');

set local role authenticated;
do $$
begin
  perform 1 from public.pachanga_provincial_ranking_entries limit 1;
  raise exception 'Direct ranking entry SELECT should have failed';
exception when insufficient_privilege then
  null;
end;
$$;
reset role;

set local role authenticated;
select public.get_my_pachanga_provincial_rank_v1(:'season_id'::uuid) as own_rank \gset
reset role;
select pg_temp.assert_true((:'own_rank'::jsonb ->> 'available')::boolean,
  'Authenticated player must read own canonical position');
select pg_temp.assert_true(not (:'own_rank'::jsonb ? 'playerProfileId'),
  'Own-position payload must not disclose the universal profile identifier');

select public.get_pachanga_ranking_admin_overview_v1() as ranking_admin_overview \gset
select pg_temp.assert_true(
  :'ranking_admin_overview'::jsonb -> 'health' ->> 'status' in ('OK', 'WARNING'),
  'An active, published ranking must have a determinate non-critical operational health');
select pg_temp.assert_true(not (:'ranking_admin_overview'::jsonb -> 'health' -> 'reasonCodes' ?| array[
  'FORMULA_CHECKSUM_MISMATCH', 'SEASON_INTERVAL_INVALID', 'RANKING_REBUILD_FAILED',
  'RANKING_QUEUE_DEAD_LETTER', 'PILOT_PUBLICATION_MISSING'
]), 'A verified publication must expose no critical ranking health reasons');

update private.pachanga_ranking_seasons
set last_refresh_at = clock_timestamp() - interval '1 hour'
where id = :'season_id'::uuid;
select pg_temp.assert_true(not exists (
  select 1
  from private.pachanga_ranking_refresh_queue queue
  where queue.season_id = :'season_id'::uuid
    and queue.state = 'queued'
), 'Idle-health regression requires an open season with no queued work');
select public.get_pachanga_ranking_admin_overview_v1() as idle_ranking_admin_overview \gset
select pg_temp.assert_true(not (
  :'idle_ranking_admin_overview'::jsonb -> 'health' -> 'reasonCodes' ? 'RANKING_REFRESH_STALE'
), 'An idle canonical ranking must not become stale merely because no evidence changed');

select private.pachanga_enqueue_ranking_refresh_v1(
  :'season_id'::uuid,
  null,
  'season',
  'Verify stale health with pending work',
  'ranking_health_regression',
  'ranking-health-pending-work',
  null,
  private.pachanga_ranking_stable_uuid_v1('ranking-health-pending-work')
) as pending_health_queue_id \gset
select public.get_pachanga_ranking_admin_overview_v1() as pending_ranking_admin_overview \gset
select pg_temp.assert_true(
  :'pending_ranking_admin_overview'::jsonb -> 'health' -> 'reasonCodes' ? 'RANKING_REFRESH_STALE',
  'An open season with old refresh evidence and queued work must report stale health'
);
delete from private.pachanga_ranking_refresh_queue
where id = :'pending_health_queue_id'::uuid;
update private.pachanga_ranking_seasons
set last_refresh_at = clock_timestamp()
where id = :'season_id'::uuid;

select set_config(
  'request.jwt.claim.sub',
  private.pachanga_ranking_stable_uuid_v1('ranking-user:2')::text,
  true
);
set local role authenticated;
do $$
begin
  perform public.get_pachanga_ranking_admin_overview_v1();
  raise exception 'Non-platform user should not read ranking administration';
exception when others then
  if sqlerrm = 'Non-platform user should not read ranking administration' then raise; end if;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub', :'owner_user_id', true);

select pg_temp.assert_true(not has_function_privilege(
  'authenticated',
  'public.get_pachanga_platform_flags_pre_ranking_v1()',
  'EXECUTE'
), 'Legacy pre-ranking flag reader must not be client executable');
select pg_temp.assert_true(not has_function_privilege(
  'authenticated',
  'public.set_pachanga_platform_flag_pre_ranking_v1(text,boolean,bigint,uuid,text)',
  'EXECUTE'
), 'Legacy pre-ranking flag writer must not be client executable');

do $$
begin
  perform public.set_pachanga_platform_flag_v1(
    'provincial_awards', true, 3,
    private.pachanga_ranking_stable_uuid_v1('ranking-awards-forbidden'),
    'This operation must be rejected'
  );
  raise exception 'Provincial awards activation should have failed';
exception when others then
  if sqlerrm = 'Provincial awards activation should have failed' then raise; end if;
end;
$$;

select pg_temp.assert_true(not (select provincial_awards_enabled from private.pachanga_ranking_settings),
  'Provincial awards must remain disabled');
select pg_temp.assert_true((select row(before.*) = row(after.*)
  from ranking_invariants_before before
  cross join lateral (
    select
      (select count(*) from public.pachanga_individual_rating_evidence) as rating_evidence,
      (select count(*) from public.pachanga_player_rating_snapshots) - 51 as rating_snapshots,
      (select count(*) from private.pachanga_conduct_reports) as conduct_reports,
      (select count(*) from public.pachanga_achievement_grants) as achievements,
      (select count(*) from public.pachanga_reward_grants) as rewards,
      (select count(*) from public.pachanga_player_reward_inventory) as player_inventory,
      (select count(*) from public.pachanga_team_cosmetic_inventory) as team_inventory
  ) after), 'Ranking flow must not mutate Rating V2, conduct, rewards or cosmetics');

select private.pachanga_ranking_stable_uuid_v1('ranking-empty-freeze') as empty_freeze_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-empty-close') as empty_close_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-empty-create') as empty_create_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-empty-open') as empty_open_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-empty-rebuild') as empty_rebuild_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-empty-publish') as empty_publish_operation_id
\gset

set local role authenticated;
select public.transition_pachanga_ranking_season_v1(
  :'season_id'::uuid, 'frozen', :open_revision,
  :'empty_freeze_operation_id'::uuid,
  'Freeze the populated season before the empty-pilot regression'
) as empty_freeze_response \gset
select public.transition_pachanga_ranking_season_v1(
  :'season_id'::uuid, 'closed',
  (:'empty_freeze_response'::jsonb ->> 'revision')::bigint,
  :'empty_close_operation_id'::uuid,
  'Close the populated season before the empty-pilot regression'
) as empty_close_response \gset
select public.create_pachanga_ranking_season_v1(
  'ranking-empty-pilot-test', 'Empty provincial pilot',
  timestamptz '2099-01-01 00:00:00+00', timestamptz '2099-12-31 23:59:59+00',
  array['08']::text[], :'empty_create_operation_id'::uuid,
  'Create an empty canonical pilot without synthetic evidence'
) as empty_create_response \gset
select public.transition_pachanga_ranking_season_v1(
  (:'empty_create_response'::jsonb ->> 'seasonId')::uuid,
  'open', 1, :'empty_open_operation_id'::uuid,
  'Open the empty canonical pilot'
) as empty_open_response \gset
select public.rebuild_pachanga_provincial_ranking_v1(
  (:'empty_create_response'::jsonb ->> 'seasonId')::uuid,
  (:'empty_open_response'::jsonb ->> 'revision')::bigint,
  :'empty_rebuild_operation_id'::uuid,
  'Build the empty canonical pilot'
) as empty_rebuild_response \gset
select public.publish_pachanga_provincial_ranking_v1(
  (:'empty_rebuild_response'::jsonb ->> 'rebuildId')::uuid,
  (:'empty_open_response'::jsonb ->> 'revision')::bigint,
  :'empty_rebuild_response'::jsonb ->> 'candidateChecksum',
  :'empty_publish_operation_id'::uuid,
  'Publish the empty canonical pilot'
) as empty_publish_response \gset
reset role;

select pg_temp.assert_true(
  :'empty_rebuild_response'::jsonb ->> 'candidateChecksum' =
    encode(extensions.digest(convert_to('[]', 'UTF8'), 'sha256'), 'hex'),
  'The empty candidate checksum must be deterministic'
);
select pg_temp.assert_true((
  select count(*) = 1
    and min(publications.entry_count) = 0
    and min(publications.ranked_count) = 0
    and min(publications.publication_checksum) =
      encode(extensions.digest(convert_to('[]', 'UTF8'), 'sha256'), 'hex')
  from public.pachanga_provincial_ranking_publications publications
  where publications.season_id = (:'empty_create_response'::jsonb ->> 'seasonId')::uuid
    and publications.province_code = '08'
), 'An empty pilot must publish exactly one canonical Barcelona revision');
select pg_temp.assert_true(
  (:'empty_publish_response'::jsonb ->> 'awardsGranted')::integer = 0
    and (:'empty_publish_response'::jsonb ->> 'rewardsGranted')::integer = 0
    and (:'empty_publish_response'::jsonb ->> 'notificationsSent')::integer = 0,
  'Publishing an empty pilot must not create side effects'
);

set local role anon;
select public.get_pachanga_provincial_ranking_v1('08', 0, 10) as empty_public_ranking \gset
reset role;
select pg_temp.assert_true((:'empty_public_ranking'::jsonb ->> 'available')::boolean,
  'An activated empty pilot must be a valid public read model');
select pg_temp.assert_true(jsonb_array_length(:'empty_public_ranking'::jsonb -> 'items') = 0,
  'An empty pilot must return an empty item list without synthetic players');
select pg_temp.assert_true(
  :'empty_public_ranking'::jsonb -> 'season' ->> 'key' = 'ranking-empty-pilot-test',
  'Public reads must select the newly published empty pilot');

select 'RANKING_PRODUCTIZATION_V1_DB_OK' as result;
rollback;
