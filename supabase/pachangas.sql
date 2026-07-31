create table if not exists public.pachanga_groups (
  id uuid primary key default gen_random_uuid(),
  invite_token uuid not null unique default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Equipo pachanguero',
  team_code text unique,
  billing_status text not null default 'trial',
  billing_trial_finalized_matches integer not null default 0,
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_price_id text,
  stripe_current_period_end timestamptz,
  billing_interval text,
  payload jsonb not null,
  payload_revision bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pachanga_group_members (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'player',
  display_name text,
  created_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create table if not exists public.pachanga_admin_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  token uuid not null unique default gen_random_uuid(),
  created_by uuid not null references auth.users(id) on delete cascade,
  accepted_by uuid references auth.users(id) on delete set null,
  accepted_at timestamptz,
  expires_at timestamptz not null default (now() + interval '14 days'),
  created_at timestamptz not null default now()
);

create table if not exists public.pachanga_group_backups (
  id uuid primary key default gen_random_uuid(),
  source_group_id uuid,
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  group_name text not null,
  team_code text,
  reason text not null default 'manual',
  payload jsonb not null,
  created_at timestamptz not null default now(),
  restored_at timestamptz,
  restored_group_id uuid
);

create table if not exists public.pachanga_player_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_group_id uuid references public.pachanga_groups(id) on delete set null,
  source_player_id text,
  display_name text not null default 'Jugador',
  phone text not null default '',
  avatar text,
  avatar_offset_x numeric,
  avatar_offset_y numeric,
  birth_date date,
  goalkeeper_only boolean not null default false,
  injured boolean not null default false,
  inactive boolean not null default false,
  imported_rating numeric,
  imported_rating_at timestamptz,
  imported_rating_from_group text,
  rating numeric not null default 5,
  ratings jsonb not null default '[]'::jsonb,
  rating_votes jsonb not null default '[]'::jsonb,
  assessment_summary jsonb not null default '{}'::jsonb,
  position text not null default 'Mediocentro / pivote',
  outfield_position text,
  market_enabled boolean not null default false,
  market_zones text not null default '',
  market_zones_geo jsonb not null default '[]'::jsonb,
  market_availability text not null default '',
  market_bio text not null default '',
  market_modalities text[] not null default '{}',
  market_open_to_group boolean not null default true,
  market_open_to_guest boolean not null default true,
  stats jsonb not null default '{}'::jsonb,
  profile_version bigint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (rating >= 1 and rating <= 10),
  check (imported_rating is null or (imported_rating >= 1 and imported_rating <= 10))
);

create table if not exists public.pachanga_player_assessments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete set null,
  assessment_kind text not null,
  engine_version text not null,
  questionnaire_version text not null,
  idempotency_key uuid not null,
  input jsonb not null,
  result jsonb not null,
  rating numeric not null,
  facet_ratings jsonb not null default '{}'::jsonb,
  reliability numeric,
  completed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (assessment_kind in ('initial', 'advanced')),
  check (rating >= 1 and rating <= 10),
  check (reliability is null or (reliability >= 0 and reliability <= 100))
);

create table if not exists public.pachanga_market_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete set null,
  source_group_id uuid references public.pachanga_groups(id) on delete set null,
  source_player_id text not null,
  display_name text not null,
  group_name text,
  avatar text,
  avatar_offset_x numeric,
  avatar_offset_y numeric,
  birth_date date,
  position text not null default 'Mediocentro / pivote',
  goalkeeper_only boolean not null default false,
  media numeric not null default 5,
  appearances integer not null default 0,
  goals integer not null default 0,
  wins integer not null default 0,
  zones text[] not null default '{}',
  zones_geo jsonb not null default '[]'::jsonb,
  availability_text text not null default '',
  modalities text[] not null default '{}',
  open_to_guest boolean not null default true,
  open_to_group boolean not null default true,
  bio text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.pachanga_open_matches (
  id uuid primary key default gen_random_uuid(),
  source_group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  source_match_id text not null,
  group_name text not null default 'Grupo de pachangas',
  title text not null default 'Partido abierto',
  date timestamptz not null,
  date_text text not null default '',
  day text not null default '',
  modality text not null default 'futbol7',
  zone text not null default '',
  place_id text,
  lat numeric,
  lng numeric,
  field_name text not null default 'Campo por confirmar',
  field_cost numeric not null default 0,
  price_per_player numeric not null default 0,
  target_players integer not null default 0,
  confirmed_count integer not null default 0,
  open_slots integer not null default 0,
  min_media numeric not null default 0,
  max_media numeric not null default 10,
  positions text[] not null default '{}',
  requires_approval boolean not null default true,
  guests_pay boolean not null default true,
  group_level numeric,
  match_url text not null default '',
  active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_group_id, source_match_id)
);

create table if not exists public.pachanga_open_match_requests (
  id uuid primary key default gen_random_uuid(),
  open_match_id uuid not null references public.pachanga_open_matches(id) on delete cascade,
  source_group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  source_match_id text not null,
  requester_user_id uuid not null references auth.users(id) on delete cascade,
  requester_profile_id uuid references public.pachanga_market_profiles(id) on delete set null,
  requester_name text not null default 'Jugador',
  avatar text,
  avatar_offset_x numeric,
  avatar_offset_y numeric,
  birth_date date,
  position text not null default 'Mediocentro / pivote',
  goalkeeper_only boolean not null default false,
  media numeric not null default 5,
  message text not null default '',
  status text not null default 'pending',
  player_id text,
  requested_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(open_match_id, requester_user_id)
);

create table if not exists public.pachanga_match_read_model (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text not null,
  match_state text not null default 'draft',
  match_version bigint not null default 0,
  configured boolean not null default false,
  lineup_closed boolean not null default false,
  finalized boolean not null default false,
  target_players integer not null default 0,
  reserve_limit integer not null default 0,
  payer_player_id text,
  score_a integer,
  score_b integer,
  source_payload_revision bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (group_id, match_id),
  check (match_state in ('draft', 'published', 'lineup_open', 'lineup_closed', 'played', 'finalized', 'historical')),
  check (target_players >= 0),
  check (reserve_limit >= 0),
  check (score_a is null or score_a >= 0),
  check (score_b is null or score_b >= 0)
);

create table if not exists public.pachanga_match_participants (
  group_id uuid not null,
  match_id text not null,
  player_id text not null,
  status text not null default 'no',
  seat_kind text not null default 'none',
  joined_at timestamptz,
  paid boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (group_id, match_id, player_id),
  foreign key (group_id, match_id) references public.pachanga_match_read_model(group_id, match_id) on delete cascade,
  check (status in ('voy', 'duda', 'no')),
  check (seat_kind in ('playing', 'reserve', 'waiting', 'none'))
);

create table if not exists public.pachanga_match_scorers (
  group_id uuid not null,
  match_id text not null,
  player_id text not null,
  goals integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (group_id, match_id, player_id),
  foreign key (group_id, match_id) references public.pachanga_match_read_model(group_id, match_id) on delete cascade,
  check (goals >= 0)
);

create table if not exists public.pachanga_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  operation_id uuid not null,
  operation_type text not null,
  user_id uuid references auth.users(id) on delete set null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  unique(group_id, operation_id)
);

create table if not exists public.pachanga_group_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text,
  operation_id uuid,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  admin_action boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.pachanga_stripe_webhook_events (
  event_id text primary key,
  event_type text not null,
  processing_status text not null default 'processing',
  processed_at timestamptz,
  error_message text,
  payload jsonb not null default '{}'::jsonb
);

alter table public.pachanga_stripe_webhook_events
add column if not exists processing_status text not null default 'processing',
add column if not exists error_message text;

alter table public.pachanga_stripe_webhook_events
alter column processed_at drop not null;

alter table public.pachanga_market_profiles
add column if not exists player_profile_id uuid references public.pachanga_player_profiles(id) on delete set null,
add column if not exists zones_geo jsonb not null default '[]'::jsonb;

alter table public.pachanga_player_profiles
add column if not exists assessment_summary jsonb not null default '{}'::jsonb;

create or replace function public.new_pachanga_team_code()
returns text
language sql
set search_path = public
as $$
  select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
$$;

update public.pachanga_groups
set team_code = public.new_pachanga_team_code()
where team_code is null;

alter table public.pachanga_groups
alter column team_code set default public.new_pachanga_team_code();

alter table public.pachanga_groups
alter column team_code set not null;

alter table public.pachanga_groups
add column if not exists payload_revision bigint not null default 0;

alter table public.pachanga_groups
add column if not exists billing_status text not null default 'trial',
add column if not exists billing_trial_finalized_matches integer not null default 0,
add column if not exists stripe_customer_id text,
add column if not exists stripe_subscription_id text,
add column if not exists stripe_price_id text,
add column if not exists stripe_current_period_end timestamptz,
add column if not exists billing_interval text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_open_match_requests_status_check'
  ) then
    alter table public.pachanga_open_match_requests
    add constraint pachanga_open_match_requests_status_check
    check (status in ('pending', 'accepted', 'rejected', 'cancelled'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_stripe_webhook_events_status_check'
  ) then
    alter table public.pachanga_stripe_webhook_events
    add constraint pachanga_stripe_webhook_events_status_check
    check (processing_status in ('processing', 'processed', 'failed'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_groups_billing_status_check'
  ) then
    alter table public.pachanga_groups
    add constraint pachanga_groups_billing_status_check
    check (billing_status in ('trial', 'active', 'trialing', 'past_due', 'canceled', 'unpaid', 'incomplete'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_groups_billing_interval_check'
  ) then
    alter table public.pachanga_groups
    add constraint pachanga_groups_billing_interval_check
    check (billing_interval is null or billing_interval in ('month', 'year'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'pachanga_group_members_role_check'
  ) then
    alter table public.pachanga_group_members
    add constraint pachanga_group_members_role_check
    check (role in ('owner', 'admin', 'player'));
  end if;
end;
$$;

update public.pachanga_group_members members
set role = 'owner'
from public.pachanga_groups groups
where members.group_id = groups.id
  and members.user_id = groups.owner_id;

create index if not exists pachanga_groups_owner_id_idx
on public.pachanga_groups(owner_id);

create unique index if not exists pachanga_groups_team_code_idx
on public.pachanga_groups(team_code);

create index if not exists pachanga_groups_stripe_customer_id_idx
on public.pachanga_groups(stripe_customer_id);

create unique index if not exists pachanga_groups_stripe_subscription_id_idx
on public.pachanga_groups(stripe_subscription_id)
where stripe_subscription_id is not null;

create index if not exists pachanga_group_members_user_id_idx
on public.pachanga_group_members(user_id);

create index if not exists pachanga_admin_invites_group_id_idx
on public.pachanga_admin_invites(group_id);

create index if not exists pachanga_admin_invites_created_by_idx
on public.pachanga_admin_invites(created_by);

create index if not exists pachanga_admin_invites_accepted_by_idx
on public.pachanga_admin_invites(accepted_by)
where accepted_by is not null;

create index if not exists pachanga_admin_invites_token_idx
on public.pachanga_admin_invites(token);

create index if not exists pachanga_group_backups_owner_id_idx
on public.pachanga_group_backups(owner_id);

create index if not exists pachanga_group_backups_created_by_idx
on public.pachanga_group_backups(created_by);

create index if not exists pachanga_group_backups_source_group_id_idx
on public.pachanga_group_backups(source_group_id);

create index if not exists pachanga_group_backups_created_at_idx
on public.pachanga_group_backups(created_at desc);

create unique index if not exists pachanga_player_profiles_user_id_idx
on public.pachanga_player_profiles(user_id);

create index if not exists pachanga_player_profiles_source_group_id_idx
on public.pachanga_player_profiles(source_group_id)
where source_group_id is not null;

create index if not exists pachanga_player_profiles_active_market_idx
on public.pachanga_player_profiles(market_enabled, rating desc)
where market_enabled = true;

create unique index if not exists pachanga_player_assessments_user_kind_idx
on public.pachanga_player_assessments(user_id, assessment_kind);

create unique index if not exists pachanga_player_assessments_user_idempotency_idx
on public.pachanga_player_assessments(user_id, idempotency_key);

create index if not exists pachanga_player_assessments_profile_kind_idx
on public.pachanga_player_assessments(player_profile_id, assessment_kind)
where player_profile_id is not null;

create unique index if not exists pachanga_market_profiles_user_id_idx
on public.pachanga_market_profiles(user_id);

create index if not exists pachanga_market_profiles_player_profile_id_idx
on public.pachanga_market_profiles(player_profile_id)
where player_profile_id is not null;

create index if not exists pachanga_market_profiles_active_media_idx
on public.pachanga_market_profiles(active, media desc);

create index if not exists pachanga_market_profiles_source_group_id_idx
on public.pachanga_market_profiles(source_group_id);

create index if not exists pachanga_market_profiles_zones_idx
on public.pachanga_market_profiles using gin(zones);

create index if not exists pachanga_market_profiles_zones_geo_idx
on public.pachanga_market_profiles using gin(zones_geo);

create index if not exists pachanga_market_profiles_modalities_idx
on public.pachanga_market_profiles using gin(modalities);

create index if not exists pachanga_open_matches_active_date_idx
on public.pachanga_open_matches(active, date);

create index if not exists pachanga_open_matches_modality_idx
on public.pachanga_open_matches(modality);

create index if not exists pachanga_open_matches_positions_idx
on public.pachanga_open_matches using gin(positions);

create index if not exists pachanga_open_matches_source_idx
on public.pachanga_open_matches(source_group_id, source_match_id);

create index if not exists pachanga_open_matches_created_by_idx
on public.pachanga_open_matches(created_by)
where created_by is not null;

create index if not exists pachanga_open_match_requests_open_match_idx
on public.pachanga_open_match_requests(open_match_id, status, requested_at);

create index if not exists pachanga_open_match_requests_group_match_idx
on public.pachanga_open_match_requests(source_group_id, source_match_id, status, requested_at);

create index if not exists pachanga_open_match_requests_user_idx
on public.pachanga_open_match_requests(requester_user_id, status, requested_at desc);

create index if not exists pachanga_open_match_requests_requester_profile_idx
on public.pachanga_open_match_requests(requester_profile_id)
where requester_profile_id is not null;

create index if not exists pachanga_open_match_requests_decided_by_idx
on public.pachanga_open_match_requests(decided_by)
where decided_by is not null;

create index if not exists pachanga_match_read_model_state_idx
on public.pachanga_match_read_model(group_id, match_state, updated_at desc);

create index if not exists pachanga_match_participants_seat_idx
on public.pachanga_match_participants(group_id, match_id, seat_kind, joined_at);

create index if not exists pachanga_match_participants_player_idx
on public.pachanga_match_participants(group_id, player_id, updated_at desc);

create index if not exists pachanga_match_scorers_match_idx
on public.pachanga_match_scorers(group_id, match_id, goals desc);

create index if not exists pachanga_operation_receipts_user_idx
on public.pachanga_operation_receipts(user_id, created_at desc)
where user_id is not null;

create index if not exists pachanga_group_events_group_idx
on public.pachanga_group_events(group_id, created_at desc);

create index if not exists pachanga_group_events_actor_id_idx
on public.pachanga_group_events(actor_id, created_at desc)
where actor_id is not null;

create index if not exists pachanga_group_events_operation_idx
on public.pachanga_group_events(group_id, operation_id)
where operation_id is not null;

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.pachanga_groups to authenticated;
grant select, insert, update on public.pachanga_group_members to authenticated;
grant select, insert, update on public.pachanga_admin_invites to authenticated;
grant select on public.pachanga_group_backups to authenticated;
grant select on public.pachanga_player_profiles to authenticated;
grant select on public.pachanga_player_assessments to authenticated;
grant select on public.pachanga_market_profiles to authenticated;
grant select on public.pachanga_open_matches to authenticated;
grant select on public.pachanga_open_match_requests to authenticated;
grant select on public.pachanga_match_read_model to authenticated;
grant select on public.pachanga_match_participants to authenticated;
grant select on public.pachanga_match_scorers to authenticated;
grant select on public.pachanga_group_events to authenticated;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  new.payload_revision = coalesce(old.payload_revision, 0) + 1;
  return new;
end;
$$;

create or replace function public.is_registered_pachanga_user()
returns boolean
language sql
set search_path = public
stable
as $$
  select (select auth.uid()) is not null
    and coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false;
$$;

drop trigger if exists set_pachanga_groups_updated_at on public.pachanga_groups;
create trigger set_pachanga_groups_updated_at
before update on public.pachanga_groups
for each row
execute function public.set_updated_at();

create or replace function public.is_pachanga_group_member(target_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.pachanga_group_members members
    where members.group_id = target_group_id
      and members.user_id = auth.uid()
  );
$$;

create or replace function public.is_pachanga_group_owner(target_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.pachanga_groups groups
    where groups.id = target_group_id
      and groups.owner_id = auth.uid()
  );
$$;

create or replace function public.is_pachanga_group_admin(target_group_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.pachanga_group_members members
    where members.group_id = target_group_id
      and members.user_id = auth.uid()
      and members.role in ('owner', 'admin')
  );
$$;

revoke all on function public.is_pachanga_group_member(uuid) from public;
revoke all on function public.is_pachanga_group_owner(uuid) from public;
revoke all on function public.is_pachanga_group_admin(uuid) from public;
revoke execute on function public.is_pachanga_group_member(uuid) from anon;
revoke execute on function public.is_pachanga_group_owner(uuid) from anon;
revoke execute on function public.is_pachanga_group_admin(uuid) from anon;
grant execute on function public.is_pachanga_group_member(uuid) to authenticated;
grant execute on function public.is_pachanga_group_owner(uuid) to authenticated;
grant execute on function public.is_pachanga_group_admin(uuid) to authenticated;

alter table public.pachanga_groups enable row level security;
alter table public.pachanga_group_members enable row level security;
alter table public.pachanga_admin_invites enable row level security;
alter table public.pachanga_group_backups enable row level security;
alter table public.pachanga_player_profiles enable row level security;
alter table public.pachanga_player_assessments enable row level security;
alter table public.pachanga_market_profiles enable row level security;
alter table public.pachanga_open_matches enable row level security;
alter table public.pachanga_open_match_requests enable row level security;
alter table public.pachanga_match_read_model enable row level security;
alter table public.pachanga_match_participants enable row level security;
alter table public.pachanga_match_scorers enable row level security;
alter table public.pachanga_operation_receipts enable row level security;
alter table public.pachanga_group_events enable row level security;
alter table public.pachanga_stripe_webhook_events enable row level security;

drop policy if exists "Owners can create groups" on public.pachanga_groups;
create policy "Owners can create groups"
on public.pachanga_groups
for insert
to authenticated
with check (
  public.is_registered_pachanga_user()
  and (select auth.uid()) = owner_id
);

drop policy if exists "Members can read groups" on public.pachanga_groups;
create policy "Members can read groups"
on public.pachanga_groups
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    owner_id = (select auth.uid())
    or public.is_pachanga_group_member(id)
  )
);

drop policy if exists "Members can update groups" on public.pachanga_groups;
drop policy if exists "Admins can update groups" on public.pachanga_groups;
create policy "Admins can update groups"
on public.pachanga_groups
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(id)
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(id)
);

drop policy if exists "Owners can delete groups" on public.pachanga_groups;
drop policy if exists "Admins can delete groups" on public.pachanga_groups;
create policy "Admins can delete groups"
on public.pachanga_groups
for delete
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_admin(id)
);

drop policy if exists "Members can read memberships" on public.pachanga_group_members;
create policy "Members can read memberships"
on public.pachanga_group_members
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    user_id = (select auth.uid())
    or public.is_pachanga_group_owner(group_id)
    or public.is_pachanga_group_member(group_id)
  )
);

drop policy if exists "Owners can add themselves as members" on public.pachanga_group_members;
create policy "Owners can add themselves as members"
on public.pachanga_group_members
for insert
to authenticated
with check (
  public.is_registered_pachanga_user()
  and user_id = (select auth.uid())
  and public.is_pachanga_group_owner(group_id)
);

