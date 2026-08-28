-- Wave 7B: canonical organizer and platform billing read models.

set lock_timeout = '5s';
set statement_timeout = '5min';

alter table private.pachanga_stripe_billing_reconciliations_v1
  add column if not exists claim_operation_id uuid,
  add column if not exists last_attempt_at timestamptz;

alter table private.pachanga_stripe_subscription_projections_v1
  add column if not exists projection_source text not null default 'STRIPE_WEBHOOK',
  add column if not exists last_reconciled_at timestamptz;

alter table private.pachanga_stripe_subscription_projections_v1
  drop constraint if exists pachanga_stripe_subscription_projection_source_ck;
alter table private.pachanga_stripe_subscription_projections_v1
  add constraint pachanga_stripe_subscription_projection_source_ck
  check (projection_source in ('STRIPE_WEBHOOK', 'STRIPE_RECONCILIATION'));

create index if not exists pachanga_stripe_reconciliation_claim_idx
  on private.pachanga_stripe_billing_reconciliations_v1(claim_operation_id, server_sequence, id)
  where claim_operation_id is not null;

create or replace function private.pachanga_billing_redact_stripe_id_v1(source text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when source is null then null
    when length(source) <= 10 then left(source, 3) || '...'
    else left(source, greatest(strpos(source, '_'), 3)) || '...' || right(source, 6)
  end;
$$;

create or replace function public.get_pachanga_organizer_plan_catalog_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare plans jsonb;
begin
  select * into settings
  from private.pachanga_organizer_billing_settings
  where singleton;

  if not settings.foundation_enabled or not settings.plan_catalog_enabled then
    return jsonb_build_object(
      'enabled', false,
      'status', 'NOT_AVAILABLE',
      'plans', '[]'::jsonb,
      'revision', settings.revision,
      'updatedAt', settings.updated_at
    );
  end if;

  select coalesce(jsonb_agg(plan_rows.item order by plan_rows.plan_code), '[]'::jsonb)
    into plans
  from (
    select catalog.plan_code, jsonb_build_object(
      'planCode', catalog.plan_code,
      'organizerKind', catalog.organizer_kind,
      'accessModel', catalog.access_model,
      'displayName', revisions.display_name,
      'summary', revisions.summary,
      'requiresStripe', catalog.requires_stripe,
      'checkoutAvailable', catalog.requires_stripe and settings.live_checkout_enabled
        and exists (
          select 1
          from private.pachanga_organizer_plan_price_mappings mappings
          where mappings.plan_revision_id = revisions.id
            and mappings.stripe_mode = 'live'
            and mappings.active and mappings.approved
        ),
      'pricingStatus', case
        when catalog.access_model = 'PARTNERSHIP' then 'PARTNERSHIP_REVIEW'
        when not catalog.requires_stripe then 'NOT_APPLICABLE'
        when exists (
          select 1
          from private.pachanga_organizer_plan_price_mappings mappings
          where mappings.plan_revision_id = revisions.id
            and mappings.stripe_mode = 'live'
            and mappings.active and mappings.approved
        ) then 'APPROVED'
        else 'AWAITING_PRICE_APPROVAL'
      end,
      'prices', coalesce((
        select jsonb_agg(jsonb_build_object(
          'interval', mappings.billing_interval,
          'currency', mappings.currency,
          'unitAmount', mappings.unit_amount,
          'taxBehavior', mappings.tax_behavior
        ) order by mappings.billing_interval)
        from private.pachanga_organizer_plan_price_mappings mappings
        where mappings.plan_revision_id = revisions.id
          and mappings.stripe_mode = 'live'
          and mappings.active and mappings.approved
      ), '[]'::jsonb),
      'features', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', features.feature_key,
          'enabled', features.enabled
        ) order by features.display_order, features.feature_key)
        from public.pachanga_organizer_plan_features features
        where features.plan_revision_id = revisions.id
      ), '[]'::jsonb),
      'limits', coalesce((
        select jsonb_agg(jsonb_build_object(
          'key', limits.limit_key,
          'value', limits.limit_value,
          'unit', limits.unit,
          'status', case when limits.limit_value is null then 'PENDING_APPROVAL' else 'ACTIVE' end
        ) order by limits.display_order, limits.limit_key)
        from public.pachanga_organizer_plan_limits limits
        where limits.plan_revision_id = revisions.id
      ), '[]'::jsonb),
      'revision', revisions.revision,
      'updatedAt', revisions.updated_at
    ) item
    from public.pachanga_organizer_plan_catalog catalog
    join lateral (
      select rows.*
      from public.pachanga_organizer_plan_revisions rows
      where rows.plan_id = catalog.id
        and rows.status = 'active'
        and rows.effective_from <= clock_timestamp()
        and (rows.effective_until is null or rows.effective_until > clock_timestamp())
      order by rows.version desc, rows.id desc
      limit 1
    ) revisions on true
    where catalog.public_available and catalog.status = 'active'
  ) plan_rows;

  return jsonb_build_object(
    'enabled', true,
    'status', case when settings.live_checkout_enabled then 'LIVE_CHECKOUT_AVAILABLE'
      else 'CATALOG_AVAILABLE' end,
    'liveCheckoutEnabled', settings.live_checkout_enabled,
    'plans', plans,
    'revision', settings.revision,
    'updatedAt', settings.updated_at
  );
