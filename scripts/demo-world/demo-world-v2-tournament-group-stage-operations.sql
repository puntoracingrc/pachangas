\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '240s';

begin;

create schema if not exists simulation;
create table if not exists simulation.demo_world_tournament_group_stage_public_snapshot (
  snapshot jsonb not null
);
create table if not exists simulation.demo_world_tournament_group_stage_final_proof (
  proof jsonb not null
);
truncate simulation.demo_world_tournament_group_stage_public_snapshot;
truncate simulation.demo_world_tournament_group_stage_final_proof;

create or replace function pg_temp.demo_v25_actor(target_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.demo_v25_group_command(
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare target_competition_id uuid;
declare expected_revision bigint;
begin
  select competitions.id into target_competition_id
  from public.pachanga_competitions competitions
  where competitions.slug = 'copa-barrios-iq-2027';
  select coalesce(
    (select states.revision from public.pachanga_tournament_group_stage_states states
      where states.competition_id = target_competition_id),
    (select competitions.tournament_revision from public.pachanga_competitions competitions
      where competitions.id = target_competition_id)
  ) into expected_revision;
  perform pg_temp.demo_v25_actor('64010000-0000-4000-8000-000000000001');
  return public.command_pachanga_tournament_group_stage_v1(
    md5('demo-world-v2-5-r6b:' || target_operation_key)::uuid,
    target_competition_id,
    expected_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament_group_stage"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v25_match_command(
  target_context_id uuid,
  target_actor_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select contexts.revision into current_revision
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id;
  perform pg_temp.demo_v25_actor(target_actor_id);
  return public.command_pachanga_league_match_operations_v1(
    md5('demo-world-v2-5-r4c:' || target_context_id || ':' || target_operation_key)::uuid,
    target_context_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament_group_stage"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v25_exception_command(
  target_context_id uuid,
  target_actor_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select contexts.revision into current_revision
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id;
  perform pg_temp.demo_v25_actor(target_actor_id);
  return public.command_pachanga_league_operational_exceptions_v1(
    md5('demo-world-v2-5-r4d:' || target_context_id || ':' || target_operation_key)::uuid,
    target_context_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament_group_stage"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v25_discipline_command(
  target_aggregate_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare competition_id uuid;
declare current_revision bigint;
begin
  select competitions.id, competitions.discipline_revision
    into competition_id, current_revision
  from public.pachanga_competitions competitions
  where competitions.slug = 'copa-barrios-iq-2027';
  perform pg_temp.demo_v25_actor('64010000-0000-4000-8000-000000000001');
  return public.command_pachanga_competition_discipline_v1(
    md5('demo-world-v2-5-r5:' || target_operation_key)::uuid,
    competition_id,
    target_aggregate_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament_group_stage"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v25_assignment_command(
  target_actor_id uuid,
  target_assignment_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select assignments.revision into current_revision
  from public.pachanga_referee_assignments assignments
  where assignments.id = target_assignment_id;
  current_revision := coalesce(current_revision, 0);
  perform pg_temp.demo_v25_actor(target_actor_id);
  return public.command_pachanga_referee_assignment_beta_v1(
    md5('demo-world-v2-5-referee:' || target_operation_key)::uuid,
    target_assignment_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament_group_stage"}'::jsonb
  );
end;
$$;

-- Eight real synthetic players and one locked R4A roster per accepted team.
insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  md5('demo-world-v2-5-player-user-' || team_number || '-' || player_number)::uuid,
  'demo-world-v2-5-player-' || team_number || '-' || player_number || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'Jugador Copa ' || team_number || '.' || player_number)
from generate_series(1, 16) team_number
cross join generate_series(1, 8) player_number;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  ('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  md5('demo-world-v2-5-player-user-' || team_number || '-' || player_number)::uuid,
  'player',
  'Jugador Copa ' || team_number || '.' || player_number
from generate_series(1, 16) team_number
cross join generate_series(1, 8) player_number;

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, display_name, phone, position
)
select
  md5('demo-world-v2-5-player-profile-' || team_number || '-' || player_number)::uuid,
  md5('demo-world-v2-5-player-user-' || team_number || '-' || player_number)::uuid,
  ('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'Jugador Copa ' || team_number || '.' || player_number,
  '',
  case player_number when 1 then 'Portero' when 7 then 'Delantero' else 'Centrocampista' end
from generate_series(1, 16) team_number
cross join generate_series(1, 8) player_number;

do $demo_rosters$
declare entry_row record;
declare roster_id uuid;
declare roster_revision_id uuid;
declare player_number integer;
declare team_number integer;
begin
  for entry_row in
    select entries.*, groups.owner_id, plans.rule_revision_id as active_rule_revision_id,
      substring(groups.team_code from 3)::integer as team_number
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    join public.pachanga_competitions competitions on competitions.id = entries.competition_id
    join public.pachanga_competition_draw_plans plans
      on plans.competition_id = competitions.id and plans.status = 'published'
    where competitions.slug = 'copa-barrios-iq-2027'
      and entries.status = 'accepted'
    order by groups.team_code
  loop
    team_number := entry_row.team_number;
    roster_id := md5('demo-world-v2-5-roster-' || team_number)::uuid;
    roster_revision_id := md5('demo-world-v2-5-roster-revision-' || team_number)::uuid;
    insert into public.pachanga_competition_rosters(
      id, entry_id, category_id, rule_revision_id, status, revision, created_by
    ) values (
      roster_id, entry_row.id, entry_row.category_id, entry_row.active_rule_revision_id,
      'locked', 1, entry_row.owner_id
    );
    insert into public.pachanga_competition_roster_revisions(
      id, roster_id, revision_number, roster_status, rule_revision_id,
      member_count, eligibility_summary, member_set_checksum, reason, created_by
    ) values (
      roster_revision_id, roster_id, 1, 'locked', entry_row.active_rule_revision_id,
      0, '{}'::jsonb,
      encode(extensions.digest(convert_to('[]', 'UTF8'), 'sha256'), 'hex'),
      'Demo World V2.5 canonical Tournament roster', entry_row.owner_id
    );
    for player_number in 1..8 loop
      insert into public.pachanga_competition_roster_members(
        id, roster_id, roster_revision_id, entry_id, player_profile_id,
        source_group_id, source_user_id, eligibility_status, public_snapshot, reason_code
      ) values (
        md5('demo-world-v2-5-roster-member-' || team_number || '-' || player_number)::uuid,
        roster_id, roster_revision_id, entry_row.id,
        md5('demo-world-v2-5-player-profile-' || team_number || '-' || player_number)::uuid,
        entry_row.team_id,
        md5('demo-world-v2-5-player-user-' || team_number || '-' || player_number)::uuid,
        'eligible',
        jsonb_build_object(
          'displayName', 'Jugador Copa ' || team_number || '.' || player_number,
          'position', case player_number when 1 then 'POR' when 7 then 'DEL' else 'MC' end
        ),
        'eligibility.demo_world_v2_5'
      );
    end loop;
    perform private.pachanga_league_finalize_roster_revision_v1(roster_revision_id);
    update public.pachanga_competition_rosters rosters
    set current_revision_id = roster_revision_id
    where rosters.id = roster_id;
  end loop;
end;
$demo_rosters$;

-- Activate only R6B private-beta gates through the audited platform RPC.
select pg_temp.demo_v25_actor('64010000-0000-4000-8000-000000000090');
select public.command_pachanga_tournament_group_stage_platform_v1(
  md5('demo-world-v2-5-r6b-flags')::uuid,
  '00000000-0000-0000-0000-00000000c6b1',
  (select settings.revision from private.pachanga_competition_foundation_settings settings where settings.singleton),
  'tournament.group_stage.flags.set',
  '{"groupStageEnabled":true,"groupSchedulingEnabled":true,"groupMatchGenerationEnabled":true,"groupTrackingEnabled":true,"groupStandingsEnabled":true,"qualificationEnabled":true,"bracketTemplateEnabled":true,"reason":"Demo World V2.5 Tournament Group Stage"}'::jsonb,
  '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament_group_stage"}'::jsonb
);

select pg_temp.demo_v25_group_command('prepare', 'group_stage.prepare');

do $demo_slots$
declare group_row record;
declare slots_value jsonb;
begin
  for group_row in
    select groups.id, groups.group_order
    from public.pachanga_competition_groups groups
    join public.pachanga_competition_stages stages on stages.id = groups.stage_id
    join public.pachanga_competition_editions editions on editions.id = stages.edition_id
    join public.pachanga_competitions competitions on competitions.id = editions.competition_id
    where competitions.slug = 'copa-barrios-iq-2027'
    order by groups.group_order
  loop
    select jsonb_agg(jsonb_build_object(
      'startsAt', ('2027-05-08T18:00:00+02:00'::timestamptz
        + make_interval(days => ((slot_number - 1) / 2) * 7, hours => ((slot_number - 1) % 2) * 2)),
      'endsAt', ('2027-05-08T19:20:00+02:00'::timestamptz
        + make_interval(days => ((slot_number - 1) / 2) * 7, hours => ((slot_number - 1) % 2) * 2)),
      'timezone', 'Europe/Madrid',
      'venueLabel', 'Pista Copa ' || chr(64 + group_row.group_order)
    ) order by slot_number)
    into slots_value
    from generate_series(1, 6) slot_number;
    perform pg_temp.demo_v25_group_command(
      'slots-group-' || group_row.group_order,
      'group_schedule.create',
      jsonb_build_object('groupId', group_row.id, 'slots', slots_value)
    );
  end loop;
end;
$demo_slots$;

select pg_temp.demo_v25_group_command('generate', 'group_schedule.generate');
select pg_temp.demo_v25_group_command('validate', 'group_schedule.validate');
select pg_temp.demo_v25_group_command('publish', 'group_schedule.publish');
select pg_temp.demo_v25_group_command('activate', 'group_stage.activate');

create temporary table demo_v25_results(
  ordinal integer primary key,
  score_home integer not null,
  score_away integer not null
);
insert into demo_v25_results(ordinal, score_home, score_away)
select ordered.ordinal,
  case when ordered.home_team_number < ordered.away_team_number
    then 2 + ((ordered.home_team_number + ordered.away_team_number) % 2)
    else ((ordered.home_team_number + ordered.away_team_number) % 2) end,
  case when ordered.away_team_number < ordered.home_team_number
    then 2 + ((ordered.home_team_number + ordered.away_team_number) % 2)
    else ((ordered.home_team_number + ordered.away_team_number) % 2) end
from (
  select row_number() over(
      order by rounds.round_number, groups.group_order, items.pairing_key, contexts.id
    )::integer as ordinal,
    substring(home_teams.team_code from 3)::integer as home_team_number,
    substring(away_teams.team_code from 3)::integer as away_team_number
  from public.pachanga_competition_match_contexts contexts
  join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
  join public.pachanga_competition_groups groups on groups.id = contexts.competition_group_id
  join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
  join public.pachanga_competitions competitions on competitions.id = contexts.competition_id
  join public.pachanga_competition_entries home_entries on home_entries.id = contexts.home_entry_id
  join public.pachanga_groups home_teams on home_teams.id = home_entries.team_id
  join public.pachanga_competition_entries away_entries on away_entries.id = contexts.away_entry_id
  join public.pachanga_groups away_teams on away_teams.id = away_entries.team_id
  where competitions.slug = 'copa-barrios-iq-2027'
) ordered;

-- Twelve of the sixteen visible J1/J2 matches have a confirmed referee;
-- four intentionally remain unassigned because the policy is optional.
do $demo_assignments$
declare match_row record;
declare assignment_id uuid;
declare referee_number integer;
begin
  for match_row in
    select contexts.id, contexts.schedule_item_id,
      row_number() over(
        order by rounds.round_number, groups.group_order, items.pairing_key, contexts.id
      )::integer as ordinal
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
    join public.pachanga_competition_groups groups on groups.id = contexts.competition_group_id
    join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
    join public.pachanga_competitions competitions on competitions.id = contexts.competition_id
    where competitions.slug = 'copa-barrios-iq-2027'
    order by rounds.round_number, groups.group_order, items.pairing_key, contexts.id
  loop
    continue when match_row.ordinal > 12;
    referee_number := 1 + ((match_row.ordinal - 1) % 8);
    assignment_id := md5('demo-world-v2-5-referee-assignment-' || match_row.ordinal)::uuid;
    perform pg_temp.demo_v25_assignment_command(
      '64010000-0000-4000-8000-000000000001', assignment_id,
      'propose-' || match_row.ordinal, 'assignment.propose',
      jsonb_build_object(
        'refereeProfileId', md5('demo-world-v2-referee-profile-' || referee_number)::uuid,
        'sourceKind', 'competition_generated',
        'sourceId', match_row.schedule_item_id::text,
        'requesterKind', 'COMPETITION',
        'requesterId', (select id from public.pachanga_competitions where slug = 'copa-barrios-iq-2027'),
        'assignmentRole', 'MAIN_REFEREE',
        'responseDeadline', clock_timestamp() + interval '10 days',
        'feeMode', 'FREE', 'currency', 'EUR'
      )
    );
    perform pg_temp.demo_v25_assignment_command(
      md5('demo-world-v2-referee-user-' || referee_number)::uuid,
      assignment_id, 'accept-' || match_row.ordinal, 'assignment.accept'
    );
    perform pg_temp.demo_v25_assignment_command(
      '64010000-0000-4000-8000-000000000001',
      assignment_id, 'confirm-' || match_row.ordinal, 'assignment.confirm'
    );
  end loop;
end;
$demo_assignments$;

-- Operate J1 and J2 through R4C, with sparse real R4D/R5 stories.
do $demo_public_rounds$
declare match_row record;
declare result_row demo_v25_results%rowtype;
declare home_owner uuid;
declare away_owner uuid;
declare home_number integer;
declare away_number integer;
declare home_member uuid;
declare away_member uuid;
declare home_profile uuid;
declare away_profile uuid;
declare home_squad uuid;
declare away_squad uuid;
declare request_id uuid;
declare incident_id uuid;
declare suspension_id uuid;
declare assignment_id uuid;
declare referee_number integer;
declare event_id uuid;
declare sanction_id uuid;
declare original_start timestamptz;
declare original_end timestamptz;
declare squad_player_number integer;
declare squad_member uuid;
begin
  for match_row in
    select contexts.*, rounds.round_number, groups.group_order,
      items.pairing_key, items.scheduled_start as fixture_start,
      items.scheduled_end as fixture_end,
      row_number() over(
        order by rounds.round_number, groups.group_order, items.pairing_key, contexts.id
      )::integer as ordinal
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
    join public.pachanga_competition_groups groups on groups.id = contexts.competition_group_id
    join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
    join public.pachanga_competitions competitions on competitions.id = contexts.competition_id
    where competitions.slug = 'copa-barrios-iq-2027'
    order by rounds.round_number, groups.group_order, items.pairing_key, contexts.id
  loop
    continue when match_row.round_number > 2;
    select * into result_row from demo_v25_results where ordinal = match_row.ordinal;
    select groups.owner_id, substring(groups.team_code from 3)::integer
      into home_owner, home_number
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = match_row.home_entry_id;
    select groups.owner_id, substring(groups.team_code from 3)::integer
      into away_owner, away_number
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = match_row.away_entry_id;
    home_member := md5('demo-world-v2-5-roster-member-' || home_number || '-7')::uuid;
    away_member := md5('demo-world-v2-5-roster-member-' || away_number || '-7')::uuid;
    home_profile := md5('demo-world-v2-5-player-profile-' || home_number || '-7')::uuid;
    away_profile := md5('demo-world-v2-5-player-profile-' || away_number || '-7')::uuid;

    if match_row.ordinal = 3 then
      perform pg_temp.demo_v25_exception_command(
        match_row.id, home_owner, 'postponement-request', 'postponement.request',
        jsonb_build_object(
          'requestingEntryId', match_row.home_entry_id,
          'reasonCode', 'TEAM_CONFLICT',
          'reasonText', 'Disponibilidad deportiva documentada.',
          'evidenceRefs', jsonb_build_array('demo://tournament/postponement'),
          'publicSummary', 'El equipo local solicita aplazar el partido.'
        )
      );
      select requests.id into request_id
      from public.pachanga_competition_postponement_requests requests
      where requests.competition_match_context_id = match_row.id
      order by requests.server_sequence desc, requests.id desc limit 1;
      perform pg_temp.demo_v25_exception_command(
        match_row.id, away_owner, 'postponement-accept', 'postponement.respond',
        jsonb_build_object('requestId', request_id, 'responseKind', 'ACCEPT',
          'reasonCode', 'RIVAL_ACCEPTED', 'publicSummary', 'El rival acepta el aplazamiento.')
      );
      perform pg_temp.demo_v25_exception_command(
        match_row.id, '64010000-0000-4000-8000-000000000001',
        'postponement-approve', 'postponement.respond',
        jsonb_build_object('requestId', request_id, 'responseKind', 'APPROVE',
          'reasonCode', 'ORGANIZER_APPROVED', 'publicSummary', 'Aplazamiento aprobado.')
      );
      perform pg_temp.demo_v25_exception_command(
        match_row.id, '64010000-0000-4000-8000-000000000001',
        'postponement-reschedule', 'fixture.reschedule',
        jsonb_build_object(
          'scheduledStart', match_row.fixture_start + interval '3 days',
          'scheduledEnd', match_row.fixture_end + interval '3 days',
          'timezone', 'Europe/Madrid', 'venueStatus', 'LABEL',
          'venueLabel', 'Pista Copa ' || chr(64 + match_row.group_order),
          'reasonCode', 'NEW_DATE', 'publicSummary', 'Nueva fecha confirmada.'
        )
      );
      assignment_id := md5('demo-world-v2-5-referee-assignment-3')::uuid;
      referee_number := 3;
      perform pg_temp.demo_v25_assignment_command(
        md5('demo-world-v2-referee-user-' || referee_number)::uuid,
        assignment_id, 'reconfirm-3', 'assignment.reconfirm'
      );
    end if;

    if match_row.ordinal = 7 then
      original_start := match_row.scheduled_start;
      original_end := match_row.scheduled_end;
      update public.pachanga_competition_match_contexts contexts set
        scheduled_start = clock_timestamp() - interval '2 hours',
        scheduled_end = clock_timestamp() - interval '40 minutes'
      where contexts.id = match_row.id;
      perform pg_temp.demo_v25_exception_command(
        match_row.id,
        case when home_number < away_number then home_owner else away_owner end,
        'no-show-report', 'no_show.report',
        jsonb_build_object(
          'responsibleEntryId', case when home_number < away_number
            then match_row.away_entry_id else match_row.home_entry_id end,
          'reasonCode', 'NO_SHOW_REPORTED',
          'reasonText', 'El visitante no comparece tras el margen reglamentario.',
          'evidenceRefs', jsonb_build_array('demo://tournament/no-show'),
          'publicSummary', 'Incomparecencia en revisión.'
        )
      );
      select incidents.id into incident_id
      from public.pachanga_competition_no_show_incidents incidents
      where incidents.competition_match_context_id = match_row.id
      order by incidents.server_sequence desc, incidents.id desc limit 1;
      perform pg_temp.demo_v25_exception_command(
        match_row.id, '64010000-0000-4000-8000-000000000001',
        'no-show-confirm', 'no_show.confirm',
        jsonb_build_object('incidentId', incident_id,
          'reasonCode', 'NO_SHOW_CONFIRMED', 'reasonText', 'Evidencia validada.',
          'publicSummary', 'Incomparecencia confirmada.')
      );
      update public.pachanga_competition_match_contexts contexts set
        scheduled_start = original_start, scheduled_end = original_end
      where contexts.id = match_row.id;
      continue;
    end if;

    perform pg_temp.demo_v25_match_command(match_row.id, home_owner, 'home-squad-create', 'squad.create', jsonb_build_object('entryId', match_row.home_entry_id));
    select squads.id into home_squad from public.pachanga_competition_match_squads squads where squads.competition_match_context_id = match_row.id and squads.side = 'HOME';
    for squad_player_number in
      select candidates.player_number
      from generate_series(1, 8) candidates(player_number)
      where not private.pachanga_competition_player_sanction_applies_v1(
        match_row.competition_id,
        md5('demo-world-v2-5-player-profile-' || home_number || '-' || candidates.player_number)::uuid,
        match_row.canonical_match_id
      )
      order by candidates.player_number
      limit 7
    loop
      squad_member := md5('demo-world-v2-5-roster-member-' || home_number || '-' || squad_player_number)::uuid;
      perform pg_temp.demo_v25_match_command(
        match_row.id, home_owner, 'home-squad-member-' || squad_player_number,
        'squad.member.add', jsonb_build_object(
          'squadId', home_squad, 'rosterMemberId', squad_member,
          'memberRole', 'STARTER', 'shirtNumber', squad_player_number,
          'positionOrder', squad_player_number, 'isCaptain', squad_player_number = 7
        )
      );
    end loop;
    perform pg_temp.demo_v25_match_command(match_row.id, home_owner, 'home-squad-submit', 'squad.submit', jsonb_build_object('squadId', home_squad));
    perform pg_temp.demo_v25_match_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'home-squad-validate', 'squad.validate', jsonb_build_object('squadId', home_squad));
    perform pg_temp.demo_v25_match_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'home-squad-lock', 'squad.lock', jsonb_build_object('squadId', home_squad));

    perform pg_temp.demo_v25_match_command(match_row.id, away_owner, 'away-squad-create', 'squad.create', jsonb_build_object('entryId', match_row.away_entry_id));
    select squads.id into away_squad from public.pachanga_competition_match_squads squads where squads.competition_match_context_id = match_row.id and squads.side = 'AWAY';
    for squad_player_number in
      select candidates.player_number
      from generate_series(1, 8) candidates(player_number)
      where not private.pachanga_competition_player_sanction_applies_v1(
        match_row.competition_id,
        md5('demo-world-v2-5-player-profile-' || away_number || '-' || candidates.player_number)::uuid,
        match_row.canonical_match_id
      )
      order by candidates.player_number
      limit 7
    loop
      squad_member := md5('demo-world-v2-5-roster-member-' || away_number || '-' || squad_player_number)::uuid;
      perform pg_temp.demo_v25_match_command(
        match_row.id, away_owner, 'away-squad-member-' || squad_player_number,
        'squad.member.add', jsonb_build_object(
          'squadId', away_squad, 'rosterMemberId', squad_member,
          'memberRole', 'STARTER', 'shirtNumber', squad_player_number,
          'positionOrder', squad_player_number, 'isCaptain', squad_player_number = 7
        )
      );
    end loop;
    perform pg_temp.demo_v25_match_command(match_row.id, away_owner, 'away-squad-submit', 'squad.submit', jsonb_build_object('squadId', away_squad));
    perform pg_temp.demo_v25_match_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'away-squad-validate', 'squad.validate', jsonb_build_object('squadId', away_squad));
    perform pg_temp.demo_v25_match_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'away-squad-lock', 'squad.lock', jsonb_build_object('squadId', away_squad));

    select members.roster_member_id, members.player_profile_id
      into home_member, home_profile
    from public.pachanga_competition_match_squads squads
    join public.pachanga_competition_match_squad_members members
      on members.squad_revision_id = squads.current_revision_id
    where squads.id = home_squad
    order by members.is_captain desc, members.position_order desc, members.id
    limit 1;
    select members.roster_member_id, members.player_profile_id
      into away_member, away_profile
    from public.pachanga_competition_match_squads squads
    join public.pachanga_competition_match_squad_members members
      on members.squad_revision_id = squads.current_revision_id
    where squads.id = away_squad
    order by members.is_captain desc, members.position_order desc, members.id
    limit 1;

    perform pg_temp.demo_v25_match_command(match_row.id, home_owner, 'home-attendance', 'attendance.set', jsonb_build_object('entryId', match_row.home_entry_id, 'rosterMemberId', home_member, 'status', 'going'));
    perform pg_temp.demo_v25_match_command(match_row.id, away_owner, 'away-attendance', 'attendance.set', jsonb_build_object('entryId', match_row.away_entry_id, 'rosterMemberId', away_member, 'status', 'going'));
    perform pg_temp.demo_v25_match_command(match_row.id, home_owner, 'home-attendance-close', 'attendance.close', jsonb_build_object('entryId', match_row.home_entry_id));
    perform pg_temp.demo_v25_match_command(match_row.id, away_owner, 'away-attendance-close', 'attendance.close', jsonb_build_object('entryId', match_row.away_entry_id));
    perform pg_temp.demo_v25_match_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'match-ready', 'match.mark_ready');
    perform pg_temp.demo_v25_match_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'match-start', 'match.start');

    if match_row.ordinal = 11 then
      perform pg_temp.demo_v25_exception_command(
        match_row.id, home_owner, 'suspension-report', 'suspension.report',
        jsonb_build_object(
          'reportingEntryId', match_row.home_entry_id, 'reportedMinute', 41,
          'partialScoreHome', 0, 'partialScoreAway', 0,
          'reasonCode', 'SAFETY_STOP', 'reasonText', 'Tormenta eléctrica.',
          'evidenceRefs', jsonb_build_array('demo://tournament/suspension'),
          'publicSummary', 'Partido suspendido temporalmente.'
        )
      );
      select suspensions.id into suspension_id
      from public.pachanga_competition_match_suspensions suspensions
      where suspensions.competition_match_context_id = match_row.id
      order by suspensions.server_sequence desc, suspensions.id desc limit 1;
      perform pg_temp.demo_v25_exception_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'suspension-confirm', 'suspension.confirm', jsonb_build_object('suspensionId', suspension_id, 'reasonCode', 'SUSPENSION_CONFIRMED'));
      perform pg_temp.demo_v25_exception_command(
        match_row.id, '64010000-0000-4000-8000-000000000001',
        'suspension-schedule-resume', 'suspension.schedule_resume',
        jsonb_build_object(
          'suspensionId', suspension_id, 'resumeMinute', 41,
          'scheduledStart', match_row.fixture_start + interval '1 day',
          'scheduledEnd', match_row.fixture_end + interval '1 day',
          'timezone', 'Europe/Madrid', 'venueStatus', 'LABEL',
          'venueLabel', 'Pista Copa ' || chr(64 + match_row.group_order),
          'reasonCode', 'RESUMPTION_APPROVED', 'publicSummary', 'Reanudación confirmada.'
        )
      );
      perform pg_temp.demo_v25_exception_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'suspension-resume', 'suspension.resume', jsonb_build_object('suspensionId', suspension_id, 'reasonCode', 'MATCH_RESUMED', 'publicSummary', 'Partido reanudado.'));
    end if;

    perform pg_temp.demo_v25_match_command(match_row.id, '64010000-0000-4000-8000-000000000001', 'match-played', 'match.mark_played');

    if match_row.ordinal in (4, 8, 12, 16) then
      perform pg_temp.demo_v25_discipline_command(
        match_row.canonical_match_id,
        'card-' || match_row.ordinal,
        'event.record',
        jsonb_build_object(
          'playerProfileId', case when match_row.ordinal = 8 then away_profile else home_profile end,
          'cardTypeCode', case when match_row.ordinal = 8 then 'RED' else 'YELLOW' end,
          'context', 'in_match', 'minute', 18 + match_row.ordinal,
          'publicReasonCategory', case when match_row.ordinal = 8 then 'dismissal' else 'accumulation' end,
          'publicSummary', case when match_row.ordinal = 8 then 'Expulsión directa' else 'Amonestación' end
        )
      );
      if match_row.ordinal = 8 then
        select events.id into event_id
        from public.pachanga_competition_disciplinary_events events
        where events.creation_operation_id = md5('demo-world-v2-5-r5:card-8')::uuid;
        select sanctions.id into sanction_id
        from public.pachanga_competition_sanctions sanctions
        where sanctions.source_event_id = event_id
        order by sanctions.server_sequence desc, sanctions.id desc limit 1;
        perform pg_temp.demo_v25_discipline_command(
          sanction_id, 'sanction-red-8', 'sanction.decide',
          jsonb_build_object(
            'decisionOutcome', 'FIXED_SANCTION', 'units', 1,
            'publicReasonCategory', 'dismissal', 'publicSummary', 'Un partido de sanción',
            'ruleArticle', 'R6B.DEMO.RED',
            'privateReason', 'Decisión sintética motivada por expulsión directa.',
            'evidenceRefs', jsonb_build_array('demo://tournament/red-card-review')
          )
        );
      end if;
    end if;

    if match_row.ordinal = 14 then
      perform pg_temp.demo_v25_match_command(
        match_row.id, home_owner, 'result-submit', 'sporting_result.submit',
        jsonb_build_object('entryId', match_row.home_entry_id, 'scoreHome', 2, 'scoreAway', 2)
      );
      perform pg_temp.demo_v25_match_command(
        match_row.id, away_owner, 'result-dispute', 'sporting_result.dispute',
        jsonb_build_object('entryId', match_row.away_entry_id,
          'scoreHome', result_row.score_home, 'scoreAway', result_row.score_away,
          'reason', 'El acta arbitral refleja otro marcador.')
      );
      perform pg_temp.demo_v25_match_command(
        match_row.id, '64010000-0000-4000-8000-000000000001',
        'result-correct', 'official_result.publish',
        jsonb_build_object(
          'outcome', 'CORRECTED_EFFECTIVE_SCORE',
          'scoreHome', result_row.score_home, 'scoreAway', result_row.score_away,
          'reasonCode', 'result.dispute_resolved',
          'publicExplanation', 'Resultado corregido según el acta oficial.'
        )
      );
    else
      perform pg_temp.demo_v25_match_command(
        match_row.id, home_owner, 'result-submit', 'sporting_result.submit',
        jsonb_build_object('entryId', match_row.home_entry_id,
          'scoreHome', result_row.score_home, 'scoreAway', result_row.score_away)
      );
      perform pg_temp.demo_v25_match_command(
        match_row.id, away_owner, 'result-accept', 'sporting_result.accept',
        jsonb_build_object('entryId', match_row.away_entry_id)
      );
      perform pg_temp.demo_v25_match_command(
        match_row.id, '64010000-0000-4000-8000-000000000001',
        'result-official', 'official_result.publish',
        jsonb_build_object('outcome', 'MIRROR_SPORTING_RESULT',
          'reasonCode', 'demo.tournament.official',
          'publicExplanation', 'Resultado confirmado por ambos equipos.')
      );
    end if;
  end loop;
