-- Pachangas IQ R4D: server-authoritative operational exception commands.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_can_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
begin
  if actor_role in ('service_authority', 'platform_owner', 'platform_admin', 'competition_owner') then
    return true;
  end if;
  return case actor_role
    when 'competition_director' then target_capability in (
      'read', 'manage', 'staff', 'rules', 'referees', 'entries_manage',
      'rosters_review', 'categories_manage', 'schedule_read', 'schedule_manage',
      'schedule_publish', 'results_read', 'results_manage', 'standings_read',
      'standings_manage', 'operations_read', 'operations_manage'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'entries_manage', 'rosters_review', 'categories_manage',
      'schedule_read', 'schedule_manage', 'schedule_publish', 'results_read',
      'results_manage', 'standings_read', 'standings_manage',
      'operations_read', 'operations_manage'
    )
    when 'competition_operations_manager' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read',
      'operations_read', 'operations_manage'
    )
    when 'competition_schedule_manager' then target_capability in (
      'read', 'schedule_read', 'schedule_manage', 'schedule_publish', 'operations_read'
    )
    when 'competition_result_manager' then target_capability in (
      'read', 'results_read', 'results_manage', 'standings_read', 'operations_read'
    )
    when 'competition_standings_manager' then target_capability in (
      'read', 'results_read', 'standings_read', 'standings_manage', 'operations_read'
    )
    when 'competition_registration_manager' then target_capability in ('read', 'entries_manage')
    when 'competition_roster_manager' then target_capability in ('read', 'rosters_review')
    when 'rules_manager' then target_capability in ('read', 'rules')
    when 'competition_referee_manager' then target_capability in ('read', 'referees')
    when 'viewer' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read', 'operations_read'
    )
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_operational_exceptions_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.league_operational_exceptions_foundation_enabled,
    'postponementsEnabled', settings.league_postponements_enabled,
    'reschedulingEnabled', settings.league_rescheduling_enabled,
    'venueChangesEnabled', settings.league_venue_changes_enabled,
    'lateArrivalEnabled', settings.league_late_arrival_enabled,
    'noShowEnabled', settings.league_no_show_enabled,
    'matchSuspensionsEnabled', settings.league_match_suspensions_enabled,
    'administrativeDecisionsEnabled', settings.league_administrative_decisions_enabled,
    'publicExceptionStatusEnabled', settings.league_public_exception_status_enabled,
    'engineVersion', 'league-operational-exceptions-v1',
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

