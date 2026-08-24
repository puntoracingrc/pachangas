-- Pachangas IQ R4D: League operational exceptions and administrative decisions.
-- Product flags are OFF by default. This migration creates no competition data.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists league_operational_exceptions_foundation_enabled boolean not null default false,
  add column if not exists league_postponements_enabled boolean not null default false,
  add column if not exists league_rescheduling_enabled boolean not null default false,
  add column if not exists league_venue_changes_enabled boolean not null default false,
  add column if not exists league_late_arrival_enabled boolean not null default false,
  add column if not exists league_no_show_enabled boolean not null default false,
  add column if not exists league_match_suspensions_enabled boolean not null default false,
  add column if not exists league_administrative_decisions_enabled boolean not null default false,
  add column if not exists league_public_exception_status_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_r4d_flags_check,
  add constraint pachanga_comp_foundation_r4d_flags_check check (
    (not league_operational_exceptions_foundation_enabled
      or league_match_operations_foundation_enabled)
    and (not league_postponements_enabled
      or league_operational_exceptions_foundation_enabled)
    and (not league_rescheduling_enabled
      or league_operational_exceptions_foundation_enabled)
    and (not league_venue_changes_enabled
      or league_operational_exceptions_foundation_enabled)
    and (not league_late_arrival_enabled
      or league_operational_exceptions_foundation_enabled)
    and (not league_no_show_enabled or (
      league_operational_exceptions_foundation_enabled
      and league_late_arrival_enabled
      and league_administrative_decisions_enabled
    ))
    and (not league_match_suspensions_enabled
      or league_operational_exceptions_foundation_enabled)
    and (not league_administrative_decisions_enabled
      or league_operational_exceptions_foundation_enabled)
    and (not league_public_exception_status_enabled
      or league_operational_exceptions_foundation_enabled)
  );

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_grants_capability_check,
  add constraint pachanga_competition_entitlement_grants_capability_check check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline', 'competition_entries_manage',
    'competition_rosters_review', 'competition_categories_manage', 'competition_schedule',
    'competition_results', 'competition_standings', 'competition_operations'
  ));

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'competition_schedule_manager',
    'competition_result_manager', 'competition_standings_manager',
    'competition_operations_manager', 'viewer'
  ));

alter table public.pachanga_competition_match_contexts
  drop constraint if exists pachanga_competition_match_contexts_status_check,
  drop constraint if exists pachanga_competition_match_contexts_venue_status_check,
  add constraint pachanga_competition_match_contexts_status_check check (status in (
    'lab_bound', 'scheduled', 'ready', 'in_progress', 'played', 'result_pending',
    'official', 'postponed', 'suspended', 'abandoned', 'cancelled',
    'administrative_review', 'retired'
  )),
  add constraint pachanga_competition_match_contexts_venue_status_check
    check (venue_status in ('CONFIRMED', 'LABEL', 'TBD'));

drop index if exists public.pachanga_competition_context_active_match_idx;
create unique index pachanga_competition_context_active_match_idx
  on public.pachanga_competition_match_contexts(canonical_match_id)
  where status <> 'retired';

alter table public.pachanga_competition_official_result_decisions
  drop constraint if exists pachanga_competition_official_result_decisions_outcome_check,
  add constraint pachanga_competition_official_result_decisions_outcome_check check (outcome in (
    'MIRROR_SPORTING_RESULT', 'CORRECTED_EFFECTIVE_SCORE', 'ANNULLED',
    'NO_SHOW', 'FORFEIT', 'SUSPENDED_MATCH_DECISION'
  )),
  add column if not exists operational_source_type text,
  add column if not exists operational_source_id uuid;

alter table public.pachanga_competition_official_result_decisions
  drop constraint if exists pachanga_competition_official_result_decisions_operational_source_check,
  add constraint pachanga_competition_official_result_decisions_operational_source_check check (
    (outcome in ('NO_SHOW', 'FORFEIT')
      and operational_source_type = 'NO_SHOW_INCIDENT'
      and operational_source_id is not null)
    or (outcome = 'SUSPENDED_MATCH_DECISION'
      and operational_source_type = 'MATCH_SUSPENSION'
      and operational_source_id is not null)
    or (outcome not in ('NO_SHOW', 'FORFEIT', 'SUSPENDED_MATCH_DECISION')
      and operational_source_type is null
      and operational_source_id is null)
  );

