\set ON_ERROR_STOP on

begin;

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
declare failure text;
begin
  begin
    execute statement;
    raise exception 'LEAGUE_BETA_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'LEAGUE_BETA_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

select pg_temp.assert_true(
  not (select league_private_beta_enabled
    from private.pachanga_competition_foundation_settings where singleton),
  'Private beta must install disabled'
);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('ba010000-0000-4000-8000-000000000001', 'beta-owner@example.test', clock_timestamp(), '{"full_name":"Beta Owner"}'),
  ('ba010000-0000-4000-8000-000000000002', 'beta-platform@example.test', clock_timestamp(), '{"full_name":"Beta Platform"}'),
  ('ba010000-0000-4000-8000-000000000003', 'beta-admin@example.test', clock_timestamp(), '{"full_name":"Beta Admin"}'),
  ('ba010000-0000-4000-8000-000000000004', 'beta-other-owner@example.test', clock_timestamp(), '{"full_name":"Other Owner"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  ('ba020000-0000-4000-8000-000000000001', 'ba010000-0000-4000-8000-000000000001', 'Beta Team', 'BET101', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'),
  ('ba020000-0000-4000-8000-000000000002', 'ba010000-0000-4000-8000-000000000004', 'Other Team', 'BET102', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}');

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('ba020000-0000-4000-8000-000000000001', 'ba010000-0000-4000-8000-000000000001', 'owner', 'Beta Owner'),
  ('ba020000-0000-4000-8000-000000000001', 'ba010000-0000-4000-8000-000000000003', 'admin', 'Beta Admin'),
  ('ba020000-0000-4000-8000-000000000002', 'ba010000-0000-4000-8000-000000000004', 'owner', 'Other Owner');

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('ba010000-0000-4000-8000-000000000002', 'platform_owner', true);

select set_config(
  'request.jwt.claims',
  '{"sub":"ba010000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select pg_temp.expect_failure(
  $$select public.command_pachanga_league_private_beta_platform_v1(
    'ba030000-0000-4000-8000-000000000090',
    'ba020000-0000-4000-8000-000000000002',
    0,
    'beta.bundle.grant',
    '{"organizerKind":"TEAM","maxTeams":13,"reason":"capacity without override"}',
    '{}'
  )$$,
  'BETA_CAPACITY_LIMIT'
);

create temporary table beta_bundle_response(body jsonb);
insert into beta_bundle_response(body)
select public.command_pachanga_league_private_beta_platform_v1(
  'ba030000-0000-4000-8000-000000000001',
  'ba020000-0000-4000-8000-000000000001',
  0,
  'beta.bundle.grant',
  '{"organizerKind":"TEAM","maxTeams":12,"expiresAt":"2027-12-31T23:59:59Z","reason":"canonical SQL test"}',
  '{"clientVersion":"test","surface":"sql"}'
);

