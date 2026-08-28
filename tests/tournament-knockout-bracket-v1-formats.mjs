import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { resolve } from "node:path";
import { createR6cPostgresHarness } from "./tournament-group-stage-v1-postgres-harness.mjs";

const harness = createR6cPostgresHarness("formats");
const baseDatabase = harness.databaseName("base");
const ownerId = "63010000-0000-4000-8000-000000000001";
const platformId = "63010000-0000-4000-8000-000000000090";

function literal(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function configureFormat(database, { participantCount, bracketSize, thirdPlace }) {
  const byePositions = participantCount === 14 && bracketSize === 16 ? "array[2,16]" : "array[]::integer[]";
  harness.query(database, `
    set session_replication_role=replica;
    with ranked as (
      select rows.id, row_number() over (
        order by groups.group_order, rows.group_position, rows.entry_id
      ) as qualifier_rank
      from public.pachanga_tournament_qualification_rows rows
      join public.pachanga_competition_groups groups on groups.id=rows.competition_group_id
      where rows.qualification_snapshot_id=(
        select current_qualification_snapshot_id
        from public.pachanga_tournament_group_stage_states
      )
    )
    update public.pachanga_tournament_qualification_rows rows set
      outcome=case when ranked.qualifier_rank<=${participantCount}
        then 'DIRECT_QUALIFIER' else 'ELIMINATED' end,
      target_bracket_slot=case when ranked.qualifier_rank<=${participantCount}
        then 'FORMAT-' || lpad(ranked.qualifier_rank::text, 3, '0') else null end,
      cross_group_rank=null
    from ranked where ranked.id=rows.id;

    delete from public.pachanga_tournament_bracket_slots;
    with positions as (
      select position as bracket_order,
        position=any(${byePositions}) as is_bye,
        sum(case when position=any(${byePositions}) then 0 else 1 end)
          over (order by position) as qualifier_rank
      from generate_series(1, ${bracketSize}) position
    ), qualifiers as (
      select rows.entry_id,
        row_number() over (order by groups.group_order, rows.group_position, rows.entry_id) as qualifier_rank
      from public.pachanga_tournament_qualification_rows rows
      join public.pachanga_competition_groups groups on groups.id=rows.competition_group_id
      where rows.outcome in ('DIRECT_QUALIFIER','EXTRA_QUALIFIER')
        and rows.qualification_snapshot_id=(
          select current_qualification_snapshot_id
          from public.pachanga_tournament_group_stage_states
        )
    )
    insert into public.pachanga_tournament_bracket_slots(
      id, bracket_template_id, slot_key, match_number, side, bracket_order,
      source_kind, source_draw_seed, resolved_entry_id, status, source_snapshot,
      server_sequence
    )
    select gen_random_uuid(), templates.id,
      'FORMAT-SLOT-' || lpad(positions.bracket_order::text, 3, '0'),
      ((positions.bracket_order + 1) / 2)::integer,
      case when positions.bracket_order % 2=1 then 'A' else 'B' end,
      positions.bracket_order,
      case when positions.is_bye then 'BYE' else 'DRAW_SEED' end,
      case when positions.is_bye then null else positions.qualifier_rank end,
      case when positions.is_bye then null else qualifiers.entry_id end,
      case when positions.is_bye then 'BYE' else 'RESOLVED' end,
      jsonb_build_object(
        'fixture', 'R6C_FORMAT_MATRIX',
        'bracketOrder', positions.bracket_order,
        'bye', positions.is_bye
      ), nextval('private.pachanga_competition_sequence')
    from public.pachanga_tournament_bracket_templates templates
    cross join positions
    left join qualifiers on qualifiers.qualifier_rank=positions.qualifier_rank
    where templates.id=(
      select current_bracket_template_id
      from public.pachanga_tournament_group_stage_states
    );

    update public.pachanga_tournament_bracket_templates templates set
      bracket_size=${bracketSize}, first_round_match_count=${bracketSize / 2},
      slot_count=${bracketSize},
      template_snapshot=jsonb_build_object(
        'kind','CompetitionBracketTemplate',
        'bracketSize',${bracketSize},
        'slots',(select jsonb_agg(jsonb_build_object(
          'slotKey',slots.slot_key,'sourceKind',slots.source_kind,
          'resolvedEntryId',slots.resolved_entry_id,'bracketOrder',slots.bracket_order
        ) order by slots.bracket_order) from public.pachanga_tournament_bracket_slots slots
          where slots.bracket_template_id=templates.id)
      )
    where templates.status='PUBLISHED';
    update public.pachanga_tournament_bracket_templates templates set
      checksum=encode(extensions.digest(convert_to(templates.template_snapshot::text,'UTF8'),'sha256'),'hex');

    update public.pachanga_competition_rule_revisions revisions set
      rule_document=jsonb_set(
        revisions.rule_document,
        '{knockoutPolicy}',
        private.pachanga_tournament_knockout_default_policy_v1()
          || jsonb_build_object('thirdPlaceMatchEnabled', ${thirdPlace}),
        true
      )
    where revisions.id=(select rule_revision_id from public.pachanga_tournament_group_stage_states);
    update public.pachanga_competition_rule_revisions revisions set
      checksum=encode(extensions.digest(convert_to(revisions.rule_document::text,'UTF8'),'sha256'),'hex')
    where revisions.id=(select rule_revision_id from public.pachanga_tournament_group_stage_states);
    set session_replication_role=origin;
  `, `configure ${participantCount}-of-${bracketSize} R6C fixture`);

  return JSON.parse(harness.query(database, `
    do $format$
    begin
      perform set_config('request.jwt.claims', ${literal(JSON.stringify({ sub: platformId, role: "authenticated" }))}, true);
      perform public.command_pachanga_tournament_knockout_platform_v1(
        ${literal(randomUUID())}::uuid,
        '00000000-0000-0000-0000-00000000c6c1'::uuid,
        (select revision from private.pachanga_competition_foundation_settings where singleton),
        'tournament.knockout.flags.set',
        jsonb_build_object(
          'knockoutFoundationEnabled',true,
          'knockoutMatchGenerationEnabled',true,
          'bracketProgressionEnabled',true,
          'extraTimeEnabled',true,
          'penaltyShootoutEnabled',true,
          'thirdPlaceEnabled',true,
          'completionEnabled',true,
          'reason','R6C format matrix flags'
        ),
        '{"clientVersion":"6.2.0+r6c-formats","surface":"sql"}'::jsonb
      );
      perform set_config('request.jwt.claims', ${literal(JSON.stringify({ sub: ownerId, role: "authenticated" }))}, true);
      perform public.command_pachanga_tournament_knockout_v1(
        ${literal(randomUUID())}::uuid,
        (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
        (select revision from public.pachanga_tournament_group_stage_states),
        'bracket.activate',
        '{"reason":"R6C format matrix activation"}'::jsonb,
        '{"clientVersion":"6.2.0+r6c-formats","surface":"sql"}'::jsonb
      );
    end
    $format$;
    select jsonb_build_object(
      'participantCount', ${participantCount},
      'bracketSize', brackets.bracket_size,
      'roundCount', brackets.round_count,
      'thirdPlaceEnabled', brackets.third_place_enabled,
      'nodes', (select count(*) from public.pachanga_tournament_bracket_nodes),
      'thirdPlaceNodes', (select count(*) from public.pachanga_tournament_bracket_nodes where node_kind='THIRD_PLACE'),
      'byeSlots', (select count(*) from public.pachanga_tournament_bracket_node_slots where source_kind='BYE'),
      'byeAdvances', (select count(*) from public.pachanga_tournament_bracket_advance_decisions where advance_reason='BYE'),
      'canonicalByeNodes', (select count(*)
        from public.pachanga_tournament_bracket_nodes nodes
        join public.pachanga_tournament_bracket_advance_decisions decisions
          on decisions.source_node_id=nodes.id and decisions.advance_reason='BYE'
        where nodes.status='advanced'
          and nodes.canonical_match_id is null
          and nodes.winner_entry_id is not null
          and nodes.loser_entry_id is null
          and ((nodes.home_entry_id is null) <> (nodes.away_entry_id is null))
          and nodes.winner_entry_id=coalesce(nodes.home_entry_id,nodes.away_entry_id)),
      'canonicalMatches', (select count(*) from public.pachanga_tournament_bracket_nodes where canonical_match_id is not null),
      'activeMemberships', (select count(*) from public.pachanga_competition_stage_memberships memberships
        where memberships.stage_id=brackets.knockout_stage_id and memberships.status='active')
    )::text
    from public.pachanga_tournament_brackets brackets;
  `, `activate ${participantCount}-of-${bracketSize} R6C format`));
}

try {
  harness.bootstrap(baseDatabase);
  harness.psql(baseDatabase, [
    "-Atq", "-v", "R6B_KEEP_TRANSACTION=1",
    "-f", resolve(harness.root, "tests/tournament-group-stage-v1-db.sql"),
    "-c", "commit;",
  ], "prepare committed R6B format base");

  const scenarios = [
    { name: "four", participantCount: 4, bracketSize: 4, thirdPlace: false, nodes: 3 },
    { name: "eight", participantCount: 8, bracketSize: 8, thirdPlace: false, nodes: 7 },
    { name: "sixteen", participantCount: 16, bracketSize: 16, thirdPlace: false, nodes: 15 },
    { name: "fourteen", participantCount: 14, bracketSize: 16, thirdPlace: false, nodes: 15 },
    { name: "third_place", participantCount: 8, bracketSize: 8, thirdPlace: true, nodes: 8 },
  ];
  const reports = [];
  for (const scenario of scenarios) {
    const database = harness.clone(baseDatabase, scenario.name);
    const report = configureFormat(database, scenario);
    assert.equal(report.bracketSize, scenario.bracketSize);
    assert.equal(report.roundCount, Math.log2(scenario.bracketSize));
    assert.equal(report.nodes, scenario.nodes);
    assert.equal(report.thirdPlaceEnabled, scenario.thirdPlace);
    assert.equal(report.thirdPlaceNodes, scenario.thirdPlace ? 1 : 0);
    assert.equal(report.byeSlots, scenario.bracketSize - scenario.participantCount);
    assert.equal(report.byeAdvances, scenario.bracketSize - scenario.participantCount);
    assert.equal(report.canonicalByeNodes, scenario.bracketSize - scenario.participantCount);
    assert.equal(report.canonicalMatches, 0, "activation and BYEs must not invent CanonicalMatches");
    assert.equal(report.activeMemberships, scenario.participantCount);
    reports.push(report);
  }

  const direct = JSON.parse(harness.query(baseDatabase, `
    select jsonb_build_object(
      'direct', private.pachanga_tournament_knockout_validate_policy_v1(
        private.pachanga_tournament_knockout_default_policy_v1()
        || '{"extraTimePolicy":"NO_EXTRA_TIME","penaltyShootoutPolicy":"PENALTIES_DIRECT"}'::jsonb
      ) #>> '{penaltyShootoutPolicy}',
      'none', private.pachanga_tournament_knockout_validate_policy_v1(
        private.pachanga_tournament_knockout_default_policy_v1()
        || '{"extraTimePolicy":"NO_EXTRA_TIME","penaltyShootoutPolicy":"NO_PENALTIES"}'::jsonb
      ) #>> '{penaltyShootoutPolicy}'
    )::text;
  `, "validate direct/no-penalties policies"));
  assert.deepEqual(direct, { direct: "PENALTIES_DIRECT", none: "NO_PENALTIES" });

  process.stdout.write(`R6C_FORMAT_REPORT|${JSON.stringify({ policies: direct, scenarios: reports })}\n`);
} finally {
  harness.cleanup();
}
