create schema if not exists simulation;
revoke all on schema simulation from public, anon, authenticated;
grant usage on schema simulation to service_role;

create table if not exists simulation.simulation_worlds (
  id uuid primary key,
  name text not null,
  seed bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  virtual_start_date timestamptz not null,
  virtual_current_date timestamptz not null,
  season_id text not null,
  status text not null check (status in ('active', 'paused', 'completed')),
  mode text not null check (mode in ('persistent', 'ephemeral')),
  source_commit text not null,
  integrity_strategy text not null default 'exclusion_and_hold',
  revision bigint not null default 0,
  config jsonb not null,
  state jsonb not null,
  updated_at timestamptz not null default clock_timestamp(),
  unique (seed, season_id, mode)
);

create table if not exists simulation.simulation_agents (
  id text not null,
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  product_user_id uuid references auth.users(id) on delete set null,
  display_name text not null,
  synthetic_email text,
  persona text not null,
  attack_profile text not null,
  province_code text not null,
  city text not null,
  status text not null,
  available_from timestamptz not null,
  unavailable_until timestamptz,
  unavailable_reason text,
  profile jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (world_id, id),
  unique (world_id, product_user_id)
);

create table if not exists simulation.simulation_entities (
  id uuid primary key default gen_random_uuid(),
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  entity_kind text not null,
  synthetic_id text not null,
  product_uuid uuid,
  product_text_id text,
  state text not null default 'active',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique (world_id, entity_kind, synthetic_id)
);

create table if not exists simulation.simulation_events (
  id bigint generated always as identity primary key,
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  server_sequence bigint not null,
  virtual_date timestamptz not null,
  event_type text not null,
  flow text not null,
  actor_agent_id text,
  operation_id uuid not null,
  status text not null check (status in ('pending', 'pass', 'failed')),
  expected jsonb not null default '{}'::jsonb,
  payload jsonb not null default '{}'::jsonb,
  related_entity_ids text[] not null default '{}',
  created_at timestamptz not null default clock_timestamp(),
  unique (world_id, server_sequence),
  unique (world_id, operation_id)
);

create table if not exists simulation.simulation_incidents (
  incident_id uuid primary key,
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  virtual_date timestamptz not null,
  severity text not null check (severity in ('critical', 'high', 'medium', 'low', 'info')),
  category text not null,
  actor text,
  team text,
  match text,
  challenge text,
  operation text not null,
  expected jsonb not null,
  actual jsonb not null,
  before_state jsonb not null,
  after_state jsonb not null,
  related_entity_ids text[] not null default '{}',
  seed bigint not null,
  reproduction_steps jsonb not null,
  first_seen timestamptz not null default clock_timestamp(),
  last_seen timestamptz not null default clock_timestamp(),
  occurrence_count integer not null default 1,
  status text not null check (status in ('open', 'confirmed_bug', 'needs_product_decision', 'false_positive', 'fixed', 'regression_verified'))
);

create table if not exists simulation.simulation_snapshots (
  id bigint generated always as identity primary key,
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  snapshot_kind text not null,
  virtual_date timestamptz not null,
  entity_kind text not null default 'world',
  entity_id text not null default 'world',
  world_revision bigint not null,
  server_sequence bigint not null,
  payload jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (world_id, snapshot_kind, virtual_date, entity_kind, entity_id)
);

update simulation.simulation_snapshots
set entity_kind = coalesce(entity_kind, 'world'),
    entity_id = coalesce(entity_id, 'world')
where entity_kind is null or entity_id is null;
alter table simulation.simulation_snapshots alter column entity_kind set default 'world';
alter table simulation.simulation_snapshots alter column entity_kind set not null;
alter table simulation.simulation_snapshots alter column entity_id set default 'world';
alter table simulation.simulation_snapshots alter column entity_id set not null;

create table if not exists simulation.simulation_coverage (
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  flow text not null,
  scenario text not null,
  times_executed integer not null default 0,
  passes integer not null default 0,
  failures integer not null default 0,
  status text not null check (status in ('PASS', 'FAIL', 'NO_COVERAGE')),
  last_execution timestamptz,
  evidence jsonb not null default '{}'::jsonb,
  primary key (world_id, flow, scenario)
);

create table if not exists simulation.simulation_ranking_history (
  id bigint generated always as identity primary key,
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  virtual_date timestamptz not null,
  scope text not null check (scope in ('province', 'autonomous_community', 'national')),
  territory_code text not null,
  agent_id text not null,
  rank integer not null,
  score numeric not null,
  movement integer not null default 0,
  certification text not null,
  explanation jsonb not null,
  unique (world_id, virtual_date, scope, territory_code, agent_id)
);

