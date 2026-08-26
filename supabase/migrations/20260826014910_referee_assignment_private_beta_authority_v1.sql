-- Pachangas IQ Wave 4: canonical schedule, availability and replacement
-- invariants around the existing R3 authority.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter function private.pachanga_referee_match_snapshot_v1(text, uuid, text)
  rename to pachanga_referee_match_snapshot_r3_v1;

create or replace function private.pachanga_referee_modality_v1(target_modality text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case upper(replace(replace(trim(coalesce(target_modality, '')), '-', '_'), ' ', '_'))
    when 'FUTBOL11' then 'FOOTBALL_11'
    when 'FUTBOL_11' then 'FOOTBALL_11'
    when 'FOOTBALL11' then 'FOOTBALL_11'
    when 'FOOTBALL_11' then 'FOOTBALL_11'
    when 'FUTBOL7' then 'FOOTBALL_7'
    when 'FUTBOL_7' then 'FOOTBALL_7'
    when 'FOOTBALL7' then 'FOOTBALL_7'
    when 'FOOTBALL_7' then 'FOOTBALL_7'
    when 'FUTBOL5' then 'FOOTBALL_5'
    when 'FUTBOL_5' then 'FOOTBALL_5'
    when 'FOOTBALL5' then 'FOOTBALL_5'
    when 'FOOTBALL_5' then 'FOOTBALL_5'
    when 'SALA' then 'FUTSAL'
    when 'FUTSAL' then 'FUTSAL'
    else 'OTHER'
  end;
$$;

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
declare
  base_snapshot jsonb;
  binding public.pachanga_canonical_match_bindings%rowtype;
  canonical public.pachanga_canonical_matches%rowtype;
  item public.pachanga_competition_schedule_items%rowtype;
  context_row public.pachanga_competition_match_contexts%rowtype;
  fixture_change public.pachanga_competition_fixture_changes%rowtype;
  fixture_revision public.pachanga_competition_fixture_change_revisions%rowtype;
  rule_revision public.pachanga_competition_rule_revisions%rowtype;
  home_team_id uuid;
  away_team_id uuid;
  normalized_kind text := lower(trim(coalesce(target_source_kind, '')));
  effective_start timestamptz;
  effective_end timestamptz;
  effective_timezone text;
  effective_venue_id uuid;
  effective_venue_label text;
  effective_venue_status text;
  schedule_revision bigint;
begin
  if normalized_kind <> 'competition_generated' then
    base_snapshot := private.pachanga_referee_match_snapshot_r3_v1(
      normalized_kind, target_source_group_id, target_source_id
    );
    select * into binding
    from public.pachanga_canonical_match_bindings bindings
    where bindings.canonical_match_id = (base_snapshot ->> 'canonicalMatchId')::uuid
      and bindings.source_kind = normalized_kind
      and bindings.source_group_id is not distinct from target_source_group_id
      and bindings.source_id = target_source_id
      and bindings.binding_status = 'active'
    order by bindings.server_sequence desc, bindings.id desc
    limit 1;
    select * into context_row
    from public.pachanga_competition_match_contexts contexts
    where contexts.canonical_match_id = (base_snapshot ->> 'canonicalMatchId')::uuid
      and contexts.status <> 'retired'
    order by contexts.server_sequence desc, contexts.id desc
    limit 1;
    return base_snapshot || jsonb_build_object(
      'canonicalBindingId', binding.id,
      'competitionMatchContextId', context_row.id,
      'originalScheduledStart', base_snapshot ->> 'scheduledStart',
      'originalScheduledEnd', base_snapshot ->> 'scheduledEnd',
      'effectiveScheduledStart', base_snapshot ->> 'scheduledStart',
      'effectiveScheduledEnd', base_snapshot ->> 'scheduledEnd',
      'effectiveTimezone', base_snapshot ->> 'timezone',
      'effectiveScheduleRevision', (base_snapshot ->> 'scheduleRevision')::bigint,
      'modality', private.pachanga_referee_modality_v1(base_snapshot ->> 'modality'),
      'venueId', context_row.venue_id,
      'venueLabel', context_row.venue_label,
      'venueStatus', coalesce(context_row.venue_status, 'TBD'),
      'published', true
    );
  end if;

  if target_source_group_id is not null
     or target_source_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = '22023';
  end if;
  select * into binding
  from public.pachanga_canonical_match_bindings bindings
  where bindings.source_kind = 'competition_generated'
    and bindings.source_group_id is null
    and bindings.source_id = target_source_id
    and bindings.binding_status = 'active'
  order by bindings.server_sequence desc, bindings.id desc
  limit 1;
  if not found then raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = 'P0002'; end if;
  select * into canonical
  from public.pachanga_canonical_matches matches
  where matches.id = binding.canonical_match_id and matches.status = 'active';
  if not found then raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = 'P0002'; end if;
  select * into item
  from public.pachanga_competition_schedule_items items
  where items.id = target_source_id::uuid
    and items.canonical_match_id = canonical.id
    and items.status = 'published';
  if not found then raise exception 'REFEREE_ASSIGNMENT_MATCH_NOT_PUBLISHED' using errcode = '42501'; end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = canonical.id
    and contexts.schedule_item_id = item.id
    and contexts.status not in ('retired', 'cancelled')
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  if not found then raise exception 'REFEREE_COMPETITION_MATCH_CONTEXT_REQUIRED' using errcode = 'P0002'; end if;
  select * into fixture_change
  from public.pachanga_competition_fixture_changes changes
  where changes.competition_match_context_id = context_row.id and changes.status = 'active'
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
  from public.pachanga_competition_entries entries where entries.id = context_row.home_entry_id;
  select entries.team_id into away_team_id
  from public.pachanga_competition_entries entries where entries.id = context_row.away_entry_id;

  effective_start := coalesce(fixture_revision.effective_scheduled_start, context_row.scheduled_start, item.scheduled_start);
  effective_end := coalesce(fixture_revision.effective_scheduled_end, context_row.scheduled_end, item.scheduled_end);
  effective_timezone := coalesce(fixture_revision.effective_timezone, context_row.timezone, item.timezone, 'Europe/Madrid');
  effective_venue_id := coalesce(fixture_revision.effective_venue_id, context_row.venue_id, item.venue_id);
  effective_venue_label := coalesce(fixture_revision.effective_venue_label, context_row.venue_label, item.venue_label);
  effective_venue_status := coalesce(fixture_revision.effective_venue_status, context_row.venue_status, item.venue_status, 'TBD');
  schedule_revision := greatest(
    item.server_sequence,
    context_row.server_sequence,
    coalesce(fixture_revision.server_sequence, 0)
  );
  if effective_start is null or effective_end is null or effective_end <= effective_start then
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
    'scheduledStart', item.scheduled_start,
    'scheduledEnd', item.scheduled_end,
    'originalScheduledStart', item.scheduled_start,
    'originalScheduledEnd', item.scheduled_end,
    'timezone', coalesce(item.timezone, effective_timezone),
    'scheduleRevision', schedule_revision,
    'effectiveScheduledStart', effective_start,
    'effectiveScheduledEnd', effective_end,
    'effectiveTimezone', effective_timezone,
    'effectiveScheduleRevision', schedule_revision,
    'modality', private.pachanga_referee_modality_v1(rule_revision.rule_document #>> '{format,modality}'),
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

create or replace function private.pachanga_referee_assignment_authority_v1(
  match_snapshot jsonb,
  target_requester_kind text,
  target_requester_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  normalized_kind text := upper(trim(coalesce(target_requester_kind, '')));
  competition_id uuid := nullif(match_snapshot ->> 'competitionId', '')::uuid;
  competition public.pachanga_competitions%rowtype;
begin
  if target_actor_id is null or target_requester_id is null then
    raise exception 'REFEREE_ASSIGNMENT_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  if normalized_kind = 'COMPETITION' then
    if competition_id is null or target_requester_id <> competition_id then
      raise exception 'REFEREE_COMPETITION_CONTEXT_REQUIRED' using errcode = '42501';
    end if;
    if private.pachanga_competition_can_v1(competition_id, target_actor_id, 'referees') then
      return 'competition_referee_authority';
    end if;
    raise exception 'REFEREE_COMPETITION_AUTHORITY_REQUIRED' using errcode = '42501';
  elsif normalized_kind = 'TEAM' then
    if not exists (
      select 1
      from jsonb_array_elements_text(coalesce(match_snapshot -> 'participantGroupIds', '[]'::jsonb)) ids(value)
      where ids.value::uuid = target_requester_id
    ) then raise exception 'REFEREE_ASSIGNMENT_TEAM_NOT_PARTICIPANT' using errcode = '42501'; end if;
    if exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_requester_id and groups.owner_id = target_actor_id
    ) or exists (
      select 1 from public.pachanga_group_members members
      where members.group_id = target_requester_id
        and members.user_id = target_actor_id
        and members.role in ('owner', 'admin')
    ) then return 'team_admin'; end if;
    if competition_id is not null
       and private.pachanga_competition_can_v1(competition_id, target_actor_id, 'referees') then
      return 'competition_referee_authority_for_team';
    end if;
    raise exception 'REFEREE_ASSIGNMENT_TEAM_ADMIN_REQUIRED' using errcode = '42501';
  elsif normalized_kind = 'CLUB' then
    if competition_id is null then raise exception 'REFEREE_CLUB_COMPETITION_CONTEXT_REQUIRED' using errcode = '42501'; end if;
    select * into competition from public.pachanga_competitions competitions where competitions.id = competition_id;
    if not found or competition.organizer_kind <> 'CLUB' or competition.organizer_club_id <> target_requester_id then
      raise exception 'REFEREE_CLUB_NOT_COMPETITION_ORGANIZER' using errcode = '42501';
    end if;
    if not private.pachanga_competition_active_entitlement_v2('CLUB', target_requester_id, 'competition_referees') then
      raise exception 'REFEREE_COMPETITION_ENTITLEMENT_REQUIRED' using errcode = '42501';
    end if;
    if private.pachanga_club_can_v1(target_requester_id, target_actor_id, 'referee_manage') then
      return 'club_referee_authority';
    end if;
    if private.pachanga_competition_can_v1(competition_id, target_actor_id, 'referees') then
      return 'competition_referee_manager';
    end if;
    raise exception 'REFEREE_CLUB_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  raise exception 'REFEREE_ASSIGNMENT_REQUESTER_INVALID' using errcode = '22023';
end;
$$;

create or replace function private.pachanga_referee_assert_assignment_beta_v1()
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_referee_foundation_settings%rowtype;
begin
  select * into settings from private.pachanga_referee_foundation_settings where singleton;
  if not settings.referee_foundation_enabled
     or not settings.referee_assignments_enabled
     or not settings.referee_assignment_private_beta_enabled then
    raise exception 'REFEREE_ASSIGNMENT_PRIVATE_BETA_DISABLED' using errcode = '0A000';
  end if;
end;
$$;

create or replace function private.pachanga_referee_assert_available_v1(
  target_profile_id uuid,
  target_start timestamptz,
  target_end timestamptz,
  target_timezone text,
  target_modality text,
  target_venue_label text,
  target_venue_status text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare profile public.pachanga_referee_profiles%rowtype;
begin
  select * into profile
  from public.pachanga_referee_profiles profiles
  where profiles.id = target_profile_id for update;
  if not found or profile.operational_status <> 'active'
     or not profile.available_for_assignments
     or profile.availability_status = 'UNAVAILABLE' then
    raise exception 'REFEREE_PROFILE_NOT_ASSIGNABLE' using errcode = '42501';
  end if;
  if target_start is null or target_end is null or target_end <= target_start then
    raise exception 'REFEREE_MATCH_SCHEDULE_REQUIRED' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.pachanga_referee_modalities modalities
    where modalities.referee_profile_id = target_profile_id and modalities.active
  ) and not exists (
    select 1 from public.pachanga_referee_modalities modalities
    where modalities.referee_profile_id = target_profile_id
      and modalities.active
      and modalities.modality = target_modality
  ) then raise exception 'REFEREE_MODALITY_INCOMPATIBLE' using errcode = '42501'; end if;
  if exists (
    select 1 from public.pachanga_referee_availability_exceptions exceptions
    where exceptions.referee_profile_id = target_profile_id
      and exceptions.status = 'active'
      and tstzrange(exceptions.unavailable_from, exceptions.unavailable_until, '[)')
        && tstzrange(target_start, target_end, '[)')
  ) then raise exception 'REFEREE_AVAILABILITY_EXCEPTION' using errcode = 'PT409'; end if;
  if exists (
    select 1 from public.pachanga_referee_availability_windows windows
    where windows.referee_profile_id = target_profile_id and windows.status = 'active'
  ) and not exists (
    select 1 from public.pachanga_referee_availability_windows windows
    where windows.referee_profile_id = target_profile_id
      and windows.status = 'active'
      and windows.weekday = extract(isodow from (target_start at time zone windows.timezone))::smallint
      and (target_start at time zone windows.timezone)::time >= windows.start_local_time
      and (target_end at time zone windows.timezone)::time <= windows.end_local_time
  ) then raise exception 'REFEREE_OUTSIDE_RECURRING_AVAILABILITY' using errcode = 'PT409'; end if;
  if coalesce(upper(target_venue_status), 'TBD') <> 'TBD'
     and nullif(trim(coalesce(target_venue_label, '')), '') is not null
     and exists (
       select 1 from public.pachanga_referee_service_areas areas
       where areas.referee_profile_id = target_profile_id and areas.status = 'active'
     )
     and not exists (
       select 1 from public.pachanga_referee_service_areas areas
       where areas.referee_profile_id = target_profile_id
         and areas.status = 'active'
         and (
           lower(target_venue_label) like '%' || lower(areas.general_area) || '%'
           or nullif(areas.municipality, '') is not null
             and lower(target_venue_label) like '%' || lower(areas.municipality) || '%'
           or nullif(areas.province, '') is not null
             and lower(target_venue_label) like '%' || lower(areas.province) || '%'
         )
     ) then raise exception 'REFEREE_SERVICE_AREA_INCOMPATIBLE' using errcode = '42501'; end if;
end;
$$;

create or replace function private.pachanga_referee_assignment_transition_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  match_snapshot jsonb;
  original public.pachanga_referee_assignments%rowtype;
  replacement_guard text := current_setting('pachangas.referee_replacement_confirm', true);
  transition_reason text := coalesce(current_setting('pachangas.referee_reason', true), '');
  beta_active boolean := coalesce((
    select settings.referee_assignment_private_beta_enabled
    from private.pachanga_referee_foundation_settings settings
    where settings.singleton
  ), false);
begin
  if beta_active
     and transition_reason not in (
       'assignment.propose', 'assignment.accept', 'assignment.decline',
       'assignment.confirm', 'assignment.cancel', 'assignment.replace',
       'assignment.reconfirm', 'assignment.expire',
       'terms.counter', 'terms.accept', 'terms.decline',
       'result.observe', 'discipline.record',
       'r4d_match_cancelled', 'r4d_schedule_changed'
     )
     and not (
       tg_op = 'UPDATE' and old.status = 'confirmed' and new.status = 'completed'
     )
     and not (
       tg_op = 'UPDATE'
       and old.status = 'completed'
       and new.status = 'cancelled'
       and new.cancel_reason_code = 'completion_voided'
       and new.cancelled_by is not null
       and new.completed_at is null
     ) then
    raise exception 'REFEREE_LEGACY_ASSIGNMENT_WRITE_DISABLED' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    match_snapshot := private.pachanga_referee_match_snapshot_v1(
      new.source_kind, new.source_group_id, new.source_id
    );
    if (match_snapshot ->> 'canonicalMatchId')::uuid <> new.canonical_match_id then
      raise exception 'REFEREE_CANONICAL_MATCH_MISMATCH' using errcode = '23514';
    end if;
    if new.source_kind = 'competition_generated'
       and not coalesce((match_snapshot ->> 'assignable')::boolean, false) then
      raise exception 'REFEREE_ASSIGNMENT_MATCH_NOT_OPEN' using errcode = '42501';
    end if;
    new.canonical_binding_id := nullif(match_snapshot ->> 'canonicalBindingId', '')::uuid;
    new.competition_match_context_id := nullif(match_snapshot ->> 'competitionMatchContextId', '')::uuid;
    new.modality := private.pachanga_referee_modality_v1(match_snapshot ->> 'modality');
    new.venue_id := nullif(match_snapshot ->> 'venueId', '')::uuid;
    new.venue_label := nullif(match_snapshot ->> 'venueLabel', '');
    new.venue_status := coalesce(nullif(match_snapshot ->> 'venueStatus', ''), 'TBD');
    new.scheduled_start := coalesce(nullif(match_snapshot ->> 'originalScheduledStart', '')::timestamptz,
      (match_snapshot ->> 'scheduledStart')::timestamptz);
    new.scheduled_end := coalesce(nullif(match_snapshot ->> 'originalScheduledEnd', '')::timestamptz,
      (match_snapshot ->> 'scheduledEnd')::timestamptz);
    new.timezone := coalesce(nullif(match_snapshot ->> 'timezone', ''), 'Europe/Madrid');
    new.schedule_source_revision := (match_snapshot ->> 'scheduleRevision')::bigint;
    new.effective_scheduled_start := (match_snapshot ->> 'effectiveScheduledStart')::timestamptz;
    new.effective_scheduled_end := (match_snapshot ->> 'effectiveScheduledEnd')::timestamptz;
    new.effective_timezone := match_snapshot ->> 'effectiveTimezone';
    new.effective_schedule_revision := (match_snapshot ->> 'effectiveScheduleRevision')::bigint;
    new.schedule_state := 'CURRENT';
    if new.replaces_assignment_id is not null then
      select * into original from public.pachanga_referee_assignments assignments
      where assignments.id = new.replaces_assignment_id for update;
      if not found or original.status <> 'confirmed'
         or original.canonical_match_id <> new.canonical_match_id
         or original.assignment_role <> new.assignment_role
         or original.replaces_assignment_id = new.id
         or original.referee_profile_id = new.referee_profile_id then
        raise exception 'REFEREE_REPLACEMENT_INVALID' using errcode = 'PT409';
      end if;
    end if;
  else
    if old.referee_profile_id <> new.referee_profile_id
       or old.canonical_match_id <> new.canonical_match_id
       or old.assignment_role <> new.assignment_role
       or old.source_kind <> new.source_kind
       or old.source_group_id is distinct from new.source_group_id
       or old.source_id <> new.source_id
       or old.requester_kind <> new.requester_kind
       or old.requester_team_id is distinct from new.requester_team_id
       or old.requester_club_id is distinct from new.requester_club_id
       or old.requester_competition_id is distinct from new.requester_competition_id then
      raise exception 'REFEREE_ASSIGNMENT_IDENTITY_IMMUTABLE' using errcode = '23514';
    end if;
    if old.status = 'confirmed' and new.status = 'replaced'
       and replacement_guard is distinct from coalesce(new.replaced_by_assignment_id::text, '') then
      raise exception 'REFEREE_REPLACEMENT_REQUESTER_CONFIRMATION_REQUIRED' using errcode = 'PT409';
    end if;
    if old.status in ('declined', 'cancelled', 'expired', 'replaced', 'completed')
       and new.status is distinct from old.status
       and not (
         old.status = 'completed'
         and new.status = 'cancelled'
         and new.cancel_reason_code = 'completion_voided'
         and new.cancelled_by is not null
         and new.completed_at is null
       ) then
      raise exception 'REFEREE_ASSIGNMENT_TERMINAL' using errcode = 'PT409';
    end if;
    if new.effective_schedule_revision < old.effective_schedule_revision then
      raise exception 'REFEREE_SCHEDULE_REVISION_REGRESSION' using errcode = '23514';
    end if;
  end if;

  if new.status in ('accepted', 'confirmed')
     and new.schedule_state = 'CURRENT'
     and (tg_op = 'INSERT'
       or old.status is distinct from new.status
       or old.schedule_state is distinct from new.schedule_state
       or old.effective_schedule_revision is distinct from new.effective_schedule_revision) then
    match_snapshot := private.pachanga_referee_match_snapshot_v1(
      new.source_kind, new.source_group_id, new.source_id
    );
    if (match_snapshot ->> 'effectiveScheduleRevision')::bigint <> new.effective_schedule_revision
       or (match_snapshot ->> 'effectiveScheduledStart')::timestamptz <> new.effective_scheduled_start
       or (match_snapshot ->> 'effectiveScheduledEnd')::timestamptz <> new.effective_scheduled_end then
      raise exception 'REFEREE_STALE_SCHEDULE' using errcode = 'PT409';
    end if;
    if new.source_kind = 'competition_generated'
       and not coalesce((match_snapshot ->> 'assignable')::boolean, false) then
      raise exception 'REFEREE_ASSIGNMENT_MATCH_NOT_OPEN' using errcode = '42501';
    end if;
    perform private.pachanga_referee_assert_available_v1(
      new.referee_profile_id, new.effective_scheduled_start,
      new.effective_scheduled_end, new.effective_timezone, new.modality,
      new.venue_label, new.venue_status
    );
    perform pg_advisory_xact_lock(hashtextextended(
      'referee-assignment-profile:' || new.referee_profile_id::text, 0
    ));
    perform pg_advisory_xact_lock(hashtextextended(
      'referee-assignment-slot:' || new.canonical_match_id::text || ':' || new.assignment_role, 0
    ));
    if exists (
      select 1 from public.pachanga_referee_assignments assignments
      where assignments.id <> new.id
        and assignments.referee_profile_id = new.referee_profile_id
        and assignments.status in ('accepted', 'confirmed')
        and assignments.schedule_state = 'CURRENT'
        and (new.replaces_assignment_id is null or assignments.id <> new.replaces_assignment_id)
        and tstzrange(assignments.effective_scheduled_start, assignments.effective_scheduled_end, '[)')
          && tstzrange(new.effective_scheduled_start, new.effective_scheduled_end, '[)')
    ) then raise exception 'REFEREE_ASSIGNMENT_TIME_CONFLICT' using errcode = 'PT409'; end if;
    if exists (
      select 1 from public.pachanga_referee_assignments assignments
      where assignments.id <> new.id
        and assignments.canonical_match_id = new.canonical_match_id
        and assignments.assignment_role = new.assignment_role
        and assignments.status in ('accepted', 'confirmed', 'completed')
        and (new.replaces_assignment_id is null or assignments.id <> new.replaces_assignment_id)
    ) then raise exception 'REFEREE_ASSIGNMENT_SLOT_TAKEN' using errcode = 'PT409'; end if;
  end if;

  if tg_op = 'UPDATE'
     and old.status = 'accepted' and new.status = 'confirmed'
     and new.replaces_assignment_id is not null then
    perform set_config('pachangas.referee_replacement_confirm', new.id::text, true);
    update public.pachanga_referee_assignments assignments set
      status = 'replaced', replaced_by_assignment_id = new.id,
      replacement_pending_assignment_id = null,
      replaced_at = clock_timestamp(),
      revision = assignments.revision + 1,
      server_sequence = nextval('private.pachanga_referee_sequence')
    where assignments.id = new.replaces_assignment_id
      and assignments.status = 'confirmed'
      and assignments.replacement_pending_assignment_id = new.id;
    if not found then raise exception 'REFEREE_REPLACEMENT_NOT_CURRENT' using errcode = 'PT409'; end if;
    perform set_config('pachangas.referee_replacement_confirm', '', true);
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_referee_assignment_transition_v1 on public.pachanga_referee_assignments;
create trigger pachanga_referee_assignment_transition_v1
before insert or update on public.pachanga_referee_assignments
for each row execute function private.pachanga_referee_assignment_transition_v1();

create or replace function private.pachanga_referee_assignment_revision_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_referee_assignment_revisions(
    assignment_id, version, status, schedule_state, referee_profile_id,
    canonical_match_id, replaces_assignment_id, replaced_by_assignment_id,
    effective_scheduled_start, effective_scheduled_end, effective_timezone,
    effective_schedule_revision, reason_code, actor_id, snapshot,
    server_sequence, effective_at
  ) values (
    new.id, new.revision, new.status, new.schedule_state, new.referee_profile_id,
    new.canonical_match_id, new.replaces_assignment_id, new.replaced_by_assignment_id,
    new.effective_scheduled_start, new.effective_scheduled_end, new.effective_timezone,
    new.effective_schedule_revision,
    left(coalesce(nullif(current_setting('pachangas.referee_reason', true), ''),
      lower(tg_op) || '_' || new.status), 120),
    auth.uid(),
    jsonb_build_object(
      'status', new.status, 'scheduleState', new.schedule_state,
      'refereeProfileId', new.referee_profile_id,
      'canonicalMatchId', new.canonical_match_id,
      'sourceKind', new.source_kind, 'sourceId', new.source_id,
      'effectiveScheduledStart', new.effective_scheduled_start,
      'effectiveScheduledEnd', new.effective_scheduled_end,
      'effectiveTimezone', new.effective_timezone,
      'effectiveScheduleRevision', new.effective_schedule_revision,
      'modality', new.modality, 'venueLabel', new.venue_label,
      'replacesAssignmentId', new.replaces_assignment_id,
      'replacedByAssignmentId', new.replaced_by_assignment_id
    ),
    new.server_sequence, clock_timestamp()
  );
  return new;
end;
$$;

drop trigger if exists pachanga_referee_assignment_revision_v1 on public.pachanga_referee_assignments;
create trigger pachanga_referee_assignment_revision_v1
after insert or update on public.pachanga_referee_assignments
for each row execute function private.pachanga_referee_assignment_revision_v1();

create or replace function private.pachanga_referee_term_revision_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into private.pachanga_referee_assignment_term_revisions(
    assignment_id, version, fee_mode, proposed_fee_cents, counter_fee_cents,
    agreed_fee_cents, currency, travel_included, private_terms_note,
    terms_status, actor_id, server_sequence, effective_at
  ) values (
    new.assignment_id, new.terms_revision, new.fee_mode,
    new.proposed_fee_cents, new.counter_fee_cents, new.agreed_fee_cents,
    new.currency, new.travel_included, new.private_terms_note,
    new.terms_status, auth.uid(), new.server_sequence, clock_timestamp()
  );
  return new;
end;
$$;

drop trigger if exists pachanga_referee_term_revision_v1 on private.pachanga_referee_assignment_terms;
create trigger pachanga_referee_term_revision_v1
after insert or update on private.pachanga_referee_assignment_terms
for each row execute function private.pachanga_referee_term_revision_v1();

create or replace function private.pachanga_referee_immutable_wave4_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'REFEREE_IMMUTABLE_HISTORY' using errcode = '55000';
end;
$$;

drop trigger if exists pachanga_referee_assignment_revisions_immutable_v1 on public.pachanga_referee_assignment_revisions;
create trigger pachanga_referee_assignment_revisions_immutable_v1
before update or delete on public.pachanga_referee_assignment_revisions
for each row execute function private.pachanga_referee_immutable_wave4_v1();
drop trigger if exists pachanga_referee_term_revisions_immutable_v1 on private.pachanga_referee_assignment_term_revisions;
create trigger pachanga_referee_term_revisions_immutable_v1
before update or delete on private.pachanga_referee_assignment_term_revisions
for each row execute function private.pachanga_referee_immutable_wave4_v1();
drop trigger if exists pachanga_referee_result_observations_immutable_v1 on private.pachanga_referee_result_observations;
create trigger pachanga_referee_result_observations_immutable_v1
before update or delete on private.pachanga_referee_result_observations
for each row execute function private.pachanga_referee_immutable_wave4_v1();

create or replace function private.pachanga_referee_deterministic_uuid_v1(seed text)
returns uuid
language sql
immutable
set search_path = pg_catalog
as $$
  select (
    substr(md5(seed), 1, 8) || '-' || substr(md5(seed), 9, 4) || '-4' ||
    substr(md5(seed), 14, 3) || '-8' || substr(md5(seed), 18, 3) || '-' ||
    substr(md5(seed), 21, 12)
  )::uuid;
$$;

create or replace function private.pachanga_referee_r4d_schedule_sync_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  fixture public.pachanga_competition_fixture_changes%rowtype;
  assignment public.pachanga_referee_assignments%rowtype;
  updated_assignment public.pachanga_referee_assignments%rowtype;
  referee_user_id uuid;
  synthetic_operation_id uuid;
  request_hash text;
  next_state text;
  next_status text;
begin
  select * into fixture
  from public.pachanga_competition_fixture_changes changes
  where changes.id = new.fixture_change_id;
  if not found then return new; end if;
  for assignment in
    select assignments.*
    from public.pachanga_referee_assignments assignments
    where assignments.canonical_match_id = fixture.canonical_match_id
      and assignments.status in ('proposed', 'accepted', 'confirmed')
    order by assignments.server_sequence, assignments.id
    for update
  loop
    next_status := case when new.change_type = 'CANCELLATION' then 'cancelled' else assignment.status end;
    next_state := case
      when new.change_type = 'CANCELLATION' then 'CANCELLED'
      when assignment.status = 'confirmed' then 'RECONFIRMATION_REQUIRED'
      else 'STALE_SCHEDULE'
    end;
    perform set_config('pachangas.referee_reason',
      case when new.change_type = 'CANCELLATION' then 'r4d_match_cancelled'
           else 'r4d_schedule_changed' end, true);
    update public.pachanga_referee_assignments assignments set
      status = next_status,
      schedule_state = next_state,
      effective_scheduled_start = coalesce(new.effective_scheduled_start, assignments.effective_scheduled_start),
      effective_scheduled_end = coalesce(new.effective_scheduled_end, assignments.effective_scheduled_end),
      effective_timezone = coalesce(new.effective_timezone, assignments.effective_timezone),
      effective_schedule_revision = greatest(assignments.effective_schedule_revision, new.server_sequence),
      venue_id = case when new.effective_venue_status = 'TBD' then null else new.effective_venue_id end,
      venue_label = case when new.effective_venue_status = 'TBD' then null else new.effective_venue_label end,
      venue_status = new.effective_venue_status,
      schedule_changed_at = clock_timestamp(),
      cancelled_at = case when new.change_type = 'CANCELLATION' then clock_timestamp() else assignments.cancelled_at end,
      cancelled_by = case when new.change_type = 'CANCELLATION' then new.created_by else assignments.cancelled_by end,
      cancel_reason_code = case when new.change_type = 'CANCELLATION' then new.public_reason_code else assignments.cancel_reason_code end,
      cancel_reason_text = case when new.change_type = 'CANCELLATION' then new.public_summary else assignments.cancel_reason_text end,
      revision = assignments.revision + 1,
      server_sequence = nextval('private.pachanga_referee_sequence')
    where assignments.id = assignment.id
    returning * into updated_assignment;
    select profiles.user_id into referee_user_id
    from public.pachanga_referee_profiles profiles where profiles.id = updated_assignment.referee_profile_id;
    synthetic_operation_id := private.pachanga_referee_deterministic_uuid_v1(
      'r4d:' || new.id::text || ':' || updated_assignment.id::text
    );
    request_hash := encode(extensions.digest(
      'r4d|' || new.id::text || '|' || updated_assignment.id::text || '|' || updated_assignment.revision::text,
      'sha256'
    ), 'hex');
    if not exists (
      select 1 from private.pachanga_referee_operation_receipts receipts
      where receipts.operation_id = synthetic_operation_id
    ) then
      perform private.pachanga_referee_store_command_v1(
        synthetic_operation_id, new.created_by, 'authenticated',
        case when new.change_type = 'CANCELLATION' then 'assignment.match_cancelled'
             else 'assignment.schedule_changed' end,
        'referee_assignment', updated_assignment.id::text, request_hash,
        updated_assignment.revision, new.public_reason_code,
        jsonb_build_object(
          'fixtureChangeRevisionId', new.id,
          'changeType', new.change_type,
          'scheduleState', updated_assignment.schedule_state,
          'effectiveScheduleRevision', updated_assignment.effective_schedule_revision
        ),
        jsonb_build_object(
          'assignmentId', updated_assignment.id,
          'status', updated_assignment.status,
          'scheduleState', updated_assignment.schedule_state,
          'effectiveScheduledStart', updated_assignment.effective_scheduled_start,
          'effectiveScheduledEnd', updated_assignment.effective_scheduled_end,
          'effectiveScheduleRevision', updated_assignment.effective_schedule_revision
        ),
        updated_assignment.referee_profile_id, updated_assignment.requester_club_id,
        updated_assignment.canonical_match_id, referee_user_id,
        updated_assignment.requester_team_id, 'private', '{}'::jsonb
      );
    end if;
    perform private.pachanga_referee_notify_v1(
      referee_user_id,
      case when new.change_type = 'CANCELLATION' then 'referee_assignment_cancelled'
           else 'referee_assignment_reconfirmation_required' end,
      case when new.change_type = 'CANCELLATION' then 'Partido cancelado'
           else 'Reconfirma el nuevo horario' end,
      case when new.change_type = 'CANCELLATION'
        then 'El partido de tu asignacion arbitral ha sido cancelado.'
        else 'El partido ha cambiado de horario o sede. Revisa tu disponibilidad.' end,
      '/mis-asignaciones-arbitrales?assignment=' || updated_assignment.id::text,
      jsonb_build_object('assignmentId', updated_assignment.id,
        'canonicalMatchId', updated_assignment.canonical_match_id),
      'referee-r4d:' || new.id::text || ':' || referee_user_id::text
    );
    if updated_assignment.proposed_by is distinct from referee_user_id then
      perform private.pachanga_referee_notify_v1(
        updated_assignment.proposed_by,
        case when new.change_type = 'CANCELLATION' then 'referee_assignment_cancelled'
             else 'referee_assignment_reconfirmation_required' end,
        case when new.change_type = 'CANCELLATION' then 'Asignacion cancelada'
             else 'Asignacion pendiente de reconfirmacion' end,
        'El horario efectivo del partido ha cambiado.',
        '/competiciones/' || coalesce(updated_assignment.competition_id::text, '') ||
          '/partidos/' || updated_assignment.canonical_match_id::text,
        jsonb_build_object('assignmentId', updated_assignment.id,
          'canonicalMatchId', updated_assignment.canonical_match_id),
        'referee-r4d-requester:' || new.id::text || ':' || updated_assignment.proposed_by::text
      );
    end if;
  end loop;
  perform set_config('pachangas.referee_reason', '', true);
  return new;
end;
$$;

drop trigger if exists pachanga_referee_r4d_schedule_sync_v1
  on public.pachanga_competition_fixture_change_revisions;
create trigger pachanga_referee_r4d_schedule_sync_v1
after insert on public.pachanga_competition_fixture_change_revisions
for each row execute function private.pachanga_referee_r4d_schedule_sync_v1();

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_referee_match_snapshot_r3_v1(text,uuid,text)'::regprocedure,
    'private.pachanga_referee_match_snapshot_v1(text,uuid,text)'::regprocedure,
    'private.pachanga_referee_modality_v1(text)'::regprocedure,
    'private.pachanga_referee_assignment_authority_v1(jsonb,text,uuid,uuid)'::regprocedure,
    'private.pachanga_referee_assert_assignment_beta_v1()'::regprocedure,
    'private.pachanga_referee_assert_available_v1(uuid,timestamptz,timestamptz,text,text,text,text)'::regprocedure,
    'private.pachanga_referee_assignment_transition_v1()'::regprocedure,
    'private.pachanga_referee_assignment_revision_v1()'::regprocedure,
    'private.pachanga_referee_term_revision_v1()'::regprocedure,
    'private.pachanga_referee_immutable_wave4_v1()'::regprocedure,
    'private.pachanga_referee_deterministic_uuid_v1(text)'::regprocedure,
    'private.pachanga_referee_r4d_schedule_sync_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;
