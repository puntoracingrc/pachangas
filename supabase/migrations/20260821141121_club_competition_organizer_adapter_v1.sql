-- Competition Organizer R2 adapter. R1 migrations remain immutable.
-- TEAM and CLUB are represented by real FKs plus database-enforced XOR constraints.

alter table public.pachanga_competition_organizer_states
  add column if not exists id uuid default gen_random_uuid(),
  add column if not exists organizer_kind text not null default 'TEAM',
  add column if not exists organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict;

alter table public.pachanga_competition_organizer_states
  drop constraint if exists pachanga_competition_organizer_states_pkey;
alter table public.pachanga_competition_organizer_states
  alter column organizer_group_id drop not null;
alter table public.pachanga_competition_organizer_states
  add constraint pachanga_competition_organizer_states_id_pkey primary key (id),
  add constraint pachanga_competition_organizer_states_pkey unique (organizer_group_id),
  add constraint pachanga_competition_organizer_states_club_key unique (organizer_club_id),
  add constraint pachanga_competition_organizer_states_kind_check check (organizer_kind in ('TEAM', 'CLUB')),
  add constraint pachanga_competition_organizer_states_authority_check check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  );

alter table public.pachanga_competition_entitlement_grants
  add column if not exists organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict;
alter table public.pachanga_competition_entitlement_grants
  alter column organizer_group_id drop not null,
  drop constraint if exists pachanga_competition_entitlement_grants_organizer_kind_check;
alter table public.pachanga_competition_entitlement_grants
  add constraint pachanga_competition_entitlement_grants_organizer_kind_check check (organizer_kind in ('TEAM', 'CLUB')),
  add constraint pachanga_competition_entitlement_grants_authority_check check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  );
drop index if exists public.pachanga_competition_entitlement_active_idx;
create unique index pachanga_competition_entitlement_team_active_idx
  on public.pachanga_competition_entitlement_grants(organizer_group_id, capability)
  where status = 'active' and organizer_kind = 'TEAM';
create unique index pachanga_competition_entitlement_club_active_idx
  on public.pachanga_competition_entitlement_grants(organizer_club_id, capability)
  where status = 'active' and organizer_kind = 'CLUB';
create index pachanga_competition_entitlement_club_expiry_idx
  on public.pachanga_competition_entitlement_grants(expires_at, organizer_club_id)
  where status = 'active' and organizer_kind = 'CLUB' and expires_at is not null;

alter table public.pachanga_competitions
  add column if not exists organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict;
alter table public.pachanga_competitions
  alter column organizer_group_id drop not null,
  drop constraint if exists pachanga_competitions_organizer_kind_check,
  drop constraint if exists pachanga_competitions_organizer_group_id_slug_key;
alter table public.pachanga_competitions
  add constraint pachanga_competitions_organizer_kind_check check (organizer_kind in ('TEAM', 'CLUB')),
  add constraint pachanga_competitions_authority_check check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  );
create unique index pachanga_competitions_team_slug_idx
  on public.pachanga_competitions(organizer_group_id, slug)
  where organizer_kind = 'TEAM';
create unique index pachanga_competitions_club_slug_idx
  on public.pachanga_competitions(organizer_club_id, slug)
  where organizer_kind = 'CLUB';
create index pachanga_competitions_club_organizer_idx
  on public.pachanga_competitions(organizer_club_id, status, updated_at desc, id)
  where organizer_kind = 'CLUB';

alter table public.pachanga_competition_invalidations
  add column if not exists organizer_club_id uuid references public.pachanga_clubs(id) on delete cascade;
alter table public.pachanga_competition_invalidations
  alter column organizer_group_id drop not null;
alter table public.pachanga_competition_invalidations
  add constraint pachanga_competition_invalidations_authority_check check (
    (organizer_group_id is not null and organizer_club_id is null)
    or (organizer_group_id is null and organizer_club_id is not null)
  );
