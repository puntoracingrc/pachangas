-- Reusable Team links for sharing with a group, while preserving one-use invites.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_team_player_invitations_v2
  add column if not exists invite_mode text not null default 'INDIVIDUAL';

do $$
declare constraint_row record;
begin
  for constraint_row in
    select constraints.conname, pg_get_constraintdef(constraints.oid) as definition
    from pg_constraint constraints
    where constraints.conrelid = 'public.pachanga_team_player_invitations_v2'::regclass
      and constraints.contype = 'c'
  loop
    if constraint_row.definition like '%max_uses = 1%'
       or (constraint_row.definition like '%use_count%' and constraint_row.definition like '%max_uses%')
       or (constraint_row.definition like '%state = ''USED''%' and constraint_row.definition like '%accepted_by%') then
      execute format(
        'alter table public.pachanga_team_player_invitations_v2 drop constraint %I',
        constraint_row.conname
      );
    end if;
  end loop;
end;
$$;

alter table public.pachanga_team_player_invitations_v2
  add constraint pachanga_team_player_invitations_v2_mode_v3_check
    check (invite_mode in ('INDIVIDUAL','TEAM_LINK')),
  add constraint pachanga_team_player_invitations_v2_max_uses_v3_check
    check (max_uses between 1 and 100),
  add constraint pachanga_team_player_invitations_v2_use_count_v3_check
    check (use_count between 0 and max_uses),
  add constraint pachanga_team_player_invitations_v2_mode_capacity_v3_check
    check (
      (invite_mode = 'INDIVIDUAL' and max_uses = 1)
      or (invite_mode = 'TEAM_LINK' and max_uses between 2 and 100)
    ),
  add constraint pachanga_team_player_invitations_v2_used_state_v3_check
    check ((state = 'USED') = (use_count = max_uses)),
  add constraint pachanga_team_player_invitations_v2_acceptance_actor_v3_check
    check (
      (invite_mode = 'INDIVIDUAL' and ((state = 'USED') = (accepted_by is not null and accepted_at is not null)))
      or (invite_mode = 'TEAM_LINK' and accepted_by is null and accepted_at is null and state <> 'DECLINED')
    );

create table if not exists private.pachanga_team_player_invitation_uses_v3 (
  invitation_id uuid not null references public.pachanga_team_player_invitations_v2(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  operation_id uuid not null,
  server_sequence bigint not null,
  accepted_at timestamptz not null default clock_timestamp(),
  primary key (invitation_id, user_id),
  unique (operation_id),
  check (server_sequence >= 1)
);

create index if not exists pachanga_team_player_invitation_uses_v3_user_idx
  on private.pachanga_team_player_invitation_uses_v3(user_id, accepted_at desc, invitation_id);

revoke all on table private.pachanga_team_player_invitation_uses_v3 from public, anon, authenticated;
grant all on table private.pachanga_team_player_invitation_uses_v3 to service_role;

insert into private.pachanga_team_player_invitation_uses_v3(
  invitation_id, user_id, operation_id, server_sequence, accepted_at
)
select
  invitations.id,
  invitations.accepted_by,
  coalesce((
    select revisions.operation_id
    from private.pachanga_team_player_invitation_revisions_v2 revisions
    where revisions.invitation_id = invitations.id
      and revisions.state = 'USED'
    order by revisions.revision desc, revisions.id
    limit 1
  ), gen_random_uuid()),
  invitations.server_sequence,
  invitations.accepted_at
from public.pachanga_team_player_invitations_v2 invitations
where invitations.invite_mode = 'INDIVIDUAL'
  and invitations.state = 'USED'
  and invitations.accepted_by is not null
  and invitations.accepted_at is not null
on conflict do nothing;

create or replace function private.pachanga_team_player_invitation_snapshot_v2(
  target_invitation_id uuid,
  include_team boolean default true
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kind', 'TeamPlayerInvitationV2',
    'invitationId', invitations.id,
    'inviteMode', invitations.invite_mode,
    'groupId', invitations.group_id,
    'teamName', case when include_team then groups.name else null end,
    'teamCode', case when include_team then groups.team_code else null end,
    'modality', case when include_team then groups.social_modality else null end,
    'generalArea', case when include_team then groups.social_general_area else null end,
    'createdByName', coalesce(creators.display_name, creators_membership.display_name, 'Admin del equipo'),
    'state', case
      when invitations.state = 'ACTIVE' and invitations.expires_at <= clock_timestamp() then 'EXPIRED'
      else invitations.state
    end,
    'maxUses', invitations.max_uses,
    'useCount', invitations.use_count,
    'remainingUses', greatest(invitations.max_uses - invitations.use_count, 0),
    'revision', invitations.revision,
    'confirmedRevision', invitations.revision,
    'serverSequence', invitations.server_sequence,
    'expiresAt', invitations.expires_at,
    'createdAt', invitations.created_at,
    'updatedAt', invitations.updated_at
  ))
  from public.pachanga_team_player_invitations_v2 invitations
  join public.pachanga_groups groups on groups.id = invitations.group_id
  left join public.pachanga_social_player_profiles_v1 creators on creators.user_id = invitations.created_by
  left join public.pachanga_group_members creators_membership
    on creators_membership.group_id = invitations.group_id
   and creators_membership.user_id = invitations.created_by
  where invitations.id = target_invitation_id;
