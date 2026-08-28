-- Pachangas IQ R6C: persisted bracket read models. Sports state is projected
-- when an authoritative event occurs; clients never rebuild brackets on read.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.pachanga_tournament_knockout_read_models (
  competition_id uuid primary key references public.pachanga_competitions(id) on delete cascade,
  bracket_id uuid not null unique references public.pachanga_tournament_brackets(id) on delete cascade,
  revision bigint not null,
  server_sequence bigint not null unique,
  public_snapshot jsonb not null,
  organizer_snapshot jsonb not null,
  snapshot_checksum text not null,
  rebuilt_at timestamptz not null default clock_timestamp(),
  check (revision >= 1),
  check (jsonb_typeof(public_snapshot) = 'object'),
  check (jsonb_typeof(organizer_snapshot) = 'object'),
  check (length(snapshot_checksum) = 64)
);

alter table public.pachanga_tournament_knockout_read_models enable row level security;
revoke all on table public.pachanga_tournament_knockout_read_models
  from public, anon, authenticated;
grant all on table public.pachanga_tournament_knockout_read_models to service_role;

create or replace function private.pachanga_tournament_knockout_entry_public_v1(
  target_entry_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case when entries.id is null then null else jsonb_build_object(
    'entryId', entries.id,
    'teamId', entries.team_id,
    'name', teams.name,
    'teamCode', teams.team_code,
    'status', entries.status
  ) end
  from (select target_entry_id as id) target
  left join public.pachanga_competition_entries entries on entries.id = target.id
  left join public.pachanga_groups teams on teams.id = entries.team_id;
$$;

create or replace function private.pachanga_tournament_knockout_node_snapshot_v1(
  target_node_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare home_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare away_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare reservation_row public.pachanga_tournament_bracket_fixture_reservations%rowtype;
declare schedule_slot public.pachanga_competition_schedule_slots%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare active_decision public.pachanga_competition_official_result_decisions%rowtype;
declare resolution_row public.pachanga_tournament_knockout_result_resolutions%rowtype;
declare advance_row public.pachanga_tournament_bracket_advance_decisions%rowtype;
declare referee_value jsonb;
begin
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id;
  if not found then return null; end if;
  select * into home_slot
  from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'HOME');
  select * into away_slot
  from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'AWAY');
  select * into reservation_row
  from private.pachanga_tournament_knockout_current_reservation_v1(node_row.id);
  if reservation_row.id is not null then
    select * into schedule_slot
    from public.pachanga_competition_schedule_slots slots
    where slots.id = reservation_row.schedule_slot_id;
  end if;
  if node_row.canonical_match_id is not null then
    select * into context_row
    from public.pachanga_competition_match_contexts contexts
    where contexts.canonical_match_id = node_row.canonical_match_id
      and contexts.status <> 'retired'
    order by contexts.server_sequence desc, contexts.id desc limit 1;
    select decisions.* into active_decision
    from public.pachanga_competition_match_sheets sheets
    join public.pachanga_competition_official_result_decisions decisions
      on decisions.id = sheets.active_official_decision_id
    where sheets.competition_match_context_id = context_row.id;
    if active_decision.id is not null then
      select * into resolution_row
      from public.pachanga_tournament_knockout_result_resolutions resolutions
      where resolutions.official_result_decision_id = active_decision.id;
    end if;
    select jsonb_strip_nulls(jsonb_build_object(
      'assignmentId', assignments.id,
      'status', assignments.status,
      'role', assignments.assignment_role,
      'displayName', profiles.public_display_name_snapshot,
      'avatar', profiles.public_avatar_snapshot,
      'verificationStatus', profiles.verification_status
    )) into referee_value
    from public.pachanga_referee_assignments assignments
    join public.pachanga_referee_profiles profiles
      on profiles.id = assignments.referee_profile_id
    where assignments.canonical_match_id = node_row.canonical_match_id
      and assignments.status not in ('cancelled', 'declined', 'expired', 'replaced')
    order by assignments.revision desc, assignments.server_sequence desc,
      assignments.id desc limit 1;
  end if;
  select * into advance_row
  from public.pachanga_tournament_bracket_advance_decisions decisions
  where decisions.source_node_id = node_row.id
  order by decisions.revision desc, decisions.server_sequence desc,
    decisions.id desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    'id', node_row.id,
    'roundCode', node_row.round_code,
    'roundOrder', node_row.round_order,
    'nodeOrder', node_row.node_order,
    'nodeKind', node_row.node_kind,
    'status', node_row.status,
    'revision', node_row.revision,
    'serverSequence', node_row.server_sequence,
    'home', private.pachanga_tournament_knockout_entry_public_v1(node_row.home_entry_id),
    'away', private.pachanga_tournament_knockout_entry_public_v1(node_row.away_entry_id),
    'winner', private.pachanga_tournament_knockout_entry_public_v1(node_row.winner_entry_id),
    'loser', private.pachanga_tournament_knockout_entry_public_v1(node_row.loser_entry_id),
    'sources', jsonb_build_object(
      'home', jsonb_strip_nulls(jsonb_build_object(
        'kind', home_slot.source_kind,
        'key', home_slot.source_key,
        'sourceNodeId', home_slot.source_node_id,
        'status', home_slot.resolution_status,
        'resolvedEntryId', home_slot.resolved_entry_id,
        'revision', home_slot.slot_revision
      )),
      'away', jsonb_strip_nulls(jsonb_build_object(
        'kind', away_slot.source_kind,
        'key', away_slot.source_key,
        'sourceNodeId', away_slot.source_node_id,
        'status', away_slot.resolution_status,
        'resolvedEntryId', away_slot.resolved_entry_id,
        'revision', away_slot.slot_revision
      ))
    ),
    'reservation', case when reservation_row.id is null then null else
      jsonb_strip_nulls(jsonb_build_object(
        'id', reservation_row.id,
        'status', reservation_row.status,
        'revision', reservation_row.reservation_revision,
        'scheduleSlotId', schedule_slot.id,
        'startsAt', schedule_slot.starts_at,
        'endsAt', schedule_slot.ends_at,
        'timezone', schedule_slot.timezone,
        'venueId', schedule_slot.venue_id,
        'venueLabel', schedule_slot.venue_label
      )) end,
    'match', case when context_row.id is null then null else
      jsonb_strip_nulls(jsonb_build_object(
        'canonicalMatchId', context_row.canonical_match_id,
        'contextId', context_row.id,
        'status', context_row.status,
        'revision', context_row.revision,
        'scheduledStart', context_row.scheduled_start,
        'scheduledEnd', context_row.scheduled_end,
        'timezone', context_row.timezone,
        'venueLabel', context_row.venue_label,
        'officialDecisionId', active_decision.id,
        'outcome', active_decision.outcome,
        'scoreHome', active_decision.effective_score_home,
        'scoreAway', active_decision.effective_score_away,
        'extraTimePlayed', resolution_row.extra_time_played,
        'scoreAfterExtraTimeHome', resolution_row.score_after_extra_time_home,
        'scoreAfterExtraTimeAway', resolution_row.score_after_extra_time_away,
        'shootoutHome', resolution_row.shootout_home,
        'shootoutAway', resolution_row.shootout_away,
        'resolutionKind', resolution_row.resolution_kind
      )) end,
    'referee', referee_value,
    'advance', case when advance_row.id is null then null else
      jsonb_strip_nulls(jsonb_build_object(
        'id', advance_row.id,
        'reason', advance_row.advance_reason,
        'winnerEntryId', advance_row.winner_entry_id,
        'loserEntryId', advance_row.loser_entry_id,
        'revision', advance_row.revision,
        'serverSequence', advance_row.server_sequence,
        'decidedAt', advance_row.decided_at
      )) end
  ));
