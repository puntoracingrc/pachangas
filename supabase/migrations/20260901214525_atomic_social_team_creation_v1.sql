-- Official UI V3F: atomic Team creation over the existing canonical Team authority.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_groups
  add column if not exists social_modality text,
  add column if not exists social_general_area text not null default '',
  add column if not exists social_target_player_count smallint not null default 14;

alter table public.pachanga_groups
  drop constraint if exists pachanga_groups_social_modality_check,
  drop constraint if exists pachanga_groups_social_general_area_check,
  drop constraint if exists pachanga_groups_social_target_player_count_check,
  add constraint pachanga_groups_social_modality_check
    check (social_modality is null or social_modality in ('sala','futbol7','futbol11')),
  add constraint pachanga_groups_social_general_area_check
    check (char_length(social_general_area) <= 120),
  add constraint pachanga_groups_social_target_player_count_check
    check (social_target_player_count between 5 and 60);

create table if not exists public.pachanga_social_team_states_v1 (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_social_team_sequence_v1'),
  last_operation_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1),
  check (server_sequence >= 1)
);

create table if not exists private.pachanga_social_team_state_revisions_v1 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  revision bigint not null,
  reason text not null,
  snapshot jsonb not null,
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (group_id, revision),
  unique (operation_id, group_id),
  check (revision >= 1),
  check (server_sequence >= 1),
  check (jsonb_typeof(snapshot) = 'object')
);

create unique index if not exists pachanga_social_team_states_sequence_idx
  on public.pachanga_social_team_states_v1(server_sequence, group_id);
create index if not exists pachanga_social_team_revisions_group_idx
  on private.pachanga_social_team_state_revisions_v1(group_id, revision desc, id);
create index if not exists pachanga_groups_social_lookup_idx
  on public.pachanga_groups(social_modality, social_general_area, id)
  where social_modality is not null;

alter table public.pachanga_social_team_states_v1 enable row level security;
revoke all on table public.pachanga_social_team_states_v1 from public, anon, authenticated;
revoke all on table private.pachanga_social_team_state_revisions_v1 from public, anon, authenticated;
grant all on table public.pachanga_social_team_states_v1 to service_role;
grant all on table private.pachanga_social_team_state_revisions_v1 to service_role;

create or replace function private.pachanga_social_team_snapshot_v1(
  target_group_id uuid,
  target_actor_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'kind', 'SocialTeam',
    'groupId', groups.id,
    'name', groups.name,
    'teamCode', groups.team_code,
    'modality', groups.social_modality,
    'generalArea', groups.social_general_area,
    'targetPlayerCount', groups.social_target_player_count,
    'role', memberships.role,
    'memberCount', (
      select count(*) from public.pachanga_group_members roster
      where roster.group_id = groups.id
    ),
    'revision', states.revision,
    'confirmedRevision', states.revision,
    'serverSequence', states.server_sequence,
    'operationalStatus', coalesce(operational.effective_status, 'ACTIVE'),
    'operationalRevision', coalesce(operational.current_revision, 0),
    'shield', coalesce(shields.config, private.pachanga_default_team_shield_config_v1(groups.name)),
    'shieldRevision', coalesce(shields.revision, 0),
    'createdAt', groups.created_at,
    'updatedAt', greatest(groups.updated_at, states.updated_at)
  )
  from public.pachanga_groups groups
  join public.pachanga_group_members memberships
    on memberships.group_id = groups.id and memberships.user_id = target_actor_id
  join public.pachanga_social_team_states_v1 states on states.group_id = groups.id
  left join private.pachanga_team_operational_states_v1 operational on operational.group_id = groups.id
  left join public.pachanga_team_shield_public shields on shields.group_id = groups.id
  where groups.id = target_group_id;
$$;

create or replace function private.pachanga_social_team_membership_revision_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare target_group_id uuid := coalesce(new.group_id, old.group_id);
declare target_user_id uuid := coalesce(new.user_id, old.user_id);
declare next_revision bigint;
declare next_sequence bigint;
declare generated_operation_id uuid := gen_random_uuid();
declare reason_value text := case
  when tg_op = 'INSERT' then 'membership.added'
  when tg_op = 'DELETE' then 'membership.removed'
  else 'membership.role_changed'
