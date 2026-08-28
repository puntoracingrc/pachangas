\set ON_ERROR_STOP on

do $permissions$
declare target_role text;
begin
  foreach target_role in array array['authenticated', 'anon', 'service_role'] loop
    if not has_schema_privilege(target_role, 'auth', 'USAGE') then
      execute format('grant usage on schema auth to %I', target_role);
    end if;
    if not has_function_privilege(target_role, 'auth.uid()', 'EXECUTE') then
      execute format('grant execute on function auth.uid() to %I', target_role);
    end if;
    if not has_function_privilege(target_role, 'auth.jwt()', 'EXECUTE') then
      execute format('grant execute on function auth.jwt() to %I', target_role);
    end if;
  end loop;
end;
$permissions$;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', target_role)::text, true);
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'WAVE7C_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'WAVE7C_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.legacy_flag(flag_name text, flag_value boolean default true)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare current_revision bigint;
begin
  select revision into current_revision from private.pachanga_organizer_billing_settings where singleton;
  return public.command_pachanga_organizer_billing_platform_v1(
    gen_random_uuid(), '7b000000-0000-4000-8000-000000000099', current_revision,
    'settings.flag', jsonb_build_object('flagKey', flag_name, 'enabled', flag_value,
      'reason', 'Wave 7C local dependency activation'),
    '{"clientVersion":"7.3.0+db","surface":"wave7c_db"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.commercial_setting(action_name text, payload jsonb)
returns jsonb language plpgsql security definer set search_path = pg_catalog as $$
declare current_revision bigint;
begin
  select revision into current_revision from private.pachanga_organizer_billing_settings where singleton;
  return public.command_pachanga_organizer_commercial_settings_v1(
    gen_random_uuid(), current_revision, action_name, payload,
    '{"clientVersion":"7.3.0+db","surface":"wave7c_db"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.billing_revision()
returns bigint language sql stable security definer set search_path = pg_catalog as $$
  select revision from private.pachanga_organizer_billing_settings where singleton
$$;

create or replace function pg_temp.commercial_decision_id(target_plan_code text)
returns uuid language sql stable security definer set search_path = pg_catalog as $$
  select id
  from private.pachanga_organizer_commercial_decisions_v1
  where plan_code = target_plan_code
$$;

create or replace function pg_temp.stripe_runtime_revision(target_mode text)
returns bigint language sql stable security definer set search_path = pg_catalog as $$
  select revision
  from private.pachanga_organizer_stripe_runtime_health_v1
  where stripe_mode = target_mode
$$;

create or replace function pg_temp.billing_account_revision(target_account_id uuid)
returns bigint language sql stable security definer set search_path = pg_catalog as $$
  select revision
  from private.pachanga_organizer_billing_accounts
  where id = target_account_id
$$;

create temporary table wave7c_state(
  test_team_checkout_operation uuid,
  test_team_account_id uuid,
  test_team_account_revision bigint,
  activation_operation uuid
);
insert into wave7c_state values (
  '7c100000-0000-4000-8000-000000000201', null, null,
  '7c100000-0000-4000-8000-000000000301'
);
grant all on table wave7c_state to authenticated, service_role;

select pg_temp.assert_true(
  (select count(*) = 3 from private.pachanga_organizer_commercial_decisions_v1)
  and (select count(*) = 3 from private.pachanga_organizer_commercial_decisions_v1 where status = 'draft')
  and (select count(*) = 0 from private.pachanga_organizer_plan_price_mappings)
  and (select not commercial_decision_workflow_enabled and not organizer_pricing_ui_enabled
    and not stripe_test_checkout_enabled and not stripe_test_portal_enabled
    and not stripe_test_webhook_ready and not stripe_test_portal_ready
    and not stripe_live_webhook_ready and not stripe_live_portal_ready
    and not demo_world_v29_enabled and not live_prices_approved
    and not live_checkout_enabled and not portal_enabled
    from private.pachanga_organizer_billing_settings where singleton),
  'Wave 7C must install with three proposals, zero mappings and every commercial flag OFF'
);
select pg_temp.assert_true(
  (select monthly_amount_minor = 990 and annual_amount_minor = 9900
    from private.pachanga_organizer_commercial_decisions_v1 where plan_code = 'TEAM_ORGANIZER_PRO')
  and (select monthly_amount_minor = 2900 and annual_amount_minor = 29000
    from private.pachanga_organizer_commercial_decisions_v1 where plan_code = 'CLUB_ORGANIZER')
  and (select monthly_amount_minor = 0 and annual_amount_minor = 0
    from private.pachanga_organizer_commercial_decisions_v1 where plan_code = 'CLUB_PARTNER'),
  'The three proposed amounts must remain exact and non-authoritative'
);

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select pg_temp.legacy_flag('foundation_enabled');
select pg_temp.legacy_flag('plan_catalog_enabled');
select pg_temp.legacy_flag('billing_accounts_enabled');
select pg_temp.legacy_flag('organizer_ui_enabled');
select pg_temp.legacy_flag('webhook_ingest_enabled');
select pg_temp.legacy_flag('stripe_sandbox_enabled');
select pg_temp.legacy_flag('reconciliation_enabled');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_billing_platform_v1(%L::uuid,%L::uuid,%s,%L,%L::jsonb,%L::jsonb)',
  gen_random_uuid(), '7b000000-0000-4000-8000-000000000099',
  pg_temp.billing_revision(),
  'settings.flag', '{"flagKey":"live_prices_approved","enabled":true,"reason":"legacy bypass"}', '{}'
), 'BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_billing_platform_v1(%L::uuid,%L::uuid,%s,%L,%L::jsonb,%L::jsonb)',
  gen_random_uuid(), '7b000000-0000-4000-8000-000000000099',
  pg_temp.billing_revision(),
  'settings.flag', '{"flagKey":"portal_enabled","enabled":true,"reason":"legacy bypass"}', '{}'
), 'BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_billing_platform_v1(%L::uuid,%L::uuid,%s,%L,%L::jsonb,%L::jsonb)',
  gen_random_uuid(), '7b000000-0000-4000-8000-000000000099',
  pg_temp.billing_revision(),
  'settings.tax_health', '{"taxHealth":"LIVE_READY","reason":"legacy bypass"}', '{}'
), 'BILLING_COMMERCIAL_SETTINGS_AUTHORITY_REQUIRED');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_billing_platform_v1(%L::uuid,%L::uuid,0,%L,%L::jsonb,%L::jsonb)',
  gen_random_uuid(), gen_random_uuid(), 'price_mapping.upsert',
  '{"planCode":"TEAM_ORGANIZER_PRO","stripeMode":"live","billingInterval":"month","stripeProductId":"prod_legacy","stripePriceId":"price_legacy","currency":"eur","unitAmount":"990","taxBehavior":"inclusive","approved":true,"reason":"legacy bypass"}', '{}'
), 'BILLING_STRIPE_CATALOG_AUTHORITY_REQUIRED');
select pg_temp.expect_failure(
  $$update private.pachanga_organizer_commercial_decisions_v1 set monthly_amount_minor = 1 where plan_code = 'TEAM_ORGANIZER_PRO'$$,
  'permission denied'
);
select pg_temp.commercial_setting('settings.feature_flag_v2',
  '{"flagKey":"commercial_decision_workflow_enabled","enabled":true,"reason":"Enable audited test workflow"}');
