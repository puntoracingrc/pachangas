-- Wave 8A: organizer access application authority and immutable revisions.
-- All product flags are born OFF. An application never grants access by itself.

set lock_timeout = '5s';
set statement_timeout = '5min';

create sequence if not exists private.pachanga_organizer_access_sequence;
revoke all on sequence private.pachanga_organizer_access_sequence from public, anon, authenticated;
grant usage, select on sequence private.pachanga_organizer_access_sequence to service_role;

create table private.pachanga_organizer_access_settings_v1 (
  singleton boolean primary key default true check (singleton),
  applications_enabled boolean not null default false,
  submission_enabled boolean not null default false,
  review_enabled boolean not null default false,
  partnership_approval_enabled boolean not null default false,
  onboarding_enabled boolean not null default false,
  first_competition_launcher_enabled boolean not null default false,
  demo_world_v30_enabled boolean not null default false,
  consent_version text not null default 'organizer-access-consent-v1',
  privacy_version text not null default 'organizer-access-privacy-v1',
  application_retention_days integer not null default 730,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_access_sequence'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (length(trim(consent_version)) between 3 and 80),
  check (length(trim(privacy_version)) between 3 and 80),
  check (application_retention_days between 30 and 3650),
  check (revision >= 1),
  check (not submission_enabled or applications_enabled),
  check (not review_enabled or applications_enabled),
  check (not partnership_approval_enabled or review_enabled),
  check (not onboarding_enabled or applications_enabled),
  check (not first_competition_launcher_enabled or onboarding_enabled),
  check (not demo_world_v30_enabled or applications_enabled)
);

insert into private.pachanga_organizer_access_settings_v1(singleton)
values (true)
on conflict (singleton) do nothing;

create table private.pachanga_organizer_access_applications_v1 (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  requested_plan_code text not null references public.pachanga_organizer_plan_catalog(plan_code) on delete restrict,
  requested_access_mode text not null,
  status text not null default 'draft',
  intent text not null default 'BOTH',
  expected_competition_type text not null default 'BOTH',
  expected_team_count integer,
  target_start_date date,
  municipality text not null default '',
  area text not null default '',
  field_relationship text not null default '',
  summary text not null default '',
  current_revision_id uuid,
  reconsideration_of_id uuid references private.pachanga_organizer_access_applications_v1(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  submitted_by uuid references auth.users(id) on delete set null,
  assigned_reviewer uuid references auth.users(id) on delete set null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_organizer_access_sequence'),
  submitted_at timestamptz,
  terminal_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (requested_access_mode in ('PARTNERSHIP_REVIEW', 'PAID_PLAN_INTEREST')),
  check (status in (
    'draft', 'submitted', 'under_review', 'needs_information',
    'approved', 'approved_interest', 'rejected', 'withdrawn', 'expired'
  )),
  check (intent in ('LEAGUE', 'TOURNAMENT', 'BOTH')),
  check (expected_competition_type in ('LEAGUE', 'TOURNAMENT', 'BOTH')),
  check (expected_team_count is null or expected_team_count between 2 and 10000),
  check (length(municipality) <= 120),
  check (length(area) <= 160),
  check (length(field_relationship) <= 500),
  check (length(summary) <= 2000),
  check (revision >= 1),
  check ((status = 'draft' and submitted_at is null) or status <> 'draft'),
  check ((status in ('approved', 'approved_interest', 'rejected', 'withdrawn', 'expired') and terminal_at is not null)
    or status not in ('approved', 'approved_interest', 'rejected', 'withdrawn', 'expired'))
);

create table private.pachanga_organizer_access_application_revisions_v1 (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references private.pachanga_organizer_access_applications_v1(id) on delete restrict,
  version integer not null,
  requested_plan_code text not null references public.pachanga_organizer_plan_catalog(plan_code) on delete restrict,
  requested_access_mode text not null,
  intent text not null,
  expected_competition_type text not null,
  expected_team_count integer,
  target_start_date date,
  municipality text not null default '',
  area text not null default '',
  field_relationship text not null default '',
  summary text not null default '',
  consent_version text,
  privacy_version text,
  consented_by uuid references auth.users(id) on delete set null,
  consented_at timestamptz,
  content_fingerprint text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique default nextval('private.pachanga_organizer_access_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  unique (application_id, version),
  check (version >= 1),
  check (requested_access_mode in ('PARTNERSHIP_REVIEW', 'PAID_PLAN_INTEREST')),
  check (intent in ('LEAGUE', 'TOURNAMENT', 'BOTH')),
  check (expected_competition_type in ('LEAGUE', 'TOURNAMENT', 'BOTH')),
  check (expected_team_count is null or expected_team_count between 2 and 10000),
  check (length(municipality) <= 120),
  check (length(area) <= 160),
  check (length(field_relationship) <= 500),
  check (length(summary) <= 2000),
  check (length(content_fingerprint) = 64),
  check (
    (consent_version is null and privacy_version is null and consented_by is null and consented_at is null)
    or (consent_version is not null and privacy_version is not null and consented_by is not null and consented_at is not null)
  )
);

alter table private.pachanga_organizer_access_applications_v1
  add constraint pachanga_organizer_access_current_revision_fkey
  foreign key (current_revision_id)
  references private.pachanga_organizer_access_application_revisions_v1(id)
  on delete restrict;

create table private.pachanga_organizer_access_operation_receipts_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  request_hash text not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  client_metadata jsonb not null default '{}'::jsonb,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'platform', 'service_authority')),
  check (length(request_hash) = 64),
  check (confirmed_revision >= 0),
  check (jsonb_typeof(client_metadata) = 'object'),
  check (jsonb_typeof(response) = 'object')
);

