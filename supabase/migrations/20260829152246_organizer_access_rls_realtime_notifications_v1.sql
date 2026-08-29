-- Wave 8A: least-privilege invalidation, Realtime convergence and notifications.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table public.pachanga_organizer_access_invalidations_v1 (
  scope_key text primary key,
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete cascade,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete cascade,
  application_id uuid references private.pachanga_organizer_access_applications_v1(id) on delete cascade,
  entity_kind text not null,
  entity_revision bigint not null,
  server_sequence bigint not null,
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM','CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (scope_key = organizer_kind || ':' || coalesce(organizer_group_id, organizer_club_id)::text),
  check (entity_kind ~ '^[A-Z][A-Z0-9_]{2,79}$'),
  check (entity_revision >= 0)
);

create index pachanga_organizer_access_invalidation_application_idx
  on public.pachanga_organizer_access_invalidations_v1(application_id, server_sequence desc, scope_key)
  where application_id is not null;
create index pachanga_organizer_access_invalidation_team_idx
  on public.pachanga_organizer_access_invalidations_v1(organizer_group_id, server_sequence desc)
  where organizer_kind = 'TEAM';
create index pachanga_organizer_access_invalidation_club_idx
  on public.pachanga_organizer_access_invalidations_v1(organizer_club_id, server_sequence desc)
  where organizer_kind = 'CLUB';

create or replace function private.pachanga_organizer_access_invalidation_can_read_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare actor_role text;
begin
  if actor_id is null then return false; end if;
  if private.pachanga_organizer_access_actor_can_v1(
    target_organizer_kind, target_organizer_id, actor_id, 'read'
  ) then return true; end if;
  actor_role := private.pachanga_platform_role_for_user_v1(actor_id);
  return actor_role is not null
    and private.pachanga_platform_capabilities_v1(actor_role) ? 'organizer_access.read';
end;
$$;

create or replace function private.pachanga_organizer_access_touch_invalidation_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_application_id uuid,
  target_entity_kind text,
  target_entity_revision bigint,
  target_server_sequence bigint
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind,'')));
declare scope_value text;
begin
  if normalized_kind not in ('TEAM','CLUB') or target_organizer_id is null then
    raise exception 'ORGANIZER_ACCESS_INVALIDATION_SCOPE_INVALID' using errcode = '22023';
  end if;
  scope_value := normalized_kind || ':' || target_organizer_id::text;
  insert into public.pachanga_organizer_access_invalidations_v1(
    scope_key, organizer_kind, organizer_group_id, organizer_club_id,
    application_id, entity_kind, entity_revision, server_sequence, updated_at
  ) values (
    scope_value, normalized_kind,
    case when normalized_kind = 'TEAM' then target_organizer_id end,
    case when normalized_kind = 'CLUB' then target_organizer_id end,
    target_application_id, upper(trim(target_entity_kind)),
    greatest(coalesce(target_entity_revision,0),0), target_server_sequence,
    clock_timestamp()
  ) on conflict (scope_key) do update set
    application_id = excluded.application_id,
    entity_kind = excluded.entity_kind,
    entity_revision = excluded.entity_revision,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at
  where excluded.server_sequence > public.pachanga_organizer_access_invalidations_v1.server_sequence;
end;
$$;

