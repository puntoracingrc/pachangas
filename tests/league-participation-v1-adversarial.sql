\set ON_ERROR_STOP on

-- This file runs after league-participation-v1-db.sql in the same transaction.
-- It attacks the public command surface while keeping all fixtures rollback-only.

do $$
declare
  flags_revision bigint;
  response jsonb;
  category_id uuid;
  category_revision bigint;
  protected_rating text := pg_temp.table_digest('public.pachanga_player_profiles'::regclass);
begin
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000001');
  select revision into flags_revision
  from private.pachanga_competition_foundation_settings where singleton;
  response := public.command_pachanga_league_participation_platform_v1(
    'd4300000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-00000000c4a1', flags_revision,
    '{"foundationEnabled":true,"registrationEnabled":true,"publicRegistrationEnabled":true,"delegatesEnabled":true,"rostersEnabled":true,"schedulePreferencesEnabled":true,"reason":"Adversarial R4A transaction"}'::jsonb,
    '{"clientVersion":"4.0.0+r4a-adversarial","installedMode":"browser","surface":"r4a_adversarial"}'::jsonb
  );

  insert into public.pachanga_competition_editions(
    id, competition_id, name, season_label, starts_at, ends_at,
    status, rule_revision_id, revision, created_by
  ) values (
    'd4070000-0000-4000-8000-000000000004',
    'd4040000-0000-4000-8000-000000000001',
    'R4A Adversarial Edition', '2029', '2029-01-01', '2029-12-31',
    'draft', 'd4060000-0000-4000-8000-000000000001', 1,
    'd4010000-0000-4000-8000-000000000003'
  );

  response := public.command_pachanga_league_participation_v1(
    'd4300000-0000-4000-8000-000000000002',
    'd4070000-0000-4000-8000-000000000004', 1, 'category.create',
    '{
      "name":"Adversarial Open",
      "slug":"adversarial-open",
      "sportFormat":"FOOTBALL_7",
      "visibility":"public",
      "ruleRevisionId":"d4060000-0000-4000-8000-000000000001",
      "reason":"Unknown authority fields must be ignored",
      "actorId":"d4010000-0000-4000-8000-000000000008",
      "rating":100,
      "facets":{"pace":100},
      "service_role":"forged",
      "evidenceReference":"vault://must-not-persist",
      "snapshot":{"status":"active"}
    }'::jsonb,
    '{
      "clientVersion":"4.0.0+r4a-adversarial",
      "serviceWorkerVersion":"sw-r4a-adversarial",
      "installedMode":"standalone",
      "surface":"r4a_adversarial",
      "email":"private@example.test",
      "token":"secret-token",
      "actorId":"d4010000-0000-4000-8000-000000000008",
      "service_role":"forged"
    }'::jsonb
  );
  category_id := (response #>> '{snapshot,id}')::uuid;
  category_revision := (response #>> '{snapshot,revision}')::bigint;

  perform pg_temp.assert_true(
    category_id is not null
    and response #>> '{snapshot,status}' = 'draft'
    and response::text not like '%vault://must-not-persist%'
    and response::text not like '%private@example.test%'
    and response::text not like '%secret-token%'
    and response::text not like '%"rating"%'
    and response::text not like '%"facets"%',
    'Client-only authority fields changed or leaked into the canonical response'
  );
  perform pg_temp.assert_true(
    (select actor_id from private.pachanga_competition_events
      where operation_id = 'd4300000-0000-4000-8000-000000000002')
      = 'd4010000-0000-4000-8000-000000000001'
    and (select client_metadata from private.pachanga_competition_operation_receipts
      where operation_id = 'd4300000-0000-4000-8000-000000000002')
      = '{"clientVersion":"4.0.0+r4a-adversarial","serviceWorkerVersion":"sw-r4a-adversarial","installedMode":"standalone","surface":"r4a_adversarial"}'::jsonb,
    'Server actor resolution or client metadata sanitization is not authoritative'
  );
  perform pg_temp.assert_true(
    not exists (
      select 1 from private.pachanga_competition_credential_evidence
      where evidence_reference = 'vault://must-not-persist'
    ),
    'Unknown evidence input reached protected credential storage'
  );

  perform pg_temp.actor('d4010000-0000-4000-8000-000000000008');
  perform pg_temp.expect_failure(
    format(
      'select public.command_pachanga_league_participation_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
      'd4300000-0000-4000-8000-000000000003', category_id,
      category_revision, 'category.activate', '{"reason":"outsider"}',
      '{"clientVersion":"4.0.0+r4a-adversarial"}'
    ),
    'COMPETITION_CATEGORY_MANAGER_REQUIRED'
  );

  perform pg_temp.actor('d4010000-0000-4000-8000-000000000001');
  perform pg_temp.expect_failure(
    format(
      'select public.command_pachanga_league_participation_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
      'd4300000-0000-4000-8000-000000000004', category_id,
      category_revision + 99, 'category.activate', '{"reason":"stale"}',
      '{"clientVersion":"4.0.0+r4a-adversarial"}'
    ),
    'STALE_REVISION'
  );

  insert into public.pachanga_competition_rule_sets(
    id, competition_id, name, status, created_by
  ) values (
    'd4050000-0000-4000-8000-000000000099',
    'd4040000-0000-4000-8000-000000000002',
    'Foreign adversarial rules', 'draft',
    'd4010000-0000-4000-8000-000000000003'
  );
  insert into public.pachanga_competition_rule_revisions(
    id, rule_set_id, version, schema_version, rule_document, checksum,
    effective_from, effective_scope, status, revision, reason, created_by
  ) select
    'd4060000-0000-4000-8000-000000000099',
    'd4050000-0000-4000-8000-000000000099', 1,
    revisions.schema_version, revisions.rule_document, revisions.checksum,
    clock_timestamp(), 'future_only', 'published', 1,
    'Foreign rule revision for adversarial scope test',
    'd4010000-0000-4000-8000-000000000003'
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id = 'd4060000-0000-4000-8000-000000000001';
  perform pg_temp.expect_failure(
    $sql$select public.command_pachanga_league_participation_v1(
      'd4300000-0000-4000-8000-000000000005',
      'd4070000-0000-4000-8000-000000000004', 2, 'category.create',
      '{"name":"Foreign rules","slug":"foreign-rules","sportFormat":"FOOTBALL_7","ruleRevisionId":"d4060000-0000-4000-8000-000000000099","reason":"foreign rule attack"}'::jsonb,
      '{"clientVersion":"4.0.0+r4a-adversarial"}'::jsonb
    )$sql$,
    'RULE_REVISION_SCOPE_MISMATCH'
  );

  perform pg_temp.assert_true(
    pg_temp.table_digest('public.pachanga_player_profiles'::regclass) = protected_rating,
    'Adversarial R4A inputs modified universal profiles or Rating V2'
  );
end;
$$;

set local role authenticated;
select pg_temp.actor('d4010000-0000-4000-8000-000000000008');
select pg_temp.expect_failure(
  $$select evidence_reference from private.pachanga_competition_credential_evidence$$,
  'permission denied'
);
select pg_temp.expect_failure(
  $$select private.pachanga_league_store_command_v1(
    gen_random_uuid(), auth.uid(), 'forged', 'competition_entry', gen_random_uuid(),
    'd4040000-0000-4000-8000-000000000001', null, null, 1, 1,
    'forged', repeat('0',64), '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, clock_timestamp()
  )$$,
  'permission denied'
);
reset role;

set local role service_role;
select pg_temp.actor(null, 'service_role');
select pg_temp.expect_failure(
  $$select public.command_pachanga_league_participation_v1(
    'd4300000-0000-4000-8000-000000000006',
    'd4070000-0000-4000-8000-000000000004', 1, 'category.create',
    '{"name":"Service spoof","slug":"service-spoof","sportFormat":"FOOTBALL_7","ruleRevisionId":"d4060000-0000-4000-8000-000000000001","actorId":"d4010000-0000-4000-8000-000000000001"}'::jsonb,
    '{"clientVersion":"4.0.0+r4a-adversarial"}'::jsonb
  )$$,
  'permission denied|Authentication required'
);
reset role;

do $$
declare flags_revision bigint;
begin
  perform pg_temp.actor('d4010000-0000-4000-8000-000000000001');
  select revision into flags_revision
  from private.pachanga_competition_foundation_settings where singleton;
  perform public.command_pachanga_league_participation_platform_v1(
    'd4300000-0000-4000-8000-000000000007',
    '00000000-0000-0000-0000-00000000c4a1', flags_revision,
    '{"foundationEnabled":false,"registrationEnabled":false,"publicRegistrationEnabled":false,"delegatesEnabled":false,"rostersEnabled":false,"schedulePreferencesEnabled":false,"reason":"End adversarial R4A transaction"}'::jsonb,
    '{"clientVersion":"4.0.0+r4a-adversarial","surface":"r4a_adversarial"}'::jsonb
  );
  perform pg_temp.expect_failure(
    $sql$select public.command_pachanga_league_participation_v1(
      'd4300000-0000-4000-8000-000000000008',
      'd4070000-0000-4000-8000-000000000004', 1, 'registration.open',
      '{}'::jsonb, '{"clientVersion":"4.0.0+r4a-adversarial"}'::jsonb
    )$sql$,
    'LEAGUE_PARTICIPATION_DISABLED'
  );
  perform pg_temp.assert_true(
    not exists (
      select 1 from private.pachanga_competition_foundation_settings settings
      where settings.league_participation_foundation_enabled
        or settings.league_registration_enabled
        or settings.league_public_registration_enabled or settings.league_delegates_enabled
        or settings.league_rosters_enabled or settings.league_schedule_preferences_enabled
    ),
    'Adversarial suite did not restore all R4A flags OFF'
  );
end;
$$;
