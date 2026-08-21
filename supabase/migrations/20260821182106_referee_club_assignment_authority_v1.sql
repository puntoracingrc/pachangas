-- Pachangas IQ Referee Platform R3: Club/Competition authorization and the
-- server-authoritative command surface. R1 and R2 semantics remain intact.

create or replace function private.pachanga_club_can_v1(
  target_club_id uuid,
  target_user_id uuid,
  target_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_role text;
begin
  if target_user_id is null then return false; end if;
  if private.pachanga_club_platform_can_v1(target_user_id, 'clubs.manage') then return true; end if;
  if target_capability = 'read'
     and private.pachanga_club_platform_can_v1(target_user_id, 'clubs.read') then return true; end if;
  selected_role := private.pachanga_club_active_role_v1(target_club_id, target_user_id);
  return case selected_role
    when 'club_owner' then target_capability in (
      'read', 'profile_manage', 'staff_manage', 'staff_manage_non_owner',
      'team_links_manage', 'competition_create', 'competition_manage', 'ownership_manage',
      'referee_manage'
    )
    when 'club_admin' then target_capability in (
      'read', 'profile_manage', 'staff_manage_non_owner', 'team_links_manage', 'referee_manage'
    )
    when 'club_competition_manager' then target_capability in (
      'read', 'competition_create', 'competition_manage'
    )
    when 'club_referee_manager' then target_capability in ('read', 'referee_manage')
    when 'club_viewer' then target_capability = 'read'
    else false
  end;
end;
$$;

revoke all on function private.pachanga_club_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check;
alter table public.pachanga_competition_staff_assignments
  add constraint pachanga_competition_staff_assignments_staff_role_check
  check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin',
    'rules_manager', 'competition_referee_manager', 'viewer'
  ));

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
    when 'competition_director' then target_capability in ('read', 'manage', 'staff', 'rules', 'referees')
    when 'competition_admin' then target_capability in ('read', 'manage')
    when 'rules_manager' then target_capability in ('read', 'rules')
    when 'competition_referee_manager' then target_capability in ('read', 'referees')
    when 'viewer' then target_capability = 'read'
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_referee_platform_can_v1(
  target_user_id uuid,
  target_capability text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    private.pachanga_platform_capabilities_v1(
      private.pachanga_platform_role_for_user_v1(target_user_id)
    ) ? target_capability,
    false
  );
$$;

