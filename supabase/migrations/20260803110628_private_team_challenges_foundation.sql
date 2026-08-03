-- Pachangas IQ social foundation: private challenges and private known-opponent agenda.
-- This migration is deliberately isolated from player and team rating calculations.

create sequence if not exists public.pachanga_team_social_sequence;
revoke all on sequence public.pachanga_team_social_sequence from public, anon, authenticated;
grant usage, select on sequence public.pachanga_team_social_sequence to service_role;

create table if not exists public.pachanga_team_social_state (
  group_id uuid primary key references public.pachanga_groups(id) on delete cascade,
  revision bigint not null default 0,
  server_sequence bigint not null default nextval('public.pachanga_team_social_sequence'),
  updated_at timestamptz not null default now(),
  check (revision >= 0)
);

create index if not exists pachanga_team_social_state_sequence_idx
  on public.pachanga_team_social_state(server_sequence);

create table if not exists public.pachanga_team_challenges (
  id uuid primary key default gen_random_uuid(),
  sender_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  receiver_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  status text not null default 'proposed',
  revision bigint not null default 1,
  proposal_number integer not null default 1,
  scheduled_at timestamptz not null,
  modality text not null,
  field_name text not null,
  field_address text not null,
  field_place_id text,
  field_maps_url text,
  message text,
  last_proposed_by_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  accepted_at timestamptz,
  rejected_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (sender_group_id <> receiver_group_id),
  check (last_proposed_by_group_id in (sender_group_id, receiver_group_id)),
  check (status in ('proposed', 'changes_proposed', 'accepted', 'rejected', 'cancelled')),
  check (modality in ('sala', 'futbol7', 'futbol11')),
  check (revision >= 1),
  check (proposal_number >= 1),
  check (char_length(field_name) between 1 and 160),
  check (char_length(field_address) between 1 and 300),
  check (field_place_id is null or char_length(field_place_id) <= 300),
  check (field_maps_url is null or char_length(field_maps_url) <= 800),
  check (message is null or char_length(message) <= 1200)
);

create index if not exists pachanga_team_challenges_sender_updated_idx
  on public.pachanga_team_challenges(sender_group_id, updated_at desc, id desc);
create index if not exists pachanga_team_challenges_receiver_updated_idx
  on public.pachanga_team_challenges(receiver_group_id, updated_at desc, id desc);
create index if not exists pachanga_team_challenges_pending_idx
  on public.pachanga_team_challenges(status, scheduled_at, id)
  where status in ('proposed', 'changes_proposed', 'accepted');

create table if not exists public.pachanga_team_challenge_events (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.pachanga_team_challenges(id) on delete restrict,
  operation_id uuid not null unique,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  actor_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  event_type text not null,
  challenge_revision bigint not null,
  snapshot jsonb not null,
  server_sequence bigint not null default nextval('public.pachanga_team_social_sequence'),
  created_at timestamptz not null default now(),
  check (event_type in ('created', 'changes_proposed', 'accepted', 'rejected', 'cancelled')),
  check (challenge_revision >= 1)
);

create unique index if not exists pachanga_team_challenge_events_sequence_idx
  on public.pachanga_team_challenge_events(server_sequence);
create index if not exists pachanga_team_challenge_events_challenge_idx
  on public.pachanga_team_challenge_events(challenge_id, challenge_revision desc, server_sequence desc);

create table if not exists public.pachanga_team_social_operation_receipts (
  operation_id uuid primary key,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  operation_type text not null,
  expected_revision bigint,
  result_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (result_revision >= 0),
  check (jsonb_typeof(client_metadata) = 'object')
);

create index if not exists pachanga_team_social_receipts_group_created_idx
  on public.pachanga_team_social_operation_receipts(group_id, created_at desc, operation_id);

create table if not exists public.pachanga_known_opponents (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  opponent_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  matches_played integer not null,
  first_encounter_at timestamptz not null,
  last_encounter_at timestamptz not null,
  last_match_id text not null,
  revision bigint not null default 1,
  updated_at timestamptz not null default now(),
  primary key (group_id, opponent_group_id),
  check (group_id <> opponent_group_id),
  check (matches_played >= 1),
  check (revision >= 1)
);

create index if not exists pachanga_known_opponents_last_idx
  on public.pachanga_known_opponents(group_id, last_encounter_at desc, opponent_group_id);

