-- Pachangas IQ Wave 4: assignment lifecycle, private fee agreement and narrow
-- match-officiating commands. Payment and official result authority stay out.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_referee_assignment_document_v1(
  target_assignment_id uuid,
  include_private_terms boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', assignments.id,
    'refereeProfileId', assignments.referee_profile_id,
    'canonicalMatchId', assignments.canonical_match_id,
    'canonicalBindingId', assignments.canonical_binding_id,
    'competitionMatchContextId', assignments.competition_match_context_id,
    'assignmentRole', assignments.assignment_role,
    'requesterKind', assignments.requester_kind,
    'requesterTeamId', assignments.requester_team_id,
    'requesterClubId', assignments.requester_club_id,
    'requesterCompetitionId', assignments.requester_competition_id,
    'competitionId', assignments.competition_id,
    'sourceKind', assignments.source_kind,
    'sourceGroupId', assignments.source_group_id,
    'sourceId', assignments.source_id,
    'status', assignments.status,
    'scheduleState', assignments.schedule_state,
    'scheduledStart', assignments.scheduled_start,
    'scheduledEnd', assignments.scheduled_end,
    'timezone', assignments.timezone,
    'effectiveScheduledStart', assignments.effective_scheduled_start,
    'effectiveScheduledEnd', assignments.effective_scheduled_end,
    'effectiveTimezone', assignments.effective_timezone,
    'scheduleSourceRevision', assignments.schedule_source_revision,
    'effectiveScheduleRevision', assignments.effective_schedule_revision,
    'modality', assignments.modality,
    'venueId', assignments.venue_id,
    'venueLabel', assignments.venue_label,
    'venueStatus', assignments.venue_status,
    'responseDeadline', assignments.response_deadline,
    'acceptedAt', assignments.accepted_at,
    'declinedAt', assignments.declined_at,
    'confirmedAt', assignments.confirmed_at,
    'cancelledAt', assignments.cancelled_at,
    'expiredAt', assignments.expired_at,
    'completedAt', assignments.completed_at,
    'reconfirmedAt', assignments.reconfirmed_at,
    'replacesAssignmentId', assignments.replaces_assignment_id,
    'replacementPendingAssignmentId', assignments.replacement_pending_assignment_id,
    'replacedByAssignmentId', assignments.replaced_by_assignment_id,
    'revision', assignments.revision,
    'serverSequence', assignments.server_sequence,
    'privateTerms', case when include_private_terms then jsonb_build_object(
      'feeMode', terms.fee_mode,
      'proposedFeeCents', terms.proposed_fee_cents,
      'counterFeeCents', terms.counter_fee_cents,
      'agreedFeeCents', terms.agreed_fee_cents,
      'currency', terms.currency,
      'travelIncluded', terms.travel_included,
      'privateNote', terms.private_terms_note,
      'status', terms.terms_status,
      'revision', terms.terms_revision
    ) else null end
  ))
  from public.pachanga_referee_assignments assignments
  left join private.pachanga_referee_assignment_terms terms
    on terms.assignment_id = assignments.id
  where assignments.id = target_assignment_id;
$$;

create or replace function private.pachanga_referee_terms_input_v1(
  target_assignment_id uuid,
  target_actor_id uuid,
  payload jsonb,
  source_terms private.pachanga_referee_assignment_terms default null
)
returns private.pachanga_referee_assignment_terms
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved private.pachanga_referee_assignment_terms%rowtype;
  selected_mode text := upper(coalesce(nullif(trim(payload ->> 'feeMode'), ''), source_terms.fee_mode, 'NEGOTIABLE'));
  selected_proposed integer := coalesce(nullif(payload ->> 'proposedFeeCents', '')::integer,
    source_terms.agreed_fee_cents, source_terms.proposed_fee_cents);
  selected_currency text := upper(coalesce(nullif(trim(payload ->> 'currency'), ''), source_terms.currency, 'EUR'));
  selected_travel boolean := coalesce((payload ->> 'travelIncluded')::boolean,
    source_terms.travel_included, false);
  selected_note text := left(coalesce(payload ->> 'privateTermsNote', source_terms.private_terms_note, ''), 1200);
begin
  if selected_mode not in ('FREE', 'FIXED', 'NEGOTIABLE', 'VOLUNTEER')
     or selected_currency !~ '^[A-Z]{3}$'
     or selected_proposed is not null and selected_proposed not between 0 and 10000000
     or selected_mode in ('FREE', 'VOLUNTEER') and selected_proposed is not null then
    raise exception 'REFEREE_ASSIGNMENT_TERMS_INVALID' using errcode = '22023';
  end if;
  insert into private.pachanga_referee_assignment_terms(
    assignment_id, fee_mode, proposed_fee_cents, currency, travel_included,
    private_terms_note, terms_status, terms_revision, proposed_by,
    server_sequence, updated_at
  ) values (
    target_assignment_id, selected_mode, selected_proposed, selected_currency,
    selected_travel, selected_note, 'PROPOSED', 1, target_actor_id,
    nextval('private.pachanga_referee_sequence'), clock_timestamp()
  ) returning * into saved;
  return saved;
end;
$$;

