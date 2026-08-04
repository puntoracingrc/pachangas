-- Pachangas IQ external match results MVP.
-- Accepted challenges become one shared, normalized and server-authoritative match.

create sequence if not exists public.pachanga_external_result_sequence;
revoke all on sequence public.pachanga_external_result_sequence from public, anon, authenticated;
grant usage, select on sequence public.pachanga_external_result_sequence to service_role;

create table if not exists public.pachanga_external_result_settings (
  singleton boolean primary key default true check (singleton),
  confirmation_timeout_hours integer not null default 72,
  reminder_before_hours integer not null default 24,
  updated_at timestamptz not null default clock_timestamp(),
  check (confirmation_timeout_hours between 1 and 720),
  check (reminder_before_hours between 1 and confirmation_timeout_hours)
);

insert into public.pachanga_external_result_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists public.pachanga_external_matches (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null unique references public.pachanga_team_challenges(id) on delete restrict,
  home_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  away_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  scheduled_at timestamptz not null,
  modality text not null,
  field_snapshot jsonb not null default '{}'::jsonb,
  home_level_snapshot numeric,
  away_level_snapshot numeric,
  state text not null default 'draft',
  revision bigint not null default 1,
  active_version integer,
  official_version integer,
  proposed_by_group_id uuid references public.pachanga_groups(id) on delete restrict,
  pending_response_from_group_id uuid references public.pachanga_groups(id) on delete restrict,
  initial_proposal_at timestamptz,
  response_deadline timestamptz,
  reminder_sent_at timestamptz,
  auto_confirmation_blocked boolean not null default false,
  canonical_score_home integer,
  canonical_score_away integer,
  canonical_unassigned_home integer not null default 0,
  canonical_unassigned_away integer not null default 0,
  official_at timestamptz,
  disputed_at timestamptz,
  cancelled_at timestamptz,
  server_sequence bigint not null default nextval('public.pachanga_external_result_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (home_group_id <> away_group_id),
  check (modality in ('sala', 'futbol7', 'futbol11')),
  check (state in (
    'draft', 'pending_rival', 'change_proposed', 'needs_scorer_fix',
    'confirmed', 'auto_confirmed', 'disputed', 'unverified', 'annulled', 'cancelled'
  )),
  check (revision >= 1),
  check (active_version is null or active_version >= 1),
  check (official_version is null or official_version >= 1),
  check (canonical_score_home is null or canonical_score_home >= 0),
  check (canonical_score_away is null or canonical_score_away >= 0),
  check (canonical_unassigned_home >= 0),
  check (canonical_unassigned_away >= 0),
  check (home_level_snapshot is null or home_level_snapshot between 0 and 100),
  check (away_level_snapshot is null or away_level_snapshot between 0 and 100),
  check (proposed_by_group_id is null or proposed_by_group_id in (home_group_id, away_group_id)),
  check (pending_response_from_group_id is null or pending_response_from_group_id in (home_group_id, away_group_id))
);

create index if not exists pachanga_external_matches_home_updated_idx
  on public.pachanga_external_matches(home_group_id, updated_at desc, id desc);
create index if not exists pachanga_external_matches_away_updated_idx
  on public.pachanga_external_matches(away_group_id, updated_at desc, id desc);
create index if not exists pachanga_external_matches_expiry_idx
  on public.pachanga_external_matches(response_deadline, id)
  where state in ('pending_rival', 'change_proposed', 'needs_scorer_fix');

create table if not exists public.pachanga_external_result_versions (
  external_match_id uuid not null references public.pachanga_external_matches(id) on delete restrict,
  version integer not null,
  previous_version integer,
  proposal_kind text not null,
  proposed_by_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  score_home integer not null,
  score_away integer not null,
  operation_id uuid not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  primary key (external_match_id, version),
  check (version >= 1),
  check (previous_version is null or previous_version >= 1),
  check (proposal_kind in ('initial', 'change')),
  check (score_home >= 0 and score_away >= 0)
);

create table if not exists public.pachanga_external_match_participants (
  external_match_id uuid not null,
  result_version integer not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  local_player_id text not null,
  player_profile_id uuid references public.pachanga_player_profiles(id) on delete restrict,
  display_name_snapshot text not null,
  card_snapshot jsonb not null default '{}'::jsonb,
  participant_order integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  primary key (external_match_id, result_version, group_id, local_player_id),
  foreign key (external_match_id, result_version)
    references public.pachanga_external_result_versions(external_match_id, version) on delete restrict,
  check (char_length(local_player_id) between 1 and 160),
  check (char_length(display_name_snapshot) between 1 and 120),
  check (jsonb_typeof(card_snapshot) = 'object'),
  check (participant_order >= 0)
);

create index if not exists pachanga_external_participants_profile_idx
  on public.pachanga_external_match_participants(player_profile_id, external_match_id)
  where player_profile_id is not null;

create table if not exists public.pachanga_external_match_scorers (
  external_match_id uuid not null,
  result_version integer not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  local_player_id text not null,
  goals integer not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (external_match_id, result_version, group_id, local_player_id),
  foreign key (external_match_id, result_version, group_id, local_player_id)
    references public.pachanga_external_match_participants(
      external_match_id, result_version, group_id, local_player_id
    ) on delete restrict,
  check (goals > 0)
);

create table if not exists public.pachanga_external_result_attestations (
  id uuid primary key default gen_random_uuid(),
  external_match_id uuid not null,
  result_version integer not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  decision text not null,
  operation_id uuid not null unique,
  participant_count integer not null default 0,
  scorer_total integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  foreign key (external_match_id, result_version)
    references public.pachanga_external_result_versions(external_match_id, version) on delete restrict,
  check (decision in ('proposed', 'accepted', 'rejected', 'auto_confirmed', 'scorers_completed')),
  check (participant_count >= 0 and scorer_total >= 0)
);

create index if not exists pachanga_external_attestations_match_idx
  on public.pachanga_external_result_attestations(external_match_id, result_version, created_at, id);

create table if not exists public.pachanga_external_result_events (
  id uuid primary key default gen_random_uuid(),
  external_match_id uuid not null references public.pachanga_external_matches(id) on delete restrict,
  operation_id uuid not null unique,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_group_id uuid references public.pachanga_groups(id) on delete set null,
  event_type text not null,
  match_revision bigint not null,
  result_version integer,
  payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('public.pachanga_external_result_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (event_type in (
    'external_match_created', 'match_result_proposed', 'match_result_change_proposed',
    'match_result_confirmed', 'match_result_auto_confirmed', 'match_scorers_completed',
    'match_result_disputed', 'match_result_cancelled', 'match_result_annulled',
    'match_result_reminder_sent'
  )),
  check (match_revision >= 1),
  check (result_version is null or result_version >= 1),
  check (jsonb_typeof(payload) = 'object')
);

create unique index if not exists pachanga_external_result_events_sequence_idx
  on public.pachanga_external_result_events(server_sequence);
create index if not exists pachanga_external_result_events_match_idx
  on public.pachanga_external_result_events(external_match_id, server_sequence desc, id desc);