create table public.pachanga_competition_fixture_changes (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  schedule_item_id uuid not null references public.pachanga_competition_schedule_items(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  change_type text not null,
  status text not null default 'active',
  source_type text not null,
  source_id uuid,
  supersedes_fixture_change_id uuid references public.pachanga_competition_fixture_changes(id) on delete restrict,
  current_revision_id uuid,
  original_scheduled_start timestamptz,
  original_scheduled_end timestamptz,
  original_timezone text,
  original_venue_id uuid,
  original_venue_label text,
  original_venue_status text not null,
  creation_operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (change_type in (
    'RESCHEDULE', 'TIME_CHANGE', 'VENUE_CHANGE', 'POSTPONEMENT',
    'CANCELLATION', 'RESUMPTION', 'REPLAY'
  )),
  check (status in ('active', 'superseded', 'annulled')),
  check (source_type in (
    'POSTPONEMENT_REQUEST', 'VENUE_CHANGE_REQUEST', 'VENUE_CONDITION_DECISION',
    'MATCH_SUSPENSION', 'ADMINISTRATIVE_DECISION', 'DIRECT_OPERATION'
  )),
  check (original_scheduled_end is null or (
    original_scheduled_start is not null and original_scheduled_end > original_scheduled_start
  )),
  check (original_timezone is null or length(trim(original_timezone)) between 3 and 80),
  check (original_venue_label is null or length(trim(original_venue_label)) between 1 and 160),
  check (original_venue_status in ('CONFIRMED', 'LABEL', 'TBD')),
  check (revision >= 1)
);

create unique index pachanga_fixture_change_active_context_idx
  on public.pachanga_competition_fixture_changes(competition_match_context_id)
  where status = 'active';

create table public.pachanga_competition_fixture_change_revisions (
  id uuid primary key default gen_random_uuid(),
  fixture_change_id uuid not null references public.pachanga_competition_fixture_changes(id) on delete restrict,
  version integer not null,
  previous_revision_id uuid references public.pachanga_competition_fixture_change_revisions(id) on delete restrict,
  change_type text not null,
  effective_scheduled_start timestamptz,
  effective_scheduled_end timestamptz,
  effective_timezone text,
  effective_venue_id uuid,
  effective_venue_label text,
  effective_venue_status text not null,
  effective_resource_key text,
  public_reason_code text not null,
  public_summary text not null default '',
  soft_constraint_impact jsonb not null default '{}'::jsonb,
  operation_id uuid not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (change_type in (
    'RESCHEDULE', 'TIME_CHANGE', 'VENUE_CHANGE', 'POSTPONEMENT',
    'CANCELLATION', 'RESUMPTION', 'REPLAY'
  )),
  check (effective_scheduled_end is null or (
    effective_scheduled_start is not null and effective_scheduled_end > effective_scheduled_start
  )),
  check (effective_timezone is null or length(trim(effective_timezone)) between 3 and 80),
  check (effective_venue_label is null or length(trim(effective_venue_label)) between 1 and 160),
  check (effective_venue_status in ('SAVED', 'LABEL', 'TBD')),
  check (effective_resource_key is null or length(trim(effective_resource_key)) between 1 and 160),
  check (length(trim(public_reason_code)) between 3 and 120),
  check (length(public_summary) <= 500),
  check (jsonb_typeof(soft_constraint_impact) = 'object'),
  unique (fixture_change_id, version)
);

alter table public.pachanga_competition_fixture_changes
  add constraint pachanga_fixture_changes_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_competition_fixture_change_revisions(id) on delete restrict;

create table public.pachanga_competition_postponement_requests (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  requesting_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  responding_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  status text not null default 'requested',
  proposed_start timestamptz,
  proposed_end timestamptz,
  proposed_timezone text,
  proposed_venue_id uuid,
  proposed_venue_label text,
  proposed_venue_status text not null default 'TBD',
  reason_code text not null,
  public_summary text not null default '',
  response_deadline timestamptz not null,
  deadline_policy text not null,
  organizer_approval_required boolean not null default true,
  team_response text not null default 'PENDING',
  organizer_response text not null default 'PENDING',
  current_response_id uuid,
  approved_fixture_change_id uuid references public.pachanga_competition_fixture_changes(id) on delete restrict,
  supersedes_request_id uuid references public.pachanga_competition_postponement_requests(id) on delete restrict,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  requested_by uuid not null references auth.users(id) on delete restrict,
  requested_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (requesting_entry_id <> responding_entry_id),
  check (status in (
    'requested', 'awaiting_response', 'approved', 'denied',
    'expired', 'withdrawn', 'superseded'
  )),
  check (proposed_end is null or (proposed_start is not null and proposed_end > proposed_start)),
  check (proposed_timezone is null or length(trim(proposed_timezone)) between 3 and 80),
  check (proposed_venue_label is null or length(trim(proposed_venue_label)) between 1 and 160),
  check (proposed_venue_status in ('SAVED', 'LABEL', 'TBD')),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_summary) <= 500),
  check (deadline_policy in ('EXPIRE', 'ESCALATE_TO_ORGANIZER', 'AUTO_DENY')),
  check (team_response in ('PENDING', 'ACCEPTED', 'REJECTED', 'COUNTERPROPOSED')),
  check (organizer_response in ('PENDING', 'APPROVED', 'DENIED', 'ESCALATED', 'NOT_REQUIRED')),
  check (resolved_at is null or status in ('approved', 'denied', 'expired', 'withdrawn', 'superseded')),
  check (revision >= 1)
);

