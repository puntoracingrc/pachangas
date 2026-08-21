-- Pachangas IQ Referee Platform R3: canonical profiles, availability, relationships,
-- assignments and rebuildable statistics. Every product flag defaults OFF.

create schema if not exists private;
create extension if not exists pgcrypto with schema extensions;

create sequence if not exists private.pachanga_referee_sequence;
revoke all on sequence private.pachanga_referee_sequence from public, anon, authenticated;
grant usage, select on sequence private.pachanga_referee_sequence to service_role;

create table if not exists private.pachanga_referee_foundation_settings (
  singleton boolean primary key default true check (singleton),
  referee_foundation_enabled boolean not null default false,
  referee_self_service_enabled boolean not null default false,
  referee_public_profiles_enabled boolean not null default false,
  referee_marketplace_enabled boolean not null default false,
  referee_club_relationships_enabled boolean not null default false,
  referee_assignments_enabled boolean not null default false,
  revision bigint not null default 1 check (revision >= 1),
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (not referee_self_service_enabled or referee_foundation_enabled),
  check (not referee_public_profiles_enabled or referee_foundation_enabled),
  check (not referee_marketplace_enabled or (referee_foundation_enabled and referee_public_profiles_enabled)),
  check (not referee_club_relationships_enabled or referee_foundation_enabled),
  check (not referee_assignments_enabled or referee_foundation_enabled)
);

insert into private.pachanga_referee_foundation_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists private.pachanga_referee_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null default 'authenticated',
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  request_hash text not null,
  confirmed_revision bigint not null check (confirmed_revision >= 0),
  server_sequence bigint not null,
  client_metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(client_metadata) = 'object'),
  response jsonb not null check (jsonb_typeof(response) = 'object'),
  created_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'service_authority')),
  check (length(request_hash) = 64)
);

create table if not exists private.pachanga_referee_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null default 'authenticated',
  aggregate_type text not null,
  aggregate_id text not null,
  profile_id uuid,
  club_id uuid,
  canonical_match_id uuid,
  action text not null,
  aggregate_revision bigint not null check (aggregate_revision >= 0),
  server_sequence bigint not null unique,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(event_payload) = 'object'),
  confirmed_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'service_authority'))
);

create table if not exists public.pachanga_referee_profiles (
  id uuid primary key,
  user_id uuid not null unique references auth.users(id) on delete restrict,
  slug text not null unique,
  public_display_name_snapshot text not null,
  public_avatar_snapshot text,
  bio text not null default '',
  experience_since_year integer,
  experience_summary text not null default '',
  operational_status text not null default 'draft',
  verification_status text not null default 'unverified',
  visibility text not null default 'private',
  marketplace_status text not null default 'not_listed',
  availability_status text not null default 'UNAVAILABLE',
  available_for_assignments boolean not null default false,
  share_recurring_availability boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 3 and 80),
  check (length(trim(public_display_name_snapshot)) between 2 and 80),
  check (public_avatar_snapshot is null or length(public_avatar_snapshot) <= 2000),
  check (length(bio) <= 1200),
  check (length(experience_summary) <= 1200),
  check (experience_since_year is null or experience_since_year between 1950 and 2100),
  check (operational_status in ('draft', 'active', 'suspended', 'archived')),
  check (verification_status in ('unverified', 'pending', 'verified', 'rejected', 'revoked')),
  check (visibility in ('private', 'unlisted', 'public')),
  check (marketplace_status in ('not_listed', 'listed', 'paused')),
  check (availability_status in ('AVAILABLE', 'LIMITED', 'UNAVAILABLE')),
  check (revision >= 1),
  check (operational_status <> 'archived' or marketplace_status = 'not_listed')
);

alter table private.pachanga_referee_events
  add constraint pachanga_referee_events_profile_id_fkey
  foreign key (profile_id) references public.pachanga_referee_profiles(id) on delete restrict;
alter table private.pachanga_referee_events
  add constraint pachanga_referee_events_club_id_fkey
  foreign key (club_id) references public.pachanga_clubs(id) on delete restrict;
alter table private.pachanga_referee_events
  add constraint pachanga_referee_events_canonical_match_id_fkey
  foreign key (canonical_match_id) references public.pachanga_canonical_matches(id) on delete restrict;

create table if not exists public.pachanga_referee_modalities (
  id uuid primary key default gen_random_uuid(),
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  modality text not null,
  active boolean not null default true,
  experience_since_year integer,
  public_note text not null default '',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (referee_profile_id, modality),
  check (modality in ('FOOTBALL_11', 'FOOTBALL_7', 'FOOTBALL_5', 'FUTSAL', 'OTHER')),
  check (experience_since_year is null or experience_since_year between 1950 and 2100),
  check (length(public_note) <= 240),
  check (revision >= 1)
);

create table if not exists public.pachanga_referee_service_areas (
  id uuid primary key default gen_random_uuid(),
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  country_code text not null default 'ES',
  province text not null default '',
  municipality text not null default '',
  general_area text not null,
  travel_radius_km integer,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (country_code ~ '^[A-Z]{2}$'),
  check (length(province) <= 120 and length(municipality) <= 120),
  check (length(trim(general_area)) between 2 and 160),
  check (travel_radius_km is null or travel_radius_km between 1 and 500),
  check (status in ('active', 'inactive')),
  check (revision >= 1)
);

create unique index if not exists pachanga_referee_service_area_identity_idx
  on public.pachanga_referee_service_areas(
    referee_profile_id, country_code, lower(province), lower(municipality), lower(general_area)
  ) where status = 'active';

