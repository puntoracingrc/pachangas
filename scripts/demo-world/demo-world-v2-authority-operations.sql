\set ON_ERROR_STOP on

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.demo_v2_actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_strip_nulls(jsonb_build_object('sub', target_user_id, 'role', target_role))::text,
    true
  );
end;
$$;

create or replace function pg_temp.demo_v2_match_command(
  target_context_id uuid,
  target_actor_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select revision into current_revision
  from public.pachanga_competition_match_contexts
  where id = target_context_id;
  perform pg_temp.demo_v2_actor(target_actor_id);
  return public.command_pachanga_league_match_operations_v1(
    md5('demo-world-v2-r4c:' || target_context_id || ':' || target_operation_key)::uuid,
    target_context_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2","serviceWorkerVersion":"demo-world-v2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v2_exception_command(
  target_context_id uuid,
  target_actor_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select revision into current_revision
  from public.pachanga_competition_match_contexts
  where id = target_context_id;
  perform pg_temp.demo_v2_actor(target_actor_id);
  return public.command_pachanga_league_operational_exceptions_v1(
    md5('demo-world-v2-r4d:' || target_context_id || ':' || target_operation_key)::uuid,
    target_context_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2","serviceWorkerVersion":"demo-world-v2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
end;
$$;

\ir demo-world-v2-discipline-operations.sql

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  reason, granted_by
) values
  ('TEAM', md5('r4b-team-0')::uuid, 'competition_results', 'platform_grant', 'active', 'Demo World V2 authority proof', 'e4010000-0000-4000-8000-000000000001'),
  ('TEAM', md5('r4b-team-0')::uuid, 'competition_standings', 'platform_grant', 'active', 'Demo World V2 authority proof', 'e4010000-0000-4000-8000-000000000001'),
  ('TEAM', md5('r4b-team-0')::uuid, 'competition_operations', 'platform_grant', 'active', 'Demo World V2 authority proof', 'e4010000-0000-4000-8000-000000000001')
on conflict do nothing;

update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  creation_enabled = true,
  context_binding_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_public_calendar_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_public_standings_enabled = true,
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  league_public_exception_status_enabled = true
where singleton;

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, display_name, phone, position
)
select
  md5('demo-world-v2-profile-' || value)::uuid,
  md5('r4b-owner-' || value)::uuid,
  md5('r4b-team-' || value)::uuid,
  'Demo League player ' || value,
  '',
  'Delantero'
from generate_series(1, 6) value;

insert into public.pachanga_competition_roster_members(
  id, roster_id, roster_revision_id, entry_id, player_profile_id,
  source_group_id, source_user_id, eligibility_status, public_snapshot, reason_code
)
select
  md5('demo-world-v2-roster-member-' || value)::uuid,
  md5('r4b-roster-' || value)::uuid,
  md5('r4b-roster-revision-' || value)::uuid,
  md5('r4b-entry-' || value)::uuid,
  md5('demo-world-v2-profile-' || value)::uuid,
  md5('r4b-team-' || value)::uuid,
  md5('r4b-owner-' || value)::uuid,
  'eligible',
  jsonb_build_object('displayName', 'Demo League player ' || value, 'position', 'DEL'),
  'eligibility.demo_world_v2'
from generate_series(1, 6) value;

create temporary table demo_v2_results(
  ordinal integer primary key,
  score_home integer not null,
  score_away integer not null
);
insert into demo_v2_results values
  (1,2,1),(2,1,1),(3,0,2),(4,3,1),(5,1,0),
  (6,2,2),(7,0,1),(8,4,2),(9,1,3),(10,2,0),
  (11,3,0),(12,2,1),(13,1,2),(14,3,0),(15,2,2);

do $demo$
declare match_row record;
declare result_row demo_v2_results%rowtype;
declare home_owner uuid;
declare away_owner uuid;
declare home_member uuid;
declare away_member uuid;
declare home_squad uuid;
declare away_squad uuid;
declare request_id uuid;
declare incident_id uuid;
declare late_incident_id uuid;
declare suspension_id uuid;
declare partial_home integer;
declare partial_away integer;
declare rescheduled_start timestamptz;
declare rescheduled_end timestamptz;
begin
  for match_row in
    select
      contexts.*,
      items.pairing_key,
      rounds.round_number,
      row_number() over(order by rounds.round_number, items.pairing_key)::integer as ordinal
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
    join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
    where contexts.competition_id = 'e4040000-0000-4000-8000-000000000001'
    order by rounds.round_number, items.pairing_key
  loop
    select * into result_row from demo_v2_results where ordinal = match_row.ordinal;
    select groups.owner_id into home_owner
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = match_row.home_entry_id;
    select groups.owner_id into away_owner
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = match_row.away_entry_id;
    select pg_temp.demo_v2_roster_member_for_match(
      match_row.home_entry_id, match_row.canonical_match_id
    ) into home_member;
    select pg_temp.demo_v2_roster_member_for_match(
      match_row.away_entry_id, match_row.canonical_match_id
    ) into away_member;

    if match_row.ordinal = 3 then
      perform pg_temp.demo_v2_exception_command(
        match_row.id, home_owner, 'postponement-request', 'postponement.request',
        jsonb_build_object(
          'requestingEntryId', match_row.home_entry_id,
          'reasonCode', 'TEAM_CONFLICT',
          'reasonText', 'Conflicto de disponibilidad documentado por el equipo local.',
          'evidenceRefs', jsonb_build_array('demo://postponement-evidence'),
          'publicSummary', 'El equipo local solicita aplazar el partido.'
        )
      );
      select id into request_id
      from public.pachanga_competition_postponement_requests
      where competition_match_context_id = match_row.id
      order by server_sequence desc, id desc limit 1;
      perform pg_temp.demo_v2_exception_command(
        match_row.id, away_owner, 'postponement-accept', 'postponement.respond',
        jsonb_build_object(
          'requestId', request_id,
          'responseKind', 'ACCEPT',
          'reasonCode', 'RIVAL_ACCEPTED',
          'publicSummary', 'El rival acepta el aplazamiento.'
        )
      );
      perform pg_temp.demo_v2_exception_command(
        match_row.id, 'e4010000-0000-4000-8000-000000000002',
        'postponement-approve', 'postponement.respond',
        jsonb_build_object(
          'requestId', request_id,
          'responseKind', 'APPROVE',
          'reasonCode', 'ORGANIZER_APPROVED',
          'publicSummary', 'Aplazamiento aprobado por la organización.'
        )
      );
      rescheduled_start := match_row.scheduled_start + interval '35 days';
      rescheduled_end := match_row.scheduled_end + interval '35 days';
      perform pg_temp.demo_v2_exception_command(
        match_row.id, 'e4010000-0000-4000-8000-000000000002',
        'postponement-reschedule', 'fixture.reschedule',
        jsonb_build_object(
          'scheduledStart', rescheduled_start,
          'scheduledEnd', rescheduled_end,
          'timezone', 'Europe/Madrid',
          'venueLabel', 'Pista Demo Liga 1',
          'venueStatus', 'LABEL',
          'reasonCode', 'NEW_DATE',
          'publicSummary', 'Nueva fecha confirmada por la organización.'
        )
      );
    elsif match_row.ordinal = 7 then
      perform pg_temp.demo_v2_exception_command(
        match_row.id, 'e4010000-0000-4000-8000-000000000002',
        'venue-change', 'fixture.change_venue',
        jsonb_build_object(
          'venueLabel', 'Camp Municipal Besòs',
          'venueStatus', 'LABEL',
          'reasonCode', 'PITCH_UNAVAILABLE',
          'reasonText', 'La instalación original no está disponible.',
          'publicSummary', 'Cambio de campo confirmado.'
        )
      );
    end if;

    if match_row.ordinal = 11 then
      perform pg_temp.demo_v2_exception_command(
        match_row.id, home_owner, 'no-show-report', 'no_show.report',
        jsonb_build_object(
          'responsibleEntryId', match_row.away_entry_id,
          'reasonCode', 'NO_SHOW_REPORTED',
          'reasonText', 'El visitante no comparece tras el margen reglamentario.',
          'evidenceRefs', jsonb_build_array('demo://no-show-evidence'),
          'publicSummary', 'Incomparecencia en revisión.'
        )
      );
      select id into incident_id
      from public.pachanga_competition_no_show_incidents
      where competition_match_context_id = match_row.id
      order by server_sequence desc, id desc limit 1;
      perform pg_temp.demo_v2_exception_command(
        match_row.id, 'e4010000-0000-4000-8000-000000000002',
        'no-show-confirm', 'no_show.confirm',
        jsonb_build_object(
          'incidentId', incident_id,
          'reasonCode', 'NO_SHOW_CONFIRMED',
          'reasonText', 'La organización valida la evidencia.',
          'publicSummary', 'Incomparecencia confirmada.'
        )
      );
      continue;
    end if;

    perform pg_temp.demo_v2_match_command(match_row.id, home_owner, 'home-squad-create', 'squad.create', jsonb_build_object('entryId', match_row.home_entry_id));
    select id into home_squad from public.pachanga_competition_match_squads where competition_match_context_id = match_row.id and side = 'HOME';
    perform pg_temp.demo_v2_match_command(match_row.id, home_owner, 'home-squad-member', 'squad.member.add', jsonb_build_object('squadId', home_squad, 'rosterMemberId', home_member, 'memberRole', 'STARTER', 'shirtNumber', 9, 'positionOrder', 1, 'isCaptain', true));
    perform pg_temp.demo_v2_match_command(match_row.id, home_owner, 'home-squad-submit', 'squad.submit', jsonb_build_object('squadId', home_squad));
    perform pg_temp.demo_v2_match_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'home-squad-validate', 'squad.validate', jsonb_build_object('squadId', home_squad));
    perform pg_temp.demo_v2_match_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'home-squad-lock', 'squad.lock', jsonb_build_object('squadId', home_squad));

    perform pg_temp.demo_v2_match_command(match_row.id, away_owner, 'away-squad-create', 'squad.create', jsonb_build_object('entryId', match_row.away_entry_id));
    select id into away_squad from public.pachanga_competition_match_squads where competition_match_context_id = match_row.id and side = 'AWAY';
    perform pg_temp.demo_v2_match_command(match_row.id, away_owner, 'away-squad-member', 'squad.member.add', jsonb_build_object('squadId', away_squad, 'rosterMemberId', away_member, 'memberRole', 'STARTER', 'shirtNumber', 10, 'positionOrder', 1, 'isCaptain', true));
    perform pg_temp.demo_v2_match_command(match_row.id, away_owner, 'away-squad-submit', 'squad.submit', jsonb_build_object('squadId', away_squad));
    perform pg_temp.demo_v2_match_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'away-squad-validate', 'squad.validate', jsonb_build_object('squadId', away_squad));
    perform pg_temp.demo_v2_match_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'away-squad-lock', 'squad.lock', jsonb_build_object('squadId', away_squad));

    perform pg_temp.demo_v2_match_command(match_row.id, home_owner, 'home-attendance', 'attendance.set', jsonb_build_object('entryId', match_row.home_entry_id, 'rosterMemberId', home_member, 'status', 'going'));
    perform pg_temp.demo_v2_match_command(match_row.id, away_owner, 'away-attendance', 'attendance.set', jsonb_build_object('entryId', match_row.away_entry_id, 'rosterMemberId', away_member, 'status', 'going'));
    perform pg_temp.demo_v2_match_command(match_row.id, home_owner, 'home-attendance-close', 'attendance.close', jsonb_build_object('entryId', match_row.home_entry_id));
    perform pg_temp.demo_v2_match_command(match_row.id, away_owner, 'away-attendance-close', 'attendance.close', jsonb_build_object('entryId', match_row.away_entry_id));
    perform pg_temp.demo_v2_match_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'match-ready', 'match.mark_ready');
    perform pg_temp.demo_v2_match_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'match-start', 'match.start');

    if match_row.ordinal = 5 then
      -- The public season is frozen in the past; move only the temporary
      -- context clock so the real grace-period policy can be exercised.
      update public.pachanga_competition_match_contexts set
        scheduled_start = clock_timestamp() - interval '5 minutes',
        scheduled_end = clock_timestamp() + interval '65 minutes'
      where id = match_row.id;
      perform pg_temp.demo_v2_exception_command(
        match_row.id, home_owner, 'late-arrival-report', 'late_arrival.report',
        jsonb_build_object(
          'responsibleEntryId', match_row.away_entry_id,
          'reasonCode', 'TEAM_DELAY',
          'reasonText', 'El visitante comunica un retraso breve.',
          'publicSummary', 'Retraso reportado.'
        )
      );
      select id into late_incident_id
      from public.pachanga_competition_late_arrival_incidents
      where competition_match_context_id = match_row.id
      order by server_sequence desc, id desc limit 1;
      perform pg_temp.demo_v2_exception_command(
        match_row.id, away_owner, 'late-arrival-confirm', 'late_arrival.confirm_arrival',
        jsonb_build_object(
          'incidentId', late_incident_id,
          'reasonCode', 'ARRIVED',
          'publicSummary', 'El equipo llega dentro del margen reglamentario.'
        )
      );
      update public.pachanga_competition_match_contexts set
        scheduled_start = match_row.scheduled_start,
        scheduled_end = match_row.scheduled_end
      where id = match_row.id;
    end if;

    if match_row.ordinal = 15 then
      partial_home := least(result_row.score_home, 1);
      partial_away := least(result_row.score_away, 1);
      perform pg_temp.demo_v2_exception_command(
        match_row.id, home_owner, 'suspension-report', 'suspension.report',
        jsonb_build_object(
          'reportingEntryId', match_row.home_entry_id,
          'reportedMinute', 38,
          'partialScoreHome', partial_home,
          'partialScoreAway', partial_away,
          'reasonCode', 'SAFETY_STOP',
          'reasonText', 'El partido se detiene temporalmente por seguridad.',
          'evidenceRefs', jsonb_build_array('demo://suspension-evidence'),
          'publicSummary', 'Partido suspendido en el minuto 38.'
        )
      );
      select id into suspension_id
      from public.pachanga_competition_match_suspensions
      where competition_match_context_id = match_row.id
      order by server_sequence desc, id desc limit 1;
      perform pg_temp.demo_v2_exception_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'suspension-confirm', 'suspension.confirm', jsonb_build_object('suspensionId', suspension_id, 'reasonCode', 'SUSPENSION_CONFIRMED'));
      perform pg_temp.demo_v2_exception_command(
        match_row.id, 'e4010000-0000-4000-8000-000000000002',
        'suspension-schedule-resume', 'suspension.schedule_resume',
        jsonb_build_object(
          'suspensionId', suspension_id,
          'resumeMinute', 38,
          'scheduledStart', match_row.scheduled_start + interval '2 days',
          'scheduledEnd', match_row.scheduled_end + interval '2 days',
          'timezone', 'Europe/Madrid',
          'venueStatus', 'LABEL',
          'venueLabel', match_row.venue_label,
          'reasonCode', 'RESUMPTION_APPROVED',
          'publicSummary', 'El partido se reanudará desde el minuto 38.'
        )
      );
      perform pg_temp.demo_v2_exception_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'suspension-resume', 'suspension.resume', jsonb_build_object('suspensionId', suspension_id, 'reasonCode', 'MATCH_RESUMED', 'publicSummary', 'Partido reanudado.'));
    end if;

    perform pg_temp.demo_v2_match_command(match_row.id, 'e4010000-0000-4000-8000-000000000002', 'match-played', 'match.mark_played');
    perform pg_temp.demo_v2_match_command(
      match_row.id, home_owner, 'result-submit', 'sporting_result.submit',
      jsonb_build_object(
        'entryId', match_row.home_entry_id,
        'scoreHome', result_row.score_home,
        'scoreAway', result_row.score_away,
        'scorers', case when result_row.score_home > 0
          then jsonb_build_array(jsonb_build_object('rosterMemberId', home_member, 'goals', result_row.score_home))
          else '[]'::jsonb end
      )
    );
    perform pg_temp.demo_v2_match_command(
      match_row.id, away_owner, 'result-accept', 'sporting_result.accept',
      jsonb_build_object(
        'entryId', match_row.away_entry_id,
        'scorers', case when result_row.score_away > 0
          then jsonb_build_array(jsonb_build_object('rosterMemberId', away_member, 'goals', result_row.score_away))
          else '[]'::jsonb end
      )
    );
    perform pg_temp.demo_v2_discipline_after_match(
      match_row.id,
      match_row.canonical_match_id,
      match_row.round_number,
      match_row.ordinal,
      match_row.home_entry_id,
      match_row.away_entry_id
    );
  end loop;

  perform pg_temp.demo_v2_discipline_finalize();

  if (select count(*) from public.pachanga_competition_match_contexts
      where competition_id = 'e4040000-0000-4000-8000-000000000001' and status = 'official') <> 15 then
    raise exception 'DEMO_WORLD_V2_NOT_ALL_MATCHES_OFFICIAL';
  end if;
  if (select count(*) from public.pachanga_competition_official_result_decisions decisions
      join public.pachanga_competition_match_contexts contexts on contexts.id = decisions.competition_match_context_id
      where contexts.competition_id = 'e4040000-0000-4000-8000-000000000001') <> 15 then
    raise exception 'DEMO_WORLD_V2_OFFICIAL_RESULT_COUNT_INVALID';
  end if;
  if (select count(*) from public.pachanga_competition_disciplinary_events
      where competition_id = 'e4040000-0000-4000-8000-000000000001') <> 20 then
    raise exception 'DEMO_WORLD_V2_1_DISCIPLINE_EVENT_COUNT_INVALID';
  end if;
  if (select count(*) from public.pachanga_competition_sanctions
      where competition_id = 'e4040000-0000-4000-8000-000000000001') <> 4 then
    raise exception 'DEMO_WORLD_V2_1_SANCTION_COUNT_INVALID:%', (
      select count(*) from public.pachanga_competition_sanctions
      where competition_id = 'e4040000-0000-4000-8000-000000000001'
    );
  end if;
end;
$demo$;
