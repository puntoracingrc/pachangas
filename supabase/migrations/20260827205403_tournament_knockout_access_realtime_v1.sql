-- Pachangas IQ R6C: authenticated command surface, canonical bracket reads,
-- invalidation-only Realtime and socially safe notifications.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_tournament_knockout_bump_revision_v1(
  target_bracket_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint,
  target_status text default null
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare confirmed_revision bigint;
begin
  update public.pachanga_tournament_brackets brackets set
    status = coalesce(target_status, brackets.status),
    revision = brackets.revision + 1,
    server_sequence = target_server_sequence,
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where brackets.id = target_bracket_id
  returning brackets.revision into confirmed_revision;
  if confirmed_revision is null then
    raise exception 'TOURNAMENT_BRACKET_NOT_FOUND' using errcode = 'P0002';
  end if;
  return confirmed_revision;
end;
$$;

create or replace function private.pachanga_tournament_knockout_round_control_v1(
  target_bracket_id uuid,
  target_round_code text,
  target_status text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare current_control public.pachanga_tournament_bracket_round_controls%rowtype;
declare saved_control public.pachanga_tournament_bracket_round_controls%rowtype;
declare normalized_round text := upper(trim(coalesce(target_round_code, '')));
declare normalized_status text := upper(trim(coalesce(target_status, '')));
declare round_order_value integer;
declare node_snapshot_value jsonb;
declare checksum_value text;
declare next_revision integer;
begin
  if target_operation_id is null or target_actor_id is null
     or normalized_status not in ('COMPLETED', 'LOCKED') then
    raise exception 'TOURNAMENT_ROUND_CONTROL_INVALID' using errcode = '22023';
  end if;
  select * into saved_control
  from public.pachanga_tournament_bracket_round_controls controls
  where controls.operation_id = target_operation_id;
  if found then
    return jsonb_build_object(
      'roundCode', saved_control.round_code,
      'status', saved_control.status,
      'controlId', saved_control.id,
      'changed', false,
      'replay', true
    );
  end if;
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = target_bracket_id for update;
  if not found or bracket_row.status not in ('active', 'administrative_review') then
    raise exception 'TOURNAMENT_BRACKET_NOT_ACTIVE' using errcode = 'PT409';
  end if;
  select min(nodes.round_order) into round_order_value
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.bracket_id = bracket_row.id and nodes.round_code = normalized_round;
  if round_order_value is null then
    raise exception 'TOURNAMENT_ROUND_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into current_control
  from public.pachanga_tournament_bracket_round_controls controls
  where controls.bracket_id = bracket_row.id
    and controls.round_code = normalized_round
  order by controls.control_revision desc, controls.server_sequence desc,
    controls.id desc limit 1 for update;
  if current_control.status = 'LOCKED' then
    if normalized_status = 'LOCKED' then
      return jsonb_build_object(
        'roundCode', normalized_round, 'status', 'LOCKED',
        'controlId', current_control.id, 'changed', false, 'replay', false
      );
    end if;
    raise exception 'TOURNAMENT_ROUND_LOCKED' using errcode = '55000';
  end if;
  if normalized_status = 'COMPLETED' and current_control.status = 'COMPLETED' then
    return jsonb_build_object(
      'roundCode', normalized_round, 'status', 'COMPLETED',
      'controlId', current_control.id, 'changed', false, 'replay', false
    );
  end if;
  if normalized_status = 'LOCKED' and current_control.status is distinct from 'COMPLETED' then
    raise exception 'TOURNAMENT_ROUND_MUST_BE_COMPLETED' using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.bracket_id = bracket_row.id
      and nodes.round_code = normalized_round
      and nodes.status not in ('advanced', 'cancelled')
  ) then
    raise exception 'TOURNAMENT_ROUND_HAS_PENDING_NODES' using errcode = 'PT409';
  end if;
  select jsonb_agg(jsonb_build_object(
    'nodeId', nodes.id,
    'status', nodes.status,
    'winnerEntryId', nodes.winner_entry_id,
    'loserEntryId', nodes.loser_entry_id,
    'canonicalMatchId', nodes.canonical_match_id,
    'revision', nodes.revision,
    'serverSequence', nodes.server_sequence
  ) order by nodes.node_kind, nodes.node_order, nodes.id)
  into node_snapshot_value
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.bracket_id = bracket_row.id and nodes.round_code = normalized_round;
  next_revision := coalesce(current_control.control_revision, 0) + 1;
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'bracketId', bracket_row.id,
    'roundCode', normalized_round,
    'roundOrder', round_order_value,
    'status', normalized_status,
    'revision', next_revision,
    'nodes', node_snapshot_value
  ));
  insert into public.pachanga_tournament_bracket_round_controls(
    id, bracket_id, round_code, round_order, control_revision,
    supersedes_control_id, status, node_snapshot, checksum, operation_id,
    created_by, server_sequence
  ) values (
    private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id, 'round-control:' || normalized_round
    ), bracket_row.id, normalized_round, round_order_value, next_revision,
    current_control.id, normalized_status, node_snapshot_value, checksum_value,
    target_operation_id, target_actor_id, target_server_sequence
  ) returning * into saved_control;
  return jsonb_build_object(
    'roundCode', normalized_round,
    'status', normalized_status,
    'controlId', saved_control.id,
    'changed', true,
    'replay', false
  );
