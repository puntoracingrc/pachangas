\set ON_ERROR_STOP on

begin;
set local statement_timeout = '10min';
set local lock_timeout = '5s';

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select md5('wave7b-scale-user:' || value)::uuid,
  'wave7b-scale-' || value || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'Wave 7B Scale Owner ' || value)
from generate_series(1, 2000) value;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
select md5('wave7b-scale-team:' || value)::uuid,
  md5('wave7b-scale-user:' || value)::uuid,
  'Wave 7B Scale Team ' || value,
  'W7B' || lpad(value::text, 5, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb,
  1
from generate_series(1, 2000) value;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select md5('wave7b-scale-team:' || value)::uuid,
  md5('wave7b-scale-user:' || value)::uuid,
  'owner',
  'Wave 7B Scale Owner ' || value
from generate_series(1, 2000) value;

set constraints all immediate;

update private.pachanga_organizer_billing_settings set
  foundation_enabled=true,
  plan_catalog_enabled=true,
  billing_accounts_enabled=true,
  organizer_ui_enabled=true,
  webhook_ingest_enabled=true,
  stripe_sandbox_enabled=true,
  portal_enabled=true,
  reconciliation_enabled=true,
  live_checkout_enabled=false,
  live_prices_approved=false,
  updated_at=clock_timestamp()
where singleton;

insert into private.pachanga_organizer_plan_price_mappings(
  plan_revision_id, stripe_mode, billing_interval, stripe_product_id, stripe_price_id,
  currency, unit_amount, tax_behavior, approved, active
) values (
  '00000000-0000-0000-0000-00000000b713', 'test', 'month',
  'prod_wave7b_scale', 'price_wave7b_scale_month', 'eur', 1299,
  'unspecified', false, true
);

insert into private.pachanga_organizer_billing_accounts(
  id, organizer_kind, organizer_group_id, stripe_mode, stripe_customer_id,
  billing_contact_user_id, locale, billing_country, tax_configuration_status,
  current_plan_family, status, revision, server_sequence
)
select md5('wave7b-scale-account:' || value)::uuid,
  'TEAM', md5('wave7b-scale-team:' || value)::uuid, 'test',
  'cus_wave7b_scale_' || value,
  md5('wave7b-scale-user:' || value)::uuid,
  'es-ES', 'ES', 'SANDBOX_READY', 'ORGANIZER',
  case when value % 10 = 0 then 'past_due'
    when value % 17 = 0 then 'canceled' else 'active' end,
  1, nextval('private.pachanga_organizer_billing_sequence')
from generate_series(1, 2000) value;

insert into private.pachanga_stripe_subscription_projections_v1(
  id, billing_account_id, stripe_mode, stripe_subscription_id, stripe_customer_id,
  plan_revision_id, stripe_price_id, status, billing_interval,
  current_period_start, current_period_end, cancel_at_period_end, canceled_at,
  grace_ends_at, last_event_created_at, last_event_id, revision, server_sequence
)
select md5('wave7b-scale-subscription:' || value)::uuid,
  md5('wave7b-scale-account:' || value)::uuid,
  'test', 'sub_wave7b_scale_' || value, 'cus_wave7b_scale_' || value,
  '00000000-0000-0000-0000-00000000b713', 'price_wave7b_scale_month',
  case when value % 10 = 0 then 'past_due'
    when value % 17 = 0 then 'canceled' else 'active' end,
  'month', clock_timestamp() - interval '15 days', clock_timestamp() + interval '15 days',
  value % 17 = 0,
  case when value % 17 = 0 then clock_timestamp() - interval '1 day' end,
  case when value % 10 = 0 then clock_timestamp() + interval '3 days' end,
  clock_timestamp() - make_interval(secs => 2000 - value),
  'evt_wave7b_scale_subscription_' || value,
  1, nextval('private.pachanga_organizer_billing_sequence')
from generate_series(1, 2000) value;

insert into private.pachanga_organizer_access_grants_v1(
  id, organizer_kind, organizer_group_id, billing_account_id,
  subscription_projection_id, plan_revision_id, access_source, source_reference,
  status, valid_from, valid_until, reason, revoked_at, revision, server_sequence
)
select md5('wave7b-scale-access:' || value)::uuid,
  'TEAM', md5('wave7b-scale-team:' || value)::uuid,
  md5('wave7b-scale-account:' || value)::uuid,
  md5('wave7b-scale-subscription:' || value)::uuid,
  '00000000-0000-0000-0000-00000000b713',
  'SUBSCRIPTION', 'subscription:test:sub_wave7b_scale_' || value,
  case when value % 10 = 0 then 'grace'
    when value % 17 = 0 then 'revoked' else 'active' end,
  clock_timestamp() - interval '15 days',
  case when value % 10 = 0 then clock_timestamp() + interval '3 days' end,
  'Wave 7B representative volume',
  case when value % 17 = 0 then clock_timestamp() - interval '1 day' end,
  1, nextval('private.pachanga_organizer_billing_sequence')
from generate_series(1, 2000) value;

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  valid_from, expires_at, reason, revision, server_sequence,
  billing_access_grant_id, billing_subscription_projection_id, billing_plan_revision_id
)
select 'TEAM', md5('wave7b-scale-team:' || account_number)::uuid,
  features.feature_key, 'subscription', 'active',
  clock_timestamp() - interval '15 days',
  case when account_number % 10 = 0 then clock_timestamp() + interval '3 days' end,
  'Wave 7B representative subscription entitlement', 1,
  nextval('private.pachanga_organizer_billing_sequence'),
  md5('wave7b-scale-access:' || account_number)::uuid,
  md5('wave7b-scale-subscription:' || account_number)::uuid,
  '00000000-0000-0000-0000-00000000b713'
