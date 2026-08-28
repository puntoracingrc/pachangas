-- Wave 7C: service-confirmed Stripe Organizer catalog and runtime health.

set lock_timeout = '5s';
set statement_timeout = '5min';

alter table private.pachanga_organizer_plan_price_mappings
  add column if not exists commercial_decision_id uuid
    references private.pachanga_organizer_commercial_decisions_v1(id) on delete restrict,
  add column if not exists catalog_revision text;

create index if not exists pachanga_organizer_mapping_decision_idx
  on private.pachanga_organizer_plan_price_mappings(commercial_decision_id, stripe_mode, billing_interval)
  where commercial_decision_id is not null;

create table if not exists private.pachanga_organizer_stripe_catalog_intents_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  decision_id uuid not null references private.pachanga_organizer_commercial_decisions_v1(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  stripe_mode text not null,
  expected_decision_revision bigint not null,
  request_hash text not null,
  status text not null default 'PREPARED',
  stripe_product_id text,
  stripe_monthly_price_id text,
  stripe_annual_price_id text,
  catalog_revision text not null,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  confirmed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (stripe_mode in ('test', 'live')),
  check (expected_decision_revision >= 1),
  check (length(request_hash) = 64),
  check (status in ('PREPARED', 'CONFIRMED', 'FAILED_SAFE')),
  check (stripe_product_id is null or stripe_product_id ~ '^prod_[A-Za-z0-9_]+$'),
  check (stripe_monthly_price_id is null or stripe_monthly_price_id ~ '^price_[A-Za-z0-9_]+$'),
  check (stripe_annual_price_id is null or stripe_annual_price_id ~ '^price_[A-Za-z0-9_]+$'),
  check (length(trim(catalog_revision)) between 3 and 120),
  check (status <> 'CONFIRMED' or (
    stripe_product_id is not null and stripe_monthly_price_id is not null
    and stripe_annual_price_id is not null and confirmed_at is not null
  ))
);

create table if not exists private.pachanga_organizer_stripe_runtime_health_v1 (
  stripe_mode text primary key,
  product_count integer not null default 0,
  price_count integer not null default 0,
  catalog_ready boolean not null default false,
  webhook_destination_ready boolean not null default false,
  webhook_signing_ready boolean not null default false,
  portal_ready boolean not null default false,
  checkout_api_ready boolean not null default false,
  destination_path text,
  safe_error_code text,
  source_revision text,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  verified_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (stripe_mode in ('test', 'live')),
  check (product_count >= 0 and price_count >= 0),
  check (destination_path is null or destination_path = '/api/webhooks/stripe'),
  check (safe_error_code is null or safe_error_code ~ '^[A-Z0-9_]{3,100}$'),
  check (revision >= 1)
);

insert into private.pachanga_organizer_stripe_runtime_health_v1(stripe_mode)
values ('test'), ('live')
on conflict (stripe_mode) do nothing;

create or replace function public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
  operation_id uuid,
  decision_id uuid,
  expected_revision bigint,
  stripe_mode text,
  reason text,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare actor_role text;
