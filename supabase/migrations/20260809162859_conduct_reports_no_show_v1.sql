-- Pachangas IQ Conduct, Reports and No-show V1.
-- Additive, server-authoritative and isolated from every sporting rating.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create sequence if not exists public.pachanga_conduct_sequence;
revoke all on sequence public.pachanga_conduct_sequence from public, anon, authenticated;
grant usage, select on sequence public.pachanga_conduct_sequence to service_role;

create table if not exists private.pachanga_conduct_settings (
  singleton boolean primary key default true check (singleton),
  policy_version text not null default 'conduct-v1-experimental',
  attendance_closure_enabled boolean not null default false,
  conduct_reports_enabled boolean not null default false,
  social_restrictions_enabled boolean not null default false,
  attendance_closure_window_hours integer not null default 48,
  attendance_dispute_window_hours integer not null default 72,
  no_show_reminder_count integer not null default 2,
  no_show_reminder_window_days integer not null default 90,
  no_show_review_count integer not null default 3,
  no_show_review_window_days integer not null default 180,
  late_cancellation_reminder_count integer not null default 4,
  late_cancellation_window_days integer not null default 90,
  operational_retention_days integer not null default 730,
  archive_retention_days integer not null default 1825,
  updated_at timestamptz not null default clock_timestamp(),
  check (attendance_closure_window_hours between 1 and 168),
  check (attendance_dispute_window_hours between 1 and 336),
  check (no_show_reminder_count between 1 and 20),
  check (no_show_review_count >= no_show_reminder_count),
  check (no_show_reminder_window_days between 1 and 730),
  check (no_show_review_window_days >= no_show_reminder_window_days),
  check (late_cancellation_reminder_count between 1 and 50),
  check (late_cancellation_window_days between 1 and 730),
  check (operational_retention_days between 30 and 3650),
  check (archive_retention_days >= operational_retention_days)
);

insert into private.pachanga_conduct_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists public.pachanga_conduct_subject_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1)
);

create table if not exists public.pachanga_attendance_group_state (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  match_id text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (group_id, match_id),
  check (char_length(match_id) between 1 and 160),
  check (revision >= 1)
);

create table if not exists private.pachanga_conduct_operation_receipts (
  operation_id uuid primary key,
  actor_user_id uuid not null references auth.users(id) on delete restrict,
  operation_type text not null,
  expected_revision bigint,
  result_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  check (result_revision >= 0),
  check (jsonb_typeof(response) = 'object'),
  check (jsonb_typeof(client_metadata) = 'object')
);

create table if not exists private.pachanga_attendance_closures (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  match_id text not null,
  context_kind text not null default 'match',
  match_occurred_at timestamptz not null,
  state text not null default 'open',
  policy_version text not null,
  revision bigint not null default 0,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  opened_by uuid not null references auth.users(id) on delete restrict,
  closed_by uuid references auth.users(id) on delete restrict,
  closed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (group_id, match_id),
  check (context_kind in ('match', 'open_match', 'guest_participation')),
  check (state in ('open', 'closed')),
  check (revision >= 0)
);

