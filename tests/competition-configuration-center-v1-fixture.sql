\set ON_ERROR_STOP on

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('5a010000-0000-4000-8000-000000000001', 'wave5-owner@example.test', clock_timestamp(), '{"full_name":"Wave 5 Owner"}'),
  ('5a010000-0000-4000-8000-000000000002', 'wave5-platform@example.test', clock_timestamp(), '{"full_name":"Wave 5 Platform"}'),
  ('5a010000-0000-4000-8000-000000000003', 'wave5-viewer@example.test', clock_timestamp(), '{"full_name":"Wave 5 Viewer"}'),
  ('5a010000-0000-4000-8000-000000000004', 'wave5-outsider@example.test', clock_timestamp(), '{"full_name":"Wave 5 Outsider"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  ('5a020000-0000-4000-8000-000000000001', '5a010000-0000-4000-8000-000000000001', 'Wave 5 Team', 'W5A101', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'),
  ('5a020000-0000-4000-8000-000000000002', '5a010000-0000-4000-8000-000000000004', 'Wave 5 Other', 'W5A102', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}');

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('5a020000-0000-4000-8000-000000000001', '5a010000-0000-4000-8000-000000000001', 'owner', 'Wave 5 Owner'),
  ('5a020000-0000-4000-8000-000000000002', '5a010000-0000-4000-8000-000000000004', 'owner', 'Wave 5 Outsider');

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('5a010000-0000-4000-8000-000000000002', 'platform_owner', true);

do $$
declare response jsonb;
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"5a010000-0000-4000-8000-000000000002","role":"authenticated"}',
    false
  );

  response := public.command_pachanga_league_private_beta_platform_v1(
    '5a030000-0000-4000-8000-000000000001',
    '5a020000-0000-4000-8000-000000000001',
    0,
    'beta.bundle.grant',
    '{"organizerKind":"TEAM","maxTeams":12,"expiresAt":"2028-12-31T23:59:59Z","reason":"Wave 5A local canonical fixture"}',
    '{"clientVersion":"test","surface":"wave5_fixture"}'
  );

  response := public.command_pachanga_league_private_beta_r5_bundle_upgrade_v1(
    '5a030000-0000-4000-8000-000000000002',
    (
      select grants.bundle_id
      from public.pachanga_competition_entitlement_grants grants
      where grants.organizer_group_id = '5a020000-0000-4000-8000-000000000001'
        and grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
        and grants.status = 'active'
      order by grants.server_sequence desc, grants.id desc
      limit 1
    ),
    (
      select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_kind = 'TEAM'
        and states.organizer_group_id = '5a020000-0000-4000-8000-000000000001'
    ),
    '{"clientVersion":"test","surface":"wave5_fixture"}'
  );
end;
$$;

update private.pachanga_competition_foundation_settings settings set
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
  competition_discipline_foundation_enabled = true,
  competition_disciplinary_events_enabled = true,
  competition_disciplinary_counters_enabled = true,
  competition_sanctions_enabled = true,
  competition_sanction_service_enabled = true,
  competition_discipline_appeals_enabled = true,
  league_public_registration_enabled = false,
  league_public_calendar_enabled = false,
  league_public_standings_enabled = false,
  league_public_exception_status_enabled = false,
  league_private_beta_public_discovery_enabled = false,
  competition_public_discipline_enabled = false,
  revision = settings.revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = '5a010000-0000-4000-8000-000000000002',
  updated_at = clock_timestamp()
where settings.singleton;

do $$
declare response jsonb;
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"5a010000-0000-4000-8000-000000000002","role":"authenticated"}',
    false
  );
  response := public.command_pachanga_competition_configuration_platform_v1(
    '5a030000-0000-4000-8000-000000000003',
    '00000000-0000-0000-0000-00000000c5a1',
    (select settings.revision from private.pachanga_competition_foundation_settings settings where settings.singleton),
    'configuration.flags.set',
    '{"configurationCenterEnabled":true,"wizardV2Enabled":true,"reason":"Wave 5A local activation"}',
    '{"clientVersion":"test","surface":"wave5_fixture"}'
  );
  if not (response #>> '{snapshot,configurationCenterEnabled}')::boolean
     or not (response #>> '{snapshot,wizardV2Enabled}')::boolean then
    raise exception 'WAVE5_PLATFORM_ACTIVATION_FAILED';
  end if;
end;
$$;

update private.pachanga_referee_foundation_settings settings set
  referee_foundation_enabled = true,
  referee_self_service_enabled = true,
  referee_public_profiles_enabled = true,
  referee_marketplace_enabled = true,
  referee_club_relationships_enabled = true,
  referee_assignments_enabled = true,
  referee_assignment_private_beta_enabled = true,
  revision = settings.revision + 1,
  server_sequence = nextval('private.pachanga_referee_sequence'),
  updated_by = '5a010000-0000-4000-8000-000000000002',
  updated_at = clock_timestamp()
where settings.singleton;

do $$
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"5a010000-0000-4000-8000-000000000001","role":"authenticated"}',
    false
  );
