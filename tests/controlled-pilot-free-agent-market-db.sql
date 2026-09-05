\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.free_agent_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email) values
  ('fa000000-0000-4000-8000-000000000001', 'free-agent-market@example.test'),
  ('fa000000-0000-4000-8000-000000000002', 'market-reader@example.test');

update private.pachanga_social_team_settings_v1 set
  social_profile_foundation_enabled = true,
  social_profile_independent_write_enabled = true;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
  true
);
select public.command_pachanga_social_profile_v1(
  'profile.create',
  0,
  'fa100000-0000-4000-8000-000000000001',
  '{"displayName":"Jugador Libre C","avatarRef":"/demo/avatar-free-agent.webp","primaryPosition":"Mediocentro / pivote","preferredModality":"futbol7","generalArea":"Barcelona","usualDays":["M","J"],"approximateTime":"20:00-22:00","shortBio":"Disponible para pachangas.","socialPreferences":{"openToTeamInvites":true,"openToMatchInvites":true}}'::jsonb,
  '{"clientVersion":"2.0.0","displayMode":"browser","surface":"controlled-pilot"}'::jsonb
) as created_profile \gset
select public.command_pachanga_free_agent_market_v1(
  'market.publish',
  1,
  'fa200000-0000-4000-8000-000000000001',
  '{}'::jsonb,
  '{"clientVersion":"2.0.0","serviceWorkerVersion":"2.0.0","displayMode":"standalone","surface":"canonical-profile","email":"must-not-persist@example.test"}'::jsonb
) as published_profile \gset
select public.command_pachanga_free_agent_market_v1(
  'market.publish',
  1,
  'fa200000-0000-4000-8000-000000000001',
  '{}'::jsonb,
  '{"clientVersion":"2.0.0","serviceWorkerVersion":"2.0.0","displayMode":"standalone","surface":"canonical-profile","email":"must-not-persist@example.test"}'::jsonb
) as replayed_profile \gset
reset role;

select pg_temp.free_agent_assert(
  (:'created_profile'::jsonb ->> 'marketPublished')::boolean = false,
  'A new social profile must remain private until explicit opt-in'
);
select pg_temp.free_agent_assert(
  (:'published_profile'::jsonb ->> 'marketPublished')::boolean,
  'Publish must return the canonical published state'
);
select pg_temp.free_agent_assert(
  (:'published_profile'::jsonb ->> 'revision')::bigint = 2,
  'Publish must advance the social profile revision once'
);
select pg_temp.free_agent_assert(
  :'published_profile'::jsonb = :'replayed_profile'::jsonb,
  'An exact replay must return the original response'
);
select pg_temp.free_agent_assert(
  (select revision from public.pachanga_social_player_profiles_v1 where user_id = 'fa000000-0000-4000-8000-000000000001') = 2,
  'An exact replay must not advance the revision again'
);
select pg_temp.free_agent_assert((
  select display_name = 'Jugador Libre C'
    and player_profile_id is null
    and source_group_id is null
    and source_player_id = 'social-profile:fa000000-0000-4000-8000-000000000001'
    and group_name is null
    and avatar = '/demo/avatar-free-agent.webp'
    and birth_date is null
    and position = 'Mediocentro / pivote'
    and goalkeeper_only = false
    and media = 5
    and appearances = 0
    and goals = 0
    and wins = 0
    and zones = array['Barcelona']::text[]
    and zones_geo = '[]'::jsonb
    and availability_text = 'Martes, Jueves · 20:00-22:00'
    and modalities = array['futbol7']::text[]
    and open_to_guest
    and open_to_group
    and bio = 'Disponible para pachangas.'
    and active
  from public.pachanga_market_profiles
  where user_id = 'fa000000-0000-4000-8000-000000000001'
), 'Mercado must contain only the server-derived social projection');
select pg_temp.free_agent_assert((
  select count(*) = 1
  from private.pachanga_social_operation_receipts_v1
  where operation_id = 'fa200000-0000-4000-8000-000000000001'
    and action = 'market.publish'
    and confirmed_revision = 2
    and not (client_metadata ? 'email')
), 'Publish must retain one idempotent receipt with sanitized metadata');
select pg_temp.free_agent_assert((
  select count(*) = 1
  from private.pachanga_social_events_v1
  where operation_id = 'fa200000-0000-4000-8000-000000000001'
    and event_kind = 'market.publish.confirmed'
    and aggregate_revision = 2
), 'Publish must retain one immutable event');
select pg_temp.free_agent_assert((
  select count(*) = 1
  from private.pachanga_social_player_profile_revisions_v1
  where user_id = 'fa000000-0000-4000-8000-000000000001'
    and revision = 2
    and (snapshot ->> 'marketPublished')::boolean
), 'The profile revision must preserve the published snapshot');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
  true
);
select public.command_pachanga_social_profile_v1(
  'profile.update',
  2,
  'fa100000-0000-4000-8000-000000000002',
  '{"generalArea":"Barcelona Centro","usualDays":["V"],"approximateTime":"16:00-20:00","shortBio":"Perfil actualizado desde servidor."}'::jsonb,
  '{"clientVersion":"2.0.0","displayMode":"standalone","surface":"controlled-pilot"}'::jsonb
) as updated_profile \gset
reset role;

