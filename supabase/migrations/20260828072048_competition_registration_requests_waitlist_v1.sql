-- Pachangas IQ Wave 7A: registration request and explicit waitlist authority.
-- A request is not a CompetitionEntry. Entry is created atomically only when
-- the organizer accepts the request.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.pachanga_competition_registration_requests (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null
    references public.pachanga_competition_publications(id) on delete restrict,
  competition_id uuid not null
    references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null
    references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null
    references public.pachanga_competition_categories(id) on delete restrict,
  team_id uuid not null references public.pachanga_groups(id) on delete restrict,
  requested_by uuid references auth.users(id) on delete set null,
  status text not null default 'submitted',
  message text not null default '',
  team_snapshot jsonb not null,
  capacity_snapshot jsonb not null,
  rule_revision_id uuid not null
    references public.pachanga_competition_rule_revisions(id) on delete restrict,
  entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  waitlist_position bigint,
  reason_code text not null default 'registration.requested',
  public_reason text not null default '',
  private_reason text not null default '',
  created_operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null unique
    default nextval('private.pachanga_competition_sequence'),
  submitted_at timestamptz not null default clock_timestamp(),
  reviewed_at timestamptz,
  accepted_at timestamptz,
  rejected_at timestamptz,
  waitlisted_at timestamptz,
  withdrawn_at timestamptz,
  expired_at timestamptz,
  cancelled_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (status in (
    'draft', 'submitted', 'under_review', 'accepted', 'rejected',
    'waitlisted', 'withdrawn', 'expired', 'cancelled'
  )),
  check (length(message) <= 1000),
  check (jsonb_typeof(team_snapshot) = 'object'),
  check (jsonb_typeof(capacity_snapshot) = 'object'),
  check (length(trim(reason_code)) between 3 and 120),
  check (length(public_reason) <= 500),
  check (length(private_reason) <= 1200),
  check (revision >= 1),
  check ((status = 'waitlisted') = (waitlist_position is not null)),
  check (waitlist_position is null or waitlist_position > 0),
  check ((status = 'accepted') = (entry_id is not null))
);

create unique index pachanga_competition_registration_request_current_team_idx
  on public.pachanga_competition_registration_requests(
    edition_id, category_id, team_id
  )
  where status in ('draft', 'submitted', 'under_review', 'waitlisted', 'accepted');

create unique index pachanga_competition_registration_waitlist_position_idx
  on public.pachanga_competition_registration_requests(
    edition_id, category_id, waitlist_position
  )
  where status = 'waitlisted';

create index pachanga_competition_registration_organizer_queue_idx
  on public.pachanga_competition_registration_requests(
    competition_id, status, server_sequence, id
  );

create index pachanga_competition_registration_team_history_idx
  on public.pachanga_competition_registration_requests(
    team_id, server_sequence desc, id desc
  );

create table public.pachanga_competition_registration_request_revisions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null
    references public.pachanga_competition_registration_requests(id) on delete restrict,
  request_revision bigint not null,
  status text not null,
  message_snapshot text not null default '',
  waitlist_position bigint,
  reason_code text not null,
  public_reason text not null default '',
  private_reason text not null default '',
  actor_id uuid references auth.users(id) on delete set null,
  operation_id uuid not null,
  server_sequence bigint not null unique
    default nextval('private.pachanga_competition_sequence'),
  effective_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (request_revision >= 1),
  check (status in (
    'draft', 'submitted', 'under_review', 'accepted', 'rejected',
    'waitlisted', 'withdrawn', 'expired', 'cancelled'
  )),
  check (length(message_snapshot) <= 1000),
  check (waitlist_position is null or waitlist_position > 0),
  check (length(public_reason) <= 500),
  check (length(private_reason) <= 1200),
  unique (request_id, request_revision),
  unique (operation_id, request_id)
);

create index pachanga_competition_registration_revision_history_idx
  on public.pachanga_competition_registration_request_revisions(
    request_id, request_revision desc, server_sequence desc, id desc
  );

-- Competition reports are a product-moderation channel. They deliberately do
-- not reuse player Conduct and cannot alter Rating, GRL, facets or sanctions.
create table private.pachanga_competition_reports (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  publication_id uuid not null
    references public.pachanga_competition_publications(id) on delete restrict,
  competition_id uuid not null
    references public.pachanga_competitions(id) on delete restrict,
  reporter_user_id uuid references auth.users(id) on delete set null,
  category text not null,
  summary text not null,
  status text not null default 'submitted',
  resolution_code text not null default '',
  public_resolution text not null default '',
  private_resolution text not null default '',
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null unique
    default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (category in ('MISLEADING', 'IMPERSONATION', 'PRIVACY', 'ABUSE', 'OTHER')),
  check (length(trim(summary)) between 10 and 1000),
  check (status in ('submitted', 'under_review', 'resolved', 'dismissed')),
  check (length(resolution_code) <= 120),
  check (length(public_resolution) <= 500),
  check (length(private_resolution) <= 1200),
  check (revision >= 1)
);

create index pachanga_competition_reports_queue_idx
  on private.pachanga_competition_reports(status, server_sequence, id);
create index pachanga_competition_reports_competition_idx
  on private.pachanga_competition_reports(competition_id, server_sequence desc, id desc);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_competition_registration_requests',
    'pachanga_competition_registration_request_revisions'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

alter table private.pachanga_competition_reports enable row level security;
revoke all on table private.pachanga_competition_reports from public, anon, authenticated;
grant all on table private.pachanga_competition_reports to service_role;

comment on table public.pachanga_competition_registration_requests is
  'Wave 7A request authority. No Entry exists until an accepted transition commits atomically.';
comment on table private.pachanga_competition_reports is
  'Competition moderation reports; isolated from player Conduct and all rating systems.';
