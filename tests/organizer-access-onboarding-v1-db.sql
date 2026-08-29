\set ON_ERROR_STOP on

do $permissions$
declare target_role text;
begin
  foreach target_role in array array['authenticated', 'anon', 'service_role'] loop
    if not has_schema_privilege(target_role, 'auth', 'USAGE') then
      execute format('grant usage on schema auth to %I', target_role);
    end if;
    if not has_function_privilege(target_role, 'auth.uid()', 'EXECUTE') then
      execute format('grant execute on function auth.uid() to %I', target_role);
    end if;
    if not has_function_privilege(target_role, 'auth.jwt()', 'EXECUTE') then
      execute format('grant execute on function auth.jwt() to %I', target_role);
    end if;
  end loop;
end;
$permissions$;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', target_role)::text, true);
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'WAVE8A_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'WAVE8A_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create temporary table wave8a_state(
  club_application_id uuid,
  club_application_revision bigint,
  club_create_response jsonb,
  suspended_application_id uuid,
  suspended_application_revision bigint,
  team_application_id uuid,
  team_application_revision bigint,
  onboarding_id uuid,
  transferred_application_id uuid,
  transferred_application_revision bigint,
  transferred_onboarding_id uuid,
  transferred_onboarding_revision bigint,
  launch_response jsonb,
  reconsidered_application_id uuid,
  reconsidered_application_revision bigint
);
insert into wave8a_state default values;
grant all on table wave8a_state to authenticated, service_role;

select pg_temp.assert_true(
  not applications_enabled and not submission_enabled and not review_enabled
    and not partnership_approval_enabled and not onboarding_enabled
    and not first_competition_launcher_enabled and not demo_world_v30_enabled,
  'Wave 8A flags must install OFF'
) from private.pachanga_organizer_access_settings_v1 where singleton;

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'private.pachanga_organizer_access_applications_v1', 'SELECT')
    and not has_table_privilege('authenticated', 'private.pachanga_organizer_access_applications_v1', 'INSERT')
    and has_function_privilege('authenticated',
      'public.command_pachanga_organizer_access_application_v1(uuid,uuid,bigint,text,jsonb,jsonb)', 'EXECUTE'),
  'Clients must use the command RPC and never private tables'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
select public.command_pachanga_organizer_access_application_v1(
  '8a100000-0000-4000-8000-000000000001',
  '8a000000-0000-4000-8000-000000000099', 1, 'settings.flags',
  '{
    "applicationsEnabled":true,"submissionEnabled":true,"reviewEnabled":true,
    "partnershipApprovalEnabled":true,"onboardingEnabled":true,
    "firstCompetitionLauncherEnabled":true,"demoWorldV30Enabled":true,
    "reason":"Wave 8A local activation"
  }', '{"clientVersion":"8.0.0+db","serviceWorkerVersion":"sw-wave8a","displayMode":"browser","surface":"wave8a_db","secret":"discard"}'
);
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
select public.command_pachanga_organizer_access_application_v1(
  '8a100000-0000-4000-8000-000000000002',
  '8a000000-0000-4000-8000-000000000098', 0, 'rate_limit.override',
  '{
    "organizerKind":"TEAM",
    "organizerId":"8a000000-0000-4000-8000-000000000010",
    "actionPattern":"application.*",
    "validUntil":"2027-01-01T00:00:00Z",
    "reason":"Wave 8A wildcard regression"
  }', '{"clientVersion":"8.0.0+db","surface":"platform_control_center"}'
);
reset role;

