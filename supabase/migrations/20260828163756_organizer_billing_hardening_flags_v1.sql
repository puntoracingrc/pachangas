-- Wave 7B: final indexes, guards, and OFF-by-default activation flags.

set lock_timeout = '5s';
set statement_timeout = '5min';

create index if not exists pachanga_billing_continuity_plan_idx
  on private.pachanga_competition_billing_continuity_grants_v1(plan_revision_id);
create index if not exists pachanga_billing_continuity_revoked_by_idx
  on private.pachanga_competition_billing_continuity_grants_v1(revoked_by)
  where revoked_by is not null;
create index if not exists pachanga_organizer_access_account_idx
  on private.pachanga_organizer_access_grants_v1(billing_account_id, server_sequence desc, id)
  where billing_account_id is not null;
create index if not exists pachanga_organizer_access_plan_idx
  on private.pachanga_organizer_access_grants_v1(plan_revision_id, status, server_sequence desc, id);
create index if not exists pachanga_organizer_access_granted_by_idx
  on private.pachanga_organizer_access_grants_v1(granted_by)
  where granted_by is not null;
create index if not exists pachanga_organizer_access_revoked_by_idx
  on private.pachanga_organizer_access_grants_v1(revoked_by)
  where revoked_by is not null;
create index if not exists pachanga_billing_event_actor_idx
  on private.pachanga_organizer_billing_events_v1(actor_id, server_sequence desc, id)
  where actor_id is not null;
create index if not exists pachanga_billing_settings_updated_by_idx
  on private.pachanga_organizer_billing_settings(updated_by)
  where updated_by is not null;
create index if not exists pachanga_checkout_actor_idx
  on private.pachanga_organizer_checkout_intents_v1(actor_id, server_sequence desc, id);
create index if not exists pachanga_checkout_plan_idx
  on private.pachanga_organizer_checkout_intents_v1(plan_revision_id, server_sequence desc, id);
create index if not exists pachanga_price_mapping_approved_by_idx
  on private.pachanga_organizer_plan_price_mappings(approved_by)
  where approved_by is not null;
create index if not exists pachanga_portal_actor_idx
  on private.pachanga_organizer_portal_intents_v1(actor_id, server_sequence desc, id);
create index if not exists pachanga_reconciliation_account_idx
  on private.pachanga_stripe_billing_reconciliations_v1(billing_account_id, server_sequence desc, id);
create index if not exists pachanga_reconciliation_requested_by_idx
  on private.pachanga_stripe_billing_reconciliations_v1(requested_by, server_sequence desc, id)
  where requested_by is not null;
create index if not exists pachanga_payment_failure_subscription_idx
  on private.pachanga_stripe_payment_failures_v1(subscription_projection_id, server_sequence desc, id)
  where subscription_projection_id is not null;
create index if not exists pachanga_payment_failure_invoice_idx
  on private.pachanga_stripe_payment_failures_v1(invoice_projection_id, server_sequence desc, id)
  where invoice_projection_id is not null;
create index if not exists pachanga_competition_entitlement_billing_plan_idx
  on public.pachanga_competition_entitlement_grants(billing_plan_revision_id, status, server_sequence desc, id)
  where billing_plan_revision_id is not null;

create or replace function private.pachanga_billing_normalized_payload_is_safe_v1(payload jsonb)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_typeof(payload) = 'object'
    and not exists (
      select 1
      from jsonb_object_keys(payload) keys(key)
      where keys.key not in (
        'objectType', 'objectId', 'customerId', 'subscriptionId', 'priceId',
        'subscriptionStatus', 'billingInterval', 'currentPeriodStart', 'currentPeriodEnd',
        'cancelAtPeriodEnd', 'canceledAt', 'invoiceId', 'invoiceStatus', 'currency',
        'amountDue', 'amountPaid', 'hostedInvoiceUrl', 'invoicePdfUrl', 'dueAt', 'paidAt',
        'failureCode', 'metadataOperationId', 'checkoutSessionId', 'checkoutStatus',
        'locale', 'billingCountry', 'taxConfigurationStatus'
      )
    );
$$;

alter table private.pachanga_stripe_webhook_events_v2
  drop constraint if exists pachanga_stripe_webhook_events_v2_safe_payload_check,
  add constraint pachanga_stripe_webhook_events_v2_safe_payload_check
    check (private.pachanga_billing_normalized_payload_is_safe_v1(normalized_payload)) not valid;
