\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values (
  'bd010000-0000-4000-8000-000000000001',
  'league-beta-scale@example.test',
  clock_timestamp(),
  '{"full_name":"League Beta Scale"}'
);

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('bd010000-0000-4000-8000-000000000001', 'platform_owner', true);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  md5('league-beta-scale-group-' || series)::uuid,
  'bd010000-0000-4000-8000-000000000001',
  'Wave 2 Scale Team ' || lpad(series::text, 3, '0'),
  'S' || lpad(series::text, 5, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
from generate_series(1, 120) series;

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  valid_from, expires_at, reason, revision, server_sequence, granted_by,
  program_key, bundle_id, beta_team_cap, created_at, updated_at
)
select
  'TEAM', groups.id, capabilities.capability, 'platform_grant', 'active',
  statement_timestamp() - interval '1 minute', statement_timestamp() + interval '30 days',
  'LEAGUE_PRIVATE_BETA_V1 scale validation', 1,
  nextval('private.pachanga_competition_sequence'),
  'bd010000-0000-4000-8000-000000000001',
  'LEAGUE_PRIVATE_BETA_V1', md5('league-beta-scale-bundle-' || groups.id)::uuid,
  12, clock_timestamp(), clock_timestamp()
from public.pachanga_groups groups
cross join lateral unnest(private.pachanga_league_private_beta_capabilities_v1()) capabilities(capability)
where groups.name like 'Wave 2 Scale Team %';

select set_config(
  'request.jwt.claims',
  '{"sub":"bd010000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

create temporary table beta_scale_snapshot(body jsonb, elapsed_ms numeric);
do $$
declare started_at timestamptz := clock_timestamp();
declare snapshot jsonb;
begin
  snapshot := public.get_pachanga_platform_league_private_beta_v1('', 0, 100);
  insert into beta_scale_snapshot values (
    snapshot,
    extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$$;

select pg_temp.assert_true(
  jsonb_array_length((select body -> 'organizers' from beta_scale_snapshot)) = 100,
  'Organizer search must remain bounded to 100 rows'
);
select pg_temp.assert_true(
  jsonb_array_length((select body -> 'bundles' from beta_scale_snapshot)) = 100,
  'Bundle read model must remain bounded to 100 rows'
);
select pg_temp.assert_true(
  ((select body #>> '{metrics,activeGrantBundles}' from beta_scale_snapshot))::integer >= 120,
  'Global bundle metric must remain accurate beyond the bounded list'
);
select pg_temp.assert_true(
  (select elapsed_ms < 2000 from beta_scale_snapshot),
  'Platform beta read model exceeded the 2 second local scale threshold'
);
select pg_temp.assert_true(
  to_regclass('public.pachanga_competition_entitlement_beta_bundle_idx') is not null
  and to_regclass('public.pachanga_competition_entitlement_beta_organizer_idx') is not null,
  'Beta entitlement indexes must exist'
);

select jsonb_build_object(
  'organizersReturned', jsonb_array_length(body -> 'organizers'),
  'bundlesReturned', jsonb_array_length(body -> 'bundles'),
  'activeBundles', (body #>> '{metrics,activeGrantBundles}')::integer,
  'elapsedMs', round(elapsed_ms, 2),
  'status', 'PASS'
)
from beta_scale_snapshot;

rollback;
