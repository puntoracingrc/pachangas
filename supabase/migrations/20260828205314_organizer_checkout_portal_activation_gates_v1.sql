-- Wave 7C: fail-closed write guards and the single live activation command.

set lock_timeout = '5s';
set statement_timeout = '5min';

create or replace function private.pachanga_billing_commercial_settings_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare authority text := current_setting('pachangas.billing_settings_authority', true);
declare protected_changed boolean;
declare emergency_disable_only boolean;
begin
  protected_changed :=
    new.tax_health is distinct from old.tax_health
    or new.commercial_decision_workflow_enabled is distinct from old.commercial_decision_workflow_enabled
    or new.organizer_pricing_ui_enabled is distinct from old.organizer_pricing_ui_enabled
    or new.stripe_test_checkout_enabled is distinct from old.stripe_test_checkout_enabled
    or new.stripe_test_portal_enabled is distinct from old.stripe_test_portal_enabled
    or new.stripe_test_webhook_ready is distinct from old.stripe_test_webhook_ready
    or new.stripe_test_portal_ready is distinct from old.stripe_test_portal_ready
    or new.stripe_live_webhook_ready is distinct from old.stripe_live_webhook_ready
    or new.stripe_live_portal_ready is distinct from old.stripe_live_portal_ready
    or new.demo_world_v29_enabled is distinct from old.demo_world_v29_enabled
    or new.organizer_terms_revision is distinct from old.organizer_terms_revision
    or new.organizer_privacy_revision is distinct from old.organizer_privacy_revision
    or new.live_prices_approved is distinct from old.live_prices_approved
    or new.live_checkout_enabled is distinct from old.live_checkout_enabled
    or new.portal_enabled is distinct from old.portal_enabled;

  emergency_disable_only :=
    new.tax_health is not distinct from old.tax_health
    and new.commercial_decision_workflow_enabled is not distinct from old.commercial_decision_workflow_enabled
    and new.organizer_pricing_ui_enabled is not distinct from old.organizer_pricing_ui_enabled
    and new.stripe_test_checkout_enabled is not distinct from old.stripe_test_checkout_enabled
    and new.stripe_test_portal_enabled is not distinct from old.stripe_test_portal_enabled
    and new.stripe_test_webhook_ready is not distinct from old.stripe_test_webhook_ready
    and new.stripe_test_portal_ready is not distinct from old.stripe_test_portal_ready
    and new.stripe_live_webhook_ready is not distinct from old.stripe_live_webhook_ready
    and new.stripe_live_portal_ready is not distinct from old.stripe_live_portal_ready
    and new.demo_world_v29_enabled is not distinct from old.demo_world_v29_enabled
    and new.organizer_terms_revision is not distinct from old.organizer_terms_revision
    and new.organizer_privacy_revision is not distinct from old.organizer_privacy_revision
    and (new.live_prices_approved is not distinct from old.live_prices_approved
      or (old.live_prices_approved and not new.live_prices_approved))
    and (new.live_checkout_enabled is not distinct from old.live_checkout_enabled
      or (old.live_checkout_enabled and not new.live_checkout_enabled))
    and (new.portal_enabled is not distinct from old.portal_enabled
      or (old.portal_enabled and not new.portal_enabled));

  if protected_changed and coalesce(authority, '') = '' and not emergency_disable_only then
    raise exception 'BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_commercial_settings_guard_v1
  on private.pachanga_organizer_billing_settings;
create trigger pachanga_billing_commercial_settings_guard_v1
before update on private.pachanga_organizer_billing_settings
for each row execute function private.pachanga_billing_commercial_settings_guard_v1();

create or replace function private.pachanga_billing_price_mapping_authority_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if coalesce(current_setting('pachangas.billing_mapping_authority', true), '') = '' then
    raise exception 'BILLING_STRIPE_CATALOG_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists pachanga_billing_price_mapping_authority_guard_v1
  on private.pachanga_organizer_plan_price_mappings;
create trigger pachanga_billing_price_mapping_authority_guard_v1
before insert or update or delete on private.pachanga_organizer_plan_price_mappings
for each row execute function private.pachanga_billing_price_mapping_authority_guard_v1();

