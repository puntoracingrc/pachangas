-- Pachangas IQ Wave 9B: constraints, manual locks, conflicts, holds and explainable quality.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table if not exists public.pachanga_competition_venue_allocation_constraints (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  constraint_kind text not null,
  constraint_code text not null,
  scope_kind text not null default 'PLAN',
  scope_id uuid,
  weight numeric(8,3) not null default 1,
  parameters jsonb not null default '{}'::jsonb check (jsonb_typeof(parameters) = 'object'),
  reason text not null,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  removed_by uuid references auth.users(id) on delete set null,
  removed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (constraint_kind in ('HARD', 'SOFT')),
  check (constraint_code in (
    'MATCH_TIME_FIXED', 'PITCH_AVAILABLE', 'NO_RESERVATION_OVERLAP',
    'NO_PARENT_CHILD_PITCH_CONFLICT', 'MODALITY_COMPATIBLE',
    'DURATION_COMPATIBLE', 'BUFFER_REQUIRED', 'PITCH_ACTIVE', 'VENUE_ACTIVE',
    'VENUE_POOL_AUTHORIZED', 'COMPETITION_WINDOW', 'RULE_REVISION_MATCH',
    'EXISTING_BINDING_PRESERVED', 'MANUAL_LOCK', 'TIMEZONE_VALID',
    'PREFERRED_VENUE', 'PREFERRED_PITCH', 'HOME_VENUE_PREFERENCE',
    'MINIMIZE_VENUE_CHANGES', 'MAXIMIZE_RECURRING_BLOCK_USAGE',
    'BALANCE_PREMIUM_SLOTS', 'BALANCE_PITCH_USAGE', 'MINIMIZE_TRAVEL_DISTANCE',
    'KEEP_GROUP_TOGETHER', 'FINAL_ON_FEATURED_PITCH',
    'AVOID_CONSECUTIVE_PITCH_CHANGES'
  )),
  check (
    (constraint_kind = 'HARD' and constraint_code in (
      'MATCH_TIME_FIXED', 'PITCH_AVAILABLE', 'NO_RESERVATION_OVERLAP',
      'NO_PARENT_CHILD_PITCH_CONFLICT', 'MODALITY_COMPATIBLE',
      'DURATION_COMPATIBLE', 'BUFFER_REQUIRED', 'PITCH_ACTIVE', 'VENUE_ACTIVE',
      'VENUE_POOL_AUTHORIZED', 'COMPETITION_WINDOW', 'RULE_REVISION_MATCH',
      'EXISTING_BINDING_PRESERVED', 'MANUAL_LOCK', 'TIMEZONE_VALID'
    ))
    or (constraint_kind = 'SOFT' and constraint_code in (
      'PREFERRED_VENUE', 'PREFERRED_PITCH', 'HOME_VENUE_PREFERENCE',
      'MINIMIZE_VENUE_CHANGES', 'MAXIMIZE_RECURRING_BLOCK_USAGE',
      'BALANCE_PREMIUM_SLOTS', 'BALANCE_PITCH_USAGE', 'MINIMIZE_TRAVEL_DISTANCE',
      'KEEP_GROUP_TOGETHER', 'FINAL_ON_FEATURED_PITCH',
      'AVOID_CONSECUTIVE_PITCH_CHANGES'
    ))
  ),
  check (scope_kind in ('PLAN', 'ROUND', 'MATCH', 'TEAM', 'VENUE', 'PITCH')),
  check (weight between 0 and 1000),
  check (length(trim(reason)) between 2 and 1000),
  check (status in ('active', 'removed', 'superseded')),
  check (revision >= 1),
  check (status <> 'removed' or (removed_by is not null and removed_at is not null)),
  unique (operation_id)
);

create index if not exists pachanga_venue_allocation_constraint_plan_idx
  on public.pachanga_competition_venue_allocation_constraints(
    allocation_plan_id, status, constraint_kind, constraint_code, server_sequence, id
  );

create table if not exists public.pachanga_competition_venue_allocation_locks (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  lock_type text not null,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  round_id uuid references public.pachanga_competition_rounds(id) on delete restrict,
  venue_id uuid references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid references public.pachanga_venue_pitches(id) on delete restrict,
  recurring_occurrence_id uuid references public.pachanga_venue_recurring_occurrences(id) on delete restrict,
  reason text not null,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  released_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  released_at timestamptz,
  check (lock_type in (
    'MATCH_TO_VENUE', 'MATCH_TO_PITCH', 'MATCH_TO_RECURRING_OCCURRENCE',
    'MATCH_KEEP_EXISTING_BINDING', 'ROUND_TO_VENUE', 'FINAL_TO_PITCH'
  )),
  check (
    (lock_type = 'MATCH_TO_VENUE' and canonical_match_id is not null and venue_id is not null)
    or (lock_type in ('MATCH_TO_PITCH', 'FINAL_TO_PITCH')
      and canonical_match_id is not null and pitch_id is not null)
    or (lock_type = 'MATCH_TO_RECURRING_OCCURRENCE'
      and canonical_match_id is not null and recurring_occurrence_id is not null)
    or (lock_type = 'MATCH_KEEP_EXISTING_BINDING' and canonical_match_id is not null)
    or (lock_type = 'ROUND_TO_VENUE' and round_id is not null and venue_id is not null)
  ),
  check (length(trim(reason)) between 2 and 1000),
  check (status in ('active', 'released', 'superseded')),
  check (revision >= 1),
  check (status <> 'released' or (released_by is not null and released_at is not null)),
  unique (operation_id)
);

create unique index if not exists pachanga_venue_allocation_lock_active_match_idx
  on public.pachanga_competition_venue_allocation_locks(
    allocation_plan_id, lock_type, canonical_match_id
  ) where status = 'active' and canonical_match_id is not null;
