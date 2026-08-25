-- Pachangas IQ R4D: canonical operational reads, platform flags and public status.

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
        'league_match_operations_flags', 'league_operational_exceptions_flags'
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
          'league_match_operations_flags', 'league_operational_exceptions_flags'
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

create or replace function public.get_pachanga_league_operational_exceptions_flags_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  return private.pachanga_league_operational_exceptions_flags_v1();
end;
$$;

revoke all on function public.get_pachanga_league_operational_exceptions_flags_v1()
  from public, anon;
grant execute on function public.get_pachanga_league_operational_exceptions_flags_v1()
  to authenticated, service_role;

create or replace function public.get_pachanga_league_operational_match_v1(
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
  if auth.uid() is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  select contexts.id into context_id
  from public.pachanga_competition_match_contexts contexts
  where contexts.competition_id = target_competition_id
    and contexts.canonical_match_id = target_canonical_match_id
    and contexts.source_kind = 'COMPETITION_GENERATED'
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  if context_id is null then
    raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002';
  end if;
  return private.pachanga_league_operational_snapshot_v1(context_id, auth.uid());
end;
$$;

revoke all on function public.get_pachanga_league_operational_match_v1(uuid, uuid)
  from public, anon;
grant execute on function public.get_pachanga_league_operational_match_v1(uuid, uuid)
  to authenticated, service_role;

create or replace function public.get_pachanga_public_league_fixture_status_v1(
  target_competition_id uuid,
  target_canonical_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare original_item public.pachanga_competition_schedule_items%rowtype;
declare fixture_row public.pachanga_competition_fixture_changes%rowtype;
declare fixture_revision public.pachanga_competition_fixture_change_revisions%rowtype;
declare public_state text;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.league_operational_exceptions_foundation_enabled
     or not settings.league_public_exception_status_enabled then
    raise exception 'LEAGUE_PUBLIC_EXCEPTION_STATUS_DISABLED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.pachanga_competitions competitions
    where competitions.id = target_competition_id
      and competitions.visibility = 'public'
  ) then raise exception 'PUBLIC_COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.competition_id = target_competition_id
    and contexts.canonical_match_id = target_canonical_match_id
    and contexts.source_kind = 'COMPETITION_GENERATED'
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  if not found then
    raise exception 'PUBLIC_FIXTURE_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into original_item
  from public.pachanga_competition_schedule_items items
  where items.id = context_row.schedule_item_id;
  select * into fixture_row
  from public.pachanga_competition_fixture_changes changes
  where changes.competition_match_context_id = context_row.id
    and changes.status = 'active';
  if found then
    select * into fixture_revision
    from public.pachanga_competition_fixture_change_revisions revisions
    where revisions.id = fixture_row.current_revision_id;
  end if;
  public_state := case context_row.status
    when 'postponed' then 'Aplazado'
    when 'suspended' then 'Suspendido'
    when 'cancelled' then 'Cancelado'
    when 'administrative_review' then 'Pendiente de decisión'
    else 'Programado' end;
  return jsonb_build_object(
    'kind', 'PublicLeagueFixtureStatus',
    'competitionId', context_row.competition_id,
    'canonicalMatchId', context_row.canonical_match_id,
    'status', context_row.status,
    'statusLabel', public_state,
    'originalSchedule', jsonb_build_object(
      'scheduledStart', original_item.scheduled_start,
      'scheduledEnd', original_item.scheduled_end,
      'timezone', original_item.timezone,
      'venueLabel', original_item.venue_label,
      'venueStatus', original_item.venue_status
    ),
    'effectiveSchedule', jsonb_build_object(
      'scheduledStart', context_row.scheduled_start,
      'scheduledEnd', context_row.scheduled_end,
      'timezone', context_row.timezone,
      'venueLabel', context_row.venue_label,
      'venueStatus', context_row.venue_status
    ),
    'latestChange', case when fixture_row.id is null then null else jsonb_build_object(
      'type', fixture_row.change_type,
      'reasonCode', fixture_revision.public_reason_code,
      'summary', fixture_revision.public_summary,
      'effectiveAt', fixture_revision.effective_at,
      'revision', fixture_row.revision,
      'serverSequence', fixture_row.server_sequence
    ) end,
    'revision', context_row.revision,
    'serverSequence', context_row.server_sequence
  );
end;
$$;

revoke all on function public.get_pachanga_public_league_fixture_status_v1(uuid, uuid)
  from public;
grant execute on function public.get_pachanga_public_league_fixture_status_v1(uuid, uuid)
  to anon, authenticated, service_role;

create or replace function public.get_my_pachanga_league_exception_requests_v1(
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
declare bounded_size integer := least(greatest(coalesce(page_size, 30), 1), 100);
declare bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'kind', 'MyLeagueExceptionRequests',
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id,
      'competitionId', source.competition_id,
      'canonicalMatchId', source.canonical_match_id,
      'contextId', source.competition_match_context_id,
      'requestingEntry', jsonb_build_object('id', source.requesting_entry_id, 'name', source.requesting_name),
      'respondingEntry', jsonb_build_object('id', source.responding_entry_id, 'name', source.responding_name),
      'actorScope', case
        when private.pachanga_league_entry_actor_scope_v1(source.requesting_entry_id, actor_id)
          in ('TEAM_OWNER', 'PRIMARY_DELEGATE') then 'REQUESTING_TEAM'
        else 'RESPONDING_TEAM' end,
      'status', source.status,
      'proposedStart', source.proposed_start,
      'proposedEnd', source.proposed_end,
      'proposedTimezone', source.proposed_timezone,
      'proposedVenueLabel', source.proposed_venue_label,
      'proposedVenueStatus', source.proposed_venue_status,
      'reasonCode', source.reason_code,
      'publicSummary', source.public_summary,
      'responseDeadline', source.response_deadline,
      'teamResponse', source.team_response,
      'organizerResponse', source.organizer_response,
      'revision', source.revision,
      'serverSequence', source.server_sequence,
      'responses', coalesce((select jsonb_agg(jsonb_build_object(
        'id', responses.id,
        'responderKind', responses.responder_kind,
        'responseKind', responses.response_kind,
        'proposedStart', responses.proposed_start,
        'proposedEnd', responses.proposed_end,
        'proposedTimezone', responses.proposed_timezone,
        'proposedVenueLabel', responses.proposed_venue_label,
        'proposedVenueStatus', responses.proposed_venue_status,
        'publicSummary', responses.public_summary,
        'serverSequence', responses.server_sequence,
        'respondedAt', responses.responded_at
      ) order by responses.server_sequence, responses.id)
      from public.pachanga_competition_postponement_responses responses
      where responses.postponement_request_id = source.id), '[]'::jsonb)
    ) order by source.server_sequence desc, source.id desc)
    from (
      select requests.*, requesting_teams.name as requesting_name,
        responding_teams.name as responding_name
      from public.pachanga_competition_postponement_requests requests
      join public.pachanga_competition_entries requesting_entries
        on requesting_entries.id = requests.requesting_entry_id
      join public.pachanga_groups requesting_teams
        on requesting_teams.id = requesting_entries.team_id
      join public.pachanga_competition_entries responding_entries
        on responding_entries.id = requests.responding_entry_id
      join public.pachanga_groups responding_teams
        on responding_teams.id = responding_entries.team_id
      where private.pachanga_league_entry_actor_scope_v1(requests.requesting_entry_id, actor_id)
          in ('TEAM_OWNER', 'PRIMARY_DELEGATE')
        or private.pachanga_league_entry_actor_scope_v1(requests.responding_entry_id, actor_id)
          in ('TEAM_OWNER', 'PRIMARY_DELEGATE')
      order by requests.server_sequence desc, requests.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb),
    'flags', private.pachanga_league_operational_exceptions_flags_v1()
  );
