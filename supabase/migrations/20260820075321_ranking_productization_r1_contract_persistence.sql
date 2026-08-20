-- Ranking Productization V1 / R1.
-- Frozen Season Score V3 contract and append-only persistence.

set lock_timeout = '5s';
set statement_timeout = '5min';

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to service_role;

create sequence if not exists private.pachanga_ranking_sequence;
revoke all on sequence private.pachanga_ranking_sequence from public, anon, authenticated;
grant usage, select on sequence private.pachanga_ranking_sequence to service_role;

create or replace function private.pachanga_ranking_json_checksum_v1(source jsonb)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(source::text, 'UTF8'), 'sha256'), 'hex');
$$;

revoke all on function private.pachanga_ranking_json_checksum_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_lock_ranking_operation_v1(target_operation_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if target_operation_id is null then raise exception 'Ranking operationId required'; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'ranking-operation:' || target_operation_id::text,
    0
  ));
end;
$$;

revoke all on function private.pachanga_lock_ranking_operation_v1(uuid)
  from public, anon, authenticated;

create table if not exists private.pachanga_ranking_settings (
  singleton boolean primary key default true check (singleton),
  season_score_product_enabled boolean not null default false,
  provincial_rankings_product_enabled boolean not null default false,
  provincial_awards_enabled boolean not null default false,
  pilot_province_codes text[] not null default array['08']::text[],
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  updated_by uuid references auth.users(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1),
  check (not provincial_awards_enabled),
  check (cardinality(pilot_province_codes) between 1 and 52)
);

insert into private.pachanga_ranking_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists private.pachanga_season_score_formula_registry (
  formula_key text not null,
  formula_version integer not null,
  configuration jsonb not null,
  configuration_checksum text generated always as (
    private.pachanga_ranking_json_checksum_v1(configuration)
  ) stored,
  active_from timestamptz not null,
  active_until timestamptz,
  created_by uuid references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  primary key (formula_key, formula_version),
  check (formula_key ~ '^[a-z0-9_]{3,80}$'),
  check (formula_version >= 1),
  check (jsonb_typeof(configuration) = 'object'),
  check (active_until is null or active_until > active_from)
);

create unique index if not exists pachanga_season_score_formula_active_idx
  on private.pachanga_season_score_formula_registry(formula_key)
  where active_until is null;

create or replace function private.pachanga_protect_season_score_formula_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Season Score formula versions are immutable';
  end if;
  if new.formula_key is distinct from old.formula_key
    or new.formula_version is distinct from old.formula_version
    or new.configuration is distinct from old.configuration
    or new.active_from is distinct from old.active_from
    or old.active_until is not null
    or (new.active_until is not null and new.active_until <= old.active_from) then
    raise exception 'Active Season Score formula configuration cannot be edited';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_protect_season_score_formula_v1()
  from public, anon, authenticated;

drop trigger if exists protect_pachanga_season_score_formula_v1
  on private.pachanga_season_score_formula_registry;
create trigger protect_pachanga_season_score_formula_v1
before update or delete on private.pachanga_season_score_formula_registry
for each row execute function private.pachanga_protect_season_score_formula_v1();

insert into private.pachanga_season_score_formula_registry(
  formula_key, formula_version, configuration, active_from
)
values (
  'season_score_v3',
  1,
  jsonb_build_object(
    'weights', jsonb_build_object('quality', 55, 'competition', 30, 'opposition', 15),
    'volumeModel', 'recent_30',
    'ratingConfidenceModel', 'full',
    'integrityMode', 'weighted',
    'integrityStrategy', 'exclusion_and_hold',
    'confidencePolicy', 'graduated',
    'opponentDecay', jsonb_build_array(1, 1, 0.5, 0.25, 0),
    'rankingEligibility', jsonb_build_object(
      'minimumValidChallenges', 15,
      'minimumLogicalOpponents', 6,
      'minimumRatingReliability', 0.45,
      'recentActivityWeeks', 12
    ),
    'provincialTrophyReadiness', jsonb_build_object(
      'minimumValidChallenges', 25,
      'minimumLogicalOpponents', 10,
      'minimumMatchCompetitiveConfidence', 0.72,
      'minimumNetworkDiversity', 0.68,
      'minimumRatingReliability', 0.55,
      'recentActivityWeeks', 12
    ),
    'matchConfidence', jsonb_build_object(
      'acceptedChallenge', 0.15,
      'agreedTime', 0.05,
      'agreedVenue', 0.10,
      'participants', 0.35,
      'bilateralResult', 0.17,
      'establishedTeams', 0.08,
      'history', 0.04,
      'opponentIndependence', 0.06,
      'dayAnomalyPenalty', 0.28
    ),
    'opponentIndependence', jsonb_build_object(
      'minimumEvidenceValue', 0.50,
      'rosterOverlapWeight', 0.55,
      'sharedAdminWeight', 0.18,
      'sameOwnerWeight', 0.08,
      'sameSportsClusterWithSharedAdminWeight', 0.04,
      'bothNewWeight', 0.08,
      'closedPairWeight', 0.11,
      'logicalClusterFactor', true
    ),
    'scorePenalty', false,
    'awardsEnabled', false
  ),
  clock_timestamp()
)
on conflict (formula_key, formula_version) do nothing;

