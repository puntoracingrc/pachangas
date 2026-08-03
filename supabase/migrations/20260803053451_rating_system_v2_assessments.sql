-- Pachangas IQ rating system V2: persist results calculated by the shared TypeScript engine.

create or replace function public.persist_pachanga_player_assessment_v2(
  p_actor_user_id uuid,
  p_target_group_id uuid,
  p_target_player_id text,
  p_assessment_kind text,
  p_assessment_input jsonb,
  p_assessment_result jsonb,
  p_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_assessment public.pachanga_player_assessments%rowtype;
  initial_assessment public.pachanga_player_assessments%rowtype;
  current_profile public.pachanga_player_profiles%rowtype;
  target_facets jsonb;
  v2_facets jsonb;
  v2_current_modifiers jsonb;
  target_rating numeric;
  completed_at timestamptz := now();
  next_vote jsonb;
  next_summary jsonb;
  operation_response jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if p_actor_user_id is null or p_operation_id is null then raise exception 'Actor and operation id required'; end if;
  if p_assessment_kind not in ('initial', 'advanced') then raise exception 'Invalid assessment kind'; end if;
  if coalesce(p_assessment_result ->> 'engineVersion', '') <> 'football-rating-v1' then raise exception 'Unsupported assessment engine'; end if;
  if not exists (
    select 1 from public.pachanga_group_members member
    where member.group_id = p_target_group_id and member.user_id = p_actor_user_id
  ) then raise exception 'Only current group members can complete assessments'; end if;

  perform set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  perform pg_advisory_xact_lock(hashtext(p_actor_user_id::text), hashtext('pachanga_' || p_assessment_kind || '_assessment_v2'));

  select * into existing_assessment
  from public.pachanga_player_assessments assessment
  where assessment.user_id = p_actor_user_id and assessment.assessment_kind = p_assessment_kind
  for update;
  if existing_assessment.id is not null then
    if existing_assessment.idempotency_key <> p_operation_id then
      raise exception '% player assessment already completed', initcap(p_assessment_kind);
    end if;
    select payload, payload_revision, updated_at into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups where id = p_target_group_id;
    return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  end if;

  if p_assessment_kind = 'initial' then
    perform public.upsert_pachanga_own_player_profile(
      p_target_group_id,
      p_target_player_id,
      jsonb_build_object(
        'position', p_assessment_result ->> 'position',
        'outfieldPosition', p_assessment_result ->> 'position'
      )
    );
  else
    select * into initial_assessment
    from public.pachanga_player_assessments assessment
    where assessment.user_id = p_actor_user_id and assessment.assessment_kind = 'initial'
    for update;
    if initial_assessment.id is null then raise exception 'Initial player assessment is required'; end if;
  end if;

  select * into current_profile
  from public.pachanga_player_profiles profile
  where profile.user_id = p_actor_user_id
  for update;
  if current_profile.id is null then raise exception 'Player profile not found'; end if;
  if p_assessment_kind = 'advanced' and not exists (
    select 1
    from public.pachanga_groups groups
    cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) player(value)
    where groups.id = p_target_group_id
      and player.value ->> 'id' = p_target_player_id
      and player.value ->> 'ownerUserId' = p_actor_user_id::text
  ) then raise exception 'You can only assess your own player profile'; end if;

  target_rating := public.pachanga_rating_v2_clamp((p_assessment_result ->> 'rating')::numeric, 1, 10);
  target_facets := p_assessment_result -> 'facets';
  v2_facets := p_assessment_result -> 'v2Facets';
  v2_current_modifiers := p_assessment_result -> 'v2CurrentModifiers';
  if jsonb_typeof(target_facets) <> 'object'
    or jsonb_typeof(v2_facets) <> 'object'
    or jsonb_typeof(v2_current_modifiers) <> 'object'
    or not (v2_facets ? 'pace')
    or not (v2_current_modifiers ? 'pace') then
    raise exception 'Invalid shared-engine assessment result';
  end if;

  insert into public.pachanga_player_assessments(
    user_id, player_profile_id, assessment_kind, engine_version, questionnaire_version,
    idempotency_key, input, result, rating, facet_ratings, reliability, completed_at
  ) values (
    p_actor_user_id, current_profile.id, p_assessment_kind,
    p_assessment_result ->> 'engineVersion', p_assessment_result ->> 'questionnaireVersion',
    p_operation_id, p_assessment_input, p_assessment_result, target_rating, target_facets,
    public.pachanga_rating_v2_clamp((p_assessment_result ->> 'reliability')::numeric), completed_at
  );

  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', p_actor_user_id::text,
    'voterName', case p_assessment_kind when 'initial' then 'Test inicial' else 'Test avanzado' end,
    'ratingRole', case when current_profile.goalkeeper_only then 'goalkeeper' else 'field' end,
    'matchCount', 0,
    'createdAt', to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source', case p_assessment_kind when 'initial' then 'initialAssessment' else 'advancedAssessment' end,
    'facets', target_facets
  );
  next_summary := coalesce(current_profile.assessment_summary, '{}'::jsonb)
    || jsonb_build_object(p_assessment_kind, public.pachanga_assessment_summary_item(p_assessment_result, completed_at));

  update public.pachanga_player_profiles
  set rating_domain = case when current_profile.goalkeeper_only then 'goalkeeper_legacy' else 'field' end,
      rating = target_rating,
      ratings = case when p_assessment_kind = 'initial' then '[]'::jsonb else ratings end,
      rating_votes = public.pachanga_assessment_without_self_votes(rating_votes, p_actor_user_id) || jsonb_build_array(next_vote),
      assessment_summary = next_summary,
      position = p_assessment_result ->> 'position',
      outfield_position = p_assessment_result ->> 'position',
      base_facets = v2_facets,
      current_facet_modifiers = v2_current_modifiers,
      rating_reliability = public.pachanga_rating_v2_clamp((p_assessment_result ->> 'reliability')::numeric),
      rating_engine_version = case when current_profile.goalkeeper_only then 'goalkeeper-legacy-pending' else 'pachangas-rating-v2' end,
      profile_version = profile_version + 1,
      updated_at = now()
  where id = current_profile.id;

  perform public.pachanga_recalculate_player_rating_v2(current_profile.id, null, p_target_group_id, 'assessment');
  perform public.sync_pachanga_player_profile_to_groups(current_profile.id);
  select payload, payload_revision, updated_at into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups where id = p_target_group_id;

  perform public.record_pachanga_group_event(
    p_target_group_id, null, 'player_' || p_assessment_kind || '_assessment_v2_completed',
    jsonb_build_object('playerProfileId', current_profile.id, 'rating', target_rating, 'payloadRevision', saved_revision),
    p_operation_id, false
  );
  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(
    p_target_group_id, p_operation_id, 'player_' || p_assessment_kind || '_assessment_v2_completed', operation_response
  );
end;
$$;

revoke all on function public.persist_pachanga_player_assessment_v2(uuid, uuid, text, text, jsonb, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.persist_pachanga_player_assessment_v2(uuid, uuid, text, text, jsonb, jsonb, uuid)
  to service_role;
