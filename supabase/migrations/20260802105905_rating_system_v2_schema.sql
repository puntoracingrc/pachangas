-- Pachangas IQ rating system V2: additive normalized schema.
-- This migration does not delete or reinterpret legacy rating data.

alter table public.pachanga_player_profiles
  add column if not exists rating_domain text not null default 'field',
  add column if not exists base_facets jsonb not null default '{}'::jsonb,
  add column if not exists calibrated_facets jsonb not null default '{}'::jsonb,
  add column if not exists current_facets jsonb not null default '{}'::jsonb,
  add column if not exists current_facet_modifiers jsonb not null default '{}'::jsonb,
  add column if not exists goalkeeper_facets jsonb not null default '{}'::jsonb,
  add column if not exists base_overall numeric,
  add column if not exists calibrated_overall numeric,
  add column if not exists current_overall numeric,
  add column if not exists rating_reliability numeric not null default 0,
  add column if not exists rating_evaluator_count integer not null default 0,
  add column if not exists rating_engine_version text,
  add column if not exists rating_recalculated_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pachanga_player_profiles_rating_domain_check'
  ) then
    alter table public.pachanga_player_profiles
      add constraint pachanga_player_profiles_rating_domain_check
      check (rating_domain in ('field', 'goalkeeper', 'goalkeeper_legacy'));
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'pachanga_player_profiles_rating_layers_check'
  ) then
    alter table public.pachanga_player_profiles
      add constraint pachanga_player_profiles_rating_layers_check
      check (
        (base_overall is null or base_overall between 0 and 100)
        and (calibrated_overall is null or calibrated_overall between 0 and 100)
        and (current_overall is null or current_overall between 0 and 100)
        and rating_reliability between 0 and 100
        and rating_evaluator_count >= 0
      );
  end if;
end;
$$;

create table if not exists public.pachanga_individual_rating_evidence (
  id uuid primary key default gen_random_uuid(),
  evaluator_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  target_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  operation_id uuid not null,
  state text not null default 'active',
  previous_evidence_id uuid references public.pachanga_individual_rating_evidence(id) on delete restrict,
  engine_version text not null,
  evaluator_reference_facets jsonb not null,
  comparisons jsonb not null,
  applied_deltas jsonb not null,
  observations jsonb not null,
  evaluator_confidence_snapshot numeric not null,
  shared_matches_used integer not null default 0,
  shared_matches_since timestamptz,
  source text not null default 'member_comparison',
  legacy_payload jsonb,
  created_at timestamptz not null default now(),
  superseded_at timestamptz,
  voided_at timestamptz,
  voided_by uuid references auth.users(id) on delete set null,
  void_reason text,
  check (evaluator_profile_id <> target_profile_id),
  check (state in ('active', 'superseded', 'void')),
  check (evaluator_confidence_snapshot between 0 and 100),
  check (shared_matches_used >= 0)
);

create unique index if not exists pachanga_individual_rating_active_pair_idx
  on public.pachanga_individual_rating_evidence(evaluator_profile_id, target_profile_id)
  where state = 'active';

create unique index if not exists pachanga_individual_rating_operation_idx
  on public.pachanga_individual_rating_evidence(evaluator_profile_id, operation_id);

create index if not exists pachanga_individual_rating_target_state_idx
  on public.pachanga_individual_rating_evidence(target_profile_id, state, created_at desc, id desc);

create index if not exists pachanga_individual_rating_group_created_idx
  on public.pachanga_individual_rating_evidence(group_id, created_at desc, id desc);

create table if not exists public.pachanga_rating_evidence_state_events (
  id uuid primary key default gen_random_uuid(),
  evidence_id uuid not null references public.pachanga_individual_rating_evidence(id) on delete restrict,
  from_state text,
  to_state text not null,
  actor_id uuid references auth.users(id) on delete set null,
  reason text,
  created_at timestamptz not null default now(),
  check (from_state is null or from_state in ('active', 'superseded', 'void')),
  check (to_state in ('active', 'superseded', 'void'))
);

create index if not exists pachanga_rating_state_events_evidence_idx
  on public.pachanga_rating_evidence_state_events(evidence_id, created_at, id);

create table if not exists public.pachanga_player_rating_snapshots (
  id uuid primary key default gen_random_uuid(),
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  trigger_evidence_id uuid references public.pachanga_individual_rating_evidence(id) on delete set null,
  group_id uuid references public.pachanga_groups(id) on delete set null,
  match_id text,
  snapshot_kind text not null,
  base_facets jsonb not null,
  calibrated_facets jsonb not null,
  current_facets jsonb not null,
  current_facet_modifiers jsonb not null default '{}'::jsonb,
  base_overall numeric,
  calibrated_overall numeric,
  current_overall numeric,
  reliability numeric not null,
  evaluator_count integer not null,
  active_evidence_ids uuid[] not null default '{}',
  engine_version text not null,
  created_at timestamptz not null default now(),
  check (snapshot_kind in ('assessment', 'recalculation', 'match_finalization', 'migration')),
  check (reliability between 0 and 100),
  check (evaluator_count >= 0)
);