end;
$demo_public_rounds$;

-- Freeze a public-safe, identifier-free state after J2.
insert into simulation.demo_world_tournament_group_stage_public_snapshot(snapshot)
with target as (
  select competitions.id from public.pachanga_competitions competitions
  where competitions.slug = 'copa-barrios-iq-2027'
), ordered_matches as (
  select contexts.*, rounds.round_number, groups.group_order,
    row_number() over(partition by groups.id, rounds.id order by items.pairing_key, contexts.id)::integer as round_match_number,
    items.scheduled_start as fixture_start, items.venue_label as fixture_venue,
    substring(home_teams.team_code from 3)::integer as home_team_number,
    substring(away_teams.team_code from 3)::integer as away_team_number,
    decisions.effective_score_home, decisions.effective_score_away,
    case
      when exists (select 1 from public.pachanga_competition_no_show_incidents incidents where incidents.competition_match_context_id=contexts.id and incidents.status in ('confirmed','resolved')) then 'NO_SHOW'
      when exists (select 1 from public.pachanga_competition_match_suspensions suspensions where suspensions.competition_match_context_id=contexts.id and suspensions.status='resumed') then 'SUSPENDED_RESUMED'
      when exists (select 1 from public.pachanga_competition_postponement_requests requests where requests.competition_match_context_id=contexts.id and requests.status='approved') then 'POSTPONED_RESCHEDULED'
      when exists (select 1 from public.pachanga_competition_result_responses responses join public.pachanga_competition_sporting_results results on results.id=responses.sporting_result_id where results.competition_match_context_id=contexts.id and responses.response_kind='DISPUTE') then 'DISPUTED_CORRECTED'
      else 'NONE'
    end as incident_type,
    (select substring(profiles.slug from '([0-9]+)$')::integer
      from public.pachanga_referee_assignments assignments
      join public.pachanga_referee_profiles profiles on profiles.id=assignments.referee_profile_id
      where assignments.competition_match_context_id=contexts.id
        and assignments.status in ('confirmed','completed')
      order by assignments.server_sequence desc, assignments.id desc limit 1) referee_number,
    (select count(*)::integer from public.pachanga_competition_disciplinary_events events where events.canonical_match_id=contexts.canonical_match_id) discipline_events
  from target
  join public.pachanga_competition_match_contexts contexts on contexts.competition_id=target.id
  join public.pachanga_competition_rounds rounds on rounds.id=contexts.round_id
  join public.pachanga_competition_groups groups on groups.id=contexts.competition_group_id
  join public.pachanga_competition_schedule_items items on items.id=contexts.schedule_item_id
  join public.pachanga_competition_entries home_entries on home_entries.id=contexts.home_entry_id
  join public.pachanga_groups home_teams on home_teams.id=home_entries.team_id
  join public.pachanga_competition_entries away_entries on away_entries.id=contexts.away_entry_id
  join public.pachanga_groups away_teams on away_teams.id=away_entries.team_id
  left join public.pachanga_competition_match_sheets sheets on sheets.competition_match_context_id=contexts.id
  left join public.pachanga_competition_official_result_decisions decisions on decisions.id=sheets.active_official_decision_id
), public_matches as (
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'matchKey', 'G' || group_order || '-J' || round_number || '-M' || round_match_number,
    'groupNumber', group_order, 'roundNumber', round_number,
    'homeTeamNumber', home_team_number, 'awayTeamNumber', away_team_number,
    'scheduledStart', fixture_start, 'venueLabel', fixture_venue,
    'status', case when status='official' then 'OFFICIAL' else 'SCHEDULED' end,
    'score', case when effective_score_home is null then null else jsonb_build_object('home',effective_score_home,'away',effective_score_away) end,
    'incidentType', incident_type, 'refereeNumber', referee_number,
    'disciplineEvents', discipline_events
  )) order by round_number, group_order, round_match_number) value
  from ordered_matches
), public_standings as (
  select jsonb_agg(jsonb_build_object(
    'groupNumber', groups.group_order, 'position', rows.position,
    'teamNumber', substring(teams.team_code from 3)::integer,
    'played', rows.played, 'wins', rows.wins, 'draws', rows.draws, 'losses', rows.losses,
    'goalsFor', rows.goals_for, 'goalsAgainst', rows.goals_against,
    'goalDifference', rows.goal_difference, 'points', rows.effective_points,
    'qualificationZone', rows.position <= 2, 'status', 'PROVISIONAL',
    'revision', snapshots.source_revision,
    'criteria', snapshots.tie_break_criteria
  ) order by groups.group_order, rows.position, rows.entry_id) value
  from target
  join public.pachanga_competition_standing_states states on states.competition_id=target.id
  join public.pachanga_competition_standing_snapshots snapshots on snapshots.id=states.current_snapshot_id
  join public.pachanga_competition_groups groups on groups.id=states.competition_group_id
  join public.pachanga_competition_standing_rows rows on rows.standing_snapshot_id=snapshots.id
  join public.pachanga_competition_entries entries on entries.id=rows.entry_id
  join public.pachanga_groups teams on teams.id=entries.team_id
), public_discipline as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'teamNumber', substring(teams.team_code from 3)::integer,
    'playerLabel', revisions.public_summary,
    'cardType', revisions.card_type_code,
    'status', revisions.event_status
  ) order by events.server_sequence, events.id), '[]'::jsonb) value
  from target
  join public.pachanga_competition_disciplinary_events events on events.competition_id=target.id
  join public.pachanga_competition_disciplinary_event_revisions revisions on revisions.id=events.current_revision_id
  join public.pachanga_competition_entries entries on entries.id=events.entry_id
  join public.pachanga_groups teams on teams.id=entries.team_id
), public_sanctions as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'teamNumber', substring(teams.team_code from 3)::integer,
    'status', sanctions.status, 'remainingUnits', sanctions.remaining_units,
    'unitType', sanctions.unit_type, 'publicSummary', revisions.public_summary
  ) order by sanctions.server_sequence, sanctions.id), '[]'::jsonb) value
  from target
  join public.pachanga_competition_sanctions sanctions on sanctions.competition_id=target.id
  join public.pachanga_competition_sanction_revisions revisions on revisions.id=sanctions.current_revision_id
  join public.pachanga_player_profiles profiles on profiles.id=sanctions.player_profile_id
  join public.pachanga_groups teams on teams.id=profiles.source_group_id
)
select jsonb_build_object(
  'currentRound', 2, 'roundCount', 3, 'groupCount', 4, 'fixtureCount', 24,
  'officialMatches', (select count(*) from ordered_matches where status='official'),
  'scheduledMatches', (select count(*) from ordered_matches where status='scheduled'),
  'matches', public_matches.value, 'standings', public_standings.value,
  'discipline', public_discipline.value, 'sanctions', public_sanctions.value,
  'referees', jsonb_build_object(
    'confirmedMatches', (select count(*) from ordered_matches where referee_number is not null),
    'unassignedMatches', (select count(*) from ordered_matches where referee_number is null)
  ),
  'incidents', jsonb_build_object(
    'postponedRescheduled', (select count(*) from ordered_matches where incident_type='POSTPONED_RESCHEDULED'),
    'noShow', (select count(*) from ordered_matches where incident_type='NO_SHOW'),
    'suspendedResumed', (select count(*) from ordered_matches where incident_type='SUSPENDED_RESUMED'),
    'disputedCorrected', (select count(*) from ordered_matches where incident_type='DISPUTED_CORRECTED')
  ),
  'qualificationStatus', 'PROVISIONAL', 'remoteWrites', 0
)
from public_matches, public_standings, public_discipline, public_sanctions;

