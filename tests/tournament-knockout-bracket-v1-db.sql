\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '240s';

create temporary table r6c_test_state(
  key text primary key,
  value jsonb not null
);

create or replace function pg_temp.r6c_assert(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then
    raise exception 'R6C_ASSERTION_FAILED: %', message;
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000090","role":"authenticated"}',
  false
);

insert into r6c_test_state values (
  'flags',
  public.command_pachanga_tournament_knockout_platform_v1(
    '65030000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-00000000c6c1',
    (select revision from private.pachanga_competition_foundation_settings where singleton),
    'tournament.knockout.flags.set',
    '{"knockoutFoundationEnabled":true,"knockoutMatchGenerationEnabled":true,"bracketProgressionEnabled":true,"extraTimeEnabled":true,"penaltyShootoutEnabled":true,"thirdPlaceEnabled":true,"completionEnabled":true,"reason":"R6C local canonical story"}',
    '{"clientVersion":"6.2.0+r6c-test","serviceWorkerVersion":"r6c-test","installedMode":"browser","surface":"sql"}'
  )
);

select pg_temp.r6c_assert(
  (select tournament_knockout_foundation_enabled
      and tournament_knockout_match_generation_enabled
      and tournament_bracket_progression_enabled
      and tournament_extra_time_enabled
      and tournament_penalty_shootout_enabled
      and tournament_third_place_enabled
      and tournament_completion_enabled
      and not tournament_two_leg_enabled
      and not tournament_double_elimination_enabled
      and not tournament_public_discovery_enabled
    from private.pachanga_competition_foundation_settings where singleton),
  'R6C flags must activate narrowly while advanced formats, discovery and payments remain off'
);

-- R6C-PRODUCT-084: an older R6A flag write must preserve every R6C-owned
-- capability and derive aggregate match generation instead of conflicting with
-- the R6C dependency constraint.
select public.command_pachanga_tournament_platform_v1(
  '65030000-0000-4000-8000-000000000101',
  '00000000-0000-0000-0000-00000000c6a1',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'tournament.flags.set',
  '{"foundationEnabled":true,"privateBetaEnabled":true,"creationEnabled":true,"drawEnabled":true,"automaticEnabled":true,"manualEnabled":true,"hybridEnabled":true,"publishEnabled":true,"reason":"R6C compatibility regression"}',
  '{"clientVersion":"6.3.0+r6c-regression","surface":"sql"}'
);