drop policy if exists "Admins can update member roles" on public.pachanga_group_members;
drop policy if exists "Owners can update member roles" on public.pachanga_group_members;
create policy "Owners can update member roles"
on public.pachanga_group_members
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
  and role <> 'owner'
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
  and role in ('admin', 'player')
);

drop policy if exists "Admins can create admin invites" on public.pachanga_admin_invites;
drop policy if exists "Owners can create admin invites" on public.pachanga_admin_invites;
create policy "Owners can create admin invites"
on public.pachanga_admin_invites
for insert
to authenticated
with check (
  public.is_registered_pachanga_user()
  and created_by = (select auth.uid())
  and public.is_pachanga_group_owner(group_id)
);

drop policy if exists "Admins can read admin invites" on public.pachanga_admin_invites;
drop policy if exists "Owners can read admin invites" on public.pachanga_admin_invites;
create policy "Owners can read admin invites"
on public.pachanga_admin_invites
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
);

drop policy if exists "Admins can update admin invites" on public.pachanga_admin_invites;
drop policy if exists "Owners can update admin invites" on public.pachanga_admin_invites;
create policy "Owners can update admin invites"
on public.pachanga_admin_invites
for update
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
)
with check (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_owner(group_id)
);

drop policy if exists "Users can read recoverable backups" on public.pachanga_group_backups;
create policy "Users can read recoverable backups"
on public.pachanga_group_backups
for select
to authenticated
using (
  coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false
  and (
    owner_id = (select auth.uid())
    or created_by = (select auth.uid())
    or (
      source_group_id is not null
      and public.is_pachanga_group_admin(source_group_id)
    )
  )
);

drop policy if exists "Users can read own universal player profile" on public.pachanga_player_profiles;
create policy "Users can read own universal player profile"
on public.pachanga_player_profiles
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and user_id = (select auth.uid())
);

drop policy if exists "Users can read own player assessments" on public.pachanga_player_assessments;
create policy "Users can read own player assessments"
on public.pachanga_player_assessments
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and user_id = (select auth.uid())
);

drop policy if exists "Authenticated users can read active market profiles" on public.pachanga_market_profiles;
create policy "Authenticated users can read active market profiles"
on public.pachanga_market_profiles
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    active = true
    or user_id = (select auth.uid())
  )
);

drop policy if exists "Authenticated users can read active open matches" on public.pachanga_open_matches;
create policy "Authenticated users can read active open matches"
on public.pachanga_open_matches
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and active = true
);

drop policy if exists "Users and admins can read open match requests" on public.pachanga_open_match_requests;
create policy "Users and admins can read open match requests"
on public.pachanga_open_match_requests
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    requester_user_id = (select auth.uid())
    or public.is_pachanga_group_admin(source_group_id)
  )
);

drop policy if exists "Members can read normalized matches" on public.pachanga_match_read_model;
create policy "Members can read normalized matches"
on public.pachanga_match_read_model
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_member(group_id)
);

drop policy if exists "Members can read normalized participants" on public.pachanga_match_participants;
create policy "Members can read normalized participants"
on public.pachanga_match_participants
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_member(group_id)
);

drop policy if exists "Members can read normalized scorers" on public.pachanga_match_scorers;
create policy "Members can read normalized scorers"
on public.pachanga_match_scorers
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_member(group_id)
);

drop policy if exists "Users can read own operation receipts" on public.pachanga_operation_receipts;
create policy "Users can read own operation receipts"
on public.pachanga_operation_receipts
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and (
    user_id = (select auth.uid())
    or public.is_pachanga_group_admin(group_id)
  )
);

drop policy if exists "Members can read group events" on public.pachanga_group_events;
create policy "Members can read group events"
on public.pachanga_group_events
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and public.is_pachanga_group_member(group_id)
);

create or replace function public.pachanga_match_state(match_payload jsonb)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when coalesce((match_payload ->> 'closed')::boolean, false) then 'finalized'
    when match_payload ? 'scoreA' or match_payload ? 'scoreB' then 'played'
    when coalesce((match_payload ->> 'lineupClosed')::boolean, false) then 'lineup_closed'
    when coalesce((match_payload ->> 'configured')::boolean, false)
      and coalesce((match_payload ->> 'publicOpen')::boolean, false) then 'published'
    when coalesce((match_payload ->> 'configured')::boolean, false) then 'lineup_open'
    else 'draft'
  end;
$$;

