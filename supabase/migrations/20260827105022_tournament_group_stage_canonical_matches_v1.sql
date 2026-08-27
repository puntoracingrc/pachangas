-- Pachangas IQ R6B: atomic canonical group-match publication and reuse of
-- R4C/R4D/R5 authorities. No knockout match can pass this adapter.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_tournament_reject_match_generation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare generation_enabled boolean := false;
begin
  if not exists (
    select 1 from public.pachanga_competitions competitions
    where competitions.id = new.competition_id
      and competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
  ) then return new; end if;
  select settings.tournament_match_generation_enabled into generation_enabled
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
  if not coalesce(generation_enabled, false)
     or current_setting('pachangas.r6b_match_publish', true) <> 'on'
     or new.source_kind <> 'COMPETITION_GENERATED'
     or new.schedule_item_id is null
     or not exists (
       select 1
       from public.pachanga_competition_schedule_items items
       join public.pachanga_competition_schedule_revisions revisions
         on revisions.id = items.schedule_revision_id
       join public.pachanga_competition_schedule_plans plans
         on plans.id = revisions.schedule_plan_id
       join public.pachanga_tournament_group_schedule_plans mappings
         on mappings.schedule_plan_id = plans.id
       join public.pachanga_tournament_group_stage_states states
         on states.id = mappings.group_stage_state_id
       join public.pachanga_competition_stages stages on stages.id = states.stage_id
       where items.id = new.schedule_item_id
         and items.status = 'validated'
         and revisions.id = plans.current_revision_id
         and revisions.status = 'validated'
         and revisions.validation_status = 'VALID'
         and plans.status = 'validated'
         and mappings.status = 'validated'
         and states.status = 'schedule_validated'
         and stages.stage_type = 'GROUP_STAGE'
         and states.competition_id = new.competition_id
         and states.edition_id = new.edition_id
         and states.stage_id = new.stage_id
         and mappings.competition_group_id = new.competition_group_id
         and states.rule_revision_id = new.rule_revision_id
         and items.home_entry_id = new.home_entry_id
         and items.away_entry_id = new.away_entry_id
     ) then
    raise exception 'TOURNAMENT_MATCH_GENERATION_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_tournament_reject_match_generation_v1()
  from public, anon, authenticated;

comment on function private.pachanga_tournament_reject_match_generation_v1() is
  'Allows only transaction-scoped R6B GROUP_STAGE fixtures validated by R4B. Knockout generation remains impossible.';

create or replace function private.pachanga_league_match_context_v1(target_context_id uuid)
returns public.pachanga_competition_match_contexts
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_competition_match_contexts%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare item_status text;
declare source_kind_value text;
begin
  select * into selected
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id;
  if not found then raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = selected.competition_id;
  if competition_row.competition_type = 'TOURNAMENT' then
    if competition_row.product_key <> 'TOURNAMENT_PRIVATE_BETA_V1'
       or not exists (
         select 1
         from public.pachanga_tournament_group_schedule_plans mappings
         join public.pachanga_tournament_group_stage_states states
           on states.id = mappings.group_stage_state_id
         join public.pachanga_competition_stages stages on stages.id = states.stage_id
         where mappings.schedule_plan_id = (
           select revisions.schedule_plan_id
           from public.pachanga_competition_schedule_items items
           join public.pachanga_competition_schedule_revisions revisions
             on revisions.id = items.schedule_revision_id
           where items.id = selected.schedule_item_id
         )
           and mappings.status = 'published'
           and states.status in ('schedule_published', 'active', 'complete')
           and stages.stage_type = 'GROUP_STAGE'
           and states.competition_id = selected.competition_id
           and states.stage_id = selected.stage_id
           and mappings.competition_group_id = selected.competition_group_id
           and states.rule_revision_id = selected.rule_revision_id
       ) then raise exception 'TOURNAMENT_GROUP_MATCH_CONTEXT_REQUIRED' using errcode = '22023'; end if;
  elsif competition_row.competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if selected.source_kind <> 'COMPETITION_GENERATED' or selected.schedule_item_id is null then
    raise exception 'R4C_REQUIRES_COMPETITION_GENERATED_CANONICAL_MATCH' using errcode = '22023';
  end if;
  select items.status into item_status
  from public.pachanga_competition_schedule_items items
  where items.id = selected.schedule_item_id
    and items.canonical_match_id = selected.canonical_match_id
    and items.competition_match_context_id = selected.id;
  if item_status <> 'published' then
    raise exception 'R4C_FIXTURE_NOT_PUBLISHED' using errcode = '22023';
  end if;
  select bindings.source_kind into source_kind_value
  from public.pachanga_canonical_match_bindings bindings
  where bindings.canonical_match_id = selected.canonical_match_id
    and bindings.binding_status = 'active'
    and bindings.source_kind = 'competition_generated'
  order by bindings.server_sequence desc, bindings.id desc
  limit 1;
  if source_kind_value is null then
    raise exception 'R4C_CANONICAL_BINDING_NOT_FOUND' using errcode = '22023';
  end if;
  if selected.home_entry_id is null or selected.away_entry_id is null
     or selected.rule_revision_id is null or selected.round_id is null then
    raise exception 'R4C_MATCH_CONTEXT_INCOMPLETE' using errcode = '22023';
  end if;
  return selected;
end;
$$;

revoke all on function private.pachanga_league_match_context_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_schedule_publish_v1(
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
declare validation_row public.pachanga_tournament_group_schedule_validations%rowtype;
declare mapping_row public.pachanga_tournament_group_schedule_plans%rowtype;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare publication jsonb;
declare publications jsonb := '[]'::jsonb;
declare expected_fixture_total integer := 0;
declare published_fixture_total integer := 0;
declare canonical_total integer := 0;
declare context_total integer := 0;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  if state_row.status <> 'schedule_validated' then
    raise exception 'TOURNAMENT_GROUP_SCHEDULE_NOT_VALIDATED' using errcode = '22023';
  end if;
  select * into validation_row
  from public.pachanga_tournament_group_schedule_validations validations
  where validations.group_stage_state_id = state_row.id
    and validations.preparation_id = state_row.current_preparation_id
  order by validations.server_sequence desc, validations.id desc
  limit 1;
  if not found or validation_row.status <> 'VALID' then
    raise exception 'TOURNAMENT_GROUP_SCHEDULE_NOT_VALIDATED' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.pachanga_tournament_group_schedule_plans mappings
    where mappings.group_stage_state_id = state_row.id and mappings.status <> 'validated'
  ) then raise exception 'TOURNAMENT_GROUP_SCHEDULE_NOT_VALIDATED' using errcode = '22023'; end if;
  if exists (
    select 1
    from public.pachanga_tournament_group_schedule_plans mappings
    join public.pachanga_competition_schedule_plans plans on plans.id = mappings.schedule_plan_id
    join public.pachanga_competition_schedule_items items
      on items.schedule_revision_id = plans.current_revision_id
    where mappings.group_stage_state_id = state_row.id
      and (items.canonical_match_id is not null or items.competition_match_context_id is not null)
  ) then raise exception 'TOURNAMENT_GROUP_SCHEDULE_ALREADY_PUBLISHED' using errcode = 'PT409'; end if;
  perform set_config('pachangas.r6b_orchestrator', 'on', true);
  perform set_config('pachangas.r6b_match_publish', 'on', true);
  for mapping_row in
    select mappings.*
    from public.pachanga_tournament_group_schedule_plans mappings
    where mappings.group_stage_state_id = state_row.id
    order by mappings.group_order, mappings.id
    for update
  loop
    select * into plan_row from public.pachanga_competition_schedule_plans plans
    where plans.id = mapping_row.schedule_plan_id for update;
    expected_fixture_total := expected_fixture_total + mapping_row.expected_fixture_count;
    -- R4B publishes one plan per edition and advances the edition immediately.
    -- R6B publishes every group plan atomically, so subsequent R4B calls must
    -- still observe the closed-registration precondition inside this transaction.
    update public.pachanga_competition_editions editions set
      status = 'registration_closed',
      registration_mode = 'CLOSED',
      revision = editions.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where editions.id = state_row.edition_id
      and editions.status = 'scheduled';
    publication := private.pachanga_league_schedule_publish_v1(
      plan_row.id, target_actor_id,
      private.pachanga_tournament_group_operation_entity_id_v1(
        target_operation_id, 'group-publish:' || mapping_row.competition_group_id::text
      ), nextval('private.pachanga_competition_sequence')
    );
    canonical_total := canonical_total + (publication ->> 'canonicalMatchCount')::integer;
    context_total := context_total + (publication ->> 'contextCount')::integer;
    publications := publications || jsonb_build_array(jsonb_build_object(
      'groupId', mapping_row.competition_group_id,
      'schedulePlanId', mapping_row.schedule_plan_id,
      'publication', publication
    ));
    update public.pachanga_tournament_group_schedule_plans mappings set
      status = 'published', revision = mappings.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where mappings.id = mapping_row.id;
  end loop;
  select count(*)::integer,
    count(items.canonical_match_id)::integer,
    count(items.competition_match_context_id)::integer
  into published_fixture_total, canonical_total, context_total
  from public.pachanga_tournament_group_schedule_plans mappings
  join public.pachanga_competition_schedule_plans plans on plans.id = mappings.schedule_plan_id
  join public.pachanga_competition_schedule_items items
    on items.schedule_revision_id = plans.current_revision_id
  where mappings.group_stage_state_id = state_row.id
    and items.status = 'published';
  if published_fixture_total <> expected_fixture_total
     or canonical_total <> expected_fixture_total
     or context_total <> expected_fixture_total
     or exists (
       select 1
       from public.pachanga_tournament_group_schedule_plans mappings
       join public.pachanga_competition_schedule_plans plans on plans.id = mappings.schedule_plan_id
       join public.pachanga_competition_schedule_items items
         on items.schedule_revision_id = plans.current_revision_id
       left join public.pachanga_canonical_match_bindings bindings
         on bindings.canonical_match_id = items.canonical_match_id
        and bindings.source_kind = 'competition_generated'
        and bindings.source_id = items.id::text
        and bindings.binding_status = 'active'
       left join public.pachanga_competition_match_contexts contexts
         on contexts.id = items.competition_match_context_id
        and contexts.canonical_match_id = items.canonical_match_id
        and contexts.schedule_item_id = items.id
       where mappings.group_stage_state_id = state_row.id
       group by items.id
       having count(bindings.id) <> 1 or count(contexts.id) <> 1
     ) then raise exception 'TOURNAMENT_CANONICAL_MATCH_CARDINALITY_VIOLATION' using errcode = 'XX000'; end if;
  update public.pachanga_tournament_group_stage_states states set
    status = 'schedule_published', fixture_count = expected_fixture_total,
    revision = states.revision + 1, server_sequence = target_server_sequence,
    updated_by = target_actor_id, updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object(
      'publications', publications,
      'canonicalMatchCount', canonical_total,
      'matchContextCount', context_total
    );
