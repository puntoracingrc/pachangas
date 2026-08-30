-- Wave 8B: only versioned Team operational write authority.

set lock_timeout = '5s';
set statement_timeout = '5min';

create or replace function private.pachanga_platform_capabilities_v1(target_role text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case target_role
    when 'platform_owner' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend', 'roles.manage',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'billing.write', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read',
      'organizer_access.read', 'organizer_access.review', 'organizer_access.approve', 'organizer_access.override',
      'teams.operational.read', 'teams.operational.review', 'teams.operational.enforce',
      'teams.operational.appeals', 'teams.operational.health'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'billing.write', 'system.read', 'flags.read', 'flags.write', 'audit.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read',
      'organizer_access.read', 'organizer_access.review', 'organizer_access.approve',
      'teams.operational.read', 'teams.operational.review', 'teams.operational.enforce',
      'teams.operational.appeals', 'teams.operational.health'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read',
      'teams.operational.read', 'teams.operational.review', 'teams.operational.enforce',
      'teams.operational.appeals', 'teams.operational.health'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read', 'clubs.read', 'referees.read',
      'organizer_access.read', 'organizer_access.support', 'teams.operational.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read',
      'billing.read', 'billing.write', 'audit.read', 'teams.operational.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read', 'referees.health.read',
      'teams.operational.read', 'teams.operational.health'
    )
    else '[]'::jsonb
  end;
$$;

create or replace function private.pachanga_team_operational_safe_client_metadata_v1(
  target_metadata jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', left(nullif(trim(target_metadata ->> 'clientVersion'), ''), 80),
    'serviceWorkerVersion', left(nullif(trim(target_metadata ->> 'serviceWorkerVersion'), ''), 80),
    'installedMode', left(nullif(trim(target_metadata ->> 'installedMode'), ''), 24),
    'surface', left(nullif(trim(target_metadata ->> 'surface'), ''), 80),
    'deviceSession', left(nullif(trim(target_metadata ->> 'deviceSession'), ''), 80)
  ));
$$;

