-- Pachangas IQ R6B: narrow Tournament adapter over the canonical R4B scheduler.
-- The public R4B command remains LEAGUE-only; only this SECURITY DEFINER
-- orchestrator may open the scoped Tournament path inside its transaction.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.pachanga_tournament_group_schedule_plans (
  id uuid primary key default gen_random_uuid(),
  group_stage_state_id uuid not null references public.pachanga_tournament_group_stage_states(id) on delete restrict,
  preparation_id uuid not null references public.pachanga_tournament_group_stage_preparations(id) on delete restrict,
  competition_group_id uuid not null references public.pachanga_competition_groups(id) on delete restrict,
  schedule_plan_id uuid not null references public.pachanga_competition_schedule_plans(id) on delete restrict,
  group_order smallint not null,
  expected_round_count smallint not null,
  expected_fixture_count smallint not null,
  status text not null default 'draft',
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (group_order between 1 and 16),
  check (expected_round_count between 1 and 62),
  check (expected_fixture_count between 1 and 992),
  check (status in ('draft', 'slots_ready', 'generated', 'validated', 'published', 'cancelled')),
  check (revision >= 1),
  unique (preparation_id, competition_group_id),
  unique (schedule_plan_id)
);

create table public.pachanga_tournament_group_schedule_validations (
  id uuid primary key,
  group_stage_state_id uuid not null references public.pachanga_tournament_group_stage_states(id) on delete restrict,
  preparation_id uuid not null references public.pachanga_tournament_group_stage_preparations(id) on delete restrict,
  status text not null,
  plan_count smallint not null,
  round_count integer not null,
  fixture_count integer not null,
  unassigned_fixture_count integer not null,
  hard_violation_count integer not null,
  validation_snapshot jsonb not null,
  input_checksum text not null,
  checksum text not null,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  operation_id uuid not null unique,
  validated_by uuid not null references auth.users(id) on delete restrict,
  validated_at timestamptz not null default clock_timestamp(),
  check (status in ('VALID', 'INVALID', 'STALE_INPUT')),
  check (plan_count between 1 and 16),
  check (round_count >= 1 and fixture_count >= 1),
  check (unassigned_fixture_count >= 0 and hard_violation_count >= 0),
  check (jsonb_typeof(validation_snapshot) = 'object'),
  check (length(input_checksum) = 64 and length(checksum) = 64),
  check (revision = 1),
  unique (group_stage_state_id, input_checksum, checksum)
);

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_tournament_group_schedule_plans',
    'pachanga_tournament_group_schedule_validations'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

create trigger guard_pachanga_tournament_group_schedule_validation_v1
before update or delete on public.pachanga_tournament_group_schedule_validations
for each row execute function private.pachanga_tournament_guard_immutable_v1();

create or replace function private.pachanga_league_schedule_plan_scope_v1(target_plan_id uuid)
returns public.pachanga_competition_schedule_plans
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_competition_schedule_plans%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare stage_row public.pachanga_competition_stages%rowtype;
declare tournament_adapter boolean := false;
begin
  select * into selected
  from public.pachanga_competition_schedule_plans plans
  where plans.id = target_plan_id;
  if not found then raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = selected.competition_id;
  if competition_row.competition_type = 'TOURNAMENT' then
    tournament_adapter := current_setting('pachangas.r6b_orchestrator', true) = 'on'
      or exists (
        select 1
        from public.pachanga_tournament_group_schedule_plans mappings
        join public.pachanga_tournament_group_stage_states states
          on states.id = mappings.group_stage_state_id
        where mappings.schedule_plan_id = selected.id
          and states.competition_id = selected.competition_id
          and states.stage_id = selected.stage_id
          and states.rule_revision_id = selected.rule_revision_id
          and states.status <> 'cancelled'
      );
    if not tournament_adapter then
      raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
  elsif competition_row.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = selected.edition_id;
  select * into stage_row from public.pachanga_competition_stages stages
  where stages.id = selected.stage_id;
  if edition_row.competition_id <> selected.competition_id
     or stage_row.edition_id <> selected.edition_id then
    raise exception 'SCHEDULE_SCOPE_MISMATCH' using errcode = '22023';
  end if;
  if competition_row.competition_type = 'TOURNAMENT' and stage_row.stage_type <> 'GROUP_STAGE' then
    raise exception 'TOURNAMENT_GROUP_STAGE_REQUIRED' using errcode = '22023';
  end if;
  if stage_row.stage_type not in ('LEAGUE_STAGE', 'GROUP_STAGE', 'SPLIT') then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if selected.division_id is not null and not exists (
    select 1 from public.pachanga_competition_divisions divisions
    where divisions.id = selected.division_id and divisions.stage_id = selected.stage_id
  ) then raise exception 'SCHEDULE_DIVISION_SCOPE_MISMATCH' using errcode = '22023'; end if;
  if selected.competition_group_id is null or not exists (
    select 1 from public.pachanga_competition_groups groups
    where groups.id = selected.competition_group_id
      and groups.stage_id = selected.stage_id
      and (selected.division_id is null or groups.division_id = selected.division_id)
  ) then raise exception 'SCHEDULE_GROUP_SCOPE_MISMATCH' using errcode = '22023'; end if;
  perform private.pachanga_league_schedule_policy_v1(selected.rule_revision_id);
  return selected;
end;
$$;

