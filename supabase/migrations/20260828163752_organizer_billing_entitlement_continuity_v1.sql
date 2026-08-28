-- Wave 7B: authoritative access bundles, entitlement projection and continuity.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table if not exists private.pachanga_organizer_access_grants_v1 (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  billing_account_id uuid references private.pachanga_organizer_billing_accounts(id) on delete restrict,
  subscription_projection_id uuid references private.pachanga_stripe_subscription_projections_v1(id) on delete restrict,
  plan_revision_id uuid not null references public.pachanga_organizer_plan_revisions(id) on delete restrict,
  access_source text not null,
  source_reference text not null,
  status text not null default 'active',
  valid_from timestamptz not null default clock_timestamp(),
  valid_until timestamptz,
  reason text not null,
  granted_by uuid references auth.users(id) on delete set null,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  restored_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (access_source in ('SUBSCRIPTION', 'PARTNERSHIP', 'PROMOTION', 'PRIVATE_BETA', 'PLATFORM_GRANT')),
  check (status in ('active', 'grace', 'continuity', 'revoked', 'expired')),
  check (length(trim(source_reference)) between 3 and 180),
  check (length(trim(reason)) between 3 and 1200),
  check (valid_until is null or valid_until > valid_from),
  check (revision >= 1),
  check (
    (access_source = 'SUBSCRIPTION' and billing_account_id is not null and subscription_projection_id is not null)
    or (access_source <> 'SUBSCRIPTION' and subscription_projection_id is null)
  ),
  check (
    (status in ('revoked', 'expired') and revoked_at is not null)
    or status in ('active', 'grace', 'continuity')
  )
);

create unique index if not exists pachanga_organizer_access_subscription_idx
  on private.pachanga_organizer_access_grants_v1(subscription_projection_id)
  where subscription_projection_id is not null;
create unique index if not exists pachanga_organizer_access_source_reference_idx
  on private.pachanga_organizer_access_grants_v1(organizer_kind, source_reference);
create index if not exists pachanga_organizer_access_team_active_idx
  on private.pachanga_organizer_access_grants_v1(organizer_group_id, status, valid_until, server_sequence desc)
  where organizer_kind = 'TEAM' and status in ('active', 'grace', 'continuity');
create index if not exists pachanga_organizer_access_club_active_idx
  on private.pachanga_organizer_access_grants_v1(organizer_club_id, status, valid_until, server_sequence desc)
  where organizer_kind = 'CLUB' and status in ('active', 'grace', 'continuity');

alter table public.pachanga_competition_entitlement_grants
  add column if not exists billing_access_grant_id uuid references private.pachanga_organizer_access_grants_v1(id) on delete restrict,
  add column if not exists billing_subscription_projection_id uuid references private.pachanga_stripe_subscription_projections_v1(id) on delete restrict,
  add column if not exists billing_plan_revision_id uuid references public.pachanga_organizer_plan_revisions(id) on delete restrict;

drop index if exists public.pachanga_competition_entitlement_team_active_idx;
drop index if exists public.pachanga_competition_entitlement_club_active_idx;

create unique index pachanga_competition_entitlement_team_legacy_active_idx
  on public.pachanga_competition_entitlement_grants(organizer_group_id, capability)
  where status = 'active' and organizer_kind = 'TEAM' and billing_access_grant_id is null;
create unique index pachanga_competition_entitlement_club_legacy_active_idx
  on public.pachanga_competition_entitlement_grants(organizer_club_id, capability)
  where status = 'active' and organizer_kind = 'CLUB' and billing_access_grant_id is null;
create unique index pachanga_competition_entitlement_team_billing_active_idx
  on public.pachanga_competition_entitlement_grants(organizer_group_id, capability, billing_access_grant_id)
  where status = 'active' and organizer_kind = 'TEAM' and billing_access_grant_id is not null;
create unique index pachanga_competition_entitlement_club_billing_active_idx
  on public.pachanga_competition_entitlement_grants(organizer_club_id, capability, billing_access_grant_id)
  where status = 'active' and organizer_kind = 'CLUB' and billing_access_grant_id is not null;
create index if not exists pachanga_competition_entitlement_billing_access_idx
  on public.pachanga_competition_entitlement_grants(billing_access_grant_id, status, capability)
  where billing_access_grant_id is not null;
create index if not exists pachanga_competition_entitlement_subscription_idx
  on public.pachanga_competition_entitlement_grants(billing_subscription_projection_id, status)
  where billing_subscription_projection_id is not null;

