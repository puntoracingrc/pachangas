-- Pachangas IQ Competition Foundation R1: canonical identity for existing matches.
-- This registry never stores sporting state. Results, participants and ratings remain
-- owned by their existing normalized authorities.

create schema if not exists private;
create extension if not exists pgcrypto with schema extensions;

create sequence if not exists private.pachanga_competition_sequence;
revoke all on sequence private.pachanga_competition_sequence from public, anon, authenticated;
grant usage, select on sequence private.pachanga_competition_sequence to service_role;

create table if not exists public.pachanga_canonical_matches (
  id uuid primary key default gen_random_uuid(),
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('active', 'review_required', 'retired')),
  check (revision >= 1)
);

create table if not exists public.pachanga_canonical_match_bindings (
  id uuid primary key default gen_random_uuid(),
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  source_kind text not null,
  source_group_id uuid references public.pachanga_groups(id) on delete restrict,
  source_id text not null,
  relation_kind text not null,
  binding_status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid references auth.users(id) on delete set null,
  review_reason text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge')),
  check (relation_kind in ('authoritative_source', 'projection', 'provenance', 'manual_verified')),
  check (binding_status in ('active', 'review_required', 'retired')),
  check (revision >= 1),
  check (length(trim(source_id)) between 1 and 240),
  check (
    (source_kind in ('group_match', 'open_match') and source_group_id is not null)
    or (source_kind in ('external_match', 'team_challenge') and source_group_id is null)
  )
);

create table if not exists public.pachanga_canonical_match_binding_reviews (
  id uuid primary key default gen_random_uuid(),
  left_source_kind text not null,
  left_source_group_id uuid references public.pachanga_groups(id) on delete restrict,
  left_source_id text not null,
  right_source_kind text,
  right_source_group_id uuid references public.pachanga_groups(id) on delete restrict,
  right_source_id text,
  reason_code text not null,
  diagnostic jsonb not null default '{}'::jsonb,
  review_status text not null default 'pending',
  resolved_canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid references auth.users(id) on delete set null,
  resolved_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (left_source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge')),
  check (right_source_kind is null or right_source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge')),
  check (review_status in ('pending', 'resolved', 'dismissed')),
  check (revision >= 1),
  check (length(trim(left_source_id)) between 1 and 240),
  check ((right_source_kind is null) = (right_source_id is null)),
  check (
    (review_status = 'resolved' and resolved_canonical_match_id is not null and resolved_at is not null)
    or (review_status <> 'resolved')
  )
);

create unique index if not exists pachanga_canonical_match_active_source_idx
  on public.pachanga_canonical_match_bindings(
    source_kind,
    coalesce(source_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    source_id
  )
  where binding_status = 'active';

create unique index if not exists pachanga_canonical_match_binding_identity_idx
  on public.pachanga_canonical_match_bindings(
    canonical_match_id,
    source_kind,
    coalesce(source_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    source_id
  );

create index if not exists pachanga_canonical_match_binding_canonical_idx
  on public.pachanga_canonical_match_bindings(canonical_match_id, binding_status, server_sequence);

create index if not exists pachanga_canonical_match_review_status_idx
  on public.pachanga_canonical_match_binding_reviews(review_status, server_sequence, id);

create unique index if not exists pachanga_canonical_match_pending_review_idx
  on public.pachanga_canonical_match_binding_reviews(
    left_source_kind,
    coalesce(left_source_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    left_source_id,
    coalesce(right_source_kind, ''),
    coalesce(right_source_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(right_source_id, ''),
    reason_code
  )
  where review_status = 'pending';

create or replace function private.pachanga_competition_touch_updated_at_v1()
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

revoke all on function private.pachanga_competition_touch_updated_at_v1()
  from public, anon, authenticated;

drop trigger if exists touch_pachanga_canonical_matches_v1 on public.pachanga_canonical_matches;
create trigger touch_pachanga_canonical_matches_v1
before update on public.pachanga_canonical_matches
for each row execute function private.pachanga_competition_touch_updated_at_v1();

drop trigger if exists touch_pachanga_canonical_match_bindings_v1 on public.pachanga_canonical_match_bindings;
create trigger touch_pachanga_canonical_match_bindings_v1
before update on public.pachanga_canonical_match_bindings
for each row execute function private.pachanga_competition_touch_updated_at_v1();

drop trigger if exists touch_pachanga_canonical_match_reviews_v1 on public.pachanga_canonical_match_binding_reviews;
create trigger touch_pachanga_canonical_match_reviews_v1
before update on public.pachanga_canonical_match_binding_reviews
for each row execute function private.pachanga_competition_touch_updated_at_v1();

alter table public.pachanga_canonical_matches enable row level security;
alter table public.pachanga_canonical_match_bindings enable row level security;
alter table public.pachanga_canonical_match_binding_reviews enable row level security;

revoke all on table public.pachanga_canonical_matches from public, anon, authenticated;
revoke all on table public.pachanga_canonical_match_bindings from public, anon, authenticated;
revoke all on table public.pachanga_canonical_match_binding_reviews from public, anon, authenticated;

grant all on table public.pachanga_canonical_matches to service_role;
grant all on table public.pachanga_canonical_match_bindings to service_role;
grant all on table public.pachanga_canonical_match_binding_reviews to service_role;

comment on table public.pachanga_canonical_matches is
  'R1 identity-only registry. Sporting state remains in the bound source authorities.';
comment on table public.pachanga_canonical_match_bindings is
  'Polymorphic, unique active source binding to one real-world canonical match.';
comment on table public.pachanga_canonical_match_binding_reviews is
  'Ambiguous or orphan source evidence. A pending review is never an active binding.';
