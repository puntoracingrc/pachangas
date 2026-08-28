-- Wave 7C: reduced public/owner reads and a mode-separated Control Center model.

set lock_timeout = '5s';
set statement_timeout = '5min';

alter function public.get_pachanga_organizer_plan_catalog_v1()
  rename to get_pachanga_organizer_plan_catalog_wave7b_legacy;

create or replace function public.get_pachanga_organizer_plan_catalog_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare base jsonb;
declare plans jsonb;
begin
  base := public.get_pachanga_organizer_plan_catalog_wave7b_legacy();
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if base ->> 'status' = 'NOT_AVAILABLE' then
    return base || jsonb_build_object(
      'pricingEnabled', false,
      'liveCheckoutEnabled', false
    );
  end if;
  select coalesce(jsonb_agg(rows.item order by rows.plan_code), '[]'::jsonb)
    into plans
  from (
    select plan_entry.value ->> 'planCode' plan_code,
      (plan_entry.value - 'checkoutAvailable' - 'pricingStatus' - 'prices')
      || jsonb_build_object(
        'checkoutAvailable',
          coalesce((plan_entry.value ->> 'requiresStripe')::boolean, false)
          and settings.organizer_pricing_ui_enabled and settings.live_checkout_enabled
          and exists (
            select 1
            from private.pachanga_organizer_plan_price_mappings mappings
            join public.pachanga_organizer_plan_revisions revisions on revisions.id = mappings.plan_revision_id
            join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id
            join private.pachanga_organizer_commercial_decisions_v1 decisions
              on decisions.id = mappings.commercial_decision_id
            where catalog.plan_code = plan_entry.value ->> 'planCode'
              and mappings.stripe_mode = 'live' and mappings.active and mappings.approved
              and decisions.status = 'published'
          ),
        'pricingStatus', case
          when plan_entry.value ->> 'accessModel' = 'PARTNERSHIP' then 'PARTNERSHIP_REVIEW'
          when not coalesce((plan_entry.value ->> 'requiresStripe')::boolean, false) then 'NOT_APPLICABLE'
          when settings.organizer_pricing_ui_enabled and exists (
            select 1
            from private.pachanga_organizer_plan_price_mappings mappings
            join public.pachanga_organizer_plan_revisions revisions on revisions.id = mappings.plan_revision_id
            join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id
            join private.pachanga_organizer_commercial_decisions_v1 decisions
              on decisions.id = mappings.commercial_decision_id
            where catalog.plan_code = plan_entry.value ->> 'planCode'
              and mappings.stripe_mode = 'live' and mappings.active and mappings.approved
              and decisions.status = 'published'
          ) then 'APPROVED'
          else 'AWAITING_PRICE_APPROVAL'
        end,
        'prices', case when settings.organizer_pricing_ui_enabled then coalesce((
          select jsonb_agg(jsonb_build_object(
            'interval', mappings.billing_interval,
            'currency', mappings.currency,
            'unitAmount', mappings.unit_amount,
            'taxBehavior', mappings.tax_behavior,
            'taxDisplayMode', decisions.tax_display_mode,
            'effectiveFrom', decisions.effective_from
          ) order by mappings.billing_interval)
          from private.pachanga_organizer_plan_price_mappings mappings
          join public.pachanga_organizer_plan_revisions revisions on revisions.id = mappings.plan_revision_id
          join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id
          join private.pachanga_organizer_commercial_decisions_v1 decisions
            on decisions.id = mappings.commercial_decision_id
          where catalog.plan_code = plan_entry.value ->> 'planCode'
            and mappings.stripe_mode = 'live' and mappings.active and mappings.approved
            and decisions.status = 'published'
        ), '[]'::jsonb) else '[]'::jsonb end
      ) item
    from jsonb_array_elements(coalesce(base -> 'plans', '[]'::jsonb)) plan_entry(value)
  ) rows;
  return (base - 'plans' - 'status' - 'liveCheckoutEnabled') || jsonb_build_object(
    'status', case when settings.live_checkout_enabled then 'LIVE_CHECKOUT_AVAILABLE'
      else 'CATALOG_AVAILABLE' end,
    'pricingEnabled', settings.organizer_pricing_ui_enabled,
    'liveCheckoutEnabled', settings.live_checkout_enabled,
    'plans', plans, 'revision', settings.revision, 'updatedAt', settings.updated_at
  );
end;
$$;