revoke all on function private.pachanga_league_operational_exceptions_flags_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_league_operational_assert_flags_v1(
  require_postponements boolean default false,
  require_rescheduling boolean default false,
  require_venue_changes boolean default false,
  require_late_arrival boolean default false,
  require_no_show boolean default false,
  require_suspensions boolean default false,
  require_administrative_decisions boolean default false
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.league_operational_exceptions_foundation_enabled then
    raise exception 'LEAGUE_OPERATIONAL_EXCEPTIONS_DISABLED' using errcode = '42501';
  end if;
  if require_postponements and not settings.league_postponements_enabled then
    raise exception 'LEAGUE_POSTPONEMENTS_DISABLED' using errcode = '42501';
  end if;
  if require_rescheduling and not settings.league_rescheduling_enabled then
    raise exception 'LEAGUE_RESCHEDULING_DISABLED' using errcode = '42501';
  end if;
  if require_venue_changes and not settings.league_venue_changes_enabled then
    raise exception 'LEAGUE_VENUE_CHANGES_DISABLED' using errcode = '42501';
  end if;
  if require_late_arrival and not settings.league_late_arrival_enabled then
    raise exception 'LEAGUE_LATE_ARRIVAL_DISABLED' using errcode = '42501';
  end if;
  if require_no_show and not settings.league_no_show_enabled then
    raise exception 'LEAGUE_NO_SHOW_DISABLED' using errcode = '42501';
  end if;
  if require_suspensions and not settings.league_match_suspensions_enabled then
    raise exception 'LEAGUE_MATCH_SUSPENSIONS_DISABLED' using errcode = '42501';
  end if;
  if require_administrative_decisions and not settings.league_administrative_decisions_enabled then
    raise exception 'LEAGUE_ADMINISTRATIVE_DECISIONS_DISABLED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_league_operational_assert_flags_v1(
  boolean, boolean, boolean, boolean, boolean, boolean, boolean
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_policy_v1(
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb := private.pachanga_league_rule_document_v1(target_rule_revision_id);
declare policy jsonb := coalesce(document #> '{operations,exceptionPolicy}', '{}'::jsonb);
declare venue_policy jsonb := coalesce(policy -> 'venuePolicy', '{}'::jsonb);
declare eligibility_policy jsonb := coalesce(policy -> 'resumptionEligibilityPolicy', '{}'::jsonb);
declare deadline_hours integer;
declare grace_minutes integer;
declare minimum_rest_hours integer;
declare maximum_duration_minutes integer;
declare winner_score integer;
declare loser_score integer;
declare deadline_policy text;
declare no_show_outcome text;
declare resumption_policy text;
declare stage_window_start timestamptz;
declare stage_window_end timestamptz;
declare organizer_approval_required boolean;
declare organizer_intervention boolean;
begin
  if jsonb_typeof(policy) <> 'object' or jsonb_typeof(venue_policy) <> 'object'
     or jsonb_typeof(eligibility_policy) <> 'object' then
    raise exception 'R4D_RULE_POLICY_INVALID' using errcode = '22023';
  end if;
  begin
    deadline_hours := nullif(policy ->> 'postponementResponseDeadlineHours', '')::integer;
    grace_minutes := nullif(policy ->> 'gracePeriodMinutes', '')::integer;
    minimum_rest_hours := nullif(policy ->> 'minimumRestHours', '')::integer;
    maximum_duration_minutes := nullif(policy ->> 'maximumMatchDurationMinutes', '')::integer;
    winner_score := nullif(policy ->> 'noShowWinnerScore', '')::integer;
    loser_score := nullif(policy ->> 'noShowLoserScore', '')::integer;
    deadline_policy := upper(nullif(trim(policy ->> 'postponementDeadlinePolicy'), ''));
    no_show_outcome := upper(nullif(trim(policy ->> 'noShowOutcome'), ''));
    resumption_policy := upper(nullif(trim(policy ->> 'resumptionPolicy'), ''));
    stage_window_start := nullif(policy ->> 'stageWindowStart', '')::timestamptz;
    stage_window_end := nullif(policy ->> 'stageWindowEnd', '')::timestamptz;
    organizer_approval_required := (policy ->> 'organizerApprovalRequired')::boolean;
    organizer_intervention := (policy ->> 'organizerCanInterveneAfterDeadline')::boolean;
  exception when others then
    raise exception 'R4D_RULE_POLICY_INVALID' using errcode = '22023';
  end;
  if deadline_hours is null or deadline_hours < 1 or deadline_hours > 720
     or grace_minutes is null or grace_minutes < 0 or grace_minutes > 180
     or minimum_rest_hours is null or minimum_rest_hours < 0 or minimum_rest_hours > 336
     or maximum_duration_minutes is null or maximum_duration_minutes < 1 or maximum_duration_minutes > 600
     or winner_score is null or winner_score < 0 or winner_score > 99
     or loser_score is null or loser_score < 0 or loser_score > 99
     or stage_window_start is null or stage_window_end is null
     or stage_window_end <= stage_window_start
     or organizer_approval_required is null or organizer_intervention is null then
    raise exception 'R4D_RULE_POLICY_REQUIRED' using errcode = '22023';
  end if;
  if deadline_policy not in ('EXPIRE', 'ESCALATE_TO_ORGANIZER', 'AUTO_DENY') then
    raise exception 'R4D_DEADLINE_POLICY_INVALID' using errcode = '22023';
  end if;
  if no_show_outcome not in ('NO_SHOW', 'FORFEIT') then
    raise exception 'R4D_NO_SHOW_POLICY_INVALID' using errcode = '22023';
  end if;
  if resumption_policy <> 'SAME_CANONICAL_MATCH' then
    raise exception 'R4D_RESUMPTION_POLICY_INVALID' using errcode = '22023';
  end if;
  if not (venue_policy ? 'allowSavedVenue')
     or not (venue_policy ? 'allowVenueLabel')
     or not (venue_policy ? 'allowTbd') then
    raise exception 'R4D_VENUE_POLICY_REQUIRED' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'postponementResponseDeadlineHours', deadline_hours,
    'postponementDeadlinePolicy', deadline_policy,
    'organizerApprovalRequired', organizer_approval_required,
    'organizerCanInterveneAfterDeadline', organizer_intervention,
    'gracePeriodMinutes', grace_minutes,
    'minimumRestHours', minimum_rest_hours,
    'maximumMatchDurationMinutes', maximum_duration_minutes,
    'noShowOutcome', no_show_outcome,
    'noShowWinnerScore', winner_score,
    'noShowLoserScore', loser_score,
    'resumptionPolicy', resumption_policy,
    'stageWindowStart', stage_window_start,
    'stageWindowEnd', stage_window_end,
    'venuePolicy', venue_policy,
    'resumptionEligibilityPolicy', eligibility_policy
  );
end;
$$;

revoke all on function private.pachanga_league_operational_policy_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_operational_request_hash_v1(
  target_action text,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_league_match_request_hash_v1(
    target_action, target_aggregate_id, target_expected_revision, target_payload
  );
$$;

revoke all on function private.pachanga_league_operational_request_hash_v1(
  text, uuid, bigint, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_competition_operation_receipts%rowtype;
begin
  select * into receipt
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id is distinct from target_actor_id
     or receipt.actor_kind <> target_actor_kind
     or receipt.action <> target_action
     or receipt.aggregate_type <> 'league_operational_exceptions'
     or receipt.aggregate_id <> target_aggregate_id::text
     or receipt.request_hash <> target_request_hash then
    raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

revoke all on function private.pachanga_league_operational_replay_v1(
  uuid, uuid, text, text, uuid, text
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_assert_manager_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text := private.pachanga_competition_actor_role_v1(
  target_competition_id, target_actor_id
);
begin
  if not private.pachanga_competition_can_v1(
    target_competition_id, target_actor_id, 'operations_manage'
  ) then
    raise exception 'COMPETITION_OPERATIONS_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  return actor_role;
end;
$$;

revoke all on function private.pachanga_league_operational_assert_manager_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_operational_assert_team_actor_v1(
  target_entry_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_scope text := private.pachanga_league_entry_actor_scope_v1(target_entry_id, target_actor_id);
begin
  if coalesce(actor_scope, '') not in ('TEAM_OWNER', 'PRIMARY_DELEGATE') then
    raise exception 'R4D_TEAM_OWNER_OR_PRIMARY_DELEGATE_REQUIRED' using errcode = '42501';
  end if;
  return actor_scope;
end;
$$;

revoke all on function private.pachanga_league_operational_assert_team_actor_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_operational_store_evidence_v1(
  target_competition_id uuid,
  target_subject_type text,
  target_subject_id uuid,
  target_reason_text text,
  target_evidence_refs jsonb,
  target_actor_id uuid,
  target_operation_id uuid,
  target_server_sequence bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare evidence jsonb := coalesce(target_evidence_refs, '[]'::jsonb);
begin
  if jsonb_typeof(evidence) <> 'array' or jsonb_array_length(evidence) > 20
     or pg_column_size(evidence) > 16000 then
    raise exception 'R4D_EVIDENCE_REFS_INVALID' using errcode = '22023';
  end if;
  insert into private.pachanga_competition_operational_evidence(
    competition_id, subject_type, subject_id, reason_text, evidence_refs,
    actor_id, operation_id, server_sequence
  ) values (
    target_competition_id, target_subject_type, target_subject_id,
    left(coalesce(target_reason_text, ''), 4000), evidence,
    target_actor_id, target_operation_id, target_server_sequence
  );
end;
$$;

revoke all on function private.pachanga_league_operational_store_evidence_v1(
  uuid, text, uuid, text, jsonb, uuid, uuid, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_validate_fixture_v1(
  target_context_id uuid,
  target_scheduled_start timestamptz,
  target_scheduled_end timestamptz,
  target_timezone text,
  target_resource_key text,
  target_policy jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare duration_minutes numeric;
declare minimum_rest_hours integer;
declare maximum_duration_minutes integer;
declare stage_window_start timestamptz;
declare stage_window_end timestamptz;
declare hard_conflicts jsonb := '[]'::jsonb;
declare soft_impact jsonb := '{}'::jsonb;
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  if target_scheduled_start is null or target_scheduled_end is null
     or target_scheduled_end <= target_scheduled_start then
    raise exception 'R4D_EFFECTIVE_SCHEDULE_INVALID' using errcode = '22023';
  end if;
  if target_timezone is null or not exists (
    select 1 from pg_catalog.pg_timezone_names zones where zones.name = target_timezone
  ) then
    raise exception 'R4D_TIMEZONE_INVALID' using errcode = '22023';
  end if;
  select * into edition_row
  from public.pachanga_competition_editions editions
  where editions.id = context_row.edition_id;
  if edition_row.starts_at is null or edition_row.ends_at is null then
    raise exception 'R4D_EDITION_RANGE_REQUIRED' using errcode = '22023';
  end if;
  if (target_scheduled_start at time zone target_timezone)::date < edition_row.starts_at
     or (target_scheduled_end at time zone target_timezone)::date > edition_row.ends_at then
    raise exception 'R4D_DATE_OUTSIDE_EDITION' using errcode = '22023';
  end if;
  begin
    minimum_rest_hours := (target_policy ->> 'minimumRestHours')::integer;
    maximum_duration_minutes := (target_policy ->> 'maximumMatchDurationMinutes')::integer;
    stage_window_start := (target_policy ->> 'stageWindowStart')::timestamptz;
    stage_window_end := (target_policy ->> 'stageWindowEnd')::timestamptz;
  exception when others then
    raise exception 'R4D_RULE_POLICY_INVALID' using errcode = '22023';
  end;
  if target_scheduled_start < stage_window_start or target_scheduled_end > stage_window_end then
    raise exception 'R4D_DATE_OUTSIDE_STAGE' using errcode = '22023';
  end if;
  duration_minutes := extract(epoch from target_scheduled_end - target_scheduled_start) / 60;
  if duration_minutes <= 0 or duration_minutes > maximum_duration_minutes then
    raise exception 'R4D_MATCH_DURATION_INVALID' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.pachanga_competition_match_contexts other_contexts
    where other_contexts.id <> context_row.id
      and other_contexts.competition_id = context_row.competition_id
      and other_contexts.status not in ('cancelled', 'abandoned', 'retired')
      and other_contexts.scheduled_start is not null
      and other_contexts.scheduled_end is not null
      and (other_contexts.home_entry_id in (context_row.home_entry_id, context_row.away_entry_id)
        or other_contexts.away_entry_id in (context_row.home_entry_id, context_row.away_entry_id))
      and tstzrange(other_contexts.scheduled_start, other_contexts.scheduled_end, '[)')
        && tstzrange(target_scheduled_start, target_scheduled_end, '[)')
  ) then
    raise exception 'R4D_TEAM_SCHEDULE_OVERLAP' using errcode = '23P01';
  end if;

  if minimum_rest_hours > 0 and exists (
    select 1
    from public.pachanga_competition_match_contexts other_contexts
    where other_contexts.id <> context_row.id
      and other_contexts.competition_id = context_row.competition_id
      and other_contexts.status not in ('cancelled', 'abandoned', 'retired')
      and other_contexts.scheduled_start is not null
      and other_contexts.scheduled_end is not null
      and (other_contexts.home_entry_id in (context_row.home_entry_id, context_row.away_entry_id)
        or other_contexts.away_entry_id in (context_row.home_entry_id, context_row.away_entry_id))
      and other_contexts.scheduled_start < target_scheduled_end + make_interval(hours => minimum_rest_hours)
      and other_contexts.scheduled_end > target_scheduled_start - make_interval(hours => minimum_rest_hours)
  ) then
    raise exception 'R4D_MINIMUM_REST_VIOLATION' using errcode = '22023';
  end if;

  if nullif(trim(coalesce(target_resource_key, '')), '') is not null and exists (
    select 1
    from public.pachanga_competition_match_contexts other_contexts
    left join public.pachanga_competition_schedule_items other_items
      on other_items.id = other_contexts.schedule_item_id
    left join public.pachanga_competition_schedule_slots other_slots
      on other_slots.id = other_items.slot_id
    left join public.pachanga_competition_fixture_changes active_changes
      on active_changes.competition_match_context_id = other_contexts.id
      and active_changes.status = 'active'
    left join public.pachanga_competition_fixture_change_revisions active_revisions
      on active_revisions.id = active_changes.current_revision_id
    where other_contexts.id <> context_row.id
      and other_contexts.competition_id = context_row.competition_id
      and other_contexts.status not in ('cancelled', 'abandoned', 'retired')
      and other_contexts.scheduled_start is not null
      and other_contexts.scheduled_end is not null
      and coalesce(active_revisions.effective_resource_key, other_slots.resource_key)
        = target_resource_key
      and tstzrange(other_contexts.scheduled_start, other_contexts.scheduled_end, '[)')
        && tstzrange(target_scheduled_start, target_scheduled_end, '[)')
  ) then
    raise exception 'R4D_VENUE_RESOURCE_OVERLAP' using errcode = '23P01';
  end if;

  soft_impact := jsonb_build_object(
    'hardConflicts', hard_conflicts,
    'preferenceImpact', 'RECORDED_NOT_BLOCKING',
    'validatedAt', clock_timestamp()
  );
  return soft_impact;
end;
$$;

revoke all on function private.pachanga_league_operational_validate_fixture_v1(
  uuid, timestamptz, timestamptz, text, text, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_create_fixture_change_v1(
  target_context_id uuid,
  target_change_type text,
  target_context_status text,
  target_scheduled_start timestamptz,
  target_scheduled_end timestamptz,
  target_timezone text,
  target_venue_id uuid,
  target_venue_label text,
  target_venue_status text,
  target_resource_key text,
  target_reason_code text,
  target_public_summary text,
  target_source_type text,
  target_source_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint,
  target_policy jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare item_row public.pachanga_competition_schedule_items%rowtype;
declare change_row public.pachanga_competition_fixture_changes%rowtype;
declare revision_row public.pachanga_competition_fixture_change_revisions%rowtype;
declare revision_id uuid := gen_random_uuid();
declare revision_version integer;
declare normalized_change_type text := upper(trim(coalesce(target_change_type, '')));
declare normalized_venue_status text := upper(trim(coalesce(target_venue_status, 'TBD')));
declare soft_impact jsonb := '{}'::jsonb;
declare venue_policy jsonb := target_policy -> 'venuePolicy';
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  select * into item_row
  from public.pachanga_competition_schedule_items items
  where items.id = context_row.schedule_item_id and items.status = 'published';
  if not found then raise exception 'R4D_PUBLISHED_FIXTURE_REQUIRED' using errcode = '22023'; end if;
  if normalized_change_type not in (
    'RESCHEDULE', 'TIME_CHANGE', 'VENUE_CHANGE', 'POSTPONEMENT',
    'CANCELLATION', 'RESUMPTION', 'REPLAY'
  ) then raise exception 'R4D_FIXTURE_CHANGE_TYPE_INVALID' using errcode = '22023'; end if;
  if normalized_venue_status not in ('SAVED', 'LABEL', 'TBD') then
    raise exception 'R4D_VENUE_STATUS_INVALID' using errcode = '22023';
  end if;
  if normalized_venue_status = 'SAVED' and not coalesce((venue_policy ->> 'allowSavedVenue')::boolean, false)
     or normalized_venue_status = 'LABEL' and not coalesce((venue_policy ->> 'allowVenueLabel')::boolean, false)
     or normalized_venue_status = 'TBD' and not coalesce((venue_policy ->> 'allowTbd')::boolean, false) then
    raise exception 'R4D_VENUE_POLICY_FORBIDS_SELECTION' using errcode = '22023';
  end if;
  if normalized_venue_status = 'SAVED' and target_venue_id is null
     or normalized_venue_status = 'LABEL' and nullif(trim(coalesce(target_venue_label, '')), '') is null
     or normalized_venue_status = 'TBD' and (target_venue_id is not null or target_venue_label is not null) then
    raise exception 'R4D_VENUE_SELECTION_INVALID' using errcode = '22023';
  end if;
  if normalized_change_type in ('RESCHEDULE', 'TIME_CHANGE', 'RESUMPTION', 'REPLAY') then
    soft_impact := private.pachanga_league_operational_validate_fixture_v1(
      context_row.id, target_scheduled_start, target_scheduled_end,
      target_timezone, target_resource_key, target_policy
    );
  elsif normalized_change_type = 'VENUE_CHANGE'
        and context_row.scheduled_start is not null and context_row.scheduled_end is not null then
    soft_impact := private.pachanga_league_operational_validate_fixture_v1(
      context_row.id, context_row.scheduled_start, context_row.scheduled_end,
      context_row.timezone, target_resource_key, target_policy
    );
  end if;

  select * into change_row
  from public.pachanga_competition_fixture_changes changes
  where changes.competition_match_context_id = context_row.id
    and changes.status = 'active'
  for update;
  if found then
    revision_version := change_row.revision::integer + 1;
    update public.pachanga_competition_fixture_changes changes set
      change_type = normalized_change_type,
      source_type = target_source_type,
      source_id = target_source_id,
      revision = changes.revision + 1,
      server_sequence = target_server_sequence,
      updated_at = clock_timestamp()
    where changes.id = change_row.id
    returning * into change_row;
  else
    revision_version := 1;
    insert into public.pachanga_competition_fixture_changes(
      competition_id, canonical_match_id, competition_match_context_id,
      schedule_item_id, rule_revision_id, change_type, status, source_type,
      source_id, original_scheduled_start, original_scheduled_end,
      original_timezone, original_venue_id, original_venue_label,
      original_venue_status, creation_operation_id, revision,
      server_sequence, created_by
    ) values (
      context_row.competition_id, context_row.canonical_match_id, context_row.id,
      context_row.schedule_item_id, context_row.rule_revision_id,
      normalized_change_type, 'active', target_source_type, target_source_id,
      item_row.scheduled_start, item_row.scheduled_end, item_row.timezone,
      item_row.venue_id, item_row.venue_label,
      case when item_row.venue_status = 'CONFIRMED' and item_row.venue_id is null
        then 'LABEL' else item_row.venue_status end,
      target_operation_id, 1, target_server_sequence, target_actor_id
    ) returning * into change_row;
  end if;

  insert into public.pachanga_competition_fixture_change_revisions(
    id, fixture_change_id, version, previous_revision_id, change_type,
    effective_scheduled_start, effective_scheduled_end, effective_timezone,
    effective_venue_id, effective_venue_label, effective_venue_status,
    effective_resource_key, public_reason_code, public_summary,
    soft_constraint_impact, operation_id, created_by, server_sequence
  ) values (
    revision_id, change_row.id, revision_version, change_row.current_revision_id,
    normalized_change_type, target_scheduled_start, target_scheduled_end,
    target_timezone, target_venue_id, target_venue_label, normalized_venue_status,
    nullif(left(trim(coalesce(target_resource_key, '')), 160), ''),
    left(trim(target_reason_code), 120), left(coalesce(target_public_summary, ''), 500),
    soft_impact, target_operation_id, target_actor_id, target_server_sequence
  ) returning * into revision_row;
  update public.pachanga_competition_fixture_changes changes set
    current_revision_id = revision_id,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where changes.id = change_row.id;

  update public.pachanga_competition_match_contexts contexts set
    scheduled_start = coalesce(target_scheduled_start, contexts.scheduled_start),
    scheduled_end = coalesce(target_scheduled_end, contexts.scheduled_end),
    timezone = coalesce(target_timezone, contexts.timezone),
    venue_id = case when target_venue_status is null then contexts.venue_id else target_venue_id end,
    venue_label = case when target_venue_status is null then contexts.venue_label else target_venue_label end,
    venue_status = case normalized_venue_status
      when 'SAVED' then 'CONFIRMED' when 'LABEL' then 'LABEL' else 'TBD' end,
    status = target_context_status,
    revision = contexts.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where contexts.id = context_row.id
  returning * into context_row;
  return jsonb_build_object(
    'fixtureChangeId', change_row.id,
    'fixtureChangeRevisionId', revision_id,
    'changeType', normalized_change_type,
    'contextStatus', context_row.status,
    'contextRevision', context_row.revision,
    'softConstraintImpact', soft_impact
  );
end;
$$;

revoke all on function private.pachanga_league_operational_create_fixture_change_v1(
  uuid, text, text, timestamptz, timestamptz, text, uuid, text, text, text,
  text, text, text, uuid, uuid, uuid, bigint, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_create_admin_decision_v1(
  target_context_id uuid,
  target_decision_type text,
  target_target_type text,
  target_target_id uuid,
  target_reason_code text,
  target_public_summary text,
  target_previous_decision_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint,
  target_bilateral_request_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare bilateral_request public.pachanga_competition_postponement_requests%rowtype;
declare bilateral_response public.pachanga_competition_postponement_responses%rowtype;
declare previous_admin public.pachanga_competition_administrative_decisions%rowtype;
declare assignment_id uuid;
declare decision_id uuid := gen_random_uuid();
declare normalized_type text := upper(trim(coalesce(target_decision_type, '')));
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  if target_bilateral_request_id is null then
    perform private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, target_actor_id
    );
  else
    select * into bilateral_request
    from public.pachanga_competition_postponement_requests requests
    where requests.id = target_bilateral_request_id
      and requests.competition_match_context_id = context_row.id
      and requests.status = 'approved'
      and requests.team_response = 'ACCEPTED'
      and requests.organizer_response = 'NOT_REQUIRED';
    if not found or target_target_type <> 'POSTPONEMENT_REQUEST'
       or target_target_id <> bilateral_request.id then
      raise exception 'R4D_BILATERAL_AUTHORITY_INVALID' using errcode = '42501';
    end if;
    select * into bilateral_response
    from public.pachanga_competition_postponement_responses responses
    where responses.id = bilateral_request.current_response_id
      and responses.response_kind = 'ACCEPT'
      and responses.responded_by = target_actor_id;
    if not found then
      raise exception 'R4D_BILATERAL_ACCEPTANCE_NOT_CONFIRMED' using errcode = '42501';
    end if;
    perform private.pachanga_league_operational_assert_team_actor_v1(
      bilateral_response.responding_entry_id, target_actor_id
    );
  end if;
  if normalized_type not in (
    'RESCHEDULE_MATCH', 'CHANGE_VENUE', 'CANCEL_MATCH', 'RESUME_FROM_MINUTE',
    'ORDER_REPLAY', 'SET_OFFICIAL_RESULT', 'ANNUL_OFFICIAL_RESULT'
  ) then raise exception 'R4D_ADMIN_EFFECT_NOT_SUPPORTED' using errcode = '0A000'; end if;
  if target_previous_decision_id is not null then
    select * into previous_admin
    from public.pachanga_competition_administrative_decisions decisions
    where decisions.id = target_previous_decision_id
      and decisions.competition_id = context_row.competition_id
      and decisions.status = 'published'
    for update;
    if not found then
      raise exception 'R4D_ADMIN_DECISION_STALE' using errcode = 'PT409';
    end if;
    if not (
      (
        previous_admin.target_type = target_target_type
        and (
          previous_admin.target_id = target_target_id
          or (
            target_target_type = 'VENUE_CHANGE_REQUEST'
            and exists (
              select 1
              from public.pachanga_competition_venue_change_requests previous_request
              join public.pachanga_competition_venue_change_requests next_request
                on next_request.id = target_target_id
              where previous_request.id = previous_admin.target_id
                and previous_request.competition_match_context_id = context_row.id
                and next_request.competition_match_context_id = context_row.id
            )
          )
        )
      )
      or (
        normalized_type = 'ANNUL_OFFICIAL_RESULT'
        and target_target_type = 'OFFICIAL_RESULT_DECISION'
        and previous_admin.decision_type = 'SET_OFFICIAL_RESULT'
        and exists (
          select 1
          from public.pachanga_competition_administrative_effects effects
          where effects.administrative_decision_id = previous_admin.id
            and effects.official_result_decision_id = target_target_id
            and effects.effect_type = 'SET_OFFICIAL_RESULT'
        )
      )
    ) then
      raise exception 'R4D_ADMIN_DECISION_TARGET_MISMATCH' using errcode = 'PT409';
    end if;
    update public.pachanga_competition_administrative_decisions decisions set
      status = 'superseded', revision = decisions.revision + 1,
      server_sequence = target_server_sequence, updated_at = clock_timestamp()
    where decisions.id = target_previous_decision_id
      and decisions.competition_id = context_row.competition_id
      and decisions.status = 'published';
  end if;
  select assignments.id into assignment_id
  from public.pachanga_competition_staff_assignments assignments
  where assignments.competition_id = context_row.competition_id
    and assignments.user_id = target_actor_id
    and assignments.status = 'active'
  order by assignments.server_sequence desc, assignments.id desc
  limit 1;
  insert into public.pachanga_competition_administrative_decisions(
    id, competition_id, decision_type, target_type, target_id,
    authority_assignment_id, rule_revision_id, reason_code, public_summary,
    previous_decision_id, status, operation_id, server_sequence, decided_by
  ) values (
    decision_id, context_row.competition_id, normalized_type,
    target_target_type, target_target_id, assignment_id, context_row.rule_revision_id,
    left(trim(target_reason_code), 120), left(coalesce(target_public_summary, ''), 500),
    target_previous_decision_id, 'published', target_operation_id,
    target_server_sequence, target_actor_id
  );
  return decision_id;
end;
$$;

revoke all on function private.pachanga_league_operational_create_admin_decision_v1(
  uuid, text, text, uuid, text, text, uuid, uuid, uuid, bigint, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_add_admin_effect_v1(
  target_decision_id uuid,
  target_effect_type text,
  target_effect_payload jsonb,
  target_fixture_change_id uuid,
  target_official_result_decision_id uuid,
  target_resumption_decision_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare effect_id uuid := gen_random_uuid();
declare normalized_type text := upper(trim(coalesce(target_effect_type, '')));
begin
  if normalized_type in (
    'DEDUCT_POINTS', 'CREATE_SANCTION', 'REVERSE_SANCTION_SERVICE',
    'CREATE_COMPETITION_CHARGE', 'CREATE_COMPETITION_CREDIT'
  ) then raise exception 'FEATURE_NOT_AVAILABLE_UNTIL_R5' using errcode = '0A000'; end if;
  if normalized_type not in (
    'RESCHEDULE_MATCH', 'CHANGE_VENUE', 'CANCEL_MATCH', 'RESUME_FROM_MINUTE',
    'ORDER_REPLAY', 'SET_OFFICIAL_RESULT', 'ANNUL_OFFICIAL_RESULT'
  ) then raise exception 'R4D_ADMIN_EFFECT_NOT_SUPPORTED' using errcode = '0A000'; end if;
  insert into public.pachanga_competition_administrative_effects(
    id, administrative_decision_id, effect_order, effect_type, effect_payload,
    status, fixture_change_id, official_result_decision_id,
    match_resumption_decision_id, server_sequence
  ) values (
    effect_id, target_decision_id, 1, normalized_type,
    coalesce(target_effect_payload, '{}'::jsonb), 'applied',
    target_fixture_change_id, target_official_result_decision_id,
    target_resumption_decision_id, target_server_sequence
  );
  return effect_id;
end;
$$;

revoke all on function private.pachanga_league_operational_add_admin_effect_v1(
  uuid, text, jsonb, uuid, uuid, uuid, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_no_show_result_v1(
  target_context_id uuid,
  target_no_show_incident_id uuid,
  target_responsible_entry_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_authority_role text,
  target_reason_code text,
  target_public_summary text,
  target_server_sequence bigint,
  target_policy jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare sheet_row public.pachanga_competition_match_sheets%rowtype;
declare active_decision public.pachanga_competition_official_result_decisions%rowtype;
declare decision_id uuid := gen_random_uuid();
declare outcome text := upper(target_policy ->> 'noShowOutcome');
declare winner_score integer := (target_policy ->> 'noShowWinnerScore')::integer;
declare loser_score integer := (target_policy ->> 'noShowLoserScore')::integer;
declare score_home integer;
declare score_away integer;
declare standings jsonb;
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  if target_responsible_entry_id not in (context_row.home_entry_id, context_row.away_entry_id) then
    raise exception 'R4D_NO_SHOW_ENTRY_NOT_IN_MATCH' using errcode = '22023';
  end if;
  if outcome not in ('NO_SHOW', 'FORFEIT') then
    raise exception 'R4D_NO_SHOW_POLICY_INVALID' using errcode = '22023';
  end if;
  if target_responsible_entry_id = context_row.home_entry_id then
    score_home := loser_score;
    score_away := winner_score;
  else
    score_home := winner_score;
    score_away := loser_score;
  end if;
  select * into sheet_row
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = context_row.id
  for update;
  if not found then
    insert into public.pachanga_competition_match_sheets(
      canonical_match_id, competition_match_context_id, created_by, server_sequence
    ) values (
      context_row.canonical_match_id, context_row.id, target_actor_id, target_server_sequence
    ) returning * into sheet_row;
  end if;
  if sheet_row.active_official_decision_id is not null then
    select * into active_decision
    from public.pachanga_competition_official_result_decisions decisions
    where decisions.id = sheet_row.active_official_decision_id;
  end if;
  insert into public.pachanga_competition_official_result_decisions(
    id, canonical_match_id, competition_match_context_id, sporting_result_id,
    sporting_result_revision_id, supersedes_decision_id, outcome,
    effective_score_home, effective_score_away, public_explanation,
    reason_code, points_adjustments, operation_id, authority_role, decided_by,
    server_sequence, operational_source_type, operational_source_id
  ) values (
    decision_id, context_row.canonical_match_id, context_row.id, null, null,
    active_decision.id, outcome, score_home, score_away,
    left(coalesce(target_public_summary, ''), 500), left(trim(target_reason_code), 120),
    '[]'::jsonb, target_operation_id, left(target_authority_role, 80),
    target_actor_id, target_server_sequence, 'NO_SHOW_INCIDENT', target_no_show_incident_id
  );
  insert into private.pachanga_competition_official_result_evidence(
    official_result_decision_id, evidence, created_by
  ) values (
    decision_id,
    jsonb_build_object(
      'source', 'R4D_NO_SHOW_INCIDENT',
      'noShowIncidentId', target_no_show_incident_id,
      'ruleRevisionId', context_row.rule_revision_id
    ),
    target_actor_id
  );
  update public.pachanga_competition_match_sheets sheets set
    active_official_decision_id = decision_id,
    revision = sheets.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where sheets.id = sheet_row.id;
  update public.pachanga_competition_match_contexts contexts set
    status = 'official', revision = contexts.revision + 1,
    server_sequence = target_server_sequence, updated_at = clock_timestamp()
  where contexts.id = context_row.id;
  standings := private.pachanga_league_standings_rebuild_v1(
    context_row.id, 'INCREMENTAL', target_operation_id,
    target_actor_id, target_server_sequence
  );
  perform set_config('pachangas.r4c_official_decision', 'on', true);
  update public.pachanga_competition_rounds rounds set
    revision = rounds.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where rounds.id = context_row.round_id;
  perform set_config('pachangas.r4c_official_decision', 'off', true);
  return jsonb_build_object(
    'decisionId', decision_id, 'outcome', outcome,
    'effectiveScoreHome', score_home, 'effectiveScoreAway', score_away,
    'standings', standings
  );
end;
$$;

revoke all on function private.pachanga_league_operational_no_show_result_v1(
  uuid, uuid, uuid, uuid, uuid, text, text, text, bigint, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_suspension_result_v1(
  target_context_id uuid,
  target_suspension_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_authority_role text,
  target_reason_code text,
  target_public_summary text,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare suspension_row public.pachanga_competition_match_suspensions%rowtype;
declare sheet_row public.pachanga_competition_match_sheets%rowtype;
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare result_revision public.pachanga_competition_sporting_result_revisions%rowtype;
declare decision_id uuid := gen_random_uuid();
declare standings jsonb;
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  select * into suspension_row
  from public.pachanga_competition_match_suspensions suspensions
  where suspensions.id = target_suspension_id
    and suspensions.competition_match_context_id = context_row.id
    and suspensions.status = 'administrative_resolution'
  for update;
  if not found then
    raise exception 'R4D_SUSPENSION_PARTIAL_RESULT_REQUIRED' using errcode = '22023';
  end if;
  select * into sheet_row
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = context_row.id
  for update;
  if not found or sheet_row.active_official_decision_id is not null then
    raise exception 'R4D_SUSPENSION_RESULT_CONFLICT' using errcode = 'PT409';
  end if;
  if suspension_row.sporting_result_revision_id is not null then
    if sheet_row.current_sporting_result_id is null then
      raise exception 'R4D_SUSPENSION_RESULT_CONFLICT' using errcode = 'PT409';
    end if;
    select * into result_row
    from public.pachanga_competition_sporting_results results
    where results.id = sheet_row.current_sporting_result_id
    for update;
    select * into result_revision
    from public.pachanga_competition_sporting_result_revisions revisions
    where revisions.id = suspension_row.sporting_result_revision_id
      and revisions.sporting_result_id = result_row.id;
    if not found or result_revision.score_home <> suspension_row.sporting_score_home
       or result_revision.score_away <> suspension_row.sporting_score_away then
      raise exception 'R4D_SUSPENSION_RESULT_SNAPSHOT_MISMATCH' using errcode = 'PT409';
    end if;
  end if;
  insert into public.pachanga_competition_official_result_decisions(
    id, canonical_match_id, competition_match_context_id, sporting_result_id,
    sporting_result_revision_id, supersedes_decision_id, outcome,
    effective_score_home, effective_score_away, public_explanation,
    reason_code, points_adjustments, operation_id, authority_role, decided_by,
    server_sequence, operational_source_type, operational_source_id
  ) values (
    decision_id, context_row.canonical_match_id, context_row.id, result_row.id,
    result_revision.id, null, 'SUSPENDED_MATCH_DECISION',
    suspension_row.sporting_score_home, suspension_row.sporting_score_away,
    left(coalesce(target_public_summary, ''), 500),
    left(trim(target_reason_code), 120), '[]'::jsonb, target_operation_id,
    left(target_authority_role, 80), target_actor_id, target_server_sequence,
    'MATCH_SUSPENSION', suspension_row.id
  );
  insert into private.pachanga_competition_official_result_evidence(
    official_result_decision_id, evidence, created_by
  ) values (
    decision_id,
    jsonb_strip_nulls(jsonb_build_object(
      'source', 'R4D_MATCH_SUSPENSION',
      'suspensionId', suspension_row.id,
      'partialResultRevisionId', result_revision.id,
      'ruleRevisionId', context_row.rule_revision_id
    )),
    target_actor_id
  );
  update public.pachanga_competition_match_sheets sheets set
    active_official_decision_id = decision_id,
    revision = sheets.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where sheets.id = sheet_row.id;
  if result_row.id is not null then
    update public.pachanga_competition_sporting_results results set
      state = 'official', revision = results.revision + 1,
      server_sequence = target_server_sequence, updated_at = clock_timestamp()
    where results.id = result_row.id;
  end if;
  update public.pachanga_competition_match_contexts contexts set
    status = 'official', revision = contexts.revision + 1,
    server_sequence = target_server_sequence, updated_at = clock_timestamp()
  where contexts.id = context_row.id;
  standings := private.pachanga_league_standings_rebuild_v1(
    context_row.id, 'INCREMENTAL', target_operation_id,
    target_actor_id, target_server_sequence
  );
  perform set_config('pachangas.r4c_official_decision', 'on', true);
  update public.pachanga_competition_rounds rounds set
    revision = rounds.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where rounds.id = context_row.round_id;
  perform set_config('pachangas.r4c_official_decision', 'off', true);
  return jsonb_build_object(
    'decisionId', decision_id,
    'outcome', 'SUSPENDED_MATCH_DECISION',
    'effectiveScoreHome', suspension_row.sporting_score_home,
    'effectiveScoreAway', suspension_row.sporting_score_away,
    'standings', standings
  );
end;
$$;

revoke all on function private.pachanga_league_operational_suspension_result_v1(
  uuid, uuid, uuid, uuid, text, text, text, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_snapshot_v1(
  target_context_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare original_item public.pachanga_competition_schedule_items%rowtype;
declare fixture_json jsonb;
declare requests_json jsonb;
declare venue_requests_json jsonb;
declare late_arrivals_json jsonb;
declare no_shows_json jsonb;
declare suspensions_json jsonb;
declare decisions_json jsonb;
declare actor_role text;
declare home_scope text;
declare away_scope text;
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  if not private.pachanga_league_match_can_read_v1(context_row.id, target_actor_id) then
    raise exception 'R4D_MATCH_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into original_item
  from public.pachanga_competition_schedule_items items
  where items.id = context_row.schedule_item_id;
  actor_role := private.pachanga_competition_actor_role_v1(context_row.competition_id, target_actor_id);
  home_scope := private.pachanga_league_entry_actor_scope_v1(context_row.home_entry_id, target_actor_id);
  away_scope := private.pachanga_league_entry_actor_scope_v1(context_row.away_entry_id, target_actor_id);
  select to_jsonb(source) into fixture_json from (
    select changes.id, changes.change_type as "changeType", changes.status,
      changes.revision, changes.server_sequence as "serverSequence",
      revisions.id as "revisionId", revisions.version,
      revisions.effective_scheduled_start as "scheduledStart",
      revisions.effective_scheduled_end as "scheduledEnd",
      revisions.effective_timezone as timezone,
      revisions.effective_venue_id as "venueId",
      revisions.effective_venue_label as "venueLabel",
      revisions.effective_venue_status as "venueStatus",
      revisions.public_reason_code as "reasonCode",
      revisions.public_summary as "publicSummary"
    from public.pachanga_competition_fixture_changes changes
    join public.pachanga_competition_fixture_change_revisions revisions
      on revisions.id = changes.current_revision_id
    where changes.competition_match_context_id = context_row.id
      and changes.status = 'active'
  ) source;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', requests.id, 'status', requests.status,
    'requestingEntryId', requests.requesting_entry_id,
    'respondingEntryId', requests.responding_entry_id,
    'proposedStart', requests.proposed_start, 'proposedEnd', requests.proposed_end,
    'proposedTimezone', requests.proposed_timezone,
    'proposedVenueLabel', requests.proposed_venue_label,
    'proposedVenueStatus', requests.proposed_venue_status,
    'reasonCode', requests.reason_code, 'publicSummary', requests.public_summary,
    'responseDeadline', requests.response_deadline,
    'teamResponse', requests.team_response,
    'organizerResponse', requests.organizer_response,
    'revision', requests.revision, 'serverSequence', requests.server_sequence
  ) order by requests.server_sequence desc, requests.id desc), '[]'::jsonb)
  into requests_json
  from public.pachanga_competition_postponement_requests requests
  where requests.competition_match_context_id = context_row.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', requests.id, 'status', requests.status,
    'venueId', requests.requested_venue_id, 'venueLabel', requests.requested_venue_label,
    'venueStatus', requests.requested_venue_status, 'reasonCode', requests.reason_code,
    'publicSummary', requests.public_summary, 'revision', requests.revision,
    'serverSequence', requests.server_sequence
  ) order by requests.server_sequence desc, requests.id desc), '[]'::jsonb)
  into venue_requests_json
  from public.pachanga_competition_venue_change_requests requests
  where requests.competition_match_context_id = context_row.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', incidents.id, 'responsibleEntryId', incidents.responsible_entry_id,
    'status', incidents.status, 'scheduledStart', incidents.scheduled_start,
    'graceDeadline', incidents.grace_deadline, 'arrivalAt', incidents.arrival_at,
    'revision', incidents.revision, 'serverSequence', incidents.server_sequence
  ) order by incidents.server_sequence desc, incidents.id desc), '[]'::jsonb)
  into late_arrivals_json
  from public.pachanga_competition_late_arrival_incidents incidents
  where incidents.competition_match_context_id = context_row.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', incidents.id, 'responsibleEntryId', incidents.responsible_entry_id,
    'status', incidents.status, 'graceDeadline', incidents.grace_deadline,
    'reasonCode', incidents.reason_code, 'publicSummary', incidents.public_summary,
    'officialResultDecisionId', incidents.official_result_decision_id,
    'revision', incidents.revision, 'serverSequence', incidents.server_sequence
  ) order by incidents.server_sequence desc, incidents.id desc), '[]'::jsonb)
  into no_shows_json
  from public.pachanga_competition_no_show_incidents incidents
  where incidents.competition_match_context_id = context_row.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', suspensions.id, 'status', suspensions.status,
    'reportedMinute', suspensions.reported_minute,
    'sportingScoreHome', suspensions.sporting_score_home,
    'sportingScoreAway', suspensions.sporting_score_away,
    'reasonCode', suspensions.reason_code, 'publicSummary', suspensions.public_summary,
    'revision', suspensions.revision, 'serverSequence', suspensions.server_sequence
  ) order by suspensions.server_sequence desc, suspensions.id desc), '[]'::jsonb)
  into suspensions_json
  from public.pachanga_competition_match_suspensions suspensions
  where suspensions.competition_match_context_id = context_row.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', decisions.id, 'decisionType', decisions.decision_type,
    'targetType', decisions.target_type, 'targetId', decisions.target_id,
    'reasonCode', decisions.reason_code, 'publicSummary', decisions.public_summary,
    'status', decisions.status, 'revision', decisions.revision,
    'serverSequence', decisions.server_sequence, 'decidedAt', decisions.decided_at
  ) order by decisions.server_sequence desc, decisions.id desc), '[]'::jsonb)
  into decisions_json
  from public.pachanga_competition_administrative_decisions decisions
  where decisions.competition_id = context_row.competition_id
    and (
      decisions.target_id = context_row.id
      or exists (select 1 from public.pachanga_competition_postponement_requests requests
        where requests.id = decisions.target_id
          and requests.competition_match_context_id = context_row.id)
      or exists (select 1 from public.pachanga_competition_no_show_incidents incidents
        where incidents.id = decisions.target_id
          and incidents.competition_match_context_id = context_row.id)
      or exists (select 1 from public.pachanga_competition_match_suspensions suspensions
        where suspensions.id = decisions.target_id
          and suspensions.competition_match_context_id = context_row.id)
    );
  return jsonb_build_object(
    'kind', 'LeagueOperationalMatchView',
    'revision', context_row.revision,
    'serverSequence', context_row.server_sequence,
    'context', jsonb_build_object(
      'id', context_row.id, 'canonicalMatchId', context_row.canonical_match_id,
      'competitionId', context_row.competition_id, 'roundId', context_row.round_id,
      'homeEntryId', context_row.home_entry_id, 'awayEntryId', context_row.away_entry_id,
      'status', context_row.status, 'scheduledStart', context_row.scheduled_start,
      'scheduledEnd', context_row.scheduled_end, 'timezone', context_row.timezone,
      'venueId', context_row.venue_id, 'venueLabel', context_row.venue_label,
      'venueStatus', context_row.venue_status, 'revision', context_row.revision,
      'serverSequence', context_row.server_sequence
    ),
    'originalSchedule', jsonb_build_object(
      'scheduleItemId', original_item.id, 'scheduledStart', original_item.scheduled_start,
      'scheduledEnd', original_item.scheduled_end, 'timezone', original_item.timezone,
      'venueId', original_item.venue_id, 'venueLabel', original_item.venue_label,
      'venueStatus', original_item.venue_status, 'revision', original_item.revision
    ),
    'effectiveFixtureChange', fixture_json,
    'postponementRequests', requests_json,
    'venueChangeRequests', venue_requests_json,
    'lateArrivalIncidents', late_arrivals_json,
    'noShowIncidents', no_shows_json,
    'suspensions', suspensions_json,
    'administrativeDecisions', decisions_json,
    'permissions', jsonb_build_object(
      'actorCompetitionRole', actor_role,
      'manageOperations', private.pachanga_competition_can_v1(
        context_row.competition_id, target_actor_id, 'operations_manage'
      ),
      'manageHome', home_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE'),
      'manageAway', away_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE')
    ),
    'flags', private.pachanga_league_operational_exceptions_flags_v1()
  );
end;
$$;

revoke all on function private.pachanga_league_operational_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_operational_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_invalidations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare invalidation jsonb;
declare invalidation_sequence bigint;
declare saved_invalidations jsonb := '[]'::jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare response jsonb;
begin
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if jsonb_typeof(coalesce(target_invalidations, '[]'::jsonb)) <> 'array' then
    raise exception 'R4D_INVALIDATIONS_INVALID' using errcode = '22023';
  end if;
  for invalidation in select value
    from jsonb_array_elements(coalesce(target_invalidations, '[]'::jsonb))
  loop
    invalidation_sequence := case when jsonb_array_length(saved_invalidations) = 0
      then target_server_sequence else nextval('private.pachanga_competition_sequence') end;
    insert into public.pachanga_competition_invalidations(
      server_sequence, competition_id, organizer_group_id, organizer_club_id,
      entity_type, entity_id, revision, created_at
    ) values (
      invalidation_sequence, target_competition_id,
      competition_row.organizer_group_id, competition_row.organizer_club_id,
      left(coalesce(invalidation ->> 'entityType', 'league_operational_exceptions'), 120),
      left(coalesce(invalidation ->> 'entityId', target_aggregate_id::text), 240),
      coalesce(nullif(invalidation ->> 'revision', '')::bigint, target_confirmed_revision),
      confirmed_at
    );
    saved_invalidations := saved_invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', left(coalesce(invalidation ->> 'entityType', 'league_operational_exceptions'), 120),
      'entityId', left(coalesce(invalidation ->> 'entityId', target_aggregate_id::text), 240),
      'revision', coalesce(nullif(invalidation ->> 'revision', '')::bigint, target_confirmed_revision),
      'serverSequence', invalidation_sequence
    ));
  end loop;
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', saved_invalidations
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind,
    'league_operational_exceptions', target_aggregate_id::text,
    target_competition_id, target_action, target_confirmed_revision,
    target_server_sequence, left(target_action, 120),
    coalesce(target_event_payload, '{}'::jsonb), confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    'league_operational_exceptions', target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence,
    target_client_metadata, response, confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_league_operational_store_command_v1(
  uuid, uuid, text, text, uuid, uuid, bigint, bigint, text,
  jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_annul_official_result_v1(
  target_context_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_authority_role text,
  target_reason_code text,
  target_public_summary text,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare sheet_row public.pachanga_competition_match_sheets%rowtype;
declare active_decision public.pachanga_competition_official_result_decisions%rowtype;
declare decision_id uuid := gen_random_uuid();
declare standings jsonb;
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  select * into sheet_row
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = context_row.id
  for update;
  if not found or sheet_row.active_official_decision_id is null then
    raise exception 'R4D_OFFICIAL_RESULT_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into active_decision
  from public.pachanga_competition_official_result_decisions decisions
  where decisions.id = sheet_row.active_official_decision_id;
  insert into public.pachanga_competition_official_result_decisions(
    id, canonical_match_id, competition_match_context_id, sporting_result_id,
    sporting_result_revision_id, supersedes_decision_id, outcome,
    effective_score_home, effective_score_away, public_explanation,
    reason_code, points_adjustments, operation_id, authority_role,
    decided_by, server_sequence
  ) values (
    decision_id, context_row.canonical_match_id, context_row.id,
    active_decision.sporting_result_id, active_decision.sporting_result_revision_id,
    active_decision.id, 'ANNULLED', null, null,
    left(coalesce(target_public_summary, ''), 500), left(trim(target_reason_code), 120),
    '[]'::jsonb, target_operation_id, left(target_authority_role, 80),
    target_actor_id, target_server_sequence
  );
  insert into private.pachanga_competition_official_result_evidence(
    official_result_decision_id, evidence, created_by
  ) values (
    decision_id,
    jsonb_build_object(
      'source', 'R4D_ADMINISTRATIVE_DECISION',
      'annulledDecisionId', active_decision.id
    ),
    target_actor_id
  );
  update public.pachanga_competition_match_sheets sheets set
    active_official_decision_id = decision_id,
    revision = sheets.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where sheets.id = sheet_row.id;
  if active_decision.sporting_result_id is not null then
    update public.pachanga_competition_sporting_results results set
      state = 'disputed', revision = results.revision + 1,
      server_sequence = target_server_sequence,
      updated_at = clock_timestamp()
    where results.id = active_decision.sporting_result_id;
  end if;
  update public.pachanga_competition_match_contexts contexts set
    status = 'administrative_review', revision = contexts.revision + 1,
    server_sequence = target_server_sequence, updated_at = clock_timestamp()
  where contexts.id = context_row.id;
  standings := private.pachanga_league_standings_rebuild_v1(
    context_row.id, 'INCREMENTAL', target_operation_id,
    target_actor_id, target_server_sequence
  );
  perform set_config('pachangas.r4c_official_decision', 'on', true);
  update public.pachanga_competition_rounds rounds set
    revision = rounds.revision + 1, server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where rounds.id = context_row.round_id;
  perform set_config('pachangas.r4c_official_decision', 'off', true);
  return jsonb_build_object(
    'decisionId', decision_id, 'outcome', 'ANNULLED',
    'supersedesDecisionId', active_decision.id, 'standings', standings
  );
end;
$$;

revoke all on function private.pachanga_league_operational_annul_official_result_v1(
  uuid, uuid, uuid, text, text, text, bigint
) from public, anon, authenticated;

create or replace function public.command_pachanga_league_operational_exceptions_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare actor_kind text := 'authenticated';
declare action_name text := lower(trim(coalesce(action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare metadata jsonb;
declare request_hash text;
declare replay jsonb;
declare sequence_value bigint;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare round_row public.pachanga_competition_rounds%rowtype;
declare policy jsonb;
declare request_row public.pachanga_competition_postponement_requests%rowtype;
declare response_row public.pachanga_competition_postponement_responses%rowtype;
declare venue_request_row public.pachanga_competition_venue_change_requests%rowtype;
declare venue_decision_row public.pachanga_competition_venue_condition_decisions%rowtype;
declare late_row public.pachanga_competition_late_arrival_incidents%rowtype;
declare no_show_row public.pachanga_competition_no_show_incidents%rowtype;
declare suspension_row public.pachanga_competition_match_suspensions%rowtype;
declare resumption_row public.pachanga_competition_match_resumption_decisions%rowtype;
declare admin_row public.pachanga_competition_administrative_decisions%rowtype;
declare effect_row public.pachanga_competition_administrative_effects%rowtype;
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare result_revision public.pachanga_competition_sporting_result_revisions%rowtype;
declare selected_entry_id uuid;
declare selected_request_id uuid;
declare selected_incident_id uuid;
declare selected_suspension_id uuid;
declare selected_decision_id uuid;
declare selected_previous_decision_id uuid;
declare selected_fixture_change_id uuid;
declare selected_official_decision_id uuid;
declare selected_resumption_id uuid;
declare selected_start timestamptz;
declare selected_end timestamptz;
declare selected_timezone text;
declare selected_venue_id uuid;
declare selected_venue_label text;
declare selected_venue_status text;
declare selected_resource_key text;
declare selected_reason_code text;
declare selected_public_summary text;
declare selected_response_kind text;
declare selected_decision_type text;
declare selected_status text;
declare selected_minute integer;
declare selected_score_home integer;
declare selected_score_away integer;
declare current_resource_key text;
declare actor_scope text;
declare authority_role text;
declare fixture_result jsonb;
declare official_result jsonb;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare invalidations jsonb := '[]'::jsonb;
declare confirmed_revision bigint;
declare server_now timestamptz := clock_timestamp();
declare response_deadline timestamptz;
declare target_entry_id uuid;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or action_name = '' then
    raise exception 'INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(payload) > 40000 then
    raise exception 'INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_PAYLOAD' using errcode = '22023';
  end if;
  if payload ?| array[
    'actorId', 'actor_id', 'ruleRevisionId', 'rule_revision_id',
    'authorityRole', 'authority_role', 'computedScoreHome', 'computedScoreAway',
    'effectiveScoreHome', 'effectiveScoreAway', 'observedScoreHome',
    'observedScoreAway', 'scoreHome', 'scoreAway', 'pointsAdjustments',
    'rating', 'facets', 'sanction', 'billing', 'sql'
  ] then raise exception 'R4D_CLIENT_AUTHORITY_FIELD_FORBIDDEN' using errcode = '42501'; end if;
  if action_name not in (
    'postponement.request', 'postponement.respond', 'postponement.withdraw',
    'postponement.expire', 'fixture.reschedule', 'fixture.change_venue',
    'fixture.cancel', 'late_arrival.report', 'late_arrival.confirm_arrival',
    'late_arrival.escalate', 'no_show.report', 'no_show.confirm',
    'no_show.reject', 'no_show.resolve', 'suspension.report',
    'suspension.confirm', 'suspension.schedule_resume', 'suspension.resume',
    'suspension.order_replay', 'suspension.resolve', 'suspension.cancel',
    'administrative_decision.publish', 'administrative_decision.supersede',
    'administrative_decision.annul'
  ) then raise exception 'R4D_ACTION_NOT_SUPPORTED' using errcode = '0A000'; end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  end if;
  metadata := private.pachanga_league_match_sanitize_metadata_v1(client_metadata);
  request_hash := private.pachanga_league_operational_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91408));
  replay := private.pachanga_league_operational_replay_v1(
    operation_id, actor_id, actor_kind, action_name, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = aggregate_id
  for update;
  if not found then raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
  perform private.pachanga_league_match_context_v1(context_row.id);
  perform pg_advisory_xact_lock(hashtextextended('r4d-round:' || context_row.round_id::text, 91409));
  select * into round_row
  from public.pachanga_competition_rounds rounds
  where rounds.id = context_row.round_id
  for update;
  if context_row.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  perform private.pachanga_league_operational_assert_flags_v1();
  sequence_value := nextval('private.pachanga_competition_sequence');
  policy := private.pachanga_league_operational_policy_v1(context_row.rule_revision_id);
  selected_reason_code := left(trim(coalesce(payload ->> 'reasonCode', action_name)), 120);
  selected_public_summary := left(coalesce(payload ->> 'publicSummary', ''), 500);
  if length(selected_reason_code) < 3 then
    raise exception 'R4D_REASON_CODE_REQUIRED' using errcode = '22023';
  end if;
  select slots.resource_key into current_resource_key
  from public.pachanga_competition_schedule_slots slots
  where slots.id = context_row.slot_id;

  if action_name = 'postponement.request' then
    perform private.pachanga_league_operational_assert_flags_v1(true, false, false, false, false, false, false);
    if context_row.status not in ('scheduled', 'ready') then
      raise exception 'R4D_POSTPONEMENT_WINDOW_CLOSED' using errcode = 'PT409';
    end if;
    selected_entry_id := nullif(payload ->> 'requestingEntryId', '')::uuid;
    if selected_entry_id not in (context_row.home_entry_id, context_row.away_entry_id) then
      raise exception 'R4D_ENTRY_NOT_IN_MATCH' using errcode = '22023';
    end if;
    actor_scope := private.pachanga_league_operational_assert_team_actor_v1(selected_entry_id, actor_id);
    target_entry_id := case when selected_entry_id = context_row.home_entry_id
      then context_row.away_entry_id else context_row.home_entry_id end;
    selected_start := nullif(payload ->> 'proposedStart', '')::timestamptz;
    selected_end := nullif(payload ->> 'proposedEnd', '')::timestamptz;
    selected_timezone := nullif(left(trim(coalesce(payload ->> 'proposedTimezone', '')), 80), '');
    if (selected_start is null) <> (selected_end is null) then
      raise exception 'R4D_PROPOSED_SCHEDULE_INCOMPLETE' using errcode = '22023';
    end if;
    selected_venue_id := nullif(payload ->> 'proposedVenueId', '')::uuid;
    selected_venue_label := nullif(left(trim(coalesce(payload ->> 'proposedVenueLabel', '')), 160), '');
    selected_venue_status := upper(coalesce(nullif(payload ->> 'proposedVenueStatus', ''),
      case when selected_venue_id is not null then 'SAVED'
        when selected_venue_label is not null then 'LABEL' else 'TBD' end));
    response_deadline := server_now + make_interval(
      hours => (policy ->> 'postponementResponseDeadlineHours')::integer
    );
    insert into public.pachanga_competition_postponement_requests(
      competition_id, canonical_match_id, competition_match_context_id,
      requesting_entry_id, responding_entry_id, rule_revision_id, status,
      proposed_start, proposed_end, proposed_timezone, proposed_venue_id,
      proposed_venue_label, proposed_venue_status, reason_code, public_summary,
      response_deadline, deadline_policy, organizer_approval_required,
      team_response, organizer_response, operation_id, server_sequence, requested_by
    ) values (
      context_row.competition_id, context_row.canonical_match_id, context_row.id,
      selected_entry_id, target_entry_id, context_row.rule_revision_id, 'awaiting_response',
      selected_start, selected_end, coalesce(selected_timezone, context_row.timezone),
      selected_venue_id, selected_venue_label, selected_venue_status,
      selected_reason_code, selected_public_summary, response_deadline,
      policy ->> 'postponementDeadlinePolicy',
      (policy ->> 'organizerApprovalRequired')::boolean,
      'PENDING', case when (policy ->> 'organizerApprovalRequired')::boolean
        then 'PENDING' else 'NOT_REQUIRED' end,
      operation_id, sequence_value, actor_id
    ) returning * into request_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'POSTPONEMENT_REQUEST', request_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object(
      'requestId', request_row.id, 'status', request_row.status,
      'requestingEntryId', request_row.requesting_entry_id,
      'respondingEntryId', request_row.responding_entry_id,
      'responseDeadline', request_row.response_deadline
    );

  elsif action_name = 'postponement.respond' then
    perform private.pachanga_league_operational_assert_flags_v1(true, false, false, false, false, false, true);
    selected_request_id := nullif(payload ->> 'requestId', '')::uuid;
    selected_response_kind := upper(trim(coalesce(payload ->> 'responseKind', '')));
    select * into request_row
    from public.pachanga_competition_postponement_requests requests
    where requests.id = selected_request_id
      and requests.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_POSTPONEMENT_REQUEST_NOT_FOUND' using errcode = 'P0002'; end if;
    if request_row.status <> 'awaiting_response' then
      raise exception 'R4D_POSTPONEMENT_REQUEST_NOT_PENDING' using errcode = 'PT409';
    end if;
    if server_now > request_row.response_deadline
       and request_row.organizer_response <> 'ESCALATED' then
      raise exception 'R4D_POSTPONEMENT_DEADLINE_EXPIRED' using errcode = 'PT409';
    end if;
    if selected_response_kind in ('ACCEPT', 'REJECT', 'COUNTERPROPOSE') then
      selected_entry_id := case when request_row.team_response = 'COUNTERPROPOSED'
        then request_row.requesting_entry_id else request_row.responding_entry_id end;
      actor_scope := private.pachanga_league_operational_assert_team_actor_v1(selected_entry_id, actor_id);
      if selected_response_kind = 'COUNTERPROPOSE' then
        selected_start := nullif(payload ->> 'proposedStart', '')::timestamptz;
        selected_end := nullif(payload ->> 'proposedEnd', '')::timestamptz;
        if selected_start is null or selected_end is null then
          raise exception 'R4D_COUNTERPROPOSAL_SCHEDULE_REQUIRED' using errcode = '22023';
        end if;
        selected_timezone := coalesce(nullif(left(trim(coalesce(payload ->> 'proposedTimezone', '')), 80), ''), request_row.proposed_timezone);
        selected_venue_id := coalesce(nullif(payload ->> 'proposedVenueId', '')::uuid, request_row.proposed_venue_id);
        selected_venue_label := coalesce(nullif(left(trim(coalesce(payload ->> 'proposedVenueLabel', '')), 160), ''), request_row.proposed_venue_label);
        selected_venue_status := upper(coalesce(nullif(payload ->> 'proposedVenueStatus', ''), request_row.proposed_venue_status));
      else
        selected_start := request_row.proposed_start;
        selected_end := request_row.proposed_end;
        selected_timezone := request_row.proposed_timezone;
        selected_venue_id := request_row.proposed_venue_id;
        selected_venue_label := request_row.proposed_venue_label;
        selected_venue_status := request_row.proposed_venue_status;
      end if;
      insert into public.pachanga_competition_postponement_responses(
        postponement_request_id, responding_entry_id, responder_kind,
        response_kind, proposed_start, proposed_end, proposed_timezone,
        proposed_venue_id, proposed_venue_label, proposed_venue_status,
        public_summary, operation_id, responded_by, server_sequence
      ) values (
        request_row.id, selected_entry_id, 'TEAM', selected_response_kind,
        selected_start, selected_end, selected_timezone, selected_venue_id,
        selected_venue_label, selected_venue_status, selected_public_summary,
        operation_id, actor_id, sequence_value
      ) returning * into response_row;
      update public.pachanga_competition_postponement_requests requests set
        proposed_start = case when selected_response_kind = 'COUNTERPROPOSE' then selected_start else requests.proposed_start end,
        proposed_end = case when selected_response_kind = 'COUNTERPROPOSE' then selected_end else requests.proposed_end end,
        proposed_timezone = case when selected_response_kind = 'COUNTERPROPOSE' then selected_timezone else requests.proposed_timezone end,
        proposed_venue_id = case when selected_response_kind = 'COUNTERPROPOSE' then selected_venue_id else requests.proposed_venue_id end,
        proposed_venue_label = case when selected_response_kind = 'COUNTERPROPOSE' then selected_venue_label else requests.proposed_venue_label end,
        proposed_venue_status = case when selected_response_kind = 'COUNTERPROPOSE' then selected_venue_status else requests.proposed_venue_status end,
        team_response = case selected_response_kind
          when 'ACCEPT' then 'ACCEPTED' when 'REJECT' then 'REJECTED'
          else 'COUNTERPROPOSED' end,
        status = case when selected_response_kind = 'REJECT' then 'denied' else requests.status end,
        current_response_id = response_row.id,
        resolved_at = case when selected_response_kind = 'REJECT' then server_now else null end,
        revision = requests.revision + 1,
        server_sequence = sequence_value,
        updated_at = server_now
      where requests.id = request_row.id returning * into request_row;
    elsif selected_response_kind in ('APPROVE', 'DENY') then
      authority_role := private.pachanga_league_operational_assert_manager_v1(
        context_row.competition_id, actor_id
      );
      if request_row.team_response <> 'ACCEPTED'
         and not (
           server_now > request_row.response_deadline
           and (policy ->> 'organizerCanInterveneAfterDeadline')::boolean
         ) then raise exception 'R4D_BILATERAL_ACCEPTANCE_REQUIRED' using errcode = 'PT409'; end if;
      insert into public.pachanga_competition_postponement_responses(
        postponement_request_id, responding_entry_id, responder_kind,
        response_kind, proposed_start, proposed_end, proposed_timezone,
        proposed_venue_id, proposed_venue_label, proposed_venue_status,
        public_summary, operation_id, responded_by, server_sequence
      ) values (
        request_row.id, null, 'ORGANIZER', selected_response_kind,
        request_row.proposed_start, request_row.proposed_end, request_row.proposed_timezone,
        request_row.proposed_venue_id, request_row.proposed_venue_label,
        request_row.proposed_venue_status, selected_public_summary,
        operation_id, actor_id, sequence_value
      ) returning * into response_row;
      update public.pachanga_competition_postponement_requests requests set
        organizer_response = case selected_response_kind when 'APPROVE' then 'APPROVED' else 'DENIED' end,
        status = case selected_response_kind when 'APPROVE' then 'approved' else 'denied' end,
        current_response_id = response_row.id, resolved_at = server_now,
        revision = requests.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where requests.id = request_row.id returning * into request_row;
    else
      raise exception 'R4D_POSTPONEMENT_RESPONSE_INVALID' using errcode = '22023';
    end if;
    if request_row.team_response = 'ACCEPTED'
       and request_row.organizer_response = 'NOT_REQUIRED'
       and request_row.status = 'awaiting_response' then
      update public.pachanga_competition_postponement_requests requests set
        status = 'approved', resolved_at = server_now,
        revision = requests.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where requests.id = request_row.id returning * into request_row;
    end if;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'POSTPONEMENT_RESPONSE', response_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    if request_row.status = 'approved' then
      perform private.pachanga_league_operational_assert_flags_v1(
        false, request_row.proposed_start is not null, false,
        false, false, false, true
      );
      selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
        context_row.id, 'RESCHEDULE_MATCH', 'POSTPONEMENT_REQUEST', request_row.id,
        selected_reason_code, selected_public_summary, null,
        operation_id, actor_id, sequence_value,
        case when request_row.organizer_response = 'NOT_REQUIRED'
          then request_row.id else null end
      );
      selected_resource_key := case request_row.proposed_venue_status
        when 'SAVED' then 'venue:' || request_row.proposed_venue_id::text
        when 'LABEL' then 'label:' || encode(extensions.digest(convert_to(lower(request_row.proposed_venue_label), 'UTF8'), 'sha256'), 'hex')
        else null end;
      fixture_result := private.pachanga_league_operational_create_fixture_change_v1(
        context_row.id,
        case when request_row.proposed_start is null then 'POSTPONEMENT' else 'RESCHEDULE' end,
        case when request_row.proposed_start is null then 'postponed' else 'scheduled' end,
        coalesce(request_row.proposed_start, context_row.scheduled_start),
        coalesce(request_row.proposed_end, context_row.scheduled_end),
        coalesce(request_row.proposed_timezone, context_row.timezone),
        case when request_row.proposed_venue_status = 'TBD' then null else request_row.proposed_venue_id end,
        case when request_row.proposed_venue_status = 'TBD' then null else request_row.proposed_venue_label end,
        request_row.proposed_venue_status, selected_resource_key,
        selected_reason_code, selected_public_summary,
        'ADMINISTRATIVE_DECISION', selected_decision_id,
        operation_id, actor_id, sequence_value, policy
      );
      selected_fixture_change_id := (fixture_result ->> 'fixtureChangeId')::uuid;
      perform private.pachanga_league_operational_add_admin_effect_v1(
        selected_decision_id, 'RESCHEDULE_MATCH',
        jsonb_build_object('source', 'POSTPONEMENT_REQUEST', 'requestId', request_row.id),
        selected_fixture_change_id, null, null, sequence_value
      );
      update public.pachanga_competition_postponement_requests requests set
        approved_fixture_change_id = selected_fixture_change_id
      where requests.id = request_row.id;
      perform private.pachanga_league_operational_store_evidence_v1(
        context_row.competition_id, 'ADMINISTRATIVE_DECISION', selected_decision_id,
        payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
        operation_id, sequence_value
      );
    else
      update public.pachanga_competition_match_contexts contexts set
        revision = contexts.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where contexts.id = context_row.id;
    end if;
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    event_payload := jsonb_build_object(
      'requestId', request_row.id, 'responseId', response_row.id,
      'responseKind', selected_response_kind, 'status', request_row.status,
      'fixtureChangeId', selected_fixture_change_id
    );

  elsif action_name = 'postponement.withdraw' then
    perform private.pachanga_league_operational_assert_flags_v1(true, false, false, false, false, false, false);
    selected_request_id := nullif(payload ->> 'requestId', '')::uuid;
    select * into request_row
    from public.pachanga_competition_postponement_requests requests
    where requests.id = selected_request_id
      and requests.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_POSTPONEMENT_REQUEST_NOT_FOUND' using errcode = 'P0002'; end if;
    perform private.pachanga_league_operational_assert_team_actor_v1(
      request_row.requesting_entry_id, actor_id
    );
    if request_row.status <> 'awaiting_response' then
      raise exception 'R4D_POSTPONEMENT_REQUEST_NOT_PENDING' using errcode = 'PT409';
    end if;
    update public.pachanga_competition_postponement_requests requests set
      status = 'withdrawn', resolved_at = server_now,
      revision = requests.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where requests.id = request_row.id returning * into request_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'POSTPONEMENT_REQUEST', request_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object('requestId', request_row.id, 'status', request_row.status);

  elsif action_name = 'postponement.expire' then
    perform private.pachanga_league_operational_assert_flags_v1(true, false, false, false, false, false, false);
    if actor_kind <> 'service_authority' then
      raise exception 'SERVICE_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    selected_request_id := nullif(payload ->> 'requestId', '')::uuid;
    select * into request_row
    from public.pachanga_competition_postponement_requests requests
    where requests.id = selected_request_id
      and requests.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_POSTPONEMENT_REQUEST_NOT_FOUND' using errcode = 'P0002'; end if;
    if request_row.status <> 'awaiting_response' or server_now <= request_row.response_deadline then
      raise exception 'R4D_POSTPONEMENT_NOT_EXPIRABLE' using errcode = 'PT409';
    end if;
    insert into public.pachanga_competition_postponement_responses(
      postponement_request_id, responder_kind, response_kind,
      public_summary, operation_id, responded_by, server_sequence
    ) values (
      request_row.id, 'SERVICE',
      case request_row.deadline_policy when 'ESCALATE_TO_ORGANIZER' then 'ESCALATE' else 'DENY' end,
      case request_row.deadline_policy
        when 'ESCALATE_TO_ORGANIZER' then 'Solicitud escalada al organizador por deadline.'
        when 'AUTO_DENY' then 'Solicitud denegada automáticamente por deadline.'
        else 'Solicitud expirada por deadline.' end,
      operation_id, null, sequence_value
    ) returning * into response_row;
    update public.pachanga_competition_postponement_requests requests set
      status = case requests.deadline_policy
        when 'EXPIRE' then 'expired' when 'AUTO_DENY' then 'denied'
        else 'awaiting_response' end,
      organizer_response = case requests.deadline_policy
        when 'ESCALATE_TO_ORGANIZER' then 'ESCALATED' else requests.organizer_response end,
      current_response_id = response_row.id,
      resolved_at = case when requests.deadline_policy = 'ESCALATE_TO_ORGANIZER'
        then null else server_now end,
      revision = requests.revision + 1,
      server_sequence = sequence_value, updated_at = server_now
    where requests.id = request_row.id returning * into request_row;
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object(
      'requestId', request_row.id, 'status', request_row.status,
      'deadlinePolicy', request_row.deadline_policy,
      'organizerResponse', request_row.organizer_response
    );

  elsif action_name in ('fixture.reschedule', 'fixture.change_venue', 'fixture.cancel') then
    if action_name = 'fixture.reschedule' then
      perform private.pachanga_league_operational_assert_flags_v1(false, true, false, false, false, false, true);
      selected_decision_type := 'RESCHEDULE_MATCH';
      selected_status := 'scheduled';
    elsif action_name = 'fixture.change_venue' then
      perform private.pachanga_league_operational_assert_flags_v1(false, false, true, false, false, false, true);
      selected_decision_type := 'CHANGE_VENUE';
      selected_status := context_row.status;
    else
      perform private.pachanga_league_operational_assert_flags_v1(false, false, false, false, false, false, true);
      selected_decision_type := 'CANCEL_MATCH';
      selected_status := 'cancelled';
      if upper(coalesce(payload ->> 'cancellationOutcome', '')) <> 'NO_RESULT' then
        raise exception 'R4D_CANCELLATION_OUTCOME_REQUIRED' using errcode = '22023';
      end if;
    end if;
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    if context_row.status in ('official', 'retired') then
      raise exception 'R4D_FIXTURE_CHANGE_WINDOW_CLOSED' using errcode = 'PT409';
    end if;
    selected_start := case when action_name = 'fixture.reschedule'
      then nullif(payload ->> 'scheduledStart', '')::timestamptz else context_row.scheduled_start end;
    selected_end := case when action_name = 'fixture.reschedule'
      then nullif(payload ->> 'scheduledEnd', '')::timestamptz else context_row.scheduled_end end;
    selected_timezone := case when action_name = 'fixture.reschedule'
      then coalesce(nullif(left(trim(coalesce(payload ->> 'timezone', '')), 80), ''), context_row.timezone)
      else context_row.timezone end;
    selected_venue_id := case when action_name = 'fixture.change_venue'
      then nullif(payload ->> 'venueId', '')::uuid else context_row.venue_id end;
    selected_venue_label := case when action_name = 'fixture.change_venue'
      then nullif(left(trim(coalesce(payload ->> 'venueLabel', '')), 160), '') else context_row.venue_label end;
    selected_venue_status := case when action_name = 'fixture.change_venue'
      then upper(coalesce(nullif(payload ->> 'venueStatus', ''),
        case when selected_venue_id is not null then 'SAVED'
          when selected_venue_label is not null then 'LABEL' else 'TBD' end))
      else case context_row.venue_status
        when 'CONFIRMED' then case when context_row.venue_id is null then 'LABEL' else 'SAVED' end
        else context_row.venue_status end end;
    selected_resource_key := case selected_venue_status
      when 'SAVED' then 'venue:' || selected_venue_id::text
      when 'LABEL' then 'label:' || encode(extensions.digest(convert_to(lower(selected_venue_label), 'UTF8'), 'sha256'), 'hex')
      else case when action_name = 'fixture.change_venue'
        then null else current_resource_key end end;
    if action_name = 'fixture.change_venue' then
      selected_reason_code := upper(selected_reason_code);
      if selected_reason_code not in (
        'WEATHER', 'PITCH_UNAVAILABLE', 'LIGHTING',
        'FACILITY_CLOSED', 'SAFETY', 'OTHER'
      ) then raise exception 'R4D_VENUE_REASON_INVALID' using errcode = '22023'; end if;
      insert into public.pachanga_competition_venue_change_requests(
        competition_id, canonical_match_id, competition_match_context_id,
        requesting_entry_id, rule_revision_id, requested_venue_id,
        requested_venue_label, requested_venue_status, requested_resource_key,
        reason_code, public_summary, status, operation_id, server_sequence,
        requested_by, resolved_at
      ) values (
        context_row.competition_id, context_row.canonical_match_id, context_row.id,
        null, context_row.rule_revision_id, selected_venue_id,
        selected_venue_label, selected_venue_status, selected_resource_key,
        selected_reason_code, selected_public_summary, 'approved', operation_id,
        sequence_value, actor_id, server_now
      ) returning * into venue_request_row;
      selected_request_id := venue_request_row.id;
      insert into public.pachanga_competition_venue_condition_decisions(
        venue_change_request_id, competition_id, canonical_match_id,
        competition_match_context_id, rule_revision_id, reason_code, outcome,
        public_summary, authority_role, operation_id, decided_by, server_sequence
      ) values (
        venue_request_row.id, context_row.competition_id,
        context_row.canonical_match_id, context_row.id,
        context_row.rule_revision_id, selected_reason_code, 'venue_changed',
        selected_public_summary, authority_role, operation_id, actor_id,
        sequence_value
      ) returning * into venue_decision_row;
      update public.pachanga_competition_venue_change_requests requests set
        current_decision_id = venue_decision_row.id,
        revision = requests.revision + 1,
        server_sequence = sequence_value,
        updated_at = server_now
      where requests.id = venue_request_row.id
      returning * into venue_request_row;
    else
      select decisions.id into selected_previous_decision_id
      from public.pachanga_competition_administrative_decisions decisions
      where decisions.competition_id = context_row.competition_id
        and decisions.target_type = 'MATCH_CONTEXT'
        and decisions.target_id = context_row.id
        and decisions.decision_type = selected_decision_type
        and decisions.status = 'published'
      order by decisions.server_sequence desc, decisions.id desc limit 1;
    end if;
    selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
      context_row.id, selected_decision_type,
      case when action_name = 'fixture.change_venue'
        then 'VENUE_CHANGE_REQUEST' else 'MATCH_CONTEXT' end,
      case when action_name = 'fixture.change_venue'
        then selected_request_id else context_row.id end,
      selected_reason_code, selected_public_summary, selected_previous_decision_id,
      operation_id, actor_id, sequence_value
    );
    fixture_result := private.pachanga_league_operational_create_fixture_change_v1(
      context_row.id,
      case action_name when 'fixture.reschedule' then 'RESCHEDULE'
        when 'fixture.change_venue' then 'VENUE_CHANGE' else 'CANCELLATION' end,
      selected_status, selected_start, selected_end, selected_timezone,
      selected_venue_id, selected_venue_label, selected_venue_status,
      selected_resource_key, selected_reason_code, selected_public_summary,
      'ADMINISTRATIVE_DECISION', selected_decision_id,
      operation_id, actor_id, sequence_value, policy
    );
    selected_fixture_change_id := (fixture_result ->> 'fixtureChangeId')::uuid;
    if action_name = 'fixture.change_venue' then
      update public.pachanga_competition_venue_change_requests requests set
        approved_fixture_change_id = selected_fixture_change_id,
        server_sequence = sequence_value,
        updated_at = server_now
      where requests.id = venue_request_row.id;
      perform private.pachanga_league_operational_store_evidence_v1(
        context_row.competition_id, 'VENUE_CHANGE_REQUEST', venue_request_row.id,
        payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
        operation_id, sequence_value
      );
      perform private.pachanga_league_operational_store_evidence_v1(
        context_row.competition_id, 'VENUE_CONDITION_DECISION', venue_decision_row.id,
        payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
        operation_id, sequence_value
      );
    end if;
    perform private.pachanga_league_operational_add_admin_effect_v1(
      selected_decision_id, selected_decision_type,
      case when selected_decision_type = 'CANCEL_MATCH'
        then jsonb_build_object('cancellationOutcome', 'NO_RESULT')
        else jsonb_build_object('validatedBy', 'R4D_SERVER') end,
      selected_fixture_change_id, null, null, sequence_value
    );
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'ADMINISTRATIVE_DECISION', selected_decision_id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    event_payload := jsonb_build_object(
      'decisionId', selected_decision_id,
      'fixtureChangeId', selected_fixture_change_id,
      'venueChangeRequestId', venue_request_row.id,
      'venueConditionDecisionId', venue_decision_row.id,
      'changeType', fixture_result ->> 'changeType',
      'status', context_row.status
    );

  elsif action_name = 'late_arrival.report' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, true, false, false, false);
    if context_row.status not in ('ready', 'in_progress')
       or context_row.scheduled_start is null
       or server_now < context_row.scheduled_start then
      raise exception 'R4D_LATE_ARRIVAL_NOT_REPORTABLE' using errcode = 'PT409';
    end if;
    selected_entry_id := nullif(payload ->> 'responsibleEntryId', '')::uuid;
    if selected_entry_id not in (context_row.home_entry_id, context_row.away_entry_id) then
      raise exception 'R4D_ENTRY_NOT_IN_MATCH' using errcode = '22023';
    end if;
    if not private.pachanga_competition_can_v1(context_row.competition_id, actor_id, 'operations_manage') then
      target_entry_id := case when selected_entry_id = context_row.home_entry_id
        then context_row.away_entry_id else context_row.home_entry_id end;
      perform private.pachanga_league_operational_assert_team_actor_v1(target_entry_id, actor_id);
    end if;
    insert into public.pachanga_competition_late_arrival_incidents(
      competition_id, canonical_match_id, competition_match_context_id,
      responsible_entry_id, rule_revision_id, scheduled_start, grace_deadline,
      status, reported_at, operation_id, server_sequence, reported_by
    ) values (
      context_row.competition_id, context_row.canonical_match_id, context_row.id,
      selected_entry_id, context_row.rule_revision_id, context_row.scheduled_start,
      context_row.scheduled_start + make_interval(
        mins => (policy ->> 'gracePeriodMinutes')::integer
      ), 'reported', server_now, operation_id, sequence_value, actor_id
    ) returning * into late_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'LATE_ARRIVAL_INCIDENT', late_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object(
      'incidentId', late_row.id, 'responsibleEntryId', late_row.responsible_entry_id,
      'status', late_row.status, 'graceDeadline', late_row.grace_deadline
    );

  elsif action_name = 'late_arrival.confirm_arrival' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, true, false, false, false);
    selected_incident_id := nullif(payload ->> 'incidentId', '')::uuid;
    select * into late_row
    from public.pachanga_competition_late_arrival_incidents incidents
    where incidents.id = selected_incident_id
      and incidents.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_LATE_ARRIVAL_NOT_FOUND' using errcode = 'P0002'; end if;
    if late_row.status <> 'reported' then
      raise exception 'R4D_LATE_ARRIVAL_NOT_PENDING' using errcode = 'PT409';
    end if;
    if not private.pachanga_competition_can_v1(context_row.competition_id, actor_id, 'operations_manage') then
      perform private.pachanga_league_operational_assert_team_actor_v1(
        late_row.responsible_entry_id, actor_id
      );
    end if;
    update public.pachanga_competition_late_arrival_incidents incidents set
      status = case when server_now <= incidents.grace_deadline
        then 'arrived_within_policy' else 'arrived_late' end,
      arrival_at = server_now, revision = incidents.revision + 1,
      server_sequence = sequence_value, updated_at = server_now
    where incidents.id = late_row.id returning * into late_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'LATE_ARRIVAL_INCIDENT', late_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object(
      'incidentId', late_row.id, 'status', late_row.status, 'arrivalAt', late_row.arrival_at
    );

  elsif action_name = 'late_arrival.escalate' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, true, true, false, true);
    selected_incident_id := nullif(payload ->> 'incidentId', '')::uuid;
    select * into late_row
    from public.pachanga_competition_late_arrival_incidents incidents
    where incidents.id = selected_incident_id
      and incidents.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_LATE_ARRIVAL_NOT_FOUND' using errcode = 'P0002'; end if;
    if late_row.status <> 'reported' or server_now <= late_row.grace_deadline then
      raise exception 'R4D_GRACE_DEADLINE_NOT_REACHED' using errcode = 'PT409';
    end if;
    if nullif(trim(coalesce(payload ->> 'reasonText', '')), '') is null then
      raise exception 'R4D_NO_SHOW_EVIDENCE_REQUIRED' using errcode = '22023';
    end if;
    if not private.pachanga_competition_can_v1(context_row.competition_id, actor_id, 'operations_manage') then
      target_entry_id := case when late_row.responsible_entry_id = context_row.home_entry_id
        then context_row.away_entry_id else context_row.home_entry_id end;
      perform private.pachanga_league_operational_assert_team_actor_v1(target_entry_id, actor_id);
    end if;
    insert into public.pachanga_competition_no_show_incidents(
      competition_id, canonical_match_id, competition_match_context_id,
      responsible_entry_id, late_arrival_incident_id, rule_revision_id,
      status, scheduled_start, grace_deadline, reason_code, public_summary,
      operation_id, server_sequence, reported_by
    ) values (
      context_row.competition_id, context_row.canonical_match_id, context_row.id,
      late_row.responsible_entry_id, late_row.id, context_row.rule_revision_id,
      'under_review', late_row.scheduled_start, late_row.grace_deadline,
      selected_reason_code, selected_public_summary,
      operation_id, sequence_value, actor_id
    ) returning * into no_show_row;
    update public.pachanga_competition_late_arrival_incidents incidents set
      status = 'escalated_to_no_show', escalated_no_show_incident_id = no_show_row.id,
      revision = incidents.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where incidents.id = late_row.id returning * into late_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'NO_SHOW_INCIDENT', no_show_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      status = 'administrative_review', revision = contexts.revision + 1,
      server_sequence = sequence_value, updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object(
      'lateArrivalIncidentId', late_row.id, 'noShowIncidentId', no_show_row.id,
      'status', no_show_row.status
    );

  elsif action_name = 'no_show.report' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, true, true, false, true);
    if context_row.status in ('official', 'cancelled', 'abandoned', 'retired')
       or context_row.scheduled_start is null then
      raise exception 'R4D_NO_SHOW_NOT_REPORTABLE' using errcode = 'PT409';
    end if;
    if nullif(trim(coalesce(payload ->> 'reasonText', '')), '') is null then
      raise exception 'R4D_NO_SHOW_EVIDENCE_REQUIRED' using errcode = '22023';
    end if;
    selected_entry_id := nullif(payload ->> 'responsibleEntryId', '')::uuid;
    if selected_entry_id not in (context_row.home_entry_id, context_row.away_entry_id) then
      raise exception 'R4D_ENTRY_NOT_IN_MATCH' using errcode = '22023';
    end if;
    response_deadline := context_row.scheduled_start + make_interval(
      mins => (policy ->> 'gracePeriodMinutes')::integer
    );
    if server_now <= response_deadline then
      raise exception 'R4D_GRACE_DEADLINE_NOT_REACHED' using errcode = 'PT409';
    end if;
    if not private.pachanga_competition_can_v1(context_row.competition_id, actor_id, 'operations_manage') then
      target_entry_id := case when selected_entry_id = context_row.home_entry_id
        then context_row.away_entry_id else context_row.home_entry_id end;
      perform private.pachanga_league_operational_assert_team_actor_v1(target_entry_id, actor_id);
    end if;
    insert into public.pachanga_competition_no_show_incidents(
      competition_id, canonical_match_id, competition_match_context_id,
      responsible_entry_id, rule_revision_id, status, scheduled_start,
      grace_deadline, reason_code, public_summary, operation_id,
      server_sequence, reported_by
    ) values (
      context_row.competition_id, context_row.canonical_match_id, context_row.id,
      selected_entry_id, context_row.rule_revision_id, 'under_review',
      context_row.scheduled_start, response_deadline,
      selected_reason_code, selected_public_summary,
      operation_id, sequence_value, actor_id
    ) returning * into no_show_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'NO_SHOW_INCIDENT', no_show_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      status = 'administrative_review', revision = contexts.revision + 1,
      server_sequence = sequence_value, updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object(
      'incidentId', no_show_row.id, 'responsibleEntryId', selected_entry_id,
      'status', no_show_row.status
    );

  elsif action_name in ('no_show.confirm', 'no_show.reject', 'no_show.resolve') then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, true, true, false, true);
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    selected_incident_id := nullif(payload ->> 'incidentId', '')::uuid;
    select * into no_show_row
    from public.pachanga_competition_no_show_incidents incidents
    where incidents.id = selected_incident_id
      and incidents.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_NO_SHOW_NOT_FOUND' using errcode = 'P0002'; end if;
    if action_name = 'no_show.confirm' then
      if no_show_row.status not in ('reported', 'under_review')
         or server_now <= no_show_row.grace_deadline then
        raise exception 'R4D_NO_SHOW_NOT_CONFIRMABLE' using errcode = 'PT409';
      end if;
      update public.pachanga_competition_no_show_incidents incidents set
        status = 'confirmed', reviewed_by = actor_id,
        revision = incidents.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where incidents.id = no_show_row.id returning * into no_show_row;
      selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
        context_row.id, 'SET_OFFICIAL_RESULT', 'NO_SHOW_INCIDENT', no_show_row.id,
        selected_reason_code, selected_public_summary, null,
        operation_id, actor_id, sequence_value
      );
      official_result := private.pachanga_league_operational_no_show_result_v1(
        context_row.id, no_show_row.id, no_show_row.responsible_entry_id,
        operation_id, actor_id, authority_role, selected_reason_code,
        selected_public_summary, sequence_value, policy
      );
      selected_official_decision_id := (official_result ->> 'decisionId')::uuid;
      update public.pachanga_competition_no_show_incidents incidents set
        official_result_decision_id = selected_official_decision_id,
        server_sequence = sequence_value, updated_at = server_now
      where incidents.id = no_show_row.id;
      perform private.pachanga_league_operational_add_admin_effect_v1(
        selected_decision_id, 'SET_OFFICIAL_RESULT',
        jsonb_build_object(
          'source', 'NO_SHOW_INCIDENT', 'incidentId', no_show_row.id,
          'outcome', official_result ->> 'outcome'
        ), null, selected_official_decision_id, null, sequence_value
      );
      perform private.pachanga_league_operational_store_evidence_v1(
        context_row.competition_id, 'ADMINISTRATIVE_DECISION', selected_decision_id,
        payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
        operation_id, sequence_value
      );
    elsif action_name = 'no_show.reject' then
      if no_show_row.status not in ('reported', 'under_review') then
        raise exception 'R4D_NO_SHOW_NOT_REVIEWABLE' using errcode = 'PT409';
      end if;
      update public.pachanga_competition_no_show_incidents incidents set
        status = 'rejected', reviewed_by = actor_id, resolved_at = server_now,
        revision = incidents.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where incidents.id = no_show_row.id returning * into no_show_row;
      update public.pachanga_competition_match_contexts contexts set
        status = case when contexts.scheduled_start > server_now then 'scheduled' else 'ready' end,
        revision = contexts.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where contexts.id = context_row.id;
    else
      if no_show_row.status <> 'confirmed' then
        raise exception 'R4D_NO_SHOW_NOT_RESOLVABLE' using errcode = 'PT409';
      end if;
      update public.pachanga_competition_no_show_incidents incidents set
        status = 'resolved', reviewed_by = actor_id, resolved_at = server_now,
        revision = incidents.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where incidents.id = no_show_row.id returning * into no_show_row;
      update public.pachanga_competition_match_contexts contexts set
        revision = contexts.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where contexts.id = context_row.id;
    end if;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'NO_SHOW_INCIDENT', no_show_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    select * into round_row from public.pachanga_competition_rounds rounds
    where rounds.id = context_row.round_id;
    event_payload := jsonb_build_object(
      'incidentId', no_show_row.id, 'status', no_show_row.status,
      'officialResultDecisionId', selected_official_decision_id,
      'administrativeDecisionId', selected_decision_id
    );

  elsif action_name = 'suspension.report' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, false, false, true, false);
    if context_row.status <> 'in_progress' then
      raise exception 'R4D_SUSPENSION_REQUIRES_STARTED_MATCH' using errcode = 'PT409';
    end if;
    if nullif(trim(coalesce(payload ->> 'reasonText', '')), '') is null then
      raise exception 'R4D_SUSPENSION_EVIDENCE_REQUIRED' using errcode = '22023';
    end if;
    if not private.pachanga_competition_can_v1(context_row.competition_id, actor_id, 'operations_manage') then
      selected_entry_id := nullif(payload ->> 'reportingEntryId', '')::uuid;
      if selected_entry_id not in (context_row.home_entry_id, context_row.away_entry_id) then
        raise exception 'R4D_ENTRY_NOT_IN_MATCH' using errcode = '22023';
      end if;
      perform private.pachanga_league_operational_assert_team_actor_v1(selected_entry_id, actor_id);
    end if;
    selected_minute := nullif(payload ->> 'reportedMinute', '')::integer;
    if selected_minute is null or selected_minute < 0 or selected_minute > 300 then
      raise exception 'R4D_SUSPENSION_MINUTE_INVALID' using errcode = '22023';
    end if;
    select results.* into result_row
    from public.pachanga_competition_sporting_results results
    where results.competition_match_context_id = context_row.id;
    if result_row.id is not null and result_row.current_revision_id is not null then
      select * into result_revision
      from public.pachanga_competition_sporting_result_revisions revisions
      where revisions.id = result_row.current_revision_id;
      selected_score_home := result_revision.score_home;
      selected_score_away := result_revision.score_away;
      if payload ? 'partialScoreHome' and (
        nullif(payload ->> 'partialScoreHome', '')::integer <> selected_score_home
        or nullif(payload ->> 'partialScoreAway', '')::integer <> selected_score_away
      ) then
        raise exception 'R4D_PARTIAL_SCORE_SNAPSHOT_MISMATCH' using errcode = 'PT409';
      end if;
    else
      begin
        selected_score_home := nullif(payload ->> 'partialScoreHome', '')::integer;
        selected_score_away := nullif(payload ->> 'partialScoreAway', '')::integer;
      exception when others then
        raise exception 'R4D_PARTIAL_SCORE_INVALID' using errcode = '22023';
      end;
    end if;
    if selected_score_home is null or selected_score_away is null
       or selected_score_home < 0 or selected_score_home > 99
       or selected_score_away < 0 or selected_score_away > 99 then
      raise exception 'R4D_PARTIAL_SCORE_REQUIRED' using errcode = '22023';
    end if;
    insert into public.pachanga_competition_match_suspensions(
      competition_id, canonical_match_id, competition_match_context_id,
      rule_revision_id, reported_minute, sporting_score_home,
      sporting_score_away, sporting_result_revision_id, reason_code,
      public_summary, status, operation_id, server_sequence, reported_by
    ) values (
      context_row.competition_id, context_row.canonical_match_id, context_row.id,
      context_row.rule_revision_id, selected_minute, selected_score_home,
      selected_score_away, result_revision.id, selected_reason_code,
      selected_public_summary, 'reported', operation_id, sequence_value, actor_id
    ) returning * into suspension_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'MATCH_SUSPENSION', suspension_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      status = 'administrative_review', revision = contexts.revision + 1,
      server_sequence = sequence_value, updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object(
      'suspensionId', suspension_row.id, 'status', suspension_row.status,
      'reportedMinute', suspension_row.reported_minute,
      'scoreHome', suspension_row.sporting_score_home,
      'scoreAway', suspension_row.sporting_score_away
    );

  elsif action_name = 'suspension.confirm' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, false, false, true, true);
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    selected_suspension_id := nullif(payload ->> 'suspensionId', '')::uuid;
    select * into suspension_row
    from public.pachanga_competition_match_suspensions suspensions
    where suspensions.id = selected_suspension_id
      and suspensions.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_SUSPENSION_NOT_FOUND' using errcode = 'P0002'; end if;
    if suspension_row.status <> 'reported' then
      raise exception 'R4D_SUSPENSION_NOT_CONFIRMABLE' using errcode = 'PT409';
    end if;
    update public.pachanga_competition_match_suspensions suspensions set
      status = 'confirmed', confirmed_by = actor_id, confirmed_at = server_now,
      revision = suspensions.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where suspensions.id = suspension_row.id returning * into suspension_row;
    update public.pachanga_competition_match_contexts contexts set
      status = 'suspended', revision = contexts.revision + 1,
      server_sequence = sequence_value, updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'MATCH_SUSPENSION', suspension_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    event_payload := jsonb_build_object('suspensionId', suspension_row.id, 'status', suspension_row.status);

  elsif action_name in ('suspension.schedule_resume', 'suspension.order_replay') then
    perform private.pachanga_league_operational_assert_flags_v1(
      false, true, false, false, false, true, true
    );
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    selected_suspension_id := nullif(payload ->> 'suspensionId', '')::uuid;
    select * into suspension_row
    from public.pachanga_competition_match_suspensions suspensions
    where suspensions.id = selected_suspension_id
      and suspensions.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4D_SUSPENSION_NOT_FOUND' using errcode = 'P0002'; end if;
    if suspension_row.status <> 'confirmed' then
      raise exception 'R4D_SUSPENSION_DECISION_NOT_ALLOWED' using errcode = 'PT409';
    end if;
    selected_start := nullif(payload ->> 'scheduledStart', '')::timestamptz;
    selected_end := nullif(payload ->> 'scheduledEnd', '')::timestamptz;
    selected_timezone := coalesce(nullif(left(trim(coalesce(payload ->> 'timezone', '')), 80), ''), context_row.timezone);
    selected_venue_id := nullif(payload ->> 'venueId', '')::uuid;
    selected_venue_label := nullif(left(trim(coalesce(payload ->> 'venueLabel', '')), 160), '');
    selected_venue_status := upper(coalesce(nullif(payload ->> 'venueStatus', ''),
      case when selected_venue_id is not null then 'SAVED'
        when selected_venue_label is not null then 'LABEL' else 'TBD' end));
    selected_resource_key := case selected_venue_status
      when 'SAVED' then 'venue:' || selected_venue_id::text
      when 'LABEL' then 'label:' || encode(extensions.digest(convert_to(lower(selected_venue_label), 'UTF8'), 'sha256'), 'hex')
      else null end;
    if action_name = 'suspension.schedule_resume' then
      selected_decision_type := 'RESUME_FROM_MINUTE';
      selected_minute := coalesce(nullif(payload ->> 'resumeMinute', '')::integer, suspension_row.reported_minute);
      selected_status := 'resume_scheduled';
    else
      selected_decision_type := 'ORDER_REPLAY';
      selected_minute := 0;
      selected_status := 'replay_ordered';
    end if;
    insert into public.pachanga_competition_match_resumption_decisions(
      match_suspension_id, decision_type, resume_minute,
      initial_score_home, initial_score_away, effective_scheduled_start,
      effective_scheduled_end, effective_timezone, effective_venue_id,
      effective_venue_label, effective_venue_status, effective_resource_key,
      reuse_canonical_match, eligibility_policy_snapshot, public_summary,
      status, operation_id, authority_role, decided_by, server_sequence
    ) values (
      suspension_row.id,
      case when action_name = 'suspension.schedule_resume' then 'RESUME' else 'REPLAY' end,
      selected_minute,
      case when action_name = 'suspension.schedule_resume' then suspension_row.sporting_score_home else 0 end,
      case when action_name = 'suspension.schedule_resume' then suspension_row.sporting_score_away else 0 end,
      selected_start, selected_end, selected_timezone, selected_venue_id,
      selected_venue_label, selected_venue_status, selected_resource_key, true,
      policy -> 'resumptionEligibilityPolicy', selected_public_summary,
      'published', operation_id, authority_role, actor_id, sequence_value
    ) returning * into resumption_row;
    selected_resumption_id := resumption_row.id;
    selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
      context_row.id, selected_decision_type, 'MATCH_SUSPENSION', suspension_row.id,
      selected_reason_code, selected_public_summary, null,
      operation_id, actor_id, sequence_value
    );
    fixture_result := private.pachanga_league_operational_create_fixture_change_v1(
      context_row.id,
      case when action_name = 'suspension.schedule_resume' then 'RESUMPTION' else 'REPLAY' end,
      case when action_name = 'suspension.schedule_resume' then 'suspended' else 'scheduled' end,
      selected_start, selected_end, selected_timezone,
      selected_venue_id, selected_venue_label, selected_venue_status,
      selected_resource_key, selected_reason_code, selected_public_summary,
      'MATCH_SUSPENSION', suspension_row.id,
      operation_id, actor_id, sequence_value, policy
    );
    selected_fixture_change_id := (fixture_result ->> 'fixtureChangeId')::uuid;
    update public.pachanga_competition_match_suspensions suspensions set
      status = selected_status, current_resumption_decision_id = resumption_row.id,
      revision = suspensions.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where suspensions.id = suspension_row.id returning * into suspension_row;
    perform private.pachanga_league_operational_add_admin_effect_v1(
      selected_decision_id, selected_decision_type,
      jsonb_build_object(
        'sameCanonicalMatch', true,
        'suspensionId', suspension_row.id,
        'resumptionDecisionId', resumption_row.id
      ), selected_fixture_change_id, null, resumption_row.id, sequence_value
    );
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'MATCH_RESUMPTION_DECISION', resumption_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    event_payload := jsonb_build_object(
      'suspensionId', suspension_row.id, 'status', suspension_row.status,
      'resumptionDecisionId', resumption_row.id,
      'fixtureChangeId', selected_fixture_change_id,
      'sameCanonicalMatch', true
    );

  elsif action_name = 'suspension.resume' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, false, false, true, true);
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    selected_suspension_id := nullif(payload ->> 'suspensionId', '')::uuid;
    select * into suspension_row
    from public.pachanga_competition_match_suspensions suspensions
    where suspensions.id = selected_suspension_id
      and suspensions.competition_match_context_id = context_row.id
    for update;
    if not found or suspension_row.status <> 'resume_scheduled' then
      raise exception 'R4D_SUSPENSION_NOT_RESUMABLE' using errcode = 'PT409';
    end if;
    update public.pachanga_competition_match_suspensions suspensions set
      status = 'resumed', resolved_at = server_now,
      revision = suspensions.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where suspensions.id = suspension_row.id returning * into suspension_row;
    update public.pachanga_competition_match_contexts contexts set
      status = 'in_progress', revision = contexts.revision + 1,
      server_sequence = sequence_value, updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'MATCH_SUSPENSION', suspension_row.id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    event_payload := jsonb_build_object(
      'suspensionId', suspension_row.id, 'status', suspension_row.status,
      'canonicalMatchId', context_row.canonical_match_id
    );

  elsif action_name in ('suspension.resolve', 'suspension.cancel') then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, false, false, true, true);
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    selected_suspension_id := nullif(payload ->> 'suspensionId', '')::uuid;
    select * into suspension_row
    from public.pachanga_competition_match_suspensions suspensions
    where suspensions.id = selected_suspension_id
      and suspensions.competition_match_context_id = context_row.id
    for update;
    if not found or suspension_row.status not in ('reported', 'confirmed', 'resume_scheduled', 'replay_ordered') then
      raise exception 'R4D_SUSPENSION_NOT_RESOLVABLE' using errcode = 'PT409';
    end if;
    if action_name = 'suspension.resolve'
       and upper(coalesce(payload ->> 'resolutionType', '')) <> 'PENDING_ADMINISTRATIVE_DECISION' then
      raise exception 'R4D_SUSPENSION_RESOLUTION_TYPE_REQUIRED' using errcode = '22023';
    end if;
    if action_name = 'suspension.cancel'
       and upper(coalesce(payload ->> 'cancellationOutcome', '')) <> 'NO_RESULT' then
      raise exception 'R4D_CANCELLATION_OUTCOME_REQUIRED' using errcode = '22023';
    end if;
    selected_status := case action_name when 'suspension.resolve'
      then 'administrative_resolution' else 'cancelled' end;
    if action_name = 'suspension.cancel' then
      selected_decision_type := 'CANCEL_MATCH';
      selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
        context_row.id, selected_decision_type, 'MATCH_SUSPENSION', suspension_row.id,
        selected_reason_code, selected_public_summary, null,
        operation_id, actor_id, sequence_value
      );
    end if;
    update public.pachanga_competition_match_suspensions suspensions set
      status = selected_status, resolved_at = server_now,
      revision = suspensions.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where suspensions.id = suspension_row.id returning * into suspension_row;
    update public.pachanga_competition_match_contexts contexts set
      status = case action_name when 'suspension.resolve'
        then 'administrative_review' else 'cancelled' end,
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = server_now
    where contexts.id = context_row.id returning * into context_row;
    if selected_decision_id is not null then
      perform private.pachanga_league_operational_add_admin_effect_v1(
        selected_decision_id, selected_decision_type,
        jsonb_build_object('suspensionId', suspension_row.id, 'noSportingResult', true),
        null, null, null, sequence_value
      );
    end if;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id,
      case when selected_decision_id is null
        then 'MATCH_SUSPENSION' else 'ADMINISTRATIVE_DECISION' end,
      coalesce(selected_decision_id, suspension_row.id),
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    event_payload := jsonb_build_object(
      'suspensionId', suspension_row.id, 'status', suspension_row.status,
      'administrativeDecisionId', selected_decision_id
    );

  elsif action_name in ('administrative_decision.publish', 'administrative_decision.supersede') then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, false, false, false, true);
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    selected_decision_type := upper(trim(coalesce(payload ->> 'decisionType', '')));
    if selected_decision_type in (
      'DEDUCT_POINTS', 'CREATE_SANCTION', 'REVERSE_SANCTION_SERVICE',
      'CREATE_COMPETITION_CHARGE', 'CREATE_COMPETITION_CREDIT'
    ) then raise exception 'FEATURE_NOT_AVAILABLE_UNTIL_R5' using errcode = '0A000'; end if;
    if selected_decision_type not in (
      'RESCHEDULE_MATCH', 'CHANGE_VENUE', 'CANCEL_MATCH', 'RESUME_FROM_MINUTE',
      'ORDER_REPLAY', 'SET_OFFICIAL_RESULT', 'ANNUL_OFFICIAL_RESULT'
    ) then raise exception 'R4D_ADMIN_EFFECT_NOT_SUPPORTED' using errcode = '0A000'; end if;
    selected_previous_decision_id := case when action_name = 'administrative_decision.supersede'
      then nullif(payload ->> 'previousDecisionId', '')::uuid else null end;
    if action_name = 'administrative_decision.supersede' and selected_previous_decision_id is null then
      raise exception 'R4D_PREVIOUS_DECISION_REQUIRED' using errcode = '22023';
    end if;
    if selected_decision_type in ('RESCHEDULE_MATCH', 'CHANGE_VENUE', 'CANCEL_MATCH') then
      if selected_decision_type = 'CANCEL_MATCH'
         and upper(coalesce(payload ->> 'cancellationOutcome', '')) <> 'NO_RESULT' then
        raise exception 'R4D_CANCELLATION_OUTCOME_REQUIRED' using errcode = '22023';
      end if;
      selected_start := case when selected_decision_type = 'RESCHEDULE_MATCH'
        then nullif(payload ->> 'scheduledStart', '')::timestamptz else context_row.scheduled_start end;
      selected_end := case when selected_decision_type = 'RESCHEDULE_MATCH'
        then nullif(payload ->> 'scheduledEnd', '')::timestamptz else context_row.scheduled_end end;
      selected_timezone := case when selected_decision_type = 'RESCHEDULE_MATCH'
        then coalesce(nullif(left(trim(coalesce(payload ->> 'timezone', '')), 80), ''), context_row.timezone)
        else context_row.timezone end;
      selected_venue_id := case when selected_decision_type = 'CHANGE_VENUE'
        then nullif(payload ->> 'venueId', '')::uuid else context_row.venue_id end;
      selected_venue_label := case when selected_decision_type = 'CHANGE_VENUE'
        then nullif(left(trim(coalesce(payload ->> 'venueLabel', '')), 160), '') else context_row.venue_label end;
      selected_venue_status := case when selected_decision_type = 'CHANGE_VENUE'
        then upper(coalesce(nullif(payload ->> 'venueStatus', ''),
          case when selected_venue_id is not null then 'SAVED'
            when selected_venue_label is not null then 'LABEL' else 'TBD' end))
        else case context_row.venue_status
          when 'CONFIRMED' then case when context_row.venue_id is null then 'LABEL' else 'SAVED' end
          else context_row.venue_status end end;
      selected_resource_key := case selected_venue_status
        when 'SAVED' then 'venue:' || selected_venue_id::text
        when 'LABEL' then 'label:' || encode(extensions.digest(convert_to(lower(selected_venue_label), 'UTF8'), 'sha256'), 'hex')
        else case when selected_decision_type = 'CHANGE_VENUE'
          then null else current_resource_key end end;
      if selected_decision_type = 'CHANGE_VENUE' then
        selected_reason_code := upper(selected_reason_code);
        if selected_reason_code not in (
          'WEATHER', 'PITCH_UNAVAILABLE', 'LIGHTING',
          'FACILITY_CLOSED', 'SAFETY', 'OTHER'
        ) then raise exception 'R4D_VENUE_REASON_INVALID' using errcode = '22023'; end if;
        insert into public.pachanga_competition_venue_change_requests(
          competition_id, canonical_match_id, competition_match_context_id,
          requesting_entry_id, rule_revision_id, requested_venue_id,
          requested_venue_label, requested_venue_status, requested_resource_key,
          reason_code, public_summary, status, operation_id, server_sequence,
          requested_by, resolved_at
        ) values (
          context_row.competition_id, context_row.canonical_match_id, context_row.id,
          null, context_row.rule_revision_id, selected_venue_id,
          selected_venue_label, selected_venue_status, selected_resource_key,
          selected_reason_code, selected_public_summary, 'approved', operation_id,
          sequence_value, actor_id, server_now
        ) returning * into venue_request_row;
        selected_request_id := venue_request_row.id;
        insert into public.pachanga_competition_venue_condition_decisions(
          venue_change_request_id, competition_id, canonical_match_id,
          competition_match_context_id, rule_revision_id, reason_code, outcome,
          public_summary, authority_role, operation_id, decided_by, server_sequence
        ) values (
          venue_request_row.id, context_row.competition_id,
          context_row.canonical_match_id, context_row.id,
          context_row.rule_revision_id, selected_reason_code, 'venue_changed',
          selected_public_summary, authority_role, operation_id, actor_id,
          sequence_value
        ) returning * into venue_decision_row;
        update public.pachanga_competition_venue_change_requests requests set
          current_decision_id = venue_decision_row.id,
          revision = requests.revision + 1,
          server_sequence = sequence_value,
          updated_at = server_now
        where requests.id = venue_request_row.id
        returning * into venue_request_row;
      end if;
      selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
        context_row.id, selected_decision_type,
        case when selected_decision_type = 'CHANGE_VENUE'
          then 'VENUE_CHANGE_REQUEST' else 'MATCH_CONTEXT' end,
        case when selected_decision_type = 'CHANGE_VENUE'
          then selected_request_id else context_row.id end,
        selected_reason_code, selected_public_summary, selected_previous_decision_id,
        operation_id, actor_id, sequence_value
      );
      fixture_result := private.pachanga_league_operational_create_fixture_change_v1(
        context_row.id,
        case selected_decision_type when 'RESCHEDULE_MATCH' then 'RESCHEDULE'
          when 'CHANGE_VENUE' then 'VENUE_CHANGE' else 'CANCELLATION' end,
        case selected_decision_type when 'CANCEL_MATCH' then 'cancelled' else 'scheduled' end,
        selected_start, selected_end, selected_timezone,
        selected_venue_id, selected_venue_label, selected_venue_status,
        selected_resource_key, selected_reason_code, selected_public_summary,
        'ADMINISTRATIVE_DECISION', selected_decision_id,
        operation_id, actor_id, sequence_value, policy
      );
      selected_fixture_change_id := (fixture_result ->> 'fixtureChangeId')::uuid;
      if selected_decision_type = 'CHANGE_VENUE' then
        update public.pachanga_competition_venue_change_requests requests set
          approved_fixture_change_id = selected_fixture_change_id,
          server_sequence = sequence_value,
          updated_at = server_now
        where requests.id = venue_request_row.id;
        perform private.pachanga_league_operational_store_evidence_v1(
          context_row.competition_id, 'VENUE_CHANGE_REQUEST', venue_request_row.id,
          payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
          operation_id, sequence_value
        );
        perform private.pachanga_league_operational_store_evidence_v1(
          context_row.competition_id, 'VENUE_CONDITION_DECISION', venue_decision_row.id,
          payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
          operation_id, sequence_value
        );
      end if;
      perform private.pachanga_league_operational_add_admin_effect_v1(
        selected_decision_id, selected_decision_type,
        case when selected_decision_type = 'CANCEL_MATCH'
          then jsonb_build_object('cancellationOutcome', 'NO_RESULT')
          else jsonb_build_object('validatedBy', 'R4D_SERVER') end,
        selected_fixture_change_id, null, null, sequence_value
      );
    elsif selected_decision_type = 'SET_OFFICIAL_RESULT' then
      selected_incident_id := nullif(payload ->> 'noShowIncidentId', '')::uuid;
      selected_suspension_id := nullif(payload ->> 'suspensionId', '')::uuid;
      if (selected_incident_id is null) = (selected_suspension_id is null) then
        raise exception 'R4D_SINGLE_OFFICIAL_RESULT_SOURCE_REQUIRED' using errcode = '22023';
      end if;
      if selected_incident_id is not null then
        select * into no_show_row
        from public.pachanga_competition_no_show_incidents incidents
        where incidents.id = selected_incident_id
          and incidents.competition_match_context_id = context_row.id
          and incidents.status = 'confirmed'
        for update;
        if not found then raise exception 'R4D_CONFIRMED_NO_SHOW_REQUIRED' using errcode = '22023'; end if;
        selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
          context_row.id, 'SET_OFFICIAL_RESULT', 'NO_SHOW_INCIDENT', no_show_row.id,
          selected_reason_code, selected_public_summary, selected_previous_decision_id,
          operation_id, actor_id, sequence_value
        );
        official_result := private.pachanga_league_operational_no_show_result_v1(
          context_row.id, no_show_row.id, no_show_row.responsible_entry_id,
          operation_id, actor_id, authority_role, selected_reason_code,
          selected_public_summary, sequence_value, policy
        );
        selected_official_decision_id := (official_result ->> 'decisionId')::uuid;
        update public.pachanga_competition_no_show_incidents incidents set
          official_result_decision_id = selected_official_decision_id,
          revision = incidents.revision + 1, server_sequence = sequence_value,
          updated_at = server_now
        where incidents.id = no_show_row.id;
        perform private.pachanga_league_operational_add_admin_effect_v1(
          selected_decision_id, 'SET_OFFICIAL_RESULT',
          jsonb_build_object('source', 'NO_SHOW_INCIDENT', 'incidentId', no_show_row.id),
          null, selected_official_decision_id, null, sequence_value
        );
      else
        select * into suspension_row
        from public.pachanga_competition_match_suspensions suspensions
        where suspensions.id = selected_suspension_id
          and suspensions.competition_match_context_id = context_row.id
          and suspensions.status = 'administrative_resolution'
        for update;
        if not found then
          raise exception 'R4D_ADMINISTRATIVE_SUSPENSION_REQUIRED' using errcode = '22023';
        end if;
        selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
          context_row.id, 'SET_OFFICIAL_RESULT', 'MATCH_SUSPENSION', suspension_row.id,
          selected_reason_code, selected_public_summary, selected_previous_decision_id,
          operation_id, actor_id, sequence_value
        );
        official_result := private.pachanga_league_operational_suspension_result_v1(
          context_row.id, suspension_row.id, operation_id, actor_id,
          authority_role, selected_reason_code, selected_public_summary,
          sequence_value
        );
        selected_official_decision_id := (official_result ->> 'decisionId')::uuid;
        perform private.pachanga_league_operational_add_admin_effect_v1(
          selected_decision_id, 'SET_OFFICIAL_RESULT',
          jsonb_build_object(
            'source', 'MATCH_SUSPENSION',
            'suspensionId', suspension_row.id,
            'partialResultRevisionId', suspension_row.sporting_result_revision_id
          ),
          null, selected_official_decision_id, null, sequence_value
        );
      end if;
    elsif selected_decision_type in ('RESUME_FROM_MINUTE', 'ORDER_REPLAY') then
      selected_suspension_id := nullif(payload ->> 'suspensionId', '')::uuid;
      select * into suspension_row
      from public.pachanga_competition_match_suspensions suspensions
      where suspensions.id = selected_suspension_id
        and suspensions.competition_match_context_id = context_row.id
        and suspensions.status in ('confirmed', 'resume_scheduled', 'replay_ordered')
      for update;
      if not found then raise exception 'R4D_CONFIRMED_SUSPENSION_REQUIRED' using errcode = '22023'; end if;
      selected_start := nullif(payload ->> 'scheduledStart', '')::timestamptz;
      selected_end := nullif(payload ->> 'scheduledEnd', '')::timestamptz;
      selected_timezone := coalesce(nullif(left(trim(coalesce(payload ->> 'timezone', '')), 80), ''), context_row.timezone);
      selected_venue_id := nullif(payload ->> 'venueId', '')::uuid;
      selected_venue_label := nullif(left(trim(coalesce(payload ->> 'venueLabel', '')), 160), '');
      selected_venue_status := upper(coalesce(nullif(payload ->> 'venueStatus', ''),
        case when selected_venue_id is not null then 'SAVED'
          when selected_venue_label is not null then 'LABEL' else 'TBD' end));
      selected_resource_key := case selected_venue_status
        when 'SAVED' then 'venue:' || selected_venue_id::text
        when 'LABEL' then 'label:' || encode(extensions.digest(convert_to(lower(selected_venue_label), 'UTF8'), 'sha256'), 'hex')
        else null end;
      if suspension_row.current_resumption_decision_id is not null then
        if action_name <> 'administrative_decision.supersede' then
          raise exception 'R4D_RESUMPTION_DECISION_ALREADY_EXISTS' using errcode = 'PT409';
        end if;
        update public.pachanga_competition_match_resumption_decisions decisions set
          status = 'superseded'
        where decisions.id = suspension_row.current_resumption_decision_id
          and decisions.status = 'published';
        if not found then
          raise exception 'R4D_RESUMPTION_DECISION_STALE' using errcode = 'PT409';
        end if;
      end if;
      insert into public.pachanga_competition_match_resumption_decisions(
        match_suspension_id, decision_type, resume_minute,
        initial_score_home, initial_score_away, effective_scheduled_start,
        effective_scheduled_end, effective_timezone, effective_venue_id,
        effective_venue_label, effective_venue_status, effective_resource_key,
        reuse_canonical_match, eligibility_policy_snapshot, public_summary,
        status, supersedes_decision_id, operation_id, authority_role,
        decided_by, server_sequence
      ) values (
        suspension_row.id,
        case selected_decision_type when 'RESUME_FROM_MINUTE' then 'RESUME' else 'REPLAY' end,
        case selected_decision_type when 'RESUME_FROM_MINUTE'
          then coalesce(nullif(payload ->> 'resumeMinute', '')::integer, suspension_row.reported_minute)
          else 0 end,
        case selected_decision_type when 'RESUME_FROM_MINUTE' then suspension_row.sporting_score_home else 0 end,
        case selected_decision_type when 'RESUME_FROM_MINUTE' then suspension_row.sporting_score_away else 0 end,
        selected_start, selected_end, selected_timezone, selected_venue_id,
        selected_venue_label, selected_venue_status, selected_resource_key, true,
        policy -> 'resumptionEligibilityPolicy', selected_public_summary,
        'published', suspension_row.current_resumption_decision_id,
        operation_id, authority_role, actor_id, sequence_value
      ) returning * into resumption_row;
      selected_resumption_id := resumption_row.id;
      selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
        context_row.id, selected_decision_type, 'MATCH_SUSPENSION', suspension_row.id,
        selected_reason_code, selected_public_summary, selected_previous_decision_id,
        operation_id, actor_id, sequence_value
      );
      fixture_result := private.pachanga_league_operational_create_fixture_change_v1(
        context_row.id,
        case selected_decision_type when 'RESUME_FROM_MINUTE' then 'RESUMPTION' else 'REPLAY' end,
        case selected_decision_type when 'RESUME_FROM_MINUTE' then 'suspended' else 'scheduled' end,
        selected_start, selected_end, selected_timezone,
        selected_venue_id, selected_venue_label, selected_venue_status,
        selected_resource_key, selected_reason_code, selected_public_summary,
        'ADMINISTRATIVE_DECISION', selected_decision_id,
        operation_id, actor_id, sequence_value, policy
      );
      selected_fixture_change_id := (fixture_result ->> 'fixtureChangeId')::uuid;
      update public.pachanga_competition_match_suspensions suspensions set
        status = case selected_decision_type when 'RESUME_FROM_MINUTE'
          then 'resume_scheduled' else 'replay_ordered' end,
        current_resumption_decision_id = resumption_row.id,
        revision = suspensions.revision + 1, server_sequence = sequence_value,
        updated_at = server_now
      where suspensions.id = suspension_row.id returning * into suspension_row;
      perform private.pachanga_league_operational_add_admin_effect_v1(
        selected_decision_id, selected_decision_type,
        jsonb_build_object('sameCanonicalMatch', true, 'suspensionId', suspension_row.id),
        selected_fixture_change_id, null, resumption_row.id, sequence_value
      );
    else
      raise exception 'R4D_USE_ADMINISTRATIVE_DECISION_ANNUL_ACTION' using errcode = '22023';
    end if;
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'ADMINISTRATIVE_DECISION', selected_decision_id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    select * into round_row from public.pachanga_competition_rounds rounds
    where rounds.id = context_row.round_id;
    event_payload := jsonb_build_object(
      'decisionId', selected_decision_id, 'decisionType', selected_decision_type,
      'fixtureChangeId', selected_fixture_change_id,
      'officialResultDecisionId', selected_official_decision_id,
      'resumptionDecisionId', selected_resumption_id
    );

  elsif action_name = 'administrative_decision.annul' then
    perform private.pachanga_league_operational_assert_flags_v1(false, false, false, false, false, false, true);
    authority_role := private.pachanga_league_operational_assert_manager_v1(
      context_row.competition_id, actor_id
    );
    selected_previous_decision_id := nullif(payload ->> 'decisionId', '')::uuid;
    select * into admin_row
    from public.pachanga_competition_administrative_decisions decisions
    where decisions.id = selected_previous_decision_id
      and decisions.competition_id = context_row.competition_id
      and decisions.status = 'published'
    for update;
    if not found then raise exception 'R4D_ADMIN_DECISION_NOT_FOUND' using errcode = 'P0002'; end if;
    if admin_row.decision_type <> 'SET_OFFICIAL_RESULT' then
      raise exception 'R4D_OPERATIONAL_REVERSAL_REQUIRES_NEW_TYPED_DECISION' using errcode = '0A000';
    end if;
    select effects.official_result_decision_id into selected_official_decision_id
    from public.pachanga_competition_administrative_effects effects
    where effects.administrative_decision_id = admin_row.id
      and effects.effect_type = 'SET_OFFICIAL_RESULT'
      and effects.status = 'applied'
    order by effects.effect_order, effects.id
    limit 1;
    if selected_official_decision_id is null then
      raise exception 'R4D_ADMIN_DECISION_EFFECT_NOT_FOUND' using errcode = 'P0002';
    end if;
    selected_decision_id := private.pachanga_league_operational_create_admin_decision_v1(
      context_row.id, 'ANNUL_OFFICIAL_RESULT', 'OFFICIAL_RESULT_DECISION',
      selected_official_decision_id,
      selected_reason_code, selected_public_summary, admin_row.id,
      operation_id, actor_id, sequence_value
    );
    official_result := private.pachanga_league_operational_annul_official_result_v1(
      context_row.id, operation_id, actor_id, authority_role,
      selected_reason_code, selected_public_summary, sequence_value
    );
    selected_official_decision_id := (official_result ->> 'decisionId')::uuid;
    perform private.pachanga_league_operational_add_admin_effect_v1(
      selected_decision_id, 'ANNUL_OFFICIAL_RESULT',
      jsonb_build_object('supersedesDecisionId', official_result ->> 'supersedesDecisionId'),
      null, selected_official_decision_id, null, sequence_value
    );
    perform private.pachanga_league_operational_store_evidence_v1(
      context_row.competition_id, 'ADMINISTRATIVE_DECISION', selected_decision_id,
      payload ->> 'reasonText', payload -> 'evidenceRefs', actor_id,
      operation_id, sequence_value
    );
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    select * into round_row from public.pachanga_competition_rounds rounds
    where rounds.id = context_row.round_id;
    event_payload := jsonb_build_object(
      'decisionId', selected_decision_id, 'decisionType', 'ANNUL_OFFICIAL_RESULT',
      'officialResultDecisionId', selected_official_decision_id
    );

  else
    raise exception 'R4D_ACTION_NOT_SUPPORTED' using errcode = '0A000';
  end if;

  snapshot := private.pachanga_league_operational_snapshot_v1(context_row.id, actor_id);
  confirmed_revision := context_row.revision;
  invalidations := jsonb_build_array(
    jsonb_build_object('entityType', 'match', 'entityId', context_row.id, 'revision', context_row.revision)
  );
  if action_name like 'postponement.%' then
    invalidations := invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', 'operational_request',
      'entityId', coalesce(request_row.id, selected_request_id),
      'revision', coalesce(request_row.revision, context_row.revision)
    ));
  elsif action_name like 'fixture.%' then
    invalidations := invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', 'fixture_change', 'entityId', selected_fixture_change_id,
      'revision', context_row.revision
    ));
  elsif action_name like 'late_arrival.%' or action_name like 'no_show.%' then
    invalidations := invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', 'operational_incident',
      'entityId', coalesce(no_show_row.id, late_row.id, selected_incident_id),
      'revision', context_row.revision
    ));
  elsif action_name like 'suspension.%' then
    invalidations := invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', 'match_suspension',
      'entityId', coalesce(suspension_row.id, selected_suspension_id),
      'revision', context_row.revision
    ));
  elsif action_name like 'administrative_decision.%' then
    invalidations := invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', 'administrative_decision', 'entityId', selected_decision_id,
      'revision', context_row.revision
    ));
  end if;
  if selected_fixture_change_id is not null then
    invalidations := invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', 'fixture_change', 'entityId', selected_fixture_change_id,
      'revision', context_row.revision
    ));
  end if;
  if selected_official_decision_id is not null then
    invalidations := invalidations || jsonb_build_array(
      jsonb_build_object('entityType', 'result', 'entityId', context_row.canonical_match_id, 'revision', context_row.revision),
      jsonb_build_object('entityType', 'standings', 'entityId', context_row.stage_id, 'revision', context_row.revision),
      jsonb_build_object('entityType', 'round', 'entityId', context_row.round_id, 'revision', round_row.revision)
    );
  end if;
  return private.pachanga_league_operational_store_command_v1(
    operation_id, actor_id, actor_kind, action_name, aggregate_id,
    context_row.competition_id, confirmed_revision, sequence_value,
    request_hash, metadata, event_payload, snapshot, invalidations
  );
end;
$$;

revoke all on function public.command_pachanga_league_operational_exceptions_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_league_operational_exceptions_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;