select pg_temp.assert_true(
  exists (
    select 1 from private.pachanga_organizer_access_rate_limit_overrides_v1 overrides
    where overrides.organizer_group_id = '8a000000-0000-4000-8000-000000000010'
      and overrides.action_pattern = 'application.*'
  ),
  'W8A-001: the canonical wildcard rate-limit override must be persistable'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000002');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_access_application_v1(%L,%L,0,%L,%L::jsonb,%L::jsonb)',
  gen_random_uuid(), '8a000000-0000-4000-8000-000000000020', 'application.create',
  '{"organizerKind":"CLUB","planCode":"CLUB_PARTNER"}', '{}'
), 'AUTHORITY_REQUIRED');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000001');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_access_application_v1(%L,%L,0,%L,%L::jsonb,%L::jsonb)',
  '8a100000-0000-4000-8000-000000000003', '8a000000-0000-4000-8000-000000000010',
  'application.create', '{"organizerKind":"TEAM","planCode":"CLUB_PARTNER"}', '{}'
), 'PLAN_NOT_AVAILABLE');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000004');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_access_application_v1(%L,%L,0,%L,%L::jsonb,%L::jsonb)',
  '8a100000-0000-4000-8000-000000000004', '8a000000-0000-4000-8000-000000000020',
  'application.create', '{"organizerKind":"CLUB","planCode":"TEAM_ORGANIZER_PRO"}', '{}'
), 'PLAN_NOT_AVAILABLE');
with created as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000005',
    '8a000000-0000-4000-8000-000000000021', 0, 'application.create',
    '{"organizerKind":"CLUB","planCode":"CLUB_PARTNER","summary":"Suspended Club negative test","reason":"Suspended Club draft"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body
)
update wave8a_state set
  suspended_application_id = (created.body ->> 'aggregateId')::uuid,
  suspended_application_revision = (created.body ->> 'confirmedRevision')::bigint
from created;
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_access_application_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
  '8a100000-0000-4000-8000-000000000006',
  (select suspended_application_id from wave8a_state),
  (select suspended_application_revision from wave8a_state),
  'application.submit', '{"consent":true,"reason":"Suspended Club must fail"}', '{}'
), 'CLUB_MUST_BE_ACTIVE');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000004');
with created as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000010',
    '8a000000-0000-4000-8000-000000000020', 0, 'application.create',
    '{
      "organizerKind":"CLUB","planCode":"CLUB_PARTNER","intent":"BOTH",
      "competitionType":"BOTH","teamCount":12,"targetStartDate":"2026-10-15",
      "municipality":"Terrassa","area":"Vallès Occidental",
      "fieldRelationship":"Acuerdo estable con dos campos",
      "summary":"Queremos organizar una liga y un torneo piloto.","reason":"Club partner application"
    }', '{"clientVersion":"8.0.0+db","serviceWorkerVersion":"sw-wave8a","displayMode":"standalone","surface":"organizer_access"}'
  ) body
)
update wave8a_state set
  club_application_id = (created.body ->> 'aggregateId')::uuid,
  club_application_revision = (created.body ->> 'confirmedRevision')::bigint,
  club_create_response = created.body
from created;

select pg_temp.assert_true(
  (public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000009',
    '8a000000-0000-4000-8000-000000000020', 0, 'application.create',
    '{
      "organizerKind":"CLUB","planCode":"CLUB_PARTNER","intent":"BOTH",
      "competitionType":"BOTH","teamCount":12,"targetStartDate":"2026-10-15",
      "municipality":"Terrassa","area":"Vallès Occidental",
      "fieldRelationship":"Acuerdo estable con dos campos",
      "summary":"Queremos organizar una liga y un torneo piloto.","reason":"Duplicate active application"
    }', '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) ->> 'aggregateId')::uuid = (select club_application_id from wave8a_state),
  'Different operation IDs must converge on the same active application'
);

select pg_temp.assert_true(
  public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000010',
    '8a000000-0000-4000-8000-000000000020', 0, 'application.create',
    '{
      "organizerKind":"CLUB","planCode":"CLUB_PARTNER","intent":"BOTH",
      "competitionType":"BOTH","teamCount":12,"targetStartDate":"2026-10-15",
      "municipality":"Terrassa","area":"Vallès Occidental",
      "fieldRelationship":"Acuerdo estable con dos campos",
      "summary":"Queremos organizar una liga y un torneo piloto.","reason":"Club partner application"
    }', '{"clientVersion":"8.0.0+db","serviceWorkerVersion":"sw-wave8a","displayMode":"standalone","surface":"organizer_access"}'
  ) = (select club_create_response from wave8a_state),
  'Exact replay must return the stored canonical response'
);

