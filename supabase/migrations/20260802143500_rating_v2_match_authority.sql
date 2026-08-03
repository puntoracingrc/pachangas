-- Pachangas IQ rating system V2: versioned match and payload mutation entrypoints.

create or replace function public.save_pachanga_payload_authoritative_v2(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb,
  operation_id uuid,
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
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if not public.pachanga_rating_payload_is_canonical_v2(current_group.payload, next_payload) then
    raise exception 'Player cards and ratings are server managed' using errcode = 'PT422';
  end if;

  ignored_result := public.save_pachanga_payload_if_current(
    target_group_id,
    expected_revision,
    next_payload
  );
  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'group_payload_saved_v2',
    jsonb_build_object('payloadRevision', ignored_result -> 'payload_revision'),
    operation_id,
    true
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'group_payload_saved_v2',
    expected_revision,
    '{}'::jsonb,
    client_metadata
  );
end;
$$;

create or replace function public.patch_pachanga_match_player_status_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_status text,
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
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  ignored_result := public.patch_pachanga_match_player_status(
    target_group_id,
    target_match_id,
    target_player_id,
    next_status,
    operation_id
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'match_attendance_v2',
    expected_revision,
    '{}'::jsonb,
    client_metadata
  );
end;
$$;

create or replace function public.patch_pachanga_match_lineup_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  next_lineup_closed boolean,
  target_team_a_ids text[],
  target_team_b_ids text[],
  target_payer_id text,
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
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  ignored_result := public.patch_pachanga_match_lineup_state(
    target_group_id,
    target_match_id,
    next_lineup_closed,
    target_team_a_ids,
    target_team_b_ids,
    target_payer_id,
    operation_id
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'match_lineup_v2',
    expected_revision,
    '{}'::jsonb,
    client_metadata
  );
end;
$$;