revoke all on function private.pachanga_league_schedule_plan_scope_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_schedule_assert_authority_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare organizer_id uuid;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  if competition_row.competition_type = 'TOURNAMENT' then
    if current_setting('pachangas.r6b_orchestrator', true) <> 'on' then
      raise exception 'TOURNAMENT_GROUP_STAGE_COMMAND_REQUIRED' using errcode = '42501';
    end if;
    if not private.pachanga_tournament_can_v1(
      target_competition_id,
      target_actor_id,
      case when target_capability = 'schedule_publish' then 'schedule_publish' else 'schedule_manage' end
    ) then raise exception 'TOURNAMENT_SCHEDULE_MANAGER_REQUIRED' using errcode = '42501'; end if;
    return;
  end if;
  if competition_row.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if not private.pachanga_competition_can_v1(
    target_competition_id, target_actor_id, target_capability
  ) then raise exception 'COMPETITION_SCHEDULE_MANAGER_REQUIRED' using errcode = '42501'; end if;
  organizer_id := case when competition_row.organizer_kind = 'CLUB'
    then competition_row.organizer_club_id else competition_row.organizer_group_id end;
  if not (
    private.pachanga_competition_active_entitlement_v2(
      competition_row.organizer_kind, organizer_id, 'competition_schedule'
    ) or private.pachanga_competition_active_entitlement_v2(
      competition_row.organizer_kind, organizer_id, 'competition_manage'
    )
  ) then raise exception 'COMPETITION_SCHEDULE_ENTITLEMENT_REQUIRED' using errcode = '42501'; end if;
end;
$$;

revoke all on function private.pachanga_league_schedule_assert_authority_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_can_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare actor_role text;
declare organizer_id uuid;
declare participant_reader boolean := false;
begin
  if target_actor_id is null then return false; end if;
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id
    and competitions.competition_type = 'TOURNAMENT'
    and competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1';
  if not found then return false; end if;
  if private.pachanga_platform_role_for_user_v1(target_actor_id)
     in ('platform_owner', 'platform_admin') then return true; end if;
  if target_capability in ('read', 'schedule_read', 'results_read', 'standings_read') then
    select exists (
      select 1
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      where entries.competition_id = target_competition_id
        and entries.status in ('accepted', 'active', 'completed')
        and (
          teams.owner_id = target_actor_id
          or exists (
            select 1 from public.pachanga_group_members members
            where members.group_id = teams.id and members.user_id = target_actor_id
          )
        )
    ) into participant_reader;
  end if;
  actor_role := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
  if target_capability in ('read', 'schedule_read', 'results_read', 'standings_read')
     and (participant_reader or actor_role is not null) then return true; end if;
  organizer_id := coalesce(competition_row.organizer_group_id, competition_row.organizer_club_id);
  if private.pachanga_tournament_active_bundle_id_v1(
       competition_row.organizer_kind, organizer_id
     ) is null then return false; end if;
  if actor_role = 'competition_owner' then return true; end if;
  return case actor_role
    when 'competition_director' then target_capability in (
      'read', 'manage', 'authoring', 'participants_manage', 'draw_read',
      'draw_manage', 'draw_validate', 'draw_publish', 'schedule_read',
      'schedule_manage', 'schedule_publish', 'results_read', 'results_manage',
      'standings_read', 'standings_manage', 'operations_manage',
      'qualification_manage', 'qualification_publish', 'bracket_manage',
      'bracket_publish'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'participants_manage', 'draw_read', 'draw_manage',
      'draw_validate', 'draw_publish', 'schedule_read', 'schedule_manage',
      'schedule_publish', 'results_read', 'results_manage', 'standings_read',
      'standings_manage', 'operations_manage', 'qualification_manage',
      'qualification_publish', 'bracket_manage', 'bracket_publish'
    )
    when 'competition_draw_manager' then target_capability in (
      'read', 'draw_read', 'draw_manage', 'draw_validate', 'draw_publish'
    )
    when 'competition_schedule_manager' then target_capability in (
      'read', 'schedule_read', 'schedule_manage', 'schedule_publish'
    )
    when 'competition_result_manager' then target_capability in (
      'read', 'results_read', 'results_manage', 'standings_read'
    )
    when 'competition_standings_manager' then target_capability in (
      'read', 'results_read', 'standings_read', 'standings_manage',
      'qualification_manage', 'qualification_publish', 'bracket_manage',
      'bracket_publish'
    )
    when 'competition_operations_manager' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read', 'operations_manage'
    )
    when 'competition_registration_manager' then target_capability in ('read', 'participants_manage')
    when 'rules_manager' then target_capability in ('read', 'authoring', 'draw_read')
    when 'viewer' then target_capability in (
      'read', 'draw_read', 'schedule_read', 'results_read', 'standings_read'
    )
    else false
  end;
end;
$$;

revoke all on function private.pachanga_tournament_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

comment on function private.pachanga_league_schedule_assert_authority_v1(uuid,uuid,text) is
  'R4B remains public-LEAGUE-only. Tournament access requires the transaction-local R6B orchestrator marker.';

create or replace function private.pachanga_league_assert_competition_v1(target_competition_id uuid)
returns public.pachanga_competitions
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_competitions%rowtype;
begin
  select * into selected
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected.competition_type = 'TOURNAMENT' then
    if selected.product_key <> 'TOURNAMENT_PRIVATE_BETA_V1'
       or not private.pachanga_tournament_can_v1(selected.id, auth.uid(), 'read') then
      raise exception 'TOURNAMENT_ROSTER_ACCESS_FORBIDDEN' using errcode = '42501';
    end if;
  elsif selected.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if selected.status <> 'draft' then
    raise exception 'COMPETITION_NOT_DRAFT' using errcode = '22023';
  end if;
  return selected;
end;
$$;

revoke all on function private.pachanga_league_assert_competition_v1(uuid)
  from public, anon, authenticated;

comment on function private.pachanga_league_assert_competition_v1(uuid) is
  'R4A roster authority is shared with invite-only Tournament entries; public Tournament registration remains disabled by RuleRevision.';

