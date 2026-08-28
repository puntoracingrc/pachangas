-- Wave 7B: idempotent command authority for Checkout, Portal, webhooks and manual grants.

set lock_timeout = '5s';
set statement_timeout = '5min';

create or replace function private.pachanga_platform_capabilities_v1(target_role text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case target_role
    when 'platform_owner' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend', 'roles.manage',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'billing.write', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'billing.write', 'system.read', 'flags.read', 'flags.write', 'audit.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read', 'clubs.read', 'referees.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read',
      'billing.read', 'billing.write', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read', 'referees.health.read'
    )
    else '[]'::jsonb
  end;
$$;

create table if not exists private.pachanga_organizer_billing_operation_receipts_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  request_hash text not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  client_metadata jsonb not null default '{}'::jsonb,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'platform', 'service_authority')),
  check (length(request_hash) = 64),
  check (confirmed_revision >= 0)
);

create table if not exists private.pachanga_organizer_billing_events_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  aggregate_revision bigint not null,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null unique,
  confirmed_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'platform', 'service_authority')),
  check (aggregate_revision >= 0),
  check (length(trim(reason_code)) between 3 and 120)
);

create table if not exists private.pachanga_organizer_checkout_intents_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  billing_account_id uuid not null references private.pachanga_organizer_billing_accounts(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  plan_revision_id uuid not null references public.pachanga_organizer_plan_revisions(id) on delete restrict,
  stripe_mode text not null,
  billing_interval text not null,
  expected_account_revision bigint not null,
  confirmed_account_revision bigint not null,
  request_hash text not null,
  status text not null default 'PREPARED',
  stripe_checkout_session_id text,
  stripe_customer_id text,
  checkout_url text,
  expires_at timestamptz,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (stripe_mode in ('test', 'live')),
  check (billing_interval in ('month', 'year')),
  check (expected_account_revision >= 0 and confirmed_account_revision >= 1),
  check (length(request_hash) = 64),
  check (status in ('PREPARED', 'SESSION_CREATED', 'WEBHOOK_CONFIRMED', 'EXPIRED', 'CANCELED', 'FAILED_SAFE')),
  check (stripe_checkout_session_id is null or stripe_checkout_session_id ~ '^cs_(test_|live_)?[A-Za-z0-9_]+$'),
  check (stripe_customer_id is null or stripe_customer_id ~ '^cus_[A-Za-z0-9_]+$'),
  check (checkout_url is null or checkout_url ~ '^https://')
);

create table if not exists private.pachanga_organizer_portal_intents_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  billing_account_id uuid not null references private.pachanga_organizer_billing_accounts(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  expected_account_revision bigint not null,
  request_hash text not null,
  status text not null default 'PREPARED',
  stripe_portal_session_id text,
  portal_url text,
  expires_at timestamptz,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (expected_account_revision >= 1),
  check (length(request_hash) = 64),
  check (status in ('PREPARED', 'SESSION_CREATED', 'EXPIRED', 'FAILED_SAFE')),
  check (stripe_portal_session_id is null or stripe_portal_session_id ~ '^bps_[A-Za-z0-9_]+$'),
  check (portal_url is null or portal_url ~ '^https://')
);

create index if not exists pachanga_billing_receipt_actor_idx
  on private.pachanga_organizer_billing_operation_receipts_v1(actor_id, created_at desc, id)
  where actor_id is not null;
create index if not exists pachanga_billing_event_aggregate_idx
  on private.pachanga_organizer_billing_events_v1(aggregate_type, aggregate_id, server_sequence desc, id);
create index if not exists pachanga_checkout_account_idx
  on private.pachanga_organizer_checkout_intents_v1(billing_account_id, server_sequence desc, id);
create index if not exists pachanga_checkout_pending_idx
  on private.pachanga_organizer_checkout_intents_v1(status, created_at, id)
  where status in ('PREPARED', 'SESSION_CREATED');
create index if not exists pachanga_portal_account_idx
  on private.pachanga_organizer_portal_intents_v1(billing_account_id, server_sequence desc, id);

create or replace function private.pachanga_billing_require_service_v1()
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.pachanga_billing_owner_can_manage_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case upper(target_organizer_kind)
    when 'TEAM' then exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_organizer_id and groups.owner_id = target_actor_id
    )
    when 'CLUB' then exists (
      select 1 from public.pachanga_clubs clubs
      where clubs.id = target_organizer_id and clubs.primary_owner_id = target_actor_id
        and clubs.operational_status = 'active'
    )
    else false
  end;
$$;

create or replace function private.pachanga_billing_client_metadata_v1(source jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', left(nullif(source ->> 'clientVersion', ''), 80),
    'serviceWorkerVersion', left(nullif(source ->> 'serviceWorkerVersion', ''), 80),
    'displayMode', case when source ->> 'displayMode' in ('browser', 'standalone', 'fullscreen') then source ->> 'displayMode' end,
    'sessionId', left(nullif(source ->> 'sessionId', ''), 120)
  ));
$$;