create or replace function private.pachanga_billing_commercial_decision_authority_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if coalesce(current_setting('pachangas.billing_commercial_authority', true), '') = '' then
    raise exception 'BILLING_COMMERCIAL_DECISION_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    raise exception 'BILLING_COMMERCIAL_DECISION_IMMUTABLE' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.status in ('published', 'superseded') then
    if not (
      old.status = 'published' and new.status = 'superseded'
      and new.id = old.id and new.plan_code = old.plan_code
      and new.organizer_kind = old.organizer_kind and new.currency = old.currency
      and new.monthly_amount_minor = old.monthly_amount_minor
      and new.annual_amount_minor = old.annual_amount_minor
      and new.tax_display_mode = old.tax_display_mode
      and new.stripe_tax_behavior = old.stripe_tax_behavior
      and new.trial_days = old.trial_days and new.effective_from = old.effective_from
      and new.public_copy_revision = old.public_copy_revision
      and new.terms_revision = old.terms_revision
      and new.privacy_revision = old.privacy_revision
      and new.decision_kind = old.decision_kind
      and new.approved_by = old.approved_by and new.approved_at = old.approved_at
      and new.published_at = old.published_at and new.supersedes_id is not distinct from old.supersedes_id
      and new.operation_id = old.operation_id and new.created_by is not distinct from old.created_by
      and new.created_at = old.created_at
      and new.revision = old.revision + 1 and new.server_sequence > old.server_sequence
    ) then
      raise exception 'BILLING_PUBLISHED_DECISION_IMMUTABLE' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_commercial_decision_authority_guard_v1
  on private.pachanga_organizer_commercial_decisions_v1;
create trigger pachanga_billing_commercial_decision_authority_guard_v1
before insert or update or delete on private.pachanga_organizer_commercial_decisions_v1
for each row execute function private.pachanga_billing_commercial_decision_authority_guard_v1();

create or replace function private.pachanga_billing_checkout_activation_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare health private.pachanga_organizer_stripe_runtime_health_v1%rowtype;
declare mapping_count integer;
declare published_count integer;
begin
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  select * into health from private.pachanga_organizer_stripe_runtime_health_v1
    where stripe_mode = new.stripe_mode;
  select count(*) into mapping_count
  from private.pachanga_organizer_plan_price_mappings mappings
  where mappings.stripe_mode = new.stripe_mode and mappings.active and mappings.approved
    and mappings.commercial_decision_id is not null;

  if new.stripe_mode = 'test' then
    if not settings.stripe_test_checkout_enabled
       or settings.tax_health not in ('TEST_READY', 'LIVE_READY')
       or mapping_count <> 4 or not health.catalog_ready
       or not health.webhook_destination_ready or not health.webhook_signing_ready
       or not health.checkout_api_ready then
      raise exception 'BILLING_TEST_CHECKOUT_GATE_INCOMPLETE' using errcode = '0A000';
    end if;
  else
    select count(distinct decisions.id) into published_count
    from private.pachanga_organizer_plan_price_mappings mappings
    join private.pachanga_organizer_commercial_decisions_v1 decisions
      on decisions.id = mappings.commercial_decision_id
    where mappings.stripe_mode = 'live' and mappings.active and mappings.approved
      and decisions.status = 'published'
      and decisions.plan_code in ('TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER')
      and decisions.terms_revision = settings.organizer_terms_revision
      and decisions.privacy_revision = settings.organizer_privacy_revision;
    if not settings.live_checkout_enabled or not settings.live_prices_approved
       or not settings.portal_enabled or settings.tax_health <> 'LIVE_READY'
       or mapping_count <> 4 or published_count <> 2 or not health.catalog_ready
       or not health.webhook_destination_ready or not health.webhook_signing_ready
       or not health.portal_ready or not health.checkout_api_ready then
      raise exception 'BILLING_LIVE_CHECKOUT_GATE_INCOMPLETE' using errcode = '0A000';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_checkout_activation_guard_v1
  on private.pachanga_organizer_checkout_intents_v1;
create trigger pachanga_billing_checkout_activation_guard_v1
before insert on private.pachanga_organizer_checkout_intents_v1
for each row execute function private.pachanga_billing_checkout_activation_guard_v1();

create or replace function private.pachanga_billing_portal_activation_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare health private.pachanga_organizer_stripe_runtime_health_v1%rowtype;
begin
  select * into account from private.pachanga_organizer_billing_accounts
    where id = new.billing_account_id;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  select * into health from private.pachanga_organizer_stripe_runtime_health_v1
    where stripe_mode = account.stripe_mode;
  if account.stripe_mode = 'test' then
    if not settings.stripe_test_portal_enabled or not health.portal_ready then
      raise exception 'BILLING_TEST_PORTAL_GATE_INCOMPLETE' using errcode = '0A000';
    end if;
  elsif not settings.portal_enabled or not settings.live_checkout_enabled
     or settings.tax_health <> 'LIVE_READY' or not health.portal_ready
     or not health.webhook_destination_ready or not health.webhook_signing_ready then
    raise exception 'BILLING_LIVE_PORTAL_GATE_INCOMPLETE' using errcode = '0A000';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_portal_activation_guard_v1
  on private.pachanga_organizer_portal_intents_v1;