end;
$$;

create or replace function private.pachanga_tournament_knockout_lifecycle_revision_v1(
  target_bracket_id uuid,
  target_lifecycle_status text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_reason text,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare prior_revision public.pachanga_tournament_bracket_revisions%rowtype;
declare saved_revision public.pachanga_tournament_bracket_revisions%rowtype;
declare revision_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'bracket-lifecycle-revision'
);
declare normalized_status text := lower(trim(coalesce(target_lifecycle_status, '')));
declare revision_kind text;
declare next_version integer;
declare checksum_value text;
begin
  select * into saved_revision
  from public.pachanga_tournament_bracket_revisions revisions
  where revisions.operation_id = target_operation_id;
  if found then return saved_revision.id; end if;
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = target_bracket_id for update;
  if not found then
    raise exception 'TOURNAMENT_BRACKET_NOT_FOUND' using errcode = 'P0002';
  end if;
  if normalized_status = 'completed' then
    if bracket_row.status not in ('active', 'administrative_review')
       or bracket_row.current_completion_snapshot_id is null then
      raise exception 'TOURNAMENT_COMPLETION_SNAPSHOT_REQUIRED' using errcode = 'PT409';
    end if;
    revision_kind := 'COMPLETION';
  elsif normalized_status = 'locked' then
    if bracket_row.status <> 'completed' then
      raise exception 'TOURNAMENT_MUST_BE_COMPLETED' using errcode = 'PT409';
    end if;
    revision_kind := 'LOCK';
  else
    raise exception 'TOURNAMENT_LIFECYCLE_STATUS_INVALID' using errcode = '22023';
  end if;
  select * into prior_revision
  from public.pachanga_tournament_bracket_revisions revisions
  where revisions.id = bracket_row.current_revision_id;
  if not found then
    raise exception 'TOURNAMENT_BRACKET_REVISION_REQUIRED' using errcode = 'P0002';
  end if;
  next_version := prior_revision.version + 1;
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'previousChecksum', prior_revision.checksum,
    'revisionKind', revision_kind,
    'lifecycleStatus', normalized_status,
    'version', next_version,
    'completionSnapshotId', bracket_row.current_completion_snapshot_id,
    'reason', left(trim(target_reason), 1200)
  ));
  insert into public.pachanga_tournament_bracket_revisions(
    id, bracket_id, version, supersedes_revision_id, revision_kind,
    lifecycle_status, qualification_snapshot_id, bracket_template_id,
    rule_revision_id, qualification_checksum, template_checksum,
    rule_checksum, policy_snapshot, structure_snapshot, checksum,
    operation_id, reason, created_by, server_sequence
  ) values (
    revision_id, bracket_row.id, next_version, prior_revision.id,
    revision_kind, normalized_status, prior_revision.qualification_snapshot_id,
    prior_revision.bracket_template_id, prior_revision.rule_revision_id,
    prior_revision.qualification_checksum, prior_revision.template_checksum,
    prior_revision.rule_checksum, prior_revision.policy_snapshot,
    prior_revision.structure_snapshot, checksum_value, target_operation_id,
    left(trim(target_reason), 1200), target_actor_id, target_server_sequence
  ) returning * into saved_revision;
  update public.pachanga_tournament_brackets brackets set
    current_revision_id = saved_revision.id,
    status = normalized_status,
    revision = brackets.revision + 1,
    server_sequence = target_server_sequence,
    updated_by = target_actor_id,
    completed_at = case when normalized_status = 'completed'
      then clock_timestamp() else brackets.completed_at end,
    locked_at = case when normalized_status = 'locked'
      then clock_timestamp() else brackets.locked_at end,
    updated_at = clock_timestamp()
  where brackets.id = bracket_row.id;
  return saved_revision.id;
