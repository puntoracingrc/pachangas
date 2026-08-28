-- Wave 7C: platform-owner commercial approval and versioned settings commands.

set lock_timeout = '5s';
set statement_timeout = '5min';

create or replace function private.pachanga_billing_require_platform_owner_v1()
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text;
begin
  actor_role := private.pachanga_platform_require_v1('billing.write');
  if actor_role <> 'platform_owner' then
    raise exception 'PLATFORM_OWNER_REQUIRED' using errcode = '42501';
  end if;
  return actor_role;
end;
$$;

create or replace function public.command_pachanga_organizer_commercial_decision_v1(
  operation_id uuid,
  decision_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare actor_role text;
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare decision private.pachanga_organizer_commercial_decisions_v1%rowtype;
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare reason_text text;
declare sequence_value bigint;
declare response jsonb;
declare requested_intervals jsonb;
begin
  if operation_id is null or decision_id is null or expected_revision is null
     or normalized_action not in (
       'commercial_decision.update', 'commercial_decision.submit',
       'commercial_decision.approve', 'commercial_decision.withdraw'
     ) or jsonb_typeof(payload) <> 'object' then
    raise exception 'BILLING_COMMERCIAL_COMMAND_INVALID' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_object_keys(payload) keys(key)
    where keys.key not in (
      'annualAmountMinor', 'billingIntervals', 'confirmLivePricing', 'currency',
      'effectiveFrom', 'monthlyAmountMinor', 'privacyRevision',
      'publicCopyRevision', 'reason', 'stripeTaxBehavior', 'taxDisplayMode',
      'termsRevision', 'trialDays'
    )
  ) then
    raise exception 'BILLING_COMMERCIAL_PAYLOAD_REJECTED' using errcode = '22023';
  end if;
  actor_role := private.pachanga_billing_require_platform_owner_v1();
  reason_text := trim(coalesce(payload ->> 'reason', ''));
  if length(reason_text) not between 3 and 1200 then
    raise exception 'BILLING_REASON_REQUIRED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    normalized_action, decision_id::text, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77101));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_organizer_commercial_decision_v1.operation_id;
  if found then
    if prior.actor_id is distinct from actor_id or prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;

  select * into decision
  from private.pachanga_organizer_commercial_decisions_v1 decisions
  where decisions.id = decision_id
  for update;
  if not found then raise exception 'BILLING_COMMERCIAL_DECISION_NOT_FOUND' using errcode = 'P0002'; end if;
  if decision.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  if decision.status in ('published', 'superseded') then
    raise exception 'BILLING_PUBLISHED_DECISION_IMMUTABLE' using errcode = 'PT409';
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  perform set_config('pachangas.billing_commercial_authority', operation_id::text, true);

  if normalized_action = 'commercial_decision.update' then
    if decision.status <> 'draft' then
      raise exception 'BILLING_COMMERCIAL_DECISION_NOT_EDITABLE' using errcode = 'PT409';
    end if;
    if payload ->> 'currency' is null or payload ->> 'monthlyAmountMinor' is null
       or payload ->> 'annualAmountMinor' is null or payload ->> 'taxDisplayMode' is null
       or payload ->> 'stripeTaxBehavior' is null or payload ->> 'trialDays' is null
       or payload ->> 'publicCopyRevision' is null or payload ->> 'termsRevision' is null
       or payload ->> 'privacyRevision' is null then
      raise exception 'BILLING_COMMERCIAL_FIELDS_REQUIRED' using errcode = '22023';
    end if;
    update private.pachanga_organizer_commercial_decisions_v1 decisions set
      currency = upper(trim(payload ->> 'currency')),
      monthly_amount_minor = (payload ->> 'monthlyAmountMinor')::bigint,
      annual_amount_minor = (payload ->> 'annualAmountMinor')::bigint,
      tax_display_mode = upper(trim(payload ->> 'taxDisplayMode')),
      stripe_tax_behavior = lower(trim(payload ->> 'stripeTaxBehavior')),
      trial_days = (payload ->> 'trialDays')::integer,
      effective_from = nullif(payload ->> 'effectiveFrom', '')::timestamptz,
      public_copy_revision = trim(payload ->> 'publicCopyRevision'),
      terms_revision = trim(payload ->> 'termsRevision'),
      privacy_revision = trim(payload ->> 'privacyRevision'),
      revision = decisions.revision + 1,
      server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where decisions.id = decision.id
    returning * into decision;

  elsif normalized_action = 'commercial_decision.submit' then
    if decision.status <> 'draft' or decision.effective_from is null
       or decision.tax_display_mode = 'PENDING_REVIEW'
       or decision.stripe_tax_behavior = 'unspecified'
       or decision.terms_revision = 'PENDING_APPROVAL'
       or decision.privacy_revision = 'PENDING_APPROVAL' then
      raise exception 'BILLING_COMMERCIAL_DECISION_INCOMPLETE' using errcode = '22023';
    end if;
    update private.pachanga_organizer_commercial_decisions_v1 decisions set
      status = 'pending_approval', revision = decisions.revision + 1,
      server_sequence = sequence_value, updated_at = clock_timestamp()
    where decisions.id = decision.id
    returning * into decision;

  elsif normalized_action = 'commercial_decision.approve' then
    requested_intervals := payload -> 'billingIntervals';
    if decision.status <> 'pending_approval'
       or payload ->> 'confirmLivePricing' <> 'CONFIRM_STRIPE_LIVE_PRICING'
       or requested_intervals is distinct from '["month", "year"]'::jsonb
       or upper(trim(coalesce(payload ->> 'currency', ''))) <> decision.currency
       or (payload ->> 'monthlyAmountMinor')::bigint is distinct from decision.monthly_amount_minor
       or (payload ->> 'annualAmountMinor')::bigint is distinct from decision.annual_amount_minor
       or upper(trim(coalesce(payload ->> 'taxDisplayMode', ''))) <> decision.tax_display_mode
       or lower(trim(coalesce(payload ->> 'stripeTaxBehavior', ''))) <> decision.stripe_tax_behavior
       or trim(coalesce(payload ->> 'termsRevision', '')) <> decision.terms_revision
       or trim(coalesce(payload ->> 'privacyRevision', '')) <> decision.privacy_revision
       or nullif(payload ->> 'effectiveFrom', '')::timestamptz is distinct from decision.effective_from then
      raise exception 'BILLING_COMMERCIAL_APPROVAL_MISMATCH' using errcode = '22023';
    end if;
    update private.pachanga_organizer_commercial_decisions_v1 decisions set
      status = 'approved', decision_kind = 'APPROVED_COMMERCIAL',
      approved_by = actor_id, approved_at = clock_timestamp(),
      revision = decisions.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where decisions.id = decision.id
    returning * into decision;

  else
    if decision.status <> 'approved' then
      raise exception 'BILLING_COMMERCIAL_DECISION_NOT_WITHDRAWABLE' using errcode = 'PT409';
    end if;
    update private.pachanga_organizer_commercial_decisions_v1 decisions set
      status = 'withdrawn', revision = decisions.revision + 1,
      server_sequence = sequence_value, updated_at = clock_timestamp()
    where decisions.id = decision.id
    returning * into decision;
  end if;

  response := jsonb_build_object(
    'decisionId', decision.id, 'planCode', decision.plan_code,
    'status', decision.status, 'approvalStatus', case
      when decision.status in ('approved', 'published') then 'APPROVED'
      else 'NOT_APPROVED' end,
    'confirmedRevision', decision.revision,
    'serverSequence', decision.server_sequence,
    'replayed', false
  );
  return private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'platform', normalized_action,
    'organizer_commercial_decision', decision.id::text, request_hash,
    decision.revision, decision.server_sequence, client_metadata, response,
    upper(replace(normalized_action, '.', '_')),
    jsonb_build_object('decisionId', decision.id, 'planCode', decision.plan_code,
      'status', decision.status, 'reason', left(reason_text, 1200), 'actorRole', actor_role)
  );
