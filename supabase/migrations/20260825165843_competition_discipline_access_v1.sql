-- Pachangas IQ R5: canonical reads, platform gates and direct-write isolation.

set lock_timeout = '5s';
set statement_timeout = '120s';

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_competition_discipline_rule_catalogs',
    'pachanga_competition_disciplinary_cycles',
    'pachanga_competition_disciplinary_events',
    'pachanga_competition_disciplinary_event_revisions',
    'pachanga_competition_disciplinary_counters',
    'pachanga_competition_sanctions',
    'pachanga_competition_sanction_revisions',
    'pachanga_competition_sanction_proposals',
    'pachanga_competition_sanction_service_events',
    'pachanga_competition_sanction_appeals',
    'pachanga_competition_sanction_appeal_revisions',
    'pachanga_competition_discipline_player_states'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

revoke all on table private.pachanga_competition_discipline_evidence
  from public, anon, authenticated;
grant all on table private.pachanga_competition_discipline_evidence to service_role;

alter table public.pachanga_competition_invalidations
  drop constraint if exists pachanga_competition_invalidations_authority_check;
alter table public.pachanga_competition_invalidations
  add constraint pachanga_competition_invalidations_authority_check check (
    (organizer_group_id is not null and organizer_club_id is null)
    or (organizer_group_id is null and organizer_club_id is not null)
    or (
      organizer_group_id is null and organizer_club_id is null
      and competition_id is null
      and entity_type in (
        'league_participation_flags', 'league_scheduling_flags',
        'league_match_operations_flags', 'league_operational_exceptions_flags',
        'competition_discipline_flags'
      )
    )
  );

create or replace function private.pachanga_league_can_read_invalidation_v1(
  organizer_group_id uuid,
  organizer_club_id uuid,
  target_competition_id uuid,
  target_group_id uuid,
  target_user_id uuid,
  target_entity_type text,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select actor_id is not null
    and actor_id = (select auth.uid())
    and (
      (
        target_entity_type in (
          'league_participation_flags', 'league_scheduling_flags',
          'league_match_operations_flags', 'league_operational_exceptions_flags',
          'competition_discipline_flags'
        )
        and target_competition_id is null
      )
      or private.pachanga_platform_role_for_user_v1(actor_id) in ('platform_owner', 'platform_admin')
      or target_user_id = actor_id
      or exists (
        select 1 from public.pachanga_groups groups
        where groups.id in (organizer_group_id, target_group_id)
          and groups.owner_id = actor_id
      )
      or exists (
        select 1 from public.pachanga_group_members members
        where members.group_id = target_group_id and members.user_id = actor_id
      )
      or private.pachanga_club_can_v1(organizer_club_id, actor_id, 'read')
      or (
        target_competition_id is not null
        and private.pachanga_competition_can_v1(target_competition_id, actor_id, 'read')
      )
      or (
        target_competition_id is not null and exists (
          select 1
          from public.pachanga_competition_entries entries
          left join public.pachanga_competition_team_delegates delegates
            on delegates.entry_id = entries.id
            and delegates.user_id = actor_id
            and delegates.status = 'active'
            and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
          left join public.pachanga_competition_roster_members roster_members
            on roster_members.entry_id = entries.id
            and roster_members.eligibility_status in ('eligible', 'waived')
            and (roster_members.effective_until is null
              or roster_members.effective_until > clock_timestamp())
          left join public.pachanga_player_profiles profiles
            on profiles.id = roster_members.player_profile_id
            and profiles.user_id = actor_id
          where entries.competition_id = target_competition_id
            and (delegates.id is not null or profiles.id is not null)
        )
      )
    );
$$;

revoke all on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) to authenticated;

create or replace function private.pachanga_competition_discipline_can_read_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select target_actor_id is not null
    and target_actor_id = (select auth.uid())
    and (
      private.pachanga_competition_can_v1(
        target_competition_id, target_actor_id, 'discipline_read'
      )
      or exists (
        select 1
        from public.pachanga_competition_entries entries
        left join public.pachanga_competition_team_delegates delegates
          on delegates.entry_id = entries.id
          and delegates.user_id = target_actor_id
          and delegates.status = 'active'
          and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
        left join public.pachanga_competition_roster_members roster_members
          on roster_members.entry_id = entries.id
          and roster_members.eligibility_status in ('eligible', 'waived')
          and (roster_members.effective_until is null
            or roster_members.effective_until > clock_timestamp())
        left join public.pachanga_player_profiles profiles
          on profiles.id = roster_members.player_profile_id
          and profiles.user_id = target_actor_id
        where entries.competition_id = target_competition_id
          and (delegates.id is not null or profiles.id is not null)
      )
    );