with submitted as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000011', club_application_id,
    club_application_revision, 'application.submit',
    '{"consent":true,"reason":"Submit complete application"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body from wave8a_state
)
update wave8a_state set club_application_revision = (submitted.body ->> 'confirmedRevision')::bigint from submitted;
reset role;

select pg_temp.assert_true(
  (select count(*) = 1 from private.pachanga_organizer_access_applications_v1 applications
    where applications.organizer_club_id = '8a000000-0000-4000-8000-000000000020'
      and applications.requested_plan_code = 'CLUB_PARTNER'
      and applications.status in ('draft','submitted','under_review','needs_information')),
  'Different operation IDs must leave one active application row'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000002');
select pg_temp.expect_failure(format(
  'select public.get_pachanga_organizer_access_application_v1(%L)',
  (select club_application_id from wave8a_state)
), 'AUTHORITY_REQUIRED');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
with reviewed as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000012', club_application_id,
    club_application_revision, 'review.start', '{"reason":"Begin independent review"}',
    '{"clientVersion":"8.0.0+db","surface":"platform_control_center"}'
  ) body from wave8a_state
)
update wave8a_state set club_application_revision = (reviewed.body ->> 'confirmedRevision')::bigint from reviewed;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000005');
with requested as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000013', club_application_id,
    club_application_revision, 'review.request_information',
    '{"message":"Confirma la disponibilidad del campo principal.","privateNote":"Validar documento en revisión manual.","reason":"Need field confirmation"}',
    '{"clientVersion":"8.0.0+db","surface":"platform_control_center"}'
  ) body from wave8a_state
)
update wave8a_state set club_application_revision = (requested.body ->> 'confirmedRevision')::bigint from requested;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000004');
select pg_temp.assert_true(
  public.get_pachanga_organizer_access_application_v1((select club_application_id from wave8a_state))::text
    !~ 'Validar documento',
  'Applicant read model must not disclose private review notes'
);
with answered as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000014', club_application_id,
    club_application_revision, 'application.respond_information',
    '{"message":"El campo principal está confirmado por toda la temporada.","consent":true,"reason":"Provide requested evidence"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body from wave8a_state
)
update wave8a_state set club_application_revision = (answered.body ->> 'confirmedRevision')::bigint from answered;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
with approved as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000015', club_application_id,
    club_application_revision, 'review.approve',
    '{"decisionCode":"PARTNERSHIP_APPROVED","message":"Club colaborador aprobado.","privateNote":"Evidence reviewed.","reason":"Approve audited Club partnership"}',
    '{"clientVersion":"8.0.0+db","surface":"platform_control_center"}'
  ) body from wave8a_state
)
update wave8a_state set
  club_application_revision = (approved.body ->> 'confirmedRevision')::bigint,
  onboarding_id = (approved.body #>> '{snapshot,onboarding,id}')::uuid
from approved;
reset role;

select pg_temp.assert_true(
  (select status = 'approved' from private.pachanga_organizer_access_applications_v1 where id = (select club_application_id from wave8a_state))
    and (select count(*) = 1 from private.pachanga_organizer_access_grants_v1 grants
      where grants.organizer_access_decision_id is not null and grants.status = 'active'
        and grants.organizer_club_id = '8a000000-0000-4000-8000-000000000020')
    and (select count(*) = 20 from public.pachanga_competition_entitlement_grants grants
      where grants.organizer_club_id = '8a000000-0000-4000-8000-000000000020'
        and grants.billing_access_grant_id is not null and grants.status = 'active')
    and (select onboarding_id is not null from wave8a_state),
  'Approval must atomically create one access grant, project capabilities and open onboarding'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000005');
select pg_temp.assert_true(
  jsonb_array_length(public.get_pachanga_platform_organizer_access_v1(null,null,50) -> 'applications') >= 1,
  'Support may read the review queue'
);
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_access_application_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
  gen_random_uuid(), (select club_application_id from wave8a_state),
  (select club_application_revision from wave8a_state), 'review.approve',
  '{"reason":"support bypass"}', '{}'
), 'CAPABILITY');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000001');
with created as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000020',
    '8a000000-0000-4000-8000-000000000010', 0, 'application.create',
    '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","intent":"LEAGUE","competitionType":"LEAGUE","teamCount":10,"summary":"Interés en organizar una liga.","reason":"Paid plan interest"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body
)
update wave8a_state set
  team_application_id = (created.body ->> 'aggregateId')::uuid,
  team_application_revision = (created.body ->> 'confirmedRevision')::bigint
