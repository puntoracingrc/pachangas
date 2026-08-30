-- Pachangas IQ Wave 9A: reservation requests, temporary holds and canonical reservations.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table if not exists public.pachanga_venue_reservation_requests (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid references public.pachanga_venue_pitches(id) on delete restrict,
  requester_kind text not null,
  requester_user_id uuid not null references auth.users(id) on delete restrict,
  requester_team_id uuid references public.pachanga_groups(id) on delete restrict,
  requester_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  competition_id uuid references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  rule_revision_id uuid references public.pachanga_competition_rule_revisions(id) on delete restrict,
  purpose text not null,
  modality text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  requested_local_start timestamp without time zone not null,
  requested_local_end timestamp without time zone not null,
  timezone text not null,
  resolved_offset_minutes integer not null,
  criteria jsonb not null default '{}'::jsonb,
  alternatives jsonb not null default '[]'::jsonb,
  message text not null default '',
  current_proposal jsonb not null default '{}'::jsonb,
  status text not null default 'DRAFT',
  current_hold_id uuid,
  current_reservation_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  submitted_at timestamptz,
  resolved_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (requester_kind in ('TEAM', 'COMPETITION', 'CLUB_COMPETITION_STAFF')),
  check (
    (requester_kind = 'TEAM' and requester_team_id is not null)
    or (requester_kind = 'COMPETITION' and competition_id is not null)
    or (requester_kind = 'CLUB_COMPETITION_STAFF' and requester_club_id is not null and competition_id is not null)
  ),
  check (purpose in ('STANDALONE_MATCH', 'COMPETITION_MATCH')),
  check (modality in ('F5', 'F7', 'F11', 'FUTSAL')),
  check (ends_at > starts_at and ends_at <= starts_at + interval '12 hours'),
  check (requested_local_end > requested_local_start),
  check (length(timezone) between 1 and 80),
  check (resolved_offset_minutes between -840 and 840),
  check (jsonb_typeof(criteria) = 'object'),
  check (jsonb_typeof(alternatives) = 'array'),
  check (jsonb_array_length(alternatives) <= 10),
  check (length(message) <= 2000),
  check (jsonb_typeof(current_proposal) = 'object'),
  check (status in (
    'DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'HELD', 'COUNTER_PROPOSED',
    'ACCEPTED', 'CONFIRMED', 'REJECTED', 'WITHDRAWN', 'EXPIRED', 'CANCELLED'
  )),
  check (revision >= 1)
);

create index if not exists pachanga_venue_requests_venue_idx
  on public.pachanga_venue_reservation_requests(
    venue_id, status, starts_at, server_sequence desc, id
  );
create index if not exists pachanga_venue_requests_pitch_idx
  on public.pachanga_venue_reservation_requests(
    pitch_id, status, starts_at, ends_at, server_sequence, id
  );
create index if not exists pachanga_venue_requests_requester_idx
  on public.pachanga_venue_reservation_requests(
    requester_user_id, status, server_sequence desc, id
  );
create index if not exists pachanga_venue_requests_team_idx
  on public.pachanga_venue_reservation_requests(
    requester_team_id, status, server_sequence desc, id
  ) where requester_team_id is not null;
create index if not exists pachanga_venue_requests_competition_idx
  on public.pachanga_venue_reservation_requests(
    competition_id, status, server_sequence desc, id
  ) where competition_id is not null;

create table if not exists private.pachanga_venue_reservation_request_revisions (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.pachanga_venue_reservation_requests(id) on delete restrict,
  revision bigint not null check (revision >= 1),
  action text not null,
  status text not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  unique (request_id, revision),
  unique (operation_id, request_id)
);

create table if not exists public.pachanga_venue_pitch_claims (
  id uuid primary key default gen_random_uuid(),
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  conflict_scope_id uuid not null,
  source_kind text not null,
  source_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  occupied_range tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  status text not null default 'ACTIVE',
  expires_at timestamptz,
  operation_id uuid not null,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  released_at timestamptz,
  check (source_kind in ('HOLD', 'RESERVATION')),
  check (ends_at > starts_at),
  check (status in ('ACTIVE', 'RELEASED', 'EXPIRED', 'CONSUMED')),
  check ((source_kind = 'HOLD' and expires_at is not null) or source_kind = 'RESERVATION'),
  check ((status = 'ACTIVE' and released_at is null) or status <> 'ACTIVE'),
  unique (source_kind, source_id)
);

alter table public.pachanga_venue_pitch_claims
  drop constraint if exists pachanga_venue_pitch_claims_no_overlap_v1;
alter table public.pachanga_venue_pitch_claims
  add constraint pachanga_venue_pitch_claims_no_overlap_v1
  exclude using gist (
    conflict_scope_id with =,
    occupied_range with &&
  ) where (status = 'ACTIVE');

create index if not exists pachanga_venue_pitch_claims_pitch_idx
  on public.pachanga_venue_pitch_claims(
    pitch_id, status, starts_at, ends_at, server_sequence, id
  );
create index if not exists pachanga_venue_pitch_claims_expiry_idx
  on public.pachanga_venue_pitch_claims(expires_at, server_sequence, id)
  where status = 'ACTIVE' and source_kind = 'HOLD';

