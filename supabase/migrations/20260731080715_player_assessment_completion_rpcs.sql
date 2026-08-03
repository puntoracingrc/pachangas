create or replace function public.pachanga_assessment_without_self_votes(votes jsonb, target_user_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(value order by ordinality), '[]'::jsonb)
  from jsonb_array_elements(coalesce(votes, '[]'::jsonb)) with ordinality as vote(value, ordinality)
  where not (
    vote.value ->> 'voterId' = target_user_id::text
    and vote.value ->> 'source' in ('initialAssessment', 'advancedAssessment')
  );
$$;

create or replace function public.pachanga_assessment_summary_item(assessment_result jsonb, completed_at timestamptz)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'completedAt', to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'engineVersion', assessment_result ->> 'engineVersion',
    'questionnaireVersion', assessment_result ->> 'questionnaireVersion',
    'rating', (assessment_result ->> 'rating')::numeric,
    'facets', assessment_result -> 'facets',
    'reliability', nullif(assessment_result ->> 'reliability', '')::numeric,
    'primaryPosition', assessment_result ->> 'primaryPosition'
  ));
$$;

create or replace function public.complete_pachanga_player_initial_assessment(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
  assessment_input jsonb,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  existing_assessment public.pachanga_player_assessments%rowtype;
  assessment_result jsonb;
  completed_at timestamptz := now();
  target_rating numeric;
  target_facets jsonb;
  next_vote jsonb;
  next_patch jsonb;
  global_profile_id uuid;
  current_profile public.pachanga_player_profiles%rowtype;
  next_summary jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  operation_response jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if operation_id is null then
    raise exception 'Operation id required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can complete player assessments';
  end if;

  perform pg_advisory_xact_lock(hashtext(current_user_id::text), hashtext('pachanga_initial_assessment'));

  select * into existing_assessment
  from public.pachanga_player_assessments
  where user_id = current_user_id
    and assessment_kind = 'initial'
  for update;

  if found then
    if existing_assessment.idempotency_key <> operation_id then
      raise exception 'Initial player assessment already completed';
    end if;

    select payload, payload_revision, updated_at
    into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups
    where id = target_group_id;

    return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  end if;

  assessment_result := public.calculate_pachanga_initial_assessment(assessment_input);
  target_rating := public.pachanga_assessment_clamp((assessment_result ->> 'rating')::numeric, 1, 10);
  target_facets := assessment_result -> 'facets';

  insert into public.pachanga_player_assessments (
    user_id,
    assessment_kind,
    engine_version,
    questionnaire_version,
    idempotency_key,
    input,
    result,
    rating,
    facet_ratings,
    reliability,
    completed_at
  )
  values (
    current_user_id,
    'initial',
    assessment_result ->> 'engineVersion',
    assessment_result ->> 'questionnaireVersion',
    operation_id,
    assessment_input,
    assessment_result,
    target_rating,
    target_facets,
    nullif(assessment_result ->> 'reliability', '')::numeric,
    completed_at
  );

  next_patch := coalesce(player_patch, '{}'::jsonb) || jsonb_build_object(
    'position', assessment_result ->> 'position',
    'outfieldPosition', assessment_result ->> 'position'
  );

  perform public.upsert_pachanga_own_player_profile(target_group_id, target_player_id, next_patch);

  select * into current_profile
  from public.pachanga_player_profiles
  where user_id = current_user_id
  for update;

  if not found then
    raise exception 'Player profile was not created';
  end if;

  global_profile_id := current_profile.id;
  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', 'Test inicial',
    'ratingRole', case when current_profile.goalkeeper_only then 'goalkeeper' else 'field' end,
    'matchCount', 0,
    'createdAt', to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source', 'initialAssessment',
    'facets', target_facets
  );
  next_summary := coalesce(current_profile.assessment_summary, '{}'::jsonb)
    || jsonb_build_object('initial', public.pachanga_assessment_summary_item(assessment_result, completed_at));

  update public.pachanga_player_profiles
  set rating = target_rating,
      ratings = '[]'::jsonb,
      rating_votes = public.pachanga_assessment_without_self_votes(rating_votes, current_user_id) || jsonb_build_array(next_vote),
      assessment_summary = next_summary,
      position = assessment_result ->> 'position',
      outfield_position = assessment_result ->> 'position',
      profile_version = profile_version + 1,
      updated_at = now()
  where id = global_profile_id;

  update public.pachanga_player_assessments
  set player_profile_id = global_profile_id
  where user_id = current_user_id
    and assessment_kind = 'initial';

  perform public.sync_pachanga_player_profile_to_groups(global_profile_id);

  select payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups
  where id = target_group_id;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'player_initial_assessment_completed',
    jsonb_build_object('playerProfileId', global_profile_id, 'rating', target_rating, 'payloadRevision', saved_revision),
    operation_id,
    false
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_id, 'player_initial_assessment_completed', operation_response);
end;
$$;