end;
$$;

create or replace function private.pachanga_tournament_knockout_rebuild_read_model_v1(
  target_bracket_id uuid,
  target_server_sequence bigint
)
returns public.pachanga_tournament_knockout_read_models
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare completion_row public.pachanga_tournament_completion_snapshots%rowtype;
declare existing_row public.pachanga_tournament_knockout_read_models%rowtype;
declare projected_row public.pachanga_tournament_knockout_read_models%rowtype;
declare rounds_value jsonb;
declare journeys_value jsonb;
declare organizer_value jsonb;
declare public_value jsonb;
declare checksum_value text;
declare unresolved_count integer;
declare unscheduled_count integer;
declare unassigned_referee_count integer;
declare pending_result_count integer;
declare review_count integer;
declare next_revision bigint;
declare latest_sequence bigint;
begin
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = target_bracket_id;
  if not found then
    raise exception 'TOURNAMENT_BRACKET_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = bracket_row.competition_id;
  select * into completion_row
  from public.pachanga_tournament_completion_snapshots snapshots
  where snapshots.id = bracket_row.current_completion_snapshot_id;
  select coalesce(jsonb_agg(
    round_item.payload
    order by round_item.round_order,
      case when round_item.round_code = 'THIRD_PLACE' then 0 else 1 end,
      round_item.round_code
  ), '[]'::jsonb)
  into rounds_value
  from (
    select round_source.round_order, round_source.round_code,
      jsonb_build_object(
        'code', round_source.round_code,
        'order', round_source.round_order,
        'label', case round_source.round_code
          when 'FINAL' then 'Final'
          when 'SEMIFINAL' then 'Semifinales'
          when 'QUARTERFINAL' then 'Cuartos'
          when 'THIRD_PLACE' then 'Tercer puesto'
          else replace(initcap(lower(round_source.round_code)), '_', ' ') end,
        'status', coalesce((
          select controls.status
          from public.pachanga_tournament_bracket_round_controls controls
          where controls.bracket_id = bracket_row.id
            and controls.round_code = round_source.round_code
          order by controls.control_revision desc,
            controls.server_sequence desc, controls.id desc
          limit 1
        ), case when not exists (
          select 1
          from public.pachanga_tournament_bracket_nodes pending_nodes
          where pending_nodes.bracket_id = bracket_row.id
            and pending_nodes.round_code = round_source.round_code
            and pending_nodes.status not in ('advanced', 'cancelled')
        ) then 'READY_TO_COMPLETE' else 'ACTIVE' end),
        'nodes', (
          select coalesce(jsonb_agg(
            private.pachanga_tournament_knockout_node_snapshot_v1(nodes.id)
            order by nodes.node_order, nodes.id
          ), '[]'::jsonb)
          from public.pachanga_tournament_bracket_nodes nodes
          where nodes.bracket_id = bracket_row.id
            and nodes.round_order = round_source.round_order
            and nodes.round_code = round_source.round_code
        )
      ) as payload
    from (
      select distinct nodes.round_order, nodes.round_code
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.bracket_id = bracket_row.id
    ) round_source
  ) round_item;
  select coalesce(jsonb_agg(jsonb_build_object(
    'entry', private.pachanga_tournament_knockout_entry_public_v1(entries.id),
    'currentNodeId', (
      select nodes.id
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.bracket_id = bracket_row.id
        and entries.id in (nodes.home_entry_id, nodes.away_entry_id)
        and nodes.status not in ('advanced', 'cancelled', 'invalidated')
      order by nodes.round_order desc, nodes.node_order, nodes.id limit 1
    ),
    'eliminatedAtNodeId', (
      select nodes.id
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.bracket_id = bracket_row.id and nodes.loser_entry_id = entries.id
      order by nodes.round_order desc, nodes.node_order, nodes.id limit 1
    ),
    'isChampion', completion_row.champion_entry_id = entries.id,
    'finalPosition', case
      when completion_row.champion_entry_id = entries.id then 1
      when completion_row.runner_up_entry_id = entries.id then 2
      when completion_row.third_place_entry_id = entries.id then 3
      when completion_row.fourth_place_entry_id = entries.id then 4
      else null end,
    'nodes', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'nodeId', nodes.id,
        'roundCode', nodes.round_code,
        'status', nodes.status,
        'outcome', case when nodes.winner_entry_id = entries.id then 'ADVANCED'
          when nodes.loser_entry_id = entries.id then 'ELIMINATED'
          when entries.id in (nodes.home_entry_id, nodes.away_entry_id) then 'PENDING'
          else null end,
        'canonicalMatchId', nodes.canonical_match_id
      ) order by nodes.round_order, nodes.node_order, nodes.id), '[]'::jsonb)
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.bracket_id = bracket_row.id
        and entries.id in (
          nodes.home_entry_id, nodes.away_entry_id,
          nodes.winner_entry_id, nodes.loser_entry_id
        )
    )
  ) order by teams.name, entries.id), '[]'::jsonb)
  into journeys_value
  from public.pachanga_competition_entries entries
  join public.pachanga_groups teams on teams.id = entries.team_id
  where entries.competition_id = bracket_row.competition_id
    and exists (
      select 1
      from public.pachanga_tournament_bracket_node_slots slots
      where slots.bracket_id = bracket_row.id
        and slots.resolved_entry_id = entries.id
    );
  select count(*) filter (where nodes.status = 'awaiting_sources'),
    count(*) filter (where nodes.canonical_match_id is null
      and nodes.status in ('ready', 'scheduled')),
    count(*) filter (where nodes.status = 'result_pending'),
    count(*) filter (where nodes.status = 'administrative_review')
  into unresolved_count, unscheduled_count, pending_result_count, review_count
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.bracket_id = bracket_row.id;
  select count(*) into unassigned_referee_count
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.bracket_id = bracket_row.id
    and nodes.canonical_match_id is not null
    and nodes.status not in ('advanced', 'cancelled', 'invalidated')
    and not exists (
      select 1 from public.pachanga_referee_assignments assignments
      where assignments.canonical_match_id = nodes.canonical_match_id
        and assignments.status not in ('cancelled', 'declined', 'expired', 'replaced')
    );
  organizer_value := jsonb_build_object(
    'unresolvedNodes', unresolved_count,
    'matchesWithoutSchedule', unscheduled_count,
    'matchesWithoutReferee', unassigned_referee_count,
    'pendingResults', pending_result_count,
    'reviewRequired', review_count,
    'invalidations', (select count(*)
      from public.pachanga_tournament_bracket_invalidations invalidations
      where invalidations.bracket_id = bracket_row.id),
    'dependencyImpacts', (select count(*)
      from public.pachanga_tournament_bracket_dependency_impacts impacts
      join public.pachanga_tournament_bracket_invalidations invalidations
        on invalidations.id = impacts.bracket_invalidation_id
      where invalidations.bracket_id = bracket_row.id),
    'completionHealthy', completion_row.id is not null,
    'nextAction', case
      when review_count > 0 then 'REVIEW_DEPENDENCIES'
      when unresolved_count > 0 then 'WAIT_FOR_SOURCES'
      when unscheduled_count > 0 then 'RESERVE_MATCH_SLOTS'
      when pending_result_count > 0 then 'REVIEW_RESULTS'
      when completion_row.id is null then 'PLAY_REMAINING_MATCHES'
      when bracket_row.status = 'active' then 'COMPLETE_TOURNAMENT'
      when bracket_row.status = 'completed' then 'LOCK_TOURNAMENT'
      else 'NONE' end
  );
  latest_sequence := greatest(
    target_server_sequence,
    bracket_row.server_sequence,
    coalesce((select max(nodes.server_sequence)
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.bracket_id = bracket_row.id), 0),
    coalesce((select max(decisions.server_sequence)
      from public.pachanga_tournament_bracket_advance_decisions decisions
      where decisions.bracket_id = bracket_row.id), 0),
    coalesce(completion_row.server_sequence, 0)
  );
  public_value := jsonb_strip_nulls(jsonb_build_object(
    'kind', 'TournamentBracketView',
    'competition', jsonb_build_object(
      'id', competition_row.id,
      'name', competition_row.name,
      'slug', competition_row.slug,
      'status', competition_row.status,
      'visibility', competition_row.visibility
    ),
    'bracket', jsonb_build_object(
      'id', bracket_row.id,
      'status', bracket_row.status,
      'format', 'SINGLE_MATCH_KNOCKOUT',
      'size', bracket_row.bracket_size,
      'roundCount', bracket_row.round_count,
      'thirdPlaceEnabled', bracket_row.third_place_enabled,
      'revision', bracket_row.revision,
      'serverSequence', bracket_row.server_sequence,
      'qualificationSnapshotId', bracket_row.qualification_snapshot_id,
      'bracketTemplateId', bracket_row.bracket_template_id,
      'ruleRevisionId', bracket_row.rule_revision_id
    ),
    'rounds', rounds_value,
    'teamJourneys', journeys_value,
    'completion', case when completion_row.id is null then null else completion_row.snapshot end,
    'publicSafeSummary', jsonb_strip_nulls(jsonb_build_object(
      'competitionId', bracket_row.competition_id,
      'status', bracket_row.status,
      'rounds', jsonb_array_length(rounds_value),
      'champion', private.pachanga_tournament_knockout_entry_public_v1(
        completion_row.champion_entry_id
      )
    )),
    'health', jsonb_build_object(
      'status', case when review_count = 0 then 'CURRENT' else 'REVIEW_REQUIRED' end,
      'unresolvedNodes', unresolved_count,
      'reviewRequired', review_count
    ),
    'cache', jsonb_build_object(
      'entityType', 'tournament_bracket',
      'entityId', bracket_row.id,
      'revision', bracket_row.revision,
      'serverSequence', latest_sequence,
      'updatedAt', bracket_row.updated_at
    )
  ));
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'public', public_value,
    'organizer', organizer_value
  ));
  select * into existing_row
  from public.pachanga_tournament_knockout_read_models models
  where models.competition_id = bracket_row.competition_id for update;
  if found and existing_row.snapshot_checksum = checksum_value then
    return existing_row;
  end if;
  next_revision := coalesce(existing_row.revision, 0) + 1;
  insert into public.pachanga_tournament_knockout_read_models(
    competition_id, bracket_id, revision, server_sequence,
    public_snapshot, organizer_snapshot, snapshot_checksum, rebuilt_at
  ) values (
    bracket_row.competition_id, bracket_row.id, next_revision, latest_sequence,
    public_value, organizer_value, checksum_value, clock_timestamp()
  ) on conflict (competition_id) do update set
    bracket_id = excluded.bracket_id,
    revision = excluded.revision,
    server_sequence = excluded.server_sequence,
    public_snapshot = excluded.public_snapshot,
    organizer_snapshot = excluded.organizer_snapshot,
    snapshot_checksum = excluded.snapshot_checksum,
    rebuilt_at = excluded.rebuilt_at
  returning * into projected_row;
  return projected_row;
