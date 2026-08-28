-- Wave 7B: least-privilege access and Realtime invalidation.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table if not exists public.pachanga_organizer_billing_invalidations_v1 (
  scope_key text primary key,
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete cascade,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete cascade,
  entity_kind text not null,
  entity_revision bigint not null,
  server_sequence bigint not null default nextval('private.pachanga_organizer_billing_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('CATALOG', 'TEAM', 'CLUB')),
  check (
    (organizer_kind = 'CATALOG' and scope_key = 'CATALOG' and organizer_group_id is null and organizer_club_id is null)
    or (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null
      and scope_key = 'TEAM:' || organizer_group_id::text)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null
      and scope_key = 'CLUB:' || organizer_club_id::text)
  ),
  check (entity_kind ~ '^[A-Z][A-Z0-9_]{2,79}$'),
  check (entity_revision >= 0)
);

create index if not exists pachanga_billing_invalidation_team_idx
  on public.pachanga_organizer_billing_invalidations_v1(organizer_group_id, server_sequence desc)
  where organizer_kind = 'TEAM';
create index if not exists pachanga_billing_invalidation_club_idx
  on public.pachanga_organizer_billing_invalidations_v1(organizer_club_id, server_sequence desc)
  where organizer_kind = 'CLUB';

insert into public.pachanga_organizer_billing_invalidations_v1(
  scope_key, organizer_kind, entity_kind, entity_revision
) values ('CATALOG', 'CATALOG', 'PLAN_CATALOG', 0)
on conflict (scope_key) do nothing;

create or replace function private.pachanga_billing_invalidation_can_read_v1(
  target_organizer_kind text,
  target_group_id uuid,
  target_club_id uuid
)
returns boolean
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare actor_role text;
begin
  if target_organizer_kind = 'CATALOG' then return true; end if;
  if actor_id is null then return false; end if;
  if target_organizer_kind = 'TEAM'
     and private.pachanga_billing_owner_can_manage_v1('TEAM', target_group_id, actor_id) then
    return true;
  end if;
  if target_organizer_kind = 'CLUB'
     and private.pachanga_billing_owner_can_manage_v1('CLUB', target_club_id, actor_id) then
    return true;
  end if;
  actor_role := private.pachanga_platform_role_for_user_v1(actor_id);
  return actor_role is not null
    and private.pachanga_platform_capabilities_v1(actor_role) ? 'billing.read';
end;
$$;

