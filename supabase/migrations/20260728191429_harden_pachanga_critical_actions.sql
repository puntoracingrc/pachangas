alter table public.pachanga_groups
add column if not exists payload_revision bigint not null default 0;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  new.payload_revision = coalesce(old.payload_revision, 0) + 1;
  return new;
end;
$$;

drop policy if exists "Members can update groups" on public.pachanga_groups;
drop policy if exists "Admins can update groups" on public.pachanga_groups;
create policy "Admins can update groups"
on public.pachanga_groups
for update
to authenticated
using (
  public.is_pachanga_group_admin(id)
)
with check (
  public.is_pachanga_group_admin(id)
);

create or replace function public.save_pachanga_payload_if_current(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can save the full team state';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if expected_revision is not null and current_group.payload_revision <> expected_revision then
    raise exception 'Team changed before saving. Reload and try again.' using errcode = '40001';
  end if;

  update public.pachanga_groups
  set payload = next_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );
end;
$$;

create or replace function public.patch_pachanga_match_player_status(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  selected_match jsonb;
  existing_entry jsonb;
  next_entry jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
  is_finalized boolean;
  was_confirmed boolean;
  will_confirmed boolean;
  previous_goals integer;
  direction integer;
  score_a integer;
  score_b integer;
  winning_ids text[];
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if next_status not in ('voy', 'duda', 'no') then
    raise exception 'Invalid status';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only change your own attendance';
  end if;

  if next_status = 'voy'
    and (
      coalesce((selected_player ->> 'injured')::boolean, false)
      or coalesce((selected_player ->> 'inactive')::boolean, false)
    )
  then
    raise exception 'This player cannot attend';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before changing attendance';
  end if;

  is_finalized := coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA';
  if is_finalized and not is_admin then
    raise exception 'Only admins can edit a finalized match';
  end if;

  select value into existing_entry
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) as value
  where value ->> 'playerId' = target_player_id
  limit 1;

  was_confirmed := existing_entry ->> 'status' = 'voy';
  will_confirmed := next_status = 'voy';

  next_entry := jsonb_build_object(
    'playerId', target_player_id,
    'status', next_status,
    'paid', case when next_status = 'voy' then coalesce((existing_entry ->> 'paid')::boolean, false) else false end
  );

  if next_status = 'voy' then
    next_entry := next_entry || jsonb_build_object(
      'joinedAt',
      coalesce(
        case when existing_entry ->> 'status' = 'voy' then existing_entry ->> 'joinedAt' else null end,
        to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
    );
  end if;

  if existing_entry is null then
    next_match_players := coalesce(selected_match -> 'players', '[]'::jsonb) || jsonb_build_array(next_entry);
  else
    select coalesce(jsonb_agg(
      case when value ->> 'playerId' = target_player_id then next_entry else value end
      order by ordinality
    ), '[]'::jsonb)
    into next_match_players
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  next_match := selected_match || jsonb_build_object('players', next_match_players);

  previous_goals := coalesce((
    select (value ->> 'goals')::integer
    from jsonb_array_elements(coalesce(selected_match -> 'scorers', '[]'::jsonb)) as value
    where value ->> 'playerId' = target_player_id
    limit 1
  ), 0);

  if is_finalized and was_confirmed and not will_confirmed then
    next_match := jsonb_set(
      next_match,
      '{scorers}',
      coalesce((
        select jsonb_agg(value)
        from jsonb_array_elements(coalesce(next_match -> 'scorers', '[]'::jsonb)) as value
        where value ->> 'playerId' <> target_player_id
      ), '[]'::jsonb),
      true
    );
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_players := current_payload -> 'players';

  if is_finalized and was_confirmed <> will_confirmed then
    direction := case when will_confirmed then 1 else -1 end;
    score_a := coalesce((selected_match ->> 'scoreA')::integer, 0);
    score_b := coalesce((selected_match ->> 'scoreB')::integer, 0);
    winning_ids := case
      when score_a = score_b then array[]::text[]
      when score_a > score_b then array(select jsonb_array_elements_text(coalesce(selected_match -> 'teamA', '[]'::jsonb)))
      else array(select jsonb_array_elements_text(coalesce(selected_match -> 'teamB', '[]'::jsonb)))
    end;

    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_player_id then
          value || jsonb_build_object(
            'appearances', greatest(0, coalesce((value ->> 'appearances')::integer, 0) + direction),
            'goals', greatest(0, coalesce((value ->> 'goals')::integer, 0) + (direction * previous_goals)),
            'wins', greatest(0, coalesce((value ->> 'wins')::integer, 0) + case when target_player_id = any(winning_ids) then direction else 0 end)
          )
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('matches', next_matches, 'players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.patch_pachanga_match_player_paid(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_paid boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  selected_match jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only mark your own payment';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before changing payments';
  end if;

  select coalesce(jsonb_agg(
    case
      when value ->> 'playerId' = target_player_id and value ->> 'status' = 'voy' then value || jsonb_build_object('paid', coalesce(next_paid, false))
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_match_players
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_match := selected_match || jsonb_build_object('players', next_match_players);

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.patch_pachanga_match_scorers(
  target_group_id uuid,
  target_match_id text,
  target_score_a integer,
  target_score_b integer,
  next_scorers jsonb,
  target_team_a_ids text[],
  target_team_b_ids text[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_match jsonb;
  sanitized_scorers jsonb;
  next_match jsonb;
  next_matches jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  score_a integer;
  score_b integer;
  team_a_total integer;
  team_b_total integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can edit scorers';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before editing scorers';
  end if;

  score_a := coalesce((selected_match ->> 'scoreA')::integer, target_score_a);
  score_b := coalesce((selected_match ->> 'scoreB')::integer, target_score_b);
  if score_a is null or score_b is null or score_a < 0 or score_b < 0 then
    raise exception 'Fill the score before editing scorers';
  end if;

  with scorer_rows as (
    select
      value ->> 'playerId' as player_id,
      greatest(0, coalesce((value ->> 'goals')::integer, 0)) as goals
    from jsonb_array_elements(coalesce(next_scorers, '[]'::jsonb)) as value
  ),
  grouped as (
    select player_id, sum(goals)::integer as goals
    from scorer_rows
    where player_id is not null and goals > 0
    group by player_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('playerId', player_id, 'goals', goals)), '[]'::jsonb)
  into sanitized_scorers
  from grouped;

  if exists (
    select 1
    from jsonb_array_elements(sanitized_scorers) as value
    where not ((value ->> 'playerId') = any(coalesce(target_team_a_ids, array[]::text[]))
      or (value ->> 'playerId') = any(coalesce(target_team_b_ids, array[]::text[])))
  ) then
    raise exception 'Scorer is not in the current lineups';
  end if;

  select coalesce(sum((value ->> 'goals')::integer), 0)
  into team_a_total
  from jsonb_array_elements(sanitized_scorers) as value
  where value ->> 'playerId' = any(coalesce(target_team_a_ids, array[]::text[]));

  select coalesce(sum((value ->> 'goals')::integer), 0)
  into team_b_total
  from jsonb_array_elements(sanitized_scorers) as value
  where value ->> 'playerId' = any(coalesce(target_team_b_ids, array[]::text[]));

  if team_a_total > score_a or team_b_total > score_b then
    raise exception 'Scorers exceed the match score';
  end if;

  next_match := jsonb_set(selected_match, '{scorers}', sanitized_scorers, true);

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_players := current_payload -> 'players';

  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    select coalesce(jsonb_agg(
      value || jsonb_build_object(
        'goals',
        greatest(0,
          coalesce((value ->> 'goals')::integer, 0)
          - coalesce((
              select (old_scorer ->> 'goals')::integer
              from jsonb_array_elements(coalesce(selected_match -> 'scorers', '[]'::jsonb)) as old_scorer
              where old_scorer ->> 'playerId' = value ->> 'id'
              limit 1
            ), 0)
          + coalesce((
              select (new_scorer ->> 'goals')::integer
              from jsonb_array_elements(sanitized_scorers) as new_scorer
              where new_scorer ->> 'playerId' = value ->> 'id'
              limit 1
            ), 0)
        )
      )
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('matches', next_matches, 'players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.patch_pachanga_player_profile(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  patched_player jsonb;
  next_players jsonb;
  next_matches jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
  patch_injured boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only edit your own player profile';
  end if;

  patched_player := selected_player;

  if player_patch ? 'name' then
    patched_player := patched_player || jsonb_build_object('name', nullif(trim(player_patch ->> 'name'), ''));
  end if;

  if player_patch ? 'phone' then
    patched_player := patched_player || jsonb_build_object('phone', coalesce(player_patch ->> 'phone', ''));
  end if;

  if player_patch ? 'avatar' then
    patched_player := patched_player || jsonb_build_object('avatar', nullif(player_patch ->> 'avatar', ''));
  end if;

  if player_patch ? 'goalkeeperOnly' then
    patched_player := patched_player || jsonb_build_object('goalkeeperOnly', coalesce((player_patch ->> 'goalkeeperOnly')::boolean, false));
  end if;

  if player_patch ? 'injured' then
    patch_injured := coalesce((player_patch ->> 'injured')::boolean, false);
    patched_player := patched_player || jsonb_build_object('injured', patch_injured);
  end if;

  if player_patch ? 'position' then
    patched_player := patched_player || jsonb_build_object('position', nullif(player_patch ->> 'position', ''));
  end if;

  if player_patch ? 'goals' then
    patched_player := patched_player || jsonb_build_object('goals', greatest(0, coalesce((player_patch ->> 'goals')::integer, 0)));
  end if;

  if is_admin and player_patch ? 'rating' then
    patched_player := patched_player || jsonb_build_object('rating', greatest(1, least(10, coalesce((player_patch ->> 'rating')::numeric, 5))));
  end if;

  if is_admin and player_patch ? 'inactive' then
    patched_player := patched_player || jsonb_build_object('inactive', coalesce((player_patch ->> 'inactive')::boolean, false));
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_player_id then patched_player else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_matches := current_payload -> 'matches';

  if patch_injured then
    select coalesce(jsonb_agg(
      case
        when not (coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA') then
          value || jsonb_build_object(
            'players',
            coalesce((
              select jsonb_agg(
                case
                  when entry ->> 'playerId' = target_player_id then
                    jsonb_build_object('playerId', target_player_id, 'status', 'no', 'paid', false)
                  else entry
                end
                order by entry_ordinality
              )
              from jsonb_array_elements(coalesce(value -> 'players', '[]'::jsonb)) with ordinality as match_entries(entry, entry_ordinality)
            ), '[]'::jsonb)
          )
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_matches
    from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('players', next_players, 'matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.append_pachanga_player_rating(
  target_group_id uuid,
  target_player_id text,
  vote_facets jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  selected_member_name text;
  clean_facets jsonb;
  next_vote jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only members can rate players';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if coalesce(selected_player ->> 'ownerUserId', '') = current_user_id::text then
    raise exception 'You cannot rate yourself';
  end if;

  if coalesce((selected_player ->> 'inactive')::boolean, false) then
    raise exception 'Inactive players cannot be rated';
  end if;

  select display_name into selected_member_name
  from public.pachanga_group_members
  where group_id = target_group_id
    and user_id = current_user_id;

  clean_facets := jsonb_build_object(
    'ritmo', greatest(1, least(10, coalesce((vote_facets ->> 'ritmo')::numeric, 5))),
    'tiro', greatest(1, least(10, coalesce((vote_facets ->> 'tiro')::numeric, 5))),
    'pase', greatest(1, least(10, coalesce((vote_facets ->> 'pase')::numeric, 5))),
    'regate', greatest(1, least(10, coalesce((vote_facets ->> 'regate')::numeric, 5))),
    'defensa', greatest(1, least(10, coalesce((vote_facets ->> 'defensa')::numeric, 5))),
    'fisico', greatest(1, least(10, coalesce((vote_facets ->> 'fisico')::numeric, 5)))
  );

  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', selected_member_name,
    'matchCount', greatest(0, coalesce((selected_player ->> 'appearances')::integer, 0)),
    'createdAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'facets', clean_facets
  );

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_player_id then
        value || jsonb_build_object('ratingVotes', coalesce(value -> 'ratingVotes', '[]'::jsonb) || jsonb_build_array(next_vote))
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

revoke all on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from public;
revoke execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from anon;
grant execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) to authenticated;
revoke all on function public.patch_pachanga_match_player_status(uuid, text, text, text) from public;
revoke execute on function public.patch_pachanga_match_player_status(uuid, text, text, text) from anon;
grant execute on function public.patch_pachanga_match_player_status(uuid, text, text, text) to authenticated;
revoke all on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) from public;
revoke execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) from anon;
grant execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean) to authenticated;
revoke all on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[]) from public;
revoke execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[]) from anon;
grant execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[]) to authenticated;
revoke all on function public.patch_pachanga_player_profile(uuid, text, jsonb) from public;
revoke execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) from anon;
grant execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) to authenticated;
revoke all on function public.append_pachanga_player_rating(uuid, text, jsonb) from public;
revoke execute on function public.append_pachanga_player_rating(uuid, text, jsonb) from anon;
grant execute on function public.append_pachanga_player_rating(uuid, text, jsonb) to authenticated;
