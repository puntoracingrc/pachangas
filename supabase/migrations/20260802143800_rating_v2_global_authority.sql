-- Pachangas IQ rating system V2: server-authoritative global observations.

create unique index if not exists pachanga_external_teams_group_name_zone_idx
  on public.pachanga_external_teams(
    created_by_group_id,
    normalized_name,
    coalesce(zone, '')
  );

create or replace function public.ensure_pachanga_external_team_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  display_name text,
  zone text,
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
  normalized_name text := lower(regexp_replace(trim(display_name), '\s+', ' ', 'g'));
  safe_zone text := nullif(left(trim(coalesce(zone, '')), 120), '');
  team_id uuid;
  replay jsonb;
  reference_level numeric;
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can configure a rival';
  end if;
  if operation_id is null or expected_revision is null or normalized_name = '' then
    raise exception 'Name, operation id and expected revision required';
  end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;

  select * into current_group from public.pachanga_groups groups
  where groups.id = target_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;
  if not current_group.ratings_enabled then raise exception 'Ratings are disabled for this group'; end if;
  if not exists (
    select 1 from public.pachanga_match_rating_snapshots snapshots
    where snapshots.group_id = target_group_id
      and snapshots.match_id = target_match_id
      and snapshots.state = 'active'
  ) then raise exception 'A finalized match snapshot is required'; end if;

  reference_level := public.pachanga_host_lineup_level_v2(target_group_id, target_match_id);
  if reference_level is null then raise exception 'Host lineup level unavailable'; end if;
  perform pg_advisory_xact_lock(hashtext(target_group_id::text), hashtext(normalized_name || ':' || coalesce(safe_zone, '')));

  select teams.id into team_id
  from public.pachanga_external_teams teams
  where teams.created_by_group_id = target_group_id
    and teams.normalized_name = normalized_name
    and teams.zone is not distinct from safe_zone
  for update;

  if team_id is null then
    insert into public.pachanga_external_teams(
      created_by_group_id, display_name, normalized_name, zone, stable_level, metadata
    ) values (
      target_group_id,
      left(trim(display_name), 120),
      normalized_name,
      safe_zone,
      reference_level,
      jsonb_build_object('matchIds', jsonb_build_array(target_match_id))
    ) returning id into team_id;
  else
    update public.pachanga_external_teams
    set metadata = jsonb_set(
          coalesce(metadata, '{}'::jsonb),
          '{matchIds}',
          coalesce((
            select jsonb_agg(distinct match_id)
            from jsonb_array_elements_text(
              coalesce(metadata -> 'matchIds', '[]'::jsonb) || jsonb_build_array(target_match_id)
            ) ids(match_id)
          ), jsonb_build_array(target_match_id)),
          true
        ),
        stable_level = coalesce(stable_level, reference_level),
        updated_at = clock_timestamp()
    where id = team_id;
  end if;

  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  perform public.record_pachanga_group_event(
    target_group_id, target_match_id, 'external_team_configured_v2',
    jsonb_build_object('externalTeamId', team_id), operation_id, true
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'external_team_configured_v2', expected_revision,
    jsonb_build_object('externalTeamId', team_id), client_metadata
  );
end;
$$;

create or replace function public.record_pachanga_global_rating_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  target_kind text,
  comparison text,
  target_guest_id uuid,
  target_external_team_id uuid,
  rated_group_id uuid,
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
  current_user_id uuid := auth.uid();
  current_group public.pachanga_groups%rowtype;
  replay jsonb;
  comparison_delta numeric;
  reference_level numeric;
  calculated_observation numeric;
  response_id uuid;
  official_result jsonb;
  calibration_result jsonb;
