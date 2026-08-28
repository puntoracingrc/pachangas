\set ON_ERROR_STOP on

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('7b000000-0000-4000-8000-000000000001', 'wave7b-team-owner@example.test', clock_timestamp(), '{"full_name":"Wave 7B Team Owner"}'),
  ('7b000000-0000-4000-8000-000000000002', 'wave7b-player@example.test', clock_timestamp(), '{"full_name":"Wave 7B Player"}'),
  ('7b000000-0000-4000-8000-000000000003', 'wave7b-platform-owner@example.test', clock_timestamp(), '{"full_name":"Wave 7B Platform Owner"}'),
  ('7b000000-0000-4000-8000-000000000004', 'wave7b-club-owner@example.test', clock_timestamp(), '{"full_name":"Wave 7B Club Owner"}'),
  ('7b000000-0000-4000-8000-000000000005', 'wave7b-next-owner@example.test', clock_timestamp(), '{"full_name":"Wave 7B Next Owner"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
values (
  '7b000000-0000-4000-8000-000000000010',
  '7b000000-0000-4000-8000-000000000001',
  'Wave 7B Team', 'W7BTEAM',
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('7b000000-0000-4000-8000-000000000010', '7b000000-0000-4000-8000-000000000001', 'owner', 'Wave 7B Team Owner'),
  ('7b000000-0000-4000-8000-000000000010', '7b000000-0000-4000-8000-000000000002', 'player', 'Wave 7B Player'),
  ('7b000000-0000-4000-8000-000000000010', '7b000000-0000-4000-8000-000000000005', 'player', 'Wave 7B Next Owner');

insert into public.pachanga_clubs(
  id, name, slug, club_type, operational_status, visibility,
  primary_owner_id, created_by, partnership_status
) values (
  '7b000000-0000-4000-8000-000000000020',
  'Wave 7B Club', 'wave-7b-club', 'FOOTBALL_CLUB', 'active', 'private',
  '7b000000-0000-4000-8000-000000000004',
  '7b000000-0000-4000-8000-000000000004', 'active'
);

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, invited_by, accepted_at
) values (
  '7b000000-0000-4000-8000-000000000020',
  '7b000000-0000-4000-8000-000000000004',
  'club_owner', 'active',
  '7b000000-0000-4000-8000-000000000004', clock_timestamp()
);

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('7b000000-0000-4000-8000-000000000003', 'platform_owner', true);

set constraints all immediate;