create table if not exists public.pachanga_referee_availability_windows (
  id uuid primary key default gen_random_uuid(),
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  weekday smallint not null,
  start_local_time time not null,
  end_local_time time not null,
  timezone text not null,
  public_visible boolean not null default false,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (weekday between 1 and 7),
  check (start_local_time < end_local_time),
  check (length(timezone) between 3 and 80),
  check (status in ('active', 'inactive')),
  check (revision >= 1)
);

create table if not exists public.pachanga_referee_availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  unavailable_from timestamptz not null,
  unavailable_until timestamptz not null,
  private_reason text not null default '',
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (unavailable_from < unavailable_until),
  check (unavailable_until <= unavailable_from + interval '366 days'),
  check (length(private_reason) <= 500),
  check (status in ('active', 'inactive')),
  check (revision >= 1)
);

create table if not exists public.pachanga_club_referee_relationships (
  id uuid primary key,
  club_id uuid not null references public.pachanga_clubs(id) on delete restrict,
  referee_profile_id uuid references public.pachanga_referee_profiles(id) on delete restrict,
  target_kind text not null,
  target_user_id uuid references auth.users(id) on delete restrict,
  relationship_type text not null,
  initiated_by text not null,
  status text not null,
  show_on_referee_profile boolean not null default false,
  show_on_club_profile boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  responded_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  ended_at timestamptz,
  ended_by uuid references auth.users(id) on delete set null,
  reason text not null default '',
  expires_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (target_kind in ('registered_user', 'email_target', 'profile_request')),
  check (relationship_type in ('REGULAR', 'COLLABORATOR', 'PREFERRED')),
  check (initiated_by in ('CLUB', 'REFEREE')),
  check (status in ('invited', 'requested', 'active', 'rejected', 'cancelled', 'ended')),
  check (revision >= 1),
  check (length(reason) <= 1200),
  check (
    (status = 'active' and referee_profile_id is not null and started_at is not null and ended_at is null)
    or (status in ('invited', 'requested') and started_at is null and ended_at is null)
    or (status in ('rejected', 'cancelled', 'ended') and ended_at is not null)
  ),
  check (
    (target_kind = 'registered_user' and target_user_id is not null)
    or (target_kind = 'email_target' and target_user_id is null)
    or (target_kind = 'profile_request' and referee_profile_id is not null and target_user_id is not null)
  )
);

create unique index if not exists pachanga_club_referee_relationship_current_idx
  on public.pachanga_club_referee_relationships(club_id, referee_profile_id)
  where referee_profile_id is not null and status in ('invited', 'requested', 'active');
create unique index if not exists pachanga_club_referee_registered_invite_idx
  on public.pachanga_club_referee_relationships(club_id, target_user_id)
  where target_kind = 'registered_user' and status = 'invited';

create table if not exists private.pachanga_referee_invitation_secrets (
  relationship_id uuid primary key references public.pachanga_club_referee_relationships(id) on delete cascade,
  token_hash text not null unique,
  target_email_normalized text,
  target_email_hash text,
  retention_until timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  consumed_at timestamptz,
  check (length(token_hash) = 64),
  check (target_email_hash is null or length(target_email_hash) = 64),
  check (
    (target_email_normalized is null and target_email_hash is null)
    or (target_email_normalized is not null and target_email_hash is not null)
  )
);

