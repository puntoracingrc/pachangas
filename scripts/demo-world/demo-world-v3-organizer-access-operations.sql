\set ON_ERROR_STOP on

begin;

create schema if not exists simulation;

create table if not exists simulation.demo_world_organizer_access_proof (
  proof jsonb not null
);
truncate simulation.demo_world_organizer_access_proof;

create or replace function pg_temp.demo_access_actor(target_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create or replace function pg_temp.demo_access_command(
  target_operation_id uuid,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_action text,
  target_payload jsonb
)
returns jsonb
language sql
as $$
  select public.command_pachanga_organizer_access_application_v1(
    target_operation_id,
    target_aggregate_id,
    target_expected_revision,
    target_action,
    target_payload,
    jsonb_build_object(
      'clientVersion', '8.0.0+demo-world-v3',
      'displayMode', 'simulation',
      'serviceWorkerVersion', 'sw-demo-world-v3',
      'surface', 'demo_world_v3'
    )
  );
$$;

create temporary table demo_access_scenarios (
  ordinal integer primary key,
  scenario_id text unique not null,
  organizer_kind text not null,
  organizer_id uuid not null,
  organizer_name text not null,
  owner_id uuid not null,
  application_id uuid,
  application_revision bigint,
  onboarding_id uuid,
  owner_transferred boolean not null default false,
  first_competition_id uuid
);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('8d000000-0000-4000-8000-000000000001', 'demo-v3-platform@example.test', clock_timestamp(), '{"full_name":"Demo V3 Platform"}'),
  ('8d000000-0000-4000-8000-000000000011', 'demo-v3-club-a@example.test', clock_timestamp(), '{"full_name":"Demo V3 Club A"}'),
  ('8d000000-0000-4000-8000-000000000012', 'demo-v3-club-b@example.test', clock_timestamp(), '{"full_name":"Demo V3 Club B"}'),
  ('8d000000-0000-4000-8000-000000000013', 'demo-v3-team-c@example.test', clock_timestamp(), '{"full_name":"Demo V3 Team C"}'),
  ('8d000000-0000-4000-8000-000000000014', 'demo-v3-team-d@example.test', clock_timestamp(), '{"full_name":"Demo V3 Team D"}'),
  ('8d000000-0000-4000-8000-000000000015', 'demo-v3-club-e@example.test', clock_timestamp(), '{"full_name":"Demo V3 Club E"}'),
  ('8d000000-0000-4000-8000-000000000016', 'demo-v3-team-f-old@example.test', clock_timestamp(), '{"full_name":"Demo V3 Team F A"}'),
  ('8d000000-0000-4000-8000-000000000017', 'demo-v3-team-f-new@example.test', clock_timestamp(), '{"full_name":"Demo V3 Team F B"}'),
  ('8d000000-0000-4000-8000-000000000018', 'demo-v3-rival-one@example.test', clock_timestamp(), '{"full_name":"Demo V3 Rival One"}'),
  ('8d000000-0000-4000-8000-000000000019', 'demo-v3-rival-two@example.test', clock_timestamp(), '{"full_name":"Demo V3 Rival Two"}');

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('8d000000-0000-4000-8000-000000000001', 'platform_owner', true);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision) values
  ('8d100000-0000-4000-8000-0000000000c1', '8d000000-0000-4000-8000-000000000013', 'Team C · Beta Vallès', 'DV3TC001', '{"name":"Team C · Beta Vallès","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('8d100000-0000-4000-8000-0000000000d1', '8d000000-0000-4000-8000-000000000014', 'Team D · Llevant', 'DV3TD001', '{"name":"Team D · Llevant","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('8d100000-0000-4000-8000-0000000000f1', '8d000000-0000-4000-8000-000000000016', 'Team F · Traspaso', 'DV3TF001', '{"name":"Team F · Traspaso","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('8d100000-0000-4000-8000-000000000101', '8d000000-0000-4000-8000-000000000018', 'Delta Poblenou', 'DV3R0001', '{"name":"Delta Poblenou","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1),
  ('8d100000-0000-4000-8000-000000000102', '8d000000-0000-4000-8000-000000000019', 'Nexe Montjuïc', 'DV3R0002', '{"name":"Nexe Montjuïc","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('8d100000-0000-4000-8000-0000000000c1', '8d000000-0000-4000-8000-000000000013', 'owner', 'Owner Team C'),
  ('8d100000-0000-4000-8000-0000000000d1', '8d000000-0000-4000-8000-000000000014', 'owner', 'Owner Team D'),
  ('8d100000-0000-4000-8000-0000000000f1', '8d000000-0000-4000-8000-000000000016', 'owner', 'Owner Team F A'),
  ('8d100000-0000-4000-8000-0000000000f1', '8d000000-0000-4000-8000-000000000017', 'player', 'Owner Team F B'),
  ('8d100000-0000-4000-8000-000000000101', '8d000000-0000-4000-8000-000000000018', 'owner', 'Owner Delta Poblenou'),
  ('8d100000-0000-4000-8000-000000000102', '8d000000-0000-4000-8000-000000000019', 'owner', 'Owner Nexe Montjuïc');

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, source_player_id, display_name, birth_date,
  rating, current_overall, base_facets, calibrated_facets, current_facets, position
) values
  ('8d300000-0000-4000-8000-000000000018', '8d000000-0000-4000-8000-000000000018', '8d100000-0000-4000-8000-000000000101', 'demo-v3-rival-one', 'Jugador Delta', '1991-06-12', 6.8, 68, '{"pace":68}', '{"pace":68}', '{"pace":68}', 'Mediocentro / pivote'),
  ('8d300000-0000-4000-8000-000000000019', '8d000000-0000-4000-8000-000000000019', '8d100000-0000-4000-8000-000000000102', 'demo-v3-rival-two', 'Jugador Nexe', '1993-09-18', 6.6, 66, '{"pace":66}', '{"pace":66}', '{"pace":66}', 'Defensa central');

insert into public.pachanga_clubs(
  id, name, slug, description, club_type, operational_status, visibility,
  primary_owner_id, created_by, partnership_status
) values
  ('8d200000-0000-4000-8000-0000000000a1', 'Club A · Marina Partner', 'demo-v3-club-a-marina', 'Club colaborador que completa su primera liga pública.', 'FOOTBALL_CLUB', 'active', 'public', '8d000000-0000-4000-8000-000000000011', '8d000000-0000-4000-8000-000000000011', 'active'),
  ('8d200000-0000-4000-8000-0000000000b1', 'Club B · Besòs Organizer', 'demo-v3-club-b-besos', 'Club interesado en el plan comercial todavía no disponible.', 'FOOTBALL_CLUB', 'active', 'unlisted', '8d000000-0000-4000-8000-000000000012', '8d000000-0000-4000-8000-000000000012', 'active'),
  ('8d200000-0000-4000-8000-0000000000e1', 'Club E · Nord Retirado', 'demo-v3-club-e-nord', 'Club que retira voluntariamente su solicitud antes de revisión.', 'FOOTBALL_CLUB', 'active', 'private', '8d000000-0000-4000-8000-000000000015', '8d000000-0000-4000-8000-000000000015', 'active');

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, invited_by, accepted_at
) values
  ('8d200000-0000-4000-8000-0000000000a1', '8d000000-0000-4000-8000-000000000011', 'club_owner', 'active', '8d000000-0000-4000-8000-000000000011', clock_timestamp()),
  ('8d200000-0000-4000-8000-0000000000b1', '8d000000-0000-4000-8000-000000000012', 'club_owner', 'active', '8d000000-0000-4000-8000-000000000012', clock_timestamp()),
  ('8d200000-0000-4000-8000-0000000000e1', '8d000000-0000-4000-8000-000000000015', 'club_owner', 'active', '8d000000-0000-4000-8000-000000000015', clock_timestamp());

insert into demo_access_scenarios(
  ordinal, scenario_id, organizer_kind, organizer_id, organizer_name, owner_id
) values
  (1, 'club_partner_approved', 'CLUB', '8d200000-0000-4000-8000-0000000000a1', 'Club A · Marina Partner', '8d000000-0000-4000-8000-000000000011'),
  (2, 'club_paid_interest', 'CLUB', '8d200000-0000-4000-8000-0000000000b1', 'Club B · Besòs Organizer', '8d000000-0000-4000-8000-000000000012'),
  (3, 'team_needs_information_beta', 'TEAM', '8d100000-0000-4000-8000-0000000000c1', 'Team C · Beta Vallès', '8d000000-0000-4000-8000-000000000013'),
  (4, 'team_rejected', 'TEAM', '8d100000-0000-4000-8000-0000000000d1', 'Team D · Llevant', '8d000000-0000-4000-8000-000000000014'),
  (5, 'club_withdrawn', 'CLUB', '8d200000-0000-4000-8000-0000000000e1', 'Club E · Nord Retirado', '8d000000-0000-4000-8000-000000000015'),
  (6, 'team_owner_transfer', 'TEAM', '8d100000-0000-4000-8000-0000000000f1', 'Team F · Traspaso', '8d000000-0000-4000-8000-000000000016');

do $demo_organizer_access$
#variable_conflict use_variable
declare
  response jsonb;
  application_id uuid;
  application_revision bigint;
  onboarding_id uuid;
  onboarding_revision bigint;
  wizard_id uuid;
  competition_id uuid;
  edition_id uuid;
  category_id uuid;
  stage_id uuid;
  division_id uuid;
  group_id uuid;
  rule_revision_id uuid;
  entry_one_id uuid;
  entry_two_id uuid;
  roster_one_id uuid;
  roster_two_id uuid;
  roster_revision bigint;
  plan_id uuid;
  publication_id uuid;
  revision_value bigint;
  preset_steps jsonb;
  step_data jsonb;
begin
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := pg_temp.demo_access_command(
    md5('demo-v3-settings-enable')::uuid,
    '00000000-0000-0000-0000-00000000a8a0', 1, 'settings.flags',
    '{"applicationsEnabled":true,"submissionEnabled":true,"reviewEnabled":true,"partnershipApprovalEnabled":true,"onboardingEnabled":true,"firstCompetitionLauncherEnabled":true,"demoWorldV30Enabled":true,"reason":"Demo World V3 synthetic activation"}'::jsonb
  );
  response := public.command_pachanga_club_platform_v1(
    md5('demo-v3-club-organizer-adapter-enable')::uuid,
    '00000000-0000-0000-0000-00000000c101',
    (select revision from private.pachanga_club_foundation_settings where singleton),
    'club_flags.set',
    '{"foundationEnabled":true,"competitionOrganizerEnabled":true,"reason":"Demo World V3 prerequisite for canonical Club grants"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","installedMode":"simulation","surface":"demo_world_v3"}'::jsonb
  );

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000011');
  response := pg_temp.demo_access_command(md5('demo-v3-club-a-create')::uuid, '8d200000-0000-4000-8000-0000000000a1', 0, 'application.create',
    '{"organizerKind":"CLUB","planCode":"CLUB_PARTNER","intent":"LEAGUE","competitionType":"LEAGUE","teamCount":4,"targetStartDate":"2027-04-01","municipality":"Barcelona","area":"Litoral","fieldRelationship":"Acuerdo con campo municipal","summary":"Primera liga local colaboradora.","reason":"Demo Club A create"}'::jsonb);
  application_id := (response ->> 'aggregateId')::uuid;
  application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-club-a-submit')::uuid, application_id, application_revision, 'application.submit', '{"consent":true,"reason":"Demo Club A submit"}'::jsonb);
  application_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := pg_temp.demo_access_command(md5('demo-v3-club-a-review')::uuid, application_id, application_revision, 'review.start', '{"reason":"Review Club A"}'::jsonb);
  application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-club-a-approve')::uuid, application_id, application_revision, 'review.approve',
    '{"decisionCode":"PARTNERSHIP_APPROVED","message":"Club colaborador aprobado.","privateNote":"Synthetic review evidence.","validFrom":"2026-08-01T00:00:00Z","reason":"Approve Demo Club A partnership"}'::jsonb);
  application_revision := (response ->> 'confirmedRevision')::bigint;
  onboarding_id := (response #>> '{snapshot,onboarding,id}')::uuid;
  update demo_access_scenarios set application_id = application_id, application_revision = application_revision, onboarding_id = onboarding_id where scenario_id = 'club_partner_approved';

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000011');
  select revision into onboarding_revision from private.pachanga_organizer_onboarding_workspaces_v1 where id = onboarding_id;
  response := pg_temp.demo_access_command(md5('demo-v3-club-a-launch')::uuid, onboarding_id, onboarding_revision, 'competition.launch',
    '{"launcherKind":"LEAGUE","launcherPayload":{"authoringMode":"SIMPLE","presetKey":"LEAGUE_F7_STANDARD"},"reason":"Launch first Demo Club A League"}'::jsonb);
  wizard_id := (response #>> '{snapshot,firstLauncherAggregateId}')::uuid;
  preset_steps := private.pachanga_competition_authoring_preset_v1('LEAGUE_F7_STANDARD') -> 'steps';
  for i in 1..12 loop
    step_data := preset_steps -> i::text;
    if i = 1 then
      step_data := step_data || '{"name":"Liga Marina V3","slug":"liga-marina-v3","description":"Primera liga pública creada desde el onboarding.","generalArea":"Barcelona"}'::jsonb;
    elsif i = 3 then
      step_data := step_data || '{"editionName":"Temporada 2027","seasonLabel":"2027","startsAt":"2027-04-01","endsAt":"2027-07-31","timezone":"Europe/Madrid"}'::jsonb;
    elsif i = 4 then
      step_data := step_data || '{"teamCap":4,"legs":1,"registrationMode":"INVITE_ONLY","registrationClosesAt":"2027-03-20T23:59:59Z"}'::jsonb;
    elsif i = 5 then
      step_data := step_data || '{"minimumRosterSize":1,"maximumRosterSize":18,"credentialRequired":false,"jerseyRequired":false,"closeRequiresApprovedRosters":false}'::jsonb;
    elsif i = 12 then
      step_data := step_data || '{"consent":true,"acknowledgeUnavailableFeatures":true,"paymentsAcknowledged":true,"tournamentsAcknowledged":true}'::jsonb;
    end if;
    response := public.command_pachanga_league_private_beta_v2(
      md5('demo-v3-club-a-wizard-step-' || i::text)::uuid,
      wizard_id, i, 'wizard.step.save',
      jsonb_build_object('step', i, 'data', step_data, 'reason', 'Demo World V3 canonical preset step'),
      '{"clientVersion":"8.0.0+demo-world-v3","installedMode":"simulation","surface":"demo_world_v3"}'::jsonb
    );
  end loop;
  response := public.command_pachanga_league_private_beta_v2(
    md5('demo-v3-club-a-wizard-finalize')::uuid,
    wizard_id, 13, 'wizard.finalize', '{"reason":"Finalize first Demo Club A League"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","installedMode":"simulation","surface":"demo_world_v3"}'::jsonb
  );
  competition_id := (response #>> '{snapshot,canonical,competitionId}')::uuid;
  edition_id := (response #>> '{snapshot,canonical,editionId}')::uuid;
  category_id := (response #>> '{snapshot,canonical,categoryId}')::uuid;
  stage_id := (response #>> '{snapshot,canonical,stageId}')::uuid;
  division_id := nullif(response #>> '{snapshot,canonical,divisionId}', '')::uuid;
  group_id := (response #>> '{snapshot,canonical,groupId}')::uuid;
  rule_revision_id := (response #>> '{snapshot,canonical,ruleRevisionId}')::uuid;
  update demo_access_scenarios set first_competition_id = competition_id where scenario_id = 'club_partner_approved';

  if (select status from public.pachanga_competition_categories where id = category_id) = 'draft' then
    select revision into revision_value from public.pachanga_competition_categories where id = category_id;
    perform public.command_pachanga_league_participation_v1(
      md5('demo-v3-club-a-category-activate')::uuid, category_id, revision_value,
      'category.activate', '{"reason":"Activate first Demo League category"}'::jsonb,
      '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
    );
  end if;
  select revision into revision_value from public.pachanga_competition_editions where id = edition_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-registration-open')::uuid, edition_id, revision_value,
    'registration.open',
    jsonb_build_object(
      'registrationMode', 'INVITE_ONLY',
      'closesAt', '2027-03-20T23:59:59Z',
      'ruleRevisionId', rule_revision_id,
      'reason', 'Open first Demo League registration'
    ),
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );

  select revision into revision_value from public.pachanga_competition_categories where id = category_id;
  response := public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-invite-one')::uuid, category_id, revision_value, 'entry.invite',
    jsonb_build_object('teamId', '8d100000-0000-4000-8000-000000000101', 'expiresAt', '2027-03-20T23:59:59Z', 'reason', 'Invite Demo rival one'),
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  entry_one_id := (response #>> '{snapshot,entry,id}')::uuid;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000018');
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-rival-one-accept')::uuid, entry_one_id, 1, 'entry.accept', '{"reason":"Accept first Demo League invitation"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select id, revision into roster_one_id, roster_revision
  from public.pachanga_competition_rosters where entry_id = entry_one_id;
  response := public.command_pachanga_league_participation_v1(
    md5('demo-v3-rival-one-roster-member')::uuid, roster_one_id, roster_revision,
    'roster.member.add', '{"playerProfileId":"8d300000-0000-4000-8000-000000000018","reason":"Add first Demo rival player"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_one_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-rival-one-roster-submit')::uuid, roster_one_id, roster_revision,
    'roster.submit', '{"reason":"Submit first Demo rival roster"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000011');
  select revision into revision_value from public.pachanga_competition_categories where id = category_id;
  response := public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-invite-two')::uuid, category_id, revision_value, 'entry.invite',
    jsonb_build_object('teamId', '8d100000-0000-4000-8000-000000000102', 'expiresAt', '2027-03-20T23:59:59Z', 'reason', 'Invite Demo rival two'),
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  entry_two_id := (response #>> '{snapshot,entry,id}')::uuid;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000019');
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-rival-two-accept')::uuid, entry_two_id, 1, 'entry.accept', '{"reason":"Accept second Demo League invitation"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select id, revision into roster_two_id, roster_revision
  from public.pachanga_competition_rosters where entry_id = entry_two_id;
  response := public.command_pachanga_league_participation_v1(
    md5('demo-v3-rival-two-roster-member')::uuid, roster_two_id, roster_revision,
    'roster.member.add', '{"playerProfileId":"8d300000-0000-4000-8000-000000000019","reason":"Add second Demo rival player"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_two_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-rival-two-roster-submit')::uuid, roster_two_id, roster_revision,
    'roster.submit', '{"reason":"Submit second Demo rival roster"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000011');
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_one_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-roster-one-approve')::uuid, roster_one_id, roster_revision,
    'roster.approve', '{"reason":"Approve first Demo rival roster"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select revision into roster_revision from public.pachanga_competition_rosters where id = roster_two_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-roster-two-approve')::uuid, roster_two_id, roster_revision,
    'roster.approve', '{"reason":"Approve second Demo rival roster"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select revision into revision_value from public.pachanga_competition_entries where id = entry_one_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-stage-one')::uuid, entry_one_id, revision_value,
    'stage_membership.assign',
    jsonb_strip_nulls(jsonb_build_object(
      'stageId', stage_id,
      'divisionId', division_id,
      'groupId', group_id,
      'reason', 'Assign first Demo rival to the canonical stage'
    )),
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select revision into revision_value from public.pachanga_competition_entries where id = entry_two_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-stage-two')::uuid, entry_two_id, revision_value,
    'stage_membership.assign',
    jsonb_strip_nulls(jsonb_build_object(
      'stageId', stage_id,
      'divisionId', division_id,
      'groupId', group_id,
      'reason', 'Assign second Demo rival to the canonical stage'
    )),
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  select revision into revision_value from public.pachanga_competition_editions where id = edition_id;
  perform public.command_pachanga_league_participation_v1(
    md5('demo-v3-club-a-registration-close')::uuid, edition_id, revision_value,
    'registration.close', '{"reason":"Close first Demo League registration"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-v3-club-a-schedule-create')::uuid, stage_id, 1, 'schedule_plan.create',
    jsonb_build_object('categoryId', category_id, 'divisionId', division_id, 'groupId', group_id, 'ruleRevisionId', rule_revision_id, 'legs', 1, 'reason', 'Create first Demo League schedule'),
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  plan_id := (response #>> '{snapshot,plan,id}')::uuid;
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-v3-club-a-slots')::uuid, plan_id, 1, 'schedule_slot.bulk_create',
    '{"startDate":"2027-04-01","endDate":"2027-04-14","weekdays":[1,2,3,4,5,6,7],"localTime":"20:00","durationMinutes":90,"timezone":"Europe/Madrid","venueLabel":"Pista Marina Demo","resourceKey":"demo-v3-marina"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-v3-club-a-generate')::uuid, plan_id, 2, 'schedule.generate', '{"seed":"demo-v3-club-a"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  response := public.command_pachanga_league_scheduling_v1(
    md5('demo-v3-club-a-validate')::uuid, plan_id, 3, 'schedule.validate', '{"reason":"Validate first Demo League schedule"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  perform public.command_pachanga_league_scheduling_v1(
    md5('demo-v3-club-a-publish-schedule')::uuid, plan_id, 4, 'schedule.publish', '{"reason":"Publish first Demo League schedule"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );

  response := public.command_pachanga_competition_publication_v1(
    md5('demo-v3-club-a-publication-prepare')::uuid, competition_id, 0, 'publication.prepare',
    jsonb_build_object(
      'editionId', edition_id, 'categoryId', category_id, 'slug', 'liga-marina-v3', 'visibility', 'public',
      'publicProfile', jsonb_build_object('name', 'Liga Marina V3', 'description', 'Primera liga pública del Club A.', 'municipality', 'Barcelona', 'generalArea', 'Litoral', 'format', 'Liga F7', 'badge', 'PARTNER', 'rulesSummary', 'Liga a una vuelta.'),
      'publicSections', jsonb_build_object('teams', true, 'calendar', true, 'results', true, 'standings', true, 'bracket', false, 'referees', false, 'venueDetail', false, 'discipline', false),
      'reason', 'Prepare first Demo Club A public League'
    ),
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  publication_id := (response #>> '{snapshot,publication,id}')::uuid;
  revision_value := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-v3-club-a-publication-consent')::uuid, competition_id, revision_value, 'publication.consent',
    '{"statements":{"authorizedRepresentative":true,"informationAccurate":true,"teamAssetsAuthorized":true,"indexingAccepted":true},"purpose":"Publicar la primera liga del Club A.","reason":"Explicit Demo Club A publication consent"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-v3-club-a-publication-submit')::uuid, competition_id, (response ->> 'confirmedRevision')::bigint, 'publication.submit', '{"reason":"Submit first Demo Club A public League"}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  revision_value := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := public.command_pachanga_public_competition_moderation_v1(
    md5('demo-v3-club-a-publication-approve')::uuid, publication_id, revision_value, 'publication.approve',
    '{"reason":"Independent Demo V3 review","publicReason":"Publicación aprobada."}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  perform public.command_pachanga_public_competition_moderation_v1(
    md5('demo-v3-club-a-publication-publish')::uuid, publication_id, (response ->> 'confirmedRevision')::bigint, 'publication.publish',
    '{"reason":"Publish first Demo Club A League","publicReason":"Liga disponible."}'::jsonb,
    '{"clientVersion":"8.0.0+demo-world-v3","surface":"demo_world_v3"}'::jsonb
  );
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000011');
  select revision into onboarding_revision from private.pachanga_organizer_onboarding_workspaces_v1 where id = onboarding_id;
  perform pg_temp.demo_access_command(md5('demo-v3-club-a-onboarding-refresh')::uuid, onboarding_id, onboarding_revision, 'onboarding.refresh', '{"reason":"Refresh completed Demo Club A onboarding"}'::jsonb);

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000012');
  response := pg_temp.demo_access_command(md5('demo-v3-club-b-create')::uuid, '8d200000-0000-4000-8000-0000000000b1', 0, 'application.create',
    '{"organizerKind":"CLUB","planCode":"CLUB_ORGANIZER","intent":"BOTH","competitionType":"BOTH","teamCount":12,"municipality":"Barcelona","area":"Besòs","summary":"Interés comercial en organizar varias competiciones.","reason":"Demo Club B create"}'::jsonb);
  application_id := (response ->> 'aggregateId')::uuid; application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-club-b-submit')::uuid, application_id, application_revision, 'application.submit', '{"consent":true,"reason":"Demo Club B submit"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := pg_temp.demo_access_command(md5('demo-v3-club-b-review')::uuid, application_id, application_revision, 'review.start', '{"reason":"Review Club B interest"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-club-b-interest')::uuid, application_id, application_revision, 'review.approve', '{"decisionCode":"PAID_PLAN_INTEREST_APPROVED","message":"Interés registrado; Checkout LIVE todavía no está disponible.","reason":"Record Demo Club B paid interest"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  update demo_access_scenarios set application_id = application_id, application_revision = application_revision where scenario_id = 'club_paid_interest';

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000013');
  response := pg_temp.demo_access_command(md5('demo-v3-team-c-create')::uuid, '8d100000-0000-4000-8000-0000000000c1', 0, 'application.create',
    '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","intent":"TOURNAMENT","competitionType":"TOURNAMENT","teamCount":8,"municipality":"Terrassa","area":"Vallès","summary":"Equipo que quiere probar un torneo privado.","reason":"Demo Team C create"}'::jsonb);
  application_id := (response ->> 'aggregateId')::uuid; application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-team-c-submit')::uuid, application_id, application_revision, 'application.submit', '{"consent":true,"reason":"Demo Team C submit"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := pg_temp.demo_access_command(md5('demo-v3-team-c-review')::uuid, application_id, application_revision, 'review.start', '{"reason":"Review Demo Team C"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-team-c-request-info')::uuid, application_id, application_revision, 'review.request_information', '{"message":"Confirma la fecha objetivo del torneo.","privateNote":"Synthetic Team C review.","reason":"Need target date"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000013');
  response := pg_temp.demo_access_command(md5('demo-v3-team-c-response')::uuid, application_id, application_revision, 'application.respond_information', '{"message":"El torneo se celebrará en junio de 2027.","consent":true,"reason":"Provide Demo Team C information"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := pg_temp.demo_access_command(md5('demo-v3-team-c-approve-beta')::uuid, application_id, application_revision, 'review.approve', '{"decisionCode":"PRIVATE_BETA_APPROVED","message":"Beta temporal aprobada.","grantPlanCode":"PRIVATE_BETA","grantSource":"PRIVATE_BETA","validFrom":"2026-08-01T00:00:00Z","validUntil":"2028-01-31T23:59:59Z","reason":"Approve Demo Team C private beta"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint; onboarding_id := (response #>> '{snapshot,onboarding,id}')::uuid;
  update demo_access_scenarios set application_id = application_id, application_revision = application_revision, onboarding_id = onboarding_id where scenario_id = 'team_needs_information_beta';

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000014');
  response := pg_temp.demo_access_command(md5('demo-v3-team-d-create')::uuid, '8d100000-0000-4000-8000-0000000000d1', 0, 'application.create', '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","intent":"LEAGUE","competitionType":"LEAGUE","teamCount":6,"municipality":"Badalona","area":"Llevant","summary":"Solicitud que no cumple los criterios de la beta.","reason":"Demo Team D create"}'::jsonb);
  application_id := (response ->> 'aggregateId')::uuid; application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-team-d-submit')::uuid, application_id, application_revision, 'application.submit', '{"consent":true,"reason":"Demo Team D submit"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := pg_temp.demo_access_command(md5('demo-v3-team-d-review')::uuid, application_id, application_revision, 'review.start', '{"reason":"Review Demo Team D"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-team-d-reject')::uuid, application_id, application_revision, 'review.reject', '{"decisionCode":"PRIVATE_BETA_NOT_AVAILABLE","message":"La beta actual no encaja con esta solicitud.","privateNote":"Synthetic rejection evidence.","reason":"Reject Demo Team D"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  update demo_access_scenarios set application_id = application_id, application_revision = application_revision where scenario_id = 'team_rejected';

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000015');
  response := pg_temp.demo_access_command(md5('demo-v3-club-e-create')::uuid, '8d200000-0000-4000-8000-0000000000e1', 0, 'application.create', '{"organizerKind":"CLUB","planCode":"CLUB_PARTNER","intent":"LEAGUE","competitionType":"LEAGUE","teamCount":6,"municipality":"Sabadell","area":"Nord","summary":"Solicitud retirada antes de la revisión.","reason":"Demo Club E create"}'::jsonb);
  application_id := (response ->> 'aggregateId')::uuid; application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-club-e-submit')::uuid, application_id, application_revision, 'application.submit', '{"consent":true,"reason":"Demo Club E submit"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-club-e-withdraw')::uuid, application_id, application_revision, 'application.withdraw', '{"reason":"El Club pospone el proyecto."}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  update demo_access_scenarios set application_id = application_id, application_revision = application_revision where scenario_id = 'club_withdrawn';

  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000016');
  response := pg_temp.demo_access_command(md5('demo-v3-team-f-create')::uuid, '8d100000-0000-4000-8000-0000000000f1', 0, 'application.create', '{"organizerKind":"TEAM","planCode":"TEAM_ORGANIZER_PRO","intent":"LEAGUE","competitionType":"LEAGUE","teamCount":8,"municipality":"Granollers","area":"Vallès Oriental","summary":"Onboarding transferido al nuevo owner.","reason":"Demo Team F create"}'::jsonb);
  application_id := (response ->> 'aggregateId')::uuid; application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-team-f-submit')::uuid, application_id, application_revision, 'application.submit', '{"consent":true,"reason":"Demo Team F submit"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000001');
  response := pg_temp.demo_access_command(md5('demo-v3-team-f-review')::uuid, application_id, application_revision, 'review.start', '{"reason":"Review Demo Team F"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.demo_access_command(md5('demo-v3-team-f-approve-beta')::uuid, application_id, application_revision, 'review.approve', '{"decisionCode":"PRIVATE_BETA_APPROVED","message":"Beta temporal aprobada.","grantPlanCode":"PRIVATE_BETA","grantSource":"PRIVATE_BETA","validFrom":"2026-08-01T00:00:00Z","validUntil":"2028-02-29T23:59:59Z","reason":"Approve Demo Team F private beta"}'::jsonb); application_revision := (response ->> 'confirmedRevision')::bigint; onboarding_id := (response #>> '{snapshot,onboarding,id}')::uuid;
  update demo_access_scenarios set application_id = application_id, application_revision = application_revision, onboarding_id = onboarding_id where scenario_id = 'team_owner_transfer';
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000016');
  perform public.transfer_pachanga_group_ownership_authoritative_v1(
    '8d100000-0000-4000-8000-0000000000f1', '8d000000-0000-4000-8000-000000000017',
    md5('demo-v3-team-f-owner-transfer')::uuid,
    (select payload_revision from public.pachanga_groups where id = '8d100000-0000-4000-8000-0000000000f1'),
    '{"clientVersion":"8.0.0+demo-world-v3","installedMode":"simulation","surface":"demo_world_v3"}'::jsonb
  );
  perform pg_temp.demo_access_actor('8d000000-0000-4000-8000-000000000017');
  select revision into onboarding_revision from private.pachanga_organizer_onboarding_workspaces_v1 where id = onboarding_id;
  perform pg_temp.demo_access_command(md5('demo-v3-team-f-new-owner-refresh')::uuid, onboarding_id, onboarding_revision, 'onboarding.refresh', '{"reason":"New owner continues Demo Team F onboarding"}'::jsonb);
  update demo_access_scenarios set owner_transferred = true, owner_id = '8d000000-0000-4000-8000-000000000017' where scenario_id = 'team_owner_transfer';
end;
$demo_organizer_access$;

insert into simulation.demo_world_organizer_access_proof(proof)
select jsonb_build_object(
  'version', 1,
  'scenarioCount', 6,
  'operationReceipts', (select count(*) from private.pachanga_organizer_access_operation_receipts_v1 receipts where receipts.client_metadata ->> 'surface' = 'demo_world_v3'),
  'grantCount', (
    select count(*)
    from private.pachanga_organizer_access_grants_v1 grants
    join private.pachanga_organizer_access_decisions_v1 decisions on decisions.id = grants.organizer_access_decision_id
    join demo_access_scenarios scenarios on scenarios.application_id = decisions.application_id
  ),
  'subscriptionGrants', (
    select count(*)
    from private.pachanga_organizer_access_grants_v1 grants
    join private.pachanga_organizer_access_decisions_v1 decisions on decisions.id = grants.organizer_access_decision_id
    join demo_access_scenarios scenarios on scenarios.application_id = decisions.application_id
    where grants.access_source = 'SUBSCRIPTION'
  ),
  'firstCompetitionLaunches', (select count(*) from demo_access_scenarios where first_competition_id is not null),
  'onboardingCompleted', (select count(*) from private.pachanga_organizer_onboarding_workspaces_v1 workspaces join demo_access_scenarios scenarios on scenarios.onboarding_id = workspaces.id where workspaces.status = 'completed'),
  'liveCheckoutEnabled', false,
  'stripeTouched', false,
  'remoteWrites', 0,
  'rpcFamilies', jsonb_build_array('ORGANIZER_ACCESS', 'LEAGUE_PRIVATE_BETA_V2', 'LEAGUE_PARTICIPATION', 'LEAGUE_SCHEDULING', 'PUBLICATION'),
  'privacy', jsonb_build_object(
    'containsAuthUuid', false,
    'containsEmail', false,
    'containsPhone', false,
    'containsPrivateNote', false,
    'containsStripeId', false
  ),
  'scenarios', (
    select jsonb_agg(jsonb_build_object(
      'id', scenarios.scenario_id,
      'organizerKind', scenarios.organizer_kind,
      'organizerName', scenarios.organizer_name,
      'planCode', applications.requested_plan_code,
      'applicationStatus', applications.status,
      'history', coalesce((
        select jsonb_agg(events.action order by events.server_sequence, events.id)
        from private.pachanga_organizer_access_events_v1 events
        where events.application_id = applications.id
      ), '[]'::jsonb),
      'decisionType', decisions.decision_type,
      'decisionCode', decisions.decision_code,
      'grant', case when grants.id is null then null else jsonb_build_object(
        'source', grants.access_source,
        'status', grants.status,
        'validUntil', grants.valid_until
      ) end,
      'onboarding', case when workspaces.id is null then null else jsonb_build_object(
        'status', workspaces.status,
        'nextAction', workspaces.next_action,
        'completedCheckpoints', (select count(*) from private.pachanga_organizer_onboarding_checkpoints_v1 checkpoints where checkpoints.workspace_id = workspaces.id and checkpoints.status = 'complete'),
        'totalCheckpoints', (select count(*) from private.pachanga_organizer_onboarding_checkpoints_v1 checkpoints where checkpoints.workspace_id = workspaces.id)
      ) end,
      'firstCompetition', case when competitions.id is null then null else jsonb_build_object(
        'name', competitions.name,
        'type', competitions.competition_type,
        'status', case when publications.lifecycle_status = 'published' then 'PUBLIC_ACTIVE' else upper(competitions.status) end,
        'visibility', coalesce(publications.visibility, competitions.visibility),
        'canonicalMatches', (select count(*) from public.pachanga_competition_match_contexts contexts where contexts.competition_id = competitions.id)
      ) end,
      'ownerTransferred', scenarios.owner_transferred,
      'checkoutAvailable', false
    ) order by scenarios.ordinal)
    from demo_access_scenarios scenarios
    join private.pachanga_organizer_access_applications_v1 applications on applications.id = scenarios.application_id
    left join lateral (
      select decisions.* from private.pachanga_organizer_access_decisions_v1 decisions
      where decisions.application_id = applications.id
      order by decisions.server_sequence desc, decisions.id desc limit 1
    ) decisions on true
    left join private.pachanga_organizer_access_grants_v1 grants on grants.organizer_access_decision_id = decisions.id
    left join private.pachanga_organizer_onboarding_workspaces_v1 workspaces on workspaces.id = scenarios.onboarding_id
    left join public.pachanga_competitions competitions on competitions.id = scenarios.first_competition_id
    left join lateral (
      select publications.* from public.pachanga_competition_publications publications
      where publications.competition_id = competitions.id
      order by publications.server_sequence desc, publications.id desc limit 1
    ) publications on true
  )
)
from private.pachanga_organizer_access_settings_v1 settings
where settings.singleton;

do $assert_demo_v3$
declare proof jsonb := (select rows.proof from simulation.demo_world_organizer_access_proof rows limit 1);
begin
  if jsonb_array_length(proof -> 'scenarios') <> 6 then raise exception 'DEMO_WORLD_V3_SCENARIO_COUNT_INVALID'; end if;
  if (proof ->> 'subscriptionGrants')::integer <> 0 or (proof ->> 'grantCount')::integer <> 3 then
    raise exception 'DEMO_WORLD_V3_GRANT_MAPPING_INVALID';
  end if;
  if (proof ->> 'firstCompetitionLaunches')::integer <> 1 or (proof ->> 'onboardingCompleted')::integer <> 1 then
    raise exception 'DEMO_WORLD_V3_FIRST_COMPETITION_INVALID';
  end if;
  if proof::text ~ '@example|\\+34|(cus|sub|price|prod)_[A-Za-z0-9_]+' then
    raise exception 'DEMO_WORLD_V3_PRIVATE_OR_STRIPE_DATA_LEAK';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(proof -> 'scenarios') scenarios
    where scenarios ->> 'id' = 'club_partner_approved'
      and scenarios ->> 'applicationStatus' = 'approved'
      and scenarios #>> '{grant,source}' = 'PARTNERSHIP'
      and scenarios #>> '{onboarding,status}' = 'completed'
      and scenarios #>> '{firstCompetition,status}' = 'PUBLIC_ACTIVE'
  ) then raise exception 'DEMO_WORLD_V3_CLUB_A_INVALID'; end if;
  if not exists (
    select 1 from jsonb_array_elements(proof -> 'scenarios') scenarios
    where scenarios ->> 'id' = 'club_paid_interest'
      and scenarios ->> 'applicationStatus' = 'approved_interest'
      and scenarios -> 'grant' = 'null'::jsonb
  ) then raise exception 'DEMO_WORLD_V3_PAID_INTEREST_INVALID'; end if;
  if not exists (
    select 1 from jsonb_array_elements(proof -> 'scenarios') scenarios
    where scenarios ->> 'id' = 'team_owner_transfer'
      and (scenarios ->> 'ownerTransferred')::boolean
  ) then raise exception 'DEMO_WORLD_V3_OWNER_TRANSFER_INVALID'; end if;
end;
$assert_demo_v3$;

commit;
