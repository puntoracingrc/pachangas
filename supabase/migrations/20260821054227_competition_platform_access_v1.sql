-- Pachangas IQ Competition Foundation R1: platform access, canonical adapters and
-- read models. All feature flags remain OFF after migration installation.

create table if not exists private.pachanga_canonical_match_health_state (
  singleton boolean primary key default true,
  snapshot jsonb not null default '{
    "canonicalMatches": 0,
    "bindingsTotal": 0,
    "sources": {"groupMatch": 0, "openMatch": 0, "externalMatch": 0, "teamChallenge": 0},
    "bindings": {"groupMatch": 0, "openMatch": 0, "externalMatch": 0, "teamChallenge": 0},
    "unboundSources": 0,
    "ambiguousBindings": 0,
    "duplicateConflicts": 0,
    "orphanCanonicalMatches": 0,
    "contextsLinked": 0
  }'::jsonb,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  dirty boolean not null default true,
  source_changed_at timestamptz,
  calculated_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (singleton),
  check (revision >= 1)
);

insert into private.pachanga_canonical_match_health_state(singleton)
values (true)
on conflict (singleton) do nothing;

revoke all on table private.pachanga_canonical_match_health_state
  from public, anon, authenticated;
grant all on table private.pachanga_canonical_match_health_state to service_role;

comment on table private.pachanga_canonical_match_health_state is
  'Materialized canonical-match health read model. Source changes mark it stale; canonical commands refresh it.';