-- Complete J3 internally through the same R4C result/decision authority.
do $demo_final_round$
declare match_row record;
declare result_row demo_v25_results%rowtype;
declare home_owner uuid;
declare away_owner uuid;
begin
  for match_row in
    select contexts.*, rounds.round_number, groups.group_order, items.pairing_key,
      row_number() over(
        order by rounds.round_number, groups.group_order, items.pairing_key, contexts.id
      )::integer as ordinal
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_rounds rounds on rounds.id=contexts.round_id
    join public.pachanga_competition_groups groups on groups.id=contexts.competition_group_id
    join public.pachanga_competition_schedule_items items on items.id=contexts.schedule_item_id
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='copa-barrios-iq-2027'
    order by rounds.round_number, groups.group_order, items.pairing_key, contexts.id
  loop
    continue when match_row.round_number <> 3;
    select * into result_row from demo_v25_results where ordinal=match_row.ordinal;
    select groups.owner_id into home_owner
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id=entries.team_id
    where entries.id=match_row.home_entry_id;
    select groups.owner_id into away_owner
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id=entries.team_id
    where entries.id=match_row.away_entry_id;
    update public.pachanga_competition_match_contexts contexts set
      status='played', revision=contexts.revision+1,
      server_sequence=nextval('private.pachanga_competition_sequence'),
      updated_at=clock_timestamp()
    where contexts.id=match_row.id;
    insert into public.pachanga_competition_match_sheets(
      canonical_match_id, competition_match_context_id, created_by
    ) values (match_row.canonical_match_id, match_row.id, '64010000-0000-4000-8000-000000000001');
    perform pg_temp.demo_v25_match_command(
      match_row.id, home_owner, 'result-submit', 'sporting_result.submit',
      jsonb_build_object('entryId', match_row.home_entry_id,
        'scoreHome', result_row.score_home, 'scoreAway', result_row.score_away)
    );
    perform pg_temp.demo_v25_match_command(
      match_row.id, away_owner, 'result-accept', 'sporting_result.accept',
      jsonb_build_object('entryId', match_row.away_entry_id)
    );
    perform pg_temp.demo_v25_match_command(
      match_row.id, '64010000-0000-4000-8000-000000000001',
      'result-official', 'official_result.publish',
      jsonb_build_object('outcome','MIRROR_SPORTING_RESULT',
        'reasonCode','demo.tournament.official',
        'publicExplanation','Resultado confirmado por ambos equipos.')
    );
  end loop;
