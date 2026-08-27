-- Pachangas IQ R6B: narrow flags, dependency gates, state hardening and indexes.
-- All R6B capabilities are born OFF; production activation is a separate,
-- audited platform command.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table private.pachanga_competition_foundation_settings
  add column if not exists tournament_group_stage_enabled boolean not null default false,
  add column if not exists tournament_group_scheduling_enabled boolean not null default false,
  add column if not exists tournament_group_match_generation_enabled boolean not null default false,
  add column if not exists tournament_group_tracking_enabled boolean not null default false,
  add column if not exists tournament_group_standings_enabled boolean not null default false,
  add column if not exists tournament_qualification_enabled boolean not null default false,
  add column if not exists tournament_bracket_template_enabled boolean not null default false,
  add column if not exists tournament_knockout_match_generation_enabled boolean not null default false;

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_tournament_flags_check,
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
    and (not tournament_group_match_generation_enabled or (
      tournament_group_scheduling_enabled and tournament_match_generation_enabled
    ))
    and (tournament_match_generation_enabled = tournament_group_match_generation_enabled)
    and (not tournament_group_tracking_enabled or tournament_group_match_generation_enabled)
    and (not tournament_group_standings_enabled or tournament_group_tracking_enabled)
    and (not tournament_qualification_enabled or tournament_group_standings_enabled)
    and (not tournament_bracket_template_enabled or tournament_qualification_enabled)
    and (not tournament_knockout_match_generation_enabled or (
      tournament_bracket_template_enabled and tournament_bracket_progression_enabled
    ))
    and (not tournament_bracket_progression_enabled or tournament_knockout_match_generation_enabled)
  );

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_tournament_phase1_off_check,
  drop constraint if exists pachanga_comp_foundation_tournament_r6b_boundary_check,
  add constraint pachanga_comp_foundation_tournament_r6b_boundary_check check (
    not tournament_public_discovery_enabled
    and not tournament_knockout_match_generation_enabled
    and not tournament_bracket_progression_enabled
    and tournament_match_generation_enabled = tournament_group_match_generation_enabled
  );

create or replace function private.pachanga_tournament_gate_dependencies_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
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
  if not new.tournament_group_scheduling_enabled
     or not new.tournament_match_generation_enabled then
    new.tournament_group_match_generation_enabled := false;
  end if;
  new.tournament_match_generation_enabled := new.tournament_group_match_generation_enabled;
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
  -- R6C and public discovery remain unavailable in R6B.
  new.tournament_public_discovery_enabled := false;
  new.tournament_knockout_match_generation_enabled := false;
  new.tournament_bracket_progression_enabled := false;
  return new;
end;
$$;

revoke all on function private.pachanga_tournament_gate_dependencies_v1()
  from public, anon, authenticated;

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
    'knockoutMatchGenerationEnabled', settings.tournament_knockout_match_generation_enabled,
    'bracketProgressionEnabled', settings.tournament_bracket_progression_enabled,
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

