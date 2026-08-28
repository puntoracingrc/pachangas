-- Pachangas IQ R6C: bracket activation, R4B slot reservations and exact 1:1
-- CanonicalMatch publication for operational knockout nodes.

set lock_timeout = '5s';
set statement_timeout = '120s';

-- R4C serializes match commands through the canonical CompetitionRound. R6C
-- reuses that authority with a dedicated engine marker; it does not publish
-- round-robin pairings or create a second match/result model.
alter table public.pachanga_competition_schedule_plans
  drop constraint if exists pachanga_competition_schedule_plans_engine_version_check,
  drop constraint if exists pachanga_competition_schedule_plans_entry_count_check,
  add constraint pachanga_competition_schedule_plans_engine_version_check
    check (engine_version in ('league-round-robin-v1', 'tournament-knockout-v1')),
  add constraint pachanga_competition_schedule_plans_entry_count_check
    check (entry_count between 0 and 128);

alter table public.pachanga_competition_schedule_revisions
  drop constraint if exists pachanga_competition_schedule_revisions_engine_version_check,
  add constraint pachanga_competition_schedule_revisions_engine_version_check
    check (engine_version in ('league-round-robin-v1', 'tournament-knockout-v1'));

create or replace function private.pachanga_tournament_bracket_template_create_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_competition_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare draw_plan public.pachanga_competition_draw_plans%rowtype;
declare qualification_snapshot public.pachanga_tournament_qualification_snapshots%rowtype;
declare qualification_row public.pachanga_tournament_qualification_rows%rowtype;
declare template_id uuid := private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id, 'bracket-template-draft'
);
declare target_slots jsonb;
declare qualifier_count integer;
declare bracket_size_value integer;
declare bye_count integer;
declare bye_matches integer[] := '{}'::integer[];
declare bye_index integer;
declare bracket_order integer;
declare match_number integer;
declare qualifier_index integer := 0;
declare slot_key text;
declare side_value text;
declare is_bye boolean;
declare slot_item jsonb;
declare slot_snapshot jsonb := '[]'::jsonb;
declare template_snapshot_value jsonb;
declare checksum_value text;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  if not private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'bracket_manage'
  ) then raise exception 'TOURNAMENT_BRACKET_MANAGER_REQUIRED' using errcode = '42501'; end if;
  select * into draw_plan from public.pachanga_competition_draw_plans plans
  where plans.id = state_row.draw_plan_id;
  if draw_plan.target_type <> 'GROUPS_THEN_KNOCKOUT' then
    raise exception 'TOURNAMENT_BRACKET_TEMPLATE_NOT_REQUIRED' using errcode = '0A000';
  end if;
  select * into qualification_snapshot
  from public.pachanga_tournament_qualification_snapshots snapshots
  where snapshots.id = state_row.current_qualification_snapshot_id;
  if not found or qualification_snapshot.status <> 'PUBLISHED' then
    raise exception 'TOURNAMENT_QUALIFICATION_NOT_PUBLISHED' using errcode = '22023';
  end if;
  target_slots := qualification_snapshot.policy_snapshot -> 'targetBracketSlots';
  qualifier_count := jsonb_array_length(target_slots);
  bracket_size_value := private.pachanga_tournament_next_power_of_two_v1(qualifier_count);
  bye_count := bracket_size_value - qualifier_count;
  if qualifier_count < 2 or qualifier_count > 128 or bye_count > bracket_size_value / 2 then
    raise exception 'TOURNAMENT_BRACKET_SIZE_INVALID' using errcode = '22023';
  end if;
  if bye_count > 0 then
    for bye_index in 1..bye_count loop
      bye_matches := array_append(
        bye_matches,
        floor((bye_index - 1) * (bracket_size_value / 2)::numeric / bye_count)::integer + 1
      );
    end loop;
  end if;
  for bracket_order in 1..bracket_size_value loop
    match_number := ceil(bracket_order::numeric / 2)::integer;
    side_value := case when bracket_order % 2 = 1 then 'A' else 'B' end;
    is_bye := side_value = 'B' and match_number = any(bye_matches);
    if is_bye then
      slot_key := 'BYE-' || lpad(match_number::text, 2, '0');
      slot_item := jsonb_build_object(
        'slotKey', slot_key,
        'bracketOrder', bracket_order,
        'matchNumber', match_number,
        'side', side_value,
        'sourceKind', 'BYE',
        'resolvedEntryId', null
      );
    else
      qualifier_index := qualifier_index + 1;
      slot_key := target_slots ->> (qualifier_index - 1);
      select * into qualification_row
      from public.pachanga_tournament_qualification_rows rows
      where rows.qualification_snapshot_id = qualification_snapshot.id
        and rows.target_bracket_slot = slot_key;
      if not found then
        raise exception 'TOURNAMENT_BRACKET_SLOT_COUNT_MISMATCH' using errcode = '22023';
      end if;
      slot_item := jsonb_build_object(
        'slotKey', slot_key,
        'bracketOrder', bracket_order,
        'matchNumber', match_number,
        'side', side_value,
        'sourceKind', case when qualification_row.outcome = 'DIRECT_QUALIFIER'
          then 'GROUP_POSITION' else 'EXTRA_QUALIFIER' end,
        'sourceGroupId', case when qualification_row.outcome = 'DIRECT_QUALIFIER'
          then qualification_row.competition_group_id else null end,
        'sourcePosition', case when qualification_row.outcome = 'DIRECT_QUALIFIER'
          then qualification_row.group_position else null end,
        'sourceExtraRank', case when qualification_row.outcome = 'EXTRA_QUALIFIER'
          then qualification_row.cross_group_rank else null end,
        'resolvedEntryId', qualification_row.entry_id
      );
    end if;
    slot_snapshot := slot_snapshot || jsonb_build_array(slot_item);
  end loop;
  if qualifier_index <> qualifier_count or jsonb_array_length(slot_snapshot) <> bracket_size_value then
    raise exception 'TOURNAMENT_BRACKET_SLOT_COUNT_MISMATCH' using errcode = '22023';
  end if;
  template_snapshot_value := jsonb_build_object(
    'kind', 'CompetitionBracketTemplate',
    'status', 'DRAFT',
    'qualificationSnapshotId', qualification_snapshot.id,
    'qualifierCount', qualifier_count,
    'bracketSize', bracket_size_value,
    'byeCount', bye_count,
    'firstRoundMatchCount', bracket_size_value / 2,
    'slots', slot_snapshot,
    'progressionEnabled', false,
    'message', 'Cuadro preparado para la fase eliminatoria.'
  );
  checksum_value := private.pachanga_tournament_json_checksum_v1(template_snapshot_value);
  insert into public.pachanga_tournament_bracket_templates(
    id, group_stage_state_id, competition_id, edition_id, stage_id,
    rule_revision_id, qualification_snapshot_id, supersedes_template_id,
    status, bracket_size, first_round_match_count, slot_count,
    template_snapshot, checksum, operation_id, created_by, server_sequence
  ) values (
    template_id, state_row.id, state_row.competition_id, state_row.edition_id,
    state_row.stage_id, state_row.rule_revision_id, qualification_snapshot.id,
    state_row.current_bracket_template_id, 'DRAFT', bracket_size_value,
    bracket_size_value / 2, bracket_size_value, template_snapshot_value,
    checksum_value, target_operation_id, target_actor_id, target_server_sequence
  );
  insert into public.pachanga_tournament_bracket_slots(
    bracket_template_id, slot_key, match_number, side, bracket_order,
    source_kind, source_group_id, source_position, source_extra_rank,
    resolved_entry_id, status, source_snapshot, server_sequence
  ) select template_id, item ->> 'slotKey', (item ->> 'matchNumber')::smallint,
    item ->> 'side', (item ->> 'bracketOrder')::smallint,
    item ->> 'sourceKind', nullif(item ->> 'sourceGroupId', '')::uuid,
    nullif(item ->> 'sourcePosition', '')::smallint,
    nullif(item ->> 'sourceExtraRank', '')::smallint,
    nullif(item ->> 'resolvedEntryId', '')::uuid,
    case when item ->> 'sourceKind' = 'BYE' then 'BYE' else 'RESOLVED' end,
    item, nextval('private.pachanga_competition_sequence')
  from jsonb_array_elements(slot_snapshot) slots(item);
  update public.pachanga_tournament_group_stage_states states set
    current_bracket_template_id = template_id,
    revision = states.revision + 1, server_sequence = target_server_sequence,
    updated_by = target_actor_id, updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object(
      'bracketTemplateId', template_id,
      'bracketTemplateStatus', 'DRAFT',
      'bracketTemplateChecksum', checksum_value,
      'bracketSize', bracket_size_value,
      'byeCount', bye_count
    );
end;
$$;

