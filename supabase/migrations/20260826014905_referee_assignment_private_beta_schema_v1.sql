-- Pachangas IQ Wave 4: extend the existing R3 assignment authority. The beta
-- gate is born OFF and no payment authority is introduced.

set lock_timeout = '5s';
set statement_timeout = '120s';

-- R5 broadened this status set, but production can retain the earlier named
-- check alongside the replacement because the legacy name was not canonical.
alter table public.pachanga_competition_match_sheets
  drop constraint if exists pachanga_competition_match_s_discipline_validation_status_check;

alter table private.pachanga_referee_foundation_settings
  add column if not exists referee_assignment_private_beta_enabled boolean not null default false;

alter table private.pachanga_referee_foundation_settings
  drop constraint if exists pachanga_referee_assignment_private_beta_gate_check,
  add constraint pachanga_referee_assignment_private_beta_gate_check check (
    not referee_assignments_enabled or referee_assignment_private_beta_enabled
  );

create or replace function private.pachanga_league_private_beta_guard_referee_assignments_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.referee_assignments_enabled
     and not new.referee_assignment_private_beta_enabled
     and exists (
       select 1
       from private.pachanga_competition_foundation_settings settings
       where settings.singleton and settings.league_private_beta_enabled
     ) then
    raise exception 'REFEREE_ASSIGNMENTS_NOT_AVAILABLE_IN_LEAGUE_BETA'
      using errcode = '0A000';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_private_beta_guard_referee_assignments_v1()
  from public, anon, authenticated;

alter table public.pachanga_referee_profiles
  add column if not exists public_fee_visibility boolean not null default false,
  add column if not exists public_fee_mode text,
  add column if not exists public_fee_from_cents integer,
  add column if not exists public_fee_currency text;

alter table public.pachanga_referee_profiles
  drop constraint if exists pachanga_referee_profiles_public_fee_check,
  add constraint pachanga_referee_profiles_public_fee_check check (
    (
      (public_fee_mode is null
        and public_fee_from_cents is null
        and public_fee_currency is null)
      or
      (public_fee_mode in ('FREE', 'FIXED', 'NEGOTIABLE', 'VOLUNTEER')
        and (public_fee_from_cents is null or public_fee_from_cents between 0 and 10000000)
        and public_fee_currency ~ '^[A-Z]{3}$'
        and (public_fee_mode <> 'FIXED' or public_fee_from_cents is not null)
        and (public_fee_mode not in ('FREE', 'VOLUNTEER') or public_fee_from_cents is null))
    )
    and (not public_fee_visibility or public_fee_mode is not null)
  );

create table if not exists private.pachanga_referee_public_fee_consents (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  actor_id uuid not null references auth.users(id) on delete restrict,
  content_fingerprint text not null,
  information_correct boolean not null default false,
  out_of_platform_payment_acknowledged boolean not null default false,
  subject_revision bigint not null check (subject_revision >= 1),
  server_sequence bigint not null unique default nextval('private.pachanga_referee_sequence'),
  consented_at timestamptz not null default clock_timestamp(),
  check (length(content_fingerprint) = 64),
  check (information_correct and out_of_platform_payment_acknowledged)
);

create index if not exists pachanga_referee_public_fee_consents_profile_idx
  on private.pachanga_referee_public_fee_consents(
    referee_profile_id, server_sequence desc, id desc
  );

alter table public.pachanga_referee_assignments
  add column if not exists canonical_binding_id uuid references public.pachanga_canonical_match_bindings(id) on delete restrict,
  add column if not exists competition_match_context_id uuid references public.pachanga_competition_match_contexts(id) on delete restrict,
  add column if not exists requester_competition_id uuid references public.pachanga_competitions(id) on delete restrict,
  add column if not exists modality text,
  add column if not exists venue_id uuid,
  add column if not exists venue_label text,
  add column if not exists venue_status text not null default 'TBD',
  add column if not exists effective_scheduled_start timestamptz,
  add column if not exists effective_scheduled_end timestamptz,
  add column if not exists effective_timezone text,
  add column if not exists effective_schedule_revision bigint,
  add column if not exists schedule_state text not null default 'CURRENT',
  add column if not exists schedule_changed_at timestamptz,
  add column if not exists reconfirmed_at timestamptz,
  add column if not exists expired_at timestamptz,
  add column if not exists replaced_at timestamptz;