end;
$$;

create or replace function private.pachanga_tournament_knockout_notify_v1(
  target_bracket_id uuid,
  target_event text,
  target_node_id uuid,
  target_operation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare normalized_event text := upper(trim(coalesce(target_event, '')));
declare recipient record;
declare sent_count integer := 0;
declare title_value text;
declare body_value text;
begin
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = target_bracket_id;
  if not found then return 0; end if;
  title_value := case normalized_event
    when 'BRACKET_ACTIVATED' then 'Cuadro eliminatorio activo'
    when 'NEXT_MATCH_READY' then 'Siguiente eliminatoria preparada'
    when 'BRACKET_CORRECTED' then 'Cuadro actualizado'
    when 'CHAMPION_CONFIRMED' then 'Campeón confirmado'
    else 'Torneo actualizado' end;
  body_value := case normalized_event
    when 'BRACKET_ACTIVATED' then 'Ya puedes consultar los cruces del torneo.'
    when 'NEXT_MATCH_READY' then 'El cuadro tiene un nuevo partido preparado.'
    when 'BRACKET_CORRECTED' then 'Se ha aplicado una corrección oficial al cuadro.'
    when 'CHAMPION_CONFIRMED' then 'El torneo ya tiene campeón oficial.'
    else 'Consulta el estado canónico del torneo.' end;
  for recipient in
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
    where entries.competition_id = bracket_row.competition_id
      and entries.status in ('accepted', 'active', 'completed')
      and recipients.user_id is not null
    order by recipients.user_id
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      'tournament_bracket_update',
      title_value,
      body_value,
      '/competiciones/' || bracket_row.competition_id::text || '/torneo?tab=bracket',
      jsonb_strip_nulls(jsonb_build_object(
        'competitionId', bracket_row.competition_id,
        'bracketId', bracket_row.id,
        'nodeId', target_node_id,
        'event', normalized_event
      )),
      'r6c:' || target_operation_id::text || ':' || normalized_event
        || ':' || recipient.user_id::text
    );
    sent_count := sent_count + 1;
  end loop;
  return sent_count;
end;
$$;

