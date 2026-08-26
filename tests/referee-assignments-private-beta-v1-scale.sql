\set ON_ERROR_STOP on
\pset pager off
\if :{?assignment_count}
\else
  \set assignment_count 10000
\endif
\if :{?disciplinary_event_count}
\else
  \set disciplinary_event_count 50000
\endif

set statement_timeout = '600s';
set lock_timeout = '5s';
set synchronous_commit = off;
set work_mem = '256MB';

create or replace function pg_temp.w4_scale_uuid(namespace text, value bigint)
returns uuid
language sql
immutable
strict
as $$
  select (
    substring(hash from 1 for 8) || '-' || substring(hash from 9 for 4) || '-' ||
    '4' || substring(hash from 14 for 3) || '-' ||
    '8' || substring(hash from 18 for 3) || '-' ||
    substring(hash from 21 for 12)
  )::uuid
  from (select md5(namespace || ':' || value::text) as hash) source;
$$;

create or replace function pg_temp.w4_scale_assert(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table w4_scale_metrics(
  metric text primary key,
  elapsed_ms numeric not null
);

create temporary table w4_scale_started(
  metric text primary key,
  started_at timestamptz not null
);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  pg_temp.w4_scale_uuid('w4-scale-referee-user', referee_number),
  'w4-scale-referee-' || referee_number || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'W4 Scale Referee ' || referee_number)
from generate_series(1, 10000) referee_number;

insert into public.pachanga_referee_profiles(
  id, user_id, slug, public_display_name_snapshot, bio,
  operational_status, verification_status, visibility, marketplace_status,
  availability_status, available_for_assignments, share_recurring_availability,
  revision, server_sequence
)
select
  pg_temp.w4_scale_uuid('w4-scale-referee-profile', referee_number),
  pg_temp.w4_scale_uuid('w4-scale-referee-user', referee_number),
  'w4-scale-referee-' || referee_number,
  'W4 Scale Referee ' || referee_number,
  'Perfil sintetico transaccional de Referee Assignments Wave 4.',
  'active', 'unverified', 'private', 'not_listed',
  'AVAILABLE', true, false, 1, 2100000000 + referee_number
from generate_series(1, 10000) referee_number;

insert into public.pachanga_team_challenges(
  id, sender_group_id, receiver_group_id, status, revision, proposal_number,
  scheduled_at, modality, field_name, field_address,
  last_proposed_by_group_id, created_by, updated_by, accepted_at
)
select
  pg_temp.w4_scale_uuid('w4-scale-challenge', match_number),
  'c4100000-0000-4000-8000-000000000002',
  'c4100000-0000-4000-8000-000000000003',
  'accepted', 1, 1,
  timestamptz '2035-01-01 08:00:00+00' + match_number * interval '3 hours',
  'futbol7', 'Pista W4 Scale', 'Barcelona',
  'c4100000-0000-4000-8000-000000000002',
  'c4010000-0000-4000-8000-000000000003',
  'c4010000-0000-4000-8000-000000000003', clock_timestamp()
from generate_series(1, :assignment_count) match_number;

insert into public.pachanga_external_matches(
  id, challenge_id, home_group_id, away_group_id, scheduled_at, modality,
  field_snapshot, state, revision, official_at
)
select
  pg_temp.w4_scale_uuid('w4-scale-external-match', match_number),
  pg_temp.w4_scale_uuid('w4-scale-challenge', match_number),
  'c4100000-0000-4000-8000-000000000002',
  'c4100000-0000-4000-8000-000000000003',
  timestamptz '2035-01-01 08:00:00+00' + match_number * interval '3 hours',
  'futbol7', '{"name":"Pista W4 Scale","municipality":"Barcelona"}'::jsonb,
  'confirmed', 1, clock_timestamp()
from generate_series(1, :assignment_count) match_number;

insert into public.pachanga_canonical_matches(id, status, revision, created_by)
select
  pg_temp.w4_scale_uuid('w4-scale-canonical-match', match_number),
  'active', 1, 'c4010000-0000-4000-8000-000000000003'
from generate_series(1, :assignment_count) match_number;

