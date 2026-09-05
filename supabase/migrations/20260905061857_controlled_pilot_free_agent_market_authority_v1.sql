-- Controlled pilot: publish a no-team social profile to Mercado without
-- creating a player card or trusting a browser-owned sporting snapshot.

set lock_timeout = '5s';
set statement_timeout = '120s';

revoke insert, update, delete, truncate, references, trigger
  on table public.pachanga_market_profiles
  from public, anon, authenticated;
grant select on table public.pachanga_market_profiles to authenticated, service_role;

create table if not exists public.pachanga_market_invalidations_v1 (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null,
  active boolean not null,
  server_sequence bigint not null default nextval('private.pachanga_social_team_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  check (server_sequence >= 1)
);

create unique index if not exists pachanga_market_invalidations_sequence_idx
  on public.pachanga_market_invalidations_v1(server_sequence, id);
create index if not exists pachanga_market_invalidations_profile_idx
  on public.pachanga_market_invalidations_v1(profile_id, server_sequence desc, id);

alter table public.pachanga_market_invalidations_v1 enable row level security;
revoke all on table public.pachanga_market_invalidations_v1
  from public, anon, authenticated, service_role;
grant select on table public.pachanga_market_invalidations_v1
  to authenticated, service_role;

drop policy if exists pachanga_market_invalidations_registered_read_v1
  on public.pachanga_market_invalidations_v1;
create policy pachanga_market_invalidations_registered_read_v1
  on public.pachanga_market_invalidations_v1
  for select
  to authenticated
  using ((select public.is_registered_pachanga_user()));

create or replace function private.pachanga_emit_market_invalidation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_market_invalidations_v1(profile_id, active)
  values (
    case when tg_op = 'DELETE' then old.id else new.id end,
    case when tg_op = 'DELETE' then false else new.active end
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_emit_market_invalidation_v1()
  from public, anon, authenticated;
drop trigger if exists pachanga_market_profiles_invalidate_v1
  on public.pachanga_market_profiles;
create trigger pachanga_market_profiles_invalidate_v1
after insert or update or delete on public.pachanga_market_profiles
for each row execute function private.pachanga_emit_market_invalidation_v1();

create or replace function private.pachanga_sync_active_free_agent_market_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare availability_value text;
begin
  select concat_ws(' · ',
    nullif(string_agg(case days.day
      when 'L' then 'Lunes'
      when 'M' then 'Martes'
      when 'X' then 'Miércoles'
      when 'J' then 'Jueves'
      when 'V' then 'Viernes'
      when 'S' then 'Sábado'
      when 'D' then 'Domingo'
    end, ', ' order by days.ordinality), ''),
    nullif(new.approximate_time, '')
  ) into availability_value
  from unnest(new.usual_days) with ordinality as days(day, ordinality);

  update public.pachanga_market_profiles market_profiles
  set display_name = new.display_name,
      avatar = new.avatar_ref,
      position = new.primary_position,
      goalkeeper_only = new.primary_position = 'Portero',
      zones = case when nullif(trim(new.general_area), '') is null
        then '{}'::text[] else array[new.general_area] end,
      zones_geo = '[]'::jsonb,
      availability_text = coalesce(availability_value, ''),
      modalities = array[new.preferred_modality],
      open_to_guest = coalesce(lower(new.social_preferences ->> 'openToMatchInvites') <> 'false', true),
      open_to_group = coalesce(lower(new.social_preferences ->> 'openToTeamInvites') <> 'false', true),
      bio = new.short_bio,
      active = nullif(trim(new.general_area), '') is not null
        and cardinality(new.usual_days) > 0
        and nullif(trim(new.approximate_time), '') is not null
        and not exists (
          select 1 from public.pachanga_group_members memberships
          where memberships.user_id = new.user_id
        )
        and not private.pachanga_has_active_social_restriction_v1(new.user_id, 'public_market'),
      updated_at = clock_timestamp()
  where market_profiles.user_id = new.user_id
    and market_profiles.active
    and market_profiles.source_group_id is null
    and market_profiles.source_player_id = 'social-profile:' || new.user_id::text;
  return new;
end;
$$;

revoke all on function private.pachanga_sync_active_free_agent_market_v1()
  from public, anon, authenticated;
drop trigger if exists pachanga_social_profile_sync_free_agent_market_v1
  on public.pachanga_social_player_profiles_v1;
create trigger pachanga_social_profile_sync_free_agent_market_v1
after update of display_name, avatar_ref, primary_position, preferred_modality,
  general_area, usual_days, approximate_time, short_bio, social_preferences
on public.pachanga_social_player_profiles_v1
for each row execute function private.pachanga_sync_active_free_agent_market_v1();

create or replace function private.pachanga_pause_free_agent_market_on_membership_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  update public.pachanga_market_profiles market_profiles
  set active = false,
      updated_at = clock_timestamp()
  where market_profiles.user_id = new.user_id
    and market_profiles.active
    and market_profiles.source_group_id is null
    and market_profiles.source_player_id = 'social-profile:' || new.user_id::text;
  return new;
end;
$$;

revoke all on function private.pachanga_pause_free_agent_market_on_membership_v1()
  from public, anon, authenticated;
drop trigger if exists pachanga_membership_pause_free_agent_market_v1
  on public.pachanga_group_members;
create trigger pachanga_membership_pause_free_agent_market_v1
after insert on public.pachanga_group_members
for each row execute function private.pachanga_pause_free_agent_market_on_membership_v1();

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
    'marketPublished', exists (
      select 1
      from public.pachanga_market_profiles market_profiles
      where market_profiles.user_id = profiles.user_id
        and market_profiles.active
        and market_profiles.source_group_id is null
        and market_profiles.source_player_id = 'social-profile:' || profiles.user_id::text
    )
  )
  from public.pachanga_social_player_profiles_v1 profiles
  where profiles.user_id = target_user_id;
$$;

create or replace function public.command_pachanga_free_agent_market_v1(
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
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare action_name text := lower(trim(coalesce(action, '')));
declare body jsonb := coalesce(payload, '{}'::jsonb);
declare settings private.pachanga_social_team_settings_v1%rowtype;
declare current_profile public.pachanga_social_player_profiles_v1%rowtype;
declare player_profile public.pachanga_player_profiles%rowtype;
declare request_hash text;
declare replay jsonb;
declare response jsonb;
declare sequence_value bigint;
declare availability_value text;
declare rating_value numeric := 5;
declare appearances_value integer := 0;
declare goals_value integer := 0;
declare wins_value integer := 0;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'AUTHENTICATION_OPERATION_AND_REVISION_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501';
  end if;
  if action_name not in ('market.publish', 'market.unpublish') then
    raise exception 'UNSUPPORTED_FREE_AGENT_MARKET_ACTION' using errcode = '22023';
  end if;
  if jsonb_typeof(body) <> 'object' or body <> '{}'::jsonb then
    raise exception 'FREE_AGENT_MARKET_PAYLOAD_NOT_ALLOWED' using errcode = '22023';
  end if;

  select * into settings
  from private.pachanga_social_team_settings_v1
  where singleton;
  if not settings.social_profile_foundation_enabled
     or not settings.social_profile_independent_write_enabled then
    raise exception 'SOCIAL_PROFILE_WRITE_DISABLED' using errcode = '42501';
  end if;

  request_hash := private.pachanga_social_request_hash_v1(
    action_name,
    actor_id::text,
    expected_revision,
    body
  );
  perform pg_advisory_xact_lock(hashtextextended('social-operation:' || operation_id::text, 0));
  replay := private.pachanga_social_replay_v1(
    operation_id,
    actor_id,
    action_name,
    actor_id::text,
    request_hash
  );
  if replay is not null then return replay; end if;

  perform pg_advisory_xact_lock(hashtextextended('social-profile:' || actor_id::text, 0));
  select * into current_profile
  from public.pachanga_social_player_profiles_v1 profiles
  where profiles.user_id = actor_id
  for update;
  if not found then raise exception 'PROFILE_NOT_FOUND' using errcode = 'P0002'; end if;
  if current_profile.revision <> expected_revision then
    raise exception 'STALE_PROFILE_REVISION' using errcode = 'PT409';
  end if;
  if action_name = 'market.publish' and exists (
    select 1
    from public.pachanga_group_members memberships
    where memberships.user_id = actor_id
  ) then
    raise exception 'FREE_AGENT_MARKET_REQUIRES_NO_TEAM' using errcode = '42501';
  end if;

  if action_name = 'market.publish' then
    if nullif(trim(current_profile.general_area), '') is null
       or cardinality(current_profile.usual_days) = 0
       or nullif(trim(current_profile.approximate_time), '') is null then
      raise exception 'FREE_AGENT_MARKET_AVAILABILITY_REQUIRED' using errcode = '22023';
    end if;
    if private.pachanga_has_active_social_restriction_v1(actor_id, 'public_market') then
      raise exception 'SOCIAL_MARKET_RESTRICTED' using errcode = '42501';
    end if;

    select * into player_profile
    from public.pachanga_player_profiles player_profiles
    where player_profiles.user_id = actor_id;
    if found then
      rating_value := greatest(1::numeric, least(10::numeric,
        coalesce(player_profile.current_overall / 10, player_profile.rating, 5)
      ));
      appearances_value := case when coalesce(player_profile.stats ->> 'appearances', '') ~ '^\d+$'
        then greatest(0, (player_profile.stats ->> 'appearances')::integer) else 0 end;
      goals_value := case when coalesce(player_profile.stats ->> 'goals', '') ~ '^\d+$'
        then greatest(0, (player_profile.stats ->> 'goals')::integer) else 0 end;
      wins_value := case when coalesce(player_profile.stats ->> 'wins', '') ~ '^\d+$'
        then greatest(0, (player_profile.stats ->> 'wins')::integer) else 0 end;
    end if;

    select concat_ws(' · ',
      nullif(string_agg(case days.day
        when 'L' then 'Lunes'
        when 'M' then 'Martes'
        when 'X' then 'Miércoles'
        when 'J' then 'Jueves'
        when 'V' then 'Viernes'
        when 'S' then 'Sábado'
        when 'D' then 'Domingo'
      end, ', ' order by days.ordinality), ''),
      nullif(current_profile.approximate_time, '')
    ) into availability_value
    from unnest(current_profile.usual_days) with ordinality as days(day, ordinality);

    insert into public.pachanga_market_profiles(
      user_id,
      player_profile_id,
      source_group_id,
      source_player_id,
      display_name,
      group_name,
      avatar,
      avatar_offset_x,
      avatar_offset_y,
      birth_date,
      position,
      goalkeeper_only,
      media,
      appearances,
      goals,
      wins,
      zones,
      zones_geo,
      availability_text,
      modalities,
      open_to_guest,
      open_to_group,
      bio,
      active
    ) values (
      actor_id,
      player_profile.id,
      null,
      'social-profile:' || actor_id::text,
      current_profile.display_name,
      null,
      current_profile.avatar_ref,
      player_profile.avatar_offset_x,
      player_profile.avatar_offset_y,
      player_profile.birth_date,
      current_profile.primary_position,
      current_profile.primary_position = 'Portero',
      rating_value,
      appearances_value,
      goals_value,
      wins_value,
      array[current_profile.general_area],
      '[]'::jsonb,
      availability_value,
      array[current_profile.preferred_modality],
      coalesce(lower(current_profile.social_preferences ->> 'openToMatchInvites') <> 'false', true),
      coalesce(lower(current_profile.social_preferences ->> 'openToTeamInvites') <> 'false', true),
      current_profile.short_bio,
      true
    )
    on conflict (user_id) do update set
      player_profile_id = excluded.player_profile_id,
      source_group_id = null,
      source_player_id = excluded.source_player_id,
      display_name = excluded.display_name,
      group_name = null,
      avatar = excluded.avatar,
      avatar_offset_x = excluded.avatar_offset_x,
      avatar_offset_y = excluded.avatar_offset_y,
      birth_date = excluded.birth_date,
      position = excluded.position,
      goalkeeper_only = excluded.goalkeeper_only,
      media = excluded.media,
      appearances = excluded.appearances,
      goals = excluded.goals,
      wins = excluded.wins,
      zones = excluded.zones,
      zones_geo = excluded.zones_geo,
      availability_text = excluded.availability_text,
      modalities = excluded.modalities,
      open_to_guest = excluded.open_to_guest,
      open_to_group = excluded.open_to_group,
      bio = excluded.bio,
      active = true,
      updated_at = clock_timestamp();
  else
    update public.pachanga_market_profiles market_profiles
    set active = false,
        updated_at = clock_timestamp()
    where market_profiles.user_id = actor_id
      and market_profiles.source_group_id is null
      and market_profiles.source_player_id = 'social-profile:' || actor_id::text;
  end if;

  sequence_value := nextval('private.pachanga_social_team_sequence_v1');
  update public.pachanga_social_player_profiles_v1 profiles
  set revision = profiles.revision + 1,
      server_sequence = sequence_value,
      updated_at = clock_timestamp()
  where profiles.user_id = actor_id
  returning * into current_profile;

  response := private.pachanga_social_profile_snapshot_v1(actor_id);
  insert into private.pachanga_social_player_profile_revisions_v1(
    user_id,
    revision,
    snapshot,
    operation_id,
    actor_id,
    server_sequence
  ) values (
    actor_id,
    current_profile.revision,
    response,
    operation_id,
    actor_id,
    sequence_value
  );
  perform private.pachanga_social_record_evidence_v1(
    operation_id,
    actor_id,
    action_name,
    'social_profile',
    actor_id::text,
    request_hash,
    expected_revision,
    current_profile.revision,
    jsonb_build_object('marketPublished', action_name = 'market.publish'),
    response,
    client_metadata,
    sequence_value
  );
  insert into public.pachanga_social_invalidations_v1(
    entity_type,
    entity_id,
    revision,
    audience_user_id,
    server_sequence
  ) values (
    'profile',
    actor_id::text,
    current_profile.revision,
    actor_id,
    sequence_value
  );
  return response;
end;
$$;

revoke all on function private.pachanga_social_profile_snapshot_v1(uuid)
  from public, anon, authenticated;
revoke all on function public.command_pachanga_free_agent_market_v1(text,bigint,uuid,jsonb,jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_free_agent_market_v1(text,bigint,uuid,jsonb,jsonb)
  to authenticated, service_role;

comment on function public.command_pachanga_free_agent_market_v1(text,bigint,uuid,jsonb,jsonb) is
  'Publishes or pauses the authenticated no-team social profile in Mercado. The server derives every public field and records an idempotent revisioned receipt.';

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_market_invalidations_v1'
  ) then
    alter publication supabase_realtime
      add table public.pachanga_market_invalidations_v1;
  end if;
end;
$$;
