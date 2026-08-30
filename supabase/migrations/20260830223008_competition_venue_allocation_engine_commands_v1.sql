-- Pachangas IQ Wave 9B: deterministic allocator and authoritative draft commands.

set lock_timeout = '5s';
set statement_timeout = '5min';

alter table private.pachanga_venue_settings_v1
  add column if not exists competition_venue_allocation_automatic_enabled boolean not null default false,
  add column if not exists competition_venue_allocation_manual_enabled boolean not null default false,
  add column if not exists competition_venue_allocation_hybrid_enabled boolean not null default false,
  add column if not exists joint_schedule_venue_optimization_enabled boolean not null default false;

create or replace function private.pachanga_venue_allocation_json_checksum_v1(source jsonb)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(coalesce(source, 'null'::jsonb)::text, 'UTF8'), 'sha256'), 'hex');
$$;

revoke all on function private.pachanga_venue_allocation_json_checksum_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_parameters_safe_v1(source jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  key_name text;
  normalized_key text;
  nested_value jsonb;
begin
  if source is null then return true; end if;
  if octet_length(source::text) > 4096 then return false; end if;
  if jsonb_typeof(source) = 'object' then
    for key_name, nested_value in select entries.key, entries.value from jsonb_each(source) entries loop
      normalized_key := regexp_replace(lower(key_name), '[^a-z0-9]', '', 'g');
      if normalized_key = any(array[
        'latitude','longitude','coordinates','address','privateaddress',
        'contact','contactname','contactphone','contactemail','phone','email',
        'accessinstructions','authid','userid','actorid','secret','token',
        'privatenotes','connectionurl'
      ]) then return false; end if;
      if not private.pachanga_venue_allocation_parameters_safe_v1(nested_value) then
        return false;
      end if;
    end loop;
  elsif jsonb_typeof(source) = 'array' then
    for nested_value in select values_row.value from jsonb_array_elements(source) values_row(value) loop
      if not private.pachanga_venue_allocation_parameters_safe_v1(nested_value) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$$;

create or replace function private.pachanga_venue_recurring_conflict_v1(target_series_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.pachanga_venue_recurring_series target
    join public.pachanga_venue_recurring_series other
      on other.pitch_id = target.pitch_id
     and other.id <> target.id
     and other.status in ('accepted', 'published', 'paused')
     and daterange(other.start_date, other.end_date, '[]')
       && daterange(target.start_date, target.end_date, '[]')
     and other.weekday = target.weekday
     and int4range(
       extract(epoch from other.local_start_time)::integer / 60 - other.buffer_minutes,
       extract(epoch from other.local_start_time)::integer / 60
         + other.duration_minutes + other.buffer_minutes,
       '[)'
     ) && int4range(
       extract(epoch from target.local_start_time)::integer / 60 - target.buffer_minutes,
       extract(epoch from target.local_start_time)::integer / 60
         + target.duration_minutes + target.buffer_minutes,
       '[)'
     )
    where target.id = target_series_id
  );
$$;

revoke all on function private.pachanga_venue_recurring_conflict_v1(uuid)
  from public, anon, authenticated;

revoke all on function private.pachanga_venue_allocation_parameters_safe_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_venue_can_v1(
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
declare actor_role text;
begin
  if target_actor_id is null then return false; end if;
  if private.pachanga_platform_role_for_user_v1(target_actor_id)
     in ('platform_owner', 'platform_admin') then return true; end if;
  actor_role := private.pachanga_competition_actor_role_v1(
    target_competition_id, target_actor_id
  );
  if target_capability = 'read' and actor_role is not null then return true; end if;
  if actor_role = 'competition_owner' then return true; end if;
  return case actor_role
    when 'competition_director' then target_capability in ('read', 'manage', 'publish')
    when 'competition_admin' then target_capability in ('read', 'manage', 'publish')
    when 'competition_operations_manager' then target_capability in ('read', 'manage', 'publish')
    when 'competition_schedule_manager' then target_capability in ('read', 'manage', 'publish')
    when 'competition_venue_manager' then target_capability in ('read', 'manage', 'publish')
    when 'viewer' then target_capability = 'read'
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_venue_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_assert_flags_v1(target_capability text)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_venue_settings_v1%rowtype;
begin
  select * into settings from private.pachanga_venue_settings_v1 where singleton;
  perform private.pachanga_venue_assert_flags_v1('availability');
  if target_capability in ('recurring', 'materialize')
     and not settings.venue_recurring_series_enabled then
    raise exception 'VENUE_RECURRING_SERIES_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'materialize'
     and not settings.venue_recurring_materialization_enabled then
    raise exception 'VENUE_RECURRING_MATERIALIZATION_DISABLED' using errcode = '0A000';
  end if;
  if target_capability in ('pool', 'allocation', 'automatic', 'manual', 'hybrid')
     and not settings.competition_venue_pool_enabled then
    raise exception 'COMPETITION_VENUE_POOL_DISABLED' using errcode = '0A000';
  end if;
  if target_capability in ('allocation', 'automatic', 'manual', 'hybrid')
     and not settings.competition_venue_allocation_foundation_enabled then
    raise exception 'VENUE_ALLOCATION_FOUNDATION_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'automatic'
     and not settings.competition_venue_allocation_automatic_enabled then
    raise exception 'VENUE_ALLOCATION_AUTOMATIC_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'manual'
     and not settings.competition_venue_allocation_manual_enabled then
    raise exception 'VENUE_ALLOCATION_MANUAL_DISABLED' using errcode = '0A000';
  end if;
  if target_capability = 'hybrid'
     and not settings.competition_venue_allocation_hybrid_enabled then
    raise exception 'VENUE_ALLOCATION_HYBRID_DISABLED' using errcode = '0A000';
  end if;
end;
$$;

revoke all on function private.pachanga_venue_allocation_assert_flags_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_modality_v1(rule_document jsonb)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case upper(replace(replace(coalesce(
    rule_document #>> '{format,modality}',
    rule_document #>> '{sport,modality}',
    rule_document ->> 'modality',
    'F7'
  ), '-', ''), '_', ''))
    when 'F5' then 'F5'
    when 'FUTBOL5' then 'F5'
    when 'FOOTBALL5' then 'F5'
    when 'F7' then 'F7'
    when 'FUTBOL7' then 'F7'
    when 'FOOTBALL7' then 'F7'
    when 'F11' then 'F11'
    when 'FUTBOL11' then 'F11'
    when 'FOOTBALL11' then 'F11'
    when 'FUTSAL' then 'FUTSAL'
    when 'FUTBOLSALA' then 'FUTSAL'
    else 'F7' end;
$$;

revoke all on function private.pachanga_venue_allocation_modality_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_materialize_series_v1(
  target_series_id uuid,
  target_actor_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare series_row public.pachanga_venue_recurring_series%rowtype;
declare revision_row private.pachanga_venue_recurring_series_revisions%rowtype;
declare occurrence_day date;
declare exception_row public.pachanga_venue_recurring_exceptions%rowtype;
declare selected_pitch_id uuid;
declare selected_start_time time;
declare selected_duration integer;
declare selected_start timestamptz;
declare selected_end timestamptz;
declare occurrence_id uuid;
declare occurrence_checksum text;
declare inserted_count integer := 0;
declare cadence_days integer;
begin
  select * into series_row from public.pachanga_venue_recurring_series rows
  where rows.id = target_series_id for update;
  if not found then raise exception 'VENUE_RECURRING_SERIES_NOT_FOUND' using errcode = 'P0002'; end if;
  if series_row.status not in ('accepted', 'published', 'paused', 'completed', 'ended') then
    raise exception 'VENUE_RECURRING_SERIES_NOT_MATERIALIZABLE' using errcode = '22023';
  end if;
  select * into revision_row from private.pachanga_venue_recurring_series_revisions rows
  where rows.id = series_row.current_revision_id;
  if not found then raise exception 'VENUE_RECURRING_REVISION_REQUIRED' using errcode = '22023'; end if;
  cadence_days := case series_row.frequency when 'WEEKLY' then 7 else 14 end;
  for occurrence_day in
    select days.day::date
    from generate_series(series_row.start_date, series_row.end_date, interval '1 day') days(day)
    where extract(isodow from days.day)::smallint = series_row.weekday
      and mod(
        days.day::date - (
          series_row.start_date
          + mod(series_row.weekday - extract(isodow from series_row.start_date)::integer + 7, 7)
        ),
        cadence_days
      ) = 0
    order by days.day
  loop
    select * into exception_row
    from public.pachanga_venue_recurring_exceptions rows
    where rows.series_id = series_row.id and rows.exception_date = occurrence_day
      and rows.status = 'active'
    order by rows.server_sequence desc, rows.id desc limit 1;
    selected_pitch_id := series_row.pitch_id;
    selected_start_time := series_row.local_start_time;
    selected_duration := series_row.duration_minutes;
    if found and exception_row.exception_kind = 'REPLACE' then
      selected_pitch_id := coalesce(exception_row.replacement_pitch_id, selected_pitch_id);
      selected_start_time := exception_row.replacement_local_start_time;
      selected_duration := exception_row.replacement_duration_minutes;
    end if;
    selected_start := private.pachanga_venue_resolve_local_v1(
      occurrence_day + selected_start_time,
      series_row.timezone,
      series_row.local_offset_minutes
    );
    selected_end := selected_start + make_interval(mins => selected_duration);
    occurrence_id := private.pachanga_venue_deterministic_uuid_v1(
      'wave9b:recurrence:' || series_row.id::text || ':' || occurrence_day::text
    );
    occurrence_checksum := private.pachanga_venue_allocation_json_checksum_v1(
      jsonb_build_object(
        'seriesId', series_row.id, 'seriesRevisionId', revision_row.id,
        'occurrenceDate', occurrence_day, 'startsAt', selected_start,
        'endsAt', selected_end, 'pitchId', selected_pitch_id,
        'exceptionId', case when found then exception_row.id else null end
      )
    );
    insert into public.pachanga_venue_recurring_occurrences(
      id, series_id, series_revision_id, occurrence_date, starts_at, ends_at,
      timezone, venue_id, pitch_id, exception_id, status, checksum
    ) values (
      occurrence_id, series_row.id, revision_row.id, occurrence_day,
      selected_start, selected_end, series_row.timezone, series_row.venue_id,
      selected_pitch_id, case when found then exception_row.id else null end,
      case when found and exception_row.exception_kind = 'SKIP' then 'excluded' else 'planned' end,
      occurrence_checksum
    ) on conflict (series_id, occurrence_date) do update set
      series_revision_id = excluded.series_revision_id,
      starts_at = case when public.pachanga_venue_recurring_occurrences.status
        in ('reserved', 'consumed') then public.pachanga_venue_recurring_occurrences.starts_at
        else excluded.starts_at end,
      ends_at = case when public.pachanga_venue_recurring_occurrences.status
        in ('reserved', 'consumed') then public.pachanga_venue_recurring_occurrences.ends_at
        else excluded.ends_at end,
      pitch_id = case when public.pachanga_venue_recurring_occurrences.status
        in ('reserved', 'consumed') then public.pachanga_venue_recurring_occurrences.pitch_id
        else excluded.pitch_id end,
      exception_id = case when public.pachanga_venue_recurring_occurrences.status
        in ('reserved', 'consumed') then public.pachanga_venue_recurring_occurrences.exception_id
        else excluded.exception_id end,
      status = case when public.pachanga_venue_recurring_occurrences.status
        in ('reserved', 'consumed') then public.pachanga_venue_recurring_occurrences.status
        else excluded.status end,
      checksum = case when public.pachanga_venue_recurring_occurrences.status
        in ('reserved', 'consumed') then public.pachanga_venue_recurring_occurrences.checksum
        else excluded.checksum end,
      revision = case when public.pachanga_venue_recurring_occurrences.checksum = excluded.checksum
        then public.pachanga_venue_recurring_occurrences.revision
        else public.pachanga_venue_recurring_occurrences.revision + 1 end,
      server_sequence = case when public.pachanga_venue_recurring_occurrences.checksum = excluded.checksum
        then public.pachanga_venue_recurring_occurrences.server_sequence
        else nextval('private.pachanga_venue_sequence') end,
      updated_at = case when public.pachanga_venue_recurring_occurrences.checksum = excluded.checksum
        then public.pachanga_venue_recurring_occurrences.updated_at else clock_timestamp() end;
    if found then inserted_count := inserted_count + 1; end if;
  end loop;
  return inserted_count;
end;
$$;

revoke all on function private.pachanga_venue_materialize_series_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_input_snapshot_v1(
  target_plan_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare rule_row public.pachanga_competition_rule_revisions%rowtype;
declare match_rows jsonb;
declare pool_rows jsonb;
declare availability_rows jsonb;
declare recurring_rows jsonb;
declare reservation_rows jsonb;
declare binding_rows jsonb;
declare exception_rows jsonb;
declare pitch_rows jsonb;
begin
  select * into plan_row from public.pachanga_competition_venue_allocation_plans rows
  where rows.id = target_plan_id;
  if not found then raise exception 'VENUE_ALLOCATION_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into rule_row from public.pachanga_competition_rule_revisions rows
  where rows.id = plan_row.rule_revision_id;

  select coalesce(jsonb_agg(item order by item ->> 'scheduledStart', item ->> 'canonicalMatchId'), '[]'::jsonb)
  into match_rows from (
    select jsonb_build_object(
      'scheduleItemId', items.id,
      'canonicalMatchId', items.canonical_match_id,
      'competitionMatchContextId', items.competition_match_context_id,
      'roundId', items.round_id,
      'homeEntryId', items.home_entry_id,
      'awayEntryId', items.away_entry_id,
      'scheduledStart', contexts.scheduled_start,
      'scheduledEnd', contexts.scheduled_end,
      'timezone', contexts.timezone,
      'scheduleItemRevision', items.revision,
      'contextRevision', contexts.revision,
      'contextSequence', contexts.server_sequence
    ) item
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_match_contexts contexts
      on contexts.id = items.competition_match_context_id
    where items.schedule_revision_id = plan_row.schedule_revision_id
      and items.canonical_match_id is not null
      and items.competition_match_context_id is not null
      and contexts.status = 'scheduled'
      and contexts.scheduled_start is not null and contexts.scheduled_end is not null
  ) snapshots;

  select coalesce(jsonb_agg(item order by item ->> 'priority', item ->> 'pitchId'), '[]'::jsonb)
  into pool_rows from (
    select jsonb_build_object(
      'membershipId', memberships.id, 'authorizationId', authorizations.id,
      'venueId', memberships.venue_id, 'pitchId', memberships.pitch_id,
      'modality', memberships.modality, 'priority', memberships.priority,
      'capacityLimit', memberships.capacity_limit, 'consumedCount', memberships.consumed_count,
      'membershipRevision', memberships.revision, 'authorizationRevision', authorizations.revision,
      'validFrom', authorizations.valid_from, 'validUntil', authorizations.valid_until,
      'allowedWeekdays', authorizations.allowed_weekdays,
      'localStartTime', authorizations.local_start_time,
      'localEndTime', authorizations.local_end_time,
      'sourceKind', authorizations.source_kind,
      'recurringSeriesId', authorizations.recurring_series_id,
      'reservationId', authorizations.reservation_id
    ) item
    from public.pachanga_competition_venue_pool_memberships memberships
    join public.pachanga_competition_venue_authorizations authorizations
      on authorizations.id = memberships.authorization_id
    where memberships.pool_id = plan_row.venue_pool_id
      and memberships.status = 'active' and authorizations.status = 'active'
  ) snapshots;

  select coalesce(jsonb_agg(item order by item ->> 'pitchId', item ->> 'serverSequence'), '[]'::jsonb)
  into availability_rows from (
    select jsonb_build_object(
      'kind', 'TEMPLATE', 'id', templates.id, 'pitchId', templates.pitch_id,
      'revision', templates.revision, 'serverSequence', templates.server_sequence,
      'status', templates.status, 'weekday', templates.weekday,
      'start', templates.start_local_time, 'end', templates.end_local_time,
      'validFrom', templates.valid_from, 'validUntil', templates.valid_until,
      'modalities', templates.modalities
    ) item from public.pachanga_venue_availability_templates templates
    where templates.pitch_id in (
      select memberships.pitch_id from public.pachanga_competition_venue_pool_memberships memberships
      where memberships.pool_id = plan_row.venue_pool_id and memberships.status = 'active'
    )
  ) snapshots;

  select coalesce(jsonb_agg(item order by item ->> 'startsAt', item ->> 'id'), '[]'::jsonb)
  into recurring_rows from (
    select jsonb_build_object(
      'id', occurrences.id, 'seriesId', occurrences.series_id,
      'seriesRevisionId', occurrences.series_revision_id,
      'pitchId', occurrences.pitch_id, 'startsAt', occurrences.starts_at,
      'endsAt', occurrences.ends_at, 'status', occurrences.status,
      'checksum', occurrences.checksum, 'revision', occurrences.revision,
      'serverSequence', occurrences.server_sequence
    ) item from public.pachanga_venue_recurring_occurrences occurrences
    where occurrences.pitch_id in (
      select memberships.pitch_id from public.pachanga_competition_venue_pool_memberships memberships
      where memberships.pool_id = plan_row.venue_pool_id and memberships.status = 'active'
    ) and occurrences.status in ('planned', 'held', 'reserved')
  ) snapshots;

  select coalesce(jsonb_agg(item order by item ->> 'startsAt', item ->> 'id'), '[]'::jsonb)
  into reservation_rows from (
    select jsonb_build_object(
      'id', reservations.id, 'pitchId', reservations.pitch_id,
      'canonicalMatchId', reservations.canonical_match_id,
      'competitionId', reservations.competition_id,
      'startsAt', reservations.starts_at, 'endsAt', reservations.ends_at,
      'status', reservations.status, 'revision', reservations.revision,
      'serverSequence', reservations.server_sequence
    ) item from public.pachanga_venue_reservations reservations
    where reservations.pitch_id in (
      select memberships.pitch_id from public.pachanga_competition_venue_pool_memberships memberships
      where memberships.pool_id = plan_row.venue_pool_id and memberships.status = 'active'
    ) and reservations.status in ('PENDING_CONFIRMATION', 'CONFIRMED')
  ) snapshots;

  select coalesce(jsonb_agg(item order by item ->> 'canonicalMatchId', item ->> 'serverSequence'), '[]'::jsonb)
  into binding_rows from (
    select jsonb_build_object(
      'id', bindings.id, 'canonicalMatchId', bindings.canonical_match_id,
      'reservationId', bindings.reservation_id, 'venueId', bindings.venue_id,
      'pitchId', bindings.pitch_id, 'status', bindings.status,
      'bindingRevision', bindings.binding_revision,
      'serverSequence', bindings.server_sequence
    ) item from public.pachanga_venue_match_bindings bindings
    where bindings.canonical_match_id in (
      select items.canonical_match_id
      from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = plan_row.schedule_revision_id
        and items.canonical_match_id is not null
    ) and bindings.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
  ) snapshots;

  select coalesce(jsonb_agg(item order by item ->> 'pitchId', item ->> 'serverSequence'), '[]'::jsonb)
  into exception_rows from (
    select jsonb_build_object(
      'id', exceptions.id, 'pitchId', exceptions.pitch_id,
      'kind', exceptions.exception_kind, 'startsAt', exceptions.starts_at,
      'endsAt', exceptions.ends_at, 'status', exceptions.status,
      'revision', exceptions.revision, 'serverSequence', exceptions.server_sequence
    ) item from public.pachanga_venue_availability_exceptions exceptions
    where exceptions.pitch_id in (
      select memberships.pitch_id from public.pachanga_competition_venue_pool_memberships memberships
      where memberships.pool_id = plan_row.venue_pool_id and memberships.status = 'active'
    )
  ) snapshots;

  select coalesce(jsonb_agg(item order by item ->> 'pitchId'), '[]'::jsonb)
  into pitch_rows from (
    select jsonb_build_object(
      'pitchId', pitches.id, 'venueId', pitches.venue_id,
      'conflictScopeId', pitches.conflict_scope_id,
      'pitchStatus', pitches.status, 'venueStatus', venues.lifecycle,
      'modalities', pitches.modalities, 'bufferMinutes', pitches.buffer_minutes,
      'pitchRevision', pitches.revision, 'pitchSequence', pitches.server_sequence,
      'venueRevision', venues.revision, 'venueSequence', venues.server_sequence,
      'timezone', venues.timezone, 'municipality', venues.municipality
    ) item
    from public.pachanga_venue_pitches pitches
    join public.pachanga_club_venues venues on venues.id = pitches.venue_id
    where pitches.id in (
      select memberships.pitch_id from public.pachanga_competition_venue_pool_memberships memberships
      where memberships.pool_id = plan_row.venue_pool_id and memberships.status = 'active'
    )
  ) snapshots;

  return jsonb_build_object(
    'matches', match_rows, 'pool', pool_rows, 'availability', availability_rows,
    'recurring', recurring_rows, 'reservations', reservation_rows,
    'bindings', binding_rows, 'exceptions', exception_rows, 'pitches', pitch_rows,
    'rule', coalesce(rule_row.rule_document, '{}'::jsonb),
    'scheduleRevisionId', plan_row.schedule_revision_id,
    'venuePoolRevisionId', plan_row.venue_pool_revision_id,
    'ruleRevisionId', plan_row.rule_revision_id
  );
end;
$$;

revoke all on function private.pachanga_venue_allocation_input_snapshot_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_freeze_inputs_v1(
  target_plan_id uuid,
  target_operation_id uuid,
  target_actor_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare source jsonb;
declare freeze_id uuid := gen_random_uuid();
declare freeze_version integer;
declare selected_sequence bigint := nextval('private.pachanga_venue_sequence');
declare match_checksum text;
declare schedule_checksum text;
declare pool_checksum text;
declare availability_checksum text;
declare reservation_checksum text;
declare binding_checksum text;
declare rule_checksum text;
declare input_checksum text;
begin
  lock table public.pachanga_competition_schedule_items in share mode;
  lock table public.pachanga_competition_match_contexts in share mode;
  lock table public.pachanga_competition_venue_pool_memberships in share mode;
  lock table public.pachanga_competition_venue_authorizations in share mode;
  lock table public.pachanga_venue_availability_templates in share mode;
  lock table public.pachanga_venue_availability_exceptions in share mode;
  lock table public.pachanga_venue_reservations in share mode;
  lock table public.pachanga_venue_match_bindings in share mode;
  select * into plan_row from public.pachanga_competition_venue_allocation_plans rows
  where rows.id = target_plan_id for update;
  source := private.pachanga_venue_allocation_input_snapshot_v1(target_plan_id);
  if jsonb_array_length(source -> 'matches') = 0 then
    raise exception 'VENUE_ALLOCATION_MATCHES_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_array_length(source -> 'pool') = 0 then
    raise exception 'VENUE_ALLOCATION_POOL_EMPTY' using errcode = '22023';
  end if;
  freeze_version := coalesce((select max(rows.version) + 1
    from private.pachanga_competition_venue_allocation_input_freezes rows
    where rows.allocation_plan_id = target_plan_id), 1);
  match_checksum := private.pachanga_venue_allocation_json_checksum_v1(source -> 'matches');
  schedule_checksum := private.pachanga_venue_allocation_json_checksum_v1(jsonb_build_object(
    'scheduleRevisionId', source -> 'scheduleRevisionId', 'matches', source -> 'matches'
  ));
  pool_checksum := private.pachanga_venue_allocation_json_checksum_v1(source -> 'pool');
  availability_checksum := private.pachanga_venue_allocation_json_checksum_v1(jsonb_build_object(
    'availability', source -> 'availability', 'exceptions', source -> 'exceptions',
    'pitches', source -> 'pitches', 'recurring', source -> 'recurring'
  ));
  reservation_checksum := private.pachanga_venue_allocation_json_checksum_v1(source -> 'reservations');
  binding_checksum := private.pachanga_venue_allocation_json_checksum_v1(source -> 'bindings');
  rule_checksum := private.pachanga_venue_allocation_json_checksum_v1(source -> 'rule');
  input_checksum := private.pachanga_venue_allocation_json_checksum_v1(jsonb_build_object(
    'match', match_checksum, 'schedule', schedule_checksum, 'pool', pool_checksum,
    'availability', availability_checksum, 'reservation', reservation_checksum,
    'binding', binding_checksum, 'rule', rule_checksum
  ));
  insert into private.pachanga_competition_venue_allocation_input_freezes(
    id, allocation_plan_id, version, competition_id, edition_id, stage_id,
    schedule_plan_id, schedule_revision_id, rule_revision_id, venue_pool_id,
    venue_pool_revision_id, match_snapshot, pool_snapshot, availability_snapshot,
    recurring_snapshot, reservation_snapshot, binding_snapshot, exception_snapshot,
    pitch_snapshot, rule_snapshot, match_checksum, schedule_checksum, pool_checksum,
    availability_checksum, reservation_checksum, binding_checksum, rule_checksum,
    input_checksum, operation_id, frozen_by, server_sequence
  ) values (
    freeze_id, target_plan_id, freeze_version, plan_row.competition_id,
    plan_row.edition_id, plan_row.stage_id, plan_row.schedule_plan_id,
    plan_row.schedule_revision_id, plan_row.rule_revision_id, plan_row.venue_pool_id,
    plan_row.venue_pool_revision_id, source -> 'matches', source -> 'pool',
    source -> 'availability', source -> 'recurring', source -> 'reservations',
    source -> 'bindings', source -> 'exceptions', source -> 'pitches',
    source -> 'rule', match_checksum, schedule_checksum, pool_checksum,
    availability_checksum, reservation_checksum, binding_checksum, rule_checksum,
    input_checksum, target_operation_id, target_actor_id, selected_sequence
  );
  update public.pachanga_competition_venue_allocation_plans rows set
    current_input_freeze_id = freeze_id,
    status = 'inputs_frozen', revision = rows.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_by = target_actor_id, updated_at = clock_timestamp()
  where rows.id = target_plan_id;
  return freeze_id;
end;
$$;

revoke all on function private.pachanga_venue_allocation_freeze_inputs_v1(uuid, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_live_input_checksum_v1(
  target_plan_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare source jsonb := private.pachanga_venue_allocation_input_snapshot_v1(target_plan_id);
begin
  return private.pachanga_venue_allocation_json_checksum_v1(jsonb_build_object(
    'match', private.pachanga_venue_allocation_json_checksum_v1(source -> 'matches'),
    'schedule', private.pachanga_venue_allocation_json_checksum_v1(jsonb_build_object(
      'scheduleRevisionId', source -> 'scheduleRevisionId', 'matches', source -> 'matches'
    )),
    'pool', private.pachanga_venue_allocation_json_checksum_v1(source -> 'pool'),
    'availability', private.pachanga_venue_allocation_json_checksum_v1(jsonb_build_object(
      'availability', source -> 'availability', 'exceptions', source -> 'exceptions',
      'pitches', source -> 'pitches', 'recurring', source -> 'recurring'
    )),
    'reservation', private.pachanga_venue_allocation_json_checksum_v1(source -> 'reservations'),
    'binding', private.pachanga_venue_allocation_json_checksum_v1(source -> 'bindings'),
    'rule', private.pachanga_venue_allocation_json_checksum_v1(source -> 'rule')
  ));
end;
$$;

revoke all on function private.pachanga_venue_allocation_live_input_checksum_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_finalize_revision_v1(
  target_revision_id uuid,
  target_actor_id uuid,
  target_candidate_count integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare revision_row public.pachanga_competition_venue_allocation_revisions%rowtype;
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare item_snapshot jsonb;
declare selected_assigned integer;
declare selected_unassigned integer;
declare selected_hard integer;
declare selected_locked integer;
declare selected_manual integer;
declare selected_recurring integer;
declare selected_score numeric(6,3);
declare selected_status text;
declare selected_result_checksum text;
declare quality_checksum text;
declare quality_explanation jsonb;
begin
  select * into revision_row
  from public.pachanga_competition_venue_allocation_revisions rows
  where rows.id = target_revision_id for update;
  select * into plan_row
  from public.pachanga_competition_venue_allocation_plans rows
  where rows.id = revision_row.allocation_plan_id for update;
  select
    count(*) filter (where items.assignment_status in ('PROPOSED','LOCKED','HELD','PUBLISHED')),
    count(*) filter (where items.assignment_status in ('UNASSIGNED','CONFLICT','TBD')),
    count(*) filter (where cardinality(items.conflict_codes) > 0),
    count(*) filter (where items.assignment_status = 'LOCKED'),
    count(*) filter (where items.manual_override),
    count(*) filter (where items.source_kind = 'RECURRING_OCCURRENCE')
  into selected_assigned, selected_unassigned, selected_hard,
    selected_locked, selected_manual, selected_recurring
  from public.pachanga_competition_venue_allocation_items items
  where items.allocation_revision_id = target_revision_id;
  if not plan_row.venue_required then selected_hard := 0; end if;
  selected_score := greatest(0, least(100,
    100
    - case when selected_assigned + selected_unassigned = 0 then 100
      else selected_unassigned::numeric * 60 / (selected_assigned + selected_unassigned) end
    - selected_hard * 10
    + least(selected_recurring, 10)
  ));
  selected_status := case
    when selected_hard > 0 and selected_assigned = 0 then 'conflicted'
    when selected_unassigned > 0 then 'partial'
    else 'generated' end;
  select coalesce(jsonb_agg(jsonb_build_object(
    'canonicalMatchId', items.canonical_match_id,
    'scheduledStart', items.scheduled_start, 'scheduledEnd', items.scheduled_end,
    'venueId', items.venue_id, 'pitchId', items.pitch_id,
    'sourceKind', items.source_kind, 'sourceId', items.source_id,
    'status', items.assignment_status, 'conflicts', items.conflict_codes,
    'warnings', items.warning_codes, 'manualOverride', items.manual_override
  ) order by items.scheduled_start, items.canonical_match_id), '[]'::jsonb)
  into item_snapshot
  from public.pachanga_competition_venue_allocation_items items
  where items.allocation_revision_id = target_revision_id;
  selected_result_checksum := private.pachanga_venue_allocation_json_checksum_v1(item_snapshot);
  quality_explanation := jsonb_build_object(
    'assignedMatches', selected_assigned,
    'unassignedMatches', selected_unassigned,
    'hardViolations', selected_hard,
    'recurringBlockUsage', selected_recurring,
    'manualOverrideCount', selected_manual,
    'lockedAssignments', selected_locked,
    'scoreFormula', '100 - unassignedShare*60 - hardViolations*10 + recurringUsage(max10)',
    'privateDistanceUsed', false
  );
  quality_checksum := private.pachanga_venue_allocation_json_checksum_v1(quality_explanation);
  update public.pachanga_competition_venue_allocation_revisions rows set
    result_checksum = selected_result_checksum,
    candidate_count = coalesce(target_candidate_count, rows.candidate_count),
    assigned_count = selected_assigned,
    unassigned_count = selected_unassigned,
    hard_violation_count = selected_hard,
    quality_score = selected_score,
    status = selected_status,
    validation_status = 'PENDING'
  where rows.id = target_revision_id;
  insert into private.pachanga_competition_venue_allocation_quality_snapshots(
    allocation_revision_id, hard_violations, unassigned_matches,
    assigned_matches, recurring_block_usage, manual_override_count,
    locked_assignments, conflicts, warnings, explanation, score, checksum,
    server_sequence
  ) values (
    target_revision_id, selected_hard, selected_unassigned, selected_assigned,
    selected_recurring, selected_manual, selected_locked,
    coalesce((select jsonb_agg(jsonb_build_object(
      'code', conflicts.conflict_code,
      'outcome', conflicts.outcome_code,
      'explanation', conflicts.public_explanation
    ) order by conflicts.server_sequence, conflicts.id)
    from private.pachanga_competition_venue_allocation_conflicts conflicts
    where conflicts.allocation_revision_id = target_revision_id
      and conflicts.status = 'active'), '[]'::jsonb),
    '[]'::jsonb, quality_explanation, selected_score, quality_checksum,
    nextval('private.pachanga_venue_sequence')
  ) on conflict (allocation_revision_id) do update set
    hard_violations = excluded.hard_violations,
    unassigned_matches = excluded.unassigned_matches,
    assigned_matches = excluded.assigned_matches,
    recurring_block_usage = excluded.recurring_block_usage,
    manual_override_count = excluded.manual_override_count,
    locked_assignments = excluded.locked_assignments,
    conflicts = excluded.conflicts,
    warnings = excluded.warnings,
    explanation = excluded.explanation,
    score = excluded.score,
    checksum = excluded.checksum,
    server_sequence = excluded.server_sequence,
    generated_at = clock_timestamp();
  update public.pachanga_competition_venue_allocation_plans rows set
    current_revision_id = target_revision_id,
    status = selected_status,
    revision = rows.revision + 1,
    server_sequence = nextval('private.pachanga_venue_sequence'),
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where rows.id = revision_row.allocation_plan_id;
  return jsonb_build_object(
    'revisionId', target_revision_id, 'status', selected_status,
    'resultChecksum', selected_result_checksum, 'assignedMatches', selected_assigned,
    'unassignedMatches', selected_unassigned, 'hardViolations', selected_hard,
    'qualityScore', selected_score
  );
end;
$$;

revoke all on function private.pachanga_venue_allocation_finalize_revision_v1(uuid, uuid, integer)
  from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_generate_v1(
  target_plan_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_seed text,
  target_search_budget integer,
  target_revision_kind text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare freeze_row private.pachanga_competition_venue_allocation_input_freezes%rowtype;
declare previous_revision public.pachanga_competition_venue_allocation_revisions%rowtype;
declare new_revision_id uuid := gen_random_uuid();
declare new_version integer;
declare constraint_snapshot jsonb;
declare lock_snapshot jsonb;
declare match_entry record;
declare binding_row public.pachanga_venue_match_bindings%rowtype;
declare lock_row public.pachanga_competition_venue_allocation_locks%rowtype;
declare candidate record;
declare evaluated_candidates integer := 0;
declare item_id uuid;
declare conflict_code text;
declare conflict_outcome text;
declare conflict_explanation text;
declare conflict_fingerprint text;
declare target_modality text;
declare recurring_occurrence_id uuid;
declare selected_source_kind text;
declare selected_source_id uuid;
declare final_snapshot jsonb;
begin
  if length(trim(coalesce(target_seed, ''))) not between 1 and 160 then
    raise exception 'VENUE_ALLOCATION_SEED_INVALID' using errcode = '22023';
  end if;
  if target_search_budget not between 1 and 1000000 then
    raise exception 'VENUE_ALLOCATION_SEARCH_BUDGET_INVALID' using errcode = '22023';
  end if;
  lock table public.pachanga_competition_schedule_items in share mode;
  lock table public.pachanga_competition_match_contexts in share mode;
  lock table public.pachanga_competition_venue_pool_memberships in share mode;
  lock table public.pachanga_competition_venue_authorizations in share mode;
  lock table public.pachanga_venue_availability_templates in share mode;
  lock table public.pachanga_venue_availability_exceptions in share mode;
  lock table public.pachanga_venue_pitch_claims in share mode;
  lock table public.pachanga_venue_reservations in share mode;
  lock table public.pachanga_venue_match_bindings in share mode;
  select * into plan_row from public.pachanga_competition_venue_allocation_plans rows
  where rows.id = target_plan_id for update;
  if not found or plan_row.current_input_freeze_id is null then
    raise exception 'VENUE_ALLOCATION_INPUT_FREEZE_REQUIRED' using errcode = '22023';
  end if;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'VENUE_ALLOCATION_PLAN_IMMUTABLE' using errcode = '22023';
  end if;
  select * into freeze_row
  from private.pachanga_competition_venue_allocation_input_freezes rows
  where rows.id = plan_row.current_input_freeze_id;
  if private.pachanga_venue_allocation_live_input_checksum_v1(target_plan_id)
     <> freeze_row.input_checksum then
    update public.pachanga_competition_venue_allocation_plans rows set
      status = 'stale', revision = rows.revision + 1,
      server_sequence = nextval('private.pachanga_venue_sequence'),
      updated_by = target_actor_id, updated_at = clock_timestamp()
    where rows.id = target_plan_id;
    raise exception 'VENUE_ALLOCATION_INPUT_STALE' using errcode = '40001';
  end if;
  select * into previous_revision
  from public.pachanga_competition_venue_allocation_revisions rows
  where rows.id = plan_row.current_revision_id;
  new_version := coalesce((select max(rows.version) + 1
    from public.pachanga_competition_venue_allocation_revisions rows
    where rows.allocation_plan_id = target_plan_id), 1);
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rows.id, 'kind', rows.constraint_kind, 'code', rows.constraint_code,
    'scopeKind', rows.scope_kind, 'scopeId', rows.scope_id,
    'weight', rows.weight, 'parameters', rows.parameters, 'revision', rows.revision
  ) order by rows.server_sequence, rows.id), '[]'::jsonb)
  into constraint_snapshot
  from public.pachanga_competition_venue_allocation_constraints rows
  where rows.allocation_plan_id = target_plan_id and rows.status = 'active';
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rows.id, 'type', rows.lock_type, 'canonicalMatchId', rows.canonical_match_id,
    'roundId', rows.round_id, 'venueId', rows.venue_id, 'pitchId', rows.pitch_id,
    'recurringOccurrenceId', rows.recurring_occurrence_id, 'revision', rows.revision
  ) order by rows.server_sequence, rows.id), '[]'::jsonb)
  into lock_snapshot
  from public.pachanga_competition_venue_allocation_locks rows
  where rows.allocation_plan_id = target_plan_id and rows.status = 'active';
  insert into public.pachanga_competition_venue_allocation_revisions(
    id, allocation_plan_id, input_freeze_id, version, revision_kind, mode,
    status, algorithm_version, seed, input_checksum, result_checksum,
    constraint_checksum, lock_checksum, search_budget, operation_id,
    generated_by, supersedes_revision_id
  ) values (
    new_revision_id, target_plan_id, freeze_row.id, new_version,
    target_revision_kind, plan_row.mode, 'generated',
    'venue-allocation-greedy-v1', trim(target_seed), freeze_row.input_checksum,
    repeat('0', 64),
    private.pachanga_venue_allocation_json_checksum_v1(constraint_snapshot),
    private.pachanga_venue_allocation_json_checksum_v1(lock_snapshot),
    target_search_budget, target_operation_id, target_actor_id, previous_revision.id
  );
  target_modality := private.pachanga_venue_allocation_modality_v1(freeze_row.rule_snapshot);
  for match_entry in
    select * from jsonb_to_recordset(freeze_row.match_snapshot) as matches(
      "scheduleItemId" uuid, "canonicalMatchId" uuid,
      "competitionMatchContextId" uuid, "roundId" uuid,
      "homeEntryId" uuid, "awayEntryId" uuid,
      "scheduledStart" timestamptz, "scheduledEnd" timestamptz,
      "timezone" text, "scheduleItemRevision" bigint,
      "contextRevision" bigint, "contextSequence" bigint
    ) order by "scheduledStart", "canonicalMatchId"
  loop
    item_id := private.pachanga_venue_deterministic_uuid_v1(
      'wave9b:item:' || new_revision_id::text || ':' || match_entry."canonicalMatchId"::text
    );
    select * into binding_row
    from public.pachanga_venue_match_bindings rows
    where rows.canonical_match_id = match_entry."canonicalMatchId"
      and rows.status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED')
    order by rows.server_sequence desc, rows.id desc limit 1;
    if found then
      insert into public.pachanga_competition_venue_allocation_items(
        id, allocation_plan_id, allocation_revision_id, schedule_item_id,
        canonical_match_id, competition_match_context_id, round_id,
        home_entry_id, away_entry_id, scheduled_start, scheduled_end, timezone,
        venue_id, pitch_id, source_kind, source_id, assignment_status,
        reservation_id, binding_id
      ) values (
        item_id, target_plan_id, new_revision_id, match_entry."scheduleItemId",
        match_entry."canonicalMatchId", match_entry."competitionMatchContextId",
        match_entry."roundId", match_entry."homeEntryId", match_entry."awayEntryId",
        match_entry."scheduledStart", match_entry."scheduledEnd", match_entry."timezone",
        binding_row.venue_id, binding_row.pitch_id, 'EXISTING_BINDING', binding_row.id,
        'LOCKED', binding_row.reservation_id, binding_row.id
      );
      continue;
    end if;

    select * into lock_row
    from public.pachanga_competition_venue_allocation_locks rows
    where rows.allocation_plan_id = target_plan_id and rows.status = 'active'
      and (rows.canonical_match_id = match_entry."canonicalMatchId"
        or rows.round_id = match_entry."roundId")
    order by case when rows.canonical_match_id is not null then 0 else 1 end,
      rows.server_sequence, rows.id limit 1;

    candidate := null;
    conflict_code := null;
    conflict_outcome := null;
    conflict_explanation := null;
    if evaluated_candidates >= target_search_budget then
      conflict_code := 'SEARCH_BUDGET_EXHAUSTED';
      conflict_outcome := 'VENUE_ALLOCATION_SEARCH_BUDGET_EXHAUSTED';
      conflict_explanation := 'El presupuesto determinista terminó antes de encontrar un campo válido.';
    else
      select
        memberships.id membership_id,
        memberships.venue_id,
        memberships.pitch_id,
        authorizations.source_kind authorization_source,
        authorizations.recurring_series_id,
        authorizations.reservation_id authorization_reservation_id,
        occurrences.id recurring_occurrence_id
      into candidate
      from public.pachanga_competition_venue_pool_memberships memberships
      join public.pachanga_competition_venue_authorizations authorizations
        on authorizations.id = memberships.authorization_id
      join public.pachanga_venue_pitches pitches on pitches.id = memberships.pitch_id
      join public.pachanga_club_venues venues on venues.id = memberships.venue_id
      left join public.pachanga_venue_recurring_occurrences occurrences
        on occurrences.pitch_id = memberships.pitch_id
       and occurrences.starts_at = match_entry."scheduledStart"
       and occurrences.ends_at = match_entry."scheduledEnd"
       and occurrences.status in ('planned', 'held', 'reserved')
      where memberships.pool_id = plan_row.venue_pool_id
        and memberships.status = 'active' and authorizations.status = 'active'
        and memberships.modality = target_modality
        and (memberships.capacity_limit is null
          or memberships.consumed_count < memberships.capacity_limit)
        and (match_entry."scheduledStart" at time zone venues.timezone)::date
          between authorizations.valid_from and authorizations.valid_until
        and extract(isodow from match_entry."scheduledStart" at time zone venues.timezone)::smallint
          = any(authorizations.allowed_weekdays)
        and (match_entry."scheduledStart" at time zone venues.timezone)::time
          >= authorizations.local_start_time
        and (match_entry."scheduledEnd" at time zone venues.timezone)::time
          <= authorizations.local_end_time
        and private.pachanga_venue_slot_is_available_v1(
          memberships.pitch_id, match_entry."scheduledStart",
          match_entry."scheduledEnd", target_modality
        )
        and not exists (
          select 1
          from public.pachanga_competition_venue_allocation_items allocated
          join public.pachanga_venue_pitches allocated_pitch
            on allocated_pitch.id = allocated.pitch_id
          where allocated.allocation_revision_id = new_revision_id
            and allocated_pitch.conflict_scope_id = pitches.conflict_scope_id
            and tstzrange(allocated.scheduled_start, allocated.scheduled_end, '[)')
              && tstzrange(match_entry."scheduledStart", match_entry."scheduledEnd", '[)')
        )
        and (
          lock_row.id is null
          or (lock_row.lock_type in ('MATCH_TO_PITCH', 'FINAL_TO_PITCH')
            and memberships.pitch_id = lock_row.pitch_id)
          or (lock_row.lock_type in ('MATCH_TO_VENUE', 'ROUND_TO_VENUE')
            and memberships.venue_id = lock_row.venue_id)
          or (lock_row.lock_type = 'MATCH_TO_RECURRING_OCCURRENCE'
            and occurrences.id = lock_row.recurring_occurrence_id)
        )
      order by
        case when occurrences.id is not null then 0 else 1 end,
        memberships.priority,
        (select count(*) from public.pachanga_competition_venue_allocation_items used
          where used.allocation_revision_id = new_revision_id
            and used.pitch_id = memberships.pitch_id),
        encode(extensions.digest(convert_to(trim(target_seed) || ':' || memberships.pitch_id::text, 'UTF8'), 'sha256'), 'hex'),
        memberships.pitch_id
      limit 1;
      evaluated_candidates := evaluated_candidates + 1;
      if candidate.membership_id is null then
        conflict_code := case when lock_row.id is not null then 'MANUAL_LOCK' else 'PITCH_AVAILABLE' end;
        conflict_outcome := case when lock_row.id is not null
          then 'VENUE_ALLOCATION_UNSATISFIABLE' else 'VENUE_ALLOCATION_PARTIAL' end;
        conflict_explanation := case when lock_row.id is not null
          then 'El lock activo contradice la disponibilidad o autorización del pool.'
          else 'No existe un Pitch autorizado y disponible para el horario fijo.' end;
      end if;
    end if;

    if candidate.membership_id is not null then
      recurring_occurrence_id := candidate.recurring_occurrence_id;
      selected_source_kind := case
        when recurring_occurrence_id is not null then 'RECURRING_OCCURRENCE'
        when candidate.authorization_source = 'CONFIRMED_RESERVATION'
          then 'CONFIRMED_RESERVATION'
        when candidate.authorization_source = 'AVAILABILITY_AGREEMENT'
          then 'PREAUTHORIZED_AVAILABILITY'
        else 'AUTHORIZED_PITCH' end;
      selected_source_id := coalesce(
        recurring_occurrence_id,
        candidate.authorization_reservation_id,
        candidate.membership_id
      );
      insert into public.pachanga_competition_venue_allocation_items(
        id, allocation_plan_id, allocation_revision_id, schedule_item_id,
        canonical_match_id, competition_match_context_id, round_id,
        home_entry_id, away_entry_id, scheduled_start, scheduled_end, timezone,
        venue_id, pitch_id, pool_membership_id, source_kind, source_id,
        assignment_status
      ) values (
        item_id, target_plan_id, new_revision_id, match_entry."scheduleItemId",
        match_entry."canonicalMatchId", match_entry."competitionMatchContextId",
        match_entry."roundId", match_entry."homeEntryId", match_entry."awayEntryId",
        match_entry."scheduledStart", match_entry."scheduledEnd", match_entry."timezone",
        candidate.venue_id, candidate.pitch_id, candidate.membership_id,
        selected_source_kind, selected_source_id,
        case when lock_row.id is not null then 'LOCKED' else 'PROPOSED' end
      );
    else
      insert into public.pachanga_competition_venue_allocation_items(
        id, allocation_plan_id, allocation_revision_id, schedule_item_id,
        canonical_match_id, competition_match_context_id, round_id,
        home_entry_id, away_entry_id, scheduled_start, scheduled_end, timezone,
        assignment_status, conflict_codes
      ) values (
        item_id, target_plan_id, new_revision_id, match_entry."scheduleItemId",
        match_entry."canonicalMatchId", match_entry."competitionMatchContextId",
        match_entry."roundId", match_entry."homeEntryId", match_entry."awayEntryId",
        match_entry."scheduledStart", match_entry."scheduledEnd", match_entry."timezone",
        case when plan_row.venue_required then 'CONFLICT' else 'TBD' end,
        case when plan_row.venue_required then array[conflict_code] else '{}'::text[] end
      );
      if plan_row.venue_required then
        conflict_fingerprint := private.pachanga_venue_allocation_json_checksum_v1(
          jsonb_build_object('revisionId', new_revision_id,
            'matchId', match_entry."canonicalMatchId", 'code', conflict_code)
        );
        insert into private.pachanga_competition_venue_allocation_conflicts(
          allocation_plan_id, allocation_revision_id, allocation_item_id,
          canonical_match_id, conflict_code, outcome_code, severity, fingerprint,
          public_explanation, private_detail, server_sequence
        ) values (
          target_plan_id, new_revision_id, item_id,
          match_entry."canonicalMatchId", conflict_code, conflict_outcome,
          'HARD', conflict_fingerprint, conflict_explanation,
          jsonb_build_object('lockId', lock_row.id, 'searchBudget', target_search_budget),
          nextval('private.pachanga_venue_sequence')
        );
      end if;
    end if;
  end loop;
  perform private.pachanga_venue_allocation_finalize_revision_v1(
    new_revision_id, target_actor_id, evaluated_candidates
  );
  select coalesce(jsonb_agg(jsonb_build_object(
    'matchId', items.canonical_match_id, 'pitchId', items.pitch_id,
    'status', items.assignment_status
  ) order by items.canonical_match_id), '[]'::jsonb)
  into final_snapshot from public.pachanga_competition_venue_allocation_items items
  where items.allocation_revision_id = new_revision_id;
  insert into private.pachanga_competition_venue_allocation_diffs(
    allocation_plan_id, from_revision_id, to_revision_id, diff, checksum, server_sequence
  ) values (
    target_plan_id, previous_revision.id, new_revision_id,
    jsonb_build_object('kind', target_revision_kind, 'items', final_snapshot),
    private.pachanga_venue_allocation_json_checksum_v1(final_snapshot),
    nextval('private.pachanga_venue_sequence')
  );
  return new_revision_id;
end;
$$;

revoke all on function private.pachanga_venue_allocation_generate_v1(
  uuid, uuid, uuid, text, integer, text
) from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_clone_revision_v1(
  target_plan_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_revision_kind text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare current_revision public.pachanga_competition_venue_allocation_revisions%rowtype;
declare new_revision_id uuid := gen_random_uuid();
declare next_version integer;
begin
  select * into plan_row from public.pachanga_competition_venue_allocation_plans rows
  where rows.id = target_plan_id for update;
  if not found or plan_row.current_revision_id is null then
    raise exception 'VENUE_ALLOCATION_REVISION_REQUIRED' using errcode = '22023';
  end if;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'VENUE_ALLOCATION_PLAN_IMMUTABLE' using errcode = '22023';
  end if;
  select * into current_revision
  from public.pachanga_competition_venue_allocation_revisions rows
  where rows.id = plan_row.current_revision_id;
  next_version := current_revision.version + 1;
  insert into public.pachanga_competition_venue_allocation_revisions(
    id, allocation_plan_id, input_freeze_id, version, revision_kind, mode,
    status, algorithm_version, seed, input_checksum, result_checksum,
    constraint_checksum, lock_checksum, search_budget, candidate_count,
    operation_id, generated_by, supersedes_revision_id
  ) values (
    new_revision_id, target_plan_id, current_revision.input_freeze_id,
    next_version, target_revision_kind, current_revision.mode, 'generated',
    current_revision.algorithm_version, current_revision.seed,
    current_revision.input_checksum, repeat('0', 64),
    current_revision.constraint_checksum, current_revision.lock_checksum,
    current_revision.search_budget, current_revision.candidate_count,
    target_operation_id, target_actor_id, current_revision.id
  );
  insert into public.pachanga_competition_venue_allocation_items(
    id, allocation_plan_id, allocation_revision_id, schedule_item_id,
    canonical_match_id, competition_match_context_id, round_id,
    home_entry_id, away_entry_id, scheduled_start, scheduled_end, timezone,
    venue_id, pitch_id, pool_membership_id, source_kind, source_id,
    assignment_status, conflict_codes, warning_codes, manual_override,
    hold_id, reservation_id, binding_id
  ) select
    private.pachanga_venue_deterministic_uuid_v1(
      'wave9b:item:' || new_revision_id::text || ':' || items.canonical_match_id::text
    ), items.allocation_plan_id, new_revision_id, items.schedule_item_id,
    items.canonical_match_id, items.competition_match_context_id, items.round_id,
    items.home_entry_id, items.away_entry_id, items.scheduled_start,
    items.scheduled_end, items.timezone, items.venue_id, items.pitch_id,
    items.pool_membership_id, items.source_kind, items.source_id,
    case when items.assignment_status in ('HELD', 'PUBLISHED') then 'PROPOSED'
      else items.assignment_status end,
    items.conflict_codes, items.warning_codes, items.manual_override,
    null, items.reservation_id, items.binding_id
  from public.pachanga_competition_venue_allocation_items items
  where items.allocation_revision_id = current_revision.id;
  return new_revision_id;
end;
$$;

revoke all on function private.pachanga_venue_allocation_clone_revision_v1(
  uuid, uuid, uuid, text
) from public, anon, authenticated;

create or replace function private.pachanga_venue_allocation_allowed_payload_v1(
  target_action text,
  target_payload jsonb
)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare allowed text[];
begin
  allowed := case target_action
    when 'recurring_series.create' then array[
      'pitchId','purpose','teamId','competitionId','modality','frequency','timezone',
      'weekday','localStartTime','localOffsetMinutes','durationMinutes','bufferMinutes',
      'startDate','endDate','reasonCode'
    ]
    when 'recurring_series.update' then array[
      'pitchId','modality','frequency','timezone','weekday','localStartTime',
      'localOffsetMinutes','durationMinutes','bufferMinutes','startDate','endDate','reasonCode'
    ]
    when 'recurring_series.validate' then array['reasonCode']
    when 'recurring_series.offer' then array['reasonCode']
    when 'recurring_series.accept' then array['reasonCode']
    when 'recurring_series.publish' then array['reasonCode']
    when 'recurring_series.pause' then array['reasonCode']
    when 'recurring_series.resume' then array['reasonCode']
    when 'recurring_series.complete' then array['reasonCode']
    when 'recurring_series.end' then array['reasonCode']
    when 'recurring_series.cancel' then array['reasonCode']
    when 'recurring_series.materialize' then array['reasonCode']
    when 'venue_pool.create' then array['competitionId','editionId','name','visibility','reasonCode']
    when 'venue_pool.update' then array['name','visibility','reasonCode']
    when 'venue_pool.offer' then array[
      'ownerClubId','venueId','pitchIds','modalities','validFrom','validUntil',
      'allowedWeekdays','localStartTime','localEndTime','capacityPerSlot','priority',
      'visibility','sourceKind','recurringSeriesId','reservationId','expiresAt','reasonCode'
    ]
    when 'venue_pool.accept' then array['reasonCode']
    when 'venue_pool.activate' then array['reasonCode']
    when 'venue_pool.revoke' then array['reasonCode']
    when 'allocation_plan.create' then array[
      'competitionId','editionId','stageId','schedulePlanId','scheduleRevisionId',
      'ruleRevisionId','venuePoolId','mode','venueRequired','reasonCode'
    ]
    when 'allocation_inputs.freeze' then array['reasonCode']
    when 'allocation_constraint.create' then array[
      'constraintKind','constraintCode','scopeKind','scopeId','weight','parameters','reason'
    ]
    when 'allocation_constraint.update' then array['constraintId','weight','parameters','reason']
    when 'allocation_constraint.remove' then array['constraintId','reasonCode']
    when 'allocation.generate' then array['seed','searchBudget','reasonCode']
    when 'allocation.regenerate' then array['seed','searchBudget','reasonCode']
    when 'allocation.item.assign' then array['canonicalMatchId','pitchId','reasonCode']
    when 'allocation.item.move' then array['canonicalMatchId','pitchId','reasonCode']
    when 'allocation.item.swap' then array['canonicalMatchId','otherCanonicalMatchId','reasonCode']
    when 'allocation.item.remove' then array['canonicalMatchId','reasonCode']
    when 'allocation.lock.create' then array[
      'lockType','canonicalMatchId','roundId','venueId','pitchId',
      'recurringOccurrenceId','reason'
    ]
    when 'allocation.lock.remove' then array['lockId','reasonCode']
    when 'allocation.hold' then array['expiresInMinutes','reasonCode']
    when 'allocation.validate' then array['reasonCode']
    when 'allocation.publish' then array['reasonCode']
    when 'allocation.cancel' then array['reasonCode']
    else null end;
  if allowed is null or jsonb_typeof(coalesce(target_payload, '{}'::jsonb)) <> 'object' then
    return false;
  end if;
  return not exists (
    select 1 from jsonb_object_keys(coalesce(target_payload, '{}'::jsonb)) keys(key)
    where not (keys.key = any(allowed))
  );
end;
$$;

revoke all on function private.pachanga_venue_allocation_allowed_payload_v1(text, jsonb)
  from public, anon, authenticated;

create or replace function public.command_pachanga_competition_venue_allocation_v1(
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
declare normalized_action text := lower(trim(coalesce(action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare existing_receipt private.pachanga_venue_operation_receipts%rowtype;
declare selected_sequence bigint;
declare confirmed_revision bigint;
declare confirmed_aggregate_id uuid;
declare aggregate_type text;
declare event_venue_id uuid;
declare event_pitch_id uuid;
declare event_match_id uuid;
declare snapshot jsonb := '{}'::jsonb;
declare invalidations jsonb := '[]'::jsonb;
declare reason_code text := left(coalesce(nullif(trim(command_payload ->> 'reasonCode'), ''), 'USER_ACTION'), 120);
declare series_row public.pachanga_venue_recurring_series%rowtype;
declare series_revision private.pachanga_venue_recurring_series_revisions%rowtype;
declare venue_row public.pachanga_club_venues%rowtype;
declare pitch_row public.pachanga_venue_pitches%rowtype;
declare pool_row public.pachanga_competition_venue_pools%rowtype;
declare pool_revision private.pachanga_competition_venue_pool_revisions%rowtype;
declare authorization_row public.pachanga_competition_venue_authorizations%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare plan_row public.pachanga_competition_venue_allocation_plans%rowtype;
declare constraint_row public.pachanga_competition_venue_allocation_constraints%rowtype;
declare lock_row public.pachanga_competition_venue_allocation_locks%rowtype;
declare new_revision_id uuid;
declare target_item public.pachanga_competition_venue_allocation_items%rowtype;
declare other_item public.pachanga_competition_venue_allocation_items%rowtype;
declare target_membership public.pachanga_competition_venue_pool_memberships%rowtype;
declare selected_status text;
declare selected_count integer;
declare next_version integer;
declare selected_checksum text;
declare selected_duration_days integer;
declare target_pitch_ids uuid[];
declare target_modalities text[];
declare target_mode text;
declare replay jsonb;
begin
  if actor_id is null then
    raise exception 'VENUE_ALLOCATION_AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if operation_id is null or expected_revision is null or expected_revision < 0
     or not private.pachanga_venue_allocation_allowed_payload_v1(normalized_action, payload) then
    raise exception 'VENUE_ALLOCATION_COMMAND_INVALID' using errcode = '22023';
  end if;
  if normalized_action in ('allocation_constraint.create','allocation_constraint.update')
     and payload ? 'parameters'
     and (
       jsonb_typeof(payload -> 'parameters') <> 'object'
       or not private.pachanga_venue_allocation_parameters_safe_v1(payload -> 'parameters')
     ) then
    raise exception 'VENUE_ALLOCATION_CONSTRAINT_PARAMETERS_INVALID' using errcode = '22023';
  end if;
  if normalized_action in (
    'recurring_series.create', 'venue_pool.create', 'allocation_plan.create'
  ) and (aggregate_id is not null or expected_revision <> 0) then
    raise exception 'VENUE_ALLOCATION_CREATE_AGGREGATE_INVALID' using errcode = '22023';
  end if;
  if normalized_action not in (
    'recurring_series.create', 'venue_pool.create', 'allocation_plan.create'
  ) and aggregate_id is null then
    raise exception 'VENUE_ALLOCATION_AGGREGATE_REQUIRED' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 90230));
  request_hash := private.pachanga_venue_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  select * into existing_receipt
  from private.pachanga_venue_operation_receipts rows
  where rows.operation_id = command_pachanga_competition_venue_allocation_v1.operation_id;
  if found then
    if existing_receipt.request_hash <> request_hash or existing_receipt.actor_id <> actor_id then
      raise exception 'VENUE_ALLOCATION_OPERATION_ID_REUSED' using errcode = '23505';
    end if;
    return existing_receipt.response;
  end if;

  if normalized_action = 'recurring_series.create' then
    perform private.pachanga_venue_allocation_assert_flags_v1('recurring');
    select pitches.* into pitch_row from public.pachanga_venue_pitches pitches
    where pitches.id = nullif(payload ->> 'pitchId', '')::uuid;
    select venues.* into venue_row from public.pachanga_club_venues venues
    where venues.id = pitch_row.venue_id;
    if not found or pitch_row.status <> 'ACTIVE' or venue_row.lifecycle <> 'ACTIVE' then
      raise exception 'VENUE_RECURRING_PITCH_NOT_ACTIVE' using errcode = '22023';
    end if;
    if not private.pachanga_club_can_v1(venue_row.club_id, actor_id, 'reservation_manage') then
      raise exception 'VENUE_RECURRING_CLUB_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    selected_duration_days := (payload ->> 'endDate')::date - (payload ->> 'startDate')::date;
    if selected_duration_days < 0 or selected_duration_days > (case
      when private.pachanga_platform_role_for_user_v1(actor_id) in ('platform_owner','platform_admin')
      then 728 else 364 end) then
      raise exception 'VENUE_RECURRING_HORIZON_INVALID' using errcode = '22023';
    end if;
    confirmed_aggregate_id := gen_random_uuid();
    selected_sequence := nextval('private.pachanga_venue_sequence');
    insert into public.pachanga_venue_recurring_series(
      id, venue_id, pitch_id, owner_club_id, purpose, team_id, competition_id,
      modality, frequency, timezone, weekday, local_start_time,
      local_offset_minutes, duration_minutes, buffer_minutes, start_date,
      end_date, operation_id, created_by, updated_by, server_sequence
    ) values (
      confirmed_aggregate_id, venue_row.id, pitch_row.id, venue_row.club_id,
      upper(payload ->> 'purpose'), nullif(payload ->> 'teamId','')::uuid,
      nullif(payload ->> 'competitionId','')::uuid, upper(payload ->> 'modality'),
      upper(payload ->> 'frequency'), payload ->> 'timezone',
      (payload ->> 'weekday')::smallint, (payload ->> 'localStartTime')::time,
      nullif(payload ->> 'localOffsetMinutes','')::integer,
      (payload ->> 'durationMinutes')::integer,
      coalesce((payload ->> 'bufferMinutes')::integer, pitch_row.buffer_minutes),
      (payload ->> 'startDate')::date, (payload ->> 'endDate')::date,
      operation_id, actor_id, actor_id, selected_sequence
    ) returning * into series_row;
    selected_checksum := private.pachanga_venue_allocation_json_checksum_v1(to_jsonb(series_row));
    insert into private.pachanga_venue_recurring_series_revisions(
      series_id, version, action, status, snapshot, checksum, operation_id,
      actor_id, server_sequence
    ) values (
      series_row.id, 1, normalized_action, series_row.status,
      to_jsonb(series_row), selected_checksum, operation_id, actor_id,
      nextval('private.pachanga_venue_sequence')
    ) returning * into series_revision;
    update public.pachanga_venue_recurring_series rows
    set current_revision_id = series_revision.id where rows.id = series_row.id
    returning * into series_row;
    confirmed_revision := series_row.revision;
    aggregate_type := 'recurring_series';
    event_venue_id := series_row.venue_id;
    event_pitch_id := series_row.pitch_id;
    snapshot := jsonb_build_object(
      'seriesId', series_row.id, 'status', series_row.status,
      'revision', series_row.revision, 'seriesRevisionId', series_revision.id,
      'checksum', selected_checksum
    );

  elsif normalized_action like 'recurring_series.%' then
    perform private.pachanga_venue_allocation_assert_flags_v1(
      case when normalized_action = 'recurring_series.materialize' then 'materialize' else 'recurring' end
    );
    select * into series_row from public.pachanga_venue_recurring_series rows
    where rows.id = aggregate_id for update;
    if not found then raise exception 'VENUE_RECURRING_SERIES_NOT_FOUND' using errcode = 'P0002'; end if;
    if series_row.revision <> expected_revision then
      raise exception 'VENUE_ALLOCATION_STALE_REVISION' using errcode = '40001';
    end if;
    if normalized_action in ('recurring_series.update','recurring_series.validate',
      'recurring_series.offer','recurring_series.publish','recurring_series.pause',
      'recurring_series.resume','recurring_series.complete','recurring_series.end',
      'recurring_series.cancel','recurring_series.materialize')
      and not private.pachanga_club_can_v1(series_row.owner_club_id, actor_id, 'reservation_manage')
      and not (series_row.competition_id is not null and private.pachanga_competition_venue_can_v1(
        series_row.competition_id, actor_id, 'manage')) then
      raise exception 'VENUE_RECURRING_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    if normalized_action = 'recurring_series.accept' then
      if series_row.team_id is not null and not exists (
        select 1 from public.pachanga_group_members members
        where members.group_id = series_row.team_id and members.user_id = actor_id
          and members.role in ('owner','admin')
      ) and not private.pachanga_club_can_v1(series_row.owner_club_id, actor_id, 'reservation_manage') then
        raise exception 'VENUE_RECURRING_ACCEPT_AUTHORITY_REQUIRED' using errcode = '42501';
      end if;
      if series_row.competition_id is not null and not private.pachanga_competition_venue_can_v1(
        series_row.competition_id, actor_id, 'manage') then
        raise exception 'VENUE_RECURRING_ACCEPT_AUTHORITY_REQUIRED' using errcode = '42501';
      end if;
    end if;
    if normalized_action in (
      'recurring_series.validate', 'recurring_series.accept',
      'recurring_series.publish', 'recurring_series.resume',
      'recurring_series.materialize'
    ) then
      perform pg_advisory_xact_lock(hashtextextended(
        'pachanga:venue-recurring:' || series_row.pitch_id::text, 0
      ));
      if private.pachanga_venue_recurring_conflict_v1(series_row.id) then
        raise exception 'VENUE_RECURRING_SERIES_CONFLICT' using errcode = '23P01';
      end if;
    end if;
    if normalized_action = 'recurring_series.update' then
      if series_row.status in ('completed','ended','cancelled') then
        raise exception 'VENUE_RECURRING_SERIES_IMMUTABLE' using errcode = '22023';
      end if;
      if exists (
        select 1 from public.pachanga_venue_recurring_occurrences occurrences
        where occurrences.series_id = series_row.id and occurrences.starts_at > clock_timestamp()
          and occurrences.status in ('reserved','consumed')
      ) and (
        payload ? 'pitchId' or payload ? 'frequency' or payload ? 'weekday'
        or payload ? 'localStartTime' or payload ? 'durationMinutes'
      ) then
        raise exception 'VENUE_RECURRING_FUTURE_RESERVATION_REQUIRES_EXPLICIT_CHANGE' using errcode = '40001';
      end if;
      select pitches.* into pitch_row from public.pachanga_venue_pitches pitches
      where pitches.id = coalesce(nullif(payload ->> 'pitchId','')::uuid, series_row.pitch_id);
      if not found or pitch_row.venue_id <> series_row.venue_id or pitch_row.status <> 'ACTIVE' then
        raise exception 'VENUE_RECURRING_PITCH_INVALID' using errcode = '22023';
      end if;
      perform pg_advisory_xact_lock(hashtextextended(
        'pachanga:venue-recurring:' || pitch_row.id::text, 0
      ));
      selected_duration_days := coalesce((payload ->> 'endDate')::date, series_row.end_date)
        - coalesce((payload ->> 'startDate')::date, series_row.start_date);
      if selected_duration_days < 0 or selected_duration_days > (case
        when private.pachanga_platform_role_for_user_v1(actor_id) in ('platform_owner','platform_admin')
        then 728 else 364 end) then
        raise exception 'VENUE_RECURRING_HORIZON_INVALID' using errcode = '22023';
      end if;
      update public.pachanga_venue_recurring_occurrences occurrences set
        status = 'superseded', revision = occurrences.revision + 1,
        server_sequence = nextval('private.pachanga_venue_sequence'),
        updated_at = clock_timestamp()
      where occurrences.series_id = series_row.id and occurrences.starts_at > clock_timestamp()
        and occurrences.status in ('planned','excluded');
      update public.pachanga_venue_recurring_series rows set
        pitch_id = pitch_row.id,
        modality = coalesce(upper(nullif(payload ->> 'modality','')), rows.modality),
        frequency = coalesce(upper(nullif(payload ->> 'frequency','')), rows.frequency),
        timezone = coalesce(nullif(payload ->> 'timezone',''), rows.timezone),
        weekday = coalesce((payload ->> 'weekday')::smallint, rows.weekday),
        local_start_time = coalesce((payload ->> 'localStartTime')::time, rows.local_start_time),
        local_offset_minutes = case when payload ? 'localOffsetMinutes'
          then nullif(payload ->> 'localOffsetMinutes','')::integer else rows.local_offset_minutes end,
        duration_minutes = coalesce((payload ->> 'durationMinutes')::integer, rows.duration_minutes),
        buffer_minutes = coalesce((payload ->> 'bufferMinutes')::integer, rows.buffer_minutes),
        start_date = coalesce((payload ->> 'startDate')::date, rows.start_date),
        end_date = coalesce((payload ->> 'endDate')::date, rows.end_date),
        status = case when rows.status in ('published','paused') then rows.status else 'draft' end,
        revision = rows.revision + 1,
        server_sequence = nextval('private.pachanga_venue_sequence'),
        updated_by = actor_id, updated_at = clock_timestamp()
      where rows.id = series_row.id returning * into series_row;
      if series_row.status in ('published', 'paused')
         and private.pachanga_venue_recurring_conflict_v1(series_row.id) then
        raise exception 'VENUE_RECURRING_SERIES_CONFLICT' using errcode = '23P01';
      end if;
      next_version := coalesce((select max(rows.version)+1
        from private.pachanga_venue_recurring_series_revisions rows
        where rows.series_id = series_row.id), 1);
      selected_checksum := private.pachanga_venue_allocation_json_checksum_v1(to_jsonb(series_row));
      insert into private.pachanga_venue_recurring_series_revisions(
        series_id, version, action, status, snapshot, impact_analysis,
        checksum, operation_id, actor_id, server_sequence
      ) values (
        series_row.id, next_version, normalized_action, series_row.status,
        to_jsonb(series_row), jsonb_build_object(
          'futureOccurrencesSuperseded', true,
          'historicalOccurrencesPreserved', true,
          'futureReservationsPreserved', true
        ), selected_checksum, operation_id, actor_id,
        nextval('private.pachanga_venue_sequence')
      ) returning * into series_revision;
      update public.pachanga_venue_recurring_series rows
      set current_revision_id = series_revision.id where rows.id = series_row.id;
    elsif normalized_action = 'recurring_series.validate' then
      if series_row.status not in ('draft','validated') then
        raise exception 'VENUE_RECURRING_VALIDATE_STATE_INVALID' using errcode = '22023';
      end if;
      update public.pachanga_venue_recurring_series rows set
        status = 'validated', revision = rows.revision + 1,
        server_sequence = nextval('private.pachanga_venue_sequence'),
        updated_by = actor_id, updated_at = clock_timestamp()
      where rows.id = series_row.id returning * into series_row;
    elsif normalized_action = 'recurring_series.offer' then
      if series_row.status <> 'validated' then raise exception 'VENUE_RECURRING_OFFER_STATE_INVALID' using errcode='22023'; end if;
      update public.pachanga_venue_recurring_series rows set
        status='offered', offered_at=clock_timestamp(), revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
    elsif normalized_action = 'recurring_series.accept' then
      if series_row.status <> 'offered' then raise exception 'VENUE_RECURRING_ACCEPT_STATE_INVALID' using errcode='22023'; end if;
      update public.pachanga_venue_recurring_series rows set
        status='accepted', accepted_at=clock_timestamp(), revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
    elsif normalized_action = 'recurring_series.publish' then
      if series_row.status <> 'accepted' then raise exception 'VENUE_RECURRING_PUBLISH_STATE_INVALID' using errcode='22023'; end if;
      update public.pachanga_venue_recurring_series rows set
        status='published', published_at=clock_timestamp(), revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
    elsif normalized_action = 'recurring_series.pause' then
      if series_row.status <> 'published' then raise exception 'VENUE_RECURRING_PAUSE_STATE_INVALID' using errcode='22023'; end if;
      update public.pachanga_venue_recurring_series rows set
        status='paused', paused_at=clock_timestamp(), revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
    elsif normalized_action = 'recurring_series.resume' then
      if series_row.status <> 'paused' then raise exception 'VENUE_RECURRING_RESUME_STATE_INVALID' using errcode='22023'; end if;
      update public.pachanga_venue_recurring_series rows set
        status='published', paused_at=null, revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
    elsif normalized_action = 'recurring_series.complete' then
      if series_row.status not in ('published','paused')
         or series_row.end_date >= (clock_timestamp() at time zone series_row.timezone)::date
         or exists (
           select 1 from public.pachanga_venue_recurring_occurrences occurrences
           where occurrences.series_id=series_row.id
             and occurrences.starts_at>clock_timestamp()
             and occurrences.status in ('planned','held','reserved')
         ) then
        raise exception 'VENUE_RECURRING_COMPLETE_STATE_INVALID' using errcode='22023';
      end if;
      update public.pachanga_venue_recurring_series rows set
        status='completed', ended_at=clock_timestamp(), revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
    elsif normalized_action = 'recurring_series.end' then
      if series_row.status not in ('published','paused') then
        raise exception 'VENUE_RECURRING_END_STATE_INVALID' using errcode='22023';
      end if;
      if exists (
        select 1 from public.pachanga_venue_recurring_occurrences occurrences
        where occurrences.series_id=series_row.id and occurrences.starts_at>clock_timestamp()
          and occurrences.status in ('held','reserved')
      ) then
        raise exception 'VENUE_RECURRING_END_HAS_FUTURE_COMMITMENTS' using errcode='40001';
      end if;
      update public.pachanga_venue_recurring_series rows set
        status='ended', ended_at=clock_timestamp(), revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
      update public.pachanga_venue_recurring_occurrences occurrences set
        status='cancelled', revision=occurrences.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_at=clock_timestamp()
      where occurrences.series_id=series_row.id and occurrences.starts_at>clock_timestamp()
        and occurrences.status in ('planned','excluded');
    elsif normalized_action = 'recurring_series.cancel' then
      if series_row.status in ('completed','ended','cancelled') then raise exception 'VENUE_RECURRING_CANCEL_STATE_INVALID' using errcode='22023'; end if;
      update public.pachanga_venue_recurring_series rows set
        status='cancelled', cancelled_at=clock_timestamp(), revision=rows.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_by=actor_id,
        updated_at=clock_timestamp() where rows.id=series_row.id returning * into series_row;
      update public.pachanga_venue_recurring_occurrences occurrences set
        status='cancelled', revision=occurrences.revision+1,
        server_sequence=nextval('private.pachanga_venue_sequence'), updated_at=clock_timestamp()
      where occurrences.series_id=series_row.id and occurrences.starts_at>clock_timestamp()
        and occurrences.status in ('planned','excluded');
    elsif normalized_action = 'recurring_series.materialize' then
      selected_count := private.pachanga_venue_materialize_series_v1(series_row.id, actor_id);
      update public.pachanga_venue_recurring_series rows set
        revision=rows.revision+1, server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id, updated_at=clock_timestamp()
      where rows.id=series_row.id returning * into series_row;
    end if;
    if normalized_action <> 'recurring_series.update' then
      next_version := coalesce((select max(rows.version)+1
        from private.pachanga_venue_recurring_series_revisions rows
        where rows.series_id=series_row.id), 1);
      selected_checksum := private.pachanga_venue_allocation_json_checksum_v1(to_jsonb(series_row));
      insert into private.pachanga_venue_recurring_series_revisions(
        series_id,version,action,status,snapshot,impact_analysis,checksum,
        operation_id,actor_id,server_sequence
      ) values(
        series_row.id,next_version,normalized_action,series_row.status,to_jsonb(series_row),
        jsonb_build_object(
          'historicalOccurrencesPreserved',true,
          'futureReservationsPreserved',true,
          'materializedCount',case when normalized_action='recurring_series.materialize'
            then selected_count else null end
        ),selected_checksum,operation_id,actor_id,nextval('private.pachanga_venue_sequence')
      ) returning * into series_revision;
      update public.pachanga_venue_recurring_series rows
      set current_revision_id=series_revision.id
      where rows.id=series_row.id returning * into series_row;
    end if;
    confirmed_aggregate_id := series_row.id;
    confirmed_revision := series_row.revision;
    selected_sequence := series_row.server_sequence;
    aggregate_type := 'recurring_series';
    event_venue_id := series_row.venue_id;
    event_pitch_id := series_row.pitch_id;
    snapshot := jsonb_build_object(
      'seriesId', series_row.id, 'status', series_row.status,
      'revision', series_row.revision, 'currentRevisionId', series_row.current_revision_id,
      'materializedCount', case when normalized_action='recurring_series.materialize'
        then selected_count else null end
    );

  elsif normalized_action = 'venue_pool.create' then
    perform private.pachanga_venue_allocation_assert_flags_v1('pool');
    select * into competition_row from public.pachanga_competitions rows
    where rows.id = nullif(payload ->> 'competitionId','')::uuid;
    if not found or not private.pachanga_competition_venue_can_v1(competition_row.id,actor_id,'manage') then
      raise exception 'VENUE_POOL_AUTHORITY_REQUIRED' using errcode='42501';
    end if;
    if not exists(select 1 from public.pachanga_competition_editions editions
      where editions.id=nullif(payload->>'editionId','')::uuid and editions.competition_id=competition_row.id) then
      raise exception 'VENUE_POOL_EDITION_INVALID' using errcode='22023';
    end if;
    confirmed_aggregate_id:=gen_random_uuid();
    selected_sequence:=nextval('private.pachanga_venue_sequence');
    insert into public.pachanga_competition_venue_pools(
      id,competition_id,edition_id,organizer_kind,organizer_group_id,organizer_club_id,
      name,visibility,operation_id,created_by,updated_by,server_sequence
    ) values(
      confirmed_aggregate_id,competition_row.id,(payload->>'editionId')::uuid,
      competition_row.organizer_kind,competition_row.organizer_group_id,
      competition_row.organizer_club_id,payload->>'name',
      coalesce(payload->>'visibility','private'),operation_id,actor_id,actor_id,
      selected_sequence
    ) returning * into pool_row;
    selected_checksum:=private.pachanga_venue_allocation_json_checksum_v1(to_jsonb(pool_row));
    insert into private.pachanga_competition_venue_pool_revisions(
      pool_id,version,action,status,snapshot,checksum,operation_id,actor_id,server_sequence
    ) values(pool_row.id,1,normalized_action,pool_row.status,to_jsonb(pool_row),selected_checksum,
      operation_id,actor_id,nextval('private.pachanga_venue_sequence')) returning * into pool_revision;
    update public.pachanga_competition_venue_pools rows set current_revision_id=pool_revision.id
      where rows.id=pool_row.id returning * into pool_row;
    confirmed_revision:=pool_row.revision;
    aggregate_type:='venue_pool';
    snapshot:=jsonb_build_object('poolId',pool_row.id,'status',pool_row.status,
      'revision',pool_row.revision,'poolRevisionId',pool_revision.id,'checksum',selected_checksum);

  elsif normalized_action like 'venue_pool.%' then
    perform private.pachanga_venue_allocation_assert_flags_v1('pool');
    if normalized_action='venue_pool.accept' then
      select * into authorization_row from public.pachanga_competition_venue_authorizations rows
        where rows.id=aggregate_id for update;
      if not found then raise exception 'VENUE_POOL_AUTHORIZATION_NOT_FOUND' using errcode='P0002'; end if;
      select * into pool_row from public.pachanga_competition_venue_pools rows
        where rows.id=authorization_row.pool_id for update;
      if authorization_row.revision<>expected_revision or authorization_row.status<>'offered' then
        raise exception 'VENUE_ALLOCATION_STALE_REVISION' using errcode='40001';
      end if;
      if not private.pachanga_competition_venue_can_v1(pool_row.competition_id,actor_id,'manage') then
        raise exception 'VENUE_POOL_ACCEPT_AUTHORITY_REQUIRED' using errcode='42501';
      end if;
      update public.pachanga_competition_venue_authorizations rows set
        status='accepted',accepted_by=actor_id,accepted_at=clock_timestamp(),
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_at=clock_timestamp() where rows.id=authorization_row.id returning * into authorization_row;
      confirmed_aggregate_id:=authorization_row.id;
      confirmed_revision:=authorization_row.revision;
      selected_sequence:=authorization_row.server_sequence;
      aggregate_type:='venue_pool_authorization';
      event_venue_id:=authorization_row.venue_id;
      snapshot:=jsonb_build_object('authorizationId',authorization_row.id,
        'poolId',pool_row.id,'status',authorization_row.status,'revision',authorization_row.revision);
    else
      select * into pool_row from public.pachanga_competition_venue_pools rows
        where rows.id=aggregate_id for update;
      if not found then raise exception 'VENUE_POOL_NOT_FOUND' using errcode='P0002'; end if;
      if pool_row.revision<>expected_revision then raise exception 'VENUE_ALLOCATION_STALE_REVISION' using errcode='40001'; end if;
      if normalized_action in ('venue_pool.update','venue_pool.activate','venue_pool.revoke')
        and not private.pachanga_competition_venue_can_v1(pool_row.competition_id,actor_id,'manage') then
        raise exception 'VENUE_POOL_AUTHORITY_REQUIRED' using errcode='42501';
      end if;
      if normalized_action='venue_pool.update' then
        if pool_row.status not in ('draft','offered','accepted') then raise exception 'VENUE_POOL_IMMUTABLE' using errcode='22023'; end if;
        update public.pachanga_competition_venue_pools rows set
          name=coalesce(nullif(payload->>'name',''),rows.name),
          visibility=coalesce(nullif(payload->>'visibility',''),rows.visibility),
          revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
          updated_by=actor_id,updated_at=clock_timestamp()
          where rows.id=pool_row.id returning * into pool_row;
      elsif normalized_action='venue_pool.offer' then
        select * into venue_row from public.pachanga_club_venues rows
          where rows.id=nullif(payload->>'venueId','')::uuid;
        if not found or venue_row.club_id<>nullif(payload->>'ownerClubId','')::uuid
          or not private.pachanga_club_can_v1(venue_row.club_id,actor_id,'reservation_manage') then
          raise exception 'VENUE_POOL_OWNER_AUTHORITY_REQUIRED' using errcode='42501';
        end if;
        select coalesce(array_agg(value::text::uuid order by value::text),'{}'::uuid[])
          into target_pitch_ids from jsonb_array_elements_text(payload->'pitchIds') values_row(value);
        select coalesce(array_agg(upper(value::text) order by upper(value::text)),'{}'::text[])
          into target_modalities from jsonb_array_elements_text(payload->'modalities') values_row(value);
        if cardinality(target_pitch_ids)=0 or exists(
          select 1 from unnest(target_pitch_ids) pitch_id
          left join public.pachanga_venue_pitches pitches on pitches.id=pitch_id
          where pitches.id is null or pitches.venue_id<>venue_row.id or pitches.status<>'ACTIVE'
            or not (target_modalities <@ pitches.modalities)
        ) then raise exception 'VENUE_POOL_PITCH_INVALID' using errcode='22023'; end if;
        insert into public.pachanga_competition_venue_authorizations(
          pool_id,competition_id,edition_id,owner_club_id,venue_id,source_kind,
          recurring_series_id,reservation_id,authorized_pitch_ids,modalities,
          valid_from,valid_until,allowed_weekdays,local_start_time,local_end_time,
          capacity_per_slot,priority,visibility,status,revision,server_sequence,
          operation_id,offered_by,offered_at,expires_at
        ) values(
          pool_row.id,pool_row.competition_id,pool_row.edition_id,venue_row.club_id,venue_row.id,
          upper(coalesce(payload->>'sourceKind',case when pool_row.organizer_club_id=venue_row.club_id
            then 'SELF_MANAGED' else 'CLUB_OFFER' end)),
          nullif(payload->>'recurringSeriesId','')::uuid,
          nullif(payload->>'reservationId','')::uuid,target_pitch_ids,target_modalities,
          (payload->>'validFrom')::date,(payload->>'validUntil')::date,
          coalesce((select array_agg(value::smallint order by value::smallint)
            from jsonb_array_elements_text(payload->'allowedWeekdays') v(value)),array[1,2,3,4,5,6,7]::smallint[]),
          coalesce((payload->>'localStartTime')::time,'00:00'::time),
          coalesce((payload->>'localEndTime')::time,'23:59:59'::time),
          coalesce((payload->>'capacityPerSlot')::integer,1),
          coalesce((payload->>'priority')::integer,100),
          coalesce(payload->>'visibility','private'),'offered',1,
          nextval('private.pachanga_venue_sequence'),operation_id,actor_id,
          clock_timestamp(),nullif(payload->>'expiresAt','')::timestamptz
        ) returning * into authorization_row;
        update public.pachanga_competition_venue_pools rows set
          status=case when rows.status='draft' then 'offered' else rows.status end,
          revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
          updated_by=actor_id,updated_at=clock_timestamp()
          where rows.id=pool_row.id returning * into pool_row;
        event_venue_id:=authorization_row.venue_id;
      elsif normalized_action='venue_pool.activate' then
        if not exists(select 1 from public.pachanga_competition_venue_authorizations authz
          where authz.pool_id=pool_row.id and authz.status='accepted') then
          raise exception 'VENUE_POOL_ACCEPTED_AUTHORIZATION_REQUIRED' using errcode='22023';
        end if;
        update public.pachanga_competition_venue_authorizations authz set
          status='active',activated_by=actor_id,activated_at=clock_timestamp(),
          revision=authz.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
          updated_at=clock_timestamp()
          where authz.pool_id=pool_row.id and authz.status='accepted';
        insert into public.pachanga_competition_venue_pool_memberships(
          pool_id,authorization_id,venue_id,pitch_id,modality,priority,
          capacity_limit,operation_id,created_by
        ) select authz.pool_id,authz.id,authz.venue_id,pitch_ids.pitch_id,modalities.modality,
          authz.priority,null,
          private.pachanga_venue_deterministic_uuid_v1('wave9b:membership:'||authz.id::text||':'||pitch_ids.pitch_id::text||':'||modalities.modality),
          actor_id
        from public.pachanga_competition_venue_authorizations authz
        cross join lateral unnest(authz.authorized_pitch_ids) pitch_ids(pitch_id)
        cross join lateral unnest(authz.modalities) modalities(modality)
        join public.pachanga_venue_pitches pitches on pitches.id=pitch_ids.pitch_id
        where authz.pool_id=pool_row.id and authz.status='active'
          and modalities.modality=any(pitches.modalities)
        on conflict on constraint pachanga_competition_venue_pool_memberships_operation_id_key
        do nothing;
        update public.pachanga_competition_venue_pools rows set
          status='active',activated_at=clock_timestamp(),revision=rows.revision+1,
          server_sequence=nextval('private.pachanga_venue_sequence'),updated_by=actor_id,
          updated_at=clock_timestamp() where rows.id=pool_row.id returning * into pool_row;
      elsif normalized_action='venue_pool.revoke' then
        if pool_row.status in ('expired','revoked') then raise exception 'VENUE_POOL_REVOKE_STATE_INVALID' using errcode='22023'; end if;
        update public.pachanga_competition_venue_pool_memberships rows set
          status='revoked',revoked_at=clock_timestamp(),revision=rows.revision+1,
          server_sequence=nextval('private.pachanga_venue_sequence'),updated_at=clock_timestamp()
          where rows.pool_id=pool_row.id and rows.status='active';
        update public.pachanga_competition_venue_authorizations rows set
          status='revoked',revoked_by=actor_id,revoked_at=clock_timestamp(),
          revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
          updated_at=clock_timestamp() where rows.pool_id=pool_row.id
            and rows.status not in ('expired','revoked');
        update public.pachanga_competition_venue_pools rows set
          status='revoked',revoked_at=clock_timestamp(),revision=rows.revision+1,
          server_sequence=nextval('private.pachanga_venue_sequence'),updated_by=actor_id,
          updated_at=clock_timestamp() where rows.id=pool_row.id returning * into pool_row;
      end if;
      next_version:=coalesce((select max(rows.version)+1 from private.pachanga_competition_venue_pool_revisions rows
        where rows.pool_id=pool_row.id),1);
      selected_checksum:=private.pachanga_venue_allocation_json_checksum_v1(to_jsonb(pool_row));
      insert into private.pachanga_competition_venue_pool_revisions(
        pool_id,version,action,status,snapshot,checksum,operation_id,actor_id,server_sequence
      ) values(pool_row.id,next_version,normalized_action,pool_row.status,to_jsonb(pool_row),selected_checksum,
        operation_id,actor_id,nextval('private.pachanga_venue_sequence')) returning * into pool_revision;
      update public.pachanga_competition_venue_pools rows set current_revision_id=pool_revision.id
        where rows.id=pool_row.id returning * into pool_row;
      confirmed_aggregate_id:=pool_row.id;
      confirmed_revision:=pool_row.revision;
      selected_sequence:=pool_row.server_sequence;
      aggregate_type:='venue_pool';
      snapshot:=jsonb_build_object('poolId',pool_row.id,'status',pool_row.status,
        'revision',pool_row.revision,'poolRevisionId',pool_revision.id,
        'authorizationId',authorization_row.id,'checksum',selected_checksum);
    end if;

  elsif normalized_action='allocation_plan.create' then
    perform private.pachanga_venue_allocation_assert_flags_v1('allocation');
    select * into competition_row from public.pachanga_competitions rows
      where rows.id=nullif(payload->>'competitionId','')::uuid;
    if not found or not private.pachanga_competition_venue_can_v1(competition_row.id,actor_id,'manage') then
      raise exception 'VENUE_ALLOCATION_AUTHORITY_REQUIRED' using errcode='42501';
    end if;
    select * into pool_row from public.pachanga_competition_venue_pools rows
      where rows.id=nullif(payload->>'venuePoolId','')::uuid and rows.competition_id=competition_row.id
        and rows.edition_id=nullif(payload->>'editionId','')::uuid and rows.status='active';
    if not found then raise exception 'VENUE_ALLOCATION_POOL_NOT_ACTIVE' using errcode='22023'; end if;
    if not exists(select 1 from public.pachanga_competition_schedule_plans plans
      join public.pachanga_competition_schedule_revisions revisions on revisions.schedule_plan_id=plans.id
      where plans.id=nullif(payload->>'schedulePlanId','')::uuid
        and revisions.id=nullif(payload->>'scheduleRevisionId','')::uuid
        and plans.competition_id=competition_row.id and plans.edition_id=nullif(payload->>'editionId','')::uuid
        and plans.stage_id=nullif(payload->>'stageId','')::uuid) then
      raise exception 'VENUE_ALLOCATION_SCHEDULE_INVALID' using errcode='22023';
    end if;
    target_mode:=upper(payload->>'mode');
    perform private.pachanga_venue_allocation_assert_flags_v1(case target_mode
      when 'AUTOMATIC' then 'automatic' when 'MANUAL_ASSISTED' then 'manual' else 'hybrid' end);
    confirmed_aggregate_id:=gen_random_uuid();
    selected_sequence:=nextval('private.pachanga_venue_sequence');
    insert into public.pachanga_competition_venue_allocation_plans(
      id,competition_id,edition_id,stage_id,schedule_plan_id,schedule_revision_id,
      rule_revision_id,venue_pool_id,venue_pool_revision_id,mode,venue_required,
      operation_id,created_by,updated_by,server_sequence
    ) values(
      confirmed_aggregate_id,competition_row.id,(payload->>'editionId')::uuid,
      (payload->>'stageId')::uuid,(payload->>'schedulePlanId')::uuid,
      (payload->>'scheduleRevisionId')::uuid,(payload->>'ruleRevisionId')::uuid,
      pool_row.id,pool_row.current_revision_id,target_mode,
      coalesce((payload->>'venueRequired')::boolean,true),operation_id,actor_id,actor_id,
      selected_sequence
    ) returning * into plan_row;
    confirmed_revision:=plan_row.revision;
    aggregate_type:='venue_allocation_plan';
    snapshot:=jsonb_build_object('planId',plan_row.id,'status',plan_row.status,
      'revision',plan_row.revision,'mode',plan_row.mode);

  elsif normalized_action like 'allocation.%'
     or normalized_action = 'allocation_inputs.freeze'
     or normalized_action like 'allocation_constraint.%' then
    perform private.pachanga_venue_allocation_assert_flags_v1('allocation');
    select * into plan_row from public.pachanga_competition_venue_allocation_plans rows
      where rows.id=aggregate_id for update;
    if not found then raise exception 'VENUE_ALLOCATION_PLAN_NOT_FOUND' using errcode='P0002'; end if;
    if plan_row.revision<>expected_revision then raise exception 'VENUE_ALLOCATION_STALE_REVISION' using errcode='40001'; end if;
    if not private.pachanga_competition_venue_can_v1(plan_row.competition_id,actor_id,
      case when normalized_action='allocation.publish' then 'publish' else 'manage' end) then
      raise exception 'VENUE_ALLOCATION_AUTHORITY_REQUIRED' using errcode='42501';
    end if;
    if normalized_action='allocation_inputs.freeze' then
      perform private.pachanga_venue_allocation_freeze_inputs_v1(plan_row.id,operation_id,actor_id);
    elsif normalized_action='allocation_constraint.create' then
      insert into public.pachanga_competition_venue_allocation_constraints(
        allocation_plan_id,constraint_kind,constraint_code,scope_kind,scope_id,
        weight,parameters,reason,operation_id,created_by,updated_by
      ) values(
        plan_row.id,upper(payload->>'constraintKind'),upper(payload->>'constraintCode'),
        upper(coalesce(payload->>'scopeKind','PLAN')),nullif(payload->>'scopeId','')::uuid,
        coalesce((payload->>'weight')::numeric,1),coalesce(payload->'parameters','{}'::jsonb),
        payload->>'reason',operation_id,actor_id,actor_id
      ) returning * into constraint_row;
      update public.pachanga_competition_venue_allocation_plans rows set
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id,updated_at=clock_timestamp() where rows.id=plan_row.id;
    elsif normalized_action='allocation_constraint.update' then
      update public.pachanga_competition_venue_allocation_constraints rows set
        weight=coalesce((payload->>'weight')::numeric,rows.weight),
        parameters=coalesce(payload->'parameters',rows.parameters),
        reason=coalesce(nullif(payload->>'reason',''),rows.reason),
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id,updated_at=clock_timestamp()
      where rows.id=nullif(payload->>'constraintId','')::uuid
        and rows.allocation_plan_id=plan_row.id and rows.status='active'
      returning * into constraint_row;
      if not found then raise exception 'VENUE_ALLOCATION_CONSTRAINT_NOT_FOUND' using errcode='P0002'; end if;
      update public.pachanga_competition_venue_allocation_plans rows set
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id,updated_at=clock_timestamp() where rows.id=plan_row.id;
    elsif normalized_action='allocation_constraint.remove' then
      update public.pachanga_competition_venue_allocation_constraints rows set
        status='removed',removed_by=actor_id,removed_at=clock_timestamp(),
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id,updated_at=clock_timestamp()
      where rows.id=nullif(payload->>'constraintId','')::uuid
        and rows.allocation_plan_id=plan_row.id and rows.status='active'
      returning * into constraint_row;
      if not found then raise exception 'VENUE_ALLOCATION_CONSTRAINT_NOT_FOUND' using errcode='P0002'; end if;
      update public.pachanga_competition_venue_allocation_plans rows set
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id,updated_at=clock_timestamp() where rows.id=plan_row.id;
    elsif normalized_action in ('allocation.generate','allocation.regenerate') then
      perform private.pachanga_venue_allocation_assert_flags_v1(case plan_row.mode
        when 'AUTOMATIC' then 'automatic' when 'MANUAL_ASSISTED' then 'manual' else 'hybrid' end);
      new_revision_id:=private.pachanga_venue_allocation_generate_v1(
        plan_row.id,operation_id,actor_id,payload->>'seed',
        coalesce((payload->>'searchBudget')::integer,10000),
        case when normalized_action='allocation.generate' then 'generated'
          when plan_row.mode='HYBRID' then 'hybrid_completion' else 'regenerated' end
      );
    elsif normalized_action in ('allocation.item.assign','allocation.item.move','allocation.item.swap','allocation.item.remove') then
      perform private.pachanga_venue_allocation_assert_flags_v1('manual');
      new_revision_id:=private.pachanga_venue_allocation_clone_revision_v1(
        plan_row.id,operation_id,actor_id,case normalized_action
          when 'allocation.item.assign' then 'manual_assign'
          when 'allocation.item.move' then 'manual_move'
          when 'allocation.item.swap' then 'manual_swap' else 'manual_remove' end
      );
      select * into target_item from public.pachanga_competition_venue_allocation_items items
      where items.allocation_revision_id=new_revision_id
        and items.canonical_match_id=nullif(payload->>'canonicalMatchId','')::uuid for update;
      if not found or target_item.assignment_status='LOCKED' and target_item.source_kind='EXISTING_BINDING' then
        raise exception 'VENUE_ALLOCATION_ITEM_IMMUTABLE' using errcode='22023';
      end if;
      if normalized_action='allocation.item.swap' then
        select * into other_item from public.pachanga_competition_venue_allocation_items items
        where items.allocation_revision_id=new_revision_id
          and items.canonical_match_id=nullif(payload->>'otherCanonicalMatchId','')::uuid for update;
        if not found or target_item.pitch_id is null or other_item.pitch_id is null
          or target_item.assignment_status='LOCKED' or other_item.assignment_status='LOCKED'
          or not private.pachanga_venue_slot_is_available_v1(other_item.pitch_id,target_item.scheduled_start,target_item.scheduled_end,
            private.pachanga_venue_allocation_modality_v1((select rule_snapshot from private.pachanga_competition_venue_allocation_input_freezes where id=plan_row.current_input_freeze_id)))
          or not private.pachanga_venue_slot_is_available_v1(target_item.pitch_id,other_item.scheduled_start,other_item.scheduled_end,
            private.pachanga_venue_allocation_modality_v1((select rule_snapshot from private.pachanga_competition_venue_allocation_input_freezes where id=plan_row.current_input_freeze_id))) then
          raise exception 'VENUE_ALLOCATION_SWAP_CONFLICT' using errcode='23P01';
        end if;
        update public.pachanga_competition_venue_allocation_items items set
          venue_id=other_item.venue_id,pitch_id=other_item.pitch_id,
          pool_membership_id=other_item.pool_membership_id,source_kind='AUTHORIZED_PITCH',
          source_id=other_item.pool_membership_id,assignment_status='PROPOSED',
          conflict_codes='{}'::text[],manual_override=true,revision=items.revision+1,
          server_sequence=nextval('private.pachanga_venue_sequence'),updated_at=clock_timestamp()
          where items.id=target_item.id;
        update public.pachanga_competition_venue_allocation_items items set
          venue_id=target_item.venue_id,pitch_id=target_item.pitch_id,
          pool_membership_id=target_item.pool_membership_id,source_kind='AUTHORIZED_PITCH',
          source_id=target_item.pool_membership_id,assignment_status='PROPOSED',
          conflict_codes='{}'::text[],manual_override=true,revision=items.revision+1,
          server_sequence=nextval('private.pachanga_venue_sequence'),updated_at=clock_timestamp()
          where items.id=other_item.id;
      elsif normalized_action='allocation.item.remove' then
        update public.pachanga_competition_venue_allocation_items items set
          venue_id=null,pitch_id=null,pool_membership_id=null,source_kind=null,source_id=null,
          assignment_status=case when plan_row.venue_required then 'UNASSIGNED' else 'TBD' end,
          conflict_codes=case when plan_row.venue_required then array['PITCH_AVAILABLE'] else '{}'::text[] end,
          manual_override=true,revision=items.revision+1,
          server_sequence=nextval('private.pachanga_venue_sequence'),updated_at=clock_timestamp()
          where items.id=target_item.id;
      else
        select * into target_membership from public.pachanga_competition_venue_pool_memberships memberships
        where memberships.pool_id=plan_row.venue_pool_id
          and memberships.pitch_id=nullif(payload->>'pitchId','')::uuid and memberships.status='active'
          and memberships.modality=private.pachanga_venue_allocation_modality_v1(
            (select rule_snapshot from private.pachanga_competition_venue_allocation_input_freezes where id=plan_row.current_input_freeze_id)
          ) order by memberships.priority,memberships.id limit 1;
        if not found or not private.pachanga_venue_slot_is_available_v1(
          target_membership.pitch_id,target_item.scheduled_start,target_item.scheduled_end,target_membership.modality
        ) or exists(
          select 1 from public.pachanga_competition_venue_allocation_items occupied
          join public.pachanga_venue_pitches occupied_pitch on occupied_pitch.id=occupied.pitch_id
          join public.pachanga_venue_pitches selected_pitch on selected_pitch.id=target_membership.pitch_id
          where occupied.allocation_revision_id=new_revision_id and occupied.id<>target_item.id
            and occupied_pitch.conflict_scope_id=selected_pitch.conflict_scope_id
            and tstzrange(occupied.scheduled_start,occupied.scheduled_end,'[)')
              && tstzrange(target_item.scheduled_start,target_item.scheduled_end,'[)')
        ) then raise exception 'VENUE_ALLOCATION_ASSIGNMENT_CONFLICT' using errcode='23P01'; end if;
        update public.pachanga_competition_venue_allocation_items items set
          venue_id=target_membership.venue_id,pitch_id=target_membership.pitch_id,
          pool_membership_id=target_membership.id,source_kind='AUTHORIZED_PITCH',
          source_id=target_membership.id,assignment_status='PROPOSED',
          conflict_codes='{}'::text[],manual_override=true,revision=items.revision+1,
          server_sequence=nextval('private.pachanga_venue_sequence'),updated_at=clock_timestamp()
          where items.id=target_item.id;
      end if;
      delete from private.pachanga_competition_venue_allocation_conflicts conflicts
        where conflicts.allocation_revision_id=new_revision_id;
      perform private.pachanga_venue_allocation_finalize_revision_v1(new_revision_id,actor_id);
    elsif normalized_action='allocation.lock.create' then
      insert into public.pachanga_competition_venue_allocation_locks(
        allocation_plan_id,lock_type,canonical_match_id,round_id,venue_id,pitch_id,
        recurring_occurrence_id,reason,operation_id,created_by
      ) values(
        plan_row.id,upper(payload->>'lockType'),nullif(payload->>'canonicalMatchId','')::uuid,
        nullif(payload->>'roundId','')::uuid,nullif(payload->>'venueId','')::uuid,
        nullif(payload->>'pitchId','')::uuid,nullif(payload->>'recurringOccurrenceId','')::uuid,
        payload->>'reason',operation_id,actor_id
      ) returning * into lock_row;
      update public.pachanga_competition_venue_allocation_plans rows set
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id,updated_at=clock_timestamp() where rows.id=plan_row.id;
    elsif normalized_action='allocation.lock.remove' then
      update public.pachanga_competition_venue_allocation_locks rows set
        status='released',released_by=actor_id,released_at=clock_timestamp(),
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence')
        where rows.id=nullif(payload->>'lockId','')::uuid and rows.allocation_plan_id=plan_row.id
          and rows.status='active' returning * into lock_row;
      if not found then raise exception 'VENUE_ALLOCATION_LOCK_NOT_FOUND' using errcode='P0002'; end if;
      update public.pachanga_competition_venue_allocation_plans rows set
        revision=rows.revision+1,server_sequence=nextval('private.pachanga_venue_sequence'),
        updated_by=actor_id,updated_at=clock_timestamp() where rows.id=plan_row.id;
    elsif normalized_action='allocation.hold' then
      replay:=private.pachanga_venue_allocation_create_holds_v1(plan_row.id,operation_id,actor_id,
        coalesce((payload->>'expiresInMinutes')::integer,60));
    elsif normalized_action='allocation.validate' then
      replay:=private.pachanga_venue_allocation_validate_v1(plan_row.id,actor_id);
    elsif normalized_action='allocation.publish' then
      replay:=private.pachanga_venue_allocation_publish_v1(plan_row.id,operation_id,actor_id,reason_code);
    elsif normalized_action='allocation.cancel' then
      replay:=private.pachanga_venue_allocation_cancel_v1(plan_row.id,actor_id,reason_code);
    end if;
    select * into plan_row from public.pachanga_competition_venue_allocation_plans rows where rows.id=aggregate_id;
    confirmed_aggregate_id:=plan_row.id;
    confirmed_revision:=plan_row.revision;
    selected_sequence:=plan_row.server_sequence;
    aggregate_type:='venue_allocation_plan';
    snapshot:=jsonb_strip_nulls(jsonb_build_object(
      'planId',plan_row.id,'status',plan_row.status,'revision',plan_row.revision,
      'currentInputFreezeId',plan_row.current_input_freeze_id,
      'currentRevisionId',plan_row.current_revision_id,
      'result',replay
    ));
  else
    raise exception 'VENUE_ALLOCATION_ACTION_UNSUPPORTED' using errcode='22023';
  end if;

  invalidations:=jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
    'entityType',aggregate_type,'entityId',confirmed_aggregate_id,
    'revision',confirmed_revision,'audienceKind',case
      when aggregate_type='recurring_series' and series_row.team_id is not null then 'TEAM'
      when aggregate_type='recurring_series' and series_row.competition_id is not null then 'COMPETITION'
      when aggregate_type in ('venue_pool','venue_allocation_plan') then 'COMPETITION'
      else 'AUTHENTICATED'
    end,
    'audienceId',case when aggregate_type='recurring_series' then coalesce(series_row.team_id,series_row.competition_id)
      when aggregate_type in ('venue_pool','venue_allocation_plan') then coalesce(pool_row.competition_id,plan_row.competition_id)
      else null end
  )));
  return private.pachanga_venue_store_command_v1(
    operation_id,actor_id,'authenticated',normalized_action,aggregate_type,
    confirmed_aggregate_id::text,confirmed_revision,selected_sequence,request_hash,
    private.pachanga_venue_client_metadata_v1(client_metadata),reason_code,
    jsonb_strip_nulls(jsonb_build_object('snapshot',snapshot)),snapshot,
    event_venue_id,event_pitch_id,null,null,event_match_id,invalidations
  );
end;
$$;

revoke all on function public.command_pachanga_competition_venue_allocation_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public, anon;
grant execute on function public.command_pachanga_competition_venue_allocation_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated, service_role;

reset statement_timeout;
reset lock_timeout;
