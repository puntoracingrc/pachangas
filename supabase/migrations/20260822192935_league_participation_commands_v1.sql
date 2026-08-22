-- Pachangas IQ R4A: server-authoritative LEAGUE participation commands.

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
      'read', 'manage', 'staff', 'rules', 'referees',
      'entries_manage', 'rosters_review', 'categories_manage'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'entries_manage', 'rosters_review', 'categories_manage'
    )
    when 'competition_registration_manager' then target_capability in ('read', 'entries_manage')
    when 'competition_roster_manager' then target_capability in ('read', 'rosters_review')
    when 'rules_manager' then target_capability in ('read', 'rules')
    when 'competition_referee_manager' then target_capability in ('read', 'referees')
    when 'viewer' then target_capability = 'read'
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_participation_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.league_participation_foundation_enabled,
    'registrationEnabled', settings.league_registration_enabled,
    'publicRegistrationEnabled', settings.league_public_registration_enabled,
    'delegatesEnabled', settings.league_delegates_enabled,
    'rostersEnabled', settings.league_rosters_enabled,
    'schedulePreferencesEnabled', settings.league_schedule_preferences_enabled,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

revoke all on function private.pachanga_league_participation_flags_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_league_assert_flags_v1(
  require_registration boolean default false,
  require_public_registration boolean default false,
  require_delegates boolean default false,
  require_rosters boolean default false,
  require_schedule_preferences boolean default false
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
  if not settings.foundation_enabled then
    raise exception 'COMPETITION_FOUNDATION_DISABLED' using errcode = '42501';
  end if;
  if not settings.league_participation_foundation_enabled then
    raise exception 'LEAGUE_PARTICIPATION_DISABLED' using errcode = '42501';
  end if;
  if require_registration and not settings.league_registration_enabled then
    raise exception 'LEAGUE_REGISTRATION_DISABLED' using errcode = '42501';
  end if;
  if require_public_registration and not settings.league_public_registration_enabled then
    raise exception 'LEAGUE_PUBLIC_REGISTRATION_DISABLED' using errcode = '42501';
  end if;
  if require_delegates and not settings.league_delegates_enabled then
    raise exception 'LEAGUE_DELEGATES_DISABLED' using errcode = '42501';
  end if;
  if require_rosters and not settings.league_rosters_enabled then
    raise exception 'LEAGUE_ROSTERS_DISABLED' using errcode = '42501';
  end if;
  if require_schedule_preferences and not settings.league_schedule_preferences_enabled then
    raise exception 'LEAGUE_SCHEDULE_PREFERENCES_DISABLED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_league_assert_flags_v1(boolean, boolean, boolean, boolean, boolean)
  from public, anon, authenticated;

create or replace function private.pachanga_league_assert_competition_v1(target_competition_id uuid)
returns public.pachanga_competitions
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_competitions%rowtype;
begin
  select * into selected
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if selected.status <> 'draft' then
    raise exception 'COMPETITION_NOT_DRAFT' using errcode = '22023';
  end if;
  return selected;
end;
$$;

revoke all on function private.pachanga_league_assert_competition_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_entry_actor_scope_v1(
  target_entry_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_entry public.pachanga_competition_entries%rowtype;
declare selected_role text;
begin
  if target_actor_id is null then return null; end if;
  select * into selected_entry
  from public.pachanga_competition_entries entries
  where entries.id = target_entry_id;
  if not found then return null; end if;
  if private.pachanga_competition_can_v1(selected_entry.competition_id, target_actor_id, 'read') then
    return 'ORGANIZER';
  end if;
  if exists (
    select 1 from public.pachanga_groups groups
    where groups.id = selected_entry.team_id and groups.owner_id = target_actor_id
  ) then return 'TEAM_OWNER'; end if;
  select delegates.delegate_role into selected_role
  from public.pachanga_competition_team_delegates delegates
  where delegates.entry_id = target_entry_id
    and delegates.user_id = target_actor_id
    and delegates.status = 'active'
    and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
  order by case delegates.delegate_role
    when 'PRIMARY_DELEGATE' then 1 when 'ROSTER_MANAGER' then 2 else 3 end,
    delegates.server_sequence desc, delegates.id desc
  limit 1;
  if selected_role is not null then return selected_role; end if;
  if exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = selected_entry.team_id and members.user_id = target_actor_id
  ) then return 'TEAM_PLAYER'; end if;
  return null;
end;
$$;

revoke all on function private.pachanga_league_entry_actor_scope_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_next_actions_v1(
  target_entry_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_entry public.pachanga_competition_entries%rowtype;
declare selected_roster public.pachanga_competition_rosters%rowtype;
declare actor_scope text;
declare actions jsonb := '[]'::jsonb;
begin
  select * into selected_entry
  from public.pachanga_competition_entries entries
  where entries.id = target_entry_id;
  if not found then return actions; end if;
  actor_scope := private.pachanga_league_entry_actor_scope_v1(target_entry_id, target_actor_id);
  select * into selected_roster
  from public.pachanga_competition_rosters rosters
  where rosters.entry_id = target_entry_id;

  if actor_scope = 'ORGANIZER' then
    if selected_entry.status = 'submitted' then
      actions := actions || jsonb_build_array('review_entry');
    end if;
    if selected_entry.status = 'accepted' and selected_roster.status = 'submitted' then
      actions := actions || jsonb_build_array('review_roster');
    end if;
    if selected_entry.status = 'accepted' and not exists (
      select 1 from public.pachanga_competition_stage_memberships memberships
      where memberships.entry_id = selected_entry.id and memberships.status = 'active'
    ) then
      actions := actions || jsonb_build_array('assign_stage');
    end if;
  elsif actor_scope = 'TEAM_OWNER' then
    if selected_entry.status = 'invited' then
      actions := actions || jsonb_build_array('accept_invitation', 'decline_invitation');
    elsif selected_entry.status = 'submitted' then
      actions := actions || jsonb_build_array('withdraw');
    elsif selected_entry.status = 'accepted' then
      actions := actions || jsonb_build_array('manage_delegates', 'manage_roster', 'withdraw');
    end if;
  elsif actor_scope in ('PRIMARY_DELEGATE', 'ROSTER_MANAGER')
        and selected_entry.status = 'accepted' then
    actions := actions || jsonb_build_array('manage_roster');
  end if;
  return actions;
end;
$$;

revoke all on function private.pachanga_league_next_actions_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_rule_document_v1(target_rule_revision_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_document jsonb;
begin
  select revisions.rule_document into selected_document
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id = target_rule_revision_id
    and revisions.status in ('published', 'frozen');
  if selected_document is null then
    raise exception 'RULE_REVISION_NOT_PUBLISHED' using errcode = '22023';
  end if;
  return selected_document;
end;
$$;

revoke all on function private.pachanga_league_rule_document_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_registration_limits_v1(
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb := private.pachanga_league_rule_document_v1(target_rule_revision_id);
declare minimum_teams integer;
declare maximum_teams integer;
begin
  minimum_teams := coalesce(
    nullif(document #>> '{registration,registrationPolicy,teamLimits,minimum}', '')::integer,
    nullif(document #>> '{registration,registrationPolicy,minimumTeams}', '')::integer,
    0
  );
  maximum_teams := coalesce(
    nullif(document #>> '{registration,registrationPolicy,teamLimits,maximum}', '')::integer,
    nullif(document #>> '{registration,registrationPolicy,maximumTeams}', '')::integer
  );
  if minimum_teams < 0 or maximum_teams is null or maximum_teams < greatest(minimum_teams, 1) then
    raise exception 'REGISTRATION_TEAM_LIMITS_INVALID' using errcode = '22023';
  end if;
  return jsonb_build_object('minimum', minimum_teams, 'maximum', maximum_teams);
end;
$$;

revoke all on function private.pachanga_league_registration_limits_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_public_player_snapshot_v1(
  target_profile_id uuid,
  target_reference_date date
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'playerProfileId', profiles.id,
    'displayName', profiles.display_name,
    'avatar', profiles.avatar,
    'position', profiles.position,
    'ageAtReference', case
      when profiles.birth_date is null or target_reference_date is null then null
      else extract(year from age(target_reference_date, profiles.birth_date))::integer
    end,
    'referenceDate', target_reference_date
  ))
  from public.pachanga_player_profiles profiles
  where profiles.id = target_profile_id;
$$;

revoke all on function private.pachanga_league_public_player_snapshot_v1(uuid, date)
  from public, anon, authenticated;

create or replace function private.pachanga_league_roster_limits_v1(target_rule_revision_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb := private.pachanga_league_rule_document_v1(target_rule_revision_id);
declare minimum_size integer;
declare maximum_size integer;
begin
  minimum_size := nullif(document #>> '{registration,rosterPolicy,minimumSize}', '')::integer;
  maximum_size := nullif(document #>> '{registration,rosterPolicy,maximumSize}', '')::integer;
  if minimum_size is null or maximum_size is null or minimum_size < 0 or maximum_size < minimum_size then
    raise exception 'ROSTER_POLICY_INVALID' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'minimumSize', minimum_size,
    'maximumSize', maximum_size,
    'multiTeamPolicy', coalesce(
      nullif(document #>> '{registration,rosterPolicy,multiTeamPolicy}', ''),
      'FORBIDDEN_SAME_EDITION_CATEGORY'
    ),
    'credentialRequired', coalesce(
      nullif(document #>> '{registration,identityRequirements,credentialRequired}', '')::boolean,
      false
    ),
    'jerseyRequired', coalesce(
      nullif(document #>> '{registration,kitPolicy,jerseyRequired}', '')::boolean,
      false
    ),
    'jerseyMinimum', coalesce(
      nullif(document #>> '{registration,kitPolicy,jerseyNumberMinimum}', '')::integer,
      0
    ),
    'jerseyMaximum', coalesce(
      nullif(document #>> '{registration,kitPolicy,jerseyNumberMaximum}', '')::integer,
      999
    ),
    'closeRequiresApprovedRosters', coalesce(
      nullif(document #>> '{registration,rosterPolicy,closeRequiresApprovedRosters}', '')::boolean,
      false
    )
  );
end;
$$;

revoke all on function private.pachanga_league_roster_limits_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_roster_checksum_v1(target_revision_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object(
    'playerProfileId', members.player_profile_id,
    'eligibilityStatus', members.eligibility_status,
    'credentialId', members.credential_id,
    'jerseyNumber', jerseys.number
  ) order by members.player_profile_id, members.id), '[]'::jsonb)::text, 'UTF8'), 'sha256'), 'hex')
  from public.pachanga_competition_roster_members members
  left join public.pachanga_competition_player_jersey_numbers jerseys
    on jerseys.roster_member_id = members.id
  where members.roster_revision_id = target_revision_id;
$$;

revoke all on function private.pachanga_league_roster_checksum_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_finalize_roster_revision_v1(target_revision_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform set_config('pachangas.r4a_revision_write', 'on', true);
  update public.pachanga_competition_roster_revisions revisions set
    member_count = summary.member_count,
    eligibility_summary = summary.eligibility_summary,
    member_set_checksum = private.pachanga_league_roster_checksum_v1(target_revision_id)
  from (
    select count(*)::integer as member_count,
      jsonb_build_object(
        'eligible', count(*) filter (where members.eligibility_status = 'eligible'),
        'waived', count(*) filter (where members.eligibility_status = 'waived'),
        'pending', count(*) filter (where members.eligibility_status = 'pending'),
        'reviewRequired', count(*) filter (where members.eligibility_status = 'review_required'),
        'ineligible', count(*) filter (where members.eligibility_status = 'ineligible'),
        'expired', count(*) filter (where members.eligibility_status = 'expired')
      ) as eligibility_summary
    from public.pachanga_competition_roster_members members
    where members.roster_revision_id = target_revision_id
  ) summary
  where revisions.id = target_revision_id;
  perform set_config('pachangas.r4a_revision_write', 'off', true);
end;
$$;

revoke all on function private.pachanga_league_finalize_roster_revision_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_clone_roster_revision_v1(
  target_roster_id uuid,
  target_status text,
  target_actor_id uuid,
  target_reason text,
  target_server_sequence bigint,
  target_submitted_by uuid default null,
  target_reviewed_by uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_roster public.pachanga_competition_rosters%rowtype;
declare new_revision_id uuid := gen_random_uuid();
begin
  select * into selected_roster
  from public.pachanga_competition_rosters rosters
  where rosters.id = target_roster_id
  for update;
  if not found then raise exception 'ROSTER_NOT_FOUND' using errcode = 'P0002'; end if;

  insert into public.pachanga_competition_roster_revisions(
    id, roster_id, revision_number, roster_status, rule_revision_id,
    member_count, eligibility_summary, member_set_checksum,
    submitted_by, reviewed_by, effective_from, reason,
    server_sequence, created_by, created_at
  ) values (
    new_revision_id, selected_roster.id, selected_roster.revision + 1,
    target_status, selected_roster.rule_revision_id, 0, '{}'::jsonb,
    encode(extensions.digest(convert_to('[]', 'UTF8'), 'sha256'), 'hex'),
    target_submitted_by, target_reviewed_by, clock_timestamp(), trim(target_reason),
    target_server_sequence, target_actor_id, clock_timestamp()
  );

  if selected_roster.current_revision_id is not null then
    insert into public.pachanga_competition_roster_members(
      id, roster_id, roster_revision_id, entry_id, player_profile_id,
      source_group_id, source_user_id, eligibility_status, credential_id,
      effective_from, effective_until, public_snapshot, reason_code,
      server_sequence, created_at
    )
    select gen_random_uuid(), members.roster_id, new_revision_id, members.entry_id,
      members.player_profile_id, members.source_group_id, members.source_user_id,
      members.eligibility_status, members.credential_id, clock_timestamp(), null,
      members.public_snapshot, members.reason_code, target_server_sequence, clock_timestamp()
    from public.pachanga_competition_roster_members members
    where members.roster_revision_id = selected_roster.current_revision_id;

    insert into public.pachanga_competition_player_jersey_numbers(
      roster_member_id, roster_revision_id, number, valid_from, revision,
      server_sequence, assigned_by, created_at
    )
    select new_members.id, new_revision_id, jerseys.number, clock_timestamp(),
      1, target_server_sequence, target_actor_id, clock_timestamp()
    from public.pachanga_competition_roster_members old_members
    join public.pachanga_competition_player_jersey_numbers jerseys
      on jerseys.roster_member_id = old_members.id
    join public.pachanga_competition_roster_members new_members
      on new_members.roster_revision_id = new_revision_id
      and new_members.player_profile_id = old_members.player_profile_id
    where old_members.roster_revision_id = selected_roster.current_revision_id;
  end if;

  update public.pachanga_competition_rosters rosters set
    current_revision_id = new_revision_id,
    status = target_status,
    revision = rosters.revision + 1,
    server_sequence = target_server_sequence
  where rosters.id = selected_roster.id;
  perform private.pachanga_league_finalize_roster_revision_v1(new_revision_id);
  return new_revision_id;
end;
$$;

revoke all on function private.pachanga_league_clone_roster_revision_v1(uuid, text, uuid, text, bigint, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_validate_roster_v1(
  target_roster_id uuid,
  target_moment text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_roster public.pachanga_competition_rosters%rowtype;
declare limits jsonb;
declare count_members integer;
declare invalid_members integer;
declare missing_jerseys integer;
declare duplicate_jerseys integer;
begin
  select * into selected_roster
  from public.pachanga_competition_rosters rosters
  where rosters.id = target_roster_id;
  if not found then raise exception 'ROSTER_NOT_FOUND' using errcode = 'P0002'; end if;
  limits := private.pachanga_league_roster_limits_v1(selected_roster.rule_revision_id);
  select count(*),
    count(*) filter (where members.eligibility_status not in ('eligible', 'waived'))
  into count_members, invalid_members
  from public.pachanga_competition_roster_members members
  where members.roster_revision_id = selected_roster.current_revision_id;
  if count_members < (limits ->> 'minimumSize')::integer then
    raise exception 'ROSTER_BELOW_MINIMUM' using errcode = '22023';
  end if;
  if count_members > (limits ->> 'maximumSize')::integer then
    raise exception 'ROSTER_ABOVE_MAXIMUM' using errcode = '22023';
  end if;
  if target_moment = 'approve' and invalid_members > 0 then
    raise exception 'ROSTER_ELIGIBILITY_INCOMPLETE' using errcode = '22023';
  end if;
  if coalesce((limits ->> 'jerseyRequired')::boolean, false) then
    select count(*) filter (where jerseys.id is null),
      count(*) - count(distinct jerseys.number)
    into missing_jerseys, duplicate_jerseys
    from public.pachanga_competition_roster_members members
    left join public.pachanga_competition_player_jersey_numbers jerseys
      on jerseys.roster_member_id = members.id
    where members.roster_revision_id = selected_roster.current_revision_id;
    if missing_jerseys > 0 then raise exception 'ROSTER_JERSEY_REQUIRED' using errcode = '22023'; end if;
    if duplicate_jerseys > 0 then raise exception 'ROSTER_JERSEY_DUPLICATE' using errcode = 'PT409'; end if;
  end if;
  return jsonb_build_object(
    'memberCount', count_members,
    'invalidMembers', invalid_members,
    'minimumSize', (limits ->> 'minimumSize')::integer,
    'maximumSize', (limits ->> 'maximumSize')::integer
  );
end;
$$;

revoke all on function private.pachanga_league_validate_roster_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_category_snapshot_v1(target_category_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', categories.id,
    'editionId', categories.edition_id,
    'name', categories.name,
    'slug', categories.slug,
    'description', categories.description,
    'sportFormat', categories.sport_format,
    'levelLabel', categories.level_label,
    'minimumAge', categories.minimum_age,
    'maximumAge', categories.maximum_age,
    'ageReferenceDate', categories.age_reference_date,
    'eligibilityPolicy', categories.eligibility_policy,
    'visibility', categories.visibility,
    'status', categories.status,
    'ruleRevisionId', categories.rule_revision_id,
    'revision', categories.revision,
    'serverSequence', categories.server_sequence,
    'updatedAt', categories.updated_at
  )
  from public.pachanga_competition_categories categories
  where categories.id = target_category_id;
$$;

revoke all on function private.pachanga_league_category_snapshot_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_roster_snapshot_v1(
  target_roster_id uuid,
  target_actor_id uuid,
  page_offset integer default 0,
  page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_roster public.pachanga_competition_rosters%rowtype;
declare actor_scope text;
declare actor_profile_id uuid;
begin
  select * into selected_roster
  from public.pachanga_competition_rosters rosters
  where rosters.id = target_roster_id;
  if not found then raise exception 'ROSTER_NOT_FOUND' using errcode = 'P0002'; end if;
  actor_scope := private.pachanga_league_entry_actor_scope_v1(selected_roster.entry_id, target_actor_id);
  if actor_scope is null then raise exception 'ROSTER_READ_FORBIDDEN' using errcode = '42501'; end if;
  if actor_scope = 'TEAM_PLAYER' then
    select profiles.id into actor_profile_id
    from public.pachanga_player_profiles profiles
    where profiles.user_id = target_actor_id;
  end if;
  return jsonb_build_object(
    'roster', jsonb_build_object(
      'id', selected_roster.id,
      'entryId', selected_roster.entry_id,
      'competitionId', (
        select entries.competition_id from public.pachanga_competition_entries entries
        where entries.id = selected_roster.entry_id
      ),
      'teamId', (
        select entries.team_id from public.pachanga_competition_entries entries
        where entries.id = selected_roster.entry_id
      ),
      'categoryId', selected_roster.category_id,
      'ruleRevisionId', selected_roster.rule_revision_id,
      'status', selected_roster.status,
      'revision', selected_roster.revision,
      'serverSequence', selected_roster.server_sequence,
      'currentRevisionId', selected_roster.current_revision_id,
      'updatedAt', selected_roster.updated_at
    ),
    'currentRevision', (
      select jsonb_build_object(
        'id', revisions.id,
        'revisionNumber', revisions.revision_number,
        'status', revisions.roster_status,
        'memberCount', revisions.member_count,
        'eligibilitySummary', revisions.eligibility_summary,
        'checksum', revisions.member_set_checksum,
        'effectiveFrom', revisions.effective_from,
        'reason', revisions.reason
      )
      from public.pachanga_competition_roster_revisions revisions
      where revisions.id = selected_roster.current_revision_id
    ),
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', members.id,
        'playerProfileId', members.player_profile_id,
        'player', members.public_snapshot,
        'eligibilityStatus', members.eligibility_status,
        'reasonCode', members.reason_code,
        'credential', jsonb_build_object(
          'id', credentials.id,
          'status', credentials.status,
          'verificationMethod', credentials.verification_method,
          'verifiedAt', credentials.verified_at,
          'expiresAt', credentials.expires_at,
          'reasonCode', credentials.reason_code,
          'revision', credentials.revision
        ),
        'jerseyNumber', jerseys.number
      ) order by members.player_profile_id, members.id)
      from (
        select current_members.*
        from public.pachanga_competition_roster_members current_members
        where current_members.roster_revision_id = selected_roster.current_revision_id
          and (actor_scope <> 'TEAM_PLAYER' or current_members.player_profile_id = actor_profile_id)
        order by current_members.player_profile_id, current_members.id
        offset greatest(coalesce(page_offset, 0), 0)
        limit least(greatest(coalesce(page_size, 50), 1), 100)
      ) members
      left join public.pachanga_player_competition_credentials credentials
        on credentials.id = members.credential_id
      left join public.pachanga_competition_player_jersey_numbers jerseys
        on jerseys.roster_member_id = members.id
    ), '[]'::jsonb),
    'memberPagination', jsonb_build_object(
      'offset', greatest(coalesce(page_offset, 0), 0),
      'pageSize', least(greatest(coalesce(page_size, 50), 1), 100),
      'total', (
        select count(*) from public.pachanga_competition_roster_members members
        where members.roster_revision_id = selected_roster.current_revision_id
          and (actor_scope <> 'TEAM_PLAYER' or members.player_profile_id = actor_profile_id)
      )
    ),
    'warnings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'memberId', members.id,
        'playerProfileId', members.player_profile_id,
        'playerName', members.public_snapshot ->> 'displayName',
        'status', members.eligibility_status,
        'code', members.reason_code
      ) order by members.server_sequence desc, members.id desc)
      from public.pachanga_competition_roster_members members
      where members.roster_revision_id = selected_roster.current_revision_id
        and members.eligibility_status in ('pending', 'ineligible', 'review_required', 'expired')
        and (actor_scope <> 'TEAM_PLAYER' or members.player_profile_id = actor_profile_id)
    ), '[]'::jsonb),
    'kits', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', kits.id, 'type', kits.kit_type,
        'primaryColor', kits.primary_color, 'secondaryColor', kits.secondary_color,
        'pattern', kits.pattern, 'assetReference', kits.asset_reference,
        'revision', kits.revision
      ) order by kits.kit_type, kits.id)
      from public.pachanga_competition_team_kits kits
      where kits.entry_id = selected_roster.entry_id and kits.status = 'active'
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', history.id, 'revisionNumber', history.revision_number,
        'status', history.roster_status, 'memberCount', history.member_count,
        'effectiveFrom', history.effective_from, 'checksum', history.member_set_checksum
      ) order by history.revision_number desc, history.id desc)
      from (
        select revisions.* from public.pachanga_competition_roster_revisions revisions
        where revisions.roster_id = selected_roster.id
        order by revisions.revision_number desc, revisions.id desc
        limit 12
      ) history
    ), '[]'::jsonb),
    'actorScope', actor_scope
  );
end;
$$;

revoke all on function private.pachanga_league_roster_snapshot_v1(uuid, uuid, integer, integer)
  from public, anon, authenticated;

create or replace function private.pachanga_league_entry_snapshot_v1(
  target_entry_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_entry public.pachanga_competition_entries%rowtype;
declare actor_scope text;
declare include_private_reason boolean;
begin
  select * into selected_entry
  from public.pachanga_competition_entries entries
  where entries.id = target_entry_id;
  if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
  actor_scope := private.pachanga_league_entry_actor_scope_v1(target_entry_id, target_actor_id);
  if actor_scope is null then raise exception 'ENTRY_READ_FORBIDDEN' using errcode = '42501'; end if;
  include_private_reason := private.pachanga_competition_can_v1(
    selected_entry.competition_id, target_actor_id, 'entries_manage'
  );
  return jsonb_build_object(
    'competition', (
      select jsonb_build_object(
        'id', competitions.id, 'name', competitions.name,
        'type', competitions.competition_type, 'visibility', competitions.visibility,
        'organizerKind', competitions.organizer_kind,
        'organizerName', coalesce(groups.name, clubs.name)
      )
      from public.pachanga_competitions competitions
      left join public.pachanga_groups groups on groups.id = competitions.organizer_group_id
      left join public.pachanga_clubs clubs on clubs.id = competitions.organizer_club_id
      where competitions.id = selected_entry.competition_id
    ),
    'edition', (
      select jsonb_build_object(
        'id', editions.id, 'name', editions.name, 'seasonLabel', editions.season_label,
        'status', editions.status, 'registrationMode', editions.registration_mode,
        'registrationOpensAt', editions.registration_opens_at,
        'registrationClosesAt', editions.registration_closes_at,
        'revision', editions.revision
      ) from public.pachanga_competition_editions editions
      where editions.id = selected_entry.edition_id
    ),
    'category', private.pachanga_league_category_snapshot_v1(selected_entry.category_id),
    'entry', jsonb_strip_nulls(jsonb_build_object(
      'id', selected_entry.id, 'teamId', selected_entry.team_id,
      'teamName', (select groups.name from public.pachanga_groups groups where groups.id = selected_entry.team_id),
      'source', selected_entry.entry_source, 'status', selected_entry.status,
      'ruleRevisionId', selected_entry.rule_revision_id,
      'submittedAt', selected_entry.submitted_at, 'acceptedAt', selected_entry.accepted_at,
      'rejectedAt', selected_entry.rejected_at, 'withdrawnAt', selected_entry.withdrawn_at,
      'reasonCode', selected_entry.reason_code,
      'privateReason', case when include_private_reason then selected_entry.reason_text_private else null end,
      'revision', selected_entry.revision, 'serverSequence', selected_entry.server_sequence,
      'updatedAt', selected_entry.updated_at
    )),
    'delegates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', delegates.id,
        'displayName', coalesce(profiles.display_name, 'Usuario registrado'),
        'role', delegates.delegate_role, 'status', delegates.status,
        'validFrom', delegates.valid_from, 'validUntil', delegates.valid_until,
        'revision', delegates.revision
      ) order by delegates.server_sequence desc, delegates.id desc)
      from public.pachanga_competition_team_delegates delegates
      left join public.pachanga_player_profiles profiles on profiles.user_id = delegates.user_id
      where delegates.entry_id = selected_entry.id
    ), '[]'::jsonb),
    'roster', (
      select jsonb_build_object(
        'id', rosters.id, 'status', rosters.status, 'revision', rosters.revision,
        'currentRevisionId', rosters.current_revision_id,
        'eligibilityHealth', revisions.eligibility_summary,
        'memberCount', revisions.member_count
      )
      from public.pachanga_competition_rosters rosters
      left join public.pachanga_competition_roster_revisions revisions
        on revisions.id = rosters.current_revision_id
      where rosters.entry_id = selected_entry.id
    ),
    'stageMembership', (
      select jsonb_build_object(
        'id', memberships.id, 'stageId', memberships.stage_id,
        'stageName', stages.name, 'divisionId', memberships.division_id,
        'divisionName', divisions.name, 'groupId', memberships.competition_group_id,
        'groupName', competition_groups.name, 'validFrom', memberships.valid_from,
        'revision', memberships.revision
      )
      from public.pachanga_competition_stage_memberships memberships
      join public.pachanga_competition_stages stages on stages.id = memberships.stage_id
      left join public.pachanga_competition_divisions divisions on divisions.id = memberships.division_id
      left join public.pachanga_competition_groups competition_groups
        on competition_groups.id = memberships.competition_group_id
      where memberships.entry_id = selected_entry.id and memberships.status = 'active'
      order by memberships.server_sequence desc, memberships.id desc limit 1
    ),
    'availabilityConstraints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', constraints.id, 'weekday', constraints.weekday,
        'startLocalTime', constraints.start_local_time,
        'endLocalTime', constraints.end_local_time,
        'timezone', constraints.timezone, 'validFromDate', constraints.valid_from_date,
        'validUntilDate', constraints.valid_until_date, 'reason', constraints.reason,
        'revision', constraints.revision
      ) order by constraints.weekday, constraints.start_local_time, constraints.id)
      from public.pachanga_team_availability_constraints constraints
      where constraints.entry_id = selected_entry.id and constraints.status = 'active'
    ), '[]'::jsonb),
    'schedulePreferences', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', preferences.id, 'weekday', preferences.weekday,
        'startLocalTime', preferences.start_local_time,
        'endLocalTime', preferences.end_local_time,
        'timezone', preferences.timezone, 'weight', preferences.weight,
        'preferredArea', preferences.preferred_area,
        'venueReference', preferences.venue_reference,
        'revision', preferences.revision
      ) order by preferences.weight desc, preferences.weekday, preferences.id)
      from public.pachanga_team_schedule_preferences preferences
      where preferences.entry_id = selected_entry.id and preferences.status = 'active'
    ), '[]'::jsonb),
    'actorScope', actor_scope,
    'nextActions', private.pachanga_league_next_actions_v1(selected_entry.id, target_actor_id)
  );
