-- Pachangas IQ Wave 9B: privacy-safe canonical read models for season Venue allocation.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_venue_recurring_series_can_read_v1(
  target_series_id uuid,
  target_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  series_row public.pachanga_venue_recurring_series%rowtype;
begin
  if target_actor_id is null then return false; end if;
  if private.pachanga_platform_role_for_user_v1(target_actor_id)
     in ('platform_owner', 'platform_admin') then return true; end if;
  select * into series_row
  from public.pachanga_venue_recurring_series series
  where series.id = target_series_id;
  if not found then return false; end if;
  return private.pachanga_club_can_v1(series_row.owner_club_id, target_actor_id, 'venue_read')
    or (series_row.competition_id is not null and private.pachanga_competition_venue_can_v1(
      series_row.competition_id, target_actor_id, 'read'
    ))
    or (series_row.team_id is not null and exists (
      select 1 from public.pachanga_group_members members
      where members.group_id = series_row.team_id and members.user_id = target_actor_id
    ));
end;
$$;

create or replace function private.pachanga_venue_pool_can_read_v1(
  target_pool_id uuid,
  target_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  pool_row public.pachanga_competition_venue_pools%rowtype;
begin
  if target_actor_id is null then return false; end if;
  if private.pachanga_platform_role_for_user_v1(target_actor_id)
     in ('platform_owner', 'platform_admin') then return true; end if;
  select * into pool_row
  from public.pachanga_competition_venue_pools pools
  where pools.id = target_pool_id;
  if not found then return false; end if;
  return private.pachanga_competition_venue_can_v1(
    pool_row.competition_id, target_actor_id, 'read'
  ) or (pool_row.organizer_club_id is not null and private.pachanga_club_can_v1(
    pool_row.organizer_club_id, target_actor_id, 'venue_read'
  )) or exists (
    select 1
    from public.pachanga_competition_venue_authorizations authorizations
    where authorizations.pool_id = pool_row.id
      and private.pachanga_club_can_v1(
        authorizations.owner_club_id, target_actor_id, 'venue_read'
      )
  );
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_venue_recurring_series_can_read_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_venue_pool_can_read_v1(uuid,uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end
$$;

create or replace function public.get_pachanga_competition_venue_allocation_overview_v1(
  target_competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null or not private.pachanga_competition_venue_can_v1(
    target_competition_id, actor_id, 'read'
  ) then
    raise exception 'VENUE_ALLOCATION_READ_FORBIDDEN' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'competitionId', target_competition_id,
    'counts', jsonb_build_object(
      'pools', (select count(*) from public.pachanga_competition_venue_pools pools
        where pools.competition_id = target_competition_id),
      'activeAuthorizations', (select count(*)
        from public.pachanga_competition_venue_authorizations authorizations
        where authorizations.competition_id = target_competition_id
          and authorizations.status = 'active'),
      'recurringSeries', (select count(*)
        from public.pachanga_venue_recurring_series series
        where series.competition_id = target_competition_id),
      'plans', (select count(*) from public.pachanga_competition_venue_allocation_plans plans
        where plans.competition_id = target_competition_id),
      'generated', (select count(*) from public.pachanga_competition_venue_allocation_plans plans
        where plans.competition_id = target_competition_id
          and plans.status in ('generated', 'partial', 'conflicted', 'validated')),
      'stale', (select count(*) from public.pachanga_competition_venue_allocation_plans plans
        where plans.competition_id = target_competition_id and plans.status = 'stale'),
      'published', (select count(*) from public.pachanga_competition_venue_allocation_plans plans
        where plans.competition_id = target_competition_id and plans.status = 'published'),
      'unassignedMatches', (select count(*)
        from public.pachanga_competition_venue_allocation_items items
        join public.pachanga_competition_venue_allocation_plans plans
          on plans.id = items.allocation_plan_id
        where plans.competition_id = target_competition_id
          and plans.current_revision_id = items.allocation_revision_id
          and items.pitch_id is null),
      'activeHolds', (select count(*)
        from public.pachanga_competition_venue_allocation_holds holds
        join public.pachanga_competition_venue_allocation_plans plans
          on plans.id = holds.allocation_plan_id
        where plans.competition_id = target_competition_id and holds.status = 'active'),
      'hardViolations', (select count(*)
        from private.pachanga_competition_venue_allocation_conflicts conflicts
        join public.pachanga_competition_venue_allocation_plans plans
          on plans.id = conflicts.allocation_plan_id
        where plans.competition_id = target_competition_id
          and conflicts.status = 'active' and conflicts.severity = 'HARD')
    ),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'planId', plans.id,
        'editionId', plans.edition_id,
        'stageId', plans.stage_id,
        'mode', plans.mode,
        'status', plans.status,
        'venueRequired', plans.venue_required,
        'revision', plans.revision,
        'serverSequence', plans.server_sequence,
        'updatedAt', plans.updated_at,
        'currentRevisionId', plans.current_revision_id
      ) order by plans.server_sequence desc, plans.id)
      from public.pachanga_competition_venue_allocation_plans plans
      where plans.competition_id = target_competition_id
    ), '[]'::jsonb),
    'serverSequence', coalesce((select max(plans.server_sequence)
      from public.pachanga_competition_venue_allocation_plans plans
      where plans.competition_id = target_competition_id), 0),
    'readAt', clock_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_competition_venue_allocation_desk_v1(
  target_plan_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare revision_row public.pachanga_competition_venue_allocation_revisions%rowtype;
declare quality_row private.pachanga_competition_venue_allocation_quality_snapshots%rowtype;
begin
  select * into plan_row
  from public.pachanga_competition_venue_allocation_plans plans
  where plans.id = target_plan_id;
  if not found or actor_id is null or not private.pachanga_competition_venue_can_v1(
    plan_row.competition_id, actor_id, 'read'
  ) then
    raise exception 'VENUE_ALLOCATION_READ_FORBIDDEN' using errcode = '42501';
  end if;
  if plan_row.current_revision_id is not null then
    select * into revision_row
    from public.pachanga_competition_venue_allocation_revisions revisions
    where revisions.id = plan_row.current_revision_id;
    select * into quality_row
    from private.pachanga_competition_venue_allocation_quality_snapshots quality
    where quality.allocation_revision_id = revision_row.id;
  end if;

  return jsonb_build_object(
    'plan', jsonb_build_object(
      'planId', plan_row.id,
      'competitionId', plan_row.competition_id,
      'editionId', plan_row.edition_id,
      'stageId', plan_row.stage_id,
      'schedulePlanId', plan_row.schedule_plan_id,
      'scheduleRevisionId', plan_row.schedule_revision_id,
      'ruleRevisionId', plan_row.rule_revision_id,
      'venuePoolId', plan_row.venue_pool_id,
      'mode', plan_row.mode,
      'venueRequired', plan_row.venue_required,
      'status', plan_row.status,
      'currentInputFreezeId', plan_row.current_input_freeze_id,
      'currentRevisionId', plan_row.current_revision_id,
      'revision', plan_row.revision,
      'serverSequence', plan_row.server_sequence,
      'updatedAt', plan_row.updated_at
    ),
    'revision', case when revision_row.id is null then null else jsonb_build_object(
      'revisionId', revision_row.id,
      'version', revision_row.version,
      'revisionKind', revision_row.revision_kind,
      'mode', revision_row.mode,
      'status', revision_row.status,
      'algorithmVersion', revision_row.algorithm_version,
      'seed', revision_row.seed,
      'inputChecksum', revision_row.input_checksum,
      'resultChecksum', revision_row.result_checksum,
      'constraintChecksum', revision_row.constraint_checksum,
      'lockChecksum', revision_row.lock_checksum,
      'searchBudget', revision_row.search_budget,
      'candidateCount', revision_row.candidate_count,
      'assignedCount', revision_row.assigned_count,
      'unassignedCount', revision_row.unassigned_count,
      'hardViolationCount', revision_row.hard_violation_count,
      'qualityScore', revision_row.quality_score,
      'validationStatus', (select validations.status
        from private.pachanga_competition_venue_allocation_validations validations
        where validations.allocation_revision_id = revision_row.id
        order by validations.server_sequence desc, validations.id desc limit 1),
      'generatedAt', revision_row.generated_at,
      'validatedAt', (select validations.validated_at
        from private.pachanga_competition_venue_allocation_validations validations
        where validations.allocation_revision_id = revision_row.id
        order by validations.server_sequence desc, validations.id desc limit 1),
      'publishedAt', plan_row.published_at,
      'serverSequence', revision_row.server_sequence
    ) end,
    'quality', case when quality_row.id is null then null else jsonb_build_object(
      'hardViolations', quality_row.hard_violations,
      'unassignedMatches', quality_row.unassigned_matches,
      'assignedMatches', quality_row.assigned_matches,
      'recurringBlockUsage', quality_row.recurring_block_usage,
      'venueChanges', quality_row.venue_changes,
      'pitchUtilization', quality_row.pitch_utilization,
      'premiumSlotBalance', quality_row.premium_slot_balance,
      'travelEstimate', jsonb_strip_nulls(jsonb_build_object(
        'status', quality_row.travel_estimate ->> 'status',
        'method', quality_row.travel_estimate ->> 'method',
        'totalKilometers', quality_row.travel_estimate -> 'totalKilometers'
      )),
      'manualOverrideCount', quality_row.manual_override_count,
      'lockedAssignments', quality_row.locked_assignments,
      'conflicts', quality_row.conflicts,
      'warnings', quality_row.warnings,
      'explanation', quality_row.explanation,
      'score', quality_row.score,
      'checksum', quality_row.checksum,
      'generatedAt', quality_row.generated_at
    ) end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'itemId', items.id,
        'scheduleItemId', items.schedule_item_id,
        'canonicalMatchId', items.canonical_match_id,
        'competitionMatchContextId', items.competition_match_context_id,
        'roundId', items.round_id,
        'homeEntryId', items.home_entry_id,
        'awayEntryId', items.away_entry_id,
        'scheduledStart', items.scheduled_start,
        'scheduledEnd', items.scheduled_end,
        'timezone', items.timezone,
        'venueId', items.venue_id,
        'venueName', venues.name,
        'pitchId', items.pitch_id,
        'pitchName', pitches.name,
        'sourceKind', items.source_kind,
        'sourceId', items.source_id,
        'assignmentStatus', items.assignment_status,
        'conflictCodes', items.conflict_codes,
        'warningCodes', items.warning_codes,
        'manualOverride', items.manual_override,
        'holdId', items.hold_id,
        'reservationId', items.reservation_id,
        'bindingId', items.binding_id,
        'revision', items.revision,
        'serverSequence', items.server_sequence
      ) order by items.scheduled_start, items.canonical_match_id, items.id)
      from public.pachanga_competition_venue_allocation_items items
      left join public.pachanga_club_venues venues on venues.id = items.venue_id
      left join public.pachanga_venue_pitches pitches on pitches.id = items.pitch_id
      where items.allocation_revision_id = plan_row.current_revision_id
    ), '[]'::jsonb),
    'constraints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'constraintId', constraints.id,
        'kind', constraints.constraint_kind,
        'code', constraints.constraint_code,
        'scopeKind', constraints.scope_kind,
        'scopeId', constraints.scope_id,
        'weight', constraints.weight,
        'parameters', constraints.parameters,
        'reason', constraints.reason,
        'revision', constraints.revision,
        'serverSequence', constraints.server_sequence
      ) order by constraints.constraint_kind, constraints.constraint_code,
        constraints.server_sequence, constraints.id)
      from public.pachanga_competition_venue_allocation_constraints constraints
      where constraints.allocation_plan_id = plan_row.id and constraints.status = 'active'
    ), '[]'::jsonb),
    'locks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lockId', locks.id,
        'lockType', locks.lock_type,
        'canonicalMatchId', locks.canonical_match_id,
        'roundId', locks.round_id,
        'venueId', locks.venue_id,
        'pitchId', locks.pitch_id,
        'recurringOccurrenceId', locks.recurring_occurrence_id,
        'reason', locks.reason,
        'revision', locks.revision,
        'serverSequence', locks.server_sequence,
        'createdAt', locks.created_at
      ) order by locks.server_sequence, locks.id)
      from public.pachanga_competition_venue_allocation_locks locks
      where locks.allocation_plan_id = plan_row.id and locks.status = 'active'
    ), '[]'::jsonb),
    'conflicts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'conflictId', conflicts.id,
        'allocationItemId', conflicts.allocation_item_id,
        'canonicalMatchId', conflicts.canonical_match_id,
        'conflictCode', conflicts.conflict_code,
        'outcomeCode', conflicts.outcome_code,
        'severity', conflicts.severity,
        'publicExplanation', conflicts.public_explanation,
        'status', conflicts.status,
        'serverSequence', conflicts.server_sequence,
        'detectedAt', conflicts.detected_at
      ) order by conflicts.server_sequence, conflicts.id)
      from private.pachanga_competition_venue_allocation_conflicts conflicts
      where conflicts.allocation_revision_id = plan_row.current_revision_id
        and conflicts.status = 'active'
    ), '[]'::jsonb),
    'readAt', clock_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_competition_venue_allocation_revision_v1(
  target_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare revision_row public.pachanga_competition_venue_allocation_revisions%rowtype;
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
begin
  select * into revision_row
  from public.pachanga_competition_venue_allocation_revisions revisions
  where revisions.id = target_revision_id;
  select * into plan_row
  from public.pachanga_competition_venue_allocation_plans plans
  where plans.id = revision_row.allocation_plan_id;
  if revision_row.id is null or actor_id is null or not private.pachanga_competition_venue_can_v1(
    plan_row.competition_id, actor_id, 'read'
  ) then raise exception 'VENUE_ALLOCATION_READ_FORBIDDEN' using errcode = '42501'; end if;
  return jsonb_build_object(
    'revision', to_jsonb(revision_row) - 'generated_by' - 'validated_by' - 'published_by' - 'operation_id',
    'items', coalesce((select jsonb_agg(
      to_jsonb(items) order by items.scheduled_start, items.canonical_match_id, items.id
    ) from public.pachanga_competition_venue_allocation_items items
      where items.allocation_revision_id = revision_row.id), '[]'::jsonb),
    'quality', (select to_jsonb(quality) - 'travel_estimate' || jsonb_build_object(
      'travel_estimate', jsonb_strip_nulls(jsonb_build_object(
        'status', quality.travel_estimate ->> 'status',
        'method', quality.travel_estimate ->> 'method',
        'totalKilometers', quality.travel_estimate -> 'totalKilometers'
      ))) from private.pachanga_competition_venue_allocation_quality_snapshots quality
      where quality.allocation_revision_id = revision_row.id)
  );
end;
$$;

create or replace function public.get_pachanga_competition_venue_allocation_diff_v1(
  target_from_revision_id uuid,
  target_to_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare plan_id uuid;
declare competition_id uuid;
begin
  select target_revision.allocation_plan_id, plans.competition_id
    into plan_id, competition_id
  from public.pachanga_competition_venue_allocation_revisions target_revision
  join public.pachanga_competition_venue_allocation_plans plans
    on plans.id = target_revision.allocation_plan_id
  where target_revision.id = target_to_revision_id
    and (target_from_revision_id is null or exists (
      select 1 from public.pachanga_competition_venue_allocation_revisions source_revision
      where source_revision.id = target_from_revision_id
        and source_revision.allocation_plan_id = target_revision.allocation_plan_id
    ));
  if plan_id is null or actor_id is null or not private.pachanga_competition_venue_can_v1(
    competition_id, actor_id, 'read'
  ) then raise exception 'VENUE_ALLOCATION_READ_FORBIDDEN' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_build_object(
      'fromRevisionId', diffs.from_revision_id,
      'toRevisionId', diffs.to_revision_id,
      'diff', diffs.diff,
      'checksum', diffs.checksum,
      'serverSequence', diffs.server_sequence,
      'createdAt', diffs.created_at
    )
    from private.pachanga_competition_venue_allocation_diffs diffs
    where diffs.from_revision_id is not distinct from target_from_revision_id
      and diffs.to_revision_id = target_to_revision_id
    order by diffs.server_sequence desc, diffs.id desc
    limit 1
  ), jsonb_build_object(
    'fromRevisionId', target_from_revision_id,
    'toRevisionId', target_to_revision_id,
    'diff', '{}'::jsonb,
    'status', 'NOT_MATERIALIZED'
  ));
