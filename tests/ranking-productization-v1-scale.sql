\set ON_ERROR_STOP on
\timing on

begin;
set local lock_timeout = '5s';
set local statement_timeout = '5min';

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

select private.pachanga_ranking_stable_uuid_v1('ranking-scale-user:1') as owner_user_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-rebuild-row') as rebuild_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-create') as create_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-open') as open_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-rebuild') as rebuild_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-publish') as publish_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-score-flag') as score_flag_operation_id,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-province-flag') as province_flag_operation_id
\gset

insert into auth.users(id, email, created_at, updated_at)
select private.pachanga_ranking_stable_uuid_v1('ranking-scale-user:' || value::text),
  'ranking-scale-' || value::text || '@example.test',
  clock_timestamp() - interval '2 years',
  clock_timestamp() - interval '2 years'
from generate_series(1, 10000) value;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (:'owner_user_id'::uuid, 'platform_owner', true);

insert into private.pachanga_ranking_territories(
  province_code, province_name, product_allowed
) values
  ('28', 'Madrid', true),
  ('46', 'Valencia', true);

insert into public.pachanga_groups(
  id, owner_id, name, team_code, invite_token, payload, created_at, updated_at
) select
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-group:' || value::text),
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-user:' || value::text),
  'Ranking Scale Team ' || value,
  'RS' || lpad(value::text, 6, '0'),
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-invite:' || value::text),
  '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb,
  clock_timestamp() - interval '2 years',
  clock_timestamp() - interval '2 years'
from generate_series(1, 1000) value;

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name,
  calibrated_overall, current_overall, calibrated_facets, current_facets,
  rating_reliability, rating_evaluator_count, rating_engine_version,
  rating_recalculated_at, profile_version, created_at, updated_at
)
select private.pachanga_ranking_stable_uuid_v1('ranking-scale-profile:' || value::text),
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-user:' || value::text),
  private.pachanga_ranking_stable_uuid_v1(
    'ranking-scale-group:' || ceil(value::numeric / 10)::integer::text
  ),
  'ranking-scale-' || value::text, 'Scale Player ' || value,
  50 + (value % 50), 50 + (value % 50),
  jsonb_build_object('pace',70,'shooting',70,'passing',70,'dribbling',70,'defending',70,'physical',70),
  jsonb_build_object('pace',70,'shooting',70,'passing',70,'dribbling',70,'defending',70,'physical',70),
  80, 5, 'pachangas-rating-v2', clock_timestamp() - interval '1 day', 3,
  clock_timestamp() - interval '2 years', clock_timestamp() - interval '1 day'
from generate_series(1, 10000) value;

select set_config('request.jwt.claim.sub', :'owner_user_id', true);
set local role authenticated;
select public.create_pachanga_ranking_season_v1(
  'ranking-product-v1-scale', 'Ranking Product V1 Scale',
  clock_timestamp() - interval '90 days', clock_timestamp() + interval '30 days',
  array['08', '28', '46']::text[], :'create_operation_id'::uuid,
  'Representative ten thousand player, one thousand team, three province scale fixture'
) as season_response \gset
reset role;
select (:'season_response'::jsonb ->> 'seasonId')::uuid as season_id \gset

set local role authenticated;
select public.transition_pachanga_ranking_season_v1(
  :'season_id'::uuid, 'open', 1, :'open_operation_id'::uuid,
  'Open scale validation season'
) as open_response \gset
reset role;
select (:'open_response'::jsonb ->> 'revision')::bigint as season_revision \gset

