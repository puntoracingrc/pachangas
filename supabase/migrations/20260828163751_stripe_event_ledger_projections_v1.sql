-- Wave 7B: private Stripe event ledger and canonical billing projections.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table if not exists private.pachanga_stripe_webhook_events_v2 (
  id uuid primary key default gen_random_uuid(),
  stripe_mode text not null,
  stripe_event_id text not null,
  event_type text not null,
  api_version text,
  object_type text,
  object_id text,
  stripe_created_at timestamptz not null,
  received_at timestamptz not null default clock_timestamp(),
  payload_checksum text not null,
  normalized_payload jsonb not null default '{}'::jsonb,
  processing_status text not null default 'RECEIVED',
  attempt_count integer not null default 1,
  safe_error_code text,
  processed_at timestamptz,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  unique (stripe_mode, stripe_event_id),
  check (stripe_mode in ('test', 'live')),
  check (stripe_event_id ~ '^evt_[A-Za-z0-9_]+$'),
  check (length(trim(event_type)) between 3 and 160),
  check (payload_checksum ~ '^[0-9a-f]{64}$'),
  check (processing_status in ('RECEIVED', 'PROCESSING', 'PROCESSED', 'IGNORED_SAFE', 'FAILED_RETRYABLE', 'FAILED_TERMINAL')),
  check (attempt_count between 1 and 1000),
  check (safe_error_code is null or safe_error_code ~ '^[A-Z0-9_]{3,80}$'),
  check ((processing_status in ('PROCESSED', 'IGNORED_SAFE') and processed_at is not null) or processing_status not in ('PROCESSED', 'IGNORED_SAFE'))
);

create table if not exists private.pachanga_stripe_webhook_deliveries_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  webhook_event_id uuid references private.pachanga_stripe_webhook_events_v2(id) on delete set null,
  endpoint_mode text not null,
  signature_verified boolean not null,
  delivery_status text not null,
  http_result integer not null,
  request_id text,
  received_at timestamptz not null default clock_timestamp(),
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  check (endpoint_mode in ('test', 'live')),
  check (delivery_status in ('ACCEPTED', 'DUPLICATE', 'REJECTED_SIGNATURE', 'REJECTED_MODE', 'FAILED_SAFE')),
  check (http_result between 100 and 599),
  check (request_id is null or length(request_id) between 3 and 160)
);

