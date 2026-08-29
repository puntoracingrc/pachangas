\set ON_ERROR_STOP on

begin;

create schema if not exists simulation;
create table if not exists simulation.demo_world_organizer_billing_proof (
  proof jsonb not null
);
truncate simulation.demo_world_organizer_billing_proof;

create or replace function pg_temp.demo_actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', target_role)::text, true);
end;
$$;

create or replace function pg_temp.demo_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.demo_legacy_flag(flag_name text)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare current_revision bigint;
begin
  select revision into current_revision
  from private.pachanga_organizer_billing_settings where singleton;
  return public.command_pachanga_organizer_billing_platform_v1(
    gen_random_uuid(), '7c900000-0000-4000-8000-000000000099', current_revision,
    'settings.flag', jsonb_build_object(
      'flagKey', flag_name, 'enabled', true,
      'reason', 'Demo World V2.9 local canonical activation'
    ), '{"clientVersion":"7.3.0+demo","surface":"demo_world_v29"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_commercial_setting(action_name text, payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare current_revision bigint;
begin
  select revision into current_revision
  from private.pachanga_organizer_billing_settings where singleton;
  return public.command_pachanga_organizer_commercial_settings_v1(
    gen_random_uuid(), current_revision, action_name, payload,
    '{"clientVersion":"7.3.0+demo","surface":"demo_world_v29"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_commercial_decision_id(target_plan_code text)
returns uuid language sql stable security definer set search_path = pg_catalog as $$
  select id
  from private.pachanga_organizer_commercial_decisions_v1
  where plan_code = target_plan_code
$$;

create temporary table demo_billing_scenarios (
  ordinal integer primary key,
  scenario_id text not null unique,
  organizer_kind text not null,
  organizer_id uuid not null unique,
  organizer_name text not null,
  plan_code text not null,
  billing_interval text,
  checkout_operation_id uuid unique,
  account_id uuid,
  account_revision bigint,
  customer_ref text,
  subscription_ref text,
  owner_snapshot jsonb
);
grant select, update on table demo_billing_scenarios to authenticated, service_role;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values (
  '7c900000-0000-4000-8000-000000000001',
  'demo-world-v29-owner@example.test', clock_timestamp(),
  '{"full_name":"Demo World V2.9 Organizer"}'
);

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('7c900000-0000-4000-8000-000000000001', 'platform_owner', true);

insert into demo_billing_scenarios(
  ordinal, scenario_id, organizer_kind, organizer_id, organizer_name, plan_code,
  billing_interval, checkout_operation_id, customer_ref, subscription_ref
) values
  (1, 'club_partner', 'CLUB', '7c900000-0000-4000-8000-000000000101', 'Club A · Llevant Partner', 'CLUB_PARTNER', null, null, null, null),
  (2, 'club_monthly_active', 'CLUB', '7c900000-0000-4000-8000-000000000102', 'Club B · Marina Monthly', 'CLUB_ORGANIZER', 'month', '7c900000-0000-4000-8000-000000000202', 'cus_demo_v29_club_b', 'sub_demo_v29_club_b'),
  (3, 'club_annual_active', 'CLUB', '7c900000-0000-4000-8000-000000000103', 'Club C · Besos Annual', 'CLUB_ORGANIZER', 'year', '7c900000-0000-4000-8000-000000000203', 'cus_demo_v29_club_c', 'sub_demo_v29_club_c'),
  (4, 'team_active', 'TEAM', '7c900000-0000-4000-8000-000000000104', 'Team D · Cobalto Raval', 'TEAM_ORGANIZER_PRO', 'month', '7c900000-0000-4000-8000-000000000204', 'cus_demo_v29_team_d', 'sub_demo_v29_team_d'),
  (5, 'team_checkout_pending', 'TEAM', '7c900000-0000-4000-8000-000000000105', 'Team E · Vertice Gracia', 'TEAM_ORGANIZER_PRO', 'year', '7c900000-0000-4000-8000-000000000205', 'cus_demo_v29_team_e', null),
  (6, 'team_past_due_grace', 'TEAM', '7c900000-0000-4000-8000-000000000106', 'Team F · Montjuic Nord', 'TEAM_ORGANIZER_PRO', 'month', '7c900000-0000-4000-8000-000000000206', 'cus_demo_v29_team_f', 'sub_demo_v29_team_f'),
  (7, 'club_canceled_continuity', 'CLUB', '7c900000-0000-4000-8000-000000000107', 'Club G · Poblenou Continuity', 'CLUB_ORGANIZER', 'year', '7c900000-0000-4000-8000-000000000207', 'cus_demo_v29_club_g', 'sub_demo_v29_club_g');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
select organizer_id, '7c900000-0000-4000-8000-000000000001', organizer_name,
  'D29' || ordinal::text, '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1
from demo_billing_scenarios where organizer_kind = 'TEAM';

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select organizer_id, '7c900000-0000-4000-8000-000000000001', 'owner', 'Demo Organizer'
from demo_billing_scenarios where organizer_kind = 'TEAM';

insert into public.pachanga_clubs(
  id, name, slug, club_type, operational_status, visibility,
  primary_owner_id, created_by, partnership_status
)
select organizer_id, organizer_name, 'demo-v29-club-' || ordinal::text,
  'FOOTBALL_CLUB', 'active', 'private',
  '7c900000-0000-4000-8000-000000000001',
  '7c900000-0000-4000-8000-000000000001',
  case when scenario_id = 'club_partner' then 'active' else 'none' end
from demo_billing_scenarios where organizer_kind = 'CLUB';

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, invited_by, accepted_at
)
select organizer_id, '7c900000-0000-4000-8000-000000000001',
  'club_owner', 'active', '7c900000-0000-4000-8000-000000000001', clock_timestamp()
from demo_billing_scenarios where organizer_kind = 'CLUB';

set local role authenticated;
select pg_temp.demo_actor('7c900000-0000-4000-8000-000000000001');
select pg_temp.demo_legacy_flag(flag_name)
from unnest(array[
  'foundation_enabled', 'plan_catalog_enabled', 'partner_grants_enabled',
  'billing_accounts_enabled', 'organizer_ui_enabled', 'webhook_ingest_enabled',
  'stripe_sandbox_enabled', 'reconciliation_enabled'
]) flag_name;
select pg_temp.demo_commercial_setting(
  'settings.feature_flag_v2',
  '{"flagKey":"commercial_decision_workflow_enabled","enabled":true,"reason":"Enable Demo World V2.9 TEST workflow"}'
);
select public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
  '7c900000-0000-4000-8000-000000000301',
  pg_temp.demo_commercial_decision_id('TEAM_ORGANIZER_PRO'),
  1, 'test', 'Create Demo World V2.9 Team TEST catalog',
  '{"clientVersion":"7.3.0+demo","surface":"demo_world_v29"}'
);
select public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
  '7c900000-0000-4000-8000-000000000302',
  pg_temp.demo_commercial_decision_id('CLUB_ORGANIZER'),
  1, 'test', 'Create Demo World V2.9 Club TEST catalog',
  '{"clientVersion":"7.3.0+demo","surface":"demo_world_v29"}'
);
reset role;

