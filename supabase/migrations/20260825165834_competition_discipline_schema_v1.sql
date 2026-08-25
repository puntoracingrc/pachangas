-- Pachangas IQ R5: configurable competition discipline foundation.
-- Every feature gate is born OFF and this migration creates no sporting data.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists competition_discipline_foundation_enabled boolean not null default false,
  add column if not exists competition_disciplinary_events_enabled boolean not null default false,
  add column if not exists competition_disciplinary_counters_enabled boolean not null default false,
  add column if not exists competition_sanctions_enabled boolean not null default false,
  add column if not exists competition_sanction_service_enabled boolean not null default false,
  add column if not exists competition_discipline_appeals_enabled boolean not null default false,
  add column if not exists competition_public_discipline_enabled boolean not null default false;

-- R5 commands share one competition-scoped optimistic-concurrency stream.
-- Entity revisions below remain append-only history versions, while this value
-- is the client/server command revision that prevents cross-aggregate races.
alter table public.pachanga_competitions
  add column if not exists discipline_revision bigint not null default 0;

alter table public.pachanga_competitions
  drop constraint if exists pachanga_competitions_discipline_revision_check,
  add constraint pachanga_competitions_discipline_revision_check
    check (discipline_revision >= 0);

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_r5_flags_check,
  add constraint pachanga_comp_foundation_r5_flags_check check (
    (not competition_discipline_foundation_enabled
      or league_match_operations_foundation_enabled)
    and (not competition_disciplinary_events_enabled
      or competition_discipline_foundation_enabled)
    and (not competition_disciplinary_counters_enabled
      or competition_disciplinary_events_enabled)
    and (not competition_sanctions_enabled
      or competition_disciplinary_counters_enabled)
    and (not competition_sanction_service_enabled
      or competition_sanctions_enabled)
    and (not competition_discipline_appeals_enabled
      or competition_sanctions_enabled)
    and (not competition_public_discipline_enabled
      or competition_discipline_foundation_enabled)
  );

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_grants_capability_check,
  add constraint pachanga_competition_entitlement_grants_capability_check check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline', 'competition_entries_manage',
    'competition_rosters_review', 'competition_categories_manage', 'competition_schedule',
    'competition_results', 'competition_standings', 'competition_operations',
    'competition_discipline_manage', 'competition_discipline_review',
    'competition_appeals_manage'
  ));

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'competition_schedule_manager',
    'competition_result_manager', 'competition_standings_manager',
    'competition_operations_manager', 'competition_discipline_manager',
    'competition_discipline_reviewer', 'competition_appeals_manager', 'viewer'
  ));