insert into private.pachanga_season_score_snapshots(
  season_id, province_code, player_profile_id, snapshot_revision,
  formula_key, formula_version, formula_checksum, evidence_revision,
  rating_input_key, rating_snapshot_id, rating_overall, rating_reliability,
  graph_batch_id, quality_component, competition_component, opposition_component,
  raw_score, visible_score, weighted_challenges, valid_challenges, logical_opponents,
  match_competitive_confidence, network_diversity, eligibility_state,
  reason_codes, safe_reason_codes, integrity_classification, integrity_risk,
  integrity_details, trophy_readiness, trophy_reason_codes,
  evidence_input, lineage, snapshot_checksum, operation_id, generated_at
)
select :'season_id'::uuid,
  case value % 3 when 0 then '08' when 1 then '28' else '46' end,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-profile:' || value::text), 1,
  seasons.formula_key, seasons.formula_version, seasons.formula_checksum,
  encode(extensions.digest(convert_to('ranking-scale-evidence:' || value::text, 'UTF8'), 'sha256'), 'hex'),
  'ranking-scale-rating:' || value::text, null, 50 + (value % 50), 0.80,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-graph'),
  300 + (value % 200), 120 + (value % 120), 50 + (value % 70),
  (300 + (value % 200)) + (120 + (value % 120)) + (50 + (value % 70)),
  round((300 + (value % 200)) + (120 + (value % 120)) + (50 + (value % 70))),
  15 + (value % 20), 15 + (value % 20), 6 + (value % 10),
  0.80, 0.80, 'eligible', '{}'::text[], '{}'::text[], 'clean', 0,
  '{"signals":{},"lowConfidenceRatio":0}'::jsonb, false,
  array['insufficient_challenges']::text[],
  '{"records":[],"strategy":"exclusion_and_hold","window":"recent_30"}'::jsonb,
  jsonb_build_object(
    'scoreReachedAt', '2026-07-01T00:00:00Z',
    'scoreWindowLogicalOpponents', 6 + (value % 10),
    'technicalOpponents', 6 + (value % 10),
    'ratingProfileVersion', 3,
    'formulaConfigurationChecksum', seasons.formula_checksum
  ),
  repeat('0', 64),
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-snapshot:' || value::text),
  '2026-08-20T08:00:00Z'::timestamptz
from generate_series(1, 10000) value
cross join private.pachanga_ranking_seasons seasons
where seasons.id = :'season_id'::uuid;

insert into private.pachanga_ranking_rebuilds(
  id, season_id, rebuild_revision, expected_season_revision, graph_batch_id,
  state, reason, operation_id, actor_user_id
) values (
  :'rebuild_id'::uuid,
  :'season_id'::uuid, 1, :season_revision,
  private.pachanga_ranking_stable_uuid_v1('ranking-scale-graph'),
  'building', 'Materialize ten thousand canonical candidates',
  :'rebuild_operation_id'::uuid, :'owner_user_id'::uuid
);

insert into private.pachanga_ranking_candidates(
  rebuild_id, season_id, province_code, player_profile_id, snapshot_id,
  tie_break, candidate_checksum
)
select :'rebuild_id'::uuid,
  snapshots.season_id, snapshots.province_code, snapshots.player_profile_id, snapshots.id,
  jsonb_build_object(
    'rawScore', snapshots.raw_score,
    'competitiveConfidence', snapshots.match_competitive_confidence,
    'logicalOpponents', snapshots.logical_opponents,
    'ratingReliability', snapshots.rating_reliability,
    'validChallenges', snapshots.valid_challenges,
    'scoreReachedAt', snapshots.lineage ->> 'scoreReachedAt',
    'stableId', snapshots.player_profile_id
  ),
  private.pachanga_ranking_candidate_snapshot_checksum_v1(snapshots.id)
from private.pachanga_season_score_snapshots snapshots
where snapshots.season_id = :'season_id'::uuid;

select clock_timestamp() as materialize_started \gset
select private.pachanga_finalize_ranking_candidate_v1(
  :'rebuild_id'::uuid
) as candidate_checksum \gset
update private.pachanga_ranking_seasons seasons
set ranking_revision = 1
where seasons.id = :'season_id'::uuid;

