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
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', target_role)::text,
    true
  );
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'WAVE7B_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'WAVE7B_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.enable_billing_flag(flag_name text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings_revision bigint;
begin
  select revision into settings_revision
  from private.pachanga_organizer_billing_settings where singleton;
  return public.command_pachanga_organizer_billing_platform_v1(
    gen_random_uuid(),
    '7b000000-0000-4000-8000-000000000099',
    settings_revision,
    'settings.flag',
    jsonb_build_object('flagKey', flag_name, 'enabled', true, 'reason', 'Wave 7B database test activation'),
    '{"clientVersion":"7.1.0+db","serviceWorkerVersion":"sw-wave7b","installedMode":"browser","surface":"wave7b_db","secret":"discard-me"}'
  );
end;
$$;

create temporary table wave7b_state(
  partner_access_id uuid,
  checkout_operation_id uuid,
  billing_account_id uuid,
  account_revision bigint,
  subscription_id uuid,
  subscription_revision bigint,
  continuity_id uuid
);
insert into wave7b_state default values;
grant all on table wave7b_state to authenticated, service_role;

-- Installation is inert and contains no invented Stripe price.
select pg_temp.assert_true(
  not foundation_enabled and not plan_catalog_enabled and not partner_grants_enabled
    and not billing_accounts_enabled and not organizer_ui_enabled
    and not webhook_ingest_enabled and not stripe_sandbox_enabled
    and not portal_enabled and not reconciliation_enabled
    and not live_checkout_enabled and not live_prices_approved,
  'Wave 7B must install with every billing flag OFF'
)
from private.pachanga_organizer_billing_settings where singleton;
select pg_temp.assert_true(
  (select count(*) = 6 from public.pachanga_organizer_plan_catalog)
    and (select count(*) = 0 from private.pachanga_organizer_plan_price_mappings),
  'Wave 7B must seed six plans and zero Stripe price mappings'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated',
    'public.prepare_pachanga_organizer_checkout_service_v1(uuid,uuid,text,uuid,text,text,text,bigint,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.ingest_pachanga_stripe_event_v1(uuid,text,text,text,text,timestamptz,text,jsonb,text)', 'EXECUTE'),
  'Checkout preparation and webhook ingestion must remain service-only'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select pg_temp.assert_true(
  public.get_pachanga_organizer_plan_catalog_v1() ->> 'status' = 'NOT_AVAILABLE',
  'The public catalog must fail closed before activation'
);
reset role;

-- Platform activation follows dependency order; live checkout stays OFF.
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select pg_temp.enable_billing_flag('foundation_enabled');
select pg_temp.enable_billing_flag('plan_catalog_enabled');
select pg_temp.enable_billing_flag('partner_grants_enabled');
select pg_temp.enable_billing_flag('billing_accounts_enabled');
select pg_temp.enable_billing_flag('organizer_ui_enabled');
select pg_temp.enable_billing_flag('webhook_ingest_enabled');
select pg_temp.enable_billing_flag('stripe_sandbox_enabled');
select pg_temp.enable_billing_flag('portal_enabled');
select pg_temp.enable_billing_flag('reconciliation_enabled');
select pg_temp.enable_billing_flag('demo_world_v28_enabled');
reset role;
select pg_temp.assert_true(
  not (select live_checkout_enabled from private.pachanga_organizer_billing_settings where singleton),
  'Live checkout must remain OFF without approved live price and tax evidence'
);

-- Test-mode price mapping is an explicit fixture and never activates live commerce.
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.command_pachanga_organizer_billing_platform_v1(
  '7b100000-0000-4000-8000-000000000001',
  '7b100000-0000-4000-8000-000000000002', 0,
  'price_mapping.upsert',
  '{
    "planCode":"TEAM_ORGANIZER_PRO","stripeMode":"test","billingInterval":"month",
    "stripeProductId":"prod_wave7b_test","stripePriceId":"price_wave7b_test_month",
    "currency":"eur","unitAmount":"1299","taxBehavior":"unspecified",
    "approved":false,"reason":"Local Stripe test fixture"
  }',
  '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
);
reset role;

