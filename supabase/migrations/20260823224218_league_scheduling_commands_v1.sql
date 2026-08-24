-- Pachangas IQ R4B: deterministic LEAGUE scheduling commands.

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
      'schedule_publish'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'entries_manage', 'rosters_review', 'categories_manage',
      'schedule_read', 'schedule_manage', 'schedule_publish'
    )
    when 'competition_schedule_manager' then target_capability in (
      'read', 'schedule_read', 'schedule_manage', 'schedule_publish'
    )
    when 'competition_registration_manager' then target_capability in ('read', 'entries_manage')
    when 'competition_roster_manager' then target_capability in ('read', 'rosters_review')
    when 'rules_manager' then target_capability in ('read', 'rules')
    when 'competition_referee_manager' then target_capability in ('read', 'referees')
    when 'viewer' then target_capability in ('read', 'schedule_read')
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_scheduling_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.league_scheduling_foundation_enabled,
    'generationEnabled', settings.league_schedule_generation_enabled,
    'editingEnabled', settings.league_schedule_editing_enabled,
    'publicationEnabled', settings.league_schedule_publication_enabled,
    'publicCalendarEnabled', settings.league_public_calendar_enabled,
    'canonicalFixtureCreationEnabled', settings.league_canonical_fixture_creation_enabled,
    'engineVersion', 'league-round-robin-v1',
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

revoke all on function private.pachanga_league_scheduling_flags_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_assert_flags_v1(
  require_generation boolean default false,
  require_editing boolean default false,
  require_publication boolean default false,
  require_public_calendar boolean default false
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
  if not settings.foundation_enabled
     or not settings.league_participation_foundation_enabled
     or not settings.league_scheduling_foundation_enabled then
    raise exception 'LEAGUE_SCHEDULING_FOUNDATION_DISABLED' using errcode = '42501';
  end if;
  if require_generation and (
    not settings.league_registration_enabled
    or not settings.league_rosters_enabled
    or not settings.league_schedule_generation_enabled
  ) then raise exception 'LEAGUE_SCHEDULE_GENERATION_DISABLED' using errcode = '42501'; end if;
  if require_editing and not settings.league_schedule_editing_enabled then
    raise exception 'LEAGUE_SCHEDULE_EDITING_DISABLED' using errcode = '42501';
  end if;
  if require_publication and (
    not settings.league_schedule_publication_enabled
    or not settings.league_canonical_fixture_creation_enabled
  ) then raise exception 'LEAGUE_SCHEDULE_PUBLICATION_DISABLED' using errcode = '42501'; end if;
  if require_public_calendar and not settings.league_public_calendar_enabled then
    raise exception 'LEAGUE_PUBLIC_CALENDAR_DISABLED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_league_schedule_assert_flags_v1(boolean, boolean, boolean, boolean)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_policy_v1(target_rule_revision_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb := private.pachanga_league_rule_document_v1(target_rule_revision_id);
declare policy jsonb := coalesce(document #> '{operations,schedulePolicy}', '{}'::jsonb);
declare selected_format text;
declare selected_legs integer;
declare duration_minutes integer;
declare buffer_minutes integer;
declare minimum_rest_minutes integer;
declare home_away_policy text;
declare venue_required boolean;
declare maximum_streak integer;
begin
  selected_format := upper(coalesce(nullif(policy ->> 'format', ''), ''));
  selected_legs := nullif(policy ->> 'legs', '')::integer;
  duration_minutes := nullif(policy ->> 'matchDurationMinutes', '')::integer;
  buffer_minutes := coalesce(nullif(policy ->> 'requiredBufferMinutes', '')::integer, 0);
  minimum_rest_minutes := coalesce(nullif(policy ->> 'minimumRestMinutes', '')::integer, 0);
  home_away_policy := upper(coalesce(nullif(policy ->> 'homeAwayPolicy', ''), 'BALANCED'));
  venue_required := coalesce(nullif(policy ->> 'venueRequired', '')::boolean, false);
  maximum_streak := coalesce(nullif(policy ->> 'maximumHomeAwayStreak', '')::integer, 3);
  if selected_format <> 'ROUND_ROBIN' or selected_legs not in (1, 2)
     or duration_minutes is null or duration_minutes < 1 or duration_minutes > 360
     or buffer_minutes < 0 or buffer_minutes > 240
     or minimum_rest_minutes < 0 or minimum_rest_minutes > 10080
     or home_away_policy not in ('BALANCED', 'MIRRORED_SECOND_LEG')
     or maximum_streak < 1 or maximum_streak > 12 then
    raise exception 'SCHEDULE_RULE_POLICY_INVALID' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'format', selected_format,
    'legs', selected_legs,
    'matchDurationMinutes', duration_minutes,
    'requiredBufferMinutes', buffer_minutes,
    'minimumRestMinutes', minimum_rest_minutes,
    'homeAwayPolicy', home_away_policy,
    'venueRequired', venue_required,
    'maximumHomeAwayStreak', maximum_streak,
    'hardHomeAwayStreak', coalesce(nullif(policy ->> 'hardHomeAwayStreak', '')::boolean, false),
    'windowStartsAt', nullif(policy ->> 'windowStartsAt', ''),
    'windowEndsAt', nullif(policy ->> 'windowEndsAt', ''),
    'softPreferenceWeights', coalesce(policy -> 'softPreferenceWeights', '{}'::jsonb),
    'rosterStatuses', coalesce(policy -> 'rosterStatuses', '["approved","locked"]'::jsonb)
  );
end;
$$;

revoke all on function private.pachanga_league_schedule_policy_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_plan_scope_v1(target_plan_id uuid)
returns public.pachanga_competition_schedule_plans
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_competition_schedule_plans%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare stage_row public.pachanga_competition_stages%rowtype;
begin
  select * into selected
  from public.pachanga_competition_schedule_plans plans
  where plans.id = target_plan_id;
  if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = selected.competition_id;
  if competition_row.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = selected.edition_id;
  select * into stage_row from public.pachanga_competition_stages stages
  where stages.id = selected.stage_id;
  if edition_row.competition_id <> selected.competition_id
     or stage_row.edition_id <> selected.edition_id then
    raise exception 'SCHEDULE_SCOPE_MISMATCH' using errcode = '22023';
  end if;
  if stage_row.stage_type not in ('LEAGUE_STAGE', 'GROUP_STAGE', 'SPLIT') then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if selected.division_id is not null and not exists (
    select 1 from public.pachanga_competition_divisions divisions
    where divisions.id = selected.division_id and divisions.stage_id = selected.stage_id
  ) then raise exception 'SCHEDULE_DIVISION_SCOPE_MISMATCH' using errcode = '22023'; end if;
  if selected.competition_group_id is not null and not exists (
    select 1 from public.pachanga_competition_groups groups
    where groups.id = selected.competition_group_id
      and groups.stage_id = selected.stage_id
      and (selected.division_id is null or groups.division_id = selected.division_id)
  ) then raise exception 'SCHEDULE_GROUP_SCOPE_MISMATCH' using errcode = '22023'; end if;
  perform private.pachanga_league_schedule_policy_v1(selected.rule_revision_id);
  return selected;
end;
$$;

revoke all on function private.pachanga_league_schedule_plan_scope_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_inputs_v1(
  target_plan_id uuid,
  target_seed text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare policy jsonb;
declare entries_snapshot jsonb;
declare ordered_entries jsonb;
declare slots_snapshot jsonb;
declare constraints_snapshot jsonb;
declare preferences_snapshot jsonb;
declare entry_checksum text;
declare slot_checksum text;
declare constraint_checksum text;
declare preference_checksum text;
declare input_checksum text;
declare entry_total integer;
declare roster_statuses text[];
begin
  plan_row := private.pachanga_league_schedule_plan_scope_v1(target_plan_id);
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = plan_row.edition_id;
  if edition_row.status <> 'registration_closed' then
    raise exception 'REGISTRATION_MUST_BE_CLOSED' using errcode = '22023';
  end if;
  policy := private.pachanga_league_schedule_policy_v1(plan_row.rule_revision_id);
  if (policy ->> 'legs')::integer <> plan_row.legs then
    raise exception 'RULE_REVISION_MISMATCH' using errcode = '22023';
  end if;
  select coalesce(array_agg(lower(value)), array['approved', 'locked']) into roster_statuses
  from jsonb_array_elements_text(policy -> 'rosterStatuses') values_list(value);

  select coalesce(jsonb_agg(jsonb_build_object(
    'entryId', source.entry_id,
    'teamId', source.team_id,
    'entryRevision', source.entry_revision,
    'membershipId', source.membership_id,
    'membershipRevision', source.membership_revision,
    'rosterId', source.roster_id,
    'rosterRevision', source.roster_revision,
    'rosterRevisionId', source.roster_revision_id,
    'eligibilitySummary', source.eligibility_summary,
    'ruleRevisionId', source.rule_revision_id
  ) order by source.entry_id), '[]'::jsonb) into entries_snapshot
  from (
    select entries.id as entry_id, entries.team_id, entries.revision as entry_revision,
      memberships.id as membership_id, memberships.revision as membership_revision,
      rosters.id as roster_id, rosters.revision as roster_revision,
      rosters.current_revision_id as roster_revision_id,
      roster_revisions.eligibility_summary, entries.rule_revision_id
    from public.pachanga_competition_entries entries
    join public.pachanga_competition_stage_memberships memberships
      on memberships.entry_id = entries.id and memberships.status = 'active'
    join public.pachanga_competition_rosters rosters
      on rosters.entry_id = entries.id and rosters.status = any(roster_statuses)
    join public.pachanga_competition_roster_revisions roster_revisions
      on roster_revisions.id = rosters.current_revision_id
    where entries.competition_id = plan_row.competition_id
      and entries.edition_id = plan_row.edition_id
      and entries.category_id = plan_row.category_id
      and entries.status in ('accepted', 'active')
      and entries.rule_revision_id = plan_row.rule_revision_id
      and memberships.stage_id = plan_row.stage_id
      and memberships.rule_revision_id = plan_row.rule_revision_id
      and memberships.division_id is not distinct from plan_row.division_id
      and memberships.competition_group_id is not distinct from plan_row.competition_group_id
      and coalesce((roster_revisions.eligibility_summary ->> 'pending')::integer, 0) = 0
      and coalesce((roster_revisions.eligibility_summary ->> 'reviewRequired')::integer, 0) = 0
      and coalesce((roster_revisions.eligibility_summary ->> 'ineligible')::integer, 0) = 0
      and coalesce((roster_revisions.eligibility_summary ->> 'expired')::integer, 0) = 0
  ) source;
  entry_total := jsonb_array_length(entries_snapshot);
  if entry_total < 2 then raise exception 'SCHEDULE_REQUIRES_AT_LEAST_TWO_ENTRIES' using errcode = '22023'; end if;
  if entry_total > 32 then raise exception 'SCHEDULE_ENGINE_CAPACITY_EXCEEDED' using errcode = '54000'; end if;

  select coalesce(jsonb_agg(item.value order by
    encode(extensions.digest(convert_to(
      coalesce(target_seed, '') || ':' || (item.value ->> 'entryId'),
      'UTF8'
    ), 'sha256'), 'hex'),
    item.value ->> 'entryId'
  ), '[]'::jsonb) into ordered_entries
  from jsonb_array_elements(entries_snapshot) item(value);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', slots.id, 'startsAt', slots.starts_at, 'endsAt', slots.ends_at,
    'timezone', slots.timezone, 'venueId', slots.venue_id,
    'resourceKey', slots.resource_key, 'revision', slots.revision
  ) order by slots.starts_at, slots.server_sequence, slots.id), '[]'::jsonb) into slots_snapshot
  from public.pachanga_competition_schedule_slots slots
  where slots.competition_id = plan_row.competition_id
    and slots.edition_id = plan_row.edition_id
    and slots.stage_id = plan_row.stage_id
    and slots.division_id is not distinct from plan_row.division_id
    and slots.competition_group_id is not distinct from plan_row.competition_group_id
    and slots.status <> 'retired';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', constraints.id, 'entryId', constraints.entry_id,
    'weekday', constraints.weekday, 'start', constraints.start_local_time,
    'end', constraints.end_local_time, 'timezone', constraints.timezone,
    'validFrom', constraints.valid_from_date, 'validUntil', constraints.valid_until_date,
    'revision', constraints.revision
  ) order by constraints.entry_id, constraints.server_sequence, constraints.id), '[]'::jsonb)
  into constraints_snapshot
  from public.pachanga_team_availability_constraints constraints
  where constraints.status = 'active'
    and exists (select 1 from jsonb_array_elements(entries_snapshot) item
      where (item ->> 'entryId')::uuid = constraints.entry_id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', preferences.id, 'entryId', preferences.entry_id,
    'weekday', preferences.weekday, 'start', preferences.start_local_time,
    'end', preferences.end_local_time, 'timezone', preferences.timezone,
    'weight', preferences.weight, 'preferredArea', preferences.preferred_area,
    'venueReference', preferences.venue_reference, 'revision', preferences.revision
  ) order by preferences.entry_id, preferences.server_sequence, preferences.id), '[]'::jsonb)
  into preferences_snapshot
  from public.pachanga_team_schedule_preferences preferences
  where preferences.status = 'active'
    and exists (select 1 from jsonb_array_elements(entries_snapshot) item
      where (item ->> 'entryId')::uuid = preferences.entry_id);

  entry_checksum := encode(extensions.digest(convert_to(entries_snapshot::text, 'UTF8'), 'sha256'), 'hex');
  slot_checksum := encode(extensions.digest(convert_to(slots_snapshot::text, 'UTF8'), 'sha256'), 'hex');
  constraint_checksum := encode(extensions.digest(convert_to(constraints_snapshot::text, 'UTF8'), 'sha256'), 'hex');
  preference_checksum := encode(extensions.digest(convert_to(preferences_snapshot::text, 'UTF8'), 'sha256'), 'hex');
  input_checksum := encode(extensions.digest(convert_to(
    plan_row.engine_version || ':' || plan_row.rule_revision_id::text || ':' ||
    entry_checksum || ':' || slot_checksum || ':' || constraint_checksum || ':' || preference_checksum,
    'UTF8'
  ), 'sha256'), 'hex');
  return jsonb_build_object(
    'entries', ordered_entries,
    'entryCount', entry_total,
    'slotCount', jsonb_array_length(slots_snapshot),
    'entryChecksum', entry_checksum,
    'slotChecksum', slot_checksum,
    'constraintChecksum', constraint_checksum,
    'preferenceChecksum', preference_checksum,
    'inputChecksum', input_checksum,
    'policy', policy
  );
