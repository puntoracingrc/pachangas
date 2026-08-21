-- Referee Platform R3 administrative access and the forward-only activation of
-- the Club referee manager role. All product flags remain OFF.

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
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read', 'clubs.read', 'referees.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'billing.read', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read', 'referees.health.read'
    )
    else '[]'::jsonb
  end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text)
  from public, anon, authenticated;

comment on function private.pachanga_platform_capabilities_v1(text) is
  'Platform matrix preserving Ranking, Competition and Club capabilities while adding Referee R3 access.';

alter table public.pachanga_club_invitations
  drop constraint if exists pachanga_club_invitations_role_check;
alter table public.pachanga_club_invitations
  add constraint pachanga_club_invitations_role_check check (
    role in ('club_owner', 'club_admin', 'club_competition_manager', 'club_referee_manager', 'club_viewer')
  );

create index if not exists pachanga_referee_receipts_rate_limit_idx
  on private.pachanga_referee_operation_receipts(actor_id, action, created_at desc)
  where actor_id is not null;

create or replace function private.pachanga_referee_rate_limit_v1(
  target_actor_id uuid,
  target_action text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  hourly_limit integer := case when target_action = 'profile.create' then 5 else 120 end;
  daily_limit integer := case when target_action = 'profile.create' then 5 else 1000 end;
begin
  if target_actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if (
    select count(*) from private.pachanga_referee_operation_receipts receipts
    where receipts.actor_id = target_actor_id and receipts.action = target_action
      and receipts.created_at >= clock_timestamp() - interval '1 hour'
  ) >= hourly_limit then
    raise exception 'REFEREE_RATE_LIMITED' using errcode = 'PT429';
  end if;
  if (
    select count(*) from private.pachanga_referee_operation_receipts receipts
    where receipts.actor_id = target_actor_id and receipts.action = target_action
      and receipts.created_at >= clock_timestamp() - interval '24 hours'
  ) >= daily_limit then
    raise exception 'REFEREE_RATE_LIMITED' using errcode = 'PT429';
  end if;
end;
$$;

revoke all on function private.pachanga_referee_rate_limit_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_referee_platform_can_health_v1(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    private.pachanga_platform_capabilities_v1(
      private.pachanga_platform_role_for_user_v1(target_user_id)
    ) ? 'referees.health.read', false
  );
$$;

revoke all on function private.pachanga_referee_platform_can_health_v1(uuid)
  from public, anon, authenticated;

create or replace function public.command_pachanga_referee_platform_admin_v1(
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
  flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000a3f3'::uuid;
  actor_id uuid := (select auth.uid());
  request_hash text;
  replay jsonb;
  reason_code text;
  aggregate_type text;
  confirmed_revision bigint;
  profile public.pachanga_referee_profiles%rowtype;
  assignment public.pachanga_referee_assignments%rowtype;
  stats public.pachanga_referee_statistics_snapshots%rowtype;
  settings private.pachanga_referee_foundation_settings%rowtype;
  snapshot jsonb;
  event_payload jsonb;
  response jsonb;
  target_status text;
  target_verification text;
  invalidation_user_id uuid;
  affected_profile_id uuid;
  affected_club_id uuid;
  affected_match_id uuid;
  next_foundation boolean;
  next_self_service boolean;
  next_public_profiles boolean;
  next_marketplace boolean;
  next_relationships boolean;
  next_assignments boolean;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or nullif(trim(command_action), '') is null then
    raise exception 'INVALID_REFEREE_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or pg_column_size(command_payload) > 32768 then
    raise exception 'INVALID_REFEREE_PLATFORM_PAYLOAD' using errcode = '22023';
  end if;
  perform private.pachanga_platform_require_v1('referees.manage');
  if command_action = 'referee_flags.set' then
    perform private.pachanga_platform_require_v1('flags.write');
  end if;
  reason_code := left(trim(coalesce(command_payload ->> 'reason', '')), 120);
  if length(reason_code) < 3 then raise exception 'REFEREE_ADMIN_REASON_REQUIRED' using errcode = '22023'; end if;
  request_hash := private.pachanga_referee_request_hash_v1(
    command_action, aggregate_id, expected_revision, command_payload
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;

  if command_action = 'referee_flags.set' then
    if aggregate_id <> flags_aggregate_id then raise exception 'INVALID_REFEREE_FLAGS_AGGREGATE' using errcode = '22023'; end if;
    select * into settings from private.pachanga_referee_foundation_settings current_settings
    where current_settings.singleton for update;
    if settings.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if (command_payload ? 'foundationEnabled' and jsonb_typeof(command_payload -> 'foundationEnabled') <> 'boolean')
       or (command_payload ? 'selfServiceEnabled' and jsonb_typeof(command_payload -> 'selfServiceEnabled') <> 'boolean')
       or (command_payload ? 'publicProfilesEnabled' and jsonb_typeof(command_payload -> 'publicProfilesEnabled') <> 'boolean')
       or (command_payload ? 'marketplaceEnabled' and jsonb_typeof(command_payload -> 'marketplaceEnabled') <> 'boolean')
       or (command_payload ? 'clubRelationshipsEnabled' and jsonb_typeof(command_payload -> 'clubRelationshipsEnabled') <> 'boolean')
       or (command_payload ? 'assignmentsEnabled' and jsonb_typeof(command_payload -> 'assignmentsEnabled') <> 'boolean') then
      raise exception 'INVALID_REFEREE_FLAG' using errcode = '22023';
    end if;
    next_foundation := coalesce((command_payload ->> 'foundationEnabled')::boolean, settings.referee_foundation_enabled);
    next_self_service := coalesce((command_payload ->> 'selfServiceEnabled')::boolean, settings.referee_self_service_enabled);
    next_public_profiles := coalesce((command_payload ->> 'publicProfilesEnabled')::boolean, settings.referee_public_profiles_enabled);
    next_marketplace := coalesce((command_payload ->> 'marketplaceEnabled')::boolean, settings.referee_marketplace_enabled);
    next_relationships := coalesce((command_payload ->> 'clubRelationshipsEnabled')::boolean, settings.referee_club_relationships_enabled);
    next_assignments := coalesce((command_payload ->> 'assignmentsEnabled')::boolean, settings.referee_assignments_enabled);
    if not next_foundation then
      next_self_service := false;
      next_public_profiles := false;
      next_marketplace := false;
      next_relationships := false;
      next_assignments := false;
    elsif not next_public_profiles then
      next_marketplace := false;
    end if;
    update private.pachanga_referee_foundation_settings current_settings set
      referee_foundation_enabled = next_foundation,
      referee_self_service_enabled = next_self_service,
      referee_public_profiles_enabled = next_public_profiles,
      referee_marketplace_enabled = next_marketplace,
      referee_club_relationships_enabled = next_relationships,
      referee_assignments_enabled = next_assignments,
      revision = current_settings.revision + 1,
      server_sequence = nextval('private.pachanga_referee_sequence'),
      updated_by = actor_id,
      updated_at = clock_timestamp()
    where current_settings.singleton returning * into settings;
    aggregate_type := 'referee_foundation_flags';
    confirmed_revision := settings.revision;
    snapshot := private.pachanga_referee_flags_snapshot_v1();
    event_payload := snapshot - 'updatedAt';

  elsif command_action in (
    'profile.activate', 'profile.suspend', 'profile.restore',
    'verification.pending', 'verification.approve', 'verification.reject', 'verification.revoke'
  ) then
    select * into profile from public.pachanga_referee_profiles profiles
    where profiles.id = aggregate_id for update;
    if not found then raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
    if profile.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    aggregate_type := 'referee_profile';
    affected_profile_id := profile.id;
    invalidation_user_id := profile.user_id;
    if command_action = 'profile.activate' then
      if profile.operational_status <> 'draft' then raise exception 'REFEREE_PROFILE_ACTIVATION_NOT_ALLOWED' using errcode = 'PT409'; end if;
      if not exists (select 1 from public.pachanga_referee_modalities m where m.referee_profile_id = profile.id and m.active)
         or not exists (select 1 from public.pachanga_referee_service_areas a where a.referee_profile_id = profile.id and a.status = 'active') then
        raise exception 'REFEREE_PROFILE_INCOMPLETE' using errcode = '22023';
      end if;
      target_status := 'active';
      update public.pachanga_referee_profiles profiles set
        operational_status = target_status, revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
    elsif command_action = 'profile.suspend' then
      if profile.operational_status <> 'active' then raise exception 'REFEREE_PROFILE_SUSPEND_NOT_ALLOWED' using errcode = 'PT409'; end if;
      target_status := 'suspended';
      update public.pachanga_referee_profiles profiles set
        operational_status = target_status, marketplace_status = 'not_listed',
        available_for_assignments = false, revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
    elsif command_action = 'profile.restore' then
      if profile.operational_status <> 'suspended' then raise exception 'REFEREE_PROFILE_RESTORE_NOT_ALLOWED' using errcode = 'PT409'; end if;
      target_status := 'active';
      update public.pachanga_referee_profiles profiles set
        operational_status = target_status, revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
    else
      target_verification := case command_action
        when 'verification.pending' then 'pending'
        when 'verification.approve' then 'verified'
        when 'verification.reject' then 'rejected'
        else 'revoked'
      end;
      update public.pachanga_referee_profiles profiles set
        verification_status = target_verification,
        revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
    end if;
    confirmed_revision := profile.revision;
    snapshot := private.pachanga_referee_private_snapshot_v1(profile.id, profile.user_id);
    event_payload := jsonb_build_object(
      'operationalStatus', profile.operational_status,
      'verificationStatus', profile.verification_status,
      'marketplaceStatus', profile.marketplace_status
    );
    perform private.pachanga_referee_notify_v1(
      profile.user_id, 'referee_profile_admin_changed', 'Estado de la ficha de árbitro actualizado',
      'Pachangas IQ ha actualizado el estado administrativo de tu ficha de árbitro.',
      '/perfil/arbitro', jsonb_build_object('profileId', profile.id),
      'referee-profile-admin:' || operation_id::text || ':' || profile.user_id::text
    );

  elsif command_action = 'stats.rebuild' then
    select * into profile from public.pachanga_referee_profiles profiles where profiles.id = aggregate_id;
    if not found then raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into stats from public.pachanga_referee_statistics_snapshots snapshots
    where snapshots.referee_profile_id = profile.id for update;
    if coalesce(stats.revision, 0) <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    stats := private.pachanga_referee_refresh_statistics_v1(profile.id, 'full_rebuild');
    aggregate_type := 'referee_statistics';
    affected_profile_id := profile.id;
    invalidation_user_id := profile.user_id;
    confirmed_revision := stats.revision;
    snapshot := jsonb_build_object('statistics', to_jsonb(stats) - 'referee_profile_id');
    event_payload := jsonb_build_object('mode', 'full_rebuild', 'checksum', stats.checksum);

  elsif command_action = 'assignment.completion.void' then
    select * into assignment from public.pachanga_referee_assignments assignments
    where assignments.id = aggregate_id for update;
    if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
    if assignment.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if assignment.status <> 'completed' then raise exception 'REFEREE_ASSIGNMENT_NOT_COMPLETED' using errcode = 'PT409'; end if;
    update public.pachanga_referee_assignments assignments set
      status = 'cancelled', cancelled_at = clock_timestamp(), cancelled_by = actor_id,
      cancel_reason_code = 'completion_voided', cancel_reason_text = left(reason_code, 800),
      completed_at = null, revision = assignments.revision + 1,
      server_sequence = nextval('private.pachanga_referee_sequence')
    where assignments.id = assignment.id returning * into assignment;
    select * into profile from public.pachanga_referee_profiles profiles where profiles.id = assignment.referee_profile_id;
    stats := private.pachanga_referee_refresh_statistics_v1(profile.id, 'full_rebuild');
    aggregate_type := 'referee_assignment';
    affected_profile_id := profile.id;
    affected_club_id := assignment.requester_club_id;
    affected_match_id := assignment.canonical_match_id;
    invalidation_user_id := profile.user_id;
    confirmed_revision := assignment.revision;
    snapshot := jsonb_build_object(
      'assignment', jsonb_build_object(
        'id', assignment.id, 'status', assignment.status,
        'revision', assignment.revision, 'serverSequence', assignment.server_sequence
      ),
      'statistics', to_jsonb(stats) - 'referee_profile_id'
    );
    event_payload := jsonb_build_object('status', 'cancelled', 'correction', 'completion_voided');
  else
    raise exception 'REFEREE_PLATFORM_ACTION_NOT_SUPPORTED' using errcode = '0A000';
  end if;

  response := private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', command_action, aggregate_type,
    aggregate_id::text, request_hash, confirmed_revision, reason_code,
    event_payload, snapshot, affected_profile_id, affected_club_id,
    affected_match_id, invalidation_user_id, null, 'private', client_metadata
  );
  return response;
end;
$$;

revoke all on function public.command_pachanga_referee_platform_admin_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_referee_platform_admin_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function public.command_pachanga_club_referee_manager_v1(
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
  actor_id uuid := (select auth.uid());
  actor_role text;
  request_hash text;
  replay jsonb;
  selected_club public.pachanga_clubs%rowtype;
  selected_invitation public.pachanga_club_invitations%rowtype;
  selected_membership public.pachanga_club_memberships%rowtype;
  invitation_id uuid;
  target_kind text;
  target_user_id uuid;
  target_email text;
  expires_at timestamptz;
  one_time_token text;
  club_sequence bigint;
  snapshot jsonb;
  response jsonb;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or command_action <> 'manager.invite' then
    raise exception 'INVALID_REFEREE_MANAGER_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or pg_column_size(command_payload) > 16384 then
    raise exception 'INVALID_REFEREE_MANAGER_PAYLOAD' using errcode = '22023';
  end if;
  perform private.pachanga_club_assert_flags_v1(false, false);
  perform private.pachanga_referee_assert_flags_v1(false, false, false, true, false);
  actor_role := private.pachanga_club_active_role_v1(aggregate_id, actor_id);
  if actor_role not in ('club_owner', 'club_admin')
     and not private.pachanga_referee_platform_can_v1(actor_id, 'referees.manage') then
    raise exception 'CLUB_STAFF_CAPABILITY_REQUIRED' using errcode = '42501';
  end if;
  request_hash := private.pachanga_referee_request_hash_v1(
    command_action, aggregate_id, expected_revision, command_payload
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  perform private.pachanga_referee_rate_limit_v1(actor_id, command_action);
  select * into selected_club from public.pachanga_clubs clubs
  where clubs.id = aggregate_id for update;
  if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected_club.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  if selected_club.operational_status in ('suspended', 'rejected', 'archived') then
    raise exception 'CLUB_INVITATIONS_BLOCKED' using errcode = '42501';
  end if;
  invitation_id := nullif(command_payload ->> 'invitationId', '')::uuid;
  if invitation_id is null or exists (
    select 1 from public.pachanga_club_invitations invitations where invitations.id = invitation_id
  ) then raise exception 'INVALID_CLUB_INVITATION_ID' using errcode = '22023'; end if;
  target_kind := trim(coalesce(command_payload ->> 'targetKind', ''));
  expires_at := coalesce(
    nullif(command_payload ->> 'expiresAt', '')::timestamptz,
    clock_timestamp() + interval '7 days'
  );
  if expires_at <= clock_timestamp() or expires_at > clock_timestamp() + interval '30 days' then
    raise exception 'INVALID_INVITATION_EXPIRY' using errcode = '22023';
  end if;
  one_time_token := encode(extensions.gen_random_bytes(32), 'hex');
  club_sequence := nextval('private.pachanga_club_sequence');
  if target_kind = 'registered_user' then
    target_user_id := nullif(command_payload ->> 'targetUserId', '')::uuid;
    if target_user_id is null or not exists (select 1 from auth.users users where users.id = target_user_id) then
      raise exception 'INVITATION_TARGET_NOT_FOUND' using errcode = 'P0002';
    end if;
    if exists (
      select 1 from public.pachanga_club_memberships memberships
      where memberships.club_id = selected_club.id and memberships.user_id = target_user_id
        and memberships.status in ('invited', 'active')
    ) then raise exception 'CLUB_MEMBERSHIP_ALREADY_CURRENT' using errcode = 'PT409'; end if;
    insert into public.pachanga_club_memberships(
      club_id, user_id, role, status, valid_from, expires_at, server_sequence,
      invited_by, created_at, updated_at
    ) values (
      selected_club.id, target_user_id, 'club_referee_manager', 'invited',
      clock_timestamp(), expires_at, club_sequence, actor_id, clock_timestamp(), clock_timestamp()
    ) returning * into selected_membership;
  elsif target_kind = 'email_target' then
    target_email := lower(trim(coalesce(command_payload ->> 'targetEmail', '')));
    if target_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$'
       or length(target_email) > 320 then
      raise exception 'INVALID_INVITATION_EMAIL' using errcode = '22023';
    end if;
  else
    raise exception 'INVALID_INVITATION_TARGET_KIND' using errcode = '22023';
  end if;
  insert into public.pachanga_club_invitations(
    id, club_id, membership_id, target_kind, target_user_id, role, status,
    expires_at, revision, server_sequence, invited_by, created_at, updated_at
  ) values (
    invitation_id, selected_club.id, selected_membership.id, target_kind, target_user_id,
    'club_referee_manager', 'pending', expires_at, 1, club_sequence,
    actor_id, clock_timestamp(), clock_timestamp()
  ) returning * into selected_invitation;
  insert into private.pachanga_club_invitation_secrets(
    invitation_id, token_hash, target_email_normalized, target_email_hash,
    retention_until, created_at
  ) values (
    selected_invitation.id,
    encode(extensions.digest(one_time_token, 'sha256'), 'hex'),
    target_email,
    case when target_email is null then null else encode(extensions.digest(target_email, 'sha256'), 'hex') end,
    expires_at + interval '90 days', clock_timestamp()
  );
  update public.pachanga_clubs clubs set
    revision = clubs.revision + 1, server_sequence = club_sequence, updated_at = clock_timestamp()
  where clubs.id = selected_club.id returning * into selected_club;
  if target_user_id is not null then
    perform private.pachanga_club_notify_v1(
      target_user_id, 'club_referee_manager_invitation', 'Invitación para gestionar árbitros',
      selected_club.name || ' te ha invitado a gestionar sus relaciones y asignaciones arbitrales.',
      '/perfil/arbitro?clubInvitation=' || selected_invitation.id::text,
      jsonb_build_object('clubId', selected_club.id, 'invitationId', selected_invitation.id),
      'club-referee-manager-invite:' || operation_id::text || ':' || target_user_id::text
    );
  end if;
  snapshot := jsonb_build_object(
    'invitation', jsonb_build_object(
      'id', selected_invitation.id, 'clubId', selected_invitation.club_id,
      'targetKind', selected_invitation.target_kind, 'role', selected_invitation.role,
      'status', selected_invitation.status, 'expiresAt', selected_invitation.expires_at,
      'revision', selected_invitation.revision, 'serverSequence', selected_invitation.server_sequence
    ),
    'clubRevision', selected_club.revision
  );
  response := private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', command_action, 'club_referee_manager_invitation',
    selected_invitation.id::text, request_hash, selected_invitation.revision,
    left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), command_action), 120),
    jsonb_build_object(
      'clubId', selected_club.id, 'invitationId', selected_invitation.id,
      'targetKind', target_kind, 'role', 'club_referee_manager', 'status', 'pending'
    ),
    snapshot, null, selected_club.id, null, target_user_id, null, 'private', client_metadata
  );
  return response || jsonb_build_object('oneTimeToken', one_time_token);
