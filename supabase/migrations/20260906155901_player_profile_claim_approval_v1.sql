-- A playing-roster entry is claimed only after another team admin approves.
set lock_timeout = '5s';
set statement_timeout = '120s';
create table private.pachanga_player_claims_v1 (
 id uuid primary key default gen_random_uuid(),
 group_id uuid not null references public.pachanga_groups(id) on delete cascade,
 player_id text not null,
 requester_id uuid not null references auth.users(id) on delete cascade,
 state text not null default 'PENDING' check(state in ('PENDING','APPROVED','REJECTED','CANCELLED','SUPERSEDED')),
 decided_by uuid references auth.users(id),
 created_at timestamptz not null default clock_timestamp(),
 decided_at timestamptz,
 profile_id uuid references public.pachanga_player_profiles(id),
 check (decided_by is null or decided_by <> requester_id)
);
alter table private.pachanga_player_claims_v1 enable row level security;
revoke all on private.pachanga_player_claims_v1 from public,anon,authenticated,service_role;
create unique index player_claim_one_pending_user_group on private.pachanga_player_claims_v1(group_id,requester_id) where state='PENDING';
create unique index player_claim_one_approved_player on private.pachanga_player_claims_v1(group_id,player_id) where state='APPROVED';
create index player_claim_group_state on private.pachanga_player_claims_v1(group_id,state,created_at);
create index player_claim_requester on private.pachanga_player_claims_v1(requester_id);

create function private.pachanga_player_claim_guard_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog as $$
declare previous jsonb; entry jsonb; owner_id text; previous_owner text; binding private.pachanga_player_claims_v1%rowtype;
begin
 if new.payload->'players' is not distinct from old.payload->'players' then return new; end if;
 for entry in select value from jsonb_array_elements(coalesce(new.payload->'players','[]')) loop
  select value into previous from jsonb_array_elements(coalesce(old.payload->'players','[]')) where value->>'id'=entry->>'id';
  owner_id := nullif(entry->>'ownerUserId','');
  previous_owner := nullif(previous->>'ownerUserId','');
  if previous_owner is not null and owner_id is distinct from previous_owner then
   raise exception 'PLAYER_OWNER_IMMUTABLE' using errcode='42501';
  end if;
  if owner_id is not null and previous is not null and previous_owner is null then
   if not exists(select 1 from private.pachanga_player_claims_v1 c where c.group_id=new.id and c.player_id=entry->>'id' and c.requester_id::text=owner_id and c.state='APPROVED') then
    raise exception 'PLAYER_CLAIM_APPROVAL_REQUIRED' using errcode='42501';
   end if;
  end if;
  select * into binding from private.pachanga_player_claims_v1 c where c.group_id=new.id and c.player_id=entry->>'id' and c.state='APPROVED';
  if found and (owner_id is distinct from binding.requester_id::text or entry->>'globalPlayerProfileId' is distinct from binding.profile_id::text) then
   raise exception 'PLAYER_OWNER_IMMUTABLE' using errcode='42501';
  end if;
  if nullif(entry->>'globalPlayerProfileId','') is not null
    and (entry->>'globalPlayerProfileId' is distinct from previous->>'globalPlayerProfileId' or owner_id is distinct from previous_owner)
    and not exists(select 1 from public.pachanga_player_profiles p where p.id::text=entry->>'globalPlayerProfileId' and p.user_id::text=owner_id) then
   raise exception 'PLAYER_PROFILE_OWNER_MISMATCH' using errcode='42501';
  end if;
 end loop;
 return new;
end;
$$;
revoke all on function private.pachanga_player_claim_guard_v1() from public,anon,authenticated,service_role;
create trigger pachanga_player_claim_guard_v1 before update of payload on public.pachanga_groups for each row execute function private.pachanga_player_claim_guard_v1();

