\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then
    raise exception '%', message;
  end if;
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text
language plpgsql
as $$
declare
  failure text;
begin
  begin
    execute statement;
    raise exception 'COMPETITION_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'COMPETITION_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.table_digest(target_table regclass)
returns text
language plpgsql
as $$
declare
  result text;
begin
  execute format(
    'select md5(coalesce(string_agg(to_jsonb(rows)::text, E''\\n'' order by to_jsonb(rows)::text), '''')) from %s rows',
    target_table
  ) into result;
  return result;
end;
$$;

create or replace function pg_temp.competition_receipt_metadata(target_operation_id uuid)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select receipts.client_metadata
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
$$;

create or replace function pg_temp.competition_receipt_count(target_operation_id uuid)
returns bigint
language sql
security definer
set search_path = pg_catalog
as $$
  select count(*)
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
$$;

create or replace function pg_temp.competition_actor_role(target_competition_id uuid, target_user_id uuid)
returns text
language sql
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_competition_actor_role_v1(target_competition_id, target_user_id);
$$;

create or replace function pg_temp.competition_entitlement_active(target_group_id uuid, target_capability text)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_competition_active_entitlement_v1(target_group_id, target_capability);
$$;

create or replace function pg_temp.competition_rule_checksum(target_document jsonb)
returns text
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_competition_rule_checksum_v1('competition_rules.v1', target_document);
$$;

insert into auth.users(id, email, raw_user_meta_data) values
  ('c1100000-0000-4000-8000-000000000001', 'competition-owner-a@example.test', '{"full_name":"Owner A"}'),
  ('c1100000-0000-4000-8000-000000000002', 'competition-admin-a@example.test', '{"full_name":"Admin A"}'),
  ('c1100000-0000-4000-8000-000000000003', 'competition-player-a@example.test', '{"full_name":"Player A"}'),
  ('c1100000-0000-4000-8000-000000000004', 'competition-owner-b@example.test', '{"full_name":"Owner B"}'),
  ('c1100000-0000-4000-8000-000000000005', 'competition-staff@example.test', '{"full_name":"Competition Staff"}'),
  ('c1100000-0000-4000-8000-000000000006', 'competition-platform-owner@example.test', '{"full_name":"Platform Owner"}'),
  ('c1100000-0000-4000-8000-000000000007', 'competition-next-owner@example.test', '{"full_name":"Next Owner"}'),
  ('c1100000-0000-4000-8000-000000000008', 'competition-platform-admin@example.test', '{"full_name":"Platform Admin"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  (
    'c1200000-0000-4000-8000-000000000001',
    'c1100000-0000-4000-8000-000000000001',
    'Competition Team A', 'CMPA101',
    '{"activeMatchId":"competition-match-a","matches":[],"players":[],"siteSettings":{},"venues":[]}'
  ),
  (
    'c1200000-0000-4000-8000-000000000002',
    'c1100000-0000-4000-8000-000000000004',
    'Competition Team B', 'CMPB101',
    '{"activeMatchId":null,"matches":[],"players":[],"siteSettings":{},"venues":[]}'
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('c1200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000001', 'owner', 'Owner A'),
  ('c1200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000002', 'admin', 'Admin A'),
  ('c1200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000003', 'player', 'Player A'),
  ('c1200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000007', 'player', 'Next Owner'),
  ('c1200000-0000-4000-8000-000000000002', 'c1100000-0000-4000-8000-000000000004', 'owner', 'Owner B');

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('c1100000-0000-4000-8000-000000000006', 'platform_owner', true),
  ('c1100000-0000-4000-8000-000000000008', 'platform_admin', true);

insert into public.pachanga_match_read_model(
  group_id, match_id, match_state, match_version, configured, lineup_closed,
  finalized, target_players, reserve_limit, score_a, score_b, source_payload_revision
) values (
  'c1200000-0000-4000-8000-000000000001', 'competition-match-a', 'finalized', 8,
  true, true, true, 14, 2, 4, 3, 8
);

insert into public.pachanga_open_matches(
  id, source_group_id, source_match_id, group_name, title, date, date_text,
  day, modality, zone, field_name, target_players, confirmed_count, open_slots,
  created_by, source_payload_revision
) values
  (
    'c1300000-0000-4000-8000-000000000001',
    'c1200000-0000-4000-8000-000000000001', 'competition-match-a',
    'Competition Team A', 'Partido proyectado', '2026-08-21 19:00:00+00',
    '21/08/2026', 'viernes', 'futbol7', 'Barcelona', 'Campo A', 14, 14, 0,
    'c1100000-0000-4000-8000-000000000001', 8
  ),
  (
    'c1300000-0000-4000-8000-000000000002',
    'c1200000-0000-4000-8000-000000000002', 'missing-group-match',
    'Competition Team B', 'Proyeccion huerfana', '2026-08-22 19:00:00+00',
    '22/08/2026', 'sabado', 'futbol7', 'Barcelona', 'Campo B', 14, 3, 11,
    'c1100000-0000-4000-8000-000000000004', 1
  );

insert into public.pachanga_team_challenges(
  id, sender_group_id, receiver_group_id, status, revision, proposal_number,
  scheduled_at, modality, field_name, field_address, last_proposed_by_group_id,
  created_by, updated_by, accepted_at
) values (
  'c1400000-0000-4000-8000-000000000001',
  'c1200000-0000-4000-8000-000000000001',
  'c1200000-0000-4000-8000-000000000002',
  'accepted', 2, 1, '2026-08-23 19:00:00+00', 'futbol7',
  'Campo Reto', 'Direccion de prueba',
  'c1200000-0000-4000-8000-000000000001',
  'c1100000-0000-4000-8000-000000000001',
  'c1100000-0000-4000-8000-000000000001', clock_timestamp()
);

insert into public.pachanga_external_matches(
  id, challenge_id, home_group_id, away_group_id, scheduled_at, modality,
  field_snapshot, state, revision, canonical_score_home, canonical_score_away
) values (
  'c1500000-0000-4000-8000-000000000001',
  'c1400000-0000-4000-8000-000000000001',
  'c1200000-0000-4000-8000-000000000001',
  'c1200000-0000-4000-8000-000000000002',
  '2026-08-23 19:00:00+00', 'futbol7', '{"name":"Campo Reto"}',
  'confirmed', 2, 2, 2
);

create temporary table r1_invariants_before(table_name text primary key, digest text);
insert into r1_invariants_before(table_name, digest)
select table_name, pg_temp.table_digest(table_name::regclass)
from (values
  ('public.pachanga_player_profiles'),
  ('public.pachanga_individual_rating_evidence'),
  ('public.pachanga_player_rating_snapshots'),
  ('public.pachanga_match_read_model'),
  ('public.pachanga_match_participants'),
  ('public.pachanga_match_scorers'),
  ('public.pachanga_external_matches'),
  ('public.pachanga_external_result_versions'),
  ('public.pachanga_external_match_participants'),
  ('public.pachanga_achievement_grants'),
  ('public.pachanga_reward_grants'),
  ('public.pachanga_player_reward_inventory'),
  ('public.pachanga_team_cosmetic_inventory'),
  ('private.pachanga_conduct_reports'),
  ('private.pachanga_moderation_cases'),
  ('public.pachanga_provincial_ranking_entries'),
  ('public.pachanga_provincial_ranking_publications'),
  ('public.pachanga_stripe_webhook_events')
) tables(table_name);

create temporary table r1_responses(label text primary key, body jsonb);
grant all on table r1_invariants_before, r1_responses to authenticated;

-- Product flags fail closed before the platform enables the staging fixture.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000001',
    'c1200000-0000-4000-8000-000000000001', 0,
    'competition.create',
    '{"name":"Disabled League","slug":"disabled-league","competitionType":"LEAGUE"}', '{}'
  )$$,
  'COMPETITION_FOUNDATION_DISABLED'
);
reset role;

-- Platform owner enables the local/staging fixture and grants the team entitlement.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000006","role":"authenticated"}', true);
insert into r1_responses values (
  'flags',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-00000000c001', 1,
    'foundation_flags.set',
    '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":true,"reason":"R1 local fixture"}',
    '{"clientVersion":"1.0.0+r1","serviceWorkerVersion":"1.0.0+r1","installedMode":"browser","surface":"competition-lab","token":"must-not-persist"}'
  )
);
insert into r1_responses values (
  'entitlement',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000003',
    'c1200000-0000-4000-8000-000000000001', 0,
    'entitlement.grant',
    '{"capability":"competition_create","reason":"R1 platform grant fixture"}',
    '{"clientVersion":"1.0.0+r1","installedMode":"browser","surface":"admin-competitions"}'
  )
);
select pg_temp.assert_true(
  not (pg_temp.competition_receipt_metadata('c1600000-0000-4000-8000-000000000002') ? 'token'),
  'Receipts must discard unknown or secret client metadata'
);

-- The canonical backfill uses exact structural relations and is repeatable.
insert into r1_responses values (
  'backfill-1',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000004',
    '00000000-0000-0000-0000-00000000c002', 2,
    'canonical.backfill', '{"reason":"R1 exact-source backfill"}', '{}'
  )
);
insert into r1_responses values (
  'backfill-2',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000005',
    '00000000-0000-0000-0000-00000000c002', 2,
    'canonical.backfill', '{"reason":"R1 repeated exact-source backfill"}', '{}'
  )
);
reset role;
select pg_temp.assert_true(
  (select body #>> '{snapshot,backfill,canonicalMatchesCreated}' from r1_responses where label = 'backfill-2') = '0',
  'A repeated canonical backfill must not create matches'
);
select pg_temp.assert_true(
  (
    select count(distinct bindings.canonical_match_id) = 1
    from public.pachanga_canonical_match_bindings bindings
    where (bindings.source_kind = 'group_match'
           and bindings.source_group_id = 'c1200000-0000-4000-8000-000000000001'
           and bindings.source_id = 'competition-match-a')
       or (bindings.source_kind = 'open_match'
           and bindings.source_group_id = 'c1200000-0000-4000-8000-000000000001'
           and bindings.source_id = 'c1300000-0000-4000-8000-000000000001')
  ),
  'An open-match projection must share the group match canonical identity'
);
select pg_temp.assert_true(
  (
    select count(distinct bindings.canonical_match_id) = 1
    from public.pachanga_canonical_match_bindings bindings
    where (bindings.source_kind = 'external_match'
           and bindings.source_id = 'c1500000-0000-4000-8000-000000000001')
       or (bindings.source_kind = 'team_challenge'
           and bindings.source_id = 'c1400000-0000-4000-8000-000000000001')
  ),
  'An accepted challenge and its external match must share one canonical identity'
);
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_canonical_match_binding_reviews reviews
    where reviews.left_source_kind = 'open_match'
      and reviews.left_source_id = 'c1300000-0000-4000-8000-000000000002'
      and reviews.reason_code = 'orphan_open_match_source'
      and reviews.review_status = 'pending'
  ),
  'An orphan or ambiguous source must enter review without being bound'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_canonical_match_bindings bindings
    where bindings.source_kind = 'open_match'
      and bindings.source_id = 'c1300000-0000-4000-8000-000000000002'
      and bindings.binding_status = 'active'
  ),
  'An orphan source must never be merged heuristically'
);

-- A platform operator can bind a reviewed source explicitly; this exercises the
-- canonical.bind branch that the automatic backfill intentionally avoids.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000006","role":"authenticated"}', true);
insert into r1_responses values (
  'manual-canonical-bind',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000034',
    '00000000-0000-0000-0000-00000000c002', 2,
    'canonical.bind',
    '{"sourceKind":"open_match","sourceGroupId":"c1200000-0000-4000-8000-000000000002","sourceId":"c1300000-0000-4000-8000-000000000002","reason":"R1 reviewed manual binding"}',
    '{"surface":"admin-competitions"}'
  )
);
reset role;
select pg_temp.assert_true(
  exists (
    select 1 from public.pachanga_canonical_match_bindings bindings
    where bindings.source_kind = 'open_match'
      and bindings.source_group_id = 'c1200000-0000-4000-8000-000000000002'
      and bindings.source_id = 'c1300000-0000-4000-8000-000000000002'
      and bindings.binding_status = 'active'
  ),
  'An explicit reviewed canonical.bind command must persist one active binding'
);
select pg_temp.assert_true(
  not (select dirty from private.pachanga_canonical_match_health_state where singleton),
  'Canonical.bind must refresh the materialized health snapshot'
);

-- Group admins, players and owners without the team entitlement cannot create.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000006',
    'c1200000-0000-4000-8000-000000000001', 1,
    'competition.create',
    '{"name":"Admin League","slug":"admin-league","competitionType":"LEAGUE"}', '{}'
  )$$,
  'COMPETITION_OWNER_REQUIRED'
);
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000003","role":"authenticated"}', true);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000007',
    'c1200000-0000-4000-8000-000000000001', 1,
    'competition.create',
    '{"name":"Player League","slug":"player-league","competitionType":"LEAGUE"}', '{}'
  )$$,
  'COMPETITION_OWNER_REQUIRED'
);
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000004","role":"authenticated"}', true);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000008',
    'c1200000-0000-4000-8000-000000000002', 0,
    'competition.create',
    '{"name":"No Entitlement League","slug":"no-entitlement-league","competitionType":"LEAGUE"}', '{}'
  )$$,
  'COMPETITION_ENTITLEMENT_REQUIRED'
);
select pg_temp.expect_failure(
  $$update public.pachanga_competition_entitlement_grants set status = 'revoked' where false$$,
  'permission denied'
);
reset role;

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000009',
    'c1200000-0000-4000-8000-000000000001', 1,
    'competition.create', '{}', '{}'
  )$$,
  'permission denied'
);
reset role;

-- Main R1 story: competition, edition, rules, structure and staff.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
insert into r1_responses values (
  'competition',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000010',
    'c1200000-0000-4000-8000-000000000001', 1,
    'competition.create',
    '{"name":"Liga Valles IQ","slug":"liga-valles-iq","competitionType":"LEAGUE","visibility":"private","reason":"R1 fixture"}',
    '{"clientVersion":"1.0.0+r1","serviceWorkerVersion":"1.0.0+r1","installedMode":"standalone","surface":"competition-lab"}'
  )
);
select pg_temp.assert_true(
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000010',
    'c1200000-0000-4000-8000-000000000001', 1,
    'competition.create',
    '{"name":"Liga Valles IQ","slug":"liga-valles-iq","competitionType":"LEAGUE","visibility":"private","reason":"R1 fixture"}',
    '{"clientVersion":"different-metadata-is-not-authority","installedMode":"browser"}'
  ) = (select body from r1_responses where label = 'competition'),
  'The same actor, operationId and intent must replay the canonical receipt'
);
select pg_temp.assert_true(
  pg_temp.competition_receipt_count('c1600000-0000-4000-8000-000000000010') = 1,
  'Idempotent replay must persist one receipt'
);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000010',
    'c1200000-0000-4000-8000-000000000001', 1,
    'competition.create',
    '{"name":"Changed Payload","slug":"changed-payload","competitionType":"LEAGUE"}', '{}'
  )$$,
  'IDEMPOTENCY_KEY_REUSED'
);

select (body #>> '{snapshot,competition,id}')::uuid as competition_id
from r1_responses where label = 'competition' \gset

insert into r1_responses values (
  'edition',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000011', :'competition_id', 1,
    'edition.create',
    '{"name":"Edicion 2026/27","seasonLabel":"2026/27","startsAt":"2026-09-01","endsAt":"2027-06-30"}', '{}'
  )
);
select (body #>> '{snapshot,editions,0,id}')::uuid as edition_id
from r1_responses where label = 'edition' \gset

insert into r1_responses values (
  'rule-set',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000012', :'competition_id', 2,
    'rule_set.create', '{"name":"Reglamento Liga F7"}', '{}'
  )
);
select (body #>> '{snapshot,ruleSets,0,id}')::uuid as rule_set_id
from r1_responses where label = 'rule-set' \gset

insert into r1_responses values (
  'staff-admin',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000013', :'competition_id', 3,
    'staff.grant',
    '{"userId":"c1100000-0000-4000-8000-000000000005","staffRole":"competition_admin"}', '{}'
  )
);
insert into r1_responses values (
  'staff-old-owner',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000014', :'competition_id', 4,
    'staff.grant',
    '{"userId":"c1100000-0000-4000-8000-000000000001","staffRole":"rules_manager"}', '{}'
  )
);

select pg_temp.assert_true(
  pg_temp.competition_rule_checksum('{"a":1,"b":2}'::jsonb)
    = pg_temp.competition_rule_checksum('{"b":2,"a":1}'::jsonb),
  'JSON key order must not change the normalized checksum'
);

insert into r1_responses values (
  'rule-revision',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000015', :'rule_set_id', 1,
    'rule_revision.create',
    jsonb_build_object(
      'schemaVersion', 'competition_rules.v1',
      'effectiveFrom', '2026-09-01T00:00:00Z',
      'effectiveScope', 'future_only',
      'reason', 'Initial R1 rules',
      'ruleDocument', '{
        "format": {"modality":"futbol7"},
        "registration": {"minimumPlayers":7,"maximumPlayers":25},
        "structure": {"stageGraph":{"nodes":[{"id":"split-1","root":true},{"id":"finals","optional":true}],"edges":[{"from":"split-1","to":"finals","order":0}]}},
        "results": {"scoringPolicy":{},"tieBreakCriteria":[]},
        "operations": {"hardAvailabilityPolicy":{"mode":"required"},"schedulePreferencePolicy":{"mode":"preferred"}},
        "discipline": {},
        "governance": {},
        "publication": {},
        "futureCapabilities": {}
      }'::jsonb
    ), '{}'
  )
);
select (body #>> '{snapshot,ruleSets,0,revisions,0,id}')::uuid as rule_revision_id
from r1_responses where label = 'rule-revision' \gset

insert into r1_responses values (
  'rule-validated',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000016', :'rule_revision_id', 1,
    'rule_revision.validate', '{}', '{}'
  )
);
insert into r1_responses values (
  'rule-published',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000017', :'rule_set_id', 2,
    'rule_revision.publish', jsonb_build_object('ruleRevisionId', :'rule_revision_id'), '{}'
  )
);
insert into r1_responses values (
  'edition-rule',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000018', :'edition_id', 1,
    'edition.assign_rule_revision', jsonb_build_object('ruleRevisionId', :'rule_revision_id'), '{}'
  )
);
insert into r1_responses values (
  'rule-frozen',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000019', :'rule_revision_id', 3,
    'rule_revision.freeze', '{}', '{}'
  )
);

insert into r1_responses values (
  'stage-1',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000020', :'edition_id', 2,
    'stage.create',
    jsonb_build_object('name','Split 1','stageType','SPLIT','stageOrder',0,'optional',false,'ruleRevisionId',:'rule_revision_id'), '{}'
  )
);
select (body #>> '{snapshot,stages,0,id}')::uuid as stage_1_id
from r1_responses where label = 'stage-1' \gset

insert into r1_responses values (
  'stage-2',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000021', :'edition_id', 3,
    'stage.create',
    jsonb_build_object('name','Finals','stageType','FINALS','stageOrder',1,'optional',true,'ruleRevisionId',:'rule_revision_id'), '{}'
  )
);
select (body #>> '{snapshot,stages,1,id}')::uuid as stage_2_id
from r1_responses where label = 'stage-2' \gset

insert into r1_responses values (
  'stage-edge',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000022', :'edition_id', 4,
    'stage_edge.create',
    jsonb_build_object('fromStageId',:'stage_1_id','toStageId',:'stage_2_id','edgeOrder',0), '{}'
  )
);
select pg_temp.expect_failure(format(
  'select public.command_pachanga_competition_foundation_v1(%L, %L, 5, %L, %L::jsonb, %L::jsonb)',
  'c1600000-0000-4000-8000-000000000023', :'edition_id', 'stage_edge.create',
  jsonb_build_object('fromStageId',:'stage_2_id','toStageId',:'stage_1_id','edgeOrder',0)::text,
  '{}'::jsonb::text
), 'STAGE_GRAPH_CYCLE');

insert into r1_responses values (
  'division',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000024', :'stage_1_id', 1,
    'division.create', '{"name":"Division 1","order":0,"levelLabel":"Nivel 1"}', '{}'
  )
);
select (body #>> '{snapshot,stages,0,divisions,0,id}')::uuid as division_id
from r1_responses where label = 'division' \gset

insert into r1_responses values (
  'group',
  public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000025', :'stage_1_id', 2,
    'group.create', jsonb_build_object('name','Grupo A','order',0,'divisionId',:'division_id'), '{}'
  )
);
select (body #>> '{snapshot,stages,0,groups,0,id}')::uuid as competition_group_id
from r1_responses where label = 'group' \gset

select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000026',
    'c1100000-0000-4000-8000-000000000001', 0,
    'edition.active', '{}', '{}'
  )$$,
  'FEATURE_NOT_AVAILABLE'
);
reset role;

-- Group membership does not leak the foundation. Explicit competition staff does.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000002","role":"authenticated"}', true);
select pg_temp.expect_failure(
  format('select public.get_pachanga_competition_foundation_snapshot_v1(%L)', :'competition_id'),
  'COMPETITION_ACCESS_DENIED'
);
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000005","role":"authenticated"}', true);
select pg_temp.assert_true(
  public.get_pachanga_competition_foundation_snapshot_v1(:'competition_id') #>> '{competition,id}' = :'competition_id',
  'Assigned competition staff must read the assigned aggregate'
);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000027',
    'c1200000-0000-4000-8000-000000000001', 2,
    'competition.create',
    '{"name":"Staff Cannot Create","slug":"staff-cannot-create","competitionType":"LEAGUE"}', '{}'
  )$$,
  'COMPETITION_OWNER_REQUIRED'
);
reset role;

-- Owner transfer keeps organization entitlements and changes the ultimate authority.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select public.transfer_pachanga_group_ownership_authoritative_v1(
  'c1200000-0000-4000-8000-000000000001',
  'c1100000-0000-4000-8000-000000000007',
  'c1600000-0000-4000-8000-000000000028',
  (select payload_revision from public.pachanga_groups where id = 'c1200000-0000-4000-8000-000000000001'),
  '{"clientVersion":"1.0.0+r1","installedMode":"browser","surface":"competition-owner-transfer"}'
);
select pg_temp.assert_true(
  pg_temp.competition_actor_role(:'competition_id', 'c1100000-0000-4000-8000-000000000001') = 'rules_manager',
  'The previous owner must keep only an explicit staff delegation'
);
select pg_temp.expect_failure(format(
  'select public.command_pachanga_competition_foundation_v1(%L, %L, 5, %L, %L::jsonb, %L::jsonb)',
  'c1600000-0000-4000-8000-000000000029', :'competition_id', 'edition.create',
  '{"name":"Old Owner Edition","seasonLabel":"old-owner"}', '{}'
), 'COMPETITION_ACCESS_DENIED');

select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000007","role":"authenticated"}', true);
select pg_temp.assert_true(
  pg_temp.competition_actor_role(:'competition_id', 'c1100000-0000-4000-8000-000000000007') = 'competition_owner',
  'The current team owner must become the competition authority'
);
select pg_temp.assert_true(
  public.get_pachanga_competition_foundation_snapshot_v1(:'competition_id') #>> '{competition,id}' = :'competition_id',
  'The new owner must read the existing competition'
);
select pg_temp.assert_true(
  pg_temp.competition_entitlement_active(
    'c1200000-0000-4000-8000-000000000001', 'competition_create'
  ),
  'The entitlement must remain attached to the organizer group after transfer'
);
reset role;

-- Frozen revisions reject mutation and deletion, including service-authority writes.
select pg_temp.expect_failure(
  format('update public.pachanga_competition_rule_revisions set rule_document = %L::jsonb where id = %L', '{"tampered":true}', :'rule_revision_id'),
  'RULE_REVISION_IMMUTABLE'
);
select pg_temp.expect_failure(
  format('delete from public.pachanga_competition_rule_revisions where id = %L', :'rule_revision_id'),
  'RULE_REVISION_IMMUTABLE'
);

-- Bind one existing canonical match to the frozen rules in laboratory context only.
select canonical_match_id as canonical_match_id
from public.pachanga_canonical_match_bindings
where source_kind = 'group_match'
  and source_group_id = 'c1200000-0000-4000-8000-000000000001'
  and source_id = 'competition-match-a'
  and binding_status = 'active' \gset

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000006","role":"authenticated"}', true);
insert into r1_responses values (
  'match-context',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000030', :'canonical_match_id', 1,
    'competition_match_context.bind',
    jsonb_build_object(
      'competitionId', :'competition_id',
      'editionId', :'edition_id',
      'stageId', :'stage_1_id',
      'divisionId', :'division_id',
      'groupId', :'competition_group_id',
      'ruleRevisionId', :'rule_revision_id',
      'reason', 'R1 laboratory context'
    ), '{}'
  )
);
select pg_temp.assert_true(
  (select body #>> '{snapshot,canonical,contexts,0,competitionId}' from r1_responses where label = 'match-context') = :'competition_id',
  'CompetitionMatchContext must refetch the canonical linked snapshot'
);

-- Revocation and expiry block only new competitions; existing history stays visible.
reset role;
select id as entitlement_id
from public.pachanga_competition_entitlement_grants
where organizer_group_id = 'c1200000-0000-4000-8000-000000000001'
  and capability = 'competition_create' and status = 'active' \gset

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000006","role":"authenticated"}', true);
insert into r1_responses values (
  'entitlement-revoked',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000031',
    'c1200000-0000-4000-8000-000000000001', 2,
    'entitlement.revoke', jsonb_build_object('entitlementId', :'entitlement_id', 'reason', 'R1 revocation fixture'), '{}'
  )
);
insert into r1_responses values (
  'entitlement-expired',
  public.command_pachanga_competition_platform_v1(
    'c1600000-0000-4000-8000-000000000032',
    'c1200000-0000-4000-8000-000000000001', 3,
    'entitlement.grant',
    '{"capability":"competition_create","validFrom":"2026-01-01T00:00:00Z","expiresAt":"2026-01-02T00:00:00Z","reason":"R1 expired fixture"}', '{}'
  )
);
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000007","role":"authenticated"}', true);
select pg_temp.expect_failure(
  $$select public.command_pachanga_competition_foundation_v1(
    'c1600000-0000-4000-8000-000000000033',
    'c1200000-0000-4000-8000-000000000001', 4,
    'competition.create',
    '{"name":"Expired Grant League","slug":"expired-grant-league","competitionType":"LEAGUE"}', '{}'
  )$$,
  'COMPETITION_ENTITLEMENT_REQUIRED'
);
select pg_temp.assert_true(
  public.get_pachanga_competition_foundation_snapshot_v1(:'competition_id') #>> '{competition,id}' = :'competition_id',
  'Revocation must not erase an existing competition or its history'
);
reset role;

-- Platform admin has the bounded global read/manage capability; moderator-style roles do not.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"c1100000-0000-4000-8000-000000000008","role":"authenticated"}', true);
select pg_temp.assert_true(
  jsonb_typeof(public.get_pachanga_platform_competition_foundation_v1(0, 50) #> '{items}') = 'array',
  'Platform admin must access the platform competition read model'
);
reset role;

-- Realtime publishes invalidation only; clients refetch the canonical read model.
select pg_temp.assert_true(
  exists (
    select 1 from pg_publication_tables publications
    where publications.pubname = 'supabase_realtime'
      and publications.schemaname = 'public'
      and publications.tablename = 'pachanga_competition_invalidations'
  ),
  'Competition invalidations must be published to Realtime'
);
select pg_temp.assert_true(
  not exists (
    select 1 from pg_publication_tables publications
    where publications.pubname = 'supabase_realtime'
      and publications.schemaname = 'public'
      and publications.tablename in (
        'pachanga_competitions', 'pachanga_competition_rule_revisions',
        'pachanga_competition_operation_receipts', 'pachanga_competition_events'
      )
  ),
  'Realtime must not expose private state or ask clients to reconstruct aggregates'
);

-- R1 must not mutate any established sporting, rating, reward, conduct, billing or ranking authority.
select pg_temp.assert_true(
  not exists (
    select 1
    from r1_invariants_before before_state
    where before_state.digest <> pg_temp.table_digest(before_state.table_name::regclass)
  ),
  'Competition R1 changed an out-of-scope authority'
);
select pg_temp.assert_true(
  (select count(*) from private.pachanga_conduct_reports) = 0
  and (select count(*) from private.pachanga_moderation_cases) = 0,
  'R1 must create zero conduct reports or cases'
);

select jsonb_build_object(
  'canonicalBackfillIdempotent', true,
  'competitionId', :'competition_id',
  'contextCanonicalMatchId', :'canonical_match_id',
  'entitlementBoundToGroup', true,
  'frozenRulesImmutable', true,
  'outOfScopeInvariantsIdentical', true,
  'realtimeInvalidationOnly', true,
  'receipts', (select count(*) from private.pachanga_competition_operation_receipts),
  'events', (select count(*) from private.pachanga_competition_events)
) as competition_foundation_db_result;

rollback;
