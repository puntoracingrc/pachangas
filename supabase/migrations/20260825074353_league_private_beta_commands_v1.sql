-- Pachangas IQ League Private Beta V1: entitlement bundle and wizard commands.
-- Canonical League entities continue to live exclusively in R1/R4 tables.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_league_private_beta_capabilities_v1()
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select array[
    'competition_create',
    'competition_manage',
    'competition_staff',
    'competition_rules',
    'competition_categories_manage',
    'competition_entries_manage',
    'competition_rosters_review',
    'competition_schedule',
    'competition_results',
    'competition_standings',
    'competition_operations'
  ]::text[];
$$;

create or replace function private.pachanga_league_private_beta_active_bundle_id_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns uuid
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with required as (
    select unnest(private.pachanga_league_private_beta_capabilities_v1()) as capability
  ), candidates as (
    select grants.bundle_id,
      max(grants.server_sequence) as latest_sequence,
      count(distinct grants.capability) filter (
        where grants.status = 'active'
          and grants.valid_from <= statement_timestamp()
          and (grants.expires_at is null or grants.expires_at > statement_timestamp())
      ) as active_capabilities
    from public.pachanga_competition_entitlement_grants grants
    where grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
      and grants.organizer_kind = upper(trim(target_organizer_kind))
      and (
        (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
        or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
      )
      and grants.capability in (select capability from required)
    group by grants.bundle_id
  )
  select candidates.bundle_id
  from candidates
  where candidates.active_capabilities = cardinality(
    private.pachanga_league_private_beta_capabilities_v1()
  )
  order by candidates.latest_sequence desc, candidates.bundle_id desc
  limit 1;
$$;

create or replace function private.pachanga_league_private_beta_bundle_snapshot_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with required as (
    select unnest(private.pachanga_league_private_beta_capabilities_v1()) as capability
  ), bundles as (
    select grants.bundle_id,
      max(grants.beta_team_cap) as team_cap,
      min(grants.valid_from) as valid_from,
      max(grants.expires_at) as expires_at,
      max(grants.server_sequence) as latest_sequence,
      min(grants.created_at) as granted_at,
      max(grants.updated_at) as updated_at,
      count(distinct grants.capability) filter (
        where grants.status = 'active'
          and grants.valid_from <= statement_timestamp()
          and (grants.expires_at is null or grants.expires_at > statement_timestamp())
      ) as active_capabilities,
      bool_or(grants.status = 'revoked') as has_revoked,
      jsonb_agg(jsonb_build_object(
        'id', grants.id,
        'capability', grants.capability,
        'status', case
          when grants.status = 'revoked' then 'revoked'
          when grants.valid_from > statement_timestamp() then 'scheduled'
          when grants.expires_at is not null and grants.expires_at <= statement_timestamp() then 'expired'
          else 'active'
        end,
        'revision', grants.revision,
        'serverSequence', grants.server_sequence
      ) order by grants.capability, grants.server_sequence, grants.id) as grants
    from public.pachanga_competition_entitlement_grants grants
    where grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
      and grants.organizer_kind = upper(trim(target_organizer_kind))
      and (
        (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
        or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
      )
      and grants.capability in (select capability from required)
    group by grants.bundle_id
  ), selected as (
    select * from bundles order by latest_sequence desc, bundle_id desc limit 1
  )
  select coalesce((
    select jsonb_build_object(
      'bundleId', selected.bundle_id,
      'programKey', 'LEAGUE_PRIVATE_BETA_V1',
      'status', case
        when selected.active_capabilities = cardinality(
          private.pachanga_league_private_beta_capabilities_v1()
        ) then 'active'
        when selected.expires_at is not null and selected.expires_at <= statement_timestamp() then 'expired'
        when selected.has_revoked then 'revoked'
        else 'incomplete'
      end,
      'teamCap', selected.team_cap,
      'validFrom', selected.valid_from,
      'expiresAt', selected.expires_at,
      'grantedAt', selected.granted_at,
      'updatedAt', selected.updated_at,
      'capabilities', selected.grants
    ) from selected
  ), jsonb_build_object(
    'programKey', 'LEAGUE_PRIVATE_BETA_V1',
    'status', 'not_granted',
    'capabilities', '[]'::jsonb
  ));
$$;

create or replace function private.pachanga_league_private_beta_authorize_organizer_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_actor_id uuid,
  require_creation boolean default true
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare bundle jsonb;
declare actor_role text;
declare organizer_name text;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.league_private_beta_enabled then
    raise exception 'LEAGUE_PRIVATE_BETA_DISABLED' using errcode = '42501';
  end if;
  if require_creation and not settings.league_private_beta_creation_enabled then
    raise exception 'LEAGUE_PRIVATE_BETA_CREATION_DISABLED' using errcode = '42501';
  end if;
  if normalized_kind = 'TEAM' then
    select groups.name,
      case when groups.owner_id = target_actor_id then 'team_owner' else null end
    into organizer_name, actor_role
    from public.pachanga_groups groups where groups.id = target_organizer_id;
    if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    if actor_role is distinct from 'team_owner' then
      raise exception 'TEAM_OWNER_REQUIRED' using errcode = '42501';
    end if;
  elsif normalized_kind = 'CLUB' then
    select clubs.name into organizer_name
    from public.pachanga_clubs clubs
    where clubs.id = target_organizer_id and clubs.operational_status = 'active';
    if not found then raise exception 'CLUB_MUST_BE_ACTIVE' using errcode = '42501'; end if;
    actor_role := private.pachanga_club_active_role_v1(target_organizer_id, target_actor_id);
    if actor_role is null
       or actor_role not in ('club_owner', 'club_competition_manager') then
      raise exception 'CLUB_COMPETITION_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if not coalesce((
      select club_settings.club_competition_organizer_enabled
      from private.pachanga_club_foundation_settings club_settings
      where club_settings.singleton
    ), false) then
      raise exception 'CLUB_COMPETITION_ORGANIZER_DISABLED' using errcode = '0A000';
    end if;
  else
    raise exception 'INVALID_ORGANIZER_KIND' using errcode = '22023';
  end if;

  bundle := private.pachanga_league_private_beta_bundle_snapshot_v1(
    normalized_kind, target_organizer_id
  );
  if bundle ->> 'status' <> 'active' then
    raise exception 'LEAGUE_PRIVATE_BETA_GRANT_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'kind', normalized_kind,
    'id', target_organizer_id,
    'name', organizer_name,
    'actorRole', actor_role,
    'bundle', bundle
  );
end;
$$;

