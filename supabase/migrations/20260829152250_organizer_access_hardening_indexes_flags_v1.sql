-- Wave 8A: immutability, existing-grant onboarding and final hardening.

set lock_timeout = '5s';
set statement_timeout = '5min';

alter table private.pachanga_organizer_access_rate_limit_overrides_v1
  drop constraint if exists pachanga_organizer_access_rate_limit_overr_action_pattern_check;
alter table private.pachanga_organizer_access_rate_limit_overrides_v1
  add constraint pachanga_organizer_access_rate_pattern_check check (
    action_pattern ~ '^[a-z][a-z0-9_.]{2,79}$'
    or action_pattern ~ '^[a-z][a-z0-9_.]{1,76}\.\*$'
  );

create or replace function private.pachanga_organizer_access_immutable_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'ORGANIZER_ACCESS_EVIDENCE_IMMUTABLE' using errcode = '42501';
end;
$$;

create or replace function private.pachanga_organizer_access_decision_update_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if old.decision_type = 'APPROVED'
     and old.resulting_access_grant_id is null
     and new.resulting_access_grant_id is not null
     and row(
       new.id,new.application_id,new.application_revision,new.decision_type,new.decision_code,
       new.applicant_message,new.private_note,new.grant_plan_code,new.grant_source,
       new.grant_valid_from,new.grant_valid_until,new.grant_limits,new.grant_capabilities,
       new.supersedes_decision_id,new.decided_by,new.revision,new.server_sequence,
       new.decided_at,new.created_at
     ) is not distinct from row(
       old.id,old.application_id,old.application_revision,old.decision_type,old.decision_code,
       old.applicant_message,old.private_note,old.grant_plan_code,old.grant_source,
       old.grant_valid_from,old.grant_valid_until,old.grant_limits,old.grant_capabilities,
       old.supersedes_decision_id,old.decided_by,old.revision,old.server_sequence,
       old.decided_at,old.created_at
     ) then
    return new;
  end if;
  raise exception 'ORGANIZER_ACCESS_DECISION_IMMUTABLE' using errcode = '42501';
end;
$$;

drop trigger if exists pachanga_organizer_access_revision_immutable_v1
  on private.pachanga_organizer_access_application_revisions_v1;
create trigger pachanga_organizer_access_revision_immutable_v1
before update or delete on private.pachanga_organizer_access_application_revisions_v1
for each row execute function private.pachanga_organizer_access_immutable_v1();

drop trigger if exists pachanga_organizer_access_message_immutable_v1
  on private.pachanga_organizer_access_messages_v1;
create trigger pachanga_organizer_access_message_immutable_v1
before update or delete on private.pachanga_organizer_access_messages_v1
for each row execute function private.pachanga_organizer_access_immutable_v1();

drop trigger if exists pachanga_organizer_access_decision_update_guard_v1
  on private.pachanga_organizer_access_decisions_v1;
create trigger pachanga_organizer_access_decision_update_guard_v1
before update on private.pachanga_organizer_access_decisions_v1
for each row execute function private.pachanga_organizer_access_decision_update_guard_v1();

drop trigger if exists pachanga_organizer_access_decision_delete_guard_v1
  on private.pachanga_organizer_access_decisions_v1;
create trigger pachanga_organizer_access_decision_delete_guard_v1
before delete on private.pachanga_organizer_access_decisions_v1
for each row execute function private.pachanga_organizer_access_immutable_v1();

drop trigger if exists pachanga_organizer_access_receipt_immutable_v1
  on private.pachanga_organizer_access_operation_receipts_v1;
create trigger pachanga_organizer_access_receipt_immutable_v1
before update or delete on private.pachanga_organizer_access_operation_receipts_v1
for each row execute function private.pachanga_organizer_access_immutable_v1();

drop trigger if exists pachanga_organizer_access_event_immutable_v1
  on private.pachanga_organizer_access_events_v1;
create trigger pachanga_organizer_access_event_immutable_v1
before update or delete on private.pachanga_organizer_access_events_v1
for each row execute function private.pachanga_organizer_access_immutable_v1();

drop trigger if exists pachanga_organizer_onboarding_event_immutable_v1
  on private.pachanga_organizer_onboarding_events_v1;
create trigger pachanga_organizer_onboarding_event_immutable_v1
before update or delete on private.pachanga_organizer_onboarding_events_v1
for each row execute function private.pachanga_organizer_access_immutable_v1();

