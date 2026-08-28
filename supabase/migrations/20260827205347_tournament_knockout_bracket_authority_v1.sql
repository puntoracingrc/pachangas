-- Pachangas IQ R6C: authoritative single-match knockout bracket structure.
-- QualificationSnapshot and BracketTemplate remain immutable inputs. This
-- migration adds only bracket structure, source lineage and future scheduling
-- reservations; sporting results remain owned by R4C.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_competition_staff_assignments
  drop constraint if exists pachanga_competition_staff_assignments_staff_role_check,
  add constraint pachanga_competition_staff_assignments_staff_role_check check (staff_role in (
    'competition_owner', 'competition_director', 'competition_admin', 'rules_manager',
    'competition_referee_manager', 'competition_registration_manager',
    'competition_roster_manager', 'competition_schedule_manager',
    'competition_result_manager', 'competition_standings_manager',
    'competition_operations_manager', 'competition_discipline_manager',
    'competition_discipline_reviewer', 'competition_appeals_manager',
    'competition_draw_manager', 'competition_bracket_manager', 'viewer'
  ));

create or replace function private.pachanga_tournament_knockout_default_policy_v1()
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'schemaVersion', 'tournament_knockout_policy.v1',
    'tieFormat', 'SINGLE_MATCH',
    'extraTimePolicy', 'EXTRA_TIME_THEN_PENALTIES',
    'extraTimeHalfMinutes', 15,
    'extraTimeHalfCount', 2,
    'extraTimeBreakMinutes', 5,
    'penaltyShootoutPolicy', 'PENALTIES_AFTER_EXTRA_TIME',
    'thirdPlaceMatchEnabled', false,
    'byePolicy', 'EXPLICIT_ADVANCE',
    'roundSchedulePolicy', 'RESERVATIONS_BEFORE_PARTICIPANTS',
    'disciplineCarryPolicy', jsonb_build_object(
      'fromGroupStage', 'CARRY_ACTIVE_SANCTIONS',
      'beforeKnockout', 'KEEP_COUNTERS',
      'beforeSemifinal', 'KEEP_COUNTERS',
      'extraTimeCards', 'COUNT_AS_MATCH',
      'substitutionsDuringExtraTime', 'RULE_CONTRACT_ONLY'
    ),
    'qualificationSourcePolicy', 'PUBLISHED_SNAPSHOT_ONLY',
    'winnerAdvancementPolicy', 'OFFICIAL_DECISION_ONLY',
    'advancedFormats', jsonb_build_object(
      'twoLegAggregate', false,
      'doubleElimination', false,
      'loserBracket', false,
      'consolationBracket', false,
      'replayMatch', false,
      'awayGoals', false
    )
  );
$$;

