-- Pachangas IQ Club Foundation R2.
-- Product flags default OFF. Clubs are independent authorities from teams.

create sequence if not exists private.pachanga_club_sequence;
revoke all on sequence private.pachanga_club_sequence from public, anon, authenticated;

create table if not exists private.pachanga_club_foundation_settings (
  singleton boolean primary key default true check (singleton),
  club_foundation_enabled boolean not null default false,
  club_self_service_creation_enabled boolean not null default false,
  club_team_relationships_enabled boolean not null default false,
  club_public_profiles_enabled boolean not null default false,
  club_competition_organizer_enabled boolean not null default false,
  revision bigint not null default 1 check (revision >= 1),
  server_sequence bigint not null default nextval('private.pachanga_club_sequence'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (not club_self_service_creation_enabled or club_foundation_enabled),
  check (not club_team_relationships_enabled or club_foundation_enabled),
  check (not club_public_profiles_enabled or club_foundation_enabled),
  check (not club_competition_organizer_enabled or club_foundation_enabled)
);

insert into private.pachanga_club_foundation_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists private.pachanga_club_operation_receipts (
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

create table if not exists private.pachanga_club_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null default 'authenticated',
  aggregate_type text not null,
  aggregate_id text not null,
  club_id uuid,
  action text not null,
  aggregate_revision bigint not null check (aggregate_revision >= 0),
  server_sequence bigint not null unique,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb check (jsonb_typeof(event_payload) = 'object'),
  confirmed_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'service_authority'))
);

create table if not exists public.pachanga_clubs (
  id uuid primary key,
  name text not null,
  slug text not null unique,
  description text not null default '',
  club_type text not null,
  country_code text not null default 'ES',
  province text not null default '',
  municipality text not null default '',
  general_area text not null default '',
  place_id text,
  website_url text,
  logo_asset text,
  visibility text not null default 'private',
  operational_status text not null default 'draft',
  verification_status text not null default 'unverified',
  partnership_status text not null default 'none',
  primary_owner_id uuid not null references auth.users(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_club_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (club_type in ('FOOTBALL_CLUB', 'SPORTS_CENTER', 'ASSOCIATION', 'INDEPENDENT_ORGANIZER', 'OTHER')),
  check (visibility in ('private', 'unlisted', 'public')),
  check (operational_status in ('draft', 'pending_review', 'active', 'suspended', 'rejected', 'archived')),
  check (verification_status in ('unverified', 'pending', 'verified', 'rejected', 'revoked')),
  check (partnership_status in ('none', 'candidate', 'active', 'paused', 'ended')),
  check (revision >= 1),
  check (length(trim(name)) between 3 and 120),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 3 and 80),
  check (length(description) <= 2000),
  check (country_code ~ '^[A-Z]{2}$'),
  check (length(province) <= 120 and length(municipality) <= 120 and length(general_area) <= 160),
  check (place_id is null or length(place_id) <= 240),
  check (website_url is null or length(website_url) <= 500),
  check (logo_asset is null or length(logo_asset) <= 500)
);

alter table private.pachanga_club_events
  add constraint pachanga_club_events_club_id_fkey
  foreign key (club_id) references public.pachanga_clubs(id) on delete restrict;

create table if not exists public.pachanga_club_memberships (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.pachanga_clubs(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role text not null,
  status text not null default 'invited',
  valid_from timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_club_sequence'),
  invited_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (role in (
    'club_owner', 'club_admin', 'club_competition_manager', 'club_viewer',
    'club_venue_manager', 'club_referee_manager', 'club_finance_manager'
  )),
  check (status in ('invited', 'active', 'declined', 'revoked', 'expired')),
  check (revision >= 1),
  check (expires_at is null or expires_at > valid_from),
  check (
    (status = 'active' and accepted_at is not null and revoked_at is null)
    or (status = 'invited' and accepted_at is null and revoked_at is null)
    or (status in ('declined', 'revoked', 'expired') and revoked_at is not null)
  )
);

create unique index if not exists pachanga_club_memberships_current_idx
  on public.pachanga_club_memberships(club_id, user_id)
  where status in ('invited', 'active');
create index if not exists pachanga_club_memberships_user_idx
  on public.pachanga_club_memberships(user_id, status, club_id, server_sequence desc);
create index if not exists pachanga_club_memberships_club_idx
  on public.pachanga_club_memberships(club_id, status, role, server_sequence desc);

create table if not exists public.pachanga_club_invitations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.pachanga_clubs(id) on delete restrict,
  membership_id uuid references public.pachanga_club_memberships(id) on delete restrict,
  target_kind text not null,
  target_user_id uuid references auth.users(id) on delete restrict,
  role text not null,
  status text not null default 'pending',
  expires_at timestamptz not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_club_sequence'),
  invited_by uuid not null references auth.users(id) on delete restrict,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (target_kind in ('registered_user', 'email_target')),
  check (role in ('club_owner', 'club_admin', 'club_competition_manager', 'club_viewer')),
  check (status in ('pending', 'accepted', 'declined', 'revoked', 'expired')),
  check (revision >= 1),
  check (expires_at > created_at),
  check (
    (target_kind = 'registered_user' and target_user_id is not null)
    or (target_kind = 'email_target' and target_user_id is null)
  ),
  check (
    (status = 'accepted' and accepted_by is not null and accepted_at is not null)
    or (status = 'pending' and accepted_by is null and accepted_at is null and revoked_at is null)
    or (status in ('declined', 'revoked', 'expired') and revoked_at is not null)
  )
);

create unique index if not exists pachanga_club_invitation_registered_pending_idx
  on public.pachanga_club_invitations(club_id, target_user_id)
  where status = 'pending' and target_kind = 'registered_user';
create index if not exists pachanga_club_invitations_club_idx
  on public.pachanga_club_invitations(club_id, status, server_sequence desc, id);
create index if not exists pachanga_club_invitations_user_idx
  on public.pachanga_club_invitations(target_user_id, status, server_sequence desc, id)
  where target_user_id is not null;

