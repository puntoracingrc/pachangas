-- Pachangas IQ R4B: typed schedule, round and canonical-fixture authorities.
-- All product flags are OFF by default and no fixture is created by this migration.

set lock_timeout = '5s';
set statement_timeout = '120s';

create extension if not exists btree_gist with schema extensions;

alter table private.pachanga_competition_foundation_settings
  add column if not exists league_scheduling_foundation_enabled boolean not null default false,
  add column if not exists league_schedule_generation_enabled boolean not null default false,
  add column if not exists league_schedule_editing_enabled boolean not null default false,
  add column if not exists league_schedule_publication_enabled boolean not null default false,
  add column if not exists league_public_calendar_enabled boolean not null default false,
  add column if not exists league_canonical_fixture_creation_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_competition_foundation_settings_schedule_flags_check,
  add constraint pachanga_competition_foundation_settings_schedule_flags_check check (
    (not league_schedule_generation_enabled or league_scheduling_foundation_enabled)
    and (not league_schedule_editing_enabled or league_schedule_generation_enabled)
    and (not league_schedule_publication_enabled or league_schedule_generation_enabled)
    and (not league_canonical_fixture_creation_enabled or league_schedule_publication_enabled)
    and (not league_public_calendar_enabled or league_scheduling_foundation_enabled)
  );

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_grants_capability_check,
  add constraint pachanga_competition_entitlement_grants_capability_check check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline', 'competition_entries_manage',
    'competition_rosters_review', 'competition_categories_manage', 'competition_schedule'
  ));

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'competition_schedule_manager', 'viewer'
  ));

create table if not exists public.pachanga_competition_schedule_plans (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  engine_version text not null default 'league-round-robin-v1',
  legs smallint not null,
  entry_count smallint not null default 0,
  status text not null default 'draft',
  current_revision_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  published_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (engine_version = 'league-round-robin-v1'),
  check (legs in (1, 2)),
  check (entry_count between 0 and 32),
  check (status in ('draft', 'generated', 'validated', 'published', 'superseded', 'cancelled')),
  check (revision >= 1),
  check ((status = 'cancelled') = (cancelled_at is not null)),
  check (status <> 'published' or published_at is not null)
);