create or replace function private.pachanga_tournament_knockout_round_authority_v1(
  target_bracket_id uuid,
  target_round_order integer,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare schedule_plan public.pachanga_competition_schedule_plans%rowtype;
declare schedule_revision public.pachanga_competition_schedule_revisions%rowtype;
declare authority_plan_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_bracket_id, 'r4b-schedule-plan'
);
declare authority_revision_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_bracket_id, 'r4b-schedule-revision-v1'
);
declare target_round_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_bracket_id, 'r4b-round:' || target_round_order::text
);
declare round_index integer;
declare round_label text;
declare authority_checksum text;
begin
  if target_bracket_id is null or target_actor_id is null
     or target_round_order is null or target_round_order < 1 then
    raise exception 'TOURNAMENT_KNOCKOUT_ROUND_AUTHORITY_INVALID' using errcode = '22023';
  end if;
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = target_bracket_id for update;
  if not found or target_round_order > bracket_row.round_count then
    raise exception 'TOURNAMENT_KNOCKOUT_ROUND_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into schedule_plan
  from public.pachanga_competition_schedule_plans plans
  where plans.id = authority_plan_id;
  if not found then
    authority_checksum := private.pachanga_tournament_json_checksum_v1(
      jsonb_build_object(
        'kind', 'TournamentKnockoutRoundAuthority',
        'bracketId', bracket_row.id,
        'bracketRevisionId', bracket_row.current_revision_id,
        'competitionId', bracket_row.competition_id,
        'stageId', bracket_row.knockout_stage_id,
        'ruleRevisionId', bracket_row.rule_revision_id,
        'bracketSize', bracket_row.bracket_size,
        'roundCount', bracket_row.round_count
      )
    );
    insert into public.pachanga_competition_schedule_plans(
      id, competition_id, edition_id, category_id, stage_id, division_id,
      competition_group_id, rule_revision_id, engine_version, legs,
      entry_count, status, current_revision_id, revision, server_sequence,
      created_by
    ) values (
      authority_plan_id, bracket_row.competition_id, bracket_row.edition_id,
      bracket_row.category_id, bracket_row.knockout_stage_id, null, null,
      bracket_row.rule_revision_id, 'tournament-knockout-v1', 1,
      bracket_row.bracket_size, 'draft', null, 1, target_server_sequence,
      target_actor_id
    );
    insert into public.pachanga_competition_schedule_revisions(
      id, schedule_plan_id, version, revision_kind, status, engine_version,
      seed, input_checksum, rule_revision_id, entry_snapshot_checksum,
      slot_snapshot_checksum, constraint_snapshot_checksum,
      preference_snapshot_checksum, entry_order, quality_score,
      validation_status, generated_by, generated_at, published_by,
      published_at, revision, server_sequence
    ) values (
      authority_revision_id, authority_plan_id, 1, 'generated', 'published',
      'tournament-knockout-v1', 'r6c-' || bracket_row.id::text,
      authority_checksum, bracket_row.rule_revision_id, authority_checksum,
      authority_checksum, authority_checksum, authority_checksum, '[]'::jsonb,
      100, 'VALID', target_actor_id, clock_timestamp(), target_actor_id,
      clock_timestamp(), 1, target_server_sequence
    );
    for round_index in 1..bracket_row.round_count loop
      select nodes.round_code into round_label
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.bracket_id = bracket_row.id
        and nodes.round_order = round_index
        and nodes.node_kind = 'MATCH'
      order by nodes.node_order, nodes.id limit 1;
      if round_label is null then
        raise exception 'TOURNAMENT_KNOCKOUT_ROUND_NOT_FOUND' using errcode = 'P0002';
      end if;
      insert into public.pachanga_competition_rounds(
        id, competition_id, edition_id, category_id, stage_id, division_id,
        competition_group_id, schedule_revision_id, round_number, leg_number,
        display_name, status, rule_revision_id, revision, server_sequence,
        created_by, published_at
      ) values (
        private.pachanga_tournament_knockout_entity_id_v1(
          bracket_row.id, 'r4b-round:' || round_index::text
        ), bracket_row.competition_id, bracket_row.edition_id,
        bracket_row.category_id, bracket_row.knockout_stage_id, null, null,
        authority_revision_id, round_index, 1, round_label, 'published',
        bracket_row.rule_revision_id, 1, target_server_sequence,
        target_actor_id, clock_timestamp()
      );
    end loop;
    update public.pachanga_competition_schedule_plans plans set
      status = 'published', current_revision_id = authority_revision_id,
      revision = plans.revision + 1, server_sequence = target_server_sequence,
      published_at = clock_timestamp()
    where plans.id = authority_plan_id
    returning * into schedule_plan;
  else
    select * into schedule_revision
    from public.pachanga_competition_schedule_revisions revisions
    where revisions.id = authority_revision_id;
    if schedule_plan.competition_id <> bracket_row.competition_id
       or schedule_plan.edition_id <> bracket_row.edition_id
       or schedule_plan.category_id <> bracket_row.category_id
       or schedule_plan.stage_id <> bracket_row.knockout_stage_id
       or schedule_plan.rule_revision_id <> bracket_row.rule_revision_id
       or schedule_plan.engine_version <> 'tournament-knockout-v1'
       or schedule_plan.status <> 'published'
       or schedule_plan.current_revision_id <> authority_revision_id
       or schedule_revision.status <> 'published'
       or schedule_revision.engine_version <> 'tournament-knockout-v1' then
      raise exception 'TOURNAMENT_KNOCKOUT_ROUND_AUTHORITY_STALE' using errcode = 'PT409';
    end if;
  end if;
  if not exists (
    select 1 from public.pachanga_competition_rounds rounds
    where rounds.id = target_round_id
      and rounds.schedule_revision_id = authority_revision_id
      and rounds.round_number = target_round_order
      and rounds.status in ('published', 'in_progress', 'completed', 'locked')
  ) then
    raise exception 'TOURNAMENT_KNOCKOUT_ROUND_AUTHORITY_STALE' using errcode = 'PT409';
  end if;
  return target_round_id;
end;
$$;

create or replace function private.pachanga_tournament_knockout_current_reservation_v1(
  target_node_id uuid
)
returns public.pachanga_tournament_bracket_fixture_reservations
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select reservations
  from public.pachanga_tournament_bracket_fixture_reservations reservations
  where reservations.bracket_node_id = target_node_id
  order by reservations.reservation_revision desc,
    reservations.server_sequence desc, reservations.id desc
  limit 1;
$$;

create or replace function private.pachanga_tournament_knockout_reserve_slot_v1(
  target_node_id uuid,
  target_starts_at timestamptz,
  target_ends_at timestamptz,
  target_timezone text,
  target_venue_id uuid,
  target_venue_label text,
  target_resource_key text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare current_reservation public.pachanga_tournament_bracket_fixture_reservations%rowtype;
declare replay_reservation public.pachanga_tournament_bracket_fixture_reservations%rowtype;
declare schedule_slot_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'schedule-slot'
);
declare reservation_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'fixture-reservation'
);
declare next_reservation_revision integer;
declare reservation_snapshot jsonb;
declare checksum_value text;
begin
  if target_operation_id is null or target_actor_id is null
     or target_starts_at is null or target_ends_at is null
     or target_ends_at <= target_starts_at
     or length(trim(coalesce(target_timezone, ''))) not between 3 and 80
     or (target_venue_label is not null
       and length(trim(target_venue_label)) not between 1 and 160)
     or (target_resource_key is not null
       and length(trim(target_resource_key)) not between 1 and 160) then
    raise exception 'TOURNAMENT_KNOCKOUT_RESERVATION_INVALID' using errcode = '22023';
  end if;
  select * into replay_reservation
  from public.pachanga_tournament_bracket_fixture_reservations reservations
  where reservations.operation_id = target_operation_id;
  if found then return replay_reservation.id; end if;
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id for update;
  if not found then
    raise exception 'TOURNAMENT_BRACKET_NODE_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = node_row.bracket_id for update;
  if bracket_row.status not in ('active', 'administrative_review')
     or node_row.status in (
       'in_progress', 'result_pending', 'official', 'advanced', 'cancelled',
       'invalidated', 'administrative_review'
     ) or node_row.canonical_match_id is not null then
    raise exception 'TOURNAMENT_KNOCKOUT_RESERVATION_NOT_ALLOWED' using errcode = 'PT409';
  end if;
  select * into current_reservation
  from private.pachanga_tournament_knockout_current_reservation_v1(node_row.id);
  next_reservation_revision := coalesce(current_reservation.reservation_revision, 0) + 1;
  reservation_snapshot := jsonb_build_object(
    'kind', 'BracketFixtureReservation',
    'bracketId', bracket_row.id,
    'bracketRevisionId', bracket_row.current_revision_id,
    'nodeId', node_row.id,
    'roundCode', node_row.round_code,
    'roundOrder', node_row.round_order,
    'nodeOrder', node_row.node_order,
    'startsAt', target_starts_at,
    'endsAt', target_ends_at,
    'timezone', trim(target_timezone),
    'venueId', target_venue_id,
    'venueLabel', nullif(trim(coalesce(target_venue_label, '')), ''),
    'resourceKey', nullif(trim(coalesce(target_resource_key, '')), ''),
    'reservationRevision', next_reservation_revision
  );
  checksum_value := private.pachanga_tournament_json_checksum_v1(reservation_snapshot);
  insert into public.pachanga_competition_schedule_slots(
    id, competition_id, edition_id, stage_id, division_id,
    competition_group_id, starts_at, ends_at, timezone, venue_id,
    venue_label, resource_key, status, revision, server_sequence, created_by
  ) values (
    schedule_slot_id, bracket_row.competition_id, bracket_row.edition_id,
    bracket_row.knockout_stage_id, null, null, target_starts_at, target_ends_at,
    trim(target_timezone), target_venue_id,
    nullif(trim(coalesce(target_venue_label, '')), ''),
    nullif(trim(coalesce(target_resource_key, '')), ''),
    'available', 1, target_server_sequence, target_actor_id
  );
  insert into public.pachanga_tournament_bracket_fixture_reservations(
    id, bracket_id, bracket_revision_id, bracket_node_id,
    reservation_revision, supersedes_reservation_id, schedule_slot_id,
    status, reservation_snapshot, checksum, operation_id, created_by,
    server_sequence
  ) values (
    reservation_id, bracket_row.id, bracket_row.current_revision_id,
    node_row.id, next_reservation_revision, current_reservation.id,
    schedule_slot_id, 'ACTIVE', reservation_snapshot, checksum_value,
    target_operation_id, target_actor_id, target_server_sequence
  );
  perform private.pachanga_tournament_knockout_resolve_node_v1(
    node_row.id,
    private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id, 'resolve-after-reservation'
    ),
    target_actor_id, nextval('private.pachanga_competition_sequence')
  );
  perform private.pachanga_tournament_knockout_record_node_revision_v1(
    node_row.id, 'RESERVATION', target_operation_id, target_actor_id,
    target_server_sequence
  );
  return reservation_id;
