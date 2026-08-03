-- Pachangas IQ rating system V2: explicit validation for authoritative payload writes.

create or replace function public.pachanga_rating_payload_is_canonical_v2(
  previous_payload jsonb,
  candidate_payload jsonb
)
returns boolean
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  candidate_player jsonb;
  previous_player jsonb;
  owner_id uuid;
  profile_id uuid;
  canonical_patch jsonb;
  protected_key text;
begin
  if jsonb_typeof(coalesce(candidate_payload -> 'players', '[]'::jsonb)) <> 'array' then
    return false;
  end if;

  for candidate_player in
    select entries.value
    from jsonb_array_elements(coalesce(candidate_payload -> 'players', '[]'::jsonb)) entries(value)
  loop
    if nullif(candidate_player ->> 'id', '') is null then return false; end if;
    owner_id := null;
    if coalesce(candidate_player ->> 'ownerUserId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      owner_id := (candidate_player ->> 'ownerUserId')::uuid;
    end if;

    if owner_id is not null then
      select profiles.id into profile_id
      from public.pachanga_player_profiles profiles
      where profiles.user_id = owner_id;
      if profile_id is null then return false; end if;
      canonical_patch := public.pachanga_player_profile_patch(profile_id);
      if canonical_patch = '{}'::jsonb or not candidate_player @> canonical_patch then return false; end if;
    else
      select entries.value into previous_player
      from jsonb_array_elements(coalesce(previous_payload -> 'players', '[]'::jsonb)) entries(value)
      where entries.value ->> 'id' = candidate_player ->> 'id'
      limit 1;

      if previous_player is null then
        if coalesce(nullif(candidate_player ->> 'rating', '')::numeric, 5) <> 5
          or jsonb_array_length(case when jsonb_typeof(candidate_player -> 'ratings') = 'array' then candidate_player -> 'ratings' else '[]'::jsonb end) > 0
          or jsonb_array_length(case when jsonb_typeof(candidate_player -> 'ratingVotes') = 'array' then candidate_player -> 'ratingVotes' else '[]'::jsonb end) > 0
          or candidate_player ? 'ratingV2'
          or candidate_player ? 'assessmentSummary'
        then return false; end if;
      else
        foreach protected_key in array array[
          'ownerUserId', 'globalPlayerProfileId', 'rating', 'ratings', 'ratingVotes',
          'ratingV2', 'assessmentSummary', 'importedRating', 'importedRatingAt',
          'importedRatingFromGroup'
        ]
        loop
          if candidate_player -> protected_key is distinct from previous_player -> protected_key then
            return false;
          end if;
        end loop;
      end if;
    end if;
  end loop;
  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then return false;
end;
$$;

revoke all on function public.pachanga_rating_payload_is_canonical_v2(jsonb, jsonb)
  from public, anon, authenticated;
