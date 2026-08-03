create or replace function public.upsert_pachanga_player_profile_from_player(
  target_group_id uuid,
  target_player_id text,
  player_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  global_profile_id uuid;
  owner_id uuid;
  safe_avatar_offset_x numeric;
  safe_avatar_offset_y numeric;
  safe_birth_date date;
  safe_imported_rating numeric;
  safe_imported_rating_at timestamptz;
  safe_market_modalities text[];
  safe_rating numeric;
  safe_stats jsonb;
begin
  if coalesce(player_payload ->> 'ownerUserId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;

  owner_id := (player_payload ->> 'ownerUserId')::uuid;

  safe_avatar_offset_x := case
    when coalesce(player_payload ->> 'avatarOffsetX', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then least(100::numeric, greatest(0::numeric, (player_payload ->> 'avatarOffsetX')::numeric))
    else null
  end;
  safe_avatar_offset_y := case
    when coalesce(player_payload ->> 'avatarOffsetY', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then least(100::numeric, greatest(0::numeric, (player_payload ->> 'avatarOffsetY')::numeric))
    else null
  end;
  safe_birth_date := case
    when coalesce(player_payload ->> 'birthDate', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (player_payload ->> 'birthDate')::date
    else null
  end;
  safe_imported_rating := case
    when coalesce(player_payload ->> 'importedRating', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then greatest(1::numeric, least(10::numeric, (player_payload ->> 'importedRating')::numeric))
    else null
  end;
  safe_imported_rating_at := case
    when coalesce(player_payload ->> 'importedRatingAt', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' then (player_payload ->> 'importedRatingAt')::timestamptz
    else null
  end;
  safe_rating := case
    when coalesce(player_payload ->> 'rating', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then greatest(1::numeric, least(10::numeric, (player_payload ->> 'rating')::numeric))
    when safe_imported_rating is not null then safe_imported_rating
    else 5
  end;

  select coalesce(array_agg(value), '{}'::text[])
  into safe_market_modalities
  from (
    select distinct value
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(player_payload -> 'marketModalities') = 'array' then player_payload -> 'marketModalities'
        else '[]'::jsonb
      end
    ) as modalities(value)
    where value in ('sala', 'futbol7', 'futbol11')
  ) as modality_values;

  safe_stats := jsonb_build_object(
    'goals', case
      when coalesce(player_payload ->> 'goals', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'goals')::integer)
      else 0
    end,
    'assists', case
      when coalesce(player_payload ->> 'assists', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'assists')::integer)
      else 0
    end,
    'appearances', case
      when coalesce(player_payload ->> 'appearances', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'appearances')::integer)
      else 0
    end,
    'wins', case
      when coalesce(player_payload ->> 'wins', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'wins')::integer)
      else 0
    end,
    'lateCancels', case
      when coalesce(player_payload ->> 'lateCancels', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'lateCancels')::integer)
      else 0
    end
  );

  insert into public.pachanga_player_profiles (
    user_id,
    source_group_id,
    source_player_id,
    display_name,
    phone,
    avatar,
    avatar_offset_x,
    avatar_offset_y,
    birth_date,
    goalkeeper_only,
    injured,
    inactive,
    imported_rating,
    imported_rating_at,
    imported_rating_from_group,
    rating,
    ratings,
    rating_votes,
    assessment_summary,
    position,
    outfield_position,
    market_enabled,
    market_zones,
    market_zones_geo,
    market_availability,
    market_bio,
    market_modalities,
    market_open_to_group,
    market_open_to_guest,
    stats
  )
  values (
    owner_id,
    target_group_id,
    nullif(trim(coalesce(target_player_id, player_payload ->> 'id', '')), ''),
    left(coalesce(nullif(trim(player_payload ->> 'name'), ''), 'Jugador'), 80),
    left(coalesce(player_payload ->> 'phone', ''), 40),
    nullif(player_payload ->> 'avatar', ''),
    safe_avatar_offset_x,
    safe_avatar_offset_y,
    safe_birth_date,
    coalesce((player_payload ->> 'goalkeeperOnly')::boolean, false),
    coalesce((player_payload ->> 'injured')::boolean, false),
    coalesce((player_payload ->> 'inactive')::boolean, false),
    safe_imported_rating,
    safe_imported_rating_at,
    nullif(left(trim(coalesce(player_payload ->> 'importedRatingFromGroup', '')), 120), ''),
    safe_rating,
    case when jsonb_typeof(player_payload -> 'ratings') = 'array' then player_payload -> 'ratings' else '[]'::jsonb end,
    case when jsonb_typeof(player_payload -> 'ratingVotes') = 'array' then player_payload -> 'ratingVotes' else '[]'::jsonb end,
    case when jsonb_typeof(player_payload -> 'assessmentSummary') = 'object' then player_payload -> 'assessmentSummary' else '{}'::jsonb end,
    left(coalesce(nullif(trim(player_payload ->> 'position'), ''), 'Mediocentro / pivote'), 80),
    nullif(left(trim(coalesce(player_payload ->> 'outfieldPosition', '')), 80), ''),
    coalesce((player_payload ->> 'marketEnabled')::boolean, false),
    left(coalesce(player_payload ->> 'marketZones', ''), 320),
    case when jsonb_typeof(player_payload -> 'marketZonesGeo') = 'array' then player_payload -> 'marketZonesGeo' else '[]'::jsonb end,
    left(coalesce(player_payload ->> 'marketAvailability', ''), 240),
    left(coalesce(player_payload ->> 'marketBio', ''), 280),
    safe_market_modalities,
    coalesce((player_payload ->> 'marketOpenToGroup')::boolean, true),
    coalesce((player_payload ->> 'marketOpenToGuest')::boolean, true),
    safe_stats
  )
  on conflict (user_id) do update set
    source_group_id = excluded.source_group_id,
    source_player_id = excluded.source_player_id,
    display_name = excluded.display_name,
    phone = excluded.phone,
    avatar = excluded.avatar,
    avatar_offset_x = excluded.avatar_offset_x,
    avatar_offset_y = excluded.avatar_offset_y,
    birth_date = excluded.birth_date,
    goalkeeper_only = excluded.goalkeeper_only,
    injured = excluded.injured,
    inactive = excluded.inactive,
    imported_rating = coalesce(excluded.imported_rating, public.pachanga_player_profiles.imported_rating),
    imported_rating_at = coalesce(excluded.imported_rating_at, public.pachanga_player_profiles.imported_rating_at),
    imported_rating_from_group = coalesce(excluded.imported_rating_from_group, public.pachanga_player_profiles.imported_rating_from_group),
    rating = excluded.rating,
    ratings = excluded.ratings,
    rating_votes = excluded.rating_votes,
    assessment_summary = case
      when excluded.assessment_summary <> '{}'::jsonb then excluded.assessment_summary
      else public.pachanga_player_profiles.assessment_summary
    end,
    position = excluded.position,
    outfield_position = excluded.outfield_position,
    market_enabled = excluded.market_enabled,
    market_zones = excluded.market_zones,
    market_zones_geo = excluded.market_zones_geo,
    market_availability = excluded.market_availability,
    market_bio = excluded.market_bio,
    market_modalities = excluded.market_modalities,
    market_open_to_group = excluded.market_open_to_group,
    market_open_to_guest = excluded.market_open_to_guest,
    stats = excluded.stats,
    profile_version = public.pachanga_player_profiles.profile_version + 1,
    updated_at = now()
  returning id into global_profile_id;

  return global_profile_id;
end;
$$;
