-- Pachangas IQ Competition Foundation R1: organizer, rules and structure.
-- Product flags default OFF. No League/Tournament engine is activated here.

create table if not exists private.pachanga_competition_foundation_settings (
  singleton boolean primary key default true check (singleton),
  foundation_enabled boolean not null default false,
  creation_enabled boolean not null default false,
  context_binding_enabled boolean not null default false,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1),
  check (not creation_enabled or foundation_enabled),
  check (not context_binding_enabled or foundation_enabled)
);

insert into private.pachanga_competition_foundation_settings(singleton)
values (true)
on conflict (singleton) do nothing;

create table if not exists private.pachanga_competition_operation_receipts (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null default 'authenticated',
  action text not null,
  aggregate_type text not null,
  aggregate_id text not null,
  request_hash text not null,
  confirmed_revision bigint not null,
  server_sequence bigint not null,
  client_metadata jsonb not null default '{}'::jsonb,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'service_authority')),
  check (confirmed_revision >= 0),
  check (length(request_hash) = 64)
);

create table if not exists private.pachanga_competition_events (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  actor_id uuid references auth.users(id) on delete set null,
  actor_kind text not null default 'authenticated',
  aggregate_type text not null,
  aggregate_id text not null,
  competition_id uuid,
  action text not null,
  aggregate_revision bigint not null,
  server_sequence bigint not null unique,
  reason_code text not null,
  event_payload jsonb not null default '{}'::jsonb,
  confirmed_at timestamptz not null default clock_timestamp(),
  check (actor_kind in ('authenticated', 'service_authority')),
  check (aggregate_revision >= 0)
);

create table if not exists public.pachanga_competition_organizer_states (
  organizer_group_id uuid primary key references public.pachanga_groups(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (revision >= 1)
);

create table if not exists public.pachanga_competition_entitlement_grants (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null default 'TEAM',
  organizer_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  capability text not null,
  grant_source text not null,
  status text not null default 'active',
  valid_from timestamptz not null default clock_timestamp(),
  expires_at timestamptz,
  reason text not null,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  granted_by uuid references auth.users(id) on delete set null,
  revoked_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind = 'TEAM'),
  check (capability in (
    'competition_create', 'competition_manage', 'competition_staff', 'competition_rules',
    'competition_referees', 'competition_discipline'
  )),
  check (grant_source in ('subscription', 'partnership', 'promotion', 'platform_grant')),
  check (status in ('active', 'revoked')),
  check (expires_at is null or expires_at > valid_from),
  check (revision >= 1),
  check (length(trim(reason)) between 3 and 1200),
  check (
    (status = 'revoked' and revoked_at is not null)
    or (status = 'active' and revoked_at is null and revoked_by is null)
  )
);

create unique index if not exists pachanga_competition_entitlement_active_idx
  on public.pachanga_competition_entitlement_grants(organizer_group_id, capability)
  where status = 'active';

create index if not exists pachanga_competition_entitlement_expiry_idx
  on public.pachanga_competition_entitlement_grants(expires_at, organizer_group_id)
  where status = 'active' and expires_at is not null;

create table if not exists public.pachanga_competitions (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null default 'TEAM',
  organizer_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  name text not null,
  slug text not null,
  competition_type text not null,
  visibility text not null default 'private',
  status text not null default 'draft',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind = 'TEAM'),
  check (competition_type in ('LEAGUE', 'TOURNAMENT')),
  check (visibility in ('private', 'internal')),
  check (status in ('draft', 'cancelled')),
  check (revision >= 1),
  check (length(trim(name)) between 3 and 120),
  check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' and length(slug) between 3 and 80),
  unique (organizer_group_id, slug)
);

create table if not exists public.pachanga_competition_rule_sets (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  name text not null,
  status text not null default 'draft',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('draft', 'active', 'archived')),
  check (revision >= 1),
  check (length(trim(name)) between 3 and 120),
  unique (competition_id, name)
);

create table if not exists public.pachanga_competition_rule_revisions (
  id uuid primary key default gen_random_uuid(),
  rule_set_id uuid not null references public.pachanga_competition_rule_sets(id) on delete restrict,
  version integer not null,
  schema_version text not null,
  rule_document jsonb not null,
  checksum text not null,
  effective_from timestamptz,
  effective_scope text not null default 'future_only',
  status text not null default 'draft',
  revision bigint not null default 1,
  supersedes_revision_id uuid references public.pachanga_competition_rule_revisions(id) on delete restrict,
  reason text not null,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (schema_version = 'competition_rules.v1'),
  check (jsonb_typeof(rule_document) = 'object'),
  check (length(checksum) = 64),
  check (effective_scope in ('future_only', 'future_stage')),
  check (status in ('draft', 'validated', 'published', 'frozen', 'superseded', 'withdrawn')),
  check (revision >= 1),
  check (length(trim(reason)) between 3 and 1200),
  unique (rule_set_id, version)
);

create unique index if not exists pachanga_competition_rule_published_idx
  on public.pachanga_competition_rule_revisions(rule_set_id)
  where status = 'published';

create table if not exists public.pachanga_competition_editions (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  name text not null,
  season_label text not null,
  starts_at date,
  ends_at date,
  status text not null default 'draft',
  rule_revision_id uuid references public.pachanga_competition_rule_revisions(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in (
    'draft', 'registration_open', 'registration_closed', 'scheduled', 'active',
    'completed', 'archived', 'cancelled', 'suspended'
  )),
  check (status in ('draft', 'cancelled')),
  check (ends_at is null or starts_at is null or ends_at >= starts_at),
  check (revision >= 1),
  check (length(trim(name)) between 3 and 120),
  check (length(trim(season_label)) between 1 and 80),
  unique (competition_id, season_label)
);

create table if not exists public.pachanga_competition_stages (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  name text not null,
  stage_type text not null,
  stage_order integer not null,
  optional_stage boolean not null default false,
  status text not null default 'draft',
  rule_revision_id uuid references public.pachanga_competition_rule_revisions(id) on delete restrict,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (stage_type in ('SPLIT', 'LEAGUE_STAGE', 'GROUP_STAGE', 'KNOCKOUT', 'PLAYOFF', 'FINALS', 'CUSTOM')),
  check (status in ('draft', 'cancelled')),
  check (stage_order >= 0),
  check (revision >= 1),
  check (length(trim(name)) between 1 and 120),
  unique (edition_id, stage_order),
  unique (edition_id, name)
);

create table if not exists public.pachanga_competition_divisions (
  id uuid primary key default gen_random_uuid(),
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  name text not null,
  division_order integer not null,
  level_label text,
  status text not null default 'draft',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('draft', 'cancelled')),
  check (division_order >= 0),
  check (revision >= 1),
  check (length(trim(name)) between 1 and 120),
  unique (stage_id, division_order),
  unique (stage_id, name)
);

create table if not exists public.pachanga_competition_groups (
  id uuid primary key default gen_random_uuid(),
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  name text not null,
  group_order integer not null,
  status text not null default 'draft',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('draft', 'cancelled')),
  check (group_order >= 0),
  check (revision >= 1),
  check (length(trim(name)) between 1 and 120),
  unique (stage_id, group_order),
  unique (stage_id, name)
);

create table if not exists public.pachanga_competition_stage_edges (
  id uuid primary key default gen_random_uuid(),
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  from_stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  to_stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  edge_order integer not null,
  transition_kind text not null default 'structural',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (from_stage_id <> to_stage_id),
  check (edge_order >= 0),
  check (transition_kind = 'structural'),
  check (revision >= 1),
  unique (edition_id, from_stage_id, to_stage_id),
  unique (edition_id, from_stage_id, edge_order)
);

create table if not exists public.pachanga_competition_staff_assignments (
  id uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  staff_role text not null,
  status text not null default 'active',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  assigned_by uuid not null references auth.users(id) on delete restrict,
  revoked_by uuid references auth.users(id) on delete set null,
  assigned_at timestamptz not null default clock_timestamp(),
  revoked_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  check (staff_role in ('competition_owner', 'competition_director', 'competition_admin', 'rules_manager', 'viewer')),
  check (status in ('active', 'revoked')),
  check (revision >= 1),
  check (
    (status = 'revoked' and revoked_at is not null)
    or (status = 'active' and revoked_at is null and revoked_by is null)
  )
);

create unique index if not exists pachanga_competition_staff_active_idx
  on public.pachanga_competition_staff_assignments(competition_id, user_id)
  where status = 'active';

create table if not exists public.pachanga_competition_match_contexts (
  id uuid primary key default gen_random_uuid(),
  canonical_match_id uuid not null references public.pachanga_canonical_matches(id) on delete restrict,
  competition_id uuid not null references public.pachanga_competitions(id) on delete restrict,
  edition_id uuid not null references public.pachanga_competition_editions(id) on delete restrict,
  stage_id uuid not null references public.pachanga_competition_stages(id) on delete restrict,
  division_id uuid references public.pachanga_competition_divisions(id) on delete restrict,
  competition_group_id uuid references public.pachanga_competition_groups(id) on delete restrict,
  rule_revision_id uuid not null references public.pachanga_competition_rule_revisions(id) on delete restrict,
  status text not null default 'lab_bound',
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('private.pachanga_competition_sequence'),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (status in ('lab_bound', 'retired')),
  check (revision >= 1)
);

