\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.r5_activation_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception 'R5_ACTIVATION_ASSERT:%', message; end if;
end;
$$;

create or replace function pg_temp.r5_activation_expect_error(statement text, expected_error text)
returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    execute statement;
  exception when others then
    caught := true;
    if sqlerrm !~ expected_error then
      raise exception 'R5_ACTIVATION_WRONG_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then raise exception 'R5_ACTIVATION_EXPECTED_ERROR_NOT_RAISED:%', expected_error; end if;
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('d5010000-0000-4000-8000-000000000001', 'r5-beta-owner@example.test', clock_timestamp(), '{"full_name":"R5 Beta Owner"}'),
  ('d5010000-0000-4000-8000-000000000002', 'r5-platform@example.test', clock_timestamp(), '{"full_name":"R5 Platform"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values (
  'd5020000-0000-4000-8000-000000000001',
  'd5010000-0000-4000-8000-000000000001',
  'R5 Beta Team', 'R5B101', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'
);
insert into public.pachanga_group_members(group_id, user_id, role, display_name) values (
  'd5020000-0000-4000-8000-000000000001',
  'd5010000-0000-4000-8000-000000000001', 'owner', 'R5 Beta Owner'
);
insert into private.pachanga_platform_admin_roles(user_id, role, active) values (
  'd5010000-0000-4000-8000-000000000002', 'platform_owner', true
);

