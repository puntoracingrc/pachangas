-- Pachangas IQ Wave 9B: atomic season holds and publication through Wave 9A authority.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_venue_settings_v1
  add column if not exists competition_venue_allocation_holds_enabled boolean not null default false,
  add column if not exists competition_venue_allocation_publish_enabled boolean not null default false;

create or replace function private.pachanga_venue_allocation_create_holds_v1(
  target_plan_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_expires_minutes integer
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
  revision_row public.pachanga_competition_venue_allocation_revisions%rowtype;
  item_row public.pachanga_competition_venue_allocation_items%rowtype;
  pitch_row public.pachanga_venue_pitches%rowtype;
  request_id uuid;
  claim_id uuid;
  created_hold_id uuid;
  link_id uuid;
  request_operation_id uuid;
  link_operation_id uuid;
  selected_expiry timestamptz;
  selected_sequence bigint;
  selected_count integer := 0;
  item_count integer;
begin
  if not coalesce((
    select settings.competition_venue_allocation_holds_enabled
    from private.pachanga_venue_settings_v1 settings
    where settings.singleton
  ), false) then
    raise exception 'VENUE_ALLOCATION_HOLDS_DISABLED' using errcode = '0A000';
  end if;
  if target_expires_minutes not between 1 and 120 then
    raise exception 'VENUE_ALLOCATION_HOLD_EXPIRY_INVALID' using errcode = '22023';
  end if;

  select * into plan_row
  from public.pachanga_competition_venue_allocation_plans plans
  where plans.id = target_plan_id
  for update;
  if not found or plan_row.status not in ('generated', 'partial', 'conflicted', 'validated') then
    raise exception 'VENUE_ALLOCATION_HOLD_TRANSITION_INVALID' using errcode = 'PT409';
  end if;
  if plan_row.current_revision_id is null then
    raise exception 'VENUE_ALLOCATION_REVISION_REQUIRED' using errcode = 'PT409';
  end if;

  select * into revision_row
  from public.pachanga_competition_venue_allocation_revisions revisions
  where revisions.id = plan_row.current_revision_id
  for update;
  if revision_row.hard_violation_count > 0
     or (plan_row.venue_required and revision_row.unassigned_count > 0) then
    raise exception 'VENUE_ALLOCATION_NOT_HOLDABLE' using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from public.pachanga_competition_venue_allocation_holds allocation_holds
    where allocation_holds.allocation_revision_id = revision_row.id
      and allocation_holds.status = 'active'
  ) then
    raise exception 'VENUE_ALLOCATION_ACTIVE_HOLDS_EXIST' using errcode = 'PT409';
  end if;

  select count(*)::integer into item_count
  from public.pachanga_competition_venue_allocation_items items
  where items.allocation_revision_id = revision_row.id
    and items.pitch_id is not null
    and items.source_kind <> 'EXISTING_BINDING';
  if item_count > 150 then
    raise exception 'VENUE_ALLOCATION_HOLD_BATCH_LIMIT' using errcode = '22023';
  end if;

  selected_expiry := clock_timestamp() + make_interval(mins => target_expires_minutes);
  for item_row in
    select items.*
    from public.pachanga_competition_venue_allocation_items items
    where items.allocation_revision_id = revision_row.id
      and items.pitch_id is not null
      and items.source_kind <> 'EXISTING_BINDING'
    order by items.scheduled_start, items.canonical_match_id, items.id
    for update
  loop
    request_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-request:' || target_operation_id::text || ':' || item_row.id::text
    );
    claim_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-claim:' || target_operation_id::text || ':' || item_row.id::text
    );
    created_hold_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-hold:' || target_operation_id::text || ':' || item_row.id::text
    );
    link_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-hold-link:' || target_operation_id::text || ':' || item_row.id::text
    );
    request_operation_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-request-op:' || target_operation_id::text || ':' || item_row.id::text
    );
    link_operation_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-link-op:' || target_operation_id::text || ':' || item_row.id::text
    );

    pitch_row := private.pachanga_venue_assert_slot_v1(
      item_row.pitch_id,
      item_row.scheduled_start,
      item_row.scheduled_end,
      private.pachanga_venue_allocation_modality_v1(
        (select freezes.rule_snapshot
         from private.pachanga_competition_venue_allocation_input_freezes freezes
         where freezes.id = plan_row.current_input_freeze_id)
      ),
      null
    );
    selected_sequence := nextval('private.pachanga_venue_sequence');

    insert into public.pachanga_venue_reservation_requests(
      id, venue_id, pitch_id, requester_kind, requester_user_id,
      competition_id, canonical_match_id, rule_revision_id, purpose, modality,
      starts_at, ends_at, requested_local_start, requested_local_end, timezone,
      resolved_offset_minutes, criteria, alternatives, message, current_proposal,
      status, revision, server_sequence, operation_id, created_by, updated_by,
      submitted_at, created_at, updated_at
    ) values (
      request_id, item_row.venue_id, item_row.pitch_id, 'COMPETITION', target_actor_id,
      plan_row.competition_id, item_row.canonical_match_id, plan_row.rule_revision_id,
      'COMPETITION_MATCH',
      private.pachanga_venue_allocation_modality_v1(
        (select freezes.rule_snapshot
         from private.pachanga_competition_venue_allocation_input_freezes freezes
         where freezes.id = plan_row.current_input_freeze_id)
      ),
      item_row.scheduled_start, item_row.scheduled_end,
      item_row.scheduled_start at time zone item_row.timezone,
      item_row.scheduled_end at time zone item_row.timezone,
      item_row.timezone,
      private.pachanga_venue_offset_minutes_v1(item_row.scheduled_start, item_row.timezone),
      jsonb_build_object(
        'allocationPlanId', plan_row.id,
        'allocationRevisionId', revision_row.id,
        'allocationItemId', item_row.id
      ),
      '[]'::jsonb, '', '{}'::jsonb, 'HELD', 1, selected_sequence,
      request_operation_id, target_actor_id, target_actor_id,
      clock_timestamp(), clock_timestamp(), clock_timestamp()
    );

    insert into public.pachanga_venue_pitch_claims(
      id, pitch_id, conflict_scope_id, source_kind, source_id, starts_at, ends_at,
      status, expires_at, operation_id, server_sequence, created_at
    ) values (
      claim_id, pitch_row.id, pitch_row.conflict_scope_id, 'HOLD', created_hold_id,
      item_row.scheduled_start - make_interval(mins => pitch_row.buffer_minutes),
      item_row.scheduled_end + make_interval(mins => pitch_row.buffer_minutes),
      'ACTIVE', selected_expiry, request_operation_id, selected_sequence,
      clock_timestamp()
    );

    insert into public.pachanga_venue_reservation_holds(
      id, request_id, pitch_id, claim_id, starts_at, ends_at, expires_at,
      status, revision, server_sequence, operation_id, created_by, created_at
    ) values (
      created_hold_id, request_id, pitch_row.id, claim_id, item_row.scheduled_start,
      item_row.scheduled_end, selected_expiry, 'ACTIVE', 1, selected_sequence,
      request_operation_id, target_actor_id, clock_timestamp()
    );

    update public.pachanga_venue_reservation_requests requests set
      current_hold_id = created_hold_id,
      updated_at = clock_timestamp()
    where requests.id = request_id;

    insert into public.pachanga_competition_venue_allocation_holds(
      id, allocation_plan_id, allocation_revision_id, allocation_item_id,
      wave9a_hold_id, expires_at, status, revision, server_sequence,
      operation_id, created_by, created_at
    ) values (
      link_id, plan_row.id, revision_row.id, item_row.id, created_hold_id,
      selected_expiry, 'active', 1, selected_sequence, link_operation_id,
      target_actor_id, clock_timestamp()
    );

    update public.pachanga_competition_venue_allocation_items items set
      hold_id = created_hold_id,
      assignment_status = 'HELD',
      revision = items.revision + 1,
      server_sequence = nextval('private.pachanga_venue_sequence'),
      updated_at = clock_timestamp()
    where items.id = item_row.id;

    perform private.pachanga_venue_append_revision_v1(
      'reservation_request', request_id, 1, 'allocation.hold',
      request_operation_id, target_actor_id, selected_sequence
    );
    selected_count := selected_count + 1;
  end loop;

  update public.pachanga_competition_venue_allocation_plans plans set
    revision = plans.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where plans.id = plan_row.id;

  return jsonb_build_object(
    'status', 'HELD',
    'heldCount', selected_count,
    'expiresAt', selected_expiry,
    'allocationRevisionId', revision_row.id
  );