create table if not exists private.pachanga_competition_billing_continuity_grants_v1 (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null unique references public.pachanga_competition_editions(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  billing_access_grant_id uuid not null references private.pachanga_organizer_access_grants_v1(id) on delete restrict,
  plan_revision_id uuid not null references public.pachanga_organizer_plan_revisions(id) on delete restrict,
  edition_planned_end date,
  continuity_until timestamptz not null,
  limits_snapshot jsonb not null default '{}'::jsonb,
  reason text not null,
  status text not null default 'active',
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (status in ('active', 'completed', 'revoked', 'expired')),
  check (length(trim(reason)) between 3 and 1200),
  check (revision >= 1),
  check ((status = 'revoked' and revoked_at is not null) or status <> 'revoked')
);

create index if not exists pachanga_billing_continuity_competition_idx
  on private.pachanga_competition_billing_continuity_grants_v1(competition_id, status, continuity_until, id);
create index if not exists pachanga_billing_continuity_access_idx
  on private.pachanga_competition_billing_continuity_grants_v1(billing_access_grant_id, status, continuity_until, id);
create index if not exists pachanga_billing_continuity_team_idx
  on private.pachanga_competition_billing_continuity_grants_v1(organizer_group_id, continuity_until desc, id)
  where organizer_kind = 'TEAM' and status = 'active';
create index if not exists pachanga_billing_continuity_club_idx
  on private.pachanga_competition_billing_continuity_grants_v1(organizer_club_id, continuity_until desc, id)
  where organizer_kind = 'CLUB' and status = 'active';

create or replace function private.pachanga_organizer_billing_creation_allowed_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns boolean
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with authority_time as materialized (select clock_timestamp() as checked_at)
  select exists (
    select 1
    from public.pachanga_competition_entitlement_grants grants
    left join private.pachanga_organizer_access_grants_v1 access
      on access.id = grants.billing_access_grant_id
    cross join authority_time
    where grants.organizer_kind = upper(target_organizer_kind)
      and (
        (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
        or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
      )
      and grants.capability = 'competition_create'
      and grants.status = 'active'
      and grants.valid_from <= authority_time.checked_at
      and (grants.expires_at is null or grants.expires_at > authority_time.checked_at)
      and (access.id is null or access.status in ('active', 'grace'))
  );
$$;

create or replace function private.pachanga_billing_guard_new_edition_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition public.pachanga_competitions%rowtype;
declare settings private.pachanga_organizer_billing_settings%rowtype;
begin
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.foundation_enabled then return new; end if;
  select * into selected_competition from public.pachanga_competitions where id = new.competition_id;
  if not found then return new; end if;
  if not private.pachanga_organizer_billing_creation_allowed_v1(
    selected_competition.organizer_kind,
    case when selected_competition.organizer_kind = 'TEAM'
      then selected_competition.organizer_group_id else selected_competition.organizer_club_id end
  ) then
    raise exception 'ORGANIZER_PLAN_CREATION_BLOCKED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_guard_new_edition_v1 on public.pachanga_competition_editions;
create trigger pachanga_billing_guard_new_edition_v1
before insert on public.pachanga_competition_editions
for each row execute function private.pachanga_billing_guard_new_edition_v1();

create or replace function private.pachanga_billing_snapshot_continuity_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition public.pachanga_competitions%rowtype;
declare selected_access private.pachanga_organizer_access_grants_v1%rowtype;
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare snapshot_until timestamptz;
declare limits_snapshot jsonb;
begin
  if new.status <> 'active' or (tg_op = 'UPDATE' and old.status = 'active') then return new; end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  if not settings.foundation_enabled then return new; end if;
  select * into selected_competition from public.pachanga_competitions where id = new.competition_id;
  select access.* into selected_access
  from private.pachanga_organizer_access_grants_v1 access
  where access.organizer_kind = selected_competition.organizer_kind
    and (
      (access.organizer_kind = 'TEAM' and access.organizer_group_id = selected_competition.organizer_group_id)
      or (access.organizer_kind = 'CLUB' and access.organizer_club_id = selected_competition.organizer_club_id)
    )
    and access.access_source = 'SUBSCRIPTION'
    and access.status in ('active', 'grace')
    and access.valid_from <= clock_timestamp()
    and (access.valid_until is null or access.valid_until > clock_timestamp())
  order by access.server_sequence desc, access.id desc
  limit 1;
  if not found then return new; end if;
  snapshot_until := least(
    clock_timestamp() + make_interval(days => settings.continuity_max_days),
    coalesce((new.ends_at + 1)::timestamptz, clock_timestamp() + make_interval(days => settings.continuity_max_days))
  );
  select coalesce(jsonb_object_agg(limits.limit_key, limits.limit_value order by limits.limit_key), '{}'::jsonb)
    into limits_snapshot
  from public.pachanga_organizer_plan_limits limits
  where limits.plan_revision_id = selected_access.plan_revision_id;
  insert into private.pachanga_competition_billing_continuity_grants_v1(
    edition_id, competition_id, organizer_kind, organizer_group_id, organizer_club_id,
    billing_access_grant_id, plan_revision_id, edition_planned_end, continuity_until,
    limits_snapshot, reason
  ) values (
    new.id, new.competition_id, selected_competition.organizer_kind,
    selected_competition.organizer_group_id, selected_competition.organizer_club_id,
    selected_access.id, selected_access.plan_revision_id, new.ends_at, snapshot_until,
    limits_snapshot, 'Edition activated while organizer subscription entitlement was valid'
  ) on conflict (edition_id) do nothing;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_snapshot_continuity_v1 on public.pachanga_competition_editions;
create trigger pachanga_billing_snapshot_continuity_v1
after insert or update of status on public.pachanga_competition_editions
for each row execute function private.pachanga_billing_snapshot_continuity_v1();

create or replace function private.pachanga_billing_guard_continuity_extension_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare continuity private.pachanga_competition_billing_continuity_grants_v1%rowtype;
begin
  if new.ends_at is not distinct from old.ends_at then return new; end if;
  select * into continuity
  from private.pachanga_competition_billing_continuity_grants_v1 grants
  where grants.edition_id = new.id and grants.status = 'active'
  for update;
  if found and new.ends_at is not null
     and (new.ends_at + 1)::timestamptz > continuity.continuity_until then
    raise exception 'BILLING_CONTINUITY_EXTENSION_BLOCKED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_guard_continuity_extension_v1 on public.pachanga_competition_editions;
create trigger pachanga_billing_guard_continuity_extension_v1
before update of ends_at on public.pachanga_competition_editions
for each row execute function private.pachanga_billing_guard_continuity_extension_v1();

create or replace function private.pachanga_billing_sync_entitlement_v1(
  target_subscription_projection_id uuid,
  target_reason text default 'Stripe subscription projection changed'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare subscription private.pachanga_stripe_subscription_projections_v1%rowtype;
declare account private.pachanga_organizer_billing_accounts%rowtype;
declare access private.pachanga_organizer_access_grants_v1%rowtype;
declare settings private.pachanga_organizer_billing_settings%rowtype;
declare capability_row record;
declare now_at timestamptz := clock_timestamp();
declare effective_status text;
declare effective_until timestamptz;
declare continuity_until timestamptz;
declare sequence_value bigint;
begin
  if not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  select * into settings from private.pachanga_organizer_billing_settings where singleton;
  select * into subscription
  from private.pachanga_stripe_subscription_projections_v1 projections
  where projections.id = target_subscription_projection_id
  for update;
  if not found then raise exception 'BILLING_SUBSCRIPTION_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.id = subscription.billing_account_id
  for update;
  if subscription.plan_revision_id is null then
    raise exception 'BILLING_UNKNOWN_PRICE' using errcode = '22023';
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');

  if subscription.status in ('active', 'trialing') then
    effective_status := 'active';
    effective_until := case when subscription.cancel_at_period_end then subscription.current_period_end else null end;
  elsif subscription.status = 'past_due' and subscription.grace_ends_at > now_at then
    effective_status := 'grace';
    effective_until := subscription.grace_ends_at;
  elsif subscription.status = 'canceled' and subscription.current_period_end > now_at then
    effective_status := 'active';
    effective_until := subscription.current_period_end;
  else
    select max(grants.continuity_until) into continuity_until
    from private.pachanga_competition_billing_continuity_grants_v1 grants
    join private.pachanga_organizer_access_grants_v1 source on source.id = grants.billing_access_grant_id
    where source.subscription_projection_id = subscription.id
      and grants.status = 'active'
      and grants.continuity_until > now_at;
    if continuity_until is not null then
      effective_status := 'continuity';
      effective_until := continuity_until;
    else
      effective_status := case when subscription.status = 'incomplete_expired' then 'expired' else 'revoked' end;
      effective_until := null;
    end if;
  end if;

  insert into private.pachanga_organizer_access_grants_v1(
    organizer_kind, organizer_group_id, organizer_club_id, billing_account_id,
    subscription_projection_id, plan_revision_id, access_source, source_reference,
    status, valid_from, valid_until, reason, revision, server_sequence, revoked_at
  ) values (
    account.organizer_kind, account.organizer_group_id, account.organizer_club_id, account.id,
    subscription.id, subscription.plan_revision_id, 'SUBSCRIPTION',
    'subscription:' || subscription.stripe_mode || ':' || subscription.stripe_subscription_id,
    effective_status, now_at, effective_until, left(target_reason, 1200), 1, sequence_value,
    case when effective_status in ('revoked', 'expired') then now_at else null end
  ) on conflict (subscription_projection_id) where subscription_projection_id is not null do update set
    plan_revision_id = excluded.plan_revision_id,
    status = excluded.status,
    valid_until = excluded.valid_until,
    reason = excluded.reason,
    revoked_at = excluded.revoked_at,
    revision = private.pachanga_organizer_access_grants_v1.revision + 1,
    server_sequence = excluded.server_sequence,
    updated_at = now_at
  returning * into access;

  if effective_status in ('active', 'grace', 'continuity') then
    for capability_row in
      select features.feature_key
      from public.pachanga_organizer_plan_features features
      where features.plan_revision_id = subscription.plan_revision_id
        and features.enabled and features.entitlement_capability
      order by features.display_order, features.feature_key
    loop
      if effective_status = 'continuity'
         and capability_row.feature_key in ('competition_create', 'tournament_create') then
        update public.pachanga_competition_entitlement_grants grants set
          status = 'revoked', revoked_at = now_at, revision = grants.revision + 1,
          server_sequence = sequence_value, updated_at = now_at
        where grants.billing_access_grant_id = access.id
          and grants.capability = capability_row.feature_key and grants.status = 'active';
      else
        if not exists (
          select 1 from public.pachanga_competition_entitlement_grants grants
          where grants.billing_access_grant_id = access.id
            and grants.capability = capability_row.feature_key
            and grants.status = 'active'
        ) then
          insert into public.pachanga_competition_entitlement_grants(
            organizer_kind, organizer_group_id, organizer_club_id, capability,
            grant_source, status, valid_from, expires_at, reason, revision,
            server_sequence, granted_by, billing_access_grant_id,
            billing_subscription_projection_id, billing_plan_revision_id,
            created_at, updated_at
          ) values (
            account.organizer_kind, account.organizer_group_id, account.organizer_club_id,
            capability_row.feature_key, 'subscription', 'active', now_at, effective_until,
            left('WAVE7B SUBSCRIPTION: ' || target_reason, 1200), 1, sequence_value, null,
            access.id, subscription.id, subscription.plan_revision_id, now_at, now_at
          );
        else
          update public.pachanga_competition_entitlement_grants grants set
            expires_at = effective_until, billing_plan_revision_id = subscription.plan_revision_id,
            revision = grants.revision + 1, server_sequence = sequence_value, updated_at = now_at
          where grants.billing_access_grant_id = access.id
            and grants.capability = capability_row.feature_key and grants.status = 'active';
        end if;
      end if;
    end loop;
  else
    update public.pachanga_competition_entitlement_grants grants set
      status = 'revoked', revoked_at = now_at, revision = grants.revision + 1,
      server_sequence = sequence_value, updated_at = now_at
    where grants.billing_access_grant_id = access.id and grants.status = 'active';
  end if;

  update private.pachanga_organizer_billing_accounts accounts set
    current_plan_family = 'ORGANIZER',
    status = case
      when effective_status = 'active' then 'active'
      when effective_status = 'grace' then 'past_due'
      when effective_status = 'continuity' then 'canceled'
      when subscription.status in ('past_due', 'unpaid') then 'past_due'
      when subscription.status in ('canceled', 'incomplete_expired') then 'canceled'
      else 'blocked'
    end,
    revision = accounts.revision + 1,
    server_sequence = sequence_value,
    updated_at = now_at
  where accounts.id = account.id;
  return access.id;
end;
$$;

revoke all on function private.pachanga_organizer_billing_creation_allowed_v1(text, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_billing_guard_new_edition_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_snapshot_continuity_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_guard_continuity_extension_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_sync_entitlement_v1(uuid, text) from public, anon, authenticated;
revoke all on table private.pachanga_organizer_access_grants_v1 from public, anon, authenticated;
revoke all on table private.pachanga_competition_billing_continuity_grants_v1 from public, anon, authenticated;
grant all on table private.pachanga_organizer_access_grants_v1 to service_role;
grant all on table private.pachanga_competition_billing_continuity_grants_v1 to service_role;

comment on table private.pachanga_competition_billing_continuity_grants_v1 is
  'Immutable activation-time plan snapshot. It permits completion but never new Competition or Edition creation.';
comment on column public.pachanga_competition_entitlement_grants.billing_access_grant_id is
  'Wave 7B source bundle. Stripe revocation may only revoke rows linked to its own bundle.';
