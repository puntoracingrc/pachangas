-- Match invitations, private notifications and read-only guest match access.
-- This migration is additive for the existing PWA. The final direct-read
-- closure for the public market lives in a later migration.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create sequence if not exists public.pachanga_match_guest_sequence;
revoke all on sequence public.pachanga_match_guest_sequence from public, anon, authenticated;

alter table public.pachanga_open_matches
  add column if not exists source_payload_revision bigint not null default 0;

alter table public.pachanga_open_match_requests
  add column if not exists revision bigint not null default 1,
  add column if not exists server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence');

update public.pachanga_open_matches open_matches
set source_payload_revision = groups.payload_revision
from public.pachanga_groups groups
where groups.id = open_matches.source_group_id
  and open_matches.source_payload_revision is distinct from groups.payload_revision;

create table if not exists public.pachanga_user_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  title text not null,
  body text not null default '',
  action_url text,
  payload jsonb not null default '{}'::jsonb,
  dedupe_key text not null unique,
  read_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (jsonb_typeof(payload) = 'object')
);

create index if not exists pachanga_user_notifications_recipient_sequence_idx
  on public.pachanga_user_notifications(recipient_user_id, server_sequence desc);
create index if not exists pachanga_user_notifications_recipient_unread_idx
  on public.pachanga_user_notifications(recipient_user_id, server_sequence desc)
  where read_at is null;

create table if not exists private.pachanga_notification_operation_receipts (
  operation_id uuid primary key,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  notification_id uuid not null references public.pachanga_user_notifications(id) on delete cascade,
  response jsonb not null,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (jsonb_typeof(response) = 'object')
);

revoke all on table private.pachanga_notification_operation_receipts
  from public, anon, authenticated;

create table if not exists public.pachanga_match_invitations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text not null,
  target_market_profile_id uuid not null references public.pachanga_market_profiles(id) on delete restrict,
  invitee_user_id uuid not null references auth.users(id) on delete cascade,
  inviter_user_id uuid not null references auth.users(id) on delete restrict,
  invitee_name text not null,
  invitee_avatar text,
  invitee_avatar_offset_x numeric,
  invitee_avatar_offset_y numeric,
  invitee_birth_date date,
  invitee_position text not null,
  invitee_goalkeeper_only boolean not null default false,
  invitee_media numeric not null default 5,
  status text not null default 'pending',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  responded_at timestamptz,
  cancelled_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('pending', 'accepted', 'rejected', 'cancelled')),
  check (invitee_media between 0 and 100)
);

create unique index if not exists pachanga_match_invitations_one_pending_idx
  on public.pachanga_match_invitations(group_id, match_id, invitee_user_id)
  where status = 'pending';
create index if not exists pachanga_match_invitations_invitee_idx
  on public.pachanga_match_invitations(invitee_user_id, server_sequence desc);
create index if not exists pachanga_match_invitations_group_match_idx
  on public.pachanga_match_invitations(group_id, match_id, server_sequence desc);

create table if not exists public.pachanga_match_guest_access (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text not null,
  guest_user_id uuid not null references auth.users(id) on delete cascade,
  player_id text not null,
  source_kind text not null,
  source_id uuid not null,
  status text not null default 'accepted',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  accepted_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  unique(source_kind, source_id),
  check (source_kind in ('invitation', 'open_request')),
  check (status in ('accepted', 'revoked'))
);

create unique index if not exists pachanga_match_guest_access_active_user_idx
  on public.pachanga_match_guest_access(group_id, match_id, guest_user_id)
  where status = 'accepted';
create index if not exists pachanga_match_guest_access_user_idx
  on public.pachanga_match_guest_access(guest_user_id, server_sequence desc);

create table if not exists public.pachanga_match_guest_snapshots (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text not null,
  snapshot_revision bigint not null default 1,
  source_payload_revision bigint not null,
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  snapshot jsonb not null,
  updated_at timestamptz not null default clock_timestamp(),
  unique(group_id, match_id),
  check (jsonb_typeof(snapshot) = 'object')
);

create index if not exists pachanga_match_guest_snapshots_sequence_idx
  on public.pachanga_match_guest_snapshots(server_sequence desc);

create table if not exists public.pachanga_guest_withdrawal_reviews (
  id uuid primary key default gen_random_uuid(),
  access_id uuid not null unique references public.pachanga_match_guest_access(id) on delete cascade,
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text not null,
  guest_user_id uuid not null references auth.users(id) on delete cascade,
  player_id text not null,
  status text not null default 'pending',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  occurred_at timestamptz not null default clock_timestamp(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('pending', 'confirmed', 'dismissed'))
);

create index if not exists pachanga_guest_withdrawal_reviews_group_idx
  on public.pachanga_guest_withdrawal_reviews(group_id, status, server_sequence desc);

alter table public.pachanga_user_notifications enable row level security;
alter table public.pachanga_match_invitations enable row level security;
alter table public.pachanga_match_guest_access enable row level security;
alter table public.pachanga_match_guest_snapshots enable row level security;
alter table public.pachanga_guest_withdrawal_reviews enable row level security;

revoke all on table public.pachanga_user_notifications from public, anon, authenticated;
revoke all on table public.pachanga_match_invitations from public, anon, authenticated;
revoke all on table public.pachanga_match_guest_access from public, anon, authenticated;
revoke all on table public.pachanga_match_guest_snapshots from public, anon, authenticated;
revoke all on table public.pachanga_guest_withdrawal_reviews from public, anon, authenticated;

grant select on table public.pachanga_user_notifications to authenticated;
grant select on table public.pachanga_match_guest_access to authenticated;
grant select on table public.pachanga_match_guest_snapshots to authenticated;

drop policy if exists "Users read their own notifications" on public.pachanga_user_notifications;
create policy "Users read their own notifications"
on public.pachanga_user_notifications
for select
to authenticated
using ((select auth.uid()) = recipient_user_id);

drop policy if exists "Guests read their own match access" on public.pachanga_match_guest_access;
create policy "Guests read their own match access"
on public.pachanga_match_guest_access
for select
to authenticated
using ((select auth.uid()) = guest_user_id);

drop policy if exists "Members and accepted guests read safe match snapshots" on public.pachanga_match_guest_snapshots;
create policy "Members and accepted guests read safe match snapshots"
on public.pachanga_match_guest_snapshots
for select
to authenticated
using (
  public.is_pachanga_group_member(group_id)
  or exists (
    select 1
    from public.pachanga_match_guest_access access
    where access.group_id = pachanga_match_guest_snapshots.group_id
      and access.match_id = pachanga_match_guest_snapshots.match_id
      and access.guest_user_id = (select auth.uid())
      and access.status = 'accepted'
  )
);

create or replace function private.pachanga_notify_v1(
  target_recipient_user_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_dedupe_key text
)
returns public.pachanga_user_notifications
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved_notification public.pachanga_user_notifications%rowtype;
begin
  if target_recipient_user_id is null or nullif(trim(target_dedupe_key), '') is null then
    raise exception 'Notification recipient and dedupe key required';
  end if;

  insert into public.pachanga_user_notifications(
    recipient_user_id, kind, title, body, action_url, payload, dedupe_key
  ) values (
    target_recipient_user_id,
    left(coalesce(nullif(trim(target_kind), ''), 'general'), 80),
    left(coalesce(nullif(trim(target_title), ''), 'Pachangas IQ'), 140),
    left(coalesce(target_body, ''), 500),
    nullif(left(coalesce(target_action_url, ''), 500), ''),
    case when jsonb_typeof(target_payload) = 'object' then target_payload else '{}'::jsonb end,
    left(target_dedupe_key, 240)
  )
  on conflict (dedupe_key) do update set
    title = excluded.title,
    body = excluded.body,
    action_url = excluded.action_url,
    payload = excluded.payload,
    revision = public.pachanga_user_notifications.revision + 1,
    server_sequence = nextval('public.pachanga_match_guest_sequence'),
    updated_at = clock_timestamp()
  returning * into saved_notification;

  return saved_notification;
end;
$$;

revoke all on function private.pachanga_notify_v1(uuid, text, text, text, text, jsonb, text)
  from public, anon, authenticated;