create index pachanga_competition_invalidations_club_idx
  on public.pachanga_competition_invalidations(organizer_club_id, server_sequence desc)
  where organizer_club_id is not null;

comment on column public.pachanga_competitions.organizer_club_id is
  'R2 Club organizer FK. The authority constraint guarantees exactly one TEAM or CLUB reference.';

create or replace function private.pachanga_competition_active_entitlement_v2(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_capability text
)
returns boolean
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with authority_time as materialized (
    select clock_timestamp() as checked_at
  )
  select exists (
    select 1
    from public.pachanga_competition_entitlement_grants grants
    cross join authority_time
    where grants.organizer_kind = upper(target_organizer_kind)
      and (
        (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
        or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
      )
      and grants.capability = target_capability
      and grants.status = 'active'
      and grants.valid_from <= authority_time.checked_at
      and (grants.expires_at is null or grants.expires_at > authority_time.checked_at)
  );
$$;

create or replace function private.pachanga_competition_entitlement_snapshot_v2(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with authority_time as materialized (
    select clock_timestamp() as checked_at
  )
  select jsonb_build_object(
    'organizerKind', upper(target_organizer_kind),
    'organizerGroupId', case when upper(target_organizer_kind) = 'TEAM' then target_organizer_id else null end,
    'organizerClubId', case when upper(target_organizer_kind) = 'CLUB' then target_organizer_id else null end,
    'organizerRevision', coalesce((
      select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_kind = upper(target_organizer_kind)
        and (
          (states.organizer_kind = 'TEAM' and states.organizer_group_id = target_organizer_id)
          or (states.organizer_kind = 'CLUB' and states.organizer_club_id = target_organizer_id)
        )
    ), 0),
    'grants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', grants.id,
        'capability', grants.capability,
        'source', grants.grant_source,
        'status', case
          when grants.status = 'revoked' then 'revoked'
          when grants.expires_at is not null and grants.expires_at <= authority_time.checked_at then 'expired'
          when grants.valid_from > authority_time.checked_at then 'scheduled'
          else 'active'
        end,
        'validFrom', grants.valid_from,
        'expiresAt', grants.expires_at,
        'revision', grants.revision,
        'updatedAt', grants.updated_at
      ) order by grants.capability, grants.server_sequence, grants.id)
      from public.pachanga_competition_entitlement_grants grants
      where grants.organizer_kind = upper(target_organizer_kind)
        and (
          (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
          or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
        )
    ), '[]'::jsonb),
    'canCreate', private.pachanga_competition_active_entitlement_v2(
      target_organizer_kind, target_organizer_id, 'competition_create'
    )
  )
  from authority_time;
$$;

create or replace function private.pachanga_competition_resolve_organizer_v2(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
declare actor_role text;
declare organizer_name text;
declare organizer_active boolean := false;
declare organizer_revision bigint := 0;
begin
  if normalized_kind = 'TEAM' then
    select groups.name into organizer_name
    from public.pachanga_groups groups where groups.id = target_organizer_id;
    if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    organizer_active := true;
    if exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_organizer_id and groups.owner_id = target_actor_id
    ) then actor_role := 'team_owner'; end if;
  elsif normalized_kind = 'CLUB' then
    select clubs.name, clubs.operational_status = 'active'
    into organizer_name, organizer_active
    from public.pachanga_clubs clubs where clubs.id = target_organizer_id;
    if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    actor_role := private.pachanga_club_active_role_v1(target_organizer_id, target_actor_id);
  else
    raise exception 'INVALID_ORGANIZER_KIND' using errcode = '22023';
  end if;
  select states.revision into organizer_revision
  from public.pachanga_competition_organizer_states states
  where states.organizer_kind = normalized_kind
    and (
      (normalized_kind = 'TEAM' and states.organizer_group_id = target_organizer_id)
      or (normalized_kind = 'CLUB' and states.organizer_club_id = target_organizer_id)
    );
  return jsonb_build_object(
    'kind', normalized_kind,
    'id', target_organizer_id,
    'name', organizer_name,
    'active', organizer_active,
    'actorRole', actor_role,
    'revision', coalesce(organizer_revision, 0),
    'canCreateCompetition', case
      when normalized_kind = 'TEAM' then actor_role = 'team_owner'
      when normalized_kind = 'CLUB' then actor_role in ('club_owner', 'club_competition_manager')
      else false
    end,
    'entitlement', private.pachanga_competition_entitlement_snapshot_v2(
      normalized_kind, target_organizer_id
    )
  );
