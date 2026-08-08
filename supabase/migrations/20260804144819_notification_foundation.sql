-- Notification foundation: preferences, criticality, canonical delivery intent
-- and server-side fan-out for the first high-value product events.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

alter table public.pachanga_user_notifications
  add column if not exists category text not null default 'group',
  add column if not exists priority text not null default 'normal',
  add column if not exists mandatory_in_app boolean not null default false,
  add column if not exists visible_in_app boolean not null default true;

alter table public.pachanga_user_notifications
  drop constraint if exists pachanga_user_notifications_category_check,
  add constraint pachanga_user_notifications_category_check
    check (category in ('group', 'match', 'market', 'challenge', 'achievement', 'security')),
  drop constraint if exists pachanga_user_notifications_priority_check,
  add constraint pachanga_user_notifications_priority_check
    check (priority in ('normal', 'high', 'critical'));

create index if not exists pachanga_user_notifications_visible_sequence_idx
  on public.pachanga_user_notifications(recipient_user_id, server_sequence desc, id desc)
  where visible_in_app;

create table if not exists public.pachanga_notification_preferences (
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  in_app_enabled boolean not null default true,
  push_enabled boolean not null default false,
  email_enabled boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (user_id, category),
  check (category in ('group', 'match', 'market', 'challenge', 'achievement', 'security')),
  check (revision >= 1)
);

create index if not exists pachanga_notification_preferences_user_sequence_idx
  on public.pachanga_notification_preferences(user_id, server_sequence desc, category);

alter table public.pachanga_notification_preferences enable row level security;
revoke all on table public.pachanga_notification_preferences from public, anon, authenticated;
grant select on table public.pachanga_notification_preferences to authenticated;

drop policy if exists "Users read their own notification preferences"
  on public.pachanga_notification_preferences;
create policy "Users read their own notification preferences"
on public.pachanga_notification_preferences
for select
to authenticated
using ((select auth.uid()) = user_id);

drop policy if exists "Users read their own notifications" on public.pachanga_user_notifications;
create policy "Users read their own visible notifications"
on public.pachanga_user_notifications
for select
to authenticated
using ((select auth.uid()) = recipient_user_id and visible_in_app);

create table if not exists private.pachanga_notification_channels (
  channel text primary key,
  enabled boolean not null default false,
  provider text,
  updated_at timestamptz not null default clock_timestamp(),
  check (channel in ('push', 'email'))
);

insert into private.pachanga_notification_channels(channel, enabled, provider)
values ('push', false, null), ('email', false, null)
on conflict (channel) do nothing;

