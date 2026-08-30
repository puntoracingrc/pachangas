-- Pachangas IQ Wave 9A: canonical Venue and Pitch foundation.
-- Exact operational location is canonical but never exposed by public read models.

set lock_timeout = '5s';
set statement_timeout = '120s';

create sequence if not exists private.pachanga_venue_sequence;
revoke all on sequence private.pachanga_venue_sequence from public, anon, authenticated;
grant usage, select on sequence private.pachanga_venue_sequence to service_role;

create table if not exists private.pachanga_venue_settings_v1 (
  singleton boolean primary key default true check (singleton),
  venue_foundation_enabled boolean not null default false,
  venue_management_enabled boolean not null default false,
  venue_public_profiles_enabled boolean not null default false,
  venue_public_directory_enabled boolean not null default false,
  venue_availability_enabled boolean not null default false,
  venue_reservation_requests_enabled boolean not null default false,
  venue_counteroffers_enabled boolean not null default false,
  venue_reservation_holds_enabled boolean not null default false,
  venue_canonical_reservations_enabled boolean not null default false,
  venue_match_binding_enabled boolean not null default false,
  venue_r4d_integration_enabled boolean not null default false,
  demo_world_v34_enabled boolean not null default false,
  venue_payments_enabled boolean not null default false,
  venue_recurring_bookings_enabled boolean not null default false,
  venue_bulk_competition_allocation_enabled boolean not null default false,
  venue_external_integrations_enabled boolean not null default false,
  revision bigint not null default 1 check (revision >= 1),
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (not venue_management_enabled or venue_foundation_enabled),
  check (not venue_public_profiles_enabled or venue_foundation_enabled),
  check (not venue_public_directory_enabled or venue_public_profiles_enabled),
  check (not venue_availability_enabled or venue_management_enabled),
  check (not venue_reservation_requests_enabled or venue_availability_enabled),
  check (not venue_counteroffers_enabled or venue_reservation_requests_enabled),
  check (not venue_reservation_holds_enabled or venue_reservation_requests_enabled),
  check (not venue_canonical_reservations_enabled or venue_reservation_requests_enabled),
  check (not venue_match_binding_enabled or venue_canonical_reservations_enabled),
  check (not venue_r4d_integration_enabled or venue_match_binding_enabled),
  check (not venue_payments_enabled or venue_canonical_reservations_enabled),
  check (not venue_recurring_bookings_enabled or venue_availability_enabled),
  check (not venue_bulk_competition_allocation_enabled or venue_match_binding_enabled),
  check (not venue_external_integrations_enabled or venue_foundation_enabled)
);

insert into private.pachanga_venue_settings_v1(singleton)
values (true)
on conflict (singleton) do nothing;

alter table public.pachanga_club_memberships
  drop constraint if exists pachanga_club_memberships_role_check;
alter table public.pachanga_club_memberships
  add constraint pachanga_club_memberships_role_check check (role in (
    'club_owner', 'club_admin', 'club_competition_manager', 'club_viewer',
    'club_venue_manager', 'club_reservation_manager',
    'club_referee_manager', 'club_finance_manager'
  ));

alter table public.pachanga_club_invitations
  drop constraint if exists pachanga_club_invitations_role_check;
alter table public.pachanga_club_invitations
  add constraint pachanga_club_invitations_role_check check (role in (
    'club_owner', 'club_admin', 'club_competition_manager', 'club_viewer',
    'club_venue_manager', 'club_reservation_manager'
  ));