end;
$$;

create or replace function private.pachanga_venue_allocation_validate_v1(
  target_plan_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
  revision_row public.pachanga_competition_venue_allocation_revisions%rowtype;
  freeze_row private.pachanga_competition_venue_allocation_input_freezes%rowtype;
  live_checksum text;
  hard_count integer := 0;
  unassigned_count integer := 0;
  validation_result_status text;
  validation_summary jsonb;
begin
  select * into plan_row
  from public.pachanga_competition_venue_allocation_plans plans
  where plans.id = target_plan_id
  for update;
  if not found or plan_row.current_revision_id is null or plan_row.current_input_freeze_id is null then
    raise exception 'VENUE_ALLOCATION_REVISION_REQUIRED' using errcode = 'PT409';
  end if;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'VENUE_ALLOCATION_VALIDATE_TRANSITION_INVALID' using errcode = 'PT409';
  end if;

  select * into revision_row
  from public.pachanga_competition_venue_allocation_revisions revisions
  where revisions.id = plan_row.current_revision_id
  for update;
  select * into freeze_row
  from private.pachanga_competition_venue_allocation_input_freezes freezes
  where freezes.id = plan_row.current_input_freeze_id;

  live_checksum := private.pachanga_venue_allocation_live_input_checksum_v1(plan_row.id);
  select count(*)::integer into unassigned_count
  from public.pachanga_competition_venue_allocation_items items
  where items.allocation_revision_id = revision_row.id
    and items.pitch_id is null;

  hard_count := revision_row.hard_violation_count;
  hard_count := hard_count + (
    select count(*)::integer
    from public.pachanga_competition_venue_allocation_items items
    join public.pachanga_competition_match_contexts contexts
      on contexts.id = items.competition_match_context_id
    left join public.pachanga_competition_venue_pool_memberships memberships
      on memberships.id = items.pool_membership_id
    left join public.pachanga_venue_reservation_holds holds
      on holds.id = items.hold_id
    left join public.pachanga_venue_match_bindings bindings
      on bindings.id = items.binding_id
    where items.allocation_revision_id = revision_row.id
      and (
        items.scheduled_start is distinct from contexts.scheduled_start
        or items.scheduled_end is distinct from contexts.scheduled_end
        or contexts.schedule_item_id is distinct from items.schedule_item_id
        or (items.pitch_id is not null and items.source_kind <> 'EXISTING_BINDING'
          and (memberships.id is null or memberships.status <> 'active'))
        or (items.assignment_status = 'HELD'
          and (holds.id is null or holds.status <> 'ACTIVE' or holds.expires_at <= clock_timestamp()))
        or (items.source_kind = 'EXISTING_BINDING'
          and (bindings.id is null or bindings.status not in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')))
      )
  );
  hard_count := hard_count + (
    select count(*)::integer
    from public.pachanga_competition_venue_allocation_items left_item
    join public.pachanga_competition_venue_allocation_items right_item
      on right_item.allocation_revision_id = left_item.allocation_revision_id
     and right_item.id > left_item.id
    join public.pachanga_venue_pitches left_pitch on left_pitch.id = left_item.pitch_id
    join public.pachanga_venue_pitches right_pitch on right_pitch.id = right_item.pitch_id
    where left_item.allocation_revision_id = revision_row.id
      and left_pitch.conflict_scope_id = right_pitch.conflict_scope_id
      and tstzrange(left_item.scheduled_start, left_item.scheduled_end, '[)')
        && tstzrange(right_item.scheduled_start, right_item.scheduled_end, '[)')
  );

  validation_result_status := case
    when live_checksum is distinct from freeze_row.input_checksum then 'STALE_INPUT'
    when hard_count > 0 or (plan_row.venue_required and unassigned_count > 0) then 'INVALID'
    else 'VALID'
  end;
  validation_summary := jsonb_build_object(
    'status', validation_result_status,
    'hardViolationCount', hard_count,
    'unassignedRequiredCount', case when plan_row.venue_required then unassigned_count else 0 end,
    'frozenInputChecksum', freeze_row.input_checksum,
    'liveInputChecksum', live_checksum,
    'allocationRevisionId', revision_row.id
  );

  insert into private.pachanga_competition_venue_allocation_validations(
    allocation_plan_id, allocation_revision_id, input_checksum, result_checksum,
    status, hard_violation_count, unassigned_required_count, summary,
    validated_by, server_sequence, validated_at
  ) values (
    plan_row.id, revision_row.id, live_checksum, revision_row.result_checksum,
    validation_result_status, hard_count,
    case when plan_row.venue_required then unassigned_count else 0 end,
    validation_summary, target_actor_id, nextval('private.pachanga_venue_sequence'),
    clock_timestamp()
  ) on conflict (allocation_revision_id, input_checksum, result_checksum)
  do nothing;

  update public.pachanga_competition_venue_allocation_plans plans set
    status = case when validation_result_status = 'VALID' then 'validated'
      when validation_result_status = 'STALE_INPUT' then 'stale' else 'conflicted' end,
    validated_at = case when validation_result_status = 'VALID' then clock_timestamp() else null end,
    revision = plans.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where plans.id = plan_row.id;

  return validation_summary;
end;
$$;

create or replace function private.pachanga_venue_allocation_publish_v1(
  target_plan_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_reason_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
  revision_row public.pachanga_competition_venue_allocation_revisions%rowtype;
  freeze_row private.pachanga_competition_venue_allocation_input_freezes%rowtype;
  item_row public.pachanga_competition_venue_allocation_items%rowtype;
  allocation_hold_row public.pachanga_competition_venue_allocation_holds%rowtype;
  hold_row public.pachanga_venue_reservation_holds%rowtype;
  claim_row public.pachanga_venue_pitch_claims%rowtype;
  request_row public.pachanga_venue_reservation_requests%rowtype;
  context_row public.pachanga_competition_match_contexts%rowtype;
  venue_row public.pachanga_club_venues%rowtype;
  created_reservation_id uuid;
  terms_id uuid;
  created_binding_id uuid;
  item_operation_id uuid;
  selected_sequence bigint;
  published_count integer := 0;
  preserved_count integer := 0;
begin
  if not coalesce((
    select settings.competition_venue_allocation_publish_enabled
    from private.pachanga_venue_settings_v1 settings
    where settings.singleton
  ), false) then
    raise exception 'VENUE_ALLOCATION_PUBLISH_DISABLED' using errcode = '0A000';
  end if;
  select * into plan_row
  from public.pachanga_competition_venue_allocation_plans plans
  where plans.id = target_plan_id
  for update;
  if not found or plan_row.status <> 'validated' or plan_row.current_revision_id is null then
    raise exception 'VENUE_ALLOCATION_PUBLISH_TRANSITION_INVALID' using errcode = 'PT409';
  end if;
  select * into revision_row
  from public.pachanga_competition_venue_allocation_revisions revisions
  where revisions.id = plan_row.current_revision_id
  for update;
  select * into freeze_row
  from private.pachanga_competition_venue_allocation_input_freezes freezes
  where freezes.id = plan_row.current_input_freeze_id;
  if not exists (
       select 1
       from private.pachanga_competition_venue_allocation_validations validations
       where validations.allocation_revision_id = revision_row.id
         and validations.input_checksum = freeze_row.input_checksum
         and validations.result_checksum = revision_row.result_checksum
         and validations.status = 'VALID'
     )
     or private.pachanga_venue_allocation_live_input_checksum_v1(plan_row.id)
        is distinct from freeze_row.input_checksum then
    raise exception 'VENUE_ALLOCATION_INPUTS_CHANGED' using errcode = '40001';
  end if;

  for item_row in
    select items.*
    from public.pachanga_competition_venue_allocation_items items
    where items.allocation_revision_id = revision_row.id
    order by items.scheduled_start, items.canonical_match_id, items.id
    for update
  loop
    if item_row.source_kind = 'EXISTING_BINDING' then
      if item_row.binding_id is null or not exists (
        select 1 from public.pachanga_venue_match_bindings bindings
        where bindings.id = item_row.binding_id
          and bindings.canonical_match_id = item_row.canonical_match_id
          and bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
      ) then
        raise exception 'VENUE_ALLOCATION_EXISTING_BINDING_CHANGED' using errcode = '40001';
      end if;
      update public.pachanga_competition_venue_allocation_items items set
        assignment_status = 'PUBLISHED',
        revision = items.revision + 1,
        server_sequence = nextval('private.pachanga_venue_sequence'),
        updated_at = clock_timestamp()
      where items.id = item_row.id;
      preserved_count := preserved_count + 1;
      continue;
    end if;
    if item_row.pitch_id is null then
      if plan_row.venue_required then
        raise exception 'VENUE_ALLOCATION_REQUIRED_ITEM_UNASSIGNED' using errcode = 'PT409';
      end if;
      continue;
    end if;

    select * into allocation_hold_row
    from public.pachanga_competition_venue_allocation_holds allocation_holds
    where allocation_holds.allocation_revision_id = revision_row.id
      and allocation_holds.allocation_item_id = item_row.id
      and allocation_holds.status = 'active'
    for update;
    if not found then
      raise exception 'VENUE_ALLOCATION_HOLD_REQUIRED' using errcode = 'PT409';
    end if;
    select * into hold_row
    from public.pachanga_venue_reservation_holds holds
    where holds.id = allocation_hold_row.wave9a_hold_id
    for update;
    if not found or hold_row.status <> 'ACTIVE' or hold_row.expires_at <= clock_timestamp() then
      raise exception 'VENUE_ALLOCATION_HOLD_EXPIRED' using errcode = 'PT409';
    end if;
    select * into claim_row
    from public.pachanga_venue_pitch_claims claims
    where claims.id = hold_row.claim_id
    for update;
    select * into request_row
    from public.pachanga_venue_reservation_requests requests
    where requests.id = hold_row.request_id
    for update;
    select * into context_row
    from public.pachanga_competition_match_contexts contexts
    where contexts.id = item_row.competition_match_context_id
      and contexts.canonical_match_id = item_row.canonical_match_id
    for update;
    select * into venue_row
    from public.pachanga_club_venues venues
    where venues.id = item_row.venue_id;
    if not found or context_row.scheduled_start is distinct from item_row.scheduled_start
       or context_row.scheduled_end is distinct from item_row.scheduled_end then
      raise exception 'VENUE_ALLOCATION_MATCH_CHANGED' using errcode = '40001';
    end if;
    if exists (
      select 1 from public.pachanga_venue_match_bindings bindings
      where bindings.canonical_match_id = item_row.canonical_match_id
        and bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
    ) then
      raise exception 'VENUE_ALLOCATION_MATCH_ALREADY_BOUND' using errcode = '23505';
    end if;

    created_reservation_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-reservation:' || target_operation_id::text || ':' || item_row.id::text
    );
    terms_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-terms:' || target_operation_id::text || ':' || item_row.id::text
    );
    created_binding_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-binding:' || target_operation_id::text || ':' || item_row.id::text
    );
    item_operation_id := private.pachanga_venue_deterministic_uuid_v1(
      'allocation-publish-op:' || target_operation_id::text || ':' || item_row.id::text
    );
    selected_sequence := nextval('private.pachanga_venue_sequence');

    insert into private.pachanga_venue_reservation_terms(
      id, request_id, terms_kind, amount_minor, currency, public_rate_allowed,
      tax_display_text, private_notes, cancellation_terms, terms_snapshot,
      version, operation_id, created_by, server_sequence, created_at
    ) values (
      terms_id, request_row.id, 'CONTACT_CLUB', null, null, false, null, '', '',
      jsonb_build_object(
        'kind', 'CONTACT_CLUB',
        'source', 'COMPETITION_VENUE_ALLOCATION',
        'allocationPlanId', plan_row.id
      ),
      1, item_operation_id, target_actor_id, selected_sequence, clock_timestamp()
    );

    update public.pachanga_venue_pitch_claims claims set
      source_kind = 'RESERVATION',
      source_id = created_reservation_id,
      expires_at = null,
      operation_id = item_operation_id,
      server_sequence = selected_sequence
    where claims.id = claim_row.id;
    update public.pachanga_venue_reservation_holds holds set
      status = 'CONSUMED',
      revision = holds.revision + 1,
      server_sequence = selected_sequence,
      released_by = target_actor_id,
      released_at = clock_timestamp()
    where holds.id = hold_row.id;

    insert into public.pachanga_venue_reservations(
      id, request_id, venue_id, pitch_id, requester_user_id, requester_team_id,
      requester_club_id, competition_id, canonical_match_id, terms_id, claim_id,
      starts_at, ends_at, timezone, status, revision, server_sequence, operation_id,
      accepted_by, accepted_at, confirmed_by, confirmed_at, created_at, updated_at
    ) values (
      created_reservation_id, request_row.id, item_row.venue_id, item_row.pitch_id,
      target_actor_id, null, null, plan_row.competition_id,
      item_row.canonical_match_id, terms_id, claim_row.id,
      item_row.scheduled_start, item_row.scheduled_end, item_row.timezone,
      'CONFIRMED', 1, selected_sequence, item_operation_id,
      target_actor_id, clock_timestamp(), target_actor_id, clock_timestamp(),
      clock_timestamp(), clock_timestamp()
    );

    update public.pachanga_venue_reservation_requests requests set
      status = 'CONFIRMED',
      current_reservation_id = created_reservation_id,
      resolved_at = clock_timestamp(),
      revision = requests.revision + 1,
      server_sequence = selected_sequence,
      operation_id = item_operation_id,
      updated_by = target_actor_id,
      updated_at = clock_timestamp()
    where requests.id = request_row.id;

    update public.pachanga_competition_match_contexts contexts set
      venue_id = item_row.venue_id,
      venue_label = venue_row.name,
      venue_status = 'CONFIRMED',
      revision = contexts.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where contexts.id = context_row.id;

    insert into public.pachanga_venue_match_bindings(
      id, reservation_id, canonical_match_id, competition_match_context_id,
      schedule_item_id, rule_revision_id, venue_id, pitch_id, status,
      binding_revision, server_sequence, operation_id, bound_by, bound_at, updated_at
    ) values (
      created_binding_id, created_reservation_id, item_row.canonical_match_id,
      item_row.competition_match_context_id, item_row.schedule_item_id,
      plan_row.rule_revision_id, item_row.venue_id, item_row.pitch_id,
      'ACTIVE', 1, selected_sequence, item_operation_id, target_actor_id,
      clock_timestamp(), clock_timestamp()
    );

    update public.pachanga_competition_venue_allocation_holds allocation_holds set
      status = 'consumed',
      revision = allocation_holds.revision + 1,
      server_sequence = nextval('private.pachanga_venue_sequence'),
      released_at = clock_timestamp()
    where allocation_holds.id = allocation_hold_row.id;
    update public.pachanga_competition_venue_allocation_items items set
      reservation_id = created_reservation_id,
      binding_id = created_binding_id,
      assignment_status = 'PUBLISHED',
      revision = items.revision + 1,
      server_sequence = nextval('private.pachanga_venue_sequence'),
      updated_at = clock_timestamp()
    where items.id = item_row.id;
    update public.pachanga_competition_venue_pool_memberships memberships set
      consumed_count = memberships.consumed_count + 1,
      revision = memberships.revision + 1,
      server_sequence = nextval('private.pachanga_venue_sequence'),
      updated_at = clock_timestamp()
    where memberships.id = item_row.pool_membership_id;

    if item_row.source_kind = 'RECURRING_OCCURRENCE' then
      update public.pachanga_venue_recurring_occurrences occurrences set
        reservation_id = created_reservation_id,
        status = 'reserved',
        revision = occurrences.revision + 1,
        server_sequence = nextval('private.pachanga_venue_sequence'),
        updated_at = clock_timestamp()
      where occurrences.id = item_row.source_id;
    end if;

    perform private.pachanga_venue_append_revision_v1(
      'reservation_request', request_row.id, request_row.revision + 1,
      'allocation.publish', item_operation_id, target_actor_id, selected_sequence
    );
    perform private.pachanga_venue_append_revision_v1(
      'reservation', created_reservation_id, 1, 'allocation.publish',
      item_operation_id, target_actor_id, nextval('private.pachanga_venue_sequence')
    );
    perform private.pachanga_venue_append_revision_v1(
      'venue_binding', created_binding_id, 1, 'allocation.publish',
      item_operation_id, target_actor_id, nextval('private.pachanga_venue_sequence')
    );
    published_count := published_count + 1;
  end loop;

  update public.pachanga_competition_venue_allocation_plans plans set
    status = 'published',
    published_at = clock_timestamp(),
    revision = plans.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where plans.id = plan_row.id;

  return jsonb_build_object(
    'status', 'PUBLISHED',
    'publishedCount', published_count,
    'preservedBindingCount', preserved_count,
    'allocationRevisionId', revision_row.id,
    'reasonCode', target_reason_code
  );
end;
$$;

create or replace function private.pachanga_venue_allocation_cancel_v1(
  target_plan_id uuid,
  target_actor_id uuid,
  target_reason_code text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
  released_count integer := 0;
begin
  select * into plan_row
  from public.pachanga_competition_venue_allocation_plans plans
  where plans.id = target_plan_id
  for update;
  if not found or plan_row.status in ('published', 'cancelled') then
    raise exception 'VENUE_ALLOCATION_CANCEL_TRANSITION_INVALID' using errcode = 'PT409';
  end if;

  with released as (
    update public.pachanga_venue_reservation_holds holds set
      status = 'RELEASED',
      revision = holds.revision + 1,
      server_sequence = nextval('private.pachanga_venue_sequence'),
      released_by = target_actor_id,
      released_at = clock_timestamp()
    from public.pachanga_competition_venue_allocation_holds allocation_holds
    where allocation_holds.allocation_plan_id = plan_row.id
      and allocation_holds.wave9a_hold_id = holds.id
      and allocation_holds.status = 'active'
      and holds.status = 'ACTIVE'
    returning holds.claim_id
  )
  update public.pachanga_venue_pitch_claims claims set
    status = 'RELEASED',
    released_at = clock_timestamp(),
    server_sequence = nextval('private.pachanga_venue_sequence')
  where claims.id in (select released.claim_id from released)
    and claims.status = 'ACTIVE';
  get diagnostics released_count = row_count;

  update public.pachanga_competition_venue_allocation_holds allocation_holds set
    status = 'released',
    revision = allocation_holds.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    released_at = clock_timestamp()
  where allocation_holds.allocation_plan_id = plan_row.id
    and allocation_holds.status = 'active';
  update public.pachanga_venue_reservation_requests requests set
    status = 'CANCELLED',
    resolved_at = clock_timestamp(),
    revision = requests.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where requests.current_hold_id in (
    select allocation_holds.wave9a_hold_id
    from public.pachanga_competition_venue_allocation_holds allocation_holds
    where allocation_holds.allocation_plan_id = plan_row.id
  ) and requests.status = 'HELD';
  update public.pachanga_competition_venue_allocation_plans plans set
    status = 'cancelled',
    cancelled_at = clock_timestamp(),
    revision = plans.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where plans.id = plan_row.id;

  return jsonb_build_object(
    'status', 'CANCELLED',
    'releasedHoldCount', released_count,
    'reasonCode', target_reason_code
  );
end;
$$;

do $$
declare
  signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_venue_allocation_create_holds_v1(uuid,uuid,uuid,integer)'::regprocedure,
    'private.pachanga_venue_allocation_validate_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_venue_allocation_publish_v1(uuid,uuid,uuid,text)'::regprocedure,
    'private.pachanga_venue_allocation_cancel_v1(uuid,uuid,text)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
    execute format('grant execute on function %s to service_role', signature);
  end loop;
end
$$;

comment on function private.pachanga_venue_allocation_publish_v1(uuid, uuid, uuid, text) is
  'Atomically converts allocation holds into Wave 9A reservations and CanonicalMatch bindings. No partial publication.';

reset statement_timeout;
reset lock_timeout;