from created;
with submitted as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000021', team_application_id,
    team_application_revision, 'application.submit', '{"consent":true,"reason":"Submit paid interest"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body from wave8a_state
)
update wave8a_state set team_application_revision = (submitted.body ->> 'confirmedRevision')::bigint from submitted;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
with reviewed as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000022', team_application_id,
    team_application_revision, 'review.start', '{"reason":"Review paid plan interest"}', '{}'
  ) body from wave8a_state
)
update wave8a_state set team_application_revision = (reviewed.body ->> 'confirmedRevision')::bigint from reviewed;
with approved as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000023', team_application_id,
    team_application_revision, 'review.approve',
    '{"decisionCode":"PAID_INTEREST_RECORDED","message":"Interés registrado.","reason":"No live commercial grant"}', '{}'
  ) body from wave8a_state
)
update wave8a_state set team_application_revision = (approved.body ->> 'confirmedRevision')::bigint from approved;
reset role;

select pg_temp.assert_true(
  (select status = 'approved_interest' from private.pachanga_organizer_access_applications_v1 where id = (select team_application_id from wave8a_state))
    and (select count(*) = 0 from private.pachanga_organizer_access_grants_v1 grants
      where grants.organizer_group_id = '8a000000-0000-4000-8000-000000000010'),
  'Paid-plan interest must never create an entitlement without an explicit non-subscription grant'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000006');
select pg_temp.expect_failure(format(
  'select public.get_pachanga_organizer_access_application_v1(%L)',
  (select team_application_id from wave8a_state)
), 'AUTHORITY_REQUIRED');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000001');
select public.transfer_pachanga_group_ownership_authoritative_v1(
  '8a000000-0000-4000-8000-000000000010',
  '8a000000-0000-4000-8000-000000000006',
  '8a100000-0000-4000-8000-000000000024',
  (select payload_revision from public.pachanga_groups where id = '8a000000-0000-4000-8000-000000000010'),
  '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
);
select pg_temp.expect_failure(format(
  'select public.get_pachanga_organizer_access_application_v1(%L)',
  (select team_application_id from wave8a_state)
), 'AUTHORITY_REQUIRED');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000006');
select pg_temp.assert_true(
  public.get_pachanga_organizer_access_application_v1((select team_application_id from wave8a_state)) ->> 'status' = 'approved_interest',
  'The new Team owner must see organizer-owned application history'
);
with created as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000025',
    '8a000000-0000-4000-8000-000000000010', 0, 'application.create',
    '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","intent":"LEAGUE","competitionType":"LEAGUE","teamCount":10,"summary":"Nueva solicitud tras transferencia de owner.","reason":"New owner application"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body
)
update wave8a_state set
  transferred_application_id = (created.body ->> 'aggregateId')::uuid,
  transferred_application_revision = (created.body ->> 'confirmedRevision')::bigint
