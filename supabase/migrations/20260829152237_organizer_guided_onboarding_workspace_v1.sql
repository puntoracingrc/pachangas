-- Wave 8A: guided onboarding workspace. A workspace reflects access; it never grants it.

set lock_timeout = '5s';
set statement_timeout = '5min';

create table private.pachanga_organizer_onboarding_workspaces_v1 (
  id uuid primary key default gen_random_uuid(),
  organizer_kind text not null,
  organizer_group_id uuid references public.pachanga_groups(id) on delete restrict,
  organizer_club_id uuid references public.pachanga_clubs(id) on delete restrict,
  origin text not null,
  source_application_id uuid references private.pachanga_organizer_access_applications_v1(id) on delete restrict,
  source_decision_id uuid references private.pachanga_organizer_access_decisions_v1(id) on delete restrict,
  source_access_grant_id uuid references private.pachanga_organizer_access_grants_v1(id) on delete restrict,
  status text not null default 'active',
  next_action text not null default 'CREATE_FIRST_COMPETITION',
  first_launcher_kind text,
  first_launcher_aggregate_id uuid,
  first_competition_id uuid references public.pachanga_competitions(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  completed_at timestamptz,
  revision bigint not null default 1,
  server_sequence bigint not null unique default nextval('private.pachanga_organizer_access_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (organizer_kind in ('TEAM', 'CLUB')),
  check (
    (organizer_kind = 'TEAM' and organizer_group_id is not null and organizer_club_id is null)
    or (organizer_kind = 'CLUB' and organizer_group_id is null and organizer_club_id is not null)
  ),
  check (origin in ('APPLICATION', 'EXISTING_GRANT', 'PLATFORM_INVITATION')),
  check (status in ('active', 'completed', 'archived')),
  check (next_action in (
    'COMPLETE_ORGANIZER_PROFILE', 'WAIT_FOR_REVIEW', 'RESPOND_INFORMATION',
    'ACCESS_APPROVED', 'CREATE_FIRST_COMPETITION', 'CONTINUE_COMPETITION_DRAFT',
    'INVITE_TEAMS', 'CONFIGURE_RULES', 'GENERATE_SCHEDULE', 'PREPARE_DRAW',
    'PUBLISH_COMPETITION', 'PREPARE_FIRST_MATCH', 'ONBOARDING_COMPLETE'
  )),
  check (first_launcher_kind is null or first_launcher_kind in ('LEAGUE_WIZARD', 'TOURNAMENT')),
  check ((first_launcher_kind is null and first_launcher_aggregate_id is null)
    or (first_launcher_kind is not null and first_launcher_aggregate_id is not null)),
  check ((status = 'completed' and completed_at is not null) or status <> 'completed'),
  check (revision >= 1)
);

create table private.pachanga_organizer_onboarding_checkpoints_v1 (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references private.pachanga_organizer_onboarding_workspaces_v1(id) on delete restrict,
  checkpoint_key text not null,
  status text not null default 'pending',
  evidence_type text,
  evidence_id uuid,
  evidence_revision bigint,
  server_sequence bigint not null unique default nextval('private.pachanga_organizer_access_sequence'),
  confirmed_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  unique (workspace_id, checkpoint_key),
  check (checkpoint_key in (
    'ORGANIZER_IDENTITY', 'ORGANIZER_ACTIVE', 'ORGANIZER_ACCESS', 'ORGANIZER_PROFILE',
    'FIRST_COMPETITION_DRAFT', 'VALID_RULE_REVISION', 'PARTICIPANTS',
    'SCHEDULE_OR_DRAW', 'PUBLICATION', 'FIRST_MATCH_PREPARED'
  )),
  check (status in ('pending', 'complete', 'not_applicable')),
  check (evidence_revision is null or evidence_revision >= 0),
  check ((status = 'pending' and confirmed_at is null) or status <> 'pending')
);

create table private.pachanga_organizer_onboarding_events_v1 (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  workspace_id uuid not null references private.pachanga_organizer_onboarding_workspaces_v1(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  workspace_revision bigint not null,
  event_payload jsonb not null default '{}'::jsonb,
  server_sequence bigint not null unique,
  confirmed_at timestamptz not null default clock_timestamp(),
  check (workspace_revision >= 1),
  check (jsonb_typeof(event_payload) = 'object')
);

create unique index pachanga_organizer_onboarding_active_team_idx
  on private.pachanga_organizer_onboarding_workspaces_v1(organizer_group_id)
  where organizer_kind = 'TEAM' and status in ('active', 'completed');
create unique index pachanga_organizer_onboarding_active_club_idx
  on private.pachanga_organizer_onboarding_workspaces_v1(organizer_club_id)
  where organizer_kind = 'CLUB' and status in ('active', 'completed');
create unique index pachanga_organizer_onboarding_application_idx
  on private.pachanga_organizer_onboarding_workspaces_v1(source_application_id)
  where source_application_id is not null;
create index pachanga_organizer_onboarding_checkpoint_workspace_idx
  on private.pachanga_organizer_onboarding_checkpoints_v1(workspace_id, server_sequence, id);
create index pachanga_organizer_onboarding_event_workspace_idx
  on private.pachanga_organizer_onboarding_events_v1(workspace_id, server_sequence desc, id);

create or replace function private.pachanga_organizer_onboarding_snapshot_v1(target_workspace_id uuid)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', workspaces.id,
    'organizerKind', workspaces.organizer_kind,
    'organizerId', coalesce(workspaces.organizer_group_id, workspaces.organizer_club_id),
    'origin', workspaces.origin,
    'sourceApplicationId', workspaces.source_application_id,
    'sourceAccessGrantId', workspaces.source_access_grant_id,
    'status', workspaces.status,
    'nextAction', workspaces.next_action,
    'firstLauncherKind', workspaces.first_launcher_kind,
    'firstLauncherAggregateId', workspaces.first_launcher_aggregate_id,
    'firstCompetitionId', workspaces.first_competition_id,
    'revision', workspaces.revision,
    'serverSequence', workspaces.server_sequence,
    'updatedAt', workspaces.updated_at,
    'checkpoints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', checkpoints.checkpoint_key,
        'status', checkpoints.status,
        'evidenceType', checkpoints.evidence_type,
        'evidenceId', checkpoints.evidence_id,
        'evidenceRevision', checkpoints.evidence_revision,
        'confirmedAt', checkpoints.confirmed_at,
        'serverSequence', checkpoints.server_sequence
      ) order by array_position(array[
        'ORGANIZER_IDENTITY', 'ORGANIZER_ACTIVE', 'ORGANIZER_ACCESS', 'ORGANIZER_PROFILE',
        'FIRST_COMPETITION_DRAFT', 'VALID_RULE_REVISION', 'PARTICIPANTS',
        'SCHEDULE_OR_DRAW', 'PUBLICATION', 'FIRST_MATCH_PREPARED'
      ]::text[], checkpoints.checkpoint_key), checkpoints.id)
      from private.pachanga_organizer_onboarding_checkpoints_v1 checkpoints
      where checkpoints.workspace_id = workspaces.id
    ), '[]'::jsonb)
  )
  from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
  where workspaces.id = target_workspace_id;
