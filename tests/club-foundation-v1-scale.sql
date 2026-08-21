\set ON_ERROR_STOP on
\timing on

begin;
set local lock_timeout = '5s';
set local statement_timeout = '5min';

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
grant execute on function auth.jwt() to authenticated;

create or replace function pg_temp.stable_uuid(value text)
returns uuid language sql immutable as $$ select md5(value)::uuid $$;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table club_scale_timings(metric text, elapsed_ms numeric);
grant select, insert on table club_scale_timings to authenticated;

insert into auth.users(id, email, email_confirmed_at)
select pg_temp.stable_uuid('club-scale-owner:' || value),
  'club-scale-owner-' || value || '@example.test', clock_timestamp()
from generate_series(1, 1000) value;

insert into auth.users(id, email, email_confirmed_at)
select pg_temp.stable_uuid('club-scale-member:' || value),
  'club-scale-member-' || value || '@example.test', clock_timestamp()
from generate_series(1, 10) value;

insert into auth.users(id, email, email_confirmed_at)
values (
  pg_temp.stable_uuid('club-scale-platform'),
  'club-scale-platform@example.test',
  clock_timestamp()
);

insert into public.pachanga_clubs(
  id, name, slug, club_type, country_code, province, municipality,
  general_area, visibility, operational_status, primary_owner_id, created_by
)
select pg_temp.stable_uuid('club-scale:' || value),
  'Club Scale ' || value, 'club-scale-' || value, 'FOOTBALL_CLUB', 'ES',
  'Barcelona', 'Barcelona', 'Zona ' || (value % 20), 'private', 'active',
  pg_temp.stable_uuid('club-scale-owner:' || value),
  pg_temp.stable_uuid('club-scale-owner:' || value)
from generate_series(1, 1000) value;

insert into public.pachanga_club_memberships(
  id, club_id, user_id, role, status, valid_from, invited_by, accepted_at
)
select pg_temp.stable_uuid('club-scale-owner-membership:' || value),
  pg_temp.stable_uuid('club-scale:' || value),
  pg_temp.stable_uuid('club-scale-owner:' || value),
  'club_owner', 'active', clock_timestamp(),
  pg_temp.stable_uuid('club-scale-owner:' || value), clock_timestamp()
from generate_series(1, 1000) value;

insert into public.pachanga_club_memberships(
  id, club_id, user_id, role, status, valid_from, invited_by, accepted_at
)
select pg_temp.stable_uuid('club-scale-member-membership:' || club_number || ':' || member_number),
  pg_temp.stable_uuid('club-scale:' || club_number),
  pg_temp.stable_uuid('club-scale-member:' || member_number),
  case when member_number = 1 then 'club_admin'
    when member_number = 2 then 'club_competition_manager'
    else 'club_viewer' end,
  'active', clock_timestamp(),
  pg_temp.stable_uuid('club-scale-owner:' || club_number), clock_timestamp()