-- A billing-linked partnership bundle coexists with a pre-existing legacy grant.
insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_club_id, capability, grant_source, reason, granted_by
) values (
  'CLUB', '7b000000-0000-4000-8000-000000000020', 'competition_create',
  'platform_grant', 'Pre-existing independent platform entitlement',
  '7b000000-0000-4000-8000-000000000003'
);

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
with granted as (
  select public.command_pachanga_organizer_billing_platform_v1(
    '7b100000-0000-4000-8000-000000000010',
    '7b000000-0000-4000-8000-000000000020', 0,
    'manual.grant',
    '{"organizerKind":"CLUB","planCode":"CLUB_PARTNER","reason":"Audited Wave 7B partner grant"}',
    '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
  ) body
)
update wave7b_state
set partner_access_id = (granted.body ->> 'accessGrantId')::uuid
from granted;
reset role;

select pg_temp.assert_true(
  (select count(*) = 20 from public.pachanga_competition_entitlement_grants grants
    where grants.billing_access_grant_id = (select partner_access_id from wave7b_state)
      and grants.status = 'active')
  and (select count(*) = 1 from public.pachanga_competition_entitlement_grants grants
    where grants.organizer_club_id = '7b000000-0000-4000-8000-000000000020'
      and grants.capability = 'competition_create'
      and grants.billing_access_grant_id is null and grants.status = 'active'),
  'Partner grant must create its own capability bundle without replacing legacy authority'
);

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select pg_temp.assert_true(
  (public.command_pachanga_organizer_billing_platform_v1(
    '7b100000-0000-4000-8000-000000000010',
    '7b000000-0000-4000-8000-000000000020', 0,
    'manual.grant',
    '{"organizerKind":"CLUB","planCode":"CLUB_PARTNER","reason":"Audited Wave 7B partner grant"}',
    '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
  ) ->> 'replayed')::boolean,
  'Manual grant replay must be exact and idempotent'
);

select public.command_pachanga_organizer_billing_platform_v1(
  '7b100000-0000-4000-8000-000000000011',
  (select partner_access_id from wave7b_state), 1,
  'manual.revoke', '{"reason":"Revoke only the partnership bundle"}',
  '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
);
reset role;
select pg_temp.assert_true(
  (select count(*) = 0 from public.pachanga_competition_entitlement_grants grants
    where grants.billing_access_grant_id = (select partner_access_id from wave7b_state)
      and grants.status = 'active')
  and (select count(*) = 1 from public.pachanga_competition_entitlement_grants grants
    where grants.organizer_club_id = '7b000000-0000-4000-8000-000000000020'
      and grants.capability = 'competition_create'
      and grants.billing_access_grant_id is null and grants.status = 'active'),
  'Revoking a partner bundle must not revoke an independent legacy grant'
);

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.command_pachanga_organizer_billing_platform_v1(
  '7b100000-0000-4000-8000-000000000012',
  (select partner_access_id from wave7b_state), 2,
  'manual.renew', '{"reason":"Restore audited partnership access","expiresAt":"2028-12-31T23:59:59Z"}',
  '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
);
reset role;

-- Only the Club owner may read billing details.
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000004');
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_billing_organizers_v1() -> 'items') = 1
    and public.get_my_pachanga_billing_organizers_v1() -> 'items' -> 0 ->> 'kind' = 'CLUB'
    and public.get_my_pachanga_billing_organizers_v1() -> 'items' -> 0 ->> 'id'
      = '7b000000-0000-4000-8000-000000000020',
  'Organizer selector must expose only the Club owned by the current actor'
);
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_organizer_billing_v1(
    'CLUB', '7b000000-0000-4000-8000-000000000020'
  ) -> 'accessGrants') = 1,
  'Club owner must see the canonical partner access bundle'
);
select pg_temp.actor('7b000000-0000-4000-8000-000000000002');
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_billing_organizers_v1() -> 'items') = 0,
  'Organizer selector must not expose teams merely because the actor is a member'
);
select pg_temp.expect_failure(
  $$select public.get_my_pachanga_organizer_billing_v1(
    'CLUB', '7b000000-0000-4000-8000-000000000020'
  )$$,
  'BILLING_OWNER_REQUIRED'
);
reset role;

