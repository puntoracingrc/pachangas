-- Pachangas IQ R4A: canonical reads, scoped Realtime and platform flag control.
-- Product flags remain OFF after installation and direct table access stays closed.

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
      and entity_type = 'league_participation_flags'
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
    (target_entity_type = 'league_participation_flags' and target_competition_id is null)
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

drop policy if exists pachanga_competition_invalidations_select_v1
  on public.pachanga_competition_invalidations;
drop policy if exists pachanga_competition_invalidations_select_v2
  on public.pachanga_competition_invalidations;
create policy pachanga_competition_invalidations_select_r4a_v1
on public.pachanga_competition_invalidations
for select
to authenticated
using (private.pachanga_league_can_read_invalidation_v1(
  organizer_group_id,
  organizer_club_id,
  competition_id,
  target_group_id,
  target_user_id,
  entity_type,
  (select auth.uid())
));

create or replace function public.get_pachanga_league_participation_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_league_participation_flags_v1();
$$;

revoke all on function public.get_pachanga_league_participation_flags_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_league_participation_flags_v1()
  to anon, authenticated, service_role;

create or replace function public.get_pachanga_league_public_registration_v1(
  target_competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  settings private.pachanga_competition_foundation_settings%rowtype;
  selected_competition public.pachanga_competitions%rowtype;
  selected_edition public.pachanga_competition_editions%rowtype;
  registration_rule_document jsonb;
  public_rule_summary jsonb;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.foundation_enabled
     or not settings.league_participation_foundation_enabled
     or not settings.league_registration_enabled
     or not settings.league_public_registration_enabled then
    raise exception 'LEAGUE_PUBLIC_REGISTRATION_DISABLED' using errcode = '42501';
  end if;

  select * into selected_competition
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id
    and competitions.competition_type = 'LEAGUE'
    and competitions.visibility = 'public';
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;

  select * into selected_edition
  from public.pachanga_competition_editions editions
  where editions.competition_id = selected_competition.id
    and editions.status = 'registration_open'
    and editions.registration_mode = 'PUBLIC_APPROVAL'
    and (editions.registration_opens_at is null or editions.registration_opens_at <= statement_timestamp())
    and (editions.registration_closes_at is null or editions.registration_closes_at > statement_timestamp())
  order by editions.server_sequence desc, editions.id desc
  limit 1;
  if not found then raise exception 'REGISTRATION_NOT_OPEN' using errcode = 'P0002'; end if;

  registration_rule_document := private.pachanga_league_rule_document_v1(
    selected_edition.registration_rule_revision_id
  );
  public_rule_summary := registration_rule_document #> '{registration,publicSummary}';

  return jsonb_build_object(
    'competition', jsonb_build_object(
      'id', selected_competition.id,
      'name', selected_competition.name,
      'slug', selected_competition.slug,
      'type', selected_competition.competition_type
    ),
    'edition', jsonb_build_object(
      'id', selected_edition.id,
      'name', selected_edition.name,
      'seasonLabel', selected_edition.season_label,
      'status', selected_edition.status,
      'registrationMode', selected_edition.registration_mode,
      'registrationOpensAt', selected_edition.registration_opens_at,
      'registrationClosesAt', selected_edition.registration_closes_at,
      'revision', selected_edition.revision,
      'serverSequence', selected_edition.server_sequence
    ),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', categories.id,
        'name', categories.name,
        'slug', categories.slug,
        'description', categories.description,
        'sportFormat', categories.sport_format,
        'levelLabel', categories.level_label,
        'minimumAge', categories.minimum_age,
        'maximumAge', categories.maximum_age,
        'ageReferenceDate', categories.age_reference_date,
        'acceptedTeams', (
          select count(*)
          from public.pachanga_competition_entries entries
          where entries.category_id = categories.id
            and entries.status in ('accepted', 'active')
        ),
        'revision', categories.revision,
        'serverSequence', categories.server_sequence
      ) order by categories.server_sequence, categories.id)
      from public.pachanga_competition_categories categories
      where categories.edition_id = selected_edition.id
        and categories.status = 'active'
        and categories.visibility = 'public'
    ), '[]'::jsonb),
    'acceptedTeams', (
      select count(*) from public.pachanga_competition_entries entries
      where entries.edition_id = selected_edition.id
        and entries.status in ('accepted', 'active')
    ),
    'rulesSummary', coalesce(public_rule_summary, '{}'::jsonb),
    'teamLimits', private.pachanga_league_registration_limits_v1(
      selected_edition.registration_rule_revision_id
    ),
    'flagsRevision', settings.revision,
    'serverSequence', greatest(selected_competition.server_sequence, selected_edition.server_sequence)
  );