create table private.pachanga_organizer_access_events_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null,
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  application_id uuid references private.pachanga_organizer_access_applications_v1(id) on delete restrict,
  organizer_kind text,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  aggregate_revision bigint not null,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null unique,
  confirmed_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'platform', 'service_authority')),
  check (organizer_kind is null or organizer_kind in ('TEAM', 'CLUB')),
  check (
    organizer_kind is null
    or (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (aggregate_revision >= 0),
  check (length(trim(reason_code)) between 3 and 120),
  check (jsonb_typeof(event_payload) = 'object')
);

create table private.pachanga_organizer_access_rate_limit_overrides_v1 (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  action_pattern text not null,
  valid_until timestamptz not null,
  reason text not null,
  granted_by uuid not null references auth.users(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_organizer_access_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (action_pattern ~ '^[a-z][a-z0-9_.]{2,79}$'),
  check (valid_until > created_at),
  check (length(trim(reason)) between 3 and 1200),
  check (revision >= 1)
);

create unique index pachanga_organizer_access_active_application_idx
  on private.pachanga_organizer_access_applications_v1(
    organizer_kind,
    coalesce(organizer_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(organizer_club_id, '00000000-0000-0000-0000-000000000000'::uuid),
    requested_plan_code
  )
  where status in ('draft', 'submitted', 'under_review', 'needs_information');

create index pachanga_organizer_access_application_status_idx
  on private.pachanga_organizer_access_applications_v1(status, server_sequence desc, id);
create index pachanga_organizer_access_application_team_idx
  on private.pachanga_organizer_access_applications_v1(organizer_group_id, server_sequence desc, id)
  where organizer_kind = 'TEAM';
create index pachanga_organizer_access_application_club_idx
  on private.pachanga_organizer_access_applications_v1(organizer_club_id, server_sequence desc, id)
  where organizer_kind = 'CLUB';
create index pachanga_organizer_access_application_reviewer_idx
  on private.pachanga_organizer_access_applications_v1(assigned_reviewer, status, server_sequence desc, id)
  where assigned_reviewer is not null;
create index pachanga_organizer_access_revision_application_idx
  on private.pachanga_organizer_access_application_revisions_v1(application_id, version desc, id);
create index pachanga_organizer_access_receipt_actor_idx
  on private.pachanga_organizer_access_operation_receipts_v1(actor_id, created_at desc, id)
  where actor_id is not null;
create index pachanga_organizer_access_event_application_idx
  on private.pachanga_organizer_access_events_v1(application_id, server_sequence desc, id)
  where application_id is not null;
create index pachanga_organizer_access_event_rate_idx
  on private.pachanga_organizer_access_events_v1(actor_id, action, confirmed_at desc, id)
  where actor_id is not null;

revoke all on table private.pachanga_organizer_access_settings_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_access_applications_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_access_application_revisions_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_access_operation_receipts_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_access_events_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_access_rate_limit_overrides_v1 from public, anon, authenticated;

grant all on table private.pachanga_organizer_access_settings_v1 to service_role;
grant all on table private.pachanga_organizer_access_applications_v1 to service_role;
grant all on table private.pachanga_organizer_access_application_revisions_v1 to service_role;
grant all on table private.pachanga_organizer_access_operation_receipts_v1 to service_role;
grant all on table private.pachanga_organizer_access_events_v1 to service_role;
grant all on table private.pachanga_organizer_access_rate_limit_overrides_v1 to service_role;

comment on table private.pachanga_organizer_access_applications_v1 is
  'Wave 8A organizer-owned application aggregate. It is never an entitlement.';
comment on table private.pachanga_organizer_access_application_revisions_v1 is
  'Immutable application content and consent evidence, ordered by server sequence.';