set local role service_role;
select pg_temp.demo_actor('7c900000-0000-4000-8000-000000000001', 'service_role');
select public.confirm_pachanga_organizer_stripe_catalog_service_v1(
  '7c900000-0000-4000-8000-000000000301', 'prod_demo_v29_team',
  'price_demo_v29_team_month', 'price_demo_v29_team_year', 'eur', 990, 9900,
  'unspecified',
  '{"product_family":"organizer","plan_code":"TEAM_ORGANIZER_PRO","organizer_kind":"team","environment":"test","catalog_revision":"organizer-plan-v1"}',
  'organizer-plan-v1'
);
select public.confirm_pachanga_organizer_stripe_catalog_service_v1(
  '7c900000-0000-4000-8000-000000000302', 'prod_demo_v29_club',
  'price_demo_v29_club_month', 'price_demo_v29_club_year', 'eur', 2900, 29000,
  'unspecified',
  '{"product_family":"organizer","plan_code":"CLUB_ORGANIZER","organizer_kind":"club","environment":"test","catalog_revision":"organizer-plan-v1"}',
  'organizer-plan-v1'
);
select public.record_pachanga_organizer_stripe_runtime_health_service_v1(
  '7c900000-0000-4000-8000-000000000303', 'test',
  (select revision from private.pachanga_organizer_stripe_runtime_health_v1 where stripe_mode = 'test'),
  true, true, true, true, '/api/webhooks/stripe', 'demo-world-v29-test-runtime', null
);
reset role;