end;
begin
  if tg_op = 'UPDATE' and new.role is not distinct from old.role then return new; end if;

  next_sequence := nextval('private.pachanga_social_team_sequence_v1');
  update public.pachanga_social_team_states_v1 states set
    revision = states.revision + 1,
    server_sequence = next_sequence,
    last_operation_id = generated_operation_id,
    updated_at = clock_timestamp()
  where states.group_id = target_group_id
  returning states.revision into next_revision;

  if next_revision is not null then
    insert into private.pachanga_social_team_state_revisions_v1(
      group_id, revision, reason, snapshot, operation_id, actor_id, server_sequence
    ) values (
      target_group_id, next_revision, reason_value,
      jsonb_build_object(
        'groupId', target_group_id,
        'userId', target_user_id,
        'role', case when tg_op = 'DELETE' then old.role else new.role end,
        'revision', next_revision,
        'serverSequence', next_sequence
      ), generated_operation_id, (select auth.uid()), next_sequence
    );
    insert into public.pachanga_social_invalidations_v1(
      entity_type, entity_id, revision, audience_group_id, server_sequence
    ) values ('roster', target_group_id::text, next_revision, target_group_id, next_sequence);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists pachanga_social_team_membership_revision_v1
  on public.pachanga_group_members;
create trigger pachanga_social_team_membership_revision_v1
after insert or update of role or delete on public.pachanga_group_members
for each row execute function private.pachanga_social_team_membership_revision_v1();

