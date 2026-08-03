-- Pachangas IQ rating system V2: final client boundary, anonymity and global calibration.
-- This migration is additive and deliberately leaves legacy routines available only to
-- trusted server-side functions while removing every client EXECUTE grant.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

alter table public.pachanga_groups
  add column if not exists ratings_enabled boolean not null default true,
  add column if not exists externally_calibrated_level numeric,
  add column if not exists external_calibration_snapshot jsonb not null default '{}'::jsonb,
  add column if not exists external_calibrated_at timestamptz;

alter table public.pachanga_guest_identities
  add column if not exists provisional_observation_count integer not null default 0,
  add column if not exists provisional_last_observed_at timestamptz;

alter table public.pachanga_external_teams
  add column if not exists stable_level numeric,
  add column if not exists calibration_observation_count integer not null default 0,
  add column if not exists calibrated_at timestamptz;

alter table public.pachanga_global_rating_responses
  add column if not exists operation_id uuid;

create unique index if not exists pachanga_global_rating_actor_operation_idx
  on public.pachanga_global_rating_responses(actor_user_id, operation_id)
  where actor_user_id is not null and operation_id is not null;

create table if not exists public.pachanga_rating_config_events (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  operation_id uuid not null,
  previous_enabled boolean not null,
  next_enabled boolean not null,
  created_at timestamptz not null default now(),
  unique (group_id, operation_id)
);

create table if not exists public.pachanga_guest_rating_tokens (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  match_id text not null,
  guest_identity_id uuid not null references public.pachanga_guest_identities(id) on delete restrict,
  action text not null default 'rate_host_team',
  issued_by uuid not null references auth.users(id) on delete restrict,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  consumed_at timestamptz,
  consumed_operation_id uuid,
  response jsonb,
  created_at timestamptz not null default now(),
  check (action = 'rate_host_team'),
  check (expires_at > created_at)
);

create index if not exists pachanga_guest_rating_tokens_scope_idx
  on public.pachanga_guest_rating_tokens(group_id, match_id, guest_identity_id, expires_at desc);

create table if not exists public.pachanga_team_external_rating_snapshots (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  base_level numeric not null,
  calibrated_level numeric not null,
  prior_weight numeric not null default 5,
  evidence_count integer not null,
  evidence_weight numeric not null,
  evidence_ids uuid[] not null default '{}',
  engine_version text not null,
  calculated_at timestamptz not null default now(),
  check (base_level between 0 and 100),
  check (calibrated_level between 0 and 100),
  check (prior_weight = 5),
  check (evidence_count >= 0),
  check (evidence_weight >= 0)
);

alter table public.pachanga_rating_config_events enable row level security;
alter table public.pachanga_guest_rating_tokens enable row level security;
alter table public.pachanga_team_external_rating_snapshots enable row level security;

revoke all on table public.pachanga_rating_config_events from public, anon, authenticated;
revoke all on table public.pachanga_guest_rating_tokens from public, anon, authenticated;
revoke all on table public.pachanga_team_external_rating_snapshots from public, anon, authenticated;
grant all on table public.pachanga_rating_config_events to service_role;
grant all on table public.pachanga_guest_rating_tokens to service_role;
grant all on table public.pachanga_team_external_rating_snapshots to service_role;

drop policy if exists "Members can read V2 individual ratings" on public.pachanga_individual_rating_evidence;
drop policy if exists "Evaluators can read only their own V2 ratings" on public.pachanga_individual_rating_evidence;
create policy "Evaluators can read only their own V2 ratings"
on public.pachanga_individual_rating_evidence for select to authenticated
using (
  evaluator_profile_id in (
    select profile.id from public.pachanga_player_profiles profile
    where profile.user_id = (select auth.uid())
  )
);

drop policy if exists "Members can read V2 rating state history" on public.pachanga_rating_evidence_state_events;
drop policy if exists "Evaluators can read only their own V2 rating history" on public.pachanga_rating_evidence_state_events;
create policy "Evaluators can read only their own V2 rating history"
on public.pachanga_rating_evidence_state_events for select to authenticated
using (
  evidence_id in (
    select evidence.id
    from public.pachanga_individual_rating_evidence evidence
    join public.pachanga_player_profiles profile on profile.id = evidence.evaluator_profile_id
    where profile.user_id = (select auth.uid())
  )
);

drop policy if exists "Members can read V2 player snapshots" on public.pachanga_player_rating_snapshots;
drop policy if exists "Players can read only their own V2 snapshots" on public.pachanga_player_rating_snapshots;
create policy "Players can read only their own V2 snapshots"
on public.pachanga_player_rating_snapshots for select to authenticated
using (
  player_profile_id in (
    select profile.id from public.pachanga_player_profiles profile
    where profile.user_id = (select auth.uid())
  )
);

