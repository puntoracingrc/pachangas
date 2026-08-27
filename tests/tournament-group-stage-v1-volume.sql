\set ON_ERROR_STOP on

set local lock_timeout = '5s';
set local statement_timeout = '240s';

create temporary table r6b_volume_scope as
select states.id as state_id, states.competition_id, states.edition_id,
  states.category_id, states.stage_id, states.rule_revision_id,
  states.current_preparation_id as preparation_id,
  mappings.competition_group_id, mappings.schedule_plan_id,
  plans.current_revision_id as schedule_revision_id,
  rounds.id as round_id, entries.id as home_entry_id,
  away_entries.id as away_entry_id, states.updated_by as actor_id
from public.pachanga_tournament_group_stage_states states
join public.pachanga_tournament_group_schedule_plans mappings
  on mappings.group_stage_state_id = states.id
join public.pachanga_competition_schedule_plans plans
  on plans.id = mappings.schedule_plan_id
join public.pachanga_competition_rounds rounds
  on rounds.schedule_revision_id = plans.current_revision_id
join public.pachanga_competition_entries entries
  on entries.competition_id = states.competition_id
join public.pachanga_competition_entries away_entries
  on away_entries.competition_id = states.competition_id
 and away_entries.id > entries.id
where states.status = 'schedule_validated'
  and mappings.status = 'validated'
  and plans.status = 'validated'
order by mappings.group_order, rounds.round_number, entries.id, away_entries.id
limit 1;

insert into public.pachanga_competition_schedule_slots(
  id, competition_id, edition_id, stage_id, competition_group_id,
  starts_at, ends_at, timezone, venue_label, status, created_by
)
select md5('r6b-volume-slot-' || value)::uuid, scope.competition_id,
  scope.edition_id, scope.stage_id, scope.competition_group_id,
  '2027-01-01T08:00:00Z'::timestamptz + value * interval '2 hours',
  '2027-01-01T09:30:00Z'::timestamptz + value * interval '2 hours',
  'Europe/Madrid', 'R6B volume fixture', 'assigned', scope.actor_id
from r6b_volume_scope scope
cross join generate_series(1, 10000) value;

insert into public.pachanga_competition_schedule_items(
  id, schedule_revision_id, round_id, home_entry_id, away_entry_id,
  pairing_key, leg_number, slot_id, scheduled_start, scheduled_end,
  timezone, venue_label, venue_status, status
)
select md5('r6b-volume-item-' || value)::uuid, scope.schedule_revision_id,
  scope.round_id, scope.home_entry_id, scope.away_entry_id,
  encode(extensions.digest(convert_to('r6b-volume-pair-' || value, 'UTF8'), 'sha256'), 'hex') || ':1',
  1, md5('r6b-volume-slot-' || value)::uuid,
  '2027-01-01T08:00:00Z'::timestamptz + value * interval '2 hours',
  '2027-01-01T09:30:00Z'::timestamptz + value * interval '2 hours',
  'Europe/Madrid', 'R6B volume fixture', 'CONFIRMED', 'validated'
from r6b_volume_scope scope
cross join generate_series(1, 10000) value;

insert into public.pachanga_canonical_matches(id, status, created_by)
select md5('r6b-volume-canonical-' || value)::uuid, 'active', scope.actor_id
from r6b_volume_scope scope
cross join generate_series(1, 10000) value;

select set_config('pachangas.r6b_match_publish', 'on', true);
insert into public.pachanga_competition_match_contexts(
  id, canonical_match_id, competition_id, edition_id, category_id, stage_id,
  competition_group_id, rule_revision_id, round_id, schedule_item_id,
  home_entry_id, away_entry_id, slot_id, scheduled_start, scheduled_end,
  timezone, venue_label, venue_status, source_kind, status, created_by
)
select md5('r6b-volume-context-' || value)::uuid,
  md5('r6b-volume-canonical-' || value)::uuid,
  scope.competition_id, scope.edition_id, scope.category_id, scope.stage_id,
  scope.competition_group_id, scope.rule_revision_id, scope.round_id,
  md5('r6b-volume-item-' || value)::uuid, scope.home_entry_id,
  scope.away_entry_id, md5('r6b-volume-slot-' || value)::uuid,
  '2027-01-01T08:00:00Z'::timestamptz + value * interval '2 hours',
  '2027-01-01T09:30:00Z'::timestamptz + value * interval '2 hours',
  'Europe/Madrid', 'R6B volume fixture', 'CONFIRMED',
  'COMPETITION_GENERATED', 'official', scope.actor_id
from r6b_volume_scope scope
cross join generate_series(1, 10000) value;