end;
$$;

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
declare actor_id uuid := (select auth.uid());
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare organizer_name text;
declare accounts jsonb;
declare accesses jsonb;
declare invoices jsonb;
declare continuity jsonb;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if normalized_kind not in ('TEAM', 'CLUB') or target_organizer_id is null then
    raise exception 'BILLING_INVALID_ORGANIZER' using errcode = '22023';
  end if;
  if not private.pachanga_billing_owner_can_manage_v1(normalized_kind, target_organizer_id, actor_id) then
    raise exception 'BILLING_OWNER_REQUIRED' using errcode = '42501';
  end if;

  select * into settings
  from private.pachanga_organizer_billing_settings
  where singleton;
  if normalized_kind = 'TEAM' then
    select groups.name into organizer_name
    from public.pachanga_groups groups where groups.id = target_organizer_id;
  else
    select clubs.name into organizer_name
    from public.pachanga_clubs clubs where clubs.id = target_organizer_id;
  end if;

  select coalesce(jsonb_agg(account_rows.item order by account_rows.stripe_mode), '[]'::jsonb)
    into accounts
  from (
    select billing_accounts.stripe_mode, jsonb_build_object(
      'id', billing_accounts.id,
      'mode', billing_accounts.stripe_mode,
      'status', billing_accounts.status,
      'locale', billing_accounts.locale,
      'billingCountry', billing_accounts.billing_country,
      'taxConfigurationStatus', billing_accounts.tax_configuration_status,
      'customerConfigured', billing_accounts.stripe_customer_id is not null,
      'plan', case when subscriptions.id is null then null else jsonb_build_object(
        'code', catalog.plan_code,
        'name', plan_revisions.display_name,
        'status', subscriptions.status,
        'billingInterval', subscriptions.billing_interval,
        'currentPeriodStart', subscriptions.current_period_start,
        'currentPeriodEnd', subscriptions.current_period_end,
        'cancelAtPeriodEnd', subscriptions.cancel_at_period_end,
        'graceEndsAt', subscriptions.grace_ends_at,
        'projectionSource', subscriptions.projection_source,
        'lastReconciledAt', subscriptions.last_reconciled_at,
        'revision', subscriptions.revision
      ) end,
      'revision', billing_accounts.revision,
      'serverSequence', billing_accounts.server_sequence,
      'updatedAt', billing_accounts.updated_at
    ) item
    from private.pachanga_organizer_billing_accounts billing_accounts
    left join lateral (
      select rows.*
      from private.pachanga_stripe_subscription_projections_v1 rows
      where rows.billing_account_id = billing_accounts.id
      order by rows.server_sequence desc, rows.id desc
      limit 1
    ) subscriptions on true
    left join public.pachanga_organizer_plan_revisions plan_revisions
      on plan_revisions.id = subscriptions.plan_revision_id
    left join public.pachanga_organizer_plan_catalog catalog
      on catalog.id = plan_revisions.plan_id
    where billing_accounts.organizer_kind = normalized_kind
      and (
        (normalized_kind = 'TEAM' and billing_accounts.organizer_group_id = target_organizer_id)
        or (normalized_kind = 'CLUB' and billing_accounts.organizer_club_id = target_organizer_id)
      )
  ) account_rows;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', access.id,
      'source', access.access_source,
      'planCode', catalog.plan_code,
      'planName', revisions.display_name,
      'status', access.status,
      'validFrom', access.valid_from,
      'validUntil', access.valid_until,
      'revision', access.revision,
      'serverSequence', access.server_sequence,
      'updatedAt', access.updated_at
    ) order by access.server_sequence desc, access.id desc), '[]'::jsonb)
    into accesses
  from private.pachanga_organizer_access_grants_v1 access
  join public.pachanga_organizer_plan_revisions revisions on revisions.id = access.plan_revision_id
  join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id
  where access.organizer_kind = normalized_kind
    and ((normalized_kind = 'TEAM' and access.organizer_group_id = target_organizer_id)
      or (normalized_kind = 'CLUB' and access.organizer_club_id = target_organizer_id));

  select coalesce(jsonb_agg(invoice_rows.item order by invoice_rows.server_sequence desc, invoice_rows.id desc), '[]'::jsonb)
    into invoices
  from (
    select rows.id, rows.server_sequence, jsonb_build_object(
      'id', rows.id,
      'status', rows.status,
      'currency', rows.currency,
      'amountDue', rows.amount_due,
      'amountPaid', rows.amount_paid,
      'hostedInvoiceUrl', rows.hosted_invoice_url,
      'invoicePdfUrl', rows.invoice_pdf_url,
      'dueAt', rows.due_at,
      'paidAt', rows.paid_at,
      'revision', rows.revision,
      'updatedAt', rows.updated_at
    ) item
    from private.pachanga_stripe_invoice_projections_v1 rows
    join private.pachanga_organizer_billing_accounts billing_accounts
      on billing_accounts.id = rows.billing_account_id
    where billing_accounts.organizer_kind = normalized_kind
      and ((normalized_kind = 'TEAM' and billing_accounts.organizer_group_id = target_organizer_id)
        or (normalized_kind = 'CLUB' and billing_accounts.organizer_club_id = target_organizer_id))
    order by rows.server_sequence desc, rows.id desc
    limit 24
  ) invoice_rows;

  select coalesce(jsonb_agg(jsonb_build_object(
      'editionId', grants.edition_id,
      'competitionId', grants.competition_id,
      'status', grants.status,
      'plannedEnd', grants.edition_planned_end,
      'continuityUntil', grants.continuity_until,
      'revision', grants.revision
    ) order by grants.server_sequence desc, grants.id desc), '[]'::jsonb)
    into continuity
  from private.pachanga_competition_billing_continuity_grants_v1 grants
  where grants.organizer_kind = normalized_kind
    and ((normalized_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
      or (normalized_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id));

  return jsonb_build_object(
    'enabled', settings.organizer_ui_enabled,
    'organizer', jsonb_build_object(
      'kind', normalized_kind,
      'id', target_organizer_id,
      'name', organizer_name
    ),
    'availability', jsonb_build_object(
      'liveCheckout', settings.live_checkout_enabled,
      'sandboxCheckout', settings.stripe_sandbox_enabled,
      'portal', settings.portal_enabled,
      'taxHealth', settings.tax_health
    ),
    'accounts', accounts,
    'accessGrants', accesses,
    'invoices', invoices,
    'continuity', continuity,
    'revision', settings.revision,
    'updatedAt', settings.updated_at
  );
end;
$$;

create or replace function public.get_my_pachanga_billing_organizers_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare organizers jsonb;
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  select coalesce(jsonb_agg(rows.item order by rows.kind, rows.name, rows.id), '[]'::jsonb)
    into organizers
  from (
    select 'TEAM'::text kind, groups.name, groups.id, jsonb_build_object(
      'kind', 'TEAM', 'id', groups.id, 'name', groups.name,
      'owner', true, 'updatedAt', groups.updated_at
    ) item
    from public.pachanga_groups groups
    where groups.owner_id = actor_id
    union all
    select 'CLUB'::text kind, clubs.name, clubs.id, jsonb_build_object(
      'kind', 'CLUB', 'id', clubs.id, 'name', clubs.name,
      'owner', true, 'updatedAt', clubs.updated_at
    ) item
    from public.pachanga_clubs clubs
    where clubs.primary_owner_id = actor_id and clubs.operational_status = 'active'
  ) rows;
  return jsonb_build_object(
    'enabled', settings.organizer_ui_enabled,
    'items', organizers,
    'revision', settings.revision,
    'updatedAt', settings.updated_at
  );
end;
$$;

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
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare safe_limit integer := least(greatest(coalesce(page_size, 50), 1), 100);
declare safe_offset integer := greatest(coalesce(page_offset, 0), 0);
begin
  perform private.pachanga_platform_require_v1('billing.read');
  select * into settings
  from private.pachanga_organizer_billing_settings
  where singleton;

  return jsonb_build_object(
    'settings', jsonb_build_object(
      'foundationEnabled', settings.foundation_enabled,
      'planCatalogEnabled', settings.plan_catalog_enabled,
      'partnerGrantsEnabled', settings.partner_grants_enabled,
      'billingAccountsEnabled', settings.billing_accounts_enabled,
      'organizerUiEnabled', settings.organizer_ui_enabled,
      'webhookIngestEnabled', settings.webhook_ingest_enabled,
      'stripeSandboxEnabled', settings.stripe_sandbox_enabled,
      'portalEnabled', settings.portal_enabled,
      'reconciliationEnabled', settings.reconciliation_enabled,
      'liveCheckoutEnabled', settings.live_checkout_enabled,
      'demoWorldV28Enabled', settings.demo_world_v28_enabled,
      'livePricesApproved', settings.live_prices_approved,
      'taxHealth', settings.tax_health,
      'gracePeriodDays', settings.grace_period_days,
      'continuityMaxDays', settings.continuity_max_days,
      'revision', settings.revision,
      'serverSequence', settings.server_sequence,
      'updatedAt', settings.updated_at
    ),
    'metrics', jsonb_build_object(
      'accounts', (select count(*) from private.pachanga_organizer_billing_accounts),
      'activeSubscriptions', (select count(*) from private.pachanga_stripe_subscription_projections_v1 where status in ('active', 'trialing')),
      'pastDueSubscriptions', (select count(*) from private.pachanga_stripe_subscription_projections_v1 where status in ('past_due', 'unpaid')),
      'activeAccessGrants', (select count(*) from private.pachanga_organizer_access_grants_v1 where status in ('active', 'grace', 'continuity')),
      'openPaymentFailures', (select count(*) from private.pachanga_stripe_payment_failures_v1 where status in ('OPEN', 'ACTION_REQUIRED')),
      'webhookRetryBacklog', (select count(*) from private.pachanga_stripe_webhook_events_v2 where processing_status in ('RECEIVED', 'FAILED_RETRYABLE')),
      'reconciliationBacklog', (select count(*) from private.pachanga_stripe_billing_reconciliations_v1 where status in ('PENDING', 'FAILED')),
      'continuityEditions', (select count(*) from private.pachanga_competition_billing_continuity_grants_v1 where status = 'active')
    ),
    'priceMappings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mappings.id,
        'planCode', catalog.plan_code,
        'mode', mappings.stripe_mode,
        'interval', mappings.billing_interval,
        'product', private.pachanga_billing_redact_stripe_id_v1(mappings.stripe_product_id),
        'price', private.pachanga_billing_redact_stripe_id_v1(mappings.stripe_price_id),
        'currency', mappings.currency,
        'unitAmount', mappings.unit_amount,
        'taxBehavior', mappings.tax_behavior,
        'approved', mappings.approved,
        'active', mappings.active,
        'revision', mappings.revision,
        'updatedAt', mappings.updated_at
      ) order by mappings.stripe_mode, catalog.plan_code, mappings.billing_interval)
      from private.pachanga_organizer_plan_price_mappings mappings
      join public.pachanga_organizer_plan_revisions revisions on revisions.id = mappings.plan_revision_id
      join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id
    ), '[]'::jsonb),
    'accounts', coalesce((
      select jsonb_agg(rows.item order by rows.server_sequence desc, rows.id desc)
      from (
        select accounts.id, accounts.server_sequence, jsonb_build_object(
          'id', accounts.id,
          'organizerKind', accounts.organizer_kind,
          'organizerId', coalesce(accounts.organizer_group_id, accounts.organizer_club_id),
          'organizerName', coalesce(groups.name, clubs.name, 'Organizador'),
          'mode', accounts.stripe_mode,
          'customer', private.pachanga_billing_redact_stripe_id_v1(accounts.stripe_customer_id),
          'billingContactConfigured', accounts.billing_contact_user_id is not null,
          'status', accounts.status,
          'taxConfigurationStatus', accounts.tax_configuration_status,
          'subscription', case when subscriptions.id is null then null else jsonb_build_object(
            'id', subscriptions.id,
            'reference', private.pachanga_billing_redact_stripe_id_v1(subscriptions.stripe_subscription_id),
            'planCode', catalog.plan_code,
            'status', subscriptions.status,
            'interval', subscriptions.billing_interval,
            'currentPeriodEnd', subscriptions.current_period_end,
            'graceEndsAt', subscriptions.grace_ends_at,
            'revision', subscriptions.revision
          ) end,
          'revision', accounts.revision,
          'serverSequence', accounts.server_sequence,
          'updatedAt', accounts.updated_at
        ) item
        from private.pachanga_organizer_billing_accounts accounts
        left join public.pachanga_groups groups on groups.id = accounts.organizer_group_id
        left join public.pachanga_clubs clubs on clubs.id = accounts.organizer_club_id
        left join lateral (
          select projections.*
          from private.pachanga_stripe_subscription_projections_v1 projections
          where projections.billing_account_id = accounts.id
          order by projections.server_sequence desc, projections.id desc
          limit 1
        ) subscriptions on true
        left join public.pachanga_organizer_plan_revisions revisions on revisions.id = subscriptions.plan_revision_id
        left join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id
        order by accounts.server_sequence desc, accounts.id desc
        limit safe_limit offset safe_offset
      ) rows
    ), '[]'::jsonb),
    'webhooks', coalesce((
      select jsonb_agg(rows.item order by rows.server_sequence desc, rows.id desc)
      from (
        select events.id, events.server_sequence, jsonb_build_object(
          'event', private.pachanga_billing_redact_stripe_id_v1(events.stripe_event_id),
          'mode', events.stripe_mode,
          'type', events.event_type,
          'status', events.processing_status,
          'attempts', events.attempt_count,
          'safeErrorCode', events.safe_error_code,
          'stripeCreatedAt', events.stripe_created_at,
          'receivedAt', events.received_at,
          'processedAt', events.processed_at,
          'serverSequence', events.server_sequence
        ) item
        from private.pachanga_stripe_webhook_events_v2 events
        order by events.server_sequence desc, events.id desc
        limit safe_limit
      ) rows
    ), '[]'::jsonb),
    'reconciliations', coalesce((
      select jsonb_agg(rows.item order by rows.server_sequence desc, rows.id desc)
      from (
        select reconciliations.id, reconciliations.server_sequence, jsonb_build_object(
          'id', reconciliations.id,
          'accountId', reconciliations.billing_account_id,
          'mode', reconciliations.stripe_mode,
          'reason', reconciliations.reason,
          'status', reconciliations.status,
          'differenceCodes', to_jsonb(reconciliations.difference_codes),
          'safeErrorCode', reconciliations.safe_error_code,
          'revision', reconciliations.revision,
          'createdAt', reconciliations.created_at,
          'completedAt', reconciliations.completed_at
        ) item
        from private.pachanga_stripe_billing_reconciliations_v1 reconciliations
        order by reconciliations.server_sequence desc, reconciliations.id desc
        limit safe_limit
      ) rows
    ), '[]'::jsonb),
    'accessGrants', coalesce((
      select jsonb_agg(rows.item order by rows.server_sequence desc, rows.id desc)
      from (
        select access.id, access.server_sequence, jsonb_build_object(
          'id', access.id,
          'organizerKind', access.organizer_kind,
          'organizerId', coalesce(access.organizer_group_id, access.organizer_club_id),
          'source', access.access_source,
          'planCode', catalog.plan_code,
          'status', access.status,
          'validUntil', access.valid_until,
          'reason', access.reason,
          'revision', access.revision,
          'serverSequence', access.server_sequence,
          'updatedAt', access.updated_at
        ) item
        from private.pachanga_organizer_access_grants_v1 access
        join public.pachanga_organizer_plan_revisions revisions on revisions.id = access.plan_revision_id
        join public.pachanga_organizer_plan_catalog catalog on catalog.id = revisions.plan_id
        order by access.server_sequence desc, access.id desc
        limit safe_limit
      ) rows
    ), '[]'::jsonb),
    'generatedAt', clock_timestamp()
  );
