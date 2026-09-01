-- Official UI V3F: single-use, expiring, revocable player invitations.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table if not exists public.pachanga_team_player_invitations_v2 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete restrict,
  state text not null default 'ACTIVE',
  max_uses smallint not null default 1,
  use_count smallint not null default 0,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_social_team_sequence_v1'),
  expires_at timestamptz not null,
  accepted_by uuid references auth.users(id) on delete set null,
  declined_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  declined_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (state in ('ACTIVE','USED','EXPIRED','REVOKED','DECLINED')),
  check (max_uses = 1),
  check (use_count between 0 and max_uses),
  check (revision >= 1),
  check (server_sequence >= 1),
  check (expires_at > created_at),
  check ((state = 'USED') = (accepted_by is not null and accepted_at is not null and use_count = 1)),
  check ((state = 'DECLINED') = (declined_by is not null and declined_at is not null)),
  check ((state = 'REVOKED') = (revoked_at is not null))
);

create table if not exists private.pachanga_team_player_invitation_secrets_v2 (
  invitation_id uuid primary key references public.pachanga_team_player_invitations_v2(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default clock_timestamp(),
  check (char_length(token_hash) = 64)
);

create table if not exists private.pachanga_team_player_invitation_revisions_v2 (
  id uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.pachanga_team_player_invitations_v2(id) on delete cascade,
  revision bigint not null,
  state text not null,
  actor_id uuid references auth.users(id) on delete set null,
  operation_id uuid not null,
  snapshot jsonb not null,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (invitation_id, revision),
  unique (operation_id, invitation_id),
  check (revision >= 1),
  check (state in ('ACTIVE','USED','EXPIRED','REVOKED','DECLINED')),
  check (jsonb_typeof(snapshot) = 'object'),
  check (server_sequence >= 1)
);

create index if not exists pachanga_team_player_invitations_v2_group_idx
  on public.pachanga_team_player_invitations_v2(group_id, state, server_sequence desc, id);
create index if not exists pachanga_team_player_invitations_v2_expiry_idx
  on public.pachanga_team_player_invitations_v2(expires_at, id)
  where state = 'ACTIVE';
create unique index if not exists pachanga_team_player_invitations_v2_sequence_idx
  on public.pachanga_team_player_invitations_v2(server_sequence, id);
create index if not exists pachanga_team_player_invitation_revisions_v2_idx
  on private.pachanga_team_player_invitation_revisions_v2(invitation_id, revision desc, id);

alter table public.pachanga_team_player_invitations_v2 enable row level security;
revoke all on table public.pachanga_team_player_invitations_v2 from public, anon, authenticated;
revoke all on table private.pachanga_team_player_invitation_secrets_v2 from public, anon, authenticated;
revoke all on table private.pachanga_team_player_invitation_revisions_v2 from public, anon, authenticated;
grant select on table public.pachanga_team_player_invitations_v2 to authenticated, service_role;
grant all on table private.pachanga_team_player_invitation_secrets_v2 to service_role;
grant all on table private.pachanga_team_player_invitation_revisions_v2 to service_role;
grant all on table public.pachanga_team_player_invitations_v2 to service_role;

drop policy if exists "Admins read Team player invitations v2"
  on public.pachanga_team_player_invitations_v2;
create policy "Admins read Team player invitations v2"
on public.pachanga_team_player_invitations_v2
for select to authenticated
using (
  public.is_pachanga_group_admin(group_id)
  or accepted_by = (select auth.uid())
  or declined_by = (select auth.uid())
);

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

create or replace function private.pachanga_social_bump_team_v1(
  target_group_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_reason text,
  target_snapshot jsonb
)
returns public.pachanga_social_team_states_v1
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare saved public.pachanga_social_team_states_v1%rowtype;
declare next_sequence bigint := nextval('private.pachanga_social_team_sequence_v1');
begin
  update public.pachanga_social_team_states_v1 states set
    revision = states.revision + 1,
    server_sequence = next_sequence,
    last_operation_id = target_operation_id,
    updated_at = clock_timestamp()
  where states.group_id = target_group_id
  returning * into saved;
  if not found then raise exception 'SOCIAL_TEAM_STATE_NOT_FOUND' using errcode = 'P0002'; end if;

  insert into private.pachanga_social_team_state_revisions_v1(
    group_id, revision, reason, snapshot, operation_id, actor_id, server_sequence
  ) values (
    target_group_id, saved.revision, target_reason,
    coalesce(target_snapshot, '{}'::jsonb) || jsonb_build_object(
      'groupId', target_group_id, 'revision', saved.revision, 'serverSequence', next_sequence
    ), target_operation_id, target_actor_id, next_sequence
  );
  insert into public.pachanga_social_invalidations_v1(
    entity_type, entity_id, revision, audience_group_id, server_sequence
  ) values ('invitation', target_group_id::text, saved.revision, target_group_id, next_sequence);
  return saved;
end;
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
  select secrets.invitation_id into invitation_id
  from private.pachanga_team_player_invitation_secrets_v2 secrets
  where secrets.token_hash = token_hash;
  if invitation_id is null then return null; end if;
  return private.pachanga_team_player_invitation_snapshot_v2(invitation_id, true);
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
       or body - array['expiresInHours']::text[] <> '{}'::jsonb then
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

    invitation_id := gen_random_uuid();
    raw_token := 'piq_' || encode(extensions.gen_random_bytes(32), 'hex');
    token_hash := encode(extensions.digest(convert_to(raw_token, 'UTF8'), 'sha256'), 'hex');
    next_sequence := nextval('private.pachanga_social_team_sequence_v1');
    insert into public.pachanga_team_player_invitations_v2(
      id, group_id, created_by, expires_at, revision, server_sequence
    ) values (
      invitation_id, target_group_id, actor_id,
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
    if invitation.revision <> expected_revision then raise exception 'STALE_INVITATION_REVISION' using errcode = 'PT409'; end if;

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
    perform private.pachanga_assert_team_operational_scope_v1(invitation.group_id, 'TEAM_MEMBERSHIP_ADMINISTRATION');
    next_sequence := nextval('private.pachanga_social_team_sequence_v1');

    if action_name = 'team.invitation.accept' then
      if not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501'; end if;
      if not exists (select 1 from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = actor_id) then
        raise exception 'SOCIAL_PROFILE_REQUIRED' using errcode = '42501';
      end if;
      if exists (select 1 from public.pachanga_group_members members where members.group_id = invitation.group_id and members.user_id = actor_id) then
        raise exception 'ALREADY_TEAM_MEMBER' using errcode = 'PT409';
      end if;
      insert into public.pachanga_group_members(group_id, user_id, role, display_name)
      select invitation.group_id, actor_id, 'player', profiles.display_name
      from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = actor_id;
      update public.pachanga_team_player_invitations_v2 invitations set
        state = 'USED', use_count = 1, accepted_by = actor_id,
        accepted_at = clock_timestamp(), revision = invitations.revision + 1,
        server_sequence = next_sequence, updated_at = clock_timestamp()
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
    jsonb_build_object('invitationId', invitation.id, 'invitationState', invitation.state)
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
    jsonb_build_object('groupId', invitation.group_id, 'state', invitation.state),
    safe_response, client_metadata, invitation.server_sequence
  );

  if action_name in ('team.invitation.accept','team.invitation.decline') then
    for admin_user in
      select members.user_id from public.pachanga_group_members members
      where members.group_id = invitation.group_id
        and members.role in ('owner','admin') and members.user_id <> actor_id
    loop
      perform private.pachanga_notify_v1(
        admin_user.user_id,
        case when action_name = 'team.invitation.accept' then 'team_player_invitation_accepted' else 'team_player_invitation_declined' end,
        case when action_name = 'team.invitation.accept' then 'Invitación aceptada' else 'Invitación rechazada' end,
        case when action_name = 'team.invitation.accept' then 'Un jugador se ha unido al equipo.' else 'Un jugador ha rechazado la invitación.' end,
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
revoke all on function private.pachanga_social_bump_team_v1(uuid,uuid,uuid,text,jsonb) from public, anon, authenticated;
revoke all on function public.lookup_pachanga_team_player_invitation_v2(text) from public, anon;
grant execute on function public.lookup_pachanga_team_player_invitation_v2(text) to authenticated, service_role;
revoke all on function public.command_pachanga_team_player_invitation_v2(text,uuid,uuid,text,bigint,uuid,jsonb,jsonb) from public, anon;
grant execute on function public.command_pachanga_team_player_invitation_v2(text,uuid,uuid,text,bigint,uuid,jsonb,jsonb) to authenticated, service_role;

comment on table private.pachanga_team_player_invitation_secrets_v2 is
  'Only SHA-256 invitation token hashes. Raw player invitation tokens are returned once and never persisted.';
