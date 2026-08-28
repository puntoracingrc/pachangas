-- Pachangas IQ R6C: knockout result resolution, append-only advancement,
-- dependency invalidation and Tournament completion. R4C remains the sporting
-- and official-result authority.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter table public.pachanga_competition_sporting_result_revisions
  drop constraint if exists pachanga_competition_sporting_result_revisions_shootout_check,
  drop constraint if exists pachanga_competition_sporting_result_revisions_check,
  add constraint pachanga_competition_sporting_result_revisions_shootout_check
    check (shootout_home is null and shootout_away is null);

comment on column public.pachanga_competition_sporting_result_revisions.shootout_home is
  'Reserved legacy column. R6C shootouts live in the knockout resolution linked to the official decision.';

create table public.pachanga_tournament_knockout_result_resolutions (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  bracket_node_id uuid not null references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_match_context_id uuid not null references public.pachanga_competition_match_contexts(id) on delete restrict,
  official_result_decision_id uuid not null unique references public.pachanga_competition_official_result_decisions(id) on delete restrict,
  supersedes_resolution_id uuid references public.pachanga_tournament_knockout_result_resolutions(id) on delete restrict,
  score_after_regulation_home integer,
  score_after_regulation_away integer,
  extra_time_played boolean not null default false,
  score_after_extra_time_home integer,
  score_after_extra_time_away integer,
  shootout_home integer,
  shootout_away integer,
  winner_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  loser_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  resolution_kind text not null,
  policy_snapshot jsonb not null,
  checksum text not null,
  operation_id uuid not null unique,
  resolved_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  resolved_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (score_after_regulation_home is null or score_after_regulation_home >= 0),
  check (score_after_regulation_away is null or score_after_regulation_away >= 0),
  check ((score_after_regulation_home is null) = (score_after_regulation_away is null)),
  check (score_after_extra_time_home is null or score_after_extra_time_home >= 0),
  check (score_after_extra_time_away is null or score_after_extra_time_away >= 0),
  check ((score_after_extra_time_home is null) = (score_after_extra_time_away is null)),
  check (shootout_home is null or shootout_home >= 0),
  check (shootout_away is null or shootout_away >= 0),
  check ((shootout_home is null) = (shootout_away is null)),
  check (not extra_time_played or score_after_extra_time_home is not null),
  check (resolution_kind in (
    'SPORTING_RESULT', 'EXTRA_TIME', 'PENALTY_SHOOTOUT', 'FORFEIT',
    'NO_SHOW', 'ADMINISTRATIVE_DECISION', 'ANNULLED'
  )),
  check ((resolution_kind = 'ANNULLED') = (winner_entry_id is null)),
  check (winner_entry_id is null or (loser_entry_id is not null and winner_entry_id <> loser_entry_id)),
  check (jsonb_typeof(policy_snapshot) = 'object'),
  check (length(checksum) = 64)
);

create table public.pachanga_tournament_bracket_advance_decisions (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  bracket_revision_id uuid not null references public.pachanga_tournament_bracket_revisions(id) on delete restrict,
  source_node_id uuid not null references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  official_result_decision_id uuid references public.pachanga_competition_official_result_decisions(id) on delete restrict,
  knockout_resolution_id uuid references public.pachanga_tournament_knockout_result_resolutions(id) on delete restrict,
  supersedes_decision_id uuid references public.pachanga_tournament_bracket_advance_decisions(id) on delete restrict,
  advance_reason text not null,
  winner_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  loser_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  destination_slots jsonb not null default '[]'::jsonb,
  revision bigint not null,
  operation_id uuid not null unique,
  decided_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  decided_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (advance_reason in (
    'SPORTING_RESULT', 'EXTRA_TIME', 'PENALTY_SHOOTOUT', 'BYE',
    'FORFEIT', 'NO_SHOW', 'ADMINISTRATIVE_DECISION'
  )),
  check (winner_entry_id is distinct from loser_entry_id),
  check (jsonb_typeof(destination_slots) = 'array'),
  check (revision >= 1),
  unique (source_node_id, revision),
  unique (official_result_decision_id)
);

create table public.pachanga_tournament_bracket_invalidations (
  id uuid primary key,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  source_node_id uuid not null references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  superseded_advance_decision_id uuid references public.pachanga_tournament_bracket_advance_decisions(id) on delete restrict,
  replacement_official_decision_id uuid references public.pachanga_competition_official_result_decisions(id) on delete restrict,
  invalidation_reason text not null,
  affected_node_ids uuid[] not null default '{}'::uuid[],
  affected_canonical_match_ids uuid[] not null default '{}'::uuid[],
  impact_snapshot jsonb not null,
  operation_id uuid not null unique,
  created_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (length(trim(invalidation_reason)) between 3 and 1200),
  check (jsonb_typeof(impact_snapshot) = 'object')
);

create table public.pachanga_tournament_bracket_dependency_impacts (
  id uuid primary key default gen_random_uuid(),
  bracket_invalidation_id uuid not null references public.pachanga_tournament_bracket_invalidations(id) on delete restrict,
  bracket_node_id uuid not null references public.pachanga_tournament_bracket_nodes(id) on delete restrict,
  canonical_match_id uuid references public.pachanga_canonical_matches(id) on delete restrict,
  impact_kind text not null,
  participant_changed boolean not null default false,
  referee_impact boolean not null default false,
  schedule_impact boolean not null default false,
  discipline_impact boolean not null default false,
  result_impact boolean not null default false,
  completion_impact boolean not null default false,
  detail jsonb not null default '{}'::jsonb,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (impact_kind in (
    'SLOT_RESEED', 'MATCH_REPLACEMENT', 'MATCH_REVIEW',
    'DESCENDANT_INVALIDATION', 'COMPLETION_INVALIDATION'
  )),
  check (jsonb_typeof(detail) = 'object'),
  unique (bracket_invalidation_id, bracket_node_id)
);

create table public.pachanga_tournament_completion_snapshots (
  id uuid primary key,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  bracket_id uuid not null references public.pachanga_tournament_brackets(id) on delete restrict,
  bracket_revision_id uuid not null references public.pachanga_tournament_bracket_revisions(id) on delete restrict,
  champion_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  runner_up_entry_id uuid not null references public.pachanga_competition_entries(id) on delete restrict,
  third_place_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  fourth_place_entry_id uuid references public.pachanga_competition_entries(id) on delete restrict,
  final_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  completion_checksum text not null,
  snapshot jsonb not null,
  revision bigint not null,
  operation_id uuid not null unique,
  completed_by uuid references auth.users(id) on delete set null,
  server_sequence bigint not null unique default nextval('private.pachanga_competition_sequence'),
  completed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check (champion_entry_id <> runner_up_entry_id),
  check (third_place_entry_id is null or third_place_entry_id <> fourth_place_entry_id),
  check (length(completion_checksum) = 64),
  check (jsonb_typeof(snapshot) = 'object'),
  check (revision >= 1),
  unique (bracket_id, revision),
  unique (bracket_id, completion_checksum)
);

alter table public.pachanga_tournament_brackets
  add constraint pachanga_tournament_bracket_current_completion_fk
  foreign key (current_completion_snapshot_id)
  references public.pachanga_tournament_completion_snapshots(id) on delete restrict;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_tournament_knockout_result_resolutions',
    'pachanga_tournament_bracket_advance_decisions',
    'pachanga_tournament_bracket_invalidations',
    'pachanga_tournament_bracket_dependency_impacts',
    'pachanga_tournament_completion_snapshots'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

