-- Pachangas IQ R4A: generic participation and roster entities.
-- Operations remain LEAGUE-only and every product flag is OFF by default.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists league_participation_foundation_enabled boolean not null default false,
  add column if not exists league_registration_enabled boolean not null default false,
  add column if not exists league_public_registration_enabled boolean not null default false,
  add column if not exists league_delegates_enabled boolean not null default false,
  add column if not exists league_rosters_enabled boolean not null default false,
  add column if not exists league_schedule_preferences_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_competition_foundation_settings_league_flags_check,
  add constraint pachanga_competition_foundation_settings_league_flags_check check (
    (not league_registration_enabled or league_participation_foundation_enabled)
    and (not league_public_registration_enabled or league_registration_enabled)
    and (not league_delegates_enabled or league_participation_foundation_enabled)
    and (not league_rosters_enabled or league_registration_enabled)
    and (not league_schedule_preferences_enabled or league_participation_foundation_enabled)
  );

alter table public.pachanga_competitions
  drop constraint if exists pachanga_competitions_visibility_check,
  add constraint pachanga_competitions_visibility_check
    check (visibility in ('private', 'internal', 'public'));

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_grants_capability_check,
  add constraint pachanga_competition_entitlement_grants_capability_check check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline', 'competition_entries_manage',
    'competition_rosters_review', 'competition_categories_manage'
  ));

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'viewer'
  ));

alter table public.pachanga_competition_editions
  add column if not exists registration_mode text not null default 'CLOSED',
  add column if not exists registration_opens_at timestamptz,
  add column if not exists registration_closes_at timestamptz,
  add column if not exists registration_closed_at timestamptz,
  add column if not exists registration_rule_revision_id uuid
    references public.pachanga_competition_rule_revisions(id) on delete restrict;

alter table public.pachanga_competition_editions
  drop constraint if exists pachanga_competition_editions_status_check,
  drop constraint if exists pachanga_competition_editions_status_check1,
  drop constraint if exists pachanga_competition_editions_registration_mode_check,
  drop constraint if exists pachanga_competition_editions_registration_window_check,
  add constraint pachanga_competition_editions_status_check check (status in (
    'draft', 'registration_open', 'registration_closed', 'scheduled', 'active',
    'completed', 'archived', 'cancelled', 'suspended'
  )),
  add constraint pachanga_competition_editions_registration_mode_check check (
    registration_mode in ('PUBLIC_APPROVAL', 'INVITE_ONLY', 'CLOSED', 'PRIVATE_CODE', 'AUTO_ACCEPT')
  ),
  add constraint pachanga_competition_editions_registration_window_check check (
    registration_closes_at is null or registration_opens_at is null
    or registration_closes_at > registration_opens_at
  );

create table if not exists public.pachanga_competition_categories (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  name text not null,
  slug text not null,
  description text not null default '',
  sport_format text not null,
  level_label text,
  minimum_age integer,
  maximum_age integer,
  age_reference_date date,
  eligibility_policy jsonb not null default '{}'::jsonb,
  visibility text not null default 'internal',
  status text not null default 'draft',
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (length(trim(name)) between 1 and 120),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 1 and 80),
  check (length(trim(sport_format)) between 2 and 40),
  check (level_label is null or length(trim(level_label)) between 1 and 80),
  check (minimum_age is null or minimum_age between 0 and 120),
  check (maximum_age is null or maximum_age between 0 and 120),
  check (minimum_age is null or maximum_age is null or minimum_age <= maximum_age),
  check (jsonb_typeof(eligibility_policy) = 'object'),
  check (visibility in ('private', 'internal', 'public')),
  check (status in ('draft', 'active', 'closed', 'archived')),
  check (revision >= 1),
  unique (edition_id, slug)
);

create table if not exists public.pachanga_competition_entries (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  team_id uuid not null references public.pachanga_groups(id) on delete restrict,
  entry_source text not null,
  status text not null default 'draft',
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  submitted_by uuid references auth.users(id) on delete set null,
  accepted_by uuid references auth.users(id) on delete set null,
  submitted_at timestamptz,
  accepted_at timestamptz,
  rejected_at timestamptz,
  withdrawn_at timestamptz,
  reason_code text not null default 'entry.created',
  reason_text_private text not null default '',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (entry_source in (
    'PUBLIC_APPLICATION', 'ORGANIZER_INVITATION', 'PRIVATE_CODE',
    'MIGRATION', 'PLATFORM_GRANT'
  )),
  check (status in (
    'draft', 'submitted', 'invited', 'accepted', 'rejected', 'withdrawn',
    'declined', 'expired', 'active', 'completed', 'disqualified'
  )),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(reason_text_private) <= 1200),
  check (revision >= 1)
);