create table if not exists simulation.simulation_operation_receipts (
  world_id uuid not null references simulation.simulation_worlds(id) on delete cascade,
  operation_id uuid not null,
  operation text not null,
  expected_revision bigint not null,
  confirmed_revision bigint not null,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (world_id, operation_id)
);

create or replace view simulation.simulation_world_summaries
with (security_invoker = true)
as
select
  worlds.id,
  worlds.name,
  worlds.seed,
  worlds.created_at,
  worlds.updated_at,
  worlds.virtual_current_date,
  worlds.season_id,
  worlds.status,
  worlds.mode,
  worlds.revision,
  (select count(*) from simulation.simulation_events events where events.world_id = worlds.id) as event_count,
  (select count(*) from simulation.simulation_incidents incidents where incidents.world_id = worlds.id) as incident_count,
  (select count(*) from simulation.simulation_entities entities where entities.world_id = worlds.id and entities.entity_kind = 'match') as match_count
from simulation.simulation_worlds worlds;

create index if not exists simulation_events_world_date_idx
  on simulation.simulation_events(world_id, virtual_date desc, server_sequence desc);
create index if not exists simulation_incidents_world_status_idx
  on simulation.simulation_incidents(world_id, status, severity, virtual_date desc);
create index if not exists simulation_snapshots_world_date_idx
  on simulation.simulation_snapshots(world_id, virtual_date desc, server_sequence desc);
create index if not exists simulation_ranking_history_lookup_idx
  on simulation.simulation_ranking_history(world_id, scope, territory_code, virtual_date desc, rank);

alter table simulation.simulation_worlds enable row level security;
alter table simulation.simulation_agents enable row level security;
alter table simulation.simulation_entities enable row level security;
alter table simulation.simulation_events enable row level security;
alter table simulation.simulation_incidents enable row level security;
alter table simulation.simulation_snapshots enable row level security;
alter table simulation.simulation_coverage enable row level security;
alter table simulation.simulation_ranking_history enable row level security;
alter table simulation.simulation_operation_receipts enable row level security;

revoke all on all tables in schema simulation from public, anon, authenticated;
revoke all on all sequences in schema simulation from public, anon, authenticated;
grant all on all tables in schema simulation to service_role;
grant usage, select on all sequences in schema simulation to service_role;
revoke all on simulation.simulation_world_summaries from public, anon, authenticated;
grant select on simulation.simulation_world_summaries to service_role;

comment on schema simulation is 'Local-only Pachangas IQ Synthetic World. Never deploy to production.';

create or replace function simulation.save_world(
  p_world jsonb,
  p_operation_id uuid,
  p_expected_revision bigint,
  p_snapshot_kind text default null,
  p_snapshot_payload jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = simulation, pg_temp
set statement_timeout = '120s'
as $$
declare
  v_world_id uuid := (p_world->>'id')::uuid;
  v_current_revision bigint;
  v_explicit_request_role text := coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), '');
  v_jwt_role text := coalesce(auth.jwt()->>'role', '');
  v_set_role text := coalesce(nullif(current_setting('role', true), 'none'), '');
  v_effective_role text;
  v_response jsonb;
  v_item jsonb;
