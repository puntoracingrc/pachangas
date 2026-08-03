-- Pachangas IQ rating system V2: deterministic server rules and permissions.

create or replace function public.pachanga_rating_v2_clamp(value numeric, min_value numeric default 0, max_value numeric default 100)
returns numeric
language sql
immutable
set search_path = public
as $$
  select greatest(min_value, least(max_value, coalesce(value, min_value)));
$$;

create or replace function public.pachanga_rating_v2_comparison_delta(comparison text)
returns numeric
language sql
immutable
set search_path = public
as $$
  select case comparison
    when 'MUCHO_PEOR' then -10
    when 'PEOR' then -5
    when 'PARECIDO' then 0
    when 'MEJOR' then 5
    when 'MUCHO_MEJOR' then 10
    else null
  end;
$$;

create or replace function public.pachanga_rating_v2_position_id(position_name text)
returns text
language sql
immutable
set search_path = public
as $$
  select case position_name
    when 'Defensa central' then 'centre_back'
    when 'Lateral derecho' then 'full_back'
    when 'Lateral izquierdo' then 'full_back'
    when 'Carrilero' then 'full_back'
    when 'Pivote defensivo' then 'defensive_midfielder'
    when 'Mediapunta' then 'attacking_midfielder'
    when 'Extremo derecho' then 'winger'
    when 'Extremo izquierdo' then 'winger'
    when 'Ala derecha' then 'winger'
    when 'Ala izquierda' then 'winger'
    when 'Delantero centro' then 'striker'
    when 'Segundo delantero' then 'striker'
    when 'Delantero / punta' then 'striker'
    when 'Pívot' then 'striker'
    else 'central_midfielder'
  end;
$$;

create or replace function public.pachanga_rating_v2_overall(facets jsonb, position_name text, rating_domain text default 'field')
returns numeric
language plpgsql
immutable
set search_path = public
as $$
declare
  facet text;
  position_id text;
  total numeric := 0;
begin
  if rating_domain <> 'field' then
    return null;
  end if;

  position_id := public.pachanga_rating_v2_position_id(position_name);
  foreach facet in array array['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical']
  loop
    total := total
      + public.pachanga_rating_v2_clamp(nullif(facets ->> facet, '')::numeric)
      * public.pachanga_assessment_overall_weight(position_id, facet);
  end loop;
  return public.pachanga_rating_v2_clamp(total);
end;
$$;

create or replace function public.pachanga_rating_v2_facets_from_assessment(target_profile_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  with latest as (
    select facet_ratings
    from public.pachanga_player_assessments
    where player_profile_id = target_profile_id
      and assessment_kind in ('initial', 'advanced')
    order by case assessment_kind when 'advanced' then 0 else 1 end, completed_at desc, id desc
    limit 1
  )
  select case
    when facet_ratings is null then '{}'::jsonb
    else jsonb_build_object(
      'pace', public.pachanga_rating_v2_clamp((facet_ratings ->> 'ritmo')::numeric * 10),
      'shooting', public.pachanga_rating_v2_clamp((facet_ratings ->> 'tiro')::numeric * 10),
      'passing', public.pachanga_rating_v2_clamp((facet_ratings ->> 'pase')::numeric * 10),
      'dribbling', public.pachanga_rating_v2_clamp((facet_ratings ->> 'regate')::numeric * 10),
      'defending', public.pachanga_rating_v2_clamp((facet_ratings ->> 'defensa')::numeric * 10),
      'physical', public.pachanga_rating_v2_clamp((facet_ratings ->> 'fisico')::numeric * 10)
    )
  end
  from latest;
$$;

create or replace function public.pachanga_rating_v2_profile_for_group_player(target_group_id uuid, target_player_id text)
returns public.pachanga_player_profiles
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  owner_id uuid;
  result public.pachanga_player_profiles%rowtype;
begin
  select nullif(player.value ->> 'ownerUserId', '')::uuid
  into owner_id
  from public.pachanga_groups groups
  cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) player(value)
  where groups.id = target_group_id
    and player.value ->> 'id' = target_player_id
    and coalesce(player.value ->> 'ownerUserId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  limit 1;

  if owner_id is null then
    return null;
  end if;

  select * into result
  from public.pachanga_player_profiles
  where user_id = owner_id;
  return result;
end;
$$;

create or replace function public.pachanga_rating_v2_shared_matches(
  evaluator_user_id uuid,
  target_user_id uuid,
  since_at timestamptz default null
)
returns integer
language sql
security definer
set search_path = public
stable
as $$
  with snapshotted_shared as (
    select distinct evaluator.group_id, evaluator.match_id
    from public.pachanga_match_rating_participants evaluator
    join public.pachanga_match_rating_participants target
      on target.group_id = evaluator.group_id
      and target.match_id = evaluator.match_id
    join public.pachanga_player_profiles evaluator_profile
      on evaluator_profile.id = evaluator.player_profile_id
    join public.pachanga_player_profiles target_profile
      on target_profile.id = target.player_profile_id
    join public.pachanga_match_rating_snapshots snapshot
      on snapshot.group_id = evaluator.group_id
      and snapshot.match_id = evaluator.match_id
    where evaluator_profile.user_id = evaluator_user_id
      and target_profile.user_id = target_user_id
      and snapshot.state = 'active'
      and evaluator.attendance_confirmed
      and target.attendance_confirmed
      and not evaluator.was_reserve
      and not target.was_reserve
      and (since_at is null or snapshot.finalized_at > since_at)
  ), legacy_shared as (
    select distinct read_model.group_id, read_model.match_id
    from public.pachanga_match_read_model read_model
    join public.pachanga_groups groups on groups.id = read_model.group_id
    join public.pachanga_group_members evaluator_member
      on evaluator_member.group_id = groups.id and evaluator_member.user_id = evaluator_user_id
    join public.pachanga_group_members target_member
      on target_member.group_id = groups.id and target_member.user_id = target_user_id
    cross join lateral (
      select value
      from jsonb_array_elements(coalesce(groups.payload -> 'matches', '[]'::jsonb)) matches(value)
      where value ->> 'id' = read_model.match_id
      limit 1
    ) match_payload
    cross join lateral (
      select value ->> 'id' as player_id
      from jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) players(value)
      where value ->> 'ownerUserId' = evaluator_user_id::text
      limit 1
    ) evaluator_player
    cross join lateral (
      select value ->> 'id' as player_id
      from jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) players(value)
      where value ->> 'ownerUserId' = target_user_id::text
      limit 1
    ) target_player
    join public.pachanga_match_participants evaluator_participant
      on evaluator_participant.group_id = read_model.group_id
      and evaluator_participant.match_id = read_model.match_id
      and evaluator_participant.player_id = evaluator_player.player_id
    join public.pachanga_match_participants target_participant
      on target_participant.group_id = read_model.group_id
      and target_participant.match_id = read_model.match_id
      and target_participant.player_id = target_player.player_id
    where (read_model.finalized or read_model.match_state in ('finalized', 'historical'))
      and not exists (
        select 1
        from public.pachanga_match_rating_snapshots persisted_snapshot
        where persisted_snapshot.group_id = read_model.group_id
          and persisted_snapshot.match_id = read_model.match_id
      )
      and evaluator_participant.status = 'voy'
      and target_participant.status = 'voy'
      and evaluator_participant.seat_kind = 'playing'
      and target_participant.seat_kind = 'playing'
      and (
        since_at is null
        or coalesce(nullif(match_payload.value ->> 'date', '')::timestamptz, read_model.updated_at) > since_at
      )
  )
  select count(*)::integer
  from (
    select * from snapshotted_shared
    union
    select * from legacy_shared
  ) shared;