create unique index if not exists pachanga_competition_entries_current_team_idx
  on public.pachanga_competition_entries(edition_id, category_id, team_id)
  where status in ('draft', 'submitted', 'invited', 'accepted', 'active');

create table if not exists public.pachanga_competition_entry_invitations (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null unique references public.pachanga_competition_entries(id) on delete restrict,
  team_id uuid not null references public.pachanga_groups(id) on delete restrict,
  status text not null default 'pending',
  expires_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  invited_by uuid not null references auth.users(id) on delete restrict,
  responded_by uuid references auth.users(id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('pending', 'accepted', 'declined', 'expired', 'cancelled')),
  check (revision >= 1)
);

create table if not exists public.pachanga_competition_team_delegates (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  delegate_role text not null,
  status text not null default 'invited',
  valid_from timestamptz,
  valid_until timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  invited_by uuid not null references auth.users(id) on delete restrict,
  accepted_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  replaced_by_delegate_id uuid references public.pachanga_competition_team_delegates(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (delegate_role in ('PRIMARY_DELEGATE', 'ROSTER_MANAGER', 'VIEWER')),
  check (status in ('invited', 'active', 'declined', 'revoked', 'replaced', 'expired')),
  check (valid_until is null or valid_from is null or valid_until > valid_from),
  check (revision >= 1)
);

create unique index if not exists pachanga_competition_primary_delegate_active_idx
  on public.pachanga_competition_team_delegates(entry_id)
  where delegate_role = 'PRIMARY_DELEGATE' and status = 'active';
create unique index if not exists pachanga_competition_delegate_pending_active_idx
  on public.pachanga_competition_team_delegates(entry_id, user_id, delegate_role)
  where status in ('invited', 'active');

create table if not exists public.pachanga_competition_stage_memberships (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  valid_from timestamptz not null default clock_timestamp(),
  valid_until timestamptz,
  status text not null default 'active',
  reason text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  assigned_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('active', 'closed', 'archived')),
  check (valid_until is null or valid_until > valid_from),
  check (length(trim(reason)) between 3 and 1200),
  check (revision >= 1)
);

create unique index if not exists pachanga_competition_stage_membership_active_idx
  on public.pachanga_competition_stage_memberships(entry_id)
  where status = 'active';

create table if not exists public.pachanga_competition_rosters (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null unique references public.pachanga_competition_entries(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  status text not null default 'draft',
  current_revision_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('draft', 'submitted', 'approved', 'locked', 'changes_requested', 'amended')),
  check (revision >= 1)
);

create table if not exists public.pachanga_competition_roster_revisions (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null references public.pachanga_competition_rosters(id) on delete restrict,
  revision_number bigint not null,
  roster_status text not null,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  member_count integer not null default 0,
  eligibility_summary jsonb not null default '{}'::jsonb,
  member_set_checksum text not null,
  submitted_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  effective_from timestamptz not null default clock_timestamp(),
  reason text not null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  check (revision_number >= 1),
  check (roster_status in ('draft', 'submitted', 'approved', 'locked', 'changes_requested', 'amended')),
  check (member_count >= 0),
  check (jsonb_typeof(eligibility_summary) = 'object'),
  check (length(member_set_checksum) = 64),
  check (length(trim(reason)) between 3 and 1200),
  unique (roster_id, revision_number)
);

alter table public.pachanga_competition_rosters
  add constraint pachanga_competition_rosters_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_roster_revisions(id) on delete restrict;

create table if not exists public.pachanga_player_competition_credentials (
  id uuid primary key default gen_random_uuid(),
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  status text not null default 'unverified',
  verification_method text not null default 'NONE',
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,
  expires_at timestamptz,
  reason_code text not null default 'credential.unverified',
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('unverified', 'pending', 'verified', 'expired', 'rejected', 'revoked')),
  check (length(trim(verification_method)) between 2 and 80),
  check (length(trim(reason_code)) between 3 and 120),
  check (revision >= 1),
  unique (player_profile_id, edition_id, category_id)
);

create table if not exists private.pachanga_competition_credential_evidence (
  credential_id uuid primary key references public.pachanga_player_competition_credentials(id) on delete cascade,
  evidence_reference text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (length(trim(evidence_reference)) between 8 and 500)
);

