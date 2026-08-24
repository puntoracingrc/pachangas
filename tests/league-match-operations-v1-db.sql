\set ON_ERROR_STOP on

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_strip_nulls(jsonb_build_object('sub', target_user_id, 'role', target_role))::text,
    true
  );
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'R4C_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'R4C_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.command(
  target_actor_id uuid,
  target_operation_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.actor(target_actor_id);
  return public.command_pachanga_league_match_operations_v1(
    target_operation_id,
    'c4400000-0000-4000-8000-000000000008',
    target_expected_revision,
    target_action,
    target_payload,
    jsonb_build_object(
      'clientVersion', '4.0.0+r4c-db',
      'serviceWorkerVersion', 'sw-r4c-db',
      'installedMode', 'standalone',
      'surface', 'r4c_db',
      'sessionId', 'fixture-session-not-persisted'
    )
  );
end;
$$;

create or replace function pg_temp.table_digest(target_table regclass)
returns text language plpgsql as $$
declare result text;
begin
  execute format(
    'select md5(coalesce(string_agg(to_jsonb(rows)::text, E''\n'' order by to_jsonb(rows)::text), '''')) from %s rows',
    target_table
  ) into result;
  return result;
end;
$$;

create temporary table r4c_command_timings(
  metric text not null,
  duration_ms numeric not null
);

create or replace function pg_temp.measure_query(
  statement text,
  metric_name text,
  samples integer default 20
)
returns void language plpgsql as $$
declare started_at timestamptz;
declare counter integer;
begin
  for counter in 1..samples loop
    started_at := clock_timestamp();
    execute statement;
    insert into pg_temp.r4c_command_timings(metric, duration_ms)
    values (metric_name, extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

create or replace function pg_temp.measure_rollback(
  statement text,
  metric_name text,
  samples integer default 20
)
returns void language plpgsql as $$
declare started_at timestamptz;
declare counter integer;
declare failure text;
begin
  for counter in 1..samples loop
    started_at := clock_timestamp();
    begin
      execute statement;
      raise exception 'R4C_PERFORMANCE_SAMPLE_ROLLBACK';
    exception when others then
      failure := sqlerrm;
      if failure <> 'R4C_PERFORMANCE_SAMPLE_ROLLBACK' then raise; end if;
    end;
    insert into pg_temp.r4c_command_timings(metric, duration_ms)
    values (metric_name, extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

\ir league-match-operations-v1-fixture.sql

create temporary table r4c_invariants_before(table_name text primary key, digest text not null);
insert into r4c_invariants_before(table_name, digest)
select table_name, pg_temp.table_digest(table_name::regclass)
from (values
  ('public.pachanga_player_profiles'),
  ('public.pachanga_individual_rating_evidence'),
  ('public.pachanga_player_rating_snapshots'),
  ('public.pachanga_achievement_grants'),
  ('public.pachanga_reward_grants'),
  ('public.pachanga_team_cosmetic_inventory'),
  ('private.pachanga_conduct_reports'),
  ('private.pachanga_moderation_cases'),
  ('public.pachanga_provincial_ranking_entries'),
  ('public.pachanga_stripe_webhook_events')
) tables(table_name);

do $body$
begin
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000003');
  perform pg_temp.assert_true(
    (public.get_pachanga_league_match_operations_flags_v1() ->> 'foundationEnabled')::boolean = false,
    'R4C flags were not OFF by default'
  );
  perform pg_temp.expect_failure(
    $$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4500000-0000-4000-8000-000000000001', 1, 'squad.create',
      '{"entryId":"c4200000-0000-4000-8000-000000000011"}'
    )$$,
    'LEAGUE_MATCH_OPERATIONS_DISABLED'
  );

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
    revision = revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_by = 'c4010000-0000-4000-8000-000000000001',
    updated_at = clock_timestamp()
  where singleton;
end;
$body$;

create or replace function pg_temp.prepare_played_match()
returns void language plpgsql as $$
declare current_revision bigint;
declare home_squad_id uuid;
declare away_squad_id uuid;
begin
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000003', 'c4600000-0000-4000-8000-000000000001', current_revision, 'squad.create', '{"entryId":"c4200000-0000-4000-8000-000000000011"}');
  select id into home_squad_id from public.pachanga_competition_match_squads where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008' and side = 'HOME';
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000003', 'c4600000-0000-4000-8000-000000000002', current_revision, 'squad.member.add', jsonb_build_object('squadId', home_squad_id, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000019', 'memberRole', 'STARTER', 'shirtNumber', 9, 'positionOrder', 1, 'isCaptain', true));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000003', 'c4600000-0000-4000-8000-000000000003', current_revision, 'squad.submit', jsonb_build_object('squadId', home_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000004', current_revision, 'squad.validate', jsonb_build_object('squadId', home_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000005', current_revision, 'squad.lock', jsonb_build_object('squadId', home_squad_id));

  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4600000-0000-4000-8000-000000000006', current_revision, 'squad.create', '{"entryId":"c4200000-0000-4000-8000-000000000012"}');
  select id into away_squad_id from public.pachanga_competition_match_squads where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008' and side = 'AWAY';
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4600000-0000-4000-8000-000000000007', current_revision, 'squad.member.add', jsonb_build_object('squadId', away_squad_id, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000020', 'memberRole', 'STARTER', 'shirtNumber', 10, 'positionOrder', 1, 'isCaptain', true));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4600000-0000-4000-8000-000000000008', current_revision, 'squad.submit', jsonb_build_object('squadId', away_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000009', current_revision, 'squad.validate', jsonb_build_object('squadId', away_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000010', current_revision, 'squad.lock', jsonb_build_object('squadId', away_squad_id));

  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000005', 'c4600000-0000-4000-8000-000000000011', current_revision, 'attendance.set', '{"entryId":"c4200000-0000-4000-8000-000000000011","rosterMemberId":"c4200000-0000-4000-8000-000000000019","status":"going"}');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000006', 'c4600000-0000-4000-8000-000000000012', current_revision, 'attendance.set', '{"entryId":"c4200000-0000-4000-8000-000000000012","rosterMemberId":"c4200000-0000-4000-8000-000000000020","status":"going"}');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000003', 'c4600000-0000-4000-8000-000000000013', current_revision, 'attendance.close', '{"entryId":"c4200000-0000-4000-8000-000000000011"}');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4600000-0000-4000-8000-000000000014', current_revision, 'attendance.close', '{"entryId":"c4200000-0000-4000-8000-000000000012"}');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000015', current_revision, 'match.mark_ready');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000016', current_revision, 'match.start');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4600000-0000-4000-8000-000000000017', current_revision, 'match.mark_played');
end;
$$;

do $body$
declare current_revision bigint;
begin
  select revision into current_revision
  from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure(
    $$select public.command_pachanga_league_match_operations_v1(
      'c4720000-0000-4000-8000-000000000001',
      'c4990000-0000-4000-8000-000000000001', 1,
      'squad.create', '{}'::jsonb, '{}'::jsonb
    )$$,
    'COMPETITION_MATCH_CONTEXT_NOT_FOUND'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4720000-0000-4000-8000-000000000002', %s,
      'sporting_result.submit',
      '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":1,"scoreAway":0}'
    )$sql$, current_revision),
    'R4C_RESULT_REQUIRES_PLAYED_MATCH'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000002',
      'c4720000-0000-4000-8000-000000000003', %s,
      'referee.assign', '{}'
    )$sql$, current_revision),
    'FEATURE_NOT_AVAILABLE'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000002',
      'c4720000-0000-4000-8000-000000000004', %s,
      'points_adjustment.apply', '{}'
    )$sql$, current_revision),
    'FEATURE_NOT_AVAILABLE'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000002',
      'c4720000-0000-4000-8000-000000000005', %s,
      'temporary_player.add', '{}'
    )$sql$, current_revision),
    'FEATURE_NOT_AVAILABLE'
  );
end;
$body$;

savepoint r4c_unpublished_fixture_story;
set constraints all immediate;
alter table public.pachanga_competition_schedule_items
  disable trigger guard_pachanga_schedule_item_v1;
update public.pachanga_competition_schedule_items
set status = 'validated'
where id = 'c4400000-0000-4000-8000-000000000005';
do $body$
begin
  perform pg_temp.expect_failure(
    $$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4720000-0000-4000-8000-000000000006', 1,
      'squad.create',
      '{"entryId":"c4200000-0000-4000-8000-000000000011"}'
    )$$,
    'R4C_FIXTURE_NOT_PUBLISHED'
  );
end;
$body$;
rollback to savepoint r4c_unpublished_fixture_story;

savepoint r4c_tournament_story;
update public.pachanga_competitions
set competition_type = 'TOURNAMENT'
where id = 'c4200000-0000-4000-8000-000000000001';
do $body$
begin
  perform pg_temp.expect_failure(
    $$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4720000-0000-4000-8000-000000000007', 1,
      'squad.create',
      '{"entryId":"c4200000-0000-4000-8000-000000000011"}'
    )$$,
    'FEATURE_NOT_AVAILABLE'
  );
end;
$body$;
rollback to savepoint r4c_tournament_story;

savepoint r4c_fair_play_story;
insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision,
  supersedes_revision_id, reason, created_by
)
select
  'c4200000-0000-4000-8000-000000000010', rules.rule_set_id, 2,
  rules.schema_version,
  jsonb_set(rules.rule_document, '{results,tieBreakCriteria}', '["POINTS","FAIR_PLAY"]'::jsonb),
  private.pachanga_competition_rule_checksum_v1(
    rules.schema_version,
    jsonb_set(rules.rule_document, '{results,tieBreakCriteria}', '["POINTS","FAIR_PLAY"]'::jsonb)
  ),
  clock_timestamp(), rules.effective_scope, 'frozen', 1,
  rules.id, 'R4C must fail closed without R5 discipline',
  'c4010000-0000-4000-8000-000000000002'
from public.pachanga_competition_rule_revisions rules
where rules.id = 'c4200000-0000-4000-8000-000000000003';
select pg_temp.expect_failure(
  $$select private.pachanga_league_match_policy_v1(
    'c4200000-0000-4000-8000-000000000010'
  )$$,
  'FEATURE_NOT_AVAILABLE_UNTIL_R5'
);
rollback to savepoint r4c_fair_play_story;

savepoint r4c_change_proposal_story;
select pg_temp.prepare_played_match();
do $body$
declare current_revision bigint;
declare current_result_revision_id uuid;
begin
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command(
    'c4010000-0000-4000-8000-000000000003',
    'c4700000-0000-4000-8000-000000000001', current_revision,
    'sporting_result.submit',
    '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":2,"scoreAway":1,"scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000019","goals":2}]}'
  );
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command(
    'c4010000-0000-4000-8000-000000000004',
    'c4700000-0000-4000-8000-000000000002', current_revision,
    'sporting_result.propose_change',
    '{"entryId":"c4200000-0000-4000-8000-000000000012","scoreHome":2,"scoreAway":2,"reason":"Falta un gol visitante.","scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000020","goals":2}]}'
  );
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command(
    'c4010000-0000-4000-8000-000000000003',
    'c4700000-0000-4000-8000-000000000003', current_revision,
    'sporting_result.accept',
    '{"entryId":"c4200000-0000-4000-8000-000000000011","scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000019","goals":2}]}'
  );
  select results.current_revision_id into current_result_revision_id
  from public.pachanga_competition_sporting_results results
  where results.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.assert_true(
    exists (
      select 1 from public.pachanga_competition_sporting_result_revisions revisions
      where revisions.id = current_result_revision_id
        and revisions.version = 3
        and revisions.score_home = 2
        and revisions.score_away = 2
        and revisions.revision_kind = 'ACCEPTANCE'
    )
      and (select count(*) from public.pachanga_competition_sporting_result_revisions
        where sporting_result_id = (
          select id from public.pachanga_competition_sporting_results
          where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008'
        )) = 3
      and (select count(*) from public.pachanga_competition_result_responses
        where sporting_result_id = (
          select id from public.pachanga_competition_sporting_results
          where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008'
        ) and response_kind in ('PROPOSE_CHANGE', 'ACCEPT')) = 2
      and (select status from public.pachanga_competition_match_contexts
        where id = 'c4400000-0000-4000-8000-000000000008') = 'official',
    'Change proposal did not preserve three revisions and bilateral acceptance'
  );
end;
$body$;
rollback to savepoint r4c_change_proposal_story;

savepoint r4c_dispute_story;
select pg_temp.prepare_played_match();
do $body$
declare current_revision bigint;
declare response jsonb;
declare decision_id uuid;
begin
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command(
    'c4010000-0000-4000-8000-000000000003',
    'c4710000-0000-4000-8000-000000000001', current_revision,
    'sporting_result.submit',
    '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":3,"scoreAway":2,"scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000019","goals":3}]}'
  );
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command(
    'c4010000-0000-4000-8000-000000000004',
    'c4710000-0000-4000-8000-000000000002', current_revision,
    'sporting_result.dispute',
    '{"entryId":"c4200000-0000-4000-8000-000000000012","scoreHome":3,"scoreAway":3,"reason":"El visitante reclama un tercer gol."}'
  );
  perform pg_temp.assert_true(
    (select state from public.pachanga_competition_sporting_results
      where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008') = 'disputed',
    'Dispute did not move the result to administrative review'
  );
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  response := pg_temp.command(
    'c4010000-0000-4000-8000-000000000009',
    'c4710000-0000-4000-8000-000000000003', current_revision,
    'official_result.publish',
    '{"outcome":"CORRECTED_EFFECTIVE_SCORE","scoreHome":3,"scoreAway":2,"reasonCode":"result.dispute_resolved","publicExplanation":"Resultado resuelto por la organización.","privateEvidence":{"evidenceReference":"fixture://private/dispute","privateReason":"Revisión privada de la evidencia."}}'
  );
  select sheets.active_official_decision_id into decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.assert_true(
    exists (
      select 1 from public.pachanga_competition_official_result_decisions decisions
      where decisions.id = decision_id
        and decisions.effective_score_home = 3
        and decisions.effective_score_away = 2
        and decisions.authority_role = 'competition_director'
    )
      and exists (
        select 1 from private.pachanga_competition_official_result_evidence evidence
        where evidence.official_result_decision_id = decision_id
          and evidence.evidence ->> 'evidenceReference' = 'fixture://private/dispute'
      )
      and exists (
        select 1 from public.pachanga_competition_result_responses responses
        where responses.response_kind = 'DISPUTE'
          and responses.reason_private = 'El visitante reclama un tercer gol.'
      ),
    'Administrative dispute resolution lost its authority or private evidence'
  );
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000005');
  response := public.get_pachanga_league_canonical_match_v1(
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006'
  );
  perform pg_temp.assert_true(
    response #>> '{officialResult,scoreHome}' = '3'
      and response #>> '{officialResult,scoreAway}' = '2'
      and response::text not like '%fixture://private/dispute%'
      and response::text not like '%Revisión privada de la evidencia.%',
    'Private dispute evidence leaked into the player read model'
  );
end;
$body$;
rollback to savepoint r4c_dispute_story;

do $body$
declare response jsonb;
declare replay jsonb;
declare current_revision bigint;
declare home_squad_id uuid;
declare away_squad_id uuid;
declare acceptance_revision bigint;
declare active_snapshot_id uuid;
declare initial_checksum text;
declare corrected_checksum text;
declare previous_decision_id uuid;
declare corrected_decision_id uuid;
declare annulled_decision_id uuid;
declare round_revision bigint;
begin
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  response := pg_temp.command(
    'c4010000-0000-4000-8000-000000000003',
    'c4500000-0000-4000-8000-000000000002', current_revision, 'squad.create',
    '{"entryId":"c4200000-0000-4000-8000-000000000011"}'
  );
  replay := pg_temp.command(
    'c4010000-0000-4000-8000-000000000003',
    'c4500000-0000-4000-8000-000000000002', current_revision, 'squad.create',
    '{"entryId":"c4200000-0000-4000-8000-000000000011"}'
  );
  perform pg_temp.assert_true(response = replay, 'Squad create replay did not return the same receipt');
  select id into home_squad_id from public.pachanga_competition_match_squads
  where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008' and side = 'HOME';

  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4720000-0000-4000-8000-000000000008', %s,
      'squad.create',
      '{"entryId":"c4200000-0000-4000-8000-000000000011"}'
    )$sql$, current_revision),
    'R4C_SQUAD_ALREADY_EXISTS'
  );
  perform pg_temp.expect_failure(
    $$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4500000-0000-4000-8000-000000000002', 1,
      'attendance.set', '{}'
    )$$,
    'IDEMPOTENCY_KEY_REUSED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4720000-0000-4000-8000-000000000009', %s,
      'squad.member.add',
      '{"squadId":"%s","rosterMemberId":"c4200000-0000-4000-8000-000000000020","memberRole":"STARTER","shirtNumber":8,"positionOrder":2}'
    )$sql$, current_revision, home_squad_id),
    'R4C_ROSTER_MEMBER_NOT_ELIGIBLE|R4C_SQUAD_CONTAINS_INELIGIBLE_PLAYER'
  );

  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000003', 'c4500000-0000-4000-8000-000000000003', current_revision, 'squad.member.add', jsonb_build_object('squadId', home_squad_id, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000019', 'memberRole', 'STARTER', 'shirtNumber', 9, 'positionOrder', 1, 'isCaptain', true));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000003', 'c4500000-0000-4000-8000-000000000004', current_revision, 'squad.submit', jsonb_build_object('squadId', home_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000005', current_revision, 'squad.validate', jsonb_build_object('squadId', home_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000006', current_revision, 'squad.lock', jsonb_build_object('squadId', home_squad_id));

  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4500000-0000-4000-8000-000000000007', current_revision, 'squad.create', '{"entryId":"c4200000-0000-4000-8000-000000000012"}');
  select id into away_squad_id from public.pachanga_competition_match_squads where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008' and side = 'AWAY';
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4500000-0000-4000-8000-000000000008', current_revision, 'squad.member.add', jsonb_build_object('squadId', away_squad_id, 'rosterMemberId', 'c4200000-0000-4000-8000-000000000020', 'memberRole', 'STARTER', 'shirtNumber', 10, 'positionOrder', 1, 'isCaptain', true));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4500000-0000-4000-8000-000000000009', current_revision, 'squad.submit', jsonb_build_object('squadId', away_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000010', current_revision, 'squad.validate', jsonb_build_object('squadId', away_squad_id));
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000011', current_revision, 'squad.lock', jsonb_build_object('squadId', away_squad_id));

  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_competition_match_squads where status = 'locked') = 2,
    'Both squads were not locked'
  );
  perform pg_temp.assert_true(
    not exists (
      select 1 from public.pachanga_competition_match_squad_members members
      join public.pachanga_competition_match_squad_revisions revisions on revisions.id = members.squad_revision_id
      join public.pachanga_competition_match_squads squads on squads.current_revision_id = revisions.id
      left join public.pachanga_competition_roster_members roster_members
        on roster_members.id = members.roster_member_id and roster_members.entry_id = squads.entry_id
      where roster_members.id is null
    ),
    'A locked squad contains an out-of-roster player'
  );
  perform pg_temp.measure_query(
    format('select private.pachanga_league_match_validate_squad_v1(%L::uuid)', home_squad_id),
    'squad_validation', 30
  );

  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000005', 'c4500000-0000-4000-8000-000000000012', current_revision, 'attendance.set', '{"entryId":"c4200000-0000-4000-8000-000000000011","rosterMemberId":"c4200000-0000-4000-8000-000000000019","status":"going"}');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000006', 'c4500000-0000-4000-8000-000000000013', current_revision, 'attendance.set', '{"entryId":"c4200000-0000-4000-8000-000000000012","rosterMemberId":"c4200000-0000-4000-8000-000000000020","status":"not_going"}');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000006', 'c4500000-0000-4000-8000-000000000014', current_revision, 'attendance.set', '{"entryId":"c4200000-0000-4000-8000-000000000012","rosterMemberId":"c4200000-0000-4000-8000-000000000020","status":"going"}');
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_match_participants where canonical_match_id = 'c4400000-0000-4000-8000-000000000006') = 2,
    'Attendance created duplicate participants instead of updating the authority'
  );
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000003', 'c4500000-0000-4000-8000-000000000015', current_revision, 'attendance.close', '{"entryId":"c4200000-0000-4000-8000-000000000011"}');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000004', 'c4500000-0000-4000-8000-000000000016', current_revision, 'attendance.close', '{"entryId":"c4200000-0000-4000-8000-000000000012"}');

  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000017', current_revision, 'match.mark_ready');
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000018', current_revision, 'match.start');
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_rounds where id = 'c4400000-0000-4000-8000-000000000003') = 'in_progress',
    'Starting the match did not start the round'
  );
  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command('c4010000-0000-4000-8000-000000000002', 'c4500000-0000-4000-8000-000000000019', current_revision, 'match.mark_played');

  select revision into current_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000007',
      'c4500000-0000-4000-8000-000000000020', %s,
      'sporting_result.submit',
      '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":3,"scoreAway":2}'
    )$sql$, current_revision),
    'R4C_TEAM_MATCH_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4500000-0000-4000-8000-000000000021', %s,
      'sporting_result.submit',
      '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":-1,"scoreAway":2}'
    )$sql$, current_revision),
    'R4C_SCORE_INVALID'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4720000-0000-4000-8000-000000000010', %s,
      'sporting_result.submit',
      '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":3,"scoreAway":2,"shootoutHome":4,"shootoutAway":3}'
    )$sql$, current_revision),
    'FEATURE_NOT_AVAILABLE'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4720000-0000-4000-8000-000000000011', %s,
      'sporting_result.submit',
      '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":3,"scoreAway":2,"scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000020","goals":1}]}'
    )$sql$, current_revision),
    'R4C_SCORER_NOT_IN_LOCKED_SQUAD'
  );
  perform pg_temp.measure_rollback(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000003',
      'c4900000-0000-4000-8000-000000000001', %s,
      'sporting_result.submit',
      '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":3,"scoreAway":2,"scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000019","goals":3}]}'
    )$sql$, current_revision),
    'sporting_result_submit', 30
  );
  response := pg_temp.command(
    'c4010000-0000-4000-8000-000000000003',
    'c4500000-0000-4000-8000-000000000022', current_revision,
    'sporting_result.submit',
    '{"entryId":"c4200000-0000-4000-8000-000000000011","scoreHome":3,"scoreAway":2,"scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000019","goals":3}]}'
  );
  select revision into acceptance_revision from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.measure_rollback(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000004',
      'c4900000-0000-4000-8000-000000000002', %s,
      'sporting_result.accept',
      '{"entryId":"c4200000-0000-4000-8000-000000000012","scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000020","goals":2}]}'
    )$sql$, acceptance_revision),
    'sporting_result_accept', 30
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000002',
      'c4720000-0000-4000-8000-000000000014', %s,
      'official_result.publish',
      '{"outcome":"CORRECTED_EFFECTIVE_SCORE","scoreHome":3,"scoreAway":2,"reasonCode":"premature.admin"}'
    )$sql$, acceptance_revision),
    'R4C_DISPUTED_RESULT_REQUIRED'
  );
  response := pg_temp.command(
    'c4010000-0000-4000-8000-000000000004',
    'c4500000-0000-4000-8000-000000000023', acceptance_revision,
    'sporting_result.accept',
    '{"entryId":"c4200000-0000-4000-8000-000000000012","scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000020","goals":2}]}'
  );
  replay := pg_temp.command(
    'c4010000-0000-4000-8000-000000000004',
    'c4500000-0000-4000-8000-000000000023', acceptance_revision,
    'sporting_result.accept',
    '{"entryId":"c4200000-0000-4000-8000-000000000012","scorers":[{"rosterMemberId":"c4200000-0000-4000-8000-000000000020","goals":2}]}'
  );
  perform pg_temp.assert_true(response = replay, 'Result acceptance replay diverged');

  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000008',
      'c4720000-0000-4000-8000-000000000012', %s,
      'official_result.supersede',
      '{"outcome":"CORRECTED_EFFECTIVE_SCORE","scoreHome":2,"scoreAway":2,"reasonCode":"forbidden.viewer"}'
    )$sql$, current_revision),
    'COMPETITION_RESULT_MANAGER_REQUIRED'
  );
  perform pg_temp.expect_failure(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000002',
      'c4720000-0000-4000-8000-000000000013', %s,
      'official_result.supersede',
      '{"outcome":"CORRECTED_EFFECTIVE_SCORE","scoreHome":2,"scoreAway":2,"reasonCode":"points.unsupported","pointsAdjustments":[{"entryId":"c4200000-0000-4000-8000-000000000011","delta":-1}]}'
    )$sql$, current_revision),
    'FEATURE_NOT_AVAILABLE'
  );

  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_contexts where id = 'c4400000-0000-4000-8000-000000000008') = 'official',
    'Bilateral acceptance did not make the match official'
  );
  perform pg_temp.assert_true(
    (select state from public.pachanga_competition_sporting_results where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008') = 'official',
    'Sporting result did not advance from confirmed to official'
  );
  perform pg_temp.assert_true(
    (select count(*)
      from public.pachanga_competition_match_sheets sheets
      join public.pachanga_competition_official_result_decisions decisions
        on decisions.id = sheets.active_official_decision_id
      where sheets.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008') = 1,
    'Auto official produced zero or multiple active decisions'
  );
  select current_snapshot_id into active_snapshot_id from public.pachanga_competition_standing_states
  where stage_id = 'c4200000-0000-4000-8000-000000000006';
  perform pg_temp.assert_true(active_snapshot_id is not null, 'Officialization did not materialize standings');
  perform pg_temp.assert_true(
    exists (select 1 from public.pachanga_competition_standing_rows where standing_snapshot_id = active_snapshot_id and entry_id = 'c4200000-0000-4000-8000-000000000011' and played = 1 and wins = 1 and effective_points = 3 and goals_for = 3 and goals_against = 2),
    'Home standings row is incorrect'
  );
  perform pg_temp.assert_true(
    exists (select 1 from public.pachanga_competition_standing_rows where standing_snapshot_id = active_snapshot_id and entry_id = 'c4200000-0000-4000-8000-000000000012' and played = 1 and losses = 1 and effective_points = 0 and goals_for = 2 and goals_against = 3),
    'Away standings row is incorrect'
  );
  select content_checksum into initial_checksum from public.pachanga_competition_standing_snapshots where id = active_snapshot_id;

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000005');
  response := public.get_pachanga_league_canonical_match_v1('c4200000-0000-4000-8000-000000000001', 'c4400000-0000-4000-8000-000000000006');
  perform pg_temp.assert_true(
    response #>> '{officialResult,scoreHome}' = '3'
      and response #>> '{officialResult,scoreAway}' = '2'
      and not response::text ilike '%privateEvidence%',
    'Roster player read model is wrong or leaked private evidence'
  );
  response := public.get_pachanga_league_standings_v1('c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008');
  perform pg_temp.assert_true(
    jsonb_array_length(response #> '{snapshot,rows}') = 2,
    'Authenticated standings read model has the wrong rows'
  );
  response := public.get_pachanga_public_league_standings_v1('c4200000-0000-4000-8000-000000000001', 'c4200000-0000-4000-8000-000000000006', 'c4200000-0000-4000-8000-000000000007', 'c4200000-0000-4000-8000-000000000008');
  perform pg_temp.assert_true(
    response ->> 'kind' = 'PublicLeagueStandings'
      and jsonb_array_length(response #> '{snapshot,rows}') = 2,
    'Public standings are not available under the frozen public policy'
  );

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000007');
  perform pg_temp.expect_failure(
    $$select public.get_pachanga_league_canonical_match_v1(
      'c4200000-0000-4000-8000-000000000001',
      'c4400000-0000-4000-8000-000000000006'
    )$$,
    'R4C_MATCH_ACCESS_DENIED'
  );

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  select revision into current_revision from public.pachanga_competition_standing_states where stage_id = 'c4200000-0000-4000-8000-000000000006';
  response := pg_temp.command(
    'c4010000-0000-4000-8000-000000000002',
    'c4500000-0000-4000-8000-000000000024', current_revision,
    'standings.rebuild', '{"rebuildKind":"FULL_AUDIT"}'
  );
  perform pg_temp.assert_true(
    response #>> '{snapshot,officialResult,scoreHome}' = '3'
      and (select content_checksum from public.pachanga_competition_standing_snapshots where id = (select current_snapshot_id from public.pachanga_competition_standing_states where stage_id = 'c4200000-0000-4000-8000-000000000006')) = initial_checksum,
    'Full rebuild diverged from incremental standings'
  );

  select sheets.active_official_decision_id into previous_decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008';
  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.measure_rollback(
    format($sql$select pg_temp.command(
      'c4010000-0000-4000-8000-000000000002',
      'c4900000-0000-4000-8000-000000000003', %s,
      'official_result.supersede',
      '{"outcome":"CORRECTED_EFFECTIVE_SCORE","scoreHome":2,"scoreAway":2,"reasonCode":"performance.official_decision","publicExplanation":"Correccion de rendimiento."}'
    )$sql$, current_revision),
    'official_result_decision', 30
  );
  response := pg_temp.command(
    'c4010000-0000-4000-8000-000000000002',
    'c4500000-0000-4000-8000-000000000025', current_revision,
    'official_result.supersede',
    '{"outcome":"CORRECTED_EFFECTIVE_SCORE","scoreHome":2,"scoreAway":2,"reasonCode":"result.corrected","publicExplanation":"Marcador corregido tras revisión.","privateEvidence":{"privateReason":"Evidencia de fixture no pública"}}'
  );
  select sheets.active_official_decision_id into corrected_decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008';
  select snapshots.content_checksum into corrected_checksum
  from public.pachanga_competition_standing_states states
  join public.pachanga_competition_standing_snapshots snapshots
    on snapshots.id = states.current_snapshot_id
  where states.stage_id = 'c4200000-0000-4000-8000-000000000006';
  perform pg_temp.assert_true(
    corrected_decision_id <> previous_decision_id
      and exists (
        select 1 from public.pachanga_competition_official_result_decisions decisions
        where decisions.id = corrected_decision_id
          and decisions.supersedes_decision_id = previous_decision_id
          and decisions.effective_score_home = 2
          and decisions.effective_score_away = 2
      )
      and exists (
        select 1 from public.pachanga_competition_official_result_decisions decisions
        where decisions.id = previous_decision_id
          and decisions.effective_score_home = 3
          and decisions.effective_score_away = 2
      )
      and corrected_checksum <> initial_checksum,
    'Official correction did not preserve lineage or rebuild standings'
  );
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_competition_standing_rows rows
      join public.pachanga_competition_standing_states states
        on states.current_snapshot_id = rows.standing_snapshot_id
      where states.stage_id = 'c4200000-0000-4000-8000-000000000006'
        and rows.played = 1 and rows.draws = 1 and rows.effective_points = 1) = 2,
    'Corrected draw was not reflected for both teams'
  );

  select revision into current_revision from public.pachanga_competition_match_contexts
  where id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.command(
    'c4010000-0000-4000-8000-000000000002',
    'c4500000-0000-4000-8000-000000000026', current_revision,
    'official_result.annul',
    '{"reasonCode":"result.annulled","publicExplanation":"Resultado anulado."}'
  );
  select sheets.active_official_decision_id into annulled_decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008';
  perform pg_temp.assert_true(
    exists (
      select 1 from public.pachanga_competition_official_result_decisions decisions
      where decisions.id = annulled_decision_id
        and decisions.supersedes_decision_id = corrected_decision_id
        and decisions.outcome = 'ANNULLED'
    )
      and (select count(*) from public.pachanga_competition_official_result_decisions
        where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008') = 3
      and (select count(*) from public.pachanga_competition_standing_rows rows
        join public.pachanga_competition_standing_states states
          on states.current_snapshot_id = rows.standing_snapshot_id
        where states.stage_id = 'c4200000-0000-4000-8000-000000000006'
          and rows.played = 0 and rows.effective_points = 0) = 2,
    'Annulment did not preserve lineage or remove the match from standings'
  );

  select revision into round_revision from public.pachanga_competition_rounds
  where id = 'c4400000-0000-4000-8000-000000000003';
  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response := public.command_pachanga_league_match_operations_v1(
    'c4500000-0000-4000-8000-000000000027',
    'c4400000-0000-4000-8000-000000000003', round_revision,
    'round.complete', '{}'::jsonb,
    '{"clientVersion":"4.0.0+r4c-db","serviceWorkerVersion":"sw-r4c-db","installedMode":"browser","surface":"r4c_db"}'::jsonb
  );
  replay := public.command_pachanga_league_match_operations_v1(
    'c4500000-0000-4000-8000-000000000027',
    'c4400000-0000-4000-8000-000000000003', round_revision,
    'round.complete', '{}'::jsonb,
    '{"clientVersion":"4.0.0+r4c-db","serviceWorkerVersion":"sw-r4c-db","installedMode":"browser","surface":"r4c_db"}'::jsonb
  );
  perform pg_temp.assert_true(response = replay, 'Round completion replay diverged');
  select revision into round_revision from public.pachanga_competition_rounds
  where id = 'c4400000-0000-4000-8000-000000000003';
  perform public.command_pachanga_league_match_operations_v1(
    'c4500000-0000-4000-8000-000000000028',
    'c4400000-0000-4000-8000-000000000003', round_revision,
    'round.lock', '{}'::jsonb,
    '{"clientVersion":"4.0.0+r4c-db","serviceWorkerVersion":"sw-r4c-db","installedMode":"browser","surface":"r4c_db"}'::jsonb
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_rounds
      where id = 'c4400000-0000-4000-8000-000000000003') = 'locked',
    'Official round did not complete and lock'
  );

  perform pg_temp.assert_true(
    (select count(*) from private.pachanga_competition_operation_receipts where aggregate_type = 'league_match_operations' and operation_id = 'c4500000-0000-4000-8000-000000000023') = 1,
    'Idempotent acceptance created duplicate receipts'
  );
  perform pg_temp.assert_true(
    not exists (
      select dedupe_key from public.pachanga_user_notifications
      where payload ->> 'competitionId' = 'c4200000-0000-4000-8000-000000000001'
      group by dedupe_key having count(*) > 1
    ),
    'R4C emitted duplicate notifications'
  );
  perform pg_temp.assert_true(
    not exists (
      select 1 from r4c_invariants_before baseline
      where baseline.digest <> pg_temp.table_digest(baseline.table_name::regclass)
    ),
    'R4C modified Rating, Rewards, Conduct, Billing or Ranking'
  );
end;
$body$;

set local role authenticated;
select pg_temp.actor('c4010000-0000-4000-8000-000000000007');
select pg_temp.expect_failure(
  $$insert into public.pachanga_competition_sporting_results(
    canonical_match_id, competition_match_context_id, rule_revision_id,
    proposed_by_entry_id, confirmation_policy, created_by
  ) values (
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    'c4200000-0000-4000-8000-000000000003',
    'c4200000-0000-4000-8000-000000000011',
    'BILATERAL', 'c4010000-0000-4000-8000-000000000007'
  )$$,
  'permission denied|row-level security'
);
reset role;

set local role authenticated;
select pg_temp.actor('c4010000-0000-4000-8000-000000000006');
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_competition_invalidations invalidations
    where invalidations.competition_id = 'c4200000-0000-4000-8000-000000000001'
      and invalidations.entity_type = 'standings'
      and invalidations.entity_id = 'c4200000-0000-4000-8000-000000000006'
  ),
  'Eligible away player could not read the standings invalidation'
);
reset role;

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
do $body$
declare
  archive_response jsonb;
  replay_response jsonb;
  decisions_before bigint;
  evidence_before bigint;
begin
  select count(*) into decisions_before
  from public.pachanga_competition_official_result_decisions
  where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008';
  select count(*) into evidence_before
  from private.pachanga_competition_official_result_evidence evidence
  join public.pachanga_competition_official_result_decisions decisions
    on decisions.id = evidence.official_result_decision_id
  where decisions.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008';

  archive_response := public.archive_pachanga_league_schedule_qa_v1(
    'c4500000-0000-4000-8000-000000000029',
    'c4400000-0000-4000-8000-000000000001',
    2,
    'R4B_STAGING_QA_ARCHIVE: R4C official cleanup regression',
    '{"clientVersion":"4.0.0+r4c-db","surface":"r4c_db_cleanup"}'::jsonb
  );
  replay_response := public.archive_pachanga_league_schedule_qa_v1(
    'c4500000-0000-4000-8000-000000000029',
    'c4400000-0000-4000-8000-000000000001',
    2,
    'R4B_STAGING_QA_ARCHIVE: R4C official cleanup regression',
    '{"clientVersion":"4.0.0+r4c-db","surface":"r4c_db_cleanup"}'::jsonb
  );

  perform pg_temp.assert_true(archive_response = replay_response, 'R4C QA archive replay diverged');
  perform pg_temp.assert_true(
    archive_response #>> '{snapshot,status}' = 'cancelled'
      and (archive_response #>> '{snapshot,retiredContexts}')::integer = 1
      and (archive_response #>> '{snapshot,cancelledRounds}')::integer = 1
      and (archive_response #>> '{snapshot,staleStandingStates}')::integer = 1,
    'R4C QA archive did not retire official authorities'
  );
  perform pg_temp.assert_true(
    (select status from public.pachanga_competition_match_contexts
      where id = 'c4400000-0000-4000-8000-000000000008') = 'retired'
      and (select status from public.pachanga_competition_rounds
        where id = 'c4400000-0000-4000-8000-000000000003') = 'cancelled'
      and (select health_status from public.pachanga_competition_standing_states
        where stage_id = 'c4200000-0000-4000-8000-000000000006') = 'STALE',
    'R4C QA archive left active match, round or standings authority'
  );
  perform pg_temp.assert_true(
    decisions_before = (select count(*)
      from public.pachanga_competition_official_result_decisions
      where competition_match_context_id = 'c4400000-0000-4000-8000-000000000008')
      and evidence_before = (select count(*)
        from private.pachanga_competition_official_result_evidence evidence
        join public.pachanga_competition_official_result_decisions decisions
          on decisions.id = evidence.official_result_decision_id
        where decisions.competition_match_context_id = 'c4400000-0000-4000-8000-000000000008'),
    'R4C QA archive deleted official lineage or private evidence'
  );
end;
$body$;
reset role;

do $body$
declare target_table regclass;
begin
  foreach target_table in array array[
    'public.pachanga_competition_match_squads'::regclass,
    'public.pachanga_competition_match_squad_revisions'::regclass,
    'public.pachanga_competition_match_squad_members'::regclass,
    'public.pachanga_competition_match_sheets'::regclass,
    'public.pachanga_competition_sporting_results'::regclass,
    'public.pachanga_competition_sporting_result_revisions'::regclass,
    'public.pachanga_competition_sporting_result_scorers'::regclass,
    'public.pachanga_competition_result_responses'::regclass,
    'public.pachanga_competition_official_result_decisions'::regclass,
    'private.pachanga_competition_official_result_evidence'::regclass,
    'public.pachanga_competition_standing_states'::regclass,
    'public.pachanga_competition_standing_snapshots'::regclass,
    'public.pachanga_competition_standing_rows'::regclass,
    'public.pachanga_competition_tie_break_explanations'::regclass,
    'public.pachanga_competition_persisted_draw_lots'::regclass,
    'public.pachanga_competition_standing_rebuild_receipts'::regclass
  ] loop
    perform pg_temp.assert_true(
      not has_table_privilege('authenticated', target_table, 'INSERT')
        and not has_table_privilege('authenticated', target_table, 'UPDATE')
        and not has_table_privilege('authenticated', target_table, 'DELETE'),
      format('Authenticated retained direct DML on %s', target_table)
    );
  end loop;
end;
$body$;

select pg_temp.assert_true(
  to_regclass('public.league_match') is null
    and to_regclass('public.league_attendance') is null
    and to_regclass('public.league_lineup') is null
    and to_regclass('public.league_scorer') is null
    and to_regclass('public.league_result') is null
    and to_regclass('public.league_player') is null,
  'A parallel League match authority was introduced'
);

select 'R4C_COMMAND_PERFORMANCE|' || jsonb_object_agg(metric, jsonb_build_object(
  'samples', samples,
  'p50Ms', p50,
  'p95Ms', p95,
  'maxMs', maximum
) order by metric)::text
from (
  select metric, count(*) as samples,
    round(percentile_cont(0.50) within group (order by duration_ms)::numeric, 3) as p50,
    round(percentile_cont(0.95) within group (order by duration_ms)::numeric, 3) as p95,
    round(max(duration_ms), 3) as maximum
  from pg_temp.r4c_command_timings
  group by metric
) statistics;