create trigger guard_pachanga_tournament_knockout_resolution_v1
before update or delete on public.pachanga_tournament_knockout_result_resolutions
for each row execute function private.pachanga_tournament_guard_immutable_v1();
create trigger guard_pachanga_tournament_advance_decision_v1
before update or delete on public.pachanga_tournament_bracket_advance_decisions
for each row execute function private.pachanga_tournament_guard_immutable_v1();
create trigger guard_pachanga_tournament_bracket_invalidation_v1
before update or delete on public.pachanga_tournament_bracket_invalidations
for each row execute function private.pachanga_tournament_guard_immutable_v1();
create trigger guard_pachanga_tournament_bracket_impact_v1
before update or delete on public.pachanga_tournament_bracket_dependency_impacts
for each row execute function private.pachanga_tournament_guard_immutable_v1();
create trigger guard_pachanga_tournament_completion_snapshot_v1
before update or delete on public.pachanga_tournament_completion_snapshots
for each row execute function private.pachanga_tournament_guard_immutable_v1();

-- The League standings engine must not manufacture a standings table for a
-- knockout stage. Rename the proven implementation and keep its public private
-- signature as a narrow dispatcher so all R4C/R4D callers remain compatible.
alter function private.pachanga_league_standings_rebuild_v1(
  uuid, text, uuid, uuid, bigint
) rename to pachanga_league_standings_rebuild_base_r6c_v1;

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
begin
  if exists (
    select 1
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_tournament_bracket_nodes nodes
      on nodes.canonical_match_id = contexts.canonical_match_id
    where contexts.id = target_context_id
  ) then
    return jsonb_build_object(
      'skipped', true,
      'reason', 'KNOCKOUT_STAGE_HAS_NO_STANDINGS',
      'contextId', target_context_id,
      'serverSequence', target_server_sequence
    );
  end if;
  return private.pachanga_league_standings_rebuild_base_r6c_v1(
    target_context_id, target_rebuild_kind, target_operation_id,
    target_actor_id, target_server_sequence
  );
end;
$$;

revoke all on function private.pachanga_league_standings_rebuild_base_r6c_v1(
  uuid, text, uuid, uuid, bigint
) from public, anon, authenticated;
revoke all on function private.pachanga_league_standings_rebuild_v1(
  uuid, text, uuid, uuid, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_tournament_knockout_current_slot_v1(
  target_node_id uuid,
  target_side text
)
returns public.pachanga_tournament_bracket_node_slots
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select slots
  from public.pachanga_tournament_bracket_node_slots slots
  where slots.bracket_node_id = target_node_id
    and slots.side = upper(trim(target_side))
  order by slots.slot_revision desc, slots.server_sequence desc, slots.id desc
  limit 1;
$$;

create or replace function private.pachanga_tournament_knockout_record_node_revision_v1(
  target_node_id uuid,
  target_revision_kind text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare previous_revision public.pachanga_tournament_bracket_node_revisions%rowtype;
declare home_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare away_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare revision_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'node-revision:' || target_node_id::text || ':' || upper(target_revision_kind)
);
declare next_version integer;
declare source_snapshot jsonb;
declare state_snapshot jsonb;
declare checksum_value text;
begin
  select * into node_row from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id for update;
  if not found then raise exception 'TOURNAMENT_BRACKET_NODE_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into previous_revision
  from public.pachanga_tournament_bracket_node_revisions revisions
  where revisions.id = node_row.current_node_revision_id;
  select * into home_slot from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'HOME');
  select * into away_slot from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'AWAY');
  next_version := coalesce(previous_revision.version, 0) + 1;
  source_snapshot := jsonb_build_object(
    'home', case when home_slot.id is null then null else home_slot.source_snapshot end,
    'away', case when away_slot.id is null then null else away_slot.source_snapshot end
  );
  state_snapshot := jsonb_build_object(
    'nodeId', node_row.id,
    'roundCode', node_row.round_code,
    'roundOrder', node_row.round_order,
    'nodeOrder', node_row.node_order,
    'status', node_row.status,
    'homeEntryId', node_row.home_entry_id,
    'awayEntryId', node_row.away_entry_id,
    'winnerEntryId', node_row.winner_entry_id,
    'loserEntryId', node_row.loser_entry_id,
    'canonicalMatchId', node_row.canonical_match_id
  );
  checksum_value := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'source', source_snapshot, 'state', state_snapshot,
    'kind', upper(target_revision_kind), 'version', next_version
  ));
  insert into public.pachanga_tournament_bracket_node_revisions(
    id, bracket_node_id, version, supersedes_revision_id, revision_kind,
    status, home_entry_id, away_entry_id, winner_entry_id, loser_entry_id,
    canonical_match_id, source_snapshot, state_snapshot, checksum,
    operation_id, created_by, server_sequence
  ) values (
    revision_id, node_row.id, next_version, previous_revision.id,
    upper(target_revision_kind), node_row.status, node_row.home_entry_id,
    node_row.away_entry_id, node_row.winner_entry_id, node_row.loser_entry_id,
    node_row.canonical_match_id, source_snapshot, state_snapshot, checksum_value,
    target_operation_id, target_actor_id, target_server_sequence
  ) on conflict (bracket_node_id, operation_id, revision_kind) do nothing;
  if not found then
    select revisions.id into revision_id
    from public.pachanga_tournament_bracket_node_revisions revisions
    where revisions.bracket_node_id = node_row.id
      and revisions.operation_id = target_operation_id
      and revisions.revision_kind = upper(target_revision_kind);
    return revision_id;
  end if;
  update public.pachanga_tournament_bracket_nodes nodes set
    current_node_revision_id = revision_id,
    revision = nodes.revision + 1,
    server_sequence = target_server_sequence,
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where nodes.id = node_row.id;
  return revision_id;
end;
$$;