end;
$$;

revoke all on function public.get_my_pachanga_league_exception_requests_v1(integer, integer)
  from public, anon;
grant execute on function public.get_my_pachanga_league_exception_requests_v1(integer, integer)
  to authenticated, service_role;

create or replace function public.get_pachanga_league_postponement_desk_v1(
  target_competition_id uuid,
  status_filter text default null,
  page_size integer default 50,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare normalized_status text := nullif(lower(trim(coalesce(status_filter, ''))), '');
declare bounded_size integer := least(greatest(coalesce(page_size, 50), 1), 200);
declare bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(target_competition_id, actor_id, 'operations_read') then
    raise exception 'COMPETITION_OPERATIONS_READER_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'kind', 'LeaguePostponementDesk',
    'competitionId', target_competition_id,
    'filter', normalized_status,
    'counts', jsonb_build_object(
      'pending', (select count(*) from public.pachanga_competition_postponement_requests requests
        where requests.competition_id = target_competition_id and requests.status = 'awaiting_response'),
      'expiredDeadlines', (select count(*) from public.pachanga_competition_postponement_requests requests
        where requests.competition_id = target_competition_id
          and requests.status = 'awaiting_response'
          and requests.response_deadline < clock_timestamp()),
      'postponedMatches', (select count(*) from public.pachanga_competition_match_contexts contexts
        where contexts.competition_id = target_competition_id and contexts.status = 'postponed')
    ),
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id,
      'canonicalMatchId', source.canonical_match_id,
      'contextId', source.competition_match_context_id,
      'contextStatus', source.context_status,
      'requestingEntry', jsonb_build_object('id', source.requesting_entry_id, 'name', source.requesting_name),
      'respondingEntry', jsonb_build_object('id', source.responding_entry_id, 'name', source.responding_name),
      'status', source.status,
      'proposedStart', source.proposed_start,
      'proposedEnd', source.proposed_end,
      'proposedTimezone', source.proposed_timezone,
      'proposedVenueLabel', source.proposed_venue_label,
      'proposedVenueStatus', source.proposed_venue_status,
      'reasonCode', source.reason_code,
      'publicSummary', source.public_summary,
      'responseDeadline', source.response_deadline,
      'deadlineExpired', source.response_deadline < clock_timestamp(),
      'deadlinePolicy', source.deadline_policy,
      'teamResponse', source.team_response,
      'organizerResponse', source.organizer_response,
      'revision', source.revision,
      'serverSequence', source.server_sequence
    ) order by source.server_sequence desc, source.id desc)
    from (
      select requests.*, contexts.status as context_status,
        requesting_teams.name as requesting_name,
        responding_teams.name as responding_name
      from public.pachanga_competition_postponement_requests requests
      join public.pachanga_competition_match_contexts contexts
        on contexts.id = requests.competition_match_context_id
      join public.pachanga_competition_entries requesting_entries
        on requesting_entries.id = requests.requesting_entry_id
      join public.pachanga_groups requesting_teams
        on requesting_teams.id = requesting_entries.team_id
      join public.pachanga_competition_entries responding_entries
        on responding_entries.id = requests.responding_entry_id
      join public.pachanga_groups responding_teams
        on responding_teams.id = responding_entries.team_id
      where requests.competition_id = target_competition_id
        and (normalized_status is null or requests.status = normalized_status)
      order by requests.server_sequence desc, requests.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb),
    'flags', private.pachanga_league_operational_exceptions_flags_v1()
  );
