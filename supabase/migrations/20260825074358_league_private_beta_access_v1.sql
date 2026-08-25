-- Pachangas IQ League Private Beta V1: canonical private reads and Realtime invalidation access.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_league_private_beta_actor_can_read_wizard_v1(
  target_wizard_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from private.pachanga_league_private_beta_wizards wizards
    where wizards.id = target_wizard_id
      and target_actor_id is not null
      and (
        wizards.created_by = target_actor_id
        or (
          wizards.organizer_kind = 'TEAM'
          and exists (
            select 1
            from public.pachanga_groups groups
            where groups.id = wizards.organizer_group_id
              and groups.owner_id = target_actor_id
          )
        )
        or (
          wizards.organizer_kind = 'CLUB'
          and private.pachanga_club_active_role_v1(
            wizards.organizer_club_id,
            target_actor_id
          ) in ('club_owner', 'club_competition_manager')
        )
      )
  );
$$;

create or replace function public.get_pachanga_league_private_beta_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'productKey', 'LEAGUE_PRIVATE_BETA_V1',
    'enabled', settings.league_private_beta_enabled,
    'creationEnabled', settings.league_private_beta_creation_enabled,
    'publicDiscoveryEnabled', false,
    'inviteOnly', true,
    'defaultTeamCap', settings.league_private_beta_default_team_cap,
    'standardMaximumTeams', 12,
    'absoluteMaximumTeams', 20,
    'maxActiveEditionsPerOrganizer',
      settings.league_private_beta_max_active_editions_per_organizer,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at,
    'unavailable', jsonb_build_array(
      'competition_discipline',
      'referee_assignments',
      'payments',
      'tournaments'
    )
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