end;
$$;

revoke all on function private.pachanga_tournament_group_schedule_publish_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_qualification_comparison_v1(
  target_criteria jsonb,
  target_entry_id uuid,
  target_points numeric,
  target_played integer,
  target_goal_difference integer,
  target_goals_for integer,
  target_wins integer,
  target_lot_seed text
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = pg_catalog
as $$
declare criterion text;
declare criterion_value numeric;
declare values_object jsonb := '{}'::jsonb;
declare sort_values jsonb := '[]'::jsonb;
declare lot_hash text;
begin
  for criterion in select upper(value) from jsonb_array_elements_text(target_criteria) criteria(value)
  loop
    criterion_value := case criterion
      when 'POINTS' then target_points
      when 'POINTS_PER_MATCH' then case when target_played = 0 then 0 else target_points / target_played end
      when 'GOAL_DIFFERENCE' then target_goal_difference
      when 'GOAL_DIFFERENCE_PER_MATCH' then case when target_played = 0 then 0 else target_goal_difference::numeric / target_played end
      when 'GOALS_FOR' then target_goals_for
      when 'GOALS_FOR_PER_MATCH' then case when target_played = 0 then 0 else target_goals_for::numeric / target_played end
      when 'WINS' then target_wins
      when 'WINS_PER_MATCH' then case when target_played = 0 then 0 else target_wins::numeric / target_played end
      when 'PERSISTED_DRAW_LOT' then null
      else null
    end;
    if criterion = 'PERSISTED_DRAW_LOT' then
      lot_hash := encode(extensions.digest(convert_to(
        target_lot_seed || ':' || target_entry_id::text, 'UTF8'
      ), 'sha256'), 'hex');
      criterion_value := (('x' || substr(lot_hash, 1, 15))::bit(60)::bigint)::numeric;
    end if;
    if criterion_value is null then
      raise exception 'TOURNAMENT_CROSS_GROUP_CRITERION_NOT_SUPPORTED' using errcode = '0A000';
    end if;
    values_object := values_object || jsonb_build_object(criterion, criterion_value);
    sort_values := sort_values || jsonb_build_array(-criterion_value);
  end loop;
  return jsonb_build_object('values', values_object, 'sortKey', sort_values);
end;
$$;

revoke all on function private.pachanga_tournament_qualification_comparison_v1(
  jsonb,uuid,numeric,integer,integer,integer,integer,text
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_qualification_rebuild_v1(
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
declare policy jsonb;
declare qualification_policy jsonb;
declare policy_kind text;
declare direct_count integer;
declare extra_count integer;
declare extra_position integer;
declare comparator jsonb;
declare equal_size_required boolean;
declare tie_policy text;
declare target_slots jsonb;
declare group_count_value integer;
declare minimum_group_size integer;
declare maximum_group_size integer;
declare fixture_count_value integer;
declare official_count_value integer;
declare pending_result_count integer;
declare disputed_result_count integer;
declare standings_health_error_count integer;
declare source_snapshot_ids uuid[];
declare source_snapshot_checksums text[];
declare source_revision_value bigint;
declare health_status text;
declare candidate_row record;
declare comparison jsonb;
declare qualifier_index integer := 0;
declare qualifier_total integer;
declare snapshot_status text;
declare snapshot_id uuid := private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id, 'qualification-snapshot'
);
declare supersedes_id uuid;
declare group_qualifiers_value jsonb;
declare cross_qualifiers_value jsonb;
declare eliminated_value jsonb;
declare target_slot_value jsonb;
declare semantic_qualification_rows jsonb;
declare health_value jsonb;
declare checksum_value text;
declare existing_snapshot public.pachanga_tournament_qualification_snapshots%rowtype;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  if state_row.status not in ('schedule_published', 'active', 'complete') then
    raise exception 'TOURNAMENT_GROUP_SCHEDULE_NOT_PUBLISHED' using errcode = '22023';
  end if;
  if not private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'qualification_manage'
  ) then raise exception 'TOURNAMENT_QUALIFICATION_MANAGER_REQUIRED' using errcode = '42501'; end if;
  select * into preparation_row
  from public.pachanga_tournament_group_stage_preparations preparations
  where preparations.id = state_row.current_preparation_id;
  policy := private.pachanga_tournament_group_stage_policy_v1(state_row.rule_revision_id);
  qualification_policy := policy -> 'qualificationPolicy';
  policy_kind := qualification_policy ->> 'kind';
  direct_count := (qualification_policy ->> 'directQualifiersPerGroup')::integer;
  extra_count := (qualification_policy ->> 'extraQualifierCount')::integer;
  comparator := qualification_policy -> 'comparatorCriteria';
  equal_size_required := (qualification_policy ->> 'equalGroupSizeRequired')::boolean;
  tie_policy := qualification_policy ->> 'tieResolutionPolicy';
  target_slots := qualification_policy -> 'targetBracketSlots';
  extra_position := case policy_kind
    when 'TOP_N_PER_GROUP_PLUS_BEST_RUNNERS_UP' then 2
    when 'TOP_N_PER_GROUP_PLUS_BEST_THIRDS' then 3
    else null
  end;
  if extra_position is not null and direct_count >= extra_position then
    raise exception 'TOURNAMENT_QUALIFICATION_POLICY_INVALID' using errcode = '22023';
  end if;
  select count(*)::integer, min(member_count)::integer, max(member_count)::integer
  into group_count_value, minimum_group_size, maximum_group_size
  from (
    select mappings.competition_group_id, count(memberships.entry_id) as member_count
    from public.pachanga_tournament_group_schedule_plans mappings
    join public.pachanga_competition_stage_memberships memberships
      on memberships.competition_group_id = mappings.competition_group_id
     and memberships.stage_id = state_row.stage_id
     and memberships.status = 'active'
    where mappings.group_stage_state_id = state_row.id
    group by mappings.competition_group_id
  ) group_sizes;
  if group_count_value <> state_row.group_count then
    raise exception 'TOURNAMENT_GROUP_STAGE_INPUT_STALE' using errcode = 'PT409';
  end if;
  if extra_count > 0 and minimum_group_size <> maximum_group_size and equal_size_required then
    raise exception 'CROSS_GROUP_QUALIFICATION_POLICY_REQUIRED' using errcode = '22023';
  end if;
  qualifier_total := state_row.group_count * direct_count + extra_count;
  if jsonb_array_length(target_slots) <> qualifier_total then
    raise exception 'TOURNAMENT_BRACKET_SLOT_COUNT_MISMATCH' using errcode = '22023';
  end if;

  select count(*)::integer,
    count(*) filter (where contexts.status = 'official')::integer,
    count(*) filter (where contexts.status <> 'official')::integer,
    count(*) filter (where results.state = 'disputed')::integer
  into fixture_count_value, official_count_value,
    pending_result_count, disputed_result_count
  from public.pachanga_competition_match_contexts contexts
  left join public.pachanga_competition_sporting_results results
    on results.competition_match_context_id = contexts.id
  where contexts.competition_id = state_row.competition_id
    and contexts.edition_id = state_row.edition_id
    and contexts.stage_id = state_row.stage_id
    and contexts.rule_revision_id = state_row.rule_revision_id
    and contexts.source_kind = 'COMPETITION_GENERATED';

  select count(*) filter (
      where states.health_status is distinct from 'CURRENT'
        or snapshots.id is null
    )::integer,
    array_agg(snapshots.id order by groups.group_order, snapshots.server_sequence, snapshots.id)
      filter (where snapshots.id is not null),
    array_agg(snapshots.content_checksum order by groups.group_order, snapshots.server_sequence, snapshots.id)
      filter (where snapshots.id is not null),
    coalesce(max(snapshots.server_sequence), 0)
  into standings_health_error_count, source_snapshot_ids,
    source_snapshot_checksums, source_revision_value
  from public.pachanga_tournament_group_schedule_plans mappings
  join public.pachanga_competition_groups groups on groups.id = mappings.competition_group_id
  left join public.pachanga_competition_standing_states states
    on states.stage_id = state_row.stage_id
   and states.competition_group_id = mappings.competition_group_id
   and states.rule_revision_id = state_row.rule_revision_id
  left join public.pachanga_competition_standing_snapshots snapshots
    on snapshots.id = states.current_snapshot_id
  where mappings.group_stage_state_id = state_row.id;
  if standings_health_error_count > 0 or cardinality(source_snapshot_ids) <> state_row.group_count then
    raise exception 'TOURNAMENT_GROUP_STANDINGS_REQUIRED' using errcode = '22023';
  end if;

  drop table if exists pg_temp.r6b_qualification_work;
  create temporary table pg_temp.r6b_qualification_work (
    competition_group_id uuid not null,
    group_order integer not null,
    standing_snapshot_id uuid not null,
    entry_id uuid primary key,
    group_position integer not null,
    played integer not null,
    wins integer not null,
    goals_for integer not null,
    goal_difference integer not null,
    effective_points numeric not null,
    outcome text not null default 'ELIMINATED',
    cross_group_rank integer,
    comparison_values jsonb not null default '{}'::jsonb,
    sort_key numeric[] not null default '{}'::numeric[],
    target_bracket_slot text
  ) on commit drop;
  insert into pg_temp.r6b_qualification_work(
    competition_group_id, group_order, standing_snapshot_id, entry_id,
    group_position, played, wins, goals_for, goal_difference, effective_points
  )
  select mappings.competition_group_id, groups.group_order, snapshots.id,
    rows.entry_id, rows.position, rows.played, rows.wins, rows.goals_for,
    rows.goal_difference, rows.effective_points
  from public.pachanga_tournament_group_schedule_plans mappings
  join public.pachanga_competition_groups groups on groups.id = mappings.competition_group_id
  join public.pachanga_competition_standing_states standing_states
    on standing_states.stage_id = state_row.stage_id
   and standing_states.competition_group_id = mappings.competition_group_id
  join public.pachanga_competition_standing_snapshots snapshots
    on snapshots.id = standing_states.current_snapshot_id
  join public.pachanga_competition_standing_rows rows
    on rows.standing_snapshot_id = snapshots.id
  where mappings.group_stage_state_id = state_row.id;
  if (select count(*) from pg_temp.r6b_qualification_work) <> state_row.entry_count then
    raise exception 'TOURNAMENT_GROUP_STANDINGS_INCOMPLETE' using errcode = '22023';
  end if;
  update pg_temp.r6b_qualification_work work
  set outcome = 'DIRECT_QUALIFIER'
  where work.group_position <= direct_count;
  if extra_count > 0 then
    for candidate_row in
      select * from pg_temp.r6b_qualification_work work
      where work.group_position = extra_position
      order by work.group_order, work.entry_id
    loop
      comparison := private.pachanga_tournament_qualification_comparison_v1(
        comparator, candidate_row.entry_id, candidate_row.effective_points,
        candidate_row.played, candidate_row.goal_difference,
        candidate_row.goals_for, candidate_row.wins,
        preparation_row.input_checksum
      );
      update pg_temp.r6b_qualification_work work set
        comparison_values = comparison -> 'values',
        sort_key = array(
          select value::numeric
          from jsonb_array_elements_text(comparison -> 'sortKey') values_list(value)
        )
      where work.entry_id = candidate_row.entry_id;
    end loop;
    if tie_policy = 'MANUAL_ORGANIZER_DECISION' and exists (
      select 1 from pg_temp.r6b_qualification_work work
      where work.group_position = extra_position
      group by work.sort_key having count(*) > 1
    ) then raise exception 'TOURNAMENT_QUALIFICATION_TIE_REQUIRES_DECISION' using errcode = 'PT409'; end if;
    with ranked as (
      select work.entry_id,
        row_number() over (order by work.sort_key, work.entry_id)::integer as cross_rank
      from pg_temp.r6b_qualification_work work
      where work.group_position = extra_position
    )
    update pg_temp.r6b_qualification_work work set
      cross_group_rank = ranked.cross_rank,
      outcome = case when ranked.cross_rank <= extra_count
        then 'EXTRA_QUALIFIER' else work.outcome end
    from ranked where ranked.entry_id = work.entry_id;
  end if;
  for candidate_row in
    select * from pg_temp.r6b_qualification_work work
    where work.outcome = 'DIRECT_QUALIFIER'
    order by work.group_order, work.group_position, work.entry_id
  loop
    qualifier_index := qualifier_index + 1;
    update pg_temp.r6b_qualification_work work
    set target_bracket_slot = target_slots ->> (qualifier_index - 1)
    where work.entry_id = candidate_row.entry_id;
  end loop;
  for candidate_row in
    select * from pg_temp.r6b_qualification_work work
    where work.outcome = 'EXTRA_QUALIFIER'
    order by work.cross_group_rank, work.entry_id
  loop
    qualifier_index := qualifier_index + 1;
    update pg_temp.r6b_qualification_work work
    set target_bracket_slot = target_slots ->> (qualifier_index - 1)
    where work.entry_id = candidate_row.entry_id;
  end loop;
  if qualifier_index <> qualifier_total then
    raise exception 'TOURNAMENT_QUALIFIER_COUNT_MISMATCH' using errcode = '22023';
  end if;
  health_status := case
    when fixture_count_value = state_row.fixture_count
      and official_count_value = fixture_count_value
      and pending_result_count = 0 and disputed_result_count = 0
      then 'READY'
    else 'PROVISIONAL'
  end;
  snapshot_status := health_status;
  health_value := jsonb_build_object(
    'status', health_status,
    'fixtureCount', fixture_count_value,
    'officialFixtureCount', official_count_value,
    'pendingFixtureCount', pending_result_count,
    'disputedResultCount', disputed_result_count,
    'standingsCurrent', true,
    'minimumGroupSize', minimum_group_size,
    'maximumGroupSize', maximum_group_size
  );
  select coalesce(jsonb_agg(jsonb_build_object(
    'groupId', work.competition_group_id,
    'entryId', work.entry_id,
    'groupPosition', work.group_position,
    'targetBracketSlot', work.target_bracket_slot
  ) order by work.group_order, work.group_position, work.entry_id), '[]'::jsonb)
  into group_qualifiers_value
  from pg_temp.r6b_qualification_work work where work.outcome = 'DIRECT_QUALIFIER';
  select coalesce(jsonb_agg(jsonb_build_object(
    'groupId', work.competition_group_id,
    'entryId', work.entry_id,
    'groupPosition', work.group_position,
    'crossGroupRank', work.cross_group_rank,
    'comparisonValues', work.comparison_values,
    'targetBracketSlot', work.target_bracket_slot
  ) order by work.cross_group_rank, work.entry_id), '[]'::jsonb)
  into cross_qualifiers_value
  from pg_temp.r6b_qualification_work work where work.outcome = 'EXTRA_QUALIFIER';
  select coalesce(jsonb_agg(jsonb_build_object(
    'groupId', work.competition_group_id,
    'entryId', work.entry_id,
    'groupPosition', work.group_position
  ) order by work.group_order, work.group_position, work.entry_id), '[]'::jsonb)
  into eliminated_value
  from pg_temp.r6b_qualification_work work where work.outcome = 'ELIMINATED';
  select coalesce(jsonb_agg(jsonb_build_object(
    'slotKey', work.target_bracket_slot,
    'entryId', work.entry_id,
    'sourceKind', case when work.outcome = 'DIRECT_QUALIFIER'
      then 'GROUP_POSITION' else 'EXTRA_QUALIFIER' end
  ) order by array_position(array(select jsonb_array_elements_text(target_slots)), work.target_bracket_slot)), '[]'::jsonb)
  into target_slot_value
  from pg_temp.r6b_qualification_work work
  where work.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER');
  select coalesce(jsonb_agg(jsonb_build_object(
    'groupOrder', work.group_order,
    'standingChecksum', snapshots.content_checksum,
    'entryId', work.entry_id,
    'groupPosition', work.group_position,
    'outcome', work.outcome,
    'crossGroupRank', work.cross_group_rank,
    'comparisonValues', work.comparison_values,
    'targetBracketSlot', work.target_bracket_slot
  ) order by work.group_order, work.group_position, work.entry_id), '[]'::jsonb)
  into semantic_qualification_rows
  from pg_temp.r6b_qualification_work work
  join public.pachanga_competition_standing_snapshots snapshots
    on snapshots.id = work.standing_snapshot_id;
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'preparation', jsonb_build_object(
      'drawChecksum', preparation_row.draw_checksum,
      'participantChecksum', preparation_row.participant_checksum,
      'ruleChecksum', preparation_row.rule_checksum,
      'groupCount', preparation_row.group_count,
      'entryCount', preparation_row.entry_count
    ),
    'sourceStandingChecksums', source_snapshot_checksums,
    'policy', qualification_policy,
    'health', health_value,
    'qualificationRows', semantic_qualification_rows,
    'targetBracketSlots', target_slot_value
  ));
  select * into existing_snapshot
  from public.pachanga_tournament_qualification_snapshots snapshots
  where snapshots.group_stage_state_id = state_row.id
    and snapshots.status = snapshot_status
    and snapshots.checksum = checksum_value
    and snapshots.id = state_row.current_qualification_snapshot_id
  order by snapshots.server_sequence desc, snapshots.id desc limit 1;
  if found then
    return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
      || jsonb_build_object('qualificationSnapshotId', existing_snapshot.id, 'qualificationReplay', true);
  end if;
  supersedes_id := state_row.current_qualification_snapshot_id;
  insert into public.pachanga_tournament_qualification_snapshots(
    id, group_stage_state_id, competition_id, edition_id, stage_id,
    rule_revision_id, preparation_id, supersedes_snapshot_id, status,
    source_standings_revision, source_standing_snapshot_ids, policy_snapshot,
    health_snapshot, group_qualifiers, cross_group_qualifiers,
    eliminated_entries, target_bracket_slots, checksum, operation_id,
    generated_by, server_sequence
  ) values (
    snapshot_id, state_row.id, state_row.competition_id, state_row.edition_id,
    state_row.stage_id, state_row.rule_revision_id, preparation_row.id,
    supersedes_id, snapshot_status, source_revision_value, source_snapshot_ids,
    qualification_policy, health_value, group_qualifiers_value,
    cross_qualifiers_value, eliminated_value, target_slot_value, checksum_value,
    target_operation_id, target_actor_id, target_server_sequence
  );
  insert into public.pachanga_tournament_qualification_rows(
    qualification_snapshot_id, competition_group_id, standing_snapshot_id,
    entry_id, group_position, cross_group_rank, outcome,
    target_bracket_slot, comparison_values, server_sequence
  ) select snapshot_id, work.competition_group_id, work.standing_snapshot_id,
    work.entry_id, work.group_position, work.cross_group_rank, work.outcome,
    work.target_bracket_slot, work.comparison_values,
    nextval('private.pachanga_competition_sequence')
  from pg_temp.r6b_qualification_work work
  order by work.group_order, work.group_position, work.entry_id;
  update public.pachanga_tournament_group_stage_states states set
    current_qualification_snapshot_id = snapshot_id,
    official_fixture_count = official_count_value,
    revision = states.revision + 1, server_sequence = target_server_sequence,
    updated_by = target_actor_id, updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object(
      'qualificationSnapshotId', snapshot_id,
      'qualificationStatus', snapshot_status,
      'qualificationChecksum', checksum_value
    );
