-- Pachangas IQ R4C: canonical reads, platform flags and Realtime access.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_competition_invalidations
  drop constraint if exists pachanga_competition_invalidations_authority_check;
alter table public.pachanga_competition_invalidations
  add constraint pachanga_competition_invalidations_authority_check check (
    (organizer_group_id is not null and organizer_club_id is null)
    or (organizer_group_id is null and organizer_club_id is not null)
    or (
      organizer_group_id is null and organizer_club_id is null
      and competition_id is null
      and entity_type in (
        'league_participation_flags', 'league_scheduling_flags',
        'league_match_operations_flags'
      )
    )
  );

create or replace function private.pachanga_league_can_read_invalidation_v1(
  organizer_group_id uuid,
  organizer_club_id uuid,
  target_competition_id uuid,
  target_group_id uuid,
  target_user_id uuid,
  target_entity_type text,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select actor_id is not null
    and actor_id = (select auth.uid())
    and (
      (
        target_entity_type in (
          'league_participation_flags', 'league_scheduling_flags',
          'league_match_operations_flags'
        )
        and target_competition_id is null
      )
      or private.pachanga_platform_role_for_user_v1(actor_id) in ('platform_owner', 'platform_admin')
      or target_user_id = actor_id
      or exists (
        select 1 from public.pachanga_groups groups
        where groups.id in (organizer_group_id, target_group_id)
          and groups.owner_id = actor_id
      )
      or exists (
        select 1 from public.pachanga_group_members members
        where members.group_id = target_group_id and members.user_id = actor_id
      )
      or private.pachanga_club_can_v1(organizer_club_id, actor_id, 'read')
      or (
        target_competition_id is not null
        and private.pachanga_competition_can_v1(target_competition_id, actor_id, 'read')
      )
      or (
        target_competition_id is not null and exists (
          select 1
          from public.pachanga_competition_entries entries
          left join public.pachanga_competition_team_delegates delegates
            on delegates.entry_id = entries.id
            and delegates.user_id = actor_id
            and delegates.status = 'active'
            and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
          left join public.pachanga_competition_roster_members roster_members
            on roster_members.entry_id = entries.id
            and roster_members.eligibility_status in ('eligible', 'waived')
            and (roster_members.effective_until is null or roster_members.effective_until > clock_timestamp())
          left join public.pachanga_player_profiles profiles
            on profiles.id = roster_members.player_profile_id
            and profiles.user_id = actor_id
          where entries.competition_id = target_competition_id
            and (delegates.id is not null or profiles.id is not null)
        )
      )
    );
$$;

revoke all on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) to authenticated;

create or replace function public.get_pachanga_league_match_operations_flags_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  return private.pachanga_league_match_operations_flags_v1();
end;
$$;

revoke all on function public.get_pachanga_league_match_operations_flags_v1()
  from public, anon;
grant execute on function public.get_pachanga_league_match_operations_flags_v1()
  to authenticated, service_role;