$$;

create or replace function public.lookup_pachanga_team_player_invitation_v2(
  invitation_token text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare token_value text := trim(coalesce(invitation_token, ''));
declare token_hash text;
declare invitation_id uuid;
declare invitation_group_id uuid;
declare settings private.pachanga_social_team_settings_v1%rowtype;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501';
  end if;
  if token_value !~ '^piq_[0-9a-f]{64}$' then return null; end if;
  select * into settings from private.pachanga_social_team_settings_v1 where singleton;
  if not settings.social_team_invitation_v2_enabled then return null; end if;
  token_hash := encode(extensions.digest(convert_to(token_value, 'UTF8'), 'sha256'), 'hex');
  select secrets.invitation_id, invitations.group_id
    into invitation_id, invitation_group_id
  from private.pachanga_team_player_invitation_secrets_v2 secrets
  join public.pachanga_team_player_invitations_v2 invitations on invitations.id = secrets.invitation_id
  where secrets.token_hash = token_hash;
  if invitation_id is null then return null; end if;
  return private.pachanga_team_player_invitation_snapshot_v2(invitation_id, true)
    || jsonb_build_object(
      'alreadyMember', exists (
        select 1
        from public.pachanga_group_members members
        where members.group_id = invitation_group_id
          and members.user_id = actor_id
      )
    );
end;
$$;

create or replace function public.command_pachanga_team_player_invitation_v2(
  action text,
  target_group_id uuid,
  target_invitation_id uuid,
  invitation_token text,
  expected_revision bigint,
  operation_id uuid,
  payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare action_name text := lower(trim(coalesce(action, '')));
declare body jsonb := coalesce(payload, '{}'::jsonb);
declare token_value text := trim(coalesce(invitation_token, ''));
declare token_hash text;
declare raw_token text;
declare settings private.pachanga_social_team_settings_v1%rowtype;
declare invitation public.pachanga_team_player_invitations_v2%rowtype;
declare existing_receipt private.pachanga_social_operation_receipts_v1%rowtype;
declare team_state public.pachanga_social_team_states_v1%rowtype;
declare invitation_id uuid;
declare aggregate_id text;
declare request_hash text;
declare response jsonb;
declare safe_response jsonb;
declare next_sequence bigint;
declare expiry_hours integer;
declare requested_max_uses integer;
declare requested_mode text;
declare admin_user record;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'AUTHENTICATION_OPERATION_AND_REVISION_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501';
  end if;
  if action_name not in (
    'team.invitation.create','team.invitation.revoke','team.invitation.accept',
    'team.invitation.decline','team.invitation.expire'
  ) then raise exception 'UNSUPPORTED_INVITATION_ACTION' using errcode = '22023'; end if;
  if jsonb_typeof(body) <> 'object' then raise exception 'INVALID_INVITATION_PAYLOAD' using errcode = '22023'; end if;

  select * into settings from private.pachanga_social_team_settings_v1 where singleton;
  if not settings.social_team_invitation_v2_enabled
     or not settings.social_team_membership_v2_enabled then
    raise exception 'TEAM_PLAYER_INVITATIONS_DISABLED' using errcode = '42501';
  end if;

  if action_name = 'team.invitation.create' then
    if target_group_id is null or target_invitation_id is not null or token_value <> ''
       or body - array['expiresInHours','inviteMode','maxUses']::text[] <> '{}'::jsonb then
      raise exception 'INVALID_INVITATION_CREATE_REQUEST' using errcode = '22023';
    end if;
    aggregate_id := target_group_id::text;
  else
    if body <> '{}'::jsonb then raise exception 'INVITATION_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
    if action_name in ('team.invitation.accept','team.invitation.decline') then
      if token_value !~ '^piq_[0-9a-f]{64}$' then raise exception 'INVALID_INVITATION_TOKEN' using errcode = '22023'; end if;
      token_hash := encode(extensions.digest(convert_to(token_value, 'UTF8'), 'sha256'), 'hex');
      select secrets.invitation_id into invitation_id
      from private.pachanga_team_player_invitation_secrets_v2 secrets
      where secrets.token_hash = token_hash;
      if invitation_id is null then raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0002'; end if;
      if target_invitation_id is not null and target_invitation_id <> invitation_id then
        raise exception 'INVITATION_TOKEN_MISMATCH' using errcode = '42501';
      end if;
    else
      invitation_id := target_invitation_id;
      if invitation_id is null or token_value <> '' then raise exception 'INVITATION_ID_REQUIRED' using errcode = '22023'; end if;
    end if;
    aggregate_id := invitation_id::text;
  end if;

  request_hash := private.pachanga_social_request_hash_v1(
    action_name, aggregate_id, expected_revision,
    body || case when token_hash is null then '{}'::jsonb else jsonb_build_object('tokenHash', token_hash) end
  );
  perform pg_advisory_xact_lock(hashtextextended('social-operation:' || operation_id::text, 0));
  select * into existing_receipt from private.pachanga_social_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_team_player_invitation_v2.operation_id;
  if found then
    if existing_receipt.actor_id <> actor_id or existing_receipt.action <> action_name
       or existing_receipt.request_hash <> request_hash then
      raise exception 'OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return existing_receipt.response || case
      when action_name = 'team.invitation.create' then jsonb_build_object('tokenAlreadyIssued', true)
      else '{}'::jsonb
    end;
  end if;

  if action_name = 'team.invitation.create' then
    if not public.is_pachanga_group_admin(target_group_id) then raise exception 'TEAM_ADMIN_REQUIRED' using errcode = '42501'; end if;
    perform private.pachanga_assert_team_operational_scope_v1(target_group_id, 'TEAM_MEMBERSHIP_ADMINISTRATION');
    perform pg_advisory_xact_lock(hashtextextended('social-team:' || target_group_id::text, 0));
    select * into team_state from public.pachanga_social_team_states_v1 states
    where states.group_id = target_group_id for update;
    if not found then raise exception 'SOCIAL_TEAM_STATE_NOT_FOUND' using errcode = 'P0002'; end if;
    if team_state.revision <> expected_revision then raise exception 'STALE_TEAM_REVISION' using errcode = 'PT409'; end if;
    begin expiry_hours := coalesce((body ->> 'expiresInHours')::integer, 168);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'INVALID_INVITATION_EXPIRY' using errcode = '22023';
    end;
    if expiry_hours not between 1 and 720 then raise exception 'INVALID_INVITATION_EXPIRY' using errcode = '22023'; end if;
    requested_mode := upper(trim(coalesce(body ->> 'inviteMode', 'INDIVIDUAL')));
    if requested_mode not in ('INDIVIDUAL','TEAM_LINK') then
      raise exception 'INVALID_INVITATION_MODE' using errcode = '22023';
    end if;
    begin requested_max_uses := coalesce((body ->> 'maxUses')::integer, case when requested_mode = 'TEAM_LINK' then 100 else 1 end);
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'INVALID_INVITATION_CAPACITY' using errcode = '22023';
    end;
    if (requested_mode = 'INDIVIDUAL' and requested_max_uses <> 1)
       or (requested_mode = 'TEAM_LINK' and requested_max_uses not between 2 and 100) then
      raise exception 'INVALID_INVITATION_CAPACITY' using errcode = '22023';
    end if;

    invitation_id := gen_random_uuid();
    raw_token := 'piq_' || encode(extensions.gen_random_bytes(32), 'hex');
    token_hash := encode(extensions.digest(convert_to(raw_token, 'UTF8'), 'sha256'), 'hex');
    next_sequence := nextval('private.pachanga_social_team_sequence_v1');
    insert into public.pachanga_team_player_invitations_v2(
      id, group_id, created_by, invite_mode, max_uses, expires_at, revision, server_sequence
    ) values (
      invitation_id, target_group_id, actor_id, requested_mode, requested_max_uses,
      clock_timestamp() + make_interval(hours => expiry_hours), 1, next_sequence
    ) returning * into invitation;
    insert into private.pachanga_team_player_invitation_secrets_v2(invitation_id, token_hash)
      values (invitation_id, token_hash);
  else
    perform pg_advisory_xact_lock(hashtextextended('social-invitation:' || invitation_id::text, 0));
    select * into invitation from public.pachanga_team_player_invitations_v2 invitations
    where invitations.id = invitation_id for update;
    if not found then raise exception 'INVITATION_NOT_FOUND' using errcode = 'P0002'; end if;
    if target_group_id is not null and target_group_id <> invitation.group_id then
      raise exception 'INVITATION_TEAM_MISMATCH' using errcode = '42501';
    end if;
    if action_name = 'team.invitation.accept' and invitation.invite_mode = 'TEAM_LINK' then
      if expected_revision > invitation.revision then raise exception 'STALE_INVITATION_REVISION' using errcode = 'PT409'; end if;
    elsif invitation.revision <> expected_revision then
      raise exception 'STALE_INVITATION_REVISION' using errcode = 'PT409';
    end if;

    if action_name in ('team.invitation.revoke','team.invitation.expire') then
      if not public.is_pachanga_group_admin(invitation.group_id) then raise exception 'TEAM_ADMIN_REQUIRED' using errcode = '42501'; end if;
    end if;
    if invitation.state <> 'ACTIVE' then raise exception 'INVITATION_NOT_ACTIVE' using errcode = 'PT409'; end if;
    if action_name <> 'team.invitation.expire' and invitation.expires_at <= clock_timestamp() then
      raise exception 'INVITATION_EXPIRED' using errcode = 'PT409';
    end if;
    if action_name = 'team.invitation.expire' and invitation.expires_at > clock_timestamp() then
      raise exception 'INVITATION_NOT_EXPIRED' using errcode = 'PT409';
    end if;
    if action_name = 'team.invitation.decline' and invitation.invite_mode = 'TEAM_LINK' then
      raise exception 'SHARED_LINK_CANNOT_BE_DECLINED' using errcode = '22023';
    end if;
    perform private.pachanga_assert_team_operational_scope_v1(invitation.group_id, 'TEAM_MEMBERSHIP_ADMINISTRATION');
    next_sequence := nextval('private.pachanga_social_team_sequence_v1');

    if action_name = 'team.invitation.accept' then
      if not exists (select 1 from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = actor_id) then
        raise exception 'SOCIAL_PROFILE_REQUIRED' using errcode = '42501';
      end if;
      if exists (select 1 from public.pachanga_group_members members where members.group_id = invitation.group_id and members.user_id = actor_id) then
        raise exception 'ALREADY_TEAM_MEMBER' using errcode = 'PT409';
      end if;
      insert into public.pachanga_group_members(group_id, user_id, role, display_name)
      select invitation.group_id, actor_id, 'player', profiles.display_name
      from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = actor_id;
      insert into private.pachanga_team_player_invitation_uses_v3(
        invitation_id, user_id, operation_id, server_sequence
      ) values (invitation.id, actor_id, operation_id, next_sequence);
      update public.pachanga_team_player_invitations_v2 invitations set
        state = case when invitations.use_count + 1 >= invitations.max_uses then 'USED' else 'ACTIVE' end,
        use_count = invitations.use_count + 1,
        accepted_by = case when invitations.invite_mode = 'INDIVIDUAL' then actor_id else null end,
        accepted_at = case when invitations.invite_mode = 'INDIVIDUAL' then clock_timestamp() else null end,
        revision = invitations.revision + 1,
        server_sequence = next_sequence,
        updated_at = clock_timestamp()
      where invitations.id = invitation.id returning * into invitation;
    elsif action_name = 'team.invitation.decline' then
      update public.pachanga_team_player_invitations_v2 invitations set
        state = 'DECLINED', declined_by = actor_id, declined_at = clock_timestamp(),
        revision = invitations.revision + 1, server_sequence = next_sequence,
        updated_at = clock_timestamp()
      where invitations.id = invitation.id returning * into invitation;
    elsif action_name = 'team.invitation.revoke' then
      update public.pachanga_team_player_invitations_v2 invitations set
        state = 'REVOKED', revoked_at = clock_timestamp(),
        revision = invitations.revision + 1, server_sequence = next_sequence,
        updated_at = clock_timestamp()
      where invitations.id = invitation.id returning * into invitation;
    else
      update public.pachanga_team_player_invitations_v2 invitations set
        state = 'EXPIRED', revision = invitations.revision + 1,
        server_sequence = next_sequence, updated_at = clock_timestamp()
      where invitations.id = invitation.id returning * into invitation;
    end if;
  end if;

  insert into private.pachanga_team_player_invitation_revisions_v2(
    invitation_id, revision, state, actor_id, operation_id, snapshot, server_sequence
  ) values (
    invitation.id, invitation.revision, invitation.state, actor_id, operation_id,
    private.pachanga_team_player_invitation_snapshot_v2(invitation.id, false), invitation.server_sequence
  );

  team_state := private.pachanga_social_bump_team_v1(
    invitation.group_id, operation_id, actor_id, action_name,
    jsonb_build_object(
      'invitationId', invitation.id,
      'invitationMode', invitation.invite_mode,
      'invitationState', invitation.state,
      'useCount', invitation.use_count
    )
  );
  safe_response := private.pachanga_team_player_invitation_snapshot_v2(invitation.id, true)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', invitation.revision,
      'teamRevision', team_state.revision,
      'serverSequence', invitation.server_sequence,
      'confirmedAt', clock_timestamp()
    );
  perform private.pachanga_social_record_evidence_v1(
    operation_id, actor_id, action_name, 'team_player_invitation', invitation.id::text,
    request_hash, expected_revision, invitation.revision,
    jsonb_build_object(
      'groupId', invitation.group_id,
      'inviteMode', invitation.invite_mode,
      'state', invitation.state,
      'useCount', invitation.use_count
    ),
    safe_response, client_metadata, invitation.server_sequence
  );

  if action_name = 'team.invitation.accept' then
    for admin_user in
      select members.user_id from public.pachanga_group_members members
      where members.group_id = invitation.group_id
        and members.role in ('owner','admin') and members.user_id <> actor_id
    loop
      perform private.pachanga_notify_v1(
        admin_user.user_id,
        'team_player_invitation_accepted',
        'Invitación aceptada',
        'Un jugador se ha unido al equipo.',
        '/equipo/invitaciones?team=' || invitation.group_id::text,
        jsonb_build_object('groupId', invitation.group_id, 'invitationId', invitation.id),
        'social-team-invitation:' || operation_id::text || ':' || admin_user.user_id::text
      );
    end loop;
  elsif action_name = 'team.invitation.decline' then
    for admin_user in
      select members.user_id from public.pachanga_group_members members
      where members.group_id = invitation.group_id
        and members.role in ('owner','admin') and members.user_id <> actor_id
    loop
      perform private.pachanga_notify_v1(
        admin_user.user_id,
        'team_player_invitation_declined',
        'Invitación rechazada',
        'Un jugador ha rechazado la invitación.',
        '/equipo/invitaciones?team=' || invitation.group_id::text,
        jsonb_build_object('groupId', invitation.group_id, 'invitationId', invitation.id),
        'social-team-invitation:' || operation_id::text || ':' || admin_user.user_id::text
      );
    end loop;
  end if;

  response := safe_response;
  if action_name = 'team.invitation.create' then
    response := response || jsonb_build_object('shareToken', raw_token, 'tokenAlreadyIssued', false);
  end if;
  return response;
end;
$$;

revoke all on function private.pachanga_team_player_invitation_snapshot_v2(uuid,boolean) from public, anon, authenticated;
revoke all on function public.command_pachanga_team_player_invitation_v2(text,uuid,uuid,text,bigint,uuid,jsonb,jsonb) from public, anon;
grant execute on function public.command_pachanga_team_player_invitation_v2(text,uuid,uuid,text,bigint,uuid,jsonb,jsonb) to authenticated, service_role;

comment on column public.pachanga_team_player_invitations_v2.invite_mode is
  'INDIVIDUAL links admit one player. TEAM_LINK links are reusable until expiry, revocation or their server-side capacity.';
comment on table private.pachanga_team_player_invitation_uses_v3 is
  'Canonical, private acceptance ledger. A reusable Team link can add each authenticated profile at most once and only as player.';

create table if not exists public.pachanga_team_membership_requests_v1 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  state text not null default 'PENDING',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_social_team_sequence_v1'),
  responded_by uuid references auth.users(id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (state in ('PENDING','ACCEPTED','REJECTED','CANCELLED')),
  check (revision >= 1),
  check (server_sequence >= 1),
  check ((state = 'PENDING') = (responded_by is null and responded_at is null))
);

create unique index if not exists pachanga_team_membership_requests_v1_pending_idx
  on public.pachanga_team_membership_requests_v1(group_id, requested_by)
  where state = 'PENDING';
create index if not exists pachanga_team_membership_requests_v1_group_idx
  on public.pachanga_team_membership_requests_v1(group_id, state, server_sequence desc, id);
create index if not exists pachanga_team_membership_requests_v1_actor_idx
  on public.pachanga_team_membership_requests_v1(requested_by, server_sequence desc, id);

create table if not exists private.pachanga_team_membership_request_revisions_v1 (
  request_id uuid not null references public.pachanga_team_membership_requests_v1(id) on delete cascade,
  revision bigint not null,
  state text not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  operation_id uuid not null,
  snapshot jsonb not null,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (request_id, revision),
  unique (operation_id),
  check (state in ('PENDING','ACCEPTED','REJECTED','CANCELLED')),
  check (revision >= 1),
  check (server_sequence >= 1),
  check (jsonb_typeof(snapshot) = 'object')
);

alter table public.pachanga_team_membership_requests_v1 enable row level security;
revoke all on table public.pachanga_team_membership_requests_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_membership_request_revisions_v1 from public, anon, authenticated;
grant select on table public.pachanga_team_membership_requests_v1 to authenticated, service_role;
grant all on table public.pachanga_team_membership_requests_v1 to service_role;
grant all on table private.pachanga_team_membership_request_revisions_v1 to service_role;

drop policy if exists "Actors read Team membership requests v1"
  on public.pachanga_team_membership_requests_v1;
create policy "Actors read Team membership requests v1"
on public.pachanga_team_membership_requests_v1
for select to authenticated
using (
  requested_by = (select auth.uid())
  or public.is_pachanga_group_admin(group_id)
);

create or replace function private.pachanga_team_membership_request_snapshot_v1(
  target_request_id uuid,
  include_requester boolean default true
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kind', 'TeamMembershipRequestV1',
    'requestId', requests.id,
    'groupId', requests.group_id,
    'teamName', groups.name,
    'teamCode', groups.team_code,
    'requesterName', case when include_requester then coalesce(profiles.display_name, 'Jugador') else null end,
    'requesterAvatarRef', case when include_requester then profiles.avatar_ref else null end,
    'requesterPrimaryPosition', case when include_requester then profiles.primary_position else null end,
    'state', requests.state,
    'revision', requests.revision,
    'confirmedRevision', requests.revision,
    'serverSequence', requests.server_sequence,
    'createdAt', requests.created_at,
    'updatedAt', requests.updated_at
  ))
  from public.pachanga_team_membership_requests_v1 requests
  join public.pachanga_groups groups on groups.id = requests.group_id
  left join public.pachanga_social_player_profiles_v1 profiles on profiles.user_id = requests.requested_by
  where requests.id = target_request_id;
