\set ON_ERROR_STOP on

begin;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('8a000000-0000-4000-8000-000000000001', 'wave8a-team-owner@example.test', clock_timestamp(), '{"full_name":"Wave 8A Team Owner"}'),
  ('8a000000-0000-4000-8000-000000000002', 'wave8a-player@example.test', clock_timestamp(), '{"full_name":"Wave 8A Player"}'),
  ('8a000000-0000-4000-8000-000000000003', 'wave8a-platform-owner@example.test', clock_timestamp(), '{"full_name":"Wave 8A Platform Owner"}'),
  ('8a000000-0000-4000-8000-000000000004', 'wave8a-club-owner@example.test', clock_timestamp(), '{"full_name":"Wave 8A Club Owner"}'),
  ('8a000000-0000-4000-8000-000000000005', 'wave8a-support@example.test', clock_timestamp(), '{"full_name":"Wave 8A Support"}'),
  ('8a000000-0000-4000-8000-000000000006', 'wave8a-next-team-owner@example.test', clock_timestamp(), '{"full_name":"Wave 8A Next Team Owner"}'),
  ('8a000000-0000-4000-8000-000000000007', 'wave8a-next-club-owner@example.test', clock_timestamp(), '{"full_name":"Wave 8A Next Club Owner"}'),
  ('8a000000-0000-4000-8000-000000000008', 'wave8a-finance@example.test', clock_timestamp(), '{"full_name":"Wave 8A Finance"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
values
  (
    '8a000000-0000-4000-8000-000000000010',
    '8a000000-0000-4000-8000-000000000001',
    'Wave 8A Team', 'W8ATEAM',
    '{"name":"Wave 8A Team","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1
  ),
  (
    '8a000000-0000-4000-8000-000000000011',
    '8a000000-0000-4000-8000-000000000001',
    'Wave 8A Reconsideration Team', 'W8ARECO',
    '{"name":"Wave 8A Reconsideration Team","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1
  );

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('8a000000-0000-4000-8000-000000000010', '8a000000-0000-4000-8000-000000000001', 'owner', 'Wave 8A Team Owner'),
  ('8a000000-0000-4000-8000-000000000010', '8a000000-0000-4000-8000-000000000002', 'player', 'Wave 8A Player'),
  ('8a000000-0000-4000-8000-000000000010', '8a000000-0000-4000-8000-000000000006', 'admin', 'Wave 8A Next Team Owner'),
  ('8a000000-0000-4000-8000-000000000011', '8a000000-0000-4000-8000-000000000001', 'owner', 'Wave 8A Team Owner');

insert into public.pachanga_clubs(
  id, name, slug, description, club_type, operational_status, visibility,
  primary_owner_id, created_by, partnership_status
) values
  (
    '8a000000-0000-4000-8000-000000000020',
    'Wave 8A Club', 'wave-8a-club', 'Club de prueba para el acceso de organizadores.',
    'FOOTBALL_CLUB', 'active', 'private',
    '8a000000-0000-4000-8000-000000000004',
    '8a000000-0000-4000-8000-000000000004', 'active'
  ),
  (
    '8a000000-0000-4000-8000-000000000021',
    'Wave 8A Suspended Club', 'wave-8a-suspended-club', 'Club suspendido para pruebas negativas.',
    'FOOTBALL_CLUB', 'suspended', 'private',
    '8a000000-0000-4000-8000-000000000004',
    '8a000000-0000-4000-8000-000000000004', 'none'
  );

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, invited_by, accepted_at
) values
  (
    '8a000000-0000-4000-8000-000000000020',
    '8a000000-0000-4000-8000-000000000004',
    'club_owner', 'active',
    '8a000000-0000-4000-8000-000000000004', clock_timestamp()
  ),
  (
    '8a000000-0000-4000-8000-000000000020',
    '8a000000-0000-4000-8000-000000000007',
    'club_owner', 'active',
    '8a000000-0000-4000-8000-000000000004', clock_timestamp()
  ),
  (
    '8a000000-0000-4000-8000-000000000021',
    '8a000000-0000-4000-8000-000000000004',
    'club_owner', 'active',
    '8a000000-0000-4000-8000-000000000004', clock_timestamp()
  );

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('8a000000-0000-4000-8000-000000000003', 'platform_owner', true),
  ('8a000000-0000-4000-8000-000000000005', 'support', true),
  ('8a000000-0000-4000-8000-000000000008', 'finance', true);

set constraints all immediate;

commit;
