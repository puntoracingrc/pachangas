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
  perform set_config('pachangas.rating_v2_defer_group_sync', 'on', true);
  for profile_id in select id from public.pachanga_player_profiles order by id
  loop
    perform public.pachanga_recalculate_player_rating_v2(profile_id, null, null, 'migration');
  end loop;
  perform set_config('pachangas.rating_v2_defer_group_sync', 'off', true);
end;
$$;

-- Rebuild the compatibility payload once after every profile has been
-- recalculated. Re-syncing a group's complete match read model for each of its
-- players multiplies the same work by the squad size on large groups.
with rebuilt_players as (
  select
    groups.id as group_id,
    coalesce(jsonb_agg(
      case
        when profile.id is null then entry.value
        else entry.value || jsonb_build_object(
          'rating', profile.rating,
          'ratingV2', jsonb_strip_nulls(jsonb_build_object(
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
          ))
        )
      end
      order by entry.ordinality
    ), '[]'::jsonb) as players
  from public.pachanga_groups groups
  cross join lateral jsonb_array_elements(
    coalesce(groups.payload -> 'players', '[]'::jsonb)
  ) with ordinality as entry(value, ordinality)
  left join public.pachanga_player_profiles profile
    on profile.user_id::text = entry.value ->> 'ownerUserId'
  group by groups.id
)
update public.pachanga_groups groups
set payload = groups.payload || jsonb_build_object('players', rebuilt_players.players)
from rebuilt_players
where rebuilt_players.group_id = groups.id;

do $$
declare
  group_row public.pachanga_groups%rowtype;
begin
  for group_row in select * from public.pachanga_groups order by id
  loop
    perform public.sync_pachanga_group_read_model(
      group_row.id,
      group_row.payload,
      group_row.payload_revision
    );
  end loop;
end;
$$;

create or replace function public.backfill_pachanga_match_rating_snapshots_v2(
  after_group_id uuid default null,
  group_batch_size integer default 25
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  group_row public.pachanga_groups%rowtype;
  match_payload jsonb;
  last_group_id uuid := after_group_id;
  processed_groups integer := 0;
  processed_matches integer := 0;
  has_more boolean := false;
begin
  if group_batch_size < 1 or group_batch_size > 100 then
    raise exception 'Group batch size must be between 1 and 100';
  end if;

  for group_row in
    select *
    from public.pachanga_groups groups
    where after_group_id is null or groups.id > after_group_id
    order by groups.id
    limit group_batch_size
  loop
    last_group_id := group_row.id;
    processed_groups := processed_groups + 1;
    for match_payload in
      select value
      from jsonb_array_elements(coalesce(group_row.payload -> 'matches', '[]'::jsonb)) matches(value)
      where coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA'
      order by value ->> 'date', value ->> 'id'
    loop
      perform public.snapshot_pachanga_match_ratings_v2(
        group_row.id,
        match_payload ->> 'id',
        match_payload
      );
      processed_matches := processed_matches + 1;
    end loop;
  end loop;

  if last_group_id is not null then
    select exists (
      select 1 from public.pachanga_groups groups where groups.id > last_group_id
    ) into has_more;
  end if;

  return jsonb_build_object(
    'afterGroupId', after_group_id,
    'nextGroupId', last_group_id,
    'processedGroups', processed_groups,
    'processedMatches', processed_matches,
    'done', not has_more
  );
end;
$$;

revoke all on function public.backfill_pachanga_match_rating_snapshots_v2(uuid, integer)
from public, anon, authenticated;
grant execute on function public.backfill_pachanga_match_rating_snapshots_v2(uuid, integer)
to service_role;

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
