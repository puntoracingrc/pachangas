-- Pachangas IQ R6A: DrawPlan, append-only DrawRevision and normalized placements.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.pachanga_competition_draw_plans (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  target_type text not null,
  mode text not null,
  status text not null default 'draft',
  participant_freeze_id uuid references public.pachanga_competition_participant_freezes(id) on delete restrict,
  current_revision_id uuid,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  group_count smallint,
  slot_count smallint,
  qualifiers_per_group smallint,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  published_at timestamptz,
  cancelled_at timestamptz,
  check (target_type in ('GROUP_ASSIGNMENT', 'KNOCKOUT_INITIAL_SEEDING', 'GROUPS_THEN_KNOCKOUT')),
  check (mode in ('PURE_RANDOM', 'SEEDED_POTS', 'CONSTRAINT_OPTIMIZED', 'MANUAL_ASSISTED', 'HYBRID')),
  check (status in ('draft', 'participants_frozen', 'generated', 'validated', 'published', 'cancelled')),
  check (group_count is null or group_count between 1 and 16),
  check (slot_count is null or slot_count between 4 and 128),
  check (qualifiers_per_group is null or qualifiers_per_group between 1 and 16),
  check (revision >= 1),
  check ((status = 'published') = (published_at is not null)),
  check ((status = 'cancelled') = (cancelled_at is not null)),
  unique (competition_id, stage_id)
);

create table public.pachanga_competition_draw_revisions (
  id uuid primary key default gen_random_uuid(),
  draw_plan_id uuid not null references public.pachanga_competition_draw_plans(id) on delete restrict,
  version integer not null,
  mode text not null,
  algorithm_version text not null,
  seed_mode text not null,
  seed text not null,
  seed_revealed boolean not null default false,
  input_checksum text not null,
  participant_checksum text not null,
  pot_checksum text not null,
  constraint_checksum text not null,
  manual_lock_checksum text not null,
  result_checksum text not null,
  validation_status text not null default 'PENDING',
  quality_score numeric(6,3) not null default 0,
  input_snapshot jsonb not null,
  pot_snapshot jsonb not null,
  constraint_snapshot jsonb not null,
  manual_lock_snapshot jsonb not null,
  validation_snapshot jsonb not null default '{}'::jsonb,
  supersedes_revision_id uuid references public.pachanga_competition_draw_revisions(id) on delete restrict,
  generated_by uuid not null references auth.users(id) on delete restrict,
  generated_at timestamptz not null default clock_timestamp(),
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  check (version >= 1),
  check (mode in ('PURE_RANDOM', 'SEEDED_POTS', 'CONSTRAINT_OPTIMIZED', 'MANUAL_ASSISTED', 'HYBRID')),
  check (seed_mode in ('SERVER_SECURE_RANDOM', 'CUSTOM_PUBLIC_SEED')),
  check (length(trim(algorithm_version)) between 3 and 80),
  check (length(seed) between 8 and 256),
  check (length(input_checksum) = 64),
  check (length(participant_checksum) = 64),
  check (length(pot_checksum) = 64),
  check (length(constraint_checksum) = 64),
  check (length(manual_lock_checksum) = 64),
  check (length(result_checksum) = 64),
  check (validation_status in ('PENDING', 'VALID', 'INVALID', 'UNSATISFIABLE', 'STALE')),
  check (quality_score between 0 and 100),
  check (jsonb_typeof(input_snapshot) = 'object'),
  check (jsonb_typeof(pot_snapshot) = 'array'),
  check (jsonb_typeof(constraint_snapshot) = 'array'),
  check (jsonb_typeof(manual_lock_snapshot) = 'array'),
  check (jsonb_typeof(validation_snapshot) = 'object'),
  check (revision = 1),
  unique (draw_plan_id, version)
);

alter table public.pachanga_competition_draw_plans
  add constraint pachanga_competition_draw_plans_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_draw_revisions(id) on delete restrict;