end;
$$;

create or replace function public.request_pachanga_billing_reconciliation_platform_v1(
  operation_id uuid,
  billing_account_id uuid,
  expected_revision bigint,
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
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare reconciliation private.pachanga_stripe_billing_reconciliations_v1%rowtype;
declare sequence_value bigint;
declare response jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('billing.write');
  if operation_id is null or billing_account_id is null or expected_revision is null
     or length(trim(coalesce(reason, ''))) not between 3 and 1200 then
    raise exception 'BILLING_INVALID_RECONCILIATION_REQUEST' using errcode = '22023';
  end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    'reconciliation.request', billing_account_id::text, expected_revision,
    jsonb_build_object('reason', trim(reason))
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77027));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = request_pachanga_billing_reconciliation_platform_v1.operation_id;
  if found then
    if prior.actor_id is distinct from actor_id or prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.id = billing_account_id
  for update;
  if not found then raise exception 'BILLING_ACCOUNT_NOT_FOUND' using errcode = 'P0002'; end if;
  if account.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  insert into private.pachanga_stripe_billing_reconciliations_v1(
    operation_id, billing_account_id, stripe_mode, requested_by, reason,
    status, server_sequence
  ) values (
    operation_id, account.id, account.stripe_mode, actor_id, trim(reason),
    'PENDING', sequence_value
  ) returning * into reconciliation;
  response := jsonb_build_object(
    'replayed', false,
    'reconciliationId', reconciliation.id,
    'status', reconciliation.status,
    'confirmedRevision', reconciliation.revision,
    'serverSequence', reconciliation.server_sequence
  );
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'platform', 'reconciliation.request',
    'organizer_billing_account', account.id::text, request_hash,
    reconciliation.revision, sequence_value, client_metadata, response,
    'RECONCILIATION_REQUESTED', jsonb_build_object(
      'reconciliationId', reconciliation.id,
      'actorRole', actor_role
    )
  );
  return response;