end;
$$;

revoke all on function public.get_pachanga_league_postponement_desk_v1(
  uuid, text, integer, integer
) from public, anon;
grant execute on function public.get_pachanga_league_postponement_desk_v1(
  uuid, text, integer, integer
) to authenticated, service_role;

create or replace function public.get_pachanga_league_incident_desk_v1(
  target_competition_id uuid,
  page_size integer default 100,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare bounded_size integer := least(greatest(coalesce(page_size, 100), 1), 300);
declare bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(target_competition_id, actor_id, 'operations_read') then
    raise exception 'COMPETITION_OPERATIONS_READER_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'kind', 'LeagueIncidentDesk',
    'competitionId', target_competition_id,
    'counts', jsonb_build_object(
      'lateArrivalOpen', (select count(*) from public.pachanga_competition_late_arrival_incidents incidents
        where incidents.competition_id = target_competition_id and incidents.status = 'reported'),
      'noShowPending', (select count(*) from public.pachanga_competition_no_show_incidents incidents
        where incidents.competition_id = target_competition_id and incidents.status in ('reported', 'under_review')),
      'suspended', (select count(*) from public.pachanga_competition_match_suspensions suspensions
        where suspensions.competition_id = target_competition_id
          and suspensions.status in ('reported', 'confirmed', 'resume_scheduled', 'replay_ordered'))
    ),
    'lateArrivals', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id, 'canonicalMatchId', source.canonical_match_id,
      'contextId', source.competition_match_context_id,
      'responsibleEntry', jsonb_build_object('id', source.responsible_entry_id, 'name', source.team_name),
      'status', source.status, 'scheduledStart', source.scheduled_start,
      'graceDeadline', source.grace_deadline, 'reportedAt', source.reported_at,
      'arrivalAt', source.arrival_at, 'revision', source.revision,
      'serverSequence', source.server_sequence
    ) order by source.server_sequence desc, source.id desc)
    from (
      select incidents.*, teams.name as team_name
      from public.pachanga_competition_late_arrival_incidents incidents
      join public.pachanga_competition_entries entries on entries.id = incidents.responsible_entry_id
      join public.pachanga_groups teams on teams.id = entries.team_id
      where incidents.competition_id = target_competition_id
      order by incidents.server_sequence desc, incidents.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb),
    'noShows', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id, 'canonicalMatchId', source.canonical_match_id,
      'contextId', source.competition_match_context_id,
      'responsibleEntry', jsonb_build_object('id', source.responsible_entry_id, 'name', source.team_name),
      'status', source.status, 'scheduledStart', source.scheduled_start,
      'graceDeadline', source.grace_deadline, 'reasonCode', source.reason_code,
      'publicSummary', source.public_summary,
      'officialResultDecisionId', source.official_result_decision_id,
      'revision', source.revision, 'serverSequence', source.server_sequence
    ) order by source.server_sequence desc, source.id desc)
    from (
      select incidents.*, teams.name as team_name
      from public.pachanga_competition_no_show_incidents incidents
      join public.pachanga_competition_entries entries on entries.id = incidents.responsible_entry_id
      join public.pachanga_groups teams on teams.id = entries.team_id
      where incidents.competition_id = target_competition_id
      order by incidents.server_sequence desc, incidents.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb),
    'suspensions', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id, 'canonicalMatchId', source.canonical_match_id,
      'contextId', source.competition_match_context_id,
      'status', source.status, 'reportedMinute', source.reported_minute,
      'sportingScoreHome', source.sporting_score_home,
      'sportingScoreAway', source.sporting_score_away,
      'reasonCode', source.reason_code, 'publicSummary', source.public_summary,
      'revision', source.revision, 'serverSequence', source.server_sequence,
      'reportedAt', source.reported_at, 'confirmedAt', source.confirmed_at,
      'resolvedAt', source.resolved_at
    ) order by source.server_sequence desc, source.id desc)
    from (
      select suspensions.*
      from public.pachanga_competition_match_suspensions suspensions
      where suspensions.competition_id = target_competition_id
      order by suspensions.server_sequence desc, suspensions.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb),
    'flags', private.pachanga_league_operational_exceptions_flags_v1()
  );
