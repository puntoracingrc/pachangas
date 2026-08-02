-- Pachangas IQ rating system V2: universal profile writes are versioned intents.

create or replace function public.patch_pachanga_player_profile_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
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
  ignored_result jsonb;
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

  ignored_result := public.patch_pachanga_player_profile_v2(
    target_group_id,
    target_player_id,
    coalesce(player_patch, '{}'::jsonb)
  );
  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'player_profile_changed_v2',
    jsonb_build_object('playerId', target_player_id),
    operation_id,
    public.is_pachanga_group_admin(target_group_id)
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'player_profile_changed_v2',
    expected_revision,
    '{}'::jsonb,
    client_metadata
  );
end;
$$;

create or replace function public.upsert_pachanga_own_player_profile_authoritative_v2(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
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
  ignored_result jsonb;
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

  ignored_result := public.upsert_pachanga_own_player_profile_v2(
    target_group_id,
    target_player_id,
    coalesce(player_patch, '{}'::jsonb)
  );
  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'own_player_profile_upserted_v2',
    jsonb_build_object('playerId', target_player_id),
    operation_id,
    false
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'own_player_profile_upserted_v2',
    expected_revision,
    '{}'::jsonb,
    client_metadata
  );
end;
$$;

revoke all on function public.append_pachanga_player_rating(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.complete_pachanga_player_initial_assessment(uuid, text, jsonb, jsonb, uuid)
  from public, anon, authenticated;
revoke all on function public.complete_pachanga_player_advanced_assessment(uuid, text, jsonb, jsonb, uuid)
  from public, anon, authenticated;
revoke all on function public.patch_pachanga_player_profile(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.upsert_pachanga_own_player_profile(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.patch_pachanga_player_profile_v2(uuid, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.upsert_pachanga_own_player_profile_v2(uuid, text, jsonb)
  from public, anon, authenticated;

revoke all on function public.patch_pachanga_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.upsert_pachanga_own_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.patch_pachanga_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.upsert_pachanga_own_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb)
  to authenticated;