create table if not exists private.pachanga_ranking_territories (
  province_code text primary key,
  province_name text not null,
  country_code text not null default 'ES',
  scope text not null default 'province',
  product_allowed boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (province_code ~ '^[0-9]{2}$'),
  check (char_length(province_name) between 2 and 80),
  check (country_code = 'ES'),
  check (scope = 'province'),
  check (revision >= 1)
);

insert into private.pachanga_ranking_territories(
  province_code, province_name, product_allowed
)
values ('08', 'Barcelona', true)
on conflict (province_code) do nothing;

insert into private.pachanga_ranking_territories(
  province_code, province_name, product_allowed
)
values ('00', 'Sin territorio verificado', false)
on conflict (province_code) do nothing;

create table if not exists private.pachanga_ranking_venue_territories (
  id uuid primary key default gen_random_uuid(),
  place_id text not null,
  province_code text not null references private.pachanga_ranking_territories(province_code) on delete restrict,
  confidence numeric not null,
  evidence_source text not null,
  evidence jsonb not null default '{}'::jsonb,
  effective_from timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  revision bigint not null default 1,
  operation_id uuid not null unique,
  actor_user_id uuid references auth.users(id) on delete restrict,
  reason text not null,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (char_length(place_id) between 3 and 300),
  check (confidence between 0 and 1),
  check (evidence_source in ('google_places_admin_verified', 'platform_admin_verified', 'canonical_import')),
  check (jsonb_typeof(evidence) = 'object'),
  check (effective_until is null or effective_until > effective_from),
  check (revision >= 1),
  check (char_length(reason) between 3 and 1200)
);

create unique index if not exists pachanga_ranking_venue_current_idx
  on private.pachanga_ranking_venue_territories(place_id)
  where effective_until is null;
create index if not exists pachanga_ranking_venue_province_idx
  on private.pachanga_ranking_venue_territories(province_code, effective_from, id);

create table if not exists private.pachanga_ranking_seasons (
  id uuid primary key default gen_random_uuid(),
  season_key text not null unique,
  label text not null,
  scope text not null default 'province',
  status text not null default 'draft',
  formula_key text not null,
  formula_version integer not null,
  formula_checksum text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  revision bigint not null default 1,
  ranking_revision bigint not null default 0,
  published_revision bigint not null default 0,
  last_refresh_at timestamptz,
  last_error_code text,
  created_by uuid references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete restrict,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  foreign key (formula_key, formula_version)
    references private.pachanga_season_score_formula_registry(formula_key, formula_version) on delete restrict,
  check (season_key ~ '^[a-z0-9_-]{3,80}$'),
  check (char_length(label) between 3 and 120),
  check (scope = 'province'),
  check (status in ('draft', 'open', 'frozen', 'closed', 'archived')),
  check (ends_at > starts_at),
  check (revision >= 1 and ranking_revision >= 0 and published_revision >= 0),
  check (published_revision <= ranking_revision),
  check (last_error_code is null or char_length(last_error_code) <= 120)
);

create unique index if not exists pachanga_ranking_single_live_season_idx
  on private.pachanga_ranking_seasons(scope, formula_key, formula_version)
  where status in ('open', 'frozen');
create index if not exists pachanga_ranking_seasons_status_idx
  on private.pachanga_ranking_seasons(status, starts_at, ends_at, id);

create table if not exists private.pachanga_ranking_season_territories (
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  province_code text not null references private.pachanga_ranking_territories(province_code) on delete restrict,
  product_enabled boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (season_id, province_code),
  check (revision >= 1)
);

create table if not exists private.pachanga_season_team_graph_snapshots (
  batch_id uuid not null,
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  graph_revision bigint not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  logical_opponent_id text not null,
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  admin_user_ids uuid[] not null default '{}',
  roster_profile_ids uuid[] not null default '{}',
  neighbor_group_ids uuid[] not null default '{}',
  logical_cluster_size integer not null default 1,
  input_checksum text not null,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  generated_at timestamptz not null default clock_timestamp(),
  primary key (batch_id, group_id),
  check (graph_revision >= 1),
  check (logical_cluster_size >= 1),
  check (input_checksum ~ '^[0-9a-f]{64}$')
);