insert into public.pachanga_canonical_match_bindings(
  id, canonical_match_id, source_kind, source_id, relation_kind,
  binding_status, revision, created_by
)
select
  pg_temp.w4_scale_uuid('w4-scale-canonical-binding', match_number),
  pg_temp.w4_scale_uuid('w4-scale-canonical-match', match_number),
  'external_match',
  pg_temp.w4_scale_uuid('w4-scale-external-match', match_number)::text,
  'authoritative_source', 'active', 1,
  'c4010000-0000-4000-8000-000000000003'
from generate_series(1, :assignment_count) match_number;

update private.pachanga_referee_foundation_settings set
  referee_foundation_enabled = true,
  referee_self_service_enabled = true,
  referee_public_profiles_enabled = true,
  referee_marketplace_enabled = true,
  referee_club_relationships_enabled = true,
  referee_assignments_enabled = true,
  referee_assignment_private_beta_enabled = true
where singleton;

create or replace procedure pg_temp.w4_scale_insert_assignment_batch(
  first_assignment integer,
  last_assignment integer
)
language plpgsql
as $$
begin
  perform set_config('pachangas.referee_reason', 'assignment.confirm', true);
  insert into public.pachanga_referee_assignments(
    id, referee_profile_id, canonical_match_id, assignment_role,
    requester_kind, requester_team_id, source_kind, source_id, status,
    scheduled_start, scheduled_end, timezone, schedule_source_revision,
    proposed_by, authority_used, proposal_message, response_deadline,
    accepted_at, confirmed_at, revision, server_sequence
  )
  select
    pg_temp.w4_scale_uuid('w4-scale-assignment', assignment_number),
    pg_temp.w4_scale_uuid('w4-scale-referee-profile', assignment_number),
    pg_temp.w4_scale_uuid('w4-scale-canonical-match', assignment_number),
    'MAIN_REFEREE', 'TEAM', 'c4100000-0000-4000-8000-000000000002',
    'external_match',
    pg_temp.w4_scale_uuid('w4-scale-external-match', assignment_number)::text,
    'confirmed',
    timestamptz '2035-01-01 08:00:00+00' + assignment_number * interval '3 hours',
    timestamptz '2035-01-01 10:00:00+00' + assignment_number * interval '3 hours',
    'Europe/Madrid', 1,
    'c4010000-0000-4000-8000-000000000003',
    'team_owner', 'W4 scale confirmed assignment',
    timestamptz '2034-12-31 00:00:00+00',
    clock_timestamp(), clock_timestamp(), 1, 2200000000 + assignment_number
  from generate_series(first_assignment, last_assignment) assignment_number;
end;
$$;

insert into w4_scale_started values ('assignment_insert', clock_timestamp());
select format(
  'begin; call pg_temp.w4_scale_insert_assignment_batch(%s, %s); commit;',
  first_assignment,
  least(first_assignment + 99, :assignment_count)
)
from generate_series(1, :assignment_count, 100) first_assignment
\gexec
insert into w4_scale_metrics(metric, elapsed_ms)
select metric, extract(epoch from clock_timestamp() - started_at) * 1000
from w4_scale_started where metric = 'assignment_insert';

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('c4010000-0000-4000-8000-000000000001', 'platform_owner', true)
on conflict (user_id) do update set role = excluded.role, active = true;

