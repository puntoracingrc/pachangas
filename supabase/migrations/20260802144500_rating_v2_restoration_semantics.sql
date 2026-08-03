-- Pachangas IQ rating system V2: restoration reactivates the original opinion.
-- A restoration is an audited state transition, never a newly emitted rating.

alter table public.pachanga_individual_rating_evidence
  add column if not exists opinion_created_at timestamptz,
  add column if not exists restored_at timestamptz;

update public.pachanga_individual_rating_evidence evidence
set opinion_created_at = coalesce(origin.opinion_created_at, origin.created_at, evidence.created_at),
    restored_at = coalesce(evidence.restored_at, evidence.created_at)
from public.pachanga_individual_rating_evidence origin
where evidence.source = 'restored'
  and evidence.previous_evidence_id = origin.id
  and (evidence.opinion_created_at is null or evidence.restored_at is null);

update public.pachanga_individual_rating_evidence
set opinion_created_at = created_at
where opinion_created_at is null;

alter table public.pachanga_individual_rating_evidence
  alter column opinion_created_at set default now(),
  alter column opinion_created_at set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'pachanga_individual_rating_restored_after_opinion_check'
  ) then
    alter table public.pachanga_individual_rating_evidence
      add constraint pachanga_individual_rating_restored_after_opinion_check
      check (restored_at is null or restored_at >= opinion_created_at);
  end if;
end;
$$;

create index if not exists pachanga_individual_rating_last_emitted_idx
  on public.pachanga_individual_rating_evidence(
    evaluator_profile_id,
    target_profile_id,
    opinion_created_at desc
  )
  where source <> 'restored';

-- V2 was not active in production when this migration was authored. This
-- repair still converts any locally-created synthetic active restoration into
-- the original evidence row so staging/repeated migration runs remain sound.
do $$
declare
  synthetic public.pachanga_individual_rating_evidence%rowtype;
  origin public.pachanga_individual_rating_evidence%rowtype;
  transition_at timestamptz;
begin
  for synthetic in
    select evidence.*
    from public.pachanga_individual_rating_evidence evidence
    where evidence.source = 'restored'
      and evidence.state = 'active'
    order by evidence.created_at, evidence.id
  loop
    select evidence.* into origin
    from public.pachanga_individual_rating_evidence evidence
    where evidence.id = synthetic.previous_evidence_id
    for update;
    if origin.id is null then
      continue;
    end if;

    transition_at := coalesce(synthetic.restored_at, synthetic.created_at, clock_timestamp());
    update public.pachanga_individual_rating_evidence
    set state = 'void',
        voided_at = coalesce(voided_at, transition_at),
        void_reason = coalesce(void_reason, 'Synthetic restoration replaced by original evidence')
    where id = synthetic.id;
    insert into public.pachanga_rating_evidence_state_events(
      evidence_id, from_state, to_state, actor_id, reason, created_at
    ) values (
      synthetic.id, 'active', 'void', null,
      'Synthetic restoration replaced by original evidence', transition_at
    );

    update public.pachanga_individual_rating_evidence
    set state = 'active', restored_at = transition_at
    where id = origin.id;
    insert into public.pachanga_rating_evidence_state_events(
      evidence_id, from_state, to_state, actor_id, reason, created_at
    ) values (
      origin.id, origin.state, 'active', null,
      'Original opinion restored during V2 semantics migration', transition_at
    );
  end loop;
end;
$$;