$$;

create or replace function private.pachanga_refresh_organizer_onboarding_v1(
  target_workspace_id uuid,
  target_actor_id uuid,
  target_reason text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare workspace private.pachanga_organizer_onboarding_workspaces_v1%rowtype;
declare organizer_id uuid;
declare competition public.pachanga_competitions%rowtype;
declare has_identity boolean := false;
declare organizer_active boolean := false;
declare has_access boolean := false;
declare profile_ready boolean := false;
declare has_draft boolean := false;
declare has_rules boolean := false;
declare has_participants boolean := false;
declare has_schedule_or_draw boolean := false;
declare has_publication boolean := false;
declare has_first_match boolean := false;
declare derived_next_action text;
declare sequence_value bigint;
declare checkpoint record;
begin
  select * into workspace
  from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
  where workspaces.id = target_workspace_id for update;
  if not found then raise exception 'ORGANIZER_ONBOARDING_NOT_FOUND' using errcode = 'P0002'; end if;
  organizer_id := coalesce(workspace.organizer_group_id, workspace.organizer_club_id);
  if workspace.organizer_kind = 'TEAM' then
    select true,
      length(trim(coalesce(groups.payload ->> 'name', groups.payload ->> 'teamName', ''))) >= 3,
      length(trim(coalesce(groups.payload ->> 'name', groups.payload ->> 'teamName', ''))) >= 3
    into organizer_active, has_identity, profile_ready
    from public.pachanga_groups groups where groups.id = organizer_id;
  else
    select clubs.operational_status = 'active', length(trim(clubs.name)) >= 3,
      length(trim(clubs.description)) >= 3 or clubs.visibility in ('unlisted', 'public')
    into organizer_active, has_identity, profile_ready
    from public.pachanga_clubs clubs where clubs.id = organizer_id;
  end if;
  has_access := coalesce(private.pachanga_organizer_billing_creation_allowed_v1(
    workspace.organizer_kind, organizer_id
  ), false);
  if workspace.first_competition_id is not null then
    select * into competition from public.pachanga_competitions competitions
    where competitions.id = workspace.first_competition_id;
  elsif workspace.first_launcher_kind = 'TOURNAMENT' then
    select * into competition from public.pachanga_competitions competitions
    where competitions.id = workspace.first_launcher_aggregate_id;
  else
    select * into competition from public.pachanga_competitions competitions
    where competitions.organizer_kind = workspace.organizer_kind
      and (
        (workspace.organizer_kind = 'TEAM' and competitions.organizer_group_id = organizer_id)
        or (workspace.organizer_kind = 'CLUB' and competitions.organizer_club_id = organizer_id)
      )
      and competitions.status <> 'cancelled'
    order by competitions.server_sequence desc, competitions.id desc limit 1;
  end if;
  has_draft := competition.id is not null or workspace.first_launcher_aggregate_id is not null;
  if competition.id is not null then
    has_rules := exists (
      select 1 from public.pachanga_competition_rule_sets sets
      join public.pachanga_competition_rule_revisions revisions on revisions.rule_set_id = sets.id
      where sets.competition_id = competition.id
        and revisions.status in ('validated', 'published', 'frozen')
    );
    has_participants := exists (
      select 1 from public.pachanga_competition_entries entries
      where entries.competition_id = competition.id
        and entries.status in ('submitted', 'invited', 'accepted', 'active', 'completed')
    );
    has_schedule_or_draw := exists (
      select 1 from public.pachanga_competition_rounds rounds
      where rounds.competition_id = competition.id
    ) or exists (
      select 1 from public.pachanga_competition_draw_plans plans
      where plans.competition_id = competition.id
        and plans.status in ('generated', 'validated', 'published')
    );
    has_publication := competition.visibility = 'private' or exists (
      select 1 from public.pachanga_competition_publications publications
      where publications.competition_id = competition.id
        and publications.lifecycle_status = 'published'
    );
    has_first_match := exists (
      select 1 from public.pachanga_competition_match_contexts contexts
      where contexts.competition_id = competition.id
    );
  end if;
  if not has_identity or not organizer_active or not profile_ready then
    derived_next_action := 'COMPLETE_ORGANIZER_PROFILE';
  elsif not has_access then derived_next_action := 'WAIT_FOR_REVIEW';
  elsif not has_draft then derived_next_action := 'CREATE_FIRST_COMPETITION';
  elsif competition.id is null then derived_next_action := 'CONTINUE_COMPETITION_DRAFT';
  elsif not has_rules then derived_next_action := 'CONFIGURE_RULES';
  elsif not has_participants then derived_next_action := 'INVITE_TEAMS';
  elsif not has_schedule_or_draw then derived_next_action := case competition.competition_type
    when 'TOURNAMENT' then 'PREPARE_DRAW' else 'GENERATE_SCHEDULE' end;
  elsif not has_publication then derived_next_action := 'PUBLISH_COMPETITION';
  elsif not has_first_match then derived_next_action := 'PREPARE_FIRST_MATCH';
  else derived_next_action := 'ONBOARDING_COMPLETE'; end if;
  for checkpoint in
    select * from (values
      ('ORGANIZER_IDENTITY', has_identity, 'organizer', organizer_id, 1::bigint),
      ('ORGANIZER_ACTIVE', organizer_active, 'organizer', organizer_id, 1::bigint),
      ('ORGANIZER_ACCESS', has_access, 'access_grant', workspace.source_access_grant_id, null::bigint),
      ('ORGANIZER_PROFILE', profile_ready, 'organizer_profile', organizer_id, 1::bigint),
      ('FIRST_COMPETITION_DRAFT', has_draft, case when competition.id is null then 'wizard' else 'competition' end,
        coalesce(competition.id, workspace.first_launcher_aggregate_id), coalesce(competition.revision, 1)),
      ('VALID_RULE_REVISION', has_rules, 'competition', competition.id, competition.revision),
      ('PARTICIPANTS', has_participants, 'competition', competition.id, competition.revision),
      ('SCHEDULE_OR_DRAW', has_schedule_or_draw, 'competition', competition.id, competition.revision),
      ('PUBLICATION', has_publication, 'competition', competition.id, competition.revision),
      ('FIRST_MATCH_PREPARED', has_first_match, 'competition', competition.id, competition.revision)
    ) values_table(checkpoint_key, completed, evidence_type, evidence_id, evidence_revision)
  loop
    sequence_value := nextval('private.pachanga_organizer_access_sequence');
    insert into private.pachanga_organizer_onboarding_checkpoints_v1(
      workspace_id, checkpoint_key, status, evidence_type, evidence_id,
      evidence_revision, server_sequence, confirmed_at, updated_at
    ) values (
      workspace.id, checkpoint.checkpoint_key,
      case when checkpoint.completed then 'complete' else 'pending' end,
      case when checkpoint.completed then checkpoint.evidence_type end,
      case when checkpoint.completed then checkpoint.evidence_id end,
      case when checkpoint.completed then checkpoint.evidence_revision end,
      sequence_value, case when checkpoint.completed then clock_timestamp() end, clock_timestamp()
    ) on conflict (workspace_id, checkpoint_key) do update set
      status = excluded.status,
      evidence_type = excluded.evidence_type,
      evidence_id = excluded.evidence_id,
      evidence_revision = excluded.evidence_revision,
      server_sequence = excluded.server_sequence,
      confirmed_at = case
        when excluded.status = 'complete' then coalesce(private.pachanga_organizer_onboarding_checkpoints_v1.confirmed_at, excluded.confirmed_at)
        else null end,
      updated_at = excluded.updated_at;
  end loop;
  if workspace.next_action <> derived_next_action
     or (derived_next_action = 'ONBOARDING_COMPLETE' and workspace.status <> 'completed') then
    sequence_value := nextval('private.pachanga_organizer_access_sequence');
    update private.pachanga_organizer_onboarding_workspaces_v1 workspaces set
      next_action = derived_next_action,
      status = case when derived_next_action = 'ONBOARDING_COMPLETE' then 'completed' else workspaces.status end,
      completed_at = case when derived_next_action = 'ONBOARDING_COMPLETE'
        then coalesce(workspaces.completed_at, clock_timestamp()) else workspaces.completed_at end,
      revision = workspaces.revision + 1,
      server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where workspaces.id = workspace.id;
  end if;
  return private.pachanga_organizer_onboarding_snapshot_v1(workspace.id);
end;
$$;

create or replace function private.pachanga_ensure_organizer_onboarding_v1(
  target_application_id uuid,
  target_decision_id uuid,
  target_access_grant_id uuid,
  target_actor_id uuid
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare application private.pachanga_organizer_access_applications_v1%rowtype;
declare access private.pachanga_organizer_access_grants_v1%rowtype;
declare workspace private.pachanga_organizer_onboarding_workspaces_v1%rowtype;
declare organizer_id uuid;
begin
  select * into application from private.pachanga_organizer_access_applications_v1
  where id = target_application_id;
  select * into access from private.pachanga_organizer_access_grants_v1
  where id = target_access_grant_id and status in ('active', 'grace', 'continuity');
  if application.id is null or access.id is null then
    raise exception 'ORGANIZER_ONBOARDING_ACCESS_REQUIRED' using errcode = '42501';
  end if;
  organizer_id := coalesce(application.organizer_group_id, application.organizer_club_id);
  select * into workspace from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
  where workspaces.organizer_kind = application.organizer_kind
    and (
      (application.organizer_kind = 'TEAM' and workspaces.organizer_group_id = organizer_id)
      or (application.organizer_kind = 'CLUB' and workspaces.organizer_club_id = organizer_id)
    ) and workspaces.status in ('active', 'completed')
  order by workspaces.server_sequence desc, workspaces.id desc limit 1;
  if not found then
    insert into private.pachanga_organizer_onboarding_workspaces_v1(
      organizer_kind, organizer_group_id, organizer_club_id, origin,
      source_application_id, source_decision_id, source_access_grant_id,
      status, next_action, created_by
    ) values (
      application.organizer_kind,
      case when application.organizer_kind = 'TEAM' then organizer_id end,
      case when application.organizer_kind = 'CLUB' then organizer_id end,
      'APPLICATION', application.id, target_decision_id, access.id,
      'active', 'ACCESS_APPROVED', target_actor_id
    ) returning * into workspace;
  elsif workspace.source_application_id is null then
    update private.pachanga_organizer_onboarding_workspaces_v1 workspaces set
      origin = 'APPLICATION',
      source_application_id = application.id,
      source_decision_id = target_decision_id,
      source_access_grant_id = access.id,
      revision = workspaces.revision + 1,
      server_sequence = nextval('private.pachanga_organizer_access_sequence'),
      updated_at = clock_timestamp()
    where workspaces.id = workspace.id
    returning * into workspace;
  end if;
  perform private.pachanga_refresh_organizer_onboarding_v1(workspace.id, target_actor_id, 'workspace.created');
  return workspace.id;
end;
$$;

revoke all on table private.pachanga_organizer_onboarding_workspaces_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_onboarding_checkpoints_v1 from public, anon, authenticated;
revoke all on table private.pachanga_organizer_onboarding_events_v1 from public, anon, authenticated;
grant all on table private.pachanga_organizer_onboarding_workspaces_v1 to service_role;
grant all on table private.pachanga_organizer_onboarding_checkpoints_v1 to service_role;
grant all on table private.pachanga_organizer_onboarding_events_v1 to service_role;
revoke all on function private.pachanga_organizer_onboarding_snapshot_v1(uuid) from public, anon, authenticated;
revoke all on function private.pachanga_refresh_organizer_onboarding_v1(uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_ensure_organizer_onboarding_v1(uuid, uuid, uuid, uuid) from public, anon, authenticated;

comment on table private.pachanga_organizer_onboarding_workspaces_v1 is
  'Derived guided workspace. It cannot be used as an authorization source.';