create unique index if not exists pachanga_schedule_plan_active_scope_idx
  on public.pachanga_competition_schedule_plans(
    edition_id,
    stage_id,
    category_id,
    coalesce(division_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(competition_group_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) where status in ('draft', 'generated', 'validated', 'published');

create table if not exists public.pachanga_competition_schedule_revisions (
  id uuid primary key default gen_random_uuid(),
  schedule_plan_id uuid not null references public.pachanga_competition_schedule_plans(id) on delete restrict,
  version integer not null,
  revision_kind text not null default 'generated',
  status text not null default 'generated',
  engine_version text not null,
  seed text not null,
  input_checksum text not null,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  entry_snapshot_checksum text not null,
  slot_snapshot_checksum text not null,
  constraint_snapshot_checksum text not null,
  preference_snapshot_checksum text not null,
  entry_order jsonb not null default '[]'::jsonb,
  quality_score numeric(6, 3) not null default 0,
  validation_status text not null default 'PENDING',
  generated_by uuid not null references auth.users(id) on delete restrict,
  generated_at timestamptz not null default clock_timestamp(),
  validated_by uuid references auth.users(id) on delete set null,
  validated_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  published_at timestamptz,
  supersedes_revision_id uuid references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (revision_kind in ('generated', 'regenerated', 'manual_move', 'manual_swap', 'home_away_swap', 'round_rename')),
  check (status in ('generated', 'validated', 'published', 'superseded', 'cancelled')),
  check (engine_version = 'league-round-robin-v1'),
  check (length(seed) between 1 and 160),
  check (length(input_checksum) = 64),
  check (length(entry_snapshot_checksum) = 64),
  check (length(slot_snapshot_checksum) = 64),
  check (length(constraint_snapshot_checksum) = 64),
  check (length(preference_snapshot_checksum) = 64),
  check (jsonb_typeof(entry_order) = 'array'),
  check (quality_score between 0 and 100),
  check (validation_status in ('PENDING', 'VALID', 'INVALID', 'STALE_INPUT')),
  check (revision >= 1),
  check (status <> 'published' or published_at is not null),
  unique (schedule_plan_id, version)
);

alter table public.pachanga_competition_schedule_plans
  add constraint pachanga_schedule_plan_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_schedule_revisions(id) on delete restrict;

create table if not exists public.pachanga_competition_schedule_slots (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  timezone text not null,
  venue_id uuid,
  venue_label text,
  resource_key text,
  status text not null default 'available',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  retired_by uuid references auth.users(id) on delete set null,
  retired_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (ends_at > starts_at),
  check (length(trim(timezone)) between 3 and 80),
  check (venue_label is null or length(trim(venue_label)) between 1 and 160),
  check (resource_key is null or length(trim(resource_key)) between 1 and 160),
  check (status in ('available', 'assigned', 'retired')),
  check (revision >= 1),
  check ((status = 'retired') = (retired_at is not null))
);

alter table public.pachanga_competition_schedule_slots
  add constraint pachanga_schedule_slot_resource_overlap_excl
  exclude using gist (
    resource_key with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (resource_key is not null and status <> 'retired');

create table if not exists public.pachanga_competition_rounds (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  schedule_revision_id uuid not null references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  round_number integer not null,
  leg_number smallint not null,
  display_name text not null,
  starts_at timestamptz,
  ends_at timestamptz,
  status text not null default 'draft',
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  published_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (round_number >= 1),
  check (leg_number in (1, 2)),
  check (length(trim(display_name)) between 1 and 120),
  check (ends_at is null or starts_at is null or ends_at > starts_at),
  check (status in ('draft', 'published', 'cancelled')),
  check (revision >= 1),
  check (status <> 'published' or published_at is not null),
  unique (schedule_revision_id, round_number)
);

create table if not exists public.pachanga_competition_round_byes (
  id uuid primary key default gen_random_uuid(),
  schedule_revision_id uuid not null references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  round_id uuid not null references public.pachanga_competition_rounds(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  leg_number smallint not null,
  reason text not null default 'ODD_TEAM_COUNT',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (leg_number in (1, 2)),
  check (reason = 'ODD_TEAM_COUNT'),
  check (revision >= 1),
  unique (round_id, entry_id)
);

create table if not exists public.pachanga_competition_schedule_items (
  id uuid primary key default gen_random_uuid(),
  schedule_revision_id uuid not null references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  round_id uuid not null references public.pachanga_competition_rounds(id) on delete restrict,
  home_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  away_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  pairing_key text not null,
  leg_number smallint not null,
  slot_id uuid references public.pachanga_competition_schedule_slots(id) on delete restrict,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  timezone text,
  venue_id uuid,
  venue_label text,
  venue_status text not null default 'TBD',
  status text not null default 'unassigned',
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (home_entry_id <> away_entry_id),
  check (length(pairing_key) between 65 and 80),
  check (leg_number in (1, 2)),
  check ((slot_id is null) = (scheduled_start is null)),
  check ((slot_id is null) = (scheduled_end is null)),
  check (scheduled_end is null or scheduled_end > scheduled_start),
  check (timezone is null or length(trim(timezone)) between 3 and 80),
  check (venue_label is null or length(trim(venue_label)) between 1 and 160),
  check (venue_status in ('CONFIRMED', 'TBD')),
  check (status in ('unassigned', 'assigned', 'conflicted', 'validated', 'published')),
  check (revision >= 1),
  check (status <> 'published' or (canonical_match_id is not null and competition_match_context_id is not null)),
  unique (schedule_revision_id, pairing_key, leg_number)
);

create unique index if not exists pachanga_schedule_item_revision_slot_idx
  on public.pachanga_competition_schedule_items(schedule_revision_id, slot_id)
  where slot_id is not null;

create table if not exists public.pachanga_competition_schedule_validations (
  id uuid primary key default gen_random_uuid(),
  schedule_revision_id uuid not null references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  input_checksum text not null,
  status text not null,
  hard_violation_count integer not null default 0,
  unassigned_item_count integer not null default 0,
  pair_count integer not null default 0,
  round_count integer not null default 0,
  bye_count integer not null default 0,
  summary jsonb not null default '{}'::jsonb,
  validated_by uuid not null references auth.users(id) on delete restrict,
  validated_at timestamptz not null default clock_timestamp(),
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  check (length(input_checksum) = 64),
  check (status in ('VALID', 'INVALID', 'STALE_INPUT')),
  check (hard_violation_count >= 0 and unassigned_item_count >= 0),
  check (pair_count >= 0 and round_count >= 0 and bye_count >= 0),
  check (jsonb_typeof(summary) = 'object'),
  check (revision >= 1)
);

create index if not exists pachanga_schedule_validation_current_idx
  on public.pachanga_competition_schedule_validations(schedule_revision_id, server_sequence desc);

create table if not exists private.pachanga_competition_schedule_conflicts (
  id uuid primary key default gen_random_uuid(),
  schedule_plan_id uuid not null references public.pachanga_competition_schedule_plans(id) on delete restrict,
  schedule_revision_id uuid references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  schedule_item_id uuid references public.pachanga_competition_schedule_items(id) on delete restrict,
  slot_id uuid references public.pachanga_competition_schedule_slots(id) on delete restrict,
  entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  conflict_type text not null,
  severity text not null default 'hard',
  fingerprint text not null,
  public_summary text not null,
  private_detail jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  detected_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  check (conflict_type in (
    'TEAM_UNAVAILABLE', 'TEAM_OVERLAP', 'VENUE_OVERLAP',
    'INSUFFICIENT_SLOT_DURATION', 'EDITION_RANGE', 'STAGE_RANGE',
    'MINIMUM_REST', 'MISSING_VENUE', 'MISSING_SLOT',
    'DUPLICATE_PAIRING', 'ROSTER_NOT_READY', 'ENTRY_NOT_ELIGIBLE',
    'RULE_REVISION_MISMATCH', 'SCHEDULE_CAPACITY_DEFICIT',
    'ROUND_STRUCTURE_MISMATCH', 'TEAM_DUPLICATED_IN_ROUND',
    'BYE_MISMATCH', 'HOME_AWAY_IMBALANCE',
    'SECOND_LEG_NOT_MIRRORED'
  )),
  check (severity in ('hard', 'soft')),
  check (length(fingerprint) = 64),
  check (length(trim(public_summary)) between 3 and 240),
  check (jsonb_typeof(private_detail) = 'object'),
  check (status in ('active', 'resolved', 'superseded')),
  check (revision >= 1),
  unique (schedule_revision_id, fingerprint)
);

create table if not exists private.pachanga_competition_schedule_quality_snapshots (
  id uuid primary key default gen_random_uuid(),
  schedule_revision_id uuid not null unique references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  hard_violations integer not null default 0,
  soft_score numeric(6, 3) not null default 0,
  preference_satisfied_count integer not null default 0,
  preference_total_count integer not null default 0,
  home_away_balance jsonb not null default '{}'::jsonb,
  time_distribution jsonb not null default '{}'::jsonb,
  maximum_home_streak integer not null default 0,
  maximum_away_streak integer not null default 0,
  unassigned_items integer not null default 0,
  explanation jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default clock_timestamp(),
  checksum text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  check (hard_violations >= 0 and unassigned_items >= 0),
  check (soft_score between 0 and 100),
  check (preference_satisfied_count >= 0 and preference_total_count >= 0),
  check (preference_satisfied_count <= preference_total_count),
  check (jsonb_typeof(home_away_balance) = 'object'),
  check (jsonb_typeof(time_distribution) = 'object'),
  check (maximum_home_streak >= 0 and maximum_away_streak >= 0),
  check (jsonb_typeof(explanation) = 'object'),
  check (length(checksum) = 64),
  check (revision >= 1)
);

alter table public.pachanga_competition_match_contexts
  add column if not exists category_id uuid references public.pachanga_competition_categories(id) on delete restrict,
  add column if not exists round_id uuid references public.pachanga_competition_rounds(id) on delete restrict,
  add column if not exists schedule_item_id uuid references public.pachanga_competition_schedule_items(id) on delete restrict,
  add column if not exists home_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  add column if not exists away_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  add column if not exists slot_id uuid references public.pachanga_competition_schedule_slots(id) on delete restrict,
  add column if not exists scheduled_start timestamptz,
  add column if not exists scheduled_end timestamptz,
  add column if not exists timezone text,
  add column if not exists venue_id uuid,
  add column if not exists venue_label text,
  add column if not exists venue_status text not null default 'TBD',
  add column if not exists source_kind text not null default 'LEGACY_LAB';

drop index if exists public.pachanga_competition_context_active_match_idx;
alter table public.pachanga_competition_match_contexts
  drop constraint if exists pachanga_competition_match_contexts_status_check,
  drop constraint if exists pachanga_competition_match_contexts_schedule_check,
  drop constraint if exists pachanga_competition_match_contexts_venue_status_check,
  drop constraint if exists pachanga_competition_match_contexts_source_kind_check,
  add constraint pachanga_competition_match_contexts_status_check
    check (status in ('lab_bound', 'scheduled', 'retired')),
  add constraint pachanga_competition_match_contexts_schedule_check check (
    scheduled_end is null or (scheduled_start is not null and scheduled_end > scheduled_start)
  ),
  add constraint pachanga_competition_match_contexts_venue_status_check
    check (venue_status in ('CONFIRMED', 'TBD')),
  add constraint pachanga_competition_match_contexts_source_kind_check
    check (source_kind in ('LEGACY_LAB', 'COMPETITION_GENERATED'));

create unique index if not exists pachanga_competition_context_active_match_idx
  on public.pachanga_competition_match_contexts(canonical_match_id)
  where status in ('lab_bound', 'scheduled');
create unique index if not exists pachanga_competition_context_schedule_item_idx
  on public.pachanga_competition_match_contexts(schedule_item_id)
  where schedule_item_id is not null and status = 'scheduled';

alter table public.pachanga_competition_schedule_items
  add constraint pachanga_schedule_item_context_fk
  foreign key (competition_match_context_id)
  references public.pachanga_competition_match_contexts(id) on delete restrict;

do $$
declare constraint_row record;
begin
  for constraint_row in
    select constraints.conname
    from pg_catalog.pg_constraint constraints
    where constraints.conrelid = 'public.pachanga_canonical_match_bindings'::regclass
      and constraints.contype = 'c'
      and pg_catalog.pg_get_constraintdef(constraints.oid) like '%source_kind%'
  loop
    execute format(
      'alter table public.pachanga_canonical_match_bindings drop constraint %I',
      constraint_row.conname
    );
  end loop;
end;
$$;

alter table public.pachanga_canonical_match_bindings
  add constraint pachanga_canonical_match_bindings_source_kind_check
    check (source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge', 'competition_generated')),
  add constraint pachanga_canonical_match_bindings_source_scope_check check (
    (source_kind in ('group_match', 'open_match') and source_group_id is not null)
    or (source_kind in ('external_match', 'team_challenge', 'competition_generated') and source_group_id is null)
  );

do $$
declare constraint_row record;
begin
  for constraint_row in
    select constraints.conname
    from pg_catalog.pg_constraint constraints
    where constraints.conrelid = 'public.pachanga_canonical_match_binding_reviews'::regclass
      and constraints.contype = 'c'
      and pg_catalog.pg_get_constraintdef(constraints.oid) like '%source_kind%'
  loop
    execute format(
      'alter table public.pachanga_canonical_match_binding_reviews drop constraint %I',
      constraint_row.conname
    );
  end loop;
end;
$$;

alter table public.pachanga_canonical_match_binding_reviews
  add constraint pachanga_canonical_match_binding_reviews_left_source_kind_check
    check (left_source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge', 'competition_generated')),
  add constraint pachanga_canonical_match_binding_reviews_right_source_kind_check
    check (right_source_kind is null or right_source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge', 'competition_generated'));

comment on table public.pachanga_competition_schedule_plans is
  'R4B aggregate selecting one LEAGUE stage scope, frozen rules and one or two round-robin legs.';
comment on table public.pachanga_competition_schedule_revisions is
  'Immutable schedule revisions. Manual draft operations clone a revision instead of overwriting history.';
comment on table public.pachanga_competition_schedule_items is
  'A pairing and slot inside one immutable schedule revision; never an authority for result, attendance or lineup.';
comment on table public.pachanga_competition_round_byes is
  'Explicit odd-team byes. R4B never creates a fictitious opponent or CanonicalMatch for a bye.';
comment on column public.pachanga_competition_match_contexts.schedule_item_id is
  'Unique R4B fixture origin. Sporting identity remains the referenced CanonicalMatch.';
