\set ON_ERROR_STOP on

begin;
select set_config('pachanga.team_operational_authority', 'on', true);

create temporary table wave8b_scale_teams(
  ordinal integer primary key,
  id uuid not null unique
);
insert into wave8b_scale_teams(ordinal, id)
select ordinal, gen_random_uuid() from generate_series(1, 10000) ordinal;

create temporary table wave8b_scale_metrics(
  metric text primary key,
  elapsed_ms numeric not null
);
grant all on table wave8b_scale_metrics to authenticated, service_role;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
select seeded.id, '8b000000-0000-4000-8000-000000000001',
  'Wave 8B Scale Team ' || seeded.ordinal,
  'S8B' || lpad(seeded.ordinal::text, 5, '0'),
  jsonb_build_object(
    'name', 'Wave 8B Scale Team ' || seeded.ordinal,
    'matches', '[]'::jsonb,
    'players', '[]'::jsonb,
    'siteSettings', '{}'::jsonb,
    'venues', '[]'::jsonb
  ), 1
from wave8b_scale_teams seeded;

insert into private.pachanga_team_operational_state_revisions_v1(
  group_id, revision, lifecycle_status, enforcement_status, effective_status,
  restriction_preset, continuity_policy, public_message, effective_from,
  reason_code, private_note, evidence, source, operation_id, actor_id,
  actor_kind, server_sequence
)
select seeded.id, revisions.revision,
  'ACTIVE', case when revisions.revision = 5 then 'LIMITED' else 'CLEAR' end,
  case when revisions.revision = 5 then 'LIMITED' else 'ACTIVE' end,
  'CUSTOM', 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
  case when revisions.revision = 5 then 'Disponibilidad limitada en la simulación.' else '' end,
  clock_timestamp() - interval '30 days' + revisions.revision * interval '1 day',
  'synthetic.scale.revision', '', jsonb_build_object('synthetic', true),
  'SYNTHETIC_SCALE', gen_random_uuid(), '8b000000-0000-4000-8000-000000000020',
  'PLATFORM', nextval('private.pachanga_team_operational_sequence_v1')
from wave8b_scale_teams seeded
cross join generate_series(2, 5) revisions(revision);

insert into private.pachanga_team_operational_restrictions_v1(
  group_id, scope, status, source_revision, preset_source, reason_code,
  public_message, effective_from, effective_until, operation_id, applied_by,
  closed_by, server_sequence, closed_at
)
select seeded.id,
  (array['MARKETPLACE','COMPETITION_ORGANIZER','COMPETITION_REGISTRATION','SOCIAL_CHALLENGES','NEW_MATCH_CREATION'])[scopes.scope_index],
  case when scopes.scope_index = ((seeded.ordinal - 1) % 5) + 1 then 'ACTIVE' else 'LIFTED' end,
  5, 'CUSTOM', 'synthetic.scale.restriction', 'Restricción sintética de escala.',
  clock_timestamp() - interval '2 days',
  case
    when scopes.scope_index = ((seeded.ordinal - 1) % 5) + 1 and seeded.ordinal <= 100
      then clock_timestamp() - interval '1 minute'
    else null
  end,
  gen_random_uuid(), '8b000000-0000-4000-8000-000000000020',
  case when scopes.scope_index <> ((seeded.ordinal - 1) % 5) + 1
    then '8b000000-0000-4000-8000-000000000020'::uuid else null end,
  nextval('private.pachanga_team_operational_sequence_v1'),
  case when scopes.scope_index <> ((seeded.ordinal - 1) % 5) + 1
    then clock_timestamp() - interval '1 day' else null end
from wave8b_scale_teams seeded
cross join generate_series(1, 5) scopes(scope_index);

update private.pachanga_team_operational_states_v1 states set
  enforcement_status = 'LIMITED',
  effective_status = 'LIMITED',
  restriction_preset = 'CUSTOM',
  continuity_policy = 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
  public_message = 'Disponibilidad limitada en la simulación.',
  current_revision = 5,
  server_sequence = nextval('private.pachanga_team_operational_sequence_v1'),
  source = 'SYNTHETIC_SCALE',
  last_operation_id = gen_random_uuid(),
  updated_by = '8b000000-0000-4000-8000-000000000020',
  updated_at = clock_timestamp()
where exists (select 1 from wave8b_scale_teams seeded where seeded.id = states.group_id);

insert into private.pachanga_team_operational_continuity_decisions_v1(
  group_id, competition_id, policy, source_revision, reason_code,
  public_message, private_note, operation_id, decided_by, server_sequence
)
select seeded.id, null,
  case when decisions.decision_index = 1
    then 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH'
    else 'FREEZE_FUTURE_SPORTING_WRITES' end,
  5, 'synthetic.scale.continuity', 'Continuidad sintética.', '', gen_random_uuid(),
  '8b000000-0000-4000-8000-000000000020',
  nextval('private.pachanga_team_operational_sequence_v1')
from wave8b_scale_teams seeded
cross join generate_series(1, 2) decisions(decision_index);