end;
$$;

create or replace function public.get_pachanga_competition_venue_allocation_health_v1(
  target_competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null or not private.pachanga_competition_venue_can_v1(
    target_competition_id, actor_id, 'read'
  ) then raise exception 'VENUE_ALLOCATION_READ_FORBIDDEN' using errcode = '42501'; end if;
  return jsonb_build_object(
    'competitionId', target_competition_id,
    'stalePlans', (select count(*) from public.pachanga_competition_venue_allocation_plans plans
      where plans.competition_id = target_competition_id and plans.status = 'stale'),
    'expiredActiveHolds', (select count(*)
      from public.pachanga_competition_venue_allocation_holds holds
      join public.pachanga_competition_venue_allocation_plans plans
        on plans.id = holds.allocation_plan_id
      where plans.competition_id = target_competition_id
        and holds.status = 'active' and holds.expires_at <= clock_timestamp()),
    'hardViolations', (select count(*)
      from private.pachanga_competition_venue_allocation_conflicts conflicts
      join public.pachanga_competition_venue_allocation_plans plans
        on plans.id = conflicts.allocation_plan_id
      where plans.competition_id = target_competition_id
        and conflicts.status = 'active' and conflicts.severity = 'HARD'),
    'multipleCurrentBindings', (select count(*) from (
      select bindings.canonical_match_id
      from public.pachanga_venue_match_bindings bindings
      join public.pachanga_competition_match_contexts contexts
        on contexts.canonical_match_id = bindings.canonical_match_id
      where contexts.competition_id = target_competition_id
        and bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
      group by bindings.canonical_match_id having count(*) > 1
    ) duplicate_bindings),
    'publishedHardViolations', (select count(*)
      from public.pachanga_competition_venue_allocation_revisions revisions
      join public.pachanga_competition_venue_allocation_plans plans
        on plans.id = revisions.allocation_plan_id
      where plans.competition_id = target_competition_id
        and plans.status = 'published' and revisions.id = plans.current_revision_id
        and revisions.hard_violation_count > 0),
    'checkedAt', clock_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_recurring_reservation_series_v1(
  target_series_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare series_row public.pachanga_venue_recurring_series%rowtype;
begin
  if not private.pachanga_venue_recurring_series_can_read_v1(target_series_id, actor_id) then
    raise exception 'VENUE_RECURRING_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into series_row from public.pachanga_venue_recurring_series series
  where series.id = target_series_id;
  return jsonb_build_object(
    'seriesId', series_row.id,
    'venueId', series_row.venue_id,
    'pitchId', series_row.pitch_id,
    'purpose', series_row.purpose,
    'teamId', series_row.team_id,
    'competitionId', series_row.competition_id,
    'modality', series_row.modality,
    'frequency', series_row.frequency,
    'timezone', series_row.timezone,
    'weekday', series_row.weekday,
    'localStartTime', series_row.local_start_time,
    'durationMinutes', series_row.duration_minutes,
    'bufferMinutes', series_row.buffer_minutes,
    'startDate', series_row.start_date,
    'endDate', series_row.end_date,
    'status', series_row.status,
    'currentRevisionId', series_row.current_revision_id,
    'revision', series_row.revision,
    'serverSequence', series_row.server_sequence,
    'updatedAt', series_row.updated_at,
    'occurrenceCounts', jsonb_build_object(
      'planned', (select count(*) from public.pachanga_venue_recurring_occurrences occurrences
        where occurrences.series_id = series_row.id and occurrences.status = 'planned'),
      'reserved', (select count(*) from public.pachanga_venue_recurring_occurrences occurrences
        where occurrences.series_id = series_row.id and occurrences.status = 'reserved'),
      'consumed', (select count(*) from public.pachanga_venue_recurring_occurrences occurrences
        where occurrences.series_id = series_row.id and occurrences.status = 'consumed'),
      'excluded', (select count(*) from public.pachanga_venue_recurring_occurrences occurrences
        where occurrences.series_id = series_row.id and occurrences.status = 'excluded')
    )
  );
end;
$$;

create or replace function public.get_pachanga_recurring_reservation_calendar_v1(
  target_series_id uuid,
  range_start date default null,
  range_end date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare series_row public.pachanga_venue_recurring_series%rowtype;
declare selected_start date;
declare selected_end date;
begin
  if not private.pachanga_venue_recurring_series_can_read_v1(target_series_id, actor_id) then
    raise exception 'VENUE_RECURRING_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into series_row from public.pachanga_venue_recurring_series series
  where series.id = target_series_id;
  selected_start := coalesce(range_start, series_row.start_date);
  selected_end := coalesce(range_end, least(series_row.end_date, selected_start + 365));
  if selected_end < selected_start or selected_end > selected_start + 728 then
    raise exception 'VENUE_RECURRING_CALENDAR_RANGE_INVALID' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'seriesId', series_row.id,
    'rangeStart', selected_start,
    'rangeEnd', selected_end,
    'timezone', series_row.timezone,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'occurrenceId', occurrences.id,
      'seriesRevisionId', occurrences.series_revision_id,
      'occurrenceDate', occurrences.occurrence_date,
      'startsAt', occurrences.starts_at,
      'endsAt', occurrences.ends_at,
      'venueId', occurrences.venue_id,
      'pitchId', occurrences.pitch_id,
      'exceptionId', occurrences.exception_id,
      'reservationId', occurrences.reservation_id,
      'status', occurrences.status,
      'checksum', occurrences.checksum,
      'revision', occurrences.revision,
      'serverSequence', occurrences.server_sequence
    ) order by occurrences.occurrence_date, occurrences.server_sequence, occurrences.id)
    from public.pachanga_venue_recurring_occurrences occurrences
    where occurrences.series_id = series_row.id
      and occurrences.occurrence_date between selected_start and selected_end), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pachanga_competition_venue_pool_v1(
  target_pool_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare pool_row public.pachanga_competition_venue_pools%rowtype;
begin
  if not private.pachanga_venue_pool_can_read_v1(target_pool_id, actor_id) then
    raise exception 'VENUE_POOL_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into pool_row from public.pachanga_competition_venue_pools pools
  where pools.id = target_pool_id;
  return jsonb_build_object(
    'pool', jsonb_build_object(
      'poolId', pool_row.id,
      'competitionId', pool_row.competition_id,
      'editionId', pool_row.edition_id,
      'name', pool_row.name,
      'purpose', pool_row.purpose,
      'visibility', pool_row.visibility,
      'status', pool_row.status,
      'currentRevisionId', pool_row.current_revision_id,
      'revision', pool_row.revision,
      'serverSequence', pool_row.server_sequence,
      'updatedAt', pool_row.updated_at
    ),
    'authorizations', coalesce((select jsonb_agg(jsonb_build_object(
      'authorizationId', authorizations.id,
      'ownerClubId', authorizations.owner_club_id,
      'venueId', authorizations.venue_id,
      'venueName', venues.name,
      'sourceKind', authorizations.source_kind,
      'recurringSeriesId', authorizations.recurring_series_id,
      'reservationId', authorizations.reservation_id,
      'pitchIds', authorizations.authorized_pitch_ids,
      'modalities', authorizations.modalities,
      'validFrom', authorizations.valid_from,
      'validUntil', authorizations.valid_until,
      'allowedWeekdays', authorizations.allowed_weekdays,
      'localStartTime', authorizations.local_start_time,
      'localEndTime', authorizations.local_end_time,
      'capacityPerSlot', authorizations.capacity_per_slot,
      'priority', authorizations.priority,
      'status', authorizations.status,
      'revision', authorizations.revision,
      'serverSequence', authorizations.server_sequence
    ) order by authorizations.priority, authorizations.server_sequence, authorizations.id)
    from public.pachanga_competition_venue_authorizations authorizations
    join public.pachanga_club_venues venues on venues.id = authorizations.venue_id
    where authorizations.pool_id = pool_row.id), '[]'::jsonb),
    'memberships', coalesce((select jsonb_agg(jsonb_build_object(
      'membershipId', memberships.id,
      'authorizationId', memberships.authorization_id,
      'venueId', memberships.venue_id,
      'pitchId', memberships.pitch_id,
      'pitchName', pitches.name,
      'modality', memberships.modality,
      'priority', memberships.priority,
      'capacityLimit', memberships.capacity_limit,
      'consumedCount', memberships.consumed_count,
      'status', memberships.status,
      'revision', memberships.revision,
      'serverSequence', memberships.server_sequence
    ) order by memberships.priority, memberships.pitch_id, memberships.modality)
    from public.pachanga_competition_venue_pool_memberships memberships
    join public.pachanga_venue_pitches pitches on pitches.id = memberships.pitch_id
    where memberships.pool_id = pool_row.id), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pachanga_venue_allocation_match_v1(
  target_canonical_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare binding_row public.pachanga_venue_match_bindings%rowtype;
declare reservation_row public.pachanga_venue_reservations%rowtype;
declare allowed boolean := false;
begin
  if actor_id is null then raise exception 'VENUE_AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = target_canonical_match_id
  order by contexts.server_sequence desc, contexts.id desc limit 1;
  allowed := context_row.id is not null and (
    private.pachanga_competition_venue_can_v1(context_row.competition_id, actor_id, 'read')
    or exists (
      select 1
      from public.pachanga_match_participants participants
      join public.pachanga_player_profiles profiles on profiles.id = participants.player_profile_id
      where participants.canonical_match_id = target_canonical_match_id
        and profiles.user_id = actor_id
    ) or exists (
      select 1
      from public.pachanga_referee_assignments assignments
      join public.pachanga_referee_profiles profiles on profiles.id = assignments.referee_profile_id
      where assignments.canonical_match_id = target_canonical_match_id
        and assignments.status in ('accepted', 'confirmed', 'completed')
        and profiles.user_id = actor_id
    )
  );
  if not allowed then raise exception 'VENUE_MATCH_READ_FORBIDDEN' using errcode = '42501'; end if;
  select * into binding_row
  from public.pachanga_venue_match_bindings bindings
  where bindings.canonical_match_id = target_canonical_match_id
    and bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
  order by bindings.server_sequence desc, bindings.id desc limit 1;
  if binding_row.id is null then
    return jsonb_build_object(
      'canonicalMatchId', target_canonical_match_id,
      'bindingStatus', 'UNASSIGNED',
      'venueStatus', context_row.venue_status,
      'revision', context_row.revision,
      'serverSequence', context_row.server_sequence
    );
  end if;
  select * into reservation_row
  from public.pachanga_venue_reservations reservations
  where reservations.id = binding_row.reservation_id;
  return jsonb_build_object(
    'canonicalMatchId', target_canonical_match_id,
    'competitionMatchContextId', context_row.id,
    'scheduledStart', context_row.scheduled_start,
    'scheduledEnd', context_row.scheduled_end,
    'timezone', context_row.timezone,
    'venueId', binding_row.venue_id,
    'venueName', (select venues.name from public.pachanga_club_venues venues
      where venues.id = binding_row.venue_id),
    'pitchId', binding_row.pitch_id,
    'pitchName', (select pitches.name from public.pachanga_venue_pitches pitches
      where pitches.id = binding_row.pitch_id),
    'reservationId', binding_row.reservation_id,
    'reservationStatus', reservation_row.status,
    'bindingId', binding_row.id,
    'bindingStatus', binding_row.status,
    'actionRequiredCode', binding_row.action_required_code,
    'bindingRevision', binding_row.binding_revision,
    'serverSequence', greatest(binding_row.server_sequence, context_row.server_sequence)
  );
end;
$$;

create or replace function public.get_pachanga_platform_venue_allocation_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null or coalesce(
    private.pachanga_platform_role_for_user_v1(actor_id), 'none'
  ) not in ('platform_owner', 'platform_admin') then
    raise exception 'VENUE_PLATFORM_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'counts', jsonb_build_object(
      'recurringSeries', (select count(*) from public.pachanga_venue_recurring_series),
      'occurrences', (select count(*) from public.pachanga_venue_recurring_occurrences),
      'pools', (select count(*) from public.pachanga_competition_venue_pools),
      'authorizations', (select count(*) from public.pachanga_competition_venue_authorizations),
      'plans', (select count(*) from public.pachanga_competition_venue_allocation_plans),
      'revisions', (select count(*) from public.pachanga_competition_venue_allocation_revisions),
      'items', (select count(*) from public.pachanga_competition_venue_allocation_items),
      'activeHolds', (select count(*) from public.pachanga_competition_venue_allocation_holds
        where status = 'active'),
      'publishedPlans', (select count(*) from public.pachanga_competition_venue_allocation_plans
        where status = 'published'),
      'conflicts', (select count(*) from private.pachanga_competition_venue_allocation_conflicts
        where status = 'active'),
      'hardViolations', (select count(*) from private.pachanga_competition_venue_allocation_conflicts
        where status = 'active' and severity = 'HARD')
    ),
    'health', jsonb_build_object(
      'expiredActiveHolds', (select count(*)
        from public.pachanga_competition_venue_allocation_holds
        where status = 'active' and expires_at <= clock_timestamp()),
      'publishedHardViolations', (select count(*)
        from public.pachanga_competition_venue_allocation_revisions revisions
        join public.pachanga_competition_venue_allocation_plans plans
          on plans.id = revisions.allocation_plan_id
        where plans.status = 'published' and revisions.id = plans.current_revision_id
          and revisions.hard_violation_count > 0),
      'multipleCurrentBindings', (select count(*) from (
        select bindings.canonical_match_id
        from public.pachanga_venue_match_bindings bindings
        where bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
        group by bindings.canonical_match_id having count(*) > 1
      ) duplicates),
      'privateCoordinatesReturned', 0,
      'checkedAt', clock_timestamp()
    ),
    'latestSequence', greatest(
      coalesce((select max(server_sequence) from public.pachanga_competition_venue_allocation_plans), 0),
      coalesce((select max(server_sequence) from public.pachanga_venue_recurring_series), 0),
      coalesce((select max(server_sequence) from public.pachanga_competition_venue_pools), 0)
    )
  );
end;
$$;

create or replace function public.get_pachanga_season_venue_home_status_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null then raise exception 'VENUE_AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  return jsonb_build_object(
    'clubBookingManager', jsonb_build_object(
      'visible', exists (select 1 from public.pachanga_clubs clubs
        where private.pachanga_club_can_v1(clubs.id, actor_id, 'reservation_manage')),
      'blocksToPublish', (select count(*)
        from public.pachanga_venue_recurring_series series
        where series.status in ('validated', 'offered', 'accepted')
          and private.pachanga_club_can_v1(series.owner_club_id, actor_id, 'reservation_manage')),
      'holdsExpiring', (select count(*)
        from public.pachanga_competition_venue_allocation_holds holds
        join public.pachanga_competition_venue_allocation_plans plans
          on plans.id = holds.allocation_plan_id
        join public.pachanga_competition_venue_authorizations authorizations
          on authorizations.pool_id = plans.venue_pool_id
        where holds.status = 'active'
          and holds.expires_at <= clock_timestamp() + interval '30 minutes'
          and private.pachanga_club_can_v1(
            authorizations.owner_club_id, actor_id, 'reservation_manage'
          )),
      'seasonConflicts', (select count(*)
        from private.pachanga_competition_venue_allocation_conflicts conflicts
        join public.pachanga_competition_venue_allocation_plans plans
          on plans.id = conflicts.allocation_plan_id
        join public.pachanga_competition_venue_authorizations authorizations
          on authorizations.pool_id = plans.venue_pool_id
        where conflicts.status = 'active' and private.pachanga_club_can_v1(
          authorizations.owner_club_id, actor_id, 'reservation_read'
        ))
    ),
    'competitionOrganizer', jsonb_build_object(
      'visible', exists (select 1 from public.pachanga_competitions competitions
        where private.pachanga_competition_venue_can_v1(competitions.id, actor_id, 'manage')),
      'matchesWithoutVenue', (select count(*)
        from public.pachanga_competition_venue_allocation_items items
        join public.pachanga_competition_venue_allocation_plans plans
          on plans.id = items.allocation_plan_id
        where plans.current_revision_id = items.allocation_revision_id
          and items.pitch_id is null
          and private.pachanga_competition_venue_can_v1(plans.competition_id, actor_id, 'read')),
      'stalePlans', (select count(*)
        from public.pachanga_competition_venue_allocation_plans plans
        where plans.status = 'stale'
          and private.pachanga_competition_venue_can_v1(plans.competition_id, actor_id, 'read')),
      'readyToPublish', (select count(*)
        from public.pachanga_competition_venue_allocation_plans plans
        where plans.status = 'validated'
          and private.pachanga_competition_venue_can_v1(plans.competition_id, actor_id, 'publish')),
      'cancelledReservations', (select count(*)
        from public.pachanga_venue_reservations reservations
        where reservations.competition_id is not null and reservations.status = 'CANCELLED'
          and private.pachanga_competition_venue_can_v1(
            reservations.competition_id, actor_id, 'read'
          ))
    ),
    'teamOwner', jsonb_build_object(
      'visible', exists (select 1 from public.pachanga_groups groups where groups.owner_id = actor_id),
      'pendingRecurringBlocks', (select count(*)
        from public.pachanga_venue_recurring_series series
        join public.pachanga_groups groups on groups.id = series.team_id
        where groups.owner_id = actor_id and series.status in ('offered', 'accepted')),
      'confirmedFields', (select count(*)
        from public.pachanga_venue_reservations reservations
        join public.pachanga_groups groups on groups.id = reservations.requester_team_id
        where groups.owner_id = actor_id and reservations.status = 'CONFIRMED')
    )
  );
end;
$$;

create or replace function public.get_pachanga_season_venue_catalog_v1(
  target_club_id uuid default null,
  target_competition_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare can_read_club boolean := false;
declare can_read_competition boolean := false;
begin
  if actor_id is null or (target_club_id is null and target_competition_id is null) then
    raise exception 'VENUE_CATALOG_READ_FORBIDDEN' using errcode = '42501';
  end if;
  can_read_club := target_club_id is not null and private.pachanga_club_can_v1(
    target_club_id, actor_id, 'venue_read'
  );
  can_read_competition := target_competition_id is not null
    and private.pachanga_competition_venue_can_v1(
      target_competition_id, actor_id, 'read'
    );
  if not can_read_club and not can_read_competition
     and coalesce(private.pachanga_platform_role_for_user_v1(actor_id), 'none')
       not in ('platform_owner', 'platform_admin') then
    raise exception 'VENUE_CATALOG_READ_FORBIDDEN' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'clubId', target_club_id,
    'competitionId', target_competition_id,
    'recurringSeries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'seriesId', series.id,
        'venueId', series.venue_id,
        'pitchId', series.pitch_id,
        'purpose', series.purpose,
        'teamId', series.team_id,
        'competitionId', series.competition_id,
        'modality', series.modality,
        'frequency', series.frequency,
        'timezone', series.timezone,
        'weekday', series.weekday,
        'localStartTime', series.local_start_time,
        'durationMinutes', series.duration_minutes,
        'startDate', series.start_date,
        'endDate', series.end_date,
        'status', series.status,
        'revision', series.revision,
        'serverSequence', series.server_sequence,
        'updatedAt', series.updated_at
      ) order by series.server_sequence desc, series.id)
      from public.pachanga_venue_recurring_series series
      where (target_club_id is null or series.owner_club_id = target_club_id)
        and (target_competition_id is null or series.competition_id = target_competition_id)
        and private.pachanga_venue_recurring_series_can_read_v1(series.id, actor_id)
    ), '[]'::jsonb),
    'venuePools', coalesce((
      select jsonb_agg(jsonb_build_object(
        'poolId', pools.id,
        'competitionId', pools.competition_id,
        'editionId', pools.edition_id,
        'name', pools.name,
        'visibility', pools.visibility,
        'status', pools.status,
        'revision', pools.revision,
        'serverSequence', pools.server_sequence,
        'updatedAt', pools.updated_at,
        'activeMemberships', (select count(*)
          from public.pachanga_competition_venue_pool_memberships memberships
          where memberships.pool_id = pools.id and memberships.status = 'active')
      ) order by pools.server_sequence desc, pools.id)
      from public.pachanga_competition_venue_pools pools
      where (target_competition_id is null or pools.competition_id = target_competition_id)
        and (target_club_id is null or pools.organizer_club_id = target_club_id
          or exists (select 1
            from public.pachanga_competition_venue_authorizations authorizations
            where authorizations.pool_id = pools.id
              and authorizations.owner_club_id = target_club_id))
        and private.pachanga_venue_pool_can_read_v1(pools.id, actor_id)
    ), '[]'::jsonb),
    'allocationPlans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'planId', plans.id,
        'competitionId', plans.competition_id,
        'editionId', plans.edition_id,
        'stageId', plans.stage_id,
        'mode', plans.mode,
        'status', plans.status,
        'revision', plans.revision,
        'serverSequence', plans.server_sequence,
        'updatedAt', plans.updated_at
      ) order by plans.server_sequence desc, plans.id)
      from public.pachanga_competition_venue_allocation_plans plans
      where target_competition_id is not null
        and plans.competition_id = target_competition_id
        and private.pachanga_competition_venue_can_v1(
          plans.competition_id, actor_id, 'read'
        )
    ), '[]'::jsonb),
    'serverSequence', greatest(
      coalesce((select max(series.server_sequence)
        from public.pachanga_venue_recurring_series series
        where (target_club_id is null or series.owner_club_id = target_club_id)
          and (target_competition_id is null or series.competition_id = target_competition_id)), 0),
      coalesce((select max(pools.server_sequence)
        from public.pachanga_competition_venue_pools pools
        where (target_competition_id is null or pools.competition_id = target_competition_id)), 0),
      coalesce((select max(plans.server_sequence)
        from public.pachanga_competition_venue_allocation_plans plans
        where target_competition_id is not null
          and plans.competition_id = target_competition_id), 0)
    ),
    'readAt', clock_timestamp()
  );
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'public.get_pachanga_competition_venue_allocation_overview_v1(uuid)'::regprocedure,
    'public.get_pachanga_competition_venue_allocation_desk_v1(uuid)'::regprocedure,
    'public.get_pachanga_competition_venue_allocation_revision_v1(uuid)'::regprocedure,
    'public.get_pachanga_competition_venue_allocation_diff_v1(uuid,uuid)'::regprocedure,
    'public.get_pachanga_competition_venue_allocation_health_v1(uuid)'::regprocedure,
    'public.get_pachanga_recurring_reservation_series_v1(uuid)'::regprocedure,
    'public.get_pachanga_recurring_reservation_calendar_v1(uuid,date,date)'::regprocedure,
    'public.get_pachanga_competition_venue_pool_v1(uuid)'::regprocedure,
    'public.get_pachanga_venue_allocation_match_v1(uuid)'::regprocedure,
    'public.get_pachanga_platform_venue_allocation_health_v1()'::regprocedure,
    'public.get_pachanga_season_venue_home_status_v1()'::regprocedure,
    'public.get_pachanga_season_venue_catalog_v1(uuid,uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon', signature);
    execute format('grant execute on function %s to authenticated, service_role', signature);
  end loop;
end
$$;

comment on function public.get_pachanga_competition_venue_allocation_desk_v1(uuid) is
  'Canonical planner projection. Quality is precomputed by PostgreSQL; private coordinates, contacts and actor identities are excluded.';

reset statement_timeout;
reset lock_timeout;
