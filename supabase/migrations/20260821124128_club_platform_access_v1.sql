-- Club Foundation R2 platform access. Product flags remain OFF.

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
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read', 'clubs.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'billing.read', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read'
    )
    else '[]'::jsonb
  end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text)
  from public, anon, authenticated;

comment on function private.pachanga_platform_capabilities_v1(text) is
  'Platform matrix preserving Ranking and Competition capabilities while adding Club R2 access.';

create or replace function private.pachanga_notification_policy_v1(target_kind text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select lower(coalesce(nullif(trim(target_kind), ''), 'general')) as kind
  )
  select jsonb_build_object(
    'category', case
      when kind like '%achievement%' or kind like '%reward%' then 'achievement'
      when kind like '%challenge%' or kind like '%external_result%' then 'challenge'
      when kind like '%invitation%' or kind like '%open_match_request%'
        or kind like '%withdrawal%' or kind like '%market%'
        or kind like 'club_team_%' then 'market'
      when kind like '%attendance%' or kind like '%availability%'
        or kind like 'match_%' then 'match'
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' then 'security'
      else 'group'
    end,
    'priority', case
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' or kind like '%challenge%'
        or kind like '%external_result%' or kind like '%invitation%'
        or kind like '%open_match_request%' or kind like '%withdrawal%'
        or kind in ('club_team_request', 'club_team_invitation') then 'critical'
      when kind like '%achievement%' or kind like '%reward%'
        or kind in ('group_member_removed', 'match_attendance_cancelled') then 'high'
      else 'normal'
    end,
    'mandatoryInApp', (
      kind like '%security%' or kind like '%sanction%' or kind like '%warning%'
      or kind like '%challenge%' or kind like '%external_result%'
      or kind like '%invitation%' or kind like '%open_match_request%'
      or kind like '%withdrawal%' or kind like '%achievement%' or kind like '%reward%'
      or kind in ('group_member_removed', 'club_team_request')
    )
  )
  from normalized;
$$;

revoke all on function private.pachanga_notification_policy_v1(text)
  from public, anon, authenticated;

alter table public.pachanga_club_invalidations alter column club_id drop not null;
alter table public.pachanga_club_invalidations
  add constraint pachanga_club_invalidations_target_check check (
    club_id is not null or entity_type = 'club_foundation_flags'
  );

create or replace function private.pachanga_club_can_read_invalidation_v2(
  target_club_id uuid,
  target_user_id uuid,
  target_group_id uuid,
  target_entity_type text,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select actor_id is not null and (
    (target_entity_type = 'club_foundation_flags' and target_club_id is null)
    or private.pachanga_club_platform_can_v1(actor_id, 'clubs.read')
    or private.pachanga_club_can_v1(target_club_id, actor_id, 'read')
    or target_user_id = actor_id
    or exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_group_id and groups.owner_id = actor_id
    )
  );
$$;

revoke all on function private.pachanga_club_can_read_invalidation_v2(uuid, uuid, uuid, text, uuid)
  from public, anon, authenticated;
grant execute on function private.pachanga_club_can_read_invalidation_v2(uuid, uuid, uuid, text, uuid)
  to authenticated;

drop policy if exists pachanga_club_invalidations_select_v1 on public.pachanga_club_invalidations;
create policy pachanga_club_invalidations_select_v2
on public.pachanga_club_invalidations
for select
to authenticated
using (private.pachanga_club_can_read_invalidation_v2(
  club_id, target_user_id, target_group_id, entity_type, (select auth.uid())
));