insert into public.pachanga_canonical_match_bindings(
  id, canonical_match_id, source_kind, source_id, relation_kind,
  binding_status, created_by
)
select md5('r6b-volume-binding-' || value)::uuid,
  md5('r6b-volume-canonical-' || value)::uuid,
  'competition_generated', md5('r6b-volume-item-' || value)::uuid::text,
  'authoritative_source', 'active', scope.actor_id
from r6b_volume_scope scope
cross join generate_series(1, 10000) value;

update public.pachanga_competition_schedule_items items set
  canonical_match_id = md5('r6b-volume-canonical-' || source.value)::uuid,
  competition_match_context_id = md5('r6b-volume-context-' || source.value)::uuid,
  status = 'published', revision = items.revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_at = clock_timestamp()
from generate_series(1, 10000) source(value)
where items.id = md5('r6b-volume-item-' || source.value)::uuid;

insert into public.pachanga_competition_official_result_decisions(
  id, canonical_match_id, competition_match_context_id, outcome,
  effective_score_home, effective_score_away, public_explanation,
  reason_code, points_adjustments, operation_id, authority_role, decided_by
)
select md5('r6b-volume-result-' || value)::uuid,
  md5('r6b-volume-canonical-' || value)::uuid,
  md5('r6b-volume-context-' || value)::uuid,
  'CORRECTED_EFFECTIVE_SCORE', value % 5, (value + 2) % 5,
  'R6B transactional volume result', 'r6b.scale.volume', '[]'::jsonb,
  md5('r6b-volume-result-operation-' || value)::uuid,
  'competition_director', scope.actor_id
from r6b_volume_scope scope
cross join generate_series(1, 10000) value;

insert into public.pachanga_competition_standing_states(
  id, competition_id, edition_id, stage_id, competition_group_id,
  rule_revision_id, health_status
)
select md5('r6b-volume-standing-state')::uuid, scope.competition_id,
  scope.edition_id, scope.stage_id, scope.competition_group_id,
  scope.rule_revision_id, 'CURRENT'
from r6b_volume_scope scope;

insert into public.pachanga_competition_standing_snapshots(
  id, standing_state_id, competition_id, edition_id, stage_id,
  competition_group_id, rule_revision_id, rebuild_kind, source_revision,
  row_count, tie_break_criteria, content_checksum
)
select md5('r6b-volume-standing-' || value)::uuid,
  md5('r6b-volume-standing-state')::uuid, scope.competition_id,
  scope.edition_id, scope.stage_id, scope.competition_group_id,
  scope.rule_revision_id, 'FULL_AUDIT', value, 0, '[]'::jsonb,
  encode(extensions.digest(convert_to('r6b-volume-standing-' || value, 'UTF8'), 'sha256'), 'hex')
from r6b_volume_scope scope
cross join generate_series(1, 1000) value;

insert into public.pachanga_tournament_qualification_snapshots(
  id, group_stage_state_id, competition_id, edition_id, stage_id,
  rule_revision_id, preparation_id, status, source_standings_revision,
  source_standing_snapshot_ids, policy_snapshot, health_snapshot,
  group_qualifiers, cross_group_qualifiers, eliminated_entries,
  target_bracket_slots, checksum, operation_id, generated_by
)
select md5('r6b-volume-qualification-' || value)::uuid, scope.state_id,
  scope.competition_id, scope.edition_id, scope.stage_id,
  scope.rule_revision_id, scope.preparation_id, 'PROVISIONAL', value,
  array[md5('r6b-volume-standing-' || value)::uuid],
  '{}'::jsonb, '{}'::jsonb, '[]'::jsonb, '[]'::jsonb, '[]'::jsonb,
  '[]'::jsonb,
  encode(extensions.digest(convert_to('r6b-volume-qualification-' || value, 'UTF8'), 'sha256'), 'hex'),
  md5('r6b-volume-qualification-operation-' || value)::uuid, scope.actor_id
from r6b_volume_scope scope
cross join generate_series(1, 1000) value;

select 'R6B_VOLUME_REPORT|' || jsonb_build_object(
  'groupMatches', (select count(*) from public.pachanga_competition_match_contexts
    where id in (select md5('r6b-volume-context-' || value)::uuid from generate_series(1, 10000) value)),
  'officialResults', (select count(*) from public.pachanga_competition_official_result_decisions
    where id in (select md5('r6b-volume-result-' || value)::uuid from generate_series(1, 10000) value)),
  'standingSnapshots', (select count(*) from public.pachanga_competition_standing_snapshots
    where id in (select md5('r6b-volume-standing-' || value)::uuid from generate_series(1, 1000) value)),
  'qualificationSnapshots', (select count(*) from public.pachanga_tournament_qualification_snapshots
    where id in (select md5('r6b-volume-qualification-' || value)::uuid from generate_series(1, 1000) value)),
  'knockoutMatches', 0,
  'statementTimeoutMs', 240000
)::text;