create or replace function private.pachanga_club_can_v1(
  target_club_id uuid,
  target_user_id uuid,
  target_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_role text;
begin
  if target_user_id is null then return false; end if;
  if private.pachanga_club_platform_can_v1(target_user_id, 'clubs.manage') then return true; end if;
  if target_capability in ('read', 'venue_read', 'reservation_read')
     and private.pachanga_club_platform_can_v1(target_user_id, 'clubs.read') then return true; end if;
  selected_role := private.pachanga_club_active_role_v1(target_club_id, target_user_id);
  return case selected_role
    when 'club_owner' then target_capability in (
      'read', 'profile_manage', 'staff_manage', 'staff_manage_non_owner',
      'team_links_manage', 'competition_create', 'competition_manage', 'ownership_manage',
      'referee_manage', 'venue_read', 'venue_manage',
      'reservation_read', 'reservation_manage'
    )
    when 'club_admin' then target_capability in (
      'read', 'profile_manage', 'staff_manage_non_owner', 'team_links_manage',
      'referee_manage', 'venue_read', 'venue_manage',
      'reservation_read', 'reservation_manage'
    )
    when 'club_competition_manager' then target_capability in (
      'read', 'competition_create', 'competition_manage',
      'venue_read', 'reservation_read', 'reservation_request'
    )
    when 'club_venue_manager' then target_capability in (
      'read', 'venue_read', 'venue_manage', 'reservation_read'
    )
    when 'club_reservation_manager' then target_capability in (
      'read', 'venue_read', 'reservation_read', 'reservation_manage'
    )
    when 'club_referee_manager' then target_capability in ('read', 'referee_manage')
    when 'club_finance_manager' then target_capability in ('read', 'reservation_read')
    when 'club_viewer' then target_capability in ('read', 'venue_read')
    else false
  end;
end;
$$;

revoke all on function private.pachanga_club_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create table if not exists public.pachanga_club_venues (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.pachanga_clubs(id) on delete restrict,
  name text not null,
  slug text not null unique,
  description text not null default '',
  municipality text not null default '',
  general_area text not null default '',
  timezone text not null default 'Europe/Madrid',
  place_id text,
  private_address text not null default '',
  public_address text,
  private_latitude numeric(9,6),
  private_longitude numeric(9,6),
  public_latitude numeric(9,6),
  public_longitude numeric(9,6),
  private_access_instructions text not null default '',
  private_contact_name text,
  private_contact_phone text,
  private_contact_email text,
  visibility text not null default 'PRIVATE',
  lifecycle text not null default 'DRAFT',
  public_content_fingerprint text,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (length(trim(name)) between 2 and 120),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 3 and 100),
  check (length(description) <= 3000),
  check (length(municipality) <= 120 and length(general_area) <= 160),
  check (length(timezone) between 1 and 80),
  check (place_id is null or length(place_id) <= 240),
  check (length(private_address) <= 500),
  check (public_address is null or length(public_address) <= 500),
  check (private_latitude is null or private_latitude between -90 and 90),
  check (private_longitude is null or private_longitude between -180 and 180),
  check (public_latitude is null or public_latitude between -90 and 90),
  check (public_longitude is null or public_longitude between -180 and 180),
  check (length(private_access_instructions) <= 3000),
  check (private_contact_name is null or length(private_contact_name) <= 160),
  check (private_contact_phone is null or length(private_contact_phone) <= 80),
  check (private_contact_email is null or length(private_contact_email) <= 320),
  check (visibility in ('PRIVATE', 'UNLISTED', 'PUBLIC')),
  check (lifecycle in ('DRAFT', 'PENDING_REVIEW', 'ACTIVE', 'SUSPENDED', 'ARCHIVED')),
  check (public_content_fingerprint is null or length(public_content_fingerprint) = 64),
  check (revision >= 1)
);

create unique index if not exists pachanga_club_venues_club_name_idx
  on public.pachanga_club_venues(club_id, lower(name))
  where lifecycle <> 'ARCHIVED';
create index if not exists pachanga_club_venues_club_idx
  on public.pachanga_club_venues(club_id, lifecycle, server_sequence desc, id);
create index if not exists pachanga_club_venues_public_idx
  on public.pachanga_club_venues(municipality, lifecycle, server_sequence desc, id)
  where visibility = 'PUBLIC' and lifecycle = 'ACTIVE';

create table if not exists private.pachanga_club_venue_revisions (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  revision bigint not null check (revision >= 1),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  reason_code text not null,
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  created_at timestamptz not null default clock_timestamp(),
  unique (venue_id, revision),
  unique (operation_id, venue_id)
);

create table if not exists private.pachanga_venue_publication_consents (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  version integer not null check (version >= 1),
  purpose text not null default 'PUBLIC_VENUE_PROFILE',
  selected_fields jsonb not null check (jsonb_typeof(selected_fields) = 'object'),
  public_address_mode text not null default 'AREA_ONLY',
  public_rate_allowed boolean not null default false,
  content_fingerprint text not null check (length(content_fingerprint) = 64),
  status text not null default 'ACTIVE',
  revision bigint not null default 1 check (revision >= 1),
  operation_id uuid not null,
  consented_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique,
  consented_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  check (purpose = 'PUBLIC_VENUE_PROFILE'),
  check (public_address_mode in ('AREA_ONLY', 'PUBLIC_ADDRESS', 'APPROXIMATE_COORDINATES', 'EXACT_COORDINATES')),
  check (status in ('ACTIVE', 'SUPERSEDED', 'REVOKED')),
  unique (venue_id, version),
  unique (operation_id, venue_id)
);

create unique index if not exists pachanga_venue_publication_consent_active_idx
  on private.pachanga_venue_publication_consents(venue_id)
  where status = 'ACTIVE';