create or replace function private.pachanga_organizer_ensure_existing_grant_onboarding_v1(
  target_access_grant_id uuid,
  target_actor_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare access private.pachanga_organizer_access_grants_v1%rowtype;
declare workspace private.pachanga_organizer_onboarding_workspaces_v1%rowtype;
declare organizer_id uuid;
declare owner_id uuid;
begin
  select * into access from private.pachanga_organizer_access_grants_v1 grants
  where grants.id = target_access_grant_id and grants.status in ('active','grace','continuity');
  if not found then raise exception 'ORGANIZER_ONBOARDING_ACCESS_REQUIRED' using errcode = '42501'; end if;
  organizer_id := coalesce(access.organizer_group_id, access.organizer_club_id);
  owner_id := coalesce(target_actor_id, private.pachanga_organizer_access_owner_id_v1(access.organizer_kind, organizer_id));
  if owner_id is null then raise exception 'ORGANIZER_ONBOARDING_OWNER_REQUIRED' using errcode = '42501'; end if;
  select * into workspace from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
  where workspaces.organizer_kind = access.organizer_kind
    and (
      (access.organizer_kind = 'TEAM' and workspaces.organizer_group_id = organizer_id)
      or (access.organizer_kind = 'CLUB' and workspaces.organizer_club_id = organizer_id)
    ) and workspaces.status in ('active','completed')
  order by workspaces.server_sequence desc, workspaces.id desc limit 1;
  if not found then
    insert into private.pachanga_organizer_onboarding_workspaces_v1(
      organizer_kind, organizer_group_id, organizer_club_id, origin,
      source_access_grant_id, status, next_action, created_by
    ) values (
      access.organizer_kind,
      case when access.organizer_kind = 'TEAM' then organizer_id end,
      case when access.organizer_kind = 'CLUB' then organizer_id end,
      'EXISTING_GRANT', access.id, 'active', 'ACCESS_APPROVED', owner_id
    ) returning * into workspace;
  end if;
  perform private.pachanga_refresh_organizer_onboarding_v1(workspace.id, owner_id, 'existing_grant');
  return workspace.id;
end;
$$;

create or replace function private.pachanga_organizer_access_grant_onboarding_trigger_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if new.status in ('active','grace','continuity')
     and new.organizer_access_decision_id is null then
    perform private.pachanga_organizer_ensure_existing_grant_onboarding_v1(new.id, new.granted_by);
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_organizer_access_grant_onboarding_v1
  on private.pachanga_organizer_access_grants_v1;
create trigger pachanga_organizer_access_grant_onboarding_v1
after insert on private.pachanga_organizer_access_grants_v1
for each row execute function private.pachanga_organizer_access_grant_onboarding_trigger_v1();

do $$
declare access record;
begin
  for access in
    select grants.id, grants.granted_by
    from private.pachanga_organizer_access_grants_v1 grants
    where grants.status in ('active','grace','continuity')
      and grants.valid_from <= clock_timestamp()
      and (grants.valid_until is null or grants.valid_until > clock_timestamp())
    order by grants.server_sequence, grants.id
  loop
    perform private.pachanga_organizer_ensure_existing_grant_onboarding_v1(access.id, access.granted_by);
  end loop;
end;
$$;

create index if not exists pachanga_organizer_access_application_current_revision_idx
  on private.pachanga_organizer_access_applications_v1(current_revision_id);
create index if not exists pachanga_organizer_access_application_created_by_idx
  on private.pachanga_organizer_access_applications_v1(created_by, server_sequence desc, id);
create index if not exists pachanga_organizer_access_revision_created_by_idx
  on private.pachanga_organizer_access_application_revisions_v1(created_by, server_sequence desc, id);
create index if not exists pachanga_organizer_access_message_author_idx
  on private.pachanga_organizer_access_messages_v1(author_id, server_sequence desc, id)
  where author_id is not null;
create index if not exists pachanga_organizer_access_decision_actor_idx
  on private.pachanga_organizer_access_decisions_v1(decided_by, server_sequence desc, id);
create index if not exists pachanga_organizer_onboarding_source_decision_idx
  on private.pachanga_organizer_onboarding_workspaces_v1(source_decision_id)
  where source_decision_id is not null;
create index if not exists pachanga_organizer_onboarding_source_grant_idx
  on private.pachanga_organizer_onboarding_workspaces_v1(source_access_grant_id)
  where source_access_grant_id is not null;

revoke all on function private.pachanga_organizer_access_immutable_v1() from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_decision_update_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_organizer_ensure_existing_grant_onboarding_v1(uuid, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_grant_onboarding_trigger_v1() from public, anon, authenticated;

comment on function public.command_pachanga_organizer_access_application_v1(uuid, uuid, bigint, text, jsonb, jsonb) is
  'Only Wave 8A write authority. Requires idempotent operationId and expected revision.';
comment on table private.pachanga_organizer_access_decisions_v1 is
  'Immutable decision evidence. APPROVED is the only decision that can atomically bridge to an existing canonical access grant.';
comment on table private.pachanga_organizer_onboarding_workspaces_v1 is
  'Derived guidance for approved or pre-existing grants. Never an entitlement source.';