from created;
with submitted as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000026', transferred_application_id,
    transferred_application_revision, 'application.submit',
    '{"consent":true,"reason":"New owner submits"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body from wave8a_state
)
update wave8a_state set transferred_application_revision = (submitted.body ->> 'confirmedRevision')::bigint from submitted;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
with reviewed as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000027', transferred_application_id,
    transferred_application_revision, 'review.start', '{"reason":"Review transferred owner application"}', '{}'
  ) body from wave8a_state
)
update wave8a_state set transferred_application_revision = (reviewed.body ->> 'confirmedRevision')::bigint from reviewed;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000008');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_access_application_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
  '8a100000-0000-4000-8000-000000000028',
  (select transferred_application_id from wave8a_state),
  (select transferred_application_revision from wave8a_state),
  'review.approve',
  '{"grantPlanCode":"PRIVATE_BETA","grantSource":"PRIVATE_BETA","reason":"Finance must not approve"}', '{}'
), 'CAPABILITY');
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
with approved as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000029', transferred_application_id,
    transferred_application_revision, 'review.approve',
    '{
      "decisionCode":"PRIVATE_BETA_APPROVED","grantPlanCode":"PRIVATE_BETA",
      "grantSource":"PRIVATE_BETA","validUntil":"2027-12-31T23:59:59Z",
      "message":"Beta temporal aprobada.","reason":"Explicit private beta decision"
    }', '{"clientVersion":"8.0.0+db","surface":"platform_control_center"}'
  ) body from wave8a_state
)
update wave8a_state set
  transferred_application_revision = (approved.body ->> 'confirmedRevision')::bigint,
  transferred_onboarding_id = (approved.body #>> '{snapshot,onboarding,id}')::uuid,
  transferred_onboarding_revision = (approved.body #>> '{snapshot,onboarding,revision}')::bigint
from approved;
reset role;

select pg_temp.assert_true(
  (select count(*) = 1 from private.pachanga_organizer_access_grants_v1 grants
    join public.pachanga_organizer_plan_revisions revisions on revisions.id = grants.plan_revision_id
    join public.pachanga_organizer_plan_catalog plans on plans.id = revisions.plan_id
    where grants.organizer_group_id = '8a000000-0000-4000-8000-000000000010'
      and plans.plan_code = 'PRIVATE_BETA' and grants.status = 'active'
      and grants.valid_until = '2027-12-31T23:59:59Z'::timestamptz)
  and (select count(*) = 20 from public.pachanga_competition_entitlement_grants grants
    where grants.organizer_group_id = '8a000000-0000-4000-8000-000000000010'
      and grants.billing_access_grant_id is not null and grants.status = 'active')
  and (select transferred_onboarding_id is not null from wave8a_state),
  'Explicit private beta must create one expiring canonical grant and one onboarding workspace'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000006');
select pg_temp.assert_true(
  public.get_pachanga_organizer_access_application_v1((select transferred_application_id from wave8a_state))
    #>> '{onboarding,nextAction}' = 'CREATE_FIRST_COMPETITION',
  'Onboarding must derive the first canonical next action on the server'
);
reset role;

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
  league_private_beta_enabled = true,
  league_private_beta_creation_enabled = true,
  league_private_beta_public_discovery_enabled = false,
  revision = revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = '8a000000-0000-4000-8000-000000000003',
  updated_at = clock_timestamp()
where singleton;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000006');
with launched as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000030', transferred_onboarding_id,
    transferred_onboarding_revision, 'competition.launch',
    '{"launcherKind":"LEAGUE","launcherPayload":{"authoringMode":"SIMPLE","presetKey":"LEAGUE_F7_STANDARD"},"reason":"First canonical League"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_onboarding"}'
  ) body from wave8a_state
)
update wave8a_state set launch_response = launched.body from launched;

select pg_temp.assert_true(
  public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000030', transferred_onboarding_id,
    transferred_onboarding_revision, 'competition.launch',
    '{"launcherKind":"LEAGUE","launcherPayload":{"authoringMode":"SIMPLE","presetKey":"LEAGUE_F7_STANDARD"},"reason":"First canonical League"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_onboarding"}'
  ) = (select launch_response from wave8a_state),
  'First Competition Launcher replay must return the same canonical receipt'
) from wave8a_state;
reset role;