create or replace function private.pachanga_tournament_group_snapshot_v1(
  target_stage_id uuid,
  target_draw_revision_id uuid,
  target_rule_revision_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'groupId', groups.id,
    'groupOrder', groups.group_order,
    'name', groups.name,
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'entryId', entries.id,
        'teamId', entries.team_id,
        'teamName', teams.name,
        'placementId', placements.id,
        'slotNumber', placements.slot_number,
        'membershipId', memberships.id,
        'entryRevision', entries.revision,
        'membershipRevision', memberships.revision,
        'rosterId', rosters.id,
        'rosterRevisionId', rosters.current_revision_id,
        'rosterRevision', rosters.revision
      ) order by placements.slot_number, entries.id)
      from public.pachanga_competition_stage_memberships memberships
      join public.pachanga_competition_entries entries on entries.id = memberships.entry_id
      join public.pachanga_groups teams on teams.id = entries.team_id
      join public.pachanga_competition_draw_placements placements
        on placements.draw_revision_id = target_draw_revision_id
       and placements.entry_id = entries.id
       and placements.group_number = groups.group_order
      left join public.pachanga_competition_rosters rosters on rosters.entry_id = entries.id
      where memberships.stage_id = target_stage_id
        and memberships.competition_group_id = groups.id
        and memberships.rule_revision_id = target_rule_revision_id
        and memberships.status = 'active'
        and entries.status in ('accepted', 'active')
    ), '[]'::jsonb)
  ) order by groups.group_order, groups.id), '[]'::jsonb)
  from public.pachanga_competition_groups groups
  where groups.stage_id = target_stage_id;
$$;

