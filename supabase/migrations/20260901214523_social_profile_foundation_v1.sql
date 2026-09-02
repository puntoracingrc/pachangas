-- Official UI V3F: independent social identity without touching Rating V2.

set lock_timeout = '5s';
set statement_timeout = '120s';

create schema if not exists private;

create sequence if not exists private.pachanga_social_team_sequence_v1;
revoke all on sequence private.pachanga_social_team_sequence_v1 from public, anon, authenticated;
grant usage, select on sequence private.pachanga_social_team_sequence_v1 to service_role;

create table if not exists private.pachanga_social_team_settings_v1 (
  singleton boolean primary key default true check (singleton),
  social_profile_foundation_enabled boolean not null default false,
  social_profile_independent_write_enabled boolean not null default false,
  social_team_creation_enabled boolean not null default false,
  social_team_invitation_v2_enabled boolean not null default false,
  social_team_membership_v2_enabled boolean not null default false,
  social_team_home_v3f_enabled boolean not null default false,
  demo_social_team_journey_enabled boolean not null default false,
  revision bigint not null default 1 check (revision >= 1),
  server_sequence bigint not null default nextval('private.pachanga_social_team_sequence_v1'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (not social_profile_independent_write_enabled or social_profile_foundation_enabled),
  check (not social_team_creation_enabled or social_profile_independent_write_enabled),
  check (not social_team_invitation_v2_enabled or social_team_creation_enabled),
  check (not social_team_membership_v2_enabled or social_team_invitation_v2_enabled),
  check (not social_team_home_v3f_enabled or social_team_creation_enabled),
  check (not demo_social_team_journey_enabled or social_team_home_v3f_enabled)
);

insert into private.pachanga_social_team_settings_v1(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists public.pachanga_social_player_profiles_v1 (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  avatar_ref text,
  primary_position text not null,
  secondary_position text,
  preferred_modality text not null,
  general_area text not null default '',
  usual_days text[] not null default '{}',
  approximate_time text not null default '',
  short_bio text not null default '',
  social_preferences jsonb not null default '{}'::jsonb,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_social_team_sequence_v1'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (char_length(trim(display_name)) between 1 and 80),
  check (primary_position in (
    'Portero','Defensa central','Lateral','Mediocentro / pivote',
    'Interior / volante','Mediapunta','Extremo','Delantero / punta'
  )),
  check (secondary_position is null or secondary_position in (
    'Portero','Defensa central','Lateral','Mediocentro / pivote',
    'Interior / volante','Mediapunta','Extremo','Delantero / punta'
  )),
  check (preferred_modality in ('sala','futbol7','futbol11')),
  check (char_length(general_area) <= 120),
  check (usual_days <@ array['L','M','X','J','V','S','D']::text[]),
  check (cardinality(usual_days) <= 7),
  check (approximate_time in ('','08:00-12:00','12:00-16:00','16:00-20:00','20:00-22:00','22:00-00:00')),
  check (char_length(short_bio) <= 280),
  check (avatar_ref is null or char_length(avatar_ref) <= 1024),
  check (jsonb_typeof(social_preferences) = 'object'),
  check (revision >= 1),
  check (server_sequence >= 1)
);

create table if not exists private.pachanga_social_player_profile_revisions_v1 (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  revision bigint not null,
  snapshot jsonb not null,
  operation_id uuid not null,
  actor_id uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (user_id, revision),
  unique (operation_id, revision),
  check (revision >= 1),
  check (server_sequence >= 1),
  check (jsonb_typeof(snapshot) = 'object')
);

create index if not exists pachanga_social_profiles_updated_idx
  on public.pachanga_social_player_profiles_v1(updated_at desc, user_id);
create unique index if not exists pachanga_social_profiles_sequence_idx
  on public.pachanga_social_player_profiles_v1(server_sequence, user_id);
create index if not exists pachanga_social_profile_revisions_user_idx
  on private.pachanga_social_player_profile_revisions_v1(user_id, revision desc, id);

alter table public.pachanga_social_player_profiles_v1 enable row level security;

revoke all on table private.pachanga_social_team_settings_v1 from public, anon, authenticated;
revoke all on table private.pachanga_social_player_profile_revisions_v1 from public, anon, authenticated;
revoke all on table public.pachanga_social_player_profiles_v1 from public, anon, authenticated;

grant all on table private.pachanga_social_team_settings_v1 to service_role;
grant all on table private.pachanga_social_player_profile_revisions_v1 to service_role;
grant select on table public.pachanga_social_player_profiles_v1 to authenticated, service_role;

drop policy if exists "Users read their own social profile v1"
  on public.pachanga_social_player_profiles_v1;
create policy "Users read their own social profile v1"
on public.pachanga_social_player_profiles_v1
for select
to authenticated
using ((select auth.uid()) = user_id);

comment on table public.pachanga_social_player_profiles_v1 is
  'V3F global social identity. It never owns Rating, facets, cards, sanctions or membership.';
comment on table private.pachanga_social_player_profile_revisions_v1 is
  'Immutable V3F social identity history. Sporting profile and Rating V2 remain separate.';
