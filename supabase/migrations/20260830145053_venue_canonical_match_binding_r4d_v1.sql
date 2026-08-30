-- Pachangas IQ Wave 9A: non-destructive reservation binding to CanonicalMatch.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_venue_deterministic_uuid_v1(seed text)
returns uuid
language sql
immutable
set search_path = pg_catalog
as $$
  select (
    substr(md5(seed), 1, 8) || '-' || substr(md5(seed), 9, 4) || '-4' ||
    substr(md5(seed), 14, 3) || '-8' || substr(md5(seed), 18, 3) || '-' ||
    substr(md5(seed), 21, 12)
  )::uuid;
$$;

revoke all on function private.pachanga_venue_deterministic_uuid_v1(text)
  from public, anon, authenticated;

create table if not exists public.pachanga_venue_match_bindings (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.pachanga_venue_reservations(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid references public.pachanga_competition_match_contexts(id) on delete restrict,
  schedule_item_id uuid references public.pachanga_competition_schedule_items(id) on delete restrict,
  rule_revision_id uuid references public.pachanga_competition_rule_revisions(id) on delete restrict,
  venue_id uuid not null references public.pachanga_club_venues(id) on delete restrict,
  pitch_id uuid not null references public.pachanga_venue_pitches(id) on delete restrict,
  previous_binding_id uuid references public.pachanga_venue_match_bindings(id) on delete restrict,
  fixture_change_id uuid references public.pachanga_competition_fixture_changes(id) on delete restrict,
  fixture_change_revision_id uuid references public.pachanga_competition_fixture_change_revisions(id) on delete restrict,
  status text not null default 'ACTIVE',
  action_required_code text,
  binding_revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_venue_sequence'),
  operation_id uuid not null,
  bound_by uuid references auth.users(id) on delete set null,
  bound_at timestamptz not null default clock_timestamp(),
  superseded_at timestamptz,
  consumed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('ACTIVE', 'ACTION_REQUIRED', 'HISTORICAL', 'UNBOUND', 'CONSUMED')),
  check (action_required_code is null or action_required_code in (
    'VENUE_ACTION_REQUIRED', 'REFEREE_RECONFIRMATION_REQUIRED'
  )),
  check (binding_revision >= 1),
  check ((status = 'HISTORICAL' and superseded_at is not null) or status <> 'HISTORICAL'),
  check ((status = 'CONSUMED' and consumed_at is not null) or status <> 'CONSUMED')
);

create unique index if not exists pachanga_venue_match_binding_current_match_idx
  on public.pachanga_venue_match_bindings(canonical_match_id)
  where status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED');
create unique index if not exists pachanga_venue_match_binding_current_reservation_idx
  on public.pachanga_venue_match_bindings(reservation_id)
  where status in ('ACTIVE', 'ACTION_REQUIRED', 'CONSUMED');
create index if not exists pachanga_venue_match_binding_context_idx
  on public.pachanga_venue_match_bindings(
    competition_match_context_id, status, server_sequence desc, id
  ) where competition_match_context_id is not null;
create index if not exists pachanga_venue_match_binding_venue_idx
  on public.pachanga_venue_match_bindings(
    venue_id, pitch_id, status, server_sequence desc, id
  );

create table if not exists private.pachanga_venue_match_binding_revisions (
  id uuid primary key default gen_random_uuid(),
  binding_id uuid not null references public.pachanga_venue_match_bindings(id) on delete restrict,
  binding_revision bigint not null check (binding_revision >= 1),
  action text not null,
  status text not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot) = 'object'),
  operation_id uuid not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique,
  effective_at timestamptz not null default clock_timestamp(),
  unique (binding_id, binding_revision),
  unique (operation_id, binding_id)
);

comment on table public.pachanga_venue_match_bindings is
  'Venue reservation projection over the existing CanonicalMatch. It never owns sporting identity, score or discipline.';
comment on column public.pachanga_venue_match_bindings.action_required_code is
  'A cancelled reservation marks Venue action required; it never cancels or forfeits the match.';

reset statement_timeout;
reset lock_timeout;