create table if not exists private.pachanga_notification_delivery_outbox (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.pachanga_user_notifications(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null,
  state text not null default 'pending',
  attempts integer not null default 0,
  available_at timestamptz not null default clock_timestamp(),
  server_sequence bigint not null default nextval('public.pachanga_match_guest_sequence'),
  payload jsonb not null default '{}'::jsonb,
  last_error text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (notification_id, channel),
  check (channel in ('push', 'email')),
  check (state in ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  check (attempts >= 0),
  check (jsonb_typeof(payload) = 'object')
);

create index if not exists pachanga_notification_delivery_pending_idx
  on private.pachanga_notification_delivery_outbox(channel, available_at, server_sequence, id)
  where state in ('pending', 'failed');

create table if not exists private.pachanga_notification_preference_receipts (
  operation_id uuid primary key,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  response jsonb not null,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (category in ('group', 'match', 'market', 'challenge', 'achievement', 'security')),
  check (jsonb_typeof(response) = 'object')
);

revoke all on table private.pachanga_notification_channels from public, anon, authenticated;
revoke all on table private.pachanga_notification_delivery_outbox from public, anon, authenticated;
revoke all on table private.pachanga_notification_preference_receipts from public, anon, authenticated;

create or replace function private.pachanga_notification_policy_v1(target_kind text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select lower(coalesce(nullif(trim(target_kind), ''), 'general')) as kind
  )
  select jsonb_build_object(
    'category', case
      when kind like '%achievement%' or kind like '%reward%' then 'achievement'
      when kind like '%challenge%' or kind like '%external_result%' then 'challenge'
      when kind like '%invitation%' or kind like '%open_match_request%'
        or kind like '%withdrawal%' or kind like '%market%' then 'market'
      when kind like '%attendance%' or kind like '%availability%'
        or kind like 'match_%' then 'match'
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' then 'security'
      else 'group'
    end,
    'priority', case
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' or kind like '%challenge%'
        or kind like '%external_result%' or kind like '%invitation%'
        or kind like '%open_match_request%' or kind like '%withdrawal%' then 'critical'
      when kind like '%achievement%' or kind like '%reward%'
        or kind in ('group_member_removed', 'match_attendance_cancelled') then 'high'
      else 'normal'
    end,
    'mandatoryInApp', (
      kind like '%security%' or kind like '%sanction%' or kind like '%warning%'
      or kind like '%challenge%' or kind like '%external_result%'
      or kind like '%invitation%' or kind like '%open_match_request%'
      or kind like '%withdrawal%' or kind like '%achievement%' or kind like '%reward%'
      or kind = 'group_member_removed'
    )
  )
  from normalized;
$$;

revoke all on function private.pachanga_notification_policy_v1(text)
  from public, anon, authenticated;

update public.pachanga_user_notifications notifications
set category = private.pachanga_notification_policy_v1(notifications.kind) ->> 'category',
    priority = private.pachanga_notification_policy_v1(notifications.kind) ->> 'priority',
    mandatory_in_app = (
      private.pachanga_notification_policy_v1(notifications.kind) ->> 'mandatoryInApp'
    )::boolean;

update public.pachanga_user_notifications
set title = 'Nuevo logro desbloqueado',
    body = 'Toca para descubrirlo.'
where kind in ('achievement_reward', 'personal_achievement_reward');

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
  normalized_kind text := left(coalesce(nullif(trim(target_kind), ''), 'general'), 80);
  policy jsonb;
  selected_category text;
  selected_priority text;
  is_mandatory boolean;
  preference public.pachanga_notification_preferences%rowtype;
  show_in_app boolean;
  use_push boolean := false;
  use_email boolean := false;
  saved_notification public.pachanga_user_notifications%rowtype;
  safe_title text;
  safe_body text;
begin
  if target_recipient_user_id is null or nullif(trim(target_dedupe_key), '') is null then
    raise exception 'Notification recipient and dedupe key required';
  end if;

  policy := private.pachanga_notification_policy_v1(normalized_kind);
  selected_category := policy ->> 'category';
  selected_priority := policy ->> 'priority';
  is_mandatory := coalesce((policy ->> 'mandatoryInApp')::boolean, false);

  select * into preference
  from public.pachanga_notification_preferences preferences
  where preferences.user_id = target_recipient_user_id
    and preferences.category = selected_category;

  show_in_app := is_mandatory or coalesce(preference.in_app_enabled, true);
  use_push := coalesce(preference.push_enabled, false) and coalesce((
    select channels.enabled from private.pachanga_notification_channels channels
    where channels.channel = 'push'
  ), false);
  use_email := coalesce(preference.email_enabled, false) and coalesce((
    select channels.enabled from private.pachanga_notification_channels channels
    where channels.channel = 'email'
  ), false);

  if normalized_kind in ('achievement_reward', 'personal_achievement_reward') then
    safe_title := 'Nuevo logro desbloqueado';
    safe_body := 'Toca para descubrirlo.';
  else
    safe_title := left(coalesce(nullif(trim(target_title), ''), 'Pachangas IQ'), 140);
    safe_body := left(coalesce(target_body, ''), 500);
  end if;

  insert into public.pachanga_user_notifications(
    recipient_user_id, kind, category, priority, mandatory_in_app, visible_in_app,
    title, body, action_url, payload, dedupe_key
  ) values (
    target_recipient_user_id,
    normalized_kind,
    selected_category,
    selected_priority,
    is_mandatory,
    show_in_app,
    safe_title,
    safe_body,
    nullif(left(coalesce(target_action_url, ''), 500), ''),
    case when jsonb_typeof(target_payload) = 'object' then target_payload else '{}'::jsonb end,
    left(target_dedupe_key, 240)
  )
  on conflict (dedupe_key) do update set
    kind = excluded.kind,
    category = excluded.category,
    priority = excluded.priority,
    mandatory_in_app = excluded.mandatory_in_app,
    visible_in_app = excluded.visible_in_app,
    title = excluded.title,
    body = excluded.body,
    action_url = excluded.action_url,
    payload = excluded.payload,
    revision = public.pachanga_user_notifications.revision + 1,
    server_sequence = nextval('public.pachanga_match_guest_sequence'),
    updated_at = clock_timestamp()
  returning * into saved_notification;

  if use_push then
    insert into private.pachanga_notification_delivery_outbox(
      notification_id, recipient_user_id, channel, payload
    ) values (
      saved_notification.id, target_recipient_user_id, 'push',
      jsonb_build_object('notificationId', saved_notification.id, 'kind', normalized_kind)
    ) on conflict (notification_id, channel) do nothing;
  end if;

  if use_email then
    insert into private.pachanga_notification_delivery_outbox(
      notification_id, recipient_user_id, channel, payload
    ) values (
      saved_notification.id, target_recipient_user_id, 'email',
      jsonb_build_object('notificationId', saved_notification.id, 'kind', normalized_kind)
    ) on conflict (notification_id, channel) do nothing;
  end if;

  return saved_notification;
end;
$$;

revoke all on function private.pachanga_notify_v1(uuid, text, text, text, text, jsonb, text)
  from public, anon, authenticated;

create or replace function public.get_pachanga_notification_preferences_v1()
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  with categories(category, label, description, position, contains_mandatory) as (
    values
      ('group', 'Grupo y miembros', 'Altas, bajas, cambios de rol e identidad del equipo.', 1, true),
      ('match', 'Partidos y asistencia', 'Confirmaciones, bajas y disponibilidad de jugadores.', 2, false),
      ('market', 'Mercado e invitaciones', 'Invitaciones, solicitudes de plaza y abandonos.', 3, true),
      ('challenge', 'Retos y resultados', 'Retos, contrapropuestas y certificación de resultados.', 4, true),
      ('achievement', 'Logros', 'Logros personales, de equipo y recompensas pendientes.', 5, true),
      ('security', 'Seguridad y administración', 'Avisos de Pachangas IQ, sanciones y acciones obligatorias.', 6, true)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', categories.category,
    'label', categories.label,
    'description', categories.description,
    'inAppEnabled', coalesce(preferences.in_app_enabled, true),
    'pushEnabled', coalesce(preferences.push_enabled, false),
    'emailEnabled', coalesce(preferences.email_enabled, false),
    'pushAvailable', coalesce(push_channel.enabled, false),
    'emailAvailable', coalesce(email_channel.enabled, false),
    'containsMandatory', categories.contains_mandatory,
    'revision', coalesce(preferences.revision, 0),
    'serverSequence', coalesce(preferences.server_sequence, 0),
    'updatedAt', preferences.updated_at
  ) order by categories.position), '[]'::jsonb)
  from categories
  left join public.pachanga_notification_preferences preferences
    on preferences.user_id = auth.uid() and preferences.category = categories.category
  left join private.pachanga_notification_channels push_channel on push_channel.channel = 'push'
  left join private.pachanga_notification_channels email_channel on email_channel.channel = 'email'
  where auth.uid() is not null;