alter function public.get_my_pachanga_organizer_billing_v1(text, uuid)
  rename to get_my_pachanga_organizer_billing_wave7b_legacy;

create or replace function public.get_my_pachanga_organizer_billing_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare base jsonb;
begin
  base := public.get_my_pachanga_organizer_billing_wave7b_legacy(
    target_organizer_kind, target_organizer_id
  );
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  return jsonb_set(base, '{availability}',
    coalesce(base -> 'availability', '{}'::jsonb) || jsonb_build_object(
      'pricingUi', settings.organizer_pricing_ui_enabled,
      'liveCheckout', settings.live_checkout_enabled,
      'sandboxCheckout', settings.stripe_test_checkout_enabled,
      'livePortal', settings.portal_enabled and settings.live_checkout_enabled,
      'sandboxPortal', settings.stripe_test_portal_enabled,
      'portal', (settings.portal_enabled and settings.live_checkout_enabled)
        or settings.stripe_test_portal_enabled,
      'taxHealth', settings.tax_health
    ), true
  ) || jsonb_build_object('revision', settings.revision, 'updatedAt', settings.updated_at);
end;
$$;

alter function public.get_pachanga_platform_organizer_billing_v2(integer, integer)
  rename to get_pachanga_platform_organizer_billing_wave7b_legacy;