end;
$$;

create or replace function private.pachanga_tournament_knockout_read_model_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare model_row public.pachanga_tournament_knockout_read_models%rowtype;
declare can_read boolean;
declare can_manage boolean;
begin
  can_read := private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'read'
  );
  if not can_read then
    raise exception 'TOURNAMENT_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into model_row
  from public.pachanga_tournament_knockout_read_models models
  where models.competition_id = target_competition_id;
  if not found then
    raise exception 'TOURNAMENT_BRACKET_NOT_FOUND' using errcode = 'P0002';
  end if;
  can_manage := private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'bracket_manage'
  );
  return model_row.public_snapshot || jsonb_build_object(
    'organizerDesk', case when can_manage then model_row.organizer_snapshot else null end,
    'permissions', jsonb_build_object(
      'read', true,
      'manageBracket', can_manage,
      'manageResults', private.pachanga_tournament_can_v1(
        target_competition_id, target_actor_id, 'results_manage'
      ),
      'manageOperations', private.pachanga_tournament_can_v1(
        target_competition_id, target_actor_id, 'operations_manage'
      )
    ),
    'readModel', jsonb_build_object(
      'revision', model_row.revision,
      'serverSequence', model_row.server_sequence,
      'checksum', model_row.snapshot_checksum,
      'rebuiltAt', model_row.rebuilt_at
    )
  );
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_knockout_entry_public_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_knockout_node_snapshot_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_knockout_rebuild_read_model_v1(uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_read_model_v1(uuid,uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

comment on table public.pachanga_tournament_knockout_read_models is
  'Canonical R6C read model rebuilt after authoritative events. Reads never recalculate Tournament progression.';
