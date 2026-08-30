-- Pachangas IQ Wave 9B: append-only season Venue allocation plans and input freezes.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_venue_settings_v1
  add column if not exists competition_venue_allocation_foundation_enabled boolean not null default false;

create table if not exists public.pachanga_competition_venue_allocation_plans (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  schedule_plan_id uuid not null references public.pachanga_competition_schedule_plans(id) on delete restrict,
  schedule_revision_id uuid not null references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  venue_pool_id uuid not null references public.pachanga_competition_venue_pools(id) on delete restrict,
  venue_pool_revision_id uuid not null references private.pachanga_competition_venue_pool_revisions(id) on delete restrict,
  mode text not null,
  venue_required boolean not null default true,
  status text not null default 'draft',
  current_input_freeze_id uuid,
  current_revision_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  validated_at timestamptz,
  published_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (mode in ('AUTOMATIC', 'MANUAL_ASSISTED', 'HYBRID')),
  check (status in (
    'draft', 'inputs_frozen', 'generated', 'partial', 'conflicted',
    'validated', 'published', 'stale', 'cancelled'
  )),
  check (revision >= 1),
  check (status <> 'validated' or validated_at is not null),
  check (status <> 'published' or published_at is not null),
  check (status <> 'cancelled' or cancelled_at is not null),
  unique (operation_id)
);

create unique index if not exists pachanga_venue_allocation_plan_active_scope_idx
  on public.pachanga_competition_venue_allocation_plans(
    competition_id, edition_id, stage_id, schedule_revision_id
  ) where status not in ('published', 'cancelled');
create index if not exists pachanga_venue_allocation_plan_competition_idx
  on public.pachanga_competition_venue_allocation_plans(
    competition_id, edition_id, status, server_sequence desc, id
  );
create index if not exists pachanga_venue_allocation_plan_pool_idx
  on public.pachanga_competition_venue_allocation_plans(
    venue_pool_id, status, server_sequence desc, id
  );

