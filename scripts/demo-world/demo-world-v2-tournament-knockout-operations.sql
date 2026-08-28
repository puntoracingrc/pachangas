\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '240s';

begin;

create schema if not exists simulation;
create table if not exists simulation.demo_world_tournament_knockout_public_snapshot (
  snapshot jsonb not null
);
create table if not exists simulation.demo_world_tournament_knockout_proof (
  proof jsonb not null
);
truncate simulation.demo_world_tournament_knockout_public_snapshot;
truncate simulation.demo_world_tournament_knockout_proof;

create temporary table demo_v26_integrity_baseline(
  key text primary key,
  value bigint not null
);
insert into demo_v26_integrity_baseline values
  ('ratingSnapshots', (select count(*) from public.pachanga_player_rating_snapshots)),
  ('rewardGrants', (select count(*) from public.pachanga_reward_grants)),
  ('conductReports', (select count(*) from private.pachanga_conduct_reports)),
  ('billingEvents', (select count(*) from public.pachanga_stripe_webhook_events));

create temporary table demo_v26_story_state(
  key text primary key,
  value jsonb not null
);
insert into demo_v26_story_state values (
  'groupStandingsChecksum',
  jsonb_build_object('value', encode(extensions.digest(convert_to(
    coalesce((select string_agg(snapshots.content_checksum, '|' order by snapshots.id)
      from public.pachanga_competition_standing_snapshots snapshots
      join public.pachanga_competition_standing_states states
        on states.current_snapshot_id = snapshots.id
      join public.pachanga_competitions competitions
        on competitions.id = states.competition_id
      where competitions.slug = 'copa-barrios-iq-2027'), ''),
    'UTF8'
  ), 'sha256'), 'hex'))
);

