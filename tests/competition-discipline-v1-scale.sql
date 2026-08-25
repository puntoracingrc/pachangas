\set ON_ERROR_STOP on

begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create temporary table r5_scale_clock(started_at timestamptz not null);
insert into r5_scale_clock values (clock_timestamp());

insert into public.pachanga_competition_disciplinary_cycles(
  id, competition_id, edition_id, rule_revision_id, scope_type, status,
  carry_policy, effective_from, created_by
) values (
  'd6100000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004',
  'c4200000-0000-4000-8000-000000000003',
  'EDITION', 'active', 'RESET', '2027-01-01T00:00:00Z',
  'c4010000-0000-4000-8000-000000000002'
);

insert into public.pachanga_competition_disciplinary_events(
  id, competition_id, canonical_match_id, competition_match_context_id,
  cycle_id, rule_revision_id, player_profile_id, entry_id,
  current_card_type_code, creation_operation_id, created_by
)
select
  md5('r5-scale-event-' || series)::uuid,
  'c4200000-0000-4000-8000-000000000001',
  (array[
    'c4400000-0000-4000-8000-000000000006',
    'c4500000-0000-4000-8000-000000000006',
    'c4600000-0000-4000-8000-000000000006',
    'c4700000-0000-4000-8000-000000000006'
  ]::uuid[])[1 + ((series - 1) % 4)],
  (array[
    'c4400000-0000-4000-8000-000000000008',
    'c4500000-0000-4000-8000-000000000008',
    'c4600000-0000-4000-8000-000000000008',
    'c4700000-0000-4000-8000-000000000008'
  ]::uuid[])[1 + ((series - 1) % 4)],
  'd6100000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000003',
  case when series % 3 = 0
    then 'c4300000-0000-4000-8000-000000000003'::uuid
    else 'c4300000-0000-4000-8000-000000000001'::uuid end,
  'c4200000-0000-4000-8000-000000000011',
  case when series % 37 = 0 then 'RED' else 'YELLOW' end,
  md5('r5-scale-event-operation-' || series)::uuid,
  'c4010000-0000-4000-8000-000000000002'
from generate_series(1, 10000) series;

insert into public.pachanga_competition_disciplinary_event_revisions(
  id, disciplinary_event_id, version, player_profile_id, entry_id,
  card_type_code, event_context, match_minute, period_code, event_status,
  public_reason_category, public_summary, rule_outcome, correction_reason,
  operation_id, created_by
)
select
  md5('r5-scale-event-revision-' || series)::uuid,
  md5('r5-scale-event-' || series)::uuid, 1,
  case when series % 3 = 0
    then 'c4300000-0000-4000-8000-000000000003'::uuid
    else 'c4300000-0000-4000-8000-000000000001'::uuid end,
  'c4200000-0000-4000-8000-000000000011',
  case when series % 37 = 0 then 'RED' else 'YELLOW' end,
  'in_match', series % 91, 'REGULATION', 'active',
  case when series % 37 = 0 then 'dismissal' else 'accumulation' end,
  'Scale event ' || series,
  jsonb_build_object(
    'cardTypeCode', case when series % 37 = 0 then 'RED' else 'YELLOW' end,
    'accumulationPoints', case when series % 37 = 0 then 0 else 1 end,
    'sanctionOutcome', case when series % 37 = 0 then 'COMMITTEE_REQUIRED' else 'NO_SANCTION' end
  ),
  'Initial scale event', md5('r5-scale-event-revision-operation-' || series)::uuid,
  'c4010000-0000-4000-8000-000000000002'
from generate_series(1, 10000) series;

update public.pachanga_competition_disciplinary_events events set
  current_revision_id = revisions.id
from public.pachanga_competition_disciplinary_event_revisions revisions
where revisions.disciplinary_event_id = events.id
  and events.cycle_id = 'd6100000-0000-4000-8000-000000000001';

insert into public.pachanga_competition_sanctions(
  id, competition_id, cycle_id, rule_revision_id, source_event_id,
  target_type, player_profile_id, sanction_outcome, status, unit_type,
  total_units, remaining_units, creation_operation_id, created_by
)
select
  md5('r5-scale-sanction-' || series)::uuid,
  'c4200000-0000-4000-8000-000000000001',
  'd6100000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000003',
  md5('r5-scale-event-' || series)::uuid,
  'PLAYER',
  case when series % 3 = 0
    then 'c4300000-0000-4000-8000-000000000003'::uuid
    else 'c4300000-0000-4000-8000-000000000001'::uuid end,
  'FIXED_SANCTION', 'active', 'MATCHES', 3, 2,
  md5('r5-scale-sanction-operation-' || series)::uuid,
  'c4010000-0000-4000-8000-000000000002'
from generate_series(1, 2000) series;

insert into public.pachanga_competition_sanction_revisions(
  id, sanction_id, version, status, sanction_outcome, unit_type,
  total_units, remaining_units, public_reason_category, public_summary,
  rule_article, decision_factors, decision_reason_private,
  operation_id, created_by
)
select
  md5('r5-scale-sanction-revision-' || series)::uuid,
  md5('r5-scale-sanction-' || series)::uuid, 1, 'active',
  'FIXED_SANCTION', 'MATCHES', 3, 2, 'accumulation',
  'Scale sanction ' || series, 'R5.SCALE',
  jsonb_build_object('source', 'scale'), '',
  md5('r5-scale-sanction-revision-operation-' || series)::uuid,
  'c4010000-0000-4000-8000-000000000002'