create unique index if not exists pachanga_competition_context_active_match_idx
  on public.pachanga_competition_match_contexts(canonical_match_id)
  where status = 'lab_bound';

create table if not exists public.pachanga_competition_invalidations (
  server_sequence bigint primary key,
  competition_id uuid references public.pachanga_competitions(id) on delete cascade,
  organizer_group_id uuid not null references public.pachanga_groups(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  revision bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  check (revision >= 0)
);

create index if not exists pachanga_competitions_organizer_idx
  on public.pachanga_competitions(organizer_group_id, status, updated_at desc, id);
create index if not exists pachanga_competition_editions_competition_idx
  on public.pachanga_competition_editions(competition_id, created_at, id);
create index if not exists pachanga_competition_rule_sets_competition_idx
  on public.pachanga_competition_rule_sets(competition_id, created_at, id);
create index if not exists pachanga_competition_rule_revisions_set_idx
  on public.pachanga_competition_rule_revisions(rule_set_id, version, id);
create index if not exists pachanga_competition_stages_edition_idx
  on public.pachanga_competition_stages(edition_id, stage_order, id);
create index if not exists pachanga_competition_divisions_stage_idx
  on public.pachanga_competition_divisions(stage_id, division_order, id);
create index if not exists pachanga_competition_groups_stage_idx
  on public.pachanga_competition_groups(stage_id, group_order, id);
create index if not exists pachanga_competition_staff_competition_idx
  on public.pachanga_competition_staff_assignments(competition_id, status, user_id);
create index if not exists pachanga_competition_context_competition_idx
  on public.pachanga_competition_match_contexts(competition_id, edition_id, stage_id);
create index if not exists pachanga_competition_invalidations_group_idx
  on public.pachanga_competition_invalidations(organizer_group_id, server_sequence desc);

alter table private.pachanga_competition_events
  add constraint pachanga_competition_events_competition_fk
  foreign key (competition_id) references public.pachanga_competitions(id) on delete set null;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'pachanga_competition_organizer_states',
    'pachanga_competition_entitlement_grants',
    'pachanga_competitions',
    'pachanga_competition_rule_sets',
    'pachanga_competition_rule_revisions',
    'pachanga_competition_editions',
    'pachanga_competition_stages',
    'pachanga_competition_divisions',
    'pachanga_competition_groups',
    'pachanga_competition_stage_edges',
    'pachanga_competition_staff_assignments',
    'pachanga_competition_match_contexts'
  ] loop
    execute format('drop trigger if exists touch_%I_v1 on public.%I', target_table, target_table);
    execute format(
      'create trigger touch_%I_v1 before update on public.%I for each row execute function private.pachanga_competition_touch_updated_at_v1()',
      target_table,
      target_table
    );
  end loop;
end;
$$;

