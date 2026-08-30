-- Wave 8B: safe Team projections, health and Platform Control Center read models.

set lock_timeout = '5s';
set statement_timeout = '5min';

create or replace function private.pachanga_team_operational_safe_projection_v1(
  target_group_id uuid,
  include_owner_detail boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'kind', 'TeamOperationalState',
    'groupId', groups.id,
    'teamCode', groups.team_code,
    'teamName', groups.name,
    'lifecycle', states.lifecycle_status,
    'enforcement', states.enforcement_status,
    'effectiveStatus', states.effective_status,
    'availabilityLabel', case states.effective_status
      when 'LIMITED' then 'Disponibilidad limitada'
      when 'SUSPENDED' then 'No disponible actualmente'
      when 'ARCHIVED' then 'Equipo archivado'
      else null
    end,
    'publicMessage', states.public_message,
    'effectiveFrom', states.effective_from,
    'effectiveUntil', states.effective_until,
    'continuityPolicy', case when include_owner_detail then states.continuity_policy else null end,
    'restrictions', case when include_owner_detail
      then private.pachanga_team_operational_restrictions_snapshot_v1(target_group_id)
      else '[]'::jsonb end,
    'appeal', case when include_owner_detail then (
      select jsonb_build_object(
        'id', appeals.id,
        'status', appeals.status,
        'subjectRevision', appeals.subject_revision,
        'requestedOutcome', appeals.requested_outcome,
        'ownerMessage', appeals.owner_message,
        'safeResolutionMessage', appeals.safe_resolution_message,
        'deadlineAt', appeals.deadline_at,
        'submittedAt', appeals.submitted_at,
        'resolvedAt', appeals.resolved_at,
        'revision', appeals.revision,
        'serverSequence', appeals.server_sequence
      )
      from private.pachanga_team_operational_appeals_v1 appeals
      where appeals.group_id = target_group_id
      order by appeals.server_sequence desc, appeals.id desc
      limit 1
    ) else null end,
    'impact', case when include_owner_detail then jsonb_build_object(
      'marketListings', (
        select count(*) from public.pachanga_open_matches matches
        where matches.source_group_id = target_group_id and matches.active
      ),
      'openChallenges', (
        select count(*) from public.pachanga_team_challenges challenges
        where target_group_id in (challenges.sender_group_id, challenges.receiver_group_id)
          and challenges.status in ('proposed','changes_proposed','accepted')
      ),
      'activeCompetitionEntries', (
        select count(*) from public.pachanga_competition_entries entries
        where entries.team_id = target_group_id and entries.status in ('accepted','active')
      ),
      'blockedOrganizerApplications', (
        select count(*) from private.pachanga_organizer_access_applications_v1 applications
        where applications.organizer_kind = 'TEAM'
          and applications.organizer_group_id = target_group_id
          and applications.operational_blocked_at is not null
          and applications.status in ('draft','submitted','under_review','needs_information')
      )
    ) else null end,
    'revision', states.current_revision,
    'serverSequence', states.server_sequence,
    'updatedAt', states.updated_at
  )
  from private.pachanga_team_operational_states_v1 states
  join public.pachanga_groups groups on groups.id = states.group_id
  where states.group_id = target_group_id;
$$;