create table if not exists private.pachanga_club_invitation_secrets (
  invitation_id uuid primary key references public.pachanga_club_invitations(id) on delete cascade,
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

create table if not exists public.pachanga_club_team_relationships (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.pachanga_clubs(id) on delete restrict,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  relationship_type text not null,
  initiated_by text not null,
  status text not null,
  show_on_club_profile boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_club_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  responded_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  ended_at timestamptz,
  ended_by uuid references auth.users(id) on delete set null,
  reason text not null default '',
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (relationship_type in ('MEMBER', 'AFFILIATED', 'HOSTED')),
  check (initiated_by in ('CLUB', 'TEAM')),
  check (status in ('invited', 'requested', 'active', 'rejected', 'cancelled', 'ended')),
  check (revision >= 1),
  check (length(reason) <= 1200),
  check (
    (status = 'active' and started_at is not null and ended_at is null)
    or (status in ('invited', 'requested') and started_at is null and ended_at is null)
    or (status in ('rejected', 'cancelled', 'ended') and ended_at is not null)
  )
);

create unique index if not exists pachanga_club_team_relationship_current_idx
  on public.pachanga_club_team_relationships(club_id, group_id)
  where status in ('invited', 'requested', 'active');
create index if not exists pachanga_club_team_relationship_club_idx
  on public.pachanga_club_team_relationships(club_id, status, server_sequence desc, id);
create index if not exists pachanga_club_team_relationship_group_idx
  on public.pachanga_club_team_relationships(group_id, status, server_sequence desc, id);

create table if not exists public.pachanga_club_invalidations (
  server_sequence bigint primary key,
  club_id uuid not null references public.pachanga_clubs(id) on delete cascade,
  target_user_id uuid references auth.users(id) on delete cascade,
  target_group_id uuid references public.pachanga_groups(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  revision bigint not null check (revision >= 0),
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists pachanga_club_invalidations_club_idx
  on public.pachanga_club_invalidations(club_id, server_sequence desc);
create index if not exists pachanga_club_invalidations_user_idx
  on public.pachanga_club_invalidations(target_user_id, server_sequence desc)
  where target_user_id is not null;
create index if not exists pachanga_club_invalidations_group_idx
  on public.pachanga_club_invalidations(target_group_id, server_sequence desc)
  where target_group_id is not null;

create index if not exists pachanga_clubs_status_idx
  on public.pachanga_clubs(operational_status, visibility, updated_at desc, id);
create index if not exists pachanga_clubs_location_idx
  on public.pachanga_clubs(country_code, province, municipality, id);

create or replace function private.pachanga_club_touch_updated_at_v1()
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

revoke all on function private.pachanga_club_touch_updated_at_v1()
  from public, anon, authenticated;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_clubs', 'pachanga_club_memberships', 'pachanga_club_invitations',
    'pachanga_club_team_relationships'
  ] loop
    execute format('drop trigger if exists pachanga_club_touch_updated_at_v1 on public.%I', target_table);
    execute format(
      'create trigger pachanga_club_touch_updated_at_v1 before update on public.%I for each row execute function private.pachanga_club_touch_updated_at_v1()',
      target_table
    );
  end loop;
end;
$$;

create or replace function private.pachanga_club_client_metadata_v1(source jsonb)
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

create or replace function private.pachanga_club_request_hash_v1(
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
  select encode(extensions.digest(convert_to(
    coalesce(target_action, '') || '|' || coalesce(target_aggregate_id::text, '') || '|'
    || coalesce(target_expected_revision::text, '') || '|' || coalesce(target_payload, '{}'::jsonb)::text,
    'UTF8'
  ), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_club_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare stored private.pachanga_club_operation_receipts%rowtype;
begin
  select * into stored
  from private.pachanga_club_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if stored.actor_id is distinct from target_actor_id
     or stored.actor_kind <> target_actor_kind
     or stored.action <> target_action
     or stored.aggregate_id <> target_aggregate_id::text
     or stored.request_hash <> target_request_hash then
    raise exception 'OPERATION_ID_REUSED' using errcode = 'PT409';
  end if;
  return stored.response;
end;
$$;

create or replace function private.pachanga_club_platform_can_v1(target_user_id uuid, target_capability text)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    private.pachanga_platform_capabilities_v1(
      private.pachanga_platform_role_for_user_v1(target_user_id)
    ) ? target_capability,
    false
  );
$$;

create or replace function private.pachanga_club_active_role_v1(target_club_id uuid, target_user_id uuid)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select memberships.role
  from public.pachanga_club_memberships memberships
  where memberships.club_id = target_club_id
    and memberships.user_id = target_user_id
    and memberships.status = 'active'
    and memberships.valid_from <= clock_timestamp()
    and (memberships.expires_at is null or memberships.expires_at > clock_timestamp())
  order by memberships.server_sequence desc, memberships.id desc
  limit 1;
$$;

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
  if target_capability = 'read'
     and private.pachanga_club_platform_can_v1(target_user_id, 'clubs.read') then return true; end if;
  selected_role := private.pachanga_club_active_role_v1(target_club_id, target_user_id);
  return case selected_role
    when 'club_owner' then target_capability in (
      'read', 'profile_manage', 'staff_manage', 'staff_manage_non_owner',
      'team_links_manage', 'competition_create', 'competition_manage', 'ownership_manage'
    )
    when 'club_admin' then target_capability in (
      'read', 'profile_manage', 'staff_manage_non_owner', 'team_links_manage'
    )
    when 'club_competition_manager' then target_capability in (
      'read', 'competition_create', 'competition_manage'
    )
    when 'club_viewer' then target_capability = 'read'
    else false
  end;
end;
$$;

create or replace function private.pachanga_club_require_v1(
  target_club_id uuid,
  target_user_id uuid,
  target_capability text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not private.pachanga_club_can_v1(target_club_id, target_user_id, target_capability) then
    raise exception 'CLUB_CAPABILITY_REQUIRED' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.pachanga_club_assert_flags_v1(
  require_creation boolean default false,
  require_relationships boolean default false
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_club_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_club_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.club_foundation_enabled then
    raise exception 'CLUB_FOUNDATION_DISABLED' using errcode = '0A000';
  end if;
  if require_creation and not settings.club_self_service_creation_enabled then
    raise exception 'CLUB_CREATION_DISABLED' using errcode = '0A000';
  end if;
  if require_relationships and not settings.club_team_relationships_enabled then
    raise exception 'CLUB_TEAM_RELATIONSHIPS_DISABLED' using errcode = '0A000';
  end if;
end;
$$;

create or replace function private.pachanga_club_flags_snapshot_v1()
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.club_foundation_enabled,
    'selfServiceCreationEnabled', settings.club_self_service_creation_enabled,
    'teamRelationshipsEnabled', settings.club_team_relationships_enabled,
    'publicProfilesEnabled', settings.club_public_profiles_enabled,
    'competitionOrganizerEnabled', settings.club_competition_organizer_enabled,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_club_foundation_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_public_club_snapshot_v1(target_club_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'name', clubs.name,
    'slug', clubs.slug,
    'logoAsset', clubs.logo_asset,
    'description', clubs.description,
    'clubType', clubs.club_type,
    'generalArea', jsonb_build_object(
      'countryCode', clubs.country_code,
      'province', clubs.province,
      'municipality', clubs.municipality,
      'area', clubs.general_area
    ),
    'verified', clubs.verification_status = 'verified',
    'partner', clubs.partnership_status = 'active',
    'teams', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', visible_teams.name,
        'relationshipType', visible_teams.relationship_type
      ) order by visible_teams.name, visible_teams.id)
      from (
        select relationships.id, groups.name, relationships.relationship_type
        from public.pachanga_club_team_relationships relationships
        join public.pachanga_groups groups on groups.id = relationships.group_id
        where relationships.club_id = clubs.id
          and relationships.status = 'active'
          and relationships.show_on_club_profile
        order by groups.name, relationships.id
        limit 100
      ) visible_teams
    ), '[]'::jsonb),
    'revision', clubs.revision,
    'serverSequence', clubs.server_sequence,
    'updatedAt', clubs.updated_at
  )
  from public.pachanga_clubs clubs
  join private.pachanga_club_foundation_settings settings on settings.singleton
  where clubs.id = target_club_id
    and settings.club_foundation_enabled
    and settings.club_public_profiles_enabled
    and clubs.operational_status = 'active'
    and clubs.visibility = 'public';
$$;

create or replace function private.pachanga_club_snapshot_v1(target_club_id uuid, target_actor_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  selected_club public.pachanga_clubs%rowtype;
  can_read boolean;
  can_manage_staff boolean;
  can_manage_links boolean;
  actor_team_owner boolean;
begin
  select * into selected_club from public.pachanga_clubs clubs where clubs.id = target_club_id;
  if not found then return null; end if;
  can_read := private.pachanga_club_can_v1(target_club_id, target_actor_id, 'read');
  actor_team_owner := exists (
    select 1
    from public.pachanga_club_team_relationships relationships
    join public.pachanga_groups groups on groups.id = relationships.group_id
    where relationships.club_id = target_club_id and groups.owner_id = target_actor_id
  );
  if not can_read and not actor_team_owner then return null; end if;
  can_manage_staff := private.pachanga_club_can_v1(target_club_id, target_actor_id, 'staff_manage_non_owner');
  can_manage_links := private.pachanga_club_can_v1(target_club_id, target_actor_id, 'team_links_manage');

  return jsonb_build_object(
    'club', jsonb_build_object(
      'id', selected_club.id,
      'name', selected_club.name,
      'slug', selected_club.slug,
      'description', case when can_read then selected_club.description else null end,
      'clubType', selected_club.club_type,
      'countryCode', case when can_read then selected_club.country_code else null end,
      'province', case when can_read then selected_club.province else null end,
      'municipality', case when can_read then selected_club.municipality else null end,
      'generalArea', case when can_read then selected_club.general_area else null end,
      'placeId', case when can_read then selected_club.place_id else null end,
      'websiteUrl', case when can_read then selected_club.website_url else null end,
      'logoAsset', case when can_read then selected_club.logo_asset else null end,
      'visibility', case when can_read then selected_club.visibility else null end,
      'operationalStatus', selected_club.operational_status,
      'verificationStatus', case when can_read then selected_club.verification_status else null end,
      'partnershipStatus', case when can_read then selected_club.partnership_status else null end,
      'primaryOwnerId', case when can_read then selected_club.primary_owner_id else null end,
      'revision', selected_club.revision,
      'serverSequence', selected_club.server_sequence,
      'createdAt', selected_club.created_at,
      'updatedAt', selected_club.updated_at
    ),
    'capabilities', jsonb_build_object(
      'read', can_read,
      'profileManage', private.pachanga_club_can_v1(target_club_id, target_actor_id, 'profile_manage'),
      'staffManage', can_manage_staff,
      'teamLinksManage', can_manage_links,
      'competitionCreate', private.pachanga_club_can_v1(target_club_id, target_actor_id, 'competition_create'),
      'ownershipManage', private.pachanga_club_can_v1(target_club_id, target_actor_id, 'ownership_manage')
    ),
    'memberships', case when can_read then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', memberships.id,
        'userId', memberships.user_id,
        'role', memberships.role,
        'status', memberships.status,
        'validFrom', memberships.valid_from,
        'expiresAt', memberships.expires_at,
        'revision', memberships.revision,
        'serverSequence', memberships.server_sequence,
        'acceptedAt', memberships.accepted_at,
        'revokedAt', memberships.revoked_at
      ) order by memberships.status, memberships.role, memberships.server_sequence, memberships.id)
      from (
        select rows.*
        from public.pachanga_club_memberships rows
        where rows.club_id = target_club_id
        order by rows.status, rows.role, rows.server_sequence, rows.id
        limit 200
      ) memberships
    ), '[]'::jsonb) else '[]'::jsonb end,
    'pendingInvitations', case when can_manage_staff then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', invitations.id,
        'targetKind', invitations.target_kind,
        'targetUserId', invitations.target_user_id,
        'role', invitations.role,
        'status', invitations.status,
        'expiresAt', invitations.expires_at,
        'revision', invitations.revision,
        'serverSequence', invitations.server_sequence
      ) order by invitations.server_sequence desc, invitations.id)
      from (
        select rows.*
        from public.pachanga_club_invitations rows
        where rows.club_id = target_club_id and rows.status = 'pending'
        order by rows.server_sequence desc, rows.id
        limit 200
      ) invitations
    ), '[]'::jsonb) else '[]'::jsonb end,
    'teamRelationships', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', relationships.id,
        'groupId', relationships.group_id,
        'teamName', groups.name,
        'relationshipType', relationships.relationship_type,
        'initiatedBy', relationships.initiated_by,
        'status', relationships.status,
        'showOnClubProfile', relationships.show_on_club_profile,
        'revision', relationships.revision,
        'serverSequence', relationships.server_sequence,
        'startedAt', relationships.started_at,
        'endedAt', relationships.ended_at
      ) order by relationships.server_sequence desc, relationships.id)
      from (
        select rows.*
        from public.pachanga_club_team_relationships rows
        join public.pachanga_groups bounded_groups on bounded_groups.id = rows.group_id
        where rows.club_id = target_club_id
          and (can_read or bounded_groups.owner_id = target_actor_id)
        order by rows.server_sequence desc, rows.id
        limit 200
      ) relationships
      join public.pachanga_groups groups on groups.id = relationships.group_id
    ), '[]'::jsonb),
    'collectionLimits', jsonb_build_object(
      'memberships', 200,
      'pendingInvitations', 200,
      'teamRelationships', 200,
      'competitions', 100
    ),
    'entitlements', '[]'::jsonb,
    'competitions', '[]'::jsonb,
    'revision', selected_club.revision,
    'serverSequence', selected_club.server_sequence
  );