create table if not exists public.pachanga_external_result_operation_receipts (
  operation_id uuid primary key,
  external_match_id uuid not null references public.pachanga_external_matches(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  operation_type text not null,
  expected_revision bigint,
  result_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  client_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  check (result_revision >= 1),
  check (jsonb_typeof(response) = 'object'),
  check (jsonb_typeof(client_metadata) = 'object')
);

create table if not exists public.pachanga_external_match_group_state (
  group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  external_match_id uuid not null references public.pachanga_external_matches(id) on delete cascade,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_external_result_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  primary key (group_id, external_match_id),
  check (revision >= 1)
);

create index if not exists pachanga_external_group_state_sequence_idx
  on public.pachanga_external_match_group_state(group_id, server_sequence desc, external_match_id);

alter table public.pachanga_external_result_settings enable row level security;
alter table public.pachanga_external_matches enable row level security;
alter table public.pachanga_external_result_versions enable row level security;
alter table public.pachanga_external_match_participants enable row level security;
alter table public.pachanga_external_match_scorers enable row level security;
alter table public.pachanga_external_result_attestations enable row level security;
alter table public.pachanga_external_result_events enable row level security;
alter table public.pachanga_external_result_operation_receipts enable row level security;
alter table public.pachanga_external_match_group_state enable row level security;

revoke all on table public.pachanga_external_result_settings from public, anon, authenticated;
revoke all on table public.pachanga_external_matches from public, anon, authenticated;
revoke all on table public.pachanga_external_result_versions from public, anon, authenticated;
revoke all on table public.pachanga_external_match_participants from public, anon, authenticated;
revoke all on table public.pachanga_external_match_scorers from public, anon, authenticated;
revoke all on table public.pachanga_external_result_attestations from public, anon, authenticated;
revoke all on table public.pachanga_external_result_events from public, anon, authenticated;
revoke all on table public.pachanga_external_result_operation_receipts from public, anon, authenticated;
revoke all on table public.pachanga_external_match_group_state from public, anon, authenticated;

grant select on table public.pachanga_external_matches to authenticated;
grant select on table public.pachanga_external_result_versions to authenticated;
grant select on table public.pachanga_external_match_participants to authenticated;
grant select on table public.pachanga_external_match_scorers to authenticated;
grant select on table public.pachanga_external_result_attestations to authenticated;
grant select on table public.pachanga_external_result_events to authenticated;
grant select on table public.pachanga_external_match_group_state to authenticated;

grant all on table public.pachanga_external_result_settings to service_role;
grant all on table public.pachanga_external_matches to service_role;
grant all on table public.pachanga_external_result_versions to service_role;
grant all on table public.pachanga_external_match_participants to service_role;
grant all on table public.pachanga_external_match_scorers to service_role;
grant all on table public.pachanga_external_result_attestations to service_role;
grant all on table public.pachanga_external_result_events to service_role;
grant all on table public.pachanga_external_result_operation_receipts to service_role;
grant all on table public.pachanga_external_match_group_state to service_role;

create or replace function private.pachanga_can_read_external_match_v1(target_external_match_id uuid)
returns boolean
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.pachanga_external_matches matches
    where matches.id = target_external_match_id
      and (
        public.is_pachanga_group_member(matches.home_group_id)
        or public.is_pachanga_group_member(matches.away_group_id)
      )
  );
$$;

revoke all on function private.pachanga_can_read_external_match_v1(uuid)
  from public, anon, authenticated;

create policy "Members read their external matches"
on public.pachanga_external_matches
for select to authenticated
using (
  public.is_pachanga_group_member(home_group_id)
  or public.is_pachanga_group_member(away_group_id)
);

create policy "Members read external result versions"
on public.pachanga_external_result_versions
for select to authenticated
using (private.pachanga_can_read_external_match_v1(external_match_id));

create policy "Members read external participants"
on public.pachanga_external_match_participants
for select to authenticated
using (private.pachanga_can_read_external_match_v1(external_match_id));

create policy "Members read external scorers"
on public.pachanga_external_match_scorers
for select to authenticated
using (private.pachanga_can_read_external_match_v1(external_match_id));

create policy "Members read external attestations"
on public.pachanga_external_result_attestations
for select to authenticated
using (private.pachanga_can_read_external_match_v1(external_match_id));

create policy "Members read external result events"
on public.pachanga_external_result_events
for select to authenticated
using (private.pachanga_can_read_external_match_v1(external_match_id));

create policy "Members read their external result state"
on public.pachanga_external_match_group_state
for select to authenticated
using (public.is_pachanga_group_member(group_id));

create or replace function private.pachanga_external_group_side_v1(
  target_external_match_id uuid,
  target_group_id uuid
)
returns text
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select case
    when matches.home_group_id = target_group_id then 'home'
    when matches.away_group_id = target_group_id then 'away'
    else null
  end
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id;
$$;

create or replace function private.pachanga_external_roster_v1(target_group_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'localPlayerId', players.value ->> 'id',
    'playerProfileId', profiles.id,
    'name', coalesce(nullif(players.value ->> 'name', ''), profiles.display_name, 'Jugador'),
    'position', coalesce(nullif(players.value ->> 'position', ''), profiles.position),
    'currentOverall', profiles.current_overall,
    'active', not coalesce((players.value ->> 'inactive')::boolean, false)
  )) order by players.ordinality), '[]'::jsonb)
  from public.pachanga_groups groups
  cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'players', '[]'::jsonb))
    with ordinality players(value, ordinality)
  left join public.pachanga_player_profiles profiles
    on profiles.user_id = case
      when coalesce(players.value ->> 'ownerUserId', '')
        ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then (players.value ->> 'ownerUserId')::uuid
      else null
    end
  where groups.id = target_group_id
    and nullif(players.value ->> 'id', '') is not null
    and not coalesce((players.value ->> 'inactive')::boolean, false);
$$;

create or replace function private.pachanga_external_match_snapshot_v1(
  target_external_match_id uuid,
  viewer_group_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', matches.id,
    'challengeId', matches.challenge_id,
    'state', matches.state,
    'revision', matches.revision,
    'serverSequence', matches.server_sequence,
    'scheduledAt', matches.scheduled_at,
    'modality', matches.modality,
    'field', matches.field_snapshot,
    'side', private.pachanga_external_group_side_v1(matches.id, viewer_group_id),
    'homeTeam', jsonb_build_object(
      'groupId', home_group.id,
      'name', home_group.name,
      'teamCode', home_group.team_code,
      'levelSnapshot', matches.home_level_snapshot
    ),
    'awayTeam', jsonb_build_object(
      'groupId', away_group.id,
      'name', away_group.name,
      'teamCode', away_group.team_code,
      'levelSnapshot', matches.away_level_snapshot
    ),
    'activeVersion', matches.active_version,
    'officialVersion', matches.official_version,
    'proposedByGroupId', matches.proposed_by_group_id,
    'pendingResponseFromGroupId', matches.pending_response_from_group_id,
    'initialProposalAt', matches.initial_proposal_at,
    'responseDeadline', matches.response_deadline,
    'reminderSentAt', matches.reminder_sent_at,
    'autoConfirmationBlocked', matches.auto_confirmation_blocked,
    'scoreHome', coalesce(active_result.score_home, matches.canonical_score_home),
    'scoreAway', coalesce(active_result.score_away, matches.canonical_score_away),
    'canonicalScoreHome', matches.canonical_score_home,
    'canonicalScoreAway', matches.canonical_score_away,
    'unassignedHome', matches.canonical_unassigned_home,
    'unassignedAway', matches.canonical_unassigned_away,
    'officialAt', matches.official_at,
    'disputedAt', matches.disputed_at,
    'cancelledAt', matches.cancelled_at,
    'participants', coalesce(participants.value, '[]'::jsonb),
    'scorers', coalesce(scorers.value, '[]'::jsonb),
    'updatedAt', matches.updated_at
  ))
  from public.pachanga_external_matches matches
  join public.pachanga_groups home_group on home_group.id = matches.home_group_id
  join public.pachanga_groups away_group on away_group.id = matches.away_group_id
  left join public.pachanga_external_result_versions active_result
    on active_result.external_match_id = matches.id
    and active_result.version = coalesce(matches.official_version, matches.active_version)
  left join lateral (
    select jsonb_agg(jsonb_build_object(
      'groupId', rows.group_id,
      'localPlayerId', rows.local_player_id,
      'playerProfileId', rows.player_profile_id,
      'name', rows.display_name_snapshot,
      'cardSnapshot', rows.card_snapshot
    ) order by rows.group_id, rows.participant_order, rows.local_player_id) as value
    from public.pachanga_external_match_participants rows
    where rows.external_match_id = matches.id
      and rows.result_version = coalesce(matches.official_version, matches.active_version)
  ) participants on true
  left join lateral (
    select jsonb_agg(jsonb_build_object(
      'groupId', rows.group_id,
      'localPlayerId', rows.local_player_id,
      'goals', rows.goals
    ) order by rows.group_id, rows.local_player_id) as value
    from public.pachanga_external_match_scorers rows
    where rows.external_match_id = matches.id
      and rows.result_version = coalesce(matches.official_version, matches.active_version)
  ) scorers on true
  where matches.id = target_external_match_id
    and viewer_group_id in (matches.home_group_id, matches.away_group_id);