create table public.pachanga_competition_draw_pots (
  id uuid primary key default gen_random_uuid(),
  draw_plan_id uuid not null references public.pachanga_competition_draw_plans(id) on delete restrict,
  pot_number smallint not null,
  label text not null,
  capacity smallint not null,
  entry_ids uuid[] not null default '{}'::uuid[],
  seeding_policy text not null,
  seeding_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (pot_number between 1 and 64),
  check (capacity between 1 and 64),
  check (cardinality(entry_ids) <= capacity),
  check (seeding_policy in ('MANUAL', 'TEAM_LEVEL_SNAPSHOT', 'RANDOM', 'PREVIOUS_POSITION_FUTURE')),
  check (seeding_policy <> 'PREVIOUS_POSITION_FUTURE'),
  check (jsonb_typeof(seeding_snapshot) = 'object'),
  check (status in ('active', 'removed')),
  check (revision >= 1)
);

create unique index pachanga_tournament_draw_pot_active_idx
  on public.pachanga_competition_draw_pots(draw_plan_id, pot_number)
  where status = 'active';

create table public.pachanga_competition_draw_constraints (
  id uuid primary key default gen_random_uuid(),
  draw_plan_id uuid not null references public.pachanga_competition_draw_plans(id) on delete restrict,
  constraint_type text not null,
  strength text not null,
  weight numeric(8,3) not null default 1,
  scope text not null default 'DRAW',
  parameters jsonb not null,
  reason text not null,
  public_attribution boolean not null default true,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (constraint_type in (
    'GROUP_SIZE', 'POT_DISTRIBUTION', 'SEED_SEPARATION', 'SAME_CLUB_AVOIDANCE',
    'TEAM_LEVEL_BALANCE', 'HOST_SEPARATION', 'PREVIOUS_OPPONENT_AVOIDANCE',
    'MANUAL_SEPARATION', 'MANUAL_TOGETHER', 'FIXED_POSITION',
    'BRACKET_HALF_SEPARATION'
  )),
  check (strength in ('HARD', 'SOFT')),
  check (weight between 0 and 100000),
  check (scope in ('DRAW', 'GROUP', 'BRACKET_HALF', 'ENTRY_PAIR')),
  check (jsonb_typeof(parameters) = 'object'),
  check (length(trim(reason)) between 3 and 1200),
  check (status in ('active', 'removed')),
  check (revision >= 1)
);

create table public.pachanga_competition_draw_manual_locks (
  id uuid primary key default gen_random_uuid(),
  draw_plan_id uuid not null references public.pachanga_competition_draw_plans(id) on delete restrict,
  lock_type text not null,
  entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  related_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  target_group_number smallint,
  target_slot smallint,
  target_half smallint,
  pot_number smallint,
  status text not null default 'active',
  reason text not null,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  released_by uuid references auth.users(id) on delete set null,
  released_at timestamptz,
  check (lock_type in ('ENTRY_TO_GROUP', 'ENTRY_TO_SLOT', 'GROUP_SEPARATION', 'BRACKET_HALF', 'POT_POSITION')),
  check (target_group_number is null or target_group_number between 1 and 16),
  check (target_slot is null or target_slot between 1 and 128),
  check (target_half is null or target_half in (1, 2)),
  check (pot_number is null or pot_number between 1 and 64),
  check (status in ('active', 'released')),
  check (length(trim(reason)) between 3 and 1200),
  check (revision >= 1),
  check ((status = 'released') = (released_at is not null))
);

create unique index pachanga_tournament_draw_lock_entry_active_idx
  on public.pachanga_competition_draw_manual_locks(draw_plan_id, entry_id, lock_type)
  where status = 'active' and entry_id is not null;