create or replace function private.pachanga_platform_capabilities_v1(target_role text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case target_role
    when 'platform_owner' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend', 'roles.manage',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read',
      'competitions.read', 'competitions.manage'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read',
      'competitions.read', 'competitions.manage'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'billing.read', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read'
    )
    else '[]'::jsonb
  end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_canonical_source_exists_v1(
  target_source_kind text,
  target_source_group_id uuid,
  target_source_id text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if target_source_kind = 'group_match' then
    return target_source_group_id is not null and exists (
      select 1 from public.pachanga_match_read_model matches
      where matches.group_id = target_source_group_id and matches.match_id = target_source_id
    );
  elsif target_source_kind = 'open_match' then
    return target_source_group_id is not null
      and target_source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and exists (
        select 1 from public.pachanga_open_matches matches
        where matches.id = target_source_id::uuid
          and matches.source_group_id = target_source_group_id
      );
  elsif target_source_kind = 'external_match' then
    return target_source_group_id is null
      and target_source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and exists (
        select 1 from public.pachanga_external_matches matches
        where matches.id = target_source_id::uuid
      );
  elsif target_source_kind = 'team_challenge' then
    return target_source_group_id is null
      and target_source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      and exists (
        select 1 from public.pachanga_team_challenges challenges
        where challenges.id = target_source_id::uuid
      );
  end if;
  return false;
end;
$$;

revoke all on function private.pachanga_canonical_source_exists_v1(text, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_related_canonical_match_v1(
  target_source_kind text,
  target_source_group_id uuid,
  target_source_id text
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  related_id uuid;
begin
  if target_source_kind = 'open_match' then
    select bindings.canonical_match_id into related_id
    from public.pachanga_open_matches open_matches
    join public.pachanga_canonical_match_bindings bindings
      on bindings.source_kind = 'group_match'
     and bindings.source_group_id = open_matches.source_group_id
     and bindings.source_id = open_matches.source_match_id
     and bindings.binding_status = 'active'
    where open_matches.id = target_source_id::uuid
      and open_matches.source_group_id = target_source_group_id
    order by bindings.server_sequence, bindings.id
    limit 1;
  elsif target_source_kind = 'team_challenge' then
    select bindings.canonical_match_id into related_id
    from public.pachanga_external_matches external_matches
    join public.pachanga_canonical_match_bindings bindings
      on bindings.source_kind = 'external_match'
     and bindings.source_group_id is null
     and bindings.source_id = external_matches.id::text
     and bindings.binding_status = 'active'
    where external_matches.challenge_id = target_source_id::uuid
    order by bindings.server_sequence, bindings.id
    limit 1;
  elsif target_source_kind = 'external_match' then
    select bindings.canonical_match_id into related_id
    from public.pachanga_external_matches external_matches
    join public.pachanga_canonical_match_bindings bindings
      on bindings.source_kind = 'team_challenge'
     and bindings.source_group_id is null
     and bindings.source_id = external_matches.challenge_id::text
     and bindings.binding_status = 'active'
    where external_matches.id = target_source_id::uuid
    order by bindings.server_sequence, bindings.id
    limit 1;
  elsif target_source_kind = 'group_match' then
    select bindings.canonical_match_id into related_id
    from public.pachanga_open_matches open_matches
    join public.pachanga_canonical_match_bindings bindings
      on bindings.source_kind = 'open_match'
     and bindings.source_group_id = open_matches.source_group_id
     and bindings.source_id = open_matches.id::text
     and bindings.binding_status = 'active'
    where open_matches.source_group_id = target_source_group_id
      and open_matches.source_match_id = target_source_id
    order by bindings.server_sequence, bindings.id
    limit 1;
  end if;
  return related_id;
end;
$$;

revoke all on function private.pachanga_related_canonical_match_v1(text, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_backfill_canonical_matches_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  group_bindings integer := 0;
  open_bindings integer := 0;
  external_bindings integer := 0;
  challenge_bindings integer := 0;
  reviews_created integer := 0;
begin
  perform pg_advisory_xact_lock(91401001);

  with missing as materialized (
    select matches.group_id, matches.match_id, gen_random_uuid() as canonical_id
    from public.pachanga_match_read_model matches
    where not exists (
      select 1 from public.pachanga_canonical_match_bindings bindings
      where bindings.source_kind = 'group_match'
        and bindings.source_group_id = matches.group_id
        and bindings.source_id = matches.match_id
        and bindings.binding_status = 'active'
    )
    order by matches.group_id, matches.match_id
  ), inserted_matches as (
    insert into public.pachanga_canonical_matches(id, server_sequence)
    select missing.canonical_id, nextval('private.pachanga_competition_sequence')
    from missing
    returning id
  )
  insert into public.pachanga_canonical_match_bindings(
    canonical_match_id, source_kind, source_group_id, source_id,
    relation_kind, server_sequence
  )
  select missing.canonical_id, 'group_match', missing.group_id, missing.match_id,
    'authoritative_source', nextval('private.pachanga_competition_sequence')
  from missing
  join inserted_matches on inserted_matches.id = missing.canonical_id;
  get diagnostics group_bindings = row_count;

  insert into public.pachanga_canonical_match_bindings(
    canonical_match_id, source_kind, source_group_id, source_id,
    relation_kind, server_sequence
  )
  select group_bindings_source.canonical_match_id, 'open_match', open_matches.source_group_id,
    open_matches.id::text, 'projection', nextval('private.pachanga_competition_sequence')
  from public.pachanga_open_matches open_matches
  join public.pachanga_canonical_match_bindings group_bindings_source
    on group_bindings_source.source_kind = 'group_match'
   and group_bindings_source.source_group_id = open_matches.source_group_id
   and group_bindings_source.source_id = open_matches.source_match_id
   and group_bindings_source.binding_status = 'active'
  where not exists (
    select 1 from public.pachanga_canonical_match_bindings existing
    where existing.source_kind = 'open_match'
      and existing.source_group_id = open_matches.source_group_id
      and existing.source_id = open_matches.id::text
      and existing.binding_status = 'active'
  )
  order by open_matches.source_group_id, open_matches.source_match_id, open_matches.id;
  get diagnostics open_bindings = row_count;

  insert into public.pachanga_canonical_match_binding_reviews(
    left_source_kind, left_source_group_id, left_source_id,
    reason_code, diagnostic, server_sequence
  )
  select 'open_match', open_matches.source_group_id, open_matches.id::text,
    'orphan_open_match_source',
    jsonb_build_object('sourceMatchId', open_matches.source_match_id),
    nextval('private.pachanga_competition_sequence')
  from public.pachanga_open_matches open_matches
  where not exists (
    select 1 from public.pachanga_match_read_model matches
    where matches.group_id = open_matches.source_group_id
      and matches.match_id = open_matches.source_match_id
  )
    and not exists (
      select 1 from public.pachanga_canonical_match_binding_reviews reviews
      where reviews.left_source_kind = 'open_match'
        and reviews.left_source_group_id = open_matches.source_group_id
        and reviews.left_source_id = open_matches.id::text
        and reviews.reason_code = 'orphan_open_match_source'
        and reviews.review_status = 'pending'
    );
  get diagnostics reviews_created = row_count;

  with missing as materialized (
    select matches.id as source_id, gen_random_uuid() as canonical_id
    from public.pachanga_external_matches matches
    where not exists (
      select 1 from public.pachanga_canonical_match_bindings bindings
      where bindings.source_kind = 'external_match'
        and bindings.source_group_id is null
        and bindings.source_id = matches.id::text
        and bindings.binding_status = 'active'
    )
    order by matches.id
  ), inserted_matches as (
    insert into public.pachanga_canonical_matches(id, server_sequence)
    select missing.canonical_id, nextval('private.pachanga_competition_sequence')
    from missing
    returning id
  )
  insert into public.pachanga_canonical_match_bindings(
    canonical_match_id, source_kind, source_group_id, source_id,
    relation_kind, server_sequence
  )
  select missing.canonical_id, 'external_match', null, missing.source_id::text,
    'authoritative_source', nextval('private.pachanga_competition_sequence')
  from missing
  join inserted_matches on inserted_matches.id = missing.canonical_id;
  get diagnostics external_bindings = row_count;

  insert into public.pachanga_canonical_match_bindings(
    canonical_match_id, source_kind, source_group_id, source_id,
    relation_kind, server_sequence
  )
  select external_bindings_source.canonical_match_id, 'team_challenge', null,
    external_matches.challenge_id::text, 'provenance',
    nextval('private.pachanga_competition_sequence')
  from public.pachanga_external_matches external_matches
  join public.pachanga_canonical_match_bindings external_bindings_source
    on external_bindings_source.source_kind = 'external_match'
   and external_bindings_source.source_group_id is null
   and external_bindings_source.source_id = external_matches.id::text
   and external_bindings_source.binding_status = 'active'
  where not exists (
    select 1 from public.pachanga_canonical_match_bindings existing
    where existing.source_kind = 'team_challenge'
      and existing.source_group_id is null
      and existing.source_id = external_matches.challenge_id::text
      and existing.binding_status = 'active'
  )
  order by external_matches.challenge_id;
  get diagnostics challenge_bindings = row_count;

  perform private.pachanga_refresh_canonical_match_health_v1();

  return jsonb_build_object(
    'groupBindingsCreated', group_bindings,
    'openBindingsCreated', open_bindings,
    'externalBindingsCreated', external_bindings,
    'challengeBindingsCreated', challenge_bindings,
    'reviewsCreated', reviews_created,
    'canonicalMatchesCreated', group_bindings + external_bindings
  );
end;
$$;

revoke all on function private.pachanga_backfill_canonical_matches_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_canonical_match_snapshot_v1(
  target_canonical_match_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'canonicalMatch', jsonb_build_object(
      'id', matches.id,
      'status', matches.status,
      'revision', matches.revision,
      'serverSequence', matches.server_sequence,
      'createdAt', matches.created_at,
      'updatedAt', matches.updated_at
    ),
    'bindings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', bindings.id,
        'sourceKind', bindings.source_kind,
        'sourceGroupId', bindings.source_group_id,
        'sourceId', bindings.source_id,
        'relationKind', bindings.relation_kind,
        'status', bindings.binding_status,
        'revision', bindings.revision,
        'serverSequence', bindings.server_sequence
      ) order by bindings.source_kind, bindings.source_group_id, bindings.source_id, bindings.id)
      from public.pachanga_canonical_match_bindings bindings
      where bindings.canonical_match_id = matches.id
    ), '[]'::jsonb),
    'contexts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', contexts.id,
        'competitionId', contexts.competition_id,
        'editionId', contexts.edition_id,
        'stageId', contexts.stage_id,
        'divisionId', contexts.division_id,
        'groupId', contexts.competition_group_id,
        'ruleRevisionId', contexts.rule_revision_id,
        'status', contexts.status,
        'revision', contexts.revision
      ) order by contexts.server_sequence, contexts.id)
      from public.pachanga_competition_match_contexts contexts
      where contexts.canonical_match_id = matches.id
    ), '[]'::jsonb)
  )
  from public.pachanga_canonical_matches matches
  where matches.id = target_canonical_match_id;