end;
$$;

revoke all on function public.get_pachanga_league_public_registration_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_league_public_registration_v1(uuid)
  to anon, authenticated, service_role;

create or replace function public.get_my_pachanga_competition_entries_v1(
  page_offset integer default 0,
  page_size integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
  bounded_size integer := least(greatest(coalesce(page_size, 30), 1), 100);
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  return jsonb_build_object(
    'total', (
      select count(distinct entries.id)
      from public.pachanga_competition_entries entries
      where exists (
        select 1 from public.pachanga_group_members members
        where members.group_id = entries.team_id and members.user_id = actor_id
      ) or exists (
        select 1 from public.pachanga_competition_team_delegates delegates
        where delegates.entry_id = entries.id and delegates.user_id = actor_id
          and delegates.status in ('invited', 'active')
      )
    ),
    'items', coalesce((
      with visible as (
        select distinct entries.*
        from public.pachanga_competition_entries entries
        where exists (
          select 1 from public.pachanga_group_members members
          where members.group_id = entries.team_id and members.user_id = actor_id
        ) or exists (
          select 1 from public.pachanga_competition_team_delegates delegates
          where delegates.entry_id = entries.id and delegates.user_id = actor_id
            and delegates.status in ('invited', 'active')
        )
        order by entries.server_sequence desc, entries.id desc
        offset bounded_offset limit bounded_size
      )
      select jsonb_agg(jsonb_build_object(
        'id', visible.id,
        'competitionId', visible.competition_id,
        'competitionName', competitions.name,
        'editionId', visible.edition_id,
        'editionName', editions.name,
        'categoryId', visible.category_id,
        'categoryName', categories.name,
        'teamId', visible.team_id,
        'teamName', teams.name,
        'status', visible.status,
        'source', visible.entry_source,
        'rosterStatus', rosters.status,
        'eligibilityHealth', revisions.eligibility_summary,
        'stageName', stages.name,
        'divisionName', divisions.name,
        'groupName', competition_groups.name,
        'registrationClosesAt', editions.registration_closes_at,
        'actorScope', private.pachanga_league_entry_actor_scope_v1(visible.id, actor_id),
        'nextActions', private.pachanga_league_next_actions_v1(visible.id, actor_id),
        'nextValidAction', private.pachanga_league_next_actions_v1(visible.id, actor_id) ->> 0,
        'revision', visible.revision,
        'serverSequence', visible.server_sequence,
        'updatedAt', visible.updated_at
      ) order by visible.server_sequence desc, visible.id desc)
      from visible
      join public.pachanga_competitions competitions on competitions.id = visible.competition_id
      join public.pachanga_competition_editions editions on editions.id = visible.edition_id
      join public.pachanga_competition_categories categories on categories.id = visible.category_id
      join public.pachanga_groups teams on teams.id = visible.team_id
      left join public.pachanga_competition_rosters rosters on rosters.entry_id = visible.id
      left join public.pachanga_competition_roster_revisions revisions
        on revisions.id = rosters.current_revision_id
      left join public.pachanga_competition_stage_memberships memberships
        on memberships.entry_id = visible.id and memberships.status = 'active'
      left join public.pachanga_competition_stages stages on stages.id = memberships.stage_id
      left join public.pachanga_competition_divisions divisions on divisions.id = memberships.division_id
      left join public.pachanga_competition_groups competition_groups
        on competition_groups.id = memberships.competition_group_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_my_pachanga_competition_entries_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_competition_entries_v1(integer, integer)
  to authenticated, service_role;

create or replace function public.get_pachanga_competition_registration_desk_v1(
  target_competition_id uuid,
  status_filter text default null,
  category_filter uuid default null,
  page_offset integer default 0,
  page_size integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
  bounded_size integer := least(greatest(coalesce(page_size, 30), 1), 100);
  normalized_status text := nullif(lower(trim(coalesce(status_filter, ''))), '');
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(target_competition_id, actor_id, 'entries_manage')
     and not private.pachanga_competition_can_v1(target_competition_id, actor_id, 'rosters_review') then
    raise exception 'REGISTRATION_DESK_FORBIDDEN' using errcode = '42501';
  end if;
  perform private.pachanga_league_assert_competition_v1(target_competition_id);

  return jsonb_build_object(
    'competitionId', target_competition_id,
    'total', (
      select count(*) from public.pachanga_competition_entries entries
      where entries.competition_id = target_competition_id
        and (normalized_status is null or entries.status = normalized_status)
        and (category_filter is null or entries.category_id = category_filter)
    ),
    'counts', (
      select coalesce(jsonb_object_agg(counts.status, counts.amount), '{}'::jsonb)
      from (
        select entries.status, count(*) as amount
        from public.pachanga_competition_entries entries
        where entries.competition_id = target_competition_id
        group by entries.status
      ) counts
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', selected.id,
        'teamId', selected.team_id,
        'teamName', teams.name,
        'categoryId', selected.category_id,
        'categoryName', categories.name,
        'source', selected.entry_source,
        'status', selected.status,
        'reasonCode', selected.reason_code,
        'privateReason', selected.reason_text_private,
        'submittedAt', selected.submitted_at,
        'rosterStatus', rosters.status,
        'memberCount', revisions.member_count,
        'eligibilityHealth', revisions.eligibility_summary,
        'warningCount',
          coalesce((revisions.eligibility_summary ->> 'pending')::integer, 0)
          + coalesce((revisions.eligibility_summary ->> 'reviewRequired')::integer, 0)
          + coalesce((revisions.eligibility_summary ->> 'ineligible')::integer, 0)
          + coalesce((revisions.eligibility_summary ->> 'expired')::integer, 0),
        'delegateCount', (
          select count(*) from public.pachanga_competition_team_delegates delegates
          where delegates.entry_id = selected.id and delegates.status = 'active'
        ),
        'stageMembership', case when memberships.id is null then null else jsonb_build_object(
          'stageId', memberships.stage_id,
          'divisionId', memberships.division_id,
          'groupId', memberships.competition_group_id
        ) end,
        'pendingActions', private.pachanga_league_next_actions_v1(selected.id, actor_id),
        'revision', selected.revision,
        'serverSequence', selected.server_sequence,
        'updatedAt', selected.updated_at
      ) order by selected.server_sequence desc, selected.id desc)
      from (
        select entries.*
        from public.pachanga_competition_entries entries
        where entries.competition_id = target_competition_id
          and (normalized_status is null or entries.status = normalized_status)
          and (category_filter is null or entries.category_id = category_filter)
        order by entries.server_sequence desc, entries.id desc
        offset bounded_offset limit bounded_size
      ) selected
      join public.pachanga_groups teams on teams.id = selected.team_id
      join public.pachanga_competition_categories categories on categories.id = selected.category_id
      left join public.pachanga_competition_rosters rosters on rosters.entry_id = selected.id
      left join public.pachanga_competition_roster_revisions revisions
        on revisions.id = rosters.current_revision_id
      left join public.pachanga_competition_stage_memberships memberships
        on memberships.entry_id = selected.id and memberships.status = 'active'
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_competition_registration_desk_v1(
  uuid, text, uuid, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_competition_registration_desk_v1(
  uuid, text, uuid, integer, integer
) to authenticated, service_role;

create or replace function public.get_pachanga_competition_entry_v1(target_entry_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  return private.pachanga_league_entry_snapshot_v1(target_entry_id, actor_id);
end;
$$;

revoke all on function public.get_pachanga_competition_entry_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_competition_entry_v1(uuid)
  to authenticated, service_role;

create or replace function public.get_pachanga_competition_roster_v1(
  target_roster_id uuid,
  page_offset integer default 0,
  page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  return private.pachanga_league_roster_snapshot_v1(
    target_roster_id,
    actor_id,
    greatest(coalesce(page_offset, 0), 0),
    least(greatest(coalesce(page_size, 50), 1), 100)
  );
end;
$$;

revoke all on function public.get_pachanga_competition_roster_v1(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_competition_roster_v1(uuid, integer, integer)
  to authenticated, service_role;

create or replace function public.get_pachanga_platform_league_participation_v1(
  page_offset integer default 0,
  page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
  bounded_size integer := least(greatest(coalesce(page_size, 50), 1), 200);
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  return jsonb_build_object(
    'flags', private.pachanga_league_participation_flags_v1(),
    'metrics', jsonb_build_object(
      'registrationOpenEditions', (
        select count(*) from public.pachanga_competition_editions editions
        join public.pachanga_competitions competitions on competitions.id = editions.competition_id
        where editions.status = 'registration_open' and competitions.competition_type = 'LEAGUE'
      ),
      'entries', (select count(*) from public.pachanga_competition_entries),
      'activeDelegates', (
        select count(*) from public.pachanga_competition_team_delegates where status = 'active'
      ),
      'rosters', (select count(*) from public.pachanga_competition_rosters),
      'eligibilityWarnings', (
        select count(*) from public.pachanga_competition_roster_members members
        join public.pachanga_competition_rosters rosters
          on rosters.current_revision_id = members.roster_revision_id
        where members.eligibility_status in ('pending', 'ineligible', 'review_required', 'expired')
      ),
      'duplicateConflicts', (
        select count(*) from (
          select entries.edition_id, entries.category_id, entries.team_id
          from public.pachanga_competition_entries entries
          where entries.status in ('draft', 'submitted', 'invited', 'accepted', 'active')
          group by entries.edition_id, entries.category_id, entries.team_id
          having count(*) > 1
        ) conflicts
      ),
      'activeStageMemberships', (
        select count(*) from public.pachanga_competition_stage_memberships where status = 'active'
      )
    ),
    'total', (select count(*) from public.pachanga_competition_entries),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', selected.id,
        'competitionId', selected.competition_id,
        'competitionName', competitions.name,
        'editionId', selected.edition_id,
        'editionName', editions.name,
        'categoryName', categories.name,
        'teamId', selected.team_id,
        'teamName', teams.name,
        'status', selected.status,
        'source', selected.entry_source,
        'rosterStatus', rosters.status,
        'memberCount', revisions.member_count,
        'eligibilityHealth', revisions.eligibility_summary,
        'revision', selected.revision,
        'serverSequence', selected.server_sequence,
        'updatedAt', selected.updated_at
      ) order by selected.server_sequence desc, selected.id desc)
      from (
        select entries.* from public.pachanga_competition_entries entries
        order by entries.server_sequence desc, entries.id desc
        offset bounded_offset limit bounded_size
      ) selected
      join public.pachanga_competitions competitions on competitions.id = selected.competition_id
      join public.pachanga_competition_editions editions on editions.id = selected.edition_id
      join public.pachanga_competition_categories categories on categories.id = selected.category_id
      join public.pachanga_groups teams on teams.id = selected.team_id
      left join public.pachanga_competition_rosters rosters on rosters.entry_id = selected.id
      left join public.pachanga_competition_roster_revisions revisions
        on revisions.id = rosters.current_revision_id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', events.id,
        'operationId', events.operation_id,
        'aggregateType', events.aggregate_type,
        'aggregateId', events.aggregate_id,
        'competitionId', events.competition_id,
        'action', events.action,
        'revision', events.aggregate_revision,
        'serverSequence', events.server_sequence,
        'reasonCode', events.reason_code,
        'confirmedAt', events.confirmed_at
      ) order by events.server_sequence desc, events.id desc)
      from (
        select * from private.pachanga_competition_events
        where aggregate_type in (
          'competition_category', 'competition_edition', 'competition_entry',
          'competition_team_delegate', 'competition_roster', 'player_competition_credential',
          'competition_stage_membership', 'league_participation_flags'
        )
        order by server_sequence desc, id desc limit 100
      ) events
    ), '[]'::jsonb),
    'errors', '[]'::jsonb
  );
end;
$$;

revoke all on function public.get_pachanga_platform_league_participation_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_league_participation_v1(integer, integer)
  to authenticated, service_role;

create or replace function public.command_pachanga_league_participation_platform_v1(
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
declare
  flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c4a1'::uuid;
  actor_id uuid := (select auth.uid());
  action_name constant text := 'league_participation_flags.set';
  settings private.pachanga_competition_foundation_settings%rowtype;
  request_hash text;
  replay jsonb;
  sanitized_metadata jsonb;
  confirmed_at timestamptz := clock_timestamp();
  sequence_value bigint;
  response jsonb;
  snapshot jsonb;
  next_foundation boolean;
  next_registration boolean;
  next_public_registration boolean;
  next_delegates boolean;
  next_rosters boolean;
  next_schedule_preferences boolean;
begin
  if operation_id is null or aggregate_id <> flags_aggregate_id
     or expected_revision is null or expected_revision < 0 then
    raise exception 'INVALID_LEAGUE_FLAGS_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(command_payload) > 32768 then
    raise exception 'INVALID_LEAGUE_FLAGS_PAYLOAD' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  perform private.pachanga_platform_require_v1('competitions.manage');
  perform private.pachanga_platform_require_v1('flags.write');

  if exists (
    select 1 from jsonb_each(command_payload) values_pair
    where values_pair.key <> 'reason' and jsonb_typeof(values_pair.value) <> 'boolean'
  ) then raise exception 'INVALID_LEAGUE_FLAG' using errcode = '22023'; end if;

  sanitized_metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    action_name, aggregate_id, expected_revision, command_payload
  );
  perform pg_advisory_xact_lock(hashtextextended('league-participation-flags:' || operation_id::text, 0));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, 'authenticated', action_name, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;

  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton for update;
  if settings.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;

  next_foundation := coalesce(
    (command_payload ->> 'foundationEnabled')::boolean,
    settings.league_participation_foundation_enabled
  );
  next_registration := coalesce(
    (command_payload ->> 'registrationEnabled')::boolean,
    settings.league_registration_enabled
  );
  next_public_registration := coalesce(
    (command_payload ->> 'publicRegistrationEnabled')::boolean,
    settings.league_public_registration_enabled
  );
  next_delegates := coalesce(
    (command_payload ->> 'delegatesEnabled')::boolean,
    settings.league_delegates_enabled
  );
  next_rosters := coalesce(
    (command_payload ->> 'rostersEnabled')::boolean,
    settings.league_rosters_enabled
  );
  next_schedule_preferences := coalesce(
    (command_payload ->> 'schedulePreferencesEnabled')::boolean,
    settings.league_schedule_preferences_enabled
  );

  if not next_foundation then
    next_registration := false;
    next_public_registration := false;
    next_delegates := false;
    next_rosters := false;
    next_schedule_preferences := false;
  elsif not next_registration then
    next_public_registration := false;
    next_rosters := false;
  end if;

  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings current_settings set
    league_participation_foundation_enabled = next_foundation,
    league_registration_enabled = next_registration,
    league_public_registration_enabled = next_public_registration,
    league_delegates_enabled = next_delegates,
    league_rosters_enabled = next_rosters,
    league_schedule_preferences_enabled = next_schedule_preferences,
    revision = current_settings.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = confirmed_at
  where current_settings.singleton
  returning * into settings;

  snapshot := private.pachanga_league_participation_flags_v1();
  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedRevision', settings.revision,
    'confirmedAt', confirmed_at,
    'serverSequence', sequence_value,
    'snapshot', snapshot,
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'league_participation_flags',
      'entityId', flags_aggregate_id,
      'revision', settings.revision
    ))
  );

  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, actor_id, 'authenticated', 'league_participation_flags',
    flags_aggregate_id::text, null, action_name, settings.revision, sequence_value,
    left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), action_name), 120),
    snapshot - 'updatedAt', confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, null, null, null, null, null,
    'league_participation_flags', flags_aggregate_id::text, settings.revision, confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
  ) values (
    operation_id, actor_id, 'authenticated', action_name, 'league_participation_flags',
    flags_aggregate_id::text, request_hash, settings.revision, sequence_value,
    sanitized_metadata, response, confirmed_at
  );
  return response;
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_participation_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_participation_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) to authenticated;

comment on function public.get_pachanga_league_public_registration_v1(uuid) is
  'Minimal gated R4A public registration read model. It excludes rejected requests and private reasons.';
comment on function public.get_pachanga_competition_registration_desk_v1(uuid, text, uuid, integer, integer) is
  'Server-paginated organizer read model for R4A entries and roster health.';
comment on function public.command_pachanga_league_participation_platform_v1(uuid, uuid, bigint, jsonb, jsonb) is
  'Idempotent platform-only R4A flag control. All six flags are installed disabled.';