create or replace function private.pachanga_competition_rule_checksum_v1(
  target_schema_version text,
  target_document jsonb
)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select encode(
    extensions.digest(
      convert_to(target_schema_version || ':' || target_document::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
$$;

revoke all on function private.pachanga_competition_rule_checksum_v1(text, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_validate_ranges_v1(
  target_value jsonb,
  target_path text default '$'
)
returns void
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  item record;
  minimum_value jsonb;
  maximum_value jsonb;
  minimum_key text;
  maximum_key text;
begin
  if jsonb_typeof(target_value) = 'object' then
    for minimum_key, maximum_key in
      select * from (values
        ('min', 'max'),
        ('minimum', 'maximum'),
        ('minimumPlayers', 'maximumPlayers'),
        ('minimumSize', 'maximumSize')
      ) as pairs(minimum_key, maximum_key)
    loop
      if target_value ? minimum_key and target_value ? maximum_key then
        minimum_value := target_value -> minimum_key;
        maximum_value := target_value -> maximum_key;
        if jsonb_typeof(minimum_value) <> 'number' or jsonb_typeof(maximum_value) <> 'number' then
          raise exception 'RULE_DOCUMENT_INVALID: range at % must be numeric', target_path
            using errcode = '22023';
        end if;
        if (minimum_value #>> '{}')::numeric > (maximum_value #>> '{}')::numeric then
          raise exception 'RULE_DOCUMENT_INVALID: minimum exceeds maximum at %', target_path
            using errcode = '22023';
        end if;
      end if;
    end loop;
    for item in select key, value from jsonb_each(target_value) loop
      perform private.pachanga_competition_validate_ranges_v1(
        item.value,
        target_path || '.' || item.key
      );
    end loop;
  elsif jsonb_typeof(target_value) = 'array' then
    for item in select (ordinality - 1)::text as key, value
      from jsonb_array_elements(target_value) with ordinality
    loop
      perform private.pachanga_competition_validate_ranges_v1(
        item.value,
        target_path || '[' || item.key || ']'
      );
    end loop;
  end if;
end;
$$;

revoke all on function private.pachanga_competition_validate_ranges_v1(jsonb, text)
  from public, anon, authenticated;

create or replace function private.pachanga_validate_competition_rule_document_v1(
  target_schema_version text,
  target_document jsonb
)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare
  section_name text;
  graph jsonb;
  graph_nodes jsonb;
  graph_edges jsonb;
  root_id text;
  hard_policy jsonb;
  preference_policy jsonb;
begin
  if target_schema_version <> 'competition_rules.v1' then
    raise exception 'RULE_SCHEMA_UNSUPPORTED' using errcode = '22023';
  end if;
  if jsonb_typeof(target_document) <> 'object' then
    raise exception 'RULE_DOCUMENT_INVALID: root must be an object' using errcode = '22023';
  end if;

  foreach section_name in array array[
    'format', 'registration', 'structure', 'results', 'operations',
    'discipline', 'governance', 'publication', 'futureCapabilities'
  ] loop
    if jsonb_typeof(target_document -> section_name) <> 'object' then
      raise exception 'RULE_DOCUMENT_INVALID: section % must be an object', section_name
        using errcode = '22023';
    end if;
  end loop;

  if target_document #> '{results,tieBreakCriteria}' is not null
     and jsonb_typeof(target_document #> '{results,tieBreakCriteria}') <> 'array' then
    raise exception 'RULE_DOCUMENT_INVALID: tieBreakCriteria must be an array'
      using errcode = '22023';
  end if;
  if target_document #> '{results,scoringPolicy}' is not null
     and jsonb_typeof(target_document #> '{results,scoringPolicy}') <> 'object' then
    raise exception 'RULE_DOCUMENT_INVALID: scoringPolicy must be an object'
      using errcode = '22023';
  end if;

  graph := target_document #> '{structure,stageGraph}';
  if jsonb_typeof(graph) <> 'object' then
    raise exception 'RULE_DOCUMENT_INVALID: structure.stageGraph must be an object'
      using errcode = '22023';
  end if;
  graph_nodes := graph -> 'nodes';
  graph_edges := graph -> 'edges';
  if jsonb_typeof(graph_nodes) <> 'array' or jsonb_typeof(graph_edges) <> 'array' then
    raise exception 'RULE_DOCUMENT_INVALID: stageGraph nodes and edges must be arrays'
      using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements(graph_nodes) node
    where jsonb_typeof(node) <> 'object'
       or nullif(trim(node ->> 'id'), '') is null
       or (node ? 'optional' and jsonb_typeof(node -> 'optional') <> 'boolean')
       or (node ? 'root' and jsonb_typeof(node -> 'root') <> 'boolean')
  ) then
    raise exception 'RULE_DOCUMENT_INVALID: every stage node needs a typed id'
      using errcode = '22023';
  end if;
  if exists (
    select node ->> 'id'
    from jsonb_array_elements(graph_nodes) node
    group by node ->> 'id'
    having count(*) > 1
  ) then
    raise exception 'RULE_DOCUMENT_INVALID: duplicate stage node'
      using errcode = '22023';
  end if;
  if jsonb_array_length(graph_nodes) > 0 then
    if (select count(*) from jsonb_array_elements(graph_nodes) node
        where coalesce((node ->> 'root')::boolean, false)) <> 1 then
      raise exception 'RULE_DOCUMENT_INVALID: stageGraph requires exactly one root'
        using errcode = '22023';
    end if;
    select node ->> 'id' into root_id
    from jsonb_array_elements(graph_nodes) node
    where coalesce((node ->> 'root')::boolean, false);
  end if;
  if exists (
    select 1 from jsonb_array_elements(graph_edges) edge
    where jsonb_typeof(edge) <> 'object'
       or nullif(trim(edge ->> 'from'), '') is null
       or nullif(trim(edge ->> 'to'), '') is null
       or edge ->> 'from' = edge ->> 'to'
       or not coalesce(edge ->> 'order', '') ~ '^[0-9]+$'
       or not exists (select 1 from jsonb_array_elements(graph_nodes) node where node ->> 'id' = edge ->> 'from')
       or not exists (select 1 from jsonb_array_elements(graph_nodes) node where node ->> 'id' = edge ->> 'to')
  ) then
    raise exception 'RULE_DOCUMENT_INVALID: stageGraph contains an invalid edge'
      using errcode = '22023';
  end if;
  if exists (
    select edge ->> 'from', (edge ->> 'order')::integer
    from jsonb_array_elements(graph_edges) edge
    group by edge ->> 'from', (edge ->> 'order')::integer
    having count(*) > 1
  ) then
    raise exception 'RULE_DOCUMENT_INVALID: stage edge order must be deterministic'
      using errcode = '22023';
  end if;
  if exists (
    with recursive edges as (
      select edge ->> 'from' as source_id, edge ->> 'to' as target_id
      from jsonb_array_elements(graph_edges) edge
    ), reach(source_id, target_id) as (
      select source_id, target_id from edges
      union
      select reach.source_id, edges.target_id
      from reach join edges on edges.source_id = reach.target_id
    )
    select 1 from reach where source_id = target_id
  ) then
    raise exception 'RULE_DOCUMENT_INVALID: undeclared stage cycles are not supported in R1'
      using errcode = '22023';
  end if;
  if root_id is not null and exists (
    with recursive edges as (
      select edge ->> 'from' as source_id, edge ->> 'to' as target_id
      from jsonb_array_elements(graph_edges) edge
    ), reachable(node_id) as (
      select root_id
      union
      select edges.target_id
      from reachable join edges on edges.source_id = reachable.node_id
    )
    select 1
    from jsonb_array_elements(graph_nodes) node
    where not coalesce((node ->> 'optional')::boolean, false)
      and not exists (select 1 from reachable where node_id = node ->> 'id')
  ) then
    raise exception 'RULE_DOCUMENT_INVALID: required stage is unreachable'
      using errcode = '22023';
  end if;

  hard_policy := target_document #> '{operations,hardAvailabilityPolicy}';
  preference_policy := target_document #> '{operations,schedulePreferencePolicy}';
  if hard_policy is not null and jsonb_typeof(hard_policy) <> 'object' then
    raise exception 'RULE_DOCUMENT_INVALID: hardAvailabilityPolicy must be an object'
      using errcode = '22023';
  end if;
  if preference_policy is not null and jsonb_typeof(preference_policy) <> 'object' then
    raise exception 'RULE_DOCUMENT_INVALID: schedulePreferencePolicy must be an object'
      using errcode = '22023';
  end if;
  if hard_policy is not null and preference_policy is not null
     and hard_policy <> '{}'::jsonb and hard_policy = preference_policy then
    raise exception 'RULE_DOCUMENT_INVALID: hard constraint cannot equal a preference'
      using errcode = '22023';
  end if;
  if target_document #>> '{identity,sourcePresetId}' is not null
     and target_document #>> '{identity,sourcePresetVersion}' is null then
    raise exception 'RULE_DOCUMENT_INVALID: mutable live preset references are forbidden'
      using errcode = '22023';
  end if;

  perform private.pachanga_competition_validate_ranges_v1(target_document, '$');
  return private.pachanga_competition_rule_checksum_v1(target_schema_version, target_document);
end;
$$;

revoke all on function private.pachanga_validate_competition_rule_document_v1(text, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_is_service_authority_v1()
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce((select auth.role()) = 'service_role', false);
$$;

revoke all on function private.pachanga_competition_is_service_authority_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_competition_active_entitlement_v1(
  target_group_id uuid,
  target_capability text
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.pachanga_competition_entitlement_grants grants
    where grants.organizer_group_id = target_group_id
      and grants.capability = target_capability
      and grants.status = 'active'
      and grants.valid_from <= statement_timestamp()
      and (grants.expires_at is null or grants.expires_at > statement_timestamp())
  );
$$;

revoke all on function private.pachanga_competition_active_entitlement_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_entitlement_snapshot_v1(
  target_group_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'organizerKind', 'TEAM',
    'organizerGroupId', target_group_id,
    'organizerRevision', coalesce((
      select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_group_id = target_group_id
    ), 0),
    'grants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', grants.id,
        'capability', grants.capability,
        'source', grants.grant_source,
        'status', case
          when grants.status = 'revoked' then 'revoked'
          when grants.expires_at is not null and grants.expires_at <= statement_timestamp() then 'expired'
          when grants.valid_from > statement_timestamp() then 'scheduled'
          else 'active'
        end,
        'validFrom', grants.valid_from,
        'expiresAt', grants.expires_at,
        'revision', grants.revision,
        'updatedAt', grants.updated_at
      ) order by grants.capability, grants.created_at, grants.id)
      from public.pachanga_competition_entitlement_grants grants
      where grants.organizer_group_id = target_group_id
    ), '[]'::jsonb),
    'canCreate', private.pachanga_competition_active_entitlement_v1(target_group_id, 'competition_create')
  );
$$;

revoke all on function private.pachanga_competition_entitlement_snapshot_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_actor_role_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  organizer_group_id uuid;
  assigned_role text;
  platform_role text;
begin
  if target_actor_id is null then
    if private.pachanga_competition_is_service_authority_v1() then return 'service_authority'; end if;
    return null;
  end if;
  platform_role := private.pachanga_platform_role_for_user_v1(target_actor_id);
  if platform_role in ('platform_owner', 'platform_admin') then return platform_role; end if;

  select competitions.organizer_group_id into organizer_group_id
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if organizer_group_id is null then return null; end if;
  if exists (
    select 1 from public.pachanga_groups groups
    where groups.id = organizer_group_id and groups.owner_id = target_actor_id
  ) then
    return 'competition_owner';
  end if;
  select assignments.staff_role into assigned_role
  from public.pachanga_competition_staff_assignments assignments
  where assignments.competition_id = target_competition_id
    and assignments.user_id = target_actor_id
    and assignments.status = 'active'
  order by assignments.server_sequence desc, assignments.id desc
  limit 1;
  return assigned_role;
end;
$$;

revoke all on function private.pachanga_competition_actor_role_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_can_v1(
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
declare
  actor_role text := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
begin
  if actor_role in ('service_authority', 'platform_owner', 'platform_admin', 'competition_owner') then
    return true;
  end if;
  return case actor_role
    when 'competition_director' then target_capability in ('read', 'manage', 'staff', 'rules')
    when 'competition_admin' then target_capability in ('read', 'manage')
    when 'rules_manager' then target_capability in ('read', 'rules')
    when 'viewer' then target_capability = 'read'
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_require_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_role text := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
begin
  if not private.pachanga_competition_can_v1(target_competition_id, target_actor_id, target_capability) then
    raise exception 'COMPETITION_ACCESS_DENIED' using errcode = '42501';
  end if;
  return actor_role;
end;
$$;

revoke all on function private.pachanga_competition_require_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_assert_flags_v1(
  require_creation boolean default false,
  require_context boolean default false
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings
  where singleton;
  if not settings.foundation_enabled then
    raise exception 'COMPETITION_FOUNDATION_DISABLED' using errcode = '42501';
  end if;
  if require_creation and not settings.creation_enabled then
    raise exception 'COMPETITION_CREATION_DISABLED' using errcode = '42501';
  end if;
  if require_context and not settings.context_binding_enabled then
    raise exception 'COMPETITION_CONTEXT_BINDING_DISABLED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_competition_assert_flags_v1(boolean, boolean)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_request_hash_v1(
  target_action text,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'action', target_action,
    'aggregateId', target_aggregate_id,
    'expectedRevision', target_expected_revision,
    'payload', target_payload
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

revoke all on function private.pachanga_competition_request_hash_v1(text, uuid, bigint, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_client_metadata_v1(
  target_metadata jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', nullif(left(coalesce(target_metadata ->> 'clientVersion', ''), 80), ''),
    'serviceWorkerVersion', nullif(left(coalesce(target_metadata ->> 'serviceWorkerVersion', ''), 80), ''),
    'installedMode', case
      when target_metadata ->> 'installedMode' in ('browser', 'standalone', 'fullscreen')
      then target_metadata ->> 'installedMode'
      else null
    end,
    'sessionId', nullif(left(coalesce(target_metadata ->> 'sessionId', ''), 120), ''),
    'surface', nullif(left(coalesce(target_metadata ->> 'surface', ''), 120), '')
  ));
$$;

revoke all on function private.pachanga_competition_client_metadata_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  saved private.pachanga_competition_operation_receipts%rowtype;
begin
  select * into saved
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if saved.actor_id is distinct from target_actor_id
     or saved.actor_kind <> target_actor_kind
     or saved.action <> target_action
     or saved.aggregate_id <> target_aggregate_id::text
     or saved.request_hash <> target_request_hash then
    raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
  end if;
  return saved.response;
end;
$$;

revoke all on function private.pachanga_competition_replay_v1(uuid, uuid, text, text, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_snapshot_v1(
  target_competition_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'competition', jsonb_build_object(
      'id', competitions.id,
      'organizerKind', competitions.organizer_kind,
      'organizerGroupId', competitions.organizer_group_id,
      'organizerName', groups.name,
      'name', competitions.name,
      'slug', competitions.slug,
      'type', competitions.competition_type,
      'visibility', competitions.visibility,
      'status', competitions.status,
      'revision', competitions.revision,
      'serverSequence', competitions.server_sequence,
      'createdAt', competitions.created_at,
      'updatedAt', competitions.updated_at
    ),
    'entitlement', private.pachanga_competition_entitlement_snapshot_v1(competitions.organizer_group_id),
    'editions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', editions.id,
        'name', editions.name,
        'seasonLabel', editions.season_label,
        'startsAt', editions.starts_at,
        'endsAt', editions.ends_at,
        'status', editions.status,
        'ruleRevisionId', editions.rule_revision_id,
        'revision', editions.revision,
        'serverSequence', editions.server_sequence,
        'updatedAt', editions.updated_at
      ) order by editions.created_at, editions.id)
      from public.pachanga_competition_editions editions
      where editions.competition_id = competitions.id
    ), '[]'::jsonb),
    'ruleSets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rule_sets.id,
        'name', rule_sets.name,
        'status', rule_sets.status,
        'revision', rule_sets.revision,
        'serverSequence', rule_sets.server_sequence,
        'revisions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', revisions.id,
            'version', revisions.version,
            'schemaVersion', revisions.schema_version,
            'checksum', revisions.checksum,
            'effectiveFrom', revisions.effective_from,
            'effectiveScope', revisions.effective_scope,
            'status', revisions.status,
            'revision', revisions.revision,
            'supersedesRevisionId', revisions.supersedes_revision_id,
            'reason', revisions.reason,
            'ruleDocument', revisions.rule_document,
            'serverSequence', revisions.server_sequence,
            'createdAt', revisions.created_at,
            'updatedAt', revisions.updated_at
          ) order by revisions.version, revisions.id)
          from public.pachanga_competition_rule_revisions revisions
          where revisions.rule_set_id = rule_sets.id
        ), '[]'::jsonb)
      ) order by rule_sets.created_at, rule_sets.id)
      from public.pachanga_competition_rule_sets rule_sets
      where rule_sets.competition_id = competitions.id
    ), '[]'::jsonb),
    'stages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', stages.id,
        'editionId', stages.edition_id,
        'name', stages.name,
        'type', stages.stage_type,
        'order', stages.stage_order,
        'optional', stages.optional_stage,
        'status', stages.status,
        'ruleRevisionId', stages.rule_revision_id,
        'revision', stages.revision,
        'serverSequence', stages.server_sequence,
        'divisions', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', divisions.id,
            'name', divisions.name,
            'order', divisions.division_order,
            'levelLabel', divisions.level_label,
            'status', divisions.status,
            'revision', divisions.revision,
            'serverSequence', divisions.server_sequence
          ) order by divisions.division_order, divisions.id)
          from public.pachanga_competition_divisions divisions
          where divisions.stage_id = stages.id
        ), '[]'::jsonb),
        'groups', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', competition_groups.id,
            'divisionId', competition_groups.division_id,
            'name', competition_groups.name,
            'order', competition_groups.group_order,
            'status', competition_groups.status,
            'revision', competition_groups.revision,
            'serverSequence', competition_groups.server_sequence
          ) order by competition_groups.group_order, competition_groups.id)
          from public.pachanga_competition_groups competition_groups
          where competition_groups.stage_id = stages.id
        ), '[]'::jsonb)
      ) order by stages.stage_order, stages.id)
      from public.pachanga_competition_stages stages
      join public.pachanga_competition_editions stage_editions on stage_editions.id = stages.edition_id
      where stage_editions.competition_id = competitions.id
    ), '[]'::jsonb),
    'stageEdges', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', edges.id,
        'editionId', edges.edition_id,
        'fromStageId', edges.from_stage_id,
        'toStageId', edges.to_stage_id,
        'order', edges.edge_order,
        'transitionKind', edges.transition_kind,
        'revision', edges.revision,
        'serverSequence', edges.server_sequence
      ) order by edges.edition_id, edges.from_stage_id, edges.edge_order, edges.id)
      from public.pachanga_competition_stage_edges edges
      join public.pachanga_competition_editions edge_editions on edge_editions.id = edges.edition_id
      where edge_editions.competition_id = competitions.id
    ), '[]'::jsonb),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', assignments.id,
        'userId', assignments.user_id,
        'role', assignments.staff_role,
        'status', assignments.status,
        'revision', assignments.revision,
        'serverSequence', assignments.server_sequence,
        'assignedAt', assignments.assigned_at,
        'revokedAt', assignments.revoked_at
      ) order by assignments.status, assignments.assigned_at, assignments.id)
      from public.pachanga_competition_staff_assignments assignments
      where assignments.competition_id = competitions.id
    ), '[]'::jsonb),
    'matchContexts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', contexts.id,
        'canonicalMatchId', contexts.canonical_match_id,
        'editionId', contexts.edition_id,
        'stageId', contexts.stage_id,
        'divisionId', contexts.division_id,
        'groupId', contexts.competition_group_id,
        'ruleRevisionId', contexts.rule_revision_id,
        'status', contexts.status,
        'revision', contexts.revision,
        'serverSequence', contexts.server_sequence
      ) order by contexts.server_sequence, contexts.id)
      from public.pachanga_competition_match_contexts contexts
      where contexts.competition_id = competitions.id
    ), '[]'::jsonb)
  )
  from public.pachanga_competitions competitions
  join public.pachanga_groups groups on groups.id = competitions.organizer_group_id
  where competitions.id = target_competition_id;