create or replace function private.pachanga_billing_request_hash_v1(
  target_action text,
  target_aggregate_id text,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(
    coalesce(target_action, '') || '|' || coalesce(target_aggregate_id, '') || '|'
    || coalesce(target_expected_revision, -1)::text || '|' || coalesce(target_payload, '{}'::jsonb)::text,
    'UTF8'
  ), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_billing_store_receipt_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id text,
  target_request_hash text,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_client_metadata jsonb,
  target_response jsonb,
  target_reason_code text,
  target_event_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into private.pachanga_organizer_billing_operation_receipts_v1(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id, target_request_hash,
    target_confirmed_revision, target_server_sequence,
    private.pachanga_billing_client_metadata_v1(target_client_metadata), target_response
  );
  insert into private.pachanga_organizer_billing_events_v1(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    aggregate_revision, reason_code, event_payload, server_sequence
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id, target_confirmed_revision,
    left(coalesce(nullif(trim(target_reason_code), ''), target_action), 120),
    coalesce(target_event_payload, '{}'::jsonb), target_server_sequence
  );
  return target_response;
end;
$$;

create or replace function public.prepare_pachanga_organizer_checkout_service_v1(
  operation_id uuid,
  actor_id uuid,
  organizer_kind text,
  organizer_id uuid,
  plan_code text,
  billing_interval text,
  stripe_mode text,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare plan_row public.pachanga_organizer_plan_catalog%rowtype;
declare plan_revision public.pachanga_organizer_plan_revisions%rowtype;
declare mapping private.pachanga_organizer_plan_price_mappings%rowtype;
declare intent private.pachanga_organizer_checkout_intents_v1%rowtype;
declare normalized_kind text := upper(trim(coalesce(organizer_kind, '')));
declare normalized_plan text := upper(trim(coalesce(plan_code, '')));
declare normalized_interval text := lower(trim(coalesce(billing_interval, '')));
declare normalized_mode text := lower(trim(coalesce(stripe_mode, '')));
declare request_hash text;
declare sequence_value bigint;
declare response jsonb;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null or actor_id is null or organizer_id is null or expected_revision is null then
    raise exception 'BILLING_INVALID_CHECKOUT_INTENT' using errcode = '22023';
  end if;
  if not private.pachanga_billing_owner_can_manage_v1(normalized_kind, organizer_id, actor_id) then
    raise exception 'BILLING_OWNER_REQUIRED' using errcode = '42501';
  end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.foundation_enabled or not settings.billing_accounts_enabled then
    raise exception 'BILLING_FOUNDATION_DISABLED' using errcode = '0A000';
  end if;
  if normalized_mode = 'live' and not settings.live_checkout_enabled then
    raise exception 'BILLING_CHECKOUT_LIVE_DISABLED' using errcode = '0A000';
  end if;
  if normalized_mode = 'test' and not settings.stripe_sandbox_enabled then
    raise exception 'BILLING_SANDBOX_DISABLED' using errcode = '0A000';
  end if;
  if normalized_interval not in ('month', 'year') or normalized_mode not in ('test', 'live') then
    raise exception 'BILLING_INVALID_INTERVAL_OR_MODE' using errcode = '22023';
  end if;
  select * into plan_row
  from public.pachanga_organizer_plan_catalog plans
  where plans.plan_code = normalized_plan and plans.status = 'active'
    and plans.requires_stripe and plans.organizer_kind = normalized_kind;
  if not found then raise exception 'BILLING_PLAN_NOT_AVAILABLE' using errcode = 'P0002'; end if;
  select * into plan_revision
  from public.pachanga_organizer_plan_revisions revisions
  where revisions.plan_id = plan_row.id and revisions.status = 'active'
    and revisions.effective_from <= clock_timestamp()
    and (revisions.effective_until is null or revisions.effective_until > clock_timestamp())
  order by revisions.version desc, revisions.id desc limit 1;
  select * into mapping
  from private.pachanga_organizer_plan_price_mappings mappings
  where mappings.plan_revision_id = plan_revision.id
    and mappings.stripe_mode = normalized_mode
    and mappings.billing_interval = normalized_interval and mappings.active;
  if not found or (normalized_mode = 'live' and not mapping.approved) then
    raise exception 'BILLING_PRICE_NOT_APPROVED' using errcode = '0A000';
  end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    'checkout.prepare', organizer_id::text, expected_revision,
    jsonb_build_object('organizerKind', normalized_kind, 'planCode', normalized_plan,
      'billingInterval', normalized_interval, 'stripeMode', normalized_mode)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77021));
  select * into intent
  from private.pachanga_organizer_checkout_intents_v1 intents
  where intents.operation_id = prepare_pachanga_organizer_checkout_service_v1.operation_id;
  if found then
    if intent.actor_id <> actor_id or intent.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    select * into account from private.pachanga_organizer_billing_accounts where id = intent.billing_account_id;
    return jsonb_build_object(
      'replayed', true, 'intentId', intent.id, 'billingAccountId', account.id,
      'stripeCustomerId', account.stripe_customer_id, 'stripePriceId', mapping.stripe_price_id,
      'stripeMode', normalized_mode, 'planCode', normalized_plan,
      'billingInterval', normalized_interval, 'status', intent.status,
      'checkoutSessionId', intent.stripe_checkout_session_id,
      'checkoutUrl', intent.checkout_url, 'expiresAt', intent.expires_at,
      'confirmedRevision', intent.confirmed_account_revision
    );
  end if;
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.organizer_kind = normalized_kind and accounts.stripe_mode = normalized_mode
    and ((normalized_kind = 'TEAM' and accounts.organizer_group_id = organizer_id)
      or (normalized_kind = 'CLUB' and accounts.organizer_club_id = organizer_id))
  for update;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  if not found then
    if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    insert into private.pachanga_organizer_billing_accounts(
      organizer_kind, organizer_group_id, organizer_club_id, stripe_mode,
      billing_contact_user_id, status, revision, server_sequence
    ) values (
      normalized_kind, case when normalized_kind = 'TEAM' then organizer_id end,
      case when normalized_kind = 'CLUB' then organizer_id end, normalized_mode,
      actor_id, 'ready', 1, sequence_value
    ) returning * into account;
  else
    if account.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    update private.pachanga_organizer_billing_accounts accounts set
      billing_contact_user_id = actor_id, status = case when accounts.status = 'unconfigured' then 'ready' else accounts.status end,
      revision = accounts.revision + 1, server_sequence = sequence_value, updated_at = clock_timestamp()
    where accounts.id = account.id returning * into account;
  end if;
  insert into private.pachanga_organizer_checkout_intents_v1(
    operation_id, billing_account_id, actor_id, plan_revision_id, stripe_mode,
    billing_interval, expected_account_revision, confirmed_account_revision,
    request_hash, server_sequence
  ) values (
    operation_id, account.id, actor_id, plan_revision.id, normalized_mode,
    normalized_interval, expected_revision, account.revision, request_hash, sequence_value
  ) returning * into intent;
  response := jsonb_build_object(
    'replayed', false, 'intentId', intent.id, 'billingAccountId', account.id,
    'stripeCustomerId', account.stripe_customer_id, 'stripePriceId', mapping.stripe_price_id,
    'stripeMode', normalized_mode, 'planCode', normalized_plan,
    'billingInterval', normalized_interval, 'status', intent.status,
    'confirmedRevision', account.revision
  );
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'authenticated', 'checkout.prepare', 'organizer_billing_account',
    account.id::text, request_hash, account.revision, sequence_value, client_metadata,
    response - 'stripeCustomerId' - 'stripePriceId', 'CHECKOUT_PREPARED',
    jsonb_build_object('intentId', intent.id, 'planCode', normalized_plan,
      'stripeMode', normalized_mode, 'billingInterval', normalized_interval)
  );
  return response;
exception
  when unique_violation then raise exception 'BILLING_CHECKOUT_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function public.confirm_pachanga_organizer_checkout_service_v1(
  operation_id uuid,
  stripe_checkout_session_id text,
  stripe_customer_id text,
  checkout_url text,
  expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare intent private.pachanga_organizer_checkout_intents_v1%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare sequence_value bigint;
begin
  perform private.pachanga_billing_require_service_v1();
  if stripe_checkout_session_id !~ '^cs_(test_|live_)?[A-Za-z0-9_]+' or stripe_customer_id !~ '^cus_[A-Za-z0-9_]+' then
    raise exception 'BILLING_INVALID_STRIPE_REFERENCE' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77022));
  select * into intent from private.pachanga_organizer_checkout_intents_v1 intents
  where intents.operation_id = confirm_pachanga_organizer_checkout_service_v1.operation_id for update;
  if not found then raise exception 'BILLING_CHECKOUT_INTENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if intent.status = 'SESSION_CREATED' then
    if intent.stripe_checkout_session_id <> stripe_checkout_session_id or intent.stripe_customer_id <> stripe_customer_id then
      raise exception 'BILLING_CHECKOUT_CONFIRMATION_CONFLICT' using errcode = 'PT409';
    end if;
    return jsonb_build_object('status', intent.status, 'checkoutUrl', intent.checkout_url,
      'expiresAt', intent.expires_at, 'confirmedRevision', intent.confirmed_account_revision);
  end if;
  if intent.status <> 'PREPARED' then raise exception 'BILLING_CHECKOUT_NOT_CONFIRMABLE' using errcode = 'PT409'; end if;
  select * into account from private.pachanga_organizer_billing_accounts accounts
  where accounts.id = intent.billing_account_id for update;
  if account.stripe_customer_id is not null and account.stripe_customer_id <> stripe_customer_id then
    raise exception 'BILLING_CUSTOMER_CONFLICT' using errcode = 'PT409';
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  update private.pachanga_organizer_billing_accounts accounts set
    stripe_customer_id = confirm_pachanga_organizer_checkout_service_v1.stripe_customer_id,
    revision = accounts.revision + 1,
    server_sequence = sequence_value, updated_at = clock_timestamp()
  where accounts.id = account.id returning * into account;
  update private.pachanga_organizer_checkout_intents_v1 intents set
    stripe_checkout_session_id = confirm_pachanga_organizer_checkout_service_v1.stripe_checkout_session_id,
    stripe_customer_id = confirm_pachanga_organizer_checkout_service_v1.stripe_customer_id,
    checkout_url = confirm_pachanga_organizer_checkout_service_v1.checkout_url,
    expires_at = confirm_pachanga_organizer_checkout_service_v1.expires_at,
    status = 'SESSION_CREATED', confirmed_account_revision = account.revision,
    server_sequence = sequence_value, updated_at = clock_timestamp()
  where intents.id = intent.id returning * into intent;
  return jsonb_build_object('status', intent.status, 'checkoutUrl', intent.checkout_url,
    'expiresAt', intent.expires_at, 'confirmedRevision', account.revision);
end;
$$;