$$;

revoke all on function private.pachanga_competition_discipline_can_read_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.get_pachanga_competition_discipline_flags_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  return private.pachanga_competition_discipline_flags_v1();
end;
$$;

revoke all on function public.get_pachanga_competition_discipline_flags_v1()
  from public, anon;
grant execute on function public.get_pachanga_competition_discipline_flags_v1()
  to authenticated, service_role;

create or replace function public.get_pachanga_competition_discipline_v1(
  target_competition_id uuid,
  target_canonical_match_id uuid default null,
  target_player_profile_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_discipline_can_read_v1(
    target_competition_id, actor_id
  ) then raise exception 'COMPETITION_DISCIPLINE_NOT_FOUND' using errcode = 'P0002'; end if;
  if target_canonical_match_id is not null and not exists (
    select 1 from public.pachanga_competition_match_contexts contexts
    where contexts.competition_id = target_competition_id
      and contexts.canonical_match_id = target_canonical_match_id
      and contexts.status <> 'retired'
  ) then raise exception 'DISCIPLINE_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
  if target_player_profile_id is not null and not exists (
    select 1 from public.pachanga_competition_roster_members members
    join public.pachanga_competition_entries entries on entries.id = members.entry_id
    where entries.competition_id = target_competition_id
      and members.player_profile_id = target_player_profile_id
  ) then raise exception 'DISCIPLINE_PLAYER_NOT_IN_COMPETITION' using errcode = 'P0002'; end if;
  return private.pachanga_competition_discipline_snapshot_v1(
    target_competition_id, actor_id,
    target_canonical_match_id, target_player_profile_id
  );
end;
$$;

revoke all on function public.get_pachanga_competition_discipline_v1(uuid, uuid, uuid)
  from public, anon;
grant execute on function public.get_pachanga_competition_discipline_v1(uuid, uuid, uuid)
  to authenticated, service_role;

create or replace function public.get_pachanga_public_competition_discipline_v1(
  target_competition_id uuid,
  target_canonical_match_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare public_enabled boolean;
declare competition_visibility text;
declare snapshot jsonb;
begin
  select settings.competition_public_discipline_enabled into public_enabled
  from private.pachanga_competition_foundation_settings settings where settings.singleton;
  select competitions.visibility into competition_visibility
  from public.pachanga_competitions competitions where competitions.id = target_competition_id;
  if not coalesce(public_enabled, false) or competition_visibility <> 'public' then
    raise exception 'PUBLIC_COMPETITION_DISCIPLINE_DISABLED' using errcode = 'P0002';
  end if;
  snapshot := private.pachanga_competition_discipline_snapshot_v1(
    target_competition_id, null, target_canonical_match_id, null
  );
  return jsonb_build_object(
    'competitionId', target_competition_id,
    'filters', snapshot -> 'filters',
    'events', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id', event -> 'id',
        'canonicalMatchId', event -> 'canonicalMatchId',
        'playerProfileId', event -> 'playerProfileId',
        'playerDisplay', event -> 'playerDisplay',
        'cardTypeCode', event -> 'cardTypeCode',
        'visualType', event -> 'visualType',
        'label', event -> 'label',
        'context', event -> 'context',
        'minute', event -> 'minute',
        'period', event -> 'period',
        'status', event -> 'status',
        'publicReasonCategory', event -> 'publicReasonCategory',
        'publicSummary', event -> 'publicSummary',
        'temporaryDismissal', event -> 'temporaryDismissal',
        'sanction', event -> 'sanction',
        'serverSequence', event -> 'serverSequence'
      )) order by (event ->> 'serverSequence')::bigint desc, event ->> 'id')
      from jsonb_array_elements(snapshot -> 'events') events(event)
    ), '[]'::jsonb),
    'sanctions', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id', sanction -> 'id',
        'cycleId', sanction -> 'cycleId',
        'targetType', sanction -> 'targetType',
        'playerProfileId', sanction -> 'playerProfileId',
        'entryId', sanction -> 'entryId',
        'status', sanction -> 'status',
        'unitType', sanction -> 'unitType',
        'totalUnits', sanction -> 'totalUnits',
        'remainingUnits', sanction -> 'remainingUnits',
        'publicReasonCategory', sanction -> 'publicReasonCategory',
        'publicSummary', sanction -> 'publicSummary',
        'serverSequence', sanction -> 'serverSequence'
      )) order by (sanction ->> 'serverSequence')::bigint desc, sanction ->> 'id')
      from jsonb_array_elements(snapshot -> 'sanctions') sanctions(sanction)
    ), '[]'::jsonb),
    'playerStates', snapshot -> 'playerStates',
    'serverSequence', snapshot #> '{health,latestServerSequence}'
  );