create index if not exists pachanga_team_graph_season_revision_idx
  on private.pachanga_season_team_graph_snapshots(season_id, graph_revision desc, server_sequence desc, group_id);

create table if not exists private.pachanga_season_score_snapshots (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references private.pachanga_ranking_seasons(id) on delete restrict,
  province_code text not null references private.pachanga_ranking_territories(province_code) on delete restrict,
  player_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  snapshot_revision bigint not null,
  formula_key text not null,
  formula_version integer not null,
  formula_checksum text not null,
  evidence_revision text not null,
  rating_input_key text not null,
  rating_snapshot_id uuid references public.pachanga_player_rating_snapshots(id) on delete restrict,
  rating_overall numeric not null,
  rating_reliability numeric not null,
  graph_batch_id uuid not null,
  quality_component numeric not null,
  competition_component numeric not null,
  opposition_component numeric not null,
  raw_score numeric not null,
  visible_score integer not null,
  weighted_challenges numeric not null,
  valid_challenges integer not null,
  logical_opponents integer not null,
  match_competitive_confidence numeric not null,
  network_diversity numeric not null,
  eligibility_state text not null,
  reason_codes text[] not null default '{}',
  safe_reason_codes text[] not null default '{}',
  integrity_classification text not null,
  integrity_risk numeric not null,
  integrity_details jsonb not null default '{}'::jsonb,
  trophy_readiness boolean not null default false,
  trophy_reason_codes text[] not null default '{}',
  evidence_input jsonb not null,
  lineage jsonb not null,
  snapshot_checksum text not null,
  operation_id uuid not null,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  generated_at timestamptz not null default clock_timestamp(),
  unique (season_id, player_profile_id, snapshot_revision),
  foreign key (formula_key, formula_version)
    references private.pachanga_season_score_formula_registry(formula_key, formula_version) on delete restrict,
  check (snapshot_revision >= 1),
  check (formula_version >= 1),
  check (rating_overall between 0 and 100),
  check (rating_reliability between 0 and 1),
  check (quality_component between 0 and 550),
  check (competition_component between 0 and 300),
  check (opposition_component between 0 and 150),
  check (raw_score between 0 and 1000),
  check (visible_score between 0 and 1000),
  check (weighted_challenges >= 0 and valid_challenges >= 0 and logical_opponents >= 0),
  check (match_competitive_confidence between 0 and 1),
  check (network_diversity between 0 and 1),
  check (eligibility_state in ('eligible', 'provisional', 'pending_integrity_review', 'not_eligible')),
  check (integrity_classification in ('clean', 'watch', 'suspicious', 'high_risk')),
  check (integrity_risk between 0 and 100),
  check (jsonb_typeof(integrity_details) = 'object'),
  check (jsonb_typeof(evidence_input) = 'object'),
  check (jsonb_typeof(lineage) = 'object')
);

create or replace function private.pachanga_set_season_score_snapshot_checksum_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  new.snapshot_checksum := private.pachanga_ranking_json_checksum_v1(
    jsonb_build_object(
      'seasonId', new.season_id,
      'provinceCode', new.province_code,
      'playerProfileId', new.player_profile_id,
      'snapshotRevision', new.snapshot_revision,
      'formulaKey', new.formula_key,
      'formulaVersion', new.formula_version,
      'formulaChecksum', new.formula_checksum,
      'evidenceRevision', new.evidence_revision,
      'ratingInputKey', new.rating_input_key,
      'ratingOverall', new.rating_overall,
      'ratingReliability', new.rating_reliability,
      'components', jsonb_build_array(
        new.quality_component, new.competition_component, new.opposition_component
      ),
      'rawScore', new.raw_score,
      'visibleScore', new.visible_score,
      'weightedChallenges', new.weighted_challenges,
      'validChallenges', new.valid_challenges,
      'logicalOpponents', new.logical_opponents,
      'matchCompetitiveConfidence', new.match_competitive_confidence,
      'networkDiversity', new.network_diversity,
      'eligibilityState', new.eligibility_state,
      'reasonCodes', to_jsonb(new.reason_codes),
      'safeReasonCodes', to_jsonb(new.safe_reason_codes),
      'integrityClassification', new.integrity_classification,
      'integrityRisk', new.integrity_risk,
      'trophyReadiness', new.trophy_readiness,
      'trophyReasonCodes', to_jsonb(new.trophy_reason_codes),
      'evidenceInput', new.evidence_input,
      'lineage', new.lineage
    )
  );
  return new;
end;
$$;

revoke all on function private.pachanga_set_season_score_snapshot_checksum_v1()
  from public, anon, authenticated;