create or replace function public.command_pachanga_club_platform_v1(
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
  flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c101'::uuid;
  actor_id uuid := (select auth.uid());
  actor_kind text := 'authenticated';
  request_hash text;
  replay jsonb;
  sanitized_metadata jsonb;
  confirmed_at timestamptz := clock_timestamp();
  sequence_value bigint;
  competition_sequence_value bigint;
  confirmed_revision bigint;
  reason_code text;
  snapshot jsonb;
  response jsonb;
  selected_club public.pachanga_clubs%rowtype;
  settings private.pachanga_club_foundation_settings%rowtype;
  organizer_state public.pachanga_competition_organizer_states%rowtype;
  selected_grant public.pachanga_competition_entitlement_grants%rowtype;
  entitlement_id uuid;
  next_foundation boolean;
  next_creation boolean;
  next_relationships boolean;
  next_public_profiles boolean;
  next_competition_organizer boolean;
  next_status text;
  previous_value text;
  grant_source text;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or nullif(trim(command_action), '') is null then
    raise exception 'INVALID_CLUB_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_CLUB_PLATFORM_PAYLOAD' using errcode = '22023';
  end if;
  perform private.pachanga_platform_require_v1('clubs.manage');
  if command_action = 'club_flags.set' then
    perform private.pachanga_platform_require_v1('flags.write');
  end if;
  sanitized_metadata := private.pachanga_club_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_club_request_hash_v1(
    command_action, aggregate_id, expected_revision, coalesce(command_payload, '{}'::jsonb)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91404));
  replay := private.pachanga_club_replay_v1(
    operation_id, actor_id, actor_kind, command_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  sequence_value := nextval('private.pachanga_club_sequence');
  reason_code := left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), command_action), 120);

  if command_action = 'club_flags.set' then
    if aggregate_id <> flags_aggregate_id then
      raise exception 'INVALID_CLUB_FLAGS_AGGREGATE' using errcode = '22023';
    end if;
    select * into settings
    from private.pachanga_club_foundation_settings current_settings
    where current_settings.singleton
    for update;
    if settings.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if (command_payload ? 'foundationEnabled' and jsonb_typeof(command_payload -> 'foundationEnabled') <> 'boolean')
       or (command_payload ? 'selfServiceCreationEnabled' and jsonb_typeof(command_payload -> 'selfServiceCreationEnabled') <> 'boolean')
       or (command_payload ? 'teamRelationshipsEnabled' and jsonb_typeof(command_payload -> 'teamRelationshipsEnabled') <> 'boolean')
       or (command_payload ? 'publicProfilesEnabled' and jsonb_typeof(command_payload -> 'publicProfilesEnabled') <> 'boolean')
       or (command_payload ? 'competitionOrganizerEnabled' and jsonb_typeof(command_payload -> 'competitionOrganizerEnabled') <> 'boolean') then
      raise exception 'INVALID_CLUB_FLAG' using errcode = '22023';
    end if;
    next_foundation := coalesce((command_payload ->> 'foundationEnabled')::boolean, settings.club_foundation_enabled);
    next_creation := coalesce((command_payload ->> 'selfServiceCreationEnabled')::boolean, settings.club_self_service_creation_enabled);
    next_relationships := coalesce((command_payload ->> 'teamRelationshipsEnabled')::boolean, settings.club_team_relationships_enabled);
    next_public_profiles := coalesce((command_payload ->> 'publicProfilesEnabled')::boolean, settings.club_public_profiles_enabled);
    next_competition_organizer := coalesce((command_payload ->> 'competitionOrganizerEnabled')::boolean, settings.club_competition_organizer_enabled);
    if not next_foundation then
      next_creation := false;
      next_relationships := false;
      next_public_profiles := false;
      next_competition_organizer := false;
    end if;
    update private.pachanga_club_foundation_settings current_settings set
      club_foundation_enabled = next_foundation,
      club_self_service_creation_enabled = next_creation,
      club_team_relationships_enabled = next_relationships,
      club_public_profiles_enabled = next_public_profiles,
      club_competition_organizer_enabled = next_competition_organizer,
      revision = current_settings.revision + 1,
      server_sequence = sequence_value,
      updated_by = actor_id,
      updated_at = confirmed_at
    where current_settings.singleton
    returning current_settings.revision into confirmed_revision;
    snapshot := private.pachanga_club_flags_snapshot_v1();
    response := jsonb_build_object(
      'operationId', operation_id,
      'confirmedRevision', confirmed_revision,
      'confirmedAt', confirmed_at,
      'serverSequence', sequence_value,
      'snapshot', snapshot,
      'invalidations', jsonb_build_array(jsonb_build_object(
        'entityType', 'club_foundation_flags',
        'entityId', aggregate_id,
        'revision', confirmed_revision
      ))
    );
    insert into private.pachanga_club_events(
      operation_id, actor_id, actor_kind, aggregate_type, aggregate_id, club_id,
      action, aggregate_revision, server_sequence, reason_code, event_payload, confirmed_at
    ) values (
      operation_id, actor_id, actor_kind, 'club_foundation_flags', aggregate_id::text, null,
      command_action, confirmed_revision, sequence_value, reason_code, snapshot, confirmed_at
    );
    insert into public.pachanga_club_invalidations(
      server_sequence, club_id, entity_type, entity_id, revision, created_at
    ) values (
      sequence_value, null, 'club_foundation_flags', aggregate_id::text, confirmed_revision, confirmed_at
    );
    insert into private.pachanga_club_operation_receipts(
      operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
      request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
    ) values (
      operation_id, actor_id, actor_kind, command_action, 'club_foundation_flags', aggregate_id::text,
      request_hash, confirmed_revision, sequence_value, sanitized_metadata, response, confirmed_at
    );
    return response;
  end if;

  select * into selected_club
  from public.pachanga_clubs clubs
  where clubs.id = aggregate_id
  for update;
  if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected_club.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;

  if command_action = 'club.status.set' then
    next_status := lower(trim(coalesce(command_payload ->> 'status', '')));
    if next_status not in ('draft', 'pending_review', 'active', 'suspended', 'rejected', 'archived') then
      raise exception 'INVALID_CLUB_STATUS' using errcode = '22023';
    end if;
    previous_value := selected_club.operational_status;
    update public.pachanga_clubs clubs set
      operational_status = next_status,
      revision = clubs.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where clubs.id = aggregate_id
    returning * into selected_club;
  elsif command_action = 'club.verification.set' then
    next_status := lower(trim(coalesce(command_payload ->> 'status', '')));
    if next_status not in ('unverified', 'pending', 'verified', 'rejected', 'revoked') then
      raise exception 'INVALID_CLUB_VERIFICATION_STATUS' using errcode = '22023';
    end if;
    previous_value := selected_club.verification_status;
    update public.pachanga_clubs clubs set
      verification_status = next_status,
      revision = clubs.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where clubs.id = aggregate_id
    returning * into selected_club;
  elsif command_action = 'club.partnership.set' then
    next_status := lower(trim(coalesce(command_payload ->> 'status', '')));
    if next_status not in ('none', 'candidate', 'active', 'paused', 'ended') then
      raise exception 'INVALID_CLUB_PARTNERSHIP_STATUS' using errcode = '22023';
    end if;
    previous_value := selected_club.partnership_status;
    update public.pachanga_clubs clubs set
      partnership_status = next_status,
      revision = clubs.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where clubs.id = aggregate_id
    returning * into selected_club;
  elsif command_action in ('club.entitlement.grant', 'club.entitlement.revoke') then
    competition_sequence_value := nextval('private.pachanga_competition_sequence');
    select * into organizer_state
    from public.pachanga_competition_organizer_states states
    where states.organizer_kind = 'CLUB' and states.organizer_club_id = aggregate_id
    for update;
    if not found then
      insert into public.pachanga_competition_organizer_states(
        organizer_kind, organizer_group_id, organizer_club_id, revision,
        server_sequence, created_at, updated_at
      ) values (
        'CLUB', null, aggregate_id, 1, competition_sequence_value, confirmed_at, confirmed_at
      ) returning * into organizer_state;
    end if;
    if command_action = 'club.entitlement.grant' then
      if trim(coalesce(command_payload ->> 'capability', '')) <> 'competition_create' then
        raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
      end if;
      if length(trim(coalesce(command_payload ->> 'reason', ''))) < 3 then
        raise exception 'ENTITLEMENT_REASON_REQUIRED' using errcode = '22023';
      end if;
      grant_source := lower(trim(coalesce(command_payload ->> 'source', 'platform_grant')));
      if grant_source not in ('platform_grant', 'partnership') then
        raise exception 'INVALID_ENTITLEMENT_SOURCE' using errcode = '22023';
      end if;
      if grant_source = 'partnership' and selected_club.partnership_status <> 'active' then
        raise exception 'ACTIVE_PARTNERSHIP_REQUIRED' using errcode = '42501';
      end if;
      update public.pachanga_competition_entitlement_grants grants set
        status = 'revoked',
        revision = grants.revision + 1,
        revoked_by = actor_id,
        revoked_at = confirmed_at,
        server_sequence = competition_sequence_value,
        updated_at = confirmed_at
      where grants.organizer_kind = 'CLUB'
        and grants.organizer_club_id = aggregate_id
        and grants.capability = 'competition_create'
        and grants.status = 'active';
      entitlement_id := gen_random_uuid();
      insert into public.pachanga_competition_entitlement_grants(
        id, organizer_kind, organizer_group_id, organizer_club_id, capability,
        grant_source, status, valid_from, expires_at, reason, revision,
        server_sequence, granted_by, created_at, updated_at
      ) values (
        entitlement_id, 'CLUB', null, aggregate_id, 'competition_create',
        grant_source, 'active',
        coalesce(nullif(command_payload ->> 'validFrom', '')::timestamptz, confirmed_at),
        nullif(command_payload ->> 'expiresAt', '')::timestamptz,
        trim(command_payload ->> 'reason'), 1,
        competition_sequence_value, actor_id, confirmed_at, confirmed_at
      );
      next_status := 'active';
    else
      entitlement_id := nullif(command_payload ->> 'entitlementId', '')::uuid;
      select * into selected_grant
      from public.pachanga_competition_entitlement_grants grants
      where grants.id = entitlement_id
        and grants.organizer_kind = 'CLUB'
        and grants.organizer_club_id = aggregate_id
      for update;
      if not found then raise exception 'ENTITLEMENT_NOT_FOUND' using errcode = 'P0002'; end if;
      if selected_grant.status <> 'active' then
        raise exception 'ENTITLEMENT_NOT_ACTIVE' using errcode = 'PT409';
      end if;
      update public.pachanga_competition_entitlement_grants grants set
        status = 'revoked',
        revision = grants.revision + 1,
        revoked_by = actor_id,
        revoked_at = confirmed_at,
        server_sequence = competition_sequence_value,
        updated_at = confirmed_at
      where grants.id = entitlement_id;
      next_status := 'revoked';
    end if;
    update public.pachanga_competition_organizer_states states set
      revision = states.revision + 1,
      server_sequence = competition_sequence_value,
      updated_at = confirmed_at
    where states.id = organizer_state.id;
    previous_value := command_payload ->> 'capability';
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where clubs.id = aggregate_id
    returning * into selected_club;
  else
    raise exception 'UNSUPPORTED_CLUB_PLATFORM_ACTION' using errcode = '0A000';
  end if;

  confirmed_revision := selected_club.revision;
  snapshot := private.pachanga_club_snapshot_v1(aggregate_id, actor_id);
  return private.pachanga_club_store_command_v1(
    operation_id, actor_id, actor_kind, command_action,
    case when command_action like 'club.entitlement.%' then 'club_competition_entitlement' else 'club' end,
    aggregate_id, aggregate_id, confirmed_revision, sequence_value, reason_code,
    request_hash, sanitized_metadata,
    jsonb_strip_nulls(jsonb_build_object(
      'previousValue', previous_value,
      'nextValue', next_status,
      'entitlementId', entitlement_id,
      'partnershipDoesNotGrantEntitlement', command_action = 'club.partnership.set'
    )),
    snapshot, null, null, confirmed_at
  );