from generate_series(1, 2000) series;

update public.pachanga_competition_sanctions sanctions set
  current_revision_id = revisions.id
from public.pachanga_competition_sanction_revisions revisions
where revisions.sanction_id = sanctions.id
  and sanctions.cycle_id = 'd6100000-0000-4000-8000-000000000001';

insert into public.pachanga_competition_sanction_service_events(
  id, competition_id, sanction_id, canonical_match_id,
  competition_match_context_id, event_type, units,
  remaining_before, remaining_after, rule_revision_id,
  operation_id, created_by
)
select
  md5('r5-scale-service-' || series)::uuid,
  'c4200000-0000-4000-8000-000000000001',
  md5('r5-scale-sanction-' || (1 + ((series - 1) % 2000)))::uuid,
  (array[
    'c4400000-0000-4000-8000-000000000006',
    'c4500000-0000-4000-8000-000000000006',
    'c4600000-0000-4000-8000-000000000006',
    'c4700000-0000-4000-8000-000000000006'
  ]::uuid[])[1 + ((series - 1) % 4)],
  (array[
    'c4400000-0000-4000-8000-000000000008',
    'c4500000-0000-4000-8000-000000000008',
    'c4600000-0000-4000-8000-000000000008',
    'c4700000-0000-4000-8000-000000000008'
  ]::uuid[])[1 + ((series - 1) % 4)],
  'SERVED', 1, 3, 2,
  'c4200000-0000-4000-8000-000000000003',
  md5('r5-scale-service-operation-' || series)::uuid,
  'c4010000-0000-4000-8000-000000000002'
from generate_series(1, 5000) series;

insert into public.pachanga_competition_sanction_appeals(
  id, competition_id, sanction_id, appellant_user_id, status,
  deadline_at, suspensive_effect, creation_operation_id
)
select
  md5('r5-scale-appeal-' || series)::uuid,
  'c4200000-0000-4000-8000-000000000001',
  md5('r5-scale-sanction-' || series)::uuid,
  'c4010000-0000-4000-8000-000000000005',
  'submitted', clock_timestamp() + interval '72 hours', false,
  md5('r5-scale-appeal-operation-' || series)::uuid
from generate_series(1, 1000) series;

insert into public.pachanga_competition_sanction_appeal_revisions(
  id, appeal_id, version, status, statement, operation_id, created_by
)
select
  md5('r5-scale-appeal-revision-' || series)::uuid,
  md5('r5-scale-appeal-' || series)::uuid, 1, 'submitted',
  'Scale appeal statement ' || series,
  md5('r5-scale-appeal-revision-operation-' || series)::uuid,
  'c4010000-0000-4000-8000-000000000005'
from generate_series(1, 1000) series;

update public.pachanga_competition_sanction_appeals appeals set
  current_revision_id = revisions.id
from public.pachanga_competition_sanction_appeal_revisions revisions
where revisions.appeal_id = appeals.id
  and appeals.competition_id = 'c4200000-0000-4000-8000-000000000001';

analyze public.pachanga_competition_disciplinary_events;
analyze public.pachanga_competition_sanctions;
analyze public.pachanga_competition_sanction_service_events;
analyze public.pachanga_competition_sanction_appeals;

create temporary table r5_scale_query_metrics(
  metric text primary key,
  duration_ms numeric not null
);
do $$
declare started_at timestamptz;
begin
  started_at := clock_timestamp();
  perform events.id
  from public.pachanga_competition_disciplinary_events events
  where events.canonical_match_id = 'c4400000-0000-4000-8000-000000000006'
    and events.status = 'active'
  order by events.server_sequence desc, events.id desc
  limit 100;
  insert into r5_scale_query_metrics values (
    'eventLookup',
    extract(epoch from (clock_timestamp() - started_at)) * 1000
  );
end;
$$;

select 'R5_SCALE_REPORT|' || jsonb_build_object(
  'events', (select count(*) from public.pachanga_competition_disciplinary_events),
  'activeSanctions', (select count(*) from public.pachanga_competition_sanctions where status='active'),
  'serviceEvents', (select count(*) from public.pachanga_competition_sanction_service_events),
  'appeals', (select count(*) from public.pachanga_competition_sanction_appeals),
  'durationMs', round(extract(epoch from (clock_timestamp() - (select started_at from r5_scale_clock))) * 1000),
  'indexBytes', (
    select sum(pg_relation_size(indexrelid))
    from pg_index
    where indrelid in (
      'public.pachanga_competition_disciplinary_events'::regclass,
      'public.pachanga_competition_sanctions'::regclass,
      'public.pachanga_competition_sanction_service_events'::regclass,
      'public.pachanga_competition_sanction_appeals'::regclass
    )
  ),
  'eventLookupMs', (
    select round(metrics.duration_ms, 3)
    from r5_scale_query_metrics metrics where metrics.metric = 'eventLookup'
  )
)::text;

rollback;

select 'R5_SCALE_ROLLBACK|' || jsonb_build_object(
  'events', (select count(*) from public.pachanga_competition_disciplinary_events),
  'sanctions', (select count(*) from public.pachanga_competition_sanctions),
  'serviceEvents', (select count(*) from public.pachanga_competition_sanction_service_events),
  'appeals', (select count(*) from public.pachanga_competition_sanction_appeals)
)::text;
