-- Official UI V3F: immutable command evidence, scoped invalidations and profile commands.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table if not exists private.pachanga_social_operation_receipts_v1 (
  operation_id uuid primary key,
  actor_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  aggregate_kind text not null,
  aggregate_id text not null,
  request_hash text not null,
  expected_revision bigint not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  check (char_length(request_hash) = 64),
  check (expected_revision >= 0 and confirmed_revision >= 0),
  check (server_sequence >= 1),
  check (jsonb_typeof(response) = 'object'),
  check (jsonb_typeof(client_metadata) = 'object')
);

create table if not exists private.pachanga_social_events_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete restrict,
  event_kind text not null,
  aggregate_kind text not null,
  aggregate_id text not null,
  aggregate_revision bigint not null,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, event_kind),
  check (aggregate_revision >= 0),
  check (server_sequence >= 1),
  check (jsonb_typeof(payload) = 'object')
);

create table if not exists public.pachanga_social_invalidations_v1 (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id text not null,
  revision bigint not null,
  audience_user_id uuid references auth.users(id) on delete cascade,
  audience_group_id uuid references public.pachanga_groups(id) on delete cascade,
  server_sequence bigint not null default nextval('private.pachanga_social_team_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  check (entity_type in ('profile','team','membership','roster','invitation','team_selection')),
  check (revision >= 0),
  check (server_sequence >= 1),
  check ((audience_user_id is not null)::integer + (audience_group_id is not null)::integer = 1)
);

create index if not exists pachanga_social_receipts_actor_idx
  on private.pachanga_social_operation_receipts_v1(actor_id, created_at desc, operation_id);
create unique index if not exists pachanga_social_receipts_sequence_idx
  on private.pachanga_social_operation_receipts_v1(server_sequence, operation_id);
create index if not exists pachanga_social_events_aggregate_idx
  on private.pachanga_social_events_v1(aggregate_kind, aggregate_id, server_sequence desc, id);
create unique index if not exists pachanga_social_events_sequence_idx
  on private.pachanga_social_events_v1(server_sequence, id);
create index if not exists pachanga_social_invalidations_user_idx
  on public.pachanga_social_invalidations_v1(audience_user_id, server_sequence desc, id)
  where audience_user_id is not null;
create index if not exists pachanga_social_invalidations_group_idx
  on public.pachanga_social_invalidations_v1(audience_group_id, server_sequence desc, id)
  where audience_group_id is not null;

alter table public.pachanga_social_invalidations_v1 enable row level security;

revoke all on table private.pachanga_social_operation_receipts_v1 from public, anon, authenticated;
revoke all on table private.pachanga_social_events_v1 from public, anon, authenticated;
revoke all on table public.pachanga_social_invalidations_v1 from public, anon, authenticated;
grant all on table private.pachanga_social_operation_receipts_v1 to service_role;
grant all on table private.pachanga_social_events_v1 to service_role;

create or replace function private.pachanga_social_immutable_evidence_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'SOCIAL_EVIDENCE_IMMUTABLE' using errcode = '55000';
end;
$$;

drop trigger if exists pachanga_social_receipts_immutable_v1
  on private.pachanga_social_operation_receipts_v1;
create trigger pachanga_social_receipts_immutable_v1
before update or delete on private.pachanga_social_operation_receipts_v1
for each row execute function private.pachanga_social_immutable_evidence_v1();

drop trigger if exists pachanga_social_events_immutable_v1
  on private.pachanga_social_events_v1;
create trigger pachanga_social_events_immutable_v1
before update or delete on private.pachanga_social_events_v1
for each row execute function private.pachanga_social_immutable_evidence_v1();

drop trigger if exists pachanga_social_profile_revisions_immutable_v1
  on private.pachanga_social_player_profile_revisions_v1;
create trigger pachanga_social_profile_revisions_immutable_v1
before update or delete on private.pachanga_social_player_profile_revisions_v1
for each row execute function private.pachanga_social_immutable_evidence_v1();

create or replace function private.pachanga_social_client_metadata_v1(target_metadata jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case when jsonb_typeof(target_metadata) <> 'object' then '{}'::jsonb
    else jsonb_strip_nulls(jsonb_build_object(
      'clientVersion', target_metadata -> 'clientVersion',
      'serviceWorkerVersion', target_metadata -> 'serviceWorkerVersion',
      'displayMode', target_metadata -> 'displayMode',
      'sessionId', target_metadata -> 'sessionId',
      'deviceId', target_metadata -> 'deviceId',
      'surface', target_metadata -> 'surface'
    )) end;
$$;

create or replace function private.pachanga_social_request_hash_v1(
  target_action text,
  target_aggregate_id text,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'action', target_action,
    'aggregateId', target_aggregate_id,
    'expectedRevision', target_expected_revision,
    'payload', coalesce(target_payload, '{}'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_social_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id text,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_social_operation_receipts_v1%rowtype;
begin
  select * into receipt
  from private.pachanga_social_operation_receipts_v1 receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id <> target_actor_id
     or receipt.action <> target_action
     or receipt.aggregate_id <> target_aggregate_id
     or receipt.request_hash <> target_request_hash then
    raise exception 'OPERATION_ID_REUSED' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

create or replace function private.pachanga_social_record_evidence_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_kind text,
  target_aggregate_id text,
  target_request_hash text,
  target_expected_revision bigint,
  target_confirmed_revision bigint,
  target_event_payload jsonb,
  target_response jsonb,
  target_client_metadata jsonb,
  target_server_sequence bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into private.pachanga_social_events_v1(
    operation_id, actor_id, event_kind, aggregate_kind, aggregate_id,
    aggregate_revision, payload, server_sequence
  ) values (
    target_operation_id, target_actor_id, target_action || '.confirmed',
    target_aggregate_kind, target_aggregate_id, target_confirmed_revision,
    coalesce(target_event_payload, '{}'::jsonb), target_server_sequence
  );
  insert into private.pachanga_social_operation_receipts_v1(
    operation_id, actor_id, action, aggregate_kind, aggregate_id, request_hash,
    expected_revision, confirmed_revision, server_sequence, response, client_metadata
  ) values (
    target_operation_id, target_actor_id, target_action, target_aggregate_kind,
    target_aggregate_id, target_request_hash, target_expected_revision,
    target_confirmed_revision, target_server_sequence, target_response,
    private.pachanga_social_client_metadata_v1(target_client_metadata)
  );
end;
$$;

create or replace function private.pachanga_social_profile_snapshot_v1(target_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'kind', 'SocialPlayerProfile',
    'displayName', profiles.display_name,
    'avatarRef', profiles.avatar_ref,
    'primaryPosition', profiles.primary_position,
    'secondaryPosition', profiles.secondary_position,
    'preferredModality', profiles.preferred_modality,
    'generalArea', profiles.general_area,
    'usualDays', to_jsonb(profiles.usual_days),
    'approximateTime', profiles.approximate_time,
    'shortBio', profiles.short_bio,
    'socialPreferences', profiles.social_preferences,
    'revision', profiles.revision,
    'confirmedRevision', profiles.revision,
    'serverSequence', profiles.server_sequence,
    'createdAt', profiles.created_at,
    'updatedAt', profiles.updated_at,
    'ratingAuthority', 'SEPARATE',
    'marketPublished', false
  )
  from public.pachanga_social_player_profiles_v1 profiles
  where profiles.user_id = target_user_id;
$$;

create or replace function public.get_my_pachanga_social_profile_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare enabled boolean;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select settings.social_profile_foundation_enabled into enabled
  from private.pachanga_social_team_settings_v1 settings where settings.singleton;
  if not coalesce(enabled, false) then return null; end if;
  return private.pachanga_social_profile_snapshot_v1(actor_id);
end;
$$;

create or replace function public.command_pachanga_social_profile_v1(
  action text,
  expected_revision bigint,
  operation_id uuid,
  payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare action_name text := lower(trim(coalesce(action, '')));
declare body jsonb := coalesce(payload, '{}'::jsonb);
declare settings private.pachanga_social_team_settings_v1%rowtype;
declare current_profile public.pachanga_social_player_profiles_v1%rowtype;
declare saved_profile public.pachanga_social_player_profiles_v1%rowtype;
declare allowed_keys text[];
declare safe_days text[];
declare safe_preferences jsonb;
declare request_hash text;
declare replay jsonb;
declare response jsonb;
declare sequence_value bigint;
declare avatar_value text;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'AUTHENTICATION_OPERATION_AND_REVISION_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(body) <> 'object' then raise exception 'INVALID_PROFILE_PAYLOAD' using errcode = '22023'; end if;
  if action_name not in ('profile.create','profile.update','profile.avatar.confirm','profile.availability.update') then
    raise exception 'UNSUPPORTED_PROFILE_ACTION' using errcode = '22023';
  end if;

  select * into settings from private.pachanga_social_team_settings_v1 where singleton;
  if not settings.social_profile_foundation_enabled
     or not settings.social_profile_independent_write_enabled then
    raise exception 'SOCIAL_PROFILE_WRITE_DISABLED' using errcode = '42501';
  end if;

  allowed_keys := case action_name
    when 'profile.avatar.confirm' then array['avatarRef']::text[]
    when 'profile.availability.update' then array['generalArea','usualDays','approximateTime']::text[]
    else array[
      'displayName','avatarRef','primaryPosition','secondaryPosition',
      'preferredModality','generalArea','usualDays','approximateTime',
      'shortBio','socialPreferences'
    ]::text[] end;
  if body - allowed_keys <> '{}'::jsonb then raise exception 'PROFILE_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;

  request_hash := private.pachanga_social_request_hash_v1(action_name, actor_id::text, expected_revision, body);
  perform pg_advisory_xact_lock(hashtextextended('social-operation:' || operation_id::text, 0));
  replay := private.pachanga_social_replay_v1(operation_id, actor_id, action_name, actor_id::text, request_hash);
  if replay is not null then return replay; end if;
  perform pg_advisory_xact_lock(hashtextextended('social-profile:' || actor_id::text, 0));

  select * into current_profile
  from public.pachanga_social_player_profiles_v1 profiles
  where profiles.user_id = actor_id
  for update;

  if action_name = 'profile.create' then
    if found then raise exception 'PROFILE_ALREADY_EXISTS' using errcode = 'PT409'; end if;
    if expected_revision <> 0 then raise exception 'STALE_PROFILE_REVISION' using errcode = 'PT409'; end if;
    if nullif(trim(body ->> 'displayName'), '') is null
       or nullif(trim(body ->> 'primaryPosition'), '') is null
       or nullif(trim(body ->> 'preferredModality'), '') is null then
      raise exception 'MINIMUM_PROFILE_REQUIRED' using errcode = '22023';
    end if;
  else
    if not found then raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
    if current_profile.revision <> expected_revision then raise exception 'STALE_PROFILE_REVISION' using errcode = 'PT409'; end if;
  end if;

  if body ? 'usualDays' then
    if jsonb_typeof(body -> 'usualDays') <> 'array' then raise exception 'INVALID_USUAL_DAYS' using errcode = '22023'; end if;
    select coalesce(array_agg(days.value order by days.ordering), '{}'::text[])
      into safe_days
    from (
      select value, min(ordinality) as ordering
      from jsonb_array_elements_text(body -> 'usualDays') with ordinality entries(value, ordinality)
      where value in ('L','M','X','J','V','S','D')
      group by value
    ) days;
    if cardinality(safe_days) <> jsonb_array_length(body -> 'usualDays') then
      raise exception 'INVALID_USUAL_DAYS' using errcode = '22023';
    end if;
  else
    safe_days := coalesce(current_profile.usual_days, '{}'::text[]);
  end if;

  if body ? 'socialPreferences' then
    if jsonb_typeof(body -> 'socialPreferences') <> 'object'
       or (body -> 'socialPreferences') - array['openToTeamInvites','openToMatchInvites']::text[] <> '{}'::jsonb then
      raise exception 'INVALID_SOCIAL_PREFERENCES' using errcode = '22023';
    end if;
    safe_preferences := jsonb_strip_nulls(jsonb_build_object(
      'openToTeamInvites', body #> '{socialPreferences,openToTeamInvites}',
      'openToMatchInvites', body #> '{socialPreferences,openToMatchInvites}'
    ));
  else
    safe_preferences := coalesce(current_profile.social_preferences, '{}'::jsonb);
  end if;

  avatar_value := case when body ? 'avatarRef' then nullif(trim(body ->> 'avatarRef'), '') else current_profile.avatar_ref end;
  if avatar_value is not null
     and avatar_value !~ '^https://'
     and avatar_value !~ '^/' then
    raise exception 'INVALID_AVATAR_REFERENCE' using errcode = '22023';
  end if;

  sequence_value := nextval('private.pachanga_social_team_sequence_v1');
  if action_name = 'profile.create' then
    insert into public.pachanga_social_player_profiles_v1(
      user_id, display_name, avatar_ref, primary_position, secondary_position,
      preferred_modality, general_area, usual_days, approximate_time,
      short_bio, social_preferences, revision, server_sequence
    ) values (
      actor_id, left(trim(body ->> 'displayName'), 80), avatar_value,
      body ->> 'primaryPosition', nullif(body ->> 'secondaryPosition',''),
      body ->> 'preferredModality', left(trim(coalesce(body ->> 'generalArea','')), 120),
      safe_days, coalesce(body ->> 'approximateTime',''),
      left(trim(coalesce(body ->> 'shortBio','')), 280), safe_preferences,
      1, sequence_value
    ) returning * into saved_profile;
  else
    update public.pachanga_social_player_profiles_v1 profiles set
      display_name = case when body ? 'displayName' then left(trim(body ->> 'displayName'),80) else profiles.display_name end,
      avatar_ref = avatar_value,
      primary_position = case when body ? 'primaryPosition' then body ->> 'primaryPosition' else profiles.primary_position end,
      secondary_position = case when body ? 'secondaryPosition' then nullif(body ->> 'secondaryPosition','') else profiles.secondary_position end,
      preferred_modality = case when body ? 'preferredModality' then body ->> 'preferredModality' else profiles.preferred_modality end,
      general_area = case when body ? 'generalArea' then left(trim(coalesce(body ->> 'generalArea','')),120) else profiles.general_area end,
      usual_days = safe_days,
      approximate_time = case when body ? 'approximateTime' then coalesce(body ->> 'approximateTime','') else profiles.approximate_time end,
      short_bio = case when body ? 'shortBio' then left(trim(coalesce(body ->> 'shortBio','')),280) else profiles.short_bio end,
      social_preferences = safe_preferences,
      revision = profiles.revision + 1,
      server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where profiles.user_id = actor_id
    returning * into saved_profile;
  end if;

  response := private.pachanga_social_profile_snapshot_v1(actor_id);
  insert into private.pachanga_social_player_profile_revisions_v1(
    user_id, revision, snapshot, operation_id, actor_id, server_sequence
  ) values (actor_id, saved_profile.revision, response, operation_id, actor_id, sequence_value);

  perform private.pachanga_social_record_evidence_v1(
    operation_id, actor_id, action_name, 'social_profile', actor_id::text,
    request_hash, expected_revision, saved_profile.revision,
    jsonb_build_object('changedFields', coalesce((select jsonb_agg(keys.key order by keys.key) from jsonb_object_keys(body) keys(key)), '[]'::jsonb)),
    response, client_metadata, sequence_value
  );
  insert into public.pachanga_social_invalidations_v1(
    entity_type, entity_id, revision, audience_user_id, server_sequence
  ) values ('profile', actor_id::text, saved_profile.revision, actor_id, sequence_value);
  return response;
end;
$$;

revoke all on function private.pachanga_social_immutable_evidence_v1() from public, anon, authenticated;
revoke all on function private.pachanga_social_client_metadata_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_social_request_hash_v1(text,text,bigint,jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_social_replay_v1(uuid,uuid,text,text,text) from public, anon, authenticated;
revoke all on function private.pachanga_social_record_evidence_v1(uuid,uuid,text,text,text,text,bigint,bigint,jsonb,jsonb,jsonb,bigint) from public, anon, authenticated;
revoke all on function private.pachanga_social_profile_snapshot_v1(uuid) from public, anon, authenticated;

revoke all on function public.get_my_pachanga_social_profile_v1() from public, anon;
grant execute on function public.get_my_pachanga_social_profile_v1() to authenticated, service_role;
revoke all on function public.command_pachanga_social_profile_v1(text,bigint,uuid,jsonb,jsonb) from public, anon;
grant execute on function public.command_pachanga_social_profile_v1(text,bigint,uuid,jsonb,jsonb) to authenticated, service_role;