create or replace function private.pachanga_team_operational_owner_actor_v1(
  target_group_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare owner_id uuid;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  select groups.owner_id into owner_id
  from public.pachanga_groups groups
  where groups.id = target_group_id;
  if owner_id is null then raise exception 'TEAM_NOT_FOUND' using errcode = 'P0002'; end if;
  if owner_id <> actor_id then raise exception 'TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
  if exists (
    select 1 from private.pachanga_platform_user_states user_states
    where user_states.user_id = actor_id
      and (
        user_states.status = 'banned'
        or (user_states.status = 'suspended' and user_states.expires_at > statement_timestamp())
      )
  ) then
    raise exception 'ACTOR_OPERATIONALLY_SUSPENDED' using errcode = '42501';
  end if;
  return actor_id;
end;
$$;

create or replace function private.pachanga_team_operational_command_snapshot_v1(
  target_group_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(private.pachanga_team_operational_state_snapshot_v1(target_group_id), '{}'::jsonb)
    || jsonb_build_object(
      'restrictions', private.pachanga_team_operational_restrictions_snapshot_v1(target_group_id),
      'appeal', coalesce((
        select jsonb_build_object(
          'id', appeals.id,
          'status', appeals.status,
          'subjectRevision', appeals.subject_revision,
          'requestedOutcome', appeals.requested_outcome,
          'deadlineAt', appeals.deadline_at,
          'submittedAt', appeals.submitted_at,
          'safeResolutionMessage', appeals.safe_resolution_message,
          'revision', appeals.revision,
          'serverSequence', appeals.server_sequence,
          'updatedAt', appeals.updated_at
        )
        from private.pachanga_team_operational_appeals_v1 appeals
        where appeals.group_id = target_group_id
        order by appeals.server_sequence desc, appeals.id desc
        limit 1
      ), 'null'::jsonb)
    );
$$;

create or replace function private.pachanga_team_operational_commit_state_v1(
  target_group_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_lifecycle text,
  target_enforcement text,
  target_preset text,
  target_continuity text,
  target_public_message text,
  target_effective_from timestamptz,
  target_effective_until timestamptz,
  target_reason_code text,
  target_private_note text,
  target_evidence jsonb,
  target_source text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare state_row private.pachanga_team_operational_states_v1%rowtype;
declare next_revision bigint;
declare sequence_value bigint;
declare next_effective text;
begin
  select * into strict state_row
  from private.pachanga_team_operational_states_v1 states
  where states.group_id = target_group_id
  for update;
  next_revision := state_row.current_revision + 1;
  sequence_value := nextval('private.pachanga_team_operational_sequence_v1');
  next_effective := private.pachanga_team_operational_effective_status_v1(target_lifecycle, target_enforcement);

  update private.pachanga_team_operational_states_v1 states set
    lifecycle_status = target_lifecycle,
    enforcement_status = target_enforcement,
    effective_status = next_effective,
    restriction_preset = target_preset,
    continuity_policy = target_continuity,
    public_message = left(coalesce(target_public_message, ''), 500),
    effective_from = coalesce(target_effective_from, clock_timestamp()),
    effective_until = target_effective_until,
    current_revision = next_revision,
    server_sequence = sequence_value,
    source = target_source,
    last_operation_id = target_operation_id,
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where states.group_id = target_group_id
  returning * into state_row;

  insert into private.pachanga_team_operational_state_revisions_v1(
    group_id, revision, lifecycle_status, enforcement_status, effective_status,
    restriction_preset, continuity_policy, public_message, effective_from,
    effective_until, reason_code, private_note, evidence, source,
    operation_id, actor_id, actor_kind, server_sequence
  ) values (
    state_row.group_id, state_row.current_revision, state_row.lifecycle_status,
    state_row.enforcement_status, state_row.effective_status, state_row.restriction_preset,
    state_row.continuity_policy, state_row.public_message, state_row.effective_from,
    state_row.effective_until, left(target_reason_code, 120), left(coalesce(target_private_note, ''), 4000),
    coalesce(target_evidence, '{}'::jsonb), target_source, target_operation_id,
    target_actor_id, target_actor_kind, sequence_value
  );
  return private.pachanga_team_operational_command_snapshot_v1(target_group_id);
end;
$$;

create or replace function private.pachanga_team_operational_store_command_v1(
  target_operation_id uuid,
  target_group_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_request_hash text,
  target_expected_revision bigint,
  target_confirmed_revision bigint,
  target_client_metadata jsonb,
  target_reason_code text,
  target_response jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare sequence_value bigint := nextval('private.pachanga_team_operational_sequence_v1');
declare canonical_response jsonb;
begin
  canonical_response := jsonb_build_object(
    'operationId', target_operation_id,
    'action', target_action,
    'confirmedRevision', target_confirmed_revision,
    'serverSequence', sequence_value,
    'confirmedAt', clock_timestamp(),
    'snapshot', target_response
  );
  insert into private.pachanga_team_operational_events_v1(
    operation_id, group_id, event_kind, aggregate_revision, actor_id,
    actor_kind, reason_code, event_payload, server_sequence
  ) values (
    target_operation_id, target_group_id, target_action, target_confirmed_revision,
    target_actor_id, target_actor_kind, target_reason_code,
    jsonb_build_object('snapshot', target_response), sequence_value
  );
  insert into private.pachanga_team_operational_operation_receipts_v1(
    operation_id, group_id, actor_id, actor_kind, action, request_hash,
    expected_revision, confirmed_revision, server_sequence, client_metadata, response
  ) values (
    target_operation_id, target_group_id, target_actor_id, target_actor_kind,
    target_action, target_request_hash, target_expected_revision,
    target_confirmed_revision, sequence_value,
    private.pachanga_team_operational_safe_client_metadata_v1(target_client_metadata),
    canonical_response
  );
  return canonical_response;
end;
$$;

create or replace function private.pachanga_team_operational_apply_scopes_v1(
  target_group_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_revision bigint,
  target_preset text,
  target_scopes text[],
  target_reason_code text,
  target_public_message text,
  target_effective_from timestamptz,
  target_effective_until timestamptz
)
returns integer
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare selected_scope text;
declare previous_id uuid;
declare applied_count integer := 0;
begin
  foreach selected_scope in array target_scopes loop
    selected_scope := upper(trim(selected_scope));
    if selected_scope not in (
      'PUBLIC_DISCOVERY', 'MARKETPLACE', 'SOCIAL_CHALLENGES', 'NEW_MATCH_CREATION',
      'COMPETITION_REGISTRATION', 'COMPETITION_ORGANIZER',
      'EXISTING_COMPETITION_OPERATIONS', 'TEAM_MEMBERSHIP_ADMINISTRATION', 'PUBLIC_PROFILE'
    ) then
      raise exception 'TEAM_OPERATIONAL_SCOPE_NOT_ALLOWED' using errcode = '22023';
    end if;
    previous_id := null;
    select restrictions.id into previous_id
    from private.pachanga_team_operational_restrictions_v1 restrictions
    where restrictions.group_id = target_group_id
      and restrictions.scope = selected_scope
      and restrictions.status = 'ACTIVE'
    for update;
    if previous_id is not null then
      update private.pachanga_team_operational_restrictions_v1 restrictions set
        status = 'SUPERSEDED', closed_by = target_actor_id,
        closed_at = clock_timestamp()
      where restrictions.id = previous_id;
    end if;
    insert into private.pachanga_team_operational_restrictions_v1(
      group_id, scope, status, source_revision, preset_source, reason_code,
      public_message, effective_from, effective_until, supersedes_restriction_id,
      operation_id, applied_by
    ) values (
      target_group_id, selected_scope, 'ACTIVE', target_revision, target_preset,
      target_reason_code, left(coalesce(target_public_message, ''), 500),
      coalesce(target_effective_from, clock_timestamp()), target_effective_until,
      previous_id, target_operation_id, target_actor_id
    );
    applied_count := applied_count + 1;
  end loop;
  return applied_count;
end;
$$;

create or replace function public.command_pachanga_team_operational_state_v1(
  operation_id uuid,
  target_group_id uuid,
  expected_revision bigint,
  action text,
  payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare actor_kind text;
declare platform_role text;
declare action_name text := lower(trim(coalesce(action, '')));
declare state_row private.pachanga_team_operational_states_v1%rowtype;
declare settings private.pachanga_team_operational_settings_v1%rowtype;
declare existing_receipt private.pachanga_team_operational_operation_receipts_v1%rowtype;
declare request_hash text;
declare reason_code text;
declare public_message text;
declare private_note text;
declare evidence jsonb;
declare next_lifecycle text;
declare next_enforcement text;
declare next_preset text;
declare next_continuity text;
declare next_effective_from timestamptz;
declare next_effective_until timestamptz;
declare scopes text[];
declare requested_scopes text[];
declare next_revision bigint;
declare canonical_snapshot jsonb;
declare review_row private.pachanga_team_operational_reviews_v1%rowtype;
declare appeal_row private.pachanga_team_operational_appeals_v1%rowtype;
declare selected_status text;
declare closed_count integer := 0;
declare remaining_count integer := 0;
begin
  perform set_config('pachanga.team_operational_authority', 'on', true);
  if operation_id is null or target_group_id is null or expected_revision is null then
    raise exception 'TEAM_OPERATIONAL_COMMAND_FIELDS_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'TEAM_OPERATIONAL_OBJECT_PAYLOAD_REQUIRED' using errcode = '22023';
  end if;
  if action_name not in (
    'team.lifecycle.archive', 'team.lifecycle.restore',
    'team.review.open', 'team.review.close',
    'team.restriction.apply', 'team.restriction.modify', 'team.restriction.lift',
    'team.suspend', 'team.restore', 'team.continuity.set',
    'team.appeal.create', 'team.appeal.submit', 'team.appeal.withdraw',
    'team.appeal.review', 'team.appeal.resolve', 'team.expire'
  ) then
    raise exception 'TEAM_OPERATIONAL_ACTION_NOT_ALLOWED' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('team-operational-operation:' || operation_id::text, 0));

  select * into settings from private.pachanga_team_operational_settings_v1 where singleton;
  if not settings.foundation_enabled then
    raise exception 'TEAM_OPERATIONAL_FEATURE_DISABLED' using errcode = '55000';
  end if;
  if action_name in ('team.review.open', 'team.review.close')
     and not settings.enforcement_enabled then
    raise exception 'TEAM_OPERATIONAL_ENFORCEMENT_DISABLED' using errcode = '55000';
  end if;
  if action_name in (
    'team.restriction.apply', 'team.restriction.modify', 'team.restriction.lift',
    'team.suspend', 'team.restore', 'team.expire'
  ) and (not settings.enforcement_enabled or not settings.restrictions_enabled) then
    raise exception 'TEAM_OPERATIONAL_RESTRICTIONS_DISABLED' using errcode = '55000';
  end if;
  if action_name = 'team.continuity.set' and not settings.continuity_enabled then
    raise exception 'TEAM_OPERATIONAL_CONTINUITY_DISABLED' using errcode = '55000';
  end if;
  if action_name in (
    'team.appeal.create', 'team.appeal.submit', 'team.appeal.withdraw',
    'team.appeal.review', 'team.appeal.resolve'
  ) and not settings.appeals_enabled then
    raise exception 'TEAM_OPERATIONAL_APPEALS_DISABLED' using errcode = '55000';
  end if;
  perform private.pachanga_ensure_team_operational_state_v1(target_group_id);
  request_hash := private.pachanga_team_operational_request_hash_v1(
    target_group_id, action_name, expected_revision, coalesce(payload, '{}'::jsonb)
  );
  select * into existing_receipt
  from private.pachanga_team_operational_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_team_operational_state_v1.operation_id;
  if found then
    if existing_receipt.request_hash <> request_hash or existing_receipt.group_id <> target_group_id then
      raise exception 'OPERATION_ID_REUSED' using errcode = '23505';
    end if;
    return existing_receipt.response;
  end if;

  select * into strict state_row
  from private.pachanga_team_operational_states_v1 states
  where states.group_id = target_group_id
  for update;
  if state_row.current_revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409',
      detail = jsonb_build_object('expectedRevision', expected_revision, 'confirmedRevision', state_row.current_revision)::text;
  end if;

  if action_name in (
    'team.lifecycle.archive', 'team.lifecycle.restore',
    'team.appeal.create', 'team.appeal.submit', 'team.appeal.withdraw'
  ) then
    actor_id := private.pachanga_team_operational_owner_actor_v1(target_group_id);
    actor_kind := 'OWNER';
  elsif action_name = 'team.expire' and coalesce((select auth.role()), '') = 'service_role' then
    actor_kind := 'SERVICE_AUTHORITY';
  else
    if action_name in ('team.review.open', 'team.review.close') then
      platform_role := private.pachanga_platform_require_v1('teams.operational.review');
    elsif action_name in ('team.appeal.review', 'team.appeal.resolve') then
      platform_role := private.pachanga_platform_require_v1('teams.operational.appeals');
    else
      platform_role := private.pachanga_platform_require_v1('teams.operational.enforce');
    end if;
    actor_kind := 'PLATFORM';
  end if;

  reason_code := left(coalesce(nullif(trim(payload ->> 'reasonCode'), ''), action_name), 120);
  public_message := left(coalesce(payload ->> 'publicMessage', state_row.public_message), 500);
  private_note := left(coalesce(payload ->> 'privateNote', ''), 4000);
  evidence := coalesce(payload -> 'evidence', '{}'::jsonb);
  if jsonb_typeof(evidence) <> 'object' then
    raise exception 'TEAM_OPERATIONAL_EVIDENCE_OBJECT_REQUIRED' using errcode = '22023';
  end if;
  next_lifecycle := state_row.lifecycle_status;
  next_enforcement := state_row.enforcement_status;
  next_preset := state_row.restriction_preset;
  next_continuity := state_row.continuity_policy;
  next_effective_from := clock_timestamp();
  next_effective_until := state_row.effective_until;
  next_revision := state_row.current_revision + 1;

  if action_name = 'team.lifecycle.archive' then
    if payload - array['confirm','continuityPolicy','publicMessage','reasonCode'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    if coalesce((payload ->> 'confirm')::boolean, false) is not true then
      raise exception 'TEAM_ARCHIVE_CONFIRMATION_REQUIRED' using errcode = '22023';
    end if;
    if exists (
      select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
      where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE'
    ) or state_row.enforcement_status in ('LIMITED', 'SUSPENDED') then
      raise exception 'TEAM_PLATFORM_RESTRICTION_MUST_BE_RESOLVED' using errcode = '42501';
    end if;
    next_lifecycle := 'ARCHIVED';
    next_continuity := upper(coalesce(nullif(payload ->> 'continuityPolicy', ''), state_row.continuity_policy));
  elsif action_name = 'team.lifecycle.restore' then
    if payload - array['confirm','publicMessage','reasonCode'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    if coalesce((payload ->> 'confirm')::boolean, false) is not true then
      raise exception 'TEAM_RESTORE_CONFIRMATION_REQUIRED' using errcode = '22023';
    end if;
    next_lifecycle := 'ACTIVE';
  elsif action_name = 'team.review.open' then
    if payload - array['reasonCode','safeMessage','privateNote','evidence','assignedReviewer'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    if exists (
      select 1 from private.pachanga_team_operational_reviews_v1 reviews
      where reviews.group_id = target_group_id and reviews.status in ('OPEN', 'NEEDS_INFORMATION')
    ) then raise exception 'TEAM_REVIEW_ALREADY_OPEN' using errcode = '23505'; end if;
    insert into private.pachanga_team_operational_reviews_v1(
      group_id, status, reason_code, safe_message, private_note, evidence,
      opened_by, assigned_reviewer, operation_id, source_revision
    ) values (
      target_group_id, 'OPEN', reason_code, left(coalesce(payload ->> 'safeMessage', ''), 500),
      private_note, evidence, actor_id,
      coalesce(nullif(payload ->> 'assignedReviewer', '')::uuid, actor_id), operation_id, next_revision
    ) returning * into review_row;
    insert into private.pachanga_team_operational_review_revisions_v1(
      review_id, version, status, reason_code, safe_message, private_note,
      evidence, assigned_reviewer, action, actor_id, operation_id
    ) values (
      review_row.id, 1, review_row.status, review_row.reason_code, review_row.safe_message,
      review_row.private_note, review_row.evidence, review_row.assigned_reviewer,
      action_name, actor_id, operation_id
    );
    if next_enforcement = 'CLEAR' then next_enforcement := 'UNDER_REVIEW'; end if;
    public_message := left(coalesce(payload ->> 'safeMessage', state_row.public_message), 500);
  elsif action_name = 'team.review.close' then
    if payload - array['reviewId','outcome','safeMessage','privateNote','reasonCode'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    select * into strict review_row
    from private.pachanga_team_operational_reviews_v1 reviews
    where reviews.id = (payload ->> 'reviewId')::uuid
      and reviews.group_id = target_group_id
      and reviews.status in ('OPEN', 'NEEDS_INFORMATION')
    for update;
    selected_status := case upper(coalesce(payload ->> 'outcome', 'NO_ACTION'))
      when 'ACTION_TAKEN' then 'CLOSED_ACTION_TAKEN' else 'CLOSED_NO_ACTION' end;
    update private.pachanga_team_operational_reviews_v1 reviews set
      status = selected_status,
      safe_message = left(coalesce(payload ->> 'safeMessage', reviews.safe_message), 500),
      private_note = left(coalesce(payload ->> 'privateNote', reviews.private_note), 4000),
      closed_at = clock_timestamp(), closed_by = actor_id,
      close_outcome = upper(coalesce(payload ->> 'outcome', 'NO_ACTION')),
      revision = reviews.revision + 1, updated_at = clock_timestamp()
    where reviews.id = review_row.id
    returning * into review_row;
    insert into private.pachanga_team_operational_review_revisions_v1(
      review_id, version, status, reason_code, safe_message, private_note,
      evidence, assigned_reviewer, action, actor_id, operation_id
    ) values (
      review_row.id, review_row.revision::integer, review_row.status, review_row.reason_code,
      review_row.safe_message, review_row.private_note, review_row.evidence,
      review_row.assigned_reviewer, action_name, actor_id, operation_id
    );
    if next_enforcement = 'UNDER_REVIEW' and not exists (
      select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
      where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE'
    ) then next_enforcement := 'CLEAR'; public_message := ''; end if;
  elsif action_name in ('team.restriction.apply', 'team.restriction.modify', 'team.suspend') then
    if payload - array[
      'confirm','preset','scopes','continuityPolicy','reasonCode','publicMessage',
      'privateNote','evidence','effectiveFrom','effectiveUntil'
    ] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    if coalesce((payload ->> 'confirm')::boolean, false) is not true then
      raise exception 'TEAM_OPERATIONAL_CONFIRMATION_REQUIRED' using errcode = '22023';
    end if;
    next_preset := upper(coalesce(nullif(payload ->> 'preset', ''),
      case when action_name = 'team.suspend' then 'FULL_PLATFORM_SUSPENSION' else 'CUSTOM' end));
    scopes := private.pachanga_team_operational_preset_scopes_v1(next_preset);
    if next_preset = 'CUSTOM' then
      if jsonb_typeof(payload -> 'scopes') <> 'array' then
        raise exception 'TEAM_OPERATIONAL_SCOPES_REQUIRED' using errcode = '22023';
      end if;
      select coalesce(array_agg(upper(trim(scope_value))), array[]::text[])
      into scopes from jsonb_array_elements_text(payload -> 'scopes') scope_value;
    elsif payload ? 'scopes' then
      raise exception 'TEAM_OPERATIONAL_PRESET_SCOPES_ARE_FIXED' using errcode = '22023';
    end if;
    if coalesce(array_length(scopes, 1), 0) = 0 then
      raise exception 'TEAM_OPERATIONAL_SCOPES_REQUIRED' using errcode = '22023';
    end if;
    next_continuity := upper(coalesce(nullif(payload ->> 'continuityPolicy', ''), state_row.continuity_policy));
    if action_name = 'team.suspend' and not (payload ? 'continuityPolicy') then
      raise exception 'TEAM_CONTINUITY_POLICY_REQUIRED' using errcode = '22023';
    end if;
    next_effective_from := coalesce(nullif(payload ->> 'effectiveFrom', '')::timestamptz, clock_timestamp());
    next_effective_until := nullif(payload ->> 'effectiveUntil', '')::timestamptz;
    if next_effective_until is not null and next_effective_until <= next_effective_from then
      raise exception 'TEAM_OPERATIONAL_EFFECTIVE_RANGE_INVALID' using errcode = '22023';
    end if;
    if action_name in ('team.restriction.modify', 'team.suspend') then
      update private.pachanga_team_operational_restrictions_v1 restrictions set
        status = 'SUPERSEDED', closed_by = actor_id, closed_at = clock_timestamp()
      where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE';
    end if;
    perform private.pachanga_team_operational_apply_scopes_v1(
      target_group_id, operation_id, actor_id, next_revision, next_preset, scopes,
      reason_code, public_message, next_effective_from, next_effective_until
    );
    next_enforcement := case when action_name = 'team.suspend' then 'SUSPENDED' else 'LIMITED' end;
  elsif action_name in ('team.restriction.lift', 'team.restore') then
    if payload - array['confirm','scopes','reasonCode','publicMessage','privateNote'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    if coalesce((payload ->> 'confirm')::boolean, false) is not true then
      raise exception 'TEAM_OPERATIONAL_CONFIRMATION_REQUIRED' using errcode = '22023';
    end if;
    requested_scopes := null;
    if action_name = 'team.restriction.lift' and payload ? 'scopes' then
      if jsonb_typeof(payload -> 'scopes') <> 'array' then
        raise exception 'TEAM_OPERATIONAL_SCOPES_ARRAY_REQUIRED' using errcode = '22023';
      end if;
      select coalesce(array_agg(upper(trim(scope_value))), array[]::text[])
      into requested_scopes from jsonb_array_elements_text(payload -> 'scopes') scope_value;
    end if;
    update private.pachanga_team_operational_restrictions_v1 restrictions set
      status = 'LIFTED', closed_by = actor_id, closed_at = clock_timestamp()
    where restrictions.group_id = target_group_id
      and restrictions.status = 'ACTIVE'
      and (requested_scopes is null or restrictions.scope = any(requested_scopes));
    get diagnostics closed_count = row_count;
    if closed_count = 0 and action_name = 'team.restriction.lift' then
      raise exception 'TEAM_OPERATIONAL_ACTIVE_RESTRICTION_NOT_FOUND' using errcode = 'P0002';
    end if;
    select count(*) into remaining_count
    from private.pachanga_team_operational_restrictions_v1 restrictions
    where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE';
    if remaining_count > 0 then
      next_enforcement := case when state_row.enforcement_status = 'SUSPENDED' then 'SUSPENDED' else 'LIMITED' end;
    elsif exists (
      select 1 from private.pachanga_team_operational_reviews_v1 reviews
      where reviews.group_id = target_group_id and reviews.status in ('OPEN','NEEDS_INFORMATION')
    ) then next_enforcement := 'UNDER_REVIEW';
    else next_enforcement := 'CLEAR'; end if;
    if remaining_count = 0 then next_preset := 'CUSTOM'; next_effective_until := null; end if;
    public_message := left(coalesce(payload ->> 'publicMessage', case when remaining_count = 0 then '' else state_row.public_message end), 500);
  elsif action_name = 'team.continuity.set' then
    if payload - array['competitionId','policy','reasonCode','publicMessage','privateNote','effectiveUntil'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    next_continuity := upper(trim(coalesce(payload ->> 'policy', '')));
    insert into private.pachanga_team_operational_continuity_decisions_v1(
      group_id, competition_id, policy, source_revision, reason_code,
      public_message, private_note, operation_id, decided_by, effective_until
    ) values (
      target_group_id, nullif(payload ->> 'competitionId', '')::uuid,
      next_continuity, next_revision, reason_code, public_message,
      private_note, operation_id, actor_id, nullif(payload ->> 'effectiveUntil', '')::timestamptz
    );
  elsif action_name = 'team.appeal.create' then
    if payload - array['restrictionId','requestedOutcome','message','reasonCode'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    if state_row.enforcement_status not in ('LIMITED', 'SUSPENDED') then
      raise exception 'TEAM_APPEAL_REQUIRES_PLATFORM_DECISION' using errcode = '22023';
    end if;
    insert into private.pachanga_team_operational_appeals_v1(
      group_id, status, subject_revision, subject_restriction_id,
      owner_message, requested_outcome, created_by, operation_id
    ) values (
      target_group_id, 'DRAFT', state_row.current_revision,
      nullif(payload ->> 'restrictionId', '')::uuid,
      left(coalesce(payload ->> 'message', ''), 3000),
      upper(coalesce(nullif(payload ->> 'requestedOutcome', ''), 'REVIEW')),
      actor_id, operation_id
    ) returning * into appeal_row;
    if nullif(trim(appeal_row.owner_message), '') is not null then
      insert into private.pachanga_team_operational_appeal_messages_v1(
        appeal_id, visibility, author_kind, body, authored_by, operation_id
      ) values (
        appeal_row.id, 'OWNER_SAFE', 'OWNER', appeal_row.owner_message, actor_id, operation_id
      );
    end if;
  elsif action_name in ('team.appeal.submit', 'team.appeal.withdraw') then
    if payload - array['appealId','message','reasonCode'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    select * into strict appeal_row
    from private.pachanga_team_operational_appeals_v1 appeals
    where appeals.id = (payload ->> 'appealId')::uuid
      and appeals.group_id = target_group_id
      and appeals.created_by = actor_id
      and (
        (action_name = 'team.appeal.submit' and appeals.status = 'DRAFT')
        or (action_name = 'team.appeal.withdraw' and appeals.status in ('DRAFT','SUBMITTED','UNDER_REVIEW'))
      )
    for update;
    update private.pachanga_team_operational_appeals_v1 appeals set
      status = case when action_name = 'team.appeal.submit' then 'SUBMITTED' else 'WITHDRAWN' end,
      owner_message = left(coalesce(payload ->> 'message', appeals.owner_message), 3000),
      submitted_at = case when action_name = 'team.appeal.submit' then clock_timestamp() else appeals.submitted_at end,
      resolved_at = case when action_name = 'team.appeal.withdraw' then clock_timestamp() else null end,
      revision = appeals.revision + 1,
      server_sequence = nextval('private.pachanga_team_operational_sequence_v1'),
      updated_at = clock_timestamp()
    where appeals.id = appeal_row.id
    returning * into appeal_row;
    if nullif(trim(coalesce(payload ->> 'message', '')), '') is not null then
      insert into private.pachanga_team_operational_appeal_messages_v1(
        appeal_id, visibility, author_kind, body, authored_by, operation_id
      ) values (
        appeal_row.id, 'OWNER_SAFE', 'OWNER', left(payload ->> 'message', 3000), actor_id, operation_id
      );
    end if;
  elsif action_name = 'team.appeal.review' then
    if payload - array['appealId','deadlineAt','safeMessage','privateNote','reasonCode'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    select * into strict appeal_row
    from private.pachanga_team_operational_appeals_v1 appeals
    where appeals.id = (payload ->> 'appealId')::uuid
      and appeals.group_id = target_group_id
      and appeals.status = 'SUBMITTED'
    for update;
    update private.pachanga_team_operational_appeals_v1 appeals set
      status = 'UNDER_REVIEW', assigned_reviewer = actor_id,
      deadline_at = nullif(payload ->> 'deadlineAt', '')::timestamptz,
      private_resolution_note = left(coalesce(payload ->> 'privateNote', ''), 4000),
      revision = appeals.revision + 1,
      server_sequence = nextval('private.pachanga_team_operational_sequence_v1'),
      updated_at = clock_timestamp()
    where appeals.id = appeal_row.id
    returning * into appeal_row;
    if nullif(trim(coalesce(payload ->> 'safeMessage', '')), '') is not null then
      insert into private.pachanga_team_operational_appeal_messages_v1(
        appeal_id, visibility, author_kind, body, authored_by, operation_id
      ) values (
        appeal_row.id, 'OWNER_SAFE', 'PLATFORM', left(payload ->> 'safeMessage', 3000), actor_id, operation_id
      );
    end if;
    if nullif(trim(coalesce(payload ->> 'privateNote', '')), '') is not null then
      insert into private.pachanga_team_operational_appeal_messages_v1(
        appeal_id, visibility, author_kind, body, authored_by, operation_id
      ) values (
        appeal_row.id, 'PLATFORM_PRIVATE', 'PLATFORM', left(payload ->> 'privateNote', 3000), actor_id, operation_id
      );
    end if;
  elsif action_name = 'team.appeal.resolve' then
    if payload - array[
      'appealId','resolution','safeMessage','privateNote','reasonCode','preset','scopes',
      'continuityPolicy','effectiveUntil'
    ] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    select * into strict appeal_row
    from private.pachanga_team_operational_appeals_v1 appeals
    where appeals.id = (payload ->> 'appealId')::uuid
      and appeals.group_id = target_group_id
      and appeals.status in ('SUBMITTED', 'UNDER_REVIEW')
    for update;
    selected_status := upper(coalesce(payload ->> 'resolution', ''));
    if selected_status not in ('UPHELD','MODIFIED','OVERTURNED','INADMISSIBLE') then
      raise exception 'TEAM_APPEAL_RESOLUTION_NOT_ALLOWED' using errcode = '22023';
    end if;
    if selected_status = 'OVERTURNED' then
      update private.pachanga_team_operational_restrictions_v1 restrictions set
        status = 'LIFTED', closed_by = actor_id, closed_at = clock_timestamp()
      where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE';
      next_enforcement := case when exists (
        select 1 from private.pachanga_team_operational_reviews_v1 reviews
        where reviews.group_id = target_group_id and reviews.status in ('OPEN','NEEDS_INFORMATION')
      ) then 'UNDER_REVIEW' else 'CLEAR' end;
      next_preset := 'CUSTOM'; next_effective_until := null;
    elsif selected_status = 'MODIFIED' then
      next_preset := upper(coalesce(nullif(payload ->> 'preset', ''), 'CUSTOM'));
      scopes := private.pachanga_team_operational_preset_scopes_v1(next_preset);
      if next_preset = 'CUSTOM' then
        if jsonb_typeof(payload -> 'scopes') <> 'array' then
          raise exception 'TEAM_OPERATIONAL_SCOPES_REQUIRED' using errcode = '22023';
        end if;
        select coalesce(array_agg(upper(trim(scope_value))), array[]::text[])
        into scopes from jsonb_array_elements_text(payload -> 'scopes') scope_value;
      end if;
      update private.pachanga_team_operational_restrictions_v1 restrictions set
        status = 'SUPERSEDED', closed_by = actor_id, closed_at = clock_timestamp()
      where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE';
      perform private.pachanga_team_operational_apply_scopes_v1(
        target_group_id, operation_id, actor_id, next_revision, next_preset, scopes,
        reason_code, coalesce(payload ->> 'safeMessage', state_row.public_message),
        clock_timestamp(), nullif(payload ->> 'effectiveUntil', '')::timestamptz
      );
      next_enforcement := 'LIMITED';
      next_continuity := upper(coalesce(nullif(payload ->> 'continuityPolicy', ''), state_row.continuity_policy));
    end if;
    update private.pachanga_team_operational_appeals_v1 appeals set
      status = selected_status,
      safe_resolution_message = left(coalesce(payload ->> 'safeMessage', ''), 1000),
      private_resolution_note = left(coalesce(payload ->> 'privateNote', ''), 4000),
      resolved_by = actor_id, resolution = selected_status,
      resolved_at = clock_timestamp(), revision = appeals.revision + 1,
      server_sequence = nextval('private.pachanga_team_operational_sequence_v1'),
      updated_at = clock_timestamp()
    where appeals.id = appeal_row.id
    returning * into appeal_row;
    if nullif(trim(coalesce(payload ->> 'safeMessage', '')), '') is not null then
      insert into private.pachanga_team_operational_appeal_messages_v1(
        appeal_id, visibility, author_kind, body, authored_by, operation_id
      ) values (
        appeal_row.id, 'OWNER_SAFE', 'PLATFORM', left(payload ->> 'safeMessage', 3000), actor_id, operation_id
      );
    end if;
    if nullif(trim(coalesce(payload ->> 'privateNote', '')), '') is not null then
      insert into private.pachanga_team_operational_appeal_messages_v1(
        appeal_id, visibility, author_kind, body, authored_by, operation_id
      ) values (
        appeal_row.id, 'PLATFORM_PRIVATE', 'PLATFORM', left(payload ->> 'privateNote', 3000), actor_id, operation_id
      );
    end if;
    public_message := left(coalesce(payload ->> 'safeMessage', state_row.public_message), 500);
  elsif action_name = 'team.expire' then
    if payload - array['reasonCode'] <> '{}'::jsonb then
      raise exception 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    update private.pachanga_team_operational_restrictions_v1 restrictions set
      status = 'EXPIRED', closed_by = actor_id, closed_at = clock_timestamp()
    where restrictions.group_id = target_group_id
      and restrictions.status = 'ACTIVE'
      and restrictions.effective_until is not null
      and restrictions.effective_until <= clock_timestamp();
    get diagnostics closed_count = row_count;
    if closed_count > 0 then
      select count(*) into remaining_count
      from private.pachanga_team_operational_restrictions_v1 restrictions
      where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE';
      if remaining_count > 0 then
        next_enforcement := case when state_row.enforcement_status = 'SUSPENDED' then 'SUSPENDED' else 'LIMITED' end;
      elsif exists (
        select 1 from private.pachanga_team_operational_reviews_v1 reviews
        where reviews.group_id = target_group_id and reviews.status in ('OPEN','NEEDS_INFORMATION')
      ) then next_enforcement := 'UNDER_REVIEW';
      else next_enforcement := 'CLEAR'; end if;
      if remaining_count = 0 then next_preset := 'CUSTOM'; next_effective_until := null; public_message := ''; end if;
    end if;
  end if;

  if action_name = 'team.expire' and closed_count = 0 then
    canonical_snapshot := private.pachanga_team_operational_command_snapshot_v1(target_group_id);
  else
    canonical_snapshot := private.pachanga_team_operational_commit_state_v1(
      target_group_id, operation_id, actor_id, actor_kind,
      next_lifecycle, next_enforcement, next_preset, next_continuity,
      public_message, next_effective_from, next_effective_until,
      reason_code, private_note, evidence, upper(replace(action_name, '.', '_'))
    );
  end if;

  select states.current_revision into next_revision
  from private.pachanga_team_operational_states_v1 states
  where states.group_id = target_group_id;
  return private.pachanga_team_operational_store_command_v1(
    operation_id, target_group_id, actor_id, actor_kind, action_name,
    request_hash, expected_revision, next_revision, client_metadata,
    reason_code, canonical_snapshot
  );
end;
$$;

create or replace function public.expire_pachanga_team_operational_states_v1(
  batch_size integer default 100,
  operation_namespace uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare target record;
declare processed integer := 0;
declare failures integer := 0;
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if batch_size not between 1 and 500 then
    raise exception 'BATCH_SIZE_OUT_OF_RANGE' using errcode = '22023';
  end if;
  for target in
    select states.group_id, states.current_revision
    from private.pachanga_team_operational_states_v1 states
    where exists (
      select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
      where restrictions.group_id = states.group_id
        and restrictions.status = 'ACTIVE'
        and restrictions.effective_until is not null
        and restrictions.effective_until <= clock_timestamp()
    )
    order by states.server_sequence, states.group_id
    for update skip locked
    limit batch_size
  loop
    begin
      perform public.command_pachanga_team_operational_state_v1(
        (
          substr(md5(operation_namespace::text || target.group_id::text || target.current_revision::text), 1, 8)
          || '-' || substr(md5(operation_namespace::text || target.group_id::text || target.current_revision::text), 9, 4)
          || '-4' || substr(md5(operation_namespace::text || target.group_id::text || target.current_revision::text), 14, 3)
          || '-a' || substr(md5(operation_namespace::text || target.group_id::text || target.current_revision::text), 18, 3)
          || '-' || substr(md5(operation_namespace::text || target.group_id::text || target.current_revision::text), 21, 12)
        )::uuid,
        target.group_id, target.current_revision, 'team.expire',
        jsonb_build_object('reasonCode', 'restriction.expired'),
        jsonb_build_object('surface', 'team_operational_expiry_worker')
      );
      processed := processed + 1;
    exception when others then
      failures := failures + 1;
    end;
  end loop;
  return jsonb_build_object('processed', processed, 'failures', failures, 'serverTime', clock_timestamp());
end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_safe_client_metadata_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_owner_actor_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_command_snapshot_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_commit_state_v1(uuid, uuid, uuid, text, text, text, text, text, text, timestamptz, timestamptz, text, text, jsonb, text) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_store_command_v1(uuid, uuid, uuid, text, text, text, bigint, bigint, jsonb, text, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_apply_scopes_v1(uuid, uuid, uuid, bigint, text, text[], text, text, timestamptz, timestamptz) from public, anon, authenticated;

revoke all on function public.command_pachanga_team_operational_state_v1(uuid, uuid, bigint, text, jsonb, jsonb) from public, anon;
grant execute on function public.command_pachanga_team_operational_state_v1(uuid, uuid, bigint, text, jsonb, jsonb) to authenticated, service_role;
revoke all on function public.expire_pachanga_team_operational_states_v1(integer, uuid) from public, anon, authenticated;
grant execute on function public.expire_pachanga_team_operational_states_v1(integer, uuid) to service_role;

comment on function public.command_pachanga_team_operational_state_v1(uuid, uuid, bigint, text, jsonb, jsonb) is
  'Only Wave 8B Team operational write authority. The server resolves actor, owner, role, revision, scopes and server time.';
