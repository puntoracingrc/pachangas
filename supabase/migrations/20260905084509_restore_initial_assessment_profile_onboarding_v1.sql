-- Restore the existing Rating V2 initial assessment as universal-profile onboarding.

set lock_timeout = '5s';
set statement_timeout = '120s';

create schema if not exists private;

create sequence if not exists private.pachanga_player_assessment_self_sequence_v1;
revoke all on sequence private.pachanga_player_assessment_self_sequence_v1 from public, anon, authenticated, service_role;

create table if not exists private.pachanga_player_assessment_self_receipts_v1 (
  user_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null,
  assessment_kind text not null check (assessment_kind in ('initial', 'advanced')),
  request_fingerprint text not null,
  expected_revision bigint not null check (expected_revision >= 0),
  confirmed_revision bigint not null check (confirmed_revision >= 1),
  server_sequence bigint not null default nextval('private.pachanga_player_assessment_self_sequence_v1'),
  response jsonb not null check (jsonb_typeof(response) = 'object'),
  client_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(client_metadata) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (user_id, operation_id),
  unique (server_sequence)
);

create table if not exists private.pachanga_player_assessment_self_events_v1 (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  assessment_kind text not null check (assessment_kind in ('initial', 'advanced')),
  operation_id uuid not null,
  expected_revision bigint not null check (expected_revision >= 0),
  confirmed_revision bigint not null check (confirmed_revision >= 1),
  server_sequence bigint not null,
  event_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(event_payload) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  unique (user_id, operation_id),
  unique (server_sequence)
);

create index if not exists pachanga_player_assessment_self_events_user_sequence_idx
  on private.pachanga_player_assessment_self_events_v1(user_id, server_sequence desc, id desc);
create index if not exists pachanga_player_assessment_self_events_profile_sequence_idx
  on private.pachanga_player_assessment_self_events_v1(player_profile_id, server_sequence desc, id desc);

revoke all on table private.pachanga_player_assessment_self_receipts_v1 from public, anon, authenticated, service_role;
revoke all on table private.pachanga_player_assessment_self_events_v1 from public, anon, authenticated, service_role;

create or replace function private.pachanga_player_assessment_self_evidence_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'PLAYER_ASSESSMENT_EVIDENCE_IMMUTABLE' using errcode = '55000';
end;
$$;

drop trigger if exists pachanga_player_assessment_self_receipts_immutable_v1
  on private.pachanga_player_assessment_self_receipts_v1;
create trigger pachanga_player_assessment_self_receipts_immutable_v1
before update or delete on private.pachanga_player_assessment_self_receipts_v1
for each row execute function private.pachanga_player_assessment_self_evidence_immutable_v1();

drop trigger if exists pachanga_player_assessment_self_events_immutable_v1
  on private.pachanga_player_assessment_self_events_v1;
create trigger pachanga_player_assessment_self_events_immutable_v1
before update or delete on private.pachanga_player_assessment_self_events_v1
for each row execute function private.pachanga_player_assessment_self_evidence_immutable_v1();

revoke all on function private.pachanga_player_assessment_self_evidence_immutable_v1()
  from public, anon, authenticated, service_role;