end;
$$;

create or replace function private.pachanga_competition_active_entitlement_v1(
  target_group_id uuid,
  target_capability text
)
returns boolean
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_competition_active_entitlement_v2('TEAM', target_group_id, target_capability);
$$;

create or replace function private.pachanga_competition_entitlement_snapshot_v1(target_group_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_competition_entitlement_snapshot_v2('TEAM', target_group_id);
$$;

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
  selected_competition public.pachanga_competitions%rowtype;
  assigned_role text;
  platform_role text;
begin
  if target_actor_id is null then
    if private.pachanga_competition_is_service_authority_v1() then return 'service_authority'; end if;
    return null;
  end if;
  platform_role := private.pachanga_platform_role_for_user_v1(target_actor_id);
  if platform_role in ('platform_owner', 'platform_admin') then return platform_role; end if;
  select * into selected_competition
  from public.pachanga_competitions competitions where competitions.id = target_competition_id;
  if not found then return null; end if;
  if selected_competition.organizer_kind = 'TEAM' and exists (
    select 1 from public.pachanga_groups groups
    where groups.id = selected_competition.organizer_group_id and groups.owner_id = target_actor_id
  ) then return 'competition_owner'; end if;
  if selected_competition.organizer_kind = 'CLUB'
     and private.pachanga_club_active_role_v1(selected_competition.organizer_club_id, target_actor_id) = 'club_owner' then
    return 'competition_owner';
  end if;
  select assignments.staff_role into assigned_role
  from public.pachanga_competition_staff_assignments assignments
  where assignments.competition_id = target_competition_id
    and assignments.user_id = target_actor_id and assignments.status = 'active'
  order by assignments.server_sequence desc, assignments.id desc
  limit 1;
  return assigned_role;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_competition_active_entitlement_v2(text,uuid,text)'::regprocedure,
    'private.pachanga_competition_entitlement_snapshot_v2(text,uuid)'::regprocedure,
    'private.pachanga_competition_resolve_organizer_v2(text,uuid,uuid)'::regprocedure,
    'private.pachanga_competition_active_entitlement_v1(uuid,text)'::regprocedure,
    'private.pachanga_competition_entitlement_snapshot_v1(uuid)'::regprocedure,
    'private.pachanga_competition_actor_role_v1(uuid,uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

create or replace function private.pachanga_competition_snapshot_v1(target_competition_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'competition', jsonb_build_object(
      'id', competitions.id,
      'organizerKind', competitions.organizer_kind,
      'organizerGroupId', competitions.organizer_group_id,
      'organizerClubId', competitions.organizer_club_id,
      'organizerName', coalesce(groups.name, clubs.name),
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
    'entitlement', private.pachanga_competition_entitlement_snapshot_v2(
      competitions.organizer_kind,
      coalesce(competitions.organizer_group_id, competitions.organizer_club_id)
    ),
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
  left join public.pachanga_groups groups on groups.id = competitions.organizer_group_id
  left join public.pachanga_clubs clubs on clubs.id = competitions.organizer_club_id
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
  target_organizer_club_id uuid;
begin
  if target_competition_id is not null then
    select competitions.organizer_club_id into target_organizer_club_id
    from public.pachanga_competitions competitions
    where competitions.id = target_competition_id;
  end if;
  if target_action = 'canonical.backfill' then
    update private.pachanga_canonical_match_health_state state
    set initialized_at = coalesce(state.initialized_at, target_confirmed_at),
        updated_at = clock_timestamp()
    where state.singleton;
    target_snapshot := jsonb_set(
      coalesce(target_snapshot, '{}'::jsonb),
      '{health}', private.pachanga_canonical_match_health_v1(), true
    );
  end if;
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', case
      when target_organizer_group_id is null and target_organizer_club_id is null then '[]'::jsonb
      else jsonb_build_array(jsonb_build_object(
        'entityType', target_aggregate_type,
        'entityId', target_aggregate_id,
        'revision', target_confirmed_revision
      ))
    end
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
  if target_organizer_group_id is not null or target_organizer_club_id is not null then
    insert into public.pachanga_competition_invalidations(
      server_sequence, competition_id, organizer_group_id, organizer_club_id,
      entity_type, entity_id, revision, created_at
    ) values (
      target_server_sequence, target_competition_id, target_organizer_group_id,
      target_organizer_club_id, target_aggregate_type, target_aggregate_id::text,
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

create or replace function private.pachanga_competition_can_read_invalidation_v2(
  target_group_id uuid,
  target_club_id uuid,
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
    or private.pachanga_club_can_v1(target_club_id, target_actor_id, 'read')
    or (
      target_competition_id is not null and exists (
        select 1 from public.pachanga_competition_staff_assignments assignments
        where assignments.competition_id = target_competition_id
          and assignments.user_id = target_actor_id and assignments.status = 'active'
      )
    )
  );
$$;

revoke all on function private.pachanga_competition_can_read_invalidation_v2(uuid, uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.pachanga_competition_can_read_invalidation_v2(uuid, uuid, uuid, uuid)
  to authenticated;

drop policy if exists pachanga_competition_invalidations_select_v1
  on public.pachanga_competition_invalidations;
create policy pachanga_competition_invalidations_select_v2
on public.pachanga_competition_invalidations
for select
to authenticated
using (private.pachanga_competition_can_read_invalidation_v2(
  organizer_group_id, organizer_club_id, competition_id, (select auth.uid())
));

create or replace function public.command_pachanga_competition_foundation_v2(
  operation_id uuid,
  organizer_kind text,
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
  normalized_kind text := upper(trim(coalesce(organizer_kind, '')));
  actor_kind text;
  request_hash text;
  replay jsonb;
  sanitized_metadata jsonb;
  confirmed_at timestamptz := clock_timestamp();
  sequence_value bigint;
  confirmed_revision bigint;
  reason_code text;
  organizer jsonb;
  selected_role text;
  selected_name text;
  selected_slug text;
  selected_type text;
  created_competition_id uuid;
  created_edition_id uuid;
  created_rule_set_id uuid;
  created_assignment_id uuid;
  organizer_state public.pachanga_competition_organizer_states%rowtype;
  snapshot jsonb;
  response jsonb;
begin
  if normalized_kind = 'TEAM' then
    return public.command_pachanga_competition_foundation_v1(
      operation_id, aggregate_id, expected_revision, command_action,
      command_payload, client_metadata
    );
  end if;
  if normalized_kind <> 'CLUB' then raise exception 'INVALID_ORGANIZER_KIND' using errcode = '22023'; end if;
  if command_action <> 'competition.create' then
    return public.command_pachanga_competition_foundation_v1(
      operation_id, aggregate_id, expected_revision, command_action,
      command_payload, client_metadata
    );
  end if;
  if operation_id is null or aggregate_id is null or expected_revision is null or expected_revision < 0
     or jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_COMPETITION_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  actor_kind := 'authenticated';
  perform private.pachanga_competition_assert_flags_v1(true, false);
  if not coalesce((
    select settings.club_competition_organizer_enabled
    from private.pachanga_club_foundation_settings settings where settings.singleton
  ), false) then raise exception 'CLUB_COMPETITION_ORGANIZER_DISABLED' using errcode = '0A000'; end if;
  sanitized_metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    command_action, aggregate_id, expected_revision,
    command_payload || jsonb_build_object('organizerKind', 'CLUB')
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91403));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, command_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  perform 1
  from public.pachanga_clubs clubs where clubs.id = aggregate_id for update;
  if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
  organizer := private.pachanga_competition_resolve_organizer_v2('CLUB', aggregate_id, actor_id);
  if not coalesce((organizer ->> 'active')::boolean, false) then
    raise exception 'CLUB_MUST_BE_ACTIVE' using errcode = '42501';
  end if;
  selected_role := organizer ->> 'actorRole';
  if selected_role not in ('club_owner', 'club_competition_manager') then
    raise exception 'CLUB_COMPETITION_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  if not private.pachanga_competition_active_entitlement_v2('CLUB', aggregate_id, 'competition_create') then
    raise exception 'COMPETITION_ENTITLEMENT_REQUIRED' using errcode = '42501';
  end if;
  select * into organizer_state
  from public.pachanga_competition_organizer_states states
  where states.organizer_kind = 'CLUB' and states.organizer_club_id = aggregate_id
  for update;
  if not found then
    if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    insert into public.pachanga_competition_organizer_states(
      organizer_kind, organizer_group_id, organizer_club_id, revision,
      server_sequence, created_at, updated_at
    ) values (
      'CLUB', null, aggregate_id, 1, nextval('private.pachanga_competition_sequence'),
      confirmed_at, confirmed_at
    ) returning * into organizer_state;
  elsif organizer_state.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  reason_code := left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), 'competition.create'), 120);
  selected_name := trim(coalesce(command_payload ->> 'name', ''));
  selected_slug := lower(trim(coalesce(command_payload ->> 'slug', '')));
  selected_type := upper(trim(coalesce(command_payload ->> 'competitionType', '')));
  created_competition_id := gen_random_uuid();
  created_edition_id := gen_random_uuid();
  created_rule_set_id := gen_random_uuid();
  insert into public.pachanga_competitions(
    id, organizer_kind, organizer_group_id, organizer_club_id, name, slug,
    competition_type, visibility, server_sequence, created_by, created_at, updated_at
  ) values (
    created_competition_id, 'CLUB', null, aggregate_id, selected_name, selected_slug,
    selected_type, coalesce(nullif(command_payload ->> 'visibility', ''), 'private'),
    sequence_value, actor_id, confirmed_at, confirmed_at
  );
  insert into public.pachanga_competition_editions(
    id, competition_id, name, season_label, starts_at, ends_at,
    server_sequence, created_by, created_at, updated_at
  ) values (
    created_edition_id, created_competition_id,
    coalesce(nullif(trim(command_payload ->> 'editionName'), ''), 'Edición inicial'),
    coalesce(nullif(trim(command_payload ->> 'seasonLabel'), ''), 'Temporada inicial'),
    nullif(command_payload ->> 'startsAt', '')::date,
    nullif(command_payload ->> 'endsAt', '')::date,
    sequence_value, actor_id, confirmed_at, confirmed_at
  );
  insert into public.pachanga_competition_rule_sets(
    id, competition_id, name, server_sequence, created_by, created_at, updated_at
  ) values (
    created_rule_set_id, created_competition_id,
    coalesce(nullif(trim(command_payload ->> 'ruleSetName'), ''), 'Reglamento principal'),
    sequence_value, actor_id, confirmed_at, confirmed_at
  );
  if selected_role = 'club_competition_manager' then
    created_assignment_id := gen_random_uuid();
    insert into public.pachanga_competition_staff_assignments(
      id, competition_id, user_id, staff_role, status, server_sequence,
      assigned_by, assigned_at, updated_at
    ) values (
      created_assignment_id, created_competition_id, actor_id, 'competition_director',
      'active', sequence_value, actor_id, confirmed_at, confirmed_at
    );
  end if;
  update public.pachanga_competition_organizer_states states set
    revision = states.revision + 1,
    server_sequence = sequence_value,
    updated_at = confirmed_at
  where states.id = organizer_state.id
  returning states.revision into confirmed_revision;
  snapshot := private.pachanga_competition_snapshot_v1(created_competition_id);
  response := private.pachanga_competition_store_command_v1(
    operation_id, actor_id, actor_kind, command_action, 'competition_organizer',
    aggregate_id, created_competition_id, null, confirmed_revision, sequence_value,
    reason_code, request_hash, sanitized_metadata,
    jsonb_build_object(
      'competitionId', created_competition_id,
      'competitionType', selected_type,
      'editionId', created_edition_id,
      'ruleSetId', created_rule_set_id,
      'staffAssignmentId', created_assignment_id,
      'organizerKind', 'CLUB'
    ), snapshot, confirmed_at
  );
  return response;
exception
  when unique_violation then raise exception 'COMPETITION_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_competition_foundation_v2(
  uuid, text, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_competition_foundation_v2(
  uuid, text, uuid, bigint, text, jsonb, jsonb
) to authenticated;

alter function private.pachanga_club_snapshot_v1(uuid, uuid)
  rename to pachanga_club_snapshot_core_v1;

create or replace function private.pachanga_club_snapshot_v1(target_club_id uuid, target_actor_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare base jsonb;
begin
  base := private.pachanga_club_snapshot_core_v1(target_club_id, target_actor_id);
  if base is null then return null; end if;
  if private.pachanga_club_can_v1(target_club_id, target_actor_id, 'read') then
    base := jsonb_set(
      base,
      '{entitlements}',
      private.pachanga_competition_entitlement_snapshot_v2('CLUB', target_club_id),
      true
    );
    base := jsonb_set(
      base,
      '{competitions}',
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', competitions.id,
          'name', competitions.name,
          'slug', competitions.slug,
          'type', competitions.competition_type,
          'visibility', competitions.visibility,
          'status', competitions.status,
          'revision', competitions.revision,
          'serverSequence', competitions.server_sequence,
          'updatedAt', competitions.updated_at
        ) order by competitions.updated_at desc, competitions.id)
        from (
          select rows.*
          from public.pachanga_competitions rows
          where rows.organizer_kind = 'CLUB' and rows.organizer_club_id = target_club_id
          order by rows.updated_at desc, rows.id
          limit 100
        ) competitions
      ), '[]'::jsonb),
      true
    );
  end if;
  return base;