create or replace function private.pachanga_tournament_knockout_resolve_node_v1(
  target_node_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare source_node public.pachanga_tournament_bracket_nodes%rowtype;
declare home_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare away_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare slot_row public.pachanga_tournament_bracket_node_slots%rowtype;
declare selected_entry_id uuid;
declare selected_status text;
declare selected_home uuid;
declare selected_away uuid;
declare desired_status text;
declare slot_operation_id uuid;
declare slot_id uuid;
declare changed boolean := false;
begin
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id for update;
  if not found then raise exception 'TOURNAMENT_BRACKET_NODE_NOT_FOUND' using errcode = 'P0002'; end if;

  foreach slot_row in array array[
    private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'HOME'),
    private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'AWAY')
  ] loop
    if slot_row.id is null then
      raise exception 'TOURNAMENT_BRACKET_SLOT_REQUIRED' using errcode = '22023';
    end if;
    selected_entry_id := slot_row.resolved_entry_id;
    selected_status := slot_row.resolution_status;
    if slot_row.source_kind in ('WINNER_OF', 'LOSER_OF') then
      select * into source_node
      from public.pachanga_tournament_bracket_nodes nodes
      where nodes.id = slot_row.source_node_id;
      selected_entry_id := case slot_row.source_kind
        when 'WINNER_OF' then source_node.winner_entry_id
        else source_node.loser_entry_id end;
      selected_status := case when selected_entry_id is null
        then 'PENDING_SOURCE' else 'RESOLVED' end;
    end if;
    if selected_entry_id is distinct from slot_row.resolved_entry_id
       or selected_status is distinct from slot_row.resolution_status then
      slot_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
        target_operation_id,
        'slot-resolution:' || node_row.id::text || ':' || slot_row.side
      );
      slot_id := private.pachanga_tournament_knockout_entity_id_v1(
        slot_operation_id, 'slot-revision'
      );
      insert into public.pachanga_tournament_bracket_node_slots(
        id, bracket_id, bracket_revision_id, bracket_node_id, side,
        slot_revision, supersedes_slot_id, source_kind, source_key,
        source_group_id, source_position, source_extra_rank, source_draw_seed,
        source_node_id, resolved_entry_id, resolution_status, source_snapshot,
        operation_id, server_sequence, created_by
      ) values (
        slot_id, slot_row.bracket_id, slot_row.bracket_revision_id,
        slot_row.bracket_node_id, slot_row.side, slot_row.slot_revision + 1,
        slot_row.id, slot_row.source_kind, slot_row.source_key,
        slot_row.source_group_id, slot_row.source_position,
        slot_row.source_extra_rank, slot_row.source_draw_seed,
        slot_row.source_node_id, selected_entry_id, selected_status,
        slot_row.source_snapshot || jsonb_build_object(
          'resolvedEntryId', selected_entry_id,
          'resolutionStatus', selected_status,
          'sourceNodeRevision', source_node.revision
        ),
        slot_operation_id, nextval('private.pachanga_competition_sequence'),
        target_actor_id
      ) on conflict (bracket_node_id, side, operation_id) do nothing;
      changed := true;
    end if;
  end loop;

  select * into home_slot
  from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'HOME');
  select * into away_slot
  from private.pachanga_tournament_knockout_current_slot_v1(node_row.id, 'AWAY');
  selected_home := home_slot.resolved_entry_id;
  selected_away := away_slot.resolved_entry_id;
  if selected_home is not null and selected_home = selected_away then
    raise exception 'TOURNAMENT_BRACKET_DUPLICATE_ENTRY' using errcode = '22023';
  end if;
  desired_status := case
    when selected_home is not null and selected_away is not null then
      case when exists (
        select 1
        from public.pachanga_tournament_bracket_fixture_reservations reservations
        where reservations.bracket_node_id = node_row.id
          and reservations.status = 'ACTIVE'
          and not exists (
            select 1
            from public.pachanga_tournament_bracket_fixture_reservations newer
            where newer.bracket_node_id = reservations.bracket_node_id
              and newer.reservation_revision > reservations.reservation_revision
          )
      ) then 'scheduled' else 'ready' end
    when selected_home is not null and away_slot.source_kind = 'BYE' then 'ready'
    when selected_away is not null and home_slot.source_kind = 'BYE' then 'ready'
    else 'awaiting_sources'
  end;
  if node_row.home_entry_id is distinct from selected_home
     or node_row.away_entry_id is distinct from selected_away
     or node_row.status is distinct from desired_status then
    update public.pachanga_tournament_bracket_nodes nodes set
      home_entry_id = selected_home,
      away_entry_id = selected_away,
      winner_entry_id = null,
      loser_entry_id = null,
      status = desired_status,
      updated_by = target_actor_id,
      updated_at = clock_timestamp()
    where nodes.id = node_row.id;
    perform private.pachanga_tournament_knockout_record_node_revision_v1(
      node_row.id, 'SOURCE_RESOLUTION', target_operation_id,
      target_actor_id, target_server_sequence
    );
    changed := true;
  end if;
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes where nodes.id = target_node_id;
  return jsonb_build_object(
    'nodeId', node_row.id,
    'status', node_row.status,
    'homeEntryId', node_row.home_entry_id,
    'awayEntryId', node_row.away_entry_id,
    'revision', node_row.revision,
    'changed', changed
  );
end;
$$;

create or replace function private.pachanga_tournament_knockout_invalidate_downstream_v1(
  target_source_node_id uuid,
  target_superseded_advance_id uuid,
  target_replacement_official_decision_id uuid,
  target_reason text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare source_node public.pachanga_tournament_bracket_nodes%rowtype;
declare invalidation_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'bracket-invalidation:' || target_source_node_id::text
);
declare affected_node_ids uuid[];
declare affected_match_ids uuid[];
declare impact_snapshot jsonb;
declare descendant record;
declare node_operation_id uuid;
begin
  select * into source_node
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_source_node_id for update;
  if not found then raise exception 'TOURNAMENT_BRACKET_NODE_NOT_FOUND' using errcode = 'P0002'; end if;
  if exists (
    with recursive latest_slots as materialized (
      select distinct on (slots.bracket_node_id, slots.side) slots.*
      from public.pachanga_tournament_bracket_node_slots slots
      where slots.bracket_id = source_node.bracket_id
      order by slots.bracket_node_id, slots.side,
        slots.slot_revision desc, slots.server_sequence desc, slots.id desc
    ), descendants(node_id) as (
      select slots.bracket_node_id from latest_slots slots
      where slots.source_node_id = source_node.id
      union
      select slots.bracket_node_id
      from latest_slots slots join descendants on slots.source_node_id = descendants.node_id
    )
    select 1
    from descendants
    join public.pachanga_tournament_bracket_nodes nodes on nodes.id = descendants.node_id
    left join public.pachanga_competition_match_contexts contexts
      on contexts.canonical_match_id = nodes.canonical_match_id
    where nodes.status in ('in_progress', 'result_pending', 'official', 'advanced')
       or contexts.status in (
         'in_progress', 'played', 'result_pending', 'official', 'suspended',
         'abandoned', 'administrative_review'
       )
  ) then
    raise exception 'DOWNSTREAM_MATCH_ALREADY_STARTED' using errcode = 'PT409';
  end if;

  with recursive latest_slots as materialized (
    select distinct on (slots.bracket_node_id, slots.side) slots.*
    from public.pachanga_tournament_bracket_node_slots slots
    where slots.bracket_id = source_node.bracket_id
    order by slots.bracket_node_id, slots.side,
      slots.slot_revision desc, slots.server_sequence desc, slots.id desc
  ), descendants(node_id) as (
    select slots.bracket_node_id from latest_slots slots
    where slots.source_node_id = source_node.id
    union
    select slots.bracket_node_id
    from latest_slots slots join descendants on slots.source_node_id = descendants.node_id
  )
  select coalesce(array_agg(nodes.id order by nodes.round_order, nodes.node_order), '{}'::uuid[]),
    coalesce(array_agg(nodes.canonical_match_id order by nodes.round_order, nodes.node_order)
      filter (where nodes.canonical_match_id is not null), '{}'::uuid[])
  into affected_node_ids, affected_match_ids
  from descendants join public.pachanga_tournament_bracket_nodes nodes
    on nodes.id = descendants.node_id;

  impact_snapshot := jsonb_build_object(
    'sourceNodeId', source_node.id,
    'affectedNodeIds', to_jsonb(affected_node_ids),
    'affectedCanonicalMatchIds', to_jsonb(affected_match_ids),
    'completionAffected', exists (
      select 1 from public.pachanga_tournament_completion_snapshots completions
      where completions.bracket_id = source_node.bracket_id
    )
  );
  insert into public.pachanga_tournament_bracket_invalidations(
    id, bracket_id, source_node_id, superseded_advance_decision_id,
    replacement_official_decision_id, invalidation_reason,
    affected_node_ids, affected_canonical_match_ids, impact_snapshot,
    operation_id, created_by, server_sequence
  ) values (
    invalidation_id, source_node.bracket_id, source_node.id,
    target_superseded_advance_id, target_replacement_official_decision_id,
    left(trim(target_reason), 1200), affected_node_ids, affected_match_ids,
    impact_snapshot, target_operation_id, target_actor_id,
    target_server_sequence
  ) on conflict (operation_id) do nothing;

  for descendant in
    select nodes.*
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.id = any(affected_node_ids)
    order by nodes.round_order, nodes.node_order
  loop
    insert into public.pachanga_tournament_bracket_dependency_impacts(
      bracket_invalidation_id, bracket_node_id, canonical_match_id,
      impact_kind, participant_changed, referee_impact, schedule_impact,
      discipline_impact, result_impact, completion_impact, detail,
      server_sequence
    ) values (
      invalidation_id, descendant.id, descendant.canonical_match_id,
      case when descendant.canonical_match_id is null
        then 'DESCENDANT_INVALIDATION' else 'MATCH_REPLACEMENT' end,
      true, descendant.canonical_match_id is not null,
      descendant.canonical_match_id is not null,
      descendant.canonical_match_id is not null,
      false, descendant.round_code = 'FINAL',
      jsonb_build_object('previousStatus', descendant.status),
      nextval('private.pachanga_competition_sequence')
    ) on conflict (bracket_invalidation_id, bracket_node_id) do nothing;
    update public.pachanga_tournament_bracket_nodes nodes set
      status = 'invalidated', winner_entry_id = null, loser_entry_id = null,
      updated_by = target_actor_id, updated_at = clock_timestamp()
    where nodes.id = descendant.id;
    node_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id, 'invalidate-node:' || descendant.id::text
    );
    perform private.pachanga_tournament_knockout_record_node_revision_v1(
      descendant.id, 'INVALIDATION', node_operation_id,
      target_actor_id, nextval('private.pachanga_competition_sequence')
    );
  end loop;
  return invalidation_id;