insert into private.pachanga_team_operational_reviews_v1(
  group_id, status, reason_code, safe_message, private_note, evidence,
  opened_at, closed_at, opened_by, assigned_reviewer, closed_by,
  close_outcome, operation_id, source_revision, revision, server_sequence
)
select seeded.id, 'CLOSED_NO_ACTION', 'synthetic.scale.review',
  'Revisión sintética cerrada.', 'Nota privada sintética.', '{"synthetic":true}',
  clock_timestamp() - reviews.review_index * interval '2 days',
  clock_timestamp() - reviews.review_index * interval '1 day',
  '8b000000-0000-4000-8000-000000000020',
  '8b000000-0000-4000-8000-000000000021',
  '8b000000-0000-4000-8000-000000000021',
  'NO_ACTION', gen_random_uuid(), 5, 2,
  nextval('private.pachanga_team_operational_sequence_v1')
from wave8b_scale_teams seeded
cross join generate_series(1, 2) reviews(review_index);

insert into private.pachanga_team_operational_appeals_v1(
  group_id, status, subject_revision, owner_message, safe_resolution_message,
  private_resolution_note, requested_outcome, submitted_at, resolved_at,
  created_by, assigned_reviewer, resolved_by, resolution, operation_id,
  revision, server_sequence
)
select seeded.id, 'UPHELD', 5, 'Apelación sintética.', 'Decisión confirmada.',
  'Resolución privada sintética.', 'REVIEW',
  clock_timestamp() - interval '2 days', clock_timestamp() - interval '1 day',
  '8b000000-0000-4000-8000-000000000001',
  '8b000000-0000-4000-8000-000000000021',
  '8b000000-0000-4000-8000-000000000021',
  'UPHELD', gen_random_uuid(), 3,
  nextval('private.pachanga_team_operational_sequence_v1')
from wave8b_scale_teams seeded;

insert into public.pachanga_team_operational_invalidations_v1(
  server_sequence, group_id, owner_id, entity_type, entity_id, revision, event_kind
)
select nextval('private.pachanga_team_operational_sequence_v1'), seeded.id,
  '8b000000-0000-4000-8000-000000000001', 'TEAM_OPERATIONAL_STATE',
  seeded.id::text, 5, 'team.synthetic.scale'
from wave8b_scale_teams seeded
cross join generate_series(1, 9) invalidations(invalidation_index);

do $metrics$
declare started_at timestamptz;
declare selected_team uuid;
begin
  select id into selected_team from wave8b_scale_teams where ordinal = 501;

  started_at := clock_timestamp();
  perform private.pachanga_team_operational_safe_projection_v1(selected_team, true);
  insert into wave8b_scale_metrics values ('team_status_read', extract(epoch from clock_timestamp() - started_at) * 1000);

  started_at := clock_timestamp();
  perform public.get_public_pachanga_team_operational_state_v1(selected_team);
  insert into wave8b_scale_metrics values ('public_team_read', extract(epoch from clock_timestamp() - started_at) * 1000);

  started_at := clock_timestamp();
  perform private.pachanga_team_operational_scope_allowed_v1(selected_team, 'MARKETPLACE');
  insert into wave8b_scale_metrics values ('scope_resolution', extract(epoch from clock_timestamp() - started_at) * 1000);
end;
$metrics$;

set local role authenticated;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"8b000000-0000-4000-8000-000000000020"}', true);
do $control_center$
declare started_at timestamptz := clock_timestamp();
begin
  perform public.list_pachanga_platform_team_operational_states_v1('{"status":"LIMITED"}', 50, 0);
  insert into wave8b_scale_metrics values ('control_center_list', extract(epoch from clock_timestamp() - started_at) * 1000);
end;
$control_center$;
reset role;

do $guards$
declare started_at timestamptz;
declare selected_team uuid;
begin
  select id into selected_team from wave8b_scale_teams where ordinal = 501;
  started_at := clock_timestamp();
  begin
    insert into public.pachanga_open_matches(source_group_id, source_match_id, date, active, created_by)
    values (selected_team, 'wave8b-scale-market', clock_timestamp() + interval '1 day', true,
      '8b000000-0000-4000-8000-000000000001');
    raise exception 'MARKET_GUARD_DID_NOT_BLOCK';
  exception when insufficient_privilege then
    if sqlerrm <> 'TEAM_OPERATIONALLY_RESTRICTED' then raise; end if;
  end;
  insert into wave8b_scale_metrics values ('marketplace_guard', extract(epoch from clock_timestamp() - started_at) * 1000);

  select id into selected_team from wave8b_scale_teams where ordinal = 502;
  started_at := clock_timestamp();
  begin
    insert into private.pachanga_organizer_access_applications_v1(
      organizer_kind, organizer_group_id, requested_plan_code, requested_access_mode, created_by
    ) values ('TEAM', selected_team, 'TEAM_ORGANIZER_PRO', 'PAID_PLAN_INTEREST',
      '8b000000-0000-4000-8000-000000000001');
    raise exception 'ORGANIZER_GUARD_DID_NOT_BLOCK';
  exception when insufficient_privilege then
    if sqlerrm <> 'TEAM_OPERATIONALLY_RESTRICTED' then raise; end if;
  end;
  insert into wave8b_scale_metrics values ('organizer_application_guard', extract(epoch from clock_timestamp() - started_at) * 1000);

  select id into selected_team from wave8b_scale_teams where ordinal = 503;
  started_at := clock_timestamp();
  begin
    insert into public.pachanga_competition_registration_requests(team_id)
    values (selected_team);
    raise exception 'REGISTRATION_GUARD_DID_NOT_BLOCK';
  exception when insufficient_privilege then
    if sqlerrm <> 'TEAM_OPERATIONALLY_RESTRICTED' then raise; end if;
  end;
  insert into wave8b_scale_metrics values ('registration_guard', extract(epoch from clock_timestamp() - started_at) * 1000);