declare normalized_mode text := lower(trim(coalesce(stripe_mode, '')));
declare reason_text text := trim(coalesce(reason, ''));
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare decision private.pachanga_organizer_commercial_decisions_v1%rowtype;
declare plan_revision public.pachanga_organizer_plan_revisions%rowtype;
declare intent private.pachanga_organizer_stripe_catalog_intents_v1%rowtype;
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare sequence_value bigint;
declare product_name text;
declare catalog_revision text;
declare response jsonb;
begin
  if operation_id is null or decision_id is null or expected_revision is null
     or normalized_mode not in ('test', 'live') or length(reason_text) not between 3 and 1200 then
    raise exception 'BILLING_STRIPE_CATALOG_REQUEST_INVALID' using errcode = '22023';
  end if;
  actor_role := private.pachanga_platform_require_v1('billing.write');
  if normalized_mode = 'live' and actor_role <> 'platform_owner' then
    raise exception 'PLATFORM_OWNER_REQUIRED' using errcode = '42501';
  end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.commercial_decision_workflow_enabled then
    raise exception 'BILLING_COMMERCIAL_WORKFLOW_DISABLED' using errcode = '0A000';
  end if;
  select * into decision
  from private.pachanga_organizer_commercial_decisions_v1 decisions
  where decisions.id = decision_id;
  if not found or decision.plan_code not in ('TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER') then
    raise exception 'BILLING_COMMERCIAL_DECISION_NOT_FOUND' using errcode = 'P0002';
  end if;
  if decision.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  if normalized_mode = 'test' and decision.status not in ('draft', 'pending_approval', 'approved', 'published') then
    raise exception 'BILLING_TEST_CATALOG_DECISION_UNAVAILABLE' using errcode = '0A000';
  end if;
  if normalized_mode = 'live' and (
    decision.status <> 'approved' or settings.tax_health <> 'LIVE_READY'
    or not settings.stripe_live_webhook_ready or not settings.stripe_live_portal_ready
    or decision.terms_revision is distinct from settings.organizer_terms_revision
    or decision.privacy_revision is distinct from settings.organizer_privacy_revision
  ) then raise exception 'BILLING_LIVE_CATALOG_GATE_INCOMPLETE' using errcode = '0A000'; end if;
  select revisions.* into plan_revision
  from public.pachanga_organizer_plan_revisions revisions
  join public.pachanga_organizer_plan_catalog plans on plans.id = revisions.plan_id
  where plans.plan_code = decision.plan_code and plans.status = 'active'
    and revisions.status = 'active'
  order by revisions.version desc, revisions.id desc limit 1;
  if not found then raise exception 'BILLING_PLAN_NOT_AVAILABLE' using errcode = 'P0002'; end if;
  catalog_revision := 'organizer-plan-v' || plan_revision.version::text;
  product_name := case decision.plan_code
    when 'CLUB_ORGANIZER' then 'Pachangas IQ — Club Organizer'
    else 'Pachangas IQ — Team Organizer Pro' end;
  request_hash := private.pachanga_billing_request_hash_v1(
    'stripe_catalog.prepare', decision.id::text, expected_revision,
    jsonb_build_object('stripeMode', normalized_mode, 'reason', reason_text)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77103));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = prepare_pachanga_organizer_stripe_catalog_platform_v1.operation_id;
  if found then
    if prior.actor_id is distinct from actor_id or prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  insert into private.pachanga_organizer_stripe_catalog_intents_v1(
    operation_id, decision_id, actor_id, stripe_mode, expected_decision_revision,
    request_hash, catalog_revision, server_sequence
  ) values (
    operation_id, decision.id, actor_id, normalized_mode, decision.revision,
    request_hash, catalog_revision, sequence_value
  ) returning * into intent;
  response := jsonb_build_object(
    'intentId', intent.id, 'decisionId', decision.id, 'stripeMode', normalized_mode,
    'planCode', decision.plan_code, 'organizerKind', decision.organizer_kind,
    'productName', product_name, 'currency', lower(decision.currency),
    'monthlyAmountMinor', decision.monthly_amount_minor,
    'annualAmountMinor', decision.annual_amount_minor,
    'taxBehavior', decision.stripe_tax_behavior, 'trialDays', decision.trial_days,
    'catalogRevision', catalog_revision,
    'metadata', jsonb_build_object(
      'product_family', 'organizer', 'plan_code', decision.plan_code,
      'organizer_kind', lower(decision.organizer_kind),
      'environment', normalized_mode, 'catalog_revision', catalog_revision
    ),
    'status', intent.status, 'confirmedRevision', decision.revision,
    'serverSequence', sequence_value, 'replayed', false
  );
  return private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'platform', 'stripe_catalog.prepare',
    'organizer_commercial_decision', decision.id::text, request_hash,
    decision.revision, sequence_value, client_metadata, response,
    'STRIPE_CATALOG_PREPARED', jsonb_build_object(
      'decisionId', decision.id, 'planCode', decision.plan_code,
      'stripeMode', normalized_mode, 'reason', left(reason_text, 1200),
      'actorRole', actor_role
    )
  );
exception
  when unique_violation then raise exception 'BILLING_STRIPE_CATALOG_CONFLICT' using errcode = 'PT409';
end;
$$;

