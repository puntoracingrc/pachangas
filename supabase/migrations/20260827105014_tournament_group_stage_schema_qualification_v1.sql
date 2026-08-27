-- Pachangas IQ R6B: Tournament group-stage authority, qualification evidence
-- and a non-progressing bracket template. R4B/R4C remain the only fixture,
-- result and standings engines.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.pachanga_tournament_group_stage_states (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  draw_plan_id uuid not null references public.pachanga_competition_draw_plans(id) on delete restrict,
  draw_revision_id uuid not null references public.pachanga_competition_draw_revisions(id) on delete restrict,
  participant_freeze_id uuid not null references public.pachanga_competition_participant_freezes(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  current_preparation_id uuid,
  current_qualification_snapshot_id uuid,
  current_bracket_template_id uuid,
  status text not null default 'prepared',
  group_count smallint not null,
  entry_count smallint not null,
  fixture_count integer not null default 0,
  official_fixture_count integer not null default 0,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid not null references auth.users(id) on delete restrict,
  completed_by uuid references auth.users(id) on delete restrict,
  completion_operation_id uuid unique,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  check (status in (
    'prepared', 'scheduling', 'schedule_validated', 'schedule_published',
    'active', 'complete', 'cancelled'
  )),
  check (group_count between 1 and 16),
  check (entry_count between 2 and 64),
  check (fixture_count >= 0 and official_fixture_count between 0 and fixture_count),
  check (revision >= 1),
  check (
    (completed_by is null and completion_operation_id is null and completed_at is null)
    or (completed_by is not null and completion_operation_id is not null
      and completed_at is not null and status = 'complete')
  ),
  unique (competition_id, stage_id),
  unique (draw_plan_id)
);

create table public.pachanga_tournament_group_stage_preparations (
  id uuid primary key,
  group_stage_state_id uuid not null references public.pachanga_tournament_group_stage_states(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  category_id uuid not null references public.pachanga_competition_categories(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  draw_plan_id uuid not null references public.pachanga_competition_draw_plans(id) on delete restrict,
  draw_revision_id uuid not null references public.pachanga_competition_draw_revisions(id) on delete restrict,
  participant_freeze_id uuid not null references public.pachanga_competition_participant_freezes(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  draw_checksum text not null,
  participant_checksum text not null,
  group_checksum text not null,
  rule_checksum text not null,
  input_checksum text not null,
  participant_snapshot jsonb not null,
  group_snapshot jsonb not null,
  schedule_policy_snapshot jsonb not null,
  qualification_policy_snapshot jsonb not null,
  group_count smallint not null,
  entry_count smallint not null,
  status text not null default 'PREPARED',
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  operation_id uuid not null unique,
  prepared_by uuid not null references auth.users(id) on delete restrict,
  prepared_at timestamptz not null default clock_timestamp(),
  check (length(draw_checksum) = 64),
  check (length(participant_checksum) = 64),
  check (length(group_checksum) = 64),
  check (length(rule_checksum) = 64),
  check (length(input_checksum) = 64),
  check (jsonb_typeof(participant_snapshot) = 'array'),
  check (jsonb_typeof(group_snapshot) = 'array'),
  check (jsonb_typeof(schedule_policy_snapshot) = 'object'),
  check (jsonb_typeof(qualification_policy_snapshot) = 'object'),
  check (group_count between 1 and 16),
  check (entry_count between 2 and 64),
  check (status = 'PREPARED'),
  check (revision = 1),
  unique (group_stage_state_id, input_checksum)
);

alter table public.pachanga_tournament_group_stage_states
  add constraint pachanga_tournament_group_stage_current_preparation_fk
  foreign key (current_preparation_id)
  references public.pachanga_tournament_group_stage_preparations(id) on delete restrict;

create table public.pachanga_tournament_qualification_snapshots (
  id uuid primary key,
  group_stage_state_id uuid not null references public.pachanga_tournament_group_stage_states(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  preparation_id uuid not null references public.pachanga_tournament_group_stage_preparations(id) on delete restrict,
  supersedes_snapshot_id uuid references public.pachanga_tournament_qualification_snapshots(id) on delete restrict,
  status text not null,
  source_standings_revision bigint not null,
  source_standing_snapshot_ids uuid[] not null,
  policy_snapshot jsonb not null,
  health_snapshot jsonb not null,
  group_qualifiers jsonb not null,
  cross_group_qualifiers jsonb not null,
  eliminated_entries jsonb not null,
  target_bracket_slots jsonb not null,
  checksum text not null,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  operation_id uuid not null unique,
  generated_by uuid not null references auth.users(id) on delete restrict,
  generated_at timestamptz not null default clock_timestamp(),
  published_by uuid references auth.users(id) on delete restrict,
  published_at timestamptz,
  check (status in ('PROVISIONAL', 'READY', 'PUBLISHED')),
  check (source_standings_revision >= 0),
  check (cardinality(source_standing_snapshot_ids) >= 1),
  check (jsonb_typeof(policy_snapshot) = 'object'),
  check (jsonb_typeof(health_snapshot) = 'object'),
  check (jsonb_typeof(group_qualifiers) = 'array'),
  check (jsonb_typeof(cross_group_qualifiers) = 'array'),
  check (jsonb_typeof(eliminated_entries) = 'array'),
  check (jsonb_typeof(target_bracket_slots) = 'array'),
  check (length(checksum) = 64),
  check (revision = 1),
  check ((status = 'PUBLISHED') = (published_at is not null)),
  check ((status = 'PUBLISHED') = (published_by is not null)),
  unique (group_stage_state_id, status, checksum)
);

create table public.pachanga_tournament_qualification_rows (
  id uuid primary key default gen_random_uuid(),
  qualification_snapshot_id uuid not null references public.pachanga_tournament_qualification_snapshots(id) on delete restrict,
  competition_group_id uuid not null references public.pachanga_competition_groups(id) on delete restrict,
  standing_snapshot_id uuid not null references public.pachanga_competition_standing_snapshots(id) on delete restrict,
  entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  group_position integer not null,
  cross_group_rank integer,
  outcome text not null,
  target_bracket_slot text,
  comparison_values jsonb not null default '{}'::jsonb,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (group_position >= 1),
  check (cross_group_rank is null or cross_group_rank >= 1),
  check (outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER', 'ELIMINATED')),
  check (target_bracket_slot is null or length(trim(target_bracket_slot)) between 1 and 80),
  check (jsonb_typeof(comparison_values) = 'object'),
  unique (qualification_snapshot_id, entry_id)
);

create unique index pachanga_tournament_qualification_rows_target_slot_idx
  on public.pachanga_tournament_qualification_rows(
    qualification_snapshot_id, target_bracket_slot
  ) where target_bracket_slot is not null;

alter table public.pachanga_tournament_group_stage_states
  add constraint pachanga_tournament_group_stage_current_qualification_fk
  foreign key (current_qualification_snapshot_id)
  references public.pachanga_tournament_qualification_snapshots(id) on delete restrict;

create table public.pachanga_tournament_bracket_templates (
  id uuid primary key,
  group_stage_state_id uuid not null references public.pachanga_tournament_group_stage_states(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  qualification_snapshot_id uuid not null references public.pachanga_tournament_qualification_snapshots(id) on delete restrict,
  supersedes_template_id uuid references public.pachanga_tournament_bracket_templates(id) on delete restrict,
  status text not null,
  bracket_size smallint not null,
  first_round_match_count smallint not null,
  slot_count smallint not null,
  template_snapshot jsonb not null,
  checksum text not null,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  operation_id uuid not null unique,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  published_by uuid references auth.users(id) on delete restrict,
  published_at timestamptz,
  check (status in ('DRAFT', 'PUBLISHED')),
  check (bracket_size between 2 and 128 and (bracket_size & (bracket_size - 1)) = 0),
  check (first_round_match_count = bracket_size / 2),
  check (slot_count = bracket_size),
  check (jsonb_typeof(template_snapshot) = 'object'),
  check (length(checksum) = 64),
  check (revision = 1),
  check ((status = 'PUBLISHED') = (published_at is not null)),
  check ((status = 'PUBLISHED') = (published_by is not null)),
  unique (group_stage_state_id, status, checksum)
);

create table public.pachanga_tournament_bracket_slots (
  id uuid primary key default gen_random_uuid(),
  bracket_template_id uuid not null references public.pachanga_tournament_bracket_templates(id) on delete restrict,
  slot_key text not null,
  match_number smallint not null,
  side text not null,
  bracket_order smallint not null,
  source_kind text not null,
  source_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  source_position smallint,
  source_extra_rank smallint,
  source_draw_seed smallint,
  resolved_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  status text not null,
  source_snapshot jsonb not null,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (length(trim(slot_key)) between 1 and 80),
  check (match_number between 1 and 64),
  check (side in ('A', 'B')),
  check (bracket_order between 1 and 128),
  check (source_kind in ('GROUP_POSITION', 'EXTRA_QUALIFIER', 'DRAW_SEED', 'BYE')),
  check (source_position is null or source_position between 1 and 64),
  check (source_extra_rank is null or source_extra_rank between 1 and 64),
  check (source_draw_seed is null or source_draw_seed between 1 and 128),
  check (status in ('PENDING_SOURCE', 'RESOLVED', 'BYE')),
  check (jsonb_typeof(source_snapshot) = 'object'),
  check ((source_kind = 'GROUP_POSITION') = (source_group_id is not null and source_position is not null)),
  check ((source_kind = 'EXTRA_QUALIFIER') = (source_extra_rank is not null)),
  check ((source_kind = 'DRAW_SEED') = (source_draw_seed is not null)),
  check ((source_kind = 'BYE') = (status = 'BYE')),
  unique (bracket_template_id, slot_key),
  unique (bracket_template_id, bracket_order),
  unique (bracket_template_id, match_number, side)
);

alter table public.pachanga_tournament_group_stage_states
  add constraint pachanga_tournament_group_stage_current_bracket_fk
  foreign key (current_bracket_template_id)
  references public.pachanga_tournament_bracket_templates(id) on delete restrict;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_tournament_group_stage_states',
    'pachanga_tournament_group_stage_preparations',
    'pachanga_tournament_qualification_snapshots',
    'pachanga_tournament_qualification_rows',
    'pachanga_tournament_bracket_templates',
    'pachanga_tournament_bracket_slots'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

create trigger guard_pachanga_tournament_group_stage_preparation_v1
before update or delete on public.pachanga_tournament_group_stage_preparations
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_qualification_snapshot_v1
before update or delete on public.pachanga_tournament_qualification_snapshots
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_qualification_row_v1
before update or delete on public.pachanga_tournament_qualification_rows
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_bracket_template_v1
before update or delete on public.pachanga_tournament_bracket_templates
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create trigger guard_pachanga_tournament_bracket_slot_v1
before update or delete on public.pachanga_tournament_bracket_slots
for each row execute function private.pachanga_tournament_guard_immutable_v1();

comment on table public.pachanga_tournament_group_stage_states is
  'Mutable R6B aggregate pointer. Fixtures, results and standings remain canonical R4B/R4C entities.';
comment on table public.pachanga_tournament_qualification_snapshots is
  'Append-only R6B qualification evidence over immutable R4C StandingSnapshots.';
comment on table public.pachanga_tournament_bracket_templates is
  'Append-only bracket layout only. It cannot generate knockout matches or advance winners.';

create or replace function private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id uuid,
  target_scope text
)
returns uuid
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select substr(encode(extensions.digest(convert_to(
    'pachangas-r6b|' || target_operation_id::text || '|' || lower(trim(target_scope)),
    'UTF8'
  ), 'sha256'), 'hex'), 1, 32)::uuid;
$$;

revoke all on function private.pachanga_tournament_group_operation_entity_id_v1(uuid, text)
  from public, anon, authenticated;
grant execute on function private.pachanga_tournament_group_operation_entity_id_v1(uuid, text)
  to service_role;

create or replace function private.pachanga_tournament_group_stage_policy_v1(
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb := private.pachanga_league_rule_document_v1(target_rule_revision_id);
declare schedule_policy jsonb;
declare match_policy jsonb;
declare qualification_policy jsonb := coalesce(document #> '{structure,qualificationPolicy}', '{}'::jsonb);
declare policy_kind text;
declare direct_count integer;
declare extra_count integer;
declare comparator jsonb;
declare target_slots jsonb;
declare equal_size_required boolean;
declare tie_policy text;
begin
  begin
    schedule_policy := private.pachanga_league_schedule_policy_v1(target_rule_revision_id);
    match_policy := private.pachanga_league_match_policy_v1(target_rule_revision_id);
    policy_kind := upper(nullif(trim(qualification_policy ->> 'kind'), ''));
    direct_count := nullif(qualification_policy ->> 'directQualifiersPerGroup', '')::integer;
    extra_count := coalesce(nullif(qualification_policy ->> 'extraQualifierCount', '')::integer, 0);
    comparator := coalesce(qualification_policy -> 'comparatorCriteria', '[]'::jsonb);
    target_slots := coalesce(qualification_policy -> 'targetBracketSlots', '[]'::jsonb);
    equal_size_required := coalesce((qualification_policy ->> 'equalGroupSizeRequired')::boolean, true);
    tie_policy := upper(coalesce(nullif(trim(qualification_policy ->> 'tieResolutionPolicy'), ''), ''));
  exception when others then
    raise exception 'TOURNAMENT_GROUP_STAGE_RULES_REQUIRED' using errcode = '22023';
  end;
  if policy_kind not in (
       'TOP_N_PER_GROUP',
       'TOP_N_PER_GROUP_PLUS_BEST_RUNNERS_UP',
       'TOP_N_PER_GROUP_PLUS_BEST_THIRDS'
     )
     or direct_count is null or direct_count < 1 or direct_count > 16
     or extra_count < 0 or extra_count > 32
     or jsonb_typeof(comparator) <> 'array'
     or jsonb_typeof(target_slots) <> 'array'
     or jsonb_array_length(target_slots) < direct_count
     or tie_policy not in ('PERSISTED_DRAW_LOT', 'MANUAL_ORGANIZER_DECISION') then
    raise exception 'TOURNAMENT_QUALIFICATION_POLICY_INVALID' using errcode = '22023';
  end if;
  if policy_kind = 'TOP_N_PER_GROUP' and extra_count <> 0 then
    raise exception 'TOURNAMENT_QUALIFICATION_POLICY_INVALID' using errcode = '22023';
  end if;
  if policy_kind <> 'TOP_N_PER_GROUP'
     and (extra_count = 0 or jsonb_array_length(comparator) = 0) then
    raise exception 'CROSS_GROUP_QUALIFICATION_POLICY_REQUIRED' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(comparator) criteria(value)
    where upper(criteria.value) not in (
      'POINTS', 'POINTS_PER_MATCH', 'GOAL_DIFFERENCE',
      'GOAL_DIFFERENCE_PER_MATCH', 'GOALS_FOR', 'GOALS_FOR_PER_MATCH',
      'WINS', 'WINS_PER_MATCH', 'PERSISTED_DRAW_LOT'
    )
  ) then raise exception 'TOURNAMENT_CROSS_GROUP_CRITERION_NOT_SUPPORTED' using errcode = '0A000'; end if;
  return jsonb_build_object(
    'schedulePolicy', schedule_policy,
    'matchPolicy', match_policy,
    'qualificationPolicy', jsonb_build_object(
      'kind', policy_kind,
      'directQualifiersPerGroup', direct_count,
      'extraQualifierCount', extra_count,
      'comparatorCriteria', comparator,
      'equalGroupSizeRequired', equal_size_required,
      'targetBracketSlots', target_slots,
      'tieResolutionPolicy', tie_policy
    ),
    'exceptionPolicy', document #> '{operations,exceptionPolicy}',
    'refereePolicy', document #> '{operations,refereePolicy}',
    'disciplinePolicy', document #> '{discipline,policy}'
  );
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_policy_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_rule_document_v1(
  target_configuration jsonb,
  target_team_cap integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare configuration jsonb := coalesce(target_configuration, '{}'::jsonb);
declare group_stage jsonb := coalesce(configuration -> 'groupStage', '{}'::jsonb);
declare target_type text := upper(coalesce(configuration ->> 'drawTarget', 'GROUP_ASSIGNMENT'));
declare draw_mode text := upper(coalesce(configuration ->> 'drawMode', 'PURE_RANDOM'));
declare modality text := upper(coalesce(configuration ->> 'modality', 'FUTBOL_7'));
declare group_count integer := coalesce(nullif(configuration ->> 'groupCount', '')::integer, 4);
declare qualifiers integer := coalesce(nullif(configuration ->> 'qualifiersPerGroup', '')::integer, 2);
declare legs integer := coalesce(nullif(group_stage ->> 'legs', '')::integer, 1);
declare duration_minutes integer := coalesce(nullif(group_stage ->> 'matchDurationMinutes', '')::integer, 60);
declare buffer_minutes integer := coalesce(nullif(group_stage ->> 'requiredBufferMinutes', '')::integer, 15);
declare minimum_rest_minutes integer := coalesce(nullif(group_stage ->> 'minimumRestMinutes', '')::integer, 720);
declare points_win integer := coalesce(nullif(group_stage ->> 'pointsForWin', '')::integer, 3);
declare points_draw integer := coalesce(nullif(group_stage ->> 'pointsForDraw', '')::integer, 1);
declare points_loss integer := coalesce(nullif(group_stage ->> 'pointsForLoss', '')::integer, 0);
declare starter_count integer;
declare squad_max integer;
declare qualification_kind text := upper(coalesce(
  group_stage ->> 'qualificationPolicy', 'TOP_N_PER_GROUP'
));
declare extra_qualifiers integer := coalesce(nullif(group_stage ->> 'extraQualifierCount', '')::integer, 0);
declare comparator jsonb := coalesce(group_stage -> 'comparatorCriteria', '[]'::jsonb);
declare target_slots jsonb := coalesce(group_stage -> 'targetBracketSlots', '[]'::jsonb);
declare qualifier_total integer;
declare slot_index integer;
declare document jsonb;
begin
  starter_count := case modality
    when 'FUTBOL_11' then 11
    when 'FUTBOL_7' then 7
    when 'FUTBOL_5' then 5
    when 'FUTSAL' then 5
    else 7
  end;
  squad_max := coalesce(nullif(group_stage ->> 'squadMax', '')::integer, starter_count * 2);
  qualifier_total := case when target_type = 'GROUPS_THEN_KNOCKOUT'
    then group_count * qualifiers + extra_qualifiers else greatest(group_count * qualifiers, 2) end;
  if jsonb_array_length(target_slots) = 0 then
    target_slots := '[]'::jsonb;
    for slot_index in 1..qualifier_total loop
      target_slots := target_slots || jsonb_build_array(
        'R1-M' || ceil(slot_index::numeric / 2)::integer || '-' || case when slot_index % 2 = 1 then 'A' else 'B' end
      );
    end loop;
  end if;
  if jsonb_typeof(configuration) <> 'object'
     or jsonb_typeof(group_stage) <> 'object'
     or target_team_cap not between 4 and 64
     or target_type not in ('GROUP_ASSIGNMENT', 'KNOCKOUT_INITIAL_SEEDING', 'GROUPS_THEN_KNOCKOUT')
     or draw_mode not in ('PURE_RANDOM', 'SEEDED_POTS', 'CONSTRAINT_OPTIMIZED', 'MANUAL_ASSISTED', 'HYBRID')
     or modality not in ('FUTBOL_5', 'FUTBOL_7', 'FUTBOL_11', 'FUTSAL')
     or group_count not between 1 and 16
     or qualifiers not between 1 and 16
     or legs not in (1, 2)
     or duration_minutes not between 1 and 360
     or buffer_minutes not between 0 and 240
     or minimum_rest_minutes not between 0 and 10080
     or squad_max < starter_count or squad_max > 64
     or points_win not between -20 and 20
     or points_draw not between -20 and 20
     or points_loss not between -20 and 20
     or qualification_kind not in (
       'TOP_N_PER_GROUP', 'TOP_N_PER_GROUP_PLUS_BEST_RUNNERS_UP',
       'TOP_N_PER_GROUP_PLUS_BEST_THIRDS'
     )
     or extra_qualifiers not between 0 and 32
     or jsonb_typeof(comparator) <> 'array'
     or jsonb_typeof(target_slots) <> 'array'
     or jsonb_array_length(target_slots) <> qualifier_total then
    raise exception 'TOURNAMENT_CONFIGURATION_INVALID' using errcode = '22023';
  end if;
  if qualification_kind = 'TOP_N_PER_GROUP' and extra_qualifiers <> 0 then
    raise exception 'TOURNAMENT_CONFIGURATION_INVALID' using errcode = '22023';
  end if;
  if qualification_kind <> 'TOP_N_PER_GROUP'
     and (extra_qualifiers = 0 or jsonb_array_length(comparator) = 0) then
    raise exception 'CROSS_GROUP_QUALIFICATION_POLICY_REQUIRED' using errcode = '22023';
  end if;
  if (select count(*) from jsonb_array_elements_text(target_slots))
     <> (select count(distinct value) from jsonb_array_elements_text(target_slots) slots(value)) then
    raise exception 'TOURNAMENT_BRACKET_SLOT_DUPLICATED' using errcode = '22023';
  end if;
  document := jsonb_build_object(
    'identity', jsonb_build_object(
      'configurationSchema', 'tournament-configuration.v2',
      'authoringMode', upper(coalesce(configuration ->> 'authoringMode', 'SIMPLE')),
      'sourcePresetId', nullif(upper(configuration ->> 'sourcePresetKey'), ''),
      'sourcePresetVersion', case when nullif(configuration ->> 'sourcePresetKey', '') is not null then 2 end
    ),
    'format', jsonb_build_object(
      'competitionType', 'TOURNAMENT', 'sportFormat', modality,
      'modality', modality, 'drawTarget', target_type, 'drawMode', draw_mode
    ),
    'registration', jsonb_build_object(
      'mode', 'INVITE_ONLY', 'minimumTeams', 4, 'maximumTeams', target_team_cap,
      'publicRegistration', false,
      'registrationPolicy', jsonb_build_object(
        'mode', 'INVITE_ONLY',
        'teamLimits', jsonb_build_object('minimum', 4, 'maximum', target_team_cap)
      ),
      'rosterPolicy', jsonb_build_object(
        'minimumSize', starter_count,
        'maximumSize', squad_max,
        'multiTeamPolicy', 'FORBIDDEN_SAME_EDITION_CATEGORY',
        'closeRequiresApprovedRosters', true
      ),
      'identityRequirements', jsonb_build_object('credentialRequired', false),
      'kitPolicy', jsonb_build_object(
        'jerseyRequired', false,
        'jerseyNumberMinimum', 1,
        'jerseyNumberMaximum', 99
      ),
      'matchSheetPolicy', jsonb_build_object(
        'squadMin', starter_count, 'squadMax', squad_max,
        'starterMin', starter_count, 'starterMax', starter_count,
        'substituteMax', squad_max - starter_count
      )
    ),
    'structure', jsonb_build_object(
      'stageGraph', jsonb_build_object(
        'nodes', jsonb_build_array(jsonb_build_object(
          'id', 'initial-stage', 'root', true, 'optional', false,
          'type', case when target_type = 'KNOCKOUT_INITIAL_SEEDING' then 'KNOCKOUT' else 'GROUP_STAGE' end
        )), 'edges', jsonb_build_array()
      ),
      'groupCount', case when target_type = 'KNOCKOUT_INITIAL_SEEDING' then null else group_count end,
      'qualifiersPerGroup', case when target_type = 'GROUPS_THEN_KNOCKOUT' then qualifiers else null end,
      'qualificationPolicy', jsonb_build_object(
        'kind', qualification_kind,
        'directQualifiersPerGroup', qualifiers,
        'extraQualifierCount', extra_qualifiers,
        'comparatorCriteria', comparator,
        'equalGroupSizeRequired', coalesce((group_stage ->> 'equalGroupSizeRequired')::boolean, true),
        'targetBracketSlots', target_slots,
        'tieResolutionPolicy', upper(coalesce(group_stage ->> 'tieResolutionPolicy', 'PERSISTED_DRAW_LOT'))
      ),
      'futureBracketTemplate', case when target_type = 'GROUPS_THEN_KNOCKOUT'
        then jsonb_build_object('targetSlots', target_slots, 'status', 'R6B_TEMPLATE_ONLY') else null end
    ),
    'operations', jsonb_build_object(
      'hardAvailabilityPolicy', jsonb_build_object('mode', 'required'),
      'schedulePreferencePolicy', jsonb_build_object('mode', 'preferred'),
      'schedulePolicy', jsonb_build_object(
        'format', 'ROUND_ROBIN', 'legs', legs,
        'matchDurationMinutes', duration_minutes,
        'requiredBufferMinutes', buffer_minutes,
        'minimumRestMinutes', minimum_rest_minutes,
        'homeAwayPolicy', case when legs = 2 then 'MIRRORED_SECOND_LEG' else 'BALANCED' end,
        'venueRequired', coalesce((group_stage ->> 'venueRequired')::boolean, false),
        'maximumHomeAwayStreak', 3, 'hardHomeAwayStreak', false,
        'windowStartsAt', nullif(configuration ->> 'startsAt', '') || 'T00:00:00Z',
        'windowEndsAt', nullif(configuration ->> 'endsAt', '') || 'T23:59:59Z',
        'rosterStatuses', jsonb_build_array('approved', 'locked'),
        'softPreferenceWeights', jsonb_build_object('day', 60, 'time', 30, 'homeAway', 10),
        'weeklyPattern', coalesce(group_stage -> 'weeklyPattern', '[]'::jsonb)
      ),
      'exceptionPolicy', jsonb_build_object(
        'postponementResponseDeadlineHours', coalesce(nullif(group_stage ->> 'postponementResponseDeadlineHours', '')::integer, 72),
        'postponementDeadlinePolicy', 'ESCALATE_TO_ORGANIZER',
        'organizerApprovalRequired', true, 'organizerCanInterveneAfterDeadline', true,
        'gracePeriodMinutes', coalesce(nullif(group_stage ->> 'gracePeriodMinutes', '')::integer, 15),
        'minimumRestHours', ceil(minimum_rest_minutes::numeric / 60)::integer,
        'maximumMatchDurationMinutes', duration_minutes + 120,
        'noShowOutcome', 'FORFEIT', 'noShowWinnerScore', 3, 'noShowLoserScore', 0,
        'resumptionPolicy', 'SAME_CANONICAL_MATCH',
        'stageWindowStart', nullif(configuration ->> 'startsAt', '') || 'T00:00:00Z',
        'stageWindowEnd', nullif(configuration ->> 'endsAt', '') || 'T23:59:59Z',
        'venuePolicy', jsonb_build_object('allowSavedVenue', true, 'allowVenueLabel', true, 'allowTbd', true),
        'resumptionEligibilityPolicy', jsonb_build_object(
          'allowOriginalSquad', true, 'allowReplacementForDocumentedInjury', false,
          'requireOriginalEligibility', true
        )
      ),
      'refereePolicy', jsonb_build_object(
        'usage', case upper(coalesce(configuration #>> '{referees,usage}', 'OPTIONAL'))
          when 'REQUIRED' then 'REQUIRED' when 'DISABLED' then 'NONE' else 'OPTIONAL' end,
        'role', 'MAIN_REFEREE',
        'proposerRoles', jsonb_build_array(
          'competition_owner', 'competition_director', 'competition_admin',
          'competition_referee_manager'
        ),
        'acceptanceIsSufficient', false, 'organizerConfirmationRequired', true,
        'responseDeadlineHours', 72, 'reconfirmAfterScheduleChange', true,
        'modalityRequired', true, 'serviceAreaRequired', true,
        'priorClubRelationshipRequired', false, 'replacementAllowed', true,
        'requiredBeforeReady', upper(coalesce(configuration #>> '{referees,usage}', 'OPTIONAL')) = 'REQUIRED',
        'authority', jsonb_build_object('reportCards', true, 'reportIncidents', true, 'observeScore', true),
        'fee', jsonb_build_object('mode', 'NEGOTIABLE', 'travelIncluded', false, 'publicConsent', false, 'paymentProcessing', false)
      ),
      'matchGeneration', true,
      'bracketProgression', false
    ),
    'results', jsonb_build_object(
      'scoringPolicy', jsonb_build_object(
        'pointsForWin', points_win, 'pointsForDraw', points_draw, 'pointsForLoss', points_loss
      ),
      'tieBreakCriteria', coalesce(group_stage -> 'tieBreakCriteria', jsonb_build_array(
        'GOAL_DIFFERENCE', 'GOALS_FOR', 'WINS', 'PERSISTED_DRAW_LOT'
      )),
      'scorerDetailPolicy', upper(coalesce(group_stage ->> 'scorerDetailPolicy', 'OPTIONAL')),
      'allowUnknownScorer', coalesce((group_stage ->> 'allowUnknownScorer')::boolean, false),
      'confirmationPolicy', jsonb_build_object(
        'mode', 'BILATERAL',
        'responseDeadlineHours', coalesce(nullif(group_stage ->> 'responseDeadlineHours', '')::integer, 72),
        'autoOfficialAfterConfirmation', coalesce((group_stage ->> 'autoOfficialAfterConfirmation')::boolean, false)
      ),
      'standingsPolicy', jsonb_build_object(
        'allowSharedPositions', coalesce((group_stage ->> 'allowSharedPositions')::boolean, false)
      ),
      'publicationPolicy', jsonb_build_object('resultsPublic', false, 'standingsPublic', false)
    ),
    'discipline', jsonb_build_object(
      'enabled', coalesce((configuration #>> '{discipline,enabled}')::boolean, false),
      'policy', private.pachanga_competition_discipline_default_policy_v1()
    ),
    'governance', jsonb_build_object('registrationMode', 'INVITE_ONLY', 'organizerConsentRequired', true),
    'publication', jsonb_build_object(
      'competitionVisibility', 'PRIVATE', 'drawAuditVisibility', 'PARTICIPANTS_ONLY',
      'calendarVisibility', 'PARTICIPANTS_ONLY', 'standingsVisibility', 'PARTICIPANTS_ONLY',
      'indexing', 'NOINDEX_NOFOLLOW'
    ),
    'futureCapabilities', jsonb_build_object(
      'tournamentMatches', true, 'bracketProgression', false, 'results', true,
      'standings', true, 'payments', false, 'prizes', false,
      'publicRegistration', false, 'aiAuthority', false
    ),
    'draw', jsonb_build_object(
      'target', target_type, 'mode', draw_mode,
      'seedModes', jsonb_build_array('SERVER_SECURE_RANDOM', 'CUSTOM_PUBLIC_SEED'),
      'algorithmVersion', 'tournament-draw-v1.0.0'
    )
  );
  perform private.pachanga_validate_competition_rule_document_v1('competition_rules.v1', document);
  return document;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'TOURNAMENT_CONFIGURATION_INVALID' using errcode = '22023';
end;
$$;

revoke all on function private.pachanga_tournament_rule_document_v1(jsonb, integer)
  from public, anon, authenticated;