create table if not exists private.pachanga_post_match_attendance (
  id uuid primary key default gen_random_uuid(),
  closure_id uuid not null references private.pachanga_attendance_closures(id) on delete restrict,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  match_id text not null,
  local_player_id text not null,
  target_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  target_user_id uuid references auth.users(id) on delete restrict,
  display_name_snapshot text not null,
  initial_match_status text not null,
  original_outcome text not null,
  current_outcome text not null,
  response_state text not null,
  dispute_deadline timestamptz,
  responded_at timestamptz,
  certified_by uuid not null references auth.users(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (closure_id, local_player_id),
  check (char_length(local_player_id) between 1 and 160),
  check (initial_match_status in ('voy', 'duda', 'no')),
  check (original_outcome in ('played', 'excused_absence', 'late_cancellation', 'unexcused_no_show')),
  check (current_outcome in ('played', 'excused_absence', 'late_cancellation', 'unexcused_no_show')),
  check (response_state in (
    'not_required', 'pending', 'agreed', 'disputed', 'under_review',
    'confirmed_uncontested', 'maintained', 'corrected'
  )),
  check (revision >= 1)
);

create table if not exists private.pachanga_attendance_reviews (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null unique references private.pachanga_post_match_attendance(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  state text not null default 'submitted',
  player_note text,
  admin_note text,
  resolved_by uuid references auth.users(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  submitted_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (state in ('submitted', 'under_review', 'maintained', 'corrected', 'escalated', 'closed')),
  check (player_note is null or char_length(player_note) <= 500),
  check (admin_note is null or char_length(admin_note) <= 500),
  check (revision >= 1)
);

create table if not exists private.pachanga_attendance_events (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references private.pachanga_post_match_attendance(id) on delete restrict,
  operation_id uuid not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  from_outcome text,
  to_outcome text,
  from_response_state text,
  to_response_state text,
  reason text,
  attendance_revision bigint not null,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, attendance_id, event_type),
  check (jsonb_typeof(payload) = 'object'),
  check (attendance_revision >= 1)
);

create table if not exists private.pachanga_moderation_cases (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  target_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  source_type text not null default 'conduct_report',
  category text not null,
  state text not null default 'submitted',
  priority text not null default 'normal',
  report_count integer not null default 0,
  source_cluster_count integer not null default 0,
  independent_source_count integer not null default 0,
  correlated_source_count integer not null default 0,
  correlated_reporting boolean not null default false,
  mutual_retaliation boolean not null default false,
  restriction_recommended boolean not null default false,
  decision_summary text,
  assigned_moderator_user_id uuid references auth.users(id) on delete set null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  first_reported_at timestamptz not null default clock_timestamp(),
  last_reported_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (source_type in ('conduct_report', 'attendance_reliability', 'attendance_dispute')),
  check (category in (
    'abusive_behavior', 'harassment', 'threats_or_violence', 'discriminatory_behavior',
    'deliberate_cheating', 'repeated_disruption', 'other', 'attendance_reliability'
  )),
  check (state in (
    'submitted', 'clustered', 'triaged', 'under_review', 'confirmed', 'dismissed',
    'warned', 'restricted', 'appealed', 'corrected', 'upheld', 'closed'
  )),
  check (priority in ('normal', 'high', 'urgent_review')),
  check (report_count >= 0 and source_cluster_count >= 0 and independent_source_count >= 0 and correlated_source_count >= 0),
  check (decision_summary is null or char_length(decision_summary) <= 500),
  check (revision >= 1)
);

create unique index if not exists pachanga_moderation_cases_open_target_category_idx
  on private.pachanga_moderation_cases(target_profile_id, source_type, category)
  where state not in ('dismissed', 'corrected', 'closed');

create table if not exists private.pachanga_report_source_clusters (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  source_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  context_kind text not null,
  context_id text not null,
  report_count integer not null default 0,
  first_reported_at timestamptz not null default clock_timestamp(),
  last_reported_at timestamptz not null default clock_timestamp(),
  unique (case_id, source_group_id, context_kind, context_id),
  check (context_kind in ('match', 'challenge', 'open_match', 'guest_participation')),
  check (report_count >= 0)
);

create table if not exists private.pachanga_conduct_reports (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  source_cluster_id uuid not null references private.pachanga_report_source_clusters(id) on delete restrict,
  reporter_user_id uuid not null references auth.users(id) on delete restrict,
  reporter_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  target_profile_id uuid not null references public.pachanga_player_profiles(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  target_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  context_kind text not null,
  context_id text not null,
  context_revision bigint not null,
  category text not null,
  description text,
  operation_id uuid not null unique,
  state text not null default 'active',
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  unique (reporter_user_id, target_profile_id, context_kind, context_id, category),
  check (reporter_user_id <> target_user_id),
  check (context_kind in ('match', 'challenge', 'open_match', 'guest_participation')),
  check (category in (
    'abusive_behavior', 'harassment', 'threats_or_violence', 'discriminatory_behavior',
    'deliberate_cheating', 'repeated_disruption', 'other'
  )),
  check (description is null or char_length(description) <= 500),
  check (state in ('active', 'withdrawn', 'dismissed')),
  check (context_revision >= 1)
);

create table if not exists private.pachanga_moderation_events (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  operation_id uuid not null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  from_state text,
  to_state text,
  case_revision bigint not null,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  unique (operation_id, case_id, event_type),
  check (jsonb_typeof(payload) = 'object'),
  check (case_revision >= 1)
);

create table if not exists private.pachanga_conduct_warnings (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  category text not null,
  state text not null default 'active',
  issued_by uuid not null references auth.users(id) on delete restrict,
  issued_at timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  check (state in ('active', 'expired', 'appealed', 'corrected', 'revoked')),
  check (revision >= 1)
);

create table if not exists private.pachanga_social_restrictions (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  restriction_type text not null,
  duration_days integer,
  state text not null default 'active',
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_at timestamptz not null default clock_timestamp(),
  effective_until timestamptz,
  ended_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  check (restriction_type in (
    'public_market', 'send_challenges', 'receive_public_challenges',
    'public_match_access', 'public_guest_access'
  )),
  check (duration_days is null or duration_days in (7, 30, 90)),
  check (state in ('active', 'expired', 'appealed', 'corrected', 'revoked')),
  check (revision >= 1)
);

create table if not exists private.pachanga_conduct_appeals (
  id uuid primary key default gen_random_uuid(),
  opaque_reference uuid not null unique default gen_random_uuid(),
  case_id uuid not null references private.pachanga_moderation_cases(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  action_kind text not null,
  warning_id uuid references private.pachanga_conduct_warnings(id) on delete restrict,
  restriction_id uuid references private.pachanga_social_restrictions(id) on delete restrict,
  explanation text not null,
  state text not null default 'submitted',
  resolution_note text,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_conduct_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (action_kind in ('warning', 'restriction')),
  check ((action_kind = 'warning' and warning_id is not null and restriction_id is null)
    or (action_kind = 'restriction' and restriction_id is not null and warning_id is null)),
  check (char_length(explanation) between 1 and 500),
  check (resolution_note is null or char_length(resolution_note) <= 500),
  check (state in ('submitted', 'under_review', 'upheld', 'corrected', 'closed')),
  check (revision >= 1)
);

create unique index if not exists pachanga_conduct_appeals_open_warning_idx
  on private.pachanga_conduct_appeals(warning_id)
  where state in ('submitted', 'under_review');
create unique index if not exists pachanga_conduct_appeals_open_restriction_idx
  on private.pachanga_conduct_appeals(restriction_id)
  where state in ('submitted', 'under_review');

create index if not exists pachanga_post_match_attendance_target_idx
  on private.pachanga_post_match_attendance(target_user_id, server_sequence desc, id desc)
  where target_user_id is not null;
create index if not exists pachanga_post_match_attendance_group_match_idx
  on private.pachanga_post_match_attendance(group_id, match_id, server_sequence, id);
create index if not exists pachanga_attendance_events_attendance_idx
  on private.pachanga_attendance_events(attendance_id, server_sequence, id);
create index if not exists pachanga_conduct_reports_case_idx
  on private.pachanga_conduct_reports(case_id, server_sequence, id);
create index if not exists pachanga_conduct_reports_target_idx
  on private.pachanga_conduct_reports(target_user_id, server_sequence desc, id desc);
create index if not exists pachanga_moderation_cases_queue_idx
  on private.pachanga_moderation_cases(state, priority, server_sequence, id)
  where state not in ('dismissed', 'corrected', 'closed');
create index if not exists pachanga_social_restrictions_active_idx
  on private.pachanga_social_restrictions(target_user_id, restriction_type, effective_until, id)
  where state = 'active';

alter table public.pachanga_conduct_subject_state enable row level security;
alter table public.pachanga_attendance_group_state enable row level security;
alter table private.pachanga_conduct_settings enable row level security;
alter table private.pachanga_conduct_operation_receipts enable row level security;
alter table private.pachanga_attendance_closures enable row level security;
alter table private.pachanga_post_match_attendance enable row level security;
alter table private.pachanga_attendance_reviews enable row level security;
alter table private.pachanga_attendance_events enable row level security;
alter table private.pachanga_moderation_cases enable row level security;
alter table private.pachanga_report_source_clusters enable row level security;
alter table private.pachanga_conduct_reports enable row level security;
alter table private.pachanga_moderation_events enable row level security;
alter table private.pachanga_conduct_warnings enable row level security;
alter table private.pachanga_social_restrictions enable row level security;
alter table private.pachanga_conduct_appeals enable row level security;

revoke all on table public.pachanga_conduct_subject_state from public, anon, authenticated;
revoke all on table public.pachanga_attendance_group_state from public, anon, authenticated;
grant select on table public.pachanga_conduct_subject_state to authenticated;
grant select on table public.pachanga_attendance_group_state to authenticated;

revoke all on table private.pachanga_conduct_settings from public, anon, authenticated;
revoke all on table private.pachanga_conduct_operation_receipts from public, anon, authenticated;
revoke all on table private.pachanga_attendance_closures from public, anon, authenticated;
revoke all on table private.pachanga_post_match_attendance from public, anon, authenticated;
revoke all on table private.pachanga_attendance_reviews from public, anon, authenticated;
revoke all on table private.pachanga_attendance_events from public, anon, authenticated;
revoke all on table private.pachanga_moderation_cases from public, anon, authenticated;
revoke all on table private.pachanga_report_source_clusters from public, anon, authenticated;
revoke all on table private.pachanga_conduct_reports from public, anon, authenticated;
revoke all on table private.pachanga_moderation_events from public, anon, authenticated;
revoke all on table private.pachanga_conduct_warnings from public, anon, authenticated;
revoke all on table private.pachanga_social_restrictions from public, anon, authenticated;
revoke all on table private.pachanga_conduct_appeals from public, anon, authenticated;

grant all on table private.pachanga_conduct_settings to service_role;
grant all on table private.pachanga_conduct_operation_receipts to service_role;
grant all on table private.pachanga_attendance_closures to service_role;
grant all on table private.pachanga_post_match_attendance to service_role;
grant all on table private.pachanga_attendance_reviews to service_role;
grant all on table private.pachanga_attendance_events to service_role;
grant all on table private.pachanga_moderation_cases to service_role;
grant all on table private.pachanga_report_source_clusters to service_role;
grant all on table private.pachanga_conduct_reports to service_role;
grant all on table private.pachanga_moderation_events to service_role;
grant all on table private.pachanga_conduct_warnings to service_role;
grant all on table private.pachanga_social_restrictions to service_role;
grant all on table private.pachanga_conduct_appeals to service_role;

drop policy if exists "Users read their conduct revision" on public.pachanga_conduct_subject_state;
create policy "Users read their conduct revision"
on public.pachanga_conduct_subject_state
for select to authenticated
using ((select auth.uid()) is not null and (select auth.uid()) = user_id);

drop policy if exists "Admins read attendance revisions" on public.pachanga_attendance_group_state;
create policy "Admins read attendance revisions"
on public.pachanga_attendance_group_state
for select to authenticated
using ((select auth.uid()) is not null and public.is_pachanga_group_admin(group_id));

create or replace function private.pachanga_is_security_moderator_v1()
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select (select auth.uid()) is not null
    and coalesce((select auth.jwt()) -> 'app_metadata' ->> 'pachangas_security_role', '')
      in ('moderator', 'security_admin');
$$;

revoke all on function private.pachanga_is_security_moderator_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_conduct_client_metadata_v1(value jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', left(nullif(value ->> 'clientVersion', ''), 80),
    'serviceWorkerVersion', left(nullif(value ->> 'serviceWorkerVersion', ''), 80),
    'displayMode', left(nullif(value ->> 'displayMode', ''), 32),
    'sessionId', left(nullif(value ->> 'sessionId', ''), 120),
    'surface', left(nullif(value ->> 'surface', ''), 80)
  ));
$$;

revoke all on function private.pachanga_conduct_client_metadata_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_conduct_replay_v1(
  target_operation_id uuid,
  target_operation_type text,
  target_actor_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  receipt private.pachanga_conduct_operation_receipts%rowtype;
begin
  select * into receipt
  from private.pachanga_conduct_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_user_id <> target_actor_user_id or receipt.operation_type <> target_operation_type then
    raise exception 'Operation id already belongs to another conduct action' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

revoke all on function private.pachanga_conduct_replay_v1(uuid, text, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_conduct_save_receipt_v1(
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_operation_type text,
  target_expected_revision bigint,
  target_result_revision bigint,
  target_server_sequence bigint,
  target_response jsonb,
  target_client_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into private.pachanga_conduct_operation_receipts(
    operation_id, actor_user_id, operation_type, expected_revision,
    result_revision, server_sequence, response, client_metadata
  ) values (
    target_operation_id, target_actor_user_id, target_operation_type,
    target_expected_revision, target_result_revision, target_server_sequence,
    target_response, private.pachanga_conduct_client_metadata_v1(coalesce(target_client_metadata, '{}'::jsonb))
  );
  return target_response;
end;
$$;

revoke all on function private.pachanga_conduct_save_receipt_v1(uuid, uuid, text, bigint, bigint, bigint, jsonb, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_bump_conduct_subject_v1(target_user_id uuid)
returns public.pachanga_conduct_subject_state
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare saved public.pachanga_conduct_subject_state%rowtype;
begin
  if target_user_id is null then return null; end if;
  insert into public.pachanga_conduct_subject_state(user_id)
  values (target_user_id)
  on conflict (user_id) do update set
    revision = public.pachanga_conduct_subject_state.revision + 1,
    server_sequence = nextval('public.pachanga_conduct_sequence'),
    updated_at = clock_timestamp()
  returning * into saved;
  return saved;
end;
$$;

revoke all on function private.pachanga_bump_conduct_subject_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_bump_attendance_group_v1(target_group_id uuid, target_match_id text)
returns public.pachanga_attendance_group_state
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare saved public.pachanga_attendance_group_state%rowtype;
begin
  insert into public.pachanga_attendance_group_state(group_id, match_id)
  values (target_group_id, target_match_id)
  on conflict (group_id, match_id) do update set
    revision = public.pachanga_attendance_group_state.revision + 1,
    server_sequence = nextval('public.pachanga_conduct_sequence'),
    updated_at = clock_timestamp()
  returning * into saved;
  return saved;
end;
$$;

revoke all on function private.pachanga_bump_attendance_group_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_conduct_notify_moderators_v1(
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_dedupe_prefix text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare moderator record;
begin
  for moderator in
    select users.id
    from auth.users users
    where coalesce(users.raw_app_meta_data ->> 'pachangas_security_role', '')
      in ('moderator', 'security_admin')
  loop
    perform private.pachanga_notify_v1(
      moderator.id, target_kind, target_title, target_body, target_action_url,
      coalesce(target_payload, '{}'::jsonb), target_dedupe_prefix || ':' || moderator.id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_conduct_notify_moderators_v1(text, text, text, text, jsonb, text)
  from public, anon, authenticated;

create or replace function private.pachanga_group_player_identity_v1(
  target_group_id uuid,
  target_local_player_id text
)
returns table(profile_id uuid, user_id uuid, display_name text)
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select
    profiles.id,
    profiles.user_id,
    coalesce(nullif(players.value ->> 'name', ''), profiles.display_name, 'Jugador')
  from public.pachanga_groups groups
  cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) players(value)
  left join public.pachanga_player_profiles profiles
    on profiles.user_id = case
      when coalesce(players.value ->> 'ownerUserId', '')
        ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then (players.value ->> 'ownerUserId')::uuid
      else null
    end
  where groups.id = target_group_id
    and players.value ->> 'id' = target_local_player_id
  limit 1;
$$;

revoke all on function private.pachanga_group_player_identity_v1(uuid, text)
  from public, anon, authenticated;

create or replace function public.get_pachanga_conduct_capabilities_v1()
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'policyVersion', settings.policy_version,
    'attendanceClosureEnabled', settings.attendance_closure_enabled,
    'conductReportsEnabled', settings.conduct_reports_enabled,
    'socialRestrictionsEnabled', settings.social_restrictions_enabled,
    'attendanceClosureWindowHours', settings.attendance_closure_window_hours,
    'attendanceDisputeWindowHours', settings.attendance_dispute_window_hours
  )
  from private.pachanga_conduct_settings settings
  where settings.singleton;
$$;

revoke all on function public.get_pachanga_conduct_capabilities_v1() from public, anon, authenticated;
grant execute on function public.get_pachanga_conduct_capabilities_v1() to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'pachanga_conduct_subject_state'
  ) then
    alter publication supabase_realtime add table public.pachanga_conduct_subject_state;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'pachanga_attendance_group_state'
  ) then
    alter publication supabase_realtime add table public.pachanga_attendance_group_state;
  end if;
end;
$$;

create or replace function private.pachanga_attendance_snapshot_v1(target_attendance_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', attendance.id,
    'groupId', attendance.group_id,
    'matchId', attendance.match_id,
    'playerId', attendance.local_player_id,
    'displayName', attendance.display_name_snapshot,
    'originalOutcome', attendance.original_outcome,
    'currentOutcome', attendance.current_outcome,
    'responseState', attendance.response_state,
    'disputeDeadline', attendance.dispute_deadline,
    'respondedAt', attendance.responded_at,
    'revision', attendance.revision,
    'serverSequence', attendance.server_sequence,
    'createdAt', attendance.created_at,
    'updatedAt', attendance.updated_at,
    'review', case when reviews.id is null then null else jsonb_build_object(
      'id', reviews.id,
      'state', reviews.state,
      'revision', reviews.revision,
      'submittedAt', reviews.submitted_at,
      'resolvedAt', reviews.resolved_at
    ) end
  ))
  from private.pachanga_post_match_attendance attendance
  left join private.pachanga_attendance_reviews reviews on reviews.attendance_id = attendance.id
  where attendance.id = target_attendance_id;
$$;

revoke all on function private.pachanga_attendance_snapshot_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_evaluate_attendance_reliability_v1(
  target_user_id uuid,
  target_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  settings private.pachanga_conduct_settings%rowtype;
  target_profile public.pachanga_player_profiles%rowtype;
  no_shows_90 integer;
  no_shows_180 integer;
  late_90 integer;
  saved_case private.pachanga_moderation_cases%rowtype;
begin
  if target_user_id is null then return; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  select * into target_profile from public.pachanga_player_profiles profiles
  where profiles.user_id = target_user_id;
  if not found then return; end if;

  select
    count(*) filter (where attendance.updated_at >= clock_timestamp() - make_interval(days => settings.no_show_reminder_window_days)),
    count(*) filter (where attendance.updated_at >= clock_timestamp() - make_interval(days => settings.no_show_review_window_days))
  into no_shows_90, no_shows_180
  from private.pachanga_post_match_attendance attendance
  where attendance.target_user_id = target_user_id
    and attendance.current_outcome = 'unexcused_no_show'
    and attendance.response_state in ('agreed', 'confirmed_uncontested', 'maintained');

  select count(*) into late_90
  from private.pachanga_post_match_attendance attendance
  where attendance.target_user_id = target_user_id
    and attendance.current_outcome = 'late_cancellation'
    and attendance.response_state in ('agreed', 'confirmed_uncontested', 'maintained')
    and attendance.updated_at >= clock_timestamp() - make_interval(days => settings.late_cancellation_window_days);

  if no_shows_90 >= settings.no_show_reminder_count then
    perform private.pachanga_notify_v1(
      target_user_id,
      'attendance_warning_reminder',
      'Recordatorio de asistencia',
      'Confirma solo cuando esperes poder acudir y avisa en cuanto cambie tu disponibilidad.',
      '/perfil/conducta',
      jsonb_build_object('confirmedNoShows', no_shows_90, 'affectsSportRating', false),
      'attendance-no-show-reminder:' || target_user_id::text || ':' || settings.policy_version
    );
  end if;

  if late_90 >= settings.late_cancellation_reminder_count then
    perform private.pachanga_notify_v1(
      target_user_id,
      'attendance_warning_late_cancellation',
      'Recordatorio de fiabilidad',
      'Tus últimas bajas se comunicaron muy cerca del partido. Avisar antes ayuda a cubrir la plaza.',
      '/perfil/conducta',
      jsonb_build_object('lateCancellations', late_90, 'automaticRestriction', false, 'affectsSportRating', false),
      'attendance-late-reminder:' || target_user_id::text || ':' || settings.policy_version
    );
  end if;

  if no_shows_180 >= settings.no_show_review_count then
    insert into private.pachanga_moderation_cases(
      target_profile_id, target_user_id, source_type, category, state, priority,
      restriction_recommended, decision_summary, report_count, source_cluster_count,
      independent_source_count, correlated_source_count
    ) values (
      target_profile.id, target_user_id, 'attendance_reliability', 'attendance_reliability',
      'triaged', 'high', true,
      'Revisión social recomendada por no-shows confirmados; no existe sanción automática.',
      0, 0, 0, 0
    )
    on conflict (target_profile_id, source_type, category)
      where state not in ('dismissed', 'corrected', 'closed')
    do update set
      restriction_recommended = true,
      priority = case when private.pachanga_moderation_cases.priority = 'urgent_review'
        then 'urgent_review' else 'high' end,
      revision = private.pachanga_moderation_cases.revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    returning * into saved_case;

    insert into private.pachanga_moderation_events(
      case_id, operation_id, actor_user_id, event_type, from_state, to_state,
      case_revision, payload
    ) values (
      saved_case.id, target_operation_id, null, 'attendance_review_recommended',
      saved_case.state, saved_case.state, saved_case.revision,
      jsonb_build_object('confirmedNoShows', no_shows_180, 'automaticRestrictionApplied', false, 'affectsSportRating', false)
    ) on conflict do nothing;

    perform private.pachanga_conduct_notify_moderators_v1(
      'conduct_warning_review', 'Revisión social recomendada',
      'Un historial objetivo de asistencia requiere revisión humana.',
      '/admin/conduct?case=' || saved_case.opaque_reference::text,
      jsonb_build_object('caseReference', saved_case.opaque_reference, 'priority', saved_case.priority),
      'conduct-attendance-review:' || saved_case.id::text
    );
  end if;
end;
$$;

revoke all on function private.pachanga_evaluate_attendance_reliability_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.close_pachanga_post_match_attendance_v1(
  target_group_id uuid,
  target_match_id text,
  target_outcomes jsonb,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  replay jsonb;
  settings private.pachanga_conduct_settings%rowtype;
  selected_group public.pachanga_groups%rowtype;
  selected_match public.pachanga_match_read_model%rowtype;
  match_payload jsonb;
  match_time timestamptz;
  closure private.pachanga_attendance_closures%rowtype;
  outcome_row record;
  participant public.pachanga_match_participants%rowtype;
  identity record;
  saved_attendance private.pachanga_post_match_attendance%rowtype;
  affected jsonb := '[]'::jsonb;
  event_sequence bigint;
  group_state public.pachanga_attendance_group_state%rowtype;
  response jsonb;
begin
  if current_user_id is null or operation_id is null or expected_revision is null
    or nullif(trim(target_match_id), '') is null then
    raise exception 'Authentication, operation id, match and expected revision required';
  end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.close', current_user_id);
  if replay is not null then return replay; end if;
  if not public.is_registered_pachanga_user() or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only registered admins can close their team attendance';
  end if;
  if jsonb_typeof(coalesce(target_outcomes, 'null'::jsonb)) <> 'array'
    or jsonb_array_length(target_outcomes) = 0 then
    raise exception 'At least one attendance outcome is required';
  end if;
  if exists (
    select 1 from jsonb_array_elements(target_outcomes) rows(value)
    where jsonb_typeof(rows.value) <> 'object'
      or nullif(trim(rows.value ->> 'playerId'), '') is null
      or rows.value ->> 'outcome' not in ('played', 'excused_absence', 'late_cancellation', 'unexcused_no_show')
  ) then raise exception 'Invalid attendance outcome'; end if;
  if exists (
    select 1 from jsonb_array_elements(target_outcomes) rows(value)
    group by rows.value ->> 'playerId' having count(*) > 1
  ) then raise exception 'Duplicate attendance player'; end if;

  perform pg_advisory_xact_lock(hashtextextended(target_group_id::text || ':' || target_match_id, 701));
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.close', current_user_id);
  if replay is not null then return replay; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  if not settings.attendance_closure_enabled then
    raise exception 'Attendance closure is not enabled';
  end if;
  select * into selected_group from public.pachanga_groups groups
  where groups.id = target_group_id for update;
  if not found then raise exception 'Group not found'; end if;
  select * into selected_match from public.pachanga_match_read_model matches
  where matches.group_id = target_group_id and matches.match_id = target_match_id;
  if not found or not (selected_match.finalized or selected_match.match_state in ('played', 'finalized', 'historical')) then
    raise exception 'Only a played or finalized match can close attendance';
  end if;
  if jsonb_array_length(target_outcomes) <> (
    select count(*) from public.pachanga_match_participants participants
    where participants.group_id = target_group_id and participants.match_id = target_match_id
  ) or exists (
    select 1 from public.pachanga_match_participants participants
    where participants.group_id = target_group_id and participants.match_id = target_match_id
      and not exists (
        select 1 from jsonb_array_elements(target_outcomes) submitted(value)
        where submitted.value ->> 'playerId' = participants.player_id
      )
  ) then
    raise exception 'Attendance closure must include every canonical match participant exactly once';
  end if;
  select matches.value into match_payload
  from jsonb_array_elements(coalesce(selected_group.payload -> 'matches', '[]'::jsonb)) matches(value)
  where matches.value ->> 'id' = target_match_id limit 1;
  if match_payload is null then raise exception 'Match payload not found'; end if;
  begin
    match_time := nullif(match_payload ->> 'date', '')::timestamptz;
  exception when others then
    raise exception 'Canonical match date required';
  end;
  if match_time is null or match_time > clock_timestamp() then
    raise exception 'Attendance can only be closed after the match';
  end if;
  if clock_timestamp() > match_time + make_interval(hours => settings.attendance_closure_window_hours) then
    raise exception 'Attendance closure window expired';
  end if;

  select * into closure from private.pachanga_attendance_closures closures
  where closures.group_id = target_group_id and closures.match_id = target_match_id
  for update;
  if not found then
    insert into private.pachanga_attendance_closures(
      group_id, match_id, match_occurred_at, policy_version, opened_by
    ) values (
      target_group_id, target_match_id, match_time, settings.policy_version, current_user_id
    ) returning * into closure;
  end if;
  if closure.revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed attendance.' using errcode = 'PT409';
  end if;
  if closure.state = 'closed' then raise exception 'Attendance is already closed'; end if;

  for outcome_row in
    select rows.value ->> 'playerId' as player_id, rows.value ->> 'outcome' as outcome
    from jsonb_array_elements(target_outcomes) rows(value)
  loop
    select * into participant from public.pachanga_match_participants participants
    where participants.group_id = target_group_id
      and participants.match_id = target_match_id
      and participants.player_id = outcome_row.player_id;
    if not found then raise exception 'Player is not linked to this match'; end if;
    select * into identity
    from private.pachanga_group_player_identity_v1(target_group_id, outcome_row.player_id);
    if not found then raise exception 'Player is not in the certifying team roster'; end if;

    if outcome_row.outcome = 'played'
      and participant.seat_kind <> 'playing'
      and not exists (
        select 1 from public.pachanga_match_rating_participants snapshots
        where snapshots.group_id = target_group_id
          and snapshots.match_id = target_match_id
          and snapshots.local_player_id = outcome_row.player_id
          and snapshots.attendance_confirmed and not snapshots.was_reserve
      ) then raise exception 'Played requires a closed-lineup participant'; end if;
    if outcome_row.outcome = 'unexcused_no_show' and participant.status <> 'voy' then
      raise exception 'No-show requires a confirmed Voy state at match closure';
    end if;
    if outcome_row.outcome = 'late_cancellation' and not (
      participant.status = 'no'
      and exists (
        select 1 from public.pachanga_group_events events
        where events.group_id = target_group_id and events.match_id = target_match_id
          and events.event_type in ('match_attendance_changed', 'match_attendance_v2')
          and events.payload ->> 'playerId' = outcome_row.player_id
          and events.payload ->> 'status' = 'voy'
      )
      and exists (
        select 1 from public.pachanga_group_events events
        where events.group_id = target_group_id and events.match_id = target_match_id
          and events.event_type in ('match_attendance_changed', 'match_attendance_v2')
          and events.payload ->> 'playerId' = outcome_row.player_id
          and events.payload ->> 'status' = 'no'
      )
    ) then raise exception 'Late cancellation requires a recorded Voy to No voy transition'; end if;

    insert into private.pachanga_post_match_attendance(
      closure_id, group_id, match_id, local_player_id, target_profile_id,
      target_user_id, display_name_snapshot, initial_match_status,
      original_outcome, current_outcome, response_state, dispute_deadline, certified_by
    ) values (
      closure.id, target_group_id, target_match_id, outcome_row.player_id,
      identity.profile_id, identity.user_id, identity.display_name, participant.status,
      outcome_row.outcome, outcome_row.outcome,
      case when outcome_row.outcome in ('late_cancellation', 'unexcused_no_show') then 'pending' else 'not_required' end,
      case when outcome_row.outcome in ('late_cancellation', 'unexcused_no_show')
        then clock_timestamp() + make_interval(hours => settings.attendance_dispute_window_hours) else null end,
      current_user_id
    ) returning * into saved_attendance;

    insert into private.pachanga_attendance_events(
      attendance_id, operation_id, actor_user_id, event_type, to_outcome,
      to_response_state, attendance_revision, payload
    ) values (
      saved_attendance.id, operation_id, current_user_id, 'attendance_certified',
      saved_attendance.current_outcome, saved_attendance.response_state,
      saved_attendance.revision,
      jsonb_build_object('affectsSportRating', false, 'automaticSanctionApplied', false)
    );
    affected := affected || jsonb_build_array(private.pachanga_attendance_snapshot_v1(saved_attendance.id));
    if identity.user_id is not null then
      perform private.pachanga_bump_conduct_subject_v1(identity.user_id);
      if outcome_row.outcome in ('late_cancellation', 'unexcused_no_show') then
        perform private.pachanga_notify_v1(
          identity.user_id,
          case when outcome_row.outcome = 'unexcused_no_show'
            then 'attendance_warning_no_show' else 'attendance_warning_late_cancellation' end,
          'Revisa tu asistencia',
          case when outcome_row.outcome = 'unexcused_no_show'
            then 'Tu asistencia se ha registrado como “No asistencia sin aviso”.'
            else 'Tu asistencia se ha registrado como “Cancelación tardía”.' end,
          '/perfil/conducta?attendance=' || saved_attendance.id::text,
          jsonb_build_object(
            'attendanceId', saved_attendance.id,
            'attendanceRevision', saved_attendance.revision,
            'attendanceResponseState', saved_attendance.response_state,
            'attendanceOutcome', saved_attendance.current_outcome,
            'matchId', target_match_id,
            'groupId', target_group_id
          ),
          'attendance-review:' || saved_attendance.id::text
        );
      end if;
    end if;
  end loop;

  event_sequence := nextval('public.pachanga_conduct_sequence');
  update private.pachanga_attendance_closures set
    state = 'closed', revision = revision + 1, server_sequence = event_sequence,
    closed_by = current_user_id, closed_at = clock_timestamp(), updated_at = clock_timestamp()
  where id = closure.id returning * into closure;
  group_state := private.pachanga_bump_attendance_group_v1(target_group_id, target_match_id);
  response := jsonb_build_object(
    'operationId', operation_id,
    'closureId', closure.id,
    'confirmedRevision', closure.revision,
    'serverSequence', event_sequence,
    'groupStateRevision', group_state.revision,
    'state', closure.state,
    'facts', affected,
    'policyVersion', settings.policy_version
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, current_user_id, 'attendance.close', expected_revision,
    closure.revision, event_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.close_pachanga_post_match_attendance_v1(uuid, text, jsonb, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.close_pachanga_post_match_attendance_v1(uuid, text, jsonb, uuid, bigint, jsonb)
  to authenticated;

create or replace function public.respond_pachanga_post_match_attendance_v1(
  target_attendance_id uuid,
  next_response text,
  response_note text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  replay jsonb;
  attendance private.pachanga_post_match_attendance%rowtype;
  saved_review private.pachanga_attendance_reviews%rowtype;
  next_state text;
  event_sequence bigint;
  response jsonb;
  admin_member record;
begin
  if current_user_id is null or operation_id is null or expected_revision is null
    or next_response not in ('agree', 'dispute') then
    raise exception 'Authentication, operation id, revision and valid response required';
  end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.respond', current_user_id);
  if replay is not null then return replay; end if;
  select * into attendance from private.pachanga_post_match_attendance facts
  where facts.id = target_attendance_id for update;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.respond', current_user_id);
  if replay is not null then return replay; end if;
  if not found or attendance.target_user_id <> current_user_id then
    raise exception 'Attendance record not available';
  end if;
  if attendance.revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the attendance record.' using errcode = 'PT409';
  end if;
  if attendance.response_state <> 'pending' then raise exception 'Attendance response already recorded'; end if;
  if attendance.dispute_deadline is null or clock_timestamp() > attendance.dispute_deadline then
    raise exception 'Attendance dispute window expired';
  end if;
  if char_length(coalesce(response_note, '')) > 500 then raise exception 'Response note is too long'; end if;
  next_state := case when next_response = 'agree' then 'agreed' else 'disputed' end;
  event_sequence := nextval('public.pachanga_conduct_sequence');
  update private.pachanga_post_match_attendance set
    response_state = next_state,
    responded_at = clock_timestamp(),
    revision = revision + 1,
    server_sequence = event_sequence,
    updated_at = clock_timestamp()
  where id = attendance.id returning * into attendance;

  if next_response = 'dispute' then
    insert into private.pachanga_attendance_reviews(attendance_id, target_user_id, player_note)
    values (attendance.id, current_user_id, nullif(trim(response_note), ''))
    returning * into saved_review;
    update private.pachanga_post_match_attendance set
      response_state = 'under_review', revision = revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence'), updated_at = clock_timestamp()
    where id = attendance.id returning * into attendance;
    for admin_member in
      select members.user_id from public.pachanga_group_members members
      where members.group_id = attendance.group_id and members.role in ('owner', 'admin')
    loop
      perform private.pachanga_notify_v1(
        admin_member.user_id, 'attendance_warning_disputed', 'Asistencia en revisión',
        attendance.display_name_snapshot || ' no está de acuerdo con el cierre de asistencia.',
        '/admin/conduct?attendanceReview=' || saved_review.id::text,
        jsonb_build_object('attendanceReviewId', saved_review.id, 'reviewRevision', saved_review.revision,
          'groupId', attendance.group_id, 'matchId', attendance.match_id),
        'attendance-dispute:' || saved_review.id::text || ':' || admin_member.user_id::text
      );
    end loop;
  else
    perform private.pachanga_evaluate_attendance_reliability_v1(current_user_id, operation_id);
  end if;

  insert into private.pachanga_attendance_events(
    attendance_id, operation_id, actor_user_id, event_type,
    from_outcome, to_outcome, from_response_state, to_response_state,
    reason, attendance_revision, payload
  ) values (
    attendance.id, operation_id, current_user_id,
    case when next_response = 'agree' then 'attendance_agreed' else 'attendance_disputed' end,
    attendance.current_outcome, attendance.current_outcome, 'pending', attendance.response_state,
    nullif(trim(response_note), ''), attendance.revision,
    jsonb_build_object('affectsSportRating', false, 'automaticSanctionApplied', false)
  );
  perform private.pachanga_bump_conduct_subject_v1(current_user_id);
  perform private.pachanga_bump_attendance_group_v1(attendance.group_id, attendance.match_id);
  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedRevision', attendance.revision,
    'serverSequence', attendance.server_sequence,
    'attendance', private.pachanga_attendance_snapshot_v1(attendance.id)
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, current_user_id, 'attendance.respond', expected_revision,
    attendance.revision, attendance.server_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.respond_pachanga_post_match_attendance_v1(uuid, text, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.respond_pachanga_post_match_attendance_v1(uuid, text, text, uuid, bigint, jsonb)
  to authenticated;

create or replace function public.resolve_pachanga_attendance_review_v1(
  target_review_id uuid,
  next_resolution text,
  corrected_outcome text,
  resolution_note text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  replay jsonb;
  review private.pachanga_attendance_reviews%rowtype;
  attendance private.pachanga_post_match_attendance%rowtype;
  old_outcome text;
  old_response text;
  event_sequence bigint;
  response jsonb;
  target_profile public.pachanga_player_profiles%rowtype;
  saved_case private.pachanga_moderation_cases%rowtype;
begin
  if current_user_id is null or operation_id is null or expected_revision is null
    or next_resolution not in ('maintain', 'correct', 'escalate') then
    raise exception 'Authentication, operation id, revision and valid resolution required';
  end if;
  if char_length(coalesce(resolution_note, '')) > 500 then raise exception 'Resolution note is too long'; end if;
  if next_resolution = 'correct' and corrected_outcome not in ('played', 'excused_absence', 'late_cancellation', 'unexcused_no_show') then
    raise exception 'Corrected outcome required';
  end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.resolve', current_user_id);
  if replay is not null then return replay; end if;
  select * into review from private.pachanga_attendance_reviews reviews
  where reviews.id = target_review_id for update;
  if not found then raise exception 'Attendance review not found'; end if;
  select * into attendance from private.pachanga_post_match_attendance facts
  where facts.id = review.attendance_id for update;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.resolve', current_user_id);
  if replay is not null then return replay; end if;
  if not public.is_pachanga_group_admin(attendance.group_id) then
    raise exception 'Only the certifying team admins can resolve attendance';
  end if;
  if review.revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the attendance review.' using errcode = 'PT409';
  end if;
  if review.state not in ('submitted', 'under_review') then raise exception 'Attendance review already resolved'; end if;
  old_outcome := attendance.current_outcome;
  old_response := attendance.response_state;
  event_sequence := nextval('public.pachanga_conduct_sequence');

  if next_resolution = 'correct' then
    update private.pachanga_post_match_attendance set
      current_outcome = corrected_outcome, response_state = 'corrected',
      revision = revision + 1, server_sequence = event_sequence, updated_at = clock_timestamp()
    where id = attendance.id returning * into attendance;
    update private.pachanga_attendance_reviews set
      state = 'corrected', admin_note = nullif(trim(resolution_note), ''),
      resolved_by = current_user_id, resolved_at = clock_timestamp(),
      revision = revision + 1, server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    where id = review.id returning * into review;
  elsif next_resolution = 'maintain' then
    update private.pachanga_post_match_attendance set
      response_state = 'maintained', revision = revision + 1,
      server_sequence = event_sequence, updated_at = clock_timestamp()
    where id = attendance.id returning * into attendance;
    update private.pachanga_attendance_reviews set
      state = 'maintained', admin_note = nullif(trim(resolution_note), ''),
      resolved_by = current_user_id, resolved_at = clock_timestamp(),
      revision = revision + 1, server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    where id = review.id returning * into review;
    perform private.pachanga_evaluate_attendance_reliability_v1(attendance.target_user_id, operation_id);
  else
    select * into target_profile from public.pachanga_player_profiles profiles
    where profiles.id = attendance.target_profile_id;
    if target_profile.id is null then raise exception 'Registered target profile required for escalation'; end if;
    insert into private.pachanga_moderation_cases(
      target_profile_id, target_user_id, source_type, category, state, priority,
      decision_summary, restriction_recommended
    ) values (
      target_profile.id, attendance.target_user_id, 'attendance_dispute',
      'attendance_reliability', 'under_review', 'high',
      'Disputed attendance escalated for internal moderation.', false
    )
    on conflict (target_profile_id, source_type, category)
      where state not in ('dismissed', 'corrected', 'closed')
    do update set
      state = 'under_review', priority = 'high',
      revision = private.pachanga_moderation_cases.revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence'), updated_at = clock_timestamp()
    returning * into saved_case;
    update private.pachanga_attendance_reviews set
      state = 'escalated', admin_note = nullif(trim(resolution_note), ''),
      resolved_by = current_user_id, resolved_at = clock_timestamp(),
      revision = revision + 1, server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    where id = review.id returning * into review;
    perform private.pachanga_conduct_notify_moderators_v1(
      'conduct_warning_review', 'Conflicto de asistencia escalado',
      'Una asistencia disputada requiere revisión interna.',
      '/admin/conduct?case=' || saved_case.opaque_reference::text,
      jsonb_build_object('caseReference', saved_case.opaque_reference),
      'attendance-escalated:' || saved_case.id::text
    );
  end if;

  insert into private.pachanga_attendance_events(
    attendance_id, operation_id, actor_user_id, event_type,
    from_outcome, to_outcome, from_response_state, to_response_state,
    reason, attendance_revision, payload
  ) values (
    attendance.id, operation_id, current_user_id, 'attendance_review_resolved',
    old_outcome, attendance.current_outcome, old_response, attendance.response_state,
    nullif(trim(resolution_note), ''), attendance.revision,
    jsonb_build_object('resolution', next_resolution, 'affectsSportRating', false, 'automaticSanctionApplied', false)
  );
  perform private.pachanga_bump_conduct_subject_v1(attendance.target_user_id);
  perform private.pachanga_bump_attendance_group_v1(attendance.group_id, attendance.match_id);
  perform private.pachanga_notify_v1(
    attendance.target_user_id,
    case when next_resolution = 'correct' then 'attendance_warning_corrected' else 'attendance_warning_resolved' end,
    case when next_resolution = 'correct' then 'Asistencia corregida' else 'Revisión de asistencia resuelta' end,
    case when next_resolution = 'correct' then 'La asistencia se ha corregido y conserva su historial de auditoría.'
      when next_resolution = 'maintain' then 'La asistencia original se mantiene tras la revisión.'
      else 'La revisión continúa con el equipo de moderación.' end,
    '/perfil/conducta?attendance=' || attendance.id::text,
    jsonb_build_object('attendanceId', attendance.id, 'attendanceRevision', attendance.revision,
      'attendanceOutcome', attendance.current_outcome, 'attendanceResponseState', attendance.response_state),
    'attendance-resolution:' || review.id::text || ':' || review.revision::text
  );
  response := jsonb_build_object(
    'operationId', operation_id, 'confirmedRevision', review.revision,
    'serverSequence', review.server_sequence,
    'attendance', private.pachanga_attendance_snapshot_v1(attendance.id),
    'reviewState', review.state
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, current_user_id, 'attendance.resolve', expected_revision,
    review.revision, review.server_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.resolve_pachanga_attendance_review_v1(uuid, text, text, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.resolve_pachanga_attendance_review_v1(uuid, text, text, text, uuid, bigint, jsonb)
  to authenticated;

create or replace function public.run_pachanga_attendance_dispute_expiry_v1(
  target_now timestamptz default clock_timestamp(),
  target_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  attendance private.pachanga_post_match_attendance%rowtype;
  processed integer := 0;
  operation_id uuid;
begin
  if current_user not in ('postgres', 'service_role') then
    raise exception 'Internal attendance expiry only';
  end if;
  for attendance in
    select * from private.pachanga_post_match_attendance facts
    where facts.response_state = 'pending' and facts.dispute_deadline <= target_now
    order by facts.dispute_deadline, facts.id
    for update skip locked limit greatest(1, least(coalesce(target_limit, 500), 5000))
  loop
    operation_id := gen_random_uuid();
    update private.pachanga_post_match_attendance set
      response_state = 'confirmed_uncontested', revision = revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence'), updated_at = clock_timestamp()
    where id = attendance.id returning * into attendance;
    insert into private.pachanga_attendance_events(
      attendance_id, operation_id, actor_user_id, event_type,
      from_outcome, to_outcome, from_response_state, to_response_state,
      attendance_revision, payload
    ) values (
      attendance.id, operation_id, null, 'attendance_confirmed_uncontested',
      attendance.current_outcome, attendance.current_outcome, 'pending', attendance.response_state,
      attendance.revision,
      jsonb_build_object('automaticSanctionApplied', false, 'affectsSportRating', false)
    );
    perform private.pachanga_evaluate_attendance_reliability_v1(attendance.target_user_id, operation_id);
    perform private.pachanga_bump_conduct_subject_v1(attendance.target_user_id);
    perform private.pachanga_bump_attendance_group_v1(attendance.group_id, attendance.match_id);
    processed := processed + 1;
  end loop;
  return jsonb_build_object('processed', processed, 'serverTime', target_now);
end;
$$;

revoke all on function public.run_pachanga_attendance_dispute_expiry_v1(timestamptz, integer)
  from public, anon, authenticated;
grant execute on function public.run_pachanga_attendance_dispute_expiry_v1(timestamptz, integer)
  to service_role;

create or replace function public.get_pachanga_attendance_admin_v1(
  target_group_id uuid,
  target_match_id text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  closure private.pachanga_attendance_closures%rowtype;
  match_revision bigint;
begin
  if auth.uid() is null or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can review attendance';
  end if;
  select matches.match_version into match_revision
  from public.pachanga_match_read_model matches
  where matches.group_id = target_group_id and matches.match_id = target_match_id;
  if match_revision is null then raise exception 'Match not found'; end if;
  select * into closure from private.pachanga_attendance_closures rows
  where rows.group_id = target_group_id and rows.match_id = target_match_id;
  return jsonb_build_object(
    'groupId', target_group_id,
    'matchId', target_match_id,
    'matchRevision', match_revision,
    'closure', case when closure.id is null then jsonb_build_object('state', 'open', 'revision', 0)
      else jsonb_build_object('id', closure.id, 'state', closure.state, 'revision', closure.revision,
        'serverSequence', closure.server_sequence, 'closedAt', closure.closed_at) end,
    'players', coalesce((
      select jsonb_agg(jsonb_build_object(
        'playerId', participants.player_id,
        'name', identities.display_name,
        'status', participants.status,
        'seatKind', participants.seat_kind,
        'attendance', case when facts.id is null then null else private.pachanga_attendance_snapshot_v1(facts.id) end
      ) order by participants.joined_at nulls last, participants.player_id)
      from public.pachanga_match_participants participants
      left join lateral private.pachanga_group_player_identity_v1(target_group_id, participants.player_id) identities on true
      left join private.pachanga_post_match_attendance facts
        on facts.group_id = participants.group_id and facts.match_id = participants.match_id
        and facts.local_player_id = participants.player_id
      where participants.group_id = target_group_id and participants.match_id = target_match_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_attendance_admin_v1(uuid, text)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_attendance_admin_v1(uuid, text)
  to authenticated;

create or replace function private.pachanga_group_player_id_for_user_v1(
  target_group_id uuid,
  target_user_id uuid
)
returns text
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select players.value ->> 'id'
  from public.pachanga_groups groups
  cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb)) players(value)
  where groups.id = target_group_id
    and players.value ->> 'ownerUserId' = target_user_id::text
  limit 1;
$$;

revoke all on function private.pachanga_group_player_id_for_user_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_validate_conduct_context_v1(
  actor_user_id uuid,
  reporter_group_id uuid,
  target_group_id uuid,
  target_profile_id uuid,
  target_user_id uuid,
  context_kind text,
  context_id text
)
returns bigint
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  context_uuid uuid;
  selected_match public.pachanga_match_read_model%rowtype;
  open_match public.pachanga_open_matches%rowtype;
  guest_access public.pachanga_match_guest_access%rowtype;
  challenge public.pachanga_team_challenges%rowtype;
  external_match public.pachanga_external_matches%rowtype;
  actor_player_id text;
  target_player_id text;
  actor_profile_id uuid;
  actor_valid boolean := false;
  target_valid boolean := false;
begin
  if actor_user_id is null or not exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = reporter_group_id and members.user_id = actor_user_id
  ) then
    raise exception 'Reporter must currently belong to the reporting group';
  end if;

  if context_kind = 'match' then
    if reporter_group_id <> target_group_id then
      raise exception 'A group match report must stay inside its sporting context';
    end if;
    select * into selected_match from public.pachanga_match_read_model matches
    where matches.group_id = target_group_id and matches.match_id = context_id;
    if not found or selected_match.match_state not in ('played', 'finalized', 'historical') then
      raise exception 'A completed match context is required';
    end if;
    actor_player_id := private.pachanga_group_player_id_for_user_v1(reporter_group_id, actor_user_id);
    target_player_id := private.pachanga_group_player_id_for_user_v1(target_group_id, target_user_id);
    actor_valid := public.is_pachanga_group_admin(reporter_group_id) or exists (
      select 1 from public.pachanga_match_participants participants
      where participants.group_id = reporter_group_id and participants.match_id = context_id
        and participants.player_id = actor_player_id and participants.seat_kind = 'playing'
    );
    target_valid := exists (
      select 1 from public.pachanga_match_participants participants
      where participants.group_id = target_group_id and participants.match_id = context_id
        and participants.player_id = target_player_id and participants.seat_kind = 'playing'
    );
    if not actor_valid or not target_valid then
      raise exception 'Reporter and target need a valid sporting relationship';
    end if;
    return greatest(selected_match.match_version, 1);
  end if;

  begin
    context_uuid := context_id::uuid;
  exception when others then
    raise exception 'A canonical context identifier is required';
  end;

  if context_kind = 'challenge' then
    select * into challenge from public.pachanga_team_challenges challenges
    where challenges.id = context_uuid;
    if not found or challenge.status <> 'accepted'
      or reporter_group_id not in (challenge.sender_group_id, challenge.receiver_group_id)
      or target_group_id not in (challenge.sender_group_id, challenge.receiver_group_id)
      or reporter_group_id = target_group_id then
      raise exception 'Accepted rival challenge context required';
    end if;
    select * into external_match from public.pachanga_external_matches matches
    where matches.challenge_id = challenge.id;
    if not found or external_match.official_version is null
      or external_match.state not in ('confirmed', 'auto_confirmed') then
      raise exception 'A completed shared match is required';
    end if;
    select profiles.id into actor_profile_id from public.pachanga_player_profiles profiles
    where profiles.user_id = actor_user_id;
    actor_valid := public.is_pachanga_group_admin(reporter_group_id) or exists (
      select 1 from public.pachanga_external_match_participants participants
      where participants.external_match_id = external_match.id
        and participants.result_version = external_match.official_version
        and participants.group_id = reporter_group_id
        and participants.player_profile_id = actor_profile_id
    );
    target_valid := exists (
      select 1 from public.pachanga_external_match_participants participants
      where participants.external_match_id = external_match.id
        and participants.result_version = external_match.official_version
        and participants.group_id = target_group_id
        and participants.player_profile_id = target_profile_id
    );
    if not actor_valid or not target_valid then
      raise exception 'Reporter and target need a valid rival-match relationship';
    end if;
    return greatest(challenge.revision, external_match.revision, 1);
  elsif context_kind = 'open_match' then
    select * into open_match from public.pachanga_open_matches matches where matches.id = context_uuid;
    if not found or open_match.source_group_id <> target_group_id then
      raise exception 'Open match context not found';
    end if;
    select * into selected_match from public.pachanga_match_read_model matches
    where matches.group_id = open_match.source_group_id and matches.match_id = open_match.source_match_id;
    if not found or selected_match.match_state not in ('played', 'finalized', 'historical') then
      raise exception 'A completed open match is required';
    end if;
    actor_player_id := private.pachanga_group_player_id_for_user_v1(open_match.source_group_id, actor_user_id);
    target_player_id := private.pachanga_group_player_id_for_user_v1(open_match.source_group_id, target_user_id);
    actor_valid := public.is_pachanga_group_admin(open_match.source_group_id)
      or exists (
        select 1 from public.pachanga_match_participants participants
        where participants.group_id = open_match.source_group_id
          and participants.match_id = open_match.source_match_id
          and participants.player_id = actor_player_id and participants.seat_kind = 'playing'
      ) or exists (
        select 1 from public.pachanga_match_guest_access access
        where access.group_id = open_match.source_group_id and access.match_id = open_match.source_match_id
          and access.guest_user_id = actor_user_id
      );
    target_valid := exists (
      select 1 from public.pachanga_match_participants participants
      where participants.group_id = open_match.source_group_id
        and participants.match_id = open_match.source_match_id
        and participants.player_id = target_player_id and participants.seat_kind = 'playing'
    ) or exists (
      select 1 from public.pachanga_match_guest_access access
      where access.group_id = open_match.source_group_id and access.match_id = open_match.source_match_id
        and access.guest_user_id = target_user_id
    );
    if not actor_valid or not target_valid then
      raise exception 'Reporter and target need a valid open-match relationship';
    end if;
    return greatest(selected_match.match_version, open_match.source_payload_revision, 1);
  elsif context_kind = 'guest_participation' then
    select * into guest_access from public.pachanga_match_guest_access access where access.id = context_uuid;
    if not found or guest_access.group_id <> target_group_id then
      raise exception 'Guest participation context not found';
    end if;
    select * into selected_match from public.pachanga_match_read_model matches
    where matches.group_id = guest_access.group_id and matches.match_id = guest_access.match_id;
    if not found or selected_match.match_state not in ('played', 'finalized', 'historical') then
      raise exception 'A completed guest match is required';
    end if;
    actor_player_id := private.pachanga_group_player_id_for_user_v1(guest_access.group_id, actor_user_id);
    target_player_id := private.pachanga_group_player_id_for_user_v1(guest_access.group_id, target_user_id);
    actor_valid := actor_user_id = guest_access.guest_user_id
      or public.is_pachanga_group_admin(guest_access.group_id)
      or exists (
        select 1 from public.pachanga_match_participants participants
        where participants.group_id = guest_access.group_id and participants.match_id = guest_access.match_id
          and participants.player_id = actor_player_id and participants.seat_kind = 'playing'
      );
    target_valid := target_user_id = guest_access.guest_user_id or exists (
      select 1 from public.pachanga_match_participants participants
      where participants.group_id = guest_access.group_id and participants.match_id = guest_access.match_id
        and participants.player_id = target_player_id and participants.seat_kind = 'playing'
    );
    if not actor_valid or not target_valid then
      raise exception 'Reporter and target need a valid guest-participation relationship';
    end if;
    return greatest(selected_match.match_version, guest_access.revision, 1);
  end if;
  raise exception 'Unsupported conduct context';
end;
$$;

revoke all on function private.pachanga_validate_conduct_context_v1(uuid, uuid, uuid, uuid, uuid, text, text)
  from public, anon, authenticated;

create or replace function public.submit_pachanga_conduct_report_v1(
  target_profile_id uuid,
  reporter_group_id uuid,
  target_group_id uuid,
  context_kind text,
  context_id text,
  category text,
  description text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  v_target_profile_id uuid := target_profile_id;
  v_reporter_group_id uuid := reporter_group_id;
  v_target_group_id uuid := target_group_id;
  v_context_kind text := context_kind;
  v_context_id text := context_id;
  v_category text := category;
  v_description text := description;
  v_operation_id uuid := operation_id;
  replay jsonb;
  settings private.pachanga_conduct_settings%rowtype;
  target_profile public.pachanga_player_profiles%rowtype;
  canonical_context_revision bigint;
  saved_case private.pachanga_moderation_cases%rowtype;
  saved_cluster private.pachanga_report_source_clusters%rowtype;
  saved_report private.pachanga_conduct_reports%rowtype;
  v_report_count integer;
  v_cluster_count integer;
  v_independent_count integer;
  reciprocal boolean;
  event_sequence bigint;
  response jsonb;
begin
  if current_user_id is null or v_operation_id is null or expected_revision is null
    or nullif(trim(v_context_id), '') is null then
    raise exception 'Authentication, operation id, context and revision required';
  end if;
  if v_context_kind not in ('match', 'challenge', 'open_match', 'guest_participation')
    or v_category not in (
      'abusive_behavior', 'harassment', 'threats_or_violence', 'discriminatory_behavior',
      'deliberate_cheating', 'repeated_disruption', 'other'
    ) then raise exception 'Invalid report context or category'; end if;
  if char_length(coalesce(v_description, '')) > 500 then raise exception 'Report description is too long'; end if;
  replay := private.pachanga_conduct_replay_v1(v_operation_id, 'conduct.report', current_user_id);
  if replay is not null then return replay; end if;
  if not public.is_registered_pachanga_user() then raise exception 'Registered reporter required'; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  if not settings.conduct_reports_enabled then raise exception 'Conduct reports are not enabled'; end if;
  select * into target_profile from public.pachanga_player_profiles profiles where profiles.id = v_target_profile_id;
  if not found or target_profile.user_id is null then raise exception 'Registered target profile required'; end if;
  if target_profile.user_id = current_user_id then raise exception 'Self-reporting is not allowed'; end if;

  canonical_context_revision := private.pachanga_validate_conduct_context_v1(
    current_user_id, v_reporter_group_id, v_target_group_id, target_profile.id,
    target_profile.user_id, v_context_kind, v_context_id
  );
  if canonical_context_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the sporting context.' using errcode = 'PT409';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_profile.id::text || ':' || category, 709));
  replay := private.pachanga_conduct_replay_v1(v_operation_id, 'conduct.report', current_user_id);
  if replay is not null then return replay; end if;

  if exists (
    select 1 from private.pachanga_conduct_reports reports
    where reports.reporter_user_id = current_user_id and reports.target_profile_id = target_profile.id
      and reports.context_kind = v_context_kind
      and reports.context_id = v_context_id
      and reports.category = v_category
  ) then raise exception 'This report already exists' using errcode = '23505'; end if;

  reciprocal := exists (
    select 1 from private.pachanga_conduct_reports reports
    where reports.reporter_user_id = target_profile.user_id
      and reports.target_user_id = current_user_id
      and reports.created_at >= clock_timestamp() - interval '14 days'
  );
  select * into saved_case from private.pachanga_moderation_cases cases
  where cases.target_profile_id = target_profile.id
    and cases.source_type = 'conduct_report'
    and cases.category = v_category
    and cases.state not in ('dismissed', 'corrected', 'closed')
  for update;
  if not found then
    insert into private.pachanga_moderation_cases(
      target_profile_id, target_user_id, source_type, category, state, priority, mutual_retaliation
    ) values (
      target_profile.id, target_profile.user_id, 'conduct_report', v_category, 'submitted',
      case when v_category = 'threats_or_violence' then 'urgent_review' else 'normal' end,
      reciprocal
    ) returning * into saved_case;
  else
    update private.pachanga_moderation_cases cases set
      last_reported_at = clock_timestamp(),
      mutual_retaliation = cases.mutual_retaliation or reciprocal,
      priority = case when v_category = 'threats_or_violence' then 'urgent_review' else cases.priority end,
      revision = cases.revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    where cases.id = saved_case.id returning * into saved_case;
  end if;

  select * into saved_cluster from private.pachanga_report_source_clusters clusters
  where clusters.case_id = saved_case.id
    and clusters.source_group_id = v_reporter_group_id
    and clusters.context_kind = v_context_kind
    and clusters.context_id = v_context_id
  for update;
  if not found then
    insert into private.pachanga_report_source_clusters(
      case_id, source_group_id, context_kind, context_id, report_count
    ) values (saved_case.id, v_reporter_group_id, v_context_kind, v_context_id, 1)
    returning * into saved_cluster;
  else
    update private.pachanga_report_source_clusters clusters set
      report_count = clusters.report_count + 1,
      last_reported_at = clock_timestamp()
    where clusters.id = saved_cluster.id returning * into saved_cluster;
  end if;

  insert into private.pachanga_conduct_reports(
    case_id, source_cluster_id, reporter_user_id, reporter_group_id,
    target_profile_id, target_user_id, target_group_id, context_kind,
    context_id, context_revision, category, description, operation_id
  ) values (
    saved_case.id, saved_cluster.id, current_user_id, reporter_group_id,
    target_profile.id, target_profile.user_id, v_target_group_id, v_context_kind,
    v_context_id, canonical_context_revision, v_category,
    nullif(trim(v_description), ''), v_operation_id
  ) returning * into saved_report;

  select count(*), count(distinct reports.reporter_group_id)
  into v_report_count, v_independent_count
  from private.pachanga_conduct_reports reports
  where reports.case_id = saved_case.id and reports.state = 'active';
  select count(*) into v_cluster_count
  from private.pachanga_report_source_clusters clusters where clusters.case_id = saved_case.id;
  event_sequence := nextval('public.pachanga_conduct_sequence');
  update private.pachanga_moderation_cases set
    state = case when v_report_count > 1 then 'clustered' else private.pachanga_moderation_cases.state end,
    report_count = v_report_count,
    source_cluster_count = v_cluster_count,
    independent_source_count = v_independent_count,
    correlated_source_count = greatest(v_report_count - v_independent_count, 0),
    correlated_reporting = v_report_count > v_independent_count,
    revision = revision + 1,
    server_sequence = event_sequence,
    last_reported_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where id = saved_case.id returning * into saved_case;

  insert into private.pachanga_moderation_events(
    case_id, operation_id, actor_user_id, event_type, from_state, to_state,
    case_revision, payload
  ) values (
    saved_case.id, v_operation_id, current_user_id, 'conduct_report_received',
    null, saved_case.state, saved_case.revision,
    jsonb_build_object(
      'reportReference', saved_report.opaque_reference,
      'sourceClusterReference', saved_cluster.opaque_reference,
      'contextKind', v_context_kind,
      'contextRevision', canonical_context_revision,
      'independentSourceCount', v_independent_count,
      'correlatedSourceCount', greatest(v_report_count - v_independent_count, 0),
      'automaticRestrictionApplied', false,
      'affectsSportRating', false
    )
  );
  perform private.pachanga_conduct_notify_moderators_v1(
    case when saved_case.priority = 'urgent_review' then 'conduct_warning_urgent_review' else 'conduct_warning_review' end,
    case when saved_case.priority = 'urgent_review' then 'Revisión urgente de conducta' else 'Nuevo caso de conducta' end,
    'Un reporte privado requiere revisión humana.',
    '/admin/conduct?case=' || saved_case.opaque_reference::text,
      jsonb_build_object('caseReference', saved_case.opaque_reference, 'priority', saved_case.priority,
      'reportCount', v_report_count, 'independentSourceCount', v_independent_count),
    'conduct-report:' || saved_report.id::text
  );
  response := jsonb_build_object(
    'operationId', v_operation_id,
    'reportReference', saved_report.opaque_reference,
    'confirmedRevision', saved_case.revision,
    'serverSequence', event_sequence,
    'state', 'received',
    'automaticRestrictionApplied', false,
    'affectsSportRating', false
  );
  return private.pachanga_conduct_save_receipt_v1(
    v_operation_id, current_user_id, 'conduct.report', expected_revision,
    saved_case.revision, event_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.submit_pachanga_conduct_report_v1(uuid, uuid, uuid, text, text, text, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.submit_pachanga_conduct_report_v1(uuid, uuid, uuid, text, text, text, text, uuid, bigint, jsonb)
  to authenticated;

create or replace function private.pachanga_expire_social_restrictions_v1(target_user_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  expired_count integer;
  v_target_user_id uuid := target_user_id;
begin
  update private.pachanga_social_restrictions restrictions set
    state = 'expired', ended_at = clock_timestamp(), revision = revision + 1,
    server_sequence = nextval('public.pachanga_conduct_sequence')
  where restrictions.state = 'active'
    and restrictions.effective_until is not null
    and restrictions.effective_until <= clock_timestamp()
    and (v_target_user_id is null or restrictions.target_user_id = v_target_user_id);
  get diagnostics expired_count = row_count;
  if v_target_user_id is not null and expired_count > 0 then
    perform private.pachanga_bump_conduct_subject_v1(v_target_user_id);
  end if;
  return expired_count;
end;
$$;

revoke all on function private.pachanga_expire_social_restrictions_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_has_active_social_restriction_v1(
  target_user_id uuid,
  target_restriction_type text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  settings private.pachanga_conduct_settings%rowtype;
  v_target_user_id uuid := target_user_id;
  v_target_restriction_type text := target_restriction_type;
begin
  select * into settings from private.pachanga_conduct_settings where singleton;
  if not settings.social_restrictions_enabled then return false; end if;
  perform private.pachanga_expire_social_restrictions_v1(v_target_user_id);
  return exists (
    select 1 from private.pachanga_social_restrictions restrictions
    where restrictions.target_user_id = v_target_user_id
      and restrictions.restriction_type = v_target_restriction_type
      and restrictions.state = 'active'
      and (restrictions.effective_until is null or restrictions.effective_until > clock_timestamp())
  );
end;
$$;

revoke all on function private.pachanga_has_active_social_restriction_v1(uuid, text)
  from public, anon, authenticated;

create or replace function public.get_pachanga_social_action_gate_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare current_user_id uuid := auth.uid();
declare settings private.pachanga_conduct_settings%rowtype;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  perform private.pachanga_expire_social_restrictions_v1(current_user_id);
  return jsonb_build_object(
    'policyVersion', settings.policy_version,
    'socialRestrictionsEnabled', settings.social_restrictions_enabled,
    'blocked', coalesce((
      select jsonb_object_agg(restrictions.restriction_type, true)
      from private.pachanga_social_restrictions restrictions
      where restrictions.target_user_id = current_user_id and restrictions.state = 'active'
        and (restrictions.effective_until is null or restrictions.effective_until > clock_timestamp())
    ), '{}'::jsonb),
    'serverTime', clock_timestamp()
  );
end;
$$;

revoke all on function public.get_pachanga_social_action_gate_v1() from public, anon, authenticated;
grant execute on function public.get_pachanga_social_action_gate_v1() to authenticated;

create or replace function private.pachanga_enforce_open_request_social_gate_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'INSERT' and (
    private.pachanga_has_active_social_restriction_v1(new.requester_user_id, 'public_match_access')
    or private.pachanga_has_active_social_restriction_v1(new.requester_user_id, 'public_guest_access')
  ) then raise exception 'SOCIAL_ACTION_RESTRICTED: public match access'; end if;
  return new;
end;
$$;

revoke all on function private.pachanga_enforce_open_request_social_gate_v1()
  from public, anon, authenticated;
drop trigger if exists pachanga_open_request_social_gate_v1 on public.pachanga_open_match_requests;
create trigger pachanga_open_request_social_gate_v1
before insert on public.pachanga_open_match_requests
for each row execute function private.pachanga_enforce_open_request_social_gate_v1();

create or replace function private.pachanga_enforce_challenge_social_gate_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'INSERT' and private.pachanga_has_active_social_restriction_v1(new.created_by, 'send_challenges') then
    raise exception 'SOCIAL_ACTION_RESTRICTED: send challenges';
  end if;
  if tg_op = 'UPDATE'
    and new.status is distinct from old.status
    and new.status in ('accepted', 'changes_proposed')
    and (
      exists (
        select 1 from public.pachanga_groups groups
        where groups.id = new.receiver_group_id and groups.owner_id = new.updated_by
      )
      or exists (
        select 1 from public.pachanga_group_members members
        where members.group_id = new.receiver_group_id and members.user_id = new.updated_by
          and members.role in ('owner', 'admin')
      )
    )
    and private.pachanga_has_active_social_restriction_v1(new.updated_by, 'receive_public_challenges')
  then
    raise exception 'SOCIAL_ACTION_RESTRICTED: receive public challenges';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_enforce_challenge_social_gate_v1()
  from public, anon, authenticated;
drop trigger if exists pachanga_team_challenge_social_gate_v1 on public.pachanga_team_challenges;
create trigger pachanga_team_challenge_social_gate_v1
before insert or update on public.pachanga_team_challenges
for each row execute function private.pachanga_enforce_challenge_social_gate_v1();

create or replace function private.pachanga_enforce_guest_access_social_gate_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.status = 'accepted'
    and (tg_op = 'INSERT' or old.status is distinct from new.status)
    and private.pachanga_has_active_social_restriction_v1(new.guest_user_id, 'public_guest_access')
  then
    raise exception 'SOCIAL_ACTION_RESTRICTED: public guest access';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_enforce_guest_access_social_gate_v1()
  from public, anon, authenticated;
drop trigger if exists pachanga_guest_access_social_gate_v1 on public.pachanga_match_guest_access;
create trigger pachanga_guest_access_social_gate_v1
before insert or update of status on public.pachanga_match_guest_access
for each row execute function private.pachanga_enforce_guest_access_social_gate_v1();

create or replace function private.pachanga_enforce_market_profile_social_gate_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if private.pachanga_has_active_social_restriction_v1(new.user_id, 'public_market') then
    new.active := false;
    new.open_to_guest := false;
    new.open_to_group := false;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_enforce_market_profile_social_gate_v1()
  from public, anon, authenticated;
drop trigger if exists pachanga_market_profile_social_gate_v1 on public.pachanga_market_profiles;
create trigger pachanga_market_profile_social_gate_v1
before insert or update on public.pachanga_market_profiles
for each row execute function private.pachanga_enforce_market_profile_social_gate_v1();

create or replace function public.get_pachanga_my_conduct_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare current_user_id uuid := auth.uid();
declare settings private.pachanga_conduct_settings%rowtype;
begin
  if current_user_id is null then raise exception 'Authentication required'; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  return jsonb_build_object(
    'policyVersion', settings.policy_version,
    'revision', coalesce((select states.revision from public.pachanga_conduct_subject_state states
      where states.user_id = current_user_id), 0),
    'attendance', coalesce((
      select jsonb_agg(private.pachanga_attendance_snapshot_v1(rows.id)
        order by rows.server_sequence desc, rows.id desc)
      from private.pachanga_post_match_attendance rows
      where rows.target_user_id = current_user_id
    ), '[]'::jsonb),
    'warnings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reference', warnings.opaque_reference, 'category', warnings.category,
        'state', warnings.state, 'issuedAt', warnings.issued_at,
        'effectiveUntil', warnings.effective_until, 'revision', warnings.revision,
        'serverSequence', warnings.server_sequence
      ) order by warnings.server_sequence desc, warnings.id desc)
      from private.pachanga_conduct_warnings warnings
      where warnings.target_user_id = current_user_id
    ), '[]'::jsonb),
    'restrictions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reference', restrictions.opaque_reference, 'type', restrictions.restriction_type,
        'state', restrictions.state, 'appliedAt', restrictions.applied_at,
        'effectiveUntil', restrictions.effective_until, 'revision', restrictions.revision,
        'serverSequence', restrictions.server_sequence
      ) order by restrictions.server_sequence desc, restrictions.id desc)
      from private.pachanga_social_restrictions restrictions
      where restrictions.target_user_id = current_user_id
    ), '[]'::jsonb),
    'appeals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reference', appeals.opaque_reference, 'actionKind', appeals.action_kind,
        'state', appeals.state, 'createdAt', appeals.created_at,
        'resolvedAt', appeals.resolved_at, 'revision', appeals.revision
      ) order by appeals.server_sequence desc, appeals.id desc)
      from private.pachanga_conduct_appeals appeals
      where appeals.target_user_id = current_user_id
    ), '[]'::jsonb),
    'submittedReports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reference', reports.opaque_reference, 'category', reports.category,
        'contextKind', reports.context_kind, 'contextId', reports.context_id,
        'state', reports.state, 'createdAt', reports.created_at
      ) order by reports.server_sequence desc, reports.id desc)
      from private.pachanga_conduct_reports reports
      where reports.reporter_user_id = current_user_id
    ), '[]'::jsonb),
    'privacy', jsonb_build_object(
      'reportsArePrivate', true,
      'reporterIdentityVisibleToTarget', false,
      'affectsSportRating', false
    )
  );
end;
$$;

revoke all on function public.get_pachanga_my_conduct_v1() from public, anon, authenticated;
grant execute on function public.get_pachanga_my_conduct_v1() to authenticated;

create or replace function public.get_pachanga_moderation_queue_v1(target_limit integer default 100)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
begin
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'caseReference', cases.opaque_reference,
      'targetProfileId', cases.target_profile_id,
      'targetName', profiles.display_name,
      'sourceType', cases.source_type,
      'category', cases.category,
      'state', cases.state,
      'priority', cases.priority,
      'reportCount', cases.report_count,
      'sourceClusterCount', cases.source_cluster_count,
      'independentSourceCount', cases.independent_source_count,
      'correlatedSourceCount', cases.correlated_source_count,
      'correlatedReporting', cases.correlated_reporting,
      'mutualRetaliation', cases.mutual_retaliation,
      'restrictionRecommended', cases.restriction_recommended,
      'revision', cases.revision,
      'serverSequence', cases.server_sequence,
      'updatedAt', cases.updated_at
    ) order by
      case cases.priority when 'urgent_review' then 0 when 'high' then 1 else 2 end,
      cases.server_sequence, cases.id)
    from (
      select rows.* from private.pachanga_moderation_cases rows
      where rows.state not in ('dismissed', 'corrected', 'closed')
      order by case rows.priority when 'urgent_review' then 0 when 'high' then 1 else 2 end,
        rows.server_sequence, rows.id
      limit greatest(1, least(target_limit, 500))
    ) cases
    join public.pachanga_player_profiles profiles on profiles.id = cases.target_profile_id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.get_pachanga_moderation_queue_v1(integer) from public, anon, authenticated;
grant execute on function public.get_pachanga_moderation_queue_v1(integer) to authenticated;

create or replace function public.get_pachanga_moderation_case_evidence_v1(target_case_reference uuid)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare selected_case private.pachanga_moderation_cases%rowtype;
begin
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  select * into selected_case from private.pachanga_moderation_cases cases
  where cases.opaque_reference = target_case_reference;
  if not found then raise exception 'Moderation case not found'; end if;
  return jsonb_build_object(
    'caseReference', selected_case.opaque_reference,
    'targetProfileId', selected_case.target_profile_id,
    'targetUserId', selected_case.target_user_id,
    'category', selected_case.category,
    'state', selected_case.state,
    'priority', selected_case.priority,
    'revision', selected_case.revision,
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'reportReference', reports.opaque_reference,
        'reporterUserId', reports.reporter_user_id,
        'reporterGroupId', reports.reporter_group_id,
        'sourceClusterReference', clusters.opaque_reference,
        'contextKind', reports.context_kind,
        'contextId', reports.context_id,
        'contextRevision', reports.context_revision,
        'category', reports.category,
        'description', reports.description,
        'state', reports.state,
        'createdAt', reports.created_at,
        'serverSequence', reports.server_sequence
      ) order by reports.server_sequence, reports.id)
      from private.pachanga_conduct_reports reports
      join private.pachanga_report_source_clusters clusters on clusters.id = reports.source_cluster_id
      where reports.case_id = selected_case.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', events.event_type, 'fromState', events.from_state,
        'toState', events.to_state, 'revision', events.case_revision,
        'payload', events.payload, 'serverSequence', events.server_sequence,
        'createdAt', events.created_at
      ) order by events.server_sequence, events.id)
      from private.pachanga_moderation_events events where events.case_id = selected_case.id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_moderation_case_evidence_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_moderation_case_evidence_v1(uuid)
  to authenticated;