end;
$$;

revoke all on function private.pachanga_tournament_qualification_rebuild_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_qualification_publish_v1(
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
declare source_snapshot public.pachanga_tournament_qualification_snapshots%rowtype;
declare published_snapshot_id uuid := private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id, 'qualification-published'
);
declare current_standing_ids uuid[];
declare checksum_value text;
declare entry_notification record;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  if not private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'qualification_publish'
  ) then raise exception 'TOURNAMENT_QUALIFICATION_PUBLISHER_REQUIRED' using errcode = '42501'; end if;
  select * into source_snapshot
  from public.pachanga_tournament_qualification_snapshots snapshots
  where snapshots.id = state_row.current_qualification_snapshot_id for update;
  if not found or source_snapshot.status <> 'READY' then
    raise exception 'TOURNAMENT_QUALIFICATION_NOT_READY' using errcode = '22023';
  end if;
  select array_agg(snapshots.id order by groups.group_order, snapshots.server_sequence, snapshots.id)
  into current_standing_ids
  from public.pachanga_tournament_group_schedule_plans mappings
  join public.pachanga_competition_groups groups on groups.id = mappings.competition_group_id
  join public.pachanga_competition_standing_states standing_states
    on standing_states.stage_id = state_row.stage_id
   and standing_states.competition_group_id = mappings.competition_group_id
   and standing_states.health_status = 'CURRENT'
  join public.pachanga_competition_standing_snapshots snapshots
    on snapshots.id = standing_states.current_snapshot_id
  where mappings.group_stage_state_id = state_row.id;
  if current_standing_ids is distinct from source_snapshot.source_standing_snapshot_ids
     or exists (
       select 1 from public.pachanga_competition_match_contexts contexts
       left join public.pachanga_competition_sporting_results results
         on results.competition_match_context_id = contexts.id
       where contexts.competition_id = state_row.competition_id
         and contexts.stage_id = state_row.stage_id
         and contexts.source_kind = 'COMPETITION_GENERATED'
         and (contexts.status <> 'official' or results.state = 'disputed')
     ) then raise exception 'TOURNAMENT_QUALIFICATION_INPUT_STALE' using errcode = 'PT409'; end if;
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'sourceQualificationSnapshotId', source_snapshot.id,
    'sourceChecksum', source_snapshot.checksum,
    'status', 'PUBLISHED'
  ));
  insert into public.pachanga_tournament_qualification_snapshots(
    id, group_stage_state_id, competition_id, edition_id, stage_id,
    rule_revision_id, preparation_id, supersedes_snapshot_id, status,
    source_standings_revision, source_standing_snapshot_ids, policy_snapshot,
    health_snapshot, group_qualifiers, cross_group_qualifiers,
    eliminated_entries, target_bracket_slots, checksum, operation_id,
    generated_by, generated_at, published_by, published_at, server_sequence
  ) values (
    published_snapshot_id, source_snapshot.group_stage_state_id,
    source_snapshot.competition_id, source_snapshot.edition_id,
    source_snapshot.stage_id, source_snapshot.rule_revision_id,
    source_snapshot.preparation_id, source_snapshot.id, 'PUBLISHED',
    source_snapshot.source_standings_revision,
    source_snapshot.source_standing_snapshot_ids, source_snapshot.policy_snapshot,
    source_snapshot.health_snapshot, source_snapshot.group_qualifiers,
    source_snapshot.cross_group_qualifiers, source_snapshot.eliminated_entries,
    source_snapshot.target_bracket_slots, checksum_value, target_operation_id,
    target_actor_id, source_snapshot.generated_at, target_actor_id,
    clock_timestamp(), target_server_sequence
  );
  insert into public.pachanga_tournament_qualification_rows(
    qualification_snapshot_id, competition_group_id, standing_snapshot_id,
    entry_id, group_position, cross_group_rank, outcome,
    target_bracket_slot, comparison_values, server_sequence
  ) select published_snapshot_id, rows.competition_group_id,
    rows.standing_snapshot_id, rows.entry_id, rows.group_position,
    rows.cross_group_rank, rows.outcome, rows.target_bracket_slot,
    rows.comparison_values, nextval('private.pachanga_competition_sequence')
  from public.pachanga_tournament_qualification_rows rows
  where rows.qualification_snapshot_id = source_snapshot.id
  order by rows.group_position, rows.entry_id;
  update public.pachanga_tournament_group_stage_states states set
    current_qualification_snapshot_id = published_snapshot_id,
    status = 'complete', official_fixture_count = states.fixture_count,
    revision = states.revision + 1, server_sequence = target_server_sequence,
    updated_by = target_actor_id, updated_at = clock_timestamp()
  where states.id = state_row.id;
  for entry_notification in
    select rows.entry_id, rows.outcome, entries.team_id, teams.owner_id
    from public.pachanga_tournament_qualification_rows rows
    join public.pachanga_competition_entries entries on entries.id = rows.entry_id
    join public.pachanga_groups teams on teams.id = entries.team_id
    where rows.qualification_snapshot_id = published_snapshot_id
    order by rows.entry_id
  loop
    perform private.pachanga_notify_v1(
      entry_notification.owner_id,
      case when entry_notification.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
        then 'tournament_qualified' else 'tournament_eliminated' end,
      case when entry_notification.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
        then 'Clasificación confirmada' else 'Fase de grupos finalizada' end,
      case when entry_notification.outcome in ('DIRECT_QUALIFIER', 'EXTRA_QUALIFIER')
        then 'Tu equipo ocupa una plaza en el cuadro preparado.'
        else 'Tu equipo ha completado la fase de grupos.' end,
      '/?mobile=competiciones&tournament=' || target_competition_id::text,
      jsonb_build_object(
        'competitionId', target_competition_id,
        'entryId', entry_notification.entry_id,
        'outcome', entry_notification.outcome
      ),
      'tournament-qualification:' || published_snapshot_id::text || ':' || entry_notification.entry_id::text
    );
  end loop;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object(
      'qualificationSnapshotId', published_snapshot_id,
      'qualificationStatus', 'PUBLISHED',
      'qualificationChecksum', checksum_value
    );