create or replace function private.pachanga_billing_touch_invalidation_v1(
  target_organizer_kind text,
  target_group_id uuid,
  target_club_id uuid,
  target_entity_kind text,
  target_entity_revision bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
declare selected_scope text;
begin
  if normalized_kind = 'CATALOG' then
    selected_scope := 'CATALOG';
    target_group_id := null;
    target_club_id := null;
  elsif normalized_kind = 'TEAM' and target_group_id is not null and target_club_id is null then
    selected_scope := 'TEAM:' || target_group_id::text;
  elsif normalized_kind = 'CLUB' and target_club_id is not null and target_group_id is null then
    selected_scope := 'CLUB:' || target_club_id::text;
  else
    raise exception 'BILLING_INVALID_INVALIDATION_SCOPE' using errcode = '22023';
  end if;

  insert into public.pachanga_organizer_billing_invalidations_v1(
    scope_key, organizer_kind, organizer_group_id, organizer_club_id,
    entity_kind, entity_revision, server_sequence, updated_at
  ) values (
    selected_scope, normalized_kind, target_group_id, target_club_id,
    upper(trim(target_entity_kind)), greatest(coalesce(target_entity_revision, 0), 0),
    nextval('private.pachanga_organizer_billing_sequence'), clock_timestamp()
  ) on conflict (scope_key) do update set
    entity_kind = excluded.entity_kind,
    entity_revision = excluded.entity_revision,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at;
end;
$$;

create or replace function private.pachanga_billing_invalidate_catalog_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_billing_touch_invalidation_v1(
    'CATALOG', null, null, 'PLAN_CATALOG', 0
  );
  return null;
end;
$$;

create or replace function private.pachanga_billing_invalidate_organizer_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_billing_touch_invalidation_v1(
    new.organizer_kind, new.organizer_group_id, new.organizer_club_id,
    case tg_table_name
      when 'pachanga_organizer_billing_accounts' then 'BILLING_ACCOUNT'
      when 'pachanga_organizer_access_grants_v1' then 'ACCESS_GRANT'
      else 'CONTINUITY'
    end,
    coalesce(new.revision, 0)
  );
  return new;
end;
$$;

create or replace function private.pachanga_billing_invalidate_projection_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare account private.pachanga_organizer_billing_accounts%rowtype;
begin
  select * into account
  from private.pachanga_organizer_billing_accounts accounts
  where accounts.id = new.billing_account_id;
  if found then
    perform private.pachanga_billing_touch_invalidation_v1(
      account.organizer_kind, account.organizer_group_id, account.organizer_club_id,
      case tg_table_name
        when 'pachanga_stripe_subscription_projections_v1' then 'SUBSCRIPTION'
        when 'pachanga_stripe_invoice_projections_v1' then 'INVOICE'
        when 'pachanga_stripe_payment_failures_v1' then 'PAYMENT_FAILURE'
        else 'RECONCILIATION'
      end,
      coalesce(new.revision, 0)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_billing_catalog_invalidation_v1 on public.pachanga_organizer_plan_catalog;
create trigger pachanga_billing_catalog_invalidation_v1
after insert or update or delete on public.pachanga_organizer_plan_catalog
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

drop trigger if exists pachanga_billing_plan_revision_invalidation_v1 on public.pachanga_organizer_plan_revisions;
create trigger pachanga_billing_plan_revision_invalidation_v1
after insert or update or delete on public.pachanga_organizer_plan_revisions
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

drop trigger if exists pachanga_billing_plan_feature_invalidation_v1 on public.pachanga_organizer_plan_features;
create trigger pachanga_billing_plan_feature_invalidation_v1
after insert or update or delete on public.pachanga_organizer_plan_features
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

drop trigger if exists pachanga_billing_plan_limit_invalidation_v1 on public.pachanga_organizer_plan_limits;
create trigger pachanga_billing_plan_limit_invalidation_v1
after insert or update or delete on public.pachanga_organizer_plan_limits
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

drop trigger if exists pachanga_billing_price_mapping_invalidation_v1 on private.pachanga_organizer_plan_price_mappings;
create trigger pachanga_billing_price_mapping_invalidation_v1
after insert or update or delete on private.pachanga_organizer_plan_price_mappings
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

drop trigger if exists pachanga_billing_settings_invalidation_v1 on private.pachanga_organizer_billing_settings;
create trigger pachanga_billing_settings_invalidation_v1
after update on private.pachanga_organizer_billing_settings
for each statement execute function private.pachanga_billing_invalidate_catalog_trigger_v1();

drop trigger if exists pachanga_billing_account_invalidation_v1 on private.pachanga_organizer_billing_accounts;
create trigger pachanga_billing_account_invalidation_v1
after insert or update on private.pachanga_organizer_billing_accounts
for each row execute function private.pachanga_billing_invalidate_organizer_trigger_v1();

drop trigger if exists pachanga_billing_access_invalidation_v1 on private.pachanga_organizer_access_grants_v1;
create trigger pachanga_billing_access_invalidation_v1
after insert or update on private.pachanga_organizer_access_grants_v1
for each row execute function private.pachanga_billing_invalidate_organizer_trigger_v1();

drop trigger if exists pachanga_billing_continuity_invalidation_v1 on private.pachanga_competition_billing_continuity_grants_v1;
create trigger pachanga_billing_continuity_invalidation_v1
after insert or update on private.pachanga_competition_billing_continuity_grants_v1
for each row execute function private.pachanga_billing_invalidate_organizer_trigger_v1();

drop trigger if exists pachanga_billing_subscription_invalidation_v1 on private.pachanga_stripe_subscription_projections_v1;
create trigger pachanga_billing_subscription_invalidation_v1
after insert or update on private.pachanga_stripe_subscription_projections_v1
for each row execute function private.pachanga_billing_invalidate_projection_trigger_v1();

drop trigger if exists pachanga_billing_invoice_invalidation_v1 on private.pachanga_stripe_invoice_projections_v1;
create trigger pachanga_billing_invoice_invalidation_v1
after insert or update on private.pachanga_stripe_invoice_projections_v1
for each row execute function private.pachanga_billing_invalidate_projection_trigger_v1();

drop trigger if exists pachanga_billing_payment_failure_invalidation_v1 on private.pachanga_stripe_payment_failures_v1;
create trigger pachanga_billing_payment_failure_invalidation_v1
after insert or update on private.pachanga_stripe_payment_failures_v1
for each row execute function private.pachanga_billing_invalidate_projection_trigger_v1();

drop trigger if exists pachanga_billing_reconciliation_invalidation_v1 on private.pachanga_stripe_billing_reconciliations_v1;
create trigger pachanga_billing_reconciliation_invalidation_v1
after insert or update on private.pachanga_stripe_billing_reconciliations_v1
for each row execute function private.pachanga_billing_invalidate_projection_trigger_v1();

alter table public.pachanga_organizer_billing_invalidations_v1 enable row level security;
alter table public.pachanga_organizer_billing_invalidations_v1 force row level security;

drop policy if exists pachanga_billing_invalidation_select_v1 on public.pachanga_organizer_billing_invalidations_v1;
create policy pachanga_billing_invalidation_select_v1
on public.pachanga_organizer_billing_invalidations_v1
for select
to anon, authenticated
using (private.pachanga_billing_invalidation_can_read_v1(
  organizer_kind, organizer_group_id, organizer_club_id
));

revoke all on table public.pachanga_organizer_billing_invalidations_v1 from public, anon, authenticated;
grant select on table public.pachanga_organizer_billing_invalidations_v1 to anon, authenticated;
grant all on table public.pachanga_organizer_billing_invalidations_v1 to service_role;

revoke all on function private.pachanga_billing_invalidation_can_read_v1(text, uuid, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_billing_touch_invalidation_v1(text, uuid, uuid, text, bigint) from public, anon, authenticated;
revoke all on function private.pachanga_billing_invalidate_catalog_trigger_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_invalidate_organizer_trigger_v1() from public, anon, authenticated;
revoke all on function private.pachanga_billing_invalidate_projection_trigger_v1() from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_organizer_billing_invalidations_v1'
  ) then
    alter publication supabase_realtime add table public.pachanga_organizer_billing_invalidations_v1;
  end if;
end;
$$;

comment on table public.pachanga_organizer_billing_invalidations_v1 is
  'Realtime invalidation only. Clients must refetch the canonical billing or catalog snapshot and never apply this WAL row as authority.';
