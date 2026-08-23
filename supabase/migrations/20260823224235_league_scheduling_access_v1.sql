-- Pachangas IQ R4B: least-privilege reads, platform controls and Realtime access.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_competition_invalidations
  drop constraint if exists pachanga_competition_invalidations_authority_check;
alter table public.pachanga_competition_invalidations
  add constraint pachanga_competition_invalidations_authority_check check (
    (
      organizer_group_id is not null
      and organizer_club_id is null
    ) or (
      organizer_group_id is null
      and organizer_club_id is not null
    ) or (
      organizer_group_id is null
      and organizer_club_id is null
      and competition_id is null
      and entity_type in ('league_participation_flags', 'league_scheduling_flags')
    )
  );

create or replace function private.pachanga_league_can_read_invalidation_v1(
  organizer_group_id uuid,
  organizer_club_id uuid,
  target_competition_id uuid,
  target_group_id uuid,
  target_user_id uuid,
  target_entity_type text,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select actor_id is not null
    and actor_id = (select auth.uid())
    and (
    (
      target_entity_type in ('league_participation_flags', 'league_scheduling_flags')
      and target_competition_id is null
    )
    or private.pachanga_platform_role_for_user_v1(actor_id) in ('platform_owner', 'platform_admin')
    or target_user_id = actor_id
    or exists (
      select 1 from public.pachanga_groups groups
      where groups.id in (organizer_group_id, target_group_id)
        and groups.owner_id = actor_id
    )
    or exists (
      select 1 from public.pachanga_group_members members
      where members.group_id = target_group_id and members.user_id = actor_id
    )
    or private.pachanga_club_can_v1(organizer_club_id, actor_id, 'read')
    or (
      target_competition_id is not null and exists (
        select 1 from public.pachanga_competition_staff_assignments assignments
        where assignments.competition_id = target_competition_id
          and assignments.user_id = actor_id
          and assignments.status = 'active'
      )
    )
    or (
      target_competition_id is not null and exists (
        select 1
        from public.pachanga_competition_entries entries
        join public.pachanga_competition_team_delegates delegates
          on delegates.entry_id = entries.id
        where entries.competition_id = target_competition_id
          and entries.team_id = target_group_id
          and delegates.user_id = actor_id
          and delegates.status = 'active'
          and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
      )
    )
  );
$$;

revoke all on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) to authenticated;

create or replace function private.pachanga_league_schedule_can_read_plan_v1(
  target_schedule_plan_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.pachanga_competition_schedule_plans plans
    where plans.id = target_schedule_plan_id
      and (
        private.pachanga_competition_can_v1(plans.competition_id, target_actor_id, 'schedule_read')
        or (
          plans.status = 'published'
          and exists (
            select 1
            from public.pachanga_competition_schedule_items items
            where items.schedule_revision_id = plans.current_revision_id
              and (
                private.pachanga_league_entry_actor_scope_v1(items.home_entry_id, target_actor_id) is not null
                or private.pachanga_league_entry_actor_scope_v1(items.away_entry_id, target_actor_id) is not null
              )
          )
        )
      )
  );
$$;