alter table public.pachanga_team_social_state enable row level security;
alter table public.pachanga_team_challenges enable row level security;
alter table public.pachanga_team_challenge_events enable row level security;
alter table public.pachanga_team_social_operation_receipts enable row level security;
alter table public.pachanga_known_opponents enable row level security;

revoke all on table public.pachanga_team_social_state from public, anon, authenticated;
revoke all on table public.pachanga_team_challenges from public, anon, authenticated;
revoke all on table public.pachanga_team_challenge_events from public, anon, authenticated;
revoke all on table public.pachanga_team_social_operation_receipts from public, anon, authenticated;
revoke all on table public.pachanga_known_opponents from public, anon, authenticated;

grant select on table public.pachanga_team_social_state to authenticated;
grant all on table public.pachanga_team_social_state to service_role;
grant all on table public.pachanga_team_challenges to service_role;
grant all on table public.pachanga_team_challenge_events to service_role;
grant all on table public.pachanga_team_social_operation_receipts to service_role;
grant all on table public.pachanga_known_opponents to service_role;

drop policy if exists "Members can observe social revisions" on public.pachanga_team_social_state;
create policy "Members can observe social revisions"
on public.pachanga_team_social_state
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_member(group_id)
);

create or replace function public.pachanga_initialize_team_social_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_team_social_state(group_id)
  values (new.id)
  on conflict (group_id) do nothing;
  return new;
end;
$$;

drop trigger if exists initialize_pachanga_team_social_state on public.pachanga_groups;
create trigger initialize_pachanga_team_social_state
after insert on public.pachanga_groups
for each row execute function public.pachanga_initialize_team_social_state();

insert into public.pachanga_team_social_state(group_id)
select groups.id
from public.pachanga_groups groups
on conflict (group_id) do nothing;

create or replace function public.pachanga_team_social_operation_replay(
  target_group_id uuid,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_operation_type text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  stored_actor uuid;
  stored_group uuid;
  stored_operation_type text;
  stored_response jsonb;
begin
  select receipts.actor_user_id, receipts.group_id, receipts.operation_type, receipts.response
  into stored_actor, stored_group, stored_operation_type, stored_response
  from public.pachanga_team_social_operation_receipts receipts
  where receipts.operation_id = target_operation_id;

  if found and (
    stored_actor is distinct from target_actor_user_id
    or stored_group is distinct from target_group_id
    or stored_operation_type is distinct from target_operation_type
  ) then
    raise exception 'Operation id was already used for another action';
  end if;
  return stored_response;
end;
$$;

create or replace function public.pachanga_team_challenge_snapshot(
  target_challenge_id uuid,
  perspective_group_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', challenges.id,
    'direction', case when challenges.sender_group_id = perspective_group_id then 'outgoing' else 'incoming' end,
    'status', challenges.status,
    'revision', challenges.revision,
    'proposalNumber', challenges.proposal_number,
    'scheduledAt', challenges.scheduled_at,
    'modality', challenges.modality,
    'field', jsonb_build_object(
      'name', challenges.field_name,
      'address', challenges.field_address,
      'placeId', challenges.field_place_id,
      'mapsUrl', challenges.field_maps_url
    ),
    'message', challenges.message,
    'lastProposedBy', case when challenges.last_proposed_by_group_id = perspective_group_id then 'own' else 'opponent' end,
    'opponent', jsonb_build_object(
      'groupId', opponents.id,
      'name', opponents.name,
      'teamCode', opponents.team_code
    ),
    'acceptedAt', challenges.accepted_at,
    'rejectedAt', challenges.rejected_at,
    'cancelledAt', challenges.cancelled_at,
    'createdAt', challenges.created_at,
    'updatedAt', challenges.updated_at
  )
  from public.pachanga_team_challenges challenges
  join public.pachanga_groups opponents
    on opponents.id = case
      when challenges.sender_group_id = perspective_group_id then challenges.receiver_group_id
      else challenges.sender_group_id
    end
  where challenges.id = target_challenge_id
    and perspective_group_id in (challenges.sender_group_id, challenges.receiver_group_id);
$$;

create or replace function public.get_pachanga_team_social_snapshot(target_group_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  current_state public.pachanga_team_social_state%rowtype;
  challenge_items jsonb;
  opponent_items jsonb;
  current_group public.pachanga_groups%rowtype;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Group membership required';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;

  select * into current_state
  from public.pachanga_team_social_state states
  where states.group_id = target_group_id;

  select coalesce(jsonb_agg(
    public.pachanga_team_challenge_snapshot(challenges.id, target_group_id)
    order by
      case when challenges.status in ('proposed', 'changes_proposed') then 0
           when challenges.status = 'accepted' then 1 else 2 end,
      challenges.updated_at desc,
      challenges.id desc
  ), '[]'::jsonb)
  into challenge_items
  from public.pachanga_team_challenges challenges
  where target_group_id in (challenges.sender_group_id, challenges.receiver_group_id);

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'groupId', opponents.id,
      'name', opponents.name,
      'teamCode', opponents.team_code,
      'matchesPlayed', known.matches_played,
      'firstEncounterAt', known.first_encounter_at,
      'lastEncounterAt', known.last_encounter_at,
      'lastMatchId', known.last_match_id,
      'revision', known.revision
    ) order by known.last_encounter_at desc, opponents.id
  ), '[]'::jsonb)
  into opponent_items
  from public.pachanga_known_opponents known
  join public.pachanga_groups opponents on opponents.id = known.opponent_group_id
  where known.group_id = target_group_id;

  return jsonb_build_object(
    'group', jsonb_build_object(
      'groupId', current_group.id,
      'name', current_group.name,
      'teamCode', current_group.team_code
    ),
    'canManage', public.is_pachanga_group_admin(target_group_id),
    'socialRevision', coalesce(current_state.revision, 0),
    'confirmedRevision', coalesce(current_state.revision, 0),
    'serverSequence', coalesce(current_state.server_sequence, 0),
    'updatedAt', coalesce(current_state.updated_at, current_group.updated_at),
    'challenges', challenge_items,
    'knownOpponents', opponent_items
  );