create or replace function public.command_pachanga_referee_assignment_beta_v1(
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
declare
  actor_id uuid := auth.uid();
  action_name text := lower(trim(coalesce(command_action, '')));
  payload jsonb := coalesce(command_payload, '{}'::jsonb);
  request_hash text;
  replay jsonb;
  assignment public.pachanga_referee_assignments%rowtype;
  original public.pachanga_referee_assignments%rowtype;
  profile public.pachanga_referee_profiles%rowtype;
  original_profile public.pachanga_referee_profiles%rowtype;
  terms private.pachanga_referee_assignment_terms%rowtype;
  original_terms private.pachanga_referee_assignment_terms%rowtype;
  match_snapshot jsonb;
  authority text;
  requester_kind text;
  requester_id uuid;
  target_profile_id uuid;
  target_deadline timestamptz;
  target_status text;
  target_reason text;
  target_user_id uuid;
  snapshot jsonb;
  event_payload jsonb;
  fee_mode text;
  counter_cents integer;
  locked_match_context_id uuid;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or action_name = '' then
    raise exception 'INVALID_OPERATION_ENVELOPE' using errcode = '22023';
  end if;
  if jsonb_typeof(payload) <> 'object' or pg_column_size(payload) > 32768
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(coalesce(client_metadata, '{}'::jsonb)) > 8192 then
    raise exception 'INVALID_COMMAND_PAYLOAD' using errcode = '22023';
  end if;
  if payload ?| array[
    'actorId', 'createdBy', 'serverSequence', 'confirmedRevision',
    'authorityUsed', 'statistics', 'rating', 'ratings', 'facets', 'grl',
    'paymentIntent', 'paymentStatus', 'serviceRole'
  ] then raise exception 'REFEREE_SERVER_FIELDS_FORBIDDEN' using errcode = '22023'; end if;
  if action_name not in (
    'assignment.propose', 'assignment.accept', 'assignment.decline',
    'assignment.confirm', 'assignment.cancel', 'assignment.replace',
    'assignment.reconfirm', 'terms.counter', 'terms.accept', 'terms.decline'
  ) then raise exception 'REFEREE_ASSIGNMENT_ACTION_NOT_AVAILABLE' using errcode = '0A000'; end if;
  perform private.pachanga_referee_assert_assignment_beta_v1();
  perform private.pachanga_referee_rate_limit_v1(actor_id, action_name);
  request_hash := private.pachanga_referee_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  perform set_config('pachangas.referee_reason', action_name, true);

  if action_name = 'assignment.propose' then
    if expected_revision <> 0
       or exists (select 1 from public.pachanga_referee_assignments where id = aggregate_id) then
      raise exception 'REFEREE_ASSIGNMENT_ID_EXISTS' using errcode = 'PT409';
    end if;
    target_profile_id := nullif(payload ->> 'refereeProfileId', '')::uuid;
    select * into profile from public.pachanga_referee_profiles profiles
    where profiles.id = target_profile_id;
    if not found or profile.operational_status <> 'active'
       or not profile.available_for_assignments then
      raise exception 'REFEREE_PROFILE_NOT_ASSIGNABLE' using errcode = '42501';
    end if;
    if upper(coalesce(nullif(payload ->> 'assignmentRole', ''), 'MAIN_REFEREE')) <> 'MAIN_REFEREE' then
      raise exception 'REFEREE_ROLE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    match_snapshot := private.pachanga_referee_match_snapshot_v1(
      lower(trim(payload ->> 'sourceKind')),
      nullif(payload ->> 'sourceGroupId', '')::uuid,
      trim(payload ->> 'sourceId')
    );
    locked_match_context_id := nullif(match_snapshot ->> 'competitionMatchContextId', '')::uuid;
    if locked_match_context_id is not null then
      perform contexts.id
      from public.pachanga_competition_match_contexts contexts
      where contexts.id = locked_match_context_id
      for update;
      if not found then
        raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002';
      end if;
      match_snapshot := private.pachanga_referee_match_snapshot_v1(
        lower(trim(payload ->> 'sourceKind')),
        nullif(payload ->> 'sourceGroupId', '')::uuid,
        trim(payload ->> 'sourceId')
      );
    end if;
    requester_kind := upper(trim(payload ->> 'requesterKind'));
    requester_id := nullif(payload ->> 'requesterId', '')::uuid;
    authority := private.pachanga_referee_assignment_authority_v1(
      match_snapshot, requester_kind, requester_id, actor_id
    );
    target_deadline := coalesce(nullif(payload ->> 'responseDeadline', '')::timestamptz,
      clock_timestamp() + interval '72 hours');
    if target_deadline <= clock_timestamp() or target_deadline > clock_timestamp() + interval '30 days' then
      raise exception 'INVALID_ASSIGNMENT_DEADLINE' using errcode = '22023';
    end if;
    insert into public.pachanga_referee_assignments(
      id, referee_profile_id, canonical_match_id, assignment_role,
      requester_kind, requester_team_id, requester_club_id,
      requester_competition_id, competition_id, source_kind, source_group_id,
      source_id, status, scheduled_start, scheduled_end, timezone,
      schedule_source_revision, effective_scheduled_start,
      effective_scheduled_end, effective_timezone, effective_schedule_revision,
      proposed_by, authority_used, proposal_message, response_deadline,
      revision, server_sequence
    ) values (
      aggregate_id, profile.id, (match_snapshot ->> 'canonicalMatchId')::uuid,
      'MAIN_REFEREE', requester_kind,
      case when requester_kind = 'TEAM' then requester_id end,
      case when requester_kind = 'CLUB' then requester_id end,
      case when requester_kind = 'COMPETITION' then requester_id end,
      nullif(match_snapshot ->> 'competitionId', '')::uuid,
      match_snapshot ->> 'sourceKind', nullif(match_snapshot ->> 'sourceGroupId', '')::uuid,
      match_snapshot ->> 'sourceId', 'proposed',
      coalesce(nullif(match_snapshot ->> 'originalScheduledStart', '')::timestamptz,
        (match_snapshot ->> 'scheduledStart')::timestamptz),
      coalesce(nullif(match_snapshot ->> 'originalScheduledEnd', '')::timestamptz,
        (match_snapshot ->> 'scheduledEnd')::timestamptz),
      match_snapshot ->> 'timezone', (match_snapshot ->> 'scheduleRevision')::bigint,
      (match_snapshot ->> 'effectiveScheduledStart')::timestamptz,
      (match_snapshot ->> 'effectiveScheduledEnd')::timestamptz,
      match_snapshot ->> 'effectiveTimezone',
      (match_snapshot ->> 'effectiveScheduleRevision')::bigint,
      actor_id, authority, left(coalesce(payload ->> 'message', ''), 800),
      target_deadline, 1, nextval('private.pachanga_referee_sequence')
    ) returning * into assignment;
    terms := private.pachanga_referee_terms_input_v1(assignment.id, actor_id, payload, null);
    target_status := 'proposed';
    target_reason := 'Nueva propuesta de arbitraje';
    target_user_id := profile.user_id;

  else
    select assignments.competition_match_context_id into locked_match_context_id
    from public.pachanga_referee_assignments assignments
    where assignments.id = aggregate_id;
    if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
    if locked_match_context_id is not null then
      perform contexts.id
      from public.pachanga_competition_match_contexts contexts
      where contexts.id = locked_match_context_id
      for update;
      if not found then
        raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002';
      end if;
    end if;
    select * into assignment from public.pachanga_referee_assignments assignments
    where assignments.id = aggregate_id for update;
    if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
    if assignment.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    select * into profile from public.pachanga_referee_profiles profiles
    where profiles.id = assignment.referee_profile_id for update;
    select * into terms from private.pachanga_referee_assignment_terms selected_terms
    where selected_terms.assignment_id = assignment.id for update;
    requester_id := coalesce(assignment.requester_team_id,
      assignment.requester_club_id, assignment.requester_competition_id);

    if action_name in ('assignment.accept', 'assignment.decline', 'terms.counter', 'assignment.reconfirm')
       or (action_name = 'assignment.cancel' and profile.user_id = actor_id) then
      if profile.user_id <> actor_id then raise exception 'REFEREE_PROFILE_OWNER_REQUIRED' using errcode = '42501'; end if;
    else
      match_snapshot := private.pachanga_referee_match_snapshot_v1(
        assignment.source_kind, assignment.source_group_id, assignment.source_id
      );
      authority := private.pachanga_referee_assignment_authority_v1(
        match_snapshot, assignment.requester_kind, requester_id, actor_id
      );
    end if;

    if action_name = 'assignment.accept' then
      if assignment.status <> 'proposed' then raise exception 'REFEREE_ASSIGNMENT_NOT_PROPOSED' using errcode = 'PT409'; end if;
      if assignment.response_deadline <= clock_timestamp() then
        update private.pachanga_referee_assignment_terms selected_terms set
          terms_status = 'DECLINED', declined_at = clock_timestamp(),
          terms_revision = selected_terms.terms_revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence'), updated_at = clock_timestamp()
        where selected_terms.assignment_id = assignment.id returning * into terms;
        update public.pachanga_referee_assignments assignments set
          status = 'expired', expired_at = clock_timestamp(),
          revision = assignments.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where assignments.id = assignment.id returning * into assignment;
        target_status := 'expired';
        target_reason := 'La propuesta ha caducado';
      else
        update private.pachanga_referee_assignment_terms selected_terms set
          terms_status = 'ACCEPTED',
          agreed_fee_cents = selected_terms.proposed_fee_cents,
          accepted_by = actor_id, accepted_at = clock_timestamp(),
          terms_revision = selected_terms.terms_revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence'), updated_at = clock_timestamp()
        where selected_terms.assignment_id = assignment.id returning * into terms;
        update public.pachanga_referee_assignments assignments set
          status = 'accepted', accepted_at = clock_timestamp(),
          revision = assignments.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where assignments.id = assignment.id returning * into assignment;
        target_status := 'accepted';
        target_reason := 'Arbitraje aceptado';
      end if;
      target_user_id := assignment.proposed_by;

    elsif action_name = 'assignment.decline' then
      if assignment.status <> 'proposed' then raise exception 'REFEREE_ASSIGNMENT_NOT_PROPOSED' using errcode = 'PT409'; end if;
      update private.pachanga_referee_assignment_terms selected_terms set
        terms_status = 'DECLINED', declined_at = clock_timestamp(),
        terms_revision = selected_terms.terms_revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence'), updated_at = clock_timestamp()
      where selected_terms.assignment_id = assignment.id returning * into terms;
      update public.pachanga_referee_assignments assignments set
        status = 'declined', declined_at = clock_timestamp(),
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      if assignment.replaces_assignment_id is not null then
        update public.pachanga_referee_assignments originals set
          replacement_pending_assignment_id = null,
          revision = originals.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where originals.id = assignment.replaces_assignment_id
          and originals.replacement_pending_assignment_id = assignment.id;
      end if;
      target_status := 'declined'; target_reason := 'Arbitraje rechazado';
      target_user_id := assignment.proposed_by;

    elsif action_name = 'terms.counter' then
      if assignment.status <> 'proposed' or terms.terms_status <> 'PROPOSED'
         or terms.fee_mode not in ('FIXED', 'NEGOTIABLE') then
        raise exception 'REFEREE_TERMS_NOT_COUNTERABLE' using errcode = 'PT409';
      end if;
      counter_cents := nullif(payload ->> 'counterFeeCents', '')::integer;
      if counter_cents is null or counter_cents not between 0 and 10000000 then
        raise exception 'REFEREE_ASSIGNMENT_TERMS_INVALID' using errcode = '22023';
      end if;
      update private.pachanga_referee_assignment_terms selected_terms set
        counter_fee_cents = counter_cents, terms_status = 'COUNTERED',
        countered_by = actor_id, countered_at = clock_timestamp(),
        private_terms_note = left(coalesce(payload ->> 'privateTermsNote', selected_terms.private_terms_note), 1200),
        terms_revision = selected_terms.terms_revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence'), updated_at = clock_timestamp()
      where selected_terms.assignment_id = assignment.id returning * into terms;
      update public.pachanga_referee_assignments assignments set
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      target_status := 'countered'; target_reason := 'Contraoferta arbitral';
      target_user_id := assignment.proposed_by;

    elsif action_name = 'terms.accept' then
      if assignment.status <> 'proposed' or terms.terms_status <> 'COUNTERED' then
        raise exception 'REFEREE_TERMS_NOT_ACCEPTABLE' using errcode = 'PT409';
      end if;
      update private.pachanga_referee_assignment_terms selected_terms set
        terms_status = 'ACCEPTED', agreed_fee_cents = selected_terms.counter_fee_cents,
        accepted_by = actor_id, accepted_at = clock_timestamp(),
        terms_revision = selected_terms.terms_revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence'), updated_at = clock_timestamp()
      where selected_terms.assignment_id = assignment.id returning * into terms;
      update public.pachanga_referee_assignments assignments set
        status = 'accepted', accepted_at = clock_timestamp(), authority_used = authority,
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      target_status := 'accepted'; target_reason := 'Contraoferta aceptada';
      target_user_id := profile.user_id;

    elsif action_name = 'terms.decline' then
      if assignment.status <> 'proposed' or terms.terms_status <> 'COUNTERED' then
        raise exception 'REFEREE_TERMS_NOT_DECLINABLE' using errcode = 'PT409';
      end if;
      update private.pachanga_referee_assignment_terms selected_terms set
        terms_status = 'DECLINED', declined_at = clock_timestamp(),
        terms_revision = selected_terms.terms_revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence'), updated_at = clock_timestamp()
      where selected_terms.assignment_id = assignment.id returning * into terms;
      update public.pachanga_referee_assignments assignments set
        status = 'declined', declined_at = clock_timestamp(), authority_used = authority,
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      if assignment.replaces_assignment_id is not null then
        update public.pachanga_referee_assignments originals set
          replacement_pending_assignment_id = null,
          revision = originals.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where originals.id = assignment.replaces_assignment_id
          and originals.replacement_pending_assignment_id = assignment.id;
      end if;
      target_status := 'declined'; target_reason := 'Contraoferta rechazada';
      target_user_id := profile.user_id;

    elsif action_name = 'assignment.confirm' then
      if assignment.status <> 'accepted' or terms.terms_status <> 'ACCEPTED'
         or assignment.schedule_state <> 'CURRENT' then
        raise exception 'REFEREE_ASSIGNMENT_NOT_CONFIRMABLE' using errcode = 'PT409';
      end if;
      update public.pachanga_referee_assignments assignments set
        status = 'confirmed', confirmed_at = clock_timestamp(), authority_used = authority,
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      target_status := 'confirmed'; target_reason := 'Arbitraje confirmado';
      target_user_id := profile.user_id;

    elsif action_name = 'assignment.cancel' then
      if assignment.status not in ('proposed', 'accepted', 'confirmed') then
        raise exception 'REFEREE_ASSIGNMENT_NOT_CANCELLABLE' using errcode = 'PT409';
      end if;
      if profile.user_id = actor_id then authority := 'referee_owner'; end if;
      if assignment.replacement_pending_assignment_id is not null then
        update public.pachanga_referee_assignments replacements set
          status = 'cancelled', cancelled_at = clock_timestamp(), cancelled_by = actor_id,
          cancel_reason_code = 'original_cancelled',
          cancel_reason_text = 'La asignacion original fue cancelada.',
          revision = replacements.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where replacements.id = assignment.replacement_pending_assignment_id
          and replacements.status in ('proposed', 'accepted');
      end if;
      update public.pachanga_referee_assignments assignments set
        status = 'cancelled', cancelled_at = clock_timestamp(), cancelled_by = actor_id,
        cancel_reason_code = left(coalesce(nullif(payload ->> 'reasonCode', ''), 'cancelled'), 80),
        cancel_reason_text = left(coalesce(payload ->> 'reasonText', ''), 800),
        replacement_pending_assignment_id = null,
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      if assignment.replaces_assignment_id is not null then
        update public.pachanga_referee_assignments originals set
          replacement_pending_assignment_id = null,
          revision = originals.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where originals.id = assignment.replaces_assignment_id
          and originals.replacement_pending_assignment_id = assignment.id;
      end if;
      target_status := 'cancelled'; target_reason := 'Arbitraje cancelado';
      target_user_id := case when profile.user_id = actor_id then assignment.proposed_by else profile.user_id end;

    elsif action_name = 'assignment.replace' then
      if assignment.status <> 'confirmed' or assignment.schedule_state <> 'CURRENT'
         or assignment.replacement_pending_assignment_id is not null then
        raise exception 'REFEREE_ASSIGNMENT_NOT_REPLACEABLE' using errcode = 'PT409';
      end if;
      target_profile_id := nullif(payload ->> 'newRefereeProfileId', '')::uuid;
      select * into original_profile from public.pachanga_referee_profiles profiles
      where profiles.id = target_profile_id;
      if not found or original_profile.id = assignment.referee_profile_id
         or original_profile.operational_status <> 'active'
         or not original_profile.available_for_assignments then
        raise exception 'REFEREE_PROFILE_NOT_ASSIGNABLE' using errcode = '42501';
      end if;
      if nullif(payload ->> 'newAssignmentId', '')::uuid is null then
        raise exception 'INVALID_REPLACEMENT_ASSIGNMENT_ID' using errcode = '22023';
      end if;
      target_deadline := coalesce(nullif(payload ->> 'responseDeadline', '')::timestamptz,
        clock_timestamp() + interval '72 hours');
      if target_deadline <= clock_timestamp() or target_deadline > clock_timestamp() + interval '30 days' then
        raise exception 'INVALID_ASSIGNMENT_DEADLINE' using errcode = '22023';
      end if;
      select * into original_terms from private.pachanga_referee_assignment_terms selected_terms
      where selected_terms.assignment_id = assignment.id;
      insert into public.pachanga_referee_assignments(
        id, referee_profile_id, canonical_match_id, assignment_role,
        requester_kind, requester_team_id, requester_club_id,
        requester_competition_id, competition_id, source_kind, source_group_id,
        source_id, status, scheduled_start, scheduled_end, timezone,
        schedule_source_revision, effective_scheduled_start,
        effective_scheduled_end, effective_timezone, effective_schedule_revision,
        proposed_by, authority_used, proposal_message, response_deadline,
        replaces_assignment_id, revision, server_sequence
      ) values (
        (payload ->> 'newAssignmentId')::uuid, original_profile.id,
        assignment.canonical_match_id, assignment.assignment_role,
        assignment.requester_kind, assignment.requester_team_id,
        assignment.requester_club_id, assignment.requester_competition_id,
        assignment.competition_id, assignment.source_kind, assignment.source_group_id,
        assignment.source_id, 'proposed', assignment.scheduled_start,
        assignment.scheduled_end, assignment.timezone, assignment.schedule_source_revision,
        assignment.effective_scheduled_start, assignment.effective_scheduled_end,
        assignment.effective_timezone, assignment.effective_schedule_revision,
        actor_id, authority, left(coalesce(payload ->> 'message', ''), 800),
        target_deadline, assignment.id, 1, nextval('private.pachanga_referee_sequence')
      ) returning * into original;
      terms := private.pachanga_referee_terms_input_v1(original.id, actor_id, payload, original_terms);
      update public.pachanga_referee_assignments assignments set
        replacement_pending_assignment_id = original.id,
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      snapshot := jsonb_build_object(
        'assignment', private.pachanga_referee_assignment_document_v1(assignment.id, true),
        'replacement', private.pachanga_referee_assignment_document_v1(original.id, true)
      );
      event_payload := jsonb_build_object('status', assignment.status,
        'replacementAssignmentId', original.id, 'termsStatus', terms.terms_status);
      perform private.pachanga_referee_refresh_statistics_v1(assignment.referee_profile_id, 'incremental');
      perform private.pachanga_referee_refresh_statistics_v1(original.referee_profile_id, 'incremental');
      perform private.pachanga_referee_notify_v1(
        original_profile.user_id, 'referee_assignment_replacement_proposed',
        'Propuesta de sustitucion', 'Te han propuesto arbitrar este partido.',
        '/mis-asignaciones-arbitrales?assignment=' || original.id::text,
        jsonb_build_object('assignmentId', original.id,
          'canonicalMatchId', original.canonical_match_id),
        'referee-replacement:' || operation_id::text || ':' || original_profile.user_id::text
      );
      perform set_config('pachangas.referee_reason', '', true);
      return private.pachanga_referee_store_command_v1(
        operation_id, actor_id, 'authenticated', action_name,
        'referee_assignment', assignment.id::text, request_hash,
        assignment.revision, left(coalesce(payload ->> 'reason', action_name), 120),
        event_payload, snapshot, assignment.referee_profile_id,
        assignment.requester_club_id, assignment.canonical_match_id,
        original_profile.user_id, assignment.requester_team_id, 'private', client_metadata
      );

    else
      if assignment.status not in ('accepted', 'confirmed')
         or assignment.schedule_state not in ('RECONFIRMATION_REQUIRED', 'STALE_SCHEDULE') then
        raise exception 'REFEREE_ASSIGNMENT_RECONFIRMATION_NOT_REQUIRED' using errcode = 'PT409';
      end if;
      match_snapshot := private.pachanga_referee_match_snapshot_v1(
        assignment.source_kind, assignment.source_group_id, assignment.source_id
      );
      update public.pachanga_referee_assignments assignments set
        effective_scheduled_start = (match_snapshot ->> 'effectiveScheduledStart')::timestamptz,
        effective_scheduled_end = (match_snapshot ->> 'effectiveScheduledEnd')::timestamptz,
        effective_timezone = match_snapshot ->> 'effectiveTimezone',
        effective_schedule_revision = (match_snapshot ->> 'effectiveScheduleRevision')::bigint,
        venue_id = nullif(match_snapshot ->> 'venueId', '')::uuid,
        venue_label = nullif(match_snapshot ->> 'venueLabel', ''),
        venue_status = match_snapshot ->> 'venueStatus',
        schedule_state = 'CURRENT', reconfirmed_at = clock_timestamp(),
        revision = assignments.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where assignments.id = assignment.id returning * into assignment;
      target_status := 'reconfirmed'; target_reason := 'Nuevo horario reconfirmado';
      target_user_id := assignment.proposed_by;
    end if;
  end if;

  perform private.pachanga_referee_refresh_statistics_v1(assignment.referee_profile_id, 'incremental');
  snapshot := jsonb_build_object(
    'assignment', private.pachanga_referee_assignment_document_v1(assignment.id, true)
  );
  event_payload := jsonb_build_object(
    'status', assignment.status,
    'scheduleState', assignment.schedule_state,
    'termsStatus', terms.terms_status,
    'feeMode', terms.fee_mode
  );
  perform private.pachanga_referee_notify_v1(
    target_user_id,
    case target_status
      when 'proposed' then 'referee_assignment_proposed'
      when 'accepted' then 'referee_assignment_accepted'
      when 'declined' then 'referee_assignment_declined'
      when 'confirmed' then 'referee_assignment_confirmed'
      when 'cancelled' then 'referee_assignment_cancelled'
      when 'expired' then 'referee_assignment_expired'
      when 'countered' then 'referee_assignment_countered'
      when 'reconfirmed' then 'referee_assignment_reconfirmed'
      else 'referee_assignment_changed' end,
    target_reason,
    'La asignacion arbitral ha cambiado. Abre el detalle para ver el estado confirmado.',
    '/mis-asignaciones-arbitrales?assignment=' || assignment.id::text,
    jsonb_build_object('assignmentId', assignment.id,
      'canonicalMatchId', assignment.canonical_match_id),
    'referee-assignment-beta:' || operation_id::text || ':' || coalesce(target_user_id::text, 'none')
  );
  perform set_config('pachangas.referee_reason', '', true);
  return private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', action_name, 'referee_assignment',
    assignment.id::text, request_hash, assignment.revision,
    left(coalesce(payload ->> 'reason', action_name), 120), event_payload,
    snapshot, assignment.referee_profile_id, assignment.requester_club_id,
    assignment.canonical_match_id, target_user_id, assignment.requester_team_id,
    'private', client_metadata
  );
