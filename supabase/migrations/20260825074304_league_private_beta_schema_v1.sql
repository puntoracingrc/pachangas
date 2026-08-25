-- Pachangas IQ Productization Wave 2: private League beta access and onboarding.
-- This migration creates no League, grant or fixture and leaves every gate OFF.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists league_private_beta_enabled boolean not null default false,
  add column if not exists league_private_beta_creation_enabled boolean not null default false,
  add column if not exists league_private_beta_max_active_editions_per_organizer smallint not null default 1,
  add column if not exists league_private_beta_default_team_cap smallint not null default 12,
  add column if not exists league_private_beta_public_discovery_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_private_beta_limits_check,
  drop constraint if exists pachanga_comp_foundation_private_beta_public_check,
  drop constraint if exists pachanga_comp_foundation_private_beta_creation_check,
  add constraint pachanga_comp_foundation_private_beta_limits_check check (
    league_private_beta_max_active_editions_per_organizer = 1
    and league_private_beta_default_team_cap between 4 and 12
  ),
  add constraint pachanga_comp_foundation_private_beta_public_check check (
    not league_private_beta_public_discovery_enabled
    and (
      not league_private_beta_enabled
      or (
        not league_public_registration_enabled
        and not league_public_calendar_enabled
        and not league_public_standings_enabled
        and not league_public_exception_status_enabled
      )
    )
  ),
  add constraint pachanga_comp_foundation_private_beta_creation_check check (
    not league_private_beta_creation_enabled
    or (
      league_private_beta_enabled
      and foundation_enabled
      and creation_enabled
      and league_participation_foundation_enabled
      and league_registration_enabled
      and league_delegates_enabled
      and league_rosters_enabled
      and league_schedule_preferences_enabled
      and league_scheduling_foundation_enabled
      and league_schedule_generation_enabled
      and league_schedule_editing_enabled
      and league_schedule_publication_enabled
      and league_canonical_fixture_creation_enabled
      and league_match_operations_foundation_enabled
      and league_match_squads_enabled
      and league_match_attendance_enabled
      and league_sporting_results_enabled
      and league_result_confirmation_enabled
      and league_official_results_enabled
      and league_standings_enabled
      and league_operational_exceptions_foundation_enabled
      and league_postponements_enabled
      and league_rescheduling_enabled
      and league_venue_changes_enabled
      and league_late_arrival_enabled
      and league_no_show_enabled
      and league_match_suspensions_enabled
      and league_administrative_decisions_enabled
    )
  );

alter table public.pachanga_competition_entitlement_grants
  add column if not exists program_key text,
  add column if not exists bundle_id uuid,
  add column if not exists beta_team_cap smallint;

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_beta_bundle_check,
  add constraint pachanga_competition_entitlement_beta_bundle_check check (
    (
      program_key is null
      and bundle_id is null
      and beta_team_cap is null
    )
    or (
      program_key = 'LEAGUE_PRIVATE_BETA_V1'
      and bundle_id is not null
      and beta_team_cap between 4 and 20
      and grant_source = 'platform_grant'
      and position('LEAGUE_PRIVATE_BETA_V1' in reason) > 0
    )
  );

create index if not exists pachanga_competition_entitlement_beta_bundle_idx
  on public.pachanga_competition_entitlement_grants(bundle_id, capability, server_sequence)
  where program_key = 'LEAGUE_PRIVATE_BETA_V1';

create index if not exists pachanga_competition_entitlement_beta_organizer_idx
  on public.pachanga_competition_entitlement_grants(
    organizer_kind,
    organizer_group_id,
    organizer_club_id,
    status,
    expires_at,
    server_sequence desc
  )
  where program_key = 'LEAGUE_PRIVATE_BETA_V1';

alter table public.pachanga_competitions
  add column if not exists product_key text,
  add column if not exists description text not null default '',
  add column if not exists general_area text,
  add column if not exists image_url text;

alter table public.pachanga_competitions
  drop constraint if exists pachanga_competitions_product_key_check,
  drop constraint if exists pachanga_competitions_product_metadata_check,
  add constraint pachanga_competitions_product_key_check check (
    product_key is null or product_key = 'LEAGUE_PRIVATE_BETA_V1'
  ),
  add constraint pachanga_competitions_product_metadata_check check (
    length(description) <= 2400
    and (general_area is null or length(trim(general_area)) between 1 and 160)
    and (image_url is null or length(trim(image_url)) between 8 and 2048)
  );