begin
  if current_user_id is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can submit global ratings';
  end if;
  if operation_id is null or expected_revision is null then
    raise exception 'Operation id and expected revision required';
  end if;
  if target_kind not in ('guest', 'external_team', 'registered_group') then
    raise exception 'Invalid global target';
  end if;
  if target_kind = 'registered_group' and rated_group_id is not null then
    perform pg_advisory_xact_lock(
      hashtextextended(
        'registered-rating:' || least(target_group_id::text, rated_group_id::text)
          || ':' || greatest(target_group_id::text, rated_group_id::text),
        0
      )
    );
  end if;

  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;
  select * into current_group from public.pachanga_groups groups
  where groups.id = target_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;
  if not current_group.ratings_enabled then raise exception 'Ratings are disabled for this group'; end if;
  if not exists (
    select 1 from public.pachanga_match_rating_snapshots snapshots
    where snapshots.group_id = target_group_id
      and snapshots.match_id = target_match_id
      and snapshots.state = 'active'
  ) then raise exception 'A finalized match snapshot is required'; end if;

  if target_kind = 'guest' and (
    target_guest_id is null or target_external_team_id is not null or rated_group_id is not null
    or not exists (
      select 1 from public.pachanga_match_rating_participants participants
      where participants.group_id = target_group_id
        and participants.match_id = target_match_id
        and participants.guest_identity_id = target_guest_id
        and participants.attendance_confirmed
        and not participants.was_reserve
    )
  ) then raise exception 'Guest target is not eligible'; end if;
  if target_kind = 'external_team' and (
    target_external_team_id is null or target_guest_id is not null or rated_group_id is not null
    or not exists (
      select 1 from public.pachanga_external_teams teams
      where teams.id = target_external_team_id
        and teams.created_by_group_id = target_group_id
        and coalesce(teams.metadata -> 'matchIds', '[]'::jsonb) ? target_match_id
    )
  ) then raise exception 'External team target is not eligible'; end if;
  if target_kind = 'registered_group' and (
    rated_group_id is null or rated_group_id = target_group_id
    or target_guest_id is not null or target_external_team_id is not null
    or not exists (
      select 1
      from public.pachanga_registered_match_opponents opponents
      join public.pachanga_groups rated_groups on rated_groups.id = opponents.opponent_group_id
      where opponents.host_group_id = target_group_id
        and opponents.match_id = target_match_id
        and opponents.opponent_group_id = rated_group_id
        and rated_groups.ratings_enabled
    )
  ) then raise exception 'Registered group target is not eligible'; end if;
  if target_kind = 'registered_group' then
    perform 1 from public.pachanga_groups groups
    where groups.id = rated_group_id
    for update;
  end if;

  comparison_delta := public.pachanga_rating_v2_comparison_delta(comparison);
  if comparison_delta is null then raise exception 'Invalid comparison'; end if;
  reference_level := public.pachanga_host_lineup_level_v2(target_group_id, target_match_id);
  if reference_level is null then raise exception 'Host lineup level unavailable'; end if;
  calculated_observation := public.pachanga_rating_v2_clamp(reference_level + comparison_delta);

  perform pg_advisory_xact_lock(
    hashtext(target_group_id::text),
    hashtext(target_match_id || ':' || target_kind || ':' || coalesce(target_guest_id::text, target_external_team_id::text, rated_group_id::text, ''))
  );
  select responses.id into response_id
  from public.pachanga_global_rating_responses responses
  where responses.group_id = record_pachanga_global_rating_authoritative_v2.target_group_id
    and responses.match_id = record_pachanga_global_rating_authoritative_v2.target_match_id
    and responses.target_kind = record_pachanga_global_rating_authoritative_v2.target_kind
    and responses.guest_identity_id is not distinct from record_pachanga_global_rating_authoritative_v2.target_guest_id
    and responses.external_team_id is not distinct from record_pachanga_global_rating_authoritative_v2.target_external_team_id
    and responses.target_group_id is not distinct from record_pachanga_global_rating_authoritative_v2.rated_group_id
    and responses.actor_user_id = current_user_id
  for update;

  if response_id is null then
    insert into public.pachanga_global_rating_responses(
      group_id, match_id, target_kind, guest_identity_id, external_team_id,
      target_group_id, actor_user_id, comparison, delta,
      reference_level_snapshot, observation, engine_version, operation_id
    ) values (
      target_group_id, target_match_id, target_kind, target_guest_id,
      target_external_team_id, rated_group_id, current_user_id, comparison,
      comparison_delta, reference_level, calculated_observation,
      'pachangas-rating-v2-global-1', operation_id
    ) returning id into response_id;
  else
    update public.pachanga_global_rating_responses
    set comparison = record_pachanga_global_rating_authoritative_v2.comparison,
        delta = comparison_delta,
        reference_level_snapshot = reference_level,
        observation = calculated_observation,
        engine_version = 'pachangas-rating-v2-global-1',
        operation_id = record_pachanga_global_rating_authoritative_v2.operation_id,
        created_at = clock_timestamp()
    where id = response_id;
  end if;

  official_result := public.pachanga_refresh_global_official_v2(
    target_group_id, target_match_id, target_kind, target_guest_id,
    target_external_team_id, rated_group_id
  );
  if target_kind = 'guest' then
    calibration_result := public.pachanga_recalculate_guest_level_v2(target_guest_id);
  elsif target_kind = 'external_team' then
    calibration_result := public.pachanga_recalculate_external_team_level_v2(target_external_team_id, clock_timestamp());
  else
    calibration_result := public.pachanga_recalculate_group_external_level_v2(rated_group_id, clock_timestamp());
  end if;

  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  insert into public.pachanga_group_events(
    group_id, match_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    target_group_id, target_match_id, operation_id, null,
    'global_rating_changed_v2', true,
    jsonb_build_object('targetKind', target_kind, 'officialEvidenceId', official_result -> 'officialEvidenceId')
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'global_rating_v2', expected_revision,
    jsonb_build_object(
      'responseId', response_id,
      'official', official_result,
      'calibration', calibration_result,
      'calibrationTarget', case when target_kind = 'registered_group' then (
        select jsonb_build_object(
          'groupId', groups.id,
          'confirmedRevision', groups.payload_revision,
          'externallyCalibratedLevel', groups.externally_calibrated_level,
          'externalCalibrationSnapshot', groups.external_calibration_snapshot
        )
        from public.pachanga_groups groups
        where groups.id = rated_group_id
      ) else null end
    ),
    client_metadata
  );