create or replace function public.get_pachanga_league_private_beta_wizard_v1(
  target_wizard_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare snapshot jsonb;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not private.pachanga_league_private_beta_actor_can_read_wizard_v1(
    target_wizard_id,
    actor_id
  ) then
    raise exception 'LEAGUE_BETA_WIZARD_NOT_FOUND' using errcode = 'P0002';
  end if;
  snapshot := private.pachanga_league_private_beta_wizard_snapshot_v1(target_wizard_id);
  return jsonb_build_object(
    'flags', public.get_pachanga_league_private_beta_flags_v1(),
    'wizard', snapshot
  );
end;
$$;

create or replace function public.get_my_pachanga_league_private_beta_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare flags jsonb;
declare organizers jsonb;
declare wizards jsonb;
declare competitions jsonb;
begin
  if actor_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  flags := public.get_pachanga_league_private_beta_flags_v1();

  with candidates as (
    select 'TEAM'::text as organizer_kind, groups.id as organizer_id,
      groups.name as organizer_name, 'team_owner'::text as actor_role,
      true as organizer_active
    from public.pachanga_groups groups
    where groups.owner_id = actor_id
    union all
    select 'CLUB'::text, clubs.id, clubs.name,
      private.pachanga_club_active_role_v1(clubs.id, actor_id),
      clubs.operational_status = 'active'
    from public.pachanga_clubs clubs
    where private.pachanga_club_active_role_v1(clubs.id, actor_id)
      in ('club_owner', 'club_competition_manager')
  ), bounded_candidates as (
    select *
    from candidates
    order by organizer_kind, organizer_name, organizer_id
    limit 100
  ), snapshots as (
    select candidates.*,
      private.pachanga_league_private_beta_bundle_snapshot_v1(
        candidates.organizer_kind,
        candidates.organizer_id
      ) as bundle
    from bounded_candidates candidates
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', snapshots.organizer_kind,
    'id', snapshots.organizer_id,
    'name', snapshots.organizer_name,
    'actorRole', snapshots.actor_role,
    'active', snapshots.organizer_active,
    'bundle', snapshots.bundle,
    'organizerRevision', coalesce((
      select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_kind = snapshots.organizer_kind
        and (
          (snapshots.organizer_kind = 'TEAM'
            and states.organizer_group_id = snapshots.organizer_id)
          or (snapshots.organizer_kind = 'CLUB'
            and states.organizer_club_id = snapshots.organizer_id)
        )
      order by states.server_sequence desc, states.id desc
      limit 1
    ), 0),
    'canCreate',
      (flags ->> 'enabled')::boolean
      and (flags ->> 'creationEnabled')::boolean
      and snapshots.organizer_active
      and snapshots.bundle ->> 'status' = 'active'
      and (
        snapshots.organizer_kind = 'TEAM'
        or coalesce((
          select club_settings.club_competition_organizer_enabled
          from private.pachanga_club_foundation_settings club_settings
          where club_settings.singleton
        ), false)
      ),
    'hasActiveLeague', exists (
      select 1
      from public.pachanga_competitions target_competitions
      where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
        and target_competitions.status <> 'cancelled'
        and target_competitions.organizer_kind = snapshots.organizer_kind
        and (
          (snapshots.organizer_kind = 'TEAM'
            and target_competitions.organizer_group_id = snapshots.organizer_id)
          or (snapshots.organizer_kind = 'CLUB'
            and target_competitions.organizer_club_id = snapshots.organizer_id)
        )
    )
  ) order by snapshots.organizer_kind, snapshots.organizer_name, snapshots.organizer_id), '[]'::jsonb)
  into organizers
  from snapshots;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', visible_wizards.id,
    'organizerKind', visible_wizards.organizer_kind,
    'organizerId', coalesce(
      visible_wizards.organizer_group_id,
      visible_wizards.organizer_club_id
    ),
    'status', visible_wizards.status,
    'currentStep', visible_wizards.current_step,
    'completedSteps', to_jsonb(visible_wizards.completed_steps),
    'competitionId', visible_wizards.competition_id,
    'revision', visible_wizards.revision,
    'serverSequence', visible_wizards.server_sequence,
    'updatedAt', visible_wizards.updated_at
  ) order by visible_wizards.server_sequence desc, visible_wizards.id desc), '[]'::jsonb)
  into wizards
  from (
    select target_wizards.*
    from private.pachanga_league_private_beta_wizards target_wizards
    where private.pachanga_league_private_beta_actor_can_read_wizard_v1(
      target_wizards.id,
      actor_id
    )
    order by target_wizards.server_sequence desc, target_wizards.id desc
    limit 100
  ) visible_wizards;

  with visible as (
    select target_competitions.*
    from public.pachanga_competitions target_competitions
    where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
      and private.pachanga_competition_can_v1(
        target_competitions.id,
        actor_id,
        'read'
      )
    order by target_competitions.server_sequence desc, target_competitions.id desc
    limit 100
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', visible.id,
    'name', visible.name,
    'slug', visible.slug,
    'description', visible.description,
    'generalArea', visible.general_area,
    'imageUrl', visible.image_url,
    'organizerKind', visible.organizer_kind,
    'organizerId', coalesce(visible.organizer_group_id, visible.organizer_club_id),
    'status', visible.status,
    'visibility', visible.visibility,
    'actorRole', private.pachanga_competition_actor_role_v1(visible.id, actor_id),
    'edition', (
      select jsonb_build_object(
        'id', editions.id,
        'name', editions.name,
        'seasonLabel', editions.season_label,
        'startsAt', editions.starts_at,
        'endsAt', editions.ends_at,
        'status', editions.status,
        'registrationMode', editions.registration_mode,
        'registrationClosesAt', editions.registration_closes_at,
        'revision', editions.revision
      )
      from public.pachanga_competition_editions editions
      where editions.competition_id = visible.id
      order by editions.server_sequence desc, editions.id desc
      limit 1
    ),
    'entryCount', (
      select count(*)
      from public.pachanga_competition_entries entries
      where entries.competition_id = visible.id
        and entries.status in ('accepted', 'active')
    ),
    'matchCount', (
      select count(*)
      from public.pachanga_competition_match_contexts contexts
      where contexts.competition_id = visible.id
    ),
    'pendingResultCount', (
      select count(*)
      from public.pachanga_competition_sporting_results results
      join public.pachanga_competition_match_contexts contexts
        on contexts.id = results.competition_match_context_id
      where contexts.competition_id = visible.id
        and results.state in ('draft', 'proposed', 'pending_confirmation', 'disputed')
    ),
    'incidentCount', (
      select
        (select count(*) from public.pachanga_competition_postponement_requests requests
          where requests.competition_id = visible.id and requests.status not in ('cancelled', 'rejected'))
        + (select count(*) from public.pachanga_competition_no_show_incidents incidents
          where incidents.competition_id = visible.id and incidents.status <> 'cancelled')
        + (select count(*) from public.pachanga_competition_match_suspensions suspensions
          where suspensions.competition_id = visible.id and suspensions.status <> 'cancelled')
    ),
    'nextAction', case
      when visible.status = 'draft' then 'configure_registration'
      when visible.status = 'registration_open' then 'review_entries'
      when visible.status = 'registration_closed' then 'prepare_schedule'
      when visible.status in ('scheduled', 'active') then 'open_match_hub'
      when visible.status = 'suspended' then 'review_incidents'
      else 'open_league'
    end,
    'revision', visible.revision,
    'serverSequence', visible.server_sequence,
    'updatedAt', visible.updated_at
  ) order by visible.server_sequence desc, visible.id desc), '[]'::jsonb)
  into competitions
  from visible;

  return jsonb_build_object(
    'flags', flags,
    'organizers', organizers,
    'wizards', wizards,
    'competitions', competitions,
    'cache', jsonb_build_object(
      'policy', 'private-no-store',
      'realtimeMode', 'invalidate_then_refetch'
    )
  );