create or replace function public.moderate_pachanga_conduct_case_v1(
  target_case_reference uuid,
  next_action text,
  decision_note text,
  restriction_types text[] default '{}',
  duration_days integer default null,
  operation_id uuid default null,
  expected_revision bigint default null,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  replay jsonb;
  settings private.pachanga_conduct_settings%rowtype;
  selected_case private.pachanga_moderation_cases%rowtype;
  old_state text;
  next_state text;
  v_restriction_type text;
  saved_warning private.pachanga_conduct_warnings%rowtype;
  saved_restriction private.pachanga_social_restrictions%rowtype;
  action_references jsonb := '[]'::jsonb;
  event_sequence bigint;
  response jsonb;
begin
  if current_user_id is null or operation_id is null or expected_revision is null
    or next_action not in ('start_review', 'confirm', 'dismiss', 'issue_warning', 'apply_restrictions', 'correct', 'close') then
    raise exception 'Moderator, operation id, revision and valid action required';
  end if;
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  if char_length(coalesce(decision_note, '')) > 500 then raise exception 'Decision note is too long'; end if;
  if next_action in ('confirm', 'dismiss', 'issue_warning', 'apply_restrictions', 'correct')
    and nullif(trim(decision_note), '') is null then
    raise exception 'A moderation reason is required';
  end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.moderate', current_user_id);
  if replay is not null then return replay; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  select * into selected_case from private.pachanga_moderation_cases cases
  where cases.opaque_reference = target_case_reference for update;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.moderate', current_user_id);
  if replay is not null then return replay; end if;
  if not found then raise exception 'Moderation case not found'; end if;
  if selected_case.revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the moderation case.' using errcode = 'PT409';
  end if;
  old_state := selected_case.state;

  if next_action = 'start_review' then
    next_state := 'under_review';
  elsif next_action = 'confirm' then
    next_state := 'confirmed';
  elsif next_action = 'dismiss' then
    next_state := 'dismissed';
  elsif next_action = 'issue_warning' then
    if selected_case.state not in ('confirmed', 'warned', 'restricted', 'upheld') then
      raise exception 'A warning requires a confirmed case';
    end if;
    insert into private.pachanga_conduct_warnings(
      case_id, target_user_id, category, issued_by
    ) values (
      selected_case.id, selected_case.target_user_id, selected_case.category, current_user_id
    ) returning * into saved_warning;
    action_references := action_references || jsonb_build_array(jsonb_build_object(
      'kind', 'warning', 'reference', saved_warning.opaque_reference,
      'revision', saved_warning.revision
    ));
    next_state := 'warned';
  elsif next_action = 'apply_restrictions' then
    if not settings.social_restrictions_enabled then
      raise exception 'Social restrictions are not enabled';
    end if;
    if selected_case.state not in ('confirmed', 'warned', 'restricted', 'upheld') then
      raise exception 'Restrictions require a confirmed case';
    end if;
    if coalesce(array_length(restriction_types, 1), 0) = 0
      or exists (
        select 1 from unnest(restriction_types) values_list(value)
        where value not in ('public_market', 'send_challenges', 'receive_public_challenges', 'public_match_access', 'public_guest_access')
      ) then raise exception 'At least one valid social restriction is required'; end if;
    if duration_days is not null and duration_days not in (7, 30, 90) then
      raise exception 'Restriction duration must be 7, 30, 90 days or indefinite';
    end if;
    foreach v_restriction_type in array restriction_types loop
      if exists (
        select 1 from private.pachanga_social_restrictions restrictions
        where restrictions.target_user_id = selected_case.target_user_id
          and restrictions.restriction_type = v_restriction_type
          and restrictions.state = 'active'
          and (restrictions.effective_until is null or restrictions.effective_until > clock_timestamp())
      ) then raise exception 'An active restriction of this type already exists'; end if;
      insert into private.pachanga_social_restrictions(
        case_id, target_user_id, restriction_type, duration_days,
        effective_until, applied_by
      ) values (
        selected_case.id, selected_case.target_user_id, v_restriction_type, duration_days,
        case when duration_days is null then null else clock_timestamp() + make_interval(days => duration_days) end,
        current_user_id
      ) returning * into saved_restriction;
      action_references := action_references || jsonb_build_array(jsonb_build_object(
        'kind', 'restriction', 'type', saved_restriction.restriction_type,
        'reference', saved_restriction.opaque_reference,
        'revision', saved_restriction.revision,
        'effectiveUntil', saved_restriction.effective_until
      ));
    end loop;
    next_state := 'restricted';
  elsif next_action = 'correct' then
    update private.pachanga_conduct_warnings warnings set
      state = 'corrected', revision = revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence')
    where warnings.case_id = selected_case.id and warnings.state in ('active', 'appealed');
    update private.pachanga_social_restrictions restrictions set
      state = 'corrected', ended_at = clock_timestamp(), revision = revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence')
    where restrictions.case_id = selected_case.id and restrictions.state in ('active', 'appealed');
    next_state := 'corrected';
  else
    next_state := 'closed';
  end if;

  event_sequence := nextval('public.pachanga_conduct_sequence');
  update private.pachanga_moderation_cases set
    state = next_state,
    decision_summary = coalesce(nullif(trim(decision_note), ''), decision_summary),
    assigned_moderator_user_id = current_user_id,
    resolved_at = case when next_state in ('dismissed', 'corrected', 'closed') then clock_timestamp() else resolved_at end,
    revision = revision + 1,
    server_sequence = event_sequence,
    updated_at = clock_timestamp()
  where id = selected_case.id returning * into selected_case;

  insert into private.pachanga_moderation_events(
    case_id, operation_id, actor_user_id, event_type, from_state, to_state,
    case_revision, payload
  ) values (
    selected_case.id, operation_id, current_user_id, 'moderation_' || next_action,
    old_state, selected_case.state, selected_case.revision,
    jsonb_build_object(
      'decisionNote', nullif(trim(decision_note), ''),
      'actions', action_references,
      'automaticRestrictionApplied', false,
      'affectsSportRating', false
    )
  );
  if next_action in ('issue_warning', 'apply_restrictions', 'correct', 'dismiss') then
    perform private.pachanga_notify_v1(
      selected_case.target_user_id,
      case when next_action = 'apply_restrictions' then 'conduct_sanction_applied'
        when next_action = 'correct' then 'conduct_warning_corrected'
        else 'conduct_warning_moderation' end,
      case when next_action = 'apply_restrictions' then 'Medida social aplicada'
        when next_action = 'correct' then 'Medida de conducta corregida'
        when next_action = 'dismiss' then 'Revisión de conducta cerrada'
        else 'Aviso de conducta' end,
      case when next_action = 'apply_restrictions' then 'Se ha aplicado una limitación temporal a funciones sociales. Puedes revisarla y apelar.'
        when next_action = 'correct' then 'La decisión anterior se ha corregido y conserva su historial de auditoría.'
        when next_action = 'dismiss' then 'La revisión se ha cerrado sin medida social.'
        else 'Tienes un aviso administrativo que debes revisar.' end,
      '/perfil/conducta?case=' || selected_case.opaque_reference::text,
      jsonb_build_object('caseReference', selected_case.opaque_reference,
        'caseRevision', selected_case.revision, 'actions', action_references,
        'mandatory', true, 'affectsSportRating', false),
      'conduct-decision:' || selected_case.id::text || ':' || selected_case.revision::text
    );
  end if;
  perform private.pachanga_bump_conduct_subject_v1(selected_case.target_user_id);
  response := jsonb_build_object(
    'operationId', operation_id,
    'caseReference', selected_case.opaque_reference,
    'state', selected_case.state,
    'confirmedRevision', selected_case.revision,
    'serverSequence', event_sequence,
    'actions', action_references,
    'automaticRestrictionApplied', false,
    'affectsSportRating', false
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, current_user_id, 'conduct.moderate', expected_revision,
    selected_case.revision, event_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.moderate_pachanga_conduct_case_v1(uuid, text, text, text[], integer, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.moderate_pachanga_conduct_case_v1(uuid, text, text, text[], integer, uuid, bigint, jsonb)
  to authenticated;

create or replace function public.appeal_pachanga_conduct_action_v1(
  action_reference uuid,
  action_kind text,
  explanation text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  replay jsonb;
  selected_warning private.pachanga_conduct_warnings%rowtype;
  selected_restriction private.pachanga_social_restrictions%rowtype;
  saved_appeal private.pachanga_conduct_appeals%rowtype;
  selected_case private.pachanga_moderation_cases%rowtype;
  event_sequence bigint;
  response jsonb;
begin
  if current_user_id is null or operation_id is null or expected_revision is null
    or action_kind not in ('warning', 'restriction')
    or char_length(trim(coalesce(explanation, ''))) not between 1 and 500 then
    raise exception 'Authentication, action, explanation, operation id and revision required';
  end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.appeal', current_user_id);
  if replay is not null then return replay; end if;
  if action_kind = 'warning' then
    select * into selected_warning from private.pachanga_conduct_warnings warnings
    where warnings.opaque_reference = action_reference for update;
    replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.appeal', current_user_id);
    if replay is not null then return replay; end if;
    if not found or selected_warning.target_user_id <> current_user_id then raise exception 'Warning not available'; end if;
    if selected_warning.revision <> expected_revision or selected_warning.state <> 'active' then
      raise exception 'Warning changed. Reload before appealing.' using errcode = 'PT409';
    end if;
    select * into selected_case from private.pachanga_moderation_cases cases where cases.id = selected_warning.case_id for update;
    update private.pachanga_conduct_warnings set state = 'appealed', revision = revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence')
    where id = selected_warning.id returning * into selected_warning;
    insert into private.pachanga_conduct_appeals(case_id, target_user_id, action_kind, warning_id, explanation)
    values (selected_case.id, current_user_id, action_kind, selected_warning.id, trim(explanation))
    returning * into saved_appeal;
  else
    select * into selected_restriction from private.pachanga_social_restrictions restrictions
    where restrictions.opaque_reference = action_reference for update;
    replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.appeal', current_user_id);
    if replay is not null then return replay; end if;
    if not found or selected_restriction.target_user_id <> current_user_id then raise exception 'Restriction not available'; end if;
    if selected_restriction.revision <> expected_revision or selected_restriction.state <> 'active' then
      raise exception 'Restriction changed. Reload before appealing.' using errcode = 'PT409';
    end if;
    select * into selected_case from private.pachanga_moderation_cases cases where cases.id = selected_restriction.case_id for update;
    update private.pachanga_social_restrictions set state = 'appealed', revision = revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence')
    where id = selected_restriction.id returning * into selected_restriction;
    insert into private.pachanga_conduct_appeals(case_id, target_user_id, action_kind, restriction_id, explanation)
    values (selected_case.id, current_user_id, action_kind, selected_restriction.id, trim(explanation))
    returning * into saved_appeal;
  end if;
  event_sequence := nextval('public.pachanga_conduct_sequence');
  update private.pachanga_moderation_cases set
    state = 'appealed', revision = revision + 1, server_sequence = event_sequence,
    updated_at = clock_timestamp()
  where id = selected_case.id returning * into selected_case;
  insert into private.pachanga_moderation_events(
    case_id, operation_id, actor_user_id, event_type, from_state, to_state, case_revision, payload
  ) values (
    selected_case.id, operation_id, current_user_id, 'conduct_appeal_submitted',
    null, selected_case.state, selected_case.revision,
    jsonb_build_object('appealReference', saved_appeal.opaque_reference,
      'actionKind', action_kind, 'affectsSportRating', false)
  );
  perform private.pachanga_conduct_notify_moderators_v1(
    'conduct_warning_appeal', 'Nueva apelación de conducta',
    'Una medida social requiere revisión interna.',
    '/admin/conduct?appeal=' || saved_appeal.opaque_reference::text,
    jsonb_build_object('appealReference', saved_appeal.opaque_reference,
      'caseReference', selected_case.opaque_reference),
    'conduct-appeal:' || saved_appeal.id::text
  );
  perform private.pachanga_bump_conduct_subject_v1(current_user_id);
  response := jsonb_build_object(
    'operationId', operation_id, 'appealReference', saved_appeal.opaque_reference,
    'state', saved_appeal.state, 'confirmedRevision', saved_appeal.revision,
    'serverSequence', event_sequence, 'affectsSportRating', false
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, current_user_id, 'conduct.appeal', expected_revision,
    saved_appeal.revision, event_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.appeal_pachanga_conduct_action_v1(uuid, text, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.appeal_pachanga_conduct_action_v1(uuid, text, text, uuid, bigint, jsonb)
  to authenticated;

create or replace function public.resolve_pachanga_conduct_appeal_v1(
  target_appeal_reference uuid,
  next_resolution text,
  resolution_note text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  replay jsonb;
  v_resolution_note text := resolution_note;
  selected_appeal private.pachanga_conduct_appeals%rowtype;
  selected_case private.pachanga_moderation_cases%rowtype;
  event_sequence bigint;
  response jsonb;
begin
  if current_user_id is null or operation_id is null or expected_revision is null
    or next_resolution not in ('uphold', 'correct')
    or char_length(trim(coalesce(v_resolution_note, ''))) not between 1 and 500 then
    raise exception 'Moderator, resolution, reason, operation id and revision required';
  end if;
  if not private.pachanga_is_security_moderator_v1() then raise exception 'Security moderator required'; end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.appeal.resolve', current_user_id);
  if replay is not null then return replay; end if;
  select * into selected_appeal from private.pachanga_conduct_appeals appeals
  where appeals.opaque_reference = target_appeal_reference for update;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'conduct.appeal.resolve', current_user_id);
  if replay is not null then return replay; end if;
  if not found then raise exception 'Appeal not found'; end if;
  if selected_appeal.revision <> expected_revision or selected_appeal.state not in ('submitted', 'under_review') then
    raise exception 'Appeal changed. Reload before resolving.' using errcode = 'PT409';
  end if;
  select * into selected_case from private.pachanga_moderation_cases cases where cases.id = selected_appeal.case_id for update;
  if next_resolution = 'correct' then
    if selected_appeal.action_kind = 'warning' then
      update private.pachanga_conduct_warnings set state = 'corrected', revision = revision + 1,
        server_sequence = nextval('public.pachanga_conduct_sequence')
      where id = selected_appeal.warning_id;
    else
      update private.pachanga_social_restrictions set state = 'corrected', ended_at = clock_timestamp(),
        revision = revision + 1, server_sequence = nextval('public.pachanga_conduct_sequence')
      where id = selected_appeal.restriction_id;
    end if;
  else
    if selected_appeal.action_kind = 'warning' then
      update private.pachanga_conduct_warnings set state = 'active', revision = revision + 1,
        server_sequence = nextval('public.pachanga_conduct_sequence')
      where id = selected_appeal.warning_id;
    else
      update private.pachanga_social_restrictions set state = 'active', revision = revision + 1,
        server_sequence = nextval('public.pachanga_conduct_sequence')
      where id = selected_appeal.restriction_id;
    end if;
  end if;
  event_sequence := nextval('public.pachanga_conduct_sequence');
  update private.pachanga_conduct_appeals set
    state = case when next_resolution = 'correct' then 'corrected' else 'upheld' end,
    resolution_note = trim(v_resolution_note), resolved_by = current_user_id,
    resolved_at = clock_timestamp(), revision = revision + 1,
    server_sequence = event_sequence
  where id = selected_appeal.id returning * into selected_appeal;
  update private.pachanga_moderation_cases set
    state = case when next_resolution = 'correct' then 'corrected' else 'upheld' end,
    decision_summary = trim(v_resolution_note), revision = revision + 1,
    server_sequence = nextval('public.pachanga_conduct_sequence'),
    updated_at = clock_timestamp()
  where id = selected_case.id returning * into selected_case;
  insert into private.pachanga_moderation_events(
    case_id, operation_id, actor_user_id, event_type, from_state, to_state, case_revision, payload
  ) values (
    selected_case.id, operation_id, current_user_id, 'conduct_appeal_resolved',
    'appealed', selected_case.state, selected_case.revision,
    jsonb_build_object('appealReference', selected_appeal.opaque_reference,
      'resolution', next_resolution, 'affectsSportRating', false)
  );
  perform private.pachanga_notify_v1(
    selected_appeal.target_user_id,
    case when next_resolution = 'correct' then 'conduct_warning_corrected' else 'conduct_sanction_upheld' end,
    case when next_resolution = 'correct' then 'Apelación corregida' else 'Apelación resuelta' end,
    case when next_resolution = 'correct' then 'La medida se ha corregido.' else 'La medida se mantiene tras la revisión.' end,
    '/perfil/conducta?appeal=' || selected_appeal.opaque_reference::text,
    jsonb_build_object('appealReference', selected_appeal.opaque_reference,
      'appealRevision', selected_appeal.revision, 'mandatory', true),
    'conduct-appeal-resolution:' || selected_appeal.id::text || ':' || selected_appeal.revision::text
  );
  perform private.pachanga_bump_conduct_subject_v1(selected_appeal.target_user_id);
  response := jsonb_build_object(
    'operationId', operation_id, 'appealReference', selected_appeal.opaque_reference,
    'state', selected_appeal.state, 'confirmedRevision', selected_appeal.revision,
    'serverSequence', event_sequence, 'affectsSportRating', false
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, current_user_id, 'conduct.appeal.resolve', expected_revision,
    selected_appeal.revision, event_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.resolve_pachanga_conduct_appeal_v1(uuid, text, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.resolve_pachanga_conduct_appeal_v1(uuid, text, text, uuid, bigint, jsonb)
  to authenticated;

create or replace function public.run_pachanga_social_restriction_expiry_v1(target_user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare expired_count integer;
begin
  if current_user not in ('postgres', 'service_role') then raise exception 'Internal restriction expiry only'; end if;
  expired_count := private.pachanga_expire_social_restrictions_v1(target_user_id);
  return jsonb_build_object('expired', expired_count, 'serverTime', clock_timestamp());
end;
$$;

revoke all on function public.run_pachanga_social_restriction_expiry_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.run_pachanga_social_restriction_expiry_v1(uuid)
  to service_role;