end;
$$;

create or replace function private.pachanga_club_notify_v1(
  target_recipient_user_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_dedupe_key text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if target_recipient_user_id is not null then
    perform private.pachanga_notify_v1(
      target_recipient_user_id, target_kind, target_title, target_body,
      target_action_url, target_payload, target_dedupe_key
    );
  end if;
end;
$$;

create or replace function private.pachanga_club_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_club_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_reason_code text,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_invalidation_user_id uuid,
  target_invalidation_group_id uuid,
  target_confirmed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare response jsonb;
begin
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', coalesce(target_snapshot, '{}'::jsonb),
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', target_aggregate_type,
      'entityId', target_aggregate_id,
      'revision', target_confirmed_revision
    ))
  );
  insert into private.pachanga_club_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id, club_id,
    action, aggregate_revision, server_sequence, reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_aggregate_type,
    target_aggregate_id::text, target_club_id, target_action, target_confirmed_revision,
    target_server_sequence, target_reason_code, coalesce(target_event_payload, '{}'::jsonb), target_confirmed_at
  );
  insert into public.pachanga_club_invalidations(
    server_sequence, club_id, target_user_id, target_group_id,
    entity_type, entity_id, revision, created_at
  ) values (
    target_server_sequence, target_club_id, target_invalidation_user_id, target_invalidation_group_id,
    target_aggregate_type, target_aggregate_id::text, target_confirmed_revision, target_confirmed_at
  );
  insert into private.pachanga_club_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence, target_client_metadata, response, target_confirmed_at
  );
  return response;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_club_client_metadata_v1(jsonb)'::regprocedure,
    'private.pachanga_club_request_hash_v1(text,uuid,bigint,jsonb)'::regprocedure,
    'private.pachanga_club_replay_v1(uuid,uuid,text,text,uuid,text)'::regprocedure,
    'private.pachanga_club_platform_can_v1(uuid,text)'::regprocedure,
    'private.pachanga_club_active_role_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_club_can_v1(uuid,uuid,text)'::regprocedure,
    'private.pachanga_club_require_v1(uuid,uuid,text)'::regprocedure,
    'private.pachanga_club_assert_flags_v1(boolean,boolean)'::regprocedure,
    'private.pachanga_club_flags_snapshot_v1()'::regprocedure,
    'private.pachanga_public_club_snapshot_v1(uuid)'::regprocedure,
    'private.pachanga_club_snapshot_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_club_notify_v1(uuid,text,text,text,text,jsonb,text)'::regprocedure,
    'private.pachanga_club_store_command_v1(uuid,uuid,text,text,text,uuid,uuid,bigint,bigint,text,text,jsonb,jsonb,jsonb,uuid,uuid,timestamptz)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