create or replace function private.pachanga_league_private_beta_rate_limit_v1(
  target_actor_id uuid,
  target_action text,
  maximum_events integer,
  target_window interval
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if (
    select count(*)
    from private.pachanga_league_private_beta_events events
    where events.actor_id = target_actor_id
      and events.action = target_action
      and events.confirmed_at >= clock_timestamp() - target_window
  ) >= maximum_events then
    raise exception 'LEAGUE_PRIVATE_BETA_RATE_LIMIT' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function private.pachanga_league_private_beta_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_league_private_beta_operation_receipts%rowtype;
begin
  select * into receipt
  from private.pachanga_league_private_beta_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id is distinct from target_actor_id
     or receipt.action <> target_action
     or receipt.aggregate_type <> target_aggregate_type
     or receipt.aggregate_id <> target_aggregate_id
     or receipt.request_hash <> target_request_hash then
    raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

create or replace function private.pachanga_league_private_beta_store_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_organizer_kind text,
  target_organizer_id uuid,
  target_wizard_id uuid,
  target_competition_id uuid,
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
declare normalized_kind text := nullif(upper(trim(coalesce(target_organizer_kind, ''))), '');
declare response jsonb;
begin
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', case when normalized_kind is null then '[]'::jsonb else jsonb_build_array(
      jsonb_build_object(
        'entityType', target_aggregate_type,
        'entityId', target_aggregate_id,
        'revision', target_confirmed_revision
      )
    ) end
  );

  insert into private.pachanga_league_private_beta_events(
    operation_id, actor_id, action, aggregate_type, aggregate_id,
    organizer_kind, organizer_group_id, organizer_club_id, competition_id,
    aggregate_revision, server_sequence, reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_action, target_aggregate_type,
    target_aggregate_id, normalized_kind,
    case when normalized_kind = 'TEAM' then target_organizer_id else null end,
    case when normalized_kind = 'CLUB' then target_organizer_id else null end,
    target_competition_id, target_confirmed_revision, target_server_sequence,
    left(coalesce(nullif(trim(target_reason_code), ''), target_action), 120),
    coalesce(target_event_payload, '{}'::jsonb), target_confirmed_at
  );

  if normalized_kind is not null then
    insert into public.pachanga_league_private_beta_invalidations(
      server_sequence, wizard_id, competition_id, organizer_kind,
      organizer_group_id, organizer_club_id, target_user_id,
      entity_type, entity_id, revision, created_at
    ) values (
      target_server_sequence, target_wizard_id, target_competition_id,
      normalized_kind,
      case when normalized_kind = 'TEAM' then target_organizer_id else null end,
      case when normalized_kind = 'CLUB' then target_organizer_id else null end,
      target_actor_id, target_aggregate_type, target_aggregate_id,
      target_confirmed_revision, target_confirmed_at
    );
  end if;

  insert into private.pachanga_league_private_beta_operation_receipts(
    operation_id, actor_id, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    target_operation_id, target_actor_id, target_action, target_aggregate_type,
    target_aggregate_id, target_request_hash, target_confirmed_revision,
    target_server_sequence,
    private.pachanga_competition_client_metadata_v1(coalesce(target_client_metadata, '{}'::jsonb)),
    response, target_confirmed_at
  );
  return response;
end;
$$;

create or replace function private.pachanga_league_private_beta_wizard_snapshot_v1(
  target_wizard_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', wizards.id,
    'organizerKind', wizards.organizer_kind,
    'organizerId', coalesce(wizards.organizer_group_id, wizards.organizer_club_id),
    'status', wizards.status,
    'currentStep', wizards.current_step,
    'completedSteps', to_jsonb(wizards.completed_steps),
    'steps', wizards.step_data,
    'competitionId', wizards.competition_id,
    'consentedAt', wizards.consented_at,
    'revision', wizards.revision,
    'serverSequence', wizards.server_sequence,
    'updatedAt', wizards.updated_at
  )
  from private.pachanga_league_private_beta_wizards wizards
  where wizards.id = target_wizard_id;
$$;

create or replace function private.pachanga_league_private_beta_normalize_step_v1(
  target_step smallint,
  target_data jsonb,
  target_bundle jsonb
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog
as $$
declare data jsonb := coalesce(target_data, '{}'::jsonb);
declare selected_name text;
declare selected_slug text;
declare selected_description text;
declare selected_area text;
declare selected_image text;
declare selected_modality text;
declare start_date date;
declare end_date date;
declare closes_at timestamptz;
declare team_cap integer;
declare bundle_cap integer;
declare legs integer;
declare minimum_size integer;
declare maximum_size integer;
declare starters integer;
declare duration_minutes integer;
declare buffer_minutes integer;
declare confirmation_hours integer;
declare tie_breaks jsonb;
declare criterion text;
declare patterns jsonb;
begin
  if jsonb_typeof(data) <> 'object' then
    raise exception 'LEAGUE_BETA_STEP_DATA_INVALID' using errcode = '22023';
  end if;
  if target_step = 1 then
    selected_name := trim(coalesce(data ->> 'name', ''));
    selected_slug := lower(trim(coalesce(data ->> 'slug', '')));
    selected_description := trim(coalesce(data ->> 'description', ''));
    selected_area := nullif(trim(coalesce(data ->> 'generalArea', '')), '');
    selected_image := nullif(trim(coalesce(data ->> 'imageUrl', '')), '');
    if length(selected_name) not between 3 and 120
       or selected_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
       or length(selected_slug) not between 3 and 80
       or length(selected_description) > 2400
       or (selected_area is not null and length(selected_area) > 160)
       or (selected_image is not null and (
         length(selected_image) > 2048 or selected_image !~* '^https://'
       )) then raise exception 'LEAGUE_BETA_IDENTITY_INVALID' using errcode = '22023'; end if;
    return jsonb_strip_nulls(jsonb_build_object(
      'name', selected_name, 'slug', selected_slug,
      'description', selected_description, 'generalArea', selected_area,
      'imageUrl', selected_image
    ));
  elsif target_step = 2 then
    selected_modality := upper(trim(coalesce(data ->> 'modality', '')));
    if selected_modality not in ('FUTBOL_5', 'FUTBOL_7', 'FUTBOL_11', 'FUTSAL') then
      raise exception 'LEAGUE_BETA_MODALITY_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object('modality', selected_modality);
  elsif target_step = 3 then
    selected_name := trim(coalesce(data ->> 'editionName', ''));
    selected_slug := trim(coalesce(data ->> 'seasonLabel', ''));
    begin
      start_date := (data ->> 'startsAt')::date;
      end_date := (data ->> 'endsAt')::date;
    exception when others then
      raise exception 'LEAGUE_BETA_EDITION_DATES_INVALID' using errcode = '22023';
    end;
    if length(selected_name) not between 3 and 120
       or length(selected_slug) not between 1 and 80
       or end_date < start_date
       or start_date < date '2020-01-01'
       or end_date > date '2100-12-31' then
      raise exception 'LEAGUE_BETA_EDITION_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'editionName', selected_name, 'seasonLabel', selected_slug,
      'startsAt', start_date, 'endsAt', end_date,
      'timezone', coalesce(nullif(trim(data ->> 'timezone'), ''), 'Europe/Madrid')
    );
  elsif target_step = 4 then
    begin
      team_cap := (data ->> 'teamCap')::integer;
      legs := (data ->> 'legs')::integer;
      closes_at := (data ->> 'registrationClosesAt')::timestamptz;
      bundle_cap := (target_bundle ->> 'teamCap')::integer;
    exception when others then
      raise exception 'LEAGUE_BETA_REGISTRATION_INVALID' using errcode = '22023';
    end;
    if team_cap < 4 or team_cap > 20 or team_cap > bundle_cap
       or legs not in (1, 2) or closes_at <= statement_timestamp()
       or upper(coalesce(data ->> 'registrationMode', '')) <> 'INVITE_ONLY' then
      raise exception 'BETA_CAPACITY_LIMIT' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'teamCap', team_cap, 'legs', legs,
      'registrationMode', 'INVITE_ONLY',
      'registrationClosesAt', closes_at
    );
  elsif target_step = 5 then
    begin
      minimum_size := (data ->> 'minimumRosterSize')::integer;
      maximum_size := (data ->> 'maximumRosterSize')::integer;
    exception when others then
      raise exception 'LEAGUE_BETA_ROSTER_INVALID' using errcode = '22023';
    end;
    if minimum_size < 1 or maximum_size < minimum_size or maximum_size > 50 then
      raise exception 'LEAGUE_BETA_ROSTER_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'minimumRosterSize', minimum_size,
      'maximumRosterSize', maximum_size,
      'credentialRequired', coalesce((data ->> 'credentialRequired')::boolean, true),
      'jerseyRequired', coalesce((data ->> 'jerseyRequired')::boolean, true),
      'closeRequiresApprovedRosters', coalesce(
        (data ->> 'closeRequiresApprovedRosters')::boolean, true
      )
    );
  elsif target_step = 6 then
    begin
      duration_minutes := (data ->> 'matchDurationMinutes')::integer;
      buffer_minutes := coalesce((data ->> 'requiredBufferMinutes')::integer, 10);
      confirmation_hours := coalesce((data ->> 'responseDeadlineHours')::integer, 48);
    exception when others then
      raise exception 'LEAGUE_BETA_MATCH_POLICY_INVALID' using errcode = '22023';
    end;
    if duration_minutes not between 20 and 180
       or buffer_minutes not between 0 and 120
       or confirmation_hours not between 1 and 720
       or coalesce((data ->> 'pointsForWin')::integer, -1) not between 0 and 10
       or coalesce((data ->> 'pointsForDraw')::integer, -1) not between 0 and 10
       or coalesce((data ->> 'pointsForLoss')::integer, -1) not between 0 and 10 then
      raise exception 'LEAGUE_BETA_MATCH_POLICY_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'matchDurationMinutes', duration_minutes,
      'requiredBufferMinutes', buffer_minutes,
      'pointsForWin', (data ->> 'pointsForWin')::integer,
      'pointsForDraw', (data ->> 'pointsForDraw')::integer,
      'pointsForLoss', (data ->> 'pointsForLoss')::integer,
      'responseDeadlineHours', confirmation_hours,
      'autoOfficialAfterConfirmation', coalesce(
        (data ->> 'autoOfficialAfterConfirmation')::boolean, true
      )
    );
  elsif target_step = 7 then
    patterns := coalesce(data -> 'weeklyPattern', '[]'::jsonb);
    if jsonb_typeof(patterns) <> 'array' or jsonb_array_length(patterns) > 14 then
      raise exception 'LEAGUE_BETA_CALENDAR_POLICY_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'weeklyPattern', patterns,
      'venueRequired', coalesce((data ->> 'venueRequired')::boolean, false),
      'allowTbd', coalesce((data ->> 'allowTbd')::boolean, true),
      'minimumRestMinutes', coalesce((data ->> 'minimumRestMinutes')::integer, 0),
      'useDivision', coalesce((data ->> 'useDivision')::boolean, true)
    );
  elsif target_step = 8 then
    tie_breaks := coalesce(data -> 'tieBreakCriteria', '[]'::jsonb);
    if jsonb_typeof(tie_breaks) <> 'array' or jsonb_array_length(tie_breaks) = 0 then
      raise exception 'LEAGUE_BETA_TIE_BREAK_INVALID' using errcode = '22023';
    end if;
    for criterion in select upper(trim(value #>> '{}')) from jsonb_array_elements(tie_breaks)
    loop
      if criterion not in (
        'POINTS', 'GOAL_DIFFERENCE', 'GOALS_FOR', 'WINS',
        'HEAD_TO_HEAD_POINTS', 'HEAD_TO_HEAD_GOAL_DIFFERENCE',
        'HEAD_TO_HEAD_GOALS_FOR', 'PERSISTED_DRAW_LOT'
      ) then raise exception 'LEAGUE_BETA_TIE_BREAK_INVALID' using errcode = '22023'; end if;
    end loop;
    return jsonb_build_object(
      'tieBreakCriteria', tie_breaks,
      'scorerDetailPolicy', case upper(coalesce(data ->> 'scorerDetailPolicy', 'OPTIONAL'))
        when 'REQUIRED' then 'REQUIRED'
        when 'DISABLED' then 'DISABLED'
        else 'OPTIONAL'
      end,
      'allowUnknownScorer', coalesce((data ->> 'allowUnknownScorer')::boolean, false),
      'allowSharedPositions', coalesce((data ->> 'allowSharedPositions')::boolean, true)
    );
  elsif target_step = 9 then
    if coalesce((data ->> 'postponementResponseDeadlineHours')::integer, 0) not between 1 and 720
       or coalesce((data ->> 'gracePeriodMinutes')::integer, -1) not between 0 and 180
       or coalesce((data ->> 'noShowWinnerScore')::integer, -1) not between 0 and 99
       or coalesce((data ->> 'noShowLoserScore')::integer, -1) not between 0 and 99 then
      raise exception 'LEAGUE_BETA_EXCEPTION_POLICY_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'postponementResponseDeadlineHours', (data ->> 'postponementResponseDeadlineHours')::integer,
      'postponementDeadlinePolicy', case upper(coalesce(data ->> 'postponementDeadlinePolicy', 'EXPIRE'))
        when 'ESCALATE_TO_ORGANIZER' then 'ESCALATE_TO_ORGANIZER'
        when 'AUTO_DENY' then 'AUTO_DENY'
        else 'EXPIRE'
      end,
      'organizerApprovalRequired', true,
      'organizerCanInterveneAfterDeadline', true,
      'gracePeriodMinutes', (data ->> 'gracePeriodMinutes')::integer,
      'minimumRestHours', coalesce((data ->> 'minimumRestHours')::integer, 0),
      'maximumMatchDurationMinutes', coalesce((data ->> 'maximumMatchDurationMinutes')::integer, 180),
      'noShowOutcome', case upper(coalesce(data ->> 'noShowOutcome', 'NO_SHOW'))
        when 'FORFEIT' then 'FORFEIT' else 'NO_SHOW' end,
      'noShowWinnerScore', (data ->> 'noShowWinnerScore')::integer,
      'noShowLoserScore', (data ->> 'noShowLoserScore')::integer,
      'resumptionPolicy', 'SAME_CANONICAL_MATCH'
    );
  elsif target_step = 10 then
    if not coalesce((data ->> 'consent')::boolean, false)
       or not coalesce((data ->> 'acknowledgeUnavailableFeatures')::boolean, false) then
      raise exception 'LEAGUE_BETA_CONSENT_REQUIRED' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'consent', true,
      'acknowledgeUnavailableFeatures', true,
      'discipline', 'NOT_AVAILABLE',
      'refereeAssignments', 'NOT_AVAILABLE',
      'payments', 'NOT_IMPLEMENTED',
      'tournaments', 'NOT_IMPLEMENTED'
    );
  end if;
  raise exception 'LEAGUE_BETA_STEP_INVALID' using errcode = '22023';