alter table private.pachanga_stripe_webhook_events_v2
  validate constraint pachanga_stripe_webhook_events_v2_safe_payload_check;

create or replace function private.pachanga_organizer_effective_limit_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_limit_key text
)
returns bigint
language sql
security definer
stable
set search_path = pg_catalog
as $$
  with matching as materialized (
    select limits.limit_value
    from private.pachanga_organizer_access_grants_v1 access
    join public.pachanga_organizer_plan_limits limits
      on limits.plan_revision_id = access.plan_revision_id
     and limits.limit_key = target_limit_key
    where access.organizer_kind = upper(target_organizer_kind)
      and ((access.organizer_kind = 'TEAM' and access.organizer_group_id = target_organizer_id)
        or (access.organizer_kind = 'CLUB' and access.organizer_club_id = target_organizer_id))
      and access.status in ('active', 'grace')
      and access.valid_from <= clock_timestamp()
      and (access.valid_until is null or access.valid_until > clock_timestamp())
  )
  select case
    when not exists (select 1 from matching) then null
    when exists (select 1 from matching where limit_value is null) then null
    else (select max(limit_value) from matching)
  end;
$$;

create or replace function private.pachanga_organizer_billing_usage_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  with organizer_competitions as materialized (
    select competitions.id, competitions.competition_type, competitions.visibility, competitions.status
    from public.pachanga_competitions competitions
    where competitions.organizer_kind = upper(target_organizer_kind)
      and ((competitions.organizer_kind = 'TEAM' and competitions.organizer_group_id = target_organizer_id)
        or (competitions.organizer_kind = 'CLUB' and competitions.organizer_club_id = target_organizer_id))
  )
  select jsonb_build_object(
    'activeCompetitions', (select count(*) from organizer_competitions where status <> 'cancelled'),
    'activeEditions', (
      select count(*)
      from public.pachanga_competition_editions editions
      join organizer_competitions competitions on competitions.id = editions.competition_id
      where editions.status not in ('completed', 'archived', 'cancelled')
    ),
    'publicCompetitions', (select count(*) from organizer_competitions where visibility = 'public' and status <> 'cancelled'),
    'leagueCreation', (select count(*) from organizer_competitions where competition_type = 'LEAGUE' and status <> 'cancelled'),
    'tournamentCreation', (select count(*) from organizer_competitions where competition_type = 'TOURNAMENT' and status <> 'cancelled'),
    'staffSeats', (
      select count(*)
      from public.pachanga_competition_staff_assignments staff
      join organizer_competitions competitions on competitions.id = staff.competition_id
      where staff.status = 'active'
    ),
    'scheduledMatches', (
      select count(*)
      from public.pachanga_competition_match_contexts contexts
      join organizer_competitions competitions on competitions.id = contexts.competition_id
      where contexts.status not in ('cancelled', 'completed')
    ),
    'refereeAssignments', (
      select count(*)
      from public.pachanga_referee_assignments assignments
      join organizer_competitions competitions
        on competitions.id = coalesce(assignments.requester_competition_id, assignments.competition_id)
      where assignments.status not in ('declined', 'cancelled', 'expired', 'replaced', 'completed')
    )
  );
$$;

create or replace function private.pachanga_billing_require_limit_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_limit_key text,
  current_usage bigint,
  requested_increment bigint default 1
)
returns void
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare approved_limit bigint;
begin
  approved_limit := private.pachanga_organizer_effective_limit_v1(
    target_organizer_kind, target_organizer_id, target_limit_key
  );
  if approved_limit is not null
     and greatest(coalesce(current_usage, 0), 0) + greatest(coalesce(requested_increment, 1), 0) > approved_limit then
    raise exception 'ORGANIZER_PLAN_LIMIT_REACHED:%', target_limit_key using errcode = '42501';
  end if;
end;
$$;