select set_config(
  'request.jwt.claims',
  '{"sub":"c4010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

create or replace procedure pg_temp.w4_scale_reconcile_batch(
  first_assignment integer,
  last_assignment integer
)
language plpgsql
as $$
declare assignment record;
begin
  for assignment in
    select id, revision, server_sequence - 2200000000 as operation_number
    from public.pachanga_referee_assignments
    where server_sequence between 2200000000 + first_assignment
                              and 2200000000 + last_assignment
    order by server_sequence
  loop
    perform public.reconcile_pachanga_referee_assignment_v1(
      pg_temp.w4_scale_uuid('w4-scale-reconcile', assignment.operation_number),
      assignment.id,
      assignment.revision,
      '{"clientVersion":"6.0.0+wave4-scale","serviceWorkerVersion":"6.0.0+wave4-scale","installedMode":"simulation","surface":"wave4_scale"}'::jsonb
    );
  end loop;
end;
$$;

insert into w4_scale_started values ('assignment_reconcile', clock_timestamp());
select format(
  'begin; call pg_temp.w4_scale_reconcile_batch(%s, %s); commit;',
  first_assignment,
  least(first_assignment + 99, :assignment_count)
)
from generate_series(1, :assignment_count, 100) first_assignment
\gexec
insert into w4_scale_metrics(metric, elapsed_ms)
select metric, extract(epoch from clock_timestamp() - started_at) * 1000
from w4_scale_started where metric = 'assignment_reconcile';

select pg_temp.w4_scale_assert((
  select count(*) from public.pachanga_referee_assignments
  where id in (
    select pg_temp.w4_scale_uuid('w4-scale-assignment', value)
    from generate_series(1, :assignment_count) value
  ) and status = 'completed'
) = :assignment_count, 'Expected configured reconciled assignments');

insert into public.pachanga_competition_disciplinary_cycles(
  id, competition_id, edition_id, stage_id, competition_group_id,
  rule_revision_id, scope_type, status, carry_policy, effective_from,
  revision, created_by
) values (
  'd603ffff-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000004',
  'c4200000-0000-4000-8000-000000000006',
  'c4200000-0000-4000-8000-000000000008',
  'c4200000-0000-4000-8000-000000000003',
  'GROUP', 'active', 'RESET', '2027-01-01T00:00:00Z', 1,
  'c4010000-0000-4000-8000-000000000002'
);

-- One valid, product-shaped Assignment anchors 50,000 R5 rows. The scale
-- corpus is inserted with business triggers paused only inside this temporary
-- transaction; the focal SQL suite separately exercises every R5 command.
begin;
select set_config('pachangas.referee_reason', 'assignment.confirm', true);
insert into public.pachanga_referee_assignments(
  id, referee_profile_id, canonical_match_id, assignment_role,
  requester_kind, requester_competition_id, competition_id,
  source_kind, source_id, status,
  scheduled_start, scheduled_end, timezone, schedule_source_revision,
  proposed_by, authority_used, proposal_message, response_deadline,
  accepted_at, confirmed_at, revision
)
values (
  'd604ffff-0000-4000-8000-000000000001',
  'd6020000-0000-4000-8000-000000000001',
  'c4500000-0000-4000-8000-000000000006',
  'MAIN_REFEREE', 'COMPETITION',
  'c4200000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000001',
  'competition_generated', 'c4500000-0000-4000-8000-000000000005',
  'confirmed', '2027-03-08T19:00:00Z', '2027-03-08T20:10:00Z',
  'Europe/Madrid', 2,
  'c4010000-0000-4000-8000-000000000002',
  'competition_referee_manager', 'W4 R5 scale anchor',
  '2027-03-07T19:00:00Z', clock_timestamp(), clock_timestamp(), 1
);
commit;

insert into w4_scale_started values ('r5_events', clock_timestamp());
begin;
set local session_replication_role = replica;
insert into public.pachanga_competition_disciplinary_events(
    id, competition_id, canonical_match_id, competition_match_context_id,
    cycle_id, rule_revision_id, player_profile_id, entry_id, status,
    current_card_type_code, creation_operation_id, revision, server_sequence,
    created_by, referee_assignment_id, reporting_referee_profile_id
)
select
    pg_temp.w4_scale_uuid('w4-scale-r5-event', event_number),
    'c4200000-0000-4000-8000-000000000001',
    'c4500000-0000-4000-8000-000000000006',
    'c4500000-0000-4000-8000-000000000008',
    'd603ffff-0000-4000-8000-000000000001',
    'c4200000-0000-4000-8000-000000000003',
    'c4300000-0000-4000-8000-000000000001',
    'c4200000-0000-4000-8000-000000000011',
    'active',
    case event_number % 20 when 0 then 'RED' when 1 then 'BLUE' else 'YELLOW' end,
    pg_temp.w4_scale_uuid('w4-scale-r5-operation', event_number),
    1, 2300000000 + event_number,
    'd6010000-0000-4000-8000-000000000001',
    'd604ffff-0000-4000-8000-000000000001',
    'd6020000-0000-4000-8000-000000000001'
from generate_series(1, :disciplinary_event_count) event_number;

insert into public.pachanga_competition_disciplinary_event_revisions(
    id, disciplinary_event_id, version, player_profile_id, entry_id,
    card_type_code, event_context, match_minute, period_code, event_status,
    public_reason_category, public_summary, rule_outcome, correction_reason,
    operation_id, created_by, server_sequence
)
select
    pg_temp.w4_scale_uuid('w4-scale-r5-revision', event_number),
    pg_temp.w4_scale_uuid('w4-scale-r5-event', event_number),
    1, 'c4300000-0000-4000-8000-000000000001',
    'c4200000-0000-4000-8000-000000000011',
    case event_number % 20 when 0 then 'RED' when 1 then 'BLUE' else 'YELLOW' end,
    'in_match', event_number % 91, 'REGULATION', 'active',
    'scale', 'Evento R5 sintetico asociado a Assignment',
    jsonb_build_object('visualType', case event_number % 20 when 0 then 'red' when 1 then 'blue' else 'yellow' end),
    'Carga de volumen autoritativa Wave 4',
    pg_temp.w4_scale_uuid('w4-scale-r5-revision-operation', event_number),
    'd6010000-0000-4000-8000-000000000001', 2400000000 + event_number
from generate_series(1, :disciplinary_event_count) event_number;

update public.pachanga_competition_disciplinary_events events set
  current_revision_id = revisions.id
from public.pachanga_competition_disciplinary_event_revisions revisions
where revisions.disciplinary_event_id = events.id
  and events.referee_assignment_id = 'd604ffff-0000-4000-8000-000000000001';
commit;
insert into w4_scale_metrics(metric, elapsed_ms)
select metric, extract(epoch from clock_timestamp() - started_at) * 1000
from w4_scale_started where metric = 'r5_events';

do $$
declare started_at timestamptz := clock_timestamp();
begin
  perform private.pachanga_referee_refresh_statistics_v1(
    'd6020000-0000-4000-8000-000000000001', 'full_rebuild'
  );
  insert into w4_scale_metrics(metric, elapsed_ms)
  values ('r5_statistics_full_rebuild', extract(epoch from clock_timestamp() - started_at) * 1000);
end;
$$;

analyze public.pachanga_referee_assignments;
analyze public.pachanga_competition_disciplinary_events;

select pg_temp.w4_scale_assert((
  select count(*) from public.pachanga_competition_disciplinary_events
  where referee_assignment_id = 'd604ffff-0000-4000-8000-000000000001'
) = :disciplinary_event_count, 'Expected configured R5 events linked to one valid Assignment');
select pg_temp.w4_scale_assert((
  select coalesce(yellow_cards_shown, 0) + coalesce(red_cards_shown, 0) + coalesce(blue_cards_shown, 0)
  from public.pachanga_referee_statistics_snapshots
  where referee_profile_id = 'd6020000-0000-4000-8000-000000000001'
) = :disciplinary_event_count, 'R5 full rebuild must account for all configured linked events');

select 'WAVE4_SCALE_REPORT|' || jsonb_build_object(
  'profiles', 10000,
  'assignmentReconciliations', :assignment_count,
  'r5LinkedEvents', :disciplinary_event_count,
  'assignmentInsertDurationMs', round((select elapsed_ms from w4_scale_metrics where metric = 'assignment_insert'), 3),
  'reconcileDurationMs', round((select elapsed_ms from w4_scale_metrics where metric = 'assignment_reconcile'), 3),
  'r5InsertDurationMs', round((select elapsed_ms from w4_scale_metrics where metric = 'r5_events'), 3),
  'r5RebuildDurationMs', round((select elapsed_ms from w4_scale_metrics where metric = 'r5_statistics_full_rebuild'), 3),
  'assignmentIndexBytes', (
    select coalesce(sum(pg_relation_size(indexrelid)), 0)
    from pg_index where indrelid = 'public.pachanga_referee_assignments'::regclass
  ),
  'disciplineIndexBytes', (
    select coalesce(sum(pg_relation_size(indexrelid)), 0)
    from pg_index where indrelid = 'public.pachanga_competition_disciplinary_events'::regclass
  ),
  'locksHeldAtReport', (
    select count(*) from pg_locks where pid = pg_backend_pid() and granted
  ),
  'rollbackStrategy', 'TEMPORARY_DATABASE_DROP'
)::text;