from generate_series(1, 1000) club_number
cross join generate_series(1, 9) member_number;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select pg_temp.stable_uuid('club-scale-team:' || value),
  pg_temp.stable_uuid('club-scale-owner:' || (((value - 1) / 5) + 1)),
  'Club Scale Team ' || value,
  'CS' || lpad(value::text, 6, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
from generate_series(1, 5000) value;

insert into public.pachanga_club_team_relationships(
  id, club_id, group_id, relationship_type, initiated_by, status,
  show_on_club_profile, created_by, started_at
)
select pg_temp.stable_uuid('club-scale-relationship:' || value),
  pg_temp.stable_uuid('club-scale:' || (((value - 1) / 5) + 1)),
  pg_temp.stable_uuid('club-scale-team:' || value),
  case when value % 3 = 0 then 'MEMBER' when value % 3 = 1 then 'AFFILIATED' else 'HOSTED' end,
  'CLUB', 'active', value % 4 = 0,
  pg_temp.stable_uuid('club-scale-owner:' || (((value - 1) / 5) + 1)),
  clock_timestamp()
from generate_series(1, 5000) value;

insert into public.pachanga_club_invitations(
  id, club_id, target_kind, target_user_id, role, status, expires_at,
  invited_by
)
select pg_temp.stable_uuid('club-scale-invitation:' || value),
  pg_temp.stable_uuid('club-scale:' || (((value - 1) / 10) + 1)),
  case when (value - 1) % 10 = 0 then 'registered_user' else 'email_target' end,
  case when (value - 1) % 10 = 0 then pg_temp.stable_uuid('club-scale-member:10') else null end,
  'club_viewer', 'pending', clock_timestamp() + interval '7 days',
  pg_temp.stable_uuid('club-scale-owner:' || (((value - 1) / 10) + 1))
from generate_series(1, 10000) value;

insert into public.pachanga_club_memberships(
  id, club_id, user_id, role, status, valid_from, expires_at, invited_by
)
select pg_temp.stable_uuid('club-scale-invited-membership:' || value),
  pg_temp.stable_uuid('club-scale:' || value),
  pg_temp.stable_uuid('club-scale-member:10'),
  'club_viewer', 'invited', clock_timestamp(), clock_timestamp() + interval '7 days',
  pg_temp.stable_uuid('club-scale-owner:' || value)
from generate_series(1, 100) value;

update public.pachanga_club_invitations invitations
set membership_id = pg_temp.stable_uuid('club-scale-invited-membership:' || sequence.value)
from generate_series(1, 100) sequence(value)
where invitations.id = pg_temp.stable_uuid('club-scale-invitation:' || (((sequence.value - 1) * 10) + 1));

insert into private.pachanga_club_invitation_secrets(
  invitation_id, token_hash, target_email_normalized, target_email_hash,
  retention_until
)
select pg_temp.stable_uuid('club-scale-invitation:' || value),
  encode(extensions.digest(
    md5('club-scale-token:' || value) || md5('club-scale-token-b:' || value),
    'sha256'
  ), 'hex'),
  case when (value - 1) % 10 = 0 then null else 'club-scale-target-' || value || '@example.test' end,
  case when (value - 1) % 10 = 0 then null else encode(extensions.digest('club-scale-target-' || value || '@example.test', 'sha256'), 'hex') end,
  clock_timestamp() + interval '97 days'
from generate_series(1, 10000) value;

insert into public.pachanga_competition_organizer_states(
  organizer_kind, organizer_group_id, organizer_club_id
)
select 'CLUB', null, pg_temp.stable_uuid('club-scale:' || value)
from generate_series(1, 1000) value;

insert into public.pachanga_competition_entitlement_grants(
  id, organizer_kind, organizer_group_id, organizer_club_id, capability,
  grant_source, reason, granted_by
)
select pg_temp.stable_uuid('club-scale-entitlement:' || value),
  'CLUB', null, pg_temp.stable_uuid('club-scale:' || value),
  'competition_create', 'platform_grant', 'Representative Club scale fixture',
  pg_temp.stable_uuid('club-scale-platform')
from generate_series(1, 1000) value;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, organizer_club_id, name, slug,
  competition_type, created_by
)
select pg_temp.stable_uuid('club-scale-competition:' || value),
  'CLUB', null, pg_temp.stable_uuid('club-scale:' || value),
  'Club Scale Competition ' || value, 'club-scale-competition-' || value,
  'LEAGUE', pg_temp.stable_uuid('club-scale-owner:' || value)
from generate_series(1, 500) value;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (pg_temp.stable_uuid('club-scale-platform'), 'platform_owner', true);

update private.pachanga_club_foundation_settings set
  club_foundation_enabled = true,
  club_self_service_creation_enabled = true,
  club_team_relationships_enabled = true,
  club_public_profiles_enabled = true,
  club_competition_organizer_enabled = true
where singleton;

select pg_temp.assert_true((select count(*) from public.pachanga_clubs where slug like 'club-scale-%') = 1000, 'Scale fixture must contain 1,000 Clubs');
select pg_temp.assert_true((select count(*) from public.pachanga_club_memberships where club_id in (select id from public.pachanga_clubs where slug like 'club-scale-%')) >= 10000, 'Scale fixture must contain at least 10,000 memberships');
select pg_temp.assert_true((select count(*) from public.pachanga_club_team_relationships where club_id in (select id from public.pachanga_clubs where slug like 'club-scale-%')) = 5000, 'Scale fixture must contain 5,000 relationships');
select pg_temp.assert_true((select count(*) from public.pachanga_club_invitations where club_id in (select id from public.pachanga_clubs where slug like 'club-scale-%')) = 10000, 'Scale fixture must contain 10,000 invitations');
select pg_temp.assert_true((select count(*) from public.pachanga_competitions where organizer_kind = 'CLUB' and organizer_club_id in (select id from public.pachanga_clubs where slug like 'club-scale-%')) = 500, 'Scale fixture must contain 500 Club competitions');

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.stable_uuid('club-scale-platform'), 'role', 'authenticated')::text, true);

