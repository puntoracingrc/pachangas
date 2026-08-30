-- Wave 8B: safe invalidation-only Realtime and mandatory operational notices.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table public.pachanga_team_operational_invalidations_v1 (
  server_sequence bigint primary key,
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  revision bigint not null,
  event_kind text not null,
  created_at timestamptz not null default clock_timestamp(),
  check (entity_type in ('TEAM_OPERATIONAL_STATE', 'TEAM_OWNER')),
  check (revision >= 1),
  check (event_kind ~ '^team\.[a-z][a-z0-9_.]{1,79}$')
);

create index pachanga_team_operational_invalidation_group_idx
  on public.pachanga_team_operational_invalidations_v1(group_id, server_sequence desc);
create index pachanga_team_operational_invalidation_owner_idx
  on public.pachanga_team_operational_invalidations_v1(owner_id, server_sequence desc);

alter table public.pachanga_team_operational_invalidations_v1 enable row level security;
revoke all on table public.pachanga_team_operational_invalidations_v1 from public, anon, authenticated;
grant select on table public.pachanga_team_operational_invalidations_v1 to authenticated;
grant all on table public.pachanga_team_operational_invalidations_v1 to service_role;

create or replace function private.pachanga_team_operational_invalidation_visible_v1(
  target_group_id uuid,
  target_owner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select (select auth.uid()) is not null and (
    target_owner_id = (select auth.uid())
    or exists (
      select 1 from public.pachanga_group_members members
      where members.group_id = target_group_id
        and members.user_id = (select auth.uid())
    )
    or private.pachanga_platform_role_for_user_v1((select auth.uid())) is not null
  );
$$;

revoke all on function private.pachanga_team_operational_invalidation_visible_v1(uuid, uuid)
  from public, anon;
grant execute on function private.pachanga_team_operational_invalidation_visible_v1(uuid, uuid)
  to authenticated, service_role;

create policy pachanga_team_operational_invalidations_member_read_v1
on public.pachanga_team_operational_invalidations_v1
for select to authenticated
using (
  private.pachanga_team_operational_invalidation_visible_v1(group_id, owner_id)
);

create or replace function private.pachanga_team_operational_invalidate_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare owner_id uuid;
declare event_kind text;
begin
  select groups.owner_id into owner_id from public.pachanga_groups groups where groups.id = new.group_id;
  select events.event_kind into event_kind
  from private.pachanga_team_operational_events_v1 events
  where events.operation_id = new.last_operation_id
  order by events.server_sequence desc, events.id desc
  limit 1;
  insert into public.pachanga_team_operational_invalidations_v1(
    server_sequence, group_id, owner_id, entity_type, entity_id,
    revision, event_kind
  ) values (
    new.server_sequence, new.group_id, owner_id, 'TEAM_OPERATIONAL_STATE',
    new.group_id::text, new.current_revision,
    coalesce(event_kind, 'team.state.changed')
  ) on conflict (server_sequence) do nothing;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_invalidate_v1
  on private.pachanga_team_operational_states_v1;
create trigger pachanga_team_operational_invalidate_v1
after update of current_revision on private.pachanga_team_operational_states_v1
for each row execute function private.pachanga_team_operational_invalidate_v1();

create or replace function private.pachanga_team_operational_owner_invalidate_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare sequence_value bigint := nextval('private.pachanga_team_operational_sequence_v1');
declare revision_value bigint;
begin
  if new.owner_id is not distinct from old.owner_id then return new; end if;
  select states.current_revision into revision_value
  from private.pachanga_team_operational_states_v1 states where states.group_id = new.id;
  insert into public.pachanga_team_operational_invalidations_v1(
    server_sequence, group_id, owner_id, entity_type, entity_id, revision, event_kind
  ) values (
    sequence_value, new.id, new.owner_id, 'TEAM_OWNER', new.id::text,
    coalesce(revision_value, 1), 'team.owner.changed'
  );
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_owner_invalidate_v1 on public.pachanga_groups;
create trigger pachanga_team_operational_owner_invalidate_v1
after update of owner_id on public.pachanga_groups
for each row execute function private.pachanga_team_operational_owner_invalidate_v1();

create or replace function private.pachanga_team_operational_notify_event_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare recipient record;
declare organizer record;
declare title text;
declare body text;
declare kind text;
declare action_url text := '/equipo/estado';
declare state_row private.pachanga_team_operational_states_v1%rowtype;
begin
  if new.actor_kind = 'MIGRATION' then return new; end if;
  select * into state_row from private.pachanga_team_operational_states_v1 states where states.group_id = new.group_id;
  kind := 'team_operational_security_' || replace(new.event_kind, '.', '_');
  title := case new.event_kind
    when 'team.review.open' then 'Revisión del equipo abierta'
    when 'team.restriction.apply' then 'Limitación del equipo actualizada'
    when 'team.restriction.modify' then 'Limitación del equipo actualizada'
    when 'team.restriction.lift' then 'Limitación del equipo retirada'
    when 'team.suspend' then 'Equipo suspendido temporalmente'
    when 'team.restore' then 'Equipo restaurado'
    when 'team.lifecycle.archive' then 'Equipo archivado'
    when 'team.lifecycle.restore' then 'Equipo restaurado'
    when 'team.appeal.submit' then 'Revisión solicitada'
    when 'team.appeal.resolve' then 'Revisión resuelta'
    when 'team.expire' then 'Limitación temporal finalizada'
    else 'Estado del equipo actualizado'
  end;
  body := coalesce(nullif(state_row.public_message, ''), case state_row.effective_status
    when 'LIMITED' then 'El equipo tiene disponibilidad limitada. Consulta el detalle.'
    when 'SUSPENDED' then 'El equipo no está disponible actualmente. Consulta el detalle.'
    when 'ARCHIVED' then 'El equipo está archivado.'
    else 'Consulta el estado actualizado del equipo.'
  end);

  for recipient in
    select recipients.user_id
    from private.pachanga_group_notification_recipients_v1(new.group_id, true) recipients
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, kind, title, body, action_url,
      jsonb_build_object(
        'groupId', new.group_id,
        'effectiveStatus', state_row.effective_status,
        'revision', new.aggregate_revision,
        'serverSequence', new.server_sequence
      ),
      'team-operational:' || new.operation_id::text || ':' || recipient.user_id::text
    );
  end loop;

  if new.event_kind = 'team.appeal.submit' then
    for recipient in
      select roles.user_id
      from private.pachanga_platform_admin_roles roles
      where roles.active
        and private.pachanga_platform_capabilities_v1(roles.role) ? 'teams.operational.appeals'
    loop
      perform private.pachanga_notify_v1(
        recipient.user_id, kind, 'Nueva revisión de equipo',
        'Hay una solicitud de revisión pendiente en el Control Center.',
        '/admin/teams/' || new.group_id::text,
        jsonb_build_object('groupId', new.group_id, 'revision', new.aggregate_revision),
        'team-operational-review:' || new.operation_id::text || ':' || recipient.user_id::text
      );
    end loop;
  end if;

  if new.event_kind in ('team.restriction.apply','team.restriction.modify','team.suspend') then
    for organizer in
      select distinct groups.owner_id as user_id, entries.competition_id
      from public.pachanga_competition_entries entries
      join public.pachanga_competitions competitions on competitions.id = entries.competition_id
      join public.pachanga_groups groups on groups.id = competitions.organizer_group_id
      where entries.team_id = new.group_id and entries.status in ('accepted','active')
        and groups.owner_id is not null
    loop
      perform private.pachanga_notify_v1(
        organizer.user_id, kind, 'Equipo con disponibilidad operativa actualizada',
        'Revisa la continuidad de una competición afectada.',
        '/competiciones/' || organizer.competition_id::text,
        jsonb_build_object('groupId', new.group_id, 'competitionId', organizer.competition_id),
        'team-operational-competition:' || new.operation_id::text || ':' || organizer.competition_id::text
      );
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_notify_event_v1
  on private.pachanga_team_operational_events_v1;
create trigger pachanga_team_operational_notify_event_v1
after insert on private.pachanga_team_operational_events_v1
for each row execute function private.pachanga_team_operational_notify_event_v1();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_team_operational_invalidations_v1'
  ) then
    alter publication supabase_realtime add table public.pachanga_team_operational_invalidations_v1;
  end if;
end;
$$;

revoke all on function private.pachanga_team_operational_invalidate_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_owner_invalidate_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_notify_event_v1() from public, anon, authenticated;

comment on table public.pachanga_team_operational_invalidations_v1 is
  'Realtime hint only. Clients must refetch the canonical Team operational snapshot and never apply WAL payloads as authority.';