create table if not exists public.pachanga_referee_assignments (
  id uuid primary key,
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  assignment_role text not null default 'MAIN_REFEREE',
  requester_kind text not null,
  requester_team_id uuid references public.pachanga_groups(id) on delete restrict,
  requester_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  competition_id uuid references public.pachanga_competitions(id) on delete restrict,
  source_kind text not null,
  source_group_id uuid references public.pachanga_groups(id) on delete restrict,
  source_id text not null,
  status text not null default 'proposed',
  scheduled_start timestamptz not null,
  scheduled_end timestamptz not null,
  timezone text not null,
  schedule_source_revision bigint not null,
  proposed_by uuid not null references auth.users(id) on delete restrict,
  authority_used text not null,
  proposal_message text not null default '',
  response_deadline timestamptz not null,
  accepted_at timestamptz,
  declined_at timestamptz,
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancel_reason_code text,
  cancel_reason_text text,
  completed_at timestamptz,
  replaces_assignment_id uuid references public.pachanga_referee_assignments(id) on delete restrict,
  replacement_pending_assignment_id uuid references public.pachanga_referee_assignments(id) on delete restrict,
  replaced_by_assignment_id uuid references public.pachanga_referee_assignments(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (assignment_role in ('MAIN_REFEREE', 'ASSISTANT_REFEREE', 'TIMEKEEPER', 'TABLE_OFFICIAL')),
  check (requester_kind in ('TEAM', 'CLUB')),
  check ((requester_kind = 'TEAM') = (requester_team_id is not null)),
  check ((requester_kind = 'CLUB') = (requester_club_id is not null)),
  check (source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge')),
  check (length(trim(source_id)) between 1 and 240),
  check (status in ('proposed', 'accepted', 'confirmed', 'declined', 'cancelled', 'replaced', 'completed')),
  check (scheduled_start < scheduled_end),
  check (schedule_source_revision >= 0),
  check (length(timezone) between 3 and 80),
  check (length(authority_used) between 3 and 120),
  check (length(proposal_message) <= 800),
  check (response_deadline > created_at),
  check (length(coalesce(cancel_reason_code, '')) <= 80),
  check (length(coalesce(cancel_reason_text, '')) <= 800),
  check (revision >= 1)
);

create unique index if not exists pachanga_referee_assignment_active_slot_idx
  on public.pachanga_referee_assignments(canonical_match_id, assignment_role)
  where status in ('accepted', 'confirmed', 'completed');

create table if not exists public.pachanga_referee_statistics_snapshots (
  referee_profile_id uuid primary key references public.pachanga_referee_profiles(id) on delete restrict,
  proposals_received bigint not null default 0,
  assignments_accepted bigint not null default 0,
  assignments_declined bigint not null default 0,
  assignments_confirmed bigint not null default 0,
  matches_completed bigint not null default 0,
  individual_matches_completed bigint not null default 0,
  competition_matches_completed bigint not null default 0,
  active_club_relationships bigint not null default 0,
  last_completed_at timestamptz,
  discipline_stats_status text not null default 'NOT_AVAILABLE',
  yellow_cards_shown integer,
  red_cards_shown integer,
  blue_cards_shown integer,
  revision bigint not null default 1,
  checksum text not null,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (proposals_received >= 0 and assignments_accepted >= 0 and assignments_declined >= 0),
  check (assignments_confirmed >= 0 and matches_completed >= 0),
  check (individual_matches_completed >= 0 and competition_matches_completed >= 0),
  check (active_club_relationships >= 0),
  check (discipline_stats_status = 'NOT_AVAILABLE'),
  check (yellow_cards_shown is null and red_cards_shown is null and blue_cards_shown is null),
  check (revision >= 1 and length(checksum) = 64)
);

create table if not exists public.pachanga_referee_invalidations (
  id uuid primary key default gen_random_uuid(),
  server_sequence bigint not null,
  referee_profile_id uuid references public.pachanga_referee_profiles(id) on delete cascade,
  club_id uuid references public.pachanga_clubs(id) on delete cascade,
  target_user_id uuid references auth.users(id) on delete cascade,
  target_group_id uuid references public.pachanga_groups(id) on delete cascade,
  audience text not null default 'private',
  entity_type text not null,
  entity_id text not null,
  revision bigint not null check (revision >= 0),
  created_at timestamptz not null default clock_timestamp(),
  check (audience in ('private', 'marketplace'))
);

create index if not exists pachanga_referee_profiles_market_idx
  on public.pachanga_referee_profiles(
    operational_status, visibility, marketplace_status, available_for_assignments, updated_at desc, id
  );
create index if not exists pachanga_referee_modalities_search_idx
  on public.pachanga_referee_modalities(modality, referee_profile_id) where active;
create index if not exists pachanga_referee_areas_search_idx
  on public.pachanga_referee_service_areas(country_code, province, municipality, referee_profile_id) where status = 'active';
create index if not exists pachanga_referee_windows_profile_idx
  on public.pachanga_referee_availability_windows(referee_profile_id, status, weekday, start_local_time);
create index if not exists pachanga_referee_exceptions_profile_idx
  on public.pachanga_referee_availability_exceptions(referee_profile_id, status, unavailable_from, unavailable_until);
create index if not exists pachanga_club_referee_relationship_club_idx
  on public.pachanga_club_referee_relationships(club_id, status, server_sequence desc, id);
create index if not exists pachanga_club_referee_relationship_profile_idx
  on public.pachanga_club_referee_relationships(referee_profile_id, status, server_sequence desc, id)
  where referee_profile_id is not null;
create index if not exists pachanga_referee_assignments_profile_idx
  on public.pachanga_referee_assignments(referee_profile_id, status, scheduled_start desc, id);
create index if not exists pachanga_referee_assignments_match_idx
  on public.pachanga_referee_assignments(canonical_match_id, status, assignment_role, server_sequence desc, id);
create index if not exists pachanga_referee_assignments_overlap_idx
  on public.pachanga_referee_assignments(referee_profile_id, scheduled_start, scheduled_end)
  where status in ('accepted', 'confirmed');
create index if not exists pachanga_referee_invalidations_user_idx
  on public.pachanga_referee_invalidations(target_user_id, server_sequence desc, id)
  where target_user_id is not null;
create index if not exists pachanga_referee_invalidations_profile_idx
  on public.pachanga_referee_invalidations(referee_profile_id, server_sequence desc, id)
  where referee_profile_id is not null;
create index if not exists pachanga_referee_invalidations_club_idx
  on public.pachanga_referee_invalidations(club_id, server_sequence desc, id)
  where club_id is not null;

create or replace function private.pachanga_referee_touch_updated_at_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function private.pachanga_referee_touch_updated_at_v1()
  from public, anon, authenticated;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_referee_profiles', 'pachanga_referee_modalities', 'pachanga_referee_service_areas',
    'pachanga_referee_availability_windows', 'pachanga_referee_availability_exceptions',
    'pachanga_club_referee_relationships', 'pachanga_referee_assignments'
  ] loop
    execute format('drop trigger if exists pachanga_referee_touch_updated_at_v1 on public.%I', target_table);
    execute format(
      'create trigger pachanga_referee_touch_updated_at_v1 before update on public.%I for each row execute function private.pachanga_referee_touch_updated_at_v1()',
      target_table
    );
  end loop;
end;
$$;

create or replace function private.pachanga_referee_client_metadata_v1(source jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', nullif(left(coalesce(source ->> 'clientVersion', ''), 80), ''),
    'serviceWorkerVersion', nullif(left(coalesce(source ->> 'serviceWorkerVersion', ''), 80), ''),
    'installedMode', nullif(left(coalesce(source ->> 'installedMode', ''), 40), ''),
    'surface', nullif(left(coalesce(source ->> 'surface', ''), 100), '')
  ));