end;
$guards$;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $expiry$
declare started_at timestamptz := clock_timestamp();
declare result jsonb;
begin
  result := public.expire_pachanga_team_operational_states_v1(100, gen_random_uuid());
  if (result ->> 'processed')::integer <> 100 or (result ->> 'failures')::integer <> 0 then
    raise exception 'EXPIRY_WORKER_SCALE_FAILED: %', result;
  end if;
  insert into wave8b_scale_metrics values ('expiry_worker_100', extract(epoch from clock_timestamp() - started_at) * 1000);
end;
$expiry$;
reset role;

do $assertions$
declare metric_row record;
begin
  if (select count(*) from wave8b_scale_teams) <> 10000 then raise exception 'SCALE_TEAM_COUNT'; end if;
  if (select count(*) from private.pachanga_team_operational_states_v1 states
      where exists (select 1 from wave8b_scale_teams seeded where seeded.id = states.group_id)) <> 10000
    then raise exception 'SCALE_STATE_COUNT'; end if;
  if (select count(*) from private.pachanga_team_operational_state_revisions_v1 revisions
      where exists (select 1 from wave8b_scale_teams seeded where seeded.id = revisions.group_id)) <> 50100
    then raise exception 'SCALE_REVISION_COUNT'; end if;
  if (select count(*) from private.pachanga_team_operational_restrictions_v1 restrictions
      where exists (select 1 from wave8b_scale_teams seeded where seeded.id = restrictions.group_id)) <> 50000
    then raise exception 'SCALE_RESTRICTION_COUNT'; end if;
  if (select count(*) from private.pachanga_team_operational_continuity_decisions_v1 decisions
      where exists (select 1 from wave8b_scale_teams seeded where seeded.id = decisions.group_id)) <> 20000
    then raise exception 'SCALE_CONTINUITY_COUNT'; end if;
  if (select count(*) from private.pachanga_team_operational_reviews_v1 reviews
      where exists (select 1 from wave8b_scale_teams seeded where seeded.id = reviews.group_id)) <> 20000
    then raise exception 'SCALE_REVIEW_COUNT'; end if;
  if (select count(*) from private.pachanga_team_operational_appeals_v1 appeals
      where exists (select 1 from wave8b_scale_teams seeded where seeded.id = appeals.group_id)) <> 10000
    then raise exception 'SCALE_APPEAL_COUNT'; end if;
  if (select count(*) from public.pachanga_team_operational_invalidations_v1 invalidations
      where exists (select 1 from wave8b_scale_teams seeded where seeded.id = invalidations.group_id)) <> 100100
    then raise exception 'SCALE_INVALIDATION_COUNT'; end if;

  for metric_row in select * from wave8b_scale_metrics loop
    if metric_row.metric = 'expiry_worker_100' and metric_row.elapsed_ms > 10000 then
      raise exception 'SCALE_THRESHOLD_EXCEEDED % %ms', metric_row.metric, metric_row.elapsed_ms;
    elsif metric_row.metric = 'control_center_list' and metric_row.elapsed_ms > 3000 then
      raise exception 'SCALE_THRESHOLD_EXCEEDED % %ms', metric_row.metric, metric_row.elapsed_ms;
    elsif metric_row.metric <> 'expiry_worker_100' and metric_row.metric <> 'control_center_list'
      and metric_row.elapsed_ms > 1000 then
      raise exception 'SCALE_THRESHOLD_EXCEEDED % %ms', metric_row.metric, metric_row.elapsed_ms;
    end if;
  end loop;
end;
$assertions$;

select jsonb_build_object(
  'teams', 10000,
  'currentStates', 10000,
  'seedStateRevisions', 50000,
  'finalStateRevisions', 50100,
  'restrictions', 50000,
  'continuityDecisions', 20000,
  'reviews', 20000,
  'appeals', 10000,
  'seedInvalidations', 100000,
  'finalInvalidations', 100100,
  'metricsMs', (select jsonb_object_agg(metric, round(elapsed_ms, 3)) from wave8b_scale_metrics),
  'rollback', true
);

rollback;