select set_config(
  'request.jwt.claims',
  '{"sub":"d5010000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

create temporary table r5_activation_state(key text primary key, value jsonb not null);
insert into r5_activation_state values (
  'bundle', public.command_pachanga_league_private_beta_platform_v1(
    'd5030000-0000-4000-8000-000000000001',
    'd5020000-0000-4000-8000-000000000001', 0,
    'beta.bundle.grant',
    '{"organizerKind":"TEAM","maxTeams":12,"expiresAt":"2027-12-31T23:59:59Z","reason":"R5 activation bridge test"}',
    '{"clientVersion":"5.0.0+r5-activation","surface":"r5_activation"}'
  )
);

select pg_temp.r5_activation_assert(
  (select count(*) = 11
   from public.pachanga_competition_entitlement_grants grants
   where grants.bundle_id = (
     select (value #>> '{snapshot,bundle,bundleId}')::uuid
     from r5_activation_state where key='bundle'
   )),
  'legacy bundle must begin with exactly eleven R1-R4 capabilities'
);
select pg_temp.r5_activation_assert(
  private.pachanga_league_private_beta_active_bundle_id_v1(
    'TEAM', 'd5020000-0000-4000-8000-000000000001'
  ) = (
    select (value #>> '{snapshot,bundle,bundleId}')::uuid
    from r5_activation_state where key='bundle'
  ),
  'legacy bundle must remain active before R5 is enabled'
);

update private.pachanga_competition_foundation_settings set
  foundation_enabled=true,
  league_participation_foundation_enabled=true,
  league_registration_enabled=true,
  league_delegates_enabled=true,
  league_rosters_enabled=true,
  league_schedule_preferences_enabled=true,
  league_scheduling_foundation_enabled=true,
  league_schedule_generation_enabled=true,
  league_schedule_editing_enabled=true,
  league_schedule_publication_enabled=true,
  league_canonical_fixture_creation_enabled=true,
  league_match_operations_foundation_enabled=true,
  league_match_squads_enabled=true,
  league_match_attendance_enabled=true,
  league_sporting_results_enabled=true,
  league_result_confirmation_enabled=true,
  league_official_results_enabled=true,
  league_standings_enabled=true,
  competition_discipline_foundation_enabled=false,
  competition_disciplinary_events_enabled=false,
  competition_disciplinary_counters_enabled=false,
  competition_sanctions_enabled=false,
  competition_sanction_service_enabled=false,
  competition_discipline_appeals_enabled=false,
  competition_public_discipline_enabled=false,
  revision=revision+1
where singleton;

select pg_temp.r5_activation_expect_error(format(
  $$select public.command_pachanga_competition_discipline_platform_v1(
    'd5030000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-00000000d501', %s,
    '{"foundationEnabled":true,"eventsEnabled":true,"countersEnabled":true,"sanctionsEnabled":true,"serviceEnabled":true,"appealsEnabled":true,"publicEnabled":false,"reason":"must reject old bundle"}',
    '{"clientVersion":"5.0.0+r5-activation","surface":"r5_activation"}'
  )$$,
  (select revision from private.pachanga_competition_foundation_settings where singleton)
), 'R5_BUNDLE_UPGRADE_REQUIRED');

insert into r5_activation_state values (
  'upgrade', public.command_pachanga_league_private_beta_r5_bundle_upgrade_v1(
    'd5030000-0000-4000-8000-000000000003',
    (select (value #>> '{snapshot,bundle,bundleId}')::uuid
      from r5_activation_state where key='bundle'),
    (select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_kind='TEAM'
        and states.organizer_group_id='d5020000-0000-4000-8000-000000000001'),
    '{"clientVersion":"5.0.0+r5-activation","surface":"r5_activation"}'
  )
);

select pg_temp.r5_activation_assert(
  (select (value #>> '{snapshot,insertedCapabilities}')::integer = 3
   from r5_activation_state where key='upgrade'),
  'explicit upgrade must add exactly three R5 capabilities'
);
select pg_temp.r5_activation_assert(
  (select count(*) = 14
   from public.pachanga_competition_entitlement_grants grants
   where grants.bundle_id = (
     select (value #>> '{snapshot,bundle,bundleId}')::uuid
     from r5_activation_state where key='bundle'
   )),
  'upgraded bundle must contain eleven legacy plus three R5 capabilities'
);
select pg_temp.r5_activation_assert(
  (select value from r5_activation_state where key='upgrade') =
  public.command_pachanga_league_private_beta_r5_bundle_upgrade_v1(
    'd5030000-0000-4000-8000-000000000003',
    (select (value #>> '{snapshot,bundle,bundleId}')::uuid
      from r5_activation_state where key='bundle'),
    (select ((value #>> '{confirmedRevision}')::bigint - 1)
      from r5_activation_state where key='upgrade'),
    '{"clientVersion":"different-replay-metadata"}'
  ),
  'bundle upgrade replay must return the original receipt'
);

insert into r5_activation_state values (
  'flags', public.command_pachanga_competition_discipline_platform_v1(
    'd5030000-0000-4000-8000-000000000004',
    '00000000-0000-0000-0000-00000000d501',
    (select revision from private.pachanga_competition_foundation_settings where singleton),
    '{"foundationEnabled":true,"eventsEnabled":true,"countersEnabled":true,"sanctionsEnabled":true,"serviceEnabled":true,"appealsEnabled":true,"publicEnabled":false,"reason":"activate private R5 beta"}',
    '{"clientVersion":"5.0.0+r5-activation","surface":"r5_activation"}'
  )
);

select pg_temp.r5_activation_assert(
  (select competition_discipline_foundation_enabled
      and competition_disciplinary_events_enabled
      and competition_disciplinary_counters_enabled
      and competition_sanctions_enabled
      and competition_sanction_service_enabled
      and competition_discipline_appeals_enabled
      and not competition_public_discipline_enabled
   from private.pachanga_competition_foundation_settings where singleton),
  'private R5 flags must activate only after the explicit upgrade'
);
select pg_temp.r5_activation_assert(
  cardinality(private.pachanga_league_private_beta_capabilities_v1()) = 14,
  'active bundle contract must require all fourteen capabilities after activation'
);
select pg_temp.r5_activation_assert(
  private.pachanga_league_private_beta_active_bundle_id_v1(
    'TEAM', 'd5020000-0000-4000-8000-000000000001'
  ) = (
    select (value #>> '{snapshot,bundle,bundleId}')::uuid
    from r5_activation_state where key='bundle'
  ),
  'upgraded bundle must remain active after R5 activation'
);

select 'R5_ACTIVATION_REPORT|' || jsonb_build_object(
  'legacyCapabilities', 11,
  'insertedR5Capabilities', 3,
  'activeCapabilities', cardinality(private.pachanga_league_private_beta_capabilities_v1()),
  'publicDiscipline', false,
  'upgradeReplay', true,
  'guardedBeforeUpgrade', true
)::text;

rollback;
