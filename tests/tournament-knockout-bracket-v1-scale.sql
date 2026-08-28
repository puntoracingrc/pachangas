set local lock_timeout = '15s';
set local statement_timeout = '240s';
set local session_replication_role = replica;

create or replace function pg_temp.r6c_scale_id(target text)
returns uuid
language sql
immutable
strict
as $$
  select md5('pachangas-r6c-scale|' || target)::uuid;
$$;

-- Clone the minimum parent graph from the canonical fixture. JSON record
-- cloning keeps this volume proof compatible with additive parent columns.
with base as (
  select competitions.*
  from public.pachanga_competitions competitions
  join public.pachanga_tournament_brackets brackets
    on brackets.competition_id = competitions.id
  order by brackets.server_sequence
  limit 1
)
insert into public.pachanga_competitions
select (jsonb_populate_record(
  null::public.pachanga_competitions,
  to_jsonb(base) || jsonb_build_object(
    'id', pg_temp.r6c_scale_id('competition:' || series.value),
    'name', 'R6C Scale Tournament ' || series.value,
    'slug', 'r6c-scale-' || series.value,
    'revision', 1,
    'tournament_revision', 1,
    'server_sequence', nextval('private.pachanga_competition_sequence'),
    'created_at', clock_timestamp(),
    'updated_at', clock_timestamp()
  )
)).*
from base cross join generate_series(1, 10000) series(value);

with base as (
  select editions.*
  from public.pachanga_competition_editions editions
  join public.pachanga_tournament_brackets brackets
    on brackets.edition_id = editions.id
  order by brackets.server_sequence
  limit 1
)
insert into public.pachanga_competition_editions
select (jsonb_populate_record(
  null::public.pachanga_competition_editions,
  to_jsonb(base) || jsonb_build_object(
    'id', pg_temp.r6c_scale_id('edition:' || series.value),
    'competition_id', pg_temp.r6c_scale_id('competition:' || series.value),
    'name', 'R6C Scale Edition ' || series.value,
    'season_label', 'scale-' || series.value,
    'revision', 1,
    'server_sequence', nextval('private.pachanga_competition_sequence'),
    'created_at', clock_timestamp(),
    'updated_at', clock_timestamp()
  )
)).*
from base cross join generate_series(1, 10000) series(value);

with base as (
  select categories.*
  from public.pachanga_competition_categories categories
  join public.pachanga_tournament_brackets brackets
    on brackets.category_id = categories.id
  order by brackets.server_sequence
  limit 1
)
insert into public.pachanga_competition_categories
select (jsonb_populate_record(
  null::public.pachanga_competition_categories,
  to_jsonb(base) || jsonb_build_object(
    'id', pg_temp.r6c_scale_id('category:' || series.value),
    'edition_id', pg_temp.r6c_scale_id('edition:' || series.value),
    'name', 'R6C Scale Category',
    'slug', 'r6c-scale',
    'revision', 1,
    'server_sequence', nextval('private.pachanga_competition_sequence'),
    'created_at', clock_timestamp(),
    'updated_at', clock_timestamp()
  )
)).*
from base cross join generate_series(1, 10000) series(value);

with base as (
  select stages.*
  from public.pachanga_competition_stages stages
  join public.pachanga_tournament_brackets brackets
    on brackets.knockout_stage_id = stages.id
  order by brackets.server_sequence
  limit 1
)
insert into public.pachanga_competition_stages
select (jsonb_populate_record(
  null::public.pachanga_competition_stages,
  to_jsonb(base) || jsonb_build_object(
    'id', pg_temp.r6c_scale_id('stage:' || series.value),
    'edition_id', pg_temp.r6c_scale_id('edition:' || series.value),
    'name', 'R6C Scale Knockout',
    'revision', 1,
    'server_sequence', nextval('private.pachanga_competition_sequence'),
    'created_at', clock_timestamp(),
    'updated_at', clock_timestamp()
  )
)).*
from base cross join generate_series(1, 10000) series(value);

with authority as (
  select brackets.*
  from public.pachanga_tournament_brackets brackets
  order by brackets.server_sequence
  limit 1
)
insert into public.pachanga_tournament_brackets(
  id, competition_id, edition_id, category_id, group_stage_state_id,
  knockout_stage_id, qualification_snapshot_id, bracket_template_id,
  rule_revision_id, status, bracket_size, round_count, third_place_enabled,
  revision, server_sequence, created_by, updated_by
)
select
  pg_temp.r6c_scale_id('bracket:' || series.value),
  pg_temp.r6c_scale_id('competition:' || series.value),
  pg_temp.r6c_scale_id('edition:' || series.value),
  pg_temp.r6c_scale_id('category:' || series.value),
  authority.group_stage_state_id,
  pg_temp.r6c_scale_id('stage:' || series.value),
  authority.qualification_snapshot_id,
  authority.bracket_template_id,
  authority.rule_revision_id,
  'active', 16, 4, false, 1,
  nextval('private.pachanga_competition_sequence'),
  authority.created_by, authority.updated_by