end;
$$;

create or replace function public.command_pachanga_league_private_beta_v1(
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
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare confirmed_revision bigint;
declare reason_text text;
declare aggregate_type text;
declare normalized_kind text;
declare organizer_id uuid;
declare organizer jsonb;
declare bundle jsonb;
declare normalized_step jsonb;
declare selected_step smallint;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare response jsonb;
declare state_was_missing boolean := false;
declare organizer_state public.pachanga_competition_organizer_states%rowtype;
declare wizard private.pachanga_league_private_beta_wizards%rowtype;
declare canonical_competition_id uuid;
declare rule_set_id uuid;
declare rule_revision_id uuid;
declare edition_id uuid;
declare category_id uuid;
declare stage_id uuid;
declare division_id uuid;
declare competition_group_id uuid;
declare staff_assignment_id uuid;
declare rule_document jsonb;
declare rule_checksum text;
declare identity_step jsonb;
declare modality_step jsonb;
declare edition_step jsonb;
declare registration_step jsonb;
declare roster_step jsonb;
declare calendar_step jsonb;
declare sport_format text;
declare step_number smallint;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or normalized_action = ''
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_LEAGUE_BETA_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  aggregate_type := case when normalized_action = 'wizard.create'
    then 'league_private_beta_organizer' else 'league_private_beta_wizard' end;
  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91407));
  replay := private.pachanga_league_private_beta_replay_v1(
    operation_id, actor_id, normalized_action, aggregate_type,
    aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  perform private.pachanga_league_private_beta_rate_limit_v1(
    actor_id,
    normalized_action,
    case when normalized_action = 'wizard.step.save' then 240 else 20 end,
    case when normalized_action = 'wizard.step.save' then interval '1 hour' else interval '1 day' end
  );
  sequence_value := nextval('private.pachanga_competition_sequence');
  reason_text := left(coalesce(nullif(trim(payload ->> 'reason'), ''), normalized_action), 120);

  if normalized_action = 'wizard.create' then
    normalized_kind := upper(trim(coalesce(payload ->> 'organizerKind', '')));
    organizer_id := aggregate_id;
    organizer := private.pachanga_league_private_beta_authorize_organizer_v1(
      normalized_kind, organizer_id, actor_id, true
    );
    if exists (
      select 1 from public.pachanga_competitions competitions
      where competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
        and competitions.status <> 'cancelled'
        and competitions.organizer_kind = normalized_kind
        and (
          (normalized_kind = 'TEAM' and competitions.organizer_group_id = organizer_id)
          or (normalized_kind = 'CLUB' and competitions.organizer_club_id = organizer_id)
        )
    ) then raise exception 'LEAGUE_BETA_ACTIVE_EDITION_LIMIT' using errcode = 'PT409'; end if;
    select * into organizer_state
    from public.pachanga_competition_organizer_states states
    where states.organizer_kind = normalized_kind and (
      (normalized_kind = 'TEAM' and states.organizer_group_id = organizer_id)
      or (normalized_kind = 'CLUB' and states.organizer_club_id = organizer_id)
    ) for update;
    if not found then
      state_was_missing := true;
      if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      insert into public.pachanga_competition_organizer_states(
        organizer_kind, organizer_group_id, organizer_club_id,
        revision, server_sequence, created_at, updated_at
      ) values (
        normalized_kind,
        case when normalized_kind = 'TEAM' then organizer_id else null end,
        case when normalized_kind = 'CLUB' then organizer_id else null end,
        1, sequence_value, confirmed_at, confirmed_at
      ) returning * into organizer_state;
      confirmed_revision := organizer_state.revision;
    elsif organizer_state.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    else
      update public.pachanga_competition_organizer_states states set
        revision = states.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where states.id = organizer_state.id
      returning states.revision into confirmed_revision;
    end if;
    insert into private.pachanga_league_private_beta_wizards(
      organizer_kind, organizer_group_id, organizer_club_id,
      created_by, status, current_step, completed_steps, step_data,
      revision, server_sequence, created_at, updated_at
    ) values (
      normalized_kind,
      case when normalized_kind = 'TEAM' then organizer_id else null end,
      case when normalized_kind = 'CLUB' then organizer_id else null end,
      actor_id, 'draft', 1, '{}'::smallint[], '{}'::jsonb,
      1, sequence_value, confirmed_at, confirmed_at
    ) returning * into wizard;
    snapshot := jsonb_build_object(
      'organizer', organizer,
      'organizerRevision', confirmed_revision,
      'wizard', private.pachanga_league_private_beta_wizard_snapshot_v1(wizard.id),
      'nextAction', 'complete_identity'
    );
    event_payload := jsonb_build_object('wizardId', wizard.id, 'status', wizard.status);
  elsif normalized_action in ('wizard.step.save', 'wizard.cancel', 'wizard.finalize') then
    select * into wizard
    from private.pachanga_league_private_beta_wizards wizards
    where wizards.id = aggregate_id for update;
    if not found then raise exception 'LEAGUE_BETA_WIZARD_NOT_FOUND' using errcode = 'P0002'; end if;
    normalized_kind := wizard.organizer_kind;
    organizer_id := coalesce(wizard.organizer_group_id, wizard.organizer_club_id);
    organizer := private.pachanga_league_private_beta_authorize_organizer_v1(
      normalized_kind, organizer_id, actor_id, normalized_action <> 'wizard.cancel'
    );
    bundle := organizer -> 'bundle';
    if wizard.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if wizard.status <> 'draft' then
      raise exception 'LEAGUE_BETA_WIZARD_NOT_EDITABLE' using errcode = '22023';
    end if;

    if normalized_action = 'wizard.step.save' then
      begin selected_step := (payload ->> 'step')::smallint;
      exception when others then
        raise exception 'LEAGUE_BETA_STEP_INVALID' using errcode = '22023';
      end;
      if selected_step not between 1 and 10 then
        raise exception 'LEAGUE_BETA_STEP_INVALID' using errcode = '22023';
      end if;
      if selected_step > 1 and exists (
        select 1 from generate_series(1, selected_step - 1) required_step
        where not (required_step::smallint = any(wizard.completed_steps))
      ) then raise exception 'LEAGUE_BETA_STEP_ORDER_REQUIRED' using errcode = 'PT409'; end if;
      normalized_step := private.pachanga_league_private_beta_normalize_step_v1(
        selected_step, payload -> 'data', bundle
      );
      update private.pachanga_league_private_beta_wizards wizards set
        step_data = jsonb_set(
          wizards.step_data, array[selected_step::text], normalized_step, true
        ),
        completed_steps = array(
          select distinct completed
          from unnest(wizards.completed_steps || selected_step) completed
          order by completed
        ),
        current_step = least(10, greatest(wizards.current_step, selected_step + 1)),
        consented_at = case when selected_step = 10 then confirmed_at else wizards.consented_at end,
        revision = wizards.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where wizards.id = wizard.id
      returning * into wizard;
      confirmed_revision := wizard.revision;
      snapshot := private.pachanga_league_private_beta_wizard_snapshot_v1(wizard.id);
      event_payload := jsonb_build_object(
        'wizardId', wizard.id, 'step', selected_step,
        'completedSteps', to_jsonb(wizard.completed_steps)
      );
    elsif normalized_action = 'wizard.cancel' then
      update private.pachanga_league_private_beta_wizards wizards set
        status = 'cancelled',
        revision = wizards.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where wizards.id = wizard.id
      returning * into wizard;
      confirmed_revision := wizard.revision;
      snapshot := private.pachanga_league_private_beta_wizard_snapshot_v1(wizard.id);
      event_payload := jsonb_build_object('wizardId', wizard.id, 'status', 'cancelled');
    else
      if not (
        array[1,2,3,4,5,6,7,8,9,10]::smallint[] <@ wizard.completed_steps
      ) then raise exception 'LEAGUE_BETA_WIZARD_INCOMPLETE' using errcode = '22023'; end if;
      for step_number in 1..10 loop
        perform private.pachanga_league_private_beta_normalize_step_v1(
          step_number::smallint, wizard.step_data -> step_number::text, bundle
        );
      end loop;
      if not coalesce((wizard.step_data #>> '{10,consent}')::boolean, false) then
        raise exception 'LEAGUE_BETA_CONSENT_REQUIRED' using errcode = '22023';
      end if;
      if exists (
        select 1 from public.pachanga_competitions competitions
        where competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
          and competitions.status <> 'cancelled'
          and competitions.organizer_kind = normalized_kind
          and (
            (normalized_kind = 'TEAM' and competitions.organizer_group_id = organizer_id)
            or (normalized_kind = 'CLUB' and competitions.organizer_club_id = organizer_id)
          )
      ) then raise exception 'LEAGUE_BETA_ACTIVE_EDITION_LIMIT' using errcode = 'PT409'; end if;

      identity_step := wizard.step_data -> '1';
      modality_step := wizard.step_data -> '2';
      edition_step := wizard.step_data -> '3';
      registration_step := wizard.step_data -> '4';
      roster_step := wizard.step_data -> '5';
      calendar_step := wizard.step_data -> '7';
      sport_format := case modality_step ->> 'modality'
        when 'FUTBOL_5' then 'FOOTBALL_5'
        when 'FUTBOL_7' then 'FOOTBALL_7'
        when 'FUTBOL_11' then 'FOOTBALL_11'
        when 'FUTSAL' then 'FUTSAL'
        else null end;
      rule_document := private.pachanga_league_private_beta_rule_document_v1(wizard.step_data);
      rule_checksum := private.pachanga_validate_competition_rule_document_v1(
        'competition_rules.v1', rule_document
      );
      canonical_competition_id := gen_random_uuid();
      rule_set_id := gen_random_uuid();
      rule_revision_id := gen_random_uuid();
      edition_id := gen_random_uuid();
      category_id := gen_random_uuid();
      stage_id := gen_random_uuid();
      competition_group_id := gen_random_uuid();
      if coalesce((calendar_step ->> 'useDivision')::boolean, true) then
        division_id := gen_random_uuid();
      end if;
      perform set_config('pachangas.league_private_beta_authorized', 'on', true);

      insert into public.pachanga_competitions(
        id, organizer_kind, organizer_group_id, organizer_club_id,
        name, slug, competition_type, visibility, status,
        product_key, description, general_area, image_url,
        revision, server_sequence, created_by, created_at, updated_at
      ) values (
        canonical_competition_id, normalized_kind,
        case when normalized_kind = 'TEAM' then organizer_id else null end,
        case when normalized_kind = 'CLUB' then organizer_id else null end,
        identity_step ->> 'name', identity_step ->> 'slug',
        'LEAGUE', 'private', 'draft', 'LEAGUE_PRIVATE_BETA_V1',
        coalesce(identity_step ->> 'description', ''),
        nullif(identity_step ->> 'generalArea', ''),
        nullif(identity_step ->> 'imageUrl', ''),
        1, nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      );
      insert into public.pachanga_competition_rule_sets(
        id, competition_id, name, status, revision, server_sequence,
        created_by, created_at, updated_at
      ) values (
        rule_set_id, canonical_competition_id, 'Reglamento Liga privada beta', 'active',
        1, nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      );
      insert into public.pachanga_competition_rule_revisions(
        id, rule_set_id, version, schema_version, rule_document, checksum,
        effective_from, effective_scope, status, revision, reason,
        server_sequence, created_by, created_at, updated_at
      ) values (
        rule_revision_id, rule_set_id, 1, 'competition_rules.v1',
        rule_document, rule_checksum, confirmed_at, 'future_only', 'frozen', 1,
        'LEAGUE_PRIVATE_BETA_V1 frozen wizard rules',
        nextval('private.pachanga_competition_sequence'), actor_id,
        confirmed_at, confirmed_at
      );
      insert into public.pachanga_competition_editions(
        id, competition_id, name, season_label, starts_at, ends_at,
        status, rule_revision_id, registration_mode,
        registration_opens_at, registration_closes_at,
        registration_rule_revision_id, revision, server_sequence,
        created_by, created_at, updated_at
      ) values (
        edition_id, canonical_competition_id,
        edition_step ->> 'editionName', edition_step ->> 'seasonLabel',
        (edition_step ->> 'startsAt')::date, (edition_step ->> 'endsAt')::date,
        'registration_open', rule_revision_id, 'INVITE_ONLY',
        confirmed_at, (registration_step ->> 'registrationClosesAt')::timestamptz,
        rule_revision_id, 1, nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      );
      insert into public.pachanga_competition_stages(
        id, edition_id, name, stage_type, stage_order, optional_stage,
        status, rule_revision_id, revision, server_sequence,
        created_by, created_at, updated_at
      ) values (
        stage_id, edition_id, 'Liga regular', 'LEAGUE_STAGE', 0, false,
        'draft', rule_revision_id, 1, nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      );
      if division_id is not null then
        insert into public.pachanga_competition_divisions(
          id, stage_id, name, division_order, level_label, status,
          revision, server_sequence, created_by, created_at, updated_at
        ) values (
          division_id, stage_id, 'División única', 0, 'Abierta', 'draft',
          1, nextval('private.pachanga_competition_sequence'),
          actor_id, confirmed_at, confirmed_at
        );
      end if;
      insert into public.pachanga_competition_groups(
        id, stage_id, division_id, name, group_order, status,
        revision, server_sequence, created_by, created_at, updated_at
      ) values (
        competition_group_id, stage_id, division_id, 'Grupo único', 0, 'draft',
        1, nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      );
      insert into public.pachanga_competition_categories(
        id, edition_id, name, slug, description, sport_format,
        eligibility_policy, visibility, status, rule_revision_id,
        revision, server_sequence, created_by, created_at, updated_at
      ) values (
        category_id, edition_id, 'General', 'general',
        'Categoría única de la Liga privada beta', sport_format,
        jsonb_build_object('credentialRequired', (roster_step ->> 'credentialRequired')::boolean),
        'private', 'active', rule_revision_id, 1,
        nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      );
      if normalized_kind = 'CLUB' and organizer ->> 'actorRole' = 'club_competition_manager' then
        staff_assignment_id := gen_random_uuid();
        insert into public.pachanga_competition_staff_assignments(
          id, competition_id, user_id, staff_role, status,
          revision, server_sequence, assigned_by, assigned_at, updated_at
        ) values (
          staff_assignment_id, canonical_competition_id, actor_id, 'competition_director',
          'active', 1, nextval('private.pachanga_competition_sequence'),
          actor_id, confirmed_at, confirmed_at
        );
      end if;

      perform private.pachanga_league_registration_limits_v1(rule_revision_id);
      perform private.pachanga_league_roster_limits_v1(rule_revision_id);
      perform private.pachanga_league_schedule_policy_v1(rule_revision_id);
      perform private.pachanga_league_match_policy_v1(rule_revision_id);
      perform private.pachanga_league_operational_policy_v1(rule_revision_id);

      update private.pachanga_league_private_beta_wizards wizards set
        status = 'completed',
        competition_id = canonical_competition_id,
        consented_at = coalesce(wizards.consented_at, confirmed_at),
        revision = wizards.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where wizards.id = wizard.id
      returning * into wizard;
      confirmed_revision := wizard.revision;
      update public.pachanga_competition_organizer_states states set
        revision = states.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where states.organizer_kind = normalized_kind and (
        (normalized_kind = 'TEAM' and states.organizer_group_id = organizer_id)
        or (normalized_kind = 'CLUB' and states.organizer_club_id = organizer_id)
      );
      snapshot := jsonb_build_object(
        'wizard', private.pachanga_league_private_beta_wizard_snapshot_v1(wizard.id),
        'canonical', jsonb_build_object(
          'competitionId', canonical_competition_id,
          'editionId', edition_id,
          'ruleSetId', rule_set_id,
          'ruleRevisionId', rule_revision_id,
          'categoryId', category_id,
          'stageId', stage_id,
          'divisionId', division_id,
          'groupId', competition_group_id,
          'staffAssignmentId', staff_assignment_id,
          'registrationMode', 'INVITE_ONLY',
          'visibility', 'private',
          'teamCap', (registration_step ->> 'teamCap')::integer,
          'legs', (registration_step ->> 'legs')::integer
        ),
        'nextAction', 'invite_teams',
        'unavailable', jsonb_build_array(
          'competition_discipline', 'referee_assignments', 'payments', 'tournaments'
        )
      );
      event_payload := jsonb_build_object(
        'wizardId', wizard.id,
        'competitionId', canonical_competition_id,
        'editionId', edition_id,
        'ruleRevisionId', rule_revision_id,
        'teamCap', (registration_step ->> 'teamCap')::integer,
        'legs', (registration_step ->> 'legs')::integer,
        'registrationMode', 'INVITE_ONLY'
      );
    end if;
  else
    raise exception 'LEAGUE_BETA_ACTION_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  response := private.pachanga_league_private_beta_store_v1(
    operation_id, actor_id, normalized_action, aggregate_type, aggregate_id,
    normalized_kind, organizer_id,
    case when normalized_action = 'wizard.create' then wizard.id else aggregate_id end,
    canonical_competition_id, confirmed_revision, sequence_value, reason_text,
    request_hash, client_metadata, event_payload, snapshot, confirmed_at
  );
  return response;
exception
  when unique_violation then raise exception 'LEAGUE_BETA_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

-- Existing organizer commands retain their role matrix. For beta competitions,
-- every non-read organizer action additionally requires an active product gate
-- and the complete, unexpired organizer bundle.
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
declare actor_role text := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
declare selected_competition public.pachanga_competitions%rowtype;
declare beta_enabled boolean;
begin
  if actor_role in ('service_authority', 'platform_owner', 'platform_admin') then return true; end if;
  select * into selected_competition
  from public.pachanga_competitions competitions where competitions.id = target_competition_id;
  if selected_competition.product_key = 'LEAGUE_PRIVATE_BETA_V1'
     and target_capability <> 'read' then
    select settings.league_private_beta_enabled into beta_enabled
    from private.pachanga_competition_foundation_settings settings where settings.singleton;
    if not coalesce(beta_enabled, false)
       or private.pachanga_league_private_beta_active_bundle_id_v1(
         selected_competition.organizer_kind,
         coalesce(selected_competition.organizer_group_id, selected_competition.organizer_club_id)
       ) is null then return false; end if;
  end if;
  if actor_role = 'competition_owner' then return true; end if;
  return case actor_role
    when 'competition_director' then target_capability in (
      'read', 'manage', 'staff', 'rules', 'referees', 'entries_manage',
      'rosters_review', 'categories_manage', 'schedule_read', 'schedule_manage',
      'schedule_publish', 'results_read', 'results_manage', 'standings_read',
      'standings_manage', 'operations_read', 'operations_manage'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'entries_manage', 'rosters_review', 'categories_manage',
      'schedule_read', 'schedule_manage', 'schedule_publish', 'results_read',
      'results_manage', 'standings_read', 'standings_manage',
      'operations_read', 'operations_manage'
    )
    when 'competition_operations_manager' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read',
      'operations_read', 'operations_manage'
    )
    when 'competition_schedule_manager' then target_capability in (
      'read', 'schedule_read', 'schedule_manage', 'schedule_publish', 'operations_read'
    )
    when 'competition_result_manager' then target_capability in (
      'read', 'results_read', 'results_manage', 'standings_read', 'operations_read'
    )
    when 'competition_standings_manager' then target_capability in (
      'read', 'results_read', 'standings_read', 'standings_manage', 'operations_read'
    )
    when 'competition_registration_manager' then target_capability in ('read', 'entries_manage')
    when 'competition_roster_manager' then target_capability in ('read', 'rosters_review')
    when 'rules_manager' then target_capability in ('read', 'rules')
    when 'competition_referee_manager' then target_capability in ('read', 'referees')
    when 'viewer' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read', 'operations_read'
    )
    else false
  end;
