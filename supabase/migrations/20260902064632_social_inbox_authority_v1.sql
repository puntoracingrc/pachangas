-- Official UI V3G: canonical social Inbox projection and read-state commands.
-- Domain notifications stay in their existing authoritative table. Inbox
-- commands never execute Match, Challenge, Market or Team actions.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_user_notifications
  add column if not exists archived_at timestamptz;

create index if not exists pachanga_user_notifications_social_active_idx
  on public.pachanga_user_notifications(
    recipient_user_id, server_sequence desc, id desc
  )
  where visible_in_app and archived_at is null;

create table if not exists private.pachanga_social_inbox_command_receipts_v1 (
  operation_id uuid primary key,
  actor_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null,
  notification_id uuid references public.pachanga_user_notifications(id) on delete cascade,
  expected_revision bigint,
  expected_server_sequence bigint,
  response jsonb not null,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (action in (
    'inbox.mark_read', 'inbox.mark_unread', 'inbox.mark_all_read', 'inbox.archive'
  )),
  check (expected_revision is null or expected_revision >= 1),
  check (expected_server_sequence is null or expected_server_sequence >= 0),
  check (jsonb_typeof(response) = 'object')
);

create index if not exists pachanga_social_inbox_receipts_actor_idx
  on private.pachanga_social_inbox_command_receipts_v1(actor_user_id, created_at desc, operation_id);

revoke all on table private.pachanga_social_inbox_command_receipts_v1
  from public, anon, authenticated;

create or replace function private.pachanga_social_inbox_try_uuid_v1(target_value text)
returns uuid
language plpgsql
immutable
set search_path = pg_catalog
as $$
begin
  if target_value is null or target_value !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  return target_value::uuid;
exception when invalid_text_representation then
  return null;
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
      'team_player_invitation_accepted',
      'team_player_invitation_declined',
      'team_shield_updated'
    ) then 'TEAM'
    else null
  end
  from normalized;
$$;

