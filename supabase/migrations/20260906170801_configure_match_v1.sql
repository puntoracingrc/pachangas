-- Configure one match from the locked server state, preserving cards and other matches exactly.
create or replace function public.configure_pachanga_match_v1(
  target_group_id uuid, target_match_id text, configuration jsonb,
  operation_id uuid, expected_revision bigint, client_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare
  current_group public.pachanga_groups%rowtype;
  selected_match jsonb;
  selected_venue jsonb;
  next_match jsonb;
  next_matches jsonb;
  next_payload jsonb;
  replay jsonb;
  match_date timestamp;
  start_year integer;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user() or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only registered group admins can configure matches' using errcode = '42501';
  end if;
  if operation_id is null or expected_revision is null or nullif(target_match_id, '') is null or length(target_match_id) > 100 then
    raise exception 'Operation, revision and match id required' using errcode = '22023';
  end if;
  if jsonb_typeof(configuration) is distinct from 'object' or exists (
    select 1 from jsonb_object_keys(configuration) key where key not in
      ('title','date','venueId','kind','targetPlayers','fieldCost','reservesAttend','reserveLimit','publicGuestsPay','publicOpenSlots','publicRequiresApproval')
  ) then raise exception 'Only match configuration fields are accepted' using errcode = '22023'; end if;
  select * into current_group from public.pachanga_groups g where g.id = target_group_id for update;
  if not found then raise exception 'Group not found' using errcode = 'PT404'; end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then
    if replay ->> 'configuredMatchId' is distinct from target_match_id or replay -> 'configuration' is distinct from configuration then
      raise exception 'Operation belongs to another command' using errcode = '22023';
    end if;
    return replay;
  end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if nullif(configuration ->> 'date','') is null or configuration ->> 'kind' not in ('sala','futbol7','futbol11')
    or nullif(configuration ->> 'kind','') is null
    or coalesce((configuration ->> 'targetPlayers')::numeric,0) < 2
    or (configuration ->> 'targetPlayers')::numeric <> trunc((configuration ->> 'targetPlayers')::numeric)
    or coalesce((configuration ->> 'fieldCost')::numeric,-1) < 0
    or coalesce((configuration ->> 'reserveLimit')::numeric,-1) < 0
    or (configuration ->> 'reserveLimit')::numeric <> trunc((configuration ->> 'reserveLimit')::numeric)
    or coalesce((configuration ->> 'publicOpenSlots')::numeric,0) < 1 then
    raise exception 'Invalid match configuration' using errcode = '22023';
  end if;
  match_date := (configuration ->> 'date')::timestamp;
  if not isfinite(match_date) then raise exception 'Invalid match date' using errcode = '22023'; end if;
  start_year := extract(year from match_date)::integer - case when extract(month from match_date) < 9 then 1 else 0 end;
  select value into selected_venue from jsonb_array_elements(coalesce(current_group.payload -> 'venues','[]'::jsonb))
    where value ->> 'id' = configuration ->> 'venueId';
  if selected_venue is null then raise exception 'Select a saved venue' using errcode = '22023'; end if;
  select value into selected_match from jsonb_array_elements(coalesce(current_group.payload -> 'matches','[]'::jsonb))
    where value ->> 'id' = target_match_id;
  if coalesce((selected_match ->> 'closed')::boolean,false) or selected_match ? 'scoreA' or selected_match ? 'scoreB' then
    raise exception 'Completed matches cannot be configured' using errcode = 'PT422';
  end if;
  next_match := coalesce(selected_match,jsonb_build_object('id',target_match_id,'players','[]'::jsonb,'publicOpen',false)) || configuration || jsonb_build_object(
    'configured',true,'place',selected_venue ->> 'name','season',start_year::text || '-' || (start_year+1)::text,
    'reserveLimit',case when coalesce((configuration ->> 'reservesAttend')::boolean,false) then (configuration ->> 'reserveLimit')::integer else 0 end
  );
  if selected_match is null then
    next_matches := jsonb_build_array(next_match) || coalesce(current_group.payload -> 'matches','[]'::jsonb);
  else
    select jsonb_agg(case when value ->> 'id' = target_match_id then next_match else value end order by ordinal) into next_matches
    from jsonb_array_elements(current_group.payload -> 'matches') with ordinality as matches(value,ordinal);
  end if;
  next_payload := current_group.payload || jsonb_build_object('matches',next_matches,'activeMatchId',target_match_id);
  perform public.save_pachanga_payload_if_current(target_group_id,expected_revision,next_payload);
  perform public.record_pachanga_group_event(target_group_id,target_match_id,'match_configured_v1',jsonb_build_object('configuration',configuration),operation_id,true);
  return public.pachanga_authoritative_response_v2(target_group_id,operation_id,'match_configured_v1',expected_revision,
    jsonb_build_object('configuredMatchId',target_match_id,'configuration',configuration),client_metadata);
end;
$$;
revoke all on function public.configure_pachanga_match_v1(uuid,text,jsonb,uuid,bigint,jsonb) from public, anon;
grant execute on function public.configure_pachanga_match_v1(uuid,text,jsonb,uuid,bigint,jsonb) to authenticated;
