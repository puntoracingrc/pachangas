alter table public.pachanga_player_profiles
add column if not exists assessment_summary jsonb not null default '{}'::jsonb;

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

create unique index if not exists pachanga_player_assessments_user_kind_idx
on public.pachanga_player_assessments(user_id, assessment_kind);

create unique index if not exists pachanga_player_assessments_user_idempotency_idx
on public.pachanga_player_assessments(user_id, idempotency_key);

create index if not exists pachanga_player_assessments_profile_kind_idx
on public.pachanga_player_assessments(player_profile_id, assessment_kind)
where player_profile_id is not null;

grant select on public.pachanga_player_assessments to authenticated;

alter table public.pachanga_player_assessments enable row level security;

drop policy if exists "Users can read own player assessments" on public.pachanga_player_assessments;
create policy "Users can read own player assessments"
on public.pachanga_player_assessments
for select
to authenticated
using (
  public.is_registered_pachanga_user()
  and user_id = (select auth.uid())
);