end;
$$;

create or replace function public.get_pachanga_global_rating_context_v2(
  target_group_id uuid,
  target_match_id text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  result jsonb;
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can open global ratings';
  end if;
  if not public.pachanga_rating_v2_ratings_enabled(target_group_id) then
    raise exception 'Ratings are disabled for this group';
  end if;
  if not exists (
    select 1 from public.pachanga_match_rating_snapshots snapshots
    where snapshots.group_id = target_group_id
      and snapshots.match_id = target_match_id
      and snapshots.state = 'active'
  ) then raise exception 'A finalized match snapshot is required'; end if;

  select jsonb_build_object(
    'groupId', target_group_id,
    'matchId', target_match_id,
    'referenceLevel', public.pachanga_host_lineup_level_v2(target_group_id, target_match_id),
    'guests', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', guests.id,
        'name', guests.display_name,
        'provisionalLevel', guests.provisional_level,
        'observationCount', guests.provisional_observation_count
      ) order by guests.display_name)
      from public.pachanga_match_rating_participants participants
      join public.pachanga_guest_identities guests on guests.id = participants.guest_identity_id
      where participants.group_id = target_group_id
        and participants.match_id = target_match_id
        and participants.attendance_confirmed
        and not participants.was_reserve
    ), '[]'::jsonb),
    'externalTeams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', teams.id,
        'name', teams.display_name,
        'zone', teams.zone,
        'calibratedLevel', teams.calibrated_external_level
      ) order by teams.display_name)
      from public.pachanga_external_teams teams
      where teams.created_by_group_id = target_group_id
        and coalesce(teams.metadata -> 'matchIds', '[]'::jsonb) ? target_match_id
    ), '[]'::jsonb),
    'registeredOpponent', (
      select jsonb_build_object(
        'groupId', groups.id,
        'name', groups.name,
        'teamCode', groups.team_code,
        'externallyCalibratedLevel', groups.externally_calibrated_level
      )
      from public.pachanga_registered_match_opponents opponents
      join public.pachanga_groups groups on groups.id = opponents.opponent_group_id
      where opponents.host_group_id = target_group_id
        and opponents.match_id = target_match_id
        and groups.ratings_enabled
    ),
    'ownResponses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'targetKind', responses.target_kind,
        'guestId', responses.guest_identity_id,
        'externalTeamId', responses.external_team_id,
        'targetGroupId', responses.target_group_id,
        'comparison', responses.comparison
      ))
      from public.pachanga_global_rating_responses responses
      where responses.group_id = target_group_id
        and responses.match_id = target_match_id
        and responses.actor_user_id = auth.uid()
    ), '[]'::jsonb),
    'note', 'Las respuestas de los administradores se combinan en una única observación oficial.'
  ) into result;
  return result;
end;
$$;

revoke all on function public.record_pachanga_global_rating_v2(uuid, text, text, text, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.ensure_pachanga_external_team_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.record_pachanga_global_rating_authoritative_v2(uuid, text, text, text, uuid, uuid, uuid, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.get_pachanga_global_rating_context_v2(uuid, text)
  from public, anon;

grant execute on function public.ensure_pachanga_external_team_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.record_pachanga_global_rating_authoritative_v2(uuid, text, text, text, uuid, uuid, uuid, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.get_pachanga_global_rating_context_v2(uuid, text)
  to authenticated;
