-- Wave 8B: human review and owner appeal aggregates.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table private.pachanga_team_operational_reviews_v1 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  status text not null default 'OPEN',
  reason_code text not null,
  safe_message text not null default '',
  private_note text not null default '',
  evidence jsonb not null default '{}'::jsonb,
  provisional_restriction boolean not null default false,
  opened_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz,
  opened_by uuid references auth.users(id) on delete set null,
  assigned_reviewer uuid references auth.users(id) on delete set null,
  closed_by uuid references auth.users(id) on delete set null,
  close_outcome text,
  operation_id uuid not null unique,
  source_revision bigint not null,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_team_operational_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('OPEN', 'NEEDS_INFORMATION', 'CLOSED_NO_ACTION', 'CLOSED_ACTION_TAKEN')),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(safe_message) <= 500),
  check (length(private_note) <= 4000),
  check (jsonb_typeof(evidence) = 'object'),
  check (source_revision >= 1),
  check (revision >= 1),
  check (
    (status in ('OPEN', 'NEEDS_INFORMATION') and closed_at is null and closed_by is null and close_outcome is null)
    or (status in ('CLOSED_NO_ACTION', 'CLOSED_ACTION_TAKEN') and closed_at is not null and close_outcome is not null)
  )
);

create unique index pachanga_team_operational_open_review_idx
  on private.pachanga_team_operational_reviews_v1(group_id)
  where status in ('OPEN', 'NEEDS_INFORMATION');

create table private.pachanga_team_operational_review_revisions_v1 (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references private.pachanga_team_operational_reviews_v1(id) on delete restrict,
  version integer not null,
  status text not null,
  reason_code text not null,
  safe_message text not null default '',
  private_note text not null default '',
  evidence jsonb not null default '{}'::jsonb,
  assigned_reviewer uuid references auth.users(id) on delete set null,
  action text not null,
  actor_id uuid references auth.users(id) on delete set null,
  operation_id uuid not null,
  server_sequence bigint not null unique default nextval('private.pachanga_team_operational_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  unique (review_id, version),
  unique (operation_id, review_id),
  check (version >= 1),
  check (status in ('OPEN', 'NEEDS_INFORMATION', 'CLOSED_NO_ACTION', 'CLOSED_ACTION_TAKEN')),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(safe_message) <= 500),
  check (length(private_note) <= 4000),
  check (jsonb_typeof(evidence) = 'object')
);

create table private.pachanga_team_operational_appeals_v1 (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  status text not null default 'DRAFT',
  subject_revision bigint not null,
  subject_restriction_id uuid references private.pachanga_team_operational_restrictions_v1(id) on delete restrict,
  owner_message text not null default '',
  safe_resolution_message text not null default '',
  private_resolution_note text not null default '',
  requested_outcome text not null default 'REVIEW',
  deadline_at timestamptz,
  submitted_at timestamptz,
  resolved_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  assigned_reviewer uuid references auth.users(id) on delete set null,
  resolved_by uuid references auth.users(id) on delete set null,
  resolution text,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_team_operational_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'UPHELD', 'MODIFIED', 'OVERTURNED', 'WITHDRAWN', 'INADMISSIBLE')),
  check (subject_revision >= 1),
  check (length(owner_message) <= 3000),
  check (length(safe_resolution_message) <= 1000),
  check (length(private_resolution_note) <= 4000),
  check (requested_outcome in ('REVIEW', 'MODIFY', 'LIFT')),
  check (revision >= 1),
  check (
    (status = 'DRAFT' and submitted_at is null and resolved_at is null)
    or (status in ('SUBMITTED', 'UNDER_REVIEW') and submitted_at is not null and resolved_at is null)
    or (status in ('UPHELD', 'MODIFIED', 'OVERTURNED', 'WITHDRAWN', 'INADMISSIBLE') and resolved_at is not null)
  )
);

create unique index pachanga_team_operational_open_appeal_idx
  on private.pachanga_team_operational_appeals_v1(group_id)
  where status in ('DRAFT', 'SUBMITTED', 'UNDER_REVIEW');

create table private.pachanga_team_operational_appeal_messages_v1 (
  id uuid primary key default gen_random_uuid(),
  appeal_id uuid not null references private.pachanga_team_operational_appeals_v1(id) on delete restrict,
  visibility text not null,
  author_kind text not null,
  body text not null,
  authored_by uuid references auth.users(id) on delete set null,
  operation_id uuid not null,
  server_sequence bigint not null unique default nextval('private.pachanga_team_operational_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, appeal_id, visibility),
  check (visibility in ('OWNER_SAFE', 'PLATFORM_PRIVATE')),
  check (author_kind in ('OWNER', 'PLATFORM', 'SERVICE_AUTHORITY')),
  check (length(trim(body)) between 1 and 3000)
);

revoke all on table private.pachanga_team_operational_reviews_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_review_revisions_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_appeals_v1 from public, anon, authenticated;
revoke all on table private.pachanga_team_operational_appeal_messages_v1 from public, anon, authenticated;

grant all on table private.pachanga_team_operational_reviews_v1 to service_role;
grant all on table private.pachanga_team_operational_review_revisions_v1 to service_role;
grant all on table private.pachanga_team_operational_appeals_v1 to service_role;
grant all on table private.pachanga_team_operational_appeal_messages_v1 to service_role;

comment on table private.pachanga_team_operational_reviews_v1 is
  'Human review queue. A review never blocks Team activity unless a separate explicit restriction exists.';
comment on table private.pachanga_team_operational_appeals_v1 is
  'Owner appeal aggregate. Submission does not suspend an operational decision.';
