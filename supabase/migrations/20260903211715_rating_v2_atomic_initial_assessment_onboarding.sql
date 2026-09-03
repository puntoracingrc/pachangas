-- Rating V2: create the initial assessment and universal player profile atomically.

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
set search_path = pg_catalog
as $$
declare
  existing_assessment public.pachanga_player_assessments%rowtype;
  initial_assessment public.pachanga_player_assessments%rowtype;
  current_profile public.pachanga_player_profiles%rowtype;
  created_assessment_id uuid;
  target_facets jsonb;
  v2_facets jsonb;
  v2_current_modifiers jsonb;
  target_rating numeric;
  target_reliability numeric;
  facet_key text;
  facet_value numeric;
  completed_at timestamptz := pg_catalog.now();
  next_vote jsonb;
  next_summary jsonb;
  operation_response jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if p_actor_user_id is null or p_operation_id is null then
    raise exception 'Actor and operation id required';
  end if;
  if p_target_group_id is null or nullif(pg_catalog.btrim(coalesce(p_target_player_id, '')), '') is null then
    raise exception 'Group and player id required';
  end if;
  if p_assessment_kind not in ('initial', 'advanced') then
    raise exception 'Invalid assessment kind';
  end if;
  if pg_catalog.jsonb_typeof(p_assessment_input) <> 'object'
    or pg_catalog.jsonb_typeof(p_assessment_result) <> 'object' then
    raise exception 'Invalid shared-engine assessment payload';
  end if;
  if coalesce(p_assessment_result ->> 'engineVersion', '') <> 'football-rating-v1' then
    raise exception 'Unsupported assessment engine';
  end if;
  if nullif(pg_catalog.btrim(coalesce(p_assessment_result ->> 'questionnaireVersion', '')), '') is null
    or nullif(pg_catalog.btrim(coalesce(p_assessment_result ->> 'position', '')), '') is null then
    raise exception 'Invalid shared-engine assessment result';
  end if;
  if not exists (
    select 1
    from public.pachanga_group_members member
    where member.group_id = p_target_group_id
      and member.user_id = p_actor_user_id
  ) then
    raise exception 'Only current group members can complete assessments';
  end if;

  target_facets := p_assessment_result -> 'facets';
  v2_facets := p_assessment_result -> 'v2Facets';
  v2_current_modifiers := p_assessment_result -> 'v2CurrentModifiers';
  if pg_catalog.jsonb_typeof(target_facets) <> 'object'
    or pg_catalog.jsonb_typeof(v2_facets) <> 'object'
    or pg_catalog.jsonb_typeof(v2_current_modifiers) <> 'object' then
    raise exception 'Invalid shared-engine assessment result';
  end if;

  begin
    target_rating := nullif(p_assessment_result ->> 'rating', '')::numeric;
    target_reliability := nullif(p_assessment_result ->> 'reliability', '')::numeric;
  exception
    when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'Invalid shared-engine assessment result';
  end;
  if target_rating is null
    or target_rating::text = 'NaN'
    or target_rating < 1
    or target_rating > 10
    or target_reliability is null
    or target_reliability::text = 'NaN'
    or target_reliability < 0
    or target_reliability > 100 then
    raise exception 'Invalid shared-engine assessment result';
  end if;

  foreach facet_key in array array['ritmo', 'tiro', 'pase', 'regate', 'defensa', 'fisico']
  loop
    begin
      facet_value := nullif(target_facets ->> facet_key, '')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid shared-engine assessment result';
    end;
    if facet_value is null
      or facet_value::text = 'NaN'
      or facet_value < 0
      or facet_value > 10 then
      raise exception 'Invalid shared-engine assessment result';
    end if;
  end loop;

  foreach facet_key in array array['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical']
  loop
    begin
      facet_value := nullif(v2_facets ->> facet_key, '')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid shared-engine assessment result';
    end;
    if facet_value is null
      or facet_value::text = 'NaN'
      or facet_value < 0
      or facet_value > 100 then
      raise exception 'Invalid shared-engine assessment result';
    end if;

    begin
      facet_value := nullif(v2_current_modifiers ->> facet_key, '')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid shared-engine assessment result';
    end;
    if facet_value is null
      or facet_value::text = 'NaN'
      or facet_value < -100
      or facet_value > 100 then
      raise exception 'Invalid shared-engine assessment result';
    end if;
  end loop;

  perform pg_catalog.set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_actor_user_id::text),
    pg_catalog.hashtext('pachanga_' || p_assessment_kind || '_assessment_v2')
  );

  select *
  into existing_assessment
  from public.pachanga_player_assessments assessment
  where assessment.user_id = p_actor_user_id
    and assessment.assessment_kind = p_assessment_kind
  for update;

  if existing_assessment.id is not null then
    if existing_assessment.idempotency_key <> p_operation_id then
      raise exception '% player assessment already completed', pg_catalog.initcap(p_assessment_kind);
    end if;
    if existing_assessment.input is distinct from p_assessment_input then
      raise exception 'Operation id was already used with a different assessment payload'
        using errcode = 'PT409';
    end if;

    select groups.payload, groups.payload_revision, groups.updated_at
    into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups groups
    where groups.id = p_target_group_id;

    return pg_catalog.jsonb_build_object(
      'payload', saved_payload,
      'payload_revision', saved_revision,
      'updated_at', saved_updated_at
    );
  end if;

  if p_assessment_kind = 'initial' then
    insert into public.pachanga_player_assessments(
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
    ) values (
      p_actor_user_id,
      null,
      p_assessment_kind,
      p_assessment_result ->> 'engineVersion',
      p_assessment_result ->> 'questionnaireVersion',
      p_operation_id,
      p_assessment_input,
      p_assessment_result,
      target_rating,
      target_facets,
      target_reliability,
      completed_at
    )
    returning id into created_assessment_id;

    perform public.upsert_pachanga_own_player_profile(
      p_target_group_id,
      p_target_player_id,
      pg_catalog.jsonb_build_object(
        'position', p_assessment_result ->> 'position',
        'outfieldPosition', p_assessment_result ->> 'position'
      )
    );
  else
    select *
    into initial_assessment
    from public.pachanga_player_assessments assessment
    where assessment.user_id = p_actor_user_id
      and assessment.assessment_kind = 'initial'
    for update;

    if initial_assessment.id is null then
      raise exception 'Initial player assessment is required';
    end if;
  end if;

  select *
  into current_profile
  from public.pachanga_player_profiles profile
  where profile.user_id = p_actor_user_id
  for update;

  if current_profile.id is null then
    raise exception 'Player profile not found';
  end if;
  if p_assessment_kind = 'advanced' and not exists (
    select 1
    from public.pachanga_groups groups
    cross join lateral pg_catalog.jsonb_array_elements(
      coalesce(groups.payload -> 'players', '[]'::jsonb)
    ) player(value)
    where groups.id = p_target_group_id
      and player.value ->> 'id' = p_target_player_id
      and player.value ->> 'ownerUserId' = p_actor_user_id::text
  ) then
    raise exception 'You can only assess your own player profile';
  end if;

  if p_assessment_kind = 'initial' then
    update public.pachanga_player_assessments assessment
    set player_profile_id = current_profile.id
    where assessment.id = created_assessment_id;
  else
    insert into public.pachanga_player_assessments(
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
    ) values (
      p_actor_user_id,
      current_profile.id,
      p_assessment_kind,
      p_assessment_result ->> 'engineVersion',
      p_assessment_result ->> 'questionnaireVersion',
      p_operation_id,
      p_assessment_input,
      p_assessment_result,
      target_rating,
      target_facets,
      target_reliability,
      completed_at
    )
    returning id into created_assessment_id;
  end if;

  next_vote := pg_catalog.jsonb_build_object(
    'id', pg_catalog.gen_random_uuid()::text,
    'voterId', p_actor_user_id::text,
    'voterName', case p_assessment_kind when 'initial' then 'Test inicial' else 'Test avanzado' end,
    'ratingRole', case when current_profile.goalkeeper_only then 'goalkeeper' else 'field' end,
    'matchCount', 0,
    'createdAt', pg_catalog.to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source', case p_assessment_kind when 'initial' then 'initialAssessment' else 'advancedAssessment' end,
    'facets', target_facets
  );
  next_summary := coalesce(current_profile.assessment_summary, '{}'::jsonb)
    || pg_catalog.jsonb_build_object(
      p_assessment_kind,
      public.pachanga_assessment_summary_item(p_assessment_result, completed_at)
    );

  update public.pachanga_player_profiles profile
  set rating_domain = case when current_profile.goalkeeper_only then 'goalkeeper_legacy' else 'field' end,
      rating = target_rating,
      ratings = case when p_assessment_kind = 'initial' then '[]'::jsonb else profile.ratings end,
      rating_votes = public.pachanga_assessment_without_self_votes(profile.rating_votes, p_actor_user_id)
        || pg_catalog.jsonb_build_array(next_vote),
      assessment_summary = next_summary,
      position = p_assessment_result ->> 'position',
      outfield_position = p_assessment_result ->> 'position',
      base_facets = v2_facets,
      current_facet_modifiers = v2_current_modifiers,
      rating_reliability = target_reliability,
      rating_engine_version = case
        when current_profile.goalkeeper_only then 'goalkeeper-legacy-pending'
        else 'pachangas-rating-v2'
      end,
      profile_version = profile.profile_version + 1,
      updated_at = pg_catalog.now()
  where profile.id = current_profile.id;

  perform public.pachanga_recalculate_player_rating_v2(
    current_profile.id,
    null,
    p_target_group_id,
    'assessment'
  );
  perform public.sync_pachanga_player_profile_to_groups(current_profile.id);

  select groups.payload, groups.payload_revision, groups.updated_at
  into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups groups
  where groups.id = p_target_group_id;

  perform public.record_pachanga_group_event(
    p_target_group_id,
    null,
    'player_' || p_assessment_kind || '_assessment_v2_completed',
    pg_catalog.jsonb_build_object(
      'playerProfileId', current_profile.id,
      'rating', target_rating,
      'payloadRevision', saved_revision
    ),
    p_operation_id,
    false
  );

  operation_response := pg_catalog.jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );
  return public.remember_pachanga_operation(
    p_target_group_id,
    p_operation_id,
    'player_' || p_assessment_kind || '_assessment_v2_completed',
    operation_response
  );