create or replace function public.confirm_pachanga_organizer_stripe_catalog_service_v1(
  operation_id uuid,
  stripe_product_id text,
  stripe_monthly_price_id text,
  stripe_annual_price_id text,
  observed_currency text,
  observed_monthly_amount_minor bigint,
  observed_annual_amount_minor bigint,
  observed_tax_behavior text,
  observed_metadata jsonb,
  observed_catalog_revision text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare intent private.pachanga_organizer_stripe_catalog_intents_v1%rowtype;
declare decision private.pachanga_organizer_commercial_decisions_v1%rowtype;
declare plan_revision public.pachanga_organizer_plan_revisions%rowtype;
declare mapping private.pachanga_organizer_plan_price_mappings%rowtype;
declare health private.pachanga_organizer_stripe_runtime_health_v1%rowtype;
declare sequence_value bigint;
declare expected_metadata jsonb;
declare response jsonb;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null or stripe_product_id !~ '^prod_[A-Za-z0-9_]+'
     or stripe_monthly_price_id !~ '^price_[A-Za-z0-9_]+'
     or stripe_annual_price_id !~ '^price_[A-Za-z0-9_]+'
     or stripe_monthly_price_id = stripe_annual_price_id then
    raise exception 'BILLING_STRIPE_CATALOG_CONFIRMATION_INVALID' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77104));
  select * into intent
  from private.pachanga_organizer_stripe_catalog_intents_v1 intents
  where intents.operation_id = confirm_pachanga_organizer_stripe_catalog_service_v1.operation_id
  for update;
  if not found then raise exception 'BILLING_STRIPE_CATALOG_INTENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if intent.status = 'CONFIRMED' then
    if intent.stripe_product_id <> stripe_product_id
       or intent.stripe_monthly_price_id <> stripe_monthly_price_id
       or intent.stripe_annual_price_id <> stripe_annual_price_id then
      raise exception 'BILLING_STRIPE_CATALOG_CONFIRMATION_CONFLICT' using errcode = 'PT409';
    end if;
    return jsonb_build_object(
      'status', intent.status, 'decisionId', intent.decision_id,
      'stripeMode', intent.stripe_mode, 'replayed', true
    );
  end if;
  if intent.status <> 'PREPARED' then raise exception 'BILLING_STRIPE_CATALOG_NOT_CONFIRMABLE' using errcode = 'PT409'; end if;
  select * into decision
  from private.pachanga_organizer_commercial_decisions_v1 decisions
  where decisions.id = intent.decision_id for update;
  if not found or decision.revision <> intent.expected_decision_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if intent.stripe_mode = 'live' and decision.status <> 'approved' then
    raise exception 'BILLING_LIVE_CATALOG_GATE_INCOMPLETE' using errcode = '0A000';
  end if;
  select revisions.* into plan_revision
  from public.pachanga_organizer_plan_revisions revisions
  join public.pachanga_organizer_plan_catalog plans on plans.id = revisions.plan_id
  where plans.plan_code = decision.plan_code and plans.status = 'active'
    and revisions.status = 'active'
  order by revisions.version desc, revisions.id desc limit 1;
  expected_metadata := jsonb_build_object(
    'product_family', 'organizer', 'plan_code', decision.plan_code,
    'organizer_kind', lower(decision.organizer_kind),
    'environment', intent.stripe_mode, 'catalog_revision', intent.catalog_revision
  );
  if lower(trim(coalesce(observed_currency, ''))) <> lower(decision.currency)
     or observed_monthly_amount_minor is distinct from decision.monthly_amount_minor
     or observed_annual_amount_minor is distinct from decision.annual_amount_minor
     or lower(trim(coalesce(observed_tax_behavior, ''))) <> decision.stripe_tax_behavior
     or observed_catalog_revision is distinct from intent.catalog_revision
     or coalesce(observed_metadata, '{}'::jsonb) <> expected_metadata then
    raise exception 'BILLING_STRIPE_CATALOG_READBACK_MISMATCH' using errcode = '22023';
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  perform set_config('pachangas.billing_mapping_authority', operation_id::text, true);
  insert into private.pachanga_organizer_plan_price_mappings(
    plan_revision_id, commercial_decision_id, stripe_mode, billing_interval,
    stripe_product_id, stripe_price_id, currency, unit_amount, tax_behavior,
    approved, active, revision, server_sequence, approved_by, approved_at,
    catalog_revision
  ) values (
    plan_revision.id, decision.id, intent.stripe_mode, 'month', stripe_product_id,
    stripe_monthly_price_id, lower(decision.currency), decision.monthly_amount_minor,
    decision.stripe_tax_behavior, true, true, 1, sequence_value,
    intent.actor_id, clock_timestamp(), intent.catalog_revision
  ) on conflict (plan_revision_id, stripe_mode, billing_interval) do update set
    commercial_decision_id = excluded.commercial_decision_id,
    stripe_product_id = excluded.stripe_product_id,
    stripe_price_id = excluded.stripe_price_id,
    currency = excluded.currency, unit_amount = excluded.unit_amount,
    tax_behavior = excluded.tax_behavior, approved = true, active = true,
    revision = private.pachanga_organizer_plan_price_mappings.revision + 1,
    server_sequence = excluded.server_sequence, approved_by = excluded.approved_by,
    approved_at = excluded.approved_at, catalog_revision = excluded.catalog_revision,
    updated_at = clock_timestamp();
  insert into private.pachanga_organizer_plan_price_mappings(
    plan_revision_id, commercial_decision_id, stripe_mode, billing_interval,
    stripe_product_id, stripe_price_id, currency, unit_amount, tax_behavior,
    approved, active, revision, server_sequence, approved_by, approved_at,
    catalog_revision
  ) values (
    plan_revision.id, decision.id, intent.stripe_mode, 'year', stripe_product_id,
    stripe_annual_price_id, lower(decision.currency), decision.annual_amount_minor,
    decision.stripe_tax_behavior, true, true, 1, sequence_value,
    intent.actor_id, clock_timestamp(), intent.catalog_revision
  ) on conflict (plan_revision_id, stripe_mode, billing_interval) do update set
    commercial_decision_id = excluded.commercial_decision_id,
    stripe_product_id = excluded.stripe_product_id,
    stripe_price_id = excluded.stripe_price_id,
    currency = excluded.currency, unit_amount = excluded.unit_amount,
    tax_behavior = excluded.tax_behavior, approved = true, active = true,
    revision = private.pachanga_organizer_plan_price_mappings.revision + 1,
    server_sequence = excluded.server_sequence, approved_by = excluded.approved_by,
    approved_at = excluded.approved_at, catalog_revision = excluded.catalog_revision,
    updated_at = clock_timestamp();
  update private.pachanga_organizer_stripe_catalog_intents_v1 intents set
    status = 'CONFIRMED', stripe_product_id = confirm_pachanga_organizer_stripe_catalog_service_v1.stripe_product_id,
    stripe_monthly_price_id = confirm_pachanga_organizer_stripe_catalog_service_v1.stripe_monthly_price_id,
    stripe_annual_price_id = confirm_pachanga_organizer_stripe_catalog_service_v1.stripe_annual_price_id,
    confirmed_at = clock_timestamp(), server_sequence = sequence_value,
    updated_at = clock_timestamp()
  where intents.id = intent.id returning * into intent;
  if intent.stripe_mode = 'live' then
    perform set_config('pachangas.billing_commercial_authority', operation_id::text, true);
    update private.pachanga_organizer_commercial_decisions_v1 decisions set
      status = 'superseded', revision = decisions.revision + 1,
      server_sequence = sequence_value, updated_at = clock_timestamp()
    where decisions.plan_code = decision.plan_code and decisions.status = 'published'
      and decisions.id <> decision.id and decision.supersedes_id = decisions.id;
    update private.pachanga_organizer_commercial_decisions_v1 decisions set
      status = 'published', published_at = clock_timestamp(),
      revision = decisions.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where decisions.id = decision.id returning * into decision;
  end if;
  update private.pachanga_organizer_stripe_runtime_health_v1 runtime set
    product_count = (select count(distinct mappings.stripe_product_id)
      from private.pachanga_organizer_plan_price_mappings mappings
      where mappings.stripe_mode = intent.stripe_mode and mappings.active and mappings.approved),
    price_count = (select count(*)
      from private.pachanga_organizer_plan_price_mappings mappings
      where mappings.stripe_mode = intent.stripe_mode and mappings.active and mappings.approved),
    catalog_ready = (select count(*) = 4
      from private.pachanga_organizer_plan_price_mappings mappings
      where mappings.stripe_mode = intent.stripe_mode and mappings.active and mappings.approved
        and mappings.commercial_decision_id is not null),
    revision = runtime.revision + 1, server_sequence = sequence_value,
    verified_at = clock_timestamp(), updated_at = clock_timestamp()
  where runtime.stripe_mode = intent.stripe_mode returning * into health;
  response := jsonb_build_object(
    'status', intent.status, 'decisionId', decision.id, 'planCode', decision.plan_code,
    'decisionStatus', decision.status, 'stripeMode', intent.stripe_mode,
    'catalogReady', health.catalog_ready, 'productCount', health.product_count,
    'priceCount', health.price_count, 'confirmedRevision', decision.revision,
    'serverSequence', sequence_value, 'replayed', false
  );
  return response;