reset role;

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000002');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_organizer_commercial_decision_v1(%L::uuid,%L::uuid,1,%L,%L::jsonb,%L::jsonb)',
  gen_random_uuid(), pg_temp.commercial_decision_id('TEAM_ORGANIZER_PRO'),
  'commercial_decision.submit', '{"reason":"player cannot approve"}', '{}'
), 'PLATFORM');
reset role;

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
  '7c100000-0000-4000-8000-000000000001',
  pg_temp.commercial_decision_id('TEAM_ORGANIZER_PRO'),
  1, 'test', 'Create Team Organizer Pro TEST catalog', '{"surface":"wave7c_db"}'
);
select public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
  '7c100000-0000-4000-8000-000000000002',
  pg_temp.commercial_decision_id('CLUB_ORGANIZER'),
  1, 'test', 'Create Club Organizer TEST catalog', '{"surface":"wave7c_db"}'
);
reset role;

set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
select public.confirm_pachanga_organizer_stripe_catalog_service_v1(
  '7c100000-0000-4000-8000-000000000001', 'prod_wave7c_test_team',
  'price_wave7c_test_team_month', 'price_wave7c_test_team_year', 'eur', 990, 9900,
  'unspecified', '{"product_family":"organizer","plan_code":"TEAM_ORGANIZER_PRO","organizer_kind":"team","environment":"test","catalog_revision":"organizer-plan-v1"}',
  'organizer-plan-v1'
);
select public.confirm_pachanga_organizer_stripe_catalog_service_v1(
  '7c100000-0000-4000-8000-000000000002', 'prod_wave7c_test_club',
  'price_wave7c_test_club_month', 'price_wave7c_test_club_year', 'eur', 2900, 29000,
  'unspecified', '{"product_family":"organizer","plan_code":"CLUB_ORGANIZER","organizer_kind":"club","environment":"test","catalog_revision":"organizer-plan-v1"}',
  'organizer-plan-v1'
);
select public.record_pachanga_organizer_stripe_runtime_health_service_v1(
  gen_random_uuid(), 'test',
  pg_temp.stripe_runtime_revision('test'),
  true, true, true, true, '/api/webhooks/stripe', 'wave7c-test-runtime-v1', null
);
reset role;