end;
$$;

revoke all on function public.persist_pachanga_player_assessment_v2(
  uuid, uuid, text, text, jsonb, jsonb, uuid
) from public, anon, authenticated, service_role;

create or replace function public.persist_pachanga_player_assessment_authoritative_v2_impl(
  p_actor_user_id uuid,
  p_target_group_id uuid,
  p_target_player_id text,
  p_assessment_kind text,
  p_assessment_input jsonb,
  p_assessment_result jsonb,
  p_operation_id uuid,
  p_expected_revision bigint,
  p_client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  legacy_result jsonb;
  final_response jsonb;
  request_fingerprint text;
  stored_fingerprint text;
  legacy_replay_matches boolean;
  authoritative_metadata jsonb;
begin
  if p_actor_user_id is null or p_operation_id is null or p_expected_revision is null then
    raise exception 'Actor, operation id and expected revision required';
  end if;
  if not exists (
    select 1
    from public.pachanga_group_members members
    where members.group_id = p_target_group_id
      and members.user_id = p_actor_user_id
  ) then
    raise exception 'Current group membership required';
  end if;

  request_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(
        pg_catalog.jsonb_build_object(
          'actorUserId', p_actor_user_id,
          'groupId', p_target_group_id,
          'playerId', p_target_player_id,
          'assessmentKind', p_assessment_kind,
          'assessmentInput', p_assessment_input
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
  authoritative_metadata := (
    case
      when pg_catalog.jsonb_typeof(p_client_metadata) = 'object' then p_client_metadata
      else '{}'::jsonb
    end - 'assessmentRequestFingerprint'
  ) || pg_catalog.jsonb_build_object('assessmentRequestFingerprint', request_fingerprint);

  replay := public.pachanga_operation_replay_v2(
    p_target_group_id,
    p_operation_id,
    p_actor_user_id
  );
  if replay is not null then
    select receipts.client_metadata ->> 'assessmentRequestFingerprint'
    into stored_fingerprint
    from public.pachanga_operation_receipts receipts
    where receipts.group_id = p_target_group_id
      and receipts.operation_id = p_operation_id;

    if stored_fingerprint is null then
      select exists (
        select 1
        from public.pachanga_player_assessments assessment
        where assessment.user_id = p_actor_user_id
          and assessment.idempotency_key = p_operation_id
          and assessment.assessment_kind = p_assessment_kind
          and assessment.input = p_assessment_input
      )
      into legacy_replay_matches;
    else
      legacy_replay_matches := stored_fingerprint = request_fingerprint;
    end if;

    if not coalesce(legacy_replay_matches, false) then
      raise exception 'Operation id was already used with a different assessment payload'
        using errcode = 'PT409';
    end if;
    return replay;
  end if;

  select *
  into current_group
  from public.pachanga_groups groups
  where groups.id = p_target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  -- A concurrent identical request can finish while this call waits for the
  -- group lock. Recheck the receipt before treating its revision as stale.
  replay := public.pachanga_operation_replay_v2(
    p_target_group_id,
    p_operation_id,
    p_actor_user_id
  );
  if replay is not null then
    select receipts.client_metadata ->> 'assessmentRequestFingerprint'
    into stored_fingerprint
    from public.pachanga_operation_receipts receipts
    where receipts.group_id = p_target_group_id
      and receipts.operation_id = p_operation_id;

    if stored_fingerprint is null then
      select exists (
        select 1
        from public.pachanga_player_assessments assessment
        where assessment.user_id = p_actor_user_id
          and assessment.idempotency_key = p_operation_id
          and assessment.assessment_kind = p_assessment_kind
          and assessment.input = p_assessment_input
      )
      into legacy_replay_matches;
    else
      legacy_replay_matches := stored_fingerprint = request_fingerprint;
    end if;

    if not coalesce(legacy_replay_matches, false) then
      raise exception 'Operation id was already used with a different assessment payload'
        using errcode = 'PT409';
    end if;
    return replay;
  end if;

  if current_group.payload_revision <> p_expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.'
      using errcode = 'PT409';
  end if;

  legacy_result := public.persist_pachanga_player_assessment_v2(
    p_actor_user_id,
    p_target_group_id,
    p_target_player_id,
    p_assessment_kind,
    p_assessment_input,
    p_assessment_result,
    p_operation_id
  );
  final_response := public.pachanga_authoritative_response_v2(
    p_target_group_id,
    p_operation_id,
    'player_' || p_assessment_kind || '_assessment_authoritative_v2',
    p_expected_revision,
    '{}'::jsonb,
    authoritative_metadata
  );

  update public.pachanga_operation_receipts receipts
  set user_id = p_actor_user_id
  where receipts.group_id = p_target_group_id
    and receipts.operation_id = p_operation_id
    and receipts.user_id is null;

  return final_response;
end;
$$;

revoke all on function public.persist_pachanga_player_assessment_authoritative_v2_impl(
  uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb
) from public, anon, authenticated, service_role;

comment on function public.persist_pachanga_player_assessment_v2(
  uuid, uuid, text, text, jsonb, jsonb, uuid
) is
  'Internal Rating V2 authority. Initial assessment and universal profile commit atomically.';

comment on function public.persist_pachanga_player_assessment_authoritative_v2_impl(
  uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb
) is
  'Server-only Rating V2 assessment authority with revision locks and payload-bound idempotency.';
