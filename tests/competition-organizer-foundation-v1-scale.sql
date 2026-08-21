\set ON_ERROR_STOP on
\timing on

begin;
set local lock_timeout = '5s';
set local statement_timeout = '5min';

create or replace function pg_temp.stable_uuid(value text)
returns uuid language sql immutable as $$ select md5(value)::uuid $$;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table r1_scale_timings(metric text, elapsed_ms numeric);
grant select, insert on table r1_scale_timings to authenticated;

insert into auth.users(id, email)
select pg_temp.stable_uuid('competition-scale-user:' || value),
  'competition-scale-' || value || '@example.test'
from generate_series(1, 1000) value;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select pg_temp.stable_uuid('competition-scale-group:' || value),
  case when value <= 100 then pg_temp.stable_uuid('competition-scale-user:1') else pg_temp.stable_uuid('competition-scale-user:' || value) end,
  'Competition Scale Team ' || value,
  'CF' || lpad(value::text, 6, '0'),
  '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
from generate_series(1, 1000) value;

insert into public.pachanga_match_read_model(
  group_id, match_id, match_state, match_version, configured, lineup_closed,
  finalized, target_players, reserve_limit, source_payload_revision
)
select pg_temp.stable_uuid('competition-scale-group:' || (((value - 1) / 10) + 1)),
  'competition-scale-match-' || value,
  'finalized', 1, true, true, true, 14, 2, 1
from generate_series(1, 10000) value;

select pg_temp.assert_true(
  (select dirty from private.pachanga_canonical_match_health_state where singleton),
  'Source writes must invalidate the materialized canonical health snapshot'
);

do $$
declare started_at timestamptz := clock_timestamp();
begin
  perform private.pachanga_backfill_canonical_matches_v1();
  insert into r1_scale_timings values ('canonical_backfill', extract(epoch from (clock_timestamp() - started_at)) * 1000);
end;
$$;

select pg_temp.assert_true(
  (select count(*) from public.pachanga_canonical_match_bindings where source_kind = 'group_match' and source_id like 'competition-scale-match-%') = 10000,
  'Scale backfill must bind exactly ten thousand group-match sources'
);
select pg_temp.assert_true(
  not (select dirty from private.pachanga_canonical_match_health_state where singleton),
  'Canonical backfill must refresh the materialized health snapshot'
);
select pg_temp.assert_true(
  (select (snapshot -> 'sources' ->> 'groupMatch')::integer from private.pachanga_canonical_match_health_state where singleton) = 10000,
  'Refreshed canonical health must contain the authoritative source count'
);

insert into public.pachanga_competition_organizer_states(organizer_group_id)
select pg_temp.stable_uuid('competition-scale-group:' || value) from generate_series(1, 1000) value;

insert into public.pachanga_competition_entitlement_grants(
  id, organizer_group_id, capability, grant_source, reason, granted_by
)
select pg_temp.stable_uuid('competition-scale-entitlement:' || value),
  pg_temp.stable_uuid('competition-scale-group:' || value),
  'competition_create', 'platform_grant', 'Representative scale fixture',
  pg_temp.stable_uuid('competition-scale-user:1')
from generate_series(1, 1000) value;

insert into public.pachanga_competitions(
  id, organizer_group_id, name, slug, competition_type, created_by
)
select pg_temp.stable_uuid('competition-scale-competition:' || value),
  pg_temp.stable_uuid('competition-scale-group:' || value),
  'Competition Scale ' || value,
  'competition-scale-' || value,
  case when value % 2 = 0 then 'LEAGUE' else 'TOURNAMENT' end,
  case when value <= 100 then pg_temp.stable_uuid('competition-scale-user:1') else pg_temp.stable_uuid('competition-scale-user:' || value) end
from generate_series(1, 500) value;

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, created_by
)
select pg_temp.stable_uuid('competition-scale-edition:' || value),
  pg_temp.stable_uuid('competition-scale-competition:' || value),
  'Edition ' || value, '2026/' || lpad((value % 100)::text, 2, '0'),
  pg_temp.stable_uuid('competition-scale-user:1')
from generate_series(1, 500) value;

insert into public.pachanga_competition_rule_sets(
  id, competition_id, name, created_by
)
select pg_temp.stable_uuid('competition-scale-rule-set:' || value),
  pg_temp.stable_uuid('competition-scale-competition:' || value),
  'Scale rules ' || value,
  pg_temp.stable_uuid('competition-scale-user:1')
from generate_series(1, 100) value;

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  status, effective_from, reason, created_by
)
select pg_temp.stable_uuid('competition-scale-rule-revision:' || series.number),
  pg_temp.stable_uuid('competition-scale-rule-set:' || series.number),
  1, 'competition_rules.v1', document.rule_document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document.rule_document),
  'validated', statement_timestamp(), 'Representative publish scale fixture',
  pg_temp.stable_uuid('competition-scale-user:1')
from generate_series(1, 100) series(number)
cross join lateral (select '{
  "format":{},"registration":{},"structure":{"stageGraph":{"nodes":[],"edges":[]}},
  "results":{"tieBreakCriteria":[],"scoringPolicy":{}},
  "operations":{"hardAvailabilityPolicy":{},"schedulePreferencePolicy":{}},
  "discipline":{},"governance":{},"publication":{},"futureCapabilities":{}
}'::jsonb as rule_document) document;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (pg_temp.stable_uuid('competition-scale-user:1'), 'platform_owner', true);

update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  creation_enabled = true,
  context_binding_enabled = true
where singleton;

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.stable_uuid('competition-scale-user:1'), 'role', 'authenticated')::text, true);