create or replace function private.pachanga_organizer_access_event_side_effects_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare organizer_id uuid := coalesce(new.organizer_group_id, new.organizer_club_id);
declare owner_id uuid;
declare recipient record;
declare title_value text;
declare body_value text;
declare action_url_value text;
declare dedupe_key_value text;
declare workspace_status text;
begin
  if new.organizer_kind in ('TEAM','CLUB') and organizer_id is not null then
    perform private.pachanga_organizer_access_touch_invalidation_v1(
      new.organizer_kind, organizer_id, new.application_id,
      case new.aggregate_type
        when 'organizer_onboarding' then 'ORGANIZER_ONBOARDING'
        when 'organizer_access_grant' then 'ORGANIZER_ACCESS_GRANT'
        else 'ORGANIZER_ACCESS_APPLICATION'
      end,
      new.aggregate_revision, new.server_sequence
    );
  end if;
  if new.application_id is null then return new; end if;
  owner_id := private.pachanga_organizer_access_owner_id_v1(new.organizer_kind, organizer_id);
  action_url_value := '/organizacion/solicitudes/' || new.application_id::text;

  if new.action = 'application.submit' and owner_id is not null then
    perform private.pachanga_notify_v1(
      owner_id, 'organizer_access_warning', 'Solicitud enviada',
      'Tu solicitud de organización ya está en la cola de revisión.',
      action_url_value,
      jsonb_build_object('applicationId', new.application_id, 'action', new.action),
      'organizer-access:submitted:' || new.application_id::text || ':' || owner_id::text
    );
  end if;

  if new.action in (
       'review.start','review.request_information','review.approve',
       'review.reject','review.expire'
     ) and owner_id is not null then
    title_value := case new.action
      when 'review.start' then 'Revisión iniciada'
      when 'review.request_information' then 'Necesitamos más información'
      when 'review.approve' then 'Solicitud de organización revisada'
      when 'review.reject' then 'Solicitud de organización resuelta'
      else 'Solicitud de organización cerrada' end;
    body_value := case new.action
      when 'review.start' then 'La plataforma ha comenzado a revisar tu solicitud.'
      when 'review.request_information' then 'Revisa la solicitud y responde desde Pachangas IQ.'
      when 'review.approve' then 'Ya puedes consultar la decisión y los siguientes pasos.'
      when 'review.reject' then 'Consulta la decisión desde tu área de organización.'
      else 'La solicitud ha vencido. Puedes consultar su estado.' end;
    perform private.pachanga_notify_v1(
      owner_id, 'organizer_access_warning', title_value, body_value,
      action_url_value,
      jsonb_build_object('applicationId', new.application_id, 'action', new.action),
      'organizer-access:' || new.operation_id::text || ':' || owner_id::text || ':decision'
    );
  end if;

  if new.action = 'review.approve' and owner_id is not null
     and nullif(new.event_payload ->> 'accessGrantId','') is not null then
    perform private.pachanga_notify_v1(
      owner_id, 'organizer_access_warning', 'Acceso de organizador concedido',
      'El acceso canónico ya está activo para tu Club o equipo.',
      '/organizacion/onboarding',
      jsonb_build_object(
        'applicationId', new.application_id,
        'accessGrantId', new.event_payload ->> 'accessGrantId',
        'action', 'access.granted'
      ),
      'organizer-access:grant:' || (new.event_payload ->> 'accessGrantId') || ':' || owner_id::text
    );
  end if;

  if new.action = 'review.approve' and owner_id is not null
     and nullif(new.event_payload ->> 'onboardingId','') is not null then
    perform private.pachanga_notify_v1(
      owner_id, 'organizer_access_warning', 'Onboarding disponible',
      'Ya puedes preparar tu primera competición desde el asistente guiado.',
      '/organizacion/onboarding',
      jsonb_build_object(
        'applicationId', new.application_id,
        'onboardingId', new.event_payload ->> 'onboardingId',
        'action', 'onboarding.available'
      ),
      'organizer-access:onboarding:' || (new.event_payload ->> 'onboardingId') || ':available:' || owner_id::text
    );
  end if;

  if new.action = 'competition.launch' and owner_id is not null then
    perform private.pachanga_notify_v1(
      owner_id, 'organizer_access_warning', 'Primer borrador creado',
      'Tu primera competición ya existe como borrador canónico.',
      '/organizacion/onboarding',
      jsonb_build_object(
        'applicationId', new.application_id,
        'launcherKind', new.event_payload ->> 'launcherKind',
        'launcherAggregateId', new.event_payload ->> 'launcherAggregateId',
        'action', new.action
      ),
      'organizer-access:first-draft:' || coalesce(
        nullif(new.event_payload ->> 'launcherAggregateId',''), new.aggregate_id
      ) || ':' || owner_id::text
    );
  end if;

  if new.action = 'onboarding.refresh' and owner_id is not null then
    select workspaces.status into workspace_status
    from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
    where workspaces.id::text = new.aggregate_id;
    if workspace_status = 'completed' then
      perform private.pachanga_notify_v1(
        owner_id, 'organizer_access_warning', 'Onboarding completado',
        'Tu espacio de organización ya está preparado para operar la competición.',
        '/organizacion/onboarding',
        jsonb_build_object(
          'applicationId', new.application_id,
          'onboardingId', new.aggregate_id,
          'action', 'onboarding.completed'
        ),
        'organizer-access:onboarding:' || new.aggregate_id || ':completed:' || owner_id::text
      );
    end if;
  end if;

  if new.action = 'access.expiry_notification' and owner_id is not null then
    dedupe_key_value := 'organizer-access:expiring:' || new.aggregate_id || ':'
      || coalesce(new.event_payload ->> 'validUntil','unknown') || ':' || owner_id::text;
    perform private.pachanga_notify_v1(
      owner_id, 'organizer_access_warning', 'Tu acceso de organizador vencerá pronto',
      'Revisa la fecha de vigencia y las opciones disponibles antes de crear otra competición.',
      '/organizacion/solicitudes/' || new.application_id::text,
      jsonb_build_object(
        'applicationId', new.application_id,
        'accessGrantId', new.aggregate_id,
        'validUntil', new.event_payload ->> 'validUntil',
        'action', new.action
      ), dedupe_key_value
    );
  end if;

  if new.action in ('application.submit','application.respond_information','application.withdraw') then
    title_value := case new.action
      when 'application.submit' then 'Nueva solicitud de organización'
      when 'application.respond_information' then 'Solicitud de organización actualizada'
      else 'Solicitud de organización retirada' end;
    body_value := 'Hay una solicitud que requiere revisión en el Control Center.';
    for recipient in
      select roles.user_id
      from private.pachanga_platform_admin_roles roles
      where roles.active and roles.role in ('platform_owner','platform_admin','support')
        and roles.user_id is distinct from new.actor_id
    loop
      perform private.pachanga_notify_v1(
        recipient.user_id, 'organizer_access_warning', title_value, body_value,
        '/admin/organizer-access?application=' || new.application_id::text,
        jsonb_build_object('applicationId', new.application_id, 'action', new.action),
        'organizer-access:' || new.operation_id::text || ':' || recipient.user_id::text || ':platform'
      );
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_organizer_access_event_side_effects_v1
  on private.pachanga_organizer_access_events_v1;