set local role authenticated;
select public.publish_pachanga_provincial_ranking_v1(
  :'rebuild_id'::uuid,
  :season_revision, :'candidate_checksum', :'publish_operation_id'::uuid,
  'Publish representative ten thousand player candidate'
) as publish_response \gset
reset role;
select extract(epoch from (clock_timestamp() - :'materialize_started'::timestamptz)) * 1000
  as materialize_ms \gset

select pg_temp.assert_true(
  (:'publish_response'::jsonb ->> 'changedCount')::integer = 10000
    and (select count(*) from public.pachanga_provincial_ranking_entries
      where season_id = :'season_id'::uuid) = 10000,
  'Scale publication must materialize exactly ten thousand players');
select pg_temp.assert_true(
  (select count(*) from public.pachanga_groups where name like 'Ranking Scale Team %') = 1000,
  'Scale fixture must contain exactly one thousand teams');
select pg_temp.assert_true(
  (select count(distinct province_code) from public.pachanga_provincial_ranking_entries
    where season_id = :'season_id'::uuid) = 3,
  'Scale publication must cover three independent provinces');
select pg_temp.assert_true(:materialize_ms::numeric < 120000,
  'Ten thousand player finalize and publish must complete under 120 seconds locally');

set local role authenticated;
select public.set_pachanga_platform_flag_v1(
  'season_score_v3', true, 1, :'score_flag_operation_id'::uuid,
  'Activate score for scale read validation'
) as score_flag \gset
select public.set_pachanga_platform_flag_v1(
  'provincial_rankings', true, (:'score_flag'::jsonb ->> 'revision')::bigint,
  :'province_flag_operation_id'::uuid,
  'Activate province for scale read validation'
) as province_flag \gset
reset role;

do $$
declare
  started_at timestamptz := clock_timestamp();
  iteration integer;
  payload jsonb;
  elapsed_ms numeric;
begin
  for iteration in 1..100 loop
    payload := public.get_pachanga_provincial_ranking_v1('08', 0, 10);
    if jsonb_array_length(payload -> 'items') <> 10 then
      raise exception 'Top 10 read returned an unexpected item count';
    end if;
  end loop;
  elapsed_ms := extract(epoch from (clock_timestamp() - started_at)) * 1000;
  raise notice 'RANKING_SCALE_TOP10_100_READS_MS=%', round(elapsed_ms, 2);
  if elapsed_ms > 5000 then
    raise exception 'One hundred cached-shape Top 10 reads exceeded five seconds';
  end if;
end;
$$;

select pg_temp.assert_true(not exists (
  select 1 from pg_locks locks where not locks.granted and locks.pid = pg_backend_pid()
), 'Scale validation must not leave a waiting lock');

explain (analyze, buffers, format json)
select entries.position, entries.display_name, entries.visible_score
from public.pachanga_provincial_ranking_entries entries
where entries.season_id = :'season_id'::uuid
  and entries.province_code = '08'
  and entries.position is not null
order by entries.position
limit 10;

select jsonb_build_object(
  'candidateRows', (select count(*) from private.pachanga_ranking_candidates
    where rebuild_id = :'rebuild_id'::uuid),
  'entryRows', (select count(*) from public.pachanga_provincial_ranking_entries
    where season_id = :'season_id'::uuid),
  'indexBytes', (
    select coalesce(sum(pg_relation_size(indexrelid)), 0)
    from pg_index where indrelid in (
      'private.pachanga_season_score_snapshots'::regclass,
      'private.pachanga_ranking_candidates'::regclass,
      'public.pachanga_provincial_ranking_entries'::regclass
    )
  ),
  'materializeMs', :materialize_ms::numeric,
  'profileRows', 10000,
  'provinceRows', (select count(distinct province_code)
    from public.pachanga_provincial_ranking_entries where season_id = :'season_id'::uuid),
  'teamRows', (select count(*) from public.pachanga_groups
    where name like 'Ranking Scale Team %')
) as ranking_scale_summary;

select 'RANKING_PRODUCTIZATION_V1_SCALE_OK' as result;
rollback;