end;
$$;

create or replace function private.pachanga_league_private_beta_rule_document_v1(
  target_steps jsonb
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog
as $$
declare identity_step jsonb := target_steps -> '1';
declare modality_step jsonb := target_steps -> '2';
declare edition_step jsonb := target_steps -> '3';
declare registration_step jsonb := target_steps -> '4';
declare roster_step jsonb := target_steps -> '5';
declare match_step jsonb := target_steps -> '6';
declare calendar_step jsonb := target_steps -> '7';
declare result_step jsonb := target_steps -> '8';
declare incident_step jsonb := target_steps -> '9';
declare modality text := modality_step ->> 'modality';
declare canonical_modality text;
declare starters integer;
declare roster_maximum integer := (roster_step ->> 'maximumRosterSize')::integer;
declare starts_at text := edition_step ->> 'startsAt';
declare ends_at text := edition_step ->> 'endsAt';
begin
  canonical_modality := case modality
    when 'FUTBOL_5' then 'futbol5'
    when 'FUTBOL_7' then 'futbol7'
    when 'FUTBOL_11' then 'futbol11'
    when 'FUTSAL' then 'futbol_sala'
    else null end;
  starters := case modality
    when 'FUTBOL_5' then 5
    when 'FUTBOL_7' then 7
    when 'FUTBOL_11' then 11
    when 'FUTSAL' then 5
    else null end;
  if canonical_modality is null or roster_maximum < starters then
    raise exception 'LEAGUE_BETA_ROSTER_TOO_SMALL_FOR_MODALITY' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'identity', jsonb_build_object(
      'productKey', 'LEAGUE_PRIVATE_BETA_V1',
      'presetId', 'league_private_beta_v1',
      'presetVersion', 1,
      'competitionName', identity_step ->> 'name'
    ),
    'format', jsonb_build_object('modality', canonical_modality),
    'registration', jsonb_build_object(
      'registrationPolicy', jsonb_build_object(
        'mode', 'INVITE_ONLY',
        'teamLimits', jsonb_build_object(
          'minimum', 4,
          'maximum', (registration_step ->> 'teamCap')::integer
        )
      ),
      'rosterPolicy', jsonb_build_object(
        'minimumSize', (roster_step ->> 'minimumRosterSize')::integer,
        'maximumSize', roster_maximum,
        'multiTeamPolicy', 'FORBIDDEN_SAME_EDITION_CATEGORY',
        'closeRequiresApprovedRosters',
          (roster_step ->> 'closeRequiresApprovedRosters')::boolean
      ),
      'identityRequirements', jsonb_build_object(
        'credentialRequired', (roster_step ->> 'credentialRequired')::boolean
      ),
      'kitPolicy', jsonb_build_object(
        'jerseyRequired', (roster_step ->> 'jerseyRequired')::boolean,
        'jerseyNumberMinimum', 1,
        'jerseyNumberMaximum', 99
      ),
      'matchSheetPolicy', jsonb_build_object(
        'squadMin', starters,
        'squadMax', roster_maximum,
        'starterMin', starters,
        'starterMax', starters,
        'substituteMax', greatest(roster_maximum - starters, 0)
      )
    ),
    'structure', jsonb_build_object(
      'stageGraph', jsonb_build_object(
        'nodes', jsonb_build_array(jsonb_build_object(
          'id', 'league-stage', 'root', true, 'optional', false
        )),
        'edges', '[]'::jsonb
      )
    ),
    'operations', jsonb_build_object(
      'hardAvailabilityPolicy', jsonb_build_object('mode', 'required'),
      'schedulePreferencePolicy', jsonb_build_object('mode', 'preferred'),
      'schedulePolicy', jsonb_build_object(
        'format', 'ROUND_ROBIN',
        'legs', (registration_step ->> 'legs')::integer,
        'matchDurationMinutes', (match_step ->> 'matchDurationMinutes')::integer,
        'requiredBufferMinutes', (match_step ->> 'requiredBufferMinutes')::integer,
        'minimumRestMinutes', (calendar_step ->> 'minimumRestMinutes')::integer,
        'homeAwayPolicy', case when (registration_step ->> 'legs')::integer = 2
          then 'MIRRORED_SECOND_LEG' else 'BALANCED' end,
        'venueRequired', (calendar_step ->> 'venueRequired')::boolean,
        'maximumHomeAwayStreak', 3,
        'hardHomeAwayStreak', false,
        'windowStartsAt', starts_at || 'T00:00:00Z',
        'windowEndsAt', ends_at || 'T23:59:59Z',
        'rosterStatuses', jsonb_build_array('approved', 'locked'),
        'softPreferenceWeights', jsonb_build_object('day', 60, 'time', 30, 'homeAway', 10),
        'weeklyPattern', calendar_step -> 'weeklyPattern'
      ),
      'exceptionPolicy', jsonb_build_object(
        'postponementResponseDeadlineHours',
          (incident_step ->> 'postponementResponseDeadlineHours')::integer,
        'postponementDeadlinePolicy', incident_step ->> 'postponementDeadlinePolicy',
        'organizerApprovalRequired', true,
        'organizerCanInterveneAfterDeadline', true,
        'gracePeriodMinutes', (incident_step ->> 'gracePeriodMinutes')::integer,
        'minimumRestHours', (incident_step ->> 'minimumRestHours')::integer,
        'maximumMatchDurationMinutes',
          (incident_step ->> 'maximumMatchDurationMinutes')::integer,
        'noShowOutcome', incident_step ->> 'noShowOutcome',
        'noShowWinnerScore', (incident_step ->> 'noShowWinnerScore')::integer,
        'noShowLoserScore', (incident_step ->> 'noShowLoserScore')::integer,
        'resumptionPolicy', 'SAME_CANONICAL_MATCH',
        'stageWindowStart', starts_at || 'T00:00:00Z',
        'stageWindowEnd', ends_at || 'T23:59:59Z',
        'venuePolicy', jsonb_build_object(
          'allowSavedVenue', true,
          'allowVenueLabel', true,
          'allowTbd', (calendar_step ->> 'allowTbd')::boolean
        ),
        'resumptionEligibilityPolicy', jsonb_build_object(
          'allowOriginalSquad', true,
          'allowReplacementForDocumentedInjury', false,
          'requireOriginalEligibility', true
        )
      )
    ),
    'results', jsonb_build_object(
      'scoringPolicy', jsonb_build_object(
        'pointsForWin', (match_step ->> 'pointsForWin')::integer,
        'pointsForDraw', (match_step ->> 'pointsForDraw')::integer,
        'pointsForLoss', (match_step ->> 'pointsForLoss')::integer
      ),
      'tieBreakCriteria', result_step -> 'tieBreakCriteria',
      'scorerDetailPolicy', result_step ->> 'scorerDetailPolicy',
      'allowUnknownScorer', (result_step ->> 'allowUnknownScorer')::boolean,
      'confirmationPolicy', jsonb_build_object(
        'mode', 'BILATERAL',
        'responseDeadlineHours', (match_step ->> 'responseDeadlineHours')::integer,
        'autoOfficialAfterConfirmation',
          (match_step ->> 'autoOfficialAfterConfirmation')::boolean
      ),
      'standingsPolicy', jsonb_build_object(
        'allowSharedPositions', (result_step ->> 'allowSharedPositions')::boolean
      ),
      'publicationPolicy', jsonb_build_object(
        'resultsPublic', false,
        'standingsPublic', false
      )
    ),
    'discipline', jsonb_build_object('enabled', false, 'status', 'NOT_AVAILABLE'),
    'governance', jsonb_build_object(
      'registrationMode', 'INVITE_ONLY',
      'organizerConsentRequired', true
    ),
    'publication', jsonb_build_object(
      'visibility', 'private',
      'calendarVisibility', 'participants_only',
      'standingsVisibility', 'participants_only',
      'exceptionVisibility', 'participants_only'
    ),
    'futureCapabilities', jsonb_build_object(
      'refereeAssignments', false,
      'discipline', false,
      'payments', false,
      'tournaments', false
    )
  );