create trigger pachanga_organizer_access_event_side_effects_v1
after insert on private.pachanga_organizer_access_events_v1
for each row execute function private.pachanga_organizer_access_event_side_effects_v1();

create or replace function public.process_pachanga_organizer_access_expiry_notifications_v1(
  operation_id uuid,
  batch_size integer default 100
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare safe_limit integer := least(greatest(coalesce(batch_size, 100), 1), 500);
declare prior private.pachanga_organizer_access_operation_receipts_v1%rowtype;
declare access record;
declare owner_id uuid;
declare request_hash text;
declare receipt_sequence bigint;
declare event_sequence bigint;
declare event_operation_id uuid;
declare dedupe_key_value text;
declare notified_count integer := 0;
declare response jsonb;
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if operation_id is null then
    raise exception 'ORGANIZER_ACCESS_OPERATION_ID_REQUIRED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_organizer_access_request_hash_v1(
    'access.expiry_notifications',
    '00000000-0000-4000-8000-000000000000'::uuid,
    0,
    jsonb_build_object('batchSize', safe_limit, 'windowDays', 7)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 80846));
  select * into prior
  from private.pachanga_organizer_access_operation_receipts_v1 receipts
  where receipts.operation_id = process_pachanga_organizer_access_expiry_notifications_v1.operation_id;
  if found then
    if prior.request_hash <> request_hash then
      raise exception 'ORGANIZER_ACCESS_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;

  for access in
    select grants.*, decisions.application_id
    from private.pachanga_organizer_access_grants_v1 grants
    join private.pachanga_organizer_access_decisions_v1 decisions
      on decisions.id = grants.organizer_access_decision_id
    where grants.status in ('active','grace','continuity')
      and grants.valid_until is not null
      and grants.valid_until > clock_timestamp()
      and grants.valid_until <= clock_timestamp() + interval '7 days'
    order by grants.valid_until, grants.server_sequence, grants.id
    for update of grants skip locked
    limit safe_limit
  loop
    owner_id := private.pachanga_organizer_access_owner_id_v1(
      access.organizer_kind,
      coalesce(access.organizer_group_id, access.organizer_club_id)
    );
    dedupe_key_value := 'organizer-access:expiring:' || access.id::text || ':'
      || to_char(access.valid_until at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      || ':' || coalesce(owner_id::text, 'missing-owner');
    if owner_id is null or exists (
      select 1 from public.pachanga_user_notifications notifications
      where notifications.dedupe_key = dedupe_key_value
    ) then
      continue;
    end if;
    event_sequence := nextval('private.pachanga_organizer_access_sequence');
    event_operation_id := (md5(operation_id::text || ':' || access.id::text))::uuid;
    insert into private.pachanga_organizer_access_events_v1(
      operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
      application_id, organizer_kind, organizer_group_id, organizer_club_id,
      aggregate_revision, reason_code, event_payload, server_sequence, confirmed_at
    ) values (
      event_operation_id, null, 'service_authority', 'access.expiry_notification',
      'organizer_access_grant', access.id::text, access.application_id,
      access.organizer_kind, access.organizer_group_id, access.organizer_club_id,
      access.revision, 'access.expiry_notification',
      jsonb_build_object(
        'accessGrantId', access.id,
        'validUntil', to_char(access.valid_until at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ), event_sequence, clock_timestamp()
    );
    notified_count := notified_count + 1;
  end loop;

  receipt_sequence := nextval('private.pachanga_organizer_access_sequence');
  response := jsonb_build_object(
    'notified', notified_count,
    'windowDays', 7,
    'confirmedRevision', notified_count,
    'serverSequence', receipt_sequence,
    'replayed', false
  );
  insert into private.pachanga_organizer_access_operation_receipts_v1(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response
  ) values (
    operation_id, null, 'service_authority', 'access.expiry_notifications',
    'organizer_access_notifications', 'global', request_hash, notified_count,
    receipt_sequence, '{}'::jsonb, response
  );
  return response;
end;
$$;

alter table public.pachanga_organizer_access_invalidations_v1 enable row level security;
revoke all on table public.pachanga_organizer_access_invalidations_v1 from public, anon, authenticated;
grant select on table public.pachanga_organizer_access_invalidations_v1 to authenticated;

create policy "Organizer access participants read invalidations"
on public.pachanga_organizer_access_invalidations_v1
for select to authenticated
using (private.pachanga_organizer_access_invalidation_can_read_v1(
  organizer_kind, coalesce(organizer_group_id, organizer_club_id)
));

alter table public.pachanga_organizer_access_invalidations_v1 replica identity full;
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'pachanga_organizer_access_invalidations_v1'
     ) then
    alter publication supabase_realtime add table public.pachanga_organizer_access_invalidations_v1;
  end if;
end;
$$;

revoke all on function private.pachanga_organizer_access_invalidation_can_read_v1(text, uuid) from public, anon, authenticated;
grant execute on function private.pachanga_organizer_access_invalidation_can_read_v1(text, uuid) to authenticated;
revoke all on function private.pachanga_organizer_access_touch_invalidation_v1(text, uuid, uuid, text, bigint, bigint) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_event_side_effects_v1() from public, anon, authenticated;
revoke all on function public.process_pachanga_organizer_access_expiry_notifications_v1(uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.process_pachanga_organizer_access_expiry_notifications_v1(uuid, integer)
  to service_role;

comment on table public.pachanga_organizer_access_invalidations_v1 is
  'Realtime invalidation only. Clients must refetch canonical organizer access read models.';

comment on function public.process_pachanga_organizer_access_expiry_notifications_v1(uuid, integer) is
  'Service-only idempotent seven-day reminder worker for expiring organizer access grants.';