revoke all on function private.pachanga_league_schedule_can_read_plan_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.pachanga_league_schedule_rls_can_read_plan_v1(
  target_schedule_plan_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_league_schedule_can_read_plan_v1(
    target_schedule_plan_id,
    (select auth.uid())
  );
$$;

revoke all on function public.pachanga_league_schedule_rls_can_read_plan_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.pachanga_league_schedule_rls_can_read_plan_v1(uuid)
  to authenticated;

create or replace function private.pachanga_league_schedule_diff_v1(
  target_schedule_revision_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with current_revision as (
    select revisions.* from public.pachanga_competition_schedule_revisions revisions
    where revisions.id = target_schedule_revision_id
  ), current_items as (
    select items.*, rounds.round_number
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.schedule_revision_id = target_schedule_revision_id
  ), previous_items as (
    select items.*, rounds.round_number
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.schedule_revision_id = (select supersedes_revision_id from current_revision)
  ), changes as (
    select coalesce(current_items.pairing_key, previous_items.pairing_key) as pairing_key,
      coalesce(current_items.leg_number, previous_items.leg_number) as leg_number,
      current_items.id as current_id, previous_items.id as previous_id,
      current_items.home_entry_id is distinct from previous_items.home_entry_id as home_away_changed,
      current_items.round_number is distinct from previous_items.round_number as round_changed,
      current_items.slot_id is distinct from previous_items.slot_id as slot_changed,
      current_items.scheduled_start is distinct from previous_items.scheduled_start as date_changed,
      current_items.venue_id is distinct from previous_items.venue_id as venue_changed
    from current_items full join previous_items
      on previous_items.pairing_key = current_items.pairing_key
      and previous_items.leg_number = current_items.leg_number
  )
  select jsonb_build_object(
    'added', coalesce(jsonb_agg(jsonb_build_object('pairingKey', pairing_key, 'leg', leg_number))
      filter (where previous_id is null), '[]'::jsonb),
    'removed', coalesce(jsonb_agg(jsonb_build_object('pairingKey', pairing_key, 'leg', leg_number))
      filter (where current_id is null), '[]'::jsonb),
    'homeAwayChanged', coalesce(jsonb_agg(pairing_key || ':' || leg_number::text)
      filter (where current_id is not null and previous_id is not null and home_away_changed), '[]'::jsonb),
    'roundChanged', coalesce(jsonb_agg(pairing_key || ':' || leg_number::text)
      filter (where current_id is not null and previous_id is not null and round_changed), '[]'::jsonb),
    'slotChanged', coalesce(jsonb_agg(pairing_key || ':' || leg_number::text)
      filter (where current_id is not null and previous_id is not null and slot_changed), '[]'::jsonb),
    'dateChanged', coalesce(jsonb_agg(pairing_key || ':' || leg_number::text)
      filter (where current_id is not null and previous_id is not null and date_changed), '[]'::jsonb),
    'venueChanged', coalesce(jsonb_agg(pairing_key || ':' || leg_number::text)
      filter (where current_id is not null and previous_id is not null and venue_changed), '[]'::jsonb),
    'previousQualityScore', (select revisions.quality_score from public.pachanga_competition_schedule_revisions revisions
      where revisions.id = (select supersedes_revision_id from current_revision)),
    'currentQualityScore', (select quality_score from current_revision)
  ) from changes;
$$;

revoke all on function private.pachanga_league_schedule_diff_v1(uuid)
  from public, anon, authenticated;

create or replace function public.get_pachanga_league_schedule_workbench_v1(
  target_schedule_plan_id uuid,
  page_offset integer default 0,
  page_size integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare inputs jsonb;
declare input_status text;
begin
  perform private.pachanga_league_schedule_assert_flags_v1();
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if page_offset < 0 or page_size < 1 or page_size > 500 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id;
  if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  if not private.pachanga_competition_can_v1(plan_row.competition_id, actor_id, 'schedule_read') then
    raise exception 'COMPETITION_SCHEDULE_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  if plan_row.current_revision_id is not null then
    select * into revision_row from public.pachanga_competition_schedule_revisions revisions
    where revisions.id = plan_row.current_revision_id;
    if plan_row.status in ('published', 'cancelled') then
      input_status := case when plan_row.status = 'published'
        then 'PUBLISHED_SNAPSHOT' else 'ARCHIVED_SNAPSHOT' end;
    else
      inputs := private.pachanga_league_schedule_inputs_v1(plan_row.id, revision_row.seed);
      input_status := case when inputs ->> 'inputChecksum' = revision_row.input_checksum
        then 'CURRENT' else 'STALE_INPUT' end;
    end if;
  else input_status := 'NOT_GENERATED'; end if;
  return private.pachanga_league_schedule_revision_snapshot_v1(plan_row.id, true)
    || jsonb_build_object(
      'inputStatus', input_status,
      'engine', jsonb_build_object('version', plan_row.engine_version, 'capacity', 32),
      'rounds', coalesce((select jsonb_agg(jsonb_build_object(
        'id', rounds.id, 'number', rounds.round_number, 'leg', rounds.leg_number,
        'name', rounds.display_name, 'startsAt', rounds.starts_at,
        'endsAt', rounds.ends_at, 'status', rounds.status,
        'revision', rounds.revision
      ) order by rounds.round_number, rounds.id)
      from public.pachanga_competition_rounds rounds
      where rounds.schedule_revision_id = revision_row.id), '[]'::jsonb),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', source.id, 'roundId', source.round_id,
        'roundNumber', source.round_number, 'leg', source.leg_number,
        'homeEntryId', source.home_entry_id, 'homeTeam', source.home_team,
        'awayEntryId', source.away_entry_id, 'awayTeam', source.away_team,
        'slotId', source.slot_id, 'startsAt', source.scheduled_start,
        'endsAt', source.scheduled_end, 'timezone', source.timezone,
        'venueId', source.venue_id, 'venueLabel', source.venue_label,
        'venueStatus', source.venue_status, 'status', source.status,
        'revision', source.revision
      ) order by source.round_number, source.pairing_key, source.id)
      from (
        select items.*, rounds.round_number,
          home_groups.name as home_team, away_groups.name as away_team
        from public.pachanga_competition_schedule_items items
        join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
        join public.pachanga_competition_entries home_entries on home_entries.id = items.home_entry_id
        join public.pachanga_groups home_groups on home_groups.id = home_entries.team_id
        join public.pachanga_competition_entries away_entries on away_entries.id = items.away_entry_id
        join public.pachanga_groups away_groups on away_groups.id = away_entries.team_id
        where items.schedule_revision_id = revision_row.id
        order by rounds.round_number, items.pairing_key, items.id
        offset page_offset limit page_size
      ) source), '[]'::jsonb),
      'slots', coalesce((select jsonb_agg(jsonb_build_object(
        'id', slots.id, 'startsAt', slots.starts_at, 'endsAt', slots.ends_at,
        'timezone', slots.timezone, 'venueId', slots.venue_id,
        'venueLabel', slots.venue_label, 'resourceKey', slots.resource_key,
        'status', slots.status, 'revision', slots.revision
      ) order by slots.starts_at, slots.server_sequence, slots.id)
      from public.pachanga_competition_schedule_slots slots
      where slots.edition_id = plan_row.edition_id
        and slots.stage_id = plan_row.stage_id
        and slots.division_id is not distinct from plan_row.division_id
        and slots.competition_group_id is not distinct from plan_row.competition_group_id
        and slots.status <> 'retired'), '[]'::jsonb),
      'diff', case when revision_row.id is null then '{}'::jsonb
        else private.pachanga_league_schedule_diff_v1(revision_row.id) end,
      'nextValidActions', case
        when plan_row.status = 'draft' then jsonb_build_array('schedule_slot.create', 'schedule_slot.bulk_create', 'schedule_slot.update', 'schedule_slot.retire', 'schedule.generate', 'schedule.cancel')
        when plan_row.status = 'generated' then jsonb_build_array('schedule_slot.create', 'schedule_slot.bulk_create', 'schedule_slot.update', 'schedule_slot.retire', 'schedule.regenerate', 'schedule_item.move_slot', 'schedule_item.swap_slot', 'schedule_item.swap_home_away', 'round.rename', 'schedule.validate', 'schedule.cancel')
        when plan_row.status = 'validated' then jsonb_build_array('schedule.publish', 'schedule.regenerate', 'schedule.cancel')
        else '[]'::jsonb end
    );