$$;

revoke all on function public.get_pachanga_notification_preferences_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_notification_preferences_v1()
  to authenticated;

create or replace function public.update_pachanga_notification_preferences_v1(
  target_category text,
  next_in_app_enabled boolean,
  next_push_enabled boolean,
  next_email_enabled boolean,
  expected_revision bigint,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  actor_operation_id uuid := operation_id;
  normalized_category text := lower(trim(coalesce(target_category, '')));
  saved_preference public.pachanga_notification_preferences%rowtype;
  saved_receipt private.pachanga_notification_preference_receipts%rowtype;
  push_available boolean;
  email_available boolean;
  response jsonb;
begin
  if actor_id is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  if normalized_category not in ('group', 'match', 'market', 'challenge', 'achievement', 'security') then
    raise exception 'Invalid notification category';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('notification-pref-op:' || operation_id::text, 0));
  select * into saved_receipt
  from private.pachanga_notification_preference_receipts receipts
  where receipts.operation_id = actor_operation_id;
  if found then
    if saved_receipt.actor_user_id <> actor_id or saved_receipt.category <> normalized_category then
      raise exception 'Operation belongs to another action';
    end if;
    return saved_receipt.response;
  end if;

  select coalesce(channels.enabled, false) into push_available
  from private.pachanga_notification_channels channels where channels.channel = 'push';
  select coalesce(channels.enabled, false) into email_available
  from private.pachanga_notification_channels channels where channels.channel = 'email';
  if coalesce(next_push_enabled, false) and not coalesce(push_available, false) then
    raise exception 'Push notifications are not available yet';
  end if;
  if coalesce(next_email_enabled, false) and not coalesce(email_available, false) then
    raise exception 'Email notifications are not available yet';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'notification-pref:' || actor_id::text || ':' || normalized_category, 0
  ));

  select * into saved_preference
  from public.pachanga_notification_preferences preferences
  where preferences.user_id = actor_id and preferences.category = normalized_category
  for update;

  if found and saved_preference.revision <> expected_revision then
    raise exception 'Notification preferences are newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if not found and expected_revision <> 0 then
    raise exception 'Notification preferences are newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;

  insert into public.pachanga_notification_preferences(
    user_id, category, in_app_enabled, push_enabled, email_enabled
  ) values (
    actor_id, normalized_category, coalesce(next_in_app_enabled, true),
    coalesce(next_push_enabled, false), coalesce(next_email_enabled, false)
  )
  on conflict (user_id, category) do update set
    in_app_enabled = excluded.in_app_enabled,
    push_enabled = excluded.push_enabled,
    email_enabled = excluded.email_enabled,
    revision = public.pachanga_notification_preferences.revision + 1,
    server_sequence = nextval('public.pachanga_match_guest_sequence'),
    updated_at = clock_timestamp()
  returning * into saved_preference;

  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedAt', clock_timestamp(),
    'preference', jsonb_build_object(
      'category', saved_preference.category,
      'inAppEnabled', saved_preference.in_app_enabled,
      'pushEnabled', saved_preference.push_enabled,
      'emailEnabled', saved_preference.email_enabled,
      'revision', saved_preference.revision,
      'serverSequence', saved_preference.server_sequence,
      'updatedAt', saved_preference.updated_at
    )
  );

  insert into private.pachanga_notification_preference_receipts(
    operation_id, actor_user_id, category, response, server_sequence
  ) values (
    actor_operation_id,
    actor_id, normalized_category, response, saved_preference.server_sequence
  );

  return response;