end;
$$;

revoke all on function public.command_pachanga_club_referee_manager_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_club_referee_manager_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function public.get_pachanga_platform_referees_v1(
  target_filters jsonb default '{}'::jsonb,
  target_page integer default 1,
  target_page_size integer default 50
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  safe_page integer := greatest(coalesce(target_page, 1), 1);
  safe_page_size integer := least(greatest(coalesce(target_page_size, 50), 1), 100);
  filters jsonb := coalesce(target_filters, '{}'::jsonb);
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('referees.read');
  if jsonb_typeof(filters) <> 'object' then raise exception 'INVALID_REFEREE_FILTERS' using errcode = '22023'; end if;
  with eligible as (
    select profiles.id
    from public.pachanga_referee_profiles profiles
    where (nullif(filters ->> 'status', '') is null or profiles.operational_status = filters ->> 'status')
      and (nullif(filters ->> 'verification', '') is null or profiles.verification_status = filters ->> 'verification')
      and (nullif(filters ->> 'marketplace', '') is null or profiles.marketplace_status = filters ->> 'marketplace')
      and (nullif(filters ->> 'modality', '') is null or exists (
        select 1 from public.pachanga_referee_modalities modalities
        where modalities.referee_profile_id = profiles.id and modalities.active
          and modalities.modality = filters ->> 'modality'
      ))
      and (nullif(filters ->> 'area', '') is null or exists (
        select 1 from public.pachanga_referee_service_areas areas
        where areas.referee_profile_id = profiles.id and areas.status = 'active'
          and concat_ws(' ', areas.province, areas.municipality, areas.general_area)
              ilike '%' || left(filters ->> 'area', 120) || '%'
      ))
      and (nullif(filters ->> 'query', '') is null
        or profiles.public_display_name_snapshot ilike '%' || left(filters ->> 'query', 120) || '%'
        or profiles.slug ilike '%' || lower(left(filters ->> 'query', 120)) || '%')
  ), paged as (
    select profiles.*
    from public.pachanga_referee_profiles profiles
    join eligible on eligible.id = profiles.id
    order by profiles.updated_at desc, profiles.server_sequence desc, profiles.id desc
    limit safe_page_size offset (safe_page - 1) * safe_page_size
  )
  select jsonb_build_object(
    'flags', private.pachanga_referee_flags_snapshot_v1(),
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', paged.id,
      'slug', paged.slug,
      'displayName', paged.public_display_name_snapshot,
      'avatar', paged.public_avatar_snapshot,
      'operationalStatus', paged.operational_status,
      'verificationStatus', paged.verification_status,
      'visibility', paged.visibility,
      'marketplaceStatus', paged.marketplace_status,
      'availabilityStatus', paged.availability_status,
      'availableForAssignments', paged.available_for_assignments,
      'modalities', coalesce((
        select jsonb_agg(m.modality order by m.modality)
        from public.pachanga_referee_modalities m where m.referee_profile_id = paged.id and m.active
      ), '[]'::jsonb),
      'areas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'province', a.province, 'municipality', a.municipality, 'generalArea', a.general_area
        ) order by a.country_code, a.province, a.municipality, a.general_area, a.id)
        from public.pachanga_referee_service_areas a where a.referee_profile_id = paged.id and a.status = 'active'
      ), '[]'::jsonb),
      'activeClubs', (select count(*) from public.pachanga_club_referee_relationships r
                      where r.referee_profile_id = paged.id and r.status = 'active'),
      'activeAssignments', (select count(*) from public.pachanga_referee_assignments a
                            where a.referee_profile_id = paged.id and a.status in ('proposed', 'accepted', 'confirmed')),
      'matchesCompleted', coalesce(stats.matches_completed, 0),
      'revision', paged.revision,
      'serverSequence', paged.server_sequence,
      'updatedAt', paged.updated_at
    ) order by paged.updated_at desc, paged.server_sequence desc, paged.id desc), '[]'::jsonb),
    'page', safe_page,
    'pageSize', safe_page_size,
    'total', (select count(*) from eligible)
  ) into result
  from paged
  left join public.pachanga_referee_statistics_snapshots stats on stats.referee_profile_id = paged.id;
  return result;