create or replace function public.get_pachanga_league_canonical_match_v1(
  target_competition_id uuid,
  target_canonical_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare context_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select contexts.id into context_id
  from public.pachanga_competition_match_contexts contexts
  where contexts.competition_id = target_competition_id
    and contexts.canonical_match_id = target_canonical_match_id
    and contexts.source_kind = 'COMPETITION_GENERATED'
  order by contexts.server_sequence desc, contexts.id desc limit 1;
  if context_id is null then raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
  return private.pachanga_league_match_snapshot_v1(context_id, auth.uid());
end;
$$;

revoke all on function public.get_pachanga_league_canonical_match_v1(uuid, uuid)
  from public, anon;
grant execute on function public.get_pachanga_league_canonical_match_v1(uuid, uuid)
  to authenticated, service_role;

create or replace function private.pachanga_league_standings_snapshot_v1(
  target_standing_state_id uuid,
  target_public boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'kind', case when target_public then 'PublicLeagueStandings' else 'LeagueStandingsView' end,
    'standingStateId', states.id,
    'competitionId', states.competition_id,
    'editionId', states.edition_id,
    'stageId', states.stage_id,
    'divisionId', states.division_id,
    'groupId', states.competition_group_id,
    'ruleRevisionId', states.rule_revision_id,
    'health', states.health_status,
    'revision', states.revision,
    'serverSequence', states.server_sequence,
    'snapshot', case when snapshots.id is null then null else jsonb_build_object(
      'id', snapshots.id,
      'sourceRevision', snapshots.source_revision,
      'engineVersion', snapshots.engine_version,
      'rebuildKind', snapshots.rebuild_kind,
      'generatedAt', snapshots.generated_at,
      'checksum', snapshots.content_checksum,
      'criteria', snapshots.tie_break_criteria,
      'computedResults', (
        select count(*) from public.pachanga_competition_match_contexts contexts
        join public.pachanga_competition_match_sheets sheets
          on sheets.competition_match_context_id = contexts.id
        join public.pachanga_competition_official_result_decisions decisions
          on decisions.id = sheets.active_official_decision_id
        where contexts.stage_id = states.stage_id
          and contexts.division_id is not distinct from states.division_id
          and contexts.competition_group_id is not distinct from states.competition_group_id
          and decisions.server_sequence <= snapshots.source_revision
      ),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'entryId', rows.entry_id,
        'position', rows.position,
        'played', rows.played,
        'wins', rows.wins,
        'draws', rows.draws,
        'losses', rows.losses,
        'goalsFor', rows.goals_for,
        'goalsAgainst', rows.goals_against,
        'goalDifference', rows.goal_difference,
        'basePoints', rows.base_points,
        'adjustmentPoints', rows.adjustment_points,
        'effectivePoints', rows.effective_points,
        'tieBreakValues', rows.tie_break_values,
        'team', rows.team_snapshot
      ) order by rows.position, rows.entry_id)
      from public.pachanga_competition_standing_rows rows
      where rows.standing_snapshot_id = snapshots.id), '[]'::jsonb),
      'explanations', coalesce((select jsonb_agg(jsonb_build_object(
        'tieGroupKey', explanations.tie_group_key,
        'candidateEntryIds', explanations.candidate_entry_ids,
        'criterion', explanations.criterion,
        'criterionOrder', explanations.criterion_order,
        'values', explanations.values_by_entry,
        'resolved', explanations.resolved,
        'explanation', explanations.public_explanation
      ) order by explanations.criterion_order, explanations.server_sequence, explanations.id)
      from public.pachanga_competition_tie_break_explanations explanations
      where explanations.standing_snapshot_id = snapshots.id), '[]'::jsonb)
    ) end
  )
  from public.pachanga_competition_standing_states states
  left join public.pachanga_competition_standing_snapshots snapshots
    on snapshots.id = states.current_snapshot_id
  where states.id = target_standing_state_id;
$$;

revoke all on function private.pachanga_league_standings_snapshot_v1(uuid, boolean)
  from public, anon, authenticated;