-- The service prepares and confirms Checkout, but neither action grants access.
set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
with prepared as (
  select public.prepare_pachanga_organizer_checkout_service_v1(
    '7b200000-0000-4000-8000-000000000001',
    '7b000000-0000-4000-8000-000000000001',
    'TEAM', '7b000000-0000-4000-8000-000000000010',
    'TEAM_ORGANIZER_PRO', 'month', 'test', 0,
    '{"clientVersion":"7.1.0+db","serviceWorkerVersion":"sw-wave7b","installedMode":"standalone","surface":"billing_settings"}'
  ) body
)
update wave7b_state set
  checkout_operation_id = '7b200000-0000-4000-8000-000000000001',
  billing_account_id = (prepared.body ->> 'billingAccountId')::uuid,
  account_revision = (prepared.body ->> 'confirmedRevision')::bigint
from prepared;

select pg_temp.assert_true(
  (public.prepare_pachanga_organizer_checkout_service_v1(
    '7b200000-0000-4000-8000-000000000001',
    '7b000000-0000-4000-8000-000000000001',
    'TEAM', '7b000000-0000-4000-8000-000000000010',
    'TEAM_ORGANIZER_PRO', 'month', 'test', 0,
    '{"clientVersion":"7.1.0+db","serviceWorkerVersion":"sw-wave7b","installedMode":"standalone","surface":"billing_settings"}'
  ) ->> 'replayed')::boolean,
  'Checkout preparation replay must not create a second billing account or intent'
);
select public.confirm_pachanga_organizer_checkout_service_v1(
  '7b200000-0000-4000-8000-000000000001',
  'cs_test_wave7b_001', 'cus_wave7b_001',
  'https://checkout.stripe.test/session/wave7b', clock_timestamp() + interval '30 minutes'
);
update wave7b_state state set account_revision = accounts.revision
from private.pachanga_organizer_billing_accounts accounts
where accounts.id = state.billing_account_id;
select pg_temp.assert_true(
  (select count(*) = 0 from private.pachanga_organizer_access_grants_v1 access
    where access.billing_account_id = (select billing_account_id from wave7b_state)),
  'Checkout session creation must never grant organizer access'
);

select public.ingest_pachanga_stripe_event_v1(
  '7b200000-0000-4000-8000-000000000010', 'test', 'evt_wave7b_checkout_001',
  'checkout.session.completed', '2026-06-30.basil', '2026-08-28T12:00:00Z',
  repeat('a', 64),
  '{"objectType":"checkout.session","objectId":"cs_test_wave7b_001","customerId":"cus_wave7b_001","metadataOperationId":"7b200000-0000-4000-8000-000000000001","checkoutSessionId":"cs_test_wave7b_001","checkoutStatus":"complete"}',
  'req-wave7b-checkout'
);
select pg_temp.assert_true(
  (select count(*) = 0 from private.pachanga_organizer_access_grants_v1 access
    where access.billing_account_id = (select billing_account_id from wave7b_state)),
  'Checkout success webhook must remain non-authoritative for entitlements'
);

-- Only a signed subscription event projects canonical access.
select public.ingest_pachanga_stripe_event_v1(
  '7b200000-0000-4000-8000-000000000011', 'test', 'evt_wave7b_subscription_001',
  'customer.subscription.updated', '2026-06-30.basil', '2026-08-28T12:01:00Z',
  repeat('b', 64),
  '{"objectType":"subscription","objectId":"sub_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","priceId":"price_wave7b_test_month","subscriptionStatus":"active","billingInterval":"month","currentPeriodStart":"2026-08-28T12:01:00Z","currentPeriodEnd":"2026-09-28T12:01:00Z","cancelAtPeriodEnd":false}',
  'req-wave7b-subscription'
);
update wave7b_state state set subscription_id = subscriptions.id
from private.pachanga_stripe_subscription_projections_v1 subscriptions
where subscriptions.billing_account_id = state.billing_account_id;
select pg_temp.assert_true(
  (select count(*) = 1 from private.pachanga_organizer_access_grants_v1 access
    where access.billing_account_id = (select billing_account_id from wave7b_state)
      and access.status = 'active')
  and (select count(*) = 20 from public.pachanga_competition_entitlement_grants grants
    where grants.billing_subscription_projection_id = (select subscription_id from wave7b_state)
      and grants.status = 'active'),
  'Signed active subscription must project one access bundle and its capabilities'
);