create or replace function public.get_pachanga_rating_eligibility(
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
  evaluator_profile public.pachanga_player_profiles%rowtype;
  target_profile public.pachanga_player_profiles%rowtype;
  last_emitted public.pachanga_individual_rating_evidence%rowtype;
  active_evidence_id uuid;
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

  select evidence.id into active_evidence_id
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile.id
    and evidence.target_profile_id = target_profile.id
    and evidence.state = 'active';

  select evidence.* into last_emitted
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile.id
    and evidence.target_profile_id = target_profile.id
    and evidence.source <> 'restored'
  order by evidence.opinion_created_at desc, evidence.created_at desc, evidence.id desc
  limit 1;

  if last_emitted.id is null then
    return jsonb_build_object(
      'canRate', true,
      'firstRating', true,
      'sharedMatches', 0,
      'requiredMatches', 0,
      'previousRatingAt', null,
      'activeEvidenceId', active_evidence_id
    );
  end if;

  shared_count := public.pachanga_rating_v2_shared_matches(
    current_user_id,
    target_profile.user_id,
    last_emitted.opinion_created_at
  );
  return jsonb_build_object(
    'canRate', shared_count >= 3,
    'firstRating', false,
    'sharedMatches', shared_count,
    'requiredMatches', 3,
    'previousRatingAt', last_emitted.opinion_created_at,
    'previousEvidenceId', last_emitted.id,
    'activeEvidenceId', active_evidence_id
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
  current_evaluator_profile_id uuid;
  target_profile public.pachanga_player_profiles%rowtype;
  own_evidence public.pachanga_individual_rating_evidence%rowtype;
begin
  if current_user_id is null or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Current group membership required';
  end if;
  select profiles.id into current_evaluator_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = current_user_id;
  target_profile := public.pachanga_rating_v2_profile_for_group_player(target_group_id, target_player_id);
  if current_evaluator_profile_id is null or target_profile.id is null then
    return jsonb_build_object(
      'rating', null,
      'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
    );
  end if;

  select evidence.* into own_evidence
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = current_evaluator_profile_id
    and evidence.target_profile_id = target_profile.id
    and evidence.state = 'active'
  limit 1;

  return jsonb_build_object(
    'rating', case when own_evidence.id is null then null else jsonb_build_object(
      'evidenceId', own_evidence.id,
      'comparisons', own_evidence.comparisons,
      'createdAt', own_evidence.opinion_created_at,
      'opinionCreatedAt', own_evidence.opinion_created_at,
      'restoredAt', own_evidence.restored_at,
      'sharedMatchesUsed', own_evidence.shared_matches_used
    ) end,
    'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
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
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  evaluator_profile public.pachanga_player_profiles%rowtype;
  target_profile public.pachanga_player_profiles%rowtype;
  previous_evidence public.pachanga_individual_rating_evidence%rowtype;
  last_emitted public.pachanga_individual_rating_evidence%rowtype;
  existing_evidence public.pachanga_individual_rating_evidence%rowtype;
  facet text;
  comparison text;
  delta numeric;
  reference_facets jsonb;
  applied_deltas jsonb := '{}'::jsonb;
  observations jsonb := '{}'::jsonb;
  shared_count integer := 0;
  emitted_at timestamptz := clock_timestamp();
  next_evidence_id uuid;
  card_result jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if current_user_id is null or not public.is_registered_pachanga_user() then raise exception 'Registered user required'; end if;
  if operation_id is null then raise exception 'Operation id required'; end if;
  if not public.is_pachanga_group_member(target_group_id) then raise exception 'Only members can rate players'; end if;

  select * into evaluator_profile from public.pachanga_player_profiles profiles where profiles.user_id = current_user_id;
  target_profile := public.pachanga_rating_v2_profile_for_group_player(target_group_id, target_player_id);
  if evaluator_profile.id is null or target_profile.id is null then raise exception 'Registered player profiles required'; end if;
  if evaluator_profile.id = target_profile.id then raise exception 'You cannot rate yourself'; end if;
  if target_profile.inactive then raise exception 'Inactive players cannot be rated'; end if;
  if not exists (
    select 1
    from public.pachanga_group_members members
    where members.group_id = target_group_id
      and members.user_id = target_profile.user_id
  ) then
    raise exception 'Target player must be a current group member';
  end if;
  if evaluator_profile.rating_domain <> 'field' or target_profile.rating_domain <> 'field' then
    raise exception 'Goalkeeper comparison engine is not available yet';
  end if;

  perform pg_advisory_xact_lock(hashtext(evaluator_profile.id::text), hashtext(target_profile.id::text));

  select evidence.* into existing_evidence
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile.id
    and evidence.operation_id = record_pachanga_individual_rating_v2.operation_id;
  if existing_evidence.id is not null then
    select groups.payload, groups.payload_revision, groups.updated_at
    into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups groups
    where groups.id = target_group_id;
    return jsonb_build_object(
      'payload', saved_payload,
      'payload_revision', saved_revision,
      'updated_at', saved_updated_at,
      'evidenceId', existing_evidence.id,
      'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
    );
  end if;

  select evidence.* into previous_evidence
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile.id
    and evidence.target_profile_id = target_profile.id
    and evidence.state = 'active'
  for update;

  select evidence.* into last_emitted
  from public.pachanga_individual_rating_evidence evidence
  where evidence.evaluator_profile_id = evaluator_profile.id
    and evidence.target_profile_id = target_profile.id
    and evidence.source <> 'restored'
  order by evidence.opinion_created_at desc, evidence.created_at desc, evidence.id desc
  limit 1;

  if last_emitted.id is not null then
    shared_count := public.pachanga_rating_v2_shared_matches(
      current_user_id,
      target_profile.user_id,
      last_emitted.opinion_created_at
    );
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
    set state = 'superseded', superseded_at = emitted_at
    where id = previous_evidence.id;
    insert into public.pachanga_rating_evidence_state_events(
      evidence_id, from_state, to_state, actor_id, reason, created_at
    ) values (
      previous_evidence.id, 'active', 'superseded', current_user_id,
      'Replaced by a new eligible rating', emitted_at
    );
  end if;

  insert into public.pachanga_individual_rating_evidence (
    evaluator_profile_id, target_profile_id, group_id, operation_id, previous_evidence_id,
    engine_version, evaluator_reference_facets, comparisons, applied_deltas, observations,
    evaluator_confidence_snapshot, shared_matches_used, shared_matches_since,
    opinion_created_at, created_at
  ) values (
    evaluator_profile.id, target_profile.id, target_group_id, operation_id, previous_evidence.id,
    'pachangas-rating-v2', reference_facets, comparisons, applied_deltas, observations,
    public.pachanga_rating_v2_clamp(coalesce(evaluator_profile.rating_reliability, 0)),
    shared_count, last_emitted.opinion_created_at, emitted_at, emitted_at
  ) returning id into next_evidence_id;

  insert into public.pachanga_rating_evidence_state_events(
    evidence_id, from_state, to_state, actor_id, reason, created_at
  ) values (
    next_evidence_id, null, 'active', current_user_id,
    'Individual member comparison', emitted_at
  );

  card_result := public.pachanga_recalculate_player_rating_v2(
    target_profile.id,
    next_evidence_id,
    target_group_id,
    'recalculation'
  );

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
    insert into public.pachanga_rating_flags(
      flag_kind, evaluator_profile_id, target_profile_id, group_id, evidence_ids, metadata
    ) values (
      'reciprocal_maximum', evaluator_profile.id, target_profile.id, target_group_id,
      array[next_evidence_id], jsonb_build_object('informationalOnly', true)
    );
  end if;

  select groups.payload, groups.payload_revision, groups.updated_at
  into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups groups
  where groups.id = target_group_id;
  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at,
    'evidenceId', next_evidence_id,
    'card', card_result,
    'eligibility', public.get_pachanga_rating_eligibility(target_group_id, target_player_id)
  );
end;
$$;

create or replace function public.void_pachanga_individual_rating_v2(
  evidence_id uuid,
  reason text,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  selected public.pachanga_individual_rating_evidence%rowtype;
  evaluator_user_id uuid;
  restored public.pachanga_individual_rating_evidence%rowtype;
  restored_id uuid;
  transition_at timestamptz := clock_timestamp();
  card_result jsonb;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  if operation_id is null or nullif(trim(reason), '') is null then raise exception 'Operation id and reason required'; end if;

  select evidence.* into selected
  from public.pachanga_individual_rating_evidence evidence
  where evidence.id = void_pachanga_individual_rating_v2.evidence_id
  for update;
  if not found then raise exception 'Rating evidence not found'; end if;
  select profiles.user_id into evaluator_user_id
  from public.pachanga_player_profiles profiles
  where profiles.id = selected.evaluator_profile_id;
  if current_user_id <> evaluator_user_id and not public.is_pachanga_group_admin(selected.group_id) then
    raise exception 'Only the evaluator or a group admin can void this rating';
  end if;
  if selected.state = 'void' then
    return jsonb_build_object(
      'evidenceId', selected.id,
      'state', 'void',
      'opinionCreatedAt', selected.opinion_created_at,
      'restoredAt', selected.restored_at
    );
  end if;

  update public.pachanga_individual_rating_evidence
  set state = 'void',
      voided_at = transition_at,
      voided_by = current_user_id,
      void_reason = trim(reason)
  where id = selected.id;
  insert into public.pachanga_rating_evidence_state_events(
    evidence_id, from_state, to_state, actor_id, reason, created_at
  ) values (
    selected.id, selected.state, 'void', current_user_id, trim(reason), transition_at
  );

  if selected.state = 'active' then
    select evidence.* into restored
    from public.pachanga_individual_rating_evidence evidence
    where evidence.evaluator_profile_id = selected.evaluator_profile_id
      and evidence.target_profile_id = selected.target_profile_id
      and evidence.state = 'superseded'
      and evidence.source <> 'restored'
      and evidence.id <> selected.id
    order by
      (evidence.id = selected.previous_evidence_id) desc,
      evidence.opinion_created_at desc,
      evidence.id desc
    limit 1
    for update;

    if restored.id is not null then
      update public.pachanga_individual_rating_evidence
      set state = 'active', restored_at = transition_at
      where id = restored.id;
      restored_id := restored.id;
      insert into public.pachanga_rating_evidence_state_events(
        evidence_id, from_state, to_state, actor_id, reason, created_at
      ) values (
        restored.id, 'superseded', 'active', current_user_id,
        'Original opinion restored after voiding a newer rating', transition_at
      );
    end if;
  end if;

  card_result := public.pachanga_recalculate_player_rating_v2(
    selected.target_profile_id,
    restored_id,
    selected.group_id,
    'recalculation'
  );
  return jsonb_build_object(
    'evidenceId', selected.id,
    'state', 'void',
    'restoredEvidenceId', restored_id,
    'opinionCreatedAt', selected.opinion_created_at,
    'restoredAt', transition_at,
    'card', card_result
  );
end;
$$;

revoke all on function public.get_pachanga_rating_eligibility(uuid, text) from public, anon;
revoke all on function public.get_my_pachanga_rating_v2(uuid, text) from public, anon;
revoke all on function public.record_pachanga_individual_rating_v2(uuid, text, jsonb, uuid)
  from public, anon, authenticated;
revoke all on function public.void_pachanga_individual_rating_v2(uuid, text, uuid)
  from public, anon, authenticated;

grant execute on function public.get_pachanga_rating_eligibility(uuid, text) to authenticated;
grant execute on function public.get_my_pachanga_rating_v2(uuid, text) to authenticated;