create unique index pachanga_postponement_request_open_context_idx
  on public.pachanga_competition_postponement_requests(competition_match_context_id)
  where status in ('requested', 'awaiting_response');

create table public.pachanga_competition_postponement_responses (
  id uuid primary key default gen_random_uuid(),
  postponement_request_id uuid not null references public.pachanga_competition_postponement_requests(id) on delete restrict,
  responding_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  responder_kind text not null,
  response_kind text not null,
  proposed_start timestamptz,
  proposed_end timestamptz,
  proposed_timezone text,
  proposed_venue_id uuid,
  proposed_venue_label text,
  proposed_venue_status text,
  public_summary text not null default '',
  operation_id uuid not null unique,
  responded_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  responded_at timestamptz not null default clock_timestamp(),
  check (responder_kind in ('TEAM', 'ORGANIZER', 'SERVICE')),
  check (response_kind in ('ACCEPT', 'REJECT', 'COUNTERPROPOSE', 'APPROVE', 'DENY', 'ESCALATE')),
  check ((responder_kind = 'TEAM') = (responding_entry_id is not null)),
  check (proposed_end is null or (proposed_start is not null and proposed_end > proposed_start)),
  check (proposed_timezone is null or length(trim(proposed_timezone)) between 3 and 80),
  check (proposed_venue_label is null or length(trim(proposed_venue_label)) between 1 and 160),
  check (proposed_venue_status is null or proposed_venue_status in ('SAVED', 'LABEL', 'TBD')),
  check (length(public_summary) <= 500)
);

alter table public.pachanga_competition_postponement_requests
  add constraint pachanga_postponement_request_current_response_fk
  foreign key (current_response_id)
  references public.pachanga_competition_postponement_responses(id) on delete restrict;

create table public.pachanga_competition_venue_change_requests (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  requesting_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  requested_venue_id uuid,
  requested_venue_label text,
  requested_venue_status text not null,
  requested_resource_key text,
  reason_code text not null,
  public_summary text not null default '',
  status text not null default 'requested',
  current_decision_id uuid,
  approved_fixture_change_id uuid references public.pachanga_competition_fixture_changes(id) on delete restrict,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  requested_by uuid not null references auth.users(id) on delete restrict,
  requested_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (requested_venue_status in ('SAVED', 'LABEL', 'TBD')),
  check (requested_venue_label is null or length(trim(requested_venue_label)) between 1 and 160),
  check (requested_resource_key is null or length(trim(requested_resource_key)) between 1 and 160),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_summary) <= 500),
  check (status in ('requested', 'approved', 'denied', 'withdrawn', 'superseded')),
  check (revision >= 1)
);