end;
$$;

create or replace function public.get_pachanga_platform_league_private_beta_v1(
  search_text text default null,
  page_offset integer default 0,
  page_size integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized_search text := lower(trim(coalesce(search_text, '')));
declare safe_offset integer := greatest(coalesce(page_offset, 0), 0);
declare safe_size integer := least(greatest(coalesce(page_size, 30), 1), 100);
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare candidates jsonb;
declare bundles jsonb;
declare competitions jsonb;
declare recent_events jsonb;
declare total_competitions bigint;
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;

  with organizer_candidates as (
    select 'TEAM'::text as organizer_kind, groups.id as organizer_id,
      groups.name as organizer_name, groups.team_code as reference,
      true as organizer_active
    from public.pachanga_groups groups
    where normalized_search = ''
      or lower(groups.name) like '%' || normalized_search || '%'
      or lower(groups.team_code) like '%' || normalized_search || '%'
    union all
    select 'CLUB', clubs.id, clubs.name, clubs.slug,
      clubs.operational_status = 'active'
    from public.pachanga_clubs clubs
    where normalized_search = ''
      or lower(clubs.name) like '%' || normalized_search || '%'
      or lower(clubs.slug) like '%' || normalized_search || '%'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'organizerKind', organizer_candidates.organizer_kind,
    'organizerId', organizer_candidates.organizer_id,
    'name', organizer_candidates.organizer_name,
    'reference', organizer_candidates.reference,
    'active', organizer_candidates.organizer_active,
    'organizerRevision', coalesce((
      select states.revision
      from public.pachanga_competition_organizer_states states
      where states.organizer_kind = organizer_candidates.organizer_kind
        and (
          (organizer_candidates.organizer_kind = 'TEAM'
            and states.organizer_group_id = organizer_candidates.organizer_id)
          or (organizer_candidates.organizer_kind = 'CLUB'
            and states.organizer_club_id = organizer_candidates.organizer_id)
        )
      order by states.server_sequence desc, states.id desc
      limit 1
    ), 0),
    'bundle', private.pachanga_league_private_beta_bundle_snapshot_v1(
      organizer_candidates.organizer_kind,
      organizer_candidates.organizer_id
    )
  ) order by organizer_candidates.organizer_kind,
    organizer_candidates.organizer_name,
    organizer_candidates.organizer_id), '[]'::jsonb)
  into candidates
  from (
    select * from organizer_candidates
    order by organizer_kind, organizer_name, organizer_id
    offset safe_offset limit safe_size
  ) organizer_candidates;

  with grouped_bundles as (
    select grants.bundle_id, grants.organizer_kind,
      coalesce(grants.organizer_group_id, grants.organizer_club_id) as organizer_id,
      max(grants.beta_team_cap) as team_cap,
      min(grants.valid_from) as valid_from,
      max(grants.expires_at) as expires_at,
      min(grants.created_at) as granted_at,
      max(grants.updated_at) as updated_at,
      max(grants.server_sequence) as server_sequence,
      count(distinct grants.capability) filter (
        where grants.status = 'active'
          and grants.valid_from <= statement_timestamp()
          and (grants.expires_at is null or grants.expires_at > statement_timestamp())
      ) as active_capabilities,
      bool_or(grants.status = 'revoked') as has_revoked,
      max(grants.granted_by::text)::uuid as granted_by
    from public.pachanga_competition_entitlement_grants grants
    where grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
    group by grants.bundle_id, grants.organizer_kind,
      coalesce(grants.organizer_group_id, grants.organizer_club_id)
  ), bounded_bundles as (
    select *
    from grouped_bundles
    order by server_sequence desc, bundle_id desc
    limit 100
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'bundleId', bounded_bundles.bundle_id,
    'organizerKind', bounded_bundles.organizer_kind,
    'organizerId', bounded_bundles.organizer_id,
    'status', case
      when bounded_bundles.active_capabilities = cardinality(
        private.pachanga_league_private_beta_capabilities_v1()
      ) then 'active'
      when bounded_bundles.expires_at is not null
        and bounded_bundles.expires_at <= statement_timestamp() then 'expired'
      when bounded_bundles.has_revoked then 'revoked'
      else 'incomplete'
    end,
    'teamCap', bounded_bundles.team_cap,
    'validFrom', bounded_bundles.valid_from,
    'expiresAt', bounded_bundles.expires_at,
    'grantedAt', bounded_bundles.granted_at,
    'updatedAt', bounded_bundles.updated_at,
    'grantedBy', bounded_bundles.granted_by,
    'capabilityCount', bounded_bundles.active_capabilities,
    'serverSequence', bounded_bundles.server_sequence
  ) order by bounded_bundles.server_sequence desc, bounded_bundles.bundle_id desc), '[]'::jsonb)
  into bundles
  from bounded_bundles;

  select count(*) into total_competitions
  from public.pachanga_competitions target_competitions
  where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1';

  with beta_competitions as (
    select target_competitions.*
    from public.pachanga_competitions target_competitions
    where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
    order by target_competitions.server_sequence desc, target_competitions.id desc
    offset safe_offset limit safe_size
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', beta_competitions.id,
    'name', beta_competitions.name,
    'organizerKind', beta_competitions.organizer_kind,
    'organizerId', coalesce(
      beta_competitions.organizer_group_id,
      beta_competitions.organizer_club_id
    ),
    'status', beta_competitions.status,
    'visibility', beta_competitions.visibility,
    'teamCount', (
      select count(*) from public.pachanga_competition_entries entries
      where entries.competition_id = beta_competitions.id
        and entries.status in ('accepted', 'active')
    ),
    'matchCount', (
      select count(*) from public.pachanga_competition_match_contexts contexts
      where contexts.competition_id = beta_competitions.id
    ),
    'pendingResults', (
      select count(*)
      from public.pachanga_competition_sporting_results results
      join public.pachanga_competition_match_contexts contexts
        on contexts.id = results.competition_match_context_id
      where contexts.competition_id = beta_competitions.id
        and results.state in ('draft', 'proposed', 'pending_confirmation', 'disputed')
    ),
    'disputes', (
      select count(*)
      from public.pachanga_competition_sporting_results results
      join public.pachanga_competition_match_contexts contexts
        on contexts.id = results.competition_match_context_id
      where contexts.competition_id = beta_competitions.id
        and results.state = 'disputed'
    ),
    'incidents', (
      select
        (select count(*) from public.pachanga_competition_postponement_requests requests
          where requests.competition_id = beta_competitions.id)
        + (select count(*) from public.pachanga_competition_no_show_incidents incidents
          where incidents.competition_id = beta_competitions.id)
        + (select count(*) from public.pachanga_competition_match_suspensions suspensions
          where suspensions.competition_id = beta_competitions.id)
    ),
    'standingsHealth', coalesce((
      select states.health_status
      from public.pachanga_competition_standing_states states
      where states.competition_id = beta_competitions.id
      order by states.server_sequence desc, states.id desc
      limit 1
    ), 'not_created'),
    'revision', beta_competitions.revision,
    'serverSequence', beta_competitions.server_sequence,
    'updatedAt', beta_competitions.updated_at
  ) order by beta_competitions.server_sequence desc, beta_competitions.id desc), '[]'::jsonb)
  into competitions
  from beta_competitions;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', events.id,
    'operationId', events.operation_id,
    'action', events.action,
    'aggregateType', events.aggregate_type,
    'aggregateId', events.aggregate_id,
    'organizerKind', events.organizer_kind,
    'organizerId', coalesce(events.organizer_group_id, events.organizer_club_id),
    'competitionId', events.competition_id,
    'revision', events.aggregate_revision,
    'serverSequence', events.server_sequence,
    'reasonCode', events.reason_code,
    'confirmedAt', events.confirmed_at
  ) order by events.server_sequence desc, events.id desc), '[]'::jsonb)
  into recent_events
  from (
    select *
    from private.pachanga_league_private_beta_events target_events
    order by target_events.server_sequence desc, target_events.id desc
    limit 100
  ) events;

  return jsonb_build_object(
    'flags', public.get_pachanga_league_private_beta_flags_v1(),
    'foundation', jsonb_build_object(
      'r1', settings.foundation_enabled and settings.creation_enabled,
      'r4a', settings.league_participation_foundation_enabled,
      'r4b', settings.league_scheduling_foundation_enabled,
      'r4c', settings.league_match_operations_foundation_enabled,
      'r4d', settings.league_operational_exceptions_foundation_enabled,
      'clubOrganizer', coalesce((
        select club_settings.club_competition_organizer_enabled
        from private.pachanga_club_foundation_settings club_settings
        where club_settings.singleton
      ), false),
      'refereeAssignments', coalesce((
        select referee_settings.referee_assignments_enabled
        from private.pachanga_referee_foundation_settings referee_settings
        where referee_settings.singleton
      ), false),
      'publicRegistration', settings.league_public_registration_enabled,
      'publicCalendar', settings.league_public_calendar_enabled,
      'publicStandings', settings.league_public_standings_enabled,
      'publicExceptionStatus', settings.league_public_exception_status_enabled
    ),
    'metrics', jsonb_build_object(
      'competitions', total_competitions,
      'drafts', (select count(*) from public.pachanga_competitions target_competitions
        where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
          and target_competitions.status = 'draft'),
      'active', (select count(*) from public.pachanga_competitions target_competitions
        where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
          and target_competitions.status in ('registration_open', 'registration_closed', 'scheduled', 'active', 'suspended')),
      'activeGrantBundles', (
        select count(*)
        from (
          select grants.bundle_id
          from public.pachanga_competition_entitlement_grants grants
          where grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
            and grants.status = 'active'
            and grants.valid_from <= statement_timestamp()
            and (grants.expires_at is null or grants.expires_at > statement_timestamp())
          group by grants.bundle_id
          having count(distinct grants.capability) = cardinality(
            private.pachanga_league_private_beta_capabilities_v1()
          )
        ) active_bundles
      ),
      'activeEditionLimitViolations', (
        select count(*)
        from (
          select target_competitions.organizer_kind,
            coalesce(
              target_competitions.organizer_group_id,
              target_competitions.organizer_club_id
            ) organizer_id
          from public.pachanga_competitions target_competitions
          where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
            and target_competitions.status <> 'cancelled'
          group by target_competitions.organizer_kind,
            coalesce(
              target_competitions.organizer_group_id,
              target_competitions.organizer_club_id
            )
          having count(*) > 1
        ) violations
      ),
      'publicExposureViolations', (
        select count(*)
        from public.pachanga_competitions target_competitions
        where target_competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
          and target_competitions.visibility <> 'private'
      )
    ),
    'organizers', candidates,
    'bundles', bundles,
    'competitions', competitions,
    'events', recent_events,
    'page', safe_offset / safe_size + 1,
    'pageSize', safe_size,
    'total', total_competitions
  );