$$;

revoke all on function private.pachanga_competition_snapshot_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_organizer_group_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_reason_code text,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_confirmed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  response jsonb;
begin
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', case when target_organizer_group_id is null then '[]'::jsonb else jsonb_build_array(
      jsonb_build_object(
        'entityType', target_aggregate_type,
        'entityId', target_aggregate_id,
        'revision', target_confirmed_revision
      )
    ) end
  );

  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_aggregate_type,
    target_aggregate_id::text, target_competition_id, target_action,
    target_confirmed_revision, target_server_sequence, target_reason_code,
    coalesce(target_event_payload, '{}'::jsonb), target_confirmed_at
  );

  if target_organizer_group_id is not null then
    insert into public.pachanga_competition_invalidations(
      server_sequence, competition_id, organizer_group_id, entity_type,
      entity_id, revision, created_at
    ) values (
      target_server_sequence, target_competition_id, target_organizer_group_id,
      target_aggregate_type, target_aggregate_id::text,
      target_confirmed_revision, target_confirmed_at
    );
  end if;

  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence, target_client_metadata, response, target_confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_competition_store_command_v1(
  uuid, uuid, text, text, text, uuid, uuid, uuid, bigint, bigint, text, text, jsonb, jsonb, jsonb, timestamptz
) from public, anon, authenticated;