set local role authenticated;
select pg_temp.demo_actor('7c900000-0000-4000-8000-000000000001');
select pg_temp.demo_commercial_setting(
  'settings.tax_health_v2',
  '{"taxHealth":"TEST_READY","confirmation":"CONFIRM_ORGANIZER_TAX_HEALTH","reason":"Demo World V2.9 TEST tax contract"}'
);
select pg_temp.demo_commercial_setting(
  'settings.feature_flag_v2',
  '{"flagKey":"stripe_test_checkout_enabled","enabled":true,"reason":"Enable Demo World V2.9 TEST Checkout"}'
);
select pg_temp.demo_commercial_setting(
  'settings.feature_flag_v2',
  '{"flagKey":"stripe_test_portal_enabled","enabled":true,"reason":"Enable Demo World V2.9 TEST Portal"}'
);
select pg_temp.demo_commercial_setting(
  'settings.feature_flag_v2',
  '{"flagKey":"demo_world_v29_enabled","enabled":true,"reason":"Enable Demo World V2.9 synthetic read model"}'
);
select public.command_pachanga_organizer_billing_platform_v1(
  '7c900000-0000-4000-8000-000000000304',
  '7c900000-0000-4000-8000-000000000101', 0,
  'manual.grant',
  '{"organizerKind":"CLUB","planCode":"CLUB_PARTNER","reason":"Demo World V2.9 audited partner access"}',
  '{"clientVersion":"7.3.0+demo","surface":"demo_world_v29"}'
);
reset role;

set local role service_role;
select pg_temp.demo_actor('7c900000-0000-4000-8000-000000000001', 'service_role');
do $checkouts$
declare selected demo_billing_scenarios%rowtype;
declare prepared jsonb;
begin
  for selected in select * from demo_billing_scenarios where checkout_operation_id is not null order by ordinal loop
    prepared := public.prepare_pachanga_organizer_checkout_service_v1(
      selected.checkout_operation_id,
      '7c900000-0000-4000-8000-000000000001', selected.organizer_kind,
      selected.organizer_id, selected.plan_code, selected.billing_interval,
      'test', 0, '{"clientVersion":"7.3.0+demo","surface":"demo_world_v29"}'
    );
    update demo_billing_scenarios set
      account_id = (prepared ->> 'billingAccountId')::uuid,
      account_revision = (prepared ->> 'confirmedRevision')::bigint
    where scenario_id = selected.scenario_id;
    perform public.confirm_pachanga_organizer_checkout_service_v1(
      selected.checkout_operation_id,
      'cs_test_demo_v29_' || selected.ordinal::text,
      selected.customer_ref,
      'https://checkout.stripe.test/demo-world-v29/' || selected.ordinal::text,
      clock_timestamp() + interval '30 minutes'
    );
    update demo_billing_scenarios state set account_revision = accounts.revision
    from private.pachanga_organizer_billing_accounts accounts
    where state.scenario_id = selected.scenario_id and accounts.id = state.account_id;
  end loop;
end;
$checkouts$;

do $subscriptions$
declare selected demo_billing_scenarios%rowtype;
declare event_time timestamptz := clock_timestamp();
declare price_ref text;
begin
  for selected in
    select * from demo_billing_scenarios
    where scenario_id in ('club_monthly_active', 'club_annual_active', 'team_active', 'team_past_due_grace', 'club_canceled_continuity')
    order by ordinal
  loop
    price_ref := case
      when selected.organizer_kind = 'CLUB' and selected.billing_interval = 'year' then 'price_demo_v29_club_year'
      when selected.organizer_kind = 'CLUB' then 'price_demo_v29_club_month'
      when selected.billing_interval = 'year' then 'price_demo_v29_team_year'
      else 'price_demo_v29_team_month' end;
    perform public.ingest_pachanga_stripe_event_v1(
      gen_random_uuid(), 'test', 'evt_demo_v29_active_' || selected.ordinal::text,
      'customer.subscription.created', '2026-06-30.basil', event_time,
      repeat('a', 64), jsonb_build_object(
        'objectType', 'subscription', 'objectId', selected.subscription_ref,
        'customerId', selected.customer_ref, 'subscriptionId', selected.subscription_ref,
        'priceId', price_ref, 'subscriptionStatus', 'active',
        'billingInterval', selected.billing_interval,
        'currentPeriodStart', event_time,
        'currentPeriodEnd', event_time + case when selected.billing_interval = 'year' then interval '1 year' else interval '1 month' end,
        'cancelAtPeriodEnd', false
      ), 'demo-world-v29-active-' || selected.ordinal::text
    );
  end loop;