create table if not exists public.pachanga_venue_reservation_holds (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.pachanga_venue_reservation_requests(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  claim_id uuid not null unique references public.pachanga_venue_pitch_claims(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  expires_at timestamptz not null,
  status text not null default 'ACTIVE',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  released_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  released_at timestamptz,
  check (ends_at > starts_at),
  check (expires_at > created_at),
  check (status in ('ACTIVE', 'EXPIRED', 'RELEASED', 'CONSUMED')),
  check (revision >= 1),
  check ((status = 'ACTIVE' and released_at is null) or status <> 'ACTIVE')
);

create unique index if not exists pachanga_venue_hold_active_request_idx
  on public.pachanga_venue_reservation_holds(request_id)
  where status = 'ACTIVE';
create index if not exists pachanga_venue_holds_expiry_idx
  on public.pachanga_venue_reservation_holds(expires_at, server_sequence, id)
  where status = 'ACTIVE';

create table if not exists private.pachanga_venue_reservation_terms (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.pachanga_venue_reservation_requests(id) on delete restrict,
  terms_kind text not null,
  amount_minor bigint,
  currency text,
  public_rate_allowed boolean not null default false,
  tax_display_text text,
  private_notes text not null default '',
  cancellation_terms text not null default '',
  terms_snapshot jsonb not null default '{}'::jsonb check (jsonb_typeof(terms_snapshot) = 'object'),
  version integer not null check (version >= 1),
  operation_id uuid not null,
  created_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  created_at timestamptz not null default clock_timestamp(),
  check (terms_kind in ('FREE', 'FIXED_QUOTE', 'NEGOTIABLE', 'CONTACT_CLUB')),
  check (amount_minor is null or amount_minor >= 0),
  check (
    (terms_kind = 'FIXED_QUOTE' and amount_minor is not null and currency ~ '^[A-Z]{3}$')
    or (terms_kind <> 'FIXED_QUOTE' and amount_minor is null and currency is null)
  ),
  check (tax_display_text is null or length(tax_display_text) <= 500),
  check (length(private_notes) <= 2000),
  check (length(cancellation_terms) <= 2000),
  unique (request_id, version),
  unique (operation_id, request_id)
);

create table if not exists public.pachanga_venue_reservations (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.pachanga_venue_reservation_requests(id) on delete restrict,
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  requester_user_id uuid not null references auth.users(id) on delete restrict,
  requester_team_id uuid references public.pachanga_groups(id) on delete restrict,
  requester_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  competition_id uuid references public.pachanga_competitions(id) on delete restrict,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  terms_id uuid not null unique references private.pachanga_venue_reservation_terms(id) on delete restrict,
  claim_id uuid not null unique references public.pachanga_venue_pitch_claims(id) on delete restrict,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  timezone text not null,
  status text not null default 'PENDING_CONFIRMATION',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz not null default clock_timestamp(),
  confirmed_by uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancelled_at timestamptz,
  cancellation_reason_code text,
  consumed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (ends_at > starts_at),
  check (length(timezone) between 1 and 80),
  check (status in ('PENDING_CONFIRMATION', 'CONFIRMED', 'CANCELLED', 'CONSUMED')),
  check (revision >= 1),
  check ((status = 'CONFIRMED' and confirmed_at is not null) or status <> 'CONFIRMED'),
  check ((status = 'CANCELLED' and cancelled_at is not null) or status <> 'CANCELLED'),
  check ((status = 'CONSUMED' and consumed_at is not null) or status <> 'CONSUMED')
);

alter table public.pachanga_venue_reservation_requests
  add constraint pachanga_venue_requests_current_hold_fk
  foreign key (current_hold_id) references public.pachanga_venue_reservation_holds(id) on delete restrict;
alter table public.pachanga_venue_reservation_requests
  add constraint pachanga_venue_requests_current_reservation_fk
  foreign key (current_reservation_id) references public.pachanga_venue_reservations(id) on delete restrict;

create index if not exists pachanga_venue_reservations_pitch_idx
  on public.pachanga_venue_reservations(
    pitch_id, status, starts_at, ends_at, server_sequence, id
  );
create index if not exists pachanga_venue_reservations_requester_idx
  on public.pachanga_venue_reservations(
    requester_user_id, status, server_sequence desc, id
  );
create index if not exists pachanga_venue_reservations_match_idx
  on public.pachanga_venue_reservations(canonical_match_id, status, server_sequence, id)
  where canonical_match_id is not null;

create table if not exists private.pachanga_venue_reservation_revisions (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.pachanga_venue_reservations(id) on delete restrict,
  revision bigint not null check (revision >= 1),
  action text not null,
  status text not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  unique (reservation_id, revision),
  unique (operation_id, reservation_id)
);

comment on table public.pachanga_venue_pitch_claims is
  'Single overlap authority for holds and canonical reservations. Released history never blocks future writes.';
comment on table private.pachanga_venue_reservation_terms is
  'Private, immutable terms snapshots. Pachangas IQ does not process Venue payments in Wave 9A.';

reset statement_timeout;
reset lock_timeout;