exception
  when unique_violation then raise exception 'CLUB_PLATFORM_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_club_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_club_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function public.get_pachanga_platform_clubs_v1(
  page_offset integer default 0,
  page_size integer default 50
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
  bounded_size integer := least(greatest(coalesce(page_size, 50), 1), 200);
begin
  perform private.pachanga_platform_require_v1('clubs.read');
  return jsonb_build_object(
    'flags', private.pachanga_club_flags_snapshot_v1(),
    'metrics', jsonb_build_object(
      'clubs', (select count(*) from public.pachanga_clubs),
      'active', (select count(*) from public.pachanga_clubs where operational_status = 'active'),
      'pendingReview', (select count(*) from public.pachanga_clubs where operational_status = 'pending_review'),
      'verified', (select count(*) from public.pachanga_clubs where verification_status = 'verified'),
      'partners', (select count(*) from public.pachanga_clubs where partnership_status = 'active'),
      'activeStaff', (select count(*) from public.pachanga_club_memberships where status = 'active'),
      'pendingInvitations', (select count(*) from public.pachanga_club_invitations where status = 'pending'),
      'activeTeamRelationships', (select count(*) from public.pachanga_club_team_relationships where status = 'active'),
      'clubCompetitions', (select count(*) from public.pachanga_competitions where organizer_kind = 'CLUB')
    ),
    'total', (select count(*) from public.pachanga_clubs),
    'items', coalesce((
      with selected as (
        select clubs.*,
          coalesce(nullif(trim(profiles.display_name), ''), 'Usuario ' || left(clubs.primary_owner_id::text, 8)) as owner_name,
          (select count(*) from public.pachanga_club_memberships memberships
            where memberships.club_id = clubs.id and memberships.status = 'active') as staff_count,
          (select count(*) from public.pachanga_club_invitations invitations
            where invitations.club_id = clubs.id and invitations.status = 'pending') as invitation_count,
          (select count(*) from public.pachanga_club_team_relationships relationships
            where relationships.club_id = clubs.id and relationships.status = 'active') as team_count,
          (select count(*) from public.pachanga_competitions competitions
            where competitions.organizer_kind = 'CLUB' and competitions.organizer_club_id = clubs.id) as competition_count,
          coalesce((select states.revision from public.pachanga_competition_organizer_states states
            where states.organizer_kind = 'CLUB' and states.organizer_club_id = clubs.id), 0) as organizer_revision,
          private.pachanga_competition_active_entitlement_v2('CLUB', clubs.id, 'competition_create') as can_create_competition
        from public.pachanga_clubs clubs
        left join public.pachanga_player_profiles profiles on profiles.user_id = clubs.primary_owner_id
        order by clubs.updated_at desc, clubs.id
        offset bounded_offset limit bounded_size
      )
      select jsonb_agg(jsonb_build_object(
        'id', selected.id,
        'name', selected.name,
        'slug', selected.slug,
        'clubType', selected.club_type,
        'countryCode', selected.country_code,
        'province', selected.province,
        'municipality', selected.municipality,
        'generalArea', selected.general_area,
        'visibility', selected.visibility,
        'operationalStatus', selected.operational_status,
        'verificationStatus', selected.verification_status,
        'partnershipStatus', selected.partnership_status,
        'primaryOwnerId', selected.primary_owner_id,
        'primaryOwnerName', selected.owner_name,
        'staffCount', selected.staff_count,
        'pendingInvitationCount', selected.invitation_count,
        'linkedTeamCount', selected.team_count,
        'competitionCount', selected.competition_count,
        'organizerRevision', selected.organizer_revision,
        'canCreateCompetition', selected.can_create_competition,
        'revision', selected.revision,
        'serverSequence', selected.server_sequence,
        'createdAt', selected.created_at,
        'updatedAt', selected.updated_at
      ) order by selected.updated_at desc, selected.id)
      from selected
    ), '[]'::jsonb),
    'recentEvents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', events.id,
        'operationId', events.operation_id,
        'clubId', events.club_id,
        'action', events.action,
        'aggregateType', events.aggregate_type,
        'aggregateId', events.aggregate_id,
        'revision', events.aggregate_revision,
        'serverSequence', events.server_sequence,
        'reasonCode', events.reason_code,
        'confirmedAt', events.confirmed_at
      ) order by events.server_sequence desc, events.id desc)
      from (
        select * from private.pachanga_club_events
        order by server_sequence desc, id desc limit 100
      ) events
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_clubs_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_clubs_v1(integer, integer)
  to authenticated;

