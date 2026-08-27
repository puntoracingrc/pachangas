-- Pachangas IQ R6B: canonical Tournament Hub read model. Clients cache this
-- snapshot and invalidate it by revision; they never rebuild sports state.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_tournament_group_hub_snapshot_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare preparation_row public.pachanga_tournament_group_stage_preparations%rowtype;
declare qualification_row public.pachanga_tournament_qualification_snapshots%rowtype;
declare bracket_row public.pachanga_tournament_bracket_templates%rowtype;
declare groups_value jsonb;
declare rounds_value jsonb;
declare matches_value jsonb;
declare standings_value jsonb;
declare qualification_value jsonb := null;
declare bracket_value jsonb := null;
declare journeys_value jsonb;
declare organizer_value jsonb := null;
declare rule_value jsonb;
declare latest_sequence bigint;
declare manager boolean;
begin
  if target_actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'read') then
    raise exception 'TOURNAMENT_READ_FORBIDDEN' using errcode = '42501';
  end if;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id
    and competitions.competition_type = 'TOURNAMENT'
    and competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1';
  if not found then raise exception 'TOURNAMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.competition_id = target_competition_id;
  if not found then raise exception 'TOURNAMENT_GROUP_STAGE_NOT_PREPARED' using errcode = 'P0002'; end if;
  select * into preparation_row
  from public.pachanga_tournament_group_stage_preparations preparations
  where preparations.id = state_row.current_preparation_id;
  manager := private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'schedule_manage'
  ) or private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'results_manage'
  ) or private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'operations_manage'
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', groups.id,
    'name', groups.name,
    'order', groups.group_order,
    'entryCount', (
      select count(*) from public.pachanga_competition_stage_memberships memberships
      where memberships.stage_id = state_row.stage_id
        and memberships.competition_group_id = groups.id
        and memberships.status = 'active'
    ),
    'schedule', coalesce((
      select jsonb_build_object(
        'status', mappings.status,
        'revision', mappings.revision,
        'serverSequence', mappings.server_sequence,
        'slotCount', (
          select count(*)
          from public.pachanga_competition_schedule_slots slots
          where slots.competition_group_id = groups.id
            and slots.stage_id = state_row.stage_id
            and slots.status in ('available', 'assigned')
        ),
        'fixtureCount', (
          select count(*)
          from public.pachanga_competition_schedule_items items
          join public.pachanga_competition_schedule_plans plans
            on plans.current_revision_id = items.schedule_revision_id
          where plans.id = mappings.schedule_plan_id
        )
      )
      from public.pachanga_tournament_group_schedule_plans mappings
      where mappings.group_stage_state_id = state_row.id
        and mappings.competition_group_id = groups.id
    ), jsonb_build_object('status', 'NOT_PREPARED', 'slotCount', 0, 'fixtureCount', 0)),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'entryId', entries.id,
        'teamId', entries.team_id,
        'name', teams.name,
        'shield', jsonb_build_object(
          'revision', coalesce((
            select shields.revision
            from public.pachanga_team_shield_public shields
            where shields.group_id = teams.id
          ), 0),
          'config', coalesce((
            select shields.config
            from public.pachanga_team_shield_public shields
            where shields.group_id = teams.id
          ), private.pachanga_default_team_shield_config_v1(teams.name)),
          'serverSequence', coalesce((
            select shields.server_sequence
            from public.pachanga_team_shield_public shields
            where shields.group_id = teams.id
          ), 0),
          'updatedAt', (
            select shields.updated_at
            from public.pachanga_team_shield_public shields
            where shields.group_id = teams.id
          )
        )
      ) order by memberships.server_sequence, entries.id)
      from public.pachanga_competition_stage_memberships memberships
      join public.pachanga_competition_entries entries on entries.id = memberships.entry_id
      join public.pachanga_groups teams on teams.id = entries.team_id
      where memberships.stage_id = state_row.stage_id
        and memberships.competition_group_id = groups.id
        and memberships.status = 'active'
    ), '[]'::jsonb)
  ) order by groups.group_order, groups.id), '[]'::jsonb)
  into groups_value
  from public.pachanga_competition_groups groups
  where groups.stage_id = state_row.stage_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'roundNumber', source.round_number,
    'label', 'Jornada ' || source.round_number::text,
    'startsAt', source.starts_at,
    'endsAt', source.ends_at,
    'matchCount', source.match_count,
    'officialCount', source.official_count,
    'pendingCount', source.pending_count,
    'status', case
      when source.official_count = source.match_count then 'official'
      when source.started_count > 0 then 'in_progress'
      else 'scheduled'
    end
  ) order by source.round_number), '[]'::jsonb)
  into rounds_value
  from (
    select rounds.round_number, min(rounds.starts_at) starts_at,
      max(rounds.ends_at) ends_at, count(items.id)::integer match_count,
      count(*) filter (where contexts.status = 'official')::integer official_count,
      count(*) filter (where contexts.status in ('in_progress', 'played', 'result_pending'))::integer started_count,
      count(*) filter (where contexts.status not in ('official', 'cancelled', 'retired'))::integer pending_count
    from public.pachanga_tournament_group_schedule_plans mappings
    join public.pachanga_competition_schedule_plans plans on plans.id = mappings.schedule_plan_id
    join public.pachanga_competition_rounds rounds
      on rounds.schedule_revision_id = plans.current_revision_id
    join public.pachanga_competition_schedule_items items on items.round_id = rounds.id
    left join public.pachanga_competition_match_contexts contexts
      on contexts.id = items.competition_match_context_id
    where mappings.group_stage_state_id = state_row.id
      and mappings.status = 'published'
    group by rounds.round_number
  ) source;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', contexts.id,
    'canonicalMatchId', contexts.canonical_match_id,
    'scheduleItemId', items.id,
    'roundId', rounds.id,
    'roundNumber', rounds.round_number,
    'groupId', mappings.competition_group_id,
    'groupOrder', mappings.group_order,
    'home', jsonb_build_object(
      'entryId', home_entries.id, 'teamId', home_entries.team_id,
      'name', home_teams.name
    ),
    'away', jsonb_build_object(
      'entryId', away_entries.id, 'teamId', away_entries.team_id,
      'name', away_teams.name
    ),
    'startsAt', contexts.scheduled_start,
    'endsAt', contexts.scheduled_end,
    'timezone', contexts.timezone,
    'venue', case when contexts.venue_status = 'CONFIRMED' then jsonb_build_object(
      'id', contexts.venue_id, 'label', contexts.venue_label,
      'status', contexts.venue_status
    ) else jsonb_build_object('status', contexts.venue_status) end,
    'status', contexts.status,
    'revision', contexts.revision,
    'serverSequence', contexts.server_sequence,
    'score', case when decisions.id is null then null else jsonb_build_object(
      'home', decisions.effective_score_home,
      'away', decisions.effective_score_away,
      'official', contexts.status = 'official',
      'decisionId', decisions.id
    ) end,
    'resultState', results.state,
    'referee', case when assignments.id is null then null else jsonb_build_object(
      'assignmentId', assignments.id,
      'profileId', referees.id,
      'displayName', referees.public_display_name_snapshot,
      'status', assignments.status,
      'scheduleState', assignments.schedule_state
    ) end,
    'incident', case when contexts.status in (
      'postponed', 'suspended', 'abandoned', 'cancelled',
      'administrative_review', 'result_pending'
    ) then jsonb_build_object('status', contexts.status) else null end,
    'disciplineEventCount', (
      select count(*) from public.pachanga_competition_disciplinary_events events
      where events.canonical_match_id = contexts.canonical_match_id
    )
  )) order by contexts.scheduled_start, mappings.group_order,
    rounds.round_number, items.id), '[]'::jsonb)
  into matches_value
  from public.pachanga_tournament_group_schedule_plans mappings
  join public.pachanga_competition_schedule_plans plans on plans.id = mappings.schedule_plan_id
  join public.pachanga_competition_schedule_items items
    on items.schedule_revision_id = plans.current_revision_id
  join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
  join public.pachanga_competition_match_contexts contexts
    on contexts.id = items.competition_match_context_id
  join public.pachanga_competition_entries home_entries on home_entries.id = items.home_entry_id
  join public.pachanga_groups home_teams on home_teams.id = home_entries.team_id
  join public.pachanga_competition_entries away_entries on away_entries.id = items.away_entry_id
  join public.pachanga_groups away_teams on away_teams.id = away_entries.team_id
  left join public.pachanga_competition_match_sheets sheets
    on sheets.competition_match_context_id = contexts.id
  left join public.pachanga_competition_official_result_decisions decisions
    on decisions.id = sheets.active_official_decision_id
  left join public.pachanga_competition_sporting_results results
    on results.id = sheets.current_sporting_result_id
  left join lateral (
    select target_assignments.*
    from public.pachanga_referee_assignments target_assignments
    where target_assignments.canonical_match_id = contexts.canonical_match_id
      and target_assignments.assignment_role = 'MAIN_REFEREE'
      and target_assignments.status in ('proposed', 'accepted', 'confirmed', 'completed')
    order by target_assignments.server_sequence desc, target_assignments.id desc
    limit 1
  ) assignments on true
  left join public.pachanga_referee_profiles referees
    on referees.id = assignments.referee_profile_id
  where mappings.group_stage_state_id = state_row.id
    and mappings.status = 'published';

  select coalesce(jsonb_agg(jsonb_build_object(
    'groupId', groups.id,
    'groupOrder', groups.group_order,
    'groupName', groups.name,
    'state', case when standing_states.id is null then null else jsonb_build_object(
      'id', standing_states.id,
      'health', standing_states.health_status,
      'revision', standing_states.revision,
      'serverSequence', standing_states.server_sequence
    ) end,
    'snapshot', case when snapshots.id is null then null else jsonb_build_object(
      'id', snapshots.id,
      'sourceRevision', snapshots.source_revision,
      'checksum', snapshots.content_checksum,
      'criteria', snapshots.tie_break_criteria,
      'generatedAt', snapshots.generated_at,
      'serverSequence', snapshots.server_sequence
    ) end,
    'rows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'entryId', rows.entry_id,
        'team', rows.team_snapshot,
        'position', rows.position,
        'played', rows.played,
        'wins', rows.wins,
        'draws', rows.draws,
        'losses', rows.losses,
        'goalsFor', rows.goals_for,
        'goalsAgainst', rows.goals_against,
        'goalDifference', rows.goal_difference,
        'points', rows.effective_points,
        'tieBreakValues', rows.tie_break_values,
        'qualificationZone', case
          when rows.position <= (preparation_row.qualification_policy_snapshot ->> 'directQualifiersPerGroup')::integer
            then 'DIRECT_PROVISIONAL'
          else 'OUTSIDE_PROVISIONAL'
        end
      ) order by rows.position, rows.entry_id)
      from public.pachanga_competition_standing_rows rows
      where rows.standing_snapshot_id = snapshots.id
    ), '[]'::jsonb)
  ) order by groups.group_order, groups.id), '[]'::jsonb)
  into standings_value
  from public.pachanga_competition_groups groups
  left join public.pachanga_competition_standing_states standing_states
    on standing_states.stage_id = state_row.stage_id
   and standing_states.competition_group_id = groups.id
  left join public.pachanga_competition_standing_snapshots snapshots
    on snapshots.id = standing_states.current_snapshot_id
  where groups.stage_id = state_row.stage_id;

  select * into qualification_row
  from public.pachanga_tournament_qualification_snapshots snapshots
  where snapshots.id = state_row.current_qualification_snapshot_id;
  if found then
    qualification_value := jsonb_build_object(
      'id', qualification_row.id,
      'status', qualification_row.status,
      'policy', qualification_row.policy_snapshot,
      'health', qualification_row.health_snapshot,
      'groupQualifiers', qualification_row.group_qualifiers,
      'crossGroupQualifiers', qualification_row.cross_group_qualifiers,
      'eliminatedEntries', qualification_row.eliminated_entries,
      'targetBracketSlots', qualification_row.target_bracket_slots,
      'checksum', qualification_row.checksum,
      'sourceStandingsRevision', qualification_row.source_standings_revision,
      'serverSequence', qualification_row.server_sequence,
      'generatedAt', qualification_row.generated_at,
      'publishedAt', qualification_row.published_at
    );
  end if;
  select * into bracket_row
  from public.pachanga_tournament_bracket_templates templates
  where templates.id = state_row.current_bracket_template_id;
  if found then
    bracket_value := jsonb_build_object(
      'id', bracket_row.id,
      'status', bracket_row.status,
      'bracketSize', bracket_row.bracket_size,
      'firstRoundMatchCount', bracket_row.first_round_match_count,
      'checksum', bracket_row.checksum,
      'template', bracket_row.template_snapshot,
      'slots', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', slots.slot_key,
          'matchNumber', slots.match_number,
          'side', slots.side,
          'order', slots.bracket_order,
          'sourceKind', slots.source_kind,
          'sourceGroupId', slots.source_group_id,
          'sourcePosition', slots.source_position,
          'sourceExtraRank', slots.source_extra_rank,
          'resolvedEntryId', slots.resolved_entry_id,
          'status', slots.status
        ) order by slots.bracket_order, slots.id)
        from public.pachanga_tournament_bracket_slots slots
        where slots.bracket_template_id = bracket_row.id
      ), '[]'::jsonb),
      'progressionEnabled', false,
      'message', 'Cuadro preparado. La fase eliminatoria se activará en la siguiente fase.'
    );
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'entryId', entries.id,
    'teamId', entries.team_id,
    'teamName', teams.name,
    'groupId', memberships.competition_group_id,
    'standing', (
      select jsonb_build_object(
        'position', rows.position,
        'points', rows.effective_points,
        'played', rows.played
      )
      from public.pachanga_competition_standing_states standing_states
      join public.pachanga_competition_standing_rows rows
        on rows.standing_snapshot_id = standing_states.current_snapshot_id
       and rows.entry_id = entries.id
      where standing_states.stage_id = state_row.stage_id
        and standing_states.competition_group_id = memberships.competition_group_id
    ),
    'nextMatches', coalesce((
      select jsonb_agg(match_item order by match_item ->> 'startsAt')
      from (
        select jsonb_build_object(
          'contextId', contexts.id,
          'canonicalMatchId', contexts.canonical_match_id,
          'startsAt', contexts.scheduled_start,
          'status', contexts.status,
          'opponentEntryId', case when contexts.home_entry_id = entries.id
            then contexts.away_entry_id else contexts.home_entry_id end,
          'venueLabel', case when contexts.venue_status = 'CONFIRMED'
            then contexts.venue_label else null end,
          'attendance', (
            select jsonb_build_object(
              'going', count(*) filter (where participants.status = 'voy'),
              'doubt', count(*) filter (where participants.status = 'duda'),
              'notGoing', count(*) filter (where participants.status = 'no'),
              'playing', count(*) filter (where participants.seat_kind = 'playing'),
              'reserve', count(*) filter (where participants.seat_kind = 'reserve'),
              'closed', coalesce((
                select case when contexts.home_entry_id = entries.id
                  then sheets.home_attendance_closed_at is not null
                  else sheets.away_attendance_closed_at is not null end
                from public.pachanga_competition_match_sheets sheets
                where sheets.competition_match_context_id = contexts.id
              ), false),
              'revision', coalesce(max(participants.revision), 0),
              'serverSequence', coalesce(max(participants.server_sequence), 0)
            )
            from public.pachanga_match_participants participants
            where participants.canonical_match_id = contexts.canonical_match_id
              and participants.competition_entry_id = entries.id
          ),
          'squad', coalesce((
            select jsonb_build_object(
              'id', squads.id,
              'status', squads.status,
              'revision', squads.revision,
              'memberCount', revisions.member_count,
              'starterCount', revisions.starter_count,
              'substituteCount', revisions.substitute_count,
              'lockedAt', squads.locked_at,
              'serverSequence', squads.server_sequence
            )
            from public.pachanga_competition_match_squads squads
            left join public.pachanga_competition_match_squad_revisions revisions
              on revisions.id = squads.current_revision_id
            where squads.canonical_match_id = contexts.canonical_match_id
              and squads.entry_id = entries.id
            order by squads.server_sequence desc, squads.id desc
            limit 1
          ), jsonb_build_object('status', 'NOT_SUBMITTED')),
          'sanctions', coalesce((
            select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
              'id', applicable.id,
              'targetType', applicable.target_type,
              'playerProfileId', applicable.player_profile_id,
              'status', applicable.status,
              'unitType', applicable.unit_type,
              'remainingUnits', applicable.remaining_units,
              'publicReasonCategory', applicable.public_reason_category,
              'publicSummary', applicable.public_summary,
              'serverSequence', applicable.server_sequence
            )) order by applicable.server_sequence desc, applicable.id desc)
            from (
              select sanctions.*, revisions.public_reason_category,
                revisions.public_summary
              from public.pachanga_competition_sanctions sanctions
              join public.pachanga_competition_sanction_revisions revisions
                on revisions.id = sanctions.current_revision_id
              where sanctions.competition_id = target_competition_id
                and sanctions.status in ('active', 'provisional')
                and coalesce(sanctions.remaining_units, 0) > 0
                and not sanctions.suspensive_hold
                and (
                  (sanctions.target_type = 'TEAM' and sanctions.entry_id = entries.id)
                  or (sanctions.target_type = 'PLAYER' and exists (
                    select 1
                    from public.pachanga_competition_roster_members roster_members
                    join public.pachanga_competition_rosters rosters
                      on rosters.id = roster_members.roster_id
                     and rosters.current_revision_id = roster_members.roster_revision_id
                    where roster_members.entry_id = entries.id
                      and roster_members.player_profile_id = sanctions.player_profile_id
                      and roster_members.eligibility_status in ('eligible', 'waived')
                      and (roster_members.effective_until is null
                        or roster_members.effective_until > clock_timestamp())
                  ))
                )
              order by sanctions.server_sequence desc, sanctions.id desc
              limit 20
            ) applicable
          ), '[]'::jsonb),
          'referee', coalesce((
            select jsonb_build_object(
              'assignmentId', assignments.id,
              'profileId', referees.id,
              'displayName', referees.public_display_name_snapshot,
              'status', assignments.status,
              'scheduleState', assignments.schedule_state
            )
            from public.pachanga_referee_assignments assignments
            join public.pachanga_referee_profiles referees
              on referees.id = assignments.referee_profile_id
            where assignments.canonical_match_id = contexts.canonical_match_id
              and assignments.assignment_role = 'MAIN_REFEREE'
              and assignments.status in ('proposed', 'accepted', 'confirmed', 'completed')
            order by assignments.server_sequence desc, assignments.id desc
            limit 1
          ), jsonb_build_object('status', 'UNASSIGNED')),
          'incidents', coalesce((
            select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
              'id', incidents.id,
              'type', incidents.incident_type,
              'status', incidents.status,
              'responsibleEntryId', incidents.responsible_entry_id,
              'publicSummary', incidents.public_summary,
              'serverSequence', incidents.server_sequence
            )) order by incidents.server_sequence desc, incidents.id desc)
            from (
              select requests.id, 'POSTPONEMENT'::text incident_type,
                requests.status, null::uuid responsible_entry_id,
                requests.public_summary, requests.server_sequence
              from public.pachanga_competition_postponement_requests requests
              where requests.competition_match_context_id = contexts.id
                and requests.status not in ('denied', 'expired', 'withdrawn', 'superseded')
              union all
              select arrivals.id, 'LATE_ARRIVAL'::text, arrivals.status,
                arrivals.responsible_entry_id, ''::text, arrivals.server_sequence
              from public.pachanga_competition_late_arrival_incidents arrivals
              where arrivals.competition_match_context_id = contexts.id
                and arrivals.status <> 'dismissed'
              union all
              select no_shows.id, 'NO_SHOW'::text, no_shows.status,
                no_shows.responsible_entry_id, no_shows.public_summary,
                no_shows.server_sequence
              from public.pachanga_competition_no_show_incidents no_shows
              where no_shows.competition_match_context_id = contexts.id
                and no_shows.status <> 'rejected'
              union all
              select suspensions.id, 'SUSPENSION'::text, suspensions.status,
                null::uuid, suspensions.public_summary, suspensions.server_sequence
              from public.pachanga_competition_match_suspensions suspensions
              where suspensions.competition_match_context_id = contexts.id
                and suspensions.status <> 'cancelled'
            ) incidents
          ), '[]'::jsonb)
        ) match_item
        from public.pachanga_competition_match_contexts contexts
        where contexts.stage_id = state_row.stage_id
          and entries.id in (contexts.home_entry_id, contexts.away_entry_id)
          and contexts.status in ('scheduled', 'ready', 'postponed')
        order by contexts.scheduled_start, contexts.id limit 5
      ) upcoming
    ), '[]'::jsonb),
    'recentResults', coalesce((
      select jsonb_agg(result_item order by result_item ->> 'decidedAt' desc)
      from (
        select jsonb_build_object(
          'contextId', contexts.id,
          'canonicalMatchId', contexts.canonical_match_id,
          'home', decisions.effective_score_home,
          'away', decisions.effective_score_away,
          'decidedAt', decisions.decided_at
        ) result_item
        from public.pachanga_competition_match_contexts contexts
        join public.pachanga_competition_match_sheets sheets
          on sheets.competition_match_context_id = contexts.id
        join public.pachanga_competition_official_result_decisions decisions
          on decisions.id = sheets.active_official_decision_id
        where contexts.stage_id = state_row.stage_id
          and entries.id in (contexts.home_entry_id, contexts.away_entry_id)
          and contexts.status = 'official'
        order by decisions.server_sequence desc, decisions.id desc limit 5
      ) recent
    ), '[]'::jsonb),
    'qualificationStatus', case
      when qualification_row.id is null then 'PROVISIONAL'
      when exists (
        select 1 from public.pachanga_tournament_qualification_rows rows
        where rows.qualification_snapshot_id = qualification_row.id
          and rows.entry_id = entries.id
          and rows.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
      ) then case when qualification_row.status = 'PUBLISHED' then 'QUALIFIED' else 'IN_ZONE' end
      else case when qualification_row.status = 'PUBLISHED' then 'ELIMINATED' else 'OUTSIDE_ZONE' end
    end
  ) order by entries.server_sequence, entries.id), '[]'::jsonb)
  into journeys_value
  from public.pachanga_competition_entries entries
  join public.pachanga_groups teams on teams.id = entries.team_id
  join public.pachanga_competition_stage_memberships memberships
    on memberships.entry_id = entries.id
   and memberships.stage_id = state_row.stage_id
   and memberships.status = 'active'
  where entries.competition_id = target_competition_id
    and (teams.owner_id = target_actor_id or exists (
      select 1 from public.pachanga_group_members members
      where members.group_id = teams.id and members.user_id = target_actor_id
    ));

  if manager then
    organizer_value := jsonb_build_object(
      'unassignedScheduleItems', (
        select count(*)
        from public.pachanga_tournament_group_schedule_plans mappings
        join public.pachanga_competition_schedule_plans plans on plans.id = mappings.schedule_plan_id
        join public.pachanga_competition_schedule_items items
          on items.schedule_revision_id = plans.current_revision_id
        where mappings.group_stage_state_id = state_row.id and items.slot_id is null
      ),
      'matchesWithoutReferee', (
        select count(*) from public.pachanga_competition_match_contexts contexts
        where contexts.stage_id = state_row.stage_id
          and contexts.status not in ('official', 'cancelled', 'retired')
          and not exists (
            select 1 from public.pachanga_referee_assignments assignments
            where assignments.canonical_match_id = contexts.canonical_match_id
              and assignments.assignment_role = 'MAIN_REFEREE'
              and assignments.status in ('accepted', 'confirmed', 'completed')
          )
      ),
      'pendingResults', (
        select count(*) from public.pachanga_competition_match_contexts contexts
        where contexts.stage_id = state_row.stage_id and contexts.status = 'result_pending'
      ),
      'openIncidents', (
        select count(*) from public.pachanga_competition_match_contexts contexts
        where contexts.stage_id = state_row.stage_id
          and contexts.status in ('postponed', 'suspended', 'abandoned', 'administrative_review')
      ),
      'standingsHealth', case when exists (
        select 1 from public.pachanga_competition_standing_states standing_states
        where standing_states.stage_id = state_row.stage_id
          and standing_states.health_status <> 'CURRENT'
      ) then 'ATTENTION' else 'CURRENT' end,
      'qualificationHealth', coalesce(qualification_row.health_snapshot ->> 'status', 'NOT_BUILT'),
      'nextAction', case state_row.status
        when 'prepared' then 'ADD_SLOTS'
        when 'scheduling' then 'GENERATE_OR_VALIDATE'
        when 'schedule_validated' then 'PUBLISH_SCHEDULE'
        when 'schedule_published' then 'OPERATE_MATCHES'
        when 'active' then 'OPERATE_MATCHES'
        when 'complete' then case when bracket_row.id is null
          then 'CREATE_BRACKET_TEMPLATE' else 'GROUP_STAGE_COMPLETE' end
        else 'REVIEW'
      end
    );
  end if;
  rule_value := jsonb_build_object(
    'ruleRevisionId', state_row.rule_revision_id,
    'schedulePolicy', preparation_row.schedule_policy_snapshot,
    'qualificationPolicy', preparation_row.qualification_policy_snapshot,
    'checksum', preparation_row.rule_checksum
  );
  select greatest(
    state_row.server_sequence,
    coalesce((select max(contexts.server_sequence)
      from public.pachanga_competition_match_contexts contexts
      where contexts.stage_id = state_row.stage_id), 0),
    coalesce((select max(standing_states.server_sequence)
      from public.pachanga_competition_standing_states standing_states
      where standing_states.stage_id = state_row.stage_id), 0),
    coalesce(qualification_row.server_sequence, 0),
    coalesce(bracket_row.server_sequence, 0)
  ) into latest_sequence;
  return jsonb_strip_nulls(jsonb_build_object(
    'kind', 'TournamentGroupStageHub',
    'competition', jsonb_build_object(
      'id', competition_row.id,
      'name', competition_row.name,
      'slug', competition_row.slug,
      'status', competition_row.status,
      'visibility', competition_row.visibility,
      'revision', competition_row.tournament_revision,
      'serverSequence', competition_row.server_sequence
    ),
    'groupStage', jsonb_build_object(
      'id', state_row.id,
      'editionId', state_row.edition_id,
      'stageId', state_row.stage_id,
      'status', state_row.status,
      'groupCount', state_row.group_count,
      'entryCount', state_row.entry_count,
      'fixtureCount', state_row.fixture_count,
      'officialFixtureCount', state_row.official_fixture_count,
      'revision', state_row.revision,
      'serverSequence', state_row.server_sequence,
      'completedAt', state_row.completed_at
    ),
    'summary', jsonb_build_object(
      'played', (select count(*) from jsonb_array_elements(matches_value) match_item
        where match_item ->> 'status' in ('played', 'result_pending', 'official')),
      'official', (select count(*) from jsonb_array_elements(matches_value) match_item
        where match_item ->> 'status' = 'official'),
      'remaining', (select count(*) from jsonb_array_elements(matches_value) match_item
        where match_item ->> 'status' not in ('official', 'cancelled', 'retired')),
      'postponed', (select count(*) from jsonb_array_elements(matches_value) match_item
        where match_item ->> 'status' = 'postponed'),
      'suspended', (select count(*) from jsonb_array_elements(matches_value) match_item
        where match_item ->> 'status' = 'suspended'),
      'pendingResults', (select count(*) from jsonb_array_elements(matches_value) match_item
        where match_item ->> 'status' = 'result_pending')
    ),
    'groups', groups_value,
    'rounds', rounds_value,
    'matches', matches_value,
    'standings', standings_value,
    'qualification', qualification_value,
    'bracketTemplate', bracket_value,
    'teamJourneys', journeys_value,
    'organizerDesk', organizer_value,
    'rules', rule_value,
    'permissions', jsonb_build_object(
      'manageSchedule', private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'schedule_manage'),
      'publishSchedule', private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'schedule_publish'),
      'manageResults', private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'results_manage'),
      'manageOperations', private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'operations_manage'),
      'manageQualification', private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'qualification_manage'),
      'publishQualification', private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'qualification_publish'),
      'manageBracket', private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'bracket_manage')
    ),
    'cache', jsonb_build_object(
      'entityType', 'tournament_group_stage',
      'entityId', state_row.id,
      'revision', state_row.revision,
      'serverSequence', latest_sequence,
      'updatedAt', state_row.updated_at
    )
  ));
end;
$$;

revoke all on function private.pachanga_tournament_group_hub_snapshot_v1(uuid,uuid)
  from public, anon, authenticated;