do $$
declare started_at timestamptz; iteration integer; payload jsonb;
begin
  for iteration in 1..100 loop
    started_at := clock_timestamp();
    payload := public.get_my_pachanga_competition_foundation_v1();
    insert into r1_scale_timings values ('organizer_read', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
  for iteration in 1..100 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_platform_competition_foundation_v1(0, 50);
    insert into r1_scale_timings values ('platform_read', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
  for iteration in 1..100 loop
    started_at := clock_timestamp();
    payload := public.command_pachanga_competition_foundation_v1(
      pg_temp.stable_uuid('competition-scale-publish:' || iteration),
      pg_temp.stable_uuid('competition-scale-rule-set:' || iteration),
      1, 'rule_revision.publish',
      jsonb_build_object(
        'ruleRevisionId', pg_temp.stable_uuid('competition-scale-rule-revision:' || iteration),
        'reason', 'Representative publish timing'
      ),
      '{"surface":"competition_scale"}'::jsonb
    );
    insert into r1_scale_timings values ('rule_publish', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

reset role;

do $$
declare started_at timestamptz; iteration integer;
begin
  for iteration in 1..200 loop
    started_at := clock_timestamp();
    perform bindings.canonical_match_id
    from public.pachanga_canonical_match_bindings bindings
    where bindings.source_kind = 'group_match'
      and bindings.source_group_id = pg_temp.stable_uuid('competition-scale-group:' || (((iteration - 1) / 10) + 1))
      and bindings.source_id = 'competition-scale-match-' || iteration
      and bindings.binding_status = 'active';
    insert into r1_scale_timings values ('binding_lookup', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

select pg_temp.assert_true((select max(elapsed_ms) from r1_scale_timings where metric = 'canonical_backfill') < 120000, 'Canonical backfill exceeded 120 seconds');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'binding_lookup') < 50, 'Binding lookup p95 exceeded 50ms');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'organizer_read') < 1000, 'Organizer read p95 exceeded 1000ms');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'platform_read') < 1500, 'Platform read p95 exceeded 1500ms');
select pg_temp.assert_true(not (select dirty from private.pachanga_canonical_match_health_state where singleton), 'Repeated reads must not mutate or stale canonical health');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'rule_publish') < 500, 'Rule publish p95 exceeded 500ms');
select pg_temp.assert_true((select count(*) from private.pachanga_competition_operation_receipts where action = 'rule_revision.publish' and client_metadata ->> 'surface' = 'competition_scale') = 100, 'Publish scale must create one receipt per operation');
select pg_temp.assert_true((select count(*) from private.pachanga_competition_events where action = 'rule_revision.publish' and reason_code = 'Representative publish timing') = 100, 'Publish scale must create one event per operation');
select pg_temp.assert_true(not exists (select 1 from pg_locks where pid = pg_backend_pid() and not granted), 'Scale validation left a waiting lock');

explain (analyze, buffers, format json)
select bindings.canonical_match_id
from public.pachanga_canonical_match_bindings bindings
where bindings.source_kind = 'group_match'
  and bindings.source_group_id = pg_temp.stable_uuid('competition-scale-group:500')
  and bindings.source_id = 'competition-scale-match-5000'
  and bindings.binding_status = 'active';

explain (analyze, buffers, format json)
select competitions.id, competitions.name, competitions.status
from public.pachanga_competitions competitions
where competitions.organizer_group_id = pg_temp.stable_uuid('competition-scale-group:1')
order by competitions.updated_at desc, competitions.id;

select jsonb_build_object(
  'adminCompetitionsP50Ms', round((select percentile_cont(0.50) within group (order by elapsed_ms) from r1_scale_timings where metric = 'platform_read')::numeric, 3),
  'adminCompetitionsP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'platform_read')::numeric, 3),
  'bindingLookupP50Ms', round((select percentile_cont(0.50) within group (order by elapsed_ms) from r1_scale_timings where metric = 'binding_lookup')::numeric, 3),
  'bindingLookupP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'binding_lookup')::numeric, 3),
  'canonicalMatches', (select count(*) from public.pachanga_canonical_matches where created_by is null),
  'competitions', 500,
  'eventRows', (select count(*) from private.pachanga_competition_events where action = 'rule_revision.publish' and reason_code = 'Representative publish timing'),
  'indexBytes', (
    select coalesce(sum(pg_relation_size(indexrelid)), 0)
    from pg_index where indrelid in (
      'public.pachanga_canonical_match_bindings'::regclass,
      'public.pachanga_competitions'::regclass,
      'public.pachanga_competition_rule_revisions'::regclass,
      'private.pachanga_competition_events'::regclass,
      'private.pachanga_competition_operation_receipts'::regclass
    )
  ),
  'organizerReadP50Ms', round((select percentile_cont(0.50) within group (order by elapsed_ms) from r1_scale_timings where metric = 'organizer_read')::numeric, 3),
  'organizerReadP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'organizer_read')::numeric, 3),
  'receiptRows', (select count(*) from private.pachanga_competition_operation_receipts where action = 'rule_revision.publish' and client_metadata ->> 'surface' = 'competition_scale'),
  'rulePublishP50Ms', round((select percentile_cont(0.50) within group (order by elapsed_ms) from r1_scale_timings where metric = 'rule_publish')::numeric, 3),
  'rulePublishP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from r1_scale_timings where metric = 'rule_publish')::numeric, 3),
  'sourceBindings', (select count(*) from public.pachanga_canonical_match_bindings where source_kind = 'group_match' and source_id like 'competition-scale-match-%'),
  'teams', 1000
) as competition_scale_summary;

rollback;