$$;

create or replace function public.lookup_pachanga_social_team_code_v1(target_team_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare code_value text := upper(trim(coalesce(target_team_code, '')));
declare enabled boolean;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501'; end if;
  select settings.social_team_home_v3f_enabled into enabled
  from private.pachanga_social_team_settings_v1 settings where settings.singleton;
  if not coalesce(enabled, false) or code_value !~ '^[A-Z0-9]{6,12}$' then return null; end if;
  return (
    select jsonb_build_object(
      'kind', 'SocialTeamCodeLookup',
      'groupId', groups.id,
      'name', groups.name,
      'teamCode', groups.team_code,
      'modality', groups.social_modality,
      'generalArea', groups.social_general_area,
      'memberCount', (select count(*) from public.pachanga_group_members members where members.group_id = groups.id),
      'teamRevision', states.revision,
      'joinPolicy', 'ADMIN_APPROVAL'
    )
    from public.pachanga_groups groups
    join public.pachanga_social_team_states_v1 states on states.group_id = groups.id
    left join private.pachanga_team_operational_states_v1 operational on operational.group_id = groups.id
    where groups.team_code = code_value
      and coalesce(operational.effective_status, 'ACTIVE') <> 'ARCHIVED'
  );
end;
$$;

create or replace function public.get_pachanga_team_membership_requests_v1(target_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then raise exception 'TEAM_ADMIN_REQUIRED' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(private.pachanga_team_membership_request_snapshot_v1(requests.id, true)
      order by requests.server_sequence desc, requests.id)
    from public.pachanga_team_membership_requests_v1 requests
    where requests.group_id = target_group_id
  ), '[]'::jsonb);