end;
$$;

create or replace function public.get_pachanga_platform_referee_v1(target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  can_manage boolean;
  profile public.pachanga_referee_profiles%rowtype;
begin
  perform private.pachanga_platform_require_v1('referees.read');
  can_manage := private.pachanga_referee_platform_can_v1(actor_id, 'referees.manage');
  select * into profile from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id;
  if not found then raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'profile', jsonb_build_object(
      'id', profile.id, 'slug', profile.slug,
      'displayName', profile.public_display_name_snapshot, 'avatar', profile.public_avatar_snapshot,
      'bio', profile.bio, 'experienceSinceYear', profile.experience_since_year,
      'experienceSummary', profile.experience_summary,
      'operationalStatus', profile.operational_status,
      'verificationStatus', profile.verification_status,
      'visibility', profile.visibility, 'marketplaceStatus', profile.marketplace_status,
      'availabilityStatus', profile.availability_status,
      'availableForAssignments', profile.available_for_assignments,
      'revision', profile.revision, 'serverSequence', profile.server_sequence,
      'createdAt', profile.created_at, 'updatedAt', profile.updated_at
    ),
    'modalities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'modality', m.modality, 'active', m.active,
        'experienceSinceYear', m.experience_since_year, 'note', m.public_note,
        'revision', m.revision
      ) order by m.modality, m.id)
      from public.pachanga_referee_modalities m where m.referee_profile_id = profile.id
    ), '[]'::jsonb),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'countryCode', a.country_code, 'province', a.province,
        'municipality', a.municipality, 'generalArea', a.general_area,
        'travelRadiusKm', a.travel_radius_km, 'status', a.status, 'revision', a.revision
      ) order by a.status, a.country_code, a.province, a.municipality, a.id)
      from public.pachanga_referee_service_areas a where a.referee_profile_id = profile.id
    ), '[]'::jsonb),
    'availability', jsonb_build_object(
      'windows', coalesce((
        select jsonb_agg(jsonb_build_object(
          'weekday', w.weekday, 'startLocalTime', w.start_local_time,
          'endLocalTime', w.end_local_time, 'timezone', w.timezone,
          'publicVisible', w.public_visible, 'status', w.status, 'revision', w.revision
        ) order by w.status, w.weekday, w.start_local_time, w.id)
        from public.pachanga_referee_availability_windows w where w.referee_profile_id = profile.id
      ), '[]'::jsonb),
      'exceptions', case when can_manage then coalesce((
        select jsonb_agg(jsonb_build_object(
          'unavailableFrom', e.unavailable_from, 'unavailableUntil', e.unavailable_until,
          'reason', e.private_reason, 'status', e.status, 'revision', e.revision
        ) order by e.unavailable_from, e.id)
        from public.pachanga_referee_availability_exceptions e where e.referee_profile_id = profile.id
      ), '[]'::jsonb) else '[]'::jsonb end
    ),
    'relationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'clubId', r.club_id, 'clubName', c.name,
        'relationshipType', r.relationship_type, 'initiatedBy', r.initiated_by,
        'status', r.status, 'showOnRefereeProfile', r.show_on_referee_profile,
        'showOnClubProfile', r.show_on_club_profile, 'startedAt', r.started_at,
        'endedAt', r.ended_at, 'revision', r.revision, 'serverSequence', r.server_sequence
      ) order by r.server_sequence desc, r.id desc)
      from (
        select relationships.*
        from public.pachanga_club_referee_relationships relationships
        where relationships.referee_profile_id = profile.id
        order by relationships.server_sequence desc, relationships.id desc
        limit 200
      ) r
      join public.pachanga_clubs c on c.id = r.club_id
    ), '[]'::jsonb),
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'canonicalMatchId', a.canonical_match_id,
        'assignmentRole', a.assignment_role, 'requesterKind', a.requester_kind,
        'requesterTeamId', a.requester_team_id, 'requesterClubId', a.requester_club_id,
        'competitionId', a.competition_id, 'sourceKind', a.source_kind, 'sourceId', a.source_id,
        'status', a.status, 'scheduledStart', a.scheduled_start, 'scheduledEnd', a.scheduled_end,
        'timezone', a.timezone, 'scheduleSourceRevision', a.schedule_source_revision,
        'responseDeadline', a.response_deadline, 'acceptedAt', a.accepted_at,
        'confirmedAt', a.confirmed_at, 'cancelledAt', a.cancelled_at,
        'completedAt', a.completed_at, 'revision', a.revision,
        'serverSequence', a.server_sequence
      ) order by a.scheduled_start desc, a.server_sequence desc, a.id desc)
      from (
        select assignments.*
        from public.pachanga_referee_assignments assignments
        where assignments.referee_profile_id = profile.id
        order by assignments.scheduled_start desc, assignments.server_sequence desc, assignments.id desc
        limit 200
      ) a
    ), '[]'::jsonb),
    'statistics', coalesce((
      select to_jsonb(s) - 'referee_profile_id'
      from public.pachanga_referee_statistics_snapshots s where s.referee_profile_id = profile.id
    ), jsonb_build_object(
      'proposals_received', 0, 'assignments_accepted', 0, 'assignments_declined', 0,
      'assignments_confirmed', 0, 'matches_completed', 0,
      'individual_matches_completed', 0, 'competition_matches_completed', 0,
      'active_club_relationships', 0, 'discipline_stats_status', 'NOT_AVAILABLE',
      'yellow_cards_shown', null, 'red_cards_shown', null, 'blue_cards_shown', null
    )),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', events.id, 'action', events.action,
        'aggregateType', events.aggregate_type, 'aggregateId', events.aggregate_id,
        'aggregateRevision', events.aggregate_revision,
        'serverSequence', events.server_sequence,
        'reasonCode', case when can_manage then events.reason_code else null end,
        'confirmedAt', events.confirmed_at
      ) order by events.server_sequence desc, events.id desc)
      from (
        select referee_events.*
        from private.pachanga_referee_events referee_events
        where referee_events.profile_id = profile.id
        order by referee_events.server_sequence desc, referee_events.id desc
        limit 200
      ) events
    ), '[]'::jsonb),
    'capabilities', jsonb_build_object('read', true, 'manage', can_manage)
  );