update public.pachanga_referee_assignments assignments
set effective_scheduled_start = coalesce(assignments.effective_scheduled_start, assignments.scheduled_start),
    effective_scheduled_end = coalesce(assignments.effective_scheduled_end, assignments.scheduled_end),
    effective_timezone = coalesce(assignments.effective_timezone, assignments.timezone),
    effective_schedule_revision = coalesce(assignments.effective_schedule_revision, assignments.schedule_source_revision)
where assignments.effective_scheduled_start is null
   or assignments.effective_scheduled_end is null
   or assignments.effective_timezone is null
   or assignments.effective_schedule_revision is null;

alter table public.pachanga_referee_assignments
  alter column effective_scheduled_start set not null,
  alter column effective_scheduled_end set not null,
  alter column effective_timezone set not null,
  alter column effective_schedule_revision set not null;

alter table public.pachanga_referee_assignments
  drop constraint if exists pachanga_referee_assignments_source_kind_check,
  drop constraint if exists pachanga_referee_assignments_status_check,
  drop constraint if exists pachanga_referee_assignments_effective_schedule_check,
  drop constraint if exists pachanga_referee_assignments_schedule_state_check,
  drop constraint if exists pachanga_referee_assignments_venue_status_check,
  drop constraint if exists pachanga_referee_assignments_modality_check,
  add constraint pachanga_referee_assignments_source_kind_check check (
    source_kind in ('group_match', 'open_match', 'external_match', 'team_challenge', 'competition_generated')
  ),
  add constraint pachanga_referee_assignments_status_check check (
    status in ('proposed', 'accepted', 'confirmed', 'declined', 'cancelled', 'expired', 'replaced', 'completed')
  ),
  add constraint pachanga_referee_assignments_effective_schedule_check check (
    effective_scheduled_start < effective_scheduled_end
    and effective_schedule_revision >= 0
    and length(effective_timezone) between 3 and 80
  ),
  add constraint pachanga_referee_assignments_schedule_state_check check (
    schedule_state in ('CURRENT', 'RECONFIRMATION_REQUIRED', 'STALE_SCHEDULE', 'CANCELLED')
  ),
  add constraint pachanga_referee_assignments_venue_status_check check (
    venue_status in ('CONFIRMED', 'SAVED', 'LABEL', 'TBD')
  ),
  add constraint pachanga_referee_assignments_modality_check check (
    modality is null or modality in ('FOOTBALL_11', 'FOOTBALL_7', 'FOOTBALL_5', 'FUTSAL', 'OTHER')
  );

do $$
declare constraint_row record;
begin
  for constraint_row in
    select constraints.conname
    from pg_constraint constraints
    where constraints.conrelid = 'public.pachanga_referee_assignments'::regclass
      and constraints.contype = 'c'
      and pg_get_constraintdef(constraints.oid) ilike '%requester_kind%'
  loop
    execute format(
      'alter table public.pachanga_referee_assignments drop constraint %I',
      constraint_row.conname
    );
  end loop;
end;
$$;

alter table public.pachanga_referee_assignments
  add constraint pachanga_referee_assignments_requester_check check (
    requester_kind in ('TEAM', 'CLUB', 'COMPETITION')
    and (requester_kind = 'TEAM') = (requester_team_id is not null)
    and (requester_kind = 'CLUB') = (requester_club_id is not null)
    and (requester_kind = 'COMPETITION') = (requester_competition_id is not null)
  );

drop index if exists public.pachanga_referee_assignment_active_slot_idx;
create unique index pachanga_referee_assignment_active_slot_idx
  on public.pachanga_referee_assignments(canonical_match_id, assignment_role)
  where status in ('confirmed', 'completed')
     or (status = 'accepted' and replaces_assignment_id is null);