$$;

create or replace function private.pachanga_referee_request_hash_v1(
  target_action text,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(
    convert_to(jsonb_build_object(
      'action', target_action,
      'aggregateId', target_aggregate_id,
      'expectedRevision', target_expected_revision,
      'payload', coalesce(target_payload, '{}'::jsonb)
    )::text, 'UTF8'), 'sha256'
  ), 'hex');
$$;

create or replace function private.pachanga_referee_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare saved private.pachanga_referee_operation_receipts%rowtype;
begin
  select * into saved
  from private.pachanga_referee_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if saved.actor_id is distinct from target_actor_id or saved.request_hash <> target_request_hash then
    raise exception 'OPERATION_ID_REUSED' using errcode = 'PT409';
  end if;
  return saved.response;
end;
$$;

create or replace function private.pachanga_referee_flags_snapshot_v1()
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.referee_foundation_enabled,
    'selfServiceEnabled', settings.referee_self_service_enabled,
    'publicProfilesEnabled', settings.referee_public_profiles_enabled,
    'marketplaceEnabled', settings.referee_marketplace_enabled,
    'clubRelationshipsEnabled', settings.referee_club_relationships_enabled,
    'assignmentsEnabled', settings.referee_assignments_enabled,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_referee_foundation_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_referee_identity_snapshot_v1(target_user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'displayName', left(coalesce(
      nullif(trim(players.display_name), ''),
      nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(users.raw_user_meta_data ->> 'name'), ''),
      'Árbitro'
    ), 80),
    'avatar', nullif(left(coalesce(players.avatar, users.raw_user_meta_data ->> 'avatar_url', ''), 2000), '')
  )
  from auth.users users
  left join public.pachanga_player_profiles players on players.user_id = users.id
  where users.id = target_user_id;
$$;

create or replace function private.pachanga_referee_statistics_document_v1(target_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'proposalsReceived', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id),
    'assignmentsAccepted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.accepted_at is not null),
    'assignmentsDeclined', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.declined_at is not null),
    'assignmentsConfirmed', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.confirmed_at is not null),
    'matchesCompleted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed'),
    'individualMatchesCompleted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed' and a.competition_id is null),
    'competitionMatchesCompleted', (select count(*) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed' and a.competition_id is not null),
    'activeClubRelationships', (select count(*) from public.pachanga_club_referee_relationships r where r.referee_profile_id = target_profile_id and r.status = 'active'),
    'lastCompletedAt', (select max(a.completed_at) from public.pachanga_referee_assignments a where a.referee_profile_id = target_profile_id and a.status = 'completed'),
    'disciplineStatsStatus', 'NOT_AVAILABLE',
    'yellowCardsShown', null,
    'redCardsShown', null,
    'blueCardsShown', null
  );
$$;

create or replace function private.pachanga_referee_refresh_statistics_v1(
  target_profile_id uuid,
  refresh_mode text default 'incremental'
)
returns public.pachanga_referee_statistics_snapshots
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  document jsonb;
  digest_value text;
  sequence_value bigint := nextval('private.pachanga_referee_sequence');
  saved public.pachanga_referee_statistics_snapshots%rowtype;