end;
$$;

create or replace function public.claim_pachanga_billing_reconciliation_service_v1(
  operation_id uuid,
  batch_size integer default 20
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare safe_limit integer := least(greatest(coalesce(batch_size, 20), 1), 100);
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare sequence_value bigint := nextval('private.pachanga_organizer_billing_sequence');
declare response jsonb;
declare confirmed_revision bigint;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null then
    raise exception 'BILLING_OPERATION_ID_REQUIRED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    'reconciliation.claim', 'queue', 0, jsonb_build_object('batchSize', safe_limit)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77028));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = claim_pachanga_billing_reconciliation_service_v1.operation_id;
  if found then
    if prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;

  with candidates as (
    select reconciliations.id
    from private.pachanga_stripe_billing_reconciliations_v1 reconciliations
    where reconciliations.status in ('PENDING', 'FAILED')
      and (reconciliations.last_attempt_at is null or reconciliations.last_attempt_at < clock_timestamp() - interval '5 minutes')
    order by reconciliations.server_sequence, reconciliations.id
    for update skip locked
    limit safe_limit
  ), claimed as (
    update private.pachanga_stripe_billing_reconciliations_v1 reconciliations set
      status = 'RUNNING', claim_operation_id = claim_pachanga_billing_reconciliation_service_v1.operation_id,
      started_at = coalesce(reconciliations.started_at, clock_timestamp()),
      last_attempt_at = clock_timestamp(), revision = reconciliations.revision + 1,
      server_sequence = sequence_value, updated_at = clock_timestamp()
    where reconciliations.id in (select candidates.id from candidates)
    returning reconciliations.*
  )
  select jsonb_build_object(
    'replayed', false,
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', claimed.id,
      'billingAccountId', claimed.billing_account_id,
      'mode', claimed.stripe_mode,
      'customerId', accounts.stripe_customer_id,
      'subscriptionId', subscriptions.stripe_subscription_id,
      'localSubscriptionStatus', subscriptions.status,
      'localPriceId', subscriptions.stripe_price_id,
      'localBillingInterval', subscriptions.billing_interval,
      'localCurrentPeriodStart', subscriptions.current_period_start,
      'localCurrentPeriodEnd', subscriptions.current_period_end,
      'localCancelAtPeriodEnd', subscriptions.cancel_at_period_end,
      'localCanceledAt', subscriptions.canceled_at,
      'localLastEventCreatedAt', subscriptions.last_event_created_at,
      'localLastEventId', subscriptions.last_event_id,
      'localProjectionRevision', coalesce(subscriptions.revision, 0),
      'revision', claimed.revision
    ) order by claimed.server_sequence, claimed.id), '[]'::jsonb)
  ), coalesce(max(claimed.revision), 0)
    into response, confirmed_revision
  from claimed
  join private.pachanga_organizer_billing_accounts accounts on accounts.id = claimed.billing_account_id
  left join lateral (
    select projections.*
    from private.pachanga_stripe_subscription_projections_v1 projections
    where projections.billing_account_id = accounts.id
    order by projections.server_sequence desc, projections.id desc
    limit 1
  ) subscriptions on true;

  response := coalesce(response, jsonb_build_object('replayed', false, 'items', '[]'::jsonb));
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, null, 'service_authority', 'reconciliation.claim', 'billing_reconciliation_queue',
    'queue', request_hash, confirmed_revision, sequence_value, '{}'::jsonb,
    response, 'RECONCILIATION_CLAIMED', jsonb_build_object(
      'itemCount', jsonb_array_length(response -> 'items')
    )
  );
  return response;