create or replace function private.pachanga_build_guest_match_snapshot_v1(
  target_group_name text,
  target_payload jsonb,
  target_match jsonb
)
returns jsonb
language sql
stable
set search_path = pg_catalog
as $$
  with participant_rows as (
    select
      entries.value ->> 'playerId' as player_id,
      entries.value ->> 'status' as status,
      entries.ordinality::bigint as sort_order
    from jsonb_array_elements(coalesce(target_match -> 'players', '[]'::jsonb))
      with ordinality as entries(value, ordinality)
    where nullif(entries.value ->> 'playerId', '') is not null
  ),
  referenced_ids as (
    select player_id, sort_order from participant_rows
    union all
    select values.value #>> '{}', 1000 + values.ordinality
    from jsonb_array_elements(coalesce(target_match -> 'teamA', '[]'::jsonb))
      with ordinality as values(value, ordinality)
    where jsonb_typeof(values.value) = 'string'
    union all
    select values.value #>> '{}', 2000 + values.ordinality
    from jsonb_array_elements(coalesce(target_match -> 'teamB', '[]'::jsonb))
      with ordinality as values(value, ordinality)
    where jsonb_typeof(values.value) = 'string'
  ),
  ordered_ids as (
    select player_id, min(sort_order) as sort_order
    from referenced_ids
    where nullif(player_id, '') is not null
    group by player_id
  ),
  safe_players as (
    select coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'id', players.value ->> 'id',
        'name', left(coalesce(nullif(trim(players.value ->> 'name'), ''), 'Jugador'), 80),
        'avatar', players.value -> 'avatar',
        'avatarOffsetX', players.value -> 'avatarOffsetX',
        'avatarOffsetY', players.value -> 'avatarOffsetY',
        'position', players.value -> 'position',
        'outfieldPosition', players.value -> 'outfieldPosition',
        'goalkeeperOnly', players.value -> 'goalkeeperOnly',
        'rating', coalesce(players.value -> 'ratingV2' -> 'currentOverall', players.value -> 'rating'),
        'injured', players.value -> 'injured',
        'inactive', players.value -> 'inactive',
        'status', participant.status,
        'team', case
          when (target_match -> 'teamA') @> jsonb_build_array(players.value ->> 'id') then 'A'
          when (target_match -> 'teamB') @> jsonb_build_array(players.value ->> 'id') then 'B'
          else null
        end
      ))
      order by ordered.sort_order, coalesce(players.value ->> 'name', ''), players.value ->> 'id'
    ), '[]'::jsonb) as value
    from jsonb_array_elements(coalesce(target_payload -> 'players', '[]'::jsonb)) players(value)
    join ordered_ids ordered on ordered.player_id = players.value ->> 'id'
    left join participant_rows participant on participant.player_id = players.value ->> 'id'
  ),
  safe_team_a as (
    select coalesce(jsonb_agg(values.value order by values.ordinality), '[]'::jsonb) as value
    from jsonb_array_elements(coalesce(target_match -> 'teamA', '[]'::jsonb))
      with ordinality as values(value, ordinality)
    where jsonb_typeof(values.value) = 'string'
  ),
  safe_team_b as (
    select coalesce(jsonb_agg(values.value order by values.ordinality), '[]'::jsonb) as value
    from jsonb_array_elements(coalesce(target_match -> 'teamB', '[]'::jsonb))
      with ordinality as values(value, ordinality)
    where jsonb_typeof(values.value) = 'string'
  ),
  safe_slots_a as (
    select coalesce(jsonb_agg(
      case when jsonb_typeof(values.value) = 'string' then values.value else 'null'::jsonb end
      order by values.ordinality
    ), '[]'::jsonb) as value
    from jsonb_array_elements(coalesce(target_match -> 'lineupSlots' -> 'teamA', '[]'::jsonb))
      with ordinality as values(value, ordinality)
  ),
  safe_slots_b as (
    select coalesce(jsonb_agg(
      case when jsonb_typeof(values.value) = 'string' then values.value else 'null'::jsonb end
      order by values.ordinality
    ), '[]'::jsonb) as value
    from jsonb_array_elements(coalesce(target_match -> 'lineupSlots' -> 'teamB', '[]'::jsonb))
      with ordinality as values(value, ordinality)
  ),
  safe_scorers as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'playerId', values.value ->> 'playerId',
        'goals', greatest(0, coalesce((values.value ->> 'goals')::integer, 0))
      ) order by values.ordinality
    ), '[]'::jsonb) as value
    from jsonb_array_elements(coalesce(target_match -> 'scorers', '[]'::jsonb))
      with ordinality as values(value, ordinality)
    where nullif(values.value ->> 'playerId', '') is not null
  )
  select jsonb_build_object(
    'schemaVersion', 1,
    'groupName', left(coalesce(nullif(trim(target_group_name), ''), 'Grupo de pachangas'), 120),
    'match', jsonb_strip_nulls(jsonb_build_object(
      'id', target_match ->> 'id',
      'title', left(coalesce(nullif(trim(target_match ->> 'title'), ''), 'Partido'), 120),
      'date', target_match -> 'date',
      'place', target_match -> 'place',
      'kind', target_match -> 'kind',
      'configured', coalesce(target_match -> 'configured', 'false'::jsonb),
      'lineupClosed', coalesce(target_match -> 'lineupClosed', 'false'::jsonb),
      'finalized', to_jsonb(coalesce((target_match ->> 'closed')::boolean, false) or target_match ? 'scoreA'),
      'targetPlayers', target_match -> 'targetPlayers',
      'reserveLimit', target_match -> 'reserveLimit',
      'confirmedCount', to_jsonb((select count(*) from participant_rows where status = 'voy')),
      'scoreA', target_match -> 'scoreA',
      'scoreB', target_match -> 'scoreB',
      'teamA', safe_team_a.value,
      'teamB', safe_team_b.value,
      'lineupSlots', jsonb_build_object('teamA', safe_slots_a.value, 'teamB', safe_slots_b.value),
      'scorers', safe_scorers.value
    )),
    'players', safe_players.value
  )
  from safe_players, safe_team_a, safe_team_b, safe_slots_a, safe_slots_b, safe_scorers;
$$;