select pg_temp.assert_true(
  (select body #>> '{snapshot,bundle,status}' from beta_bundle_response) = 'active',
  'A newly effective bundle must be active in its authoritative response'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_entitlement_grants
    where bundle_id = (select (body #>> '{snapshot,bundle,bundleId}')::uuid from beta_bundle_response)) = 11,
  'The beta bundle must reuse exactly eleven canonical capability grants'
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
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  league_public_registration_enabled = false,
  league_public_calendar_enabled = false,
  league_public_standings_enabled = false,
  league_public_exception_status_enabled = false,
  league_private_beta_enabled = true,
  league_private_beta_creation_enabled = true,
  league_private_beta_public_discovery_enabled = false,
  revision = revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = 'ba010000-0000-4000-8000-000000000002',
  updated_at = clock_timestamp()
where singleton;

select set_config(
  'request.jwt.claims',
  '{"sub":"ba010000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
select pg_temp.expect_failure(
  $$select public.command_pachanga_league_private_beta_v1(
    'ba030000-0000-4000-8000-000000000091',
    'ba020000-0000-4000-8000-000000000001',
    1,
    'wizard.create',
    '{"organizerKind":"TEAM"}',
    '{}'
  )$$,
  'TEAM_OWNER_REQUIRED'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ba010000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
select pg_temp.expect_failure(
  $$select public.command_pachanga_league_private_beta_v1(
    'ba030000-0000-4000-8000-000000000092',
    'ba020000-0000-4000-8000-000000000002',
    0,
    'wizard.create',
    '{"organizerKind":"TEAM"}',
    '{}'
  )$$,
  'LEAGUE_PRIVATE_BETA_GRANT_REQUIRED'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ba010000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

create temporary table beta_wizard_response(body jsonb);
insert into beta_wizard_response(body)
select public.command_pachanga_league_private_beta_v1(
  'ba030000-0000-4000-8000-000000000002',
  'ba020000-0000-4000-8000-000000000001',
  1,
  'wizard.create',
  '{"organizerKind":"TEAM","reason":"canonical SQL test"}',
  '{"clientVersion":"test","surface":"sql"}'
);

select pg_temp.assert_true(
  (select body from beta_wizard_response) = public.command_pachanga_league_private_beta_v1(
    'ba030000-0000-4000-8000-000000000002',
    'ba020000-0000-4000-8000-000000000001',
    1,
    'wizard.create',
    '{"organizerKind":"TEAM","reason":"canonical SQL test"}',
    '{"clientVersion":"different-replay-metadata"}'
  ),
  'Idempotent replay must return the original canonical response'
);

create temporary table beta_smoke_state as
select
  (body #>> '{snapshot,wizard,id}')::uuid as wizard_id,
  1::bigint as revision
from beta_wizard_response;

select pg_temp.expect_failure(format(
  $$select public.command_pachanga_league_private_beta_v1(
    'ba030000-0000-4000-8000-000000000093',
    %L::uuid,
    0,
    'wizard.step.save',
    '{"step":1,"data":{"name":"Stale","slug":"stale-test"}}',
    '{}'
  )$$,
  (select wizard_id from beta_smoke_state)
), 'STALE_REVISION');

do $$
declare response jsonb;
declare wizard_id uuid := (select state.wizard_id from beta_smoke_state state);
declare payloads jsonb[] := array[
  '{"step":1,"data":{"name":"Liga Beta Local","slug":"liga-beta-local","description":"Prueba canónica","generalArea":"Barcelona"}}'::jsonb,
  '{"step":2,"data":{"modality":"FUTBOL_7"}}'::jsonb,
  '{"step":3,"data":{"editionName":"Temporada 2027","seasonLabel":"2027","startsAt":"2027-01-15","endsAt":"2027-11-30","timezone":"Europe/Madrid"}}'::jsonb,
  '{"step":4,"data":{"teamCap":6,"legs":1,"registrationMode":"INVITE_ONLY","registrationClosesAt":"2026-12-15T23:59:59Z"}}'::jsonb,
  '{"step":5,"data":{"minimumRosterSize":7,"maximumRosterSize":18,"credentialRequired":true,"jerseyRequired":true,"closeRequiresApprovedRosters":true}}'::jsonb,
  '{"step":6,"data":{"matchDurationMinutes":70,"requiredBufferMinutes":10,"pointsForWin":3,"pointsForDraw":1,"pointsForLoss":0,"responseDeadlineHours":48,"autoOfficialAfterConfirmation":true}}'::jsonb,
  '{"step":7,"data":{"weeklyPattern":[{"dayOfWeek":6,"startTime":"18:00"}],"venueRequired":false,"allowTbd":true,"minimumRestMinutes":1440,"useDivision":true}}'::jsonb,
  '{"step":8,"data":{"tieBreakCriteria":["POINTS","GOAL_DIFFERENCE","GOALS_FOR","WINS","PERSISTED_DRAW_LOT"],"scorerDetailPolicy":"OPTIONAL","allowUnknownScorer":false,"allowSharedPositions":true}}'::jsonb,
  '{"step":9,"data":{"postponementResponseDeadlineHours":48,"postponementDeadlinePolicy":"ESCALATE_TO_ORGANIZER","gracePeriodMinutes":15,"minimumRestHours":24,"maximumMatchDurationMinutes":180,"noShowOutcome":"NO_SHOW","noShowWinnerScore":3,"noShowLoserScore":0}}'::jsonb,
  '{"step":10,"data":{"consent":true,"acknowledgeUnavailableFeatures":true}}'::jsonb
];
declare operation_ids uuid[] := array[
  'ba030000-0000-4000-8000-000000000003',
  'ba030000-0000-4000-8000-000000000004',
  'ba030000-0000-4000-8000-000000000005',
  'ba030000-0000-4000-8000-000000000006',
  'ba030000-0000-4000-8000-000000000007',
  'ba030000-0000-4000-8000-000000000008',
  'ba030000-0000-4000-8000-000000000009',
  'ba030000-0000-4000-8000-00000000000a',
  'ba030000-0000-4000-8000-00000000000b',
  'ba030000-0000-4000-8000-00000000000c'
];
begin
  for i in 1..10 loop
    response := public.command_pachanga_league_private_beta_v1(
      operation_ids[i], wizard_id, i, 'wizard.step.save', payloads[i], '{}'
    );
  end loop;
  response := public.command_pachanga_league_private_beta_v1(
    'ba030000-0000-4000-8000-00000000000d',
    wizard_id,
    11,
    'wizard.finalize',
    '{"reason":"canonical SQL finalize"}',
    '{}'
  );
  if response #>> '{snapshot,canonical,registrationMode}' <> 'INVITE_ONLY' then
    raise exception 'Finalized competition is not invite-only';
  end if;
  if response #>> '{snapshot,canonical,editionStatus}' <> 'draft'
     or response #>> '{snapshot,nextAction}' <> 'open_registration' then
    raise exception 'LPB-017: finalize response must require canonical registration opening';
  end if;
end;
$$;

select pg_temp.assert_true(
  (select count(*) from public.pachanga_competitions
    where product_key = 'LEAGUE_PRIVATE_BETA_V1') = 1,
  'Finalize must create exactly one beta Competition'
);
select pg_temp.assert_true(
  (select count(*)
    from public.pachanga_competition_editions editions
    join public.pachanga_competitions competitions
      on competitions.id = editions.competition_id
    where competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
      and editions.registration_mode = 'INVITE_ONLY') = 1,
  'Finalize must create one invite-only Edition'
);
select pg_temp.assert_true(
  (select count(*)
    from public.pachanga_competition_editions editions
    join public.pachanga_competitions competitions
      on competitions.id = editions.competition_id
    where competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
      and editions.status = 'draft'
      and editions.registration_opens_at is null) = 1,
  'LPB-017: finalize must keep the Edition draft until registration.open'
);
select pg_temp.assert_true(
  (select count(*)
    from public.pachanga_competition_rule_revisions revisions
    join public.pachanga_competition_rule_sets rule_sets
      on rule_sets.id = revisions.rule_set_id
    join public.pachanga_competitions competitions
      on competitions.id = rule_sets.competition_id
    where competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
      and revisions.status = 'frozen'
      and revisions.rule_document #>> '{discipline,enabled}' = 'false'
      and revisions.rule_document #>> '{futureCapabilities,refereeAssignments}' = 'false') = 1,
  'Finalize must freeze one rule revision with discipline and referee assignments disabled'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_stages stages
    join public.pachanga_competition_editions editions on editions.id = stages.edition_id
    join public.pachanga_competitions competitions on competitions.id = editions.competition_id
    where competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
      and stages.stage_type = 'LEAGUE_STAGE') = 1,
  'Beta must create one League stage and no tournament graph'
);

select pg_temp.expect_failure(
  $$update private.pachanga_competition_foundation_settings
    set league_public_calendar_enabled = true where singleton$$,
  'LEAGUE_PRIVATE_BETA_PUBLIC_SURFACES_DISABLED|private_beta_public_check'
);
select pg_temp.expect_failure(
  $$update private.pachanga_referee_foundation_settings
    set referee_assignments_enabled = true where singleton$$,
  'REFEREE_ASSIGNMENTS_NOT_AVAILABLE_IN_LEAGUE_BETA'
);

select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_league_private_beta_v1() -> 'competitions') = 1,
  'Owner private read model must expose the finalized League'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"ba010000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_league_private_beta_v1() -> 'competitions') = 0,
  'Unrelated owner must not see another private League'
);
select pg_temp.expect_failure(format(
  'select public.get_pachanga_league_private_beta_wizard_v1(%L::uuid)',
  (select wizard_id from beta_smoke_state)
), 'LEAGUE_BETA_WIZARD_NOT_FOUND');

select set_config(
  'request.jwt.claims',
  '{"sub":"ba010000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select pg_temp.assert_true(
  (public.get_pachanga_platform_league_private_beta_v1('', 0, 30)
    #>> '{metrics,competitions}')::integer = 1,
  'Platform health must count the canonical beta League'
);
select pg_temp.assert_true(
  (public.get_pachanga_platform_league_private_beta_v1('', 0, 30)
    #>> '{metrics,publicExposureViolations}')::integer = 0,
  'Platform health must report no public exposure'
);

select pg_temp.assert_true(
  (select count(*) from public.pachanga_player_rating_snapshots) = 0
  and (select count(*) from public.pachanga_individual_rating_evidence) = 0,
  'League onboarding must not mutate Rating V2'
);
select pg_temp.assert_true(
  (select count(*) from private.pachanga_conduct_reports) = 0
  and (select count(*) from private.pachanga_moderation_cases) = 0,
  'League onboarding must not create conduct or moderation cases'
);

rollback;