create table if not exists private.pachanga_competition_venue_allocation_input_freezes (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  version integer not null,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  schedule_plan_id uuid not null references public.pachanga_competition_schedule_plans(id) on delete restrict,
  schedule_revision_id uuid not null references public.pachanga_competition_schedule_revisions(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  venue_pool_id uuid not null references public.pachanga_competition_venue_pools(id) on delete restrict,
  venue_pool_revision_id uuid not null references private.pachanga_competition_venue_pool_revisions(id) on delete restrict,
  match_snapshot jsonb not null check (jsonb_typeof(match_snapshot) = 'array'),
  pool_snapshot jsonb not null check (jsonb_typeof(pool_snapshot) = 'array'),
  availability_snapshot jsonb not null check (jsonb_typeof(availability_snapshot) = 'array'),
  recurring_snapshot jsonb not null check (jsonb_typeof(recurring_snapshot) = 'array'),
  reservation_snapshot jsonb not null check (jsonb_typeof(reservation_snapshot) = 'array'),
  binding_snapshot jsonb not null check (jsonb_typeof(binding_snapshot) = 'array'),
  exception_snapshot jsonb not null check (jsonb_typeof(exception_snapshot) = 'array'),
  pitch_snapshot jsonb not null check (jsonb_typeof(pitch_snapshot) = 'array'),
  rule_snapshot jsonb not null check (jsonb_typeof(rule_snapshot) = 'object'),
  match_checksum text not null check (length(match_checksum) = 64),
  schedule_checksum text not null check (length(schedule_checksum) = 64),
  pool_checksum text not null check (length(pool_checksum) = 64),
  availability_checksum text not null check (length(availability_checksum) = 64),
  reservation_checksum text not null check (length(reservation_checksum) = 64),
  binding_checksum text not null check (length(binding_checksum) = 64),
  rule_checksum text not null check (length(rule_checksum) = 64),
  input_checksum text not null check (length(input_checksum) = 64),
  operation_id uuid not null,
  frozen_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique,
  frozen_at timestamptz not null default clock_timestamp(),
  unique (allocation_plan_id, version),
  unique (allocation_plan_id, operation_id)
);

alter table public.pachanga_competition_venue_allocation_plans
  add constraint pachanga_venue_allocation_plan_current_freeze_fk
  foreign key (current_input_freeze_id)
  references private.pachanga_competition_venue_allocation_input_freezes(id) on delete restrict;

create table if not exists public.pachanga_competition_venue_allocation_revisions (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  input_freeze_id uuid not null references private.pachanga_competition_venue_allocation_input_freezes(id) on delete restrict,
  version integer not null,
  revision_kind text not null,
  mode text not null,
  status text not null default 'generated',
  algorithm_version text not null,
  seed text not null,
  input_checksum text not null check (length(input_checksum) = 64),
  result_checksum text not null check (length(result_checksum) = 64),
  constraint_checksum text not null check (length(constraint_checksum) = 64),
  lock_checksum text not null check (length(lock_checksum) = 64),
  search_budget integer not null,
  candidate_count integer not null default 0,
  assigned_count integer not null default 0,
  unassigned_count integer not null default 0,
  hard_violation_count integer not null default 0,
  quality_score numeric(6,3) not null default 0,
  validation_status text not null default 'PENDING',
  supersedes_revision_id uuid references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  operation_id uuid not null,
  generated_by uuid not null references auth.users(id) on delete restrict,
  validated_by uuid references auth.users(id) on delete set null,
  published_by uuid references auth.users(id) on delete set null,
  generated_at timestamptz not null default clock_timestamp(),
  validated_at timestamptz,
  published_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (revision_kind in (
    'generated', 'regenerated', 'manual_assign', 'manual_move',
    'manual_swap', 'manual_remove', 'hybrid_completion'
  )),
  check (mode in ('AUTOMATIC', 'MANUAL_ASSISTED', 'HYBRID')),
  check (status in ('generated', 'partial', 'conflicted', 'validated', 'published', 'superseded', 'cancelled')),
  check (length(algorithm_version) between 3 and 120),
  check (length(seed) between 1 and 160),
  check (search_budget between 1 and 1000000),
  check (candidate_count >= 0 and assigned_count >= 0 and unassigned_count >= 0),
  check (hard_violation_count >= 0),
  check (quality_score between 0 and 100),
  check (validation_status in ('PENDING', 'VALID', 'INVALID', 'STALE_INPUT')),
  check (revision >= 1),
  check (status <> 'validated' or validated_at is not null),
  check (status <> 'published' or published_at is not null),
  unique (allocation_plan_id, version),
  unique (allocation_plan_id, operation_id)
);

alter table public.pachanga_competition_venue_allocation_plans
  add constraint pachanga_venue_allocation_plan_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict;

create index if not exists pachanga_venue_allocation_revision_plan_idx
  on public.pachanga_competition_venue_allocation_revisions(
    allocation_plan_id, version desc, server_sequence desc, id
  );

create table if not exists public.pachanga_competition_venue_allocation_items (
  id uuid primary key,
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  allocation_revision_id uuid not null references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  schedule_item_id uuid not null references public.pachanga_competition_schedule_items(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  round_id uuid not null references public.pachanga_competition_rounds(id) on delete restrict,
  home_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  away_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  scheduled_start timestamptz not null,
  scheduled_end timestamptz not null,
  timezone text not null,
  venue_id uuid references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid references public.pachanga_venue_pitches(id) on delete restrict,
  pool_membership_id uuid references public.pachanga_competition_venue_pool_memberships(id) on delete restrict,
  source_kind text,
  source_id uuid,
  assignment_status text not null default 'UNASSIGNED',
  conflict_codes text[] not null default '{}'::text[],
  warning_codes text[] not null default '{}'::text[],
  manual_override boolean not null default false,
  hold_id uuid references public.pachanga_venue_reservation_holds(id) on delete restrict,
  reservation_id uuid references public.pachanga_venue_reservations(id) on delete restrict,
  binding_id uuid references public.pachanga_venue_match_bindings(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (home_entry_id <> away_entry_id),
  check (scheduled_end > scheduled_start),
  check (length(timezone) between 1 and 80),
  check ((venue_id is null) = (pitch_id is null)),
  check (source_kind is null or source_kind in (
    'AUTHORIZED_PITCH', 'RECURRING_OCCURRENCE', 'CONFIRMED_RESERVATION',
    'PREAUTHORIZED_AVAILABILITY', 'ALLOCATION_HOLD', 'EXISTING_BINDING'
  )),
  check (assignment_status in (
    'UNASSIGNED', 'PROPOSED', 'LOCKED', 'CONFLICT', 'HELD', 'PUBLISHED', 'TBD'
  )),
  check (revision >= 1),
  unique (allocation_revision_id, schedule_item_id),
  unique (allocation_revision_id, canonical_match_id)
);

create index if not exists pachanga_venue_allocation_item_plan_idx
  on public.pachanga_competition_venue_allocation_items(
    allocation_plan_id, allocation_revision_id, round_id, server_sequence, id
  );
create index if not exists pachanga_venue_allocation_item_pitch_idx
  on public.pachanga_competition_venue_allocation_items(
    pitch_id, scheduled_start, scheduled_end, assignment_status, server_sequence, id
  ) where pitch_id is not null;
create index if not exists pachanga_venue_allocation_item_match_idx
  on public.pachanga_competition_venue_allocation_items(
    canonical_match_id, server_sequence desc, id
  );
create index if not exists pachanga_venue_allocation_item_reservation_idx
  on public.pachanga_competition_venue_allocation_items(reservation_id)
  where reservation_id is not null;

create table if not exists private.pachanga_competition_venue_allocation_diffs (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  from_revision_id uuid references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  to_revision_id uuid not null references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  diff jsonb not null check (jsonb_typeof(diff) = 'object'),
  checksum text not null check (length(checksum) = 64),
  server_sequence bigint not null unique,
  created_at timestamptz not null default clock_timestamp(),
  unique (from_revision_id, to_revision_id)
);

comment on table private.pachanga_competition_venue_allocation_input_freezes is
  'Immutable authoritative snapshot of Match times, pool, availability, reservations, bindings and rule inputs.';
comment on table public.pachanga_competition_venue_allocation_items is
  'One Venue proposal per existing CanonicalMatch and ScheduleItem. It never owns sporting date, time or result.';

reset statement_timeout;
reset lock_timeout;