create table public.pachanga_competition_draw_placements (
  id uuid primary key default gen_random_uuid(),
  draw_revision_id uuid not null references public.pachanga_competition_draw_revisions(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  group_number smallint,
  slot_number smallint,
  seed_number smallint,
  pot_number smallint,
  placement_source text not null,
  manual_lock_id uuid references public.pachanga_competition_draw_manual_locks(id) on delete restrict,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (group_number is null or group_number between 1 and 16),
  check (slot_number is null or slot_number between 1 and 128),
  check (seed_number is null or seed_number between 1 and 128),
  check (pot_number is null or pot_number between 1 and 64),
  check (placement_source in ('ENGINE', 'MANUAL', 'LOCKED', 'HYBRID_FILL')),
  check (group_number is not null or slot_number is not null or seed_number is not null),
  unique (draw_revision_id, entry_id)
);

create unique index pachanga_tournament_draw_group_slot_idx
  on public.pachanga_competition_draw_placements(draw_revision_id, group_number, slot_number)
  where group_number is not null and slot_number is not null;

create unique index pachanga_tournament_draw_seed_idx
  on public.pachanga_competition_draw_placements(draw_revision_id, seed_number)
  where seed_number is not null;

create table public.pachanga_competition_draw_byes (
  id uuid primary key default gen_random_uuid(),
  draw_revision_id uuid not null references public.pachanga_competition_draw_revisions(id) on delete restrict,
  target_slot smallint not null,
  policy text not null,
  beneficiary_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  seed_basis jsonb not null default '{}'::jsonb,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (target_slot between 1 and 128),
  check (policy in ('SEEDED', 'RANDOM', 'MANUAL')),
  check (jsonb_typeof(seed_basis) = 'object'),
  check (revision = 1),
  unique (draw_revision_id, target_slot)
);

create table public.pachanga_competition_draw_quality_snapshots (
  draw_revision_id uuid primary key references public.pachanga_competition_draw_revisions(id) on delete restrict,
  hard_violations integer not null,
  soft_score numeric(10,3) not null,
  level_balance numeric(10,3) not null,
  same_club_collisions integer not null,
  pot_distribution numeric(10,3) not null,
  seed_distribution numeric(10,3) not null,
  group_size_balance numeric(10,3) not null,
  manual_override_count integer not null,
  unassigned_entries integer not null,
  explanations jsonb not null,
  checksum text not null,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (hard_violations >= 0),
  check (same_club_collisions >= 0),
  check (manual_override_count >= 0),
  check (unassigned_entries >= 0),
  check (jsonb_typeof(explanations) = 'array'),
  check (length(checksum) = 64)
);

create index pachanga_tournament_draw_plan_scope_idx
  on public.pachanga_competition_draw_plans(
    competition_id, edition_id, stage_id, server_sequence desc, id desc
  );
create index pachanga_tournament_draw_revision_plan_idx
  on public.pachanga_competition_draw_revisions(
    draw_plan_id, version desc, server_sequence desc, id desc
  );
create index pachanga_tournament_draw_constraint_plan_idx
  on public.pachanga_competition_draw_constraints(
    draw_plan_id, status, constraint_type, server_sequence desc, id desc
  );
create index pachanga_tournament_draw_lock_plan_idx
  on public.pachanga_competition_draw_manual_locks(
    draw_plan_id, status, server_sequence desc, id desc
  );
create index pachanga_tournament_draw_placement_revision_idx
  on public.pachanga_competition_draw_placements(
    draw_revision_id, group_number, slot_number, seed_number, entry_id
  );

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_competition_draw_plans',
    'pachanga_competition_draw_revisions',
    'pachanga_competition_draw_pots',
    'pachanga_competition_draw_constraints',
    'pachanga_competition_draw_manual_locks',
    'pachanga_competition_draw_placements',
    'pachanga_competition_draw_byes',
    'pachanga_competition_draw_quality_snapshots'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

create trigger guard_pachanga_tournament_draw_revision_v1
before update or delete on public.pachanga_competition_draw_revisions
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_draw_placement_v1
before update or delete on public.pachanga_competition_draw_placements
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_draw_bye_v1
before update or delete on public.pachanga_competition_draw_byes
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_draw_quality_v1
before update or delete on public.pachanga_competition_draw_quality_snapshots
for each row execute function private.pachanga_tournament_guard_immutable_v1();

comment on table public.pachanga_competition_draw_revisions is
  'Append-only deterministic draw evidence. Validation creates a new revision instead of rewriting one.';
comment on table public.pachanga_competition_draw_placements is
  'Immutable placements bound to one DrawRevision. No row creates a Tournament match.';
