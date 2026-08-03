-- Pachangas IQ rating system V2: deterministic global calibration.

create or replace function public.pachanga_host_lineup_level_v2(
  target_group_id uuid,
  target_match_id text
)
returns numeric
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select avg(nullif(participants.card_snapshot ->> 'currentOverall', '')::numeric)
  from public.pachanga_match_rating_participants participants
  where participants.group_id = target_group_id
    and participants.match_id = target_match_id
    and participants.player_profile_id is not null
    and participants.attendance_confirmed
    and not participants.was_reserve;
$$;

create or replace function public.pachanga_refresh_global_official_v2(
  source_group_id uuid,
  source_match_id text,
  source_target_kind text,
  source_guest_id uuid default null,
  source_external_team_id uuid default null,
  source_target_group_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  official_id uuid;
  calculated_observation numeric;
  calculated_count integer;
  calculated_ids uuid[];
begin
  select
    avg(responses.observation),
    count(*)::integer,
    array_agg(responses.id order by coalesce(responses.actor_user_id, responses.actor_guest_identity_id))
  into calculated_observation, calculated_count, calculated_ids
  from public.pachanga_global_rating_responses responses
  where responses.group_id = source_group_id
    and responses.match_id = source_match_id
    and responses.target_kind = source_target_kind
    and responses.guest_identity_id is not distinct from source_guest_id
    and responses.external_team_id is not distinct from source_external_team_id
    and responses.target_group_id is not distinct from source_target_group_id;

  if calculated_count < 1 then raise exception 'No global responses to aggregate'; end if;

  select evidence.id into official_id
  from public.pachanga_global_rating_evidence evidence
  where evidence.group_id = source_group_id
    and evidence.match_id = source_match_id
    and evidence.target_kind = source_target_kind
    and evidence.guest_identity_id is not distinct from source_guest_id
    and evidence.external_team_id is not distinct from source_external_team_id
    and evidence.target_group_id is not distinct from source_target_group_id
  for update;

  if official_id is null then
    insert into public.pachanga_global_rating_evidence(
      group_id, match_id, target_kind, guest_identity_id, external_team_id,
      target_group_id, official_observation, response_count, response_ids,
      engine_version
    ) values (
      source_group_id, source_match_id, source_target_kind, source_guest_id,
      source_external_team_id, source_target_group_id, calculated_observation,
      calculated_count, calculated_ids, 'pachangas-rating-v2-global-1'
    ) returning id into official_id;
  else
    update public.pachanga_global_rating_evidence
    set official_observation = calculated_observation,
        response_count = calculated_count,
        response_ids = calculated_ids,
        engine_version = 'pachangas-rating-v2-global-1',
        updated_at = clock_timestamp()
    where id = official_id;
  end if;

  return jsonb_build_object(
    'officialEvidenceId', official_id,
    'officialObservation', calculated_observation,
    'responseCount', calculated_count
  );
end;
$$;

create or replace function public.pachanga_recalculate_guest_level_v2(target_guest_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  calculated_level numeric;
  calculated_count integer;
  calculated_at timestamptz;
begin
  select avg(evidence.official_observation), count(*)::integer, max(evidence.updated_at)
  into calculated_level, calculated_count, calculated_at
  from public.pachanga_global_rating_evidence evidence
  where evidence.target_kind = 'guest'
    and evidence.guest_identity_id = target_guest_id;

  update public.pachanga_guest_identities
  set provisional_level = calculated_level,
      provisional_observation_count = calculated_count,
      provisional_last_observed_at = calculated_at,
      updated_at = clock_timestamp()
  where id = target_guest_id;

  return jsonb_build_object(
    'provisionalLevel', calculated_level,
    'observationCount', calculated_count,
    'lastObservedAt', calculated_at
  );
end;
$$;

create or replace function public.pachanga_recalculate_group_external_level_v2(
  target_group_id uuid,
  at_time timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  base_level numeric;
  calibrated_level numeric;
  evidence_count integer;
  evidence_weight numeric;
  weighted_total numeric;
  evidence_ids uuid[];
  result jsonb;
begin
  base_level := coalesce(public.pachanga_group_level_v2(
    pachanga_recalculate_group_external_level_v2.target_group_id,
    at_time
  ), 50);

  with valid_evidence as (
    select evidence.id, evidence.official_observation, 1::numeric as source_weight
    from public.pachanga_global_rating_evidence evidence
    where evidence.target_kind = 'registered_group'
      and evidence.target_group_id = pachanga_recalculate_group_external_level_v2.target_group_id
      and evidence.updated_at >= at_time - interval '12 months'
      and evidence.updated_at <= at_time
    union all
    select evidence.id, evidence.official_observation, 0.5::numeric as source_weight
    from public.pachanga_global_rating_evidence evidence
    where evidence.target_kind = 'host_team'
      and evidence.group_id = pachanga_recalculate_group_external_level_v2.target_group_id
      and evidence.updated_at >= at_time - interval '12 months'
      and evidence.updated_at <= at_time
  )
  select
    count(*)::integer,
    coalesce(sum(source_weight), 0),
    coalesce(sum(
      source_weight * public.pachanga_rating_v2_clamp(
        official_observation,
        greatest(0, base_level - 10),
        least(100, base_level + 10)
      )
    ), 0),
    coalesce(array_agg(id order by id), '{}'::uuid[])
  into evidence_count, evidence_weight, weighted_total, evidence_ids
  from valid_evidence;

  calibrated_level := public.pachanga_rating_v2_clamp(
    (5 * base_level + weighted_total) / (5 + evidence_weight)
  );
  result := jsonb_build_object(
    'baseLevel', base_level,
    'priorWeight', 5,
    'calibratedLevel', calibrated_level,
    'evidenceCount', evidence_count,
    'evidenceWeight', evidence_weight,
    'evidenceIds', to_jsonb(evidence_ids),
    'windowMonths', 12,
    'engineVersion', 'pachangas-rating-v2-external-1',
    'calculatedAt', at_time
  );

  update public.pachanga_groups
  set externally_calibrated_level = calibrated_level,
      external_calibration_snapshot = result,
      external_calibrated_at = at_time
  where id = pachanga_recalculate_group_external_level_v2.target_group_id;

  insert into public.pachanga_team_external_rating_snapshots(
    group_id, base_level, calibrated_level, prior_weight, evidence_count,
    evidence_weight, evidence_ids, engine_version, calculated_at
  ) values (
    pachanga_recalculate_group_external_level_v2.target_group_id,
    base_level, calibrated_level, 5, evidence_count,
    evidence_weight, evidence_ids, 'pachangas-rating-v2-external-1', at_time
  );
  return result;
end;
$$;

create or replace function public.pachanga_recalculate_external_team_level_v2(
  target_external_team_id uuid,
  at_time timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  base_level numeric;
  calculated_level numeric;
  evidence_count integer;
  weighted_total numeric;
  result jsonb;
begin
  select coalesce(teams.stable_level, teams.calibrated_external_level, 50)
  into base_level
  from public.pachanga_external_teams teams
  where teams.id = target_external_team_id
  for update;
  if base_level is null then raise exception 'External team not found'; end if;

  select count(*)::integer,
    coalesce(sum(public.pachanga_rating_v2_clamp(
      evidence.official_observation,
      greatest(0, base_level - 10),
      least(100, base_level + 10)
    )), 0)
  into evidence_count, weighted_total
  from public.pachanga_global_rating_evidence evidence
  where evidence.target_kind = 'external_team'
    and evidence.external_team_id = target_external_team_id
    and evidence.updated_at >= at_time - interval '12 months'
    and evidence.updated_at <= at_time;

  calculated_level := public.pachanga_rating_v2_clamp(
    (5 * base_level + weighted_total) / (5 + evidence_count)
  );
  update public.pachanga_external_teams
  set stable_level = coalesce(stable_level, base_level),
      calibrated_external_level = calculated_level,
      calibration_observation_count = evidence_count,
      calibrated_at = at_time,
      updated_at = clock_timestamp()
  where id = target_external_team_id;
  result := jsonb_build_object(
    'baseLevel', base_level,
    'priorWeight', 5,
    'calibratedLevel', calculated_level,
    'evidenceCount', evidence_count,
    'windowMonths', 12,
    'engineVersion', 'pachangas-rating-v2-external-1',
    'calculatedAt', at_time
  );
  return result;
end;
$$;

revoke all on function public.pachanga_host_lineup_level_v2(uuid, text)
  from public, anon, authenticated;
revoke all on function public.pachanga_refresh_global_official_v2(uuid, text, text, uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.pachanga_recalculate_guest_level_v2(uuid)
  from public, anon, authenticated;
revoke all on function public.pachanga_recalculate_group_external_level_v2(uuid, timestamptz)
  from public, anon, authenticated;
revoke all on function public.pachanga_recalculate_external_team_level_v2(uuid, timestamptz)
  from public, anon, authenticated;