$$;

create or replace function public.get_pachanga_external_results_snapshot_v1(target_group_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'groupId', groups.id,
    'groupName', groups.name,
    'canManage', public.is_pachanga_group_admin(groups.id),
    'confirmedRevision', coalesce((
      select max(states.revision)
      from public.pachanga_external_match_group_state states
      where states.group_id = groups.id
    ), 0),
    'serverSequence', coalesce((
      select max(states.server_sequence)
      from public.pachanga_external_match_group_state states
      where states.group_id = groups.id
    ), 0),
    'roster', private.pachanga_external_roster_v1(groups.id),
    'matches', coalesce((
      select jsonb_agg(private.pachanga_external_match_snapshot_v1(matches.id, groups.id)
        order by matches.scheduled_at desc, matches.id desc)
      from public.pachanga_external_matches matches
      where groups.id in (matches.home_group_id, matches.away_group_id)
    ), '[]'::jsonb),
    'updatedAt', clock_timestamp()
  )
  from public.pachanga_groups groups
  where groups.id = target_group_id
    and public.is_pachanga_group_member(groups.id);
$$;

create or replace function private.pachanga_external_operation_replay_v1(
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_operation_type text
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  saved public.pachanga_external_result_operation_receipts%rowtype;
begin
  select * into saved
  from public.pachanga_external_result_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if saved.actor_user_id is distinct from target_actor_user_id
    or saved.operation_type <> target_operation_type then
    raise exception 'Operation belongs to another actor or action';
  end if;
  return saved.response;
end;
$$;

create or replace function private.pachanga_external_bump_state_v1(
  target_external_match_id uuid,
  target_server_sequence bigint
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_external_match_group_state(
    group_id, external_match_id, revision, server_sequence
  )
  select sides.group_id, matches.id, 1, target_server_sequence
  from public.pachanga_external_matches matches
  cross join lateral (values (matches.home_group_id), (matches.away_group_id)) sides(group_id)
  where matches.id = target_external_match_id
  on conflict (group_id, external_match_id) do update set
    revision = public.pachanga_external_match_group_state.revision + 1,
    server_sequence = excluded.server_sequence,
    updated_at = clock_timestamp();
end;
$$;

create or replace function private.pachanga_external_record_event_v1(
  target_external_match_id uuid,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_actor_group_id uuid,
  target_event_type text,
  target_result_version integer,
  target_payload jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_revision bigint;
  saved_sequence bigint;
begin
  select matches.revision into current_revision
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id;

  insert into public.pachanga_external_result_events(
    external_match_id, operation_id, actor_user_id, actor_group_id,
    event_type, match_revision, result_version, payload
  ) values (
    target_external_match_id, target_operation_id, target_actor_user_id,
    target_actor_group_id, target_event_type, current_revision,
    target_result_version,
    case when jsonb_typeof(target_payload) = 'object' then target_payload else '{}'::jsonb end
  )
  returning server_sequence into saved_sequence;

  update public.pachanga_external_matches matches
  set server_sequence = saved_sequence,
      updated_at = clock_timestamp()
  where matches.id = target_external_match_id;
  perform private.pachanga_external_bump_state_v1(target_external_match_id, saved_sequence);
  return saved_sequence;
end;
$$;

create or replace function private.pachanga_external_store_response_v1(
  target_external_match_id uuid,
  target_viewer_group_id uuid,
  target_operation_id uuid,
  target_operation_type text,
  target_expected_revision bigint,
  target_server_sequence bigint,
  target_client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  canonical jsonb;
  final_response jsonb;
  stored_response jsonb;
begin
  canonical := private.pachanga_external_match_snapshot_v1(
    target_external_match_id, target_viewer_group_id
  );
  final_response := canonical || jsonb_build_object(
    'operationId', target_operation_id,
    'expectedRevision', target_expected_revision,
    'confirmedRevision', (canonical ->> 'revision')::bigint,
    'confirmedAt', clock_timestamp(),
    'serverSequence', target_server_sequence
  );

  insert into public.pachanga_external_result_operation_receipts(
    operation_id, external_match_id, actor_user_id, operation_type,
    expected_revision, result_revision, server_sequence, response, client_metadata
  ) values (
    target_operation_id, target_external_match_id, auth.uid(), target_operation_type,
    target_expected_revision, (canonical ->> 'revision')::bigint,
    target_server_sequence, final_response,
    case when jsonb_typeof(target_client_metadata) = 'object'
      then target_client_metadata else '{}'::jsonb end
  ) on conflict (operation_id) do nothing;

  select receipts.response into stored_response
  from public.pachanga_external_result_operation_receipts receipts
  where receipts.operation_id = target_operation_id
    and receipts.actor_user_id is not distinct from auth.uid();
  if stored_response is null then raise exception 'Operation belongs to another actor'; end if;
  return stored_response;
end;
$$;

create or replace function private.pachanga_external_notify_admins_v1(
  target_group_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_external_match_id uuid,
  target_dedupe_suffix text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipient record;
begin
  for recipient in
    select members.user_id
    from public.pachanga_group_members members
    where members.group_id = target_group_id
      and members.role in ('owner', 'admin')
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id,
      target_kind,
      target_title,
      target_body,
      '/mercado?section=retos',
      jsonb_build_object('externalMatchId', target_external_match_id),
      'external-result:' || target_external_match_id::text || ':'
        || target_dedupe_suffix || ':' || recipient.user_id::text
    );
  end loop;
end;
$$;

create or replace function private.pachanga_set_external_side_submission_v1(
  target_external_match_id uuid,
  target_result_version integer,
  target_group_id uuid,
  target_score integer,
  target_participant_ids text[],
  target_scorers jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_group public.pachanga_groups%rowtype;
  participant_id text;
  participant_payload jsonb;
  profile public.pachanga_player_profiles%rowtype;
  participant_position integer := 0;
  normalized_participants text[];
  scorer_total integer := 0;
  scorer_entry jsonb;
  scorer_player_id text;
  scorer_goals integer;
begin
  if target_score is null or target_score < 0 then raise exception 'Valid team score required'; end if;
  if coalesce(array_length(target_participant_ids, 1), 0) < 1 then
    raise exception 'At least one participant is required';
  end if;
  if jsonb_typeof(coalesce(target_scorers, '[]'::jsonb)) <> 'array' then
    raise exception 'Scorers must be an array';
  end if;

  select array_agg(distinct values.player_id order by values.player_id)
  into normalized_participants
  from unnest(target_participant_ids) values(player_id)
  where nullif(trim(values.player_id), '') is not null;
  if coalesce(cardinality(normalized_participants), 0) <> cardinality(target_participant_ids) then
    raise exception 'Participants must be unique and valid';
  end if;

  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;

  delete from public.pachanga_external_match_scorers scorers
  where scorers.external_match_id = target_external_match_id
    and scorers.result_version = target_result_version
    and scorers.group_id = target_group_id;
  delete from public.pachanga_external_match_participants participants
  where participants.external_match_id = target_external_match_id
    and participants.result_version = target_result_version
    and participants.group_id = target_group_id;

  foreach participant_id in array target_participant_ids loop
    select players.value into participant_payload
    from jsonb_array_elements(coalesce(current_group.payload -> 'players', '[]'::jsonb)) players(value)
    where players.value ->> 'id' = participant_id
      and not coalesce((players.value ->> 'inactive')::boolean, false)
    limit 1;
    if participant_payload is null then
      raise exception 'Participant does not belong to the acting team';
    end if;

    profile := null;
    if coalesce(participant_payload ->> 'ownerUserId', '')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      select * into profile
      from public.pachanga_player_profiles profiles
      where profiles.user_id = (participant_payload ->> 'ownerUserId')::uuid;
    end if;

    participant_position := participant_position + 1;
    insert into public.pachanga_external_match_participants(
      external_match_id, result_version, group_id, local_player_id,
      player_profile_id, display_name_snapshot, card_snapshot, participant_order
    ) values (
      target_external_match_id, target_result_version, target_group_id, participant_id,
      profile.id,
      left(coalesce(nullif(participant_payload ->> 'name', ''), profile.display_name, 'Jugador'), 120),
      jsonb_strip_nulls(jsonb_build_object(
        'currentOverall', profile.current_overall,
        'baseOverall', profile.base_overall,
        'calibratedOverall', profile.calibrated_overall,
        'currentFacets', profile.current_facets,
        'ratingReliability', profile.rating_reliability,
        'engineVersion', profile.rating_engine_version,
        'position', coalesce(participant_payload ->> 'position', profile.position)
      )),
      participant_position
    );
  end loop;

  for scorer_entry in
    select values.value
    from jsonb_array_elements(coalesce(target_scorers, '[]'::jsonb)) values(value)
  loop
    scorer_player_id := nullif(trim(scorer_entry ->> 'playerId'), '');
    if scorer_player_id is null
      or coalesce(scorer_entry ->> 'goals', '') !~ '^[1-9][0-9]*$' then
      raise exception 'Invalid scorer entry';
    end if;
    scorer_goals := (scorer_entry ->> 'goals')::integer;
    if not scorer_player_id = any(target_participant_ids) then
      raise exception 'Scorer must be a participant of the acting team';
    end if;
    if exists (
      select 1 from public.pachanga_external_match_scorers scorers
      where scorers.external_match_id = target_external_match_id
        and scorers.result_version = target_result_version
        and scorers.group_id = target_group_id
        and scorers.local_player_id = scorer_player_id
    ) then raise exception 'Duplicate scorer entry'; end if;
    insert into public.pachanga_external_match_scorers(
      external_match_id, result_version, group_id, local_player_id, goals
    ) values (
      target_external_match_id, target_result_version, target_group_id,
      scorer_player_id, scorer_goals
    );
    scorer_total := scorer_total + scorer_goals;
  end loop;

  if scorer_total <> target_score then
    raise exception 'Own scorers must add up exactly to the team score';
  end if;
  return jsonb_build_object(
    'participantCount', cardinality(target_participant_ids),
    'scorerTotal', scorer_total
  );
end;
$$;

create or replace function private.pachanga_copy_external_result_version_v1(
  target_external_match_id uuid,
  source_version integer,
  target_version integer
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.pachanga_external_match_participants(
    external_match_id, result_version, group_id, local_player_id,
    player_profile_id, display_name_snapshot, card_snapshot, participant_order
  )
  select participants.external_match_id, target_version, participants.group_id,
    participants.local_player_id, participants.player_profile_id,
    participants.display_name_snapshot, participants.card_snapshot,
    participants.participant_order
  from public.pachanga_external_match_participants participants
  where participants.external_match_id = target_external_match_id
    and participants.result_version = source_version;

  insert into public.pachanga_external_match_scorers(
    external_match_id, result_version, group_id, local_player_id, goals
  )
  select scorers.external_match_id, target_version, scorers.group_id,
    scorers.local_player_id, scorers.goals
  from public.pachanga_external_match_scorers scorers
  where scorers.external_match_id = target_external_match_id
    and scorers.result_version = source_version;
end;
$$;

create or replace function private.pachanga_external_side_scorer_total_v1(
  target_external_match_id uuid,
  target_result_version integer,
  target_group_id uuid
)
returns integer
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(sum(scorers.goals), 0)::integer
  from public.pachanga_external_match_scorers scorers
  where scorers.external_match_id = target_external_match_id
    and scorers.result_version = target_result_version
    and scorers.group_id = target_group_id;
$$;

create or replace function private.pachanga_finalize_external_result_v1(
  target_external_match_id uuid,
  target_result_version integer,
  target_final_state text,
  target_operation_id uuid,
  target_actor_user_id uuid,
  target_actor_group_id uuid
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_external_matches%rowtype;
  result_version public.pachanga_external_result_versions%rowtype;
  home_total integer;
  away_total integer;
  event_sequence bigint;
begin
  if target_final_state not in ('confirmed', 'auto_confirmed') then
    raise exception 'Invalid official state';
  end if;
  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  select * into result_version
  from public.pachanga_external_result_versions versions
  where versions.external_match_id = target_external_match_id
    and versions.version = target_result_version;
  if not found then raise exception 'Result version not found'; end if;

  home_total := private.pachanga_external_side_scorer_total_v1(
    target_external_match_id, target_result_version, selected.home_group_id
  );
  away_total := private.pachanga_external_side_scorer_total_v1(
    target_external_match_id, target_result_version, selected.away_group_id
  );
  if target_final_state = 'confirmed'
    and (home_total <> result_version.score_home or away_total <> result_version.score_away) then
    raise exception 'Both scorer distributions must match the accepted score';
  end if;
  if target_final_state = 'auto_confirmed'
    and target_actor_group_id is not null
    and ((target_actor_group_id = selected.home_group_id and home_total <> result_version.score_home)
      or (target_actor_group_id = selected.away_group_id and away_total <> result_version.score_away)) then
    raise exception 'The proposing team scorer distribution must be complete';
  end if;

  update public.pachanga_external_matches matches
  set state = target_final_state,
      revision = matches.revision + 1,
      official_version = target_result_version,
      canonical_score_home = result_version.score_home,
      canonical_score_away = result_version.score_away,
      canonical_unassigned_home = case
        when home_total = result_version.score_home then 0 else result_version.score_home - home_total end,
      canonical_unassigned_away = case
        when away_total = result_version.score_away then 0 else result_version.score_away - away_total end,
      pending_response_from_group_id = null,
      response_deadline = null,
      official_at = clock_timestamp(),
      updated_at = clock_timestamp()
  where matches.id = target_external_match_id;

  insert into public.pachanga_external_result_attestations(
    external_match_id, result_version, group_id, actor_user_id,
    decision, operation_id, participant_count, scorer_total
  ) values (
    target_external_match_id, target_result_version,
    case when target_final_state = 'auto_confirmed'
      then coalesce(selected.pending_response_from_group_id, selected.away_group_id)
      else target_actor_group_id end,
    target_actor_user_id,
    case when target_final_state = 'auto_confirmed' then 'auto_confirmed' else 'accepted' end,
    target_operation_id,
    case when target_final_state = 'auto_confirmed' then 0 else (
      select count(*) from public.pachanga_external_match_participants participants
      where participants.external_match_id = target_external_match_id
        and participants.result_version = target_result_version
        and participants.group_id = target_actor_group_id
    ) end,
    case when target_final_state = 'auto_confirmed' then 0
      when target_actor_group_id = selected.home_group_id then home_total else away_total end
  );

  event_sequence := private.pachanga_external_record_event_v1(
    target_external_match_id, target_operation_id, target_actor_user_id,
    target_actor_group_id,
    case when target_final_state = 'auto_confirmed'
      then 'match_result_auto_confirmed' else 'match_result_confirmed' end,
    target_result_version,
    jsonb_build_object(
      'scoreHome', result_version.score_home,
      'scoreAway', result_version.score_away,
      'unassignedHome', case when home_total = result_version.score_home then 0
        else result_version.score_home - home_total end,
      'unassignedAway', case when away_total = result_version.score_away then 0
        else result_version.score_away - away_total end
    )
  );
  return event_sequence;
end;
$$;

create or replace function private.pachanga_create_external_match_for_challenge_v1(
  target_challenge_id uuid,
  target_operation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_team_challenges%rowtype;
  saved_match_id uuid;
begin
  select * into selected
  from public.pachanga_team_challenges challenges
  where challenges.id = target_challenge_id;
  if not found or selected.status <> 'accepted' then return null; end if;

  insert into public.pachanga_external_matches(
    challenge_id, home_group_id, away_group_id, scheduled_at, modality,
    field_snapshot, home_level_snapshot, away_level_snapshot
  ) values (
    selected.id, selected.sender_group_id, selected.receiver_group_id,
    selected.scheduled_at, selected.modality,
    jsonb_strip_nulls(jsonb_build_object(
      'name', selected.field_name,
      'address', selected.field_address,
      'placeId', selected.field_place_id,
      'mapsUrl', selected.field_maps_url
    )),
    public.pachanga_group_level_v2(selected.sender_group_id, selected.scheduled_at),
    public.pachanga_group_level_v2(selected.receiver_group_id, selected.scheduled_at)
  )
  on conflict (challenge_id) do update set
    scheduled_at = excluded.scheduled_at,
    modality = excluded.modality,
    field_snapshot = excluded.field_snapshot,
    updated_at = clock_timestamp()
  returning id into saved_match_id;

  if not exists (
    select 1 from public.pachanga_external_result_events events
    where events.external_match_id = saved_match_id
      and events.event_type = 'external_match_created'
  ) then
    perform private.pachanga_external_record_event_v1(
      saved_match_id,
      coalesce(target_operation_id, gen_random_uuid()),
      null,
      null,
      'external_match_created',
      null,
      jsonb_build_object('challengeId', selected.id)
    );
  end if;
  return saved_match_id;
end;
$$;

create or replace function private.pachanga_create_external_match_after_challenge_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  accepted_operation_id uuid;
begin
  if new.status = 'accepted' and old.status is distinct from new.status then
    select events.operation_id into accepted_operation_id
    from public.pachanga_team_challenge_events events
    where events.challenge_id = new.id
      and events.event_type = 'accepted'
    order by events.server_sequence desc, events.id desc
    limit 1;
    perform private.pachanga_create_external_match_for_challenge_v1(
      new.id, coalesce(accepted_operation_id, gen_random_uuid())
    );
  end if;
  return new;
end;
$$;

drop trigger if exists create_external_match_after_challenge_accept
  on public.pachanga_team_challenges;
create trigger create_external_match_after_challenge_accept
after update of status on public.pachanga_team_challenges
for each row execute function private.pachanga_create_external_match_after_challenge_v1();

do $$
declare
  accepted record;
begin
  for accepted in
    select challenges.id
    from public.pachanga_team_challenges challenges
    where challenges.status = 'accepted'
  loop
    perform private.pachanga_create_external_match_for_challenge_v1(
      accepted.id, gen_random_uuid()
    );
  end loop;
end;
$$;

create or replace function public.publish_pachanga_external_result_v1(
  target_group_id uuid,
  target_external_match_id uuid,
  target_score_home integer,
  target_score_away integer,
  target_participant_ids text[],
  target_scorers jsonb,
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
  selected public.pachanga_external_matches%rowtype;
  replay jsonb;
  next_version integer;
  own_score integer;
  submission jsonb;
  event_sequence bigint;
  settings public.pachanga_external_result_settings%rowtype;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('external-result-operation:' || operation_id::text, 0));
  replay := private.pachanga_external_operation_replay_v1(
    operation_id, auth.uid(), 'external_result_publish'
  );
  if replay is not null then return replay; end if;

  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found or target_group_id not in (selected.home_group_id, selected.away_group_id) then
    raise exception 'External match not found';
  end if;
  if selected.revision <> expected_revision then
    raise exception 'External match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.state not in ('draft', 'pending_rival') then
    raise exception 'Result cannot be published in its current state';
  end if;
  if selected.state = 'pending_rival' and selected.proposed_by_group_id <> target_group_id then
    raise exception 'Use the change proposal action to answer with another score';
  end if;
  if target_score_home is null or target_score_away is null
    or target_score_home < 0 or target_score_away < 0 then
    raise exception 'Valid non-negative scores are required';
  end if;

  select * into settings from public.pachanga_external_result_settings where singleton;
  next_version := coalesce(selected.active_version, 0) + 1;
  insert into public.pachanga_external_result_versions(
    external_match_id, version, previous_version, proposal_kind,
    proposed_by_group_id, score_home, score_away, operation_id, created_by
  ) values (
    selected.id, next_version, selected.active_version,
    case when selected.active_version is null then 'initial' else 'change' end,
    target_group_id, target_score_home, target_score_away, operation_id, auth.uid()
  );
  if selected.active_version is not null then
    perform private.pachanga_copy_external_result_version_v1(
      selected.id, selected.active_version, next_version
    );
  end if;
  own_score := case when target_group_id = selected.home_group_id
    then target_score_home else target_score_away end;
  submission := private.pachanga_set_external_side_submission_v1(
    selected.id, next_version, target_group_id, own_score,
    target_participant_ids, target_scorers
  );

  update public.pachanga_external_matches matches
  set state = case when selected.active_version is null then 'pending_rival' else 'change_proposed' end,
      revision = matches.revision + 1,
      active_version = next_version,
      proposed_by_group_id = target_group_id,
      pending_response_from_group_id = case when target_group_id = selected.home_group_id
        then selected.away_group_id else selected.home_group_id end,
      initial_proposal_at = coalesce(matches.initial_proposal_at, clock_timestamp()),
      response_deadline = clock_timestamp()
        + make_interval(hours => settings.confirmation_timeout_hours),
      reminder_sent_at = null,
      auto_confirmation_blocked = selected.active_version is not null,
      updated_at = clock_timestamp()
  where matches.id = selected.id;

  insert into public.pachanga_external_result_attestations(
    external_match_id, result_version, group_id, actor_user_id,
    decision, operation_id, participant_count, scorer_total
  ) values (
    selected.id, next_version, target_group_id, auth.uid(), 'proposed', operation_id,
    (submission ->> 'participantCount')::integer,
    (submission ->> 'scorerTotal')::integer
  );
  event_sequence := private.pachanga_external_record_event_v1(
    selected.id, operation_id, auth.uid(), target_group_id,
    case when selected.active_version is null
      then 'match_result_proposed' else 'match_result_change_proposed' end,
    next_version,
    jsonb_build_object('scoreHome', target_score_home, 'scoreAway', target_score_away)
  );
  perform private.pachanga_external_notify_admins_v1(
    case when target_group_id = selected.home_group_id
      then selected.away_group_id else selected.home_group_id end,
    'external_result_proposed', 'Resultado pendiente',
    'El rival ha enviado un marcador. Revisa el resultado y certifica tus goleadores.',
    selected.id, 'proposal-' || next_version::text
  );
  return private.pachanga_external_store_response_v1(
    selected.id, target_group_id, operation_id, 'external_result_publish',
    expected_revision, event_sequence, client_metadata
  );
end;
$$;

create or replace function public.propose_pachanga_external_result_change_v1(
  target_group_id uuid,
  target_external_match_id uuid,
  target_score_home integer,
  target_score_away integer,
  target_participant_ids text[],
  target_scorers jsonb,
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
  selected public.pachanga_external_matches%rowtype;
  replay jsonb;
  next_version integer;
  own_score integer;
  other_score integer;
  other_total integer;
  submission jsonb;
  event_sequence bigint;
  settings public.pachanga_external_result_settings%rowtype;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('external-result-operation:' || operation_id::text, 0));
  replay := private.pachanga_external_operation_replay_v1(
    operation_id, auth.uid(), 'external_result_change'
  );
  if replay is not null then return replay; end if;

  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found or target_group_id not in (selected.home_group_id, selected.away_group_id) then
    raise exception 'External match not found';
  end if;
  if selected.revision <> expected_revision then
    raise exception 'External match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.state <> 'pending_rival'
    or selected.pending_response_from_group_id <> target_group_id then
    raise exception 'Only the waiting rival can propose a score change';
  end if;
  if target_score_home is null or target_score_away is null
    or target_score_home < 0 or target_score_away < 0 then
    raise exception 'Valid non-negative scores are required';
  end if;

  select * into settings from public.pachanga_external_result_settings where singleton;
  next_version := selected.active_version + 1;
  insert into public.pachanga_external_result_versions(
    external_match_id, version, previous_version, proposal_kind,
    proposed_by_group_id, score_home, score_away, operation_id, created_by
  ) values (
    selected.id, next_version, selected.active_version, 'change',
    target_group_id, target_score_home, target_score_away, operation_id, auth.uid()
  );
  perform private.pachanga_copy_external_result_version_v1(
    selected.id, selected.active_version, next_version
  );
  own_score := case when target_group_id = selected.home_group_id
    then target_score_home else target_score_away end;
  other_score := case when target_group_id = selected.home_group_id
    then target_score_away else target_score_home end;
  submission := private.pachanga_set_external_side_submission_v1(
    selected.id, next_version, target_group_id, own_score,
    target_participant_ids, target_scorers
  );
  other_total := private.pachanga_external_side_scorer_total_v1(
    selected.id, next_version,
    case when target_group_id = selected.home_group_id
      then selected.away_group_id else selected.home_group_id end
  );

  update public.pachanga_external_matches matches
  set state = case when other_total = other_score then 'change_proposed' else 'needs_scorer_fix' end,
      revision = matches.revision + 1,
      active_version = next_version,
      proposed_by_group_id = target_group_id,
      pending_response_from_group_id = case when target_group_id = selected.home_group_id
        then selected.away_group_id else selected.home_group_id end,
      response_deadline = clock_timestamp()
        + make_interval(hours => settings.confirmation_timeout_hours),
      reminder_sent_at = null,
      auto_confirmation_blocked = true,
      updated_at = clock_timestamp()
  where matches.id = selected.id;

  insert into public.pachanga_external_result_attestations(
    external_match_id, result_version, group_id, actor_user_id,
    decision, operation_id, participant_count, scorer_total
  ) values (
    selected.id, next_version, target_group_id, auth.uid(), 'proposed', operation_id,
    (submission ->> 'participantCount')::integer,
    (submission ->> 'scorerTotal')::integer
  );
  event_sequence := private.pachanga_external_record_event_v1(
    selected.id, operation_id, auth.uid(), target_group_id,
    'match_result_change_proposed', next_version,
    jsonb_build_object('scoreHome', target_score_home, 'scoreAway', target_score_away)
  );
  perform private.pachanga_external_notify_admins_v1(
    case when target_group_id = selected.home_group_id
      then selected.away_group_id else selected.home_group_id end,
    'external_result_changed', 'Correccion de resultado',
    'El rival propone otro marcador. Debes aceptarlo o rechazarlo.',
    selected.id, 'change-' || next_version::text
  );
  return private.pachanga_external_store_response_v1(
    selected.id, target_group_id, operation_id, 'external_result_change',
    expected_revision, event_sequence, client_metadata
  );
end;
$$;

create or replace function public.confirm_pachanga_external_result_v1(
  target_group_id uuid,
  target_external_match_id uuid,
  target_participant_ids text[],
  target_scorers jsonb,
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
  selected public.pachanga_external_matches%rowtype;
  active_result public.pachanga_external_result_versions%rowtype;
  replay jsonb;
  own_score integer;
  event_sequence bigint;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('external-result-operation:' || operation_id::text, 0));
  replay := private.pachanga_external_operation_replay_v1(
    operation_id, auth.uid(), 'external_result_confirm'
  );
  if replay is not null then return replay; end if;

  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found or target_group_id not in (selected.home_group_id, selected.away_group_id) then
    raise exception 'External match not found';
  end if;
  if selected.revision <> expected_revision then
    raise exception 'External match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.state not in ('pending_rival', 'change_proposed', 'needs_scorer_fix')
    or selected.pending_response_from_group_id <> target_group_id
    or selected.proposed_by_group_id = target_group_id then
    raise exception 'This team is not allowed to confirm the active proposal';
  end if;

  select * into active_result
  from public.pachanga_external_result_versions versions
  where versions.external_match_id = selected.id
    and versions.version = selected.active_version;
  own_score := case when target_group_id = selected.home_group_id
    then active_result.score_home else active_result.score_away end;
  perform private.pachanga_set_external_side_submission_v1(
    selected.id, selected.active_version, target_group_id, own_score,
    target_participant_ids, target_scorers
  );

  event_sequence := private.pachanga_finalize_external_result_v1(
    selected.id, selected.active_version, 'confirmed', operation_id,
    auth.uid(), target_group_id
  );
  perform private.pachanga_external_notify_admins_v1(
    selected.home_group_id, 'external_result_confirmed', 'Resultado confirmado',
    'El resultado externo ya es oficial.', selected.id,
    'confirmed-' || selected.active_version::text || '-home'
  );
  perform private.pachanga_external_notify_admins_v1(
    selected.away_group_id, 'external_result_confirmed', 'Resultado confirmado',
    'El resultado externo ya es oficial.', selected.id,
    'confirmed-' || selected.active_version::text || '-away'
  );
  return private.pachanga_external_store_response_v1(
    selected.id, target_group_id, operation_id, 'external_result_confirm',
    expected_revision, event_sequence, client_metadata
  );
end;
$$;

create or replace function public.reject_pachanga_external_result_change_v1(
  target_group_id uuid,
  target_external_match_id uuid,
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
  selected public.pachanga_external_matches%rowtype;
  replay jsonb;
  event_sequence bigint;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('external-result-operation:' || operation_id::text, 0));
  replay := private.pachanga_external_operation_replay_v1(
    operation_id, auth.uid(), 'external_result_reject_change'
  );
  if replay is not null then return replay; end if;

  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found or target_group_id not in (selected.home_group_id, selected.away_group_id) then
    raise exception 'External match not found';
  end if;
  if selected.revision <> expected_revision then
    raise exception 'External match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.state not in ('change_proposed', 'needs_scorer_fix')
    or selected.pending_response_from_group_id <> target_group_id
    or selected.proposed_by_group_id = target_group_id then
    raise exception 'No rival correction is waiting for this team';
  end if;

  update public.pachanga_external_matches matches
  set state = 'disputed', revision = matches.revision + 1,
      pending_response_from_group_id = null, response_deadline = null,
      disputed_at = clock_timestamp(), updated_at = clock_timestamp()
  where matches.id = selected.id;
  insert into public.pachanga_external_result_attestations(
    external_match_id, result_version, group_id, actor_user_id,
    decision, operation_id, participant_count, scorer_total
  ) values (
    selected.id, selected.active_version, target_group_id, auth.uid(),
    'rejected', operation_id, 0, 0
  );
  event_sequence := private.pachanga_external_record_event_v1(
    selected.id, operation_id, auth.uid(), target_group_id,
    'match_result_disputed', selected.active_version,
    jsonb_build_object('reason', 'correction_rejected')
  );
  perform private.pachanga_external_notify_admins_v1(
    selected.home_group_id, 'external_result_disputed', 'Resultado en discrepancia',
    'La correccion no ha sido aceptada. No se aplicaran estadisticas ni premios.',
    selected.id, 'disputed-home'
  );
  perform private.pachanga_external_notify_admins_v1(
    selected.away_group_id, 'external_result_disputed', 'Resultado en discrepancia',
    'La correccion no ha sido aceptada. No se aplicaran estadisticas ni premios.',
    selected.id, 'disputed-away'
  );
  return private.pachanga_external_store_response_v1(
    selected.id, target_group_id, operation_id, 'external_result_reject_change',
    expected_revision, event_sequence, client_metadata
  );
end;
$$;

create or replace function public.cancel_pachanga_external_match_v1(
  target_group_id uuid,
  target_external_match_id uuid,
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
  selected public.pachanga_external_matches%rowtype;
  replay jsonb;
  event_sequence bigint;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('external-result-operation:' || operation_id::text, 0));
  replay := private.pachanga_external_operation_replay_v1(
    operation_id, auth.uid(), 'external_match_cancel'
  );
  if replay is not null then return replay; end if;
  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found or target_group_id not in (selected.home_group_id, selected.away_group_id) then
    raise exception 'External match not found';
  end if;
  if selected.revision <> expected_revision then
    raise exception 'External match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.state in ('confirmed', 'auto_confirmed', 'annulled', 'cancelled') then
    raise exception 'Official or closed matches cannot be cancelled here';
  end if;
  update public.pachanga_external_matches matches
  set state = 'cancelled', revision = matches.revision + 1,
      pending_response_from_group_id = null, response_deadline = null,
      cancelled_at = clock_timestamp(), updated_at = clock_timestamp()
  where matches.id = selected.id;
  event_sequence := private.pachanga_external_record_event_v1(
    selected.id, operation_id, auth.uid(), target_group_id,
    'match_result_cancelled', selected.active_version, '{}'::jsonb
  );
  return private.pachanga_external_store_response_v1(
    selected.id, target_group_id, operation_id, 'external_match_cancel',
    expected_revision, event_sequence, client_metadata
  );
end;
$$;

create or replace function public.complete_pachanga_external_scorers_v1(
  target_group_id uuid,
  target_external_match_id uuid,
  target_participant_ids text[],
  target_scorers jsonb,
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
  selected public.pachanga_external_matches%rowtype;
  replay jsonb;
  own_score integer;
  submission jsonb;
  event_sequence bigint;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null
    or not public.is_registered_pachanga_user()
    or not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Admin authentication, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('external-result-operation:' || operation_id::text, 0));
  replay := private.pachanga_external_operation_replay_v1(
    operation_id, auth.uid(), 'external_scorers_complete'
  );
  if replay is not null then return replay; end if;
  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found or target_group_id not in (selected.home_group_id, selected.away_group_id) then
    raise exception 'External match not found';
  end if;
  if selected.revision <> expected_revision then
    raise exception 'External match revision is newer. Reload the confirmed state.' using errcode = 'PT409';
  end if;
  if selected.state <> 'auto_confirmed' then
    raise exception 'Only auto-confirmed matches can receive pending scorers';
  end if;
  if (target_group_id = selected.home_group_id and selected.canonical_unassigned_home = 0)
    or (target_group_id = selected.away_group_id and selected.canonical_unassigned_away = 0) then
    raise exception 'This team has no pending scorers';
  end if;
  own_score := case when target_group_id = selected.home_group_id
    then selected.canonical_score_home else selected.canonical_score_away end;
  submission := private.pachanga_set_external_side_submission_v1(
    selected.id, selected.official_version, target_group_id, own_score,
    target_participant_ids, target_scorers
  );
  update public.pachanga_external_matches matches
  set revision = matches.revision + 1,
      canonical_unassigned_home = case when target_group_id = matches.home_group_id
        then 0 else matches.canonical_unassigned_home end,
      canonical_unassigned_away = case when target_group_id = matches.away_group_id
        then 0 else matches.canonical_unassigned_away end,
      updated_at = clock_timestamp()
  where matches.id = selected.id;
  insert into public.pachanga_external_result_attestations(
    external_match_id, result_version, group_id, actor_user_id,
    decision, operation_id, participant_count, scorer_total
  ) values (
    selected.id, selected.official_version, target_group_id, auth.uid(),
    'scorers_completed', operation_id,
    (submission ->> 'participantCount')::integer,
    (submission ->> 'scorerTotal')::integer
  );
  event_sequence := private.pachanga_external_record_event_v1(
    selected.id, operation_id, auth.uid(), target_group_id,
    'match_scorers_completed', selected.official_version,
    jsonb_build_object('groupId', target_group_id)
  );
  return private.pachanga_external_store_response_v1(
    selected.id, target_group_id, operation_id, 'external_scorers_complete',
    expected_revision, event_sequence, client_metadata
  );
end;
$$;

create or replace function private.pachanga_expire_external_match_v1(
  target_external_match_id uuid,
  target_operation_id uuid,
  target_now timestamptz default clock_timestamp()
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_external_matches%rowtype;
  event_sequence bigint;
begin
  perform pg_advisory_xact_lock(hashtextextended('external-result-operation:' || target_operation_id::text, 0));
  if exists (
    select 1 from public.pachanga_external_result_events events
    where events.operation_id = target_operation_id
  ) then
    select events.server_sequence into event_sequence
    from public.pachanga_external_result_events events
    where events.operation_id = target_operation_id;
    return event_sequence;
  end if;
  select * into selected
  from public.pachanga_external_matches matches
  where matches.id = target_external_match_id
  for update;
  if not found or selected.response_deadline is null or selected.response_deadline > target_now then
    return null;
  end if;
  if selected.state = 'pending_rival' and not selected.auto_confirmation_blocked then
    event_sequence := private.pachanga_finalize_external_result_v1(
      selected.id, selected.active_version, 'auto_confirmed', target_operation_id,
      null, selected.proposed_by_group_id
    );
    perform private.pachanga_external_notify_admins_v1(
      selected.home_group_id, 'external_result_auto_confirmed', 'Resultado confirmado por plazo',
      'El marcador inicial se ha confirmado al vencer el plazo.', selected.id,
      'auto-confirmed-home'
    );
    perform private.pachanga_external_notify_admins_v1(
      selected.away_group_id, 'external_result_auto_confirmed', 'Resultado confirmado por plazo',
      'El marcador inicial se ha confirmado al vencer el plazo.', selected.id,
      'auto-confirmed-away'
    );
    return event_sequence;
  end if;
  if selected.state in ('change_proposed', 'needs_scorer_fix') then
    update public.pachanga_external_matches matches
    set state = 'disputed', revision = matches.revision + 1,
        pending_response_from_group_id = null, response_deadline = null,
        disputed_at = target_now, updated_at = clock_timestamp()
    where matches.id = selected.id;
    return private.pachanga_external_record_event_v1(
      selected.id, target_operation_id, null, null,
      'match_result_disputed', selected.active_version,
      jsonb_build_object('reason', 'change_response_expired')
    );
  end if;
  return null;
end;
$$;

create or replace function public.run_pachanga_external_result_expiry_v1(
  operation_id uuid,
  target_batch_size integer default 100,
  target_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  settings public.pachanga_external_result_settings%rowtype;
  candidate record;
  processed integer := 0;
  reminded integer := 0;
  generated_operation_id uuid;
  event_sequence bigint;
begin
  if operation_id is null then raise exception 'Operation id required'; end if;
  select * into settings from public.pachanga_external_result_settings where singleton;

  for candidate in
    select matches.*
    from public.pachanga_external_matches matches
    where matches.state in ('pending_rival', 'change_proposed', 'needs_scorer_fix')
      and matches.response_deadline is not null
      and matches.response_deadline <= target_now
    order by matches.response_deadline, matches.id
    limit greatest(1, least(coalesce(target_batch_size, 100), 500))
    for update skip locked
  loop
    generated_operation_id := md5(
      operation_id::text || ':' || candidate.id::text || ':expire:' || candidate.revision::text
    )::uuid;
    event_sequence := private.pachanga_expire_external_match_v1(
      candidate.id, generated_operation_id, target_now
    );
    if event_sequence is not null then processed := processed + 1; end if;
  end loop;

  for candidate in
    select matches.*
    from public.pachanga_external_matches matches
    where matches.state = 'pending_rival'
      and not matches.auto_confirmation_blocked
      and matches.reminder_sent_at is null
      and matches.response_deadline > target_now
      and matches.response_deadline <= target_now
        + make_interval(hours => settings.reminder_before_hours)
    order by matches.response_deadline, matches.id
    limit greatest(1, least(coalesce(target_batch_size, 100), 500))
    for update skip locked
  loop
    generated_operation_id := md5(
      operation_id::text || ':' || candidate.id::text || ':reminder:' || candidate.revision::text
    )::uuid;
    update public.pachanga_external_matches matches
    set reminder_sent_at = target_now,
        revision = matches.revision + 1,
        updated_at = clock_timestamp()
    where matches.id = candidate.id;
    event_sequence := private.pachanga_external_record_event_v1(
      candidate.id, generated_operation_id, null, null,
      'match_result_reminder_sent', candidate.active_version,
      jsonb_build_object('deadline', candidate.response_deadline)
    );
    perform private.pachanga_external_notify_admins_v1(
      candidate.pending_response_from_group_id,
      'external_result_reminder', 'Resultado pendiente de respuesta',
      'Queda menos de un dia para que venza la propuesta inicial.',
      candidate.id, 'reminder-' || candidate.active_version::text
    );
    reminded := reminded + 1;
  end loop;

  return jsonb_build_object(
    'operationId', operation_id,
    'processed', processed,
    'reminded', reminded,
    'serverTime', target_now
  );
end;
$$;

revoke all on function private.pachanga_external_group_side_v1(uuid, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_external_roster_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_external_match_snapshot_v1(uuid, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_external_operation_replay_v1(uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_external_bump_state_v1(uuid, bigint) from public, anon, authenticated;
revoke all on function private.pachanga_external_record_event_v1(uuid, uuid, uuid, uuid, text, integer, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_external_store_response_v1(uuid, uuid, uuid, text, bigint, bigint, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_external_notify_admins_v1(uuid, text, text, text, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_set_external_side_submission_v1(uuid, integer, uuid, integer, text[], jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_copy_external_result_version_v1(uuid, integer, integer) from public, anon, authenticated;
revoke all on function private.pachanga_external_side_scorer_total_v1(uuid, integer, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_finalize_external_result_v1(uuid, integer, text, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_create_external_match_for_challenge_v1(uuid, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_create_external_match_after_challenge_v1() from public, anon, authenticated;
revoke all on function private.pachanga_expire_external_match_v1(uuid, uuid, timestamptz) from public, anon, authenticated;

revoke all on function public.get_pachanga_external_results_snapshot_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_external_results_snapshot_v1(uuid) to authenticated;
revoke all on function public.publish_pachanga_external_result_v1(uuid, uuid, integer, integer, text[], jsonb, uuid, bigint, jsonb) from public, anon;
grant execute on function public.publish_pachanga_external_result_v1(uuid, uuid, integer, integer, text[], jsonb, uuid, bigint, jsonb) to authenticated;
revoke all on function public.propose_pachanga_external_result_change_v1(uuid, uuid, integer, integer, text[], jsonb, uuid, bigint, jsonb) from public, anon;
grant execute on function public.propose_pachanga_external_result_change_v1(uuid, uuid, integer, integer, text[], jsonb, uuid, bigint, jsonb) to authenticated;
revoke all on function public.confirm_pachanga_external_result_v1(uuid, uuid, text[], jsonb, uuid, bigint, jsonb) from public, anon;
grant execute on function public.confirm_pachanga_external_result_v1(uuid, uuid, text[], jsonb, uuid, bigint, jsonb) to authenticated;
revoke all on function public.reject_pachanga_external_result_change_v1(uuid, uuid, uuid, bigint, jsonb) from public, anon;
grant execute on function public.reject_pachanga_external_result_change_v1(uuid, uuid, uuid, bigint, jsonb) to authenticated;
revoke all on function public.cancel_pachanga_external_match_v1(uuid, uuid, uuid, bigint, jsonb) from public, anon;
grant execute on function public.cancel_pachanga_external_match_v1(uuid, uuid, uuid, bigint, jsonb) to authenticated;
revoke all on function public.complete_pachanga_external_scorers_v1(uuid, uuid, text[], jsonb, uuid, bigint, jsonb) from public, anon;
grant execute on function public.complete_pachanga_external_scorers_v1(uuid, uuid, text[], jsonb, uuid, bigint, jsonb) to authenticated;
revoke all on function public.run_pachanga_external_result_expiry_v1(uuid, integer, timestamptz) from public, anon, authenticated;
grant execute on function public.run_pachanga_external_result_expiry_v1(uuid, integer, timestamptz) to service_role;

alter table public.pachanga_external_match_group_state replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pachanga_external_match_group_state'
  ) then
    alter publication supabase_realtime add table public.pachanga_external_match_group_state;
  end if;
end;
$$;
