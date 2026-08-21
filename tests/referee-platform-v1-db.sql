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
    raise exception 'REFEREE_TEST_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'REFEREE_TEST_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
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

create or replace function pg_temp.table_digest(target_table regclass)
returns text language plpgsql as $$
declare result text;
begin
  execute format(
    'select md5(coalesce(string_agg(to_jsonb(rows)::text, E''\\n'' order by to_jsonb(rows)::text), '''')) from %s rows',
    target_table
  ) into result;
  return result;
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('a3010000-0000-4000-8000-000000000001', 'ref-platform-owner@example.test', clock_timestamp(), '{"full_name":"Platform Owner"}'),
  ('a3010000-0000-4000-8000-000000000002', 'ref-platform-admin@example.test', clock_timestamp(), '{"full_name":"Platform Admin"}'),
  ('a3010000-0000-4000-8000-000000000003', 'ref-support@example.test', clock_timestamp(), '{"full_name":"Support"}'),
  ('a3010000-0000-4000-8000-000000000004', 'referee-one@example.test', clock_timestamp(), '{"full_name":"Alex Referee"}'),
  ('a3010000-0000-4000-8000-000000000005', 'referee-player@example.test', clock_timestamp(), '{"full_name":"Sam Player Referee"}'),
  ('a3010000-0000-4000-8000-000000000006', 'referee-two@example.test', clock_timestamp(), '{"full_name":"Morgan Referee"}'),
  ('a3010000-0000-4000-8000-000000000007', 'team-owner@example.test', clock_timestamp(), '{"full_name":"Team Owner"}'),
  ('a3010000-0000-4000-8000-000000000008', 'team-admin@example.test', clock_timestamp(), '{"full_name":"Team Admin"}'),
  ('a3010000-0000-4000-8000-000000000009', 'club-owner@example.test', clock_timestamp(), '{"full_name":"Club Owner"}'),
  ('a3010000-0000-4000-8000-000000000010', 'club-admin@example.test', clock_timestamp(), '{"full_name":"Club Admin"}'),
  ('a3010000-0000-4000-8000-000000000011', 'club-ref-manager@example.test', clock_timestamp(), '{"full_name":"Club Referee Manager"}'),
  ('a3010000-0000-4000-8000-000000000012', 'normal-user@example.test', clock_timestamp(), '{"full_name":"Normal User"}'),
  ('a3010000-0000-4000-8000-000000000013', 'email-invite@example.test', clock_timestamp(), '{"full_name":"Email Invite"}'),
  ('a3010000-0000-4000-8000-000000000014', 'unverified@example.test', null, '{"full_name":"Unverified User"}');

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('a3010000-0000-4000-8000-000000000001', 'platform_owner', true),
  ('a3010000-0000-4000-8000-000000000002', 'platform_admin', true),
  ('a3010000-0000-4000-8000-000000000003', 'support', true);

insert into public.pachanga_player_profiles(
  user_id, display_name, source_player_id, rating, current_overall,
  base_facets, calibrated_facets, current_facets
) values (
  'a3010000-0000-4000-8000-000000000005', 'Sam Player Referee', 'sam-player-ref',
  7.4, 74, '{"pace":74}', '{"pace":74}', '{"pace":74}'
);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision) values (
  'a3020000-0000-4000-8000-000000000001',
  'a3010000-0000-4000-8000-000000000007',
  'R3 Team A', 'R3TEAM1',
  '{"matches":[{"id":"r3-match-a","date":"2026-09-15T18:00:00Z","kind":"futbol7"},{"id":"r3-match-b","date":"2026-09-15T19:00:00Z","kind":"futbol7"},{"id":"r3-match-c","date":"2026-09-15T22:00:00Z","kind":"futbol7"}],"players":[],"siteSettings":{"timezone":"Europe/Madrid"},"venues":[]}',
  4
);
insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('a3020000-0000-4000-8000-000000000001', 'a3010000-0000-4000-8000-000000000007', 'owner', 'Team Owner'),
  ('a3020000-0000-4000-8000-000000000001', 'a3010000-0000-4000-8000-000000000008', 'admin', 'Team Admin');
insert into public.pachanga_match_read_model(
  group_id, match_id, match_state, match_version, configured, lineup_closed,
  finalized, target_players, reserve_limit, source_payload_revision
) values
  ('a3020000-0000-4000-8000-000000000001', 'r3-match-a', 'published', 4, true, false, false, 14, 2, 4),
  ('a3020000-0000-4000-8000-000000000001', 'r3-match-b', 'published', 4, true, false, false, 14, 2, 4),
  ('a3020000-0000-4000-8000-000000000001', 'r3-match-c', 'published', 4, true, false, false, 14, 2, 4);
insert into public.pachanga_canonical_matches(id, created_by) values
  ('a3030000-0000-4000-8000-000000000001', 'a3010000-0000-4000-8000-000000000001'),
  ('a3030000-0000-4000-8000-000000000002', 'a3010000-0000-4000-8000-000000000001'),
  ('a3030000-0000-4000-8000-000000000003', 'a3010000-0000-4000-8000-000000000001');
insert into public.pachanga_canonical_match_bindings(
  canonical_match_id, source_kind, source_group_id, source_id, relation_kind, created_by
) values
  ('a3030000-0000-4000-8000-000000000001', 'group_match', 'a3020000-0000-4000-8000-000000000001', 'r3-match-a', 'manual_verified', 'a3010000-0000-4000-8000-000000000001'),
  ('a3030000-0000-4000-8000-000000000002', 'group_match', 'a3020000-0000-4000-8000-000000000001', 'r3-match-b', 'manual_verified', 'a3010000-0000-4000-8000-000000000001'),
  ('a3030000-0000-4000-8000-000000000003', 'group_match', 'a3020000-0000-4000-8000-000000000001', 'r3-match-c', 'manual_verified', 'a3010000-0000-4000-8000-000000000001');

create temporary table referee_invariants_before(table_name text primary key, digest text);
insert into referee_invariants_before(table_name, digest)
select table_name, pg_temp.table_digest(table_name::regclass)
from (values
  ('public.pachanga_player_profiles'),
  ('public.pachanga_individual_rating_evidence'),
  ('public.pachanga_player_rating_snapshots'),
  ('private.pachanga_conduct_reports'),
  ('private.pachanga_moderation_cases'),
  ('public.pachanga_achievement_grants'),
  ('public.pachanga_reward_grants'),
  ('public.pachanga_team_cosmetic_inventory'),
  ('public.pachanga_provincial_ranking_entries')
) tables(table_name);

do $$
declare
  response jsonb;
  replay jsonb;
  profile_revision bigint;
  club_revision bigint;
  invitation_token text;
  relationship_token text;
  email_relationship_token text;
  stats_revision bigint;
  checksum_before text;
begin
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000001');
  response := public.command_pachanga_club_platform_v1(
    'a3040000-0000-4000-8000-000000000001',
    '00000000-0000-0000-0000-00000000c101', 1, 'club_flags.set',
    '{"foundationEnabled":true,"selfServiceCreationEnabled":true,"teamRelationshipsEnabled":true,"publicProfilesEnabled":false,"competitionOrganizerEnabled":false,"reason":"R3 local Club fixture"}', '{}'
  );
  response := public.command_pachanga_referee_platform_admin_v1(
    'a3040000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-00000000a3f3', 1, 'referee_flags.set',
    '{"foundationEnabled":true,"selfServiceEnabled":true,"publicProfilesEnabled":true,"marketplaceEnabled":true,"clubRelationshipsEnabled":true,"assignmentsEnabled":true,"reason":"R3 local functional test"}',
    '{"clientVersion":"3.0.0+dbtest","serviceWorkerVersion":"sw-r3","installedMode":"standalone","surface":"db"}'
  );
  perform pg_temp.assert_true((response #>> '{snapshot,marketplaceEnabled}')::boolean, 'R3 flags did not enable');

  perform pg_temp.actor('a3010000-0000-4000-8000-000000000009');
  response := public.command_pachanga_club_foundation_v1(
    'a3040000-0000-4000-8000-000000000003',
    'a3050000-0000-4000-8000-000000000001', 0, 'club.create',
    '{"name":"Club Arbitral A","slug":"club-arbitral-a","clubType":"FOOTBALL_CLUB","countryCode":"ES","province":"Barcelona","municipality":"Barcelona","generalArea":"Barcelona","visibility":"private","reason":"R3 Club fixture"}', '{}'
  );
  select revision into club_revision from public.pachanga_clubs where id = 'a3050000-0000-4000-8000-000000000001';
  response := public.command_pachanga_club_referee_manager_v1(
    'a3040000-0000-4000-8000-000000000004',
    'a3050000-0000-4000-8000-000000000001', club_revision, 'manager.invite',
    '{"invitationId":"a3060000-0000-4000-8000-000000000001","targetKind":"registered_user","targetUserId":"a3010000-0000-4000-8000-000000000011","reason":"Invite referee manager"}', '{}'
  );
  invitation_token := response ->> 'oneTimeToken';
  perform pg_temp.assert_true(length(invitation_token) = 64, 'Manager invitation token missing');
  replay := public.command_pachanga_club_referee_manager_v1(
    'a3040000-0000-4000-8000-000000000004',
    'a3050000-0000-4000-8000-000000000001', club_revision, 'manager.invite',
    '{"invitationId":"a3060000-0000-4000-8000-000000000001","targetKind":"registered_user","targetUserId":"a3010000-0000-4000-8000-000000000011","reason":"Invite referee manager"}', '{}'
  );
  perform pg_temp.assert_true(not replay ? 'oneTimeToken', 'Manager token leaked through replay');
  perform pg_temp.assert_true(not exists (
    select 1 from private.pachanga_referee_operation_receipts receipts
    where receipts.operation_id = 'a3040000-0000-4000-8000-000000000004'
      and receipts.response::text like '%' || invitation_token || '%'
  ), 'Manager token leaked into receipt');
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000011');
  perform public.command_pachanga_club_foundation_v1(
    'a3040000-0000-4000-8000-000000000005',
    'a3060000-0000-4000-8000-000000000001', 1, 'membership.accept',
    jsonb_build_object('token', invitation_token, 'reason', 'Accept referee manager'), '{}'
  );
  perform pg_temp.assert_true(exists (
    select 1 from public.pachanga_club_memberships memberships
    where memberships.club_id = 'a3050000-0000-4000-8000-000000000001'
      and memberships.user_id = 'a3010000-0000-4000-8000-000000000011'
      and memberships.role = 'club_referee_manager' and memberships.status = 'active'
  ), 'club_referee_manager was not activated');
  perform pg_temp.assert_true(private.pachanga_club_can_v1(
    'a3050000-0000-4000-8000-000000000001', 'a3010000-0000-4000-8000-000000000011', 'referee_manage'
  ), 'club_referee_manager lacks referee_manage');
  perform pg_temp.assert_true(not private.pachanga_club_can_v1(
    'a3050000-0000-4000-8000-000000000001', 'a3010000-0000-4000-8000-000000000011', 'team_links_manage'
  ), 'club_referee_manager gained team management');

  perform pg_temp.actor('a3010000-0000-4000-8000-000000000004');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000006', 'a3070000-0000-4000-8000-000000000001', 0,
    'profile.create', '{"slug":"alex-referee","bio":"Árbitro de fútbol base y amateur.","experienceSinceYear":2018,"experienceSummary":"Experiencia en fútbol 7 y fútbol 11.","availabilityStatus":"AVAILABLE","reason":"Create referee profile"}', '{}'
  );
  replay := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000006', 'a3070000-0000-4000-8000-000000000001', 0,
    'profile.create', '{"slug":"alex-referee","bio":"Árbitro de fútbol base y amateur.","experienceSinceYear":2018,"experienceSummary":"Experiencia en fútbol 7 y fútbol 11.","availabilityStatus":"AVAILABLE","reason":"Create referee profile"}', '{}'
  );
  perform pg_temp.assert_true(replay ->> 'serverSequence' = response ->> 'serverSequence', 'Profile create replay diverged');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'a3040000-0000-4000-8000-000000000099', 'a3070000-0000-4000-8000-000000000099', 0,
      'profile.create', '{"slug":"alex-second","bio":"Duplicate profile attempt","experienceSummary":"Duplicate profile attempt"}', '{}'
    )
  $sql$, 'ALREADY_EXISTS');
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000007', 'a3070000-0000-4000-8000-000000000001', profile_revision,
    'profile.modalities.replace', '{"modalities":[{"modality":"FOOTBALL_7","experienceSinceYear":2018},{"modality":"FOOTBALL_11","experienceSinceYear":2020}],"reason":"Set modalities"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000008', 'a3070000-0000-4000-8000-000000000001', profile_revision,
    'profile.areas.replace', '{"areas":[{"countryCode":"ES","province":"Barcelona","municipality":"Barcelona","generalArea":"Barcelona","travelRadiusKm":35},{"countryCode":"ES","province":"Barcelona","municipality":"Sabadell","generalArea":"Sabadell","travelRadiusKm":20}],"reason":"Set areas"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000009', 'a3070000-0000-4000-8000-000000000001', profile_revision,
    'profile.availability.replace', '{"windows":[{"weekday":6,"startLocalTime":"15:00","endLocalTime":"21:00","timezone":"Europe/Madrid","publicVisible":true}],"exceptions":[{"unavailableFrom":"2026-10-01T08:00:00Z","unavailableUntil":"2026-10-02T08:00:00Z","reason":"Private medical appointment"}],"reason":"Set availability"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000010', 'a3070000-0000-4000-8000-000000000001', profile_revision,
    'profile.update', '{"visibility":"public","availabilityStatus":"AVAILABLE","availableForAssignments":true,"shareRecurringAvailability":true,"reason":"Publish profile settings"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000011', 'a3070000-0000-4000-8000-000000000001', profile_revision,
    'profile.activate', '{"reason":"Activate complete referee profile"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000012', 'a3070000-0000-4000-8000-000000000001', profile_revision,
    'marketplace.list', '{"reason":"List active referee"}', '{}'
  );
  perform pg_temp.assert_true((response #>> '{snapshot,profile,verificationStatus}') = 'unverified', 'Profile creation implied verification');
  perform pg_temp.assert_true(not (response::text ilike '%referee-one@example.test%'), 'Private snapshot leaked email');
  perform pg_temp.assert_true(not (public.get_pachanga_public_referee_v1('alex-referee')::text ilike '%Private medical appointment%'), 'Public profile leaked private exception');
  response := public.search_pachanga_referee_market_v1('{"area":"Barcelona","modality":"FOOTBALL_7"}', 1, 10);
  perform pg_temp.assert_true((response ->> 'total')::integer = 1, 'Marketplace filters did not find referee');
  perform pg_temp.assert_true(response ->> 'ordering' = 'filter_relevance_then_recent_activity', 'Marketplace ordering is not explainable');

  perform pg_temp.actor('a3010000-0000-4000-8000-000000000005');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000013', 'a3070000-0000-4000-8000-000000000002', 0,
    'profile.create', '{"slug":"sam-player-referee","bio":"Jugador y árbitro en identidades separadas.","experienceSummary":"Experiencia arbitral local suficiente.","availabilityStatus":"AVAILABLE","reason":"Create player referee facet"}', '{}'
  );
  perform pg_temp.assert_true((select rating from public.pachanga_player_profiles where user_id = 'a3010000-0000-4000-8000-000000000005') = 7.4, 'Player rating changed when referee profile was created');

  perform pg_temp.actor('a3010000-0000-4000-8000-000000000011');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000014', 'a3080000-0000-4000-8000-000000000001', 0,
    'relationship.invite', '{"clubId":"a3050000-0000-4000-8000-000000000001","targetKind":"registered_user","targetUserId":"a3010000-0000-4000-8000-000000000004","relationshipType":"REGULAR","reason":"Invite registered referee"}', '{}'
  );
  relationship_token := response ->> 'oneTimeToken';
  perform pg_temp.assert_true(length(relationship_token) = 64, 'Relationship token missing');
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000004');
  perform public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000015', 'a3080000-0000-4000-8000-000000000001', 1,
    'relationship.accept', jsonb_build_object('reason', 'Accept registered Club relation'), '{}'
  );
  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_referee_platform_v1(
      'a3040000-0000-4000-8000-000000000098', 'a3080000-0000-4000-8000-000000000001', 2,
      'relationship.accept', %L::jsonb, '{}'
    )
  $sql$, jsonb_build_object('token', relationship_token, 'reason', 'Reuse token')::text), 'NOT_PENDING|TOKEN_INVALID');
  perform pg_temp.assert_true((select status from public.pachanga_club_referee_relationships where id = 'a3080000-0000-4000-8000-000000000001') = 'active', 'Club relationship not active');

  perform pg_temp.actor('a3010000-0000-4000-8000-000000000011');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000016', 'a3080000-0000-4000-8000-000000000002', 0,
    'relationship.invite', '{"clubId":"a3050000-0000-4000-8000-000000000001","targetKind":"email_target","targetEmail":"email-invite@example.test","relationshipType":"COLLABORATOR","reason":"Invite by email"}', '{}'
  );
  email_relationship_token := response ->> 'oneTimeToken';
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000013');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'a3040000-0000-4000-8000-000000000096', 'a3080000-0000-4000-8000-000000000002', 1,
      'relationship.reject', '{"reason":"Reject email invitation without token"}', '{}'
    )
  $sql$, 'TOKEN_REQUIRED|TOKEN_INVALID');
  perform public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000017', 'a3080000-0000-4000-8000-000000000002', 1,
    'relationship.reject', jsonb_build_object('token', email_relationship_token, 'reason', 'Reject without creating profile'), '{}'
  );
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_referee_profiles where user_id = 'a3010000-0000-4000-8000-000000000013'
  ), 'Rejecting email invitation created a profile');

  perform pg_temp.actor('a3010000-0000-4000-8000-000000000008');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'a3040000-0000-4000-8000-000000000018', 'a3090000-0000-4000-8000-000000000001', 0,
      'assignment.propose', '{"refereeProfileId":"a3070000-0000-4000-8000-000000000001","requesterKind":"TEAM","requesterId":"a3020000-0000-4000-8000-000000000001","sourceKind":"group_match","sourceGroupId":"a3020000-0000-4000-8000-000000000001","sourceId":"r3-match-a","reason":"Admin must not propose"}', '{}'
    )
  $sql$, 'TEAM_OWNER_REQUIRED');
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000007');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'a3040000-0000-4000-8000-000000000019', 'a3090000-0000-4000-8000-000000000099', 0,
      'assignment.propose', '{"refereeProfileId":"a3070000-0000-4000-8000-000000000001","requesterKind":"TEAM","requesterId":"a3020000-0000-4000-8000-000000000001","sourceKind":"group_match","sourceGroupId":"a3020000-0000-4000-8000-000000000001","sourceId":"unbound-match","reason":"Unbound match"}', '{}'
    )
  $sql$, 'CANONICAL_MATCH_REQUIRED');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000020', 'a3090000-0000-4000-8000-000000000001', 0,
    'assignment.propose', '{"refereeProfileId":"a3070000-0000-4000-8000-000000000001","requesterKind":"TEAM","requesterId":"a3020000-0000-4000-8000-000000000001","sourceKind":"group_match","sourceGroupId":"a3020000-0000-4000-8000-000000000001","sourceId":"r3-match-a","assignmentRole":"MAIN_REFEREE","message":"Partido individual R3","reason":"Propose bound match"}', '{}'
  );
  perform pg_temp.assert_true(response #>> '{snapshot,assignment,scheduleSourceRevision}' = '4', 'Server schedule revision was not resolved');
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000004');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000021', 'a3090000-0000-4000-8000-000000000001', 1,
    'assignment.accept', '{"reason":"Accept assignment"}', '{}'
  );
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000007');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000022', 'a3090000-0000-4000-8000-000000000001', 2,
    'assignment.confirm', '{"reason":"Confirm assignment"}', '{}'
  );
  perform pg_temp.assert_true(response #>> '{snapshot,assignment,status}' = 'confirmed', 'Assignment was not confirmed');

  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000023', 'a3090000-0000-4000-8000-000000000002', 0,
    'assignment.propose', '{"refereeProfileId":"a3070000-0000-4000-8000-000000000001","requesterKind":"TEAM","requesterId":"a3020000-0000-4000-8000-000000000001","sourceKind":"group_match","sourceGroupId":"a3020000-0000-4000-8000-000000000001","sourceId":"r3-match-b","reason":"Overlapping proposal"}', '{}'
  );
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000004');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'a3040000-0000-4000-8000-000000000024', 'a3090000-0000-4000-8000-000000000002', 1,
      'assignment.accept', '{"reason":"Accept overlapping"}', '{}'
    )
  $sql$, 'TIME_CONFLICT');

  perform pg_temp.actor('a3010000-0000-4000-8000-000000000007');
  response := public.command_pachanga_referee_platform_v1(
    'a3040000-0000-4000-8000-000000000027', 'a3090000-0000-4000-8000-000000000003', 0,
    'assignment.propose', '{"refereeProfileId":"a3070000-0000-4000-8000-000000000001","requesterKind":"TEAM","requesterId":"a3020000-0000-4000-8000-000000000001","sourceKind":"group_match","sourceGroupId":"a3020000-0000-4000-8000-000000000001","sourceId":"r3-match-c","reason":"Schedule snapshot proposal"}', '{}'
  );
  update public.pachanga_groups
  set payload = jsonb_set(payload, '{matches,2,date}', '"2026-09-15T23:00:00Z"'::jsonb),
      payload_revision = 6
  where id = 'a3020000-0000-4000-8000-000000000001';
  update public.pachanga_match_read_model
  set match_version = 6, source_payload_revision = 6
  where group_id = 'a3020000-0000-4000-8000-000000000001' and match_id = 'r3-match-c';
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000004');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_referee_platform_v1(
      'a3040000-0000-4000-8000-000000000028', 'a3090000-0000-4000-8000-000000000003', 1,
      'assignment.accept', '{"reason":"Reject stale schedule snapshot"}', '{}'
    )
  $sql$, 'MATCH_SCHEDULE_CHANGED');

  update public.pachanga_match_read_model set
    match_state = 'finalized', finalized = true, lineup_closed = true,
    match_version = 5, source_payload_revision = 5
  where group_id = 'a3020000-0000-4000-8000-000000000001' and match_id = 'r3-match-a';
  update public.pachanga_groups set payload_revision = 5
  where id = 'a3020000-0000-4000-8000-000000000001';
  perform pg_temp.actor('a3010000-0000-4000-8000-000000000001');
  response := public.reconcile_pachanga_referee_assignment_v1(
    'a3040000-0000-4000-8000-000000000025', 'a3090000-0000-4000-8000-000000000001', 3, '{}'
  );
  replay := public.reconcile_pachanga_referee_assignment_v1(
    'a3040000-0000-4000-8000-000000000025', 'a3090000-0000-4000-8000-000000000001', 3, '{}'
  );
  perform pg_temp.assert_true(replay ->> 'serverSequence' = response ->> 'serverSequence', 'Reconcile replay diverged');
  perform pg_temp.assert_true(response #>> '{snapshot,assignment,status}' = 'completed', 'Assignment was not completed');
  perform pg_temp.assert_true((response #>> '{snapshot,statistics,matches_completed}')::integer = 1, 'Completion stats did not increment');
  select revision, checksum into stats_revision, checksum_before
  from public.pachanga_referee_statistics_snapshots where referee_profile_id = 'a3070000-0000-4000-8000-000000000001';
  response := public.command_pachanga_referee_platform_admin_v1(
    'a3040000-0000-4000-8000-000000000026', 'a3070000-0000-4000-8000-000000000001', stats_revision,
    'stats.rebuild', '{"reason":"Verify full rebuild checksum"}', '{}'
  );
  perform pg_temp.assert_true(response #>> '{snapshot,statistics,checksum}' = checksum_before, 'Full rebuild checksum differs from incremental snapshot');
  perform pg_temp.assert_true(response #>> '{snapshot,statistics,discipline_stats_status}' = 'NOT_AVAILABLE', 'Discipline stats became available');
  perform pg_temp.assert_true(response #> '{snapshot,statistics,yellow_cards_shown}' = 'null'::jsonb, 'Yellow cards must remain null');

  response := public.get_pachanga_platform_referees_v1('{"status":"active"}', 1, 20);
  perform pg_temp.assert_true((response ->> 'total')::integer >= 1, 'Control Center list omitted active referee');
  response := public.search_pachanga_platform_referees_v1('Barcelona', 20);
  perform pg_temp.assert_true(jsonb_array_length(response) >= 1, 'Administrative referee search failed');
  response := public.get_pachanga_platform_referee_health_v1();
  perform pg_temp.assert_true((response #>> '{assignments,activeSlotConflicts}')::integer = 0, 'Health found active slot conflicts');
  perform pg_temp.assert_true((response #>> '{assignments,timeOverlapConflicts}')::integer = 0, 'Health found stored overlap conflicts');
end;
$$;

-- Direct product-table writes remain closed even while product flags are ON.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"a3010000-0000-4000-8000-000000000012","role":"authenticated"}', true);
select pg_temp.expect_failure($sql$
  insert into public.pachanga_referee_profiles(id, user_id, slug, public_display_name_snapshot)
  values ('a3070000-0000-4000-8000-000000000099', 'a3010000-0000-4000-8000-000000000012', 'forbidden-profile', 'Forbidden')
$sql$, 'permission denied|row-level security');
select pg_temp.assert_true(public.get_pachanga_public_referee_v1('alex-referee') is not null, 'Authenticated normal user cannot read gated public profile');
reset role;

-- Anonymous users receive only the minimized public read model while the flag is ON.
set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.assert_true(public.get_pachanga_public_referee_v1('alex-referee') is not null, 'Anon public read model unavailable with flag ON');
select pg_temp.assert_true(public.get_pachanga_public_referee_v1('alex-referee')::text not ilike '%@example.test%', 'Anon public profile leaked email');
reset role;

-- Referee R3 must not modify established product authorities.
select pg_temp.assert_true(
  not exists (
    select 1 from referee_invariants_before before_state
    where before_state.digest <> pg_temp.table_digest(before_state.table_name::regclass)
  ),
  'Referee R3 changed Rating, Conduct, Rewards, Cosmetics or Ranking state'
);
select pg_temp.assert_true((select count(*) from private.pachanga_conduct_reports) = 0, 'R3 created conduct reports');
select pg_temp.assert_true((select count(*) from private.pachanga_moderation_cases) = 0, 'R3 created moderation cases');
select pg_temp.assert_true((select count(*) from public.pachanga_reward_grants) = 0, 'R3 created rewards');
select pg_temp.assert_true((select count(*) from public.pachanga_stripe_webhook_events) = 0, 'R3 touched Stripe');
select pg_temp.assert_true(not exists (
  select 1 from information_schema.columns
  where table_schema = 'public' and table_name like 'pachanga_referee%'
    and column_name ~ '(rating|overall|grl|stars|season_score|rank)'
), 'R3 introduced a referee rating column');
select pg_temp.assert_true(not exists (
  select 1 from private.pachanga_referee_operation_receipts receipts
  where receipts.response::text ilike '%@example.test%'
     or receipts.response::text ~ '"oneTimeToken"'
), 'Referee receipts leaked email or token');
select pg_temp.assert_true(not exists (
  select 1 from private.pachanga_referee_events events
  where events.event_payload::text ilike '%@example.test%'
), 'Referee events leaked email');

rollback;