create function public.get_pachanga_player_claims_v1(target_group_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog as $$
declare actor uuid := auth.uid(); admin_access boolean; group_payload jsonb;
begin
 if actor is null or not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode='42501'; end if;
 select role in ('owner','admin') into admin_access from public.pachanga_group_members where group_id=target_group_id and user_id=actor;
 if not found then raise exception 'TEAM_MEMBERSHIP_REQUIRED' using errcode='42501'; end if;
 select payload into group_payload from public.pachanga_groups where id=target_group_id;
 return jsonb_build_object(
  'canReview',admin_access,
  'hasTeamPlayer',exists(select 1 from jsonb_array_elements(coalesce(group_payload->'players','[]')) p where p->>'ownerUserId'=actor::text),
  'candidates',coalesce((select jsonb_agg(jsonb_build_object('playerId',p->>'id','name',p->>'name','avatar',p->>'avatar') order by p->>'name') from jsonb_array_elements(coalesce(group_payload->'players','[]')) p where nullif(p->>'ownerUserId','') is null and coalesce(p->>'inactive','false')<>'true'),'[]'::jsonb),
  'requests',coalesce((select jsonb_agg(jsonb_build_object(
   'id',c.id,'playerId',c.player_id,'playerName',coalesce((select p->>'name' from jsonb_array_elements(coalesce(group_payload->'players','[]')) p where p->>'id'=c.player_id),'Jugador'),
   'requesterName',coalesce(nullif(s.display_name,''),nullif(pp.display_name,''),nullif(m.display_name,''),'Jugador'),
   'requesterAvatar',pp.avatar,'isMine',c.requester_id=actor,'state',c.state,'createdAt',c.created_at
  ) order by c.created_at desc) from private.pachanga_player_claims_v1 c
  left join public.pachanga_group_members m on m.group_id=c.group_id and m.user_id=c.requester_id
  left join public.pachanga_social_player_profiles_v1 s on s.user_id=c.requester_id
  left join public.pachanga_player_profiles pp on pp.user_id=c.requester_id
  where c.group_id=target_group_id and ((admin_access and c.state='PENDING') or c.requester_id=actor)),'[]'::jsonb)
 );
end;
$$;

create function public.request_pachanga_player_claim_v1(target_group_id uuid,target_player_id text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid:=auth.uid(); g public.pachanga_groups%rowtype; p jsonb; pending private.pachanga_player_claims_v1%rowtype; requester_name text;
begin
 if actor is null or not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode='42501'; end if;
 select * into g from public.pachanga_groups where id=target_group_id for update;
 if not exists(select 1 from public.pachanga_group_members where group_id=target_group_id and user_id=actor) then raise exception 'TEAM_MEMBERSHIP_REQUIRED' using errcode='42501'; end if;
 select value into p from jsonb_array_elements(coalesce(g.payload->'players','[]')) where value->>'id'=target_player_id;
 if p is null or coalesce(p->>'inactive','false')='true' then raise exception 'PLAYER_NOT_AVAILABLE'; end if;
 if nullif(p->>'ownerUserId','') is not null then raise exception 'PLAYER_ALREADY_OWNED'; end if;
 if exists(select 1 from jsonb_array_elements(coalesce(g.payload->'players','[]')) as entries(value) where value->>'ownerUserId'=actor::text) then raise exception 'ALREADY_HAS_TEAM_PLAYER'; end if;
 select * into pending from private.pachanga_player_claims_v1 where group_id=target_group_id and requester_id=actor and state='PENDING';
 if found then
  if pending.player_id<>target_player_id then raise exception 'ANOTHER_CLAIM_PENDING'; end if;
  return jsonb_build_object('requestId',pending.id,'state',pending.state);
 end if;
 insert into private.pachanga_player_claims_v1(group_id,player_id,requester_id) values(target_group_id,target_player_id,actor) returning * into pending;
 select coalesce(nullif(s.display_name,''),nullif(canonical.display_name,''),nullif(m.display_name,''),'Un jugador') into requester_name
 from public.pachanga_group_members m left join public.pachanga_social_player_profiles_v1 s on s.user_id=m.user_id left join public.pachanga_player_profiles canonical on canonical.user_id=m.user_id
 where m.group_id=target_group_id and m.user_id=actor;
 insert into public.pachanga_user_notifications(recipient_user_id,kind,category,priority,mandatory_in_app,visible_in_app,title,body,action_url,payload,dedupe_key)
 select m.user_id,'player_profile_claim_requested','group','normal',true,true,'Solicitud para vincular una ficha',
 requester_name||' solicita la ficha de '||coalesce(p->>'name','Jugador')||'. Confirma que es esa persona.',
 '/equipo/plantilla?team='||target_group_id::text,jsonb_build_object('groupId',target_group_id,'claimId',pending.id),'player-claim:'||pending.id::text||':'||m.user_id::text
 from public.pachanga_group_members m where m.group_id=target_group_id and m.role in ('owner','admin') and m.user_id<>actor;
 return jsonb_build_object('requestId',pending.id,'state',pending.state);
end;
$$;

create function public.decide_pachanga_player_claim_v1(target_claim_id uuid,decision text)
returns jsonb language plpgsql security definer set search_path=pg_catalog as $$
declare actor uuid:=auth.uid(); c private.pachanga_player_claims_v1%rowtype; g public.pachanga_groups%rowtype; p jsonb; profile public.pachanga_player_profiles%rowtype; next_players jsonb; saved_revision bigint; group_id_value uuid; next_state text;
begin
 if actor is null or not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode='42501'; end if;
 if decision not in ('approve','reject','cancel') or decision is null then raise exception 'INVALID_CLAIM_DECISION'; end if;
 select group_id into group_id_value from private.pachanga_player_claims_v1 where id=target_claim_id;
 select * into g from public.pachanga_groups where id=group_id_value for update;
 select * into c from private.pachanga_player_claims_v1 where id=target_claim_id for update;
 if not found then raise exception 'CLAIM_NOT_FOUND'; end if;
 if decision='cancel' then
  if c.requester_id<>actor then raise exception 'CLAIM_OWNER_REQUIRED' using errcode='42501'; end if;
 else
  if not exists(select 1 from public.pachanga_group_members where group_id=c.group_id and user_id=actor and role in ('owner','admin')) then raise exception 'TEAM_ADMIN_REQUIRED' using errcode='42501'; end if;
  if actor=c.requester_id then raise exception 'ANOTHER_ADMIN_REQUIRED' using errcode='42501'; end if;
 end if;
 next_state := case decision when 'approve' then 'APPROVED' when 'reject' then 'REJECTED' else 'CANCELLED' end;
 if c.state=next_state then return jsonb_build_object('state',c.state); end if;
 if c.state<>'PENDING' then raise exception 'CLAIM_ALREADY_DECIDED'; end if;
 if decision='approve' then
  if not exists(select 1 from public.pachanga_group_members where group_id=c.group_id and user_id=c.requester_id) then raise exception 'REQUESTER_LEFT_TEAM'; end if;
  select value into p from jsonb_array_elements(coalesce(g.payload->'players','[]')) where value->>'id'=c.player_id;
  if p is null or coalesce(p->>'inactive','false')='true' then raise exception 'PLAYER_NOT_AVAILABLE'; end if;
  if nullif(p->>'ownerUserId','') is not null then raise exception 'PLAYER_ALREADY_OWNED'; end if;
  if exists(select 1 from jsonb_array_elements(coalesce(g.payload->'players','[]')) as entries(value) where value->>'ownerUserId'=c.requester_id::text) then raise exception 'ALREADY_HAS_TEAM_PLAYER'; end if;
  -- Reuse the account's universal profile without overwriting its card or rewards.
  insert into public.pachanga_player_profiles(user_id,source_group_id,source_player_id,display_name,avatar,position,outfield_position,stats)
  values(c.requester_id,c.group_id,c.player_id,coalesce(nullif(p->>'name',''),'Jugador'),nullif(p->>'avatar',''),coalesce(nullif(p->>'position',''),'Mediocentro / pivote'),nullif(p->>'outfieldPosition',''),
   jsonb_build_object('goals',coalesce(p->'goals','0'::jsonb),'assists',coalesce(p->'assists','0'::jsonb),'appearances',coalesce(p->'appearances','0'::jsonb),'wins',coalesce(p->'wins','0'::jsonb)))
  on conflict(user_id) do nothing;
  select * into profile from public.pachanga_player_profiles where user_id=c.requester_id for update;
  update private.pachanga_player_claims_v1 set state='APPROVED',decided_by=actor,decided_at=clock_timestamp(),profile_id=profile.id where id=c.id;
  -- Keep the stable roster id, all match references, team statistics and photo.
  select jsonb_agg(case when value->>'id'=c.player_id then value||jsonb_build_object('ownerUserId',c.requester_id::text,'globalPlayerProfileId',profile.id::text) else value end order by ordinality)
  into next_players from jsonb_array_elements(g.payload->'players') with ordinality;
  update public.pachanga_groups set payload=g.payload||jsonb_build_object('players',next_players) where id=c.group_id returning payload_revision into saved_revision;
  perform public.sync_pachanga_group_read_model(c.group_id,g.payload||jsonb_build_object('players',next_players),saved_revision);
  update private.pachanga_player_claims_v1 set state='SUPERSEDED',decided_at=clock_timestamp(),decided_by=case when requester_id=actor then null else actor end where group_id=c.group_id and player_id=c.player_id and state='PENDING';
 else
  update private.pachanga_player_claims_v1 set state=next_state,decided_at=clock_timestamp(),decided_by=case when decision='cancel' then null else actor end where id=c.id;
 end if;
 -- Close existing admin notices and notify requesters of the confirmed result, in-app only.
 update public.pachanga_user_notifications n set read_at=coalesce(n.read_at,clock_timestamp()),revision=n.revision+1,server_sequence=nextval('public.pachanga_match_guest_sequence'),updated_at=clock_timestamp()
 where n.kind='player_profile_claim_requested' and n.payload->>'claimId' in (select id::text from private.pachanga_player_claims_v1 where group_id=c.group_id and player_id=c.player_id and state<>'PENDING');
 insert into public.pachanga_user_notifications(recipient_user_id,kind,category,priority,mandatory_in_app,visible_in_app,title,body,action_url,payload,dedupe_key)
 select requester_id,'player_profile_claim_decided','group','normal',true,true,
 case when state='APPROVED' then 'Tu ficha ya está vinculada' else 'Solicitud de ficha resuelta' end,
 case state when 'APPROVED' then 'Tu cuenta ya está vinculada al jugador del equipo. Conservas sus partidos y estadísticas.' when 'REJECTED' then 'El administrador ha rechazado la solicitud. Habla con él si ha habido un error.' when 'SUPERSEDED' then 'La ficha se ha vinculado a otra cuenta tras la revisión del administrador.' else 'Has cancelado la solicitud de ficha.' end,
 '/equipo/plantilla?team='||group_id::text,jsonb_build_object('groupId',group_id,'claimId',id),'player-claim-result:'||id::text
 from private.pachanga_player_claims_v1 where group_id=c.group_id and player_id=c.player_id and state<>'PENDING'
 on conflict(dedupe_key) do nothing;
 return jsonb_build_object('state',next_state);
end;
$$;
revoke all on function public.get_pachanga_player_claims_v1(uuid) from public,anon;
revoke all on function public.request_pachanga_player_claim_v1(uuid,text) from public,anon;
revoke all on function public.decide_pachanga_player_claim_v1(uuid,text) from public,anon;
grant execute on function public.get_pachanga_player_claims_v1(uuid), public.request_pachanga_player_claim_v1(uuid,text),public.decide_pachanga_player_claim_v1(uuid,text) to authenticated;

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
    when kind in ('player_profile_claim_requested','player_profile_claim_decided') then 'TEAM'
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

  if notice.kind in ('player_profile_claim_requested','player_profile_claim_decided') then
    source_uuid := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'claimId');
    source_group_id := private.pachanga_social_inbox_try_uuid_v1(notice.payload ->> 'groupId');
    source_id := source_uuid::text;
    context_label := 'Ficha de jugador';
    if not exists(select 1 from public.pachanga_group_members where group_id=source_group_id and user_id=target_actor_id) then return null; end if;
    deep_link := '/equipo/plantilla?team='||source_group_id::text;
    cta_label := 'Ver solicitud';
    if exists(select 1 from private.pachanga_player_claims_v1 c where c.id=source_uuid and c.state='PENDING')
      and exists(select 1 from public.pachanga_group_members where group_id=source_group_id and user_id=target_actor_id and role in ('owner','admin')) then
      attention_state := 'ACTION_REQUIRED'; status_label := 'Pendiente de aprobación';
    else attention_state := 'RESOLVED'; status_label := 'Solicitud resuelta'; end if;

  elsif notice.kind = 'roulette_free_spin_reward' then
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
$function$;