revoke all on function private.pachanga_tournament_flags_v1()
  from public, anon, authenticated;

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
  if settings.tournament_knockout_match_generation_enabled
     or settings.tournament_bracket_progression_enabled then
    raise exception 'TOURNAMENT_R6C_MUST_REMAIN_DISABLED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_assert_flags_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_group_stage_state_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if old.completed_at is not null and row(
    new.completed_by,new.completion_operation_id,new.completed_at
  ) is distinct from row(
    old.completed_by,old.completion_operation_id,old.completed_at
  ) then
    raise exception 'TOURNAMENT_GROUP_STAGE_COMPLETION_IMMUTABLE' using errcode = 'PT409';
  end if;
  if (new.completed_at is null) <> (new.completed_by is null)
     or (new.completed_at is null) <> (new.completion_operation_id is null)
     or (new.completed_at is not null and new.status <> 'complete') then
    raise exception 'TOURNAMENT_GROUP_STAGE_COMPLETION_INVALID' using errcode = '22023';
  end if;
  if row(
    new.id,new.competition_id,new.edition_id,new.category_id,new.stage_id,
    new.draw_plan_id,new.draw_revision_id,new.participant_freeze_id,
    new.rule_revision_id,new.created_by,new.created_at
  ) is distinct from row(
    old.id,old.competition_id,old.edition_id,old.category_id,old.stage_id,
    old.draw_plan_id,old.draw_revision_id,old.participant_freeze_id,
    old.rule_revision_id,old.created_by,old.created_at
  ) then raise exception 'TOURNAMENT_GROUP_STAGE_LINEAGE_IMMUTABLE' using errcode = '22023'; end if;
  if old.current_preparation_id is null
     and new.current_preparation_id is not null
     and new.revision = old.revision
     and row(new.status,new.current_qualification_snapshot_id,new.current_bracket_template_id,
       new.fixture_count,new.official_fixture_count,new.server_sequence,new.updated_by,new.updated_at)
       is not distinct from row(old.status,old.current_qualification_snapshot_id,old.current_bracket_template_id,
       old.fixture_count,old.official_fixture_count,old.server_sequence,old.updated_by,old.updated_at) then
    return new;
  end if;
  if new.revision <> old.revision + 1 or new.server_sequence <= old.server_sequence then
    raise exception 'TOURNAMENT_GROUP_STAGE_REVISION_INVALID' using errcode = 'PT409';
  end if;
  if not (
    new.status = old.status
    or (old.status = 'prepared' and new.status in ('scheduling','cancelled'))
    or (old.status = 'scheduling' and new.status in ('schedule_validated','cancelled'))
    or (old.status = 'schedule_validated' and new.status in ('scheduling','schedule_published','cancelled'))
    or (old.status = 'schedule_published' and new.status in ('active','complete','cancelled'))
    or (old.status = 'active' and new.status in ('complete','cancelled'))
  ) then raise exception 'TOURNAMENT_GROUP_STAGE_TRANSITION_INVALID' using errcode = '22023'; end if;
  if new.fixture_count < old.fixture_count
     or new.official_fixture_count < old.official_fixture_count
     or new.official_fixture_count > new.fixture_count then
    raise exception 'TOURNAMENT_GROUP_STAGE_COUNTER_INVALID' using errcode = '22023';
  end if;
  if new.current_qualification_snapshot_id is not null and not exists (
    select 1 from public.pachanga_tournament_qualification_snapshots snapshots
    where snapshots.id = new.current_qualification_snapshot_id
      and snapshots.group_stage_state_id = new.id
  ) then raise exception 'TOURNAMENT_QUALIFICATION_SCOPE_INVALID' using errcode = '22023'; end if;
  if new.current_bracket_template_id is not null and not exists (
    select 1 from public.pachanga_tournament_bracket_templates templates
    where templates.id = new.current_bracket_template_id
      and templates.group_stage_state_id = new.id
  ) then raise exception 'TOURNAMENT_BRACKET_SCOPE_INVALID' using errcode = '22023'; end if;
  return new;
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_state_guard_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_tournament_group_stage_state_v1
  on public.pachanga_tournament_group_stage_states;
create trigger guard_pachanga_tournament_group_stage_state_v1
before update or delete on public.pachanga_tournament_group_stage_states
for each row execute function private.pachanga_tournament_group_stage_state_guard_v1();

create or replace function private.pachanga_tournament_group_stage_frozen_entry_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare target_competition_id uuid := case
  when tg_op = 'DELETE' then old.competition_id else new.competition_id
end;
begin
  if tg_op = 'UPDATE'
     and new.status is not distinct from old.status
     and new.team_id is not distinct from old.team_id
     and new.category_id is not distinct from old.category_id then
    return new;
  end if;
  if not exists (
    select 1
    from public.pachanga_tournament_group_stage_states states
    where states.competition_id = target_competition_id
      and states.status <> 'cancelled'
  ) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'r6b-command:' || target_competition_id::text, 91922
  ));
  if exists (
    select 1
    from public.pachanga_tournament_group_stage_states states
    where states.competition_id = target_competition_id
      and states.status <> 'cancelled'
  ) then
    raise exception 'TOURNAMENT_PARTICIPANT_FREEZE_LOCKED' using errcode = 'PT409';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_frozen_entry_guard_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_tournament_group_stage_frozen_entry_v1
  on public.pachanga_competition_entries;
