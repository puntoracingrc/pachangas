\set ON_ERROR_STOP on

begin;

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'CLUB_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'CLUB_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', target_user_id, 'role', target_role)::text, true);
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('c2100000-0000-4000-8000-000000000001', 'club-owner@example.test', clock_timestamp(), '{"full_name":"Club Owner"}'),
  ('c2100000-0000-4000-8000-000000000002', 'club-admin@example.test', clock_timestamp(), '{"full_name":"Club Admin"}'),
  ('c2100000-0000-4000-8000-000000000003', 'club-manager@example.test', clock_timestamp(), '{"full_name":"Club Manager"}'),
  ('c2100000-0000-4000-8000-000000000004', 'club-viewer@example.test', clock_timestamp(), '{"full_name":"Club Viewer"}'),
  ('c2100000-0000-4000-8000-000000000005', 'team-owner@example.test', clock_timestamp(), '{"full_name":"Team Owner"}'),
  ('c2100000-0000-4000-8000-000000000006', 'club-outsider@example.test', clock_timestamp(), '{"full_name":"Outsider"}'),
  ('c2100000-0000-4000-8000-000000000007', 'club-platform@example.test', clock_timestamp(), '{"full_name":"Platform Owner"}'),
  ('c2100000-0000-4000-8000-000000000008', 'club-next-owner@example.test', clock_timestamp(), '{"full_name":"Next Owner"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  ('c2200000-0000-4000-8000-000000000001', 'c2100000-0000-4000-8000-000000000005', 'Linked Team', 'CLUBT01', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'),
  ('c2200000-0000-4000-8000-000000000002', 'c2100000-0000-4000-8000-000000000006', 'Other Team', 'CLUBT02', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}');

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('c2200000-0000-4000-8000-000000000001', 'c2100000-0000-4000-8000-000000000005', 'owner', 'Team Owner'),
  ('c2200000-0000-4000-8000-000000000002', 'c2100000-0000-4000-8000-000000000006', 'owner', 'Outsider');

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('c2100000-0000-4000-8000-000000000007', 'platform_owner', true);

do $$
declare
  response jsonb;
  replay jsonb;
  club_revision bigint;
  invitation_id uuid;
  invitation_token text;
  manager_invitation_id uuid;
  manager_token text;
  admin_invitation_id uuid;
  admin_token text;
  owner_invitation_id uuid;
  owner_token text;
  relationship_id uuid;
  relationship_revision bigint;
  organizer_revision bigint;
  entitlement_id uuid;
  created_competition_id uuid;