end;
$demo_final_round$;

select pg_temp.demo_v25_group_command('qualification-rebuild', 'qualification.rebuild');
select pg_temp.demo_v25_group_command('qualification-validate', 'qualification.validate');
select pg_temp.demo_v25_group_command('qualification-publish', 'qualification.publish');
select pg_temp.demo_v25_group_command('bracket-create', 'bracket_template.create');
select pg_temp.demo_v25_group_command('bracket-publish', 'bracket_template.publish');

insert into simulation.demo_world_tournament_group_stage_final_proof(proof)
with target as (
  select competitions.id from public.pachanga_competitions competitions
  where competitions.slug='copa-barrios-iq-2027'
), state as (
  select states.* from target
  join public.pachanga_tournament_group_stage_states states on states.competition_id=target.id
), qualification as (
  select snapshots.* from state
  join public.pachanga_tournament_qualification_snapshots snapshots
    on snapshots.id=state.current_qualification_snapshot_id
), bracket as (
  select templates.* from state
  join public.pachanga_tournament_bracket_templates templates
    on templates.id=state.current_bracket_template_id
), qualification_rows as (
  select jsonb_agg(jsonb_build_object(
    'teamNumber', substring(teams.team_code from 3)::integer,
    'groupNumber', groups.group_order, 'groupPosition', rows.group_position,
    'crossGroupRank', rows.cross_group_rank, 'outcome', rows.outcome,
    'targetBracketSlot', rows.target_bracket_slot
  ) order by groups.group_order, rows.group_position, rows.entry_id) value
  from qualification
  join public.pachanga_tournament_qualification_rows rows on rows.qualification_snapshot_id=qualification.id
  join public.pachanga_competition_groups groups on groups.id=rows.competition_group_id
  join public.pachanga_competition_entries entries on entries.id=rows.entry_id
  join public.pachanga_groups teams on teams.id=entries.team_id
), final_standings as (
  select jsonb_agg(jsonb_build_object(
    'groupNumber', groups.group_order, 'position', rows.position,
    'teamNumber', substring(teams.team_code from 3)::integer,
    'played', rows.played, 'wins', rows.wins, 'draws', rows.draws, 'losses', rows.losses,
    'goalsFor', rows.goals_for, 'goalsAgainst', rows.goals_against,
    'goalDifference', rows.goal_difference, 'points', rows.effective_points
  ) order by groups.group_order, rows.position, rows.entry_id) value
  from target
  join public.pachanga_competition_standing_states states on states.competition_id=target.id
  join public.pachanga_competition_standing_snapshots snapshots on snapshots.id=states.current_snapshot_id
  join public.pachanga_competition_groups groups on groups.id=states.competition_group_id
  join public.pachanga_competition_standing_rows rows on rows.standing_snapshot_id=snapshots.id
  join public.pachanga_competition_entries entries on entries.id=rows.entry_id
  join public.pachanga_groups teams on teams.id=entries.team_id
), bracket_slots as (
  select jsonb_agg(jsonb_build_object(
    'slotKey', slots.slot_key, 'matchNumber', slots.match_number,
    'side', slots.side, 'sourceKind', slots.source_kind,
    'sourceGroupNumber', groups.group_order, 'sourcePosition', slots.source_position,
    'teamNumber', substring(teams.team_code from 3)::integer,
    'status', slots.status
  ) order by slots.bracket_order) value
  from bracket
  join public.pachanga_tournament_bracket_slots slots on slots.bracket_template_id=bracket.id
  left join public.pachanga_competition_groups groups on groups.id=slots.source_group_id
  left join public.pachanga_competition_entries entries on entries.id=slots.resolved_entry_id
  left join public.pachanga_groups teams on teams.id=entries.team_id
)
select jsonb_build_object(
  'groupStageStatus', state.status, 'groupCount', state.group_count,
  'fixtureCount', state.fixture_count,
  'canonicalMatches', (select count(*) from target join public.pachanga_competition_match_contexts contexts on contexts.competition_id=target.id),
  'officialMatches', (select count(*) from target join public.pachanga_competition_match_contexts contexts on contexts.competition_id=target.id where contexts.status='official'),
  'standingSnapshots', (select count(*) from target join public.pachanga_competition_standing_states states on states.competition_id=target.id where states.current_snapshot_id is not null),
  'qualificationStatus', qualification.status,
  'qualificationChecksum', qualification.checksum,
  'qualifiers', (select count(*) from public.pachanga_tournament_qualification_rows rows where rows.qualification_snapshot_id=qualification.id and rows.outcome in ('DIRECT_QUALIFIER','EXTRA_QUALIFIER')),
  'eliminated', (select count(*) from public.pachanga_tournament_qualification_rows rows where rows.qualification_snapshot_id=qualification.id and rows.outcome='ELIMINATED'),
  'qualificationRows', qualification_rows.value,
  'finalStandings', final_standings.value,
  'bracketStatus', bracket.status, 'bracketSize', bracket.bracket_size,
  'bracketSlots', bracket_slots.value,
  'knockoutMatches', 0, 'bracketProgressionEnabled', false,
  'remoteWrites', 0
)
from state, qualification, bracket, qualification_rows, final_standings, bracket_slots;

