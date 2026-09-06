-- Age controls for public discovery and external team organization.
-- Internal team membership and match participation remain unchanged.
set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_social_player_profiles_v1 add column if not exists birth_date date;
update public.pachanga_social_player_profiles_v1 social set birth_date = player.birth_date
from public.pachanga_player_profiles player where player.user_id=social.user_id
  and social.birth_date is null and player.birth_date <= current_date;

create or replace function private.pachanga_market_birth_date_v1(target_user_id uuid)
returns date language sql stable security definer set search_path=pg_catalog as $$
 select coalesce(
   (select birth_date from public.pachanga_social_player_profiles_v1 where user_id=target_user_id),
   (select birth_date from public.pachanga_player_profiles where user_id=target_user_id)
 );
$$;
create or replace function private.pachanga_market_adult_v1(target_user_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select coalesce(private.pachanga_market_birth_date_v1(target_user_id)
   <= ((current_timestamp at time zone 'Europe/Madrid')::date - interval '18 years')::date,false);
$$;
create or replace function private.pachanga_assert_market_adult_v1(target_user_id uuid)
returns void language plpgsql stable security definer set search_path=pg_catalog as $$
begin
 if not private.pachanga_market_adult_v1(target_user_id) then
   raise exception 'MARKET_ADULT_REQUIRED' using errcode='42501';
 end if;
end;
$$;
revoke all on function private.pachanga_market_birth_date_v1(uuid) from public,anon,authenticated;
revoke all on function private.pachanga_market_adult_v1(uuid) from public,anon,authenticated;
revoke all on function private.pachanga_assert_market_adult_v1(uuid) from public,anon,authenticated;
grant execute on function private.pachanga_market_adult_v1(uuid) to authenticated;

create or replace function public.get_my_pachanga_market_age_access_v1()
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare actor uuid := auth.uid();
begin
 if actor is null or not public.is_registered_pachanga_user() then
   raise exception 'AUTHENTICATION_REQUIRED' using errcode='42501';
 end if;
 return jsonb_build_object('access',case
   when private.pachanga_market_birth_date_v1(actor) is null then 'missing'
   when private.pachanga_market_adult_v1(actor) then 'adult' else 'minor' end);
end;
$$;
revoke all on function public.get_my_pachanga_market_age_access_v1() from public,anon;
grant execute on function public.get_my_pachanga_market_age_access_v1() to authenticated,service_role;

create or replace function private.pachanga_social_profile_snapshot_v1(target_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'kind', 'SocialPlayerProfile',
    'birthDate', case when target_user_id = auth.uid() then profiles.birth_date end,
    'marketAgeAllowed', private.pachanga_market_adult_v1(target_user_id),
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
declare safe_birth_date date;
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
      'birthDate','displayName','avatarRef','primaryPosition','secondaryPosition',
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

  safe_birth_date := current_profile.birth_date;
  if body ? 'birthDate' then
    if coalesce(body->>'birthDate','') !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'VALID_BIRTH_DATE_REQUIRED' using errcode='22023';
    end if;
    begin safe_birth_date := (body->>'birthDate')::date;
    exception when others then raise exception 'VALID_BIRTH_DATE_REQUIRED' using errcode='22023'; end;
  end if;
  if action_name in ('profile.create','profile.update') and (safe_birth_date is null
    or safe_birth_date > (current_timestamp at time zone 'Europe/Madrid')::date
    or safe_birth_date < ((current_timestamp at time zone 'Europe/Madrid')::date - interval '120 years')::date) then
    raise exception 'VALID_BIRTH_DATE_REQUIRED' using errcode='22023';
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
      user_id, birth_date, display_name, avatar_ref, primary_position, secondary_position,
      preferred_modality, general_area, usual_days, approximate_time,
      short_bio, social_preferences, revision, server_sequence
    ) values (
      actor_id, safe_birth_date, left(trim(body ->> 'displayName'), 80), avatar_value,
      body ->> 'primaryPosition', nullif(body ->> 'secondaryPosition',''),
      body ->> 'preferredModality', left(trim(coalesce(body ->> 'generalArea','')), 120),
      safe_days, coalesce(body ->> 'approximateTime',''),
      left(trim(coalesce(body ->> 'shortBio','')), 280), safe_preferences,
      1, sequence_value
    ) returning * into saved_profile;
  else
    update public.pachanga_social_player_profiles_v1 profiles set
      birth_date = safe_birth_date,
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

CREATE OR REPLACE FUNCTION public.search_pachanga_open_matches_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  if auth.uid() is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  perform private.pachanga_reconcile_open_match_lifecycle_v1(null);

  return (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', open_matches.id,
        'source_payload_revision', open_matches.source_payload_revision,
        'group_name', open_matches.group_name,
        'title', open_matches.title,
        'date', open_matches.date,
        'date_text', open_matches.date_text,
        'day', open_matches.day,
        'modality', open_matches.modality,
        'zone', open_matches.zone,
        'lat', case when open_matches.lat is null then null else round(open_matches.lat::numeric, 2) end,
        'lng', case when open_matches.lng is null then null else round(open_matches.lng::numeric, 2) end,
        'field_name', open_matches.field_name,
        'field_cost', open_matches.field_cost,
        'price_per_player', open_matches.price_per_player,
        'target_players', open_matches.target_players,
        'confirmed_count', open_matches.confirmed_count,
        'open_slots', open_matches.open_slots,
        'min_media', open_matches.min_media,
        'max_media', open_matches.max_media,
        'positions', open_matches.positions,
        'requires_approval', open_matches.requires_approval,
        'guests_pay', open_matches.guests_pay,
        'group_level', open_matches.group_level,
        'active', open_matches.active
      ) order by open_matches.date asc, open_matches.id asc
    ), '[]'::jsonb)
    from public.pachanga_open_matches open_matches
    where (
      open_matches.active and private.pachanga_team_has_adult_admin_v1(open_matches.source_group_id) and open_matches.open_slots > 0 and open_matches.date > clock_timestamp()
    ) or exists (
      select 1 from public.pachanga_open_match_requests own_request
      where own_request.open_match_id = open_matches.id
        and own_request.requester_user_id = auth.uid()
        and own_request.status = 'accepted'
    )
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.search_pachanga_challengeable_teams(requesting_group_id uuid, target_zone_query text DEFAULT NULL::text, target_zone_lat double precision DEFAULT NULL::double precision, target_zone_lng double precision DEFAULT NULL::double precision, target_max_distance_km integer DEFAULT NULL::integer, target_min_team_level numeric DEFAULT NULL::numeric, target_max_team_level numeric DEFAULT NULL::numeric, target_weekday smallint DEFAULT NULL::smallint, target_start_time time without time zone DEFAULT NULL::time without time zone, target_end_time time without time zone DEFAULT NULL::time without time zone, target_modality text DEFAULT NULL::text, target_page integer DEFAULT 1, target_page_size integer DEFAULT 12)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  candidate record;
  current_search_state public.pachanga_challengeable_team_search_state%rowtype;
  has_more boolean := false;
  item_count integer := 0;
  items jsonb := '[]'::jsonb;
  requester_level numeric;
  safe_page integer := coalesce(target_page, 1);
  safe_page_size integer := coalesce(target_page_size, 12);
  safe_zone_query text := case
    when target_zone_lat is null then nullif(trim(target_zone_query), '')
    else null
  end;
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_member(requesting_group_id) then
    raise exception 'Group membership required';
  end if;
  if safe_page < 1 or safe_page > 1000 or safe_page_size < 1 or safe_page_size > 24 then
    raise exception 'Invalid pagination';
  end if;
  if char_length(coalesce(safe_zone_query, '')) > 120 then raise exception 'Zone query is too long'; end if;
  if (target_zone_lat is null) <> (target_zone_lng is null)
    or (target_zone_lat is not null and target_zone_lat not between -90 and 90)
    or (target_zone_lng is not null and target_zone_lng not between -180 and 180) then
    raise exception 'Search coordinates are invalid';
  end if;
  if target_max_distance_km is not null and (
    target_zone_lat is null or target_max_distance_km < 1 or target_max_distance_km > 100
  ) then
    raise exception 'Distance filter requires a zone and 1 to 100 km';
  end if;
  if (target_min_team_level is not null and target_min_team_level not between 0 and 100)
    or (target_max_team_level is not null and target_max_team_level not between 0 and 100)
    or (
      target_min_team_level is not null
      and target_max_team_level is not null
      and target_min_team_level > target_max_team_level
    ) then
    raise exception 'Team level filter is invalid';
  end if;
  if target_weekday is not null and target_weekday not between 1 and 7 then raise exception 'Invalid weekday'; end if;
  if (target_start_time is null) <> (target_end_time is null)
    or (
      target_start_time is not null
      and (target_weekday is null or target_end_time <= target_start_time)
    ) then
    raise exception 'Time filter requires a day and a valid range';
  end if;
  if target_modality is not null and target_modality not in ('sala', 'futbol7', 'futbol11') then
    raise exception 'Invalid modality';
  end if;

  perform 1
  from public.pachanga_challengeable_team_search_state states
  where states.id
  for share;

  select * into current_search_state
  from public.pachanga_challengeable_team_search_state states
  where states.id;

  select levels.stable_level into requester_level
  from public.pachanga_team_level_read_models levels
  where levels.group_id = requesting_group_id;

  for candidate in
    with candidates as (
      select
        profiles.*,
        groups.name as group_name,
        levels.stable_level as team_level,
        case
          when target_zone_lat is null or profiles.zone_lat is null then null
          else 6371.0 * 2.0 * asin(sqrt(least(1.0,
            power(sin(radians(profiles.zone_lat - target_zone_lat) / 2.0), 2)
            + cos(radians(target_zone_lat)) * cos(radians(profiles.zone_lat))
              * power(sin(radians(profiles.zone_lng - target_zone_lng) / 2.0), 2)
          )))
        end as distance_km,
        (
          select coalesce(jsonb_agg(
            jsonb_build_object(
              'day', slots.weekday,
              'start', to_char(slots.starts_at, 'HH24:MI'),
              'end', to_char(slots.ends_at, 'HH24:MI')
            ) order by slots.weekday, slots.starts_at, slots.ends_at
          ), '[]'::jsonb)
          from public.pachanga_challengeable_team_availability slots
          where slots.group_id = profiles.group_id
        ) as availability
      from public.pachanga_challengeable_team_profiles profiles
      join public.pachanga_groups groups on groups.id = profiles.group_id
      left join public.pachanga_team_level_read_models levels on levels.group_id = profiles.group_id
      where profiles.enabled
        and private.pachanga_team_has_adult_admin_v1(profiles.group_id)
        and profiles.group_id <> requesting_group_id
        and (requester_level is null or requester_level between profiles.min_opponent_level and profiles.max_opponent_level)
        and (target_min_team_level is null or levels.stable_level >= target_min_team_level)
        and (target_max_team_level is null or levels.stable_level <= target_max_team_level)
        and (target_modality is null or target_modality = any(profiles.modalities))
        and (
          safe_zone_query is null
          or lower(profiles.zone_label) like '%' || lower(safe_zone_query) || '%'
        )
        and (
          target_weekday is null
          or exists (
            select 1
            from public.pachanga_challengeable_team_availability slots
            where slots.group_id = profiles.group_id
              and slots.weekday = target_weekday
              and (
                target_start_time is null
                or slots.starts_at <= target_start_time and slots.ends_at >= target_end_time
              )
          )
        )
    )
    select *
    from candidates
    where target_zone_lat is null
      or (
        distance_km <= travel_radius_km
        and (target_max_distance_km is null or distance_km <= target_max_distance_km)
      )
    order by
      distance_km asc nulls last,
      abs(coalesce(team_level, 50) - coalesce(requester_level, team_level, 50)),
      lower(group_name),
      group_id
    offset (safe_page - 1) * safe_page_size
    limit safe_page_size + 1
  loop
    item_count := item_count + 1;
    if item_count > safe_page_size then
      has_more := true;
    else
      items := items || jsonb_build_array(jsonb_build_object(
        'groupId', candidate.group_id,
        'name', candidate.group_name,
        'zoneLabel', candidate.zone_label,
        'travelRadiusKm', candidate.travel_radius_km,
        'teamLevel', candidate.team_level,
        'minOpponentLevel', candidate.min_opponent_level,
        'maxOpponentLevel', candidate.max_opponent_level,
        'modalities', to_jsonb(candidate.modalities),
        'availability', candidate.availability,
        'distanceKm', case when candidate.distance_km is null then null else round(candidate.distance_km::numeric, 1) end,
        'levelCompatibility', case
          when requester_level is null or candidate.team_level is null then 'unknown'
          else 'compatible'
        end,
        'profileRevision', candidate.revision,
        'updatedAt', candidate.updated_at
      ));
    end if;
  end loop;

  return jsonb_build_object(
    'items', items,
    'page', safe_page,
    'pageSize', safe_page_size,
    'hasMore', has_more,
    'requestingGroupId', requesting_group_id,
    'requesterLevel', requester_level,
    'searchRevision', coalesce(current_search_state.revision, 0),
    'confirmedRevision', coalesce(current_search_state.revision, 0),
    'serverSequence', coalesce(current_search_state.server_sequence, 0),
    'updatedAt', current_search_state.updated_at
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.lookup_pachanga_challengeable_team_for_challenge(requesting_group_id uuid, opponent_group_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  opponent public.pachanga_groups%rowtype;
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(requesting_group_id) then
    raise exception 'Only group admins can prepare public challenges';
  end if;
  if opponent_group_id is null or opponent_group_id = requesting_group_id then
    raise exception 'Invalid rival';
  end if;

  select groups.* into opponent
  from public.pachanga_groups groups
  join public.pachanga_challengeable_team_profiles profiles on profiles.group_id = groups.id
  where groups.id = opponent_group_id
    and profiles.enabled and private.pachanga_team_has_adult_admin_v1(profiles.group_id);
  if not found then raise exception 'Public rival is no longer available'; end if;

  return jsonb_build_object(
    'groupId', opponent.id,
    'name', opponent.name,
    'teamCode', opponent.team_code
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.sync_pachanga_open_match_authoritative_v2(target_group_id uuid, target_match_id text, match_patch jsonb, operation_id uuid, expected_revision bigint, client_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '750ms'
AS $function$
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  return public.sync_pachanga_open_match_authoritative_v2_impl(
    target_group_id, target_match_id, match_patch, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$function$;


CREATE OR REPLACE FUNCTION public.request_pachanga_open_match_authoritative_v2(target_open_match_id uuid, operation_id uuid, expected_match_revision bigint, client_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '750ms'
AS $function$
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  return public.request_pachanga_open_match_authoritative_v2_impl(
    target_open_match_id, operation_id, expected_match_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$function$;


CREATE OR REPLACE FUNCTION public.create_pachanga_team_challenge_authoritative(target_group_id uuid, opponent_team_code text, target_scheduled_at timestamp with time zone, target_modality text, target_field_name text, target_field_address text, target_field_place_id text, target_field_maps_url text, target_message text, operation_id uuid, expected_revision bigint, client_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  opponent_group_id uuid;
  current_revision bigint;
  challenge_id uuid;
  event_sequence bigint;
  replay jsonb;
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('team-social-operation:' || operation_id::text, 0));
  replay := public.pachanga_team_social_operation_replay(
    target_group_id, operation_id, auth.uid(), 'team_challenge_created'
  );
  if replay is not null then return replay; end if;

  select groups.id into opponent_group_id
  from public.pachanga_groups groups
  where upper(groups.team_code) = upper(trim(opponent_team_code))
    and groups.id <> target_group_id
  limit 1;
  if opponent_group_id is null then raise exception 'Rival not found'; end if;
  if target_scheduled_at is null or target_scheduled_at <= clock_timestamp() then
    raise exception 'Challenge date must be in the future';
  end if;
  if target_modality not in ('sala', 'futbol7', 'futbol11') then raise exception 'Invalid modality'; end if;
  if nullif(trim(target_field_name), '') is null or nullif(trim(target_field_address), '') is null then
    raise exception 'Field name and address are required';
  end if;
  if char_length(trim(target_field_name)) > 160 or char_length(trim(target_field_address)) > 300
    or char_length(coalesce(target_field_place_id, '')) > 300
    or char_length(coalesce(target_field_maps_url, '')) > 800
    or char_length(coalesce(target_message, '')) > 1200 then
    raise exception 'Challenge text is too long';
  end if;
  if nullif(trim(coalesce(target_field_maps_url, '')), '') is not null
    and trim(target_field_maps_url) !~* '^https://(www\.)?(google\.[a-z.]+/maps|maps\.app\.goo\.gl)/' then
    raise exception 'Google Maps link is invalid';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'team-social-pair:' || least(target_group_id::text, opponent_group_id::text)
      || ':' || greatest(target_group_id::text, opponent_group_id::text), 0
  ));
  perform 1 from public.pachanga_team_social_state states
  where states.group_id in (target_group_id, opponent_group_id)
  order by states.group_id
  for update;
  select states.revision into current_revision
  from public.pachanga_team_social_state states
  where states.group_id = target_group_id;
  if current_revision is distinct from expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  insert into public.pachanga_team_challenges(
    sender_group_id,
    receiver_group_id,
    scheduled_at,
    modality,
    field_name,
    field_address,
    field_place_id,
    field_maps_url,
    message,
    last_proposed_by_group_id,
    created_by,
    updated_by
  ) values (
    target_group_id,
    opponent_group_id,
    target_scheduled_at,
    target_modality,
    left(trim(target_field_name), 160),
    left(trim(target_field_address), 300),
    nullif(left(trim(coalesce(target_field_place_id, '')), 300), ''),
    nullif(left(trim(coalesce(target_field_maps_url, '')), 800), ''),
    nullif(left(trim(coalesce(target_message, '')), 1200), ''),
    target_group_id,
    auth.uid(),
    auth.uid()
  ) returning id into challenge_id;

  insert into public.pachanga_team_challenge_events(
    challenge_id, operation_id, actor_user_id, actor_group_id,
    event_type, challenge_revision, snapshot
  ) values (
    challenge_id, operation_id, auth.uid(), target_group_id,
    'created', 1, public.pachanga_team_challenge_snapshot(challenge_id, target_group_id)
  ) returning server_sequence into event_sequence;

  perform public.pachanga_team_social_bump(array[target_group_id, opponent_group_id], event_sequence);
  return public.pachanga_team_social_store_response(
    target_group_id, operation_id, 'team_challenge_created', expected_revision,
    event_sequence, client_metadata
  );
end;
$function$;


CREATE OR REPLACE FUNCTION public.respond_pachanga_team_challenge_authoritative(target_group_id uuid, target_challenge_id uuid, target_action text, target_scheduled_at timestamp with time zone, target_modality text, target_field_name text, target_field_address text, target_field_place_id text, target_field_maps_url text, target_message text, operation_id uuid, expected_revision bigint, client_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '750ms'
AS $function$
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication required';
  end if;
  if not exists (
    select 1 from public.pachanga_team_challenges challenges
    where challenges.id = target_challenge_id
      and target_group_id in (challenges.sender_group_id, challenges.receiver_group_id)
  ) then raise exception 'Challenge not found'; end if;

  if private.pachanga_expire_team_challenge_v1(target_challenge_id, null) then
    raise exception 'Challenge expired. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  return public.respond_pachanga_team_challenge_without_expiry_v1(
    target_group_id, target_challenge_id, target_action, target_scheduled_at,
    target_modality, target_field_name, target_field_address, target_field_place_id,
    target_field_maps_url, target_message, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$function$;


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
  if lower(trim(action)) = 'market.publish' then
    perform private.pachanga_assert_market_adult_v1(auth.uid());
  end if;
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


-- A team can use external discovery when it has an adult administrator.
-- The creator need not be adult; existing membership authorization is preserved.
create or replace function private.pachanga_team_has_adult_admin_v1(target_group uuid)
returns boolean language sql stable security definer set search_path=pg_catalog as $$
 select exists(select 1 from public.pachanga_group_members members
   where members.group_id=target_group and members.role in ('owner','admin')
     and private.pachanga_market_adult_v1(members.user_id))
   or exists(select 1 from public.pachanga_groups groups
     where groups.id=target_group and private.pachanga_market_adult_v1(groups.owner_id));
$$;
revoke all on function private.pachanga_team_has_adult_admin_v1(uuid) from public,anon,authenticated;
grant execute on function private.pachanga_team_has_adult_admin_v1(uuid) to authenticated;

create policy pachanga_market_age_read_v1 on public.pachanga_market_profiles
as restrictive for select to authenticated using (
 private.pachanga_market_adult_v1((select auth.uid())) and private.pachanga_market_adult_v1(user_id)
);
create policy pachanga_challengeable_age_read_v1 on public.pachanga_challengeable_team_profiles
as restrictive for select to authenticated using (
 private.pachanga_market_adult_v1((select auth.uid())) and private.pachanga_team_has_adult_admin_v1(group_id)
);

create or replace function private.pachanga_market_age_visibility_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if not private.pachanga_market_adult_v1(new.user_id) then
  new.active:=false; new.open_to_guest:=false; new.open_to_group:=false;
 end if;
 return new;
end;
$$;
revoke all on function private.pachanga_market_age_visibility_v1() from public,anon,authenticated;
create trigger pachanga_market_age_visibility_v1 before insert or update on public.pachanga_market_profiles
for each row execute function private.pachanga_market_age_visibility_v1();

create or replace function private.pachanga_market_age_request_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if new.status in ('pending','accepted') and (tg_op='INSERT' or old.status is distinct from new.status) then
  perform private.pachanga_assert_market_adult_v1(new.requester_user_id);
 end if;
 return new;
end;
$$;
revoke all on function private.pachanga_market_age_request_v1() from public,anon,authenticated;
create trigger pachanga_market_age_request_v1 before insert or update of status on public.pachanga_open_match_requests
for each row execute function private.pachanga_market_age_request_v1();

create or replace function private.pachanga_market_age_invitation_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if new.status in ('pending','accepted') and (tg_op='INSERT' or old.status is distinct from new.status) then
  perform private.pachanga_assert_market_adult_v1(new.invitee_user_id);
  if tg_op='INSERT' then perform private.pachanga_assert_market_adult_v1(new.inviter_user_id); end if;
 end if;
 return new;
end;
$$;
revoke all on function private.pachanga_market_age_invitation_v1() from public,anon,authenticated;
create trigger pachanga_market_age_invitation_v1 before insert or update of status on public.pachanga_match_invitations
for each row execute function private.pachanga_market_age_invitation_v1();

create or replace function private.pachanga_challenge_age_action_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if (tg_op='INSERT' or (new.status is distinct from old.status and new.status in ('accepted','changes_proposed','proposed')))
   and (not private.pachanga_team_has_adult_admin_v1(new.sender_group_id)
     or not private.pachanga_team_has_adult_admin_v1(new.receiver_group_id)) then
  raise exception 'MARKET_ADULT_REQUIRED: adult team administrator required' using errcode='42501';
 end if;
 if tg_op='INSERT' then perform private.pachanga_assert_market_adult_v1(new.created_by);
 elsif new.status is distinct from old.status and new.status in ('accepted','changes_proposed','proposed') then
  perform private.pachanga_assert_market_adult_v1(new.updated_by);
 end if;
 return new;
end;
$$;
revoke all on function private.pachanga_challenge_age_action_v1() from public,anon,authenticated;
create trigger pachanga_challenge_age_action_v1 before insert or update on public.pachanga_team_challenges
for each row execute function private.pachanga_challenge_age_action_v1();

create or replace function private.pachanga_team_listing_age_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
begin
 if tg_table_name='pachanga_challengeable_team_profiles' then
  if new.enabled and (tg_op='INSERT' or not old.enabled or auth.uid() is not null) then
   perform private.pachanga_assert_market_adult_v1(new.updated_by);
  end if;
  if not private.pachanga_team_has_adult_admin_v1(new.group_id) then new.enabled:=false; end if;
 else
  if new.active and (tg_op='INSERT' or not old.active) then
   perform private.pachanga_assert_market_adult_v1(coalesce(auth.uid(),new.created_by));
  end if;
  if not private.pachanga_team_has_adult_admin_v1(new.source_group_id) then new.active:=false; end if;
 end if;
 return new;
end;
$$;
revoke all on function private.pachanga_team_listing_age_v1() from public,anon,authenticated;
create trigger pachanga_challengeable_listing_age_v1 before insert or update on public.pachanga_challengeable_team_profiles
for each row execute function private.pachanga_team_listing_age_v1();
create trigger pachanga_open_match_listing_age_v1 before insert or update on public.pachanga_open_matches
for each row execute function private.pachanga_team_listing_age_v1();

-- Revoke discoverability when the birth date or administrator membership changes.
-- Do not delete matches, remove players or change accepted team participation.
create or replace function private.pachanga_recheck_age_visibility_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
declare target_user uuid;
declare changed_group uuid;
declare affected_groups uuid[];
begin
 if tg_op='DELETE' then target_user:=old.user_id; else target_user:=new.user_id; end if;
 if tg_table_name='pachanga_group_members' then
  if tg_op='DELETE' then changed_group:=old.group_id; else changed_group:=new.group_id; end if;
 end if;
 select array_agg(id) into affected_groups from (
  select group_id as id from public.pachanga_group_members where user_id=target_user
  union select id from public.pachanga_groups where owner_id=target_user
  union select changed_group where changed_group is not null
 ) groups;
 update public.pachanga_market_profiles set active=false,open_to_guest=false,open_to_group=false
  where user_id=target_user and active and not private.pachanga_market_adult_v1(target_user);
 update public.pachanga_challengeable_team_profiles set enabled=false
  where group_id=any(affected_groups) and enabled and not private.pachanga_team_has_adult_admin_v1(group_id);
 update public.pachanga_open_matches set active=false
  where source_group_id=any(affected_groups) and active and not private.pachanga_team_has_adult_admin_v1(source_group_id);
 return null;
end;
$$;
revoke all on function private.pachanga_recheck_age_visibility_v1() from public,anon,authenticated;
create trigger pachanga_social_birth_age_visibility_v1 after insert or update of birth_date on public.pachanga_social_player_profiles_v1
for each row execute function private.pachanga_recheck_age_visibility_v1();
create trigger pachanga_player_birth_age_visibility_v1 after insert or update of birth_date on public.pachanga_player_profiles
for each row execute function private.pachanga_recheck_age_visibility_v1();
create trigger pachanga_admin_age_visibility_v1 after insert or update of role or delete on public.pachanga_group_members
for each row execute function private.pachanga_recheck_age_visibility_v1();

update public.pachanga_market_profiles set active=false,open_to_guest=false,open_to_group=false
where active and not private.pachanga_market_adult_v1(user_id);
update public.pachanga_challengeable_team_profiles set enabled=false
where enabled and not private.pachanga_team_has_adult_admin_v1(group_id);
update public.pachanga_open_matches set active=false
where active and not private.pachanga_team_has_adult_admin_v1(source_group_id);

-- Reviewing applications is an external organization action.
CREATE OR REPLACE FUNCTION public.review_pachanga_open_match_request_authoritative_v2(target_group_id uuid, target_request_id uuid, next_status text, operation_id uuid, expected_revision bigint, client_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
 SET lock_timeout TO '750ms'
AS $function$
begin
  perform private.pachanga_assert_market_adult_v1(auth.uid());
  return public.review_pachanga_open_match_request_authoritative_v2_impl(
    target_group_id, target_request_id, next_status, operation_id, expected_revision, client_metadata
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  return public.pachanga_translate_http_conflict_v2(sqlerrm);
end;
$function$;