drop index if exists public.pachanga_referee_assignments_overlap_idx;
create index pachanga_referee_assignments_overlap_idx
  on public.pachanga_referee_assignments(
    referee_profile_id, effective_scheduled_start, effective_scheduled_end, id
  ) where status in ('accepted', 'confirmed') and schedule_state = 'CURRENT';

create index if not exists pachanga_referee_assignments_schedule_health_idx
  on public.pachanga_referee_assignments(
    schedule_state, effective_scheduled_start, canonical_match_id, id
  ) where status in ('proposed', 'accepted', 'confirmed');

create index if not exists pachanga_referee_assignments_canonical_binding_idx
  on public.pachanga_referee_assignments(canonical_binding_id)
  where canonical_binding_id is not null;

create index if not exists pachanga_referee_assignments_competition_context_idx
  on public.pachanga_referee_assignments(competition_match_context_id)
  where competition_match_context_id is not null;

create index if not exists pachanga_referee_assignments_requester_competition_idx
  on public.pachanga_referee_assignments(requester_competition_id)
  where requester_competition_id is not null;

create table if not exists private.pachanga_referee_assignment_terms (
  assignment_id uuid primary key references public.pachanga_referee_assignments(id) on delete restrict,
  fee_mode text not null default 'NEGOTIABLE',
  proposed_fee_cents integer,
  counter_fee_cents integer,
  agreed_fee_cents integer,
  currency text not null default 'EUR',
  travel_included boolean not null default false,
  private_terms_note text not null default '',
  terms_status text not null default 'PROPOSED',
  terms_revision bigint not null default 1,
  proposed_by uuid references auth.users(id) on delete restrict,
  countered_by uuid references auth.users(id) on delete restrict,
  accepted_by uuid references auth.users(id) on delete restrict,
  proposed_at timestamptz not null default clock_timestamp(),
  countered_at timestamptz,
  accepted_at timestamptz,
  declined_at timestamptz,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (fee_mode in ('FREE', 'FIXED', 'NEGOTIABLE', 'VOLUNTEER')),
  check (proposed_fee_cents is null or proposed_fee_cents between 0 and 10000000),
  check (counter_fee_cents is null or counter_fee_cents between 0 and 10000000),
  check (agreed_fee_cents is null or agreed_fee_cents between 0 and 10000000),
  check (currency ~ '^[A-Z]{3}$'),
  check (length(private_terms_note) <= 1200),
  check (terms_status in ('PROPOSED', 'COUNTERED', 'ACCEPTED', 'DECLINED')),
  check (terms_revision >= 1),
  check (
    (fee_mode in ('FREE', 'VOLUNTEER') and proposed_fee_cents is null)
    or fee_mode in ('FIXED', 'NEGOTIABLE')
  )
);

create index if not exists pachanga_referee_assignment_terms_proposed_by_idx
  on private.pachanga_referee_assignment_terms(proposed_by)
  where proposed_by is not null;

create index if not exists pachanga_referee_assignment_terms_countered_by_idx
  on private.pachanga_referee_assignment_terms(countered_by)
  where countered_by is not null;

create index if not exists pachanga_referee_assignment_terms_accepted_by_idx
  on private.pachanga_referee_assignment_terms(accepted_by)
  where accepted_by is not null;

create table if not exists private.pachanga_referee_assignment_term_revisions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.pachanga_referee_assignments(id) on delete restrict,
  version bigint not null,
  fee_mode text not null,
  proposed_fee_cents integer,
  counter_fee_cents integer,
  agreed_fee_cents integer,
  currency text not null,
  travel_included boolean not null,
  private_terms_note text not null,
  terms_status text not null,
  actor_id uuid references auth.users(id) on delete set null,
  server_sequence bigint not null,
  effective_at timestamptz not null default clock_timestamp(),
  unique (assignment_id, version)
);

create index if not exists pachanga_referee_assignment_term_revisions_actor_idx
  on private.pachanga_referee_assignment_term_revisions(actor_id)
  where actor_id is not null;

