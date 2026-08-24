-- Pachangas IQ R4C: canonical League match operations, sporting results and standings.
-- All product flags are OFF by default. This migration creates no competition data.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists league_match_operations_foundation_enabled boolean not null default false,
  add column if not exists league_match_squads_enabled boolean not null default false,
  add column if not exists league_match_attendance_enabled boolean not null default false,
  add column if not exists league_sporting_results_enabled boolean not null default false,
  add column if not exists league_result_confirmation_enabled boolean not null default false,
  add column if not exists league_official_results_enabled boolean not null default false,
  add column if not exists league_standings_enabled boolean not null default false,
  add column if not exists league_public_standings_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_r4c_flags_check,
  add constraint pachanga_comp_foundation_r4c_flags_check check (
    (not league_match_operations_foundation_enabled or (
      league_participation_foundation_enabled and league_scheduling_foundation_enabled
    ))
    and (not league_match_squads_enabled or (
      league_match_operations_foundation_enabled and league_rosters_enabled
    ))
    and (not league_match_attendance_enabled or league_match_operations_foundation_enabled)
    and (not league_sporting_results_enabled or league_match_operations_foundation_enabled)
    and (not league_result_confirmation_enabled or league_sporting_results_enabled)
    and (not league_official_results_enabled or (
      league_sporting_results_enabled and league_result_confirmation_enabled
    ))
    and (not league_standings_enabled or league_official_results_enabled)
    and (not league_public_standings_enabled or league_standings_enabled)
  );

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_grants_capability_check,
  add constraint pachanga_competition_entitlement_grants_capability_check check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline', 'competition_entries_manage',
    'competition_rosters_review', 'competition_categories_manage', 'competition_schedule',
    'competition_results', 'competition_standings'
  ));

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'competition_schedule_manager',
    'competition_result_manager', 'competition_standings_manager', 'viewer'
  ));

alter table public.pachanga_competition_match_contexts
  drop constraint if exists pachanga_competition_match_contexts_status_check,
  add constraint pachanga_competition_match_contexts_status_check check (status in (
    'lab_bound', 'scheduled', 'ready', 'in_progress', 'played',
    'result_pending', 'official', 'retired'
  ));

drop index if exists public.pachanga_competition_context_active_match_idx;
create unique index pachanga_competition_context_active_match_idx
  on public.pachanga_competition_match_contexts(canonical_match_id)
  where status in (
    'lab_bound', 'scheduled', 'ready', 'in_progress', 'played',
    'result_pending', 'official'
  );

alter table public.pachanga_competition_rounds
  drop constraint if exists pachanga_competition_rounds_status_check,
  add constraint pachanga_competition_rounds_status_check check (
    status in ('draft', 'published', 'in_progress', 'completed', 'locked', 'cancelled')
  );

-- Attendance V1 remains the only pre-match attendance authority. Its legacy
-- group identity is preserved while competition-generated CanonicalMatches get
-- a disjoint identity in the same table.
alter table public.pachanga_match_participants
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  add column if not exists competition_match_context_id uuid references public.pachanga_competition_match_contexts(id) on delete restrict,
  add column if not exists competition_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  add column if not exists roster_member_id uuid references public.pachanga_competition_roster_members(id) on delete restrict,
  add column if not exists player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  add column if not exists revision bigint not null default 1,
  add column if not exists server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  add column if not exists changed_by uuid references auth.users(id) on delete restrict;

alter table public.pachanga_match_participants
  alter column id set not null;

alter table public.pachanga_match_participants
  drop constraint if exists pachanga_match_participants_pkey,
  add constraint pachanga_match_participants_pkey primary key (id);

alter table public.pachanga_match_participants
  alter column group_id drop not null,
  alter column match_id drop not null,
  alter column player_id drop not null,
  add constraint pachanga_match_participants_legacy_identity_key unique (group_id, match_id, player_id),
  add constraint pachanga_match_participants_scope_check check (
    (
      canonical_match_id is null
      and group_id is not null and match_id is not null and player_id is not null
      and competition_match_context_id is null and competition_entry_id is null
      and roster_member_id is null and player_profile_id is null
    )
    or
    (
      canonical_match_id is not null
      and group_id is null and match_id is null and player_id is null
      and competition_match_context_id is not null and competition_entry_id is not null
      and roster_member_id is not null and player_profile_id is not null
    )
  ),
  add constraint pachanga_match_participants_revision_check check (revision >= 1);