create or replace function public.record_pachanga_group_event(
  target_group_id uuid,
  target_match_id text,
  target_event_type text,
  event_payload jsonb default '{}'::jsonb,
  target_operation_id uuid default null,
  is_admin_action boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.pachanga_group_events (
    group_id,
    match_id,
    operation_id,
    actor_id,
    event_type,
    admin_action,
    payload
  )
  values (
    target_group_id,
    nullif(target_match_id, ''),
    target_operation_id,
    auth.uid(),
    left(coalesce(nullif(trim(target_event_type), ''), 'unknown'), 120),
    coalesce(is_admin_action, false),
    coalesce(event_payload, '{}'::jsonb)
  );
end;
$$;

create or replace function public.remember_pachanga_operation(
  target_group_id uuid,
  target_operation_id uuid,
  target_operation_type text,
  operation_response jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  stored_response jsonb;
begin
  if target_operation_id is null then
    return operation_response;
  end if;

  insert into public.pachanga_operation_receipts (
    group_id,
    operation_id,
    operation_type,
    user_id,
    response
  )
  values (
    target_group_id,
    target_operation_id,
    left(coalesce(nullif(trim(target_operation_type), ''), 'unknown'), 120),
    auth.uid(),
    operation_response
  )
  on conflict (group_id, operation_id) do nothing;

  select response into stored_response
  from public.pachanga_operation_receipts
  where group_id = target_group_id
    and operation_id = target_operation_id;

  return coalesce(stored_response, operation_response);
end;
$$;

create or replace function public.sync_pachanga_match_read_model(
  target_group_id uuid,
  match_payload jsonb,
  source_revision bigint default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_match_id text;
  next_reserve_limit integer;
  next_state text;
  next_target_players integer;
begin
  current_match_id := match_payload ->> 'id';
  if current_match_id is null or current_match_id = '' then
    return;
  end if;

  next_target_players := greatest(0, coalesce((match_payload ->> 'targetPlayers')::integer, 0));
  next_reserve_limit := case
    when coalesce((match_payload ->> 'reservesAttend')::boolean, false)
      then greatest(0, coalesce((match_payload ->> 'reserveLimit')::integer, 0))
    else 0
  end;
  next_state := public.pachanga_match_state(match_payload);

  insert into public.pachanga_match_read_model (
    group_id,
    match_id,
    match_state,
    configured,
    lineup_closed,
    finalized,
    target_players,
    reserve_limit,
    payer_player_id,
    score_a,
    score_b,
    source_payload_revision,
    updated_at
  )
  values (
    target_group_id,
    current_match_id,
    next_state,
    coalesce((match_payload ->> 'configured')::boolean, false),
    coalesce((match_payload ->> 'lineupClosed')::boolean, false),
    coalesce((match_payload ->> 'closed')::boolean, false) or match_payload ? 'scoreA',
    next_target_players,
    next_reserve_limit,
    nullif(match_payload ->> 'payerId', ''),
    case when match_payload ? 'scoreA' then greatest(0, coalesce((match_payload ->> 'scoreA')::integer, 0)) else null end,
    case when match_payload ? 'scoreB' then greatest(0, coalesce((match_payload ->> 'scoreB')::integer, 0)) else null end,
    coalesce(source_revision, 0),
    now()
  )
  on conflict (group_id, match_id) do update set
    match_state = excluded.match_state,
    match_version = public.pachanga_match_read_model.match_version + 1,
    configured = excluded.configured,
    lineup_closed = excluded.lineup_closed,
    finalized = excluded.finalized,
    target_players = excluded.target_players,
    reserve_limit = excluded.reserve_limit,
    payer_player_id = excluded.payer_player_id,
    score_a = excluded.score_a,
    score_b = excluded.score_b,
    source_payload_revision = excluded.source_payload_revision,
    updated_at = now();

  delete from public.pachanga_match_participants
  where group_id = target_group_id
    and match_id = current_match_id;

  with entries as (
    select
      value,
      ordinality,
      value ->> 'playerId' as player_id,
      case
        when value ->> 'status' in ('voy', 'duda', 'no') then value ->> 'status'
        else 'no'
      end as status
    from jsonb_array_elements(coalesce(match_payload -> 'players', '[]'::jsonb)) with ordinality as source(value, ordinality)
    where nullif(value ->> 'playerId', '') is not null
  ),
  ordered_going as (
    select
      player_id,
      row_number() over (
        order by coalesce(value ->> 'joinedAt', '9999-12-31T23:59:59.999Z'), ordinality
      ) as seat_order
    from entries
    where status = 'voy'
  )
  insert into public.pachanga_match_participants (
    group_id,
    match_id,
    player_id,
    status,
    seat_kind,
    joined_at,
    paid,
    updated_at
  )
  select
    target_group_id,
    current_match_id,
    entries.player_id,
    entries.status,
    case
      when entries.status <> 'voy' then 'none'
      when ordered_going.seat_order <= next_target_players then 'playing'
      when ordered_going.seat_order <= next_target_players + next_reserve_limit then 'reserve'
      else 'waiting'
    end,
    case
      when coalesce(entries.value ->> 'joinedAt', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
        then (entries.value ->> 'joinedAt')::timestamptz
      else null
    end,
    coalesce((entries.value ->> 'paid')::boolean, false),
    now()
  from entries
  left join ordered_going on ordered_going.player_id = entries.player_id;

  delete from public.pachanga_match_scorers
  where group_id = target_group_id
    and match_id = current_match_id;

  insert into public.pachanga_match_scorers (
    group_id,
    match_id,
    player_id,
    goals,
    updated_at
  )
  select
    target_group_id,
    current_match_id,
    value ->> 'playerId',
    greatest(0, coalesce((value ->> 'goals')::integer, 0)),
    now()
  from jsonb_array_elements(coalesce(match_payload -> 'scorers', '[]'::jsonb)) as scorer(value)
  where nullif(value ->> 'playerId', '') is not null
    and greatest(0, coalesce((value ->> 'goals')::integer, 0)) > 0
  on conflict (group_id, match_id, player_id) do update set
    goals = public.pachanga_match_scorers.goals + excluded.goals,
    updated_at = now();
end;
$$;

create or replace function public.sync_pachanga_group_read_model(
  target_group_id uuid,
  group_payload jsonb,
  source_revision bigint default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  match_entry jsonb;
begin
  delete from public.pachanga_match_read_model read_model
  where read_model.group_id = target_group_id
    and not exists (
      select 1
      from jsonb_array_elements(coalesce(group_payload -> 'matches', '[]'::jsonb)) as matches(value)
      where matches.value ->> 'id' = read_model.match_id
    );

  for match_entry in
    select value
    from jsonb_array_elements(coalesce(group_payload -> 'matches', '[]'::jsonb)) as matches(value)
  loop
    perform public.sync_pachanga_match_read_model(target_group_id, match_entry, source_revision);
  end loop;
end;
$$;

create or replace function public.pachanga_player_profile_patch(target_profile_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  profile public.pachanga_player_profiles%rowtype;
begin
  select * into profile
  from public.pachanga_player_profiles
  where id = target_profile_id;

  if not found then
    return '{}'::jsonb;
  end if;

  return jsonb_strip_nulls(
    jsonb_build_object(
      'globalPlayerProfileId', profile.id::text,
      'ownerUserId', profile.user_id::text,
      'name', profile.display_name,
      'phone', profile.phone,
      'avatar', profile.avatar,
      'avatarOffsetX', profile.avatar_offset_x,
      'avatarOffsetY', profile.avatar_offset_y,
      'birthDate', profile.birth_date,
      'goalkeeperOnly', profile.goalkeeper_only,
      'injured', profile.injured,
      'inactive', profile.inactive,
      'importedRating', profile.imported_rating,
      'importedRatingAt', case
        when profile.imported_rating_at is not null then to_char(profile.imported_rating_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
        else null
      end,
      'importedRatingFromGroup', profile.imported_rating_from_group,
      'rating', profile.rating,
      'ratings', profile.ratings,
      'ratingVotes', profile.rating_votes,
      'assessmentSummary', profile.assessment_summary,
      'position', profile.position,
      'outfieldPosition', profile.outfield_position,
      'marketEnabled', profile.market_enabled,
      'marketZones', profile.market_zones,
      'marketZonesGeo', profile.market_zones_geo,
      'marketAvailability', profile.market_availability,
      'marketBio', profile.market_bio,
      'marketModalities', to_jsonb(profile.market_modalities),
      'marketOpenToGroup', profile.market_open_to_group,
      'marketOpenToGuest', profile.market_open_to_guest
    )
  );
end;
$$;

create or replace function public.upsert_pachanga_player_profile_from_player(
  target_group_id uuid,
  target_player_id text,
  player_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  global_profile_id uuid;
  owner_id uuid;
  safe_avatar_offset_x numeric;
  safe_avatar_offset_y numeric;
  safe_birth_date date;
  safe_imported_rating numeric;
  safe_imported_rating_at timestamptz;
  safe_market_modalities text[];
  safe_rating numeric;
  safe_stats jsonb;
begin
  if coalesce(player_payload ->> 'ownerUserId', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;

  owner_id := (player_payload ->> 'ownerUserId')::uuid;

  safe_avatar_offset_x := case
    when coalesce(player_payload ->> 'avatarOffsetX', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then least(100::numeric, greatest(0::numeric, (player_payload ->> 'avatarOffsetX')::numeric))
    else null
  end;
  safe_avatar_offset_y := case
    when coalesce(player_payload ->> 'avatarOffsetY', '') ~ '^-?[0-9]+(\.[0-9]+)?$'
      then least(100::numeric, greatest(0::numeric, (player_payload ->> 'avatarOffsetY')::numeric))
    else null
  end;
  safe_birth_date := case
    when coalesce(player_payload ->> 'birthDate', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then (player_payload ->> 'birthDate')::date
    else null
  end;
  safe_imported_rating := case
    when coalesce(player_payload ->> 'importedRating', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then greatest(1::numeric, least(10::numeric, (player_payload ->> 'importedRating')::numeric))
    else null
  end;
  safe_imported_rating_at := case
    when coalesce(player_payload ->> 'importedRatingAt', '') ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' then (player_payload ->> 'importedRatingAt')::timestamptz
    else null
  end;
  safe_rating := case
    when coalesce(player_payload ->> 'rating', '') ~ '^[0-9]+(\.[0-9]+)?$'
      then greatest(1::numeric, least(10::numeric, (player_payload ->> 'rating')::numeric))
    when safe_imported_rating is not null then safe_imported_rating
    else 5
  end;

  select coalesce(array_agg(value), '{}'::text[])
  into safe_market_modalities
  from (
    select distinct value
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(player_payload -> 'marketModalities') = 'array' then player_payload -> 'marketModalities'
        else '[]'::jsonb
      end
    ) as modalities(value)
    where value in ('sala', 'futbol7', 'futbol11')
  ) as modality_values;

  safe_stats := jsonb_build_object(
    'goals', case
      when coalesce(player_payload ->> 'goals', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'goals')::integer)
      else 0
    end,
    'assists', case
      when coalesce(player_payload ->> 'assists', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'assists')::integer)
      else 0
    end,
    'appearances', case
      when coalesce(player_payload ->> 'appearances', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'appearances')::integer)
      else 0
    end,
    'wins', case
      when coalesce(player_payload ->> 'wins', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'wins')::integer)
      else 0
    end,
    'lateCancels', case
      when coalesce(player_payload ->> 'lateCancels', '') ~ '^[0-9]+$' then greatest(0, (player_payload ->> 'lateCancels')::integer)
      else 0
    end
  );

  insert into public.pachanga_player_profiles (
    user_id,
    source_group_id,
    source_player_id,
    display_name,
    phone,
    avatar,
    avatar_offset_x,
    avatar_offset_y,
    birth_date,
    goalkeeper_only,
    injured,
    inactive,
    imported_rating,
    imported_rating_at,
    imported_rating_from_group,
    rating,
    ratings,
    rating_votes,
    assessment_summary,
    position,
    outfield_position,
    market_enabled,
    market_zones,
    market_zones_geo,
    market_availability,
    market_bio,
    market_modalities,
    market_open_to_group,
    market_open_to_guest,
    stats
  )
  values (
    owner_id,
    target_group_id,
    nullif(trim(coalesce(target_player_id, player_payload ->> 'id', '')), ''),
    left(coalesce(nullif(trim(player_payload ->> 'name'), ''), 'Jugador'), 80),
    left(coalesce(player_payload ->> 'phone', ''), 40),
    nullif(player_payload ->> 'avatar', ''),
    safe_avatar_offset_x,
    safe_avatar_offset_y,
    safe_birth_date,
    coalesce((player_payload ->> 'goalkeeperOnly')::boolean, false),
    coalesce((player_payload ->> 'injured')::boolean, false),
    coalesce((player_payload ->> 'inactive')::boolean, false),
    safe_imported_rating,
    safe_imported_rating_at,
    nullif(left(trim(coalesce(player_payload ->> 'importedRatingFromGroup', '')), 120), ''),
    safe_rating,
    case when jsonb_typeof(player_payload -> 'ratings') = 'array' then player_payload -> 'ratings' else '[]'::jsonb end,
    case when jsonb_typeof(player_payload -> 'ratingVotes') = 'array' then player_payload -> 'ratingVotes' else '[]'::jsonb end,
    case when jsonb_typeof(player_payload -> 'assessmentSummary') = 'object' then player_payload -> 'assessmentSummary' else '{}'::jsonb end,
    left(coalesce(nullif(trim(player_payload ->> 'position'), ''), 'Mediocentro / pivote'), 80),
    nullif(left(trim(coalesce(player_payload ->> 'outfieldPosition', '')), 80), ''),
    coalesce((player_payload ->> 'marketEnabled')::boolean, false),
    left(coalesce(player_payload ->> 'marketZones', ''), 320),
    case when jsonb_typeof(player_payload -> 'marketZonesGeo') = 'array' then player_payload -> 'marketZonesGeo' else '[]'::jsonb end,
    left(coalesce(player_payload ->> 'marketAvailability', ''), 240),
    left(coalesce(player_payload ->> 'marketBio', ''), 280),
    safe_market_modalities,
    coalesce((player_payload ->> 'marketOpenToGroup')::boolean, true),
    coalesce((player_payload ->> 'marketOpenToGuest')::boolean, true),
    safe_stats
  )
  on conflict (user_id) do update set
    source_group_id = excluded.source_group_id,
    source_player_id = excluded.source_player_id,
    display_name = excluded.display_name,
    phone = excluded.phone,
    avatar = excluded.avatar,
    avatar_offset_x = excluded.avatar_offset_x,
    avatar_offset_y = excluded.avatar_offset_y,
    birth_date = excluded.birth_date,
    goalkeeper_only = excluded.goalkeeper_only,
    injured = excluded.injured,
    inactive = excluded.inactive,
    imported_rating = coalesce(excluded.imported_rating, public.pachanga_player_profiles.imported_rating),
    imported_rating_at = coalesce(excluded.imported_rating_at, public.pachanga_player_profiles.imported_rating_at),
    imported_rating_from_group = coalesce(excluded.imported_rating_from_group, public.pachanga_player_profiles.imported_rating_from_group),
    rating = excluded.rating,
    ratings = excluded.ratings,
    rating_votes = excluded.rating_votes,
    assessment_summary = case
      when excluded.assessment_summary <> '{}'::jsonb then excluded.assessment_summary
      else public.pachanga_player_profiles.assessment_summary
    end,
    position = excluded.position,
    outfield_position = excluded.outfield_position,
    market_enabled = excluded.market_enabled,
    market_zones = excluded.market_zones,
    market_zones_geo = excluded.market_zones_geo,
    market_availability = excluded.market_availability,
    market_bio = excluded.market_bio,
    market_modalities = excluded.market_modalities,
    market_open_to_group = excluded.market_open_to_group,
    market_open_to_guest = excluded.market_open_to_guest,
    stats = excluded.stats,
    profile_version = public.pachanga_player_profiles.profile_version + 1,
    updated_at = now()
  returning id into global_profile_id;

  return global_profile_id;
end;
$$;

create or replace function public.sync_pachanga_player_profile_to_groups(
  target_profile_id uuid,
  except_group_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  next_payload jsonb;
  next_players jsonb;
  profile_patch jsonb;
  profile_user_id uuid;
  saved_revision bigint;
begin
  select user_id into profile_user_id
  from public.pachanga_player_profiles
  where id = target_profile_id;

  if profile_user_id is null then
    return;
  end if;

  profile_patch := public.pachanga_player_profile_patch(target_profile_id);
  if profile_patch = '{}'::jsonb then
    return;
  end if;

  for current_group in
    select *
    from public.pachanga_groups groups
    where (except_group_id is null or groups.id <> except_group_id)
      and exists (
        select 1
        from jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) as players(value)
        where players.value ->> 'ownerUserId' = profile_user_id::text
      )
    order by groups.id
    for update skip locked
  loop
    select coalesce(jsonb_agg(
      case
        when value ->> 'ownerUserId' = profile_user_id::text then value || profile_patch
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

    next_payload := current_group.payload || jsonb_build_object('players', next_players);

    update public.pachanga_groups
    set payload = next_payload
    where id = current_group.id
    returning payload_revision into saved_revision;

    perform public.sync_pachanga_group_read_model(current_group.id, next_payload, saved_revision);
  end loop;
end;
$$;

do $$
declare
  group_record record;
  player_record jsonb;
  profile_id uuid;
begin
  for group_record in
    select id, payload
    from public.pachanga_groups
    order by updated_at asc
  loop
    for player_record in
      select value
      from jsonb_array_elements(coalesce(group_record.payload -> 'players', '[]'::jsonb)) as players(value)
    loop
      profile_id := public.upsert_pachanga_player_profile_from_player(
        group_record.id,
        player_record ->> 'id',
        player_record
      );
    end loop;
  end loop;

  for profile_id in
    select id
    from public.pachanga_player_profiles
  loop
    perform public.sync_pachanga_player_profile_to_groups(profile_id);
  end loop;

  update public.pachanga_market_profiles market_profiles
  set player_profile_id = player_profiles.id,
      updated_at = now()
  from public.pachanga_player_profiles player_profiles
  where market_profiles.user_id = player_profiles.user_id
    and market_profiles.player_profile_id is null;
end;
$$;

do $$
declare
  group_record record;
begin
  for group_record in
    select id, payload, payload_revision
    from public.pachanga_groups
  loop
    perform public.sync_pachanga_group_read_model(
      group_record.id,
      group_record.payload,
      group_record.payload_revision
    );
  end loop;
end;
$$;

revoke all on function public.pachanga_match_state(jsonb) from public;
revoke all on function public.record_pachanga_group_event(uuid, text, text, jsonb, uuid, boolean) from public;
revoke all on function public.remember_pachanga_operation(uuid, uuid, text, jsonb) from public;
revoke all on function public.sync_pachanga_match_read_model(uuid, jsonb, bigint) from public;
revoke all on function public.sync_pachanga_group_read_model(uuid, jsonb, bigint) from public;
revoke all on function public.pachanga_player_profile_patch(uuid) from public;
revoke all on function public.upsert_pachanga_player_profile_from_player(uuid, text, jsonb) from public;
revoke all on function public.sync_pachanga_player_profile_to_groups(uuid, uuid) from public;
revoke execute on function public.pachanga_match_state(jsonb) from anon;
revoke execute on function public.record_pachanga_group_event(uuid, text, text, jsonb, uuid, boolean) from anon;
revoke execute on function public.remember_pachanga_operation(uuid, uuid, text, jsonb) from anon;
revoke execute on function public.sync_pachanga_match_read_model(uuid, jsonb, bigint) from anon;
revoke execute on function public.sync_pachanga_group_read_model(uuid, jsonb, bigint) from anon;
revoke execute on function public.pachanga_player_profile_patch(uuid) from anon;
revoke execute on function public.upsert_pachanga_player_profile_from_player(uuid, text, jsonb) from anon;
revoke execute on function public.sync_pachanga_player_profile_to_groups(uuid, uuid) from anon;
revoke execute on function public.record_pachanga_group_event(uuid, text, text, jsonb, uuid, boolean) from authenticated;
revoke execute on function public.remember_pachanga_operation(uuid, uuid, text, jsonb) from authenticated;
revoke execute on function public.sync_pachanga_match_read_model(uuid, jsonb, bigint) from authenticated;
revoke execute on function public.sync_pachanga_group_read_model(uuid, jsonb, bigint) from authenticated;
revoke execute on function public.pachanga_player_profile_patch(uuid) from authenticated;
revoke execute on function public.upsert_pachanga_player_profile_from_player(uuid, text, jsonb) from authenticated;
revoke execute on function public.sync_pachanga_player_profile_to_groups(uuid, uuid) from authenticated;

create or replace function public.join_pachanga_group(token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id uuid;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select id into target_group_id
  from public.pachanga_groups
  where invite_token = token;

  if target_group_id is null then
    raise exception 'Invalid invite token';
  end if;

  insert into public.pachanga_group_members (group_id, user_id)
  values (target_group_id, current_user_id)
  on conflict (group_id, user_id) do nothing;

  return target_group_id;
end;
$$;

create or replace function public.join_pachanga_team(token uuid, member_name text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id uuid;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select id into target_group_id
  from public.pachanga_groups
  where invite_token = token;

  if target_group_id is null then
    raise exception 'Invalid invite token';
  end if;

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (target_group_id, current_user_id, 'player', nullif(trim(member_name), ''))
  on conflict (group_id, user_id) do update
    set display_name = coalesce(nullif(trim(excluded.display_name), ''), public.pachanga_group_members.display_name);

  return target_group_id;
end;
$$;

drop function if exists public.create_pachanga_admin_invite(uuid);
create or replace function public.create_pachanga_admin_invite(target_group_id uuid, operation_key uuid default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  created_token uuid;
  existing_response jsonb;
  response_payload jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_owner(target_group_id) then
    raise exception 'Only the group owner can invite admins';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response ->> 'token';
    end if;
  end if;

  insert into public.pachanga_admin_invites (group_id, created_by)
  values (target_group_id, current_user_id)
  returning token into created_token;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'admin_invite_created',
    jsonb_build_object('token', created_token),
    operation_key,
    true
  );

  response_payload := public.remember_pachanga_operation(
    target_group_id,
    operation_key,
    'admin_invite_created',
    jsonb_build_object('token', created_token)
  );

  if response_payload ? 'token' then
    return (response_payload ->> 'token')::uuid;
  end if;

  return created_token;
end;
$$;

create or replace function public.accept_pachanga_admin_invite(admin_token uuid, member_name text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_group_id uuid;
  current_user_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select group_id into target_group_id
  from public.pachanga_admin_invites invites
  where invites.token = admin_token
    and (
      invites.accepted_at is null
      or invites.accepted_by = current_user_id
    )
    and invites.expires_at > now();

  if target_group_id is null then
    raise exception 'Invalid admin invite';
  end if;

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (target_group_id, current_user_id, 'admin', nullif(trim(member_name), ''))
  on conflict (group_id, user_id) do update
    set role = case
        when public.pachanga_group_members.role = 'owner' then 'owner'
        else 'admin'
      end,
      display_name = coalesce(nullif(trim(excluded.display_name), ''), public.pachanga_group_members.display_name);

  update public.pachanga_admin_invites
  set accepted_by = current_user_id,
      accepted_at = now()
  where public.pachanga_admin_invites.token = admin_token
    and public.pachanga_admin_invites.accepted_at is null;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'admin_invite_accepted',
    jsonb_build_object('acceptedBy', current_user_id),
    null,
    true
  );

  return target_group_id;
end;
$$;

create or replace function public.update_pachanga_member_name(target_group_id uuid, member_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  next_name text;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  next_name := nullif(trim(member_name), '');
  if next_name is null then
    raise exception 'Member name required';
  end if;

  update public.pachanga_group_members
  set display_name = next_name
  where group_id = target_group_id
    and user_id = current_user_id;

  if not found then
    raise exception 'Current user is not a member of this group';
  end if;

  return next_name;
end;
$$;

create or replace function public.set_pachanga_member_role(
  target_group_id uuid,
  target_user_id uuid,
  next_role text,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  existing_response jsonb;
  operation_response jsonb;
  previous_role text;
  saved_role text;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_owner(target_group_id) then
    raise exception 'Only the group owner can update member roles';
  end if;
  if target_user_id = current_user_id then
    raise exception 'The owner role cannot be changed here';
  end if;
  if next_role not in ('admin', 'player') then
    raise exception 'Invalid member role';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  select role into previous_role
  from public.pachanga_group_members
  where group_id = target_group_id
    and user_id = target_user_id
  for update;

  if not found then
    raise exception 'Member not found';
  end if;
  if previous_role = 'owner' then
    raise exception 'Owner role cannot be changed';
  end if;

  update public.pachanga_group_members
  set role = next_role
  where group_id = target_group_id
    and user_id = target_user_id
    and role <> 'owner'
  returning role into saved_role;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'member_role_changed',
    jsonb_build_object(
      'targetUserId', target_user_id,
      'previousRole', previous_role,
      'nextRole', saved_role
    ),
    operation_key,
    true
  );

  operation_response := jsonb_build_object('user_id', target_user_id, 'role', saved_role);
  return public.remember_pachanga_operation(target_group_id, operation_key, 'member_role_changed', operation_response);
end;
$$;

create or replace function public.create_pachanga_group_backup(
  target_group_id uuid,
  backup_reason text default 'manual',
  backup_payload jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  created_backup_id uuid;
  source_group public.pachanga_groups%rowtype;
  snapshot_payload jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can create backups';
  end if;

  select * into source_group
  from public.pachanga_groups
  where id = target_group_id;

  if not found then
    raise exception 'Group not found';
  end if;

  snapshot_payload := coalesce(backup_payload, source_group.payload);

  insert into public.pachanga_group_backups (
    source_group_id,
    owner_id,
    created_by,
    group_name,
    team_code,
    reason,
    payload
  )
  values (
    source_group.id,
    source_group.owner_id,
    current_user_id,
    source_group.name,
    source_group.team_code,
    coalesce(nullif(trim(backup_reason), ''), 'manual'),
    snapshot_payload
  )
  returning id into created_backup_id;

  delete from public.pachanga_group_backups stale_backup
  using (
    select backup_id
    from (
      select
        backups.id as backup_id,
        row_number() over (
          order by (backups.id = created_backup_id) desc, backups.created_at desc, backups.id desc
        ) as backup_rank
      from public.pachanga_group_backups backups
      where backups.source_group_id = source_group.id
    ) ranked_backups
    where ranked_backups.backup_rank > 3
  ) old_backups
  where stale_backup.id = old_backups.backup_id;

  perform public.record_pachanga_group_event(
    source_group.id,
    null,
    'group_backup_created',
    jsonb_build_object('backupId', created_backup_id, 'reason', coalesce(nullif(trim(backup_reason), ''), 'manual')),
    null,
    true
  );

  return created_backup_id;
end;
$$;

create or replace function public.restore_pachanga_group_backup(backup_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
	declare
	  current_user_id uuid;
	  selected_backup public.pachanga_group_backups%rowtype;
	  restored_group uuid;
	  restored_payload jsonb;
	  restored_revision bigint;
	  can_restore_existing boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) then
    raise exception 'Registered user required';
  end if;

  select * into selected_backup
  from public.pachanga_group_backups
  where id = backup_id;

  if not found then
    raise exception 'Backup not found';
  end if;

  if selected_backup.owner_id <> current_user_id
    and selected_backup.created_by is distinct from current_user_id
    and not (
      selected_backup.source_group_id is not null
      and public.is_pachanga_group_admin(selected_backup.source_group_id)
    )
  then
    raise exception 'You cannot restore this backup';
  end if;

  can_restore_existing := selected_backup.source_group_id is not null
    and public.is_pachanga_group_admin(selected_backup.source_group_id)
    and exists (
      select 1 from public.pachanga_groups groups
      where groups.id = selected_backup.source_group_id
    );

  if can_restore_existing then
	  update public.pachanga_groups
	  set payload = selected_backup.payload,
	      name = selected_backup.group_name
	  where id = selected_backup.source_group_id
	  returning payload, payload_revision
	  into restored_payload, restored_revision;

	  restored_group := selected_backup.source_group_id;
  else
    insert into public.pachanga_groups (owner_id, name, payload)
    values (current_user_id, selected_backup.group_name, selected_backup.payload)
    returning id, payload, payload_revision
    into restored_group, restored_payload, restored_revision;

    insert into public.pachanga_group_members (group_id, user_id, role, display_name)
    values (restored_group, current_user_id, 'owner', null)
    on conflict (group_id, user_id) do update
      set role = 'owner';
  end if;

	  update public.pachanga_group_backups
	  set restored_at = now(),
	      restored_group_id = restored_group
	  where id = backup_id;

  perform public.sync_pachanga_group_read_model(restored_group, restored_payload, restored_revision);
  perform public.record_pachanga_group_event(
    restored_group,
    null,
    'group_backup_restored',
    jsonb_build_object('backupId', backup_id, 'payloadRevision', restored_revision),
    null,
    true
  );

	  return restored_group;
	end;
	$$;

create or replace function public.save_pachanga_payload_if_current(
  target_group_id uuid,
  expected_revision bigint,
  next_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_finalized_count integer;
  next_finalized_count integer;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can save the full team state';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if expected_revision is not null and current_group.payload_revision <> expected_revision then
    raise exception 'Team changed before saving. Reload and try again.' using errcode = '40001';
  end if;

  select count(*) into current_finalized_count
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) as value
  where coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA';

  select count(*) into next_finalized_count
  from jsonb_array_elements(coalesce(next_payload -> 'matches', '[]'::jsonb)) as value
  where coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA';

  if next_finalized_count > current_finalized_count then
    raise exception 'Finalize matches with finalize_pachanga_match_if_current.';
  end if;

  if current_group.payload = next_payload then
    return jsonb_build_object(
      'payload', current_group.payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );
  end if;

  update public.pachanga_groups
  set payload = next_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'group_payload_saved',
    jsonb_build_object('payloadRevision', saved_revision),
    null,
    true
  );

  return jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );
end;
$$;

drop function if exists public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb);
create or replace function public.finalize_pachanga_match_if_current(
  target_group_id uuid,
  expected_revision bigint,
  target_match_id text,
  next_payload jsonb,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  existing_response jsonb;
  selected_match jsonb;
  proposed_match jsonb;
  operation_response jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  was_finalized boolean;
  will_finalized boolean;
  billing_active boolean;
  next_trial_count integer;
  payer_player_id text;
  paying_ids text[];
  reserve_limit integer;
  score_a integer;
  score_b integer;
  target_players integer;
  team_a_ids text[];
  team_b_ids text[];
  team_a_total integer;
  team_b_total integer;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can finalize matches';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  if expected_revision is not null and current_group.payload_revision <> expected_revision then
    raise exception 'Team changed before saving. Reload and try again.' using errcode = '40001';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_group.payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  select value into proposed_match
  from jsonb_array_elements(coalesce(next_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if proposed_match is null then
    raise exception 'Finalized match missing from payload';
  end if;

  if not coalesce((proposed_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before finalizing it';
  end if;

  was_finalized := coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA';
  will_finalized := coalesce((proposed_match ->> 'closed')::boolean, false) or proposed_match ? 'scoreA';

  if was_finalized then
    raise exception 'Match already finalized';
  end if;

  if not will_finalized then
    raise exception 'Match must be finalized';
  end if;

  if not coalesce((proposed_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'Close the lineup before finalizing';
  end if;

  if not (proposed_match ? 'scoreA') or not (proposed_match ? 'scoreB') then
    raise exception 'Fill the score before finalizing';
  end if;

  score_a := coalesce((proposed_match ->> 'scoreA')::integer, -1);
  score_b := coalesce((proposed_match ->> 'scoreB')::integer, -1);
  if score_a < 0 or score_b < 0 then
    raise exception 'Invalid match score';
  end if;

  target_players := greatest(0, coalesce((proposed_match ->> 'targetPlayers')::integer, 0));
  reserve_limit := case
    when coalesce((proposed_match ->> 'reservesAttend')::boolean, false)
      then greatest(0, coalesce((proposed_match ->> 'reserveLimit')::integer, 0))
    else 0
  end;

  select coalesce(array_agg(player_id), '{}'::text[])
  into paying_ids
  from (
    select value ->> 'playerId' as player_id
    from jsonb_array_elements(coalesce(proposed_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality)
    where value ->> 'status' = 'voy'
    order by coalesce(value ->> 'joinedAt', '9999-12-31T23:59:59.999Z'), ordinality
    limit target_players + reserve_limit
  ) as paying_rows;

  if cardinality(paying_ids) < 1 then
    raise exception 'Close a lineup with players before finalizing';
  end if;

  payer_player_id := nullif(proposed_match ->> 'payerId', '');
  if payer_player_id is null or not payer_player_id = any(paying_ids) then
    raise exception 'Payer must belong to the closed lineup';
  end if;

  select coalesce(array_agg(value), '{}'::text[])
  into team_a_ids
  from jsonb_array_elements_text(coalesce(proposed_match -> 'teamA', '[]'::jsonb)) as team(value);

  select coalesce(array_agg(value), '{}'::text[])
  into team_b_ids
  from jsonb_array_elements_text(coalesce(proposed_match -> 'teamB', '[]'::jsonb)) as team(value);

  if cardinality(team_a_ids) + cardinality(team_b_ids) < 1 then
    raise exception 'Closed lineups are required before finalizing';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(proposed_match -> 'scorers', '[]'::jsonb)) as scorer(value)
    where nullif(value ->> 'playerId', '') is not null
      and not ((value ->> 'playerId') = any(team_a_ids) or (value ->> 'playerId') = any(team_b_ids))
  ) then
    raise exception 'Scorer is not in the current lineups';
  end if;

  select coalesce(sum(greatest(0, coalesce((value ->> 'goals')::integer, 0))), 0)
  into team_a_total
  from jsonb_array_elements(coalesce(proposed_match -> 'scorers', '[]'::jsonb)) as scorer(value)
  where value ->> 'playerId' = any(team_a_ids);

  select coalesce(sum(greatest(0, coalesce((value ->> 'goals')::integer, 0))), 0)
  into team_b_total
  from jsonb_array_elements(coalesce(proposed_match -> 'scorers', '[]'::jsonb)) as scorer(value)
  where value ->> 'playerId' = any(team_b_ids);

  if team_a_total > score_a or team_b_total > score_b then
    raise exception 'Scorers exceed the match score';
  end if;

  billing_active := current_group.billing_status in ('active', 'trialing')
    and (
      current_group.stripe_current_period_end is null
      or current_group.stripe_current_period_end > now()
    );
  next_trial_count := greatest(0, coalesce(current_group.billing_trial_finalized_matches, 0));

  if not was_finalized and not billing_active then
    if next_trial_count >= 2 then
      raise exception 'Trial limit reached. Subscription required.';
    end if;

    next_trial_count := next_trial_count + 1;
  end if;

  update public.pachanga_groups
  set
    payload = next_payload,
    billing_trial_finalized_matches = next_trial_count
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  perform public.record_pachanga_group_event(
    target_group_id,
    target_match_id,
    'match_finalized',
    jsonb_build_object(
      'scoreA', score_a,
      'scoreB', score_b,
      'payerId', payer_player_id,
      'payingCount', cardinality(paying_ids),
      'payloadRevision', saved_revision
    ),
    operation_key,
    true
  );

  operation_response := jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at,
    'billing_status', current_group.billing_status,
    'billing_trial_finalized_matches', next_trial_count,
    'stripe_customer_id', current_group.stripe_customer_id,
    'stripe_subscription_id', current_group.stripe_subscription_id,
    'stripe_price_id', current_group.stripe_price_id,
    'stripe_current_period_end', current_group.stripe_current_period_end,
    'billing_interval', current_group.billing_interval
  );

  return public.remember_pachanga_operation(target_group_id, operation_key, 'match_finalized', operation_response);
end;
$$;

drop function if exists public.patch_pachanga_match_player_status(uuid, text, text, text);
create or replace function public.patch_pachanga_match_player_status(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_status text,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  existing_response jsonb;
  selected_player jsonb;
  selected_match jsonb;
  existing_entry jsonb;
  next_entry jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
  is_finalized boolean;
  was_confirmed boolean;
  will_confirmed boolean;
  previous_goals integer;
  direction integer;
  score_a integer;
  score_b integer;
  winning_ids text[];
  next_confirmed_count integer;
  target_players integer;
  next_open_slots integer;
  operation_response jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if next_status not in ('voy', 'duda', 'no') then
    raise exception 'Invalid status';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only change your own attendance';
  end if;

  if next_status = 'voy'
    and (
      coalesce((selected_player ->> 'injured')::boolean, false)
      or coalesce((selected_player ->> 'inactive')::boolean, false)
    )
  then
    raise exception 'This player cannot attend';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before changing attendance';
  end if;

  is_finalized := coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA';
  if not is_finalized and coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'Open the lineup before changing attendance';
  end if;

  if is_finalized and not is_admin then
    raise exception 'Only admins can edit a finalized match';
  end if;

  select value into existing_entry
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) as value
  where value ->> 'playerId' = target_player_id
  limit 1;

  was_confirmed := existing_entry ->> 'status' = 'voy';
  will_confirmed := next_status = 'voy';

  next_entry := jsonb_build_object(
    'playerId', target_player_id,
    'status', next_status,
    'paid', case when next_status = 'voy' then coalesce((existing_entry ->> 'paid')::boolean, false) else false end
  );

  if next_status = 'voy' then
    next_entry := next_entry || jsonb_build_object(
      'joinedAt',
      coalesce(
        case when existing_entry ->> 'status' = 'voy' then existing_entry ->> 'joinedAt' else null end,
        to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
      )
    );
  end if;

  if existing_entry is null then
    next_match_players := coalesce(selected_match -> 'players', '[]'::jsonb) || jsonb_build_array(next_entry);
  else
    select coalesce(jsonb_agg(
      case when value ->> 'playerId' = target_player_id then next_entry else value end
      order by ordinality
    ), '[]'::jsonb)
    into next_match_players
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  next_match := selected_match || jsonb_build_object('players', next_match_players);

  select count(*)
  into next_confirmed_count
  from jsonb_array_elements(next_match_players) as entry(value)
  where entry.value ->> 'status' = 'voy';

  target_players := greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, 0));
  next_open_slots := greatest(target_players - next_confirmed_count, 0);

  if not is_finalized and (selected_match ? 'publicOpen' or selected_match ? 'publicOpenSlots') then
    next_match := next_match || jsonb_build_object(
      'publicOpen',
        next_open_slots > 0
        and not coalesce((next_match ->> 'lineupClosed')::boolean, false),
      'publicOpenSlots',
        greatest(next_open_slots, 1)
    );
  end if;

  previous_goals := coalesce((
    select (value ->> 'goals')::integer
    from jsonb_array_elements(coalesce(selected_match -> 'scorers', '[]'::jsonb)) as value
    where value ->> 'playerId' = target_player_id
    limit 1
  ), 0);

  if is_finalized and was_confirmed and not will_confirmed then
    next_match := jsonb_set(
      next_match,
      '{scorers}',
      coalesce((
        select jsonb_agg(value)
        from jsonb_array_elements(coalesce(next_match -> 'scorers', '[]'::jsonb)) as value
        where value ->> 'playerId' <> target_player_id
      ), '[]'::jsonb),
      true
    );
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_players := current_payload -> 'players';

  if is_finalized and was_confirmed <> will_confirmed then
    direction := case when will_confirmed then 1 else -1 end;
    score_a := coalesce((selected_match ->> 'scoreA')::integer, 0);
    score_b := coalesce((selected_match ->> 'scoreB')::integer, 0);
    winning_ids := case
      when score_a = score_b then array[]::text[]
      when score_a > score_b then array(select jsonb_array_elements_text(coalesce(selected_match -> 'teamA', '[]'::jsonb)))
      else array(select jsonb_array_elements_text(coalesce(selected_match -> 'teamB', '[]'::jsonb)))
    end;

    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_player_id then
          value || jsonb_build_object(
            'appearances', greatest(0, coalesce((value ->> 'appearances')::integer, 0) + direction),
            'goals', greatest(0, coalesce((value ->> 'goals')::integer, 0) + (direction * previous_goals)),
            'wins', greatest(0, coalesce((value ->> 'wins')::integer, 0) + case when target_player_id = any(winning_ids) then direction else 0 end)
          )
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('matches', next_matches, 'players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(target_group_id, next_match, saved_revision);

  if not is_finalized then
    update public.pachanga_open_matches
    set confirmed_count = next_confirmed_count,
        open_slots = next_open_slots,
        active = case
          when coalesce((next_match ->> 'lineupClosed')::boolean, false) then false
          when next_open_slots <= 0 then false
          when public.pachanga_open_matches.active or public.pachanga_open_matches.open_slots = 0 then true
          else public.pachanga_open_matches.active
        end,
        updated_at = now()
    where source_group_id = target_group_id
      and source_match_id = target_match_id;
  end if;

  perform public.record_pachanga_group_event(
    target_group_id,
    target_match_id,
    'match_attendance_changed',
    jsonb_build_object(
      'playerId', target_player_id,
      'status', next_status,
      'confirmedCount', next_confirmed_count,
      'openSlots', next_open_slots,
      'payloadRevision', saved_revision
    ),
    operation_key,
    is_admin
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_key, 'match_attendance_changed', operation_response);
end;
$$;

create or replace function public.patch_pachanga_match_lineup_state(
  target_group_id uuid,
  target_match_id text,
  next_lineup_closed boolean,
  target_team_a_ids text[],
  target_team_b_ids text[],
  target_payer_id text default null,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  existing_response jsonb;
  next_match jsonb;
  next_matches jsonb;
  operation_response jsonb;
  payer_player_id text;
  paying_ids text[];
  playing_ids text[];
  reserve_limit integer;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  selected_match jsonb;
  target_players integer;
  team_a_ids text[];
  team_b_ids text[];
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can change the lineup state';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  current_payload := current_group.payload;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;
  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before closing the lineup';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'Finalized matches cannot change lineup state';
  end if;

  target_players := greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, 0));
  reserve_limit := case
    when coalesce((selected_match ->> 'reservesAttend')::boolean, false)
      then greatest(0, coalesce((selected_match ->> 'reserveLimit')::integer, 0))
    else 0
  end;

  select coalesce(array_agg(player_id), '{}'::text[])
  into playing_ids
  from (
    select value ->> 'playerId' as player_id
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality)
    where value ->> 'status' = 'voy'
    order by coalesce(value ->> 'joinedAt', '9999-12-31T23:59:59.999Z'), ordinality
    limit target_players
  ) as playing_rows;

  select coalesce(array_agg(player_id), '{}'::text[])
  into paying_ids
  from (
    select value ->> 'playerId' as player_id
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality)
    where value ->> 'status' = 'voy'
    order by coalesce(value ->> 'joinedAt', '9999-12-31T23:59:59.999Z'), ordinality
    limit target_players + reserve_limit
  ) as paying_rows;

  team_a_ids := coalesce(target_team_a_ids, '{}'::text[]);
  team_b_ids := coalesce(target_team_b_ids, '{}'::text[]);

  if coalesce(next_lineup_closed, false) then
    if cardinality(playing_ids) < 1 then
      raise exception 'Add players before closing the lineup';
    end if;

    if exists (
      select 1
      from unnest(team_a_ids || team_b_ids) as ids(player_id)
      group by ids.player_id
      having count(*) > 1
    ) then
      raise exception 'A player cannot appear in both lineups';
    end if;

    if exists (
      select 1
      from unnest(team_a_ids || team_b_ids) as ids(player_id)
      where not ids.player_id = any(playing_ids)
    ) then
      raise exception 'Closed lineups can only include confirmed players';
    end if;

    if cardinality(team_a_ids) + cardinality(team_b_ids) <> cardinality(playing_ids) then
      raise exception 'Closed lineups must include every confirmed player once';
    end if;

    payer_player_id := nullif(target_payer_id, '');
    if payer_player_id is null then
      payer_player_id := paying_ids[1];
    end if;
    if payer_player_id is null or not payer_player_id = any(paying_ids) then
      raise exception 'Payer must belong to the closed lineup';
    end if;

    next_match := selected_match || jsonb_build_object(
      'lineupClosed', true,
      'payerId', payer_player_id,
      'publicOpen', false,
      'teamA', to_jsonb(team_a_ids),
      'teamB', to_jsonb(team_b_ids)
    );
  else
    next_match := selected_match || jsonb_build_object(
      'lineupClosed', false,
      'payerId', null
    );
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(target_group_id, next_match, saved_revision);

  update public.pachanga_open_matches
  set active = case
        when coalesce(next_lineup_closed, false) then false
        else active
      end,
      updated_at = now()
  where source_group_id = target_group_id
    and source_match_id = target_match_id;

  perform public.record_pachanga_group_event(
    target_group_id,
    target_match_id,
    case when coalesce(next_lineup_closed, false) then 'match_lineup_closed' else 'match_lineup_opened' end,
    jsonb_build_object(
      'lineupClosed', coalesce(next_lineup_closed, false),
      'payerId', payer_player_id,
      'playingCount', cardinality(playing_ids),
      'payingCount', cardinality(paying_ids),
      'payloadRevision', saved_revision
    ),
    operation_key,
    true
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(
    target_group_id,
    operation_key,
    case when coalesce(next_lineup_closed, false) then 'match_lineup_closed' else 'match_lineup_opened' end,
    operation_response
  );
end;
$$;

drop function if exists public.patch_pachanga_match_player_paid(uuid, text, text, boolean);
create or replace function public.patch_pachanga_match_player_paid(
  target_group_id uuid,
  target_match_id text,
  target_player_id text,
  next_paid boolean,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  existing_response jsonb;
  selected_player jsonb;
  selected_match jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  operation_response jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  is_admin boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only mark your own payment';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before changing payments';
  end if;

  if not (
    coalesce((selected_match ->> 'lineupClosed')::boolean, false)
    or coalesce((selected_match ->> 'closed')::boolean, false)
    or selected_match ? 'scoreA'
  ) then
    raise exception 'Close the lineup before changing payments';
  end if;

  select coalesce(jsonb_agg(
    case
      when value ->> 'playerId' = target_player_id and value ->> 'status' = 'voy' then value || jsonb_build_object('paid', coalesce(next_paid, false))
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_match_players
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_match := selected_match || jsonb_build_object('players', next_match_players);

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(target_group_id, next_match, saved_revision);
  perform public.record_pachanga_group_event(
    target_group_id,
    target_match_id,
    'match_payment_changed',
    jsonb_build_object(
      'playerId', target_player_id,
      'paid', coalesce(next_paid, false),
      'payloadRevision', saved_revision
    ),
    operation_key,
    is_admin
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_key, 'match_payment_changed', operation_response);
end;
$$;

drop function if exists public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[]);
create or replace function public.patch_pachanga_match_scorers(
  target_group_id uuid,
  target_match_id text,
  target_score_a integer,
  target_score_b integer,
  next_scorers jsonb,
  target_team_a_ids text[],
  target_team_b_ids text[],
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  existing_response jsonb;
  selected_match jsonb;
  sanitized_scorers jsonb;
  next_match jsonb;
  next_matches jsonb;
  next_players jsonb;
  operation_response jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  score_a integer;
  score_b integer;
  team_a_total integer;
  team_b_total integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can edit scorers';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  current_payload := current_group.payload;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before editing scorers';
  end if;

  score_a := coalesce((selected_match ->> 'scoreA')::integer, target_score_a);
  score_b := coalesce((selected_match ->> 'scoreB')::integer, target_score_b);
  if score_a is null or score_b is null or score_a < 0 or score_b < 0 then
    raise exception 'Fill the score before editing scorers';
  end if;

  with scorer_rows as (
    select
      value ->> 'playerId' as player_id,
      greatest(0, coalesce((value ->> 'goals')::integer, 0)) as goals
    from jsonb_array_elements(coalesce(next_scorers, '[]'::jsonb)) as value
  ),
  grouped as (
    select player_id, sum(goals)::integer as goals
    from scorer_rows
    where player_id is not null and goals > 0
    group by player_id
  )
  select coalesce(jsonb_agg(jsonb_build_object('playerId', player_id, 'goals', goals)), '[]'::jsonb)
  into sanitized_scorers
  from grouped;

  if exists (
    select 1
    from jsonb_array_elements(sanitized_scorers) as value
    where not ((value ->> 'playerId') = any(coalesce(target_team_a_ids, array[]::text[]))
      or (value ->> 'playerId') = any(coalesce(target_team_b_ids, array[]::text[])))
  ) then
    raise exception 'Scorer is not in the current lineups';
  end if;

  select coalesce(sum((value ->> 'goals')::integer), 0)
  into team_a_total
  from jsonb_array_elements(sanitized_scorers) as value
  where value ->> 'playerId' = any(coalesce(target_team_a_ids, array[]::text[]));

  select coalesce(sum((value ->> 'goals')::integer), 0)
  into team_b_total
  from jsonb_array_elements(sanitized_scorers) as value
  where value ->> 'playerId' = any(coalesce(target_team_b_ids, array[]::text[]));

  if team_a_total > score_a or team_b_total > score_b then
    raise exception 'Scorers exceed the match score';
  end if;

  next_match := jsonb_set(selected_match, '{scorers}', sanitized_scorers, true);

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_match_id then next_match else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_players := current_payload -> 'players';

  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    select coalesce(jsonb_agg(
      player_entry.value || jsonb_build_object(
        'goals',
        greatest(0,
          coalesce((player_entry.value ->> 'goals')::integer, 0)
          - coalesce((
              select (old_scorer.value ->> 'goals')::integer
              from jsonb_array_elements(coalesce(selected_match -> 'scorers', '[]'::jsonb)) as old_scorer(value)
              where old_scorer.value ->> 'playerId' = player_entry.value ->> 'id'
              limit 1
            ), 0)
          + coalesce((
              select (new_scorer.value ->> 'goals')::integer
              from jsonb_array_elements(sanitized_scorers) as new_scorer(value)
              where new_scorer.value ->> 'playerId' = player_entry.value ->> 'id'
              limit 1
            ), 0)
        )
      )
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as player_entry(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('matches', next_matches, 'players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(target_group_id, next_match, saved_revision);
  perform public.record_pachanga_group_event(
    target_group_id,
    target_match_id,
    'match_scorers_changed',
    jsonb_build_object(
      'scoreA', score_a,
      'scoreB', score_b,
      'teamAGoals', team_a_total,
      'teamBGoals', team_b_total,
      'payloadRevision', saved_revision
    ),
    operation_key,
    true
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_key, 'match_scorers_changed', operation_response);
end;
$$;

create or replace function public.pachanga_assessment_clamp(value numeric, min_value numeric, max_value numeric)
returns numeric
language sql
immutable
set search_path = public
as $$
  select least(max_value, greatest(min_value, coalesce(value, min_value)));
$$;

create or replace function public.pachanga_assessment_response_score(
  answers jsonb,
  question_id text,
  limit5 numeric default null,
  required boolean default false
)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  answer_value numeric;
begin
  if coalesce(answers ->> question_id, '') !~ '^[1-5]$' then
    if required then
      raise exception 'Assessment answer % is required', question_id;
    end if;
    return null;
  end if;

  answer_value := (answers ->> question_id)::numeric;
  if limit5 is not null then
    answer_value := answer_value - 0.5 * greatest(0::numeric, answer_value - limit5);
  end if;

  return 25 + 15 * (answer_value - 1);
end;
$$;

create or replace function public.pachanga_assessment_overall_weight(position_id text, attribute_id text)
returns numeric
language sql
immutable
set search_path = public
as $$
  select case position_id
    when 'centre_back' then case attribute_id when 'pace' then 0.15 when 'shooting' then 0.03 when 'passing' then 0.14 when 'dribbling' then 0.08 when 'defending' then 0.35 when 'physical' then 0.25 else 0 end
    when 'full_back' then case attribute_id when 'pace' then 0.22 when 'shooting' then 0.05 when 'passing' then 0.16 when 'dribbling' then 0.14 when 'defending' then 0.25 when 'physical' then 0.18 else 0 end
    when 'defensive_midfielder' then case attribute_id when 'pace' then 0.12 when 'shooting' then 0.05 when 'passing' then 0.24 when 'dribbling' then 0.15 when 'defending' then 0.25 when 'physical' then 0.19 else 0 end
    when 'attacking_midfielder' then case attribute_id when 'pace' then 0.15 when 'shooting' then 0.18 when 'passing' then 0.23 when 'dribbling' then 0.26 when 'defending' then 0.05 when 'physical' then 0.13 else 0 end
    when 'winger' then case attribute_id when 'pace' then 0.25 when 'shooting' then 0.18 when 'passing' then 0.16 when 'dribbling' then 0.28 when 'defending' then 0.03 when 'physical' then 0.1 else 0 end
    when 'striker' then case attribute_id when 'pace' then 0.2 when 'shooting' then 0.32 when 'passing' then 0.1 when 'dribbling' then 0.18 when 'defending' then 0.03 when 'physical' then 0.17 else 0 end
    else case attribute_id when 'pace' then 0.12 when 'shooting' then 0.1 when 'passing' then 0.28 when 'dribbling' then 0.22 when 'defending' then 0.13 when 'physical' then 0.15 else 0 end
  end;
$$;

create or replace function public.pachanga_assessment_mode_confidence(mode_shares jsonb, attribute_id text)
returns numeric
language sql
immutable
set search_path = public
as $$
  select coalesce(sum(
    share.percentage * case share.mode
      when 'futsal_5' then case attribute_id when 'pace' then 0.85 when 'shooting' then 0.9 when 'passing' then 0.95 when 'dribbling' then 0.98 when 'defending' then 0.88 when 'physical' then 0.75 else 1 end
      when 'football_11' then case attribute_id when 'pace' then 0.94 when 'shooting' then 0.92 when 'passing' then 0.94 when 'dribbling' then 0.88 when 'defending' then 0.98 when 'physical' then 0.98 else 1 end
      else case attribute_id when 'pace' then 0.93 when 'shooting' then 0.91 when 'passing' then 0.92 when 'dribbling' then 0.93 when 'defending' then 0.91 when 'physical' then 0.9 else 1 end
    end / 100
  ), 1)
  from jsonb_to_recordset(coalesce(mode_shares, '[]'::jsonb)) as share(mode text, percentage numeric);
$$;

create or replace function public.pachanga_assessment_app_position(position_id text)
returns text
language sql
immutable
set search_path = public
as $$
  select case position_id
    when 'centre_back' then 'Defensa central'
    when 'full_back' then 'Lateral derecho'
    when 'defensive_midfielder' then 'Pivote defensivo'
    when 'attacking_midfielder' then 'Mediapunta'
    when 'winger' then 'Extremo derecho'
    when 'striker' then 'Delantero / punta'
    else 'Mediocentro / pivote'
  end;
$$;

create or replace function public.pachanga_assessment_facets_from_attributes(attribute_ratings jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'ritmo', public.pachanga_assessment_clamp((attribute_ratings ->> 'pace')::numeric / 10, 1, 10),
    'tiro', public.pachanga_assessment_clamp((attribute_ratings ->> 'shooting')::numeric / 10, 1, 10),
    'pase', public.pachanga_assessment_clamp((attribute_ratings ->> 'passing')::numeric / 10, 1, 10),
    'regate', public.pachanga_assessment_clamp((attribute_ratings ->> 'dribbling')::numeric / 10, 1, 10),
    'defensa', public.pachanga_assessment_clamp((attribute_ratings ->> 'defending')::numeric / 10, 1, 10),
    'fisico', public.pachanga_assessment_clamp((attribute_ratings ->> 'physical')::numeric / 10, 1, 10)
  );
$$;

create or replace function public.calculate_pachanga_initial_assessment(assessment_input jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  answers jsonb := coalesce(assessment_input -> 'answers', '{}'::jsonb);
  mode_shares jsonb := coalesce(assessment_input -> 'modeShares', '[]'::jsonb);
  calculated_at text := coalesce(assessment_input ->> 'calculatedAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  primary_position text := coalesce(nullif(assessment_input ->> 'primaryPosition', ''), 'central_midfielder');
  experience_level text := coalesce(nullif(assessment_input ->> 'experienceLevel', ''), 'regular_pachangas');
  frequency_id text := coalesce(nullif(assessment_input ->> 'frequency', ''), 'weekly');
  years_since_level numeric := greatest(0::numeric, coalesce(nullif(assessment_input ->> 'yearsSinceLevel', '')::numeric, 0));
  mode_total numeric;
  regular_mode_count integer;
  experience_score numeric;
  experience5 numeric;
  frequency5 numeric;
  frequency_adjustment numeric;
  experience_effective numeric;
  limit5 numeric;
  control_score numeric;
  carry_score numeric;
  pass_score numeric;
  decision_score numeric;
  finish_score numeric;
  movement_score numeric;
  defense_score numeric;
  duel_score numeric;
  pace_score numeric;
  physical_score numeric;
  c numeric;
  p numeric;
  a numeric;
  d numeric;
  v numeric;
  h numeric;
  raw_pace numeric;
  raw_shooting numeric;
  raw_passing numeric;
  raw_dribbling numeric;
  raw_defending numeric;
  raw_physical numeric;
  base_ratings jsonb;
  current_ratings jsonb;
  base_overall numeric;
  current_overall numeric;
  reliability numeric;
begin
  if primary_position not in ('centre_back', 'full_back', 'defensive_midfielder', 'central_midfielder', 'attacking_midfielder', 'winger', 'striker') then
    raise exception 'Invalid assessment position';
  end if;

  select coalesce(sum(share.percentage), 0), count(*) filter (where share.percentage > 0)
  into mode_total, regular_mode_count
  from jsonb_to_recordset(mode_shares) as share(mode text, percentage numeric)
  where share.mode in ('futsal_5', 'football_7', 'football_11')
    and share.percentage >= 0
    and share.percentage <= 100;

  if round(mode_total * 100) / 100 <> 100 then
    raise exception 'Assessment modalities must add up to 100';
  end if;

  experience_score := case experience_level
    when 'barely_played' then 25
    when 'occasional_pachangas' then 35
    when 'regular_pachangas' then 45
    when 'social_league' then 55
    when 'amateur_club' then 65
    when 'federated_club' then 75
    when 'national_semipro' then 85
    when 'professional' then 92
    else 45
  end;
  experience5 := case experience_level
    when 'barely_played' then 1
    when 'occasional_pachangas' then 1.5
    when 'regular_pachangas' then 2
    when 'social_league' then 2.75
    when 'amateur_club' then 3.5
    when 'federated_club' then 4.2
    when 'national_semipro' then 4.7
    when 'professional' then 5
    else 2
  end;
  frequency5 := case frequency_id
    when 'less_monthly' then 1
    when 'monthly_twice' then 2
    when 'weekly' then 3
    when 'two_three_weekly' then 4
    when 'four_plus_weekly' then 5
    else 3
  end;
  frequency_adjustment := case frequency_id
    when 'less_monthly' then -6
    when 'monthly_twice' then -3
    when 'weekly' then 0
    when 'two_three_weekly' then 2
    when 'four_plus_weekly' then 3
    else 0
  end;
  experience_effective := case
    when years_since_level <= 0 then experience_score
    else 50 + (experience_score - 50) * exp(-0.12 * years_since_level)
  end;
  limit5 := least(5::numeric, 1.2 + 0.55 * experience5 + 0.25 * frequency5);

  control_score := public.pachanga_assessment_response_score(answers, 'controlUnderPressure', limit5, true);
  carry_score := public.pachanga_assessment_response_score(answers, 'ballCarrying', limit5, true);
  pass_score := public.pachanga_assessment_response_score(answers, 'passingExecution', limit5, true);
  decision_score := public.pachanga_assessment_response_score(answers, 'decisionMaking', limit5, true);
  finish_score := public.pachanga_assessment_response_score(answers, 'finishing', limit5, true);
  movement_score := public.pachanga_assessment_response_score(answers, 'attackingMovement', limit5, true);
  defense_score := public.pachanga_assessment_response_score(answers, 'defensivePositioning', limit5, true);
  duel_score := public.pachanga_assessment_response_score(answers, 'defensiveDuels', limit5, true);
  pace_score := public.pachanga_assessment_response_score(answers, 'paceComparison', limit5, true);
  physical_score := public.pachanga_assessment_response_score(answers, 'physicalIntensity', limit5, true);

  c := 0.6 * control_score + 0.4 * carry_score;
  p := 0.6 * pass_score + 0.4 * decision_score;
  a := 0.7 * finish_score + 0.3 * movement_score;
  d := 0.6 * defense_score + 0.4 * duel_score;
  v := pace_score;
  h := physical_score;

  raw_pace := 0.7 * v + 0.15 * c + 0.1 * a + 0.05 * d;
  raw_shooting := 0.75 * a + 0.1 * c + 0.1 * p + 0.05 * v;
  raw_passing := 0.7 * p + 0.15 * c + 0.1 * d + 0.05 * a;
  raw_dribbling := 0.7 * c + 0.15 * v + 0.1 * p + 0.05 * a;
  raw_defending := 0.7 * d + 0.1 * h + 0.1 * p + 0.05 * v + 0.05 * c;
  raw_physical := 0.7 * h + 0.15 * v + 0.1 * d + 0.05 * a;

  base_ratings := jsonb_build_object(
    'pace', public.pachanga_assessment_clamp(0.82 * raw_pace + 0.18 * experience_effective, 20, 90),
    'shooting', public.pachanga_assessment_clamp(0.82 * raw_shooting + 0.18 * experience_effective, 20, 90),
    'passing', public.pachanga_assessment_clamp(0.82 * raw_passing + 0.18 * experience_effective, 20, 90),
    'dribbling', public.pachanga_assessment_clamp(0.82 * raw_dribbling + 0.18 * experience_effective, 20, 90),
    'defending', public.pachanga_assessment_clamp(0.82 * raw_defending + 0.18 * experience_effective, 20, 90),
    'physical', public.pachanga_assessment_clamp(0.82 * raw_physical + 0.18 * experience_effective, 20, 90)
  );
  current_ratings := jsonb_build_object(
    'pace', public.pachanga_assessment_clamp((base_ratings ->> 'pace')::numeric + frequency_adjustment, 0, 92),
    'shooting', public.pachanga_assessment_clamp((base_ratings ->> 'shooting')::numeric + 0.4 * frequency_adjustment, 0, 92),
    'passing', public.pachanga_assessment_clamp((base_ratings ->> 'passing')::numeric + 0.3 * frequency_adjustment, 0, 92),
    'dribbling', public.pachanga_assessment_clamp((base_ratings ->> 'dribbling')::numeric + 0.4 * frequency_adjustment, 0, 92),
    'defending', public.pachanga_assessment_clamp((base_ratings ->> 'defending')::numeric + 0.5 * frequency_adjustment, 0, 92),
    'physical', public.pachanga_assessment_clamp((base_ratings ->> 'physical')::numeric + frequency_adjustment, 0, 92)
  );

  base_overall := (base_ratings ->> 'pace')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'pace')
    + (base_ratings ->> 'shooting')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'shooting')
    + (base_ratings ->> 'passing')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'passing')
    + (base_ratings ->> 'dribbling')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'dribbling')
    + (base_ratings ->> 'defending')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'defending')
    + (base_ratings ->> 'physical')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'physical');
  current_overall := (current_ratings ->> 'pace')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'pace')
    + (current_ratings ->> 'shooting')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'shooting')
    + (current_ratings ->> 'passing')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'passing')
    + (current_ratings ->> 'dribbling')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'dribbling')
    + (current_ratings ->> 'defending')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'defending')
    + (current_ratings ->> 'physical')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'physical');
  reliability := public.pachanga_assessment_clamp(20 + 15 * ((experience5 - 1) / 4) + 10 * ((frequency5 - 1) / 4) + 5 * least(2, greatest(0, regular_mode_count - 1)), 20, 55);

  return jsonb_build_object(
    'kind', 'initial',
    'engineVersion', 'football-rating-v1',
    'questionnaireVersion', 'initial-test-v1',
    'calculatedAt', calculated_at,
    'primaryPosition', primary_position,
    'position', public.pachanga_assessment_app_position(primary_position),
    'modeShares', mode_shares,
    'baseRatings', base_ratings,
    'currentRatings', current_ratings,
    'baseOverall', base_overall,
    'currentOverall', current_overall,
    'rating', public.pachanga_assessment_clamp(base_overall / 10, 1, 10),
    'facets', public.pachanga_assessment_facets_from_attributes(base_ratings),
    'reliability', reliability,
    'technicalComposites', jsonb_build_object('C', c, 'P', p, 'A', a, 'D', d, 'V', v, 'H', h)
  );
end;
$$;

create or replace function public.calculate_pachanga_advanced_assessment(assessment_input jsonb, initial_result jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  answers jsonb := coalesce(assessment_input -> 'answers', '{}'::jsonb);
  calculated_at text := coalesce(assessment_input ->> 'calculatedAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  primary_position text := coalesce(initial_result ->> 'primaryPosition', 'central_midfielder');
  initial_ratings jsonb := coalesce(initial_result -> 'baseRatings', '{}'::jsonb);
  initial_reliability numeric := coalesce(nullif(initial_result ->> 'reliability', '')::numeric, 35);
  entry record;
  score numeric;
  weights jsonb;
  total_weight jsonb := '{"pace":4,"shooting":4,"passing":4,"dribbling":4,"defending":4,"physical":4}'::jsonb;
  weighted_score jsonb;
  final_ratings jsonb := '{}'::jsonb;
  attribute_id text;
  weight numeric;
  calculated_value numeric;
  coverage numeric;
  max_delta numeric;
  initial_value numeric;
  completed_count integer := 0;
  base_overall numeric;
  reliability numeric;
begin
  weighted_score := jsonb_build_object(
    'pace', 4 * coalesce(nullif(initial_ratings ->> 'pace', '')::numeric, 50),
    'shooting', 4 * coalesce(nullif(initial_ratings ->> 'shooting', '')::numeric, 50),
    'passing', 4 * coalesce(nullif(initial_ratings ->> 'passing', '')::numeric, 50),
    'dribbling', 4 * coalesce(nullif(initial_ratings ->> 'dribbling', '')::numeric, 50),
    'defending', 4 * coalesce(nullif(initial_ratings ->> 'defending', '')::numeric, 50),
    'physical', 4 * coalesce(nullif(initial_ratings ->> 'physical', '')::numeric, 50)
  );

  for entry in
    select key, value
    from jsonb_each(answers)
  loop
    if coalesce(entry.value #>> '{}', '') !~ '^[1-5]$' then
      continue;
    end if;

    completed_count := completed_count + 1;
    score := 25 + 15 * ((entry.value #>> '{}')::numeric - 1);
    weights := case
      when entry.key like 'TEC-%' then '{"dribbling":1,"passing":0.25}'::jsonb
      when entry.key like 'PAS-%' then '{"passing":1,"dribbling":0.15}'::jsonb
      when entry.key like 'TIR-%' then '{"shooting":1,"pace":0.15,"dribbling":0.1}'::jsonb
      when entry.key like 'DEF-%' then '{"defending":1,"physical":0.15}'::jsonb
      when entry.key like 'RIT-%' then '{"pace":1,"physical":0.2}'::jsonb
      when entry.key like 'FIS-%' then '{"physical":1,"pace":0.2}'::jsonb
      when entry.key like 'INT-%' then '{"passing":0.55,"defending":0.35,"dribbling":0.2}'::jsonb
      when entry.key like 'MOD-F5-%' then '{"dribbling":0.45,"passing":0.35,"pace":0.25,"shooting":0.2}'::jsonb
      when entry.key like 'MOD-F7-%' then '{"passing":0.35,"pace":0.3,"defending":0.3,"physical":0.25,"shooting":0.15}'::jsonb
      when entry.key like 'MOD-F11-%' then '{"passing":0.35,"defending":0.35,"physical":0.3,"shooting":0.15}'::jsonb
      when entry.key like 'POS-CB-%' then '{"defending":0.85,"physical":0.35,"passing":0.2}'::jsonb
      when entry.key like 'POS-FB-%' then '{"pace":0.45,"defending":0.45,"passing":0.25,"physical":0.25}'::jsonb
      when entry.key like 'POS-DM-%' then '{"defending":0.45,"passing":0.45,"physical":0.25,"dribbling":0.2}'::jsonb
      when entry.key like 'POS-CM-%' then '{"passing":0.45,"dribbling":0.4,"shooting":0.2,"defending":0.2}'::jsonb
      when entry.key like 'POS-W-%' then '{"pace":0.55,"dribbling":0.55,"shooting":0.25,"passing":0.2}'::jsonb
      when entry.key like 'POS-ST-%' then '{"shooting":0.6,"pace":0.35,"physical":0.25,"dribbling":0.2}'::jsonb
      else '{}'::jsonb
    end;

    for attribute_id, weight in
      select key, (value #>> '{}')::numeric
      from jsonb_each(weights)
    loop
      weighted_score := jsonb_set(
        weighted_score,
        array[attribute_id],
        to_jsonb(coalesce((weighted_score ->> attribute_id)::numeric, 0) + score * weight)
      );
      total_weight := jsonb_set(
        total_weight,
        array[attribute_id],
        to_jsonb(coalesce((total_weight ->> attribute_id)::numeric, 0) + weight)
      );
    end loop;
  end loop;

  foreach attribute_id in array array['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical']
  loop
    initial_value := coalesce(nullif(initial_ratings ->> attribute_id, '')::numeric, 50);
    calculated_value := coalesce((weighted_score ->> attribute_id)::numeric, initial_value * 4) / greatest(4, coalesce((total_weight ->> attribute_id)::numeric, 4));
    coverage := least(1::numeric, greatest(0::numeric, coalesce((total_weight ->> attribute_id)::numeric, 4) - 4) / 8);
    max_delta := 5 + 13 * coverage;
    final_ratings := jsonb_set(
      final_ratings,
      array[attribute_id],
      to_jsonb(public.pachanga_assessment_clamp(calculated_value, initial_value - max_delta, least(92::numeric, initial_value + max_delta)))
    );
  end loop;

  base_overall := (final_ratings ->> 'pace')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'pace')
    + (final_ratings ->> 'shooting')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'shooting')
    + (final_ratings ->> 'passing')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'passing')
    + (final_ratings ->> 'dribbling')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'dribbling')
    + (final_ratings ->> 'defending')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'defending')
    + (final_ratings ->> 'physical')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'physical');
  reliability := public.pachanga_assessment_clamp(initial_reliability + least(26::numeric, completed_count * 0.65), initial_reliability, 65);

  return jsonb_build_object(
    'kind', 'advanced',
    'engineVersion', 'football-rating-v1',
    'questionnaireVersion', 'advanced-test-v1',
    'calculatedAt', calculated_at,
    'primaryPosition', primary_position,
    'baseRatings', final_ratings,
    'baseOverall', base_overall,
    'rating', public.pachanga_assessment_clamp(base_overall / 10, 1, 10),
    'facets', public.pachanga_assessment_facets_from_attributes(final_ratings),
    'reliability', reliability,
    'answeredCount', completed_count
  );
end;
$$;

create or replace function public.upsert_pachanga_own_player_profile(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  owned_player jsonb;
  selected_player_id text;
  next_player jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  existing_global_profile_id uuid;
  global_profile_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can create a player profile';
  end if;

  selected_player_id := nullif(trim(coalesce(target_player_id, '')), '');
  if selected_player_id is null then
    raise exception 'Player id required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select id into existing_global_profile_id
  from public.pachanga_player_profiles
  where user_id = current_user_id
  for update;

  select value into owned_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'ownerUserId' = current_user_id::text
  limit 1;

  if owned_player is not null then
    selected_player := owned_player;
    selected_player_id := owned_player ->> 'id';
  else
    select value into selected_player
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
    where value ->> 'id' = selected_player_id
    limit 1;

    if selected_player is not null
      and coalesce(selected_player ->> 'ownerUserId', '') <> ''
      and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text
    then
      raise exception 'This player profile already belongs to another user';
    end if;
  end if;

  if existing_global_profile_id is null
    and selected_player is null
    and not exists (
      select 1
      from public.pachanga_player_assessments assessments
      where assessments.user_id = current_user_id
        and assessments.assessment_kind = 'initial'
    )
    and not (coalesce(player_patch, '{}'::jsonb) ? 'importedRating')
  then
    raise exception 'Complete the initial player assessment before creating a new profile';
  end if;

  next_player := coalesce(
    selected_player,
    jsonb_build_object(
      'id', selected_player_id,
      'name', 'Jugador',
      'phone', '',
      'goalkeeperOnly', false,
      'injured', false,
      'rating', 5,
      'ratings', '[]'::jsonb,
      'ratingVotes', '[]'::jsonb,
      'position', 'Mediocentro / pivote',
      'outfieldPosition', 'Mediocentro / pivote',
      'goals', 0,
      'assists', 0,
      'appearances', 0,
      'wins', 0,
      'lateCancels', 0
    )
  ) || jsonb_build_object(
    'id', selected_player_id,
    'ownerUserId', current_user_id::text
  );

  if player_patch ? 'name' then
    next_player := next_player || jsonb_build_object('name', coalesce(nullif(trim(player_patch ->> 'name'), ''), 'Jugador'));
  end if;

  if player_patch ? 'phone' then
    next_player := next_player || jsonb_build_object('phone', coalesce(player_patch ->> 'phone', ''));
  end if;

  if player_patch ? 'birthDate' then
    next_player := next_player || jsonb_build_object('birthDate', nullif(player_patch ->> 'birthDate', ''));
  end if;

  if player_patch ? 'avatar' then
    next_player := next_player || jsonb_build_object('avatar', nullif(player_patch ->> 'avatar', ''));
  end if;

  if player_patch ? 'avatarOffsetX' then
    next_player := next_player || jsonb_build_object('avatarOffsetX', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetX', '')::numeric, 50))));
  end if;

  if player_patch ? 'avatarOffsetY' then
    next_player := next_player || jsonb_build_object('avatarOffsetY', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetY', '')::numeric, 0))));
  end if;

  if player_patch ? 'goalkeeperOnly' then
    next_player := next_player || jsonb_build_object('goalkeeperOnly', coalesce((player_patch ->> 'goalkeeperOnly')::boolean, false));
  end if;

  if player_patch ? 'injured' then
    next_player := next_player || jsonb_build_object('injured', coalesce((player_patch ->> 'injured')::boolean, false));
  end if;

  if player_patch ? 'position' then
    next_player := next_player || jsonb_build_object('position', coalesce(nullif(player_patch ->> 'position', ''), 'Mediocentro / pivote'));
  end if;

  if player_patch ? 'outfieldPosition' then
    next_player := next_player || jsonb_build_object('outfieldPosition', coalesce(nullif(player_patch ->> 'outfieldPosition', ''), 'Mediocentro / pivote'));
  end if;

  if player_patch ? 'goals' then
    next_player := next_player || jsonb_build_object('goals', greatest(0, coalesce((player_patch ->> 'goals')::integer, 0)));
  end if;

  if player_patch ? 'importedRating' then
    next_player := next_player || jsonb_build_object(
      'importedRating', greatest(1, least(10, coalesce((player_patch ->> 'importedRating')::numeric, 5))),
      'rating', greatest(1, least(10, coalesce((player_patch ->> 'importedRating')::numeric, 5)))
    );
  end if;

  if player_patch ? 'importedRatingFromGroup' then
    next_player := next_player || jsonb_build_object('importedRatingFromGroup', nullif(trim(player_patch ->> 'importedRatingFromGroup'), ''));
  end if;

  if player_patch ? 'importedRatingAt' then
    next_player := next_player || jsonb_build_object('importedRatingAt', nullif(player_patch ->> 'importedRatingAt', ''));
  end if;

  if player_patch ? 'marketEnabled' then
    next_player := next_player || jsonb_build_object('marketEnabled', coalesce((player_patch ->> 'marketEnabled')::boolean, false));
  end if;

  if player_patch ? 'marketZones' then
    next_player := next_player || jsonb_build_object('marketZones', left(coalesce(player_patch ->> 'marketZones', ''), 320));
  end if;

  if player_patch ? 'marketAvailability' then
    next_player := next_player || jsonb_build_object('marketAvailability', left(coalesce(player_patch ->> 'marketAvailability', ''), 240));
  end if;

  if player_patch ? 'marketBio' then
    next_player := next_player || jsonb_build_object('marketBio', left(coalesce(player_patch ->> 'marketBio', ''), 280));
  end if;

  if player_patch ? 'marketOpenToGroup' then
    next_player := next_player || jsonb_build_object('marketOpenToGroup', coalesce((player_patch ->> 'marketOpenToGroup')::boolean, true));
  end if;

  if player_patch ? 'marketOpenToGuest' then
    next_player := next_player || jsonb_build_object('marketOpenToGuest', coalesce((player_patch ->> 'marketOpenToGuest')::boolean, true));
  end if;

  if player_patch ? 'marketModalities' then
    next_player := next_player || jsonb_build_object(
      'marketModalities',
      case
        when jsonb_typeof(player_patch -> 'marketModalities') = 'array' then
          coalesce((
            select jsonb_agg(value)
            from jsonb_array_elements_text(player_patch -> 'marketModalities') as modalities(value)
            where value in ('sala', 'futbol7', 'futbol11')
          ), '[]'::jsonb)
        else '[]'::jsonb
      end
    );
  end if;

  global_profile_id := public.upsert_pachanga_player_profile_from_player(target_group_id, selected_player_id, next_player);
  if global_profile_id is not null then
    next_player := next_player || public.pachanga_player_profile_patch(global_profile_id);
  end if;

  if selected_player is null then
    next_players := coalesce(current_payload -> 'players', '[]'::jsonb) || jsonb_build_array(next_player);
  else
    select coalesce(jsonb_agg(
      case when value ->> 'id' = selected_player_id then next_player else value end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.pachanga_assessment_without_self_votes(votes jsonb, target_user_id uuid)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(jsonb_agg(value order by ordinality), '[]'::jsonb)
  from jsonb_array_elements(coalesce(votes, '[]'::jsonb)) with ordinality as vote(value, ordinality)
  where not (
    vote.value ->> 'voterId' = target_user_id::text
    and vote.value ->> 'source' in ('initialAssessment', 'advancedAssessment')
  );
$$;

create or replace function public.pachanga_assessment_summary_item(assessment_result jsonb, completed_at timestamptz)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'completedAt', to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'engineVersion', assessment_result ->> 'engineVersion',
    'questionnaireVersion', assessment_result ->> 'questionnaireVersion',
    'rating', (assessment_result ->> 'rating')::numeric,
    'facets', assessment_result -> 'facets',
    'reliability', nullif(assessment_result ->> 'reliability', '')::numeric,
    'primaryPosition', assessment_result ->> 'primaryPosition'
  ));
$$;

create or replace function public.complete_pachanga_player_initial_assessment(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
  assessment_input jsonb,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  existing_assessment public.pachanga_player_assessments%rowtype;
  assessment_result jsonb;
  completed_at timestamptz := now();
  target_rating numeric;
  target_facets jsonb;
  next_vote jsonb;
  next_patch jsonb;
  global_profile_id uuid;
  current_profile public.pachanga_player_profiles%rowtype;
  next_summary jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  operation_response jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if operation_id is null then
    raise exception 'Operation id required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can complete player assessments';
  end if;

  perform pg_advisory_xact_lock(hashtext(current_user_id::text), hashtext('pachanga_initial_assessment'));

  select * into existing_assessment
  from public.pachanga_player_assessments
  where user_id = current_user_id
    and assessment_kind = 'initial'
  for update;

  if found then
    if existing_assessment.idempotency_key <> operation_id then
      raise exception 'Initial player assessment already completed';
    end if;

    select payload, payload_revision, updated_at
    into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups
    where id = target_group_id;

    return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  end if;

  assessment_result := public.calculate_pachanga_initial_assessment(assessment_input);
  target_rating := public.pachanga_assessment_clamp((assessment_result ->> 'rating')::numeric, 1, 10);
  target_facets := assessment_result -> 'facets';

  insert into public.pachanga_player_assessments (
    user_id,
    assessment_kind,
    engine_version,
    questionnaire_version,
    idempotency_key,
    input,
    result,
    rating,
    facet_ratings,
    reliability,
    completed_at
  )
  values (
    current_user_id,
    'initial',
    assessment_result ->> 'engineVersion',
    assessment_result ->> 'questionnaireVersion',
    operation_id,
    assessment_input,
    assessment_result,
    target_rating,
    target_facets,
    nullif(assessment_result ->> 'reliability', '')::numeric,
    completed_at
  );

  next_patch := coalesce(player_patch, '{}'::jsonb) || jsonb_build_object(
    'position', assessment_result ->> 'position',
    'outfieldPosition', assessment_result ->> 'position'
  );

  perform public.upsert_pachanga_own_player_profile(target_group_id, target_player_id, next_patch);

  select * into current_profile
  from public.pachanga_player_profiles
  where user_id = current_user_id
  for update;

  if not found then
    raise exception 'Player profile was not created';
  end if;

  global_profile_id := current_profile.id;
  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', 'Test inicial',
    'ratingRole', case when current_profile.goalkeeper_only then 'goalkeeper' else 'field' end,
    'matchCount', 0,
    'createdAt', to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source', 'initialAssessment',
    'facets', target_facets
  );
  next_summary := coalesce(current_profile.assessment_summary, '{}'::jsonb)
    || jsonb_build_object('initial', public.pachanga_assessment_summary_item(assessment_result, completed_at));

  update public.pachanga_player_profiles
  set rating = target_rating,
      ratings = '[]'::jsonb,
      rating_votes = public.pachanga_assessment_without_self_votes(rating_votes, current_user_id) || jsonb_build_array(next_vote),
      assessment_summary = next_summary,
      position = assessment_result ->> 'position',
      outfield_position = assessment_result ->> 'position',
      profile_version = profile_version + 1,
      updated_at = now()
  where id = global_profile_id;

  update public.pachanga_player_assessments
  set player_profile_id = global_profile_id
  where user_id = current_user_id
    and assessment_kind = 'initial';

  perform public.sync_pachanga_player_profile_to_groups(global_profile_id);

  select payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups
  where id = target_group_id;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'player_initial_assessment_completed',
    jsonb_build_object('playerProfileId', global_profile_id, 'rating', target_rating, 'payloadRevision', saved_revision),
    operation_id,
    false
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_id, 'player_initial_assessment_completed', operation_response);
end;
$$;

create or replace function public.complete_pachanga_player_advanced_assessment(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb,
  assessment_input jsonb,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  initial_assessment public.pachanga_player_assessments%rowtype;
  existing_assessment public.pachanga_player_assessments%rowtype;
  assessment_result jsonb;
  completed_at timestamptz := now();
  target_rating numeric;
  target_facets jsonb;
  next_vote jsonb;
  current_group public.pachanga_groups%rowtype;
  selected_player jsonb;
  current_profile public.pachanga_player_profiles%rowtype;
  next_summary jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  operation_response jsonb;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if operation_id is null then
    raise exception 'Operation id required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can complete player assessments';
  end if;

  perform pg_advisory_xact_lock(hashtext(current_user_id::text), hashtext('pachanga_advanced_assessment'));

  select * into existing_assessment
  from public.pachanga_player_assessments
  where user_id = current_user_id
    and assessment_kind = 'advanced'
  for update;

  if found then
    if existing_assessment.idempotency_key <> operation_id then
      raise exception 'Advanced player assessment already completed';
    end if;

    select payload, payload_revision, updated_at
    into saved_payload, saved_revision, saved_updated_at
    from public.pachanga_groups
    where id = target_group_id;

    return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  end if;

  select * into initial_assessment
  from public.pachanga_player_assessments
  where user_id = current_user_id
    and assessment_kind = 'initial'
  for update;

  if not found then
    raise exception 'Initial player assessment is required before the advanced assessment';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null or coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only complete the advanced assessment for your own player profile';
  end if;

  select * into current_profile
  from public.pachanga_player_profiles
  where user_id = current_user_id
  for update;

  if not found then
    raise exception 'Player profile not found';
  end if;

  assessment_result := public.calculate_pachanga_advanced_assessment(assessment_input, initial_assessment.result);
  target_rating := public.pachanga_assessment_clamp((assessment_result ->> 'rating')::numeric, 1, 10);
  target_facets := assessment_result -> 'facets';

  insert into public.pachanga_player_assessments (
    user_id,
    player_profile_id,
    assessment_kind,
    engine_version,
    questionnaire_version,
    idempotency_key,
    input,
    result,
    rating,
    facet_ratings,
    reliability,
    completed_at
  )
  values (
    current_user_id,
    current_profile.id,
    'advanced',
    assessment_result ->> 'engineVersion',
    assessment_result ->> 'questionnaireVersion',
    operation_id,
    assessment_input,
    assessment_result,
    target_rating,
    target_facets,
    nullif(assessment_result ->> 'reliability', '')::numeric,
    completed_at
  );

  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', 'Test avanzado',
    'ratingRole', case when current_profile.goalkeeper_only then 'goalkeeper' else 'field' end,
    'matchCount', 0,
    'createdAt', to_char(completed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'source', 'advancedAssessment',
    'facets', target_facets
  );
  next_summary := coalesce(current_profile.assessment_summary, '{}'::jsonb)
    || jsonb_build_object('advanced', public.pachanga_assessment_summary_item(assessment_result, completed_at));

  update public.pachanga_player_profiles
  set rating = target_rating,
      rating_votes = public.pachanga_assessment_without_self_votes(rating_votes, current_user_id) || jsonb_build_array(next_vote),
      assessment_summary = next_summary,
      profile_version = profile_version + 1,
      updated_at = now()
  where id = current_profile.id;

  perform public.sync_pachanga_player_profile_to_groups(current_profile.id);

  select payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at
  from public.pachanga_groups
  where id = target_group_id;

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'player_advanced_assessment_completed',
    jsonb_build_object('playerProfileId', current_profile.id, 'rating', target_rating, 'payloadRevision', saved_revision),
    operation_id,
    false
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_id, 'player_advanced_assessment_completed', operation_response);
end;
$$;

create or replace function public.patch_pachanga_player_profile(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  patched_player jsonb;
  next_players jsonb;
  next_matches jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  global_profile_id uuid;
  is_admin boolean;
  patch_injured boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;
  is_admin := public.is_pachanga_group_admin(target_group_id);

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if not is_admin and coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'You can only edit your own player profile';
  end if;

  patched_player := selected_player;

  if player_patch ? 'name' then
    patched_player := patched_player || jsonb_build_object('name', nullif(trim(player_patch ->> 'name'), ''));
  end if;

  if player_patch ? 'phone' then
    patched_player := patched_player || jsonb_build_object('phone', coalesce(player_patch ->> 'phone', ''));
  end if;

  if player_patch ? 'birthDate' then
    patched_player := patched_player || jsonb_build_object('birthDate', nullif(player_patch ->> 'birthDate', ''));
  end if;

  if player_patch ? 'avatar' then
    patched_player := patched_player || jsonb_build_object('avatar', nullif(player_patch ->> 'avatar', ''));
  end if;

  if player_patch ? 'avatarOffsetX' then
    patched_player := patched_player || jsonb_build_object('avatarOffsetX', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetX', '')::numeric, 50))));
  end if;

  if player_patch ? 'avatarOffsetY' then
    patched_player := patched_player || jsonb_build_object('avatarOffsetY', least(100, greatest(0, coalesce(nullif(player_patch ->> 'avatarOffsetY', '')::numeric, 0))));
  end if;

  if player_patch ? 'goalkeeperOnly' then
    patched_player := patched_player || jsonb_build_object('goalkeeperOnly', coalesce((player_patch ->> 'goalkeeperOnly')::boolean, false));
  end if;

  if player_patch ? 'injured' then
    patch_injured := coalesce((player_patch ->> 'injured')::boolean, false);
    patched_player := patched_player || jsonb_build_object('injured', patch_injured);
  end if;

  if player_patch ? 'position' then
    patched_player := patched_player || jsonb_build_object('position', nullif(player_patch ->> 'position', ''));
  end if;

  if player_patch ? 'outfieldPosition' then
    patched_player := patched_player || jsonb_build_object('outfieldPosition', nullif(player_patch ->> 'outfieldPosition', ''));
  end if;

  if player_patch ? 'goals' then
    patched_player := patched_player || jsonb_build_object('goals', greatest(0, coalesce((player_patch ->> 'goals')::integer, 0)));
  end if;

  if player_patch ? 'marketEnabled' then
    patched_player := patched_player || jsonb_build_object('marketEnabled', coalesce((player_patch ->> 'marketEnabled')::boolean, false));
  end if;

  if player_patch ? 'marketZones' then
    patched_player := patched_player || jsonb_build_object('marketZones', left(coalesce(player_patch ->> 'marketZones', ''), 320));
  end if;

  if player_patch ? 'marketAvailability' then
    patched_player := patched_player || jsonb_build_object('marketAvailability', left(coalesce(player_patch ->> 'marketAvailability', ''), 240));
  end if;

  if player_patch ? 'marketBio' then
    patched_player := patched_player || jsonb_build_object('marketBio', left(coalesce(player_patch ->> 'marketBio', ''), 280));
  end if;

  if player_patch ? 'marketOpenToGroup' then
    patched_player := patched_player || jsonb_build_object('marketOpenToGroup', coalesce((player_patch ->> 'marketOpenToGroup')::boolean, true));
  end if;

  if player_patch ? 'marketOpenToGuest' then
    patched_player := patched_player || jsonb_build_object('marketOpenToGuest', coalesce((player_patch ->> 'marketOpenToGuest')::boolean, true));
  end if;

  if player_patch ? 'marketModalities' then
    patched_player := patched_player || jsonb_build_object(
      'marketModalities',
      case
        when jsonb_typeof(player_patch -> 'marketModalities') = 'array' then
          coalesce((
            select jsonb_agg(value)
            from jsonb_array_elements_text(player_patch -> 'marketModalities') as modalities(value)
            where value in ('sala', 'futbol7', 'futbol11')
          ), '[]'::jsonb)
        else '[]'::jsonb
      end
    );
  end if;

  if is_admin and player_patch ? 'rating' then
    patched_player := patched_player || jsonb_build_object('rating', greatest(1, least(10, coalesce((player_patch ->> 'rating')::numeric, 5))));
  end if;

  if is_admin and player_patch ? 'inactive' then
    patched_player := patched_player || jsonb_build_object('inactive', coalesce((player_patch ->> 'inactive')::boolean, false));
  end if;

  if coalesce(patched_player ->> 'ownerUserId', '') = current_user_id::text then
    global_profile_id := public.upsert_pachanga_player_profile_from_player(target_group_id, target_player_id, patched_player);
    if global_profile_id is not null then
      patched_player := patched_player || public.pachanga_player_profile_patch(global_profile_id);
    end if;
  end if;

  select coalesce(jsonb_agg(
    case when value ->> 'id' = target_player_id then patched_player else value end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  next_matches := current_payload -> 'matches';

  if patch_injured then
    select coalesce(jsonb_agg(
      case
        when not (coalesce((value ->> 'closed')::boolean, false) or value ? 'scoreA') then
          value || jsonb_build_object(
            'players',
            coalesce((
              select jsonb_agg(
                case
                  when entry ->> 'playerId' = target_player_id then
                    jsonb_build_object('playerId', target_player_id, 'status', 'no', 'paid', false)
                  else entry
                end
                order by entry_ordinality
              )
              from jsonb_array_elements(coalesce(value -> 'players', '[]'::jsonb)) with ordinality as match_entries(entry, entry_ordinality)
            ), '[]'::jsonb)
          )
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_matches
    from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  current_payload := current_payload || jsonb_build_object('players', next_players, 'matches', next_matches);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

create or replace function public.sync_pachanga_market_profile(
  target_group_id uuid,
  target_player_id text,
  market_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  selected_player jsonb;
  current_group public.pachanga_groups%rowtype;
  market_player_patch jsonb;
  next_players jsonb;
  sanitized_zones text[];
  sanitized_zones_geo jsonb;
  sanitized_modalities text[];
  saved_profile public.pachanga_market_profiles%rowtype;
  saved_payload jsonb;
  saved_revision bigint;
  global_profile_id uuid;
  wants_active boolean;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only group members can publish market profiles';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if coalesce(selected_player ->> 'ownerUserId', '') <> current_user_id::text then
    raise exception 'Only the player owner can publish this profile';
  end if;

  wants_active := coalesce((market_patch ->> 'active')::boolean, false);

  if not wants_active then
    global_profile_id := public.upsert_pachanga_player_profile_from_player(
      target_group_id,
      target_player_id,
      selected_player || jsonb_build_object('marketEnabled', false)
    );

    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_player_id then value || jsonb_build_object('marketEnabled', false) || public.pachanga_player_profile_patch(global_profile_id)
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_players
    from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

    update public.pachanga_groups
    set payload = current_group.payload || jsonb_build_object('players', next_players)
    where id = target_group_id
    returning payload, payload_revision
    into saved_payload, saved_revision;

    update public.pachanga_market_profiles
    set active = false,
        player_profile_id = coalesce(global_profile_id, player_profile_id),
        updated_at = now()
    where user_id = current_user_id
    returning * into saved_profile;

    perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
    if global_profile_id is not null then
      perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
    end if;

    return jsonb_build_object('active', false, 'id', saved_profile.id);
  end if;

  select coalesce(array_agg(value), '{}'::text[])
  into sanitized_zones
  from (
    select distinct left(trim(value), 80) as value
    from jsonb_array_elements_text(coalesce(market_patch -> 'zones', '[]'::jsonb)) as zones(value)
    where trim(value) <> ''
    limit 12
  ) as zone_values;

  select coalesce(jsonb_agg(zone_value order by zone_order), '[]'::jsonb)
  into sanitized_zones_geo
  from (
    select *
    from (
      select distinct on (zone_key)
        zone_key,
        ordinality as zone_order,
        jsonb_strip_nulls(jsonb_build_object(
          'placeId', left(coalesce(nullif(trim(value ->> 'placeId'), ''), zone_key), 160),
          'name', left(coalesce(nullif(trim(value ->> 'name'), ''), nullif(trim(value ->> 'city'), ''), 'Zona'), 80),
          'city', nullif(left(trim(coalesce(value ->> 'city', '')), 80), ''),
          'province', nullif(left(trim(coalesce(value ->> 'province', '')), 80), ''),
          'country', nullif(left(trim(coalesce(value ->> 'country', '')), 80), ''),
          'address', nullif(left(trim(coalesce(value ->> 'address', '')), 200), ''),
          'lat', case
            when coalesce(value ->> 'lat', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-90::numeric, least(90::numeric, (value ->> 'lat')::numeric))
            else null
          end,
          'lng', case
            when coalesce(value ->> 'lng', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-180::numeric, least(180::numeric, (value ->> 'lng')::numeric))
            else null
          end,
          'radiusKm', case
            when coalesce(value ->> 'radiusKm', '') ~ '^[0-9]+$' and (value ->> 'radiusKm')::integer in (0, 5, 10, 20, 30, 50) then (value ->> 'radiusKm')::integer
            else 0
          end
        )) as zone_value
      from jsonb_array_elements(
        case
          when jsonb_typeof(market_patch -> 'zonesGeo') = 'array' then market_patch -> 'zonesGeo'
          else '[]'::jsonb
        end
      ) with ordinality as zones(value, ordinality)
      cross join lateral (
        select coalesce(
          nullif(trim(value ->> 'placeId'), ''),
          lower(regexp_replace(coalesce(nullif(trim(value ->> 'name'), ''), nullif(trim(value ->> 'city'), ''), ''), '[[:space:]]+', ' ', 'g'))
        ) as zone_key
      ) as zone_keys
      where jsonb_typeof(value) = 'object'
        and zone_key <> ''
      order by zone_key, ordinality
    ) as deduped_zones
    order by zone_order
    limit 12
  ) as zone_values;

  select coalesce(array_agg(value), '{}'::text[])
  into sanitized_modalities
  from (
    select distinct value
    from jsonb_array_elements_text(coalesce(market_patch -> 'modalities', '[]'::jsonb)) as modalities(value)
    where value in ('sala', 'futbol7', 'futbol11')
  ) as modality_values;

  market_player_patch := jsonb_build_object(
    'marketEnabled', true,
    'marketZones', left(coalesce(market_patch ->> 'zonesText', market_patch ->> 'marketZones', array_to_string(sanitized_zones, ', ')), 320),
    'marketZonesGeo', sanitized_zones_geo,
    'marketAvailability', left(coalesce(market_patch ->> 'availabilityText', ''), 240),
    'marketBio', left(coalesce(market_patch ->> 'bio', ''), 280),
    'marketOpenToGroup', coalesce((market_patch ->> 'openToGroup')::boolean, true),
    'marketOpenToGuest', coalesce((market_patch ->> 'openToGuest')::boolean, true),
    'marketModalities', to_jsonb(sanitized_modalities)
  );

  global_profile_id := public.upsert_pachanga_player_profile_from_player(
    target_group_id,
    target_player_id,
    selected_player || market_player_patch
  );
  if global_profile_id is not null then
    market_player_patch := market_player_patch || public.pachanga_player_profile_patch(global_profile_id);
  end if;

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_player_id then value || market_player_patch
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  update public.pachanga_groups
  set payload = current_group.payload || jsonb_build_object('players', next_players)
  where id = target_group_id
  returning payload, payload_revision
  into saved_payload, saved_revision;

  insert into public.pachanga_market_profiles (
    user_id,
    player_profile_id,
    source_group_id,
    source_player_id,
    display_name,
    group_name,
    avatar,
    avatar_offset_x,
    avatar_offset_y,
    birth_date,
    position,
    goalkeeper_only,
    media,
    appearances,
    goals,
    wins,
    zones,
    zones_geo,
    availability_text,
    modalities,
    open_to_guest,
    open_to_group,
    bio,
    active
  )
  values (
    current_user_id,
    global_profile_id,
    target_group_id,
    target_player_id,
    coalesce(nullif(trim(market_patch ->> 'displayName'), ''), nullif(trim(selected_player ->> 'name'), ''), 'Jugador'),
    nullif(trim(coalesce(market_patch ->> 'groupName', current_group.name)), ''),
    nullif(market_patch ->> 'avatar', ''),
    least(100, greatest(0, coalesce(nullif(market_patch ->> 'avatarOffsetX', '')::numeric, 50))),
    least(100, greatest(0, coalesce(nullif(market_patch ->> 'avatarOffsetY', '')::numeric, 0))),
    nullif(market_patch ->> 'birthDate', '')::date,
    coalesce(nullif(trim(market_patch ->> 'position'), ''), 'Mediocentro / pivote'),
    coalesce((market_patch ->> 'goalkeeperOnly')::boolean, false),
    greatest(1, least(10, coalesce((market_patch ->> 'media')::numeric, 5))),
    greatest(0, coalesce((market_patch ->> 'appearances')::integer, 0)),
    greatest(0, coalesce((market_patch ->> 'goals')::integer, 0)),
    greatest(0, coalesce((market_patch ->> 'wins')::integer, 0)),
    sanitized_zones,
    sanitized_zones_geo,
    left(coalesce(market_patch ->> 'availabilityText', ''), 240),
    sanitized_modalities,
    coalesce((market_patch ->> 'openToGuest')::boolean, true),
    coalesce((market_patch ->> 'openToGroup')::boolean, true),
    left(coalesce(market_patch ->> 'bio', ''), 280),
    true
  )
  on conflict (user_id) do update set
    source_group_id = excluded.source_group_id,
    source_player_id = excluded.source_player_id,
    display_name = excluded.display_name,
    group_name = excluded.group_name,
    avatar = excluded.avatar,
    avatar_offset_x = excluded.avatar_offset_x,
    avatar_offset_y = excluded.avatar_offset_y,
    birth_date = excluded.birth_date,
    position = excluded.position,
    goalkeeper_only = excluded.goalkeeper_only,
    media = excluded.media,
    appearances = excluded.appearances,
    goals = excluded.goals,
    wins = excluded.wins,
    zones = excluded.zones,
    zones_geo = excluded.zones_geo,
    availability_text = excluded.availability_text,
    modalities = excluded.modalities,
    open_to_guest = excluded.open_to_guest,
    open_to_group = excluded.open_to_group,
    bio = excluded.bio,
    active = true,
    player_profile_id = excluded.player_profile_id,
    updated_at = now()
  returning * into saved_profile;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;

  return jsonb_build_object('active', saved_profile.active, 'id', saved_profile.id);
end;
$$;

drop function if exists public.sync_pachanga_open_match(uuid, text, jsonb);
create or replace function public.sync_pachanga_open_match(
  target_group_id uuid,
  target_match_id text,
  match_patch jsonb,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  existing_response jsonb;
  match_public_patch jsonb;
  max_media numeric;
  min_media numeric;
  next_matches jsonb;
  open_match public.pachanga_open_matches%rowtype;
  operation_response jsonb;
  open_slots integer;
  sanitized_positions text[];
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  selected_match jsonb;
  wants_active boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only admins can publish open matches';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = target_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = target_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Match not found';
  end if;

  wants_active := coalesce((match_patch ->> 'active')::boolean, false);

  if not wants_active then
    select coalesce(jsonb_agg(
      case
        when value ->> 'id' = target_match_id then value || jsonb_build_object('publicOpen', false)
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_matches
    from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

    current_payload := current_payload || jsonb_build_object('matches', next_matches);

    update public.pachanga_open_matches
    set active = false,
        updated_at = now()
    where source_group_id = target_group_id
      and source_match_id = target_match_id;

	    update public.pachanga_groups
	    set payload = current_payload
	    where id = target_group_id
	    returning payload, payload_revision, updated_at
	    into saved_payload, saved_revision, saved_updated_at;

    perform public.sync_pachanga_match_read_model(
      target_group_id,
      selected_match || jsonb_build_object('publicOpen', false),
      saved_revision
    );
    perform public.record_pachanga_group_event(
      target_group_id,
      target_match_id,
      'open_match_unpublished',
      jsonb_build_object('payloadRevision', saved_revision),
      operation_key,
      true
    );

    operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
    return public.remember_pachanga_operation(target_group_id, operation_key, 'open_match_unpublished', operation_response);
		  end if;

  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Save the match before publishing it';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'Finalized matches cannot be published';
  end if;
  if coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'Closed lineups cannot be published';
  end if;

  open_slots := greatest(0, least(
    greatest(1, coalesce((selected_match ->> 'targetPlayers')::integer, 1)),
    greatest(0, coalesce((match_patch ->> 'openSlots')::integer, 0))
  ));

  if open_slots < 1 then
    raise exception 'Open matches need at least one available slot';
  end if;

  min_media := greatest(0, least(10, coalesce((match_patch ->> 'minRating')::numeric, 0)));
  max_media := greatest(0, least(10, coalesce((match_patch ->> 'maxRating')::numeric, 10)));
  if min_media > max_media then
    min_media := max_media;
  end if;

  select coalesce(array_agg(value), '{}'::text[])
  into sanitized_positions
  from (
    select distinct value
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(match_patch -> 'positions') = 'array' then match_patch -> 'positions'
        else '[]'::jsonb
      end
    ) as positions(value)
    where value in ('Portero', 'Defensa', 'Medio', 'Ataque')
  ) as position_values;

  match_public_patch := jsonb_build_object(
    'publicOpen', true,
    'publicOpenSlots', open_slots,
    'publicMinRating', min_media,
    'publicMaxRating', max_media,
    'publicPositions', to_jsonb(sanitized_positions),
    'publicRequiresApproval', coalesce((match_patch ->> 'requiresApproval')::boolean, true),
    'publicGuestsPay', coalesce((match_patch ->> 'guestsPay')::boolean, true)
  );

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_match_id then value || match_public_patch
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('matches', next_matches);

  insert into public.pachanga_open_matches (
    source_group_id,
    source_match_id,
    group_name,
    title,
    date,
    date_text,
    day,
    modality,
    zone,
    place_id,
    lat,
    lng,
    field_name,
    field_cost,
    price_per_player,
    target_players,
    confirmed_count,
    open_slots,
    min_media,
    max_media,
    positions,
    requires_approval,
    guests_pay,
    group_level,
    match_url,
    active,
    created_by
  )
  values (
    target_group_id,
    target_match_id,
    left(coalesce(nullif(trim(match_patch ->> 'groupName'), ''), current_group.name, 'Grupo de pachangas'), 120),
    left(coalesce(nullif(trim(match_patch ->> 'title'), ''), selected_match ->> 'title', 'Partido abierto'), 120),
    coalesce(nullif(match_patch ->> 'date', ''), selected_match ->> 'date')::timestamptz,
    left(coalesce(match_patch ->> 'dateText', ''), 80),
    left(coalesce(match_patch ->> 'day', ''), 20),
    case when coalesce(match_patch ->> 'modality', selected_match ->> 'kind', 'futbol7') in ('sala', 'futbol7', 'futbol11')
      then coalesce(match_patch ->> 'modality', selected_match ->> 'kind', 'futbol7')
      else 'futbol7'
    end,
    left(coalesce(match_patch ->> 'zone', ''), 180),
    nullif(left(coalesce(match_patch ->> 'placeId', ''), 180), ''),
    case
      when coalesce(match_patch ->> 'lat', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-90::numeric, least(90::numeric, (match_patch ->> 'lat')::numeric))
      else null
    end,
    case
      when coalesce(match_patch ->> 'lng', '') ~ '^-?[0-9]+(\.[0-9]+)?$' then greatest(-180::numeric, least(180::numeric, (match_patch ->> 'lng')::numeric))
      else null
    end,
    left(coalesce(nullif(trim(match_patch ->> 'fieldName'), ''), selected_match ->> 'place', 'Campo por confirmar'), 140),
    greatest(0, coalesce((match_patch ->> 'fieldCost')::numeric, 0)),
    greatest(0, coalesce((match_patch ->> 'pricePerPlayer')::numeric, 0)),
    greatest(0, coalesce((match_patch ->> 'targetPlayers')::integer, coalesce((selected_match ->> 'targetPlayers')::integer, 0))),
    greatest(0, coalesce((match_patch ->> 'confirmedCount')::integer, 0)),
    open_slots,
    min_media,
    max_media,
    sanitized_positions,
    coalesce((match_patch ->> 'requiresApproval')::boolean, true),
    coalesce((match_patch ->> 'guestsPay')::boolean, true),
    case
      when coalesce(match_patch ->> 'groupLevel', '') ~ '^[0-9]+(\.[0-9]+)?$' then greatest(0::numeric, least(10::numeric, (match_patch ->> 'groupLevel')::numeric))
      else null
    end,
    left(coalesce(match_patch ->> 'matchUrl', ''), 500),
    true,
    auth.uid()
  )
  on conflict (source_group_id, source_match_id) do update set
    group_name = excluded.group_name,
    title = excluded.title,
    date = excluded.date,
    date_text = excluded.date_text,
    day = excluded.day,
    modality = excluded.modality,
    zone = excluded.zone,
    place_id = excluded.place_id,
    lat = excluded.lat,
    lng = excluded.lng,
    field_name = excluded.field_name,
    field_cost = excluded.field_cost,
    price_per_player = excluded.price_per_player,
    target_players = excluded.target_players,
    confirmed_count = excluded.confirmed_count,
    open_slots = excluded.open_slots,
    min_media = excluded.min_media,
    max_media = excluded.max_media,
    positions = excluded.positions,
    requires_approval = excluded.requires_approval,
    guests_pay = excluded.guests_pay,
    group_level = excluded.group_level,
    match_url = excluded.match_url,
    active = true,
    updated_at = now()
  returning * into open_match;

	  update public.pachanga_groups
	  set payload = current_payload
	  where id = target_group_id
	  returning payload, payload_revision, updated_at
	  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(target_group_id, selected_match || match_public_patch, saved_revision);
  perform public.record_pachanga_group_event(
    target_group_id,
    target_match_id,
    'open_match_published',
    jsonb_build_object(
      'openMatchId', open_match.id,
      'openSlots', open_slots,
      'payloadRevision', saved_revision
    ),
    operation_key,
    true
  );

  operation_response := jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
  return public.remember_pachanga_operation(target_group_id, operation_key, 'open_match_published', operation_response);
		end;
		$$;

drop function if exists public.request_pachanga_open_match(uuid);
create or replace function public.request_pachanga_open_match(target_open_match_id uuid, operation_key uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  existing_response jsonb;
  operation_response jsonb;
  saved_request public.pachanga_open_match_requests%rowtype;
  selected_open public.pachanga_open_matches%rowtype;
  selected_profile public.pachanga_market_profiles%rowtype;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select * into selected_open
  from public.pachanga_open_matches
  where id = target_open_match_id
    and active = true
  for update;

  if not found then
    raise exception 'Partido abierto no disponible';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = selected_open.source_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  if selected_open.open_slots < 1 then
    raise exception 'No quedan plazas abiertas';
  end if;

  select * into selected_profile
  from public.pachanga_market_profiles
  where user_id = current_user_id
    and active = true
  order by media desc, appearances desc, updated_at desc
  limit 1;

  if not found then
    raise exception 'Publica tu ficha en el mercado antes de solicitar plaza';
  end if;

  if coalesce(selected_profile.open_to_guest, true) = false then
    raise exception 'Tu ficha no acepta invitaciones puntuales';
  end if;

  if cardinality(selected_profile.modalities) > 0
    and not selected_open.modality = any(selected_profile.modalities)
  then
    raise exception 'Tu ficha no coincide con la modalidad del partido';
  end if;

  if selected_profile.media < selected_open.min_media
    or selected_profile.media > selected_open.max_media
  then
    raise exception 'Tu media no entra en el rango de este partido';
  end if;

  insert into public.pachanga_open_match_requests as requests (
    open_match_id,
    source_group_id,
    source_match_id,
    requester_user_id,
    requester_profile_id,
    requester_name,
    avatar,
    avatar_offset_x,
    avatar_offset_y,
    birth_date,
    position,
    goalkeeper_only,
    media,
    status,
    requested_at
  )
  values (
    selected_open.id,
    selected_open.source_group_id,
    selected_open.source_match_id,
    current_user_id,
    selected_profile.id,
    selected_profile.display_name,
    selected_profile.avatar,
    selected_profile.avatar_offset_x,
    selected_profile.avatar_offset_y,
    selected_profile.birth_date,
    selected_profile.position,
    selected_profile.goalkeeper_only,
    selected_profile.media,
    'pending',
    now()
  )
  on conflict (open_match_id, requester_user_id) do update set
    requester_profile_id = excluded.requester_profile_id,
    requester_name = excluded.requester_name,
    avatar = excluded.avatar,
    avatar_offset_x = excluded.avatar_offset_x,
    avatar_offset_y = excluded.avatar_offset_y,
    birth_date = excluded.birth_date,
    position = excluded.position,
    goalkeeper_only = excluded.goalkeeper_only,
    media = excluded.media,
    status = case
      when requests.status = 'accepted' then 'accepted'
      else 'pending'
    end,
	    requested_at = case
	      when requests.status in ('accepted', 'pending') then requests.requested_at
	      else now()
	    end,
    decided_by = case
      when requests.status = 'accepted' then requests.decided_by
      else null
    end,
    decided_at = case
      when requests.status = 'accepted' then requests.decided_at
      else null
    end,
    decision_note = null,
    updated_at = now()
	  returning * into saved_request;

  perform public.record_pachanga_group_event(
    selected_open.source_group_id,
    selected_open.source_match_id,
    'open_match_requested',
    jsonb_build_object(
      'openMatchId', selected_open.id,
      'requestId', saved_request.id,
      'requesterUserId', current_user_id,
      'status', saved_request.status
    ),
    operation_key,
    false
  );

  operation_response := jsonb_build_object(
	    'id', saved_request.id,
	    'status', saved_request.status
	  );

  return public.remember_pachanga_operation(selected_open.source_group_id, operation_key, 'open_match_requested', operation_response);
end;
$$;

drop function if exists public.review_pachanga_open_match_request(uuid, text);
create or replace function public.review_pachanga_open_match_request(
  target_request_id uuid,
  next_status text,
  operation_key uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  current_user_id uuid;
  existing_response jsonb;
  existing_entry jsonb;
  existing_player jsonb;
  next_confirmed_count integer;
  next_entry jsonb;
  next_match jsonb;
  next_match_players jsonb;
  next_matches jsonb;
  next_open_slots integer;
  next_player jsonb;
  next_players jsonb;
  operation_response jsonb;
  accepted_player_id text;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  selected_match jsonb;
  selected_open public.pachanga_open_matches%rowtype;
  selected_request public.pachanga_open_match_requests%rowtype;
  global_profile_id uuid;
  target_players integer;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;
  if next_status not in ('accepted', 'rejected') then
    raise exception 'Estado de solicitud no válido';
  end if;

  select * into selected_request
  from public.pachanga_open_match_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Solicitud no encontrada';
  end if;

  if not public.is_pachanga_group_admin(selected_request.source_group_id) then
    raise exception 'Solo los admins pueden revisar solicitudes';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = selected_request.source_group_id
  for update;

  if not found then
    raise exception 'Grupo no encontrado';
  end if;

  if operation_key is not null then
    select response into existing_response
    from public.pachanga_operation_receipts
    where group_id = selected_request.source_group_id
      and operation_id = operation_key;

    if existing_response is not null then
      return existing_response;
    end if;
  end if;

  current_payload := current_group.payload;

  if selected_request.status = next_status and next_status in ('accepted', 'rejected') then
    operation_response := jsonb_build_object(
      'payload', current_payload,
      'payload_revision', current_group.payload_revision,
      'updated_at', current_group.updated_at
    );
    return public.remember_pachanga_operation(
      selected_request.source_group_id,
      operation_key,
      'open_match_request_already_decided',
      operation_response
    );
  end if;

  if selected_request.status <> 'pending' then
    raise exception 'La solicitud ya estaba decidida';
  end if;

  if next_status = 'rejected' then
    update public.pachanga_open_match_requests
    set status = 'rejected',
        decided_by = current_user_id,
        decided_at = now(),
        updated_at = now()
	    where id = selected_request.id;

    perform public.record_pachanga_group_event(
      selected_request.source_group_id,
      selected_request.source_match_id,
      'open_match_request_rejected',
      jsonb_build_object('requestId', selected_request.id),
      operation_key,
      true
    );

    operation_response := jsonb_build_object(
	      'payload', current_payload,
	      'payload_revision', current_group.payload_revision,
	      'updated_at', current_group.updated_at
	    );

    return public.remember_pachanga_operation(
      selected_request.source_group_id,
      operation_key,
      'open_match_request_rejected',
      operation_response
    );
	  end if;

  select * into selected_open
  from public.pachanga_open_matches
  where id = selected_request.open_match_id
  for update;

  if not found or selected_open.active = false then
    raise exception 'El partido abierto ya no está disponible';
  end if;

  select value into selected_match
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) as value
  where value ->> 'id' = selected_request.source_match_id
  limit 1;

  if selected_match is null then
    raise exception 'Partido no encontrado';
  end if;
  if not coalesce((selected_match ->> 'configured')::boolean, false) then
    raise exception 'Guarda el partido antes de aceptar jugadores';
  end if;
  if coalesce((selected_match ->> 'closed')::boolean, false) or selected_match ? 'scoreA' then
    raise exception 'No se pueden aceptar jugadores en partidos finalizados';
  end if;
  if coalesce((selected_match ->> 'lineupClosed')::boolean, false) then
    raise exception 'La alineación está cerrada';
  end if;

  select value into existing_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'ownerUserId' = selected_request.requester_user_id::text
  limit 1;

  if existing_player is null then
    accepted_player_id := coalesce(
      nullif(selected_request.player_id, ''),
      'mk-' || substr(replace(selected_request.requester_user_id::text, '-', ''), 1, 8) || '-' || substr(replace(selected_request.id::text, '-', ''), 1, 6)
    );
    next_player := jsonb_strip_nulls(jsonb_build_object(
      'id', accepted_player_id,
      'name', left(coalesce(nullif(trim(selected_request.requester_name), ''), 'Jugador'), 80),
      'phone', '',
      'avatar', selected_request.avatar,
      'avatarOffsetX', selected_request.avatar_offset_x,
      'avatarOffsetY', selected_request.avatar_offset_y,
      'birthDate', selected_request.birth_date,
      'position', selected_request.position,
      'goalkeeperOnly', selected_request.goalkeeper_only,
      'rating', greatest(1::numeric, least(10::numeric, selected_request.media)),
      'importedRating', greatest(1::numeric, least(10::numeric, selected_request.media)),
      'importedRatingAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'importedRatingFromGroup', 'Mercado de fichajes',
      'goals', 0,
      'appearances', 0,
      'wins', 0,
      'injured', false,
      'inactive', false,
      'ownerUserId', selected_request.requester_user_id::text,
      'ratingVotes', '[]'::jsonb
    ));
    global_profile_id := public.upsert_pachanga_player_profile_from_player(
      selected_request.source_group_id,
      accepted_player_id,
      next_player
    );
    if global_profile_id is not null then
      next_player := next_player || public.pachanga_player_profile_patch(global_profile_id);
    end if;
    next_players := coalesce(current_payload -> 'players', '[]'::jsonb) || jsonb_build_array(next_player);
  else
    accepted_player_id := existing_player ->> 'id';
    select id into global_profile_id
    from public.pachanga_player_profiles
    where user_id = selected_request.requester_user_id;

    if global_profile_id is null then
      global_profile_id := public.upsert_pachanga_player_profile_from_player(
        selected_request.source_group_id,
        accepted_player_id,
        existing_player || jsonb_build_object('ownerUserId', selected_request.requester_user_id::text)
      );
    end if;

    if global_profile_id is not null then
      select coalesce(jsonb_agg(
        case
          when value ->> 'id' = accepted_player_id then value || public.pachanga_player_profile_patch(global_profile_id)
          else value
        end
        order by ordinality
      ), '[]'::jsonb)
      into next_players
      from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
    else
      next_players := coalesce(current_payload -> 'players', '[]'::jsonb);
    end if;
  end if;

  select value into existing_entry
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) as value
  where value ->> 'playerId' = accepted_player_id
  limit 1;

  select count(*) into next_confirmed_count
  from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) as entry(value)
  where value ->> 'status' = 'voy';

  target_players := greatest(0, coalesce((selected_match ->> 'targetPlayers')::integer, selected_open.target_players, 0));

  if (existing_entry is null or existing_entry ->> 'status' <> 'voy')
    and next_confirmed_count >= target_players
  then
    raise exception 'No quedan plazas en este partido';
  end if;

  next_entry := jsonb_build_object(
    'playerId', accepted_player_id,
    'status', 'voy',
    'paid', false,
    'joinedAt', to_char(selected_request.requested_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );

  if existing_entry is null then
    next_match_players := coalesce(selected_match -> 'players', '[]'::jsonb) || jsonb_build_array(next_entry);
  else
    select coalesce(jsonb_agg(
      case
        when value ->> 'playerId' = accepted_player_id then value || next_entry
        else value
      end
      order by ordinality
    ), '[]'::jsonb)
    into next_match_players
    from jsonb_array_elements(coalesce(selected_match -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);
  end if;

  select count(*) into next_confirmed_count
  from jsonb_array_elements(next_match_players) as entry(value)
  where value ->> 'status' = 'voy';

  next_open_slots := greatest(target_players - next_confirmed_count, 0);
  next_match := selected_match || jsonb_build_object(
    'players', next_match_players,
    'publicOpen', next_open_slots > 0,
    'publicOpenSlots', greatest(next_open_slots, 1)
  );

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = selected_request.source_match_id then next_match
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_matches
  from jsonb_array_elements(coalesce(current_payload -> 'matches', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object(
    'players', next_players,
    'matches', next_matches
  );

  insert into public.pachanga_group_members (group_id, user_id, role, display_name)
  values (selected_request.source_group_id, selected_request.requester_user_id, 'player', selected_request.requester_name)
  on conflict (group_id, user_id) do update set
    display_name = coalesce(nullif(public.pachanga_group_members.display_name, ''), excluded.display_name);

  update public.pachanga_open_match_requests
  set status = 'accepted',
      player_id = accepted_player_id,
      decided_by = current_user_id,
      decided_at = now(),
      updated_at = now()
  where id = selected_request.id;

  update public.pachanga_open_matches
  set confirmed_count = next_confirmed_count,
      open_slots = next_open_slots,
      active = next_open_slots > 0,
      updated_at = now()
  where id = selected_open.id;

  update public.pachanga_groups
  set payload = current_payload
  where id = selected_request.source_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_match_read_model(selected_request.source_group_id, next_match, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, selected_request.source_group_id);
  end if;
  perform public.record_pachanga_group_event(
    selected_request.source_group_id,
    selected_request.source_match_id,
    'open_match_request_accepted',
    jsonb_build_object(
      'requestId', selected_request.id,
      'playerId', accepted_player_id,
      'confirmedCount', next_confirmed_count,
      'openSlots', next_open_slots,
      'payloadRevision', saved_revision
    ),
    operation_key,
    true
  );

  operation_response := jsonb_build_object(
    'payload', saved_payload,
    'payload_revision', saved_revision,
    'updated_at', saved_updated_at
  );

  return public.remember_pachanga_operation(
    selected_request.source_group_id,
    operation_key,
    'open_match_request_accepted',
    operation_response
  );
end;
$$;

create or replace function public.append_pachanga_player_rating(
  target_group_id uuid,
  target_player_id text,
  vote_facets jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_user_id uuid;
  current_group public.pachanga_groups%rowtype;
  current_payload jsonb;
  selected_player jsonb;
  selected_member_name text;
  clean_facets jsonb;
  last_vote_match_count integer;
  player_appearances integer;
  next_vote jsonb;
  patched_player jsonb;
  next_players jsonb;
  saved_payload jsonb;
  saved_revision bigint;
  saved_updated_at timestamptz;
  global_profile_id uuid;
  selected_owner_id uuid;
begin
  current_user_id := auth.uid();
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;
  if not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  if not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Only members can rate players';
  end if;

  select * into current_group
  from public.pachanga_groups
  where id = target_group_id
  for update;

  if not found then
    raise exception 'Group not found';
  end if;

  current_payload := current_group.payload;

  select value into selected_player
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) as value
  where value ->> 'id' = target_player_id
  limit 1;

  if selected_player is null then
    raise exception 'Player not found';
  end if;

  if coalesce(selected_player ->> 'ownerUserId', '') = current_user_id::text then
    raise exception 'You cannot rate yourself';
  end if;

  if coalesce((selected_player ->> 'inactive')::boolean, false) then
    raise exception 'Inactive players cannot be rated';
  end if;

  player_appearances := greatest(0, coalesce((selected_player ->> 'appearances')::integer, 0));

  select max(greatest(0, coalesce((vote.value ->> 'matchCount')::integer, 0)))
  into last_vote_match_count
  from jsonb_array_elements(coalesce(selected_player -> 'ratingVotes', '[]'::jsonb)) as vote(value)
  where vote.value ->> 'voterId' = current_user_id::text;

  if player_appearances < coalesce(last_vote_match_count + 3, case when player_appearances = 0 then 0 else 3 end) then
    raise exception 'Rating window closed for this player';
  end if;

  select display_name into selected_member_name
  from public.pachanga_group_members
  where group_id = target_group_id
    and user_id = current_user_id;

  clean_facets := jsonb_build_object(
    'ritmo', greatest(1, least(10, coalesce((vote_facets ->> 'ritmo')::numeric, 5))),
    'tiro', greatest(1, least(10, coalesce((vote_facets ->> 'tiro')::numeric, 5))),
    'pase', greatest(1, least(10, coalesce((vote_facets ->> 'pase')::numeric, 5))),
    'regate', greatest(1, least(10, coalesce((vote_facets ->> 'regate')::numeric, 5))),
    'defensa', greatest(1, least(10, coalesce((vote_facets ->> 'defensa')::numeric, 5))),
    'fisico', greatest(1, least(10, coalesce((vote_facets ->> 'fisico')::numeric, 5)))
  );

  next_vote := jsonb_build_object(
    'id', gen_random_uuid()::text,
    'voterId', current_user_id::text,
    'voterName', selected_member_name,
    'ratingRole',
      case
        when coalesce((selected_player ->> 'goalkeeperOnly')::boolean, false)
          or coalesce(selected_player ->> 'position', '') in ('Portero', 'Porteria')
        then 'goalkeeper'
        else 'field'
      end,
    'matchCount', player_appearances,
    'createdAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'facets', clean_facets
  );

  patched_player := selected_player || jsonb_build_object('ratingVotes', coalesce(selected_player -> 'ratingVotes', '[]'::jsonb) || jsonb_build_array(next_vote));

  if coalesce(selected_player ->> 'ownerUserId', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    selected_owner_id := (selected_player ->> 'ownerUserId')::uuid;

    update public.pachanga_player_profiles
    set rating_votes = coalesce(rating_votes, '[]'::jsonb) || jsonb_build_array(next_vote),
        profile_version = profile_version + 1,
        updated_at = now()
    where user_id = selected_owner_id
    returning id into global_profile_id;

    if global_profile_id is null then
      global_profile_id := public.upsert_pachanga_player_profile_from_player(target_group_id, target_player_id, patched_player);
    end if;

    if global_profile_id is not null then
      patched_player := patched_player || public.pachanga_player_profile_patch(global_profile_id);
    end if;
  end if;

  select coalesce(jsonb_agg(
    case
      when value ->> 'id' = target_player_id then patched_player
      else value
    end
    order by ordinality
  ), '[]'::jsonb)
  into next_players
  from jsonb_array_elements(coalesce(current_payload -> 'players', '[]'::jsonb)) with ordinality as entries(value, ordinality);

  current_payload := current_payload || jsonb_build_object('players', next_players);

  update public.pachanga_groups
  set payload = current_payload
  where id = target_group_id
  returning payload, payload_revision, updated_at
  into saved_payload, saved_revision, saved_updated_at;

  perform public.sync_pachanga_group_read_model(target_group_id, saved_payload, saved_revision);
  if global_profile_id is not null then
    perform public.sync_pachanga_player_profile_to_groups(global_profile_id, target_group_id);
  end if;

  return jsonb_build_object('payload', saved_payload, 'payload_revision', saved_revision, 'updated_at', saved_updated_at);
end;
$$;

revoke all on function public.join_pachanga_group(uuid) from public;
revoke execute on function public.join_pachanga_group(uuid) from anon;
grant execute on function public.join_pachanga_group(uuid) to authenticated;
revoke all on function public.join_pachanga_team(uuid, text) from public;
revoke execute on function public.join_pachanga_team(uuid, text) from anon;
grant execute on function public.join_pachanga_team(uuid, text) to authenticated;
revoke all on function public.create_pachanga_admin_invite(uuid, uuid) from public;
revoke execute on function public.create_pachanga_admin_invite(uuid, uuid) from anon;
grant execute on function public.create_pachanga_admin_invite(uuid, uuid) to authenticated;
revoke all on function public.accept_pachanga_admin_invite(uuid, text) from public;
revoke execute on function public.accept_pachanga_admin_invite(uuid, text) from anon;
grant execute on function public.accept_pachanga_admin_invite(uuid, text) to authenticated;
revoke all on function public.update_pachanga_member_name(uuid, text) from public;
revoke execute on function public.update_pachanga_member_name(uuid, text) from anon;
grant execute on function public.update_pachanga_member_name(uuid, text) to authenticated;
revoke all on function public.set_pachanga_member_role(uuid, uuid, text, uuid) from public;
revoke execute on function public.set_pachanga_member_role(uuid, uuid, text, uuid) from anon;
grant execute on function public.set_pachanga_member_role(uuid, uuid, text, uuid) to authenticated;
revoke all on function public.create_pachanga_group_backup(uuid, text, jsonb) from public;
revoke execute on function public.create_pachanga_group_backup(uuid, text, jsonb) from anon;
grant execute on function public.create_pachanga_group_backup(uuid, text, jsonb) to authenticated;
revoke all on function public.restore_pachanga_group_backup(uuid) from public;
revoke execute on function public.restore_pachanga_group_backup(uuid) from anon;
grant execute on function public.restore_pachanga_group_backup(uuid) to authenticated;
revoke all on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from public;
revoke execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) from anon;
grant execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb) to authenticated;
revoke all on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid) from public;
revoke execute on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid) from anon;
grant execute on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid) to authenticated;
revoke all on function public.patch_pachanga_match_player_status(uuid, text, text, text, uuid) from public;
revoke execute on function public.patch_pachanga_match_player_status(uuid, text, text, text, uuid) from anon;
grant execute on function public.patch_pachanga_match_player_status(uuid, text, text, text, uuid) to authenticated;
revoke all on function public.patch_pachanga_match_lineup_state(uuid, text, boolean, text[], text[], text, uuid) from public;
revoke execute on function public.patch_pachanga_match_lineup_state(uuid, text, boolean, text[], text[], text, uuid) from anon;
grant execute on function public.patch_pachanga_match_lineup_state(uuid, text, boolean, text[], text[], text, uuid) to authenticated;
revoke all on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean, uuid) from public;
revoke execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean, uuid) from anon;
grant execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean, uuid) to authenticated;
revoke all on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[], uuid) from public;
revoke execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[], uuid) from anon;
grant execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[], uuid) to authenticated;
revoke all on function public.upsert_pachanga_own_player_profile(uuid, text, jsonb) from public;
revoke execute on function public.upsert_pachanga_own_player_profile(uuid, text, jsonb) from anon;
grant execute on function public.upsert_pachanga_own_player_profile(uuid, text, jsonb) to authenticated;
revoke all on function public.patch_pachanga_player_profile(uuid, text, jsonb) from public;
revoke execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) from anon;
grant execute on function public.patch_pachanga_player_profile(uuid, text, jsonb) to authenticated;
revoke all on function public.sync_pachanga_market_profile(uuid, text, jsonb) from public;
revoke execute on function public.sync_pachanga_market_profile(uuid, text, jsonb) from anon;
grant execute on function public.sync_pachanga_market_profile(uuid, text, jsonb) to authenticated;
revoke all on function public.sync_pachanga_open_match(uuid, text, jsonb, uuid) from public;
revoke execute on function public.sync_pachanga_open_match(uuid, text, jsonb, uuid) from anon;
grant execute on function public.sync_pachanga_open_match(uuid, text, jsonb, uuid) to authenticated;
revoke all on function public.request_pachanga_open_match(uuid, uuid) from public;
revoke execute on function public.request_pachanga_open_match(uuid, uuid) from anon;
grant execute on function public.request_pachanga_open_match(uuid, uuid) to authenticated;
revoke all on function public.review_pachanga_open_match_request(uuid, text, uuid) from public;
revoke execute on function public.review_pachanga_open_match_request(uuid, text, uuid) from anon;
grant execute on function public.review_pachanga_open_match_request(uuid, text, uuid) to authenticated;
revoke all on function public.append_pachanga_player_rating(uuid, text, jsonb) from public;
revoke execute on function public.append_pachanga_player_rating(uuid, text, jsonb) from anon;
grant execute on function public.append_pachanga_player_rating(uuid, text, jsonb) to authenticated;
revoke all on function public.pachanga_assessment_clamp(numeric, numeric, numeric) from public;
revoke execute on function public.pachanga_assessment_clamp(numeric, numeric, numeric) from anon;
revoke execute on function public.pachanga_assessment_clamp(numeric, numeric, numeric) from authenticated;
revoke all on function public.pachanga_assessment_response_score(jsonb, text, numeric, boolean) from public;
revoke execute on function public.pachanga_assessment_response_score(jsonb, text, numeric, boolean) from anon;
revoke execute on function public.pachanga_assessment_response_score(jsonb, text, numeric, boolean) from authenticated;
revoke all on function public.pachanga_assessment_overall_weight(text, text) from public;
revoke execute on function public.pachanga_assessment_overall_weight(text, text) from anon;
revoke execute on function public.pachanga_assessment_overall_weight(text, text) from authenticated;
revoke all on function public.pachanga_assessment_mode_confidence(jsonb, text) from public;
revoke execute on function public.pachanga_assessment_mode_confidence(jsonb, text) from anon;
revoke execute on function public.pachanga_assessment_mode_confidence(jsonb, text) from authenticated;
revoke all on function public.pachanga_assessment_app_position(text) from public;
revoke execute on function public.pachanga_assessment_app_position(text) from anon;
revoke execute on function public.pachanga_assessment_app_position(text) from authenticated;
revoke all on function public.pachanga_assessment_facets_from_attributes(jsonb) from public;
revoke execute on function public.pachanga_assessment_facets_from_attributes(jsonb) from anon;
revoke execute on function public.pachanga_assessment_facets_from_attributes(jsonb) from authenticated;
revoke all on function public.calculate_pachanga_initial_assessment(jsonb) from public;
revoke execute on function public.calculate_pachanga_initial_assessment(jsonb) from anon;
revoke execute on function public.calculate_pachanga_initial_assessment(jsonb) from authenticated;
revoke all on function public.calculate_pachanga_advanced_assessment(jsonb, jsonb) from public;
revoke execute on function public.calculate_pachanga_advanced_assessment(jsonb, jsonb) from anon;
revoke execute on function public.calculate_pachanga_advanced_assessment(jsonb, jsonb) from authenticated;
revoke all on function public.pachanga_assessment_without_self_votes(jsonb, uuid) from public;
revoke execute on function public.pachanga_assessment_without_self_votes(jsonb, uuid) from anon;
revoke execute on function public.pachanga_assessment_without_self_votes(jsonb, uuid) from authenticated;
revoke all on function public.pachanga_assessment_summary_item(jsonb, timestamptz) from public;
revoke execute on function public.pachanga_assessment_summary_item(jsonb, timestamptz) from anon;
revoke execute on function public.pachanga_assessment_summary_item(jsonb, timestamptz) from authenticated;
revoke all on function public.complete_pachanga_player_initial_assessment(uuid, text, jsonb, jsonb, uuid) from public;
revoke execute on function public.complete_pachanga_player_initial_assessment(uuid, text, jsonb, jsonb, uuid) from anon;
grant execute on function public.complete_pachanga_player_initial_assessment(uuid, text, jsonb, jsonb, uuid) to authenticated;
revoke all on function public.complete_pachanga_player_advanced_assessment(uuid, text, jsonb, jsonb, uuid) from public;
revoke execute on function public.complete_pachanga_player_advanced_assessment(uuid, text, jsonb, jsonb, uuid) from anon;
grant execute on function public.complete_pachanga_player_advanced_assessment(uuid, text, jsonb, jsonb, uuid) to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_groups'
  ) then
    alter publication supabase_realtime add table public.pachanga_groups;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_open_match_requests'
  ) then
    alter publication supabase_realtime add table public.pachanga_open_match_requests;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_group_events'
  ) then
    alter publication supabase_realtime add table public.pachanga_group_events;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_match_read_model'
  ) then
    alter publication supabase_realtime add table public.pachanga_match_read_model;
  end if;
end;
$$;