from generate_series(1, 2000) account_number
join public.pachanga_organizer_plan_features features
  on features.plan_revision_id='00000000-0000-0000-0000-00000000b713'
  and features.enabled and features.entitlement_capability
where account_number % 17 <> 0;

insert into private.pachanga_stripe_webhook_events_v2(
  stripe_mode, stripe_event_id, event_type, api_version, object_type, object_id,
  stripe_created_at, payload_checksum, normalized_payload, processing_status,
  processed_at, server_sequence
)
select 'test', 'evt_wave7b_scale_' || value,
  'customer.updated', '2026-06-30.basil', 'customer',
  'cus_wave7b_scale_' || (((value - 1) % 2000) + 1),
  clock_timestamp() - make_interval(secs => 10000 - value),
  md5(value::text) || md5('wave7b:' || value), '{}'::jsonb, 'PROCESSED',
  clock_timestamp(), nextval('private.pachanga_organizer_billing_sequence')
from generate_series(1, 10000) value;

insert into private.pachanga_stripe_webhook_deliveries_v1(
  operation_id, webhook_event_id, endpoint_mode, signature_verified,
  delivery_status, http_result, request_id, server_sequence
)
select md5('wave7b-scale-delivery:' || value)::uuid,
  events.id, 'test', true, 'ACCEPTED', 200,
  'req-wave7b-scale-' || value,
  nextval('private.pachanga_organizer_billing_sequence')
from generate_series(1, 10000) value
join private.pachanga_stripe_webhook_events_v2 events
  on events.stripe_event_id='evt_wave7b_scale_' || value;

insert into private.pachanga_stripe_invoice_projections_v1(
  billing_account_id, subscription_projection_id, stripe_mode, stripe_invoice_id,
  stripe_subscription_id, stripe_customer_id, status, currency,
  amount_due, amount_paid, last_event_created_at, last_event_id, server_sequence
)
select md5('wave7b-scale-account:' || source.account_number)::uuid,
  md5('wave7b-scale-subscription:' || source.account_number)::uuid,
  'test', 'in_wave7b_scale_' || source.value,
  'sub_wave7b_scale_' || source.account_number,
  'cus_wave7b_scale_' || source.account_number,
  case when source.value % 4 = 0 then 'open' else 'paid' end,
  'eur', 1299, case when source.value % 4 = 0 then 0 else 1299 end,
  clock_timestamp() - make_interval(secs => 4000 - source.value),
  'evt_wave7b_scale_invoice_' || source.value,
  nextval('private.pachanga_organizer_billing_sequence')
from (
  select value, ((value - 1) % 2000) + 1 as account_number
  from generate_series(1, 4000) value
) source;

insert into private.pachanga_stripe_payment_failures_v1(
  billing_account_id, subscription_projection_id, invoice_projection_id,
  stripe_mode, failure_key, safe_failure_code, status,
  first_failed_at, last_failed_at, server_sequence
)
select invoices.billing_account_id, invoices.subscription_projection_id, invoices.id,
  'test', invoices.stripe_invoice_id, 'CARD_DECLINED', 'OPEN',
  clock_timestamp() - interval '1 day', clock_timestamp(),
  nextval('private.pachanga_organizer_billing_sequence')
from private.pachanga_stripe_invoice_projections_v1 invoices
where invoices.status='open'
order by invoices.id
limit 400;

insert into private.pachanga_stripe_billing_reconciliations_v1(
  operation_id, billing_account_id, stripe_mode, reason, status,
  difference_codes, safe_error_code, server_sequence
)
select md5('wave7b-scale-reconciliation:' || value)::uuid,
  md5('wave7b-scale-account:' || (((value - 1) % 2000) + 1))::uuid,
  'test', 'Wave 7B representative reconciliation', 'PENDING',
  array['REMOTE_DRIFT'], 'BILLING_REMOTE_DRIFT',
  nextval('private.pachanga_organizer_billing_sequence')
from generate_series(1, 10000) value;

analyze private.pachanga_organizer_billing_accounts;
analyze private.pachanga_stripe_subscription_projections_v1;
analyze private.pachanga_organizer_access_grants_v1;
analyze public.pachanga_competition_entitlement_grants;
analyze private.pachanga_stripe_webhook_events_v2;
analyze private.pachanga_stripe_webhook_deliveries_v1;
analyze private.pachanga_stripe_invoice_projections_v1;
analyze private.pachanga_stripe_payment_failures_v1;
analyze private.pachanga_stripe_billing_reconciliations_v1;

commit;
