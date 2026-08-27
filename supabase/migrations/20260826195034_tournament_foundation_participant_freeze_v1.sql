-- Pachangas IQ R6A: private Tournament foundation and immutable participant freezes.
-- Every Tournament gate is born OFF. This migration creates no Tournament or match data.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists tournament_foundation_enabled boolean not null default false,
  add column if not exists tournament_private_beta_enabled boolean not null default false,
  add column if not exists tournament_creation_enabled boolean not null default false,
  add column if not exists tournament_draw_enabled boolean not null default false,
  add column if not exists tournament_automatic_draw_enabled boolean not null default false,
  add column if not exists tournament_draw_manual_enabled boolean not null default false,
  add column if not exists tournament_draw_hybrid_enabled boolean not null default false,
  add column if not exists tournament_draw_publish_enabled boolean not null default false,
  add column if not exists tournament_public_discovery_enabled boolean not null default false,
  add column if not exists tournament_match_generation_enabled boolean not null default false,
  add column if not exists tournament_bracket_progression_enabled boolean not null default false,
  add column if not exists tournament_standard_team_cap smallint not null default 32,
  add column if not exists tournament_override_team_cap smallint not null default 64;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_tournament_flags_check,
  drop constraint if exists pachanga_comp_foundation_tournament_limits_check,
  add constraint pachanga_comp_foundation_tournament_limits_check check (
    tournament_standard_team_cap = 32
    and tournament_override_team_cap = 64
  ),
  add constraint pachanga_comp_foundation_tournament_flags_check check (
    (not tournament_private_beta_enabled or tournament_foundation_enabled)
    and (not tournament_creation_enabled or (
      tournament_private_beta_enabled and foundation_enabled and creation_enabled
    ))
    and (not tournament_draw_enabled or tournament_private_beta_enabled)
    and (not tournament_automatic_draw_enabled or tournament_draw_enabled)
    and (not tournament_draw_manual_enabled or tournament_draw_enabled)
    and (not tournament_draw_hybrid_enabled or (
      tournament_draw_enabled and tournament_draw_manual_enabled
    ))
    and (not tournament_draw_publish_enabled or tournament_draw_enabled)
    and (not tournament_public_discovery_enabled or tournament_foundation_enabled)
    and (not tournament_match_generation_enabled or tournament_draw_publish_enabled)
    and (not tournament_bracket_progression_enabled or tournament_match_generation_enabled)
  );

alter table public.pachanga_competitions
  add column if not exists tournament_revision bigint not null default 0;

alter table public.pachanga_competitions
  drop constraint if exists pachanga_competitions_tournament_revision_check,
  drop constraint if exists pachanga_competitions_product_key_check,
  add constraint pachanga_competitions_tournament_revision_check check (tournament_revision >= 0),
  add constraint pachanga_competitions_product_key_check check (
    product_key is null
    or product_key in ('LEAGUE_PRIVATE_BETA_V1', 'TOURNAMENT_PRIVATE_BETA_V1')
  );

-- The League beta may remain active while the private Tournament beta is used.
-- Preserve every League guard while routing the explicit Tournament product to R6A.
create or replace function private.pachanga_league_private_beta_guard_competition_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;

  if new.product_key = 'TOURNAMENT_PRIVATE_BETA_V1' then
    if new.competition_type <> 'TOURNAMENT' then
      raise exception 'TOURNAMENT_PRIVATE_BETA_TYPE_REQUIRED' using errcode = '22023';
    end if;
    if new.visibility <> 'private' then
      raise exception 'TOURNAMENT_PRIVATE_BETA_VISIBILITY_REQUIRED' using errcode = '22023';
    end if;
    return new;
  end if;

  if new.product_key = 'LEAGUE_PRIVATE_BETA_V1'
     or settings.league_private_beta_enabled then
    if not settings.league_private_beta_enabled then
      raise exception 'LEAGUE_PRIVATE_BETA_DISABLED' using errcode = '42501';
    end if;
    if current_setting('pachangas.league_private_beta_authorized', true) <> 'on' then
      raise exception 'LEAGUE_PRIVATE_BETA_COMMAND_REQUIRED' using errcode = '42501';
    end if;
    if not settings.league_private_beta_creation_enabled then
      raise exception 'LEAGUE_PRIVATE_BETA_CREATION_DISABLED' using errcode = '42501';
    end if;
    if new.competition_type <> 'LEAGUE' then
      raise exception 'TOURNAMENT_ENGINE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    if new.visibility <> 'private' then
      raise exception 'LEAGUE_PRIVATE_BETA_VISIBILITY_REQUIRED' using errcode = '22023';
    end if;
    new.product_key := 'LEAGUE_PRIVATE_BETA_V1';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_private_beta_guard_competition_v1()
  from public, anon, authenticated;