create trigger pachanga_billing_portal_activation_guard_v1
before insert on private.pachanga_organizer_portal_intents_v1
for each row execute function private.pachanga_billing_portal_activation_guard_v1();

create or replace function public.prepare_pachanga_organizer_portal_service_v1(
  operation_id uuid,
  actor_id uuid,
  organizer_kind text,
  organizer_id uuid,
  stripe_mode text,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare intent private.pachanga_organizer_portal_intents_v1%rowtype;
declare normalized_kind text := upper(trim(coalesce(organizer_kind, '')));
declare normalized_mode text := lower(trim(coalesce(stripe_mode, '')));
declare request_hash text;
declare sequence_value bigint;
declare response jsonb;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null or actor_id is null or organizer_id is null
     or expected_revision is null or normalized_mode not in ('test', 'live') then
    raise exception 'BILLING_INVALID_PORTAL_INTENT' using errcode = '22023';
  end if;
  if not private.pachanga_billing_owner_can_manage_v1(normalized_kind, organizer_id, actor_id) then
    raise exception 'BILLING_OWNER_REQUIRED' using errcode = '42501';
  end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if normalized_mode = 'test' and not settings.stripe_test_portal_enabled then
    raise exception 'BILLING_TEST_PORTAL_DISABLED' using errcode = '0A000';
  elsif normalized_mode = 'live' and not settings.portal_enabled then
    raise exception 'BILLING_LIVE_PORTAL_DISABLED' using errcode = '0A000';
  end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    'portal.prepare', organizer_id::text, expected_revision,
    jsonb_build_object('organizerKind', normalized_kind, 'stripeMode', normalized_mode)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77023));
  select * into intent from private.pachanga_organizer_portal_intents_v1 intents
  where intents.operation_id = prepare_pachanga_organizer_portal_service_v1.operation_id;
  if found then
    if intent.actor_id <> actor_id or intent.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    select * into account from private.pachanga_organizer_billing_accounts where id = intent.billing_account_id;
    return jsonb_build_object('replayed', true, 'intentId', intent.id,
      'billingAccountId', account.id, 'stripeCustomerId', account.stripe_customer_id,
      'status', intent.status, 'portalUrl', intent.portal_url, 'expiresAt', intent.expires_at,
      'confirmedRevision', account.revision, 'stripeMode', account.stripe_mode);
  end if;
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.organizer_kind = normalized_kind and accounts.stripe_mode = normalized_mode
    and ((normalized_kind = 'TEAM' and accounts.organizer_group_id = organizer_id)
      or (normalized_kind = 'CLUB' and accounts.organizer_club_id = organizer_id))
  for update;
  if not found or account.stripe_customer_id is null then
    raise exception 'BILLING_CUSTOMER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if account.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  insert into private.pachanga_organizer_portal_intents_v1(
    operation_id, billing_account_id, actor_id, expected_account_revision,
    request_hash, server_sequence
  ) values (
    operation_id, account.id, actor_id, expected_revision, request_hash, sequence_value
  ) returning * into intent;
  response := jsonb_build_object('replayed', false, 'intentId', intent.id,
    'billingAccountId', account.id, 'stripeCustomerId', account.stripe_customer_id,
    'status', intent.status, 'confirmedRevision', account.revision, 'stripeMode', account.stripe_mode);
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'authenticated', 'portal.prepare', 'organizer_billing_account',
    account.id::text, request_hash, account.revision, sequence_value, client_metadata,
    response - 'stripeCustomerId', 'PORTAL_PREPARED', jsonb_build_object('intentId', intent.id)
  );
  return response;
end;
$$;