create or replace function public.get_pachanga_competition_foundation_snapshot_v1(
  target_competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  snapshot jsonb;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  perform private.pachanga_competition_require_v1(target_competition_id, actor_id, 'read');
  snapshot := private.pachanga_competition_snapshot_v1(target_competition_id);
  if snapshot is null then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  return snapshot;
end;
$$;

revoke all on function public.get_pachanga_competition_foundation_snapshot_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_competition_foundation_snapshot_v1(uuid)
  to authenticated, service_role;

create or replace function public.get_my_pachanga_competition_foundation_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  settings private.pachanga_competition_foundation_settings%rowtype;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  return jsonb_build_object(
    'flags', jsonb_build_object(
      'foundationEnabled', settings.foundation_enabled,
      'creationEnabled', settings.creation_enabled,
      'contextBindingEnabled', settings.context_binding_enabled,
      'revision', settings.revision,
      'updatedAt', settings.updated_at
    ),
    'organizers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'groupId', groups.id,
        'name', groups.name,
        'owner', groups.owner_id = actor_id,
        'entitlement', private.pachanga_competition_entitlement_snapshot_v1(groups.id)
      ) order by groups.name, groups.id)
      from public.pachanga_groups groups
      where groups.owner_id = actor_id
        or exists (
          select 1
          from public.pachanga_competitions competitions
          join public.pachanga_competition_staff_assignments assignments
            on assignments.competition_id = competitions.id
          where competitions.organizer_group_id = groups.id
            and assignments.user_id = actor_id
            and assignments.status = 'active'
        )
    ), '[]'::jsonb),
    'competitions', coalesce((
      select jsonb_agg(private.pachanga_competition_snapshot_v1(competitions.id)
        order by competitions.updated_at desc, competitions.id)
      from public.pachanga_competitions competitions
      where private.pachanga_competition_can_v1(competitions.id, actor_id, 'read')
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_my_pachanga_competition_foundation_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_pachanga_competition_foundation_v1()
  to authenticated, service_role;

create or replace function public.command_pachanga_competition_foundation_v1(
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
  created_id uuid;
  selected_user_id uuid;
  selected_rule_revision_id uuid;
  selected_division_id uuid;
  supersedes_id uuid;
  selected_name text;
  selected_slug text;
  selected_type text;
  selected_role text;
  selected_scope text;
  selected_checksum text;
  selected_document jsonb;
  next_version integer;
  selected_order integer;
  selected_from_stage_id uuid;
  selected_to_stage_id uuid;
  group_row public.pachanga_groups%rowtype;
  organizer_row public.pachanga_competition_organizer_states%rowtype;
  competition_row public.pachanga_competitions%rowtype;
  edition_row public.pachanga_competition_editions%rowtype;
  rule_set_row public.pachanga_competition_rule_sets%rowtype;
  rule_revision_row public.pachanga_competition_rule_revisions%rowtype;
  stage_row public.pachanga_competition_stages%rowtype;
  assignment_row public.pachanga_competition_staff_assignments%rowtype;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or nullif(trim(command_action), '') is null then
    raise exception 'INVALID_COMPETITION_COMMAND' using errcode = '22023';
  end if;
  if expected_revision < 0 then
    raise exception 'INVALID_EXPECTED_REVISION' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_COMPETITION_COMMAND_PAYLOAD' using errcode = '22023';
  end if;
  if actor_id is null and not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  actor_kind := case when actor_id is null then 'service_authority' else 'authenticated' end;
  sanitized_metadata := private.pachanga_competition_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb));
  request_hash := private.pachanga_competition_request_hash_v1(
    command_action, aggregate_id, expected_revision, coalesce(command_payload, '{}'::jsonb)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91401));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, command_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;

  if command_action in (
    'edition.registration_open', 'edition.registration_closed', 'edition.scheduled',
    'edition.active', 'edition.completed', 'edition.archived', 'edition.suspended'
  ) then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  perform private.pachanga_competition_assert_flags_v1(command_action = 'competition.create', false);
  sequence_value := nextval('private.pachanga_competition_sequence');
  reason_code := left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), command_action), 120);

  if command_action = 'competition.create' then
    select * into group_row
    from public.pachanga_groups groups
    where groups.id = aggregate_id
    for update;
    if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    if actor_id is null or group_row.owner_id <> actor_id then
      raise exception 'COMPETITION_OWNER_REQUIRED' using errcode = '42501';
    end if;
    if not private.pachanga_competition_active_entitlement_v1(aggregate_id, 'competition_create') then
      raise exception 'COMPETITION_ENTITLEMENT_REQUIRED' using errcode = '42501';
    end if;
    insert into public.pachanga_competition_organizer_states(organizer_group_id)
    values (aggregate_id)
    on conflict on constraint pachanga_competition_organizer_states_pkey do nothing;
    select * into organizer_row
    from public.pachanga_competition_organizer_states states
    where states.organizer_group_id = aggregate_id
    for update;
    if organizer_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;

    selected_name := trim(coalesce(command_payload ->> 'name', ''));
    selected_slug := lower(trim(coalesce(command_payload ->> 'slug', '')));
    selected_type := upper(trim(coalesce(command_payload ->> 'competitionType', '')));
    created_id := gen_random_uuid();
    insert into public.pachanga_competitions(
      id, organizer_group_id, name, slug, competition_type, visibility,
      server_sequence, created_by
    ) values (
      created_id, aggregate_id, selected_name, selected_slug, selected_type,
      coalesce(nullif(command_payload ->> 'visibility', ''), 'private'),
      sequence_value, actor_id
    );
    update public.pachanga_competition_organizer_states states set
      revision = states.revision + 1,
      server_sequence = sequence_value
    where states.organizer_group_id = aggregate_id
    returning states.revision into confirmed_revision;
    competition_id := created_id;
    organizer_group_id := aggregate_id;
    aggregate_type := 'competition_organizer';
    event_payload := jsonb_build_object('competitionId', created_id, 'competitionType', selected_type);

  elsif command_action in ('competition.cancel', 'edition.create', 'rule_set.create', 'staff.grant', 'staff.revoke') then
    select * into competition_row
    from public.pachanga_competitions competitions
    where competitions.id = aggregate_id
    for update;
    if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
    perform private.pachanga_competition_require_v1(
      competition_row.id,
      actor_id,
      case when command_action in ('staff.grant', 'staff.revoke') then 'staff' else 'manage' end
    );
    if competition_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if competition_row.status <> 'draft' and command_action <> 'competition.cancel' then
      raise exception 'COMPETITION_NOT_DRAFT' using errcode = '22023';
    end if;
    competition_id := competition_row.id;
    organizer_group_id := competition_row.organizer_group_id;
    aggregate_type := 'competition';

    if command_action = 'competition.cancel' then
      if competition_row.status <> 'draft' then
        raise exception 'COMPETITION_TRANSITION_NOT_ALLOWED' using errcode = '22023';
      end if;
      update public.pachanga_competitions competitions set
        status = 'cancelled', revision = competitions.revision + 1,
        server_sequence = sequence_value
      where competitions.id = competition_row.id
      returning competitions.revision into confirmed_revision;
      event_payload := jsonb_build_object('status', 'cancelled');

    elsif command_action = 'edition.create' then
      created_id := gen_random_uuid();
      insert into public.pachanga_competition_editions(
        id, competition_id, name, season_label, starts_at, ends_at,
        server_sequence, created_by
      ) values (
        created_id, competition_row.id,
        trim(coalesce(command_payload ->> 'name', '')),
        trim(coalesce(command_payload ->> 'seasonLabel', '')),
        nullif(command_payload ->> 'startsAt', '')::date,
        nullif(command_payload ->> 'endsAt', '')::date,
        sequence_value, actor_id
      );
      update public.pachanga_competitions competitions set
        revision = competitions.revision + 1, server_sequence = sequence_value
      where competitions.id = competition_row.id
      returning competitions.revision into confirmed_revision;
      event_payload := jsonb_build_object('editionId', created_id);

    elsif command_action = 'rule_set.create' then
      created_id := gen_random_uuid();
      insert into public.pachanga_competition_rule_sets(
        id, competition_id, name, server_sequence, created_by
      ) values (
        created_id, competition_row.id,
        trim(coalesce(command_payload ->> 'name', '')),
        sequence_value, actor_id
      );
      update public.pachanga_competitions competitions set
        revision = competitions.revision + 1, server_sequence = sequence_value
      where competitions.id = competition_row.id
      returning competitions.revision into confirmed_revision;
      event_payload := jsonb_build_object('ruleSetId', created_id);

    elsif command_action = 'staff.grant' then
      selected_user_id := (command_payload ->> 'userId')::uuid;
      selected_role := trim(coalesce(command_payload ->> 'staffRole', ''));
      if not exists (select 1 from auth.users users where users.id = selected_user_id) then
        raise exception 'STAFF_USER_NOT_FOUND' using errcode = 'P0002';
      end if;
      if selected_role = 'competition_owner' and not exists (
        select 1 from public.pachanga_groups groups
        where groups.id = competition_row.organizer_group_id and groups.owner_id = selected_user_id
      ) then
        raise exception 'COMPETITION_OWNER_ROLE_RESERVED' using errcode = '42501';
      end if;
      update public.pachanga_competition_staff_assignments assignments set
        status = 'revoked', revision = assignments.revision + 1,
        revoked_by = actor_id, revoked_at = confirmed_at,
        server_sequence = sequence_value
      where assignments.competition_id = competition_row.id
        and assignments.user_id = selected_user_id
        and assignments.status = 'active';
      created_id := gen_random_uuid();
      insert into public.pachanga_competition_staff_assignments(
        id, competition_id, user_id, staff_role, server_sequence, assigned_by, assigned_at
      ) values (
        created_id, competition_row.id, selected_user_id, selected_role,
        sequence_value, actor_id, confirmed_at
      );
      update public.pachanga_competitions competitions set
        revision = competitions.revision + 1, server_sequence = sequence_value
      where competitions.id = competition_row.id
      returning competitions.revision into confirmed_revision;
      event_payload := jsonb_build_object('staffAssignmentId', created_id, 'staffRole', selected_role);

    else
      select * into assignment_row
      from public.pachanga_competition_staff_assignments assignments
      where assignments.id = (command_payload ->> 'staffAssignmentId')::uuid
        and assignments.competition_id = competition_row.id
      for update;
      if not found then raise exception 'STAFF_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
      if assignment_row.status <> 'active' then
        raise exception 'STAFF_ASSIGNMENT_NOT_ACTIVE' using errcode = '22023';
      end if;
      update public.pachanga_competition_staff_assignments assignments set
        status = 'revoked', revision = assignments.revision + 1,
        revoked_by = actor_id, revoked_at = confirmed_at,
        server_sequence = sequence_value
      where assignments.id = assignment_row.id;
      update public.pachanga_competitions competitions set
        revision = competitions.revision + 1, server_sequence = sequence_value
      where competitions.id = competition_row.id
      returning competitions.revision into confirmed_revision;
      event_payload := jsonb_build_object('staffAssignmentId', assignment_row.id);
    end if;

  elsif command_action = 'rule_revision.create' then
    select * into rule_set_row
    from public.pachanga_competition_rule_sets rule_sets
    where rule_sets.id = aggregate_id
    for update;
    if not found then raise exception 'RULE_SET_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into competition_row
    from public.pachanga_competitions competitions
    where competitions.id = rule_set_row.competition_id;
    perform private.pachanga_competition_require_v1(competition_row.id, actor_id, 'rules');
    if rule_set_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    selected_document := command_payload -> 'ruleDocument';
    if jsonb_typeof(selected_document) <> 'object' then
      raise exception 'RULE_DOCUMENT_INVALID' using errcode = '22023';
    end if;
    if coalesce(command_payload ->> 'schemaVersion', '') <> 'competition_rules.v1' then
      raise exception 'RULE_SCHEMA_UNSUPPORTED' using errcode = '22023';
    end if;
    supersedes_id := nullif(command_payload ->> 'supersedesRevisionId', '')::uuid;
    if supersedes_id is not null and not exists (
      select 1 from public.pachanga_competition_rule_revisions revisions
      where revisions.id = supersedes_id and revisions.rule_set_id = rule_set_row.id
    ) then
      raise exception 'SUPERSEDED_RULE_REVISION_NOT_FOUND' using errcode = 'P0002';
    end if;
    select coalesce(max(revisions.version), 0) + 1 into next_version
    from public.pachanga_competition_rule_revisions revisions
    where revisions.rule_set_id = rule_set_row.id;
    selected_checksum := private.pachanga_competition_rule_checksum_v1('competition_rules.v1', selected_document);
    selected_scope := coalesce(nullif(command_payload ->> 'effectiveScope', ''), 'future_only');
    created_id := gen_random_uuid();
    insert into public.pachanga_competition_rule_revisions(
      id, rule_set_id, version, schema_version, rule_document, checksum,
      effective_from, effective_scope, supersedes_revision_id, reason,
      server_sequence, created_by
    ) values (
      created_id, rule_set_row.id, next_version, 'competition_rules.v1',
      selected_document, selected_checksum,
      nullif(command_payload ->> 'effectiveFrom', '')::timestamptz,
      selected_scope, supersedes_id, reason_code,
      sequence_value, actor_id
    );
    update public.pachanga_competition_rule_sets rule_sets set
      revision = rule_sets.revision + 1, server_sequence = sequence_value
    where rule_sets.id = rule_set_row.id
    returning rule_sets.revision into confirmed_revision;
    competition_id := competition_row.id;
    organizer_group_id := competition_row.organizer_group_id;
    aggregate_type := 'competition_rule_set';
    event_payload := jsonb_build_object(
      'ruleRevisionId', created_id, 'version', next_version, 'checksum', selected_checksum
    );

  elsif command_action in ('rule_revision.validate', 'rule_revision.freeze') then
    select * into rule_revision_row
    from public.pachanga_competition_rule_revisions revisions
    where revisions.id = aggregate_id
    for update;
    if not found then raise exception 'RULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into rule_set_row
    from public.pachanga_competition_rule_sets rule_sets
    where rule_sets.id = rule_revision_row.rule_set_id;
    select * into competition_row
    from public.pachanga_competitions competitions
    where competitions.id = rule_set_row.competition_id;
    perform private.pachanga_competition_require_v1(competition_row.id, actor_id, 'rules');
    if rule_revision_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if command_action = 'rule_revision.validate' then
      if rule_revision_row.status <> 'draft' then
        raise exception 'RULE_REVISION_NOT_DRAFT' using errcode = '22023';
      end if;
      selected_checksum := private.pachanga_validate_competition_rule_document_v1(
        rule_revision_row.schema_version, rule_revision_row.rule_document
      );
      if selected_checksum <> rule_revision_row.checksum then
        raise exception 'RULE_CHECKSUM_MISMATCH' using errcode = '22023';
      end if;
      update public.pachanga_competition_rule_revisions revisions set
        status = 'validated', revision = revisions.revision + 1,
        server_sequence = sequence_value
      where revisions.id = rule_revision_row.id
      returning revisions.revision into confirmed_revision;
      event_payload := jsonb_build_object('checksum', selected_checksum, 'status', 'validated');
    else
      if rule_revision_row.status <> 'published' then
        raise exception 'RULE_REVISION_NOT_PUBLISHED' using errcode = '22023';
      end if;
      update public.pachanga_competition_rule_revisions revisions set
        status = 'frozen', revision = revisions.revision + 1,
        server_sequence = sequence_value
      where revisions.id = rule_revision_row.id
      returning revisions.revision into confirmed_revision;
      event_payload := jsonb_build_object('checksum', rule_revision_row.checksum, 'status', 'frozen');
    end if;
    competition_id := competition_row.id;
    organizer_group_id := competition_row.organizer_group_id;
    aggregate_type := 'competition_rule_revision';

  elsif command_action = 'rule_revision.publish' then
    select * into rule_set_row
    from public.pachanga_competition_rule_sets rule_sets
    where rule_sets.id = aggregate_id
    for update;
    if not found then raise exception 'RULE_SET_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into competition_row
    from public.pachanga_competitions competitions
    where competitions.id = rule_set_row.competition_id;
    perform private.pachanga_competition_require_v1(competition_row.id, actor_id, 'rules');
    if not private.pachanga_competition_active_entitlement_v1(
      competition_row.organizer_group_id, 'competition_create'
    ) then
      raise exception 'COMPETITION_ENTITLEMENT_REQUIRED' using errcode = '42501';
    end if;
    if rule_set_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    selected_rule_revision_id := (command_payload ->> 'ruleRevisionId')::uuid;
    select * into rule_revision_row
    from public.pachanga_competition_rule_revisions revisions
    where revisions.id = selected_rule_revision_id
      and revisions.rule_set_id = rule_set_row.id
    for update;
    if not found then raise exception 'RULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
    if rule_revision_row.status <> 'validated' or rule_revision_row.effective_from is null then
      raise exception 'RULE_REVISION_NOT_PUBLISHABLE' using errcode = '22023';
    end if;
    update public.pachanga_competition_rule_revisions revisions set
      status = 'superseded', revision = revisions.revision + 1,
      server_sequence = sequence_value
    where revisions.rule_set_id = rule_set_row.id
      and revisions.status = 'published'
      and revisions.id <> rule_revision_row.id;
    update public.pachanga_competition_rule_revisions revisions set
      status = 'published', revision = revisions.revision + 1,
      server_sequence = sequence_value
    where revisions.id = rule_revision_row.id;
    update public.pachanga_competition_rule_sets rule_sets set
      status = 'active', revision = rule_sets.revision + 1,
      server_sequence = sequence_value
    where rule_sets.id = rule_set_row.id
    returning rule_sets.revision into confirmed_revision;
    competition_id := competition_row.id;
    organizer_group_id := competition_row.organizer_group_id;
    aggregate_type := 'competition_rule_set';
    event_payload := jsonb_build_object(
      'ruleRevisionId', rule_revision_row.id,
      'version', rule_revision_row.version,
      'checksum', rule_revision_row.checksum,
      'status', 'published'
    );

  elsif command_action in ('edition.cancel', 'edition.assign_rule_revision', 'stage.create', 'stage_edge.create') then
    select * into edition_row
    from public.pachanga_competition_editions editions
    where editions.id = aggregate_id
    for update;
    if not found then raise exception 'COMPETITION_EDITION_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into competition_row
    from public.pachanga_competitions competitions
    where competitions.id = edition_row.competition_id;
    perform private.pachanga_competition_require_v1(
      competition_row.id,
      actor_id,
      case when command_action = 'edition.assign_rule_revision' then 'rules' else 'manage' end
    );
    if edition_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if edition_row.status <> 'draft' then
      raise exception 'COMPETITION_EDITION_NOT_DRAFT' using errcode = '22023';
    end if;
    competition_id := competition_row.id;
    organizer_group_id := competition_row.organizer_group_id;
    aggregate_type := 'competition_edition';

    if command_action = 'edition.cancel' then
      update public.pachanga_competition_editions editions set
        status = 'cancelled', revision = editions.revision + 1,
        server_sequence = sequence_value
      where editions.id = edition_row.id
      returning editions.revision into confirmed_revision;
      event_payload := jsonb_build_object('status', 'cancelled');

    elsif command_action = 'edition.assign_rule_revision' then
      selected_rule_revision_id := (command_payload ->> 'ruleRevisionId')::uuid;
      if not exists (
        select 1
        from public.pachanga_competition_rule_revisions revisions
        join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = revisions.rule_set_id
        where revisions.id = selected_rule_revision_id
          and rule_sets.competition_id = competition_row.id
          and revisions.status in ('published', 'frozen')
      ) then
        raise exception 'RULE_REVISION_NOT_ASSIGNABLE' using errcode = '22023';
      end if;
      update public.pachanga_competition_editions editions set
        rule_revision_id = selected_rule_revision_id,
        revision = editions.revision + 1,
        server_sequence = sequence_value
      where editions.id = edition_row.id
      returning editions.revision into confirmed_revision;
      event_payload := jsonb_build_object('ruleRevisionId', selected_rule_revision_id);

    elsif command_action = 'stage.create' then
      selected_rule_revision_id := coalesce(
        nullif(command_payload ->> 'ruleRevisionId', '')::uuid,
        edition_row.rule_revision_id
      );
      if selected_rule_revision_id is not null and not exists (
        select 1
        from public.pachanga_competition_rule_revisions revisions
        join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = revisions.rule_set_id
        where revisions.id = selected_rule_revision_id
          and rule_sets.competition_id = competition_row.id
          and revisions.status in ('published', 'frozen')
      ) then
        raise exception 'RULE_REVISION_NOT_ASSIGNABLE' using errcode = '22023';
      end if;
      created_id := gen_random_uuid();
      insert into public.pachanga_competition_stages(
        id, edition_id, name, stage_type, stage_order, optional_stage,
        rule_revision_id, server_sequence, created_by
      ) values (
        created_id, edition_row.id,
        trim(coalesce(command_payload ->> 'name', '')),
        upper(trim(coalesce(command_payload ->> 'stageType', ''))),
        (command_payload ->> 'stageOrder')::integer,
        coalesce((command_payload ->> 'optional')::boolean, false),
        selected_rule_revision_id, sequence_value, actor_id
      );
      update public.pachanga_competition_editions editions set
        revision = editions.revision + 1, server_sequence = sequence_value
      where editions.id = edition_row.id
      returning editions.revision into confirmed_revision;
      event_payload := jsonb_build_object('stageId', created_id);

    else
      selected_from_stage_id := (command_payload ->> 'fromStageId')::uuid;
      selected_to_stage_id := (command_payload ->> 'toStageId')::uuid;
      if not exists (
        select 1 from public.pachanga_competition_stages stages
        where stages.id = selected_from_stage_id and stages.edition_id = edition_row.id
      ) or not exists (
        select 1 from public.pachanga_competition_stages stages
        where stages.id = selected_to_stage_id and stages.edition_id = edition_row.id
      ) then
        raise exception 'STAGE_EDGE_REFERENCE_INVALID' using errcode = '22023';
      end if;
      if exists (
        with recursive reachable(stage_id) as (
          select edges.to_stage_id
          from public.pachanga_competition_stage_edges edges
          where edges.edition_id = edition_row.id
            and edges.from_stage_id = selected_to_stage_id
          union
          select edges.to_stage_id
          from reachable
          join public.pachanga_competition_stage_edges edges
            on edges.from_stage_id = reachable.stage_id
          where edges.edition_id = edition_row.id
        )
        select 1 from reachable where stage_id = selected_from_stage_id
      ) then
        raise exception 'STAGE_GRAPH_CYCLE' using errcode = '22023';
      end if;
      created_id := gen_random_uuid();
      insert into public.pachanga_competition_stage_edges(
        id, edition_id, from_stage_id, to_stage_id, edge_order,
        server_sequence, created_by
      ) values (
        created_id, edition_row.id, selected_from_stage_id, selected_to_stage_id,
        (command_payload ->> 'edgeOrder')::integer,
        sequence_value, actor_id
      );
      update public.pachanga_competition_editions editions set
        revision = editions.revision + 1, server_sequence = sequence_value
      where editions.id = edition_row.id
      returning editions.revision into confirmed_revision;
      event_payload := jsonb_build_object(
        'stageEdgeId', created_id,
        'fromStageId', selected_from_stage_id,
        'toStageId', selected_to_stage_id
      );
    end if;

  elsif command_action in ('division.create', 'group.create') then
    select * into stage_row
    from public.pachanga_competition_stages stages
    where stages.id = aggregate_id
    for update;
    if not found then raise exception 'COMPETITION_STAGE_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into edition_row
    from public.pachanga_competition_editions editions
    where editions.id = stage_row.edition_id;
    select * into competition_row
    from public.pachanga_competitions competitions
    where competitions.id = edition_row.competition_id;
    competition_id := competition_row.id;
    organizer_group_id := competition_row.organizer_group_id;
    perform private.pachanga_competition_require_v1(competition_id, actor_id, 'manage');
    if stage_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    aggregate_type := 'competition_stage';
    created_id := gen_random_uuid();
    selected_name := trim(coalesce(command_payload ->> 'name', ''));
    selected_order := (command_payload ->> 'order')::integer;
    if command_action = 'division.create' then
      insert into public.pachanga_competition_divisions(
        id, stage_id, name, division_order, level_label, server_sequence, created_by
      ) values (
        created_id, stage_row.id, selected_name, selected_order,
        nullif(trim(coalesce(command_payload ->> 'levelLabel', '')), ''),
        sequence_value, actor_id
      );
      event_payload := jsonb_build_object('divisionId', created_id);
    else
      selected_division_id := nullif(command_payload ->> 'divisionId', '')::uuid;
      if selected_division_id is not null and not exists (
        select 1 from public.pachanga_competition_divisions divisions
        where divisions.id = selected_division_id and divisions.stage_id = stage_row.id
      ) then
        raise exception 'COMPETITION_DIVISION_NOT_FOUND' using errcode = 'P0002';
      end if;
      insert into public.pachanga_competition_groups(
        id, stage_id, division_id, name, group_order, server_sequence, created_by
      ) values (
        created_id, stage_row.id, selected_division_id, selected_name,
        selected_order, sequence_value, actor_id
      );
      event_payload := jsonb_build_object('groupId', created_id, 'divisionId', selected_division_id);
    end if;
    update public.pachanga_competition_stages stages set
      revision = stages.revision + 1, server_sequence = sequence_value
    where stages.id = stage_row.id
    returning stages.revision into confirmed_revision;

  else
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  snapshot := private.pachanga_competition_snapshot_v1(competition_id);
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

