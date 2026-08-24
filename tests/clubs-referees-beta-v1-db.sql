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

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'BETA_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'BETA_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
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
  ('b4010000-0000-4000-8000-000000000001', 'beta-platform@example.test', clock_timestamp(), '{"full_name":"Platform"}'),
  ('b4010000-0000-4000-8000-000000000002', 'beta-club-owner@example.test', clock_timestamp(), '{"full_name":"Club Owner"}'),
  ('b4010000-0000-4000-8000-000000000003', 'beta-team-owner@example.test', clock_timestamp(), '{"full_name":"Team Owner"}'),
  ('b4010000-0000-4000-8000-000000000004', 'beta-team-admin@example.test', clock_timestamp(), '{"full_name":"Team Admin"}'),
  ('b4010000-0000-4000-8000-000000000005', 'beta-referee@example.test', clock_timestamp(), '{"full_name":"Alex Arbitro"}'),
  ('b4010000-0000-4000-8000-000000000006', 'beta-outsider@example.test', clock_timestamp(), '{"full_name":"Outsider"}');

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('b4010000-0000-4000-8000-000000000001', 'platform_owner', true);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values
  ('b4020000-0000-4000-8000-000000000001', 'b4010000-0000-4000-8000-000000000003', 'Equipo Beta', 'BETAT01', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}');
insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('b4020000-0000-4000-8000-000000000001', 'b4010000-0000-4000-8000-000000000003', 'owner', 'Team Owner'),
  ('b4020000-0000-4000-8000-000000000001', 'b4010000-0000-4000-8000-000000000004', 'admin', 'Team Admin');
insert into public.pachanga_challengeable_team_profiles(
  group_id, enabled, zone_label, zone_place_id, zone_lat, zone_lng,
  travel_radius_km, modalities, created_by, updated_by
) values (
  'b4020000-0000-4000-8000-000000000001', true, 'Sabadell', 'beta-place', 41.5463, 2.1086,
  20, array['futbol7'], 'b4010000-0000-4000-8000-000000000003', 'b4010000-0000-4000-8000-000000000003'
);

do $$
declare
  response jsonb;
  replay jsonb;
  directory jsonb;
  club_revision bigint;
  profile_revision bigint;
  relationship_id uuid := 'b4090000-0000-4000-8000-000000000001';
  relationship_token text;
  team_relationship_id uuid;