end;
$$;

revoke all on function public.update_pachanga_notification_preferences_v1(
  text, boolean, boolean, boolean, bigint, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.update_pachanga_notification_preferences_v1(
  text, boolean, boolean, boolean, bigint, uuid
) to authenticated;

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
      and notifications.visible_in_app
    order by notifications.server_sequence desc, notifications.id desc
    limit 120
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', notifications.id,
      'kind', notifications.kind,
      'category', notifications.category,
      'priority', notifications.priority,
      'mandatoryInApp', notifications.mandatory_in_app,
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
  left join public.pachanga_groups request_groups on request_groups.id = open_requests.source_group_id;
$$;

revoke all on function public.get_pachanga_notification_center_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_notification_center_v1()
  to authenticated, service_role;

create or replace function private.pachanga_group_notification_recipients_v1(
  target_group_id uuid,
  admins_only boolean default false
)
returns table(user_id uuid)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select distinct candidates.user_id
  from (
    select groups.owner_id as user_id, 'owner'::text as role
    from public.pachanga_groups groups
    where groups.id = target_group_id
    union all
    select members.user_id, members.role
    from public.pachanga_group_members members
    where members.group_id = target_group_id
  ) candidates
  where candidates.user_id is not null
    and (not coalesce(admins_only, false) or candidates.role in ('owner', 'admin'));
$$;

revoke all on function private.pachanga_group_notification_recipients_v1(uuid, boolean)
  from public, anon, authenticated;

create or replace function private.pachanga_notify_group_membership_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_group_id uuid := coalesce(new.group_id, old.group_id);
  selected_user_id uuid := coalesce(new.user_id, old.user_id);
  selected_name text := coalesce(nullif(trim(coalesce(new.display_name, old.display_name)), ''), 'Un jugador');
  selected_created_at timestamptz := coalesce(new.created_at, old.created_at, clock_timestamp());
  recipient record;
  notification_kind text;
begin
  notification_kind := case when tg_op = 'INSERT' then 'group_member_joined' else 'group_member_removed' end;

  for recipient in
    select recipients.user_id
    from private.pachanga_group_notification_recipients_v1(selected_group_id, false) recipients
    where recipients.user_id <> selected_user_id
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      notification_kind,
      case when tg_op = 'INSERT' then 'Nuevo miembro en el grupo' else 'Cambio en el grupo' end,
      selected_name || case when tg_op = 'INSERT'
        then ' se ha unido al grupo.' else ' ya no forma parte del grupo.' end,
      '/?mobile=equipo',
      jsonb_build_object('groupId', selected_group_id, 'memberUserId', selected_user_id),
      'group-membership:' || selected_group_id::text || ':' || selected_user_id::text || ':'
        || lower(tg_op) || ':' || floor(extract(epoch from selected_created_at) * 1000000)::bigint::text
        || ':' || recipient.user_id::text
    );
  end loop;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function private.pachanga_notify_group_membership_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_notify_group_membership_v1 on public.pachanga_group_members;
