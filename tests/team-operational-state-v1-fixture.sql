\set ON_ERROR_STOP on

begin;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('8b000000-0000-4000-8000-000000000001', 'wave8b-owner-a@example.test', clock_timestamp(), '{"full_name":"Synthetic Owner A"}'),
  ('8b000000-0000-4000-8000-000000000002', 'wave8b-owner-b@example.test', clock_timestamp(), '{"full_name":"Synthetic Owner B"}'),
  ('8b000000-0000-4000-8000-000000000003', 'wave8b-owner-c@example.test', clock_timestamp(), '{"full_name":"Synthetic Owner C"}'),
  ('8b000000-0000-4000-8000-000000000004', 'wave8b-owner-d@example.test', clock_timestamp(), '{"full_name":"Synthetic Owner D"}'),
  ('8b000000-0000-4000-8000-000000000005', 'wave8b-owner-e@example.test', clock_timestamp(), '{"full_name":"Synthetic Owner E"}'),
  ('8b000000-0000-4000-8000-000000000006', 'wave8b-owner-f@example.test', clock_timestamp(), '{"full_name":"Synthetic Owner F"}'),
  ('8b000000-0000-4000-8000-000000000007', 'wave8b-owner-g@example.test', clock_timestamp(), '{"full_name":"Synthetic Owner G"}'),
  ('8b000000-0000-4000-8000-000000000008', 'wave8b-next-owner@example.test', clock_timestamp(), '{"full_name":"Synthetic Next Owner"}'),
  ('8b000000-0000-4000-8000-000000000009', 'wave8b-team-admin@example.test', clock_timestamp(), '{"full_name":"Synthetic Team Admin"}'),
  ('8b000000-0000-4000-8000-000000000020', 'wave8b-platform-owner@example.test', clock_timestamp(), '{"full_name":"Synthetic Platform Owner"}'),
  ('8b000000-0000-4000-8000-000000000021', 'wave8b-moderator@example.test', clock_timestamp(), '{"full_name":"Synthetic Moderator"}'),
  ('8b000000-0000-4000-8000-000000000022', 'wave8b-outsider@example.test', clock_timestamp(), '{"full_name":"Synthetic Outsider"}'),
  ('8b000000-0000-4000-8000-000000000023', 'wave8b-support@example.test', clock_timestamp(), '{"full_name":"Synthetic Support"}'),
  ('8b000000-0000-4000-8000-000000000024', 'wave8b-club-owner@example.test', clock_timestamp(), '{"full_name":"Synthetic Club Owner"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision, billing_status)
values
  ('8b000000-0000-4000-8000-000000000101', '8b000000-0000-4000-8000-000000000001', 'Synthetic Team A', 'W8BTA', '{"name":"Synthetic Team A","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1, 'trial'),
  ('8b000000-0000-4000-8000-000000000102', '8b000000-0000-4000-8000-000000000002', 'Synthetic Team B', 'W8BTB', '{"name":"Synthetic Team B","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1, 'trial'),
  ('8b000000-0000-4000-8000-000000000103', '8b000000-0000-4000-8000-000000000003', 'Synthetic Team C', 'W8BTC', '{"name":"Synthetic Team C","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1, 'trial'),
  ('8b000000-0000-4000-8000-000000000104', '8b000000-0000-4000-8000-000000000004', 'Synthetic Team D', 'W8BTD', '{"name":"Synthetic Team D","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1, 'active'),
  ('8b000000-0000-4000-8000-000000000105', '8b000000-0000-4000-8000-000000000005', 'Synthetic Team E', 'W8BTE', '{"name":"Synthetic Team E","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1, 'trial'),
  ('8b000000-0000-4000-8000-000000000106', '8b000000-0000-4000-8000-000000000006', 'Synthetic Team F', 'W8BTF', '{"name":"Synthetic Team F","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1, 'trial'),
  ('8b000000-0000-4000-8000-000000000107', '8b000000-0000-4000-8000-000000000007', 'Synthetic Team G', 'W8BTG', '{"name":"Synthetic Team G","matches":[],"players":[],"siteSettings":{},"venues":[]}', 1, 'past_due');

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('8b000000-0000-4000-8000-000000000101', '8b000000-0000-4000-8000-000000000001', 'owner', 'Synthetic Owner A'),
  ('8b000000-0000-4000-8000-000000000101', '8b000000-0000-4000-8000-000000000009', 'admin', 'Synthetic Team Admin'),
  ('8b000000-0000-4000-8000-000000000102', '8b000000-0000-4000-8000-000000000002', 'owner', 'Synthetic Owner B'),
  ('8b000000-0000-4000-8000-000000000103', '8b000000-0000-4000-8000-000000000003', 'owner', 'Synthetic Owner C'),
  ('8b000000-0000-4000-8000-000000000104', '8b000000-0000-4000-8000-000000000004', 'owner', 'Synthetic Owner D'),
  ('8b000000-0000-4000-8000-000000000105', '8b000000-0000-4000-8000-000000000005', 'owner', 'Synthetic Owner E'),
  ('8b000000-0000-4000-8000-000000000106', '8b000000-0000-4000-8000-000000000006', 'owner', 'Synthetic Owner F'),
  ('8b000000-0000-4000-8000-000000000106', '8b000000-0000-4000-8000-000000000008', 'admin', 'Synthetic Next Owner'),
  ('8b000000-0000-4000-8000-000000000107', '8b000000-0000-4000-8000-000000000007', 'owner', 'Synthetic Owner G');

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('8b000000-0000-4000-8000-000000000020', 'platform_owner', true),
  ('8b000000-0000-4000-8000-000000000021', 'moderator', true),
  ('8b000000-0000-4000-8000-000000000023', 'support', true);

delete from public.pachanga_user_notifications
where recipient_user_id::text like '8b000000-0000-4000-8000-%';

commit;