revoke all on function private.pachanga_tournament_group_snapshot_v1(uuid,uuid,uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_stage_snapshot_v1(
  target_competition_id uuid,
  target_include_private boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare preparation_row public.pachanga_tournament_group_stage_preparations%rowtype;
declare result jsonb;
begin
  select * into state_row
  from public.pachanga_tournament_group_stage_states states
  where states.competition_id = target_competition_id
  order by states.server_sequence desc, states.id desc
  limit 1;
  if not found then return null; end if;
  select * into preparation_row
  from public.pachanga_tournament_group_stage_preparations preparations
  where preparations.id = state_row.current_preparation_id;
  result := jsonb_build_object(
    'state', jsonb_build_object(
      'id', state_row.id,
      'competitionId', state_row.competition_id,
      'editionId', state_row.edition_id,
      'categoryId', state_row.category_id,
      'stageId', state_row.stage_id,
      'drawPlanId', state_row.draw_plan_id,
      'drawRevisionId', state_row.draw_revision_id,
      'participantFreezeId', state_row.participant_freeze_id,
      'ruleRevisionId', state_row.rule_revision_id,
      'preparationId', state_row.current_preparation_id,
      'qualificationSnapshotId', state_row.current_qualification_snapshot_id,
      'bracketTemplateId', state_row.current_bracket_template_id,
      'status', state_row.status,
      'groupCount', state_row.group_count,
      'entryCount', state_row.entry_count,
      'fixtureCount', state_row.fixture_count,
      'officialFixtureCount', state_row.official_fixture_count,
      'revision', state_row.revision,
      'serverSequence', state_row.server_sequence,
      'completedAt', state_row.completed_at,
      'updatedAt', state_row.updated_at
    ),
    'groups', preparation_row.group_snapshot,
    'schedulePlans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', mappings.id,
        'groupId', mappings.competition_group_id,
        'groupOrder', mappings.group_order,
        'schedulePlanId', mappings.schedule_plan_id,
        'status', mappings.status,
        'expectedRounds', mappings.expected_round_count,
        'expectedFixtures', mappings.expected_fixture_count,
        'revision', mappings.revision,
        'schedule', private.pachanga_league_schedule_revision_snapshot_v1(
          mappings.schedule_plan_id, target_include_private
        )
      ) order by mappings.group_order, mappings.id)
      from public.pachanga_tournament_group_schedule_plans mappings
      where mappings.group_stage_state_id = state_row.id
    ), '[]'::jsonb),
    'revision', state_row.revision,
    'serverSequence', state_row.server_sequence,
    'updatedAt', state_row.updated_at
  );
  if target_include_private then
    result := result || jsonb_build_object(
      'preparation', jsonb_build_object(
        'id', preparation_row.id,
        'inputChecksum', preparation_row.input_checksum,
        'drawChecksum', preparation_row.draw_checksum,
        'participantChecksum', preparation_row.participant_checksum,
        'groupChecksum', preparation_row.group_checksum,
        'ruleChecksum', preparation_row.rule_checksum,
        'schedulePolicy', preparation_row.schedule_policy_snapshot,
        'qualificationPolicy', preparation_row.qualification_policy_snapshot,
        'preparedAt', preparation_row.prepared_at
      )
    );
  end if;
  return result;
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_snapshot_v1(uuid,boolean)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_stage_assert_current_v1(
  target_competition_id uuid
)
returns public.pachanga_tournament_group_stage_states
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare revision_row public.pachanga_competition_draw_revisions%rowtype;
declare freeze_row public.pachanga_competition_participant_freezes%rowtype;
declare preparation_row public.pachanga_tournament_group_stage_preparations%rowtype;
declare current_entry_ids uuid[];
declare current_group_snapshot jsonb;
declare current_group_checksum text;
begin
  select * into state_row
  from public.pachanga_tournament_group_stage_states states
  where states.competition_id = target_competition_id;
  if not found then raise exception 'TOURNAMENT_GROUP_STAGE_NOT_PREPARED' using errcode = 'P0002'; end if;
  if state_row.status = 'cancelled' then
    raise exception 'TOURNAMENT_GROUP_STAGE_CANCELLED' using errcode = '22023';
  end if;
  select * into plan_row from public.pachanga_competition_draw_plans plans
  where plans.id = state_row.draw_plan_id;
  select * into revision_row from public.pachanga_competition_draw_revisions revisions
  where revisions.id = state_row.draw_revision_id;
  select * into freeze_row from public.pachanga_competition_participant_freezes freezes
  where freezes.id = state_row.participant_freeze_id;
  select * into preparation_row
  from public.pachanga_tournament_group_stage_preparations preparations
  where preparations.id = state_row.current_preparation_id;
  if plan_row.status <> 'published'
     or plan_row.current_revision_id is distinct from state_row.draw_revision_id
     or plan_row.participant_freeze_id is distinct from state_row.participant_freeze_id
     or plan_row.rule_revision_id is distinct from state_row.rule_revision_id
     or revision_row.validation_status <> 'VALID'
     or freeze_row.rule_revision_id is distinct from state_row.rule_revision_id then
    raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
  end if;
  select coalesce(array_agg(entries.id order by entries.id), '{}'::uuid[])
  into current_entry_ids
  from public.pachanga_competition_entries entries
  where entries.competition_id = state_row.competition_id
    and entries.edition_id = state_row.edition_id
    and entries.status in ('accepted', 'active');
  if current_entry_ids <> (select array_agg(entry_id order by entry_id) from unnest(freeze_row.entry_ids) entry_id) then
    raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
  end if;
  current_group_snapshot := private.pachanga_tournament_group_snapshot_v1(
    state_row.stage_id, state_row.draw_revision_id, state_row.rule_revision_id
  );
  current_group_checksum := private.pachanga_tournament_json_checksum_v1(current_group_snapshot);
  if current_group_checksum <> preparation_row.group_checksum then
    raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
  end if;
  return state_row;
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_assert_current_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_stage_prepare_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_competition_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare stage_row public.pachanga_competition_stages%rowtype;
declare category_row public.pachanga_competition_categories%rowtype;
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare revision_row public.pachanga_competition_draw_revisions%rowtype;
declare freeze_row public.pachanga_competition_participant_freezes%rowtype;
declare rule_row public.pachanga_competition_rule_revisions%rowtype;
declare policy jsonb;
declare group_snapshot jsonb;
declare participant_snapshot jsonb;
declare group_checksum text;
declare input_checksum text;
declare current_entry_ids uuid[];
declare state_id uuid := private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id, 'group-stage-state'
);
declare preparation_id uuid := private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id, 'group-stage-preparation'
);
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare group_item jsonb;
declare group_entry_count integer;
declare legs integer;
declare even_count integer;
declare expected_rounds integer;
declare expected_fixtures integer;
declare schedule_plan_id uuid;
declare schedule_inputs jsonb;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id for update;
  if not found or competition_row.competition_type <> 'TOURNAMENT'
     or competition_row.product_key <> 'TOURNAMENT_PRIVATE_BETA_V1' then
    raise exception 'TOURNAMENT_NOT_FOUND' using errcode = 'P0002';
  end if;
  if not private.pachanga_tournament_can_v1(target_competition_id, target_actor_id, 'schedule_manage') then
    raise exception 'TOURNAMENT_SCHEDULE_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  select * into plan_row
  from public.pachanga_competition_draw_plans plans
  where plans.competition_id = target_competition_id and plans.status = 'published'
  order by plans.server_sequence desc, plans.id desc limit 1 for update;
  if not found or plan_row.target_type not in ('GROUP_ASSIGNMENT', 'GROUPS_THEN_KNOCKOUT') then
    raise exception 'TOURNAMENT_PUBLISHED_GROUP_DRAW_REQUIRED' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('r6b-stage:' || plan_row.stage_id::text, 91410));
  if exists (
    select 1 from public.pachanga_tournament_group_stage_states states
    where states.competition_id = target_competition_id and states.stage_id = plan_row.stage_id
  ) then raise exception 'TOURNAMENT_GROUP_STAGE_ALREADY_PREPARED' using errcode = 'PT409'; end if;
  select * into revision_row from public.pachanga_competition_draw_revisions revisions
  where revisions.id = plan_row.current_revision_id and revisions.validation_status = 'VALID';
  select * into freeze_row from public.pachanga_competition_participant_freezes freezes
  where freezes.id = plan_row.participant_freeze_id;
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = plan_row.edition_id for update;
  select * into stage_row from public.pachanga_competition_stages stages
  where stages.id = plan_row.stage_id;
  select * into rule_row from public.pachanga_competition_rule_revisions revisions
  where revisions.id = plan_row.rule_revision_id and revisions.status = 'frozen';
  select * into category_row from public.pachanga_competition_categories categories
  where categories.edition_id = plan_row.edition_id
    and categories.rule_revision_id = plan_row.rule_revision_id
    and categories.status = 'active'
  order by categories.server_sequence desc, categories.id desc limit 1;
  if revision_row.id is null or freeze_row.id is null or rule_row.id is null
     or category_row.id is null or stage_row.stage_type <> 'GROUP_STAGE'
     or edition_row.rule_revision_id is distinct from plan_row.rule_revision_id
     or stage_row.rule_revision_id is distinct from plan_row.rule_revision_id
     or freeze_row.rule_revision_id is distinct from plan_row.rule_revision_id then
    raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
  end if;
  policy := private.pachanga_tournament_group_stage_policy_v1(plan_row.rule_revision_id);
  legs := (policy #>> '{schedulePolicy,legs}')::integer;
  update public.pachanga_competition_entries entries set
    rule_revision_id = plan_row.rule_revision_id,
    revision = entries.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where entries.id = any(freeze_row.entry_ids)
    and entries.competition_id = target_competition_id
    and entries.edition_id = plan_row.edition_id
    and entries.status in ('accepted', 'active')
    and entries.rule_revision_id is distinct from plan_row.rule_revision_id;
  select coalesce(array_agg(entries.id order by entries.id), '{}'::uuid[])
  into current_entry_ids
  from public.pachanga_competition_entries entries
  where entries.competition_id = target_competition_id
    and entries.edition_id = plan_row.edition_id
    and entries.status in ('accepted', 'active');
  if current_entry_ids <> (select array_agg(entry_id order by entry_id) from unnest(freeze_row.entry_ids) entry_id)
     or cardinality(current_entry_ids) <> plan_row.slot_count then
    raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from public.pachanga_competition_draw_placements placements
    where placements.draw_revision_id = revision_row.id
      and (
        placements.group_number is null
        or not exists (
          select 1
          from public.pachanga_competition_groups groups
          join public.pachanga_competition_stage_memberships memberships
            on memberships.competition_group_id = groups.id
           and memberships.entry_id = placements.entry_id
           and memberships.status = 'active'
          where groups.stage_id = plan_row.stage_id
            and groups.group_order = placements.group_number
            and memberships.rule_revision_id = plan_row.rule_revision_id
        )
      )
  ) or exists (
    select memberships.entry_id
    from public.pachanga_competition_stage_memberships memberships
    where memberships.stage_id = plan_row.stage_id and memberships.status = 'active'
    group by memberships.entry_id having count(*) <> 1
  ) then raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409'; end if;
  if exists (
    select 1 from unnest(freeze_row.entry_ids) entry_id
    where not exists (
      select 1
      from public.pachanga_competition_rosters rosters
      join public.pachanga_competition_roster_revisions roster_revisions
        on roster_revisions.id = rosters.current_revision_id
      where rosters.entry_id = entry_id
        and rosters.rule_revision_id = plan_row.rule_revision_id
        and rosters.status in ('approved', 'locked')
        and coalesce((roster_revisions.eligibility_summary ->> 'pending')::integer, 0) = 0
        and coalesce((roster_revisions.eligibility_summary ->> 'reviewRequired')::integer, 0) = 0
        and coalesce((roster_revisions.eligibility_summary ->> 'ineligible')::integer, 0) = 0
        and coalesce((roster_revisions.eligibility_summary ->> 'expired')::integer, 0) = 0
    )
  ) then raise exception 'TOURNAMENT_GROUP_STAGE_ROSTERS_REQUIRED' using errcode = '22023'; end if;
  participant_snapshot := private.pachanga_tournament_participant_snapshot_v1(
    target_competition_id, plan_row.edition_id, plan_row.stage_id
  );
  group_snapshot := private.pachanga_tournament_group_snapshot_v1(
    plan_row.stage_id, revision_row.id, plan_row.rule_revision_id
  );
  if jsonb_array_length(group_snapshot) <> plan_row.group_count then
    raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
  end if;
  group_checksum := private.pachanga_tournament_json_checksum_v1(group_snapshot);
  input_checksum := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'competitionId', target_competition_id,
    'drawPlanId', plan_row.id,
    'drawRevisionId', revision_row.id,
    'drawChecksum', revision_row.result_checksum,
    'participantFreezeId', freeze_row.id,
    'participantChecksum', freeze_row.checksum,
    'groupChecksum', group_checksum,
    'ruleRevisionId', rule_row.id,
    'ruleChecksum', rule_row.checksum,
    'policy', policy
  ));
  update public.pachanga_competition_editions editions set
    status = 'registration_closed',
    registration_mode = 'CLOSED',
    registration_closed_at = coalesce(editions.registration_closed_at, clock_timestamp()),
    revision = editions.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where editions.id = edition_row.id and editions.status in ('draft', 'registration_open');
  insert into public.pachanga_tournament_group_stage_states(
    id, competition_id, edition_id, category_id, stage_id, draw_plan_id,
    draw_revision_id, participant_freeze_id, rule_revision_id, status,
    group_count, entry_count, revision, server_sequence, created_by, updated_by
  ) values (
    state_id, target_competition_id, plan_row.edition_id, category_row.id,
    plan_row.stage_id, plan_row.id, revision_row.id, freeze_row.id,
    plan_row.rule_revision_id, 'prepared', plan_row.group_count,
    cardinality(current_entry_ids), 1, target_server_sequence,
    target_actor_id, target_actor_id
  ) returning * into state_row;
  insert into public.pachanga_tournament_group_stage_preparations(
    id, group_stage_state_id, competition_id, edition_id, category_id, stage_id,
    draw_plan_id, draw_revision_id, participant_freeze_id, rule_revision_id,
    draw_checksum, participant_checksum, group_checksum, rule_checksum,
    input_checksum, participant_snapshot, group_snapshot,
    schedule_policy_snapshot, qualification_policy_snapshot,
    group_count, entry_count, operation_id, prepared_by
  ) values (
    preparation_id, state_id, target_competition_id, plan_row.edition_id,
    category_row.id, plan_row.stage_id, plan_row.id, revision_row.id,
    freeze_row.id, plan_row.rule_revision_id, revision_row.result_checksum,
    freeze_row.checksum, group_checksum, rule_row.checksum,
    input_checksum, participant_snapshot, group_snapshot,
    policy -> 'schedulePolicy', policy -> 'qualificationPolicy',
    plan_row.group_count, cardinality(current_entry_ids), target_operation_id,
    target_actor_id
  );
  update public.pachanga_tournament_group_stage_states states
  set current_preparation_id = preparation_id
  where states.id = state_id;
  perform set_config('pachangas.r6b_orchestrator', 'on', true);
  for group_item in select value from jsonb_array_elements(group_snapshot)
  loop
    group_entry_count := jsonb_array_length(group_item -> 'entries');
    if group_entry_count < 2 or group_entry_count > 32 then
      raise exception 'TOURNAMENT_GROUP_SIZE_NOT_SCHEDULABLE' using errcode = '22023';
    end if;
    even_count := case when group_entry_count % 2 = 0 then group_entry_count else group_entry_count + 1 end;
    expected_rounds := (even_count - 1) * legs;
    expected_fixtures := (group_entry_count * (group_entry_count - 1) / 2) * legs;
    schedule_plan_id := private.pachanga_tournament_group_operation_entity_id_v1(
      target_operation_id, 'group-schedule-plan:' || (group_item ->> 'groupId')
    );
    insert into public.pachanga_competition_schedule_plans(
      id, competition_id, edition_id, category_id, stage_id,
      competition_group_id, rule_revision_id, engine_version, legs,
      entry_count, status, revision, server_sequence, created_by
    ) values (
      schedule_plan_id, target_competition_id, plan_row.edition_id,
      category_row.id, plan_row.stage_id, (group_item ->> 'groupId')::uuid,
      plan_row.rule_revision_id, 'league-round-robin-v1', legs,
      group_entry_count, 'draft', 1,
      nextval('private.pachanga_competition_sequence'), target_actor_id
    );
    insert into public.pachanga_tournament_group_schedule_plans(
      id, group_stage_state_id, preparation_id, competition_group_id,
      schedule_plan_id, group_order, expected_round_count,
      expected_fixture_count, status, server_sequence, created_by
    ) values (
      private.pachanga_tournament_group_operation_entity_id_v1(
        target_operation_id, 'group-schedule-mapping:' || (group_item ->> 'groupId')
      ), state_id, preparation_id, (group_item ->> 'groupId')::uuid,
      schedule_plan_id, (group_item ->> 'groupOrder')::smallint,
      expected_rounds, expected_fixtures, 'draft',
      nextval('private.pachanga_competition_sequence'), target_actor_id
    );
    schedule_inputs := private.pachanga_league_schedule_inputs_v1(
      schedule_plan_id, 'r6b-plan:' || schedule_plan_id::text
    );
    if (schedule_inputs ->> 'entryCount')::integer <> group_entry_count then
      raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
    end if;
  end loop;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true);
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_prepare_v1(uuid,uuid,uuid,bigint)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_schedule_resource_key_v1(
  target_venue_id uuid,
  target_venue_label text
)
returns text
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select case
    when target_venue_id is not null then 'venue:' || target_venue_id::text
    when nullif(trim(target_venue_label), '') is not null then
      'label:' || encode(extensions.digest(convert_to(
        lower(regexp_replace(trim(target_venue_label), '\s+', ' ', 'g')),
        'UTF8'
      ), 'sha256'), 'hex')
    else null
  end;