drop policy if exists "Members can read guest identities" on public.pachanga_guest_identities;
drop policy if exists "Admins or linked users can read guest identities" on public.pachanga_guest_identities;
create policy "Admins or linked users can read guest identities"
on public.pachanga_guest_identities for select to authenticated
using (
  linked_user_id = (select auth.uid())
  or public.is_pachanga_group_admin(created_by_group_id)
);

drop policy if exists "Members can read guest link history" on public.pachanga_guest_link_events;
drop policy if exists "Linked users or admins can read guest link history" on public.pachanga_guest_link_events;
create policy "Linked users or admins can read guest link history"
on public.pachanga_guest_link_events for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.pachanga_guest_identities guest
    where guest.id = pachanga_guest_link_events.guest_identity_id
      and public.is_pachanga_group_admin(guest.created_by_group_id)
  )
);

drop policy if exists "Members can read external teams" on public.pachanga_external_teams;
drop policy if exists "Admins can read external teams" on public.pachanga_external_teams;
create policy "Admins can read external teams"
on public.pachanga_external_teams for select to authenticated
using (
  public.is_pachanga_group_admin(created_by_group_id)
  or (linked_group_id is not null and public.is_pachanga_group_admin(linked_group_id))
);

drop policy if exists "Members can read global rating responses" on public.pachanga_global_rating_responses;
drop policy if exists "Actors can read only their own global responses" on public.pachanga_global_rating_responses;
create policy "Actors can read only their own global responses"
on public.pachanga_global_rating_responses for select to authenticated
using (actor_user_id = (select auth.uid()));

drop policy if exists "Admins can read rating flags" on public.pachanga_rating_flags;
revoke select on table public.pachanga_rating_flags from authenticated;
grant select on table public.pachanga_rating_flags to service_role;

create or replace function public.pachanga_rating_v2_ratings_enabled(target_group_id uuid)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(groups.ratings_enabled, true)
  from public.pachanga_groups groups
  where groups.id = target_group_id;
$$;

