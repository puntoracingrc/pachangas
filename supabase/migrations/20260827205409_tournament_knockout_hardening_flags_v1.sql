-- Pachangas IQ R6C: dependency gates, fail-closed flags, capability matrix,
-- canonical generation guard and bounded indexes. Every new flag is born OFF.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists tournament_knockout_foundation_enabled boolean not null default false,
  add column if not exists tournament_extra_time_enabled boolean not null default false,
  add column if not exists tournament_penalty_shootout_enabled boolean not null default false,
  add column if not exists tournament_third_place_enabled boolean not null default false,
  add column if not exists tournament_completion_enabled boolean not null default false,
  add column if not exists tournament_two_leg_enabled boolean not null default false,
  add column if not exists tournament_double_elimination_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_tournament_flags_check,
  drop constraint if exists pachanga_comp_foundation_tournament_r6b_boundary_check,
  add constraint pachanga_comp_foundation_tournament_flags_check check (
    (not tournament_private_beta_enabled or tournament_foundation_enabled)
    and (not tournament_creation_enabled or (
      tournament_private_beta_enabled and foundation_enabled and creation_enabled
    ))
    and (not tournament_draw_enabled or tournament_private_beta_enabled)
    and (not tournament_automatic_draw_enabled or tournament_draw_enabled)
    and (not tournament_draw_manual_enabled or tournament_draw_enabled)
    and (not tournament_draw_hybrid_enabled or (
      tournament_draw_enabled and tournament_draw_manual_enabled
    ))
    and (not tournament_draw_publish_enabled or tournament_draw_enabled)
    and (not tournament_public_discovery_enabled or tournament_foundation_enabled)
    and (not tournament_group_stage_enabled or tournament_draw_publish_enabled)
    and (not tournament_group_scheduling_enabled or tournament_group_stage_enabled)
    and (not tournament_group_match_generation_enabled or tournament_group_scheduling_enabled)
    and (not tournament_group_tracking_enabled or tournament_group_match_generation_enabled)
    and (not tournament_group_standings_enabled or tournament_group_tracking_enabled)
    and (not tournament_qualification_enabled or tournament_group_standings_enabled)
    and (not tournament_bracket_template_enabled or tournament_qualification_enabled)
    and (not tournament_knockout_foundation_enabled or tournament_bracket_template_enabled)
    and (not tournament_knockout_match_generation_enabled or (
      tournament_knockout_foundation_enabled and tournament_bracket_progression_enabled
    ))
    and (not tournament_bracket_progression_enabled or tournament_knockout_foundation_enabled)
    and (not tournament_extra_time_enabled or tournament_knockout_foundation_enabled)
    and (not tournament_penalty_shootout_enabled or tournament_knockout_foundation_enabled)
    and (not tournament_third_place_enabled or tournament_knockout_foundation_enabled)
    and (not tournament_completion_enabled or tournament_bracket_progression_enabled)
    and (tournament_match_generation_enabled = (
      tournament_group_match_generation_enabled or tournament_knockout_match_generation_enabled
    ))
  ),
  add constraint pachanga_comp_foundation_tournament_r6c_boundary_check check (
    not tournament_public_discovery_enabled
    and not tournament_two_leg_enabled
    and not tournament_double_elimination_enabled
  );