create trigger pachanga_notify_group_membership_v1
after insert or delete on public.pachanga_group_members
for each row execute function private.pachanga_notify_group_membership_v1();

alter table public.pachanga_group_events
  add column if not exists server_sequence bigint
    not null default nextval('public.pachanga_match_guest_sequence');

create index if not exists pachanga_group_events_attendance_sequence_idx
  on public.pachanga_group_events(group_id, match_id, event_type, server_sequence desc, id desc)
  where event_type = 'match_attendance_changed';

create or replace function private.pachanga_notify_attendance_event_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  next_status text := new.payload ->> 'status';
  previous_status text;
  player_name text;
  match_name text;
  recipient record;
begin
  if new.event_type <> 'match_attendance_changed' or new.match_id is null then return new; end if;

  select events.payload ->> 'status' into previous_status
  from public.pachanga_group_events events
  where events.group_id = new.group_id
    and events.match_id = new.match_id
    and events.event_type = 'match_attendance_changed'
    and events.payload ->> 'playerId' = new.payload ->> 'playerId'
    and events.server_sequence < new.server_sequence
  order by events.server_sequence desc, events.id desc
  limit 1;

  if not coalesce((
    (next_status = 'voy' and previous_status is distinct from 'voy')
    or (next_status = 'no' and previous_status = 'voy')
  ), false) then return new; end if;

  select coalesce(players.value ->> 'name', 'Un jugador') into player_name
  from public.pachanga_groups groups
  cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) players(value)
  where groups.id = new.group_id and players.value ->> 'id' = new.payload ->> 'playerId'
  limit 1;

  select coalesce(matches.value ->> 'name', 'el partido') into match_name
  from public.pachanga_groups groups
  cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'matches', '[]'::jsonb)) matches(value)
  where groups.id = new.group_id and matches.value ->> 'id' = new.match_id
  limit 1;

  for recipient in
    select recipients.user_id
    from private.pachanga_group_notification_recipients_v1(new.group_id, false) recipients
    where recipients.user_id is distinct from new.actor_id
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      case when next_status = 'voy' then 'match_attendance_joined' else 'match_attendance_cancelled' end,
      case when next_status = 'voy' then 'Se ha apuntado al partido' else 'Cambio de asistencia' end,
      coalesce(player_name, 'Un jugador') || case when next_status = 'voy'
        then ' se ha apuntado a ' else ' ya no irá a ' end || coalesce(match_name, 'el partido') || '.',
      '/?mobile=partido&p=' || replace(new.match_id, '-', ''),
      jsonb_build_object(
        'groupId', new.group_id, 'matchId', new.match_id,
        'playerId', new.payload ->> 'playerId', 'status', next_status,
        'payloadRevision', new.payload -> 'payloadRevision'
      ),
      'attendance-event:' || new.id::text || ':' || recipient.user_id::text
    );
  end loop;

  return new;