revoke all on function public.command_pachanga_competition_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_competition_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function private.pachanga_competition_guard_rule_history_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'RULE_REVISION_IMMUTABLE' using errcode = '22023';
  end if;
  if old.rule_set_id is distinct from new.rule_set_id
     or old.version is distinct from new.version
     or old.schema_version is distinct from new.schema_version
     or old.rule_document is distinct from new.rule_document
     or old.checksum is distinct from new.checksum
     or old.effective_from is distinct from new.effective_from
     or old.effective_scope is distinct from new.effective_scope
     or old.supersedes_revision_id is distinct from new.supersedes_revision_id
     or old.reason is distinct from new.reason
     or old.created_by is distinct from new.created_by
     or old.created_at is distinct from new.created_at then
    raise exception 'RULE_REVISION_IMMUTABLE' using errcode = '22023';
  end if;
  if old.status in ('frozen', 'superseded') and old.status is distinct from new.status then
    raise exception 'RULE_REVISION_FROZEN' using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_guard_rule_history_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_competition_rule_history_v1
  on public.pachanga_competition_rule_revisions;
create trigger guard_pachanga_competition_rule_history_v1
before update or delete on public.pachanga_competition_rule_revisions
for each row execute function private.pachanga_competition_guard_rule_history_v1();

create or replace function private.pachanga_competition_validate_relations_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  target_competition_id uuid;
  target_edition_id uuid;
  target_stage_id uuid;