end;
$$;

revoke all on function private.pachanga_league_entry_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_notify_team_v1(
  target_entry_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare recipient record;
begin
  for recipient in
    select groups.owner_id as user_id
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = target_entry_id
    union
    select delegates.user_id
    from public.pachanga_competition_team_delegates delegates
    where delegates.entry_id = target_entry_id and delegates.status = 'active'
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, target_kind, target_title, target_body,
      '/mis-competiciones/inscripciones',
      jsonb_build_object('entryId', target_entry_id),
      'league:' || target_operation_id::text || ':' || recipient.user_id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_league_notify_team_v1(uuid, text, text, text, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_notify_organizer_v1(
  target_competition_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_operation_id uuid,
  target_entry_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare recipient record;
begin
  for recipient in
    with competition as (
      select * from public.pachanga_competitions where id = target_competition_id
    )
    select groups.owner_id as user_id
    from competition join public.pachanga_groups groups
      on groups.id = competition.organizer_group_id
    union
    select memberships.user_id
    from competition join public.pachanga_club_memberships memberships
      on memberships.club_id = competition.organizer_club_id
    where memberships.status = 'active'
      and memberships.role in ('club_owner', 'club_competition_manager')
    union
    select assignments.user_id
    from public.pachanga_competition_staff_assignments assignments
    where assignments.competition_id = target_competition_id
      and assignments.status = 'active'
      and assignments.staff_role in (
        'competition_director', 'competition_admin',
        'competition_registration_manager', 'competition_roster_manager'
      )
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, target_kind, target_title, target_body,
      '/competiciones/' || target_competition_id::text || '/gestion/inscripciones',
      jsonb_strip_nulls(jsonb_build_object('competitionId', target_competition_id, 'entryId', target_entry_id)),
      'league:' || target_operation_id::text || ':' || recipient.user_id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_league_notify_organizer_v1(uuid, text, text, text, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_target_group_id uuid,
  target_target_user_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_reason_code text,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_confirmed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition public.pachanga_competitions%rowtype;
declare response jsonb;
begin
  select * into selected_competition
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', target_aggregate_type,
      'entityId', target_aggregate_id,
      'revision', target_confirmed_revision
    ))
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated', target_aggregate_type,
    target_aggregate_id::text, target_competition_id, target_action,
    target_confirmed_revision, target_server_sequence, left(target_reason_code, 120),
    coalesce(target_event_payload, '{}'::jsonb), target_confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    target_server_sequence, target_competition_id,
    selected_competition.organizer_group_id, selected_competition.organizer_club_id,
    target_target_group_id, target_target_user_id, target_aggregate_type,
    target_aggregate_id::text, target_confirmed_revision, target_confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated', target_action,
    target_aggregate_type, target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence, target_client_metadata,
    response, target_confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_league_store_command_v1(
  uuid, uuid, text, text, uuid, uuid, uuid, uuid, bigint, bigint,
  text, text, jsonb, jsonb, jsonb, timestamptz
) from public, anon, authenticated;

create or replace function private.pachanga_league_create_empty_roster_v1(
  target_entry_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint,
  target_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_entry public.pachanga_competition_entries%rowtype;
declare roster_id uuid := gen_random_uuid();
declare revision_id uuid := gen_random_uuid();
begin
  select * into selected_entry
  from public.pachanga_competition_entries entries
  where entries.id = target_entry_id;
  if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
  insert into public.pachanga_competition_rosters(
    id, entry_id, category_id, rule_revision_id, status, revision,
    server_sequence, created_by, created_at, updated_at
  ) values (
    roster_id, selected_entry.id, selected_entry.category_id,
    selected_entry.rule_revision_id, 'draft', 1,
    target_server_sequence, target_actor_id, clock_timestamp(), clock_timestamp()
  );
  insert into public.pachanga_competition_roster_revisions(
    id, roster_id, revision_number, roster_status, rule_revision_id,
    member_count, eligibility_summary, member_set_checksum, effective_from,
    reason, server_sequence, created_by, created_at
  ) values (
    revision_id, roster_id, 1, 'draft', selected_entry.rule_revision_id,
    0, jsonb_build_object(
      'eligible', 0, 'waived', 0, 'pending', 0,
      'reviewRequired', 0, 'ineligible', 0, 'expired', 0
    ), encode(extensions.digest(convert_to('[]', 'UTF8'), 'sha256'), 'hex'),
    clock_timestamp(), left(trim(target_reason), 1200), target_server_sequence,
    target_actor_id, clock_timestamp()
  );
  update public.pachanga_competition_rosters rosters
  set current_revision_id = revision_id
  where rosters.id = roster_id;
  return roster_id;
end;
$$;

revoke all on function private.pachanga_league_create_empty_roster_v1(uuid, uuid, bigint, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_member_eligibility_v1(
  target_profile_id uuid,
  target_category_id uuid,
  target_rule_revision_id uuid,
  target_credential_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_profile public.pachanga_player_profiles%rowtype;
declare selected_category public.pachanga_competition_categories%rowtype;
declare selected_credential public.pachanga_player_competition_credentials%rowtype;
declare limits jsonb := private.pachanga_league_roster_limits_v1(target_rule_revision_id);
declare age_at_reference integer;
declare credential_required boolean;
begin
  select * into selected_profile
  from public.pachanga_player_profiles profiles where profiles.id = target_profile_id;
  if not found then raise exception 'PLAYER_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into selected_category
  from public.pachanga_competition_categories categories where categories.id = target_category_id;
  if not found then raise exception 'CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;
  if target_credential_id is not null then
    select * into selected_credential
    from public.pachanga_player_competition_credentials credentials
    where credentials.id = target_credential_id;
  end if;
  credential_required := coalesce(
    nullif(selected_category.eligibility_policy ->> 'credentialRequired', '')::boolean,
    (limits ->> 'credentialRequired')::boolean,
    false
  );
  if selected_category.age_reference_date is not null and selected_profile.birth_date is not null then
    age_at_reference := extract(year from age(selected_category.age_reference_date, selected_profile.birth_date))::integer;
  end if;
  if (selected_category.minimum_age is not null or selected_category.maximum_age is not null)
     and age_at_reference is null then
    return jsonb_build_object('status', 'pending', 'reasonCode', 'eligibility.birth_date_required');
  end if;
  if selected_category.minimum_age is not null and age_at_reference < selected_category.minimum_age then
    return jsonb_build_object('status', 'ineligible', 'reasonCode', 'eligibility.minimum_age');
  end if;
  if selected_category.maximum_age is not null and age_at_reference > selected_category.maximum_age then
    return jsonb_build_object('status', 'ineligible', 'reasonCode', 'eligibility.maximum_age');
  end if;
  if credential_required and (
    target_credential_id is null
    or selected_credential.status <> 'verified'
    or (selected_credential.expires_at is not null and selected_credential.expires_at <= clock_timestamp())
  ) then
    return jsonb_build_object('status', 'pending', 'reasonCode', 'eligibility.credential_required');
  end if;
  return jsonb_build_object('status', 'eligible', 'reasonCode', 'eligibility.valid');
end;
$$;

revoke all on function private.pachanga_league_member_eligibility_v1(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_assert_multi_team_v1(
  target_player_profile_id uuid,
  target_entry_id uuid,
  target_rule_revision_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_entry public.pachanga_competition_entries%rowtype;
declare limits jsonb := private.pachanga_league_roster_limits_v1(target_rule_revision_id);
declare policy text;
begin
  select * into selected_entry
  from public.pachanga_competition_entries entries where entries.id = target_entry_id;
  if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
  policy := upper(coalesce(limits ->> 'multiTeamPolicy', ''));
  if policy not in ('FORBIDDEN_SAME_EDITION_CATEGORY', 'ALLOWED_DIFFERENT_CATEGORY', 'ALLOWED') then
    raise exception 'MULTI_TEAM_POLICY_INVALID' using errcode = '22023';
  end if;
  if policy <> 'ALLOWED' and exists (
    select 1
    from public.pachanga_competition_roster_members members
    join public.pachanga_competition_rosters rosters
      on rosters.id = members.roster_id
      and rosters.current_revision_id = members.roster_revision_id
    join public.pachanga_competition_entries entries on entries.id = rosters.entry_id
    where members.player_profile_id = target_player_profile_id
      and entries.id <> selected_entry.id
      and entries.edition_id = selected_entry.edition_id
      and entries.category_id = selected_entry.category_id
      and entries.status in ('accepted', 'active')
      and rosters.status in (
        'draft', 'submitted', 'approved', 'locked', 'changes_requested', 'amended'
      )
  ) then
    raise exception 'PLAYER_MULTI_TEAM_CONFLICT' using errcode = 'PT409';
  end if;
end;
$$;

revoke all on function private.pachanga_league_assert_multi_team_v1(uuid, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_assert_team_owner_v1(
  target_team_id uuid,
  target_actor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1 from public.pachanga_groups groups
    where groups.id = target_team_id and groups.owner_id = target_actor_id
  ) then raise exception 'TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
end;
$$;

revoke all on function private.pachanga_league_assert_team_owner_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_assert_roster_manager_v1(
  target_entry_id uuid,
  target_actor_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare scope text := private.pachanga_league_entry_actor_scope_v1(target_entry_id, target_actor_id);
begin
  if scope is null
     or scope not in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER') then
    raise exception 'ROSTER_MANAGER_REQUIRED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_league_assert_roster_manager_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.command_pachanga_league_participation_v1(
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
declare request_hash text;
declare replay jsonb;
declare metadata jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare command_reason text;
declare command_reason_code text;
declare competition_id uuid;
declare target_group_id uuid;
declare target_user_id uuid;
declare confirmed_revision bigint;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare aggregate_type text := 'league_participation';
declare created_id uuid;
declare created_secondary_id uuid;
declare previous_delegate_id uuid;
declare new_revision_id uuid;
declare selected_role text;
declare selected_status text;
declare selected_mode text;
declare selected_type text;
declare selected_slug text;
declare selected_name text;
declare selected_rule_revision_id uuid;
declare selected_team_id uuid;
declare selected_user_id uuid;
declare selected_profile_id uuid;
declare selected_stage_id uuid;
declare selected_division_id uuid;
declare selected_group_id uuid;
declare selected_credential_id uuid;
declare selected_number integer;
declare selected_weekday integer;
declare selected_weight integer;
declare selected_start_time time;
declare selected_end_time time;
declare selected_opens_at timestamptz;
declare selected_closes_at timestamptz;
declare selected_valid_until timestamptz;
declare selected_reference text;
declare selected_document jsonb;
declare selected_limits jsonb;
declare selected_eligibility jsonb;
declare response jsonb;
declare pending_count bigint;
declare actor_scope text;
declare competition_row public.pachanga_competitions%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare category_row public.pachanga_competition_categories%rowtype;
declare entry_row public.pachanga_competition_entries%rowtype;
declare invitation_row public.pachanga_competition_entry_invitations%rowtype;
declare delegate_row public.pachanga_competition_team_delegates%rowtype;
declare roster_row public.pachanga_competition_rosters%rowtype;
declare credential_row public.pachanga_player_competition_credentials%rowtype;
declare member_row public.pachanga_competition_roster_members%rowtype;
declare stage_row public.pachanga_competition_stages%rowtype;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or normalized_action = '' or expected_revision < 0 then
    raise exception 'INVALID_LEAGUE_PARTICIPATION_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_LEAGUE_PARTICIPATION_PAYLOAD' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if normalized_action in (
    'round.create', 'fixture.generate', 'match.create', 'match_squad.create',
    'temporary_player.request', 'result.submit', 'standing.rebuild',
    'edition.scheduled', 'edition.active', 'edition.completed'
  ) then raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000'; end if;

  metadata := private.pachanga_competition_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb));
  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91404));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, 'authenticated', normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  command_reason := left(coalesce(nullif(trim(payload ->> 'reason'), ''), normalized_action), 1200);
  command_reason_code := left(coalesce(nullif(trim(payload ->> 'reasonCode'), ''), normalized_action), 120);

  if normalized_action = 'category.create' then
    perform private.pachanga_league_assert_flags_v1();
    select * into edition_row
    from public.pachanga_competition_editions editions
    where editions.id = aggregate_id for update;
    if not found then raise exception 'EDITION_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(edition_row.competition_id);
    competition_id := competition_row.id;
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'categories_manage') then
      raise exception 'COMPETITION_CATEGORY_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if edition_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if edition_row.status <> 'draft' then raise exception 'EDITION_NOT_DRAFT' using errcode = '22023'; end if;
    selected_rule_revision_id := (payload ->> 'ruleRevisionId')::uuid;
    perform private.pachanga_league_rule_document_v1(selected_rule_revision_id);
    if not exists (
      select 1 from public.pachanga_competition_rule_revisions revisions
      join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = revisions.rule_set_id
      where revisions.id = selected_rule_revision_id
        and rule_sets.competition_id = competition_row.id
    ) then raise exception 'RULE_REVISION_SCOPE_MISMATCH' using errcode = '22023'; end if;
    created_id := gen_random_uuid();
    insert into public.pachanga_competition_categories(
      id, edition_id, name, slug, description, sport_format, level_label,
      minimum_age, maximum_age, age_reference_date, eligibility_policy,
      visibility, status, rule_revision_id, server_sequence, created_by
    ) values (
      created_id, edition_row.id, trim(coalesce(payload ->> 'name', '')),
      lower(trim(coalesce(payload ->> 'slug', ''))),
      left(coalesce(payload ->> 'description', ''), 1200),
      trim(coalesce(payload ->> 'sportFormat', '')),
      nullif(left(trim(coalesce(payload ->> 'levelLabel', '')), 80), ''),
      nullif(payload ->> 'minimumAge', '')::integer,
      nullif(payload ->> 'maximumAge', '')::integer,
      nullif(payload ->> 'ageReferenceDate', '')::date,
      case when jsonb_typeof(payload -> 'eligibilityPolicy') = 'object'
        then payload -> 'eligibilityPolicy' else '{}'::jsonb end,
      coalesce(nullif(lower(payload ->> 'visibility'), ''), 'internal'),
      'draft', selected_rule_revision_id, sequence_value, actor_id
    );
    update public.pachanga_competition_editions editions set
      revision = editions.revision + 1,
      server_sequence = sequence_value
    where editions.id = edition_row.id
    returning editions.revision into confirmed_revision;
    snapshot := private.pachanga_league_category_snapshot_v1(created_id);
    aggregate_type := 'competition_edition';
    event_payload := jsonb_build_object('categoryId', created_id, 'status', 'draft');

  elsif normalized_action in ('category.activate', 'category.close', 'category.archive') then
    perform private.pachanga_league_assert_flags_v1();
    select * into category_row
    from public.pachanga_competition_categories categories
    where categories.id = aggregate_id for update;
    if not found then raise exception 'CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = category_row.edition_id for update;
    competition_row := private.pachanga_league_assert_competition_v1(edition_row.competition_id);
    competition_id := competition_row.id;
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'categories_manage') then
      raise exception 'COMPETITION_CATEGORY_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if category_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    selected_status := case normalized_action
      when 'category.activate' then 'active'
      when 'category.close' then 'closed'
      else 'archived' end;
    if (selected_status = 'active' and category_row.status <> 'draft')
       or (selected_status = 'closed' and category_row.status <> 'active')
       or (selected_status = 'archived' and category_row.status not in ('draft', 'closed')) then
      raise exception 'CATEGORY_TRANSITION_NOT_ALLOWED' using errcode = '22023';
    end if;
    update public.pachanga_competition_categories categories set
      status = selected_status, revision = categories.revision + 1,
      server_sequence = sequence_value
    where categories.id = category_row.id
    returning categories.revision into confirmed_revision;
    snapshot := private.pachanga_league_category_snapshot_v1(category_row.id);
    aggregate_type := 'competition_category';
    event_payload := jsonb_build_object('status', selected_status);

  elsif normalized_action = 'registration.open' then
    perform private.pachanga_league_assert_flags_v1(true, false, false, false, false);
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = aggregate_id for update;
    if not found then raise exception 'EDITION_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(edition_row.competition_id);
    competition_id := competition_row.id;
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'entries_manage') then
      raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if not private.pachanga_competition_active_entitlement_v2(
      competition_row.organizer_kind,
      coalesce(competition_row.organizer_group_id, competition_row.organizer_club_id),
      'competition_manage'
    ) then raise exception 'COMPETITION_MANAGE_ENTITLEMENT_REQUIRED' using errcode = '42501'; end if;
    if competition_row.organizer_kind = 'CLUB' and not exists (
      select 1 from public.pachanga_clubs clubs
      where clubs.id = competition_row.organizer_club_id
        and clubs.operational_status = 'active'
    ) then raise exception 'ORGANIZER_NOT_ACTIVE' using errcode = '42501'; end if;
    if edition_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if edition_row.status <> 'draft' then raise exception 'REGISTRATION_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
    selected_mode := upper(trim(coalesce(payload ->> 'registrationMode', '')));
    if selected_mode not in ('PUBLIC_APPROVAL', 'INVITE_ONLY') then
      raise exception 'REGISTRATION_MODE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    if selected_mode = 'PUBLIC_APPROVAL' then
      perform private.pachanga_league_assert_flags_v1(true, true, false, false, false);
    end if;
    selected_rule_revision_id := coalesce(
      nullif(payload ->> 'ruleRevisionId', '')::uuid,
      edition_row.rule_revision_id
    );
    selected_document := private.pachanga_league_rule_document_v1(selected_rule_revision_id);
    if jsonb_typeof(selected_document #> '{registration,registrationPolicy}') <> 'object' then
      raise exception 'REGISTRATION_POLICY_INVALID' using errcode = '22023';
    end if;
    perform private.pachanga_league_registration_limits_v1(selected_rule_revision_id);
    if not exists (
      select 1 from public.pachanga_competition_categories categories
      where categories.edition_id = edition_row.id and categories.status = 'active'
    ) then raise exception 'ACTIVE_CATEGORY_REQUIRED' using errcode = '22023'; end if;
    selected_opens_at := coalesce(nullif(payload ->> 'opensAt', '')::timestamptz, confirmed_at);
    selected_closes_at := nullif(payload ->> 'closesAt', '')::timestamptz;
    if selected_closes_at is null or selected_closes_at <= selected_opens_at
       or selected_opens_at > confirmed_at then
      raise exception 'REGISTRATION_WINDOW_INVALID' using errcode = '22023';
    end if;
    update public.pachanga_competition_editions editions set
      status = 'registration_open', registration_mode = selected_mode,
      registration_opens_at = selected_opens_at,
      registration_closes_at = selected_closes_at,
      registration_closed_at = null,
      registration_rule_revision_id = selected_rule_revision_id,
      rule_revision_id = selected_rule_revision_id,
      revision = editions.revision + 1,
      server_sequence = sequence_value
    where editions.id = edition_row.id
    returning editions.revision into confirmed_revision;
    snapshot := jsonb_build_object(
      'editionId', edition_row.id, 'status', 'registration_open',
      'registrationMode', selected_mode, 'registrationOpensAt', selected_opens_at,
      'registrationClosesAt', selected_closes_at,
      'ruleRevisionId', selected_rule_revision_id,
      'revision', confirmed_revision
    );
    aggregate_type := 'competition_edition';
    event_payload := snapshot;

  elsif normalized_action = 'registration.notify_closing' then
    perform private.pachanga_league_assert_flags_v1(true, false, false, false, false);
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = aggregate_id for update;
    if not found then raise exception 'EDITION_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(edition_row.competition_id);
    competition_id := competition_row.id;
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'entries_manage') then
      raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if edition_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if edition_row.status <> 'registration_open' or edition_row.registration_closes_at <= confirmed_at then
      raise exception 'REGISTRATION_NOT_OPEN' using errcode = '22023';
    end if;
    if exists (
      select 1 from private.pachanga_competition_events events
      where events.aggregate_type = 'competition_edition'
        and events.aggregate_id = edition_row.id::text
        and events.action = 'registration.notify_closing'
        and events.confirmed_at >= edition_row.registration_opens_at
    ) then raise exception 'REGISTRATION_CLOSING_ALREADY_NOTIFIED' using errcode = 'PT409'; end if;
    for entry_row in
      select * from public.pachanga_competition_entries entries
      where entries.edition_id = edition_row.id
        and entries.status in ('submitted', 'invited', 'accepted')
    loop
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_registration_closing', 'La inscripción termina pronto',
        'Consulta la fecha límite y completa las acciones pendientes de tu equipo.', operation_id
      );
    end loop;
    confirmed_revision := edition_row.revision;
    snapshot := jsonb_build_object(
      'editionId', edition_row.id,
      'status', edition_row.status,
      'registrationClosesAt', edition_row.registration_closes_at,
      'revision', confirmed_revision
    );
    aggregate_type := 'competition_edition';
    event_payload := jsonb_build_object(
      'registrationClosesAt', edition_row.registration_closes_at,
      'notification', 'league_registration_closing'
    );

  elsif normalized_action in ('registration.close', 'registration.close_and_expire_pending') then
    perform private.pachanga_league_assert_flags_v1(true, false, false, false, false);
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = aggregate_id for update;
    if not found then raise exception 'EDITION_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(edition_row.competition_id);
    competition_id := competition_row.id;
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'entries_manage') then
      raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if edition_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if edition_row.status <> 'registration_open' then
      raise exception 'REGISTRATION_TRANSITION_NOT_ALLOWED' using errcode = '22023';
    end if;
    select count(*) into pending_count
    from public.pachanga_competition_entries entries
    where entries.edition_id = edition_row.id and entries.status in ('submitted', 'invited');
    if pending_count > 0 and normalized_action = 'registration.close' then
      raise exception 'REGISTRATION_PENDING_ENTRIES' using errcode = 'PT409';
    end if;
    selected_limits := private.pachanga_league_roster_limits_v1(edition_row.registration_rule_revision_id);
    if coalesce((selected_limits ->> 'closeRequiresApprovedRosters')::boolean, false)
       and exists (
         select 1 from public.pachanga_competition_entries entries
         left join public.pachanga_competition_rosters rosters on rosters.entry_id = entries.id
         where entries.edition_id = edition_row.id and entries.status = 'accepted'
           and coalesce(rosters.status, '') not in ('approved', 'locked')
       ) then raise exception 'REGISTRATION_ROSTERS_NOT_READY' using errcode = 'PT409'; end if;
    if normalized_action = 'registration.close_and_expire_pending' then
      update public.pachanga_competition_entries entries set
        status = case when entries.status = 'invited' then 'expired' else 'rejected' end,
        rejected_at = case when entries.status = 'submitted' then confirmed_at else entries.rejected_at end,
        reason_code = 'registration.closed', reason_text_private = command_reason,
        revision = entries.revision + 1, server_sequence = sequence_value
      where entries.edition_id = edition_row.id and entries.status in ('submitted', 'invited');
      update public.pachanga_competition_entry_invitations invitations set
        status = 'expired', responded_at = confirmed_at,
        revision = invitations.revision + 1, server_sequence = sequence_value
      where invitations.entry_id in (
        select entries.id from public.pachanga_competition_entries entries
        where entries.edition_id = edition_row.id and entries.status = 'expired'
      ) and invitations.status = 'pending';
    end if;
    update public.pachanga_competition_editions editions set
      status = 'registration_closed', registration_mode = 'CLOSED',
      registration_closed_at = confirmed_at,
      revision = editions.revision + 1, server_sequence = sequence_value
    where editions.id = edition_row.id
    returning editions.revision into confirmed_revision;
    snapshot := jsonb_build_object(
      'editionId', edition_row.id, 'status', 'registration_closed',
      'registrationClosedAt', confirmed_at, 'expiredPendingCount', pending_count,
      'revision', confirmed_revision
    );
    aggregate_type := 'competition_edition';
    event_payload := snapshot;
    for entry_row in
      select * from public.pachanga_competition_entries entries
      where entries.edition_id = edition_row.id and entries.status in ('accepted', 'rejected', 'expired')
    loop
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_registration_closed', 'Inscripción cerrada',
        'La organización ha cerrado la inscripción de la competición.', operation_id
      );
    end loop;

  elsif normalized_action in ('entry.submit', 'entry.invite') then
    perform private.pachanga_league_assert_flags_v1(
      true, normalized_action = 'entry.submit', false, false, false
    );
    select * into category_row
    from public.pachanga_competition_categories categories
    where categories.id = aggregate_id for update;
    if not found then raise exception 'CATEGORY_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = category_row.edition_id for update;
    competition_row := private.pachanga_league_assert_competition_v1(edition_row.competition_id);
    competition_id := competition_row.id;
    if category_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if category_row.status <> 'active' then raise exception 'CATEGORY_NOT_ACTIVE' using errcode = '22023'; end if;
    if edition_row.status <> 'registration_open' or confirmed_at < edition_row.registration_opens_at
       or confirmed_at >= edition_row.registration_closes_at then
      raise exception 'REGISTRATION_NOT_OPEN' using errcode = '22023';
    end if;
    selected_team_id := (payload ->> 'teamId')::uuid;
    selected_limits := private.pachanga_league_registration_limits_v1(
      edition_row.registration_rule_revision_id
    );
    if (
      select count(*) from public.pachanga_competition_entries entries
      where entries.edition_id = edition_row.id
        and entries.category_id = category_row.id
        and entries.status in ('draft', 'submitted', 'invited', 'accepted', 'active')
    ) >= (selected_limits ->> 'maximum')::integer then
      raise exception 'REGISTRATION_TEAM_LIMIT_REACHED' using errcode = 'PT409';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
      edition_row.id::text || ':' || category_row.id::text || ':' || selected_team_id::text, 91405
    ));
    if normalized_action = 'entry.submit' then
      if edition_row.registration_mode <> 'PUBLIC_APPROVAL' then
        raise exception 'PUBLIC_REGISTRATION_NOT_AVAILABLE' using errcode = '0A000';
      end if;
      perform private.pachanga_league_assert_team_owner_v1(selected_team_id, actor_id);
      selected_type := 'PUBLIC_APPLICATION';
      selected_status := 'submitted';
    else
      if not private.pachanga_competition_can_v1(competition_id, actor_id, 'entries_manage') then
        raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
      end if;
      if not exists (select 1 from public.pachanga_groups groups where groups.id = selected_team_id) then
        raise exception 'TEAM_NOT_FOUND' using errcode = 'P0002';
      end if;
      selected_type := 'ORGANIZER_INVITATION';
      selected_status := 'invited';
    end if;
    created_id := gen_random_uuid();
    insert into public.pachanga_competition_entries(
      id, competition_id, edition_id, category_id, team_id, entry_source,
      status, rule_revision_id, submitted_by, submitted_at, reason_code,
      reason_text_private, revision, server_sequence, created_by
    ) values (
      created_id, competition_id, edition_row.id, category_row.id, selected_team_id,
      selected_type, selected_status, edition_row.registration_rule_revision_id,
      case when normalized_action = 'entry.submit' then actor_id else null end,
      case when normalized_action = 'entry.submit' then confirmed_at else null end,
      command_reason_code,
      case when normalized_action = 'entry.invite' then command_reason else '' end,
      1, sequence_value, actor_id
    );
    if normalized_action = 'entry.invite' then
      created_secondary_id := gen_random_uuid();
      insert into public.pachanga_competition_entry_invitations(
        id, entry_id, team_id, status, expires_at, revision,
        server_sequence, invited_by
      ) values (
        created_secondary_id, created_id, selected_team_id, 'pending',
        nullif(payload ->> 'expiresAt', '')::timestamptz, 1,
        sequence_value, actor_id
      );
      perform private.pachanga_league_notify_team_v1(
        created_id, 'league_entry_invitation', 'Invitación a competición',
        'Tu equipo ha recibido una invitación privada.', operation_id
      );
    else
      perform private.pachanga_league_notify_organizer_v1(
        competition_id, 'league_entry_submitted', 'Nueva solicitud de inscripción',
        'Un equipo ha solicitado participar.', operation_id, created_id
      );
    end if;
    confirmed_revision := 1;
    snapshot := private.pachanga_league_entry_snapshot_v1(created_id, actor_id);
    aggregate_type := 'competition_category';
    target_group_id := selected_team_id;
    event_payload := jsonb_build_object(
      'entryId', created_id, 'source', selected_type, 'status', selected_status
    );

  elsif normalized_action in ('entry.accept', 'entry.reject', 'entry.withdraw', 'entry.decline') then
    perform private.pachanga_league_assert_flags_v1(true, false, false, false, false);
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = aggregate_id for update;
    if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    if entry_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = entry_row.edition_id for update;
    if normalized_action = 'entry.accept' then
      if entry_row.status = 'submitted' then
        if not private.pachanga_competition_can_v1(competition_id, actor_id, 'entries_manage') then
          raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
        end if;
      elsif entry_row.status = 'invited' then
        perform private.pachanga_league_assert_team_owner_v1(entry_row.team_id, actor_id);
        select * into invitation_row
        from public.pachanga_competition_entry_invitations invitations
        where invitations.entry_id = entry_row.id for update;
        if invitation_row.status <> 'pending'
           or (invitation_row.expires_at is not null and invitation_row.expires_at <= confirmed_at) then
          raise exception 'ENTRY_INVITATION_NOT_PENDING' using errcode = '22023';
        end if;
        update public.pachanga_competition_entry_invitations invitations set
          status = 'accepted', responded_by = actor_id, responded_at = confirmed_at,
          revision = invitations.revision + 1, server_sequence = sequence_value
        where invitations.id = invitation_row.id;
      else raise exception 'ENTRY_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      update public.pachanga_competition_entries entries set
        status = 'accepted', accepted_by = actor_id, accepted_at = confirmed_at,
        submitted_by = coalesce(entries.submitted_by, actor_id),
        submitted_at = coalesce(entries.submitted_at, confirmed_at),
        reason_code = command_reason_code,
        reason_text_private = case when entry_row.status = 'submitted'
          then command_reason else entries.reason_text_private end,
        revision = entries.revision + 1, server_sequence = sequence_value
      where entries.id = entry_row.id
      returning entries.revision into confirmed_revision;
      if not exists (
        select 1 from public.pachanga_competition_rosters rosters where rosters.entry_id = entry_row.id
      ) then
        perform private.pachanga_league_create_empty_roster_v1(
          entry_row.id, actor_id, sequence_value, 'Roster draft created after entry acceptance'
        );
      end if;
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_entry_accepted', 'Inscripción aceptada',
        'La participación del equipo ha sido aceptada.', operation_id
      );
      perform private.pachanga_league_notify_organizer_v1(
        competition_id, 'league_entry_accepted', 'Inscripción confirmada',
        'El equipo ya forma parte de la edición.', operation_id, entry_row.id
      );
      selected_status := 'accepted';
    elsif normalized_action = 'entry.reject' then
      if entry_row.status <> 'submitted' then raise exception 'ENTRY_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      if not private.pachanga_competition_can_v1(competition_id, actor_id, 'entries_manage') then
        raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
      end if;
      update public.pachanga_competition_entries entries set
        status = 'rejected', rejected_at = confirmed_at,
        reason_code = command_reason_code,
        reason_text_private = command_reason, revision = entries.revision + 1,
        server_sequence = sequence_value
      where entries.id = entry_row.id returning entries.revision into confirmed_revision;
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_entry_rejected', 'Solicitud no aceptada',
        'La organización ha resuelto la solicitud.', operation_id
      );
      selected_status := 'rejected';
    elsif normalized_action = 'entry.withdraw' then
      if entry_row.status not in ('submitted', 'accepted') then
        raise exception 'ENTRY_TRANSITION_NOT_ALLOWED' using errcode = '22023';
      end if;
      perform private.pachanga_league_assert_team_owner_v1(entry_row.team_id, actor_id);
      update public.pachanga_competition_entries entries set
        status = 'withdrawn', withdrawn_at = confirmed_at,
        reason_code = command_reason_code,
        reason_text_private = command_reason, revision = entries.revision + 1,
        server_sequence = sequence_value
      where entries.id = entry_row.id returning entries.revision into confirmed_revision;
      perform private.pachanga_league_notify_organizer_v1(
        competition_id, 'league_entry_withdrawn', 'Equipo retirado',
        'Un equipo ha retirado su participación.', operation_id, entry_row.id
      );
      selected_status := 'withdrawn';
    else
      if entry_row.status <> 'invited' then raise exception 'ENTRY_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      perform private.pachanga_league_assert_team_owner_v1(entry_row.team_id, actor_id);
      update public.pachanga_competition_entry_invitations invitations set
        status = 'declined', responded_by = actor_id, responded_at = confirmed_at,
        revision = invitations.revision + 1, server_sequence = sequence_value
      where invitations.entry_id = entry_row.id and invitations.status = 'pending';
      update public.pachanga_competition_entries entries set
        status = 'declined', reason_code = command_reason_code,
        reason_text_private = command_reason,
        revision = entries.revision + 1, server_sequence = sequence_value
      where entries.id = entry_row.id returning entries.revision into confirmed_revision;
      perform private.pachanga_league_notify_organizer_v1(
        competition_id, 'league_entry_declined', 'Invitación rechazada',
        'El equipo ha rechazado la invitación.', operation_id, entry_row.id
      );
      selected_status := 'declined';
    end if;
    snapshot := private.pachanga_league_entry_snapshot_v1(entry_row.id, actor_id);
    aggregate_type := 'competition_entry';
    event_payload := jsonb_build_object('status', selected_status);

  elsif normalized_action in ('delegate.invite', 'delegate.primary.transfer', 'delegate.transfer') then
    perform private.pachanga_league_assert_flags_v1(false, false, true, false, false);
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = aggregate_id for update;
    if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    perform private.pachanga_league_assert_team_owner_v1(entry_row.team_id, actor_id);
    if entry_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if entry_row.status <> 'accepted' then raise exception 'ENTRY_NOT_ACCEPTED' using errcode = '22023'; end if;
    if normalized_action = 'delegate.invite' then
      selected_user_id := (payload ->> 'userId')::uuid;
      selected_role := upper(trim(coalesce(payload ->> 'role', '')));
      if selected_role not in ('PRIMARY_DELEGATE', 'ROSTER_MANAGER', 'VIEWER') then
        raise exception 'DELEGATE_ROLE_INVALID' using errcode = '22023';
      end if;
      if not exists (select 1 from auth.users users where users.id = selected_user_id) then
        raise exception 'DELEGATE_USER_NOT_FOUND' using errcode = 'P0002';
      end if;
      created_id := gen_random_uuid();
      insert into public.pachanga_competition_team_delegates(
        id, entry_id, user_id, delegate_role, status, valid_until,
        revision, server_sequence, invited_by
      ) values (
        created_id, entry_row.id, selected_user_id, selected_role, 'invited',
        nullif(payload ->> 'validUntil', '')::timestamptz,
        1, sequence_value, actor_id
      );
      target_user_id := selected_user_id;
      perform private.pachanga_notify_v1(
        selected_user_id, 'league_delegate_invitation', 'Invitación como delegado',
        'Un equipo te ha invitado a representarlo en una competición.',
        '/mis-competiciones/inscripciones', jsonb_build_object('delegateId', created_id),
        'league:' || operation_id::text || ':' || selected_user_id::text
      );
      event_payload := jsonb_build_object('delegateId', created_id, 'role', selected_role, 'status', 'invited');
    else
      created_secondary_id := (payload ->> 'targetDelegateId')::uuid;
      select * into delegate_row
      from public.pachanga_competition_team_delegates delegates
      where delegates.id = created_secondary_id and delegates.entry_id = entry_row.id
        and delegates.status = 'active' for update;
      if not found then raise exception 'TARGET_DELEGATE_NOT_ACTIVE' using errcode = '22023'; end if;
      select delegates.id into previous_delegate_id
      from public.pachanga_competition_team_delegates delegates
      where delegates.entry_id = entry_row.id
        and delegates.delegate_role = 'PRIMARY_DELEGATE'
        and delegates.status = 'active'
      for update;
      if previous_delegate_id is null then
        raise exception 'PRIMARY_DELEGATE_NOT_ACTIVE' using errcode = '22023';
      end if;
      if previous_delegate_id = delegate_row.id then
        raise exception 'TARGET_DELEGATE_ALREADY_PRIMARY' using errcode = '22023';
      end if;
      created_id := gen_random_uuid();
      update public.pachanga_competition_team_delegates delegates set
        status = 'replaced', valid_until = confirmed_at, revoked_by = actor_id,
        revoked_at = confirmed_at,
        revision = delegates.revision + 1, server_sequence = sequence_value
      where delegates.id = previous_delegate_id;
      insert into public.pachanga_competition_team_delegates(
        id, entry_id, user_id, delegate_role, status, valid_from,
        valid_until, revision, server_sequence, invited_by, accepted_at
      ) values (
        created_id, entry_row.id, delegate_row.user_id, 'PRIMARY_DELEGATE',
        'active', confirmed_at, delegate_row.valid_until, 1,
        sequence_value, actor_id, confirmed_at
      );
      update public.pachanga_competition_team_delegates delegates set
        replaced_by_delegate_id = created_id
      where delegates.id = previous_delegate_id;
      target_user_id := delegate_row.user_id;
      event_payload := jsonb_build_object(
        'delegateId', created_id, 'role', 'PRIMARY_DELEGATE', 'status', 'active'
      );
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_delegate_transferred', 'Delegado principal actualizado',
        'El equipo ha actualizado su representación principal.', operation_id
      );
    end if;
    update public.pachanga_competition_entries entries set
      revision = entries.revision + 1, server_sequence = sequence_value
    where entries.id = entry_row.id returning entries.revision into confirmed_revision;
    snapshot := private.pachanga_league_entry_snapshot_v1(entry_row.id, actor_id);
    aggregate_type := 'competition_entry';

  elsif normalized_action in ('delegate.accept', 'delegate.decline', 'delegate.revoke') then
    perform private.pachanga_league_assert_flags_v1(false, false, true, false, false);
    select * into delegate_row from public.pachanga_competition_team_delegates delegates
    where delegates.id = aggregate_id for update;
    if not found then raise exception 'DELEGATE_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = delegate_row.entry_id for update;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    target_user_id := delegate_row.user_id;
    if delegate_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if normalized_action in ('delegate.accept', 'delegate.decline') then
      if delegate_row.user_id <> actor_id then raise exception 'DELEGATE_INVITEE_REQUIRED' using errcode = '42501'; end if;
      if delegate_row.status <> 'invited' then raise exception 'DELEGATE_INVITATION_NOT_PENDING' using errcode = '22023'; end if;
      selected_status := case normalized_action when 'delegate.accept' then 'active' else 'declined' end;
      update public.pachanga_competition_team_delegates delegates set
        status = selected_status,
        valid_from = case when selected_status = 'active' then confirmed_at else delegates.valid_from end,
        accepted_at = case when selected_status = 'active' then confirmed_at else delegates.accepted_at end,
        revoked_at = case when selected_status = 'declined' then confirmed_at else delegates.revoked_at end,
        revision = delegates.revision + 1, server_sequence = sequence_value
      where delegates.id = delegate_row.id
      returning delegates.revision into confirmed_revision;
    else
      perform private.pachanga_league_assert_team_owner_v1(entry_row.team_id, actor_id);
      if delegate_row.status not in ('invited', 'active') then
        raise exception 'DELEGATE_TRANSITION_NOT_ALLOWED' using errcode = '22023';
      end if;
      selected_status := 'revoked';
      update public.pachanga_competition_team_delegates delegates set
        status = 'revoked', valid_until = confirmed_at, revoked_by = actor_id,
        revoked_at = confirmed_at, revision = delegates.revision + 1,
        server_sequence = sequence_value
      where delegates.id = delegate_row.id
      returning delegates.revision into confirmed_revision;
    end if;
    update public.pachanga_competition_entries entries set
      revision = entries.revision + 1, server_sequence = sequence_value
    where entries.id = entry_row.id;
    perform private.pachanga_league_notify_team_v1(
      entry_row.id,
      case selected_status when 'active' then 'league_delegate_accepted' else 'league_delegate_revoked' end,
      case selected_status when 'active' then 'Delegación aceptada' else 'Delegación actualizada' end,
      'La representación del equipo en la competición ha cambiado.', operation_id
    );
    snapshot := private.pachanga_league_entry_snapshot_v1(entry_row.id, actor_id);
    aggregate_type := 'competition_team_delegate';
    event_payload := jsonb_build_object('status', selected_status, 'role', delegate_row.delegate_role);

  elsif normalized_action = 'roster.create' then
    perform private.pachanga_league_assert_flags_v1(true, false, false, true, false);
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = aggregate_id for update;
    if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    if entry_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if entry_row.status <> 'accepted' then raise exception 'ENTRY_NOT_ACCEPTED' using errcode = '22023'; end if;
    perform private.pachanga_league_assert_roster_manager_v1(entry_row.id, actor_id);
    if exists (select 1 from public.pachanga_competition_rosters rosters where rosters.entry_id = entry_row.id) then
      raise exception 'ROSTER_ALREADY_EXISTS' using errcode = 'PT409';
    end if;
    created_id := private.pachanga_league_create_empty_roster_v1(
      entry_row.id, actor_id, sequence_value, command_reason
    );
    update public.pachanga_competition_entries entries set
      revision = entries.revision + 1, server_sequence = sequence_value
    where entries.id = entry_row.id returning entries.revision into confirmed_revision;
    snapshot := private.pachanga_league_roster_snapshot_v1(created_id, actor_id, 0, 50);
    aggregate_type := 'competition_entry';
    event_payload := jsonb_build_object('rosterId', created_id, 'status', 'draft');

  elsif normalized_action in ('roster.member.add', 'roster.member.remove', 'jersey.assign') then
    perform private.pachanga_league_assert_flags_v1(true, false, false, true, false);
    select * into roster_row from public.pachanga_competition_rosters rosters
    where rosters.id = aggregate_id for update;
    if not found then raise exception 'ROSTER_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = roster_row.entry_id for update;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    perform private.pachanga_league_assert_roster_manager_v1(entry_row.id, actor_id);
    if roster_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if roster_row.status not in ('draft', 'changes_requested', 'amended') then
      raise exception 'ROSTER_NOT_EDITABLE' using errcode = '22023';
    end if;
    selected_profile_id := (payload ->> 'playerProfileId')::uuid;
    if normalized_action = 'roster.member.add' then
      if exists (
        select 1 from public.pachanga_competition_roster_members members
        where members.roster_revision_id = roster_row.current_revision_id
          and members.player_profile_id = selected_profile_id
      ) then raise exception 'ROSTER_MEMBER_ALREADY_EXISTS' using errcode = 'PT409'; end if;
      select profiles.user_id into selected_user_id
      from public.pachanga_player_profiles profiles where profiles.id = selected_profile_id;
      if selected_user_id is null then raise exception 'PLAYER_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
      if not exists (
        select 1 from public.pachanga_group_members members
        where members.group_id = entry_row.team_id and members.user_id = selected_user_id
      ) then raise exception 'PLAYER_NOT_IN_TEAM' using errcode = '42501'; end if;
      perform pg_advisory_xact_lock(hashtextextended(
        'league-roster-player:' || entry_row.edition_id::text || ':'
          || entry_row.category_id::text || ':' || selected_profile_id::text,
        91406
      ));
      perform private.pachanga_league_assert_multi_team_v1(
        selected_profile_id, entry_row.id, roster_row.rule_revision_id
      );
      select credentials.id into selected_credential_id
      from public.pachanga_player_competition_credentials credentials
      where credentials.player_profile_id = selected_profile_id
        and credentials.edition_id = entry_row.edition_id
        and credentials.category_id = entry_row.category_id;
      if selected_credential_id is null then
        selected_credential_id := gen_random_uuid();
        insert into public.pachanga_player_competition_credentials(
          id, player_profile_id, competition_id, edition_id, category_id,
          status, verification_method, reason_code, rule_revision_id,
          revision, server_sequence
        ) values (
          selected_credential_id, selected_profile_id, competition_id,
          entry_row.edition_id, entry_row.category_id, 'unverified', 'NONE',
          'credential.unverified', roster_row.rule_revision_id, 1, sequence_value
        );
      end if;
      selected_eligibility := private.pachanga_league_member_eligibility_v1(
        selected_profile_id, entry_row.category_id,
        roster_row.rule_revision_id, selected_credential_id
      );
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, roster_row.status, actor_id, command_reason,
        sequence_value, null, null
      );
      insert into public.pachanga_competition_roster_members(
        roster_id, roster_revision_id, entry_id, player_profile_id,
        source_group_id, source_user_id, eligibility_status, credential_id,
        effective_from, public_snapshot, reason_code, server_sequence
      ) values (
        roster_row.id, new_revision_id, entry_row.id, selected_profile_id,
        entry_row.team_id, selected_user_id, selected_eligibility ->> 'status',
        selected_credential_id, confirmed_at,
        private.pachanga_league_public_player_snapshot_v1(
          selected_profile_id,
          (select categories.age_reference_date from public.pachanga_competition_categories categories
           where categories.id = entry_row.category_id)
        ),
        selected_eligibility ->> 'reasonCode', sequence_value
      );
      perform private.pachanga_league_finalize_roster_revision_v1(new_revision_id);
      selected_limits := private.pachanga_league_roster_limits_v1(roster_row.rule_revision_id);
      if (select revisions.member_count from public.pachanga_competition_roster_revisions revisions
          where revisions.id = new_revision_id) > (selected_limits ->> 'maximumSize')::integer then
        raise exception 'ROSTER_ABOVE_MAXIMUM' using errcode = '22023';
      end if;
    elsif normalized_action = 'roster.member.remove' then
      if not exists (
        select 1 from public.pachanga_competition_roster_members members
        where members.roster_revision_id = roster_row.current_revision_id
          and members.player_profile_id = selected_profile_id
      ) then raise exception 'ROSTER_MEMBER_NOT_FOUND' using errcode = 'P0002'; end if;
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, roster_row.status, actor_id, command_reason,
        sequence_value, null, null
      );
      delete from public.pachanga_competition_player_jersey_numbers jerseys
      where jerseys.roster_member_id in (
        select members.id from public.pachanga_competition_roster_members members
        where members.roster_revision_id = new_revision_id
          and members.player_profile_id = selected_profile_id
      );
      delete from public.pachanga_competition_roster_members members
      where members.roster_revision_id = new_revision_id
        and members.player_profile_id = selected_profile_id;
      perform private.pachanga_league_finalize_roster_revision_v1(new_revision_id);
    else
      selected_number := nullif(payload ->> 'number', '')::integer;
      selected_limits := private.pachanga_league_roster_limits_v1(roster_row.rule_revision_id);
      if selected_number < (selected_limits ->> 'jerseyMinimum')::integer
         or selected_number > (selected_limits ->> 'jerseyMaximum')::integer then
        raise exception 'JERSEY_NUMBER_OUT_OF_RANGE' using errcode = '22023';
      end if;
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, roster_row.status, actor_id, command_reason,
        sequence_value, null, null
      );
      select * into member_row
      from public.pachanga_competition_roster_members members
      where members.roster_revision_id = new_revision_id
        and members.player_profile_id = selected_profile_id;
      if not found then raise exception 'ROSTER_MEMBER_NOT_FOUND' using errcode = 'P0002'; end if;
      delete from public.pachanga_competition_player_jersey_numbers jerseys
      where jerseys.roster_member_id = member_row.id;
      insert into public.pachanga_competition_player_jersey_numbers(
        roster_member_id, roster_revision_id, number, valid_from,
        revision, server_sequence, assigned_by
      ) values (
        member_row.id, new_revision_id, selected_number, confirmed_at,
        1, sequence_value, actor_id
      );
      perform private.pachanga_league_finalize_roster_revision_v1(new_revision_id);
    end if;
    select * into roster_row from public.pachanga_competition_rosters rosters
    where rosters.id = aggregate_id;
    confirmed_revision := roster_row.revision;
    snapshot := private.pachanga_league_roster_snapshot_v1(roster_row.id, actor_id, 0, 100);
    aggregate_type := 'competition_roster';
    event_payload := jsonb_build_object(
      'rosterRevisionId', new_revision_id, 'playerProfileId', selected_profile_id,
      'memberCount', snapshot #>> '{currentRevision,memberCount}'
    );

  elsif normalized_action in (
    'roster.submit', 'roster.request_changes', 'roster.reopen',
    'roster.approve', 'roster.lock', 'roster.amend'
  ) then
    perform private.pachanga_league_assert_flags_v1(true, false, false, true, false);
    select * into roster_row from public.pachanga_competition_rosters rosters
    where rosters.id = aggregate_id for update;
    if not found then raise exception 'ROSTER_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = roster_row.entry_id for update;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    if roster_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if normalized_action in ('roster.submit', 'roster.reopen') then
      perform private.pachanga_league_assert_roster_manager_v1(entry_row.id, actor_id);
    else
      if not private.pachanga_competition_can_v1(competition_id, actor_id, 'rosters_review') then
        raise exception 'COMPETITION_ROSTER_REVIEWER_REQUIRED' using errcode = '42501';
      end if;
    end if;
    if normalized_action = 'roster.submit' then
      if roster_row.status not in ('draft', 'amended') then raise exception 'ROSTER_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      perform private.pachanga_league_validate_roster_v1(roster_row.id, 'submit');
      selected_status := 'submitted';
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, selected_status, actor_id, command_reason,
        sequence_value, actor_id, null
      );
      perform private.pachanga_league_notify_organizer_v1(
        competition_id, 'league_roster_submitted', 'Plantilla enviada',
        'Un equipo ha enviado su plantilla para revisión.', operation_id, entry_row.id
      );
    elsif normalized_action = 'roster.request_changes' then
      if roster_row.status <> 'submitted' then raise exception 'ROSTER_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      selected_status := 'changes_requested';
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, selected_status, actor_id, command_reason,
        sequence_value, null, actor_id
      );
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_roster_changes_requested', 'Cambios en la plantilla',
        'La organización ha solicitado cambios en la plantilla.', operation_id
      );
    elsif normalized_action = 'roster.reopen' then
      if roster_row.status <> 'changes_requested' then raise exception 'ROSTER_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      selected_status := 'draft';
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, selected_status, actor_id, command_reason,
        sequence_value, null, null
      );
    elsif normalized_action = 'roster.approve' then
      if roster_row.status <> 'submitted' then raise exception 'ROSTER_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      perform private.pachanga_league_validate_roster_v1(roster_row.id, 'approve');
      selected_status := 'approved';
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, selected_status, actor_id, command_reason,
        sequence_value, null, actor_id
      );
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_roster_approved', 'Plantilla aprobada',
        'La organización ha aprobado la plantilla.', operation_id
      );
    elsif normalized_action = 'roster.lock' then
      if roster_row.status <> 'approved' then raise exception 'ROSTER_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      selected_status := 'locked';
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, selected_status, actor_id, command_reason,
        sequence_value, null, actor_id
      );
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_roster_locked', 'Plantilla cerrada',
        'La plantilla de competición ha quedado cerrada.', operation_id
      );
    else
      if roster_row.status <> 'locked' then raise exception 'ROSTER_TRANSITION_NOT_ALLOWED' using errcode = '22023'; end if;
      selected_status := 'amended';
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, selected_status, actor_id, command_reason,
        sequence_value, null, actor_id
      );
      perform private.pachanga_league_notify_team_v1(
        entry_row.id, 'league_roster_amended', 'Enmienda de plantilla abierta',
        'La organización ha autorizado una enmienda con historial.', operation_id
      );
    end if;
    select rosters.revision into confirmed_revision
    from public.pachanga_competition_rosters rosters where rosters.id = roster_row.id;
    snapshot := private.pachanga_league_roster_snapshot_v1(roster_row.id, actor_id, 0, 100);
    aggregate_type := 'competition_roster';
    event_payload := jsonb_build_object('status', selected_status, 'rosterRevisionId', new_revision_id);

  elsif normalized_action in ('credential.review', 'eligibility.waive') then
    perform private.pachanga_league_assert_flags_v1(true, false, false, true, false);
    select * into credential_row
    from public.pachanga_player_competition_credentials credentials
    where credentials.id = aggregate_id for update;
    if not found then raise exception 'CREDENTIAL_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(credential_row.competition_id);
    competition_id := competition_row.id;
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'rosters_review') then
      raise exception 'COMPETITION_ROSTER_REVIEWER_REQUIRED' using errcode = '42501';
    end if;
    if credential_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    select members.* into member_row
    from public.pachanga_competition_roster_members members
    join public.pachanga_competition_rosters rosters
      on rosters.id = members.roster_id and rosters.current_revision_id = members.roster_revision_id
    where members.credential_id = credential_row.id
    order by members.server_sequence desc, members.id desc limit 1;
    if not found then raise exception 'CREDENTIAL_ROSTER_MEMBER_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into roster_row from public.pachanga_competition_rosters rosters
    where rosters.id = member_row.roster_id for update;
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = roster_row.entry_id for update;
    target_group_id := entry_row.team_id;
    if normalized_action = 'credential.review' then
      selected_status := lower(trim(coalesce(payload ->> 'status', '')));
      if selected_status not in ('pending', 'verified', 'expired', 'rejected', 'revoked') then
        raise exception 'CREDENTIAL_STATUS_INVALID' using errcode = '22023';
      end if;
      selected_type := left(coalesce(nullif(trim(payload ->> 'verificationMethod'), ''), 'MANUAL_REVIEW'), 80);
      update public.pachanga_player_competition_credentials credentials set
        status = selected_status, verification_method = selected_type,
        verified_by = case when selected_status = 'verified' then actor_id else credentials.verified_by end,
        verified_at = case when selected_status = 'verified' then confirmed_at else credentials.verified_at end,
        expires_at = nullif(payload ->> 'expiresAt', '')::timestamptz,
        reason_code = command_reason_code,
        revision = credentials.revision + 1,
        server_sequence = sequence_value
      where credentials.id = credential_row.id
      returning credentials.revision into confirmed_revision;
      selected_reference := nullif(trim(coalesce(payload ->> 'evidenceReference', '')), '');
      if selected_reference is not null then
        insert into private.pachanga_competition_credential_evidence(
          credential_id, evidence_reference, created_by
        ) values (
          credential_row.id, left(selected_reference, 500), actor_id
        ) on conflict (credential_id) do update set
          evidence_reference = excluded.evidence_reference,
          updated_at = clock_timestamp();
      end if;
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, roster_row.status, actor_id, command_reason,
        sequence_value, null, actor_id
      );
      selected_eligibility := private.pachanga_league_member_eligibility_v1(
        credential_row.player_profile_id, credential_row.category_id,
        credential_row.rule_revision_id, credential_row.id
      );
      if selected_status = 'rejected' then
        selected_eligibility := jsonb_build_object(
          'status', 'ineligible', 'reasonCode', command_reason_code
        );
      elsif selected_status in ('expired', 'revoked') then
        selected_eligibility := jsonb_build_object(
          'status', 'expired', 'reasonCode', command_reason_code
        );
      end if;
      update public.pachanga_competition_roster_members members set
        eligibility_status = selected_eligibility ->> 'status',
        reason_code = selected_eligibility ->> 'reasonCode'
      where members.roster_revision_id = new_revision_id
        and members.player_profile_id = credential_row.player_profile_id;
    else
      selected_valid_until := nullif(payload ->> 'validUntil', '')::timestamptz;
      update public.pachanga_player_competition_credentials credentials set
        revision = credentials.revision + 1, server_sequence = sequence_value
      where credentials.id = credential_row.id
      returning credentials.revision into confirmed_revision;
      new_revision_id := private.pachanga_league_clone_roster_revision_v1(
        roster_row.id, roster_row.status, actor_id, command_reason,
        sequence_value, null, actor_id
      );
      select * into member_row
      from public.pachanga_competition_roster_members members
      where members.roster_revision_id = new_revision_id
        and members.player_profile_id = credential_row.player_profile_id;
      insert into public.pachanga_competition_eligibility_waivers(
        roster_member_id, player_profile_id, rule_revision_id, status,
        valid_from, valid_until, reason, revision, server_sequence, granted_by
      ) values (
        member_row.id, credential_row.player_profile_id,
        credential_row.rule_revision_id, 'active', confirmed_at,
        selected_valid_until, command_reason, 1, sequence_value, actor_id
      );
      update public.pachanga_competition_roster_members members set
        eligibility_status = 'waived', reason_code = command_reason_code
      where members.id = member_row.id;
      selected_status := 'waived';
    end if;
    perform private.pachanga_league_finalize_roster_revision_v1(new_revision_id);
    snapshot := private.pachanga_league_roster_snapshot_v1(roster_row.id, actor_id, 0, 100);
    aggregate_type := 'player_competition_credential';
    event_payload := jsonb_build_object(
      'credentialStatus', selected_status,
      'rosterRevisionId', new_revision_id,
      'playerProfileId', credential_row.player_profile_id
    );

  elsif normalized_action = 'kit.set' then
    perform private.pachanga_league_assert_flags_v1(true, false, false, true, false);
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = aggregate_id for update;
    if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    perform private.pachanga_league_assert_roster_manager_v1(entry_row.id, actor_id);
    if entry_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    selected_type := upper(trim(coalesce(payload ->> 'kitType', '')));
    if selected_type not in ('HOME', 'AWAY', 'ALTERNATE') then raise exception 'KIT_TYPE_INVALID' using errcode = '22023'; end if;
    update public.pachanga_competition_team_kits kits set
      status = 'retired', valid_until = confirmed_at,
      revision = kits.revision + 1, server_sequence = sequence_value
    where kits.entry_id = entry_row.id and kits.kit_type = selected_type and kits.status = 'active';
    created_id := gen_random_uuid();
    insert into public.pachanga_competition_team_kits(
      id, entry_id, kit_type, primary_color, secondary_color, pattern,
      asset_reference, valid_from, status, revision, server_sequence, created_by
    ) values (
      created_id, entry_row.id, selected_type,
      upper(trim(coalesce(payload ->> 'primaryColor', ''))),
      upper(trim(coalesce(payload ->> 'secondaryColor', ''))),
      nullif(left(trim(coalesce(payload ->> 'pattern', '')), 80), ''),
      nullif(left(trim(coalesce(payload ->> 'assetReference', '')), 500), ''),
      confirmed_at, 'active', 1, sequence_value, actor_id
    );
    update public.pachanga_competition_entries entries set
      revision = entries.revision + 1, server_sequence = sequence_value
    where entries.id = entry_row.id returning entries.revision into confirmed_revision;
    snapshot := private.pachanga_league_entry_snapshot_v1(entry_row.id, actor_id);
    aggregate_type := 'competition_entry';
    event_payload := jsonb_build_object('kitId', created_id, 'kitType', selected_type);

  elsif normalized_action = 'stage_membership.assign' then
    perform private.pachanga_league_assert_flags_v1();
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = aggregate_id for update;
    if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'entries_manage') then
      raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if entry_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if entry_row.status <> 'accepted' then raise exception 'ENTRY_NOT_ACCEPTED' using errcode = '22023'; end if;
    selected_stage_id := (payload ->> 'stageId')::uuid;
    selected_division_id := nullif(payload ->> 'divisionId', '')::uuid;
    selected_group_id := nullif(payload ->> 'groupId', '')::uuid;
    select * into stage_row from public.pachanga_competition_stages stages
    where stages.id = selected_stage_id and stages.edition_id = entry_row.edition_id;
    if not found then raise exception 'STAGE_SCOPE_MISMATCH' using errcode = '22023'; end if;
    if selected_division_id is not null and not exists (
      select 1 from public.pachanga_competition_divisions divisions
      where divisions.id = selected_division_id and divisions.stage_id = selected_stage_id
    ) then raise exception 'DIVISION_SCOPE_MISMATCH' using errcode = '22023'; end if;
    if selected_group_id is not null and not exists (
      select 1 from public.pachanga_competition_groups groups
      where groups.id = selected_group_id and groups.stage_id = selected_stage_id
        and (selected_division_id is null or groups.division_id = selected_division_id)
    ) then raise exception 'GROUP_SCOPE_MISMATCH' using errcode = '22023'; end if;
    update public.pachanga_competition_stage_memberships memberships set
      status = 'closed', valid_until = confirmed_at,
      revision = memberships.revision + 1, server_sequence = sequence_value
    where memberships.entry_id = entry_row.id and memberships.status = 'active';
    created_id := gen_random_uuid();
    insert into public.pachanga_competition_stage_memberships(
      id, entry_id, stage_id, division_id, competition_group_id,
      rule_revision_id, valid_from, status, reason, revision,
      server_sequence, assigned_by
    ) values (
      created_id, entry_row.id, selected_stage_id, selected_division_id,
      selected_group_id, entry_row.rule_revision_id, confirmed_at,
      'active', command_reason, 1, sequence_value, actor_id
    );
    update public.pachanga_competition_entries entries set
      revision = entries.revision + 1, server_sequence = sequence_value
    where entries.id = entry_row.id returning entries.revision into confirmed_revision;
    snapshot := private.pachanga_league_entry_snapshot_v1(entry_row.id, actor_id);
    aggregate_type := 'competition_entry';
    event_payload := jsonb_build_object(
      'stageMembershipId', created_id, 'stageId', selected_stage_id,
      'divisionId', selected_division_id, 'groupId', selected_group_id
    );

  elsif normalized_action in ('availability.set', 'preference.set') then
    perform private.pachanga_league_assert_flags_v1(false, false, false, false, true);
    select * into entry_row from public.pachanga_competition_entries entries
    where entries.id = aggregate_id for update;
    if not found then raise exception 'ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
    competition_row := private.pachanga_league_assert_competition_v1(entry_row.competition_id);
    competition_id := competition_row.id;
    target_group_id := entry_row.team_id;
    perform private.pachanga_league_assert_roster_manager_v1(entry_row.id, actor_id);
    if entry_row.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    selected_weekday := nullif(payload ->> 'weekday', '')::integer;
    selected_start_time := (payload ->> 'startLocalTime')::time;
    selected_end_time := (payload ->> 'endLocalTime')::time;
    if selected_weekday not between 1 and 7 or selected_end_time <= selected_start_time then
      raise exception 'SCHEDULE_WINDOW_INVALID' using errcode = '22023';
    end if;
    created_id := gen_random_uuid();
    if normalized_action = 'availability.set' then
      insert into public.pachanga_team_availability_constraints(
        id, entry_id, weekday, start_local_time, end_local_time, timezone,
        valid_from_date, valid_until_date, reason, status, revision,
        server_sequence, created_by
      ) values (
        created_id, entry_row.id, selected_weekday, selected_start_time,
        selected_end_time, trim(coalesce(payload ->> 'timezone', '')),
        nullif(payload ->> 'validFromDate', '')::date,
        nullif(payload ->> 'validUntilDate', '')::date,
        command_reason, 'active', 1, sequence_value, actor_id
      );
      selected_type := 'hard_constraint';
    else
      selected_weight := nullif(payload ->> 'weight', '')::integer;
      insert into public.pachanga_team_schedule_preferences(
        id, entry_id, weekday, start_local_time, end_local_time, timezone,
        weight, preferred_area, venue_reference, status, revision,
        server_sequence, created_by
      ) values (
        created_id, entry_row.id, selected_weekday, selected_start_time,
        selected_end_time, trim(coalesce(payload ->> 'timezone', '')),
        selected_weight, nullif(left(trim(coalesce(payload ->> 'preferredArea', '')), 160), ''),
        nullif(left(trim(coalesce(payload ->> 'venueReference', '')), 500), ''),
        'active', 1, sequence_value, actor_id
      );
      selected_type := 'soft_preference';
    end if;
    update public.pachanga_competition_entries entries set
      revision = entries.revision + 1, server_sequence = sequence_value
    where entries.id = entry_row.id returning entries.revision into confirmed_revision;
    snapshot := private.pachanga_league_entry_snapshot_v1(entry_row.id, actor_id);
    aggregate_type := 'competition_entry';
    event_payload := jsonb_build_object(
      'scheduleRuleId', created_id, 'kind', selected_type,
      'weekday', selected_weekday
    );

  else
    raise exception 'LEAGUE_PARTICIPATION_ACTION_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  response := private.pachanga_league_store_command_v1(
    operation_id, actor_id, normalized_action, aggregate_type, aggregate_id,
    competition_id, target_group_id, target_user_id, confirmed_revision,
    sequence_value, command_reason_code, request_hash, metadata, event_payload,
    snapshot, confirmed_at
  );
  if normalized_action in ('registration.close', 'registration.close_and_expire_pending') then
    for entry_row in
      select distinct on (entries.team_id) entries.*
      from public.pachanga_competition_entries entries
      where entries.edition_id = edition_row.id
      order by entries.team_id, entries.server_sequence desc, entries.id desc
    loop
      insert into public.pachanga_competition_invalidations(
        server_sequence, competition_id, organizer_group_id, organizer_club_id,
        target_group_id, target_user_id, entity_type, entity_id, revision, created_at
      ) values (
        nextval('private.pachanga_competition_sequence'), competition_id,
        competition_row.organizer_group_id, competition_row.organizer_club_id,
        entry_row.team_id, null, 'competition_edition', edition_row.id::text,
        confirmed_revision, clock_timestamp()
      );
    end loop;
  end if;
  return response;