drop trigger if exists set_pachanga_season_score_snapshot_checksum_v1
  on private.pachanga_season_score_snapshots;
create trigger set_pachanga_season_score_snapshot_checksum_v1
before insert on private.pachanga_season_score_snapshots
for each row execute function private.pachanga_set_season_score_snapshot_checksum_v1();

create unique index if not exists pachanga_season_score_snapshot_sequence_idx
  on private.pachanga_season_score_snapshots(server_sequence);
create index if not exists pachanga_season_score_snapshot_latest_idx
  on private.pachanga_season_score_snapshots(
    season_id, province_code, player_profile_id, snapshot_revision desc, server_sequence desc, id desc
  );

create table if not exists private.pachanga_ranking_operation_receipts (
  operation_id uuid primary key,
  action text not null,
  target_type text not null,
  target_id text not null,
  actor_user_id uuid references auth.users(id) on delete restrict,
  expected_revision bigint,
  result_revision bigint,
  response jsonb not null,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (char_length(action) between 3 and 120),
  check (char_length(target_type) between 2 and 80),
  check (char_length(target_id) between 1 and 240),
  check (jsonb_typeof(response) = 'object')
);

create table if not exists private.pachanga_ranking_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null,
  event_type text not null,
  season_id uuid references private.pachanga_ranking_seasons(id) on delete restrict,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  province_code text references private.pachanga_ranking_territories(province_code) on delete restrict,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('private.pachanga_ranking_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, event_type, player_profile_id),
  check (char_length(event_type) between 3 and 120),
  check (jsonb_typeof(payload) = 'object')
);

create unique index if not exists pachanga_ranking_events_sequence_idx
  on private.pachanga_ranking_events(server_sequence);
create index if not exists pachanga_ranking_events_season_idx
  on private.pachanga_ranking_events(season_id, server_sequence desc, id desc);

create or replace function private.pachanga_protect_ranking_append_only_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Ranking evidence and snapshots are append-only';
end;
$$;

revoke all on function private.pachanga_protect_ranking_append_only_v1()
  from public, anon, authenticated;

drop trigger if exists protect_pachanga_team_graph_append_only_v1
  on private.pachanga_season_team_graph_snapshots;
create trigger protect_pachanga_team_graph_append_only_v1
before update or delete on private.pachanga_season_team_graph_snapshots
for each row execute function private.pachanga_protect_ranking_append_only_v1();

drop trigger if exists protect_pachanga_score_snapshot_append_only_v1
  on private.pachanga_season_score_snapshots;
create trigger protect_pachanga_score_snapshot_append_only_v1
before update or delete on private.pachanga_season_score_snapshots
for each row execute function private.pachanga_protect_ranking_append_only_v1();

revoke all on table private.pachanga_ranking_settings from public, anon, authenticated;
revoke all on table private.pachanga_season_score_formula_registry from public, anon, authenticated;
revoke all on table private.pachanga_ranking_territories from public, anon, authenticated;
revoke all on table private.pachanga_ranking_venue_territories from public, anon, authenticated;
revoke all on table private.pachanga_ranking_seasons from public, anon, authenticated;
revoke all on table private.pachanga_ranking_season_territories from public, anon, authenticated;
revoke all on table private.pachanga_season_team_graph_snapshots from public, anon, authenticated;
revoke all on table private.pachanga_season_score_snapshots from public, anon, authenticated;
revoke all on table private.pachanga_ranking_operation_receipts from public, anon, authenticated;
revoke all on table private.pachanga_ranking_events from public, anon, authenticated;

grant all on table private.pachanga_ranking_settings to service_role;
grant all on table private.pachanga_season_score_formula_registry to service_role;
grant all on table private.pachanga_ranking_territories to service_role;
grant all on table private.pachanga_ranking_venue_territories to service_role;
grant all on table private.pachanga_ranking_seasons to service_role;
grant all on table private.pachanga_ranking_season_territories to service_role;
grant all on table private.pachanga_season_team_graph_snapshots to service_role;
grant all on table private.pachanga_season_score_snapshots to service_role;
grant all on table private.pachanga_ranking_operation_receipts to service_role;
grant all on table private.pachanga_ranking_events to service_role;

comment on table private.pachanga_season_score_formula_registry is
  'Immutable Season Score V3 formula registry. Changes require a new formula version.';
comment on table private.pachanga_season_score_snapshots is
  'Append-only authoritative Season Score snapshots. Rating V2 is read-only input.';
comment on column private.pachanga_ranking_venue_territories.province_code is
  'Competitive venue territory, never nationality, domicile, IP or personal GPS.';

reset lock_timeout;
reset statement_timeout;
