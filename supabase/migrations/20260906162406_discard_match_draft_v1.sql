-- Discard only the selected server-side draft; never resubmit client-normalized cards.
create or replace function public.discard_pachanga_match_draft_v1(
  target_group_id uuid,
  target_match_id text,
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
  selected_match jsonb;
  next_matches jsonb;
  next_payload jsonb;
  next_active_id text;
  replay jsonb;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required' using errcode = '42501';
  end if;
  if operation_id is null or expected_revision is null or nullif(target_match_id, '') is null then
    raise exception 'Operation id, revision and draft id required' using errcode = '22023';
  end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can discard drafts' using errcode = '42501';
  end if;

  select * into current_group from public.pachanga_groups groups
  where groups.id = target_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  -- Check after the row lock, including concurrent retries of the same command.
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then
    if replay ->> 'discardedDraftId' is distinct from target_match_id then
      raise exception 'Operation belongs to another command' using errcode = '22023';
    end if;
    return replay;
  end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select value into selected_match
  from jsonb_array_elements(current_group.payload -> 'matches')
  where value ->> 'id' = target_match_id;
  if selected_match is null then raise exception 'Draft not found' using errcode = 'PT404'; end if;
  if selected_match -> 'configured' is distinct from 'false'::jsonb
    or coalesce((selected_match ->> 'closed')::boolean, false)
    or selected_match ? 'scoreA' or selected_match ? 'scoreB'
    or coalesce((selected_match ->> 'publicOpen')::boolean, false) then
    raise exception 'Only unpublished drafts can be discarded' using errcode = 'PT422';
  end if;

  select coalesce(jsonb_agg(value order by ordinal), '[]'::jsonb) into next_matches
  from jsonb_array_elements(current_group.payload -> 'matches') with ordinality as matches(value, ordinal)
  where value ->> 'id' is distinct from target_match_id;
  next_active_id := current_group.payload ->> 'activeMatchId';
  if not exists(select 1 from jsonb_array_elements(next_matches) where value ->> 'id' = next_active_id) then
    next_active_id := coalesce(next_matches -> 0 ->> 'id', '');
  end if;
  next_payload := current_group.payload || jsonb_build_object('matches', next_matches, 'activeMatchId', next_active_id);
  perform public.save_pachanga_payload_if_current(target_group_id, expected_revision, next_payload);
  perform public.record_pachanga_group_event(
    target_group_id, target_match_id, 'match_draft_discarded_v1',
    jsonb_build_object('discardedDraft', selected_match), operation_id, true
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'match_draft_discarded_v1', expected_revision,
    jsonb_build_object('discardedDraftId', target_match_id), client_metadata
  );
end;
$$;
revoke all on function public.discard_pachanga_match_draft_v1(uuid, text, uuid, bigint, jsonb) from public, anon;
grant execute on function public.discard_pachanga_match_draft_v1(uuid, text, uuid, bigint, jsonb) to authenticated;