end;
$$;

revoke all on function private.pachanga_tournament_qualification_publish_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_bracket_template_create_v1(
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
declare draw_plan public.pachanga_competition_draw_plans%rowtype;
declare qualification_snapshot public.pachanga_tournament_qualification_snapshots%rowtype;
declare template_id uuid := private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id, 'bracket-template-draft'
);
declare target_slots jsonb;
declare bracket_size_value integer;
declare slot_snapshot jsonb;
declare template_snapshot_value jsonb;
declare checksum_value text;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  if not private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'bracket_manage'
  ) then raise exception 'TOURNAMENT_BRACKET_MANAGER_REQUIRED' using errcode = '42501'; end if;
  select * into draw_plan from public.pachanga_competition_draw_plans plans
  where plans.id = state_row.draw_plan_id;
  if draw_plan.target_type <> 'GROUPS_THEN_KNOCKOUT' then
    raise exception 'TOURNAMENT_BRACKET_TEMPLATE_NOT_REQUIRED' using errcode = '0A000';
  end if;
  select * into qualification_snapshot
  from public.pachanga_tournament_qualification_snapshots snapshots
  where snapshots.id = state_row.current_qualification_snapshot_id;
  if not found or qualification_snapshot.status <> 'PUBLISHED' then
    raise exception 'TOURNAMENT_QUALIFICATION_NOT_PUBLISHED' using errcode = '22023';
  end if;
  target_slots := qualification_snapshot.policy_snapshot -> 'targetBracketSlots';
  bracket_size_value := jsonb_array_length(target_slots);
  if bracket_size_value < 2 or bracket_size_value > 128
     or (bracket_size_value & (bracket_size_value - 1)) <> 0 then
    raise exception 'TOURNAMENT_BRACKET_SIZE_INVALID' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'slotKey', slot_key,
    'bracketOrder', bracket_order,
    'matchNumber', ceil(bracket_order::numeric / 2)::integer,
    'side', case when bracket_order % 2 = 1 then 'A' else 'B' end,
    'sourceKind', case when rows.outcome = 'DIRECT_QUALIFIER'
      then 'GROUP_POSITION' else 'EXTRA_QUALIFIER' end,
    'sourceGroupId', case when rows.outcome = 'DIRECT_QUALIFIER'
      then rows.competition_group_id else null end,
    'sourcePosition', case when rows.outcome = 'DIRECT_QUALIFIER'
      then rows.group_position else null end,
    'sourceExtraRank', case when rows.outcome = 'EXTRA_QUALIFIER'
      then rows.cross_group_rank else null end,
    'resolvedEntryId', rows.entry_id
  ) order by bracket_order), '[]'::jsonb)
  into slot_snapshot
  from (
    select (ordinality - 1)::integer as slot_index,
      ordinality::integer as bracket_order, value as slot_key
    from jsonb_array_elements_text(target_slots) with ordinality slots(value, ordinality)
  ) ordered_slots
  join public.pachanga_tournament_qualification_rows rows
    on rows.qualification_snapshot_id = qualification_snapshot.id
   and rows.target_bracket_slot = ordered_slots.slot_key;
  if jsonb_array_length(slot_snapshot) <> bracket_size_value then
    raise exception 'TOURNAMENT_BRACKET_SLOT_COUNT_MISMATCH' using errcode = '22023';
  end if;
  template_snapshot_value := jsonb_build_object(
    'kind', 'CompetitionBracketTemplate',
    'status', 'DRAFT',
    'qualificationSnapshotId', qualification_snapshot.id,
    'bracketSize', bracket_size_value,
    'firstRoundMatchCount', bracket_size_value / 2,
    'slots', slot_snapshot,
    'progressionEnabled', false,
    'message', 'Cuadro preparado. La fase eliminatoria se activará en la siguiente fase.'
  );
  checksum_value := private.pachanga_tournament_json_checksum_v1(template_snapshot_value);
  insert into public.pachanga_tournament_bracket_templates(
    id, group_stage_state_id, competition_id, edition_id, stage_id,
    rule_revision_id, qualification_snapshot_id, supersedes_template_id,
    status, bracket_size, first_round_match_count, slot_count,
    template_snapshot, checksum, operation_id, created_by, server_sequence
  ) values (
    template_id, state_row.id, state_row.competition_id, state_row.edition_id,
    state_row.stage_id, state_row.rule_revision_id, qualification_snapshot.id,
    state_row.current_bracket_template_id, 'DRAFT', bracket_size_value,
    bracket_size_value / 2, bracket_size_value, template_snapshot_value,
    checksum_value, target_operation_id, target_actor_id, target_server_sequence
  );
  insert into public.pachanga_tournament_bracket_slots(
    bracket_template_id, slot_key, match_number, side, bracket_order,
    source_kind, source_group_id, source_position, source_extra_rank,
    resolved_entry_id, status, source_snapshot, server_sequence
  ) select template_id, item ->> 'slotKey', (item ->> 'matchNumber')::smallint,
    item ->> 'side', (item ->> 'bracketOrder')::smallint,
    item ->> 'sourceKind', nullif(item ->> 'sourceGroupId', '')::uuid,
    nullif(item ->> 'sourcePosition', '')::smallint,
    nullif(item ->> 'sourceExtraRank', '')::smallint,
    (item ->> 'resolvedEntryId')::uuid, 'RESOLVED', item,
    nextval('private.pachanga_competition_sequence')
  from jsonb_array_elements(slot_snapshot) slots(item);
  update public.pachanga_tournament_group_stage_states states set
    current_bracket_template_id = template_id,
    revision = states.revision + 1, server_sequence = target_server_sequence,
    updated_by = target_actor_id, updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object(
      'bracketTemplateId', template_id,
      'bracketTemplateStatus', 'DRAFT',
      'bracketTemplateChecksum', checksum_value
    );