select pg_temp.free_agent_assert(
  (:'updated_profile'::jsonb ->> 'marketPublished')::boolean
    and (:'updated_profile'::jsonb ->> 'confirmedRevision')::bigint = 3,
  'Editing a published social profile must preserve its canonical publication state'
);
select pg_temp.free_agent_assert((
  select zones = array['Barcelona Centro']::text[]
    and availability_text = 'Viernes · 16:00-20:00'
    and bio = 'Perfil actualizado desde servidor.'
    and active
  from public.pachanga_market_profiles
  where user_id = 'fa000000-0000-4000-8000-000000000001'
), 'Editing a published social profile must refresh its active Mercado projection');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);
select pg_temp.free_agent_assert(
  (select count(*) from public.pachanga_market_profiles
    where display_name = 'Jugador Libre C'
      and zones @> array['Barcelona Centro']::text[]
      and modalities @> array['futbol7']::text[]) = 1,
  'Another registered user must discover the active profile'
);
select pg_temp.free_agent_assert(
  (select count(*) from public.pachanga_market_invalidations_v1
    where profile_id = (select id from public.pachanga_market_profiles
      where user_id = 'fa000000-0000-4000-8000-000000000001')) = 2,
  'Another registered user must receive bounded canonical Mercado invalidations'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}',
  true
);
select pg_temp.free_agent_assert(
  (select count(*) from public.pachanga_market_invalidations_v1) = 0,
  'Anonymous sign-in sessions must not read Mercado invalidations'
);
reset role;

do $$
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"fa000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true}',
    true
  );
  set local role authenticated;
  begin
    perform public.command_pachanga_free_agent_market_v1(
      'market.publish', 0, 'fa200000-0000-4000-8000-000000000007', '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'An anonymous sign-in session published a Mercado profile';
  exception when sqlstate '42501' then null;
  end;
  reset role;
end;
$$;

do $$
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"fa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
    true
  );
  set local role authenticated;
  begin
    update public.pachanga_market_profiles
    set display_name = 'Client forged name'
    where user_id = 'fa000000-0000-4000-8000-000000000001';
    raise exception 'Authenticated clients changed the market table directly';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.command_pachanga_free_agent_market_v1(
      'market.unpublish', 2, 'fa200000-0000-4000-8000-000000000001', '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'A reused operation id changed intent';
  exception when sqlstate 'PT409' then null;
  end;
  begin
    perform public.command_pachanga_free_agent_market_v1(
      'market.publish', 1, 'fa200000-0000-4000-8000-000000000002', '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'A stale revision was accepted';
  exception when sqlstate 'PT409' then null;
  end;
  begin
    perform public.command_pachanga_free_agent_market_v1(
      'market.publish', 3, 'fa200000-0000-4000-8000-000000000003', '{"displayName":"Forged"}'::jsonb, '{}'::jsonb
    );
    raise exception 'Client-authored market fields were accepted';
  exception when sqlstate '22023' then null;
  end;
  reset role;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
  true
);
select public.command_pachanga_free_agent_market_v1(
  'market.unpublish', 3, 'fa200000-0000-4000-8000-000000000004', '{}'::jsonb, '{}'
) as unpublished_profile \gset
reset role;

select pg_temp.free_agent_assert(
  (:'unpublished_profile'::jsonb ->> 'marketPublished')::boolean = false,
  'Unpublish must return the canonical private state'
);
select pg_temp.free_agent_assert((
  select not active from public.pachanga_market_profiles
  where user_id = 'fa000000-0000-4000-8000-000000000001'
), 'Unpublish must remove the projection from the active read model');
select pg_temp.free_agent_assert((
  select count(*) = 1 from public.pachanga_social_player_profiles_v1
  where user_id = 'fa000000-0000-4000-8000-000000000001'
), 'Unpublish must preserve the social profile');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);
select pg_temp.free_agent_assert(
  (select count(*) from public.pachanga_market_profiles where display_name = 'Jugador Libre C') = 0,
  'Other users must stop seeing the unpublished profile'
);
reset role;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"fa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
  true
);
select public.command_pachanga_free_agent_market_v1(
  'market.publish', 4, 'fa200000-0000-4000-8000-000000000006', '{}'::jsonb, '{}'
) as republished_profile \gset
reset role;

