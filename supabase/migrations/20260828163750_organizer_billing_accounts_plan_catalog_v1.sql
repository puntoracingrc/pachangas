-- Wave 7B: organizer-owned billing accounts and a server-side plan catalog.
-- Commercial flags default OFF and no live Price is seeded by this migration.

set lock_timeout = '5s';
set statement_timeout = '5min';

create sequence if not exists private.pachanga_organizer_billing_sequence;
revoke all on sequence private.pachanga_organizer_billing_sequence from public, anon, authenticated;
grant usage, select on sequence private.pachanga_organizer_billing_sequence to service_role;

create table if not exists private.pachanga_organizer_billing_settings (
  singleton boolean primary key default true check (singleton),
  foundation_enabled boolean not null default false,
  plan_catalog_enabled boolean not null default false,
  partner_grants_enabled boolean not null default false,
  billing_accounts_enabled boolean not null default false,
  organizer_ui_enabled boolean not null default false,
  webhook_ingest_enabled boolean not null default false,
  stripe_sandbox_enabled boolean not null default false,
  portal_enabled boolean not null default false,
  reconciliation_enabled boolean not null default false,
  live_checkout_enabled boolean not null default false,
  demo_world_v28_enabled boolean not null default false,
  live_prices_approved boolean not null default false,
  tax_health text not null default 'UNCONFIGURED',
  grace_period_days integer not null default 7,
  continuity_max_days integer not null default 120,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (tax_health in ('UNCONFIGURED', 'SANDBOX_READY', 'LIVE_REVIEW_REQUIRED', 'LIVE_READY', 'BLOCKED')),
  check (grace_period_days between 0 and 60),
  check (continuity_max_days between 1 and 366),
  check (revision >= 1),
  check (not plan_catalog_enabled or foundation_enabled),
  check (not partner_grants_enabled or foundation_enabled),
  check (not billing_accounts_enabled or foundation_enabled),
  check (not organizer_ui_enabled or (foundation_enabled and plan_catalog_enabled)),
  check (not webhook_ingest_enabled or (foundation_enabled and billing_accounts_enabled)),
  check (not stripe_sandbox_enabled or webhook_ingest_enabled),
  check (not portal_enabled or billing_accounts_enabled),
  check (not reconciliation_enabled or webhook_ingest_enabled),
  check (
    not live_checkout_enabled
    or (
      foundation_enabled and plan_catalog_enabled and billing_accounts_enabled
      and webhook_ingest_enabled and portal_enabled and live_prices_approved
      and tax_health = 'LIVE_READY'
    )
  )
);