end;
$$;

create or replace function private.pachanga_tournament_knockout_determine_winner_v1(
  target_node_id uuid,
  target_official_decision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare decision_row public.pachanga_competition_official_result_decisions%rowtype;
declare evidence jsonb := '{}'::jsonb;
declare knockout jsonb := '{}'::jsonb;
declare policy jsonb;
declare regulation_home integer;
declare regulation_away integer;
declare extra_time_played boolean := false;
declare extra_home integer;
declare extra_away integer;
declare shootout_home_value integer;
declare shootout_away_value integer;
declare winner_id uuid;
declare loser_id uuid;
declare resolution_kind text;
declare advance_reason text;
begin
  select * into node_row from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id;
  select * into bracket_row from public.pachanga_tournament_brackets brackets
  where brackets.id = node_row.bracket_id;
  select * into decision_row
  from public.pachanga_competition_official_result_decisions decisions
  where decisions.id = target_official_decision_id;
  if node_row.id is null or decision_row.id is null
     or node_row.canonical_match_id is distinct from decision_row.canonical_match_id
     or not exists (
       select 1
       from public.pachanga_competition_match_contexts contexts
       join public.pachanga_competition_match_sheets sheets
         on sheets.competition_match_context_id = contexts.id
       where contexts.id = decision_row.competition_match_context_id
         and contexts.canonical_match_id = decision_row.canonical_match_id
         and contexts.status = 'official'
         and sheets.active_official_decision_id = decision_row.id
     ) then
    raise exception 'TOURNAMENT_KNOCKOUT_OFFICIAL_DECISION_INVALID' using errcode = '22023';
  end if;
  select coalesce(result_evidence.evidence, '{}'::jsonb) into evidence
  from private.pachanga_competition_official_result_evidence result_evidence
  where result_evidence.official_result_decision_id = decision_row.id;
  evidence := coalesce(evidence, '{}'::jsonb);
  knockout := coalesce(evidence -> 'knockout', '{}'::jsonb);
  if jsonb_typeof(knockout) <> 'object'
     or knockout ?| array['winnerEntryId', 'loserEntryId', 'championEntryId'] then
    raise exception 'TOURNAMENT_SERVER_FIELDS_FORBIDDEN' using errcode = '22023';
  end if;
  policy := private.pachanga_tournament_knockout_policy_v1(bracket_row.rule_revision_id);
  if decision_row.outcome = 'ANNULLED' then
    return jsonb_build_object(
      'resolutionKind', 'ANNULLED',
      'advanceReason', null,
      'winnerEntryId', null,
      'loserEntryId', null,
      'policy', policy
    );
  end if;
  begin
    regulation_home := coalesce(
      nullif(knockout ->> 'scoreAfterRegulationHome', '')::integer,
      decision_row.effective_score_home
    );
    regulation_away := coalesce(
      nullif(knockout ->> 'scoreAfterRegulationAway', '')::integer,
      decision_row.effective_score_away
    );
    extra_time_played := coalesce((knockout ->> 'extraTimePlayed')::boolean, false);
    extra_home := nullif(knockout ->> 'scoreAfterExtraTimeHome', '')::integer;
    extra_away := nullif(knockout ->> 'scoreAfterExtraTimeAway', '')::integer;
    shootout_home_value := nullif(knockout ->> 'shootoutHome', '')::integer;
    shootout_away_value := nullif(knockout ->> 'shootoutAway', '')::integer;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'TOURNAMENT_KNOCKOUT_RESULT_INVALID' using errcode = '22023';
  end;
  if regulation_home is null or regulation_away is null
     or regulation_home < 0 or regulation_away < 0
     or extra_home < 0 or extra_away < 0
     or shootout_home_value < 0 or shootout_away_value < 0 then
    raise exception 'TOURNAMENT_KNOCKOUT_RESULT_INVALID' using errcode = '22023';
  end if;
  if decision_row.outcome in ('NO_SHOW', 'FORFEIT') then
    if decision_row.effective_score_home = decision_row.effective_score_away then
      raise exception 'KNOCKOUT_WINNER_REQUIRED' using errcode = '22023';
    end if;
    winner_id := case when decision_row.effective_score_home > decision_row.effective_score_away
      then node_row.home_entry_id else node_row.away_entry_id end;
    loser_id := case when winner_id = node_row.home_entry_id
      then node_row.away_entry_id else node_row.home_entry_id end;
    resolution_kind := case decision_row.outcome when 'NO_SHOW' then 'NO_SHOW' else 'FORFEIT' end;
    advance_reason := resolution_kind;
  elsif regulation_home <> regulation_away then
    if extra_time_played or extra_home is not null or shootout_home_value is not null
       or decision_row.effective_score_home is distinct from regulation_home
       or decision_row.effective_score_away is distinct from regulation_away then
      raise exception 'TOURNAMENT_KNOCKOUT_RESULT_INVALID' using errcode = '22023';
    end if;
    winner_id := case when regulation_home > regulation_away
      then node_row.home_entry_id else node_row.away_entry_id end;
    loser_id := case when winner_id = node_row.home_entry_id
      then node_row.away_entry_id else node_row.home_entry_id end;
    resolution_kind := case when decision_row.outcome = 'MIRROR_SPORTING_RESULT'
      then 'SPORTING_RESULT' else 'ADMINISTRATIVE_DECISION' end;
    advance_reason := resolution_kind;
  else
    if policy ->> 'extraTimePolicy' = 'EXTRA_TIME_THEN_PENALTIES' then
      if not extra_time_played or extra_home is null or extra_away is null
         or decision_row.effective_score_home is distinct from extra_home
         or decision_row.effective_score_away is distinct from extra_away then
        raise exception 'TOURNAMENT_EXTRA_TIME_REQUIRED' using errcode = '22023';
      end if;
      if extra_home <> extra_away then
        if shootout_home_value is not null then
          raise exception 'TOURNAMENT_SHOOTOUT_NOT_ALLOWED' using errcode = '22023';
        end if;
        winner_id := case when extra_home > extra_away
          then node_row.home_entry_id else node_row.away_entry_id end;
        loser_id := case when winner_id = node_row.home_entry_id
          then node_row.away_entry_id else node_row.home_entry_id end;
        resolution_kind := 'EXTRA_TIME';
        advance_reason := 'EXTRA_TIME';
      end if;
    elsif extra_time_played or extra_home is not null then
      raise exception 'TOURNAMENT_EXTRA_TIME_NOT_ALLOWED' using errcode = '22023';
    end if;
    if winner_id is null then
      if policy ->> 'penaltyShootoutPolicy' = 'NO_PENALTIES' then
        raise exception 'KNOCKOUT_WINNER_REQUIRED' using errcode = '22023';
      end if;
      if policy ->> 'penaltyShootoutPolicy' = 'PENALTIES_AFTER_EXTRA_TIME'
         and not extra_time_played then
        raise exception 'TOURNAMENT_EXTRA_TIME_REQUIRED' using errcode = '22023';
      end if;
      if policy ->> 'penaltyShootoutPolicy' = 'PENALTIES_DIRECT'
         and extra_time_played then
        raise exception 'TOURNAMENT_EXTRA_TIME_NOT_ALLOWED' using errcode = '22023';
      end if;
      if shootout_home_value is null or shootout_away_value is null
         or shootout_home_value = shootout_away_value then
        raise exception 'KNOCKOUT_WINNER_REQUIRED' using errcode = '22023';
      end if;
      winner_id := case when shootout_home_value > shootout_away_value
        then node_row.home_entry_id else node_row.away_entry_id end;
      loser_id := case when winner_id = node_row.home_entry_id
        then node_row.away_entry_id else node_row.home_entry_id end;
      resolution_kind := 'PENALTY_SHOOTOUT';
      advance_reason := 'PENALTY_SHOOTOUT';
    end if;
  end if;
  if winner_id is null or loser_id is null or winner_id = loser_id then
    raise exception 'KNOCKOUT_WINNER_REQUIRED' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'scoreAfterRegulationHome', regulation_home,
    'scoreAfterRegulationAway', regulation_away,
    'extraTimePlayed', extra_time_played,
    'scoreAfterExtraTimeHome', extra_home,
    'scoreAfterExtraTimeAway', extra_away,
    'shootoutHome', shootout_home_value,
    'shootoutAway', shootout_away_value,
    'winnerEntryId', winner_id,
    'loserEntryId', loser_id,
    'resolutionKind', resolution_kind,
    'advanceReason', advance_reason,
    'policy', policy
  );