end;
$$;

create or replace function public.pachanga_team_social_bump(
  target_group_ids uuid[],
  target_server_sequence bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_team_social_state(group_id, revision, server_sequence, updated_at)
  select distinct group_id, 1, target_server_sequence, clock_timestamp()
  from unnest(target_group_ids) group_ids(group_id)
  where group_id is not null
  on conflict (group_id) do update set
    revision = public.pachanga_team_social_state.revision + 1,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at;
end;
$$;

create or replace function public.pachanga_team_social_store_response(
  target_group_id uuid,
  target_operation_id uuid,
  target_operation_type text,
  target_expected_revision bigint,
  target_server_sequence bigint,
  target_client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  canonical jsonb;
  final_response jsonb;
  stored_response jsonb;
begin
  canonical := public.get_pachanga_team_social_snapshot(target_group_id);
  final_response := canonical || jsonb_build_object(
    'operationId', target_operation_id,
    'expectedRevision', target_expected_revision,
    'confirmedAt', clock_timestamp(),
    'serverSequence', target_server_sequence
  );

  insert into public.pachanga_team_social_operation_receipts(
    operation_id,
    group_id,
    actor_user_id,
    operation_type,
    expected_revision,
    result_revision,
    server_sequence,
    response,
    client_metadata
  ) values (
    target_operation_id,
    target_group_id,
    auth.uid(),
    left(coalesce(nullif(trim(target_operation_type), ''), 'unknown'), 120),
    target_expected_revision,
    (canonical ->> 'confirmedRevision')::bigint,
    target_server_sequence,
    final_response,
    case when jsonb_typeof(target_client_metadata) = 'object' then target_client_metadata else '{}'::jsonb end
  )
  on conflict (operation_id) do nothing;

  select receipts.response into stored_response
  from public.pachanga_team_social_operation_receipts receipts
  where receipts.operation_id = target_operation_id
    and receipts.actor_user_id = auth.uid();

  if stored_response is null then raise exception 'Operation belongs to another actor'; end if;
  return stored_response;
end;
$$;

create or replace function public.lookup_pachanga_team_by_code(
  target_group_id uuid,
  opponent_team_code text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  opponent public.pachanga_groups%rowtype;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can look up rivals';
  end if;
  if nullif(trim(opponent_team_code), '') is null then raise exception 'Team code required'; end if;

  select * into opponent
  from public.pachanga_groups groups
  where upper(groups.team_code) = upper(trim(opponent_team_code))
    and groups.id <> target_group_id
  limit 1;
  if not found then raise exception 'No team matches that code'; end if;

  return jsonb_build_object(
    'groupId', opponent.id,
    'name', opponent.name,
    'teamCode', opponent.team_code
  );
end;
$$;

create or replace function public.create_pachanga_team_challenge_authoritative(
  target_group_id uuid,
  opponent_team_code text,
  target_scheduled_at timestamptz,
  target_modality text,
  target_field_name text,
  target_field_address text,
  target_field_place_id text,
  target_field_maps_url text,
  target_message text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  opponent_group_id uuid;
  current_revision bigint;
  challenge_id uuid;
  event_sequence bigint;
  replay jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('team-social-operation:' || operation_id::text, 0));
  replay := public.pachanga_team_social_operation_replay(
    target_group_id, operation_id, auth.uid(), 'team_challenge_created'
  );
  if replay is not null then return replay; end if;

  select groups.id into opponent_group_id
  from public.pachanga_groups groups
  where upper(groups.team_code) = upper(trim(opponent_team_code))
    and groups.id <> target_group_id
  limit 1;
  if opponent_group_id is null then raise exception 'Rival not found'; end if;
  if target_scheduled_at is null or target_scheduled_at <= clock_timestamp() then
    raise exception 'Challenge date must be in the future';
  end if;
  if target_modality not in ('sala', 'futbol7', 'futbol11') then raise exception 'Invalid modality'; end if;
  if nullif(trim(target_field_name), '') is null or nullif(trim(target_field_address), '') is null then
    raise exception 'Field name and address are required';
  end if;
  if char_length(trim(target_field_name)) > 160 or char_length(trim(target_field_address)) > 300
    or char_length(coalesce(target_field_place_id, '')) > 300
    or char_length(coalesce(target_field_maps_url, '')) > 800
    or char_length(coalesce(target_message, '')) > 1200 then
    raise exception 'Challenge text is too long';
  end if;
  if nullif(trim(coalesce(target_field_maps_url, '')), '') is not null
    and trim(target_field_maps_url) !~* '^https://(www\.)?(google\.[a-z.]+/maps|maps\.app\.goo\.gl)/' then
    raise exception 'Google Maps link is invalid';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'team-social-pair:' || least(target_group_id::text, opponent_group_id::text)
      || ':' || greatest(target_group_id::text, opponent_group_id::text), 0
  ));
  perform 1 from public.pachanga_team_social_state states
  where states.group_id in (target_group_id, opponent_group_id)
  order by states.group_id
  for update;
  select states.revision into current_revision
  from public.pachanga_team_social_state states
  where states.group_id = target_group_id;
  if current_revision is distinct from expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  insert into public.pachanga_team_challenges(
    sender_group_id,
    receiver_group_id,
    scheduled_at,
    modality,
    field_name,
    field_address,
    field_place_id,
    field_maps_url,
    message,
    last_proposed_by_group_id,
    created_by,
    updated_by
  ) values (
    target_group_id,
    opponent_group_id,
    target_scheduled_at,
    target_modality,
    left(trim(target_field_name), 160),
    left(trim(target_field_address), 300),
    nullif(left(trim(coalesce(target_field_place_id, '')), 300), ''),
    nullif(left(trim(coalesce(target_field_maps_url, '')), 800), ''),
    nullif(left(trim(coalesce(target_message, '')), 1200), ''),
    target_group_id,
    auth.uid(),
    auth.uid()
  ) returning id into challenge_id;

  insert into public.pachanga_team_challenge_events(
    challenge_id, operation_id, actor_user_id, actor_group_id,
    event_type, challenge_revision, snapshot
  ) values (
    challenge_id, operation_id, auth.uid(), target_group_id,
    'created', 1, public.pachanga_team_challenge_snapshot(challenge_id, target_group_id)
  ) returning server_sequence into event_sequence;

  perform public.pachanga_team_social_bump(array[target_group_id, opponent_group_id], event_sequence);
  return public.pachanga_team_social_store_response(
    target_group_id, operation_id, 'team_challenge_created', expected_revision,
    event_sequence, client_metadata
  );
end;
$$;

create or replace function public.respond_pachanga_team_challenge_authoritative(
  target_group_id uuid,
  target_challenge_id uuid,
  target_action text,
  target_scheduled_at timestamptz,
  target_modality text,
  target_field_name text,
  target_field_address text,
  target_field_place_id text,
  target_field_maps_url text,
  target_message text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_team_challenges%rowtype;
  event_sequence bigint;
  next_revision bigint;
  replay jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  if target_action not in ('accept', 'reject', 'propose_changes', 'cancel') then raise exception 'Invalid action'; end if;
  perform pg_advisory_xact_lock(hashtextextended('team-social-operation:' || operation_id::text, 0));
  replay := public.pachanga_team_social_operation_replay(
    target_group_id, operation_id, auth.uid(), 'team_challenge_' || target_action
  );
  if replay is not null then return replay; end if;

  select * into selected
  from public.pachanga_team_challenges challenges
  where challenges.id = target_challenge_id;
  if not found or target_group_id not in (selected.sender_group_id, selected.receiver_group_id) then
    raise exception 'Challenge not found';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'team-social-pair:' || least(selected.sender_group_id::text, selected.receiver_group_id::text)
      || ':' || greatest(selected.sender_group_id::text, selected.receiver_group_id::text), 0
  ));
  select * into selected
  from public.pachanga_team_challenges challenges
  where challenges.id = target_challenge_id
  for update;
  perform 1 from public.pachanga_team_social_state states
  where states.group_id in (selected.sender_group_id, selected.receiver_group_id)
  order by states.group_id
  for update;

  if selected.revision <> expected_revision then
    raise exception 'Challenge revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.status not in ('proposed', 'changes_proposed') then raise exception 'Challenge is already closed'; end if;
  if target_action in ('accept', 'reject') and selected.last_proposed_by_group_id = target_group_id then
    raise exception 'The proposing team cannot accept or reject its own proposal';
  end if;
  if target_action = 'cancel' and selected.sender_group_id <> target_group_id then
    raise exception 'Only the sending team can cancel this challenge';
  end if;
  if target_action = 'propose_changes' then
    if target_scheduled_at is null or target_scheduled_at <= clock_timestamp() then
      raise exception 'Challenge date must be in the future';
    end if;
    if target_modality not in ('sala', 'futbol7', 'futbol11') then raise exception 'Invalid modality'; end if;
    if nullif(trim(target_field_name), '') is null or nullif(trim(target_field_address), '') is null then
      raise exception 'Field name and address are required';
    end if;
    if char_length(trim(target_field_name)) > 160 or char_length(trim(target_field_address)) > 300
      or char_length(coalesce(target_field_place_id, '')) > 300
      or char_length(coalesce(target_field_maps_url, '')) > 800
      or char_length(coalesce(target_message, '')) > 1200 then
      raise exception 'Challenge text is too long';
    end if;
    if nullif(trim(coalesce(target_field_maps_url, '')), '') is not null
      and trim(target_field_maps_url) !~* '^https://(www\.)?(google\.[a-z.]+/maps|maps\.app\.goo\.gl)/' then
      raise exception 'Google Maps link is invalid';
    end if;
  end if;

  next_revision := selected.revision + 1;
  update public.pachanga_team_challenges challenges
  set
    status = case target_action
      when 'accept' then 'accepted'
      when 'reject' then 'rejected'
      when 'cancel' then 'cancelled'
      else 'changes_proposed'
    end,
    revision = next_revision,
    proposal_number = case when target_action = 'propose_changes' then challenges.proposal_number + 1 else challenges.proposal_number end,
    scheduled_at = case when target_action = 'propose_changes' then target_scheduled_at else challenges.scheduled_at end,
    modality = case when target_action = 'propose_changes' then target_modality else challenges.modality end,
    field_name = case when target_action = 'propose_changes' then left(trim(target_field_name), 160) else challenges.field_name end,
    field_address = case when target_action = 'propose_changes' then left(trim(target_field_address), 300) else challenges.field_address end,
    field_place_id = case when target_action = 'propose_changes' then nullif(left(trim(coalesce(target_field_place_id, '')), 300), '') else challenges.field_place_id end,
    field_maps_url = case when target_action = 'propose_changes' then nullif(left(trim(coalesce(target_field_maps_url, '')), 800), '') else challenges.field_maps_url end,
    message = case when target_action = 'propose_changes' then nullif(left(trim(coalesce(target_message, '')), 1200), '') else challenges.message end,
    last_proposed_by_group_id = case when target_action = 'propose_changes' then target_group_id else challenges.last_proposed_by_group_id end,
    accepted_at = case when target_action = 'accept' then clock_timestamp() else challenges.accepted_at end,
    rejected_at = case when target_action = 'reject' then clock_timestamp() else challenges.rejected_at end,
    cancelled_at = case when target_action = 'cancel' then clock_timestamp() else challenges.cancelled_at end,
    updated_by = auth.uid(),
    updated_at = clock_timestamp()
  where challenges.id = target_challenge_id;

  insert into public.pachanga_team_challenge_events(
    challenge_id, operation_id, actor_user_id, actor_group_id,
    event_type, challenge_revision, snapshot
  ) values (
    target_challenge_id, operation_id, auth.uid(), target_group_id,
    case target_action
      when 'accept' then 'accepted'
      when 'reject' then 'rejected'
      when 'cancel' then 'cancelled'
      else 'changes_proposed'
    end,
    next_revision,
    public.pachanga_team_challenge_snapshot(target_challenge_id, target_group_id)
  ) returning server_sequence into event_sequence;

  perform public.pachanga_team_social_bump(array[selected.sender_group_id, selected.receiver_group_id], event_sequence);
  return public.pachanga_team_social_store_response(
    target_group_id, operation_id, 'team_challenge_' || target_action,
    expected_revision, event_sequence, client_metadata
  );