create or replace function public.activate_pachanga_organizer_live_checkout_platform_v1(
  operation_id uuid,
  expected_revision bigint,
  confirmation text,
  reason text,
  terms_revision text,
  privacy_revision text,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare actor_role text;
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare health private.pachanga_organizer_stripe_runtime_health_v1%rowtype;
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare sequence_value bigint;
declare response jsonb;
begin
  if operation_id is null or expected_revision is null
     or confirmation is distinct from 'CONFIRM_ORGANIZER_LIVE_CHECKOUT'
     or length(trim(coalesce(reason, ''))) not between 3 and 1200
     or length(trim(coalesce(activate_pachanga_organizer_live_checkout_platform_v1.terms_revision, ''))) not between 3 and 120
     or length(trim(coalesce(activate_pachanga_organizer_live_checkout_platform_v1.privacy_revision, ''))) not between 3 and 120 then
    raise exception 'BILLING_LIVE_ACTIVATION_INVALID' using errcode = '22023';
  end if;
  actor_role := private.pachanga_billing_require_platform_owner_v1();
  request_hash := private.pachanga_billing_request_hash_v1(
    'live_checkout.activate', 'commercial-settings', expected_revision,
    jsonb_build_object('confirmation', confirmation, 'reason', trim(reason),
      'termsRevision', trim(activate_pachanga_organizer_live_checkout_platform_v1.terms_revision),
      'privacyRevision', trim(activate_pachanga_organizer_live_checkout_platform_v1.privacy_revision))
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77106));
  select * into prior from private.pachanga_organizer_billing_operation_receipts_v1 receipts
    where receipts.operation_id = activate_pachanga_organizer_live_checkout_platform_v1.operation_id;
  if found then
    if prior.actor_id is distinct from actor_id or prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;
  select * into settings from private.pachanga_organizer_billing_settings
    where singleton for update;
  if settings.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  select * into health from private.pachanga_organizer_stripe_runtime_health_v1
    where stripe_mode = 'live' for share;
  if not settings.commercial_decision_workflow_enabled
     or settings.tax_health <> 'LIVE_READY'
     or settings.organizer_terms_revision is distinct from trim(activate_pachanga_organizer_live_checkout_platform_v1.terms_revision)
     or settings.organizer_privacy_revision is distinct from trim(activate_pachanga_organizer_live_checkout_platform_v1.privacy_revision)
     or not health.catalog_ready or not health.webhook_destination_ready
     or not health.webhook_signing_ready or not health.portal_ready
     or not health.checkout_api_ready
     or (select count(*) from private.pachanga_organizer_plan_price_mappings mappings
         join private.pachanga_organizer_commercial_decisions_v1 decisions
           on decisions.id = mappings.commercial_decision_id
         where mappings.stripe_mode = 'live' and mappings.active and mappings.approved
           and decisions.status = 'published'
           and decisions.plan_code in ('TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER')
           and decisions.terms_revision = trim(activate_pachanga_organizer_live_checkout_platform_v1.terms_revision)
           and decisions.privacy_revision = trim(activate_pachanga_organizer_live_checkout_platform_v1.privacy_revision)) <> 4
     or (select count(*) from private.pachanga_organizer_commercial_decisions_v1 decisions
         where decisions.status = 'published'
           and decisions.plan_code in ('TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER')
           and decisions.terms_revision = trim(activate_pachanga_organizer_live_checkout_platform_v1.terms_revision)
           and decisions.privacy_revision = trim(activate_pachanga_organizer_live_checkout_platform_v1.privacy_revision)) <> 2 then
    raise exception 'BILLING_LIVE_ACTIVATION_GATE_INCOMPLETE' using errcode = '0A000';
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  perform set_config('pachangas.billing_settings_authority', operation_id::text, true);
  update private.pachanga_organizer_billing_settings current_settings set
    portal_enabled = true, live_prices_approved = true, live_checkout_enabled = true,
    organizer_pricing_ui_enabled = true,
    revision = current_settings.revision + 1, server_sequence = sequence_value,
    updated_by = actor_id, updated_at = clock_timestamp()
  where singleton returning * into settings;
  response := jsonb_build_object(
    'livePricesApproved', settings.live_prices_approved,
    'liveCheckoutEnabled', settings.live_checkout_enabled,
    'portalEnabled', settings.portal_enabled,
    'confirmedRevision', settings.revision, 'serverSequence', settings.server_sequence,
    'replayed', false
  );
  return private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'platform', 'live_checkout.activate',
    'organizer_commercial_settings', 'singleton', request_hash,
    settings.revision, settings.server_sequence, client_metadata, response,
    'ORGANIZER_LIVE_CHECKOUT_ACTIVATED',
    jsonb_build_object('reason', left(trim(reason), 1200), 'actorRole', actor_role,
      'termsRevision', trim(activate_pachanga_organizer_live_checkout_platform_v1.terms_revision),
      'privacyRevision', trim(activate_pachanga_organizer_live_checkout_platform_v1.privacy_revision))
  );
end;
$$;

revoke all on function private.pachanga_billing_commercial_settings_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_price_mapping_authority_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_commercial_decision_authority_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_checkout_activation_guard_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_portal_activation_guard_v1() from public, anon, authenticated;
revoke all on function public.prepare_pachanga_organizer_portal_service_v1(uuid, uuid, text, uuid, text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.prepare_pachanga_organizer_portal_service_v1(uuid, uuid, text, uuid, text, bigint, jsonb) to service_role;
revoke all on function public.activate_pachanga_organizer_live_checkout_platform_v1(uuid, bigint, text, text, text, text, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.activate_pachanga_organizer_live_checkout_platform_v1(uuid, bigint, text, text, text, text, jsonb) to authenticated, service_role;

comment on function public.activate_pachanga_organizer_live_checkout_platform_v1(uuid, bigint, text, text, text, text, jsonb) is
  'Single platform-owner gate for Organizer live pricing, Portal, and Checkout. Never called by a migration.';