exception
  when unique_violation then raise exception 'REFEREE_ASSIGNMENT_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function public.expire_pachanga_referee_assignments_v1(
  operation_id uuid,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare assignment public.pachanga_referee_assignments%rowtype;
declare expired_count integer := 0;
begin
  if not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'SERVICE_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  perform private.pachanga_referee_assert_assignment_beta_v1();
  for assignment in
    select assignments.* from public.pachanga_referee_assignments assignments
    where assignments.status = 'proposed' and assignments.response_deadline <= clock_timestamp()
    order by assignments.response_deadline, assignments.id for update skip locked
  loop
    perform set_config('pachangas.referee_reason', 'assignment.expire', true);
    update public.pachanga_referee_assignments assignments set
      status = 'expired', expired_at = clock_timestamp(),
      revision = assignments.revision + 1,
      server_sequence = nextval('private.pachanga_referee_sequence')
    where assignments.id = assignment.id;
    update private.pachanga_referee_assignment_terms terms set
      terms_status = 'DECLINED', declined_at = clock_timestamp(),
      terms_revision = terms.terms_revision + 1,
      server_sequence = nextval('private.pachanga_referee_sequence'), updated_at = clock_timestamp()
    where terms.assignment_id = assignment.id;
    if assignment.replaces_assignment_id is not null then
      update public.pachanga_referee_assignments originals set
        replacement_pending_assignment_id = null,
        revision = originals.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where originals.id = assignment.replaces_assignment_id
        and originals.replacement_pending_assignment_id = assignment.id;
    end if;
    expired_count := expired_count + 1;
  end loop;
  perform set_config('pachangas.referee_reason', '', true);
  return jsonb_build_object('operationId', operation_id, 'expired', expired_count,
    'confirmedAt', clock_timestamp(), 'clientMetadataAccepted', jsonb_typeof(client_metadata) = 'object');