from authority cross join generate_series(1, 10000) series(value);

with authority as (
  select brackets.*
  from public.pachanga_tournament_brackets brackets
  where brackets.id not in (
    select pg_temp.r6c_scale_id('bracket:' || series.value)
    from generate_series(1, 10000) series(value)
  )
  order by brackets.server_sequence
  limit 1
), source_revision as (
  select revisions.*
  from public.pachanga_tournament_bracket_revisions revisions
  where revisions.bracket_id = (select id from authority)
  order by revisions.version
  limit 1
)
insert into public.pachanga_tournament_bracket_revisions(
  id, bracket_id, version, revision_kind, lifecycle_status,
  qualification_snapshot_id, bracket_template_id, rule_revision_id,
  qualification_checksum, template_checksum, rule_checksum,
  policy_snapshot, structure_snapshot, checksum, operation_id, reason,
  created_by, server_sequence
)
select
  pg_temp.r6c_scale_id('bracket-revision:' || series.value),
  pg_temp.r6c_scale_id('bracket:' || series.value), 1, 'ACTIVATION', 'active',
  source_revision.qualification_snapshot_id,
  source_revision.bracket_template_id,
  source_revision.rule_revision_id,
  source_revision.qualification_checksum,
  source_revision.template_checksum,
  source_revision.rule_checksum,
  source_revision.policy_snapshot,
  jsonb_build_object('scale', true, 'bracket', series.value),
  md5('r6c-scale-bracket-revision-' || series.value)
    || md5('r6c-scale-bracket-revision-tail-' || series.value),
  pg_temp.r6c_scale_id('bracket-revision-operation:' || series.value),
  'R6C isolated scale activation', source_revision.created_by,
  nextval('private.pachanga_competition_sequence')
from source_revision cross join generate_series(1, 10000) series(value);

update public.pachanga_tournament_brackets brackets set
  current_revision_id = pg_temp.r6c_scale_id('bracket-revision:' || series.value)
from generate_series(1, 10000) series(value)
where brackets.id = pg_temp.r6c_scale_id('bracket:' || series.value);

with actor as (
  select updated_by from public.pachanga_tournament_brackets
  where id = pg_temp.r6c_scale_id('bracket:1')
)
insert into public.pachanga_canonical_matches(
  id, status, revision, server_sequence, created_by
)
select
  pg_temp.r6c_scale_id('match:' || bracket_number || ':' || match_number),
  'active', 1, nextval('private.pachanga_competition_sequence'), actor.updated_by
from actor
cross join generate_series(1, 10000) brackets(bracket_number)
cross join generate_series(1, 2) matches(match_number);

with actor as (
  select updated_by from public.pachanga_tournament_brackets
  where id = pg_temp.r6c_scale_id('bracket:1')
)
insert into public.pachanga_tournament_bracket_nodes(
  id, bracket_id, bracket_revision_id, round_code, round_order, node_order,
  node_kind, canonical_match_id, status, revision, server_sequence, updated_by
)
select
  pg_temp.r6c_scale_id('node:' || bracket_number || ':' || node_number),
  pg_temp.r6c_scale_id('bracket:' || bracket_number),
  pg_temp.r6c_scale_id('bracket-revision:' || bracket_number),
  'SCALE', 1, node_number, 'MATCH',
  case when node_number <= 2 then
    pg_temp.r6c_scale_id('match:' || bracket_number || ':' || node_number)
  end,
  case when node_number <= 2 then 'match_created' else 'awaiting_sources' end,
  1, nextval('private.pachanga_competition_sequence'), actor.updated_by
from actor
cross join generate_series(1, 10000) brackets(bracket_number)
cross join generate_series(1, 10) nodes(node_number);

with actor as (
  select updated_by from public.pachanga_tournament_brackets
  where id = pg_temp.r6c_scale_id('bracket:1')
)
insert into public.pachanga_tournament_bracket_node_slots(
  id, bracket_id, bracket_revision_id, bracket_node_id, side, slot_revision,
  source_kind, source_key, resolution_status, source_snapshot, operation_id,
  server_sequence, created_by
)
select
  pg_temp.r6c_scale_id('slot:' || bracket_number || ':' || node_number),
  pg_temp.r6c_scale_id('bracket:' || bracket_number),
  pg_temp.r6c_scale_id('bracket-revision:' || bracket_number),
  pg_temp.r6c_scale_id('node:' || bracket_number || ':' || node_number),
  'HOME', 1, 'BYE', 'SCALE-BYE-' || node_number, 'BYE',
  jsonb_build_object('sourceKind', 'BYE', 'scale', true),
  pg_temp.r6c_scale_id('slot-operation:' || bracket_number || ':' || node_number),
  nextval('private.pachanga_competition_sequence'), actor.updated_by
