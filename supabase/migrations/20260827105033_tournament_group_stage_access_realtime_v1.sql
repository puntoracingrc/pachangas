-- Pachangas IQ R6B: authenticated command surface, canonical reads and
-- invalidation-only Realtime. Direct table access remains closed.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function public.get_pachanga_tournament_group_hub_v1(
  competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  return private.pachanga_tournament_group_hub_snapshot_v1(competition_id, actor_id);
end;
$$;

create or replace function public.command_pachanga_tournament_group_stage_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare sequence_value bigint;
declare competition_row public.pachanga_competitions%rowtype;
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare qualification_row public.pachanga_tournament_qualification_snapshots%rowtype;
declare bracket_row public.pachanga_tournament_bracket_templates%rowtype;
declare target_group_id uuid;
declare action_result jsonb;
declare snapshot jsonb;
declare confirmed_revision bigint;
declare event_payload jsonb;
declare notification_row record;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or actor_id is null
     or normalized_action not in (
       'group_stage.prepare',
       'group_schedule.create',
       'group_schedule.generate',
       'group_schedule.validate',
       'group_schedule.publish',
       'group_stage.activate',
       'group_stage.complete',
       'qualification.rebuild',
       'qualification.validate',
       'qualification.publish',
       'bracket_template.create',
       'bracket_template.publish'
     )
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_TOURNAMENT_GROUP_STAGE_COMMAND' using errcode = '22023';
  end if;
  if payload ?| array[
    'actorId','actorUserId','createdBy','updatedBy','serverSequence',
    'revision','confirmedRevision','confirmedAt','competitionId','stageId',
    'schedulePlanId','resourceKey','canonicalMatchId','matchContextId',
    'standingSnapshotId','qualificationSnapshotId','bracketTemplateId',
    'result','checksum','status'
  ] then
    raise exception 'TOURNAMENT_SERVER_FIELDS_FORBIDDEN' using errcode = '22023';
  end if;
  if normalized_action = 'group_schedule.create' then
    if payload - array['groupId','slots','reason']::text[] <> '{}'::jsonb
       or jsonb_typeof(coalesce(payload -> 'slots', 'null'::jsonb)) <> 'array' then
      raise exception 'TOURNAMENT_GROUP_SLOT_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    begin
      target_group_id := (payload ->> 'groupId')::uuid;
    exception when others then
      raise exception 'TOURNAMENT_GROUP_SLOT_PAYLOAD_INVALID' using errcode = '22023';
    end;
  elsif payload - array['reason']::text[] <> '{}'::jsonb then
    raise exception 'TOURNAMENT_GROUP_STAGE_PAYLOAD_INVALID' using errcode = '22023';
  end if;

  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91921));
  replay := private.pachanga_tournament_replay_v1(
    operation_id, actor_id, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'r6b-command:' || aggregate_id::text, 91922
  ));

  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = aggregate_id
  for update;
  if not found or competition_row.competition_type <> 'TOURNAMENT'
     or competition_row.product_key <> 'TOURNAMENT_PRIVATE_BETA_V1' then
    raise exception 'TOURNAMENT_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform private.pachanga_tournament_assert_flags_v1();
  perform private.pachanga_tournament_group_stage_assert_flags_v1(normalized_action);

  select * into state_row
  from public.pachanga_tournament_group_stage_states states
  where states.competition_id = aggregate_id
  for update;
  if normalized_action = 'group_stage.prepare' then
    if found then
      raise exception 'TOURNAMENT_GROUP_STAGE_ALREADY_PREPARED' using errcode = 'PT409';
    end if;
    if competition_row.tournament_revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
  else
    if not found then
      raise exception 'TOURNAMENT_GROUP_STAGE_NOT_PREPARED' using errcode = 'P0002';
    end if;
    if state_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
  end if;

  if normalized_action in (
    'group_stage.prepare','group_schedule.create','group_schedule.generate',
    'group_schedule.validate','group_stage.activate'
  ) and not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'schedule_manage') then
    raise exception 'TOURNAMENT_SCHEDULE_MANAGER_REQUIRED' using errcode = '42501';
  elsif normalized_action = 'group_schedule.publish'
    and not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'schedule_publish') then
    raise exception 'TOURNAMENT_SCHEDULE_PUBLISHER_REQUIRED' using errcode = '42501';
  elsif normalized_action in ('qualification.rebuild','qualification.validate')
    and not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'qualification_manage') then
    raise exception 'TOURNAMENT_QUALIFICATION_MANAGER_REQUIRED' using errcode = '42501';
  elsif normalized_action = 'qualification.publish'
    and not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'qualification_publish') then
    raise exception 'TOURNAMENT_QUALIFICATION_PUBLISHER_REQUIRED' using errcode = '42501';
  elsif normalized_action = 'bracket_template.create'
    and not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'bracket_manage') then
    raise exception 'TOURNAMENT_BRACKET_MANAGER_REQUIRED' using errcode = '42501';
  elsif normalized_action = 'bracket_template.publish'
    and not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'bracket_publish') then
    raise exception 'TOURNAMENT_BRACKET_PUBLISHER_REQUIRED' using errcode = '42501';
  elsif normalized_action = 'group_stage.complete'
    and not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'operations_manage') then
    raise exception 'TOURNAMENT_OPERATIONS_MANAGER_REQUIRED' using errcode = '42501';
  end if;

  sequence_value := nextval('private.pachanga_competition_sequence');
  case normalized_action
    when 'group_stage.prepare' then
      action_result := private.pachanga_tournament_group_stage_prepare_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
    when 'group_schedule.create' then
      action_result := private.pachanga_tournament_group_schedule_create_slots_v1(
        operation_id, actor_id, aggregate_id, target_group_id,
        payload -> 'slots', sequence_value
      );
    when 'group_schedule.generate' then
      action_result := private.pachanga_tournament_group_schedule_generate_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
    when 'group_schedule.validate' then
      action_result := private.pachanga_tournament_group_schedule_validate_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
    when 'group_schedule.publish' then
      action_result := private.pachanga_tournament_group_schedule_publish_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
    when 'group_stage.activate' then
      if state_row.status <> 'schedule_published' or state_row.fixture_count < 1 then
        raise exception 'TOURNAMENT_GROUP_SCHEDULE_NOT_PUBLISHED' using errcode = '22023';
      end if;
      update public.pachanga_tournament_group_stage_states states set
        status = 'active', revision = states.revision + 1,
        server_sequence = sequence_value, updated_by = actor_id,
        updated_at = clock_timestamp()
      where states.id = state_row.id;
      action_result := jsonb_build_object('status', 'active');
    when 'group_stage.complete' then
      select * into qualification_row
      from public.pachanga_tournament_qualification_snapshots snapshots
      where snapshots.id = state_row.current_qualification_snapshot_id;
      if not found or qualification_row.status <> 'PUBLISHED'
         or state_row.status <> 'complete' then
        raise exception 'TOURNAMENT_QUALIFICATION_NOT_PUBLISHED' using errcode = '22023';
      end if;
      if state_row.completed_at is not null then
        raise exception 'TOURNAMENT_GROUP_STAGE_ALREADY_COMPLETED' using errcode = 'PT409';
      end if;
      update public.pachanga_tournament_group_stage_states states set
        completed_by = actor_id,
        completion_operation_id = operation_id,
        completed_at = clock_timestamp(),
        revision = states.revision + 1,
        server_sequence = sequence_value,
        updated_by = actor_id,
        updated_at = clock_timestamp()
      where states.id = state_row.id;
      action_result := jsonb_build_object(
        'status', 'complete',
        'qualificationSnapshotId', qualification_row.id,
        'completionOperationId', operation_id
      );
    when 'qualification.rebuild' then
      action_result := private.pachanga_tournament_qualification_rebuild_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
    when 'qualification.validate' then
      select * into qualification_row
      from public.pachanga_tournament_qualification_snapshots snapshots
      where snapshots.id = state_row.current_qualification_snapshot_id;
      if not found or qualification_row.status <> 'READY' then
        raise exception 'TOURNAMENT_QUALIFICATION_NOT_READY' using errcode = '22023';
      end if;
      action_result := jsonb_build_object(
        'qualificationSnapshotId', qualification_row.id,
        'status', qualification_row.status,
        'checksum', qualification_row.checksum
      );
    when 'qualification.publish' then
      action_result := private.pachanga_tournament_qualification_publish_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
    when 'bracket_template.create' then
      action_result := private.pachanga_tournament_bracket_template_create_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
    when 'bracket_template.publish' then
      action_result := private.pachanga_tournament_bracket_template_publish_v1(
        operation_id, actor_id, aggregate_id, sequence_value
      );
  end case;

  select * into state_row
  from public.pachanga_tournament_group_stage_states states
  where states.competition_id = aggregate_id;
  confirmed_revision := state_row.revision;
  snapshot := private.pachanga_tournament_group_hub_snapshot_v1(aggregate_id, actor_id);
  event_payload := jsonb_strip_nulls(jsonb_build_object(
    'action', normalized_action,
    'groupStageStateId', state_row.id,
    'groupId', target_group_id,
    'status', state_row.status,
    'result', action_result
  ));

  if normalized_action in ('group_schedule.publish','bracket_template.publish') then
    if normalized_action = 'bracket_template.publish' then
      select * into bracket_row
      from public.pachanga_tournament_bracket_templates templates
      where templates.id = state_row.current_bracket_template_id;
    end if;
    for notification_row in
      select distinct recipients.user_id
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      cross join lateral (
        select teams.owner_id as user_id
        union
        select members.user_id
        from public.pachanga_group_members members
        where members.group_id = teams.id
      ) recipients
      where entries.competition_id = aggregate_id
        and entries.status in ('accepted','active','completed')
        and recipients.user_id is not null
      order by recipients.user_id
    loop
      perform private.pachanga_notify_v1(
        notification_row.user_id,
        case when normalized_action = 'group_schedule.publish'
          then 'tournament_schedule_published' else 'tournament_bracket_prepared' end,
        case when normalized_action = 'group_schedule.publish'
          then 'Calendario de grupos publicado' else 'Cuadro preparado' end,
        case when normalized_action = 'group_schedule.publish'
          then 'Ya puedes consultar las jornadas y partidos de tu grupo.'
          else 'La plantilla eliminatoria ya está disponible, sin progresión activa.' end,
        '/?mobile=competiciones&tournament=' || aggregate_id::text,
        jsonb_strip_nulls(jsonb_build_object(
          'competitionId', aggregate_id,
          'groupStageStateId', state_row.id,
          'bracketTemplateId', bracket_row.id
        )),
        normalized_action || ':' || operation_id::text || ':' || notification_row.user_id::text
      );
    end loop;
  end if;

  return private.pachanga_tournament_store_command_v1(
    operation_id, actor_id, normalized_action, aggregate_id, aggregate_id,
    confirmed_revision, sequence_value, request_hash,
    private.pachanga_competition_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb)),
    event_payload, snapshot
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available
    or exclusion_violation then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function public.get_pachanga_platform_tournament_group_stage_control_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare states_value jsonb;
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  select coalesce(jsonb_agg(jsonb_build_object(
    'competitionId', states.competition_id,
    'competitionName', competitions.name,
    'groupStageStateId', states.id,
    'status', states.status,
    'groups', states.group_count,
    'entries', states.entry_count,
    'fixtures', states.fixture_count,
    'officialFixtures', states.official_fixture_count,
    'revision', states.revision,
    'serverSequence', states.server_sequence,
    'updatedAt', states.updated_at
  ) order by states.server_sequence desc, states.id desc), '[]'::jsonb)
  into states_value
  from public.pachanga_tournament_group_stage_states states
  join public.pachanga_competitions competitions on competitions.id = states.competition_id;
  return jsonb_build_object(
    'flags', private.pachanga_tournament_flags_v1(),
    'metrics', jsonb_build_object(
      'groupStages', (select count(*) from public.pachanga_tournament_group_stage_states),
      'schedulePlans', (select count(*) from public.pachanga_tournament_group_schedule_plans),
      'publishedFixtures', (select coalesce(sum(states.fixture_count), 0)
        from public.pachanga_tournament_group_stage_states states),
      'officialFixtures', (select coalesce(sum(states.official_fixture_count), 0)
        from public.pachanga_tournament_group_stage_states states),
      'qualificationSnapshots', (select count(*) from public.pachanga_tournament_qualification_snapshots),
      'publishedQualifications', (select count(*) from public.pachanga_tournament_qualification_snapshots snapshots
        where snapshots.status = 'PUBLISHED'),
      'bracketTemplates', (select count(*) from public.pachanga_tournament_bracket_templates),
      'knockoutMatches', 0
    ),
    'states', states_value,
    'health', jsonb_build_object(
      'knockoutMatchGenerationOff', true,
      'bracketProgressionOff', not (private.pachanga_tournament_flags_v1() ->> 'bracketProgressionEnabled')::boolean,
      'publicDiscoveryOff', not (private.pachanga_tournament_flags_v1() ->> 'publicDiscoveryEnabled')::boolean
    ),
    'updatedAt', statement_timestamp()
  );
end;
$$;

revoke all on function public.get_pachanga_tournament_group_hub_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.command_pachanga_tournament_group_stage_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_platform_tournament_group_stage_control_v1()
  from public, anon, authenticated, service_role;

grant execute on function public.get_pachanga_tournament_group_hub_v1(uuid)
  to authenticated;
grant execute on function public.command_pachanga_tournament_group_stage_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated;
grant execute on function public.get_pachanga_platform_tournament_group_stage_control_v1()
  to authenticated, service_role;

comment on function public.command_pachanga_tournament_group_stage_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) is 'R6B server-authoritative Tournament group-stage orchestrator. Browser input is intent only; every successful response contains the canonical Hub snapshot.';
comment on function public.get_pachanga_tournament_group_hub_v1(uuid) is
  'Canonical Tournament group-stage read model. Realtime events only invalidate this snapshot.';