end;
$$;

create or replace function public.complete_pachanga_billing_reconciliation_service_v1(
  operation_id uuid,
  reconciliation_id uuid,
  expected_revision bigint,
  outcome text,
  difference_codes text[] default '{}'::text[],
  safe_error_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare normalized_outcome text := upper(trim(coalesce(outcome, '')));
declare normalized_differences text[] := coalesce(difference_codes, '{}'::text[]);
declare reconciliation private.pachanga_stripe_billing_reconciliations_v1%rowtype;
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare sequence_value bigint;
declare response jsonb;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null or reconciliation_id is null or expected_revision is null
     or normalized_outcome not in ('HEALTHY', 'REPAIRED', 'FAILED')
     or exists (select 1 from unnest(normalized_differences) value where value !~ '^[A-Z0-9_]{3,80}$') then
    raise exception 'BILLING_INVALID_RECONCILIATION_RESULT' using errcode = '22023';
  end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    'reconciliation.complete', reconciliation_id::text, expected_revision,
    jsonb_build_object('outcome', normalized_outcome, 'differenceCodes', to_jsonb(normalized_differences),
      'safeErrorCode', safe_error_code)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77029));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = complete_pachanga_billing_reconciliation_service_v1.operation_id;
  if found then
    if prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;
  select * into reconciliation
  from private.pachanga_stripe_billing_reconciliations_v1 rows
  where rows.id = reconciliation_id
  for update;
  if not found then raise exception 'BILLING_RECONCILIATION_NOT_FOUND' using errcode = 'P0002'; end if;
  if reconciliation.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  update private.pachanga_stripe_billing_reconciliations_v1 rows set
    status = normalized_outcome,
    difference_codes = normalized_differences,
    safe_error_code = case when normalized_outcome = 'FAILED'
      then private.pachanga_billing_safe_error_v1(
        complete_pachanga_billing_reconciliation_service_v1.safe_error_code
      ) else null end,
    completed_at = case when normalized_outcome in ('HEALTHY', 'REPAIRED') then clock_timestamp() else null end,
    revision = rows.revision + 1,
    server_sequence = sequence_value,
    updated_at = clock_timestamp()
  where rows.id = reconciliation.id
  returning * into reconciliation;
  response := jsonb_build_object(
    'replayed', false,
    'reconciliationId', reconciliation.id,
    'status', reconciliation.status,
    'differenceCodes', to_jsonb(reconciliation.difference_codes),
    'safeErrorCode', reconciliation.safe_error_code,
    'confirmedRevision', reconciliation.revision,
    'serverSequence', reconciliation.server_sequence
  );
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, null, 'service_authority', 'reconciliation.complete',
    'billing_reconciliation', reconciliation.id::text, request_hash,
    reconciliation.revision, sequence_value, '{}'::jsonb, response,
    'RECONCILIATION_' || reconciliation.status,
    jsonb_build_object('differenceCodes', to_jsonb(reconciliation.difference_codes))
  );
  return response;