select pg_temp.assert_true(
  (select count(*) = 4 from private.pachanga_organizer_plan_price_mappings
    where stripe_mode='test' and approved and active and commercial_decision_id is not null)
  and (select catalog_ready and product_count = 2 and price_count = 4
    from private.pachanga_organizer_stripe_runtime_health_v1 where stripe_mode='test'),
  'TEST catalog readback must own exactly two Products and four Prices'
);

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select pg_temp.commercial_setting('settings.tax_health_v2',
  '{"taxHealth":"TEST_READY","confirmation":"CONFIRM_ORGANIZER_TAX_HEALTH","reason":"TEST tax review complete"}');
select pg_temp.commercial_setting('settings.feature_flag_v2',
  '{"flagKey":"stripe_test_checkout_enabled","enabled":true,"reason":"Enable TEST Checkout"}');
select pg_temp.commercial_setting('settings.feature_flag_v2',
  '{"flagKey":"stripe_test_portal_enabled","enabled":true,"reason":"Enable TEST Portal"}');
reset role;

set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
with prepared as (
  select public.prepare_pachanga_organizer_checkout_service_v1(
    (select test_team_checkout_operation from wave7c_state),
    '7b000000-0000-4000-8000-000000000001', 'TEAM',
    '7b000000-0000-4000-8000-000000000010', 'TEAM_ORGANIZER_PRO',
    'month', 'test', 0, '{"surface":"wave7c_db"}'
  ) body
)
update wave7c_state set test_team_account_id=(body->>'billingAccountId')::uuid,
  test_team_account_revision=(body->>'confirmedRevision')::bigint from prepared;
select public.confirm_pachanga_organizer_checkout_service_v1(
  (select test_team_checkout_operation from wave7c_state), 'cs_test_wave7c_team',
  'cus_wave7c_team', 'https://checkout.stripe.test/wave7c', clock_timestamp()+interval '30 minutes'
);
update wave7c_state
set test_team_account_revision=pg_temp.billing_account_revision(test_team_account_id);
select public.prepare_pachanga_organizer_portal_service_v1(
  '7c100000-0000-4000-8000-000000000202',
  '7b000000-0000-4000-8000-000000000001', 'TEAM',
  '7b000000-0000-4000-8000-000000000010', 'test',
  (select test_team_account_revision from wave7c_state), '{"surface":"wave7c_db"}'
);
select public.confirm_pachanga_organizer_portal_service_v1(
  '7c100000-0000-4000-8000-000000000202', 'bps_wave7c_team',
  'https://billing.stripe.test/wave7c', clock_timestamp()+interval '30 minutes'
);
select pg_temp.expect_failure(format(
  'select public.prepare_pachanga_organizer_portal_service_v1(%L::uuid,%L::uuid,%L,%L::uuid,%L,%s,%L::jsonb)',
  gen_random_uuid(), '7b000000-0000-4000-8000-000000000001', 'TEAM',
  '7b000000-0000-4000-8000-000000000010', 'live', 0, '{}'
), 'BILLING_LIVE_PORTAL_DISABLED');
reset role;

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.assert_true(
  public.get_pachanga_organizer_plan_catalog_v1()::text not like '%prod_wave7c%'
  and public.get_pachanga_organizer_plan_catalog_v1()::text not like '%price_wave7c%'
  and not (public.get_pachanga_organizer_plan_catalog_v1() ->> 'liveCheckoutEnabled')::boolean,
  'Public catalog must not expose TEST identifiers or draft proposal amounts'
);
reset role;

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select pg_temp.expect_failure(format(
  'select public.activate_pachanga_organizer_live_checkout_platform_v1(%L::uuid,%s,%L,%L,%L,%L,%L::jsonb)',
  gen_random_uuid(), pg_temp.billing_revision(),
  'CONFIRM_ORGANIZER_LIVE_CHECKOUT', 'Too early', 'terms-v1', 'privacy-v1', '{}'
), 'BILLING_LIVE_ACTIVATION_GATE_INCOMPLETE');