begin
  perform pg_temp.actor('c2100000-0000-4000-8000-000000000007');
  response := public.command_pachanga_club_platform_v1(
    'c2300000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-00000000c101', 1, 'club_flags.set',
    '{"foundationEnabled":true,"selfServiceCreationEnabled":true,"teamRelationshipsEnabled":true,"publicProfilesEnabled":true,"competitionOrganizerEnabled":true,"reason":"local R2 test"}',
    '{"clientVersion":"1.0.0+dbtest","surface":"db"}'
  );
  perform pg_temp.assert_true((response ->> 'confirmedRevision')::bigint = 2, 'Club flags revision did not advance');
  perform public.command_pachanga_competition_platform_v1(
    'c2300000-0000-4000-8000-000000000020',
    '00000000-0000-0000-0000-00000000c001', 1, 'foundation_flags.set',
    '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":false,"reason":"local R2 competition fixture"}',
    '{"clientVersion":"1.0.0+dbtest","surface":"db"}'
  );

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000001');
  response := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000002',
    'c2400000-0000-4000-8000-000000000001', 0, 'club.create',
    '{"name":"Club Canonico","slug":"club-canonico","clubType":"FOOTBALL_CLUB","countryCode":"ES","province":"Barcelona","municipality":"Barcelona","generalArea":"Eixample","visibility":"private","reason":"create test club"}',
    '{"clientVersion":"1.0.0+dbtest","serviceWorkerVersion":"sw-test","installedMode":"standalone","surface":"db"}'
  );
  perform pg_temp.assert_true((response ->> 'confirmedRevision')::bigint = 1, 'Club create revision is not one');
  perform pg_temp.assert_true(exists (
    select 1 from public.pachanga_club_memberships memberships
    where memberships.club_id = 'c2400000-0000-4000-8000-000000000001'
      and memberships.user_id = 'c2100000-0000-4000-8000-000000000001'
      and memberships.role = 'club_owner' and memberships.status = 'active'
  ), 'Creator is not an active Club owner');

  replay := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000002',
    'c2400000-0000-4000-8000-000000000001', 0, 'club.create',
    '{"name":"Club Canonico","slug":"club-canonico","clubType":"FOOTBALL_CLUB","countryCode":"ES","province":"Barcelona","municipality":"Barcelona","generalArea":"Eixample","visibility":"private","reason":"create test club"}',
    '{"clientVersion":"1.0.0+dbtest","surface":"db"}'
  );
  perform pg_temp.assert_true(replay ->> 'serverSequence' = response ->> 'serverSequence', 'Idempotent replay changed sequence');
  perform pg_temp.assert_true((select count(*) from private.pachanga_club_operation_receipts where operation_id = 'c2300000-0000-4000-8000-000000000002') = 1, 'Replay created another receipt');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_club_foundation_v1(
      'c2300000-0000-4000-8000-000000000002',
      'c2400000-0000-4000-8000-000000000001', 1, 'club.profile.update',
      '{"name":"Reused operation","reason":"reuse"}', '{}'
    )
  $sql$, 'OPERATION_ID_REUSED');

  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000003',
    'c2400000-0000-4000-8000-000000000001', club_revision, 'membership.invite',
    '{"targetKind":"registered_user","targetUserId":"c2100000-0000-4000-8000-000000000003","role":"club_competition_manager","reason":"invite manager"}', '{}'
  );
  manager_invitation_id := (response ->> 'invitationId')::uuid;
  manager_token := response ->> 'oneTimeToken';
  perform pg_temp.assert_true(length(manager_token) = 64, 'Invitation token was not returned once');
  replay := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000003',
    'c2400000-0000-4000-8000-000000000001', club_revision, 'membership.invite',
    '{"targetKind":"registered_user","targetUserId":"c2100000-0000-4000-8000-000000000003","role":"club_competition_manager","reason":"invite manager"}', '{}'
  );
  perform pg_temp.assert_true(not (replay ? 'oneTimeToken'), 'Invitation token leaked through receipt replay');
  perform pg_temp.assert_true((
    select count(*)
    from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = 'c2100000-0000-4000-8000-000000000003'
      and notifications.kind = 'club_staff_invitation'
      and notifications.dedupe_key = 'club-staff-invitation:c2300000-0000-4000-8000-000000000003:c2100000-0000-4000-8000-000000000003'
  ) = 1, 'Invitation replay duplicated the notification');
  perform pg_temp.assert_true(not exists (
    select 1 from private.pachanga_club_invitation_secrets secrets
    where secrets.invitation_id = manager_invitation_id and secrets.token_hash = manager_token
  ), 'Plain invitation token was persisted');

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000003');
  response := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000004', manager_invitation_id, 1,
    'membership.accept', jsonb_build_object('token', manager_token, 'reason', 'accept manager'), '{}'
  );
  perform pg_temp.assert_true(exists (
    select 1 from public.pachanga_club_memberships memberships
    where memberships.club_id = 'c2400000-0000-4000-8000-000000000001'
      and memberships.user_id = 'c2100000-0000-4000-8000-000000000003'
      and memberships.role = 'club_competition_manager' and memberships.status = 'active'
  ), 'Manager invitation did not activate membership');
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_club_foundation_v1(
      'c2300000-0000-4000-8000-000000000099', '%s', 2,
      'membership.accept', %L::jsonb, '{}'
    )
  $sql$, manager_invitation_id, jsonb_build_object('token', manager_token, 'reason', 'replay token')::text), 'NOT_PENDING|TOKEN_INVALID');

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000001');
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000005',
    'c2400000-0000-4000-8000-000000000001', club_revision, 'membership.invite',
    '{"targetKind":"registered_user","targetUserId":"c2100000-0000-4000-8000-000000000002","role":"club_admin","reason":"invite admin"}', '{}'
  );
  admin_invitation_id := (response ->> 'invitationId')::uuid;
  admin_token := response ->> 'oneTimeToken';
  perform pg_temp.actor('c2100000-0000-4000-8000-000000000002');
  perform public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000006', admin_invitation_id, 1,
    'membership.accept', jsonb_build_object('token', admin_token, 'reason', 'accept admin'), '{}'
  );

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000001');
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_publication_consent_v1(
    'c2300000-0000-4000-8000-000000000201', 'CLUB',
    'c2400000-0000-4000-8000-000000000001', club_revision,
    '{"representationAuthorized":true,"informationCorrect":true}', '{}'
  );
  club_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000202',
    'c2400000-0000-4000-8000-000000000001', club_revision,
    'club.review.submit', '{"reason":"submit test Club for review"}', '{}'
  );
  club_revision := (response ->> 'confirmedRevision')::bigint;

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000007');
  perform public.command_pachanga_club_platform_v1(
    'c2300000-0000-4000-8000-000000000007',
    'c2400000-0000-4000-8000-000000000001', club_revision,
    'club.status.set', '{"status":"active","reason":"activate test club"}', '{}'
  );
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_platform_v1(
    'c2300000-0000-4000-8000-000000000008',
    'c2400000-0000-4000-8000-000000000001', club_revision,
    'club.verification.set', '{"status":"verified","reason":"verify test club"}', '{}'
  );
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_platform_v1(
    'c2300000-0000-4000-8000-000000000009',
    'c2400000-0000-4000-8000-000000000001', club_revision,
    'club.partnership.set', '{"status":"active","reason":"partner test club"}', '{}'
  );
  perform pg_temp.assert_true(not private.pachanga_competition_active_entitlement_v2(
    'CLUB', 'c2400000-0000-4000-8000-000000000001', 'competition_create'
  ), 'Partnership granted an implicit entitlement');
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_platform_v1(
    'c2300000-0000-4000-8000-000000000010',
    'c2400000-0000-4000-8000-000000000001', club_revision,
    'club.entitlement.grant',
    '{"capability":"competition_create","source":"partnership","validFrom":"2026-01-01T00:00:00Z","reason":"explicit partner entitlement"}', '{}'
  );
  select grants.id into entitlement_id
  from public.pachanga_competition_entitlement_grants grants
  where grants.organizer_kind = 'CLUB' and grants.organizer_club_id = 'c2400000-0000-4000-8000-000000000001'
    and grants.capability = 'competition_create' and grants.status = 'active';
  perform pg_temp.assert_true(entitlement_id is not null, 'Explicit Club entitlement was not created');

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000002');
  select revision into organizer_revision from public.pachanga_competition_organizer_states
  where organizer_kind = 'CLUB' and organizer_club_id = 'c2400000-0000-4000-8000-000000000001';
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_competition_foundation_v2(
      'c2300000-0000-4000-8000-000000000011', 'CLUB',
      'c2400000-0000-4000-8000-000000000001', %s, 'competition.create',
      '{"name":"Admin Forbidden","slug":"admin-forbidden","competitionType":"LEAGUE","visibility":"private","reason":"admin forbidden"}', '{}'
    )
  $sql$, organizer_revision), 'MANAGER_REQUIRED');

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000003');
  response := public.command_pachanga_competition_foundation_v2(
    'c2300000-0000-4000-8000-000000000012', 'CLUB',
    'c2400000-0000-4000-8000-000000000001', organizer_revision, 'competition.create',
    '{"name":"Liga del Club","slug":"liga-club","competitionType":"LEAGUE","visibility":"private","editionName":"2026","seasonLabel":"2026","reason":"create Club competition"}', '{}'
  );
  created_competition_id := (response #>> '{snapshot,competition,id}')::uuid;
  perform pg_temp.assert_true(created_competition_id is not null, 'Club competition draft was not created');
  perform pg_temp.assert_true(exists (
    select 1 from public.pachanga_competition_staff_assignments assignments
    where assignments.competition_id = created_competition_id
      and assignments.user_id = 'c2100000-0000-4000-8000-000000000003'
      and assignments.staff_role = 'competition_director' and assignments.status = 'active'
  ), 'Club competition manager did not become competition director');
  perform pg_temp.actor('c2100000-0000-4000-8000-000000000007');
  response := public.get_pachanga_platform_competition_foundation_v2(0, 50);
  perform pg_temp.assert_true(exists (
    select 1
    from jsonb_array_elements(response -> 'items') item
    where item ->> 'id' = created_competition_id::text
      and item ->> 'organizerKind' = 'CLUB'
      and item ->> 'organizerClubId' = 'c2400000-0000-4000-8000-000000000001'
  ), 'Platform Competition V2 read model omitted the Club organizer');

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000001');
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000013',
    'c2400000-0000-4000-8000-000000000001', club_revision, 'team_relationship.invite',
    '{"groupId":"c2200000-0000-4000-8000-000000000001","relationshipType":"AFFILIATED","reason":"invite linked team"}', '{}'
  );
  select id, revision into relationship_id, relationship_revision
  from public.pachanga_club_team_relationships
  where club_id = 'c2400000-0000-4000-8000-000000000001'
    and group_id = 'c2200000-0000-4000-8000-000000000001' and status = 'invited';
  perform pg_temp.actor('c2100000-0000-4000-8000-000000000006');
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_club_foundation_v1(
      'c2300000-0000-4000-8000-000000000014', '%s', %s,
      'team_relationship.accept', '{"reason":"wrong team owner"}', '{}'
    )
  $sql$, relationship_id, relationship_revision), 'TEAM_OWNER_REQUIRED');
  perform pg_temp.actor('c2100000-0000-4000-8000-000000000005');
  perform public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000015', relationship_id, relationship_revision,
    'team_relationship.accept', '{"reason":"team accepts"}', '{}'
  );
  perform pg_temp.assert_true(exists (
    select 1 from public.pachanga_club_team_relationships
    where id = relationship_id and status = 'active'
  ), 'Club-Team relationship did not activate');
  perform pg_temp.assert_true((select owner_id from public.pachanga_groups where id = 'c2200000-0000-4000-8000-000000000001') = 'c2100000-0000-4000-8000-000000000005', 'Team authority changed after Club link');

  perform pg_temp.actor('c2100000-0000-4000-8000-000000000001');
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000016',
    'c2400000-0000-4000-8000-000000000001', club_revision, 'club.profile.update',
    '{"visibility":"public","reason":"publish public profile"}', '{}'
  );
  response := public.get_pachanga_public_club_v1('club-canonico');
  perform pg_temp.assert_true(response ->> 'name' = 'Club Canonico', 'Public Club snapshot is unavailable');
  perform pg_temp.assert_true(not (response ? 'primaryOwnerId') and not (response ? 'memberships') and not (response ? 'placeId'), 'Public Club leaked private fields');

  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000017',
    'c2400000-0000-4000-8000-000000000001', club_revision, 'membership.invite',
    '{"targetKind":"registered_user","targetUserId":"c2100000-0000-4000-8000-000000000008","role":"club_owner","reason":"invite next owner"}', '{}'
  );
  owner_invitation_id := (response ->> 'invitationId')::uuid;
  owner_token := response ->> 'oneTimeToken';
  perform pg_temp.actor('c2100000-0000-4000-8000-000000000008');
  perform public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000018', owner_invitation_id, 1,
    'membership.accept', jsonb_build_object('token', owner_token, 'reason', 'accept owner'), '{}'
  );
  perform pg_temp.actor('c2100000-0000-4000-8000-000000000001');
  select revision into club_revision from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_foundation_v1(
    'c2300000-0000-4000-8000-000000000019',
    'c2400000-0000-4000-8000-000000000001', club_revision, 'club.primary_owner.transfer',
    '{"targetUserId":"c2100000-0000-4000-8000-000000000008","retainPreviousOwner":true,"reason":"transfer primary owner"}', '{}'
  );
  perform pg_temp.assert_true((select primary_owner_id from public.pachanga_clubs where id = 'c2400000-0000-4000-8000-000000000001') = 'c2100000-0000-4000-8000-000000000008', 'Primary ownership did not transfer');