create or replace function public.get_pachanga_organizer_checkout_status_v1(operation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare request_actor_id uuid := (select auth.uid());
declare intent private.pachanga_organizer_checkout_intents_v1%rowtype;
declare access private.pachanga_organizer_access_grants_v1%rowtype;
begin
  if request_actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select * into intent from private.pachanga_organizer_checkout_intents_v1 intents
  where intents.operation_id = get_pachanga_organizer_checkout_status_v1.operation_id
    and intents.actor_id = request_actor_id;
  if not found then raise exception 'BILLING_CHECKOUT_INTENT_NOT_FOUND' using errcode = 'P0002'; end if;
  select grants.* into access
  from private.pachanga_organizer_access_grants_v1 grants
  join private.pachanga_stripe_subscription_projections_v1 subscriptions
    on subscriptions.id = grants.subscription_projection_id
  where subscriptions.billing_account_id = intent.billing_account_id
    and grants.plan_revision_id = intent.plan_revision_id
  order by grants.server_sequence desc, grants.id desc limit 1;
  return jsonb_build_object(
    'operationId', intent.operation_id, 'status', intent.status,
    'confirmation', case when access.id is null then 'PENDING' else upper(access.status) end,
    'entitlementActive', coalesce(access.status in ('active', 'grace'), false),
    'confirmedRevision', intent.confirmed_account_revision, 'updatedAt', intent.updated_at
  );
end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text) from public, anon, authenticated;
revoke all on function private.pachanga_billing_require_service_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_owner_can_manage_v1(text, uuid, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_billing_client_metadata_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_billing_request_hash_v1(text, text, bigint, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_billing_store_receipt_v1(uuid, uuid, text, text, text, text, text, bigint, bigint, jsonb, jsonb, text, jsonb) from public, anon, authenticated;
revoke all on function public.prepare_pachanga_organizer_checkout_service_v1(uuid, uuid, text, uuid, text, text, text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.prepare_pachanga_organizer_checkout_service_v1(uuid, uuid, text, uuid, text, text, text, bigint, jsonb) to service_role;
revoke all on function public.confirm_pachanga_organizer_checkout_service_v1(uuid, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.confirm_pachanga_organizer_checkout_service_v1(uuid, text, text, text, timestamptz) to service_role;
revoke all on function public.get_pachanga_organizer_checkout_status_v1(uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_organizer_checkout_status_v1(uuid) to authenticated, service_role;

revoke all on table private.pachanga_organizer_billing_operation_receipts_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_billing_events_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_checkout_intents_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_portal_intents_v1 from public, anon, authenticated;
grant all on table private.pachanga_organizer_billing_operation_receipts_v1 to service_role;
grant all on table private.pachanga_organizer_billing_events_v1 to service_role;
grant all on table private.pachanga_organizer_checkout_intents_v1 to service_role;
grant all on table private.pachanga_organizer_portal_intents_v1 to service_role;

create or replace function public.prepare_pachanga_organizer_portal_service_v1(
  operation_id uuid,
  actor_id uuid,
  organizer_kind text,
  organizer_id uuid,
  stripe_mode text,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare intent private.pachanga_organizer_portal_intents_v1%rowtype;
declare normalized_kind text := upper(trim(coalesce(organizer_kind, '')));
declare normalized_mode text := lower(trim(coalesce(stripe_mode, '')));
declare request_hash text;
declare sequence_value bigint;
declare response jsonb;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null or actor_id is null or organizer_id is null or expected_revision is null then
    raise exception 'BILLING_INVALID_PORTAL_INTENT' using errcode = '22023';
  end if;
  if not private.pachanga_billing_owner_can_manage_v1(normalized_kind, organizer_id, actor_id) then
    raise exception 'BILLING_OWNER_REQUIRED' using errcode = '42501';
  end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.portal_enabled then raise exception 'BILLING_PORTAL_DISABLED' using errcode = '0A000'; end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    'portal.prepare', organizer_id::text, expected_revision,
    jsonb_build_object('organizerKind', normalized_kind, 'stripeMode', normalized_mode)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77023));
  select * into intent from private.pachanga_organizer_portal_intents_v1 intents
  where intents.operation_id = prepare_pachanga_organizer_portal_service_v1.operation_id;
  if found then
    if intent.actor_id <> actor_id or intent.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    select * into account from private.pachanga_organizer_billing_accounts where id = intent.billing_account_id;
    return jsonb_build_object('replayed', true, 'intentId', intent.id,
      'billingAccountId', account.id, 'stripeCustomerId', account.stripe_customer_id,
      'status', intent.status, 'portalUrl', intent.portal_url, 'expiresAt', intent.expires_at,
      'confirmedRevision', account.revision, 'stripeMode', account.stripe_mode);
  end if;
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.organizer_kind = normalized_kind and accounts.stripe_mode = normalized_mode
    and ((normalized_kind = 'TEAM' and accounts.organizer_group_id = organizer_id)
      or (normalized_kind = 'CLUB' and accounts.organizer_club_id = organizer_id))
  for update;
  if not found or account.stripe_customer_id is null then
    raise exception 'BILLING_CUSTOMER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if account.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  insert into private.pachanga_organizer_portal_intents_v1(
    operation_id, billing_account_id, actor_id, expected_account_revision,
    request_hash, server_sequence
  ) values (
    operation_id, account.id, actor_id, expected_revision, request_hash, sequence_value
  ) returning * into intent;
  response := jsonb_build_object('replayed', false, 'intentId', intent.id,
    'billingAccountId', account.id, 'stripeCustomerId', account.stripe_customer_id,
    'status', intent.status, 'confirmedRevision', account.revision, 'stripeMode', account.stripe_mode);
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'authenticated', 'portal.prepare', 'organizer_billing_account',
    account.id::text, request_hash, account.revision, sequence_value, client_metadata,
    response - 'stripeCustomerId', 'PORTAL_PREPARED', jsonb_build_object('intentId', intent.id)
  );
  return response;
end;
$$;

create or replace function public.confirm_pachanga_organizer_portal_service_v1(
  operation_id uuid,
  stripe_portal_session_id text,
  portal_url text,
  expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare intent private.pachanga_organizer_portal_intents_v1%rowtype;
begin
  perform private.pachanga_billing_require_service_v1();
  if stripe_portal_session_id !~ '^bps_[A-Za-z0-9_]+' or portal_url !~ '^https://' then
    raise exception 'BILLING_INVALID_PORTAL_REFERENCE' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77024));
  select * into intent from private.pachanga_organizer_portal_intents_v1 intents
  where intents.operation_id = confirm_pachanga_organizer_portal_service_v1.operation_id for update;
  if not found then raise exception 'BILLING_PORTAL_INTENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if intent.status = 'SESSION_CREATED' then
    if intent.stripe_portal_session_id <> stripe_portal_session_id then
      raise exception 'BILLING_PORTAL_CONFIRMATION_CONFLICT' using errcode = 'PT409';
    end if;
    return jsonb_build_object('status', intent.status, 'portalUrl', intent.portal_url, 'expiresAt', intent.expires_at);
  end if;
  if intent.status <> 'PREPARED' then raise exception 'BILLING_PORTAL_NOT_CONFIRMABLE' using errcode = 'PT409'; end if;
  update private.pachanga_organizer_portal_intents_v1 intents set
    stripe_portal_session_id = confirm_pachanga_organizer_portal_service_v1.stripe_portal_session_id,
    portal_url = confirm_pachanga_organizer_portal_service_v1.portal_url,
    expires_at = confirm_pachanga_organizer_portal_service_v1.expires_at,
    status = 'SESSION_CREATED', updated_at = clock_timestamp()
  where intents.id = intent.id returning * into intent;
  return jsonb_build_object('status', intent.status, 'portalUrl', intent.portal_url, 'expiresAt', intent.expires_at);
end;
$$;

create or replace function public.command_pachanga_organizer_billing_platform_v1(
  operation_id uuid,
  aggregate_id uuid,
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
declare request_hash text;
declare previous_receipt private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare plan_row public.pachanga_organizer_plan_catalog%rowtype;
declare plan_revision public.pachanga_organizer_plan_revisions%rowtype;
declare access private.pachanga_organizer_access_grants_v1%rowtype;
declare mapping private.pachanga_organizer_plan_price_mappings%rowtype;
declare capability_row record;
declare normalized_kind text;
declare organizer_id uuid;
declare requested_plan_code text;
declare capability_code text;
declare access_source text;
declare grant_source text;
declare valid_from timestamptz;
declare requested_valid_until timestamptz;
declare reason_text text;
declare sequence_value bigint;
declare confirmed_revision bigint;
declare response jsonb;
declare notify_user_id uuid;
declare flag_key text;
declare flag_value boolean;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or normalized_action not in ('manual.grant', 'manual.revoke', 'manual.renew', 'settings.flag', 'settings.tax_health', 'price_mapping.upsert')
     or jsonb_typeof(payload) <> 'object' then
    raise exception 'BILLING_PLATFORM_COMMAND_INVALID' using errcode = '22023';
  end if;
  actor_role := private.pachanga_platform_require_v1('billing.write');
  reason_text := left(coalesce(nullif(trim(payload ->> 'reason'), ''), normalized_action), 1200);
  if length(reason_text) < 3 then raise exception 'BILLING_REASON_REQUIRED' using errcode = '22023'; end if;
  request_hash := private.pachanga_billing_request_hash_v1(normalized_action, aggregate_id::text, expected_revision, payload);
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77025));
  select * into previous_receipt from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = command_pachanga_organizer_billing_platform_v1.operation_id;
  if found then
    if previous_receipt.actor_id <> actor_id or previous_receipt.request_hash <> request_hash then
      raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409';
    end if;
    return previous_receipt.response || jsonb_build_object('replayed', true);
  end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton for update;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');

  if normalized_action = 'settings.flag' then
    if expected_revision <> settings.revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    flag_key := lower(trim(coalesce(payload ->> 'flagKey', '')));
    flag_value := coalesce((payload ->> 'enabled')::boolean, false);
    if flag_key not in (
      'foundation_enabled', 'plan_catalog_enabled', 'partner_grants_enabled',
      'billing_accounts_enabled', 'organizer_ui_enabled', 'webhook_ingest_enabled',
      'stripe_sandbox_enabled', 'portal_enabled', 'reconciliation_enabled',
      'live_checkout_enabled', 'demo_world_v28_enabled', 'live_prices_approved'
    ) then raise exception 'BILLING_FLAG_NOT_SUPPORTED' using errcode = '22023'; end if;
    if flag_key in ('live_checkout_enabled', 'live_prices_approved') and actor_role <> 'platform_owner' then
      raise exception 'PLATFORM_OWNER_REQUIRED' using errcode = '42501';
    end if;
    update private.pachanga_organizer_billing_settings current_settings set
      foundation_enabled = case when flag_key = 'foundation_enabled' then flag_value else current_settings.foundation_enabled end,
      plan_catalog_enabled = case when flag_key = 'plan_catalog_enabled' then flag_value else current_settings.plan_catalog_enabled end,
      partner_grants_enabled = case when flag_key = 'partner_grants_enabled' then flag_value else current_settings.partner_grants_enabled end,
      billing_accounts_enabled = case when flag_key = 'billing_accounts_enabled' then flag_value else current_settings.billing_accounts_enabled end,
      organizer_ui_enabled = case when flag_key = 'organizer_ui_enabled' then flag_value else current_settings.organizer_ui_enabled end,
      webhook_ingest_enabled = case when flag_key = 'webhook_ingest_enabled' then flag_value else current_settings.webhook_ingest_enabled end,
      stripe_sandbox_enabled = case when flag_key = 'stripe_sandbox_enabled' then flag_value else current_settings.stripe_sandbox_enabled end,
      portal_enabled = case when flag_key = 'portal_enabled' then flag_value else current_settings.portal_enabled end,
      reconciliation_enabled = case when flag_key = 'reconciliation_enabled' then flag_value else current_settings.reconciliation_enabled end,
      live_checkout_enabled = case when flag_key = 'live_checkout_enabled' then flag_value else current_settings.live_checkout_enabled end,
      demo_world_v28_enabled = case when flag_key = 'demo_world_v28_enabled' then flag_value else current_settings.demo_world_v28_enabled end,
      live_prices_approved = case when flag_key = 'live_prices_approved' then flag_value else current_settings.live_prices_approved end,
      revision = current_settings.revision + 1, server_sequence = sequence_value,
      updated_by = actor_id, updated_at = clock_timestamp()
    where singleton returning revision into confirmed_revision;
    response := jsonb_build_object('flagKey', flag_key, 'enabled', flag_value,
      'confirmedRevision', confirmed_revision, 'serverSequence', sequence_value);

  elsif normalized_action = 'settings.tax_health' then
    if expected_revision <> settings.revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if actor_role <> 'platform_owner' then raise exception 'PLATFORM_OWNER_REQUIRED' using errcode = '42501'; end if;
    update private.pachanga_organizer_billing_settings current_settings set
      tax_health = upper(trim(coalesce(payload ->> 'taxHealth', ''))),
      revision = current_settings.revision + 1, server_sequence = sequence_value,
      updated_by = actor_id, updated_at = clock_timestamp()
    where singleton returning revision into confirmed_revision;
    response := jsonb_build_object('taxHealth', upper(trim(payload ->> 'taxHealth')),
      'confirmedRevision', confirmed_revision, 'serverSequence', sequence_value);

  elsif normalized_action = 'price_mapping.upsert' then
    requested_plan_code := upper(trim(coalesce(payload ->> 'planCode', '')));
    select * into plan_row from public.pachanga_organizer_plan_catalog plans
    where plans.plan_code = requested_plan_code
      and plans.requires_stripe and plans.status = 'active';
    if not found then raise exception 'BILLING_PLAN_NOT_AVAILABLE' using errcode = 'P0002'; end if;
    select * into plan_revision from public.pachanga_organizer_plan_revisions revisions
    where revisions.plan_id = plan_row.id and revisions.status = 'active'
    order by revisions.version desc, revisions.id desc limit 1;
    select * into mapping from private.pachanga_organizer_plan_price_mappings mappings
    where mappings.plan_revision_id = plan_revision.id
      and mappings.stripe_mode = lower(payload ->> 'stripeMode')
      and mappings.billing_interval = lower(payload ->> 'billingInterval') for update;
    if found and mapping.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if not found and expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if lower(payload ->> 'stripeMode') = 'live' and coalesce((payload ->> 'approved')::boolean, false)
       and actor_role <> 'platform_owner' then raise exception 'PLATFORM_OWNER_REQUIRED' using errcode = '42501'; end if;
    insert into private.pachanga_organizer_plan_price_mappings(
      plan_revision_id, stripe_mode, billing_interval, stripe_product_id, stripe_price_id,
      currency, unit_amount, tax_behavior, approved, active, revision, server_sequence,
      approved_by, approved_at
    ) values (
      plan_revision.id, lower(payload ->> 'stripeMode'), lower(payload ->> 'billingInterval'),
      payload ->> 'stripeProductId', payload ->> 'stripePriceId', lower(payload ->> 'currency'),
      nullif(payload ->> 'unitAmount', '')::bigint, lower(payload ->> 'taxBehavior'),
      coalesce((payload ->> 'approved')::boolean, false), true, 1, sequence_value,
      case when coalesce((payload ->> 'approved')::boolean, false) then actor_id end,
      case when coalesce((payload ->> 'approved')::boolean, false) then clock_timestamp() end
    ) on conflict (plan_revision_id, stripe_mode, billing_interval) do update set
      stripe_product_id = excluded.stripe_product_id, stripe_price_id = excluded.stripe_price_id,
      currency = excluded.currency, unit_amount = excluded.unit_amount, tax_behavior = excluded.tax_behavior,
      approved = excluded.approved, active = true,
      revision = private.pachanga_organizer_plan_price_mappings.revision + 1,
      server_sequence = excluded.server_sequence, approved_by = excluded.approved_by,
      approved_at = excluded.approved_at, updated_at = clock_timestamp()
    returning * into mapping;
    confirmed_revision := mapping.revision;
    response := jsonb_build_object('mappingId', mapping.id, 'planCode', requested_plan_code,
      'stripeMode', mapping.stripe_mode, 'billingInterval', mapping.billing_interval,
      'currency', mapping.currency, 'approved', mapping.approved,
      'confirmedRevision', confirmed_revision, 'serverSequence', sequence_value);

  elsif normalized_action = 'manual.grant' then
    if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if not settings.foundation_enabled then raise exception 'BILLING_FOUNDATION_DISABLED' using errcode = '0A000'; end if;
    normalized_kind := upper(trim(coalesce(payload ->> 'organizerKind', '')));
    organizer_id := aggregate_id;
    requested_plan_code := upper(trim(coalesce(payload ->> 'planCode', '')));
    select * into plan_row from public.pachanga_organizer_plan_catalog plans
    where plans.plan_code = requested_plan_code
      and plans.status = 'active' and not plans.requires_stripe
      and (plans.organizer_kind = normalized_kind or plans.organizer_kind = 'ANY');
    if not found then raise exception 'BILLING_MANUAL_PLAN_NOT_AVAILABLE' using errcode = 'P0002'; end if;
    if requested_plan_code = 'CLUB_PARTNER' and not settings.partner_grants_enabled then
      raise exception 'BILLING_PARTNER_GRANTS_DISABLED' using errcode = '0A000';
    end if;
    if normalized_kind = 'TEAM' and not exists (select 1 from public.pachanga_groups where id = organizer_id) then
      raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002';
    elsif normalized_kind = 'CLUB' and not exists (select 1 from public.pachanga_clubs where id = organizer_id and operational_status = 'active') then
      raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002';
    end if;
    select * into plan_revision from public.pachanga_organizer_plan_revisions revisions
    where revisions.plan_id = plan_row.id and revisions.status = 'active'
    order by revisions.version desc, revisions.id desc limit 1;
    valid_from := coalesce(nullif(payload ->> 'validFrom', '')::timestamptz, clock_timestamp());
    requested_valid_until := nullif(payload ->> 'expiresAt', '')::timestamptz;
    if requested_valid_until is not null
       and requested_valid_until <= greatest(valid_from, clock_timestamp()) then
      raise exception 'BILLING_GRANT_EXPIRY_INVALID' using errcode = '22023';
    end if;
    access_source := plan_row.access_model;
    grant_source := case access_source when 'PARTNERSHIP' then 'partnership'
      when 'PROMOTION' then 'promotion' else 'platform_grant' end;
    insert into private.pachanga_organizer_access_grants_v1(
      organizer_kind, organizer_group_id, organizer_club_id, plan_revision_id,
      access_source, source_reference, status, valid_from, valid_until, reason,
      granted_by, revision, server_sequence
    ) values (
      normalized_kind, case when normalized_kind = 'TEAM' then organizer_id end,
      case when normalized_kind = 'CLUB' then organizer_id end, plan_revision.id,
      access_source, lower(access_source) || ':' || gen_random_uuid()::text,
      'active', valid_from, requested_valid_until, reason_text, actor_id, 1, sequence_value
    ) returning * into access;
    foreach capability_code in array array(
      select features.feature_key from public.pachanga_organizer_plan_features features
      where features.plan_revision_id = plan_revision.id and features.enabled and features.entitlement_capability
      order by features.display_order, features.feature_key
    ) loop
      insert into public.pachanga_competition_entitlement_grants(
        organizer_kind, organizer_group_id, organizer_club_id, capability, grant_source,
        status, valid_from, expires_at, reason, revision, server_sequence, granted_by,
        billing_access_grant_id, billing_plan_revision_id, created_at, updated_at
      ) values (
        normalized_kind, case when normalized_kind = 'TEAM' then organizer_id end,
        case when normalized_kind = 'CLUB' then organizer_id end, capability_code, grant_source,
        'active', valid_from, requested_valid_until,
        left('WAVE7B ' || access_source || ': ' || reason_text, 1200),
        1, sequence_value, actor_id, access.id, plan_revision.id, clock_timestamp(), clock_timestamp()
      );
    end loop;
    confirmed_revision := access.revision;
    select case normalized_kind when 'TEAM' then groups.owner_id else null end into notify_user_id
      from public.pachanga_groups groups where normalized_kind = 'TEAM' and groups.id = organizer_id;
    if normalized_kind = 'CLUB' then select clubs.primary_owner_id into notify_user_id from public.pachanga_clubs clubs where clubs.id = organizer_id; end if;
    if notify_user_id is not null then
      perform private.pachanga_notify_v1(notify_user_id, 'organizer_plan_activated', 'Acceso de organizador activado',
        case when access_source = 'PARTNERSHIP' then 'Se ha concedido el acceso de Club colaborador.' else 'Se ha activado un acceso de organizador.' end,
        '/ajustes/facturacion', jsonb_build_object('accessGrantId', access.id, 'planCode', plan_row.plan_code),
        'billing-access:' || access.id::text || ':activated');
    end if;
    response := jsonb_build_object('accessGrantId', access.id, 'planCode', plan_row.plan_code,
      'status', access.status, 'validFrom', access.valid_from, 'validUntil', access.valid_until,
      'confirmedRevision', confirmed_revision, 'serverSequence', sequence_value);

  else
    select * into access from private.pachanga_organizer_access_grants_v1 grants
    where grants.id = aggregate_id for update;
    if not found or access.access_source = 'SUBSCRIPTION' then
      raise exception 'BILLING_MANUAL_GRANT_NOT_FOUND' using errcode = 'P0002';
    end if;
    if access.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if normalized_action = 'manual.revoke' then
      update private.pachanga_organizer_access_grants_v1 grants set
        status = 'revoked', revoked_by = actor_id, revoked_at = clock_timestamp(),
        revision = grants.revision + 1, server_sequence = sequence_value,
        reason = reason_text, updated_at = clock_timestamp()
      where grants.id = access.id returning * into access;
      update public.pachanga_competition_entitlement_grants grants set
        status = 'revoked', revoked_by = actor_id, revoked_at = clock_timestamp(),
        revision = grants.revision + 1, server_sequence = sequence_value, updated_at = clock_timestamp()
      where grants.billing_access_grant_id = access.id and grants.status = 'active';
    else
      requested_valid_until := nullif(payload ->> 'expiresAt', '')::timestamptz;
      if requested_valid_until is not null and requested_valid_until <= clock_timestamp() then
        raise exception 'BILLING_GRANT_EXPIRY_INVALID' using errcode = '22023';
      end if;
      update private.pachanga_organizer_access_grants_v1 grants set
        status = 'active', valid_until = requested_valid_until, restored_at = clock_timestamp(),
        revoked_by = null, revoked_at = null, revision = grants.revision + 1,
        server_sequence = sequence_value, reason = reason_text, updated_at = clock_timestamp()
      where grants.id = access.id returning * into access;
      for capability_row in
        select features.feature_key from public.pachanga_organizer_plan_features features
        where features.plan_revision_id = access.plan_revision_id and features.enabled and features.entitlement_capability
        order by features.display_order, features.feature_key
      loop
        if not exists (select 1 from public.pachanga_competition_entitlement_grants grants
          where grants.billing_access_grant_id = access.id and grants.capability = capability_row.feature_key and grants.status = 'active') then
          insert into public.pachanga_competition_entitlement_grants(
            organizer_kind, organizer_group_id, organizer_club_id, capability, grant_source,
            status, valid_from, expires_at, reason, revision, server_sequence, granted_by,
            billing_access_grant_id, billing_plan_revision_id, created_at, updated_at
          ) values (
            access.organizer_kind, access.organizer_group_id, access.organizer_club_id,
            capability_row.feature_key,
            case access.access_source when 'PARTNERSHIP' then 'partnership' when 'PROMOTION' then 'promotion' else 'platform_grant' end,
            'active', clock_timestamp(), requested_valid_until,
            left('WAVE7B RENEW: ' || reason_text, 1200),
            1, sequence_value, actor_id, access.id, access.plan_revision_id, clock_timestamp(), clock_timestamp()
          );
        end if;
      end loop;
    end if;
    confirmed_revision := access.revision;
    response := jsonb_build_object('accessGrantId', access.id, 'status', access.status,
      'validUntil', access.valid_until, 'confirmedRevision', confirmed_revision,
      'serverSequence', sequence_value);
  end if;

  return private.pachanga_billing_store_receipt_v1(
    operation_id, actor_id, 'platform', normalized_action, 'organizer_billing', aggregate_id::text,
    request_hash, confirmed_revision, sequence_value, client_metadata,
    response || jsonb_build_object('replayed', false), upper(replace(normalized_action, '.', '_')),
    response - 'replayed'
  );