alter table public.pachanga_competition_entitlement_grants
  drop constraint if exists pachanga_competition_entitlement_grants_capability_check,
  drop constraint if exists pachanga_competition_entitlement_beta_bundle_check,
  add constraint pachanga_competition_entitlement_grants_capability_check check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline', 'competition_entries_manage',
    'competition_rosters_review', 'competition_categories_manage', 'competition_schedule',
    'competition_results', 'competition_standings', 'competition_operations',
    'competition_discipline_manage', 'competition_discipline_review',
    'competition_appeals_manage', 'tournament_create', 'tournament_manage',
    'tournament_draw', 'tournament_draw_publish'
  )),
  add constraint pachanga_competition_entitlement_beta_bundle_check check (
    (
      program_key is null
      and bundle_id is null
      and beta_team_cap is null
    )
    or (
      program_key = 'LEAGUE_PRIVATE_BETA_V1'
      and bundle_id is not null
      and beta_team_cap between 4 and 20
      and grant_source = 'platform_grant'
      and position('LEAGUE_PRIVATE_BETA_V1' in reason) > 0
    )
    or (
      program_key = 'TOURNAMENT_PRIVATE_BETA_V1'
      and bundle_id is not null
      and beta_team_cap between 4 and 64
      and grant_source = 'platform_grant'
      and position('TOURNAMENT_PRIVATE_BETA_V1' in reason) > 0
    )
  );

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'competition_schedule_manager',
    'competition_result_manager', 'competition_standings_manager',
    'competition_operations_manager', 'competition_discipline_manager',
    'competition_discipline_reviewer', 'competition_appeals_manager',
    'competition_draw_manager', 'viewer'
  ));

create index if not exists pachanga_tournament_beta_bundle_idx
  on public.pachanga_competition_entitlement_grants(
    bundle_id, capability, server_sequence desc, id desc
  ) where program_key = 'TOURNAMENT_PRIVATE_BETA_V1';

create index if not exists pachanga_tournament_beta_organizer_idx
  on public.pachanga_competition_entitlement_grants(
    organizer_kind, organizer_group_id, organizer_club_id,
    status, expires_at, server_sequence desc, id desc
  ) where program_key = 'TOURNAMENT_PRIVATE_BETA_V1';

create index if not exists pachanga_tournament_team_competition_idx
  on public.pachanga_competitions(
    organizer_group_id, status, tournament_revision desc, id
  ) where product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
    and organizer_kind = 'TEAM';

create index if not exists pachanga_tournament_club_competition_idx
  on public.pachanga_competitions(
    organizer_club_id, status, tournament_revision desc, id
  ) where product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
    and organizer_kind = 'CLUB';

create table public.pachanga_competition_participant_freezes (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  entry_ids uuid[] not null,
  entry_snapshot jsonb not null,
  roster_readiness jsonb not null,
  seeding_snapshot jsonb not null,
  club_relationship_snapshot jsonb not null,
  participant_count smallint not null,
  tournament_revision bigint not null,
  checksum text not null,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  frozen_by uuid not null references auth.users(id) on delete restrict,
  frozen_at timestamptz not null default clock_timestamp(),
  check (participant_count between 4 and 64),
  check (cardinality(entry_ids) = participant_count),
  check (jsonb_typeof(entry_snapshot) = 'array'),
  check (jsonb_typeof(roster_readiness) = 'object'),
  check (jsonb_typeof(seeding_snapshot) = 'object'),
  check (jsonb_typeof(club_relationship_snapshot) = 'object'),
  check (length(checksum) = 64),
  check (revision = 1),
  check (tournament_revision >= 0)
);

create index pachanga_tournament_freeze_scope_idx
  on public.pachanga_competition_participant_freezes(
    competition_id, edition_id, stage_id, server_sequence desc, id desc
  );

create table public.pachanga_tournament_invalidations (
  server_sequence bigint primary key,
  competition_id uuid not null references public.pachanga_competitions(id) on delete cascade,
  target_user_id uuid references auth.users(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  revision bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (revision >= 0),
  check (length(trim(entity_type)) between 3 and 80),
  check (length(trim(entity_id)) between 1 and 120)
);

create index pachanga_tournament_invalidations_competition_idx
  on public.pachanga_tournament_invalidations(
    competition_id, server_sequence desc
  );

create index pachanga_tournament_invalidations_user_idx
  on public.pachanga_tournament_invalidations(
    target_user_id, server_sequence desc
  ) where target_user_id is not null;

alter table public.pachanga_competition_participant_freezes enable row level security;
alter table public.pachanga_tournament_invalidations enable row level security;

revoke all on table public.pachanga_competition_participant_freezes
  from public, anon, authenticated;
revoke all on table public.pachanga_tournament_invalidations
  from public, anon, authenticated;
grant all on table public.pachanga_competition_participant_freezes to service_role;
grant all on table public.pachanga_tournament_invalidations to service_role;
grant select on table public.pachanga_tournament_invalidations to authenticated;

create or replace function private.pachanga_tournament_guard_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'TOURNAMENT_HISTORY_IMMUTABLE' using errcode = '55000';
end;
$$;

revoke all on function private.pachanga_tournament_guard_immutable_v1()
  from public, anon, authenticated;

create trigger guard_pachanga_tournament_participant_freeze_v1
before update or delete on public.pachanga_competition_participant_freezes
for each row execute function private.pachanga_tournament_guard_immutable_v1();

comment on table public.pachanga_competition_participant_freezes is
  'R6A immutable Tournament participant evidence. It never acts as a live entry list.';
comment on table public.pachanga_tournament_invalidations is
  'Transport-only invalidations. Clients must refetch a canonical Tournament snapshot.';