create unique index if not exists pachanga_beta_active_team_competition_idx
  on public.pachanga_competitions(organizer_group_id)
  where product_key = 'LEAGUE_PRIVATE_BETA_V1'
    and organizer_kind = 'TEAM'
    and status <> 'cancelled';

create unique index if not exists pachanga_beta_active_club_competition_idx
  on public.pachanga_competitions(organizer_club_id)
  where product_key = 'LEAGUE_PRIVATE_BETA_V1'
    and organizer_kind = 'CLUB'
    and status <> 'cancelled';

create table if not exists private.pachanga_league_private_beta_wizards (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'draft',
  current_step smallint not null default 1,
  completed_steps smallint[] not null default '{}'::smallint[],
  step_data jsonb not null default '{}'::jsonb,
  consented_at timestamptz,
  competition_id uuid unique references public.pachanga_competitions(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (status in ('draft', 'completed', 'cancelled')),
  check (current_step between 1 and 10),
  check (completed_steps <@ array[1,2,3,4,5,6,7,8,9,10]::smallint[]),
  check (jsonb_typeof(step_data) = 'object'),
  check (revision >= 1),
  check (
    (status = 'completed' and competition_id is not null and consented_at is not null)
    or (status <> 'completed' and competition_id is null)
  )
);

create unique index if not exists pachanga_league_beta_active_team_wizard_idx
  on private.pachanga_league_private_beta_wizards(organizer_group_id)
  where status = 'draft' and organizer_kind = 'TEAM';

create unique index if not exists pachanga_league_beta_active_club_wizard_idx
  on private.pachanga_league_private_beta_wizards(organizer_club_id)
  where status = 'draft' and organizer_kind = 'CLUB';

create index if not exists pachanga_league_beta_wizard_actor_idx
  on private.pachanga_league_private_beta_wizards(created_by, status, server_sequence desc);

create table if not exists private.pachanga_league_private_beta_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  request_hash text not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null unique,
  client_metadata jsonb not null default '{}'::jsonb,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  check (length(request_hash) = 64),
  check (confirmed_revision >= 0),
  check (jsonb_typeof(client_metadata) = 'object'),
  check (jsonb_typeof(response) = 'object')
);