select pg_temp.assert_true(
  (public.ingest_pachanga_stripe_event_v1(
    '7b200000-0000-4000-8000-000000000012', 'test', 'evt_wave7b_subscription_001',
    'customer.subscription.updated', '2026-06-30.basil', '2026-08-28T12:01:00Z',
    repeat('b', 64),
    '{"objectType":"subscription","objectId":"sub_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","priceId":"price_wave7b_test_month","subscriptionStatus":"active","billingInterval":"month","currentPeriodStart":"2026-08-28T12:01:00Z","currentPeriodEnd":"2026-09-28T12:01:00Z","cancelAtPeriodEnd":false}',
    'req-wave7b-subscription-duplicate'
  ) ->> 'duplicate')::boolean,
  'Duplicate Stripe event must be acknowledged without double application'
);
select pg_temp.assert_true(
  (select count(*) = 1 from private.pachanga_stripe_subscription_projections_v1),
  'Duplicate Stripe event must not create a second projection'
);

-- Stable event identity breaks timestamp ties deterministically.
select public.ingest_pachanga_stripe_event_v1(
  '7b200000-0000-4000-8000-000000000013', 'test', 'evt_wave7b_same_time_z',
  'customer.subscription.updated', '2026-06-30.basil', '2026-08-28T12:02:00Z',
  repeat('c', 64),
  '{"objectType":"subscription","objectId":"sub_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","priceId":"price_wave7b_test_month","subscriptionStatus":"past_due","billingInterval":"month","currentPeriodStart":"2026-08-28T12:01:00Z","currentPeriodEnd":"2026-09-28T12:01:00Z","cancelAtPeriodEnd":false}',
  'req-wave7b-same-time-z'
);
select public.ingest_pachanga_stripe_event_v1(
  '7b200000-0000-4000-8000-000000000014', 'test', 'evt_wave7b_same_time_a',
  'customer.subscription.updated', '2026-06-30.basil', '2026-08-28T12:02:00Z',
  repeat('d', 64),
  '{"objectType":"subscription","objectId":"sub_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","priceId":"price_wave7b_test_month","subscriptionStatus":"active","billingInterval":"month","currentPeriodStart":"2026-08-28T12:01:00Z","currentPeriodEnd":"2026-09-28T12:01:00Z","cancelAtPeriodEnd":false}',
  'req-wave7b-same-time-a'
);
select pg_temp.assert_true(
  (select status = 'past_due' and last_event_id = 'evt_wave7b_same_time_z'
    from private.pachanga_stripe_subscription_projections_v1
    where id = (select subscription_id from wave7b_state)),
  'Same-timestamp events must converge using the stable Stripe event id tie-breaker'
);

-- Unknown Price enters reconciliation; arbitrary normalized keys are rejected.
select pg_temp.assert_true(
  public.ingest_pachanga_stripe_event_v1(
    '7b200000-0000-4000-8000-000000000015', 'test', 'evt_wave7b_unknown_price',
    'customer.subscription.updated', '2026-06-30.basil', '2026-08-28T12:03:00Z',
    repeat('e', 64),
    '{"objectType":"subscription","objectId":"sub_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","priceId":"price_not_allowlisted","subscriptionStatus":"active"}',
    'req-wave7b-unknown-price'
  ) ->> 'status' = 'RECONCILIATION_REQUIRED',
  'Unknown Stripe Price must fail closed into reconciliation'
);
select pg_temp.expect_failure(
  $$select public.ingest_pachanga_stripe_event_v1(
    '7b200000-0000-4000-8000-000000000016', 'test', 'evt_wave7b_bad_payload',
    'customer.updated', '2026-06-30.basil', '2026-08-28T12:04:00Z', repeat('f', 64),
    '{"objectType":"customer","objectId":"cus_wave7b_001","customerId":"cus_wave7b_001","cardNumber":"4242424242424242"}',
    'req-wave7b-bad-payload'
  )$$,
  'BILLING_NORMALIZED_PAYLOAD_KEY_REJECTED'
);