create table if not exists public.pachanga_competition_roster_members (
  id uuid primary key default gen_random_uuid(),
  roster_id uuid not null references public.pachanga_competition_rosters(id) on delete restrict,
  roster_revision_id uuid not null references public.pachanga_competition_roster_revisions(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  source_group_id uuid references public.pachanga_groups(id) on delete restrict,
  source_user_id uuid references auth.users(id) on delete restrict,
  eligibility_status text not null default 'pending',
  credential_id uuid references public.pachanga_player_competition_credentials(id) on delete restrict,
  effective_from timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  public_snapshot jsonb not null default '{}'::jsonb,
  reason_code text not null default 'eligibility.pending',
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (eligibility_status in ('pending', 'eligible', 'ineligible', 'waived', 'review_required', 'expired')),
  check (effective_until is null or effective_until > effective_from),
  check (jsonb_typeof(public_snapshot) = 'object'),
  check (length(trim(reason_code)) between 3 and 120),
  unique (roster_revision_id, player_profile_id)
);

create table if not exists public.pachanga_competition_eligibility_waivers (
  id uuid primary key default gen_random_uuid(),
  roster_member_id uuid not null references public.pachanga_competition_roster_members(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  status text not null default 'active',
  valid_from timestamptz not null default clock_timestamp(),
  valid_until timestamptz,
  reason text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  granted_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('active', 'revoked', 'expired')),
  check (valid_until is null or valid_until > valid_from),
  check (length(trim(reason)) between 3 and 1200),
  check (revision >= 1)
);

create table if not exists public.pachanga_competition_team_kits (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  kit_type text not null,
  primary_color text not null,
  secondary_color text not null,
  pattern text,
  asset_reference text,
  valid_from timestamptz not null default clock_timestamp(),
  valid_until timestamptz,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (kit_type in ('HOME', 'AWAY', 'ALTERNATE')),
  check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  check (secondary_color ~ '^#[0-9A-Fa-f]{6}$'),
  check (pattern is null or length(trim(pattern)) between 1 and 80),
  check (asset_reference is null or length(trim(asset_reference)) between 3 and 500),
  check (valid_until is null or valid_until > valid_from),
  check (status in ('active', 'retired')),
  check (revision >= 1)
);

create unique index if not exists pachanga_competition_team_kits_active_idx
  on public.pachanga_competition_team_kits(entry_id, kit_type)
  where status = 'active';

create table if not exists public.pachanga_competition_player_jersey_numbers (
  id uuid primary key default gen_random_uuid(),
  roster_member_id uuid not null references public.pachanga_competition_roster_members(id) on delete restrict,
  roster_revision_id uuid not null references public.pachanga_competition_roster_revisions(id) on delete restrict,
  number integer not null,
  valid_from timestamptz not null default clock_timestamp(),
  valid_until timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  assigned_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  check (number between 0 and 999),
  check (valid_until is null or valid_until > valid_from),
  check (revision >= 1),
  unique (roster_member_id),
  unique (roster_revision_id, number)
);

create table if not exists public.pachanga_team_availability_constraints (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  weekday integer not null,
  start_local_time time not null,
  end_local_time time not null,
  timezone text not null,
  valid_from_date date,
  valid_until_date date,
  reason text not null,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (weekday between 1 and 7),
  check (end_local_time > start_local_time),
  check (length(trim(timezone)) between 3 and 100),
  check (valid_until_date is null or valid_from_date is null or valid_until_date >= valid_from_date),
  check (length(trim(reason)) between 3 and 1200),
  check (status in ('active', 'retired')),
  check (revision >= 1)
);

create table if not exists public.pachanga_team_schedule_preferences (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  weekday integer not null,
  start_local_time time not null,
  end_local_time time not null,
  timezone text not null,
  weight integer not null default 50,
  preferred_area text,
  venue_reference text,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (weekday between 1 and 7),
  check (end_local_time > start_local_time),
  check (length(trim(timezone)) between 3 and 100),
  check (weight between 1 and 100),
  check (preferred_area is null or length(trim(preferred_area)) between 1 and 160),
  check (venue_reference is null or length(trim(venue_reference)) between 3 and 500),
  check (status in ('active', 'retired')),
  check (revision >= 1)
);

alter table public.pachanga_competition_invalidations
  add column if not exists target_group_id uuid references public.pachanga_groups(id) on delete cascade,
  add column if not exists target_user_id uuid references auth.users(id) on delete cascade;

create index if not exists pachanga_competition_categories_edition_idx
  on public.pachanga_competition_categories(edition_id, status, server_sequence desc, id);
create index if not exists pachanga_competition_entries_desk_idx
  on public.pachanga_competition_entries(competition_id, status, category_id, server_sequence desc, id);
create index if not exists pachanga_competition_entries_team_idx
  on public.pachanga_competition_entries(team_id, server_sequence desc, id);
create index if not exists pachanga_competition_delegate_entry_idx
  on public.pachanga_competition_team_delegates(entry_id, status, server_sequence desc, id);
create index if not exists pachanga_competition_delegate_user_idx
  on public.pachanga_competition_team_delegates(user_id, status, server_sequence desc, id);
create index if not exists pachanga_competition_stage_membership_history_idx
  on public.pachanga_competition_stage_memberships(entry_id, server_sequence desc, id);
create index if not exists pachanga_competition_roster_revision_idx
  on public.pachanga_competition_roster_revisions(roster_id, revision_number desc, id);
create index if not exists pachanga_competition_roster_member_revision_idx
  on public.pachanga_competition_roster_members(roster_revision_id, player_profile_id, id);
create index if not exists pachanga_competition_roster_member_player_idx
  on public.pachanga_competition_roster_members(player_profile_id, entry_id, server_sequence desc, id);
create index if not exists pachanga_player_competition_credential_scope_idx
  on public.pachanga_player_competition_credentials(competition_id, category_id, status, server_sequence desc, id);
create index if not exists pachanga_competition_waiver_player_idx
  on public.pachanga_competition_eligibility_waivers(player_profile_id, status, server_sequence desc, id);
create index if not exists pachanga_team_availability_entry_idx
  on public.pachanga_team_availability_constraints(entry_id, status, weekday, id);
create index if not exists pachanga_team_schedule_preference_entry_idx
  on public.pachanga_team_schedule_preferences(entry_id, status, weekday, weight desc, id);
create index if not exists pachanga_competition_invalidations_target_group_idx
  on public.pachanga_competition_invalidations(target_group_id, server_sequence desc)
  where target_group_id is not null;
create index if not exists pachanga_competition_invalidations_target_user_idx
  on public.pachanga_competition_invalidations(target_user_id, server_sequence desc)
  where target_user_id is not null;

create or replace function private.pachanga_competition_participation_touch_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function private.pachanga_competition_participation_touch_v1()
  from public, anon, authenticated;

do $$
declare target_table regclass;
begin
  foreach target_table in array array[
    'public.pachanga_competition_categories'::regclass,
    'public.pachanga_competition_entries'::regclass,
    'public.pachanga_competition_entry_invitations'::regclass,
    'public.pachanga_competition_team_delegates'::regclass,
    'public.pachanga_competition_stage_memberships'::regclass,
    'public.pachanga_competition_rosters'::regclass,
    'public.pachanga_player_competition_credentials'::regclass,
    'public.pachanga_competition_eligibility_waivers'::regclass,
    'public.pachanga_competition_team_kits'::regclass,
    'public.pachanga_team_availability_constraints'::regclass,
    'public.pachanga_team_schedule_preferences'::regclass
  ] loop
    execute format('drop trigger if exists touch_r4a_updated_at on %s', target_table);
    execute format(
      'create trigger touch_r4a_updated_at before update on %s for each row execute function private.pachanga_competition_participation_touch_v1()',
      target_table
    );
  end loop;
end;
$$;

create or replace function private.pachanga_competition_roster_revision_immutable_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if current_user = 'postgres'
     and current_setting('pachangas.r4a_revision_write', true) = 'on' then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  raise exception 'ROSTER_REVISION_IMMUTABLE' using errcode = '55000';
end;
$$;

revoke all on function private.pachanga_competition_roster_revision_immutable_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_competition_roster_revision_v1
  on public.pachanga_competition_roster_revisions;
create trigger guard_pachanga_competition_roster_revision_v1
before update or delete on public.pachanga_competition_roster_revisions
for each row execute function private.pachanga_competition_roster_revision_immutable_v1();

do $$
declare target_table regclass;
begin
  foreach target_table in array array[
    'public.pachanga_competition_categories'::regclass,
    'public.pachanga_competition_entries'::regclass,
    'public.pachanga_competition_entry_invitations'::regclass,
    'public.pachanga_competition_team_delegates'::regclass,
    'public.pachanga_competition_stage_memberships'::regclass,
    'public.pachanga_competition_rosters'::regclass,
    'public.pachanga_competition_roster_revisions'::regclass,
    'public.pachanga_competition_roster_members'::regclass,
    'public.pachanga_player_competition_credentials'::regclass,
    'public.pachanga_competition_eligibility_waivers'::regclass,
    'public.pachanga_competition_team_kits'::regclass,
    'public.pachanga_competition_player_jersey_numbers'::regclass,
    'public.pachanga_team_availability_constraints'::regclass,
    'public.pachanga_team_schedule_preferences'::regclass
  ] loop
    execute format('alter table %s enable row level security', target_table);
    execute format('revoke all on table %s from public, anon, authenticated', target_table);
    execute format('grant all on table %s to service_role', target_table);
  end loop;
end;
$$;

revoke all on table private.pachanga_competition_credential_evidence
  from public, anon, authenticated;
grant all on table private.pachanga_competition_credential_evidence to service_role;

comment on table public.pachanga_competition_entries is
  'R4A generic team participation. It does not activate fixtures, matches or standings.';
comment on table public.pachanga_competition_rosters is
  'Competition roster layer between habitual team membership and future match squads.';
comment on table private.pachanga_competition_credential_evidence is
  'Opaque protected evidence references. Never exposed by R4A read models or Realtime.';