end;
$$;

alter table public.pachanga_league_private_beta_invalidations enable row level security;

drop policy if exists "League beta actors read invalidations"
  on public.pachanga_league_private_beta_invalidations;
create policy "League beta actors read invalidations"
on public.pachanga_league_private_beta_invalidations
for select
to authenticated
using (
  target_user_id = (select auth.uid())
  or (
    organizer_kind = 'TEAM'
    and exists (
      select 1 from public.pachanga_groups groups
      where groups.id = organizer_group_id
        and groups.owner_id = (select auth.uid())
    )
  )
  or (
    organizer_kind = 'CLUB'
    and private.pachanga_club_active_role_v1(
      organizer_club_id,
      (select auth.uid())
    ) in ('club_owner', 'club_competition_manager')
  )
  or (
    competition_id is not null
    and private.pachanga_competition_can_v1(
      competition_id,
      (select auth.uid()),
      'read'
    )
  )
);

grant select on table public.pachanga_league_private_beta_invalidations to authenticated;

do $$
begin
  if exists (
    select 1 from pg_publication publications
    where publications.pubname = 'supabase_realtime'
  ) and not exists (
    select 1 from pg_publication_tables publication_tables
    where publication_tables.pubname = 'supabase_realtime'
      and publication_tables.schemaname = 'public'
      and publication_tables.tablename = 'pachanga_league_private_beta_invalidations'
  ) then
    alter publication supabase_realtime
      add table public.pachanga_league_private_beta_invalidations;
  end if;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_league_private_beta_actor_can_read_wizard_v1(uuid,uuid)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

revoke all on function public.get_pachanga_league_private_beta_flags_v1()
  from public, anon, authenticated;
grant execute on function public.get_pachanga_league_private_beta_flags_v1()
  to authenticated, service_role;

revoke all on function public.get_pachanga_league_private_beta_wizard_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_league_private_beta_wizard_v1(uuid)
  to authenticated;

revoke all on function public.get_my_pachanga_league_private_beta_v1()
  from public, anon, authenticated;
grant execute on function public.get_my_pachanga_league_private_beta_v1()
  to authenticated;

revoke all on function public.get_pachanga_platform_league_private_beta_v1(text,integer,integer)
  from public, anon, authenticated;
grant execute on function public.get_pachanga_platform_league_private_beta_v1(text,integer,integer)
  to authenticated, service_role;

comment on function public.get_my_pachanga_league_private_beta_v1() is
  'Bounded private League dashboard. Returns canonical summaries only; Realtime invalidates and clients refetch.';
comment on table public.pachanga_league_private_beta_invalidations is
  'No sporting payload. Authorized clients use each monotonic invalidation only to refetch canonical read models.';