-- Invoice failures are projected, deduplicated and recoverable.
select public.ingest_pachanga_stripe_event_v1(
  '7b200000-0000-4000-8000-000000000017', 'test', 'evt_wave7b_invoice_failed',
  'invoice.payment_failed', '2026-06-30.basil', '2026-08-28T12:05:00Z',
  repeat('1', 64),
  '{"objectType":"invoice","objectId":"in_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","subscriptionStatus":"past_due","invoiceId":"in_wave7b_001","invoiceStatus":"open","currency":"eur","amountDue":"1299","amountPaid":"0","failureCode":"card_declined"}',
  'req-wave7b-invoice-failed'
);
select public.ingest_pachanga_stripe_event_v1(
  '7b200000-0000-4000-8000-000000000018', 'test', 'evt_wave7b_invoice_paid',
  'invoice.paid', '2026-06-30.basil', '2026-08-28T12:06:00Z',
  repeat('2', 64),
  '{"objectType":"invoice","objectId":"in_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","subscriptionStatus":"active","invoiceId":"in_wave7b_001","invoiceStatus":"paid","currency":"eur","amountDue":"1299","amountPaid":"1299","paidAt":"2026-08-28T12:06:00Z"}',
  'req-wave7b-invoice-paid'
);
select pg_temp.assert_true(
  (select count(*) = 1 and bool_and(status = 'RECOVERED')
    from private.pachanga_stripe_payment_failures_v1),
  'Paid invoice must recover the unique failure projection'
);

-- Activate an edition while subscribed, then cancel. Existing edition gets continuity;
-- future competition and edition creation remains blocked.
insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, competition_type,
  visibility, status, created_by
) values (
  '7b300000-0000-4000-8000-000000000001', 'TEAM',
  '7b000000-0000-4000-8000-000000000010', 'Wave 7B Existing League',
  'wave-7b-existing-league', 'LEAGUE', 'private', 'draft',
  '7b000000-0000-4000-8000-000000000001'
);
insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status, created_by
) values (
  '7b300000-0000-4000-8000-000000000002',
  '7b300000-0000-4000-8000-000000000001',
  'Wave 7B Active Edition', '2026-27', '2026-08-01', '2026-12-31', 'active',
  '7b000000-0000-4000-8000-000000000001'
);
update wave7b_state state set continuity_id = continuity.id
from private.pachanga_competition_billing_continuity_grants_v1 continuity
where continuity.edition_id = '7b300000-0000-4000-8000-000000000002';
select pg_temp.assert_true(
  (select continuity_id is not null from wave7b_state),
  'Edition activation must capture an immutable continuity snapshot'
);