revoke all on function private.pachanga_build_guest_match_snapshot_v1(text, jsonb, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_sync_guest_match_state_v1(
  target_group_id uuid,
  target_group_name text,
  target_payload jsonb,
  target_payload_revision bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_match jsonb;
  safe_snapshot jsonb;
  revoked_access public.pachanga_match_guest_access%rowtype;
begin
  update public.pachanga_open_matches open_matches
  set source_payload_revision = target_payload_revision,
      updated_at = case
        when open_matches.source_payload_revision is distinct from target_payload_revision then clock_timestamp()
        else open_matches.updated_at
      end
  where open_matches.source_group_id = target_group_id
    and open_matches.source_payload_revision is distinct from target_payload_revision;

  for selected_match in
    select matches.value
    from jsonb_array_elements(coalesce(target_payload -> 'matches', '[]'::jsonb)) matches(value)
    where nullif(matches.value ->> 'id', '') is not null
  loop
    safe_snapshot := private.pachanga_build_guest_match_snapshot_v1(
      target_group_name, target_payload, selected_match
    );

    insert into public.pachanga_match_guest_snapshots(
      group_id, match_id, source_payload_revision, snapshot
    ) values (
      target_group_id,
      selected_match ->> 'id',
      target_payload_revision,
      safe_snapshot
    )
    on conflict (group_id, match_id) do update set
      snapshot_revision = public.pachanga_match_guest_snapshots.snapshot_revision + 1,
      source_payload_revision = excluded.source_payload_revision,
      server_sequence = nextval('public.pachanga_match_guest_sequence'),
      snapshot = excluded.snapshot,
      updated_at = clock_timestamp()
    where public.pachanga_match_guest_snapshots.snapshot is distinct from excluded.snapshot;
  end loop;

  delete from public.pachanga_match_guest_snapshots snapshots
  where snapshots.group_id = target_group_id
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(target_payload -> 'matches', '[]'::jsonb)) matches(value)
      where matches.value ->> 'id' = snapshots.match_id
    );

  for revoked_access in
    update public.pachanga_match_guest_access access
    set status = 'revoked',
        revision = access.revision + 1,
        server_sequence = nextval('public.pachanga_match_guest_sequence'),
        revoked_at = coalesce(access.revoked_at, clock_timestamp()),
        updated_at = clock_timestamp()
    where access.group_id = target_group_id
      and access.status = 'accepted'
      and not exists (
        select 1
        from jsonb_array_elements(coalesce(target_payload -> 'matches', '[]'::jsonb)) matches(value)
        cross join lateral jsonb_array_elements(coalesce(matches.value -> 'players', '[]'::jsonb)) participants(value)
        where matches.value ->> 'id' = access.match_id
          and participants.value ->> 'playerId' = access.player_id
          and participants.value ->> 'status' = 'voy'
      )
    returning access.*
  loop
    perform private.pachanga_notify_v1(
      revoked_access.guest_user_id,
      'match_access_revoked',
      'Acceso al partido retirado',
      'Ya no figuras como asistente y el acceso de invitado se ha cerrado.',
      null,
      jsonb_build_object('accessId', revoked_access.id, 'accessRevision', revoked_access.revision),
      'guest-access-revoked:' || revoked_access.id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_sync_guest_match_state_v1(uuid, text, jsonb, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_sync_guest_match_state_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_sync_guest_match_state_v1(new.id, new.name, new.payload, new.payload_revision);
  return new;
end;
$$;

revoke all on function private.pachanga_sync_guest_match_state_trigger_v1()
  from public, anon, authenticated;

drop trigger if exists sync_pachanga_guest_match_state on public.pachanga_groups;
create trigger sync_pachanga_guest_match_state
after insert or update of payload, payload_revision, name on public.pachanga_groups
for each row execute function private.pachanga_sync_guest_match_state_trigger_v1();

do $$
declare
  selected_group public.pachanga_groups%rowtype;
begin
  for selected_group in select * from public.pachanga_groups loop
    perform private.pachanga_sync_guest_match_state_v1(
      selected_group.id,
      selected_group.name,
      selected_group.payload,
      selected_group.payload_revision
    );
  end loop;
end;
$$;

create or replace function private.pachanga_safe_operation_replay_v1(
  target_group_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_operation_type text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  saved_receipt public.pachanga_operation_receipts%rowtype;
begin
  if target_operation_id is null then return null; end if;

  select * into saved_receipt
  from public.pachanga_operation_receipts receipts
  where receipts.group_id = target_group_id
    and receipts.operation_id = target_operation_id;

  if not found then return null; end if;
  if saved_receipt.user_id is distinct from target_actor_id then
    raise exception 'Operation belongs to another actor';
  end if;
  if saved_receipt.operation_type is distinct from target_operation_type then
    raise exception 'Operation id was already used for another action';
  end if;
  return saved_receipt.response;
end;
$$;

create or replace function private.pachanga_store_safe_operation_v1(
  target_group_id uuid,
  target_operation_id uuid,
  target_operation_type text,
  target_actor_id uuid,
  target_expected_revision bigint,
  target_result_revision bigint,
  target_client_metadata jsonb,
  target_response jsonb,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  stored_response jsonb;
begin
  if target_operation_id is null or target_actor_id is null then
    raise exception 'Operation id and actor required';
  end if;

  insert into public.pachanga_operation_receipts(
    group_id, operation_id, operation_type, user_id, response,
    expected_revision, result_revision, client_metadata, server_sequence
  ) values (
    target_group_id,
    target_operation_id,
    left(target_operation_type, 120),
    target_actor_id,
    target_response,
    target_expected_revision,
    target_result_revision,
    case when jsonb_typeof(target_client_metadata) = 'object' then target_client_metadata else '{}'::jsonb end,
    target_server_sequence
  )
  on conflict (group_id, operation_id) do nothing;

  select receipts.response into stored_response
  from public.pachanga_operation_receipts receipts
  where receipts.group_id = target_group_id
    and receipts.operation_id = target_operation_id;

  return stored_response;
end;
$$;

revoke all on function private.pachanga_safe_operation_replay_v1(uuid, uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_store_safe_operation_v1(uuid, uuid, text, uuid, bigint, bigint, jsonb, jsonb, bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_accept_guest_into_match_v1(
  target_group_id uuid,
  target_match_id text,
  target_user_id uuid,
  target_name text,
  target_avatar text,
  target_avatar_offset_x numeric,
  target_avatar_offset_y numeric,
  target_birth_date date,
  target_position text,
  target_goalkeeper_only boolean,
  target_media numeric,
  target_joined_at timestamptz,
  target_source_kind text,
  target_source_id uuid,
  target_operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_match jsonb;
  existing_player jsonb;
  existing_entry jsonb;
  next_player jsonb;
  next_players jsonb;
  next_entry jsonb;
  next_match_players jsonb;
  next_match jsonb;
  next_matches jsonb;
  accepted_player_id text;
  global_profile_id uuid;
  match_target_players integer;
  reserve_limit integer;
  capacity integer;
  next_confirmed_count integer;
  next_open_slots integer;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  saved_access public.pachanga_match_guest_access%rowtype;
begin
  if target_user_id is null or target_source_id is null then
    raise exception 'Guest identity and source required';
  end if;
  if target_source_kind not in ('invitation', 'open_request') then
    raise exception 'Invalid guest source';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;

  current_payload := current_group.payload;
  select matches.value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then raise exception 'Partido no encontrado'; end if;
  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Guarda el partido antes de aceptar jugadores';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'No se pueden aceptar jugadores en partidos finalizados';
  end if;
  if coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'La alineación está cerrada';
  end if;

  select players.value into existing_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) players(value)
  where players.value ->> 'ownerUserId' = target_user_id::text
  limit 1;

  if existing_player is null then
    accepted_player_id := 'guest-' || substr(replace(target_user_id::text, '-', ''), 1, 12);
    if exists (
      select 1 from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) players(value)
      where players.value ->> 'id' = accepted_player_id
    ) then
      accepted_player_id := accepted_player_id || '-' || substr(replace(target_source_id::text, '-', ''), 1, 6);
    end if;

    next_player := jsonb_strip_nulls(jsonb_build_object(
      'id', accepted_player_id,
      'name', left(coalesce(nullif(trim(target_name), ''), 'Jugador'), 80),
      'phone', '',
      'avatar', target_avatar,
      'avatarOffsetX', target_avatar_offset_x,
      'avatarOffsetY', target_avatar_offset_y,
      'birthDate', target_birth_date,
      'position', left(coalesce(nullif(trim(target_position), ''), 'Mediocentro / pivote'), 80),
      'goalkeeperOnly', coalesce(target_goalkeeper_only, false),
      'rating', greatest(1::numeric, least(10::numeric, coalesce(target_media, 5))),
      'importedRating', greatest(1::numeric, least(10::numeric, coalesce(target_media, 5))),
      'importedRatingAt', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'importedRatingFromGroup', 'Mercado de fichajes',
      'goals', 0,
      'appearances', 0,
      'wins', 0,
      'injured', false,
      'inactive', false,
      'ownerUserId', target_user_id::text,
      'ratingVotes', '[]'::jsonb
    ));

    global_profile_id := public.upsert_pachanga_player_profile_from_player(
      target_group_id, accepted_player_id, next_player
    );
    if global_profile_id is not null then
      next_player := next_player || public.pachanga_player_profile_patch(global_profile_id);
    end if;
    next_players := coalesce(current_payload -> 'players', '[]'::jsonb) || jsonb_build_array(next_player);
  else
    accepted_player_id := existing_player ->> 'id';
    next_players := coalesce(current_payload -> 'players', '[]'::jsonb);
    select profiles.id into global_profile_id
    from public.pachanga_player_profiles profiles
    where profiles.user_id = target_user_id;
  end if;

  select participants.value into existing_entry
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) participants(value)
  where participants.value ->> 'playerId' = accepted_player_id
  limit 1;

  select count(*)::integer into next_confirmed_count
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) participants(value)
  where participants.value ->> 'status' = 'voy';

  match_target_players := greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, 0));
  reserve_limit := case
    when coalesce((selected_match ->> 'reservesAttend')::boolean, false)
      then greatest(0, coalesce((selected_match ->> 'reserveLimit')::integer, 0))
    else 0
  end;
  capacity := match_target_players + reserve_limit;

  if (existing_entry is null or existing_entry ->> 'status' <> 'voy')
    and next_confirmed_count >= capacity
  then
    raise exception 'No quedan plazas en este partido';
  end if;

  next_entry := jsonb_build_object(
    'playerId', accepted_player_id,
    'status', 'voy',
    'paid', false,
    'joinedAt', to_char(coalesce(target_joined_at, clock_timestamp()) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );

  if existing_entry is null then
    next_match_players := coalesce(selected_match -> 'players', '[]'::jsonb) || jsonb_build_array(next_entry);
  else
    select coalesce(jsonb_agg(
      case when entries.value ->> 'playerId' = accepted_player_id then entries.value || next_entry else entries.value end
      order by entries.ordinality
    ), '[]'::jsonb)
    into next_match_players
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb))
      with ordinality as entries(value, ordinality);
  end if;

  select count(*)::integer into next_confirmed_count
  from jsonb_array_elements(next_match_players) participants(value)
  where participants.value ->> 'status' = 'voy';
  next_open_slots := greatest(match_target_players - least(next_confirmed_count, match_target_players), 0);

  next_match := selected_match || jsonb_build_object(
    'players', next_match_players,
    'publicOpen', next_open_slots > 0,
    'publicOpenSlots', greatest(next_open_slots, 1)
  );

  select coalesce(jsonb_agg(
    case when entries.value ->> 'id' = target_match_id then next_match else entries.value end
    order by entries.ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb))
    with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('players', next_players, 'matches', next_matches);

  update public.pachanga_open_matches open_matches
  set confirmed_count = least(next_confirmed_count, match_target_players),
      open_slots = next_open_slots,
      active = next_open_slots > 0,
      updated_at = clock_timestamp()
  where open_matches.source_group_id = target_group_id
    and open_matches.source_match_id = target_match_id;

  update public.pachanga_groups groups
  set payload = current_payload
  where groups.id = target_group_id
  returning groups.payload, groups.payload_revision, groups.updated_at
  into saved_payload, saved_revision, saved_updated_at;

  select access.* into saved_access
  from public.pachanga_match_guest_access access
  where access.group_id = target_group_id
    and access.match_id = target_match_id
    and access.guest_user_id = target_user_id
    and access.status = 'accepted'
  order by access.server_sequence desc
  limit 1
  for update;

  if not found then
    insert into public.pachanga_match_guest_access(
      group_id, match_id, guest_user_id, player_id, source_kind, source_id, status
    ) values (
      target_group_id, target_match_id, target_user_id, accepted_player_id,
      target_source_kind, target_source_id, 'accepted'
    )
    on conflict (source_kind, source_id) do update set
      player_id = excluded.player_id,
      status = 'accepted',
      revision = public.pachanga_match_guest_access.revision + 1,
      server_sequence = nextval('public.pachanga_match_guest_sequence'),
      accepted_at = clock_timestamp(),
      revoked_at = null,
      updated_at = clock_timestamp()
    returning * into saved_access;
  end if;

  perform public.sync_pachanga_match_read_model(target_group_id, next_match, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;
  perform public.record_pachanga_group_event(
    target_group_id,
    target_match_id,
    'match_guest_accepted',
    jsonb_build_object(
      'accessId', saved_access.id,
      'playerId', accepted_player_id,
      'sourceKind', target_source_kind,
      'confirmedCount', next_confirmed_count,
      'openSlots', next_open_slots,
      'payloadRevision', saved_revision
    ),
    target_operation_id,
    true
  );

  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at,
    'accessId', saved_access.id,
    'accessRevision', saved_access.revision,
    'playerId', accepted_player_id
  );
end;
$$;

