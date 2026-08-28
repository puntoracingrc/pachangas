-- Wave 7C: indexes, invalidation, grants, and an OFF-by-default release gate.

set lock_timeout = '5s';
set statement_timeout = '5min';

create index if not exists pachanga_organizer_commercial_approved_by_idx
  on private.pachanga_organizer_commercial_decisions_v1(approved_by, server_sequence desc, id)
  where approved_by is not null;
create index if not exists pachanga_organizer_commercial_created_by_idx
  on private.pachanga_organizer_commercial_decisions_v1(created_by, server_sequence desc, id)
  where created_by is not null;
create index if not exists pachanga_organizer_catalog_intent_actor_idx
  on private.pachanga_organizer_stripe_catalog_intents_v1(actor_id, server_sequence desc, id);
create index if not exists pachanga_organizer_catalog_intent_decision_idx
  on private.pachanga_organizer_stripe_catalog_intents_v1(decision_id, server_sequence desc, id);
create index if not exists pachanga_organizer_catalog_intent_pending_idx
  on private.pachanga_organizer_stripe_catalog_intents_v1(status, server_sequence, id)
  where status = 'PREPARED';

drop trigger if exists pachanga_billing_commercial_decision_invalidation_v1
  on private.pachanga_organizer_commercial_decisions_v1;
create trigger pachanga_billing_commercial_decision_invalidation_v1
after insert or update on private.pachanga_organizer_commercial_decisions_v1
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

drop trigger if exists pachanga_billing_runtime_health_invalidation_v1
  on private.pachanga_organizer_stripe_runtime_health_v1;
create trigger pachanga_billing_runtime_health_invalidation_v1
after insert or update on private.pachanga_organizer_stripe_runtime_health_v1
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

create or replace function private.pachanga_billing_invalidate_previous_team_owner_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare sequence_value bigint;
begin
  if new.owner_id is not distinct from old.owner_id then return new; end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');

  update private.pachanga_organizer_checkout_intents_v1 intents set
    status = 'EXPIRED', server_sequence = sequence_value, updated_at = clock_timestamp()
  where intents.actor_id = old.owner_id
    and intents.status in ('PREPARED', 'SESSION_CREATED')
    and intents.billing_account_id in (
      select accounts.id
      from private.pachanga_organizer_billing_accounts accounts
      where accounts.organizer_kind = 'TEAM' and accounts.organizer_group_id = new.id
    );
  update private.pachanga_organizer_portal_intents_v1 intents set
    status = 'EXPIRED', server_sequence = sequence_value, updated_at = clock_timestamp()
  where intents.actor_id = old.owner_id
    and intents.status in ('PREPARED', 'SESSION_CREATED')
    and intents.billing_account_id in (
      select accounts.id
      from private.pachanga_organizer_billing_accounts accounts
      where accounts.organizer_kind = 'TEAM' and accounts.organizer_group_id = new.id
    );
  update private.pachanga_organizer_billing_accounts accounts set
    billing_contact_user_id = new.owner_id,
    revision = accounts.revision + 1,
    server_sequence = sequence_value,
    updated_at = clock_timestamp()
  where accounts.organizer_kind = 'TEAM' and accounts.organizer_group_id = new.id;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_invalidate_previous_team_owner_v1
  on public.pachanga_groups;
create trigger pachanga_billing_invalidate_previous_team_owner_v1
after update of owner_id on public.pachanga_groups
for each row execute function private.pachanga_billing_invalidate_previous_team_owner_v1();

create or replace function private.pachanga_billing_revalidate_intent_owner_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare current_owner_id uuid;
declare organizer_active boolean := true;
begin
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.id = new.billing_account_id;
  if not found then
    raise exception 'BILLING_ACCOUNT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if account.organizer_kind = 'TEAM' then
    select groups.owner_id into current_owner_id
    from public.pachanga_groups groups
    where groups.id = account.organizer_group_id
    for update;
  elsif account.organizer_kind = 'CLUB' then
    select clubs.primary_owner_id, clubs.operational_status = 'active'
    into current_owner_id, organizer_active
    from public.pachanga_clubs clubs
    where clubs.id = account.organizer_club_id
    for update;
  else
    organizer_active := false;
  end if;

  if not found
     or current_owner_id is distinct from new.actor_id
     or not organizer_active then
    raise exception 'BILLING_OWNER_REQUIRED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_revalidate_checkout_owner_v1
  on private.pachanga_organizer_checkout_intents_v1;
create trigger pachanga_billing_revalidate_checkout_owner_v1
before insert on private.pachanga_organizer_checkout_intents_v1
for each row execute function private.pachanga_billing_revalidate_intent_owner_v1();

drop trigger if exists pachanga_billing_revalidate_portal_owner_v1
  on private.pachanga_organizer_portal_intents_v1;
create trigger pachanga_billing_revalidate_portal_owner_v1
before insert on private.pachanga_organizer_portal_intents_v1
for each row execute function private.pachanga_billing_revalidate_intent_owner_v1();

create or replace function private.pachanga_billing_keep_expired_checkout_closed_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.status = 'EXPIRED' and new.status = 'WEBHOOK_CONFIRMED' then return old; end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_keep_expired_checkout_closed_v1
  on private.pachanga_organizer_checkout_intents_v1;
create trigger pachanga_billing_keep_expired_checkout_closed_v1
before update of status on private.pachanga_organizer_checkout_intents_v1
for each row execute function private.pachanga_billing_keep_expired_checkout_closed_v1();

revoke all on table private.pachanga_organizer_commercial_decisions_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_stripe_catalog_intents_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_stripe_runtime_health_v1 from public, anon, authenticated;
revoke all on function private.pachanga_billing_invalidate_previous_team_owner_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_revalidate_intent_owner_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_keep_expired_checkout_closed_v1() from public, anon, authenticated;
grant all on table private.pachanga_organizer_commercial_decisions_v1 to service_role;
grant all on table private.pachanga_organizer_stripe_catalog_intents_v1 to service_role;
grant all on table private.pachanga_organizer_stripe_runtime_health_v1 to service_role;

do $$
begin
  if exists (
    select 1 from private.pachanga_organizer_billing_settings settings
    where settings.commercial_decision_workflow_enabled
       or settings.organizer_pricing_ui_enabled
       or settings.stripe_test_checkout_enabled
       or settings.stripe_test_portal_enabled
       or settings.stripe_test_webhook_ready
       or settings.stripe_test_portal_ready
       or settings.stripe_live_webhook_ready
       or settings.stripe_live_portal_ready
       or settings.demo_world_v29_enabled
       or settings.live_checkout_enabled
       or settings.live_prices_approved
  ) then
    raise exception 'WAVE7C_FLAGS_MUST_START_DISABLED';
  end if;
end;
$$;

comment on function public.command_pachanga_organizer_billing_platform_v1(uuid, uuid, bigint, text, jsonb, jsonb) is
  'Wave 7B compatibility command. Wave 7C table guards reject legacy price mappings, commercial tax changes, and live activation.';
comment on table private.pachanga_organizer_stripe_runtime_health_v1 is
  'Mode-separated Stripe Organizer health. It stores no credentials and never grants sporting access.';
comment on table private.pachanga_organizer_stripe_catalog_intents_v1 is
  'Idempotent prepare/confirm evidence for Stripe Organizer Product and Price readback.';