end;
$$;

create or replace function public.search_pachanga_platform_referees_v1(
  target_query text,
  target_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  safe_query text := left(trim(coalesce(target_query, '')), 120);
  safe_limit integer := least(greatest(coalesce(target_limit, 20), 1), 50);
begin
  perform private.pachanga_platform_require_v1('referees.read');
  if length(safe_query) < 2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(results.item order by results.rank desc, results.display_name, results.profile_id)
    from (
      select distinct on (profiles.id)
        profiles.id as profile_id,
        profiles.public_display_name_snapshot as display_name,
        case
          when lower(profiles.slug) = lower(safe_query) then 100
          when lower(profiles.public_display_name_snapshot) = lower(safe_query) then 90
          when profiles.public_display_name_snapshot ilike safe_query || '%' then 70
          else 40
        end as rank,
        jsonb_build_object(
          'kind', 'referee', 'id', profiles.id, 'label', profiles.public_display_name_snapshot,
          'subtitle', concat_ws(' · ', nullif(profiles.slug, ''), nullif(areas.general_area, ''), nullif(modalities.modality, '')),
          'href', '/admin/referees?profile=' || profiles.id::text,
          'status', profiles.operational_status,
          'verificationStatus', profiles.verification_status
        ) as item
      from public.pachanga_referee_profiles profiles
      left join public.pachanga_referee_service_areas areas
        on areas.referee_profile_id = profiles.id and areas.status = 'active'
      left join public.pachanga_referee_modalities modalities
        on modalities.referee_profile_id = profiles.id and modalities.active
      left join public.pachanga_club_referee_relationships relationships
        on relationships.referee_profile_id = profiles.id and relationships.status = 'active'
      left join public.pachanga_clubs clubs on clubs.id = relationships.club_id
      where profiles.public_display_name_snapshot ilike '%' || safe_query || '%'
         or profiles.slug ilike '%' || safe_query || '%'
         or areas.general_area ilike '%' || safe_query || '%'
         or areas.province ilike '%' || safe_query || '%'
         or areas.municipality ilike '%' || safe_query || '%'
         or modalities.modality ilike '%' || safe_query || '%'
         or clubs.name ilike '%' || safe_query || '%'
      order by profiles.id, rank desc, areas.id, modalities.id, clubs.id
      limit safe_limit
    ) results
  ), '[]'::jsonb);