create unique index pachanga_match_participants_canonical_profile_idx
  on public.pachanga_match_participants(canonical_match_id, player_profile_id)
  where canonical_match_id is not null;
create unique index pachanga_match_participants_canonical_roster_idx
  on public.pachanga_match_participants(canonical_match_id, roster_member_id)
  where canonical_match_id is not null;

comment on table public.pachanga_match_participants is
  'Single pre-match Attendance V1 authority for legacy group matches and competition-generated CanonicalMatches.';

create table public.pachanga_competition_match_squads (
  id uuid primary key default gen_random_uuid(),
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  roster_id uuid not null references public.pachanga_competition_rosters(id) on delete restrict,
  roster_revision_id uuid not null references public.pachanga_competition_roster_revisions(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  side text not null,
  status text not null default 'draft',
  current_revision_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_at timestamptz,
  validated_by uuid references auth.users(id) on delete set null,
  validated_at timestamptz,
  rejected_by uuid references auth.users(id) on delete set null,
  rejected_at timestamptz,
  locked_by uuid references auth.users(id) on delete set null,
  locked_at timestamptz,
  rejection_reason_private text not null default '',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (side in ('HOME', 'AWAY')),
  check (status in ('draft', 'submitted', 'validated', 'rejected', 'locked')),
  check (revision >= 1),
  check (length(rejection_reason_private) <= 1200),
  unique (canonical_match_id, entry_id),
  unique (canonical_match_id, side)
);

create table public.pachanga_competition_match_squad_revisions (
  id uuid primary key default gen_random_uuid(),
  squad_id uuid not null references public.pachanga_competition_match_squads(id) on delete restrict,
  version integer not null,
  squad_status text not null,
  roster_revision_id uuid not null references public.pachanga_competition_roster_revisions(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  member_count integer not null default 0,
  starter_count integer not null default 0,
  substitute_count integer not null default 0,
  captain_player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  member_set_checksum text not null,
  lineup_checksum text not null,
  reason text not null,
  effective_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (squad_status in ('draft', 'submitted', 'validated', 'rejected', 'locked')),
  check (member_count >= 0 and starter_count >= 0 and substitute_count >= 0),
  check (starter_count + substitute_count = member_count),
  check (length(member_set_checksum) = 64),
  check (length(lineup_checksum) = 64),
  check (length(trim(reason)) between 3 and 1200),
  unique (squad_id, version)
);

alter table public.pachanga_competition_match_squads
  add constraint pachanga_competition_match_squads_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_match_squad_revisions(id) on delete restrict;

create table public.pachanga_competition_match_squad_members (
  id uuid primary key default gen_random_uuid(),
  squad_revision_id uuid not null references public.pachanga_competition_match_squad_revisions(id) on delete restrict,
  roster_member_id uuid not null references public.pachanga_competition_roster_members(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  member_role text not null,
  shirt_number integer,
  position_order integer not null default 0,
  is_captain boolean not null default false,
  public_snapshot jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (member_role in ('STARTER', 'SUBSTITUTE')),
  check (shirt_number is null or shirt_number between 0 and 999),
  check (position_order >= 0),
  check (jsonb_typeof(public_snapshot) = 'object'),
  unique (squad_revision_id, roster_member_id),
  unique (squad_revision_id, player_profile_id)
);

create unique index pachanga_match_squad_member_captain_idx
  on public.pachanga_competition_match_squad_members(squad_revision_id)
  where is_captain;
create unique index pachanga_match_squad_member_number_idx
  on public.pachanga_competition_match_squad_members(squad_revision_id, shirt_number)
  where shirt_number is not null;

create table public.pachanga_competition_match_sheets (
  id uuid primary key default gen_random_uuid(),
  canonical_match_id uuid not null unique references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null unique references public.pachanga_competition_match_contexts(id) on delete restrict,
  home_squad_id uuid references public.pachanga_competition_match_squads(id) on delete restrict,
  away_squad_id uuid references public.pachanga_competition_match_squads(id) on delete restrict,
  current_sporting_result_id uuid,
  active_official_decision_id uuid,
  home_attendance_closed_by uuid references auth.users(id) on delete set null,
  home_attendance_closed_at timestamptz,
  away_attendance_closed_by uuid references auth.users(id) on delete set null,
  away_attendance_closed_at timestamptz,
  discipline_validation_status text not null default 'NOT_AVAILABLE',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (discipline_validation_status = 'NOT_AVAILABLE'),
  check ((home_attendance_closed_by is null) = (home_attendance_closed_at is null)),
  check ((away_attendance_closed_by is null) = (away_attendance_closed_at is null)),
  check (revision >= 1)
);

create table public.pachanga_competition_sporting_results (
  id uuid primary key default gen_random_uuid(),
  canonical_match_id uuid not null unique references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null unique references public.pachanga_competition_match_contexts(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  state text not null default 'submitted',
  current_revision_id uuid,
  proposed_by_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  pending_response_from_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  response_deadline timestamptz,
  confirmation_policy text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  confirmed_at timestamptz,
  disputed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (state in ('submitted', 'change_proposed', 'confirmed', 'disputed', 'official', 'annulled')),
  check (confirmation_policy in ('BILATERAL', 'AUTO_CONFIRM_AFTER_DEADLINE')),
  check (revision >= 1)
);

create table public.pachanga_competition_sporting_result_revisions (
  id uuid primary key default gen_random_uuid(),
  sporting_result_id uuid not null references public.pachanga_competition_sporting_results(id) on delete restrict,
  version integer not null,
  previous_revision_id uuid references public.pachanga_competition_sporting_result_revisions(id) on delete restrict,
  revision_kind text not null,
  proposed_by_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  score_home integer not null,
  score_away integer not null,
  shootout_home integer,
  shootout_away integer,
  scorer_detail_policy text not null,
  home_scorer_total integer not null default 0,
  away_scorer_total integer not null default 0,
  home_unassigned_goals integer not null default 0,
  away_unassigned_goals integer not null default 0,
  content_checksum text not null,
  operation_id uuid not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (revision_kind in ('INITIAL', 'CHANGE', 'ACCEPTANCE')),
  check (score_home >= 0 and score_away >= 0),
  check (shootout_home is null and shootout_away is null),
  check (scorer_detail_policy in ('REQUIRED', 'OPTIONAL', 'DISABLED')),
  check (home_scorer_total >= 0 and away_scorer_total >= 0),
  check (home_unassigned_goals >= 0 and away_unassigned_goals >= 0),
  check (length(content_checksum) = 64),
  unique (sporting_result_id, version)
);

alter table public.pachanga_competition_sporting_results
  add constraint pachanga_competition_sporting_results_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_sporting_result_revisions(id) on delete restrict;

alter table public.pachanga_competition_match_sheets
  add constraint pachanga_competition_match_sheets_current_result_fk
  foreign key (current_sporting_result_id)
  references public.pachanga_competition_sporting_results(id) on delete restrict;

create table public.pachanga_competition_sporting_result_scorers (
  id uuid primary key default gen_random_uuid(),
  sporting_result_revision_id uuid not null references public.pachanga_competition_sporting_result_revisions(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  roster_member_id uuid references public.pachanga_competition_roster_members(id) on delete restrict,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  unknown_scorer_slot integer,
  goals integer not null,
  display_name_snapshot text,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (goals > 0),
  check (unknown_scorer_slot is null or unknown_scorer_slot >= 1),
  check (
    (player_profile_id is not null and roster_member_id is not null and unknown_scorer_slot is null)
    or (player_profile_id is null and roster_member_id is null and unknown_scorer_slot is not null)
  ),
  check (display_name_snapshot is null or length(trim(display_name_snapshot)) between 1 and 120)
);

create unique index pachanga_sporting_result_known_scorer_idx
  on public.pachanga_competition_sporting_result_scorers(
    sporting_result_revision_id, entry_id, player_profile_id
  ) where player_profile_id is not null;
create unique index pachanga_sporting_result_unknown_scorer_idx
  on public.pachanga_competition_sporting_result_scorers(
    sporting_result_revision_id, entry_id, unknown_scorer_slot
  ) where unknown_scorer_slot is not null;

create table public.pachanga_competition_result_responses (
  id uuid primary key default gen_random_uuid(),
  sporting_result_id uuid not null references public.pachanga_competition_sporting_results(id) on delete restrict,
  sporting_result_revision_id uuid not null references public.pachanga_competition_sporting_result_revisions(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  response_kind text not null,
  proposed_score_home integer,
  proposed_score_away integer,
  reason_private text not null default '',
  operation_id uuid not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (response_kind in ('ACCEPT', 'PROPOSE_CHANGE', 'DISPUTE')),
  check (proposed_score_home is null or proposed_score_home >= 0),
  check (proposed_score_away is null or proposed_score_away >= 0),
  check ((proposed_score_home is null) = (proposed_score_away is null)),
  check (length(reason_private) <= 1200)
);

create table public.pachanga_competition_official_result_decisions (
  id uuid primary key default gen_random_uuid(),
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  sporting_result_id uuid references public.pachanga_competition_sporting_results(id) on delete restrict,
  sporting_result_revision_id uuid references public.pachanga_competition_sporting_result_revisions(id) on delete restrict,
  supersedes_decision_id uuid references public.pachanga_competition_official_result_decisions(id) on delete restrict,
  outcome text not null,
  effective_score_home integer,
  effective_score_away integer,
  public_explanation text not null default '',
  reason_code text not null,
  points_adjustments jsonb not null default '[]'::jsonb,
  operation_id uuid not null unique,
  authority_role text not null,
  decided_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  decided_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (outcome in ('MIRROR_SPORTING_RESULT', 'CORRECTED_EFFECTIVE_SCORE', 'ANNULLED')),
  check (effective_score_home is null or effective_score_home >= 0),
  check (effective_score_away is null or effective_score_away >= 0),
  check ((effective_score_home is null) = (effective_score_away is null)),
  check ((outcome = 'ANNULLED') = (effective_score_home is null)),
  check (jsonb_typeof(points_adjustments) = 'array' and jsonb_array_length(points_adjustments) = 0),
  check (length(public_explanation) <= 500),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(trim(authority_role)) between 3 and 80)
);

alter table public.pachanga_competition_match_sheets
  add constraint pachanga_competition_match_sheets_official_decision_fk
  foreign key (active_official_decision_id)
  references public.pachanga_competition_official_result_decisions(id) on delete restrict;

create table private.pachanga_competition_official_result_evidence (
  official_result_decision_id uuid primary key references public.pachanga_competition_official_result_decisions(id) on delete restrict,
  evidence jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  check (jsonb_typeof(evidence) = 'object')
);

create table public.pachanga_competition_standing_states (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  current_snapshot_id uuid,
  health_status text not null default 'PENDING',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (health_status in ('PENDING', 'CURRENT', 'STALE', 'ERROR')),
  check (revision >= 1)
);

create unique index pachanga_competition_standing_state_scope_idx
  on public.pachanga_competition_standing_states(
    stage_id,
    coalesce(division_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(competition_group_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table public.pachanga_competition_standing_snapshots (
  id uuid primary key default gen_random_uuid(),
  standing_state_id uuid not null references public.pachanga_competition_standing_states(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  supersedes_snapshot_id uuid references public.pachanga_competition_standing_snapshots(id) on delete restrict,
  rebuild_kind text not null,
  engine_version text not null default 'league-standings-v1',
  source_revision bigint not null,
  row_count integer not null default 0,
  tie_break_criteria jsonb not null,
  content_checksum text not null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  generated_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (rebuild_kind in ('INCREMENTAL', 'FULL_AUDIT')),
  check (engine_version = 'league-standings-v1'),
  check (source_revision >= 0 and row_count >= 0),
  check (jsonb_typeof(tie_break_criteria) = 'array'),
  check (length(content_checksum) = 64)
);

alter table public.pachanga_competition_standing_states
  add constraint pachanga_competition_standing_states_current_snapshot_fk
  foreign key (current_snapshot_id)
  references public.pachanga_competition_standing_snapshots(id) on delete restrict;

create table public.pachanga_competition_standing_rows (
  id uuid primary key default gen_random_uuid(),
  standing_snapshot_id uuid not null references public.pachanga_competition_standing_snapshots(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  position integer not null,
  played integer not null default 0,
  wins integer not null default 0,
  draws integer not null default 0,
  losses integer not null default 0,
  goals_for integer not null default 0,
  goals_against integer not null default 0,
  goal_difference integer not null default 0,
  base_points numeric(12,3) not null default 0,
  adjustment_points numeric(12,3) not null default 0,
  effective_points numeric(12,3) not null default 0,
  tie_break_values jsonb not null default '[]'::jsonb,
  team_snapshot jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (position >= 1),
  check (played >= 0 and wins >= 0 and draws >= 0 and losses >= 0),
  check (goals_for >= 0 and goals_against >= 0),
  check (played = wins + draws + losses),
  check (goal_difference = goals_for - goals_against),
  check (jsonb_typeof(tie_break_values) = 'array'),
  check (jsonb_typeof(team_snapshot) = 'object'),
  unique (standing_snapshot_id, entry_id)
);

create table public.pachanga_competition_tie_break_explanations (
  id uuid primary key default gen_random_uuid(),
  standing_snapshot_id uuid not null references public.pachanga_competition_standing_snapshots(id) on delete restrict,
  tie_group_key text not null,
  candidate_entry_ids uuid[] not null,
  criterion text not null,
  criterion_order integer not null,
  values_by_entry jsonb not null,
  resolved boolean not null default false,
  public_explanation text not null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (cardinality(candidate_entry_ids) >= 2),
  check (criterion_order >= 0),
  check (jsonb_typeof(values_by_entry) = 'object'),
  check (length(trim(public_explanation)) between 3 and 500)
);

create table public.pachanga_competition_persisted_draw_lots (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  tie_group_key text not null,
  candidate_entry_ids uuid[] not null,
  candidate_checksum text not null,
  seed text not null,
  algorithm text not null default 'sha256-order-v1',
  result_entry_ids uuid[] not null,
  operation_id uuid not null unique,
  confirmed_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  confirmed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (cardinality(candidate_entry_ids) >= 2),
  check (cardinality(result_entry_ids) = cardinality(candidate_entry_ids)),
  check (length(candidate_checksum) = 64),
  check (length(trim(seed)) between 1 and 160),
  check (algorithm = 'sha256-order-v1'),
  unique (stage_id, tie_group_key)
);

create table public.pachanga_competition_standing_rebuild_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  standing_state_id uuid not null references public.pachanga_competition_standing_states(id) on delete restrict,
  standing_snapshot_id uuid not null references public.pachanga_competition_standing_snapshots(id) on delete restrict,
  rebuild_kind text not null,
  source_revision bigint not null,
  previous_checksum text,
  confirmed_checksum text not null,
  full_audit_checksum text,
  duration_ms integer not null default 0,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (rebuild_kind in ('INCREMENTAL', 'FULL_AUDIT')),
  check (source_revision >= 0 and duration_ms >= 0),
  check (previous_checksum is null or length(previous_checksum) = 64),
  check (length(confirmed_checksum) = 64),
  check (full_audit_checksum is null or length(full_audit_checksum) = 64)
);

create index pachanga_match_attendance_context_idx
  on public.pachanga_match_participants(
    competition_match_context_id, competition_entry_id, server_sequence desc, id desc
  ) where canonical_match_id is not null;
create index pachanga_match_squads_context_idx
  on public.pachanga_competition_match_squads(competition_match_context_id, side);
create index pachanga_match_squad_revisions_latest_idx
  on public.pachanga_competition_match_squad_revisions(squad_id, version desc, server_sequence desc);
create index pachanga_sporting_result_revisions_latest_idx
  on public.pachanga_competition_sporting_result_revisions(sporting_result_id, version desc, server_sequence desc);
create index pachanga_official_results_stage_source_idx
  on public.pachanga_competition_official_result_decisions(competition_match_context_id, server_sequence desc, id desc);
create index pachanga_standing_snapshots_state_idx
  on public.pachanga_competition_standing_snapshots(standing_state_id, server_sequence desc, id desc);
create index pachanga_standing_rows_snapshot_position_idx
  on public.pachanga_competition_standing_rows(standing_snapshot_id, position, entry_id);

alter table public.pachanga_competition_match_squads enable row level security;
alter table public.pachanga_competition_match_squad_revisions enable row level security;
alter table public.pachanga_competition_match_squad_members enable row level security;
alter table public.pachanga_competition_match_sheets enable row level security;
alter table public.pachanga_competition_sporting_results enable row level security;
alter table public.pachanga_competition_sporting_result_revisions enable row level security;
alter table public.pachanga_competition_sporting_result_scorers enable row level security;
alter table public.pachanga_competition_result_responses enable row level security;
alter table public.pachanga_competition_official_result_decisions enable row level security;
alter table public.pachanga_competition_standing_states enable row level security;
alter table public.pachanga_competition_standing_snapshots enable row level security;
alter table public.pachanga_competition_standing_rows enable row level security;
alter table public.pachanga_competition_tie_break_explanations enable row level security;
alter table public.pachanga_competition_persisted_draw_lots enable row level security;
alter table public.pachanga_competition_standing_rebuild_receipts enable row level security;

revoke all on table public.pachanga_competition_match_squads from public, anon, authenticated;
revoke all on table public.pachanga_competition_match_squad_revisions from public, anon, authenticated;
revoke all on table public.pachanga_competition_match_squad_members from public, anon, authenticated;
revoke all on table public.pachanga_competition_match_sheets from public, anon, authenticated;
revoke all on table public.pachanga_competition_sporting_results from public, anon, authenticated;
revoke all on table public.pachanga_competition_sporting_result_revisions from public, anon, authenticated;
revoke all on table public.pachanga_competition_sporting_result_scorers from public, anon, authenticated;
revoke all on table public.pachanga_competition_result_responses from public, anon, authenticated;
revoke all on table public.pachanga_competition_official_result_decisions from public, anon, authenticated;
revoke all on table public.pachanga_competition_standing_states from public, anon, authenticated;
revoke all on table public.pachanga_competition_standing_snapshots from public, anon, authenticated;
revoke all on table public.pachanga_competition_standing_rows from public, anon, authenticated;
revoke all on table public.pachanga_competition_tie_break_explanations from public, anon, authenticated;
revoke all on table public.pachanga_competition_persisted_draw_lots from public, anon, authenticated;
revoke all on table public.pachanga_competition_standing_rebuild_receipts from public, anon, authenticated;
revoke all on table private.pachanga_competition_official_result_evidence from public, anon, authenticated;

grant all on table public.pachanga_competition_match_squads to service_role;
grant all on table public.pachanga_competition_match_squad_revisions to service_role;
grant all on table public.pachanga_competition_match_squad_members to service_role;
grant all on table public.pachanga_competition_match_sheets to service_role;
grant all on table public.pachanga_competition_sporting_results to service_role;
grant all on table public.pachanga_competition_sporting_result_revisions to service_role;
grant all on table public.pachanga_competition_sporting_result_scorers to service_role;
grant all on table public.pachanga_competition_result_responses to service_role;
grant all on table public.pachanga_competition_official_result_decisions to service_role;
grant all on table public.pachanga_competition_standing_states to service_role;
grant all on table public.pachanga_competition_standing_snapshots to service_role;
grant all on table public.pachanga_competition_standing_rows to service_role;
grant all on table public.pachanga_competition_tie_break_explanations to service_role;
grant all on table public.pachanga_competition_persisted_draw_lots to service_role;
grant all on table public.pachanga_competition_standing_rebuild_receipts to service_role;
grant all on table private.pachanga_competition_official_result_evidence to service_role;

comment on table public.pachanga_competition_match_sheets is
  'Minimal R4C sheet linking the CanonicalMatch to locked squads and current sporting/official authorities.';
comment on table public.pachanga_competition_official_result_decisions is
  'Append-only official result lineage. The active decision is selected by the MatchSheet pointer.';
comment on table public.pachanga_competition_standing_snapshots is
  'Immutable standings materialization. Reads use the explicit StandingState current_snapshot_id pointer.';
