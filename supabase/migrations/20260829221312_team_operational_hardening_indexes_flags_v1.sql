-- Wave 8B: authority hardening, immutable evidence, performance indexes and OFF-by-default flags.

set lock_timeout = '5s';
set statement_timeout = '5min';

create or replace function private.pachanga_team_operational_authority_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if coalesce(current_setting('pachanga.team_operational_authority', true), '') <> 'on' then
    raise exception 'TEAM_OPERATIONAL_COMMAND_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function private.pachanga_team_operational_immutable_guard_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception 'TEAM_OPERATIONAL_EVIDENCE_IMMUTABLE' using errcode = '42501';
  end if;
  if coalesce(current_setting('pachanga.team_operational_authority', true), '') <> 'on' then
    raise exception 'TEAM_OPERATIONAL_COMMAND_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_team_operational_state_authority_v1
  on private.pachanga_team_operational_states_v1;
create trigger pachanga_team_operational_state_authority_v1
before insert or update or delete on private.pachanga_team_operational_states_v1
for each row execute function private.pachanga_team_operational_authority_guard_v1();

drop trigger if exists pachanga_team_operational_settings_authority_v1
  on private.pachanga_team_operational_settings_v1;
create trigger pachanga_team_operational_settings_authority_v1
before insert or update or delete on private.pachanga_team_operational_settings_v1
for each row execute function private.pachanga_team_operational_authority_guard_v1();

drop trigger if exists pachanga_team_operational_restriction_authority_v1
  on private.pachanga_team_operational_restrictions_v1;
create trigger pachanga_team_operational_restriction_authority_v1
before insert or update or delete on private.pachanga_team_operational_restrictions_v1
for each row execute function private.pachanga_team_operational_authority_guard_v1();

drop trigger if exists pachanga_team_operational_review_authority_v1
  on private.pachanga_team_operational_reviews_v1;
create trigger pachanga_team_operational_review_authority_v1
before insert or update or delete on private.pachanga_team_operational_reviews_v1
for each row execute function private.pachanga_team_operational_authority_guard_v1();

drop trigger if exists pachanga_team_operational_appeal_authority_v1
  on private.pachanga_team_operational_appeals_v1;
create trigger pachanga_team_operational_appeal_authority_v1
before insert or update or delete on private.pachanga_team_operational_appeals_v1
for each row execute function private.pachanga_team_operational_authority_guard_v1();

drop trigger if exists pachanga_team_operational_revision_immutable_v1
  on private.pachanga_team_operational_state_revisions_v1;
create trigger pachanga_team_operational_revision_immutable_v1
before insert or update or delete on private.pachanga_team_operational_state_revisions_v1
for each row execute function private.pachanga_team_operational_immutable_guard_v1();

drop trigger if exists pachanga_team_operational_receipt_immutable_v1
  on private.pachanga_team_operational_operation_receipts_v1;
create trigger pachanga_team_operational_receipt_immutable_v1
before insert or update or delete on private.pachanga_team_operational_operation_receipts_v1
for each row execute function private.pachanga_team_operational_immutable_guard_v1();

drop trigger if exists pachanga_team_operational_event_immutable_v1
  on private.pachanga_team_operational_events_v1;
create trigger pachanga_team_operational_event_immutable_v1
before insert or update or delete on private.pachanga_team_operational_events_v1
for each row execute function private.pachanga_team_operational_immutable_guard_v1();

drop trigger if exists pachanga_team_operational_continuity_immutable_v1
  on private.pachanga_team_operational_continuity_decisions_v1;
create trigger pachanga_team_operational_continuity_immutable_v1
before insert or update or delete on private.pachanga_team_operational_continuity_decisions_v1
for each row execute function private.pachanga_team_operational_immutable_guard_v1();

drop trigger if exists pachanga_team_operational_review_revision_immutable_v1
  on private.pachanga_team_operational_review_revisions_v1;
create trigger pachanga_team_operational_review_revision_immutable_v1
before insert or update or delete on private.pachanga_team_operational_review_revisions_v1
for each row execute function private.pachanga_team_operational_immutable_guard_v1();

drop trigger if exists pachanga_team_operational_appeal_message_immutable_v1
  on private.pachanga_team_operational_appeal_messages_v1;
create trigger pachanga_team_operational_appeal_message_immutable_v1
before insert or update or delete on private.pachanga_team_operational_appeal_messages_v1
for each row execute function private.pachanga_team_operational_immutable_guard_v1();

create index pachanga_team_operational_state_status_idx
  on private.pachanga_team_operational_states_v1(effective_status, server_sequence desc, group_id);