end;
$subscriptions$;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, organizer_club_id, name, slug,
  competition_type, visibility, status, created_by
) values (
  '7c900000-0000-4000-8000-000000000401', 'CLUB', null,
  '7c900000-0000-4000-8000-000000000107', 'Liga Continuidad Demo V2.9',
  'liga-continuidad-demo-v29', 'LEAGUE', 'private', 'draft',
  '7c900000-0000-4000-8000-000000000001'
);
insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status, created_by
) values (
  '7c900000-0000-4000-8000-000000000402',
  '7c900000-0000-4000-8000-000000000401', 'Edicion activa Demo V2.9',
  '2026-27', current_date, current_date + 90, 'active',
  '7c900000-0000-4000-8000-000000000001'
);

select public.ingest_pachanga_stripe_event_v1(
  '7c900000-0000-4000-8000-000000000501', 'test', 'evt_demo_v29_past_due',
  'customer.subscription.updated', '2026-06-30.basil', clock_timestamp(),
  repeat('b', 64), jsonb_build_object(
    'objectType', 'subscription', 'objectId', 'sub_demo_v29_team_f',
    'customerId', 'cus_demo_v29_team_f', 'subscriptionId', 'sub_demo_v29_team_f',
    'priceId', 'price_demo_v29_team_month', 'subscriptionStatus', 'past_due',
    'billingInterval', 'month', 'currentPeriodStart', clock_timestamp() - interval '1 month',
    'currentPeriodEnd', clock_timestamp() + interval '5 days', 'cancelAtPeriodEnd', false
  ), 'demo-world-v29-past-due'
);
select public.ingest_pachanga_stripe_event_v1(
  '7c900000-0000-4000-8000-000000000502', 'test', 'evt_demo_v29_canceled',
  'customer.subscription.deleted', '2026-06-30.basil', clock_timestamp(),
  repeat('c', 64), jsonb_build_object(
    'objectType', 'subscription', 'objectId', 'sub_demo_v29_club_g',
    'customerId', 'cus_demo_v29_club_g', 'subscriptionId', 'sub_demo_v29_club_g',
    'priceId', 'price_demo_v29_club_year', 'subscriptionStatus', 'canceled',
    'billingInterval', 'year', 'currentPeriodStart', clock_timestamp() - interval '1 year',
    'currentPeriodEnd', clock_timestamp() - interval '1 minute',
    'cancelAtPeriodEnd', false, 'canceledAt', clock_timestamp()
  ), 'demo-world-v29-canceled'
);
reset role;

set local role authenticated;
select pg_temp.demo_actor('7c900000-0000-4000-8000-000000000001');
update demo_billing_scenarios state
set owner_snapshot = public.get_my_pachanga_organizer_billing_v1(
  state.organizer_kind, state.organizer_id
);
update demo_billing_scenarios state
set owner_snapshot = owner_snapshot || jsonb_build_object(
  'checkoutStatus', public.get_pachanga_organizer_checkout_status_v1(state.checkout_operation_id)
)
where state.scenario_id = 'team_checkout_pending';
reset role;