end;
$$;

revoke all on function public.command_pachanga_referee_assignment_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_referee_assignment_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;
revoke all on function public.expire_pachanga_referee_assignments_v1(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.expire_pachanga_referee_assignments_v1(uuid, jsonb)
  to service_role;
revoke all on function private.pachanga_referee_assignment_document_v1(uuid, boolean),
  private.pachanga_referee_terms_input_v1(uuid, uuid, jsonb, private.pachanga_referee_assignment_terms)
  from public, anon, authenticated;

create or replace function public.command_pachanga_referee_officiating_v1(
  operation_id uuid,
  target_assignment_id uuid,
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
declare
  actor_id uuid := auth.uid();
  action_name text := lower(trim(coalesce(command_action, '')));
  payload jsonb := coalesce(command_payload, '{}'::jsonb);
  request_hash text;
  replay jsonb;
  assignment public.pachanga_referee_assignments%rowtype;
  profile public.pachanga_referee_profiles%rowtype;
  competition public.pachanga_competitions%rowtype;
  context_row public.pachanga_competition_match_contexts%rowtype;
  event_row public.pachanga_competition_disciplinary_events%rowtype;
  cycle_row public.pachanga_competition_disciplinary_cycles%rowtype;
  catalog_row public.pachanga_competition_discipline_rule_catalogs%rowtype;
  selected_player_id uuid;
  selected_entry_id uuid;
  selected_card_code text;
  selected_context text;
  selected_minute integer;
  selected_period text;
  selected_public_category text;
  selected_public_summary text;
  selected_private_reason text;
  selected_evidence jsonb;
  selected_cycle_id uuid;
  rule_outcome jsonb;
  event_revision_id uuid;
  counter_checksum text;
  state_checksum text;
  changed_count integer;
  competition_revision bigint;
  sequence_value bigint;
  invalidations jsonb;
  discipline_response jsonb;
  observation_revision bigint;
  observation_id uuid;
  snapshot jsonb;
  target_requester_id uuid;
  locked_match_context_id uuid;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if operation_id is null or target_assignment_id is null
     or expected_revision is null or expected_revision < 1
     or action_name not in ('discipline.record', 'result.observe') then
    raise exception 'REFEREE_OFFICIATING_ENVELOPE_INVALID' using errcode = '22023';
  end if;
  if jsonb_typeof(payload) <> 'object' or pg_column_size(payload) > 32768
     or payload ?| array[
       'actorId', 'createdBy', 'reportingRefereeProfileId', 'refereeAssignmentId',
       'serverSequence', 'confirmedRevision', 'sanction', 'counter', 'waiver',
       'appeal', 'officialResult', 'standings', 'rating', 'facets', 'grl', 'serviceRole'
     ] then raise exception 'REFEREE_OFFICIATING_SERVER_FIELDS_FORBIDDEN' using errcode = '22023'; end if;
  perform private.pachanga_referee_assert_assignment_beta_v1();
  request_hash := private.pachanga_referee_request_hash_v1(
    action_name, target_assignment_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  select assignments.competition_match_context_id into locked_match_context_id
  from public.pachanga_referee_assignments assignments
  where assignments.id = target_assignment_id;
  if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if locked_match_context_id is not null then
    perform contexts.id
    from public.pachanga_competition_match_contexts contexts
    where contexts.id = locked_match_context_id
    for update;
    if not found then
      raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;
  select * into assignment from public.pachanga_referee_assignments assignments
  where assignments.id = target_assignment_id for update;
  if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if assignment.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  select * into profile from public.pachanga_referee_profiles profiles
  where profiles.id = assignment.referee_profile_id;
  if profile.user_id <> actor_id then raise exception 'REFEREE_PROFILE_OWNER_REQUIRED' using errcode = '42501'; end if;
  if assignment.status <> 'confirmed' or assignment.schedule_state <> 'CURRENT' then
    raise exception 'REFEREE_CURRENT_CONFIRMED_ASSIGNMENT_REQUIRED' using errcode = '42501';
  end if;
  if assignment.competition_id is null or assignment.competition_match_context_id is null then
    raise exception 'REFEREE_COMPETITION_MATCH_REQUIRED' using errcode = '42501';
  end if;
  select * into context_row from public.pachanga_competition_match_contexts contexts
  where contexts.id = assignment.competition_match_context_id
    and contexts.canonical_match_id = assignment.canonical_match_id
    and contexts.competition_id = assignment.competition_id
    and contexts.status in ('ready', 'in_progress', 'played', 'result_pending', 'official')
  for update;
  if not found then raise exception 'REFEREE_MATCH_STATE_NOT_OFFICIABLE' using errcode = '42501'; end if;

  if action_name = 'result.observe' then
    if payload - array['homeScore', 'awayScore', 'privateNote'] <> '{}'::jsonb then
      raise exception 'REFEREE_RESULT_OBSERVATION_INVALID' using errcode = '22023';
    end if;
    select coalesce(max(observations.observation_revision), 0) + 1
      into observation_revision
    from private.pachanga_referee_result_observations observations
    where observations.assignment_id = assignment.id;
    insert into private.pachanga_referee_result_observations(
      assignment_id, referee_profile_id, canonical_match_id,
      home_score, away_score, private_note, operation_id,
      observation_revision, created_by
    ) values (
      assignment.id, assignment.referee_profile_id, assignment.canonical_match_id,
      nullif(payload ->> 'homeScore', '')::integer,
      nullif(payload ->> 'awayScore', '')::integer,
      left(coalesce(payload ->> 'privateNote', ''), 1200), operation_id,
      observation_revision, actor_id
    ) returning id into observation_id;
    perform set_config('pachangas.referee_reason', 'result.observe', true);
    update public.pachanga_referee_assignments assignments set
      revision = assignments.revision + 1,
      server_sequence = nextval('private.pachanga_referee_sequence')
    where assignments.id = assignment.id returning * into assignment;
    snapshot := jsonb_build_object(
      'assignment', private.pachanga_referee_assignment_document_v1(assignment.id, true),
      'resultObservation', jsonb_build_object(
        'id', observation_id, 'revision', observation_revision,
        'homeScore', (payload ->> 'homeScore')::integer,
        'awayScore', (payload ->> 'awayScore')::integer,
        'authority', 'PRIVATE_REFEREE_EVIDENCE',
        'officialResultChanged', false
      )
    );
    perform set_config('pachangas.referee_reason', '', true);
    return private.pachanga_referee_store_command_v1(
      operation_id, actor_id, 'authenticated', action_name,
      'referee_assignment', assignment.id::text, request_hash,
      assignment.revision, action_name,
      jsonb_build_object('observationId', observation_id,
        'officialResultChanged', false), snapshot,
      assignment.referee_profile_id, assignment.requester_club_id,
      assignment.canonical_match_id, assignment.proposed_by,
      assignment.requester_team_id, 'private', client_metadata
    );
  end if;

  if payload - array[
    'playerProfileId', 'cardTypeCode', 'context', 'minute', 'period',
    'publicReasonCategory', 'publicSummary', 'evidenceRefs', 'privateNotes'
  ] <> '{}'::jsonb then
    raise exception 'DISCIPLINE_EVENT_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, false);
  select * into competition from public.pachanga_competitions competitions
  where competitions.id = assignment.competition_id for update;
  selected_player_id := nullif(payload ->> 'playerProfileId', '')::uuid;
  selected_card_code := upper(trim(coalesce(payload ->> 'cardTypeCode', '')));
  selected_context := lower(trim(coalesce(payload ->> 'context', 'in_match')));
  selected_minute := nullif(payload ->> 'minute', '')::integer;
  selected_period := nullif(trim(payload ->> 'period'), '');
  selected_public_category := nullif(trim(payload ->> 'publicReasonCategory'), '');
  selected_public_summary := left(coalesce(payload ->> 'publicSummary', ''), 500);
  selected_private_reason := left(coalesce(payload ->> 'privateNotes', ''), 4000);
  selected_evidence := coalesce(payload -> 'evidenceRefs', '[]'::jsonb);
  if selected_player_id is null or selected_card_code = ''
     or selected_context not in ('pre_match', 'in_match', 'interval', 'post_match', 'venue')
     or selected_context = 'in_match' and selected_minute is null
     or selected_minute is not null and selected_minute not between 0 and 300
     or jsonb_typeof(selected_evidence) <> 'array'
     or jsonb_array_length(selected_evidence) > 20
     or pg_column_size(selected_evidence) > 16000 then
    raise exception 'DISCIPLINE_EVENT_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  catalog_row := private.pachanga_competition_discipline_ensure_catalog_v1(
    assignment.competition_id, context_row.rule_revision_id, actor_id
  );
  if selected_public_category is not null and not exists (
    select 1 from jsonb_array_elements_text(catalog_row.public_reason_categories) categories(value)
    where categories.value = selected_public_category
  ) then raise exception 'DISCIPLINE_PUBLIC_REASON_NOT_ALLOWED' using errcode = '22023'; end if;
  rule_outcome := private.pachanga_competition_discipline_rule_outcome_v1(
    context_row.rule_revision_id, selected_card_code
  );
  selected_entry_id := private.pachanga_competition_discipline_match_entry_v1(
    assignment.canonical_match_id, selected_player_id
  );
  selected_cycle_id := private.pachanga_competition_discipline_resolve_cycle_v1(
    context_row.id, actor_id
  );
  select * into cycle_row from public.pachanga_competition_disciplinary_cycles cycles
  where cycles.id = selected_cycle_id for update;
  insert into public.pachanga_competition_disciplinary_events(
    competition_id, canonical_match_id, competition_match_context_id,
    match_sheet_id, cycle_id, rule_revision_id, player_profile_id, entry_id,
    current_card_type_code, creation_operation_id, created_by,
    referee_assignment_id, reporting_referee_profile_id
  ) values (
    assignment.competition_id, assignment.canonical_match_id, context_row.id,
    (select sheets.id from public.pachanga_competition_match_sheets sheets
      where sheets.canonical_match_id = assignment.canonical_match_id),
    selected_cycle_id, context_row.rule_revision_id, selected_player_id,
    selected_entry_id, selected_card_code, operation_id, actor_id,
    assignment.id, assignment.referee_profile_id
  ) returning * into event_row;
  insert into public.pachanga_competition_disciplinary_event_revisions(
    disciplinary_event_id, version, player_profile_id, entry_id,
    card_type_code, event_context, match_minute, period_code, event_status,
    public_reason_category, public_summary, rule_outcome, correction_reason,
    operation_id, created_by
  ) values (
    event_row.id, 1, selected_player_id, selected_entry_id,
    selected_card_code, selected_context, selected_minute, selected_period,
    'active', selected_public_category, selected_public_summary, rule_outcome,
    'Initial event reported by confirmed referee', operation_id, actor_id
  ) returning id into event_revision_id;
  update public.pachanga_competition_disciplinary_events events set
    current_revision_id = event_revision_id
  where events.id = event_row.id;
  if jsonb_array_length(selected_evidence) > 0 or selected_private_reason <> '' then
    insert into private.pachanga_competition_discipline_evidence(
      competition_id, subject_type, subject_id, evidence_refs,
      private_notes, operation_id, actor_id, server_sequence
    ) values (
      assignment.competition_id, 'DISCIPLINARY_EVENT', event_row.id,
      selected_evidence, selected_private_reason, operation_id, actor_id,
      event_row.server_sequence
    );
  end if;
  counter_checksum := private.pachanga_competition_discipline_rebuild_counters_v1(
    selected_cycle_id, selected_player_id
  );
  changed_count := private.pachanga_competition_discipline_reconcile_sanctions_v1(
    selected_cycle_id, selected_player_id, actor_id, 'Referee event recorded'
  );
  perform private.pachanga_competition_discipline_guard_locked_squads_v1(
    assignment.competition_id, selected_player_id
  );
  state_checksum := private.pachanga_competition_discipline_rebuild_player_state_v1(
    selected_cycle_id, selected_player_id
  );
  update public.pachanga_competitions competitions set
    discipline_revision = competitions.discipline_revision + 1
  where competitions.id = assignment.competition_id
  returning competitions.discipline_revision into competition_revision;
  sequence_value := nextval('private.pachanga_competition_sequence');
  invalidations := jsonb_build_array(
    jsonb_build_object('entityType', 'competition_discipline',
      'entityId', assignment.competition_id, 'revision', competition_revision),
    jsonb_build_object('entityType', 'competition_discipline_match',
      'entityId', assignment.canonical_match_id, 'revision', competition_revision),
    jsonb_build_object('entityType', 'competition_discipline_player',
      'entityId', selected_player_id, 'revision', competition_revision)
  );
  discipline_response := private.pachanga_competition_discipline_store_command_v1(
    operation_id, actor_id, 'referee.event.record', assignment.canonical_match_id,
    assignment.competition_id, competition_revision, sequence_value, request_hash,
    coalesce(client_metadata, '{}'::jsonb),
    jsonb_build_object(
      'eventId', event_row.id, 'assignmentId', assignment.id,
      'refereeProfileId', assignment.referee_profile_id,
      'cardTypeCode', selected_card_code, 'counterChecksum', counter_checksum,
      'playerStateChecksum', state_checksum,
      'derivedSanctionChanges', changed_count
    ),
    jsonb_build_object(
      'event', jsonb_build_object(
        'id', event_row.id, 'canonicalMatchId', assignment.canonical_match_id,
        'assignmentId', assignment.id, 'playerProfileId', selected_player_id,
        'cardTypeCode', selected_card_code, 'status', 'active'
      ),
      'counterChecksum', counter_checksum,
      'playerStateChecksum', state_checksum
    ), invalidations
  );
  perform set_config('pachangas.referee_reason', 'discipline.record', true);
  update public.pachanga_referee_assignments assignments set
    revision = assignments.revision + 1,
    server_sequence = nextval('private.pachanga_referee_sequence')
  where assignments.id = assignment.id returning * into assignment;
  perform private.pachanga_referee_refresh_statistics_v1(
    assignment.referee_profile_id, 'incremental'
  );
  snapshot := jsonb_build_object(
    'assignment', private.pachanga_referee_assignment_document_v1(assignment.id, true),
    'discipline', discipline_response -> 'snapshot',
    'r4cOfficialResultChanged', false
  );
  perform set_config('pachangas.referee_reason', '', true);
  return private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', action_name,
    'referee_assignment', assignment.id::text, request_hash,
    assignment.revision, action_name,
    jsonb_build_object('eventId', event_row.id,
      'competitionDisciplineRevision', competition_revision,
      'r4cOfficialResultChanged', false), snapshot,
    assignment.referee_profile_id, assignment.requester_club_id,
    assignment.canonical_match_id, assignment.proposed_by,
    assignment.requester_team_id, 'private', client_metadata
  );
exception
  when unique_violation then raise exception 'REFEREE_OFFICIATING_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function private.pachanga_referee_statistics_document_v1(target_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'proposalsReceived', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id),
    'assignmentsAccepted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.accepted_at is not null),
    'assignmentsDeclined', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.declined_at is not null),
    'assignmentsConfirmed', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.confirmed_at is not null),
    'matchesCompleted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed'),
    'individualMatchesCompleted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed' and a.competition_id is null),
    'competitionMatchesCompleted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed' and a.competition_id is not null),
    'leagueMatchesCompleted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed' and a.source_kind = 'competition_generated'),
    'replacements', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'replaced'),
    'cancellations', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'cancelled'),
    'activeClubRelationships', (select count(*) from public.pachanga_club_referee_relationships r where r.referee_profile_id = target_profile_id and r.status = 'active'),
    'lastCompletedAt', (select max(a.completed_at) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed'),
    'disciplineStatsStatus', 'CANONICAL_R5',
    'yellowCardsShown', (select count(*) from public.pachanga_competition_disciplinary_events e where e.reporting_referee_profile_id = target_profile_id and e.status = 'active' and e.current_card_type_code = 'YELLOW'),
    'redCardsShown', (select count(*) from public.pachanga_competition_disciplinary_events e where e.reporting_referee_profile_id = target_profile_id and e.status = 'active' and e.current_card_type_code = 'RED'),
    'blueCardsShown', (select count(*) from public.pachanga_competition_disciplinary_events e where e.reporting_referee_profile_id = target_profile_id and e.status = 'active' and e.current_card_type_code = 'BLUE')
  );