end;
$$;

revoke all on function public.get_pachanga_public_competition_discipline_v1(uuid, uuid)
  from public;
grant execute on function public.get_pachanga_public_competition_discipline_v1(uuid, uuid)
  to anon, authenticated, service_role;

create or replace function public.get_pachanga_platform_competition_discipline_v1(
  page_size integer default 100,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare bounded_size integer := least(greatest(coalesce(page_size, 100), 1), 500);
declare bounded_offset integer := greatest(coalesce(page_offset, 0), 0);
begin
  perform private.pachanga_platform_require_v1('competitions.manage');
  return jsonb_build_object(
    'kind', 'PlatformCompetitionDiscipline',
    'flags', private.pachanga_competition_discipline_flags_v1(),
    'counts', jsonb_build_object(
      'ruleCatalogs', (select count(*) from public.pachanga_competition_discipline_rule_catalogs),
      'cycles', (select count(*) from public.pachanga_competition_disciplinary_cycles),
      'events', (select count(*) from public.pachanga_competition_disciplinary_events),
      'counters', (select count(*) from public.pachanga_competition_disciplinary_counters),
      'activeSanctions', (select count(*) from public.pachanga_competition_sanctions
        where status in ('active', 'provisional', 'under_review')),
      'serviceEvents', (select count(*) from public.pachanga_competition_sanction_service_events),
      'appeals', (select count(*) from public.pachanga_competition_sanction_appeals),
      'legacyBackfill', 0
    ),
    'health', jsonb_build_object(
      'eventsWithoutRevision', (select count(*)
        from public.pachanga_competition_disciplinary_events where current_revision_id is null),
      'sanctionsWithoutRevision', (select count(*)
        from public.pachanga_competition_sanctions where current_revision_id is null),
      'appealsWithoutRevision', (select count(*)
        from public.pachanga_competition_sanction_appeals where current_revision_id is null),
      'counterChecksumMissing', (select count(*)
        from public.pachanga_competition_disciplinary_counters
        where length(state_checksum) <> 64)
    ),
    'recentSanctions', coalesce((select jsonb_agg(jsonb_build_object(
      'id', source.id, 'competitionId', source.competition_id,
      'playerProfileId', source.player_profile_id,
      'status', source.status, 'remainingUnits', source.remaining_units,
      'unitType', source.unit_type, 'revision', source.revision,
      'serverSequence', source.server_sequence
    ) order by source.server_sequence desc, source.id desc)
    from (
      select sanctions.* from public.pachanga_competition_sanctions sanctions
      order by sanctions.server_sequence desc, sanctions.id desc
      limit bounded_size offset bounded_offset
    ) source), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_platform_competition_discipline_v1(integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_competition_discipline_v1(integer, integer)
  to authenticated;

create or replace function public.command_pachanga_competition_discipline_platform_v1(
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
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000d501'::uuid;
declare actor_id uuid := (select auth.uid());
declare action_name constant text := 'competition_discipline_flags.set';
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare request_hash text;
declare replay jsonb;
declare metadata jsonb;
declare sequence_value bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare snapshot jsonb;
declare response jsonb;
declare next_foundation boolean;
declare next_events boolean;
declare next_counters boolean;
declare next_sanctions boolean;
declare next_service boolean;
declare next_appeals boolean;
declare next_public boolean;
begin
  if operation_id is null or aggregate_id <> flags_aggregate_id
     or expected_revision is null or expected_revision < 0 then
    raise exception 'INVALID_COMPETITION_DISCIPLINE_FLAGS_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if jsonb_typeof(coalesce(command_payload, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(command_payload) > 32768 then
    raise exception 'INVALID_COMPETITION_DISCIPLINE_FLAGS_PAYLOAD' using errcode = '22023';
  end if;
  perform private.pachanga_platform_require_v1('competitions.manage');
  perform private.pachanga_platform_require_v1('flags.write');
  if exists (
    select 1 from jsonb_each(command_payload) pair
    where pair.key <> 'reason'
      and (
        pair.key not in (
          'foundationEnabled', 'eventsEnabled', 'countersEnabled',
          'sanctionsEnabled', 'serviceEnabled', 'appealsEnabled', 'publicEnabled'
        ) or jsonb_typeof(pair.value) <> 'boolean'
      )
  ) then raise exception 'INVALID_COMPETITION_DISCIPLINE_FLAG' using errcode = '22023'; end if;
  metadata := private.pachanga_league_match_sanitize_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_discipline_request_hash_v1(
    flags_aggregate_id, action_name, aggregate_id, expected_revision, command_payload
  );
  perform pg_advisory_xact_lock(hashtextextended(
    'competition-discipline-flags:' || operation_id::text, 0
  ));
  replay := private.pachanga_competition_discipline_replay_v1(
    operation_id, actor_id, action_name, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton for update;
  if settings.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  next_foundation := coalesce((command_payload ->> 'foundationEnabled')::boolean,
    settings.competition_discipline_foundation_enabled);
  next_events := coalesce((command_payload ->> 'eventsEnabled')::boolean,
    settings.competition_disciplinary_events_enabled);
  next_counters := coalesce((command_payload ->> 'countersEnabled')::boolean,
    settings.competition_disciplinary_counters_enabled);
  next_sanctions := coalesce((command_payload ->> 'sanctionsEnabled')::boolean,
    settings.competition_sanctions_enabled);
  next_service := coalesce((command_payload ->> 'serviceEnabled')::boolean,
    settings.competition_sanction_service_enabled);
  next_appeals := coalesce((command_payload ->> 'appealsEnabled')::boolean,
    settings.competition_discipline_appeals_enabled);
  next_public := coalesce((command_payload ->> 'publicEnabled')::boolean,
    settings.competition_public_discipline_enabled);
  if not next_foundation then
    next_events := false; next_counters := false; next_sanctions := false;
    next_service := false; next_appeals := false; next_public := false;
  end if;
  if not next_events then
    next_counters := false; next_sanctions := false;
    next_service := false; next_appeals := false;
  elsif not next_counters then
    next_sanctions := false; next_service := false; next_appeals := false;
  elsif not next_sanctions then
    next_service := false; next_appeals := false;
  end if;
  if next_foundation and not settings.league_match_operations_foundation_enabled then
    raise exception 'R4C_MATCH_OPERATIONS_DEPENDENCY_NOT_ENABLED' using errcode = '42501';
  end if;
  if next_foundation and not settings.competition_discipline_foundation_enabled
     and exists (
       select 1
       from public.pachanga_competition_entitlement_grants grants
       where grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
         and grants.status = 'active'
         and grants.valid_from <= confirmed_at
         and (grants.expires_at is null or grants.expires_at > confirmed_at)
       group by grants.bundle_id
       having count(distinct grants.capability) filter (
         where grants.capability in (
           'competition_create', 'competition_manage', 'competition_staff',
           'competition_rules', 'competition_categories_manage',
           'competition_entries_manage', 'competition_rosters_review',
           'competition_schedule', 'competition_results',
           'competition_standings', 'competition_operations'
         )
       ) = 11
       and count(distinct grants.capability) filter (
         where grants.capability in (
           'competition_discipline_manage',
           'competition_discipline_review',
           'competition_appeals_manage'
         )
       ) < 3
     ) then
    raise exception 'R5_BUNDLE_UPGRADE_REQUIRED' using errcode = 'PT409';
  end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings current_settings set
    competition_discipline_foundation_enabled = next_foundation,
    competition_disciplinary_events_enabled = next_events,
    competition_disciplinary_counters_enabled = next_counters,
    competition_sanctions_enabled = next_sanctions,
    competition_sanction_service_enabled = next_service,
    competition_discipline_appeals_enabled = next_appeals,
    competition_public_discipline_enabled = next_public,
    revision = current_settings.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = confirmed_at
  where current_settings.singleton returning * into settings;
  snapshot := private.pachanga_competition_discipline_flags_v1();
  response := jsonb_build_object(
    'operationId', operation_id, 'confirmedRevision', settings.revision,
    'confirmedAt', confirmed_at, 'serverSequence', sequence_value,
    'snapshot', snapshot,
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'competition_discipline_flags',
      'entityId', flags_aggregate_id, 'revision', settings.revision,
      'serverSequence', sequence_value
    ))
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, actor_id, 'authenticated', 'competition_discipline',
    aggregate_id::text, null, action_name, settings.revision, sequence_value,
    left(coalesce(nullif(trim(command_payload ->> 'reason'), ''), action_name), 120),
    snapshot - 'updatedAt', confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, null, null, null, null, null,
    'competition_discipline_flags', flags_aggregate_id::text,
    settings.revision, confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    operation_id, actor_id, 'authenticated', action_name,
    'competition_discipline', aggregate_id::text, request_hash,
    settings.revision, sequence_value, metadata, response, confirmed_at
  );
  return response;
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_competition_discipline_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_competition_discipline_platform_v1(
  uuid, uuid, bigint, jsonb, jsonb
) to authenticated;