create table if not exists public.pachanga_venue_pitches (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  parent_pitch_id uuid references public.pachanga_venue_pitches(id) on delete restrict,
  conflict_scope_id uuid not null,
  name text not null,
  slug text not null,
  modalities text[] not null,
  surface text not null default 'ARTIFICIAL_GRASS',
  environment text not null default 'OUTDOOR',
  width_m numeric(6,2),
  length_m numeric(6,2),
  has_lighting boolean not null default false,
  has_changing_rooms boolean not null default false,
  has_showers boolean not null default false,
  is_accessible boolean not null default false,
  has_parking boolean not null default false,
  spectator_capacity integer,
  public_rate_kind text not null default 'CONTACT_CLUB',
  public_rate_amount_minor bigint,
  public_rate_currency text,
  public_rate_note text,
  status text not null default 'ACTIVE',
  visibility text not null default 'PRIVATE',
  minimum_slot_minutes integer not null default 60,
  buffer_minutes integer not null default 0,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (length(trim(name)) between 1 and 120),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 1 and 100),
  check (cardinality(modalities) between 1 and 4),
  check (modalities <@ array['F5','F7','F11','FUTSAL']::text[]),
  check (surface in ('ARTIFICIAL_GRASS', 'NATURAL_GRASS', 'PARQUET', 'CONCRETE', 'RUBBER', 'OTHER')),
  check (environment in ('INDOOR', 'OUTDOOR', 'COVERED')),
  check (width_m is null or width_m between 5 and 150),
  check (length_m is null or length_m between 10 and 250),
  check (spectator_capacity is null or spectator_capacity >= 0),
  check (public_rate_kind in ('FREE', 'FIXED_QUOTE', 'NEGOTIABLE', 'CONTACT_CLUB')),
  check (public_rate_amount_minor is null or public_rate_amount_minor >= 0),
  check (
    (public_rate_kind = 'FIXED_QUOTE'
      and public_rate_amount_minor is not null
      and public_rate_currency ~ '^[A-Z]{3}$')
    or (public_rate_kind <> 'FIXED_QUOTE'
      and public_rate_amount_minor is null
      and public_rate_currency is null)
  ),
  check (public_rate_note is null or length(public_rate_note) <= 500),
  check (status in ('ACTIVE', 'MAINTENANCE', 'TEMPORARILY_CLOSED', 'ARCHIVED')),
  check (visibility in ('PRIVATE', 'UNLISTED', 'PUBLIC')),
  check (minimum_slot_minutes between 15 and 360),
  check (buffer_minutes between 0 and 180),
  check (revision >= 1),
  unique (venue_id, slug)
);

alter table public.pachanga_venue_pitches
  drop constraint if exists pachanga_venue_pitches_parent_same_venue_v1;

create or replace function private.pachanga_venue_pitch_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare parent_row public.pachanga_venue_pitches%rowtype;
begin
  if new.parent_pitch_id is null then
    new.conflict_scope_id := new.id;
  else
    select * into parent_row
    from public.pachanga_venue_pitches pitches
    where pitches.id = new.parent_pitch_id;
    if not found or parent_row.venue_id <> new.venue_id then
      raise exception 'VENUE_PITCH_PARENT_INVALID' using errcode = '23514';
    end if;
    if parent_row.parent_pitch_id is not null then
      raise exception 'VENUE_PITCH_NESTING_UNSUPPORTED' using errcode = '23514';
    end if;
    new.conflict_scope_id := parent_row.conflict_scope_id;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_venue_pitch_scope_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_venue_pitch_scope_v1 on public.pachanga_venue_pitches;
create trigger pachanga_venue_pitch_scope_v1
before insert or update of parent_pitch_id, venue_id
on public.pachanga_venue_pitches
for each row execute function private.pachanga_venue_pitch_scope_v1();

create index if not exists pachanga_venue_pitches_venue_idx
  on public.pachanga_venue_pitches(venue_id, status, server_sequence desc, id);
create index if not exists pachanga_venue_pitches_modalities_idx
  on public.pachanga_venue_pitches using gin(modalities);
create index if not exists pachanga_venue_pitches_scope_idx
  on public.pachanga_venue_pitches(conflict_scope_id, status, id);

create table if not exists private.pachanga_venue_pitch_revisions (
  id uuid primary key default gen_random_uuid(),
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  revision bigint not null check (revision >= 1),
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  reason_code text not null,
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  created_at timestamptz not null default clock_timestamp(),
  unique (pitch_id, revision),
  unique (operation_id, pitch_id)
);

comment on table public.pachanga_club_venues is
  'Canonical Club Venue authority. Exact location remains private behind RPC read models.';
comment on table public.pachanga_venue_pitches is
  'Canonical reservable Pitch authority. parent/child pitches share one conservative conflict scope in V1.';
comment on column public.pachanga_venue_pitches.conflict_scope_id is
  'Reservation exclusion scope. V1 deliberately prevents simultaneous parent/child or sibling subdivision bookings.';

reset statement_timeout;
reset lock_timeout;