$$;

revoke all on function private.pachanga_canonical_match_snapshot_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_compute_canonical_match_health_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with source_counts as (
    select
      (select count(*) from public.pachanga_match_read_model) as group_sources,
      (select count(*) from public.pachanga_open_matches) as open_sources,
      (select count(*) from public.pachanga_external_matches) as external_sources,
      (select count(*) from public.pachanga_team_challenges challenges
        where exists (select 1 from public.pachanga_external_matches matches where matches.challenge_id = challenges.id)
      ) as challenge_sources
  ), binding_counts as (
    select
      count(*) filter (where source_kind = 'group_match' and binding_status = 'active') as group_bindings,
      count(*) filter (where source_kind = 'open_match' and binding_status = 'active') as open_bindings,
      count(*) filter (where source_kind = 'external_match' and binding_status = 'active') as external_bindings,
      count(*) filter (where source_kind = 'team_challenge' and binding_status = 'active') as challenge_bindings
    from public.pachanga_canonical_match_bindings
  ), conflicts as (
    select
      (select count(*)
       from public.pachanga_open_matches open_matches
       join public.pachanga_canonical_match_bindings open_bindings
         on open_bindings.source_kind = 'open_match'
        and open_bindings.source_group_id = open_matches.source_group_id
        and open_bindings.source_id = open_matches.id::text
        and open_bindings.binding_status = 'active'
       join public.pachanga_canonical_match_bindings group_bindings
         on group_bindings.source_kind = 'group_match'
        and group_bindings.source_group_id = open_matches.source_group_id
        and group_bindings.source_id = open_matches.source_match_id
        and group_bindings.binding_status = 'active'
       where open_bindings.canonical_match_id <> group_bindings.canonical_match_id) as open_conflicts,
      (select count(*)
       from public.pachanga_external_matches external_matches
       join public.pachanga_canonical_match_bindings external_bindings
         on external_bindings.source_kind = 'external_match'
        and external_bindings.source_id = external_matches.id::text
        and external_bindings.binding_status = 'active'
       join public.pachanga_canonical_match_bindings challenge_bindings
         on challenge_bindings.source_kind = 'team_challenge'
        and challenge_bindings.source_id = external_matches.challenge_id::text
        and challenge_bindings.binding_status = 'active'
       where external_bindings.canonical_match_id <> challenge_bindings.canonical_match_id) as challenge_conflicts
  )
  select jsonb_build_object(
    'canonicalMatches', (select count(*) from public.pachanga_canonical_matches where status = 'active'),
    'bindingsTotal', (select count(*) from public.pachanga_canonical_match_bindings where binding_status = 'active'),
    'sources', jsonb_build_object(
      'groupMatch', source_counts.group_sources,
      'openMatch', source_counts.open_sources,
      'externalMatch', source_counts.external_sources,
      'teamChallenge', source_counts.challenge_sources
    ),
    'bindings', jsonb_build_object(
      'groupMatch', binding_counts.group_bindings,
      'openMatch', binding_counts.open_bindings,
      'externalMatch', binding_counts.external_bindings,
      'teamChallenge', binding_counts.challenge_bindings
    ),
    'unboundSources',
      greatest(source_counts.group_sources - binding_counts.group_bindings, 0)
      + greatest(source_counts.open_sources - binding_counts.open_bindings, 0)
      + greatest(source_counts.external_sources - binding_counts.external_bindings, 0)
      + greatest(source_counts.challenge_sources - binding_counts.challenge_bindings, 0),
    'ambiguousBindings', (select count(*) from public.pachanga_canonical_match_binding_reviews where review_status = 'pending'),
    'duplicateConflicts', conflicts.open_conflicts + conflicts.challenge_conflicts,
    'orphanCanonicalMatches', (
      select count(*) from public.pachanga_canonical_matches matches
      where matches.status = 'active' and not exists (
        select 1 from public.pachanga_canonical_match_bindings bindings
        where bindings.canonical_match_id = matches.id and bindings.binding_status = 'active'
      )
    ),
    'contextsLinked', (select count(*) from public.pachanga_competition_match_contexts where status = 'lab_bound')
  )
  from source_counts, binding_counts, conflicts;