end;
$$;

create or replace function private.pachanga_tournament_knockout_generate_match_v1(
  target_node_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare reservation_row public.pachanga_tournament_bracket_fixture_reservations%rowtype;
declare schedule_slot public.pachanga_competition_schedule_slots%rowtype;
declare generated_canonical_match_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'canonical-match'
);
declare generated_binding_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'canonical-binding'
);
declare generated_context_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'competition-context'
);
declare coordination_round_id uuid;
declare source_id_value text;
begin
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id for update;
  if not found then
    raise exception 'TOURNAMENT_BRACKET_NODE_NOT_FOUND' using errcode = 'P0002';
  end if;
  if node_row.canonical_match_id is not null then
    return jsonb_build_object(
      'nodeId', node_row.id,
      'canonicalMatchId', node_row.canonical_match_id,
      'matchContextId', (
        select contexts.id
        from public.pachanga_competition_match_contexts contexts
        where contexts.canonical_match_id = node_row.canonical_match_id
          and contexts.status <> 'retired'
        order by contexts.server_sequence desc, contexts.id desc limit 1
      ),
      'replay', true
    );
  end if;
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = node_row.bracket_id for update;
  select * into reservation_row
  from private.pachanga_tournament_knockout_current_reservation_v1(node_row.id);
  if bracket_row.status not in ('active', 'administrative_review')
     or node_row.status not in ('ready', 'scheduled')
     or node_row.home_entry_id is null or node_row.away_entry_id is null
     or node_row.home_entry_id = node_row.away_entry_id
     or reservation_row.id is null or reservation_row.status <> 'ACTIVE' then
    raise exception 'TOURNAMENT_KNOCKOUT_MATCH_NOT_READY' using errcode = 'PT409';
  end if;
  select * into schedule_slot
  from public.pachanga_competition_schedule_slots slots
  where slots.id = reservation_row.schedule_slot_id for update;
  if not found or schedule_slot.status not in ('available', 'assigned')
     or schedule_slot.competition_id <> bracket_row.competition_id
     or schedule_slot.edition_id <> bracket_row.edition_id
     or schedule_slot.stage_id <> bracket_row.knockout_stage_id then
    raise exception 'TOURNAMENT_KNOCKOUT_RESERVATION_STALE' using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from public.pachanga_tournament_bracket_nodes other_nodes
    where other_nodes.bracket_id = node_row.bracket_id
      and other_nodes.id <> node_row.id
      and other_nodes.canonical_match_id is not null
      and other_nodes.status not in ('cancelled', 'invalidated')
      and other_nodes.round_code = node_row.round_code
      and other_nodes.node_order = node_row.node_order
  ) then
    raise exception 'TOURNAMENT_KNOCKOUT_MATCH_CARDINALITY_VIOLATION' using errcode = '23505';
  end if;
  coordination_round_id := private.pachanga_tournament_knockout_round_authority_v1(
    bracket_row.id, node_row.round_order, target_actor_id, target_server_sequence
  );
  source_id_value := 'tournament-knockout:' || node_row.id::text
    || ':node-revision:' || node_row.revision::text;
  perform set_config('pachangas.r6c_match_publish', 'on', true);
  insert into public.pachanga_canonical_matches(
    id, status, revision, server_sequence, created_by
  ) values (
    generated_canonical_match_id, 'active', 1, target_server_sequence, target_actor_id
  );
  insert into public.pachanga_canonical_match_bindings(
    id, canonical_match_id, source_kind, source_group_id, source_id,
    relation_kind, binding_status, revision, server_sequence, created_by
  ) values (
    generated_binding_id, generated_canonical_match_id, 'competition_generated', null,
    source_id_value, 'authoritative_source', 'active', 1,
    target_server_sequence, target_actor_id
  );
  update public.pachanga_tournament_bracket_nodes nodes set
    canonical_match_id = generated_canonical_match_id,
    status = 'match_created',
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where nodes.id = node_row.id;
  insert into public.pachanga_competition_match_contexts(
    id, canonical_match_id, competition_id, edition_id, stage_id,
    division_id, competition_group_id, rule_revision_id, status, revision,
    server_sequence, created_by, category_id, round_id, schedule_item_id,
    home_entry_id, away_entry_id, slot_id, scheduled_start, scheduled_end,
    timezone, venue_id, venue_label, venue_status, source_kind
  ) values (
    generated_context_id, generated_canonical_match_id, bracket_row.competition_id,
    bracket_row.edition_id, bracket_row.knockout_stage_id, null, null,
    bracket_row.rule_revision_id, 'scheduled', 1, target_server_sequence,
    target_actor_id, bracket_row.category_id, coordination_round_id, null,
    node_row.home_entry_id, node_row.away_entry_id, schedule_slot.id,
    schedule_slot.starts_at, schedule_slot.ends_at, schedule_slot.timezone,
    schedule_slot.venue_id, schedule_slot.venue_label,
    case when schedule_slot.venue_id is not null then 'CONFIRMED'
      when schedule_slot.venue_label is not null then 'LABEL' else 'TBD' end,
    'COMPETITION_GENERATED'
  );
  if schedule_slot.status = 'available' then
    update public.pachanga_competition_schedule_slots slots set
      status = 'assigned', revision = slots.revision + 1,
      server_sequence = target_server_sequence,
      updated_at = clock_timestamp()
    where slots.id = schedule_slot.id;
  end if;
  perform private.pachanga_tournament_knockout_record_node_revision_v1(
    node_row.id, 'MATCH_GENERATION', target_operation_id, target_actor_id,
    target_server_sequence
  );
  return jsonb_build_object(
    'nodeId', node_row.id,
    'canonicalMatchId', generated_canonical_match_id,
    'canonicalBindingId', generated_binding_id,
    'matchContextId', generated_context_id,
    'scheduleSlotId', schedule_slot.id,
    'replay', false
  );
end;
$$;

create or replace function private.pachanga_tournament_knockout_replace_downstream_v1(
  target_node_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare old_context public.pachanga_competition_match_contexts%rowtype;
declare old_binding public.pachanga_canonical_match_bindings%rowtype;
declare replacement jsonb;
begin
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id for update;
  if not found or node_row.canonical_match_id is null then
    raise exception 'TOURNAMENT_KNOCKOUT_DOWNSTREAM_MATCH_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into old_context
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = node_row.canonical_match_id
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1 for update;
  if not found or old_context.status not in ('scheduled', 'ready') then
    raise exception 'DOWNSTREAM_MATCH_ALREADY_STARTED' using errcode = 'PT409';
  end if;
  if exists (
    select 1 from public.pachanga_competition_match_sheets sheets
    where sheets.competition_match_context_id = old_context.id
      and (sheets.current_sporting_result_id is not null
        or sheets.active_official_decision_id is not null)
  ) then
    raise exception 'DOWNSTREAM_MATCH_ALREADY_STARTED' using errcode = 'PT409';
  end if;
  select * into old_binding
  from public.pachanga_canonical_match_bindings bindings
  where bindings.canonical_match_id = node_row.canonical_match_id
    and bindings.source_kind = 'competition_generated'
    and bindings.binding_status = 'active'
  order by bindings.server_sequence desc, bindings.id desc limit 1 for update;
  update public.pachanga_competition_match_contexts contexts set
    status = 'retired', revision = contexts.revision + 1,
    server_sequence = target_server_sequence, updated_at = clock_timestamp()
  where contexts.id = old_context.id;
  update public.pachanga_canonical_match_bindings bindings set
    binding_status = 'retired', revision = bindings.revision + 1,
    server_sequence = target_server_sequence,
    review_reason = 'R6C downstream participant correction',
    updated_at = clock_timestamp()
  where bindings.id = old_binding.id;
  update public.pachanga_canonical_matches matches set
    status = 'retired', revision = matches.revision + 1,
    server_sequence = target_server_sequence, updated_at = clock_timestamp()
  where matches.id = node_row.canonical_match_id;
  update public.pachanga_tournament_bracket_nodes nodes set
    canonical_match_id = null,
    status = case when nodes.home_entry_id is not null and nodes.away_entry_id is not null
      then 'scheduled' else 'awaiting_sources' end,
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where nodes.id = node_row.id;
  perform private.pachanga_tournament_knockout_record_node_revision_v1(
    node_row.id, 'REPLACEMENT', target_operation_id, target_actor_id,
    target_server_sequence
  );
  replacement := private.pachanga_tournament_knockout_generate_match_v1(
    node_row.id,
    private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id, 'replacement-canonical-match'
    ),
    target_actor_id, nextval('private.pachanga_competition_sequence')
  );
  return replacement || jsonb_build_object(
    'supersededCanonicalMatchId', old_context.canonical_match_id,
    'supersededMatchContextId', old_context.id
  );