end;
$$;

revoke all on function private.pachanga_league_schedule_inputs_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_slot_check_v1(
  target_schedule_revision_id uuid,
  target_home_entry_id uuid,
  target_away_entry_id uuid,
  target_slot_id uuid,
  target_ignored_item_ids uuid[] default array[]::uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare slot_row public.pachanga_competition_schedule_slots%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare policy jsonb;
declare reasons jsonb := '[]'::jsonb;
declare required_minutes integer;
declare minimum_rest interval;
declare window_start timestamptz;
declare window_end timestamptz;
begin
  select * into revision_row from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = target_schedule_revision_id;
  if not found then return jsonb_build_object('eligible', false, 'reasons', jsonb_build_array('REVISION_NOT_FOUND')); end if;
  plan_row := private.pachanga_league_schedule_plan_scope_v1(revision_row.schedule_plan_id);
  select * into slot_row from public.pachanga_competition_schedule_slots slots
  where slots.id = target_slot_id;
  if not found or slot_row.status = 'retired'
     or slot_row.edition_id <> plan_row.edition_id
     or slot_row.stage_id <> plan_row.stage_id
     or slot_row.division_id is distinct from plan_row.division_id
     or slot_row.competition_group_id is distinct from plan_row.competition_group_id then
    return jsonb_build_object('eligible', false, 'reasons', jsonb_build_array('MISSING_SLOT'));
  end if;
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = plan_row.edition_id;
  policy := private.pachanga_league_schedule_policy_v1(plan_row.rule_revision_id);
  required_minutes := (policy ->> 'matchDurationMinutes')::integer
    + (policy ->> 'requiredBufferMinutes')::integer;
  minimum_rest := make_interval(mins => (policy ->> 'minimumRestMinutes')::integer);
  window_start := nullif(policy ->> 'windowStartsAt', '')::timestamptz;
  window_end := nullif(policy ->> 'windowEndsAt', '')::timestamptz;

  if extract(epoch from (slot_row.ends_at - slot_row.starts_at)) / 60 < required_minutes then
    reasons := reasons || jsonb_build_array('INSUFFICIENT_SLOT_DURATION');
  end if;
  if edition_row.starts_at is not null
     and (slot_row.starts_at at time zone slot_row.timezone)::date < edition_row.starts_at then
    reasons := reasons || jsonb_build_array('EDITION_RANGE');
  end if;
  if edition_row.ends_at is not null
     and (slot_row.ends_at at time zone slot_row.timezone)::date > edition_row.ends_at then
    reasons := reasons || jsonb_build_array('EDITION_RANGE');
  end if;
  if window_start is not null and slot_row.starts_at < window_start then
    reasons := reasons || jsonb_build_array('STAGE_RANGE');
  end if;
  if window_end is not null and slot_row.ends_at > window_end then
    reasons := reasons || jsonb_build_array('STAGE_RANGE');
  end if;
  if (policy ->> 'venueRequired')::boolean and slot_row.venue_id is null then
    reasons := reasons || jsonb_build_array('MISSING_VENUE');
  end if;
  if exists (
    select 1
    from public.pachanga_team_availability_constraints constraints
    cross join lateral generate_series(
      (slot_row.starts_at at time zone constraints.timezone)::date - 1,
      (slot_row.ends_at at time zone constraints.timezone)::date,
      interval '1 day'
    ) candidate_day
    where constraints.entry_id in (target_home_entry_id, target_away_entry_id)
      and constraints.status = 'active'
      and extract(isodow from candidate_day)::integer = constraints.weekday
      and (constraints.valid_from_date is null or candidate_day::date >= constraints.valid_from_date)
      and (constraints.valid_until_date is null or candidate_day::date <= constraints.valid_until_date)
      and tstzrange(slot_row.starts_at, slot_row.ends_at, '[)') && tstzrange(
        (candidate_day::date + constraints.start_local_time) at time zone constraints.timezone,
        (candidate_day::date + constraints.end_local_time) at time zone constraints.timezone,
        '[)'
      )
  ) then reasons := reasons || jsonb_build_array('TEAM_UNAVAILABLE'); end if;
  if exists (
    select 1
    from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = target_schedule_revision_id
      and items.id <> all(coalesce(target_ignored_item_ids, array[]::uuid[]))
      and items.slot_id is not null
      and (items.home_entry_id in (target_home_entry_id, target_away_entry_id)
        or items.away_entry_id in (target_home_entry_id, target_away_entry_id))
      and tstzrange(items.scheduled_start, items.scheduled_end, '[)')
        && tstzrange(slot_row.starts_at, slot_row.ends_at, '[)')
  ) then reasons := reasons || jsonb_build_array('TEAM_OVERLAP'); end if;
  if minimum_rest > interval '0 minutes' and exists (
    select 1
    from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = target_schedule_revision_id
      and items.id <> all(coalesce(target_ignored_item_ids, array[]::uuid[]))
      and items.slot_id is not null
      and (items.home_entry_id in (target_home_entry_id, target_away_entry_id)
        or items.away_entry_id in (target_home_entry_id, target_away_entry_id))
      and (
        (items.scheduled_end <= slot_row.starts_at and slot_row.starts_at - items.scheduled_end < minimum_rest)
        or (slot_row.ends_at <= items.scheduled_start and items.scheduled_start - slot_row.ends_at < minimum_rest)
      )
  ) then reasons := reasons || jsonb_build_array('MINIMUM_REST'); end if;
  if exists (
    select 1 from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = target_schedule_revision_id
      and items.id <> all(coalesce(target_ignored_item_ids, array[]::uuid[]))
      and items.slot_id = target_slot_id
  ) then reasons := reasons || jsonb_build_array('VENUE_OVERLAP'); end if;
  return jsonb_build_object('eligible', jsonb_array_length(reasons) = 0, 'reasons', reasons);
end;
$$;

revoke all on function private.pachanga_league_schedule_slot_check_v1(uuid, uuid, uuid, uuid, uuid[])
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_quality_v1(
  target_schedule_revision_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare preference_total integer := 0;
declare preference_satisfied integer := 0;
declare preference_weight_total numeric := 0;
declare preference_weight_satisfied numeric := 0;
declare hard_total integer := 0;
declare unassigned_total integer := 0;
declare score numeric(6, 3) := 100;
declare preference_score numeric(6, 3) := 100;
declare home_away_score numeric(6, 3) := 100;
declare day_weight numeric := 50;
declare time_weight numeric := 40;
declare venue_weight numeric := 0;
declare home_away_weight numeric := 10;
declare policy jsonb;
declare home_balance jsonb := '{}'::jsonb;
declare time_distribution jsonb := '{}'::jsonb;
declare preference_teams jsonb := '{}'::jsonb;
declare max_home integer := 0;
declare max_away integer := 0;
declare explanation jsonb := '{}'::jsonb;
declare checksum text;
declare snapshot jsonb;
declare existing_checksum text;
begin
  select private.pachanga_league_schedule_policy_v1(plans.rule_revision_id)
    into policy
  from public.pachanga_competition_schedule_revisions revisions
  join public.pachanga_competition_schedule_plans plans
    on plans.id = revisions.schedule_plan_id
  where revisions.id = target_schedule_revision_id;
  day_weight := greatest(coalesce(nullif(policy #>> '{softPreferenceWeights,day}', '')::numeric, 50), 0);
  time_weight := greatest(coalesce(nullif(policy #>> '{softPreferenceWeights,time}', '')::numeric, 40), 0);
  venue_weight := greatest(coalesce(nullif(policy #>> '{softPreferenceWeights,venue}', '')::numeric, 0), 0);
  home_away_weight := greatest(coalesce(nullif(policy #>> '{softPreferenceWeights,homeAway}', '')::numeric, 10), 0);
  with evaluations as (
    select preferences.id, preferences.entry_id, items.id as item_id,
      preferences.weight::numeric as row_weight,
      extract(isodow from items.scheduled_start at time zone preferences.timezone)::integer = preferences.weekday as day_match,
      (items.scheduled_start at time zone preferences.timezone)::time < preferences.end_local_time
        and (items.scheduled_end at time zone preferences.timezone)::time > preferences.start_local_time as time_match,
      preferences.preferred_area is not null or preferences.venue_reference is not null as venue_applicable,
      case when preferences.preferred_area is null and preferences.venue_reference is null then true
        else lower(coalesce(items.venue_label, '') || ' ' || coalesce(slots.resource_key, ''))
          like '%' || lower(coalesce(preferences.preferred_area, preferences.venue_reference, '')) || '%'
      end as venue_match
    from public.pachanga_team_schedule_preferences preferences
    join public.pachanga_competition_schedule_items items
      on items.schedule_revision_id = target_schedule_revision_id
      and preferences.entry_id in (items.home_entry_id, items.away_entry_id)
      and items.slot_id is not null
    left join public.pachanga_competition_schedule_slots slots on slots.id = items.slot_id
    where preferences.status = 'active'
  ), weighted as (
    select *, row_weight * (day_weight + time_weight
      + case when venue_applicable then venue_weight else 0 end) as possible_weight,
      row_weight * (
        case when day_match then day_weight else 0 end
        + case when time_match then time_weight else 0 end
        + case when venue_applicable and venue_match then venue_weight else 0 end
      ) as satisfied_weight
    from evaluations
  )
  select count(*), count(*) filter (where day_match and time_match and venue_match),
    coalesce(sum(possible_weight), 0), coalesce(sum(satisfied_weight), 0)
  into preference_total, preference_satisfied,
    preference_weight_total, preference_weight_satisfied
  from weighted;
  select count(*) into hard_total from private.pachanga_competition_schedule_conflicts conflicts
  where conflicts.schedule_revision_id = target_schedule_revision_id
    and conflicts.status = 'active' and conflicts.severity = 'hard';
  select count(*) into unassigned_total from public.pachanga_competition_schedule_items items
  where items.schedule_revision_id = target_schedule_revision_id and items.slot_id is null;
  with sides as (
    select home_entry_id as entry_id, count(*) filter (where true) as home_count, 0::bigint as away_count
    from public.pachanga_competition_schedule_items where schedule_revision_id = target_schedule_revision_id group by home_entry_id
    union all
    select away_entry_id, 0::bigint, count(*)
    from public.pachanga_competition_schedule_items where schedule_revision_id = target_schedule_revision_id group by away_entry_id
  ), totals as (
    select entry_id, sum(home_count) as home_count, sum(away_count) as away_count
    from sides group by entry_id
  ) select coalesce(jsonb_object_agg(entry_id::text, jsonb_build_object(
    'home', home_count, 'away', away_count, 'difference', abs(home_count - away_count)
  ) order by entry_id), '{}'::jsonb) into home_balance from totals;

  with fixture_sides as (
    select rounds.round_number, items.home_entry_id as entry_id, 'H'::text as side
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.schedule_revision_id = target_schedule_revision_id
    union all
    select rounds.round_number, items.away_entry_id, 'A'::text
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.schedule_revision_id = target_schedule_revision_id
  ), grouped as (
    select entry_id, side,
      row_number() over(partition by entry_id order by round_number)
      - row_number() over(partition by entry_id, side order by round_number) as streak_group
    from fixture_sides
  ), streaks as (
    select entry_id, side, streak_group, count(*)::integer as length
    from grouped group by entry_id, side, streak_group
  ) select coalesce(max(length) filter (where side = 'H'), 0),
           coalesce(max(length) filter (where side = 'A'), 0)
    into max_home, max_away from streaks;

  select coalesce(jsonb_object_agg(day_label, fixtures order by day_label), '{}'::jsonb)
  into time_distribution
  from (
    select extract(isodow from items.scheduled_start at time zone items.timezone)::text as day_label,
      count(*) as fixtures
    from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = target_schedule_revision_id and items.slot_id is not null
    group by 1
  ) distribution;

  preference_score := case when preference_weight_total > 0
    then round((preference_weight_satisfied / preference_weight_total) * 100, 3)
    else 100 end;
  home_away_score := case
    when greatest(max_home, max_away) <= (policy ->> 'maximumHomeAwayStreak')::integer then 100
    else greatest(0, 100 - 20 * (
      greatest(max_home, max_away) - (policy ->> 'maximumHomeAwayStreak')::integer
    )) end;
  score := case
    when preference_weight_total = 0 and home_away_weight = 0 then 100
    else round((preference_score * greatest(day_weight + time_weight + venue_weight, 0)
      + home_away_score * home_away_weight)
      / nullif(greatest(day_weight + time_weight + venue_weight, 0) + home_away_weight, 0), 3)
    end;
  if hard_total > 0 or unassigned_total > 0 then score := 0; end if;

  with evaluations as (
    select preferences.entry_id,
      extract(isodow from items.scheduled_start at time zone preferences.timezone)::integer = preferences.weekday
        and (items.scheduled_start at time zone preferences.timezone)::time < preferences.end_local_time
        and (items.scheduled_end at time zone preferences.timezone)::time > preferences.start_local_time
        as satisfied,
      preferences.weight
    from public.pachanga_team_schedule_preferences preferences
    join public.pachanga_competition_schedule_items items
      on items.schedule_revision_id = target_schedule_revision_id
      and preferences.entry_id in (items.home_entry_id, items.away_entry_id)
      and items.slot_id is not null
    where preferences.status = 'active'
  ), grouped as (
    select entry_id, count(*) as opportunities,
      count(*) filter (where satisfied) as satisfied,
      coalesce(sum(weight) filter (where satisfied), 0) as satisfied_weight,
      coalesce(sum(weight), 0) as total_weight
    from evaluations group by entry_id
  )
  select coalesce(jsonb_object_agg(entry_id::text, jsonb_build_object(
    'opportunities', opportunities, 'satisfied', satisfied,
    'weightedScore', case when total_weight > 0
      then round(satisfied_weight::numeric / total_weight::numeric * 100, 3) else 100 end
  ) order by entry_id), '{}'::jsonb) into preference_teams from grouped;

  explanation := jsonb_build_object(
    'preferences', jsonb_build_object(
      'satisfied', preference_satisfied,
      'total', preference_total,
      'unsatisfied', greatest(preference_total - preference_satisfied, 0),
      'weightedSatisfied', preference_weight_satisfied,
      'weightedTotal', preference_weight_total,
      'weightedScore', preference_score,
      'byEntry', preference_teams
    ),
    'policyWeights', jsonb_build_object(
      'day', day_weight, 'time', time_weight,
      'venue', venue_weight, 'homeAway', home_away_weight
    ),
    'tradeOffs', case when preference_total = 0
      then jsonb_build_array('No había preferencias activas en la entrada canónica.')
      else jsonb_build_array('Las restricciones duras prevalecen sobre cualquier preferencia.') end,
    'homeAway', jsonb_build_object(
      'maximumHomeStreak', max_home, 'maximumAwayStreak', max_away,
      'score', home_away_score
    )
  );
  snapshot := jsonb_build_object(
    'hardViolations', hard_total, 'softScore', score,
    'preferenceSatisfiedCount', preference_satisfied,
    'preferenceTotalCount', preference_total,
    'homeAwayBalance', home_balance, 'timeDistribution', time_distribution,
    'maximumHomeStreak', max_home, 'maximumAwayStreak', max_away,
    'unassignedItems', unassigned_total, 'explanation', explanation
  );
  checksum := encode(extensions.digest(convert_to(snapshot::text, 'UTF8'), 'sha256'), 'hex');
  select quality.checksum into existing_checksum
  from private.pachanga_competition_schedule_quality_snapshots quality
  where quality.schedule_revision_id = target_schedule_revision_id;
  if existing_checksum is not null and existing_checksum <> checksum then
    raise exception 'QUALITY_SNAPSHOT_IMMUTABLE' using errcode = 'PT409';
  end if;
  insert into private.pachanga_competition_schedule_quality_snapshots(
    schedule_revision_id, hard_violations, soft_score,
    preference_satisfied_count, preference_total_count, home_away_balance,
    time_distribution, maximum_home_streak, maximum_away_streak,
    unassigned_items, explanation, checksum, server_sequence
  ) values (
    target_schedule_revision_id, hard_total, score,
    preference_satisfied, preference_total, home_balance,
    time_distribution, max_home, max_away, unassigned_total,
    explanation, checksum, target_server_sequence
  ) on conflict (schedule_revision_id) do nothing;
  update public.pachanga_competition_schedule_revisions revisions
  set quality_score = score,
      revision = revisions.revision + 1,
      server_sequence = target_server_sequence
  where revisions.id = target_schedule_revision_id;
  return snapshot || jsonb_build_object('checksum', checksum);
end;
$$;

revoke all on function private.pachanga_league_schedule_quality_v1(uuid, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_rebuild_conflicts_v1(
  target_schedule_revision_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare plan_id uuid;
declare item_row public.pachanga_competition_schedule_items%rowtype;
declare check_result jsonb;
declare reason_value text;
declare active_count integer;
declare expected_rounds integer;
declare expected_items_per_round integer;
begin
  select * into revision_row from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = target_schedule_revision_id;
  if not found then raise exception 'SCHEDULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
  plan_id := revision_row.schedule_plan_id;
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = plan_id;
  expected_rounds := (case when plan_row.entry_count % 2 = 0
    then plan_row.entry_count else plan_row.entry_count + 1 end - 1) * plan_row.legs;
  expected_items_per_round := plan_row.entry_count / 2;

  for item_row in
    select * from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = target_schedule_revision_id
    order by items.server_sequence, items.id
  loop
    if item_row.slot_id is null then
      check_result := jsonb_build_object('eligible', false, 'reasons', jsonb_build_array('MISSING_SLOT'));
    else
      check_result := private.pachanga_league_schedule_slot_check_v1(
        target_schedule_revision_id, item_row.home_entry_id, item_row.away_entry_id,
        item_row.slot_id, array[item_row.id]
      );
    end if;
    for reason_value in select jsonb_array_elements_text(check_result -> 'reasons')
    loop
      insert into private.pachanga_competition_schedule_conflicts(
        schedule_plan_id, schedule_revision_id, schedule_item_id, slot_id,
        conflict_type, severity, fingerprint, public_summary, private_detail,
        server_sequence
      ) values (
        plan_id, target_schedule_revision_id, item_row.id, item_row.slot_id,
        reason_value, 'hard', encode(extensions.digest(convert_to(
          target_schedule_revision_id::text || ':' || item_row.id::text || ':' || reason_value,
          'UTF8'
        ), 'sha256'), 'hex'),
        case reason_value
          when 'TEAM_UNAVAILABLE' then 'Un equipo no está disponible en este horario.'
          when 'TEAM_OVERLAP' then 'Un equipo tiene dos partidos solapados.'
          when 'VENUE_OVERLAP' then 'El recurso ya está asignado en ese horario.'
          when 'INSUFFICIENT_SLOT_DURATION' then 'El slot no cubre la duración y el margen reglamentarios.'
          when 'EDITION_RANGE' then 'El partido queda fuera de la edición.'
          when 'STAGE_RANGE' then 'El partido queda fuera de la ventana de la fase.'
          when 'MINIMUM_REST' then 'No se cumple el descanso mínimo.'
          when 'MISSING_VENUE' then 'La regla exige una sede confirmada.'
          else 'El partido no tiene un slot válido.' end,
        jsonb_build_object('reason', reason_value, 'itemId', item_row.id),
        target_server_sequence
      ) on conflict (schedule_revision_id, fingerprint) do nothing;
    end loop;
  end loop;

  if exists (
    select 1 from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = target_schedule_revision_id
    group by items.pairing_key, items.leg_number having count(*) > 1
  ) then
    insert into private.pachanga_competition_schedule_conflicts(
      schedule_plan_id, schedule_revision_id, conflict_type, severity,
      fingerprint, public_summary, private_detail, server_sequence
    ) values (
      plan_id, target_schedule_revision_id, 'DUPLICATE_PAIRING', 'hard',
      encode(extensions.digest(convert_to(target_schedule_revision_id::text || ':DUPLICATE_PAIRING', 'UTF8'), 'sha256'), 'hex'),
      'Existe una pareja duplicada fuera de las vueltas permitidas.', '{}'::jsonb,
      target_server_sequence
    ) on conflict (schedule_revision_id, fingerprint) do nothing;
  end if;
  if (select count(*) from public.pachanga_competition_rounds rounds
      where rounds.schedule_revision_id = target_schedule_revision_id) <> expected_rounds
     or exists (
       select 1
       from public.pachanga_competition_rounds rounds
       where rounds.schedule_revision_id = target_schedule_revision_id
         and (
           rounds.leg_number not in (1, 2)
           or (rounds.round_number <= expected_rounds / plan_row.legs and rounds.leg_number <> 1)
           or (plan_row.legs = 2 and rounds.round_number > expected_rounds / 2 and rounds.leg_number <> 2)
           or (select count(*) from public.pachanga_competition_schedule_items items
               where items.round_id = rounds.id) <> expected_items_per_round
           or (select count(*) from public.pachanga_competition_round_byes byes
               where byes.round_id = rounds.id) <> case when plan_row.entry_count % 2 = 1 then 1 else 0 end
         )
     )
     or exists (
       with entries as (
         select (value ->> 'entryId')::uuid as entry_id
         from jsonb_array_elements(revision_row.entry_order) value
       ), appearances as (
         select items.round_id, items.home_entry_id as entry_id
         from public.pachanga_competition_schedule_items items
         where items.schedule_revision_id = target_schedule_revision_id
         union all
         select items.round_id, items.away_entry_id
         from public.pachanga_competition_schedule_items items
         where items.schedule_revision_id = target_schedule_revision_id
         union all
         select byes.round_id, byes.entry_id
         from public.pachanga_competition_round_byes byes
         where byes.schedule_revision_id = target_schedule_revision_id
       )
       select 1
       from public.pachanga_competition_rounds rounds
       cross join entries
       left join appearances on appearances.round_id = rounds.id
         and appearances.entry_id = entries.entry_id
       where rounds.schedule_revision_id = target_schedule_revision_id
       group by rounds.id, entries.entry_id
       having count(appearances.entry_id) <> 1
     ) then
    insert into private.pachanga_competition_schedule_conflicts(
      schedule_plan_id, schedule_revision_id, conflict_type, severity,
      fingerprint, public_summary, private_detail, server_sequence
    ) values (
      plan_id, target_schedule_revision_id, 'ROUND_STRUCTURE_MISMATCH', 'hard',
      encode(extensions.digest(convert_to(target_schedule_revision_id::text || ':ROUND_STRUCTURE_MISMATCH', 'UTF8'), 'sha256'), 'hex'),
      'La estructura de jornadas no coincide con las entradas congeladas.',
      jsonb_build_object('expectedRounds', expected_rounds, 'expectedItemsPerRound', expected_items_per_round),
      target_server_sequence
    ) on conflict (schedule_revision_id, fingerprint) do nothing;
  end if;
  if exists (
    with appearances as (
      select items.round_id, items.home_entry_id as entry_id
      from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = target_schedule_revision_id
      union all
      select items.round_id, items.away_entry_id
      from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = target_schedule_revision_id
    )
    select 1 from appearances group by round_id, entry_id having count(*) > 1
  ) then
    insert into private.pachanga_competition_schedule_conflicts(
      schedule_plan_id, schedule_revision_id, conflict_type, severity,
      fingerprint, public_summary, private_detail, server_sequence
    ) values (
      plan_id, target_schedule_revision_id, 'TEAM_DUPLICATED_IN_ROUND', 'hard',
      encode(extensions.digest(convert_to(target_schedule_revision_id::text || ':TEAM_DUPLICATED_IN_ROUND', 'UTF8'), 'sha256'), 'hex'),
      'Un equipo aparece más de una vez en la misma jornada.', '{}'::jsonb,
      target_server_sequence
    ) on conflict (schedule_revision_id, fingerprint) do nothing;
  end if;
  if (plan_row.entry_count % 2 = 0 and exists (
      select 1 from public.pachanga_competition_round_byes byes
      where byes.schedule_revision_id = target_schedule_revision_id
    )) or (plan_row.entry_count % 2 = 1 and exists (
      select 1
      from jsonb_array_elements(revision_row.entry_order) entry(value)
      left join public.pachanga_competition_round_byes byes
        on byes.schedule_revision_id = target_schedule_revision_id
        and byes.entry_id = (entry.value ->> 'entryId')::uuid
      group by entry.value
      having count(byes.id) <> plan_row.legs
    )) then
    insert into private.pachanga_competition_schedule_conflicts(
      schedule_plan_id, schedule_revision_id, conflict_type, severity,
      fingerprint, public_summary, private_detail, server_sequence
    ) values (
      plan_id, target_schedule_revision_id, 'BYE_MISMATCH', 'hard',
      encode(extensions.digest(convert_to(target_schedule_revision_id::text || ':BYE_MISMATCH', 'UTF8'), 'sha256'), 'hex'),
      'Los descansos no corresponden al número de equipos y vueltas.', '{}'::jsonb,
      target_server_sequence
    ) on conflict (schedule_revision_id, fingerprint) do nothing;
  end if;
  if exists (
    with sides as (
      select items.home_entry_id as entry_id, 1 as balance
      from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = target_schedule_revision_id
      union all
      select items.away_entry_id, -1
      from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = target_schedule_revision_id
    )
    select 1 from sides group by entry_id
    having abs(sum(balance)) > case when plan_row.legs = 1 then 1 else 0 end
  ) then
    insert into private.pachanga_competition_schedule_conflicts(
      schedule_plan_id, schedule_revision_id, conflict_type, severity,
      fingerprint, public_summary, private_detail, server_sequence
    ) values (
      plan_id, target_schedule_revision_id, 'HOME_AWAY_IMBALANCE', 'hard',
      encode(extensions.digest(convert_to(target_schedule_revision_id::text || ':HOME_AWAY_IMBALANCE', 'UTF8'), 'sha256'), 'hex'),
      'El balance local y visitante no cumple la política de la Liga.', '{}'::jsonb,
      target_server_sequence
    ) on conflict (schedule_revision_id, fingerprint) do nothing;
  end if;
  if plan_row.legs = 2 and exists (
    select 1
    from public.pachanga_competition_schedule_items first_leg
    where first_leg.schedule_revision_id = target_schedule_revision_id
      and first_leg.leg_number = 1
      and not exists (
        select 1 from public.pachanga_competition_schedule_items second_leg
        where second_leg.schedule_revision_id = target_schedule_revision_id
          and second_leg.leg_number = 2
          and second_leg.pairing_key = first_leg.pairing_key
          and second_leg.home_entry_id = first_leg.away_entry_id
          and second_leg.away_entry_id = first_leg.home_entry_id
      )
  ) then
    insert into private.pachanga_competition_schedule_conflicts(
      schedule_plan_id, schedule_revision_id, conflict_type, severity,
      fingerprint, public_summary, private_detail, server_sequence
    ) values (
      plan_id, target_schedule_revision_id, 'SECOND_LEG_NOT_MIRRORED', 'hard',
      encode(extensions.digest(convert_to(target_schedule_revision_id::text || ':SECOND_LEG_NOT_MIRRORED', 'UTF8'), 'sha256'), 'hex'),
      'La segunda vuelta no es el espejo exacto de la primera.', '{}'::jsonb,
      target_server_sequence
    ) on conflict (schedule_revision_id, fingerprint) do nothing;
  end if;
  select count(*) into active_count
  from private.pachanga_competition_schedule_conflicts conflicts
  where conflicts.schedule_revision_id = target_schedule_revision_id and conflicts.status = 'active';
  return jsonb_build_object(
    'hardViolations', active_count,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', conflicts.id, 'type', conflicts.conflict_type,
        'itemId', conflicts.schedule_item_id, 'entryId', conflicts.entry_id,
        'summary', conflicts.public_summary
      ) order by conflicts.server_sequence, conflicts.id)
      from private.pachanga_competition_schedule_conflicts conflicts
      where conflicts.schedule_revision_id = target_schedule_revision_id and conflicts.status = 'active'
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function private.pachanga_league_schedule_rebuild_conflicts_v1(uuid, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_clone_revision_v1(
  target_schedule_plan_id uuid,
  target_source_revision_id uuid,
  target_revision_kind text,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare source_row public.pachanga_competition_schedule_revisions%rowtype;
declare new_id uuid := gen_random_uuid();
declare next_version integer;
declare source_round record;
declare new_round_id uuid;
begin
  select * into source_row from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = target_source_revision_id
    and revisions.schedule_plan_id = target_schedule_plan_id;
  if not found then raise exception 'SCHEDULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
  if source_row.status = 'published' then
    raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
  end if;
  select coalesce(max(revisions.version), 0) + 1 into next_version
  from public.pachanga_competition_schedule_revisions revisions
  where revisions.schedule_plan_id = target_schedule_plan_id;
  insert into public.pachanga_competition_schedule_revisions(
    id, schedule_plan_id, version, revision_kind, status, engine_version, seed,
    input_checksum, rule_revision_id, entry_snapshot_checksum,
    slot_snapshot_checksum, constraint_snapshot_checksum,
    preference_snapshot_checksum, entry_order, quality_score,
    validation_status, generated_by, generated_at, supersedes_revision_id,
    revision, server_sequence
  ) values (
    new_id, target_schedule_plan_id, next_version, target_revision_kind,
    'generated', source_row.engine_version, source_row.seed,
    source_row.input_checksum, source_row.rule_revision_id,
    source_row.entry_snapshot_checksum, source_row.slot_snapshot_checksum,
    source_row.constraint_snapshot_checksum, source_row.preference_snapshot_checksum,
    source_row.entry_order, 0, 'PENDING', target_actor_id,
    clock_timestamp(), source_row.id, 1, target_server_sequence
  );
  for source_round in
    select * from public.pachanga_competition_rounds rounds
    where rounds.schedule_revision_id = source_row.id
    order by rounds.round_number, rounds.id
  loop
    new_round_id := gen_random_uuid();
    insert into public.pachanga_competition_rounds(
      id, competition_id, edition_id, category_id, stage_id, division_id,
      competition_group_id, schedule_revision_id, round_number, leg_number,
      display_name, starts_at, ends_at, status, rule_revision_id,
      revision, server_sequence, created_by
    ) values (
      new_round_id, source_round.competition_id, source_round.edition_id,
      source_round.category_id, source_round.stage_id, source_round.division_id,
      source_round.competition_group_id, new_id, source_round.round_number,
      source_round.leg_number, source_round.display_name, source_round.starts_at,
      source_round.ends_at, 'draft', source_round.rule_revision_id, 1,
      target_server_sequence, target_actor_id
    );
    insert into public.pachanga_competition_round_byes(
      schedule_revision_id, round_id, entry_id, leg_number, reason,
      revision, server_sequence
    ) select new_id, new_round_id, byes.entry_id, byes.leg_number, byes.reason,
      1, target_server_sequence
    from public.pachanga_competition_round_byes byes
    where byes.round_id = source_round.id;
    insert into public.pachanga_competition_schedule_items(
      schedule_revision_id, round_id, home_entry_id, away_entry_id,
      pairing_key, leg_number, slot_id, scheduled_start, scheduled_end,
      timezone, venue_id, venue_label, venue_status, status,
      revision, server_sequence
    ) select
      new_id, new_round_id, items.home_entry_id, items.away_entry_id,
      items.pairing_key, items.leg_number, items.slot_id, items.scheduled_start,
      items.scheduled_end, items.timezone, items.venue_id, items.venue_label,
      items.venue_status, case when items.slot_id is null then 'unassigned' else 'assigned' end,
      1, target_server_sequence
    from public.pachanga_competition_schedule_items items
    where items.round_id = source_round.id
    order by items.server_sequence, items.id;
  end loop;
  update public.pachanga_competition_schedule_revisions revisions
  set status = 'superseded', revision = revisions.revision + 1,
      server_sequence = target_server_sequence
  where revisions.id = source_row.id;
  return new_id;
end;
$$;

revoke all on function private.pachanga_league_schedule_clone_revision_v1(uuid, uuid, text, uuid, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_revision_snapshot_v1(
  target_schedule_plan_id uuid,
  target_include_private boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare result jsonb;
begin
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id;
  if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  if plan_row.current_revision_id is not null then
    select * into revision_row from public.pachanga_competition_schedule_revisions revisions
    where revisions.id = plan_row.current_revision_id;
  end if;
  result := jsonb_build_object(
    'plan', jsonb_build_object(
      'id', plan_row.id, 'competitionId', plan_row.competition_id,
      'editionId', plan_row.edition_id, 'categoryId', plan_row.category_id,
      'stageId', plan_row.stage_id, 'divisionId', plan_row.division_id,
      'groupId', plan_row.competition_group_id, 'ruleRevisionId', plan_row.rule_revision_id,
      'engineVersion', plan_row.engine_version, 'legs', plan_row.legs,
      'entryCount', plan_row.entry_count, 'status', plan_row.status,
      'currentRevisionId', plan_row.current_revision_id,
      'revision', plan_row.revision, 'serverSequence', plan_row.server_sequence,
      'publishedAt', plan_row.published_at, 'updatedAt', plan_row.updated_at
    ),
    'revision', case when revision_row.id is null then null else jsonb_build_object(
      'id', revision_row.id, 'version', revision_row.version,
      'kind', revision_row.revision_kind, 'status', revision_row.status,
      'engineVersion', revision_row.engine_version, 'seed', revision_row.seed,
      'inputChecksum', revision_row.input_checksum,
      'qualityScore', revision_row.quality_score,
      'validationStatus', revision_row.validation_status,
      'supersedesRevisionId', revision_row.supersedes_revision_id,
      'revision', revision_row.revision, 'serverSequence', revision_row.server_sequence,
      'generatedAt', revision_row.generated_at, 'validatedAt', revision_row.validated_at,
      'publishedAt', revision_row.published_at
    ) end,
    'counts', jsonb_build_object(
      'rounds', (select count(*) from public.pachanga_competition_rounds rounds
        where rounds.schedule_revision_id = revision_row.id),
      'items', (select count(*) from public.pachanga_competition_schedule_items items
        where items.schedule_revision_id = revision_row.id),
      'byes', (select count(*) from public.pachanga_competition_round_byes byes
        where byes.schedule_revision_id = revision_row.id),
      'unassigned', (select count(*) from public.pachanga_competition_schedule_items items
        where items.schedule_revision_id = revision_row.id and items.slot_id is null),
      'published', (select count(*) from public.pachanga_competition_schedule_items items
        where items.schedule_revision_id = revision_row.id and items.status = 'published')
    ),
    'quality', (select jsonb_build_object(
      'hardViolations', quality.hard_violations, 'softScore', quality.soft_score,
      'preferenceSatisfiedCount', quality.preference_satisfied_count,
      'preferenceTotalCount', quality.preference_total_count,
      'homeAwayBalance', quality.home_away_balance,
      'timeDistribution', quality.time_distribution,
      'maximumHomeStreak', quality.maximum_home_streak,
      'maximumAwayStreak', quality.maximum_away_streak,
      'unassignedItems', quality.unassigned_items,
      'explanation', quality.explanation, 'checksum', quality.checksum
    ) from private.pachanga_competition_schedule_quality_snapshots quality
      where quality.schedule_revision_id = revision_row.id),
    'canonicalMatches', coalesce((select jsonb_agg(jsonb_build_object(
      'scheduleItemId', items.id, 'canonicalMatchId', items.canonical_match_id,
      'contextId', items.competition_match_context_id
    ) order by rounds.round_number, items.id)
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.schedule_revision_id = revision_row.id and items.canonical_match_id is not null), '[]'::jsonb)
  );
  if target_include_private then
    result := result || jsonb_build_object(
      'entryOrder', coalesce(revision_row.entry_order, '[]'::jsonb),
      'checksums', jsonb_build_object(
        'entries', revision_row.entry_snapshot_checksum,
        'slots', revision_row.slot_snapshot_checksum,
        'constraints', revision_row.constraint_snapshot_checksum,
        'preferences', revision_row.preference_snapshot_checksum
      ),
      'conflicts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', conflicts.id, 'type', conflicts.conflict_type,
        'itemId', conflicts.schedule_item_id, 'slotId', conflicts.slot_id,
        'entryId', conflicts.entry_id, 'summary', conflicts.public_summary,
        'detail', conflicts.private_detail
      ) order by conflicts.server_sequence, conflicts.id)
      from private.pachanga_competition_schedule_conflicts conflicts
      where conflicts.schedule_revision_id = revision_row.id and conflicts.status = 'active'), '[]'::jsonb)
    );
  end if;
  return result;
end;
$$;

revoke all on function private.pachanga_league_schedule_revision_snapshot_v1(uuid, boolean)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_reason_code text,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_invalidations jsonb,
  target_confirmed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare response jsonb;
declare invalidation jsonb;
declare invalidation_sequence bigint;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', coalesce(target_invalidations, '[]'::jsonb)
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated', 'league_schedule',
    target_aggregate_id::text, target_competition_id, target_action,
    target_confirmed_revision, target_server_sequence,
    left(target_reason_code, 120), coalesce(target_event_payload, '{}'::jsonb),
    target_confirmed_at
  );
  for invalidation in select * from jsonb_array_elements(coalesce(target_invalidations, '[]'::jsonb))
  loop
    invalidation_sequence := nextval('private.pachanga_competition_sequence');
    insert into public.pachanga_competition_invalidations(
      server_sequence, competition_id, organizer_group_id, organizer_club_id,
      target_group_id, target_user_id, entity_type, entity_id, revision, created_at
    ) values (
      invalidation_sequence, target_competition_id,
      competition_row.organizer_group_id, competition_row.organizer_club_id,
      nullif(invalidation ->> 'targetGroupId', '')::uuid,
      nullif(invalidation ->> 'targetUserId', '')::uuid,
      invalidation ->> 'entityType', invalidation ->> 'entityId',
      coalesce((invalidation ->> 'revision')::bigint, target_confirmed_revision),
      target_confirmed_at
    );
  end loop;
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated', target_action,
    'league_schedule', target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence, target_client_metadata,
    response, target_confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_league_schedule_store_command_v1(
  uuid, uuid, text, uuid, uuid, bigint, bigint, text, text, jsonb,
  jsonb, jsonb, jsonb, timestamptz
) from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_notify_published_v1(
  target_schedule_plan_id uuid,
  target_operation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare recipient record;
declare sent_count integer := 0;
begin
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id;
  for recipient in
    with eligible_entries as (
      select entries.id, entries.team_id
      from public.pachanga_competition_entries entries
      join public.pachanga_competition_stage_memberships memberships
        on memberships.entry_id = entries.id and memberships.status = 'active'
      where entries.edition_id = plan_row.edition_id
        and entries.category_id = plan_row.category_id
        and entries.status in ('accepted', 'active')
        and memberships.stage_id = plan_row.stage_id
        and memberships.division_id is not distinct from plan_row.division_id
        and memberships.competition_group_id is not distinct from plan_row.competition_group_id
    )
    select groups.owner_id as user_id, entries.id as entry_id
    from eligible_entries entries join public.pachanga_groups groups on groups.id = entries.team_id
    union
    select delegates.user_id, entries.id
    from eligible_entries entries
    join public.pachanga_competition_team_delegates delegates on delegates.entry_id = entries.id
    where delegates.status = 'active'
      and delegates.delegate_role in ('PRIMARY_DELEGATE', 'ROSTER_MANAGER')
      and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      'match_competition_schedule_published',
      'Calendario de Liga publicado',
      'Ya puedes consultar todas las jornadas de tu equipo.',
      '/mis-competiciones/calendario?entry=' || recipient.entry_id::text,
      jsonb_build_object('schedulePlanId', plan_row.id, 'entryId', recipient.entry_id),
      'league-schedule:' || target_operation_id::text || ':' || recipient.user_id::text
    );
    sent_count := sent_count + 1;
  end loop;
  return sent_count;
end;
$$;

revoke all on function private.pachanga_league_schedule_notify_published_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_generate_revision_v1(
  target_schedule_plan_id uuid,
  target_seed text,
  target_revision_kind text,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare inputs jsonb;
declare policy jsonb;
declare entry_ids uuid[];
declare rotation uuid[];
declare even_count integer;
declare entry_count integer;
declare rounds_per_leg integer;
declare required_matches integer;
declare available_slots integer;
declare round_index integer;
declare pair_index integer;
declare leg_index integer;
declare global_round integer;
declare left_entry uuid;
declare right_entry uuid;
declare home_entry uuid;
declare away_entry uuid;
declare round_id uuid;
declare second_round_id uuid;
declare new_revision_id uuid := gen_random_uuid();
declare next_version integer;
declare selected_item public.pachanga_competition_schedule_items%rowtype;
declare selected_slot public.pachanga_competition_schedule_slots%rowtype;
declare repair_item public.pachanga_competition_schedule_items%rowtype;
declare repair_source_slot public.pachanga_competition_schedule_slots%rowtype;
declare repair_target_slot public.pachanga_competition_schedule_slots%rowtype;
declare repair_item_id uuid;
declare repair_source_slot_id uuid;
declare repair_target_slot_id uuid;
declare pairing_key text;
declare balance_item_id uuid;
declare required_minutes integer;
declare minimum_rest interval;
declare window_start timestamptz;
declare window_end timestamptz;
begin
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id for update;
  if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
  end if;
  inputs := private.pachanga_league_schedule_inputs_v1(plan_row.id, target_seed);
  policy := inputs -> 'policy';
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = plan_row.edition_id;
  required_minutes := (policy ->> 'matchDurationMinutes')::integer
    + (policy ->> 'requiredBufferMinutes')::integer;
  minimum_rest := make_interval(mins => (policy ->> 'minimumRestMinutes')::integer);
  window_start := nullif(policy ->> 'windowStartsAt', '')::timestamptz;
  window_end := nullif(policy ->> 'windowEndsAt', '')::timestamptz;
  entry_count := (inputs ->> 'entryCount')::integer;
  select array_agg((entry.value ->> 'entryId')::uuid order by entry.ordinality)
    into entry_ids
  from jsonb_array_elements(inputs -> 'entries') with ordinality entry(value, ordinality);
  if entry_count % 2 = 1 then entry_ids := array_append(entry_ids, null::uuid); end if;
  even_count := array_length(entry_ids, 1);
  rounds_per_leg := even_count - 1;
  required_matches := (entry_count * (entry_count - 1) / 2) * plan_row.legs;
  available_slots := (inputs ->> 'slotCount')::integer;
  if available_slots < required_matches then
    raise exception 'SCHEDULE_CAPACITY_DEFICIT required=% available=% deficit=%',
      required_matches, available_slots, required_matches - available_slots using errcode = '22023';
  end if;
  select coalesce(max(revisions.version), 0) + 1 into next_version
  from public.pachanga_competition_schedule_revisions revisions
  where revisions.schedule_plan_id = plan_row.id;
  if plan_row.current_revision_id is not null then
    update public.pachanga_competition_schedule_revisions revisions
    set status = 'superseded', revision = revisions.revision + 1,
        server_sequence = target_server_sequence
    where revisions.id = plan_row.current_revision_id and revisions.status <> 'published';
  end if;
  insert into public.pachanga_competition_schedule_revisions(
    id, schedule_plan_id, version, revision_kind, status, engine_version, seed,
    input_checksum, rule_revision_id, entry_snapshot_checksum,
    slot_snapshot_checksum, constraint_snapshot_checksum,
    preference_snapshot_checksum, entry_order, quality_score,
    validation_status, generated_by, generated_at, supersedes_revision_id,
    revision, server_sequence
  ) values (
    new_revision_id, plan_row.id, next_version, target_revision_kind,
    'generated', plan_row.engine_version, target_seed,
    inputs ->> 'inputChecksum', plan_row.rule_revision_id,
    inputs ->> 'entryChecksum', inputs ->> 'slotChecksum',
    inputs ->> 'constraintChecksum', inputs ->> 'preferenceChecksum',
    inputs -> 'entries', 0, 'PENDING', target_actor_id, clock_timestamp(),
    plan_row.current_revision_id, 1, target_server_sequence
  );

  rotation := entry_ids;
  for round_index in 1..rounds_per_leg loop
    round_id := gen_random_uuid();
    insert into public.pachanga_competition_rounds(
      id, competition_id, edition_id, category_id, stage_id, division_id,
      competition_group_id, schedule_revision_id, round_number, leg_number,
      display_name, status, rule_revision_id, server_sequence, created_by
    ) values (
      round_id, plan_row.competition_id, plan_row.edition_id, plan_row.category_id,
      plan_row.stage_id, plan_row.division_id, plan_row.competition_group_id,
      new_revision_id, round_index, 1, 'Jornada ' || round_index::text,
      'draft', plan_row.rule_revision_id, target_server_sequence, target_actor_id
    );
    for pair_index in 1..(even_count / 2) loop
      left_entry := rotation[pair_index];
      right_entry := rotation[even_count - pair_index + 1];
      if left_entry is null or right_entry is null then
        insert into public.pachanga_competition_round_byes(
          schedule_revision_id, round_id, entry_id, leg_number, reason,
          server_sequence
        ) values (
          new_revision_id, round_id, coalesce(left_entry, right_entry), 1,
          'ODD_TEAM_COUNT', target_server_sequence
        );
      else
        if (pair_index = 1 and round_index % 2 = 0)
           or (pair_index > 1 and pair_index % 2 = 0) then
          home_entry := right_entry; away_entry := left_entry;
        else
          home_entry := left_entry; away_entry := right_entry;
        end if;
        pairing_key := least(home_entry, away_entry)::text || ':' || greatest(home_entry, away_entry)::text;
        insert into public.pachanga_competition_schedule_items(
          schedule_revision_id, round_id, home_entry_id, away_entry_id,
          pairing_key, leg_number, venue_status, status, server_sequence
        ) values (
          new_revision_id, round_id, home_entry, away_entry,
          pairing_key, 1, 'TBD', 'unassigned', target_server_sequence
        );
      end if;
    end loop;
    rotation := array[rotation[1]] || array[rotation[even_count]] || rotation[2:even_count - 1];
  end loop;

  if entry_count % 2 = 1 then
    loop
      balance_item_id := null;
      with sides as (
        select items.home_entry_id as entry_id, 1::integer as balance
        from public.pachanga_competition_schedule_items items
        where items.schedule_revision_id = new_revision_id and items.leg_number = 1
        union all
        select items.away_entry_id, -1::integer
        from public.pachanga_competition_schedule_items items
        where items.schedule_revision_id = new_revision_id and items.leg_number = 1
      ), balances as (
        select sides.entry_id, sum(sides.balance)::integer as balance
        from sides group by sides.entry_id
      )
      select items.id into balance_item_id
      from public.pachanga_competition_schedule_items items
      join balances home_balance on home_balance.entry_id = items.home_entry_id
      join balances away_balance on away_balance.entry_id = items.away_entry_id
      join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
      where items.schedule_revision_id = new_revision_id
        and items.leg_number = 1
        and home_balance.balance > 1
        and away_balance.balance < -1
      order by rounds.round_number, items.pairing_key, items.id
      limit 1;
      exit when balance_item_id is null;
      update public.pachanga_competition_schedule_items items set
        home_entry_id = items.away_entry_id,
        away_entry_id = items.home_entry_id,
        revision = items.revision + 1,
        server_sequence = target_server_sequence
      where items.id = balance_item_id;
    end loop;
  end if;

  if plan_row.legs = 2 then
    for round_index in 1..rounds_per_leg loop
      global_round := rounds_per_leg + round_index;
      second_round_id := gen_random_uuid();
      insert into public.pachanga_competition_rounds(
        id, competition_id, edition_id, category_id, stage_id, division_id,
        competition_group_id, schedule_revision_id, round_number, leg_number,
        display_name, status, rule_revision_id, server_sequence, created_by
      ) values (
        second_round_id, plan_row.competition_id, plan_row.edition_id,
        plan_row.category_id, plan_row.stage_id, plan_row.division_id,
        plan_row.competition_group_id, new_revision_id, global_round, 2,
        'Jornada ' || global_round::text, 'draft', plan_row.rule_revision_id,
        target_server_sequence, target_actor_id
      );
      insert into public.pachanga_competition_round_byes(
        schedule_revision_id, round_id, entry_id, leg_number, reason,
        server_sequence
      ) select new_revision_id, second_round_id, byes.entry_id, 2,
        byes.reason, target_server_sequence
      from public.pachanga_competition_round_byes byes
      join public.pachanga_competition_rounds rounds on rounds.id = byes.round_id
      where byes.schedule_revision_id = new_revision_id
        and rounds.round_number = round_index and rounds.leg_number = 1;
      insert into public.pachanga_competition_schedule_items(
        schedule_revision_id, round_id, home_entry_id, away_entry_id,
        pairing_key, leg_number, venue_status, status, server_sequence
      ) select new_revision_id, second_round_id, items.away_entry_id,
        items.home_entry_id, items.pairing_key, 2, 'TBD', 'unassigned',
        target_server_sequence
      from public.pachanga_competition_schedule_items items
      join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
      where items.schedule_revision_id = new_revision_id
        and rounds.round_number = round_index and rounds.leg_number = 1
      order by items.pairing_key, items.id;
    end loop;
  end if;

  for selected_item in
    select items.* from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.schedule_revision_id = new_revision_id
    order by (
      select count(*)
      from public.pachanga_team_availability_constraints constraints
      where constraints.status = 'active'
        and constraints.entry_id in (items.home_entry_id, items.away_entry_id)
    ) desc,
    (
      select count(*)
      from public.pachanga_team_schedule_preferences preferences
      where preferences.status = 'active'
        and preferences.entry_id in (items.home_entry_id, items.away_entry_id)
    ) desc,
    rounds.round_number, items.pairing_key, items.id
  loop
    -- A bounded repair may already have assigned this item before its turn.
    select items.* into selected_item
    from public.pachanga_competition_schedule_items items
    where items.id = selected_item.id;
    if selected_item.slot_id is not null then continue; end if;
    selected_slot := null;
    -- Hard legality is filtered set-wise. Preference scoring only needs a
    -- deterministic bounded horizon; the selected slot is fully rechecked.
    with eligible_slots as materialized (
      select slots.*
      from public.pachanga_competition_schedule_slots slots
      where slots.competition_id = plan_row.competition_id
        and slots.edition_id = plan_row.edition_id
        and slots.stage_id = plan_row.stage_id
        and slots.division_id is not distinct from plan_row.division_id
        and slots.competition_group_id is not distinct from plan_row.competition_group_id
        and slots.status <> 'retired'
        and extract(epoch from (slots.ends_at - slots.starts_at)) / 60 >= required_minutes
        and (edition_row.starts_at is null
          or (slots.starts_at at time zone slots.timezone)::date >= edition_row.starts_at)
        and (edition_row.ends_at is null
          or (slots.ends_at at time zone slots.timezone)::date <= edition_row.ends_at)
        and (window_start is null or slots.starts_at >= window_start)
        and (window_end is null or slots.ends_at <= window_end)
        and (not (policy ->> 'venueRequired')::boolean or slots.venue_id is not null)
        and not exists (
          select 1 from public.pachanga_competition_schedule_items used
          where used.schedule_revision_id = new_revision_id and used.slot_id = slots.id
        )
        and not exists (
          select 1
          from public.pachanga_team_availability_constraints constraints
          cross join lateral generate_series(
            (slots.starts_at at time zone constraints.timezone)::date - 1,
            (slots.ends_at at time zone constraints.timezone)::date,
            interval '1 day'
          ) candidate_day
          where constraints.entry_id in (selected_item.home_entry_id, selected_item.away_entry_id)
            and constraints.status = 'active'
            and extract(isodow from candidate_day)::integer = constraints.weekday
            and (constraints.valid_from_date is null or candidate_day::date >= constraints.valid_from_date)
            and (constraints.valid_until_date is null or candidate_day::date <= constraints.valid_until_date)
            and tstzrange(slots.starts_at, slots.ends_at, '[)') && tstzrange(
              (candidate_day::date + constraints.start_local_time) at time zone constraints.timezone,
              (candidate_day::date + constraints.end_local_time) at time zone constraints.timezone,
              '[)'
            )
        )
        and not exists (
          select 1 from public.pachanga_competition_schedule_items occupied
          where occupied.schedule_revision_id = new_revision_id
            and occupied.id <> selected_item.id
            and occupied.slot_id is not null
            and (occupied.home_entry_id in (selected_item.home_entry_id, selected_item.away_entry_id)
              or occupied.away_entry_id in (selected_item.home_entry_id, selected_item.away_entry_id))
            and tstzrange(occupied.scheduled_start, occupied.scheduled_end, '[)')
              && tstzrange(slots.starts_at, slots.ends_at, '[)')
        )
        and (
          minimum_rest <= interval '0 minutes'
          or not exists (
            select 1 from public.pachanga_competition_schedule_items occupied
            where occupied.schedule_revision_id = new_revision_id
              and occupied.id <> selected_item.id
              and occupied.slot_id is not null
              and (occupied.home_entry_id in (selected_item.home_entry_id, selected_item.away_entry_id)
                or occupied.away_entry_id in (selected_item.home_entry_id, selected_item.away_entry_id))
              and (
                (occupied.scheduled_end <= slots.starts_at
                  and slots.starts_at - occupied.scheduled_end < minimum_rest)
                or (slots.ends_at <= occupied.scheduled_start
                  and occupied.scheduled_start - slots.ends_at < minimum_rest)
              )
          )
        )
      order by slots.starts_at, slots.server_sequence, slots.id
      limit 64
    )
    select slots.* into selected_slot
    from eligible_slots slots
    order by (
      select coalesce(sum(preferences.weight), 0)
      from public.pachanga_team_schedule_preferences preferences
      where preferences.status = 'active'
        and preferences.entry_id in (selected_item.home_entry_id, selected_item.away_entry_id)
        and extract(isodow from slots.starts_at at time zone preferences.timezone)::integer = preferences.weekday
        and (slots.starts_at at time zone preferences.timezone)::time < preferences.end_local_time
        and (slots.ends_at at time zone preferences.timezone)::time > preferences.start_local_time
    ) desc,
    slots.starts_at,
    encode(extensions.digest(convert_to(
      target_seed || ':' || selected_item.pairing_key || ':'
      || selected_item.leg_number::text || ':' || slots.id::text,
      'UTF8'
    ), 'sha256'), 'hex'),
    slots.id
    limit 1;
    if selected_slot.id is not null and not (
      private.pachanga_league_schedule_slot_check_v1(
        new_revision_id, selected_item.home_entry_id, selected_item.away_entry_id,
        selected_slot.id, array[selected_item.id]
      ) ->> 'eligible'
    )::boolean then
      raise exception 'SCHEDULE_ASSIGNMENT_ELIGIBILITY_DRIFT' using errcode = 'XX000';
    end if;
    if selected_slot.id is null then
      repair_item_id := null;
      repair_source_slot_id := null;
      repair_target_slot_id := null;
      select occupied.id, occupied_slot.id, free_slot.id
        into repair_item_id, repair_source_slot_id, repair_target_slot_id
      from public.pachanga_competition_schedule_items occupied
      join public.pachanga_competition_schedule_slots occupied_slot
        on occupied_slot.id = occupied.slot_id
      cross join public.pachanga_competition_schedule_slots free_slot
      where occupied.schedule_revision_id = new_revision_id
        and occupied.slot_id is not null
        and occupied.id <> selected_item.id
        and occupied.home_entry_id not in (selected_item.home_entry_id, selected_item.away_entry_id)
        and occupied.away_entry_id not in (selected_item.home_entry_id, selected_item.away_entry_id)
        and free_slot.competition_id = plan_row.competition_id
        and free_slot.edition_id = plan_row.edition_id
        and free_slot.stage_id = plan_row.stage_id
        and free_slot.division_id is not distinct from plan_row.division_id
        and free_slot.competition_group_id is not distinct from plan_row.competition_group_id
        and free_slot.status <> 'retired'
        and not exists (
          select 1 from public.pachanga_competition_schedule_items used
          where used.schedule_revision_id = new_revision_id and used.slot_id = free_slot.id
        )
        and (private.pachanga_league_schedule_slot_check_v1(
          new_revision_id, selected_item.home_entry_id, selected_item.away_entry_id,
          occupied_slot.id, array[selected_item.id, occupied.id]
        ) ->> 'eligible')::boolean
        and (private.pachanga_league_schedule_slot_check_v1(
          new_revision_id, occupied.home_entry_id, occupied.away_entry_id,
          free_slot.id, array[selected_item.id, occupied.id]
        ) ->> 'eligible')::boolean
      order by free_slot.starts_at, occupied_slot.starts_at,
        encode(extensions.digest(convert_to(
          target_seed || ':repair:' || selected_item.id::text || ':'
          || occupied.id::text || ':' || free_slot.id::text,
          'UTF8'
        ), 'sha256'), 'hex'),
        occupied.id, free_slot.id
      limit 1;
      if repair_item_id is null then
        raise exception 'SCHEDULE_UNSATISFIABLE item=% search=bounded_repair_exhausted',
          selected_item.id using errcode = '22023';
      end if;
      select * into repair_item from public.pachanga_competition_schedule_items items
      where items.id = repair_item_id;
      select * into repair_source_slot from public.pachanga_competition_schedule_slots slots
      where slots.id = repair_source_slot_id;
      select * into repair_target_slot from public.pachanga_competition_schedule_slots slots
      where slots.id = repair_target_slot_id;
      update public.pachanga_competition_schedule_items items set
        slot_id = null, scheduled_start = null, scheduled_end = null,
        timezone = null, venue_id = null, venue_label = null,
        venue_status = 'TBD', status = 'unassigned',
        revision = items.revision + 1,
        server_sequence = target_server_sequence
      where items.id = repair_item.id;
      update public.pachanga_competition_schedule_items items set
        slot_id = repair_source_slot.id,
        scheduled_start = repair_source_slot.starts_at,
        scheduled_end = repair_source_slot.ends_at,
        timezone = repair_source_slot.timezone,
        venue_id = repair_source_slot.venue_id,
        venue_label = repair_source_slot.venue_label,
        venue_status = case when repair_source_slot.venue_id is null then 'TBD' else 'CONFIRMED' end,
        status = 'assigned', revision = items.revision + 1,
        server_sequence = target_server_sequence
      where items.id = selected_item.id;
      update public.pachanga_competition_schedule_items items set
        slot_id = repair_target_slot.id,
        scheduled_start = repair_target_slot.starts_at,
        scheduled_end = repair_target_slot.ends_at,
        timezone = repair_target_slot.timezone,
        venue_id = repair_target_slot.venue_id,
        venue_label = repair_target_slot.venue_label,
        venue_status = case when repair_target_slot.venue_id is null then 'TBD' else 'CONFIRMED' end,
        status = 'assigned', revision = items.revision + 1,
        server_sequence = target_server_sequence
      where items.id = repair_item.id;
      continue;
    end if;
    update public.pachanga_competition_schedule_items items set
      slot_id = selected_slot.id,
      scheduled_start = selected_slot.starts_at,
      scheduled_end = selected_slot.ends_at,
      timezone = selected_slot.timezone,
      venue_id = selected_slot.venue_id,
      venue_label = selected_slot.venue_label,
      venue_status = case when selected_slot.venue_id is null then 'TBD' else 'CONFIRMED' end,
      status = 'assigned',
      revision = items.revision + 1,
      server_sequence = target_server_sequence
    where items.id = selected_item.id;
  end loop;

  update public.pachanga_competition_rounds rounds set
    starts_at = source.minimum_start,
    ends_at = source.maximum_end,
    revision = rounds.revision + 1,
    server_sequence = target_server_sequence
  from (
    select items.round_id, min(items.scheduled_start) as minimum_start,
      max(items.scheduled_end) as maximum_end
    from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = new_revision_id group by items.round_id
  ) source where source.round_id = rounds.id;
  perform private.pachanga_league_schedule_rebuild_conflicts_v1(new_revision_id, target_server_sequence);
  perform private.pachanga_league_schedule_quality_v1(new_revision_id, target_server_sequence);
  return new_revision_id;
end;
$$;

revoke all on function private.pachanga_league_schedule_generate_revision_v1(uuid, text, text, uuid, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_validate_revision_v1(
  target_schedule_revision_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare inputs jsonb;
declare conflicts jsonb;
declare quality jsonb;
declare entry_count integer;
declare even_count integer;
declare expected_rounds integer;
declare expected_pairs integer;
declare expected_byes integer;
declare actual_rounds integer;
declare actual_pairs integer;
declare actual_byes integer;
declare unassigned integer;
declare hard_count integer;
declare computed_status text;
declare validation_summary jsonb;
begin
  select * into revision_row from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = target_schedule_revision_id for update;
  if not found then raise exception 'SCHEDULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = revision_row.schedule_plan_id for update;
  if plan_row.current_revision_id <> revision_row.id then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if plan_row.status = 'published' then
    raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
  end if;
  inputs := private.pachanga_league_schedule_inputs_v1(plan_row.id, revision_row.seed);
  entry_count := (inputs ->> 'entryCount')::integer;
  if inputs ->> 'inputChecksum' <> revision_row.input_checksum then
    computed_status := 'STALE_INPUT';
    conflicts := jsonb_build_object('hardViolations', 1, 'items', jsonb_build_array(
      jsonb_build_object('type', 'RULE_REVISION_MISMATCH', 'summary', 'Las entradas autoritativas han cambiado.')
    ));
    quality := jsonb_build_object('softScore', revision_row.quality_score);
  else
    conflicts := private.pachanga_league_schedule_rebuild_conflicts_v1(
      revision_row.id, target_server_sequence
    );
    quality := private.pachanga_league_schedule_quality_v1(
      revision_row.id, target_server_sequence
    );
    hard_count := (conflicts ->> 'hardViolations')::integer;
    computed_status := case when hard_count = 0 then 'VALID' else 'INVALID' end;
  end if;
  even_count := case when entry_count % 2 = 0 then entry_count else entry_count + 1 end;
  expected_rounds := (even_count - 1) * plan_row.legs;
  expected_pairs := (entry_count * (entry_count - 1) / 2) * plan_row.legs;
  expected_byes := case when entry_count % 2 = 1 then entry_count * plan_row.legs else 0 end;
  select count(*) into actual_rounds from public.pachanga_competition_rounds rounds
  where rounds.schedule_revision_id = revision_row.id;
  select count(*) into actual_pairs from public.pachanga_competition_schedule_items items
  where items.schedule_revision_id = revision_row.id;
  select count(*) into actual_byes from public.pachanga_competition_round_byes byes
  where byes.schedule_revision_id = revision_row.id;
  select count(*) into unassigned from public.pachanga_competition_schedule_items items
  where items.schedule_revision_id = revision_row.id and items.slot_id is null;
  if actual_rounds <> expected_rounds or actual_pairs <> expected_pairs
     or actual_byes <> expected_byes or unassigned <> 0 then
    computed_status := case when computed_status = 'STALE_INPUT' then computed_status else 'INVALID' end;
  end if;
  if plan_row.legs = 2 and exists (
    select 1
    from public.pachanga_competition_schedule_items first_leg
    where first_leg.schedule_revision_id = revision_row.id and first_leg.leg_number = 1
      and not exists (
        select 1 from public.pachanga_competition_schedule_items second_leg
        where second_leg.schedule_revision_id = revision_row.id
          and second_leg.leg_number = 2
          and second_leg.pairing_key = first_leg.pairing_key
          and second_leg.home_entry_id = first_leg.away_entry_id
          and second_leg.away_entry_id = first_leg.home_entry_id
      )
  ) then computed_status := 'INVALID'; end if;
  validation_summary := jsonb_build_object(
    'status', computed_status,
    'hardViolations', coalesce((conflicts ->> 'hardViolations')::integer, 0),
    'expectedRounds', expected_rounds, 'roundCount', actual_rounds,
    'expectedPairs', expected_pairs, 'pairCount', actual_pairs,
    'expectedByes', expected_byes, 'byeCount', actual_byes,
    'unassignedItems', unassigned, 'conflicts', conflicts, 'quality', quality,
    'inputChecksum', inputs ->> 'inputChecksum'
  );
  insert into public.pachanga_competition_schedule_validations(
    schedule_revision_id, input_checksum, status, hard_violation_count,
    unassigned_item_count, pair_count, round_count, bye_count, summary,
    validated_by, server_sequence
  ) values (
    revision_row.id, inputs ->> 'inputChecksum', computed_status,
    coalesce((conflicts ->> 'hardViolations')::integer, 0), unassigned,
    actual_pairs, actual_rounds, actual_byes, validation_summary,
    target_actor_id, target_server_sequence
  );
  update public.pachanga_competition_schedule_revisions revisions set
    validation_status = computed_status,
    status = case when computed_status = 'VALID' then 'validated' else 'generated' end,
    validated_by = target_actor_id,
    validated_at = clock_timestamp(),
    revision = revisions.revision + 1,
    server_sequence = target_server_sequence
  where revisions.id = revision_row.id;
  update public.pachanga_competition_schedule_items items set
    status = case when computed_status = 'VALID' then 'validated'
      when items.slot_id is null then 'unassigned' else 'assigned' end,
    revision = items.revision + 1,
    server_sequence = target_server_sequence
  where items.schedule_revision_id = revision_row.id;
  return validation_summary;
end;
$$;

revoke all on function private.pachanga_league_schedule_validate_revision_v1(uuid, uuid, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_publish_v1(
  target_schedule_plan_id uuid,
  target_actor_id uuid,
  target_operation_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare stage_row public.pachanga_competition_stages%rowtype;
declare item_row record;
declare inputs jsonb;
declare canonical_id uuid;
declare context_id uuid;
declare canonical_ids jsonb := '[]'::jsonb;
declare context_ids jsonb := '[]'::jsonb;
declare notification_count integer := 0;
begin
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id for update;
  if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  if plan_row.status = 'published' then
    raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
  end if;
  if plan_row.current_revision_id is null then
    raise exception 'SCHEDULE_REVISION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into revision_row from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = plan_row.current_revision_id for update;
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = plan_row.edition_id for update;
  select * into stage_row from public.pachanga_competition_stages stages
  where stages.id = plan_row.stage_id for update;
  if revision_row.status <> 'validated' or revision_row.validation_status <> 'VALID'
     or plan_row.status <> 'validated' then
    raise exception 'SCHEDULE_NOT_VALIDATED' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.pachanga_competition_rule_revisions rule_revisions
    where rule_revisions.id = plan_row.rule_revision_id
      and rule_revisions.status = 'frozen'
  ) then
    raise exception 'SCHEDULE_RULE_REVISION_NOT_FROZEN' using errcode = '22023';
  end if;
  inputs := private.pachanga_league_schedule_inputs_v1(plan_row.id, revision_row.seed);
  if inputs ->> 'inputChecksum' <> revision_row.input_checksum then
    raise exception 'STALE_INPUT' using errcode = 'PT409';
  end if;
  if exists (
    select 1 from private.pachanga_competition_schedule_conflicts conflicts
    where conflicts.schedule_revision_id = revision_row.id
      and conflicts.status = 'active' and conflicts.severity = 'hard'
  ) or exists (
    select 1 from public.pachanga_competition_schedule_items items
    where items.schedule_revision_id = revision_row.id
      and (items.status <> 'validated' or items.slot_id is null)
  ) then raise exception 'SCHEDULE_NOT_VALID' using errcode = '22023'; end if;

  for item_row in
    select items.*, rounds.round_number
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.schedule_revision_id = revision_row.id
    order by rounds.round_number, items.pairing_key, items.id
    for update of items
  loop
    select bindings.canonical_match_id into canonical_id
    from public.pachanga_canonical_match_bindings bindings
    where bindings.source_kind = 'competition_generated'
      and bindings.source_group_id is null
      and bindings.source_id = item_row.id::text
      and bindings.binding_status = 'active'
    order by bindings.server_sequence desc, bindings.id desc
    limit 1;
    if canonical_id is null then
      canonical_id := gen_random_uuid();
      insert into public.pachanga_canonical_matches(
        id, status, revision, server_sequence, created_by
      ) values (canonical_id, 'active', 1, target_server_sequence, target_actor_id);
      insert into public.pachanga_canonical_match_bindings(
        canonical_match_id, source_kind, source_group_id, source_id,
        relation_kind, binding_status, revision, server_sequence, created_by
      ) values (
        canonical_id, 'competition_generated', null, item_row.id::text,
        'authoritative_source', 'active', 1, target_server_sequence, target_actor_id
      );
    end if;
    select contexts.id into context_id
    from public.pachanga_competition_match_contexts contexts
    where contexts.schedule_item_id = item_row.id and contexts.status = 'scheduled'
    order by contexts.server_sequence desc, contexts.id desc
    limit 1;
    if context_id is null then
      context_id := gen_random_uuid();
      insert into public.pachanga_competition_match_contexts(
        id, canonical_match_id, competition_id, edition_id, category_id,
        stage_id, division_id, competition_group_id, round_id, schedule_item_id,
        home_entry_id, away_entry_id, rule_revision_id, slot_id,
        scheduled_start, scheduled_end, timezone, venue_id, venue_label,
        venue_status, source_kind, status, revision, server_sequence, created_by
      ) values (
        context_id, canonical_id, plan_row.competition_id, plan_row.edition_id,
        plan_row.category_id, plan_row.stage_id, plan_row.division_id,
        plan_row.competition_group_id, item_row.round_id, item_row.id,
        item_row.home_entry_id, item_row.away_entry_id, plan_row.rule_revision_id,
        item_row.slot_id, item_row.scheduled_start, item_row.scheduled_end,
        item_row.timezone, item_row.venue_id, item_row.venue_label,
        item_row.venue_status, 'COMPETITION_GENERATED', 'scheduled', 1,
        target_server_sequence, target_actor_id
      );
    end if;
    update public.pachanga_competition_schedule_items items set
      canonical_match_id = canonical_id,
      competition_match_context_id = context_id,
      status = 'published',
      revision = items.revision + 1,
      server_sequence = target_server_sequence
    where items.id = item_row.id;
    update public.pachanga_competition_schedule_slots slots set
      status = 'assigned', revision = slots.revision + 1,
      server_sequence = target_server_sequence
    where slots.id = item_row.slot_id and slots.status = 'available';
    canonical_ids := canonical_ids || jsonb_build_array(canonical_id);
    context_ids := context_ids || jsonb_build_array(context_id);
  end loop;
  update public.pachanga_competition_rounds rounds set
    status = 'published', published_at = clock_timestamp(),
    revision = rounds.revision + 1, server_sequence = target_server_sequence
  where rounds.schedule_revision_id = revision_row.id;
  update public.pachanga_competition_schedule_revisions revisions set
    status = 'published', validation_status = 'VALID',
    published_by = target_actor_id, published_at = clock_timestamp(),
    revision = revisions.revision + 1, server_sequence = target_server_sequence
  where revisions.id = revision_row.id;
  update public.pachanga_competition_schedule_plans plans set
    status = 'published', published_at = clock_timestamp(),
    revision = plans.revision + 1, server_sequence = target_server_sequence
  where plans.id = plan_row.id;
  update public.pachanga_competition_editions editions set
    status = 'scheduled', revision = editions.revision + 1,
    server_sequence = target_server_sequence
  where editions.id = edition_row.id and editions.status = 'registration_closed';
  notification_count := private.pachanga_league_schedule_notify_published_v1(
    plan_row.id, target_operation_id
  );
  return jsonb_build_object(
    'canonicalMatchIds', canonical_ids,
    'contextIds', context_ids,
    'canonicalMatchCount', jsonb_array_length(canonical_ids),
    'contextCount', jsonb_array_length(context_ids),
    'notificationCount', notification_count
  );
end;
$$;

revoke all on function private.pachanga_league_schedule_publish_v1(uuid, uuid, uuid, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_assert_authority_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare organizer_id uuid;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  if competition_row.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if not private.pachanga_competition_can_v1(
    target_competition_id, target_actor_id, target_capability
  ) then raise exception 'COMPETITION_SCHEDULE_MANAGER_REQUIRED' using errcode = '42501'; end if;
  organizer_id := case when competition_row.organizer_kind = 'CLUB'
    then competition_row.organizer_club_id else competition_row.organizer_group_id end;
  if not (
    private.pachanga_competition_active_entitlement_v2(
      competition_row.organizer_kind, organizer_id, 'competition_schedule'
    ) or private.pachanga_competition_active_entitlement_v2(
      competition_row.organizer_kind, organizer_id, 'competition_manage'
    )
  ) then raise exception 'COMPETITION_SCHEDULE_ENTITLEMENT_REQUIRED' using errcode = '42501'; end if;
end;
$$;

revoke all on function private.pachanga_league_schedule_assert_authority_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function public.command_pachanga_league_scheduling_v1(
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
declare actor_id uuid := (select auth.uid());
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare metadata jsonb;
declare request_hash text;
declare replay jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare confirmed_revision bigint;
declare competition_id uuid;
declare plan_id uuid;
declare revision_id uuid;
declare source_revision_id uuid;
declare source_item_a public.pachanga_competition_schedule_items%rowtype;
declare source_item_b public.pachanga_competition_schedule_items%rowtype;
declare clone_item_a public.pachanga_competition_schedule_items%rowtype;
declare clone_item_b public.pachanga_competition_schedule_items%rowtype;
declare source_round public.pachanga_competition_rounds%rowtype;
declare clone_round public.pachanga_competition_rounds%rowtype;
declare slot_a public.pachanga_competition_schedule_slots%rowtype;
declare slot_b public.pachanga_competition_schedule_slots%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare stage_row public.pachanga_competition_stages%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare category_row public.pachanga_competition_categories%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare policy jsonb;
declare inputs jsonb;
declare validation jsonb;
declare publication jsonb;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare invalidations jsonb := '[]'::jsonb;
declare seed_value text;
declare reason_code text;
declare timezone_value text;
declare starts_value timestamptz;
declare ends_value timestamptz;
declare local_time_value time;
declare local_date_start date;
declare local_date_end date;
declare weekday_values integer[];
declare duration_minutes integer;
declare generated_date date;
declare new_slot_id uuid;
declare created_slot_ids jsonb := '[]'::jsonb;
declare eligibility jsonb;
declare notification_targets jsonb;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or normalized_action = '' then
    raise exception 'INVALID_LEAGUE_SCHEDULING_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(payload) > 40000 then
    raise exception 'INVALID_LEAGUE_SCHEDULING_PAYLOAD' using errcode = '22023';
  end if;
  if normalized_action in (
    'result.submit', 'standing.rebuild', 'match.postpone', 'match.suspend',
    'discipline.create', 'field.reserve', 'lineup.create', 'attendance.confirm'
  ) then raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000'; end if;
  metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91405));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, 'authenticated', normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  reason_code := left(coalesce(nullif(trim(payload ->> 'reasonCode'), ''), normalized_action), 120);

  if normalized_action = 'schedule_plan.create' then
    perform private.pachanga_league_schedule_assert_flags_v1();
    select * into stage_row from public.pachanga_competition_stages stages
    where stages.id = aggregate_id for update;
    if not found then raise exception 'STAGE_NOT_FOUND' using errcode = 'P0002'; end if;
    if stage_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if stage_row.stage_type not in ('LEAGUE_STAGE', 'GROUP_STAGE', 'SPLIT') then
      raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = stage_row.edition_id for update;
    if edition_row.status <> 'registration_closed' then
      raise exception 'REGISTRATION_MUST_BE_CLOSED' using errcode = '22023';
    end if;
    select * into competition_row from public.pachanga_competitions competitions
    where competitions.id = edition_row.competition_id;
    competition_id := competition_row.id;
    perform private.pachanga_league_schedule_assert_authority_v1(competition_id, actor_id, 'schedule_manage');
    select * into category_row from public.pachanga_competition_categories categories
    where categories.id = (payload ->> 'categoryId')::uuid
      and categories.edition_id = edition_row.id;
    if not found then raise exception 'CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;
    if nullif(payload ->> 'ruleRevisionId', '')::uuid is distinct from stage_row.rule_revision_id
       or stage_row.rule_revision_id is distinct from edition_row.rule_revision_id then
      raise exception 'RULE_REVISION_MISMATCH' using errcode = '22023';
    end if;
    policy := private.pachanga_league_schedule_policy_v1(stage_row.rule_revision_id);
    if (payload ->> 'legs')::integer <> (policy ->> 'legs')::integer then
      raise exception 'RULE_REVISION_MISMATCH' using errcode = '22023';
    end if;
    plan_id := gen_random_uuid();
    insert into public.pachanga_competition_schedule_plans(
      id, competition_id, edition_id, category_id, stage_id, division_id,
      competition_group_id, rule_revision_id, engine_version, legs,
      entry_count, status, revision, server_sequence, created_by
    ) values (
      plan_id, competition_id, edition_row.id, category_row.id, stage_row.id,
      nullif(payload ->> 'divisionId', '')::uuid,
      nullif(payload ->> 'groupId', '')::uuid, stage_row.rule_revision_id,
      'league-round-robin-v1', (payload ->> 'legs')::smallint,
      0, 'draft', 1, sequence_value, actor_id
    );
    inputs := private.pachanga_league_schedule_inputs_v1(plan_id, 'plan:' || plan_id::text);
    update public.pachanga_competition_schedule_plans plans
    set entry_count = (inputs ->> 'entryCount')::smallint
    where plans.id = plan_id returning plans.revision into confirmed_revision;
    snapshot := private.pachanga_league_schedule_revision_snapshot_v1(plan_id, true);
    event_payload := jsonb_build_object('planId', plan_id, 'entryCount', inputs ->> 'entryCount');

  elsif normalized_action in (
    'schedule_slot.create', 'schedule_slot.bulk_create',
    'schedule_slot.update', 'schedule_slot.retire'
  ) then
    perform private.pachanga_league_schedule_assert_flags_v1(
      false,
      normalized_action in ('schedule_slot.update', 'schedule_slot.retire'),
      false,
      false
    );
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = aggregate_id for update;
    if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    plan_id := plan_row.id; competition_id := plan_row.competition_id;
    if plan_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if plan_row.status in ('published', 'cancelled') then
      raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
    end if;
    perform private.pachanga_league_schedule_assert_authority_v1(competition_id, actor_id, 'schedule_manage');
    if normalized_action <> 'schedule_slot.retire' then
      timezone_value := trim(coalesce(payload ->> 'timezone', ''));
      if not exists (select 1 from pg_catalog.pg_timezone_names zones where zones.name = timezone_value) then
        raise exception 'INVALID_TIMEZONE' using errcode = '22023';
      end if;
    end if;
    if normalized_action = 'schedule_slot.create' then
      starts_value := (payload ->> 'startsAt')::timestamptz;
      ends_value := (payload ->> 'endsAt')::timestamptz;
      if ends_value <= starts_value then raise exception 'INVALID_SLOT_RANGE' using errcode = '22023'; end if;
      new_slot_id := gen_random_uuid();
      insert into public.pachanga_competition_schedule_slots(
        id, competition_id, edition_id, stage_id, division_id,
        competition_group_id, starts_at, ends_at, timezone, venue_id,
        venue_label, resource_key, status, server_sequence, created_by
      ) values (
        new_slot_id, plan_row.competition_id, plan_row.edition_id, plan_row.stage_id,
        plan_row.division_id, plan_row.competition_group_id, starts_value, ends_value,
        timezone_value, nullif(payload ->> 'venueId', '')::uuid,
        nullif(left(trim(coalesce(payload ->> 'venueLabel', '')), 160), ''),
        nullif(left(trim(coalesce(payload ->> 'resourceKey', '')), 160), ''),
        'available', sequence_value, actor_id
      );
      created_slot_ids := jsonb_build_array(new_slot_id);
    elsif normalized_action = 'schedule_slot.bulk_create' then
      local_date_start := (payload ->> 'startDate')::date;
      local_date_end := (payload ->> 'endDate')::date;
      local_time_value := (payload ->> 'localTime')::time;
      duration_minutes := (payload ->> 'durationMinutes')::integer;
      select array_agg(value::integer order by value::integer) into weekday_values
      from jsonb_array_elements_text(payload -> 'weekdays') weekday(value);
      if local_date_end < local_date_start or local_date_end - local_date_start > 370
         or duration_minutes < 1 or duration_minutes > 600
         or weekday_values is null
         or exists (select 1 from unnest(weekday_values) value where value not between 1 and 7) then
        raise exception 'INVALID_WEEKLY_SLOT_PATTERN' using errcode = '22023';
      end if;
      for generated_date in
        select value::date from generate_series(local_date_start, local_date_end, interval '1 day') value
        where extract(isodow from value)::integer = any(weekday_values)
        order by value
      loop
        starts_value := (generated_date + local_time_value) at time zone timezone_value;
        ends_value := starts_value + make_interval(mins => duration_minutes);
        new_slot_id := gen_random_uuid();
        insert into public.pachanga_competition_schedule_slots(
          id, competition_id, edition_id, stage_id, division_id,
          competition_group_id, starts_at, ends_at, timezone, venue_id,
          venue_label, resource_key, status, server_sequence, created_by
        ) values (
          new_slot_id, plan_row.competition_id, plan_row.edition_id,
          plan_row.stage_id, plan_row.division_id, plan_row.competition_group_id,
          starts_value, ends_value, timezone_value,
          nullif(payload ->> 'venueId', '')::uuid,
          nullif(left(trim(coalesce(payload ->> 'venueLabel', '')), 160), ''),
          nullif(left(trim(coalesce(payload ->> 'resourceKey', '')), 160), ''),
          'available', sequence_value, actor_id
        );
        created_slot_ids := created_slot_ids || jsonb_build_array(new_slot_id);
      end loop;
      if jsonb_array_length(created_slot_ids) = 0 then
        raise exception 'WEEKLY_SLOT_PATTERN_EMPTY' using errcode = '22023';
      end if;
    else
      select * into slot_a
      from public.pachanga_competition_schedule_slots slots
      where slots.id = (payload ->> 'slotId')::uuid
        and slots.competition_id = plan_row.competition_id
        and slots.edition_id = plan_row.edition_id
        and slots.stage_id = plan_row.stage_id
        and slots.division_id is not distinct from plan_row.division_id
        and slots.competition_group_id is not distinct from plan_row.competition_group_id
      for update;
      if not found then raise exception 'SCHEDULE_SLOT_NOT_FOUND' using errcode = 'P0002'; end if;
      if exists (
        select 1 from public.pachanga_competition_schedule_items items
        where items.slot_id = slot_a.id
      ) then raise exception 'SCHEDULE_SLOT_IN_USE' using errcode = 'PT409'; end if;
      if normalized_action = 'schedule_slot.update' then
        if slot_a.status = 'retired' then
          raise exception 'SCHEDULE_SLOT_RETIRED' using errcode = 'PT409';
        end if;
        starts_value := (payload ->> 'startsAt')::timestamptz;
        ends_value := (payload ->> 'endsAt')::timestamptz;
        if ends_value <= starts_value then raise exception 'INVALID_SLOT_RANGE' using errcode = '22023'; end if;
        update public.pachanga_competition_schedule_slots slots set
          starts_at = starts_value,
          ends_at = ends_value,
          timezone = timezone_value,
          venue_id = nullif(payload ->> 'venueId', '')::uuid,
          venue_label = nullif(left(trim(coalesce(payload ->> 'venueLabel', '')), 160), ''),
          resource_key = nullif(left(trim(coalesce(payload ->> 'resourceKey', '')), 160), ''),
          revision = slots.revision + 1,
          server_sequence = sequence_value
        where slots.id = slot_a.id;
      else
        update public.pachanga_competition_schedule_slots slots set
          status = 'retired', retired_by = actor_id, retired_at = confirmed_at,
          revision = slots.revision + 1, server_sequence = sequence_value
        where slots.id = slot_a.id and slots.status <> 'retired';
      end if;
      created_slot_ids := jsonb_build_array(slot_a.id);
    end if;
    update public.pachanga_competition_schedule_plans plans set
      status = case when plans.status = 'validated' then 'generated' else plans.status end,
      revision = plans.revision + 1, server_sequence = sequence_value
    where plans.id = plan_row.id returning plans.revision into confirmed_revision;
    snapshot := private.pachanga_league_schedule_revision_snapshot_v1(plan_row.id, true)
      || jsonb_build_object('affectedSlotIds', created_slot_ids);
    event_payload := jsonb_build_object('slotIds', created_slot_ids, 'action', normalized_action);

  elsif normalized_action in ('schedule.generate', 'schedule.regenerate') then
    perform private.pachanga_league_schedule_assert_flags_v1(true, false, false, false);
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = aggregate_id for update;
    if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    plan_id := plan_row.id; competition_id := plan_row.competition_id;
    if plan_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if normalized_action = 'schedule.regenerate' and plan_row.current_revision_id is null then
      raise exception 'SCHEDULE_REVISION_NOT_FOUND' using errcode = 'P0002';
    end if;
    perform private.pachanga_league_schedule_assert_authority_v1(competition_id, actor_id, 'schedule_manage');
    seed_value := left(coalesce(nullif(trim(payload ->> 'seed'), ''), operation_id::text), 160);
    revision_id := private.pachanga_league_schedule_generate_revision_v1(
      plan_row.id, seed_value,
      case when normalized_action = 'schedule.generate' and plan_row.current_revision_id is null
        then 'generated' else 'regenerated' end,
      actor_id, sequence_value
    );
    inputs := private.pachanga_league_schedule_inputs_v1(plan_row.id, seed_value);
    update public.pachanga_competition_schedule_plans plans set
      current_revision_id = revision_id, entry_count = (inputs ->> 'entryCount')::smallint,
      status = 'generated', revision = plans.revision + 1,
      server_sequence = sequence_value
    where plans.id = plan_row.id returning plans.revision into confirmed_revision;
    snapshot := private.pachanga_league_schedule_revision_snapshot_v1(plan_row.id, true);
    event_payload := jsonb_build_object('scheduleRevisionId', revision_id, 'seed', seed_value);

  elsif normalized_action in (
    'schedule_item.move_slot', 'schedule_item.swap_slot',
    'schedule_item.swap_home_away', 'round.rename'
  ) then
    perform private.pachanga_league_schedule_assert_flags_v1(true, true, false, false);
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = aggregate_id for update;
    if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    plan_id := plan_row.id; competition_id := plan_row.competition_id;
    if plan_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if plan_row.current_revision_id is null then raise exception 'SCHEDULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.status = 'published' then
      raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
    end if;
    perform private.pachanga_league_schedule_assert_authority_v1(competition_id, actor_id, 'schedule_manage');
    source_revision_id := plan_row.current_revision_id;
    revision_id := private.pachanga_league_schedule_clone_revision_v1(
      plan_row.id, source_revision_id,
      case normalized_action
        when 'schedule_item.move_slot' then 'manual_move'
        when 'schedule_item.swap_slot' then 'manual_swap'
        when 'schedule_item.swap_home_away' then 'home_away_swap'
        else 'round_rename' end,
      actor_id, sequence_value
    );
    if normalized_action = 'round.rename' then
      select * into source_round from public.pachanga_competition_rounds rounds
      where rounds.id = (payload ->> 'roundId')::uuid
        and rounds.schedule_revision_id = source_revision_id;
      if not found then raise exception 'ROUND_NOT_FOUND' using errcode = 'P0002'; end if;
      select * into clone_round from public.pachanga_competition_rounds rounds
      where rounds.schedule_revision_id = revision_id
        and rounds.round_number = source_round.round_number;
      if length(trim(coalesce(payload ->> 'displayName', ''))) not between 1 and 120 then
        raise exception 'INVALID_ROUND_NAME' using errcode = '22023';
      end if;
      update public.pachanga_competition_rounds rounds set
        display_name = trim(payload ->> 'displayName'),
        revision = rounds.revision + 1, server_sequence = sequence_value
      where rounds.id = clone_round.id;
    else
      select * into source_item_a from public.pachanga_competition_schedule_items items
      where items.id = (payload ->> 'itemId')::uuid
        and items.schedule_revision_id = source_revision_id;
      if not found then raise exception 'SCHEDULE_ITEM_NOT_FOUND' using errcode = 'P0002'; end if;
      select * into clone_item_a from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = revision_id
        and items.pairing_key = source_item_a.pairing_key
        and items.leg_number = source_item_a.leg_number;
      if normalized_action = 'schedule_item.move_slot' then
        select * into slot_a from public.pachanga_competition_schedule_slots slots
        where slots.id = (payload ->> 'slotId')::uuid and slots.status <> 'retired';
        if not found then raise exception 'SCHEDULE_SLOT_NOT_FOUND' using errcode = 'P0002'; end if;
        eligibility := private.pachanga_league_schedule_slot_check_v1(
          revision_id, clone_item_a.home_entry_id, clone_item_a.away_entry_id,
          slot_a.id, array[clone_item_a.id]
        );
        if not (eligibility ->> 'eligible')::boolean then
          raise exception 'SCHEDULE_UNSATISFIABLE %', eligibility -> 'reasons' using errcode = '22023';
        end if;
        update public.pachanga_competition_schedule_items items set
          slot_id = slot_a.id, scheduled_start = slot_a.starts_at,
          scheduled_end = slot_a.ends_at, timezone = slot_a.timezone,
          venue_id = slot_a.venue_id, venue_label = slot_a.venue_label,
          venue_status = case when slot_a.venue_id is null then 'TBD' else 'CONFIRMED' end,
          status = 'assigned', revision = items.revision + 1,
          server_sequence = sequence_value
        where items.id = clone_item_a.id;
      elsif normalized_action = 'schedule_item.swap_slot' then
        select * into source_item_b from public.pachanga_competition_schedule_items items
        where items.id = (payload ->> 'otherItemId')::uuid
          and items.schedule_revision_id = source_revision_id;
        if not found or source_item_b.id = source_item_a.id then
          raise exception 'SCHEDULE_ITEM_NOT_FOUND' using errcode = 'P0002';
        end if;
        select * into clone_item_b from public.pachanga_competition_schedule_items items
        where items.schedule_revision_id = revision_id
          and items.pairing_key = source_item_b.pairing_key
          and items.leg_number = source_item_b.leg_number;
        select * into slot_a from public.pachanga_competition_schedule_slots slots where slots.id = source_item_a.slot_id;
        select * into slot_b from public.pachanga_competition_schedule_slots slots where slots.id = source_item_b.slot_id;
        if slot_a.id is null or slot_b.id is null then raise exception 'SCHEDULE_SLOT_NOT_FOUND' using errcode = 'P0002'; end if;
        eligibility := private.pachanga_league_schedule_slot_check_v1(
          revision_id, clone_item_a.home_entry_id, clone_item_a.away_entry_id,
          slot_b.id, array[clone_item_a.id, clone_item_b.id]
        );
        if not (eligibility ->> 'eligible')::boolean then
          raise exception 'SCHEDULE_UNSATISFIABLE %', eligibility -> 'reasons' using errcode = '22023';
        end if;
        eligibility := private.pachanga_league_schedule_slot_check_v1(
          revision_id, clone_item_b.home_entry_id, clone_item_b.away_entry_id,
          slot_a.id, array[clone_item_a.id, clone_item_b.id]
        );
        if not (eligibility ->> 'eligible')::boolean then
          raise exception 'SCHEDULE_UNSATISFIABLE %', eligibility -> 'reasons' using errcode = '22023';
        end if;
        -- Partial unique indexes are checked row by row. Release both slots
        -- inside this transaction before assigning the reciprocal values.
        update public.pachanga_competition_schedule_items items set
          slot_id = null, scheduled_start = null, scheduled_end = null,
          timezone = null, venue_id = null, venue_label = null,
          venue_status = 'TBD', status = 'unassigned',
          revision = items.revision + 1,
          server_sequence = sequence_value
        where items.id in (clone_item_a.id, clone_item_b.id);
        update public.pachanga_competition_schedule_items items set
          slot_id = case when items.id = clone_item_a.id then slot_b.id else slot_a.id end,
          scheduled_start = case when items.id = clone_item_a.id then slot_b.starts_at else slot_a.starts_at end,
          scheduled_end = case when items.id = clone_item_a.id then slot_b.ends_at else slot_a.ends_at end,
          timezone = case when items.id = clone_item_a.id then slot_b.timezone else slot_a.timezone end,
          venue_id = case when items.id = clone_item_a.id then slot_b.venue_id else slot_a.venue_id end,
          venue_label = case when items.id = clone_item_a.id then slot_b.venue_label else slot_a.venue_label end,
          venue_status = case when (case when items.id = clone_item_a.id then slot_b.venue_id else slot_a.venue_id end) is null then 'TBD' else 'CONFIRMED' end,
          status = 'assigned', revision = items.revision + 1,
          server_sequence = sequence_value
        where items.id in (clone_item_a.id, clone_item_b.id);
      else
        update public.pachanga_competition_schedule_items items set
          home_entry_id = items.away_entry_id,
          away_entry_id = items.home_entry_id,
          revision = items.revision + 1,
          server_sequence = sequence_value
        where items.schedule_revision_id = revision_id
          and items.pairing_key = source_item_a.pairing_key;
      end if;
    end if;
    update public.pachanga_competition_rounds rounds set
      starts_at = source.minimum_start, ends_at = source.maximum_end,
      revision = rounds.revision + 1,
      server_sequence = sequence_value
    from (
      select items.round_id, min(items.scheduled_start) as minimum_start,
        max(items.scheduled_end) as maximum_end
      from public.pachanga_competition_schedule_items items
      where items.schedule_revision_id = revision_id group by items.round_id
    ) source where source.round_id = rounds.id;
    perform private.pachanga_league_schedule_rebuild_conflicts_v1(revision_id, sequence_value);
    perform private.pachanga_league_schedule_quality_v1(revision_id, sequence_value);
    update public.pachanga_competition_schedule_plans plans set
      current_revision_id = revision_id, status = 'generated',
      revision = plans.revision + 1, server_sequence = sequence_value
    where plans.id = plan_row.id returning plans.revision into confirmed_revision;
    snapshot := private.pachanga_league_schedule_revision_snapshot_v1(plan_row.id, true);
    event_payload := jsonb_build_object(
      'scheduleRevisionId', revision_id,
      'supersedesRevisionId', source_revision_id
    );

  elsif normalized_action = 'schedule.validate' then
    perform private.pachanga_league_schedule_assert_flags_v1(true, false, false, false);
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = aggregate_id for update;
    if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    plan_id := plan_row.id; competition_id := plan_row.competition_id;
    if plan_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    perform private.pachanga_league_schedule_assert_authority_v1(competition_id, actor_id, 'schedule_manage');
    validation := private.pachanga_league_schedule_validate_revision_v1(
      plan_row.current_revision_id, actor_id, sequence_value
    );
    update public.pachanga_competition_schedule_plans plans set
      status = case when validation ->> 'status' = 'VALID' then 'validated' else 'generated' end,
      revision = plans.revision + 1, server_sequence = sequence_value
    where plans.id = plan_row.id returning plans.revision into confirmed_revision;
    snapshot := private.pachanga_league_schedule_revision_snapshot_v1(plan_row.id, true)
      || jsonb_build_object('validation', validation);
    event_payload := validation - 'conflicts' - 'quality';

  elsif normalized_action = 'schedule.publish' then
    perform private.pachanga_league_schedule_assert_flags_v1(true, false, true, false);
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = aggregate_id for update;
    if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    plan_id := plan_row.id; competition_id := plan_row.competition_id;
    if plan_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    perform private.pachanga_league_schedule_assert_authority_v1(competition_id, actor_id, 'schedule_publish');
    publication := private.pachanga_league_schedule_publish_v1(
      plan_row.id, actor_id, operation_id, sequence_value
    );
    select plans.revision into confirmed_revision
    from public.pachanga_competition_schedule_plans plans where plans.id = plan_row.id;
    snapshot := private.pachanga_league_schedule_revision_snapshot_v1(plan_row.id, true)
      || jsonb_build_object('publication', publication);
    event_payload := publication;

  elsif normalized_action = 'schedule.cancel' then
    perform private.pachanga_league_schedule_assert_flags_v1();
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = aggregate_id for update;
    if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    plan_id := plan_row.id; competition_id := plan_row.competition_id;
    if plan_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if plan_row.status = 'published' then
      raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
    end if;
    perform private.pachanga_league_schedule_assert_authority_v1(competition_id, actor_id, 'schedule_manage');
    update public.pachanga_competition_schedule_plans plans set
      status = 'cancelled', cancelled_by = actor_id, cancelled_at = confirmed_at,
      revision = plans.revision + 1, server_sequence = sequence_value
    where plans.id = plan_row.id returning plans.revision into confirmed_revision;
    update public.pachanga_competition_schedule_revisions revisions
    set status = 'cancelled', revision = revisions.revision + 1,
        server_sequence = sequence_value
    where revisions.id = plan_row.current_revision_id and revisions.status <> 'published';
    update public.pachanga_competition_rounds rounds
    set status = 'cancelled', revision = rounds.revision + 1,
        server_sequence = sequence_value
    where rounds.schedule_revision_id = plan_row.current_revision_id and rounds.status = 'draft';
    snapshot := private.pachanga_league_schedule_revision_snapshot_v1(plan_row.id, true);
    event_payload := jsonb_build_object('status', 'cancelled');
  else
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  plan_id := coalesce(plan_id, aggregate_id);
  if competition_id is null then
    select plans.competition_id into competition_id
    from public.pachanga_competition_schedule_plans plans where plans.id = plan_id;
  end if;
  invalidations := jsonb_build_array(jsonb_build_object(
    'entityType', 'league_schedule', 'entityId', plan_id,
    'revision', confirmed_revision
  ));
  if plan_id is not null and exists (
    select 1 from public.pachanga_competition_schedule_plans plans
    where plans.id = plan_id and plans.current_revision_id is not null
  ) then
    invalidations := invalidations || coalesce((
      select jsonb_agg(jsonb_build_object(
        'entityType', 'league_round', 'entityId', rounds.id,
        'revision', rounds.revision
      ) order by rounds.round_number, rounds.id)
      from public.pachanga_competition_rounds rounds
      join public.pachanga_competition_schedule_plans plans
        on plans.current_revision_id = rounds.schedule_revision_id
      where plans.id = plan_id
    ), '[]'::jsonb);
    invalidations := invalidations || coalesce((
      select jsonb_agg(jsonb_build_object(
        'entityType', 'league_team_calendar', 'entityId', entries.id,
        'targetGroupId', entries.team_id, 'revision', confirmed_revision
      ) order by entries.id)
      from (
        select distinct items.home_entry_id as entry_id
        from public.pachanga_competition_schedule_items items
        join public.pachanga_competition_schedule_plans plans
          on plans.current_revision_id = items.schedule_revision_id
        where plans.id = plan_id
        union
        select distinct items.away_entry_id
        from public.pachanga_competition_schedule_items items
        join public.pachanga_competition_schedule_plans plans
          on plans.current_revision_id = items.schedule_revision_id
        where plans.id = plan_id
      ) targets join public.pachanga_competition_entries entries on entries.id = targets.entry_id
    ), '[]'::jsonb);
  end if;
  return private.pachanga_league_schedule_store_command_v1(
    operation_id, actor_id, normalized_action, plan_id, competition_id,
    confirmed_revision, sequence_value, reason_code, request_hash, metadata,
    event_payload, snapshot, invalidations, confirmed_at
  );
exception
  when exclusion_violation then
    raise exception 'SCHEDULE_SLOT_RESOURCE_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_scheduling_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;

comment on function public.command_pachanga_league_scheduling_v1(uuid, uuid, bigint, text, jsonb, jsonb) is
  'R4B server-authoritative schedule intent endpoint. It never accepts client pairings, actor IDs, conflicts or canonical IDs.';