end;
$$;

create or replace function public.command_pachanga_team_membership_request_v1(
  action text,
  target_group_id uuid,
  target_request_id uuid,
  expected_revision bigint,
  operation_id uuid,
  payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare action_name text := lower(trim(coalesce(action, '')));
declare body jsonb := coalesce(payload, '{}'::jsonb);
declare request_row public.pachanga_team_membership_requests_v1%rowtype;
declare team_state public.pachanga_social_team_states_v1%rowtype;
declare existing_receipt private.pachanga_social_operation_receipts_v1%rowtype;
declare request_hash text;
declare aggregate_id text;
declare next_sequence bigint;
declare safe_response jsonb;
declare admin_user record;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'AUTHENTICATION_OPERATION_AND_REVISION_REQUIRED' using errcode = '42501';
  end if;
  if not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501'; end if;
  if action_name not in ('team.membership.request.create','team.membership.request.accept','team.membership.request.reject','team.membership.request.cancel') then
    raise exception 'UNSUPPORTED_TEAM_MEMBERSHIP_REQUEST_ACTION' using errcode = '22023';
  end if;
  if body <> '{}'::jsonb then raise exception 'TEAM_MEMBERSHIP_REQUEST_PAYLOAD_NOT_ALLOWED' using errcode = '22023'; end if;

  if action_name = 'team.membership.request.create' then
    if target_group_id is null or target_request_id is not null then raise exception 'TEAM_ID_REQUIRED' using errcode = '22023'; end if;
    aggregate_id := target_group_id::text;
  else
    if target_request_id is null then raise exception 'TEAM_MEMBERSHIP_REQUEST_ID_REQUIRED' using errcode = '22023'; end if;
    aggregate_id := target_request_id::text;
  end if;

  request_hash := private.pachanga_social_request_hash_v1(action_name, aggregate_id, expected_revision, body);
  perform pg_advisory_xact_lock(hashtextextended('social-operation:' || operation_id::text, 0));
  select * into existing_receipt from private.pachanga_social_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_team_membership_request_v1.operation_id;
  if found then
    if existing_receipt.actor_id <> actor_id or existing_receipt.action <> action_name
       or existing_receipt.request_hash <> request_hash then
      raise exception 'OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return existing_receipt.response;
  end if;

  if action_name = 'team.membership.request.create' then
    if not exists (select 1 from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = actor_id) then
      raise exception 'SOCIAL_PROFILE_REQUIRED' using errcode = '42501';
    end if;
    if exists (select 1 from public.pachanga_group_members members where members.group_id = target_group_id and members.user_id = actor_id) then
      raise exception 'ALREADY_TEAM_MEMBER' using errcode = 'PT409';
    end if;
    perform private.pachanga_assert_team_operational_scope_v1(target_group_id, 'TEAM_MEMBERSHIP_ADMINISTRATION');
    perform pg_advisory_xact_lock(hashtextextended('social-team:' || target_group_id::text, 0));
    select * into team_state from public.pachanga_social_team_states_v1 states
    where states.group_id = target_group_id for update;
    if not found then raise exception 'SOCIAL_TEAM_STATE_NOT_FOUND' using errcode = 'P0002'; end if;
    if team_state.revision <> expected_revision then raise exception 'STALE_TEAM_REVISION' using errcode = 'PT409'; end if;
    if exists (
      select 1 from public.pachanga_team_membership_requests_v1 requests
      where requests.group_id = target_group_id and requests.requested_by = actor_id and requests.state = 'PENDING'
    ) then raise exception 'TEAM_MEMBERSHIP_REQUEST_ALREADY_PENDING' using errcode = 'PT409'; end if;
    next_sequence := nextval('private.pachanga_social_team_sequence_v1');
    insert into public.pachanga_team_membership_requests_v1(
      group_id, requested_by, revision, server_sequence
    ) values (target_group_id, actor_id, 1, next_sequence)
    returning * into request_row;
  else
    perform pg_advisory_xact_lock(hashtextextended('social-team-membership-request:' || target_request_id::text, 0));
    select * into request_row from public.pachanga_team_membership_requests_v1 requests
    where requests.id = target_request_id for update;
    if not found then raise exception 'TEAM_MEMBERSHIP_REQUEST_NOT_FOUND' using errcode = 'P0002'; end if;
    if target_group_id is not null and target_group_id <> request_row.group_id then
      raise exception 'TEAM_MEMBERSHIP_REQUEST_TEAM_MISMATCH' using errcode = '42501';
    end if;
    if request_row.revision <> expected_revision then raise exception 'STALE_TEAM_MEMBERSHIP_REQUEST_REVISION' using errcode = 'PT409'; end if;
    if request_row.state <> 'PENDING' then raise exception 'TEAM_MEMBERSHIP_REQUEST_NOT_PENDING' using errcode = 'PT409'; end if;
    if action_name = 'team.membership.request.cancel' then
      if request_row.requested_by <> actor_id then raise exception 'TEAM_MEMBERSHIP_REQUEST_ACTOR_REQUIRED' using errcode = '42501'; end if;
    elsif not public.is_pachanga_group_admin(request_row.group_id) then
      raise exception 'TEAM_ADMIN_REQUIRED' using errcode = '42501';
    end if;
    if action_name = 'team.membership.request.accept' then
      perform private.pachanga_assert_team_operational_scope_v1(request_row.group_id, 'TEAM_MEMBERSHIP_ADMINISTRATION');
      if exists (
        select 1 from public.pachanga_group_members members
        where members.group_id = request_row.group_id and members.user_id = request_row.requested_by
      ) then raise exception 'ALREADY_TEAM_MEMBER' using errcode = 'PT409'; end if;
    end if;
    next_sequence := nextval('private.pachanga_social_team_sequence_v1');
    if action_name = 'team.membership.request.accept' then
      insert into public.pachanga_group_members(group_id, user_id, role, display_name)
      select request_row.group_id, request_row.requested_by, 'player', profiles.display_name
      from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = request_row.requested_by;
    end if;
    update public.pachanga_team_membership_requests_v1 requests set
      state = case action_name
        when 'team.membership.request.accept' then 'ACCEPTED'
        when 'team.membership.request.reject' then 'REJECTED'
        else 'CANCELLED'
      end,
      responded_by = actor_id,
      responded_at = clock_timestamp(),
      revision = requests.revision + 1,
      server_sequence = next_sequence,
      updated_at = clock_timestamp()
    where requests.id = request_row.id
    returning * into request_row;
  end if;

  insert into private.pachanga_team_membership_request_revisions_v1(
    request_id, revision, state, actor_id, operation_id, snapshot, server_sequence
  ) values (
    request_row.id, request_row.revision, request_row.state, actor_id, operation_id,
    private.pachanga_team_membership_request_snapshot_v1(request_row.id, false), request_row.server_sequence
  );

  team_state := private.pachanga_social_bump_team_v1(
    request_row.group_id, operation_id, actor_id, action_name,
    jsonb_build_object('requestId', request_row.id, 'requestState', request_row.state)
  );
  safe_response := private.pachanga_team_membership_request_snapshot_v1(request_row.id, true)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', request_row.revision,
      'teamRevision', team_state.revision,
      'serverSequence', request_row.server_sequence,
      'confirmedAt', clock_timestamp()
    );
  perform private.pachanga_social_record_evidence_v1(
    operation_id, actor_id, action_name, 'team_membership_request', request_row.id::text,
    request_hash, expected_revision, request_row.revision,
    jsonb_build_object('groupId', request_row.group_id, 'state', request_row.state),
    safe_response, client_metadata, request_row.server_sequence
  );

  if action_name = 'team.membership.request.create' then
    for admin_user in
      select members.user_id from public.pachanga_group_members members
      where members.group_id = request_row.group_id and members.role in ('owner','admin')
    loop
      perform private.pachanga_notify_v1(
        admin_user.user_id,
        'team_player_invitation_requested',
        'Solicitud para entrar al equipo',
        'Un jugador quiere unirse mediante el código del equipo.',
        '/equipo/invitaciones?team=' || request_row.group_id::text,
        jsonb_build_object('groupId', request_row.group_id, 'requestId', request_row.id),
        'team-membership-request:' || request_row.id::text || ':' || admin_user.user_id::text
      );
    end loop;
  elsif action_name in ('team.membership.request.accept','team.membership.request.reject') then
    perform private.pachanga_notify_v1(
      request_row.requested_by,
      case when action_name = 'team.membership.request.accept'
        then 'team_membership_request_accepted'
        else 'team_membership_request_rejected'
      end,
      case when action_name = 'team.membership.request.accept' then 'Solicitud aceptada' else 'Solicitud rechazada' end,
      case when action_name = 'team.membership.request.accept'
        then 'Ya formas parte del equipo como jugador.'
        else 'El equipo no ha aceptado tu solicitud.'
      end,
      case when action_name = 'team.membership.request.accept'
        then '/equipo?team=' || request_row.group_id::text
        else '/?social=join'
      end,
      jsonb_build_object('groupId', request_row.group_id, 'requestId', request_row.id),
      'team-membership-request-response:' || request_row.id::text || ':' || request_row.state
    );
  end if;

  return safe_response;