$$;

revoke all on function private.pachanga_compute_canonical_match_health_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_canonical_match_health_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select state.snapshot || jsonb_build_object(
    'revision', state.revision,
    'serverSequence', state.server_sequence,
    'stale', state.dirty,
    'sourceChangedAt', state.source_changed_at,
    'calculatedAt', state.calculated_at,
    'updatedAt', state.updated_at
  )
  from private.pachanga_canonical_match_health_state state
  where state.singleton;
$$;

revoke all on function private.pachanga_canonical_match_health_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_refresh_canonical_match_health_v1()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  computed_snapshot jsonb;
  refreshed_snapshot jsonb;
begin
  perform pg_advisory_xact_lock(91401002);
  computed_snapshot := private.pachanga_compute_canonical_match_health_v1();

  update private.pachanga_canonical_match_health_state state set
    snapshot = computed_snapshot,
    revision = state.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    dirty = false,
    calculated_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where state.singleton;

  refreshed_snapshot := private.pachanga_canonical_match_health_v1();
  return refreshed_snapshot;
end;
$$;

revoke all on function private.pachanga_refresh_canonical_match_health_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_mark_canonical_match_health_dirty_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  update private.pachanga_canonical_match_health_state state set
    revision = state.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    dirty = true,
    source_changed_at = clock_timestamp(),
    updated_at = clock_timestamp()
  where state.singleton and not state.dirty;
  return null;
end;
$$;

revoke all on function private.pachanga_mark_canonical_match_health_dirty_v1()
  from public, anon, authenticated;

drop trigger if exists mark_canonical_health_dirty_group_match_v1 on public.pachanga_match_read_model;
create trigger mark_canonical_health_dirty_group_match_v1
after insert or update or delete or truncate on public.pachanga_match_read_model
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

drop trigger if exists mark_canonical_health_dirty_open_match_v1 on public.pachanga_open_matches;
create trigger mark_canonical_health_dirty_open_match_v1
after insert or update or delete or truncate on public.pachanga_open_matches
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

drop trigger if exists mark_canonical_health_dirty_external_match_v1 on public.pachanga_external_matches;
create trigger mark_canonical_health_dirty_external_match_v1
after insert or update or delete or truncate on public.pachanga_external_matches
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

drop trigger if exists mark_canonical_health_dirty_team_challenge_v1 on public.pachanga_team_challenges;
create trigger mark_canonical_health_dirty_team_challenge_v1
after insert or update or delete or truncate on public.pachanga_team_challenges
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

drop trigger if exists mark_canonical_health_dirty_match_v1 on public.pachanga_canonical_matches;
create trigger mark_canonical_health_dirty_match_v1
after insert or update or delete or truncate on public.pachanga_canonical_matches
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

drop trigger if exists mark_canonical_health_dirty_binding_v1 on public.pachanga_canonical_match_bindings;
create trigger mark_canonical_health_dirty_binding_v1
after insert or update or delete or truncate on public.pachanga_canonical_match_bindings
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

drop trigger if exists mark_canonical_health_dirty_review_v1 on public.pachanga_canonical_match_binding_reviews;
create trigger mark_canonical_health_dirty_review_v1
after insert or update or delete or truncate on public.pachanga_canonical_match_binding_reviews
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

drop trigger if exists mark_canonical_health_dirty_context_v1 on public.pachanga_competition_match_contexts;
create trigger mark_canonical_health_dirty_context_v1
after insert or update or delete or truncate on public.pachanga_competition_match_contexts
for each statement execute function private.pachanga_mark_canonical_match_health_dirty_v1();

