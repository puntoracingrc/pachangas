\set ON_ERROR_STOP on

create or replace function pg_temp.team_invite_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email) values
  ('f6000000-0000-4000-8000-000000000001', 'team-link-owner@example.test'),
  ('f6000000-0000-4000-8000-000000000002', 'team-link-player-one@example.test'),
  ('f6000000-0000-4000-8000-000000000003', 'team-link-player-two@example.test'),
  ('f6000000-0000-4000-8000-000000000004', 'team-code-requester@example.test'),
  ('f6000000-0000-4000-8000-000000000005', 'team-link-outsider@example.test');

update private.pachanga_social_team_settings_v1 set
  social_profile_foundation_enabled = true,
  social_profile_independent_write_enabled = true,
  social_team_creation_enabled = true,
  social_team_invitation_v2_enabled = true,
  social_team_membership_v2_enabled = true,
  social_team_home_v3f_enabled = true;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_social_profile_v1(
  'profile.create', 0, 'f6100000-0000-4000-8000-000000000001',
  '{"displayName":"Owner Enlace","primaryPosition":"Mediocentro / pivote","preferredModality":"futbol7","generalArea":"Barcelona"}'::jsonb,
  '{}'::jsonb
) as owner_profile \gset
select public.command_pachanga_social_team_v1(
  'team.create', 0, 'f6200000-0000-4000-8000-000000000001',
  '{"name":"Equipo Enlace Reutilizable","modality":"futbol7","generalArea":"Barcelona","shieldKey":"team.shield.shape.round"}'::jsonb,
  '{}'::jsonb
) as created_team \gset
reset role;

select set_config('team_invite.group_id', :'created_team'::jsonb ->> 'groupId', true) as saved_group_id \gset
select set_config('team_invite.team_code', (select team_code from public.pachanga_groups where id = current_setting('team_invite.group_id')::uuid), true) as saved_team_code \gset

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_social_profile_v1(
  'profile.create', 0, 'f6100000-0000-4000-8000-000000000002',
  '{"displayName":"Jugador Uno","primaryPosition":"Defensa central","preferredModality":"futbol7","generalArea":"Barcelona"}'::jsonb,
  '{}'::jsonb
) as player_one_profile \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_social_profile_v1(
  'profile.create', 0, 'f6100000-0000-4000-8000-000000000003',
  '{"displayName":"Jugador Dos","primaryPosition":"Delantero / punta","preferredModality":"futbol7","generalArea":"Barcelona"}'::jsonb,
  '{}'::jsonb
) as player_two_profile \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_social_profile_v1(
  'profile.create', 0, 'f6100000-0000-4000-8000-000000000004',
  '{"displayName":"Solicitante Código","primaryPosition":"Portero","preferredModality":"futbol7","generalArea":"Barcelona"}'::jsonb,
  '{}'::jsonb
) as requester_profile \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_social_profile_v1(
  'profile.create', 0, 'f6100000-0000-4000-8000-000000000005',
  '{"displayName":"Usuario Ajeno","primaryPosition":"Extremo","preferredModality":"futbol7","generalArea":"Barcelona"}'::jsonb,
  '{}'::jsonb
) as outsider_profile \gset
reset role;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_team_player_invitation_v2(
  'team.invitation.create', current_setting('team_invite.group_id')::uuid, null, null,
  (select revision from public.pachanga_social_team_states_v1 where group_id = current_setting('team_invite.group_id')::uuid),
  'f6300000-0000-4000-8000-000000000001',
  '{"expiresInHours":168,"inviteMode":"TEAM_LINK","maxUses":3}'::jsonb,
  '{}'::jsonb
) as created_link \gset
reset role;

select set_config('team_invite.invitation_id', :'created_link'::jsonb ->> 'invitationId', true) as saved_invitation_id \gset
select set_config('team_invite.token', :'created_link'::jsonb ->> 'shareToken', true) as saved_invitation_token \gset
select pg_temp.team_invite_assert(:'created_link'::jsonb ->> 'inviteMode' = 'TEAM_LINK', 'The shared link must be reusable');
select pg_temp.team_invite_assert((:'created_link'::jsonb ->> 'maxUses')::integer = 3, 'The server must enforce the configured shared-link capacity');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);
select public.lookup_pachanga_team_player_invitation_v2(current_setting('team_invite.token')) as first_lookup \gset
select public.command_pachanga_team_player_invitation_v2(
  'team.invitation.accept', null, current_setting('team_invite.invitation_id')::uuid,
  current_setting('team_invite.token'), 1,
  'f6400000-0000-4000-8000-000000000001', '{}'::jsonb, '{}'::jsonb
) as first_accept \gset
reset role;

select pg_temp.team_invite_assert(not (:'first_lookup'::jsonb ->> 'alreadyMember')::boolean, 'A new player must not be reported as a current member');
select pg_temp.team_invite_assert(:'first_accept'::jsonb ->> 'state' = 'ACTIVE', 'The reusable link must remain active after its first use');
select pg_temp.team_invite_assert((:'first_accept'::jsonb ->> 'useCount')::integer = 1, 'First acceptance must consume exactly one place');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000003","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_team_player_invitation_v2(
  'team.invitation.accept', null, current_setting('team_invite.invitation_id')::uuid,
  current_setting('team_invite.token'), 1,
  'f6400000-0000-4000-8000-000000000002', '{}'::jsonb, '{}'::jsonb
) as second_accept \gset
reset role;