from actor
cross join generate_series(1, 10000) brackets(bracket_number)
cross join generate_series(1, 10) nodes(node_number);

with entries as (
  select array_agg(entries.id order by entries.server_sequence, entries.id) ids
  from (
    select competition_entries.*
    from public.pachanga_competition_entries competition_entries
    order by competition_entries.server_sequence, competition_entries.id
    limit 2
  ) entries
), actor as (
  select updated_by from public.pachanga_tournament_brackets
  where id = pg_temp.r6c_scale_id('bracket:1')
)
insert into public.pachanga_tournament_bracket_advance_decisions(
  id, bracket_id, bracket_revision_id, source_node_id, advance_reason,
  winner_entry_id, destination_slots, revision, operation_id, decided_by,
  server_sequence
)
select
  pg_temp.r6c_scale_id('advance:' || bracket_number || ':' || node_number),
  pg_temp.r6c_scale_id('bracket:' || bracket_number),
  pg_temp.r6c_scale_id('bracket-revision:' || bracket_number),
  pg_temp.r6c_scale_id('node:' || bracket_number || ':' || node_number),
  'BYE', entries.ids[1], '[]'::jsonb, 1,
  pg_temp.r6c_scale_id('advance-operation:' || bracket_number || ':' || node_number),
  actor.updated_by, nextval('private.pachanga_competition_sequence')
from entries cross join actor
cross join generate_series(1, 10000) brackets(bracket_number)
cross join generate_series(1, 5) nodes(node_number);

with entries as (
  select array_agg(entries.id order by entries.server_sequence, entries.id) ids
  from (
    select competition_entries.*
    from public.pachanga_competition_entries competition_entries
    order by competition_entries.server_sequence, competition_entries.id
    limit 2
  ) entries
), actor as (
  select updated_by from public.pachanga_tournament_brackets
  where id = pg_temp.r6c_scale_id('bracket:1')
)
insert into public.pachanga_tournament_completion_snapshots(
  id, competition_id, edition_id, bracket_id, bracket_revision_id,
  champion_entry_id, runner_up_entry_id, final_match_id,
  completion_checksum, snapshot, revision, operation_id, completed_by,
  server_sequence
)
select
  pg_temp.r6c_scale_id('completion:' || series.value),
  pg_temp.r6c_scale_id('competition:' || series.value),
  pg_temp.r6c_scale_id('edition:' || series.value),
  pg_temp.r6c_scale_id('bracket:' || series.value),
  pg_temp.r6c_scale_id('bracket-revision:' || series.value),
  entries.ids[1], entries.ids[2],
  pg_temp.r6c_scale_id('match:' || series.value || ':1'),
  md5('r6c-scale-completion-' || series.value)
    || md5('r6c-scale-completion-tail-' || series.value),
  jsonb_build_object('scale', true, 'bracket', series.value), 1,
  pg_temp.r6c_scale_id('completion-operation:' || series.value),
  actor.updated_by, nextval('private.pachanga_competition_sequence')
from entries cross join actor cross join generate_series(1, 10000) series(value);

select 'R6C_SCALE_REPORT|' || jsonb_build_object(
  'brackets', (select count(*) from public.pachanga_tournament_brackets
    where id in (select pg_temp.r6c_scale_id('bracket:' || value)
      from generate_series(1, 10000) series(value))),
  'nodes', (select count(*) from public.pachanga_tournament_bracket_nodes
    where bracket_id in (select pg_temp.r6c_scale_id('bracket:' || value)
      from generate_series(1, 10000) series(value))),
  'slots', (select count(*) from public.pachanga_tournament_bracket_node_slots
    where bracket_id in (select pg_temp.r6c_scale_id('bracket:' || value)
      from generate_series(1, 10000) series(value))),
  'advanceDecisions', (select count(*)
    from public.pachanga_tournament_bracket_advance_decisions
    where bracket_id in (select pg_temp.r6c_scale_id('bracket:' || value)
      from generate_series(1, 10000) series(value))),
  'canonicalMatches', (select count(*) from public.pachanga_canonical_matches
    where id in (select pg_temp.r6c_scale_id('match:' || bracket_number || ':' || match_number)
      from generate_series(1, 10000) brackets(bracket_number)
      cross join generate_series(1, 2) matches(match_number))),
  'completionSnapshots', (select count(*)
    from public.pachanga_tournament_completion_snapshots
    where bracket_id in (select pg_temp.r6c_scale_id('bracket:' || value)
      from generate_series(1, 10000) series(value))),
  'statementTimeoutMs', 240000
)::text;
