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

insert into auth.users(id, email, email_confirmed_at) values
  ('d2100000-0000-4000-8000-000000000001', 'club-a-owner@example.test', clock_timestamp()),
  ('d2100000-0000-4000-8000-000000000002', 'club-email-target@example.test', clock_timestamp()),
  ('d2100000-0000-4000-8000-000000000003', 'club-wrong-email@example.test', clock_timestamp()),
  ('d2100000-0000-4000-8000-000000000004', 'club-viewer@example.test', clock_timestamp()),
  ('d2100000-0000-4000-8000-000000000005', 'club-team-owner@example.test', clock_timestamp()),
  ('d2100000-0000-4000-8000-000000000006', 'club-team-admin@example.test', clock_timestamp()),
  ('d2100000-0000-4000-8000-000000000007', 'club-other-team-owner@example.test', clock_timestamp()),
  ('d2100000-0000-4000-8000-000000000008', 'club-platform-owner@example.test', clock_timestamp());

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  ('d2200000-0000-4000-8000-000000000001', 'd2100000-0000-4000-8000-000000000005', 'Adversarial Team A', 'CLADV01', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'),
  ('d2200000-0000-4000-8000-000000000002', 'd2100000-0000-4000-8000-000000000007', 'Adversarial Team B', 'CLADV02', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}');

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('d2200000-0000-4000-8000-000000000001', 'd2100000-0000-4000-8000-000000000005', 'owner', 'Team owner'),
  ('d2200000-0000-4000-8000-000000000001', 'd2100000-0000-4000-8000-000000000006', 'admin', 'Team admin'),
  ('d2200000-0000-4000-8000-000000000002', 'd2100000-0000-4000-8000-000000000007', 'owner', 'Other team owner');

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('d2100000-0000-4000-8000-000000000008', 'platform_owner', true);

do $$
declare
  response jsonb;
  club_a_revision bigint;
  club_b_revision bigint;
  organizer_revision bigint;
  email_invitation_id uuid;
  email_token text;
  expired_invitation_id uuid;
  expired_token text;
  revoked_invitation_id uuid;
  revoked_token text;
  relationship_a_id uuid;
  relationship_b_id uuid;
  relationship_c_id uuid;
  relationship_revision bigint;
  entitlement_id uuid;
  owner_membership_id uuid;
begin
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000008');
  perform public.command_pachanga_club_platform_v1(
    'd2300000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-00000000c101', 1, 'club_flags.set',
    '{"foundationEnabled":true,"selfServiceCreationEnabled":true,"teamRelationshipsEnabled":true,"publicProfilesEnabled":true,"competitionOrganizerEnabled":true,"reason":"adversarial fixture"}', '{}'
  );
  perform public.command_pachanga_competition_platform_v1(
    'd2300000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-00000000c001', 1, 'foundation_flags.set',
    '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":false,"reason":"adversarial fixture"}', '{}'
  );

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000003',
    'd2400000-0000-4000-8000-000000000001', 0, 'club.create',
    '{"name":"Club Adversarial A","slug":"club-adversarial-a","clubType":"FOOTBALL_CLUB","countryCode":"ES","province":"Madrid","municipality":"Madrid","generalArea":"Centro","placeId":"private-place-a","visibility":"public","reason":"create A"}', '{}'
  );
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000004',
    'd2400000-0000-4000-8000-000000000002', 0, 'club.create',
    '{"name":"Club Adversarial B","slug":"club-adversarial-b","clubType":"ASSOCIATION","countryCode":"ES","province":"Madrid","municipality":"Madrid","generalArea":"Norte","placeId":"private-place-b","visibility":"private","reason":"create B"}', '{}'
  );

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000008');
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_platform_v1(
    'd2300000-0000-4000-8000-000000000005', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'club.status.set', '{"status":"active","reason":"activate A"}', '{}'
  );
  select revision into club_b_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000002';
  perform public.command_pachanga_club_platform_v1(
    'd2300000-0000-4000-8000-000000000006', 'd2400000-0000-4000-8000-000000000002', club_b_revision,
    'club.status.set', '{"status":"active","reason":"activate B"}', '{}'
  );

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000007', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'membership.invite',
    '{"targetKind":"email_target","targetEmail":"club-email-target@example.test","role":"club_viewer","reason":"email invite"}', '{}'
  );
  email_invitation_id := (response ->> 'invitationId')::uuid;
  email_token := response ->> 'oneTimeToken';

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure(format(
    'select public.get_pachanga_club_invitation_v1(%L::uuid, %L)',
    email_invitation_id, email_token
  ), 'EMAIL_MISMATCH');
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000002');
  perform pg_temp.expect_failure(format(
    'select public.get_pachanga_club_invitation_v1(%L::uuid, %L)',
    email_invitation_id, repeat('0', 64)
  ), 'TOKEN_INVALID');
  response := public.get_pachanga_club_invitation_v1(email_invitation_id, email_token);
  perform pg_temp.assert_true(response ->> 'role' = 'club_viewer', 'Email invitation preview is unavailable to the bound account');
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000008', email_invitation_id, 1,
    'membership.accept', jsonb_build_object('token', email_token, 'reason', 'accept email invite'), '{}'
  );
  perform pg_temp.expect_failure(format(
    'select public.command_pachanga_club_foundation_v1(%L::uuid,%L::uuid,2,%L,%L::jsonb,%L::jsonb)',
    'd2300000-0000-4000-8000-000000000009', email_invitation_id,
    'membership.accept', jsonb_build_object('token', email_token, 'reason', 'reuse token')::text, '{}'::jsonb::text
  ), 'NOT_PENDING|TOKEN_INVALID');

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000010', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'membership.invite', jsonb_build_object(
      'targetKind', 'email_target', 'targetEmail', 'expired@example.test',
      'role', 'club_viewer', 'expiresAt', clock_timestamp() + interval '100 milliseconds',
      'reason', 'expiring invitation'
    ), '{}'
  );
  expired_invitation_id := (response ->> 'invitationId')::uuid;
  expired_token := response ->> 'oneTimeToken';
  perform pg_sleep(0.15);
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure(format(
    'select public.command_pachanga_club_foundation_v1(%L::uuid,%L::uuid,1,%L,%L::jsonb,%L::jsonb)',
    'd2300000-0000-4000-8000-000000000011', expired_invitation_id,
    'membership.accept', jsonb_build_object('token', expired_token, 'reason', 'expired')::text, '{}'::jsonb::text
  ), 'EXPIRED');

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000012', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'membership.invite',
    '{"targetKind":"registered_user","targetUserId":"d2100000-0000-4000-8000-000000000004","role":"club_viewer","reason":"revoke invite"}', '{}'
  );
  revoked_invitation_id := (response ->> 'invitationId')::uuid;
  revoked_token := response ->> 'oneTimeToken';
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000013', revoked_invitation_id, 1,
    'membership.invitation.revoke', '{"reason":"owner revokes"}', '{}'
  );
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000004');
  perform pg_temp.expect_failure(format(
    'select public.command_pachanga_club_foundation_v1(%L::uuid,%L::uuid,2,%L,%L::jsonb,%L::jsonb)',
    'd2300000-0000-4000-8000-000000000014', revoked_invitation_id,
    'membership.accept', jsonb_build_object('token', revoked_token, 'reason', 'revoked')::text, '{}'::jsonb::text
  ), 'NOT_PENDING');

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000005');
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000015', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'team_relationship.request',
    '{"groupId":"d2200000-0000-4000-8000-000000000001","relationshipType":"MEMBER","reason":"first request"}', '{}'
  );
  select id, revision into relationship_a_id, relationship_revision
  from public.pachanga_club_team_relationships
  where club_id = 'd2400000-0000-4000-8000-000000000001'
    and group_id = 'd2200000-0000-4000-8000-000000000001' and status = 'requested';
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000016', relationship_a_id, relationship_revision,
    'team_relationship.reject', '{"reason":"first request rejected"}', '{}'
  );

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000005');
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000017', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'team_relationship.request',
    '{"groupId":"d2200000-0000-4000-8000-000000000001","relationshipType":"MEMBER","reason":"second request"}', '{}'
  );
  select id, revision into relationship_a_id, relationship_revision
  from public.pachanga_club_team_relationships
  where club_id = 'd2400000-0000-4000-8000-000000000001'
    and group_id = 'd2200000-0000-4000-8000-000000000001' and status = 'requested';
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000018', relationship_a_id, relationship_revision,
    'team_relationship.accept', '{"reason":"second request accepted"}', '{}'
  );
  select revision into relationship_revision from public.pachanga_club_team_relationships where id = relationship_a_id;
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000005');
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000019', relationship_a_id, relationship_revision,
    'team_relationship.visibility.set', '{"showOnClubProfile":true,"reason":"team consents"}', '{}'
  );
  response := public.get_pachanga_public_club_v1('club-adversarial-a');
  perform pg_temp.assert_true(jsonb_array_length(response -> 'teams') = 1, 'Public profile ignored explicit Team consent');

  select revision into club_b_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000002';
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000020', 'd2400000-0000-4000-8000-000000000002', club_b_revision,
    'team_relationship.request',
    '{"groupId":"d2200000-0000-4000-8000-000000000001","relationshipType":"AFFILIATED","reason":"multi club request"}', '{}'
  );
  select id, revision into relationship_b_id, relationship_revision
  from public.pachanga_club_team_relationships
  where club_id = 'd2400000-0000-4000-8000-000000000002'
    and group_id = 'd2200000-0000-4000-8000-000000000001' and status = 'requested';
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000021', relationship_b_id, relationship_revision,
    'team_relationship.accept', '{"reason":"multi club accepted"}', '{}'
  );
  perform pg_temp.assert_true((
    select count(*) from public.pachanga_club_team_relationships
    where group_id = 'd2200000-0000-4000-8000-000000000001' and status = 'active'
  ) = 2, 'A Team cannot keep two independent Club relationships');

  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000022', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'team_relationship.invite',
    '{"groupId":"d2200000-0000-4000-8000-000000000002","relationshipType":"HOSTED","reason":"Club invites Team B"}', '{}'
  );
  select id, revision into relationship_c_id, relationship_revision
  from public.pachanga_club_team_relationships
  where club_id = 'd2400000-0000-4000-8000-000000000001'
    and group_id = 'd2200000-0000-4000-8000-000000000002' and status = 'invited';
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000006');
  perform pg_temp.expect_failure(format(
    'select public.command_pachanga_club_foundation_v1(%L::uuid,%L::uuid,%s,%L,%L::jsonb,%L::jsonb)',
    'd2300000-0000-4000-8000-000000000023', relationship_c_id, relationship_revision,
    'team_relationship.accept', '{"reason":"team admin forbidden"}', '{}'
  ), 'TEAM_OWNER_REQUIRED');
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  perform public.command_pachanga_club_foundation_v1(
    'd2300000-0000-4000-8000-000000000024', relationship_c_id, relationship_revision,
    'team_relationship.cancel', '{"reason":"Club cancels its invitation"}', '{}'
  );

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000005');
  response := public.get_pachanga_club_foundation_snapshot_v1('d2400000-0000-4000-8000-000000000002');
  perform pg_temp.assert_true(response #>> '{club,placeId}' is null, 'Linked Team owner received private place data');
  perform pg_temp.assert_true(jsonb_array_length(response -> 'memberships') = 0, 'Linked Team owner received Club staff');
  perform pg_temp.assert_true(jsonb_array_length(response -> 'teamRelationships') = 1, 'Linked Team owner received another Team relationship');

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000008');
  select revision into club_b_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000002';
  perform public.command_pachanga_club_platform_v1(
    'd2300000-0000-4000-8000-000000000025', 'd2400000-0000-4000-8000-000000000002', club_b_revision,
    'club.entitlement.grant',
    '{"capability":"competition_create","source":"platform_grant","validFrom":"2026-01-01T00:00:00Z","expiresAt":"2026-01-02T00:00:00Z","reason":"expired grant"}', '{}'
  );
  select revision into organizer_revision from public.pachanga_competition_organizer_states
  where organizer_kind = 'CLUB' and organizer_club_id = 'd2400000-0000-4000-8000-000000000002';
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  perform pg_temp.expect_failure(format(
    'select public.command_pachanga_competition_foundation_v2(%L::uuid,%L,%L::uuid,%s,%L,%L::jsonb,%L::jsonb)',
    'd2300000-0000-4000-8000-000000000026', 'CLUB', 'd2400000-0000-4000-8000-000000000002', organizer_revision,
    'competition.create', '{"name":"Expired Club Competition","slug":"expired-club-competition","competitionType":"LEAGUE","visibility":"private"}', '{}'
  ), 'ENTITLEMENT_REQUIRED');

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000008');
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_platform_v1(
    'd2300000-0000-4000-8000-000000000027', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'club.entitlement.grant',
    '{"capability":"competition_create","source":"platform_grant","validFrom":"2026-01-01T00:00:00Z","reason":"active grant"}', '{}'
  );
  select id into entitlement_id from public.pachanga_competition_entitlement_grants
  where organizer_kind = 'CLUB' and organizer_club_id = 'd2400000-0000-4000-8000-000000000001' and status = 'active';
  select revision into club_a_revision from public.pachanga_clubs where id = 'd2400000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_platform_v1(
    'd2300000-0000-4000-8000-000000000028', 'd2400000-0000-4000-8000-000000000001', club_a_revision,
    'club.entitlement.revoke', jsonb_build_object('entitlementId', entitlement_id, 'reason', 'explicit revoke'), '{}'
  );
  perform pg_temp.assert_true(not private.pachanga_competition_active_entitlement_v2(
    'CLUB', 'd2400000-0000-4000-8000-000000000001', 'competition_create'
  ), 'Revoked Club entitlement remains active');

  select id into owner_membership_id from public.pachanga_club_memberships
  where club_id = 'd2400000-0000-4000-8000-000000000001'
    and user_id = 'd2100000-0000-4000-8000-000000000001'
    and role = 'club_owner' and status = 'active';
  perform pg_temp.actor('d2100000-0000-4000-8000-000000000001');
  perform pg_temp.expect_failure(format(
    'select public.command_pachanga_club_foundation_v1(%L::uuid,%L::uuid,1,%L,%L::jsonb,%L::jsonb)',
    'd2300000-0000-4000-8000-000000000029', owner_membership_id,
    'membership.revoke', '{"reason":"cannot remove primary owner"}', '{}'
  ), 'PRIMARY_OWNER_TRANSFER_REQUIRED|LAST_CLUB_OWNER_REQUIRED');

  perform pg_temp.actor('d2100000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure(
    'select public.get_pachanga_club_foundation_snapshot_v1(''d2400000-0000-4000-8000-000000000001''::uuid)',
    'FORBIDDEN'
  );
end;
$$;

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.assert_true(
  (public.get_pachanga_public_club_v1('club-adversarial-a') ->> 'name') = 'Club Adversarial A',
  'Anonymous public Club read model is unavailable while gated ON'
);
select pg_temp.expect_failure(
  'select public.command_pachanga_club_foundation_v1(''d2300000-0000-4000-8000-000000000030'', ''d2400000-0000-4000-8000-000000000001'', 1, ''club.profile.update'', ''{}'', ''{}'')',
  'permission denied|Authentication required'
);
reset role;

select pg_temp.assert_true(not exists (
  select 1 from private.pachanga_club_invitation_secrets
  where target_email_normalized is not null and consumed_at is not null
), 'Consumed invitation retained its email contact');
select pg_temp.assert_true(not exists (
  select 1 from public.pachanga_player_profiles where user_id::text like 'd2100000-%'
), 'Club R2 created or modified player profiles');
select pg_temp.assert_true(not exists (
  select 1 from private.pachanga_conduct_reports where reporter_user_id::text like 'd2100000-%'
), 'Club R2 created conduct reports');

rollback;

select 'club-foundation-v1-adversarial-ok' as result;