end;
$$;

-- R4C/R4D keep one context loader. Preserve their proven group-stage branch
-- and add only the reservation-backed knockout relation.
create or replace function private.pachanga_league_match_context_v1(target_context_id uuid)
returns public.pachanga_competition_match_contexts
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_competition_match_contexts%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare item_status text;
declare source_kind_value text;
declare is_knockout boolean := false;
begin
  select * into selected
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id;
  if not found then
    raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = selected.competition_id;
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.canonical_match_id = selected.canonical_match_id;
  is_knockout := found;
  if competition_row.competition_type = 'TOURNAMENT' then
    if competition_row.product_key <> 'TOURNAMENT_PRIVATE_BETA_V1' then
      raise exception 'TOURNAMENT_GROUP_MATCH_CONTEXT_REQUIRED' using errcode = '22023';
    end if;
    if is_knockout then
      select * into bracket_row
      from public.pachanga_tournament_brackets brackets
      where brackets.id = node_row.bracket_id;
      if bracket_row.status not in ('active', 'administrative_review', 'completed', 'locked')
         or selected.stage_id <> bracket_row.knockout_stage_id
         or selected.category_id <> bracket_row.category_id
         or selected.rule_revision_id <> bracket_row.rule_revision_id
         or selected.home_entry_id <> node_row.home_entry_id
         or selected.away_entry_id <> node_row.away_entry_id
         or selected.round_id is null or selected.schedule_item_id is not null
         or not exists (
           select 1
           from public.pachanga_competition_rounds rounds
           join public.pachanga_competition_schedule_revisions revisions
             on revisions.id = rounds.schedule_revision_id
           join public.pachanga_competition_schedule_plans plans
             on plans.id = revisions.schedule_plan_id
           where rounds.id = selected.round_id
             and rounds.round_number = node_row.round_order
             and rounds.competition_id = bracket_row.competition_id
             and rounds.edition_id = bracket_row.edition_id
             and rounds.category_id = bracket_row.category_id
             and rounds.stage_id = bracket_row.knockout_stage_id
             and rounds.rule_revision_id = bracket_row.rule_revision_id
             and rounds.status in ('published', 'in_progress', 'completed', 'locked')
             and revisions.id = private.pachanga_tournament_knockout_entity_id_v1(
               bracket_row.id, 'r4b-schedule-revision-v1'
             )
             and revisions.status = 'published'
             and revisions.engine_version = 'tournament-knockout-v1'
             and plans.id = private.pachanga_tournament_knockout_entity_id_v1(
               bracket_row.id, 'r4b-schedule-plan'
             )
             and plans.current_revision_id = revisions.id
             and plans.status = 'published'
             and plans.engine_version = 'tournament-knockout-v1'
         )
         or not exists (
           select 1
           from public.pachanga_tournament_bracket_fixture_reservations reservations
           where reservations.bracket_node_id = node_row.id
             and reservations.schedule_slot_id = selected.slot_id
             and reservations.status = 'ACTIVE'
             and not exists (
               select 1
               from public.pachanga_tournament_bracket_fixture_reservations newer
               where newer.bracket_node_id = reservations.bracket_node_id
                 and newer.reservation_revision > reservations.reservation_revision
             )
         ) then
        raise exception 'TOURNAMENT_KNOCKOUT_MATCH_CONTEXT_REQUIRED' using errcode = '22023';
      end if;
    elsif not exists (
      select 1
      from public.pachanga_tournament_group_schedule_plans mappings
      join public.pachanga_tournament_group_stage_states states
        on states.id = mappings.group_stage_state_id
      join public.pachanga_competition_stages stages on stages.id = states.stage_id
      where mappings.schedule_plan_id = (
        select revisions.schedule_plan_id
        from public.pachanga_competition_schedule_items items
        join public.pachanga_competition_schedule_revisions revisions
          on revisions.id = items.schedule_revision_id
        where items.id = selected.schedule_item_id
      )
        and mappings.status = 'published'
        and states.status in ('schedule_published', 'active', 'complete')
        and stages.stage_type = 'GROUP_STAGE'
        and states.competition_id = selected.competition_id
        and states.stage_id = selected.stage_id
        and mappings.competition_group_id = selected.competition_group_id
        and states.rule_revision_id = selected.rule_revision_id
    ) then
      raise exception 'TOURNAMENT_GROUP_MATCH_CONTEXT_REQUIRED' using errcode = '22023';
    end if;
  elsif competition_row.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if selected.source_kind <> 'COMPETITION_GENERATED' then
    raise exception 'R4C_REQUIRES_COMPETITION_GENERATED_CANONICAL_MATCH' using errcode = '22023';
  end if;
  if is_knockout then
    if selected.status = 'retired' then
      raise exception 'R4C_FIXTURE_NOT_PUBLISHED' using errcode = '22023';
    end if;
  else
    if selected.schedule_item_id is null then
      raise exception 'R4C_REQUIRES_COMPETITION_GENERATED_CANONICAL_MATCH' using errcode = '22023';
    end if;
    select items.status into item_status
    from public.pachanga_competition_schedule_items items
    where items.id = selected.schedule_item_id
      and items.canonical_match_id = selected.canonical_match_id
      and items.competition_match_context_id = selected.id;
    if item_status <> 'published' then
      raise exception 'R4C_FIXTURE_NOT_PUBLISHED' using errcode = '22023';
    end if;
  end if;
  select bindings.source_kind into source_kind_value
  from public.pachanga_canonical_match_bindings bindings
  where bindings.canonical_match_id = selected.canonical_match_id
    and bindings.binding_status = 'active'
    and bindings.source_kind = 'competition_generated'
  order by bindings.server_sequence desc, bindings.id desc limit 1;
  if source_kind_value is null then
    raise exception 'R4C_CANONICAL_BINDING_NOT_FOUND' using errcode = '22023';
  end if;
  if selected.home_entry_id is null or selected.away_entry_id is null
     or selected.rule_revision_id is null or selected.round_id is null then
    raise exception 'R4C_MATCH_CONTEXT_INCOMPLETE' using errcode = '22023';
  end if;
  return selected;
end;
$$;