begin
  perform pg_temp.actor('b4010000-0000-4000-8000-000000000001');
  perform public.command_pachanga_club_platform_v1(
    'b4030000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-00000000c101', 1, 'club_flags.set',
    '{"foundationEnabled":true,"selfServiceCreationEnabled":true,"teamRelationshipsEnabled":true,"publicProfilesEnabled":true,"competitionOrganizerEnabled":false,"reason":"Wave 1 DB test"}', '{}'
  );
  perform public.command_pachanga_referee_platform_admin_v1(
    'b4030000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-00000000a3f3', 1, 'referee_flags.set',
    '{"foundationEnabled":true,"selfServiceEnabled":true,"publicProfilesEnabled":true,"marketplaceEnabled":true,"clubRelationshipsEnabled":true,"assignmentsEnabled":false,"reason":"Wave 1 DB test"}', '{}'
  );

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000002');
  response := public.command_pachanga_club_foundation_v1(
    'b4030000-0000-4000-8000-000000000003',
    'b4040000-0000-4000-8000-000000000001', 0, 'club.create',
    '{"name":"Club Beta Canonico","slug":"club-beta-canonico","clubType":"FOOTBALL_CLUB","countryCode":"ES","province":"Barcelona","municipality":"Sabadell","generalArea":"Valles Occidental","description":"Club publico para validar Wave 1.","visibility":"public","reason":"create beta Club"}',
    '{"clientVersion":"1.0.0+dbtest","serviceWorkerVersion":"sw-beta","installedMode":"standalone","surface":"db"}'
  );
  perform pg_temp.assert_true((response ->> 'confirmedRevision')::bigint = 1, 'Club draft revision is not one');
  perform pg_temp.assert_true(public.get_pachanga_public_club_v1('club-beta-canonico') is null, 'Draft Club leaked publicly');

  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_club_foundation_v1(
      'b4030000-0000-4000-8000-000000000004',
      'b4040000-0000-4000-8000-000000000001', 1, 'club.review.submit',
      '{"reason":"missing consent"}', '{}'
    )
  $sql$, 'CLUB_PUBLICATION_CONSENT_REQUIRED');

  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_publication_consent_v1(
      'b4030000-0000-4000-8000-000000000005', 'CLUB',
      'b4040000-0000-4000-8000-000000000001', 1,
      '{"representationAuthorized":true,"informationCorrect":false}', '{}'
    )
  $sql$, 'CLUB_PUBLICATION_CONFIRMATIONS_REQUIRED');

  response := public.command_pachanga_publication_consent_v1(
    'b4030000-0000-4000-8000-000000000006', 'CLUB',
    'b4040000-0000-4000-8000-000000000001', 1,
    '{"representationAuthorized":true,"informationCorrect":true}',
    '{"clientVersion":"1.0.0+dbtest","surface":"db"}'
  );
  replay := public.command_pachanga_publication_consent_v1(
    'b4030000-0000-4000-8000-000000000006', 'CLUB',
    'b4040000-0000-4000-8000-000000000001', 1,
    '{"representationAuthorized":true,"informationCorrect":true}',
    '{"clientVersion":"1.0.0+dbtest","surface":"db"}'
  );
  perform pg_temp.assert_true(response ->> 'serverSequence' = replay ->> 'serverSequence', 'Club consent replay diverged');
  perform pg_temp.assert_true((select count(*) from private.pachanga_publication_consents where operation_id = 'b4030000-0000-4000-8000-000000000006') = 1, 'Club consent replay duplicated evidence');
  club_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_club_foundation_v1(
    'b4030000-0000-4000-8000-000000000007',
    'b4040000-0000-4000-8000-000000000001', club_revision, 'club.review.submit',
    '{"reason":"submit beta review"}', '{}'
  );
  club_revision := (response ->> 'confirmedRevision')::bigint;

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000001');
  response := public.command_pachanga_club_platform_v1(
    'b4030000-0000-4000-8000-000000000008',
    'b4040000-0000-4000-8000-000000000001', club_revision, 'club.status.set',
    '{"status":"active","reason":"approve beta Club"}', '{}'
  );
  club_revision := (response ->> 'confirmedRevision')::bigint;
  directory := public.search_pachanga_public_clubs_v1('{"verified":"false","municipality":"Sabadell"}', 1, 24);
  perform pg_temp.assert_true((directory ->> 'total')::integer = 1, 'Active public unverified Club missing from directory');
  perform pg_temp.assert_true(not (directory #>> '{items,0,verified}')::boolean, 'Operational approval implied verification');
  perform pg_temp.assert_true(directory::text !~* 'email|phone|primaryOwner|targetUser|entitlement', 'Public Club directory leaked private fields');
  perform public.command_pachanga_club_platform_v1(
    'b4030000-0000-4000-8000-000000000009',
    'b4040000-0000-4000-8000-000000000001', club_revision, 'club.verification.set',
    '{"status":"verified","reason":"verify separately"}', '{}'
  );

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000006');
  perform public.command_pachanga_club_foundation_v1(
    'b4030000-0000-4000-8000-000000000026',
    'b4040000-0000-4000-8000-000000000002', 0, 'club.create',
    '{"name":"Club Beta Borrador","slug":"club-beta-borrador","clubType":"FOOTBALL_CLUB","countryCode":"ES","province":"Barcelona","municipality":"Terrassa","generalArea":"Valles Occidental","description":"No disponible para relaciones.","visibility":"private","reason":"negative draft Club"}', '{}'
  );

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000002');
  response := public.get_my_pachanga_clubs_beta_v1();
  perform pg_temp.assert_true(response #>> '{clubs,0,teamCandidates,0,name}' = 'Equipo Beta', 'Public team candidate missing from Club workspace');
  perform pg_temp.assert_true((response #> '{clubs,0,teamCandidates}')::text !~* 'zoneLat|zoneLng|ownerId|beta-place', 'Team candidate leaked coordinates, owner identity or place ID');
  select revision into club_revision from public.pachanga_clubs where id = 'b4040000-0000-4000-8000-000000000001';
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_club_foundation_v1(
      'b4030000-0000-4000-8000-000000000027',
      'b4040000-0000-4000-8000-000000000001', %s, 'club.profile.update',
      '{"name":"Cambio sin retirar publicación","reason":"must pause public profile"}', '{}'
    )
  $sql$, club_revision), 'CLUB_PUBLICATION_PAUSE_REQUIRED');
  response := public.command_pachanga_club_foundation_v1(
    'b4030000-0000-4000-8000-000000000010',
    'b4040000-0000-4000-8000-000000000001', club_revision, 'team_relationship.invite',
    '{"groupId":"b4020000-0000-4000-8000-000000000001","relationshipType":"AFFILIATED","reason":"invite team"}', '{}'
  );
  team_relationship_id := (response #>> '{snapshot,teamRelationships,0,id}')::uuid;
  response := public.get_my_pachanga_clubs_beta_v1();
  perform pg_temp.assert_true(jsonb_array_length(response #> '{clubs,0,teamCandidates}') = 0, 'Pending relationship did not remove team from invitation candidates');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000004');
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_club_foundation_v1(
      'b4030000-0000-4000-8000-000000000011', %L::uuid, 1,
      'team_relationship.accept', '{"reason":"admin cannot accept"}', '{}'
    )
  $sql$, team_relationship_id), 'TEAM_OWNER_REQUIRED');
  perform pg_temp.actor('b4010000-0000-4000-8000-000000000003');
  response := public.get_my_pachanga_clubs_beta_v1();
  perform pg_temp.assert_true(response #>> '{clubs,0,teamRelationships,0,status}' = 'invited', 'Team owner cannot read the pending Club invitation');
  perform pg_temp.assert_true(not coalesce((response #>> '{clubs,0,capabilities,teamLinksManage}')::boolean, false), 'Team owner incorrectly gained Club management capability');
  perform public.command_pachanga_club_foundation_v1(
    'b4030000-0000-4000-8000-000000000012', team_relationship_id, 1,
    'team_relationship.accept', '{"reason":"owner accepts"}', '{}'
  );

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000005');
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000013',
    'b4050000-0000-4000-8000-000000000001', 0, 'profile.create',
    '{"slug":"alex-arbitro-beta","bio":"Arbitro amateur.","experienceSinceYear":2019,"experienceSummary":"Futbol 7 y futbol sala.","availabilityStatus":"AVAILABLE","reason":"create referee"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000014',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.modalities.replace',
    '{"modalities":[{"modality":"FOOTBALL_7","experienceSinceYear":2019}],"reason":"modalities"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000015',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.areas.replace',
    '{"areas":[{"countryCode":"ES","province":"Barcelona","municipality":"Sabadell","generalArea":"Valles Occidental","travelRadiusKm":30}],"reason":"areas"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000016',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.update',
    '{"visibility":"public","availabilityStatus":"AVAILABLE","availableForAssignments":true,"shareRecurringAvailability":false,"reason":"public settings"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_referee_platform_v1(
      'b4030000-0000-4000-8000-000000000017',
      'b4050000-0000-4000-8000-000000000001', %s, 'profile.activate',
      '{"reason":"missing consent"}', '{}'
    )
  $sql$, profile_revision), 'REFEREE_PUBLICATION_CONSENT_REQUIRED');
  response := public.command_pachanga_publication_consent_v1(
    'b4030000-0000-4000-8000-000000000018', 'REFEREE_PROFILE',
    'b4050000-0000-4000-8000-000000000001', profile_revision,
    '{"informationCorrect":true,"unverifiedNotCertification":true,"publicZonesAvailability":true}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000019',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.activate',
    '{"reason":"activate"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000020',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'marketplace.list',
    '{"reason":"list"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.assert_true((public.search_pachanga_referee_market_v1('{"modality":"FOOTBALL_7","municipality":"Sabadell"}', 1, 24) ->> 'total')::integer = 1, 'Referee missing from marketplace');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000001');
  response := public.command_pachanga_referee_platform_admin_v1(
    'b4030000-0000-4000-8000-000000000031',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.suspend',
    '{"reason":"suspend referee for restore regression"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    public.get_pachanga_public_referee_v1('alex-arbitro-beta') is null,
    'Suspended referee remained public'
  );
  response := public.command_pachanga_referee_platform_admin_v1(
    'b4030000-0000-4000-8000-000000000032',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.restore',
    '{"reason":"restore referee privately"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    response #>> '{snapshot,profile,visibility}' = 'private'
      and response #>> '{snapshot,profile,marketplaceStatus}' = 'not_listed'
      and not (response #>> '{snapshot,profile,availableForAssignments}')::boolean,
    'Restored referee was not safely private, unlisted and unavailable'
  );

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000005');
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000033',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.update',
    '{"availableForAssignments":true,"reason":"prepare explicit republication"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_publication_consent_v1(
    'b4030000-0000-4000-8000-000000000034', 'REFEREE_PROFILE',
    'b4050000-0000-4000-8000-000000000001', profile_revision,
    '{"informationCorrect":true,"unverifiedNotCertification":true,"publicZonesAvailability":true}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000035',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'profile.update',
    '{"visibility":"public","reason":"explicit republication"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000036',
    'b4050000-0000-4000-8000-000000000001', profile_revision, 'marketplace.list',
    '{"reason":"relist after explicit republication"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;

  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_referee_platform_v1(
      'b4030000-0000-4000-8000-000000000021',
      'b4050000-0000-4000-8000-000000000001', %s, 'profile.update',
      '{"bio":"Edit while listed","reason":"should pause"}', '{}'
    )
  $sql$, profile_revision), 'REFEREE_PUBLICATION_PAUSE_REQUIRED');
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_referee_platform_v1(
      'b4030000-0000-4000-8000-000000000030',
      'b4050000-0000-4000-8000-000000000001', %s, 'profile.update',
      '{"availableForAssignments":false,"reason":"market availability needs republishing"}', '{}'
    )
  $sql$, profile_revision), 'REFEREE_PUBLICATION_PAUSE_REQUIRED');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'b4030000-0000-4000-8000-000000000028',
      'b4090000-0000-4000-8000-000000000002', 0, 'relationship.request',
      '{"clubId":"b4040000-0000-4000-8000-000000000002","relationshipType":"REGULAR","reason":"draft Club unavailable"}', '{}'
    )
  $sql$, 'REFEREE_RELATIONSHIP_CLUB_NOT_ACTIVE');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'b4030000-0000-4000-8000-000000000022',
      'b4080000-0000-4000-8000-000000000001', 0, 'assignment.propose',
      '{"refereeProfileId":"b4050000-0000-4000-8000-000000000001","requesterKind":"TEAM","requesterId":"b4020000-0000-4000-8000-000000000001","sourceKind":"group_match","sourceGroupId":"b4020000-0000-4000-8000-000000000001","sourceId":"future-match"}', '{}'
    )
  $sql$, 'REFEREE_ASSIGNMENTS_DISABLED|FEATURE_NOT_AVAILABLE');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000002');
  select revision into club_revision from public.pachanga_clubs where id = 'b4040000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_referee_invite_by_profile_v1(
    relationship_id, 'b4040000-0000-4000-8000-000000000001', club_revision,
    'b4050000-0000-4000-8000-000000000001', 'REGULAR', '{}'
  );
  relationship_token := response ->> 'oneTimeToken';
  perform pg_temp.assert_true(length(relationship_token) = 64, 'Club-referee token was not returned once');
  perform pg_temp.assert_true(exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = 'b4010000-0000-4000-8000-000000000005'
      and notifications.kind = 'referee_club_invitation'
      and notifications.action_url = '/perfil/arbitro?section=clubs&relationship=' || relationship_id::text
  ), 'Club-referee invitation notification did not route the referee to their own profile');
  replay := public.command_pachanga_club_referee_invite_by_profile_v1(
    relationship_id, 'b4040000-0000-4000-8000-000000000001', club_revision,
    'b4050000-0000-4000-8000-000000000001', 'REGULAR', '{}'
  );
  perform pg_temp.assert_true(not replay ? 'oneTimeToken', 'Club-referee replay leaked one-time token');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000005');
  perform public.command_pachanga_referee_platform_v1(
    'b4030000-0000-4000-8000-000000000023', relationship_id, 1,
    'relationship.accept', jsonb_build_object('token', relationship_token, 'reason', 'accept Club'), '{}'
  );
  perform pg_temp.assert_true((select count(*) from public.pachanga_club_referee_relationships where id = relationship_id and status = 'active') = 1, 'Club-referee relation was not activated');
  perform pg_temp.assert_true(exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = 'b4010000-0000-4000-8000-000000000002'
      and notifications.kind = 'referee_club_relationship_accepted'
      and notifications.action_url = '/clubes/gestionar?club=b4040000-0000-4000-8000-000000000001&section=arbitros&relationship=' || relationship_id::text
  ), 'Club-referee response notification did not route the Club initiator to Club management');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000002');
  response := public.get_my_pachanga_clubs_beta_v1();
  perform pg_temp.assert_true(response::text !~* 'beta-referee@example.test|targetUserId|tokenHash', 'Club beta read leaked referee identity or secret');
  perform pg_temp.assert_true(response #>> '{clubs,0,refereeRelationships,0,refereeName}' = 'Alex Arbitro', 'Club beta read lacks friendly referee name');
  perform pg_temp.assert_true((select count(*) from public.pachanga_user_notifications where kind = 'club_review_submitted') = 1, 'Review notification missing or duplicated');
  perform pg_temp.assert_true((select count(*) from public.pachanga_user_notifications where kind = 'club_review_approved') = 1, 'Approval notification missing or duplicated');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000001');
  select revision into club_revision from public.pachanga_clubs where id = 'b4040000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_platform_v1(
    'b4030000-0000-4000-8000-000000000024',
    'b4040000-0000-4000-8000-000000000001', club_revision, 'club.status.set',
    '{"status":"suspended","reason":"negative beta check"}', '{}'
  );
  perform pg_temp.actor('b4010000-0000-4000-8000-000000000002');
  select revision into club_revision from public.pachanga_clubs where id = 'b4040000-0000-4000-8000-000000000001';
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_club_foundation_v1(
      'b4030000-0000-4000-8000-000000000025',
      'b4040000-0000-4000-8000-000000000001', %s, 'team_relationship.invite',
      '{"groupId":"b4020000-0000-4000-8000-000000000001","relationshipType":"AFFILIATED","reason":"suspended Club cannot invite"}', '{}'
    )
  $sql$, club_revision), 'CLUB_NOT_ACTIVE');

  perform pg_temp.actor('b4010000-0000-4000-8000-000000000001');
  select revision into club_revision from public.pachanga_clubs
  where id = 'b4040000-0000-4000-8000-000000000001';
  perform public.command_pachanga_club_platform_v1(
    'b4030000-0000-4000-8000-000000000029',
    'b4040000-0000-4000-8000-000000000001', club_revision, 'club.status.set',
    '{"status":"active","reason":"restore suspended Club"}', '{}'
  );
  perform pg_temp.assert_true(
    (select operational_status = 'active' from public.pachanga_clubs
     where id = 'b4040000-0000-4000-8000-000000000001'),
    'Platform could not restore a suspended Club with valid publication consent'
  );
end;
$$;

set local role authenticated;
select pg_temp.actor('b4010000-0000-4000-8000-000000000006');
select pg_temp.expect_failure(
  'update public.pachanga_clubs set description = ''forbidden direct write'' where id = ''b4040000-0000-4000-8000-000000000001''',
  'permission denied|row-level security'
);
reset role;