end;
$$;

revoke all on function public.get_pachanga_league_schedule_workbench_v1(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_league_schedule_workbench_v1(uuid, integer, integer)
  to authenticated;

create or replace function private.pachanga_league_team_calendar_v1(target_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with entry_scope as (
    select entries.*, groups.name as team_name
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = target_entry_id
  ), published_plan as (
    select plans.*
    from public.pachanga_competition_schedule_plans plans, entry_scope entries
    join public.pachanga_competition_stage_memberships memberships
      on memberships.entry_id = entries.id and memberships.status = 'active'
    where plans.edition_id = entries.edition_id
      and plans.category_id = entries.category_id
      and plans.stage_id = memberships.stage_id
      and plans.division_id is not distinct from memberships.division_id
      and plans.competition_group_id is not distinct from memberships.competition_group_id
      and plans.status = 'published'
    order by plans.server_sequence desc, plans.id desc limit 1
  ), fixtures as (
    select items.*, rounds.round_number, rounds.display_name, rounds.leg_number as round_leg,
      contexts.status as context_status,
      case when items.home_entry_id = target_entry_id then 'HOME' else 'AWAY' end as side,
      case when items.home_entry_id = target_entry_id then items.away_entry_id else items.home_entry_id end as rival_entry_id
    from published_plan plans
    join public.pachanga_competition_schedule_items items
      on items.schedule_revision_id = plans.current_revision_id and items.status = 'published'
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    join public.pachanga_competition_match_contexts contexts
      on contexts.id = items.competition_match_context_id and contexts.status = 'scheduled'
    where target_entry_id in (items.home_entry_id, items.away_entry_id)
  )
  select jsonb_build_object(
    'competition', jsonb_build_object('id', competitions.id, 'name', competitions.name),
    'edition', jsonb_build_object('id', editions.id, 'name', editions.name, 'seasonLabel', editions.season_label),
    'stage', jsonb_build_object('id', stages.id, 'name', stages.name, 'type', stages.stage_type),
    'division', case when divisions.id is null then null else jsonb_build_object('id', divisions.id, 'name', divisions.name) end,
    'group', case when competition_groups.id is null then null else jsonb_build_object('id', competition_groups.id, 'name', competition_groups.name) end,
    'entry', jsonb_build_object('id', entries.id, 'teamId', entries.team_id, 'teamName', entries.team_name),
    'schedulePlanId', plans.id,
    'revision', plans.revision,
    'serverSequence', plans.server_sequence,
    'nextFixture', (select jsonb_build_object(
      'itemId', fixtures.id, 'roundNumber', fixtures.round_number,
      'startsAt', fixtures.scheduled_start, 'timezone', fixtures.timezone
    ) from fixtures where fixtures.scheduled_start >= clock_timestamp()
      order by fixtures.scheduled_start, fixtures.id limit 1),
    'fixtures', coalesce((select jsonb_agg(jsonb_build_object(
      'itemId', fixtures.id, 'canonicalMatchId', fixtures.canonical_match_id,
      'contextId', fixtures.competition_match_context_id,
      'roundNumber', fixtures.round_number, 'roundName', fixtures.display_name,
      'leg', fixtures.leg_number, 'side', fixtures.side,
      'rivalEntryId', fixtures.rival_entry_id, 'rivalTeam', rival_groups.name,
      'startsAt', fixtures.scheduled_start, 'endsAt', fixtures.scheduled_end,
      'timezone', fixtures.timezone, 'venueId', fixtures.venue_id,
      'venueLabel', fixtures.venue_label, 'venueStatus', fixtures.venue_status,
      'status', fixtures.context_status
    ) order by fixtures.round_number, fixtures.id)
    from fixtures
    join public.pachanga_competition_entries rival_entries on rival_entries.id = fixtures.rival_entry_id
    join public.pachanga_groups rival_groups on rival_groups.id = rival_entries.team_id), '[]'::jsonb)
  )
  from entry_scope entries
  join published_plan plans on true
  join public.pachanga_competitions competitions on competitions.id = plans.competition_id
  join public.pachanga_competition_editions editions on editions.id = plans.edition_id
  join public.pachanga_competition_stages stages on stages.id = plans.stage_id
  left join public.pachanga_competition_divisions divisions on divisions.id = plans.division_id
  left join public.pachanga_competition_groups competition_groups on competition_groups.id = plans.competition_group_id;
$$;

revoke all on function private.pachanga_league_team_calendar_v1(uuid)
  from public, anon, authenticated;

create or replace function public.get_pachanga_my_league_schedule_v1(target_entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare result jsonb;
begin
  perform private.pachanga_league_schedule_assert_flags_v1();
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if private.pachanga_league_entry_actor_scope_v1(target_entry_id, actor_id) is null then
    raise exception 'LEAGUE_CALENDAR_FORBIDDEN' using errcode = '42501';
  end if;
  result := private.pachanga_league_team_calendar_v1(target_entry_id);
  if result is null then raise exception 'PUBLISHED_SCHEDULE_NOT_FOUND' using errcode = 'P0002'; end if;
  return result;
end;
$$;

revoke all on function public.get_pachanga_my_league_schedule_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_my_league_schedule_v1(uuid)
  to authenticated;

create or replace function public.get_pachanga_public_league_calendar_v1(
  target_competition_id uuid,
  target_round_from integer default 1,
  target_round_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
begin
  perform private.pachanga_league_schedule_assert_flags_v1(false, false, false, true);
  if target_round_from < 1 or target_round_limit < 1 or target_round_limit > 50 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id
    and competitions.competition_type = 'LEAGUE'
    and competitions.visibility = 'public';
  if not found then raise exception 'PUBLIC_COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  return (
    select jsonb_build_object(
      'competition', jsonb_build_object('id', competition_row.id, 'name', competition_row.name),
      'edition', jsonb_build_object('id', editions.id, 'name', editions.name, 'seasonLabel', editions.season_label),
      'stage', jsonb_build_object('id', stages.id, 'name', stages.name),
      'schedulePlanId', plans.id, 'revision', plans.revision,
      'rounds', coalesce(jsonb_agg(jsonb_build_object(
        'id', rounds.id, 'number', rounds.round_number, 'name', rounds.display_name,
        'leg', rounds.leg_number, 'startsAt', rounds.starts_at,
        'endsAt', rounds.ends_at, 'status', rounds.status,
        'fixtures', coalesce((select jsonb_agg(jsonb_build_object(
          'canonicalMatchId', items.canonical_match_id,
          'homeTeam', home_groups.name, 'awayTeam', away_groups.name,
          'startsAt', items.scheduled_start, 'endsAt', items.scheduled_end,
          'timezone', items.timezone,
          'venueLabel', case when items.venue_status = 'CONFIRMED' then items.venue_label else null end,
          'venueStatus', items.venue_status, 'status', 'scheduled'
        ) order by items.scheduled_start, items.id)
        from public.pachanga_competition_schedule_items items
        join public.pachanga_competition_entries home_entries on home_entries.id = items.home_entry_id
        join public.pachanga_groups home_groups on home_groups.id = home_entries.team_id
        join public.pachanga_competition_entries away_entries on away_entries.id = items.away_entry_id
        join public.pachanga_groups away_groups on away_groups.id = away_entries.team_id
        where items.round_id = rounds.id and items.status = 'published'), '[]'::jsonb),
        'byes', coalesce((select jsonb_agg(groups.name order by groups.name, byes.id)
          from public.pachanga_competition_round_byes byes
          join public.pachanga_competition_entries entries on entries.id = byes.entry_id
          join public.pachanga_groups groups on groups.id = entries.team_id
          where byes.round_id = rounds.id), '[]'::jsonb)
      ) order by rounds.round_number, rounds.id), '[]'::jsonb)
    )
    from public.pachanga_competition_schedule_plans plans
    join public.pachanga_competition_editions editions on editions.id = plans.edition_id
    join public.pachanga_competition_stages stages on stages.id = plans.stage_id
    join public.pachanga_competition_rounds rounds on rounds.schedule_revision_id = plans.current_revision_id
      and rounds.status = 'published'
      and rounds.round_number >= target_round_from
      and rounds.round_number < target_round_from + target_round_limit
    where plans.competition_id = target_competition_id and plans.status = 'published'
    group by plans.id, plans.revision, editions.id, stages.id
    order by plans.server_sequence desc, plans.id desc limit 1
  );
end;
$$;

revoke all on function public.get_pachanga_public_league_calendar_v1(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_public_league_calendar_v1(uuid, integer, integer)
  to anon, authenticated;

create or replace function public.get_pachanga_league_round_detail_v1(target_round_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare round_row public.pachanga_competition_rounds%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare public_enabled boolean;
begin
  select * into round_row from public.pachanga_competition_rounds rounds
  where rounds.id = target_round_id;
  if not found then raise exception 'ROUND_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.current_revision_id = round_row.schedule_revision_id
  order by plans.server_sequence desc, plans.id desc limit 1;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = round_row.competition_id;
  select settings.league_public_calendar_enabled into public_enabled
  from private.pachanga_competition_foundation_settings settings where settings.singleton;
  if not (
    actor_id is not null and private.pachanga_league_schedule_can_read_plan_v1(plan_row.id, actor_id)
  ) and not (
    public_enabled and competition_row.visibility = 'public'
    and plan_row.status = 'published' and round_row.status = 'published'
  ) then raise exception 'LEAGUE_ROUND_FORBIDDEN' using errcode = '42501'; end if;
  return jsonb_build_object(
    'competition', jsonb_build_object('id', competition_row.id, 'name', competition_row.name),
    'round', jsonb_build_object(
      'id', round_row.id, 'number', round_row.round_number,
      'name', round_row.display_name, 'leg', round_row.leg_number,
      'startsAt', round_row.starts_at, 'endsAt', round_row.ends_at,
      'status', round_row.status, 'ruleRevisionId', round_row.rule_revision_id,
      'revision', round_row.revision
    ),
    'fixtures', coalesce((select jsonb_agg(jsonb_build_object(
      'itemId', items.id, 'canonicalMatchId', items.canonical_match_id,
      'homeEntryId', items.home_entry_id, 'homeTeam', home_groups.name,
      'awayEntryId', items.away_entry_id, 'awayTeam', away_groups.name,
      'startsAt', items.scheduled_start, 'endsAt', items.scheduled_end,
      'timezone', items.timezone, 'venueLabel', items.venue_label,
      'venueStatus', items.venue_status, 'status', items.status
    ) order by items.scheduled_start, items.id)
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_entries home_entries on home_entries.id = items.home_entry_id
    join public.pachanga_groups home_groups on home_groups.id = home_entries.team_id
    join public.pachanga_competition_entries away_entries on away_entries.id = items.away_entry_id
    join public.pachanga_groups away_groups on away_groups.id = away_entries.team_id
    where items.round_id = round_row.id), '[]'::jsonb),
    'byes', coalesce((select jsonb_agg(jsonb_build_object(
      'entryId', byes.entry_id, 'teamName', groups.name, 'reason', byes.reason
    ) order by groups.name, byes.id)
    from public.pachanga_competition_round_byes byes
    join public.pachanga_competition_entries entries on entries.id = byes.entry_id
    join public.pachanga_groups groups on groups.id = entries.team_id
    where byes.round_id = round_row.id), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_league_round_detail_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_league_round_detail_v1(uuid)
  to anon, authenticated;

create or replace function public.get_pachanga_platform_league_scheduling_v1(
  page_offset integer default 0,
  page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  if page_offset < 0 or page_size < 1 or page_size > 200 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'flags', private.pachanga_league_scheduling_flags_v1(),
    'metrics', jsonb_build_object(
      'draftPlans', (select count(*) from public.pachanga_competition_schedule_plans plans
        where plans.status in ('draft', 'generated', 'validated')),
      'stalePlans', (select count(*) from public.pachanga_competition_schedule_plans plans
        join public.pachanga_competition_schedule_revisions revisions on revisions.id = plans.current_revision_id
        where revisions.validation_status = 'STALE_INPUT'),
      'invalidSchedules', (select count(*) from public.pachanga_competition_schedule_revisions revisions
        where revisions.validation_status = 'INVALID' and revisions.status <> 'superseded'),
      'publishedRounds', (select count(*) from public.pachanga_competition_rounds rounds where rounds.status = 'published'),
      'generatedCanonicalMatches', (select count(*) from public.pachanga_canonical_match_bindings bindings
        where bindings.source_kind = 'competition_generated' and bindings.binding_status = 'active'),
      'unassignedItems', (select count(*) from public.pachanga_competition_schedule_items items
        join public.pachanga_competition_schedule_revisions revisions on revisions.id = items.schedule_revision_id
        where items.slot_id is null and revisions.status <> 'superseded'),
      'hardConflicts', (select count(*) from private.pachanga_competition_schedule_conflicts conflicts
        where conflicts.status = 'active' and conflicts.severity = 'hard'),
      'averageQualityScore', coalesce((select round(avg(revisions.quality_score), 3)
        from public.pachanga_competition_schedule_revisions revisions
        where revisions.status in ('generated', 'validated', 'published')), 0)
    ),
    'legacyCanonicalHealth', private.pachanga_canonical_match_health_v1(),
    'total', (select count(*) from public.pachanga_competition_schedule_plans),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id, 'competitionId', source.competition_id,
      'competitionName', source.competition_name, 'editionName', source.edition_name,
      'stageName', source.stage_name, 'status', source.status,
      'legs', source.legs, 'entryCount', source.entry_count,
      'revision', source.revision, 'validationStatus', source.validation_status,
      'qualityScore', source.quality_score, 'roundCount', source.round_count,
      'itemCount', source.item_count, 'hardConflicts', source.hard_conflicts,
      'serverSequence', source.server_sequence, 'updatedAt', source.updated_at
    ) order by source.server_sequence desc, source.id desc)
    from (
      select plans.*, competitions.name as competition_name,
        editions.name as edition_name, stages.name as stage_name,
        revisions.validation_status, revisions.quality_score,
        (select count(*) from public.pachanga_competition_rounds rounds
          where rounds.schedule_revision_id = plans.current_revision_id) as round_count,
        (select count(*) from public.pachanga_competition_schedule_items schedule_items
          where schedule_items.schedule_revision_id = plans.current_revision_id) as item_count,
        (select count(*) from private.pachanga_competition_schedule_conflicts conflicts
          where conflicts.schedule_revision_id = plans.current_revision_id
            and conflicts.status = 'active' and conflicts.severity = 'hard') as hard_conflicts
      from public.pachanga_competition_schedule_plans plans
      join public.pachanga_competitions competitions on competitions.id = plans.competition_id
      join public.pachanga_competition_editions editions on editions.id = plans.edition_id
      join public.pachanga_competition_stages stages on stages.id = plans.stage_id
      left join public.pachanga_competition_schedule_revisions revisions on revisions.id = plans.current_revision_id
      order by plans.server_sequence desc, plans.id desc
      offset page_offset limit page_size
    ) source), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_league_scheduling_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_league_scheduling_v1(integer, integer)
  to authenticated;

create or replace function public.command_pachanga_league_scheduling_platform_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c4b1'::uuid;
declare actor_id uuid := (select auth.uid());
declare action_name constant text := 'league_scheduling_flags.set';
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare request_hash text;
declare replay jsonb;
declare metadata jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare response jsonb;
declare snapshot jsonb;
declare next_foundation boolean;
declare next_generation boolean;
declare next_editing boolean;
declare next_publication boolean;
declare next_public_calendar boolean;
declare next_canonical_creation boolean;
begin
  if operation_id is null or aggregate_id <> flags_aggregate_id
     or expected_revision is null or expected_revision < 0 then
    raise exception 'INVALID_LEAGUE_SCHEDULING_FLAGS_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(command_payload) > 32768 then
    raise exception 'INVALID_LEAGUE_SCHEDULING_FLAGS_PAYLOAD' using errcode = '22023';
  end if;
  perform private.pachanga_platform_require_v1('competitions.manage');
  perform private.pachanga_platform_require_v1('flags.write');
  if exists (
    select 1 from jsonb_each(command_payload) pair
    where pair.key <> 'reason' and jsonb_typeof(pair.value) <> 'boolean'
  ) then raise exception 'INVALID_LEAGUE_SCHEDULING_FLAG' using errcode = '22023'; end if;
  metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    action_name, aggregate_id, expected_revision, command_payload
  );
  perform pg_advisory_xact_lock(hashtextextended('league-scheduling-flags:' || operation_id::text, 0));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, 'authenticated', action_name, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into settings from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton for update;
  if settings.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  next_foundation := coalesce((command_payload ->> 'foundationEnabled')::boolean, settings.league_scheduling_foundation_enabled);
  next_generation := coalesce((command_payload ->> 'generationEnabled')::boolean, settings.league_schedule_generation_enabled);
  next_editing := coalesce((command_payload ->> 'editingEnabled')::boolean, settings.league_schedule_editing_enabled);
  next_publication := coalesce((command_payload ->> 'publicationEnabled')::boolean, settings.league_schedule_publication_enabled);
  next_public_calendar := coalesce((command_payload ->> 'publicCalendarEnabled')::boolean, settings.league_public_calendar_enabled);
  next_canonical_creation := coalesce((command_payload ->> 'canonicalFixtureCreationEnabled')::boolean, settings.league_canonical_fixture_creation_enabled);
  if not next_foundation then
    next_generation := false; next_editing := false; next_publication := false;
    next_public_calendar := false; next_canonical_creation := false;
  end if;
  if not next_generation then
    next_editing := false; next_publication := false; next_canonical_creation := false;
  end if;
  if not next_publication then next_canonical_creation := false; end if;
  if (next_generation or next_editing or next_publication or next_canonical_creation)
     and not (
       settings.league_participation_foundation_enabled
       and settings.league_registration_enabled
       and settings.league_rosters_enabled
     ) then raise exception 'R4A_DEPENDENCY_NOT_ENABLED' using errcode = '42501'; end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings current_settings set
    league_scheduling_foundation_enabled = next_foundation,
    league_schedule_generation_enabled = next_generation,
    league_schedule_editing_enabled = next_editing,
    league_schedule_publication_enabled = next_publication,
    league_public_calendar_enabled = next_public_calendar,
    league_canonical_fixture_creation_enabled = next_canonical_creation,
    revision = current_settings.revision + 1,
    server_sequence = sequence_value, updated_by = actor_id,
    updated_at = confirmed_at
  where current_settings.singleton returning * into settings;
  snapshot := private.pachanga_league_scheduling_flags_v1();
  response := jsonb_build_object(
    'operationId', operation_id, 'confirmedRevision', settings.revision,
    'confirmedAt', confirmed_at, 'serverSequence', sequence_value,
    'snapshot', snapshot,
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'league_scheduling_flags', 'entityId', flags_aggregate_id,
      'revision', settings.revision
    ))
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, actor_id, 'authenticated', 'league_scheduling_flags',
    flags_aggregate_id::text, null, action_name, settings.revision,
    sequence_value, left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), action_name), 120),
    snapshot - 'updatedAt', confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, null, null, null, null, null, 'league_scheduling_flags',
    flags_aggregate_id::text, settings.revision, confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    operation_id, actor_id, 'authenticated', action_name,
    'league_scheduling_flags', flags_aggregate_id::text, request_hash,
    settings.revision, sequence_value, metadata, response, confirmed_at
  );
  return response;
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_scheduling_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_scheduling_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) to authenticated;

