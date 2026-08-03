-- Pachangas IQ rating system V2: anonymous social reads and group switch.

drop policy if exists "Users can read own operation receipts" on public.pachanga_operation_receipts;
create policy "Users can read own operation receipts"
on public.pachanga_operation_receipts
for select to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    user_id = (select auth.uid())
    or (
      public.is_pachanga_group_admin(group_id)
      and operation_type not in (
        'individual_rating_v2',
        'individual_rating_void_v2',
        'individual_rating_moderated_v2'
      )
    )
  )
);

grant select on table public.pachanga_operation_receipts to authenticated;
grant select on table
  public.pachanga_operation_receipts,
  public.pachanga_individual_rating_evidence,
  public.pachanga_rating_evidence_state_events
to service_role;

create or replace function public.get_pachanga_rating_eligibility(target_group_id uuid, target_player_id text)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  evaluator_profile public.pachanga_player_profiles%rowtype;
  target_profile public.pachanga_player_profiles%rowtype;
  previous_evidence public.pachanga_individual_rating_evidence%rowtype;
  shared_count integer := 0;
begin
  if current_user_id is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can rate players';
  end if;
  if not coalesce(public.pachanga_rating_v2_ratings_enabled(target_group_id), false) then
    return jsonb_build_object(
      'canRate', false,
      'reason', 'ratings_disabled',
      'sharedMatches', 0,
      'requiredMatches', 0
    );
  end if;

  select * into evaluator_profile
  from public.pachanga_player_profiles profiles
  where profiles.user_id = current_user_id;
  target_profile := public.pachanga_rating_v2_profile_for_group_player(target_group_id, target_player_id);

  if evaluator_profile.id is null or target_profile.id is null then
    return jsonb_build_object('canRate', false, 'reason', 'registered_profiles_required', 'sharedMatches', 0, 'requiredMatches', 0);
  end if;
  if evaluator_profile.id = target_profile.id then
    return jsonb_build_object('canRate', false, 'reason', 'self_rating', 'sharedMatches', 0, 'requiredMatches', 0);
  end if;
  if target_profile.inactive then
    return jsonb_build_object('canRate', false, 'reason', 'inactive_target', 'sharedMatches', 0, 'requiredMatches', 0);
  end if;
  if not exists (
    select 1
    from public.pachanga_group_members members
    where members.group_id = target_group_id
      and members.user_id = target_profile.user_id
  ) then
    return jsonb_build_object('canRate', false, 'reason', 'target_not_current_member', 'sharedMatches', 0, 'requiredMatches', 0);
  end if;

  select * into previous_evidence
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile.id
    and evidence.target_profile_id = target_profile.id
    and evidence.state = 'active'
  order by evidence.created_at desc, evidence.id desc
  limit 1;

  if previous_evidence.id is null then
    return jsonb_build_object(
      'canRate', true,
      'firstRating', true,
      'sharedMatches', 0,
      'requiredMatches', 0,
      'previousRatingAt', null
    );
  end if;

  shared_count := public.pachanga_rating_v2_shared_matches(
    current_user_id,
    target_profile.user_id,
    previous_evidence.created_at
  );
  return jsonb_build_object(
    'canRate', shared_count >= 3,
    'firstRating', false,
    'sharedMatches', shared_count,
    'requiredMatches', 3,
    'previousRatingAt', previous_evidence.created_at
  );
end;
$$;

create or replace function public.get_my_pachanga_rating_v2(
  target_group_id uuid,
  target_player_id text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  evaluator_profile_id uuid;
  target_profile public.pachanga_player_profiles%rowtype;
  own_evidence public.pachanga_individual_rating_evidence%rowtype;
begin
  if current_user_id is null or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Current group membership required';
  end if;
  select profiles.id into evaluator_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = current_user_id;
  target_profile := public.pachanga_rating_v2_profile_for_group_player(target_group_id, target_player_id);
  if evaluator_profile_id is null or target_profile.id is null then
    return jsonb_build_object(
      'rating', null,
      'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
    );
  end if;

  select * into own_evidence
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile_id
    and evidence.target_profile_id = target_profile.id
    and evidence.state = 'active'
  order by evidence.created_at desc, evidence.id desc
  limit 1;

  return jsonb_build_object(
    'rating', case when own_evidence.id is null then null else jsonb_build_object(
      'evidenceId', own_evidence.id,
      'comparisons', own_evidence.comparisons,
      'createdAt', own_evidence.created_at,
      'sharedMatchesUsed', own_evidence.shared_matches_used
    ) end,
    'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
  );
end;
$$;

create or replace function public.get_pachanga_player_rating_summary_v2(
  target_group_id uuid,
  target_player_id text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  target_profile public.pachanga_player_profiles%rowtype;
  ready boolean;
begin
  if auth.uid() is null or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Current group membership required';
  end if;
  target_profile := public.pachanga_rating_v2_profile_for_group_player(target_group_id, target_player_id);
  if target_profile.id is null then
    raise exception 'Registered player profile required';
  end if;
  ready := target_profile.rating_evaluator_count >= 3;
  return jsonb_build_object(
    'state', case when ready then 'ready' else 'calibrating' end,
    'evaluatorCount', target_profile.rating_evaluator_count,
    'requiredEvaluators', 3,
    'reliability', case when ready then target_profile.rating_reliability else null end,
    'calibratedOverall', case when ready then target_profile.calibrated_overall else null end,
    'calibratedFacets', case when ready then target_profile.calibrated_facets else null end,
    'explanation', case
      when ready then 'Media social agregada y ponderada por fiabilidad.'
      else 'Calibración en curso.'
    end
  );
end;
$$;

create or replace function public.list_pachanga_rating_moderation_v2(target_group_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  result jsonb;
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can moderate ratings';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'moderationId', evidence.moderation_id,
    'targetPlayerId', target_player.value ->> 'id',
    'targetName', target_player.value ->> 'name',
    'state', evidence.state,
    'createdAt', evidence.created_at,
    'source', evidence.source
  ) order by evidence.created_at desc, evidence.id desc), '[]'::jsonb)
  into result
  from public.pachanga_individual_rating_evidence evidence
  join public.pachanga_player_profiles target_profile on target_profile.id = evidence.target_profile_id
  join public.pachanga_groups groups on groups.id = target_group_id
  left join lateral (
    select players.value
    from jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) players(value)
    where players.value ->> 'ownerUserId' = target_profile.user_id::text
    limit 1
  ) target_player on true
  where evidence.group_id = target_group_id
    and evidence.state = 'active';
  return result;
end;
$$;

revoke all on function public.get_pachanga_rating_eligibility(uuid, text) from public, anon;
revoke all on function public.get_my_pachanga_rating_v2(uuid, text) from public, anon;
revoke all on function public.get_pachanga_player_rating_summary_v2(uuid, text) from public, anon;
revoke all on function public.list_pachanga_rating_moderation_v2(uuid) from public, anon;

grant execute on function public.get_pachanga_rating_eligibility(uuid, text) to authenticated;
grant execute on function public.get_my_pachanga_rating_v2(uuid, text) to authenticated;
grant execute on function public.get_pachanga_player_rating_summary_v2(uuid, text) to authenticated;
grant execute on function public.list_pachanga_rating_moderation_v2(uuid) to authenticated;