create or replace function public.get_pachanga_team_operational_state_v1(
  target_group_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare is_owner boolean;
declare is_member boolean;
declare is_platform boolean;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select exists(select 1 from public.pachanga_groups groups where groups.id = target_group_id and groups.owner_id = actor_id)
    into is_owner;
  select exists(select 1 from public.pachanga_group_members members where members.group_id = target_group_id and members.user_id = actor_id)
    into is_member;
  is_platform := private.pachanga_platform_role_for_user_v1(actor_id) is not null;
  if not (is_owner or is_member or is_platform) then
    raise exception 'TEAM_MEMBERSHIP_REQUIRED' using errcode = '42501';
  end if;
  return private.pachanga_team_operational_safe_projection_v1(
    target_group_id, is_owner or is_platform
  );
end;
$$;

create or replace function public.get_my_pachanga_team_operational_states_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with visible_teams as (
    select groups.id as group_id,
      case when groups.owner_id = (select auth.uid()) then 'owner'
        else coalesce(members.role, 'member') end as member_role,
      groups.owner_id = (select auth.uid()) as is_owner
    from public.pachanga_groups groups
    left join public.pachanga_group_members members
      on members.group_id = groups.id and members.user_id = (select auth.uid())
    where (select auth.uid()) is not null
      and (groups.owner_id = (select auth.uid()) or members.user_id is not null)
  )
  select jsonb_build_object(
    'kind', 'MyTeamOperationalStates',
    'items', coalesce(jsonb_agg(
      private.pachanga_team_operational_safe_projection_v1(visible_teams.group_id, visible_teams.is_owner)
      || jsonb_build_object('role', visible_teams.member_role, 'isOwner', visible_teams.is_owner)
      order by visible_teams.is_owner desc, visible_teams.group_id
    ), '[]'::jsonb),
    'serverTime', clock_timestamp()
  )
  from visible_teams;
$$;

create or replace function public.get_public_pachanga_team_operational_state_v1(
  target_group_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_team_operational_settings_v1%rowtype;
declare projection jsonb;
begin
  select * into settings from private.pachanga_team_operational_settings_v1 where singleton;
  if not settings.public_projection_enabled then return null; end if;
  projection := private.pachanga_team_operational_safe_projection_v1(target_group_id, false);
  if projection is null then return null; end if;
  return projection - array['continuityPolicy','restrictions','appeal','impact'];
end;
$$;

create or replace function private.pachanga_team_operational_health_v1(
  target_group_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare issues jsonb := '[]'::jsonb;
declare issue_count integer;
declare state_row private.pachanga_team_operational_states_v1%rowtype;
begin
  select * into state_row from private.pachanga_team_operational_states_v1 states where states.group_id = target_group_id;
  if not found then
    return jsonb_build_object('status','ERROR','issues',jsonb_build_array('STATE_MISSING'),'nextAction','INITIALIZE_TEAM');
  end if;
  if exists (
    select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
    where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE'
      and restrictions.effective_until is not null and restrictions.effective_until <= clock_timestamp()
  ) then issues := issues || '"EXPIRED_RESTRICTION_NOT_CLOSED"'::jsonb; end if;
  if state_row.enforcement_status = 'SUSPENDED' and state_row.continuity_policy is null then
    issues := issues || '"SUSPENSION_WITHOUT_CONTINUITY"'::jsonb;
  end if;
  if state_row.enforcement_status = 'SUSPENDED' and not exists (
    select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
    where restrictions.group_id = target_group_id and restrictions.status = 'ACTIVE'
  ) then issues := issues || '"SUSPENSION_WITHOUT_ACTIVE_SCOPE"'::jsonb; end if;
  if state_row.current_revision <> coalesce((
    select max(revisions.revision) from private.pachanga_team_operational_state_revisions_v1 revisions
    where revisions.group_id = target_group_id
  ), 0) then issues := issues || '"REVISION_MISMATCH"'::jsonb; end if;
  if exists (
    select 1 from private.pachanga_organizer_access_grants_v1 grants
    where grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_group_id
      and grants.status in ('active','grace','continuity')
      and not private.pachanga_team_operational_scope_allowed_v1(target_group_id, 'COMPETITION_ORGANIZER')
  ) then issues := issues || '"ACTIVE_GRANT_OPERATIONALLY_BLOCKED"'::jsonb; end if;
  if exists (
    select 1 from public.pachanga_competition_entries entries
    where entries.team_id = target_group_id and entries.status in ('accepted','active')
      and not private.pachanga_team_operational_scope_allowed_v1(
        target_group_id, 'EXISTING_COMPETITION_OPERATIONS', entries.competition_id
      )
  ) then issues := issues || '"ACTIVE_COMPETITION_ENTRY_AFFECTED"'::jsonb; end if;
  if exists (
    select 1 from public.pachanga_open_matches matches
    where matches.source_group_id = target_group_id and matches.active
      and not private.pachanga_team_operational_scope_allowed_v1(target_group_id, 'MARKETPLACE')
  ) then issues := issues || '"PUBLIC_MARKET_LISTING_INCOMPATIBLE"'::jsonb; end if;
  if exists (
    select 1 from public.pachanga_team_challenges challenges
    where target_group_id in (challenges.sender_group_id, challenges.receiver_group_id)
      and challenges.status in ('proposed','changes_proposed')
      and not private.pachanga_team_operational_scope_allowed_v1(target_group_id, 'SOCIAL_CHALLENGES')
  ) then issues := issues || '"OPEN_CHALLENGE_AFFECTED"'::jsonb; end if;
  if not exists (select 1 from auth.users users where users.id = (select groups.owner_id from public.pachanga_groups groups where groups.id = target_group_id)) then
    issues := issues || '"OWNER_MISSING"'::jsonb;
  end if;
  issue_count := jsonb_array_length(issues);
  return jsonb_build_object(
    'status', case when issue_count = 0 then 'HEALTHY' else 'ATTENTION' end,
    'issues', issues,
    'issueCount', issue_count,
    'nextAction', case
      when issues ? 'EXPIRED_RESTRICTION_NOT_CLOSED' then 'RUN_EXPIRY_WORKER'
      when issues ? 'REVISION_MISMATCH' then 'REVIEW_REVISION_LINEAGE'
      when issue_count > 0 then 'REVIEW_TEAM_IMPACT'
      else 'NONE'
    end
  );
end;
$$;

create or replace function public.list_pachanga_platform_team_operational_states_v1(
  filters jsonb default '{}'::jsonb,
  page_limit integer default 50,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text;
declare normalized_status text := upper(nullif(trim(filters ->> 'status'), ''));
begin
  actor_role := private.pachanga_platform_require_v1('teams.operational.read');
  if page_limit not between 1 and 200 or page_offset not between 0 and 1000000 then
    raise exception 'PAGINATION_OUT_OF_RANGE' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'kind', 'PlatformTeamOperationalList',
    'actorRole', actor_role,
    'items', coalesce((
      select jsonb_agg(item order by (item ->> 'serverSequence')::bigint desc, item ->> 'groupId')
      from (
        select private.pachanga_team_operational_safe_projection_v1(states.group_id, true)
          || jsonb_build_object(
            'health', private.pachanga_team_operational_health_v1(states.group_id),
            'reviewOpen', exists(
              select 1 from private.pachanga_team_operational_reviews_v1 reviews
              where reviews.group_id = states.group_id and reviews.status in ('OPEN','NEEDS_INFORMATION')
            ),
            'appealOpen', exists(
              select 1 from private.pachanga_team_operational_appeals_v1 appeals
              where appeals.group_id = states.group_id and appeals.status in ('DRAFT','SUBMITTED','UNDER_REVIEW')
            )
          ) as item
        from private.pachanga_team_operational_states_v1 states
        join public.pachanga_groups groups on groups.id = states.group_id
        where (
          normalized_status is null
          or (normalized_status in ('ACTIVE','UNDER_REVIEW','LIMITED','SUSPENDED','ARCHIVED')
            and states.effective_status = normalized_status)
          or (normalized_status = 'EXPIRING' and (
            (states.effective_until > clock_timestamp() and states.effective_until <= clock_timestamp() + interval '7 days')
            or exists (
              select 1 from private.pachanga_team_operational_restrictions_v1 expiring
              where expiring.group_id = states.group_id and expiring.status = 'ACTIVE'
                and expiring.effective_until > clock_timestamp()
                and expiring.effective_until <= clock_timestamp() + interval '7 days'
            )
          ))
          or (normalized_status = 'APPEALED' and exists (
            select 1 from private.pachanga_team_operational_appeals_v1 appeals
            where appeals.group_id = states.group_id and appeals.status in ('DRAFT','SUBMITTED','UNDER_REVIEW')
          ))
          or (normalized_status = 'COMPETITION_AFFECTED' and exists (
            select 1 from public.pachanga_competition_entries entries
            where entries.team_id = states.group_id and entries.status in ('accepted','active')
              and (
                states.effective_status in ('LIMITED','SUSPENDED','ARCHIVED')
                or not private.pachanga_team_operational_scope_allowed_v1(
                  states.group_id, 'EXISTING_COMPETITION_OPERATIONS', entries.competition_id
                )
              )
          ))
        )
          and (not (filters ? 'query') or groups.name ilike '%' || left(filters ->> 'query', 120) || '%'
            or groups.team_code ilike '%' || left(filters ->> 'query', 120) || '%')
        order by states.server_sequence desc, states.group_id
        limit page_limit offset page_offset
      ) page
    ), '[]'::jsonb),
    'total', (
      select count(*) from private.pachanga_team_operational_states_v1 states
      join public.pachanga_groups groups on groups.id = states.group_id
      where (
        normalized_status is null
        or (normalized_status in ('ACTIVE','UNDER_REVIEW','LIMITED','SUSPENDED','ARCHIVED')
          and states.effective_status = normalized_status)
        or (normalized_status = 'EXPIRING' and (
          (states.effective_until > clock_timestamp() and states.effective_until <= clock_timestamp() + interval '7 days')
          or exists (
            select 1 from private.pachanga_team_operational_restrictions_v1 expiring
            where expiring.group_id = states.group_id and expiring.status = 'ACTIVE'
              and expiring.effective_until > clock_timestamp()
              and expiring.effective_until <= clock_timestamp() + interval '7 days'
          )
        ))
        or (normalized_status = 'APPEALED' and exists (
          select 1 from private.pachanga_team_operational_appeals_v1 appeals
          where appeals.group_id = states.group_id and appeals.status in ('DRAFT','SUBMITTED','UNDER_REVIEW')
        ))
        or (normalized_status = 'COMPETITION_AFFECTED' and exists (
          select 1 from public.pachanga_competition_entries entries
          where entries.team_id = states.group_id and entries.status in ('accepted','active')
            and (
              states.effective_status in ('LIMITED','SUSPENDED','ARCHIVED')
              or not private.pachanga_team_operational_scope_allowed_v1(
                states.group_id, 'EXISTING_COMPETITION_OPERATIONS', entries.competition_id
              )
            )
        ))
      )
        and (not (filters ? 'query') or groups.name ilike '%' || left(filters ->> 'query', 120) || '%'
          or groups.team_code ilike '%' || left(filters ->> 'query', 120) || '%')
    ),
    'pageLimit', page_limit,
    'pageOffset', page_offset,
    'serverTime', clock_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_platform_team_operational_detail_v1(
  target_group_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text;
declare capabilities jsonb;
declare may_review boolean;
declare may_enforce boolean;
begin
  actor_role := private.pachanga_platform_require_v1('teams.operational.read');
  capabilities := private.pachanga_platform_capabilities_v1(actor_role);
  may_review := capabilities ? 'teams.operational.review';
  may_enforce := capabilities ? 'teams.operational.enforce';
  return private.pachanga_team_operational_safe_projection_v1(target_group_id, true)
    || jsonb_build_object(
      'health', private.pachanga_team_operational_health_v1(target_group_id),
      'reviews', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', reviews.id,
          'status', reviews.status,
          'reasonCode', reviews.reason_code,
          'safeMessage', reviews.safe_message,
          'privateNote', case when may_review then reviews.private_note else null end,
          'evidence', case when may_review then reviews.evidence else null end,
          'openedAt', reviews.opened_at,
          'closedAt', reviews.closed_at,
          'revision', reviews.revision,
          'serverSequence', reviews.server_sequence
        ) order by reviews.server_sequence desc, reviews.id)
        from private.pachanga_team_operational_reviews_v1 reviews
        where reviews.group_id = target_group_id
      ), '[]'::jsonb),
      'events', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', events.id,
          'eventKind', events.event_kind,
          'aggregateRevision', events.aggregate_revision,
          'reasonCode', events.reason_code,
          'serverSequence', events.server_sequence,
          'confirmedAt', events.confirmed_at
        ) order by events.server_sequence desc, events.id)
        from (
          select * from private.pachanga_team_operational_events_v1 events
          where events.group_id = target_group_id
          order by events.server_sequence desc, events.id desc limit 100
        ) events
      ), '[]'::jsonb),
      'receipts', coalesce((
        select jsonb_agg(jsonb_build_object(
          'operationId', receipts.operation_id,
          'action', receipts.action,
          'actorKind', receipts.actor_kind,
          'expectedRevision', receipts.expected_revision,
          'confirmedRevision', receipts.confirmed_revision,
          'serverSequence', receipts.server_sequence,
          'createdAt', receipts.created_at
        ) order by receipts.server_sequence desc, receipts.operation_id)
        from (
          select * from private.pachanga_team_operational_operation_receipts_v1 receipts
          where receipts.group_id = target_group_id
          order by receipts.server_sequence desc, receipts.operation_id desc limit 100
        ) receipts
      ), '[]'::jsonb),
      'continuityDecisions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', decisions.id,
          'competitionId', decisions.competition_id,
          'policy', decisions.policy,
          'sourceRevision', decisions.source_revision,
          'reasonCode', decisions.reason_code,
          'publicMessage', decisions.public_message,
          'privateNote', case when may_enforce then decisions.private_note else null end,
          'effectiveFrom', decisions.effective_from,
          'effectiveUntil', decisions.effective_until,
          'serverSequence', decisions.server_sequence
        ) order by decisions.server_sequence desc, decisions.id)
        from private.pachanga_team_operational_continuity_decisions_v1 decisions
        where decisions.group_id = target_group_id
      ), '[]'::jsonb),
      'affectedOrganizerApplications', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', applications.id,
          'status', applications.status,
          'operationalBlockedAt', applications.operational_blocked_at,
          'operationalBlockedRevision', applications.operational_blocked_revision,
          'operationalBlockedCode', applications.operational_blocked_code
        ) order by applications.server_sequence desc, applications.id)
        from private.pachanga_organizer_access_applications_v1 applications
        where applications.organizer_kind = 'TEAM'
          and applications.organizer_group_id = target_group_id
          and applications.operational_blocked_at is not null
      ), '[]'::jsonb),
      'affectedRegistrationRequests', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', requests.id,
          'competitionId', requests.competition_id,
          'status', requests.status,
          'operationalBlockedAt', requests.operational_blocked_at,
          'operationalBlockedRevision', requests.operational_blocked_revision,
          'operationalBlockedCode', requests.operational_blocked_code,
          'serverSequence', requests.server_sequence
        ) order by requests.server_sequence desc, requests.id)
        from public.pachanga_competition_registration_requests requests
        where requests.team_id = target_group_id
          and requests.operational_blocked_at is not null
      ), '[]'::jsonb),
      'affectedCompetitionEntries', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', entries.id,
          'competitionId', entries.competition_id,
          'status', entries.status,
          'continuityPolicy', private.pachanga_team_operational_continuity_for_competition_v1(
            target_group_id, entries.competition_id
          )
        ) order by entries.server_sequence desc, entries.id)
        from public.pachanga_competition_entries entries
        where entries.team_id = target_group_id and entries.status in ('accepted','active')
      ), '[]'::jsonb)
    );