select pg_temp.r6c_assert(
  (select tournament_knockout_foundation_enabled
      and tournament_knockout_match_generation_enabled
      and tournament_bracket_progression_enabled
      and tournament_extra_time_enabled
      and tournament_penalty_shootout_enabled
      and tournament_third_place_enabled
      and tournament_completion_enabled
      and tournament_match_generation_enabled
      and not tournament_two_leg_enabled
      and not tournament_double_elimination_enabled
      and not tournament_public_discovery_enabled
    from private.pachanga_competition_foundation_settings where singleton),
  'R6A tournament flag command must preserve active R6C capabilities'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

insert into r6c_test_state values (
  'activate_expected',
  jsonb_build_object('revision', (
    select states.revision from public.pachanga_tournament_group_stage_states states
    join public.pachanga_competitions competitions on competitions.id=states.competition_id
    where competitions.slug='r6a-concurrency-fixture'
  ))
);
insert into r6c_test_state values (
  'activate',
  public.command_pachanga_tournament_knockout_v1(
    '65030000-0000-4000-8000-000000000002',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6c_test_state where key='activate_expected'),
    'bracket.activate',
    '{"reason":"R6C canonical activation"}',
    '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  )
);

select pg_temp.r6c_assert(
  (select value from r6c_test_state where key='activate') =
  public.command_pachanga_tournament_knockout_v1(
    '65030000-0000-4000-8000-000000000002',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6c_test_state where key='activate_expected'),
    'bracket.activate',
    '{"reason":"R6C canonical activation"}',
    '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  ),
  'bracket activation replay must return the byte-equivalent receipt'
);

select pg_temp.r6c_assert(
  (select count(*)=1 and min(status)='active' and min(bracket_size)=8
      and min(round_count)=3 and not bool_or(third_place_enabled)
    from public.pachanga_tournament_brackets),
  'R6C activation must materialize one live eight-team bracket without third place when the frozen rule disables it'
);
select pg_temp.r6c_assert(
  (select count(*)=7 from public.pachanga_tournament_bracket_nodes),
  'eight teams must materialize four quarterfinals, two semifinals and one final'
);
select pg_temp.r6c_assert(
  (select count(*)=14
      and count(*) filter (where source_kind='GROUP_POSITION')=8
      and count(*) filter (where source_kind='WINNER_OF')=6
    from public.pachanga_tournament_bracket_node_slots),
  'live bracket slots must preserve qualification and winner lineage'
);
select pg_temp.r6c_assert(
  (select count(*)=1 and min(version)=1 and min(revision_kind)='ACTIVATION'
    from public.pachanga_tournament_bracket_revisions),
  'activation must create one immutable initial BracketRevision'
);
select pg_temp.r6c_assert(
  (select count(*) = (
      select count(*)
      from public.pachanga_tournament_qualification_rows qualification_rows
      join public.pachanga_tournament_brackets brackets
        on brackets.qualification_snapshot_id = qualification_rows.qualification_snapshot_id
      where qualification_rows.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
    )
    and bool_and(memberships.status = 'active')
    and count(distinct memberships.entry_id) = count(*)
    from public.pachanga_competition_stage_memberships memberships
    join public.pachanga_tournament_brackets brackets
      on brackets.knockout_stage_id = memberships.stage_id),
  'activation must move every published qualifier exactly once into the knockout stage'
);
select pg_temp.r6c_assert(
  not exists (
    select 1
    from public.pachanga_competition_stage_memberships memberships
    join public.pachanga_tournament_brackets brackets on true
    join public.pachanga_tournament_group_stage_states states
      on states.id = brackets.group_stage_state_id
    join public.pachanga_competition_entries entries
      on entries.id = memberships.entry_id
    where memberships.stage_id = states.stage_id
      and memberships.status = 'active'
      and entries.competition_id = brackets.competition_id
      and entries.category_id = brackets.category_id
  ),
  'the completed source stage must retain history without active category memberships'
);
select pg_temp.r6c_assert(
  not exists (
    select 1
    from public.pachanga_competition_stage_memberships memberships
    join public.pachanga_tournament_brackets brackets
      on brackets.knockout_stage_id = memberships.stage_id
    left join public.pachanga_tournament_qualification_rows qualification_rows
      on qualification_rows.qualification_snapshot_id = brackets.qualification_snapshot_id
     and qualification_rows.entry_id = memberships.entry_id
     and qualification_rows.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
    where memberships.status = 'active'
      and qualification_rows.id is null
  ),
  'eliminated entries and byes must never receive a knockout membership'
);

-- Regression R6C-PRODUCT-007: participant resolution alone must never invent
-- a future match without an explicit organizer reservation.
do $$
declare selected_node uuid;
begin
  select nodes.id into selected_node
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.round_code='QUARTERFINAL'
  order by nodes.node_order limit 1;
  begin
    perform public.command_pachanga_tournament_knockout_v1(
      '65030000-0000-4000-8000-000000000003',
      (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
      (select revision from public.pachanga_tournament_brackets),
      'bracket.node.generate_match',
      jsonb_build_object('nodeId', selected_node, 'reason', 'must require reservation'),
      '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
    );
    raise exception 'R6C_MATCH_WITHOUT_RESERVATION_UNEXPECTEDLY_SUCCEEDED';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'TOURNAMENT_KNOCKOUT_MATCH_NOT_READY' then raise; end if;
  end;
end;
$$;

-- Reserve every round before all participants are known. R4B remains the
-- authority for time and place while R6C owns only bracket participants.
do $$
declare node_row record;
declare slot_start timestamptz := '2027-06-01 18:00:00+02'::timestamptz;
begin
  for node_row in
    select nodes.id, nodes.round_order, nodes.node_order
    from public.pachanga_tournament_bracket_nodes nodes
    order by nodes.round_order, nodes.node_order
  loop
    perform public.command_pachanga_tournament_knockout_v1(
      gen_random_uuid(),
      (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
      (select revision from public.pachanga_tournament_brackets),
      'bracket.reserve_slot',
      jsonb_build_object(
        'nodeId', node_row.id,
        'startsAt', slot_start + make_interval(days => node_row.round_order * 7, hours => node_row.node_order * 2),
        'endsAt', slot_start + make_interval(days => node_row.round_order * 7, hours => node_row.node_order * 2 + 2),
        'timezone', 'Europe/Madrid',
        'venueLabel', 'Campo R6C ' || node_row.round_order || '-' || node_row.node_order,
        'resourceKey', 'r6c-' || node_row.round_order || '-' || node_row.node_order,
        'reason', 'Reserva canónica de eliminatoria'
      ),
      '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
    );
  end loop;
end;
$$;

select pg_temp.r6c_assert(
  (select count(*)=7 and count(distinct schedule_slot_id)=7
    from public.pachanga_tournament_bracket_fixture_reservations
    where status='ACTIVE'),
  'every future knockout node must own an explicit R4B-backed reservation'
);

-- Generate the four participant-resolved quarterfinals. The second command
-- uses a fixed operationId so replay/cardinality can be asserted permanently.
do $$
declare node_row record;
declare operation_value uuid;
declare first_response jsonb;
declare replay_response jsonb;
begin
  for node_row in
    select nodes.id, nodes.node_order
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.round_code='QUARTERFINAL'
    order by nodes.node_order
  loop
    operation_value := case when node_row.node_order=1
      then '65030000-0000-4000-8000-000000000004'::uuid else gen_random_uuid() end;
    first_response := public.command_pachanga_tournament_knockout_v1(
      operation_value,
      (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
      (select revision from public.pachanga_tournament_brackets),
      'bracket.node.generate_match',
      jsonb_build_object('nodeId', node_row.id, 'reason', 'Publicación canónica de cuartos'),
      '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
    );
    if node_row.node_order=1 then
      replay_response := public.command_pachanga_tournament_knockout_v1(
        operation_value,
        (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
        ((first_response ->> 'confirmedRevision')::bigint - 1),
        'bracket.node.generate_match',
        jsonb_build_object('nodeId', node_row.id, 'reason', 'Publicación canónica de cuartos'),
        '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
      );
      perform pg_temp.r6c_assert(
        first_response=replay_response,
        'match generation replay must return the same receipt'
      );
    end if;
  end loop;
end;
$$;

select pg_temp.r6c_assert(
  (select count(*)=4 and count(distinct canonical_match_id)=4
    from public.pachanga_tournament_bracket_nodes
    where round_code='QUARTERFINAL'),
  'quarterfinal generation must create exactly one CanonicalMatch per node'
);

create or replace function pg_temp.r6c_play_node(
  target_node_id uuid,
  target_resolution_kind text
)
returns uuid
language plpgsql
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare home_owner uuid;
declare away_owner uuid;
declare score_home integer;
declare score_away integer;
declare knockout_evidence jsonb;
declare decision_id uuid;
begin
  select * into node_row from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id=target_node_id;
  if node_row.canonical_match_id is null then
    perform public.command_pachanga_tournament_knockout_v1(
      gen_random_uuid(),
      (select competition_id from public.pachanga_tournament_brackets where id=node_row.bracket_id),
      (select revision from public.pachanga_tournament_brackets where id=node_row.bracket_id),
      'bracket.node.generate_match',
      jsonb_build_object('nodeId', node_row.id, 'reason', 'Generación del siguiente cruce'),
      '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
    );
    select * into node_row from public.pachanga_tournament_bracket_nodes nodes
    where nodes.id=target_node_id;
  end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.canonical_match_id=node_row.canonical_match_id
    and contexts.status <> 'retired'
  order by contexts.server_sequence desc, contexts.id desc limit 1;
  select groups.owner_id into home_owner
  from public.pachanga_competition_entries entries
  join public.pachanga_groups groups on groups.id=entries.team_id
  where entries.id=context_row.home_entry_id;
  select groups.owner_id into away_owner
  from public.pachanga_competition_entries entries
  join public.pachanga_groups groups on groups.id=entries.team_id
  where entries.id=context_row.away_entry_id;

  if upper(target_resolution_kind)='REGULATION' then
    score_home := 2; score_away := 0;
    knockout_evidence := jsonb_build_object(
      'scoreAfterRegulationHome', 2, 'scoreAfterRegulationAway', 0,
      'extraTimePlayed', false
    );
  elsif upper(target_resolution_kind)='EXTRA_TIME' then
    score_home := 2; score_away := 1;
    knockout_evidence := jsonb_build_object(
      'scoreAfterRegulationHome', 1, 'scoreAfterRegulationAway', 1,
      'extraTimePlayed', true,
      'scoreAfterExtraTimeHome', 2, 'scoreAfterExtraTimeAway', 1
    );
  elsif upper(target_resolution_kind)='PENALTY_SHOOTOUT' then
    score_home := 1; score_away := 1;
    knockout_evidence := jsonb_build_object(
      'scoreAfterRegulationHome', 1, 'scoreAfterRegulationAway', 1,
      'extraTimePlayed', true,
      'scoreAfterExtraTimeHome', 1, 'scoreAfterExtraTimeAway', 1,
      'shootoutHome', 5, 'shootoutAway', 4
    );
  else
    raise exception 'R6C_TEST_RESOLUTION_KIND_INVALID';
  end if;

  update public.pachanga_competition_match_contexts contexts set
    status='played', revision=contexts.revision+1,
    server_sequence=nextval('private.pachanga_competition_sequence'),
    updated_at=clock_timestamp()
  where contexts.id=context_row.id;
  insert into public.pachanga_competition_match_sheets(
    canonical_match_id, competition_match_context_id, created_by
  ) values (
    context_row.canonical_match_id, context_row.id,
    '63010000-0000-4000-8000-000000000001'
  );
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', home_owner, 'role', 'authenticated'
  )::text, true);
  perform public.command_pachanga_league_match_operations_v1(
    gen_random_uuid(), context_row.id,
    (select revision from public.pachanga_competition_match_contexts where id=context_row.id),
    'sporting_result.submit', jsonb_build_object(
      'entryId', context_row.home_entry_id,
      'scoreHome', score_home, 'scoreAway', score_away
    ), '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  );
  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', away_owner, 'role', 'authenticated'
  )::text, true);
  perform public.command_pachanga_league_match_operations_v1(
    gen_random_uuid(), context_row.id,
    (select revision from public.pachanga_competition_match_contexts where id=context_row.id),
    'sporting_result.accept', jsonb_build_object('entryId', context_row.away_entry_id),
    '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );
  perform public.command_pachanga_league_match_operations_v1(
    gen_random_uuid(), context_row.id,
    (select revision from public.pachanga_competition_match_contexts where id=context_row.id),
    'official_result.publish', jsonb_build_object(
      'outcome', 'MIRROR_SPORTING_RESULT',
      'reasonCode', 'r6c.test.official',
      'publicExplanation', 'Resultado eliminatorio confirmado.',
      'privateEvidence', jsonb_build_object('knockout', knockout_evidence)
    ), '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  );
  select sheets.active_official_decision_id into decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id=context_row.id;
  perform public.command_pachanga_tournament_knockout_v1(
    gen_random_uuid(),
    (select competition_id from public.pachanga_tournament_brackets where id=node_row.bracket_id),
    (select revision from public.pachanga_tournament_brackets where id=node_row.bracket_id),
    'bracket.result.advance',
    jsonb_build_object('officialDecisionId', decision_id, 'reason', 'Aplicar resultado oficial R4C'),
    '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  );
  return decision_id;
end;
$$;

-- Four different quarterfinal stories include regulation, extra time and a
-- shootout. The fourth remains ordinary so exceptional cases stay exceptional.
select pg_temp.r6c_play_node(nodes.id, case nodes.node_order
  when 1 then 'REGULATION'
  when 2 then 'EXTRA_TIME'
  when 3 then 'PENALTY_SHOOTOUT'
  else 'REGULATION' end)
from public.pachanga_tournament_bracket_nodes nodes
where nodes.round_code='QUARTERFINAL'
order by nodes.node_order;

select pg_temp.r6c_assert(
  (select count(*)=4 from public.pachanga_tournament_bracket_nodes
    where round_code='QUARTERFINAL' and status='advanced'),
  'all quarterfinals must advance from R4C official decisions'
);
select pg_temp.r6c_assert(
  (select count(*)=2 and count(distinct canonical_match_id)=2
    from public.pachanga_tournament_bracket_nodes
    where round_code='SEMIFINAL' and status='match_created'),
  'reserved semifinals must auto-generate only after both sources resolve'
);
select pg_temp.r6c_assert(
  (select count(*)=1
    from public.pachanga_tournament_knockout_result_resolutions
    where resolution_kind='PENALTY_SHOOTOUT'
      and score_after_regulation_home=1 and score_after_regulation_away=1
      and score_after_extra_time_home=1 and score_after_extra_time_away=1
      and shootout_home=5 and shootout_away=4),
  'shootout goals must remain separate from regulation and extra-time scores'
);

-- Regression R6C-PRODUCT-008: replacing a scheduled downstream match must use
-- canonical context state and never reference a non-existent MatchSheet field.
do $$
declare semifinal_id uuid;
declare old_match_id uuid;
declare replacement_response jsonb;
begin
  select nodes.id, nodes.canonical_match_id into semifinal_id, old_match_id
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.round_code='SEMIFINAL' and nodes.node_order=1;
  replacement_response := public.command_pachanga_tournament_knockout_v1(
    '65030000-0000-4000-8000-000000000005',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select revision from public.pachanga_tournament_brackets),
    'bracket.admin.replace_downstream',
    jsonb_build_object('nodeId', semifinal_id, 'reason', 'R6C scheduled replacement regression'),
    '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  );
  perform pg_temp.r6c_assert(
    (replacement_response #>> '{result,canonicalMatchId}')::uuid is distinct from old_match_id
      and (select status='retired' from public.pachanga_canonical_matches where id=old_match_id)
      and (select bool_and(status='retired')
        from public.pachanga_competition_match_contexts
        where canonical_match_id=old_match_id)
      and exists (
        select 1 from public.pachanga_tournament_bracket_node_revisions revisions
        where revisions.bracket_node_id=semifinal_id
          and revisions.canonical_match_id=old_match_id
      ),
    'scheduled replacement must preserve a valid retired match, context and node revision'
  );
end;
$$;

select pg_temp.r6c_play_node(nodes.id, 'REGULATION')
from public.pachanga_tournament_bracket_nodes nodes
where nodes.round_code='SEMIFINAL'
order by nodes.node_order;

select pg_temp.r6c_assert(
  (select count(*)=1 and min(status)='match_created'
    from public.pachanga_tournament_bracket_nodes where round_code='FINAL'),
  'the reserved final must auto-generate after both semifinal winners resolve'
);

select pg_temp.r6c_play_node(nodes.id, 'PENALTY_SHOOTOUT')
from public.pachanga_tournament_bracket_nodes nodes
where nodes.round_code='FINAL';

insert into r6c_test_state values (
  'completion_expected',
  jsonb_build_object('revision', (select revision from public.pachanga_tournament_brackets))
);
insert into r6c_test_state values (
  'completion',
  public.command_pachanga_tournament_knockout_v1(
    '65030000-0000-4000-8000-000000000006',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6c_test_state where key='completion_expected'),
    'tournament.completion.rebuild',
    '{"reason":"Construir snapshot canónico del campeón"}',
    '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  )
);
select pg_temp.r6c_assert(
  (select value from r6c_test_state where key='completion') =
  public.command_pachanga_tournament_knockout_v1(
    '65030000-0000-4000-8000-000000000006',
    (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
    (select (value ->> 'revision')::bigint from r6c_test_state where key='completion_expected'),
    'tournament.completion.rebuild',
    '{"reason":"Construir snapshot canónico del campeón"}',
    '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
  ),
  'completion replay must return the byte-equivalent receipt'
);

select public.command_pachanga_tournament_knockout_v1(
  '65030000-0000-4000-8000-000000000007',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select revision from public.pachanga_tournament_brackets),
  'tournament.complete',
  '{"reason":"Final oficial y cuadro sano"}',
  '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
);
select public.command_pachanga_tournament_knockout_v1(
  '65030000-0000-4000-8000-000000000008',
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select revision from public.pachanga_tournament_brackets),
  'tournament.lock',
  '{"reason":"Cierre inmutable del torneo"}',
  '{"clientVersion":"6.2.0+r6c-test","surface":"sql"}'
);

select pg_temp.r6c_assert(
  (select count(*)=7 from public.pachanga_tournament_bracket_nodes where status='advanced'),
  'every operational node must finish advanced before lock'
);
select pg_temp.r6c_assert(
  (select count(*)=7 and count(distinct source_node_id)=7
    from public.pachanga_tournament_bracket_advance_decisions),
  'each match node must own exactly one active advancement lineage'
);
select pg_temp.r6c_assert(
  (select count(*)=2 and count(distinct champion_entry_id)=1
      and bool_and((snapshot ->> 'rewardGrants')::integer=0)
    from public.pachanga_tournament_completion_snapshots),
  'completion rebuild and close may version the snapshot but must preserve one champion and zero rewards'
);
select pg_temp.r6c_assert(
  (select status='locked' and current_completion_snapshot_id is not null
    from public.pachanga_tournament_brackets),
  'completed tournament must become immutable after lock'
);
select pg_temp.r6c_assert(
  (select count(*)=0 from public.pachanga_reward_grants),
  'R6C must not grant rewards'
);

-- Authenticated clients have no direct write route to bracket evidence.
set role authenticated;
do $$
begin
  begin
    update public.pachanga_tournament_brackets set status='active';
    raise exception 'R6C_DIRECT_WRITE_UNEXPECTEDLY_SUCCEEDED';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

select 'R6C_DB_REPORT|' || jsonb_build_object(
  'nodes', (select count(*) from public.pachanga_tournament_bracket_nodes),
  'slots', (select count(*)
    from public.pachanga_tournament_bracket_node_slots slots
    where not exists (
      select 1
      from public.pachanga_tournament_bracket_node_slots newer
      where newer.bracket_node_id = slots.bracket_node_id
        and newer.side = slots.side
        and newer.slot_revision > slots.slot_revision
    )),
  'slotRevisions', (select count(*)
    from public.pachanga_tournament_bracket_node_slots),
  'knockoutMatches', (select count(*) from public.pachanga_tournament_bracket_nodes
    where canonical_match_id is not null),
  'advances', (select count(*) from public.pachanga_tournament_bracket_advance_decisions),
  'resultKinds', (select count(distinct resolution_kind)
    from public.pachanga_tournament_knockout_result_resolutions),
  'championSnapshots', (select count(*) from public.pachanga_tournament_completion_snapshots),
  'bracketStatus', (select status from public.pachanga_tournament_brackets),
  'rewardGrants', (select count(*) from public.pachanga_reward_grants)
)::text;

rollback;