end;
$$;

revoke all on function private.pachanga_notify_attendance_event_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_notify_attendance_event_v1 on public.pachanga_group_events;
create trigger pachanga_notify_attendance_event_v1
after insert on public.pachanga_group_events
for each row execute function private.pachanga_notify_attendance_event_v1();

create or replace function private.pachanga_notify_player_availability_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  membership record;
  recipient record;
begin
  if new.injured is not distinct from old.injured then return new; end if;

  for membership in
    select distinct members.group_id
    from public.pachanga_group_members members
    where members.user_id = new.user_id
  loop
    for recipient in
      select recipients.user_id
      from private.pachanga_group_notification_recipients_v1(membership.group_id, false) recipients
      where recipients.user_id <> new.user_id
    loop
      perform private.pachanga_notify_v1(
        recipient.user_id,
        case when new.injured then 'player_availability_unavailable' else 'player_availability_available' end,
        'Disponibilidad actualizada',
        new.display_name || case when new.injured
          then ' no está disponible.' else ' vuelve a estar disponible.' end,
        '/?mobile=equipo',
        jsonb_build_object('groupId', membership.group_id, 'playerProfileId', new.id, 'available', not new.injured),
        'player-availability:' || new.id::text || ':' || txid_current()::text || ':'
          || new.injured::text || ':' || membership.group_id::text || ':' || recipient.user_id::text
      );
    end loop;
  end loop;

  return new;
end;
$$;

revoke all on function private.pachanga_notify_player_availability_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_notify_player_availability_v1 on public.pachanga_player_profiles;
create trigger pachanga_notify_player_availability_v1
after update of injured on public.pachanga_player_profiles
for each row execute function private.pachanga_notify_player_availability_v1();

create or replace function private.pachanga_notify_challenge_event_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_challenge public.pachanga_team_challenges%rowtype;
  target_group_id uuid;
  actor_group_name text;
  recipient record;
begin
  select * into selected_challenge
  from public.pachanga_team_challenges challenges where challenges.id = new.challenge_id;
  if not found then return new; end if;

  target_group_id := case when new.actor_group_id = selected_challenge.sender_group_id
    then selected_challenge.receiver_group_id else selected_challenge.sender_group_id end;
  select groups.name into actor_group_name from public.pachanga_groups groups where groups.id = new.actor_group_id;

  for recipient in
    select recipients.user_id
    from private.pachanga_group_notification_recipients_v1(target_group_id, true) recipients
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      'team_challenge_' || new.event_type,
      case new.event_type
        when 'created' then 'Nuevo reto recibido'
        when 'changes_proposed' then 'Cambios propuestos en un reto'
        when 'accepted' then 'Reto aceptado'
        when 'rejected' then 'Reto rechazado'
        else 'Reto cancelado'
      end,
      coalesce(actor_group_name, 'El otro equipo') || case new.event_type
        when 'created' then ' os ha retado.'
        when 'changes_proposed' then ' ha enviado una contrapropuesta.'
        when 'accepted' then ' ha aceptado el reto.'
        when 'rejected' then ' ha rechazado el reto.'
        else ' ha cancelado el reto.'
      end,
      '/mercado?section=retos',
      jsonb_build_object(
        'challengeId', new.challenge_id,
        'challengeRevision', new.challenge_revision,
        'eventType', new.event_type,
        'targetGroupId', target_group_id
      ),
      'challenge-event:' || new.id::text || ':' || recipient.user_id::text
    );
  end loop;

  return new;
end;
$$;

revoke all on function private.pachanga_notify_challenge_event_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_notify_challenge_event_v1 on public.pachanga_team_challenge_events;
create trigger pachanga_notify_challenge_event_v1
after insert on public.pachanga_team_challenge_events
for each row execute function private.pachanga_notify_challenge_event_v1();
