-- Pachangas IQ Wave 9B: finite recurring Venue blocks and deterministic occurrences.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_venue_settings_v1
  add column if not exists venue_recurring_series_enabled boolean not null default false,
  add column if not exists venue_recurring_materialization_enabled boolean not null default false,
  add column if not exists venue_public_recurring_sales_enabled boolean not null default false,
  add column if not exists venue_external_calendar_enabled boolean not null default false;

create table if not exists public.pachanga_venue_recurring_series (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  owner_club_id uuid not null references public.pachanga_clubs(id) on delete restrict,
  purpose text not null,
  team_id uuid references public.pachanga_groups(id) on delete restrict,
  competition_id uuid references public.pachanga_competitions(id) on delete restrict,
  modality text not null,
  frequency text not null,
  timezone text not null,
  weekday smallint not null,
  local_start_time time without time zone not null,
  local_offset_minutes integer,
  duration_minutes integer not null,
  buffer_minutes integer not null default 0,
  start_date date not null,
  end_date date not null,
  status text not null default 'draft',
  current_revision_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  offered_at timestamptz,
  accepted_at timestamptz,
  published_at timestamptz,
  paused_at timestamptz,
  ended_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (purpose in ('TEAM_RECURRING_BLOCK', 'COMPETITION_RECURRING_BLOCK')),
  check (
    (purpose = 'TEAM_RECURRING_BLOCK' and team_id is not null and competition_id is null)
    or (purpose = 'COMPETITION_RECURRING_BLOCK' and competition_id is not null and team_id is null)
  ),
  check (modality in ('F5', 'F7', 'F11', 'FUTSAL')),
  check (frequency in ('WEEKLY', 'BIWEEKLY')),
  check (length(timezone) between 1 and 80),
  check (weekday between 1 and 7),
  check (local_offset_minutes is null or local_offset_minutes between -840 and 840),
  check (duration_minutes between 15 and 720),
  check (buffer_minutes between 0 and 180),
  check (end_date >= start_date),
  check (end_date <= start_date + 728),
  check (status in (
    'draft', 'validated', 'offered', 'accepted', 'published', 'paused',
    'completed', 'ended', 'cancelled'
  )),
  check (revision >= 1),
  check (status <> 'offered' or offered_at is not null),
  check (status <> 'accepted' or accepted_at is not null),
  check (status not in ('published', 'paused', 'completed', 'ended') or published_at is not null),
  check (status <> 'paused' or paused_at is not null),
  check (status not in ('completed', 'ended') or ended_at is not null),
  check (status <> 'cancelled' or cancelled_at is not null)
);

create unique index if not exists pachanga_venue_recurring_series_operation_idx
  on public.pachanga_venue_recurring_series(operation_id);
create index if not exists pachanga_venue_recurring_series_pitch_idx
  on public.pachanga_venue_recurring_series(
    pitch_id, status, start_date, end_date, server_sequence desc, id
  );
create index if not exists pachanga_venue_recurring_series_club_idx
  on public.pachanga_venue_recurring_series(
    owner_club_id, status, server_sequence desc, id
  );
create index if not exists pachanga_venue_recurring_series_competition_idx
  on public.pachanga_venue_recurring_series(
    competition_id, status, server_sequence desc, id
  ) where competition_id is not null;
create index if not exists pachanga_venue_recurring_series_team_idx
  on public.pachanga_venue_recurring_series(
    team_id, status, server_sequence desc, id
  ) where team_id is not null;

create table if not exists private.pachanga_venue_recurring_series_revisions (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.pachanga_venue_recurring_series(id) on delete restrict,
  version integer not null,
  action text not null,
  status text not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  impact_analysis jsonb not null default '{}'::jsonb check (jsonb_typeof(impact_analysis) = 'object'),
  checksum text not null check (length(checksum) = 64),
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  restored_at timestamptz,
  unique (series_id, version),
  unique (series_id, operation_id)
);

alter table public.pachanga_venue_recurring_series
  add constraint pachanga_venue_recurring_series_current_revision_fk
  foreign key (current_revision_id)
  references private.pachanga_venue_recurring_series_revisions(id) on delete restrict;

create table if not exists public.pachanga_venue_recurring_exceptions (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.pachanga_venue_recurring_series(id) on delete restrict,
  series_revision_id uuid not null references private.pachanga_venue_recurring_series_revisions(id) on delete restrict,
  exception_date date not null,
  exception_kind text not null,
  replacement_pitch_id uuid references public.pachanga_venue_pitches(id) on delete restrict,
  replacement_local_start_time time without time zone,
  replacement_duration_minutes integer,
  reason_code text not null,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  superseded_by_id uuid references public.pachanga_venue_recurring_exceptions(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  check (exception_kind in ('SKIP', 'REPLACE')),
  check (
    (exception_kind = 'SKIP' and replacement_pitch_id is null
      and replacement_local_start_time is null and replacement_duration_minutes is null)
    or (exception_kind = 'REPLACE' and replacement_local_start_time is not null
      and replacement_duration_minutes between 15 and 720)
  ),
  check (length(trim(reason_code)) between 2 and 120),
  check (status in ('active', 'superseded', 'cancelled')),
  check (revision >= 1),
  check ((status = 'superseded' and superseded_at is not null and superseded_by_id is not null)
    or status <> 'superseded')
);

create unique index if not exists pachanga_venue_recurring_exception_active_idx
  on public.pachanga_venue_recurring_exceptions(series_id, exception_date)
  where status = 'active';
create unique index if not exists pachanga_venue_recurring_exception_operation_idx
  on public.pachanga_venue_recurring_exceptions(operation_id);

create table if not exists public.pachanga_venue_recurring_occurrences (
  id uuid primary key,
  series_id uuid not null references public.pachanga_venue_recurring_series(id) on delete restrict,
  series_revision_id uuid not null references private.pachanga_venue_recurring_series_revisions(id) on delete restrict,
  occurrence_date date not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  timezone text not null,
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  exception_id uuid references public.pachanga_venue_recurring_exceptions(id) on delete restrict,
  reservation_id uuid references public.pachanga_venue_reservations(id) on delete restrict,
  status text not null default 'planned',
  checksum text not null check (length(checksum) = 64),
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  materialized_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (ends_at > starts_at),
  check (length(timezone) between 1 and 80),
  check (status in (
    'planned', 'excluded', 'held', 'reserved', 'superseded', 'cancelled', 'consumed'
  )),
  check (revision >= 1),
  unique (series_id, occurrence_date)
);

create index if not exists pachanga_venue_recurring_occurrence_pitch_idx
  on public.pachanga_venue_recurring_occurrences(
    pitch_id, status, starts_at, ends_at, server_sequence, id
  );
create index if not exists pachanga_venue_recurring_occurrence_series_idx
  on public.pachanga_venue_recurring_occurrences(
    series_id, occurrence_date, server_sequence, id
  );
create index if not exists pachanga_venue_recurring_occurrence_reservation_idx
  on public.pachanga_venue_recurring_occurrences(reservation_id)
  where reservation_id is not null;

comment on table public.pachanga_venue_recurring_series is
  'Finite WEEKLY/BIWEEKLY reservation intent. A series never occupies a Pitch until Wave 9A creates a hold or canonical reservation.';
comment on table public.pachanga_venue_recurring_occurrences is
  'Deterministic bounded projections. Historical and consumed occurrences are never deleted by a series revision.';

reset statement_timeout;
reset lock_timeout;