do $demo_assertions$
declare public_snapshot jsonb;
declare final_proof jsonb;
begin
  select snapshot into public_snapshot from simulation.demo_world_tournament_group_stage_public_snapshot;
  select proof into final_proof from simulation.demo_world_tournament_group_stage_final_proof;
  if (public_snapshot ->> 'officialMatches')::integer <> 16
     or (public_snapshot ->> 'scheduledMatches')::integer <> 8
     or jsonb_array_length(public_snapshot -> 'standings') <> 16
     or jsonb_array_length(public_snapshot -> 'discipline') <> 4
     or jsonb_array_length(public_snapshot -> 'sanctions') < 1
     or (public_snapshot #>> '{incidents,postponedRescheduled}')::integer <> 1
     or (public_snapshot #>> '{incidents,noShow}')::integer <> 1
     or (public_snapshot #>> '{incidents,suspendedResumed}')::integer <> 1
     or (public_snapshot #>> '{incidents,disputedCorrected}')::integer <> 1 then
    raise exception 'DEMO_WORLD_V2_5_PUBLIC_SNAPSHOT_INVALID:%', public_snapshot;
  end if;
  if (final_proof ->> 'canonicalMatches')::integer <> 24
     or (final_proof ->> 'officialMatches')::integer <> 24
     or (final_proof ->> 'standingSnapshots')::integer <> 4
     or (final_proof ->> 'qualifiers')::integer <> 8
     or (final_proof ->> 'eliminated')::integer <> 8
     or (final_proof ->> 'qualificationStatus') <> 'PUBLISHED'
     or (final_proof ->> 'bracketStatus') <> 'PUBLISHED'
     or jsonb_array_length(final_proof -> 'bracketSlots') <> 8
     or (final_proof ->> 'knockoutMatches')::integer <> 0
     or (final_proof ->> 'bracketProgressionEnabled')::boolean then
    raise exception 'DEMO_WORLD_V2_5_FINAL_PROOF_INVALID:%', final_proof;
  end if;
end;
$demo_assertions$;

select 'DEMO_WORLD_V2_5_TOURNAMENT_GROUP_STAGE_REPORT|' || jsonb_build_object(
  'publicOfficialMatches', (select (snapshot ->> 'officialMatches')::integer from simulation.demo_world_tournament_group_stage_public_snapshot),
  'publicScheduledMatches', (select (snapshot ->> 'scheduledMatches')::integer from simulation.demo_world_tournament_group_stage_public_snapshot),
  'finalOfficialMatches', (select (proof ->> 'officialMatches')::integer from simulation.demo_world_tournament_group_stage_final_proof),
  'qualifiers', (select (proof ->> 'qualifiers')::integer from simulation.demo_world_tournament_group_stage_final_proof),
  'bracketSlots', (select jsonb_array_length(proof -> 'bracketSlots') from simulation.demo_world_tournament_group_stage_final_proof),
  'knockoutMatches', 0, 'remoteWrites', 0
)::text;

\if :{?DEMO_WORLD_V2_PERSIST}
commit;
\else
rollback;
\endif