end;
$$;

revoke all on function private.pachanga_club_snapshot_core_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_club_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.get_my_pachanga_competition_foundation_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare settings private.pachanga_competition_foundation_settings%rowtype;
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
        'kind', 'TEAM',
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
          where competitions.organizer_kind = 'TEAM'
            and competitions.organizer_group_id = groups.id
            and assignments.user_id = actor_id and assignments.status = 'active'
        )
    ), '[]'::jsonb),
    'clubOrganizers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kind', 'CLUB',
        'clubId', clubs.id,
        'name', clubs.name,
        'operationalStatus', clubs.operational_status,
        'role', private.pachanga_club_active_role_v1(clubs.id, actor_id),
        'entitlement', private.pachanga_competition_entitlement_snapshot_v2('CLUB', clubs.id)
      ) order by clubs.name, clubs.id)
      from public.pachanga_clubs clubs
      where private.pachanga_club_can_v1(clubs.id, actor_id, 'competition_create')
        or exists (
          select 1
          from public.pachanga_competitions competitions
          join public.pachanga_competition_staff_assignments assignments
            on assignments.competition_id = competitions.id
          where competitions.organizer_kind = 'CLUB'
            and competitions.organizer_club_id = clubs.id
            and assignments.user_id = actor_id and assignments.status = 'active'
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

comment on function public.command_pachanga_competition_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is 'Backward-compatible TEAM organizer command. Meaning and envelope remain R1.';
comment on function public.command_pachanga_competition_foundation_v2(
  uuid, text, uuid, bigint, text, jsonb, jsonb
) is 'Generic TEAM/CLUB organizer adapter. TEAM delegates to R1; CLUB creation uses canonical R1 Competition entities.';
