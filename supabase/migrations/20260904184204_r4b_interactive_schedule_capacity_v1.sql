-- R4B interactive generation remains synchronous, so the product boundary is
-- deliberately lower than the deterministic engine's technical capacity.

create or replace function private.pachanga_league_schedule_interactive_maximum_teams_v1()
returns integer
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select 20;
$$;

revoke all on function private.pachanga_league_schedule_interactive_maximum_teams_v1()
  from public, anon, authenticated, service_role;

comment on function private.pachanga_league_schedule_interactive_maximum_teams_v1() is
  'Canonical R4B product limit for synchronous generate/regenerate commands. The round-robin engine itself remains capable of 32 entries.';

create or replace function private.pachanga_league_schedule_interactive_preflight_v1(
  target_schedule_plan_id uuid,
  target_seed text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare inputs jsonb;
declare eligible_teams integer;
declare maximum_teams integer := private.pachanga_league_schedule_interactive_maximum_teams_v1();
begin
  inputs := private.pachanga_league_schedule_inputs_v1(
    target_schedule_plan_id,
    target_seed
  );
  eligible_teams := (inputs ->> 'entryCount')::integer;

  return jsonb_build_object(
    'allowed', eligible_teams <= maximum_teams,
    'eligibleTeams', eligible_teams,
    'maximumTeams', maximum_teams,
    'reasonCode', case when eligible_teams > maximum_teams
      then 'INTERACTIVE_TEAM_LIMIT_EXCEEDED' else null end,
    'inputs', inputs
  );
end;
$$;

revoke all on function private.pachanga_league_schedule_interactive_preflight_v1(uuid, text)
  from public, anon, authenticated, service_role;

comment on function private.pachanga_league_schedule_interactive_preflight_v1(uuid, text) is
  'Reuses the exact canonical R4B input snapshot to decide whether synchronous schedule generation is allowed.';

-- Keep the 2-32 deterministic engine available only as an internal primitive.
-- Every production scheduling path continues to call the original function
-- name, which is recreated below as the interactive authority boundary.
alter function private.pachanga_league_schedule_generate_revision_v1(
  uuid, text, text, uuid, bigint
) rename to pachanga_league_schedule_generate_revision_engine_v1;

revoke all on function private.pachanga_league_schedule_generate_revision_engine_v1(
  uuid, text, text, uuid, bigint
) from public, anon, authenticated, service_role;

comment on function private.pachanga_league_schedule_generate_revision_engine_v1(
  uuid, text, text, uuid, bigint
) is
  'Internal deterministic 2-32 team engine. Not an interactive API and not executable by client roles.';

create or replace function private.pachanga_league_schedule_generate_revision_v1(
  target_schedule_plan_id uuid,
  target_seed text,
  target_revision_kind text,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare preflight jsonb;
begin
  perform 1
  from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id
  for update;
  if not found then
    raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;

  preflight := private.pachanga_league_schedule_interactive_preflight_v1(
    target_schedule_plan_id,
    target_seed
  );
  if not (preflight ->> 'allowed')::boolean then
    raise exception using
      errcode = '54000',
      message = 'SCHEDULE_INTERACTIVE_CAPACITY_EXCEEDED',
      detail = jsonb_build_object(
        'eligibleTeams', (preflight ->> 'eligibleTeams')::integer,
        'maximumTeams', (preflight ->> 'maximumTeams')::integer
      )::text,
      hint = 'INTERACTIVE_TEAM_LIMIT_EXCEEDED';
  end if;

  -- Conflict reconstruction runs inside the engine before the outer command
  -- writes its final snapshot. Keep this derived counter aligned with the
  -- canonical inputs for that same transaction.
  update public.pachanga_competition_schedule_plans plans
  set entry_count = (preflight ->> 'eligibleTeams')::smallint
  where plans.id = target_schedule_plan_id
    and plans.entry_count is distinct from (preflight ->> 'eligibleTeams')::smallint;

  return private.pachanga_league_schedule_generate_revision_engine_v1(
    target_schedule_plan_id,
    target_seed,
    target_revision_kind,
    target_actor_id,
    target_server_sequence
  );
end;
$$;

revoke all on function private.pachanga_league_schedule_generate_revision_v1(
  uuid, text, text, uuid, bigint
) from public, anon, authenticated, service_role;

comment on function private.pachanga_league_schedule_generate_revision_v1(
  uuid, text, text, uuid, bigint
) is
  'Interactive R4B generator boundary. It rejects canonical scopes above 20 teams before invoking the 2-32 engine.';

-- Preserve the complete, previously certified command implementation behind a
-- private boundary. The public wrapper performs the new preflight before the
-- old implementation consumes a sequence or writes any scheduling evidence.
alter function public.command_pachanga_league_scheduling_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) rename to pachanga_league_scheduling_command_impl_v1;

alter function public.pachanga_league_scheduling_command_impl_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) set schema private;