revoke all on function private.pachanga_accept_guest_into_match_v1(uuid, text, uuid, text, text, numeric, numeric, date, text, boolean, numeric, timestamptz, text, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_open_request_notification_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  admin_member record;
  selected_group_name text;
  selected_match_title text;
  selected_access_id uuid;
begin
  select groups.name into selected_group_name
  from public.pachanga_groups groups
  where groups.id = new.source_group_id;

  select open_matches.title into selected_match_title
  from public.pachanga_open_matches open_matches
  where open_matches.id = new.open_match_id;

  if new.status = 'pending'
    and (tg_op = 'INSERT' or old.status is distinct from new.status)
  then
    for admin_member in
      select members.user_id
      from public.pachanga_group_members members
      where members.group_id = new.source_group_id
        and members.role in ('owner', 'admin')
    loop
      perform private.pachanga_notify_v1(
        admin_member.user_id,
        'open_match_request',
        'Nueva solicitud de plaza',
        left(coalesce(new.requester_name, 'Un jugador'), 80) || ' quiere unirse a ' || left(coalesce(selected_match_title, 'tu partido'), 120) || '.',
        '/?mobile=partido&p=' || replace(new.source_match_id, '-', ''),
        jsonb_build_object(
          'requestId', new.id,
          'openMatchId', new.open_match_id,
          'status', new.status,
          'requestRevision', new.revision
        ),
        'open-request-admin:' || new.id::text || ':pending:' || admin_member.user_id::text
      );
    end loop;
  elsif new.status in ('accepted', 'rejected', 'cancelled')
    and (tg_op = 'INSERT' or old.status is distinct from new.status)
  then
    select access.id into selected_access_id
    from public.pachanga_match_guest_access access
    where access.group_id = new.source_group_id
      and access.match_id = new.source_match_id
      and access.guest_user_id = new.requester_user_id
      and access.status = 'accepted'
    order by access.server_sequence desc
    limit 1;

    perform private.pachanga_notify_v1(
      new.requester_user_id,
      'open_match_request_' || new.status,
      case
        when new.status = 'accepted' then 'Solicitud aceptada'
        when new.status = 'rejected' then 'Solicitud rechazada'
        else 'Solicitud cancelada'
      end,
      case
        when new.status = 'accepted' then 'Ya puedes consultar el partido de ' || left(coalesce(selected_group_name, 'Pachangas IQ'), 120) || '.'
        when new.status = 'rejected' then left(coalesce(selected_group_name, 'El equipo'), 120) || ' no ha aceptado esta solicitud.'
        else 'La solicitud ya no está activa.'
      end,
      case when new.status = 'accepted' and selected_access_id is not null
        then '/partido-invitado?acceso=' || selected_access_id::text
        else null
      end,
      jsonb_strip_nulls(jsonb_build_object(
        'requestId', new.id,
        'openMatchId', new.open_match_id,
        'status', new.status,
        'requestRevision', new.revision,
        'accessId', selected_access_id
      )),
      'open-request-user:' || new.id::text || ':' || new.status
    );

    for admin_member in
      select members.user_id
      from public.pachanga_group_members members
      where members.group_id = new.source_group_id
        and members.role in ('owner', 'admin')
    loop
      perform private.pachanga_notify_v1(
        admin_member.user_id,
        'open_match_request_' || new.status,
        case
          when new.status = 'accepted' then 'Solicitud de plaza aceptada'
          when new.status = 'rejected' then 'Solicitud de plaza rechazada'
          else 'Solicitud de plaza cancelada'
        end,
        case
          when new.status = 'accepted'
            then left(coalesce(new.requester_name, 'Un jugador'), 80) || ' se ha incorporado a ' || left(coalesce(selected_match_title, 'tu partido'), 120) || '.'
          when new.status = 'rejected'
            then 'La solicitud de ' || left(coalesce(new.requester_name, 'un jugador'), 80) || ' ha sido rechazada.'
          else left(coalesce(new.requester_name, 'Un jugador'), 80) || ' ha retirado su solicitud para ' || left(coalesce(selected_match_title, 'tu partido'), 120) || '.'
        end,
        '/?mobile=partido&p=' || replace(new.source_match_id, '-', ''),
        jsonb_build_object(
          'requestId', new.id,
          'openMatchId', new.open_match_id,
          'status', new.status,
          'requestRevision', new.revision
        ),
        'open-request-admin:' || new.id::text || ':pending:' || admin_member.user_id::text
      );
    end loop;
  end if;

  return new;
end;
$$;

revoke all on function private.pachanga_open_request_notification_trigger_v1()
  from public, anon, authenticated;

drop trigger if exists notify_pachanga_open_match_request on public.pachanga_open_match_requests;
create trigger notify_pachanga_open_match_request
after insert or update of status on public.pachanga_open_match_requests
for each row execute function private.pachanga_open_request_notification_trigger_v1();

create or replace function private.pachanga_bump_open_request_revision_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.revision := old.revision + 1;
  new.server_sequence := nextval('public.pachanga_match_guest_sequence');
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function private.pachanga_bump_open_request_revision_v1()
  from public, anon, authenticated;

drop trigger if exists bump_pachanga_open_match_request_revision on public.pachanga_open_match_requests;
create trigger bump_pachanga_open_match_request_revision
before update on public.pachanga_open_match_requests
for each row execute function private.pachanga_bump_open_request_revision_v1();

create or replace function public.review_pachanga_open_match_request(
  target_request_id uuid,
  next_status text,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  selected_request public.pachanga_open_match_requests%rowtype;
  selected_open public.pachanga_open_matches%rowtype;
  current_group public.pachanga_groups%rowtype;
  existing_response jsonb;
  operation_response jsonb;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  if not public.is_registered_pachanga_user() then raise exception 'Registered user required'; end if;
  if next_status not in ('accepted', 'rejected') then raise exception 'Estado de solicitud no válido'; end if;

  select * into selected_request
  from public.pachanga_open_match_requests requests
  where requests.id = target_request_id
  for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  if not public.is_pachanga_group_admin(selected_request.source_group_id) then
    raise exception 'Solo los admins pueden revisar solicitudes';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_request.source_group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;

  if operation_key is not null then
    select receipts.response into existing_response
    from public.pachanga_operation_receipts receipts
    where receipts.group_id = selected_request.source_group_id
      and receipts.operation_id = operation_key;
    if existing_response is not null then return existing_response; end if;
  end if;

  if selected_request.status = next_status then
    operation_response := jsonb_build_object(
      'payload', current_group.payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );
    return public.remember_pachanga_operation(
      selected_request.source_group_id,
      operation_key,
      'open_match_request_already_decided',
      operation_response
    );
  end if;
  if selected_request.status <> 'pending' then raise exception 'La solicitud ya estaba decidida'; end if;

  if next_status = 'rejected' then
    update public.pachanga_open_match_requests requests
    set status = 'rejected',
        decided_by = current_user_id,
        decided_at = clock_timestamp()
    where requests.id = selected_request.id;

    perform public.record_pachanga_group_event(
      selected_request.source_group_id,
      selected_request.source_match_id,
      'open_match_request_rejected',
      jsonb_build_object('requestId', selected_request.id),
      operation_key,
      true
    );

    operation_response := jsonb_build_object(
      'payload', current_group.payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );
    return public.remember_pachanga_operation(
      selected_request.source_group_id,
      operation_key,
      'open_match_request_rejected',
      operation_response
    );
  end if;

  select * into selected_open
  from public.pachanga_open_matches open_matches
  where open_matches.id = selected_request.open_match_id
  for update;
  if not found or not selected_open.active then
    raise exception 'El partido abierto ya no está disponible';
  end if;

  operation_response := private.pachanga_accept_guest_into_match_v1(
    selected_request.source_group_id,
    selected_request.source_match_id,
    selected_request.requester_user_id,
    selected_request.requester_name,
    selected_request.avatar,
    selected_request.avatar_offset_x,
    selected_request.avatar_offset_y,
    selected_request.birth_date,
    selected_request.position,
    selected_request.goalkeeper_only,
    selected_request.media,
    selected_request.requested_at,
    'open_request',
    selected_request.id,
    operation_key
  );

  update public.pachanga_open_match_requests requests
  set status = 'accepted',
      player_id = operation_response ->> 'playerId',
      decided_by = current_user_id,
      decided_at = clock_timestamp()
  where requests.id = selected_request.id;

  return public.remember_pachanga_operation(
    selected_request.source_group_id,
    operation_key,
    'open_match_request_accepted',
    operation_response
  );
end;
$$;

revoke all on function public.review_pachanga_open_match_request(uuid, text, uuid)
  from public, anon, authenticated;

create or replace function public.request_pachanga_open_match_authoritative_v2_impl(
  target_open_match_id uuid,
  operation_id uuid,
  expected_match_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_operation_id uuid := operation_id;
  selected_open public.pachanga_open_matches%rowtype;
  current_group public.pachanga_groups%rowtype;
  selected_request public.pachanga_open_match_requests%rowtype;
  replay jsonb;
  replay_actor uuid;
  legacy_result jsonb;
  confirmed_open public.pachanga_open_matches%rowtype;
  final_response jsonb;
  normalized_client_metadata jsonb := case
    when jsonb_typeof(client_metadata) = 'object' then client_metadata
    else '{}'::jsonb
  end;
begin
  if auth.uid() is null or operation_id is null or expected_match_revision is null then
    raise exception 'Authentication, operation id and expected match revision required';
  end if;

  select * into selected_open
  from public.pachanga_open_matches open_matches
  where open_matches.id = target_open_match_id
  for update;
  if not found then raise exception 'Open match not found'; end if;

  select receipts.response, receipts.user_id into replay, replay_actor
  from public.pachanga_operation_receipts receipts
  where receipts.group_id = selected_open.source_group_id
    and receipts.operation_id = actor_operation_id;
  if replay is not null then
    if replay_actor is distinct from auth.uid() then raise exception 'Operation belongs to another actor'; end if;
    return replay;
  end if;
  if selected_open.source_payload_revision <> expected_match_revision then
    raise exception 'Match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_open.source_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;

  legacy_result := public.request_pachanga_open_match(target_open_match_id, operation_id);

  select * into selected_request
  from public.pachanga_open_match_requests requests
  where requests.open_match_id = target_open_match_id
    and requests.requester_user_id = auth.uid();
  if not found then raise exception 'Confirmed request not found'; end if;

  select * into confirmed_open
  from public.pachanga_open_matches open_matches
  where open_matches.id = target_open_match_id;

  final_response := jsonb_build_object(
    'operationId', operation_id,
    'expectedRevision', expected_match_revision,
    'confirmedRevision', confirmed_open.source_payload_revision,
    'confirmedAt', clock_timestamp(),
    'request', jsonb_build_object(
      'id', selected_request.id,
      'openMatchId', selected_request.open_match_id,
      'status', selected_request.status,
      'revision', selected_request.revision,
      'serverSequence', selected_request.server_sequence
    ),
    'openMatch', jsonb_build_object(
      'id', confirmed_open.id,
      'active', confirmed_open.active,
      'confirmedCount', confirmed_open.confirmed_count,
      'openSlots', confirmed_open.open_slots,
      'sourcePayloadRevision', confirmed_open.source_payload_revision
    )
  );

  update public.pachanga_operation_receipts receipts
  set response = final_response,
      expected_revision = expected_match_revision,
      result_revision = confirmed_open.source_payload_revision,
      client_metadata = normalized_client_metadata
  where receipts.group_id = selected_open.source_group_id
    and receipts.operation_id = actor_operation_id
    and receipts.user_id = auth.uid();

  return final_response;
end;
$$;

revoke all on function public.request_pachanga_open_match_authoritative_v2_impl(uuid, uuid, bigint, jsonb)
  from public, anon, authenticated;

create or replace function public.create_pachanga_match_invitation_v1(
  target_group_id uuid,
  target_match_id text,
  target_market_profile_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_id uuid := auth.uid();
  current_group public.pachanga_groups%rowtype;
  target_profile public.pachanga_market_profiles%rowtype;
  selected_match jsonb;
  saved_invitation public.pachanga_match_invitations%rowtype;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;

  replay := private.pachanga_safe_operation_replay_v1(
    target_group_id, operation_id, actor_id, 'match_invitation_create_v1'
  );
  if replay is not null then return replay; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Solo los admins pueden invitar jugadores';
  end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select matches.value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = target_match_id
  limit 1;
  if selected_match is null then raise exception 'Partido no encontrado'; end if;
  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Guarda el partido antes de invitar jugadores';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'No se puede invitar a un partido finalizado';
  end if;
  if coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'La alineación está cerrada';
  end if;

  select * into target_profile
  from public.pachanga_market_profiles profiles
  where profiles.id = target_market_profile_id
    and profiles.active
    and profiles.open_to_guest
  for update;
  if not found then raise exception 'El jugador ya no acepta invitaciones puntuales'; end if;
  if target_profile.user_id = actor_id then raise exception 'No puedes invitarte a ti mismo'; end if;
  if exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = target_group_id and members.user_id = target_profile.user_id
  ) then
    raise exception 'El jugador ya pertenece al grupo';
  end if;
  if exists (
    select 1 from public.pachanga_match_guest_access access
    where access.group_id = target_group_id
      and access.match_id = target_match_id
      and access.guest_user_id = target_profile.user_id
      and access.status = 'accepted'
  ) then
    raise exception 'El jugador ya tiene acceso al partido';
  end if;

  select * into saved_invitation
  from public.pachanga_match_invitations invitations
  where invitations.group_id = target_group_id
    and invitations.match_id = target_match_id
    and invitations.invitee_user_id = target_profile.user_id
    and invitations.status = 'pending'
  order by invitations.server_sequence desc
  limit 1
  for update;

  if not found then
    insert into public.pachanga_match_invitations(
      group_id, match_id, target_market_profile_id, invitee_user_id, inviter_user_id,
      invitee_name, invitee_avatar, invitee_avatar_offset_x, invitee_avatar_offset_y,
      invitee_birth_date, invitee_position, invitee_goalkeeper_only, invitee_media
    ) values (
      target_group_id, target_match_id, target_profile.id, target_profile.user_id, actor_id,
      left(target_profile.display_name, 80), target_profile.avatar, target_profile.avatar_offset_x,
      target_profile.avatar_offset_y, target_profile.birth_date, target_profile.position,
      target_profile.goalkeeper_only, target_profile.media
    )
    returning * into saved_invitation;
  end if;

  perform private.pachanga_notify_v1(
    saved_invitation.invitee_user_id,
    'match_invitation',
    'Invitación a un partido',
    left(current_group.name, 120) || ' te invita a ' || left(coalesce(selected_match ->> 'title', 'un partido'), 120) || '.',
    null,
    jsonb_build_object(
      'invitationId', saved_invitation.id,
      'status', saved_invitation.status,
      'invitationRevision', saved_invitation.revision,
      'matchRevision', current_group.payload_revision
    ),
    'match-invitation:' || saved_invitation.id::text || ':invitee'
  );

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', current_group.payload_revision,
    'invitation', jsonb_build_object(
      'id', saved_invitation.id,
      'status', saved_invitation.status,
      'revision', saved_invitation.revision,
      'serverSequence', saved_invitation.server_sequence,
      'inviteeName', saved_invitation.invitee_name,
      'targetMarketProfileId', saved_invitation.target_market_profile_id
    )
  );

  return private.pachanga_store_safe_operation_v1(
    target_group_id, operation_id, 'match_invitation_create_v1', actor_id,
    expected_revision, current_group.payload_revision, client_metadata,
    response, saved_invitation.server_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.create_pachanga_match_invitation_v1(uuid, text, uuid, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.create_pachanga_match_invitation_v1(uuid, text, uuid, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.respond_pachanga_match_invitation_v1(
  target_invitation_id uuid,
  next_status text,
  operation_id uuid,
  expected_invitation_revision bigint,
  expected_match_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_id uuid := auth.uid();
  selected_invitation public.pachanga_match_invitations%rowtype;
  current_group public.pachanga_groups%rowtype;
  acceptance jsonb;
  saved_access_id uuid;
  result_revision bigint;
  result_sequence bigint;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or operation_id is null
    or expected_invitation_revision is null or expected_match_revision is null
  then
    raise exception 'Authentication, operation id and revisions required';
  end if;
  if next_status not in ('accepted', 'rejected') then raise exception 'Respuesta no válida'; end if;

  select * into selected_invitation
  from public.pachanga_match_invitations invitations
  where invitations.id = target_invitation_id
  for update;
  if not found then raise exception 'Invitación no encontrada'; end if;
  if selected_invitation.invitee_user_id <> actor_id then
    raise exception 'Solo el jugador invitado puede responder';
  end if;

  replay := private.pachanga_safe_operation_replay_v1(
    selected_invitation.group_id, operation_id, actor_id, 'match_invitation_respond_v1'
  );
  if replay is not null then return replay; end if;
  if selected_invitation.revision <> expected_invitation_revision then
    raise exception 'Invitation revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected_invitation.status <> 'pending' then raise exception 'La invitación ya estaba decidida'; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_invitation.group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;
  if current_group.payload_revision <> expected_match_revision then
    raise exception 'Match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  if next_status = 'accepted' then
    acceptance := private.pachanga_accept_guest_into_match_v1(
      selected_invitation.group_id,
      selected_invitation.match_id,
      selected_invitation.invitee_user_id,
      selected_invitation.invitee_name,
      selected_invitation.invitee_avatar,
      selected_invitation.invitee_avatar_offset_x,
      selected_invitation.invitee_avatar_offset_y,
      selected_invitation.invitee_birth_date,
      selected_invitation.invitee_position,
      selected_invitation.invitee_goalkeeper_only,
      selected_invitation.invitee_media,
      selected_invitation.created_at,
      'invitation',
      selected_invitation.id,
      operation_id
    );
    saved_access_id := (acceptance ->> 'accessId')::uuid;
    result_revision := (acceptance ->> 'payload_revision')::bigint;
  else
    result_revision := current_group.payload_revision;
  end if;

  update public.pachanga_match_invitations invitations
  set status = next_status,
      revision = invitations.revision + 1,
      server_sequence = nextval('public.pachanga_match_guest_sequence'),
      responded_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where invitations.id = selected_invitation.id
  returning invitations.server_sequence into result_sequence;

  perform private.pachanga_notify_v1(
    actor_id,
    'match_invitation_' || next_status,
    case when next_status = 'accepted' then 'Invitación aceptada' else 'Invitación rechazada' end,
    case when next_status = 'accepted'
      then 'Ya puedes consultar el partido y seguir sus cambios en tiempo real.'
      else 'Has rechazado la invitación.'
    end,
    case when saved_access_id is not null then '/partido-invitado?acceso=' || saved_access_id::text else null end,
    jsonb_strip_nulls(jsonb_build_object(
      'invitationId', selected_invitation.id,
      'status', next_status,
      'invitationRevision', expected_invitation_revision + 1,
      'matchRevision', result_revision,
      'accessId', saved_access_id
    )),
    'match-invitation:' || selected_invitation.id::text || ':invitee'
  );

  perform private.pachanga_notify_v1(
    selected_invitation.inviter_user_id,
    'match_invitation_response',
    case when next_status = 'accepted' then 'Invitación aceptada' else 'Invitación rechazada' end,
    left(selected_invitation.invitee_name, 80) || case when next_status = 'accepted' then ' irá al partido.' else ' ha rechazado la invitación.' end,
    '/?mobile=partido&p=' || replace(selected_invitation.match_id, '-', ''),
    jsonb_build_object(
      'invitationId', selected_invitation.id,
      'status', next_status,
      'matchRevision', result_revision
    ),
    'match-invitation:' || selected_invitation.id::text || ':inviter:' || next_status
  );

  response := jsonb_strip_nulls(jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', result_revision,
    'invitation', jsonb_build_object(
      'id', selected_invitation.id,
      'status', next_status,
      'revision', expected_invitation_revision + 1,
      'serverSequence', result_sequence
    ),
    'accessId', saved_access_id
  ));

  return private.pachanga_store_safe_operation_v1(
    selected_invitation.group_id, operation_id, 'match_invitation_respond_v1', actor_id,
    expected_match_revision, result_revision, client_metadata, response, result_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.respond_pachanga_match_invitation_v1(uuid, text, uuid, bigint, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.respond_pachanga_match_invitation_v1(uuid, text, uuid, bigint, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.cancel_pachanga_match_invitation_v1(
  target_invitation_id uuid,
  operation_id uuid,
  expected_invitation_revision bigint,
  expected_match_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_id uuid := auth.uid();
  selected_invitation public.pachanga_match_invitations%rowtype;
  current_group public.pachanga_groups%rowtype;
  result_sequence bigint;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or operation_id is null
    or expected_invitation_revision is null or expected_match_revision is null
  then
    raise exception 'Authentication, operation id and revisions required';
  end if;

  select * into selected_invitation
  from public.pachanga_match_invitations invitations
  where invitations.id = target_invitation_id
  for update;
  if not found then raise exception 'Invitación no encontrada'; end if;

  replay := private.pachanga_safe_operation_replay_v1(
    selected_invitation.group_id, operation_id, actor_id, 'match_invitation_cancel_v1'
  );
  if replay is not null then return replay; end if;
  if not public.is_pachanga_group_admin(selected_invitation.group_id) then
    raise exception 'Solo los admins pueden cancelar invitaciones';
  end if;
  if selected_invitation.revision <> expected_invitation_revision then
    raise exception 'Invitation revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected_invitation.status <> 'pending' then raise exception 'La invitación ya estaba decidida'; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_invitation.group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;
  if current_group.payload_revision <> expected_match_revision then
    raise exception 'Match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  update public.pachanga_match_invitations invitations
  set status = 'cancelled',
      revision = invitations.revision + 1,
      server_sequence = nextval('public.pachanga_match_guest_sequence'),
      cancelled_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where invitations.id = selected_invitation.id
  returning invitations.server_sequence into result_sequence;

  perform private.pachanga_notify_v1(
    selected_invitation.invitee_user_id,
    'match_invitation_cancelled',
    'Invitación cancelada',
    left(current_group.name, 120) || ' ha cancelado la invitación.',
    null,
    jsonb_build_object(
      'invitationId', selected_invitation.id,
      'status', 'cancelled',
      'invitationRevision', expected_invitation_revision + 1,
      'matchRevision', current_group.payload_revision
    ),
    'match-invitation:' || selected_invitation.id::text || ':invitee'
  );

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', current_group.payload_revision,
    'invitation', jsonb_build_object(
      'id', selected_invitation.id,
      'status', 'cancelled',
      'revision', expected_invitation_revision + 1,
      'serverSequence', result_sequence
    )
  );

  return private.pachanga_store_safe_operation_v1(
    selected_invitation.group_id, operation_id, 'match_invitation_cancel_v1', actor_id,
    expected_match_revision, current_group.payload_revision, client_metadata, response, result_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.cancel_pachanga_match_invitation_v1(uuid, uuid, bigint, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.cancel_pachanga_match_invitation_v1(uuid, uuid, bigint, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.get_pachanga_notification_center_v1()
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  with recent_notifications as (
    select notifications.*
    from public.pachanga_user_notifications notifications
    where notifications.recipient_user_id = auth.uid()
    order by notifications.server_sequence desc, notifications.id desc
    limit 120
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', notifications.id,
      'kind', notifications.kind,
      'title', notifications.title,
      'body', notifications.body,
      'actionUrl', notifications.action_url,
      'payload', notifications.payload,
      'readAt', notifications.read_at,
      'revision', notifications.revision,
      'serverSequence', notifications.server_sequence,
      'createdAt', notifications.created_at,
      'updatedAt', notifications.updated_at,
      'context', jsonb_strip_nulls(jsonb_build_object(
        'invitationId', invitations.id,
        'invitationStatus', invitations.status,
        'invitationRevision', invitations.revision,
        'matchRevision', coalesce(snapshots.source_payload_revision, groups.payload_revision),
        'accessId', guest_access.id,
        'accessStatus', guest_access.status,
        'reviewId', reviews.id,
        'reviewStatus', reviews.status,
        'reviewRevision', reviews.revision,
        'groupRevision', review_groups.payload_revision,
        'requestId', open_requests.id,
        'requestGroupId', open_requests.source_group_id,
        'requestGroupRevision', request_groups.payload_revision,
        'requestStatus', open_requests.status,
        'requestRevision', open_requests.revision
      ))
    )
    order by notifications.server_sequence desc, notifications.id desc
  ), '[]'::jsonb)
  from recent_notifications notifications
  left join public.pachanga_match_invitations invitations
    on invitations.id::text = notifications.payload ->> 'invitationId'
    and invitations.invitee_user_id = auth.uid()
  left join public.pachanga_match_guest_snapshots snapshots
    on snapshots.group_id = invitations.group_id and snapshots.match_id = invitations.match_id
  left join public.pachanga_groups groups on groups.id = invitations.group_id
  left join public.pachanga_match_guest_access guest_access
    on guest_access.id::text = notifications.payload ->> 'accessId'
    and guest_access.guest_user_id = auth.uid()
  left join public.pachanga_guest_withdrawal_reviews reviews
    on reviews.id::text = notifications.payload ->> 'reviewId'
    and public.is_pachanga_group_admin(reviews.group_id)
  left join public.pachanga_groups review_groups on review_groups.id = reviews.group_id
  left join public.pachanga_open_match_requests open_requests
    on open_requests.id::text = notifications.payload ->> 'requestId'
    and (
      open_requests.requester_user_id = auth.uid()
      or public.is_pachanga_group_admin(open_requests.source_group_id)
    )
  left join public.pachanga_groups request_groups on request_groups.id = open_requests.source_group_id
  ;
$$;

revoke all on function public.get_pachanga_notification_center_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_notification_center_v1()
  to authenticated, service_role;

create or replace function public.mark_pachanga_notification_read_v1(
  target_notification_id uuid,
  operation_id uuid,
  expected_revision bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  actor_operation_id uuid := operation_id;
  current_notification public.pachanga_user_notifications%rowtype;
  saved_receipt private.pachanga_notification_operation_receipts%rowtype;
  response jsonb;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;

  select * into saved_receipt
  from private.pachanga_notification_operation_receipts receipts
  where receipts.operation_id = actor_operation_id;
  if found then
    if saved_receipt.actor_user_id <> actor_id
      or saved_receipt.notification_id <> target_notification_id
    then
      raise exception 'Operation belongs to another action';
    end if;
    return saved_receipt.response;
  end if;

  select * into current_notification
  from public.pachanga_user_notifications notifications
  where notifications.id = target_notification_id
    and notifications.recipient_user_id = actor_id
  for update;
  if not found then raise exception 'Notificación no encontrada'; end if;
  if current_notification.revision <> expected_revision then
    raise exception 'Notification revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  if current_notification.read_at is null then
    update public.pachanga_user_notifications notifications
    set read_at = clock_timestamp(),
        revision = notifications.revision + 1,
        server_sequence = nextval('public.pachanga_match_guest_sequence'),
        updated_at = clock_timestamp()
    where notifications.id = current_notification.id
    returning * into current_notification;
  end if;

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'notification', jsonb_build_object(
      'id', current_notification.id,
      'revision', current_notification.revision,
      'serverSequence', current_notification.server_sequence,
      'readAt', current_notification.read_at
    )
  );

  insert into private.pachanga_notification_operation_receipts(
    operation_id, actor_user_id, notification_id, response, server_sequence
  ) values (
    actor_operation_id, actor_id, current_notification.id, response, current_notification.server_sequence
  );

  return response;
end;
$$;

revoke all on function public.mark_pachanga_notification_read_v1(uuid, uuid, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.mark_pachanga_notification_read_v1(uuid, uuid, bigint)
  to authenticated, service_role;

create or replace function public.get_pachanga_guest_match_snapshot_v1(target_access_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  selected_access public.pachanga_match_guest_access%rowtype;
  selected_snapshot public.pachanga_match_guest_snapshots%rowtype;
begin
  if actor_id is null then raise exception 'Authentication required'; end if;

  select * into selected_access
  from public.pachanga_match_guest_access access
  where access.id = target_access_id
    and access.guest_user_id = actor_id;
  if not found then raise exception 'Acceso no encontrado'; end if;
  if selected_access.status <> 'accepted' then
    return jsonb_build_object(
      'access', jsonb_build_object(
        'id', selected_access.id,
        'groupId', selected_access.group_id,
        'matchId', selected_access.match_id,
        'status', selected_access.status,
        'revision', selected_access.revision,
        'serverSequence', selected_access.server_sequence
      )
    );
  end if;

  select * into selected_snapshot
  from public.pachanga_match_guest_snapshots snapshots
  where snapshots.group_id = selected_access.group_id
    and snapshots.match_id = selected_access.match_id;
  if not found then raise exception 'El partido ya no está disponible'; end if;

  return jsonb_build_object(
    'access', jsonb_build_object(
      'id', selected_access.id,
      'groupId', selected_access.group_id,
      'matchId', selected_access.match_id,
      'status', selected_access.status,
      'revision', selected_access.revision,
      'serverSequence', selected_access.server_sequence,
      'acceptedAt', selected_access.accepted_at
    ),
    'snapshotId', selected_snapshot.id,
    'snapshot', selected_snapshot.snapshot,
    'snapshotRevision', selected_snapshot.snapshot_revision,
    'sourcePayloadRevision', selected_snapshot.source_payload_revision,
    'serverSequence', selected_snapshot.server_sequence,
    'updatedAt', selected_snapshot.updated_at
  );
end;
$$;

revoke all on function public.get_pachanga_guest_match_snapshot_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_guest_match_snapshot_v1(uuid)
  to authenticated, service_role;

create or replace function public.leave_pachanga_guest_match_v1(
  target_access_id uuid,
  operation_id uuid,
  expected_snapshot_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_id uuid := auth.uid();
  selected_access public.pachanga_match_guest_access%rowtype;
  current_group public.pachanga_groups%rowtype;
  current_snapshot public.pachanga_match_guest_snapshots%rowtype;
  selected_match jsonb;
  next_match_players jsonb;
  next_team_a jsonb;
  next_team_b jsonb;
  next_slots_a jsonb;
  next_slots_b jsonb;
  next_match jsonb;
  next_matches jsonb;
  next_confirmed_count integer;
  match_target_players integer;
  next_open_slots integer;
  saved_revision bigint;
  saved_updated_at timestamptz;
  saved_review public.pachanga_guest_withdrawal_reviews%rowtype;
  guest_display_name text;
  response jsonb;
  replay jsonb;
  admin_member record;
begin
  if actor_id is null or operation_id is null or expected_snapshot_revision is null then
    raise exception 'Authentication, operation id and expected snapshot revision required';
  end if;

  select * into selected_access
  from public.pachanga_match_guest_access access
  where access.id = target_access_id
  for update;
  if not found then raise exception 'Acceso no encontrado'; end if;
  if selected_access.guest_user_id <> actor_id then
    raise exception 'Solo el invitado puede abandonar el partido';
  end if;

  replay := private.pachanga_safe_operation_replay_v1(
    selected_access.group_id, operation_id, actor_id, 'match_guest_leave_v1'
  );
  if replay is not null then return replay; end if;
  if selected_access.status <> 'accepted' then raise exception 'El acceso ya no está activo'; end if;

  select * into current_snapshot
  from public.pachanga_match_guest_snapshots snapshots
  where snapshots.group_id = selected_access.group_id
    and snapshots.match_id = selected_access.match_id
  for update;
  if not found then raise exception 'El partido ya no está disponible'; end if;
  if expected_snapshot_revision > current_snapshot.snapshot_revision then
    raise exception 'Snapshot revision is invalid. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_access.group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;

  select matches.value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = selected_access.match_id
  limit 1;
  if selected_match is null then raise exception 'Partido no encontrado'; end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'No se puede abandonar un partido finalizado';
  end if;
  if not exists (
    select 1
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) participants(value)
    where participants.value ->> 'playerId' = selected_access.player_id
      and participants.value ->> 'status' = 'voy'
  ) then
    raise exception 'Ya no figuras como asistente';
  end if;

  select left(coalesce(nullif(trim(players.value ->> 'name'), ''), 'Invitado'), 80)
  into guest_display_name
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) players(value)
  where players.value ->> 'id' = selected_access.player_id
  limit 1;
  guest_display_name := coalesce(guest_display_name, 'Invitado');

  select coalesce(jsonb_agg(
    case when entries.value ->> 'playerId' = selected_access.player_id
      then entries.value || jsonb_build_object('status', 'no', 'paid', false)
      else entries.value end
    order by entries.ordinality
  ), '[]'::jsonb)
  into next_match_players
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb))
    with ordinality as entries(value, ordinality);

  select coalesce(jsonb_agg(entries.value order by entries.ordinality), '[]'::jsonb)
  into next_team_a
  from jsonb_array_elements(coalesce(selected_match -> 'teamA', '[]'::jsonb))
    with ordinality as entries(value, ordinality)
  where entries.value #>> '{}' <> selected_access.player_id;

  select coalesce(jsonb_agg(entries.value order by entries.ordinality), '[]'::jsonb)
  into next_team_b
  from jsonb_array_elements(coalesce(selected_match -> 'teamB', '[]'::jsonb))
    with ordinality as entries(value, ordinality)
  where entries.value #>> '{}' <> selected_access.player_id;

  select coalesce(jsonb_agg(
    case when entries.value #>> '{}' = selected_access.player_id then 'null'::jsonb else entries.value end
    order by entries.ordinality
  ), '[]'::jsonb)
  into next_slots_a
  from jsonb_array_elements(coalesce(selected_match -> 'lineupSlots' -> 'teamA', '[]'::jsonb))
    with ordinality as entries(value, ordinality);

  select coalesce(jsonb_agg(
    case when entries.value #>> '{}' = selected_access.player_id then 'null'::jsonb else entries.value end
    order by entries.ordinality
  ), '[]'::jsonb)
  into next_slots_b
  from jsonb_array_elements(coalesce(selected_match -> 'lineupSlots' -> 'teamB', '[]'::jsonb))
    with ordinality as entries(value, ordinality);

  select count(*)::integer into next_confirmed_count
  from jsonb_array_elements(next_match_players) participants(value)
  where participants.value ->> 'status' = 'voy';
  match_target_players := greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, 0));
  next_open_slots := greatest(match_target_players - least(next_confirmed_count, match_target_players), 0);

  next_match := selected_match || jsonb_build_object(
    'players', next_match_players,
    'teamA', next_team_a,
    'teamB', next_team_b,
    'lineupSlots', jsonb_build_object('teamA', next_slots_a, 'teamB', next_slots_b),
    'publicOpen', next_open_slots > 0,
    'publicOpenSlots', greatest(next_open_slots, 1)
  );

  select coalesce(jsonb_agg(
    case when entries.value ->> 'id' = selected_access.match_id then next_match else entries.value end
    order by entries.ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb))
    with ordinality as entries(value, ordinality);

  update public.pachanga_match_guest_access access
  set status = 'revoked',
      revision = access.revision + 1,
      server_sequence = nextval('public.pachanga_match_guest_sequence'),
      revoked_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where access.id = selected_access.id
  returning * into selected_access;

  if selected_access.source_kind = 'open_request' then
    update public.pachanga_open_match_requests requests
    set status = 'cancelled',
        decided_by = actor_id,
        decided_at = clock_timestamp(),
        decision_note = 'guest_left'
    where requests.id = selected_access.source_id
      and requests.requester_user_id = actor_id
      and requests.status = 'accepted';
  end if;

  update public.pachanga_open_matches open_matches
  set confirmed_count = least(next_confirmed_count, match_target_players),
      open_slots = next_open_slots,
      active = next_open_slots > 0,
      updated_at = clock_timestamp()
  where open_matches.source_group_id = selected_access.group_id
    and open_matches.source_match_id = selected_access.match_id;

  update public.pachanga_groups groups
  set payload = current_group.payload || jsonb_build_object('matches', next_matches)
  where groups.id = selected_access.group_id
  returning groups.payload_revision, groups.updated_at into saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(selected_access.group_id, next_match, saved_revision);

  insert into public.pachanga_guest_withdrawal_reviews(
    access_id, group_id, match_id, guest_user_id, player_id
  ) values (
    selected_access.id, selected_access.group_id, selected_access.match_id,
    selected_access.guest_user_id, selected_access.player_id
  )
  on conflict (access_id) do update set
    updated_at = public.pachanga_guest_withdrawal_reviews.updated_at
  returning * into saved_review;

  perform public.record_pachanga_group_event(
    selected_access.group_id,
    selected_access.match_id,
    'match_guest_left',
    jsonb_build_object(
      'accessId', selected_access.id,
      'withdrawalReviewId', saved_review.id,
      'playerId', selected_access.player_id,
      'payloadRevision', saved_revision
    ),
    operation_id,
    true
  );

  perform private.pachanga_notify_v1(
    actor_id,
    'match_guest_left',
    'Has abandonado el partido',
    'Tu plaza se ha liberado y ya no puedes consultar este partido.',
    null,
    jsonb_build_object('accessId', selected_access.id, 'status', 'revoked'),
    'match-guest-left:' || selected_access.id::text || ':guest'
  );

  for admin_member in
    select members.user_id
    from public.pachanga_group_members members
    where members.group_id = selected_access.group_id
      and members.role in ('owner', 'admin')
  loop
    perform private.pachanga_notify_v1(
      admin_member.user_id,
      'match_guest_withdrawal_review',
      guest_display_name || ' ha abandonado',
      'Revisa únicamente si debe constar el abandono de este partido.',
      '/?mobile=partido&p=' || replace(selected_access.match_id, '-', ''),
      jsonb_build_object(
        'reviewId', saved_review.id,
        'reviewStatus', saved_review.status,
        'reviewRevision', saved_review.revision,
        'groupRevision', saved_revision
      ),
      'match-guest-left:' || selected_access.id::text || ':admin:' || admin_member.user_id::text
    );
  end loop;

  response := jsonb_strip_nulls(jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', saved_revision,
    'access', jsonb_build_object(
      'id', selected_access.id,
      'status', selected_access.status,
      'revision', selected_access.revision,
      'serverSequence', selected_access.server_sequence
    ),
    'withdrawalReviewId', saved_review.id,
    'reconciledFromRevision', case
      when expected_snapshot_revision <> current_snapshot.snapshot_revision then expected_snapshot_revision
      else null
    end
  ));

  return private.pachanga_store_safe_operation_v1(
    selected_access.group_id, operation_id, 'match_guest_leave_v1', actor_id,
    expected_snapshot_revision, saved_revision, client_metadata, response,
    selected_access.server_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.leave_pachanga_guest_match_v1(uuid, uuid, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.leave_pachanga_guest_match_v1(uuid, uuid, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.review_pachanga_guest_withdrawal_v1(
  target_review_id uuid,
  next_status text,
  operation_id uuid,
  expected_review_revision bigint,
  expected_group_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_id uuid := auth.uid();
  selected_review public.pachanga_guest_withdrawal_reviews%rowtype;
  current_group public.pachanga_groups%rowtype;
  result_sequence bigint;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or operation_id is null
    or expected_review_revision is null or expected_group_revision is null
  then
    raise exception 'Authentication, operation id and revisions required';
  end if;
  if next_status not in ('confirmed', 'dismissed') then raise exception 'Revisión no válida'; end if;

  select * into selected_review
  from public.pachanga_guest_withdrawal_reviews reviews
  where reviews.id = target_review_id
  for update;
  if not found then raise exception 'Revisión no encontrada'; end if;

  replay := private.pachanga_safe_operation_replay_v1(
    selected_review.group_id, operation_id, actor_id, 'match_guest_withdrawal_review_v1'
  );
  if replay is not null then return replay; end if;
  if not public.is_pachanga_group_admin(selected_review.group_id) then
    raise exception 'Solo los admins pueden revisar abandonos';
  end if;
  if selected_review.revision <> expected_review_revision then
    raise exception 'Review revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected_review.status <> 'pending' then raise exception 'La revisión ya estaba decidida'; end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = selected_review.group_id
  for update;
  if not found then raise exception 'Grupo no encontrado'; end if;
  if current_group.payload_revision <> expected_group_revision then
    raise exception 'Group revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  update public.pachanga_guest_withdrawal_reviews reviews
  set status = next_status,
      revision = reviews.revision + 1,
      server_sequence = nextval('public.pachanga_match_guest_sequence'),
      reviewed_by = actor_id,
      reviewed_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where reviews.id = selected_review.id
  returning reviews.server_sequence into result_sequence;

  perform private.pachanga_notify_v1(
    selected_review.guest_user_id,
    'match_guest_withdrawal_' || next_status,
    case when next_status = 'confirmed' then 'Abandono registrado' else 'Incidencia descartada' end,
    case when next_status = 'confirmed'
      then 'El administrador ha confirmado que abandonaste este partido después de aceptar.'
      else 'El administrador ha descartado la incidencia de abandono.'
    end,
    null,
    jsonb_build_object('reviewId', selected_review.id, 'reviewStatus', next_status),
    'match-guest-left:' || selected_review.access_id::text || ':guest-review'
  );

  perform public.record_pachanga_group_event(
    selected_review.group_id,
    selected_review.match_id,
    'match_guest_withdrawal_' || next_status,
    jsonb_build_object(
      'withdrawalReviewId', selected_review.id,
      'affectsSportRating', false
    ),
    operation_id,
    true
  );

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', current_group.payload_revision,
    'review', jsonb_build_object(
      'id', selected_review.id,
      'status', next_status,
      'revision', expected_review_revision + 1,
      'serverSequence', result_sequence,
      'affectsSportRating', false
    )
  );

  return private.pachanga_store_safe_operation_v1(
    selected_review.group_id, operation_id, 'match_guest_withdrawal_review_v1', actor_id,
    expected_group_revision, current_group.payload_revision, client_metadata,
    response, result_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.review_pachanga_guest_withdrawal_v1(uuid, text, uuid, bigint, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.review_pachanga_guest_withdrawal_v1(uuid, text, uuid, bigint, bigint, jsonb)
  to authenticated, service_role;

create or replace function public.search_pachanga_open_matches_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  return (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', open_matches.id,
        'source_payload_revision', open_matches.source_payload_revision,
        'group_name', open_matches.group_name,
        'title', open_matches.title,
        'date', open_matches.date,
        'date_text', open_matches.date_text,
        'day', open_matches.day,
        'modality', open_matches.modality,
        'zone', open_matches.zone,
        'lat', case when open_matches.lat is null then null else round(open_matches.lat::numeric, 2) end,
        'lng', case when open_matches.lng is null then null else round(open_matches.lng::numeric, 2) end,
        'field_name', open_matches.field_name,
        'field_cost', open_matches.field_cost,
        'price_per_player', open_matches.price_per_player,
        'target_players', open_matches.target_players,
        'confirmed_count', open_matches.confirmed_count,
        'open_slots', open_matches.open_slots,
        'min_media', open_matches.min_media,
        'max_media', open_matches.max_media,
        'positions', open_matches.positions,
        'requires_approval', open_matches.requires_approval,
        'guests_pay', open_matches.guests_pay,
        'group_level', open_matches.group_level,
        'active', open_matches.active
      )
      order by open_matches.date asc, open_matches.id asc
    ), '[]'::jsonb)
    from public.pachanga_open_matches open_matches
    where (
      open_matches.active
      and open_matches.open_slots > 0
    ) or exists (
      select 1
      from public.pachanga_open_match_requests own_request
      where own_request.open_match_id = open_matches.id
        and own_request.requester_user_id = auth.uid()
        and own_request.status = 'accepted'
    )
  );
end;
$$;

revoke all on function public.search_pachanga_open_matches_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.search_pachanga_open_matches_v1()
  to authenticated, service_role;

create or replace function public.get_my_pachanga_open_match_requests_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  return (
    select coalesce(jsonb_agg(
      jsonb_strip_nulls(jsonb_build_object(
        'id', requests.id,
        'open_match_id', requests.open_match_id,
        'status', requests.status,
        'revision', requests.revision,
        'server_sequence', requests.server_sequence,
        'match_revision', open_matches.source_payload_revision,
        'access_id', access.id,
        'action_url', case when access.status = 'accepted'
          then '/partido-invitado?acceso=' || access.id::text
          else null
        end
      ))
      order by requests.server_sequence desc, requests.id desc
    ), '[]'::jsonb)
    from public.pachanga_open_match_requests requests
    join public.pachanga_open_matches open_matches on open_matches.id = requests.open_match_id
    left join public.pachanga_match_guest_access access
      on access.source_kind = 'open_request'
      and access.source_id = requests.id
      and access.guest_user_id = auth.uid()
    where requests.requester_user_id = auth.uid()
  );
end;
$$;

revoke all on function public.get_my_pachanga_open_match_requests_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_open_match_requests_v1()
  to authenticated, service_role;

create or replace function public.get_pachanga_match_invitation_admin_state_v1(
  target_group_id uuid,
  target_match_id text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  current_revision bigint;
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Solo los admins pueden consultar invitaciones';
  end if;
  select groups.payload_revision into current_revision
  from public.pachanga_groups groups where groups.id = target_group_id;
  if not found then raise exception 'Grupo no encontrado'; end if;

  return jsonb_build_object(
    'confirmedRevision', current_revision,
    'invitations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', invitations.id,
          'targetMarketProfileId', invitations.target_market_profile_id,
          'inviteeName', invitations.invitee_name,
          'status', invitations.status,
          'revision', invitations.revision,
          'serverSequence', invitations.server_sequence
        ) order by invitations.server_sequence desc, invitations.id desc
      )
      from public.pachanga_match_invitations invitations
      where invitations.group_id = target_group_id
        and invitations.match_id = target_match_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_match_invitation_admin_state_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_match_invitation_admin_state_v1(uuid, text)
  to authenticated, service_role;

create or replace function public.cancel_my_pachanga_open_match_request_v1(
  target_request_id uuid,
  operation_id uuid,
  expected_request_revision bigint,
  expected_match_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
set lock_timeout = '750ms'
as $$
declare
  actor_id uuid := auth.uid();
  selected_request public.pachanga_open_match_requests%rowtype;
  selected_open public.pachanga_open_matches%rowtype;
  replay jsonb;
  response jsonb;
begin
  if actor_id is null or operation_id is null
    or expected_request_revision is null or expected_match_revision is null
  then
    raise exception 'Authentication, operation id and revisions required';
  end if;

  select * into selected_request
  from public.pachanga_open_match_requests requests
  where requests.id = target_request_id
  for update;
  if not found then raise exception 'Solicitud no encontrada'; end if;
  if selected_request.requester_user_id <> actor_id then
    raise exception 'Solo el solicitante puede cancelar la solicitud';
  end if;

  replay := private.pachanga_safe_operation_replay_v1(
    selected_request.source_group_id, operation_id, actor_id, 'open_match_request_cancel_v1'
  );
  if replay is not null then return replay; end if;
  if selected_request.revision <> expected_request_revision then
    raise exception 'Request revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected_request.status <> 'pending' then raise exception 'La solicitud ya estaba decidida'; end if;

  select * into selected_open
  from public.pachanga_open_matches open_matches
  where open_matches.id = selected_request.open_match_id
  for update;
  if not found then raise exception 'Partido abierto no encontrado'; end if;
  if selected_open.source_payload_revision <> expected_match_revision then
    raise exception 'Match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  update public.pachanga_open_match_requests requests
  set status = 'cancelled',
      decided_by = actor_id,
      decided_at = clock_timestamp()
  where requests.id = selected_request.id
  returning * into selected_request;

  perform public.record_pachanga_group_event(
    selected_request.source_group_id,
    selected_request.source_match_id,
    'open_match_request_cancelled',
    jsonb_build_object('requestId', selected_request.id),
    operation_id,
    true
  );

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'confirmedRevision', selected_open.source_payload_revision,
    'request', jsonb_build_object(
      'id', selected_request.id,
      'openMatchId', selected_request.open_match_id,
      'status', selected_request.status,
      'revision', selected_request.revision,
      'serverSequence', selected_request.server_sequence
    )
  );

  return private.pachanga_store_safe_operation_v1(
    selected_request.source_group_id, operation_id, 'open_match_request_cancel_v1', actor_id,
    expected_match_revision, selected_open.source_payload_revision, client_metadata,
    response, selected_request.server_sequence
  );
exception when transaction_rollback or serialization_failure or deadlock_detected or lock_not_available then
  raise exception 'La operación está ocupada. Recarga e inténtalo de nuevo.' using errcode = 'PT409';
end;
$$;

revoke all on function public.cancel_my_pachanga_open_match_request_v1(uuid, uuid, bigint, bigint, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.cancel_my_pachanga_open_match_request_v1(uuid, uuid, bigint, bigint, jsonb)
  to authenticated, service_role;

alter table public.pachanga_user_notifications replica identity full;
alter table public.pachanga_match_guest_access replica identity full;
alter table public.pachanga_match_guest_snapshots replica identity full;
alter table public.pachanga_open_match_requests replica identity full;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'pachanga_user_notifications',
    'pachanga_match_guest_access',
    'pachanga_match_guest_snapshots',
    'pachanga_open_match_requests'
  ]
  loop
    if not exists (
      select 1
      from pg_catalog.pg_publication_tables publication_tables
      where publication_tables.pubname = 'supabase_realtime'
        and publication_tables.schemaname = 'public'
        and publication_tables.tablename = target_table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', target_table);
    end if;
  end loop;
end;
$$;

comment on table public.pachanga_match_guest_snapshots is
  'Read-only canonical match snapshots. They intentionally exclude phones, birth dates, payer data, group codes, rating votes and assessments.';
comment on table public.pachanga_guest_withdrawal_reviews is
  'Administrative conduct evidence for a guest leaving after acceptance. It never modifies sporting rating, facets, votes or assessments.';