create or replace function public.command_pachanga_club_foundation_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_kind text;
  request_hash text;
  replay jsonb;
  sanitized_metadata jsonb;
  confirmed_at timestamptz := clock_timestamp();
  sequence_value bigint;
  confirmed_revision bigint;
  reason_code text;
  aggregate_type text;
  affected_club_id uuid;
  snapshot jsonb;
  event_payload jsonb := '{}'::jsonb;
  invalidation_user_id uuid;
  invalidation_group_id uuid;
  one_time_token text;
  response jsonb;
  selected_name text;
  selected_slug text;
  selected_role text;
  selected_target_kind text;
  selected_target_user_id uuid;
  selected_target_email text;
  selected_relationship_type text;
  selected_group_id uuid;
  selected_status text;
  selected_expires_at timestamptz;
  retain_previous_owner boolean;
  previous_owner_id uuid;
  owner_count integer;
  created_id uuid;
  selected_club public.pachanga_clubs%rowtype;
  selected_membership public.pachanga_club_memberships%rowtype;
  selected_invitation public.pachanga_club_invitations%rowtype;
  selected_secret private.pachanga_club_invitation_secrets%rowtype;
  selected_relationship public.pachanga_club_team_relationships%rowtype;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or nullif(trim(command_action), '') is null then
    raise exception 'INVALID_CLUB_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_CLUB_COMMAND_PAYLOAD' using errcode = '22023';
  end if;
  if actor_id is null and coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  actor_kind := case when actor_id is null then 'service_authority' else 'authenticated' end;
  sanitized_metadata := private.pachanga_club_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb));
  request_hash := private.pachanga_club_request_hash_v1(
    command_action, aggregate_id, expected_revision, coalesce(command_payload, '{}'::jsonb)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 92201));
  replay := private.pachanga_club_replay_v1(
    operation_id, actor_id, actor_kind, command_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  sequence_value := nextval('private.pachanga_club_sequence');
  reason_code := left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), command_action), 120);

  if command_action = 'club.create' then
    perform private.pachanga_club_assert_flags_v1(true, false);
    if actor_id is null or not exists (
      select 1 from auth.users users
      where users.id = actor_id and users.email_confirmed_at is not null
    ) then
      raise exception 'VERIFIED_EMAIL_REQUIRED' using errcode = '42501';
    end if;
    if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if exists (select 1 from public.pachanga_clubs clubs where clubs.id = aggregate_id) then
      raise exception 'CLUB_ALREADY_EXISTS' using errcode = 'PT409';
    end if;
    if (select count(*) from public.pachanga_clubs clubs
        where clubs.created_by = actor_id
          and clubs.operational_status in ('draft', 'pending_review')) >= 3 then
      raise exception 'CLUB_DRAFT_LIMIT_REACHED' using errcode = 'PT429';
    end if;
    if (select count(*) from public.pachanga_clubs clubs
        where clubs.created_by = actor_id
          and clubs.created_at >= confirmed_at - interval '24 hours') >= 5 then
      raise exception 'CLUB_CREATION_RATE_LIMITED' using errcode = 'PT429';
    end if;
    selected_name := trim(coalesce(command_payload ->> 'name', ''));
    selected_slug := lower(trim(coalesce(command_payload ->> 'slug', '')));
    insert into public.pachanga_clubs(
      id, name, slug, description, club_type, country_code, province, municipality,
      general_area, place_id, website_url, logo_asset, visibility,
      primary_owner_id, revision, server_sequence, created_by, created_at, updated_at
    ) values (
      aggregate_id, selected_name, selected_slug,
      left(coalesce(command_payload ->> 'description', ''), 2000),
      upper(trim(coalesce(command_payload ->> 'clubType', ''))),
      upper(coalesce(nullif(trim(command_payload ->> 'countryCode'), ''), 'ES')),
      left(trim(coalesce(command_payload ->> 'province', '')), 120),
      left(trim(coalesce(command_payload ->> 'municipality', '')), 120),
      left(trim(coalesce(command_payload ->> 'generalArea', '')), 160),
      nullif(left(trim(coalesce(command_payload ->> 'placeId', '')), 240), ''),
      nullif(left(trim(coalesce(command_payload ->> 'websiteUrl', '')), 500), ''),
      nullif(left(trim(coalesce(command_payload ->> 'logoAsset', '')), 500), ''),
      coalesce(nullif(command_payload ->> 'visibility', ''), 'private'),
      actor_id, 1, sequence_value, actor_id, confirmed_at, confirmed_at
    ) returning * into selected_club;
    insert into public.pachanga_club_memberships(
      club_id, user_id, role, status, valid_from, revision, server_sequence,
      invited_by, accepted_at, created_at, updated_at
    ) values (
      selected_club.id, actor_id, 'club_owner', 'active', confirmed_at, 1,
      sequence_value, actor_id, confirmed_at, confirmed_at, confirmed_at
    );
    affected_club_id := selected_club.id;
    aggregate_type := 'club';
    confirmed_revision := selected_club.revision;
    event_payload := jsonb_build_object(
      'name', selected_club.name, 'slug', selected_club.slug, 'clubType', selected_club.club_type
    );

  elsif command_action in ('club.profile.update', 'club.review.submit', 'club.primary_owner.transfer') then
    perform private.pachanga_club_assert_flags_v1(false, false);
    select * into selected_club
    from public.pachanga_clubs clubs
    where clubs.id = aggregate_id
    for update;
    if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_club.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    affected_club_id := selected_club.id;
    aggregate_type := 'club';

    if command_action = 'club.profile.update' then
      perform private.pachanga_club_require_v1(affected_club_id, actor_id, 'profile_manage');
      if selected_club.operational_status = 'archived' then
        raise exception 'CLUB_ARCHIVED' using errcode = '22023';
      end if;
      update public.pachanga_clubs clubs set
        name = case when command_payload ? 'name' then trim(command_payload ->> 'name') else clubs.name end,
        slug = case when command_payload ? 'slug' then lower(trim(command_payload ->> 'slug')) else clubs.slug end,
        description = case when command_payload ? 'description' then left(command_payload ->> 'description', 2000) else clubs.description end,
        club_type = case when command_payload ? 'clubType' then upper(trim(command_payload ->> 'clubType')) else clubs.club_type end,
        country_code = case when command_payload ? 'countryCode' then upper(trim(command_payload ->> 'countryCode')) else clubs.country_code end,
        province = case when command_payload ? 'province' then left(trim(command_payload ->> 'province'), 120) else clubs.province end,
        municipality = case when command_payload ? 'municipality' then left(trim(command_payload ->> 'municipality'), 120) else clubs.municipality end,
        general_area = case when command_payload ? 'generalArea' then left(trim(command_payload ->> 'generalArea'), 160) else clubs.general_area end,
        place_id = case when command_payload ? 'placeId' then nullif(left(trim(command_payload ->> 'placeId'), 240), '') else clubs.place_id end,
        website_url = case when command_payload ? 'websiteUrl' then nullif(left(trim(command_payload ->> 'websiteUrl'), 500), '') else clubs.website_url end,
        logo_asset = case when command_payload ? 'logoAsset' then nullif(left(trim(command_payload ->> 'logoAsset'), 500), '') else clubs.logo_asset end,
        visibility = case when command_payload ? 'visibility' then command_payload ->> 'visibility' else clubs.visibility end,
        revision = clubs.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where clubs.id = affected_club_id
      returning * into selected_club;
      confirmed_revision := selected_club.revision;
      event_payload := jsonb_build_object('profileUpdated', true);

    elsif command_action = 'club.review.submit' then
      perform private.pachanga_club_require_v1(affected_club_id, actor_id, 'profile_manage');
      if selected_club.operational_status not in ('draft', 'rejected') then
        raise exception 'CLUB_REVIEW_TRANSITION_NOT_ALLOWED' using errcode = '22023';
      end if;
      update public.pachanga_clubs clubs set
        operational_status = 'pending_review',
        verification_status = case when clubs.verification_status in ('unverified', 'rejected') then 'pending' else clubs.verification_status end,
        revision = clubs.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where clubs.id = affected_club_id
      returning * into selected_club;
      confirmed_revision := selected_club.revision;
      event_payload := jsonb_build_object('operationalStatus', 'pending_review');

    else
      perform private.pachanga_club_require_v1(affected_club_id, actor_id, 'ownership_manage');
      selected_target_user_id := nullif(command_payload ->> 'targetUserId', '')::uuid;
      if selected_target_user_id is null or selected_target_user_id = selected_club.primary_owner_id then
        raise exception 'INVALID_PRIMARY_OWNER_TARGET' using errcode = '22023';
      end if;
      if not exists (
        select 1 from public.pachanga_club_memberships memberships
        where memberships.club_id = affected_club_id and memberships.user_id = selected_target_user_id
          and memberships.role = 'club_owner' and memberships.status = 'active'
      ) then
        raise exception 'PRIMARY_OWNER_TARGET_MUST_BE_ACTIVE_OWNER' using errcode = '42501';
      end if;
      previous_owner_id := selected_club.primary_owner_id;
      retain_previous_owner := coalesce((command_payload ->> 'retainPreviousOwner')::boolean, true);
      update public.pachanga_clubs clubs set
        primary_owner_id = selected_target_user_id,
        revision = clubs.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where clubs.id = affected_club_id
      returning * into selected_club;
      if not retain_previous_owner then
        update public.pachanga_club_memberships memberships set
          status = 'revoked', revision = memberships.revision + 1,
          revoked_by = actor_id, revoked_at = confirmed_at,
          server_sequence = sequence_value, updated_at = confirmed_at
        where memberships.club_id = affected_club_id and memberships.user_id = previous_owner_id
          and memberships.role = 'club_owner' and memberships.status = 'active';
      end if;
      confirmed_revision := selected_club.revision;
      event_payload := jsonb_build_object(
        'beforePrimaryOwnerId', previous_owner_id,
        'afterPrimaryOwnerId', selected_target_user_id,
        'previousOwnerRetained', retain_previous_owner
      );
      invalidation_user_id := selected_target_user_id;
    end if;

  elsif command_action = 'membership.invite' then
    perform private.pachanga_club_assert_flags_v1(false, false);
    select * into selected_club
    from public.pachanga_clubs clubs where clubs.id = aggregate_id for update;
    if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_club.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if selected_club.operational_status in ('suspended', 'rejected', 'archived') then
      raise exception 'CLUB_INVITATIONS_BLOCKED' using errcode = '42501';
    end if;
    selected_role := trim(coalesce(command_payload ->> 'role', ''));
    if selected_role in ('club_venue_manager', 'club_referee_manager', 'club_finance_manager') then
      raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    if selected_role not in ('club_owner', 'club_admin', 'club_competition_manager', 'club_viewer') then
      raise exception 'INVALID_CLUB_ROLE' using errcode = '22023';
    end if;
    if selected_role = 'club_owner' then
      perform private.pachanga_club_require_v1(selected_club.id, actor_id, 'staff_manage');
    else
      perform private.pachanga_club_require_v1(selected_club.id, actor_id, 'staff_manage_non_owner');
    end if;
    selected_target_kind := trim(coalesce(command_payload ->> 'targetKind', ''));
    selected_expires_at := coalesce(
      nullif(command_payload ->> 'expiresAt', '')::timestamptz,
      confirmed_at + interval '7 days'
    );
    if selected_expires_at <= confirmed_at or selected_expires_at > confirmed_at + interval '30 days' then
      raise exception 'INVALID_INVITATION_EXPIRY' using errcode = '22023';
    end if;
    one_time_token := encode(extensions.gen_random_bytes(32), 'hex');
    created_id := gen_random_uuid();
    if selected_target_kind = 'registered_user' then
      selected_target_user_id := nullif(command_payload ->> 'targetUserId', '')::uuid;
      if selected_target_user_id is null or not exists (
        select 1 from auth.users users where users.id = selected_target_user_id
      ) then raise exception 'INVITATION_TARGET_NOT_FOUND' using errcode = 'P0002'; end if;
      if exists (
        select 1 from public.pachanga_club_memberships memberships
        where memberships.club_id = selected_club.id
          and memberships.user_id = selected_target_user_id
          and memberships.status in ('invited', 'active')
      ) then raise exception 'CLUB_MEMBERSHIP_ALREADY_CURRENT' using errcode = 'PT409'; end if;
      insert into public.pachanga_club_memberships(
        club_id, user_id, role, status, valid_from, expires_at, server_sequence,
        invited_by, created_at, updated_at
      ) values (
        selected_club.id, selected_target_user_id, selected_role, 'invited', confirmed_at,
        selected_expires_at, sequence_value, actor_id, confirmed_at, confirmed_at
      ) returning * into selected_membership;
      invalidation_user_id := selected_target_user_id;
    elsif selected_target_kind = 'email_target' then
      selected_target_email := lower(trim(coalesce(command_payload ->> 'targetEmail', '')));
      if selected_target_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$'
         or length(selected_target_email) > 320 then
        raise exception 'INVALID_INVITATION_EMAIL' using errcode = '22023';
      end if;
    else
      raise exception 'INVALID_INVITATION_TARGET_KIND' using errcode = '22023';
    end if;
    insert into public.pachanga_club_invitations(
      id, club_id, membership_id, target_kind, target_user_id, role, status,
      expires_at, revision, server_sequence, invited_by, created_at, updated_at
    ) values (
      created_id, selected_club.id, selected_membership.id, selected_target_kind,
      selected_target_user_id, selected_role, 'pending', selected_expires_at,
      1, sequence_value, actor_id, confirmed_at, confirmed_at
    ) returning * into selected_invitation;
    insert into private.pachanga_club_invitation_secrets(
      invitation_id, token_hash, target_email_normalized, target_email_hash,
      retention_until, created_at
    ) values (
      selected_invitation.id,
      encode(extensions.digest(one_time_token, 'sha256'), 'hex'),
      selected_target_email,
      case when selected_target_email is null then null else encode(extensions.digest(selected_target_email, 'sha256'), 'hex') end,
      selected_expires_at + interval '90 days', confirmed_at
    );
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1, server_sequence = sequence_value, updated_at = confirmed_at
    where clubs.id = selected_club.id returning * into selected_club;
    affected_club_id := selected_club.id;
    aggregate_type := 'club';
    confirmed_revision := selected_club.revision;
    event_payload := jsonb_build_object(
      'invitationId', selected_invitation.id,
      'targetKind', selected_target_kind,
      'role', selected_role,
      'expiresAt', selected_expires_at
    );
    if selected_target_user_id is not null then
      perform private.pachanga_club_notify_v1(
        selected_target_user_id, 'club_staff_invitation', 'Invitación a un Club',
        selected_club.name || ' te ha invitado a formar parte de su staff.',
        '/laboratorio-club-foundation?invitation=' || selected_invitation.id::text,
        jsonb_build_object('clubId', selected_club.id, 'invitationId', selected_invitation.id),
        'club-staff-invitation:' || operation_id::text || ':' || selected_target_user_id::text
      );
    end if;

  elsif command_action in ('membership.accept', 'membership.decline') then
    perform private.pachanga_club_assert_flags_v1(false, false);
    if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select * into selected_invitation
    from public.pachanga_club_invitations invitations
    where invitations.id = aggregate_id
    for update;
    if not found then raise exception 'CLUB_INVITATION_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_invitation.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if selected_invitation.status <> 'pending' then
      raise exception 'CLUB_INVITATION_NOT_PENDING' using errcode = 'PT409';
    end if;
    if selected_invitation.expires_at <= confirmed_at then
      raise exception 'CLUB_INVITATION_EXPIRED' using errcode = '42501';
    end if;
    one_time_token := trim(coalesce(command_payload ->> 'token', ''));
    if length(one_time_token) <> 64 then
      raise exception 'CLUB_INVITATION_TOKEN_INVALID' using errcode = '42501';
    end if;
    select * into selected_secret
    from private.pachanga_club_invitation_secrets secrets
    where secrets.invitation_id = selected_invitation.id
    for update;
    if not found or selected_secret.consumed_at is not null
       or selected_secret.token_hash <> encode(extensions.digest(one_time_token, 'sha256'), 'hex') then
      raise exception 'CLUB_INVITATION_TOKEN_INVALID' using errcode = '42501';
    end if;
    if selected_invitation.target_kind = 'registered_user' then
      if selected_invitation.target_user_id <> actor_id then
        raise exception 'CLUB_INVITATION_RECIPIENT_MISMATCH' using errcode = '42501';
      end if;
    elsif not exists (
      select 1 from auth.users users
      where users.id = actor_id and users.email_confirmed_at is not null
        and lower(users.email) = selected_secret.target_email_normalized
    ) then
      raise exception 'CLUB_INVITATION_EMAIL_MISMATCH' using errcode = '42501';
    end if;
    select * into selected_club
    from public.pachanga_clubs clubs
    where clubs.id = selected_invitation.club_id
    for update;
    if selected_club.operational_status in ('archived', 'rejected') then
      raise exception 'CLUB_INVITATION_BLOCKED' using errcode = '42501';
    end if;

    if command_action = 'membership.accept' then
      if exists (
        select 1 from public.pachanga_club_memberships memberships
        where memberships.club_id = selected_invitation.club_id
          and memberships.user_id = actor_id and memberships.status = 'active'
          and memberships.id is distinct from selected_invitation.membership_id
      ) then raise exception 'CLUB_MEMBERSHIP_ALREADY_ACTIVE' using errcode = 'PT409'; end if;
      if selected_invitation.membership_id is null then
        insert into public.pachanga_club_memberships(
          club_id, user_id, role, status, valid_from, expires_at, revision,
          server_sequence, invited_by, accepted_at, created_at, updated_at
        ) values (
          selected_invitation.club_id, actor_id, selected_invitation.role, 'active',
          confirmed_at, null, 1, sequence_value, selected_invitation.invited_by,
          confirmed_at, confirmed_at, confirmed_at
        ) returning * into selected_membership;
      else
        update public.pachanga_club_memberships memberships set
          status = 'active', expires_at = null, accepted_at = confirmed_at,
          revision = memberships.revision + 1, server_sequence = sequence_value,
          updated_at = confirmed_at
        where memberships.id = selected_invitation.membership_id
          and memberships.status = 'invited'
        returning * into selected_membership;
        if not found then raise exception 'CLUB_INVITATION_MEMBERSHIP_CONFLICT' using errcode = 'PT409'; end if;
      end if;
      update public.pachanga_club_invitations invitations set
        membership_id = selected_membership.id,
        status = 'accepted', accepted_by = actor_id, accepted_at = confirmed_at,
        revision = invitations.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where invitations.id = selected_invitation.id
      returning * into selected_invitation;
      event_payload := jsonb_build_object(
        'invitationId', selected_invitation.id,
        'membershipId', selected_membership.id,
        'role', selected_membership.role,
        'status', 'accepted'
      );
      perform private.pachanga_club_notify_v1(
        selected_invitation.invited_by, 'club_staff_invitation_accepted',
        'Invitación de Club aceptada', 'La invitación de staff ha sido aceptada.',
        '/laboratorio-club-foundation?club=' || selected_invitation.club_id::text,
        jsonb_build_object('clubId', selected_invitation.club_id, 'invitationId', selected_invitation.id),
        'club-staff-invitation-accepted:' || operation_id::text || ':' || selected_invitation.invited_by::text
      );
    else
      update public.pachanga_club_invitations invitations set
        status = 'declined', revoked_by = actor_id, revoked_at = confirmed_at,
        revision = invitations.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where invitations.id = selected_invitation.id
      returning * into selected_invitation;
      if selected_invitation.membership_id is not null then
        update public.pachanga_club_memberships memberships set
          status = 'declined', revoked_by = actor_id, revoked_at = confirmed_at,
          revision = memberships.revision + 1, server_sequence = sequence_value,
          updated_at = confirmed_at
        where memberships.id = selected_invitation.membership_id and memberships.status = 'invited';
      end if;
      event_payload := jsonb_build_object(
        'invitationId', selected_invitation.id, 'role', selected_invitation.role, 'status', 'declined'
      );
      perform private.pachanga_club_notify_v1(
        selected_invitation.invited_by, 'club_staff_invitation_declined',
        'Invitación de Club rechazada', 'La invitación de staff ha sido rechazada.',
        '/laboratorio-club-foundation?club=' || selected_invitation.club_id::text,
        jsonb_build_object('clubId', selected_invitation.club_id, 'invitationId', selected_invitation.id),
        'club-staff-invitation-declined:' || operation_id::text || ':' || selected_invitation.invited_by::text
      );
    end if;
    update private.pachanga_club_invitation_secrets secrets
    set consumed_at = confirmed_at, target_email_normalized = null, target_email_hash = null
    where secrets.invitation_id = selected_invitation.id;
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1, server_sequence = sequence_value, updated_at = confirmed_at
    where clubs.id = selected_invitation.club_id returning * into selected_club;
    affected_club_id := selected_club.id;
    aggregate_type := 'club_invitation';
    confirmed_revision := selected_invitation.revision;
    invalidation_user_id := actor_id;

  elsif command_action = 'membership.invitation.revoke' then
    perform private.pachanga_club_assert_flags_v1(false, false);
    select * into selected_invitation
    from public.pachanga_club_invitations invitations
    where invitations.id = aggregate_id
    for update;
    if not found then raise exception 'CLUB_INVITATION_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_invitation.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if selected_invitation.status <> 'pending' then raise exception 'CLUB_INVITATION_NOT_PENDING' using errcode = 'PT409'; end if;
    if selected_invitation.role = 'club_owner' then
      perform private.pachanga_club_require_v1(selected_invitation.club_id, actor_id, 'staff_manage');
    else
      perform private.pachanga_club_require_v1(selected_invitation.club_id, actor_id, 'staff_manage_non_owner');
    end if;
    select * into selected_club
    from public.pachanga_clubs clubs where clubs.id = selected_invitation.club_id for update;
    update public.pachanga_club_invitations invitations set
      status = 'revoked', revoked_by = actor_id, revoked_at = confirmed_at,
      revision = invitations.revision + 1, server_sequence = sequence_value,
      updated_at = confirmed_at
    where invitations.id = selected_invitation.id returning * into selected_invitation;
    if selected_invitation.membership_id is not null then
      update public.pachanga_club_memberships memberships set
        status = 'revoked', revoked_by = actor_id, revoked_at = confirmed_at,
        revision = memberships.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where memberships.id = selected_invitation.membership_id and memberships.status = 'invited';
    end if;
    update private.pachanga_club_invitation_secrets secrets
    set consumed_at = confirmed_at, target_email_normalized = null, target_email_hash = null
    where secrets.invitation_id = selected_invitation.id;
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1, server_sequence = sequence_value, updated_at = confirmed_at
    where clubs.id = selected_invitation.club_id returning * into selected_club;
    affected_club_id := selected_club.id;
    aggregate_type := 'club_invitation';
    confirmed_revision := selected_invitation.revision;
    invalidation_user_id := selected_invitation.target_user_id;
    event_payload := jsonb_build_object('invitationId', selected_invitation.id, 'status', 'revoked');

  elsif command_action = 'membership.revoke' then
    perform private.pachanga_club_assert_flags_v1(false, false);
    select * into selected_membership
    from public.pachanga_club_memberships memberships
    where memberships.id = aggregate_id
    for update;
    if not found then raise exception 'CLUB_MEMBERSHIP_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_membership.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if selected_membership.status <> 'active' then raise exception 'CLUB_MEMBERSHIP_NOT_ACTIVE' using errcode = 'PT409'; end if;
    if selected_membership.role = 'club_owner' then
      perform private.pachanga_club_require_v1(selected_membership.club_id, actor_id, 'staff_manage');
    else
      perform private.pachanga_club_require_v1(selected_membership.club_id, actor_id, 'staff_manage_non_owner');
    end if;
    select * into selected_club
    from public.pachanga_clubs clubs where clubs.id = selected_membership.club_id for update;
    if selected_club.primary_owner_id = selected_membership.user_id then
      raise exception 'PRIMARY_OWNER_TRANSFER_REQUIRED' using errcode = '42501';
    end if;
    if selected_membership.role = 'club_owner' then
      select count(*) into owner_count
      from public.pachanga_club_memberships memberships
      where memberships.club_id = selected_membership.club_id
        and memberships.role = 'club_owner' and memberships.status = 'active';
      if owner_count <= 1 then raise exception 'LAST_CLUB_OWNER_REQUIRED' using errcode = '42501'; end if;
    end if;
    update public.pachanga_club_memberships memberships set
      status = 'revoked', revoked_by = actor_id, revoked_at = confirmed_at,
      revision = memberships.revision + 1, server_sequence = sequence_value,
      updated_at = confirmed_at
    where memberships.id = selected_membership.id returning * into selected_membership;
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1, server_sequence = sequence_value, updated_at = confirmed_at
    where clubs.id = selected_membership.club_id returning * into selected_club;
    affected_club_id := selected_club.id;
    aggregate_type := 'club_membership';
    confirmed_revision := selected_membership.revision;
    invalidation_user_id := selected_membership.user_id;
    event_payload := jsonb_build_object(
      'membershipId', selected_membership.id, 'role', selected_membership.role, 'status', 'revoked'
    );
    perform private.pachanga_club_notify_v1(
      selected_membership.user_id, 'club_staff_membership_revoked',
      'Acceso de Club retirado', 'Tu acceso al Club ha sido retirado.',
      '/perfil', jsonb_build_object('clubId', selected_membership.club_id),
      'club-membership-revoked:' || operation_id::text || ':' || selected_membership.user_id::text
    );

  elsif command_action in ('team_relationship.invite', 'team_relationship.request') then
    perform private.pachanga_club_assert_flags_v1(false, true);
    select * into selected_club
    from public.pachanga_clubs clubs where clubs.id = aggregate_id for update;
    if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_club.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if selected_club.operational_status <> 'active' then
      raise exception 'CLUB_MUST_BE_ACTIVE' using errcode = '42501';
    end if;
    selected_group_id := nullif(command_payload ->> 'groupId', '')::uuid;
    if selected_group_id is null or not exists (
      select 1 from public.pachanga_groups groups where groups.id = selected_group_id
    ) then raise exception 'TEAM_NOT_FOUND' using errcode = 'P0002'; end if;
    selected_relationship_type := upper(trim(coalesce(command_payload ->> 'relationshipType', '')));
    if selected_relationship_type not in ('MEMBER', 'AFFILIATED', 'HOSTED') then
      raise exception 'INVALID_CLUB_TEAM_RELATIONSHIP_TYPE' using errcode = '22023';
    end if;
    if exists (
      select 1 from public.pachanga_club_team_relationships relationships
      where relationships.club_id = selected_club.id and relationships.group_id = selected_group_id
        and relationships.status in ('invited', 'requested', 'active')
    ) then raise exception 'CLUB_TEAM_RELATIONSHIP_ALREADY_CURRENT' using errcode = 'PT409'; end if;

    if command_action = 'team_relationship.invite' then
      perform private.pachanga_club_require_v1(selected_club.id, actor_id, 'team_links_manage');
      selected_status := 'invited';
    else
      if actor_id is null or not exists (
        select 1 from public.pachanga_groups groups
        where groups.id = selected_group_id and groups.owner_id = actor_id
      ) then raise exception 'TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
      selected_status := 'requested';
    end if;
    created_id := gen_random_uuid();
    insert into public.pachanga_club_team_relationships(
      id, club_id, group_id, relationship_type, initiated_by, status,
      show_on_club_profile, revision, server_sequence, created_by, reason, created_at, updated_at
    ) values (
      created_id, selected_club.id, selected_group_id, selected_relationship_type,
      case when selected_status = 'invited' then 'CLUB' else 'TEAM' end,
      selected_status, false, 1, sequence_value, actor_id,
      left(coalesce(command_payload ->> 'reason', ''), 1200), confirmed_at, confirmed_at
    ) returning * into selected_relationship;
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1, server_sequence = sequence_value, updated_at = confirmed_at
    where clubs.id = selected_club.id returning * into selected_club;
    affected_club_id := selected_club.id;
    aggregate_type := 'club';
    confirmed_revision := selected_club.revision;
    invalidation_group_id := selected_group_id;
    event_payload := jsonb_build_object(
      'relationshipId', selected_relationship.id,
      'groupId', selected_group_id,
      'relationshipType', selected_relationship_type,
      'status', selected_status,
      'initiatedBy', selected_relationship.initiated_by
    );
    if selected_status = 'invited' then
      select groups.owner_id into selected_target_user_id
      from public.pachanga_groups groups where groups.id = selected_group_id;
      perform private.pachanga_club_notify_v1(
        selected_target_user_id, 'club_team_invitation', 'Invitación de un Club',
        selected_club.name || ' quiere vincular tu equipo.',
        '/laboratorio-club-foundation?relationship=' || selected_relationship.id::text,
        jsonb_build_object(
          'clubId', selected_club.id, 'groupId', selected_group_id,
          'relationshipId', selected_relationship.id
        ),
        'club-team-invitation:' || operation_id::text || ':' || selected_target_user_id::text
      );
    else
      for selected_target_user_id in
        select memberships.user_id
        from public.pachanga_club_memberships memberships
        where memberships.club_id = selected_club.id and memberships.status = 'active'
          and memberships.role in ('club_owner', 'club_admin')
      loop
        perform private.pachanga_club_notify_v1(
          selected_target_user_id, 'club_team_request', 'Solicitud de vinculación',
          'Un equipo quiere vincularse con ' || selected_club.name || '.',
          '/laboratorio-club-foundation?relationship=' || selected_relationship.id::text,
          jsonb_build_object(
            'clubId', selected_club.id, 'groupId', selected_group_id,
            'relationshipId', selected_relationship.id
          ),
          'club-team-request:' || operation_id::text || ':' || selected_target_user_id::text
        );
      end loop;
    end if;

  elsif command_action in (
    'team_relationship.accept', 'team_relationship.reject',
    'team_relationship.cancel', 'team_relationship.end', 'team_relationship.visibility.set'
  ) then
    perform private.pachanga_club_assert_flags_v1(false, true);
    select * into selected_relationship
    from public.pachanga_club_team_relationships relationships
    where relationships.id = aggregate_id
    for update;
    if not found then raise exception 'CLUB_TEAM_RELATIONSHIP_NOT_FOUND' using errcode = 'P0002'; end if;
    if selected_relationship.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    select * into selected_club
    from public.pachanga_clubs clubs where clubs.id = selected_relationship.club_id for update;
    if not found then raise exception 'CLUB_NOT_FOUND' using errcode = 'P0002'; end if;
    affected_club_id := selected_club.id;
    aggregate_type := 'club_team_relationship';
    invalidation_group_id := selected_relationship.group_id;

    if command_action in ('team_relationship.accept', 'team_relationship.reject') then
      if selected_relationship.status not in ('invited', 'requested') then
        raise exception 'CLUB_TEAM_RELATIONSHIP_NOT_PENDING' using errcode = 'PT409';
      end if;
      if selected_relationship.status = 'invited' then
        if actor_id is null or not exists (
          select 1 from public.pachanga_groups groups
          where groups.id = selected_relationship.group_id and groups.owner_id = actor_id
        ) then raise exception 'TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
      else
        perform private.pachanga_club_require_v1(selected_relationship.club_id, actor_id, 'team_links_manage');
      end if;
      selected_status := case when command_action = 'team_relationship.accept' then 'active' else 'rejected' end;
      update public.pachanga_club_team_relationships relationships set
        status = selected_status,
        responded_by = actor_id,
        started_at = case when selected_status = 'active' then confirmed_at else relationships.started_at end,
        ended_at = case when selected_status = 'rejected' then confirmed_at else null end,
        ended_by = case when selected_status = 'rejected' then actor_id else null end,
        reason = case when selected_status = 'rejected' then left(coalesce(command_payload ->> 'reason', ''), 1200) else relationships.reason end,
        revision = relationships.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where relationships.id = selected_relationship.id
      returning * into selected_relationship;

    elsif command_action = 'team_relationship.cancel' then
      if selected_relationship.status not in ('invited', 'requested') then
        raise exception 'CLUB_TEAM_RELATIONSHIP_NOT_PENDING' using errcode = 'PT409';
      end if;
      if selected_relationship.initiated_by = 'CLUB' then
        perform private.pachanga_club_require_v1(selected_relationship.club_id, actor_id, 'team_links_manage');
      elsif actor_id is null or not exists (
        select 1 from public.pachanga_groups groups
        where groups.id = selected_relationship.group_id and groups.owner_id = actor_id
      ) then raise exception 'TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
      selected_status := 'cancelled';
      update public.pachanga_club_team_relationships relationships set
        status = 'cancelled', ended_at = confirmed_at, ended_by = actor_id,
        reason = left(coalesce(command_payload ->> 'reason', ''), 1200),
        revision = relationships.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where relationships.id = selected_relationship.id
      returning * into selected_relationship;

    elsif command_action = 'team_relationship.end' then
      if selected_relationship.status <> 'active' then
        raise exception 'CLUB_TEAM_RELATIONSHIP_NOT_ACTIVE' using errcode = 'PT409';
      end if;
      if not private.pachanga_club_can_v1(selected_relationship.club_id, actor_id, 'team_links_manage')
         and not exists (
           select 1 from public.pachanga_groups groups
           where groups.id = selected_relationship.group_id and groups.owner_id = actor_id
         ) then raise exception 'CLUB_OR_TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
      selected_status := 'ended';
      update public.pachanga_club_team_relationships relationships set
        status = 'ended', ended_at = confirmed_at, ended_by = actor_id,
        reason = left(coalesce(command_payload ->> 'reason', ''), 1200),
        revision = relationships.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where relationships.id = selected_relationship.id
      returning * into selected_relationship;

    else
      if selected_relationship.status <> 'active' then
        raise exception 'CLUB_TEAM_RELATIONSHIP_NOT_ACTIVE' using errcode = 'PT409';
      end if;
      if actor_id is null or not exists (
        select 1 from public.pachanga_groups groups
        where groups.id = selected_relationship.group_id and groups.owner_id = actor_id
      ) then raise exception 'TEAM_OWNER_REQUIRED' using errcode = '42501'; end if;
      if not (command_payload ? 'showOnClubProfile')
         or jsonb_typeof(command_payload -> 'showOnClubProfile') <> 'boolean' then
        raise exception 'INVALID_CLUB_PROFILE_VISIBILITY' using errcode = '22023';
      end if;
      selected_status := selected_relationship.status;
      update public.pachanga_club_team_relationships relationships set
        show_on_club_profile = (command_payload ->> 'showOnClubProfile')::boolean,
        revision = relationships.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where relationships.id = selected_relationship.id
      returning * into selected_relationship;
    end if;
    update public.pachanga_clubs clubs set
      revision = clubs.revision + 1, server_sequence = sequence_value, updated_at = confirmed_at
    where clubs.id = selected_relationship.club_id returning * into selected_club;
    confirmed_revision := selected_relationship.revision;
    event_payload := jsonb_build_object(
      'relationshipId', selected_relationship.id,
      'groupId', selected_relationship.group_id,
      'relationshipType', selected_relationship.relationship_type,
      'status', selected_relationship.status,
      'showOnClubProfile', selected_relationship.show_on_club_profile
    );
    perform private.pachanga_club_notify_v1(
      selected_relationship.created_by,
      'club_team_relationship_' || selected_relationship.status,
      case selected_relationship.status
        when 'active' then 'Vinculación aceptada'
        when 'rejected' then 'Vinculación rechazada'
        when 'ended' then 'Vinculación finalizada'
        else 'Vinculación cancelada'
      end,
      'La relación entre Club y equipo ha cambiado.',
      '/laboratorio-club-foundation?relationship=' || selected_relationship.id::text,
      jsonb_build_object(
        'clubId', selected_relationship.club_id,
        'groupId', selected_relationship.group_id,
        'relationshipId', selected_relationship.id,
        'status', selected_relationship.status
      ),
      'club-team-relationship:' || operation_id::text || ':' || selected_relationship.created_by::text
    );
  else
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  if affected_club_id is null then affected_club_id := selected_club.id; end if;
  snapshot := private.pachanga_club_snapshot_v1(affected_club_id, actor_id);
  response := private.pachanga_club_store_command_v1(
    operation_id, actor_id, actor_kind, command_action, aggregate_type, aggregate_id,
    affected_club_id, confirmed_revision, sequence_value, reason_code, request_hash,
    sanitized_metadata, event_payload, snapshot, invalidation_user_id,
    invalidation_group_id, confirmed_at
  );
  if one_time_token is not null then
    return response || jsonb_build_object(
      'oneTimeToken', one_time_token,
      'invitationId', selected_invitation.id,
      'tokenReturnedOnce', true
    );
  end if;
  return response;