begin
  if refresh_mode not in ('incremental', 'full_rebuild') then
    raise exception 'INVALID_STATS_REFRESH_MODE' using errcode = '22023';
  end if;
  if not exists (select 1 from public.pachanga_referee_profiles profiles where profiles.id = target_profile_id) then
    raise exception 'REFEREE_PROFILE_NOT_FOUND' using errcode = 'P0002';
  end if;
  document := private.pachanga_referee_statistics_document_v1(target_profile_id);
  digest_value := encode(extensions.digest(convert_to(document::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.pachanga_referee_statistics_snapshots(
    referee_profile_id, proposals_received, assignments_accepted, assignments_declined,
    assignments_confirmed, matches_completed, individual_matches_completed,
    competition_matches_completed, active_club_relationships, last_completed_at,
    discipline_stats_status, yellow_cards_shown, red_cards_shown, blue_cards_shown,
    revision, checksum, server_sequence, updated_at
  ) values (
    target_profile_id,
    (document ->> 'proposalsReceived')::bigint,
    (document ->> 'assignmentsAccepted')::bigint,
    (document ->> 'assignmentsDeclined')::bigint,
    (document ->> 'assignmentsConfirmed')::bigint,
    (document ->> 'matchesCompleted')::bigint,
    (document ->> 'individualMatchesCompleted')::bigint,
    (document ->> 'competitionMatchesCompleted')::bigint,
    (document ->> 'activeClubRelationships')::bigint,
    nullif(document ->> 'lastCompletedAt', '')::timestamptz,
    'NOT_AVAILABLE', null, null, null, 1, digest_value, sequence_value, clock_timestamp()
  )
  on conflict (referee_profile_id) do update set
    proposals_received = excluded.proposals_received,
    assignments_accepted = excluded.assignments_accepted,
    assignments_declined = excluded.assignments_declined,
    assignments_confirmed = excluded.assignments_confirmed,
    matches_completed = excluded.matches_completed,
    individual_matches_completed = excluded.individual_matches_completed,
    competition_matches_completed = excluded.competition_matches_completed,
    active_club_relationships = excluded.active_club_relationships,
    last_completed_at = excluded.last_completed_at,
    discipline_stats_status = 'NOT_AVAILABLE',
    yellow_cards_shown = null,
    red_cards_shown = null,
    blue_cards_shown = null,
    revision = public.pachanga_referee_statistics_snapshots.revision + 1,
    checksum = excluded.checksum,
    server_sequence = excluded.server_sequence,
    updated_at = excluded.updated_at
  returning * into saved;
  return saved;
end;
$$;

revoke all on function private.pachanga_referee_refresh_statistics_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_referee_public_snapshot_v1(target_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'slug', profiles.slug,
    'displayName', profiles.public_display_name_snapshot,
    'avatar', profiles.public_avatar_snapshot,
    'bio', profiles.bio,
    'experienceSinceYear', profiles.experience_since_year,
    'experienceSummary', profiles.experience_summary,
    'operationalStatus', profiles.operational_status,
    'verificationStatus', profiles.verification_status,
    'availabilityStatus', profiles.availability_status,
    'modalities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'modality', modalities.modality,
        'experienceSinceYear', modalities.experience_since_year,
        'note', modalities.public_note
      ) order by modalities.modality)
      from public.pachanga_referee_modalities modalities
      where modalities.referee_profile_id = profiles.id and modalities.active
    ), '[]'::jsonb),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'countryCode', areas.country_code,
        'province', areas.province,
        'municipality', areas.municipality,
        'generalArea', areas.general_area,
        'travelRadiusKm', areas.travel_radius_km
      ) order by areas.country_code, areas.province, areas.municipality, areas.general_area, areas.id)
      from public.pachanga_referee_service_areas areas
      where areas.referee_profile_id = profiles.id and areas.status = 'active'
    ), '[]'::jsonb),
    'availabilityWindows', case when profiles.share_recurring_availability then coalesce((
      select jsonb_agg(jsonb_build_object(
        'weekday', windows.weekday,
        'startLocalTime', windows.start_local_time,
        'endLocalTime', windows.end_local_time,
        'timezone', windows.timezone
      ) order by windows.weekday, windows.start_local_time, windows.id)
      from public.pachanga_referee_availability_windows windows
      where windows.referee_profile_id = profiles.id and windows.status = 'active' and windows.public_visible
    ), '[]'::jsonb) else '[]'::jsonb end,
    'clubs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', clubs.name,
        'slug', clubs.slug,
        'relationshipType', relationships.relationship_type,
        'verified', clubs.verification_status = 'verified'
      ) order by clubs.name, clubs.id)
      from public.pachanga_club_referee_relationships relationships
      join public.pachanga_clubs clubs on clubs.id = relationships.club_id
      where relationships.referee_profile_id = profiles.id
        and relationships.status = 'active'
        and relationships.show_on_referee_profile
        and clubs.operational_status = 'active'
        and clubs.visibility = 'public'
    ), '[]'::jsonb),
    'statistics', jsonb_build_object(
      'matchesCompleted', coalesce(stats.matches_completed, 0),
      'individualMatchesCompleted', coalesce(stats.individual_matches_completed, 0),
      'competitionMatchesCompleted', coalesce(stats.competition_matches_completed, 0),
      'disciplineStatsStatus', 'NOT_AVAILABLE',
      'yellowCardsShown', null,
      'redCardsShown', null,
      'blueCardsShown', null,
      'lastCompletedAt', stats.last_completed_at
    ),
    'revision', profiles.revision,
    'serverSequence', profiles.server_sequence,
    'updatedAt', profiles.updated_at
  )
  from public.pachanga_referee_profiles profiles
  left join public.pachanga_referee_statistics_snapshots stats on stats.referee_profile_id = profiles.id
  where profiles.id = target_profile_id;
$$;

