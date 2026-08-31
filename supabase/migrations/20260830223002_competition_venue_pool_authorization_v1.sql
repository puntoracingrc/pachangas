-- Pachangas IQ Wave 9B: explicit Competition Venue Pool authorization.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_venue_settings_v1
  add column if not exists competition_venue_pool_enabled boolean not null default false;

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_grants_capability_check,
  add constraint pachanga_competition_entitlement_grants_capability_check check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline', 'competition_entries_manage',
    'competition_rosters_review', 'competition_categories_manage', 'competition_schedule',
    'competition_results', 'competition_standings', 'competition_operations',
    'competition_discipline_manage', 'competition_discipline_review',
    'competition_appeals_manage', 'competition_venues', 'tournament_create',
    'tournament_manage', 'tournament_draw', 'tournament_draw_publish'
  ));

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'competition_schedule_manager',
    'competition_result_manager', 'competition_standings_manager',
    'competition_operations_manager', 'competition_discipline_manager',
    'competition_discipline_reviewer', 'competition_appeals_manager',
    'competition_draw_manager', 'competition_bracket_manager',
    'competition_venue_manager', 'viewer'
  ));

create table if not exists public.pachanga_competition_venue_pools (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  name text not null,
  purpose text not null default 'COMPETITION_MATCHES',
  visibility text not null default 'private',
  status text not null default 'draft',
  current_revision_id uuid,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  activated_at timestamptz,
  exhausted_at timestamptz,
  expired_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (length(trim(name)) between 2 and 160),
  check (purpose = 'COMPETITION_MATCHES'),
  check (visibility in ('private', 'competition_staff', 'participants')),
  check (status in ('draft', 'offered', 'accepted', 'active', 'exhausted', 'expired', 'revoked')),
  check (revision >= 1),
  check (status not in ('active', 'exhausted') or activated_at is not null),
  check (status <> 'exhausted' or exhausted_at is not null),
  check (status <> 'expired' or expired_at is not null),
  check (status <> 'revoked' or revoked_at is not null),
  unique (competition_id, edition_id, name),
  unique (operation_id)
);

create index if not exists pachanga_competition_venue_pools_competition_idx
  on public.pachanga_competition_venue_pools(
    competition_id, edition_id, status, server_sequence desc, id
  );
create index if not exists pachanga_competition_venue_pools_club_idx
  on public.pachanga_competition_venue_pools(
    organizer_club_id, status, server_sequence desc, id
  ) where organizer_club_id is not null;

create table if not exists private.pachanga_competition_venue_pool_revisions (
  id uuid primary key default gen_random_uuid(),
  pool_id uuid not null references public.pachanga_competition_venue_pools(id) on delete restrict,
  version integer not null,
  action text not null,
  status text not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  checksum text not null check (length(checksum) = 64),
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  unique (pool_id, version),
  unique (pool_id, operation_id)
);

alter table public.pachanga_competition_venue_pools
  add constraint pachanga_competition_venue_pool_current_revision_fk
  foreign key (current_revision_id)
  references private.pachanga_competition_venue_pool_revisions(id) on delete restrict;