$$;

create or replace function public.get_pachanga_rating_eligibility(target_group_id uuid, target_player_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
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

  select * into evaluator_profile from public.pachanga_player_profiles where user_id = current_user_id;
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
    from public.pachanga_group_members member
    where member.group_id = target_group_id
      and member.user_id = target_profile.user_id
  ) then
    return jsonb_build_object('canRate', false, 'reason', 'target_not_current_member', 'sharedMatches', 0, 'requiredMatches', 0);
  end if;

  select * into previous_evidence
  from public.pachanga_individual_rating_evidence
  where evaluator_profile_id = evaluator_profile.id
    and target_profile_id = target_profile.id
    and state = 'active'
  order by created_at desc, id desc
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

  shared_count := public.pachanga_rating_v2_shared_matches(current_user_id, target_profile.user_id, previous_evidence.created_at);
  return jsonb_build_object(
    'canRate', shared_count >= 3,
    'firstRating', false,
    'sharedMatches', shared_count,
    'requiredMatches', 3,
    'previousRatingAt', previous_evidence.created_at,
    'previousEvidenceId', previous_evidence.id
  );
end;
$$;

create or replace function public.pachanga_recalculate_player_rating_v2(
  target_profile_id uuid,
  trigger_evidence_id uuid default null,
  snapshot_group_id uuid default null,
  snapshot_kind text default 'recalculation'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  profile public.pachanga_player_profiles%rowtype;
  facet text;
  base_value numeric;
  prior_weight numeric;
  weighted_observations numeric;
  evaluator_weights numeric;
  calibrated_value numeric;
  modifier_value numeric;
  base_values jsonb;
  calibrated_values jsonb := '{}'::jsonb;
  current_values jsonb := '{}'::jsonb;
  active_ids uuid[];
  evaluator_count integer;
  calculated_base_overall numeric;
  calculated_calibrated_overall numeric;
  calculated_current_overall numeric;
begin
  select * into profile
  from public.pachanga_player_profiles
  where id = target_profile_id
  for update;
  if not found then raise exception 'Player profile not found'; end if;

  base_values := case
    when jsonb_typeof(profile.base_facets) = 'object' and profile.base_facets ? 'pace' then profile.base_facets
    else public.pachanga_rating_v2_facets_from_assessment(profile.id)
  end;
  if base_values is null or not (base_values ? 'pace') then
    raise exception 'A valid base assessment is required';
  end if;

  prior_weight := 2 + 3 * (public.pachanga_rating_v2_clamp(profile.rating_reliability) / 100);
  foreach facet in array array['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical']
  loop
    base_value := public.pachanga_rating_v2_clamp((base_values ->> facet)::numeric);
    select
      coalesce(sum(
        (0.5 + 0.5 * public.pachanga_rating_v2_clamp(evidence.evaluator_confidence_snapshot) / 100)
        * public.pachanga_rating_v2_clamp(
          (evidence.observations ->> facet)::numeric,
          greatest(0, base_value - 15),
          least(100, base_value + 15)
        )
      ), 0),
      coalesce(sum(0.5 + 0.5 * public.pachanga_rating_v2_clamp(evidence.evaluator_confidence_snapshot) / 100), 0)
    into weighted_observations, evaluator_weights
    from public.pachanga_individual_rating_evidence evidence
    where evidence.target_profile_id = profile.id and evidence.state = 'active';

    calibrated_value := public.pachanga_rating_v2_clamp(
      (prior_weight * base_value + weighted_observations) / (prior_weight + evaluator_weights)
    );
    modifier_value := coalesce(nullif(profile.current_facet_modifiers ->> facet, '')::numeric, 0);
    calibrated_values := calibrated_values || jsonb_build_object(facet, calibrated_value);
    current_values := current_values || jsonb_build_object(facet, public.pachanga_rating_v2_clamp(calibrated_value + modifier_value));
  end loop;

  select coalesce(array_agg(evidence.id order by evidence.evaluator_profile_id), '{}'::uuid[]), count(distinct evidence.evaluator_profile_id)::integer
  into active_ids, evaluator_count
  from public.pachanga_individual_rating_evidence evidence
  where evidence.target_profile_id = profile.id and evidence.state = 'active';

  calculated_base_overall := public.pachanga_rating_v2_overall(base_values, coalesce(profile.outfield_position, profile.position), profile.rating_domain);
  calculated_calibrated_overall := public.pachanga_rating_v2_overall(calibrated_values, coalesce(profile.outfield_position, profile.position), profile.rating_domain);
  calculated_current_overall := public.pachanga_rating_v2_overall(current_values, coalesce(profile.outfield_position, profile.position), profile.rating_domain);

  update public.pachanga_player_profiles
  set base_facets = base_values,
      calibrated_facets = calibrated_values,
      current_facets = current_values,
      base_overall = calculated_base_overall,
      calibrated_overall = calculated_calibrated_overall,
      current_overall = calculated_current_overall,
      rating = case when calculated_current_overall is null then rating else calculated_current_overall / 10 end,
      rating_evaluator_count = evaluator_count,
      rating_engine_version = 'pachangas-rating-v2',
      rating_recalculated_at = now(),
      profile_version = profile_version + 1,
      updated_at = now()
  where id = profile.id;

  insert into public.pachanga_player_rating_snapshots (
    player_profile_id, trigger_evidence_id, group_id, snapshot_kind,
    base_facets, calibrated_facets, current_facets, current_facet_modifiers,
    base_overall, calibrated_overall, current_overall, reliability,
    evaluator_count, active_evidence_ids, engine_version
  ) values (
    profile.id, trigger_evidence_id, snapshot_group_id, snapshot_kind,
    base_values, calibrated_values, current_values, profile.current_facet_modifiers,
    calculated_base_overall, calculated_calibrated_overall, calculated_current_overall,
    profile.rating_reliability, evaluator_count, active_ids, 'pachangas-rating-v2'
  );

  if coalesce(current_setting('pachangas.rating_v2_defer_group_sync', true), 'off') <> 'on' then
    perform public.sync_pachanga_player_profile_to_groups(profile.id);
  end if;
  return jsonb_build_object(
    'baseFacets', base_values,
    'calibratedFacets', calibrated_values,
    'currentFacets', current_values,
    'baseOverall', calculated_base_overall,
    'calibratedOverall', calculated_calibrated_overall,
    'currentOverall', calculated_current_overall,
    'reliability', profile.rating_reliability,
    'evaluatorCount', evaluator_count,
    'activeEvidenceIds', to_jsonb(active_ids),
    'engineVersion', 'pachangas-rating-v2'
  );
end;
$$;

create or replace function public.record_pachanga_individual_rating_v2(
  target_group_id uuid,
  target_player_id text,
  comparisons jsonb,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  evaluator_profile public.pachanga_player_profiles%rowtype;
  target_profile public.pachanga_player_profiles%rowtype;
  previous_evidence public.pachanga_individual_rating_evidence%rowtype;
  existing_evidence public.pachanga_individual_rating_evidence%rowtype;
  facet text;
  comparison text;
  delta numeric;
  reference_facets jsonb;
  applied_deltas jsonb := '{}'::jsonb;
  observations jsonb := '{}'::jsonb;
  shared_count integer := 0;
  next_evidence_id uuid;
  card_result jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if current_user_id is null or not public.is_registered_pachanga_user() then raise exception 'Registered user required'; end if;
  if operation_id is null then raise exception 'Operation id required'; end if;
  if not public.is_pachanga_group_member(target_group_id) then raise exception 'Only members can rate players'; end if;

  select * into evaluator_profile from public.pachanga_player_profiles where user_id = current_user_id;
  target_profile := public.pachanga_rating_v2_profile_for_group_player(target_group_id, target_player_id);
  if evaluator_profile.id is null or target_profile.id is null then raise exception 'Registered player profiles required'; end if;
  if evaluator_profile.id = target_profile.id then raise exception 'You cannot rate yourself'; end if;
  if target_profile.inactive then raise exception 'Inactive players cannot be rated'; end if;
  if not exists (
    select 1
    from public.pachanga_group_members member
    where member.group_id = target_group_id
      and member.user_id = target_profile.user_id
  ) then
    raise exception 'Target player must be a current group member';
  end if;
  if evaluator_profile.rating_domain <> 'field' or target_profile.rating_domain <> 'field' then
    raise exception 'Goalkeeper comparison engine is not available yet';
  end if;

  perform pg_advisory_xact_lock(hashtext(evaluator_profile.id::text), hashtext(target_profile.id::text));

  select * into existing_evidence
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile.id
    and evidence.operation_id = record_pachanga_individual_rating_v2.operation_id;
  if existing_evidence.id is not null then
    select payload, payload_revision, updated_at into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups where id = target_group_id;
    return jsonb_build_object(
      'payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at,
      'evidenceId', existing_evidence.id, 'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
    );
  end if;

  select * into previous_evidence
  from public.pachanga_individual_rating_evidence
  where evaluator_profile_id = evaluator_profile.id and target_profile_id = target_profile.id and state = 'active'
  for update;

  if previous_evidence.id is not null then
    shared_count := public.pachanga_rating_v2_shared_matches(current_user_id, target_profile.user_id, previous_evidence.created_at);
    if shared_count < 3 then raise exception 'Three additional shared matches are required'; end if;
  end if;

  reference_facets := case
    when evaluator_profile.current_facets ? 'pace' then evaluator_profile.current_facets
    when evaluator_profile.calibrated_facets ? 'pace' then evaluator_profile.calibrated_facets
    when evaluator_profile.base_facets ? 'pace' then evaluator_profile.base_facets
    else public.pachanga_rating_v2_facets_from_assessment(evaluator_profile.id)
  end;
  if reference_facets is null or not (reference_facets ? 'pace') then raise exception 'Evaluator card is not ready'; end if;

  foreach facet in array array['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical']
  loop
    comparison := comparisons ->> facet;
    delta := public.pachanga_rating_v2_comparison_delta(comparison);
    if delta is null then raise exception 'Invalid comparison for %', facet; end if;
    applied_deltas := applied_deltas || jsonb_build_object(facet, delta);
    observations := observations || jsonb_build_object(
      facet,
      public.pachanga_rating_v2_clamp((reference_facets ->> facet)::numeric + delta)
    );
  end loop;

  if previous_evidence.id is not null then
    update public.pachanga_individual_rating_evidence
    set state = 'superseded', superseded_at = now()
    where id = previous_evidence.id;
    insert into public.pachanga_rating_evidence_state_events(evidence_id, from_state, to_state, actor_id, reason)
    values (previous_evidence.id, 'active', 'superseded', current_user_id, 'Replaced by a new eligible rating');
  end if;

  insert into public.pachanga_individual_rating_evidence (
    evaluator_profile_id, target_profile_id, group_id, operation_id, previous_evidence_id,
    engine_version, evaluator_reference_facets, comparisons, applied_deltas, observations,
    evaluator_confidence_snapshot, shared_matches_used, shared_matches_since
  ) values (
    evaluator_profile.id, target_profile.id, target_group_id, operation_id, previous_evidence.id,
    'pachangas-rating-v2', reference_facets, comparisons, applied_deltas, observations,
    public.pachanga_rating_v2_clamp(coalesce(evaluator_profile.rating_reliability, 0)),
    shared_count, previous_evidence.created_at
  ) returning id into next_evidence_id;

  insert into public.pachanga_rating_evidence_state_events(evidence_id, from_state, to_state, actor_id, reason)
  values (next_evidence_id, null, 'active', current_user_id, 'Individual member comparison');

  card_result := public.pachanga_recalculate_player_rating_v2(target_profile.id, next_evidence_id, target_group_id, 'recalculation');

  if exists (
    select 1
    from public.pachanga_individual_rating_evidence reverse_rating
    where reverse_rating.evaluator_profile_id = target_profile.id
      and reverse_rating.target_profile_id = evaluator_profile.id
      and reverse_rating.state = 'active'
      and reverse_rating.comparisons = jsonb_build_object(
        'pace', 'MUCHO_MEJOR', 'shooting', 'MUCHO_MEJOR', 'passing', 'MUCHO_MEJOR',
        'dribbling', 'MUCHO_MEJOR', 'defending', 'MUCHO_MEJOR', 'physical', 'MUCHO_MEJOR'
      )
  ) and comparisons = jsonb_build_object(
    'pace', 'MUCHO_MEJOR', 'shooting', 'MUCHO_MEJOR', 'passing', 'MUCHO_MEJOR',
    'dribbling', 'MUCHO_MEJOR', 'defending', 'MUCHO_MEJOR', 'physical', 'MUCHO_MEJOR'
  ) then
    insert into public.pachanga_rating_flags(flag_kind, evaluator_profile_id, target_profile_id, group_id, evidence_ids, metadata)
    values ('reciprocal_maximum', evaluator_profile.id, target_profile.id, target_group_id, array[next_evidence_id], jsonb_build_object('informationalOnly', true));
  end if;

  select payload, payload_revision, updated_at into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups where id = target_group_id;
  return jsonb_build_object(
    'payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at,
    'evidenceId', next_evidence_id, 'card', card_result,
    'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
  );
end;
$$;

create or replace function public.void_pachanga_individual_rating_v2(evidence_id uuid, reason text, operation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  selected public.pachanga_individual_rating_evidence%rowtype;
  evaluator_user_id uuid;
  restored public.pachanga_individual_rating_evidence%rowtype;
  restored_id uuid;
  card_result jsonb;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null or nullif(trim(reason), '') is null then raise exception 'Operation id and reason required'; end if;

  select * into selected from public.pachanga_individual_rating_evidence where id = evidence_id for update;
  if not found then raise exception 'Rating evidence not found'; end if;
  select user_id into evaluator_user_id from public.pachanga_player_profiles where id = selected.evaluator_profile_id;
  if current_user_id <> evaluator_user_id and not public.is_pachanga_group_admin(selected.group_id) then
    raise exception 'Only the evaluator or a group admin can void this rating';
  end if;
  if selected.state = 'void' then return jsonb_build_object('evidenceId', selected.id, 'state', 'void'); end if;

  update public.pachanga_individual_rating_evidence
  set state = 'void', voided_at = now(), voided_by = current_user_id, void_reason = trim(reason)
  where id = selected.id;
  insert into public.pachanga_rating_evidence_state_events(evidence_id, from_state, to_state, actor_id, reason)
  values (selected.id, selected.state, 'void', current_user_id, trim(reason));

  if selected.state = 'active' then
    select * into restored
    from public.pachanga_individual_rating_evidence
    where evaluator_profile_id = selected.evaluator_profile_id
      and target_profile_id = selected.target_profile_id
      and state = 'superseded'
      and id <> selected.id
    order by created_at desc, id desc
    limit 1;

    if restored.id is not null then
      insert into public.pachanga_individual_rating_evidence (
        evaluator_profile_id, target_profile_id, group_id, operation_id, previous_evidence_id,
        engine_version, evaluator_reference_facets, comparisons, applied_deltas, observations,
        evaluator_confidence_snapshot, shared_matches_used, shared_matches_since, source
      ) values (
        restored.evaluator_profile_id, restored.target_profile_id, restored.group_id, operation_id, restored.id,
        restored.engine_version, restored.evaluator_reference_facets, restored.comparisons, restored.applied_deltas, restored.observations,
        restored.evaluator_confidence_snapshot, restored.shared_matches_used, restored.shared_matches_since, 'restored'
      ) returning id into restored_id;
      insert into public.pachanga_rating_evidence_state_events(evidence_id, from_state, to_state, actor_id, reason)
      values (restored_id, null, 'active', current_user_id, 'Restored after voiding a newer rating');
    end if;
  end if;

  card_result := public.pachanga_recalculate_player_rating_v2(selected.target_profile_id, restored_id, selected.group_id, 'recalculation');
  return jsonb_build_object('evidenceId', selected.id, 'state', 'void', 'restoredEvidenceId', restored_id, 'card', card_result);
end;
$$;

create or replace function public.create_pachanga_guest_identity_v2(target_group_id uuid, display_name text, contact_hint text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  guest_id uuid;
  normalized text := lower(regexp_replace(trim(display_name), '\s+', ' ', 'g'));
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then raise exception 'Only group admins can create guests'; end if;
  if normalized = '' then raise exception 'Guest name required'; end if;
  insert into public.pachanga_guest_identities(created_by_group_id, display_name, normalized_name, contact_hint)
  values (target_group_id, trim(display_name), normalized, nullif(trim(contact_hint), ''))
  returning id into guest_id;
  return guest_id;
end;
$$;

create or replace function public.link_pachanga_guest_identity_v2(guest_id uuid, target_user_id uuid, reason text, operation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  guest public.pachanga_guest_identities%rowtype;
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null or operation_id is null then raise exception 'Authentication and operation id required'; end if;
  select * into guest from public.pachanga_guest_identities where id = guest_id for update;
  if not found then raise exception 'Guest identity not found'; end if;
  if current_user_id <> target_user_id and not public.is_pachanga_group_admin(guest.created_by_group_id) then
    raise exception 'Only the target user or a group admin can link this guest';
  end if;
  if guest.link_state = 'linked' and guest.linked_user_id = target_user_id then
    return jsonb_build_object('guestId', guest.id, 'userId', target_user_id, 'state', 'linked');
  end if;
  if guest.link_state = 'linked' and guest.linked_user_id <> target_user_id then raise exception 'Guest is already linked'; end if;

  insert into public.pachanga_guest_link_events(guest_identity_id, user_id, action, actor_id, reason, previous_state)
  values (guest.id, target_user_id, 'linked', current_user_id, nullif(trim(reason), ''), to_jsonb(guest));
  update public.pachanga_guest_identities
  set linked_user_id = target_user_id, link_state = 'linked', updated_at = now()
  where id = guest.id;
  update public.pachanga_match_rating_participants participant
  set player_profile_id = profile.id
  from public.pachanga_player_profiles profile
  where participant.guest_identity_id = guest.id
    and profile.user_id = target_user_id;
  return jsonb_build_object('guestId', guest.id, 'userId', target_user_id, 'state', 'linked');
end;
$$;

create or replace function public.reverse_pachanga_guest_link_v2(guest_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  guest public.pachanga_guest_identities%rowtype;
  current_user_id uuid := auth.uid();
begin
  select * into guest from public.pachanga_guest_identities where id = guest_id for update;
  if not found then raise exception 'Guest identity not found'; end if;
  if current_user_id is null or (current_user_id <> guest.linked_user_id and not public.is_pachanga_group_admin(guest.created_by_group_id)) then
    raise exception 'Only the linked user or a group admin can reverse this link';
  end if;
  if guest.linked_user_id is null then return jsonb_build_object('guestId', guest.id, 'state', guest.link_state); end if;
  if nullif(trim(reason), '') is null then raise exception 'Reason required'; end if;

  insert into public.pachanga_guest_link_events(guest_identity_id, user_id, action, actor_id, reason, previous_state)
  values (guest.id, guest.linked_user_id, 'reversed', current_user_id, trim(reason), to_jsonb(guest));
  update public.pachanga_guest_identities
  set linked_user_id = null, link_state = 'reversed', updated_at = now()
  where id = guest.id;
  update public.pachanga_match_rating_participants
  set player_profile_id = null
  where guest_identity_id = guest.id;
  return jsonb_build_object('guestId', guest.id, 'state', 'reversed');
end;
$$;

create or replace function public.record_pachanga_global_rating_v2(
  target_group_id uuid,
  target_match_id text,
  target_kind text,
  comparison text,
  target_guest_id uuid default null,
  target_external_team_id uuid default null,
  rated_group_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  snapshot public.pachanga_match_rating_snapshots%rowtype;
  reference_level numeric;
  comparison_delta numeric;
  calculated_observation numeric;
  response_id uuid;
  official_id uuid;
  calculated_official_observation numeric;
  calculated_response_count integer;
  calculated_response_ids uuid[];
begin
  if current_user_id is null or not public.is_pachanga_group_admin(target_group_id) then raise exception 'Only group admins can submit global ratings'; end if;
  if target_kind not in ('guest', 'external_team', 'registered_group') then raise exception 'Invalid global rating target'; end if;
  if target_kind = 'guest' and (
    target_guest_id is null
    or target_external_team_id is not null
    or rated_group_id is not null
    or not exists (
      select 1
      from public.pachanga_guest_identities guest
      join public.pachanga_match_rating_participants participant
        on participant.guest_identity_id = guest.id
        and participant.group_id = record_pachanga_global_rating_v2.target_group_id
        and participant.match_id = target_match_id
        and participant.attendance_confirmed
        and not participant.was_reserve
      where guest.id = target_guest_id
        and guest.created_by_group_id = record_pachanga_global_rating_v2.target_group_id
    )
  ) then raise exception 'Guest must be a real participant in this match'; end if;
  if target_kind = 'external_team' and (
    target_external_team_id is null
    or target_guest_id is not null
    or rated_group_id is not null
    or not exists (
      select 1 from public.pachanga_external_teams external_team
      where external_team.id = target_external_team_id
        and external_team.created_by_group_id = record_pachanga_global_rating_v2.target_group_id
    )
  ) then raise exception 'External team identity does not belong to this group'; end if;
  if target_kind = 'registered_group' and (
    rated_group_id is null
    or rated_group_id = record_pachanga_global_rating_v2.target_group_id
    or target_guest_id is not null
    or target_external_team_id is not null
  ) then raise exception 'A different registered group is required'; end if;
  comparison_delta := public.pachanga_rating_v2_comparison_delta(comparison);
  if comparison_delta is null then raise exception 'Invalid comparison'; end if;
  select * into snapshot
  from public.pachanga_match_rating_snapshots
  where group_id = target_group_id and match_id = target_match_id and state = 'active';
  if not found then raise exception 'Active finalized match rating snapshot required'; end if;
  reference_level := coalesce((snapshot.lineup_a_level + snapshot.lineup_b_level) / 2, snapshot.lineup_a_level, snapshot.lineup_b_level, snapshot.group_level);
  if reference_level is null then raise exception 'Host lineup level unavailable'; end if;
  calculated_observation := public.pachanga_rating_v2_clamp(reference_level + comparison_delta);

  select id into response_id
  from public.pachanga_global_rating_responses response
  where response.group_id = record_pachanga_global_rating_v2.target_group_id
    and response.match_id = target_match_id
    and response.target_kind = record_pachanga_global_rating_v2.target_kind
    and response.guest_identity_id is not distinct from target_guest_id
    and response.external_team_id is not distinct from target_external_team_id
    and response.target_group_id is not distinct from rated_group_id
    and response.actor_user_id = current_user_id
  for update;

  if response_id is null then
    insert into public.pachanga_global_rating_responses (
      group_id, match_id, target_kind, guest_identity_id, external_team_id, target_group_id,
      actor_user_id, comparison, delta, reference_level_snapshot, observation, engine_version
    ) values (
      record_pachanga_global_rating_v2.target_group_id, target_match_id, target_kind,
      target_guest_id, target_external_team_id, rated_group_id, current_user_id,
      comparison, comparison_delta, reference_level, calculated_observation, 'pachangas-rating-v2'
    ) returning id into response_id;
  else
    update public.pachanga_global_rating_responses
    set comparison = record_pachanga_global_rating_v2.comparison,
        delta = comparison_delta,
        reference_level_snapshot = reference_level,
        observation = calculated_observation
    where id = response_id;
  end if;

  select avg(response.observation), count(*)::integer, array_agg(response.id order by response.actor_user_id)
  into calculated_official_observation, calculated_response_count, calculated_response_ids
  from public.pachanga_global_rating_responses response
  where response.group_id = record_pachanga_global_rating_v2.target_group_id
    and response.match_id = target_match_id
    and response.target_kind = record_pachanga_global_rating_v2.target_kind
    and response.guest_identity_id is not distinct from target_guest_id
    and response.external_team_id is not distinct from target_external_team_id
    and response.target_group_id is not distinct from rated_group_id;

  select id into official_id
  from public.pachanga_global_rating_evidence
  where group_id = record_pachanga_global_rating_v2.target_group_id
    and match_id = target_match_id
    and pachanga_global_rating_evidence.target_kind = record_pachanga_global_rating_v2.target_kind
    and guest_identity_id is not distinct from target_guest_id
    and external_team_id is not distinct from target_external_team_id
    and pachanga_global_rating_evidence.target_group_id is not distinct from rated_group_id
  for update;

  if official_id is null then
    insert into public.pachanga_global_rating_evidence (
      group_id, match_id, target_kind, guest_identity_id, external_team_id, target_group_id,
      official_observation, response_count, response_ids, engine_version
    ) values (
      record_pachanga_global_rating_v2.target_group_id, target_match_id, target_kind,
      target_guest_id, target_external_team_id, rated_group_id,
      calculated_official_observation, calculated_response_count, calculated_response_ids, 'pachangas-rating-v2'
    ) returning id into official_id;
  else
    update public.pachanga_global_rating_evidence
    set official_observation = calculated_official_observation,
        response_count = calculated_response_count,
        response_ids = calculated_response_ids,
        updated_at = now()
    where id = official_id;
  end if;

  if target_kind = 'guest' then
    update public.pachanga_guest_identities
    set provisional_level = (
      select avg(evidence.official_observation) from public.pachanga_global_rating_evidence evidence
      where evidence.guest_identity_id = target_guest_id and evidence.target_kind = 'guest'
    ), updated_at = now()
    where id = target_guest_id;
  elsif target_kind = 'external_team' then
    update public.pachanga_external_teams
    set calibrated_external_level = (
      select avg(evidence.official_observation) from public.pachanga_global_rating_evidence evidence
      where evidence.external_team_id = target_external_team_id and evidence.target_kind = 'external_team'
    ), updated_at = now()
    where id = target_external_team_id;
  end if;

  return jsonb_build_object(
    'responseId', response_id,
    'officialEvidenceId', official_id,
    'officialObservation', calculated_official_observation,
    'responseCount', calculated_response_count
  );
end;
$$;

create or replace function public.issue_pachanga_guest_rating_token_v2(guest_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  guest public.pachanga_guest_identities%rowtype;
  plain_token text := gen_random_uuid()::text || gen_random_uuid()::text;
begin
  select * into guest from public.pachanga_guest_identities where id = guest_id for update;
  if not found then raise exception 'Guest identity not found'; end if;
  if auth.uid() is null or not public.is_pachanga_group_admin(guest.created_by_group_id) then
    raise exception 'Only group admins can issue guest rating tokens';
  end if;
  update public.pachanga_guest_identities
  set claim_token_hash = md5(plain_token), updated_at = now()
  where id = guest.id;
  return plain_token;
end;
$$;

create or replace function public.record_pachanga_guest_team_rating_v2(
  target_group_id uuid,
  target_match_id text,
  guest_id uuid,
  claim_token text,
  comparison text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  guest public.pachanga_guest_identities%rowtype;
  participant public.pachanga_match_rating_participants%rowtype;
  comparison_delta numeric;
  reference_level numeric;
  calculated_observation numeric;
  response_id uuid;
  official_id uuid;
  calculated_official_observation numeric;
  calculated_response_count integer;
  calculated_response_ids uuid[];
begin
  if coalesce(length(claim_token), 0) < 60 then raise exception 'Invalid guest token'; end if;
  select * into guest
  from public.pachanga_guest_identities
  where id = guest_id
    and created_by_group_id = record_pachanga_guest_team_rating_v2.target_group_id
    and claim_token_hash = md5(claim_token)
  for update;
  if not found then raise exception 'Invalid guest token'; end if;

  select * into participant
  from public.pachanga_match_rating_participants
  where group_id = record_pachanga_guest_team_rating_v2.target_group_id
    and match_id = record_pachanga_guest_team_rating_v2.target_match_id
    and guest_identity_id = guest.id
    and attendance_confirmed
    and not was_reserve;
  if not found or not exists (
    select 1 from public.pachanga_match_rating_snapshots snapshot
    where snapshot.group_id = record_pachanga_guest_team_rating_v2.target_group_id
      and snapshot.match_id = record_pachanga_guest_team_rating_v2.target_match_id
      and snapshot.state = 'active'
  ) then raise exception 'Guest must be a real participant in an active finalized match'; end if;

  comparison_delta := public.pachanga_rating_v2_comparison_delta(comparison);
  if comparison_delta is null then raise exception 'Invalid comparison'; end if;
  reference_level := coalesce(
    nullif(participant.card_snapshot ->> 'currentOverall', '')::numeric,
    guest.provisional_level
  );
  if reference_level is null then raise exception 'Guest reference level unavailable'; end if;
  calculated_observation := public.pachanga_rating_v2_clamp(reference_level + comparison_delta);
  perform pg_advisory_xact_lock(
    hashtext(record_pachanga_guest_team_rating_v2.target_group_id::text),
    hashtext(record_pachanga_guest_team_rating_v2.target_match_id || ':host-team')
  );

  select response.id into response_id
  from public.pachanga_global_rating_responses response
  where response.group_id = record_pachanga_guest_team_rating_v2.target_group_id
    and response.match_id = record_pachanga_guest_team_rating_v2.target_match_id
    and response.target_kind = 'host_team'
    and response.actor_guest_identity_id = guest.id
  for update;
  if response_id is null then
    insert into public.pachanga_global_rating_responses(
      group_id, match_id, target_kind, actor_guest_identity_id,
      comparison, delta, reference_level_snapshot, observation, engine_version
    ) values (
      record_pachanga_guest_team_rating_v2.target_group_id,
      record_pachanga_guest_team_rating_v2.target_match_id,
      'host_team', guest.id,
      comparison, comparison_delta, reference_level, calculated_observation, 'pachangas-rating-v2'
    ) returning id into response_id;
  else
    update public.pachanga_global_rating_responses
    set comparison = record_pachanga_guest_team_rating_v2.comparison,
        delta = comparison_delta,
        reference_level_snapshot = reference_level,
        observation = calculated_observation
    where id = response_id;
  end if;

  select avg(response.observation), count(*)::integer, array_agg(response.id order by response.actor_guest_identity_id)
  into calculated_official_observation, calculated_response_count, calculated_response_ids
  from public.pachanga_global_rating_responses response
  where response.group_id = record_pachanga_guest_team_rating_v2.target_group_id
    and response.match_id = record_pachanga_guest_team_rating_v2.target_match_id
    and response.target_kind = 'host_team';

  select evidence.id into official_id
  from public.pachanga_global_rating_evidence evidence
  where evidence.group_id = record_pachanga_guest_team_rating_v2.target_group_id
    and evidence.match_id = record_pachanga_guest_team_rating_v2.target_match_id
    and evidence.target_kind = 'host_team'
  for update;
  if official_id is null then
    insert into public.pachanga_global_rating_evidence(
      group_id, match_id, target_kind, official_observation,
      response_count, response_ids, engine_version
    ) values (
      record_pachanga_guest_team_rating_v2.target_group_id,
      record_pachanga_guest_team_rating_v2.target_match_id,
      'host_team', calculated_official_observation,
      calculated_response_count, calculated_response_ids, 'pachangas-rating-v2'
    ) returning id into official_id;
  else
    update public.pachanga_global_rating_evidence
    set official_observation = calculated_official_observation,
        response_count = calculated_response_count,
        response_ids = calculated_response_ids,
        updated_at = now()
    where id = official_id;
  end if;

  return jsonb_build_object(
    'responseId', response_id,
    'officialEvidenceId', official_id,
    'officialObservation', calculated_official_observation,
    'responseCount', calculated_response_count
  );
end;
$$;

create or replace function public.pachanga_group_level_v2(target_group_id uuid, at_time timestamptz default now())
returns numeric
language sql
security definer
set search_path = public
stable
as $$
  with active_profiles as (
    select
      profile.id,
      profile.calibrated_overall,
      count(participant.match_id) filter (
    where snapshot.finalized_at >= at_time - interval '12 months'
          and snapshot.finalized_at <= at_time
          and participant.attendance_confirmed
          and not participant.was_reserve
          and snapshot.state = 'active'
      ) as appearances,
      max(snapshot.finalized_at) filter (
        where snapshot.finalized_at <= at_time
          and participant.attendance_confirmed
          and not participant.was_reserve
          and snapshot.state = 'active'
      ) as last_appearance
    from public.pachanga_group_members member
    join public.pachanga_player_profiles profile on profile.user_id = member.user_id
    left join public.pachanga_match_rating_participants participant
      on participant.group_id = member.group_id
      and participant.player_profile_id = profile.id
    left join public.pachanga_match_rating_snapshots snapshot
      on snapshot.group_id = participant.group_id
      and snapshot.match_id = participant.match_id
    where member.group_id = target_group_id
      and not profile.inactive
      and profile.calibrated_overall is not null
    group by profile.id, profile.calibrated_overall
  ), habitual as (
    select calibrated_overall
    from active_profiles
    order by appearances desc, last_appearance desc nulls last, id
    limit 11
  )
  select avg(calibrated_overall) from habitual;
$$;

create or replace function public.snapshot_pachanga_match_ratings_v2(
  target_group_id uuid,
  target_match_id text,
  match_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  group_payload jsonb;
  player_entry jsonb;
  player_payload jsonb;
  player_profile public.pachanga_player_profiles%rowtype;
  guest_id uuid;
  player_id text;
  team_side text;
  is_reserve boolean;
  card_snapshot jsonb;
  card_level numeric;
  match_time timestamptz := now();
  group_level numeric;
  lineup_a_level numeric;
  lineup_b_level numeric;
  result jsonb;
begin
  if exists (
    select 1 from public.pachanga_match_rating_snapshots snapshot
    where snapshot.group_id = target_group_id and snapshot.match_id = target_match_id
  ) then
    select snapshot.snapshot into result
    from public.pachanga_match_rating_snapshots snapshot
    where snapshot.group_id = target_group_id and snapshot.match_id = target_match_id;
    return result;
  end if;

  select payload into group_payload from public.pachanga_groups where id = target_group_id;
  if group_payload is null then raise exception 'Group not found'; end if;
  if not (coalesce((match_payload ->> 'closed')::boolean, false) or match_payload ? 'scoreA') then
    raise exception 'Only finalized matches can be snapshotted';
  end if;
  if coalesce(match_payload ->> 'date', '') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}' then
    match_time := (match_payload ->> 'date')::timestamptz;
  end if;

  insert into public.pachanga_match_rating_snapshots(
    group_id, match_id, engine_version, snapshot, finalized_at
  ) values (
    target_group_id, target_match_id, 'pachangas-rating-v2', match_payload, match_time
  );

  for player_entry in
    select value
    from jsonb_array_elements(coalesce(match_payload -> 'players', '[]'::jsonb)) entries(value)
    where value ->> 'status' = 'voy'
  loop
    player_id := player_entry ->> 'playerId';
    select value into player_payload
    from jsonb_array_elements(coalesce(group_payload -> 'players', '[]'::jsonb)) players(value)
    where value ->> 'id' = player_id
    limit 1;

    player_profile := null;
    if coalesce(player_payload ->> 'ownerUserId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select * into player_profile
      from public.pachanga_player_profiles
      where user_id = (player_payload ->> 'ownerUserId')::uuid;
    end if;

    guest_id := null;
    if player_profile.id is null then
      insert into public.pachanga_guest_identities(
        created_by_group_id, source_player_id, display_name, normalized_name, provisional_level, metadata
      ) values (
        target_group_id,
        player_id,
        coalesce(nullif(player_payload ->> 'name', ''), 'Invitado'),
        lower(regexp_replace(coalesce(nullif(player_payload ->> 'name', ''), 'Invitado'), '\s+', ' ', 'g')),
        public.pachanga_rating_v2_clamp(coalesce(nullif(player_payload ->> 'rating', '')::numeric * 10, 50)),
        jsonb_build_object('source', 'match_finalization')
      )
      on conflict (created_by_group_id, source_player_id) where source_player_id is not null
      do update set display_name = excluded.display_name, updated_at = now()
      returning id into guest_id;
    end if;

    team_side := case
      when exists (select 1 from jsonb_array_elements_text(coalesce(match_payload -> 'teamA', '[]'::jsonb)) team(value) where value = player_id) then 'A'
      when exists (select 1 from jsonb_array_elements_text(coalesce(match_payload -> 'teamB', '[]'::jsonb)) team(value) where value = player_id) then 'B'
      else 'external'
    end;
    is_reserve := team_side = 'external';
    card_level := coalesce(
      player_profile.current_overall,
      public.pachanga_rating_v2_clamp(coalesce(nullif(player_payload ->> 'rating', '')::numeric * 10, 50))
    );
    card_snapshot := jsonb_strip_nulls(jsonb_build_object(
      'playerId', player_id,
      'name', player_payload ->> 'name',
      'position', player_payload ->> 'position',
      'ratingDomain', player_profile.rating_domain,
      'baseFacets', player_profile.base_facets,
      'calibratedFacets', player_profile.calibrated_facets,
      'currentFacets', player_profile.current_facets,
      'baseOverall', player_profile.base_overall,
      'calibratedOverall', player_profile.calibrated_overall,
      'currentOverall', card_level,
      'reliability', player_profile.rating_reliability,
      'engineVersion', coalesce(player_profile.rating_engine_version, 'legacy-snapshot')
    ));

    insert into public.pachanga_match_rating_participants(
      group_id, match_id, local_player_id, player_profile_id, guest_identity_id,
      team_side, attendance_confirmed, was_reserve, card_snapshot
    ) values (
      target_group_id, target_match_id, player_id, player_profile.id, guest_id,
      team_side, true, is_reserve, card_snapshot
    );

    if player_profile.id is not null then
      insert into public.pachanga_player_rating_snapshots(
        player_profile_id, group_id, match_id, snapshot_kind,
        base_facets, calibrated_facets, current_facets, current_facet_modifiers,
        base_overall, calibrated_overall, current_overall, reliability,
        evaluator_count, engine_version
      ) values (
        player_profile.id, target_group_id, target_match_id, 'match_finalization',
        player_profile.base_facets, player_profile.calibrated_facets, player_profile.current_facets,
        player_profile.current_facet_modifiers, player_profile.base_overall,
        player_profile.calibrated_overall, player_profile.current_overall,
        player_profile.rating_reliability, player_profile.rating_evaluator_count,
        coalesce(player_profile.rating_engine_version, 'legacy-snapshot')
      );
    end if;
  end loop;

  select avg((participant.card_snapshot ->> 'currentOverall')::numeric)
  into lineup_a_level
  from public.pachanga_match_rating_participants participant
  where participant.group_id = target_group_id and participant.match_id = target_match_id
    and participant.team_side = 'A' and participant.attendance_confirmed and not participant.was_reserve;

  select avg((participant.card_snapshot ->> 'currentOverall')::numeric)
  into lineup_b_level
  from public.pachanga_match_rating_participants participant
  where participant.group_id = target_group_id and participant.match_id = target_match_id
    and participant.team_side = 'B' and participant.attendance_confirmed and not participant.was_reserve;

  group_level := public.pachanga_group_level_v2(target_group_id, match_time);
  result := jsonb_build_object(
    'match', match_payload,
    'groupLevel', group_level,
    'lineupALevel', lineup_a_level,
    'lineupBLevel', lineup_b_level,
    'capturedAt', match_time,
    'engineVersion', 'pachangas-rating-v2'
  );
  update public.pachanga_match_rating_snapshots
  set group_level = (result ->> 'groupLevel')::numeric,
      lineup_a_level = (result ->> 'lineupALevel')::numeric,
      lineup_b_level = (result ->> 'lineupBLevel')::numeric,
      snapshot = result
  where group_id = target_group_id and match_id = target_match_id;
  return result;
end;
$$;

create or replace function public.capture_new_pachanga_match_rating_snapshots_v2()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  next_match jsonb;
  previous_match jsonb;
begin
  update public.pachanga_match_rating_snapshots snapshot
  set state = 'void', voided_at = now(), void_reason = 'Match removed or no longer finalized in the source payload'
  where snapshot.group_id = new.id
    and snapshot.state = 'active'
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(new.payload -> 'matches', '[]'::jsonb)) current_match(value)
      where current_match.value ->> 'id' = snapshot.match_id
        and (coalesce((current_match.value ->> 'closed')::boolean, false) or current_match.value ? 'scoreA')
    );

  for next_match in select value from jsonb_array_elements(coalesce(new.payload -> 'matches', '[]'::jsonb)) entries(value)
  loop
    if coalesce((next_match ->> 'closed')::boolean, false) or next_match ? 'scoreA' then
      select value into previous_match
      from jsonb_array_elements(coalesce(old.payload -> 'matches', '[]'::jsonb)) entries(value)
      where value ->> 'id' = next_match ->> 'id'
      limit 1;
      if previous_match is null
        or not (coalesce((previous_match ->> 'closed')::boolean, false) or previous_match ? 'scoreA')
      then
        perform public.snapshot_pachanga_match_ratings_v2(new.id, next_match ->> 'id', next_match);
      end if;
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists capture_new_pachanga_match_rating_snapshots_v2 on public.pachanga_groups;
create trigger capture_new_pachanga_match_rating_snapshots_v2
after update of payload on public.pachanga_groups
for each row
when (old.payload is distinct from new.payload)
execute function public.capture_new_pachanga_match_rating_snapshots_v2();

drop policy if exists "Members can read V2 individual ratings" on public.pachanga_individual_rating_evidence;
create policy "Members can read V2 individual ratings"
on public.pachanga_individual_rating_evidence for select to authenticated
using (
  (select auth.uid()) in (
    select user_id from public.pachanga_group_members where group_id = pachanga_individual_rating_evidence.group_id
  )
);

drop policy if exists "Members can read V2 rating state history" on public.pachanga_rating_evidence_state_events;
create policy "Members can read V2 rating state history"
on public.pachanga_rating_evidence_state_events for select to authenticated
using (
  exists (
    select 1 from public.pachanga_individual_rating_evidence evidence
    join public.pachanga_group_members member on member.group_id = evidence.group_id
    where evidence.id = pachanga_rating_evidence_state_events.evidence_id
      and member.user_id = (select auth.uid())
  )
);

drop policy if exists "Members can read V2 player snapshots" on public.pachanga_player_rating_snapshots;
create policy "Members can read V2 player snapshots"
on public.pachanga_player_rating_snapshots for select to authenticated
using (
  player_profile_id in (
    select profile.id
    from public.pachanga_player_profiles profile
    where profile.user_id = (select auth.uid())
  )
  or group_id in (
    select group_id from public.pachanga_group_members where user_id = (select auth.uid())
  )
);

drop policy if exists "Members can read V2 match snapshots" on public.pachanga_match_rating_snapshots;
create policy "Members can read V2 match snapshots"
on public.pachanga_match_rating_snapshots for select to authenticated
using (group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid())));

drop policy if exists "Members can read V2 match participant snapshots" on public.pachanga_match_rating_participants;
create policy "Members can read V2 match participant snapshots"
on public.pachanga_match_rating_participants for select to authenticated
using (group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid())));

drop policy if exists "Members can read guest identities" on public.pachanga_guest_identities;
create policy "Members can read guest identities"
on public.pachanga_guest_identities for select to authenticated
using (created_by_group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid())) or linked_user_id = (select auth.uid()));

drop policy if exists "Members can read guest link history" on public.pachanga_guest_link_events;
create policy "Members can read guest link history"
on public.pachanga_guest_link_events for select to authenticated
using (
  user_id = (select auth.uid())
  or guest_identity_id in (
    select guest.id from public.pachanga_guest_identities guest
    where guest.created_by_group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid()))
  )
);