revoke all on function private.pachanga_league_scheduling_command_impl_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;

comment on function private.pachanga_league_scheduling_command_impl_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is
  'Private certified R4B command implementation. Client roles must use the public preflight wrapper.';

create or replace function public.command_pachanga_league_scheduling_v1(
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
declare actor_id uuid := (select auth.uid());
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare preflight jsonb;
declare seed_value text;
begin
  if normalized_action not in ('schedule.generate', 'schedule.regenerate') then
    return private.pachanga_league_scheduling_command_impl_v1(
      operation_id,
      aggregate_id,
      expected_revision,
      command_action,
      command_payload,
      client_metadata
    );
  end if;

  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 then
    raise exception 'INVALID_LEAGUE_SCHEDULING_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(payload) > 40000 then
    raise exception 'INVALID_LEAGUE_SCHEDULING_PAYLOAD' using errcode = '22023';
  end if;

  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action,
    aggregate_id,
    expected_revision,
    payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91405));
  replay := private.pachanga_competition_replay_v1(
    operation_id,
    actor_id,
    'authenticated',
    normalized_action,
    aggregate_id,
    request_hash
  );
  if replay is not null then
    return replay;
  end if;

  -- Authority is checked before taking the plan lock so an unauthorized actor
  -- cannot use the capacity preflight as a scope oracle.
  select * into plan_row
  from public.pachanga_competition_schedule_plans plans
  where plans.id = aggregate_id;
  if not found then
    raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform private.pachanga_league_schedule_assert_authority_v1(
    plan_row.competition_id,
    actor_id,
    'schedule_manage'
  );

  select * into plan_row
  from public.pachanga_competition_schedule_plans plans
  where plans.id = aggregate_id
  for update;
  if not found then
    raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;
  if plan_row.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'POST_PUBLICATION_CHANGE_REQUIRES_R4C' using errcode = '0A000';
  end if;
  if normalized_action = 'schedule.regenerate'
     and plan_row.current_revision_id is null then
    raise exception 'SCHEDULE_REVISION_NOT_FOUND' using errcode = 'P0002';
  end if;

  perform private.pachanga_league_schedule_assert_flags_v1(true, false, false, false);
  seed_value := left(
    coalesce(nullif(trim(payload ->> 'seed'), ''), operation_id::text),
    160
  );
  preflight := private.pachanga_league_schedule_interactive_preflight_v1(
    plan_row.id,
    seed_value
  );
  if not (preflight ->> 'allowed')::boolean then
    raise exception using
      errcode = '54000',
      message = 'SCHEDULE_INTERACTIVE_CAPACITY_EXCEEDED',
      detail = jsonb_build_object(
        'eligibleTeams', (preflight ->> 'eligibleTeams')::integer,
        'maximumTeams', (preflight ->> 'maximumTeams')::integer
      )::text,
      hint = 'INTERACTIVE_TEAM_LIMIT_EXCEEDED';
  end if;

  update public.pachanga_competition_schedule_plans plans
  set entry_count = (preflight ->> 'eligibleTeams')::smallint
  where plans.id = plan_row.id
    and plans.entry_count is distinct from (preflight ->> 'eligibleTeams')::smallint;

  return private.pachanga_league_scheduling_command_impl_v1(
    operation_id,
    aggregate_id,
    expected_revision,
    command_action,
    command_payload,
    client_metadata
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_scheduling_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_scheduling_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

comment on function public.command_pachanga_league_scheduling_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is
  'R4B server-authoritative schedule intent endpoint. Interactive generation is limited to 20 canonical eligible teams; client payloads cannot override it.';

-- The historical "platform command" is a flags-only endpoint, not a second
-- generation API. Tighten its payload allowlist so a platform actor cannot
-- smuggle a scheduling action into an ignored key and mistake it for success.
alter function public.command_pachanga_league_scheduling_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) rename to pachanga_league_scheduling_platform_flags_impl_v1;

alter function public.pachanga_league_scheduling_platform_flags_impl_v1(
  uuid, uuid, bigint, jsonb, jsonb
) set schema private;

revoke all on function private.pachanga_league_scheduling_platform_flags_impl_v1(
  uuid, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.command_pachanga_league_scheduling_platform_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
begin
  if actor_id is null then
    raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
  end if;
  if jsonb_typeof(payload) <> 'object'
     or exists (
       select 1
       from jsonb_object_keys(payload) keys(key)
       where keys.key not in (
         'foundationEnabled',
         'generationEnabled',
         'editingEnabled',
         'publicationEnabled',
         'publicCalendarEnabled',
         'canonicalFixtureCreationEnabled',
         'reason'
       )
     ) then
    raise exception 'INVALID_LEAGUE_SCHEDULING_FLAGS_PAYLOAD' using errcode = '22023';
  end if;

  return private.pachanga_league_scheduling_platform_flags_impl_v1(
    operation_id,
    aggregate_id,
    expected_revision,
    command_payload,
    client_metadata
  );
end;
$$;

revoke all on function public.command_pachanga_league_scheduling_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_scheduling_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) to authenticated;

