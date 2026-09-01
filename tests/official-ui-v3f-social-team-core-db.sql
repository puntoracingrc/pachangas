\set ON_ERROR_STOP on

create or replace function pg_temp.v3f_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

insert into auth.users(id, email) values
  ('f3000000-0000-4000-8000-000000000001', 'v3f-owner@example.test'),
  ('f3000000-0000-4000-8000-000000000002', 'v3f-player@example.test'),
  ('f3000000-0000-4000-8000-000000000003', 'v3f-outsider@example.test');

update private.pachanga_social_team_settings_v1 set
  social_profile_foundation_enabled = true,
  social_profile_independent_write_enabled = true,
  social_team_creation_enabled = true,
  social_team_invitation_v2_enabled = true,
  social_team_membership_v2_enabled = true,
  social_team_home_v3f_enabled = true,
  demo_social_team_journey_enabled = true;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_social_profile_v1(
  'profile.create', 0, 'f3100000-0000-4000-8000-000000000001',
  '{"displayName":"Owner V3F","primaryPosition":"Mediocentro / pivote","secondaryPosition":"Defensa central","preferredModality":"futbol7","generalArea":"Barcelona","usualDays":["M","J"],"approximateTime":"20:00-22:00","shortBio":"Juego y organizo.","socialPreferences":{"openToTeamInvites":true,"openToMatchInvites":true}}'::jsonb,
  '{"clientVersion":"1.0.0","displayMode":"browser"}'::jsonb
) as owner_profile \gset
select public.command_pachanga_social_team_v1(
  'team.create', 0, 'f3200000-0000-4000-8000-000000000001',
  '{"name":"V3F Social Team","modality":"futbol7","generalArea":"Barcelona","targetPlayerCount":14,"shieldKey":"team.shield.shape.round"}'::jsonb,
  '{"clientVersion":"1.0.0","displayMode":"browser"}'::jsonb
) as created_team \gset
reset role;

select set_config('v3f.group_id', :'created_team'::jsonb ->> 'groupId', true) as saved_group_id \gset
select set_config('v3f.team_revision', :'created_team'::jsonb ->> 'teamRevision', true) as saved_team_revision \gset
select pg_temp.v3f_assert(:'owner_profile'::jsonb ->> 'ratingAuthority' = 'SEPARATE', 'Social profile must declare separate Rating authority');
select pg_temp.v3f_assert(:'created_team'::jsonb ->> 'role' = 'owner', 'Atomic creator must be owner');
select pg_temp.v3f_assert((:'created_team'::jsonb ->> 'memberCount')::integer = 1, 'Atomic Team must start with exactly one member');
select pg_temp.v3f_assert((:'created_team'::jsonb -> 'shield' ->> 'shapeKey') = 'team.shield.shape.round', 'Selected base shield must be persisted');
select pg_temp.v3f_assert((select lifecycle_status from private.pachanga_team_operational_states_v1 where group_id=current_setting('v3f.group_id')::uuid)='ACTIVE', 'New Team must start ACTIVE');
select pg_temp.v3f_assert((select enforcement_status from private.pachanga_team_operational_states_v1 where group_id=current_setting('v3f.group_id')::uuid)='CLEAR', 'New Team must start CLEAR');
select pg_temp.v3f_assert((select revision from public.pachanga_team_shield_public where group_id=current_setting('v3f.group_id')::uuid)=1, 'Initial shield projection must exist');
select pg_temp.v3f_assert((select count(*) from public.pachanga_group_members where group_id=current_setting('v3f.group_id')::uuid and role='owner')=1, 'Exactly one owner membership required');
select pg_temp.v3f_assert((select payload->'matches' from public.pachanga_groups where id=current_setting('v3f.group_id')::uuid)='[]'::jsonb, 'Team creation must not fabricate a sporting match');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_social_profile_v1(
  'profile.create', 0, 'f3100000-0000-4000-8000-000000000002',
  '{"displayName":"Player V3F","primaryPosition":"Delantero / punta","preferredModality":"futbol7","generalArea":"Barcelona","usualDays":["S"],"approximateTime":"16:00-20:00","socialPreferences":{"openToTeamInvites":true}}'::jsonb,
  '{}'::jsonb
) as player_profile \gset
reset role;

select revision as invite_expected_revision
from public.pachanga_social_team_states_v1
where group_id=current_setting('v3f.group_id')::uuid \gset
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_team_player_invitation_v2(
  'invitation.create', current_setting('v3f.group_id')::uuid, null, null,
  :'invite_expected_revision'::bigint,
  'f3300000-0000-4000-8000-000000000001', '{"expiresInHours":24}'::jsonb, '{}'::jsonb
) as created_invite \gset
select public.command_pachanga_team_player_invitation_v2(
  'invitation.create', current_setting('v3f.group_id')::uuid, null, null,
  :'invite_expected_revision'::bigint,
  'f3300000-0000-4000-8000-000000000001', '{"expiresInHours":24}'::jsonb, '{}'::jsonb
) as replayed_invite \gset
reset role;