$$;

create or replace function private.pachanga_referee_refresh_statistics_v1(
  target_profile_id uuid,
  refresh_mode text default 'incremental'
)
returns public.pachanga_referee_statistics_snapshots
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  document jsonb;
  digest_value text;
  sequence_value bigint := nextval('private.pachanga_referee_sequence');
  saved public.pachanga_referee_statistics_snapshots%rowtype;
begin
  if refresh_mode not in ('incremental', 'full_rebuild') then
    raise exception 'INVALID_STATS_REFRESH_MODE' using errcode = '22023';
  end if;
  if not exists (select 1 from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id) then
    raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002';
  end if;
  document := private.pachanga_referee_statistics_document_v1(target_profile_id);
  digest_value := encode(extensions.digest(convert_to(document::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.pachanga_referee_statistics_snapshots(
    referee_profile_id, proposals_received, assignments_accepted, assignments_declined,
    assignments_confirmed, matches_completed, individual_matches_completed,
    competition_matches_completed, league_matches_completed, replacements,
    cancellations, active_club_relationships, last_completed_at,
    discipline_stats_status, yellow_cards_shown, red_cards_shown, blue_cards_shown,
    revision, checksum, server_sequence, updated_at
  ) values (
    target_profile_id,
    (document ->> 'proposalsReceived')::bigint,
    (document ->> 'assignmentsAccepted')::bigint,
    (document ->> 'assignmentsDeclined')::bigint,
    (document ->> 'assignmentsConfirmed')::bigint,
    (document ->> 'matchesCompleted')::bigint,
    (document ->> 'individualMatchesCompleted')::bigint,
    (document ->> 'competitionMatchesCompleted')::bigint,
    (document ->> 'leagueMatchesCompleted')::bigint,
    (document ->> 'replacements')::bigint,
    (document ->> 'cancellations')::bigint,
    (document ->> 'activeClubRelationships')::bigint,
    nullif(document ->> 'lastCompletedAt', '')::timestamptz,
    'CANONICAL_R5',
    (document ->> 'yellowCardsShown')::integer,
    (document ->> 'redCardsShown')::integer,
    (document ->> 'blueCardsShown')::integer,
    1, digest_value, sequence_value, clock_timestamp()
  ) on conflict (referee_profile_id) do update set
    proposals_received = excluded.proposals_received,
    assignments_accepted = excluded.assignments_accepted,
    assignments_declined = excluded.assignments_declined,
    assignments_confirmed = excluded.assignments_confirmed,
    matches_completed = excluded.matches_completed,
    individual_matches_completed = excluded.individual_matches_completed,
    competition_matches_completed = excluded.competition_matches_completed,
    league_matches_completed = excluded.league_matches_completed,
    replacements = excluded.replacements,
    cancellations = excluded.cancellations,
    active_club_relationships = excluded.active_club_relationships,
    last_completed_at = excluded.last_completed_at,
    discipline_stats_status = excluded.discipline_stats_status,
    yellow_cards_shown = excluded.yellow_cards_shown,
    red_cards_shown = excluded.red_cards_shown,
    blue_cards_shown = excluded.blue_cards_shown,
    revision = public.pachanga_referee_statistics_snapshots.revision + 1,
    checksum = excluded.checksum,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at
  returning * into saved;
  return saved;
end;
$$;

revoke all on function public.command_pachanga_referee_officiating_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_referee_officiating_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;
revoke all on function private.pachanga_referee_statistics_document_v1(uuid),
  private.pachanga_referee_refresh_statistics_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_referee_public_fee_fingerprint_v1(
  target_profile_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'feeMode', profiles.public_fee_mode,
    'fromCents', profiles.public_fee_from_cents,
    'currency', profiles.public_fee_currency,
    'paymentManagedByPachangasIq', false
  )::text, 'UTF8'), 'sha256'), 'hex')
  from public.pachanga_referee_profiles profiles
  where profiles.id = target_profile_id
    and profiles.public_fee_mode is not null;