create table if not exists private.pachanga_league_private_beta_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  organizer_kind text,
  organizer_group_id uuid references public.pachanga_groups(id) on delete set null,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete set null,
  competition_id uuid references public.pachanga_competitions(id) on delete set null,
  aggregate_revision bigint not null,
  server_sequence bigint not null unique,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb,
  confirmed_at timestamptz not null default clock_timestamp(),
  check (organizer_kind is null or organizer_kind in ('TEAM', 'CLUB')),
  check (
    organizer_kind is null
    or (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (aggregate_revision >= 0),
  check (jsonb_typeof(event_payload) = 'object')
);

create index if not exists pachanga_league_beta_events_organizer_idx
  on private.pachanga_league_private_beta_events(
    organizer_kind,
    organizer_group_id,
    organizer_club_id,
    server_sequence desc
  );

create table if not exists public.pachanga_league_private_beta_invalidations (
  server_sequence bigint primary key,
  wizard_id uuid references private.pachanga_league_private_beta_wizards(id) on delete cascade,
  competition_id uuid references public.pachanga_competitions(id) on delete cascade,
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete cascade,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete cascade,
  target_user_id uuid references auth.users(id) on delete cascade,
  entity_type text not null,
  entity_id uuid not null,
  revision bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (revision >= 0)
);

create index if not exists pachanga_league_beta_invalidations_actor_idx
  on public.pachanga_league_private_beta_invalidations(target_user_id, server_sequence desc);

create index if not exists pachanga_league_beta_invalidations_competition_idx
  on public.pachanga_league_private_beta_invalidations(competition_id, server_sequence desc);

create or replace function private.pachanga_league_private_beta_touch_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

drop trigger if exists touch_pachanga_league_private_beta_wizard_v1
  on private.pachanga_league_private_beta_wizards;
create trigger touch_pachanga_league_private_beta_wizard_v1
before update on private.pachanga_league_private_beta_wizards
for each row execute function private.pachanga_league_private_beta_touch_v1();

create or replace function private.pachanga_league_private_beta_guard_competition_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;

  if new.product_key = 'LEAGUE_PRIVATE_BETA_V1'
     or settings.league_private_beta_enabled then
    if not settings.league_private_beta_enabled then
      raise exception 'LEAGUE_PRIVATE_BETA_DISABLED' using errcode = '42501';
    end if;
    if current_setting('pachangas.league_private_beta_authorized', true) <> 'on' then
      raise exception 'LEAGUE_PRIVATE_BETA_COMMAND_REQUIRED' using errcode = '42501';
    end if;
    if not settings.league_private_beta_creation_enabled then
      raise exception 'LEAGUE_PRIVATE_BETA_CREATION_DISABLED' using errcode = '42501';
    end if;
    if new.competition_type <> 'LEAGUE' then
      raise exception 'TOURNAMENT_ENGINE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    if new.visibility <> 'private' then
      raise exception 'LEAGUE_PRIVATE_BETA_VISIBILITY_REQUIRED' using errcode = '22023';
    end if;
    new.product_key := 'LEAGUE_PRIVATE_BETA_V1';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_pachanga_league_private_beta_competition_v1
  on public.pachanga_competitions;
create trigger guard_pachanga_league_private_beta_competition_v1
before insert on public.pachanga_competitions
for each row execute function private.pachanga_league_private_beta_guard_competition_v1();

create or replace function private.pachanga_league_private_beta_guard_structure_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare beta_competition_id uuid;
declare existing_count integer;
begin
  if tg_table_name = 'pachanga_competition_editions' then
    beta_competition_id := new.competition_id;
  elsif tg_table_name = 'pachanga_competition_stages' then
    select editions.competition_id into beta_competition_id
    from public.pachanga_competition_editions editions where editions.id = new.edition_id;
  elsif tg_table_name = 'pachanga_competition_categories' then
    select editions.competition_id into beta_competition_id
    from public.pachanga_competition_editions editions where editions.id = new.edition_id;
  elsif tg_table_name = 'pachanga_competition_divisions' then
    select editions.competition_id into beta_competition_id
    from public.pachanga_competition_stages stages
    join public.pachanga_competition_editions editions on editions.id = stages.edition_id
    where stages.id = new.stage_id;
  elsif tg_table_name = 'pachanga_competition_groups' then
    select editions.competition_id into beta_competition_id
    from public.pachanga_competition_stages stages
    join public.pachanga_competition_editions editions on editions.id = stages.edition_id
    where stages.id = new.stage_id;
  end if;

  if not exists (
    select 1 from public.pachanga_competitions competitions
    where competitions.id = beta_competition_id
      and competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
  ) then return new; end if;

  if current_setting('pachangas.league_private_beta_authorized', true) <> 'on' then
    raise exception 'LEAGUE_PRIVATE_BETA_COMMAND_REQUIRED' using errcode = '42501';
  end if;

  if tg_table_name = 'pachanga_competition_editions' then
    select count(*) into existing_count
    from public.pachanga_competition_editions editions
    where editions.competition_id = new.competition_id;
  elsif tg_table_name = 'pachanga_competition_stages' then
    if new.stage_type <> 'LEAGUE_STAGE' then
      raise exception 'LEAGUE_PRIVATE_BETA_STRUCTURE_LIMIT' using errcode = '22023';
    end if;
    select count(*) into existing_count
    from public.pachanga_competition_stages stages where stages.edition_id = new.edition_id;
  elsif tg_table_name = 'pachanga_competition_categories' then
    if new.visibility = 'public' then
      raise exception 'LEAGUE_PRIVATE_BETA_PUBLIC_DISCOVERY_DISABLED' using errcode = '42501';
    end if;
    select count(*) into existing_count
    from public.pachanga_competition_categories categories where categories.edition_id = new.edition_id;
  elsif tg_table_name = 'pachanga_competition_divisions' then
    select count(*) into existing_count
    from public.pachanga_competition_divisions divisions where divisions.stage_id = new.stage_id;
  else
    select count(*) into existing_count
    from public.pachanga_competition_groups competition_groups where competition_groups.stage_id = new.stage_id;
  end if;

  if existing_count >= 1 then
    raise exception 'LEAGUE_PRIVATE_BETA_STRUCTURE_LIMIT' using errcode = 'PT409';
  end if;
  return new;
end;
$$;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_competition_editions',
    'pachanga_competition_stages',
    'pachanga_competition_divisions',
    'pachanga_competition_groups',
    'pachanga_competition_categories'
  ] loop
    execute format('drop trigger if exists guard_private_beta_structure_v1 on public.%I', target_table);
    execute format(
      'create trigger guard_private_beta_structure_v1 before insert on public.%I for each row execute function private.pachanga_league_private_beta_guard_structure_v1()',
      target_table
    );
  end loop;