create table if not exists private.pachanga_stripe_subscription_projections_v1 (
  id uuid primary key default gen_random_uuid(),
  billing_account_id uuid not null references private.pachanga_organizer_billing_accounts(id) on delete restrict,
  stripe_mode text not null,
  stripe_subscription_id text not null,
  stripe_customer_id text not null,
  subscription_family text not null default 'ORGANIZER',
  plan_revision_id uuid references public.pachanga_organizer_plan_revisions(id) on delete restrict,
  stripe_price_id text,
  status text not null,
  billing_interval text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  canceled_at timestamptz,
  grace_ends_at timestamptz,
  last_event_created_at timestamptz not null,
  last_event_id text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (stripe_mode, stripe_subscription_id),
  check (stripe_mode in ('test', 'live')),
  check (stripe_subscription_id ~ '^sub_[A-Za-z0-9_]+$'),
  check (stripe_customer_id ~ '^cus_[A-Za-z0-9_]+$'),
  check (subscription_family = 'ORGANIZER'),
  check (stripe_price_id is null or stripe_price_id ~ '^price_[A-Za-z0-9_]+$'),
  check (status in ('incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'unpaid', 'paused', 'canceled')),
  check (billing_interval is null or billing_interval in ('month', 'year')),
  check (current_period_end is null or current_period_start is null or current_period_end > current_period_start),
  check (last_event_id ~ '^evt_[A-Za-z0-9_]+$'),
  check (revision >= 1)
);

create unique index if not exists pachanga_stripe_subscription_active_family_idx
  on private.pachanga_stripe_subscription_projections_v1(billing_account_id, stripe_mode, subscription_family)
  where status not in ('canceled', 'incomplete_expired');

create table if not exists private.pachanga_stripe_invoice_projections_v1 (
  id uuid primary key default gen_random_uuid(),
  billing_account_id uuid not null references private.pachanga_organizer_billing_accounts(id) on delete restrict,
  subscription_projection_id uuid references private.pachanga_stripe_subscription_projections_v1(id) on delete set null,
  stripe_mode text not null,
  stripe_invoice_id text not null,
  stripe_subscription_id text,
  stripe_customer_id text not null,
  status text not null,
  currency text not null,
  amount_due bigint not null default 0,
  amount_paid bigint not null default 0,
  hosted_invoice_url text,
  invoice_pdf_url text,
  due_at timestamptz,
  paid_at timestamptz,
  last_event_created_at timestamptz not null,
  last_event_id text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint pachanga_stripe_invoice_mode_id_uq unique (stripe_mode, stripe_invoice_id),
  check (stripe_mode in ('test', 'live')),
  check (stripe_invoice_id ~ '^in_[A-Za-z0-9_]+$'),
  check (stripe_subscription_id is null or stripe_subscription_id ~ '^sub_[A-Za-z0-9_]+$'),
  check (stripe_customer_id ~ '^cus_[A-Za-z0-9_]+$'),
  check (status in ('draft', 'open', 'paid', 'uncollectible', 'void')),
  check (currency ~ '^[a-z]{3}$'),
  check (amount_due >= 0 and amount_paid >= 0),
  check (hosted_invoice_url is null or hosted_invoice_url ~ '^https://'),
  check (invoice_pdf_url is null or invoice_pdf_url ~ '^https://'),
  check (last_event_id ~ '^evt_[A-Za-z0-9_]+$'),
  check (revision >= 1)
);

create table if not exists private.pachanga_stripe_payment_failures_v1 (
  id uuid primary key default gen_random_uuid(),
  billing_account_id uuid not null references private.pachanga_organizer_billing_accounts(id) on delete restrict,
  subscription_projection_id uuid references private.pachanga_stripe_subscription_projections_v1(id) on delete set null,
  invoice_projection_id uuid references private.pachanga_stripe_invoice_projections_v1(id) on delete set null,
  stripe_mode text not null,
  failure_key text not null,
  safe_failure_code text not null,
  status text not null default 'OPEN',
  first_failed_at timestamptz not null,
  last_failed_at timestamptz not null,
  recovered_at timestamptz,
  attempt_count integer not null default 1,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint pachanga_stripe_failure_mode_key_uq unique (stripe_mode, failure_key),
  check (stripe_mode in ('test', 'live')),
  check (length(failure_key) between 3 and 180),
  check (safe_failure_code ~ '^[A-Z0-9_]{3,80}$'),
  check (status in ('OPEN', 'ACTION_REQUIRED', 'RECOVERED', 'CLOSED')),
  check (last_failed_at >= first_failed_at),
  check ((status = 'RECOVERED' and recovered_at is not null) or status <> 'RECOVERED'),
  check (attempt_count between 1 and 1000),
  check (revision >= 1)
);

create table if not exists private.pachanga_stripe_billing_reconciliations_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  billing_account_id uuid not null references private.pachanga_organizer_billing_accounts(id) on delete restrict,
  stripe_mode text not null,
  requested_by uuid references auth.users(id) on delete set null,
  reason text not null,
  status text not null default 'PENDING',
  difference_codes text[] not null default '{}'::text[],
  safe_error_code text,
  started_at timestamptz,
  completed_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (stripe_mode in ('test', 'live')),
  check (length(trim(reason)) between 3 and 1200),
  check (status in ('PENDING', 'RUNNING', 'HEALTHY', 'REPAIRED', 'FAILED')),
  check (safe_error_code is null or safe_error_code ~ '^[A-Z0-9_]{3,80}$'),
  check (revision >= 1)
);

create index if not exists pachanga_stripe_event_processing_idx
  on private.pachanga_stripe_webhook_events_v2(processing_status, server_sequence, id)
  where processing_status in ('RECEIVED', 'FAILED_RETRYABLE');
create index if not exists pachanga_stripe_event_object_idx
  on private.pachanga_stripe_webhook_events_v2(stripe_mode, object_type, object_id, stripe_created_at desc, stripe_event_id desc);
create index if not exists pachanga_stripe_delivery_event_idx
  on private.pachanga_stripe_webhook_deliveries_v1(webhook_event_id, server_sequence desc)
  where webhook_event_id is not null;
create index if not exists pachanga_stripe_subscription_account_idx
  on private.pachanga_stripe_subscription_projections_v1(billing_account_id, server_sequence desc, id);
create index if not exists pachanga_stripe_subscription_customer_idx
  on private.pachanga_stripe_subscription_projections_v1(stripe_mode, stripe_customer_id);
create index if not exists pachanga_stripe_subscription_plan_idx
  on private.pachanga_stripe_subscription_projections_v1(plan_revision_id, status)
  where plan_revision_id is not null;
create index if not exists pachanga_stripe_invoice_account_idx
  on private.pachanga_stripe_invoice_projections_v1(billing_account_id, last_event_created_at desc, last_event_id desc);
create index if not exists pachanga_stripe_invoice_subscription_idx
  on private.pachanga_stripe_invoice_projections_v1(subscription_projection_id, server_sequence desc)
  where subscription_projection_id is not null;
create index if not exists pachanga_stripe_payment_failure_open_idx
  on private.pachanga_stripe_payment_failures_v1(billing_account_id, last_failed_at desc, id)
  where status in ('OPEN', 'ACTION_REQUIRED');
create index if not exists pachanga_stripe_reconciliation_queue_idx
  on private.pachanga_stripe_billing_reconciliations_v1(server_sequence, id)
  where status in ('PENDING', 'FAILED');

create or replace function private.pachanga_billing_safe_error_v1(source_error text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare sanitized text := upper(trim(coalesce(source_error, 'UNKNOWN')));
begin
  sanitized := regexp_replace(sanitized, '[^A-Z0-9_]+', '_', 'g');
  sanitized := trim(both '_' from sanitized);
  if length(sanitized) < 3 then sanitized := 'UNKNOWN'; end if;
  return left(sanitized, 80);
end;
$$;

create or replace function private.pachanga_billing_event_is_newer_v1(
  candidate_created_at timestamptz,
  candidate_event_id text,
  current_created_at timestamptz,
  current_event_id text
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select current_created_at is null
    or (candidate_created_at, candidate_event_id) > (current_created_at, current_event_id);
$$;

revoke all on function private.pachanga_billing_safe_error_v1(text) from public, anon, authenticated;
revoke all on function private.pachanga_billing_event_is_newer_v1(timestamptz, text, timestamptz, text) from public, anon, authenticated;

revoke all on table private.pachanga_stripe_webhook_events_v2 from public, anon, authenticated;
revoke all on table private.pachanga_stripe_webhook_deliveries_v1 from public, anon, authenticated;
revoke all on table private.pachanga_stripe_subscription_projections_v1 from public, anon, authenticated;
revoke all on table private.pachanga_stripe_invoice_projections_v1 from public, anon, authenticated;
revoke all on table private.pachanga_stripe_payment_failures_v1 from public, anon, authenticated;
revoke all on table private.pachanga_stripe_billing_reconciliations_v1 from public, anon, authenticated;

grant all on table private.pachanga_stripe_webhook_events_v2 to service_role;
grant all on table private.pachanga_stripe_webhook_deliveries_v1 to service_role;
grant all on table private.pachanga_stripe_subscription_projections_v1 to service_role;
grant all on table private.pachanga_stripe_invoice_projections_v1 to service_role;
grant all on table private.pachanga_stripe_payment_failures_v1 to service_role;
grant all on table private.pachanga_stripe_billing_reconciliations_v1 to service_role;

comment on table private.pachanga_stripe_webhook_events_v2 is
  'Signed Stripe event ledger. normalized_payload is allowlisted and must not contain card or customer PII.';
comment on function private.pachanga_billing_event_is_newer_v1(timestamptz, text, timestamptz, text) is
  'Stable event ordering; no latest projection query may depend on created_at alone.';