select pg_temp.assert_true(
  (select count(*) = 1 from private.pachanga_league_private_beta_wizards wizards
    where wizards.organizer_group_id = '8a000000-0000-4000-8000-000000000010')
  and (select launch_response #>> '{snapshot,firstLauncherAggregateId}' is not null from wave8a_state),
  'First Competition Launcher must create exactly one existing-engine draft'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000001');
with created as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000040',
    '8a000000-0000-4000-8000-000000000011', 0, 'application.create',
    '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","intent":"TOURNAMENT","competitionType":"TOURNAMENT","teamCount":8,"summary":"Solicitud para probar rechazo y reconsideración.","reason":"Reconsideration scenario"}',
    '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body
)
update wave8a_state set
  reconsidered_application_id = (created.body ->> 'aggregateId')::uuid,
  reconsidered_application_revision = (created.body ->> 'confirmedRevision')::bigint
from created;

do $rate_limit$
declare iteration integer;
begin
  for iteration in 1..8 loop
    perform public.command_pachanga_organizer_access_application_v1(
      gen_random_uuid(), '8a000000-0000-4000-8000-000000000011', 0, 'application.create',
      '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","reason":"Duplicate rate-limit exercise"}',
      '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
    );
  end loop;
end;
$rate_limit$;
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_access_application_v1(%L,%L,0,%L,%L::jsonb,%L::jsonb)',
  '8a100000-0000-4000-8000-000000000041', '8a000000-0000-4000-8000-000000000011',
  'application.create', '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","reason":"Rate limit must apply"}', '{}'
), 'RATE_LIMITED');

with submitted as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000042', reconsidered_application_id,
    reconsidered_application_revision, 'application.submit',
    '{"consent":true,"reason":"Submit reconsideration source"}', '{}'
  ) body from wave8a_state
)
update wave8a_state set reconsidered_application_revision = (submitted.body ->> 'confirmedRevision')::bigint from submitted;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000003');
with reviewed as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000043', reconsidered_application_id,
    reconsidered_application_revision, 'review.start', '{"reason":"Review reconsideration source"}', '{}'
  ) body from wave8a_state
)
update wave8a_state set reconsidered_application_revision = (reviewed.body ->> 'confirmedRevision')::bigint from reviewed;
with rejected as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000044', reconsidered_application_id,
    reconsidered_application_revision, 'review.reject',
    '{"decisionCode":"INSUFFICIENT_SCOPE","message":"Ajusta el alcance y vuelve a solicitarlo.","reason":"Reject with reconsideration available"}', '{}'
  ) body from wave8a_state
)
update wave8a_state set reconsidered_application_revision = (rejected.body ->> 'confirmedRevision')::bigint from rejected;
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000001');
with reconsidered as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000045', reconsidered_application_id,
    reconsidered_application_revision, 'application.reconsider',
    '{"reason":"Authorized reconsideration"}', '{"clientVersion":"8.0.0+db","surface":"organizer_access"}'
  ) body from wave8a_state
), previous as (
  select reconsidered_application_id as previous_id from wave8a_state
)
update wave8a_state set
  reconsidered_application_id = (reconsidered.body ->> 'aggregateId')::uuid,
  reconsidered_application_revision = (reconsidered.body ->> 'confirmedRevision')::bigint
from reconsidered, previous;

select pg_temp.assert_true(
  public.get_pachanga_organizer_access_application_v1((select reconsidered_application_id from wave8a_state)) ->> 'status' = 'draft'
  and public.get_pachanga_organizer_access_application_v1((select reconsidered_application_id from wave8a_state))
    ->> 'reconsiderationOfId' is not null,
  'Authorized reconsideration must preserve the rejected history and open one new draft'
);