create or replace function private.persist_pachanga_player_assessment_self_authoritative_v1_impl(
  p_actor_user_id uuid,
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
#variable_conflict use_variable
declare
  existing_receipt private.pachanga_player_assessment_self_receipts_v1%rowtype;
  existing_assessment public.pachanga_player_assessments%rowtype;
  initial_assessment public.pachanga_player_assessments%rowtype;
  current_profile public.pachanga_player_profiles%rowtype;
  saved_profile public.pachanga_player_profiles%rowtype;
  created_assessment_id uuid;
  target_facets jsonb;
  v2_facets jsonb;
  v2_current_modifiers jsonb;
  target_rating numeric;
  target_reliability numeric;
  facet_key text;
  facet_value numeric;
  completed_at timestamptz := pg_catalog.clock_timestamp();
  display_name_value text;
  avatar_value text;
  next_vote jsonb;
  next_summary jsonb;
  request_fingerprint text;
  authoritative_metadata jsonb;
  confirmed_sequence bigint;
  operation_response jsonb;
begin
  if p_actor_user_id is null or p_operation_id is null or p_expected_revision is null then
    raise exception 'Actor, operation id and expected revision required';
  end if;
  if p_expected_revision < 0 then
    raise exception 'Invalid expected revision';
  end if;
  if p_assessment_kind not in ('initial', 'advanced') then
    raise exception 'Invalid assessment kind';
  end if;
  if not exists (select 1 from auth.users users where users.id = p_actor_user_id) then
    raise exception 'Registered user required';
  end if;
  if pg_catalog.jsonb_typeof(p_assessment_input) <> 'object'
    or pg_catalog.jsonb_typeof(p_assessment_result) <> 'object' then
    raise exception 'Invalid shared-engine assessment payload';
  end if;
  if coalesce(p_assessment_result ->> 'engineVersion', '') <> 'football-rating-v1'
    or (p_assessment_kind = 'initial' and coalesce(p_assessment_result ->> 'questionnaireVersion', '') <> 'initial-test-v1')
    or (p_assessment_kind = 'advanced' and coalesce(p_assessment_result ->> 'questionnaireVersion', '') <> 'advanced-test-v1')
    or nullif(pg_catalog.btrim(coalesce(p_assessment_result ->> 'position', '')), '') is null then
    raise exception 'Invalid shared-engine assessment result';
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
  if target_rating is null or target_rating::text = 'NaN' or target_rating < 1 or target_rating > 10
    or target_reliability is null or target_reliability::text = 'NaN'
    or target_reliability < 0 or target_reliability > 100 then
    raise exception 'Invalid shared-engine assessment result';
  end if;

  foreach facet_key in array array['ritmo', 'tiro', 'pase', 'regate', 'defensa', 'fisico'] loop
    begin
      facet_value := nullif(target_facets ->> facet_key, '')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid shared-engine assessment result';
    end;
    if facet_value is null or facet_value::text = 'NaN' or facet_value < 0 or facet_value > 10 then
      raise exception 'Invalid shared-engine assessment result';
    end if;
  end loop;

  foreach facet_key in array array['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical'] loop
    begin
      facet_value := nullif(v2_facets ->> facet_key, '')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid shared-engine assessment result';
    end;
    if facet_value is null or facet_value::text = 'NaN' or facet_value < 0 or facet_value > 100 then
      raise exception 'Invalid shared-engine assessment result';
    end if;
    begin
      facet_value := nullif(v2_current_modifiers ->> facet_key, '')::numeric;
    exception
      when invalid_text_representation or numeric_value_out_of_range then
        raise exception 'Invalid shared-engine assessment result';
    end;
    if facet_value is null or facet_value::text = 'NaN' or facet_value < -100 or facet_value > 100 then
      raise exception 'Invalid shared-engine assessment result';
    end if;
  end loop;

  request_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(pg_catalog.jsonb_build_object(
        'actorUserId', p_actor_user_id,
        'assessmentKind', p_assessment_kind,
        'assessmentInput', p_assessment_input
      )::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  authoritative_metadata := pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'clientVersion', nullif(pg_catalog.left(pg_catalog.btrim(coalesce(p_client_metadata ->> 'clientVersion', '')), 120), ''),
    'displayMode', nullif(pg_catalog.left(pg_catalog.btrim(coalesce(p_client_metadata ->> 'displayMode', '')), 120), ''),
    'serviceWorkerVersion', nullif(pg_catalog.left(pg_catalog.btrim(coalesce(p_client_metadata ->> 'serviceWorkerVersion', '')), 120), ''),
    'surface', nullif(pg_catalog.left(pg_catalog.btrim(coalesce(p_client_metadata ->> 'surface', '')), 120), '')
  ));

  perform pg_catalog.set_config('request.jwt.claim.sub', p_actor_user_id::text, true);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(p_actor_user_id::text),
    pg_catalog.hashtext('pachanga_' || p_assessment_kind || '_assessment_v2')
  );

  select * into existing_receipt
  from private.pachanga_player_assessment_self_receipts_v1 receipts
  where receipts.user_id = p_actor_user_id and receipts.operation_id = p_operation_id;
  if existing_receipt.operation_id is not null then
    if existing_receipt.request_fingerprint <> request_fingerprint then
      raise exception 'Operation id was already used with a different assessment payload'
        using errcode = 'PT409';
    end if;
    return existing_receipt.response;
  end if;

  select * into current_profile
  from public.pachanga_player_profiles profiles
  where profiles.user_id = p_actor_user_id
  for update;
  if coalesce(current_profile.profile_version, 0) <> p_expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.'
      using errcode = 'PT409';
  end if;

  select * into existing_assessment
  from public.pachanga_player_assessments assessments
  where assessments.user_id = p_actor_user_id
    and assessments.assessment_kind = p_assessment_kind
  for update;
  if existing_assessment.id is not null then
    if existing_assessment.idempotency_key <> p_operation_id then
      raise exception '% player assessment already completed', pg_catalog.initcap(p_assessment_kind);
    end if;
    if existing_assessment.input is distinct from p_assessment_input then
      raise exception 'Operation id was already used with a different assessment payload'
        using errcode = 'PT409';
    end if;
    raise exception 'Assessment replay receipt missing';
  end if;

  if p_assessment_kind = 'advanced' then
    select * into initial_assessment
    from public.pachanga_player_assessments assessments
    where assessments.user_id = p_actor_user_id
      and assessments.assessment_kind = 'initial'
    for update;
    if initial_assessment.id is null then
      raise exception 'Initial player assessment is required';
    end if;
    if current_profile.id is null then
      raise exception 'Player profile not found';
    end if;
  else
    insert into public.pachanga_player_assessments(
      user_id, player_profile_id, assessment_kind, engine_version,
      questionnaire_version, idempotency_key, input, result, rating,
      facet_ratings, reliability, completed_at
    ) values (
      p_actor_user_id, null, p_assessment_kind,
      p_assessment_result ->> 'engineVersion',
      p_assessment_result ->> 'questionnaireVersion',
      p_operation_id, p_assessment_input, p_assessment_result, target_rating,
      target_facets, target_reliability, completed_at
    ) returning id into created_assessment_id;

    if current_profile.id is null then
      select coalesce(
        (select profiles.display_name from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = p_actor_user_id),
        (select members.display_name from public.pachanga_group_members members
          where members.user_id = p_actor_user_id and nullif(pg_catalog.btrim(coalesce(members.display_name, '')), '') is not null
          order by members.created_at, members.group_id limit 1),
        'Jugador'
      ), (select profiles.avatar_ref from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = p_actor_user_id)
      into display_name_value, avatar_value;

      insert into public.pachanga_player_profiles(
        user_id, source_group_id, source_player_id, display_name, avatar, position, outfield_position
      ) values (
        p_actor_user_id, null, null, pg_catalog.left(display_name_value, 80), avatar_value,
        p_assessment_result ->> 'position', p_assessment_result ->> 'position'
      ) returning * into current_profile;
    end if;
  end if;

  if p_assessment_kind = 'initial' then
    update public.pachanga_player_assessments assessments
    set player_profile_id = current_profile.id
    where assessments.id = created_assessment_id;
  else
    insert into public.pachanga_player_assessments(
      user_id, player_profile_id, assessment_kind, engine_version,
      questionnaire_version, idempotency_key, input, result, rating,
      facet_ratings, reliability, completed_at
    ) values (
      p_actor_user_id, current_profile.id, p_assessment_kind,
      p_assessment_result ->> 'engineVersion',
      p_assessment_result ->> 'questionnaireVersion',
      p_operation_id, p_assessment_input, p_assessment_result, target_rating,
      target_facets, target_reliability, completed_at
    ) returning id into created_assessment_id;
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

  update public.pachanga_player_profiles profiles
  set rating_domain = case when current_profile.goalkeeper_only then 'goalkeeper_legacy' else 'field' end,
      rating = target_rating,
      ratings = case when p_assessment_kind = 'initial' then '[]'::jsonb else profiles.ratings end,
      rating_votes = public.pachanga_assessment_without_self_votes(profiles.rating_votes, p_actor_user_id)
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
      profile_version = profiles.profile_version + 1,
      updated_at = pg_catalog.clock_timestamp()
  where profiles.id = current_profile.id;

  perform public.pachanga_recalculate_player_rating_v2(current_profile.id, null, null, 'assessment');
  perform public.sync_pachanga_player_profile_to_groups(current_profile.id);

  select * into saved_profile
  from public.pachanga_player_profiles profiles
  where profiles.id = current_profile.id;
  confirmed_sequence := pg_catalog.nextval('private.pachanga_player_assessment_self_sequence_v1');
  operation_response := pg_catalog.jsonb_build_object(
    'assessmentKind', p_assessment_kind,
    'confirmedRevision', saved_profile.profile_version,
    'expectedRevision', p_expected_revision,
    'operationId', p_operation_id,
    'playerProfile', pg_catalog.jsonb_build_object(
      'id', saved_profile.id,
      'display_name', saved_profile.display_name,
      'avatar', saved_profile.avatar,
      'position', saved_profile.position,
      'outfield_position', saved_profile.outfield_position,
      'current_overall', saved_profile.current_overall,
      'current_facets', saved_profile.current_facets,
      'rating_reliability', saved_profile.rating_reliability,
      'assessment_summary', saved_profile.assessment_summary,
      'profile_version', saved_profile.profile_version,
      'updated_at', saved_profile.updated_at
    ),
    'serverSequence', confirmed_sequence,
    'updatedAt', saved_profile.updated_at
  );

  insert into private.pachanga_player_assessment_self_events_v1(
    user_id, player_profile_id, assessment_kind, operation_id,
    expected_revision, confirmed_revision, server_sequence, event_payload
  ) values (
    p_actor_user_id, saved_profile.id, p_assessment_kind, p_operation_id,
    p_expected_revision, saved_profile.profile_version, confirmed_sequence,
    pg_catalog.jsonb_build_object(
      'engineVersion', p_assessment_result ->> 'engineVersion',
      'questionnaireVersion', p_assessment_result ->> 'questionnaireVersion',
      'reliability', target_reliability
    )
  );
  insert into private.pachanga_player_assessment_self_receipts_v1(
    user_id, operation_id, assessment_kind, request_fingerprint,
    expected_revision, confirmed_revision, server_sequence, response, client_metadata
  ) values (
    p_actor_user_id, p_operation_id, p_assessment_kind, request_fingerprint,
    p_expected_revision, saved_profile.profile_version, confirmed_sequence,
    operation_response, authoritative_metadata
  );

  return operation_response;
end;
$$;

revoke all on function private.persist_pachanga_player_assessment_self_authoritative_v1_impl(
  uuid, text, jsonb, jsonb, uuid, bigint, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.persist_pachanga_player_assessment_self_authoritative_v1(
  p_actor_user_id uuid,
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
begin
  return private.persist_pachanga_player_assessment_self_authoritative_v1_impl(
    p_actor_user_id, p_assessment_kind, p_assessment_input, p_assessment_result,
    p_operation_id, p_expected_revision, p_client_metadata
  );
exception
  when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'Concurrent assessment update. Reload the confirmed state.' using errcode = 'PT409';
end;
$$;

revoke all on function public.persist_pachanga_player_assessment_self_authoritative_v1(
  uuid, text, jsonb, jsonb, uuid, bigint, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.persist_pachanga_player_assessment_self_authoritative_v1(
  uuid, text, jsonb, jsonb, uuid, bigint, jsonb
) to service_role;

comment on function public.persist_pachanga_player_assessment_self_authoritative_v1(
  uuid, text, jsonb, jsonb, uuid, bigint, jsonb
) is 'Server-only Rating V2 assessment authority for a universal player profile without requiring team membership.';