create or replace function private.pachanga_referee_private_snapshot_v1(
  target_profile_id uuid,
  target_actor_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'profile', jsonb_build_object(
      'id', profiles.id,
      'slug', profiles.slug,
      'displayName', profiles.public_display_name_snapshot,
      'avatar', profiles.public_avatar_snapshot,
      'bio', profiles.bio,
      'experienceSinceYear', profiles.experience_since_year,
      'experienceSummary', profiles.experience_summary,
      'operationalStatus', profiles.operational_status,
      'verificationStatus', profiles.verification_status,
      'visibility', profiles.visibility,
      'marketplaceStatus', profiles.marketplace_status,
      'availabilityStatus', profiles.availability_status,
      'availableForAssignments', profiles.available_for_assignments,
      'shareRecurringAvailability', profiles.share_recurring_availability,
      'revision', profiles.revision,
      'serverSequence', profiles.server_sequence,
      'updatedAt', profiles.updated_at
    ),
    'modalities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'modality', m.modality, 'active', m.active,
        'experienceSinceYear', m.experience_since_year, 'note', m.public_note,
        'revision', m.revision, 'serverSequence', m.server_sequence
      ) order by m.modality, m.id)
      from public.pachanga_referee_modalities m where m.referee_profile_id = profiles.id
    ), '[]'::jsonb),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id, 'countryCode', a.country_code, 'province', a.province,
        'municipality', a.municipality, 'generalArea', a.general_area,
        'travelRadiusKm', a.travel_radius_km, 'status', a.status,
        'revision', a.revision, 'serverSequence', a.server_sequence
      ) order by a.status, a.country_code, a.province, a.municipality, a.id)
      from public.pachanga_referee_service_areas a where a.referee_profile_id = profiles.id
    ), '[]'::jsonb),
    'availabilityWindows', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', w.id, 'weekday', w.weekday, 'startLocalTime', w.start_local_time,
        'endLocalTime', w.end_local_time, 'timezone', w.timezone,
        'publicVisible', w.public_visible, 'status', w.status,
        'revision', w.revision, 'serverSequence', w.server_sequence
      ) order by w.status, w.weekday, w.start_local_time, w.id)
      from public.pachanga_referee_availability_windows w where w.referee_profile_id = profiles.id
    ), '[]'::jsonb),
    'availabilityExceptions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'unavailableFrom', e.unavailable_from,
        'unavailableUntil', e.unavailable_until, 'reason', e.private_reason,
        'status', e.status, 'revision', e.revision, 'serverSequence', e.server_sequence
      ) order by e.unavailable_from, e.id)
      from public.pachanga_referee_availability_exceptions e where e.referee_profile_id = profiles.id
    ), '[]'::jsonb),
    'relationships', coalesce((
      select jsonb_agg(rows.document order by rows.server_sequence desc, rows.id desc)
      from (
        select r.id, r.server_sequence, jsonb_build_object(
          'id', r.id, 'clubId', r.club_id, 'clubName', clubs.name,
          'relationshipType', r.relationship_type, 'initiatedBy', r.initiated_by,
          'status', r.status, 'showOnRefereeProfile', r.show_on_referee_profile,
          'showOnClubProfile', r.show_on_club_profile, 'startedAt', r.started_at,
          'endedAt', r.ended_at, 'revision', r.revision, 'serverSequence', r.server_sequence
        ) as document
        from public.pachanga_club_referee_relationships r
        join public.pachanga_clubs clubs on clubs.id = r.club_id
        where r.referee_profile_id = profiles.id or r.target_user_id = target_actor_id
        order by r.server_sequence desc, r.id desc
        limit 200
      ) rows
    ), '[]'::jsonb),
    'assignments', coalesce((
      select jsonb_agg(rows.document order by rows.scheduled_start desc, rows.server_sequence desc, rows.id desc)
      from (
        select a.id, a.scheduled_start, a.server_sequence, jsonb_build_object(
          'id', a.id, 'canonicalMatchId', a.canonical_match_id,
          'assignmentRole', a.assignment_role, 'requesterKind', a.requester_kind,
          'requesterTeamId', a.requester_team_id, 'requesterClubId', a.requester_club_id,
          'competitionId', a.competition_id, 'sourceKind', a.source_kind,
          'sourceGroupId', a.source_group_id, 'sourceId', a.source_id,
          'status', a.status, 'scheduledStart', a.scheduled_start,
          'scheduledEnd', a.scheduled_end, 'timezone', a.timezone,
          'scheduleSourceRevision', a.schedule_source_revision,
          'responseDeadline', a.response_deadline, 'acceptedAt', a.accepted_at,
          'confirmedAt', a.confirmed_at, 'cancelledAt', a.cancelled_at,
          'completedAt', a.completed_at, 'replacesAssignmentId', a.replaces_assignment_id,
          'replacedByAssignmentId', a.replaced_by_assignment_id,
          'revision', a.revision, 'serverSequence', a.server_sequence
        ) as document
        from public.pachanga_referee_assignments a
        where a.referee_profile_id = profiles.id
        order by a.scheduled_start desc, a.server_sequence desc, a.id desc
        limit 200
      ) rows
    ), '[]'::jsonb),
    'statistics', coalesce((
      select jsonb_build_object(
        'proposalsReceived', s.proposals_received,
        'assignmentsAccepted', s.assignments_accepted,
        'assignmentsDeclined', s.assignments_declined,
        'assignmentsConfirmed', s.assignments_confirmed,
        'matchesCompleted', s.matches_completed,
        'individualMatchesCompleted', s.individual_matches_completed,
        'competitionMatchesCompleted', s.competition_matches_completed,
        'activeClubRelationships', s.active_club_relationships,
        'lastCompletedAt', s.last_completed_at,
        'disciplineStatsStatus', s.discipline_stats_status,
        'yellowCardsShown', s.yellow_cards_shown,
        'redCardsShown', s.red_cards_shown,
        'blueCardsShown', s.blue_cards_shown,
        'revision', s.revision, 'checksum', s.checksum,
        'serverSequence', s.server_sequence, 'updatedAt', s.updated_at
      ) from public.pachanga_referee_statistics_snapshots s where s.referee_profile_id = profiles.id
    ), jsonb_build_object(
      'proposalsReceived', 0, 'assignmentsAccepted', 0, 'assignmentsDeclined', 0,
      'assignmentsConfirmed', 0, 'matchesCompleted', 0,
      'individualMatchesCompleted', 0, 'competitionMatchesCompleted', 0,
      'activeClubRelationships', 0, 'disciplineStatsStatus', 'NOT_AVAILABLE',
      'yellowCardsShown', null, 'redCardsShown', null, 'blueCardsShown', null
    ))
  )
  from public.pachanga_referee_profiles profiles
  where profiles.id = target_profile_id and profiles.user_id = target_actor_id;
$$;

create or replace function public.get_pachanga_referee_foundation_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$ select private.pachanga_referee_flags_snapshot_v1(); $$;