end;
$$;

create or replace function public.get_pachanga_platform_referee_health_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if not private.pachanga_referee_platform_can_health_v1(actor_id) then
    raise exception 'REFEREE_HEALTH_CAPABILITY_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'flags', private.pachanga_referee_flags_snapshot_v1(),
    'profiles', jsonb_build_object(
      'total', (select count(*) from public.pachanga_referee_profiles),
      'draft', (select count(*) from public.pachanga_referee_profiles where operational_status = 'draft'),
      'active', (select count(*) from public.pachanga_referee_profiles where operational_status = 'active'),
      'suspended', (select count(*) from public.pachanga_referee_profiles where operational_status = 'suspended'),
      'archived', (select count(*) from public.pachanga_referee_profiles where operational_status = 'archived'),
      'listed', (select count(*) from public.pachanga_referee_profiles where marketplace_status = 'listed')
    ),
    'relationships', jsonb_build_object(
      'pending', (select count(*) from public.pachanga_club_referee_relationships where status in ('invited', 'requested')),
      'active', (select count(*) from public.pachanga_club_referee_relationships where status = 'active')
    ),
    'assignments', jsonb_build_object(
      'proposed', (select count(*) from public.pachanga_referee_assignments where status = 'proposed'),
      'accepted', (select count(*) from public.pachanga_referee_assignments where status = 'accepted'),
      'confirmed', (select count(*) from public.pachanga_referee_assignments where status = 'confirmed'),
      'completed', (select count(*) from public.pachanga_referee_assignments where status = 'completed'),
      'activeSlotConflicts', (
        select count(*) from (
          select canonical_match_id, assignment_role from public.pachanga_referee_assignments
          where status in ('accepted', 'confirmed', 'completed')
          group by canonical_match_id, assignment_role having count(*) > 1
        ) conflicts
      ),
      'timeOverlapConflicts', (
        select count(*) from public.pachanga_referee_assignments left_assignment
        join public.pachanga_referee_assignments right_assignment
          on right_assignment.referee_profile_id = left_assignment.referee_profile_id
         and right_assignment.id > left_assignment.id
         and right_assignment.status in ('accepted', 'confirmed')
         and tstzrange(right_assignment.scheduled_start, right_assignment.scheduled_end, '[)')
             && tstzrange(left_assignment.scheduled_start, left_assignment.scheduled_end, '[)')
        where left_assignment.status in ('accepted', 'confirmed')
      )
    ),
    'statistics', jsonb_build_object(
      'snapshots', (select count(*) from public.pachanga_referee_statistics_snapshots),
      'disciplineNotAvailable', (select count(*) from public.pachanga_referee_statistics_snapshots
                                 where discipline_stats_status = 'NOT_AVAILABLE'
                                   and yellow_cards_shown is null and red_cards_shown is null and blue_cards_shown is null)
    ),
    'ledger', jsonb_build_object(
      'events', (select count(*) from private.pachanga_referee_events),
      'receipts', (select count(*) from private.pachanga_referee_operation_receipts),
      'lastServerSequence', (select coalesce(max(server_sequence), 0) from private.pachanga_referee_events)
    ),
    'generatedAt', clock_timestamp()
  );
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'public.get_pachanga_platform_referees_v1(jsonb,integer,integer)'::regprocedure,
    'public.get_pachanga_platform_referee_v1(uuid)'::regprocedure,
    'public.search_pachanga_platform_referees_v1(text,integer)'::regprocedure,
    'public.get_pachanga_platform_referee_health_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', signature);
    execute format('grant execute on function %s to authenticated', signature);
  end loop;