$$;

revoke all on function private.pachanga_tournament_schedule_resource_key_v1(uuid,text)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_schedule_create_slots_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_competition_id uuid,
  target_group_id uuid,
  target_slots jsonb,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare mapping_row public.pachanga_tournament_group_schedule_plans%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare slot_item jsonb;
declare slot_id uuid;
declare starts_value timestamptz;
declare ends_value timestamptz;
declare timezone_value text;
declare venue_id_value uuid;
declare venue_label_value text;
declare resource_key_value text;
declare created_ids jsonb := '[]'::jsonb;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  if jsonb_typeof(target_slots) <> 'array'
     or jsonb_array_length(target_slots) < 1
     or jsonb_array_length(target_slots) > 1000 then
    raise exception 'TOURNAMENT_GROUP_SLOTS_INVALID' using errcode = '22023';
  end if;
  select * into mapping_row
  from public.pachanga_tournament_group_schedule_plans mappings
  where mappings.group_stage_state_id = state_row.id
    and mappings.competition_group_id = target_group_id
  for update;
  if not found then raise exception 'TOURNAMENT_GROUP_SCHEDULE_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into plan_row from public.pachanga_competition_schedule_plans plans
  where plans.id = mapping_row.schedule_plan_id for update;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
  end if;
  perform set_config('pachangas.r6b_orchestrator', 'on', true);
  for slot_item in select value from jsonb_array_elements(target_slots)
  loop
    if jsonb_typeof(slot_item) <> 'object'
       or slot_item ?| array['resourceKey', 'createdBy', 'competitionId', 'schedulePlanId'] then
      raise exception 'TOURNAMENT_GROUP_SLOT_SERVER_FIELDS_FORBIDDEN' using errcode = '22023';
    end if;
    begin
      starts_value := (slot_item ->> 'startsAt')::timestamptz;
      ends_value := (slot_item ->> 'endsAt')::timestamptz;
      venue_id_value := nullif(slot_item ->> 'venueId', '')::uuid;
    exception when others then
      raise exception 'TOURNAMENT_GROUP_SLOT_INVALID' using errcode = '22023';
    end;
    timezone_value := trim(coalesce(slot_item ->> 'timezone', ''));
    venue_label_value := nullif(left(trim(coalesce(slot_item ->> 'venueLabel', '')), 160), '');
    if starts_value is null or ends_value is null or ends_value <= starts_value
       or not exists (
         select 1 from pg_catalog.pg_timezone_names zones where zones.name = timezone_value
       ) then raise exception 'TOURNAMENT_GROUP_SLOT_INVALID' using errcode = '22023'; end if;
    if starts_value < statement_timestamp() - interval '1 day'
       or ends_value > statement_timestamp() + interval '3 years' then
      raise exception 'TOURNAMENT_GROUP_SLOT_RANGE_INVALID' using errcode = '22023';
    end if;
    resource_key_value := private.pachanga_tournament_schedule_resource_key_v1(
      venue_id_value, venue_label_value
    );
    slot_id := private.pachanga_tournament_group_operation_entity_id_v1(
      target_operation_id,
      'group-slot:' || target_group_id::text || ':' || jsonb_array_length(created_ids)::text
    );
    insert into public.pachanga_competition_schedule_slots(
      id, competition_id, edition_id, stage_id, division_id,
      competition_group_id, starts_at, ends_at, timezone, venue_id,
      venue_label, resource_key, status, revision, server_sequence, created_by
    ) values (
      slot_id, plan_row.competition_id, plan_row.edition_id, plan_row.stage_id,
      plan_row.division_id, plan_row.competition_group_id, starts_value,
      ends_value, timezone_value, venue_id_value, venue_label_value,
      resource_key_value, 'available', 1,
      nextval('private.pachanga_competition_sequence'), target_actor_id
    );
    created_ids := created_ids || jsonb_build_array(slot_id);
  end loop;
  update public.pachanga_competition_schedule_plans plans set
    status = case when plans.status = 'validated' then 'generated' else plans.status end,
    revision = plans.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where plans.id = plan_row.id;
  update public.pachanga_tournament_group_schedule_plans mappings set
    status = 'slots_ready',
    revision = mappings.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where mappings.id = mapping_row.id;
  update public.pachanga_tournament_group_stage_states states set
    status = 'scheduling', revision = states.revision + 1,
    server_sequence = target_server_sequence, updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object('createdSlotIds', created_ids);