end;
$$;

create or replace function private.pachanga_tournament_knockout_advance_node_v1(
  target_node_id uuid,
  target_official_decision_id uuid,
  target_resolution_id uuid,
  target_advance_reason text,
  target_winner_entry_id uuid,
  target_loser_entry_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare prior_decision public.pachanga_tournament_bracket_advance_decisions%rowtype;
declare advance_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'advance:' || target_node_id::text
);
declare next_revision bigint;
declare destination_snapshot jsonb;
declare dependent_slot public.pachanga_tournament_bracket_node_slots%rowtype;
declare destination_node public.pachanga_tournament_bracket_nodes%rowtype;
declare destination_before public.pachanga_tournament_bracket_nodes%rowtype;
declare selected_entry_id uuid;
declare slot_operation_id uuid;
declare slot_id uuid;
declare child_operation_id uuid;
begin
  select * into node_row from public.pachanga_tournament_bracket_nodes nodes
  where nodes.id = target_node_id for update;
  select * into bracket_row from public.pachanga_tournament_brackets brackets
  where brackets.id = node_row.bracket_id for update;
  if node_row.id is null then raise exception 'TOURNAMENT_BRACKET_NODE_NOT_FOUND' using errcode = 'P0002'; end if;
  if bracket_row.status not in ('active', 'administrative_review') then
    raise exception 'TOURNAMENT_BRACKET_NOT_ACTIVE' using errcode = 'PT409';
  end if;
  if target_winner_entry_id not in (node_row.home_entry_id, node_row.away_entry_id)
     or (target_loser_entry_id is not null
       and target_loser_entry_id not in (node_row.home_entry_id, node_row.away_entry_id))
     or target_winner_entry_id is not distinct from target_loser_entry_id then
    raise exception 'TOURNAMENT_KNOCKOUT_WINNER_INVALID' using errcode = '22023';
  end if;
  select * into prior_decision
  from public.pachanga_tournament_bracket_advance_decisions decisions
  where decisions.source_node_id = node_row.id
  order by decisions.revision desc, decisions.server_sequence desc, decisions.id desc
  limit 1;
  if prior_decision.official_result_decision_id is not distinct from target_official_decision_id
     and prior_decision.id is not null then
    return prior_decision.id;
  end if;
  if prior_decision.id is not null
     and (prior_decision.winner_entry_id is distinct from target_winner_entry_id
       or prior_decision.loser_entry_id is distinct from target_loser_entry_id) then
    perform private.pachanga_tournament_knockout_invalidate_downstream_v1(
      node_row.id, prior_decision.id, target_official_decision_id,
      'El resultado oficial cambió la plaza clasificada.', target_operation_id,
      target_actor_id, target_server_sequence
    );
  end if;
  next_revision := coalesce(prior_decision.revision, 0) + 1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'nodeId', slots.bracket_node_id,
    'side', slots.side,
    'sourceKind', slots.source_kind,
    'entryId', case slots.source_kind when 'WINNER_OF'
      then target_winner_entry_id else target_loser_entry_id end
  ) order by nodes.round_order, nodes.node_order, slots.side), '[]'::jsonb)
  into destination_snapshot
  from (
    select distinct on (all_slots.bracket_node_id, all_slots.side) all_slots.*
    from public.pachanga_tournament_bracket_node_slots all_slots
    where all_slots.source_node_id = node_row.id
    order by all_slots.bracket_node_id, all_slots.side,
      all_slots.slot_revision desc, all_slots.server_sequence desc, all_slots.id desc
  ) slots
  join public.pachanga_tournament_bracket_nodes nodes on nodes.id = slots.bracket_node_id;
  insert into public.pachanga_tournament_bracket_advance_decisions(
    id, bracket_id, bracket_revision_id, source_node_id,
    official_result_decision_id, knockout_resolution_id,
    supersedes_decision_id, advance_reason, winner_entry_id, loser_entry_id,
    destination_slots, revision, operation_id, decided_by, server_sequence
  ) values (
    advance_id, node_row.bracket_id, bracket_row.current_revision_id, node_row.id,
    target_official_decision_id, target_resolution_id, prior_decision.id,
    upper(target_advance_reason), target_winner_entry_id, target_loser_entry_id,
    destination_snapshot, next_revision, target_operation_id,
    target_actor_id, target_server_sequence
  );
  update public.pachanga_tournament_bracket_nodes nodes set
    winner_entry_id = target_winner_entry_id,
    loser_entry_id = target_loser_entry_id,
    status = 'advanced',
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where nodes.id = node_row.id;
  perform private.pachanga_tournament_knockout_record_node_revision_v1(
    node_row.id,
    case when upper(target_advance_reason) = 'BYE' then 'BYE_ADVANCE' else 'ADVANCE' end,
    target_operation_id, target_actor_id, target_server_sequence
  );

  for dependent_slot in
    select distinct on (slots.bracket_node_id, slots.side) slots.*
    from public.pachanga_tournament_bracket_node_slots slots
    where slots.source_node_id = node_row.id
    order by slots.bracket_node_id, slots.side,
      slots.slot_revision desc, slots.server_sequence desc, slots.id desc
  loop
    selected_entry_id := case dependent_slot.source_kind
      when 'WINNER_OF' then target_winner_entry_id else target_loser_entry_id end;
    select * into destination_before
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.id = dependent_slot.bracket_node_id;
    slot_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id,
      'advance-slot:' || dependent_slot.bracket_node_id::text || ':' || dependent_slot.side
    );
    slot_id := private.pachanga_tournament_knockout_entity_id_v1(
      slot_operation_id, 'slot-revision'
    );
    insert into public.pachanga_tournament_bracket_node_slots(
      id, bracket_id, bracket_revision_id, bracket_node_id, side,
      slot_revision, supersedes_slot_id, source_kind, source_key,
      source_group_id, source_position, source_extra_rank, source_draw_seed,
      source_node_id, resolved_entry_id, resolution_status, source_snapshot,
      operation_id, server_sequence, created_by
    ) values (
      slot_id, dependent_slot.bracket_id, dependent_slot.bracket_revision_id,
      dependent_slot.bracket_node_id, dependent_slot.side,
      dependent_slot.slot_revision + 1, dependent_slot.id,
      dependent_slot.source_kind, dependent_slot.source_key,
      dependent_slot.source_group_id, dependent_slot.source_position,
      dependent_slot.source_extra_rank, dependent_slot.source_draw_seed,
      dependent_slot.source_node_id, selected_entry_id,
      case when selected_entry_id is null then 'PENDING_SOURCE' else 'RESOLVED' end,
      dependent_slot.source_snapshot || jsonb_build_object(
        'sourceAdvanceDecisionId', advance_id,
        'resolvedEntryId', selected_entry_id
      ), slot_operation_id, nextval('private.pachanga_competition_sequence'),
      target_actor_id
    ) on conflict (bracket_node_id, side, operation_id) do nothing;
    child_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
      target_operation_id, 'resolve-destination:' || dependent_slot.bracket_node_id::text
    );
    perform private.pachanga_tournament_knockout_resolve_node_v1(
      dependent_slot.bracket_node_id, child_operation_id, target_actor_id,
      nextval('private.pachanga_competition_sequence')
    );
    select * into destination_node
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.id = dependent_slot.bracket_node_id;
    if destination_node.status = 'ready'
       and ((destination_node.home_entry_id is not null and destination_node.away_entry_id is null)
         or (destination_node.away_entry_id is not null and destination_node.home_entry_id is null))
       and exists (
         select 1
         from (
           select private.pachanga_tournament_knockout_current_slot_v1(
             destination_node.id, 'HOME'
           ) as slot
           union all
           select private.pachanga_tournament_knockout_current_slot_v1(
             destination_node.id, 'AWAY'
           )
         ) current_slots
         where (current_slots.slot).source_kind = 'BYE'
       ) then
      child_operation_id := private.pachanga_tournament_knockout_entity_id_v1(
        target_operation_id, 'bye-advance:' || destination_node.id::text
      );
      perform private.pachanga_tournament_knockout_advance_node_v1(
        destination_node.id, null, null, 'BYE',
        coalesce(destination_node.home_entry_id, destination_node.away_entry_id),
        null, child_operation_id, target_actor_id,
        nextval('private.pachanga_competition_sequence')
      );
    elsif to_regprocedure(
      'private.pachanga_tournament_knockout_generate_match_v1(uuid,uuid,uuid,bigint)'
    ) is not null then
      if destination_before.canonical_match_id is not null
         and (destination_before.home_entry_id is distinct from destination_node.home_entry_id
           or destination_before.away_entry_id is distinct from destination_node.away_entry_id) then
        execute 'select private.pachanga_tournament_knockout_replace_downstream_v1($1,$2,$3,$4)'
          using destination_node.id,
            private.pachanga_tournament_knockout_entity_id_v1(
              target_operation_id, 'replace-match:' || destination_node.id::text
            ), target_actor_id, nextval('private.pachanga_competition_sequence');
      elsif destination_node.canonical_match_id is null
         and destination_node.status in ('ready', 'scheduled')
         and exists (
           select 1
           from public.pachanga_tournament_bracket_fixture_reservations reservations
           where reservations.bracket_node_id = destination_node.id
             and reservations.status = 'ACTIVE'
             and not exists (
               select 1
               from public.pachanga_tournament_bracket_fixture_reservations newer
               where newer.bracket_node_id = reservations.bracket_node_id
                 and newer.reservation_revision > reservations.reservation_revision
             )
         ) then
        execute 'select private.pachanga_tournament_knockout_generate_match_v1($1,$2,$3,$4)'
          using destination_node.id,
            private.pachanga_tournament_knockout_entity_id_v1(
              target_operation_id, 'generate-match:' || destination_node.id::text
            ), target_actor_id, nextval('private.pachanga_competition_sequence');
      end if;
    end if;
  end loop;
  return advance_id;