create or replace function public.complete_pachanga_player_advanced_assessment(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
  assessment_input jsonb,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  initial_assessment public.pachanga_player_assessments%rowtype;
  existing_assessment public.pachanga_player_assessments%rowtype;
  assessment_result jsonb;
  completed_at timestamptz := now();
  target_rating numeric;
  target_facets jsonb;
  next_vote jsonb;
  current_group public.pachanga_groups%rowtype;
  selected_player jsonb;
  current_profile public.pachanga_player_profiles%rowtype;
  next_summary jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  operation_response jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if operation_id is null then
    raise exception 'Operation id required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can complete player assessments';
  end if;

  perform pg_advisory_xact_lock(hashtext(current_user_id::text), hashtext('pachanga_advanced_assessment'));

  select * into existing_assessment
  from public.pachanga_player_assessments
  where user_id = current_user_id
    and assessment_kind = 'advanced'
  for update;

  if found then
    if existing_assessment.idempotency_key <> operation_id then
      raise exception 'Advanced player assessment already completed';
    end if;

    select payload, payload_revision, updated_at
    into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups
    where id = target_group_id;

    return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  end if;

  select * into initial_assessment
  from public.pachanga_player_assessments
  where user_id = current_user_id
    and assessment_kind = 'initial'
  for update;

  if not found then
    raise exception 'Initial player assessment is required before the advanced assessment';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null or coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only complete the advanced assessment for your own player profile';
  end if;

  select * into current_profile
  from public.pachanga_player_profiles
  where user_id = current_user_id
  for update;

  if not found then
    raise exception 'Player profile not found';
  end if;

  assessment_result := public.calculate_pachanga_advanced_assessment(assessment_input, initial_assessment.result);
  target_rating := public.pachanga_assessment_clamp((assessment_result ->> 'rating')::numeric, 1, 10);
  target_facets := assessment_result -> 'facets';

  insert into public.pachanga_player_assessments (
    user_id,
    player_profile_id,
    assessment_kind,
    engine_version,
    questionnaire_version,
    idempotency_key,
    input,
    result,
    rating,
    facet_ratings,
    reliability,
    completed_at
  )
  values (
    current_user_id,
    current_profile.id,
    'advanced',
    assessment_result ->> 'engineVersion',
    assessment_result ->> 'questionnaireVersion',
    operation_id,
    assessment_input,
    assessment_result,
    target_rating,
    target_facets,
    nullif(assessment_result ->> 'reliability', '')::numeric,
    completed_at
  );

  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', 'Test avanzado',
    'ratingRole', case when current_profile.goalkeeper_only then 'goalkeeper' else 'field' end,
    'matchCount', 0,
    'createdAt', to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source', 'advancedAssessment',
    'facets', target_facets
  );
  next_summary := coalesce(current_profile.assessment_summary, '{}'::jsonb)
    || jsonb_build_object('advanced', public.pachanga_assessment_summary_item(assessment_result, completed_at));

  update public.pachanga_player_profiles
  set rating = target_rating,
      rating_votes = public.pachanga_assessment_without_self_votes(rating_votes, current_user_id) || jsonb_build_array(next_vote),
      assessment_summary = next_summary,
      profile_version = profile_version + 1,
      updated_at = now()
  where id = current_profile.id;

  perform public.sync_pachanga_player_profile_to_groups(current_profile.id);

  select payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups
  where id = target_group_id;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'player_advanced_assessment_completed',
    jsonb_build_object('playerProfileId', current_profile.id, 'rating', target_rating, 'payloadRevision', saved_revision),
    operation_id,
    false
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_id, 'player_advanced_assessment_completed', operation_response);
end;
$$;