end;
$$;

create or replace function public.command_pachanga_league_private_beta_platform_v1(
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
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare confirmed_revision bigint;
declare reason_text text;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare response jsonb;
declare normalized_kind text;
declare organizer_id uuid;
declare selected_bundle_id uuid;
declare team_cap integer;
declare expires_at timestamptz;
declare valid_from timestamptz;
declare state_was_missing boolean := false;
declare organizer_state public.pachanga_competition_organizer_states%rowtype;
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare next_enabled boolean;
declare next_creation boolean;
declare next_public boolean;
declare capability_name text;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or normalized_action = ''
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_LEAGUE_BETA_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'Authentication required' using errcode = '42501';
    end if;
  else
    perform private.pachanga_platform_require_v1('competitions.manage');
    if normalized_action in ('beta.flags.set', 'beta.kill_switch') then
      perform private.pachanga_platform_require_v1('flags.write');
    end if;
  end if;

  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91408));
  replay := private.pachanga_league_private_beta_replay_v1(
    operation_id, actor_id, normalized_action, 'league_private_beta_platform',
    aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  perform private.pachanga_league_private_beta_rate_limit_v1(
    actor_id, normalized_action, 120, interval '1 hour'
  );
  sequence_value := nextval('private.pachanga_competition_sequence');
  reason_text := trim(coalesce(payload ->> 'reason', ''));
  if length(reason_text) < 3 then
    raise exception 'LEAGUE_BETA_REASON_REQUIRED' using errcode = '22023';
  end if;

  if normalized_action in ('beta.flags.set', 'beta.kill_switch') then
    if aggregate_id <> '00000000-0000-0000-0000-00000000b201'::uuid then
      raise exception 'INVALID_LEAGUE_BETA_FLAGS_AGGREGATE' using errcode = '22023';
    end if;
    select * into settings
    from private.pachanga_competition_foundation_settings current_settings
    where current_settings.singleton for update;
    if settings.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;

    if normalized_action = 'beta.kill_switch' then
      update private.pachanga_competition_foundation_settings foundation_settings set
        league_private_beta_creation_enabled = false,
        league_private_beta_enabled = false,
        league_private_beta_public_discovery_enabled = false,
        league_public_registration_enabled = false,
        league_public_calendar_enabled = false,
        league_public_standings_enabled = false,
        league_public_exception_status_enabled = false,
        league_administrative_decisions_enabled = false,
        league_match_suspensions_enabled = false,
        league_no_show_enabled = false,
        league_late_arrival_enabled = false,
        league_venue_changes_enabled = false,
        league_rescheduling_enabled = false,
        league_postponements_enabled = false,
        league_operational_exceptions_foundation_enabled = false,
        league_standings_enabled = false,
        league_official_results_enabled = false,
        league_result_confirmation_enabled = false,
        league_sporting_results_enabled = false,
        league_match_attendance_enabled = false,
        league_match_squads_enabled = false,
        league_match_operations_foundation_enabled = false,
        league_canonical_fixture_creation_enabled = false,
        league_schedule_publication_enabled = false,
        league_schedule_editing_enabled = false,
        league_schedule_generation_enabled = false,
        league_scheduling_foundation_enabled = false,
        league_schedule_preferences_enabled = false,
        league_rosters_enabled = false,
        league_delegates_enabled = false,
        league_registration_enabled = false,
        league_participation_foundation_enabled = false,
        context_binding_enabled = false,
        creation_enabled = false,
        foundation_enabled = false,
        revision = foundation_settings.revision + 1,
        server_sequence = sequence_value,
        updated_by = actor_id,
        updated_at = confirmed_at
      where foundation_settings.singleton
      returning foundation_settings.revision into confirmed_revision;
      update private.pachanga_club_foundation_settings club_settings set
        club_competition_organizer_enabled = false,
        revision = club_settings.revision + 1,
        server_sequence = sequence_value,
        updated_by = actor_id,
        updated_at = confirmed_at
      where club_settings.singleton;
      snapshot := jsonb_build_object(
        'enabled', false, 'creationEnabled', false,
        'publicDiscoveryEnabled', false,
        'killSwitchApplied', true,
        'revision', confirmed_revision,
        'updatedAt', confirmed_at
      );
    else
      if (payload ? 'enabled' and jsonb_typeof(payload -> 'enabled') <> 'boolean')
         or (payload ? 'creationEnabled' and jsonb_typeof(payload -> 'creationEnabled') <> 'boolean')
         or (payload ? 'publicDiscoveryEnabled' and jsonb_typeof(payload -> 'publicDiscoveryEnabled') <> 'boolean') then
        raise exception 'INVALID_LEAGUE_BETA_FLAG' using errcode = '22023';
      end if;
      next_enabled := coalesce((payload ->> 'enabled')::boolean, settings.league_private_beta_enabled);
      next_creation := coalesce(
        (payload ->> 'creationEnabled')::boolean,
        settings.league_private_beta_creation_enabled
      );
      next_public := coalesce(
        (payload ->> 'publicDiscoveryEnabled')::boolean,
        settings.league_private_beta_public_discovery_enabled
      );
      if not next_enabled then next_creation := false; end if;
      if next_public then
        raise exception 'LEAGUE_PRIVATE_BETA_PUBLIC_DISCOVERY_DISABLED' using errcode = '0A000';
      end if;
      if next_enabled and exists (
        select 1 from private.pachanga_referee_foundation_settings referee_settings
        where referee_settings.singleton and referee_settings.referee_assignments_enabled
      ) then
        raise exception 'REFEREE_ASSIGNMENTS_NOT_AVAILABLE_IN_LEAGUE_BETA' using errcode = '0A000';
      end if;
      update private.pachanga_competition_foundation_settings foundation_settings set
        league_private_beta_enabled = next_enabled,
        league_private_beta_creation_enabled = next_creation,
        league_private_beta_public_discovery_enabled = false,
        revision = foundation_settings.revision + 1,
        server_sequence = sequence_value,
        updated_by = actor_id,
        updated_at = confirmed_at
      where foundation_settings.singleton
      returning foundation_settings.revision into confirmed_revision;
      snapshot := jsonb_build_object(
        'enabled', next_enabled,
        'creationEnabled', next_creation,
        'publicDiscoveryEnabled', false,
        'maxActiveEditionsPerOrganizer', settings.league_private_beta_max_active_editions_per_organizer,
        'defaultTeamCap', settings.league_private_beta_default_team_cap,
        'revision', confirmed_revision,
        'updatedAt', confirmed_at
      );
    end if;
    event_payload := snapshot - 'updatedAt';
  elsif normalized_action in ('beta.bundle.grant', 'beta.bundle.revoke') then
    normalized_kind := upper(trim(coalesce(payload ->> 'organizerKind', '')));
    organizer_id := aggregate_id;
    if normalized_kind = 'TEAM' then
      perform 1 from public.pachanga_groups groups where groups.id = organizer_id for update;
      if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    elsif normalized_kind = 'CLUB' then
      perform 1 from public.pachanga_clubs clubs where clubs.id = organizer_id for update;
      if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    else
      raise exception 'INVALID_ORGANIZER_KIND' using errcode = '22023';
    end if;
    select * into organizer_state
    from public.pachanga_competition_organizer_states states
    where states.organizer_kind = normalized_kind and (
      (normalized_kind = 'TEAM' and states.organizer_group_id = organizer_id)
      or (normalized_kind = 'CLUB' and states.organizer_club_id = organizer_id)
    ) for update;
    if not found then
      state_was_missing := true;
      if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      insert into public.pachanga_competition_organizer_states(
        organizer_kind, organizer_group_id, organizer_club_id,
        revision, server_sequence, created_at, updated_at
      ) values (
        normalized_kind,
        case when normalized_kind = 'TEAM' then organizer_id else null end,
        case when normalized_kind = 'CLUB' then organizer_id else null end,
        1, sequence_value, confirmed_at, confirmed_at
      ) returning * into organizer_state;
      confirmed_revision := organizer_state.revision;
    elsif organizer_state.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;

    if normalized_action = 'beta.bundle.grant' then
      select * into settings
      from private.pachanga_competition_foundation_settings current_settings
      where current_settings.singleton;
      begin
        team_cap := coalesce(
          nullif(payload ->> 'maxTeams', '')::integer,
          settings.league_private_beta_default_team_cap
        );
        valid_from := coalesce(
          nullif(payload ->> 'validFrom', '')::timestamptz,
          statement_timestamp()
        );
        expires_at := nullif(payload ->> 'expiresAt', '')::timestamptz;
      exception when others then
        raise exception 'LEAGUE_BETA_GRANT_INVALID' using errcode = '22023';
      end;
      if team_cap < 4 or team_cap > 20
         or (team_cap > 12 and not coalesce((payload ->> 'capacityOverride')::boolean, false)) then
        raise exception 'BETA_CAPACITY_LIMIT' using errcode = '22023';
      end if;
      if expires_at is not null and expires_at <= greatest(valid_from, confirmed_at) then
        raise exception 'LEAGUE_BETA_GRANT_EXPIRY_INVALID' using errcode = '22023';
      end if;
      if exists (
        select 1 from public.pachanga_competition_entitlement_grants grants
        where grants.organizer_kind = normalized_kind
          and (
            (normalized_kind = 'TEAM' and grants.organizer_group_id = organizer_id)
            or (normalized_kind = 'CLUB' and grants.organizer_club_id = organizer_id)
          )
          and grants.capability = any(private.pachanga_league_private_beta_capabilities_v1())
          and grants.status = 'active'
          and grants.valid_from <= confirmed_at
          and (grants.expires_at is null or grants.expires_at > confirmed_at)
      ) then raise exception 'LEAGUE_BETA_ENTITLEMENT_CONFLICT' using errcode = 'PT409'; end if;
      selected_bundle_id := gen_random_uuid();
      foreach capability_name in array private.pachanga_league_private_beta_capabilities_v1()
      loop
        insert into public.pachanga_competition_entitlement_grants(
          organizer_kind, organizer_group_id, organizer_club_id,
          capability, grant_source, status, valid_from, expires_at,
          reason, revision, server_sequence, granted_by,
          program_key, bundle_id, beta_team_cap, created_at, updated_at
        ) values (
          normalized_kind,
          case when normalized_kind = 'TEAM' then organizer_id else null end,
          case when normalized_kind = 'CLUB' then organizer_id else null end,
          capability_name, 'platform_grant', 'active', valid_from, expires_at,
          left('LEAGUE_PRIVATE_BETA_V1: ' || reason_text, 1200),
          1, sequence_value, actor_id,
          'LEAGUE_PRIVATE_BETA_V1', selected_bundle_id, team_cap, confirmed_at, confirmed_at
        );
      end loop;
      event_payload := jsonb_build_object(
        'bundleId', selected_bundle_id, 'teamCap', team_cap,
        'expiresAt', expires_at,
        'capabilityCount', cardinality(private.pachanga_league_private_beta_capabilities_v1())
      );
    else
      selected_bundle_id := nullif(payload ->> 'bundleId', '')::uuid;
      if selected_bundle_id is null then
        raise exception 'LEAGUE_BETA_BUNDLE_REQUIRED' using errcode = '22023';
      end if;
      if not exists (
        select 1 from public.pachanga_competition_entitlement_grants grants
        where grants.bundle_id = selected_bundle_id
          and grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
          and grants.organizer_kind = normalized_kind
          and (
            (normalized_kind = 'TEAM' and grants.organizer_group_id = organizer_id)
            or (normalized_kind = 'CLUB' and grants.organizer_club_id = organizer_id)
          )
          and grants.status = 'active'
      ) then raise exception 'LEAGUE_BETA_BUNDLE_NOT_ACTIVE' using errcode = 'P0002'; end if;
      update public.pachanga_competition_entitlement_grants grants set
        status = 'revoked',
        revision = grants.revision + 1,
        server_sequence = sequence_value,
        revoked_by = actor_id,
        revoked_at = confirmed_at,
        updated_at = confirmed_at
      where grants.bundle_id = selected_bundle_id
        and grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
        and grants.status = 'active';
      event_payload := jsonb_build_object('bundleId', selected_bundle_id, 'status', 'revoked');
    end if;
    if not state_was_missing then
      update public.pachanga_competition_organizer_states states set
        revision = states.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where states.id = organizer_state.id
      returning states.revision into confirmed_revision;
    end if;
    snapshot := jsonb_build_object(
      'organizerKind', normalized_kind,
      'organizerId', organizer_id,
      'organizerRevision', confirmed_revision,
      'bundle', private.pachanga_league_private_beta_bundle_snapshot_v1(
        normalized_kind, organizer_id
      )
    );
  else
    raise exception 'LEAGUE_BETA_PLATFORM_ACTION_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  response := private.pachanga_league_private_beta_store_v1(
    operation_id, actor_id, normalized_action, 'league_private_beta_platform',
    aggregate_id, normalized_kind, organizer_id, null, null,
    confirmed_revision, sequence_value, reason_text, request_hash,
    client_metadata, event_payload, snapshot, confirmed_at
  );
  return response;