end;
$$;

create or replace function public.pachanga_rebuild_known_opponent_pair(
  first_group_id uuid,
  second_group_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  directional_first integer;
  directional_second integer;
  encounter_count integer;
  first_at timestamptz;
  last_at timestamptz;
  latest_match_id text;
  event_sequence bigint;
begin
  if first_group_id is null or second_group_id is null or first_group_id = second_group_id then return; end if;

  select count(*) into directional_first
  from public.pachanga_registered_match_opponents opponents
  join public.pachanga_match_rating_snapshots snapshots
    on snapshots.group_id = opponents.host_group_id and snapshots.match_id = opponents.match_id
  where opponents.host_group_id = first_group_id
    and opponents.opponent_group_id = second_group_id
    and snapshots.state = 'active';

  select count(*) into directional_second
  from public.pachanga_registered_match_opponents opponents
  join public.pachanga_match_rating_snapshots snapshots
    on snapshots.group_id = opponents.host_group_id and snapshots.match_id = opponents.match_id
  where opponents.host_group_id = second_group_id
    and opponents.opponent_group_id = first_group_id
    and snapshots.state = 'active';

  encounter_count := greatest(directional_first, directional_second);
  select min(snapshots.finalized_at), max(snapshots.finalized_at)
  into first_at, last_at
  from public.pachanga_registered_match_opponents opponents
  join public.pachanga_match_rating_snapshots snapshots
    on snapshots.group_id = opponents.host_group_id and snapshots.match_id = opponents.match_id
  where ((opponents.host_group_id = first_group_id and opponents.opponent_group_id = second_group_id)
      or (opponents.host_group_id = second_group_id and opponents.opponent_group_id = first_group_id))
    and snapshots.state = 'active';

  select opponents.match_id
  into latest_match_id
  from public.pachanga_registered_match_opponents opponents
  join public.pachanga_match_rating_snapshots snapshots
    on snapshots.group_id = opponents.host_group_id and snapshots.match_id = opponents.match_id
  where ((opponents.host_group_id = first_group_id and opponents.opponent_group_id = second_group_id)
      or (opponents.host_group_id = second_group_id and opponents.opponent_group_id = first_group_id))
    and snapshots.state = 'active'
  order by snapshots.finalized_at desc, opponents.host_group_id, opponents.match_id
  limit 1;

  if encounter_count < 1 or latest_match_id is null then
    delete from public.pachanga_known_opponents known
    where (known.group_id = first_group_id and known.opponent_group_id = second_group_id)
       or (known.group_id = second_group_id and known.opponent_group_id = first_group_id);
  else
    insert into public.pachanga_known_opponents(
      group_id, opponent_group_id, matches_played, first_encounter_at,
      last_encounter_at, last_match_id, revision, updated_at
    ) values
      (first_group_id, second_group_id, encounter_count, first_at, last_at, latest_match_id, 1, clock_timestamp()),
      (second_group_id, first_group_id, encounter_count, first_at, last_at, latest_match_id, 1, clock_timestamp())
    on conflict (group_id, opponent_group_id) do update set
      matches_played = excluded.matches_played,
      first_encounter_at = excluded.first_encounter_at,
      last_encounter_at = excluded.last_encounter_at,
      last_match_id = excluded.last_match_id,
      revision = public.pachanga_known_opponents.revision + 1,
      updated_at = excluded.updated_at;
  end if;

  event_sequence := nextval('public.pachanga_team_social_sequence');
  perform public.pachanga_team_social_bump(array[first_group_id, second_group_id], event_sequence);
end;
$$;

create or replace function public.pachanga_refresh_known_opponents_from_link()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.pachanga_rebuild_known_opponent_pair(old.host_group_id, old.opponent_group_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and (
    tg_op = 'INSERT'
    or old.host_group_id is distinct from new.host_group_id
    or old.opponent_group_id is distinct from new.opponent_group_id
  ) then
    perform public.pachanga_rebuild_known_opponent_pair(new.host_group_id, new.opponent_group_id);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists refresh_known_opponents_from_registered_link
  on public.pachanga_registered_match_opponents;
create trigger refresh_known_opponents_from_registered_link
after insert or update or delete on public.pachanga_registered_match_opponents
for each row execute function public.pachanga_refresh_known_opponents_from_link();

create or replace function public.pachanga_refresh_known_opponents_from_snapshot()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  linked record;
  source_group_id uuid;
  source_match_id text;
begin
  source_group_id := case when tg_op = 'DELETE' then old.group_id else new.group_id end;
  source_match_id := case when tg_op = 'DELETE' then old.match_id else new.match_id end;
  for linked in
    select opponents.host_group_id, opponents.opponent_group_id
    from public.pachanga_registered_match_opponents opponents
    where opponents.host_group_id = source_group_id
      and opponents.match_id = source_match_id
  loop
    perform public.pachanga_rebuild_known_opponent_pair(linked.host_group_id, linked.opponent_group_id);
  end loop;
  if tg_op = 'UPDATE'
    and (old.group_id is distinct from new.group_id or old.match_id is distinct from new.match_id) then
    for linked in
      select opponents.host_group_id, opponents.opponent_group_id
      from public.pachanga_registered_match_opponents opponents
      where opponents.host_group_id = old.group_id
        and opponents.match_id = old.match_id
    loop
      perform public.pachanga_rebuild_known_opponent_pair(linked.host_group_id, linked.opponent_group_id);
    end loop;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists refresh_known_opponents_from_match_snapshot
  on public.pachanga_match_rating_snapshots;
create trigger refresh_known_opponents_from_match_snapshot
after insert or update or delete on public.pachanga_match_rating_snapshots
for each row execute function public.pachanga_refresh_known_opponents_from_snapshot();

do $$
declare
  linked record;
begin
  for linked in
    select distinct opponents.host_group_id, opponents.opponent_group_id
    from public.pachanga_registered_match_opponents opponents
  loop
    perform public.pachanga_rebuild_known_opponent_pair(linked.host_group_id, linked.opponent_group_id);
  end loop;
end;
$$;

revoke all on function public.pachanga_initialize_team_social_state() from public, anon, authenticated;
revoke all on function public.pachanga_team_social_operation_replay(uuid, uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.pachanga_team_challenge_snapshot(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pachanga_team_social_bump(uuid[], bigint) from public, anon, authenticated;
revoke all on function public.pachanga_team_social_store_response(uuid, uuid, text, bigint, bigint, jsonb) from public, anon, authenticated;
revoke all on function public.pachanga_rebuild_known_opponent_pair(uuid, uuid) from public, anon, authenticated;
revoke all on function public.pachanga_refresh_known_opponents_from_link() from public, anon, authenticated;
revoke all on function public.pachanga_refresh_known_opponents_from_snapshot() from public, anon, authenticated;

revoke all on function public.get_pachanga_team_social_snapshot(uuid) from public, anon;
grant execute on function public.get_pachanga_team_social_snapshot(uuid) to authenticated;
revoke all on function public.lookup_pachanga_team_by_code(uuid, text) from public, anon;
grant execute on function public.lookup_pachanga_team_by_code(uuid, text) to authenticated;
revoke all on function public.create_pachanga_team_challenge_authoritative(
  uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) from public, anon;
grant execute on function public.create_pachanga_team_challenge_authoritative(
  uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) to authenticated;
revoke all on function public.respond_pachanga_team_challenge_authoritative(
  uuid, uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) from public, anon;
grant execute on function public.respond_pachanga_team_challenge_authoritative(
  uuid, uuid, text, timestamptz, text, text, text, text, text, text, uuid, bigint, jsonb
) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_team_social_state'
  ) then
    alter publication supabase_realtime add table public.pachanga_team_social_state;
  end if;
end;
$$;