create index if not exists pachanga_player_rating_snapshots_profile_created_idx
  on public.pachanga_player_rating_snapshots(player_profile_id, created_at desc, id desc);

create table if not exists public.pachanga_match_rating_snapshots (
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  match_id text not null,
  group_level numeric,
  lineup_a_level numeric,
  lineup_b_level numeric,
  engine_version text not null,
  snapshot jsonb not null default '{}'::jsonb,
  state text not null default 'active',
  voided_at timestamptz,
  void_reason text,
  finalized_at timestamptz not null default now(),
  primary key (group_id, match_id),
  check (group_level is null or group_level between 0 and 100),
  check (lineup_a_level is null or lineup_a_level between 0 and 100),
  check (lineup_b_level is null or lineup_b_level between 0 and 100),
  check (state in ('active', 'void'))
);

create table if not exists public.pachanga_match_rating_participants (
  group_id uuid not null,
  match_id text not null,
  local_player_id text not null,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  guest_identity_id uuid,
  team_side text not null,
  attendance_confirmed boolean not null default true,
  was_reserve boolean not null default false,
  card_snapshot jsonb not null,
  created_at timestamptz not null default now(),
  primary key (group_id, match_id, local_player_id),
  foreign key (group_id, match_id)
    references public.pachanga_match_rating_snapshots(group_id, match_id) on delete restrict,
  check (team_side in ('A', 'B', 'external'))
);

create index if not exists pachanga_match_rating_participants_profile_idx
  on public.pachanga_match_rating_participants(player_profile_id, created_at desc)
  where player_profile_id is not null;

create table if not exists public.pachanga_guest_identities (
  id uuid primary key default gen_random_uuid(),
  created_by_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  source_player_id text,
  display_name text not null,
  normalized_name text not null,
  contact_hint text,
  claim_token_hash text,
  linked_user_id uuid references auth.users(id) on delete set null,
  link_state text not null default 'unlinked',
  provisional_level numeric,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (link_state in ('unlinked', 'pending', 'linked', 'reversed')),
  check (provisional_level is null or provisional_level between 0 and 100)
);

create index if not exists pachanga_guest_identity_name_idx
  on public.pachanga_guest_identities(normalized_name);

create unique index if not exists pachanga_guest_identity_source_player_idx
  on public.pachanga_guest_identities(created_by_group_id, source_player_id)
  where source_player_id is not null;

create index if not exists pachanga_guest_identity_linked_user_idx
  on public.pachanga_guest_identities(linked_user_id)
  where linked_user_id is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'pachanga_match_rating_participants_guest_fk'
  ) then
    alter table public.pachanga_match_rating_participants
      add constraint pachanga_match_rating_participants_guest_fk
      foreign key (guest_identity_id) references public.pachanga_guest_identities(id) on delete restrict;
  end if;
end;
$$;