insert into private.pachanga_organizer_billing_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists public.pachanga_organizer_plan_catalog (
  id uuid primary key,
  plan_code text not null unique,
  organizer_kind text not null,
  plan_family text not null,
  access_model text not null,
  public_available boolean not null default false,
  requires_stripe boolean not null default false,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (plan_code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  check (organizer_kind in ('TEAM', 'CLUB', 'ANY')),
  check (plan_family in ('ORGANIZER', 'INTERNAL_ACCESS')),
  check (access_model in ('SUBSCRIPTION', 'PARTNERSHIP', 'PROMOTION', 'PRIVATE_BETA', 'PLATFORM_GRANT')),
  check (status in ('draft', 'active', 'retired')),
  check (revision >= 1),
  check (not requires_stripe or access_model = 'SUBSCRIPTION')
);

create table if not exists public.pachanga_organizer_plan_revisions (
  id uuid primary key,
  plan_id uuid not null references public.pachanga_organizer_plan_catalog(id) on delete restrict,
  version integer not null,
  display_name text not null,
  summary text not null,
  status text not null default 'active',
  effective_from timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (plan_id, version),
  check (version >= 1),
  check (length(trim(display_name)) between 3 and 100),
  check (length(trim(summary)) between 3 and 600),
  check (status in ('draft', 'active', 'retired')),
  check (effective_until is null or effective_until > effective_from),
  check (revision >= 1)
);

create table if not exists public.pachanga_organizer_plan_features (
  id uuid primary key default gen_random_uuid(),
  plan_revision_id uuid not null references public.pachanga_organizer_plan_revisions(id) on delete cascade,
  feature_key text not null,
  entitlement_capability boolean not null default false,
  enabled boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  unique (plan_revision_id, feature_key),
  check (feature_key ~ '^[a-z][a-z0-9_]{2,79}$'),
  check (display_order between 0 and 10000)
);

create table if not exists public.pachanga_organizer_plan_limits (
  id uuid primary key default gen_random_uuid(),
  plan_revision_id uuid not null references public.pachanga_organizer_plan_revisions(id) on delete cascade,
  limit_key text not null,
  limit_value bigint,
  unit text not null default 'count',
  enforcement_mode text not null default 'FUTURE_CREATION',
  display_order integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  unique (plan_revision_id, limit_key),
  check (limit_key ~ '^[a-z][A-Za-z0-9]{2,79}$'),
  check (limit_value is null or limit_value >= 0),
  check (unit in ('count', 'bytes')),
  check (enforcement_mode in ('FUTURE_CREATION', 'INFORMATIONAL')),
  check (display_order between 0 and 10000)
);

create table if not exists private.pachanga_organizer_plan_price_mappings (
  id uuid primary key default gen_random_uuid(),
  plan_revision_id uuid not null references public.pachanga_organizer_plan_revisions(id) on delete restrict,
  stripe_mode text not null,
  billing_interval text not null,
  stripe_product_id text not null,
  stripe_price_id text not null,
  currency text not null,
  unit_amount bigint,
  tax_behavior text not null,
  approved boolean not null default false,
  active boolean not null default true,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (stripe_mode, stripe_price_id),
  unique (plan_revision_id, stripe_mode, billing_interval),
  check (stripe_mode in ('test', 'live')),
  check (billing_interval in ('month', 'year')),
  check (stripe_product_id ~ '^prod_[A-Za-z0-9_]+$'),
  check (stripe_price_id ~ '^price_[A-Za-z0-9_]+$'),
  check (currency ~ '^[a-z]{3}$'),
  check (unit_amount is null or unit_amount >= 0),
  check (tax_behavior in ('inclusive', 'exclusive', 'unspecified')),
  check (revision >= 1),
  check ((approved and approved_by is not null and approved_at is not null) or not approved)
);

create table if not exists private.pachanga_organizer_billing_accounts (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  stripe_mode text not null,
  stripe_customer_id text,
  billing_contact_user_id uuid references auth.users(id) on delete set null,
  locale text not null default 'es-ES',
  billing_country text,
  tax_configuration_status text not null default 'UNCONFIGURED',
  current_plan_family text,
  status text not null default 'unconfigured',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (stripe_mode in ('test', 'live')),
  check (stripe_customer_id is null or stripe_customer_id ~ '^cus_[A-Za-z0-9_]+$'),
  check (locale ~ '^[a-z]{2}(?:-[A-Z]{2})?$'),
  check (billing_country is null or billing_country ~ '^[A-Z]{2}$'),
  check (tax_configuration_status in ('UNCONFIGURED', 'SANDBOX_READY', 'LIVE_REVIEW_REQUIRED', 'LIVE_READY', 'BLOCKED')),
  check (current_plan_family is null or current_plan_family in ('ORGANIZER')),
  check (status in ('unconfigured', 'ready', 'active', 'past_due', 'canceled', 'blocked')),
  check (revision >= 1)
);

create unique index if not exists pachanga_organizer_billing_account_team_mode_idx
  on private.pachanga_organizer_billing_accounts(organizer_group_id, stripe_mode)
  where organizer_kind = 'TEAM';
create unique index if not exists pachanga_organizer_billing_account_club_mode_idx
  on private.pachanga_organizer_billing_accounts(organizer_club_id, stripe_mode)
  where organizer_kind = 'CLUB';
create unique index if not exists pachanga_organizer_billing_account_customer_idx
  on private.pachanga_organizer_billing_accounts(stripe_mode, stripe_customer_id)
  where stripe_customer_id is not null;
create index if not exists pachanga_organizer_billing_account_contact_idx
  on private.pachanga_organizer_billing_accounts(billing_contact_user_id)
  where billing_contact_user_id is not null;
create index if not exists pachanga_organizer_plan_revision_active_idx
  on public.pachanga_organizer_plan_revisions(plan_id, effective_from desc, id)
  where status = 'active';
create index if not exists pachanga_organizer_plan_feature_revision_idx
  on public.pachanga_organizer_plan_features(plan_revision_id, display_order, feature_key);
create index if not exists pachanga_organizer_plan_limit_revision_idx
  on public.pachanga_organizer_plan_limits(plan_revision_id, display_order, limit_key);
create index if not exists pachanga_organizer_price_mapping_health_idx
  on private.pachanga_organizer_plan_price_mappings(stripe_mode, active, approved, plan_revision_id);

alter table public.pachanga_organizer_plan_catalog enable row level security;
alter table public.pachanga_organizer_plan_revisions enable row level security;
alter table public.pachanga_organizer_plan_features enable row level security;
alter table public.pachanga_organizer_plan_limits enable row level security;

revoke all on table public.pachanga_organizer_plan_catalog from public, anon, authenticated;
revoke all on table public.pachanga_organizer_plan_revisions from public, anon, authenticated;
revoke all on table public.pachanga_organizer_plan_features from public, anon, authenticated;
revoke all on table public.pachanga_organizer_plan_limits from public, anon, authenticated;
revoke all on table private.pachanga_organizer_billing_settings from public, anon, authenticated;
revoke all on table private.pachanga_organizer_plan_price_mappings from public, anon, authenticated;
revoke all on table private.pachanga_organizer_billing_accounts from public, anon, authenticated;

grant all on table public.pachanga_organizer_plan_catalog to service_role;
grant all on table public.pachanga_organizer_plan_revisions to service_role;
grant all on table public.pachanga_organizer_plan_features to service_role;
grant all on table public.pachanga_organizer_plan_limits to service_role;
grant all on table private.pachanga_organizer_billing_settings to service_role;
grant all on table private.pachanga_organizer_plan_price_mappings to service_role;
grant all on table private.pachanga_organizer_billing_accounts to service_role;

insert into public.pachanga_organizer_plan_catalog(
  id, plan_code, organizer_kind, plan_family, access_model, public_available, requires_stripe
) values
  ('00000000-0000-0000-0000-00000000b701', 'CLUB_PARTNER', 'CLUB', 'ORGANIZER', 'PARTNERSHIP', true, false),
  ('00000000-0000-0000-0000-00000000b702', 'CLUB_ORGANIZER', 'CLUB', 'ORGANIZER', 'SUBSCRIPTION', true, true),
  ('00000000-0000-0000-0000-00000000b703', 'TEAM_ORGANIZER_PRO', 'TEAM', 'ORGANIZER', 'SUBSCRIPTION', true, true),
  ('00000000-0000-0000-0000-00000000b704', 'PROMOTION', 'ANY', 'INTERNAL_ACCESS', 'PROMOTION', false, false),
  ('00000000-0000-0000-0000-00000000b705', 'PRIVATE_BETA', 'ANY', 'INTERNAL_ACCESS', 'PRIVATE_BETA', false, false),
  ('00000000-0000-0000-0000-00000000b706', 'PLATFORM_GRANT', 'ANY', 'INTERNAL_ACCESS', 'PLATFORM_GRANT', false, false)
on conflict (id) do nothing;

insert into public.pachanga_organizer_plan_revisions(
  id, plan_id, version, display_name, summary
) values
  ('00000000-0000-0000-0000-00000000b711', '00000000-0000-0000-0000-00000000b701', 1, 'Club colaborador', 'Acceso de organizacion concedido por una partnership auditada, sin cobro.'),
  ('00000000-0000-0000-0000-00000000b712', '00000000-0000-0000-0000-00000000b702', 1, 'Club Organizer', 'Plan de organizacion para Clubs. El precio live permanece pendiente de aprobacion.'),
  ('00000000-0000-0000-0000-00000000b713', '00000000-0000-0000-0000-00000000b703', 1, 'Team Organizer Pro', 'Add-on de organizacion para el owner de un equipo. No sustituye el plan base.'),
  ('00000000-0000-0000-0000-00000000b714', '00000000-0000-0000-0000-00000000b704', 1, 'Promocion', 'Acceso temporal concedido por una promocion auditada.'),
  ('00000000-0000-0000-0000-00000000b715', '00000000-0000-0000-0000-00000000b705', 1, 'Private Beta', 'Acceso interno y revocable para una beta privada.'),
  ('00000000-0000-0000-0000-00000000b716', '00000000-0000-0000-0000-00000000b706', 1, 'Platform Grant', 'Acceso interno concedido por una autoridad de plataforma.')
on conflict (id) do nothing;

with revisions(id) as (
  values
    ('00000000-0000-0000-0000-00000000b711'::uuid),
    ('00000000-0000-0000-0000-00000000b712'::uuid),
    ('00000000-0000-0000-0000-00000000b713'::uuid),
    ('00000000-0000-0000-0000-00000000b714'::uuid),
    ('00000000-0000-0000-0000-00000000b715'::uuid),
    ('00000000-0000-0000-0000-00000000b716'::uuid)
), capabilities(feature_key, display_order) as (
  values
    ('competition_create', 10), ('competition_manage', 20), ('competition_staff', 30),
    ('competition_rules', 40), ('competition_referees', 50), ('competition_discipline', 60),
    ('competition_entries_manage', 70), ('competition_rosters_review', 80),
    ('competition_categories_manage', 90), ('competition_schedule', 100),
    ('competition_results', 110), ('competition_standings', 120),
    ('competition_operations', 130), ('competition_discipline_manage', 140),
    ('competition_discipline_review', 150), ('competition_appeals_manage', 160),
    ('tournament_create', 170), ('tournament_manage', 180),
    ('tournament_draw', 190), ('tournament_draw_publish', 200)
)
insert into public.pachanga_organizer_plan_features(
  plan_revision_id, feature_key, entitlement_capability, enabled, display_order
)
select revisions.id, capabilities.feature_key, true, true, capabilities.display_order
from revisions cross join capabilities
on conflict (plan_revision_id, feature_key) do nothing;

with revisions(id) as (
  values
    ('00000000-0000-0000-0000-00000000b711'::uuid),
    ('00000000-0000-0000-0000-00000000b712'::uuid),
    ('00000000-0000-0000-0000-00000000b713'::uuid),
    ('00000000-0000-0000-0000-00000000b714'::uuid),
    ('00000000-0000-0000-0000-00000000b715'::uuid),
    ('00000000-0000-0000-0000-00000000b716'::uuid)
), limits(limit_key, display_order) as (
  values
    ('activeCompetitions', 10), ('activeEditions', 20), ('maxTeamsPerCompetition', 30),
    ('publicCompetitions', 40), ('leagueCreation', 50), ('tournamentCreation', 60),
    ('staffSeats', 70), ('scheduledMatches', 80), ('refereeAssignments', 90),
    ('storageDocuments', 100)
)
insert into public.pachanga_organizer_plan_limits(
  plan_revision_id, limit_key, limit_value, unit, enforcement_mode, display_order
)
select revisions.id, limits.limit_key, null, case when limits.limit_key = 'storageDocuments' then 'bytes' else 'count' end,
  case when limits.limit_key = 'storageDocuments' then 'INFORMATIONAL' else 'FUTURE_CREATION' end,
  limits.display_order
from revisions cross join limits
on conflict (plan_revision_id, limit_key) do nothing;

comment on table private.pachanga_organizer_billing_accounts is
  'Organizer-owned Stripe Customer authority. Ownership changes do not create a new billing account.';
comment on table private.pachanga_organizer_plan_price_mappings is
  'Private allowlist for Stripe Prices. Wave 7B seeds no live Price and invents no commercial amount.';
comment on table public.pachanga_organizer_plan_limits is
  'Null limit_value means the commercial limit is not yet approved; React must not invent one.';