exception
  when unique_violation then raise exception 'LEAGUE_BETA_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_league_private_beta_capabilities_v1()'::regprocedure,
    'private.pachanga_league_private_beta_active_bundle_id_v1(text,uuid)'::regprocedure,
    'private.pachanga_league_private_beta_bundle_snapshot_v1(text,uuid)'::regprocedure,
    'private.pachanga_league_private_beta_authorize_organizer_v1(text,uuid,uuid,boolean)'::regprocedure,
    'private.pachanga_league_private_beta_rate_limit_v1(uuid,text,integer,interval)'::regprocedure,
    'private.pachanga_league_private_beta_replay_v1(uuid,uuid,text,text,uuid,text)'::regprocedure,
    'private.pachanga_league_private_beta_store_v1(uuid,uuid,text,text,uuid,text,uuid,uuid,uuid,bigint,bigint,text,text,jsonb,jsonb,jsonb,timestamptz)'::regprocedure,
    'private.pachanga_league_private_beta_wizard_snapshot_v1(uuid)'::regprocedure,
    'private.pachanga_league_private_beta_normalize_step_v1(smallint,jsonb,jsonb)'::regprocedure,
    'private.pachanga_league_private_beta_rule_document_v1(jsonb)'::regprocedure,
    'private.pachanga_competition_can_v1(uuid,uuid,text)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

revoke all on function public.command_pachanga_league_private_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_private_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

revoke all on function public.command_pachanga_league_private_beta_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_private_beta_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;

comment on function public.command_pachanga_league_private_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is 'Idempotent private-beta wizard. Finalize materializes one canonical R1/R4 League graph in one transaction.';
comment on function public.command_pachanga_league_private_beta_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is 'Platform-only private-beta flags, existing-entitlement bundle and emergency kill switch.';
