-- Pachangas IQ rating system V2: authoritative social rating mutations.

create or replace function public.record_pachanga_individual_rating_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  comparisons jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  legacy_result jsonb;
  evidence_id uuid;
  opaque_id uuid;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;

  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;

  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;
  if not current_group.ratings_enabled then
    raise exception 'Ratings are disabled for this group';
  end if;

  legacy_result := public.record_pachanga_individual_rating_v2(
    target_group_id,
    target_player_id,
    comparisons,
    operation_id
  );
  evidence_id := nullif(legacy_result ->> 'evidenceId', '')::uuid;
  select evidence.moderation_id into opaque_id
  from public.pachanga_individual_rating_evidence evidence
  where evidence.id = evidence_id;

  insert into public.pachanga_group_events(
    group_id, match_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    target_group_id,
    null,
    operation_id,
    null,
    'individual_rating_changed_v2',
    false,
    jsonb_build_object('moderationId', opaque_id)
  );

  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'individual_rating_v2',
    expected_revision,
    jsonb_build_object(
      'evidenceId', evidence_id,
      'card', legacy_result -> 'card',
      'eligibility', legacy_result -> 'eligibility'
    ),
    client_metadata
  );
end;
$$;

create or replace function public.set_pachanga_group_ratings_enabled_authoritative_v2(
  target_group_id uuid,
  next_enabled boolean,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  legacy_result jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;

  legacy_result := public.set_pachanga_group_ratings_enabled_v2(
    target_group_id,
    next_enabled,
    operation_id
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'rating_settings_v2',
    expected_revision,
    legacy_result,
    client_metadata
  );
end;
$$;

revoke all on function public.record_pachanga_individual_rating_v2(uuid, text, jsonb, uuid)
  from public, anon, authenticated;
revoke all on function public.set_pachanga_group_ratings_enabled_v2(uuid, boolean, uuid)
  from public, anon, authenticated;
revoke all on function public.record_pachanga_individual_rating_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.set_pachanga_group_ratings_enabled_authoritative_v2(uuid, boolean, uuid, bigint, jsonb)
  from public, anon;

grant execute on function public.record_pachanga_individual_rating_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.set_pachanga_group_ratings_enabled_authoritative_v2(uuid, boolean, uuid, bigint, jsonb)
  to authenticated;