create or replace function private.pachanga_social_inbox_descriptor_v1(
  target_notification_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare
  notice public.pachanga_user_notifications%rowtype;
  domain_name text;
  attention_state text := 'INFORMATIONAL';
  deep_link text;
  cta_label text := 'Abrir';
  context_label text;
  source_id text;
  status_label text := 'Actividad';
  priority_rank integer;
  sort_rank integer;
  source_uuid uuid;
  source_group_id uuid;
  member_group_id uuid;
  invitation_row public.pachanga_match_invitations%rowtype;
  request_row public.pachanga_open_match_requests%rowtype;
  access_row public.pachanga_match_guest_access%rowtype;
  challenge_row public.pachanga_team_challenges%rowtype;
  external_match_row public.pachanga_external_matches%rowtype;
begin
  if target_actor_id is null then return null; end if;

  select * into notice
  from public.pachanga_user_notifications notifications
  where notifications.id = target_notification_id
    and notifications.recipient_user_id = target_actor_id
    and notifications.visible_in_app;
  if not found then return null; end if;

  domain_name := private.pachanga_social_inbox_domain_v1(notice.kind);
  if domain_name is null then return null; end if;

  priority_rank := case notice.priority
    when 'critical' then 30
    when 'high' then 20
    else 10
  end;
  context_label := case domain_name
    when 'MATCH' then 'Partido'
    when 'CHALLENGE' then 'Reto'
    when 'MARKET' then 'Mercado'
    else 'Equipo'
  end;

  if notice.kind like 'team_challenge_%' then
    source_uuid := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'challengeId');
    if source_uuid is not null then
      select * into challenge_row
      from public.pachanga_team_challenges challenges
      where challenges.id = source_uuid;
      if challenge_row.id is not null then
        select members.group_id into member_group_id
        from public.pachanga_group_members members
        where members.group_id in (challenge_row.sender_group_id, challenge_row.receiver_group_id)
          and members.user_id = target_actor_id
          and members.role in ('owner', 'admin')
        order by (challenge_row.last_proposed_by_group_id <> members.group_id) desc, members.group_id
        limit 1;
        if member_group_id is null then challenge_row.id := null; end if;
      end if;
    end if;
    source_id := source_uuid::text;
    if challenge_row.id is not null then
      deep_link := '/retos?view=active&reto=' || challenge_row.id::text;
      if challenge_row.status in ('proposed', 'changes_proposed')
        and challenge_row.last_proposed_by_group_id <> member_group_id then
        attention_state := 'ACTION_REQUIRED';
        status_label := 'Necesita respuesta';
        cta_label := 'Revisar reto';
      elsif challenge_row.status in ('accepted', 'rejected', 'cancelled') then
        attention_state := 'RESOLVED';
        status_label := 'Resuelto';
        cta_label := 'Ver reto';
      else
        cta_label := 'Ver reto';
      end if;
    else
      attention_state := 'RESOLVED';
      status_label := 'Ya no disponible';
    end if;

  elsif notice.kind like 'external_result_%' then
    source_uuid := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'externalMatchId');
    if source_uuid is not null then
      select * into external_match_row
      from public.pachanga_external_matches matches
      where matches.id = source_uuid;
      if external_match_row.id is not null then
        select members.group_id into member_group_id
        from public.pachanga_group_members members
        where members.group_id in (external_match_row.home_group_id, external_match_row.away_group_id)
          and members.user_id = target_actor_id
          and members.role in ('owner', 'admin')
        order by (external_match_row.pending_response_from_group_id = members.group_id) desc, members.group_id
        limit 1;
        if member_group_id is null then external_match_row.id := null; end if;
      end if;
    end if;
    source_id := source_uuid::text;
    if external_match_row.id is not null then
      deep_link := '/retos?view=active&reto=' || external_match_row.challenge_id::text;
      if external_match_row.state in ('pending_rival', 'change_proposed', 'needs_scorer_fix')
        and external_match_row.pending_response_from_group_id = member_group_id then
        attention_state := 'ACTION_REQUIRED';
        status_label := 'Resultado pendiente';
        cta_label := 'Revisar resultado';
      elsif external_match_row.state in ('confirmed', 'auto_confirmed', 'disputed', 'unverified', 'annulled', 'cancelled') then
        attention_state := 'RESOLVED';
        status_label := 'Resuelto';
        cta_label := 'Ver resultado';
      else
        cta_label := 'Ver partido';
      end if;
    else
      attention_state := 'RESOLVED';
      status_label := 'Ya no disponible';
    end if;

  elsif notice.kind = 'match_invitation' or notice.kind like 'match_invitation_%' then
    source_uuid := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'invitationId');
    if source_uuid is not null then
      select * into invitation_row
      from public.pachanga_match_invitations invitations
      where invitations.id = source_uuid
        and (
          invitations.invitee_user_id = target_actor_id
          or invitations.inviter_user_id = target_actor_id
        );
    end if;
    source_id := source_uuid::text;
    if invitation_row.id is not null then
      if invitation_row.invitee_user_id = target_actor_id then
        deep_link := '/mercado?tab=partidos&invitacion=' || invitation_row.id::text;
      else
        deep_link := '/?mobile=partido&p=' || replace(invitation_row.match_id, '-', '');
      end if;
      if invitation_row.invitee_user_id = target_actor_id and invitation_row.status = 'pending' then
        attention_state := 'ACTION_REQUIRED';
        status_label := 'Necesita respuesta';
        cta_label := 'Revisar invitación';
      elsif invitation_row.status in ('accepted', 'rejected', 'cancelled') then
        attention_state := 'RESOLVED';
        status_label := 'Resuelta';
        cta_label := 'Ver invitación';
      end if;
    else
      attention_state := 'RESOLVED';
      status_label := 'Ya no disponible';
    end if;

  elsif notice.kind = 'open_match_request' or notice.kind like 'open_match_request_%' then
    source_uuid := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'requestId');
    if source_uuid is not null then
      select * into request_row
      from public.pachanga_open_match_requests requests
      where requests.id = source_uuid
        and (
          requests.requester_user_id = target_actor_id
          or public.is_pachanga_group_admin(requests.source_group_id)
        );
    end if;
    source_id := source_uuid::text;
    if request_row.id is not null then
      if request_row.requester_user_id = target_actor_id and request_row.status = 'accepted' then
        select * into access_row
        from public.pachanga_match_guest_access access
        where access.source_kind = 'open_request'
          and access.source_id = request_row.id
          and access.guest_user_id = target_actor_id
        order by access.server_sequence desc, access.id desc
        limit 1;
      end if;
      deep_link := case
        when access_row.id is not null and access_row.status = 'accepted'
          then '/partido-invitado?acceso=' || access_row.id::text
        when request_row.requester_user_id <> target_actor_id
          then '/?mobile=partido&p=' || replace(request_row.source_match_id, '-', '')
        else '/mercado?tab=partidos'
      end;
      if request_row.status = 'pending'
        and request_row.requester_user_id <> target_actor_id
        and public.is_pachanga_group_admin(request_row.source_group_id) then
        attention_state := 'ACTION_REQUIRED';
        status_label := 'Solicitud pendiente';
        cta_label := 'Revisar plaza';
      elsif request_row.status in ('accepted', 'rejected', 'cancelled') then
        attention_state := 'RESOLVED';
        status_label := 'Resuelta';
        cta_label := case when request_row.status = 'accepted' then 'Ver partido' else 'Ver Mercado' end;
      else
        cta_label := 'Ver solicitud';
      end if;
    else
      attention_state := 'RESOLVED';
      status_label := 'Ya no disponible';
    end if;

  elsif domain_name = 'MATCH' then
    source_group_id := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'groupId');
    source_id := coalesce(nullif(notice.payload ->> 'matchId', ''), source_group_id::text);
    if nullif(notice.payload ->> 'matchId', '') is not null then
      deep_link := '/?mobile=partido&p=' || replace(notice.payload ->> 'matchId', '-', '');
      cta_label := 'Ver partido';
    else
      deep_link := '/equipo';
      cta_label := 'Ver equipo';
    end if;
    if notice.kind in ('match_access_revoked', 'match_guest_left') then
      attention_state := 'RESOLVED';
      status_label := 'Acceso cerrado';
    end if;

  else
    source_group_id := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'groupId');
    source_id := coalesce(source_group_id::text, notice.payload ->> 'invitationId');
    deep_link := case
      when notice.kind like 'team_player_invitation_%' and source_group_id is not null
        then '/equipo/invitaciones?team=' || source_group_id::text
      else '/equipo'
    end;
    cta_label := case when notice.kind like 'team_player_invitation_%' then 'Ver invitaciones' else 'Ver equipo' end;
    if notice.kind in ('group_member_left', 'group_member_removed', 'team_player_invitation_accepted', 'team_player_invitation_declined') then
      attention_state := 'RESOLVED';
      status_label := 'Actualizado';
    end if;
  end if;

  sort_rank := case attention_state
    when 'ACTION_REQUIRED' then 1000 + case domain_name
      when 'MATCH' then 400
      when 'CHALLENGE' then 300
      when 'TEAM' then 200
      else 100
    end + priority_rank
    when 'INFORMATIONAL' then 500 + priority_rank
    else 100 + priority_rank
  end;

  return jsonb_strip_nulls(jsonb_build_object(
    'id', notice.id,
    'sourceDomain', domain_name,
    'sourceId', source_id,
    'kind', notice.kind,
    'category', lower(domain_name),
    'title', left(notice.title, 140),
    'summary', left(notice.body, 500),
    'context', context_label,
    'statusLabel', status_label,
    'occurredAt', notice.created_at,
    'updatedAt', notice.updated_at,
    'priority', notice.priority,
    'attentionState', attention_state,
    'readState', case when notice.read_at is null then 'UNREAD' else 'READ' end,
    'archiveState', case when notice.archived_at is null then 'ACTIVE' else 'ARCHIVED' end,
    'readAt', notice.read_at,
    'archivedAt', notice.archived_at,
    'revision', notice.revision,
    'serverSequence', notice.server_sequence,
    'deepLink', deep_link,
    'ctaLabel', cta_label,
    'sortRank', sort_rank
  ));