create table if not exists public.pachanga_competition_venue_authorizations (
  id uuid primary key default gen_random_uuid(),
  pool_id uuid not null references public.pachanga_competition_venue_pools(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  owner_club_id uuid not null references public.pachanga_clubs(id) on delete restrict,
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  source_kind text not null,
  recurring_series_id uuid references public.pachanga_venue_recurring_series(id) on delete restrict,
  reservation_id uuid references public.pachanga_venue_reservations(id) on delete restrict,
  authorized_pitch_ids uuid[] not null,
  modalities text[] not null,
  valid_from date not null,
  valid_until date not null,
  allowed_weekdays smallint[] not null default array[1,2,3,4,5,6,7]::smallint[],
  local_start_time time without time zone not null default '00:00',
  local_end_time time without time zone not null default '23:59:59',
  capacity_per_slot integer not null default 1,
  priority integer not null default 100,
  purpose text not null default 'COMPETITION_MATCHES',
  visibility text not null default 'private',
  status text not null default 'draft',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  offered_by uuid references auth.users(id) on delete set null,
  offered_at timestamptz,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  activated_by uuid references auth.users(id) on delete set null,
  activated_at timestamptz,
  expires_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (source_kind in (
    'SELF_MANAGED', 'CLUB_OFFER', 'RECURRING_SERIES',
    'CONFIRMED_RESERVATION', 'AVAILABILITY_AGREEMENT'
  )),
  check ((source_kind = 'RECURRING_SERIES') = (recurring_series_id is not null)),
  check ((source_kind = 'CONFIRMED_RESERVATION') = (reservation_id is not null)),
  check (cardinality(authorized_pitch_ids) between 1 and 100),
  check (cardinality(modalities) between 1 and 4),
  check (modalities <@ array['F5','F7','F11','FUTSAL']::text[]),
  check (valid_until >= valid_from),
  check (cardinality(allowed_weekdays) between 1 and 7),
  check (allowed_weekdays <@ array[1,2,3,4,5,6,7]::smallint[]),
  check (local_end_time > local_start_time),
  check (capacity_per_slot between 1 and 20),
  check (priority between 1 and 1000),
  check (purpose = 'COMPETITION_MATCHES'),
  check (visibility in ('private', 'competition_staff', 'participants')),
  check (status in ('draft', 'offered', 'accepted', 'active', 'exhausted', 'expired', 'revoked')),
  check (revision >= 1),
  check (status <> 'offered' or (offered_by is not null and offered_at is not null)),
  check (status <> 'accepted' or (accepted_by is not null and accepted_at is not null)),
  check (status not in ('active', 'exhausted') or (activated_by is not null and activated_at is not null)),
  check (status <> 'expired' or expires_at is not null),
  check (status <> 'revoked' or (revoked_by is not null and revoked_at is not null)),
  unique (operation_id)
);

create index if not exists pachanga_competition_venue_authorization_pool_idx
  on public.pachanga_competition_venue_authorizations(
    pool_id, status, priority, server_sequence, id
  );
create index if not exists pachanga_competition_venue_authorization_owner_idx
  on public.pachanga_competition_venue_authorizations(
    owner_club_id, status, server_sequence desc, id
  );
create index if not exists pachanga_competition_venue_authorization_venue_idx
  on public.pachanga_competition_venue_authorizations(
    venue_id, status, valid_from, valid_until, server_sequence, id
  );

create table if not exists public.pachanga_competition_venue_pool_memberships (
  id uuid primary key default gen_random_uuid(),
  pool_id uuid not null references public.pachanga_competition_venue_pools(id) on delete restrict,
  authorization_id uuid not null references public.pachanga_competition_venue_authorizations(id) on delete restrict,
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  modality text not null,
  priority integer not null default 100,
  capacity_limit integer,
  consumed_count integer not null default 0,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  exhausted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (modality in ('F5', 'F7', 'F11', 'FUTSAL')),
  check (priority between 1 and 1000),
  check (capacity_limit is null or capacity_limit between 1 and 10000),
  check (consumed_count >= 0),
  check (capacity_limit is null or consumed_count <= capacity_limit),
  check (status in ('active', 'exhausted', 'expired', 'revoked')),
  check (revision >= 1),
  check (status <> 'exhausted' or exhausted_at is not null),
  check (status <> 'revoked' or revoked_at is not null),
  unique (operation_id)
);

create unique index if not exists pachanga_competition_venue_pool_membership_active_idx
  on public.pachanga_competition_venue_pool_memberships(pool_id, pitch_id, modality)
  where status = 'active';
create index if not exists pachanga_competition_venue_pool_membership_pitch_idx
  on public.pachanga_competition_venue_pool_memberships(
    pitch_id, status, priority, server_sequence, id
  );

comment on table public.pachanga_competition_venue_authorizations is
  'Explicit Club decision permitting one Competition edition to use a bounded Venue window. Public directory visibility never grants allocation authority.';
comment on table public.pachanga_competition_venue_pool_memberships is
  'Authorized Pitch and modality membership. Consumption is preserved and revoked rows are never deleted.';

reset statement_timeout;
reset lock_timeout;