select pg_temp.free_agent_assert(
  (:'republished_profile'::jsonb ->> 'marketPublished')::boolean
    and (:'republished_profile'::jsonb ->> 'confirmedRevision')::bigint = 5,
  'A paused free-agent profile must be explicitly publishable again'
);

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
values (
  'fa300000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'Equipo que bloquea modo libre',
  'FAMARKET',
  '{"players":[],"matches":[]}'::jsonb
);
insert into public.pachanga_group_members(group_id, user_id, role, display_name)
values (
  'fa300000-0000-4000-8000-000000000001',
  'fa000000-0000-4000-8000-000000000001',
  'owner',
  'Jugador Libre C'
);

select pg_temp.free_agent_assert((
  select not active from public.pachanga_market_profiles
  where user_id = 'fa000000-0000-4000-8000-000000000001'
), 'Joining a Team must pause an existing free-agent projection');

do $$
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"fa000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}',
    true
  );
  set local role authenticated;
  begin
    perform public.command_pachanga_free_agent_market_v1(
      'market.publish', 5, 'fa200000-0000-4000-8000-000000000005', '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'A current Team member published through the free-agent command';
  exception when sqlstate '42501' then null;
  end;
  reset role;
end;
$$;

select pg_temp.free_agent_assert(
  not exists (
    select 1 from public.pachanga_player_profiles
    where user_id = 'fa000000-0000-4000-8000-000000000001'
  ),
  'The free-agent market command must not create or modify Rating V2 profiles'
);
select pg_temp.free_agent_assert(
  has_function_privilege(
    'authenticated',
    'public.command_pachanga_free_agent_market_v1(text,bigint,uuid,jsonb,jsonb)',
    'execute'
  ),
  'Authenticated clients need only the dedicated command grant'
);
select pg_temp.free_agent_assert(
  not has_function_privilege(
    'anon',
    'public.command_pachanga_free_agent_market_v1(text,bigint,uuid,jsonb,jsonb)',
    'execute'
  ),
  'Anonymous clients must not publish profiles'
);
select pg_temp.free_agent_assert(
  not has_table_privilege('authenticated', 'public.pachanga_market_profiles', 'insert')
    and not has_table_privilege('authenticated', 'public.pachanga_market_profiles', 'update')
    and not has_table_privilege('authenticated', 'public.pachanga_market_profiles', 'delete'),
  'Mercado projection writes must remain RPC-only'
);
select pg_temp.free_agent_assert(
  has_table_privilege('authenticated', 'public.pachanga_market_invalidations_v1', 'select')
    and not has_table_privilege('authenticated', 'public.pachanga_market_invalidations_v1', 'insert')
    and not has_table_privilege('authenticated', 'public.pachanga_market_invalidations_v1', 'update')
    and not has_table_privilege('authenticated', 'public.pachanga_market_invalidations_v1', 'delete'),
  'Mercado invalidations must be readable but server-write-only'
);
select pg_temp.free_agent_assert((
  select array_agg(active order by server_sequence, id)
    = array[true,true,false,true,false]::boolean[]
  from public.pachanga_market_invalidations_v1
  where profile_id = (
    select id from public.pachanga_market_profiles
    where user_id = 'fa000000-0000-4000-8000-000000000001'
  )
), 'Mercado invalidations must preserve publish, edit, pause, republish and Team-join order');

rollback;