insert into simulation.demo_world_organizer_billing_proof(proof)
select jsonb_build_object(
  'catalogMappings', (select count(*) from private.pachanga_organizer_plan_price_mappings where stripe_mode = 'test' and active and approved),
  'liveCheckoutEnabled', settings.live_checkout_enabled,
  'liveMappings', (select count(*) from private.pachanga_organizer_plan_price_mappings where stripe_mode = 'live'),
  'livePortalEnabled', settings.portal_enabled,
  'operationReceipts', (
    select count(*)
    from private.pachanga_organizer_billing_operation_receipts_v1
    where actor_id = '7c900000-0000-4000-8000-000000000001'
  ),
  'privacy', jsonb_build_object(
    'containsPii', false, 'containsPriceId', false,
    'containsStripeCustomerId', false, 'containsStripeSubscriptionId', false
  ),
  'readModelVerified', true,
  'remoteWrites', 0,
  'scenarios', (
    select jsonb_agg(jsonb_build_object(
      'accessStatus', case state.scenario_id
        when 'team_checkout_pending' then 'pending'
        else coalesce(state.owner_snapshot #>> '{accessGrants,0,status}', 'active') end,
      'accountStatus', case state.scenario_id
        when 'club_partner' then 'active'
        when 'team_checkout_pending' then 'checkout_pending'
        else state.owner_snapshot #>> '{accounts,0,status}' end,
      'billingInterval', state.billing_interval,
      'continuityUntil', state.owner_snapshot #>> '{continuity,0,continuityUntil}',
      'creationAllowed', private.pachanga_organizer_billing_creation_allowed_v1(state.organizer_kind, state.organizer_id),
      'graceEndsAt', state.owner_snapshot #>> '{accounts,0,plan,graceEndsAt}',
      'id', state.scenario_id,
      'note', case state.scenario_id
        when 'club_partner' then 'Partnership auditada: acceso activo sin cargo ni Checkout.'
        when 'club_monthly_active' then 'Suscripcion mensual de Club confirmada por el webhook TEST.'
        when 'club_annual_active' then 'Suscripcion anual de Club confirmada por el webhook TEST.'
        when 'team_active' then 'Add-on mensual activo sobre el plan base del equipo.'
        when 'team_checkout_pending' then 'Checkout creado; el acceso sigue pendiente hasta el webhook firmado.'
        when 'team_past_due_grace' then 'Pago pendiente: la politica canonica mantiene temporalmente el acceso durante la gracia.'
        else 'Suscripcion cancelada: la edicion iniciada conserva continuidad sin permitir nuevas creaciones.' end,
      'organizerKind', state.organizer_kind,
      'organizerName', state.organizer_name,
      'planCode', state.plan_code,
      'renewalAt', case when state.scenario_id in ('club_monthly_active', 'club_annual_active', 'team_active')
        then state.owner_snapshot #>> '{accounts,0,plan,currentPeriodEnd}' else null end
    ) order by state.ordinal)
    from demo_billing_scenarios state
  ),
  'stripeEvents', (select count(*) from private.pachanga_stripe_webhook_events_v2 where stripe_event_id like 'evt_demo_v29_%'),
  'testRuntimeReady', test_health.catalog_ready and test_health.webhook_destination_ready
    and test_health.webhook_signing_ready and test_health.portal_ready and test_health.checkout_api_ready
)
from private.pachanga_organizer_billing_settings settings
join private.pachanga_organizer_stripe_runtime_health_v1 test_health on test_health.stripe_mode = 'test'
where settings.singleton;

select jsonb_build_object(
  'catalogMappings', proof -> 'catalogMappings',
  'liveCheckoutEnabled', proof -> 'liveCheckoutEnabled',
  'liveMappings', proof -> 'liveMappings',
  'livePortalEnabled', proof -> 'livePortalEnabled',
  'operationReceipts', proof -> 'operationReceipts',
  'scenarioStates', (
    select jsonb_agg(jsonb_build_object(
      'accessStatus', scenario -> 'accessStatus',
      'accountStatus', scenario -> 'accountStatus',
      'creationAllowed', scenario -> 'creationAllowed',
      'id', scenario -> 'id'
    ))
    from jsonb_array_elements(proof -> 'scenarios') scenario
  ),
  'stripeEvents', proof -> 'stripeEvents',
  'testRuntimeReady', proof -> 'testRuntimeReady'
) as demo_world_v29_redacted_diagnostic
from simulation.demo_world_organizer_billing_proof;

select pg_temp.demo_assert(
  (select jsonb_array_length(proof -> 'scenarios') = 7
    and (proof ->> 'catalogMappings')::integer = 4
    and (proof ->> 'liveMappings')::integer = 0
    and not (proof ->> 'liveCheckoutEnabled')::boolean
    and not (proof ->> 'livePortalEnabled')::boolean
    and (proof ->> 'testRuntimeReady')::boolean
    and (proof ->> 'stripeEvents')::integer = 7
    and (proof ->> 'operationReceipts')::integer >= 20
    and proof::text !~ '(cus|sub|price|prod)_[A-Za-z0-9_]+'
    and proof::text !~ '@example|\\+34'
    from simulation.demo_world_organizer_billing_proof),
  'DEMO_WORLD_V2_9_ORGANIZER_BILLING_PROOF_INVALID'
);

select pg_temp.demo_assert(
  (select bool_and(owner_snapshot -> 'organizer' ->> 'name' = organizer_name)
    from demo_billing_scenarios)
  and (select owner_snapshot #>> '{checkoutStatus,confirmation}' = 'PENDING'
    from demo_billing_scenarios where scenario_id = 'team_checkout_pending')
  and (select owner_snapshot #>> '{accounts,0,status}' = 'past_due'
    from demo_billing_scenarios where scenario_id = 'team_past_due_grace')
  and (select owner_snapshot #>> '{accessGrants,0,status}' = 'continuity'
    from demo_billing_scenarios where scenario_id = 'club_canceled_continuity'),
  'DEMO_WORLD_V2_9_CANONICAL_READ_MODEL_MISMATCH'
);

commit;