exception
  when unique_violation then raise exception 'BILLING_PLATFORM_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.prepare_pachanga_organizer_portal_service_v1(uuid, uuid, text, uuid, text, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.prepare_pachanga_organizer_portal_service_v1(uuid, uuid, text, uuid, text, bigint, jsonb) to service_role;
revoke all on function public.confirm_pachanga_organizer_portal_service_v1(uuid, text, text, timestamptz) from public, anon, authenticated;
grant execute on function public.confirm_pachanga_organizer_portal_service_v1(uuid, text, text, timestamptz) to service_role;
revoke all on function public.command_pachanga_organizer_billing_platform_v1(uuid, uuid, bigint, text, jsonb, jsonb) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_organizer_billing_platform_v1(uuid, uuid, bigint, text, jsonb, jsonb) to authenticated, service_role;

comment on function public.command_pachanga_organizer_billing_platform_v1(uuid, uuid, bigint, text, jsonb, jsonb) is
  'Platform-only Wave 7B command surface. Direct UPDATE is never part of the operational contract.';

create or replace function public.record_pachanga_stripe_delivery_rejection_service_v1(
  operation_id uuid,
  endpoint_mode text,
  delivery_status text,
  http_result integer,
  request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare saved private.pachanga_stripe_webhook_deliveries_v1%rowtype;
begin
  perform private.pachanga_billing_require_service_v1();
  if lower(endpoint_mode) not in ('test', 'live')
     or delivery_status not in ('REJECTED_SIGNATURE', 'REJECTED_MODE', 'FAILED_SAFE')
     or http_result < 400 or http_result > 599 then
    raise exception 'BILLING_INVALID_REJECTED_DELIVERY' using errcode = '22023';
  end if;
  insert into private.pachanga_stripe_webhook_deliveries_v1(
    operation_id, endpoint_mode, signature_verified, delivery_status, http_result, request_id
  ) values (
    operation_id, lower(endpoint_mode), false, delivery_status, http_result, left(request_id, 160)
  ) on conflict (operation_id) do update set operation_id = excluded.operation_id
  returning * into saved;
  return jsonb_build_object('deliveryId', saved.id, 'status', saved.delivery_status);
end;
$$;

create or replace function public.ingest_pachanga_stripe_event_v1(
  delivery_operation_id uuid,
  stripe_mode text,
  stripe_event_id text,
  event_type text,
  api_version text,
  stripe_created_at timestamptz,
  payload_checksum text,
  normalized_payload jsonb,
  request_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare saved_event private.pachanga_stripe_webhook_events_v2%rowtype;
declare existing_event private.pachanga_stripe_webhook_events_v2%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare mapping private.pachanga_organizer_plan_price_mappings%rowtype;
declare subscription private.pachanga_stripe_subscription_projections_v1%rowtype;
declare invoice private.pachanga_stripe_invoice_projections_v1%rowtype;
declare intent private.pachanga_organizer_checkout_intents_v1%rowtype;
declare payload jsonb := coalesce(normalized_payload, '{}'::jsonb);
declare normalized_mode text := lower(trim(coalesce(stripe_mode, '')));
declare object_type text := nullif(payload ->> 'objectType', '');
declare object_id text := nullif(payload ->> 'objectId', '');
declare customer_id text := nullif(payload ->> 'customerId', '');
declare subscription_id text := nullif(payload ->> 'subscriptionId', '');
declare price_id text := nullif(payload ->> 'priceId', '');
declare subscription_status text := lower(nullif(payload ->> 'subscriptionStatus', ''));
declare invoice_id text := nullif(payload ->> 'invoiceId', '');
declare event_status text;
declare previous_status text;
declare sequence_value bigint;
declare grace_ends timestamptz;
declare metadata_operation_id uuid;
declare allowed_key text;
declare notify_kind text;
declare notify_title text;
declare notify_body text;
begin
  perform private.pachanga_billing_require_service_v1();
  if delivery_operation_id is null or normalized_mode not in ('test', 'live')
     or stripe_event_id !~ '^evt_[A-Za-z0-9_]+' or nullif(trim(event_type), '') is null
     or stripe_created_at is null or payload_checksum !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(payload) <> 'object' then
    raise exception 'BILLING_INVALID_STRIPE_EVENT' using errcode = '22023';
  end if;
  for allowed_key in select jsonb_object_keys(payload)
  loop
    if allowed_key not in (
      'objectType', 'objectId', 'customerId', 'subscriptionId', 'priceId',
      'subscriptionStatus', 'billingInterval', 'currentPeriodStart', 'currentPeriodEnd',
      'cancelAtPeriodEnd', 'canceledAt', 'invoiceId', 'invoiceStatus', 'currency',
      'amountDue', 'amountPaid', 'hostedInvoiceUrl', 'invoicePdfUrl', 'dueAt', 'paidAt',
      'failureCode', 'metadataOperationId', 'checkoutSessionId', 'checkoutStatus',
      'locale', 'billingCountry', 'taxConfigurationStatus'
    ) then raise exception 'BILLING_NORMALIZED_PAYLOAD_KEY_REJECTED' using errcode = '22023'; end if;
  end loop;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.webhook_ingest_enabled then raise exception 'BILLING_WEBHOOK_DISABLED' using errcode = '0A000'; end if;
  if normalized_mode = 'test' and not settings.stripe_sandbox_enabled then
    raise exception 'BILLING_SANDBOX_DISABLED' using errcode = '0A000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(normalized_mode || ':' || stripe_event_id, 77026));
  select * into existing_event from private.pachanga_stripe_webhook_events_v2 events
  where events.stripe_mode = normalized_mode and events.stripe_event_id = ingest_pachanga_stripe_event_v1.stripe_event_id;
  if found then
    insert into private.pachanga_stripe_webhook_deliveries_v1(
      operation_id, webhook_event_id, endpoint_mode, signature_verified,
      delivery_status, http_result, request_id
    ) values (
      delivery_operation_id, existing_event.id, normalized_mode, true, 'DUPLICATE', 200, left(request_id, 160)
    ) on conflict (operation_id) do nothing;
    return jsonb_build_object('accepted', true, 'duplicate', true,
      'status', existing_event.processing_status, 'eventId', existing_event.stripe_event_id);
  end if;
  insert into private.pachanga_stripe_webhook_events_v2(
    stripe_mode, stripe_event_id, event_type, api_version, object_type, object_id,
    stripe_created_at, payload_checksum, normalized_payload, processing_status
  ) values (
    normalized_mode, stripe_event_id, left(event_type, 160), nullif(left(api_version, 80), ''),
    object_type, object_id, stripe_created_at, payload_checksum, payload, 'PROCESSING'
  ) returning * into saved_event;
  insert into private.pachanga_stripe_webhook_deliveries_v1(
    operation_id, webhook_event_id, endpoint_mode, signature_verified,
    delivery_status, http_result, request_id
  ) values (
    delivery_operation_id, saved_event.id, normalized_mode, true, 'ACCEPTED', 200, left(request_id, 160)
  );
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');

  begin
  if event_type in ('checkout.session.completed', 'checkout.session.expired') then
    begin metadata_operation_id := nullif(payload ->> 'metadataOperationId', '')::uuid;
    exception when others then metadata_operation_id := null; end;
    if metadata_operation_id is not null then
      select * into intent from private.pachanga_organizer_checkout_intents_v1 intents
      where intents.operation_id = metadata_operation_id and intents.stripe_mode = normalized_mode for update;
      if found then
        update private.pachanga_organizer_checkout_intents_v1 intents set
          status = case when event_type = 'checkout.session.completed' then 'WEBHOOK_CONFIRMED' else 'EXPIRED' end,
          stripe_checkout_session_id = coalesce(nullif(payload ->> 'checkoutSessionId', ''), intents.stripe_checkout_session_id),
          stripe_customer_id = coalesce(customer_id, intents.stripe_customer_id),
          server_sequence = sequence_value, updated_at = clock_timestamp()
        where intents.id = intent.id;
      end if;
    end if;
    event_status := 'PROCESSED';

  elsif event_type in (
    'customer.subscription.created', 'customer.subscription.updated',
    'customer.subscription.deleted', 'customer.subscription.paused',
    'customer.subscription.resumed'
  ) then
    if customer_id !~ '^cus_[A-Za-z0-9_]+' or subscription_id !~ '^sub_[A-Za-z0-9_]+'
       or subscription_status not in ('incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'unpaid', 'paused', 'canceled') then
      raise exception 'BILLING_INVALID_SUBSCRIPTION_PROJECTION' using errcode = '22023';
    end if;
    select * into account from private.pachanga_organizer_billing_accounts accounts
    where accounts.stripe_mode = normalized_mode and accounts.stripe_customer_id = customer_id for update;
    if not found then
      update private.pachanga_stripe_webhook_events_v2 events set
        processing_status = 'FAILED_RETRYABLE', safe_error_code = 'BILLING_ACCOUNT_NOT_FOUND',
        attempt_count = events.attempt_count + 1
      where events.id = saved_event.id;
      return jsonb_build_object('accepted', true, 'duplicate', false,
        'status', 'RECONCILIATION_REQUIRED', 'errorCode', 'BILLING_ACCOUNT_NOT_FOUND');
    end if;
    select * into mapping from private.pachanga_organizer_plan_price_mappings mappings
    where mappings.stripe_mode = normalized_mode and mappings.stripe_price_id = price_id and mappings.active;
    if not found then
      insert into private.pachanga_stripe_billing_reconciliations_v1(
        operation_id, billing_account_id, stripe_mode, reason, status,
        difference_codes, safe_error_code, server_sequence
      ) values (
        gen_random_uuid(), account.id, normalized_mode, 'Unknown Stripe Price received by signed webhook',
        'PENDING', array['UNKNOWN_PRICE'], 'BILLING_UNKNOWN_PRICE', sequence_value
      );
      update private.pachanga_stripe_webhook_events_v2 events set
        processing_status = 'FAILED_RETRYABLE', safe_error_code = 'BILLING_UNKNOWN_PRICE',
        attempt_count = events.attempt_count + 1
      where events.id = saved_event.id;
      return jsonb_build_object('accepted', true, 'duplicate', false,
        'status', 'RECONCILIATION_REQUIRED', 'errorCode', 'BILLING_UNKNOWN_PRICE');
    end if;
    select * into subscription from private.pachanga_stripe_subscription_projections_v1 projections
    where projections.stripe_mode = normalized_mode and projections.stripe_subscription_id = subscription_id for update;
    if found and not private.pachanga_billing_event_is_newer_v1(
      stripe_created_at, stripe_event_id, subscription.last_event_created_at, subscription.last_event_id
    ) then
      event_status := 'PROCESSED';
    else
      previous_status := subscription.status;
      grace_ends := case when subscription_status = 'past_due'
        then clock_timestamp() + make_interval(days => settings.grace_period_days) else null end;
      if found then
        update private.pachanga_stripe_subscription_projections_v1 projections set
          billing_account_id = account.id, stripe_customer_id = customer_id,
          plan_revision_id = mapping.plan_revision_id, stripe_price_id = price_id,
          status = subscription_status, billing_interval = nullif(payload ->> 'billingInterval', ''),
          current_period_start = nullif(payload ->> 'currentPeriodStart', '')::timestamptz,
          current_period_end = nullif(payload ->> 'currentPeriodEnd', '')::timestamptz,
          cancel_at_period_end = coalesce((payload ->> 'cancelAtPeriodEnd')::boolean, false),
          canceled_at = nullif(payload ->> 'canceledAt', '')::timestamptz,
          grace_ends_at = grace_ends, last_event_created_at = stripe_created_at,
          last_event_id = stripe_event_id, revision = projections.revision + 1,
          server_sequence = sequence_value, updated_at = clock_timestamp()
        where projections.id = subscription.id returning * into subscription;
      else
        insert into private.pachanga_stripe_subscription_projections_v1(
          billing_account_id, stripe_mode, stripe_subscription_id, stripe_customer_id,
          plan_revision_id, stripe_price_id, status, billing_interval,
          current_period_start, current_period_end, cancel_at_period_end, canceled_at,
          grace_ends_at, last_event_created_at, last_event_id, server_sequence
        ) values (
          account.id, normalized_mode, subscription_id, customer_id, mapping.plan_revision_id,
          price_id, subscription_status, nullif(payload ->> 'billingInterval', ''),
          nullif(payload ->> 'currentPeriodStart', '')::timestamptz,
          nullif(payload ->> 'currentPeriodEnd', '')::timestamptz,
          coalesce((payload ->> 'cancelAtPeriodEnd')::boolean, false),
          nullif(payload ->> 'canceledAt', '')::timestamptz, grace_ends,
          stripe_created_at, stripe_event_id, sequence_value
        ) returning * into subscription;
      end if;
      perform private.pachanga_billing_sync_entitlement_v1(subscription.id, 'Signed Stripe event ' || stripe_event_id);
      notify_kind := case subscription_status
        when 'active' then 'organizer_plan_activated'
        when 'trialing' then 'organizer_plan_activated'
        when 'past_due' then 'billing_warning_payment_failed'
        when 'unpaid' then 'billing_warning_access_blocked'
        when 'paused' then 'billing_warning_access_blocked'
        when 'canceled' then 'organizer_subscription_canceled'
        else null end;
      notify_title := case subscription_status
        when 'active' then 'Plan de organizador activo'
        when 'trialing' then 'Plan de organizador activo'
        when 'past_due' then 'Pago pendiente'
        when 'unpaid' then 'Acceso de creacion bloqueado'
        when 'paused' then 'Suscripcion pausada'
        when 'canceled' then 'Suscripcion cancelada'
        else null end;
      notify_body := case subscription_status
        when 'past_due' then 'Revisa la facturacion antes de que termine el periodo de gracia.'
        when 'unpaid' then 'No se pueden crear nuevas competiciones hasta regularizar el plan.'
        when 'paused' then 'No se pueden crear nuevas competiciones mientras la suscripcion este pausada.'
        when 'canceled' then 'Las ediciones con continuidad pueden concluir; no se admiten nuevas altas.'
        else 'El acceso de organizacion se ha confirmado desde Stripe.' end;
      if notify_kind is not null and account.billing_contact_user_id is not null and previous_status is distinct from subscription_status then
        perform private.pachanga_notify_v1(account.billing_contact_user_id, notify_kind, notify_title, notify_body,
          '/ajustes/facturacion', jsonb_build_object('billingAccountId', account.id, 'status', subscription_status),
          'billing-subscription:' || subscription.id::text || ':' || subscription.revision::text || ':' || notify_kind);
      end if;
      event_status := 'PROCESSED';
    end if;

  elsif event_type in (
    'invoice.created', 'invoice.finalized', 'invoice.paid',
    'invoice.payment_failed', 'invoice.payment_action_required'
  ) then
    if customer_id !~ '^cus_[A-Za-z0-9_]+' or invoice_id !~ '^in_[A-Za-z0-9_]+' then
      raise exception 'BILLING_INVALID_INVOICE_PROJECTION' using errcode = '22023';
    end if;
    select * into account from private.pachanga_organizer_billing_accounts accounts
    where accounts.stripe_mode = normalized_mode and accounts.stripe_customer_id = customer_id for update;
    if not found then
      update private.pachanga_stripe_webhook_events_v2 events set
        processing_status = 'FAILED_RETRYABLE', safe_error_code = 'BILLING_ACCOUNT_NOT_FOUND'
      where events.id = saved_event.id;
      return jsonb_build_object('accepted', true, 'status', 'RECONCILIATION_REQUIRED', 'errorCode', 'BILLING_ACCOUNT_NOT_FOUND');
    end if;
    select * into subscription from private.pachanga_stripe_subscription_projections_v1 projections
    where projections.stripe_mode = normalized_mode and projections.stripe_subscription_id = subscription_id;
    select * into invoice from private.pachanga_stripe_invoice_projections_v1 projections
    where projections.stripe_mode = normalized_mode and projections.stripe_invoice_id = invoice_id for update;
    if not found or private.pachanga_billing_event_is_newer_v1(
      stripe_created_at, stripe_event_id, invoice.last_event_created_at, invoice.last_event_id
    ) then
      insert into private.pachanga_stripe_invoice_projections_v1(
        billing_account_id, subscription_projection_id, stripe_mode, stripe_invoice_id,
        stripe_subscription_id, stripe_customer_id, status, currency, amount_due, amount_paid,
        hosted_invoice_url, invoice_pdf_url, due_at, paid_at,
        last_event_created_at, last_event_id, server_sequence
      ) values (
        account.id, subscription.id, normalized_mode, invoice_id, subscription_id, customer_id,
        lower(coalesce(nullif(payload ->> 'invoiceStatus', ''), 'open')),
        lower(coalesce(nullif(payload ->> 'currency', ''), 'eur')),
        coalesce(nullif(payload ->> 'amountDue', '')::bigint, 0),
        coalesce(nullif(payload ->> 'amountPaid', '')::bigint, 0),
        nullif(payload ->> 'hostedInvoiceUrl', ''), nullif(payload ->> 'invoicePdfUrl', ''),
        nullif(payload ->> 'dueAt', '')::timestamptz, nullif(payload ->> 'paidAt', '')::timestamptz,
        stripe_created_at, stripe_event_id, sequence_value
      ) on conflict on constraint pachanga_stripe_invoice_mode_id_uq do update set
        subscription_projection_id = excluded.subscription_projection_id,
        status = excluded.status, currency = excluded.currency,
        amount_due = excluded.amount_due, amount_paid = excluded.amount_paid,
        hosted_invoice_url = excluded.hosted_invoice_url, invoice_pdf_url = excluded.invoice_pdf_url,
        due_at = excluded.due_at, paid_at = excluded.paid_at,
        last_event_created_at = excluded.last_event_created_at, last_event_id = excluded.last_event_id,
        revision = private.pachanga_stripe_invoice_projections_v1.revision + 1,
        server_sequence = excluded.server_sequence, updated_at = clock_timestamp()
      returning * into invoice;
    end if;
    if event_type in ('invoice.payment_failed', 'invoice.payment_action_required') then
      insert into private.pachanga_stripe_payment_failures_v1(
        billing_account_id, subscription_projection_id, invoice_projection_id, stripe_mode,
        failure_key, safe_failure_code, status, first_failed_at, last_failed_at, server_sequence
      ) values (
        account.id, subscription.id, invoice.id, normalized_mode, invoice_id,
        private.pachanga_billing_safe_error_v1(coalesce(payload ->> 'failureCode', event_type)),
        case when event_type = 'invoice.payment_action_required' then 'ACTION_REQUIRED' else 'OPEN' end,
        stripe_created_at, stripe_created_at, sequence_value
      ) on conflict on constraint pachanga_stripe_failure_mode_key_uq do update set
        status = excluded.status, safe_failure_code = excluded.safe_failure_code,
        last_failed_at = greatest(private.pachanga_stripe_payment_failures_v1.last_failed_at, excluded.last_failed_at),
        attempt_count = private.pachanga_stripe_payment_failures_v1.attempt_count + 1,
        revision = private.pachanga_stripe_payment_failures_v1.revision + 1,
        server_sequence = excluded.server_sequence, updated_at = clock_timestamp();
      if account.billing_contact_user_id is not null then
        perform private.pachanga_notify_v1(account.billing_contact_user_id,
          case when event_type = 'invoice.payment_action_required' then 'billing_warning_action_required' else 'billing_warning_payment_failed' end,
          case when event_type = 'invoice.payment_action_required' then 'Accion de pago necesaria' else 'Pago no completado' end,
          'Abre Facturacion para revisar la suscripcion del organizador.', '/ajustes/facturacion',
          jsonb_build_object('billingAccountId', account.id, 'status', event_type),
          'billing-invoice:' || invoice.id::text || ':' || event_type);
      end if;
    elsif event_type = 'invoice.paid' then
      update private.pachanga_stripe_payment_failures_v1 failures set
        status = 'RECOVERED', recovered_at = clock_timestamp(), revision = failures.revision + 1,
        server_sequence = sequence_value, updated_at = clock_timestamp()
      where failures.invoice_projection_id = invoice.id and failures.status in ('OPEN', 'ACTION_REQUIRED');
    end if;
    if subscription.id is not null and subscription_status in ('incomplete', 'incomplete_expired', 'trialing', 'active', 'past_due', 'unpaid', 'paused', 'canceled')
       and private.pachanga_billing_event_is_newer_v1(stripe_created_at, stripe_event_id, subscription.last_event_created_at, subscription.last_event_id) then
      update private.pachanga_stripe_subscription_projections_v1 projections set
        status = subscription_status,
        grace_ends_at = case when subscription_status = 'past_due'
          then clock_timestamp() + make_interval(days => settings.grace_period_days) else null end,
        last_event_created_at = stripe_created_at, last_event_id = stripe_event_id,
        revision = projections.revision + 1, server_sequence = sequence_value, updated_at = clock_timestamp()
      where projections.id = subscription.id returning * into subscription;
      perform private.pachanga_billing_sync_entitlement_v1(subscription.id, 'Signed Stripe invoice event ' || stripe_event_id);
    end if;
    event_status := 'PROCESSED';

  elsif event_type = 'customer.updated' then
    select * into account from private.pachanga_organizer_billing_accounts accounts
    where accounts.stripe_mode = normalized_mode and accounts.stripe_customer_id = customer_id for update;
    if found then
      update private.pachanga_organizer_billing_accounts accounts set
        locale = coalesce(nullif(payload ->> 'locale', ''), accounts.locale),
        billing_country = coalesce(nullif(payload ->> 'billingCountry', ''), accounts.billing_country),
        tax_configuration_status = coalesce(nullif(payload ->> 'taxConfigurationStatus', ''), accounts.tax_configuration_status),
        revision = accounts.revision + 1, server_sequence = sequence_value, updated_at = clock_timestamp()
      where accounts.id = account.id;
    end if;
    event_status := 'PROCESSED';
  else
    event_status := 'IGNORED_SAFE';
  end if;

  update private.pachanga_stripe_webhook_events_v2 events set
    processing_status = event_status, processed_at = clock_timestamp(), safe_error_code = null
  where events.id = saved_event.id;
  return jsonb_build_object('accepted', true, 'duplicate', false,
    'status', event_status, 'eventId', stripe_event_id);
  exception
    when others then
    if saved_event.id is not null then
      update private.pachanga_stripe_webhook_events_v2 events set
        processing_status = case when sqlstate in ('40001', '40P01', '55P03') then 'FAILED_RETRYABLE' else 'FAILED_TERMINAL' end,
        safe_error_code = private.pachanga_billing_safe_error_v1(sqlerrm),
        attempt_count = events.attempt_count + 1
      where events.id = saved_event.id;
    end if;
    return jsonb_build_object(
      'accepted', true,
      'duplicate', false,
      'status', case when sqlstate in ('40001', '40P01', '55P03') then 'FAILED_RETRYABLE' else 'FAILED_TERMINAL' end,
      'errorCode', private.pachanga_billing_safe_error_v1(sqlerrm),
      'eventId', stripe_event_id
    );
  end;
end;
$$;

revoke all on function public.record_pachanga_stripe_delivery_rejection_service_v1(uuid, text, text, integer, text) from public, anon, authenticated;
grant execute on function public.record_pachanga_stripe_delivery_rejection_service_v1(uuid, text, text, integer, text) to service_role;
revoke all on function public.ingest_pachanga_stripe_event_v1(uuid, text, text, text, text, timestamptz, text, jsonb, text) from public, anon, authenticated;
grant execute on function public.ingest_pachanga_stripe_event_v1(uuid, text, text, text, text, timestamptz, text, jsonb, text) to service_role;

comment on function public.ingest_pachanga_stripe_event_v1(uuid, text, text, text, text, timestamptz, text, jsonb, text) is
  'Service-only signed event ingestion. Redirects never call this function and never grant an entitlement.';