end;
$$;

comment on function public.get_pachanga_platform_referees_v1(jsonb, integer, integer) is
  'Paginated Referee R3 Control Center list without email, phone or invitation secrets.';
comment on function public.get_pachanga_platform_referee_v1(uuid) is
  'Referee R3 administrative detail; support receives a limited read model and never PII.';
comment on function public.search_pachanga_platform_referees_v1(text, integer) is
  'Administrative referee search by public identity, area, modality or visible Club; never email.';

create or replace function private.pachanga_referee_can_read_invalidation_v1(
  target_profile_id uuid,
  target_club_id uuid,
  target_user_id uuid,
  target_group_id uuid,
  target_audience text,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select actor_id is not null and (
    target_user_id = actor_id
    or private.pachanga_referee_platform_can_v1(actor_id, 'referees.read')
    or exists (select 1 from public.pachanga_referee_profiles p where p.id = target_profile_id and p.user_id = actor_id)
    or (target_club_id is not null and private.pachanga_club_can_v1(target_club_id, actor_id, 'read'))
    or exists (select 1 from public.pachanga_groups g where g.id = target_group_id and g.owner_id = actor_id)
    or (target_audience = 'marketplace' and coalesce((
      select s.referee_marketplace_enabled from private.pachanga_referee_foundation_settings s where s.singleton
    ), false))
  );
$$;

revoke all on function private.pachanga_referee_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.pachanga_referee_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, text, uuid
) to authenticated;