exception
  when unique_violation then
    raise exception 'CLUB_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function private.pachanga_club_guard_owner_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare target_club_id uuid;
declare target_primary_owner_id uuid;
begin
  if tg_op = 'DELETE' then
    target_club_id := old.club_id;
  elsif tg_table_name = 'pachanga_clubs' then
    target_club_id := new.id;
  else
    target_club_id := new.club_id;
  end if;
  select clubs.primary_owner_id into target_primary_owner_id
  from public.pachanga_clubs clubs where clubs.id = target_club_id;
  if not found then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;
  if not exists (
    select 1 from public.pachanga_club_memberships memberships
    where memberships.club_id = target_club_id
      and memberships.user_id = target_primary_owner_id
      and memberships.role = 'club_owner'
      and memberships.status = 'active'
  ) then
    raise exception 'CLUB_PRIMARY_OWNER_MEMBERSHIP_REQUIRED' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.pachanga_club_memberships memberships
    where memberships.club_id = target_club_id
      and memberships.role = 'club_owner'
      and memberships.status = 'active'
  ) then
    raise exception 'LAST_CLUB_OWNER_REQUIRED' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function private.pachanga_club_guard_owner_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_club_guard_owner_from_club_v1 on public.pachanga_clubs;
create constraint trigger pachanga_club_guard_owner_from_club_v1
after insert or update of primary_owner_id on public.pachanga_clubs
deferrable initially deferred
for each row execute function private.pachanga_club_guard_owner_v1();