comment on function public.command_pachanga_league_scheduling_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) is
  'Platform-only R4B feature-flag command. It does not accept or execute schedule generation actions.';

-- Keep the certified workbench implementation private, then enrich its read
-- model with the canonical product limit and a server-computed eligibility
-- decision. Historical schedules never re-evaluate live roster eligibility.
alter function public.get_pachanga_league_schedule_workbench_v1(
  uuid, integer, integer
) rename to pachanga_league_schedule_workbench_impl_v1;

alter function public.pachanga_league_schedule_workbench_impl_v1(
  uuid, integer, integer
) set schema private;

revoke all on function private.pachanga_league_schedule_workbench_impl_v1(
  uuid, integer, integer
) from public, anon, authenticated, service_role;

comment on function private.pachanga_league_schedule_workbench_impl_v1(
  uuid, integer, integer
) is
  'Private certified R4B workbench implementation. The public wrapper adds canonical interactive-capacity metadata.';

create or replace function public.get_pachanga_league_schedule_workbench_v1(
  target_schedule_plan_id uuid,
  page_offset integer default 0,
  page_size integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare result jsonb;
declare plan_row public.pachanga_competition_schedule_plans%rowtype;
declare revision_row public.pachanga_competition_schedule_revisions%rowtype;
declare preflight jsonb;
declare next_actions jsonb;
declare seed_value text;
declare source_kind text;
declare eligible_teams integer;
declare maximum_teams integer := private.pachanga_league_schedule_interactive_maximum_teams_v1();
declare generation_allowed boolean;
begin
  result := private.pachanga_league_schedule_workbench_impl_v1(
    target_schedule_plan_id,
    page_offset,
    page_size
  );

  select * into plan_row
  from public.pachanga_competition_schedule_plans plans
  where plans.id = target_schedule_plan_id;
  if not found then
    raise exception 'SCHEDULE_PLAN_NOT_FOUND' using errcode = 'P0002';
  end if;

  if plan_row.current_revision_id is not null then
    select * into revision_row
    from public.pachanga_competition_schedule_revisions revisions
    where revisions.id = plan_row.current_revision_id;
  end if;

  if plan_row.status in ('published', 'cancelled', 'superseded') then
    eligible_teams := case
      when revision_row.id is not null then jsonb_array_length(revision_row.entry_order)
      else plan_row.entry_count
    end;
    source_kind := 'FROZEN_REVISION';
  else
    seed_value := coalesce(revision_row.seed, 'plan:' || plan_row.id::text);
    preflight := private.pachanga_league_schedule_interactive_preflight_v1(
      plan_row.id,
      seed_value
    );
    eligible_teams := (preflight ->> 'eligibleTeams')::integer;
    source_kind := 'CANONICAL_CURRENT_INPUTS';
  end if;

  generation_allowed := eligible_teams <= maximum_teams;
  next_actions := coalesce(result -> 'nextValidActions', '[]'::jsonb);
  if not generation_allowed then
    select coalesce(jsonb_agg(actions.value order by actions.ordinality), '[]'::jsonb)
    into next_actions
    from jsonb_array_elements(next_actions) with ordinality actions(value, ordinality)
    where actions.value #>> '{}' not in ('schedule.generate', 'schedule.regenerate');
  end if;

  result := jsonb_set(
    result,
    '{engine}',
    coalesce(result -> 'engine', '{}'::jsonb)
      || jsonb_build_object('maximumTeams', 32),
    true
  );
  result := jsonb_set(result, '{nextValidActions}', next_actions, true);

  return result || jsonb_build_object(
    'interactiveGeneration', jsonb_build_object(
      'allowed', generation_allowed,
      'eligibleTeams', eligible_teams,
      'maximumTeams', maximum_teams,
      'reasonCode', case when generation_allowed then null
        else 'INTERACTIVE_TEAM_LIMIT_EXCEEDED' end,
      'source', source_kind
    )
  );
end;
$$;

revoke all on function public.get_pachanga_league_schedule_workbench_v1(
  uuid, integer, integer
) from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_league_schedule_workbench_v1(
  uuid, integer, integer
) to authenticated;

comment on function public.get_pachanga_league_schedule_workbench_v1(
  uuid, integer, integer
) is
  'Private organizer workbench with canonical current-input capacity metadata. Historical revisions stay readable without live roster recalculation.';