begin
  if tg_table_name = 'pachanga_competition_editions' then
    if new.rule_revision_id is not null and not exists (
      select 1
      from public.pachanga_competition_rule_revisions revisions
      join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = revisions.rule_set_id
      where revisions.id = new.rule_revision_id
        and rule_sets.competition_id = new.competition_id
        and revisions.status in ('published', 'frozen', 'superseded')
    ) then raise exception 'RULE_REVISION_RELATION_INVALID' using errcode = '23514'; end if;
  elsif tg_table_name = 'pachanga_competition_stages' then
    if new.rule_revision_id is not null then
      select editions.competition_id into target_competition_id
      from public.pachanga_competition_editions editions where editions.id = new.edition_id;
      if not exists (
        select 1
        from public.pachanga_competition_rule_revisions revisions
        join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = revisions.rule_set_id
        where revisions.id = new.rule_revision_id
          and rule_sets.competition_id = target_competition_id
          and revisions.status in ('published', 'frozen', 'superseded')
      ) then raise exception 'RULE_REVISION_RELATION_INVALID' using errcode = '23514'; end if;
    end if;
  elsif tg_table_name = 'pachanga_competition_groups' then
    if new.division_id is not null and not exists (
      select 1 from public.pachanga_competition_divisions divisions
      where divisions.id = new.division_id and divisions.stage_id = new.stage_id
    ) then raise exception 'DIVISION_STAGE_RELATION_INVALID' using errcode = '23514'; end if;
  elsif tg_table_name = 'pachanga_competition_match_contexts' then
    select editions.competition_id into target_competition_id
    from public.pachanga_competition_editions editions where editions.id = new.edition_id;
    select stages.edition_id into target_edition_id
    from public.pachanga_competition_stages stages where stages.id = new.stage_id;
    if target_competition_id is distinct from new.competition_id
       or target_edition_id is distinct from new.edition_id then
      raise exception 'COMPETITION_CONTEXT_RELATION_INVALID' using errcode = '23514';
    end if;
    if new.division_id is not null and not exists (
      select 1 from public.pachanga_competition_divisions divisions
      where divisions.id = new.division_id and divisions.stage_id = new.stage_id
    ) then raise exception 'COMPETITION_CONTEXT_DIVISION_INVALID' using errcode = '23514'; end if;
    if new.competition_group_id is not null then
      select competition_groups.stage_id into target_stage_id
      from public.pachanga_competition_groups competition_groups
      where competition_groups.id = new.competition_group_id;
      if target_stage_id is distinct from new.stage_id then
        raise exception 'COMPETITION_CONTEXT_GROUP_INVALID' using errcode = '23514';
      end if;
    end if;
    if not exists (
      select 1
      from public.pachanga_competition_rule_revisions revisions
      join public.pachanga_competition_rule_sets rule_sets on rule_sets.id = revisions.rule_set_id
      where revisions.id = new.rule_revision_id
        and rule_sets.competition_id = new.competition_id
        and revisions.status = 'frozen'
    ) then raise exception 'COMPETITION_CONTEXT_REQUIRES_FROZEN_RULES' using errcode = '23514'; end if;
    if not exists (
      select 1 from public.pachanga_canonical_matches matches
      where matches.id = new.canonical_match_id and matches.status = 'active'
    ) then raise exception 'COMPETITION_CONTEXT_CANONICAL_MATCH_INVALID' using errcode = '23514'; end if;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_validate_relations_v1()
  from public, anon, authenticated;