create or replace function private.pachanga_billing_guard_competition_limits_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare organizer_id uuid;
declare usage jsonb;
begin
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.foundation_enabled then return new; end if;
  organizer_id := case when new.organizer_kind = 'TEAM' then new.organizer_group_id else new.organizer_club_id end;
  if tg_op = 'INSERT'
     and not private.pachanga_organizer_billing_creation_allowed_v1(
       new.organizer_kind,
       organizer_id
     ) then
    raise exception 'ORGANIZER_PLAN_CREATION_BLOCKED' using errcode = '42501';
  end if;
  usage := private.pachanga_organizer_billing_usage_v1(new.organizer_kind, organizer_id);
  if tg_op = 'INSERT' then
    perform private.pachanga_billing_require_limit_v1(new.organizer_kind, organizer_id,
      'activeCompetitions', coalesce((usage ->> 'activeCompetitions')::bigint, 0), 1);
    perform private.pachanga_billing_require_limit_v1(new.organizer_kind, organizer_id,
      case when new.competition_type = 'LEAGUE' then 'leagueCreation' else 'tournamentCreation' end,
      coalesce((usage ->> case when new.competition_type = 'LEAGUE' then 'leagueCreation' else 'tournamentCreation' end)::bigint, 0), 1);
    if new.visibility = 'public' then
      perform private.pachanga_billing_require_limit_v1(new.organizer_kind, organizer_id,
        'publicCompetitions', coalesce((usage ->> 'publicCompetitions')::bigint, 0), 1);
    end if;
  elsif old.visibility <> 'public' and new.visibility = 'public' then
    perform private.pachanga_billing_require_limit_v1(new.organizer_kind, organizer_id,
      'publicCompetitions', coalesce((usage ->> 'publicCompetitions')::bigint, 0), 1);
  end if;
  return new;
end;
$$;

create or replace function private.pachanga_billing_guard_edition_limit_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition public.pachanga_competitions%rowtype;
declare organizer_id uuid;
declare usage jsonb;
declare settings private.pachanga_organizer_billing_settings%rowtype;
begin
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.foundation_enabled then return new; end if;
  select * into selected_competition from public.pachanga_competitions where id = new.competition_id;
  organizer_id := case when selected_competition.organizer_kind = 'TEAM'
    then selected_competition.organizer_group_id else selected_competition.organizer_club_id end;
  usage := private.pachanga_organizer_billing_usage_v1(selected_competition.organizer_kind, organizer_id);
  perform private.pachanga_billing_require_limit_v1(selected_competition.organizer_kind, organizer_id,
    'activeEditions', coalesce((usage ->> 'activeEditions')::bigint, 0), 1);
  return new;
end;
$$;

create or replace function private.pachanga_billing_guard_entry_limit_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition public.pachanga_competitions%rowtype;
declare organizer_id uuid;
declare accepted_count bigint;
begin
  if new.status not in ('accepted', 'active')
     or (tg_op = 'UPDATE' and old.status in ('accepted', 'active')) then return new; end if;
  if not (select foundation_enabled from private.pachanga_organizer_billing_settings where singleton) then return new; end if;
  select * into selected_competition from public.pachanga_competitions where id = new.competition_id;
  organizer_id := case when selected_competition.organizer_kind = 'TEAM'
    then selected_competition.organizer_group_id else selected_competition.organizer_club_id end;
  select count(*) into accepted_count
  from public.pachanga_competition_entries entries
  where entries.competition_id = new.competition_id
    and entries.status in ('accepted', 'active')
    and entries.id <> new.id;
  perform private.pachanga_billing_require_limit_v1(selected_competition.organizer_kind, organizer_id,
    'maxTeamsPerCompetition', accepted_count, 1);
  return new;
end;
$$;

create or replace function private.pachanga_billing_guard_staff_limit_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition public.pachanga_competitions%rowtype;
declare organizer_id uuid;
declare active_count bigint;
begin
  if new.status <> 'active' or (tg_op = 'UPDATE' and old.status = 'active') then return new; end if;
  if not (select foundation_enabled from private.pachanga_organizer_billing_settings where singleton) then return new; end if;
  select * into selected_competition from public.pachanga_competitions where id = new.competition_id;
  organizer_id := case when selected_competition.organizer_kind = 'TEAM'
    then selected_competition.organizer_group_id else selected_competition.organizer_club_id end;
  select count(*) into active_count
  from public.pachanga_competition_staff_assignments assignments
  join public.pachanga_competitions competitions on competitions.id = assignments.competition_id
  where competitions.organizer_kind = selected_competition.organizer_kind
    and ((competitions.organizer_kind = 'TEAM' and competitions.organizer_group_id = selected_competition.organizer_group_id)
      or (competitions.organizer_kind = 'CLUB' and competitions.organizer_club_id = selected_competition.organizer_club_id))
    and assignments.status = 'active' and assignments.id <> new.id;
  perform private.pachanga_billing_require_limit_v1(selected_competition.organizer_kind, organizer_id,
    'staffSeats', active_count, 1);
  return new;