end;
$$;

revoke all on function public.get_pachanga_league_incident_desk_v1(uuid, integer, integer)
  from public, anon;
grant execute on function public.get_pachanga_league_incident_desk_v1(uuid, integer, integer)
  to authenticated, service_role;

create or replace function public.get_pachanga_league_administrative_decision_desk_v1(
  target_competition_id uuid,
  status_filter text default null,
  page_size integer default 100,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare normalized_status text := nullif(lower(trim(coalesce(status_filter, ''))), '');
declare bounded_size integer := least(greatest(coalesce(page_size, 100), 1), 300);
declare bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(target_competition_id, actor_id, 'operations_read') then
    raise exception 'COMPETITION_OPERATIONS_READER_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'kind', 'LeagueAdministrativeDecisionDesk',
    'competitionId', target_competition_id,
    'filter', normalized_status,
    'items', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id,
      'decisionType', source.decision_type,
      'targetType', source.target_type,
      'targetId', source.target_id,
      'ruleRevisionId', source.rule_revision_id,
      'reasonCode', source.reason_code,
      'publicSummary', source.public_summary,
      'previousDecisionId', source.previous_decision_id,
      'status', source.status,
      'revision', source.revision,
      'serverSequence', source.server_sequence,
      'decidedAt', source.decided_at,
      'effects', coalesce((select jsonb_agg(jsonb_build_object(
        'id', effects.id,
        'order', effects.effect_order,
        'type', effects.effect_type,
        'status', effects.status,
        'fixtureChangeId', effects.fixture_change_id,
        'officialResultDecisionId', effects.official_result_decision_id,
        'resumptionDecisionId', effects.match_resumption_decision_id,
        'serverSequence', effects.server_sequence,
        'appliedAt', effects.applied_at
      ) order by effects.effect_order, effects.id)
      from public.pachanga_competition_administrative_effects effects
      where effects.administrative_decision_id = source.id), '[]'::jsonb)
    ) order by source.server_sequence desc, source.id desc)
    from (
      select decisions.*
      from public.pachanga_competition_administrative_decisions decisions
      where decisions.competition_id = target_competition_id
        and (normalized_status is null or decisions.status = normalized_status)
      order by decisions.server_sequence desc, decisions.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb),
    'flags', private.pachanga_league_operational_exceptions_flags_v1()
  );