select public.command_pachanga_organizer_commercial_decision_v1(
  gen_random_uuid(), pg_temp.commercial_decision_id('TEAM_ORGANIZER_PRO'), 1,
  'commercial_decision.update',
  '{"currency":"EUR","monthlyAmountMinor":990,"annualAmountMinor":9900,"taxDisplayMode":"TAX_INCLUDED","stripeTaxBehavior":"inclusive","trialDays":0,"effectiveFrom":"2026-09-01T00:00:00Z","publicCopyRevision":"organizer-pricing-v1","termsRevision":"terms-v1","privacyRevision":"privacy-v1","reason":"Complete Team commercial proposal"}', '{}'
);
select public.command_pachanga_organizer_commercial_decision_v1(
  gen_random_uuid(), pg_temp.commercial_decision_id('TEAM_ORGANIZER_PRO'), 2,
  'commercial_decision.submit', '{"reason":"Submit Team commercial proposal"}', '{}'
);
select public.command_pachanga_organizer_commercial_decision_v1(
  gen_random_uuid(), pg_temp.commercial_decision_id('TEAM_ORGANIZER_PRO'), 3,
  'commercial_decision.approve',
  '{"billingIntervals":["month","year"],"confirmLivePricing":"CONFIRM_STRIPE_LIVE_PRICING","currency":"EUR","monthlyAmountMinor":990,"annualAmountMinor":9900,"taxDisplayMode":"TAX_INCLUDED","stripeTaxBehavior":"inclusive","effectiveFrom":"2026-09-01T00:00:00Z","termsRevision":"terms-v1","privacyRevision":"privacy-v1","reason":"Approve Team Organizer pricing"}', '{}'
);
select public.command_pachanga_organizer_commercial_decision_v1(
  gen_random_uuid(), pg_temp.commercial_decision_id('CLUB_ORGANIZER'), 1,
  'commercial_decision.update',
  '{"currency":"EUR","monthlyAmountMinor":2900,"annualAmountMinor":29000,"taxDisplayMode":"TAX_INCLUDED","stripeTaxBehavior":"inclusive","trialDays":0,"effectiveFrom":"2026-09-01T00:00:00Z","publicCopyRevision":"organizer-pricing-v1","termsRevision":"terms-v1","privacyRevision":"privacy-v1","reason":"Complete Club commercial proposal"}', '{}'
);
select public.command_pachanga_organizer_commercial_decision_v1(
  gen_random_uuid(), pg_temp.commercial_decision_id('CLUB_ORGANIZER'), 2,
  'commercial_decision.submit', '{"reason":"Submit Club commercial proposal"}', '{}'
);
select public.command_pachanga_organizer_commercial_decision_v1(
  gen_random_uuid(), pg_temp.commercial_decision_id('CLUB_ORGANIZER'), 3,
  'commercial_decision.approve',
  '{"billingIntervals":["month","year"],"confirmLivePricing":"CONFIRM_STRIPE_LIVE_PRICING","currency":"EUR","monthlyAmountMinor":2900,"annualAmountMinor":29000,"taxDisplayMode":"TAX_INCLUDED","stripeTaxBehavior":"inclusive","effectiveFrom":"2026-09-01T00:00:00Z","termsRevision":"terms-v1","privacyRevision":"privacy-v1","reason":"Approve Club Organizer pricing"}', '{}'
);
select pg_temp.commercial_setting('settings.tax_health_v2',
  '{"taxHealth":"LIVE_READY","confirmation":"CONFIRM_ORGANIZER_TAX_HEALTH","termsRevision":"terms-v1","privacyRevision":"privacy-v1","reason":"Commercial and tax review complete"}');
reset role;

set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
select public.record_pachanga_organizer_stripe_runtime_health_service_v1(
  gen_random_uuid(), 'live', 1, true, true, true, true,
  '/api/webhooks/stripe', 'wave7c-live-runtime-v1', null
);
reset role;

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
  '7c100000-0000-4000-8000-000000000101',
  pg_temp.commercial_decision_id('TEAM_ORGANIZER_PRO'),
  4, 'live', 'Create approved Team live catalog fixture', '{}');