with withdrawn as (
  select public.command_pachanga_organizer_access_application_v1(
    '8a100000-0000-4000-8000-000000000046', reconsidered_application_id,
    reconsidered_application_revision, 'application.withdraw',
    '{"reason":"Withdraw reconsidered draft"}', '{}'
  ) body from wave8a_state
)
update wave8a_state set reconsidered_application_revision = (withdrawn.body ->> 'confirmedRevision')::bigint from withdrawn;
reset role;

select pg_temp.assert_true(
  (select status = 'withdrawn' from private.pachanga_organizer_access_applications_v1
    where id = (select reconsidered_application_id from wave8a_state))
  and (select count(*) = 0 from private.pachanga_organizer_access_grants_v1 grants
    where grants.organizer_group_id = '8a000000-0000-4000-8000-000000000011'),
  'Rejected/reconsidered/withdrawn applications must not leak any grant'
);

select pg_temp.assert_true(
  (select count(*) = 2 from private.pachanga_organizer_access_operation_receipts_v1 receipts
    where receipts.client_metadata ? 'clientVersion'
      and not receipts.client_metadata ? 'secret'
      and receipts.operation_id in ('8a100000-0000-4000-8000-000000000001','8a100000-0000-4000-8000-000000000010')),
  'Stored client metadata must be allowlisted and secret-free'
);

update private.pachanga_organizer_onboarding_workspaces_v1 workspaces set
  status = 'completed', completed_at = clock_timestamp(),
  revision = workspaces.revision + 1,
  server_sequence = nextval('private.pachanga_organizer_access_sequence'),
  updated_at = clock_timestamp()
where workspaces.id = (select transferred_onboarding_id from wave8a_state);
update wave8a_state set transferred_onboarding_revision = (
  select revision from private.pachanga_organizer_onboarding_workspaces_v1
  where id = (select transferred_onboarding_id from wave8a_state)
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000006');
select public.command_pachanga_organizer_access_application_v1(
  '8a100000-0000-4000-8000-000000000050',
  (select transferred_onboarding_id from wave8a_state),
  (select transferred_onboarding_revision from wave8a_state),
  'onboarding.refresh', '{"reason":"Verify completed onboarding notification"}',
  '{"clientVersion":"8.0.0+db","surface":"organizer_onboarding"}'
);
reset role;

update private.pachanga_organizer_access_grants_v1 grants set
  valid_until = clock_timestamp() + interval '3 days',
  updated_at = clock_timestamp()
where grants.organizer_group_id = '8a000000-0000-4000-8000-000000000010'
  and grants.organizer_access_decision_id is not null
  and grants.status = 'active';

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000006');
select pg_temp.expect_failure(
  'select public.process_pachanga_organizer_access_expiry_notifications_v1(''8a100000-0000-4000-8000-000000000051'', 100)',
  'PERMISSION DENIED'
);
reset role;

set local role service_role;
select pg_temp.actor(null, 'service_role');
select pg_temp.assert_true(
  (public.process_pachanga_organizer_access_expiry_notifications_v1(
    '8a100000-0000-4000-8000-000000000051', 100
  ) ->> 'notified')::integer = 1,
  'Service reminder worker must emit one due access notification'
);
select pg_temp.assert_true(
  (public.process_pachanga_organizer_access_expiry_notifications_v1(
    '8a100000-0000-4000-8000-000000000051', 100
  ) ->> 'replayed')::boolean,
  'Exact reminder replay must return its stored canonical receipt'
);
select pg_temp.assert_true(
  (public.process_pachanga_organizer_access_expiry_notifications_v1(
    '8a100000-0000-4000-8000-000000000052', 100
  ) ->> 'notified')::integer = 0,
  'A later reminder pass must not emit the same semantic notification again'
);
reset role;

select pg_temp.assert_true(
  (select count(*) >= 2 from public.pachanga_user_notifications notifications
    where notifications.kind = 'organizer_access_warning')
    and (select count(*) = count(distinct notifications.dedupe_key)
      from public.pachanga_user_notifications notifications
      where notifications.kind = 'organizer_access_warning'),
  'Lifecycle notifications must be durable and deduplicated'
);

select pg_temp.assert_true(
  (select count(*) = 0 from public.pachanga_user_notifications notifications
    where notifications.kind = 'organizer_access_warning'
      and notifications.recipient_user_id = '8a000000-0000-4000-8000-000000000002')
  and (select bool_and(notifications.mandatory_in_app and notifications.visible_in_app)
    from public.pachanga_user_notifications notifications
    where notifications.kind = 'organizer_access_warning'),
  'Organizer access notifications must reach only necessary actors and remain mandatory in-app'
);

select pg_temp.assert_true(
  (select array_agg(distinct notifications.payload ->> 'action') @> array[
      'application.submit', 'review.start', 'review.request_information',
      'application.respond_information', 'review.approve', 'access.granted',
      'onboarding.available', 'competition.launch', 'onboarding.completed',
      'access.expiry_notification'
    ]::text[]
    from public.pachanga_user_notifications notifications
    where notifications.kind = 'organizer_access_warning')
  and exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.kind = 'organizer_access_warning'
      and notifications.payload ->> 'action' = 'review.reject'
  ),
  'Every implemented application, review, grant and onboarding notification must preserve its semantic action'
);