create table public.pachanga_competition_venue_condition_decisions (
  id uuid primary key default gen_random_uuid(),
  venue_change_request_id uuid references public.pachanga_competition_venue_change_requests(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  reason_code text not null,
  outcome text not null,
  public_summary text not null default '',
  authority_role text not null,
  operation_id uuid not null unique,
  decided_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  decided_at timestamptz not null default clock_timestamp(),
  check (reason_code in (
    'WEATHER', 'PITCH_UNAVAILABLE', 'LIGHTING', 'FACILITY_CLOSED', 'SAFETY', 'OTHER'
  )),
  check (outcome in (
    'reported', 'inspection_required', 'play_confirmed',
    'venue_changed', 'postponed', 'cancelled'
  )),
  check (length(public_summary) <= 500),
  check (length(trim(authority_role)) between 3 and 80)
);

alter table public.pachanga_competition_venue_change_requests
  add constraint pachanga_venue_change_request_current_decision_fk
  foreign key (current_decision_id)
  references public.pachanga_competition_venue_condition_decisions(id) on delete restrict;

create table public.pachanga_competition_late_arrival_incidents (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  responsible_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  scheduled_start timestamptz not null,
  grace_deadline timestamptz not null,
  status text not null default 'reported',
  reported_at timestamptz not null default clock_timestamp(),
  arrival_at timestamptz,
  escalated_no_show_incident_id uuid,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  reported_by uuid not null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  check (grace_deadline >= scheduled_start),
  check (status in (
    'reported', 'arrived_within_policy', 'arrived_late',
    'escalated_to_no_show', 'dismissed'
  )),
  check (arrival_at is null or status in ('arrived_within_policy', 'arrived_late')),
  check (revision >= 1)
);

create unique index pachanga_late_arrival_open_context_entry_idx
  on public.pachanga_competition_late_arrival_incidents(
    competition_match_context_id, responsible_entry_id
  ) where status = 'reported';

create table public.pachanga_competition_no_show_incidents (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  responsible_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  late_arrival_incident_id uuid references public.pachanga_competition_late_arrival_incidents(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  status text not null default 'reported',
  scheduled_start timestamptz not null,
  grace_deadline timestamptz not null,
  reason_code text not null,
  public_summary text not null default '',
  official_result_decision_id uuid references public.pachanga_competition_official_result_decisions(id) on delete restrict,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  reported_by uuid not null references auth.users(id) on delete restrict,
  reported_at timestamptz not null default clock_timestamp(),
  reviewed_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (grace_deadline >= scheduled_start),
  check (status in ('reported', 'under_review', 'confirmed', 'rejected', 'resolved')),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_summary) <= 500),
  check (revision >= 1)
);

create unique index pachanga_no_show_open_context_entry_idx
  on public.pachanga_competition_no_show_incidents(
    competition_match_context_id, responsible_entry_id
  ) where status in ('reported', 'under_review', 'confirmed');

alter table public.pachanga_competition_late_arrival_incidents
  add constraint pachanga_late_arrival_no_show_fk
  foreign key (escalated_no_show_incident_id)
  references public.pachanga_competition_no_show_incidents(id) on delete restrict;

create table public.pachanga_competition_match_suspensions (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  reported_minute integer not null,
  sporting_score_home integer not null,
  sporting_score_away integer not null,
  sporting_result_revision_id uuid references public.pachanga_competition_sporting_result_revisions(id) on delete restrict,
  reason_code text not null,
  public_summary text not null default '',
  status text not null default 'reported',
  current_resumption_decision_id uuid,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  reported_by uuid not null references auth.users(id) on delete restrict,
  reported_at timestamptz not null default clock_timestamp(),
  confirmed_by uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz,
  resolved_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (reported_minute between 0 and 300),
  check (sporting_score_home >= 0 and sporting_score_away >= 0),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_summary) <= 500),
  check (status in (
    'reported', 'confirmed', 'resume_scheduled', 'resumed', 'replay_ordered',
    'administrative_resolution', 'abandoned', 'cancelled'
  )),
  check (revision >= 1)
);

create unique index pachanga_match_suspension_open_context_idx
  on public.pachanga_competition_match_suspensions(competition_match_context_id)
  where status in ('reported', 'confirmed', 'resume_scheduled', 'replay_ordered');

