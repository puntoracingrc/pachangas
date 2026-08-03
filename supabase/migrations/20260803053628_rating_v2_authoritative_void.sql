-- Pachangas IQ rating system V2: private withdrawal and opaque moderation.

create or replace function public.void_my_pachanga_individual_rating_v2(
  evidence_id uuid,
  reason text,
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
  selected public.pachanga_individual_rating_evidence%rowtype;
  evaluator_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  legacy_result jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  select * into selected
  from public.pachanga_individual_rating_evidence evidence
  where evidence.id = void_my_pachanga_individual_rating_v2.evidence_id;
  if not found then raise exception 'Rating not found'; end if;
  select profiles.user_id into evaluator_user_id
  from public.pachanga_player_profiles profiles
  where profiles.id = selected.evaluator_profile_id;
  if evaluator_user_id <> auth.uid() then
    raise exception 'Only your own rating can be withdrawn';
  end if;

  replay := public.pachanga_operation_replay_v2(selected.group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected.group_id
  for update;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  legacy_result := public.void_pachanga_individual_rating_v2(evidence_id, reason, operation_id);
  insert into public.pachanga_group_events(group_id, operation_id, actor_id, event_type, payload)
  values (
    selected.group_id,
    operation_id,
    null,
    'individual_rating_voided_v2',
    jsonb_build_object('moderationId', selected.moderation_id)
  );
  return public.pachanga_authoritative_response_v2(
    selected.group_id,
    operation_id,
    'individual_rating_void_v2',
    expected_revision,
    legacy_result,
    client_metadata
  );
end;
$$;

create or replace function public.moderate_pachanga_individual_rating_v2(
  target_group_id uuid,
  target_moderation_id uuid,
  reason text,
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
  selected public.pachanga_individual_rating_evidence%rowtype;
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  legacy_result jsonb;
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can moderate ratings';
  end if;
  if operation_id is null or expected_revision is null then
    raise exception 'Operation id and expected revision required';
  end if;
  select * into selected
  from public.pachanga_individual_rating_evidence evidence
  where evidence.group_id = target_group_id
    and evidence.moderation_id = target_moderation_id;
  if not found then raise exception 'Rating not found'; end if;

  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;
  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  legacy_result := public.void_pachanga_individual_rating_v2(selected.id, reason, operation_id);
  insert into public.pachanga_group_events(
    group_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    target_group_id,
    operation_id,
    null,
    'individual_rating_moderated_v2',
    true,
    jsonb_build_object('moderationId', target_moderation_id)
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'individual_rating_moderated_v2',
    expected_revision,
    legacy_result - 'evidenceId' - 'restoredEvidenceId',
    client_metadata
  );
end;
$$;

revoke all on function public.void_pachanga_individual_rating_v2(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function public.void_my_pachanga_individual_rating_v2(uuid, text, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.moderate_pachanga_individual_rating_v2(uuid, uuid, text, uuid, bigint, jsonb)
  from public, anon;

grant execute on function public.void_my_pachanga_individual_rating_v2(uuid, text, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.moderate_pachanga_individual_rating_v2(uuid, uuid, text, uuid, bigint, jsonb)
  to authenticated;