begin
  v_effective_role := coalesce(
    nullif(v_explicit_request_role, ''),
    nullif(v_jwt_role, ''),
    nullif(v_set_role, ''),
    session_user
  );

  if v_effective_role not in ('postgres', 'service_role') then
    raise exception 'SYNTHETIC_SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;

  select response into v_response
  from simulation.simulation_operation_receipts
  where world_id = v_world_id and operation_id = p_operation_id;
  if found then
    return v_response || jsonb_build_object('idempotentReplay', true);
  end if;

  select revision into v_current_revision
  from simulation.simulation_worlds
  where id = v_world_id
  for update;

  if not found then
    if p_expected_revision <> -1 then
      raise exception 'SYNTHETIC_WORLD_NOT_FOUND' using errcode = 'P0002';
    end if;
    insert into simulation.simulation_worlds (
      id, name, seed, virtual_start_date, virtual_current_date, season_id, status,
      mode, source_commit, revision, config, state
    ) values (
      v_world_id, p_world->>'name', (p_world->>'seed')::bigint,
      (p_world->>'startDate')::timestamptz, (p_world->>'currentDate')::timestamptz,
      p_world->>'seasonId', p_world->>'status', p_world->>'mode', p_world->>'sourceCommit',
      (p_world->>'revision')::bigint, p_world->'config', p_world->'state'
    );
  else
    if v_current_revision <> p_expected_revision then
      raise exception 'STALE_WORLD_REVISION expected %, actual %', p_expected_revision, v_current_revision using errcode = '40001';
    end if;
    update simulation.simulation_worlds set
      name = p_world->>'name',
      virtual_current_date = (p_world->>'currentDate')::timestamptz,
      status = p_world->>'status',
      revision = (p_world->>'revision')::bigint,
      config = p_world->'config',
      state = p_world->'state',
      updated_at = clock_timestamp()
    where id = v_world_id;
  end if;

  for v_item in select value from jsonb_array_elements(p_world#>'{state,agents}') loop
    insert into simulation.simulation_agents (
      id, world_id, product_user_id, display_name, persona, attack_profile, province_code,
      city, status, available_from, unavailable_until, unavailable_reason, profile
    ) values (
      v_item->>'id', v_world_id, nullif(v_item->>'productUserId', '')::uuid,
      v_item->>'displayName', v_item->>'persona', v_item->>'attackProfile', v_item->>'provinceCode',
      v_item->>'city', v_item->>'status', (v_item->>'availableFrom')::timestamptz,
      nullif(v_item->>'unavailableUntil', '')::timestamptz, nullif(v_item->>'unavailableReason', ''), v_item
    ) on conflict (world_id, id) do update set
      product_user_id = excluded.product_user_id,
      status = excluded.status,
      unavailable_until = excluded.unavailable_until,
      unavailable_reason = excluded.unavailable_reason,
      profile = excluded.profile
    where simulation.simulation_agents.product_user_id is distinct from excluded.product_user_id
       or simulation.simulation_agents.status is distinct from excluded.status
       or simulation.simulation_agents.unavailable_until is distinct from excluded.unavailable_until
       or simulation.simulation_agents.unavailable_reason is distinct from excluded.unavailable_reason
       or simulation.simulation_agents.profile is distinct from excluded.profile;
  end loop;

  insert into simulation.simulation_entities (world_id, entity_kind, synthetic_id, metadata)
  select v_world_id, source.kind, source.item->>'id', source.item
  from (
    select distinct on (raw.kind, raw.item->>'id') raw.kind, raw.item
    from (
      select 'team'::text kind, value item, ordinality from jsonb_array_elements(p_world#>'{state,teams}') with ordinality
      union all select 'challenge', value, ordinality from jsonb_array_elements(p_world#>'{state,challenges}') with ordinality
      union all select 'match', value, ordinality from jsonb_array_elements(p_world#>'{state,matches}') with ordinality
      union all select 'achievement', value, ordinality from jsonb_array_elements(p_world#>'{state,achievements}') with ordinality
      union all select 'reward_box', value, ordinality from jsonb_array_elements(p_world#>'{state,boxes}') with ordinality
      union all select 'rating_opinion', value, ordinality from jsonb_array_elements(p_world#>'{state,ratingOpinions}') with ordinality
      union all select 'attendance_record', value, ordinality from jsonb_array_elements(p_world#>'{state,attendanceRecords}') with ordinality
      union all select 'conduct_scenario', value, ordinality from jsonb_array_elements(p_world#>'{state,conductScenarios}') with ordinality
    ) raw
    order by raw.kind, raw.item->>'id', raw.ordinality desc
  ) source
  on conflict (world_id, entity_kind, synthetic_id) do update set
    metadata = excluded.metadata,
    updated_at = clock_timestamp()
  where simulation.simulation_entities.metadata is distinct from excluded.metadata;

  insert into simulation.simulation_events (
    world_id, server_sequence, virtual_date, event_type, flow, actor_agent_id,
    operation_id, status, expected, payload, related_entity_ids
  )
  select
    v_world_id, (source.value->>'sequence')::bigint, (source.value->>'virtualDate')::timestamptz,
    source.value->>'eventType', source.value->>'flow', nullif(source.value->>'actorAgentId', ''),
    (source.value->>'operationId')::uuid, source.value->>'status', source.value->'expected', source.value->'payload',
    array(select jsonb_array_elements_text(source.value->'entityIds'))
  from jsonb_array_elements(p_world#>'{state,events}') source(value)
  where (source.value->>'sequence')::bigint > coalesce((
    select max(events.server_sequence)
    from simulation.simulation_events events
    where events.world_id = v_world_id
  ), 0)
  on conflict (world_id, operation_id) do nothing;

  for v_item in select value from jsonb_array_elements(p_world#>'{state,incidents}') loop
    insert into simulation.simulation_incidents (
      incident_id, world_id, virtual_date, severity, category, actor, operation, expected,
      actual, before_state, after_state, related_entity_ids, seed, reproduction_steps,
      occurrence_count, status
    ) values (
      (v_item->>'id')::uuid, v_world_id, (v_item->>'virtualDate')::timestamptz,
      v_item->>'severity', v_item->>'category', nullif(v_item->>'actorAgentId', ''),
      v_item->>'operation', v_item->'expected', v_item->'actual', v_item->'beforeState',
      v_item->'afterState', array(select jsonb_array_elements_text(v_item->'relatedEntityIds')),
      (p_world->>'seed')::bigint, v_item->'reproductionSteps', (v_item->>'occurrenceCount')::integer,
      v_item->>'status'
    ) on conflict (incident_id) do update set
      actual = excluded.actual,
      after_state = excluded.after_state,
      occurrence_count = excluded.occurrence_count,
      last_seen = clock_timestamp(),
      status = excluded.status;
  end loop;

  for v_item in select value from jsonb_array_elements(p_world#>'{state,coverage}') loop
    insert into simulation.simulation_coverage (
      world_id, flow, scenario, times_executed, passes, failures, status, last_execution
    ) values (
      v_world_id, v_item->>'flow', v_item->>'scenario', (v_item->>'timesExecuted')::integer,
      (v_item->>'passes')::integer, (v_item->>'failures')::integer, v_item->>'status',
      nullif(v_item->>'lastExecution', '')::timestamptz
    ) on conflict (world_id, flow, scenario) do update set
      times_executed = excluded.times_executed,
      passes = excluded.passes,
      failures = excluded.failures,
      status = excluded.status,
      last_execution = excluded.last_execution;
  end loop;

  for v_item in select value from jsonb_array_elements(p_world#>'{state,rankings}') loop
    insert into simulation.simulation_ranking_history (
      world_id, virtual_date, scope, territory_code, agent_id, rank, score,
      movement, certification, explanation
    ) values (
      v_world_id, (p_world->>'currentDate')::timestamptz, 'province', v_item->>'provinceCode',
      v_item->>'agentId', (v_item->>'rank')::integer, (v_item->>'score')::numeric,
      (v_item->>'movement')::integer, v_item->>'certification',
      jsonb_build_object(
        'quality', v_item->'quality', 'competition', v_item->'competition',
        'opposition', v_item->'opposition', 'logicalOpponents', v_item->'logicalOpponents',
        'validChallenges', v_item->'validChallenges', 'integrityRisk', v_item->'integrityRisk',
        'certificationReasons', v_item->'certificationReasons'
      )
    ) on conflict (world_id, virtual_date, scope, territory_code, agent_id) do update set
      rank = excluded.rank,
      score = excluded.score,
      movement = excluded.movement,
      certification = excluded.certification,
      explanation = excluded.explanation;
  end loop;

  if p_snapshot_kind is not null then
    insert into simulation.simulation_snapshots (
      world_id, snapshot_kind, virtual_date, world_revision, server_sequence, payload
    ) values (
      v_world_id, p_snapshot_kind, (p_world->>'currentDate')::timestamptz,
      (p_world->>'revision')::bigint, (p_world#>>'{state,eventSequence}')::bigint,
      coalesce(p_snapshot_payload, p_world)
    ) on conflict (world_id, snapshot_kind, virtual_date, entity_kind, entity_id) do update set
      world_revision = excluded.world_revision,
      server_sequence = excluded.server_sequence,
      payload = excluded.payload;
  end if;

  v_response := jsonb_build_object(
    'worldId', v_world_id,
    'confirmedRevision', (p_world->>'revision')::bigint,
    'serverSequence', (p_world#>>'{state,eventSequence}')::bigint,
    'idempotentReplay', false
  );
  insert into simulation.simulation_operation_receipts (
    world_id, operation_id, operation, expected_revision, confirmed_revision, response
  ) values (
    v_world_id, p_operation_id, 'save_world', p_expected_revision,
    (p_world->>'revision')::bigint, v_response
  );
  return v_response;
end;
$$;

revoke all on function simulation.save_world(jsonb, uuid, bigint, text, jsonb) from public, anon, authenticated;
grant execute on function simulation.save_world(jsonb, uuid, bigint, text, jsonb) to service_role;