create or replace function private.pachanga_tournament_gate_dependencies_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare r6c_authority boolean := current_setting(
  'pachangas.r6c_flag_authority', true
) = 'on';
begin
  if tg_op = 'UPDATE' and not r6c_authority
     and new.tournament_foundation_enabled and new.tournament_private_beta_enabled then
    new.tournament_knockout_foundation_enabled := old.tournament_knockout_foundation_enabled;
    new.tournament_knockout_match_generation_enabled := old.tournament_knockout_match_generation_enabled;
    new.tournament_bracket_progression_enabled := old.tournament_bracket_progression_enabled;
    new.tournament_extra_time_enabled := old.tournament_extra_time_enabled;
    new.tournament_penalty_shootout_enabled := old.tournament_penalty_shootout_enabled;
    new.tournament_third_place_enabled := old.tournament_third_place_enabled;
    new.tournament_completion_enabled := old.tournament_completion_enabled;
  end if;
  if not new.foundation_enabled then
    new.tournament_foundation_enabled := false;
  end if;
  if not new.tournament_foundation_enabled then
    new.tournament_private_beta_enabled := false;
  end if;
  if not new.tournament_private_beta_enabled then
    new.tournament_creation_enabled := false;
    new.tournament_draw_enabled := false;
  end if;
  if not new.creation_enabled then
    new.tournament_creation_enabled := false;
  end if;
  if not new.tournament_draw_enabled then
    new.tournament_automatic_draw_enabled := false;
    new.tournament_draw_manual_enabled := false;
    new.tournament_draw_hybrid_enabled := false;
    new.tournament_draw_publish_enabled := false;
  end if;
  if not new.tournament_draw_manual_enabled then
    new.tournament_draw_hybrid_enabled := false;
  end if;
  if not new.tournament_draw_publish_enabled then
    new.tournament_group_stage_enabled := false;
  end if;
  if not new.tournament_group_stage_enabled then
    new.tournament_group_scheduling_enabled := false;
  end if;
  if not new.tournament_group_scheduling_enabled then
    new.tournament_group_match_generation_enabled := false;
  end if;
  if not new.tournament_group_match_generation_enabled then
    new.tournament_group_tracking_enabled := false;
  end if;
  if not new.tournament_group_tracking_enabled then
    new.tournament_group_standings_enabled := false;
  end if;
  if not new.tournament_group_standings_enabled then
    new.tournament_qualification_enabled := false;
  end if;
  if not new.tournament_qualification_enabled then
    new.tournament_bracket_template_enabled := false;
  end if;
  if not new.tournament_bracket_template_enabled then
    new.tournament_knockout_foundation_enabled := false;
  end if;
  if not new.tournament_knockout_foundation_enabled then
    new.tournament_knockout_match_generation_enabled := false;
    new.tournament_bracket_progression_enabled := false;
    new.tournament_extra_time_enabled := false;
    new.tournament_penalty_shootout_enabled := false;
    new.tournament_third_place_enabled := false;
    new.tournament_completion_enabled := false;
  end if;
  if not new.tournament_knockout_match_generation_enabled then
    new.tournament_bracket_progression_enabled := false;
  end if;
  if not new.tournament_bracket_progression_enabled then
    new.tournament_completion_enabled := false;
  end if;
  new.tournament_match_generation_enabled :=
    new.tournament_group_match_generation_enabled
    or new.tournament_knockout_match_generation_enabled;
  new.tournament_public_discovery_enabled := false;
  new.tournament_two_leg_enabled := false;
  new.tournament_double_elimination_enabled := false;
  return new;
end;
$$;