end;
$$;

create or replace function private.pachanga_social_inbox_domain_v1(target_kind text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select lower(trim(coalesce(target_kind, ''))) as kind
  )
  select case
    when kind in (
      'match_attendance_joined',
      'match_attendance_cancelled',
      'player_availability_unavailable',
      'player_availability_available',
      'match_access_revoked',
      'match_guest_left'
    ) then 'MATCH'
    when kind like 'team_challenge_%'
      or kind like 'external_result_%' then 'CHALLENGE'
    when kind = 'match_invitation'
      or kind like 'match_invitation_%'
      or kind = 'open_match_request'
      or kind like 'open_match_request_%' then 'MARKET'
    when kind in (
      'group_member_joined',
      'group_member_left',
      'group_member_removed',
      'team_membership_request_accepted',
      'team_membership_request_rejected',
      'team_player_invitation_accepted',
      'team_player_invitation_declined',
      'team_player_invitation_requested',
      'team_shield_updated'
    ) then 'TEAM'
    else null
  end
  from normalized;
$$;

revoke all on function private.pachanga_team_membership_request_snapshot_v1(uuid,boolean) from public, anon, authenticated;
revoke all on function public.lookup_pachanga_team_player_invitation_v2(text) from public, anon;
grant execute on function public.lookup_pachanga_team_player_invitation_v2(text) to authenticated, service_role;
revoke all on function public.get_pachanga_team_membership_requests_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_team_membership_requests_v1(uuid) to authenticated, service_role;
revoke all on function public.command_pachanga_team_membership_request_v1(text,uuid,uuid,bigint,uuid,jsonb,jsonb) from public, anon;
grant execute on function public.command_pachanga_team_membership_request_v1(text,uuid,uuid,bigint,uuid,jsonb,jsonb) to authenticated, service_role;

comment on table public.pachanga_team_membership_requests_v1 is
  'Server-authoritative requests created after finding a Team by its short code. Only an owner/admin acceptance creates player membership.';
