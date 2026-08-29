-- Wave 7C: immutable commercial decisions and mode-specific activation flags.

set lock_timeout = '5s';
set statement_timeout = '5min';

alter table private.pachanga_organizer_billing_settings
  add column if not exists commercial_decision_workflow_enabled boolean not null default false,
  add column if not exists organizer_pricing_ui_enabled boolean not null default false,
  add column if not exists stripe_test_checkout_enabled boolean not null default false,
  add column if not exists stripe_test_portal_enabled boolean not null default false,
  add column if not exists stripe_test_webhook_ready boolean not null default false,
  add column if not exists stripe_test_portal_ready boolean not null default false,
  add column if not exists stripe_live_webhook_ready boolean not null default false,
  add column if not exists stripe_live_portal_ready boolean not null default false,
  add column if not exists demo_world_v29_enabled boolean not null default false,
  add column if not exists organizer_terms_revision text,
  add column if not exists organizer_privacy_revision text;

alter table private.pachanga_organizer_billing_settings
  drop constraint if exists pachanga_organizer_billing_settings_tax_health_check,
  drop constraint if exists pachanga_organizer_billing_settings_check8;

update private.pachanga_organizer_billing_settings
set tax_health = case tax_health
  when 'SANDBOX_READY' then 'TEST_READY'
  when 'LIVE_REVIEW_REQUIRED' then 'TAX_REVIEW_REQUIRED'
  else tax_health
end
where tax_health in ('SANDBOX_READY', 'LIVE_REVIEW_REQUIRED');

alter table private.pachanga_organizer_billing_settings
  add constraint pachanga_organizer_billing_settings_tax_health_v2_ck
    check (tax_health in (
      'UNCONFIGURED', 'COMMERCIAL_DECISION_PENDING', 'TAX_REVIEW_REQUIRED',
      'TEST_READY', 'LIVE_READY', 'BLOCKED'
    )),
  add constraint pachanga_organizer_billing_settings_test_checkout_v1_ck
    check (not stripe_test_checkout_enabled or (
      foundation_enabled and plan_catalog_enabled and billing_accounts_enabled
      and webhook_ingest_enabled and stripe_sandbox_enabled
      and stripe_test_webhook_ready and tax_health in ('TEST_READY', 'LIVE_READY')
    )),
  add constraint pachanga_organizer_billing_settings_test_portal_v1_ck
    check (not stripe_test_portal_enabled or (
      billing_accounts_enabled and stripe_sandbox_enabled and stripe_test_portal_ready
    )),
  add constraint pachanga_organizer_billing_settings_live_checkout_v2_ck
    check (not live_checkout_enabled or (
      foundation_enabled and plan_catalog_enabled and billing_accounts_enabled
      and webhook_ingest_enabled and portal_enabled and live_prices_approved
      and stripe_live_webhook_ready and stripe_live_portal_ready
      and tax_health = 'LIVE_READY'
    ));

alter table private.pachanga_organizer_billing_accounts
  drop constraint if exists pachanga_organizer_billing_accou_tax_configuration_status_check;

update private.pachanga_organizer_billing_accounts
set tax_configuration_status = case tax_configuration_status
  when 'SANDBOX_READY' then 'TEST_READY'
  when 'LIVE_REVIEW_REQUIRED' then 'TAX_REVIEW_REQUIRED'
  else tax_configuration_status
end
where tax_configuration_status in ('SANDBOX_READY', 'LIVE_REVIEW_REQUIRED');

alter table private.pachanga_organizer_billing_accounts
  add constraint pachanga_organizer_billing_accounts_tax_health_v2_ck
    check (tax_configuration_status in (
      'UNCONFIGURED', 'COMMERCIAL_DECISION_PENDING', 'TAX_REVIEW_REQUIRED',
      'TEST_READY', 'LIVE_READY', 'BLOCKED'
    ));