create or replace function private.pachanga_club_immutable_ledger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'CLUB_AUDIT_LEDGER_IMMUTABLE' using errcode = '42501';
end;
$$;

revoke all on function private.pachanga_club_immutable_ledger_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_club_receipts_v1
  on private.pachanga_club_operation_receipts;
create trigger guard_pachanga_club_receipts_v1
before update or delete on private.pachanga_club_operation_receipts
for each row execute function private.pachanga_club_immutable_ledger_v1();

drop trigger if exists guard_pachanga_club_events_v1
  on private.pachanga_club_events;
create trigger guard_pachanga_club_events_v1
before update or delete on private.pachanga_club_events
for each row execute function private.pachanga_club_immutable_ledger_v1();

drop trigger if exists pachanga_club_guard_owner_from_membership_v1 on public.pachanga_club_memberships;
create constraint trigger pachanga_club_guard_owner_from_membership_v1
after insert or update or delete on public.pachanga_club_memberships
deferrable initially deferred
for each row execute function private.pachanga_club_guard_owner_v1();

create or replace function public.get_pachanga_club_foundation_flags_v1()
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_club_flags_snapshot_v1()
  where (select auth.uid()) is not null or coalesce((select auth.role()), '') = 'service_role';
$$;

create or replace function public.get_pachanga_club_foundation_snapshot_v1(target_club_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare snapshot jsonb;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  snapshot := private.pachanga_club_snapshot_v1(target_club_id, actor_id);
  if snapshot is null then raise exception 'CLUB_NOT_FOUND_OR_FORBIDDEN' using errcode = '42501'; end if;
  return snapshot;
end;
$$;

create or replace function public.get_my_pachanga_club_foundation_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'flags', private.pachanga_club_flags_snapshot_v1(),
    'clubs', coalesce((
      select jsonb_agg(private.pachanga_club_snapshot_v1(clubs.id, actor_id)
        order by clubs.updated_at desc, clubs.id)
      from (
        select rows.*
        from public.pachanga_clubs rows
        where private.pachanga_club_can_v1(rows.id, actor_id, 'read')
          or exists (
            select 1
            from public.pachanga_club_team_relationships relationships
            join public.pachanga_groups groups on groups.id = relationships.group_id
            where relationships.club_id = rows.id and groups.owner_id = actor_id
          )
        order by rows.updated_at desc, rows.id
        limit 50
      ) clubs
    ), '[]'::jsonb),
    'pendingInvitations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', invitations.id,
        'clubId', invitations.club_id,
        'clubName', clubs.name,
        'targetKind', invitations.target_kind,
        'role', invitations.role,
        'status', case when invitations.expires_at <= clock_timestamp() then 'expired' else invitations.status end,
        'expiresAt', invitations.expires_at,
        'revision', invitations.revision,
        'serverSequence', invitations.server_sequence
      ) order by invitations.server_sequence desc, invitations.id)
      from (
        select rows.*
        from public.pachanga_club_invitations rows
        where rows.target_user_id = actor_id and rows.status = 'pending'
        order by rows.server_sequence desc, rows.id
        limit 100
      ) invitations
      join public.pachanga_clubs clubs on clubs.id = invitations.club_id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pachanga_club_invitation_v1(
  target_invitation_id uuid,
  invitation_token text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare invitation public.pachanga_club_invitations%rowtype;
declare secret private.pachanga_club_invitation_secrets%rowtype;
declare club public.pachanga_clubs%rowtype;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into invitation from public.pachanga_club_invitations rows where rows.id = target_invitation_id;
  select * into secret from private.pachanga_club_invitation_secrets rows where rows.invitation_id = target_invitation_id;
  if invitation.id is null or secret.invitation_id is null
     or invitation.status <> 'pending' or invitation.expires_at <= clock_timestamp()
     or length(trim(coalesce(invitation_token, ''))) <> 64
     or secret.consumed_at is not null
     or secret.token_hash <> encode(extensions.digest(trim(invitation_token), 'sha256'), 'hex') then
    raise exception 'CLUB_INVITATION_TOKEN_INVALID' using errcode = '42501';
  end if;
  if invitation.target_kind = 'registered_user' and invitation.target_user_id <> actor_id then
    raise exception 'CLUB_INVITATION_RECIPIENT_MISMATCH' using errcode = '42501';
  end if;
  if invitation.target_kind = 'email_target' and not exists (
    select 1 from auth.users users
    where users.id = actor_id and users.email_confirmed_at is not null
      and lower(users.email) = secret.target_email_normalized
  ) then raise exception 'CLUB_INVITATION_EMAIL_MISMATCH' using errcode = '42501'; end if;
  select * into club from public.pachanga_clubs clubs where clubs.id = invitation.club_id;
  return jsonb_build_object(
    'id', invitation.id,
    'clubId', invitation.club_id,
    'clubName', club.name,
    'role', invitation.role,
    'status', invitation.status,
    'expiresAt', invitation.expires_at,
    'revision', invitation.revision
  );
end;
$$;

create or replace function public.get_pachanga_public_club_v1(target_slug text)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_public_club_snapshot_v1(clubs.id)
  from public.pachanga_clubs clubs
  where clubs.slug = lower(trim(target_slug));
$$;

create or replace function public.purge_pachanga_club_invitation_contacts_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare expired_count integer;
declare purged_count integer;
declare sequence_value bigint := nextval('private.pachanga_club_sequence');
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  with expired as (
    update public.pachanga_club_invitations invitations set
      status = 'expired', revoked_at = clock_timestamp(),
      revision = invitations.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where invitations.status = 'pending' and invitations.expires_at <= clock_timestamp()
    returning invitations.membership_id
  )
  select count(*) into expired_count from expired;
  update public.pachanga_club_memberships memberships set
    status = 'expired', revoked_at = clock_timestamp(),
    revision = memberships.revision + 1, server_sequence = sequence_value,
    updated_at = clock_timestamp()
  where memberships.status = 'invited'
    and memberships.expires_at <= clock_timestamp();
  with purged as (
    update private.pachanga_club_invitation_secrets secrets set
      target_email_normalized = null,
      target_email_hash = null
    where secrets.retention_until <= clock_timestamp()
      and secrets.target_email_normalized is not null
    returning 1
  ) select count(*) into purged_count from purged;
  return jsonb_build_object(
    'expiredInvitations', expired_count,
    'purgedContactRecords', purged_count,
    'serverSequence', sequence_value,
    'confirmedAt', clock_timestamp()
  );
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'public.get_pachanga_club_foundation_flags_v1()'::regprocedure,
    'public.get_pachanga_club_foundation_snapshot_v1(uuid)'::regprocedure,
    'public.get_my_pachanga_club_foundation_v1()'::regprocedure,
    'public.get_pachanga_club_invitation_v1(uuid,text)'::regprocedure,
    'public.get_pachanga_public_club_v1(text)'::regprocedure,
    'public.purge_pachanga_club_invitation_contacts_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', signature);
  end loop;