create unique index if not exists pachanga_venue_allocation_lock_active_round_idx
  on public.pachanga_competition_venue_allocation_locks(
    allocation_plan_id, lock_type, round_id
  ) where status = 'active' and round_id is not null;
create index if not exists pachanga_venue_allocation_lock_plan_idx
  on public.pachanga_competition_venue_allocation_locks(
    allocation_plan_id, status, server_sequence, id
  );

create table if not exists private.pachanga_competition_venue_allocation_conflicts (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  allocation_revision_id uuid not null references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  allocation_item_id uuid references public.pachanga_competition_venue_allocation_items(id) on delete restrict,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  conflict_code text not null,
  outcome_code text not null default 'VENUE_ALLOCATION_CONFLICT',
  severity text not null default 'HARD',
  fingerprint text not null check (length(fingerprint) = 64),
  public_explanation text not null,
  private_detail jsonb not null default '{}'::jsonb check (jsonb_typeof(private_detail) = 'object'),
  status text not null default 'active',
  resolved_by_revision_id uuid references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  server_sequence bigint not null unique,
  detected_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  check (outcome_code in (
    'VENUE_ALLOCATION_CONFLICT', 'VENUE_ALLOCATION_UNSATISFIABLE',
    'VENUE_ALLOCATION_SEARCH_BUDGET_EXHAUSTED', 'VENUE_ALLOCATION_PARTIAL',
    'SUGGESTED_SCHEDULE_CHANGE'
  )),
  check (severity in ('HARD', 'SOFT', 'WARNING')),
  check (length(trim(public_explanation)) between 3 and 500),
  check (status in ('active', 'resolved', 'superseded')),
  check (status <> 'resolved' or (resolved_at is not null and resolved_by_revision_id is not null)),
  unique (allocation_revision_id, fingerprint)
);

create index if not exists pachanga_venue_allocation_conflict_plan_idx
  on private.pachanga_competition_venue_allocation_conflicts(
    allocation_plan_id, status, severity, server_sequence, id
  );

create table if not exists private.pachanga_competition_venue_allocation_quality_snapshots (
  id uuid primary key default gen_random_uuid(),
  allocation_revision_id uuid not null unique references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  hard_violations integer not null default 0,
  unassigned_matches integer not null default 0,
  assigned_matches integer not null default 0,
  recurring_block_usage integer not null default 0,
  venue_changes integer not null default 0,
  pitch_utilization jsonb not null default '{}'::jsonb check (jsonb_typeof(pitch_utilization) = 'object'),
  premium_slot_balance jsonb not null default '{}'::jsonb check (jsonb_typeof(premium_slot_balance) = 'object'),
  travel_estimate jsonb not null default '{}'::jsonb check (jsonb_typeof(travel_estimate) = 'object'),
  manual_override_count integer not null default 0,
  locked_assignments integer not null default 0,
  conflicts jsonb not null default '[]'::jsonb check (jsonb_typeof(conflicts) = 'array'),
  warnings jsonb not null default '[]'::jsonb check (jsonb_typeof(warnings) = 'array'),
  explanation jsonb not null default '{}'::jsonb check (jsonb_typeof(explanation) = 'object'),
  score numeric(6,3) not null,
  checksum text not null check (length(checksum) = 64),
  server_sequence bigint not null unique,
  generated_at timestamptz not null default clock_timestamp(),
  check (hard_violations >= 0 and unassigned_matches >= 0 and assigned_matches >= 0),
  check (recurring_block_usage >= 0 and venue_changes >= 0),
  check (manual_override_count >= 0 and locked_assignments >= 0),
  check (score between 0 and 100)
);

create table if not exists public.pachanga_competition_venue_allocation_holds (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  allocation_revision_id uuid not null references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  allocation_item_id uuid not null references public.pachanga_competition_venue_allocation_items(id) on delete restrict,
  wave9a_hold_id uuid not null unique references public.pachanga_venue_reservation_holds(id) on delete restrict,
  expires_at timestamptz not null,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  released_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  check (status in ('active', 'expired', 'released', 'consumed')),
  check (revision >= 1),
  check (expires_at > created_at),
  check ((status = 'active' and released_at is null) or status <> 'active'),
  unique (allocation_revision_id, allocation_item_id),
  unique (operation_id)
);

create index if not exists pachanga_venue_allocation_holds_expiry_idx
  on public.pachanga_competition_venue_allocation_holds(
    expires_at, server_sequence, id
  ) where status = 'active';

create table if not exists private.pachanga_competition_venue_allocation_validations (
  id uuid primary key default gen_random_uuid(),
  allocation_plan_id uuid not null references public.pachanga_competition_venue_allocation_plans(id) on delete restrict,
  allocation_revision_id uuid not null references public.pachanga_competition_venue_allocation_revisions(id) on delete restrict,
  input_checksum text not null check (length(input_checksum) = 64),
  result_checksum text not null check (length(result_checksum) = 64),
  status text not null,
  hard_violation_count integer not null,
  unassigned_required_count integer not null,
  summary jsonb not null check (jsonb_typeof(summary) = 'object'),
  validated_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique,
  validated_at timestamptz not null default clock_timestamp(),
  check (status in ('VALID', 'INVALID', 'STALE_INPUT')),
  check (hard_violation_count >= 0 and unassigned_required_count >= 0),
  unique (allocation_revision_id, input_checksum, result_checksum)
);

comment on table private.pachanga_competition_venue_allocation_quality_snapshots is
  'Precomputed explainable quality; clients never recalculate allocation quality or private-distance inputs.';
comment on table public.pachanga_competition_venue_allocation_locks is
  'Append-only manual intent. Regeneration preserves every active lock or returns an explained conflict.';

reset statement_timeout;
reset lock_timeout;