end;
$$;

create or replace function private.pachanga_tournament_knockout_apply_official_decision_v1(
  target_official_decision_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare decision_row public.pachanga_competition_official_result_decisions%rowtype;
declare node_row public.pachanga_tournament_bracket_nodes%rowtype;
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare prior_resolution public.pachanga_tournament_knockout_result_resolutions%rowtype;
declare prior_advance public.pachanga_tournament_bracket_advance_decisions%rowtype;
declare resolution jsonb;
declare resolution_id uuid;
declare resolution_checksum text;
declare advance_id uuid;
declare sequence_value bigint;
begin
  select * into decision_row
  from public.pachanga_competition_official_result_decisions decisions
  where decisions.id = target_official_decision_id for update;
  if not found then raise exception 'TOURNAMENT_OFFICIAL_DECISION_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into node_row
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.canonical_match_id = decision_row.canonical_match_id
  for update;
  if not found then return jsonb_build_object('applied', false, 'reason', 'NOT_KNOCKOUT_MATCH'); end if;
  select * into bracket_row
  from public.pachanga_tournament_brackets brackets
  where brackets.id = node_row.bracket_id for update;
  select * into prior_resolution
  from public.pachanga_tournament_knockout_result_resolutions resolutions
  where resolutions.official_result_decision_id = decision_row.id;
  if found then
    select * into prior_advance
    from public.pachanga_tournament_bracket_advance_decisions decisions
    where decisions.knockout_resolution_id = prior_resolution.id;
    return jsonb_build_object(
      'applied', true,
      'replay', true,
      'resolutionId', prior_resolution.id,
      'advanceDecisionId', prior_advance.id,
      'winnerEntryId', prior_resolution.winner_entry_id,
      'loserEntryId', prior_resolution.loser_entry_id
    );
  end if;
  if bracket_row.status in ('completed', 'locked') then
    raise exception 'TOURNAMENT_BRACKET_COMPLETED' using errcode = '55000';
  end if;
  if exists (
    select 1
    from public.pachanga_tournament_bracket_round_controls controls
    where controls.bracket_id = node_row.bracket_id
      and controls.round_code = node_row.round_code
      and controls.status = 'LOCKED'
      and not exists (
        select 1
        from public.pachanga_tournament_bracket_round_controls newer
        where newer.bracket_id = controls.bracket_id
          and newer.round_code = controls.round_code
          and newer.control_revision > controls.control_revision
      )
  ) then
    raise exception 'TOURNAMENT_ROUND_LOCKED' using errcode = '55000';
  end if;
  resolution := private.pachanga_tournament_knockout_determine_winner_v1(
    node_row.id, decision_row.id
  );
  resolution_id := private.pachanga_tournament_knockout_entity_id_v1(
    decision_row.operation_id, 'result-resolution:' || node_row.id::text
  );
  sequence_value := nextval('private.pachanga_competition_sequence');
  select resolutions.* into prior_resolution
  from public.pachanga_tournament_knockout_result_resolutions resolutions
  join public.pachanga_tournament_bracket_advance_decisions advances
    on advances.knockout_resolution_id = resolutions.id
  where advances.source_node_id = node_row.id
  order by advances.revision desc, advances.server_sequence desc, advances.id desc
  limit 1;
  resolution_checksum := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'nodeId', node_row.id,
    'officialDecisionId', decision_row.id,
    'officialDecisionSequence', decision_row.server_sequence,
    'resolution', resolution
  ));
  insert into public.pachanga_tournament_knockout_result_resolutions(
    id, bracket_id, bracket_node_id, canonical_match_id,
    competition_match_context_id, official_result_decision_id,
    supersedes_resolution_id, score_after_regulation_home,
    score_after_regulation_away, extra_time_played,
    score_after_extra_time_home, score_after_extra_time_away,
    shootout_home, shootout_away, winner_entry_id, loser_entry_id,
    resolution_kind, policy_snapshot, checksum, operation_id, resolved_by,
    server_sequence
  ) values (
    resolution_id, node_row.bracket_id, node_row.id,
    decision_row.canonical_match_id, decision_row.competition_match_context_id,
    decision_row.id, prior_resolution.id,
    nullif(resolution ->> 'scoreAfterRegulationHome', '')::integer,
    nullif(resolution ->> 'scoreAfterRegulationAway', '')::integer,
    coalesce((resolution ->> 'extraTimePlayed')::boolean, false),
    nullif(resolution ->> 'scoreAfterExtraTimeHome', '')::integer,
    nullif(resolution ->> 'scoreAfterExtraTimeAway', '')::integer,
    nullif(resolution ->> 'shootoutHome', '')::integer,
    nullif(resolution ->> 'shootoutAway', '')::integer,
    nullif(resolution ->> 'winnerEntryId', '')::uuid,
    nullif(resolution ->> 'loserEntryId', '')::uuid,
    resolution ->> 'resolutionKind', resolution -> 'policy',
    resolution_checksum, decision_row.operation_id, decision_row.decided_by,
    sequence_value
  );
  if resolution ->> 'resolutionKind' = 'ANNULLED' then
    select * into prior_advance
    from public.pachanga_tournament_bracket_advance_decisions decisions
    where decisions.source_node_id = node_row.id
    order by decisions.revision desc, decisions.server_sequence desc, decisions.id desc
    limit 1;
    if prior_advance.id is not null then
      perform private.pachanga_tournament_knockout_invalidate_downstream_v1(
        node_row.id, prior_advance.id, decision_row.id,
        'La decisión oficial anterior fue anulada.', decision_row.operation_id,
        decision_row.decided_by, sequence_value
      );
    end if;
    update public.pachanga_tournament_bracket_nodes nodes set
      winner_entry_id = null, loser_entry_id = null,
      status = 'administrative_review',
      updated_by = coalesce(decision_row.decided_by, bracket_row.updated_by),
      updated_at = clock_timestamp()
    where nodes.id = node_row.id;
    perform private.pachanga_tournament_knockout_record_node_revision_v1(
      node_row.id, 'INVALIDATION', decision_row.operation_id,
      coalesce(decision_row.decided_by, bracket_row.updated_by), sequence_value
    );
    update public.pachanga_tournament_brackets brackets set
      status = 'administrative_review',
      revision = brackets.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_by = coalesce(decision_row.decided_by, bracket_row.updated_by),
      updated_at = clock_timestamp()
    where brackets.id = bracket_row.id;
    if to_regprocedure(
      'private.pachanga_tournament_knockout_rebuild_read_model_v1(uuid,bigint)'
    ) is not null then
      execute 'select private.pachanga_tournament_knockout_rebuild_read_model_v1($1,$2)'
        using bracket_row.id, nextval('private.pachanga_competition_sequence');
    end if;
    if to_regprocedure(
      'private.pachanga_tournament_knockout_notify_v1(uuid,text,uuid,uuid)'
    ) is not null then
      execute 'select private.pachanga_tournament_knockout_notify_v1($1,$2,$3,$4)'
        using bracket_row.id, 'BRACKET_CORRECTED', node_row.id,
          decision_row.operation_id;
    end if;
    return jsonb_build_object(
      'applied', true, 'resolutionId', resolution_id,
      'advanceDecisionId', null, 'winnerEntryId', null,
      'requiresAdministrativeReview', true
    );
  end if;
  advance_id := private.pachanga_tournament_knockout_advance_node_v1(
    node_row.id, decision_row.id, resolution_id,
    resolution ->> 'advanceReason', (resolution ->> 'winnerEntryId')::uuid,
    (resolution ->> 'loserEntryId')::uuid, decision_row.operation_id,
    coalesce(decision_row.decided_by, bracket_row.updated_by), sequence_value
  );
  update public.pachanga_tournament_brackets brackets set
    status = case
      when brackets.status = 'administrative_review' and not exists (
        select 1
        from public.pachanga_tournament_bracket_nodes review_nodes
        where review_nodes.bracket_id = brackets.id
          and review_nodes.status = 'administrative_review'
      ) then 'active'
      else brackets.status
    end,
    revision = brackets.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_by = coalesce(decision_row.decided_by, bracket_row.updated_by),
    updated_at = clock_timestamp()
  where brackets.id = bracket_row.id;
  if to_regprocedure(
    'private.pachanga_tournament_knockout_rebuild_read_model_v1(uuid,bigint)'
  ) is not null then
    execute 'select private.pachanga_tournament_knockout_rebuild_read_model_v1($1,$2)'
      using bracket_row.id, nextval('private.pachanga_competition_sequence');
  end if;
  if to_regprocedure(
    'private.pachanga_tournament_knockout_notify_v1(uuid,text,uuid,uuid)'
  ) is not null then
    execute 'select private.pachanga_tournament_knockout_notify_v1($1,$2,$3,$4)'
      using bracket_row.id, 'NEXT_MATCH_READY', node_row.id,
        decision_row.operation_id;
  end if;
  return jsonb_build_object(
    'applied', true,
    'replay', false,
    'resolutionId', resolution_id,
    'advanceDecisionId', advance_id,
    'winnerEntryId', resolution ->> 'winnerEntryId',
    'loserEntryId', resolution ->> 'loserEntryId',
    'resolutionKind', resolution ->> 'resolutionKind'
  );