create trigger guard_pachanga_tournament_group_stage_frozen_entry_v1
before update of status, team_id, category_id or delete
on public.pachanga_competition_entries
for each row execute function private.pachanga_tournament_group_stage_frozen_entry_guard_v1();

create or replace function private.pachanga_tournament_group_stage_official_result_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare state_row public.pachanga_tournament_group_stage_states%rowtype;
declare qualification_status text;
declare sequence_value bigint;
begin
  if new.supersedes_decision_id is null then
    return new;
  end if;
  select states.* into state_row
  from public.pachanga_tournament_group_stage_states states
  join public.pachanga_competition_match_contexts contexts
    on contexts.competition_id = states.competition_id
   and contexts.stage_id = states.stage_id
  where contexts.id = new.competition_match_context_id
    and states.status <> 'cancelled';
  if not found then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'r6b-command:' || state_row.competition_id::text, 91922
  ));
  select * into state_row
  from public.pachanga_tournament_group_stage_states states
  where states.id = state_row.id
  for update;
  select snapshots.status into qualification_status
  from public.pachanga_tournament_qualification_snapshots snapshots
  where snapshots.id = state_row.current_qualification_snapshot_id;
  if state_row.completed_at is not null or qualification_status = 'PUBLISHED' then
    raise exception 'TOURNAMENT_GROUP_STAGE_RESULTS_FINALIZED' using errcode = 'PT409';
  end if;
  if state_row.current_qualification_snapshot_id is not null
     or state_row.current_bracket_template_id is not null then
    sequence_value := nextval('private.pachanga_competition_sequence');
    update public.pachanga_tournament_group_stage_states states set
      current_qualification_snapshot_id = null,
      current_bracket_template_id = null,
      revision = states.revision + 1,
      server_sequence = sequence_value,
      updated_by = coalesce(new.decided_by, states.updated_by),
      updated_at = clock_timestamp()
    where states.id = state_row.id;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_tournament_group_stage_official_result_guard_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_tournament_group_stage_official_result_v1
  on public.pachanga_competition_official_result_decisions;
create trigger guard_pachanga_tournament_group_stage_official_result_v1
before insert on public.pachanga_competition_official_result_decisions
for each row execute function private.pachanga_tournament_group_stage_official_result_guard_v1();

create index if not exists pachanga_tournament_group_stage_status_idx
  on public.pachanga_tournament_group_stage_states(status, server_sequence desc, id desc);