create or replace function public.get_pachanga_platform_organizer_billing_v2(
  page_size integer default 50,
  page_offset integer default 0
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare base jsonb;
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare health_test private.pachanga_organizer_stripe_runtime_health_v1%rowtype;
declare health_live private.pachanga_organizer_stripe_runtime_health_v1%rowtype;
declare decisions jsonb;
declare mappings jsonb;
begin
  base := public.get_pachanga_platform_organizer_billing_wave7b_legacy(page_size, page_offset);
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  select * into health_test from private.pachanga_organizer_stripe_runtime_health_v1 where stripe_mode = 'test';
  select * into health_live from private.pachanga_organizer_stripe_runtime_health_v1 where stripe_mode = 'live';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rows.id, 'planCode', rows.plan_code, 'organizerKind', rows.organizer_kind,
    'currency', rows.currency, 'monthlyAmountMinor', rows.monthly_amount_minor,
    'annualAmountMinor', rows.annual_amount_minor, 'taxDisplayMode', rows.tax_display_mode,
    'stripeTaxBehavior', rows.stripe_tax_behavior, 'trialDays', rows.trial_days,
    'effectiveFrom', rows.effective_from, 'publicCopyRevision', rows.public_copy_revision,
    'termsRevision', rows.terms_revision, 'privacyRevision', rows.privacy_revision,
    'decisionKind', rows.decision_kind, 'status', rows.status,
    'approvedAt', rows.approved_at, 'publishedAt', rows.published_at,
    'supersedesId', rows.supersedes_id, 'revision', rows.revision,
    'serverSequence', rows.server_sequence, 'updatedAt', rows.updated_at
  ) order by rows.plan_code, rows.revision desc, rows.id desc), '[]'::jsonb)
  into decisions from private.pachanga_organizer_commercial_decisions_v1 rows;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', price.id, 'planCode', catalog.plan_code, 'mode', price.stripe_mode,
    'interval', price.billing_interval,
    'product', private.pachanga_billing_redact_stripe_id_v1(price.stripe_product_id),
    'price', private.pachanga_billing_redact_stripe_id_v1(price.stripe_price_id),
    'currency', price.currency, 'unitAmount', price.unit_amount,
    'taxBehavior', price.tax_behavior, 'approved', price.approved, 'active', price.active,
    'decisionId', price.commercial_decision_id, 'catalogRevision', price.catalog_revision,
    'authorityStatus', case when price.commercial_decision_id is null
      then 'LEGACY_UNMAPPED' else 'COMMERCIAL_DECISION_LINKED' end,
    'revision', price.revision, 'serverSequence', price.server_sequence,
    'updatedAt', price.updated_at
  ) order by price.stripe_mode, catalog.plan_code, price.billing_interval), '[]'::jsonb)
  into mappings
  from private.pachanga_organizer_plan_price_mappings price
  join public.pachanga_organizer_plan_revisions revisions on revisions.id = price.plan_revision_id
  join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id;

  return (base - 'settings' - 'priceMappings') || jsonb_build_object(
    'settings', coalesce(base -> 'settings', '{}'::jsonb) || jsonb_build_object(
      'commercialDecisionWorkflowEnabled', settings.commercial_decision_workflow_enabled,
      'organizerPricingUiEnabled', settings.organizer_pricing_ui_enabled,
      'stripeTestCheckoutEnabled', settings.stripe_test_checkout_enabled,
      'stripeTestPortalEnabled', settings.stripe_test_portal_enabled,
      'stripeTestWebhookReady', settings.stripe_test_webhook_ready,
      'stripeTestPortalReady', settings.stripe_test_portal_ready,
      'stripeLiveWebhookReady', settings.stripe_live_webhook_ready,
      'stripeLivePortalReady', settings.stripe_live_portal_ready,
      'demoWorldV29Enabled', settings.demo_world_v29_enabled,
      'organizerTermsRevision', settings.organizer_terms_revision,
      'organizerPrivacyRevision', settings.organizer_privacy_revision,
      'taxHealth', settings.tax_health, 'revision', settings.revision,
      'serverSequence', settings.server_sequence, 'updatedAt', settings.updated_at
    ),
    'commercialDecisions', decisions,
    'priceMappings', mappings,
    'runtimeHealth', jsonb_build_array(
      jsonb_build_object('mode', 'test', 'productCount', health_test.product_count,
        'priceCount', health_test.price_count, 'catalogReady', health_test.catalog_ready,
        'webhookDestinationReady', health_test.webhook_destination_ready,
        'webhookSigningReady', health_test.webhook_signing_ready,
        'portalReady', health_test.portal_ready, 'checkoutApiReady', health_test.checkout_api_ready,
        'destinationPath', health_test.destination_path, 'safeErrorCode', health_test.safe_error_code,
        'sourceRevision', health_test.source_revision, 'revision', health_test.revision,
        'serverSequence', health_test.server_sequence, 'verifiedAt', health_test.verified_at),
      jsonb_build_object('mode', 'live', 'productCount', health_live.product_count,
        'priceCount', health_live.price_count, 'catalogReady', health_live.catalog_ready,
        'webhookDestinationReady', health_live.webhook_destination_ready,
        'webhookSigningReady', health_live.webhook_signing_ready,
        'portalReady', health_live.portal_ready, 'checkoutApiReady', health_live.checkout_api_ready,
        'destinationPath', health_live.destination_path, 'safeErrorCode', health_live.safe_error_code,
        'sourceRevision', health_live.source_revision, 'revision', health_live.revision,
        'serverSequence', health_live.server_sequence, 'verifiedAt', health_live.verified_at)
    ),
    'activationChecklist', jsonb_build_object(
      'commercialWorkflow', settings.commercial_decision_workflow_enabled,
      'paidDecisionsApproved', (select count(*) = 2
        from private.pachanga_organizer_commercial_decisions_v1 rows
        where rows.plan_code in ('TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER')
          and rows.status in ('approved', 'published')),
      'paidDecisionsPublished', (select count(*) = 2
        from private.pachanga_organizer_commercial_decisions_v1 rows
        where rows.plan_code in ('TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER')
          and rows.status = 'published'),
      'taxReady', settings.tax_health = 'LIVE_READY',
      'testCatalogReady', health_test.catalog_ready,
      'testCheckoutReady', health_test.checkout_api_ready
        and health_test.webhook_destination_ready and health_test.webhook_signing_ready,
      'testPortalReady', health_test.portal_ready,
      'liveCatalogReady', health_live.catalog_ready,
      'liveCheckoutReady', health_live.checkout_api_ready
        and health_live.webhook_destination_ready and health_live.webhook_signing_ready,
      'livePortalReady', health_live.portal_ready,
      'liveActivated', settings.live_checkout_enabled and settings.live_prices_approved
    )
  );
end;
$$;

revoke all on function public.get_pachanga_organizer_plan_catalog_wave7b_legacy() from public, anon, authenticated, service_role;
revoke all on function public.get_my_pachanga_organizer_billing_wave7b_legacy(text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.get_pachanga_platform_organizer_billing_wave7b_legacy(integer, integer) from public, anon, authenticated, service_role;

revoke all on function public.get_pachanga_organizer_plan_catalog_v1() from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_organizer_plan_catalog_v1() to anon, authenticated, service_role;
revoke all on function public.get_my_pachanga_organizer_billing_v1(text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_organizer_billing_v1(text, uuid) to authenticated, service_role;
revoke all on function public.get_pachanga_platform_organizer_billing_v2(integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_organizer_billing_v2(integer, integer) to authenticated, service_role;