create or replace function private.pachanga_tournament_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.tournament_foundation_enabled,
    'privateBetaEnabled', settings.tournament_private_beta_enabled,
    'creationEnabled', settings.tournament_creation_enabled,
    'drawEnabled', settings.tournament_draw_enabled,
    'automaticEnabled', settings.tournament_automatic_draw_enabled,
    'manualEnabled', settings.tournament_draw_manual_enabled,
    'hybridEnabled', settings.tournament_draw_hybrid_enabled,
    'publishEnabled', settings.tournament_draw_publish_enabled,
    'groupStageEnabled', settings.tournament_group_stage_enabled,
    'groupSchedulingEnabled', settings.tournament_group_scheduling_enabled,
    'groupMatchGenerationEnabled', settings.tournament_group_match_generation_enabled,
    'matchGenerationEnabled', settings.tournament_match_generation_enabled,
    'groupTrackingEnabled', settings.tournament_group_tracking_enabled,
    'groupStandingsEnabled', settings.tournament_group_standings_enabled,
    'qualificationEnabled', settings.tournament_qualification_enabled,
    'bracketTemplateEnabled', settings.tournament_bracket_template_enabled,
    'knockoutFoundationEnabled', settings.tournament_knockout_foundation_enabled,
    'knockoutMatchGenerationEnabled', settings.tournament_knockout_match_generation_enabled,
    'bracketProgressionEnabled', settings.tournament_bracket_progression_enabled,
    'extraTimeEnabled', settings.tournament_extra_time_enabled,
    'penaltyShootoutEnabled', settings.tournament_penalty_shootout_enabled,
    'thirdPlaceEnabled', settings.tournament_third_place_enabled,
    'completionEnabled', settings.tournament_completion_enabled,
    'twoLegEnabled', settings.tournament_two_leg_enabled,
    'doubleEliminationEnabled', settings.tournament_double_elimination_enabled,
    'publicDiscoveryEnabled', settings.tournament_public_discovery_enabled,
    'standardTeamCap', settings.tournament_standard_team_cap,
    'overrideTeamCap', settings.tournament_override_team_cap,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_tournament_group_stage_assert_flags_v1(
  target_action text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare action_name text := lower(trim(coalesce(target_action, '')));
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.tournament_foundation_enabled
     or not settings.tournament_private_beta_enabled
     or not settings.tournament_group_stage_enabled then
    raise exception 'TOURNAMENT_GROUP_STAGE_DISABLED' using errcode = '42501';
  end if;
  if action_name in (
       'group_schedule.create','group_schedule.generate','group_schedule.validate'
     ) and not settings.tournament_group_scheduling_enabled then
    raise exception 'TOURNAMENT_GROUP_SCHEDULING_DISABLED' using errcode = '42501';
  end if;
  if action_name = 'group_schedule.publish'
     and (not settings.tournament_group_match_generation_enabled
       or not settings.tournament_match_generation_enabled) then
    raise exception 'TOURNAMENT_GROUP_MATCH_GENERATION_DISABLED' using errcode = '42501';
  end if;
  if action_name in ('group_stage.activate','group_stage.complete')
     and not settings.tournament_group_tracking_enabled then
    raise exception 'TOURNAMENT_GROUP_TRACKING_DISABLED' using errcode = '42501';
  end if;
  if action_name like 'qualification.%'
     and (not settings.tournament_group_standings_enabled
       or not settings.tournament_qualification_enabled) then
    raise exception 'TOURNAMENT_QUALIFICATION_DISABLED' using errcode = '42501';
  end if;
  if action_name like 'bracket_template.%'
     and not settings.tournament_bracket_template_enabled then
    raise exception 'TOURNAMENT_BRACKET_TEMPLATE_DISABLED' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.pachanga_tournament_knockout_assert_flags_v1(
  target_action text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare action_name text := lower(trim(coalesce(target_action, '')));
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.tournament_foundation_enabled
     or not settings.tournament_private_beta_enabled
     or not settings.tournament_knockout_foundation_enabled then
    raise exception 'TOURNAMENT_KNOCKOUT_DISABLED' using errcode = '42501';
  end if;
  if action_name in (
    'bracket.node.generate_match','bracket.admin.replace_downstream'
  ) and (not settings.tournament_knockout_match_generation_enabled
    or not settings.tournament_match_generation_enabled) then
    raise exception 'TOURNAMENT_KNOCKOUT_MATCH_GENERATION_DISABLED' using errcode = '42501';
  end if;
  if action_name not in ('bracket.reserve_slot')
     and not settings.tournament_bracket_progression_enabled then
    raise exception 'TOURNAMENT_BRACKET_PROGRESSION_DISABLED' using errcode = '42501';
  end if;
  if action_name like 'tournament.%'
     and not settings.tournament_completion_enabled then
    raise exception 'TOURNAMENT_COMPLETION_DISABLED' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.pachanga_tournament_knockout_insert_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.tournament_knockout_foundation_enabled
     or not settings.tournament_bracket_progression_enabled then
    raise exception 'TOURNAMENT_KNOCKOUT_DISABLED' using errcode = '42501';
  end if;
  if tg_table_name = 'pachanga_tournament_brackets' then
    if new.third_place_enabled and not settings.tournament_third_place_enabled then
      raise exception 'TOURNAMENT_THIRD_PLACE_DISABLED' using errcode = '42501';
    end if;
  elsif tg_table_name = 'pachanga_tournament_knockout_result_resolutions' then
    if new.extra_time_played and not settings.tournament_extra_time_enabled then
      raise exception 'TOURNAMENT_EXTRA_TIME_DISABLED' using errcode = '42501';
    end if;
    if new.shootout_home is not null and not settings.tournament_penalty_shootout_enabled then
      raise exception 'TOURNAMENT_PENALTY_SHOOTOUT_DISABLED' using errcode = '42501';
    end if;
  end if;
  if tg_table_name = 'pachanga_tournament_completion_snapshots'
     and not settings.tournament_completion_enabled then
    raise exception 'TOURNAMENT_COMPLETION_DISABLED' using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger guard_pachanga_tournament_bracket_flags_v1
before insert on public.pachanga_tournament_brackets
for each row execute function private.pachanga_tournament_knockout_insert_guard_v1();
create trigger guard_pachanga_tournament_resolution_flags_v1
before insert on public.pachanga_tournament_knockout_result_resolutions
for each row execute function private.pachanga_tournament_knockout_insert_guard_v1();
create trigger guard_pachanga_tournament_advance_flags_v1
before insert on public.pachanga_tournament_bracket_advance_decisions
for each row execute function private.pachanga_tournament_knockout_insert_guard_v1();
create trigger guard_pachanga_tournament_completion_flags_v1
before insert on public.pachanga_tournament_completion_snapshots
for each row execute function private.pachanga_tournament_knockout_insert_guard_v1();

create or replace function private.pachanga_tournament_reject_match_generation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
begin
  if not exists (
    select 1 from public.pachanga_competitions competitions
    where competitions.id = new.competition_id
      and competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
  ) then return new; end if;
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if current_setting('pachangas.r6c_match_publish', true) = 'on' then
    select * into node_row
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.canonical_match_id = new.canonical_match_id;
    if not settings.tournament_match_generation_enabled
       or not settings.tournament_knockout_match_generation_enabled
       or not settings.tournament_bracket_progression_enabled
       or new.source_kind <> 'COMPETITION_GENERATED'
       or new.schedule_item_id is not null or new.round_id is null
       or node_row.id is null
       or node_row.home_entry_id <> new.home_entry_id
       or node_row.away_entry_id <> new.away_entry_id
       or not exists (
         select 1
         from public.pachanga_tournament_brackets brackets
         join public.pachanga_tournament_bracket_fixture_reservations reservations
           on reservations.bracket_id = brackets.id
          and reservations.bracket_node_id = node_row.id
         join public.pachanga_competition_rounds rounds on rounds.id = new.round_id
         join public.pachanga_competition_schedule_revisions revisions
           on revisions.id = rounds.schedule_revision_id
         join public.pachanga_competition_schedule_plans plans
           on plans.id = revisions.schedule_plan_id
         where brackets.id = node_row.bracket_id
           and brackets.competition_id = new.competition_id
           and brackets.edition_id = new.edition_id
           and brackets.category_id = new.category_id
           and brackets.knockout_stage_id = new.stage_id
           and brackets.rule_revision_id = new.rule_revision_id
           and brackets.status in ('active', 'administrative_review')
           and rounds.round_number = node_row.round_order
           and rounds.competition_id = brackets.competition_id
           and rounds.edition_id = brackets.edition_id
           and rounds.category_id = brackets.category_id
           and rounds.stage_id = brackets.knockout_stage_id
           and rounds.rule_revision_id = brackets.rule_revision_id
           and rounds.status in ('published', 'in_progress', 'completed', 'locked')
           and revisions.id = private.pachanga_tournament_knockout_entity_id_v1(
             brackets.id, 'r4b-schedule-revision-v1'
           )
           and revisions.status = 'published'
           and revisions.engine_version = 'tournament-knockout-v1'
           and plans.id = private.pachanga_tournament_knockout_entity_id_v1(
             brackets.id, 'r4b-schedule-plan'
           )
           and plans.current_revision_id = revisions.id
           and plans.status = 'published'
           and plans.engine_version = 'tournament-knockout-v1'
           and reservations.schedule_slot_id = new.slot_id
           and reservations.status = 'ACTIVE'
           and not exists (
             select 1
             from public.pachanga_tournament_bracket_fixture_reservations newer
             where newer.bracket_node_id = reservations.bracket_node_id
               and newer.reservation_revision > reservations.reservation_revision
           )
       ) then
      raise exception 'TOURNAMENT_KNOCKOUT_MATCH_GENERATION_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    return new;
  end if;
  if not settings.tournament_match_generation_enabled
     or not settings.tournament_group_match_generation_enabled
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
  if target_capability in (
    'read','draw_read','schedule_read','results_read','standings_read','bracket_read'
  ) then
    select exists (
      select 1
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      where entries.competition_id = target_competition_id
        and entries.status in ('accepted', 'active', 'completed')
        and (teams.owner_id = target_actor_id or exists (
          select 1 from public.pachanga_group_members members
          where members.group_id = teams.id and members.user_id = target_actor_id
        ))
    ) into participant_reader;
  end if;
  actor_role := private.pachanga_competition_actor_role_v1(
    target_competition_id, target_actor_id
  );
  if target_capability in (
    'read','draw_read','schedule_read','results_read','standings_read','bracket_read'
  ) and (participant_reader or actor_role is not null) then return true; end if;
  organizer_id := coalesce(
    competition_row.organizer_group_id, competition_row.organizer_club_id
  );
  if private.pachanga_tournament_active_bundle_id_v1(
       competition_row.organizer_kind, organizer_id
     ) is null then return false; end if;
  if actor_role = 'competition_owner' then return true; end if;
  return case actor_role
    when 'competition_director' then target_capability in (
      'read','manage','authoring','participants_manage','draw_read','draw_manage',
      'draw_validate','draw_publish','schedule_read','schedule_manage',
      'schedule_publish','results_read','results_manage','standings_read',
      'standings_manage','operations_manage','qualification_manage',
      'qualification_publish','bracket_read','bracket_manage','bracket_publish'
    )
    when 'competition_admin' then target_capability in (
      'read','manage','participants_manage','draw_read','draw_manage',
      'draw_validate','draw_publish','schedule_read','schedule_manage',
      'schedule_publish','results_read','results_manage','standings_read',
      'standings_manage','operations_manage','qualification_manage',
      'qualification_publish','bracket_read','bracket_manage','bracket_publish'
    )
    when 'competition_draw_manager' then target_capability in (
      'read','draw_read','draw_manage','draw_validate','draw_publish','bracket_read'
    )
    when 'competition_bracket_manager' then target_capability in (
      'read','bracket_read','bracket_manage','bracket_publish','schedule_read',
      'results_read','standings_read'
    )
    when 'competition_schedule_manager' then target_capability in (
      'read','schedule_read','schedule_manage','schedule_publish','bracket_read'
    )
    when 'competition_result_manager' then target_capability in (
      'read','results_read','results_manage','standings_read','bracket_read'
    )
    when 'competition_standings_manager' then target_capability in (
      'read','results_read','standings_read','standings_manage',
      'qualification_manage','qualification_publish','bracket_read',
      'bracket_manage','bracket_publish'
    )
    when 'competition_operations_manager' then target_capability in (
      'read','schedule_read','results_read','standings_read','bracket_read',
      'operations_manage'
    )
    when 'competition_registration_manager' then target_capability in (
      'read','participants_manage'
    )
    when 'rules_manager' then target_capability in ('read','authoring','draw_read')
    when 'viewer' then target_capability in (
      'read','draw_read','schedule_read','results_read','standings_read','bracket_read'
    )
    else false
  end;
end;
$$;

create or replace function public.command_pachanga_tournament_knockout_platform_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c6c1'::uuid;
declare actor_id uuid := (select auth.uid());
declare actor_kind text;
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare sequence_value bigint;
declare confirmed_revision bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare reason_text text;
declare snapshot jsonb;
begin
  if operation_id is null or aggregate_id <> flags_aggregate_id
     or expected_revision is null or expected_revision < 0
     or normalized_action <> 'tournament.knockout.flags.set'
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or payload - array[
       'knockoutFoundationEnabled','knockoutMatchGenerationEnabled',
       'bracketProgressionEnabled','extraTimeEnabled',
       'penaltyShootoutEnabled','thirdPlaceEnabled','completionEnabled','reason'
     ]::text[] <> '{}'::jsonb then
    raise exception 'INVALID_TOURNAMENT_KNOCKOUT_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_each(payload) item
    where item.key <> 'reason' and jsonb_typeof(item.value) <> 'boolean'
  ) then
    raise exception 'INVALID_TOURNAMENT_KNOCKOUT_FLAG' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  else
    perform private.pachanga_platform_require_v1('competitions.manage');
    perform private.pachanga_platform_require_v1('flags.write');
    actor_kind := 'authenticated';
  end if;
  reason_text := left(trim(coalesce(payload ->> 'reason', '')), 1100);
  if length(reason_text) < 3 then
    raise exception 'TOURNAMENT_PLATFORM_REASON_REQUIRED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 92603));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton for update;
  if settings.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if coalesce(
       (payload ->> 'knockoutFoundationEnabled')::boolean,
       settings.tournament_knockout_foundation_enabled
     ) and (
       not settings.tournament_foundation_enabled
       or not settings.tournament_private_beta_enabled
       or not settings.tournament_bracket_template_enabled
     ) then
    raise exception 'TOURNAMENT_KNOCKOUT_DEPENDENCY_DISABLED' using errcode = '0A000';
  end if;
  perform set_config('pachangas.r6c_flag_authority', 'on', true);
  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings foundation_settings set
    tournament_knockout_foundation_enabled = coalesce(
      (payload ->> 'knockoutFoundationEnabled')::boolean,
      foundation_settings.tournament_knockout_foundation_enabled
    ),
    tournament_knockout_match_generation_enabled = coalesce(
      (payload ->> 'knockoutMatchGenerationEnabled')::boolean,
      foundation_settings.tournament_knockout_match_generation_enabled
    ),
    tournament_bracket_progression_enabled = coalesce(
      (payload ->> 'bracketProgressionEnabled')::boolean,
      foundation_settings.tournament_bracket_progression_enabled
    ),
    tournament_extra_time_enabled = coalesce(
      (payload ->> 'extraTimeEnabled')::boolean,
      foundation_settings.tournament_extra_time_enabled
    ),
    tournament_penalty_shootout_enabled = coalesce(
      (payload ->> 'penaltyShootoutEnabled')::boolean,
      foundation_settings.tournament_penalty_shootout_enabled
    ),
    tournament_third_place_enabled = coalesce(
      (payload ->> 'thirdPlaceEnabled')::boolean,
      foundation_settings.tournament_third_place_enabled
    ),
    tournament_completion_enabled = coalesce(
      (payload ->> 'completionEnabled')::boolean,
      foundation_settings.tournament_completion_enabled
    ),
    tournament_match_generation_enabled = foundation_settings.tournament_group_match_generation_enabled
      or coalesce(
        (payload ->> 'knockoutMatchGenerationEnabled')::boolean,
        foundation_settings.tournament_knockout_match_generation_enabled
      ),
    tournament_two_leg_enabled = false,
    tournament_double_elimination_enabled = false,
    tournament_public_discovery_enabled = false,
    revision = foundation_settings.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = confirmed_at
  where foundation_settings.singleton
  returning foundation_settings.revision into confirmed_revision;
  snapshot := private.pachanga_tournament_flags_v1();
  if (payload ->> 'knockoutFoundationEnabled')::boolean is true
       and not (snapshot ->> 'knockoutFoundationEnabled')::boolean
     or (payload ->> 'knockoutMatchGenerationEnabled')::boolean is true
       and not (snapshot ->> 'knockoutMatchGenerationEnabled')::boolean
     or (payload ->> 'bracketProgressionEnabled')::boolean is true
       and not (snapshot ->> 'bracketProgressionEnabled')::boolean
     or (payload ->> 'extraTimeEnabled')::boolean is true
       and not (snapshot ->> 'extraTimeEnabled')::boolean
     or (payload ->> 'penaltyShootoutEnabled')::boolean is true
       and not (snapshot ->> 'penaltyShootoutEnabled')::boolean
     or (payload ->> 'thirdPlaceEnabled')::boolean is true
       and not (snapshot ->> 'thirdPlaceEnabled')::boolean
     or (payload ->> 'completionEnabled')::boolean is true
       and not (snapshot ->> 'completionEnabled')::boolean then
    raise exception 'TOURNAMENT_KNOCKOUT_FLAG_DEPENDENCY_DISABLED' using errcode = '0A000';
  end if;
  return private.pachanga_competition_store_command_v1(
    operation_id, actor_id, actor_kind, normalized_action,
    'tournament_knockout_flags', aggregate_id, null, null,
    confirmed_revision, sequence_value, 'tournament_knockout_flags',
    request_hash,
    private.pachanga_competition_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb)),
    snapshot - array['updatedAt']::text[], snapshot, confirmed_at
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function public.get_pachanga_platform_tournament_knockout_control_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  return jsonb_build_object(
    'flags', private.pachanga_tournament_flags_v1(),
    'metrics', jsonb_build_object(
      'brackets', (select count(*) from public.pachanga_tournament_brackets),
      'activeBrackets', (select count(*) from public.pachanga_tournament_brackets brackets
        where brackets.status in ('active','administrative_review')),
      'nodes', (select count(*) from public.pachanga_tournament_bracket_nodes),
      'knockoutMatches', (select count(*) from public.pachanga_tournament_bracket_nodes nodes
        where nodes.canonical_match_id is not null),
      'advances', (select count(*) from public.pachanga_tournament_bracket_advance_decisions),
      'invalidations', (select count(*) from public.pachanga_tournament_bracket_invalidations),
      'completionSnapshots', (select count(*) from public.pachanga_tournament_completion_snapshots)
    ),
    'health', jsonb_build_object(
      'publicDiscoveryOff', not (private.pachanga_tournament_flags_v1() ->> 'publicDiscoveryEnabled')::boolean,
      'twoLegOff', not (private.pachanga_tournament_flags_v1() ->> 'twoLegEnabled')::boolean,
      'doubleEliminationOff', not (private.pachanga_tournament_flags_v1() ->> 'doubleEliminationEnabled')::boolean,
      'rewardGrants', 0,
      'legacyBackfillCount', 0
    ),
    'updatedAt', statement_timestamp()
  );