$$;

create or replace function private.pachanga_referee_public_fee_consent_snapshot_v1(
  target_profile_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  selected private.pachanga_referee_public_fee_consents%rowtype;
  current_fingerprint text;
begin
  select * into selected
  from private.pachanga_referee_public_fee_consents consents
  where consents.referee_profile_id = target_profile_id
  order by consents.server_sequence desc, consents.id desc
  limit 1;
  current_fingerprint := private.pachanga_referee_public_fee_fingerprint_v1(target_profile_id);
  if selected.id is null then
    return jsonb_build_object('consented', false, 'matchesCurrentContent', false);
  end if;
  return jsonb_build_object(
    'consented', true,
    'matchesCurrentContent', selected.content_fingerprint = current_fingerprint,
    'informationCorrect', selected.information_correct,
    'outOfPlatformPaymentAcknowledged', selected.out_of_platform_payment_acknowledged,
    'subjectRevision', selected.subject_revision,
    'serverSequence', selected.server_sequence,
    'consentedAt', selected.consented_at
  );
end;
$$;

create or replace function private.pachanga_referee_public_fee_consent_valid_v1(
  target_profile_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    (private.pachanga_referee_public_fee_consent_snapshot_v1(target_profile_id)
      ->> 'matchesCurrentContent')::boolean,
    false
  );
$$;

create or replace function public.command_pachanga_referee_public_fee_v1(
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
declare
  actor_id uuid := auth.uid();
  action_name text := lower(trim(coalesce(command_action, '')));
  payload jsonb := coalesce(command_payload, '{}'::jsonb);
  profile public.pachanga_referee_profiles%rowtype;
  request_hash text;
  replay jsonb;
  selected_mode text;
  selected_from integer;
  selected_currency text;
  fingerprint text;
  sequence_value bigint;
  snapshot jsonb;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 1
     or action_name not in ('public_fee.configure', 'public_fee.publish', 'public_fee.unpublish')
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(payload) > 8192 then
    raise exception 'INVALID_REFEREE_PUBLIC_FEE_COMMAND' using errcode = '22023';
  end if;
  if payload ?| array[
    'actorId', 'serverSequence', 'confirmedRevision', 'paymentStatus',
    'paymentIntent', 'stripeAccount', 'bankAccount', 'serviceRole'
  ] then raise exception 'REFEREE_SERVER_FIELDS_FORBIDDEN' using errcode = '22023'; end if;
  perform private.pachanga_referee_assert_flags_v1(true, false, false, false, false);
  request_hash := private.pachanga_referee_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  perform private.pachanga_referee_rate_limit_v1(actor_id, action_name);
  select * into profile
  from public.pachanga_referee_profiles profiles
  where profiles.id = aggregate_id for update;
  if not found then raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  if profile.user_id <> actor_id then
    raise exception 'REFEREE_PROFILE_OWNER_REQUIRED' using errcode = '42501';
  end if;
  if profile.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  sequence_value := nextval('private.pachanga_referee_sequence');

  if action_name = 'public_fee.configure' then
    selected_mode := upper(trim(coalesce(payload ->> 'feeMode', '')));
    selected_from := nullif(payload ->> 'fromCents', '')::integer;
    selected_currency := upper(trim(coalesce(payload ->> 'currency', 'EUR')));
    if selected_mode not in ('FREE', 'FIXED', 'NEGOTIABLE', 'VOLUNTEER')
       or selected_currency !~ '^[A-Z]{3}$'
       or selected_from is not null and selected_from not between 0 and 10000000
       or selected_mode = 'FIXED' and selected_from is null
       or selected_mode in ('FREE', 'VOLUNTEER') and selected_from is not null then
      raise exception 'REFEREE_PUBLIC_FEE_INVALID' using errcode = '22023';
    end if;
    update public.pachanga_referee_profiles profiles set
      public_fee_visibility = false,
      public_fee_mode = selected_mode,
      public_fee_from_cents = selected_from,
      public_fee_currency = selected_currency,
      revision = profiles.revision + 1,
      server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where profiles.id = profile.id returning * into profile;

  elsif action_name = 'public_fee.publish' then
    if profile.operational_status <> 'active' or profile.visibility <> 'public'
       or profile.marketplace_status <> 'listed' or profile.public_fee_mode is null then
      raise exception 'REFEREE_PUBLIC_FEE_PUBLICATION_NOT_ALLOWED' using errcode = 'PT409';
    end if;
    if coalesce((payload ->> 'informationCorrect')::boolean, false) is not true
       or coalesce((payload ->> 'outOfPlatformPaymentAcknowledged')::boolean, false) is not true then
      raise exception 'REFEREE_PUBLIC_FEE_CONFIRMATIONS_REQUIRED' using errcode = '22023';
    end if;
    fingerprint := private.pachanga_referee_public_fee_fingerprint_v1(profile.id);
    insert into private.pachanga_referee_public_fee_consents(
      operation_id, referee_profile_id, actor_id, content_fingerprint,
      information_correct, out_of_platform_payment_acknowledged,
      subject_revision, server_sequence, consented_at
    ) values (
      operation_id, profile.id, actor_id, fingerprint, true, true,
      profile.revision + 1, sequence_value, clock_timestamp()
    );
    update public.pachanga_referee_profiles profiles set
      public_fee_visibility = true,
      revision = profiles.revision + 1,
      server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where profiles.id = profile.id returning * into profile;

  else
    update public.pachanga_referee_profiles profiles set
      public_fee_visibility = false,
      revision = profiles.revision + 1,
      server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where profiles.id = profile.id returning * into profile;
  end if;

  snapshot := jsonb_build_object(
    'profileId', profile.id,
    'publicFee', jsonb_build_object(
      'visible', profile.public_fee_visibility,
      'feeMode', profile.public_fee_mode,
      'fromCents', profile.public_fee_from_cents,
      'currency', profile.public_fee_currency,
      'paymentManagedByPachangasIq', false,
      'consent', private.pachanga_referee_public_fee_consent_snapshot_v1(profile.id)
    ),
    'revision', profile.revision,
    'serverSequence', profile.server_sequence,
    'updatedAt', profile.updated_at
  );
  return private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', action_name, 'referee_public_fee',
    profile.id::text, request_hash, profile.revision, action_name,
    jsonb_build_object(
      'visible', profile.public_fee_visibility,
      'feeMode', profile.public_fee_mode,
      'paymentManagedByPachangasIq', false
    ), snapshot, profile.id, null, null, actor_id, null, 'private', client_metadata
  );
exception
  when unique_violation then raise exception 'REFEREE_PUBLIC_FEE_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_referee_public_fee_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_referee_public_fee_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_referee_public_fee_fingerprint_v1(uuid)'::regprocedure,
    'private.pachanga_referee_public_fee_consent_snapshot_v1(uuid)'::regprocedure,
    'private.pachanga_referee_public_fee_consent_valid_v1(uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;