create or replace function public.get_pachanga_league_standings_v1(
  target_competition_id uuid,
  target_stage_id uuid,
  target_division_id uuid default null,
  target_group_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare state_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(target_competition_id, auth.uid(), 'standings_read')
     and not exists (
       select 1 from public.pachanga_competition_stage_memberships memberships
       join public.pachanga_competition_entries entries on entries.id = memberships.entry_id
       left join public.pachanga_competition_team_delegates delegates
         on delegates.entry_id = entries.id and delegates.user_id = auth.uid()
         and delegates.status = 'active'
       left join public.pachanga_competition_roster_members roster_members
         on roster_members.entry_id = entries.id
       left join public.pachanga_player_profiles profiles
         on profiles.id = roster_members.player_profile_id and profiles.user_id = auth.uid()
       where entries.competition_id = target_competition_id
         and memberships.stage_id = target_stage_id
         and memberships.status = 'active'
         and (delegates.id is not null or profiles.id is not null or entries.team_id in (
           select groups.id from public.pachanga_groups groups where groups.owner_id = auth.uid()
         ))
     ) then raise exception 'LEAGUE_STANDINGS_ACCESS_DENIED' using errcode = '42501'; end if;
  select states.id into state_id from public.pachanga_competition_standing_states states
  where states.competition_id = target_competition_id
    and states.stage_id = target_stage_id
    and states.division_id is not distinct from target_division_id
    and states.competition_group_id is not distinct from target_group_id;
  if state_id is null then
    return jsonb_build_object(
      'kind', 'LeagueStandingsView', 'competitionId', target_competition_id,
      'stageId', target_stage_id, 'health', 'PENDING', 'revision', 0,
      'snapshot', null, 'flags', private.pachanga_league_match_operations_flags_v1()
    );
  end if;
  return private.pachanga_league_standings_snapshot_v1(state_id, false)
    || jsonb_build_object('flags', private.pachanga_league_match_operations_flags_v1());
end;
$$;

revoke all on function public.get_pachanga_league_standings_v1(uuid, uuid, uuid, uuid)
  from public, anon;
grant execute on function public.get_pachanga_league_standings_v1(uuid, uuid, uuid, uuid)
  to authenticated, service_role;

create or replace function public.get_pachanga_public_league_standings_v1(
  target_competition_id uuid,
  target_stage_id uuid,
  target_division_id uuid default null,
  target_group_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_competition_standing_states%rowtype;
declare policy jsonb;
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  if not settings.league_standings_enabled or not settings.league_public_standings_enabled then
    raise exception 'LEAGUE_PUBLIC_STANDINGS_DISABLED' using errcode = '42501';
  end if;
  if not exists (select 1 from public.pachanga_competitions competitions
    where competitions.id = target_competition_id and competitions.visibility = 'public') then
    raise exception 'PUBLIC_COMPETITION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into state_row from public.pachanga_competition_standing_states states
  where states.competition_id = target_competition_id
    and states.stage_id = target_stage_id
    and states.division_id is not distinct from target_division_id
    and states.competition_group_id is not distinct from target_group_id;
  if not found or state_row.current_snapshot_id is null then
    raise exception 'PUBLIC_STANDINGS_NOT_AVAILABLE' using errcode = 'P0002';
  end if;
  policy := private.pachanga_league_match_policy_v1(state_row.rule_revision_id);
  if not coalesce((policy ->> 'publicStandings')::boolean, false) then
    raise exception 'PUBLIC_STANDINGS_NOT_AVAILABLE' using errcode = 'P0002';
  end if;
  return private.pachanga_league_standings_snapshot_v1(state_row.id, true);
end;
$$;

revoke all on function public.get_pachanga_public_league_standings_v1(uuid, uuid, uuid, uuid)
  from public;
grant execute on function public.get_pachanga_public_league_standings_v1(uuid, uuid, uuid, uuid)
  to anon, authenticated, service_role;

create or replace function public.get_pachanga_league_result_desk_v1(
  target_competition_id uuid,
  target_state text default null,
  page_size integer default 50,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized_state text := nullif(lower(trim(coalesce(target_state, ''))), '');
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(target_competition_id, auth.uid(), 'results_read') then
    raise exception 'COMPETITION_RESULT_READER_REQUIRED' using errcode = '42501';
  end if;
  if page_size < 1 or page_size > 200 or page_offset < 0 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'kind', 'LeagueResultDesk',
    'competitionId', target_competition_id,
    'filter', normalized_state,
    'matches', coalesce((select jsonb_agg(jsonb_build_object(
      'contextId', source.context_id,
      'canonicalMatchId', source.canonical_match_id,
      'roundId', source.round_id,
      'roundName', source.round_name,
      'scheduledStart', source.scheduled_start,
      'matchStatus', source.match_status,
      'homeEntry', jsonb_build_object('id', source.home_entry_id, 'name', source.home_name),
      'awayEntry', jsonb_build_object('id', source.away_entry_id, 'name', source.away_name),
      'sportingResultId', source.sporting_result_id,
      'sportingState', source.sporting_state,
      'scoreHome', source.score_home,
      'scoreAway', source.score_away,
      'scorerMismatch', source.scorer_mismatch,
      'officialDecisionId', source.official_decision_id,
      'officialOutcome', source.official_outcome,
      'nextAction', case
        when source.sporting_state = 'disputed' then 'official_result.publish'
        when source.sporting_state = 'confirmed' and source.official_decision_id is null then 'official_result.publish'
        when source.official_decision_id is not null then 'official_result.supersede'
        else 'wait_for_teams'
      end,
      'revision', source.revision,
      'serverSequence', source.server_sequence
    ) order by source.scheduled_start nulls last, source.server_sequence, source.context_id)
    from (
      select contexts.id as context_id, contexts.canonical_match_id, contexts.round_id,
        rounds.display_name as round_name, contexts.scheduled_start,
        contexts.status as match_status, contexts.home_entry_id, contexts.away_entry_id,
        home_groups.name as home_name, away_groups.name as away_name,
        results.id as sporting_result_id, results.state as sporting_state,
        revisions.score_home, revisions.score_away,
        revisions.home_scorer_total > revisions.score_home
          or revisions.away_scorer_total > revisions.score_away as scorer_mismatch,
        decisions.id as official_decision_id, decisions.outcome as official_outcome,
        contexts.revision, contexts.server_sequence
      from public.pachanga_competition_match_contexts contexts
      join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
      join public.pachanga_competition_entries home_entries on home_entries.id = contexts.home_entry_id
      join public.pachanga_groups home_groups on home_groups.id = home_entries.team_id
      join public.pachanga_competition_entries away_entries on away_entries.id = contexts.away_entry_id
      join public.pachanga_groups away_groups on away_groups.id = away_entries.team_id
      left join public.pachanga_competition_match_sheets sheets
        on sheets.competition_match_context_id = contexts.id
      left join public.pachanga_competition_sporting_results results
        on results.id = sheets.current_sporting_result_id
      left join public.pachanga_competition_sporting_result_revisions revisions
        on revisions.id = results.current_revision_id
      left join public.pachanga_competition_official_result_decisions decisions
        on decisions.id = sheets.active_official_decision_id
      where contexts.competition_id = target_competition_id
        and contexts.source_kind = 'COMPETITION_GENERATED'
        and (normalized_state is null
          or lower(coalesce(results.state, contexts.status)) = normalized_state)
      order by contexts.scheduled_start nulls last, contexts.server_sequence, contexts.id
      limit page_size offset page_offset
    ) source), '[]'::jsonb),
    'flags', private.pachanga_league_match_operations_flags_v1()
  );
end;
$$;

revoke all on function public.get_pachanga_league_result_desk_v1(uuid, text, integer, integer)
  from public, anon;
grant execute on function public.get_pachanga_league_result_desk_v1(uuid, text, integer, integer)
  to authenticated, service_role;

create or replace function public.get_pachanga_my_league_match_operations_v1(
  page_size integer default 30,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if page_size < 1 or page_size > 100 or page_offset < 0 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'kind', 'MyLeagueMatchOperations',
    'matches', coalesce((select jsonb_agg(
      private.pachanga_league_match_snapshot_v1(source.id, actor_id)
      order by source.scheduled_start nulls last, source.server_sequence, source.id
    ) from (
      select distinct contexts.id, contexts.scheduled_start, contexts.server_sequence
      from public.pachanga_competition_match_contexts contexts
      where contexts.source_kind = 'COMPETITION_GENERATED'
        and private.pachanga_league_match_can_read_v1(contexts.id, actor_id)
      order by contexts.scheduled_start nulls last, contexts.server_sequence, contexts.id
      limit page_size offset page_offset
    ) source), '[]'::jsonb),
    'standings', coalesce((select jsonb_agg(
      private.pachanga_league_standings_snapshot_v1(states.id, false)
      order by states.server_sequence desc, states.id
    )
    from public.pachanga_competition_standing_states states
    where exists (
      select 1 from public.pachanga_competition_match_contexts contexts
      where contexts.stage_id = states.stage_id
        and contexts.division_id is not distinct from states.division_id
        and contexts.competition_group_id is not distinct from states.competition_group_id
        and private.pachanga_league_match_can_read_v1(contexts.id, actor_id)
    )), '[]'::jsonb),
    'flags', private.pachanga_league_match_operations_flags_v1()
  );
end;
$$;

revoke all on function public.get_pachanga_my_league_match_operations_v1(integer, integer)
  from public, anon;
grant execute on function public.get_pachanga_my_league_match_operations_v1(integer, integer)
  to authenticated, service_role;

create or replace function public.get_pachanga_platform_league_match_operations_v1(
  page_size integer default 100,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_platform_require_v1('competitions.manage');
  if page_size < 1 or page_size > 500 or page_offset < 0 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'kind', 'PlatformLeagueMatchOperations',
    'flags', private.pachanga_league_match_operations_flags_v1(),
    'counts', jsonb_build_object(
      'scheduled', (select count(*) from public.pachanga_competition_match_contexts where status = 'scheduled'),
      'ready', (select count(*) from public.pachanga_competition_match_contexts where status = 'ready'),
      'played', (select count(*) from public.pachanga_competition_match_contexts where status in ('played', 'result_pending')),
      'official', (select count(*) from public.pachanga_competition_match_contexts where status = 'official'),
      'pendingResults', (select count(*) from public.pachanga_competition_sporting_results where state in ('submitted', 'change_proposed')),
      'disputes', (select count(*) from public.pachanga_competition_sporting_results where state = 'disputed'),
      'standingsCurrent', (select count(*) from public.pachanga_competition_standing_states where health_status = 'CURRENT'),
      'standingsErrors', (select count(*) from public.pachanga_competition_standing_states where health_status in ('STALE', 'ERROR')),
      'generatedCanonicalMatches', (select count(*) from public.pachanga_canonical_match_bindings where source_kind = 'competition_generated' and binding_status = 'active'),
      'legacyBackfill', 0
    ),
    'matches', coalesce((select jsonb_agg(jsonb_build_object(
      'contextId', contexts.id, 'competitionId', contexts.competition_id,
      'canonicalMatchId', contexts.canonical_match_id, 'status', contexts.status,
      'roundId', contexts.round_id, 'revision', contexts.revision,
      'serverSequence', contexts.server_sequence
    ) order by contexts.server_sequence desc, contexts.id desc)
    from (select * from public.pachanga_competition_match_contexts
      where source_kind = 'COMPETITION_GENERATED'
      order by server_sequence desc, id desc limit page_size offset page_offset) contexts), '[]'::jsonb),
    'standingsHealth', coalesce((select jsonb_agg(jsonb_build_object(
      'id', states.id, 'competitionId', states.competition_id,
      'stageId', states.stage_id, 'health', states.health_status,
      'revision', states.revision, 'currentSnapshotId', states.current_snapshot_id,
      'serverSequence', states.server_sequence
    ) order by states.server_sequence desc, states.id desc)
    from public.pachanga_competition_standing_states states), '[]'::jsonb),
    'recentRebuilds', coalesce((select jsonb_agg(jsonb_build_object(
      'snapshotId', receipts.standing_snapshot_id,
      'kind', receipts.rebuild_kind,
      'sourceRevision', receipts.source_revision,
      'checksum', receipts.confirmed_checksum,
      'durationMs', receipts.duration_ms,
      'serverSequence', receipts.server_sequence
    ) order by receipts.server_sequence desc, receipts.id desc)
    from (select * from public.pachanga_competition_standing_rebuild_receipts
      order by server_sequence desc, id desc limit 50) receipts), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_league_match_operations_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_league_match_operations_v1(integer, integer)
  to authenticated;

create or replace function public.command_pachanga_league_match_operations_platform_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c4c1'::uuid;
declare actor_id uuid := auth.uid();
declare action_name constant text := 'league_match_operations_flags.set';
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare request_hash text;
declare replay jsonb;
declare metadata jsonb;
declare sequence_value bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare snapshot jsonb;
declare response jsonb;
declare next_foundation boolean;
declare next_squads boolean;
declare next_attendance boolean;
declare next_sporting boolean;
declare next_confirmation boolean;
declare next_official boolean;
declare next_standings boolean;
declare next_public_standings boolean;
begin
  if operation_id is null or aggregate_id <> flags_aggregate_id
     or expected_revision is null or expected_revision < 0 then
    raise exception 'INVALID_LEAGUE_MATCH_OPERATIONS_FLAGS_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(command_payload) > 32768 then
    raise exception 'INVALID_LEAGUE_MATCH_OPERATIONS_FLAGS_PAYLOAD' using errcode = '22023';
  end if;
  perform private.pachanga_platform_require_v1('competitions.manage');
  perform private.pachanga_platform_require_v1('flags.write');
  if exists (
    select 1 from jsonb_each(command_payload) pair
    where pair.key <> 'reason'
      and (
        pair.key not in (
          'foundationEnabled', 'squadsEnabled', 'attendanceEnabled',
          'sportingResultsEnabled', 'resultConfirmationEnabled',
          'officialResultsEnabled', 'standingsEnabled', 'publicStandingsEnabled'
        ) or jsonb_typeof(pair.value) <> 'boolean'
      )
  ) then raise exception 'INVALID_LEAGUE_MATCH_OPERATIONS_FLAG' using errcode = '22023'; end if;
  metadata := private.pachanga_league_match_sanitize_metadata_v1(client_metadata);
  request_hash := private.pachanga_league_match_request_hash_v1(
    action_name, aggregate_id, expected_revision, command_payload
  );
  perform pg_advisory_xact_lock(hashtextextended('league-match-operations-flags:' || operation_id::text, 0));
  replay := private.pachanga_league_match_operation_replay_v1(
    operation_id, actor_id, action_name, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into settings from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton for update;
  if settings.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  next_foundation := coalesce((command_payload ->> 'foundationEnabled')::boolean, settings.league_match_operations_foundation_enabled);
  next_squads := coalesce((command_payload ->> 'squadsEnabled')::boolean, settings.league_match_squads_enabled);
  next_attendance := coalesce((command_payload ->> 'attendanceEnabled')::boolean, settings.league_match_attendance_enabled);
  next_sporting := coalesce((command_payload ->> 'sportingResultsEnabled')::boolean, settings.league_sporting_results_enabled);
  next_confirmation := coalesce((command_payload ->> 'resultConfirmationEnabled')::boolean, settings.league_result_confirmation_enabled);
  next_official := coalesce((command_payload ->> 'officialResultsEnabled')::boolean, settings.league_official_results_enabled);
  next_standings := coalesce((command_payload ->> 'standingsEnabled')::boolean, settings.league_standings_enabled);
  next_public_standings := coalesce((command_payload ->> 'publicStandingsEnabled')::boolean, settings.league_public_standings_enabled);
  if not next_foundation then
    next_squads := false; next_attendance := false; next_sporting := false;
    next_confirmation := false; next_official := false;
    next_standings := false; next_public_standings := false;
  end if;
  if not next_sporting then
    next_confirmation := false; next_official := false;
    next_standings := false; next_public_standings := false;
  end if;
  if not next_confirmation then
    next_official := false; next_standings := false; next_public_standings := false;
  end if;
  if not next_official then next_standings := false; next_public_standings := false; end if;
  if not next_standings then next_public_standings := false; end if;
  if next_foundation and not (
    settings.foundation_enabled
    and settings.league_participation_foundation_enabled
    and settings.league_rosters_enabled
    and settings.league_scheduling_foundation_enabled
    and settings.league_schedule_publication_enabled
    and settings.league_canonical_fixture_creation_enabled
  ) then raise exception 'R4A_R4B_DEPENDENCY_NOT_ENABLED' using errcode = '42501'; end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings current_settings set
    league_match_operations_foundation_enabled = next_foundation,
    league_match_squads_enabled = next_squads,
    league_match_attendance_enabled = next_attendance,
    league_sporting_results_enabled = next_sporting,
    league_result_confirmation_enabled = next_confirmation,
    league_official_results_enabled = next_official,
    league_standings_enabled = next_standings,
    league_public_standings_enabled = next_public_standings,
    revision = current_settings.revision + 1,
    server_sequence = sequence_value, updated_by = actor_id,
    updated_at = confirmed_at
  where current_settings.singleton returning * into settings;
  snapshot := private.pachanga_league_match_operations_flags_v1();
  response := jsonb_build_object(
    'operationId', operation_id, 'confirmedRevision', settings.revision,
    'confirmedAt', confirmed_at, 'serverSequence', sequence_value,
    'snapshot', snapshot,
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'league_match_operations_flags',
      'entityId', flags_aggregate_id, 'revision', settings.revision,
      'serverSequence', sequence_value
    ))
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, actor_id, 'authenticated', 'league_match_operations_flags',
    flags_aggregate_id::text, null, action_name, settings.revision,
    sequence_value, left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), action_name), 120),
    snapshot - 'updatedAt', confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, null, null, null, null, null,
    'league_match_operations_flags', flags_aggregate_id::text,
    settings.revision, confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    operation_id, actor_id, 'authenticated', action_name,
    'league_match_operations', aggregate_id::text, request_hash,
    settings.revision, sequence_value, metadata, response, confirmed_at
  );
  return response;
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_match_operations_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_match_operations_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) to authenticated;