grant execute on function public.command_pachanga_league_scheduling_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

alter table public.pachanga_competition_schedule_plans enable row level security;
alter table public.pachanga_competition_schedule_revisions enable row level security;
alter table public.pachanga_competition_schedule_slots enable row level security;
alter table public.pachanga_competition_rounds enable row level security;
alter table public.pachanga_competition_round_byes enable row level security;
alter table public.pachanga_competition_schedule_items enable row level security;
alter table public.pachanga_competition_schedule_validations enable row level security;

revoke all on table public.pachanga_competition_schedule_plans from public, anon, authenticated;
revoke all on table public.pachanga_competition_schedule_revisions from public, anon, authenticated;
revoke all on table public.pachanga_competition_schedule_slots from public, anon, authenticated;
revoke all on table public.pachanga_competition_rounds from public, anon, authenticated;
revoke all on table public.pachanga_competition_round_byes from public, anon, authenticated;
revoke all on table public.pachanga_competition_schedule_items from public, anon, authenticated;
revoke all on table public.pachanga_competition_schedule_validations from public, anon, authenticated;
revoke all on table private.pachanga_competition_schedule_conflicts from public, anon, authenticated;
revoke all on table private.pachanga_competition_schedule_quality_snapshots from public, anon, authenticated;

grant select on table public.pachanga_competition_schedule_plans to authenticated;
grant select on table public.pachanga_competition_schedule_revisions to authenticated;
grant select on table public.pachanga_competition_schedule_slots to authenticated;
grant select on table public.pachanga_competition_rounds to authenticated;
grant select on table public.pachanga_competition_round_byes to authenticated;
grant select on table public.pachanga_competition_schedule_items to authenticated;
grant select on table public.pachanga_competition_schedule_validations to authenticated;