end;
$$;

drop trigger if exists pachanga_billing_guard_competition_limits_v1 on public.pachanga_competitions;
create trigger pachanga_billing_guard_competition_limits_v1
before insert or update of visibility on public.pachanga_competitions
for each row execute function private.pachanga_billing_guard_competition_limits_v1();

drop trigger if exists pachanga_billing_guard_edition_limit_v1 on public.pachanga_competition_editions;
create trigger pachanga_billing_guard_edition_limit_v1
before insert on public.pachanga_competition_editions
for each row execute function private.pachanga_billing_guard_edition_limit_v1();

drop trigger if exists pachanga_billing_guard_entry_limit_v1 on public.pachanga_competition_entries;
create trigger pachanga_billing_guard_entry_limit_v1
before insert or update of status on public.pachanga_competition_entries
for each row execute function private.pachanga_billing_guard_entry_limit_v1();

drop trigger if exists pachanga_billing_guard_staff_limit_v1 on public.pachanga_competition_staff_assignments;
create trigger pachanga_billing_guard_staff_limit_v1
before insert or update of status on public.pachanga_competition_staff_assignments
for each row execute function private.pachanga_billing_guard_staff_limit_v1();

create or replace function public.get_my_pachanga_organizer_usage_v1(
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
declare usage jsonb;
declare limits jsonb;
begin
  if actor_id is null or target_organizer_id is null
     or not private.pachanga_billing_owner_can_manage_v1(normalized_kind, target_organizer_id, actor_id) then
    raise exception 'BILLING_OWNER_REQUIRED' using errcode = '42501';
  end if;
  usage := private.pachanga_organizer_billing_usage_v1(normalized_kind, target_organizer_id);
  select coalesce(jsonb_object_agg(keys.key,
    private.pachanga_organizer_effective_limit_v1(normalized_kind, target_organizer_id, keys.key)
    order by keys.key), '{}'::jsonb)
    into limits
  from (values
    ('activeCompetitions'), ('activeEditions'), ('maxTeamsPerCompetition'),
    ('publicCompetitions'), ('leagueCreation'), ('tournamentCreation'),
    ('staffSeats'), ('scheduledMatches'), ('refereeAssignments'), ('storageDocuments')
  ) keys(key);
  return jsonb_build_object(
    'organizerKind', normalized_kind,
    'organizerId', target_organizer_id,
    'usage', usage,
    'limits', limits,
    'generatedAt', clock_timestamp()
  );
end;
$$;

create or replace function private.pachanga_billing_guard_legacy_group_fields_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if (select foundation_enabled from private.pachanga_organizer_billing_settings where singleton)
     and not private.pachanga_competition_is_service_authority_v1()
     and (
       new.billing_status is distinct from old.billing_status
       or new.stripe_customer_id is distinct from old.stripe_customer_id
       or new.stripe_subscription_id is distinct from old.stripe_subscription_id
       or new.stripe_price_id is distinct from old.stripe_price_id
       or new.stripe_current_period_end is distinct from old.stripe_current_period_end
       or new.billing_interval is distinct from old.billing_interval
     ) then
    raise exception 'BILLING_SERVER_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_guard_legacy_group_fields_v1 on public.pachanga_groups;
create trigger pachanga_billing_guard_legacy_group_fields_v1
before update of billing_status, stripe_customer_id, stripe_subscription_id,
  stripe_price_id, stripe_current_period_end, billing_interval
on public.pachanga_groups
for each row execute function private.pachanga_billing_guard_legacy_group_fields_v1();

create or replace function public.process_pachanga_billing_expirations_service_v1(
  operation_id uuid,
  batch_size integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare safe_limit integer := least(greatest(coalesce(batch_size, 100), 1), 500);
declare prior private.pachanga_organizer_billing_operation_receipts_v1%rowtype;
declare subscription private.pachanga_stripe_subscription_projections_v1%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare access private.pachanga_organizer_access_grants_v1%rowtype;
declare continuity private.pachanga_competition_billing_continuity_grants_v1%rowtype;
declare request_hash text;
declare sequence_value bigint;
declare subscription_count integer := 0;
declare access_count integer := 0;
declare continuity_count integer := 0;
declare checkout_count integer := 0;
declare portal_count integer := 0;
declare response jsonb;
begin
  perform private.pachanga_billing_require_service_v1();
  if operation_id is null then raise exception 'BILLING_OPERATION_ID_REQUIRED' using errcode = '22023'; end if;
  request_hash := private.pachanga_billing_request_hash_v1(
    'billing.expire', 'global', 0, jsonb_build_object('batchSize', safe_limit)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 77030));
  select * into prior
  from private.pachanga_organizer_billing_operation_receipts_v1 receipts
  where receipts.operation_id = process_pachanga_billing_expirations_service_v1.operation_id;
  if found then
    if prior.request_hash <> request_hash then raise exception 'BILLING_OPERATION_ID_REUSED' using errcode = 'PT409'; end if;
    return prior.response || jsonb_build_object('replayed', true);
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');

  for subscription in
    select projections.*
    from private.pachanga_stripe_subscription_projections_v1 projections
    where (
        (projections.status = 'past_due' and projections.grace_ends_at <= clock_timestamp())
        or (projections.status = 'canceled' and projections.current_period_end <= clock_timestamp())
      )
      and (
        not exists (
          select 1 from private.pachanga_organizer_access_grants_v1 projected_access
          where projected_access.subscription_projection_id = projections.id
        )
        or exists (
          select 1 from private.pachanga_organizer_access_grants_v1 projected_access
          where projected_access.subscription_projection_id = projections.id
            and projected_access.status in ('active', 'grace')
        )
      )
    order by projections.server_sequence, projections.id
    for update skip locked
    limit safe_limit
  loop
    perform private.pachanga_billing_sync_entitlement_v1(subscription.id, 'Server clock expired subscription access');
    subscription_count := subscription_count + 1;
    select * into account from private.pachanga_organizer_billing_accounts where id = subscription.billing_account_id;
    if account.billing_contact_user_id is not null then
      perform private.pachanga_notify_v1(account.billing_contact_user_id,
        'billing_warning_access_blocked', 'Acceso de creacion bloqueado',
        'El periodo de gracia ha terminado. Las ediciones con continuidad pueden concluir.',
        '/ajustes/facturacion', jsonb_build_object('billingAccountId', account.id),
        'billing-expired:' || subscription.id::text || ':' || subscription.revision::text);
    end if;
  end loop;

  for access in
    select grants.*
    from private.pachanga_organizer_access_grants_v1 grants
    where grants.access_source <> 'SUBSCRIPTION' and grants.status in ('active', 'grace')
      and grants.valid_until is not null and grants.valid_until <= clock_timestamp()
    order by grants.server_sequence, grants.id
    for update skip locked
    limit safe_limit
  loop
    update private.pachanga_organizer_access_grants_v1 grants set
      status = 'expired', revoked_at = clock_timestamp(),
      revision = grants.revision + 1, server_sequence = sequence_value, updated_at = clock_timestamp()
    where grants.id = access.id;
    update public.pachanga_competition_entitlement_grants grants set
      status = 'revoked', revoked_at = clock_timestamp(),
      revision = grants.revision + 1, server_sequence = sequence_value, updated_at = clock_timestamp()
    where grants.billing_access_grant_id = access.id and grants.status = 'active';
    access_count := access_count + 1;
  end loop;

  for continuity in
    select grants.*
    from private.pachanga_competition_billing_continuity_grants_v1 grants
    join public.pachanga_competition_editions editions on editions.id = grants.edition_id
    where grants.status = 'active'
      and (grants.continuity_until <= clock_timestamp()
        or editions.status in ('completed', 'archived', 'cancelled'))
    order by grants.server_sequence, grants.id
    for update of grants skip locked
    limit safe_limit
  loop
    update private.pachanga_competition_billing_continuity_grants_v1 grants set
      status = case when grants.continuity_until <= clock_timestamp() then 'expired' else 'completed' end,
      revision = grants.revision + 1, server_sequence = sequence_value, updated_at = clock_timestamp()
    where grants.id = continuity.id;
    continuity_count := continuity_count + 1;
  end loop;

  update private.pachanga_organizer_checkout_intents_v1 intents set
    status = 'EXPIRED', updated_at = clock_timestamp(), server_sequence = sequence_value
  where intents.id in (
    select rows.id from private.pachanga_organizer_checkout_intents_v1 rows
    where rows.status in ('PREPARED', 'SESSION_CREATED') and rows.expires_at <= clock_timestamp()
    order by rows.server_sequence, rows.id limit safe_limit
  );
  get diagnostics checkout_count = row_count;
  update private.pachanga_organizer_portal_intents_v1 intents set
    status = 'EXPIRED', updated_at = clock_timestamp(), server_sequence = sequence_value
  where intents.id in (
    select rows.id from private.pachanga_organizer_portal_intents_v1 rows
    where rows.status = 'SESSION_CREATED' and rows.expires_at <= clock_timestamp()
    order by rows.server_sequence, rows.id limit safe_limit
  );
  get diagnostics portal_count = row_count;

  response := jsonb_build_object(
    'replayed', false,
    'subscriptionsExpired', subscription_count,
    'manualAccessExpired', access_count,
    'continuityClosed', continuity_count,
    'checkoutIntentsExpired', checkout_count,
    'portalIntentsExpired', portal_count,
    'confirmedRevision', subscription_count + access_count + continuity_count + checkout_count + portal_count,
    'serverSequence', sequence_value
  );
  perform private.pachanga_billing_store_receipt_v1(
    operation_id, null, 'service_authority', 'billing.expire', 'organizer_billing',
    'global', request_hash,
    subscription_count + access_count + continuity_count + checkout_count + portal_count,
    sequence_value, '{}'::jsonb, response, 'BILLING_EXPIRATIONS_PROCESSED',
    response - 'replayed'
  );
  return response;
end;
$$;

alter table public.pachanga_organizer_plan_catalog force row level security;
alter table public.pachanga_organizer_plan_revisions force row level security;
alter table public.pachanga_organizer_plan_features force row level security;
alter table public.pachanga_organizer_plan_limits force row level security;

update private.pachanga_organizer_billing_settings settings set
  foundation_enabled = false,
  plan_catalog_enabled = false,
  partner_grants_enabled = false,
  billing_accounts_enabled = false,
  organizer_ui_enabled = false,
  webhook_ingest_enabled = false,
  stripe_sandbox_enabled = false,
  portal_enabled = false,
  reconciliation_enabled = false,
  live_checkout_enabled = false,
  demo_world_v28_enabled = false,
  live_prices_approved = false,
  tax_health = 'UNCONFIGURED',
  updated_at = clock_timestamp()
where singleton;

revoke all on function private.pachanga_billing_normalized_payload_is_safe_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_effective_limit_v1(text, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_billing_usage_v1(text, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_billing_require_limit_v1(text, uuid, text, bigint, bigint) from public, anon, authenticated;
revoke all on function private.pachanga_billing_guard_competition_limits_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_guard_edition_limit_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_guard_entry_limit_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_guard_staff_limit_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_guard_legacy_group_fields_v1() from public, anon, authenticated;

revoke all on function public.get_my_pachanga_organizer_usage_v1(text, uuid) from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_organizer_usage_v1(text, uuid) to authenticated, service_role;

revoke all on function public.process_pachanga_billing_expirations_service_v1(uuid, integer) from public, anon, authenticated, service_role;
grant execute on function public.process_pachanga_billing_expirations_service_v1(uuid, integer) to service_role;

comment on function private.pachanga_organizer_effective_limit_v1(text, uuid, text) is
  'Returns only approved persisted plan limits. Null means no commercial value has been approved and must never be invented by a client.';
comment on function public.process_pachanga_billing_expirations_service_v1(uuid, integer) is
  'Idempotent server-clock processor for grace, cancellation, manual access, continuity and hosted-session expiry.';
comment on trigger pachanga_billing_guard_legacy_group_fields_v1 on public.pachanga_groups is
  'Authenticated clients cannot make legacy Stripe columns compete with the Wave 7B canonical projections.';