exception when exclusion_violation then
  raise exception 'SCHEDULE_SLOT_RESOURCE_CONFLICT' using errcode = 'PT409';
end;
$$;

revoke all on function private.pachanga_tournament_group_schedule_create_slots_v1(
  uuid,uuid,uuid,uuid,jsonb,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_schedule_generate_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_competition_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare mapping_row public.pachanga_tournament_group_schedule_plans%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare generated_revision_id uuid;
declare input_snapshot jsonb;
declare seed_value text;
declare generated jsonb := '[]'::jsonb;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  perform set_config('pachangas.r6b_orchestrator', 'on', true);
  for mapping_row in
    select mappings.*
    from public.pachanga_tournament_group_schedule_plans mappings
    where mappings.group_stage_state_id = state_row.id
      and mappings.status not in ('published', 'cancelled')
    order by mappings.group_order, mappings.id
    for update
  loop
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = mapping_row.schedule_plan_id for update;
    if not exists (
      select 1 from public.pachanga_competition_schedule_slots slots
      where slots.competition_id = plan_row.competition_id
        and slots.edition_id = plan_row.edition_id
        and slots.stage_id = plan_row.stage_id
        and slots.competition_group_id = plan_row.competition_group_id
        and slots.status <> 'retired'
    ) then raise exception 'TOURNAMENT_GROUP_SLOTS_REQUIRED' using errcode = '22023'; end if;
    seed_value := left(encode(extensions.digest(convert_to(
      target_operation_id::text || ':' || state_row.current_preparation_id::text
      || ':group-order:' || mapping_row.group_order::text,
      'UTF8'
    ), 'sha256'), 'hex'), 160);
    generated_revision_id := private.pachanga_league_schedule_generate_revision_v1(
      plan_row.id, seed_value,
      case when plan_row.current_revision_id is null then 'generated' else 'regenerated' end,
      target_actor_id, nextval('private.pachanga_competition_sequence')
    );
    input_snapshot := private.pachanga_league_schedule_inputs_v1(plan_row.id, seed_value);
    update public.pachanga_competition_schedule_plans plans set
      current_revision_id = generated_revision_id,
      entry_count = (input_snapshot ->> 'entryCount')::smallint,
      status = 'generated', revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where plans.id = plan_row.id;
    update public.pachanga_tournament_group_schedule_plans mappings set
      status = 'generated', revision = mappings.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where mappings.id = mapping_row.id;
    generated := generated || jsonb_build_array(jsonb_build_object(
      'groupId', mapping_row.competition_group_id,
      'schedulePlanId', plan_row.id,
      'scheduleRevisionId', generated_revision_id,
      'inputChecksum', input_snapshot ->> 'inputChecksum'
    ));
  end loop;
  if jsonb_array_length(generated) = 0 then
    raise exception 'TOURNAMENT_GROUP_SCHEDULE_ALREADY_PUBLISHED' using errcode = 'PT409';
  end if;
  update public.pachanga_tournament_group_stage_states states set
    status = 'scheduling', revision = states.revision + 1,
    server_sequence = target_server_sequence, updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object('generated', generated);
end;
$$;

revoke all on function private.pachanga_tournament_group_schedule_generate_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_schedule_validate_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_competition_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare preparation_row public.pachanga_tournament_group_stage_preparations%rowtype;
declare mapping_row public.pachanga_tournament_group_schedule_plans%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare validation jsonb;
declare plan_validations jsonb := '[]'::jsonb;
declare plan_count_value integer := 0;
declare round_count_value integer := 0;
declare fixture_count_value integer := 0;
declare unassigned_count_value integer := 0;
declare local_hard_count integer := 0;
declare global_team_overlap_count integer := 0;
declare global_venue_overlap_count integer := 0;
declare fixture_mismatch_count integer := 0;
declare round_mismatch_count integer := 0;
declare member_scope_error_count integer := 0;
declare input_checksum_value text;
declare validation_snapshot jsonb;
declare validation_checksum text;
declare computed_status text;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  select * into preparation_row
  from public.pachanga_tournament_group_stage_preparations preparations
  where preparations.id = state_row.current_preparation_id;
  perform set_config('pachangas.r6b_orchestrator', 'on', true);
  for mapping_row in
    select mappings.*
    from public.pachanga_tournament_group_schedule_plans mappings
    where mappings.group_stage_state_id = state_row.id
      and mappings.status not in ('published', 'cancelled')
    order by mappings.group_order, mappings.id
    for update
  loop
    plan_count_value := plan_count_value + 1;
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = mapping_row.schedule_plan_id for update;
    if plan_row.current_revision_id is null then
      raise exception 'TOURNAMENT_GROUP_SCHEDULE_NOT_GENERATED' using errcode = '22023';
    end if;
    validation := private.pachanga_league_schedule_validate_revision_v1(
      plan_row.current_revision_id, target_actor_id,
      nextval('private.pachanga_competition_sequence')
    );
    round_count_value := round_count_value + coalesce((validation ->> 'roundCount')::integer, 0);
    fixture_count_value := fixture_count_value + coalesce((validation ->> 'pairCount')::integer, 0);
    unassigned_count_value := unassigned_count_value
      + coalesce((validation ->> 'unassignedItems')::integer, 0);
    local_hard_count := local_hard_count
      + coalesce((validation ->> 'hardViolations')::integer, 0);
    if coalesce((validation ->> 'roundCount')::integer, 0) <> mapping_row.expected_round_count then
      round_mismatch_count := round_mismatch_count + 1;
    end if;
    if coalesce((validation ->> 'pairCount')::integer, 0) <> mapping_row.expected_fixture_count then
      fixture_mismatch_count := fixture_mismatch_count + 1;
    end if;
    update public.pachanga_competition_schedule_plans plans set
      status = case when validation ->> 'status' = 'VALID' then 'validated' else 'generated' end,
      revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where plans.id = plan_row.id;
    plan_validations := plan_validations || jsonb_build_array(jsonb_build_object(
      'groupId', mapping_row.competition_group_id,
      'schedulePlanId', mapping_row.schedule_plan_id,
      'scheduleRevisionId', plan_row.current_revision_id,
      'status', validation ->> 'status',
      'roundCount', validation -> 'roundCount',
      'fixtureCount', validation -> 'pairCount',
      'unassigned', validation -> 'unassignedItems',
      'hardViolations', validation -> 'hardViolations',
      'inputChecksum', validation ->> 'inputChecksum'
    ));
  end loop;
  if plan_count_value <> state_row.group_count then
    raise exception 'TOURNAMENT_GROUP_SCHEDULE_SCOPE_INCOMPLETE' using errcode = '22023';
  end if;

  with active_items as (
    select items.id, items.home_entry_id, items.away_entry_id,
      items.scheduled_start, items.scheduled_end
    from public.pachanga_tournament_group_schedule_plans mappings
    join public.pachanga_competition_schedule_plans plans
      on plans.id = mappings.schedule_plan_id
    join public.pachanga_competition_schedule_items items
      on items.schedule_revision_id = plans.current_revision_id
    where mappings.group_stage_state_id = state_row.id
  ), entry_windows as (
    select items.id, items.home_entry_id as entry_id,
      items.scheduled_start, items.scheduled_end from active_items items
    union all
    select items.id, items.away_entry_id,
      items.scheduled_start, items.scheduled_end from active_items items
  )
  select count(*)::integer into global_team_overlap_count
  from entry_windows left_window
  join entry_windows right_window
    on right_window.entry_id = left_window.entry_id
   and right_window.id > left_window.id
   and tstzrange(left_window.scheduled_start, left_window.scheduled_end, '[)')
     && tstzrange(right_window.scheduled_start, right_window.scheduled_end, '[)');

  with active_items as (
    select items.id, items.scheduled_start, items.scheduled_end,
      slots.resource_key
    from public.pachanga_tournament_group_schedule_plans mappings
    join public.pachanga_competition_schedule_plans plans
      on plans.id = mappings.schedule_plan_id
    join public.pachanga_competition_schedule_items items
      on items.schedule_revision_id = plans.current_revision_id
    join public.pachanga_competition_schedule_slots slots on slots.id = items.slot_id
    where mappings.group_stage_state_id = state_row.id
      and slots.resource_key is not null
  )
  select count(*)::integer into global_venue_overlap_count
  from active_items left_item
  join active_items right_item
    on right_item.resource_key = left_item.resource_key
   and right_item.id > left_item.id
   and tstzrange(left_item.scheduled_start, left_item.scheduled_end, '[)')
     && tstzrange(right_item.scheduled_start, right_item.scheduled_end, '[)');

  select count(*)::integer into member_scope_error_count
  from public.pachanga_tournament_group_schedule_plans mappings
  join public.pachanga_competition_schedule_plans plans on plans.id = mappings.schedule_plan_id
  join public.pachanga_competition_schedule_items items
    on items.schedule_revision_id = plans.current_revision_id
  where mappings.group_stage_state_id = state_row.id
    and (
      not exists (
        select 1 from public.pachanga_competition_stage_memberships memberships
        where memberships.entry_id = items.home_entry_id
          and memberships.stage_id = state_row.stage_id
          and memberships.competition_group_id = mappings.competition_group_id
          and memberships.status = 'active'
      )
      or not exists (
        select 1 from public.pachanga_competition_stage_memberships memberships
        where memberships.entry_id = items.away_entry_id
          and memberships.stage_id = state_row.stage_id
          and memberships.competition_group_id = mappings.competition_group_id
          and memberships.status = 'active'
      )
    );

  input_checksum_value := private.pachanga_tournament_json_checksum_v1(
    jsonb_build_object(
      'preparationInputChecksum', preparation_row.input_checksum,
      'plans', plan_validations
    )
  );
  computed_status := case
    when exists (
      select 1 from jsonb_array_elements(plan_validations) plan_validation
      where plan_validation ->> 'status' = 'STALE_INPUT'
    ) then 'STALE_INPUT'
    when local_hard_count + global_team_overlap_count + global_venue_overlap_count
      + fixture_mismatch_count + round_mismatch_count + member_scope_error_count
      + unassigned_count_value = 0 then 'VALID'
    else 'INVALID'
  end;
  validation_snapshot := jsonb_build_object(
    'status', computed_status,
    'planCount', plan_count_value,
    'roundCount', round_count_value,
    'fixtureCount', fixture_count_value,
    'unassignedFixtureCount', unassigned_count_value,
    'hardViolationCount', local_hard_count + global_team_overlap_count
      + global_venue_overlap_count + fixture_mismatch_count
      + round_mismatch_count + member_scope_error_count,
    'globalChecks', jsonb_build_object(
      'teamOverlaps', global_team_overlap_count,
      'venueOverlaps', global_venue_overlap_count,
      'fixtureMismatches', fixture_mismatch_count,
      'roundMismatches', round_mismatch_count,
      'membershipScopeErrors', member_scope_error_count
    ),
    'plans', plan_validations
  );
  validation_checksum := private.pachanga_tournament_json_checksum_v1(validation_snapshot);
  insert into public.pachanga_tournament_group_schedule_validations(
    id, group_stage_state_id, preparation_id, status, plan_count,
    round_count, fixture_count, unassigned_fixture_count,
    hard_violation_count, validation_snapshot, input_checksum, checksum,
    operation_id, validated_by, server_sequence
  ) values (
    private.pachanga_tournament_group_operation_entity_id_v1(target_operation_id, 'global-validation'),
    state_row.id, preparation_row.id, computed_status, plan_count_value,
    round_count_value, fixture_count_value, unassigned_count_value,
    (validation_snapshot ->> 'hardViolationCount')::integer,
    validation_snapshot, input_checksum_value, validation_checksum,
    target_operation_id, target_actor_id, target_server_sequence
  );
  update public.pachanga_tournament_group_schedule_plans mappings set
    status = case when computed_status = 'VALID' then 'validated' else 'generated' end,
    revision = mappings.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where mappings.group_stage_state_id = state_row.id
    and mappings.status not in ('published', 'cancelled');
  update public.pachanga_tournament_group_stage_states states set
    status = case when computed_status = 'VALID' then 'schedule_validated' else 'scheduling' end,
    fixture_count = fixture_count_value,
    revision = states.revision + 1,
    server_sequence = target_server_sequence,
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object('validation', validation_snapshot, 'validationChecksum', validation_checksum);
end;
$$;

revoke all on function private.pachanga_tournament_group_schedule_validate_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;