drop function if exists public.finalize_pachanga_match_authoritative_v2(uuid, bigint, text, jsonb, uuid, jsonb);
create or replace function public.finalize_pachanga_match_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_score_a integer,
  target_score_b integer,
  target_scorers jsonb,
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
  selected_match jsonb;
  normalized_scorers jsonb;
  next_match jsonb;
  next_matches jsonb;
  next_players jsonb;
  next_payload jsonb;
  team_a_ids text[];
  team_b_ids text[];
  playing_ids text[];
  winner_ids text[] := '{}'::text[];
  target_players integer;
  reserve_limit integer;
  payer_player_id text;
  team_a_total integer;
  team_b_total integer;
  legacy_result jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  if target_score_a is null or target_score_b is null or target_score_a < 0 or target_score_b < 0 then
    raise exception 'Valid non-negative scores are required';
  end if;
  if jsonb_typeof(coalesce(target_scorers, '[]'::jsonb)) <> 'array' then
    raise exception 'Scorers must be an array';
  end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can finalize matches';
  end if;

  select matches.value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = target_match_id
  limit 1;
  if selected_match is null then raise exception 'Match not found'; end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'Match already finalized';
  end if;
  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before finalizing it';
  end if;
  if not coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'Close the lineup before finalizing';
  end if;

  select coalesce(array_agg(ids.value), '{}'::text[])
  into team_a_ids
  from jsonb_array_elements_text(coalesce(selected_match -> 'teamA', '[]'::jsonb)) ids(value);
  select coalesce(array_agg(ids.value), '{}'::text[])
  into team_b_ids
  from jsonb_array_elements_text(coalesce(selected_match -> 'teamB', '[]'::jsonb)) ids(value);
  if cardinality(team_a_ids) + cardinality(team_b_ids) < 1 then
    raise exception 'Closed lineups are required before finalizing';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(target_scorers, '[]'::jsonb)) scorers(value)
    where jsonb_typeof(scorers.value) <> 'object'
      or nullif(scorers.value ->> 'playerId', '') is null
      or coalesce(scorers.value ->> 'goals', '') !~ '^[0-9]+$'
      or not (
        scorers.value ->> 'playerId' = any(team_a_ids)
        or scorers.value ->> 'playerId' = any(team_b_ids)
      )
  ) then raise exception 'Invalid scorer entry'; end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(target_scorers, '[]'::jsonb)) scorers(value)
    group by scorers.value ->> 'playerId'
    having count(*) > 1
  ) then raise exception 'Duplicate scorer entry'; end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'playerId', scorers.value ->> 'playerId',
      'goals', (scorers.value ->> 'goals')::integer
    ) order by scorers.ordinality
  ), '[]'::jsonb)
  into normalized_scorers
  from jsonb_array_elements(coalesce(target_scorers, '[]'::jsonb))
    with ordinality scorers(value, ordinality)
  where (scorers.value ->> 'goals')::integer > 0;

  select coalesce(sum((scorers.value ->> 'goals')::integer), 0)
  into team_a_total
  from jsonb_array_elements(normalized_scorers) scorers(value)
  where scorers.value ->> 'playerId' = any(team_a_ids);
  select coalesce(sum((scorers.value ->> 'goals')::integer), 0)
  into team_b_total
  from jsonb_array_elements(normalized_scorers) scorers(value)
  where scorers.value ->> 'playerId' = any(team_b_ids);
  if team_a_total > target_score_a or team_b_total > target_score_b then
    raise exception 'Scorers exceed the match score';
  end if;

  target_players := greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, 0));
  reserve_limit := case
    when coalesce((selected_match ->> 'reservesAttend')::boolean, false)
      then greatest(0, coalesce((selected_match ->> 'reserveLimit')::integer, 0))
    else 0
  end;
  select coalesce(array_agg(rows.player_id), '{}'::text[])
  into playing_ids
  from (
    select entries.value ->> 'playerId' as player_id
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb))
      with ordinality entries(value, ordinality)
    where entries.value ->> 'status' = 'voy'
    order by coalesce(entries.value ->> 'joinedAt', '9999-12-31T23:59:59.999Z'), entries.ordinality
    limit target_players + reserve_limit
  ) rows;
  if cardinality(playing_ids) < 1 then
    raise exception 'Close a lineup with players before finalizing';
  end if;
  payer_player_id := nullif(selected_match ->> 'payerId', '');
  if payer_player_id is null or not payer_player_id = any(playing_ids) then
    raise exception 'Payer must belong to the closed lineup';
  end if;
  if target_score_a > target_score_b then winner_ids := team_a_ids;
  elsif target_score_b > target_score_a then winner_ids := team_b_ids;
  end if;

  select coalesce(jsonb_agg(
    case
      when players.value ->> 'id' = any(playing_ids) then
        players.value || jsonb_build_object(
          'appearances', greatest(0, coalesce((players.value ->> 'appearances')::integer, 0)) + 1,
          'goals', greatest(0, coalesce((players.value ->> 'goals')::integer, 0)) + coalesce((
            select sum((scorers.value ->> 'goals')::integer)
            from jsonb_array_elements(normalized_scorers) scorers(value)
            where scorers.value ->> 'playerId' = players.value ->> 'id'
          ), 0),
          'wins', greatest(0, coalesce((players.value ->> 'wins')::integer, 0))
            + case when players.value ->> 'id' = any(winner_ids) then 1 else 0 end
        )
      else players.value
    end
    order by players.ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb))
    with ordinality players(value, ordinality);

  next_match := selected_match || jsonb_build_object(
    'scoreA', target_score_a,
    'scoreB', target_score_b,
    'scorers', normalized_scorers,
    'closed', true,
    'payerId', payer_player_id
  );
  select coalesce(jsonb_agg(
    case when matches.value ->> 'id' = target_match_id then next_match else matches.value end
    order by matches.ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb))
    with ordinality matches(value, ordinality);
  next_payload := jsonb_set(
    jsonb_set(current_group.payload, '{players}', next_players, true),
    '{matches}', next_matches, true
  );

  legacy_result := public.finalize_pachanga_match_if_current(
    target_group_id,
    expected_revision,
    target_match_id,
    next_payload,
    operation_id
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id,
    operation_id,
    'match_finalized_v2',
    expected_revision,
    jsonb_build_object(
      'billing_status', legacy_result -> 'billing_status',
      'billing_trial_finalized_matches', legacy_result -> 'billing_trial_finalized_matches'
    ),
    client_metadata
  );
end;
$$;

revoke all on function public.save_pachanga_payload_authoritative_v2(uuid, bigint, jsonb, uuid, jsonb)
  from public, anon;
revoke all on function public.patch_pachanga_match_player_status_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.patch_pachanga_match_lineup_authoritative_v2(uuid, text, boolean, text[], text[], text, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.finalize_pachanga_match_authoritative_v2(uuid, text, integer, integer, jsonb, uuid, bigint, jsonb)
  from public, anon;

grant execute on function public.save_pachanga_payload_authoritative_v2(uuid, bigint, jsonb, uuid, jsonb)
  to authenticated;
grant execute on function public.patch_pachanga_match_player_status_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.patch_pachanga_match_lineup_authoritative_v2(uuid, text, boolean, text[], text[], text, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.finalize_pachanga_match_authoritative_v2(uuid, text, integer, integer, jsonb, uuid, bigint, jsonb)
  to authenticated;