end;
$$;

create or replace function public.record_pachanga_organizer_stripe_runtime_health_service_v1(
  operation_id uuid,
  stripe_mode text,
  expected_revision bigint,
  webhook_destination_ready boolean,
  webhook_signing_ready boolean,
  portal_ready boolean,
  checkout_api_ready boolean,
  destination_path text,
  source_revision text,
  safe_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare normalized_mode text := lower(trim(coalesce(stripe_mode, '')));
declare health private.pachanga_organizer_stripe_runtime_health_v1%rowtype;
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare sequence_value bigint;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null or normalized_mode not in ('test', 'live')
     or expected_revision is null or destination_path is distinct from '/api/webhooks/stripe'
     or length(trim(coalesce(source_revision, ''))) not between 3 and 120
     or (safe_error_code is not null and safe_error_code !~ '^[A-Z0-9_]{3,100}$') then
    raise exception 'BILLING_RUNTIME_HEALTH_INVALID' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77105));
  select * into health
  from private.pachanga_organizer_stripe_runtime_health_v1 runtime
  where runtime.stripe_mode = normalized_mode for update;
  if health.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  update private.pachanga_organizer_stripe_runtime_health_v1 runtime set
    webhook_destination_ready = record_pachanga_organizer_stripe_runtime_health_service_v1.webhook_destination_ready,
    webhook_signing_ready = record_pachanga_organizer_stripe_runtime_health_service_v1.webhook_signing_ready,
    portal_ready = record_pachanga_organizer_stripe_runtime_health_service_v1.portal_ready,
    checkout_api_ready = record_pachanga_organizer_stripe_runtime_health_service_v1.checkout_api_ready,
    destination_path = record_pachanga_organizer_stripe_runtime_health_service_v1.destination_path,
    source_revision = left(trim(record_pachanga_organizer_stripe_runtime_health_service_v1.source_revision), 120),
    safe_error_code = record_pachanga_organizer_stripe_runtime_health_service_v1.safe_error_code,
    revision = runtime.revision + 1, server_sequence = sequence_value,
    verified_at = clock_timestamp(), updated_at = clock_timestamp()
  where runtime.stripe_mode = normalized_mode returning * into health;
  perform set_config('pachangas.billing_settings_authority', operation_id::text, true);
  update private.pachanga_organizer_billing_settings current_settings set
    stripe_test_webhook_ready = case when normalized_mode = 'test'
      then health.webhook_destination_ready and health.webhook_signing_ready
      else current_settings.stripe_test_webhook_ready end,
    stripe_test_portal_ready = case when normalized_mode = 'test'
      then health.portal_ready else current_settings.stripe_test_portal_ready end,
    stripe_live_webhook_ready = case when normalized_mode = 'live'
      then health.webhook_destination_ready and health.webhook_signing_ready
      else current_settings.stripe_live_webhook_ready end,
    stripe_live_portal_ready = case when normalized_mode = 'live'
      then health.portal_ready else current_settings.stripe_live_portal_ready end,
    revision = current_settings.revision + 1, server_sequence = sequence_value,
    updated_at = clock_timestamp()
  where singleton returning * into settings;
  return jsonb_build_object(
    'mode', normalized_mode, 'catalogReady', health.catalog_ready,
    'webhookReady', health.webhook_destination_ready and health.webhook_signing_ready,
    'portalReady', health.portal_ready, 'checkoutApiReady', health.checkout_api_ready,
    'confirmedRevision', health.revision, 'settingsRevision', settings.revision,
    'serverSequence', sequence_value
  );