create table if not exists public.pachanga_referee_assignment_revisions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.pachanga_referee_assignments(id) on delete restrict,
  version bigint not null,
  status text not null,
  schedule_state text not null,
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  replaces_assignment_id uuid references public.pachanga_referee_assignments(id) on delete restrict,
  replaced_by_assignment_id uuid references public.pachanga_referee_assignments(id) on delete restrict,
  effective_scheduled_start timestamptz not null,
  effective_scheduled_end timestamptz not null,
  effective_timezone text not null,
  effective_schedule_revision bigint not null,
  reason_code text not null,
  actor_id uuid references auth.users(id) on delete set null,
  snapshot jsonb not null,
  server_sequence bigint not null,
  effective_at timestamptz not null default clock_timestamp(),
  unique (assignment_id, version),
  check (jsonb_typeof(snapshot) = 'object')
);

create index if not exists pachanga_referee_assignment_revisions_profile_idx
  on public.pachanga_referee_assignment_revisions(referee_profile_id);

create index if not exists pachanga_referee_assignment_revisions_match_idx
  on public.pachanga_referee_assignment_revisions(canonical_match_id);

create index if not exists pachanga_referee_assignment_revisions_replaces_idx
  on public.pachanga_referee_assignment_revisions(replaces_assignment_id)
  where replaces_assignment_id is not null;

create index if not exists pachanga_referee_assignment_revisions_replaced_by_idx
  on public.pachanga_referee_assignment_revisions(replaced_by_assignment_id)
  where replaced_by_assignment_id is not null;

create index if not exists pachanga_referee_assignment_revisions_actor_idx
  on public.pachanga_referee_assignment_revisions(actor_id)
  where actor_id is not null;

insert into public.pachanga_referee_assignment_revisions(
  assignment_id, version, status, schedule_state, referee_profile_id,
  canonical_match_id, replaces_assignment_id, replaced_by_assignment_id,
  effective_scheduled_start, effective_scheduled_end, effective_timezone,
  effective_schedule_revision, reason_code, actor_id, snapshot, server_sequence,
  effective_at
)
select assignments.id, assignments.revision, assignments.status,
  assignments.schedule_state, assignments.referee_profile_id,
  assignments.canonical_match_id, assignments.replaces_assignment_id,
  assignments.replaced_by_assignment_id, assignments.effective_scheduled_start,
  assignments.effective_scheduled_end, assignments.effective_timezone,
  assignments.effective_schedule_revision, 'wave4_initial_snapshot', null,
  jsonb_build_object(
    'status', assignments.status,
    'scheduleState', assignments.schedule_state,
    'canonicalMatchId', assignments.canonical_match_id,
    'refereeProfileId', assignments.referee_profile_id
  ),
  assignments.server_sequence, assignments.updated_at
from public.pachanga_referee_assignments assignments
on conflict (assignment_id, version) do nothing;