end;
$$;

revoke all on function public.get_pachanga_league_administrative_decision_desk_v1(
  uuid, text, integer, integer
) from public, anon;
grant execute on function public.get_pachanga_league_administrative_decision_desk_v1(
  uuid, text, integer, integer
) to authenticated, service_role;

create or replace function public.get_pachanga_platform_league_operational_exceptions_v1(
  page_size integer default 100,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare bounded_size integer := least(greatest(coalesce(page_size, 100), 1), 500);
declare bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
begin
  perform private.pachanga_platform_require_v1('competitions.manage');
  return jsonb_build_object(
    'kind', 'PlatformLeagueOperationalExceptions',
    'flags', private.pachanga_league_operational_exceptions_flags_v1(),
    'counts', jsonb_build_object(
      'fixtureChanges', (select count(*) from public.pachanga_competition_fixture_changes),
      'postponementRequests', (select count(*) from public.pachanga_competition_postponement_requests),
      'postponementResponses', (select count(*) from public.pachanga_competition_postponement_responses),
      'venueChangeRequests', (select count(*) from public.pachanga_competition_venue_change_requests),
      'venueDecisions', (select count(*) from public.pachanga_competition_venue_condition_decisions),
      'lateArrivalIncidents', (select count(*) from public.pachanga_competition_late_arrival_incidents),
      'noShowIncidents', (select count(*) from public.pachanga_competition_no_show_incidents),
      'matchSuspensions', (select count(*) from public.pachanga_competition_match_suspensions),
      'administrativeDecisions', (select count(*) from public.pachanga_competition_administrative_decisions),
      'administrativeEffects', (select count(*) from public.pachanga_competition_administrative_effects),
      'expiredDeadlines', (select count(*) from public.pachanga_competition_postponement_requests requests
        where requests.status = 'awaiting_response' and requests.response_deadline < clock_timestamp()),
      'operationalEvents', (select count(*) from private.pachanga_competition_events events
        where events.aggregate_type = 'league_operational_exceptions'),
      'legacyBackfill', 0
    ),
    'health', jsonb_build_object(
      'publishedScheduleItemsMutated', 0,
      'duplicateActiveContexts', (select count(*) from (
        select contexts.canonical_match_id
        from public.pachanga_competition_match_contexts contexts
        where contexts.status <> 'retired'
        group by contexts.canonical_match_id having count(*) > 1
      ) duplicates),
      'fixtureChangesWithoutRevision', (select count(*)
        from public.pachanga_competition_fixture_changes changes
        where changes.current_revision_id is null),
      'noShowResultsWithoutSource', (select count(*)
        from public.pachanga_competition_official_result_decisions decisions
        where decisions.outcome in ('NO_SHOW', 'FORFEIT', 'SUSPENDED_MATCH_DECISION')
          and decisions.operational_source_id is null)
    ),
    'recent', coalesce((select jsonb_agg(jsonb_build_object(
      'contextId', source.id,
      'competitionId', source.competition_id,
      'canonicalMatchId', source.canonical_match_id,
      'status', source.status,
      'scheduledStart', source.scheduled_start,
      'revision', source.revision,
      'serverSequence', source.server_sequence
    ) order by source.server_sequence desc, source.id desc)
    from (
      select contexts.*
      from public.pachanga_competition_match_contexts contexts
      where contexts.source_kind = 'COMPETITION_GENERATED'
        and contexts.status in (
          'postponed', 'suspended', 'abandoned', 'cancelled', 'administrative_review'
        )
      order by contexts.server_sequence desc, contexts.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_league_operational_exceptions_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_league_operational_exceptions_v1(integer, integer)
  to authenticated;

create or replace function public.command_pachanga_league_operational_exceptions_platform_v1(
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
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c4d1'::uuid;
declare actor_id uuid := auth.uid();
declare action_name constant text := 'league_operational_exceptions_flags.set';
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare request_hash text;
declare replay jsonb;
declare metadata jsonb;
declare sequence_value bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare snapshot jsonb;
declare response jsonb;
declare next_foundation boolean;
declare next_postponements boolean;
declare next_rescheduling boolean;
declare next_venue_changes boolean;
declare next_late_arrival boolean;
declare next_no_show boolean;
declare next_suspensions boolean;
declare next_admin_decisions boolean;
declare next_public_status boolean;
begin
  if operation_id is null or aggregate_id <> flags_aggregate_id
     or expected_revision is null or expected_revision < 0 then
    raise exception 'INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_FLAGS_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(command_payload) > 32768 then
    raise exception 'INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_FLAGS_PAYLOAD' using errcode = '22023';
  end if;
  perform private.pachanga_platform_require_v1('competitions.manage');
  perform private.pachanga_platform_require_v1('flags.write');
  if exists (
    select 1 from jsonb_each(command_payload) pair
    where pair.key <> 'reason'
      and (
        pair.key not in (
          'foundationEnabled', 'postponementsEnabled', 'reschedulingEnabled',
          'venueChangesEnabled', 'lateArrivalEnabled', 'noShowEnabled',
          'matchSuspensionsEnabled', 'administrativeDecisionsEnabled',
          'publicExceptionStatusEnabled'
        ) or jsonb_typeof(pair.value) <> 'boolean'
      )
  ) then raise exception 'INVALID_LEAGUE_OPERATIONAL_EXCEPTIONS_FLAG' using errcode = '22023'; end if;
  metadata := private.pachanga_league_match_sanitize_metadata_v1(client_metadata);
  request_hash := private.pachanga_league_operational_request_hash_v1(
    action_name, aggregate_id, expected_revision, command_payload
  );
  perform pg_advisory_xact_lock(hashtextextended(
    'league-operational-exceptions-flags:' || operation_id::text, 0
  ));
  replay := private.pachanga_league_operational_replay_v1(
    operation_id, actor_id, 'authenticated', action_name, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton
  for update;
  if settings.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  next_foundation := coalesce((command_payload ->> 'foundationEnabled')::boolean,
    settings.league_operational_exceptions_foundation_enabled);
  next_postponements := coalesce((command_payload ->> 'postponementsEnabled')::boolean,
    settings.league_postponements_enabled);
  next_rescheduling := coalesce((command_payload ->> 'reschedulingEnabled')::boolean,
    settings.league_rescheduling_enabled);
  next_venue_changes := coalesce((command_payload ->> 'venueChangesEnabled')::boolean,
    settings.league_venue_changes_enabled);
  next_late_arrival := coalesce((command_payload ->> 'lateArrivalEnabled')::boolean,
    settings.league_late_arrival_enabled);
  next_no_show := coalesce((command_payload ->> 'noShowEnabled')::boolean,
    settings.league_no_show_enabled);
  next_suspensions := coalesce((command_payload ->> 'matchSuspensionsEnabled')::boolean,
    settings.league_match_suspensions_enabled);
  next_admin_decisions := coalesce((command_payload ->> 'administrativeDecisionsEnabled')::boolean,
    settings.league_administrative_decisions_enabled);
  next_public_status := coalesce((command_payload ->> 'publicExceptionStatusEnabled')::boolean,
    settings.league_public_exception_status_enabled);
  if not next_foundation then
    next_postponements := false;
    next_rescheduling := false;
    next_venue_changes := false;
    next_late_arrival := false;
    next_no_show := false;
    next_suspensions := false;
    next_admin_decisions := false;
    next_public_status := false;
  end if;
  if not next_late_arrival or not next_admin_decisions then next_no_show := false; end if;
  if next_foundation and not (
    settings.league_participation_foundation_enabled
    and settings.league_rosters_enabled
    and settings.league_scheduling_foundation_enabled
    and settings.league_schedule_publication_enabled
    and settings.league_canonical_fixture_creation_enabled
    and settings.league_match_operations_foundation_enabled
  ) then raise exception 'R4A_R4B_R4C_DEPENDENCY_NOT_ENABLED' using errcode = '42501'; end if;
  if next_no_show and not (
    settings.league_sporting_results_enabled
    and settings.league_official_results_enabled
    and settings.league_standings_enabled
  ) then raise exception 'R4C_RESULT_DEPENDENCY_NOT_ENABLED' using errcode = '42501'; end if;
  if next_suspensions and not settings.league_sporting_results_enabled then
    raise exception 'R4C_SPORTING_RESULTS_DEPENDENCY_NOT_ENABLED' using errcode = '42501';
  end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings current_settings set
    league_operational_exceptions_foundation_enabled = next_foundation,
    league_postponements_enabled = next_postponements,
    league_rescheduling_enabled = next_rescheduling,
    league_venue_changes_enabled = next_venue_changes,
    league_late_arrival_enabled = next_late_arrival,
    league_no_show_enabled = next_no_show,
    league_match_suspensions_enabled = next_suspensions,
    league_administrative_decisions_enabled = next_admin_decisions,
    league_public_exception_status_enabled = next_public_status,
    revision = current_settings.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = confirmed_at
  where current_settings.singleton
  returning * into settings;
  snapshot := private.pachanga_league_operational_exceptions_flags_v1();
  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedRevision', settings.revision,
    'confirmedAt', confirmed_at,
    'serverSequence', sequence_value,
    'snapshot', snapshot,
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'league_operational_exceptions_flags',
      'entityId', flags_aggregate_id,
      'revision', settings.revision,
      'serverSequence', sequence_value
    ))
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, actor_id, 'authenticated', 'league_operational_exceptions',
    aggregate_id::text, null, action_name, settings.revision, sequence_value,
    left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), action_name), 120),
    snapshot - 'updatedAt', confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, null, null, null, null, null,
    'league_operational_exceptions_flags', flags_aggregate_id::text,
    settings.revision, confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    operation_id, actor_id, 'authenticated', action_name,
    'league_operational_exceptions', aggregate_id::text, request_hash,
    settings.revision, sequence_value, metadata, response, confirmed_at
  );
  return response;
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_operational_exceptions_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_operational_exceptions_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) to authenticated;
