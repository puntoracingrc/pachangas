-- Pachangas IQ Wave 7A: public Competition publication and consent authority.
-- All product flags are additive and born OFF.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists public_competition_foundation_enabled boolean not null default false,
  add column if not exists public_competition_publication_enabled boolean not null default false,
  add column if not exists public_competition_discovery_enabled boolean not null default false,
  add column if not exists public_competition_registration_requests_enabled boolean not null default false,
  add column if not exists public_competition_waitlist_enabled boolean not null default false,
  add column if not exists public_competition_calendar_enabled boolean not null default false,
  add column if not exists public_competition_results_enabled boolean not null default false,
  add column if not exists public_competition_standings_enabled boolean not null default false,
  add column if not exists public_competition_bracket_enabled boolean not null default false,
  add column if not exists public_competition_exception_status_enabled boolean not null default false,
  add column if not exists public_competition_referee_display_enabled boolean not null default false,
  add column if not exists public_competition_discipline_enabled boolean not null default false,
  add column if not exists public_competition_auto_accept_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_competition_foundation_settings_public_competition_flags_check,
  add constraint pachanga_competition_foundation_settings_public_competition_flags_check check (
    (not public_competition_publication_enabled or public_competition_foundation_enabled)
    and (not public_competition_discovery_enabled or public_competition_publication_enabled)
    and (not public_competition_registration_requests_enabled or public_competition_publication_enabled)
    and (not public_competition_waitlist_enabled or public_competition_registration_requests_enabled)
    and (not public_competition_calendar_enabled or public_competition_publication_enabled)
    and (not public_competition_results_enabled or public_competition_calendar_enabled)
    and (not public_competition_standings_enabled or public_competition_results_enabled)
    and (not public_competition_bracket_enabled or public_competition_results_enabled)
    and (not public_competition_exception_status_enabled or public_competition_calendar_enabled)
    and (not public_competition_referee_display_enabled or public_competition_calendar_enabled)
    and not public_competition_discipline_enabled
    and not public_competition_auto_accept_enabled
  );

alter table public.pachanga_competitions
  drop constraint if exists pachanga_competitions_visibility_check,
  add constraint pachanga_competitions_visibility_check
    check (visibility in ('private', 'internal', 'unlisted', 'public'));

alter table public.pachanga_competition_editions
  drop constraint if exists pachanga_competition_editions_registration_mode_check,
  add constraint pachanga_competition_editions_registration_mode_check check (
    registration_mode in (
      'PUBLIC_APPROVAL', 'REQUEST_APPROVAL', 'INVITE_ONLY', 'CLOSED',
      'PRIVATE_CODE', 'AUTO_ACCEPT'
    )
  );

create table public.pachanga_competition_publications (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null unique
    references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid references public.pachanga_competition_categories(id) on delete restrict,
  slug text not null unique,
  visibility text not null default 'private',
  lifecycle_status text not null default 'draft',
  public_profile jsonb not null default '{}'::jsonb,
  public_sections jsonb not null default jsonb_build_object(
    'teams', true,
    'calendar', true,
    'results', true,
    'standings', true,
    'bracket', true,
    'referees', false,
    'venueDetail', false,
    'discipline', false
  ),
  content_fingerprint text not null,
  current_consent_id uuid,
  organizer_verified boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null unique
    default nextval('private.pachanga_competition_sequence'),
  submitted_at timestamptz,
  approved_at timestamptz,
  published_at timestamptz,
  suspended_at timestamptz,
  archived_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 3 and 80),
  check (visibility in ('private', 'unlisted', 'public')),
  check (lifecycle_status in (
    'draft', 'pending_review', 'approved', 'published', 'rejected',
    'changes_requested', 'suspended', 'archived'
  )),
  check (jsonb_typeof(public_profile) = 'object'),
  check (jsonb_typeof(public_sections) = 'object'),
  check (length(content_fingerprint) = 64),
  check (revision >= 1),
  check (not (public_sections ->> 'discipline')::boolean),
  check (lifecycle_status <> 'published' or (
    visibility in ('public', 'unlisted')
    and edition_id is not null
    and category_id is not null
    and current_consent_id is not null
    and published_at is not null
  ))
);

create table public.pachanga_competition_publication_consents (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null
    references public.pachanga_competition_publications(id) on delete restrict,
  competition_id uuid not null
    references public.pachanga_competitions(id) on delete restrict,
  consent_version text not null,
  consent_number integer not null,
  content_fingerprint text not null,
  purpose text not null,
  statements jsonb not null,
  public_sections_snapshot jsonb not null,
  status text not null default 'current',
  actor_id uuid references auth.users(id) on delete set null,
  operation_id uuid not null unique,
  revision bigint not null default 1,
  server_sequence bigint not null unique
    default nextval('private.pachanga_competition_sequence'),
  confirmed_at timestamptz not null default clock_timestamp(),
  restored_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  check (consent_version = 'public-competition-consent.v1'),
  check (consent_number >= 1),
  check (length(content_fingerprint) = 64),
  check (length(trim(purpose)) between 3 and 500),
  check (jsonb_typeof(statements) = 'object'),
  check (jsonb_typeof(public_sections_snapshot) = 'object'),
  check (status in ('current', 'obsolete', 'withdrawn')),
  check (revision >= 1),
  unique (publication_id, consent_number)
);

alter table public.pachanga_competition_publications
  add constraint pachanga_competition_publications_current_consent_fkey
  foreign key (current_consent_id)
  references public.pachanga_competition_publication_consents(id) on delete restrict;

create unique index pachanga_competition_publication_current_consent_idx
  on public.pachanga_competition_publication_consents(publication_id)
  where status = 'current';

create table public.pachanga_competition_publication_reviews (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null
    references public.pachanga_competition_publications(id) on delete restrict,
  competition_id uuid not null
    references public.pachanga_competitions(id) on delete restrict,
  review_action text not null,
  from_status text not null,
  to_status text not null,
  public_reason text not null default '',
  private_reason text not null default '',
  actor_id uuid references auth.users(id) on delete set null,
  operation_id uuid not null unique,
  server_sequence bigint not null unique
    default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (review_action in (
    'SUBMIT', 'WITHDRAW', 'APPROVE', 'REJECT', 'REQUEST_CHANGES',
    'PUBLISH', 'UNPUBLISH', 'SUSPEND', 'RESTORE', 'ARCHIVE',
    'VERIFY_ORGANIZER'
  )),
  check (length(public_reason) <= 500),
  check (length(private_reason) <= 1200)
);

create index pachanga_competition_publication_review_queue_idx
  on public.pachanga_competition_publications(
    lifecycle_status, server_sequence desc, id desc
  );
create index pachanga_competition_publication_review_history_idx
  on public.pachanga_competition_publication_reviews(
    publication_id, server_sequence desc, id desc
  );

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_competition_publications',
    'pachanga_competition_publication_consents',
    'pachanga_competition_publication_reviews'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

comment on table public.pachanga_competition_publications is
  'Wave 7A moderation lifecycle. It projects a canonical Competition; it is not another sports domain.';
comment on table public.pachanga_competition_publication_consents is
  'Versioned organizer consent bound to the exact public content fingerprint.';
comment on table public.pachanga_competition_publication_reviews is
  'Append-only publication moderation audit. Private reasons are never returned by public RPCs.';