create index pachanga_team_operational_state_expiry_idx
  on private.pachanga_team_operational_states_v1(effective_until, group_id)
  where effective_until is not null and enforcement_status in ('LIMITED','SUSPENDED');
create index pachanga_team_operational_revision_group_idx
  on private.pachanga_team_operational_state_revisions_v1(group_id, revision desc, server_sequence desc, id);
create index pachanga_team_operational_revision_actor_idx
  on private.pachanga_team_operational_state_revisions_v1(actor_id, server_sequence desc, id)
  where actor_id is not null;
create index pachanga_team_operational_restriction_group_idx
  on private.pachanga_team_operational_restrictions_v1(group_id, status, server_sequence desc, id);
create index pachanga_team_operational_restriction_expiry_idx
  on private.pachanga_team_operational_restrictions_v1(effective_until, group_id, scope)
  where status = 'ACTIVE' and effective_until is not null;
create index pachanga_team_operational_continuity_group_idx
  on private.pachanga_team_operational_continuity_decisions_v1(group_id, competition_id, server_sequence desc, id);
create index pachanga_team_operational_review_queue_idx
  on private.pachanga_team_operational_reviews_v1(status, server_sequence desc, group_id);
create index pachanga_team_operational_appeal_queue_idx
  on private.pachanga_team_operational_appeals_v1(status, deadline_at, server_sequence desc, group_id);
create index pachanga_team_operational_receipt_group_idx
  on private.pachanga_team_operational_operation_receipts_v1(group_id, server_sequence desc, operation_id);
create index pachanga_team_operational_event_group_idx
  on private.pachanga_team_operational_events_v1(group_id, server_sequence desc, id);
create index pachanga_organizer_access_operational_block_idx
  on private.pachanga_organizer_access_applications_v1(organizer_group_id, operational_blocked_at desc, id)
  where operational_blocked_at is not null;
create index pachanga_registration_operational_block_idx
  on public.pachanga_competition_registration_requests(team_id, operational_blocked_at desc, id)
  where operational_blocked_at is not null;

create or replace function public.get_pachanga_team_operational_feature_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'teamOperationalFoundationEnabled', settings.foundation_enabled,
    'teamOperationalEnforcementEnabled', settings.enforcement_enabled,
    'teamOperationalRestrictionsEnabled', settings.restrictions_enabled,
    'teamOperationalContinuityEnabled', settings.continuity_enabled,
    'teamOperationalAppealsEnabled', settings.appeals_enabled,
    'teamOperationalCrossProductGuardsEnabled', settings.cross_product_guards_enabled,
    'teamOperationalPublicProjectionEnabled', settings.public_projection_enabled,
    'demoWorldV31Enabled', settings.demo_world_v31_enabled,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_team_operational_settings_v1 settings
  where settings.singleton;
$$;

do $$
declare group_count bigint;
declare state_count bigint;
declare bad_count bigint;
begin
  select count(*) into group_count from public.pachanga_groups;
  select count(*) into state_count from private.pachanga_team_operational_states_v1;
  select count(*) into bad_count
  from private.pachanga_team_operational_states_v1 states
  where states.source = 'MIGRATION_INITIALIZATION'
    and not (
      states.lifecycle_status = 'ACTIVE'
      and states.enforcement_status = 'CLEAR'
      and states.effective_status = 'ACTIVE'
      and states.current_revision = 1
    );
  if group_count <> state_count or bad_count <> 0 then
    raise exception 'TEAM_OPERATIONAL_INITIALIZATION_INCOMPLETE';
  end if;
  if exists (
    select 1 from private.pachanga_team_operational_settings_v1 settings
    where settings.singleton and (
      settings.foundation_enabled or settings.enforcement_enabled or settings.restrictions_enabled
      or settings.continuity_enabled or settings.appeals_enabled
      or settings.cross_product_guards_enabled or settings.public_projection_enabled
      or settings.demo_world_v31_enabled
    )
  ) then
    raise exception 'TEAM_OPERATIONAL_FLAGS_MUST_BE_BORN_OFF';
  end if;
end;
$$;

revoke all on function private.pachanga_team_operational_authority_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_immutable_guard_v1() from public, anon, authenticated;
revoke all on function public.get_pachanga_team_operational_feature_flags_v1() from public;
grant execute on function public.get_pachanga_team_operational_feature_flags_v1() to anon, authenticated, service_role;

comment on function public.get_pachanga_team_operational_feature_flags_v1() is
  'Safe Wave 8B feature flag readback. All flags are created OFF and can only be changed through the platform command RPC.';