create table if not exists public.pachanga_guest_link_events (
  id uuid primary key default gen_random_uuid(),
  guest_identity_id uuid not null references public.pachanga_guest_identities(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  action text not null,
  actor_id uuid references auth.users(id) on delete set null,
  reason text,
  previous_state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (action in ('link_requested', 'linked', 'reversed'))
);

create table if not exists public.pachanga_external_teams (
  id uuid primary key default gen_random_uuid(),
  created_by_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  display_name text not null,
  normalized_name text not null,
  zone text,
  linked_group_id uuid references public.pachanga_groups(id) on delete set null,
  link_state text not null default 'unlinked',
  calibrated_external_level numeric,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (link_state in ('unlinked', 'pending', 'linked', 'reversed')),
  check (calibrated_external_level is null or calibrated_external_level between 0 and 100)
);

create index if not exists pachanga_external_teams_duplicate_hint_idx
  on public.pachanga_external_teams(normalized_name, zone);

create table if not exists public.pachanga_global_rating_responses (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  match_id text not null,
  target_kind text not null,
  guest_identity_id uuid references public.pachanga_guest_identities(id) on delete restrict,
  external_team_id uuid references public.pachanga_external_teams(id) on delete restrict,
  target_group_id uuid references public.pachanga_groups(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete restrict,
  actor_guest_identity_id uuid references public.pachanga_guest_identities(id) on delete restrict,
  comparison text not null,
  delta numeric not null,
  reference_level_snapshot numeric not null,
  observation numeric not null,
  engine_version text not null,
  created_at timestamptz not null default now(),
  check (target_kind in ('guest', 'external_team', 'registered_group', 'host_team')),
  check (comparison in ('MUCHO_PEOR', 'PEOR', 'PARECIDO', 'MEJOR', 'MUCHO_MEJOR')),
  check (delta in (-10, -5, 0, 5, 10)),
  check (reference_level_snapshot between 0 and 100),
  check (observation between 0 and 100),
  check ((actor_user_id is not null)::integer + (actor_guest_identity_id is not null)::integer = 1)
);

create unique index if not exists pachanga_global_rating_admin_response_idx
  on public.pachanga_global_rating_responses(
    group_id,
    match_id,
    target_kind,
    coalesce(guest_identity_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(external_team_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(target_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(actor_user_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(actor_guest_identity_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table if not exists public.pachanga_global_rating_evidence (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  match_id text not null,
  target_kind text not null,
  guest_identity_id uuid references public.pachanga_guest_identities(id) on delete restrict,
  external_team_id uuid references public.pachanga_external_teams(id) on delete restrict,
  target_group_id uuid references public.pachanga_groups(id) on delete restrict,
  official_observation numeric not null,
  response_count integer not null,
  response_ids uuid[] not null,
  engine_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (target_kind in ('guest', 'external_team', 'registered_group', 'host_team')),
  check (official_observation between 0 and 100),
  check (response_count > 0)
);

create unique index if not exists pachanga_global_rating_official_idx
  on public.pachanga_global_rating_evidence(
    group_id,
    match_id,
    target_kind,
    coalesce(guest_identity_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(external_team_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(target_group_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table if not exists public.pachanga_rating_flags (
  id uuid primary key default gen_random_uuid(),
  flag_kind text not null,
  severity text not null default 'info',
  evaluator_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  target_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  group_id uuid references public.pachanga_groups(id) on delete restrict,
  evidence_ids uuid[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'open',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  check (severity in ('info', 'warning')),
  check (status in ('open', 'dismissed', 'confirmed'))
);

create table if not exists public.pachanga_legacy_rating_evidence (
  id uuid primary key default gen_random_uuid(),
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  source_kind text not null,
  classification text not null,
  original_payload jsonb not null,
  safe_facets jsonb,
  contributes_to_v2 boolean not null default false,
  migration_version text not null,
  created_at timestamptz not null default now(),
  check (classification in ('initial_assessment', 'advanced_assessment', 'external_vote', 'legacy', 'imported', 'unclassifiable'))
);

create unique index if not exists pachanga_legacy_rating_profile_source_idx
  on public.pachanga_legacy_rating_evidence(player_profile_id, source_kind, migration_version);

alter table public.pachanga_individual_rating_evidence enable row level security;
alter table public.pachanga_rating_evidence_state_events enable row level security;
alter table public.pachanga_player_rating_snapshots enable row level security;
alter table public.pachanga_match_rating_snapshots enable row level security;
alter table public.pachanga_match_rating_participants enable row level security;
alter table public.pachanga_guest_identities enable row level security;
alter table public.pachanga_guest_link_events enable row level security;
alter table public.pachanga_external_teams enable row level security;
alter table public.pachanga_global_rating_responses enable row level security;
alter table public.pachanga_global_rating_evidence enable row level security;
alter table public.pachanga_rating_flags enable row level security;
alter table public.pachanga_legacy_rating_evidence enable row level security;

revoke all on public.pachanga_individual_rating_evidence from anon, authenticated;
revoke all on public.pachanga_rating_evidence_state_events from anon, authenticated;
revoke all on public.pachanga_player_rating_snapshots from anon, authenticated;
revoke all on public.pachanga_match_rating_snapshots from anon, authenticated;
revoke all on public.pachanga_match_rating_participants from anon, authenticated;
revoke all on public.pachanga_guest_identities from anon, authenticated;
revoke all on public.pachanga_guest_link_events from anon, authenticated;
revoke all on public.pachanga_external_teams from anon, authenticated;
revoke all on public.pachanga_global_rating_responses from anon, authenticated;
revoke all on public.pachanga_global_rating_evidence from anon, authenticated;
revoke all on public.pachanga_rating_flags from anon, authenticated;
revoke all on public.pachanga_legacy_rating_evidence from anon, authenticated;

grant select on public.pachanga_individual_rating_evidence to authenticated;
grant select on public.pachanga_rating_evidence_state_events to authenticated;
grant select on public.pachanga_player_rating_snapshots to authenticated;
grant select on public.pachanga_match_rating_snapshots to authenticated;
grant select on public.pachanga_match_rating_participants to authenticated;
grant select on public.pachanga_guest_identities to authenticated;
grant select on public.pachanga_guest_link_events to authenticated;
grant select on public.pachanga_external_teams to authenticated;
grant select on public.pachanga_global_rating_responses to authenticated;
grant select on public.pachanga_global_rating_evidence to authenticated;
grant select on public.pachanga_rating_flags to authenticated;
grant select on public.pachanga_legacy_rating_evidence to authenticated;