create index if not exists pachanga_tournament_group_stage_preparation_idx
  on public.pachanga_tournament_group_stage_preparations(
    group_stage_state_id, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_group_schedule_scope_idx
  on public.pachanga_tournament_group_schedule_plans(
    group_stage_state_id, group_order, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_group_validation_scope_idx
  on public.pachanga_tournament_group_schedule_validations(
    group_stage_state_id, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_qualification_scope_idx
  on public.pachanga_tournament_qualification_snapshots(
    group_stage_state_id, status, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_qualification_rows_group_idx
  on public.pachanga_tournament_qualification_rows(
    qualification_snapshot_id, competition_group_id, group_position, entry_id
  );
create index if not exists pachanga_tournament_bracket_scope_idx
  on public.pachanga_tournament_bracket_templates(
    group_stage_state_id, status, server_sequence desc, id desc
  );
create index if not exists pachanga_tournament_context_tracking_idx
  on public.pachanga_competition_match_contexts(
    competition_id, stage_id, competition_group_id, status,
    server_sequence desc, id desc
  ) where source_kind = 'COMPETITION_GENERATED';

create or replace function public.command_pachanga_tournament_group_stage_platform_v1(
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
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c6b1'::uuid;
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
     or normalized_action <> 'tournament.group_stage.flags.set'
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or payload - array[
       'groupStageEnabled','groupSchedulingEnabled','groupMatchGenerationEnabled',
       'groupTrackingEnabled','groupStandingsEnabled','qualificationEnabled',
       'bracketTemplateEnabled','reason'
     ]::text[] <> '{}'::jsonb then
    raise exception 'INVALID_TOURNAMENT_GROUP_STAGE_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_each(payload) item
    where item.key <> 'reason' and jsonb_typeof(item.value) <> 'boolean'
  ) then raise exception 'INVALID_TOURNAMENT_GROUP_STAGE_FLAG' using errcode = '22023'; end if;
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
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91923));
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
  if coalesce((payload ->> 'groupStageEnabled')::boolean, settings.tournament_group_stage_enabled)
     and not settings.tournament_draw_publish_enabled then
    raise exception 'TOURNAMENT_GROUP_STAGE_REQUIRES_PUBLISHED_DRAW' using errcode = '0A000';
  end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings foundation_settings set
    tournament_group_stage_enabled = coalesce(
      (payload ->> 'groupStageEnabled')::boolean,
      foundation_settings.tournament_group_stage_enabled
    ),
    tournament_group_scheduling_enabled = coalesce(
      (payload ->> 'groupSchedulingEnabled')::boolean,
      foundation_settings.tournament_group_scheduling_enabled
    ),
    tournament_group_match_generation_enabled = coalesce(
      (payload ->> 'groupMatchGenerationEnabled')::boolean,
      foundation_settings.tournament_group_match_generation_enabled
    ),
    tournament_match_generation_enabled = coalesce(
      (payload ->> 'groupMatchGenerationEnabled')::boolean,
      foundation_settings.tournament_group_match_generation_enabled
    ),
    tournament_group_tracking_enabled = coalesce(
      (payload ->> 'groupTrackingEnabled')::boolean,
      foundation_settings.tournament_group_tracking_enabled
    ),
    tournament_group_standings_enabled = coalesce(
      (payload ->> 'groupStandingsEnabled')::boolean,
      foundation_settings.tournament_group_standings_enabled
    ),
    tournament_qualification_enabled = coalesce(
      (payload ->> 'qualificationEnabled')::boolean,
      foundation_settings.tournament_qualification_enabled
    ),
    tournament_bracket_template_enabled = coalesce(
      (payload ->> 'bracketTemplateEnabled')::boolean,
      foundation_settings.tournament_bracket_template_enabled
    ),
    tournament_knockout_match_generation_enabled = false,
    tournament_bracket_progression_enabled = false,
    tournament_public_discovery_enabled = false,
    revision = foundation_settings.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = confirmed_at
  where foundation_settings.singleton
  returning foundation_settings.revision into confirmed_revision;
  snapshot := private.pachanga_tournament_flags_v1();
  if (payload ->> 'groupStageEnabled')::boolean is true
     and not (snapshot ->> 'groupStageEnabled')::boolean
     or (payload ->> 'groupSchedulingEnabled')::boolean is true
     and not (snapshot ->> 'groupSchedulingEnabled')::boolean
     or (payload ->> 'groupMatchGenerationEnabled')::boolean is true
     and not (snapshot ->> 'groupMatchGenerationEnabled')::boolean
     or (payload ->> 'groupTrackingEnabled')::boolean is true
     and not (snapshot ->> 'groupTrackingEnabled')::boolean
     or (payload ->> 'groupStandingsEnabled')::boolean is true
     and not (snapshot ->> 'groupStandingsEnabled')::boolean
     or (payload ->> 'qualificationEnabled')::boolean is true
     and not (snapshot ->> 'qualificationEnabled')::boolean
     or (payload ->> 'bracketTemplateEnabled')::boolean is true
     and not (snapshot ->> 'bracketTemplateEnabled')::boolean then
    raise exception 'TOURNAMENT_GROUP_STAGE_FLAG_DEPENDENCY_DISABLED' using errcode = '0A000';
  end if;
  return private.pachanga_competition_store_command_v1(
    operation_id, actor_id, actor_kind, normalized_action,
    'tournament_group_stage_flags', aggregate_id, null, null,
    confirmed_revision, sequence_value, 'tournament_group_stage_flags',
    request_hash,
    private.pachanga_competition_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb)),
    snapshot - array['updatedAt']::text[], snapshot, confirmed_at
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_tournament_group_stage_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_tournament_group_stage_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated, service_role;

comment on function public.command_pachanga_tournament_group_stage_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) is 'Audited R6B activation authority. Knockout generation, bracket progression and public discovery are always forced OFF.';