create or replace function public.get_pachanga_platform_club_v1(target_club_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare snapshot jsonb;
begin
  perform private.pachanga_platform_require_v1('clubs.read');
  snapshot := private.pachanga_club_snapshot_v1(target_club_id, actor_id);
  if snapshot is null then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
  return snapshot || jsonb_build_object(
    'recentEvents', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', events.id,
        'operationId', events.operation_id,
        'action', events.action,
        'aggregateType', events.aggregate_type,
        'revision', events.aggregate_revision,
        'serverSequence', events.server_sequence,
        'reasonCode', events.reason_code,
        'confirmedAt', events.confirmed_at
      ) order by events.server_sequence desc, events.id desc)
      from (
        select * from private.pachanga_club_events rows
        where rows.club_id = target_club_id
        order by rows.server_sequence desc, rows.id desc limit 100
      ) events
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_club_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_club_v1(uuid)
  to authenticated;

create or replace function public.get_pachanga_platform_competition_foundation_v2(
  page_offset integer default 0,
  page_size integer default 50
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
  bounded_size integer := least(greatest(coalesce(page_size, 50), 1), 200);
  settings private.pachanga_competition_foundation_settings%rowtype;
  authority_time timestamptz := clock_timestamp();
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  select * into settings
  from private.pachanga_competition_foundation_settings
  where singleton;

  return jsonb_build_object(
    'flags', jsonb_build_object(
      'foundationEnabled', settings.foundation_enabled,
      'creationEnabled', settings.creation_enabled,
      'contextBindingEnabled', settings.context_binding_enabled,
      'revision', settings.revision,
      'serverSequence', settings.server_sequence,
      'updatedAt', settings.updated_at
    ),
    'metrics', jsonb_build_object(
      'competitions', (select count(*) from public.pachanga_competitions),
      'drafts', (select count(*) from public.pachanga_competitions where status = 'draft'),
      'editions', (select count(*) from public.pachanga_competition_editions),
      'ruleRevisions', (select count(*) from public.pachanga_competition_rule_revisions),
      'activeEntitlements', (
        select count(*)
        from public.pachanga_competition_entitlement_grants grants
        where grants.status = 'active'
          and grants.valid_from <= authority_time
          and (grants.expires_at is null or grants.expires_at > authority_time)
      ),
      'staffAssignments', (
        select count(*) from public.pachanga_competition_staff_assignments where status = 'active'
      ),
      'events', (select count(*) from private.pachanga_competition_events),
      'receipts', (select count(*) from private.pachanga_competition_operation_receipts)
    ),
    'bindingHealth', private.pachanga_canonical_match_health_v1(),
    'total', (select count(*) from public.pachanga_competitions),
    'items', coalesce((
      with edition_counts as (
        select editions.competition_id, count(*) as amount
        from public.pachanga_competition_editions editions
        group by editions.competition_id
      ), rule_counts as (
        select rule_sets.competition_id, count(revisions.id) as amount,
          max(revisions.version) as latest_version
        from public.pachanga_competition_rule_sets rule_sets
        left join public.pachanga_competition_rule_revisions revisions
          on revisions.rule_set_id = rule_sets.id
        group by rule_sets.competition_id
      ), staff_counts as (
        select assignments.competition_id, count(*) as amount
        from public.pachanga_competition_staff_assignments assignments
        where assignments.status = 'active'
        group by assignments.competition_id
      ), context_counts as (
        select contexts.competition_id, count(*) as amount
        from public.pachanga_competition_match_contexts contexts
        where contexts.status = 'lab_bound'
        group by contexts.competition_id
      ), selected as (
        select competitions.*,
          coalesce(groups.name, clubs.name) as organizer_name,
          coalesce(edition_counts.amount, 0) as edition_count,
          coalesce(rule_counts.amount, 0) as rule_revision_count,
          rule_counts.latest_version,
          coalesce(staff_counts.amount, 0) as staff_count,
          coalesce(context_counts.amount, 0) as context_count
        from public.pachanga_competitions competitions
        left join public.pachanga_groups groups
          on competitions.organizer_kind = 'TEAM'
         and groups.id = competitions.organizer_group_id
        left join public.pachanga_clubs clubs
          on competitions.organizer_kind = 'CLUB'
         and clubs.id = competitions.organizer_club_id
        left join edition_counts on edition_counts.competition_id = competitions.id
        left join rule_counts on rule_counts.competition_id = competitions.id
        left join staff_counts on staff_counts.competition_id = competitions.id
        left join context_counts on context_counts.competition_id = competitions.id
        order by competitions.updated_at desc, competitions.id
        offset bounded_offset limit bounded_size
      )
      select jsonb_agg(jsonb_build_object(
        'id', selected.id,
        'name', selected.name,
        'slug', selected.slug,
        'type', selected.competition_type,
        'status', selected.status,
        'visibility', selected.visibility,
        'organizerKind', selected.organizer_kind,
        'organizerGroupId', selected.organizer_group_id,
        'organizerClubId', selected.organizer_club_id,
        'organizerName', selected.organizer_name,
        'revision', selected.revision,
        'serverSequence', selected.server_sequence,
        'editionCount', selected.edition_count,
        'ruleRevisionCount', selected.rule_revision_count,
        'latestRuleVersion', selected.latest_version,
        'staffCount', selected.staff_count,
        'contextCount', selected.context_count,
        'updatedAt', selected.updated_at
      ) order by selected.updated_at desc, selected.id)
      from selected
    ), '[]'::jsonb),
    'entitlements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', grants.id,
        'organizerKind', grants.organizer_kind,
        'organizerGroupId', grants.organizer_group_id,
        'organizerClubId', grants.organizer_club_id,
        'organizerName', coalesce(groups.name, clubs.name),
        'capability', grants.capability,
        'source', grants.grant_source,
        'status', case
          when grants.status = 'revoked' then 'revoked'
          when grants.expires_at is not null and grants.expires_at <= authority_time then 'expired'
          when grants.valid_from > authority_time then 'scheduled'
          else 'active'
        end,
        'organizerRevision', states.revision,
        'revision', grants.revision,
        'validFrom', grants.valid_from,
        'expiresAt', grants.expires_at,
        'updatedAt', grants.updated_at
      ) order by grants.server_sequence desc, grants.id desc)
      from public.pachanga_competition_entitlement_grants grants
      left join public.pachanga_groups groups
        on grants.organizer_kind = 'TEAM'
       and groups.id = grants.organizer_group_id
      left join public.pachanga_clubs clubs
        on grants.organizer_kind = 'CLUB'
       and clubs.id = grants.organizer_club_id
      join public.pachanga_competition_organizer_states states
        on states.organizer_kind = grants.organizer_kind
       and (
         (grants.organizer_kind = 'TEAM' and states.organizer_group_id = grants.organizer_group_id)
         or (grants.organizer_kind = 'CLUB' and states.organizer_club_id = grants.organizer_club_id)
       )
    ), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', reviews.id,
        'leftSourceKind', reviews.left_source_kind,
        'leftSourceGroupId', reviews.left_source_group_id,
        'leftSourceId', reviews.left_source_id,
        'rightSourceKind', reviews.right_source_kind,
        'rightSourceGroupId', reviews.right_source_group_id,
        'rightSourceId', reviews.right_source_id,
        'reasonCode', reviews.reason_code,
        'status', reviews.review_status,
        'revision', reviews.revision,
        'serverSequence', reviews.server_sequence,
        'createdAt', reviews.created_at
      ) order by reviews.server_sequence desc, reviews.id desc)
      from (
        select * from public.pachanga_canonical_match_binding_reviews
        order by server_sequence desc, id desc limit 100
      ) reviews
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
        order by server_sequence desc, id desc limit 100
      ) events
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_competition_foundation_v2(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_competition_foundation_v2(integer, integer)
  to authenticated, service_role;

comment on function public.get_pachanga_platform_competition_foundation_v2(integer, integer) is
  'R2 platform read model for TEAM and CLUB organizers. V1 remains unchanged for legacy TEAM clients.';

create or replace function public.search_pachanga_platform_v1(
  search_text text,
  result_limit integer default 20
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  needle text := '%' || lower(trim(coalesce(search_text, ''))) || '%';
  safe_limit integer := least(greatest(coalesce(result_limit, 20), 1), 50);
  actor_role text;
  can_read_billing boolean;
  can_read_pii boolean;
  can_read_clubs boolean;
begin
  actor_role := private.pachanga_platform_require_v1('search.read');
  can_read_billing := actor_role in ('platform_owner', 'platform_admin', 'finance');
  can_read_pii := actor_role in ('platform_owner', 'platform_admin', 'support', 'finance');
  can_read_clubs := private.pachanga_platform_capabilities_v1(actor_role) ? 'clubs.read';
  if char_length(trim(coalesce(search_text, ''))) < 2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(limited.item order by limited.priority, limited.label, limited.id)
    from (
      select results.*
      from (
        select 1 as priority, users.id::text as id, jsonb_build_object(
          'type', 'user', 'id', users.id,
          'label', coalesce(
            nullif(trim(profiles.display_name), ''),
            nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
            nullif(trim(users.raw_user_meta_data ->> 'name'), ''),
            case when can_read_pii then users.email else null end,
            'Usuario ' || left(users.id::text, 8)
          ),
          'secondary', case when can_read_pii then users.email else null end,
          'href', '/admin/users/' || users.id::text
        ) as item, coalesce(
          nullif(trim(profiles.display_name), ''),
          nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
          nullif(trim(users.raw_user_meta_data ->> 'name'), ''),
          case when can_read_pii then users.email else null end,
          users.id::text
        ) as label
        from auth.users users
        left join public.pachanga_player_profiles profiles on profiles.user_id = users.id
        where (can_read_pii and lower(coalesce(users.email, '')) like needle)
           or lower(coalesce(profiles.display_name, '')) like needle
           or lower(coalesce(users.raw_user_meta_data ->> 'full_name', '')) like needle
           or lower(coalesce(users.raw_user_meta_data ->> 'name', '')) like needle
           or users.id::text like needle
        union all
        select 2, groups.id::text, jsonb_build_object(
          'type', 'team', 'id', groups.id, 'label', groups.name,
          'secondary', groups.team_code, 'href', '/admin/teams/' || groups.id::text
        ), coalesce(groups.name, groups.team_code, groups.id::text)
        from public.pachanga_groups groups
        where lower(coalesce(groups.name, '')) like needle
           or lower(coalesce(groups.team_code, '')) like needle
           or (can_read_billing and lower(coalesce(groups.stripe_customer_id, '')) like needle)
           or (can_read_billing and lower(coalesce(groups.stripe_subscription_id, '')) like needle)
        union all
        select 3, clubs.id::text, jsonb_build_object(
          'type', 'club', 'id', clubs.id, 'label', clubs.name,
          'secondary', concat_ws(' · ', nullif(clubs.municipality, ''), clubs.operational_status),
          'href', '/admin/clubs?club=' || clubs.id::text
        ), clubs.name
        from public.pachanga_clubs clubs
        where can_read_clubs and (
          lower(clubs.name) like needle
          or lower(clubs.slug) like needle
          or lower(clubs.municipality) like needle
          or exists (
            select 1 from public.pachanga_player_profiles owner_profiles
            where owner_profiles.user_id = clubs.primary_owner_id
              and lower(coalesce(owner_profiles.display_name, '')) like needle
          )
          or exists (
            select 1
            from public.pachanga_club_team_relationships relationships
            join public.pachanga_groups linked_groups on linked_groups.id = relationships.group_id
            where relationships.club_id = clubs.id
              and lower(coalesce(linked_groups.name, '')) like needle
          )
        )
        union all
        select 4, matches.group_id::text || ':' || matches.match_id, jsonb_build_object(
          'type', 'match', 'id', matches.match_id, 'label', 'Partido ' || matches.match_id,
          'secondary', groups.name, 'href', '/admin/matches/' || matches.group_id::text || '/' || matches.match_id
        ), matches.match_id
        from public.pachanga_match_read_model matches
        join public.pachanga_groups groups on groups.id = matches.group_id
        where lower(matches.match_id) like needle
        union all
        select 5, challenges.id::text, jsonb_build_object(
          'type', 'challenge', 'id', challenges.id, 'label', 'Reto ' || left(challenges.id::text, 8),
          'secondary', sender.name || ' vs ' || receiver.name,
          'href', '/admin/challenges/' || challenges.id::text
        ), challenges.id::text
        from public.pachanga_team_challenges challenges
        join public.pachanga_groups sender on sender.id = challenges.sender_group_id
        join public.pachanga_groups receiver on receiver.id = challenges.receiver_group_id
        where challenges.id::text like needle
           or lower(sender.name) like needle or lower(receiver.name) like needle
        union all
        select 6, cases.opaque_reference::text, jsonb_build_object(
          'type', 'moderation', 'id', cases.opaque_reference,
          'label', 'Caso ' || left(cases.opaque_reference::text, 8),
          'secondary', cases.category, 'href', '/admin/conduct?case=' || cases.opaque_reference::text
        ), cases.opaque_reference::text
        from private.pachanga_moderation_cases cases
        where cases.opaque_reference::text like needle
      ) results
      order by results.priority, results.label, results.id
      limit safe_limit
    ) limited
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.search_pachanga_platform_v1(text, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.search_pachanga_platform_v1(text, integer)
  to authenticated;

comment on function public.command_pachanga_club_platform_v1(uuid, uuid, bigint, text, jsonb, jsonb) is
  'Audited platform-only Club controls. Partnership never grants Competition entitlement implicitly.';
comment on function public.get_pachanga_platform_clubs_v1(integer, integer) is
  'Bounded Club Control Center read model without invitation contacts or private location detail.';