exception
  when unique_violation then
    raise exception 'LEAGUE_PARTICIPATION_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_participation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_participation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function private.pachanga_league_mark_departed_roster_members_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare affected record;
declare actor_id uuid := coalesce((select auth.uid()), old.user_id);
declare read_actor_id uuid;
declare operation_id uuid;
declare sequence_value bigint;
declare new_revision_id uuid;
declare confirmed_revision bigint;
declare selected_status text;
declare snapshot jsonb;
declare request_hash text;
begin
  for affected in
    select rosters.id as roster_id, rosters.revision, rosters.status,
      rosters.created_by, entries.id as entry_id, entries.competition_id,
      entries.team_id, groups.owner_id
    from public.pachanga_competition_rosters rosters
    join public.pachanga_competition_entries entries on entries.id = rosters.entry_id
    join public.pachanga_groups groups on groups.id = entries.team_id
    join public.pachanga_competition_roster_members members
      on members.roster_id = rosters.id
      and members.roster_revision_id = rosters.current_revision_id
    where entries.team_id = old.group_id
      and entries.status in ('accepted', 'active')
      and rosters.status in ('submitted', 'approved', 'locked')
      and members.source_user_id = old.user_id
    order by rosters.id
    for update of rosters
  loop
    operation_id := gen_random_uuid();
    sequence_value := nextval('private.pachanga_competition_sequence');
    read_actor_id := affected.owner_id;
    actor_id := coalesce((select auth.uid()), affected.owner_id, affected.created_by);
    selected_status := case when affected.status = 'submitted'
      then 'changes_requested' else 'amended' end;
    new_revision_id := private.pachanga_league_clone_roster_revision_v1(
      affected.roster_id,
      selected_status,
      actor_id,
      'Team membership ended; roster review required',
      sequence_value,
      null,
      null
    );
    update public.pachanga_competition_roster_members members set
      eligibility_status = 'review_required',
      reason_code = 'eligibility.team_membership_ended'
    where members.roster_revision_id = new_revision_id
      and members.source_user_id = old.user_id;
    perform private.pachanga_league_finalize_roster_revision_v1(new_revision_id);
    select rosters.revision into confirmed_revision
    from public.pachanga_competition_rosters rosters
    where rosters.id = affected.roster_id;
    snapshot := private.pachanga_league_roster_snapshot_v1(
      affected.roster_id, read_actor_id, 0, 100
    );
    request_hash := private.pachanga_competition_request_hash_v1(
      'roster.membership_departure.detected',
      affected.roster_id,
      affected.revision,
      jsonb_build_object('sourceGroupId', old.group_id, 'sourceUserId', old.user_id)
    );
    perform private.pachanga_league_store_command_v1(
      operation_id,
      actor_id,
      'roster.membership_departure.detected',
      'competition_roster',
      affected.roster_id,
      affected.competition_id,
      affected.team_id,
      old.user_id,
      confirmed_revision,
      sequence_value,
      'eligibility.team_membership_ended',
      request_hash,
      jsonb_build_object('surface', 'server_membership_transition'),
      jsonb_build_object(
        'entryId', affected.entry_id,
        'rosterRevisionId', new_revision_id,
        'status', selected_status
      ),
      snapshot,
      clock_timestamp()
    );
    perform private.pachanga_league_notify_team_v1(
      affected.entry_id,
      'league_roster_membership_review',
      'Plantilla pendiente de revisión',
      'Un jugador de la plantilla ya no pertenece al equipo.',
      operation_id
    );
    perform private.pachanga_league_notify_organizer_v1(
      affected.competition_id,
      'league_roster_membership_review',
      'Elegibilidad pendiente de revisión',
      'Una plantilla requiere revisión tras un cambio de membresía.',
      operation_id,
      affected.entry_id
    );
  end loop;
  return old;
end;
$$;

revoke all on function private.pachanga_league_mark_departed_roster_members_v1()
  from public, anon, authenticated;

drop trigger if exists mark_departed_competition_roster_members_v1
  on public.pachanga_group_members;
create trigger mark_departed_competition_roster_members_v1
after delete on public.pachanga_group_members
for each row execute function private.pachanga_league_mark_departed_roster_members_v1();