drop trigger if exists validate_pachanga_competition_edition_relation_v1
  on public.pachanga_competition_editions;
create trigger validate_pachanga_competition_edition_relation_v1
before insert or update of competition_id, rule_revision_id
on public.pachanga_competition_editions
for each row execute function private.pachanga_competition_validate_relations_v1();

drop trigger if exists validate_pachanga_competition_stage_relation_v1
  on public.pachanga_competition_stages;
create trigger validate_pachanga_competition_stage_relation_v1
before insert or update of edition_id, rule_revision_id
on public.pachanga_competition_stages
for each row execute function private.pachanga_competition_validate_relations_v1();

drop trigger if exists validate_pachanga_competition_group_relation_v1
  on public.pachanga_competition_groups;
create trigger validate_pachanga_competition_group_relation_v1
before insert or update of stage_id, division_id
on public.pachanga_competition_groups
for each row execute function private.pachanga_competition_validate_relations_v1();

drop trigger if exists validate_pachanga_competition_context_relation_v1
  on public.pachanga_competition_match_contexts;
create trigger validate_pachanga_competition_context_relation_v1
before insert or update of canonical_match_id, competition_id, edition_id, stage_id,
  division_id, competition_group_id, rule_revision_id
on public.pachanga_competition_match_contexts
for each row execute function private.pachanga_competition_validate_relations_v1();

create or replace function private.pachanga_competition_validate_stage_edge_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not exists (
    select 1 from public.pachanga_competition_stages stages
    where stages.id = new.from_stage_id and stages.edition_id = new.edition_id
  ) or not exists (
    select 1 from public.pachanga_competition_stages stages
    where stages.id = new.to_stage_id and stages.edition_id = new.edition_id
  ) then
    raise exception 'STAGE_EDGE_REFERENCE_INVALID' using errcode = '23514';
  end if;
  if exists (
    with recursive edges as (
      select current_edges.from_stage_id, current_edges.to_stage_id
      from public.pachanga_competition_stage_edges current_edges
      where current_edges.edition_id = new.edition_id
        and (tg_op = 'INSERT' or current_edges.id <> new.id)
      union all
      select new.from_stage_id, new.to_stage_id
    ), reach(source_id, target_id) as (
      select from_stage_id, to_stage_id from edges
      union
      select reach.source_id, edges.to_stage_id
      from reach join edges on edges.from_stage_id = reach.target_id
    )
    select 1 from reach where source_id = target_id
  ) then
    raise exception 'STAGE_GRAPH_CYCLE' using errcode = '23514';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_validate_stage_edge_v1()
  from public, anon, authenticated;

drop trigger if exists validate_pachanga_competition_stage_edge_v1
  on public.pachanga_competition_stage_edges;
create trigger validate_pachanga_competition_stage_edge_v1
before insert or update on public.pachanga_competition_stage_edges
for each row execute function private.pachanga_competition_validate_stage_edge_v1();

create or replace function private.pachanga_competition_immutable_ledger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'COMPETITION_AUDIT_LEDGER_IMMUTABLE' using errcode = '42501';
end;
$$;

revoke all on function private.pachanga_competition_immutable_ledger_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_competition_receipts_v1
  on private.pachanga_competition_operation_receipts;
create trigger guard_pachanga_competition_receipts_v1
before update or delete on private.pachanga_competition_operation_receipts
for each row execute function private.pachanga_competition_immutable_ledger_v1();

drop trigger if exists guard_pachanga_competition_events_v1
  on private.pachanga_competition_events;
create trigger guard_pachanga_competition_events_v1
before update or delete on private.pachanga_competition_events
for each row execute function private.pachanga_competition_immutable_ledger_v1();

create or replace function private.pachanga_competition_can_read_invalidation_v1(
  target_group_id uuid,
  target_competition_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select target_actor_id is not null and (
    private.pachanga_platform_role_for_user_v1(target_actor_id) in ('platform_owner', 'platform_admin')
    or exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_group_id and groups.owner_id = target_actor_id
    )
    or (
      target_competition_id is not null and exists (
        select 1 from public.pachanga_competition_staff_assignments assignments
        where assignments.competition_id = target_competition_id
          and assignments.user_id = target_actor_id
          and assignments.status = 'active'
      )
    )
  );
$$;

revoke all on function private.pachanga_competition_can_read_invalidation_v1(uuid, uuid, uuid)
  from public, anon, authenticated;

alter table public.pachanga_competition_organizer_states enable row level security;
alter table public.pachanga_competition_entitlement_grants enable row level security;
alter table public.pachanga_competitions enable row level security;
alter table public.pachanga_competition_rule_sets enable row level security;
alter table public.pachanga_competition_rule_revisions enable row level security;
alter table public.pachanga_competition_editions enable row level security;
alter table public.pachanga_competition_stages enable row level security;
alter table public.pachanga_competition_divisions enable row level security;
alter table public.pachanga_competition_groups enable row level security;
alter table public.pachanga_competition_stage_edges enable row level security;
alter table public.pachanga_competition_staff_assignments enable row level security;
alter table public.pachanga_competition_match_contexts enable row level security;
alter table public.pachanga_competition_invalidations enable row level security;

revoke all on table private.pachanga_competition_foundation_settings from public, anon, authenticated;
revoke all on table private.pachanga_competition_operation_receipts from public, anon, authenticated;
revoke all on table private.pachanga_competition_events from public, anon, authenticated;
grant all on table private.pachanga_competition_foundation_settings to service_role;
grant all on table private.pachanga_competition_operation_receipts to service_role;
grant all on table private.pachanga_competition_events to service_role;

revoke all on table public.pachanga_competition_organizer_states from public, anon, authenticated;
revoke all on table public.pachanga_competition_entitlement_grants from public, anon, authenticated;
revoke all on table public.pachanga_competitions from public, anon, authenticated;
revoke all on table public.pachanga_competition_rule_sets from public, anon, authenticated;
revoke all on table public.pachanga_competition_rule_revisions from public, anon, authenticated;
revoke all on table public.pachanga_competition_editions from public, anon, authenticated;
revoke all on table public.pachanga_competition_stages from public, anon, authenticated;
revoke all on table public.pachanga_competition_divisions from public, anon, authenticated;
revoke all on table public.pachanga_competition_groups from public, anon, authenticated;
revoke all on table public.pachanga_competition_stage_edges from public, anon, authenticated;
revoke all on table public.pachanga_competition_staff_assignments from public, anon, authenticated;
revoke all on table public.pachanga_competition_match_contexts from public, anon, authenticated;
revoke all on table public.pachanga_competition_invalidations from public, anon, authenticated;

grant all on table public.pachanga_competition_organizer_states to service_role;
grant all on table public.pachanga_competition_entitlement_grants to service_role;
grant all on table public.pachanga_competitions to service_role;
grant all on table public.pachanga_competition_rule_sets to service_role;
grant all on table public.pachanga_competition_rule_revisions to service_role;
grant all on table public.pachanga_competition_editions to service_role;
grant all on table public.pachanga_competition_stages to service_role;
grant all on table public.pachanga_competition_divisions to service_role;
grant all on table public.pachanga_competition_groups to service_role;
grant all on table public.pachanga_competition_stage_edges to service_role;
grant all on table public.pachanga_competition_staff_assignments to service_role;
grant all on table public.pachanga_competition_match_contexts to service_role;
grant all on table public.pachanga_competition_invalidations to service_role;
grant select on table public.pachanga_competition_invalidations to authenticated;

drop policy if exists pachanga_competition_invalidations_select_v1
  on public.pachanga_competition_invalidations;
create policy pachanga_competition_invalidations_select_v1
on public.pachanga_competition_invalidations
for select
to authenticated
using (
  private.pachanga_competition_can_read_invalidation_v1(
    organizer_group_id,
    competition_id,
    (select auth.uid())
  )
);

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_publication_tables publication_tables
    where publication_tables.pubname = 'supabase_realtime'
      and publication_tables.schemaname = 'public'
      and publication_tables.tablename = 'pachanga_competition_invalidations'
  ) then
    alter publication supabase_realtime add table public.pachanga_competition_invalidations;
  end if;
end;
$$;

comment on table public.pachanga_competition_invalidations is
  'Realtime invalidation only. Clients must refetch the canonical competition read model.';