create or replace function public.set_pachanga_group_ratings_enabled_v2(
  target_group_id uuid,
  next_enabled boolean,
  operation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  previous_enabled boolean;
  saved_enabled boolean;
begin
  if current_user_id is null or operation_id is null then raise exception 'Authentication and operation id required'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then raise exception 'Only group admins can change rating settings'; end if;

  select groups.ratings_enabled into previous_enabled
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;

  if exists (
    select 1 from public.pachanga_rating_config_events event
    where event.group_id = target_group_id
      and event.operation_id = set_pachanga_group_ratings_enabled_v2.operation_id
  ) then
    return jsonb_build_object('ratingsEnabled', previous_enabled, 'operationId', operation_id);
  end if;

  update public.pachanga_groups
  set ratings_enabled = coalesce(next_enabled, true), updated_at = now()
  where id = target_group_id
  returning ratings_enabled into saved_enabled;

  insert into public.pachanga_rating_config_events(
    group_id, actor_user_id, operation_id, previous_enabled, next_enabled
  ) values (
    target_group_id, current_user_id, operation_id, previous_enabled, saved_enabled
  );

  perform public.record_pachanga_group_event(
    target_group_id,
    null,
    'rating_settings_changed_v2',
    jsonb_build_object('previousEnabled', previous_enabled, 'ratingsEnabled', saved_enabled),
    operation_id,
    false
  );
  return jsonb_build_object('ratingsEnabled', saved_enabled, 'operationId', operation_id);
end;
$$;

revoke all on function public.pachanga_rating_v2_ratings_enabled(uuid) from public, anon, authenticated;
revoke all on function public.set_pachanga_group_ratings_enabled_v2(uuid, boolean, uuid) from public, anon;
grant execute on function public.set_pachanga_group_ratings_enabled_v2(uuid, boolean, uuid) to authenticated;

create or replace function public.pachanga_player_profile_patch(target_profile_id uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  profile public.pachanga_player_profiles%rowtype;
  visible_facets jsonb;
  visible_overall numeric;
  social_ready boolean;
  rating_v2 jsonb;
begin
  select * into profile
  from public.pachanga_player_profiles
  where id = target_profile_id;
  if not found then return '{}'::jsonb; end if;

  social_ready := profile.rating_evaluator_count >= 3;
  visible_facets := case when social_ready then profile.current_facets else jsonb_build_object(
    'pace', public.pachanga_rating_v2_clamp(coalesce(nullif(profile.base_facets ->> 'pace', '')::numeric, 50) + coalesce(nullif(profile.current_facet_modifiers ->> 'pace', '')::numeric, 0)),
    'shooting', public.pachanga_rating_v2_clamp(coalesce(nullif(profile.base_facets ->> 'shooting', '')::numeric, 50) + coalesce(nullif(profile.current_facet_modifiers ->> 'shooting', '')::numeric, 0)),
    'passing', public.pachanga_rating_v2_clamp(coalesce(nullif(profile.base_facets ->> 'passing', '')::numeric, 50) + coalesce(nullif(profile.current_facet_modifiers ->> 'passing', '')::numeric, 0)),
    'dribbling', public.pachanga_rating_v2_clamp(coalesce(nullif(profile.base_facets ->> 'dribbling', '')::numeric, 50) + coalesce(nullif(profile.current_facet_modifiers ->> 'dribbling', '')::numeric, 0)),
    'defending', public.pachanga_rating_v2_clamp(coalesce(nullif(profile.base_facets ->> 'defending', '')::numeric, 50) + coalesce(nullif(profile.current_facet_modifiers ->> 'defending', '')::numeric, 0)),
    'physical', public.pachanga_rating_v2_clamp(coalesce(nullif(profile.base_facets ->> 'physical', '')::numeric, 50) + coalesce(nullif(profile.current_facet_modifiers ->> 'physical', '')::numeric, 0))
  ) end;
  visible_overall := case
    when social_ready then profile.current_overall
    else public.pachanga_rating_v2_overall(visible_facets, coalesce(profile.outfield_position, profile.position), profile.rating_domain)
  end;

  rating_v2 := jsonb_build_object(
    'domain', profile.rating_domain,
    'baseFacets', profile.base_facets,
    'currentFacets', visible_facets,
    'currentFacetModifiers', profile.current_facet_modifiers,
    'goalkeeperFacets', profile.goalkeeper_facets,
    'baseOverall', profile.base_overall,
    'currentOverall', visible_overall,
    'reliability', profile.rating_reliability,
    'evaluatorCount', profile.rating_evaluator_count,
    'requiredEvaluators', 3,
    'socialState', case when social_ready then 'ready' else 'calibrating' end,
    'engineVersion', profile.rating_engine_version,
    'recalculatedAt', profile.rating_recalculated_at
  ) || case when social_ready then jsonb_build_object(
    'calibratedFacets', profile.calibrated_facets,
    'calibratedOverall', profile.calibrated_overall
  ) else '{}'::jsonb end;

  return jsonb_strip_nulls(jsonb_build_object(
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
    'rating', case when visible_overall is null then profile.rating else visible_overall / 10 end,
    'ratings', '[]'::jsonb,
    'ratingVotes', '[]'::jsonb,
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
    'marketOpenToGuest', profile.market_open_to_guest,
    'ratingV2', rating_v2
  ));
end;
$$;

create or replace function public.patch_pachanga_player_profile_v2(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if coalesce(player_patch, '{}'::jsonb) ?| array[
    'rating', 'ratings', 'ratingVotes', 'ratingV2', 'assessmentSummary',
    'importedRating', 'importedRatingAt', 'importedRatingFromGroup',
    'baseFacets', 'calibratedFacets', 'currentFacets', 'currentFacetModifiers',
    'baseOverall', 'calibratedOverall', 'currentOverall', 'ratingReliability'
  ] then raise exception 'Rating fields are server managed'; end if;
  return public.patch_pachanga_player_profile(target_group_id, target_player_id, coalesce(player_patch, '{}'::jsonb));
end;
$$;

create or replace function public.upsert_pachanga_own_player_profile_v2(
  target_group_id uuid,
  target_player_id text,
  player_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if coalesce(player_patch, '{}'::jsonb) ?| array[
    'rating', 'ratings', 'ratingVotes', 'ratingV2', 'assessmentSummary',
    'importedRating', 'importedRatingAt', 'importedRatingFromGroup',
    'baseFacets', 'calibratedFacets', 'currentFacets', 'currentFacetModifiers',
    'baseOverall', 'calibratedOverall', 'currentOverall', 'ratingReliability'
  ] then raise exception 'Rating fields are server managed'; end if;
  return public.upsert_pachanga_own_player_profile(target_group_id, target_player_id, coalesce(player_patch, '{}'::jsonb));
end;
$$;

revoke all on function public.patch_pachanga_player_profile_v2(uuid, text, jsonb) from public, anon;
revoke all on function public.upsert_pachanga_own_player_profile_v2(uuid, text, jsonb) from public, anon;
grant execute on function public.patch_pachanga_player_profile_v2(uuid, text, jsonb) to authenticated;
grant execute on function public.upsert_pachanga_own_player_profile_v2(uuid, text, jsonb) to authenticated;