end;
$$;

create temporary table wave5_state(
  wizard_id uuid,
  competition_id uuid,
  edition_id uuid,
  source_rule_revision_id uuid,
  draft_id uuid,
  published_rule_revision_id uuid
);

do $$
declare response jsonb;
declare wizard_id uuid;
declare preset_steps jsonb;
declare step_data jsonb;
declare revision bigint := 1;
declare organizer_revision bigint;
begin
  select states.revision into organizer_revision
  from public.pachanga_competition_organizer_states states
  where states.organizer_kind = 'TEAM'
    and states.organizer_group_id = '5a020000-0000-4000-8000-000000000001';
  response := public.command_pachanga_league_private_beta_v2(
    '5a030000-0000-4000-8000-000000000010',
    '5a020000-0000-4000-8000-000000000001',
    organizer_revision,
    'wizard.create',
    '{"organizerKind":"TEAM","authoringMode":"SIMPLE","presetKey":"LEAGUE_F7_STANDARD","reason":"Wave 5A fixture"}',
    '{"clientVersion":"test","surface":"wave5_fixture"}'
  );
  wizard_id := (response #>> '{snapshot,wizard,id}')::uuid;
  preset_steps := private.pachanga_competition_authoring_preset_v1('LEAGUE_F7_STANDARD') -> 'steps';

  for step_number in 1..12 loop
    step_data := preset_steps -> step_number::text;
    if step_number = 1 then
      step_data := step_data || '{"name":"Liga Wave 5A","slug":"liga-wave-5a","description":"Fixture canónica de configuración"}'::jsonb;
    elsif step_number = 3 then
      step_data := step_data || '{"editionName":"Temporada Wave 5A","seasonLabel":"2027","startsAt":"2027-03-01","endsAt":"2027-11-30","timezone":"Europe/Madrid"}'::jsonb;
    elsif step_number = 12 then
      step_data := step_data || '{"consent":true,"acknowledgeUnavailableFeatures":true,"paymentsAcknowledged":true,"tournamentsAcknowledged":true}'::jsonb;
    end if;
    response := public.command_pachanga_league_private_beta_v2(
      ('5a030000-0000-4000-8000-' || lpad((16 + step_number)::text, 12, '0'))::uuid,
      wizard_id,
      revision,
      'wizard.step.save',
      jsonb_build_object('step', step_number, 'data', step_data, 'reason', 'Wave 5A fixture step'),
      '{"clientVersion":"test","surface":"wave5_fixture"}'
    );
    revision := (response ->> 'confirmedRevision')::bigint;
  end loop;

  response := public.command_pachanga_league_private_beta_v2(
    '5a030000-0000-4000-8000-000000000040',
    wizard_id,
    revision,
    'wizard.finalize',
    '{"reason":"Wave 5A fixture finalization"}',
    '{"clientVersion":"test","surface":"wave5_fixture"}'
  );

  insert into wave5_state(wizard_id, competition_id)
  values (wizard_id, (response #>> '{snapshot,canonical,competitionId}')::uuid);
end;
$$;

update wave5_state state set
  edition_id = editions.id,
  source_rule_revision_id = editions.rule_revision_id
from public.pachanga_competition_editions editions
where editions.competition_id = state.competition_id;

insert into public.pachanga_competition_staff_assignments(
  competition_id, user_id, staff_role, status, assigned_by
)
select state.competition_id, '5a010000-0000-4000-8000-000000000003', 'viewer', 'active',
  '5a010000-0000-4000-8000-000000000001'
from wave5_state state;