end;
$$;

revoke all on function private.pachanga_tournament_bracket_template_create_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_bracket_template_publish_v1(
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
declare source_template public.pachanga_tournament_bracket_templates%rowtype;
declare published_template_id uuid := private.pachanga_tournament_group_operation_entity_id_v1(
  target_operation_id, 'bracket-template-published'
);
declare published_snapshot jsonb;
declare checksum_value text;
begin
  state_row := private.pachanga_tournament_group_stage_assert_current_v1(target_competition_id);
  select * into state_row from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id for update;
  if not private.pachanga_tournament_can_v1(
    target_competition_id, target_actor_id, 'bracket_publish'
  ) then raise exception 'TOURNAMENT_BRACKET_PUBLISHER_REQUIRED' using errcode = '42501'; end if;
  select * into source_template
  from public.pachanga_tournament_bracket_templates templates
  where templates.id = state_row.current_bracket_template_id for update;
  if not found or source_template.status <> 'DRAFT' then
    raise exception 'TOURNAMENT_BRACKET_TEMPLATE_NOT_DRAFT' using errcode = '22023';
  end if;
  if source_template.qualification_snapshot_id is distinct from state_row.current_qualification_snapshot_id
     or not exists (
       select 1 from public.pachanga_tournament_qualification_snapshots snapshots
       where snapshots.id = source_template.qualification_snapshot_id
         and snapshots.status = 'PUBLISHED'
     ) then raise exception 'TOURNAMENT_BRACKET_TEMPLATE_INPUT_STALE' using errcode = 'PT409'; end if;
  published_snapshot := jsonb_set(
    source_template.template_snapshot, '{status}', '"PUBLISHED"'::jsonb, true
  );
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'sourceTemplateId', source_template.id,
    'sourceChecksum', source_template.checksum,
    'template', published_snapshot
  ));
  insert into public.pachanga_tournament_bracket_templates(
    id, group_stage_state_id, competition_id, edition_id, stage_id,
    rule_revision_id, qualification_snapshot_id, supersedes_template_id,
    status, bracket_size, first_round_match_count, slot_count,
    template_snapshot, checksum, operation_id, created_by, created_at,
    published_by, published_at, server_sequence
  ) values (
    published_template_id, source_template.group_stage_state_id,
    source_template.competition_id, source_template.edition_id,
    source_template.stage_id, source_template.rule_revision_id,
    source_template.qualification_snapshot_id, source_template.id,
    'PUBLISHED', source_template.bracket_size,
    source_template.first_round_match_count, source_template.slot_count,
    published_snapshot, checksum_value, target_operation_id, target_actor_id,
    source_template.created_at, target_actor_id, clock_timestamp(),
    target_server_sequence
  );
  insert into public.pachanga_tournament_bracket_slots(
    bracket_template_id, slot_key, match_number, side, bracket_order,
    source_kind, source_group_id, source_position, source_extra_rank,
    source_draw_seed, resolved_entry_id, status, source_snapshot,
    server_sequence
  ) select published_template_id, slots.slot_key, slots.match_number,
    slots.side, slots.bracket_order, slots.source_kind,
    slots.source_group_id, slots.source_position, slots.source_extra_rank,
    slots.source_draw_seed, slots.resolved_entry_id, slots.status,
    slots.source_snapshot, nextval('private.pachanga_competition_sequence')
  from public.pachanga_tournament_bracket_slots slots
  where slots.bracket_template_id = source_template.id
  order by slots.bracket_order, slots.id;
  update public.pachanga_tournament_group_stage_states states set
    current_bracket_template_id = published_template_id,
    revision = states.revision + 1, server_sequence = target_server_sequence,
    updated_by = target_actor_id, updated_at = clock_timestamp()
  where states.id = state_row.id;
  return private.pachanga_tournament_group_stage_snapshot_v1(target_competition_id, true)
    || jsonb_build_object(
      'bracketTemplateId', published_template_id,
      'bracketTemplateStatus', 'PUBLISHED',
      'bracketTemplateChecksum', checksum_value,
      'knockoutMatchCount', 0,
      'bracketProgressionEnabled', false
    );