create table if not exists private.pachanga_organizer_commercial_decisions_v1 (
  id uuid primary key default gen_random_uuid(),
  plan_code text not null references public.pachanga_organizer_plan_catalog(plan_code) on delete restrict,
  organizer_kind text not null,
  currency text not null,
  monthly_amount_minor bigint not null,
  annual_amount_minor bigint not null,
  tax_display_mode text not null default 'PENDING_REVIEW',
  stripe_tax_behavior text not null default 'unspecified',
  trial_days integer not null default 0,
  effective_from timestamptz,
  public_copy_revision text not null,
  terms_revision text not null,
  privacy_revision text not null,
  decision_kind text not null default 'PROPOSED',
  status text not null default 'draft',
  approved_by uuid references auth.users(id) on delete restrict,
  approved_at timestamptz,
  published_at timestamptz,
  supersedes_id uuid references private.pachanga_organizer_commercial_decisions_v1(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  operation_id uuid not null unique,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (plan_code, revision),
  check (plan_code in ('CLUB_PARTNER', 'TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER')),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (currency ~ '^[A-Z]{3}$'),
  check (monthly_amount_minor >= 0 and annual_amount_minor >= 0),
  check (tax_display_mode in ('PENDING_REVIEW', 'TAX_INCLUDED', 'TAX_EXCLUDED')),
  check (stripe_tax_behavior in ('inclusive', 'exclusive', 'unspecified')),
  check (trial_days between 0 and 365),
  check (length(trim(public_copy_revision)) between 3 and 120),
  check (length(trim(terms_revision)) between 3 and 120),
  check (length(trim(privacy_revision)) between 3 and 120),
  check (decision_kind in ('PROPOSED', 'APPROVED_COMMERCIAL')),
  check (status in ('draft', 'pending_approval', 'approved', 'published', 'withdrawn', 'superseded')),
  check (revision >= 1),
  check (
    status not in ('approved', 'published', 'superseded')
    or (approved_by is not null and approved_at is not null and effective_from is not null)
  ),
  check (status not in ('published', 'superseded') or published_at is not null),
  check (plan_code <> 'CLUB_PARTNER' or (organizer_kind = 'CLUB' and monthly_amount_minor = 0 and annual_amount_minor = 0)),
  check (plan_code <> 'CLUB_ORGANIZER' or organizer_kind = 'CLUB'),
  check (plan_code <> 'TEAM_ORGANIZER_PRO' or organizer_kind = 'TEAM')
);

create unique index if not exists pachanga_organizer_commercial_published_plan_idx
  on private.pachanga_organizer_commercial_decisions_v1(plan_code)
  where status = 'published';

create index if not exists pachanga_organizer_commercial_status_idx
  on private.pachanga_organizer_commercial_decisions_v1(status, effective_from, server_sequence desc, id);

create index if not exists pachanga_organizer_commercial_supersedes_idx
  on private.pachanga_organizer_commercial_decisions_v1(supersedes_id)
  where supersedes_id is not null;

insert into private.pachanga_organizer_commercial_decisions_v1(
  plan_code, organizer_kind, currency, monthly_amount_minor, annual_amount_minor,
  tax_display_mode, stripe_tax_behavior, trial_days, effective_from,
  public_copy_revision, terms_revision, privacy_revision, decision_kind, status,
  operation_id
)
select seed.plan_code, seed.organizer_kind, 'EUR', seed.monthly_amount_minor,
  seed.annual_amount_minor, 'PENDING_REVIEW', 'unspecified', 0, null,
  'organizer-pricing-v1-proposal', 'PENDING_APPROVAL', 'PENDING_APPROVAL',
  'PROPOSED', 'draft', gen_random_uuid()
from (values
  ('CLUB_PARTNER'::text, 'CLUB'::text, 0::bigint, 0::bigint),
  ('TEAM_ORGANIZER_PRO'::text, 'TEAM'::text, 990::bigint, 9900::bigint),
  ('CLUB_ORGANIZER'::text, 'CLUB'::text, 2900::bigint, 29000::bigint)
) seed(plan_code, organizer_kind, monthly_amount_minor, annual_amount_minor)
where not exists (
  select 1 from private.pachanga_organizer_commercial_decisions_v1 existing
  where existing.plan_code = seed.plan_code
);

revoke all on table private.pachanga_organizer_commercial_decisions_v1 from public, anon, authenticated;
grant all on table private.pachanga_organizer_commercial_decisions_v1 to service_role;

comment on table private.pachanga_organizer_commercial_decisions_v1 is
  'Wave 7C commercial authority. Draft proposals never authorize live Stripe resources or Checkout.';