drop policy if exists "Members can read external teams" on public.pachanga_external_teams;
create policy "Members can read external teams"
on public.pachanga_external_teams for select to authenticated
using (created_by_group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid())) or linked_group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid())));

drop policy if exists "Members can read global rating responses" on public.pachanga_global_rating_responses;
create policy "Members can read global rating responses"
on public.pachanga_global_rating_responses for select to authenticated
using (group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid())));

drop policy if exists "Members can read global rating evidence" on public.pachanga_global_rating_evidence;
create policy "Members can read global rating evidence"
on public.pachanga_global_rating_evidence for select to authenticated
using (group_id in (select group_id from public.pachanga_group_members where user_id = (select auth.uid())));

drop policy if exists "Admins can read rating flags" on public.pachanga_rating_flags;
create policy "Admins can read rating flags"
on public.pachanga_rating_flags for select to authenticated
using (group_id is not null and public.is_pachanga_group_admin(group_id));

drop policy if exists "Users can read own legacy rating evidence" on public.pachanga_legacy_rating_evidence;
create policy "Users can read own legacy rating evidence"
on public.pachanga_legacy_rating_evidence for select to authenticated
using (player_profile_id in (select id from public.pachanga_player_profiles where user_id = (select auth.uid())));

revoke all on function public.pachanga_rating_v2_profile_for_group_player(uuid, text) from public, anon, authenticated;
revoke all on function public.pachanga_rating_v2_shared_matches(uuid, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.pachanga_recalculate_player_rating_v2(uuid, uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.get_pachanga_rating_eligibility(uuid, text) to authenticated;
grant execute on function public.record_pachanga_individual_rating_v2(uuid, text, jsonb, uuid) to authenticated;
grant execute on function public.void_pachanga_individual_rating_v2(uuid, text, uuid) to authenticated;
grant execute on function public.create_pachanga_guest_identity_v2(uuid, text, text) to authenticated;
grant execute on function public.link_pachanga_guest_identity_v2(uuid, uuid, text, uuid) to authenticated;
grant execute on function public.reverse_pachanga_guest_link_v2(uuid, text) to authenticated;
grant execute on function public.record_pachanga_global_rating_v2(uuid, text, text, text, uuid, uuid, uuid) to authenticated;
grant execute on function public.issue_pachanga_guest_rating_token_v2(uuid) to authenticated;
grant execute on function public.record_pachanga_guest_team_rating_v2(uuid, text, uuid, text, text) to anon, authenticated;

revoke execute on function public.get_pachanga_rating_eligibility(uuid, text) from public, anon;
revoke execute on function public.record_pachanga_individual_rating_v2(uuid, text, jsonb, uuid) from public, anon;
revoke execute on function public.void_pachanga_individual_rating_v2(uuid, text, uuid) from public, anon;
revoke execute on function public.create_pachanga_guest_identity_v2(uuid, text, text) from public, anon;
revoke execute on function public.link_pachanga_guest_identity_v2(uuid, uuid, text, uuid) from public, anon;
revoke execute on function public.reverse_pachanga_guest_link_v2(uuid, text) from public, anon;
revoke execute on function public.record_pachanga_global_rating_v2(uuid, text, text, text, uuid, uuid, uuid) from public, anon;
revoke execute on function public.issue_pachanga_guest_rating_token_v2(uuid) from public, anon;
revoke execute on function public.record_pachanga_guest_team_rating_v2(uuid, text, uuid, text, text) from public;