end;
$$;

revoke all on table private.pachanga_organizer_stripe_catalog_intents_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_stripe_runtime_health_v1 from public, anon, authenticated;
grant all on table private.pachanga_organizer_stripe_catalog_intents_v1 to service_role;
grant all on table private.pachanga_organizer_stripe_runtime_health_v1 to service_role;
revoke all on function public.prepare_pachanga_organizer_stripe_catalog_platform_v1(uuid, uuid, bigint, text, text, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.prepare_pachanga_organizer_stripe_catalog_platform_v1(uuid, uuid, bigint, text, text, jsonb) to authenticated, service_role;
revoke all on function public.confirm_pachanga_organizer_stripe_catalog_service_v1(uuid, text, text, text, text, bigint, bigint, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.confirm_pachanga_organizer_stripe_catalog_service_v1(uuid, text, text, text, text, bigint, bigint, text, jsonb, text) to service_role;
revoke all on function public.record_pachanga_organizer_stripe_runtime_health_service_v1(uuid, text, bigint, boolean, boolean, boolean, boolean, text, text, text) from public, anon, authenticated;
grant execute on function public.record_pachanga_organizer_stripe_runtime_health_service_v1(uuid, text, bigint, boolean, boolean, boolean, boolean, text, text, text) to service_role;