select pg_temp.assert_true(
  (select count(*) = 1 from public.pachanga_user_notifications notifications
    where notifications.kind = 'organizer_access_warning'
      and notifications.payload ->> 'action' = 'access.expiry_notification')
  and (select count(*) = 2 from private.pachanga_organizer_access_operation_receipts_v1 receipts
    where receipts.action = 'access.expiry_notifications'),
  'Expiry reminders must be semantically deduplicated while every worker operation keeps an idempotent receipt'
);

select pg_temp.assert_true(
  has_function_privilege(
    'authenticated',
    'private.pachanga_organizer_access_invalidation_can_read_v1(text,uuid)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'private.pachanga_organizer_access_invalidation_can_read_v1(text,uuid)',
    'EXECUTE'
  )
  and has_table_privilege(
    'authenticated',
    'public.pachanga_organizer_access_invalidations_v1',
    'SELECT'
  )
  and not has_table_privilege(
    'authenticated',
    'public.pachanga_organizer_access_invalidations_v1',
    'INSERT'
  ),
  'W8A-018: authenticated participants need only the RLS predicate and SELECT privileges'
);

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000004');
select pg_temp.assert_true(
  (select count(*) > 0
   from public.pachanga_organizer_access_invalidations_v1 invalidations
   where invalidations.organizer_club_id = '8a000000-0000-4000-8000-000000000020'),
  'W8A-018: Club owner must read the canonical invalidation used by Realtime'
);
reset role;

set local role authenticated;
select pg_temp.actor('8a000000-0000-4000-8000-000000000002');
select pg_temp.assert_true(
  (select count(*) = 0
   from public.pachanga_organizer_access_invalidations_v1 invalidations
   where invalidations.organizer_club_id = '8a000000-0000-4000-8000-000000000020'),
  'W8A-018: unrelated authenticated user must not read another organizer invalidation'
);
reset role;

select pg_temp.assert_true(
  not has_function_privilege('anon',
    'public.command_pachanga_organizer_access_application_v1(uuid,uuid,bigint,text,jsonb,jsonb)', 'EXECUTE')
    and not has_function_privilege('authenticated',
      'public.process_pachanga_organizer_access_expiry_notifications_v1(uuid,integer)', 'EXECUTE')
    and has_function_privilege('service_role',
      'public.process_pachanga_organizer_access_expiry_notifications_v1(uuid,integer)', 'EXECUTE')
    and has_function_privilege('authenticated',
      'public.get_my_pachanga_organizer_access_v1()', 'EXECUTE'),
  'Anonymous writes stay blocked while authenticated canonical reads remain available'
);

select 'ORGANIZER_ACCESS_ONBOARDING_V1_DB_PASS' as result;
