-- Pachangas IQ rating system V2: assessments join the revisioned authority path.

create or replace function public.persist_pachanga_player_assessment_authoritative_v2(
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
as $$
declare
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  legacy_result jsonb;
  final_response jsonb;
begin
  if p_actor_user_id is null or p_operation_id is null or p_expected_revision is null then
    raise exception 'Actor, operation id and expected revision required';
  end if;
  if not exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = p_target_group_id
      and members.user_id = p_actor_user_id
  ) then raise exception 'Current group membership required'; end if;

  replay := public.pachanga_operation_replay_v2(p_target_group_id, p_operation_id, p_actor_user_id);
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = p_target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> p_expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
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
    p_client_metadata
  );
  update public.pachanga_operation_receipts receipts
  set user_id = p_actor_user_id
  where receipts.group_id = p_target_group_id
    and receipts.operation_id = p_operation_id
    and receipts.user_id is null;
  return final_response;
end;
$$;

revoke all on function public.persist_pachanga_player_assessment_v2(uuid, uuid, text, text, jsonb, jsonb, uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.persist_pachanga_player_assessment_authoritative_v2(uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.persist_pachanga_player_assessment_authoritative_v2(uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb)
  to service_role;