create or replace function public.command_pachanga_social_team_v1(
  action text,
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
declare settings private.pachanga_social_team_settings_v1%rowtype;
declare existing_receipt private.pachanga_social_operation_receipts_v1%rowtype;
declare group_id uuid := gen_random_uuid();
declare team_name text;
declare team_code text;
declare modality text;
declare general_area text;
declare target_players smallint;
declare shield_config jsonb;
declare requested_shape text;
declare request_hash text;
declare response jsonb;
declare team_revision bigint;
declare team_sequence bigint;
declare shield_sequence bigint;
declare attempts integer := 0;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'AUTHENTICATION_OPERATION_AND_REVISION_REQUIRED' using errcode = '42501';
  end if;
  if action_name <> 'team.create' then raise exception 'UNSUPPORTED_TEAM_ACTION' using errcode = '22023'; end if;
  if expected_revision <> 0 then raise exception 'STALE_TEAM_REVISION' using errcode = 'PT409'; end if;
  if not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501'; end if;
  if jsonb_typeof(body) <> 'object' or body - array['name','modality','generalArea','targetPlayerCount','shieldKey']::text[] <> '{}'::jsonb then
    raise exception 'TEAM_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
  end if;

  select * into settings from private.pachanga_social_team_settings_v1 where singleton;
  if not settings.social_profile_foundation_enabled
     or not settings.social_team_creation_enabled then
    raise exception 'SOCIAL_TEAM_CREATION_DISABLED' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.pachanga_social_player_profiles_v1 profiles
    where profiles.user_id = actor_id
  ) then raise exception 'SOCIAL_PROFILE_REQUIRED' using errcode = '42501'; end if;

  team_name := left(trim(coalesce(body ->> 'name','')), 80);
  modality := trim(coalesce(body ->> 'modality',''));
  general_area := left(trim(coalesce(body ->> 'generalArea','')), 120);
  begin target_players := coalesce((body ->> 'targetPlayerCount')::smallint, 14);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'INVALID_TARGET_PLAYER_COUNT' using errcode = '22023';
  end;
  if char_length(team_name) < 2 then raise exception 'TEAM_NAME_REQUIRED' using errcode = '22023'; end if;
  if modality not in ('sala','futbol7','futbol11') then raise exception 'INVALID_TEAM_MODALITY' using errcode = '22023'; end if;
  if general_area = '' then raise exception 'TEAM_GENERAL_AREA_REQUIRED' using errcode = '22023'; end if;
  if target_players not between 5 and 60 then raise exception 'INVALID_TARGET_PLAYER_COUNT' using errcode = '22023'; end if;

  request_hash := private.pachanga_social_request_hash_v1(action_name, actor_id::text, expected_revision, body);
  perform pg_advisory_xact_lock(hashtextextended('social-operation:' || operation_id::text, 0));
  select * into existing_receipt from private.pachanga_social_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_social_team_v1.operation_id;
  if found then
    if existing_receipt.actor_id <> actor_id or existing_receipt.action <> action_name
       or existing_receipt.request_hash <> request_hash then
      raise exception 'OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return existing_receipt.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('social-team-create:' || actor_id::text, 0));
  if exists (
    select 1 from private.pachanga_social_operation_receipts_v1 receipts
    where receipts.actor_id = actor_id and receipts.action = 'team.create'
      and receipts.created_at > clock_timestamp() - interval '30 seconds'
  ) then raise exception 'TEAM_CREATION_RECENTLY_CONFIRMED' using errcode = 'PT409'; end if;
  if (select count(*) from public.pachanga_groups groups where groups.owner_id = actor_id) >= 5 then
    raise exception 'TEAM_OWNER_LIMIT_REACHED' using errcode = '42501';
  end if;

  loop
    attempts := attempts + 1;
    team_code := public.new_pachanga_team_code();
    exit when not exists (select 1 from public.pachanga_groups groups where groups.team_code = team_code);
    if attempts >= 8 then raise exception 'TEAM_CODE_GENERATION_FAILED' using errcode = 'PT409'; end if;
  end loop;

  insert into public.pachanga_groups(
    id, owner_id, name, team_code, social_modality, social_general_area,
    social_target_player_count, payload
  ) values (
    group_id, actor_id, team_name, team_code, modality, general_area,
    target_players,
    jsonb_build_object(
      'activeMatchId', '', 'matches', '[]'::jsonb, 'players', '[]'::jsonb, 'venues', '[]'::jsonb,
      'siteSettings', jsonb_build_object(
        'brand', team_name,
        'title', 'Tu equipo ya está preparado.',
        'subtitle', 'Crea el primer partido e invita a tu plantilla.'
      )
    )
  );

  team_sequence := nextval('private.pachanga_social_team_sequence_v1');
  insert into public.pachanga_social_team_states_v1(
    group_id, revision, server_sequence, last_operation_id
  ) values (group_id, 1, team_sequence, operation_id);
  insert into private.pachanga_social_team_state_revisions_v1(
    group_id, revision, reason, snapshot, operation_id, actor_id, server_sequence
  ) values (
    group_id, 1, 'team.created',
    jsonb_build_object('groupId', group_id, 'name', team_name, 'teamCode', team_code,
      'modality', modality, 'generalArea', general_area, 'targetPlayerCount', target_players,
      'revision', 1, 'serverSequence', team_sequence),
    operation_id, actor_id, team_sequence
  );

  insert into public.pachanga_group_members(group_id, user_id, role, display_name)
  select group_id, actor_id, 'owner', profiles.display_name
  from public.pachanga_social_player_profiles_v1 profiles where profiles.user_id = actor_id;

  requested_shape := nullif(trim(body ->> 'shieldKey'), '');
  shield_config := private.pachanga_default_team_shield_config_v1(team_name);
  if requested_shape is not null then
    shield_config := jsonb_set(shield_config, '{shapeKey}', to_jsonb(requested_shape));
  end if;
  shield_config := private.pachanga_validate_team_shield_config_v1(group_id, shield_config);
  shield_sequence := nextval('public.pachanga_team_crest_sequence');
  insert into public.pachanga_team_shield_state(group_id, revision, server_sequence)
    values (group_id, 1, shield_sequence);
  insert into public.pachanga_team_shield_versions(
    group_id, version_number, config, operation_id, saved_by, server_sequence
  ) values (group_id, 1, shield_config, operation_id, actor_id, shield_sequence);
  insert into public.pachanga_team_shield_loadouts(
    group_id, revision, config, updated_by, server_sequence
  ) values (group_id, 1, shield_config, actor_id, shield_sequence);
  perform private.pachanga_upsert_team_shield_public_v1(group_id, 1, shield_sequence, shield_config);
  insert into public.pachanga_team_shield_events(
    operation_id, event_type, group_id, actor_user_id,
    confirmed_revision, server_sequence, payload
  ) values (
    operation_id, 'team_shield_saved', group_id, actor_id, 1, shield_sequence,
    jsonb_build_object('version', 1, 'config', shield_config, 'source', 'social_team_creation_v1')
  );

  select states.revision, states.server_sequence into team_revision, team_sequence
  from public.pachanga_social_team_states_v1 states where states.group_id = group_id;
  response := private.pachanga_social_team_snapshot_v1(group_id, actor_id)
    || jsonb_build_object(
      'operationId', operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', team_revision,
      'serverSequence', team_sequence,
      'confirmedAt', clock_timestamp(),
      'created', true
    );
  perform private.pachanga_social_record_evidence_v1(
    operation_id, actor_id, action_name, 'social_team', group_id::text,
    request_hash, expected_revision, team_revision,
    jsonb_build_object('groupId', group_id, 'ownerRole', 'owner', 'shieldRevision', 1),
    response, client_metadata, team_sequence
  );
  insert into public.pachanga_social_invalidations_v1(
    entity_type, entity_id, revision, audience_user_id, server_sequence
  ) values ('team_selection', group_id::text, team_revision, actor_id, team_sequence);
  return response;
end;
$$;

revoke all on function private.pachanga_social_team_snapshot_v1(uuid,uuid) from public, anon, authenticated;
revoke all on function private.pachanga_social_team_membership_revision_v1() from public, anon, authenticated;
revoke all on function public.command_pachanga_social_team_v1(text,bigint,uuid,jsonb,jsonb) from public, anon;
grant execute on function public.command_pachanga_social_team_v1(text,bigint,uuid,jsonb,jsonb) to authenticated, service_role;

comment on table public.pachanga_social_team_states_v1 is
  'V3F social revision projection. pachanga_groups and pachanga_group_members remain Team and membership authority.';