end;
$$;

create or replace function private.pachanga_tournament_knockout_official_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_tournament_knockout_apply_official_decision_v1(new.id);
  return null;
end;
$$;

drop trigger if exists apply_pachanga_tournament_knockout_official_v1
  on public.pachanga_competition_official_result_decisions;
create constraint trigger apply_pachanga_tournament_knockout_official_v1
after insert on public.pachanga_competition_official_result_decisions
deferrable initially deferred
for each row execute function private.pachanga_tournament_knockout_official_trigger_v1();

create or replace function private.pachanga_tournament_completion_rebuild_v1(
  target_bracket_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns public.pachanga_tournament_completion_snapshots
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare bracket_row public.pachanga_tournament_brackets%rowtype;
declare final_node public.pachanga_tournament_bracket_nodes%rowtype;
declare third_node public.pachanga_tournament_bracket_nodes%rowtype;
declare prior_snapshot public.pachanga_tournament_completion_snapshots%rowtype;
declare snapshot_row public.pachanga_tournament_completion_snapshots%rowtype;
declare snapshot_id uuid := private.pachanga_tournament_knockout_entity_id_v1(
  target_operation_id, 'completion-snapshot'
);
declare snapshot_value jsonb;
declare checksum_value text;
declare next_revision bigint;
begin
  select * into bracket_row from public.pachanga_tournament_brackets brackets
  where brackets.id = target_bracket_id for update;
  if not found then raise exception 'TOURNAMENT_BRACKET_NOT_FOUND' using errcode = 'P0002'; end if;
  if bracket_row.status not in ('active', 'administrative_review') then
    raise exception 'TOURNAMENT_BRACKET_NOT_ACTIVE' using errcode = 'PT409';
  end if;
  select * into final_node
  from public.pachanga_tournament_bracket_nodes nodes
  where nodes.bracket_id = bracket_row.id and nodes.round_code = 'FINAL'
    and nodes.node_kind = 'MATCH' and nodes.status = 'advanced';
  if not found or final_node.winner_entry_id is null
     or final_node.loser_entry_id is null or final_node.canonical_match_id is null then
    raise exception 'TOURNAMENT_FINAL_OFFICIAL_REQUIRED' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.pachanga_tournament_bracket_nodes nodes
    left join public.pachanga_competition_match_contexts contexts
      on contexts.canonical_match_id = nodes.canonical_match_id
    where nodes.bracket_id = bracket_row.id
      and nodes.id <> final_node.id
      and (nodes.status not in ('advanced', 'cancelled')
        or contexts.status in (
          'postponed', 'suspended', 'administrative_review', 'result_pending'
        ))
  ) then raise exception 'TOURNAMENT_BRACKET_HEALTH_INVALID' using errcode = 'PT409'; end if;
  if bracket_row.third_place_enabled then
    select * into third_node
    from public.pachanga_tournament_bracket_nodes nodes
    where nodes.bracket_id = bracket_row.id and nodes.node_kind = 'THIRD_PLACE'
      and nodes.status = 'advanced';
    if not found then raise exception 'TOURNAMENT_THIRD_PLACE_REQUIRED' using errcode = '22023'; end if;
  end if;
  select * into prior_snapshot
  from public.pachanga_tournament_completion_snapshots snapshots
  where snapshots.id = bracket_row.current_completion_snapshot_id;
  next_revision := coalesce(prior_snapshot.revision, 0) + 1;
  snapshot_value := jsonb_build_object(
    'kind', 'TournamentCompletionSnapshot',
    'competitionId', bracket_row.competition_id,
    'editionId', bracket_row.edition_id,
    'bracketId', bracket_row.id,
    'bracketRevisionId', bracket_row.current_revision_id,
    'championEntryId', final_node.winner_entry_id,
    'runnerUpEntryId', final_node.loser_entry_id,
    'thirdPlaceEntryId', third_node.winner_entry_id,
    'fourthPlaceEntryId', third_node.loser_entry_id,
    'finalMatchId', final_node.canonical_match_id,
    'rewardGrants', 0,
    'revision', next_revision
  );
  checksum_value := private.pachanga_tournament_json_checksum_v1(snapshot_value);
  select * into snapshot_row
  from public.pachanga_tournament_completion_snapshots snapshots
  where snapshots.bracket_id = bracket_row.id
    and snapshots.completion_checksum = checksum_value;
  if found then return snapshot_row; end if;
  insert into public.pachanga_tournament_completion_snapshots(
    id, competition_id, edition_id, bracket_id, bracket_revision_id,
    champion_entry_id, runner_up_entry_id, third_place_entry_id,
    fourth_place_entry_id, final_match_id, completion_checksum, snapshot,
    revision, operation_id, completed_by, server_sequence
  ) values (
    snapshot_id, bracket_row.competition_id, bracket_row.edition_id,
    bracket_row.id, bracket_row.current_revision_id, final_node.winner_entry_id,
    final_node.loser_entry_id, third_node.winner_entry_id,
    third_node.loser_entry_id, final_node.canonical_match_id,
    checksum_value, snapshot_value, next_revision, target_operation_id,
    target_actor_id, target_server_sequence
  ) returning * into snapshot_row;
  update public.pachanga_tournament_brackets brackets set
    current_completion_snapshot_id = snapshot_row.id,
    revision = brackets.revision + 1,
    server_sequence = target_server_sequence,
    updated_by = target_actor_id,
    updated_at = clock_timestamp()
  where brackets.id = bracket_row.id;
  return snapshot_row;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_knockout_current_slot_v1(uuid,text)'::regprocedure,
    'private.pachanga_tournament_knockout_record_node_revision_v1(uuid,text,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_resolve_node_v1(uuid,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_invalidate_downstream_v1(uuid,uuid,uuid,text,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_determine_winner_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_tournament_knockout_advance_node_v1(uuid,uuid,uuid,text,uuid,uuid,uuid,uuid,bigint)'::regprocedure,
    'private.pachanga_tournament_knockout_apply_official_decision_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_knockout_official_trigger_v1()'::regprocedure,
    'private.pachanga_tournament_completion_rebuild_v1(uuid,uuid,uuid,bigint)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

grant execute on function private.pachanga_tournament_knockout_apply_official_decision_v1(uuid)
  to service_role;

comment on table public.pachanga_tournament_knockout_result_resolutions is
  'Append-only R6C interpretation of an R4C OfficialResultDecision. Penalty goals never enter the ordinary score or scorer totals.';
comment on table public.pachanga_tournament_bracket_advance_decisions is
  'Append-only winner/loser advancement lineage. BYE decisions never create a match or result.';
comment on table public.pachanga_tournament_completion_snapshots is
  'Append-only champion, runner-up and optional third-place read model. It grants no rewards.';