end;
$$;

drop function if exists public.apply_pachanga_billing_reconciliation_snapshot_service_v1(
  uuid, uuid, bigint, timestamptz, text, text, text, text, text,
  timestamptz, timestamptz, boolean, timestamptz, text[]
);

create or replace function public.apply_pachanga_billing_reconciliation_snapshot_service_v1(
  operation_id uuid,
  reconciliation_id uuid,
  expected_revision bigint,
  observed_at timestamptz,
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_price_id text,
  subscription_status text,
  billing_interval text,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean default false,
  canceled_at timestamptz default null,
  difference_codes text[] default '{}'::text[],
  expected_projection_revision bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare normalized_status text := lower(trim(coalesce(subscription_status, '')));
declare normalized_interval text := lower(trim(coalesce(billing_interval, '')));
declare normalized_differences text[] := coalesce(difference_codes, '{}'::text[]);
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare reconciliation private.pachanga_stripe_billing_reconciliations_v1%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare mapping private.pachanga_organizer_plan_price_mappings%rowtype;
declare subscription private.pachanga_stripe_subscription_projections_v1%rowtype;
declare competing_subscription private.pachanga_stripe_subscription_projections_v1%rowtype;
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare sequence_value bigint;
declare synthetic_event_id text := 'evt_reconcile_' || replace(operation_id::text, '-', '');
declare grace_ends timestamptz;
declare response jsonb;
declare code text;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null or reconciliation_id is null or expected_revision is null or observed_at is null
     or expected_projection_revision is null or expected_projection_revision < 0
     or stripe_customer_id !~ '^cus_[A-Za-z0-9_]+' or stripe_subscription_id !~ '^sub_[A-Za-z0-9_]+'
     or stripe_price_id !~ '^price_[A-Za-z0-9_]+'
     or normalized_status not in ('incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'unpaid', 'paused', 'canceled')
     or normalized_interval not in ('month', 'year')
     or (current_period_start is not null and current_period_end is not null and current_period_end <= current_period_start)
     or observed_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'BILLING_INVALID_RECONCILIATION_SNAPSHOT' using errcode = '22023';
  end if;
  foreach code in array normalized_differences loop
    if code !~ '^[A-Z0-9_]{3,80}$' then
      raise exception 'BILLING_INVALID_RECONCILIATION_SNAPSHOT' using errcode = '22023';
    end if;
  end loop;
  request_hash := private.pachanga_billing_request_hash_v1(
    'reconciliation.snapshot', reconciliation_id::text, expected_revision,
    jsonb_build_object(
      'observedAt', observed_at, 'customerId', stripe_customer_id,
      'subscriptionId', stripe_subscription_id, 'priceId', stripe_price_id,
      'status', normalized_status, 'billingInterval', normalized_interval,
      'currentPeriodStart', current_period_start, 'currentPeriodEnd', current_period_end,
      'cancelAtPeriodEnd', coalesce(cancel_at_period_end, false), 'canceledAt', canceled_at,
      'differenceCodes', to_jsonb(normalized_differences),
      'expectedProjectionRevision', expected_projection_revision
    )
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77030));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = apply_pachanga_billing_reconciliation_snapshot_service_v1.operation_id;
  if found then
    if prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;

  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.reconciliation_enabled then
    raise exception 'BILLING_RECONCILIATION_DISABLED' using errcode = '0A000';
  end if;
  select * into reconciliation
  from private.pachanga_stripe_billing_reconciliations_v1 rows
  where rows.id = reconciliation_id
  for update;
  if not found then raise exception 'BILLING_RECONCILIATION_NOT_FOUND' using errcode = 'P0002'; end if;
  if reconciliation.revision <> expected_revision or reconciliation.status <> 'RUNNING' then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.id = reconciliation.billing_account_id
  for update;
  if not found or account.stripe_mode <> reconciliation.stripe_mode
     or account.stripe_customer_id is distinct from stripe_customer_id then
    raise exception 'BILLING_RECONCILIATION_ACCOUNT_MISMATCH' using errcode = '22023';
  end if;
  select * into mapping
  from private.pachanga_organizer_plan_price_mappings mappings
  where mappings.stripe_mode = reconciliation.stripe_mode
    and mappings.stripe_price_id = apply_pachanga_billing_reconciliation_snapshot_service_v1.stripe_price_id
    and mappings.active
    and (reconciliation.stripe_mode = 'test' or mappings.approved)
  for share;
  if not found then raise exception 'BILLING_UNKNOWN_PRICE' using errcode = '22023'; end if;

  select * into subscription
  from private.pachanga_stripe_subscription_projections_v1 projections
  where projections.stripe_mode = reconciliation.stripe_mode
    and projections.stripe_subscription_id = apply_pachanga_billing_reconciliation_snapshot_service_v1.stripe_subscription_id
  for update;
  if found and subscription.billing_account_id <> account.id then
    raise exception 'BILLING_RECONCILIATION_SUBSCRIPTION_MISMATCH' using errcode = '22023';
  end if;
  if coalesce(subscription.revision, 0) <> expected_projection_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;

  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  if found and subscription.last_event_created_at >= observed_at then
    if not ('STALE_OBSERVATION_IGNORED' = any(normalized_differences)) then
      normalized_differences := array_append(normalized_differences, 'STALE_OBSERVATION_IGNORED');
    end if;
    update private.pachanga_stripe_billing_reconciliations_v1 rows set
      status = 'HEALTHY', difference_codes = normalized_differences,
      safe_error_code = null, completed_at = clock_timestamp(),
      revision = rows.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where rows.id = reconciliation.id
    returning * into reconciliation;
    response := jsonb_build_object(
      'replayed', false, 'reconciliationId', reconciliation.id,
      'status', reconciliation.status, 'applied', false,
      'differenceCodes', to_jsonb(reconciliation.difference_codes),
      'confirmedRevision', reconciliation.revision,
      'projectionRevision', subscription.revision,
      'serverSequence', reconciliation.server_sequence
    );
    perform private.pachanga_billing_store_receipt_v1(
      operation_id, null, 'service_authority', 'reconciliation.snapshot',
      'billing_reconciliation', reconciliation.id::text, request_hash,
      reconciliation.revision, sequence_value, '{}'::jsonb, response,
      'RECONCILIATION_STALE_OBSERVATION_IGNORED',
      jsonb_build_object('differenceCodes', to_jsonb(reconciliation.difference_codes))
    );
    return response;
  end if;

  if subscription.id is null then
    select * into competing_subscription
    from private.pachanga_stripe_subscription_projections_v1 projections
    where projections.billing_account_id = account.id
      and projections.stripe_mode = reconciliation.stripe_mode
      and projections.subscription_family = 'ORGANIZER'
      and projections.status not in ('canceled', 'incomplete_expired')
    order by projections.server_sequence desc, projections.id desc
    limit 1
    for update;
    if found then
      raise exception 'BILLING_RECONCILIATION_SUBSCRIPTION_MISMATCH' using errcode = 'PT409';
    end if;
  end if;

  grace_ends := case
    when normalized_status = 'past_due' and subscription.status = 'past_due' and subscription.grace_ends_at is not null
      then subscription.grace_ends_at
    when normalized_status = 'past_due' then observed_at + make_interval(days => settings.grace_period_days)
    else null
  end;
  if subscription.id is null then
    insert into private.pachanga_stripe_subscription_projections_v1(
      billing_account_id, stripe_mode, stripe_subscription_id, stripe_customer_id,
      plan_revision_id, stripe_price_id, status, billing_interval,
      current_period_start, current_period_end, cancel_at_period_end, canceled_at,
      grace_ends_at, last_event_created_at, last_event_id, revision, server_sequence,
      projection_source, last_reconciled_at
    ) values (
      account.id, reconciliation.stripe_mode, stripe_subscription_id, stripe_customer_id,
      mapping.plan_revision_id, stripe_price_id, normalized_status, normalized_interval,
      current_period_start, current_period_end, coalesce(cancel_at_period_end, false), canceled_at,
      grace_ends, observed_at, synthetic_event_id, 1, sequence_value,
      'STRIPE_RECONCILIATION', clock_timestamp()
    ) returning * into subscription;
  else
    update private.pachanga_stripe_subscription_projections_v1 projections set
      stripe_customer_id = apply_pachanga_billing_reconciliation_snapshot_service_v1.stripe_customer_id,
      plan_revision_id = mapping.plan_revision_id,
      stripe_price_id = apply_pachanga_billing_reconciliation_snapshot_service_v1.stripe_price_id,
      status = normalized_status,
      billing_interval = normalized_interval,
      current_period_start = apply_pachanga_billing_reconciliation_snapshot_service_v1.current_period_start,
      current_period_end = apply_pachanga_billing_reconciliation_snapshot_service_v1.current_period_end,
      cancel_at_period_end = coalesce(apply_pachanga_billing_reconciliation_snapshot_service_v1.cancel_at_period_end, false),
      canceled_at = apply_pachanga_billing_reconciliation_snapshot_service_v1.canceled_at,
      grace_ends_at = grace_ends,
      last_event_created_at = observed_at,
      last_event_id = synthetic_event_id,
      revision = projections.revision + 1,
      server_sequence = sequence_value,
      projection_source = 'STRIPE_RECONCILIATION',
      last_reconciled_at = clock_timestamp(),
      updated_at = clock_timestamp()
    where projections.id = subscription.id
    returning * into subscription;
  end if;
  perform private.pachanga_billing_sync_entitlement_v1(
    subscription.id, 'Stripe reconciliation snapshot ' || reconciliation.id::text
  );

  if coalesce(array_length(normalized_differences, 1), 0) = 0 then
    normalized_differences := array['PROJECTION_DRIFT'];
  end if;
  update private.pachanga_stripe_billing_reconciliations_v1 rows set
    status = 'REPAIRED', difference_codes = normalized_differences,
    safe_error_code = null, completed_at = clock_timestamp(),
    revision = rows.revision + 1, server_sequence = sequence_value,
    updated_at = clock_timestamp()
  where rows.id = reconciliation.id
  returning * into reconciliation;
  response := jsonb_build_object(
    'replayed', false, 'reconciliationId', reconciliation.id,
    'status', reconciliation.status, 'applied', true,
    'differenceCodes', to_jsonb(reconciliation.difference_codes),
    'confirmedRevision', reconciliation.revision,
    'projectionRevision', subscription.revision,
    'serverSequence', reconciliation.server_sequence
  );
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, null, 'service_authority', 'reconciliation.snapshot',
    'billing_reconciliation', reconciliation.id::text, request_hash,
    reconciliation.revision, sequence_value, '{}'::jsonb, response,
    'RECONCILIATION_REPAIRED',
    jsonb_build_object(
      'differenceCodes', to_jsonb(reconciliation.difference_codes),
      'projectionId', subscription.id,
      'projectionRevision', subscription.revision,
      'projectionSource', subscription.projection_source
    )
  );
  return response;
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function private.pachanga_billing_redact_stripe_id_v1(text) from public, anon, authenticated;

