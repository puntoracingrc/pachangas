create or replace function public.pachanga_player_profile_patch(target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  profile public.pachanga_player_profiles%rowtype;
begin
  select * into profile
  from public.pachanga_player_profiles
  where id = target_profile_id;

  if not found then
    return '{}'::jsonb;
  end if;

  return jsonb_strip_nulls(
    jsonb_build_object(
      'globalPlayerProfileId', profile.id::text,
      'ownerUserId', profile.user_id::text,
      'name', profile.display_name,
      'phone', profile.phone,
      'avatar', profile.avatar,
      'avatarOffsetX', profile.avatar_offset_x,
      'avatarOffsetY', profile.avatar_offset_y,
      'birthDate', profile.birth_date,
      'goalkeeperOnly', profile.goalkeeper_only,
      'injured', profile.injured,
      'inactive', profile.inactive,
      'importedRating', profile.imported_rating,
      'importedRatingAt', case
        when profile.imported_rating_at is not null then to_char(profile.imported_rating_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        else null
      end,
      'importedRatingFromGroup', profile.imported_rating_from_group,
      'rating', profile.rating,
      'ratings', profile.ratings,
      'ratingVotes', profile.rating_votes,
      'assessmentSummary', profile.assessment_summary,
      'position', profile.position,
      'outfieldPosition', profile.outfield_position,
      'marketEnabled', profile.market_enabled,
      'marketZones', profile.market_zones,
      'marketZonesGeo', profile.market_zones_geo,
      'marketAvailability', profile.market_availability,
      'marketBio', profile.market_bio,
      'marketModalities', to_jsonb(profile.market_modalities),
      'marketOpenToGroup', profile.market_open_to_group,
      'marketOpenToGuest', profile.market_open_to_guest
    )
  );
end;
$$;