select pg_temp.team_invite_assert((:'second_accept'::jsonb ->> 'useCount')::integer = 2, 'A second player must be able to use the same shared link');
select pg_temp.team_invite_assert((select count(*) from public.pachanga_group_members where group_id = current_setting('team_invite.group_id')::uuid and user_id in ('f6000000-0000-4000-8000-000000000002','f6000000-0000-4000-8000-000000000003') and role = 'player') = 2, 'Shared links may only create player memberships');
select pg_temp.team_invite_assert((select count(*) from private.pachanga_team_player_invitation_uses_v3 where invitation_id = current_setting('team_invite.invitation_id')::uuid) = 2, 'Each accepted player must have one private ledger entry');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);
select public.lookup_pachanga_team_player_invitation_v2(current_setting('team_invite.token')) as member_lookup \gset
reset role;
select pg_temp.team_invite_assert((:'member_lookup'::jsonb ->> 'alreadyMember')::boolean, 'An existing member must receive the canonical alreadyMember state');

do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);
  set local role authenticated;
  begin
    perform public.command_pachanga_team_player_invitation_v2(
      'team.invitation.accept', null, current_setting('team_invite.invitation_id')::uuid,
      current_setting('team_invite.token'), 1,
      'f6400000-0000-4000-8000-000000000003', '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'An existing member consumed the shared link twice';
  exception when sqlstate 'PT409' then
    if sqlerrm <> 'ALREADY_TEAM_MEMBER' then raise; end if;
  end;
  reset role;
end;
$$;

select pg_temp.team_invite_assert((select use_count from public.pachanga_team_player_invitations_v2 where id = current_setting('team_invite.invitation_id')::uuid) = 2, 'A repeat by an existing member must not consume capacity');
select pg_temp.team_invite_assert((select count(*) from public.pachanga_group_members where group_id = current_setting('team_invite.group_id')::uuid and user_id = 'f6000000-0000-4000-8000-000000000002') = 1, 'An existing member must never be duplicated');
select pg_temp.team_invite_assert(not exists (select 1 from private.pachanga_social_events_v1 where payload::text like '%' || current_setting('team_invite.token') || '%'), 'The raw shared token must not enter the evidence log');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000004","role":"authenticated","is_anonymous":false}', true);
select public.lookup_pachanga_social_team_code_v1(current_setting('team_invite.team_code')) as code_lookup \gset
select public.command_pachanga_team_membership_request_v1(
  'team.membership.request.create', current_setting('team_invite.group_id')::uuid, null,
  (:'code_lookup'::jsonb ->> 'teamRevision')::bigint,
  'f6500000-0000-4000-8000-000000000001', '{}'::jsonb, '{}'::jsonb
) as membership_request \gset
reset role;

select set_config('team_invite.request_id', :'membership_request'::jsonb ->> 'requestId', true) as saved_request_id \gset
select pg_temp.team_invite_assert(:'code_lookup'::jsonb ->> 'joinPolicy' = 'ADMIN_APPROVAL', 'The short code must require admin approval');
select pg_temp.team_invite_assert(not exists (select 1 from public.pachanga_group_members where group_id = current_setting('team_invite.group_id')::uuid and user_id = 'f6000000-0000-4000-8000-000000000004'), 'A code lookup or request must not create membership');

do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}', true);
  set local role authenticated;
  begin
    perform public.command_pachanga_team_membership_request_v1(
      'team.membership.request.accept', current_setting('team_invite.group_id')::uuid,
      current_setting('team_invite.request_id')::uuid, 1,
      'f6500000-0000-4000-8000-000000000002', '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'A non-admin accepted another player request';
  exception when insufficient_privilege then null;
  end;
  reset role;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}', true);
select public.get_pachanga_team_membership_requests_v1(current_setting('team_invite.group_id')::uuid) as admin_requests \gset
select public.command_pachanga_team_membership_request_v1(
  'team.membership.request.accept', current_setting('team_invite.group_id')::uuid,
  current_setting('team_invite.request_id')::uuid, 1,
  'f6500000-0000-4000-8000-000000000003', '{}'::jsonb, '{}'::jsonb
) as accepted_request \gset
reset role;

select pg_temp.team_invite_assert(jsonb_array_length(:'admin_requests'::jsonb) = 1, 'The admin must see the pending request');
select pg_temp.team_invite_assert(:'accepted_request'::jsonb ->> 'state' = 'ACCEPTED', 'The admin must be able to accept the request');
select pg_temp.team_invite_assert((select role from public.pachanga_group_members where group_id = current_setting('team_invite.group_id')::uuid and user_id = 'f6000000-0000-4000-8000-000000000004') = 'player', 'Admin approval may only grant player membership');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f6000000-0000-4000-8000-000000000005","role":"authenticated","is_anonymous":false}', true);
select pg_temp.team_invite_assert((select count(*) from public.pachanga_team_membership_requests_v1) = 0, 'An unrelated player must not see another player request through RLS');
reset role;

select pg_temp.team_invite_assert(not exists (
  select 1 from public.pachanga_group_members
  where group_id = current_setting('team_invite.group_id')::uuid
    and user_id <> 'f6000000-0000-4000-8000-000000000001'
    and role in ('owner','admin')
), 'No invitation or membership request may grant owner/admin');
select pg_temp.team_invite_assert(not exists (
  select 1 from public.pachanga_player_profiles
  where user_id in (
    'f6000000-0000-4000-8000-000000000001',
    'f6000000-0000-4000-8000-000000000002',
    'f6000000-0000-4000-8000-000000000003',
    'f6000000-0000-4000-8000-000000000004',
    'f6000000-0000-4000-8000-000000000005'
  )
), 'Team invitation flows must not alter Rating V2 profiles');
