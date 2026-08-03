create or replace function public.snapshot_pachanga_match_ratings_v2(
  target_group_id uuid,
  target_match_id text,
  match_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  group_payload jsonb;
  player_entry jsonb;
  player_payload jsonb;
  player_profile public.pachanga_player_profiles%rowtype;
  guest_id uuid;
  player_id text;
  team_side text;
  is_reserve boolean;
  card_snapshot jsonb;
  card_level numeric;
  match_time timestamptz := now();
  group_level numeric;
  lineup_a_level numeric;
  lineup_b_level numeric;
  result jsonb;
begin
  if exists (
    select 1 from public.pachanga_match_rating_snapshots snapshot
    where snapshot.group_id = target_group_id and snapshot.match_id = target_match_id
  ) then
    select snapshot.snapshot into result
    from public.pachanga_match_rating_snapshots snapshot
    where snapshot.group_id = target_group_id and snapshot.match_id = target_match_id;
    return result;
  end if;

  select payload into group_payload from public.pachanga_groups where id = target_group_id;
  if group_payload is null then raise exception 'Group not found'; end if;
  if not (coalesce((match_payload ->> 'closed')::boolean, false) or match_payload ? 'scoreA') then
    raise exception 'Only finalized matches can be snapshotted';
  end if;
  if coalesce(match_payload ->> 'date', '') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}' then
    match_time := (match_payload ->> 'date')::timestamptz;
  end if;

  insert into public.pachanga_match_rating_snapshots(
    group_id, match_id, engine_version, snapshot, finalized_at
  ) values (
    target_group_id, target_match_id, 'pachangas-rating-v2', match_payload, match_time
  );

  for player_entry in
    select value
    from jsonb_array_elements(coalesce(match_payload -> 'players', '[]'::jsonb)) entries(value)
    where value ->> 'status' = 'voy'
  loop
    player_id := player_entry ->> 'playerId';
    select value into player_payload
    from jsonb_array_elements(coalesce(group_payload -> 'players', '[]'::jsonb)) players(value)
    where value ->> 'id' = player_id
    limit 1;

    player_profile := null;
    if coalesce(player_payload ->> 'ownerUserId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select * into player_profile
      from public.pachanga_player_profiles
      where user_id = (player_payload ->> 'ownerUserId')::uuid;
    end if;

    guest_id := null;
    if player_profile.id is null then
      insert into public.pachanga_guest_identities(
        created_by_group_id, source_player_id, display_name, normalized_name, provisional_level, metadata
      ) values (
        target_group_id,
        player_id,
        coalesce(nullif(player_payload ->> 'name', ''), 'Invitado'),
        lower(regexp_replace(coalesce(nullif(player_payload ->> 'name', ''), 'Invitado'), '\s+', ' ', 'g')),
        public.pachanga_rating_v2_clamp(coalesce(nullif(player_payload ->> 'rating', '')::numeric * 10, 50)),
        jsonb_build_object('source', 'match_finalization')
      )
      on conflict (created_by_group_id, source_player_id) where source_player_id is not null
      do update set display_name = excluded.display_name, updated_at = now()
      returning id into guest_id;
    end if;

    team_side := case
      when exists (select 1 from jsonb_array_elements_text(coalesce(match_payload -> 'teamA', '[]'::jsonb)) team(value) where value = player_id) then 'A'
      when exists (select 1 from jsonb_array_elements_text(coalesce(match_payload -> 'teamB', '[]'::jsonb)) team(value) where value = player_id) then 'B'
      else 'external'
    end;
    is_reserve := team_side = 'external';
    card_level := coalesce(
      player_profile.current_overall,
      public.pachanga_rating_v2_clamp(coalesce(nullif(player_payload ->> 'rating', '')::numeric * 10, 50))
    );
    card_snapshot := jsonb_strip_nulls(jsonb_build_object(
      'playerId', player_id,
      'name', player_payload ->> 'name',
      'position', player_payload ->> 'position',
      'ratingDomain', player_profile.rating_domain,
      'baseFacets', player_profile.base_facets,
      'calibratedFacets', player_profile.calibrated_facets,
      'currentFacets', player_profile.current_facets,
      'baseOverall', player_profile.base_overall,
      'calibratedOverall', player_profile.calibrated_overall,
      'currentOverall', card_level,
      'reliability', player_profile.rating_reliability,
      'engineVersion', coalesce(player_profile.rating_engine_version, 'legacy-snapshot')
    ));

    insert into public.pachanga_match_rating_participants(
      group_id, match_id, local_player_id, player_profile_id, guest_identity_id,
      team_side, attendance_confirmed, was_reserve, card_snapshot
    ) values (
      target_group_id, target_match_id, player_id, player_profile.id, guest_id,
      team_side, true, is_reserve, card_snapshot
    );

    if player_profile.id is not null then
      insert into public.pachanga_player_rating_snapshots(
        player_profile_id, group_id, match_id, snapshot_kind,
        base_facets, calibrated_facets, current_facets, current_facet_modifiers,
        base_overall, calibrated_overall, current_overall, reliability,
        evaluator_count, engine_version
      ) values (
        player_profile.id, target_group_id, target_match_id, 'match_finalization',
        player_profile.base_facets, player_profile.calibrated_facets, player_profile.current_facets,
        player_profile.current_facet_modifiers, player_profile.base_overall,
        player_profile.calibrated_overall, player_profile.current_overall,
        player_profile.rating_reliability, player_profile.rating_evaluator_count,
        coalesce(player_profile.rating_engine_version, 'legacy-snapshot')
      );
    end if;
  end loop;

  select avg((participant.card_snapshot ->> 'currentOverall')::numeric)
  into lineup_a_level
  from public.pachanga_match_rating_participants participant
  where participant.group_id = target_group_id and participant.match_id = target_match_id
    and participant.team_side = 'A' and participant.attendance_confirmed and not participant.was_reserve;

  select avg((participant.card_snapshot ->> 'currentOverall')::numeric)
  into lineup_b_level
  from public.pachanga_match_rating_participants participant
  where participant.group_id = target_group_id and participant.match_id = target_match_id
    and participant.team_side = 'B' and participant.attendance_confirmed and not participant.was_reserve;

  group_level := public.pachanga_group_level_v2(target_group_id, match_time);
  result := jsonb_build_object(
    'match', match_payload,
    'groupLevel', group_level,
    'lineupALevel', lineup_a_level,
    'lineupBLevel', lineup_b_level,
    'capturedAt', match_time,
    'engineVersion', 'pachangas-rating-v2'
  );
  update public.pachanga_match_rating_snapshots
  set group_level = (result ->> 'groupLevel')::numeric,
      lineup_a_level = (result ->> 'lineupALevel')::numeric,
      lineup_b_level = (result ->> 'lineupBLevel')::numeric,
      snapshot = result
  where group_id = target_group_id and match_id = target_match_id;
  return result;
end;
$$;

revoke all on function public.snapshot_pachanga_match_ratings_v2(uuid, text, jsonb)
from public, anon, authenticated;
grant execute on function public.snapshot_pachanga_match_ratings_v2(uuid, text, jsonb)
to service_role;
