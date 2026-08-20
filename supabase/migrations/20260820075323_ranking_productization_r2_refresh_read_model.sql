-- Ranking Productization V1 / R2.
-- Durable refresh queue, deterministic rebuilds and canonical read-model candidates.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table if not exists private.pachanga_ranking_refresh_queue (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  refresh_scope text not null default 'player',
  reason text not null,
  source_type text not null,
  source_id text not null,
  source_sequence bigint,
  expected_season_revision bigint not null,
  operation_id uuid not null unique,
  state text not null default 'queued',
  attempts integer not null default 0,
  available_at timestamptz not null default clock_timestamp(),
  claimed_at timestamptz,
  completed_at timestamptz,
  error_code text,
  error_detail text,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (refresh_scope in ('player', 'season')),
  check ((refresh_scope = 'player' and player_profile_id is not null)
    or (refresh_scope = 'season' and player_profile_id is null)),
  check (state in ('queued', 'processing', 'completed', 'failed', 'dead_letter')),
  check (attempts between 0 and 20),
  check (expected_season_revision >= 1),
  check (char_length(reason) between 3 and 240),
  check (char_length(source_type) between 2 and 80),
  check (char_length(source_id) between 1 and 240),
  check (error_code is null or char_length(error_code) <= 120),
  check (error_detail is null or char_length(error_detail) <= 500)
);

create index if not exists pachanga_ranking_refresh_queue_claim_idx
  on private.pachanga_ranking_refresh_queue(state, available_at, server_sequence, id)
  where state in ('queued', 'failed');
create index if not exists pachanga_ranking_refresh_queue_target_idx
  on private.pachanga_ranking_refresh_queue(season_id, player_profile_id, server_sequence desc, id desc);
create unique index if not exists pachanga_ranking_refresh_queue_active_target_idx
  on private.pachanga_ranking_refresh_queue(
    season_id,
    coalesce(player_profile_id, '00000000-0000-0000-0000-000000000000'::uuid),
    refresh_scope
  )
  where state in ('queued', 'processing', 'failed');

create table if not exists private.pachanga_ranking_rebuilds (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  rebuild_revision bigint not null,
  expected_season_revision bigint not null,
  graph_batch_id uuid,
  state text not null default 'building',
  reason text not null,
  operation_id uuid not null unique,
  actor_user_id uuid references auth.users(id) on delete restrict,
  candidate_checksum text,
  published_checksum text,
  candidate_count integer not null default 0,
  changed_count integer not null default 0,
  error_code text,
  error_detail text,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  check (rebuild_revision >= 1 and expected_season_revision >= 1),
  check (state in ('building', 'candidate_ready', 'published', 'failed', 'discarded')),
  check (char_length(reason) between 3 and 1200),
  check (candidate_count >= 0 and changed_count >= 0),
  check (candidate_checksum is null or candidate_checksum ~ '^[0-9a-f]{64}$'),
  check (published_checksum is null or published_checksum ~ '^[0-9a-f]{64}$'),
  check (error_code is null or char_length(error_code) <= 120),
  check (error_detail is null or char_length(error_detail) <= 500)
);

create unique index if not exists pachanga_ranking_rebuild_revision_idx
  on private.pachanga_ranking_rebuilds(season_id, rebuild_revision);
create index if not exists pachanga_ranking_rebuild_state_idx
  on private.pachanga_ranking_rebuilds(season_id, state, server_sequence desc, id desc);

create table if not exists private.pachanga_ranking_candidates (
  rebuild_id uuid not null references private.pachanga_ranking_rebuilds(id) on delete restrict,
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  province_code text not null references private.pachanga_ranking_territories(province_code) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  snapshot_id uuid not null references private.pachanga_season_score_snapshots(id) on delete restrict,
  candidate_rank integer,
  tie_break jsonb not null,
  candidate_checksum text not null,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  primary key (rebuild_id, player_profile_id),
  check (candidate_rank is null or candidate_rank >= 1),
  check (jsonb_typeof(tie_break) = 'object'),
  check (candidate_checksum ~ '^[0-9a-f]{64}$')
);

create index if not exists pachanga_ranking_candidates_order_idx
  on private.pachanga_ranking_candidates(rebuild_id, province_code, candidate_rank, player_profile_id);

revoke all on table private.pachanga_ranking_refresh_queue from public, anon, authenticated;
revoke all on table private.pachanga_ranking_rebuilds from public, anon, authenticated;
revoke all on table private.pachanga_ranking_candidates from public, anon, authenticated;
grant all on table private.pachanga_ranking_refresh_queue to service_role;
grant all on table private.pachanga_ranking_rebuilds to service_role;
grant all on table private.pachanga_ranking_candidates to service_role;

create or replace function private.pachanga_ranking_clamp_v1(
  source numeric,
  minimum_value numeric,
  maximum_value numeric
)
returns numeric
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select greatest(minimum_value, least(maximum_value, source));
$$;

create or replace function private.pachanga_ranking_expected_result_v1(
  team_rating numeric,
  opponent_rating numeric
)
returns numeric
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select 1 / (1 + power(10::numeric, (opponent_rating - team_rating) / 32));
$$;

create or replace function private.pachanga_ranking_confidence_weight_v1(confidence numeric)
returns numeric
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select case
    when confidence < 0.50 then 0
    when confidence >= 0.75 then 1
    else 0.35 + ((confidence - 0.50) / 0.25) * 0.65
  end;
$$;

revoke all on function private.pachanga_ranking_clamp_v1(numeric, numeric, numeric)
  from public, anon, authenticated;
revoke all on function private.pachanga_ranking_expected_result_v1(numeric, numeric)
  from public, anon, authenticated;
revoke all on function private.pachanga_ranking_confidence_weight_v1(numeric)
  from public, anon, authenticated;

comment on table private.pachanga_ranking_refresh_queue is
  'Durable idempotent refresh intents. A queued operation is never a confirmed ranking change.';
comment on table private.pachanga_ranking_candidates is
  'Private candidate rows. They are not public until an explicit compare-and-publish operation succeeds.';