select public.prepare_pachanga_organizer_stripe_catalog_platform_v1(
  '7c100000-0000-4000-8000-000000000102',
  pg_temp.commercial_decision_id('CLUB_ORGANIZER'),
  4, 'live', 'Create approved Club live catalog fixture', '{}');
reset role;

set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
select public.confirm_pachanga_organizer_stripe_catalog_service_v1(
  '7c100000-0000-4000-8000-000000000101', 'prod_wave7c_live_team',
  'price_wave7c_live_team_month', 'price_wave7c_live_team_year', 'eur', 990, 9900,
  'inclusive', '{"product_family":"organizer","plan_code":"TEAM_ORGANIZER_PRO","organizer_kind":"team","environment":"live","catalog_revision":"organizer-plan-v1"}',
  'organizer-plan-v1');
select public.confirm_pachanga_organizer_stripe_catalog_service_v1(
  '7c100000-0000-4000-8000-000000000102', 'prod_wave7c_live_club',
  'price_wave7c_live_club_month', 'price_wave7c_live_club_year', 'eur', 2900, 29000,
  'inclusive', '{"product_family":"organizer","plan_code":"CLUB_ORGANIZER","organizer_kind":"club","environment":"live","catalog_revision":"organizer-plan-v1"}',
  'organizer-plan-v1');
reset role;

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.activate_pachanga_organizer_live_checkout_platform_v1(
  (select activation_operation from wave7c_state),
  pg_temp.billing_revision(),
  'CONFIRM_ORGANIZER_LIVE_CHECKOUT', 'Approved controlled activation',
  'terms-v1', 'privacy-v1', '{"surface":"wave7c_db"}'
);
select pg_temp.assert_true(
  (public.activate_pachanga_organizer_live_checkout_platform_v1(
    (select activation_operation from wave7c_state),
    pg_temp.billing_revision() - 1,
    'CONFIRM_ORGANIZER_LIVE_CHECKOUT', 'Approved controlled activation',
    'terms-v1', 'privacy-v1', '{"surface":"wave7c_db"}') ->> 'replayed')::boolean,
  'Live activation replay must return the original receipt'
);
reset role;

select pg_temp.assert_true(
  (select live_prices_approved and live_checkout_enabled and portal_enabled
    and organizer_pricing_ui_enabled from private.pachanga_organizer_billing_settings where singleton)
  and (select count(*) = 4 from private.pachanga_organizer_plan_price_mappings
    where stripe_mode='live' and active and approved and commercial_decision_id is not null)
  and (select count(*) = 2 from private.pachanga_organizer_commercial_decisions_v1
    where status='published' and plan_code in ('TEAM_ORGANIZER_PRO','CLUB_ORGANIZER')),
  'One canonical activation must bind two published decisions to four live mappings'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.assert_true(
  (public.get_pachanga_organizer_plan_catalog_v1() ->> 'liveCheckoutEnabled')::boolean
  and public.get_pachanga_organizer_plan_catalog_v1()::text not like '%prod_wave7c_live%'
  and public.get_pachanga_organizer_plan_catalog_v1()::text not like '%price_wave7c_live%'
  and (select jsonb_array_length(item -> 'prices') = 2
    from jsonb_array_elements(public.get_pachanga_organizer_plan_catalog_v1() -> 'plans') item
    where item ->> 'planCode' = 'TEAM_ORGANIZER_PRO'),
  'Public catalog may expose approved prices but never Stripe identifiers'
);
reset role;

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000004');
select pg_temp.assert_true(
  public.get_my_pachanga_organizer_billing_v1('CLUB', '7b000000-0000-4000-8000-000000000020')
    -> 'availability' ->> 'sandboxCheckout' = 'true'
  and public.get_my_pachanga_organizer_billing_v1('CLUB', '7b000000-0000-4000-8000-000000000020')
    -> 'availability' ->> 'liveCheckout' = 'true',
  'Owner read model must separate TEST and LIVE availability'
);
reset role;

select pg_temp.assert_true(
  not has_function_privilege('authenticated',
    'public.confirm_pachanga_organizer_stripe_catalog_service_v1(uuid,text,text,text,text,bigint,bigint,text,jsonb,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.record_pachanga_organizer_stripe_runtime_health_service_v1(uuid,text,bigint,boolean,boolean,boolean,boolean,text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.command_pachanga_organizer_commercial_decision_v1(uuid,uuid,bigint,text,jsonb,jsonb)', 'EXECUTE'),
  'Service confirmation and commercial writes must preserve least privilege'
);

select 'ORGANIZER_COMMERCIAL_ACTIVATION_V1_DB_OK';