do $$
declare started_at timestamptz; iteration integer; payload jsonb;
begin
  for iteration in 1..100 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_platform_clubs_v1((iteration - 1) * 10, 30);
    insert into club_scale_timings values ('admin_clubs', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
  for iteration in 1..100 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_platform_club_v1(pg_temp.stable_uuid('club-scale:' || iteration));
    insert into club_scale_timings values ('club_read_model', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

reset role;

do $$
declare started_at timestamptz; iteration integer;
begin
  for iteration in 1..200 loop
    started_at := clock_timestamp();
    perform relationships.id
    from public.pachanga_club_team_relationships relationships
    where relationships.club_id = pg_temp.stable_uuid('club-scale:' || (((iteration - 1) / 5) + 1))
      and relationships.group_id = pg_temp.stable_uuid('club-scale-team:' || iteration);
    insert into club_scale_timings values ('relationship_lookup', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
  for iteration in 1..200 loop
    started_at := clock_timestamp();
    perform private.pachanga_competition_resolve_organizer_v2(
      'CLUB', pg_temp.stable_uuid('club-scale:' || (((iteration - 1) % 1000) + 1)),
      pg_temp.stable_uuid('club-scale-owner:' || (((iteration - 1) % 1000) + 1))
    );
    insert into club_scale_timings values ('organizer_club', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.stable_uuid('club-scale-member:10'), 'role', 'authenticated')::text, true);
do $$
declare started_at timestamptz; iteration integer; invitation_number integer; payload jsonb; token text;
begin
  for iteration in 1..100 loop
    invitation_number := ((iteration - 1) * 10) + 1;
    token := md5('club-scale-token:' || invitation_number) || md5('club-scale-token-b:' || invitation_number);
    started_at := clock_timestamp();
    payload := public.command_pachanga_club_foundation_v1(
      pg_temp.stable_uuid('club-scale-accept-operation:' || iteration),
      pg_temp.stable_uuid('club-scale-invitation:' || invitation_number),
      1, 'membership.accept',
      jsonb_build_object('token', token, 'reason', 'Scale invitation acceptance'),
      '{"clientVersion":"1.0.0+scale","surface":"club_scale"}'::jsonb
    );
    insert into club_scale_timings values ('invitation_accept', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

reset role;

select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'admin_clubs') < 1500, 'Admin Clubs p95 exceeded 1500ms');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'club_read_model') < 1000, 'Club read model p95 exceeded 1000ms');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'relationship_lookup') < 50, 'Relationship lookup p95 exceeded 50ms');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'organizer_club') < 100, 'Club organizer resolution p95 exceeded 100ms');
select pg_temp.assert_true((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'invitation_accept') < 500, 'Invitation acceptance p95 exceeded 500ms');
select pg_temp.assert_true(not exists (select 1 from pg_locks where pid = pg_backend_pid() and not granted), 'Scale validation left a waiting lock');

explain (analyze, buffers, format json)
select relationships.id
from public.pachanga_club_team_relationships relationships
where relationships.club_id = pg_temp.stable_uuid('club-scale:500')
  and relationships.group_id = pg_temp.stable_uuid('club-scale-team:2500');

explain (analyze, buffers, format json)
select clubs.id, clubs.name, clubs.operational_status
from public.pachanga_clubs clubs
order by clubs.updated_at desc, clubs.id
limit 50;

select jsonb_build_object(
  'adminClubsP50Ms', round((select percentile_cont(0.50) within group (order by elapsed_ms) from club_scale_timings where metric = 'admin_clubs')::numeric, 3),
  'adminClubsP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'admin_clubs')::numeric, 3),
  'clubReadModelP50Ms', round((select percentile_cont(0.50) within group (order by elapsed_ms) from club_scale_timings where metric = 'club_read_model')::numeric, 3),
  'clubReadModelP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'club_read_model')::numeric, 3),
  'invitationAcceptP50Ms', round((select percentile_cont(0.50) within group (order by elapsed_ms) from club_scale_timings where metric = 'invitation_accept')::numeric, 3),
  'invitationAcceptP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'invitation_accept')::numeric, 3),
  'organizerClubP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'organizer_club')::numeric, 3),
  'relationshipLookupP95Ms', round((select percentile_cont(0.95) within group (order by elapsed_ms) from club_scale_timings where metric = 'relationship_lookup')::numeric, 3),
  'clubs', 1000,
  'memberships', (select count(*) from public.pachanga_club_memberships where club_id in (select id from public.pachanga_clubs where slug like 'club-scale-%')),
  'relationships', 5000,
  'invitations', 10000,
  'competitions', 500,
  'indexBytes', (
    select coalesce(sum(pg_relation_size(indexrelid)), 0)
    from pg_index where indrelid in (
      'public.pachanga_clubs'::regclass,
      'public.pachanga_club_memberships'::regclass,
      'public.pachanga_club_invitations'::regclass,
      'public.pachanga_club_team_relationships'::regclass
    )
  )
) as club_scale_summary;

rollback;