create or replace function private.pachanga_referee_assert_flags_v1(
  require_self_service boolean default false,
  require_public_profiles boolean default false,
  require_marketplace boolean default false,
  require_relationships boolean default false,
  require_assignments boolean default false
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_referee_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_referee_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.referee_foundation_enabled then
    raise exception 'REFEREE_FOUNDATION_DISABLED' using errcode = '0A000';
  end if;
  if require_self_service and not settings.referee_self_service_enabled then
    raise exception 'REFEREE_SELF_SERVICE_DISABLED' using errcode = '0A000';
  end if;
  if require_public_profiles and not settings.referee_public_profiles_enabled then
    raise exception 'REFEREE_PUBLIC_PROFILES_DISABLED' using errcode = '0A000';
  end if;
  if require_marketplace and not settings.referee_marketplace_enabled then
    raise exception 'REFEREE_MARKETPLACE_DISABLED' using errcode = '0A000';
  end if;
  if require_relationships and not settings.referee_club_relationships_enabled then
    raise exception 'REFEREE_CLUB_RELATIONSHIPS_DISABLED' using errcode = '0A000';
  end if;
  if require_assignments and not settings.referee_assignments_enabled then
    raise exception 'REFEREE_ASSIGNMENTS_DISABLED' using errcode = '0A000';
  end if;
end;
$$;

create or replace function private.pachanga_referee_profile_for_user_v1(target_user_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select profiles.id
  from public.pachanga_referee_profiles profiles
  where profiles.user_id = target_user_id
  order by profiles.server_sequence desc, profiles.id desc
  limit 1;
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
  binding public.pachanga_canonical_match_bindings%rowtype;
  canonical public.pachanga_canonical_matches%rowtype;
  selected_group public.pachanga_groups%rowtype;
  selected_match jsonb;
  open_match public.pachanga_open_matches%rowtype;
  external_match public.pachanga_external_matches%rowtype;
  challenge public.pachanga_team_challenges%rowtype;
  read_match public.pachanga_match_read_model%rowtype;
  competition_context public.pachanga_competition_match_contexts%rowtype;
  scheduled_start timestamptz;
  scheduled_end timestamptz;
  timezone_name text := 'Europe/Madrid';
  schedule_revision bigint := 0;
  concluded boolean := false;
  participant_groups jsonb := '[]'::jsonb;
  modality text := 'futbol7';
begin
  if target_source_kind not in ('group_match', 'open_match', 'external_match', 'team_challenge')
     or nullif(trim(target_source_id), '') is null then
    raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = '22023';
  end if;
  select * into binding
  from public.pachanga_canonical_match_bindings bindings
  where bindings.source_kind = target_source_kind
    and bindings.source_group_id is not distinct from target_source_group_id
    and bindings.source_id = target_source_id
    and bindings.binding_status = 'active'
  order by bindings.server_sequence desc, bindings.id desc
  limit 1;
  if not found then
    raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = 'P0002';
  end if;
  select * into canonical
  from public.pachanga_canonical_matches matches
  where matches.id = binding.canonical_match_id and matches.status = 'active';
  if not found then
    raise exception 'REFEREE_CANONICAL_MATCH_REQUIRED' using errcode = 'P0002';
  end if;

  if target_source_kind = 'group_match' then
    select * into selected_group from public.pachanga_groups groups where groups.id = target_source_group_id;
    select matches.value into selected_match
    from jsonb_array_elements(coalesce(selected_group.payload -> 'matches', '[]'::jsonb)) matches(value)
    where matches.value ->> 'id' = target_source_id
    limit 1;
    if selected_match is null then raise exception 'REFEREE_MATCH_SOURCE_NOT_FOUND' using errcode = 'P0002'; end if;
    timezone_name := coalesce(nullif(selected_match ->> 'timezone', ''), nullif(selected_group.payload #>> '{siteSettings,timezone}', ''), 'Europe/Madrid');
    scheduled_start := (selected_match ->> 'date')::timestamptz;
    modality := coalesce(nullif(selected_match ->> 'kind', ''), 'futbol7');
    select * into read_match from public.pachanga_match_read_model matches
    where matches.group_id = target_source_group_id and matches.match_id = target_source_id;
    schedule_revision := greatest(coalesce(read_match.match_version, 0), coalesce(read_match.source_payload_revision, 0), selected_group.payload_revision);
    concluded := coalesce(read_match.finalized, false) or read_match.match_state in ('finalized', 'historical');
    participant_groups := jsonb_build_array(target_source_group_id);

  elsif target_source_kind = 'open_match' then
    if target_source_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'REFEREE_MATCH_SOURCE_NOT_FOUND' using errcode = 'P0002';
    end if;
    select * into open_match from public.pachanga_open_matches matches
    where matches.id = target_source_id::uuid and matches.source_group_id = target_source_group_id;
    if not found then raise exception 'REFEREE_MATCH_SOURCE_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into selected_group from public.pachanga_groups groups where groups.id = open_match.source_group_id;
    select * into read_match from public.pachanga_match_read_model matches
    where matches.group_id = open_match.source_group_id and matches.match_id = open_match.source_match_id;
    timezone_name := coalesce(nullif(selected_group.payload #>> '{siteSettings,timezone}', ''), 'Europe/Madrid');
    scheduled_start := open_match.date;
    modality := open_match.modality;
    schedule_revision := greatest(coalesce(read_match.match_version, 0), coalesce(read_match.source_payload_revision, 0), selected_group.payload_revision);
    concluded := coalesce(read_match.finalized, false) or read_match.match_state in ('finalized', 'historical');
    participant_groups := jsonb_build_array(open_match.source_group_id);

  elsif target_source_kind = 'external_match' then
    if target_source_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'REFEREE_MATCH_SOURCE_NOT_FOUND' using errcode = 'P0002';
    end if;
    select * into external_match from public.pachanga_external_matches matches where matches.id = target_source_id::uuid;
    if not found then raise exception 'REFEREE_MATCH_SOURCE_NOT_FOUND' using errcode = 'P0002'; end if;
    scheduled_start := external_match.scheduled_at;
    modality := external_match.modality;
    schedule_revision := external_match.revision;
    concluded := external_match.state in ('confirmed', 'auto_confirmed');
    participant_groups := jsonb_build_array(external_match.home_group_id, external_match.away_group_id);

  else
    if target_source_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'REFEREE_MATCH_SOURCE_NOT_FOUND' using errcode = 'P0002';
    end if;
    select * into challenge from public.pachanga_team_challenges challenges where challenges.id = target_source_id::uuid;
    if not found then raise exception 'REFEREE_MATCH_SOURCE_NOT_FOUND' using errcode = 'P0002'; end if;
    scheduled_start := challenge.scheduled_at;
    modality := challenge.modality;
    schedule_revision := challenge.revision;
    select exists (
      select 1 from public.pachanga_external_matches matches
      where matches.challenge_id = challenge.id and matches.state in ('confirmed', 'auto_confirmed')
    ) into concluded;
    participant_groups := jsonb_build_array(challenge.sender_group_id, challenge.receiver_group_id);
  end if;

  if scheduled_start is null then raise exception 'REFEREE_MATCH_SCHEDULE_REQUIRED' using errcode = '22023'; end if;
  if not exists (select 1 from pg_timezone_names zones where zones.name = timezone_name) then
    timezone_name := 'Europe/Madrid';
  end if;
  scheduled_end := scheduled_start + case when modality in ('sala', 'FUTSAL') then interval '90 minutes' else interval '2 hours' end;
  select * into competition_context
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = canonical.id and contexts.status = 'lab_bound'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;

  return jsonb_build_object(
    'canonicalMatchId', canonical.id,
    'canonicalRevision', canonical.revision,
    'sourceKind', target_source_kind,
    'sourceGroupId', target_source_group_id,
    'sourceId', target_source_id,
    'scheduledStart', scheduled_start,
    'scheduledEnd', scheduled_end,
    'timezone', timezone_name,
    'scheduleRevision', schedule_revision,
    'concluded', concluded,
    'participantGroupIds', participant_groups,
    'competitionId', competition_context.competition_id
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
  competition_id uuid := nullif(match_snapshot ->> 'competitionId', '')::uuid;
  competition public.pachanga_competitions%rowtype;
begin
  if target_actor_id is null or target_requester_id is null then
    raise exception 'REFEREE_ASSIGNMENT_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  if target_requester_kind = 'TEAM' then
    if not exists (
      select 1 from jsonb_array_elements_text(coalesce(match_snapshot -> 'participantGroupIds', '[]'::jsonb)) ids(value)
      where ids.value::uuid = target_requester_id
    ) then raise exception 'REFEREE_ASSIGNMENT_TEAM_NOT_PARTICIPANT' using errcode = '42501'; end if;
    if not exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_requester_id and groups.owner_id = target_actor_id
    ) then raise exception 'REFEREE_ASSIGNMENT_TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
    return 'team_owner';
  elsif target_requester_kind = 'CLUB' then
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

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_referee_platform_can_v1(uuid,text)'::regprocedure,
    'private.pachanga_referee_assert_flags_v1(boolean,boolean,boolean,boolean,boolean)'::regprocedure,
    'private.pachanga_referee_profile_for_user_v1(uuid)'::regprocedure,
    'private.pachanga_referee_match_snapshot_v1(text,uuid,text)'::regprocedure,
    'private.pachanga_referee_assignment_authority_v1(jsonb,text,uuid,uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

create or replace function private.pachanga_referee_notify_v1(
  target_user_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_dedupe_key text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if target_user_id is null then return; end if;
  perform private.pachanga_notify_v1(
    target_user_id,
    left(target_kind, 80),
    left(target_title, 140),
    left(target_body, 500),
    left(target_action_url, 500),
    case when jsonb_typeof(target_payload) = 'object' then target_payload else '{}'::jsonb end,
    left(target_dedupe_key, 240)
  );
end;
$$;

create or replace function private.pachanga_referee_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id text,
  target_request_hash text,
  target_confirmed_revision bigint,
  target_reason_code text,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_profile_id uuid,
  target_club_id uuid,
  target_canonical_match_id uuid,
  target_invalidation_user_id uuid,
  target_invalidation_group_id uuid,
  target_invalidation_audience text,
  target_client_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  sequence_value bigint := nextval('private.pachanga_referee_sequence');
  confirmed_at timestamptz := clock_timestamp();
  response jsonb;
begin
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'action', target_action,
    'aggregateType', target_aggregate_type,
    'aggregateId', target_aggregate_id,
    'confirmedRevision', target_confirmed_revision,
    'serverSequence', sequence_value,
    'confirmedAt', confirmed_at,
    'snapshot', coalesce(target_snapshot, '{}'::jsonb)
  );
  insert into private.pachanga_referee_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    profile_id, club_id, canonical_match_id, action, aggregate_revision,
    server_sequence, reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_aggregate_type,
    target_aggregate_id, target_profile_id, target_club_id, target_canonical_match_id,
    target_action, target_confirmed_revision, sequence_value,
    left(coalesce(nullif(trim(target_reason_code), ''), target_action), 120),
    coalesce(target_event_payload, '{}'::jsonb), confirmed_at
  );
  insert into private.pachanga_referee_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id, target_request_hash,
    target_confirmed_revision, sequence_value,
    private.pachanga_referee_client_metadata_v1(target_client_metadata), response, confirmed_at
  );
  insert into public.pachanga_referee_invalidations(
    server_sequence, referee_profile_id, club_id, target_user_id, target_group_id,
    audience, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, target_profile_id, target_club_id, target_invalidation_user_id,
    target_invalidation_group_id,
    case when target_invalidation_audience = 'marketplace' then 'marketplace' else 'private' end,
    target_aggregate_type, target_aggregate_id, target_confirmed_revision, confirmed_at
  );
  if target_actor_id is not null and target_actor_id is distinct from target_invalidation_user_id then
    insert into public.pachanga_referee_invalidations(
      server_sequence, referee_profile_id, club_id, target_user_id, target_group_id,
      audience, entity_type, entity_id, revision, created_at
    ) values (
      sequence_value, target_profile_id, target_club_id, target_actor_id,
      target_invalidation_group_id, 'private', target_aggregate_type,
      target_aggregate_id, target_confirmed_revision, confirmed_at
    );
  end if;
  return response;
end;
$$;

revoke all on function private.pachanga_referee_notify_v1(uuid, text, text, text, text, jsonb, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_referee_store_command_v1(
  uuid, uuid, text, text, text, text, text, bigint, text, jsonb, jsonb,
  uuid, uuid, uuid, uuid, uuid, text, jsonb
) from public, anon, authenticated;

create or replace function public.command_pachanga_referee_platform_v1(
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
  request_hash text;
  replay jsonb;
  reason_code text;
  response jsonb;
  snapshot jsonb := '{}'::jsonb;
  event_payload jsonb := '{}'::jsonb;
  aggregate_type text;
  confirmed_revision bigint := 0;
  affected_profile_id uuid;
  affected_club_id uuid;
  affected_canonical_match_id uuid;
  invalidation_user_id uuid;
  invalidation_group_id uuid;
  invalidation_audience text := 'private';
  profile public.pachanga_referee_profiles%rowtype;
  target_profile public.pachanga_referee_profiles%rowtype;
  relationship public.pachanga_club_referee_relationships%rowtype;
  assignment public.pachanga_referee_assignments%rowtype;
  replaced_assignment public.pachanga_referee_assignments%rowtype;
  club public.pachanga_clubs%rowtype;
  identity_snapshot jsonb;
  match_snapshot jsonb;
  resolved_authority text;
  one_time_token text;
  target_kind text;
  target_user_id uuid;
  target_email text;
  target_profile_id uuid;
  target_club_id uuid;
  target_requester_id uuid;
  target_requester_kind text;
  target_role text;
  target_status text;
  target_side text;
  target_expires_at timestamptz;
  target_deadline timestamptz;
  item jsonb;
  item_id uuid;
  item_text text;
  notifier record;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or nullif(trim(command_action), '') is null then
    raise exception 'INVALID_OPERATION_ENVELOPE' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if jsonb_typeof(command_payload) <> 'object' or pg_column_size(command_payload) > 32768 then
    raise exception 'INVALID_COMMAND_PAYLOAD' using errcode = '22023';
  end if;
  reason_code := left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), command_action), 120);
  request_hash := private.pachanga_referee_request_hash_v1(command_action, aggregate_id, expected_revision, command_payload);
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  perform private.pachanga_referee_rate_limit_v1(actor_id, command_action);

  if command_action = 'profile.create' then
    perform private.pachanga_referee_assert_flags_v1(true, false, false, false, false);
    if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    perform pg_advisory_xact_lock(hashtextextended('referee-profile-user:' || actor_id::text, 0));
    if exists (select 1 from public.pachanga_referee_profiles profiles where profiles.user_id = actor_id) then
      raise exception 'REFEREE_PROFILE_ALREADY_EXISTS' using errcode = 'PT409';
    end if;
    if exists (select 1 from public.pachanga_referee_profiles profiles where profiles.id = aggregate_id) then
      raise exception 'REFEREE_PROFILE_ID_EXISTS' using errcode = 'PT409';
    end if;
    if not exists (
      select 1 from auth.users users
      where users.id = actor_id and users.email_confirmed_at is not null
        and not coalesce((users.raw_app_meta_data ->> 'is_anonymous')::boolean, false)
    ) then raise exception 'VERIFIED_EMAIL_REQUIRED' using errcode = '42501'; end if;
    item_text := lower(trim(coalesce(command_payload ->> 'slug', '')));
    if item_text !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(item_text) not between 3 and 80 then
      raise exception 'INVALID_REFEREE_SLUG' using errcode = '22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('referee-profile-slug:' || item_text, 0));
    if exists (select 1 from public.pachanga_referee_profiles profiles where profiles.slug = item_text) then
      raise exception 'REFEREE_SLUG_TAKEN' using errcode = 'PT409';
    end if;
    identity_snapshot := private.pachanga_referee_identity_snapshot_v1(actor_id);
    if length(trim(coalesce(identity_snapshot ->> 'displayName', ''))) < 2 then
      raise exception 'PUBLIC_IDENTITY_REQUIRED' using errcode = '22023';
    end if;
    insert into public.pachanga_referee_profiles(
      id, user_id, slug, public_display_name_snapshot, public_avatar_snapshot,
      bio, experience_since_year, experience_summary, operational_status,
      verification_status, visibility, marketplace_status, availability_status,
      available_for_assignments, share_recurring_availability, revision, server_sequence
    ) values (
      aggregate_id, actor_id, item_text,
      identity_snapshot ->> 'displayName', nullif(identity_snapshot ->> 'avatar', ''),
      left(coalesce(command_payload ->> 'bio', ''), 1200),
      nullif(command_payload ->> 'experienceSinceYear', '')::integer,
      left(coalesce(command_payload ->> 'experienceSummary', ''), 1200),
      'draft', 'unverified', 'private', 'not_listed',
      coalesce(nullif(command_payload ->> 'availabilityStatus', ''), 'UNAVAILABLE'),
      false, false, 1, nextval('private.pachanga_referee_sequence')
    ) returning * into profile;
    perform private.pachanga_referee_refresh_statistics_v1(profile.id, 'incremental');
    affected_profile_id := profile.id;
    invalidation_user_id := actor_id;
    aggregate_type := 'referee_profile';
    confirmed_revision := profile.revision;
    snapshot := private.pachanga_referee_private_snapshot_v1(profile.id, actor_id);
    event_payload := jsonb_build_object('slug', profile.slug, 'operationalStatus', profile.operational_status);

  elsif command_action in (
    'profile.update', 'profile.modalities.replace', 'profile.areas.replace',
    'profile.availability.replace', 'profile.activate', 'profile.archive',
    'marketplace.list', 'marketplace.pause', 'marketplace.unlist'
  ) then
    perform private.pachanga_referee_assert_flags_v1(false, false, command_action like 'marketplace.%', false, false);
    select * into profile from public.pachanga_referee_profiles profiles
    where profiles.id = aggregate_id for update;
    if not found then raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
    if profile.user_id <> actor_id then raise exception 'REFEREE_PROFILE_OWNER_REQUIRED' using errcode = '42501'; end if;
    if profile.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if profile.operational_status in ('suspended', 'archived') and command_action <> 'profile.archive' then
      raise exception 'REFEREE_PROFILE_NOT_MUTABLE' using errcode = '42501';
    end if;
    affected_profile_id := profile.id;
    invalidation_user_id := actor_id;
    aggregate_type := 'referee_profile';

    if command_action = 'profile.update' then
      if command_payload ? 'slug' then
        item_text := lower(trim(coalesce(command_payload ->> 'slug', '')));
        if item_text !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(item_text) not between 3 and 80 then
          raise exception 'INVALID_REFEREE_SLUG' using errcode = '22023';
        end if;
        perform pg_advisory_xact_lock(hashtextextended('referee-profile-slug:' || item_text, 0));
        if exists (
          select 1 from public.pachanga_referee_profiles profiles
          where profiles.slug = item_text and profiles.id <> profile.id
        ) then raise exception 'REFEREE_SLUG_TAKEN' using errcode = 'PT409'; end if;
      end if;
      update public.pachanga_referee_profiles profiles set
        slug = case when command_payload ? 'slug' then item_text else profiles.slug end,
        bio = case when command_payload ? 'bio' then left(command_payload ->> 'bio', 1200) else profiles.bio end,
        experience_since_year = case when command_payload ? 'experienceSinceYear' then nullif(command_payload ->> 'experienceSinceYear', '')::integer else profiles.experience_since_year end,
        experience_summary = case when command_payload ? 'experienceSummary' then left(command_payload ->> 'experienceSummary', 1200) else profiles.experience_summary end,
        visibility = case when command_payload ? 'visibility' then command_payload ->> 'visibility' else profiles.visibility end,
        availability_status = case when command_payload ? 'availabilityStatus' then upper(command_payload ->> 'availabilityStatus') else profiles.availability_status end,
        available_for_assignments = case when command_payload ? 'availableForAssignments' then (command_payload ->> 'availableForAssignments')::boolean else profiles.available_for_assignments end,
        share_recurring_availability = case when command_payload ? 'shareRecurringAvailability' then (command_payload ->> 'shareRecurringAvailability')::boolean else profiles.share_recurring_availability end,
        marketplace_status = case
          when (command_payload ? 'visibility' and command_payload ->> 'visibility' <> 'public')
            or (command_payload ? 'availableForAssignments' and not (command_payload ->> 'availableForAssignments')::boolean)
          then 'not_listed' else profiles.marketplace_status end,
        revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
      event_payload := jsonb_build_object('profileUpdated', true);

    elsif command_action = 'profile.modalities.replace' then
      if jsonb_typeof(command_payload -> 'modalities') <> 'array'
         or jsonb_array_length(command_payload -> 'modalities') > 10 then
        raise exception 'INVALID_REFEREE_MODALITIES' using errcode = '22023';
      end if;
      update public.pachanga_referee_modalities modalities set
        active = false, revision = modalities.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where modalities.referee_profile_id = profile.id and modalities.active;
      for item in select value from jsonb_array_elements(command_payload -> 'modalities') entries(value) loop
        item_text := upper(trim(coalesce(item ->> 'modality', '')));
        if item_text not in ('FOOTBALL_11', 'FOOTBALL_7', 'FOOTBALL_5', 'FUTSAL', 'OTHER') then
          raise exception 'INVALID_REFEREE_MODALITY' using errcode = '22023';
        end if;
        insert into public.pachanga_referee_modalities(
          referee_profile_id, modality, active, experience_since_year, public_note,
          revision, server_sequence
        ) values (
          profile.id, item_text, true, nullif(item ->> 'experienceSinceYear', '')::integer,
          left(coalesce(item ->> 'note', ''), 240), 1, nextval('private.pachanga_referee_sequence')
        ) on conflict (referee_profile_id, modality) do update set
          active = true,
          experience_since_year = excluded.experience_since_year,
          public_note = excluded.public_note,
          revision = public.pachanga_referee_modalities.revision + 1,
          server_sequence = excluded.server_sequence;
      end loop;
      update public.pachanga_referee_profiles profiles set
        revision = profiles.revision + 1, server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
      event_payload := jsonb_build_object('modalitiesReplaced', jsonb_array_length(command_payload -> 'modalities'));

    elsif command_action = 'profile.areas.replace' then
      if jsonb_typeof(command_payload -> 'areas') <> 'array'
         or jsonb_array_length(command_payload -> 'areas') > 20 then
        raise exception 'INVALID_REFEREE_AREAS' using errcode = '22023';
      end if;
      update public.pachanga_referee_service_areas areas set
        status = 'inactive', revision = areas.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where areas.referee_profile_id = profile.id and areas.status = 'active';
      for item in select value from jsonb_array_elements(command_payload -> 'areas') entries(value) loop
        if length(trim(coalesce(item ->> 'generalArea', ''))) < 2 then
          raise exception 'REFEREE_AREA_REQUIRED' using errcode = '22023';
        end if;
        insert into public.pachanga_referee_service_areas(
          referee_profile_id, country_code, province, municipality, general_area,
          travel_radius_km, status, revision, server_sequence
        ) values (
          profile.id, upper(coalesce(nullif(trim(item ->> 'countryCode'), ''), 'ES')),
          left(trim(coalesce(item ->> 'province', '')), 120),
          left(trim(coalesce(item ->> 'municipality', '')), 120),
          left(trim(item ->> 'generalArea'), 160),
          nullif(item ->> 'travelRadiusKm', '')::integer,
          'active', 1, nextval('private.pachanga_referee_sequence')
        );
      end loop;
      update public.pachanga_referee_profiles profiles set
        revision = profiles.revision + 1, server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
      event_payload := jsonb_build_object('areasReplaced', jsonb_array_length(command_payload -> 'areas'));

    elsif command_action = 'profile.availability.replace' then
      if jsonb_typeof(coalesce(command_payload -> 'windows', '[]'::jsonb)) <> 'array'
         or jsonb_typeof(coalesce(command_payload -> 'exceptions', '[]'::jsonb)) <> 'array'
         or jsonb_array_length(coalesce(command_payload -> 'windows', '[]'::jsonb)) > 40
         or jsonb_array_length(coalesce(command_payload -> 'exceptions', '[]'::jsonb)) > 40 then
        raise exception 'INVALID_REFEREE_AVAILABILITY' using errcode = '22023';
      end if;
      update public.pachanga_referee_availability_windows windows set
        status = 'inactive', revision = windows.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where windows.referee_profile_id = profile.id and windows.status = 'active';
      update public.pachanga_referee_availability_exceptions exceptions set
        status = 'inactive', revision = exceptions.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where exceptions.referee_profile_id = profile.id and exceptions.status = 'active';
      for item in select value from jsonb_array_elements(coalesce(command_payload -> 'windows', '[]'::jsonb)) entries(value) loop
        if not exists (select 1 from pg_timezone_names zones where zones.name = item ->> 'timezone') then
          raise exception 'INVALID_REFEREE_TIMEZONE' using errcode = '22023';
        end if;
        insert into public.pachanga_referee_availability_windows(
          referee_profile_id, weekday, start_local_time, end_local_time, timezone,
          public_visible, status, revision, server_sequence
        ) values (
          profile.id, (item ->> 'weekday')::smallint, (item ->> 'startLocalTime')::time,
          (item ->> 'endLocalTime')::time, item ->> 'timezone',
          coalesce((item ->> 'publicVisible')::boolean, false), 'active', 1,
          nextval('private.pachanga_referee_sequence')
        );
      end loop;
      for item in select value from jsonb_array_elements(coalesce(command_payload -> 'exceptions', '[]'::jsonb)) entries(value) loop
        insert into public.pachanga_referee_availability_exceptions(
          referee_profile_id, unavailable_from, unavailable_until, private_reason,
          status, revision, server_sequence
        ) values (
          profile.id, (item ->> 'unavailableFrom')::timestamptz,
          (item ->> 'unavailableUntil')::timestamptz,
          left(coalesce(item ->> 'reason', ''), 500), 'active', 1,
          nextval('private.pachanga_referee_sequence')
        );
      end loop;
      update public.pachanga_referee_profiles profiles set
        revision = profiles.revision + 1, server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
      event_payload := jsonb_build_object(
        'windowsReplaced', jsonb_array_length(coalesce(command_payload -> 'windows', '[]'::jsonb)),
        'exceptionsReplaced', jsonb_array_length(coalesce(command_payload -> 'exceptions', '[]'::jsonb))
      );

    elsif command_action = 'profile.activate' then
      if profile.operational_status <> 'draft' then raise exception 'REFEREE_PROFILE_ACTIVATION_NOT_ALLOWED' using errcode = '22023'; end if;
      if length(trim(profile.public_display_name_snapshot)) < 2
         or length(trim(profile.bio || profile.experience_summary)) < 10
         or not exists (select 1 from public.pachanga_referee_modalities m where m.referee_profile_id = profile.id and m.active)
         or not exists (select 1 from public.pachanga_referee_service_areas a where a.referee_profile_id = profile.id and a.status = 'active') then
        raise exception 'REFEREE_PROFILE_INCOMPLETE' using errcode = '22023';
      end if;
      update public.pachanga_referee_profiles profiles set
        operational_status = 'active', revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
      event_payload := jsonb_build_object('operationalStatus', 'active', 'verificationStatus', profile.verification_status);

    elsif command_action = 'profile.archive' then
      if profile.operational_status not in ('draft', 'active') then raise exception 'REFEREE_PROFILE_ARCHIVE_NOT_ALLOWED' using errcode = '22023'; end if;
      update public.pachanga_referee_profiles profiles set
        operational_status = 'archived', marketplace_status = 'not_listed',
        available_for_assignments = false, revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
      event_payload := jsonb_build_object('operationalStatus', 'archived');

    else
      if command_action = 'marketplace.list' then
        if profile.operational_status <> 'active' or profile.visibility <> 'public'
           or not profile.available_for_assignments then
          raise exception 'REFEREE_MARKETPLACE_PROFILE_NOT_ELIGIBLE' using errcode = '22023';
        end if;
        target_status := 'listed';
      elsif command_action = 'marketplace.pause' then target_status := 'paused';
      else target_status := 'not_listed';
      end if;
      update public.pachanga_referee_profiles profiles set
        marketplace_status = target_status,
        revision = profiles.revision + 1,
        server_sequence = nextval('private.pachanga_referee_sequence')
      where profiles.id = profile.id returning * into profile;
      invalidation_audience := 'marketplace';
      event_payload := jsonb_build_object('marketplaceStatus', target_status);
    end if;
    confirmed_revision := profile.revision;
    snapshot := private.pachanga_referee_private_snapshot_v1(profile.id, actor_id);

  elsif command_action in (
    'relationship.invite', 'relationship.request', 'relationship.accept',
    'relationship.reject', 'relationship.cancel', 'relationship.end',
    'relationship.visibility.set'
  ) then
    perform private.pachanga_referee_assert_flags_v1(false, false, false, true, false);
    aggregate_type := 'club_referee_relationship';
    if command_action in ('relationship.invite', 'relationship.request') then
      if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      if exists (select 1 from public.pachanga_club_referee_relationships relationships where relationships.id = aggregate_id) then
        raise exception 'REFEREE_RELATIONSHIP_ID_EXISTS' using errcode = 'PT409';
      end if;
      target_club_id := nullif(command_payload ->> 'clubId', '')::uuid;
      select * into club from public.pachanga_clubs clubs where clubs.id = target_club_id;
      if not found or club.operational_status in ('suspended', 'rejected', 'archived') then
        raise exception 'REFEREE_RELATIONSHIP_CLUB_UNAVAILABLE' using errcode = '42501';
      end if;
      target_role := upper(trim(coalesce(command_payload ->> 'relationshipType', 'REGULAR')));
      if target_role not in ('REGULAR', 'COLLABORATOR', 'PREFERRED') then
        raise exception 'INVALID_REFEREE_RELATIONSHIP_TYPE' using errcode = '22023';
      end if;
      if command_action = 'relationship.invite' then
        if not private.pachanga_club_can_v1(target_club_id, actor_id, 'referee_manage') then
          raise exception 'CLUB_REFEREE_CAPABILITY_REQUIRED' using errcode = '42501';
        end if;
        target_kind := trim(coalesce(command_payload ->> 'targetKind', ''));
        target_expires_at := coalesce(nullif(command_payload ->> 'expiresAt', '')::timestamptz, clock_timestamp() + interval '7 days');
        if target_expires_at <= clock_timestamp() or target_expires_at > clock_timestamp() + interval '30 days' then
          raise exception 'INVALID_INVITATION_EXPIRY' using errcode = '22023';
        end if;
        one_time_token := encode(extensions.gen_random_bytes(32), 'hex');
        if target_kind = 'registered_user' then
          target_user_id := nullif(command_payload ->> 'targetUserId', '')::uuid;
          if target_user_id is null or not exists (select 1 from auth.users users where users.id = target_user_id) then
            raise exception 'REFEREE_INVITATION_TARGET_NOT_FOUND' using errcode = 'P0002';
          end if;
          target_profile_id := private.pachanga_referee_profile_for_user_v1(target_user_id);
        elsif target_kind = 'email_target' then
          target_email := lower(trim(coalesce(command_payload ->> 'targetEmail', '')));
          if target_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' or length(target_email) > 320 then
            raise exception 'INVALID_INVITATION_EMAIL' using errcode = '22023';
          end if;
        else raise exception 'INVALID_INVITATION_TARGET_KIND' using errcode = '22023';
        end if;
        insert into public.pachanga_club_referee_relationships(
          id, club_id, referee_profile_id, target_kind, target_user_id,
          relationship_type, initiated_by, status, revision, server_sequence,
          created_by, reason, expires_at
        ) values (
          aggregate_id, target_club_id, target_profile_id, target_kind, target_user_id,
          target_role, 'CLUB', 'invited', 1, nextval('private.pachanga_referee_sequence'),
          actor_id, left(coalesce(command_payload ->> 'reason', ''), 1200), target_expires_at
        ) returning * into relationship;
        insert into private.pachanga_referee_invitation_secrets(
          relationship_id, token_hash, target_email_normalized, target_email_hash,
          retention_until
        ) values (
          relationship.id, encode(extensions.digest(one_time_token, 'sha256'), 'hex'),
          target_email,
          case when target_email is null then null else encode(extensions.digest(target_email, 'sha256'), 'hex') end,
          target_expires_at + interval '90 days'
        );
        if target_user_id is not null then
          perform private.pachanga_referee_notify_v1(
            target_user_id, 'referee_club_invitation', 'Invitación de Club',
            club.name || ' quiere vincularte como árbitro.',
            '/perfil/arbitro?relationship=' || relationship.id::text,
            jsonb_build_object('relationshipId', relationship.id, 'clubId', club.id),
            'referee-club-invite:' || operation_id::text || ':' || target_user_id::text
          );
        end if;
        invalidation_user_id := target_user_id;
      else
        target_profile_id := private.pachanga_referee_profile_for_user_v1(actor_id);
        if target_profile_id is null then raise exception 'REFEREE_PROFILE_REQUIRED' using errcode = '42501'; end if;
        select * into target_profile from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id;
        if target_profile.operational_status <> 'active' then raise exception 'ACTIVE_REFEREE_PROFILE_REQUIRED' using errcode = '42501'; end if;
        if exists (
          select 1 from public.pachanga_club_referee_relationships relationships
          where relationships.club_id = target_club_id and relationships.referee_profile_id = target_profile_id
            and relationships.status in ('invited', 'requested', 'active')
        ) then raise exception 'REFEREE_RELATIONSHIP_ALREADY_CURRENT' using errcode = 'PT409'; end if;
        insert into public.pachanga_club_referee_relationships(
          id, club_id, referee_profile_id, target_kind, target_user_id,
          relationship_type, initiated_by, status, revision, server_sequence,
          created_by, reason
        ) values (
          aggregate_id, target_club_id, target_profile_id, 'profile_request', actor_id,
          target_role, 'REFEREE', 'requested', 1, nextval('private.pachanga_referee_sequence'),
          actor_id, left(coalesce(command_payload ->> 'reason', ''), 1200)
        ) returning * into relationship;
        for notifier in
          select memberships.user_id from public.pachanga_club_memberships memberships
          where memberships.club_id = target_club_id and memberships.status = 'active'
            and memberships.role in ('club_owner', 'club_admin', 'club_referee_manager')
        loop
          perform private.pachanga_referee_notify_v1(
            notifier.user_id, 'referee_club_request', 'Solicitud de árbitro',
            target_profile.public_display_name_snapshot || ' solicita vincularse con ' || club.name || '.',
            '/admin/referees?relationship=' || relationship.id::text,
            jsonb_build_object('relationshipId', relationship.id, 'clubId', club.id),
            'referee-club-request:' || operation_id::text || ':' || notifier.user_id::text
          );
        end loop;
        invalidation_user_id := actor_id;
      end if;
      affected_profile_id := relationship.referee_profile_id;
      affected_club_id := relationship.club_id;
      confirmed_revision := relationship.revision;
      event_payload := jsonb_build_object(
        'relationshipType', relationship.relationship_type,
        'initiatedBy', relationship.initiated_by,
        'status', relationship.status,
        'targetKind', relationship.target_kind,
        'expiresAt', relationship.expires_at
      );
    else
      select * into relationship
      from public.pachanga_club_referee_relationships relationships
      where relationships.id = aggregate_id for update;
      if not found then raise exception 'REFEREE_RELATIONSHIP_NOT_FOUND' using errcode = 'P0002'; end if;
      if relationship.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      select * into club from public.pachanga_clubs clubs where clubs.id = relationship.club_id;
      affected_profile_id := relationship.referee_profile_id;
      affected_club_id := relationship.club_id;
      target_profile_id := coalesce(relationship.referee_profile_id, private.pachanga_referee_profile_for_user_v1(actor_id));

      if command_action in ('relationship.accept', 'relationship.reject') then
        if relationship.status = 'invited' then
          if relationship.expires_at <= clock_timestamp() then raise exception 'REFEREE_INVITATION_EXPIRED' using errcode = '42501'; end if;
          if relationship.target_kind = 'registered_user' and relationship.target_user_id <> actor_id then
            raise exception 'REFEREE_INVITATION_TARGET_REQUIRED' using errcode = '42501';
          end if;
          if relationship.target_kind = 'email_target' and not exists (
            select 1 from private.pachanga_referee_invitation_secrets secrets
            join auth.users users on users.id = actor_id and users.email_confirmed_at is not null
            where secrets.relationship_id = relationship.id
              and secrets.target_email_hash = encode(extensions.digest(lower(users.email), 'sha256'), 'hex')
          ) then raise exception 'REFEREE_INVITATION_TARGET_REQUIRED' using errcode = '42501'; end if;
          if relationship.target_kind = 'email_target' and (
            length(trim(coalesce(command_payload ->> 'token', ''))) <> 64 or not exists (
              select 1 from private.pachanga_referee_invitation_secrets secrets
              where secrets.relationship_id = relationship.id
                and secrets.consumed_at is null
                and secrets.token_hash = encode(extensions.digest(trim(command_payload ->> 'token'), 'sha256'), 'hex')
            )
          ) then raise exception 'REFEREE_INVITATION_TOKEN_INVALID' using errcode = '42501'; end if;
          if command_action = 'relationship.accept' then
            if target_profile_id is null then raise exception 'REFEREE_PROFILE_REQUIRED' using errcode = '42501'; end if;
            select * into target_profile from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id;
            if target_profile.user_id <> actor_id or target_profile.operational_status <> 'active' then
              raise exception 'ACTIVE_REFEREE_PROFILE_REQUIRED' using errcode = '42501';
            end if;
          end if;
          update private.pachanga_referee_invitation_secrets secrets
          set consumed_at = clock_timestamp(),
              target_email_normalized = null,
              target_email_hash = null,
              retention_until = least(secrets.retention_until, clock_timestamp())
          where secrets.relationship_id = relationship.id;
        elsif relationship.status = 'requested' then
          if not private.pachanga_club_can_v1(relationship.club_id, actor_id, 'referee_manage') then
            raise exception 'CLUB_REFEREE_CAPABILITY_REQUIRED' using errcode = '42501';
          end if;
          target_profile_id := relationship.referee_profile_id;
          select * into target_profile from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id;
          if command_action = 'relationship.accept' and target_profile.operational_status <> 'active' then
            raise exception 'ACTIVE_REFEREE_PROFILE_REQUIRED' using errcode = '42501';
          end if;
        else raise exception 'REFEREE_RELATIONSHIP_NOT_PENDING' using errcode = 'PT409'; end if;
        target_status := case when command_action = 'relationship.accept' then 'active' else 'rejected' end;
        update public.pachanga_club_referee_relationships relationships set
          referee_profile_id = case when target_status = 'active' then target_profile_id else relationships.referee_profile_id end,
          target_kind = case
            when target_status = 'active' and relationships.target_kind = 'email_target' then 'registered_user'
            else relationships.target_kind
          end,
          target_user_id = case
            when target_status = 'active' then coalesce(relationships.target_user_id, target_profile.user_id)
            else relationships.target_user_id
          end,
          status = target_status,
          responded_by = actor_id,
          started_at = case when target_status = 'active' then clock_timestamp() else null end,
          ended_at = case when target_status = 'rejected' then clock_timestamp() else null end,
          ended_by = case when target_status = 'rejected' then actor_id else null end,
          revision = relationships.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where relationships.id = relationship.id returning * into relationship;
        perform private.pachanga_referee_notify_v1(
          relationship.created_by,
          case when target_status = 'active' then 'referee_club_relationship_accepted' else 'referee_club_relationship_rejected' end,
          case when target_status = 'active' then 'Vinculación aceptada' else 'Vinculación rechazada' end,
          'La solicitud de vinculación arbitral con ' || club.name || ' ha cambiado de estado.',
          '/perfil/arbitro', jsonb_build_object('relationshipId', relationship.id, 'clubId', club.id),
          'referee-relationship-response:' || operation_id::text || ':' || relationship.created_by::text
        );
        invalidation_user_id := case when target_status = 'active' then target_profile.user_id else actor_id end;

      elsif command_action in ('relationship.cancel', 'relationship.end') then
        if relationship.status not in ('invited', 'requested', 'active') then
          raise exception 'REFEREE_RELATIONSHIP_NOT_CURRENT' using errcode = 'PT409';
        end if;
        if not (
          (target_profile_id is not null and exists (
            select 1 from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id and profiles.user_id = actor_id
          )) or private.pachanga_club_can_v1(relationship.club_id, actor_id, 'referee_manage')
        ) then raise exception 'REFEREE_RELATIONSHIP_AUTHORITY_REQUIRED' using errcode = '42501'; end if;
        target_status := case when relationship.status = 'active' then 'ended' else 'cancelled' end;
        update public.pachanga_club_referee_relationships relationships set
          status = target_status, ended_at = clock_timestamp(), ended_by = actor_id,
          reason = left(coalesce(command_payload ->> 'reason', relationships.reason), 1200),
          revision = relationships.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where relationships.id = relationship.id returning * into relationship;
        invalidation_user_id := relationship.target_user_id;

      else
        if relationship.status <> 'active' then raise exception 'ACTIVE_REFEREE_RELATIONSHIP_REQUIRED' using errcode = '22023'; end if;
        target_side := lower(trim(coalesce(command_payload ->> 'side', '')));
        if target_side = 'referee' then
          if not exists (
            select 1 from public.pachanga_referee_profiles profiles
            where profiles.id = relationship.referee_profile_id and profiles.user_id = actor_id
          ) then raise exception 'REFEREE_PROFILE_OWNER_REQUIRED' using errcode = '42501'; end if;
          update public.pachanga_club_referee_relationships relationships set
            show_on_referee_profile = coalesce((command_payload ->> 'visible')::boolean, false),
            revision = relationships.revision + 1,
            server_sequence = nextval('private.pachanga_referee_sequence')
          where relationships.id = relationship.id returning * into relationship;
        elsif target_side = 'club' then
          if not private.pachanga_club_can_v1(relationship.club_id, actor_id, 'referee_manage') then
            raise exception 'CLUB_REFEREE_CAPABILITY_REQUIRED' using errcode = '42501';
          end if;
          update public.pachanga_club_referee_relationships relationships set
            show_on_club_profile = coalesce((command_payload ->> 'visible')::boolean, false),
            revision = relationships.revision + 1,
            server_sequence = nextval('private.pachanga_referee_sequence')
          where relationships.id = relationship.id returning * into relationship;
        else raise exception 'INVALID_RELATIONSHIP_VISIBILITY_SIDE' using errcode = '22023'; end if;
        invalidation_user_id := relationship.target_user_id;
      end if;
      affected_profile_id := relationship.referee_profile_id;
      confirmed_revision := relationship.revision;
      event_payload := jsonb_build_object(
        'relationshipType', relationship.relationship_type,
        'initiatedBy', relationship.initiated_by,
        'status', relationship.status,
        'showOnRefereeProfile', relationship.show_on_referee_profile,
        'showOnClubProfile', relationship.show_on_club_profile,
        'startedAt', relationship.started_at,
        'endedAt', relationship.ended_at
      );
    end if;
    if affected_profile_id is not null then
      perform private.pachanga_referee_refresh_statistics_v1(affected_profile_id, 'incremental');
    end if;
    snapshot := jsonb_build_object(
      'relationship', jsonb_build_object(
        'id', relationship.id, 'clubId', relationship.club_id, 'clubName', club.name,
        'refereeProfileId', relationship.referee_profile_id,
        'relationshipType', relationship.relationship_type,
        'initiatedBy', relationship.initiated_by, 'status', relationship.status,
        'showOnRefereeProfile', relationship.show_on_referee_profile,
        'showOnClubProfile', relationship.show_on_club_profile,
        'startedAt', relationship.started_at, 'endedAt', relationship.ended_at,
        'expiresAt', relationship.expires_at, 'revision', relationship.revision,
        'serverSequence', relationship.server_sequence
      )
    );

  elsif command_action in (
    'assignment.propose', 'assignment.accept', 'assignment.decline',
    'assignment.confirm', 'assignment.cancel', 'assignment.replace'
  ) then
    perform private.pachanga_referee_assert_flags_v1(false, false, false, false, true);
    aggregate_type := 'referee_assignment';
    if command_action = 'assignment.propose' then
      if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      if exists (select 1 from public.pachanga_referee_assignments assignments where assignments.id = aggregate_id) then
        raise exception 'REFEREE_ASSIGNMENT_ID_EXISTS' using errcode = 'PT409';
      end if;
      target_profile_id := nullif(command_payload ->> 'refereeProfileId', '')::uuid;
      select * into target_profile from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id;
      if not found or target_profile.operational_status <> 'active' or not target_profile.available_for_assignments then
        raise exception 'REFEREE_PROFILE_NOT_ASSIGNABLE' using errcode = '42501';
      end if;
      target_role := upper(coalesce(nullif(trim(command_payload ->> 'assignmentRole'), ''), 'MAIN_REFEREE'));
      if target_role <> 'MAIN_REFEREE' then raise exception 'REFEREE_ROLE_NOT_AVAILABLE' using errcode = '0A000'; end if;
      target_requester_kind := upper(trim(coalesce(command_payload ->> 'requesterKind', '')));
      target_requester_id := nullif(command_payload ->> 'requesterId', '')::uuid;
      match_snapshot := private.pachanga_referee_match_snapshot_v1(
        trim(command_payload ->> 'sourceKind'),
        nullif(command_payload ->> 'sourceGroupId', '')::uuid,
        trim(command_payload ->> 'sourceId')
      );
      resolved_authority := private.pachanga_referee_assignment_authority_v1(
        match_snapshot, target_requester_kind, target_requester_id, actor_id
      );
      target_deadline := coalesce(nullif(command_payload ->> 'responseDeadline', '')::timestamptz, clock_timestamp() + interval '72 hours');
      if target_deadline <= clock_timestamp() or target_deadline > clock_timestamp() + interval '30 days' then
        raise exception 'INVALID_ASSIGNMENT_DEADLINE' using errcode = '22023';
      end if;
      insert into public.pachanga_referee_assignments(
        id, referee_profile_id, canonical_match_id, assignment_role, requester_kind,
        requester_team_id, requester_club_id, competition_id, source_kind,
        source_group_id, source_id, status, scheduled_start, scheduled_end, timezone,
        schedule_source_revision, proposed_by, authority_used, proposal_message,
        response_deadline, revision, server_sequence
      ) values (
        aggregate_id, target_profile.id, (match_snapshot ->> 'canonicalMatchId')::uuid,
        target_role, target_requester_kind,
        case when target_requester_kind = 'TEAM' then target_requester_id else null end,
        case when target_requester_kind = 'CLUB' then target_requester_id else null end,
        nullif(match_snapshot ->> 'competitionId', '')::uuid,
        match_snapshot ->> 'sourceKind', nullif(match_snapshot ->> 'sourceGroupId', '')::uuid,
        match_snapshot ->> 'sourceId', 'proposed',
        (match_snapshot ->> 'scheduledStart')::timestamptz,
        (match_snapshot ->> 'scheduledEnd')::timestamptz,
        match_snapshot ->> 'timezone', (match_snapshot ->> 'scheduleRevision')::bigint,
        actor_id, resolved_authority, left(coalesce(command_payload ->> 'message', ''), 800),
        target_deadline, 1, nextval('private.pachanga_referee_sequence')
      ) returning * into assignment;
      perform private.pachanga_referee_notify_v1(
        target_profile.user_id, 'referee_assignment_proposed', 'Propuesta de arbitraje',
        'Has recibido una propuesta para arbitrar un partido.',
        '/perfil/arbitro?assignment=' || assignment.id::text,
        jsonb_build_object('assignmentId', assignment.id, 'canonicalMatchId', assignment.canonical_match_id),
        'referee-assignment-proposed:' || operation_id::text || ':' || target_profile.user_id::text
      );
      invalidation_user_id := target_profile.user_id;

    else
      select * into assignment from public.pachanga_referee_assignments assignments
      where assignments.id = aggregate_id for update;
      if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
      if assignment.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      select * into target_profile from public.pachanga_referee_profiles profiles
      where profiles.id = assignment.referee_profile_id for update;
      match_snapshot := private.pachanga_referee_match_snapshot_v1(
        assignment.source_kind, assignment.source_group_id, assignment.source_id
      );
      target_requester_id := coalesce(assignment.requester_team_id, assignment.requester_club_id);

      if command_action in ('assignment.accept', 'assignment.decline') then
        if target_profile.user_id <> actor_id then raise exception 'REFEREE_PROFILE_OWNER_REQUIRED' using errcode = '42501'; end if;
        if assignment.status <> 'proposed' then raise exception 'REFEREE_ASSIGNMENT_NOT_PROPOSED' using errcode = 'PT409'; end if;
        if assignment.response_deadline <= clock_timestamp() then raise exception 'REFEREE_ASSIGNMENT_EXPIRED' using errcode = '42501'; end if;
        if command_action = 'assignment.accept' then
          if target_profile.operational_status <> 'active' then raise exception 'ACTIVE_REFEREE_PROFILE_REQUIRED' using errcode = '42501'; end if;
          if (match_snapshot ->> 'scheduleRevision')::bigint <> assignment.schedule_source_revision
             or (match_snapshot ->> 'scheduledStart')::timestamptz <> assignment.scheduled_start
             or (match_snapshot ->> 'scheduledEnd')::timestamptz <> assignment.scheduled_end then
            perform private.pachanga_referee_notify_v1(
              target_profile.user_id, 'referee_match_schedule_changed', 'Horario modificado',
              'El horario del partido ha cambiado. Solicita una propuesta actualizada.',
              '/perfil/arbitro?assignment=' || assignment.id::text,
              jsonb_build_object('assignmentId', assignment.id),
              'referee-schedule-changed:' || assignment.id::text || ':' || (match_snapshot ->> 'scheduleRevision')
            );
            raise exception 'MATCH_SCHEDULE_CHANGED' using errcode = 'PT409';
          end if;
          perform pg_advisory_xact_lock(hashtextextended('referee-assignment-profile:' || assignment.referee_profile_id::text, 0));
          perform pg_advisory_xact_lock(hashtextextended('referee-assignment-slot:' || assignment.canonical_match_id::text || ':' || assignment.assignment_role, 0));
          if assignment.replaces_assignment_id is not null then
            select * into replaced_assignment from public.pachanga_referee_assignments assignments
            where assignments.id = assignment.replaces_assignment_id for update;
            if not found or replaced_assignment.status <> 'confirmed'
               or replaced_assignment.replacement_pending_assignment_id <> assignment.id then
              raise exception 'REFEREE_REPLACEMENT_NOT_CURRENT' using errcode = 'PT409';
            end if;
            update public.pachanga_referee_assignments assignments set
              status = 'replaced', replaced_by_assignment_id = assignment.id,
              replacement_pending_assignment_id = null,
              revision = assignments.revision + 1,
              server_sequence = nextval('private.pachanga_referee_sequence')
            where assignments.id = replaced_assignment.id returning * into replaced_assignment;
          end if;
          if exists (
            select 1 from public.pachanga_referee_assignments existing
            where existing.referee_profile_id = assignment.referee_profile_id
              and existing.id <> assignment.id
              and existing.status in ('accepted', 'confirmed')
              and tstzrange(existing.scheduled_start, existing.scheduled_end, '[)')
                  && tstzrange(assignment.scheduled_start, assignment.scheduled_end, '[)')
          ) then raise exception 'REFEREE_ASSIGNMENT_TIME_CONFLICT' using errcode = 'PT409'; end if;
          if exists (
            select 1 from public.pachanga_referee_assignments existing
            where existing.canonical_match_id = assignment.canonical_match_id
              and existing.assignment_role = assignment.assignment_role
              and existing.id <> assignment.id
              and existing.status in ('accepted', 'confirmed', 'completed')
          ) then raise exception 'REFEREE_ASSIGNMENT_SLOT_TAKEN' using errcode = 'PT409'; end if;
          update public.pachanga_referee_assignments assignments set
            status = 'accepted', accepted_at = clock_timestamp(),
            revision = assignments.revision + 1,
            server_sequence = nextval('private.pachanga_referee_sequence')
          where assignments.id = assignment.id returning * into assignment;
          target_status := 'accepted';
          if replaced_assignment.id is not null then
            perform private.pachanga_referee_notify_v1(
              (select profiles.user_id from public.pachanga_referee_profiles profiles
               where profiles.id = replaced_assignment.referee_profile_id),
              'referee_assignment_replaced', 'Sustitución confirmada',
              'Tu asignación arbitral ha sido sustituida y se conserva en el historial.',
              '/perfil/arbitro?assignment=' || replaced_assignment.id::text,
              jsonb_build_object(
                'assignmentId', replaced_assignment.id,
                'replacementAssignmentId', assignment.id,
                'canonicalMatchId', assignment.canonical_match_id
              ),
              'referee-assignment-replaced:' || operation_id::text || ':' || replaced_assignment.referee_profile_id::text
            );
          end if;
        else
          update public.pachanga_referee_assignments assignments set
            status = 'declined', declined_at = clock_timestamp(),
            revision = assignments.revision + 1,
            server_sequence = nextval('private.pachanga_referee_sequence')
          where assignments.id = assignment.id returning * into assignment;
          target_status := 'declined';
          if assignment.replaces_assignment_id is not null then
            update public.pachanga_referee_assignments assignments set
              replacement_pending_assignment_id = null,
              revision = assignments.revision + 1,
              server_sequence = nextval('private.pachanga_referee_sequence')
            where assignments.id = assignment.replaces_assignment_id
              and assignments.replacement_pending_assignment_id = assignment.id;
          end if;
        end if;
        perform private.pachanga_referee_notify_v1(
          assignment.proposed_by,
          case when target_status = 'accepted' then 'referee_assignment_accepted' else 'referee_assignment_declined' end,
          case when target_status = 'accepted' then 'Arbitraje aceptado' else 'Arbitraje rechazado' end,
          'La propuesta de arbitraje ha cambiado de estado.',
          '/?mobile=partido', jsonb_build_object('assignmentId', assignment.id, 'canonicalMatchId', assignment.canonical_match_id),
          'referee-assignment-response:' || operation_id::text || ':' || assignment.proposed_by::text
        );
        invalidation_user_id := assignment.proposed_by;

      elsif command_action = 'assignment.confirm' then
        if assignment.status <> 'accepted' then raise exception 'REFEREE_ASSIGNMENT_NOT_ACCEPTED' using errcode = 'PT409'; end if;
        resolved_authority := private.pachanga_referee_assignment_authority_v1(
          match_snapshot, assignment.requester_kind, target_requester_id, actor_id
        );
        if target_profile.operational_status <> 'active' then raise exception 'ACTIVE_REFEREE_PROFILE_REQUIRED' using errcode = '42501'; end if;
        if (match_snapshot ->> 'scheduleRevision')::bigint <> assignment.schedule_source_revision
           or (match_snapshot ->> 'scheduledStart')::timestamptz <> assignment.scheduled_start
           or (match_snapshot ->> 'scheduledEnd')::timestamptz <> assignment.scheduled_end then
          raise exception 'MATCH_SCHEDULE_CHANGED' using errcode = 'PT409';
        end if;
        perform pg_advisory_xact_lock(hashtextextended('referee-assignment-profile:' || assignment.referee_profile_id::text, 0));
        perform pg_advisory_xact_lock(hashtextextended('referee-assignment-slot:' || assignment.canonical_match_id::text || ':' || assignment.assignment_role, 0));
        if exists (
          select 1 from public.pachanga_referee_assignments existing
          where existing.referee_profile_id = assignment.referee_profile_id
            and existing.id <> assignment.id and existing.status in ('accepted', 'confirmed')
            and tstzrange(existing.scheduled_start, existing.scheduled_end, '[)')
                && tstzrange(assignment.scheduled_start, assignment.scheduled_end, '[)')
        ) then raise exception 'REFEREE_ASSIGNMENT_TIME_CONFLICT' using errcode = 'PT409'; end if;
        update public.pachanga_referee_assignments assignments set
          status = 'confirmed', confirmed_at = clock_timestamp(), authority_used = resolved_authority,
          revision = assignments.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where assignments.id = assignment.id returning * into assignment;
        if assignment.replaces_assignment_id is not null then
          update public.pachanga_referee_assignments assignments set
            replacement_pending_assignment_id = null,
            revision = assignments.revision + 1,
            server_sequence = nextval('private.pachanga_referee_sequence')
          where assignments.id = assignment.replaces_assignment_id
            and assignments.replacement_pending_assignment_id = assignment.id;
        end if;
        perform private.pachanga_referee_notify_v1(
          target_profile.user_id, 'referee_assignment_confirmed', 'Arbitraje confirmado',
          'Tu asignación para el partido ha quedado confirmada.',
          '/perfil/arbitro?assignment=' || assignment.id::text,
          jsonb_build_object('assignmentId', assignment.id, 'canonicalMatchId', assignment.canonical_match_id),
          'referee-assignment-confirmed:' || operation_id::text || ':' || target_profile.user_id::text
        );
        invalidation_user_id := target_profile.user_id;

      elsif command_action = 'assignment.cancel' then
        if assignment.status not in ('proposed', 'accepted', 'confirmed') then
          raise exception 'REFEREE_ASSIGNMENT_NOT_CANCELLABLE' using errcode = 'PT409';
        end if;
        if target_profile.user_id <> actor_id then
          resolved_authority := private.pachanga_referee_assignment_authority_v1(
            match_snapshot, assignment.requester_kind, target_requester_id, actor_id
          );
        end if;
        update public.pachanga_referee_assignments assignments set
          status = 'cancelled', cancelled_at = clock_timestamp(), cancelled_by = actor_id,
          cancel_reason_code = left(coalesce(nullif(command_payload ->> 'reasonCode', ''), 'cancelled'), 80),
          cancel_reason_text = left(coalesce(command_payload ->> 'reasonText', ''), 800),
          revision = assignments.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where assignments.id = assignment.id returning * into assignment;
        perform private.pachanga_referee_notify_v1(
          case when target_profile.user_id = actor_id then assignment.proposed_by else target_profile.user_id end,
          'referee_assignment_cancelled', 'Arbitraje cancelado',
          'La asignación arbitral ha sido cancelada.',
          '/perfil/arbitro?assignment=' || assignment.id::text,
          jsonb_build_object('assignmentId', assignment.id, 'canonicalMatchId', assignment.canonical_match_id),
          'referee-assignment-cancelled:' || operation_id::text
        );
        invalidation_user_id := case when target_profile.user_id = actor_id then assignment.proposed_by else target_profile.user_id end;

      else
        if assignment.status <> 'confirmed' then raise exception 'REFEREE_ASSIGNMENT_NOT_REPLACEABLE' using errcode = 'PT409'; end if;
        resolved_authority := private.pachanga_referee_assignment_authority_v1(
          match_snapshot, assignment.requester_kind, target_requester_id, actor_id
        );
        target_profile_id := nullif(command_payload ->> 'newRefereeProfileId', '')::uuid;
        item_id := nullif(command_payload ->> 'newAssignmentId', '')::uuid;
        if item_id is null or exists (select 1 from public.pachanga_referee_assignments existing where existing.id = item_id) then
          raise exception 'INVALID_REPLACEMENT_ASSIGNMENT_ID' using errcode = '22023';
        end if;
        select * into target_profile from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id;
        if not found or target_profile.operational_status <> 'active' or not target_profile.available_for_assignments then
          raise exception 'REFEREE_PROFILE_NOT_ASSIGNABLE' using errcode = '42501';
        end if;
        target_deadline := coalesce(
          nullif(command_payload ->> 'responseDeadline', '')::timestamptz,
          clock_timestamp() + interval '72 hours'
        );
        if target_deadline <= clock_timestamp() or target_deadline > clock_timestamp() + interval '30 days' then
          raise exception 'INVALID_ASSIGNMENT_DEADLINE' using errcode = '22023';
        end if;
        insert into public.pachanga_referee_assignments(
          id, referee_profile_id, canonical_match_id, assignment_role, requester_kind,
          requester_team_id, requester_club_id, competition_id, source_kind,
          source_group_id, source_id, status, scheduled_start, scheduled_end, timezone,
          schedule_source_revision, proposed_by, authority_used, proposal_message,
          response_deadline, replaces_assignment_id, revision, server_sequence
        ) values (
          item_id, target_profile.id, assignment.canonical_match_id, assignment.assignment_role,
          assignment.requester_kind, assignment.requester_team_id, assignment.requester_club_id,
          assignment.competition_id, assignment.source_kind, assignment.source_group_id,
          assignment.source_id, 'proposed', assignment.scheduled_start, assignment.scheduled_end,
          assignment.timezone, assignment.schedule_source_revision, actor_id, resolved_authority,
          left(coalesce(command_payload ->> 'message', ''), 800),
          target_deadline,
          assignment.id, 1, nextval('private.pachanga_referee_sequence')
        ) returning * into replaced_assignment;
        update public.pachanga_referee_assignments assignments set
          replacement_pending_assignment_id = replaced_assignment.id,
          revision = assignments.revision + 1,
          server_sequence = nextval('private.pachanga_referee_sequence')
        where assignments.id = assignment.id returning * into assignment;
        perform private.pachanga_referee_notify_v1(
          target_profile.user_id, 'referee_assignment_replacement_proposed', 'Propuesta de sustitución',
          'Te han propuesto sustituir al árbitro de un partido.',
          '/perfil/arbitro?assignment=' || replaced_assignment.id::text,
          jsonb_build_object('assignmentId', replaced_assignment.id, 'canonicalMatchId', replaced_assignment.canonical_match_id),
          'referee-assignment-replacement:' || operation_id::text || ':' || target_profile.user_id::text
        );
        invalidation_user_id := target_profile.user_id;
        event_payload := jsonb_build_object('replacementAssignmentId', replaced_assignment.id);
      end if;
    end if;
    affected_profile_id := assignment.referee_profile_id;
    affected_club_id := assignment.requester_club_id;
    affected_canonical_match_id := assignment.canonical_match_id;
    invalidation_group_id := assignment.requester_team_id;
    confirmed_revision := assignment.revision;
    perform private.pachanga_referee_refresh_statistics_v1(assignment.referee_profile_id, 'incremental');
    if replaced_assignment.id is not null and replaced_assignment.referee_profile_id <> assignment.referee_profile_id then
      perform private.pachanga_referee_refresh_statistics_v1(replaced_assignment.referee_profile_id, 'incremental');
    end if;
    snapshot := jsonb_build_object(
      'assignment', jsonb_build_object(
        'id', assignment.id, 'refereeProfileId', assignment.referee_profile_id,
        'canonicalMatchId', assignment.canonical_match_id, 'assignmentRole', assignment.assignment_role,
        'requesterKind', assignment.requester_kind, 'requesterTeamId', assignment.requester_team_id,
        'requesterClubId', assignment.requester_club_id, 'competitionId', assignment.competition_id,
        'sourceKind', assignment.source_kind, 'sourceGroupId', assignment.source_group_id,
        'sourceId', assignment.source_id, 'status', assignment.status,
        'scheduledStart', assignment.scheduled_start, 'scheduledEnd', assignment.scheduled_end,
        'timezone', assignment.timezone, 'scheduleSourceRevision', assignment.schedule_source_revision,
        'responseDeadline', assignment.response_deadline, 'acceptedAt', assignment.accepted_at,
        'confirmedAt', assignment.confirmed_at, 'cancelledAt', assignment.cancelled_at,
        'completedAt', assignment.completed_at, 'replacementPendingAssignmentId', assignment.replacement_pending_assignment_id,
        'replacedByAssignmentId', assignment.replaced_by_assignment_id,
        'revision', assignment.revision, 'serverSequence', assignment.server_sequence
      ),
      'replacement', case when replaced_assignment.id is null then null else jsonb_build_object(
        'id', replaced_assignment.id, 'refereeProfileId', replaced_assignment.referee_profile_id,
        'status', replaced_assignment.status, 'revision', replaced_assignment.revision,
        'serverSequence', replaced_assignment.server_sequence
      ) end
    );
    event_payload := event_payload || jsonb_build_object(
      'status', assignment.status, 'assignmentRole', assignment.assignment_role,
      'scheduledStart', assignment.scheduled_start, 'scheduledEnd', assignment.scheduled_end,
      'scheduleSourceRevision', assignment.schedule_source_revision
    );
  else
    raise exception 'REFEREE_ACTION_NOT_SUPPORTED' using errcode = '0A000';
  end if;

  response := private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', command_action, aggregate_type,
    aggregate_id::text, request_hash, confirmed_revision, reason_code,
    event_payload, snapshot, affected_profile_id, affected_club_id,
    affected_canonical_match_id, invalidation_user_id, invalidation_group_id,
    invalidation_audience, client_metadata
  );
  if one_time_token is not null then
    return response || jsonb_build_object('oneTimeToken', one_time_token);
  end if;
  return response;
end;
$$;

revoke all on function public.command_pachanga_referee_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_referee_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function public.reconcile_pachanga_referee_assignment_v1(
  operation_id uuid,
  target_assignment_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_kind text := 'authenticated';
  request_hash text;
  replay jsonb;
  assignment public.pachanga_referee_assignments%rowtype;
  profile public.pachanga_referee_profiles%rowtype;
  match_snapshot jsonb;
  snapshot jsonb;
  response jsonb;
begin
  if operation_id is null or target_assignment_id is null or expected_revision is null then
    raise exception 'INVALID_OPERATION_ENVELOPE' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'REFEREE_RECONCILIATION_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  elsif not private.pachanga_referee_platform_can_v1(actor_id, 'referees.manage') then
    raise exception 'REFEREE_RECONCILIATION_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  perform private.pachanga_referee_assert_flags_v1(false, false, false, false, true);
  request_hash := private.pachanga_referee_request_hash_v1(
    'assignment.reconcile', target_assignment_id, expected_revision, '{}'::jsonb
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  select * into assignment from public.pachanga_referee_assignments assignments
  where assignments.id = target_assignment_id for update;
  if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if assignment.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  if assignment.status <> 'confirmed' then raise exception 'REFEREE_ASSIGNMENT_NOT_CONFIRMED' using errcode = 'PT409'; end if;
  match_snapshot := private.pachanga_referee_match_snapshot_v1(
    assignment.source_kind, assignment.source_group_id, assignment.source_id
  );
  if not coalesce((match_snapshot ->> 'concluded')::boolean, false) then
    raise exception 'REFEREE_CANONICAL_MATCH_NOT_CONCLUDED' using errcode = 'PT409';
  end if;
  if (match_snapshot ->> 'canonicalMatchId')::uuid <> assignment.canonical_match_id then
    raise exception 'REFEREE_CANONICAL_MATCH_CHANGED' using errcode = 'PT409';
  end if;
  update public.pachanga_referee_assignments assignments set
    status = 'completed', completed_at = clock_timestamp(),
    revision = assignments.revision + 1,
    server_sequence = nextval('private.pachanga_referee_sequence')
  where assignments.id = assignment.id returning * into assignment;
  select * into profile from public.pachanga_referee_profiles profiles where profiles.id = assignment.referee_profile_id;
  perform private.pachanga_referee_refresh_statistics_v1(assignment.referee_profile_id, 'incremental');
  perform private.pachanga_referee_notify_v1(
    profile.user_id, 'referee_assignment_completed', 'Partido arbitrado completado',
    'La asignación se ha conciliado con el partido canónico concluido.',
    '/perfil/arbitro?assignment=' || assignment.id::text,
    jsonb_build_object('assignmentId', assignment.id, 'canonicalMatchId', assignment.canonical_match_id),
    'referee-assignment-completed:' || operation_id::text || ':' || profile.user_id::text
  );
  snapshot := jsonb_build_object(
    'assignment', jsonb_build_object(
      'id', assignment.id, 'refereeProfileId', assignment.referee_profile_id,
      'canonicalMatchId', assignment.canonical_match_id, 'status', assignment.status,
      'completedAt', assignment.completed_at, 'revision', assignment.revision,
      'serverSequence', assignment.server_sequence
    ),
    'statistics', (select to_jsonb(stats) - 'referee_profile_id'
                   from public.pachanga_referee_statistics_snapshots stats
                   where stats.referee_profile_id = assignment.referee_profile_id)
  );
  response := private.pachanga_referee_store_command_v1(
    operation_id, actor_id, actor_kind, 'assignment.reconcile', 'referee_assignment',
    assignment.id::text, request_hash, assignment.revision, 'canonical_match_concluded',
    jsonb_build_object('status', 'completed', 'completedAt', assignment.completed_at),
    snapshot, assignment.referee_profile_id, assignment.requester_club_id,
    assignment.canonical_match_id, profile.user_id, assignment.requester_team_id,
    'private', client_metadata
  );
  return response;
end;
$$;

create or replace function public.get_pachanga_referee_relationship_invitation_v1(
  target_relationship_id uuid,
  invitation_token text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_email text;
  relationship public.pachanga_club_referee_relationships%rowtype;
  club public.pachanga_clubs%rowtype;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if length(trim(coalesce(invitation_token, ''))) <> 64 then
    raise exception 'REFEREE_INVITATION_TOKEN_INVALID' using errcode = '42501';
  end if;
  select lower(users.email) into actor_email from auth.users users
  where users.id = actor_id and users.email_confirmed_at is not null;
  select * into relationship from public.pachanga_club_referee_relationships relationships
  where relationships.id = target_relationship_id and relationships.status = 'invited';
  if not found or relationship.expires_at <= clock_timestamp() then
    raise exception 'REFEREE_INVITATION_NOT_AVAILABLE' using errcode = 'P0002';
  end if;
  if relationship.target_kind = 'registered_user' and relationship.target_user_id <> actor_id then
    raise exception 'REFEREE_INVITATION_TARGET_REQUIRED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from private.pachanga_referee_invitation_secrets secrets
    where secrets.relationship_id = relationship.id and secrets.consumed_at is null
      and secrets.token_hash = encode(extensions.digest(trim(invitation_token), 'sha256'), 'hex')
      and (relationship.target_kind <> 'email_target' or secrets.target_email_normalized = actor_email)
  ) then raise exception 'REFEREE_INVITATION_TOKEN_INVALID' using errcode = '42501'; end if;
  select * into club from public.pachanga_clubs clubs where clubs.id = relationship.club_id;
  return jsonb_build_object(
    'relationshipId', relationship.id,
    'club', jsonb_build_object('name', club.name, 'slug', club.slug, 'clubType', club.club_type),
    'relationshipType', relationship.relationship_type,
    'expiresAt', relationship.expires_at,
    'revision', relationship.revision,
    'profileRequired', private.pachanga_referee_profile_for_user_v1(actor_id) is null
  );
end;
$$;

create or replace function public.get_pachanga_referee_club_v1(target_club_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid()); selected_club public.pachanga_clubs%rowtype;
begin
  if actor_id is null or not private.pachanga_club_can_v1(target_club_id, actor_id, 'read') then
    raise exception 'CLUB_REFEREE_READ_REQUIRED' using errcode = '42501';
  end if;
  select * into selected_club from public.pachanga_clubs clubs where clubs.id = target_club_id;
  if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'club', jsonb_build_object(
      'id', selected_club.id, 'name', selected_club.name, 'slug', selected_club.slug,
      'operationalStatus', selected_club.operational_status,
      'verificationStatus', selected_club.verification_status
    ),
    'capabilities', jsonb_build_object(
      'read', true,
      'manage', private.pachanga_club_can_v1(target_club_id, actor_id, 'referee_manage')
    ),
    'relationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rows.id, 'refereeProfileId', rows.referee_profile_id,
        'referee', case when rows.profile_id is null then null else private.pachanga_referee_public_snapshot_v1(rows.profile_id) end,
        'targetKind', rows.target_kind, 'relationshipType', rows.relationship_type,
        'initiatedBy', rows.initiated_by, 'status', rows.status,
        'showOnRefereeProfile', rows.show_on_referee_profile,
        'showOnClubProfile', rows.show_on_club_profile,
        'startedAt', rows.started_at, 'endedAt', rows.ended_at,
        'expiresAt', rows.expires_at, 'revision', rows.revision,
        'serverSequence', rows.server_sequence
      ) order by rows.server_sequence desc, rows.id desc)
      from (
        select relationships.*, profiles.id as profile_id
        from public.pachanga_club_referee_relationships relationships
        left join public.pachanga_referee_profiles profiles on profiles.id = relationships.referee_profile_id
        where relationships.club_id = target_club_id
        order by relationships.server_sequence desc, relationships.id desc
        limit 200
      ) rows
    ), '[]'::jsonb),
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rows.id, 'refereeProfileId', rows.referee_profile_id,
        'refereeDisplayName', rows.referee_display_name,
        'canonicalMatchId', rows.canonical_match_id,
        'assignmentRole', rows.assignment_role, 'status', rows.status,
        'scheduledStart', rows.scheduled_start, 'scheduledEnd', rows.scheduled_end,
        'competitionId', rows.competition_id, 'revision', rows.revision,
        'serverSequence', rows.server_sequence
      ) order by rows.scheduled_start desc, rows.server_sequence desc, rows.id desc)
      from (
        select assignments.*, profiles.public_display_name_snapshot as referee_display_name
        from public.pachanga_referee_assignments assignments
        join public.pachanga_referee_profiles profiles on profiles.id = assignments.referee_profile_id
        where assignments.requester_club_id = target_club_id
        order by assignments.scheduled_start desc, assignments.server_sequence desc, assignments.id desc
        limit 200
      ) rows
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pachanga_referee_assignment_v1(target_assignment_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  assignment public.pachanga_referee_assignments%rowtype;
  profile public.pachanga_referee_profiles%rowtype;
  requester_id uuid;
  can_read boolean := false;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select * into assignment from public.pachanga_referee_assignments assignments where assignments.id = target_assignment_id;
  if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into profile from public.pachanga_referee_profiles profiles where profiles.id = assignment.referee_profile_id;
  requester_id := coalesce(assignment.requester_team_id, assignment.requester_club_id);
  can_read := profile.user_id = actor_id
    or private.pachanga_referee_platform_can_v1(actor_id, 'referees.read')
    or (assignment.requester_kind = 'TEAM' and exists (
      select 1 from public.pachanga_groups groups where groups.id = requester_id and groups.owner_id = actor_id
    ))
    or (assignment.requester_kind = 'CLUB' and private.pachanga_club_can_v1(requester_id, actor_id, 'read'));
  if not can_read then raise exception 'REFEREE_ASSIGNMENT_READ_REQUIRED' using errcode = '42501'; end if;
  return jsonb_build_object(
    'assignment', jsonb_build_object(
      'id', assignment.id, 'refereeProfileId', assignment.referee_profile_id,
      'refereeDisplayName', profile.public_display_name_snapshot,
      'canonicalMatchId', assignment.canonical_match_id,
      'assignmentRole', assignment.assignment_role,
      'requesterKind', assignment.requester_kind,
      'requesterTeamId', assignment.requester_team_id,
      'requesterClubId', assignment.requester_club_id,
      'competitionId', assignment.competition_id,
      'sourceKind', assignment.source_kind,
      'sourceGroupId', assignment.source_group_id,
      'sourceId', assignment.source_id,
      'status', assignment.status,
      'scheduledStart', assignment.scheduled_start,
      'scheduledEnd', assignment.scheduled_end,
      'timezone', assignment.timezone,
      'scheduleSourceRevision', assignment.schedule_source_revision,
      'proposalMessage', assignment.proposal_message,
      'responseDeadline', assignment.response_deadline,
      'acceptedAt', assignment.accepted_at,
      'confirmedAt', assignment.confirmed_at,
      'cancelledAt', assignment.cancelled_at,
      'completedAt', assignment.completed_at,
      'revision', assignment.revision,
      'serverSequence', assignment.server_sequence
    )
  );
end;
$$;

create or replace function public.purge_pachanga_referee_invitation_contacts_v1()
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare purged integer;
begin
  if not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'SERVICE_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  update private.pachanga_referee_invitation_secrets secrets set
    target_email_normalized = null,
    target_email_hash = null
  where secrets.retention_until <= clock_timestamp()
    and (secrets.target_email_normalized is not null or secrets.target_email_hash is not null);
  get diagnostics purged = row_count;
  return purged;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'public.reconcile_pachanga_referee_assignment_v1(uuid,uuid,bigint,jsonb)'::regprocedure,
    'public.get_pachanga_referee_relationship_invitation_v1(uuid,text)'::regprocedure,
    'public.get_pachanga_referee_club_v1(uuid)'::regprocedure,
    'public.get_pachanga_referee_assignment_v1(uuid)'::regprocedure,
    'public.purge_pachanga_referee_invitation_contacts_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', signature);
  end loop;
end;
$$;
grant execute on function public.reconcile_pachanga_referee_assignment_v1(uuid, uuid, bigint, jsonb)
  to authenticated, service_role;
grant execute on function public.get_pachanga_referee_relationship_invitation_v1(uuid, text)
  to authenticated;
grant execute on function public.get_pachanga_referee_club_v1(uuid)
  to authenticated, service_role;
grant execute on function public.get_pachanga_referee_assignment_v1(uuid)
  to authenticated, service_role;
grant execute on function public.purge_pachanga_referee_invitation_contacts_v1()
  to service_role;