end;
$$;

create unique index if not exists pachanga_tournament_node_canonical_match_uq
  on public.pachanga_tournament_bracket_nodes(canonical_match_id)
  where canonical_match_id is not null;
create index if not exists pachanga_tournament_bracket_status_sequence_idx
  on public.pachanga_tournament_brackets(status, server_sequence desc, id desc);
create index if not exists pachanga_tournament_node_round_status_idx
  on public.pachanga_tournament_bracket_nodes(
    bracket_id, round_order, round_code, status, node_order, id
  );
create index if not exists pachanga_tournament_slot_source_node_idx
  on public.pachanga_tournament_bracket_node_slots(
    source_node_id, slot_revision desc, server_sequence desc, id desc
  ) where source_node_id is not null;
create index if not exists pachanga_tournament_slot_current_lookup_idx
  on public.pachanga_tournament_bracket_node_slots(
    bracket_node_id, side, slot_revision desc, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_reservation_current_lookup_idx
  on public.pachanga_tournament_bracket_fixture_reservations(
    bracket_node_id, reservation_revision desc, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_advance_current_lookup_idx
  on public.pachanga_tournament_bracket_advance_decisions(
    source_node_id, revision desc, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_resolution_node_lookup_idx
  on public.pachanga_tournament_knockout_result_resolutions(
    bracket_node_id, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_round_control_current_idx
  on public.pachanga_tournament_bracket_round_controls(
    bracket_id, round_code, control_revision desc, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_invalidation_bracket_idx
  on public.pachanga_tournament_bracket_invalidations(
    bracket_id, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_completion_current_idx
  on public.pachanga_tournament_completion_snapshots(
    bracket_id, revision desc, server_sequence desc, id desc
  );

create or replace function private.pachanga_referee_replaced_statistics_sync_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_referee_refresh_statistics_v1(
    new.referee_profile_id,
    'incremental'
  );
  return new;
end;
$$;

drop trigger if exists pachanga_referee_replaced_statistics_sync_v1
  on public.pachanga_referee_assignments;
create trigger pachanga_referee_replaced_statistics_sync_v1
after update of status on public.pachanga_referee_assignments
for each row
when (old.status is distinct from new.status and new.status = 'replaced')
execute function private.pachanga_referee_replaced_statistics_sync_v1();

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_gate_dependencies_v1()'::regprocedure,
    'private.pachanga_tournament_flags_v1()'::regprocedure,
    'private.pachanga_tournament_group_stage_assert_flags_v1(text)'::regprocedure,
    'private.pachanga_tournament_knockout_assert_flags_v1(text)'::regprocedure,
    'private.pachanga_tournament_knockout_insert_guard_v1()'::regprocedure,
    'private.pachanga_tournament_reject_match_generation_v1()'::regprocedure,
    'private.pachanga_tournament_can_v1(uuid,uuid,text)'::regprocedure,
    'private.pachanga_referee_replaced_statistics_sync_v1()'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

revoke all on function public.command_pachanga_tournament_knockout_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_tournament_knockout_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated, service_role;
revoke all on function public.get_pachanga_platform_tournament_knockout_control_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_tournament_knockout_control_v1()
  to authenticated, service_role;

comment on function public.command_pachanga_tournament_knockout_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) is 'Audited R6C flag authority. Two-leg, double elimination, public discovery and payments remain fail-closed.';
comment on function private.pachanga_tournament_reject_match_generation_v1() is
  'Accepts R6B group fixtures or reservation-backed R6C knockout fixtures only inside their transaction-scoped server orchestrators.';
comment on function private.pachanga_referee_replaced_statistics_sync_v1() is
  'Keeps the original referee statistics read model canonical when replacement confirmation changes the original assignment indirectly.';