create or replace function public.get_pachanga_league_schedule_for_competition_v1(
  target_competition_id uuid,
  page_offset integer default 0,
  page_size integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  competition_row public.pachanga_competitions%rowtype;
  plan_id uuid;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if target_competition_id is null then
    raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then
    raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if competition_row.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  perform private.pachanga_league_schedule_assert_authority_v1(
    target_competition_id,
    actor_id,
    'schedule_read'
  );

  select plans.id into plan_id
  from public.pachanga_competition_schedule_plans plans
  where plans.competition_id = target_competition_id
    and plans.status <> 'cancelled'
  order by plans.server_sequence desc, plans.id desc
  limit 1;

  if plan_id is not null then
    return public.get_pachanga_league_schedule_workbench_v1(
      plan_id,
      greatest(coalesce(page_offset, 0), 0),
      least(greatest(coalesce(page_size, 200), 1), 500)
    );
  end if;

  return jsonb_build_object(
    'competition', jsonb_build_object(
      'id', competition_row.id,
      'name', competition_row.name,
      'type', competition_row.competition_type
    ),
    'plan', null,
    'setup', jsonb_build_object(
      'candidates', coalesce((
        select jsonb_agg(jsonb_build_object(
          'categoryId', candidates.category_id,
          'categoryName', candidates.category_name,
          'divisionId', candidates.division_id,
          'divisionName', candidates.division_name,
          'editionId', candidates.edition_id,
          'editionName', candidates.edition_name,
          'editionStatus', candidates.edition_status,
          'groupId', candidates.group_id,
          'groupName', candidates.group_name,
          'legs', candidates.legs,
          'ruleRevisionId', candidates.rule_revision_id,
          'stageId', candidates.stage_id,
          'stageName', candidates.stage_name,
          'stageRevision', candidates.stage_revision,
          'stageType', candidates.stage_type
        ) order by
          candidates.edition_sequence,
          candidates.stage_order,
          candidates.category_sequence,
          candidates.division_order,
          candidates.group_order
        )
        from (
          select
            categories.id as category_id,
            categories.name as category_name,
            categories.server_sequence as category_sequence,
            divisions.id as division_id,
            divisions.name as division_name,
            coalesce(divisions.division_order, 0) as division_order,
            editions.id as edition_id,
            editions.name as edition_name,
            editions.server_sequence as edition_sequence,
            editions.status as edition_status,
            competition_groups.id as group_id,
            competition_groups.name as group_name,
            coalesce(competition_groups.group_order, 0) as group_order,
            (private.pachanga_league_schedule_policy_v1(stages.rule_revision_id) ->> 'legs')::integer as legs,
            stages.rule_revision_id,
            stages.id as stage_id,
            stages.name as stage_name,
            stages.stage_order,
            stages.revision as stage_revision,
            stages.stage_type
          from public.pachanga_competition_editions editions
          join public.pachanga_competition_stages stages
            on stages.edition_id = editions.id
          join public.pachanga_competition_categories categories
            on categories.edition_id = editions.id
           and categories.rule_revision_id = stages.rule_revision_id
           and categories.status in ('active', 'closed')
          left join public.pachanga_competition_divisions divisions
            on divisions.stage_id = stages.id
           and divisions.status <> 'cancelled'
          left join public.pachanga_competition_groups competition_groups
            on competition_groups.stage_id = stages.id
           and competition_groups.status <> 'cancelled'
          where editions.competition_id = target_competition_id
            and editions.status = 'registration_closed'
            and stages.stage_type in ('LEAGUE_STAGE', 'GROUP_STAGE', 'SPLIT')
            and stages.rule_revision_id = editions.rule_revision_id
        ) candidates
      ), '[]'::jsonb)
    ),
    'nextValidActions', jsonb_build_array('schedule_plan.create')
  );
end;
$$;

revoke all on function public.get_pachanga_league_schedule_for_competition_v1(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_league_schedule_for_competition_v1(uuid, integer, integer)
  to authenticated;

grant all on table public.pachanga_competition_schedule_plans to service_role;
grant all on table public.pachanga_competition_schedule_revisions to service_role;
grant all on table public.pachanga_competition_schedule_slots to service_role;
grant all on table public.pachanga_competition_rounds to service_role;
grant all on table public.pachanga_competition_round_byes to service_role;
grant all on table public.pachanga_competition_schedule_items to service_role;
grant all on table public.pachanga_competition_schedule_validations to service_role;
grant all on table private.pachanga_competition_schedule_conflicts to service_role;
grant all on table private.pachanga_competition_schedule_quality_snapshots to service_role;

drop policy if exists "Authorized actors read schedule plans" on public.pachanga_competition_schedule_plans;
create policy "Authorized actors read schedule plans"
on public.pachanga_competition_schedule_plans for select to authenticated
using (public.pachanga_league_schedule_rls_can_read_plan_v1(id));

drop policy if exists "Authorized actors read schedule revisions" on public.pachanga_competition_schedule_revisions;
create policy "Authorized actors read schedule revisions"
on public.pachanga_competition_schedule_revisions for select to authenticated
using (public.pachanga_league_schedule_rls_can_read_plan_v1(schedule_plan_id));

drop policy if exists "Schedule managers read slots" on public.pachanga_competition_schedule_slots;
create policy "Schedule managers read slots"
on public.pachanga_competition_schedule_slots for select to authenticated
using (private.pachanga_competition_can_v1(competition_id, (select auth.uid()), 'schedule_read'));

drop policy if exists "Authorized actors read rounds" on public.pachanga_competition_rounds;
create policy "Authorized actors read rounds"
on public.pachanga_competition_rounds for select to authenticated
using (exists (
  select 1 from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = schedule_revision_id
    and public.pachanga_league_schedule_rls_can_read_plan_v1(revisions.schedule_plan_id)
));

drop policy if exists "Authorized actors read byes" on public.pachanga_competition_round_byes;
create policy "Authorized actors read byes"
on public.pachanga_competition_round_byes for select to authenticated
using (exists (
  select 1 from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = schedule_revision_id
    and public.pachanga_league_schedule_rls_can_read_plan_v1(revisions.schedule_plan_id)
));

drop policy if exists "Authorized actors read schedule items" on public.pachanga_competition_schedule_items;
create policy "Authorized actors read schedule items"
on public.pachanga_competition_schedule_items for select to authenticated
using (exists (
  select 1 from public.pachanga_competition_schedule_revisions revisions
  where revisions.id = schedule_revision_id
    and public.pachanga_league_schedule_rls_can_read_plan_v1(revisions.schedule_plan_id)
));

drop policy if exists "Schedule managers read validations" on public.pachanga_competition_schedule_validations;
create policy "Schedule managers read validations"
on public.pachanga_competition_schedule_validations for select to authenticated
using (exists (
  select 1 from public.pachanga_competition_schedule_revisions revisions
  join public.pachanga_competition_schedule_plans plans on plans.id = revisions.schedule_plan_id
  where revisions.id = schedule_revision_id
    and private.pachanga_competition_can_v1(plans.competition_id, (select auth.uid()), 'schedule_read')
));

create or replace function private.pachanga_compute_canonical_match_health_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with source_counts as (
    select
      (select count(*) from public.pachanga_match_read_model) as group_sources,
      (select count(*) from public.pachanga_open_matches) as open_sources,
      (select count(*) from public.pachanga_external_matches) as external_sources,
      (select count(*) from public.pachanga_team_challenges challenges
        where exists (select 1 from public.pachanga_external_matches matches where matches.challenge_id = challenges.id)
      ) as challenge_sources,
      (select count(*) from public.pachanga_competition_schedule_items items
        where items.status = 'published') as competition_generated_sources
  ), binding_counts as (
    select
      count(*) filter (where source_kind = 'group_match' and binding_status = 'active') as group_bindings,
      count(*) filter (where source_kind = 'open_match' and binding_status = 'active') as open_bindings,
      count(*) filter (where source_kind = 'external_match' and binding_status = 'active') as external_bindings,
      count(*) filter (where source_kind = 'team_challenge' and binding_status = 'active') as challenge_bindings,
      count(*) filter (where source_kind = 'competition_generated' and binding_status = 'active') as competition_generated_bindings
    from public.pachanga_canonical_match_bindings
  ), conflicts as (
    select
      (select count(*)
       from public.pachanga_open_matches open_matches
       join public.pachanga_canonical_match_bindings open_bindings
         on open_bindings.source_kind = 'open_match'
        and open_bindings.source_group_id = open_matches.source_group_id
        and open_bindings.source_id = open_matches.id::text
        and open_bindings.binding_status = 'active'
       join public.pachanga_canonical_match_bindings group_bindings
         on group_bindings.source_kind = 'group_match'
        and group_bindings.source_group_id = open_matches.source_group_id
        and group_bindings.source_id = open_matches.source_match_id
        and group_bindings.binding_status = 'active'
       where open_bindings.canonical_match_id <> group_bindings.canonical_match_id) as open_conflicts,
      (select count(*)
       from public.pachanga_external_matches external_matches
       join public.pachanga_canonical_match_bindings external_bindings
         on external_bindings.source_kind = 'external_match'
        and external_bindings.source_id = external_matches.id::text
        and external_bindings.binding_status = 'active'
       join public.pachanga_canonical_match_bindings challenge_bindings
         on challenge_bindings.source_kind = 'team_challenge'
        and challenge_bindings.source_id = external_matches.challenge_id::text
        and challenge_bindings.binding_status = 'active'
       where external_bindings.canonical_match_id <> challenge_bindings.canonical_match_id) as challenge_conflicts
  )
  select jsonb_build_object(
    'canonicalMatches', (select count(*) from public.pachanga_canonical_matches where status = 'active'),
    'bindingsTotal', (select count(*) from public.pachanga_canonical_match_bindings where binding_status = 'active'),
    'sources', jsonb_build_object(
      'groupMatch', source_counts.group_sources, 'openMatch', source_counts.open_sources,
      'externalMatch', source_counts.external_sources, 'teamChallenge', source_counts.challenge_sources,
      'competitionGenerated', source_counts.competition_generated_sources
    ),
    'bindings', jsonb_build_object(
      'groupMatch', binding_counts.group_bindings, 'openMatch', binding_counts.open_bindings,
      'externalMatch', binding_counts.external_bindings, 'teamChallenge', binding_counts.challenge_bindings,
      'competitionGenerated', binding_counts.competition_generated_bindings
    ),
    'competitionGeneratedMatches', binding_counts.competition_generated_bindings,
    'unboundSources',
      greatest(source_counts.group_sources - binding_counts.group_bindings, 0)
      + greatest(source_counts.open_sources - binding_counts.open_bindings, 0)
      + greatest(source_counts.external_sources - binding_counts.external_bindings, 0)
      + greatest(source_counts.challenge_sources - binding_counts.challenge_bindings, 0)
      + greatest(source_counts.competition_generated_sources - binding_counts.competition_generated_bindings, 0),
    'ambiguousBindings', (select count(*) from public.pachanga_canonical_match_binding_reviews where review_status = 'pending'),
    'duplicateConflicts', conflicts.open_conflicts + conflicts.challenge_conflicts,
    'orphanCanonicalMatches', (
      select count(*) from public.pachanga_canonical_matches matches
      where matches.status = 'active' and not exists (
        select 1 from public.pachanga_canonical_match_bindings bindings
        where bindings.canonical_match_id = matches.id and bindings.binding_status = 'active'
      )
    ),
    'contextsLinked', (select count(*) from public.pachanga_competition_match_contexts
      where status in ('lab_bound', 'scheduled'))
  ) from source_counts, binding_counts, conflicts;
$$;

revoke all on function private.pachanga_compute_canonical_match_health_v1()
  from public, anon, authenticated;

select private.pachanga_refresh_canonical_match_health_v1();