create or replace function pg_temp.demo_v26_actor(target_user_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.demo_v26_team_number(target_entry_id uuid)
returns integer language sql stable as $$
  select substring(groups.team_code from 3)::integer
  from public.pachanga_competition_entries entries
  join public.pachanga_groups groups on groups.id = entries.team_id
  where entries.id = target_entry_id
$$;

create or replace function pg_temp.demo_v26_bracket_command(
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare target_competition_id uuid;
declare current_revision bigint;
begin
  select competitions.id into target_competition_id
  from public.pachanga_competitions competitions
  where competitions.slug = 'copa-barrios-iq-2027';
  select coalesce(
    (select brackets.revision from public.pachanga_tournament_brackets brackets
      where brackets.competition_id = target_competition_id),
    (select states.revision from public.pachanga_tournament_group_stage_states states
      where states.competition_id = target_competition_id)
  ) into current_revision;
  perform pg_temp.demo_v26_actor('64010000-0000-4000-8000-000000000001');
  return public.command_pachanga_tournament_knockout_v1(
    md5('demo-world-v2-6-r6c:' || target_operation_key)::uuid,
    target_competition_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.6","serviceWorkerVersion":"demo-world-v2.6","installedMode":"simulation","surface":"demo_world_v2_tournament_knockout"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v26_match_command(
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
  perform pg_temp.demo_v26_actor(target_actor_id);
  return public.command_pachanga_league_match_operations_v1(
    md5('demo-world-v2-6-r4c:' || target_context_id || ':' || target_operation_key)::uuid,
    target_context_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.6","serviceWorkerVersion":"demo-world-v2.6","installedMode":"simulation","surface":"demo_world_v2_tournament_knockout"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v26_exception_command(
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
  perform pg_temp.demo_v26_actor(target_actor_id);
  return public.command_pachanga_league_operational_exceptions_v1(
    md5('demo-world-v2-6-r4d:' || target_context_id || ':' || target_operation_key)::uuid,
    target_context_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.6","serviceWorkerVersion":"demo-world-v2.6","installedMode":"simulation","surface":"demo_world_v2_tournament_knockout"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v26_assignment_command(
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
  perform pg_temp.demo_v26_actor(target_actor_id);
  return public.command_pachanga_referee_assignment_beta_v1(
    md5('demo-world-v2-6-referee:' || target_operation_key)::uuid,
    target_assignment_id,
    coalesce(current_revision, 0),
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.6","serviceWorkerVersion":"demo-world-v2.6","installedMode":"simulation","surface":"demo_world_v2_tournament_knockout"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v26_discipline_command(
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
  perform pg_temp.demo_v26_actor('64010000-0000-4000-8000-000000000001');
  return public.command_pachanga_competition_discipline_v1(
    md5('demo-world-v2-6-r5:' || target_operation_key)::uuid,
    competition_id,
    target_aggregate_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.6","serviceWorkerVersion":"demo-world-v2.6","installedMode":"simulation","surface":"demo_world_v2_tournament_knockout"}'::jsonb
  );
end;
$$;

-- Demo V2.6 is the synthetic published contract for an eight-team bracket
-- with a third-place match. The production authoring surface remains frozen;
-- this local-only seed adjusts its immutable RuleRevision before activation.
set local session_replication_role = replica;
update public.pachanga_competition_rule_revisions revisions set
  rule_document = jsonb_set(
    revisions.rule_document,
    '{knockoutPolicy,thirdPlaceMatchEnabled}',
    'true'::jsonb,
    true
  ),
  checksum = encode(extensions.digest(convert_to(
    jsonb_set(
      revisions.rule_document,
      '{knockoutPolicy,thirdPlaceMatchEnabled}',
      'true'::jsonb,
      true
    )::text,
    'UTF8'
  ), 'sha256'), 'hex')
where revisions.id = (
  select states.rule_revision_id
  from public.pachanga_tournament_group_stage_states states
  join public.pachanga_competitions competitions on competitions.id = states.competition_id
  where competitions.slug = 'copa-barrios-iq-2027'
);
set local session_replication_role = origin;

select pg_temp.demo_v26_actor('64010000-0000-4000-8000-000000000090');
select public.command_pachanga_tournament_knockout_platform_v1(
  md5('demo-world-v2-6-r6c-flags')::uuid,
  '00000000-0000-0000-0000-00000000c6c1',
  (select settings.revision
    from private.pachanga_competition_foundation_settings settings
    where settings.singleton),
  'tournament.knockout.flags.set',
  '{"knockoutFoundationEnabled":true,"knockoutMatchGenerationEnabled":true,"bracketProgressionEnabled":true,"extraTimeEnabled":true,"penaltyShootoutEnabled":true,"thirdPlaceEnabled":true,"completionEnabled":true,"reason":"Demo World V2.6 Full Tournament parity"}'::jsonb,
  '{"clientVersion":"demo-world-v2.6","serviceWorkerVersion":"demo-world-v2.6","installedMode":"simulation","surface":"demo_world_v2_tournament_knockout"}'::jsonb
);

-- Carry one real active group-stage sanction into the knockout phase. The
-- player is not added to a later squad while the sanction applies.
do $demo_v26_discipline$
declare source_match_id uuid;
declare event_id uuid;
declare sanction_id uuid;
begin
  select contexts.canonical_match_id into source_match_id
  from public.pachanga_competition_match_contexts contexts
  join public.pachanga_competition_entries home_entries on home_entries.id = contexts.home_entry_id
  join public.pachanga_groups home_teams on home_teams.id = home_entries.team_id
  join public.pachanga_competition_entries away_entries on away_entries.id = contexts.away_entry_id
  join public.pachanga_groups away_teams on away_teams.id = away_entries.team_id
  join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
  where contexts.competition_id = (
      select id from public.pachanga_competitions where slug = 'copa-barrios-iq-2027'
    )
    and 'DW00004' in (home_teams.team_code, away_teams.team_code)
    and exists (
      select 1
      from public.pachanga_competition_match_squads squads
      join public.pachanga_competition_match_squad_members members
        on members.squad_revision_id = squads.current_revision_id
      where squads.competition_match_context_id = contexts.id
        and members.player_profile_id = md5('demo-world-v2-5-player-profile-4-1')::uuid
    )
  order by rounds.round_number desc, contexts.server_sequence desc, contexts.id desc
  limit 1;
  perform pg_temp.demo_v26_discipline_command(
    source_match_id,
    'knockout-carry-red-team-4',
    'event.record',
    jsonb_build_object(
      'playerProfileId', md5('demo-world-v2-5-player-profile-4-1')::uuid,
      'cardTypeCode', 'RED',
      'context', 'post_match',
      'minute', 70,
      'publicReasonCategory', 'dismissal',
      'publicSummary', 'Sanción vigente para el primer cruce eliminatorio'
    )
  );
  select events.id into event_id
  from public.pachanga_competition_disciplinary_events events
  where events.creation_operation_id = md5('demo-world-v2-6-r5:knockout-carry-red-team-4')::uuid;
  select sanctions.id into sanction_id
  from public.pachanga_competition_sanctions sanctions
  where sanctions.source_event_id = event_id
  order by sanctions.server_sequence desc, sanctions.id desc
  limit 1;
  perform pg_temp.demo_v26_discipline_command(
    sanction_id,
    'knockout-carry-sanction-team-4',
    'sanction.decide',
    jsonb_build_object(
      'decisionOutcome', 'FIXED_SANCTION',
      'units', 1,
      'publicReasonCategory', 'dismissal',
      'publicSummary', 'Un partido de sanción',
      'ruleArticle', 'R6C.DEMO.CARRY',
      'privateReason', 'Carry sintético de una sanción activa desde la fase de grupos.',
      'evidenceRefs', jsonb_build_array('demo://tournament/knockout-discipline-carry')
    )
  );
end;
$demo_v26_discipline$;

select pg_temp.demo_v26_bracket_command(
  'activate', 'bracket.activate',
  '{"reason":"Activar cuadro eliminatorio canónico Demo World V2.6"}'::jsonb
);

do $demo_v26_reservations$
declare node_row record;
declare starts_at timestamptz;
begin
  for node_row in
    select nodes.id, nodes.round_code, nodes.round_order, nodes.node_order
    from public.pachanga_tournament_bracket_nodes nodes
    join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
    join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
    where competitions.slug = 'copa-barrios-iq-2027'
    order by nodes.round_order, nodes.node_order
  loop
    starts_at := '2027-06-01T18:00:00+02:00'::timestamptz
      + make_interval(days => (node_row.round_order - 1) * 7, hours => (node_row.node_order - 1) * 2);
    perform pg_temp.demo_v26_bracket_command(
      'reserve-' || lower(node_row.round_code) || '-' || node_row.node_order,
      'bracket.reserve_slot',
      jsonb_build_object(
        'nodeId', node_row.id,
        'startsAt', starts_at,
        'endsAt', starts_at + interval '90 minutes',
        'timezone', 'Europe/Madrid',
        'venueLabel', 'Estadi Copa IQ Barcelona · ' || replace(initcap(lower(node_row.round_code)), '_', ' '),
        'resourceKey', 'demo-v26-' || lower(node_row.round_code) || '-' || node_row.node_order,
        'reason', 'Reserva canónica de la fase eliminatoria'
      )
    );
  end loop;
end;
$demo_v26_reservations$;

do $demo_v26_generate_quarters$
declare node_row record;
begin
  for node_row in
    select nodes.id, nodes.node_order
    from public.pachanga_tournament_bracket_nodes nodes
    join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
    join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
    where competitions.slug = 'copa-barrios-iq-2027'
      and nodes.round_code = 'QUARTERFINAL'
    order by nodes.node_order
  loop
    perform pg_temp.demo_v26_bracket_command(
      'generate-quarter-' || node_row.node_order,
      'bracket.node.generate_match',
      jsonb_build_object('nodeId', node_row.id, 'reason', 'Publicar cuarto de final')
    );
  end loop;
end;
$demo_v26_generate_quarters$;

create or replace function pg_temp.demo_v26_play_node(
  target_node_id uuid,
  target_resolution_kind text,
  target_story_key text
)
returns uuid language plpgsql as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare home_owner uuid;
declare away_owner uuid;
declare score_home integer;
declare score_away integer;
declare knockout_evidence jsonb;
declare decision_id uuid;
begin
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id;
  if node_row.canonical_match_id is null then
    perform pg_temp.demo_v26_bracket_command(
      'generate-' || target_story_key,
      'bracket.node.generate_match',
      jsonb_build_object('nodeId', node_row.id, 'reason', 'Generar cruce ' || target_story_key)
    );
    select * into node_row
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.id = target_node_id;
  end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = node_row.canonical_match_id
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  select groups.owner_id into home_owner
  from public.pachanga_competition_entries entries
  join public.pachanga_groups groups on groups.id = entries.team_id
  where entries.id = context_row.home_entry_id;
  select groups.owner_id into away_owner
  from public.pachanga_competition_entries entries
  join public.pachanga_groups groups on groups.id = entries.team_id
  where entries.id = context_row.away_entry_id;

  if upper(target_resolution_kind) = 'REGULATION' then
    score_home := 2;
    score_away := 0;
    knockout_evidence := jsonb_build_object(
      'scoreAfterRegulationHome', 2,
      'scoreAfterRegulationAway', 0,
      'extraTimePlayed', false
    );
  elsif upper(target_resolution_kind) = 'EXTRA_TIME' then
    score_home := 2;
    score_away := 1;
    knockout_evidence := jsonb_build_object(
      'scoreAfterRegulationHome', 1,
      'scoreAfterRegulationAway', 1,
      'extraTimePlayed', true,
      'scoreAfterExtraTimeHome', 2,
      'scoreAfterExtraTimeAway', 1
    );
  elsif upper(target_resolution_kind) = 'PENALTY_SHOOTOUT' then
    score_home := 1;
    score_away := 1;
    knockout_evidence := jsonb_build_object(
      'scoreAfterRegulationHome', 1,
      'scoreAfterRegulationAway', 1,
      'extraTimePlayed', true,
      'scoreAfterExtraTimeHome', 1,
      'scoreAfterExtraTimeAway', 1,
      'shootoutHome', 5,
      'shootoutAway', 4
    );
  else
    raise exception 'DEMO_WORLD_V2_6_RESOLUTION_KIND_INVALID:%', target_resolution_kind;
  end if;

  update public.pachanga_competition_match_contexts contexts set
    status = 'played',
    revision = contexts.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where contexts.id = context_row.id;
  insert into public.pachanga_competition_match_sheets(
    canonical_match_id, competition_match_context_id, created_by
  ) values (
    context_row.canonical_match_id,
    context_row.id,
    '64010000-0000-4000-8000-000000000001'
  );
  perform pg_temp.demo_v26_match_command(
    context_row.id,
    home_owner,
    target_story_key || '-submit',
    'sporting_result.submit',
    jsonb_build_object(
      'entryId', context_row.home_entry_id,
      'scoreHome', score_home,
      'scoreAway', score_away
    )
  );
  perform pg_temp.demo_v26_match_command(
    context_row.id,
    away_owner,
    target_story_key || '-accept',
    'sporting_result.accept',
    jsonb_build_object('entryId', context_row.away_entry_id)
  );
  perform pg_temp.demo_v26_match_command(
    context_row.id,
    '64010000-0000-4000-8000-000000000001',
    target_story_key || '-official',
    'official_result.publish',
    jsonb_build_object(
      'outcome', 'MIRROR_SPORTING_RESULT',
      'reasonCode', 'demo.tournament.knockout.official',
      'publicExplanation', 'Resultado eliminatorio confirmado.',
      'privateEvidence', jsonb_build_object('knockout', knockout_evidence)
    )
  );
  select sheets.active_official_decision_id into decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = context_row.id;
  perform pg_temp.demo_v26_bracket_command(
    target_story_key || '-advance',
    'bracket.result.advance',
    jsonb_build_object(
      'officialDecisionId', decision_id,
      'reason', 'Aplicar resultado oficial R4C al cuadro'
    )
  );
  return decision_id;
end;
$$;

create or replace function pg_temp.demo_v26_no_show_node(
  target_node_id uuid,
  target_story_key text
)
returns uuid language plpgsql as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare home_owner uuid;
declare original_start timestamptz;
declare original_end timestamptz;
declare incident_id uuid;
declare decision_id uuid;
begin
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = node_row.canonical_match_id
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  select groups.owner_id into home_owner
  from public.pachanga_competition_entries entries
  join public.pachanga_groups groups on groups.id = entries.team_id
  where entries.id = context_row.home_entry_id;
  original_start := context_row.scheduled_start;
  original_end := context_row.scheduled_end;
  update public.pachanga_competition_match_contexts contexts set
    status = 'ready',
    scheduled_start = clock_timestamp() - interval '2 hours',
    scheduled_end = clock_timestamp() - interval '40 minutes',
    revision = contexts.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where contexts.id = context_row.id;
  perform pg_temp.demo_v26_exception_command(
    context_row.id,
    home_owner,
    target_story_key || '-report',
    'no_show.report',
    jsonb_build_object(
      'responsibleEntryId', context_row.away_entry_id,
      'reasonCode', 'NO_SHOW_REPORTED',
      'reasonText', 'El rival no comparece tras el margen reglamentario.',
      'evidenceRefs', jsonb_build_array('demo://tournament/knockout-no-show'),
      'publicSummary', 'Incomparecencia en revisión.'
    )
  );
  select incidents.id into incident_id
  from public.pachanga_competition_no_show_incidents incidents
  where incidents.competition_match_context_id = context_row.id
  order by incidents.server_sequence desc, incidents.id desc
  limit 1;
  perform pg_temp.demo_v26_exception_command(
    context_row.id,
    '64010000-0000-4000-8000-000000000001',
    target_story_key || '-confirm',
    'no_show.confirm',
    jsonb_build_object(
      'incidentId', incident_id,
      'reasonCode', 'NO_SHOW_CONFIRMED',
      'reasonText', 'La organización valida la evidencia.',
      'publicSummary', 'Incomparecencia confirmada.'
    )
  );
  update public.pachanga_competition_match_contexts contexts set
    scheduled_start = original_start,
    scheduled_end = original_end
  where contexts.id = context_row.id;
  select sheets.active_official_decision_id into decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = context_row.id;
  perform pg_temp.demo_v26_bracket_command(
    target_story_key || '-advance',
    'bracket.result.advance',
    jsonb_build_object(
      'officialDecisionId', decision_id,
      'reason', 'Aplicar no-show R4D confirmado al cuadro'
    )
  );
  return decision_id;
end;
$$;

select pg_temp.demo_v26_play_node(nodes.id, 'REGULATION', 'quarter-1-regulation')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'QUARTERFINAL'
  and nodes.node_order = 1;

select pg_temp.demo_v26_play_node(nodes.id, 'EXTRA_TIME', 'quarter-2-extra-time')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'QUARTERFINAL'
  and nodes.node_order = 2;

select pg_temp.demo_v26_play_node(nodes.id, 'PENALTY_SHOOTOUT', 'quarter-3-shootout')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'QUARTERFINAL'
  and nodes.node_order = 3;

select pg_temp.demo_v26_no_show_node(nodes.id, 'quarter-4-no-show')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'QUARTERFINAL'
  and nodes.node_order = 4;

-- Correct QF1 after its semifinal has been generated but before it starts.
-- R6C must retire the old semifinal match and generate a replacement without
-- mutating either historical CanonicalMatch.
do $demo_v26_correction$
declare quarter_node public.pachanga_tournament_bracket_nodes%rowtype;
declare quarter_context public.pachanga_competition_match_contexts%rowtype;
declare semifinal_node public.pachanga_tournament_bracket_nodes%rowtype;
declare old_match_id uuid;
declare old_context_id uuid;
declare corrected_decision_id uuid;
begin
  select nodes.* into quarter_node
  from public.pachanga_tournament_bracket_nodes nodes
  join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
  join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
  where competitions.slug = 'copa-barrios-iq-2027'
    and nodes.round_code = 'QUARTERFINAL'
    and nodes.node_order = 1;
  select contexts.* into quarter_context
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = quarter_node.canonical_match_id
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  select nodes.* into semifinal_node
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.bracket_id = quarter_node.bracket_id
    and nodes.round_code = 'SEMIFINAL'
    and nodes.node_order = 1;
  old_match_id := semifinal_node.canonical_match_id;
  select contexts.id into old_context_id
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id = old_match_id
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;

  perform pg_temp.demo_v26_match_command(
    quarter_context.id,
    '64010000-0000-4000-8000-000000000001',
    'quarter-1-correction',
    'official_result.supersede',
    jsonb_build_object(
      'outcome', 'CORRECTED_EFFECTIVE_SCORE',
      'scoreHome', 0,
      'scoreAway', 2,
      'reasonCode', 'demo.tournament.knockout.correction',
      'publicExplanation', 'El acta oficial corrige el ganador del cuarto.',
      'privateEvidence', jsonb_build_object(
        'knockout', jsonb_build_object(
          'scoreAfterRegulationHome', 0,
          'scoreAfterRegulationAway', 2,
          'extraTimePlayed', false
        ),
        'privateReason', 'Corrección sintética previa al inicio de la semifinal.'
      )
    )
  );
  select sheets.active_official_decision_id into corrected_decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = quarter_context.id;
  perform pg_temp.demo_v26_bracket_command(
    'quarter-1-correction-advance',
    'bracket.result.advance',
    jsonb_build_object(
      'officialDecisionId', corrected_decision_id,
      'reason', 'Recalcular semifinal tras la corrección oficial'
    )
  );

  select nodes.* into semifinal_node
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.bracket_id = quarter_node.bracket_id
    and nodes.round_code = 'SEMIFINAL'
    and nodes.node_order = 1;
  if semifinal_node.canonical_match_id is not distinct from old_match_id
     or (select status from public.pachanga_canonical_matches where id = old_match_id) <> 'retired'
     or (select status from public.pachanga_competition_match_contexts where id = old_context_id) <> 'retired'
     or not exists (
       select 1
       from public.pachanga_tournament_bracket_node_revisions revisions
       where revisions.bracket_node_id = semifinal_node.id
         and revisions.canonical_match_id = old_match_id
     ) then
    raise exception 'DEMO_WORLD_V2_6_CORRECTION_LINEAGE_INVALID';
  end if;
  insert into demo_v26_story_state values (
    'correction',
    jsonb_build_object(
      'oldMatchRetired', true,
      'oldContextRetired', true,
      'replacementCreated', true,
      'nodeHistoryRetained', true,
      'oldMatchKey', 'SF1-v1',
      'replacementMatchKey', 'SF1-v2'
    )
  );
end;
$demo_v26_correction$;

-- The active carry sanction belongs to team 4, which reaches the corrected
-- semifinal. PostgreSQL, not the client, rejects that player for this match.
do $demo_v26_discipline_check$
declare semifinal_match_id uuid;
declare sanction_applies boolean;
declare diagnostic jsonb;
begin
  select nodes.canonical_match_id into semifinal_match_id
  from public.pachanga_tournament_bracket_nodes nodes
  join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
  join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
  where competitions.slug = 'copa-barrios-iq-2027'
    and nodes.round_code = 'SEMIFINAL'
    and nodes.node_order = 1;
  sanction_applies := private.pachanga_competition_player_sanction_applies_v1(
    (select id from public.pachanga_competitions where slug = 'copa-barrios-iq-2027'),
    md5('demo-world-v2-5-player-profile-4-1')::uuid,
    semifinal_match_id
  );
  if not sanction_applies then
    select jsonb_build_object(
      'sanctions', coalesce((select jsonb_agg(jsonb_build_object(
        'status', sanctions.status,
        'remainingUnits', sanctions.remaining_units,
        'unitType', sanctions.unit_type,
        'suspensiveHold', sanctions.suspensive_hold,
        'sourceMatch', source_events.canonical_match_id
      ))
      from public.pachanga_competition_sanctions sanctions
      left join public.pachanga_competition_disciplinary_events source_events
        on source_events.id = sanctions.source_event_id
      where sanctions.competition_id = (
          select id from public.pachanga_competitions where slug = 'copa-barrios-iq-2027'
        )
        and sanctions.player_profile_id = md5('demo-world-v2-5-player-profile-4-1')::uuid), '[]'::jsonb),
      'targetItems', coalesce((select jsonb_agg(jsonb_build_object(
        'status', items.status,
        'start', items.scheduled_start,
        'roundNumber', rounds.round_number,
        'stageType', stages.stage_type
      ))
      from public.pachanga_competition_schedule_items items
      join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
      join public.pachanga_competition_stages stages on stages.id = rounds.stage_id
      where items.canonical_match_id = semifinal_match_id), '[]'::jsonb)
    ) into diagnostic;
    raise exception 'DEMO_WORLD_V2_6_DISCIPLINE_CARRY_NOT_APPLIED:%', diagnostic;
  end if;
  insert into demo_v26_story_state values (
    'discipline',
    jsonb_build_object(
      'teamNumber', 4,
      'playerLabel', 'Jugador Copa 4.1',
      'sanctionApplies', true,
      'blockedFromSemifinal', true,
      'ratingChanged', false
    )
  );
end;
$demo_v26_discipline_check$;

-- A confirmed referee is replaced on the corrected semifinal through the
-- real Referee Assignment state machine.
do $demo_v26_semifinal_referee$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare original_assignment_id uuid := md5('demo-world-v2-6-semifinal-referee-original')::uuid;
declare replacement_assignment_id uuid := md5('demo-world-v2-6-semifinal-referee-replacement')::uuid;
begin
  select contexts.* into context_row
  from public.pachanga_tournament_bracket_nodes nodes
  join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
  join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
  join public.pachanga_competition_match_contexts contexts
    on contexts.canonical_match_id = nodes.canonical_match_id
   and contexts.status <> 'retired'
  where competitions.slug = 'copa-barrios-iq-2027'
    and nodes.round_code = 'SEMIFINAL'
    and nodes.node_order = 1
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  perform pg_temp.demo_v26_assignment_command(
    '64010000-0000-4000-8000-000000000001',
    original_assignment_id,
    'semifinal-original-propose',
    'assignment.propose',
    jsonb_build_object(
      'refereeProfileId', md5('demo-world-v2-referee-profile-6')::uuid,
      'sourceKind', 'competition_generated',
      'sourceId', context_row.canonical_match_id::text,
      'requesterKind', 'COMPETITION',
      'requesterId', context_row.competition_id,
      'assignmentRole', 'MAIN_REFEREE',
      'responseDeadline', clock_timestamp() + interval '10 days',
      'feeMode', 'FREE',
      'currency', 'EUR'
    )
  );
  perform pg_temp.demo_v26_assignment_command(
    md5('demo-world-v2-referee-user-6')::uuid,
    original_assignment_id,
    'semifinal-original-accept',
    'assignment.accept'
  );
  perform pg_temp.demo_v26_assignment_command(
    '64010000-0000-4000-8000-000000000001',
    original_assignment_id,
    'semifinal-original-confirm',
    'assignment.confirm'
  );
  perform pg_temp.demo_v26_assignment_command(
    '64010000-0000-4000-8000-000000000001',
    original_assignment_id,
    'semifinal-replace',
    'assignment.replace',
    jsonb_build_object(
      'newRefereeProfileId', md5('demo-world-v2-referee-profile-8')::uuid,
      'newAssignmentId', replacement_assignment_id,
      'responseDeadline', clock_timestamp() + interval '10 days',
      'feeMode', 'FREE',
      'currency', 'EUR'
    )
  );
  perform pg_temp.demo_v26_assignment_command(
    md5('demo-world-v2-referee-user-8')::uuid,
    replacement_assignment_id,
    'semifinal-replacement-accept',
    'assignment.accept'
  );
  perform pg_temp.demo_v26_assignment_command(
    '64010000-0000-4000-8000-000000000001',
    replacement_assignment_id,
    'semifinal-replacement-confirm',
    'assignment.confirm'
  );
  insert into demo_v26_story_state values (
    'semifinalReferee',
    jsonb_build_object(
      'originalRefereeNumber', 6,
      'originalStatus', (select status from public.pachanga_referee_assignments where id = original_assignment_id),
      'replacementRefereeNumber', 8,
      'replacementStatus', (select status from public.pachanga_referee_assignments where id = replacement_assignment_id),
      'lineageLinked', (select replaces_assignment_id = original_assignment_id
        from public.pachanga_referee_assignments where id = replacement_assignment_id)
    )
  );
end;
$demo_v26_semifinal_referee$;

select pg_temp.demo_v26_play_node(nodes.id, 'REGULATION', 'semifinal-1-regulation')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'SEMIFINAL'
  and nodes.node_order = 1;

select pg_temp.demo_v26_play_node(nodes.id, 'REGULATION', 'semifinal-2-regulation')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'SEMIFINAL'
  and nodes.node_order = 2;

do $demo_v26_final_fixture_cardinality$
begin
  if not (
    select count(*) = 2
      and count(distinct nodes.canonical_match_id) = 2
      and bool_and(nodes.status = 'match_created')
    from public.pachanga_tournament_bracket_nodes nodes
    join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
    join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
    where competitions.slug = 'copa-barrios-iq-2027'
      and nodes.round_code in ('FINAL', 'THIRD_PLACE')
  ) then
    raise exception 'DEMO_WORLD_V2_6_FINAL_FIXTURE_CARDINALITY_INVALID';
  end if;
end;
$demo_v26_final_fixture_cardinality$;

-- The final has a confirmed referee before its official result.
do $demo_v26_final_referee$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare assignment_id uuid := md5('demo-world-v2-6-final-referee')::uuid;
begin
  select contexts.* into context_row
  from public.pachanga_tournament_bracket_nodes nodes
  join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
  join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
  join public.pachanga_competition_match_contexts contexts
    on contexts.canonical_match_id = nodes.canonical_match_id
   and contexts.status <> 'retired'
  where competitions.slug = 'copa-barrios-iq-2027'
    and nodes.round_code = 'FINAL'
  order by contexts.server_sequence desc, contexts.id desc
  limit 1;
  perform pg_temp.demo_v26_assignment_command(
    '64010000-0000-4000-8000-000000000001',
    assignment_id,
    'final-propose',
    'assignment.propose',
    jsonb_build_object(
      'refereeProfileId', md5('demo-world-v2-referee-profile-7')::uuid,
      'sourceKind', 'competition_generated',
      'sourceId', context_row.canonical_match_id::text,
      'requesterKind', 'COMPETITION',
      'requesterId', context_row.competition_id,
      'assignmentRole', 'MAIN_REFEREE',
      'responseDeadline', clock_timestamp() + interval '10 days',
      'feeMode', 'FREE',
      'currency', 'EUR'
    )
  );
  perform pg_temp.demo_v26_assignment_command(
    md5('demo-world-v2-referee-user-7')::uuid,
    assignment_id,
    'final-accept',
    'assignment.accept'
  );
  perform pg_temp.demo_v26_assignment_command(
    '64010000-0000-4000-8000-000000000001',
    assignment_id,
    'final-confirm',
    'assignment.confirm'
  );
  insert into demo_v26_story_state values (
    'finalReferee',
    jsonb_build_object(
      'refereeNumber', 7,
      'status', (select status from public.pachanga_referee_assignments where id = assignment_id)
    )
  );
end;
$demo_v26_final_referee$;

select pg_temp.demo_v26_play_node(nodes.id, 'REGULATION', 'third-place-regulation')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'THIRD_PLACE';

select pg_temp.demo_v26_play_node(nodes.id, 'REGULATION', 'final-regulation')
from public.pachanga_tournament_bracket_nodes nodes
join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
join public.pachanga_competitions competitions on competitions.id = brackets.competition_id
where competitions.slug = 'copa-barrios-iq-2027'
  and nodes.round_code = 'FINAL';

select pg_temp.demo_v26_bracket_command(
  'completion-rebuild',
  'tournament.completion.rebuild',
  '{"reason":"Construir snapshot canónico del campeón Demo World V2.6"}'::jsonb
);
select pg_temp.demo_v26_bracket_command(
  'tournament-complete',
  'tournament.complete',
  '{"reason":"Final y tercer puesto oficiales; cuadro sano"}'::jsonb
);
select pg_temp.demo_v26_bracket_command(
  'tournament-lock',
  'tournament.lock',
  '{"reason":"Cerrar de forma inmutable COPA BARRIOS IQ 2027"}'::jsonb
);

insert into simulation.demo_world_tournament_knockout_public_snapshot(snapshot)
with target as (
  select competitions.id
  from public.pachanga_competitions competitions
  where competitions.slug = 'copa-barrios-iq-2027'
), bracket as (
  select brackets.*
  from target
  join public.pachanga_tournament_brackets brackets
    on brackets.competition_id = target.id
), completion as (
  select snapshots.*
  from bracket
  join public.pachanga_tournament_completion_snapshots snapshots
    on snapshots.id = bracket.current_completion_snapshot_id
), current_nodes as (
  select
    nodes.*,
    case nodes.round_code
      when 'QUARTERFINAL' then 'QF' || nodes.node_order
      when 'SEMIFINAL' then 'SF' || nodes.node_order
      when 'THIRD_PLACE' then 'THIRD'
      when 'FINAL' then 'FINAL'
      else nodes.round_code || nodes.node_order
    end as node_key,
    home_teams.name as home_team_name,
    substring(home_teams.team_code from 3)::integer as home_team_number,
    away_teams.name as away_team_name,
    substring(away_teams.team_code from 3)::integer as away_team_number,
    substring(winner_teams.team_code from 3)::integer as winner_team_number,
    substring(loser_teams.team_code from 3)::integer as loser_team_number,
    contexts.scheduled_start,
    contexts.venue_label,
    resolutions.resolution_kind,
    resolutions.score_after_regulation_home,
    resolutions.score_after_regulation_away,
    resolutions.extra_time_played,
    resolutions.score_after_extra_time_home,
    resolutions.score_after_extra_time_away,
    resolutions.shootout_home,
    resolutions.shootout_away,
    referee.referee_number,
    referee.assignment_status
  from bracket
  join public.pachanga_tournament_bracket_nodes nodes on nodes.bracket_id = bracket.id
  join public.pachanga_competition_entries home_entries on home_entries.id = nodes.home_entry_id
  join public.pachanga_groups home_teams on home_teams.id = home_entries.team_id
  join public.pachanga_competition_entries away_entries on away_entries.id = nodes.away_entry_id
  join public.pachanga_groups away_teams on away_teams.id = away_entries.team_id
  join public.pachanga_competition_entries winner_entries on winner_entries.id = nodes.winner_entry_id
  join public.pachanga_groups winner_teams on winner_teams.id = winner_entries.team_id
  join public.pachanga_competition_entries loser_entries on loser_entries.id = nodes.loser_entry_id
  join public.pachanga_groups loser_teams on loser_teams.id = loser_entries.team_id
  left join lateral (
    select match_contexts.*
    from public.pachanga_competition_match_contexts match_contexts
    where match_contexts.canonical_match_id = nodes.canonical_match_id
      and match_contexts.status <> 'retired'
    order by match_contexts.server_sequence desc, match_contexts.id desc
    limit 1
  ) contexts on true
  left join lateral (
    select result_resolutions.*
    from public.pachanga_tournament_knockout_result_resolutions result_resolutions
    where result_resolutions.bracket_node_id = nodes.id
    order by result_resolutions.server_sequence desc, result_resolutions.id desc
    limit 1
  ) resolutions on true
  left join lateral (
    select
      substring(profiles.slug from '([0-9]+)$')::integer as referee_number,
      assignments.status as assignment_status
    from public.pachanga_referee_assignments assignments
    join public.pachanga_referee_profiles profiles on profiles.id = assignments.referee_profile_id
    where assignments.competition_match_context_id = contexts.id
      and assignments.status in ('confirmed', 'completed')
    order by assignments.server_sequence desc, assignments.id desc
    limit 1
  ) referee on true
), public_nodes as (
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'nodeKey', node_key,
    'roundCode', round_code,
    'roundOrder', round_order,
    'nodeOrder', node_order,
    'status', 'OFFICIAL',
    'homeTeam', jsonb_build_object('teamNumber', home_team_number, 'name', home_team_name),
    'awayTeam', jsonb_build_object('teamNumber', away_team_number, 'name', away_team_name),
    'scheduledStart', scheduled_start,
    'venueLabel', venue_label,
    'resolutionKind', resolution_kind,
    'score', jsonb_build_object(
      'home', coalesce(score_after_extra_time_home, score_after_regulation_home),
      'away', coalesce(score_after_extra_time_away, score_after_regulation_away)
    ),
    'regulationScore', jsonb_build_object(
      'home', score_after_regulation_home,
      'away', score_after_regulation_away
    ),
    'extraTime', case when extra_time_played then jsonb_build_object(
      'home', score_after_extra_time_home,
      'away', score_after_extra_time_away
    ) else null end,
    'shootout', case when shootout_home is not null then jsonb_build_object(
      'home', shootout_home,
      'away', shootout_away
    ) else null end,
    'winnerTeamNumber', winner_team_number,
    'loserTeamNumber', loser_team_number,
    'referee', case when referee_number is null then null else jsonb_build_object(
      'refereeNumber', referee_number,
      'status', upper(assignment_status)
    ) end
  )) order by round_order, node_order) value
  from current_nodes
), qualifier_entries as (
  select distinct source.entry_id
  from (
    select nodes.home_entry_id as entry_id from current_nodes nodes where nodes.round_code = 'QUARTERFINAL'
    union all
    select nodes.away_entry_id as entry_id from current_nodes nodes where nodes.round_code = 'QUARTERFINAL'
  ) source
), journeys as (
  select jsonb_agg(jsonb_build_object(
    'teamNumber', substring(teams.team_code from 3)::integer,
    'teamName', teams.name,
    'status', case
      when qualifiers.entry_id = completion.champion_entry_id then 'CHAMPION'
      when qualifiers.entry_id = completion.runner_up_entry_id then 'RUNNER_UP'
      when qualifiers.entry_id = completion.third_place_entry_id then 'THIRD_PLACE'
      when qualifiers.entry_id = completion.fourth_place_entry_id then 'FOURTH_PLACE'
      else 'ELIMINATED'
    end,
    'finalPosition', case
      when qualifiers.entry_id = completion.champion_entry_id then 1
      when qualifiers.entry_id = completion.runner_up_entry_id then 2
      when qualifiers.entry_id = completion.third_place_entry_id then 3
      when qualifiers.entry_id = completion.fourth_place_entry_id then 4
      else null
    end,
    'path', (
      select jsonb_agg(nodes.node_key order by nodes.round_order, nodes.node_order)
      from current_nodes nodes
      where qualifiers.entry_id in (nodes.home_entry_id, nodes.away_entry_id)
    )
  ) order by substring(teams.team_code from 3)::integer) value
  from qualifier_entries qualifiers
  join public.pachanga_competition_entries entries on entries.id = qualifiers.entry_id
  join public.pachanga_groups teams on teams.id = entries.team_id
  cross join completion
), podium as (
  select jsonb_build_object(
    'champion', jsonb_build_object(
      'teamNumber', substring(champion.team_code from 3)::integer,
      'name', champion.name
    ),
    'runnerUp', jsonb_build_object(
      'teamNumber', substring(runner.team_code from 3)::integer,
      'name', runner.name
    ),
    'thirdPlace', jsonb_build_object(
      'teamNumber', substring(third_place.team_code from 3)::integer,
      'name', third_place.name
    ),
    'fourthPlace', jsonb_build_object(
      'teamNumber', substring(fourth_place.team_code from 3)::integer,
      'name', fourth_place.name
    )
  ) value
  from completion
  join public.pachanga_competition_entries champion_entry on champion_entry.id = completion.champion_entry_id
  join public.pachanga_groups champion on champion.id = champion_entry.team_id
  join public.pachanga_competition_entries runner_entry on runner_entry.id = completion.runner_up_entry_id
  join public.pachanga_groups runner on runner.id = runner_entry.team_id
  join public.pachanga_competition_entries third_entry on third_entry.id = completion.third_place_entry_id
  join public.pachanga_groups third_place on third_place.id = third_entry.team_id
  join public.pachanga_competition_entries fourth_entry on fourth_entry.id = completion.fourth_place_entry_id
  join public.pachanga_groups fourth_place on fourth_place.id = fourth_entry.team_id
)
select jsonb_build_object(
  'competitionName', 'COPA BARRIOS IQ 2027',
  'status', 'LOCKED',
  'format', 'SINGLE_MATCH_KNOCKOUT',
  'thirdPlaceEnabled', true,
  'rounds', jsonb_build_array(
    jsonb_build_object('code', 'QUARTERFINAL', 'label', 'Cuartos', 'matches', 4),
    jsonb_build_object('code', 'SEMIFINAL', 'label', 'Semifinales', 'matches', 2),
    jsonb_build_object('code', 'THIRD_PLACE', 'label', 'Tercer puesto', 'matches', 1),
    jsonb_build_object('code', 'FINAL', 'label', 'Final', 'matches', 1)
  ),
  'nodes', public_nodes.value,
  'podium', podium.value,
  'teamJourneys', journeys.value,
  'discipline', (select value from demo_v26_story_state where key = 'discipline'),
  'organizerDesk', jsonb_build_object(
    'unresolvedNodes', 0,
    'unscheduledMatches', 0,
    'unassignedFinals', 0,
    'pendingResults', 0,
    'correctionsWithImpact', 1,
    'bracketHealth', 'HEALTHY',
    'completionHealth', 'COMPLETE',
    'nextAction', 'TOURNAMENT_LOCKED'
  ),
  'transport', jsonb_build_object('methods', jsonb_build_array('GET'), 'remoteWrites', 0),
  'publicSafe', true
)
from public_nodes, journeys, podium;

insert into simulation.demo_world_tournament_knockout_proof(proof)
with target as (
  select competitions.id
  from public.pachanga_competitions competitions
  where competitions.slug = 'copa-barrios-iq-2027'
), bracket as (
  select brackets.*
  from target
  join public.pachanga_tournament_brackets brackets on brackets.competition_id = target.id
), completion as (
  select snapshots.*
  from bracket
  join public.pachanga_tournament_completion_snapshots snapshots
    on snapshots.id = bracket.current_completion_snapshot_id
), podium as (
  select
    substring(champion.team_code from 3)::integer champion_number,
    substring(runner.team_code from 3)::integer runner_number,
    substring(third_place.team_code from 3)::integer third_number,
    substring(fourth_place.team_code from 3)::integer fourth_number
  from completion
  join public.pachanga_competition_entries champion_entry on champion_entry.id = completion.champion_entry_id
  join public.pachanga_groups champion on champion.id = champion_entry.team_id
  join public.pachanga_competition_entries runner_entry on runner_entry.id = completion.runner_up_entry_id
  join public.pachanga_groups runner on runner.id = runner_entry.team_id
  join public.pachanga_competition_entries third_entry on third_entry.id = completion.third_place_entry_id
  join public.pachanga_groups third_place on third_place.id = third_entry.team_id
  join public.pachanga_competition_entries fourth_entry on fourth_entry.id = completion.fourth_place_entry_id
  join public.pachanga_groups fourth_place on fourth_place.id = fourth_entry.team_id
), group_checksum as (
  select encode(extensions.digest(convert_to(
    coalesce((select string_agg(snapshots.content_checksum, '|' order by snapshots.id)
      from public.pachanga_competition_standing_snapshots snapshots
      join public.pachanga_competition_standing_states states
        on states.current_snapshot_id = snapshots.id
      join target on target.id = states.competition_id), ''),
    'UTF8'
  ), 'sha256'), 'hex') value
), current_slots as (
  select slots.*
  from bracket
  join public.pachanga_tournament_bracket_node_slots slots on slots.bracket_id = bracket.id
  where not exists (
    select 1
    from public.pachanga_tournament_bracket_node_slots newer
    where newer.bracket_node_id = slots.bracket_node_id
      and newer.side = slots.side
      and newer.slot_revision > slots.slot_revision
  )
), active_advances as (
  select distinct on (decisions.source_node_id) decisions.*
  from bracket
  join public.pachanga_tournament_bracket_advance_decisions decisions
    on decisions.bracket_id = bracket.id
  order by decisions.source_node_id, decisions.revision desc,
    decisions.server_sequence desc, decisions.id desc
), result_kinds as (
  select jsonb_object_agg(kinds.resolution_kind, kinds.count order by kinds.resolution_kind) value
  from (
    select resolutions.resolution_kind, count(*)::integer count
    from bracket
    join public.pachanga_tournament_knockout_result_resolutions resolutions
      on resolutions.bracket_id = bracket.id
    group by resolutions.resolution_kind
  ) kinds
), shootout as (
  select resolutions.*
  from bracket
  join public.pachanga_tournament_knockout_result_resolutions resolutions
    on resolutions.bracket_id = bracket.id
  where resolutions.resolution_kind = 'PENALTY_SHOOTOUT'
  order by resolutions.server_sequence
  limit 1
)
select jsonb_build_object(
  'bracket', jsonb_build_object(
    'status', bracket.status,
    'size', bracket.bracket_size,
    'roundCount', bracket.round_count,
    'thirdPlaceEnabled', bracket.third_place_enabled,
    'revision', bracket.revision,
    'revisionCount', (select count(*) from public.pachanga_tournament_bracket_revisions revisions where revisions.bracket_id = bracket.id),
    'nodeCount', (select count(*) from public.pachanga_tournament_bracket_nodes nodes where nodes.bracket_id = bracket.id),
    'advancedNodes', (select count(*) from public.pachanga_tournament_bracket_nodes nodes where nodes.bracket_id = bracket.id and nodes.status = 'advanced'),
    'currentSlots', (select count(*) from current_slots),
    'slotRevisions', (select count(*) from public.pachanga_tournament_bracket_node_slots slots where slots.bracket_id = bracket.id),
    'fixtureReservations', (select count(*) from public.pachanga_tournament_bracket_fixture_reservations reservations where reservations.bracket_id = bracket.id and reservations.status = 'ACTIVE')
  ),
  'matches', jsonb_build_object(
    'active', (select count(*) from public.pachanga_tournament_bracket_nodes nodes where nodes.bracket_id = bracket.id and nodes.canonical_match_id is not null),
    'historical', (select count(distinct revisions.canonical_match_id)
      from public.pachanga_tournament_bracket_node_revisions revisions
      join public.pachanga_tournament_bracket_nodes nodes on nodes.id = revisions.bracket_node_id
      where nodes.bracket_id = bracket.id and revisions.canonical_match_id is not null),
    'retired', (select count(*)
      from public.pachanga_canonical_matches matches
      where matches.status = 'retired'
        and exists (
          select 1 from public.pachanga_tournament_bracket_node_revisions revisions
          join public.pachanga_tournament_bracket_nodes nodes on nodes.id = revisions.bracket_node_id
          where nodes.bracket_id = bracket.id and revisions.canonical_match_id = matches.id
        )),
    'quarterfinals', (select count(*) from public.pachanga_tournament_bracket_nodes nodes where nodes.bracket_id = bracket.id and nodes.round_code = 'QUARTERFINAL'),
    'semifinals', (select count(*) from public.pachanga_tournament_bracket_nodes nodes where nodes.bracket_id = bracket.id and nodes.round_code = 'SEMIFINAL'),
    'finals', (select count(*) from public.pachanga_tournament_bracket_nodes nodes where nodes.bracket_id = bracket.id and nodes.round_code = 'FINAL'),
    'thirdPlace', (select count(*) from public.pachanga_tournament_bracket_nodes nodes where nodes.bracket_id = bracket.id and nodes.round_code = 'THIRD_PLACE')
  ),
  'progression', jsonb_build_object(
    'advanceDecisions', (select count(*) from public.pachanga_tournament_bracket_advance_decisions decisions where decisions.bracket_id = bracket.id),
    'activeAdvanceDecisions', (select count(*) from active_advances),
    'invalidations', (select count(*) from public.pachanga_tournament_bracket_invalidations invalidations where invalidations.bracket_id = bracket.id),
    'dependencyImpacts', (select count(*)
      from public.pachanga_tournament_bracket_dependency_impacts impacts
      join public.pachanga_tournament_bracket_invalidations invalidations
        on invalidations.id = impacts.bracket_invalidation_id
      where invalidations.bracket_id = bracket.id),
    'resolutionKinds', result_kinds.value
  ),
  'penaltySeparation', jsonb_build_object(
    'regulationHome', shootout.score_after_regulation_home,
    'regulationAway', shootout.score_after_regulation_away,
    'extraTimeHome', shootout.score_after_extra_time_home,
    'extraTimeAway', shootout.score_after_extra_time_away,
    'shootoutHome', shootout.shootout_home,
    'shootoutAway', shootout.shootout_away,
    'shootoutGoalsAddedToSportingScore', false,
    'groupStandingsUnchanged', group_checksum.value = (
      select value ->> 'value' from demo_v26_story_state where key = 'groupStandingsChecksum'
    )
  ),
  'correction', (select value from demo_v26_story_state where key = 'correction'),
  'r4d', jsonb_build_object(
    'confirmedNoShows', (select count(*)
      from target
      join public.pachanga_competition_no_show_incidents incidents on incidents.competition_id = target.id
      where incidents.status in ('confirmed', 'resolved')),
    'knockoutNoShowResolution', exists (
      select 1 from bracket
      join public.pachanga_tournament_knockout_result_resolutions resolutions
        on resolutions.bracket_id = bracket.id
      join public.pachanga_competition_official_result_decisions decisions
        on decisions.id = resolutions.official_result_decision_id
      join public.pachanga_competition_no_show_incidents incidents
        on incidents.id = decisions.operational_source_id
       and incidents.competition_id = bracket.competition_id
      where resolutions.resolution_kind in ('NO_SHOW', 'FORFEIT')
        and decisions.operational_source_type = 'NO_SHOW_INCIDENT'
        and incidents.status in ('confirmed', 'resolved')
    )
  ),
  'r5', (select value from demo_v26_story_state where key = 'discipline'),
  'referees', jsonb_build_object(
    'semifinalReplacement', (select value from demo_v26_story_state where key = 'semifinalReferee'),
    'final', (select value from demo_v26_story_state where key = 'finalReferee')
  ),
  'completion', jsonb_build_object(
    'snapshots', (select count(*) from public.pachanga_tournament_completion_snapshots snapshots where snapshots.bracket_id = bracket.id),
    'championTeamNumber', podium.champion_number,
    'runnerUpTeamNumber', podium.runner_number,
    'thirdPlaceTeamNumber', podium.third_number,
    'fourthPlaceTeamNumber', podium.fourth_number,
    'rewardGrants', completion.snapshot ->> 'rewardGrants'
  ),
  'integrity', jsonb_build_object(
    'ratingV2Unchanged', (select count(*) from public.pachanga_player_rating_snapshots) = (select value from demo_v26_integrity_baseline where key = 'ratingSnapshots'),
    'rewardsUnchanged', (select count(*) from public.pachanga_reward_grants) = (select value from demo_v26_integrity_baseline where key = 'rewardGrants'),
    'conductUnchanged', (select count(*) from private.pachanga_conduct_reports) = (select value from demo_v26_integrity_baseline where key = 'conductReports'),
    'billingUnchanged', (select count(*) from public.pachanga_stripe_webhook_events) = (select value from demo_v26_integrity_baseline where key = 'billingEvents'),
    'remoteWrites', 0
  ),
  'policy', (select revisions.policy_snapshot
    from public.pachanga_tournament_bracket_revisions revisions
    where revisions.id = bracket.current_revision_id),
  'readModel', (select jsonb_build_object(
      'revision', models.revision,
      'serverSequencePresent', models.server_sequence > 0,
      'checksumPresent', length(models.snapshot_checksum) = 64
    )
    from public.pachanga_tournament_knockout_read_models models
    where models.bracket_id = bracket.id),
  'remoteWrites', 0
)
from bracket, completion, podium, group_checksum, result_kinds, shootout;

do $demo_v26_assertions$
declare public_snapshot jsonb;
declare proof jsonb;
begin
  select snapshot into public_snapshot
  from simulation.demo_world_tournament_knockout_public_snapshot;
  select knockout_proof.proof into proof
  from simulation.demo_world_tournament_knockout_proof knockout_proof;
  if (proof #>> '{bracket,status}') <> 'locked'
     or (proof #>> '{bracket,nodeCount}')::integer <> 8
     or (proof #>> '{bracket,advancedNodes}')::integer <> 8
     or (proof #>> '{bracket,currentSlots}')::integer <> 16
     or (proof #>> '{bracket,fixtureReservations}')::integer <> 8
     or not (proof #>> '{bracket,thirdPlaceEnabled}')::boolean
     or (proof #>> '{matches,active}')::integer <> 8
     or (proof #>> '{matches,historical}')::integer <> 9
     or (proof #>> '{matches,retired}')::integer <> 1
     or (proof #>> '{matches,quarterfinals}')::integer <> 4
     or (proof #>> '{matches,semifinals}')::integer <> 2
     or (proof #>> '{matches,finals}')::integer <> 1
     or (proof #>> '{matches,thirdPlace}')::integer <> 1
     or (proof #>> '{progression,activeAdvanceDecisions}')::integer <> 8
     or (proof #>> '{progression,invalidations}')::integer <> 1
     or (proof #>> '{progression,resolutionKinds,SPORTING_RESULT}')::integer < 1
     or (proof #>> '{progression,resolutionKinds,EXTRA_TIME}')::integer <> 1
     or (proof #>> '{progression,resolutionKinds,PENALTY_SHOOTOUT}')::integer <> 1
     or coalesce(nullif(proof #>> '{progression,resolutionKinds,NO_SHOW}', ''), '0')::integer
       + coalesce(nullif(proof #>> '{progression,resolutionKinds,FORFEIT}', ''), '0')::integer <> 1 then
    raise exception 'DEMO_WORLD_V2_6_KNOCKOUT_GRAPH_INVALID:%', proof;
  end if;
  if not (proof #>> '{penaltySeparation,groupStandingsUnchanged}')::boolean
     or (proof #>> '{penaltySeparation,regulationHome}')::integer <> 1
     or (proof #>> '{penaltySeparation,regulationAway}')::integer <> 1
     or (proof #>> '{penaltySeparation,shootoutHome}')::integer <> 5
     or (proof #>> '{penaltySeparation,shootoutAway}')::integer <> 4
     or (proof #>> '{penaltySeparation,shootoutGoalsAddedToSportingScore}')::boolean then
    raise exception 'DEMO_WORLD_V2_6_PENALTY_ACCOUNTING_INVALID:%', proof -> 'penaltySeparation';
  end if;
  if not (proof #>> '{correction,oldMatchRetired}')::boolean
     or not (proof #>> '{correction,replacementCreated}')::boolean
     or not (proof #>> '{correction,nodeHistoryRetained}')::boolean
     or not (proof #>> '{r4d,knockoutNoShowResolution}')::boolean
     or not (proof #>> '{r5,sanctionApplies}')::boolean
     or (proof #>> '{referees,semifinalReplacement,originalStatus}') <> 'replaced'
     or (proof #>> '{referees,semifinalReplacement,replacementStatus}') <> 'confirmed'
     or (proof #>> '{referees,final,status}') <> 'confirmed' then
    raise exception 'DEMO_WORLD_V2_6_LINKED_STORIES_INVALID:%', proof;
  end if;
  if (proof #>> '{completion,snapshots}')::integer <> 2
     or nullif(proof #>> '{completion,championTeamNumber}', '') is null
     or nullif(proof #>> '{completion,runnerUpTeamNumber}', '') is null
     or nullif(proof #>> '{completion,thirdPlaceTeamNumber}', '') is null
     or nullif(proof #>> '{completion,fourthPlaceTeamNumber}', '') is null
     or (proof #>> '{completion,rewardGrants}')::integer <> 0
     or not (proof #>> '{integrity,ratingV2Unchanged}')::boolean
     or not (proof #>> '{integrity,rewardsUnchanged}')::boolean
     or not (proof #>> '{integrity,conductUnchanged}')::boolean
     or not (proof #>> '{integrity,billingUnchanged}')::boolean
     or (proof #>> '{integrity,remoteWrites}')::integer <> 0 then
    raise exception 'DEMO_WORLD_V2_6_COMPLETION_OR_INTEGRITY_INVALID:%', proof;
  end if;
  if jsonb_array_length(public_snapshot -> 'nodes') <> 8
     or jsonb_array_length(public_snapshot -> 'teamJourneys') <> 8
     or public_snapshot::text ~* '[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
     or public_snapshot::text ~* '(privateReason|evidenceRefs|operationId|serverSequence)' then
    raise exception 'DEMO_WORLD_V2_6_PUBLIC_SNAPSHOT_UNSAFE:%', public_snapshot;
  end if;
  if exists (
    select 1
    from public.pachanga_tournament_bracket_nodes nodes
    join public.pachanga_tournament_brackets brackets on brackets.id = nodes.bracket_id
    where brackets.competition_id = (
      select id from public.pachanga_competitions where slug = 'copa-barrios-iq-2027'
    )
    group by nodes.round_code, nodes.node_order
    having count(*) > 1
  ) then
    raise exception 'DEMO_WORLD_V2_6_DUPLICATE_NODE';
  end if;
end;
$demo_v26_assertions$;

select 'DEMO_WORLD_V2_6_TOURNAMENT_KNOCKOUT_REPORT|' || jsonb_build_object(
  'nodes', (select (proof #>> '{bracket,nodeCount}')::integer from simulation.demo_world_tournament_knockout_proof),
  'activeMatches', (select (proof #>> '{matches,active}')::integer from simulation.demo_world_tournament_knockout_proof),
  'historicalMatches', (select (proof #>> '{matches,historical}')::integer from simulation.demo_world_tournament_knockout_proof),
  'championTeamNumber', (select (proof #>> '{completion,championTeamNumber}')::integer from simulation.demo_world_tournament_knockout_proof),
  'thirdPlaceTeamNumber', (select (proof #>> '{completion,thirdPlaceTeamNumber}')::integer from simulation.demo_world_tournament_knockout_proof),
  'remoteWrites', 0
)::text;

\if :{?DEMO_WORLD_V2_PERSIST}
commit;
\else
rollback;
\endif