end;
$$;

revoke all on function private.pachanga_tournament_bracket_template_publish_v1(
  uuid,uuid,uuid,bigint
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_ensure_catalog_v1(
  target_competition_id uuid,
  target_rule_revision_id uuid,
  target_actor_id uuid
)
returns public.pachanga_competition_discipline_rule_catalogs
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_catalog public.pachanga_competition_discipline_rule_catalogs%rowtype;
declare selected_competition public.pachanga_competitions%rowtype;
declare default_policy jsonb := private.pachanga_competition_discipline_default_policy_v1();
declare computed_checksum text;
begin
  select * into selected_catalog
  from public.pachanga_competition_discipline_rule_catalogs catalogs
  where catalogs.rule_revision_id = target_rule_revision_id;
  if found then
    if selected_catalog.competition_id <> target_competition_id then
      raise exception 'DISCIPLINE_RULE_CATALOG_SCOPE_MISMATCH' using errcode = '22023';
    end if;
    return selected_catalog;
  end if;
  select * into selected_competition
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected_competition.product_key not in (
    'LEAGUE_PRIVATE_BETA_V1', 'TOURNAMENT_PRIVATE_BETA_V1'
  ) then raise exception 'DISCIPLINE_RULE_CATALOG_REQUIRED' using errcode = '22023'; end if;
  if selected_competition.product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
     and not exists (
       select 1 from public.pachanga_tournament_group_stage_states states
       where states.competition_id = target_competition_id
         and states.rule_revision_id = target_rule_revision_id
         and states.status in ('schedule_published', 'active', 'complete')
     ) then raise exception 'TOURNAMENT_GROUP_STAGE_NOT_ACTIVE' using errcode = '22023'; end if;
  if not exists (
    select 1
    from public.pachanga_competition_rule_revisions revisions
    join public.pachanga_competition_rule_sets sets on sets.id = revisions.rule_set_id
    where revisions.id = target_rule_revision_id
      and sets.competition_id = target_competition_id
      and revisions.status in ('published', 'frozen')
  ) then raise exception 'DISCIPLINE_RULE_REVISION_INVALID' using errcode = '22023'; end if;
  computed_checksum := encode(
    extensions.digest(convert_to(default_policy::text, 'UTF8'), 'sha256'),
    'hex'
  );
  insert into public.pachanga_competition_discipline_rule_catalogs(
    rule_revision_id, competition_id, policy_version, card_type_catalog,
    cycle_policy, sanction_policy, appeal_policy, public_reason_categories,
    checksum, created_by
  ) values (
    target_rule_revision_id, target_competition_id,
    default_policy ->> 'policyVersion', default_policy -> 'cardTypeCatalog',
    default_policy -> 'cyclePolicy', default_policy -> 'sanctionPolicy',
    default_policy -> 'appealPolicy', default_policy -> 'publicReasonCategories',
    computed_checksum, target_actor_id
  ) returning * into selected_catalog;
  return selected_catalog;
end;
$$;

revoke all on function private.pachanga_competition_discipline_ensure_catalog_v1(
  uuid,uuid,uuid
) from public, anon, authenticated;

-- R4C's algorithm is unchanged. This recompilation only makes its intended
-- local-variable precedence explicit for persisted tie-lot lookups.
create or replace function private.pachanga_league_standings_rebuild_v1(
  target_context_id uuid,
  target_rebuild_kind text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare policy jsonb;
declare criteria jsonb;
declare criterion text;
declare criterion_index integer := 0;
declare allow_shared boolean;
declare state_row public.pachanga_competition_standing_states%rowtype;
declare snapshot_id uuid := gen_random_uuid();
declare previous_checksum text;
declare confirmed_checksum text;
declare source_revision bigint;
declare row_total integer;
declare group_row record;
declare candidate_checksum text;
declare tie_group_key text;
declare lot_row public.pachanga_competition_persisted_draw_lots%rowtype;
declare started_at timestamptz := clock_timestamp();
declare duration_ms integer;
declare scope_match_count integer := 0;
declare scope_official_count integer := 0;
declare scope_is_complete boolean := false;
begin
  if upper(target_rebuild_kind) not in ('INCREMENTAL', 'FULL_AUDIT') then
    raise exception 'R4C_REBUILD_KIND_INVALID' using errcode = '22023';
  end if;
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  policy := private.pachanga_league_match_policy_v1(context_row.rule_revision_id);
  criteria := coalesce(policy -> 'tieBreakCriteria', '[]'::jsonb);
  allow_shared := coalesce((policy ->> 'allowSharedPositions')::boolean, false);
  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws(':', context_row.stage_id, context_row.division_id, context_row.competition_group_id),
    91407
  ));

  select
    count(distinct contexts.id)::integer,
    (count(distinct contexts.id) filter (
      where contexts.status = 'official'
        and sheets.active_official_decision_id is not null
        and decisions.id is not null
    ))::integer
  into scope_match_count, scope_official_count
  from public.pachanga_competition_match_contexts contexts
  left join public.pachanga_competition_match_sheets sheets
    on sheets.competition_match_context_id = contexts.id
  left join public.pachanga_competition_official_result_decisions decisions
    on decisions.id = sheets.active_official_decision_id
  where contexts.stage_id = context_row.stage_id
    and contexts.division_id is not distinct from context_row.division_id
    and contexts.competition_group_id is not distinct from context_row.competition_group_id
    and contexts.rule_revision_id = context_row.rule_revision_id
    and contexts.status <> 'retired';
  scope_is_complete := scope_match_count > 0
    and scope_official_count = scope_match_count;

  select * into state_row
  from public.pachanga_competition_standing_states states
  where states.stage_id = context_row.stage_id
    and states.division_id is not distinct from context_row.division_id
    and states.competition_group_id is not distinct from context_row.competition_group_id
  for update;
  if not found then
    insert into public.pachanga_competition_standing_states(
      competition_id, edition_id, stage_id, division_id, competition_group_id,
      rule_revision_id, health_status, server_sequence
    ) values (
      context_row.competition_id, context_row.edition_id, context_row.stage_id,
      context_row.division_id, context_row.competition_group_id,
      context_row.rule_revision_id, 'PENDING', target_server_sequence
    ) returning * into state_row;
  elsif state_row.rule_revision_id <> context_row.rule_revision_id then
    raise exception 'R4C_STANDINGS_RULE_REVISION_MISMATCH' using errcode = 'PT409';
  end if;
  if state_row.current_snapshot_id is not null then
    select snapshots.content_checksum into previous_checksum
    from public.pachanga_competition_standing_snapshots snapshots
    where snapshots.id = state_row.current_snapshot_id;
  end if;

  drop table if exists pg_temp.r4c_standings_work;
  drop table if exists pg_temp.r4c_tie_explanations;
  create temporary table pg_temp.r4c_standings_work (
    entry_id uuid primary key,
    played integer not null,
    wins integer not null,
    draws integer not null,
    losses integer not null,
    goals_for integer not null,
    goals_against integer not null,
    goal_difference integer not null,
    base_points numeric(12,3) not null,
    adjustment_points numeric(12,3) not null,
    effective_points numeric(12,3) not null,
    criterion_value numeric not null default 0,
    sort_key numeric[] not null,
    tie_break_values jsonb not null default '[]'::jsonb,
    final_position integer,
    team_snapshot jsonb not null
  ) on commit drop;
  create temporary table pg_temp.r4c_tie_explanations (
    tie_group_key text not null,
    candidate_entry_ids uuid[] not null,
    criterion text not null,
    criterion_order integer not null,
    values_by_entry jsonb not null,
    resolved boolean not null,
    public_explanation text not null
  ) on commit drop;

  insert into pg_temp.r4c_standings_work(
    entry_id, played, wins, draws, losses, goals_for, goals_against,
    goal_difference, base_points, adjustment_points, effective_points,
    sort_key, team_snapshot
  )
  with official_matches as (
    select contexts.home_entry_id, contexts.away_entry_id,
      decisions.effective_score_home as score_home,
      decisions.effective_score_away as score_away
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_match_sheets sheets
      on sheets.competition_match_context_id = contexts.id
    join public.pachanga_competition_official_result_decisions decisions
      on decisions.id = sheets.active_official_decision_id
    where contexts.stage_id = context_row.stage_id
      and contexts.division_id is not distinct from context_row.division_id
      and contexts.competition_group_id is not distinct from context_row.competition_group_id
      and contexts.rule_revision_id = context_row.rule_revision_id
      and contexts.status = 'official'
      and decisions.outcome <> 'ANNULLED'
  ), entry_stats as (
    select memberships.entry_id,
      count(matches.entry_id)::integer as played,
      count(matches.entry_id) filter (where matches.goals_for > matches.goals_against)::integer as wins,
      count(matches.entry_id) filter (where matches.goals_for = matches.goals_against)::integer as draws,
      count(matches.entry_id) filter (where matches.goals_for < matches.goals_against)::integer as losses,
      coalesce(sum(matches.goals_for), 0)::integer as goals_for,
      coalesce(sum(matches.goals_against), 0)::integer as goals_against
    from public.pachanga_competition_stage_memberships memberships
    left join lateral (
      select official.home_entry_id as entry_id,
        official.score_home as goals_for, official.score_away as goals_against
      from official_matches official where official.home_entry_id = memberships.entry_id
      union all
      select official.away_entry_id,
        official.score_away, official.score_home
      from official_matches official where official.away_entry_id = memberships.entry_id
    ) matches on true
    where memberships.stage_id = context_row.stage_id
      and memberships.division_id is not distinct from context_row.division_id
      and memberships.competition_group_id is not distinct from context_row.competition_group_id
      and memberships.rule_revision_id = context_row.rule_revision_id
      and memberships.status = 'active'
    group by memberships.entry_id
  )
  select stats.entry_id, stats.played, stats.wins, stats.draws, stats.losses,
    stats.goals_for, stats.goals_against,
    stats.goals_for - stats.goals_against,
    stats.wins * (policy ->> 'pointsForWin')::numeric
      + stats.draws * (policy ->> 'pointsForDraw')::numeric
      + stats.losses * (policy ->> 'pointsForLoss')::numeric,
    0::numeric,
    stats.wins * (policy ->> 'pointsForWin')::numeric
      + stats.draws * (policy ->> 'pointsForDraw')::numeric
      + stats.losses * (policy ->> 'pointsForLoss')::numeric,
    array[-(
      stats.wins * (policy ->> 'pointsForWin')::numeric
      + stats.draws * (policy ->> 'pointsForDraw')::numeric
      + stats.losses * (policy ->> 'pointsForLoss')::numeric
    )],
    jsonb_build_object('entryId', entries.id, 'teamId', entries.team_id, 'name', groups.name)
  from entry_stats stats
  join public.pachanga_competition_entries entries on entries.id = stats.entry_id
  join public.pachanga_groups groups on groups.id = entries.team_id;

  for criterion in select value #>> '{}' from jsonb_array_elements(criteria)
  loop
    criterion_index := criterion_index + 1;
    update pg_temp.r4c_standings_work work set criterion_value = case criterion
      when 'GOAL_DIFFERENCE' then work.goal_difference
      when 'GOALS_FOR' then work.goals_for
      when 'WINS' then work.wins
      else 0
    end
    where work.entry_id is not null;

    for group_row in
      select work.sort_key,
        array_agg(work.entry_id order by work.entry_id) as candidates
      from pg_temp.r4c_standings_work work
      group by work.sort_key
      having count(*) > 1
    loop
      candidate_checksum := encode(extensions.digest(convert_to(
        array_to_string(group_row.candidates, ','), 'UTF8'
      ), 'sha256'), 'hex');
      tie_group_key := encode(extensions.digest(convert_to(concat_ws(':',
        context_row.stage_id, coalesce(context_row.division_id::text, '-'),
        coalesce(context_row.competition_group_id::text, '-'),
        array_to_string(group_row.sort_key, ','), candidate_checksum
      ), 'UTF8'), 'sha256'), 'hex');

      if criterion in (
        'HEAD_TO_HEAD_POINTS', 'HEAD_TO_HEAD_GOAL_DIFFERENCE', 'HEAD_TO_HEAD_GOALS_FOR'
      ) then
        update pg_temp.r4c_standings_work work set criterion_value = coalesce((
          with mini_matches as (
            select contexts.home_entry_id, contexts.away_entry_id,
              decisions.effective_score_home as score_home,
              decisions.effective_score_away as score_away
            from public.pachanga_competition_match_contexts contexts
            join public.pachanga_competition_match_sheets sheets
              on sheets.competition_match_context_id = contexts.id
            join public.pachanga_competition_official_result_decisions decisions
              on decisions.id = sheets.active_official_decision_id
            where contexts.stage_id = context_row.stage_id
              and contexts.division_id is not distinct from context_row.division_id
              and contexts.competition_group_id is not distinct from context_row.competition_group_id
              and contexts.rule_revision_id = context_row.rule_revision_id
              and contexts.status = 'official'
              and decisions.outcome <> 'ANNULLED'
              and contexts.home_entry_id = any(group_row.candidates)
              and contexts.away_entry_id = any(group_row.candidates)
          ), mini_stats as (
            select sum(stats.points)::numeric as points,
              sum(stats.goals_for)::numeric as goals_for,
              sum(stats.goals_against)::numeric as goals_against
            from (
              select case when matches.score_home > matches.score_away then (policy ->> 'pointsForWin')::numeric
                     when matches.score_home = matches.score_away then (policy ->> 'pointsForDraw')::numeric
                     else (policy ->> 'pointsForLoss')::numeric end as points,
                matches.score_home as goals_for, matches.score_away as goals_against
              from mini_matches matches where matches.home_entry_id = work.entry_id
              union all
              select case when matches.score_away > matches.score_home then (policy ->> 'pointsForWin')::numeric
                     when matches.score_away = matches.score_home then (policy ->> 'pointsForDraw')::numeric
                     else (policy ->> 'pointsForLoss')::numeric end,
                matches.score_away, matches.score_home
              from mini_matches matches where matches.away_entry_id = work.entry_id
            ) stats
          ) select case criterion
            when 'HEAD_TO_HEAD_POINTS' then mini_stats.points
            when 'HEAD_TO_HEAD_GOAL_DIFFERENCE' then mini_stats.goals_for - mini_stats.goals_against
            else mini_stats.goals_for
          end from mini_stats
        ), 0)
        where work.entry_id = any(group_row.candidates);
      elsif criterion = 'PERSISTED_DRAW_LOT' then
        select * into lot_row
        from public.pachanga_competition_persisted_draw_lots lots
        where lots.stage_id = context_row.stage_id
          and lots.division_id is not distinct from context_row.division_id
          and lots.competition_group_id is not distinct from context_row.competition_group_id
          and lots.rule_revision_id = context_row.rule_revision_id
          and lots.tie_group_key = tie_group_key
          and lots.candidate_checksum = candidate_checksum;
        if found then
          update pg_temp.r4c_standings_work work
          set criterion_value = cardinality(lot_row.result_entry_ids)
            - array_position(lot_row.result_entry_ids, work.entry_id) + 1
          where work.entry_id = any(group_row.candidates);
        elsif scope_is_complete then
          raise exception 'TIE_REQUIRES_DECISION:%', tie_group_key using errcode = 'PT409';
        end if;
      end if;

      insert into pg_temp.r4c_tie_explanations(
        tie_group_key, candidate_entry_ids, criterion, criterion_order,
        values_by_entry, resolved, public_explanation
      )
      select tie_group_key, group_row.candidates, criterion, criterion_index,
        jsonb_object_agg(work.entry_id::text, work.criterion_value order by work.entry_id),
        count(distinct work.criterion_value) > 1,
        case when count(distinct work.criterion_value) > 1
          then 'El empate se separa mediante ' || criterion || '.'
          else 'El empate continúa después de aplicar ' || criterion || '.' end
      from pg_temp.r4c_standings_work work
      where work.entry_id = any(group_row.candidates);
    end loop;

    update pg_temp.r4c_standings_work work set
      sort_key = work.sort_key || (-work.criterion_value),
      tie_break_values = work.tie_break_values || jsonb_build_array(jsonb_build_object(
        'criterion', criterion, 'value', work.criterion_value
      ))
    where work.entry_id is not null;
  end loop;

  if scope_is_complete and not allow_shared and exists (
    select 1 from pg_temp.r4c_standings_work work
    group by work.sort_key having count(*) > 1
  ) then raise exception 'TIE_REQUIRES_DECISION' using errcode = 'PT409'; end if;

  update pg_temp.r4c_standings_work work set final_position = ranked.position
  from (
    select standings.entry_id,
      rank() over (order by standings.sort_key)::integer as position
    from pg_temp.r4c_standings_work standings
  ) ranked
  where ranked.entry_id = work.entry_id;

  select count(*)::integer into row_total from pg_temp.r4c_standings_work;
  select coalesce(max(decisions.server_sequence), 0) into source_revision
  from public.pachanga_competition_match_contexts contexts
  join public.pachanga_competition_match_sheets sheets
    on sheets.competition_match_context_id = contexts.id
  join public.pachanga_competition_official_result_decisions decisions
    on decisions.id = sheets.active_official_decision_id
  where contexts.stage_id = context_row.stage_id
    and contexts.division_id is not distinct from context_row.division_id
    and contexts.competition_group_id is not distinct from context_row.competition_group_id
    and contexts.rule_revision_id = context_row.rule_revision_id;

  select encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object(
    'entryId', work.entry_id,
    'position', work.final_position,
    'played', work.played,
    'wins', work.wins,
    'draws', work.draws,
    'losses', work.losses,
    'goalsFor', work.goals_for,
    'goalsAgainst', work.goals_against,
    'goalDifference', work.goal_difference,
    'basePoints', work.base_points,
    'adjustmentPoints', work.adjustment_points,
    'effectivePoints', work.effective_points,
    'tieBreakValues', work.tie_break_values
  ) order by work.final_position, work.entry_id), '[]'::jsonb)::text, 'UTF8'), 'sha256'), 'hex')
  into confirmed_checksum
  from pg_temp.r4c_standings_work work;

  insert into public.pachanga_competition_standing_snapshots(
    id, standing_state_id, competition_id, edition_id, stage_id, division_id,
    competition_group_id, rule_revision_id, supersedes_snapshot_id, rebuild_kind,
    source_revision, row_count, tie_break_criteria, content_checksum, server_sequence
  ) values (
    snapshot_id, state_row.id, context_row.competition_id, context_row.edition_id,
    context_row.stage_id, context_row.division_id, context_row.competition_group_id,
    context_row.rule_revision_id, state_row.current_snapshot_id, upper(target_rebuild_kind),
    source_revision, row_total, jsonb_build_array('POINTS') || criteria,
    confirmed_checksum, target_server_sequence
  );
  insert into public.pachanga_competition_standing_rows(
    standing_snapshot_id, entry_id, position, played, wins, draws, losses,
    goals_for, goals_against, goal_difference, base_points, adjustment_points,
    effective_points, tie_break_values, team_snapshot, server_sequence
  )
  select snapshot_id, work.entry_id, work.final_position, work.played, work.wins,
    work.draws, work.losses, work.goals_for, work.goals_against,
    work.goal_difference, work.base_points, work.adjustment_points,
    work.effective_points, work.tie_break_values, work.team_snapshot,
    target_server_sequence
  from pg_temp.r4c_standings_work work
  order by work.final_position, work.entry_id;
  insert into public.pachanga_competition_tie_break_explanations(
    standing_snapshot_id, tie_group_key, candidate_entry_ids, criterion,
    criterion_order, values_by_entry, resolved, public_explanation, server_sequence
  )
  select snapshot_id, explanations.tie_group_key, explanations.candidate_entry_ids,
    explanations.criterion, explanations.criterion_order,
    explanations.values_by_entry, explanations.resolved,
    explanations.public_explanation, target_server_sequence
  from pg_temp.r4c_tie_explanations explanations
  order by explanations.criterion_order, explanations.tie_group_key;

  update public.pachanga_competition_standing_states states set
    current_snapshot_id = snapshot_id,
    health_status = 'CURRENT',
    revision = states.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where states.id = state_row.id;
  duration_ms := greatest(0, floor(extract(epoch from (clock_timestamp() - started_at)) * 1000)::integer);
  insert into public.pachanga_competition_standing_rebuild_receipts(
    operation_id, standing_state_id, standing_snapshot_id, rebuild_kind,
    source_revision, previous_checksum, confirmed_checksum, full_audit_checksum,
    duration_ms, server_sequence
  ) values (
    target_operation_id, state_row.id, snapshot_id, upper(target_rebuild_kind),
    source_revision, previous_checksum, confirmed_checksum,
    case when upper(target_rebuild_kind) = 'FULL_AUDIT' then confirmed_checksum else null end,
    duration_ms, target_server_sequence
  );
  return jsonb_build_object(
    'standingStateId', state_row.id,
    'standingSnapshotId', snapshot_id,
    'revision', state_row.revision + 1,
    'sourceRevision', source_revision,
    'checksum', confirmed_checksum,
    'rowCount', row_total,
    'rebuildKind', upper(target_rebuild_kind),
    'durationMs', duration_ms
  );
end;
$$;

revoke all on function private.pachanga_league_standings_rebuild_v1(
  uuid, text, uuid, uuid, bigint
) from public, anon, authenticated;