exception
  when unique_violation then raise exception 'BILLING_COMMERCIAL_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function public.command_pachanga_organizer_commercial_settings_v1(
  operation_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare actor_role text;
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare request_hash text;
declare sequence_value bigint;
declare reason_text text;
declare flag_key text;
declare flag_value boolean;
declare target_tax_health text;
declare response jsonb;
begin
  if operation_id is null or expected_revision is null
     or normalized_action not in ('settings.feature_flag_v2', 'settings.tax_health_v2')
     or jsonb_typeof(payload) <> 'object' then
    raise exception 'BILLING_COMMERCIAL_SETTINGS_INVALID' using errcode = '22023';
  end if;
  actor_role := private.pachanga_billing_require_platform_owner_v1();
  reason_text := trim(coalesce(payload ->> 'reason', ''));
  if length(reason_text) not between 3 and 1200 then
    raise exception 'BILLING_REASON_REQUIRED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    normalized_action, 'commercial-settings', expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77102));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_organizer_commercial_settings_v1.operation_id;
  if found then
    if prior.actor_id is distinct from actor_id or prior.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;
  select * into settings
  from private.pachanga_organizer_billing_settings
  where singleton for update;
  if settings.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  perform set_config('pachangas.billing_settings_authority', operation_id::text, true);

  if normalized_action = 'settings.tax_health_v2' then
    if payload ->> 'confirmation' <> 'CONFIRM_ORGANIZER_TAX_HEALTH' then
      raise exception 'BILLING_TAX_CONFIRMATION_REQUIRED' using errcode = '22023';
    end if;
    target_tax_health := upper(trim(coalesce(payload ->> 'taxHealth', '')));
    if target_tax_health not in (
      'UNCONFIGURED', 'COMMERCIAL_DECISION_PENDING', 'TAX_REVIEW_REQUIRED',
      'TEST_READY', 'LIVE_READY', 'BLOCKED'
    ) then raise exception 'BILLING_TAX_HEALTH_INVALID' using errcode = '22023'; end if;
    if target_tax_health = 'LIVE_READY' and (
      nullif(trim(coalesce(payload ->> 'termsRevision', '')), '') is null
      or nullif(trim(coalesce(payload ->> 'privacyRevision', '')), '') is null
      or (select count(*) from private.pachanga_organizer_commercial_decisions_v1 decisions
          where decisions.plan_code in ('TEAM_ORGANIZER_PRO', 'CLUB_ORGANIZER')
            and decisions.status in ('approved', 'published')
            and decisions.tax_display_mode <> 'PENDING_REVIEW'
            and decisions.stripe_tax_behavior <> 'unspecified'
            and decisions.terms_revision = trim(payload ->> 'termsRevision')
            and decisions.privacy_revision = trim(payload ->> 'privacyRevision')) <> 2
    ) then raise exception 'BILLING_LIVE_TAX_GATE_INCOMPLETE' using errcode = '0A000'; end if;
    update private.pachanga_organizer_billing_settings current_settings set
      tax_health = target_tax_health,
      organizer_terms_revision = nullif(trim(payload ->> 'termsRevision'), ''),
      organizer_privacy_revision = nullif(trim(payload ->> 'privacyRevision'), ''),
      revision = current_settings.revision + 1, server_sequence = sequence_value,
      updated_by = actor_id, updated_at = clock_timestamp()
    where singleton returning * into settings;
    response := jsonb_build_object('taxHealth', settings.tax_health,
      'confirmedRevision', settings.revision, 'serverSequence', settings.server_sequence,
      'replayed', false);
  else
    flag_key := lower(trim(coalesce(payload ->> 'flagKey', '')));
    if jsonb_typeof(payload -> 'enabled') <> 'boolean' or flag_key not in (
      'commercial_decision_workflow_enabled', 'organizer_pricing_ui_enabled',
      'stripe_test_checkout_enabled', 'stripe_test_portal_enabled',
      'demo_world_v29_enabled'
    ) then raise exception 'BILLING_COMMERCIAL_FLAG_INVALID' using errcode = '22023'; end if;
    flag_value := (payload ->> 'enabled')::boolean;
    if flag_value and flag_key = 'stripe_test_checkout_enabled' and (
      not settings.stripe_test_webhook_ready
      or settings.tax_health not in ('TEST_READY', 'LIVE_READY')
      or (select count(*) from private.pachanga_organizer_plan_price_mappings mappings
          where mappings.stripe_mode = 'test' and mappings.active and mappings.approved) < 4
    ) then raise exception 'BILLING_TEST_CHECKOUT_GATE_INCOMPLETE' using errcode = '0A000'; end if;
    if flag_value and flag_key = 'stripe_test_portal_enabled'
       and not settings.stripe_test_portal_ready then
      raise exception 'BILLING_TEST_PORTAL_GATE_INCOMPLETE' using errcode = '0A000';
    end if;
    update private.pachanga_organizer_billing_settings current_settings set
      commercial_decision_workflow_enabled = case when flag_key = 'commercial_decision_workflow_enabled' then flag_value else current_settings.commercial_decision_workflow_enabled end,
      organizer_pricing_ui_enabled = case when flag_key = 'organizer_pricing_ui_enabled' then flag_value else current_settings.organizer_pricing_ui_enabled end,
      stripe_test_checkout_enabled = case when flag_key = 'stripe_test_checkout_enabled' then flag_value else current_settings.stripe_test_checkout_enabled end,
      stripe_test_portal_enabled = case when flag_key = 'stripe_test_portal_enabled' then flag_value else current_settings.stripe_test_portal_enabled end,
      demo_world_v29_enabled = case when flag_key = 'demo_world_v29_enabled' then flag_value else current_settings.demo_world_v29_enabled end,
      revision = current_settings.revision + 1, server_sequence = sequence_value,
      updated_by = actor_id, updated_at = clock_timestamp()
    where singleton returning * into settings;
    response := jsonb_build_object('flagKey', flag_key, 'enabled', flag_value,
      'confirmedRevision', settings.revision, 'serverSequence', settings.server_sequence,
      'replayed', false);
  end if;

  return private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'platform', normalized_action,
    'organizer_commercial_settings', 'singleton', request_hash,
    settings.revision, settings.server_sequence, client_metadata, response,
    upper(replace(normalized_action, '.', '_')),
    (response - 'replayed') || jsonb_build_object('reason', left(reason_text, 1200), 'actorRole', actor_role)
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function private.pachanga_billing_require_platform_owner_v1() from public, anon, authenticated;
revoke all on function public.command_pachanga_organizer_commercial_decision_v1(uuid, uuid, bigint, text, jsonb, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_organizer_commercial_decision_v1(uuid, uuid, bigint, text, jsonb, jsonb) to authenticated, service_role;
revoke all on function public.command_pachanga_organizer_commercial_settings_v1(uuid, bigint, text, jsonb, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_organizer_commercial_settings_v1(uuid, bigint, text, jsonb, jsonb) to authenticated, service_role;