select set_config('v3f.invitation_id', :'created_invite'::jsonb ->> 'invitationId', true) as saved_invitation_id \gset
select set_config('v3f.invitation_token', :'created_invite'::jsonb ->> 'shareToken', true) as saved_invitation_token \gset
select pg_temp.v3f_assert(current_setting('v3f.invitation_token') ~ '^piq_[0-9a-f]{64}$', 'Raw invitation must have the expected opaque format');
select pg_temp.v3f_assert(not (:'replayed_invite'::jsonb ? 'shareToken'), 'Idempotent retry must never replay the raw token');
select pg_temp.v3f_assert((:'replayed_invite'::jsonb ->> 'tokenAlreadyIssued')::boolean, 'Retry must explain that the token was already issued');
select pg_temp.v3f_assert((select response ? 'shareToken' from private.pachanga_social_operation_receipts_v1 where operation_id='f3300000-0000-4000-8000-000000000001')=false, 'Receipt must not contain the raw token');
select pg_temp.v3f_assert((select token_hash <> current_setting('v3f.invitation_token') and char_length(token_hash)=64 from private.pachanga_team_player_invitation_secrets_v2 where invitation_id=current_setting('v3f.invitation_id')::uuid), 'Only the token hash may persist');
select pg_temp.v3f_assert(not exists (select 1 from private.pachanga_social_events_v1 where payload::text like '%' || current_setting('v3f.invitation_token') || '%'), 'Events must not leak raw invitation tokens');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);
select public.lookup_pachanga_team_player_invitation_v2(current_setting('v3f.invitation_token')) as lookup_invite \gset
select public.command_pachanga_team_player_invitation_v2(
  'invitation.accept', null, current_setting('v3f.invitation_id')::uuid,
  current_setting('v3f.invitation_token'), 1,
  'f3400000-0000-4000-8000-000000000001', '{}'::jsonb, '{}'::jsonb
) as accepted_invite \gset
reset role;

select pg_temp.v3f_assert(:'lookup_invite'::jsonb ->> 'state' = 'ACTIVE', 'Bearer lookup must return an active safe snapshot');
select pg_temp.v3f_assert(:'accepted_invite'::jsonb ->> 'state' = 'USED', 'Accept must consume the invitation');
select pg_temp.v3f_assert((select role from public.pachanga_group_members where group_id=current_setting('v3f.group_id')::uuid and user_id='f3000000-0000-4000-8000-000000000002')='player', 'Player invitation may only grant player role');
select pg_temp.v3f_assert((select count(*) from public.pachanga_group_members where group_id=current_setting('v3f.group_id')::uuid)=2, 'Accept must create one membership');
select pg_temp.v3f_assert((select count(*) from public.pachanga_team_player_invitations_v2 where id=current_setting('v3f.invitation_id')::uuid and use_count=1)=1, 'Invitation must remain single use');

do $$
begin
  perform set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}', true);
  set local role authenticated;
  begin
    perform public.command_pachanga_team_player_invitation_v2(
      'invitation.accept', null, current_setting('v3f.invitation_id')::uuid,
      current_setting('v3f.invitation_token'), 2,
      'f3400000-0000-4000-8000-000000000002', '{}'::jsonb, '{}'::jsonb
    );
    raise exception 'A used invitation was accepted twice';
  exception when sqlstate 'PT409' then null;
  end;
  reset role;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":false}', true);
select public.command_pachanga_team_player_invitation_v2(
  'invitation.create', current_setting('v3f.group_id')::uuid, null, null,
  (select revision from public.pachanga_social_team_states_v1 where group_id=current_setting('v3f.group_id')::uuid),
  'f3300000-0000-4000-8000-000000000002', '{"expiresInHours":24}'::jsonb, '{}'::jsonb
) as revoke_candidate \gset
select public.command_pachanga_team_player_invitation_v2(
  'invitation.revoke', current_setting('v3f.group_id')::uuid,
  (:'revoke_candidate'::jsonb ->> 'invitationId')::uuid, null, 1,
  'f3500000-0000-4000-8000-000000000001', '{}'::jsonb, '{}'::jsonb
) as revoked_invite \gset
reset role;
select pg_temp.v3f_assert(:'revoked_invite'::jsonb ->> 'state' = 'REVOKED', 'Admin must be able to revoke an active invitation');

select pg_temp.v3f_assert(not has_function_privilege('authenticated','public.join_pachanga_group(uuid)','execute'), 'Legacy group-token join must be revoked');
select pg_temp.v3f_assert(not has_function_privilege('authenticated','public.join_pachanga_team(uuid,text)','execute'), 'Legacy Team-token join must be revoked');
select pg_temp.v3f_assert(has_function_privilege('authenticated','public.accept_pachanga_admin_invite_authoritative_v1(uuid,text,uuid,bigint,jsonb)','execute'), 'Separate admin invitation flow must remain available');
select pg_temp.v3f_assert(not has_table_privilege('authenticated','public.pachanga_groups','insert'), 'Authenticated clients must not insert Teams directly');
select pg_temp.v3f_assert(not has_table_privilege('authenticated','public.pachanga_group_members','insert'), 'Authenticated clients must not insert memberships directly');
select pg_temp.v3f_assert(not exists (
  select 1 from information_schema.columns
  where table_schema='public' and table_name='pachanga_social_player_profiles_v1'
    and column_name in ('rating','facets','grl','rating_votes','current_overall')
), 'Social profile authority must not contain Rating V2 fields');
select pg_temp.v3f_assert(not exists (
  select 1 from public.pachanga_player_profiles
  where user_id in ('f3000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000002')
), 'V3F onboarding must not create or alter a Rating V2 profile');