end;
$$;

create or replace function private.pachanga_league_private_beta_guard_public_flags_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.league_private_beta_enabled and (
    new.league_private_beta_public_discovery_enabled
    or new.league_public_registration_enabled
    or new.league_public_calendar_enabled
    or new.league_public_standings_enabled
    or new.league_public_exception_status_enabled
  ) then
    raise exception 'LEAGUE_PRIVATE_BETA_PUBLIC_SURFACES_DISABLED' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_pachanga_league_private_beta_public_flags_v1
  on private.pachanga_competition_foundation_settings;
create trigger guard_pachanga_league_private_beta_public_flags_v1
before insert or update on private.pachanga_competition_foundation_settings
for each row execute function private.pachanga_league_private_beta_guard_public_flags_v1();

create or replace function private.pachanga_league_private_beta_guard_referee_assignments_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.referee_assignments_enabled and exists (
    select 1
    from private.pachanga_competition_foundation_settings settings
    where settings.singleton and settings.league_private_beta_enabled
  ) then
    raise exception 'REFEREE_ASSIGNMENTS_NOT_AVAILABLE_IN_LEAGUE_BETA' using errcode = '0A000';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_pachanga_league_beta_referee_assignments_v1
  on private.pachanga_referee_foundation_settings;
create trigger guard_pachanga_league_beta_referee_assignments_v1
before insert or update on private.pachanga_referee_foundation_settings
for each row execute function private.pachanga_league_private_beta_guard_referee_assignments_v1();

do $$
begin
  if exists (
    select 1 from pg_proc procedures
    join pg_namespace namespaces on namespaces.oid = procedures.pronamespace
    where namespaces.nspname = 'private'
      and procedures.proname = 'pachanga_competition_immutable_ledger_v1'
  ) then
    execute 'drop trigger if exists guard_pachanga_league_beta_receipts_v1 on private.pachanga_league_private_beta_operation_receipts';
    execute 'create trigger guard_pachanga_league_beta_receipts_v1 before update or delete on private.pachanga_league_private_beta_operation_receipts for each row execute function private.pachanga_competition_immutable_ledger_v1()';
    execute 'drop trigger if exists guard_pachanga_league_beta_events_v1 on private.pachanga_league_private_beta_events';
    execute 'create trigger guard_pachanga_league_beta_events_v1 before update or delete on private.pachanga_league_private_beta_events for each row execute function private.pachanga_competition_immutable_ledger_v1()';
  end if;
end;
$$;

revoke all on table private.pachanga_league_private_beta_wizards
  from public, anon, authenticated;
revoke all on table private.pachanga_league_private_beta_operation_receipts
  from public, anon, authenticated;
revoke all on table private.pachanga_league_private_beta_events
  from public, anon, authenticated;
revoke all on table public.pachanga_league_private_beta_invalidations
  from public, anon, authenticated;

grant all on table private.pachanga_league_private_beta_wizards to service_role;
grant all on table private.pachanga_league_private_beta_operation_receipts to service_role;
grant all on table private.pachanga_league_private_beta_events to service_role;
grant all on table public.pachanga_league_private_beta_invalidations to service_role;

comment on column public.pachanga_competitions.product_key is
  'Productization marker only. Sporting truth remains in the existing R1/R4 canonical tables.';
comment on column public.pachanga_competition_entitlement_grants.bundle_id is
  'Groups existing entitlement grants into one private-beta grant operation; it is not a second permission authority.';
comment on table private.pachanga_league_private_beta_wizards is
  'Server-authoritative, resumable onboarding draft. Completion materializes only existing R1/R4 canonical entities.';