create or replace function private.pachanga_tournament_knockout_validate_policy_v1(
  target_policy jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare policy jsonb := private.pachanga_tournament_knockout_default_policy_v1()
  || coalesce(target_policy, '{}'::jsonb);
declare half_minutes integer;
declare half_count integer;
declare break_minutes integer;
begin
  if jsonb_typeof(coalesce(target_policy, '{}'::jsonb)) <> 'object' then
    raise exception 'TOURNAMENT_KNOCKOUT_POLICY_INVALID' using errcode = '22023';
  end if;
  begin
    half_minutes := (policy ->> 'extraTimeHalfMinutes')::integer;
    half_count := (policy ->> 'extraTimeHalfCount')::integer;
    break_minutes := (policy ->> 'extraTimeBreakMinutes')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'TOURNAMENT_KNOCKOUT_POLICY_INVALID' using errcode = '22023';
  end;
  if policy ->> 'schemaVersion' <> 'tournament_knockout_policy.v1'
     or policy ->> 'tieFormat' <> 'SINGLE_MATCH'
     or policy ->> 'extraTimePolicy' not in ('NO_EXTRA_TIME', 'EXTRA_TIME_THEN_PENALTIES')
     or policy ->> 'penaltyShootoutPolicy' not in (
       'PENALTIES_DIRECT', 'PENALTIES_AFTER_EXTRA_TIME', 'NO_PENALTIES'
     )
     or policy ->> 'byePolicy' <> 'EXPLICIT_ADVANCE'
     or policy ->> 'roundSchedulePolicy' <> 'RESERVATIONS_BEFORE_PARTICIPANTS'
     or policy ->> 'qualificationSourcePolicy' <> 'PUBLISHED_SNAPSHOT_ONLY'
     or policy ->> 'winnerAdvancementPolicy' <> 'OFFICIAL_DECISION_ONLY'
     or jsonb_typeof(policy -> 'disciplineCarryPolicy') <> 'object'
     or jsonb_typeof(policy -> 'advancedFormats') <> 'object'
     or coalesce((policy #>> '{advancedFormats,twoLegAggregate}')::boolean, true)
     or coalesce((policy #>> '{advancedFormats,doubleElimination}')::boolean, true)
     or coalesce((policy #>> '{advancedFormats,loserBracket}')::boolean, true)
     or coalesce((policy #>> '{advancedFormats,consolationBracket}')::boolean, true)
     or coalesce((policy #>> '{advancedFormats,replayMatch}')::boolean, true)
     or coalesce((policy #>> '{advancedFormats,awayGoals}')::boolean, true)
     or half_minutes not between 1 and 60
     or half_count not between 1 and 4
     or break_minutes not between 0 and 30 then
    raise exception 'TOURNAMENT_KNOCKOUT_POLICY_INVALID' using errcode = '22023';
  end if;
  if policy ->> 'extraTimePolicy' = 'NO_EXTRA_TIME'
     and policy ->> 'penaltyShootoutPolicy' = 'PENALTIES_AFTER_EXTRA_TIME' then
    raise exception 'TOURNAMENT_KNOCKOUT_POLICY_INVALID' using errcode = '22023';
  end if;
  return policy;
exception when invalid_text_representation then
  raise exception 'TOURNAMENT_KNOCKOUT_POLICY_INVALID' using errcode = '22023';
end;
$$;

create or replace function private.pachanga_tournament_knockout_rule_insert_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare is_tournament boolean;
declare policy jsonb;
begin
  select competitions.competition_type = 'TOURNAMENT'
  into is_tournament
  from public.pachanga_competition_rule_sets rule_sets
  join public.pachanga_competitions competitions on competitions.id = rule_sets.competition_id
  where rule_sets.id = new.rule_set_id;
  if coalesce(is_tournament, false) then
    policy := private.pachanga_tournament_knockout_validate_policy_v1(
      new.rule_document -> 'knockoutPolicy'
    );
    new.rule_document := jsonb_set(new.rule_document, '{knockoutPolicy}', policy, true);
    new.checksum := encode(extensions.digest(
      convert_to(new.rule_document::text, 'UTF8'), 'sha256'
    ), 'hex');
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_pachanga_tournament_knockout_rule_v1
  on public.pachanga_competition_rule_revisions;
create trigger normalize_pachanga_tournament_knockout_rule_v1
before insert on public.pachanga_competition_rule_revisions
for each row execute function private.pachanga_tournament_knockout_rule_insert_v1();

create or replace function private.pachanga_tournament_knockout_policy_v1(
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb;
begin
  select revisions.rule_document into document
  from public.pachanga_competition_rule_revisions revisions
  join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = revisions.rule_set_id
  join public.pachanga_competitions competitions on competitions.id = rule_sets.competition_id
  where revisions.id = target_rule_revision_id
    and revisions.status in ('published', 'frozen', 'superseded')
    and competitions.competition_type = 'TOURNAMENT';
  if not found then
    raise exception 'TOURNAMENT_KNOCKOUT_RULE_REVISION_REQUIRED' using errcode = '22023';
  end if;
  return private.pachanga_tournament_knockout_validate_policy_v1(
    document -> 'knockoutPolicy'
  );
end;
$$;

create or replace function private.pachanga_tournament_knockout_entity_id_v1(
  target_namespace uuid,
  target_scope text
)
returns uuid
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select substr(encode(extensions.digest(convert_to(
    'pachangas-r6c|' || target_namespace::text || '|' || lower(trim(target_scope)),
    'UTF8'
  ), 'sha256'), 'hex'), 1, 32)::uuid;
$$;

create table public.pachanga_tournament_brackets (
  id uuid primary key,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  group_stage_state_id uuid not null references public.pachanga_tournament_group_stage_states(id) on delete restrict,
  knockout_stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  qualification_snapshot_id uuid not null references public.pachanga_tournament_qualification_snapshots(id) on delete restrict,
  bracket_template_id uuid not null references public.pachanga_tournament_bracket_templates(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  current_revision_id uuid,
  current_completion_snapshot_id uuid,
  status text not null default 'template',
  bracket_size smallint not null,
  round_count smallint not null,
  third_place_enabled boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  locked_at timestamptz,
  check (status in (
    'template', 'seeded', 'ready', 'active', 'completed', 'locked',
    'administrative_review'
  )),
  check (bracket_size between 2 and 128 and (bracket_size & (bracket_size - 1)) = 0),
  check (round_count between 1 and 7),
  check (revision >= 1),
  check ((status in ('completed', 'locked')) = (completed_at is not null)),
  check ((status = 'locked') = (locked_at is not null)),
  unique (competition_id),
  unique (edition_id, knockout_stage_id)
);

create table public.pachanga_tournament_bracket_revisions (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  version integer not null,
  supersedes_revision_id uuid references public.pachanga_tournament_bracket_revisions(id) on delete restrict,
  revision_kind text not null,
  lifecycle_status text not null,
  qualification_snapshot_id uuid not null references public.pachanga_tournament_qualification_snapshots(id) on delete restrict,
  bracket_template_id uuid not null references public.pachanga_tournament_bracket_templates(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  qualification_checksum text not null,
  template_checksum text not null,
  rule_checksum text not null,
  policy_snapshot jsonb not null,
  structure_snapshot jsonb not null,
  checksum text not null,
  operation_id uuid not null unique,
  reason text not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (revision_kind in (
    'ACTIVATION', 'STRUCTURE_REBUILD', 'ADMINISTRATIVE_REVIEW',
    'COMPLETION', 'LOCK'
  )),
  check (lifecycle_status in (
    'seeded', 'ready', 'active', 'completed', 'locked', 'administrative_review'
  )),
  check (length(qualification_checksum) = 64),
  check (length(template_checksum) = 64),
  check (length(rule_checksum) = 64),
  check (jsonb_typeof(policy_snapshot) = 'object'),
  check (jsonb_typeof(structure_snapshot) = 'object'),
  check (length(checksum) = 64),
  check (length(trim(reason)) between 3 and 1200),
  unique (bracket_id, version)
);

alter table public.pachanga_tournament_brackets
  add constraint pachanga_tournament_bracket_current_revision_fk
  foreign key (current_revision_id)
  references public.pachanga_tournament_bracket_revisions(id) on delete restrict;

create table public.pachanga_tournament_bracket_nodes (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  bracket_revision_id uuid not null references public.pachanga_tournament_bracket_revisions(id) on delete restrict,
  current_node_revision_id uuid,
  round_code text not null,
  round_order smallint not null,
  node_order smallint not null,
  node_kind text not null default 'MATCH',
  home_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  away_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  winner_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  loser_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  status text not null default 'awaiting_sources',
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  updated_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (length(trim(round_code)) between 2 and 40),
  check (round_order between 1 and 7),
  check (node_order between 1 and 64),
  check (node_kind in ('MATCH', 'THIRD_PLACE')),
  check (status in (
    'awaiting_sources', 'ready', 'scheduled', 'match_created', 'in_progress',
    'result_pending', 'official', 'advanced', 'cancelled', 'invalidated',
    'administrative_review'
  )),
  check (revision >= 1),
  check (home_entry_id is null or home_entry_id <> away_entry_id),
  constraint pachanga_tournament_bracket_nodes_outcome_check check (
    (winner_entry_id is null and loser_entry_id is null)
    or (
      winner_entry_id is not null
      and loser_entry_id is not null
      and winner_entry_id <> loser_entry_id
    )
    or (
      status = 'advanced'
      and canonical_match_id is null
      and winner_entry_id is not null
      and loser_entry_id is null
      and ((home_entry_id is null) <> (away_entry_id is null))
      and winner_entry_id = coalesce(home_entry_id, away_entry_id)
    )
  ),
  unique (bracket_id, round_code, node_order)
);

create table public.pachanga_tournament_bracket_node_revisions (
  id uuid primary key,
  bracket_node_id uuid not null references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  version integer not null,
  supersedes_revision_id uuid references public.pachanga_tournament_bracket_node_revisions(id) on delete restrict,
  revision_kind text not null,
  status text not null,
  home_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  away_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  winner_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  loser_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  source_snapshot jsonb not null,
  state_snapshot jsonb not null,
  checksum text not null,
  operation_id uuid not null,
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (revision_kind in (
    'ACTIVATION', 'SOURCE_RESOLUTION', 'BYE_ADVANCE', 'RESERVATION',
    'MATCH_GENERATION', 'MATCH_STATE', 'OFFICIAL_RESULT', 'ADVANCE',
    'INVALIDATION', 'REPLACEMENT', 'COMPLETION'
  )),
  check (status in (
    'awaiting_sources', 'ready', 'scheduled', 'match_created', 'in_progress',
    'result_pending', 'official', 'advanced', 'cancelled', 'invalidated',
    'administrative_review'
  )),
  check (jsonb_typeof(source_snapshot) = 'object'),
  check (jsonb_typeof(state_snapshot) = 'object'),
  check (length(checksum) = 64),
  unique (bracket_node_id, version),
  unique (bracket_node_id, operation_id, revision_kind)
);

alter table public.pachanga_tournament_bracket_nodes
  add constraint pachanga_tournament_bracket_node_current_revision_fk
  foreign key (current_node_revision_id)
  references public.pachanga_tournament_bracket_node_revisions(id) on delete restrict;

create table public.pachanga_tournament_bracket_node_slots (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  bracket_revision_id uuid not null references public.pachanga_tournament_bracket_revisions(id) on delete restrict,
  bracket_node_id uuid not null references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  side text not null,
  slot_revision integer not null,
  supersedes_slot_id uuid references public.pachanga_tournament_bracket_node_slots(id) on delete restrict,
  source_kind text not null,
  source_key text not null,
  source_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  source_position smallint,
  source_extra_rank smallint,
  source_draw_seed smallint,
  source_node_id uuid references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  resolved_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  resolution_status text not null,
  source_snapshot jsonb not null,
  operation_id uuid not null,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  check (side in ('HOME', 'AWAY')),
  check (slot_revision >= 1),
  check (source_kind in (
    'GROUP_POSITION', 'EXTRA_QUALIFIER', 'DRAW_SEED',
    'WINNER_OF', 'LOSER_OF', 'BYE'
  )),
  check (length(trim(source_key)) between 1 and 120),
  check (source_position is null or source_position between 1 and 64),
  check (source_extra_rank is null or source_extra_rank between 1 and 64),
  check (source_draw_seed is null or source_draw_seed between 1 and 128),
  check (resolution_status in ('PENDING_SOURCE', 'RESOLVED', 'BYE', 'INVALIDATED')),
  check (jsonb_typeof(source_snapshot) = 'object'),
  check ((source_kind = 'GROUP_POSITION') = (source_group_id is not null and source_position is not null)),
  check ((source_kind = 'EXTRA_QUALIFIER') = (source_extra_rank is not null)),
  check ((source_kind = 'DRAW_SEED') = (source_draw_seed is not null)),
  check ((source_kind in ('WINNER_OF', 'LOSER_OF')) = (source_node_id is not null)),
  check ((source_kind = 'BYE') = (resolution_status = 'BYE')),
  unique (bracket_node_id, side, slot_revision),
  unique (bracket_node_id, side, operation_id)
);

create table public.pachanga_tournament_bracket_fixture_reservations (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  bracket_revision_id uuid not null references public.pachanga_tournament_bracket_revisions(id) on delete restrict,
  bracket_node_id uuid not null references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  reservation_revision integer not null,
  supersedes_reservation_id uuid references public.pachanga_tournament_bracket_fixture_reservations(id) on delete restrict,
  schedule_slot_id uuid not null references public.pachanga_competition_schedule_slots(id) on delete restrict,
  status text not null default 'ACTIVE',
  reservation_snapshot jsonb not null,
  checksum text not null,
  operation_id uuid not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (reservation_revision >= 1),
  check (status in ('ACTIVE', 'CANCELLED')),
  check (jsonb_typeof(reservation_snapshot) = 'object'),
  check (length(checksum) = 64),
  unique (bracket_node_id, reservation_revision)
);

create table public.pachanga_tournament_bracket_round_controls (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  round_code text not null,
  round_order smallint not null,
  control_revision integer not null,
  supersedes_control_id uuid references public.pachanga_tournament_bracket_round_controls(id) on delete restrict,
  status text not null,
  node_snapshot jsonb not null,
  checksum text not null,
  operation_id uuid not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (length(trim(round_code)) between 2 and 40),
  check (round_order between 1 and 7),
  check (control_revision >= 1),
  check (status in ('COMPLETED', 'LOCKED')),
  check (jsonb_typeof(node_snapshot) = 'array'),
  check (length(checksum) = 64),
  unique (bracket_id, round_code, control_revision)
);

create or replace function private.pachanga_tournament_bracket_lifecycle_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'TOURNAMENT_BRACKET_IMMUTABLE' using errcode = '55000';
  end if;
  if new.revision <> old.revision + 1
     or new.competition_id is distinct from old.competition_id
     or new.edition_id is distinct from old.edition_id
     or new.category_id is distinct from old.category_id
     or new.group_stage_state_id is distinct from old.group_stage_state_id
     or new.knockout_stage_id is distinct from old.knockout_stage_id
     or new.qualification_snapshot_id is distinct from old.qualification_snapshot_id
     or new.bracket_template_id is distinct from old.bracket_template_id
     or new.rule_revision_id is distinct from old.rule_revision_id
     or new.bracket_size is distinct from old.bracket_size
     or new.round_count is distinct from old.round_count
     or new.third_place_enabled is distinct from old.third_place_enabled then
    raise exception 'TOURNAMENT_BRACKET_REVISION_INVALID' using errcode = 'PT409';
  end if;
  if old.status = 'locked' then
    raise exception 'TOURNAMENT_BRACKET_LOCKED' using errcode = '55000';
  end if;
  if old.status = 'completed' and new.status <> 'locked' then
    raise exception 'TOURNAMENT_BRACKET_COMPLETED' using errcode = '55000';
  end if;
  if old.status <> new.status and not (
    (old.status = 'template' and new.status = 'seeded')
    or (old.status = 'seeded' and new.status = 'ready')
    or (old.status = 'ready' and new.status = 'active')
    or (old.status = 'active' and new.status in ('administrative_review', 'completed'))
    or (old.status = 'administrative_review' and new.status in ('active', 'completed'))
    or (old.status = 'completed' and new.status = 'locked')
  ) then
    raise exception 'TOURNAMENT_BRACKET_TRANSITION_INVALID' using errcode = '22023';
  end if;
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create trigger guard_pachanga_tournament_bracket_lifecycle_v1
before update or delete on public.pachanga_tournament_brackets
for each row execute function private.pachanga_tournament_bracket_lifecycle_guard_v1();

create trigger guard_pachanga_tournament_bracket_revision_v1
before update or delete on public.pachanga_tournament_bracket_revisions
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_bracket_node_revision_v1
before update or delete on public.pachanga_tournament_bracket_node_revisions
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_bracket_node_slot_v1
before update or delete on public.pachanga_tournament_bracket_node_slots
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_bracket_reservation_v1
before update or delete on public.pachanga_tournament_bracket_fixture_reservations
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_bracket_round_control_v1
before update or delete on public.pachanga_tournament_bracket_round_controls
for each row execute function private.pachanga_tournament_guard_immutable_v1();

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_tournament_brackets',
    'pachanga_tournament_bracket_revisions',
    'pachanga_tournament_bracket_nodes',
    'pachanga_tournament_bracket_node_revisions',
    'pachanga_tournament_bracket_node_slots',
    'pachanga_tournament_bracket_fixture_reservations',
    'pachanga_tournament_bracket_round_controls'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_knockout_default_policy_v1()'::regprocedure,
    'private.pachanga_tournament_knockout_validate_policy_v1(jsonb)'::regprocedure,
    'private.pachanga_tournament_knockout_rule_insert_v1()'::regprocedure,
    'private.pachanga_tournament_knockout_policy_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_knockout_entity_id_v1(uuid,text)'::regprocedure,
    'private.pachanga_tournament_bracket_lifecycle_guard_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

grant execute on function private.pachanga_tournament_knockout_policy_v1(uuid)
  to service_role;
grant execute on function private.pachanga_tournament_knockout_entity_id_v1(uuid,text)
  to service_role;

comment on table public.pachanga_tournament_brackets is
  'Mutable R6C aggregate pointer. Every structural state is preserved in append-only bracket and node revisions.';
comment on table public.pachanga_tournament_bracket_node_slots is
  'Append-only slot-source lineage for GROUP_POSITION, EXTRA_QUALIFIER, DRAW_SEED, WINNER_OF, LOSER_OF and BYE.';
comment on table public.pachanga_tournament_bracket_fixture_reservations is
  'Append-only Tournament reservation over the canonical R4B schedule-slot authority.';
comment on table public.pachanga_tournament_bracket_round_controls is
  'Append-only completion and lock controls for one authoritative knockout round.';
