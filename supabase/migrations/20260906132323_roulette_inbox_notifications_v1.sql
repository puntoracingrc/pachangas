-- Free roulette credits share the canonical in-app inbox and receipts.
set lock_timeout = '5s';
set statement_timeout = '120s';

-- Internal-only projection: never enqueues email or push delivery.
create function private.pachanga_roulette_credit_notice_v1(target_credit_id uuid)
returns void language plpgsql security invoker set search_path=pg_catalog as $$
declare credit private.pachanga_roulette_credits%rowtype;
begin
  select * into credit from private.pachanga_roulette_credits where id=target_credit_id;
  if not found then return; end if;
  if credit.consumed_at is null then
    insert into public.pachanga_user_notifications(
      recipient_user_id,kind,category,priority,mandatory_in_app,visible_in_app,
      title,body,action_url,payload,dedupe_key
    ) values (
      credit.user_id,'roulette_free_spin_reward','achievement','normal',true,true,
      'Tienes un giro gratis en la ruleta',
      case credit.origin
        when 'assessment:initial' then 'Has completado el test inicial. Tu giro gratis te espera en la ruleta.'
        when 'assessment:advanced' then 'Has completado el test avanzado. Has conseguido otro giro gratis en la ruleta.'
        else case when credit.origin like 'week:%'
          then 'Ya tienes tu giro gratis semanal por haber jugado un partido en los últimos 30 días.'
          else 'Has conseguido un giro gratis. Descubre qué cofre te toca en la ruleta.' end
      end,
      '/ruleta',jsonb_build_object('creditId',credit.id,'origin',credit.origin),
      'roulette-credit:'||credit.id::text
    ) on conflict(dedupe_key) do nothing;
  else
    update public.pachanga_user_notifications n
    set title='Giro gratis utilizado',body='Ya has utilizado este giro gratis en la ruleta.',
        read_at=coalesce(n.read_at,clock_timestamp()),
        revision=n.revision+1,server_sequence=nextval('public.pachanga_match_guest_sequence'),
        updated_at=clock_timestamp()
    where n.recipient_user_id=credit.user_id
      and n.dedupe_key='roulette-credit:'||credit.id::text
      and n.title is distinct from 'Giro gratis utilizado';
  end if;
end;
$$;
revoke all on function private.pachanga_roulette_credit_notice_v1(uuid) from public,anon,authenticated;

create function private.pachanga_roulette_credit_notice_trigger_v1()
returns trigger language plpgsql security invoker set search_path=pg_catalog as $$
begin
  perform private.pachanga_roulette_credit_notice_v1(new.id);
  return new;
end;
$$;
revoke all on function private.pachanga_roulette_credit_notice_trigger_v1() from public,anon,authenticated;
create trigger pachanga_roulette_credit_notice_v1
  after insert or update of consumed_at on private.pachanga_roulette_credits
  for each row execute function private.pachanga_roulette_credit_notice_trigger_v1();

CREATE OR REPLACE FUNCTION private.pachanga_social_inbox_domain_v1(target_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  with normalized as (
    select lower(trim(coalesce(target_kind, ''))) as kind
  )
  select case
    when kind = 'roulette_free_spin_reward' then 'REWARD'
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
$function$
;

CREATE OR REPLACE FUNCTION private.pachanga_social_inbox_descriptor_v1(target_notification_id uuid, target_actor_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
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

  if notice.kind = 'roulette_free_spin_reward' then
    source_uuid := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'creditId');
    source_id := source_uuid::text;
    context_label := 'Ruleta de premios';
    if exists(select 1 from private.pachanga_roulette_credits c
      where c.id=source_uuid and c.user_id=target_actor_id and c.consumed_at is null) then
      attention_state := 'ACTION_REQUIRED';
      status_label := 'Giro gratis disponible';
      deep_link := '/ruleta';
      cta_label := 'Ir a la ruleta';
    else
      attention_state := 'RESOLVED';
      status_label := 'Giro utilizado';
    end if;

  elsif notice.kind like 'team_challenge_%' then
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
$function$
;

CREATE OR REPLACE FUNCTION public.get_my_pachanga_social_inbox_v1(target_view text DEFAULT 'pending'::text, target_domain text DEFAULT NULL::text, page_size integer DEFAULT 25, cursor_sort_rank integer DEFAULT NULL::integer, cursor_server_sequence bigint DEFAULT NULL::bigint, cursor_notification_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 VOLATILE SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
#variable_conflict use_variable
declare
  actor_id uuid := (select auth.uid());
  selected_view text := lower(trim(coalesce(target_view, 'pending')));
  selected_domain text := upper(nullif(trim(coalesce(target_domain, '')), ''));
  selected_size integer := greatest(1, least(coalesce(page_size, 25), 50));
  response jsonb;
  player_profile uuid;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if selected_view not in ('pending', 'all') then
    raise exception 'SOCIAL_INBOX_VIEW_INVALID' using errcode = '22023';
  end if;
  if selected_domain is not null and selected_domain not in ('MATCH', 'CHALLENGE', 'MARKET', 'TEAM', 'REWARD') then
    raise exception 'SOCIAL_INBOX_DOMAIN_INVALID' using errcode = '22023';
  end if;
  if (cursor_sort_rank is null) <> (cursor_server_sequence is null)
    or (cursor_sort_rank is null) <> (cursor_notification_id is null) then
    raise exception 'SOCIAL_INBOX_CURSOR_INVALID' using errcode = '22023';
  end if;

  -- Reconcile earned credits when the bell loads, before visiting the roulette.
  -- Use the same per-user lock as spinning to serialize grant/consume/notice writes.
  select id into player_profile from public.pachanga_player_profiles where user_id=actor_id;
  if player_profile is not null then
    perform pg_advisory_xact_lock(hashtextextended('roulette:'||actor_id::text,0));
    perform private.pachanga_roulette_sync_credits(actor_id,player_profile);
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
    'filters', jsonb_build_array('MATCH', 'CHALLENGE', 'MARKET', 'TEAM', 'REWARD'),
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
$function$
;

-- Only announce credits that remain usable; spent credits never create a new alert.
do $$ declare credit_id uuid; begin
  for credit_id in select id from private.pachanga_roulette_credits where consumed_at is null loop
    perform private.pachanga_roulette_credit_notice_v1(credit_id);
  end loop;
end $$;