revoke all on function public.get_pachanga_organizer_plan_catalog_v1() from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_organizer_plan_catalog_v1() to anon, authenticated, service_role;

revoke all on function public.get_my_pachanga_organizer_billing_v1(text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_organizer_billing_v1(text, uuid) to authenticated, service_role;

revoke all on function public.get_my_pachanga_billing_organizers_v1() from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_billing_organizers_v1() to authenticated, service_role;

revoke all on function public.get_pachanga_platform_organizer_billing_v2(integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_organizer_billing_v2(integer, integer) to authenticated, service_role;

revoke all on function public.request_pachanga_billing_reconciliation_platform_v1(uuid, uuid, bigint, text, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.request_pachanga_billing_reconciliation_platform_v1(uuid, uuid, bigint, text, jsonb) to authenticated;

revoke all on function public.claim_pachanga_billing_reconciliation_service_v1(uuid, integer) from public, anon, authenticated, service_role;
grant execute on function public.claim_pachanga_billing_reconciliation_service_v1(uuid, integer) to service_role;

revoke all on function public.complete_pachanga_billing_reconciliation_service_v1(uuid, uuid, bigint, text, text[], text) from public, anon, authenticated, service_role;
grant execute on function public.complete_pachanga_billing_reconciliation_service_v1(uuid, uuid, bigint, text, text[], text) to service_role;

revoke all on function public.apply_pachanga_billing_reconciliation_snapshot_service_v1(uuid, uuid, bigint, timestamptz, text, text, text, text, text, timestamptz, timestamptz, boolean, timestamptz, text[], bigint) from public, anon, authenticated, service_role;
grant execute on function public.apply_pachanga_billing_reconciliation_snapshot_service_v1(uuid, uuid, bigint, timestamptz, text, text, text, text, text, timestamptz, timestamptz, boolean, timestamptz, text[], bigint) to service_role;

comment on function public.get_pachanga_organizer_plan_catalog_v1() is
  'Public plan read model. It never exposes Stripe Product or Price identifiers and invents no commercial amount.';
comment on function public.get_my_pachanga_organizer_billing_v1(text, uuid) is
  'Owner-only canonical billing read model. Stripe IDs stay private; invoice URLs are visible only to the organizer owner.';
comment on function public.get_my_pachanga_billing_organizers_v1() is
  'Owner-only organizer selector for Billing UI. It contains no financial or Stripe identifier.';
comment on function public.get_pachanga_platform_organizer_billing_v2(integer, integer) is
  'Billing Control Center V2 with stable ordering, redacted Stripe references and no customer PII.';