end;
$$;

create or replace function public.command_pachanga_team_operational_settings_v1(
  operation_id uuid,
  expected_revision bigint,
  payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare actor_role text;
declare settings private.pachanga_team_operational_settings_v1%rowtype;
declare existing private.pachanga_platform_admin_action_ledger%rowtype;
declare before_state jsonb;
declare response jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('flags.write');
  perform set_config('pachanga.team_operational_authority', 'on', true);
  if payload - array[
    'foundationEnabled','enforcementEnabled','restrictionsEnabled','continuityEnabled',
    'appealsEnabled','crossProductGuardsEnabled','publicProjectionEnabled',
    'demoWorldV31Enabled','reason'
  ] <> '{}'::jsonb then
    raise exception 'TEAM_OPERATIONAL_SETTINGS_FIELD_NOT_ALLOWED' using errcode = '22023';
  end if;
  select * into existing from private.pachanga_platform_admin_action_ledger ledger
  where ledger.operation_id = command_pachanga_team_operational_settings_v1.operation_id;
  if found then
    if existing.action <> 'team_operational.settings' then
      raise exception 'OPERATION_ID_REUSED' using errcode = '23505';
    end if;
    return existing.response;
  end if;
  select * into strict settings from private.pachanga_team_operational_settings_v1 where singleton for update;
  if settings.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  before_state := to_jsonb(settings) - array['updated_by'];
  update private.pachanga_team_operational_settings_v1 current_settings set
    foundation_enabled = coalesce((payload ->> 'foundationEnabled')::boolean, current_settings.foundation_enabled),
    enforcement_enabled = coalesce((payload ->> 'enforcementEnabled')::boolean, current_settings.enforcement_enabled),
    restrictions_enabled = coalesce((payload ->> 'restrictionsEnabled')::boolean, current_settings.restrictions_enabled),
    continuity_enabled = coalesce((payload ->> 'continuityEnabled')::boolean, current_settings.continuity_enabled),
    appeals_enabled = coalesce((payload ->> 'appealsEnabled')::boolean, current_settings.appeals_enabled),
    cross_product_guards_enabled = coalesce((payload ->> 'crossProductGuardsEnabled')::boolean, current_settings.cross_product_guards_enabled),
    public_projection_enabled = coalesce((payload ->> 'publicProjectionEnabled')::boolean, current_settings.public_projection_enabled),
    demo_world_v31_enabled = coalesce((payload ->> 'demoWorldV31Enabled')::boolean, current_settings.demo_world_v31_enabled),
    revision = current_settings.revision + 1,
    server_sequence = nextval('private.pachanga_team_operational_sequence_v1'),
    updated_by = actor_id,
    updated_at = clock_timestamp()
  where singleton
  returning * into settings;
  response := jsonb_build_object(
    'kind', 'TeamOperationalSettings',
    'foundationEnabled', settings.foundation_enabled,
    'enforcementEnabled', settings.enforcement_enabled,
    'restrictionsEnabled', settings.restrictions_enabled,
    'continuityEnabled', settings.continuity_enabled,
    'appealsEnabled', settings.appeals_enabled,
    'crossProductGuardsEnabled', settings.cross_product_guards_enabled,
    'publicProjectionEnabled', settings.public_projection_enabled,
    'demoWorldV31Enabled', settings.demo_world_v31_enabled,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response
  ) values (
    operation_id, actor_id, actor_role, 'team_operational.settings',
    'team_operational_settings', 'singleton',
    left(coalesce(nullif(payload ->> 'reason',''), 'team operational settings'), 1200),
    before_state, response, response
  );
  return response;
end;
$$;

revoke all on function private.pachanga_team_operational_safe_projection_v1(uuid, boolean) from public, anon, authenticated;
revoke all on function private.pachanga_team_operational_health_v1(uuid) from public, anon, authenticated;

revoke all on function public.get_pachanga_team_operational_state_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_team_operational_state_v1(uuid) to authenticated, service_role;
revoke all on function public.get_my_pachanga_team_operational_states_v1() from public, anon;
grant execute on function public.get_my_pachanga_team_operational_states_v1() to authenticated, service_role;
revoke all on function public.get_public_pachanga_team_operational_state_v1(uuid) from public;
grant execute on function public.get_public_pachanga_team_operational_state_v1(uuid) to anon, authenticated, service_role;
revoke all on function public.list_pachanga_platform_team_operational_states_v1(jsonb, integer, integer) from public, anon;
grant execute on function public.list_pachanga_platform_team_operational_states_v1(jsonb, integer, integer) to authenticated, service_role;
revoke all on function public.get_pachanga_platform_team_operational_detail_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_platform_team_operational_detail_v1(uuid) to authenticated, service_role;
revoke all on function public.command_pachanga_team_operational_settings_v1(uuid, bigint, jsonb) from public, anon;
grant execute on function public.command_pachanga_team_operational_settings_v1(uuid, bigint, jsonb) to authenticated, service_role;