end;
$$;

grant execute on function public.get_pachanga_club_foundation_flags_v1() to authenticated, service_role;
grant execute on function public.get_pachanga_club_foundation_snapshot_v1(uuid) to authenticated, service_role;
grant execute on function public.get_my_pachanga_club_foundation_v1() to authenticated, service_role;
grant execute on function public.get_pachanga_club_invitation_v1(uuid, text) to authenticated;
grant execute on function public.get_pachanga_public_club_v1(text) to anon, authenticated, service_role;
grant execute on function public.purge_pachanga_club_invitation_contacts_v1() to service_role;

create or replace function private.pachanga_club_can_read_invalidation_v1(
  target_club_id uuid,
  target_user_id uuid,
  target_group_id uuid,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select actor_id is not null and (
    private.pachanga_club_platform_can_v1(actor_id, 'clubs.read')
    or private.pachanga_club_can_v1(target_club_id, actor_id, 'read')
    or target_user_id = actor_id
    or exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_group_id and groups.owner_id = actor_id
    )
  );
$$;

revoke all on function private.pachanga_club_can_read_invalidation_v1(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.pachanga_club_can_read_invalidation_v1(uuid, uuid, uuid, uuid)
  to authenticated;

alter table public.pachanga_clubs enable row level security;
alter table public.pachanga_club_memberships enable row level security;
alter table public.pachanga_club_invitations enable row level security;
alter table public.pachanga_club_team_relationships enable row level security;
alter table public.pachanga_club_invalidations enable row level security;

revoke all on table public.pachanga_clubs from public, anon, authenticated;
revoke all on table public.pachanga_club_memberships from public, anon, authenticated;
revoke all on table public.pachanga_club_invitations from public, anon, authenticated;
revoke all on table public.pachanga_club_team_relationships from public, anon, authenticated;
revoke all on table public.pachanga_club_invalidations from public, anon, authenticated;
revoke all on table private.pachanga_club_foundation_settings from public, anon, authenticated;
revoke all on table private.pachanga_club_operation_receipts from public, anon, authenticated;
revoke all on table private.pachanga_club_events from public, anon, authenticated;
revoke all on table private.pachanga_club_invitation_secrets from public, anon, authenticated;

grant all on table public.pachanga_clubs to service_role;
grant all on table public.pachanga_club_memberships to service_role;
grant all on table public.pachanga_club_invitations to service_role;
grant all on table public.pachanga_club_team_relationships to service_role;
grant all on table public.pachanga_club_invalidations to service_role;
grant all on table private.pachanga_club_foundation_settings to service_role;
grant all on table private.pachanga_club_operation_receipts to service_role;
grant all on table private.pachanga_club_events to service_role;
grant all on table private.pachanga_club_invitation_secrets to service_role;
grant select on table public.pachanga_club_invalidations to authenticated;

drop policy if exists pachanga_club_invalidations_select_v1 on public.pachanga_club_invalidations;
create policy pachanga_club_invalidations_select_v1
on public.pachanga_club_invalidations
for select
to authenticated
using (private.pachanga_club_can_read_invalidation_v1(
  club_id, target_user_id, target_group_id, (select auth.uid())
));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables tables
       where tables.pubname = 'supabase_realtime'
         and tables.schemaname = 'public'
         and tables.tablename = 'pachanga_club_invalidations'
     ) then
    alter publication supabase_realtime add table public.pachanga_club_invalidations;
  end if;
end;
$$;

comment on table public.pachanga_clubs is
  'Canonical Club authority. A Club is not a pachanga_group and never inherits team ownership.';
comment on table public.pachanga_club_invalidations is
  'RLS-scoped invalidators only. Clients refetch canonical Club read models after each row.';
comment on table private.pachanga_club_invitation_secrets is
  'Private one-use invitation hashes. Plain tokens are never persisted; email contact is purged after retention.';