create table if not exists private.pachanga_referee_result_observations (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.pachanga_referee_assignments(id) on delete restrict,
  referee_profile_id uuid not null references public.pachanga_referee_profiles(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  home_score integer not null,
  away_score integer not null,
  private_note text not null default '',
  operation_id uuid not null unique,
  observation_revision bigint not null,
  server_sequence bigint not null default nextval('private.pachanga_referee_sequence'),
  observed_at timestamptz not null default clock_timestamp(),
  created_by uuid not null references auth.users(id) on delete restrict,
  unique (assignment_id, observation_revision),
  check (home_score between 0 and 99 and away_score between 0 and 99),
  check (length(private_note) <= 1200),
  check (observation_revision >= 1)
);

alter table public.pachanga_competition_disciplinary_events
  add column if not exists referee_assignment_id uuid references public.pachanga_referee_assignments(id) on delete restrict,
  add column if not exists reporting_referee_profile_id uuid references public.pachanga_referee_profiles(id) on delete restrict;

alter table public.pachanga_competition_disciplinary_events
  drop constraint if exists pachanga_discipline_referee_assignment_pair_check,
  add constraint pachanga_discipline_referee_assignment_pair_check check (
    (referee_assignment_id is null) = (reporting_referee_profile_id is null)
  );

create index if not exists pachanga_discipline_referee_assignment_idx
  on public.pachanga_competition_disciplinary_events(
    referee_assignment_id, status, server_sequence desc, id
  ) where referee_assignment_id is not null;

create index if not exists pachanga_discipline_reporting_referee_idx
  on public.pachanga_competition_disciplinary_events(reporting_referee_profile_id)
  where reporting_referee_profile_id is not null;

alter table public.pachanga_referee_statistics_snapshots
  add column if not exists replacements bigint not null default 0,
  add column if not exists cancellations bigint not null default 0,
  add column if not exists league_matches_completed bigint not null default 0;

do $$
declare constraint_row record;
begin
  for constraint_row in
    select constraints.conname
    from pg_constraint constraints
    where constraints.conrelid = 'public.pachanga_referee_statistics_snapshots'::regclass
      and constraints.contype = 'c'
      and (
        pg_get_constraintdef(constraints.oid) ilike '%discipline_stats_status%'
        or pg_get_constraintdef(constraints.oid) ilike '%yellow_cards_shown%'
      )
  loop
    execute format(
      'alter table public.pachanga_referee_statistics_snapshots drop constraint %I',
      constraint_row.conname
    );
  end loop;
end;
$$;

update public.pachanga_referee_statistics_snapshots snapshots
set discipline_stats_status = 'CANONICAL_R5',
    yellow_cards_shown = coalesce(snapshots.yellow_cards_shown, 0),
    red_cards_shown = coalesce(snapshots.red_cards_shown, 0),
    blue_cards_shown = coalesce(snapshots.blue_cards_shown, 0);

alter table public.pachanga_referee_statistics_snapshots
  alter column yellow_cards_shown set default 0,
  alter column red_cards_shown set default 0,
  alter column blue_cards_shown set default 0,
  alter column yellow_cards_shown set not null,
  alter column red_cards_shown set not null,
  alter column blue_cards_shown set not null,
  add constraint pachanga_referee_statistics_discipline_status_check check (
    discipline_stats_status in ('NOT_AVAILABLE', 'CANONICAL_R5')
  ),
  add constraint pachanga_referee_statistics_card_counts_check check (
    yellow_cards_shown >= 0 and red_cards_shown >= 0 and blue_cards_shown >= 0
  ),
  add constraint pachanga_referee_statistics_wave4_counts_check check (
    replacements >= 0 and cancellations >= 0 and league_matches_completed >= 0
  );

alter table public.pachanga_referee_invalidations
  add column if not exists canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete cascade,
  add column if not exists competition_id uuid references public.pachanga_competitions(id) on delete cascade;

create or replace function private.pachanga_referee_assignment_invalidation_scope_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.entity_type = 'referee_assignment'
     and new.entity_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    select assignments.canonical_match_id, assignments.competition_id
      into new.canonical_match_id, new.competition_id
    from public.pachanga_referee_assignments assignments
    where assignments.id = new.entity_id::uuid;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_referee_assignment_invalidation_scope_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_referee_assignment_invalidation_scope_v1
  on public.pachanga_referee_invalidations;
create trigger pachanga_referee_assignment_invalidation_scope_v1
before insert on public.pachanga_referee_invalidations
for each row execute function private.pachanga_referee_assignment_invalidation_scope_v1();

create index if not exists pachanga_referee_invalidations_match_idx
  on public.pachanga_referee_invalidations(
    canonical_match_id, server_sequence desc, id desc
  ) where canonical_match_id is not null;

create index if not exists pachanga_referee_invalidations_competition_idx
  on public.pachanga_referee_invalidations(
    competition_id, server_sequence desc, id desc
  ) where competition_id is not null;

revoke all on table private.pachanga_referee_assignment_terms,
  private.pachanga_referee_assignment_term_revisions,
  private.pachanga_referee_result_observations,
  private.pachanga_referee_public_fee_consents
  from public, anon, authenticated;

revoke all on table public.pachanga_referee_assignment_revisions
  from public, anon, authenticated;

comment on table public.pachanga_referee_assignment_revisions is
  'Immutable R3 assignment history. Product reads use bounded RPC snapshots, never direct table grants.';
comment on table private.pachanga_referee_assignment_terms is
  'Private out-of-platform fee agreement. This table is not a payment authority.';
comment on table private.pachanga_referee_result_observations is
  'Private referee evidence only. R4C remains the official result authority.';