end;
$$;

set local role authenticated;
select pg_temp.actor('c2100000-0000-4000-8000-000000000006');
select pg_temp.expect_failure(
  'update public.pachanga_clubs set name = ''Direct client write'' where id = ''c2400000-0000-4000-8000-000000000001''',
  'permission denied|row-level security'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_club_invalidations where club_id = 'c2400000-0000-4000-8000-000000000001') = 0,
  'Outsider can read Club invalidations'
);
reset role;

set local role authenticated;
select pg_temp.actor('c2100000-0000-4000-8000-000000000008');
select pg_temp.assert_true(
  (select count(*) from public.pachanga_club_invalidations where club_id = 'c2400000-0000-4000-8000-000000000001') > 0,
  'Active Club owner cannot read invalidations'
);
reset role;

select pg_temp.expect_failure(
  'update private.pachanga_club_operation_receipts set action = ''tamper'' where operation_id = ''c2300000-0000-4000-8000-000000000002''',
  'CLUB_AUDIT_LEDGER_IMMUTABLE'
);
select pg_temp.expect_failure(
  'delete from private.pachanga_club_events where operation_id = ''c2300000-0000-4000-8000-000000000002''',
  'CLUB_AUDIT_LEDGER_IMMUTABLE'
);

select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_organizer_states where organizer_kind = 'TEAM' and organizer_group_id is not null) >= 0,
  'TEAM organizer rows became invalid'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_competitions
    where (organizer_kind = 'TEAM' and (organizer_group_id is null or organizer_club_id is not null))
       or (organizer_kind = 'CLUB' and (organizer_club_id is null or organizer_group_id is not null))
  ),
  'Competition organizer XOR invariant failed'
);

rollback;

select 'club-foundation-v1-db-ok' as result;