end;
$$;

revoke all on function private.pachanga_social_inbox_try_uuid_v1(text)
  from public, anon, authenticated;
revoke all on function private.pachanga_social_inbox_domain_v1(text)
  from public, anon, authenticated;
revoke all on function private.pachanga_social_inbox_descriptor_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.get_my_pachanga_social_inbox_v1(
  target_view text default 'pending',
  target_domain text default null,
  page_size integer default 25,
  cursor_sort_rank integer default null,
  cursor_server_sequence bigint default null,
  cursor_notification_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare
  actor_id uuid := (select auth.uid());
  selected_view text := lower(trim(coalesce(target_view, 'pending')));
  selected_domain text := upper(nullif(trim(coalesce(target_domain, '')), ''));
  selected_size integer := greatest(1, least(coalesce(page_size, 25), 50));
  response jsonb;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if selected_view not in ('pending', 'all') then
    raise exception 'SOCIAL_INBOX_VIEW_INVALID' using errcode = '22023';
  end if;
  if selected_domain is not null and selected_domain not in ('MATCH', 'CHALLENGE', 'MARKET', 'TEAM') then
    raise exception 'SOCIAL_INBOX_DOMAIN_INVALID' using errcode = '22023';
  end if;
  if (cursor_sort_rank is null) <> (cursor_server_sequence is null)
    or (cursor_sort_rank is null) <> (cursor_notification_id is null) then
    raise exception 'SOCIAL_INBOX_CURSOR_INVALID' using errcode = '22023';
  end if;

  with eligible as materialized (
    select
      notifications.id,
      notifications.server_sequence,
      notifications.read_at,
      notifications.archived_at,
      descriptor.value as item,
      (descriptor.value ->> 'sortRank')::integer as sort_rank,
      descriptor.value ->> 'sourceDomain' as source_domain,
      descriptor.value ->> 'attentionState' as attention_state
    from public.pachanga_user_notifications notifications
    cross join lateral (
      select private.pachanga_social_inbox_descriptor_v1(notifications.id, actor_id) as value
    ) descriptor
    where notifications.recipient_user_id = actor_id
      and notifications.visible_in_app
      and descriptor.value is not null
  ), filtered as (
    select *
    from eligible
    where (selected_domain is null or source_domain = selected_domain)
      and (
        (selected_view = 'pending' and attention_state = 'ACTION_REQUIRED')
        or (selected_view = 'all' and archived_at is null)
      )
      and (
        cursor_sort_rank is null
        or (sort_rank, server_sequence, id) < (
          cursor_sort_rank, cursor_server_sequence, cursor_notification_id
        )
      )
  ), page_plus_one as materialized (
    select * from filtered
    order by sort_rank desc, server_sequence desc, id desc
    limit selected_size + 1
  ), page_rows as materialized (
    select * from page_plus_one
    order by sort_rank desc, server_sequence desc, id desc
    limit selected_size
  ), last_row as (
    select * from page_rows
    order by sort_rank, server_sequence, id
    limit 1
  )
  select jsonb_build_object(
    'pendingCount', (select count(*) from eligible where attention_state = 'ACTION_REQUIRED'),
    'unreadCount', (select count(*) from eligible where read_at is null and archived_at is null),
    'items', coalesce((
      select jsonb_agg(item - 'sortRank' order by sort_rank desc, server_sequence desc, id desc)
      from page_rows
    ), '[]'::jsonb),
    'filters', jsonb_build_array('MATCH', 'CHALLENGE', 'MARKET', 'TEAM'),
    'view', selected_view,
    'domain', selected_domain,
    'pageSize', selected_size,
    'hasMore', (select count(*) > selected_size from page_plus_one),
    'nextCursor', case when (select count(*) from page_rows) = selected_size then (
      select jsonb_build_object(
        'sortRank', sort_rank,
        'serverSequence', server_sequence,
        'notificationId', id
      ) from last_row
    ) else null end,
    'fetchedAt', clock_timestamp(),
    'serverSequence', coalesce((select max(server_sequence) from eligible), 0)
  ) into response;

  return response;
end;
$$;

revoke all on function public.get_my_pachanga_social_inbox_v1(text, text, integer, integer, bigint, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_social_inbox_v1(text, text, integer, integer, bigint, uuid)
  to authenticated, service_role;

create or replace function public.command_pachanga_social_inbox_v1(
  action text,
  target_notification_id uuid,
  operation_id uuid,
  expected_revision bigint default null,
  expected_server_sequence bigint default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare
  actor_id uuid := (select auth.uid());
  action_name text := lower(trim(coalesce(action, '')));
  actor_operation_id uuid := operation_id;
  receipt private.pachanga_social_inbox_command_receipts_v1%rowtype;
  notification public.pachanga_user_notifications%rowtype;
  descriptor jsonb;
  changed_count integer := 0;
  result_sequence bigint := 0;
  response jsonb;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if operation_id is null then
    raise exception 'OPERATION_ID_REQUIRED' using errcode = '22023';
  end if;
  if action_name not in (
    'inbox.mark_read', 'inbox.mark_unread', 'inbox.mark_all_read', 'inbox.archive'
  ) then
    raise exception 'SOCIAL_INBOX_ACTION_INVALID' using errcode = '22023';
  end if;

  perform set_config('lock_timeout', '5s', true);

  select * into receipt
  from private.pachanga_social_inbox_command_receipts_v1 receipts
  where receipts.operation_id = actor_operation_id;
  if found then
    if receipt.actor_user_id <> actor_id
      or receipt.action <> action_name
      or receipt.notification_id is distinct from target_notification_id
      or receipt.expected_revision is distinct from expected_revision
      or receipt.expected_server_sequence is distinct from expected_server_sequence then
      raise exception 'OPERATION_ID_CONFLICT' using errcode = '23505';
    end if;
    return receipt.response;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(actor_id::text, 0));

  -- A concurrent replay may have committed while this transaction waited for
  -- the per-user lock. Re-read the receipt so the same operation returns the
  -- exact confirmed response instead of colliding on the unique key.
  select * into receipt
  from private.pachanga_social_inbox_command_receipts_v1 receipts
  where receipts.operation_id = actor_operation_id;
  if found then
    if receipt.actor_user_id <> actor_id
      or receipt.action <> action_name
      or receipt.notification_id is distinct from target_notification_id
      or receipt.expected_revision is distinct from expected_revision
      or receipt.expected_server_sequence is distinct from expected_server_sequence then
      raise exception 'OPERATION_ID_CONFLICT' using errcode = '23505';
    end if;
    return receipt.response;
  end if;

  if action_name = 'inbox.mark_all_read' then
    if target_notification_id is not null or expected_server_sequence is null or expected_server_sequence < 0 then
      raise exception 'SOCIAL_INBOX_MARK_ALL_INPUT_INVALID' using errcode = '22023';
    end if;

    with candidates as materialized (
      select notifications.id
      from public.pachanga_user_notifications notifications
      where notifications.recipient_user_id = actor_id
        and notifications.visible_in_app
        and notifications.archived_at is null
        and notifications.read_at is null
        and notifications.server_sequence <= expected_server_sequence
        and private.pachanga_social_inbox_descriptor_v1(notifications.id, actor_id) is not null
      order by notifications.server_sequence, notifications.id
      limit 500
    ), updated as (
      update public.pachanga_user_notifications notifications
      set read_at = clock_timestamp(),
          revision = notifications.revision + 1,
          server_sequence = nextval('public.pachanga_match_guest_sequence'),
          updated_at = clock_timestamp()
      where notifications.id in (select candidates.id from candidates)
      returning notifications.server_sequence
    )
    select count(*)::integer, coalesce(max(server_sequence), expected_server_sequence)
    into changed_count, result_sequence
    from updated;
  else
    if target_notification_id is null or expected_revision is null then
      raise exception 'SOCIAL_INBOX_ITEM_INPUT_REQUIRED' using errcode = '22023';
    end if;

    select * into notification
    from public.pachanga_user_notifications notifications
    where notifications.id = target_notification_id
      and notifications.recipient_user_id = actor_id
      and notifications.visible_in_app
    for update;
    if not found then
      raise exception 'SOCIAL_INBOX_ITEM_NOT_FOUND' using errcode = 'P0002';
    end if;
    descriptor := private.pachanga_social_inbox_descriptor_v1(notification.id, actor_id);
    if descriptor is null then
      raise exception 'SOCIAL_INBOX_ITEM_NOT_FOUND' using errcode = 'P0002';
    end if;
    if notification.revision <> expected_revision then
      raise exception 'SOCIAL_INBOX_STALE' using errcode = 'PT409';
    end if;

    if action_name = 'inbox.mark_read' and notification.read_at is null then
      update public.pachanga_user_notifications notifications
      set read_at = clock_timestamp(),
          revision = notifications.revision + 1,
          server_sequence = nextval('public.pachanga_match_guest_sequence'),
          updated_at = clock_timestamp()
      where notifications.id = notification.id
      returning * into notification;
      changed_count := 1;
    elsif action_name = 'inbox.mark_unread' and notification.read_at is not null then
      update public.pachanga_user_notifications notifications
      set read_at = null,
          revision = notifications.revision + 1,
          server_sequence = nextval('public.pachanga_match_guest_sequence'),
          updated_at = clock_timestamp()
      where notifications.id = notification.id
      returning * into notification;
      changed_count := 1;
    elsif action_name = 'inbox.archive' and notification.archived_at is null then
      update public.pachanga_user_notifications notifications
      set archived_at = clock_timestamp(),
          revision = notifications.revision + 1,
          server_sequence = nextval('public.pachanga_match_guest_sequence'),
          updated_at = clock_timestamp()
      where notifications.id = notification.id
      returning * into notification;
      changed_count := 1;
    end if;
    result_sequence := notification.server_sequence;
  end if;

  response := jsonb_build_object(
    'operationId', actor_operation_id,
    'action', action_name,
    'notificationId', target_notification_id,
    'changedCount', changed_count,
    'confirmedAt', clock_timestamp(),
    'serverSequence', result_sequence,
    'inbox', public.get_my_pachanga_social_inbox_v1('pending', null, 25, null, null, null)
  );

  insert into private.pachanga_social_inbox_command_receipts_v1(
    operation_id, actor_user_id, action, notification_id,
    expected_revision, expected_server_sequence, response, server_sequence
  ) values (
    actor_operation_id, actor_id, action_name, target_notification_id,
    expected_revision, expected_server_sequence, response, result_sequence
  );

  return response;
end;
$$;

revoke all on function public.command_pachanga_social_inbox_v1(text, uuid, uuid, bigint, bigint)
  from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_social_inbox_v1(text, uuid, uuid, bigint, bigint)
  to authenticated, service_role;

create or replace function public.get_my_pachanga_match_invitation_action_v1(
  target_invitation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare
  actor_id uuid := (select auth.uid());
  invitation public.pachanga_match_invitations%rowtype;
  group_row public.pachanga_groups%rowtype;
  match_row jsonb;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  select * into invitation
  from public.pachanga_match_invitations invitations
  where invitations.id = target_invitation_id
    and invitations.invitee_user_id = actor_id;
  if not found then
    raise exception 'MATCH_INVITATION_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into group_row from public.pachanga_groups groups where groups.id = invitation.group_id;
  select matches.value into match_row
  from jsonb_array_elements(coalesce(group_row.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = invitation.match_id
  limit 1;

  return jsonb_strip_nulls(jsonb_build_object(
    'invitationId', invitation.id,
    'groupId', invitation.group_id,
    'teamName', left(group_row.name, 120),
    'matchId', invitation.match_id,
    'matchTitle', left(coalesce(nullif(match_row ->> 'title', ''), nullif(match_row ->> 'name', ''), 'Partido'), 120),
    'matchDate', match_row ->> 'date',
    'matchPlace', left(coalesce(match_row ->> 'place', ''), 160),
    'matchKind', match_row ->> 'kind',
    'status', invitation.status,
    'revision', invitation.revision,
    'matchRevision', group_row.payload_revision,
    'createdAt', invitation.created_at,
    'updatedAt', invitation.updated_at
  ));
end;
$$;

revoke all on function public.get_my_pachanga_match_invitation_action_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_match_invitation_action_v1(uuid)
  to authenticated, service_role;

comment on function public.get_my_pachanga_social_inbox_v1(text, text, integer, integer, bigint, uuid) is
  'V3G social-only read model. It excludes advanced/platform notifications and returns no raw payload.';
comment on function public.command_pachanga_social_inbox_v1(text, uuid, uuid, bigint, bigint) is
  'V3G read/archive command. It never executes a Match, Challenge, Market or Team action.';