-- R5 originally resolved sporting order exclusively through published R4B
-- ScheduleItems. Knockout fixtures deliberately use the reservation-backed
-- canonical context instead, so expose both authorities through one private,
-- deterministic projection without creating a second schedule model.
create or replace function private.pachanga_competition_player_sanction_applies_v1(
  target_competition_id uuid,
  target_player_profile_id uuid,
  target_canonical_match_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with fixture_candidates as (
    select rounds.competition_id, items.canonical_match_id,
      items.scheduled_start, rounds.round_number, rounds.stage_id,
      items.server_sequence, items.id as stable_id, 1 as authority_priority
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.status = 'published'

    union all

    select contexts.competition_id, contexts.canonical_match_id,
      contexts.scheduled_start, rounds.round_number, rounds.stage_id,
      contexts.server_sequence, contexts.id as stable_id, 2 as authority_priority
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_tournament_bracket_nodes nodes
      on nodes.canonical_match_id = contexts.canonical_match_id
    join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
    join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
    join public.pachanga_competition_schedule_revisions revisions
      on revisions.id = rounds.schedule_revision_id
    join public.pachanga_competition_schedule_plans plans
      on plans.id = revisions.schedule_plan_id
    join public.pachanga_canonical_matches matches
      on matches.id = contexts.canonical_match_id
    where contexts.source_kind = 'COMPETITION_GENERATED'
      and contexts.schedule_item_id is null
      and contexts.status <> 'retired'
      and matches.status <> 'retired'
      and brackets.status in ('active', 'administrative_review', 'completed', 'locked')
      and contexts.competition_id = brackets.competition_id
      and contexts.edition_id = brackets.edition_id
      and contexts.category_id = brackets.category_id
      and contexts.stage_id = brackets.knockout_stage_id
      and contexts.rule_revision_id = brackets.rule_revision_id
      and contexts.home_entry_id = nodes.home_entry_id
      and contexts.away_entry_id = nodes.away_entry_id
      and rounds.round_number = nodes.round_order
      and revisions.id = private.pachanga_tournament_knockout_entity_id_v1(
        brackets.id, 'r4b-schedule-revision-v1'
      )
      and revisions.status = 'published'
      and revisions.engine_version = 'tournament-knockout-v1'
      and plans.id = private.pachanga_tournament_knockout_entity_id_v1(
        brackets.id, 'r4b-schedule-plan'
      )
      and plans.current_revision_id = revisions.id
      and plans.status = 'published'
      and plans.engine_version = 'tournament-knockout-v1'
      and exists (
        select 1
        from public.pachanga_tournament_bracket_fixture_reservations reservations
        where reservations.bracket_node_id = nodes.id
          and reservations.schedule_slot_id = contexts.slot_id
          and reservations.status = 'ACTIVE'
          and not exists (
            select 1
            from public.pachanga_tournament_bracket_fixture_reservations newer
            where newer.bracket_node_id = reservations.bracket_node_id
              and newer.reservation_revision > reservations.reservation_revision
          )
      )
  ), fixtures as (
    select distinct on (candidates.competition_id, candidates.canonical_match_id)
      candidates.competition_id, candidates.canonical_match_id,
      candidates.scheduled_start, candidates.round_number, candidates.stage_id
    from fixture_candidates candidates
    order by candidates.competition_id, candidates.canonical_match_id,
      candidates.authority_priority, candidates.server_sequence desc,
      candidates.stable_id desc
  ), target_fixture as (
    select fixtures.*
    from fixtures
    where fixtures.competition_id = target_competition_id
      and fixtures.canonical_match_id = target_canonical_match_id
  )
  select exists (
    select 1
    from public.pachanga_competition_sanctions sanctions
    left join public.pachanga_competition_disciplinary_events source_events
      on source_events.id = sanctions.source_event_id
    left join fixtures source_fixture
      on source_fixture.competition_id = sanctions.competition_id
     and source_fixture.canonical_match_id = source_events.canonical_match_id
    cross join target_fixture target
    where sanctions.competition_id = target_competition_id
      and sanctions.target_type = 'PLAYER'
      and sanctions.player_profile_id = target_player_profile_id
      and sanctions.status in ('active', 'provisional')
      and coalesce(sanctions.remaining_units, 0) > 0
      and not sanctions.suspensive_hold
      and source_events.canonical_match_id <> target_canonical_match_id
      and (
        sanctions.unit_type = 'COMPETITION_EXPULSION'
        or (sanctions.unit_type = 'STAGE'
          and source_fixture.stage_id = target.stage_id)
        or coalesce(target.round_number > source_fixture.round_number, false)
        or coalesce(target.scheduled_start > source_fixture.scheduled_start, false)
      )
  );
$$;

-- Wave 4 addresses generated fixtures by ScheduleItem ID. R6C keeps that
-- contract unchanged for leagues and group stages, while a knockout caller
-- uses the already-public CanonicalMatch ID as a narrow server-resolved handle.
alter function private.pachanga_referee_match_snapshot_v1(text, uuid, text)
  rename to pachanga_referee_match_snapshot_wave4_v1;

create or replace function private.pachanga_referee_match_snapshot_v1(
  target_source_kind text,
  target_source_group_id uuid,
  target_source_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := lower(trim(coalesce(target_source_kind, '')));
declare target_match_id uuid;
declare binding public.pachanga_canonical_match_bindings%rowtype;
declare canonical public.pachanga_canonical_matches%rowtype;
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare reservation_row public.pachanga_tournament_bracket_fixture_reservations%rowtype;
declare schedule_slot public.pachanga_competition_schedule_slots%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare fixture_change public.pachanga_competition_fixture_changes%rowtype;
declare fixture_revision public.pachanga_competition_fixture_change_revisions%rowtype;
declare rule_revision public.pachanga_competition_rule_revisions%rowtype;
declare home_team_id uuid;
declare away_team_id uuid;
declare effective_start timestamptz;
declare effective_end timestamptz;
declare effective_timezone text;
declare effective_venue_id uuid;
declare effective_venue_label text;
declare effective_venue_status text;
declare schedule_revision bigint;
begin
  if normalized_kind <> 'competition_generated'
     or target_source_group_id is not null
     or target_source_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return private.pachanga_referee_match_snapshot_wave4_v1(
      target_source_kind, target_source_group_id, target_source_id
    );
  end if;

  target_match_id := target_source_id::uuid;
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.canonical_match_id = target_match_id;
  if not found then
    return private.pachanga_referee_match_snapshot_wave4_v1(
      target_source_kind, target_source_group_id, target_source_id
    );
  end if;

  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = node_row.bracket_id;
  if not found or bracket_row.status not in (
    'active', 'administrative_review', 'completed', 'locked'
  ) then
    raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = 'P0002';
  end if;
  select * into binding
  from public.pachanga_canonical_match_bindings bindings
  where bindings.canonical_match_id = target_match_id
    and bindings.source_kind = 'competition_generated'
    and bindings.source_group_id is null
    and bindings.source_id like 'tournament-knockout:' || node_row.id::text || ':%'
    and bindings.binding_status = 'active'
  order by bindings.server_sequence desc, bindings.id desc
  limit 1;
  if not found then
    raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = 'P0002';
  end if;
  select * into canonical
  from public.pachanga_canonical_matches matches
  where matches.id = target_match_id and matches.status = 'active';
  if not found then
    raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = 'P0002';
  end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = target_match_id
    and contexts.schedule_item_id is null
    and contexts.status not in ('retired', 'cancelled')
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  if not found then
    raise exception 'REFEREE_COMPETITION_MATCH_CONTEXT_REQUIRED' using errcode = 'P0002';
  end if;
  select * into context_row
  from private.pachanga_league_match_context_v1(context_row.id);

  select * into reservation_row
  from private.pachanga_tournament_knockout_current_reservation_v1(node_row.id);
  if not found or reservation_row.status <> 'ACTIVE'
     or reservation_row.schedule_slot_id <> context_row.slot_id then
    raise exception 'REFEREE_ASSIGNMENT_MATCH_NOT_PUBLISHED' using errcode = '42501';
  end if;
  select * into schedule_slot
  from public.pachanga_competition_schedule_slots slots
  where slots.id = reservation_row.schedule_slot_id
    and slots.status = 'assigned';
  if not found then
    raise exception 'REFEREE_ASSIGNMENT_MATCH_NOT_PUBLISHED' using errcode = '42501';
  end if;

  select * into fixture_change
  from public.pachanga_competition_fixture_changes changes
  where changes.competition_match_context_id = context_row.id
    and changes.status = 'active'
  order by changes.server_sequence desc, changes.id desc
  limit 1;
  if found and fixture_change.current_revision_id is not null then
    select * into fixture_revision
    from public.pachanga_competition_fixture_change_revisions revisions
    where revisions.id = fixture_change.current_revision_id;
  end if;
  select * into rule_revision
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id = context_row.rule_revision_id;
  select entries.team_id into home_team_id
  from public.pachanga_competition_entries entries
  where entries.id = context_row.home_entry_id;
  select entries.team_id into away_team_id
  from public.pachanga_competition_entries entries
  where entries.id = context_row.away_entry_id;

  effective_start := coalesce(
    fixture_revision.effective_scheduled_start,
    context_row.scheduled_start, schedule_slot.starts_at
  );
  effective_end := coalesce(
    fixture_revision.effective_scheduled_end,
    context_row.scheduled_end, schedule_slot.ends_at
  );
  effective_timezone := coalesce(
    fixture_revision.effective_timezone,
    context_row.timezone, schedule_slot.timezone, 'Europe/Madrid'
  );
  effective_venue_id := coalesce(
    fixture_revision.effective_venue_id,
    context_row.venue_id, schedule_slot.venue_id
  );
  effective_venue_label := coalesce(
    fixture_revision.effective_venue_label,
    context_row.venue_label, schedule_slot.venue_label
  );
  effective_venue_status := coalesce(
    fixture_revision.effective_venue_status,
    context_row.venue_status,
    case when schedule_slot.venue_id is not null then 'CONFIRMED'
      when schedule_slot.venue_label is not null then 'LABEL' else 'TBD' end
  );
  schedule_revision := greatest(
    reservation_row.server_sequence,
    schedule_slot.server_sequence,
    context_row.server_sequence,
    coalesce(fixture_revision.server_sequence, 0)
  );
  if effective_start is null or effective_end is null
     or effective_end <= effective_start then
    raise exception 'REFEREE_MATCH_SCHEDULE_REQUIRED' using errcode = '22023';
  end if;

  return jsonb_build_object(
    'canonicalMatchId', canonical.id,
    'canonicalRevision', canonical.revision,
    'canonicalBindingId', binding.id,
    'competitionMatchContextId', context_row.id,
    'sourceKind', 'competition_generated',
    'sourceGroupId', null,
    'sourceId', target_source_id,
    'scheduledStart', context_row.scheduled_start,
    'scheduledEnd', context_row.scheduled_end,
    'originalScheduledStart', context_row.scheduled_start,
    'originalScheduledEnd', context_row.scheduled_end,
    'timezone', coalesce(context_row.timezone, effective_timezone),
    'scheduleRevision', schedule_revision,
    'effectiveScheduledStart', effective_start,
    'effectiveScheduledEnd', effective_end,
    'effectiveTimezone', effective_timezone,
    'effectiveScheduleRevision', schedule_revision,
    'modality', private.pachanga_referee_modality_v1(
      rule_revision.rule_document #>> '{format,modality}'
    ),
    'venueId', effective_venue_id,
    'venueLabel', effective_venue_label,
    'venueStatus', effective_venue_status,
    'concluded', context_row.status in ('played', 'result_pending', 'official'),
    'assignable', context_row.status in ('scheduled', 'ready'),
    'published', true,
    'participantGroupIds', jsonb_build_array(home_team_id, away_team_id),
    'competitionId', context_row.competition_id
  );
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_knockout_round_authority_v1(uuid,integer,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_current_reservation_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_knockout_reserve_slot_v1(uuid,timestamp with time zone,timestamp with time zone,text,uuid,text,text,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_generate_match_v1(uuid,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_replace_downstream_v1(uuid,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_league_match_context_v1(uuid)'::regprocedure,
    'private.pachanga_competition_player_sanction_applies_v1(uuid,uuid,uuid)'::regprocedure,
    'private.pachanga_referee_match_snapshot_v1(text,uuid,text)'::regprocedure,
    'private.pachanga_referee_match_snapshot_wave4_v1(text,uuid,text)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

grant execute on function private.pachanga_tournament_knockout_generate_match_v1(
  uuid,uuid,uuid,bigint
) to service_role;

comment on function private.pachanga_tournament_knockout_generate_match_v1(
  uuid,uuid,uuid,bigint
) is 'Creates exactly one reservation-backed CanonicalMatch for an operational R6C node. BYE nodes never reach this function.';

revoke all on function private.pachanga_tournament_bracket_template_create_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_knockout_round_code_v1(
  target_bracket_size integer,
  target_round_order integer
)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare remaining integer := target_bracket_size / (2 ^ target_round_order);
begin
  if remaining = 1 then return 'FINAL'; end if;
  if remaining = 2 then return 'SEMIFINAL'; end if;
  if remaining = 4 then return 'QUARTERFINAL'; end if;
  return 'ROUND_OF_' || (remaining * 2)::text;
end;
$$;

-- The canonical R4B relation trigger still validates every normal generated
-- context. Knockout contexts are the single narrow exception: their schedule
-- authority is the active BracketFixtureReservation rather than a round-robin
-- ScheduleItem.
create or replace function private.pachanga_tournament_knockout_context_relation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare node_revision public.pachanga_tournament_bracket_node_revisions%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare historical_context boolean := false;
declare relation_home_entry_id uuid;
declare relation_away_entry_id uuid;
begin
  -- Constraint triggers are deferred; validate the final committed row rather
  -- than an intermediate INSERT/UPDATE image captured earlier in the transaction.
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = new.id;
  if not found then return new; end if;
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.canonical_match_id = context_row.canonical_match_id;
  if not found then
    select * into node_revision
    from public.pachanga_tournament_bracket_node_revisions revisions
    where revisions.canonical_match_id = context_row.canonical_match_id
      and revisions.home_entry_id = context_row.home_entry_id
      and revisions.away_entry_id = context_row.away_entry_id
    order by revisions.server_sequence desc, revisions.id desc
    limit 1;
    if found then
      select * into node_row
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.id = node_revision.bracket_node_id;
      historical_context := true;
    end if;
  end if;
  if found then
    select * into bracket_row from public.pachanga_tournament_brackets brackets
    where brackets.id = node_row.bracket_id;
    relation_home_entry_id := case when historical_context
      then node_revision.home_entry_id else node_row.home_entry_id end;
    relation_away_entry_id := case when historical_context
      then node_revision.away_entry_id else node_row.away_entry_id end;
    if context_row.source_kind <> 'COMPETITION_GENERATED'
       or context_row.competition_id <> bracket_row.competition_id
       or context_row.edition_id <> bracket_row.edition_id
       or context_row.category_id <> bracket_row.category_id
       or context_row.stage_id <> bracket_row.knockout_stage_id
       or context_row.rule_revision_id <> bracket_row.rule_revision_id
       or context_row.home_entry_id is distinct from relation_home_entry_id
       or context_row.away_entry_id is distinct from relation_away_entry_id
       or context_row.schedule_item_id is not null
       or context_row.round_id is null
       or not exists (
         select 1
         from public.pachanga_competition_rounds rounds
         join public.pachanga_competition_schedule_revisions revisions
           on revisions.id = rounds.schedule_revision_id
         join public.pachanga_competition_schedule_plans plans
           on plans.id = revisions.schedule_plan_id
         where rounds.id = context_row.round_id
           and rounds.round_number = node_row.round_order
           and rounds.competition_id = bracket_row.competition_id
           and rounds.edition_id = bracket_row.edition_id
           and rounds.category_id = bracket_row.category_id
           and rounds.stage_id = bracket_row.knockout_stage_id
           and rounds.rule_revision_id = bracket_row.rule_revision_id
           and revisions.id = private.pachanga_tournament_knockout_entity_id_v1(
             bracket_row.id, 'r4b-schedule-revision-v1'
           )
           and revisions.engine_version = 'tournament-knockout-v1'
           and plans.id = private.pachanga_tournament_knockout_entity_id_v1(
             bracket_row.id, 'r4b-schedule-plan'
           )
           and plans.current_revision_id = revisions.id
           and plans.engine_version = 'tournament-knockout-v1'
       )
       or (
         not historical_context
         and not exists (
           select 1
           from public.pachanga_tournament_bracket_fixture_reservations reservations
           where reservations.bracket_node_id = node_row.id
             and reservations.schedule_slot_id = context_row.slot_id
             and reservations.status = 'ACTIVE'
             and not exists (
               select 1
               from public.pachanga_tournament_bracket_fixture_reservations newer
               where newer.bracket_node_id = reservations.bracket_node_id
                 and newer.reservation_revision > reservations.reservation_revision
             )
         )
       )
       or (
         historical_context
         and (
           context_row.status <> 'retired'
           or not exists (
             select 1 from public.pachanga_canonical_matches matches
             where matches.id = context_row.canonical_match_id and matches.status = 'retired'
           )
           or not exists (
             select 1 from public.pachanga_canonical_match_bindings bindings
             where bindings.canonical_match_id = context_row.canonical_match_id
               and bindings.source_kind = 'competition_generated'
               and bindings.binding_status = 'retired'
           )
           or not exists (
             select 1
             from public.pachanga_tournament_bracket_fixture_reservations reservations
             where reservations.bracket_node_id = node_row.id
               and reservations.schedule_slot_id = context_row.slot_id
           )
         )
       ) then
      raise exception 'TOURNAMENT_KNOCKOUT_CONTEXT_INVALID' using errcode = '23514';
    end if;
    return new;
  end if;
  if context_row.source_kind = 'COMPETITION_GENERATED' and not exists (
    select 1
    from public.pachanga_competition_rounds rounds
    join public.pachanga_competition_schedule_items items
      on items.round_id = rounds.id
    where rounds.id = context_row.round_id
      and rounds.competition_id = context_row.competition_id
      and rounds.edition_id = context_row.edition_id
      and rounds.stage_id = context_row.stage_id
      and rounds.rule_revision_id = context_row.rule_revision_id
      and items.id = context_row.schedule_item_id
      and items.home_entry_id = context_row.home_entry_id
      and items.away_entry_id = context_row.away_entry_id
      and items.slot_id = context_row.slot_id
  ) then raise exception 'COMPETITION_GENERATED_CONTEXT_INVALID' using errcode = '23514'; end if;
  return new;
end;
$$;

drop trigger if exists validate_pachanga_generated_context_relation_v1
  on public.pachanga_competition_match_contexts;
create constraint trigger validate_pachanga_generated_context_relation_v1
after insert or update on public.pachanga_competition_match_contexts
deferrable initially deferred for each row
execute function private.pachanga_tournament_knockout_context_relation_v1();

create or replace function private.pachanga_tournament_knockout_activate_v1(
  target_competition_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare qualification_row public.pachanga_tournament_qualification_snapshots%rowtype;
declare template_row public.pachanga_tournament_bracket_templates%rowtype;
declare rule_row public.pachanga_competition_rule_revisions%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare target_bracket_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'bracket'
);
declare bracket_revision_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'bracket-revision-1'
);
declare knockout_stage_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'knockout-stage'
);
declare stage_edge_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'group-to-knockout-edge'
);
declare policy jsonb;
declare structure_snapshot jsonb;
declare checksum_value text;
declare round_count_value integer := 0;
declare size_cursor integer;
declare round_order_value integer;
declare match_count integer;
declare node_order_value integer;
declare round_code_value text;
declare node_id uuid;
declare home_source_node_id uuid;
declare away_source_node_id uuid;
declare template_slot public.pachanga_tournament_bracket_slots%rowtype;
declare slot_side text;
declare slot_id uuid;
declare slot_operation_id uuid;
declare node_operation_id uuid;
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare home_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare away_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare previous_stage_order integer;
declare transition_at timestamptz := clock_timestamp();
begin
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.competition_id = target_competition_id;
  if found then return bracket_row.id; end if;
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row
  from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  if state_row.status <> 'complete' then
    raise exception 'TOURNAMENT_GROUP_STAGE_NOT_COMPLETE' using errcode = '22023';
  end if;
  if not private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'bracket_publish'
  ) then raise exception 'TOURNAMENT_BRACKET_MANAGER_REQUIRED' using errcode = '42501'; end if;
  select * into qualification_row
  from public.pachanga_tournament_qualification_snapshots snapshots
  where snapshots.id = state_row.current_qualification_snapshot_id;
  select * into template_row
  from public.pachanga_tournament_bracket_templates templates
  where templates.id = state_row.current_bracket_template_id;
  select * into rule_row
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id = state_row.rule_revision_id;
  if qualification_row.status <> 'PUBLISHED'
     or template_row.status <> 'PUBLISHED'
     or template_row.qualification_snapshot_id <> qualification_row.id
     or template_row.rule_revision_id <> state_row.rule_revision_id
     or rule_row.status <> 'frozen'
     or not exists (
       select 1 from public.pachanga_competition_draw_plans plans
       where plans.id = state_row.draw_plan_id
         and plans.current_revision_id = state_row.draw_revision_id
         and plans.status = 'published'
     ) then raise exception 'TOURNAMENT_BRACKET_INPUT_STALE' using errcode = 'PT409'; end if;
  if exists (
    select slots.resolved_entry_id
    from public.pachanga_tournament_bracket_slots slots
    where slots.bracket_template_id = template_row.id
      and slots.resolved_entry_id is not null
    group by slots.resolved_entry_id having count(*) > 1
  ) or (select count(*) from public.pachanga_tournament_bracket_slots slots
        where slots.bracket_template_id = template_row.id) <> template_row.bracket_size
    or exists (
      select 1
      from public.pachanga_tournament_bracket_slots slots
      where slots.bracket_template_id = template_row.id
        and (
          (slots.source_kind = 'BYE' and (
            slots.status <> 'BYE' or slots.resolved_entry_id is not null
          ))
          or (slots.source_kind <> 'BYE' and (
            slots.status <> 'RESOLVED' or slots.resolved_entry_id is null
          ))
        )
    )
    or exists (
      (select slots.resolved_entry_id
       from public.pachanga_tournament_bracket_slots slots
       where slots.bracket_template_id = template_row.id
         and slots.source_kind <> 'BYE')
      except
      (select rows.entry_id
       from public.pachanga_tournament_qualification_rows rows
       where rows.qualification_snapshot_id = qualification_row.id
         and rows.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER'))
    )
    or exists (
      (select rows.entry_id
       from public.pachanga_tournament_qualification_rows rows
       where rows.qualification_snapshot_id = qualification_row.id
         and rows.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER'))
      except
      (select slots.resolved_entry_id
       from public.pachanga_tournament_bracket_slots slots
       where slots.bracket_template_id = template_row.id
         and slots.source_kind <> 'BYE')
    ) then
    raise exception 'TOURNAMENT_BRACKET_TEMPLATE_INVALID' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.pachanga_tournament_qualification_rows qualification_rows
    join public.pachanga_competition_entries entries
      on entries.id = qualification_rows.entry_id
    where qualification_rows.qualification_snapshot_id = qualification_row.id
      and qualification_rows.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
      and (
        entries.competition_id <> state_row.competition_id
        or entries.edition_id <> state_row.edition_id
        or entries.category_id <> state_row.category_id
        or entries.rule_revision_id <> state_row.rule_revision_id
        or entries.status not in ('accepted', 'active')
        or not exists (
          select 1
          from public.pachanga_competition_stage_memberships memberships
          where memberships.entry_id = entries.id
            and memberships.stage_id = state_row.stage_id
            and memberships.rule_revision_id = state_row.rule_revision_id
            and memberships.status = 'active'
        )
      )
  ) then
    raise exception 'TOURNAMENT_KNOCKOUT_QUALIFIER_MEMBERSHIP_INVALID'
      using errcode = 'PT409';
  end if;
  policy := private.pachanga_tournament_knockout_policy_v1(rule_row.id);
  size_cursor := template_row.bracket_size;
  while size_cursor > 1 loop
    round_count_value := round_count_value + 1;
    size_cursor := size_cursor / 2;
  end loop;
  select max(stages.stage_order) into previous_stage_order
  from public.pachanga_competition_stages stages
  where stages.edition_id = state_row.edition_id;
  insert into public.pachanga_competition_stages(
    id, edition_id, name, stage_type, stage_order, optional_stage, status,
    rule_revision_id, revision, server_sequence, created_by
  ) values (
    knockout_stage_id, state_row.edition_id, 'Eliminatorias', 'KNOCKOUT',
    coalesce(previous_stage_order, 0) + 1, false, 'draft', rule_row.id, 1,
    nextval('private.pachanga_competition_sequence'), target_actor_id
  );
  insert into public.pachanga_competition_stage_edges(
    id, edition_id, from_stage_id, to_stage_id, edge_order,
    transition_kind, revision, server_sequence, created_by
  ) values (
    stage_edge_id, state_row.edition_id, state_row.stage_id,
    knockout_stage_id, 0, 'structural', 1,
    nextval('private.pachanga_competition_sequence'), target_actor_id
  );
  update public.pachanga_competition_stage_memberships memberships set
    status = 'closed', valid_until = transition_at,
    revision = memberships.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = transition_at
  where memberships.stage_id = state_row.stage_id
    and memberships.status = 'active'
    and memberships.entry_id in (
      select entries.id
      from public.pachanga_competition_entries entries
      where entries.competition_id = state_row.competition_id
        and entries.edition_id = state_row.edition_id
        and entries.category_id = state_row.category_id
    );
  insert into public.pachanga_competition_stage_memberships(
    id, entry_id, stage_id, division_id, competition_group_id,
    rule_revision_id, valid_from, status, reason, revision,
    server_sequence, assigned_by, created_at, updated_at
  )
  select
    private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id,
      'knockout-stage-membership:' || qualification_rows.entry_id::text
    ),
    qualification_rows.entry_id, knockout_stage_id, null, null,
    state_row.rule_revision_id, transition_at, 'active',
    'Clasificación publicada para la fase eliminatoria', 1,
    nextval('private.pachanga_competition_sequence'), target_actor_id,
    transition_at, transition_at
  from public.pachanga_tournament_qualification_rows qualification_rows
  where qualification_rows.qualification_snapshot_id = qualification_row.id
    and qualification_rows.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
  order by qualification_rows.entry_id;
  structure_snapshot := jsonb_build_object(
    'kind', 'CompetitionBracketRevision',
    'format', 'SINGLE_MATCH_KNOCKOUT',
    'bracketSize', template_row.bracket_size,
    'roundCount', round_count_value,
    'thirdPlaceMatchEnabled', coalesce((policy ->> 'thirdPlaceMatchEnabled')::boolean, false),
    'qualificationSnapshotId', qualification_row.id,
    'bracketTemplateId', template_row.id,
    'templateSlots', template_row.template_snapshot -> 'slots'
  );
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'qualificationChecksum', qualification_row.checksum,
    'templateChecksum', template_row.checksum,
    'ruleChecksum', rule_row.checksum,
    'policy', policy,
    'structure', structure_snapshot
  ));
  insert into public.pachanga_tournament_brackets(
    id, competition_id, edition_id, category_id, group_stage_state_id,
    knockout_stage_id, qualification_snapshot_id, bracket_template_id,
    rule_revision_id, status, bracket_size, round_count,
    third_place_enabled, revision, server_sequence, created_by, updated_by
  ) values (
    target_bracket_id, state_row.competition_id, state_row.edition_id,
    state_row.category_id, state_row.id, knockout_stage_id,
    qualification_row.id, template_row.id, rule_row.id, 'seeded',
    template_row.bracket_size, round_count_value,
    coalesce((policy ->> 'thirdPlaceMatchEnabled')::boolean, false),
    1, target_server_sequence, target_actor_id, target_actor_id
  );
  insert into public.pachanga_tournament_bracket_revisions(
    id, bracket_id, version, revision_kind, lifecycle_status,
    qualification_snapshot_id, bracket_template_id, rule_revision_id,
    qualification_checksum, template_checksum, rule_checksum,
    policy_snapshot, structure_snapshot, checksum, operation_id, reason,
    created_by, server_sequence
  ) values (
    bracket_revision_id, target_bracket_id, 1, 'ACTIVATION', 'seeded',
    qualification_row.id, template_row.id, rule_row.id,
    qualification_row.checksum, template_row.checksum, rule_row.checksum,
    policy, structure_snapshot, checksum_value, target_operation_id,
    'Activación del cuadro eliminatorio desde clasificación publicada.',
    target_actor_id, nextval('private.pachanga_competition_sequence')
  );
  update public.pachanga_tournament_brackets brackets set
    current_revision_id = bracket_revision_id,
    status = 'ready', revision = brackets.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_by = target_actor_id
  where brackets.id = target_bracket_id;
  update public.pachanga_tournament_brackets brackets set
    status = 'active', revision = brackets.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_by = target_actor_id
  where brackets.id = target_bracket_id;

  for round_order_value in 1..round_count_value loop
    match_count := template_row.bracket_size / (2 ^ round_order_value);
    round_code_value := private.pachanga_tournament_knockout_round_code_v1(
      template_row.bracket_size, round_order_value
    );
    for node_order_value in 1..match_count loop
      node_id := private.pachanga_tournament_knockout_entity_id_v1(
        target_bracket_id, 'node:' || round_code_value || ':' || node_order_value::text
      );
      insert into public.pachanga_tournament_bracket_nodes(
        id, bracket_id, bracket_revision_id, round_code, round_order,
        node_order, node_kind, status, revision, server_sequence, updated_by
      ) values (
        node_id, target_bracket_id, bracket_revision_id, round_code_value,
        round_order_value, node_order_value, 'MATCH', 'awaiting_sources', 1,
        nextval('private.pachanga_competition_sequence'), target_actor_id
      );
      if round_order_value = 1 then
        foreach slot_side in array array['HOME', 'AWAY'] loop
          select * into template_slot
          from public.pachanga_tournament_bracket_slots slots
          where slots.bracket_template_id = template_row.id
            and slots.match_number = node_order_value
            and slots.side = case slot_side when 'HOME' then 'A' else 'B' end;
          slot_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
            target_operation_id,
            'initial-slot:' || node_id::text || ':' || slot_side
          );
          slot_id := private.pachanga_tournament_knockout_entity_id_v1(
            slot_operation_id, 'slot-revision'
          );
          insert into public.pachanga_tournament_bracket_node_slots(
            id, bracket_id, bracket_revision_id, bracket_node_id, side,
            slot_revision, source_kind, source_key, source_group_id,
            source_position, source_extra_rank, source_draw_seed,
            resolved_entry_id, resolution_status, source_snapshot,
            operation_id, server_sequence, created_by
          ) values (
            slot_id, target_bracket_id, bracket_revision_id, node_id, slot_side, 1,
            template_slot.source_kind, template_slot.slot_key,
            template_slot.source_group_id, template_slot.source_position,
            template_slot.source_extra_rank, template_slot.source_draw_seed,
            template_slot.resolved_entry_id,
            case when template_slot.source_kind = 'BYE' then 'BYE' else 'RESOLVED' end,
            template_slot.source_snapshot || jsonb_build_object(
              'qualificationSnapshotId', qualification_row.id,
              'bracketTemplateId', template_row.id
            ), slot_operation_id, nextval('private.pachanga_competition_sequence'),
            target_actor_id
          );
        end loop;
      else
        select nodes.id into home_source_node_id
        from public.pachanga_tournament_bracket_nodes nodes
        where nodes.bracket_id = target_bracket_id
          and nodes.round_order = round_order_value - 1
          and nodes.node_order = node_order_value * 2 - 1;
        select nodes.id into away_source_node_id
        from public.pachanga_tournament_bracket_nodes nodes
        where nodes.bracket_id = target_bracket_id
          and nodes.round_order = round_order_value - 1
          and nodes.node_order = node_order_value * 2;
        foreach slot_side in array array['HOME', 'AWAY'] loop
          slot_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
            target_operation_id,
            'initial-slot:' || node_id::text || ':' || slot_side
          );
          slot_id := private.pachanga_tournament_knockout_entity_id_v1(
            slot_operation_id, 'slot-revision'
          );
          insert into public.pachanga_tournament_bracket_node_slots(
            id, bracket_id, bracket_revision_id, bracket_node_id, side,
            slot_revision, source_kind, source_key, source_node_id,
            resolution_status, source_snapshot, operation_id,
            server_sequence, created_by
          ) values (
            slot_id, target_bracket_id, bracket_revision_id, node_id, slot_side, 1,
            'WINNER_OF', 'WINNER:' || case slot_side when 'HOME'
              then home_source_node_id::text else away_source_node_id::text end,
            case slot_side when 'HOME' then home_source_node_id else away_source_node_id end,
            'PENDING_SOURCE', jsonb_build_object(
              'sourceKind', 'WINNER_OF',
              'sourceNodeId', case slot_side when 'HOME'
                then home_source_node_id else away_source_node_id end
            ), slot_operation_id, nextval('private.pachanga_competition_sequence'),
            target_actor_id
          );
        end loop;
      end if;
      node_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
        target_operation_id, 'activate-node:' || node_id::text
      );
      perform private.pachanga_tournament_knockout_record_node_revision_v1(
        node_id, 'ACTIVATION', node_operation_id, target_actor_id,
        nextval('private.pachanga_competition_sequence')
      );
    end loop;
  end loop;

  if coalesce((policy ->> 'thirdPlaceMatchEnabled')::boolean, false) then
    node_id := private.pachanga_tournament_knockout_entity_id_v1(
      target_bracket_id, 'node:THIRD_PLACE:1'
    );
    insert into public.pachanga_tournament_bracket_nodes(
      id, bracket_id, bracket_revision_id, round_code, round_order,
      node_order, node_kind, status, revision, server_sequence, updated_by
    ) values (
      node_id, target_bracket_id, bracket_revision_id, 'THIRD_PLACE',
      round_count_value, 1, 'THIRD_PLACE', 'awaiting_sources', 1,
      nextval('private.pachanga_competition_sequence'), target_actor_id
    );
    select nodes.id into home_source_node_id
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.bracket_id = target_bracket_id and nodes.round_code = 'SEMIFINAL'
      and nodes.node_order = 1;
    select nodes.id into away_source_node_id
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.bracket_id = target_bracket_id and nodes.round_code = 'SEMIFINAL'
      and nodes.node_order = 2;
    foreach slot_side in array array['HOME', 'AWAY'] loop
      slot_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
        target_operation_id, 'initial-slot:' || node_id::text || ':' || slot_side
      );
      insert into public.pachanga_tournament_bracket_node_slots(
        id, bracket_id, bracket_revision_id, bracket_node_id, side,
        slot_revision, source_kind, source_key, source_node_id,
        resolution_status, source_snapshot, operation_id,
        server_sequence, created_by
      ) values (
        private.pachanga_tournament_knockout_entity_id_v1(slot_operation_id, 'slot-revision'),
        target_bracket_id, bracket_revision_id, node_id, slot_side, 1, 'LOSER_OF',
        'LOSER:' || case slot_side when 'HOME' then home_source_node_id::text
          else away_source_node_id::text end,
        case slot_side when 'HOME' then home_source_node_id else away_source_node_id end,
        'PENDING_SOURCE', jsonb_build_object(
          'sourceKind', 'LOSER_OF',
          'sourceNodeId', case slot_side when 'HOME'
            then home_source_node_id else away_source_node_id end
        ), slot_operation_id, nextval('private.pachanga_competition_sequence'),
        target_actor_id
      );
    end loop;
    perform private.pachanga_tournament_knockout_record_node_revision_v1(
      node_id, 'ACTIVATION',
      private.pachanga_tournament_knockout_entity_id_v1(
        target_operation_id, 'activate-node:' || node_id::text
      ), target_actor_id, nextval('private.pachanga_competition_sequence')
    );
  end if;

  for node_row in
    select nodes.* from public.pachanga_tournament_bracket_nodes nodes
    where nodes.bracket_id = target_bracket_id and nodes.round_order = 1
    order by nodes.node_order
  loop
    node_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id, 'resolve-initial:' || node_row.id::text
    );
    perform private.pachanga_tournament_knockout_resolve_node_v1(
      node_row.id, node_operation_id, target_actor_id,
      nextval('private.pachanga_competition_sequence')
    );
    select * into node_row
    from public.pachanga_tournament_bracket_nodes nodes where nodes.id = node_row.id;
    select * into home_slot
    from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'HOME');
    select * into away_slot
    from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'AWAY');
    if node_row.status = 'ready'
       and ((node_row.home_entry_id is not null and away_slot.source_kind = 'BYE')
         or (node_row.away_entry_id is not null and home_slot.source_kind = 'BYE')) then
      perform private.pachanga_tournament_knockout_advance_node_v1(
        node_row.id, null, null, 'BYE',
        coalesce(node_row.home_entry_id, node_row.away_entry_id), null,
        private.pachanga_tournament_knockout_entity_id_v1(
          target_operation_id, 'bye-advance:' || node_row.id::text
        ), target_actor_id, nextval('private.pachanga_competition_sequence')
      );
    end if;
  end loop;
  return target_bracket_id;
end;
$$;