create or replace function private.pachanga_rebuild_season_team_graph_v1(
  target_season_id uuid,
  target_graph_revision bigint,
  target_batch_id uuid default gen_random_uuid()
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_season private.pachanga_ranking_seasons%rowtype;
begin
  if target_season_id is null or target_batch_id is null or target_graph_revision < 1 then
    raise exception 'seasonId, graphRevision and batchId required';
  end if;
  select * into selected_season
  from private.pachanga_ranking_seasons seasons
  where seasons.id = target_season_id;
  if not found then raise exception 'Ranking season not found'; end if;

  with recursive
  participating_groups as (
    select matches.home_group_id as group_id
    from public.pachanga_external_matches matches
    where matches.scheduled_at >= selected_season.starts_at
      and matches.scheduled_at < selected_season.ends_at
      and matches.state in ('confirmed', 'auto_confirmed')
    union
    select matches.away_group_id
    from public.pachanga_external_matches matches
    where matches.scheduled_at >= selected_season.starts_at
      and matches.scheduled_at < selected_season.ends_at
      and matches.state in ('confirmed', 'auto_confirmed')
  ),
  roster as (
    select participants.group_id,
      array_agg(distinct participants.player_profile_id order by participants.player_profile_id)
        filter (where participants.player_profile_id is not null) as profile_ids
    from public.pachanga_external_matches matches
    join public.pachanga_external_match_participants participants
      on participants.external_match_id = matches.id
     and participants.result_version = matches.official_version
    where matches.scheduled_at >= selected_season.starts_at
      and matches.scheduled_at < selected_season.ends_at
      and matches.state in ('confirmed', 'auto_confirmed')
    group by participants.group_id
  ),
  group_data as (
    select groups.id as group_id,
      groups.owner_id,
      groups.created_at,
      coalesce(roster.profile_ids, '{}'::uuid[]) as roster_profile_ids,
      coalesce((
        select array_agg(distinct members.user_id order by members.user_id)
        from public.pachanga_group_members members
        where members.group_id = groups.id
          and members.role in ('owner', 'admin')
      ), array[groups.owner_id]::uuid[]) as admin_user_ids
    from public.pachanga_groups groups
    join participating_groups participating on participating.group_id = groups.id
    left join roster on roster.group_id = groups.id
  ),
  pair_signals as (
    select left_group.group_id as left_id,
      right_group.group_id as right_id,
      overlap.intersection_count::numeric / greatest(
        1,
        cardinality(left_group.roster_profile_ids)
          + cardinality(right_group.roster_profile_ids)
          - overlap.intersection_count
      ) as roster_overlap,
      left_group.admin_user_ids && right_group.admin_user_ids as shared_admin,
      left_group.created_at >= selected_season.starts_at - interval '45 days'
        and right_group.created_at >= selected_season.starts_at - interval '45 days' as both_new
    from group_data left_group
    join group_data right_group on right_group.group_id > left_group.group_id
    cross join lateral (
      select count(*)::integer as intersection_count
      from unnest(left_group.roster_profile_ids) profile_id
      where profile_id = any(right_group.roster_profile_ids)
    ) overlap
  ),
  edges as (
    select group_id as left_id, group_id as right_id from group_data
    union all
    select left_id, right_id
    from pair_signals
    where roster_overlap >= 0.75
       or (roster_overlap >= 0.55 and shared_admin and both_new)
    union all
    select right_id, left_id
    from pair_signals
    where roster_overlap >= 0.75
       or (roster_overlap >= 0.55 and shared_admin and both_new)
  ),
  reach(root_id, node_id) as (
    select group_id, group_id from group_data
    union
    select reach.root_id, edges.right_id
    from reach
    join edges on edges.left_id = reach.node_id
  ),
  components as (
    select node_id as group_id, min(root_id::text)::uuid as component_id
    from reach
    group by node_id
  ),
  component_sizes as (
    select component_id, count(*)::integer as cluster_size
    from components
    group by component_id
  ),
  neighbors as (
    select home_group_id as group_id,
      array_agg(distinct away_group_id order by away_group_id) as group_ids
    from public.pachanga_external_matches matches
    where matches.scheduled_at >= selected_season.starts_at
      and matches.scheduled_at < selected_season.ends_at
      and matches.state in ('confirmed', 'auto_confirmed')
    group by home_group_id
    union all
    select away_group_id,
      array_agg(distinct home_group_id order by home_group_id)
    from public.pachanga_external_matches matches
    where matches.scheduled_at >= selected_season.starts_at
      and matches.scheduled_at < selected_season.ends_at
      and matches.state in ('confirmed', 'auto_confirmed')
    group by away_group_id
  ),
  merged_neighbors as (
    select group_id,
      array_agg(distinct neighbor_id order by neighbor_id) as group_ids
    from neighbors
    cross join lateral unnest(neighbors.group_ids) neighbor_id
    group by group_id
  )
  insert into private.pachanga_season_team_graph_snapshots(
    batch_id, season_id, graph_revision, group_id, logical_opponent_id,
    owner_user_id, admin_user_ids, roster_profile_ids, neighbor_group_ids,
    logical_cluster_size, input_checksum
  )
  select target_batch_id,
    target_season_id,
    target_graph_revision,
    groups.group_id,
    'logical:' || components.component_id::text,
    groups.owner_id,
    groups.admin_user_ids,
    groups.roster_profile_ids,
    coalesce(merged_neighbors.group_ids, '{}'::uuid[]),
    component_sizes.cluster_size,
    private.pachanga_ranking_json_checksum_v1(jsonb_build_object(
      'groupId', groups.group_id,
      'componentId', components.component_id,
      'ownerUserId', groups.owner_id,
      'adminUserIds', to_jsonb(groups.admin_user_ids),
      'rosterProfileIds', to_jsonb(groups.roster_profile_ids),
      'neighbors', to_jsonb(coalesce(merged_neighbors.group_ids, '{}'::uuid[])),
      'clusterSize', component_sizes.cluster_size,
      'graphRevision', target_graph_revision
    ))
  from group_data groups
  join components on components.group_id = groups.group_id
  join component_sizes on component_sizes.component_id = components.component_id
  left join merged_neighbors on merged_neighbors.group_id = groups.group_id;

  return target_batch_id;
end;
$$;

revoke all on function private.pachanga_rebuild_season_team_graph_v1(uuid, bigint, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_season_player_evidence_v1(
  target_season_id uuid,
  target_player_profile_id uuid,
  target_graph_batch_id uuid
)
returns table (
  external_match_id uuid,
  occurred_at timestamptz,
  province_code text,
  team_group_id uuid,
  opponent_group_id uuid,
  opponent_logical_id text,
  result_value numeric,
  team_rating numeric,
  opponent_rating numeric,
  opponent_independence numeric,
  participation_confidence numeric,
  venue_confidence numeric,
  match_confidence numeric,
  confidence_weight numeric,
  eligible_evidence boolean,
  exclusion_reasons text[]
)
language sql
security definer
stable
set search_path = pg_catalog
as $$
  with season as (
    select *
    from private.pachanga_ranking_seasons seasons
    where seasons.id = target_season_id
  ),
  base as (
    select matches.id as external_match_id,
      matches.scheduled_at as occurred_at,
      participants.group_id as team_group_id,
      case when participants.group_id = matches.home_group_id
        then matches.away_group_id else matches.home_group_id end as opponent_group_id,
      case
        when matches.canonical_score_home = matches.canonical_score_away then 0.5::numeric
        when participants.group_id = matches.home_group_id
          and matches.canonical_score_home > matches.canonical_score_away then 1::numeric
        when participants.group_id = matches.away_group_id
          and matches.canonical_score_away > matches.canonical_score_home then 1::numeric
        else 0::numeric
      end as result_value,
      case when participants.group_id = matches.home_group_id
        then matches.home_level_snapshot else matches.away_level_snapshot end as team_rating,
      case when participants.group_id = matches.home_group_id
        then matches.away_level_snapshot else matches.home_level_snapshot end as opponent_rating,
      matches.state,
      matches.modality,
      matches.field_snapshot ->> 'placeId' as place_id,
      matches.home_group_id,
      matches.away_group_id,
      matches.official_version,
      challenges.status as challenge_status
    from season
    join public.pachanga_external_matches matches
      on matches.scheduled_at >= season.starts_at
     and matches.scheduled_at < season.ends_at
     and matches.state in ('confirmed', 'auto_confirmed')
     and matches.official_version is not null
    join public.pachanga_team_challenges challenges on challenges.id = matches.challenge_id
    join public.pachanga_external_match_participants participants
      on participants.external_match_id = matches.id
     and participants.result_version = matches.official_version
     and participants.player_profile_id = target_player_profile_id
  ),
  measured as (
    select base.*,
      venue.province_code,
      coalesce(venue.confidence, 0) as venue_confidence,
      team_graph.owner_user_id as team_owner_id,
      opponent_graph.owner_user_id as opponent_owner_id,
      team_graph.admin_user_ids as team_admin_ids,
      opponent_graph.admin_user_ids as opponent_admin_ids,
      team_graph.roster_profile_ids as team_roster_ids,
      opponent_graph.roster_profile_ids as opponent_roster_ids,
      team_graph.neighbor_group_ids as team_neighbor_ids,
      opponent_graph.neighbor_group_ids as opponent_neighbor_ids,
      opponent_graph.logical_opponent_id,
      coalesce(opponent_graph.logical_cluster_size, 1) as opponent_cluster_size,
      team_group.created_at as team_created_at,
      opponent_group.created_at as opponent_created_at,
      participant_counts.home_count,
      participant_counts.away_count,
      greatest(1, case base.modality when 'sala' then 5 when 'futbol7' then 7 else 11 end) as expected_players
    from base
    left join private.pachanga_ranking_venue_territories venue
      on venue.place_id = base.place_id
     and venue.effective_until is null
    left join private.pachanga_season_team_graph_snapshots team_graph
      on team_graph.batch_id = target_graph_batch_id
     and team_graph.group_id = base.team_group_id
    left join private.pachanga_season_team_graph_snapshots opponent_graph
      on opponent_graph.batch_id = target_graph_batch_id
     and opponent_graph.group_id = base.opponent_group_id
    join public.pachanga_groups team_group on team_group.id = base.team_group_id
    join public.pachanga_groups opponent_group on opponent_group.id = base.opponent_group_id
    cross join lateral (
      select
        count(*) filter (where participants.group_id = base.home_group_id)::integer as home_count,
        count(*) filter (where participants.group_id = base.away_group_id)::integer as away_count
      from public.pachanga_external_match_participants participants
      where participants.external_match_id = base.external_match_id
        and participants.result_version = base.official_version
    ) participant_counts
  ),
  signals as (
    select measured.*,
      roster_overlap.intersection_count::numeric / greatest(
        1,
        cardinality(coalesce(measured.team_roster_ids, '{}'::uuid[]))
          + cardinality(coalesce(measured.opponent_roster_ids, '{}'::uuid[]))
          - roster_overlap.intersection_count
      ) as roster_overlap,
      coalesce(measured.team_admin_ids && measured.opponent_admin_ids, false) as shared_admin,
      measured.team_owner_id is not null
        and measured.team_owner_id = measured.opponent_owner_id as same_owner,
      measured.team_created_at >= measured.occurred_at - interval '45 days'
        and measured.opponent_created_at >= measured.occurred_at - interval '45 days' as both_new,
      neighbor_overlap.intersection_count::numeric / greatest(
        1,
        least(
          cardinality(coalesce(measured.team_neighbor_ids, '{}'::uuid[])),
          cardinality(coalesce(measured.opponent_neighbor_ids, '{}'::uuid[]))
        )
      ) as closed_pair_ratio,
      least(1::numeric,
        least(measured.home_count, measured.away_count)::numeric / measured.expected_players
      ) as participation_confidence,
      private.pachanga_ranking_clamp_v1((
        select count(*)::numeric
        from public.pachanga_external_matches same_day
        join public.pachanga_external_match_participants same_day_participant
          on same_day_participant.external_match_id = same_day.id
         and same_day_participant.result_version = same_day.official_version
         and same_day_participant.player_profile_id = target_player_profile_id
        where same_day.state in ('confirmed', 'auto_confirmed')
          and (same_day.scheduled_at at time zone 'UTC')::date
            = (measured.occurred_at at time zone 'UTC')::date
      ) - 2, 0, 8) / 8 as day_anomaly,
      exists (
        select 1
        from public.pachanga_external_result_attestations attestations
        where attestations.external_match_id = measured.external_match_id
          and attestations.result_version = measured.official_version
          and attestations.decision = 'accepted'
      ) as has_bilateral_acceptance
    from measured
    cross join lateral (
      select count(*)::integer as intersection_count
      from unnest(coalesce(measured.team_roster_ids, '{}'::uuid[])) profile_id
      where profile_id = any(coalesce(measured.opponent_roster_ids, '{}'::uuid[]))
    ) roster_overlap
    cross join lateral (
      select count(*)::integer as intersection_count
      from unnest(coalesce(measured.team_neighbor_ids, '{}'::uuid[])) group_id
      where group_id = any(coalesce(measured.opponent_neighbor_ids, '{}'::uuid[]))
    ) neighbor_overlap
  ),
  independent as (
    select signals.*,
      private.pachanga_ranking_clamp_v1(
        (1
          - signals.roster_overlap * 0.55
          - case when signals.shared_admin then 0.18 else 0 end
          - case when signals.same_owner then 0.08 else 0 end
          - case when signals.same_owner and signals.shared_admin then 0.04 else 0 end
          - case when signals.both_new then 0.08 else 0 end
          - signals.closed_pair_ratio * 0.11
        ) / greatest(1, signals.opponent_cluster_size),
        0, 1
      ) as opponent_independence
    from signals
  ),
  confident as (
    select independent.*,
      private.pachanga_ranking_clamp_v1(
        case when independent.challenge_status = 'accepted' then 0.15 else 0 end
        + case when independent.occurred_at is not null then 0.05 else 0 end
        + independent.venue_confidence * 0.10
        + independent.participation_confidence * 0.35
        + case
            when independent.state = 'confirmed' then 0.17
            when independent.state = 'auto_confirmed' then 0.72 * 0.17
            else 0
          end
        + private.pachanga_ranking_clamp_v1(
            least(
              extract(epoch from (independent.occurred_at - independent.team_created_at)) / 86400,
              extract(epoch from (independent.occurred_at - independent.opponent_created_at)) / 86400
            ) / 120,
            0, 1
          ) * 0.08
        + private.pachanga_ranking_clamp_v1(
            cardinality(coalesce(independent.opponent_neighbor_ids, '{}'::uuid[]))::numeric / 5,
            0, 1
          ) * 0.04
        + independent.opponent_independence * 0.06
        - independent.day_anomaly * 0.28,
        0, 1
      ) as match_confidence
    from independent
  )
  select confident.external_match_id,
    confident.occurred_at,
    confident.province_code,
    confident.team_group_id,
    confident.opponent_group_id,
    confident.logical_opponent_id,
    confident.result_value,
    confident.team_rating,
    confident.opponent_rating,
    confident.opponent_independence,
    confident.participation_confidence,
    confident.venue_confidence,
    confident.match_confidence,
    private.pachanga_ranking_confidence_weight_v1(confident.match_confidence),
    confident.province_code is not null
      and confident.logical_opponent_id is not null
      and confident.team_rating between 0 and 100
      and confident.opponent_rating between 0 and 100
      and confident.venue_confidence >= 0.50
      and confident.participation_confidence >= 0.50
      and confident.opponent_independence >= 0.50
      and confident.match_confidence >= 0.50 as eligible_evidence,
    array_remove(array[
      case when confident.province_code is null then 'territory_unverified' end,
      case when confident.logical_opponent_id is null then 'team_graph_missing' end,
      case when confident.team_rating is null or confident.opponent_rating is null then 'team_rating_missing' end,
      case when confident.venue_confidence < 0.50 then 'venue_confidence_low' end,
      case when confident.participation_confidence < 0.50 then 'participation_confidence_low' end,
      case when confident.opponent_independence < 0.50 then 'opponent_independence_low' end,
      case when confident.match_confidence < 0.50 then 'match_confidence_low' end,
      case when confident.day_anomaly > 0 then 'same_day_match_frequency_anomaly' end
    ]::text[], null)
  from confident
  order by confident.occurred_at, confident.external_match_id;
$$;

revoke all on function private.pachanga_season_player_evidence_v1(uuid, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_calculate_season_score_v1(
  target_season_id uuid,
  target_player_profile_id uuid,
  target_graph_batch_id uuid,
  target_snapshot_revision bigint,
  target_operation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_season private.pachanga_ranking_seasons%rowtype;
  selected_formula private.pachanga_season_score_formula_registry%rowtype;
  selected_profile public.pachanga_player_profiles%rowtype;
  latest_rating_snapshot_id uuid;
  previous_province_code text;
  resolved_province_code text;
  evidence jsonb := '[]'::jsonb;
  valid_challenges integer := 0;
  logical_opponents integer := 0;
  technical_opponents integer := 0;
  latest_activity timestamptz;
  latest_evidence_activity timestamptz;
  score_window_opponents integer := 0;
  weighted_challenges numeric := 0;
  competition_evidence numeric := 50;
  opponent_strength numeric := 50;
  competition_confidence numeric := 0;
  competitive_confidence numeric := 0;
  network_diversity numeric := 0;
  low_confidence_ratio numeric := 0;
  rating_overall numeric;
  rating_reliability numeric;
  quality_value numeric;
  competition_value numeric;
  opposition_value numeric;
  quality_contribution numeric;
  competition_contribution numeric;
  opposition_contribution numeric;
  raw_score numeric;
  visible_score integer;
  risk numeric := 0;
  risk_classification text := 'clean';
  risk_signals jsonb := '{}'::jsonb;
  reason_codes text[] := '{}'::text[];
  safe_reason_codes text[] := '{}'::text[];
  trophy_reason_codes text[] := '{}'::text[];
  eligibility_state text;
  trophy_readiness boolean := false;
  evidence_revision text;
  rating_input_key text;
  score_reached_at timestamptz;
  saved_snapshot_id uuid;
  as_of_at timestamptz;
begin
  if target_season_id is null or target_player_profile_id is null
    or target_graph_batch_id is null or target_snapshot_revision < 1
    or target_operation_id is null then
    raise exception 'Season score calculation arguments required';
  end if;

  select * into selected_season
  from private.pachanga_ranking_seasons seasons
  where seasons.id = target_season_id;
  if not found then raise exception 'Ranking season not found'; end if;

  select * into selected_formula
  from private.pachanga_season_score_formula_registry formulas
  where formulas.formula_key = selected_season.formula_key
    and formulas.formula_version = selected_season.formula_version;
  if not found or selected_formula.configuration_checksum <> selected_season.formula_checksum then
    raise exception 'Ranking formula checksum mismatch';
  end if;

  select * into selected_profile
  from public.pachanga_player_profiles profiles
  where profiles.id = target_player_profile_id;
  if not found then raise exception 'Player profile not found'; end if;

  rating_overall := selected_profile.current_overall;
  rating_reliability := coalesce(selected_profile.rating_reliability, 0) / 100;
  if rating_overall is null or rating_overall not between 0 and 100 then
    raise exception 'Canonical Rating V2 input unavailable';
  end if;

  select snapshots.id into latest_rating_snapshot_id
  from public.pachanga_player_rating_snapshots snapshots
  where snapshots.player_profile_id = target_player_profile_id
  order by snapshots.created_at desc, snapshots.id desc
  limit 1;
  rating_input_key := concat_ws(':',
    target_player_profile_id::text,
    selected_profile.profile_version::text,
    coalesce(latest_rating_snapshot_id::text, 'profile'),
    coalesce(selected_profile.rating_recalculated_at::text, selected_profile.updated_at::text)
  );

  select snapshots.province_code into previous_province_code
  from private.pachanga_season_score_snapshots snapshots
  where snapshots.season_id = target_season_id
    and snapshots.player_profile_id = target_player_profile_id
  order by snapshots.snapshot_revision desc, snapshots.server_sequence desc, snapshots.id desc
  limit 1;

  select coalesce(jsonb_agg(to_jsonb(rows) order by rows.occurred_at, rows.external_match_id), '[]'::jsonb)
  into evidence
  from private.pachanga_season_player_evidence_v1(
    target_season_id, target_player_profile_id, target_graph_batch_id
  ) rows;

  with rows as (
    select *
    from jsonb_to_recordset(evidence) as evidence_rows(
      external_match_id uuid,
      occurred_at timestamptz,
      province_code text,
      team_group_id uuid,
      opponent_group_id uuid,
      opponent_logical_id text,
      result_value numeric,
      team_rating numeric,
      opponent_rating numeric,
      opponent_independence numeric,
      participation_confidence numeric,
      venue_confidence numeric,
      match_confidence numeric,
      confidence_weight numeric,
      eligible_evidence boolean,
      exclusion_reasons text[]
    )
  ),
  province_counts as (
    select province_code, count(*)::integer as evidence_count
    from rows
    where eligible_evidence
    group by province_code
  ),
  maximum as (
    select max(evidence_count) as evidence_count from province_counts
  ),
  tied as (
    select counts.province_code, counts.evidence_count
    from province_counts counts
    join maximum on maximum.evidence_count = counts.evidence_count
  ),
  reached as (
    select tied.province_code,
      max(rows.occurred_at) filter (
        where running.position <= tied.evidence_count
      ) as reached_at
    from tied
    join rows on rows.province_code = tied.province_code and rows.eligible_evidence
    cross join lateral (
      select count(*)::integer as position
      from rows earlier
      where earlier.eligible_evidence
        and earlier.province_code = rows.province_code
        and (earlier.occurred_at, earlier.external_match_id)
          <= (rows.occurred_at, rows.external_match_id)
    ) running
    group by tied.province_code
  )
  select reached.province_code into resolved_province_code
  from reached
  order by case when reached.province_code = previous_province_code then 0 else 1 end,
    reached.reached_at,
    reached.province_code
  limit 1;

  with rows as (
    select *
    from jsonb_to_recordset(evidence) as evidence_rows(
      external_match_id uuid,
      occurred_at timestamptz,
      province_code text,
      team_group_id uuid,
      opponent_group_id uuid,
      opponent_logical_id text,
      result_value numeric,
      team_rating numeric,
      opponent_rating numeric,
      opponent_independence numeric,
      participation_confidence numeric,
      venue_confidence numeric,
      match_confidence numeric,
      confidence_weight numeric,
      eligible_evidence boolean,
      exclusion_reasons text[]
    )
  ),
  valid as (
    select * from rows where eligible_evidence
  ),
  latest_thirty as (
    select *
    from valid
    order by occurred_at desc, external_match_id desc
    limit 30
  ),
  encountered as (
    select latest_thirty.*,
      row_number() over (
        partition by opponent_logical_id order by occurred_at, external_match_id
      ) as encounter_number
    from latest_thirty
  ),
  weighted as (
    select encountered.*,
      confidence_weight * opponent_independence * case encounter_number
        when 1 then 1
        when 2 then 1
        when 3 then 0.5
        when 4 then 0.25
        else 0
      end as final_weight,
      private.pachanga_ranking_clamp_v1(
        50 + (
          result_value - private.pachanga_ranking_expected_result_v1(team_rating, opponent_rating)
        ) * 85,
        0, 100
      ) as performance_value
    from encountered
  )
  select (select count(*)::integer from valid),
    (select count(distinct opponent_logical_id)::integer from valid),
    (select count(distinct opponent_group_id)::integer from valid),
    (select max(occurred_at) from valid),
    (select max(occurred_at) from rows),
    coalesce(sum(final_weight), 0),
    (select count(distinct opponent_logical_id)::integer from weighted where final_weight > 0),
    coalesce(sum(performance_value * final_weight) / nullif(sum(final_weight), 0), 50),
    coalesce(sum(opponent_rating * final_weight) / nullif(sum(final_weight), 0), 50),
    coalesce((select avg(match_confidence * (0.70 + opponent_independence * 0.30)) from rows), 0)
      * (0.65 + rating_reliability * 0.35),
    coalesce((
      select count(*) filter (
        where match_confidence < 0.50 or opponent_independence < 0.50
      )::numeric / nullif(count(*), 0)
      from rows
    ), 0)
  into valid_challenges, logical_opponents, technical_opponents, latest_activity,
    latest_evidence_activity, weighted_challenges, score_window_opponents,
    competition_evidence, opponent_strength,
    competitive_confidence, low_confidence_ratio
  from weighted;

  with rows as (
    select *
    from jsonb_to_recordset(evidence) as evidence_rows(
      external_match_id uuid,
      occurred_at timestamptz,
      province_code text,
      team_group_id uuid,
      opponent_group_id uuid,
      opponent_logical_id text,
      result_value numeric,
      team_rating numeric,
      opponent_rating numeric,
      opponent_independence numeric,
      participation_confidence numeric,
      venue_confidence numeric,
      match_confidence numeric,
      confidence_weight numeric,
      eligible_evidence boolean,
      exclusion_reasons text[]
    )
  ),
  valid as (select * from rows),
  logical as (
    select opponent_logical_id, max(opponent_independence) as independence
    from valid group by opponent_logical_id
  ),
  technical as (select distinct opponent_group_id from valid),
  closed_set as (
    select opponent_group_id as group_id from valid
    union select team_group_id from valid
  ),
  external_ratios as (
    select technical.opponent_group_id,
      coalesce((
        select count(*) filter (where not exists (
          select 1 from closed_set where closed_set.group_id = neighbor_id
        ))::numeric / nullif(count(*), 0)
        from private.pachanga_season_team_graph_snapshots graph
        cross join lateral unnest(graph.neighbor_group_ids) neighbor_id
        where graph.batch_id = target_graph_batch_id
          and graph.group_id = technical.opponent_group_id
      ), 0) as external_ratio
    from technical
  ),
  parts as (
    select
      coalesce((select sum(independence) from logical) / nullif((select count(*) from technical), 0), 0)
        as structural_diversity,
      coalesce((select avg(external_ratio) from external_ratios), 0) as external_exposure,
      coalesce((select avg(greatest(
        0,
        result_value - private.pachanga_ranking_expected_result_v1(team_rating, opponent_rating)
      )) from valid), 0) as outcome_anomaly
  )
  select private.pachanga_ranking_clamp_v1(
    (structural_diversity * 0.72 + external_exposure * 0.28)
      * (1 - outcome_anomaly * (1 - external_exposure) * 0.35),
    0, 1
  ) into network_diversity
  from parts;

  as_of_at := least(clock_timestamp(), selected_season.ends_at);
  reason_codes := array_remove(array[
    case when resolved_province_code is null then 'territory_unverified' end,
    case when valid_challenges < 15 then 'insufficient_valid_challenges' end,
    case when logical_opponents < 6 then 'insufficient_logical_opponents' end,
    case when rating_reliability < 0.45 then 'insufficient_rating_reliability' end,
    case when latest_activity is null or latest_activity < as_of_at - interval '12 weeks'
      then 'insufficient_recent_activity' end
  ]::text[], null);

  with rows as (
    select *
    from jsonb_to_recordset(evidence) as evidence_rows(
      external_match_id uuid,
      occurred_at timestamptz,
      province_code text,
      team_group_id uuid,
      opponent_group_id uuid,
      opponent_logical_id text,
      result_value numeric,
      team_rating numeric,
      opponent_rating numeric,
      opponent_independence numeric,
      participation_confidence numeric,
      venue_confidence numeric,
      match_confidence numeric,
      confidence_weight numeric,
      eligible_evidence boolean,
      exclusion_reasons text[]
    )
  ),
  source_stats as (
    select count(*)::numeric as record_count,
      count(distinct opponent_group_id)::numeric as technical_opponent_count,
      count(distinct opponent_logical_id)::numeric as logical_opponent_count,
      coalesce(avg(opponent_independence), 0) as average_independence,
      coalesce(avg(participation_confidence), 1) as average_participation,
      coalesce(avg(venue_confidence), 1) as average_venue,
      coalesce((
        select max(weekly.match_count)::numeric
        from (
          select count(*)::integer as match_count
          from rows weekly_rows
          group by date_trunc('week', weekly_rows.occurred_at at time zone 'UTC')
        ) weekly
      ), 0) as maximum_weekly_frequency,
      coalesce((
        select count(*) filter (where daily.province_count > 1)::numeric / nullif(count(*), 0)
        from (
          select count(distinct coalesce(daily_rows.province_code, '00'))::integer as province_count
          from rows daily_rows
          group by (daily_rows.occurred_at at time zone 'UTC')::date
        ) daily
      ), 0) as impossible_day_ratio,
      coalesce((
        select max(clusters.match_count)::numeric
        from (
          select count(*)::integer as match_count
          from rows cluster_rows
          group by cluster_rows.opponent_logical_id
        ) clusters
      ), 0) as maximum_cluster_count
    from rows
  ),
  signals as (
    select source_stats.*,
      private.pachanga_ranking_clamp_v1(
        (30 - extract(epoch from (as_of_at - selected_profile.created_at)) / 86400) / 30,
        0, 1
      ) * private.pachanga_ranking_clamp_v1(1 - average_independence, 0, 1)
        as account_age_cluster,
      private.pachanga_ranking_clamp_v1((maximum_weekly_frequency - 3) / 7, 0, 1)
        as abnormal_match_frequency,
      private.pachanga_ranking_clamp_v1(
        maximum_cluster_count / greatest(1, record_count) - 0.35, 0, 0.65
      ) / 0.65 as closed_network_ratio,
      private.pachanga_ranking_clamp_v1(impossible_day_ratio * 2, 0, 1)
        as impossible_travel_ratio,
      private.pachanga_ranking_clamp_v1(
        1 - logical_opponent_count / greatest(1, technical_opponent_count), 0, 1
      ) as opponent_identity_gap,
      private.pachanga_ranking_clamp_v1(1 - average_participation, 0, 1)
        as participation_anomaly,
      private.pachanga_ranking_clamp_v1((rating_overall - 80) / 20, 0, 1)
        * private.pachanga_ranking_clamp_v1(1 - record_count / 20, 0, 1)
        * (1 - average_independence * 0.5) as rating_vs_external_evidence,
      private.pachanga_ranking_clamp_v1(
        1 - logical_opponent_count / greatest(1, record_count), 0, 1
      ) as repeated_opponent_ratio,
      private.pachanga_ranking_clamp_v1(1 - average_venue, 0, 1) as venue_anomaly
    from source_stats
  )
  select case when record_count = 0
      then round(100 * (case when rating_overall >= 90 then 0.45 else 0 end) * 0.12, 4)
      else round(100 * (
        repeated_opponent_ratio * 0.10
        + opponent_identity_gap * 0.18
        + closed_network_ratio * 0.14
        + abnormal_match_frequency * 0.11
        + impossible_travel_ratio * 0.09
        + participation_anomaly * 0.08
        + venue_anomaly * 0.07
        + rating_vs_external_evidence * 0.11
        + account_age_cluster * 0.12
      ), 4)
    end,
    jsonb_build_object(
      'accountAgeCluster', case when record_count = 0 then 0 else account_age_cluster end,
      'abnormalMatchFrequency', case when record_count = 0 then 0 else abnormal_match_frequency end,
      'closedNetworkRatio', case when record_count = 0 then 0 else closed_network_ratio end,
      'impossibleTravelRatio', case when record_count = 0 then 0 else impossible_travel_ratio end,
      'opponentIdentityGap', case when record_count = 0 then 0 else opponent_identity_gap end,
      'participationAnomaly', case when record_count = 0 then 0 else participation_anomaly end,
      'ratingVsExternalEvidence', case when record_count = 0
        then case when rating_overall >= 90 then 0.45 else 0 end
        else rating_vs_external_evidence end,
      'repeatedOpponentRatio', case when record_count = 0 then 0 else repeated_opponent_ratio end,
      'venueAnomaly', case when record_count = 0 then 0 else venue_anomaly end
    )
  into risk, risk_signals
  from signals;
  risk := private.pachanga_ranking_clamp_v1(risk, 0, 100);
  risk_classification := case
    when risk >= 75 then 'high_risk'
    when risk >= 50 then 'suspicious'
    when risk >= 25 then 'watch'
    else 'clean'
  end;

  if cardinality(reason_codes) = 0 and (
    risk_classification in ('suspicious', 'high_risk')
    or low_confidence_ratio > 0.20
    or network_diversity < 0.68
  ) then
    eligibility_state := 'pending_integrity_review';
    reason_codes := reason_codes || array_remove(array[
      case when risk_classification in ('suspicious', 'high_risk') then 'integrity_anomaly' end,
      case when low_confidence_ratio > 0.20 then 'low_confidence_dependency' end,
      case when network_diversity < 0.68 then 'insufficient_network_diversity' end
    ]::text[], null);
  elsif cardinality(reason_codes) = 0 then
    eligibility_state := 'eligible';
  elsif valid_challenges > 0 and resolved_province_code is not null then
    eligibility_state := 'provisional';
  else
    eligibility_state := 'not_eligible';
  end if;

  safe_reason_codes := array_remove(array[
    case when 'territory_unverified' = any(reason_codes) then 'ranking_territory_pending' end,
    case when 'insufficient_valid_challenges' = any(reason_codes)
      or 'insufficient_logical_opponents' = any(reason_codes)
      then 'ranking_evidence_incomplete' end,
    case when 'insufficient_rating_reliability' = any(reason_codes)
      then 'rating_reliability_incomplete' end,
    case when 'insufficient_recent_activity' = any(reason_codes)
      then 'recent_activity_required' end,
    case when 'integrity_anomaly' = any(reason_codes)
      or 'low_confidence_dependency' = any(reason_codes)
      or 'insufficient_network_diversity' = any(reason_codes)
      then 'ranking_review_pending' end
  ]::text[], null);

  trophy_reason_codes := array_remove(array[
    case when eligibility_state <> 'eligible' then 'ranking_not_eligible' end,
    case when valid_challenges < 25 then 'insufficient_challenges' end,
    case when logical_opponents < 10 then 'insufficient_logical_opponents' end,
    case when competitive_confidence < 0.72 then 'insufficient_competitive_confidence' end,
    case when network_diversity < 0.68 then 'insufficient_network_diversity' end,
    case when rating_reliability < 0.55 then 'insufficient_rating_reliability' end,
    case when latest_evidence_activity is null or latest_evidence_activity < as_of_at - interval '12 weeks'
      then 'insufficient_recent_activity' end,
    case when low_confidence_ratio > 0.20 then 'low_confidence_dependency' end,
    case when risk_classification in ('suspicious', 'high_risk') then 'integrity_anomaly' end
  ]::text[], null);
  trophy_readiness := cardinality(trophy_reason_codes) = 0;

  quality_value := private.pachanga_ranking_clamp_v1(
    rating_overall * (0.72 + rating_reliability * 0.28), 0, 100
  );
  competition_confidence := 1 - exp(-weighted_challenges / 7);
  competition_value := private.pachanga_ranking_clamp_v1(
    50 * (1 - competition_confidence) + competition_evidence * competition_confidence,
    0, 100
  );
  opposition_value := private.pachanga_ranking_clamp_v1(
    opponent_strength * 0.58 + 100 * (1 - exp(-score_window_opponents::numeric / 6)) * 0.42,
    0, 100
  );
  quality_contribution := quality_value * 5.5;
  competition_contribution := competition_value * 3;
  opposition_contribution := opposition_value * 1.5;
  raw_score := private.pachanga_ranking_clamp_v1(
    quality_contribution + competition_contribution + opposition_contribution,
    0, 1000
  );
  visible_score := round(raw_score)::integer;
  score_reached_at := coalesce(latest_evidence_activity, latest_activity, selected_season.starts_at);
  evidence_revision := private.pachanga_ranking_json_checksum_v1(jsonb_build_object(
    'evidence', evidence
  ));

  if resolved_province_code is null then
    select territories.province_code into resolved_province_code
    from private.pachanga_ranking_territories territories
    where territories.province_code = '00'
    limit 1;
  end if;
  if resolved_province_code is null then raise exception 'No ranking territory configured'; end if;

  insert into private.pachanga_season_score_snapshots(
    season_id, province_code, player_profile_id, snapshot_revision,
    formula_key, formula_version, formula_checksum, evidence_revision,
    rating_input_key, rating_snapshot_id, rating_overall, rating_reliability,
    graph_batch_id, quality_component, competition_component, opposition_component,
    raw_score, visible_score, weighted_challenges, valid_challenges, logical_opponents,
    match_competitive_confidence, network_diversity, eligibility_state,
    reason_codes, safe_reason_codes, integrity_classification, integrity_risk,
    integrity_details, trophy_readiness, trophy_reason_codes,
    evidence_input, lineage, snapshot_checksum, operation_id
  ) values (
    target_season_id, resolved_province_code, target_player_profile_id, target_snapshot_revision,
    selected_season.formula_key, selected_season.formula_version, selected_season.formula_checksum,
    evidence_revision, rating_input_key, latest_rating_snapshot_id, rating_overall, rating_reliability,
    target_graph_batch_id, quality_contribution, competition_contribution, opposition_contribution,
    raw_score, visible_score, weighted_challenges, valid_challenges, logical_opponents,
    competitive_confidence, network_diversity, eligibility_state,
    reason_codes, safe_reason_codes, risk_classification, risk,
    jsonb_build_object('signals', risk_signals, 'lowConfidenceRatio', low_confidence_ratio),
    trophy_readiness, trophy_reason_codes,
    jsonb_build_object('records', evidence, 'strategy', 'exclusion_and_hold', 'window', 'recent_30'),
    jsonb_build_object(
      'scoreReachedAt', score_reached_at,
      'scoreWindowLogicalOpponents', score_window_opponents,
      'technicalOpponents', technical_opponents,
      'ratingProfileVersion', selected_profile.profile_version,
      'ratingRecalculatedAt', selected_profile.rating_recalculated_at,
      'formulaConfigurationChecksum', selected_formula.configuration_checksum
    ),
    repeat('0', 64), target_operation_id
  )
  returning id into saved_snapshot_id;

  return saved_snapshot_id;
end;
$$;

revoke all on function private.pachanga_calculate_season_score_v1(uuid, uuid, uuid, bigint, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_ranking_candidate_snapshot_checksum_v1(
  target_snapshot_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_ranking_json_checksum_v1(jsonb_build_object(
    'seasonId', snapshots.season_id,
    'provinceCode', snapshots.province_code,
    'playerProfileId', snapshots.player_profile_id,
    'formulaKey', snapshots.formula_key,
    'formulaVersion', snapshots.formula_version,
    'formulaChecksum', snapshots.formula_checksum,
    'evidenceRevision', snapshots.evidence_revision,
    'ratingInputKey', snapshots.rating_input_key,
    'ratingOverall', snapshots.rating_overall,
    'ratingReliability', snapshots.rating_reliability,
    'components', jsonb_build_array(
      snapshots.quality_component,
      snapshots.competition_component,
      snapshots.opposition_component
    ),
    'rawScore', snapshots.raw_score,
    'visibleScore', snapshots.visible_score,
    'weightedChallenges', snapshots.weighted_challenges,
    'validChallenges', snapshots.valid_challenges,
    'logicalOpponents', snapshots.logical_opponents,
    'matchCompetitiveConfidence', snapshots.match_competitive_confidence,
    'networkDiversity', snapshots.network_diversity,
    'eligibilityState', snapshots.eligibility_state,
    'reasonCodes', to_jsonb(snapshots.reason_codes),
    'safeReasonCodes', to_jsonb(snapshots.safe_reason_codes),
    'integrityClassification', snapshots.integrity_classification,
    'integrityRisk', snapshots.integrity_risk,
    'integrityDetails', snapshots.integrity_details,
    'trophyReadiness', snapshots.trophy_readiness,
    'trophyReasonCodes', to_jsonb(snapshots.trophy_reason_codes),
    'evidenceInput', snapshots.evidence_input,
    'lineage', snapshots.lineage
  ))
  from private.pachanga_season_score_snapshots snapshots
  where snapshots.id = target_snapshot_id;
$$;

revoke all on function private.pachanga_ranking_candidate_snapshot_checksum_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_ranking_stable_uuid_v1(source text)
returns uuid
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select (
    substr(md5(source), 1, 8) || '-' ||
    substr(md5(source), 9, 4) || '-' ||
    '4' || substr(md5(source), 14, 3) || '-' ||
    '8' || substr(md5(source), 18, 3) || '-' ||
    substr(md5(source), 21, 12)
  )::uuid;
$$;

revoke all on function private.pachanga_ranking_stable_uuid_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_finalize_ranking_candidate_v1(target_rebuild_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  checksum_value text;
  row_count integer;
begin
  if target_rebuild_id is null then raise exception 'rebuildId required'; end if;

  update private.pachanga_ranking_candidates candidates
  set candidate_rank = null
  where candidates.rebuild_id = target_rebuild_id;

  with ordered as materialized (
    select candidates.rebuild_id,
      candidates.player_profile_id,
      row_number() over (
        partition by candidates.province_code
        order by snapshots.raw_score desc,
          snapshots.match_competitive_confidence desc,
          snapshots.logical_opponents desc,
          snapshots.rating_reliability desc,
          snapshots.valid_challenges desc,
          (snapshots.lineage ->> 'scoreReachedAt')::timestamptz asc,
          candidates.player_profile_id asc
      )::integer as ranking_position
    from private.pachanga_ranking_candidates candidates
    join private.pachanga_season_score_snapshots snapshots on snapshots.id = candidates.snapshot_id
    where candidates.rebuild_id = target_rebuild_id
      and snapshots.eligibility_state = 'eligible'
      and candidates.province_code <> '00'
  )
  update private.pachanga_ranking_candidates candidates
  set candidate_rank = ordered.ranking_position
  from ordered
  where candidates.rebuild_id = ordered.rebuild_id
    and candidates.player_profile_id = ordered.player_profile_id;

  select private.pachanga_ranking_json_checksum_v1(coalesce(jsonb_agg(
    jsonb_build_object(
      'provinceCode', candidates.province_code,
      'playerProfileId', candidates.player_profile_id,
      'candidateChecksum', candidates.candidate_checksum,
      'candidateRank', candidates.candidate_rank,
      'eligibilityState', snapshots.eligibility_state
    ) order by candidates.province_code,
      candidates.candidate_rank nulls last,
      candidates.player_profile_id
  ), '[]'::jsonb)), count(*)::integer
  into checksum_value, row_count
  from private.pachanga_ranking_candidates candidates
  join private.pachanga_season_score_snapshots snapshots on snapshots.id = candidates.snapshot_id
  where candidates.rebuild_id = target_rebuild_id;

  update private.pachanga_ranking_rebuilds rebuilds
  set state = 'candidate_ready',
      candidate_checksum = checksum_value,
      candidate_count = row_count,
      completed_at = clock_timestamp()
  where rebuilds.id = target_rebuild_id
    and rebuilds.state = 'building';
  if not found then raise exception 'Ranking rebuild is not building'; end if;
  return checksum_value;
end;
$$;

revoke all on function private.pachanga_finalize_ranking_candidate_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_build_season_ranking_candidate_v1(
  target_season_id uuid,
  expected_season_revision bigint,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_season private.pachanga_ranking_seasons%rowtype;
  selected_profile_id uuid;
  saved_snapshot_id uuid;
  saved_rebuild_id uuid := gen_random_uuid();
  graph_batch_id uuid := gen_random_uuid();
  next_rebuild_revision bigint;
  replay private.pachanga_ranking_operation_receipts%rowtype;
  response jsonb;
begin
  if target_season_id is null or expected_season_revision is null
    or target_operation_id is null or char_length(trim(coalesce(target_reason, ''))) < 3 then
    raise exception 'seasonId, expectedRevision, operationId and reason required';
  end if;
  perform private.pachanga_lock_ranking_operation_v1(target_operation_id);
  perform pg_advisory_xact_lock(hashtextextended('ranking-season:' || target_season_id::text, 0));

  select * into replay
  from private.pachanga_ranking_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if found then
    if replay.action <> 'ranking.rebuild_candidate' or replay.target_id <> target_season_id::text then
      raise exception 'operationId already belongs to a different ranking action';
    end if;
    return (replay.response ->> 'rebuildId')::uuid;
  end if;

  select * into selected_season
  from private.pachanga_ranking_seasons seasons
  where seasons.id = target_season_id
  for update;
  if not found then raise exception 'Ranking season not found'; end if;
  if selected_season.revision <> expected_season_revision then
    raise exception 'Ranking season revision mismatch' using errcode = '40001';
  end if;
  if selected_season.status not in ('open', 'frozen', 'closed') then
    raise exception 'Ranking season cannot be rebuilt in its current state';
  end if;

  next_rebuild_revision := selected_season.ranking_revision + 1;
  insert into private.pachanga_ranking_rebuilds(
    id, season_id, rebuild_revision, expected_season_revision, graph_batch_id,
    reason, operation_id, actor_user_id
  ) values (
    saved_rebuild_id, target_season_id, next_rebuild_revision, expected_season_revision,
    graph_batch_id, trim(target_reason), target_operation_id, target_actor_user_id
  );

  perform private.pachanga_rebuild_season_team_graph_v1(
    target_season_id, next_rebuild_revision, graph_batch_id
  );

  for selected_profile_id in
    select distinct participants.player_profile_id
    from public.pachanga_external_matches matches
    join public.pachanga_external_match_participants participants
      on participants.external_match_id = matches.id
     and participants.result_version = matches.official_version
    where matches.scheduled_at >= selected_season.starts_at
      and matches.scheduled_at < selected_season.ends_at
      and matches.state in ('confirmed', 'auto_confirmed')
      and participants.player_profile_id is not null
    order by participants.player_profile_id
  loop
    begin
      saved_snapshot_id := private.pachanga_calculate_season_score_v1(
        target_season_id,
        selected_profile_id,
        graph_batch_id,
        next_rebuild_revision,
        private.pachanga_ranking_stable_uuid_v1(
          target_operation_id::text || ':' || selected_profile_id::text
        )
      );
      insert into private.pachanga_ranking_candidates(
        rebuild_id, season_id, province_code, player_profile_id, snapshot_id,
        tie_break, candidate_checksum
      )
      select saved_rebuild_id,
        target_season_id,
        snapshots.province_code,
        selected_profile_id,
        snapshots.id,
        jsonb_build_object(
          'rawScore', snapshots.raw_score,
          'competitiveConfidence', snapshots.match_competitive_confidence,
          'logicalOpponents', snapshots.logical_opponents,
          'ratingReliability', snapshots.rating_reliability,
          'validChallenges', snapshots.valid_challenges,
          'scoreReachedAt', snapshots.lineage ->> 'scoreReachedAt',
          'stableId', selected_profile_id
        ),
        private.pachanga_ranking_candidate_snapshot_checksum_v1(snapshots.id)
      from private.pachanga_season_score_snapshots snapshots
      where snapshots.id = saved_snapshot_id;
    exception when others then
      if sqlerrm = 'Canonical Rating V2 input unavailable' then
        continue;
      end if;
      raise;
    end;
  end loop;

  perform private.pachanga_finalize_ranking_candidate_v1(saved_rebuild_id);
  update private.pachanga_ranking_seasons seasons
  set ranking_revision = next_rebuild_revision,
      last_refresh_at = clock_timestamp(),
      last_error_code = null,
      updated_at = clock_timestamp()
  where seasons.id = target_season_id;

  response := jsonb_build_object(
    'rebuildId', saved_rebuild_id,
    'seasonId', target_season_id,
    'rankingRevision', next_rebuild_revision,
    'candidateChecksum', (
      select candidate_checksum from private.pachanga_ranking_rebuilds where id = saved_rebuild_id
    )
  );
  insert into private.pachanga_ranking_operation_receipts(
    operation_id, action, target_type, target_id, actor_user_id,
    expected_revision, result_revision, response
  ) values (
    target_operation_id, 'ranking.rebuild_candidate', 'ranking_season', target_season_id::text,
    target_actor_user_id, expected_season_revision, next_rebuild_revision, response
  );
  insert into private.pachanga_ranking_events(
    operation_id, event_type, season_id, payload
  ) values (
    target_operation_id, 'ranking_candidate_built', target_season_id, response
  );
  return saved_rebuild_id;
exception when others then
  update private.pachanga_ranking_rebuilds rebuilds
  set state = 'failed',
      error_code = sqlstate,
      error_detail = left(sqlerrm, 500),
      completed_at = clock_timestamp()
  where rebuilds.id = saved_rebuild_id;
  update private.pachanga_ranking_seasons seasons
  set last_error_code = sqlstate, updated_at = clock_timestamp()
  where seasons.id = target_season_id;
  raise;
end;
$$;

revoke all on function private.pachanga_build_season_ranking_candidate_v1(uuid, bigint, uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_build_player_ranking_candidate_v1(
  target_season_id uuid,
  target_player_profile_id uuid,
  expected_season_revision bigint,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_season private.pachanga_ranking_seasons%rowtype;
  baseline_rebuild private.pachanga_ranking_rebuilds%rowtype;
  saved_rebuild_id uuid := gen_random_uuid();
  saved_snapshot_id uuid;
  next_rebuild_revision bigint;
  replay private.pachanga_ranking_operation_receipts%rowtype;
  response jsonb;
begin
  if target_season_id is null or target_player_profile_id is null
    or expected_season_revision is null or target_operation_id is null
    or char_length(trim(coalesce(target_reason, ''))) < 3 then
    raise exception 'Season, player, expectedRevision, operationId and reason required';
  end if;
  perform private.pachanga_lock_ranking_operation_v1(target_operation_id);
  perform pg_advisory_xact_lock(hashtextextended('ranking-season:' || target_season_id::text, 0));

  select * into replay
  from private.pachanga_ranking_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if found then
    if replay.action <> 'ranking.refresh_player' or replay.target_id <> target_player_profile_id::text then
      raise exception 'operationId already belongs to a different ranking action';
    end if;
    return (replay.response ->> 'rebuildId')::uuid;
  end if;

  select * into selected_season
  from private.pachanga_ranking_seasons seasons
  where seasons.id = target_season_id
  for update;
  if not found then raise exception 'Ranking season not found'; end if;
  if selected_season.revision <> expected_season_revision then
    raise exception 'Ranking season revision mismatch' using errcode = '40001';
  end if;
  if selected_season.status not in ('open', 'frozen') then
    raise exception 'Ranking season does not accept incremental refresh';
  end if;

  select * into baseline_rebuild
  from private.pachanga_ranking_rebuilds rebuilds
  where rebuilds.season_id = target_season_id
    and rebuilds.state in ('candidate_ready', 'published')
  order by rebuilds.rebuild_revision desc, rebuilds.server_sequence desc, rebuilds.id desc
  limit 1;
  if not found then raise exception 'Full ranking rebuild required before incremental refresh'; end if;

  next_rebuild_revision := selected_season.ranking_revision + 1;
  insert into private.pachanga_ranking_rebuilds(
    id, season_id, rebuild_revision, expected_season_revision, graph_batch_id,
    reason, operation_id, actor_user_id
  ) values (
    saved_rebuild_id, target_season_id, next_rebuild_revision, expected_season_revision,
    baseline_rebuild.graph_batch_id, trim(target_reason), target_operation_id, target_actor_user_id
  );

  insert into private.pachanga_ranking_candidates(
    rebuild_id, season_id, province_code, player_profile_id, snapshot_id,
    candidate_rank, tie_break, candidate_checksum
  )
  select saved_rebuild_id,
    candidates.season_id,
    candidates.province_code,
    candidates.player_profile_id,
    candidates.snapshot_id,
    null,
    candidates.tie_break,
    candidates.candidate_checksum
  from private.pachanga_ranking_candidates candidates
  where candidates.rebuild_id = baseline_rebuild.id
    and candidates.player_profile_id <> target_player_profile_id;

  saved_snapshot_id := private.pachanga_calculate_season_score_v1(
    target_season_id,
    target_player_profile_id,
    baseline_rebuild.graph_batch_id,
    next_rebuild_revision,
    private.pachanga_ranking_stable_uuid_v1(
      target_operation_id::text || ':' || target_player_profile_id::text
    )
  );
  insert into private.pachanga_ranking_candidates(
    rebuild_id, season_id, province_code, player_profile_id, snapshot_id,
    tie_break, candidate_checksum
  )
  select saved_rebuild_id,
    target_season_id,
    snapshots.province_code,
    target_player_profile_id,
    snapshots.id,
    jsonb_build_object(
      'rawScore', snapshots.raw_score,
      'competitiveConfidence', snapshots.match_competitive_confidence,
      'logicalOpponents', snapshots.logical_opponents,
      'ratingReliability', snapshots.rating_reliability,
      'validChallenges', snapshots.valid_challenges,
      'scoreReachedAt', snapshots.lineage ->> 'scoreReachedAt',
      'stableId', target_player_profile_id
    ),
    private.pachanga_ranking_candidate_snapshot_checksum_v1(snapshots.id)
  from private.pachanga_season_score_snapshots snapshots
  where snapshots.id = saved_snapshot_id;

  perform private.pachanga_finalize_ranking_candidate_v1(saved_rebuild_id);
  update private.pachanga_ranking_seasons seasons
  set ranking_revision = next_rebuild_revision,
      last_refresh_at = clock_timestamp(),
      last_error_code = null,
      updated_at = clock_timestamp()
  where seasons.id = target_season_id;

  response := jsonb_build_object(
    'rebuildId', saved_rebuild_id,
    'seasonId', target_season_id,
    'playerProfileId', target_player_profile_id,
    'rankingRevision', next_rebuild_revision,
    'candidateChecksum', (
      select candidate_checksum from private.pachanga_ranking_rebuilds where id = saved_rebuild_id
    )
  );
  insert into private.pachanga_ranking_operation_receipts(
    operation_id, action, target_type, target_id, actor_user_id,
    expected_revision, result_revision, response
  ) values (
    target_operation_id, 'ranking.refresh_player', 'player_profile', target_player_profile_id::text,
    target_actor_user_id, expected_season_revision, next_rebuild_revision, response
  );
  insert into private.pachanga_ranking_events(
    operation_id, event_type, season_id, player_profile_id, payload
  ) values (
    target_operation_id, 'ranking_player_candidate_built', target_season_id,
    target_player_profile_id, response
  );
  return saved_rebuild_id;
end;
$$;

revoke all on function private.pachanga_build_player_ranking_candidate_v1(uuid, uuid, bigint, uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_enqueue_ranking_refresh_v1(
  target_season_id uuid,
  target_player_profile_id uuid,
  target_refresh_scope text,
  target_reason text,
  target_source_type text,
  target_source_id text,
  target_source_sequence bigint,
  target_operation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  season_revision bigint;
  saved_id uuid;
begin
  if target_season_id is null or target_refresh_scope not in ('player', 'season')
    or target_operation_id is null then raise exception 'Invalid ranking refresh intent'; end if;
  if (target_refresh_scope = 'player') <> (target_player_profile_id is not null) then
    raise exception 'Ranking refresh scope and player do not match';
  end if;
  select seasons.revision into season_revision
  from private.pachanga_ranking_seasons seasons
  where seasons.id = target_season_id
    and seasons.status in ('open', 'frozen');
  if season_revision is null then return null; end if;

  begin
    insert into private.pachanga_ranking_refresh_queue(
      season_id, player_profile_id, refresh_scope, reason, source_type, source_id,
      source_sequence, expected_season_revision, operation_id
    ) values (
      target_season_id, target_player_profile_id, target_refresh_scope,
      left(trim(target_reason), 240), left(target_source_type, 80), left(target_source_id, 240),
      target_source_sequence, season_revision, target_operation_id
    ) returning id into saved_id;
  exception when unique_violation then
    select queue.id into saved_id
    from private.pachanga_ranking_refresh_queue queue
    where queue.season_id = target_season_id
      and queue.refresh_scope = target_refresh_scope
      and queue.player_profile_id is not distinct from target_player_profile_id
      and queue.state in ('queued', 'processing', 'failed')
    order by queue.server_sequence desc, queue.id desc
    limit 1;
  end;
  return saved_id;
end;
$$;

revoke all on function private.pachanga_enqueue_ranking_refresh_v1(uuid, uuid, text, text, text, text, bigint, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_enqueue_ranking_from_external_event_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_match public.pachanga_external_matches%rowtype;
  selected_season record;
begin
  if new.event_type not in (
    'match_result_confirmed', 'match_result_auto_confirmed', 'match_scorers_completed',
    'match_result_disputed', 'match_result_cancelled', 'match_result_annulled'
  ) then return new; end if;
  select * into selected_match
  from public.pachanga_external_matches matches
  where matches.id = new.external_match_id;
  if not found then return new; end if;

  for selected_season in
    select seasons.id, seasons.revision
    from private.pachanga_ranking_seasons seasons
    where seasons.status in ('open', 'frozen')
      and selected_match.scheduled_at >= seasons.starts_at
      and selected_match.scheduled_at < seasons.ends_at
  loop
    perform private.pachanga_enqueue_ranking_refresh_v1(
      selected_season.id,
      null,
      'season',
      'Canonical external match event changed ranking evidence',
      'external_result_event',
      new.id::text,
      new.server_sequence,
      private.pachanga_ranking_stable_uuid_v1(
        'external-result-event:' || new.id::text || ':' || selected_season.id::text
      )
    );
  end loop;
  return new;
end;
$$;

revoke all on function private.pachanga_enqueue_ranking_from_external_event_v1()
  from public, anon, authenticated;
drop trigger if exists enqueue_ranking_from_external_event_v1
  on public.pachanga_external_result_events;
create trigger enqueue_ranking_from_external_event_v1
after insert on public.pachanga_external_result_events
for each row execute function private.pachanga_enqueue_ranking_from_external_event_v1();

create or replace function private.pachanga_enqueue_ranking_from_rating_v2_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_season record;
begin
  if new.current_overall is not distinct from old.current_overall
    and new.rating_reliability is not distinct from old.rating_reliability
    and new.rating_recalculated_at is not distinct from old.rating_recalculated_at then
    return new;
  end if;
  for selected_season in
    select distinct seasons.id, seasons.revision
    from private.pachanga_ranking_seasons seasons
    join public.pachanga_external_matches matches
      on matches.scheduled_at >= seasons.starts_at
     and matches.scheduled_at < seasons.ends_at
     and matches.state in ('confirmed', 'auto_confirmed')
    join public.pachanga_external_match_participants participants
      on participants.external_match_id = matches.id
     and participants.result_version = matches.official_version
     and participants.player_profile_id = new.id
    where seasons.status in ('open', 'frozen')
  loop
    perform private.pachanga_enqueue_ranking_refresh_v1(
      selected_season.id,
      new.id,
      'player',
      'Canonical Rating V2 input changed',
      'player_profile',
      new.id::text,
      new.profile_version,
      private.pachanga_ranking_stable_uuid_v1(
        'rating-v2:' || new.id::text || ':' || new.profile_version::text || ':' || selected_season.id::text
      )
    );
  end loop;
  return new;
end;
$$;

revoke all on function private.pachanga_enqueue_ranking_from_rating_v2_v1()
  from public, anon, authenticated;
drop trigger if exists enqueue_ranking_from_rating_v2_v1
  on public.pachanga_player_profiles;
create trigger enqueue_ranking_from_rating_v2_v1
after update of current_overall, rating_reliability, rating_recalculated_at
on public.pachanga_player_profiles
for each row execute function private.pachanga_enqueue_ranking_from_rating_v2_v1();

create or replace function public.process_pachanga_ranking_refresh_queue_v1(
  maximum_operations integer default 10
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued private.pachanga_ranking_refresh_queue%rowtype;
  processed integer := 0;
  completed integer := 0;
  failed integer := 0;
  has_baseline boolean;
begin
  if current_user not in ('service_role', 'postgres', 'supabase_admin') then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  maximum_operations := greatest(1, least(coalesce(maximum_operations, 10), 50));

  for queued in
    select queue.*
    from private.pachanga_ranking_refresh_queue queue
    where queue.state in ('queued', 'failed')
      and queue.available_at <= clock_timestamp()
      and queue.attempts < 5
    order by queue.available_at, queue.server_sequence, queue.id
    for update skip locked
    limit maximum_operations
  loop
    processed := processed + 1;
    update private.pachanga_ranking_refresh_queue queue
    set state = 'processing',
        attempts = queue.attempts + 1,
        claimed_at = clock_timestamp(),
        error_code = null,
        error_detail = null,
        updated_at = clock_timestamp()
    where queue.id = queued.id;

    begin
      if queued.refresh_scope = 'season' then
        perform private.pachanga_build_season_ranking_candidate_v1(
          queued.season_id,
          queued.expected_season_revision,
          queued.operation_id,
          null,
          queued.reason
        );
      else
        select exists (
          select 1
          from private.pachanga_ranking_rebuilds rebuilds
          where rebuilds.season_id = queued.season_id
            and rebuilds.state in ('candidate_ready', 'published')
        ) into has_baseline;
        if has_baseline then
          perform private.pachanga_build_player_ranking_candidate_v1(
            queued.season_id,
            queued.player_profile_id,
            queued.expected_season_revision,
            queued.operation_id,
            null,
            queued.reason
          );
        else
          perform private.pachanga_build_season_ranking_candidate_v1(
            queued.season_id,
            queued.expected_season_revision,
            queued.operation_id,
            null,
            'Initial full rebuild required by player refresh'
          );
        end if;
      end if;

      update private.pachanga_ranking_refresh_queue queue
      set state = 'completed',
          completed_at = clock_timestamp(),
          updated_at = clock_timestamp()
      where queue.id = queued.id;
      completed := completed + 1;
    exception when others then
      update private.pachanga_ranking_refresh_queue queue
      set state = case when queue.attempts >= 5 then 'dead_letter' else 'failed' end,
          available_at = clock_timestamp() + make_interval(mins => least(60, power(2, queue.attempts)::integer)),
          error_code = sqlstate,
          error_detail = left(sqlerrm, 500),
          updated_at = clock_timestamp()
      where queue.id = queued.id;
      failed := failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'processed', processed,
    'completed', completed,
    'failed', failed,
    'serverTime', clock_timestamp()
  );
end;
$$;

revoke all on function public.process_pachanga_ranking_refresh_queue_v1(integer)
  from public, anon, authenticated;
grant execute on function public.process_pachanga_ranking_refresh_queue_v1(integer)
  to service_role;

reset lock_timeout;
reset statement_timeout;