create table public.pachanga_competition_match_resumption_decisions (
  id uuid primary key default gen_random_uuid(),
  match_suspension_id uuid not null references public.pachanga_competition_match_suspensions(id) on delete restrict,
  decision_type text not null,
  resume_minute integer,
  initial_score_home integer,
  initial_score_away integer,
  effective_scheduled_start timestamptz,
  effective_scheduled_end timestamptz,
  effective_timezone text,
  effective_venue_id uuid,
  effective_venue_label text,
  effective_venue_status text,
  effective_resource_key text,
  reuse_canonical_match boolean not null default true,
  eligibility_policy_snapshot jsonb not null default '{}'::jsonb,
  public_summary text not null default '',
  status text not null default 'published',
  supersedes_decision_id uuid references public.pachanga_competition_match_resumption_decisions(id) on delete restrict,
  operation_id uuid not null unique,
  authority_role text not null,
  decided_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  decided_at timestamptz not null default clock_timestamp(),
  check (decision_type in ('RESUME', 'REPLAY', 'ADMINISTRATIVE_RESOLUTION', 'ABANDON', 'CANCEL')),
  check (resume_minute is null or resume_minute between 0 and 300),
  check (initial_score_home is null or initial_score_home >= 0),
  check (initial_score_away is null or initial_score_away >= 0),
  check ((initial_score_home is null) = (initial_score_away is null)),
  check (effective_scheduled_end is null or (
    effective_scheduled_start is not null and effective_scheduled_end > effective_scheduled_start
  )),
  check (effective_timezone is null or length(trim(effective_timezone)) between 3 and 80),
  check (effective_venue_label is null or length(trim(effective_venue_label)) between 1 and 160),
  check (effective_venue_status is null or effective_venue_status in ('SAVED', 'LABEL', 'TBD')),
  check (effective_resource_key is null or length(trim(effective_resource_key)) between 1 and 160),
  check (reuse_canonical_match),
  check (jsonb_typeof(eligibility_policy_snapshot) = 'object'),
  check (length(public_summary) <= 500),
  check (status in ('published', 'superseded', 'annulled')),
  check (length(trim(authority_role)) between 3 and 80)
);

alter table public.pachanga_competition_match_suspensions
  add constraint pachanga_match_suspension_current_resumption_fk
  foreign key (current_resumption_decision_id)
  references public.pachanga_competition_match_resumption_decisions(id) on delete restrict;

create table public.pachanga_competition_administrative_decisions (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  decision_type text not null,
  target_type text not null,
  target_id uuid not null,
  authority_assignment_id uuid references public.pachanga_competition_staff_assignments(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  reason_code text not null,
  public_summary text not null default '',
  previous_decision_id uuid references public.pachanga_competition_administrative_decisions(id) on delete restrict,
  status text not null default 'published',
  revision bigint not null default 1,
  operation_id uuid not null unique,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (decision_type in (
    'RESCHEDULE_MATCH', 'CHANGE_VENUE', 'CANCEL_MATCH', 'RESUME_FROM_MINUTE',
    'ORDER_REPLAY', 'SET_OFFICIAL_RESULT', 'ANNUL_OFFICIAL_RESULT'
  )),
  check (target_type in (
    'MATCH_CONTEXT', 'POSTPONEMENT_REQUEST', 'VENUE_CHANGE_REQUEST',
    'LATE_ARRIVAL_INCIDENT', 'NO_SHOW_INCIDENT', 'MATCH_SUSPENSION',
    'OFFICIAL_RESULT_DECISION'
  )),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_summary) <= 500),
  check (status in ('published', 'superseded', 'annulled')),
  check (revision >= 1)
);

create unique index pachanga_admin_decision_active_target_idx
  on public.pachanga_competition_administrative_decisions(
    target_type, target_id, decision_type
  ) where status = 'published';

