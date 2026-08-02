-- Pachangas IQ rating system V2: conservative legacy preservation and backfill.

insert into public.pachanga_legacy_rating_evidence(
  player_profile_id, source_kind, classification, original_payload,
  safe_facets, contributes_to_v2, migration_version
)
select
  profile.id,
  'profile_rating_state',
  case
    when profile.assessment_summary <> '{}'::jsonb then 'legacy'
    when profile.imported_rating is not null then 'imported'
    when profile.rating_votes <> '[]'::jsonb then 'external_vote'
    else 'unclassifiable'
  end,
  jsonb_build_object(
    'rating', profile.rating,
    'ratings', profile.ratings,
    'ratingVotes', profile.rating_votes,
    'assessmentSummary', profile.assessment_summary,
    'importedRating', profile.imported_rating,
    'importedRatingAt', profile.imported_rating_at,
    'importedRatingFromGroup', profile.imported_rating_from_group
  ),
  null,
  false,
  'pachangas-rating-v2'
from public.pachanga_player_profiles profile
on conflict (player_profile_id, source_kind, migration_version) do nothing;

insert into public.pachanga_legacy_rating_evidence(
  player_profile_id, source_kind, classification, original_payload,
  safe_facets, contributes_to_v2, migration_version
)
select
  assessment.player_profile_id,
  'assessment:' || assessment.id::text,
  case assessment.assessment_kind
    when 'initial' then 'initial_assessment'
    when 'advanced' then 'advanced_assessment'
    else 'unclassifiable'
  end,
  jsonb_build_object(
    'assessmentId', assessment.id,
    'kind', assessment.assessment_kind,
    'engineVersion', assessment.engine_version,
    'questionnaireVersion', assessment.questionnaire_version,
    'input', assessment.input,
    'result', assessment.result,
    'rating', assessment.rating,
    'facetRatings', assessment.facet_ratings,
    'reliability', assessment.reliability,
    'completedAt', assessment.completed_at
  ),
  public.pachanga_rating_v2_facets_from_assessment(assessment.player_profile_id),
  false,
  'pachangas-rating-v2'
from public.pachanga_player_assessments assessment
where assessment.player_profile_id is not null
on conflict (player_profile_id, source_kind, migration_version) do nothing;

with assessment as (
  select
    profile.id,
    public.pachanga_rating_v2_facets_from_assessment(profile.id) as facets,
    (
      select completed.reliability
      from public.pachanga_player_assessments completed
      where completed.player_profile_id = profile.id
      order by case completed.assessment_kind when 'advanced' then 0 else 1 end, completed.completed_at desc, completed.id desc
      limit 1
    ) as reliability
  from public.pachanga_player_profiles profile
)
update public.pachanga_player_profiles profile
set
  rating_domain = case when profile.goalkeeper_only then 'goalkeeper_legacy' else 'field' end,
  base_facets = case
    when assessment.facets ? 'pace' then assessment.facets
    else jsonb_build_object(
      'pace', public.pachanga_rating_v2_clamp(profile.rating * 10),
      'shooting', public.pachanga_rating_v2_clamp(profile.rating * 10),
      'passing', public.pachanga_rating_v2_clamp(profile.rating * 10),
      'dribbling', public.pachanga_rating_v2_clamp(profile.rating * 10),
      'defending', public.pachanga_rating_v2_clamp(profile.rating * 10),
      'physical', public.pachanga_rating_v2_clamp(profile.rating * 10)
    )
  end,
  rating_reliability = public.pachanga_rating_v2_clamp(coalesce(assessment.reliability, 0)),
  rating_engine_version = case when profile.goalkeeper_only then 'goalkeeper-legacy-pending' else 'pachangas-rating-v2' end
from assessment
where assessment.id = profile.id;

do $$
declare
  profile_id uuid;
begin
  for profile_id in select id from public.pachanga_player_profiles order by id
  loop
    perform public.pachanga_recalculate_player_rating_v2(profile_id, null, null, 'migration');
  end loop;
end;
$$;

do $$
declare
  group_row public.pachanga_groups%rowtype;
  match_payload jsonb;
begin
  for group_row in select * from public.pachanga_groups order by id
  loop
    for match_payload in
      select value
      from jsonb_array_elements(coalesce(group_row.payload -> 'matches', '[]'::jsonb)) matches(value)
      where coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA'
      order by value ->> 'date', value ->> 'id'
    loop
      perform public.snapshot_pachanga_match_ratings_v2(group_row.id, match_payload ->> 'id', match_payload);
    end loop;
  end loop;
end;
$$;

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
  select * into profile from public.pachanga_player_profiles where id = target_profile_id;
  if not found then return '{}'::jsonb; end if;

  return jsonb_strip_nulls(jsonb_build_object(
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
    'importedRatingAt', case when profile.imported_rating_at is not null then to_char(profile.imported_rating_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') else null end,
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
    'marketOpenToGuest', profile.market_open_to_guest,
    'ratingV2', jsonb_build_object(
      'domain', profile.rating_domain,
      'baseFacets', profile.base_facets,
      'calibratedFacets', profile.calibrated_facets,
      'currentFacets', profile.current_facets,
      'currentFacetModifiers', profile.current_facet_modifiers,
      'goalkeeperFacets', profile.goalkeeper_facets,
      'baseOverall', profile.base_overall,
      'calibratedOverall', profile.calibrated_overall,
      'currentOverall', profile.current_overall,
      'reliability', profile.rating_reliability,
      'evaluatorCount', profile.rating_evaluator_count,
      'engineVersion', profile.rating_engine_version,
      'recalculatedAt', profile.rating_recalculated_at
    )
  ));
end;
$$;

revoke all on function public.pachanga_group_level_v2(uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.snapshot_pachanga_match_ratings_v2(uuid, text, jsonb) from public, anon, authenticated;
revoke all on function public.capture_new_pachanga_match_rating_snapshots_v2() from public, anon, authenticated;
revoke all on function public.pachanga_player_profile_patch(uuid) from public, anon, authenticated;