-- A version-bound immutable extension of CompetitionRuleRevision. The catalog is
-- part of the rule revision contract without rewriting an already published JSON document.
create table public.pachanga_competition_discipline_rule_catalogs (
  rule_revision_id uuid primary key
    references public.pachanga_competition_rule_revisions(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  policy_version text not null,
  card_type_catalog jsonb not null,
  cycle_policy jsonb not null,
  sanction_policy jsonb not null,
  appeal_policy jsonb not null,
  public_reason_categories jsonb not null default '[]'::jsonb,
  checksum text not null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  check (length(trim(policy_version)) between 3 and 80),
  check (jsonb_typeof(card_type_catalog) = 'array' and jsonb_array_length(card_type_catalog) > 0),
  check (jsonb_typeof(cycle_policy) = 'object'),
  check (jsonb_typeof(sanction_policy) = 'object'),
  check (jsonb_typeof(appeal_policy) = 'object'),
  check (jsonb_typeof(public_reason_categories) = 'array'),
  check (length(checksum) = 64)
);

create table public.pachanga_competition_disciplinary_cycles (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid references public.pachanga_competition_stages(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  scope_type text not null,
  status text not null default 'active',
  carry_policy text not null,
  effective_from timestamptz not null,
  effective_until timestamptz,
  previous_cycle_id uuid references public.pachanga_competition_disciplinary_cycles(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (scope_type in ('EDITION', 'STAGE', 'GROUP', 'SPLIT')),
  check (status in ('active', 'closed', 'superseded')),
  check (carry_policy in ('RESET', 'CARRY')),
  check (effective_until is null or effective_until > effective_from),
  check (
    (scope_type = 'EDITION' and stage_id is null and competition_group_id is null)
    or (scope_type in ('STAGE', 'SPLIT') and stage_id is not null and competition_group_id is null)
    or (scope_type = 'GROUP' and stage_id is not null and competition_group_id is not null)
  ),
  check (revision >= 1)
);

create unique index pachanga_discipline_active_cycle_scope_idx
  on public.pachanga_competition_disciplinary_cycles(
    competition_id,
    scope_type,
    coalesce(stage_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(competition_group_id, '00000000-0000-0000-0000-000000000000'::uuid)
  ) where status = 'active';

create table public.pachanga_competition_disciplinary_events (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  match_sheet_id uuid references public.pachanga_competition_match_sheets(id) on delete restrict,
  cycle_id uuid not null references public.pachanga_competition_disciplinary_cycles(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  status text not null default 'active',
  current_revision_id uuid,
  current_card_type_code text not null,
  creation_operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('active', 'annulled', 'superseded')),
  check (length(trim(current_card_type_code)) between 1 and 40),
  check (revision >= 1)
);

create table public.pachanga_competition_disciplinary_event_revisions (
  id uuid primary key default gen_random_uuid(),
  disciplinary_event_id uuid not null references public.pachanga_competition_disciplinary_events(id) on delete restrict,
  version integer not null,
  previous_revision_id uuid references public.pachanga_competition_disciplinary_event_revisions(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  card_type_code text not null,
  event_context text not null,
  match_minute integer,
  period_code text,
  event_status text not null,
  public_reason_category text,
  public_summary text not null default '',
  rule_outcome jsonb not null,
  correction_reason text not null,
  operation_id uuid not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (length(trim(card_type_code)) between 1 and 40),
  check (event_context in ('pre_match', 'in_match', 'interval', 'post_match', 'venue')),
  check (match_minute is null or match_minute between 0 and 300),
  check (period_code is null or length(trim(period_code)) between 1 and 40),
  check (event_status in ('active', 'annulled')),
  check (public_reason_category is null or length(trim(public_reason_category)) between 1 and 80),
  check (length(public_summary) <= 500),
  check (jsonb_typeof(rule_outcome) = 'object'),
  check (length(trim(correction_reason)) between 3 and 1200),
  unique (disciplinary_event_id, version)
);

alter table public.pachanga_competition_disciplinary_events
  add constraint pachanga_disciplinary_events_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_disciplinary_event_revisions(id) on delete restrict;

create table public.pachanga_competition_disciplinary_counters (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  cycle_id uuid not null references public.pachanga_competition_disciplinary_cycles(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  card_type_code text not null,
  active_event_count integer not null default 0,
  carried_points integer not null default 0,
  accumulation_points integer not null default 0,
  threshold_hits integer not null default 0,
  last_event_server_sequence bigint not null default 0,
  state_checksum text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (active_event_count >= 0 and carried_points >= 0
    and accumulation_points >= carried_points and threshold_hits >= 0),
  check (last_event_server_sequence >= 0),
  check (length(trim(card_type_code)) between 1 and 40),
  check (length(state_checksum) = 64),
  check (revision >= 1),
  unique (cycle_id, player_profile_id, card_type_code)
);

create table public.pachanga_competition_sanctions (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  cycle_id uuid not null references public.pachanga_competition_disciplinary_cycles(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  source_event_id uuid references public.pachanga_competition_disciplinary_events(id) on delete restrict,
  target_type text not null default 'PLAYER',
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  sanction_outcome text not null,
  status text not null,
  unit_type text,
  total_units integer,
  remaining_units integer,
  suspensive_hold boolean not null default false,
  current_revision_id uuid,
  creation_operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (target_type in ('PLAYER', 'TEAM')),
  check (
    (target_type = 'PLAYER' and player_profile_id is not null and entry_id is null)
    or (target_type = 'TEAM' and player_profile_id is null and entry_id is not null)
  ),
  check (sanction_outcome in (
    'NO_SANCTION', 'FIXED_SANCTION', 'PROVISIONAL_SANCTION',
    'COMMITTEE_REQUIRED', 'SANCTION_RANGE'
  )),
  check (status in (
    'no_sanction', 'provisional', 'under_review', 'active',
    'served', 'overturned', 'cancelled'
  )),
  check (unit_type is null or unit_type in (
    'MATCHES', 'ROUNDS', 'WEEKS', 'STAGE', 'COMPETITION_EXPULSION'
  )),
  check (
    (sanction_outcome = 'NO_SANCTION' and total_units is null and remaining_units is null)
    or (sanction_outcome <> 'NO_SANCTION' and unit_type is not null
      and total_units is not null and total_units >= 0
      and remaining_units is not null and remaining_units between 0 and total_units)
  ),
  check (revision >= 1)
);

create table public.pachanga_competition_sanction_revisions (
  id uuid primary key default gen_random_uuid(),
  sanction_id uuid not null references public.pachanga_competition_sanctions(id) on delete restrict,
  version integer not null,
  previous_revision_id uuid references public.pachanga_competition_sanction_revisions(id) on delete restrict,
  status text not null,
  sanction_outcome text not null,
  unit_type text,
  total_units integer,
  remaining_units integer,
  public_reason_category text,
  public_summary text not null default '',
  rule_article text,
  decision_factors jsonb not null default '{}'::jsonb,
  decision_reason_private text not null default '',
  operation_id uuid not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (status in (
    'no_sanction', 'provisional', 'under_review', 'active',
    'served', 'overturned', 'cancelled'
  )),
  check (sanction_outcome in (
    'NO_SANCTION', 'FIXED_SANCTION', 'PROVISIONAL_SANCTION',
    'COMMITTEE_REQUIRED', 'SANCTION_RANGE'
  )),
  check (unit_type is null or unit_type in (
    'MATCHES', 'ROUNDS', 'WEEKS', 'STAGE', 'COMPETITION_EXPULSION'
  )),
  check (total_units is null or total_units >= 0),
  check (remaining_units is null or remaining_units >= 0),
  check (public_reason_category is null or length(trim(public_reason_category)) between 1 and 80),
  check (length(public_summary) <= 500),
  check (rule_article is null or length(trim(rule_article)) between 1 and 160),
  check (jsonb_typeof(decision_factors) = 'object'),
  check (length(decision_reason_private) <= 4000),
  unique (sanction_id, version)
);

alter table public.pachanga_competition_sanctions
  add constraint pachanga_competition_sanctions_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_sanction_revisions(id) on delete restrict;

create table public.pachanga_competition_sanction_proposals (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  sanction_id uuid not null unique references public.pachanga_competition_sanctions(id) on delete restrict,
  source_event_id uuid not null references public.pachanga_competition_disciplinary_events(id) on delete restrict,
  status text not null default 'pending',
  minimum_units integer,
  maximum_units integer,
  unit_type text,
  rule_article text,
  proposal_reason text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('pending', 'under_review', 'decided', 'withdrawn')),
  check (minimum_units is null or minimum_units >= 0),
  check (maximum_units is null or maximum_units >= minimum_units),
  check (unit_type is null or unit_type in (
    'MATCHES', 'ROUNDS', 'WEEKS', 'STAGE', 'COMPETITION_EXPULSION'
  )),
  check (rule_article is null or length(trim(rule_article)) between 1 and 160),
  check (length(trim(proposal_reason)) between 3 and 2000),
  check (revision >= 1)
);

create table public.pachanga_competition_sanction_service_events (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  sanction_id uuid not null references public.pachanga_competition_sanctions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  event_type text not null,
  units integer not null,
  remaining_before integer not null,
  remaining_after integer not null,
  reverses_service_event_id uuid references public.pachanga_competition_sanction_service_events(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  operation_id uuid not null unique,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  check (event_type in ('SERVED', 'REVERSED')),
  check (units > 0 and remaining_before >= 0 and remaining_after >= 0),
  check (
    (event_type = 'SERVED' and reverses_service_event_id is null and remaining_after < remaining_before)
    or (event_type = 'REVERSED' and reverses_service_event_id is not null and remaining_after > remaining_before)
  )
);

create index pachanga_sanction_service_match_idx
  on public.pachanga_competition_sanction_service_events(
    sanction_id, canonical_match_id, event_type, server_sequence desc
  );
create unique index pachanga_sanction_service_reversal_idx
  on public.pachanga_competition_sanction_service_events(reverses_service_event_id)
  where event_type = 'REVERSED';

create table public.pachanga_competition_sanction_appeals (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  sanction_id uuid not null references public.pachanga_competition_sanctions(id) on delete restrict,
  appellant_user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'draft',
  deadline_at timestamptz not null,
  suspensive_effect boolean not null default false,
  current_revision_id uuid,
  creation_operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in (
    'draft', 'submitted', 'admissible', 'under_review', 'upheld',
    'modified', 'overturned', 'inadmissible', 'withdrawn'
  )),
  check (revision >= 1)
);

create unique index pachanga_sanction_appeal_open_idx
  on public.pachanga_competition_sanction_appeals(sanction_id, appellant_user_id)
  where status in ('draft', 'submitted', 'admissible', 'under_review');

create table public.pachanga_competition_sanction_appeal_revisions (
  id uuid primary key default gen_random_uuid(),
  appeal_id uuid not null references public.pachanga_competition_sanction_appeals(id) on delete restrict,
  version integer not null,
  previous_revision_id uuid references public.pachanga_competition_sanction_appeal_revisions(id) on delete restrict,
  status text not null,
  statement text not null,
  public_resolution text not null default '',
  resolution_reason_private text not null default '',
  operation_id uuid not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (status in (
    'draft', 'submitted', 'admissible', 'under_review', 'upheld',
    'modified', 'overturned', 'inadmissible', 'withdrawn'
  )),
  check (length(statement) between 3 and 4000),
  check (length(public_resolution) <= 1000),
  check (length(resolution_reason_private) <= 4000),
  unique (appeal_id, version)
);

alter table public.pachanga_competition_sanction_appeals
  add constraint pachanga_sanction_appeals_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_sanction_appeal_revisions(id) on delete restrict;

-- Materialized, reconstructible read state. It contains no evidence or deliberation.
create table public.pachanga_competition_discipline_player_states (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  cycle_id uuid not null references public.pachanga_competition_disciplinary_cycles(id) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  display_snapshot jsonb not null default '{}'::jsonb,
  card_summary jsonb not null default '{}'::jsonb,
  sanction_status text not null default 'AVAILABLE',
  remaining_units integer not null default 0,
  unit_type text,
  public_reason_category text,
  source_server_sequence bigint not null default 0,
  state_checksum text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (jsonb_typeof(display_snapshot) = 'object'),
  check (jsonb_typeof(card_summary) = 'object'),
  check (sanction_status in ('AVAILABLE', 'PROVISIONAL', 'SUSPENDED', 'UNDER_REVIEW')),
  check (remaining_units >= 0),
  check (unit_type is null or unit_type in (
    'MATCHES', 'ROUNDS', 'WEEKS', 'STAGE', 'COMPETITION_EXPULSION'
  )),
  check (public_reason_category is null or length(trim(public_reason_category)) between 1 and 80),
  check (source_server_sequence >= 0),
  check (length(state_checksum) = 64),
  check (revision >= 1),
  unique (cycle_id, player_profile_id)
);

create table private.pachanga_competition_discipline_evidence (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  subject_type text not null,
  subject_id uuid not null,
  evidence_refs jsonb not null default '[]'::jsonb,
  private_notes text not null default '',
  operation_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (subject_type in ('DISCIPLINARY_EVENT', 'SANCTION', 'APPEAL')),
  check (jsonb_typeof(evidence_refs) = 'array'),
  check (length(private_notes) <= 4000),
  unique (subject_type, subject_id, operation_id)
);

alter table public.pachanga_competition_match_sheets
  drop constraint if exists pachanga_competition_match_sheets_discipline_validation_status_check,
  add constraint pachanga_competition_match_sheets_discipline_validation_status_check
    check (discipline_validation_status in (
      'NOT_AVAILABLE', 'PENDING', 'VALIDATED', 'BLOCKED', 'STALE'
    ));

create index pachanga_disciplinary_events_match_idx
  on public.pachanga_competition_disciplinary_events(
    canonical_match_id, status, server_sequence desc, id desc
  );
create index pachanga_disciplinary_events_player_idx
  on public.pachanga_competition_disciplinary_events(
    competition_id, player_profile_id, cycle_id, status, server_sequence desc, id desc
  );
create index pachanga_disciplinary_event_revisions_event_idx
  on public.pachanga_competition_disciplinary_event_revisions(
    disciplinary_event_id, version desc, server_sequence desc, id desc
  );
create index pachanga_disciplinary_counters_player_idx
  on public.pachanga_competition_disciplinary_counters(
    competition_id, player_profile_id, cycle_id, server_sequence desc, id desc
  );
create index pachanga_sanctions_player_idx
  on public.pachanga_competition_sanctions(
    competition_id, player_profile_id, status, remaining_units desc, server_sequence desc, id desc
  ) where target_type = 'PLAYER';
create index pachanga_sanctions_source_event_idx
  on public.pachanga_competition_sanctions(source_event_id, server_sequence desc, id desc);
create unique index pachanga_sanctions_source_event_unique_idx
  on public.pachanga_competition_sanctions(source_event_id)
  where source_event_id is not null;
create index pachanga_sanction_service_fixture_idx
  on public.pachanga_competition_sanction_service_events(
    canonical_match_id, server_sequence desc, id desc
  );
create index pachanga_sanction_appeals_desk_idx
  on public.pachanga_competition_sanction_appeals(
    competition_id, status, deadline_at, server_sequence desc, id desc
  );
create index pachanga_discipline_player_states_competition_idx
  on public.pachanga_competition_discipline_player_states(
    competition_id, sanction_status, server_sequence desc, id desc
  );
create index pachanga_discipline_evidence_subject_idx
  on private.pachanga_competition_discipline_evidence(
    subject_type, subject_id, server_sequence desc, id desc
  );

comment on table public.pachanga_competition_discipline_rule_catalogs is
  'Immutable R5 card and sanction policy bound one-to-one to a CompetitionRuleRevision.';
comment on column public.pachanga_competitions.discipline_revision is
  'Monotonic R5 command-stream revision. Clients send this as expectedRevision for every discipline write.';
comment on table public.pachanga_competition_disciplinary_events is
  'Canonical disciplinary facts; corrections append revisions and never erase history.';
comment on table public.pachanga_competition_disciplinary_counters is
  'Materialized R5 counters reconstructed from active disciplinary event revisions.';
comment on table public.pachanga_competition_sanctions is
  'Competition-only sanctions. This domain must never update Rating, Conduct, Rewards or cosmetics.';
comment on table public.pachanga_competition_discipline_player_states is
  'Minimized participant/public projection with no evidence, reporter identity or deliberation.';