create or replace function public.get_my_pachanga_referee_platform_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  profile_id uuid;
  actor_email text;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select profiles.id into profile_id
  from public.pachanga_referee_profiles profiles where profiles.user_id = actor_id;
  select lower(users.email) into actor_email from auth.users users where users.id = actor_id;
  return jsonb_build_object(
    'flags', private.pachanga_referee_flags_snapshot_v1(),
    'profile', case when profile_id is null then null else private.pachanga_referee_private_snapshot_v1(profile_id, actor_id) end,
    'pendingInvitations', coalesce((
      select jsonb_agg(rows.document order by rows.server_sequence desc, rows.id desc)
      from (
        select relationships.id, relationships.server_sequence, jsonb_build_object(
          'id', relationships.id,
          'clubId', relationships.club_id,
          'clubName', clubs.name,
          'relationshipType', relationships.relationship_type,
          'targetKind', relationships.target_kind,
          'status', relationships.status,
          'expiresAt', relationships.expires_at,
          'revision', relationships.revision,
          'serverSequence', relationships.server_sequence
        ) as document
        from public.pachanga_club_referee_relationships relationships
        join public.pachanga_clubs clubs on clubs.id = relationships.club_id
        left join private.pachanga_referee_invitation_secrets secrets on secrets.relationship_id = relationships.id
        where relationships.status = 'invited'
          and (
            relationships.target_user_id = actor_id
            or (relationships.target_kind = 'email_target' and secrets.target_email_normalized = actor_email)
          )
        order by relationships.server_sequence desc, relationships.id desc
        limit 100
      ) rows
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pachanga_public_referee_v1(target_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare profile_id uuid;
begin
  if not coalesce((select settings.referee_foundation_enabled and settings.referee_public_profiles_enabled
                   from private.pachanga_referee_foundation_settings settings where settings.singleton), false) then
    return null;
  end if;
  select profiles.id into profile_id
  from public.pachanga_referee_profiles profiles
  where profiles.slug = lower(trim(target_slug))
    and profiles.operational_status = 'active'
    and profiles.visibility = 'public';
  if profile_id is null then return null; end if;
  return private.pachanga_referee_public_snapshot_v1(profile_id);
end;
$$;

create or replace function public.search_pachanga_referee_market_v1(
  target_filters jsonb default '{}'::jsonb,
  target_page integer default 1,
  target_page_size integer default 24
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  safe_page integer := greatest(1, coalesce(target_page, 1));
  safe_page_size integer := least(60, greatest(1, coalesce(target_page_size, 24)));
  safe_filters jsonb := case when jsonb_typeof(target_filters) = 'object' then target_filters else '{}'::jsonb end;
  result jsonb;
begin
  if not coalesce((select settings.referee_foundation_enabled
                          and settings.referee_public_profiles_enabled
                          and settings.referee_marketplace_enabled
                   from private.pachanga_referee_foundation_settings settings where settings.singleton), false) then
    return jsonb_build_object('items', '[]'::jsonb, 'page', safe_page, 'pageSize', safe_page_size, 'total', 0);
  end if;
  with eligible as materialized (
    select profiles.id,
      (case when nullif(trim(safe_filters ->> 'zone'), '') is not null and exists (
        select 1 from public.pachanga_referee_service_areas areas
        where areas.referee_profile_id = profiles.id and areas.status = 'active'
          and concat_ws(' ', areas.province, areas.municipality, areas.general_area) ilike '%' || trim(safe_filters ->> 'zone') || '%'
      ) then 4 else 0 end
      + case when nullif(trim(safe_filters ->> 'modality'), '') is not null and exists (
        select 1 from public.pachanga_referee_modalities modalities
        where modalities.referee_profile_id = profiles.id and modalities.active
          and modalities.modality = upper(trim(safe_filters ->> 'modality'))
      ) then 3 else 0 end
      + case when nullif(trim(safe_filters ->> 'weekday'), '') is not null and exists (
        select 1 from public.pachanga_referee_availability_windows windows
        where windows.referee_profile_id = profiles.id and windows.status = 'active'
          and windows.weekday = (safe_filters ->> 'weekday')::smallint
      ) then 2 else 0 end
      + case when profiles.verification_status = 'verified' then 1 else 0 end) as relevance
    from public.pachanga_referee_profiles profiles
    where profiles.operational_status = 'active'
      and profiles.visibility = 'public'
      and profiles.marketplace_status = 'listed'
      and profiles.available_for_assignments
      and (nullif(trim(safe_filters ->> 'availabilityStatus'), '') is null
           or profiles.availability_status = upper(trim(safe_filters ->> 'availabilityStatus')))
      and (nullif(trim(safe_filters ->> 'verified'), '') is null
           or (profiles.verification_status = 'verified') = (safe_filters ->> 'verified')::boolean)
      and (nullif(trim(safe_filters ->> 'minExperienceYear'), '') is null
           or profiles.experience_since_year <= (safe_filters ->> 'minExperienceYear')::integer)
      and (nullif(trim(safe_filters ->> 'zone'), '') is null or exists (
        select 1 from public.pachanga_referee_service_areas areas
        where areas.referee_profile_id = profiles.id and areas.status = 'active'
          and concat_ws(' ', areas.province, areas.municipality, areas.general_area) ilike '%' || trim(safe_filters ->> 'zone') || '%'
      ))
      and (nullif(trim(safe_filters ->> 'province'), '') is null or exists (
        select 1 from public.pachanga_referee_service_areas areas
        where areas.referee_profile_id = profiles.id and areas.status = 'active'
          and areas.province ilike trim(safe_filters ->> 'province')
      ))
      and (nullif(trim(safe_filters ->> 'municipality'), '') is null or exists (
        select 1 from public.pachanga_referee_service_areas areas
        where areas.referee_profile_id = profiles.id and areas.status = 'active'
          and areas.municipality ilike trim(safe_filters ->> 'municipality')
      ))
      and (nullif(trim(safe_filters ->> 'modality'), '') is null or exists (
        select 1 from public.pachanga_referee_modalities modalities
        where modalities.referee_profile_id = profiles.id and modalities.active
          and modalities.modality = upper(trim(safe_filters ->> 'modality'))
      ))
      and (nullif(trim(safe_filters ->> 'weekday'), '') is null or exists (
        select 1 from public.pachanga_referee_availability_windows windows
        where windows.referee_profile_id = profiles.id and windows.status = 'active'
          and windows.weekday = (safe_filters ->> 'weekday')::smallint
          and (nullif(trim(safe_filters ->> 'startTime'), '') is null or windows.end_local_time > (safe_filters ->> 'startTime')::time)
          and (nullif(trim(safe_filters ->> 'endTime'), '') is null or windows.start_local_time < (safe_filters ->> 'endTime')::time)
      ))
      and (nullif(trim(safe_filters ->> 'clubId'), '') is null or exists (
        select 1 from public.pachanga_club_referee_relationships relationships
        where relationships.referee_profile_id = profiles.id and relationships.status = 'active'
          and relationships.club_id = (safe_filters ->> 'clubId')::uuid
      ))
  ), paged as (
    select eligible.id, eligible.relevance
    from eligible
    join public.pachanga_referee_profiles profiles on profiles.id = eligible.id
    order by eligible.relevance desc, profiles.updated_at desc, profiles.id
    limit safe_page_size offset (safe_page - 1) * safe_page_size
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(
      private.pachanga_referee_public_snapshot_v1(paged.id)
      || jsonb_build_object('refereeProfileId', paged.id, 'relevance', paged.relevance)
      order by paged.relevance desc, profiles.updated_at desc, profiles.id
    ), '[]'::jsonb),
    'page', safe_page,
    'pageSize', safe_page_size,
    'total', (select count(*) from eligible),
    'ordering', 'filter_relevance_then_recent_activity'
  ) into result
  from paged join public.pachanga_referee_profiles profiles on profiles.id = paged.id;
  return result;
end;
$$;

create or replace function private.pachanga_referee_immutable_ledger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'REFEREE_LEDGER_IMMUTABLE' using errcode = '42501';
end;
$$;

drop trigger if exists pachanga_referee_receipts_immutable_v1 on private.pachanga_referee_operation_receipts;
create trigger pachanga_referee_receipts_immutable_v1
before update or delete on private.pachanga_referee_operation_receipts
for each row execute function private.pachanga_referee_immutable_ledger_v1();
drop trigger if exists pachanga_referee_events_immutable_v1 on private.pachanga_referee_events;
create trigger pachanga_referee_events_immutable_v1
before update or delete on private.pachanga_referee_events
for each row execute function private.pachanga_referee_immutable_ledger_v1();

create or replace function private.pachanga_referee_can_read_invalidation_v1(
  target_profile_id uuid,
  target_club_id uuid,
  target_user_id uuid,
  target_group_id uuid,
  target_audience text,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select actor_id is not null and (
    target_user_id = actor_id
    or exists (select 1 from public.pachanga_referee_profiles p where p.id = target_profile_id and p.user_id = actor_id)
    or (target_club_id is not null and private.pachanga_club_can_v1(target_club_id, actor_id, 'read'))
    or exists (select 1 from public.pachanga_groups g where g.id = target_group_id and g.owner_id = actor_id)
    or (target_audience = 'marketplace' and coalesce((
      select s.referee_marketplace_enabled from private.pachanga_referee_foundation_settings s where s.singleton
    ), false))
  );
$$;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_referee_profiles', 'pachanga_referee_modalities', 'pachanga_referee_service_areas',
    'pachanga_referee_availability_windows', 'pachanga_referee_availability_exceptions',
    'pachanga_club_referee_relationships', 'pachanga_referee_assignments',
    'pachanga_referee_statistics_snapshots', 'pachanga_referee_invalidations'
  ] loop
    execute format('alter table public.%I enable row level security', target_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', target_table);
    execute format('grant all on table public.%I to service_role', target_table);
  end loop;
end;
$$;

grant select on table public.pachanga_referee_invalidations to authenticated;
create policy pachanga_referee_invalidations_select_v1
on public.pachanga_referee_invalidations
for select to authenticated
using (private.pachanga_referee_can_read_invalidation_v1(
  referee_profile_id, club_id, target_user_id, target_group_id, audience, (select auth.uid())
));

-- Realtime evaluates this policy as the authenticated subscriber. Keep the
-- helper outside exposed schemas while allowing the policy engine to execute it.
revoke all on function private.pachanga_referee_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.pachanga_referee_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, text, uuid
) to authenticated;

revoke all on function public.get_pachanga_referee_foundation_flags_v1() from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_referee_foundation_flags_v1() to anon, authenticated, service_role;
revoke all on function public.get_my_pachanga_referee_platform_v1() from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_referee_platform_v1() to authenticated, service_role;
revoke all on function public.get_pachanga_public_referee_v1(text) from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_public_referee_v1(text) to anon, authenticated, service_role;
revoke all on function public.search_pachanga_referee_market_v1(jsonb, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.search_pachanga_referee_market_v1(jsonb, integer, integer) to authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'pachanga_referee_invalidations'
     ) then
    alter publication supabase_realtime add table public.pachanga_referee_invalidations;
  end if;
end;
$$;

comment on table public.pachanga_referee_profiles is
  'R3 referee facet for one universal user. It is independent from PlayerProfile and contains no referee rating.';
comment on table public.pachanga_referee_statistics_snapshots is
  'Rebuildable assignment statistics. Discipline values remain NOT_AVAILABLE/null until a future canonical discipline engine.';
comment on table public.pachanga_referee_invalidations is
  'RLS-scoped Realtime invalidations; clients refetch canonical read models instead of applying WAL as truth.';