create or replace function public.command_pachanga_competition_platform_v1(
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
declare
  flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c001'::uuid;
  registry_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c002'::uuid;
  actor_id uuid := (select auth.uid());
  actor_kind text;
  request_hash text;
  replay jsonb;
  sanitized_metadata jsonb;
  confirmed_at timestamptz := clock_timestamp();
  sequence_value bigint;
  reason_code text;
  aggregate_type text;
  competition_id uuid;
  organizer_group_id uuid;
  confirmed_revision bigint;
  event_payload jsonb := '{}'::jsonb;
  snapshot jsonb;
  settings private.pachanga_competition_foundation_settings%rowtype;
  organizer_row public.pachanga_competition_organizer_states%rowtype;
  grant_row public.pachanga_competition_entitlement_grants%rowtype;
  canonical_row public.pachanga_canonical_matches%rowtype;
  competition_row public.pachanga_competitions%rowtype;
  target_source_kind text;
  target_source_group_id uuid;
  target_source_id text;
  relation_kind text;
  capability_name text;
  canonical_match_id uuid;
  related_canonical_id uuid;
  created_id uuid;
  backfill_result jsonb;
  state_was_missing boolean := false;
  next_foundation boolean;
  next_creation boolean;
  next_context boolean;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or nullif(trim(command_action), '') is null then
    raise exception 'INVALID_COMPETITION_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_COMPETITION_PLATFORM_PAYLOAD' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'Authentication required' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  else
    perform private.pachanga_platform_require_v1('competitions.manage');
    actor_kind := 'authenticated';
  end if;
  sanitized_metadata := private.pachanga_competition_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb));
  request_hash := private.pachanga_competition_request_hash_v1(
    command_action, aggregate_id, expected_revision, coalesce(command_payload, '{}'::jsonb)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91402));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, command_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  reason_code := left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), command_action), 120);

  if command_action = 'foundation_flags.set' then
    if aggregate_id <> flags_aggregate_id then
      raise exception 'INVALID_FOUNDATION_FLAGS_AGGREGATE' using errcode = '22023';
    end if;
    select * into settings
    from private.pachanga_competition_foundation_settings
    where singleton
    for update;
    if settings.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if command_payload ? 'foundationEnabled'
       and jsonb_typeof(command_payload -> 'foundationEnabled') <> 'boolean' then
      raise exception 'INVALID_FOUNDATION_FLAG' using errcode = '22023';
    end if;
    if command_payload ? 'creationEnabled'
       and jsonb_typeof(command_payload -> 'creationEnabled') <> 'boolean' then
      raise exception 'INVALID_CREATION_FLAG' using errcode = '22023';
    end if;
    if command_payload ? 'contextBindingEnabled'
       and jsonb_typeof(command_payload -> 'contextBindingEnabled') <> 'boolean' then
      raise exception 'INVALID_CONTEXT_BINDING_FLAG' using errcode = '22023';
    end if;
    next_foundation := coalesce((command_payload ->> 'foundationEnabled')::boolean, settings.foundation_enabled);
    next_creation := coalesce((command_payload ->> 'creationEnabled')::boolean, settings.creation_enabled);
    next_context := coalesce((command_payload ->> 'contextBindingEnabled')::boolean, settings.context_binding_enabled);
    if not next_foundation then
      next_creation := false;
      next_context := false;
    end if;
    update private.pachanga_competition_foundation_settings foundation_settings set
      foundation_enabled = next_foundation,
      creation_enabled = next_creation,
      context_binding_enabled = next_context,
      revision = foundation_settings.revision + 1,
      server_sequence = sequence_value,
      updated_by = actor_id,
      updated_at = confirmed_at
    where foundation_settings.singleton
    returning foundation_settings.revision into confirmed_revision;
    aggregate_type := 'competition_foundation_flags';
    snapshot := jsonb_build_object(
      'foundationEnabled', next_foundation,
      'creationEnabled', next_creation,
      'contextBindingEnabled', next_context,
      'revision', confirmed_revision,
      'updatedAt', confirmed_at
    );
    event_payload := snapshot - 'updatedAt';

  elsif command_action in ('entitlement.grant', 'entitlement.revoke') then
    perform 1 from public.pachanga_groups groups where groups.id = aggregate_id for update;
    if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into organizer_row
    from public.pachanga_competition_organizer_states states
    where states.organizer_group_id = aggregate_id
    for update;
    if not found then
      state_was_missing := true;
      if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      insert into public.pachanga_competition_organizer_states(
        organizer_group_id, revision, server_sequence
      ) values (aggregate_id, 1, sequence_value)
      returning * into organizer_row;
      confirmed_revision := 1;
    else
      if organizer_row.revision <> expected_revision then
        raise exception 'STALE_REVISION' using errcode = 'PT409';
      end if;
    end if;
    organizer_group_id := aggregate_id;
    aggregate_type := 'competition_organizer';

    if command_action = 'entitlement.grant' then
      capability_name := trim(coalesce(command_payload ->> 'capability', ''));
      if capability_name not in (
        'competition_create', 'competition_manage', 'competition_staff', 'competition_rules'
      ) then
        raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
      end if;
      if length(trim(coalesce(command_payload ->> 'reason', ''))) < 3 then
        raise exception 'ENTITLEMENT_REASON_REQUIRED' using errcode = '22023';
      end if;
      update public.pachanga_competition_entitlement_grants grants set
        status = 'revoked', revision = grants.revision + 1,
        revoked_by = actor_id, revoked_at = confirmed_at,
        server_sequence = sequence_value
      where grants.organizer_group_id = aggregate_id
        and grants.capability = capability_name
        and grants.status = 'active';
      created_id := gen_random_uuid();
      insert into public.pachanga_competition_entitlement_grants(
        id, organizer_group_id, capability, grant_source, valid_from, expires_at,
        reason, server_sequence, granted_by
      ) values (
        created_id, aggregate_id, capability_name, 'platform_grant',
        coalesce(nullif(command_payload ->> 'validFrom', '')::timestamptz, confirmed_at),
        nullif(command_payload ->> 'expiresAt', '')::timestamptz,
        trim(command_payload ->> 'reason'), sequence_value, actor_id
      );
      event_payload := jsonb_build_object('entitlementId', created_id, 'capability', capability_name);
    else
      select * into grant_row
      from public.pachanga_competition_entitlement_grants grants
      where grants.id = (command_payload ->> 'entitlementId')::uuid
        and grants.organizer_group_id = aggregate_id
      for update;
      if not found then raise exception 'ENTITLEMENT_NOT_FOUND' using errcode = 'P0002'; end if;
      if grant_row.status <> 'active' then
        raise exception 'ENTITLEMENT_NOT_ACTIVE' using errcode = '22023';
      end if;
      update public.pachanga_competition_entitlement_grants grants set
        status = 'revoked', revision = grants.revision + 1,
        revoked_by = actor_id, revoked_at = confirmed_at,
        server_sequence = sequence_value
      where grants.id = grant_row.id;
      event_payload := jsonb_build_object('entitlementId', grant_row.id, 'capability', grant_row.capability);
    end if;
    if not state_was_missing then
      update public.pachanga_competition_organizer_states states set
        revision = states.revision + 1, server_sequence = sequence_value
      where states.organizer_group_id = aggregate_id
      returning states.revision into confirmed_revision;
    end if;
    snapshot := private.pachanga_competition_entitlement_snapshot_v1(aggregate_id);

  elsif command_action in ('canonical.backfill', 'canonical.binding_review.create') then
    if aggregate_id <> registry_aggregate_id then
      raise exception 'INVALID_CANONICAL_REGISTRY_AGGREGATE' using errcode = '22023';
    end if;
    perform private.pachanga_competition_assert_flags_v1(false, false);
    select * into settings
    from private.pachanga_competition_foundation_settings
    where singleton
    for share;
    if settings.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    confirmed_revision := settings.revision;
    aggregate_type := 'canonical_match_registry';
    if command_action = 'canonical.backfill' then
      backfill_result := private.pachanga_backfill_canonical_matches_v1();
      snapshot := jsonb_build_object(
        'backfill', backfill_result,
        'health', private.pachanga_canonical_match_health_v1()
      );
      event_payload := backfill_result;
    else
      target_source_kind := trim(coalesce(command_payload ->> 'leftSourceKind', ''));
      target_source_group_id := nullif(command_payload ->> 'leftSourceGroupId', '')::uuid;
      target_source_id := trim(coalesce(command_payload ->> 'leftSourceId', ''));
      if not private.pachanga_canonical_source_exists_v1(target_source_kind, target_source_group_id, target_source_id) then
        raise exception 'CANONICAL_SOURCE_NOT_FOUND' using errcode = 'P0002';
      end if;
      if nullif(command_payload ->> 'rightSourceKind', '') is not null
         and not private.pachanga_canonical_source_exists_v1(
           command_payload ->> 'rightSourceKind',
           nullif(command_payload ->> 'rightSourceGroupId', '')::uuid,
           command_payload ->> 'rightSourceId'
         ) then
        raise exception 'CANONICAL_REVIEW_SOURCE_NOT_FOUND' using errcode = 'P0002';
      end if;
      created_id := gen_random_uuid();
      insert into public.pachanga_canonical_match_binding_reviews(
        id, left_source_kind, left_source_group_id, left_source_id,
        right_source_kind, right_source_group_id, right_source_id,
        reason_code, diagnostic, server_sequence, created_by
      ) values (
        created_id, target_source_kind, target_source_group_id, target_source_id,
        nullif(command_payload ->> 'rightSourceKind', ''),
        nullif(command_payload ->> 'rightSourceGroupId', '')::uuid,
        nullif(command_payload ->> 'rightSourceId', ''),
        coalesce(nullif(command_payload ->> 'reasonCode', ''), 'manual_ambiguous_match'),
        jsonb_build_object('note', left(coalesce(command_payload ->> 'note', ''), 500)),
        sequence_value, actor_id
      );
      perform private.pachanga_refresh_canonical_match_health_v1();
      snapshot := jsonb_build_object(
        'reviewId', created_id,
        'health', private.pachanga_canonical_match_health_v1()
      );
      event_payload := jsonb_build_object('reviewId', created_id, 'reasonCode', command_payload ->> 'reasonCode');
    end if;

  elsif command_action = 'canonical.bind' then
    perform private.pachanga_competition_assert_flags_v1(false, false);
    target_source_kind := trim(coalesce(command_payload ->> 'sourceKind', ''));
    target_source_group_id := nullif(command_payload ->> 'sourceGroupId', '')::uuid;
    target_source_id := trim(coalesce(command_payload ->> 'sourceId', ''));
    if not private.pachanga_canonical_source_exists_v1(target_source_kind, target_source_group_id, target_source_id) then
      raise exception 'CANONICAL_SOURCE_NOT_FOUND' using errcode = 'P0002';
    end if;
    if exists (
      select 1 from public.pachanga_canonical_match_bindings bindings
      where bindings.source_kind = target_source_kind
        and bindings.source_group_id is not distinct from target_source_group_id
        and bindings.source_id = target_source_id
        and bindings.binding_status = 'active'
    ) then
      raise exception 'CANONICAL_SOURCE_ALREADY_BOUND' using errcode = 'PT409';
    end if;
    related_canonical_id := private.pachanga_related_canonical_match_v1(
      target_source_kind, target_source_group_id, target_source_id
    );
    canonical_match_id := nullif(command_payload ->> 'canonicalMatchId', '')::uuid;
    if canonical_match_id is null then
      if aggregate_id <> registry_aggregate_id then
        raise exception 'INVALID_CANONICAL_REGISTRY_AGGREGATE' using errcode = '22023';
      end if;
      select * into settings
      from private.pachanga_competition_foundation_settings
      where singleton
      for share;
      if settings.revision <> expected_revision then
        raise exception 'STALE_REVISION' using errcode = 'PT409';
      end if;
      if related_canonical_id is not null then
        raise exception 'CANONICAL_MATCH_ID_REQUIRED' using errcode = '22023';
      end if;
      canonical_match_id := gen_random_uuid();
      insert into public.pachanga_canonical_matches(
        id, revision, server_sequence, created_by
      ) values (canonical_match_id, 1, sequence_value, actor_id);
      confirmed_revision := 1;
      aggregate_type := 'canonical_match_registry';
    else
      if aggregate_id <> canonical_match_id then
        raise exception 'CANONICAL_AGGREGATE_MISMATCH' using errcode = '22023';
      end if;
      select * into canonical_row
      from public.pachanga_canonical_matches matches
      where matches.id = canonical_match_id and matches.status = 'active'
      for update;
      if not found then raise exception 'CANONICAL_MATCH_NOT_FOUND' using errcode = 'P0002'; end if;
      if canonical_row.revision <> expected_revision then
        raise exception 'STALE_REVISION' using errcode = 'PT409';
      end if;
      if related_canonical_id is not null and related_canonical_id <> canonical_match_id then
        raise exception 'CANONICAL_RELATED_SOURCE_CONFLICT' using errcode = 'PT409';
      end if;
      update public.pachanga_canonical_matches matches set
        revision = matches.revision + 1, server_sequence = sequence_value
      where matches.id = canonical_match_id
      returning matches.revision into confirmed_revision;
      aggregate_type := 'canonical_match';
    end if;
    relation_kind := case
      when target_source_kind = 'open_match' then 'projection'
      when target_source_kind = 'team_challenge' then 'provenance'
      when aggregate_id = registry_aggregate_id then 'authoritative_source'
      else 'manual_verified'
    end;
    created_id := gen_random_uuid();
    insert into public.pachanga_canonical_match_bindings(
      id, canonical_match_id, source_kind, source_group_id, source_id,
      relation_kind, server_sequence, created_by
    ) values (
      created_id, canonical_match_id, target_source_kind, target_source_group_id, target_source_id,
      relation_kind, sequence_value, actor_id
    );
    perform private.pachanga_refresh_canonical_match_health_v1();
    snapshot := private.pachanga_canonical_match_snapshot_v1(canonical_match_id);
    event_payload := jsonb_build_object(
      'canonicalMatchId', canonical_match_id,
      'bindingId', created_id,
      'sourceKind', target_source_kind,
      'relationKind', relation_kind
    );

  elsif command_action = 'competition_match_context.bind' then
    perform private.pachanga_competition_assert_flags_v1(false, true);
    select * into canonical_row
    from public.pachanga_canonical_matches matches
    where matches.id = aggregate_id and matches.status = 'active'
    for update;
    if not found then raise exception 'CANONICAL_MATCH_NOT_FOUND' using errcode = 'P0002'; end if;
    if canonical_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    competition_id := (command_payload ->> 'competitionId')::uuid;
    select * into competition_row
    from public.pachanga_competitions competitions
    where competitions.id = competition_id;
    if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
    organizer_group_id := competition_row.organizer_group_id;
    created_id := gen_random_uuid();
    insert into public.pachanga_competition_match_contexts(
      id, canonical_match_id, competition_id, edition_id, stage_id,
      division_id, competition_group_id, rule_revision_id,
      server_sequence, created_by
    ) values (
      created_id, canonical_row.id, competition_id,
      (command_payload ->> 'editionId')::uuid,
      (command_payload ->> 'stageId')::uuid,
      nullif(command_payload ->> 'divisionId', '')::uuid,
      nullif(command_payload ->> 'groupId', '')::uuid,
      (command_payload ->> 'ruleRevisionId')::uuid,
      sequence_value, actor_id
    );
    update public.pachanga_canonical_matches matches set
      revision = matches.revision + 1, server_sequence = sequence_value
    where matches.id = canonical_row.id
    returning matches.revision into confirmed_revision;
    perform private.pachanga_refresh_canonical_match_health_v1();
    aggregate_type := 'canonical_match';
    snapshot := jsonb_build_object(
      'canonical', private.pachanga_canonical_match_snapshot_v1(canonical_row.id),
      'competition', private.pachanga_competition_snapshot_v1(competition_id)
    );
    event_payload := jsonb_build_object(
      'contextId', created_id,
      'canonicalMatchId', canonical_row.id,
      'competitionId', competition_id
    );
  else
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  return private.pachanga_competition_store_command_v1(
    operation_id,
    actor_id,
    actor_kind,
    command_action,
    aggregate_type,
    aggregate_id,
    competition_id,
    organizer_group_id,
    confirmed_revision,
    sequence_value,
    reason_code,
    request_hash,
    sanitized_metadata,
    event_payload,
    snapshot,
    confirmed_at
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_competition_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_competition_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;

create or replace function public.get_pachanga_competition_foundation_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.foundation_enabled,
    'creationEnabled', settings.creation_enabled,
    'contextBindingEnabled', settings.context_binding_enabled,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton and (select auth.uid()) is not null;
$$;

revoke all on function public.get_pachanga_competition_foundation_flags_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_competition_foundation_flags_v1()
  to authenticated, service_role;

create or replace function public.get_pachanga_platform_canonical_match_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  return private.pachanga_canonical_match_health_v1();
end;
$$;

revoke all on function public.get_pachanga_platform_canonical_match_health_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_canonical_match_health_v1()
  to authenticated, service_role;

create or replace function public.get_pachanga_platform_canonical_match_v1(
  target_canonical_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  snapshot jsonb;
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  snapshot := private.pachanga_canonical_match_snapshot_v1(target_canonical_match_id);
  if snapshot is null then raise exception 'CANONICAL_MATCH_NOT_FOUND' using errcode = 'P0002'; end if;
  return snapshot;
end;
$$;

revoke all on function public.get_pachanga_platform_canonical_match_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_canonical_match_v1(uuid)
  to authenticated, service_role;

create or replace function public.get_pachanga_platform_competition_foundation_v1(
  page_offset integer default 0,
  page_size integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
  bounded_size integer := least(greatest(coalesce(page_size, 50), 1), 200);
  settings private.pachanga_competition_foundation_settings%rowtype;
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  return jsonb_build_object(
    'flags', jsonb_build_object(
      'foundationEnabled', settings.foundation_enabled,
      'creationEnabled', settings.creation_enabled,
      'contextBindingEnabled', settings.context_binding_enabled,
      'revision', settings.revision,
      'serverSequence', settings.server_sequence,
      'updatedAt', settings.updated_at
    ),
    'metrics', jsonb_build_object(
      'competitions', (select count(*) from public.pachanga_competitions),
      'drafts', (select count(*) from public.pachanga_competitions where status = 'draft'),
      'editions', (select count(*) from public.pachanga_competition_editions),
      'ruleRevisions', (select count(*) from public.pachanga_competition_rule_revisions),
      'activeEntitlements', (
        select count(*) from public.pachanga_competition_entitlement_grants grants
        where grants.status = 'active'
          and grants.valid_from <= statement_timestamp()
          and (grants.expires_at is null or grants.expires_at > statement_timestamp())
      ),
      'staffAssignments', (
        select count(*) from public.pachanga_competition_staff_assignments where status = 'active'
      ),
      'events', (select count(*) from private.pachanga_competition_events),
      'receipts', (select count(*) from private.pachanga_competition_operation_receipts)
    ),
    'bindingHealth', private.pachanga_canonical_match_health_v1(),
    'total', (select count(*) from public.pachanga_competitions),
    'items', coalesce((
      with edition_counts as (
        select editions.competition_id, count(*) as amount
        from public.pachanga_competition_editions editions group by editions.competition_id
      ), rule_counts as (
        select rule_sets.competition_id, count(revisions.id) as amount,
          max(revisions.version) as latest_version
        from public.pachanga_competition_rule_sets rule_sets
        left join public.pachanga_competition_rule_revisions revisions
          on revisions.rule_set_id = rule_sets.id
        group by rule_sets.competition_id
      ), staff_counts as (
        select assignments.competition_id, count(*) as amount
        from public.pachanga_competition_staff_assignments assignments
        where assignments.status = 'active'
        group by assignments.competition_id
      ), context_counts as (
        select contexts.competition_id, count(*) as amount
        from public.pachanga_competition_match_contexts contexts
        where contexts.status = 'lab_bound'
        group by contexts.competition_id
      ), selected as (
        select competitions.*, groups.name as organizer_name,
          coalesce(edition_counts.amount, 0) as edition_count,
          coalesce(rule_counts.amount, 0) as rule_revision_count,
          rule_counts.latest_version,
          coalesce(staff_counts.amount, 0) as staff_count,
          coalesce(context_counts.amount, 0) as context_count
        from public.pachanga_competitions competitions
        join public.pachanga_groups groups on groups.id = competitions.organizer_group_id
        left join edition_counts on edition_counts.competition_id = competitions.id
        left join rule_counts on rule_counts.competition_id = competitions.id
        left join staff_counts on staff_counts.competition_id = competitions.id
        left join context_counts on context_counts.competition_id = competitions.id
        order by competitions.updated_at desc, competitions.id
        offset bounded_offset limit bounded_size
      )
      select jsonb_agg(jsonb_build_object(
        'id', selected.id,
        'name', selected.name,
        'slug', selected.slug,
        'type', selected.competition_type,
        'status', selected.status,
        'visibility', selected.visibility,
        'organizerGroupId', selected.organizer_group_id,
        'organizerName', selected.organizer_name,
        'revision', selected.revision,
        'serverSequence', selected.server_sequence,
        'editionCount', selected.edition_count,
        'ruleRevisionCount', selected.rule_revision_count,
        'latestRuleVersion', selected.latest_version,
        'staffCount', selected.staff_count,
        'contextCount', selected.context_count,
        'updatedAt', selected.updated_at
      ) order by selected.updated_at desc, selected.id)
      from selected
    ), '[]'::jsonb),
    'entitlements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', grants.id,
        'organizerGroupId', grants.organizer_group_id,
        'organizerName', groups.name,
        'capability', grants.capability,
        'source', grants.grant_source,
        'status', case
          when grants.status = 'revoked' then 'revoked'
          when grants.expires_at is not null and grants.expires_at <= statement_timestamp() then 'expired'
          when grants.valid_from > statement_timestamp() then 'scheduled'
          else 'active'
        end,
        'organizerRevision', states.revision,
        'revision', grants.revision,
        'validFrom', grants.valid_from,
        'expiresAt', grants.expires_at,
        'updatedAt', grants.updated_at
      ) order by grants.server_sequence desc, grants.id desc)
      from public.pachanga_competition_entitlement_grants grants
      join public.pachanga_groups groups on groups.id = grants.organizer_group_id
      join public.pachanga_competition_organizer_states states
        on states.organizer_group_id = grants.organizer_group_id
    ), '[]'::jsonb),
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', reviews.id,
        'leftSourceKind', reviews.left_source_kind,
        'leftSourceGroupId', reviews.left_source_group_id,
        'leftSourceId', reviews.left_source_id,
        'rightSourceKind', reviews.right_source_kind,
        'rightSourceGroupId', reviews.right_source_group_id,
        'rightSourceId', reviews.right_source_id,
        'reasonCode', reviews.reason_code,
        'status', reviews.review_status,
        'revision', reviews.revision,
        'serverSequence', reviews.server_sequence,
        'createdAt', reviews.created_at
      ) order by reviews.server_sequence desc, reviews.id desc)
      from (
        select * from public.pachanga_canonical_match_binding_reviews
        order by server_sequence desc, id desc limit 100
      ) reviews
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', events.id,
        'operationId', events.operation_id,
        'aggregateType', events.aggregate_type,
        'aggregateId', events.aggregate_id,
        'competitionId', events.competition_id,
        'action', events.action,
        'revision', events.aggregate_revision,
        'serverSequence', events.server_sequence,
        'reasonCode', events.reason_code,
        'confirmedAt', events.confirmed_at
      ) order by events.server_sequence desc, events.id desc)
      from (
        select * from private.pachanga_competition_events
        order by server_sequence desc, id desc limit 100
      ) events
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_competition_foundation_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_competition_foundation_v1(integer, integer)
  to authenticated, service_role;

select private.pachanga_refresh_canonical_match_health_v1();