create or replace function public.get_pachanga_tournament_knockout_v1(
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
  return private.pachanga_tournament_knockout_read_model_v1(competition_id, actor_id);
end;
$$;

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
declare snapshot jsonb;
declare target_competition_id uuid := competition_id;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  snapshot := private.pachanga_tournament_group_hub_snapshot_v1(
    target_competition_id, actor_id
  );
  if exists (
    select 1 from public.pachanga_tournament_brackets brackets
    where brackets.competition_id = target_competition_id
  ) then
    snapshot := snapshot || jsonb_build_object(
      'knockout', private.pachanga_tournament_knockout_read_model_v1(
        target_competition_id, actor_id
      )
    );
  else
    snapshot := snapshot || jsonb_build_object('knockout', null);
  end if;
  return snapshot;
end;
$$;

create or replace function public.command_pachanga_tournament_knockout_v1(
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
declare competition_row public.pachanga_competitions%rowtype;
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare advance_row public.pachanga_tournament_bracket_advance_decisions%rowtype;
declare completion_row public.pachanga_tournament_completion_snapshots%rowtype;
declare action_sequence bigint;
declare event_sequence bigint;
declare confirmed_revision bigint;
declare target_node_id uuid;
declare target_decision_id uuid;
declare target_venue_id uuid;
declare target_round_code text;
declare starts_at_value timestamptz;
declare ends_at_value timestamptz;
declare reason_text text;
declare action_result jsonb := '{}'::jsonb;
declare snapshot jsonb;
declare changed boolean := false;
declare revision_already_bumped boolean := false;
declare notification_event text;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or actor_id is null
     or normalized_action not in (
       'bracket.activate', 'bracket.reserve_slot', 'bracket.node.resolve',
       'bracket.node.generate_match', 'bracket.node.invalidate',
       'bracket.result.advance', 'bracket.result.recompute',
       'bracket.admin.replace_downstream', 'bracket.complete_round',
       'bracket.lock_round', 'tournament.completion.rebuild',
       'tournament.complete', 'tournament.lock'
     ) or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_TOURNAMENT_KNOCKOUT_COMMAND' using errcode = '22023';
  end if;
  if payload ?| array[
    'actorId','actorUserId','createdBy','updatedBy','winnerEntryId',
    'loserEntryId','championEntryId','runnerUpEntryId','thirdPlaceEntryId',
    'serverSequence','revision','confirmedRevision','confirmedAt','completedAt',
    'canonicalMatchId','matchContextId','downstreamMatchId','result','score',
    'advanceReason','policySnapshot','checksum','status'
  ] then
    raise exception 'TOURNAMENT_SERVER_FIELDS_FORBIDDEN' using errcode = '22023';
  end if;
  if normalized_action = 'bracket.reserve_slot' then
    if payload - array[
      'nodeId','startsAt','endsAt','timezone','venueId','venueLabel',
      'resourceKey','reason'
    ]::text[] <> '{}'::jsonb then
      raise exception 'TOURNAMENT_KNOCKOUT_RESERVATION_PAYLOAD_INVALID' using errcode = '22023';
    end if;
  elsif normalized_action in (
    'bracket.node.resolve','bracket.node.generate_match',
    'bracket.node.invalidate','bracket.admin.replace_downstream'
  ) then
    if payload - array['nodeId','reason']::text[] <> '{}'::jsonb then
      raise exception 'TOURNAMENT_KNOCKOUT_NODE_PAYLOAD_INVALID' using errcode = '22023';
    end if;
  elsif normalized_action in ('bracket.result.advance','bracket.result.recompute') then
    if payload - array['officialDecisionId','reason']::text[] <> '{}'::jsonb then
      raise exception 'TOURNAMENT_KNOCKOUT_RESULT_PAYLOAD_INVALID' using errcode = '22023';
    end if;
  elsif normalized_action in ('bracket.complete_round','bracket.lock_round') then
    if payload - array['roundCode','reason']::text[] <> '{}'::jsonb then
      raise exception 'TOURNAMENT_KNOCKOUT_ROUND_PAYLOAD_INVALID' using errcode = '22023';
    end if;
  elsif payload - array['reason']::text[] <> '{}'::jsonb then
    raise exception 'TOURNAMENT_KNOCKOUT_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  if normalized_action in (
       'bracket.reserve_slot','bracket.node.resolve',
       'bracket.node.generate_match','bracket.node.invalidate',
       'bracket.admin.replace_downstream'
     ) and nullif(payload ->> 'nodeId', '') is null then
    raise exception 'TOURNAMENT_KNOCKOUT_NODE_REQUIRED' using errcode = '22023';
  end if;
  if normalized_action in ('bracket.result.advance','bracket.result.recompute')
     and nullif(payload ->> 'officialDecisionId', '') is null then
    raise exception 'TOURNAMENT_OFFICIAL_DECISION_REQUIRED' using errcode = '22023';
  end if;
  if normalized_action in ('bracket.complete_round','bracket.lock_round')
     and nullif(trim(payload ->> 'roundCode'), '') is null then
    raise exception 'TOURNAMENT_ROUND_REQUIRED' using errcode = '22023';
  end if;
  begin
    if payload ? 'nodeId' then target_node_id := (payload ->> 'nodeId')::uuid; end if;
    if payload ? 'officialDecisionId' then
      target_decision_id := (payload ->> 'officialDecisionId')::uuid;
    end if;
    if nullif(payload ->> 'venueId', '') is not null then
      target_venue_id := (payload ->> 'venueId')::uuid;
    end if;
    if payload ? 'startsAt' then starts_at_value := (payload ->> 'startsAt')::timestamptz; end if;
    if payload ? 'endsAt' then ends_at_value := (payload ->> 'endsAt')::timestamptz; end if;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception 'TOURNAMENT_KNOCKOUT_PAYLOAD_INVALID' using errcode = '22023';
  end;
  target_round_code := upper(trim(coalesce(payload ->> 'roundCode', '')));
  reason_text := left(trim(coalesce(payload ->> 'reason', normalized_action)), 1200);
  if length(reason_text) < 3 then
    raise exception 'TOURNAMENT_KNOCKOUT_REASON_REQUIRED' using errcode = '22023';
  end if;

  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 92601));
  replay := private.pachanga_tournament_replay_v1(
    operation_id, actor_id, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'r6c-command:' || aggregate_id::text, 92602
  ));
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = aggregate_id for update;
  if not found or competition_row.competition_type <> 'TOURNAMENT'
     or competition_row.product_key <> 'TOURNAMENT_PRIVATE_BETA_V1' then
    raise exception 'TOURNAMENT_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform private.pachanga_tournament_assert_flags_v1();
  if to_regprocedure(
    'private.pachanga_tournament_knockout_assert_flags_v1(text)'
  ) is null then
    raise exception 'TOURNAMENT_KNOCKOUT_DISABLED' using errcode = '42501';
  end if;
  execute 'select private.pachanga_tournament_knockout_assert_flags_v1($1)'
    using normalized_action;

  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.competition_id = aggregate_id for update;
  if normalized_action = 'bracket.activate' then
    if found then
      if bracket_row.revision <> expected_revision then
        raise exception 'STALE_REVISION' using errcode = 'PT409';
      end if;
    else
      select * into state_row
      from public.pachanga_tournament_group_stage_states states
      where states.competition_id = aggregate_id for update;
      if not found then
        raise exception 'TOURNAMENT_GROUP_STAGE_NOT_PREPARED' using errcode = 'P0002';
      end if;
      if state_row.revision <> expected_revision then
        raise exception 'STALE_REVISION' using errcode = 'PT409';
      end if;
    end if;
  else
    if not found then
      raise exception 'TOURNAMENT_BRACKET_NOT_FOUND' using errcode = 'P0002';
    end if;
    if bracket_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
  end if;
  if normalized_action in (
    'bracket.result.advance','bracket.result.recompute'
  ) then
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'results_manage') then
      raise exception 'TOURNAMENT_RESULT_MANAGER_REQUIRED' using errcode = '42501';
    end if;
  elsif normalized_action in ('tournament.complete','tournament.lock') then
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'bracket_publish') then
      raise exception 'TOURNAMENT_BRACKET_PUBLISHER_REQUIRED' using errcode = '42501';
    end if;
  elsif normalized_action in (
      'bracket.node.invalidate','bracket.admin.replace_downstream'
    ) and not (
      private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'bracket_manage')
      or private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'operations_manage')
    ) then
    raise exception 'TOURNAMENT_BRACKET_OR_OPERATIONS_MANAGER_REQUIRED' using errcode = '42501';
  elsif normalized_action not in (
      'bracket.node.invalidate','bracket.admin.replace_downstream'
    ) and not private.pachanga_tournament_can_v1(
      aggregate_id, actor_id, 'bracket_manage'
    ) then
    raise exception 'TOURNAMENT_BRACKET_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  if target_node_id is not null then
    select * into node_row
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.id = target_node_id
      and nodes.bracket_id = bracket_row.id for update;
    if not found then
      raise exception 'TOURNAMENT_BRACKET_NODE_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;

  action_sequence := nextval('private.pachanga_competition_sequence');
  case normalized_action
    when 'bracket.activate' then
      if bracket_row.id is null then
        action_result := jsonb_build_object(
          'bracketId', private.pachanga_tournament_knockout_activate_v1(
            aggregate_id, operation_id, actor_id, action_sequence
          ), 'replay', false
        );
        changed := true;
        notification_event := 'BRACKET_ACTIVATED';
      else
        action_result := jsonb_build_object('bracketId', bracket_row.id, 'replay', true);
      end if;
    when 'bracket.reserve_slot' then
      action_result := jsonb_build_object(
        'reservationId', private.pachanga_tournament_knockout_reserve_slot_v1(
          target_node_id, starts_at_value, ends_at_value, payload ->> 'timezone',
          target_venue_id, payload ->> 'venueLabel', payload ->> 'resourceKey',
          operation_id, actor_id, action_sequence
        )
      );
      changed := true;
    when 'bracket.node.resolve' then
      action_result := private.pachanga_tournament_knockout_resolve_node_v1(
        target_node_id, operation_id, actor_id, action_sequence
      );
      changed := coalesce((action_result ->> 'changed')::boolean, false);
    when 'bracket.node.generate_match' then
      action_result := private.pachanga_tournament_knockout_generate_match_v1(
        target_node_id, operation_id, actor_id, action_sequence
      );
      changed := not coalesce((action_result ->> 'replay')::boolean, false);
      if changed then notification_event := 'NEXT_MATCH_READY'; end if;
    when 'bracket.node.invalidate' then
      select * into advance_row
      from public.pachanga_tournament_bracket_advance_decisions decisions
      where decisions.source_node_id = target_node_id
      order by decisions.revision desc, decisions.server_sequence desc,
        decisions.id desc limit 1;
      if not found then
        raise exception 'TOURNAMENT_ADVANCE_DECISION_NOT_FOUND' using errcode = 'P0002';
      end if;
      action_result := jsonb_build_object(
        'invalidationId', private.pachanga_tournament_knockout_invalidate_downstream_v1(
          target_node_id, advance_row.id, null, reason_text, operation_id,
          actor_id, action_sequence
        )
      );
      changed := true;
      notification_event := 'BRACKET_CORRECTED';
    when 'bracket.result.advance' then
      action_result := private.pachanga_tournament_knockout_apply_official_decision_v1(
        target_decision_id
      );
    when 'bracket.result.recompute' then
      action_result := private.pachanga_tournament_knockout_apply_official_decision_v1(
        target_decision_id
      );
    when 'bracket.admin.replace_downstream' then
      action_result := private.pachanga_tournament_knockout_replace_downstream_v1(
        target_node_id, operation_id, actor_id, action_sequence
      );
      changed := true;
      notification_event := 'BRACKET_CORRECTED';
    when 'bracket.complete_round' then
      action_result := private.pachanga_tournament_knockout_round_control_v1(
        bracket_row.id, target_round_code, 'COMPLETED', operation_id,
        actor_id, action_sequence
      );
      changed := coalesce((action_result ->> 'changed')::boolean, false);
    when 'bracket.lock_round' then
      action_result := private.pachanga_tournament_knockout_round_control_v1(
        bracket_row.id, target_round_code, 'LOCKED', operation_id,
        actor_id, action_sequence
      );
      changed := coalesce((action_result ->> 'changed')::boolean, false);
    when 'tournament.completion.rebuild' then
      select * into completion_row
      from private.pachanga_tournament_completion_rebuild_v1(
        bracket_row.id, operation_id, actor_id, action_sequence
      );
      action_result := jsonb_build_object(
        'completionSnapshotId', completion_row.id,
        'championEntryId', completion_row.champion_entry_id,
        'runnerUpEntryId', completion_row.runner_up_entry_id,
        'thirdPlaceEntryId', completion_row.third_place_entry_id,
        'checksum', completion_row.completion_checksum
      );
      revision_already_bumped := true;
    when 'tournament.complete' then
      select * into completion_row
      from private.pachanga_tournament_completion_rebuild_v1(
        bracket_row.id,
        private.pachanga_tournament_knockout_entity_id_v1(
          operation_id, 'completion-before-close'
        ), actor_id, action_sequence
      );
      action_result := jsonb_build_object(
        'bracketRevisionId', private.pachanga_tournament_knockout_lifecycle_revision_v1(
          bracket_row.id, 'completed', operation_id, actor_id,
          reason_text, nextval('private.pachanga_competition_sequence')
        ), 'completionSnapshotId', completion_row.id, 'status', 'completed'
      );
      revision_already_bumped := true;
      notification_event := 'CHAMPION_CONFIRMED';
    when 'tournament.lock' then
      action_result := jsonb_build_object(
        'bracketRevisionId', private.pachanga_tournament_knockout_lifecycle_revision_v1(
          bracket_row.id, 'locked', operation_id, actor_id,
          reason_text, action_sequence
        ), 'status', 'locked'
      );
      revision_already_bumped := true;
  end case;

  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.competition_id = aggregate_id for update;
  event_sequence := nextval('private.pachanga_competition_sequence');
  if changed and not revision_already_bumped then
    if normalized_action = 'bracket.node.invalidate' then
      confirmed_revision := private.pachanga_tournament_knockout_bump_revision_v1(
        bracket_row.id, actor_id, event_sequence, 'administrative_review'
      );
    else
      confirmed_revision := private.pachanga_tournament_knockout_bump_revision_v1(
        bracket_row.id, actor_id, event_sequence, null
      );
    end if;
  else
    select brackets.revision into confirmed_revision
    from public.pachanga_tournament_brackets brackets
    where brackets.id = bracket_row.id;
  end if;
  perform private.pachanga_tournament_knockout_rebuild_read_model_v1(
    bracket_row.id, event_sequence
  );
  snapshot := private.pachanga_tournament_knockout_read_model_v1(
    aggregate_id, actor_id
  );
  if notification_event is not null then
    perform private.pachanga_tournament_knockout_notify_v1(
      bracket_row.id, notification_event, target_node_id, operation_id
    );
  end if;
  return private.pachanga_tournament_store_command_v1(
    operation_id, actor_id, normalized_action, aggregate_id, aggregate_id,
    confirmed_revision, event_sequence, request_hash,
    private.pachanga_competition_client_metadata_v1(
      coalesce(client_metadata, '{}'::jsonb)
    ), jsonb_strip_nulls(jsonb_build_object(
      'action', normalized_action,
      'bracketId', bracket_row.id,
      'nodeId', target_node_id,
      'result', action_result
    )), snapshot
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available
    or exclusion_violation or unique_violation then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_knockout_bump_revision_v1(uuid,uuid,bigint,text)'::regprocedure,
    'private.pachanga_tournament_knockout_round_control_v1(uuid,text,text,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_lifecycle_revision_v1(uuid,text,uuid,uuid,text,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_notify_v1(uuid,text,uuid,uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

revoke all on function public.get_pachanga_tournament_knockout_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_tournament_group_hub_v1(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.command_pachanga_tournament_knockout_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public, anon, authenticated, service_role;

grant execute on function public.get_pachanga_tournament_knockout_v1(uuid)
  to authenticated, service_role;
grant execute on function public.get_pachanga_tournament_group_hub_v1(uuid)
  to authenticated, service_role;
grant execute on function public.command_pachanga_tournament_knockout_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated, service_role;

comment on function public.command_pachanga_tournament_knockout_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) is 'Only authenticated R6C write authority. Winner, loser, champion and downstream canonical identifiers are always resolved server-side.';