select public.ingest_pachanga_stripe_event_v1(
  '7b200000-0000-4000-8000-000000000019', 'test', 'evt_wave7b_subscription_canceled',
  'customer.subscription.deleted', '2026-06-30.basil', '2026-08-28T12:07:00Z',
  repeat('3', 64),
  '{"objectType":"subscription","objectId":"sub_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","priceId":"price_wave7b_test_month","subscriptionStatus":"canceled","billingInterval":"month","currentPeriodStart":"2026-07-01T00:00:00Z","currentPeriodEnd":"2026-08-01T00:00:00Z","cancelAtPeriodEnd":false,"canceledAt":"2026-08-28T12:07:00Z"}',
  'req-wave7b-subscription-canceled'
);
select pg_temp.assert_true(
  (select status = 'continuity' from private.pachanga_organizer_access_grants_v1
    where subscription_projection_id = (select subscription_id from wave7b_state))
  and not exists (
    select 1 from public.pachanga_competition_entitlement_grants grants
    where grants.billing_subscription_projection_id = (select subscription_id from wave7b_state)
      and grants.capability in ('competition_create', 'tournament_create')
      and grants.status = 'active'
  )
  and exists (
    select 1 from public.pachanga_competition_entitlement_grants grants
    where grants.billing_subscription_projection_id = (select subscription_id from wave7b_state)
      and grants.capability = 'competition_manage' and grants.status = 'active'
  ),
  'Continuity must preserve management of the existing edition but revoke new creation'
);
select pg_temp.expect_failure(
  $$insert into public.pachanga_competitions(
    organizer_kind, organizer_group_id, name, slug, competition_type, created_by
  ) values (
    'TEAM', '7b000000-0000-4000-8000-000000000010', 'Blocked League',
    'wave-7b-blocked-league', 'LEAGUE', '7b000000-0000-4000-8000-000000000001'
  )$$,
  'ORGANIZER_PLAN_CREATION_BLOCKED'
);
select pg_temp.expect_failure(
  $$insert into public.pachanga_competition_editions(
    competition_id, name, season_label, status, created_by
  ) values (
    '7b300000-0000-4000-8000-000000000001', 'Blocked Future Edition',
    '2027-28', 'draft', '7b000000-0000-4000-8000-000000000001'
  )$$,
  'ORGANIZER_PLAN_CREATION_BLOCKED'
);
reset role;

-- Ownership transfer preserves the organizer billing account and moves owner access.
update public.pachanga_groups
set owner_id = '7b000000-0000-4000-8000-000000000005'
where id = '7b000000-0000-4000-8000-000000000010';
update public.pachanga_group_members set role = 'player'
where group_id = '7b000000-0000-4000-8000-000000000010'
  and user_id = '7b000000-0000-4000-8000-000000000001';
update public.pachanga_group_members set role = 'owner'
where group_id = '7b000000-0000-4000-8000-000000000010'
  and user_id = '7b000000-0000-4000-8000-000000000005';

set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000001');
select pg_temp.expect_failure(
  $$select public.get_my_pachanga_organizer_billing_v1(
    'TEAM', '7b000000-0000-4000-8000-000000000010'
  )$$,
  'BILLING_OWNER_REQUIRED'
);
select pg_temp.actor('7b000000-0000-4000-8000-000000000005');
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_organizer_billing_v1(
    'TEAM', '7b000000-0000-4000-8000-000000000010'
  ) -> 'accounts') = 1,
  'New team owner must inherit access to the unchanged billing account'
);
reset role;

-- Platform read model redacts Stripe identifiers and exposes no full payload.
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select pg_temp.assert_true(
  public.get_pachanga_platform_organizer_billing_v2(50, 0)::text not like '%cus_wave7b_001%'
    and public.get_pachanga_platform_organizer_billing_v2(50, 0)::text not like '%price_wave7b_test_month%',
  'Platform read model must redact full Stripe identifiers'
);
reset role;

-- Direct legacy billing writes by an authenticated client remain blocked.
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000005');
select pg_temp.expect_failure(
  $$update public.pachanga_groups
    set stripe_customer_id = 'cus_forged_client'
    where id = '7b000000-0000-4000-8000-000000000010'$$,
  'permission denied'
);
reset role;

-- Reconciliation is claimed once and completes with expected revision.
update wave7b_state state set account_revision = accounts.revision
from private.pachanga_organizer_billing_accounts accounts
where accounts.id = state.billing_account_id;
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.request_pachanga_billing_reconciliation_platform_v1(
  '7b400000-0000-4000-8000-000000000010',
  (select billing_account_id from wave7b_state),
  (select account_revision from wave7b_state),
  'Verify the canceled projection against Stripe',
  '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
);
reset role;