create table public.pachanga_competition_administrative_effects (
  id uuid primary key default gen_random_uuid(),
  administrative_decision_id uuid not null references public.pachanga_competition_administrative_decisions(id) on delete restrict,
  effect_order integer not null,
  effect_type text not null,
  effect_payload jsonb not null default '{}'::jsonb,
  status text not null default 'applied',
  fixture_change_id uuid references public.pachanga_competition_fixture_changes(id) on delete restrict,
  official_result_decision_id uuid references public.pachanga_competition_official_result_decisions(id) on delete restrict,
  match_resumption_decision_id uuid references public.pachanga_competition_match_resumption_decisions(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  applied_at timestamptz not null default clock_timestamp(),
  check (effect_order >= 1),
  check (effect_type in (
    'RESCHEDULE_MATCH', 'CHANGE_VENUE', 'CANCEL_MATCH', 'RESUME_FROM_MINUTE',
    'ORDER_REPLAY', 'SET_OFFICIAL_RESULT', 'ANNUL_OFFICIAL_RESULT'
  )),
  check (jsonb_typeof(effect_payload) = 'object'),
  check (status in ('applied', 'reversed', 'failed')),
  unique (administrative_decision_id, effect_order)
);

create table private.pachanga_competition_operational_evidence (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  subject_type text not null,
  subject_id uuid not null,
  reason_text text not null default '',
  evidence_refs jsonb not null default '[]'::jsonb,
  actor_id uuid references auth.users(id) on delete set null,
  operation_id uuid not null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (subject_type in (
    'FIXTURE_CHANGE', 'POSTPONEMENT_REQUEST', 'POSTPONEMENT_RESPONSE',
    'VENUE_CHANGE_REQUEST', 'VENUE_CONDITION_DECISION', 'LATE_ARRIVAL_INCIDENT',
    'NO_SHOW_INCIDENT', 'MATCH_SUSPENSION', 'MATCH_RESUMPTION_DECISION',
    'ADMINISTRATIVE_DECISION'
  )),
  check (length(reason_text) <= 4000),
  check (jsonb_typeof(evidence_refs) = 'array'),
  unique (operation_id, subject_type, subject_id)
);

create index pachanga_fixture_changes_context_sequence_idx
  on public.pachanga_competition_fixture_changes(
    competition_match_context_id, server_sequence desc, id desc
  );
create index pachanga_fixture_change_revisions_current_idx
  on public.pachanga_competition_fixture_change_revisions(
    fixture_change_id, version desc, server_sequence desc, id desc
  );
create index pachanga_postponements_competition_status_idx
  on public.pachanga_competition_postponement_requests(
    competition_id, status, response_deadline, server_sequence desc, id desc
  );
create index pachanga_postponement_responses_request_idx
  on public.pachanga_competition_postponement_responses(
    postponement_request_id, server_sequence desc, id desc
  );
create index pachanga_venue_requests_competition_status_idx
  on public.pachanga_competition_venue_change_requests(
    competition_id, status, server_sequence desc, id desc
  );
create index pachanga_late_arrivals_competition_status_idx
  on public.pachanga_competition_late_arrival_incidents(
    competition_id, status, grace_deadline, server_sequence desc, id desc
  );
create index pachanga_no_shows_competition_status_idx
  on public.pachanga_competition_no_show_incidents(
    competition_id, status, grace_deadline, server_sequence desc, id desc
  );
create index pachanga_suspensions_competition_status_idx
  on public.pachanga_competition_match_suspensions(
    competition_id, status, server_sequence desc, id desc
  );
create index pachanga_admin_decisions_competition_status_idx
  on public.pachanga_competition_administrative_decisions(
    competition_id, status, server_sequence desc, id desc
  );
create index pachanga_operational_evidence_subject_idx
  on private.pachanga_competition_operational_evidence(
    subject_type, subject_id, server_sequence desc, id desc
  );

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_competition_fixture_changes',
    'pachanga_competition_fixture_change_revisions',
    'pachanga_competition_postponement_requests',
    'pachanga_competition_postponement_responses',
    'pachanga_competition_venue_change_requests',
    'pachanga_competition_venue_condition_decisions',
    'pachanga_competition_late_arrival_incidents',
    'pachanga_competition_no_show_incidents',
    'pachanga_competition_match_suspensions',
    'pachanga_competition_match_resumption_decisions',
    'pachanga_competition_administrative_decisions',
    'pachanga_competition_administrative_effects'
  ] loop
    execute format('alter table public.%I enable row level security', target_table);
    execute format('revoke all on table public.%I from anon, authenticated', target_table);
  end loop;
  alter table private.pachanga_competition_operational_evidence enable row level security;
  revoke all on table private.pachanga_competition_operational_evidence from anon, authenticated;
end;
$$;

comment on table public.pachanga_competition_fixture_changes is
  'R4D effective fixture overlay. The original R4B ScheduleItem remains immutable.';
comment on table public.pachanga_competition_postponement_requests is
  'R4D bilateral postponement workflow resolved from frozen RuleRevision policy.';
comment on table public.pachanga_competition_no_show_incidents is
  'R4D no-show evidence and review; never a Conduct, Rating or disciplinary authority.';
comment on table public.pachanga_competition_administrative_effects is
  'R4D allow-listed operational effects. Arbitrary SQL, billing and sanctions are forbidden.';
