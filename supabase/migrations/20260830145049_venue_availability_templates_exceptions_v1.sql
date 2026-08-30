-- Pachangas IQ Wave 9A: recurring availability, exceptions and bounded occurrences.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_venue_resolve_local_v1(
  target_local timestamp without time zone,
  target_timezone text,
  target_offset_minutes integer default null
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare resolved timestamptz;
declare candidate timestamptz;
begin
  if target_local is null or nullif(trim(coalesce(target_timezone, '')), '') is null then
    raise exception 'VENUE_LOCAL_TIME_REQUIRED' using errcode = '22023';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_timezone_names zones
    where zones.name = target_timezone
  ) then
    raise exception 'VENUE_TIMEZONE_INVALID' using errcode = '22023';
  end if;
  if target_offset_minutes is not null then
    if target_offset_minutes not between -840 and 840 then
      raise exception 'VENUE_TIMEZONE_OFFSET_INVALID' using errcode = '22023';
    end if;
    candidate := target_local - make_interval(mins => target_offset_minutes);
    if candidate at time zone target_timezone <> target_local then
      raise exception 'VENUE_LOCAL_TIME_OFFSET_MISMATCH' using errcode = '22023';
    end if;
    return candidate;
  end if;
  resolved := target_local at time zone target_timezone;
  if resolved at time zone target_timezone <> target_local then
    raise exception 'VENUE_LOCAL_TIME_DOES_NOT_EXIST' using errcode = '22023';
  end if;
  if (resolved - interval '1 hour') at time zone target_timezone = target_local
     or (resolved + interval '1 hour') at time zone target_timezone = target_local then
    raise exception 'VENUE_LOCAL_TIME_AMBIGUOUS_OFFSET_REQUIRED' using errcode = '22023';
  end if;
  return resolved;
end;
$$;

revoke all on function private.pachanga_venue_resolve_local_v1(
  timestamp without time zone, text, integer
) from public, anon, authenticated;

create or replace function private.pachanga_venue_offset_minutes_v1(
  target_instant timestamptz,
  target_timezone text
)
returns integer
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select round(extract(epoch from (
    (target_instant at time zone target_timezone)
    - (target_instant at time zone 'UTC')
  )) / 60)::integer;
$$;

revoke all on function private.pachanga_venue_offset_minutes_v1(timestamptz, text)
  from public, anon, authenticated;

create table if not exists public.pachanga_venue_availability_templates (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  weekday smallint not null,
  start_local_time time without time zone not null,
  end_local_time time without time zone not null,
  slot_minutes integer not null,
  buffer_minutes integer not null default 0,
  valid_from date not null,
  valid_until date,
  timezone text not null,
  modalities text[] not null,
  capacity integer not null default 1,
  visibility text not null default 'PRIVATE',
  status text not null default 'ACTIVE',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (weekday between 1 and 7),
  check (end_local_time > start_local_time),
  check (slot_minutes between 15 and 360),
  check (buffer_minutes between 0 and 180),
  check (valid_until is null or valid_until >= valid_from),
  check (length(timezone) between 1 and 80),
  check (cardinality(modalities) between 1 and 4),
  check (modalities <@ array['F5','F7','F11','FUTSAL']::text[]),
  check (capacity between 1 and 100),
  check (visibility in ('PRIVATE', 'UNLISTED', 'PUBLIC')),
  check (status in ('ACTIVE', 'DISABLED')),
  check (revision >= 1)
);

create index if not exists pachanga_venue_availability_templates_pitch_idx
  on public.pachanga_venue_availability_templates(
    pitch_id, status, weekday, valid_from, valid_until, server_sequence, id
  );
create index if not exists pachanga_venue_availability_templates_modalities_idx
  on public.pachanga_venue_availability_templates using gin(modalities);

create table if not exists private.pachanga_venue_availability_template_revisions (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.pachanga_venue_availability_templates(id) on delete restrict,
  revision bigint not null check (revision >= 1),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  reason_code text not null,
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  created_at timestamptz not null default clock_timestamp(),
  unique (template_id, revision),
  unique (operation_id, template_id)
);

create table if not exists public.pachanga_venue_availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  exception_kind text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_range tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  public_reason text,
  private_reason text not null default '',
  visibility text not null default 'PRIVATE',
  priority integer not null default 100,
  status text not null default 'ACTIVE',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (exception_kind in ('BLOCKED', 'MAINTENANCE', 'CLOSED', 'SPECIAL_OPENING', 'PRIVATE_HOLD', 'EVENT')),
  check (ends_at > starts_at),
  check (public_reason is null or length(public_reason) <= 500),
  check (length(private_reason) <= 2000),
  check (visibility in ('PRIVATE', 'UNLISTED', 'PUBLIC')),
  check (priority between 0 and 1000),
  check (status in ('ACTIVE', 'CANCELLED')),
  check (revision >= 1)
);

create index if not exists pachanga_venue_availability_exceptions_pitch_idx
  on public.pachanga_venue_availability_exceptions(
    pitch_id, status, starts_at, ends_at, priority desc, server_sequence, id
  );
create index if not exists pachanga_venue_availability_exceptions_range_idx
  on public.pachanga_venue_availability_exceptions using gist(pitch_id, time_range)
  where status = 'ACTIVE';

create table if not exists private.pachanga_venue_availability_exception_revisions (
  id uuid primary key default gen_random_uuid(),
  exception_id uuid not null references public.pachanga_venue_availability_exceptions(id) on delete restrict,
  revision bigint not null check (revision >= 1),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  reason_code text not null,
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  created_at timestamptz not null default clock_timestamp(),
  unique (exception_id, revision),
  unique (operation_id, exception_id)
);

create table if not exists private.pachanga_venue_availability_occurrences (
  id uuid primary key default gen_random_uuid(),
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  source_kind text not null,
  source_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_range tstzrange generated always as (tstzrange(starts_at, ends_at, '[)')) stored,
  availability_status text not null,
  reason_code text not null,
  source_revision bigint not null,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  generated_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  check (source_kind in ('TEMPLATE', 'SPECIAL_OPENING')),
  check (ends_at > starts_at),
  check (availability_status in ('AVAILABLE', 'BLOCKED')),
  check (source_revision >= 1),
  check (expires_at > generated_at),
  check (ends_at <= starts_at + interval '24 hours'),
  unique (pitch_id, source_kind, source_id, starts_at, ends_at, source_revision)
);

create index if not exists pachanga_venue_availability_occurrences_pitch_idx
  on private.pachanga_venue_availability_occurrences(
    pitch_id, starts_at, ends_at, availability_status, server_sequence, id
  );

comment on table private.pachanga_venue_availability_occurrences is
  'Bounded, disposable read cache. Commands never materialize unbounded recurring calendars.';

reset statement_timeout;
reset lock_timeout;