set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
select pg_temp.assert_true(
  jsonb_array_length(public.claim_pachanga_billing_reconciliation_service_v1(
    '7b400000-0000-4000-8000-000000000001', 25
  ) -> 'items') >= 1,
  'Unknown Price must produce a claimable reconciliation item'
);
select pg_temp.assert_true(
  (public.claim_pachanga_billing_reconciliation_service_v1(
    '7b400000-0000-4000-8000-000000000001', 25
  ) ->> 'replayed')::boolean,
  'Reconciliation claim must replay exactly'
);
select pg_temp.assert_true(
  (public.apply_pachanga_billing_reconciliation_snapshot_service_v1(
    '7b400000-0000-4000-8000-000000000011',
    (select id from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000010'),
    (select revision from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000010'),
    '2026-08-28T12:08:00Z', 'cus_wave7b_001', 'sub_wave7b_001',
    'price_wave7b_test_month', 'active', 'month',
    '2026-08-28T12:01:00Z', '2026-09-28T12:01:00Z', false, null,
    array['STATUS_MISMATCH'],
    (select revision from private.pachanga_stripe_subscription_projections_v1
      where id = (select subscription_id from wave7b_state))
  ) ->> 'applied')::boolean,
  'A newer server-side Stripe snapshot must repair the canonical projection'
);
select pg_temp.assert_true(
  (select status = 'active' and projection_source = 'STRIPE_RECONCILIATION'
      and last_event_id like 'evt_reconcile_%'
    from private.pachanga_stripe_subscription_projections_v1
    where id = (select subscription_id from wave7b_state))
  and not exists (
    select 1 from private.pachanga_stripe_webhook_events_v2 events
    where events.stripe_event_id like 'evt_reconcile_%'
  ),
  'Reconciliation must be auditable without fabricating a signed webhook event'
);
select pg_temp.assert_true(
  (public.apply_pachanga_billing_reconciliation_snapshot_service_v1(
    '7b400000-0000-4000-8000-000000000011',
    (select id from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000010'),
    (select revision - 1 from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000010'),
    '2026-08-28T12:08:00Z', 'cus_wave7b_001', 'sub_wave7b_001',
    'price_wave7b_test_month', 'active', 'month',
    '2026-08-28T12:01:00Z', '2026-09-28T12:01:00Z', false, null,
    array['STATUS_MISMATCH'],
    (select revision - 1 from private.pachanga_stripe_subscription_projections_v1
      where id = (select subscription_id from wave7b_state))
  ) ->> 'replayed')::boolean,
  'Applied reconciliation snapshots must replay without a second entitlement mutation'
);
reset role;

update wave7b_state state set account_revision = accounts.revision
from private.pachanga_organizer_billing_accounts accounts
where accounts.id = state.billing_account_id;
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.request_pachanga_billing_reconciliation_platform_v1(
  '7b400000-0000-4000-8000-000000000020',
  (select billing_account_id from wave7b_state),
  (select account_revision from wave7b_state),
  'Prove that a stale Stripe observation cannot beat newer authority',
  '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
);
reset role;
set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
select public.claim_pachanga_billing_reconciliation_service_v1(
  '7b400000-0000-4000-8000-000000000021', 25
);
select pg_temp.assert_true(
  not (public.apply_pachanga_billing_reconciliation_snapshot_service_v1(
    '7b400000-0000-4000-8000-000000000022',
    (select id from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000020'),
    (select revision from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000020'),
    '2026-08-28T12:07:30Z', 'cus_wave7b_001', 'sub_wave7b_001',
    'price_wave7b_test_month', 'canceled', 'month',
    '2026-07-01T00:00:00Z', '2026-08-01T00:00:00Z', false,
    '2026-08-28T12:07:00Z', array['STATUS_MISMATCH'],
    (select revision from private.pachanga_stripe_subscription_projections_v1
      where id = (select subscription_id from wave7b_state))
  ) ->> 'applied')::boolean
  and (select status = 'active' and last_event_created_at = '2026-08-28T12:08:00Z'
    from private.pachanga_stripe_subscription_projections_v1
    where id = (select subscription_id from wave7b_state)),
  'An older reconciliation snapshot must never overwrite the newer canonical projection'
);
reset role;

update wave7b_state state set
  account_revision = accounts.revision,
  subscription_revision = subscriptions.revision
from private.pachanga_organizer_billing_accounts accounts,
  private.pachanga_stripe_subscription_projections_v1 subscriptions
where accounts.id = state.billing_account_id
  and subscriptions.id = state.subscription_id;
set local role authenticated;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003');
select public.request_pachanga_billing_reconciliation_platform_v1(
  '7b400000-0000-4000-8000-000000000030',
  (select billing_account_id from wave7b_state),
  (select account_revision from wave7b_state),
  'Prove projection revision protects a concurrent webhook',
  '{"clientVersion":"7.1.0+db","surface":"wave7b_control_center"}'
);
reset role;
set local role service_role;
select pg_temp.actor('7b000000-0000-4000-8000-000000000003', 'service_role');
select public.claim_pachanga_billing_reconciliation_service_v1(
  '7b400000-0000-4000-8000-000000000031', 25
);
select public.ingest_pachanga_stripe_event_v1(
  '7b400000-0000-4000-8000-000000000032', 'test', 'evt_wave7b_reconciliation_race',
  'customer.subscription.updated', '2026-06-30.basil', '2026-08-28T12:09:00Z',
  repeat('4', 64),
  '{"objectType":"subscription","objectId":"sub_wave7b_001","customerId":"cus_wave7b_001","subscriptionId":"sub_wave7b_001","priceId":"price_wave7b_test_month","subscriptionStatus":"past_due","billingInterval":"month","currentPeriodStart":"2026-08-28T12:01:00Z","currentPeriodEnd":"2026-09-28T12:01:00Z","cancelAtPeriodEnd":false}',
  'req-wave7b-reconciliation-race'
);
select pg_temp.expect_failure(
  $$select public.apply_pachanga_billing_reconciliation_snapshot_service_v1(
    '7b400000-0000-4000-8000-000000000033',
    (select id from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000030'),
    (select revision from private.pachanga_stripe_billing_reconciliations_v1
      where operation_id = '7b400000-0000-4000-8000-000000000030'),
    '2026-08-28T12:10:00Z', 'cus_wave7b_001', 'sub_wave7b_001',
    'price_wave7b_test_month', 'active', 'month',
    '2026-08-28T12:01:00Z', '2026-09-28T12:01:00Z', false, null,
    array['STATUS_MISMATCH'], (select subscription_revision from wave7b_state)
  )$$,
  'STALE_REVISION'
);
select pg_temp.assert_true(
  (select status = 'past_due' and last_event_id = 'evt_wave7b_reconciliation_race'
    from private.pachanga_stripe_subscription_projections_v1
    where id = (select subscription_id from wave7b_state)),
  'A webhook processed after claim must remain the canonical projection'
);
select public.complete_pachanga_billing_reconciliation_service_v1(
  '7b400000-0000-4000-8000-000000000034',
  (select id from private.pachanga_stripe_billing_reconciliations_v1
    where operation_id = '7b400000-0000-4000-8000-000000000030'),
  (select revision from private.pachanga_stripe_billing_reconciliations_v1
    where operation_id = '7b400000-0000-4000-8000-000000000030'),
  'FAILED', array['PROJECTION_CHANGED_AFTER_CLAIM'], 'STALE_REVISION'
);
reset role;

select pg_temp.assert_true(
  not exists (
    select 1 from private.pachanga_organizer_billing_operation_receipts_v1 receipts
    where receipts.client_metadata ? 'secret'
  ),
  'Client metadata allowlist must discard secret-looking fields'
);
select pg_temp.assert_true(
  (select count(*) >= 1 from public.pachanga_organizer_billing_invalidations_v1),
  'Canonical writes must emit invalidations for Realtime refetch'
);

select 'ORGANIZER_PLANS_STRIPE_BILLING_V1_DB_OK';
