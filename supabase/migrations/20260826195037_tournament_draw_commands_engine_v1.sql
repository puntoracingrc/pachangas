-- Pachangas IQ R6A: private Tournament commands and deterministic draw engine.
-- Browser clients send intentions only. PostgreSQL owns identity, seed, placement,
-- validation, publication, sequence and time.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_tournament_capabilities_v1()
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select array[
    'tournament_create',
    'tournament_manage',
    'tournament_draw',
    'tournament_draw_publish'
  ]::text[];
$$;

create or replace function private.pachanga_tournament_active_bundle_id_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns uuid
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with candidates as (
    select grants.bundle_id,
      max(grants.server_sequence) as latest_sequence,
      count(distinct grants.capability) filter (
        where grants.status = 'active'
          and grants.valid_from <= statement_timestamp()
          and (grants.expires_at is null or grants.expires_at > statement_timestamp())
      ) as active_capabilities
    from public.pachanga_competition_entitlement_grants grants
    where grants.program_key = 'TOURNAMENT_PRIVATE_BETA_V1'
      and grants.organizer_kind = upper(trim(target_organizer_kind))
      and (
        (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
        or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
      )
      and grants.capability = any(private.pachanga_tournament_capabilities_v1())
    group by grants.bundle_id
  )
  select candidates.bundle_id
  from candidates
  where candidates.active_capabilities = cardinality(private.pachanga_tournament_capabilities_v1())
  order by candidates.latest_sequence desc, candidates.bundle_id desc
  limit 1;
$$;

create or replace function private.pachanga_tournament_bundle_snapshot_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with bundles as (
    select grants.bundle_id,
      max(grants.beta_team_cap) as team_cap,
      min(grants.valid_from) as valid_from,
      max(grants.expires_at) as expires_at,
      max(grants.server_sequence) as latest_sequence,
      bool_or(grants.status = 'revoked') as has_revoked,
      count(distinct grants.capability) filter (
        where grants.status = 'active'
          and grants.valid_from <= statement_timestamp()
          and (grants.expires_at is null or grants.expires_at > statement_timestamp())
      ) as active_capabilities,
      jsonb_agg(jsonb_build_object(
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
    where grants.program_key = 'TOURNAMENT_PRIVATE_BETA_V1'
      and grants.organizer_kind = upper(trim(target_organizer_kind))
      and (
        (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
        or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
      )
      and grants.capability = any(private.pachanga_tournament_capabilities_v1())
    group by grants.bundle_id
  ), selected as (
    select * from bundles order by latest_sequence desc, bundle_id desc limit 1
  )
  select coalesce((
    select jsonb_build_object(
      'bundleId', selected.bundle_id,
      'programKey', 'TOURNAMENT_PRIVATE_BETA_V1',
      'status', case
        when selected.active_capabilities = cardinality(private.pachanga_tournament_capabilities_v1())
          then 'active'
        when selected.expires_at is not null and selected.expires_at <= statement_timestamp()
          then 'expired'
        when selected.has_revoked then 'revoked'
        else 'incomplete'
      end,
      'teamCap', selected.team_cap,
      'validFrom', selected.valid_from,
      'expiresAt', selected.expires_at,
      'capabilities', selected.grants
    ) from selected
  ), jsonb_build_object(
    'programKey', 'TOURNAMENT_PRIVATE_BETA_V1',
    'status', 'not_granted',
    'capabilities', '[]'::jsonb
  ));
$$;

create or replace function private.pachanga_tournament_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.tournament_foundation_enabled,
    'privateBetaEnabled', settings.tournament_private_beta_enabled,
    'creationEnabled', settings.tournament_creation_enabled,
    'drawEnabled', settings.tournament_draw_enabled,
    'automaticEnabled', settings.tournament_automatic_draw_enabled,
    'manualEnabled', settings.tournament_draw_manual_enabled,
    'hybridEnabled', settings.tournament_draw_hybrid_enabled,
    'publishEnabled', settings.tournament_draw_publish_enabled,
    'publicDiscoveryEnabled', settings.tournament_public_discovery_enabled,
    'matchGenerationEnabled', settings.tournament_match_generation_enabled,
    'bracketProgressionEnabled', settings.tournament_bracket_progression_enabled,
    'standardTeamCap', settings.tournament_standard_team_cap,
    'overrideTeamCap', settings.tournament_override_team_cap,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_tournament_assert_flags_v1(
  require_creation boolean default false,
  require_draw boolean default false,
  require_automatic boolean default false,
  require_manual boolean default false,
  require_hybrid boolean default false,
  require_publish boolean default false
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.tournament_foundation_enabled
     or not settings.tournament_private_beta_enabled then
    raise exception 'TOURNAMENT_PRIVATE_BETA_DISABLED' using errcode = '42501';
  end if;
  if require_creation and not settings.tournament_creation_enabled then
    raise exception 'TOURNAMENT_CREATION_DISABLED' using errcode = '42501';
  end if;
  if require_draw and not settings.tournament_draw_enabled then
    raise exception 'TOURNAMENT_DRAW_DISABLED' using errcode = '42501';
  end if;
  if require_automatic and not settings.tournament_automatic_draw_enabled then
    raise exception 'TOURNAMENT_AUTOMATIC_DRAW_DISABLED' using errcode = '42501';
  end if;
  if require_manual and not settings.tournament_draw_manual_enabled then
    raise exception 'TOURNAMENT_MANUAL_DRAW_DISABLED' using errcode = '42501';
  end if;
  if require_hybrid and not settings.tournament_draw_hybrid_enabled then
    raise exception 'TOURNAMENT_HYBRID_DRAW_DISABLED' using errcode = '42501';
  end if;
  if require_publish and not settings.tournament_draw_publish_enabled then
    raise exception 'TOURNAMENT_DRAW_PUBLISH_DISABLED' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.command_pachanga_tournament_draw_v1(
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
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare allowed_keys text[];
declare request_hash text;
declare replay jsonb;
declare sequence_value bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare confirmed_revision bigint;
declare response jsonb;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare competition_row public.pachanga_competitions%rowtype;
declare organizer_state public.pachanga_competition_organizer_states%rowtype;
declare organizer jsonb;
declare organizer_kind text;
declare organizer_id uuid;
declare bundle jsonb;
declare bundle_cap integer;
declare rule_document jsonb;
declare rule_checksum text;
declare rule_set_id uuid;
declare rule_revision_id uuid;
declare previous_rule_revision_id uuid;
declare next_rule_version integer;
declare edition_id uuid;
declare stage_id uuid;
declare category_id uuid;
declare plan_id uuid;
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare revision_row public.pachanga_competition_draw_revisions%rowtype;
declare entry_row public.pachanga_competition_entries%rowtype;
declare invitation_row public.pachanga_competition_entry_invitations%rowtype;
declare freeze_row public.pachanga_competition_participant_freezes%rowtype;
declare participant_snapshot jsonb;
declare participant_count integer;
declare entry_ids uuid[];
declare freeze_checksum text;
declare freeze_id uuid;
declare target_id uuid;
declare second_id uuid;
declare pot_row public.pachanga_competition_draw_pots%rowtype;
declare constraint_row public.pachanga_competition_draw_constraints%rowtype;
declare lock_row public.pachanga_competition_draw_manual_locks%rowtype;
declare target_type text;
declare draw_mode text;
declare seed_mode text;
declare selected_seed text;
declare group_count integer;
declare slot_count integer;
declare qualifiers integer;
declare entry_pot integer;
declare solution jsonb;
declare placements jsonb;
declare byes jsonb;
declare left_placement jsonb;
declare right_placement jsonb;
declare next_revision_id uuid;
declare quality jsonb;
declare group_id uuid;
declare group_number integer;
declare placement jsonb;
declare team_owner_id uuid;
declare notification record;
declare actor_role text;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or normalized_action = ''
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_TOURNAMENT_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if payload ?| array[
    'actorId', 'serverSequence', 'confirmedRevision', 'confirmedAt',
    'publishedAt', 'result', 'placements', 'quality', 'algorithmVersion',
    'inputChecksum', 'resultChecksum', 'seedResult'
  ] then raise exception 'TOURNAMENT_SERVER_FIELDS_FORBIDDEN' using errcode = '22023'; end if;

  allowed_keys := case normalized_action
    when 'tournament.create' then array[
      'organizerKind','name','slug','description','generalArea','modality',
      'editionName','seasonLabel','startsAt','endsAt','participantCap',
      'groupCount','qualifiersPerGroup','drawTarget','drawMode',
      'registrationClosesAt','authoringMode','sourcePresetKey',
      'discipline','referees','reason'
    ]
    when 'tournament.authoring.save' then array[
      'name','slug','description','generalArea','modality','editionName',
      'seasonLabel','startsAt','endsAt','participantCap','groupCount',
      'qualifiersPerGroup','drawTarget','drawMode','registrationClosesAt',
      'authoringMode','sourcePresetKey','discipline','referees','reason'
    ]
    when 'tournament.cancel' then array['reason']
    when 'participant.invite' then array['teamId','reason']
    when 'participant.accept' then array['entryId','reason']
    when 'participant.decline' then array['entryId','reason']
    when 'participant.withdraw' then array['entryId','reason']
    when 'draw_plan.create' then array[
      'editionId','stageId','ruleRevisionId','targetType','mode',
      'groupCount','slotCount','qualifiersPerGroup','reason'
    ]
    when 'participants.freeze' then array['planId','reason']
    when 'participants.unfreeze' then array['planId','reason']
    when 'draw_pot.create' then array[
      'planId','potNumber','label','capacity','entryIds','seedingPolicy','reason'
    ]
    when 'draw_pot.update' then array[
      'planId','potId','label','capacity','entryIds','seedingPolicy','reason'
    ]
    when 'draw_constraint.create' then array[
      'planId','constraintType','strength','weight','scope','parameters',
      'reason','publicAttribution'
    ]
    when 'draw_constraint.update' then array[
      'planId','constraintId','strength','weight','scope','parameters',
      'reason','publicAttribution'
    ]
    when 'draw_constraint.remove' then array['planId','constraintId','reason']
    when 'draw.generate' then array['planId','seedMode','publicSeed','reason']
    when 'draw.regenerate' then array['planId','seedMode','publicSeed','reason']
    when 'draw.entry.place' then array[
      'planId','entryId','groupNumber','slotNumber','seedNumber','reason'
    ]
    when 'draw.entry.move' then array[
      'planId','entryId','groupNumber','slotNumber','seedNumber','reason'
    ]
    when 'draw.entry.swap' then array['planId','entryId','otherEntryId','reason']
    when 'draw.entry.remove' then array['planId','entryId','reason']
    when 'draw.lock.create' then array[
      'planId','lockType','entryId','relatedEntryId','groupNumber',
      'slotNumber','half','potNumber','reason'
    ]
    when 'draw.lock.remove' then array['planId','lockId','reason']
    when 'draw.validate' then array['planId','reason']
    when 'draw.publish' then array['planId','reason']
    when 'draw.cancel' then array['planId','reason']
    else null
  end;
  if allowed_keys is null then
    raise exception 'TOURNAMENT_ACTION_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if payload - allowed_keys <> '{}'::jsonb then
    raise exception 'TOURNAMENT_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91601));
  replay := private.pachanga_tournament_replay_v1(
    operation_id, actor_id, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;

  if normalized_action = 'tournament.create' then
    organizer_kind := upper(trim(coalesce(payload ->> 'organizerKind', '')));
    organizer_id := aggregate_id;
    organizer := private.pachanga_tournament_authorize_organizer_v1(
      organizer_kind, organizer_id, actor_id, true
    );
    bundle := organizer -> 'bundle';
    bundle_cap := (bundle ->> 'teamCap')::integer;
    if coalesce(nullif(payload ->> 'participantCap', '')::integer, least(16, bundle_cap))
       > bundle_cap then raise exception 'BETA_CAPACITY_LIMIT' using errcode = '22023'; end if;
    select * into organizer_state
    from public.pachanga_competition_organizer_states states
    where states.organizer_kind = organizer_kind and (
      (organizer_kind = 'TEAM' and states.organizer_group_id = organizer_id)
      or (organizer_kind = 'CLUB' and states.organizer_club_id = organizer_id)
    ) for update;
    sequence_value := nextval('private.pachanga_competition_sequence');
    if not found then
      if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      insert into public.pachanga_competition_organizer_states(
        organizer_kind, organizer_group_id, organizer_club_id,
        revision, server_sequence, created_at, updated_at
      ) values (
        organizer_kind,
        case when organizer_kind = 'TEAM' then organizer_id end,
        case when organizer_kind = 'CLUB' then organizer_id end,
        1, sequence_value, confirmed_at, confirmed_at
      ) returning * into organizer_state;
    elsif organizer_state.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    competition_row.id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'competition');
    rule_set_id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'rule-set');
    rule_revision_id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'rule-revision');
    edition_id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'edition');
    stage_id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'stage');
    category_id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'category');
    target_type := upper(coalesce(payload ->> 'drawTarget', 'GROUP_ASSIGNMENT'));
    draw_mode := upper(coalesce(payload ->> 'drawMode', 'PURE_RANDOM'));
    bundle_cap := coalesce(nullif(payload ->> 'participantCap', '')::integer, least(16, bundle_cap));
    rule_document := private.pachanga_tournament_rule_document_v1(payload, bundle_cap);
    rule_checksum := private.pachanga_validate_competition_rule_document_v1(
      'competition_rules.v1', rule_document
    );
    insert into public.pachanga_competitions(
      id, organizer_kind, organizer_group_id, organizer_club_id,
      name, slug, competition_type, visibility, status, product_key,
      description, general_area, revision, tournament_revision,
      server_sequence, created_by, created_at, updated_at
    ) values (
      competition_row.id, organizer_kind,
      case when organizer_kind = 'TEAM' then organizer_id end,
      case when organizer_kind = 'CLUB' then organizer_id end,
      trim(coalesce(payload ->> 'name', 'Torneo privado')),
      lower(trim(coalesce(payload ->> 'slug', 'torneo-' || substr(competition_row.id::text, 1, 8)))),
      'TOURNAMENT', 'private', 'draft', 'TOURNAMENT_PRIVATE_BETA_V1',
      left(coalesce(payload ->> 'description', ''), 2400),
      nullif(left(trim(coalesce(payload ->> 'generalArea', '')), 160), ''),
      1, 1, sequence_value, actor_id, confirmed_at, confirmed_at
    );
    insert into public.pachanga_competition_rule_sets(
      id, competition_id, name, status, revision, server_sequence,
      created_by, created_at, updated_at
    ) values (
      rule_set_id, competition_row.id, 'Reglamento del Torneo', 'active',
      1, nextval('private.pachanga_competition_sequence'), actor_id,
      confirmed_at, confirmed_at
    );
    insert into public.pachanga_competition_rule_revisions(
      id, rule_set_id, version, schema_version, rule_document, checksum,
      effective_from, effective_scope, status, revision, reason,
      server_sequence, created_by, created_at, updated_at
    ) values (
      rule_revision_id, rule_set_id, 1, 'competition_rules.v1',
      rule_document, rule_checksum, confirmed_at, 'future_only', 'frozen', 1,
      'TOURNAMENT_PRIVATE_BETA_V1 initial canonical rules',
      nextval('private.pachanga_competition_sequence'), actor_id,
      confirmed_at, confirmed_at
    );
    insert into public.pachanga_competition_editions(
      id, competition_id, name, season_label, starts_at, ends_at, status,
      rule_revision_id, registration_mode, registration_opens_at,
      registration_closes_at, registration_rule_revision_id,
      revision, server_sequence, created_by, created_at, updated_at
    ) values (
      edition_id, competition_row.id,
      coalesce(nullif(trim(payload ->> 'editionName'), ''), 'Edición inicial'),
      coalesce(nullif(trim(payload ->> 'seasonLabel'), ''), extract(year from current_date)::integer::text),
      coalesce(nullif(payload ->> 'startsAt', '')::date, current_date + 30),
      coalesce(nullif(payload ->> 'endsAt', '')::date, current_date + 120),
      'registration_open', rule_revision_id, 'INVITE_ONLY', confirmed_at,
      coalesce(nullif(payload ->> 'registrationClosesAt', '')::timestamptz, confirmed_at + interval '21 days'),
      rule_revision_id, 1, nextval('private.pachanga_competition_sequence'),
      actor_id, confirmed_at, confirmed_at
    );
    insert into public.pachanga_competition_stages(
      id, edition_id, name, stage_type, stage_order, optional_stage,
      status, rule_revision_id, revision, server_sequence,
      created_by, created_at, updated_at
    ) values (
      stage_id, edition_id,
      case when target_type = 'KNOCKOUT_INITIAL_SEEDING' then 'Cuadro inicial' else 'Fase de grupos' end,
      case when target_type = 'KNOCKOUT_INITIAL_SEEDING' then 'KNOCKOUT' else 'GROUP_STAGE' end,
      0, false, 'draft', rule_revision_id, 1,
      nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at, confirmed_at
    );
    insert into public.pachanga_competition_categories(
      id, edition_id, name, slug, description, sport_format,
      eligibility_policy, visibility, status, rule_revision_id,
      revision, server_sequence, created_by, created_at, updated_at
    ) values (
      category_id, edition_id, 'General', 'general', 'Categoría única del Torneo privado beta',
      upper(coalesce(payload ->> 'modality', 'FUTBOL_7')),
      jsonb_build_object('entryStatusRequired', 'accepted'),
      'private', 'active', rule_revision_id, 1,
      nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at, confirmed_at
    );
    actor_role := organizer ->> 'actorRole';
    if actor_role in ('team_admin', 'club_competition_manager') then
      insert into public.pachanga_competition_staff_assignments(
        competition_id, user_id, staff_role, status, revision,
        server_sequence, assigned_by, assigned_at, updated_at
      ) values (
        competition_row.id, actor_id, 'competition_director', 'active', 1,
        nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at, confirmed_at
      );
    end if;
    if organizer_state.revision = expected_revision then
      update public.pachanga_competition_organizer_states states set
        revision = states.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where states.id = organizer_state.id;
    end if;
    confirmed_revision := 1;
    snapshot := private.pachanga_tournament_command_snapshot_v1(competition_row.id, actor_id);
    event_payload := jsonb_build_object(
      'competitionId', competition_row.id, 'editionId', edition_id,
      'stageId', stage_id, 'categoryId', category_id,
      'ruleRevisionId', rule_revision_id, 'targetType', target_type,
      'drawMode', draw_mode, 'matchGeneration', false
    );
    return private.pachanga_tournament_store_command_v1(
      operation_id, actor_id, normalized_action, aggregate_id,
      competition_row.id, confirmed_revision, sequence_value, request_hash,
      client_metadata, event_payload, snapshot
    );
  end if;

  perform pg_advisory_xact_lock(hashtextextended(aggregate_id::text, 91602));
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = aggregate_id for update;
  if not found then raise exception 'TOURNAMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if competition_row.competition_type <> 'TOURNAMENT'
     or competition_row.product_key <> 'TOURNAMENT_PRIVATE_BETA_V1' then
    raise exception 'TOURNAMENT_PRODUCT_MISMATCH' using errcode = '22023';
  end if;
  if competition_row.tournament_revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if competition_row.status = 'cancelled' and normalized_action <> 'tournament.cancel' then
    raise exception 'TOURNAMENT_NOT_EDITABLE' using errcode = '22023';
  end if;
  sequence_value := nextval('private.pachanga_competition_sequence');
  organizer_id := coalesce(competition_row.organizer_group_id, competition_row.organizer_club_id);
  bundle := private.pachanga_tournament_bundle_snapshot_v1(
    competition_row.organizer_kind, organizer_id
  );
  bundle_cap := coalesce(nullif(bundle ->> 'teamCap', '')::integer, 0);

  if normalized_action = 'tournament.authoring.save' then
    perform private.pachanga_tournament_assert_flags_v1(false, false, false, false, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'authoring') then
      raise exception 'TOURNAMENT_AUTHORING_FORBIDDEN' using errcode = '42501';
    end if;
    if exists (
      select 1 from public.pachanga_competition_draw_plans plans
      where plans.competition_id = aggregate_id and plans.status = 'published'
    ) then raise exception 'PUBLISHED_TOURNAMENT_RULES_IMMUTABLE' using errcode = '22023'; end if;
    bundle_cap := coalesce(nullif(payload ->> 'participantCap', '')::integer, least(16, bundle_cap));
    if bundle_cap not between 4 and coalesce(nullif(bundle ->> 'teamCap', '')::integer, 0) then
      raise exception 'BETA_CAPACITY_LIMIT' using errcode = '22023';
    end if;
    select sets.id, revisions.id into rule_set_id, previous_rule_revision_id
    from public.pachanga_competition_rule_sets sets
    join public.pachanga_competition_rule_revisions revisions on revisions.rule_set_id = sets.id
    where sets.competition_id = aggregate_id
    order by revisions.version desc, revisions.id desc limit 1;
    select coalesce(max(revisions.version), 0) + 1 into next_rule_version
    from public.pachanga_competition_rule_revisions revisions
    where revisions.rule_set_id = rule_set_id;
    rule_revision_id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'rule-revision');
    rule_document := private.pachanga_tournament_rule_document_v1(payload, bundle_cap);
    rule_checksum := private.pachanga_validate_competition_rule_document_v1(
      'competition_rules.v1', rule_document
    );
    insert into public.pachanga_competition_rule_revisions(
      id, rule_set_id, version, schema_version, rule_document, checksum,
      effective_from, effective_scope, status, revision,
      supersedes_revision_id, reason, server_sequence, created_by,
      created_at, updated_at
    ) values (
      rule_revision_id, rule_set_id, next_rule_version, 'competition_rules.v1',
      rule_document, rule_checksum, confirmed_at, 'future_only', 'frozen', 1,
      previous_rule_revision_id,
      left(coalesce(nullif(trim(payload ->> 'reason'), ''), 'Tournament authoring update'), 1200),
      nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at, confirmed_at
    );
    update public.pachanga_competitions competitions set
      name = trim(coalesce(payload ->> 'name', competitions.name)),
      slug = lower(trim(coalesce(payload ->> 'slug', competitions.slug))),
      description = left(coalesce(payload ->> 'description', competitions.description), 2400),
      general_area = coalesce(nullif(trim(payload ->> 'generalArea'), ''), competitions.general_area),
      updated_at = confirmed_at
    where competitions.id = aggregate_id;
    update public.pachanga_competition_editions editions set
      name = coalesce(nullif(trim(payload ->> 'editionName'), ''), editions.name),
      season_label = coalesce(nullif(trim(payload ->> 'seasonLabel'), ''), editions.season_label),
      starts_at = coalesce(nullif(payload ->> 'startsAt', '')::date, editions.starts_at),
      ends_at = coalesce(nullif(payload ->> 'endsAt', '')::date, editions.ends_at),
      registration_closes_at = coalesce(
        nullif(payload ->> 'registrationClosesAt', '')::timestamptz,
        editions.registration_closes_at
      ),
      rule_revision_id = rule_revision_id,
      registration_rule_revision_id = rule_revision_id,
      revision = editions.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where editions.competition_id = aggregate_id
    returning editions.id into edition_id;
    update public.pachanga_competition_stages stages set
      stage_type = case when upper(coalesce(payload ->> 'drawTarget', 'GROUP_ASSIGNMENT')) = 'KNOCKOUT_INITIAL_SEEDING'
        then 'KNOCKOUT' else 'GROUP_STAGE' end,
      rule_revision_id = rule_revision_id,
      revision = stages.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where stages.edition_id = edition_id
    returning stages.id into stage_id;
    update public.pachanga_competition_categories categories set
      sport_format = upper(coalesce(payload ->> 'modality', categories.sport_format)),
      rule_revision_id = rule_revision_id,
      revision = categories.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where categories.edition_id = edition_id;
    update public.pachanga_competition_draw_plans plans set
      rule_revision_id = rule_revision_id,
      target_type = upper(coalesce(payload ->> 'drawTarget', plans.target_type)),
      mode = upper(coalesce(payload ->> 'drawMode', plans.mode)),
      group_count = case when upper(coalesce(payload ->> 'drawTarget', plans.target_type)) = 'KNOCKOUT_INITIAL_SEEDING'
        then null else coalesce(nullif(payload ->> 'groupCount', '')::smallint, plans.group_count) end,
      qualifiers_per_group = coalesce(
        nullif(payload ->> 'qualifiersPerGroup', '')::smallint, plans.qualifiers_per_group
      ),
      status = case when plans.current_revision_id is null then 'draft' else 'participants_frozen' end,
      revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where plans.competition_id = aggregate_id and plans.status <> 'cancelled';
    event_payload := jsonb_build_object(
      'ruleRevisionId', rule_revision_id, 'ruleVersion', next_rule_version,
      'checksum', rule_checksum
    );

  elsif normalized_action = 'participant.invite' then
    perform private.pachanga_tournament_assert_flags_v1(false, false, false, false, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'participants_manage') then
      raise exception 'TOURNAMENT_PARTICIPANTS_FORBIDDEN' using errcode = '42501';
    end if;
    target_id := nullif(payload ->> 'teamId', '')::uuid;
    select editions.id, editions.rule_revision_id into edition_id, rule_revision_id
    from public.pachanga_competition_editions editions
    where editions.competition_id = aggregate_id and editions.status in ('draft', 'registration_open')
    order by editions.server_sequence desc, editions.id desc limit 1;
    select categories.id into category_id
    from public.pachanga_competition_categories categories
    where categories.edition_id = edition_id and categories.status = 'active'
    order by categories.server_sequence desc, categories.id desc limit 1;
    if target_id is null or category_id is null or not exists (
      select 1 from public.pachanga_groups teams where teams.id = target_id
    ) then raise exception 'TOURNAMENT_TEAM_NOT_FOUND' using errcode = 'P0002'; end if;
    insert into public.pachanga_competition_entries(
      id, competition_id, edition_id, category_id, team_id, entry_source,
      status, rule_revision_id, reason_code, reason_text_private,
      revision, server_sequence, created_by, updated_at
    ) values (
      private.pachanga_tournament_operation_entity_id_v1(operation_id, 'entry'),
      aggregate_id, edition_id, category_id, target_id, 'ORGANIZER_INVITATION',
      'invited', rule_revision_id, 'tournament.invited',
      left(coalesce(payload ->> 'reason', ''), 1200), 1,
      nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at
    ) returning * into entry_row;
    insert into public.pachanga_competition_entry_invitations(
      id, entry_id, team_id, status, expires_at, revision,
      server_sequence, invited_by, created_at, updated_at
    ) values (
      private.pachanga_tournament_operation_entity_id_v1(operation_id, 'invitation'),
      entry_row.id, target_id, 'pending', confirmed_at + interval '14 days', 1,
      nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at, confirmed_at
    ) returning * into invitation_row;
    select teams.owner_id into team_owner_id from public.pachanga_groups teams where teams.id = target_id;
    perform private.pachanga_notify_v1(
      team_owner_id, 'tournament_invitation', 'Invitación a Torneo',
      competition_row.name || ' ha invitado a tu equipo.',
      '/competiciones/' || aggregate_id::text || '/gestion/participantes',
      jsonb_build_object('competitionId', aggregate_id, 'entryId', entry_row.id),
      'tournament-invite:' || operation_id::text
    );
    event_payload := jsonb_build_object(
      'entryId', entry_row.id, 'invitationId', invitation_row.id, 'teamId', target_id
    );

  elsif normalized_action in ('participant.accept', 'participant.decline', 'participant.withdraw') then
    target_id := nullif(payload ->> 'entryId', '')::uuid;
    select * into entry_row
    from public.pachanga_competition_entries entries
    where entries.id = target_id and entries.competition_id = aggregate_id for update;
    if not found then raise exception 'TOURNAMENT_ENTRY_NOT_FOUND' using errcode = 'P0002'; end if;
    if not private.pachanga_tournament_team_admin_v1(entry_row.team_id, actor_id) then
      raise exception 'TEAM_ADMIN_REQUIRED' using errcode = '42501';
    end if;
    if normalized_action = 'participant.accept' then
      if entry_row.status <> 'invited' then raise exception 'ENTRY_NOT_INVITED' using errcode = '22023'; end if;
      update public.pachanga_competition_entries entries set
        status = 'accepted', accepted_by = actor_id, accepted_at = confirmed_at,
        reason_code = 'tournament.invitation.accepted',
        revision = entries.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where entries.id = entry_row.id returning * into entry_row;
      update public.pachanga_competition_entry_invitations invitations set
        status = 'accepted', responded_by = actor_id, responded_at = confirmed_at,
        revision = invitations.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where invitations.entry_id = entry_row.id and invitations.status = 'pending';
      select stages.id into stage_id
      from public.pachanga_competition_stages stages
      where stages.edition_id = entry_row.edition_id
      order by stages.stage_order, stages.id limit 1;
      insert into public.pachanga_competition_stage_memberships(
        id, entry_id, stage_id, rule_revision_id, status, reason,
        revision, server_sequence, assigned_by, created_at, updated_at
      ) values (
        private.pachanga_tournament_operation_entity_id_v1(operation_id, 'stage-membership'),
        entry_row.id, stage_id, entry_row.rule_revision_id, 'active',
        'Tournament invitation accepted', 1,
        nextval('private.pachanga_competition_sequence'), actor_id,
        confirmed_at, confirmed_at
      );
      perform private.pachanga_notify_v1(
        competition_row.created_by, 'tournament_participant_accepted',
        'Equipo aceptado', 'Un equipo ha aceptado la invitación a ' || competition_row.name || '.',
        '/competiciones/' || aggregate_id::text || '/gestion/participantes',
        jsonb_build_object('competitionId', aggregate_id, 'entryId', entry_row.id),
        'tournament-accepted:' || operation_id::text
      );
    elsif normalized_action = 'participant.decline' then
      if entry_row.status <> 'invited' then raise exception 'ENTRY_NOT_INVITED' using errcode = '22023'; end if;
      update public.pachanga_competition_entries entries set
        status = 'declined', reason_code = 'tournament.invitation.declined',
        revision = entries.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where entries.id = entry_row.id returning * into entry_row;
      update public.pachanga_competition_entry_invitations invitations set
        status = 'declined', responded_by = actor_id, responded_at = confirmed_at,
        revision = invitations.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where invitations.entry_id = entry_row.id and invitations.status = 'pending';
      perform private.pachanga_notify_v1(
        competition_row.created_by, 'tournament_participant_declined',
        'Invitación rechazada', 'Un equipo ha rechazado la invitación a ' || competition_row.name || '.',
        '/competiciones/' || aggregate_id::text || '/gestion/participantes',
        jsonb_build_object('competitionId', aggregate_id, 'entryId', entry_row.id),
        'tournament-declined:' || operation_id::text
      );
    else
      if entry_row.status not in ('accepted', 'active') then
        raise exception 'ENTRY_NOT_WITHDRAWABLE' using errcode = '22023';
      end if;
      update public.pachanga_competition_entries entries set
        status = 'withdrawn', withdrawn_at = confirmed_at,
        reason_code = 'tournament.participant.withdrawn',
        reason_text_private = left(coalesce(payload ->> 'reason', ''), 1200),
        revision = entries.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where entries.id = entry_row.id returning * into entry_row;
      update public.pachanga_competition_stage_memberships memberships set
        status = 'closed', valid_until = confirmed_at,
        revision = memberships.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where memberships.entry_id = entry_row.id and memberships.status = 'active';
      perform private.pachanga_notify_v1(
        competition_row.created_by, 'tournament_participant_withdrawn',
        'Equipo retirado', 'Un equipo se ha retirado de ' || competition_row.name || '.',
        '/competiciones/' || aggregate_id::text || '/gestion/participantes',
        jsonb_build_object('competitionId', aggregate_id, 'entryId', entry_row.id),
        'tournament-withdrawn:' || operation_id::text
      );
    end if;
    event_payload := jsonb_build_object(
      'entryId', entry_row.id, 'teamId', entry_row.team_id, 'status', entry_row.status
    );

  elsif normalized_action = 'draw_plan.create' then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, false, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    edition_id := nullif(payload ->> 'editionId', '')::uuid;
    stage_id := nullif(payload ->> 'stageId', '')::uuid;
    rule_revision_id := nullif(payload ->> 'ruleRevisionId', '')::uuid;
    target_type := upper(trim(coalesce(payload ->> 'targetType', '')));
    draw_mode := upper(trim(coalesce(payload ->> 'mode', '')));
    group_count := nullif(payload ->> 'groupCount', '')::integer;
    slot_count := nullif(payload ->> 'slotCount', '')::integer;
    qualifiers := nullif(payload ->> 'qualifiersPerGroup', '')::integer;
    if target_type not in ('GROUP_ASSIGNMENT', 'KNOCKOUT_INITIAL_SEEDING', 'GROUPS_THEN_KNOCKOUT')
       or draw_mode not in ('PURE_RANDOM','SEEDED_POTS','CONSTRAINT_OPTIMIZED','MANUAL_ASSISTED','HYBRID')
       or not exists (
         select 1
         from public.pachanga_competition_editions editions
         join public.pachanga_competition_stages stages on stages.edition_id = editions.id
         join public.pachanga_competition_rule_sets sets on sets.competition_id = editions.competition_id
         join public.pachanga_competition_rule_revisions revisions
           on revisions.rule_set_id = sets.id and revisions.id = rule_revision_id
         where editions.id = edition_id and editions.competition_id = aggregate_id
           and stages.id = stage_id and revisions.status in ('published','frozen')
       ) then raise exception 'DRAW_PLAN_SCOPE_INVALID' using errcode = '22023'; end if;
    if target_type = 'KNOCKOUT_INITIAL_SEEDING' then
      if slot_count is not null and (
        slot_count not between 4 and 128 or (slot_count & (slot_count - 1)) <> 0
      ) then raise exception 'KNOCKOUT_SLOT_COUNT_INVALID' using errcode = '22023'; end if;
      group_count := null;
    elsif group_count not between 1 and 16 then
      raise exception 'DRAW_GROUP_COUNT_INVALID' using errcode = '22023';
    end if;
    insert into public.pachanga_competition_draw_plans(
      id, competition_id, edition_id, stage_id, target_type, mode, status,
      rule_revision_id, group_count, slot_count, qualifiers_per_group,
      revision, server_sequence, created_by, created_at, updated_at
    ) values (
      private.pachanga_tournament_operation_entity_id_v1(operation_id, 'draw-plan'),
      aggregate_id, edition_id, stage_id, target_type, draw_mode, 'draft',
      rule_revision_id, group_count, slot_count, qualifiers, 1,
      nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at, confirmed_at
    ) returning * into plan_row;
    plan_id := plan_row.id;
    event_payload := jsonb_build_object(
      'drawPlanId', plan_id, 'targetType', target_type, 'mode', draw_mode
    );

  elsif normalized_action in ('participants.freeze', 'participants.unfreeze') then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, false, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row
    from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.status in ('published','cancelled') then
      raise exception 'DRAW_PLAN_NOT_EDITABLE' using errcode = '22023';
    end if;
    if normalized_action = 'participants.unfreeze' then
      update public.pachanga_competition_draw_plans plans set
        participant_freeze_id = null, current_revision_id = null, status = 'draft',
        revision = plans.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where plans.id = plan_id returning * into plan_row;
      event_payload := jsonb_build_object('drawPlanId', plan_id, 'status', 'draft');
    else
      participant_snapshot := private.pachanga_tournament_participant_snapshot_v1(
        aggregate_id, plan_row.edition_id, plan_row.stage_id
      );
      participant_count := jsonb_array_length(participant_snapshot);
      if participant_count < 4 or participant_count > 64
         or participant_count > bundle_cap
         or (participant_count > 32 and bundle_cap <= 32) then
        raise exception 'BETA_CAPACITY_LIMIT' using errcode = '22023';
      end if;
      if exists (
        select 1
        from jsonb_array_elements(participant_snapshot) item
        where nullif(item ->> 'rosterStatus', '') is not null
          and item ->> 'rosterStatus' not in ('approved', 'locked')
      ) then
        raise exception 'PARTICIPANT_ROSTER_NOT_ELIGIBLE' using errcode = '22023';
      end if;
      select array_agg((item ->> 'entryId')::uuid order by item ->> 'entryId')
      into entry_ids from jsonb_array_elements(participant_snapshot) item;
      if cardinality(entry_ids) <> participant_count
         or cardinality(array(select distinct value from unnest(entry_ids) value)) <> participant_count then
        raise exception 'DUPLICATE_PARTICIPANT' using errcode = 'PT409';
      end if;
      if plan_row.target_type = 'KNOCKOUT_INITIAL_SEEDING' then
        slot_count := coalesce(plan_row.slot_count,
          private.pachanga_tournament_next_power_of_two_v1(participant_count));
        if slot_count < participant_count then
          raise exception 'KNOCKOUT_SLOT_COUNT_INVALID' using errcode = '22023';
        end if;
      else slot_count := plan_row.slot_count; end if;
      freeze_checksum := private.pachanga_tournament_current_input_checksum_v1(
        aggregate_id, plan_row.edition_id, plan_row.stage_id, plan_row.rule_revision_id
      );
      freeze_id := private.pachanga_tournament_operation_entity_id_v1(operation_id, 'participant-freeze');
      insert into public.pachanga_competition_participant_freezes(
        id, competition_id, edition_id, stage_id, rule_revision_id,
        entry_ids, entry_snapshot, roster_readiness, seeding_snapshot,
        club_relationship_snapshot, participant_count, tournament_revision,
        checksum, revision, server_sequence, frozen_by, frozen_at
      ) values (
        freeze_id, aggregate_id, plan_row.edition_id, plan_row.stage_id,
        plan_row.rule_revision_id, entry_ids, participant_snapshot,
        jsonb_build_object(
          'approvedOrLocked', (select count(*) from jsonb_array_elements(participant_snapshot) item
            where item ->> 'rosterStatus' in ('approved','locked')),
          'withoutRoster', (select count(*) from jsonb_array_elements(participant_snapshot) item
            where nullif(item ->> 'rosterStatus', '') is null)
        ),
        jsonb_build_object(
          'policy', 'TEAM_LEVEL_SNAPSHOT',
          'teams', (select coalesce(jsonb_agg(jsonb_build_object(
            'entryId', item ->> 'entryId', 'teamLevel', item -> 'teamLevel',
            'revision', item -> 'teamLevelRevision',
            'calculatedAt', item -> 'teamLevelCalculatedAt'
          ) order by item ->> 'entryId'), '[]'::jsonb)
          from jsonb_array_elements(participant_snapshot) item)
        ),
        jsonb_build_object(
          'teams', (select coalesce(jsonb_agg(jsonb_build_object(
            'entryId', item ->> 'entryId', 'clubId', item -> 'clubId',
            'relationshipRevision', item -> 'clubRelationshipRevision'
          ) order by item ->> 'entryId'), '[]'::jsonb)
          from jsonb_array_elements(participant_snapshot) item)
        ),
        participant_count, expected_revision, freeze_checksum, 1,
        nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at
      ) returning * into freeze_row;
      update public.pachanga_competition_draw_plans plans set
        participant_freeze_id = freeze_id,
        slot_count = slot_count, status = 'participants_frozen',
        revision = plans.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where plans.id = plan_id returning * into plan_row;
      for notification in
        select distinct teams.owner_id
        from jsonb_array_elements(participant_snapshot) item
        join public.pachanga_groups teams on teams.id = (item ->> 'teamId')::uuid
      loop
        perform private.pachanga_notify_v1(
          notification.owner_id, 'tournament_participants_frozen',
          'Participantes confirmados', 'Los participantes de ' || competition_row.name || ' han quedado congelados.',
          '/competiciones/' || aggregate_id::text || '/sorteo',
          jsonb_build_object('competitionId', aggregate_id, 'drawPlanId', plan_id),
          'tournament-freeze:' || operation_id::text || ':' || notification.owner_id::text
        );
      end loop;
      event_payload := jsonb_build_object(
        'drawPlanId', plan_id, 'freezeId', freeze_id,
        'participantCount', participant_count, 'checksum', freeze_checksum
      );
    end if;

  elsif normalized_action in ('draw_pot.create', 'draw_pot.update') then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, false, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.status in ('published','cancelled') then raise exception 'DRAW_PLAN_NOT_EDITABLE' using errcode = '22023'; end if;
    if jsonb_typeof(coalesce(payload -> 'entryIds', '[]'::jsonb)) <> 'array'
       or exists (
         select 1 from jsonb_array_elements_text(coalesce(payload -> 'entryIds', '[]'::jsonb)) ids(value)
         where not exists (
           select 1 from public.pachanga_competition_participant_freezes freezes
           where freezes.id = plan_row.participant_freeze_id and ids.value::uuid = any(freezes.entry_ids)
         )
       ) then raise exception 'DRAW_POT_ENTRY_INVALID' using errcode = '22023'; end if;
    select array_agg(value::uuid order by value::uuid) into entry_ids
    from jsonb_array_elements_text(coalesce(payload -> 'entryIds', '[]'::jsonb)) ids(value);
    entry_ids := coalesce(entry_ids, '{}'::uuid[]);
    if cardinality(entry_ids) <> cardinality(array(select distinct value from unnest(entry_ids) value)) then
      raise exception 'DRAW_POT_DUPLICATE_ENTRY' using errcode = '22023';
    end if;
    if normalized_action = 'draw_pot.create' then
      insert into public.pachanga_competition_draw_pots(
        id, draw_plan_id, pot_number, label, capacity, entry_ids,
        seeding_policy, seeding_snapshot, status, revision,
        server_sequence, created_by, created_at, updated_at
      ) values (
        private.pachanga_tournament_operation_entity_id_v1(operation_id, 'draw-pot'),
        plan_id, (payload ->> 'potNumber')::smallint,
        left(trim(coalesce(payload ->> 'label', 'Bombo')), 120),
        (payload ->> 'capacity')::smallint, entry_ids,
        upper(coalesce(payload ->> 'seedingPolicy', 'MANUAL')),
        jsonb_build_object('entryIds', to_jsonb(entry_ids)),
        'active', 1, nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      ) returning * into pot_row;
    else
      target_id := nullif(payload ->> 'potId', '')::uuid;
      update public.pachanga_competition_draw_pots pots set
        label = left(trim(coalesce(payload ->> 'label', pots.label)), 120),
        capacity = coalesce(nullif(payload ->> 'capacity', '')::smallint, pots.capacity),
        entry_ids = entry_ids,
        seeding_policy = upper(coalesce(payload ->> 'seedingPolicy', pots.seeding_policy)),
        seeding_snapshot = jsonb_build_object('entryIds', to_jsonb(entry_ids)),
        revision = pots.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = confirmed_at
      where pots.id = target_id and pots.draw_plan_id = plan_id and pots.status = 'active'
      returning * into pot_row;
      if not found then raise exception 'DRAW_POT_NOT_FOUND' using errcode = 'P0002'; end if;
    end if;
    if exists (
      select entry_id
      from public.pachanga_competition_draw_pots pots,
        unnest(pots.entry_ids) entry_id
      where pots.draw_plan_id = plan_id and pots.status = 'active'
      group by entry_id having count(*) > 1
    ) then raise exception 'DRAW_ENTRY_IN_MULTIPLE_POTS' using errcode = '22023'; end if;
    update public.pachanga_competition_draw_plans plans set
      status = case when plans.participant_freeze_id is null then 'draft' else 'participants_frozen' end,
      revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'), updated_at = confirmed_at
    where plans.id = plan_id returning * into plan_row;
    event_payload := jsonb_build_object('drawPlanId', plan_id, 'potId', pot_row.id);

  elsif normalized_action in ('draw_constraint.create','draw_constraint.update','draw_constraint.remove') then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, false, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.status in ('published','cancelled') then raise exception 'DRAW_PLAN_NOT_EDITABLE' using errcode = '22023'; end if;
    if normalized_action = 'draw_constraint.create' then
      insert into public.pachanga_competition_draw_constraints(
        id, draw_plan_id, constraint_type, strength, weight, scope,
        parameters, reason, public_attribution, status, revision,
        server_sequence, created_by, created_at, updated_at
      ) values (
        private.pachanga_tournament_operation_entity_id_v1(operation_id, 'draw-constraint'),
        plan_id, upper(trim(payload ->> 'constraintType')),
        upper(trim(payload ->> 'strength')),
        coalesce(nullif(payload ->> 'weight', '')::numeric, 1),
        upper(coalesce(payload ->> 'scope', 'DRAW')),
        coalesce(payload -> 'parameters', '{}'::jsonb),
        left(trim(coalesce(payload ->> 'reason', 'Restricción del sorteo')), 1200),
        coalesce((payload ->> 'publicAttribution')::boolean, true),
        'active', 1, nextval('private.pachanga_competition_sequence'),
        actor_id, confirmed_at, confirmed_at
      ) returning * into constraint_row;
    else
      target_id := nullif(payload ->> 'constraintId', '')::uuid;
      if normalized_action = 'draw_constraint.update' then
        update public.pachanga_competition_draw_constraints constraints set
          strength = upper(coalesce(payload ->> 'strength', constraints.strength)),
          weight = coalesce(nullif(payload ->> 'weight', '')::numeric, constraints.weight),
          scope = upper(coalesce(payload ->> 'scope', constraints.scope)),
          parameters = coalesce(payload -> 'parameters', constraints.parameters),
          reason = left(coalesce(nullif(trim(payload ->> 'reason'), ''), constraints.reason), 1200),
          public_attribution = coalesce(
            (payload ->> 'publicAttribution')::boolean, constraints.public_attribution
          ),
          revision = constraints.revision + 1,
          server_sequence = nextval('private.pachanga_competition_sequence'),
          updated_at = confirmed_at
        where constraints.id = target_id and constraints.draw_plan_id = plan_id
          and constraints.status = 'active'
        returning * into constraint_row;
      else
        update public.pachanga_competition_draw_constraints constraints set
          status = 'removed', revision = constraints.revision + 1,
          server_sequence = nextval('private.pachanga_competition_sequence'),
          updated_at = confirmed_at
        where constraints.id = target_id and constraints.draw_plan_id = plan_id
          and constraints.status = 'active'
        returning * into constraint_row;
      end if;
      if not found then raise exception 'DRAW_CONSTRAINT_NOT_FOUND' using errcode = 'P0002'; end if;
    end if;
    if constraint_row.status = 'active'
       and constraint_row.constraint_type in ('GROUP_SIZE','TEAM_LEVEL_BALANCE')
       and constraint_row.parameters ? 'maxGap'
       and (
         jsonb_typeof(constraint_row.parameters -> 'maxGap') <> 'number'
         or (constraint_row.parameters ->> 'maxGap')::numeric not between 0 and 100
       ) then
      raise exception 'DRAW_CONSTRAINT_THRESHOLD_INVALID' using errcode = '22023';
    end if;
    update public.pachanga_competition_draw_plans plans set
      status = case when plans.participant_freeze_id is null then 'draft' else 'participants_frozen' end,
      revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'), updated_at = confirmed_at
    where plans.id = plan_id returning * into plan_row;
    event_payload := jsonb_build_object(
      'drawPlanId', plan_id, 'constraintId', constraint_row.id,
      'status', constraint_row.status
    );

  elsif normalized_action in ('draw.generate','draw.regenerate') then
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    perform private.pachanga_tournament_assert_flags_v1(
      false, true,
      plan_row.mode in ('PURE_RANDOM','SEEDED_POTS','CONSTRAINT_OPTIMIZED'),
      plan_row.mode = 'MANUAL_ASSISTED', plan_row.mode = 'HYBRID', false
    );
    if plan_row.status in ('published','cancelled') or plan_row.participant_freeze_id is null then
      raise exception 'DRAW_PLAN_NOT_GENERATABLE' using errcode = '22023';
    end if;
    perform private.pachanga_tournament_assert_input_fresh_v1(plan_id);
    seed_mode := upper(coalesce(payload ->> 'seedMode', 'SERVER_SECURE_RANDOM'));
    if seed_mode = 'SERVER_SECURE_RANDOM' then
      selected_seed := encode(extensions.gen_random_bytes(32), 'hex');
    elsif seed_mode = 'CUSTOM_PUBLIC_SEED' then
      selected_seed := trim(coalesce(payload ->> 'publicSeed', ''));
      if length(selected_seed) not between 8 and 128
         or selected_seed !~ '^[A-Za-z0-9._:-]+$' then
        raise exception 'DRAW_SEED_INVALID' using errcode = '22023';
      end if;
    else raise exception 'DRAW_SEED_MODE_INVALID' using errcode = '22023'; end if;
    solution := private.pachanga_tournament_solve_v1(plan_id, selected_seed);
    next_revision_id := private.pachanga_tournament_persist_revision_v1(
      plan_id, actor_id, plan_row.mode, seed_mode, selected_seed,
      solution -> 'placements', solution -> 'byes', 'PENDING',
      plan_row.current_revision_id, false
    );
    select * into plan_row from public.pachanga_competition_draw_plans plans where plans.id = plan_id;
    for notification in
      select distinct teams.owner_id
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      where entries.competition_id = aggregate_id and entries.status in ('accepted','active')
    loop
      perform private.pachanga_notify_v1(
        notification.owner_id,
        case when normalized_action = 'draw.regenerate'
          then 'tournament_draw_regenerated' else 'tournament_draw_ready' end,
        case when normalized_action = 'draw.regenerate'
          then 'Sorteo regenerado' else 'Sorteo preparado' end,
        case when normalized_action = 'draw.regenerate'
          then 'El sorteo de ' || competition_row.name || ' se ha regenerado antes de publicar.'
          else 'El sorteo de ' || competition_row.name || ' está preparado para validación.' end,
        '/competiciones/' || aggregate_id::text || '/sorteo',
        jsonb_build_object('competitionId', aggregate_id, 'drawPlanId', plan_id),
        case when normalized_action = 'draw.regenerate'
          then 'tournament-draw-regenerated:' else 'tournament-draw-ready:' end
          || operation_id::text || ':' || notification.owner_id::text
      );
    end loop;
    event_payload := jsonb_build_object(
      'drawPlanId', plan_id, 'drawRevisionId', next_revision_id,
      'mode', plan_row.mode, 'seedMode', seed_mode,
      'resultChecksum', private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
        'placements', solution -> 'placements', 'byes', solution -> 'byes'
      )),
      'regenerated', normalized_action = 'draw.regenerate'
    );

  elsif normalized_action in (
    'draw.entry.place','draw.entry.move','draw.entry.swap','draw.entry.remove'
  ) then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, true, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.mode not in ('MANUAL_ASSISTED','HYBRID')
       or plan_row.status in ('published','cancelled')
       or plan_row.current_revision_id is null then
      raise exception 'DRAW_MANUAL_EDIT_NOT_AVAILABLE' using errcode = '22023';
    end if;
    perform private.pachanga_tournament_assert_input_fresh_v1(plan_id);
    select * into revision_row
    from public.pachanga_competition_draw_revisions revisions
    where revisions.id = plan_row.current_revision_id;
    placements := private.pachanga_tournament_revision_placements_v1(revision_row.id);
    byes := private.pachanga_tournament_revision_byes_v1(revision_row.id);
    target_id := nullif(payload ->> 'entryId', '')::uuid;
    if target_id is null or not exists (
      select 1 from public.pachanga_competition_participant_freezes freezes
      where freezes.id = plan_row.participant_freeze_id and target_id = any(freezes.entry_ids)
    ) then raise exception 'DRAW_ENTRY_NOT_FROZEN' using errcode = '22023'; end if;
    select pots.pot_number into entry_pot
    from public.pachanga_competition_draw_pots pots
    where pots.draw_plan_id = plan_id and pots.status = 'active'
      and target_id = any(pots.entry_ids)
    order by pots.pot_number, pots.id limit 1;
    if normalized_action = 'draw.entry.place' then
      if exists (
        select 1 from jsonb_array_elements(placements) value
        where value ->> 'entryId' = target_id::text
      ) then raise exception 'DRAW_ENTRY_ALREADY_PLACED' using errcode = 'PT409'; end if;
      placements := placements || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'entryId', target_id,
        'groupNumber', nullif(payload ->> 'groupNumber', '')::integer,
        'slotNumber', nullif(payload ->> 'slotNumber', '')::integer,
        'seedNumber', nullif(payload ->> 'seedNumber', '')::integer,
        'potNumber', entry_pot,
        'placementSource', 'MANUAL'
      )));
    elsif normalized_action = 'draw.entry.move' then
      if not exists (
        select 1 from jsonb_array_elements(placements) value
        where value ->> 'entryId' = target_id::text
      ) then raise exception 'DRAW_ENTRY_NOT_PLACED' using errcode = 'P0002'; end if;
      select jsonb_agg(
        case when value ->> 'entryId' = target_id::text then
          (value - array['groupNumber','slotNumber','seedNumber','manualLockId'])
          || jsonb_strip_nulls(jsonb_build_object(
            'groupNumber', nullif(payload ->> 'groupNumber', '')::integer,
            'slotNumber', nullif(payload ->> 'slotNumber', '')::integer,
            'seedNumber', nullif(payload ->> 'seedNumber', '')::integer,
            'placementSource', 'MANUAL'
          ))
        else value end order by value ->> 'entryId'
      ) into placements from jsonb_array_elements(placements) value;
    elsif normalized_action = 'draw.entry.swap' then
      second_id := nullif(payload ->> 'otherEntryId', '')::uuid;
      select value into left_placement from jsonb_array_elements(placements) value
      where value ->> 'entryId' = target_id::text;
      select value into right_placement from jsonb_array_elements(placements) value
      where value ->> 'entryId' = second_id::text;
      if left_placement is null or right_placement is null then
        raise exception 'DRAW_SWAP_ENTRY_NOT_PLACED' using errcode = 'P0002';
      end if;
      select jsonb_agg(
        case
          when value ->> 'entryId' = target_id::text then
            (value - array['groupNumber','slotNumber','seedNumber','manualLockId'])
            || jsonb_strip_nulls(jsonb_build_object(
              'groupNumber', right_placement -> 'groupNumber',
              'slotNumber', right_placement -> 'slotNumber',
              'seedNumber', right_placement -> 'seedNumber',
              'placementSource', 'MANUAL'
            ))
          when value ->> 'entryId' = second_id::text then
            (value - array['groupNumber','slotNumber','seedNumber','manualLockId'])
            || jsonb_strip_nulls(jsonb_build_object(
              'groupNumber', left_placement -> 'groupNumber',
              'slotNumber', left_placement -> 'slotNumber',
              'seedNumber', left_placement -> 'seedNumber',
              'placementSource', 'MANUAL'
            ))
          else value end order by value ->> 'entryId'
      ) into placements from jsonb_array_elements(placements) value;
    else
      select coalesce(jsonb_agg(value order by value ->> 'entryId'), '[]'::jsonb)
      into placements from jsonb_array_elements(placements) value
      where value ->> 'entryId' <> target_id::text;
    end if;
    if plan_row.target_type in ('GROUP_ASSIGNMENT','GROUPS_THEN_KNOCKOUT') then
      if exists (
        select 1
        from jsonb_array_elements(placements) value
        where nullif(value ->> 'groupNumber', '') is null
           or nullif(value ->> 'slotNumber', '') is null
           or (value ->> 'groupNumber')::integer not between 1 and plan_row.group_count
           or (value ->> 'slotNumber')::integer not between 1 and 128
      ) then raise exception 'DRAW_POSITION_INVALID' using errcode = '22023'; end if;
      if exists (
        select 1
        from jsonb_array_elements(placements) value
        group by value ->> 'groupNumber', value ->> 'slotNumber'
        having count(*) > 1
      ) then raise exception 'DRAW_POSITION_OCCUPIED' using errcode = 'PT409'; end if;
    end if;
    if plan_row.target_type = 'KNOCKOUT_INITIAL_SEEDING' then
      if exists (
        select 1 from jsonb_array_elements(placements) value
        where nullif(value ->> 'seedNumber', '') is null
          or (value ->> 'seedNumber')::integer not between 1 and plan_row.slot_count
      ) then raise exception 'DRAW_POSITION_INVALID' using errcode = '22023'; end if;
      if exists (
        select 1 from jsonb_array_elements(placements) value
        group by value ->> 'seedNumber' having count(*) > 1
      ) then raise exception 'DRAW_POSITION_OCCUPIED' using errcode = 'PT409'; end if;
      byes := '[]'::jsonb;
      for group_number in 1..plan_row.slot_count loop
        if not exists (
          select 1 from jsonb_array_elements(placements) value
          where (value ->> 'seedNumber')::integer = group_number
        ) then byes := byes || jsonb_build_array(jsonb_build_object(
          'targetSlot', group_number,
          'policy', case when plan_row.mode = 'SEEDED_POTS' then 'SEEDED' else 'MANUAL' end,
          'beneficiaryEntryId', null,
          'seedBasis', jsonb_build_object('manualRevision', true, 'slot', group_number)
        )); end if;
      end loop;
    else byes := '[]'::jsonb; end if;
    next_revision_id := private.pachanga_tournament_persist_revision_v1(
      plan_id, actor_id, plan_row.mode, revision_row.seed_mode, revision_row.seed,
      placements, byes, 'PENDING', revision_row.id, false
    );
    event_payload := jsonb_build_object(
      'drawPlanId', plan_id, 'drawRevisionId', next_revision_id,
      'entryId', target_id, 'otherEntryId', second_id,
      'manualAction', normalized_action
    );

  elsif normalized_action in ('draw.lock.create','draw.lock.remove') then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, true, true, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.mode <> 'HYBRID' or plan_row.status in ('published','cancelled') then
      raise exception 'DRAW_LOCK_NOT_AVAILABLE' using errcode = '22023';
    end if;
    if normalized_action = 'draw.lock.create' then
      if length(trim(coalesce(payload ->> 'reason', ''))) < 3 then
        raise exception 'DRAW_LOCK_REASON_REQUIRED' using errcode = '22023';
      end if;
      target_type := upper(trim(coalesce(payload ->> 'lockType', '')));
      target_id := nullif(payload ->> 'entryId', '')::uuid;
      second_id := nullif(payload ->> 'relatedEntryId', '')::uuid;
      if target_id is null or plan_row.participant_freeze_id is null
         or not exists (
           select 1 from public.pachanga_competition_participant_freezes freezes
           where freezes.id = plan_row.participant_freeze_id
             and target_id = any(freezes.entry_ids)
         ) then raise exception 'DRAW_LOCK_ENTRY_NOT_FROZEN' using errcode = '22023'; end if;
      if target_type = 'ENTRY_TO_GROUP'
         and nullif(payload ->> 'groupNumber', '')::integer is null then
        raise exception 'DRAW_LOCK_GROUP_REQUIRED' using errcode = '22023';
      elsif target_type = 'ENTRY_TO_SLOT'
         and nullif(payload ->> 'slotNumber', '')::integer is null then
        raise exception 'DRAW_LOCK_SLOT_REQUIRED' using errcode = '22023';
      elsif target_type = 'GROUP_SEPARATION'
         and (second_id is null or second_id = target_id or not exists (
           select 1 from public.pachanga_competition_participant_freezes freezes
           where freezes.id = plan_row.participant_freeze_id
             and second_id = any(freezes.entry_ids)
         )) then
        raise exception 'DRAW_LOCK_RELATED_ENTRY_INVALID' using errcode = '22023';
      elsif target_type = 'BRACKET_HALF'
         and nullif(payload ->> 'half', '')::integer is null then
        raise exception 'DRAW_LOCK_HALF_REQUIRED' using errcode = '22023';
      elsif target_type = 'POT_POSITION'
         and nullif(payload ->> 'potNumber', '')::integer is null then
        raise exception 'DRAW_LOCK_POT_REQUIRED' using errcode = '22023';
      end if;
      insert into public.pachanga_competition_draw_manual_locks(
        id, draw_plan_id, lock_type, entry_id, related_entry_id,
        target_group_number, target_slot, target_half, pot_number,
        status, reason, revision, server_sequence, created_by, created_at
      ) values (
        private.pachanga_tournament_operation_entity_id_v1(operation_id, 'draw-lock'),
        plan_id, target_type, target_id, second_id,
        nullif(payload ->> 'groupNumber', '')::smallint,
        nullif(payload ->> 'slotNumber', '')::smallint,
        nullif(payload ->> 'half', '')::smallint,
        nullif(payload ->> 'potNumber', '')::smallint,
        'active', left(trim(payload ->> 'reason'), 1200), 1,
        nextval('private.pachanga_competition_sequence'), actor_id, confirmed_at
      ) returning * into lock_row;
    else
      target_id := nullif(payload ->> 'lockId', '')::uuid;
      update public.pachanga_competition_draw_manual_locks locks set
        status = 'released', released_by = actor_id, released_at = confirmed_at,
        revision = locks.revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence')
      where locks.id = target_id and locks.draw_plan_id = plan_id and locks.status = 'active'
      returning * into lock_row;
      if not found then raise exception 'DRAW_LOCK_NOT_FOUND' using errcode = 'P0002'; end if;
    end if;
    update public.pachanga_competition_draw_plans plans set
      status = case when plans.participant_freeze_id is null then 'draft' else 'participants_frozen' end,
      revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where plans.id = plan_id returning * into plan_row;
    event_payload := jsonb_build_object(
      'drawPlanId', plan_id, 'lockId', lock_row.id, 'status', lock_row.status
    );

  elsif normalized_action = 'draw.validate' then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, false, false, false);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_validate') then
      raise exception 'TOURNAMENT_DRAW_VALIDATE_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.status in ('published','cancelled') or plan_row.current_revision_id is null then
      raise exception 'DRAW_REVISION_NOT_VALIDATABLE' using errcode = '22023';
    end if;
    perform private.pachanga_tournament_assert_input_fresh_v1(plan_id);
    perform private.pachanga_tournament_assert_revision_current_v1(plan_id);
    select * into revision_row from public.pachanga_competition_draw_revisions revisions
    where revisions.id = plan_row.current_revision_id;
    placements := private.pachanga_tournament_revision_placements_v1(revision_row.id);
    byes := private.pachanga_tournament_revision_byes_v1(revision_row.id);
    quality := private.pachanga_tournament_evaluate_draw_v1(plan_id, placements);
    next_revision_id := private.pachanga_tournament_persist_revision_v1(
      plan_id, actor_id, plan_row.mode, revision_row.seed_mode, revision_row.seed,
      placements, byes,
      case when (quality ->> 'hardViolations')::integer = 0
             and (quality ->> 'unassignedEntries')::integer = 0
        then 'VALID' else 'INVALID' end,
      revision_row.id, false
    );
    event_payload := jsonb_build_object(
      'drawPlanId', plan_id, 'drawRevisionId', next_revision_id,
      'validationStatus', case when (quality ->> 'hardViolations')::integer = 0
             and (quality ->> 'unassignedEntries')::integer = 0
        then 'VALID' else 'INVALID' end,
      'hardViolations', quality -> 'hardViolations',
      'unassignedEntries', quality -> 'unassignedEntries'
    );

  elsif normalized_action = 'draw.publish' then
    perform private.pachanga_tournament_assert_flags_v1(false, true, false, false, false, true);
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_publish') then
      raise exception 'TOURNAMENT_DRAW_PUBLISH_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    select * into plan_row from public.pachanga_competition_draw_plans plans
    where plans.id = plan_id and plans.competition_id = aggregate_id for update;
    if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
    if plan_row.status = 'published' then raise exception 'DRAW_ALREADY_PUBLISHED' using errcode = 'PT409'; end if;
    if plan_row.status <> 'validated' or plan_row.current_revision_id is null then
      raise exception 'DRAW_VALIDATION_REQUIRED' using errcode = '22023';
    end if;
    perform private.pachanga_tournament_assert_input_fresh_v1(plan_id);
    perform private.pachanga_tournament_assert_revision_current_v1(plan_id);
    select * into revision_row from public.pachanga_competition_draw_revisions revisions
    where revisions.id = plan_row.current_revision_id
      and revisions.validation_status = 'VALID';
    if not found then raise exception 'DRAW_VALIDATION_REQUIRED' using errcode = '22023'; end if;
    placements := private.pachanga_tournament_revision_placements_v1(revision_row.id);
    byes := private.pachanga_tournament_revision_byes_v1(revision_row.id);
    next_revision_id := private.pachanga_tournament_persist_revision_v1(
      plan_id, actor_id, plan_row.mode, revision_row.seed_mode, revision_row.seed,
      placements, byes, 'VALID', revision_row.id, true
    );
    if plan_row.target_type in ('GROUP_ASSIGNMENT','GROUPS_THEN_KNOCKOUT') then
      for group_number in 1..plan_row.group_count loop
        insert into public.pachanga_competition_groups(
          stage_id, name, group_order, status, revision,
          server_sequence, created_by, created_at, updated_at
        ) values (
          plan_row.stage_id, 'Grupo ' || chr(64 + group_number), group_number,
          'draft', 1, nextval('private.pachanga_competition_sequence'),
          actor_id, confirmed_at, confirmed_at
        ) on conflict on constraint pachanga_competition_groups_stage_id_group_order_key do update set
          name = excluded.name,
          revision = public.pachanga_competition_groups.revision + 1,
          server_sequence = excluded.server_sequence,
          updated_at = excluded.updated_at
        returning id into group_id;
        for placement in
          select value from jsonb_array_elements(placements) value
          where (value ->> 'groupNumber')::integer = group_number
        loop
          update public.pachanga_competition_stage_memberships memberships set
            status = 'closed', valid_until = confirmed_at,
            revision = memberships.revision + 1,
            server_sequence = nextval('private.pachanga_competition_sequence'),
            updated_at = confirmed_at
          where memberships.entry_id = (placement ->> 'entryId')::uuid
            and memberships.status = 'active';
          insert into public.pachanga_competition_stage_memberships(
            entry_id, stage_id, competition_group_id, rule_revision_id,
            status, reason, revision, server_sequence,
            assigned_by, created_at, updated_at
          ) values (
            (placement ->> 'entryId')::uuid, plan_row.stage_id, group_id,
            plan_row.rule_revision_id, 'active', 'Published Tournament draw', 1,
            nextval('private.pachanga_competition_sequence'), actor_id,
            confirmed_at, confirmed_at
          );
        end loop;
      end loop;
    end if;
    update public.pachanga_competition_draw_plans plans set
      current_revision_id = next_revision_id, status = 'published',
      published_at = confirmed_at, revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where plans.id = plan_id returning * into plan_row;
    for notification in
      select entries.id as entry_id, teams.owner_id,
        placement.value ->> 'groupNumber' as assigned_group,
        placement.value ->> 'seedNumber' as assigned_seed
      from jsonb_array_elements(placements) placement(value)
      join public.pachanga_competition_entries entries
        on entries.id = (placement.value ->> 'entryId')::uuid
      join public.pachanga_groups teams on teams.id = entries.team_id
    loop
      perform private.pachanga_notify_v1(
        notification.owner_id, 'tournament_draw_published', 'Sorteo publicado',
        'Ya puedes consultar la asignación oficial de ' || competition_row.name || '.',
        '/competiciones/' || aggregate_id::text || '/sorteo',
        jsonb_strip_nulls(jsonb_build_object(
          'competitionId', aggregate_id, 'drawPlanId', plan_id,
          'entryId', notification.entry_id,
          'groupNumber', notification.assigned_group,
          'seedNumber', notification.assigned_seed
        )),
        'tournament-published:' || operation_id::text || ':' || notification.owner_id::text
      );
      perform private.pachanga_notify_v1(
        notification.owner_id, 'tournament_draw_assignment',
        case when notification.assigned_group is not null then 'Grupo asignado' else 'Seed asignado' end,
        'Tu equipo ya tiene posición oficial en ' || competition_row.name || '.',
        '/competiciones/' || aggregate_id::text || '/sorteo',
        jsonb_strip_nulls(jsonb_build_object(
          'competitionId', aggregate_id, 'drawPlanId', plan_id,
          'entryId', notification.entry_id,
          'groupNumber', notification.assigned_group,
          'seedNumber', notification.assigned_seed
        )),
        'tournament-assignment:' || operation_id::text || ':' || notification.owner_id::text
      );
    end loop;
    event_payload := jsonb_build_object(
      'drawPlanId', plan_id, 'drawRevisionId', next_revision_id,
      'resultChecksum', (select revisions.result_checksum
        from public.pachanga_competition_draw_revisions revisions
        where revisions.id = next_revision_id),
      'targetType', plan_row.target_type, 'seedRevealed', true,
      'tournamentMatchesCreated', 0
    );

  elsif normalized_action = 'draw.cancel' then
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'draw_manage') then
      raise exception 'TOURNAMENT_DRAW_FORBIDDEN' using errcode = '42501';
    end if;
    plan_id := nullif(payload ->> 'planId', '')::uuid;
    update public.pachanga_competition_draw_plans plans set
      status = 'cancelled', cancelled_at = confirmed_at,
      revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where plans.id = plan_id and plans.competition_id = aggregate_id
      and plans.status not in ('published','cancelled')
    returning * into plan_row;
    if not found then raise exception 'DRAW_PLAN_NOT_CANCELLABLE' using errcode = '22023'; end if;
    for notification in
      select distinct teams.owner_id
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      where entries.competition_id = aggregate_id and entries.status in ('accepted','active')
    loop
      perform private.pachanga_notify_v1(
        notification.owner_id, 'tournament_draw_cancelled', 'Sorteo cancelado',
        'El borrador de sorteo de ' || competition_row.name || ' ha sido cancelado.',
        '/competiciones/' || aggregate_id::text || '/gestion/participantes',
        jsonb_build_object('competitionId', aggregate_id, 'drawPlanId', plan_id),
        'tournament-draw-cancelled:' || operation_id::text || ':' || notification.owner_id::text
      );
    end loop;
    event_payload := jsonb_build_object('drawPlanId', plan_id, 'status', 'cancelled');

  elsif normalized_action = 'tournament.cancel' then
    if not private.pachanga_tournament_can_v1(aggregate_id, actor_id, 'manage') then
      raise exception 'TOURNAMENT_MANAGE_FORBIDDEN' using errcode = '42501';
    end if;
    if exists (
      select 1 from public.pachanga_competition_draw_plans plans
      where plans.competition_id = aggregate_id and plans.status = 'published'
    ) then raise exception 'PUBLISHED_TOURNAMENT_IMMUTABLE' using errcode = '22023'; end if;
    update public.pachanga_competition_draw_plans plans set
      status = 'cancelled', cancelled_at = confirmed_at,
      revision = plans.revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = confirmed_at
    where plans.competition_id = aggregate_id and plans.status <> 'cancelled';
    update public.pachanga_competitions competitions set status = 'cancelled'
    where competitions.id = aggregate_id;
    for notification in
      select distinct teams.owner_id
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      where entries.competition_id = aggregate_id
        and entries.status in ('invited','accepted','active')
    loop
      perform private.pachanga_notify_v1(
        notification.owner_id, 'tournament_cancelled', 'Torneo cancelado',
        competition_row.name || ' ha sido cancelado por su organización.',
        '/torneos', jsonb_build_object('competitionId', aggregate_id),
        'tournament-cancelled:' || operation_id::text || ':' || notification.owner_id::text
      );
    end loop;
    event_payload := jsonb_build_object('competitionId', aggregate_id, 'status', 'cancelled');
  else
    raise exception 'TOURNAMENT_ACTION_NOT_AVAILABLE' using errcode = '0A000';
  end if;

  update public.pachanga_competitions competitions set
    tournament_revision = competitions.tournament_revision + 1,
    server_sequence = sequence_value,
    updated_at = confirmed_at
  where competitions.id = aggregate_id
  returning competitions.tournament_revision into confirmed_revision;
  snapshot := private.pachanga_tournament_command_snapshot_v1(aggregate_id, actor_id);
  response := private.pachanga_tournament_store_command_v1(
    operation_id, actor_id, normalized_action, aggregate_id, aggregate_id,
    confirmed_revision, sequence_value, request_hash, client_metadata,
    event_payload, snapshot
  );
  return response;
exception
  when unique_violation then
    raise exception 'TOURNAMENT_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_tournament_draw_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_tournament_draw_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

create or replace function private.pachanga_tournament_authorize_organizer_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_actor_id uuid,
  require_creation boolean default true
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
declare actor_role text;
declare organizer_name text;
declare bundle jsonb;
declare platform_role text := private.pachanga_platform_role_for_user_v1(target_actor_id);
begin
  perform private.pachanga_tournament_assert_flags_v1(require_creation, false, false, false, false, false);
  if normalized_kind = 'TEAM' then
    select groups.name,
      case when groups.owner_id = target_actor_id then 'team_owner'
           when exists (
             select 1 from public.pachanga_group_members members
             where members.group_id = groups.id and members.user_id = target_actor_id
               and members.role = 'admin'
           ) then 'team_admin' end
    into organizer_name, actor_role
    from public.pachanga_groups groups where groups.id = target_organizer_id;
    if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    if (actor_role is null or actor_role not in ('team_owner', 'team_admin'))
       and platform_role not in ('platform_owner', 'platform_admin') then
      raise exception 'TEAM_ADMIN_REQUIRED' using errcode = '42501';
    end if;
  elsif normalized_kind = 'CLUB' then
    select clubs.name into organizer_name
    from public.pachanga_clubs clubs
    where clubs.id = target_organizer_id and clubs.operational_status = 'active';
    if not found then raise exception 'CLUB_MUST_BE_ACTIVE' using errcode = '42501'; end if;
    actor_role := private.pachanga_club_active_role_v1(target_organizer_id, target_actor_id);
    if (actor_role is null or actor_role not in ('club_owner', 'club_competition_manager'))
       and platform_role not in ('platform_owner', 'platform_admin') then
      raise exception 'CLUB_COMPETITION_MANAGER_REQUIRED' using errcode = '42501';
    end if;
  else
    raise exception 'INVALID_ORGANIZER_KIND' using errcode = '22023';
  end if;
  bundle := private.pachanga_tournament_bundle_snapshot_v1(normalized_kind, target_organizer_id);
  if bundle ->> 'status' <> 'active' then
    raise exception 'TOURNAMENT_PRIVATE_BETA_GRANT_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'kind', normalized_kind,
    'id', target_organizer_id,
    'name', organizer_name,
    'actorRole', coalesce(actor_role, platform_role),
    'bundle', bundle
  );
end;
$$;

create or replace function private.pachanga_tournament_can_v1(
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
declare competition_row public.pachanga_competitions%rowtype;
declare actor_role text;
declare organizer_id uuid;
declare participant_reader boolean := false;
begin
  if target_actor_id is null then return false; end if;
  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id
    and competitions.competition_type = 'TOURNAMENT'
    and competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1';
  if not found then return false; end if;
  if private.pachanga_platform_role_for_user_v1(target_actor_id)
     in ('platform_owner', 'platform_admin') then return true; end if;
  if target_capability = 'read' then
    select exists (
      select 1
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      where entries.competition_id = target_competition_id
        and entries.status in ('accepted', 'active', 'completed')
        and (
          teams.owner_id = target_actor_id
          or exists (
            select 1 from public.pachanga_group_members members
            where members.group_id = teams.id and members.user_id = target_actor_id
          )
        )
    ) into participant_reader;
  end if;
  actor_role := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
  if target_capability = 'read' and (participant_reader or actor_role is not null) then return true; end if;
  organizer_id := coalesce(competition_row.organizer_group_id, competition_row.organizer_club_id);
  if private.pachanga_tournament_active_bundle_id_v1(
       competition_row.organizer_kind, organizer_id
     ) is null then return false; end if;
  if actor_role = 'competition_owner' then return true; end if;
  return case actor_role
    when 'competition_director' then target_capability in (
      'read', 'manage', 'authoring', 'participants_manage', 'draw_read',
      'draw_manage', 'draw_validate', 'draw_publish'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'participants_manage', 'draw_read',
      'draw_manage', 'draw_validate', 'draw_publish'
    )
    when 'competition_draw_manager' then target_capability in (
      'read', 'draw_read', 'draw_manage', 'draw_validate', 'draw_publish'
    )
    when 'competition_registration_manager' then target_capability in (
      'read', 'participants_manage'
    )
    when 'rules_manager' then target_capability in ('read', 'authoring', 'draw_read')
    when 'viewer' then target_capability in ('read', 'draw_read')
    else false
  end;
end;
$$;

create or replace function private.pachanga_tournament_team_admin_v1(
  target_team_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1 from public.pachanga_groups groups
    where groups.id = target_team_id and groups.owner_id = target_actor_id
  ) or exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = target_team_id and members.user_id = target_actor_id
      and members.role in ('owner', 'admin')
  );
$$;

create or replace function private.pachanga_tournament_json_checksum_v1(target_value jsonb)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(target_value::text, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_tournament_operation_entity_id_v1(
  target_operation_id uuid,
  target_scope text
)
returns uuid
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select substr(encode(extensions.digest(convert_to(
    'pachangas-r6a|' || target_operation_id::text || '|' || lower(trim(target_scope)),
    'UTF8'
  ), 'sha256'), 'hex'), 1, 32)::uuid;
$$;

create or replace function private.pachanga_tournament_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_competition_operation_receipts%rowtype;
begin
  select * into receipt
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id is distinct from target_actor_id
     or receipt.actor_kind <> 'authenticated'
     or receipt.action <> target_action
     or receipt.aggregate_type <> 'tournament'
     or receipt.aggregate_id <> target_aggregate_id::text
     or receipt.request_hash <> target_request_hash then
    raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

create or replace function private.pachanga_tournament_command_snapshot_v1(
  target_competition_id uuid,
  target_actor_id uuid
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
      'name', competitions.name,
      'slug', competitions.slug,
      'status', competitions.status,
      'visibility', competitions.visibility,
      'tournamentRevision', competitions.tournament_revision,
      'serverSequence', competitions.server_sequence,
      'updatedAt', competitions.updated_at
    ),
    'entries', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', entries.id,
        'teamId', entries.team_id,
        'teamName', teams.name,
        'status', entries.status,
        'revision', entries.revision,
        'serverSequence', entries.server_sequence
      ) order by entries.server_sequence, entries.id)
      from public.pachanga_competition_entries entries
      join public.pachanga_groups teams on teams.id = entries.team_id
      where entries.competition_id = competitions.id
        and (
          private.pachanga_tournament_can_v1(
            target_competition_id, target_actor_id, 'participants_manage'
          )
          or entries.status in ('accepted', 'active', 'completed')
          or teams.owner_id = target_actor_id
          or exists (
            select 1
            from public.pachanga_group_members members
            where members.group_id = teams.id
              and members.user_id = target_actor_id
          )
        )
    ), '[]'::jsonb),
    'drawPlans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', plans.id,
        'stageId', plans.stage_id,
        'targetType', plans.target_type,
        'mode', plans.mode,
        'status', plans.status,
        'participantFreezeId', plans.participant_freeze_id,
        'currentRevisionId', plans.current_revision_id,
        'revision', plans.revision,
        'serverSequence', plans.server_sequence
      ) order by plans.server_sequence, plans.id)
      from public.pachanga_competition_draw_plans plans
      where plans.competition_id = competitions.id
        and (
          plans.status = 'published'
          or private.pachanga_tournament_can_v1(
            target_competition_id, target_actor_id, 'draw_read'
          )
        )
    ), '[]'::jsonb)
  )
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
$$;

create or replace function private.pachanga_tournament_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare confirmed_at timestamptz := clock_timestamp();
declare response jsonb;
begin
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'tournament',
      'entityId', target_competition_id,
      'revision', target_confirmed_revision,
      'serverSequence', target_server_sequence
    ))
  );
  insert into public.pachanga_tournament_invalidations(
    server_sequence, competition_id, entity_type, entity_id, revision, created_at
  ) values (
    target_server_sequence, target_competition_id, 'tournament',
    target_competition_id::text, target_confirmed_revision, confirmed_at
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated', 'tournament',
    target_aggregate_id::text, target_competition_id, target_action,
    target_confirmed_revision, target_server_sequence, left(target_action, 120),
    coalesce(target_event_payload, '{}'::jsonb), confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated', target_action,
    'tournament', target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence,
    private.pachanga_competition_client_metadata_v1(coalesce(target_client_metadata, '{}'::jsonb)),
    response, confirmed_at
  );
  return response;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_capabilities_v1()'::regprocedure,
    'private.pachanga_tournament_active_bundle_id_v1(text,uuid)'::regprocedure,
    'private.pachanga_tournament_bundle_snapshot_v1(text,uuid)'::regprocedure,
    'private.pachanga_tournament_flags_v1()'::regprocedure,
    'private.pachanga_tournament_assert_flags_v1(boolean,boolean,boolean,boolean,boolean,boolean)'::regprocedure,
    'private.pachanga_tournament_authorize_organizer_v1(text,uuid,uuid,boolean)'::regprocedure,
    'private.pachanga_tournament_can_v1(uuid,uuid,text)'::regprocedure,
    'private.pachanga_tournament_team_admin_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_tournament_json_checksum_v1(jsonb)'::regprocedure,
    'private.pachanga_tournament_operation_entity_id_v1(uuid,text)'::regprocedure,
    'private.pachanga_tournament_replay_v1(uuid,uuid,text,uuid,text)'::regprocedure,
    'private.pachanga_tournament_command_snapshot_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_tournament_store_command_v1(uuid,uuid,text,uuid,uuid,bigint,bigint,text,jsonb,jsonb,jsonb)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

create or replace function private.pachanga_tournament_rule_document_v1(
  target_configuration jsonb,
  target_team_cap integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare configuration jsonb := coalesce(target_configuration, '{}'::jsonb);
declare target_type text := upper(coalesce(configuration ->> 'drawTarget', 'GROUP_ASSIGNMENT'));
declare draw_mode text := upper(coalesce(configuration ->> 'drawMode', 'PURE_RANDOM'));
declare modality text := upper(coalesce(configuration ->> 'modality', 'FUTBOL_7'));
declare group_count integer := coalesce(nullif(configuration ->> 'groupCount', '')::integer, 4);
declare qualifiers integer := coalesce(nullif(configuration ->> 'qualifiersPerGroup', '')::integer, 2);
declare document jsonb;
begin
  if jsonb_typeof(configuration) <> 'object'
     or target_team_cap not between 4 and 64
     or target_type not in ('GROUP_ASSIGNMENT', 'KNOCKOUT_INITIAL_SEEDING', 'GROUPS_THEN_KNOCKOUT')
     or draw_mode not in ('PURE_RANDOM', 'SEEDED_POTS', 'CONSTRAINT_OPTIMIZED', 'MANUAL_ASSISTED', 'HYBRID')
     or modality not in ('FUTBOL_5', 'FUTBOL_7', 'FUTBOL_11', 'FUTSAL')
     or group_count not between 1 and 16
     or qualifiers not between 1 and 16 then
    raise exception 'TOURNAMENT_CONFIGURATION_INVALID' using errcode = '22023';
  end if;
  document := jsonb_build_object(
    'identity', jsonb_build_object(
      'configurationSchema', 'tournament-configuration.v1',
      'authoringMode', upper(coalesce(configuration ->> 'authoringMode', 'SIMPLE')),
      'sourcePresetId', nullif(upper(configuration ->> 'sourcePresetKey'), ''),
      'sourcePresetVersion', case when nullif(configuration ->> 'sourcePresetKey', '') is not null then 1 end
    ),
    'format', jsonb_build_object(
      'competitionType', 'TOURNAMENT',
      'sportFormat', modality,
      'drawTarget', target_type,
      'drawMode', draw_mode
    ),
    'registration', jsonb_build_object(
      'mode', 'INVITE_ONLY',
      'minimumTeams', 4,
      'maximumTeams', target_team_cap,
      'publicRegistration', false
    ),
    'structure', jsonb_build_object(
      'stageGraph', jsonb_build_object(
        'nodes', jsonb_build_array(jsonb_build_object(
          'id', 'initial-stage', 'root', true, 'optional', false,
          'type', case when target_type = 'KNOCKOUT_INITIAL_SEEDING' then 'KNOCKOUT' else 'GROUP_STAGE' end
        )),
        'edges', jsonb_build_array()
      ),
      'groupCount', case when target_type = 'KNOCKOUT_INITIAL_SEEDING' then null else group_count end,
      'qualifiersPerGroup', case when target_type = 'GROUPS_THEN_KNOCKOUT' then qualifiers else null end,
      'futureBracketTemplate', case when target_type = 'GROUPS_THEN_KNOCKOUT'
        then jsonb_build_object('qualifiersPerGroup', qualifiers, 'status', 'FUTURE_R6B')
        else null end
    ),
    'results', jsonb_build_object(
      'tieBreakCriteria', jsonb_build_array(),
      'scoringPolicy', jsonb_build_object('status', 'FUTURE_R6B')
    ),
    'operations', jsonb_build_object(
      'hardAvailabilityPolicy', jsonb_build_object(
        'enabled', false, 'source', 'NOT_APPLICABLE_R6A'
      ),
      'schedulePreferencePolicy', jsonb_build_object(
        'enabled', false, 'source', 'FUTURE_R6B'
      ),
      'matchGeneration', false,
      'bracketProgression', false
    ),
    'discipline', jsonb_build_object(
      'enabled', coalesce((configuration #>> '{discipline,enabled}')::boolean, false),
      'source', 'COMPETITION_CONFIGURATION_CENTER'
    ),
    'governance', jsonb_build_object(
      'referees', jsonb_build_object(
        'usage', case upper(coalesce(configuration #>> '{referees,usage}', 'OPTIONAL'))
          when 'REQUIRED' then 'REQUIRED' when 'DISABLED' then 'DISABLED' else 'OPTIONAL' end,
        'assignmentsAvailable', false
      )
    ),
    'publication', jsonb_build_object(
      'competitionVisibility', 'PRIVATE',
      'drawAuditVisibility', 'PARTICIPANTS_ONLY',
      'indexing', 'NOINDEX_NOFOLLOW'
    ),
    'futureCapabilities', jsonb_build_object(
      'tournamentMatches', false,
      'bracketProgression', false,
      'results', false,
      'standings', false,
      'payments', false,
      'prizes', false,
      'publicRegistration', false,
      'aiAuthority', false
    ),
    'draw', jsonb_build_object(
      'target', target_type,
      'mode', draw_mode,
      'seedModes', jsonb_build_array('SERVER_SECURE_RANDOM', 'CUSTOM_PUBLIC_SEED'),
      'algorithmVersion', 'tournament-draw-v1.0.0'
    )
  );
  perform private.pachanga_validate_competition_rule_document_v1('competition_rules.v1', document);
  return document;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'TOURNAMENT_CONFIGURATION_INVALID' using errcode = '22023';
end;
$$;

create or replace function private.pachanga_tournament_next_power_of_two_v1(target_value integer)
returns integer
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare result integer := 1;
begin
  if target_value not between 1 and 128 then
    raise exception 'KNOCKOUT_SLOT_COUNT_INVALID' using errcode = '22023';
  end if;
  while result < target_value loop result := result * 2; end loop;
  return result;
end;
$$;

revoke all on function private.pachanga_tournament_rule_document_v1(jsonb, integer)
  from public, anon, authenticated;
revoke all on function private.pachanga_tournament_next_power_of_two_v1(integer)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_assert_revision_current_v1(
  target_draw_plan_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare revision_row public.pachanga_competition_draw_revisions%rowtype;
declare current_pots jsonb;
declare current_constraints jsonb;
declare current_locks jsonb;
begin
  select * into plan_row
  from public.pachanga_competition_draw_plans plans where plans.id = target_draw_plan_id;
  if not found or plan_row.current_revision_id is null then
    raise exception 'DRAW_REVISION_REQUIRED' using errcode = '22023';
  end if;
  select * into revision_row
  from public.pachanga_competition_draw_revisions revisions
  where revisions.id = plan_row.current_revision_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', pots.id, 'potNumber', pots.pot_number, 'label', pots.label,
    'capacity', pots.capacity, 'entryIds', to_jsonb(pots.entry_ids),
    'seedingPolicy', pots.seeding_policy, 'seedingSnapshot', pots.seeding_snapshot,
    'revision', pots.revision, 'serverSequence', pots.server_sequence
  ) order by pots.pot_number, pots.server_sequence, pots.id), '[]'::jsonb)
  into current_pots
  from public.pachanga_competition_draw_pots pots
  where pots.draw_plan_id = plan_row.id and pots.status = 'active';
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', constraints.id, 'type', constraints.constraint_type,
    'strength', constraints.strength, 'weight', constraints.weight,
    'scope', constraints.scope, 'parameters', constraints.parameters,
    'reason', constraints.reason, 'publicAttribution', constraints.public_attribution,
    'revision', constraints.revision, 'serverSequence', constraints.server_sequence
  ) order by constraints.server_sequence, constraints.id), '[]'::jsonb)
  into current_constraints
  from public.pachanga_competition_draw_constraints constraints
  where constraints.draw_plan_id = plan_row.id and constraints.status = 'active';
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', locks.id, 'type', locks.lock_type, 'entryId', locks.entry_id,
    'relatedEntryId', locks.related_entry_id, 'groupNumber', locks.target_group_number,
    'slot', locks.target_slot, 'half', locks.target_half,
    'potNumber', locks.pot_number, 'reason', locks.reason,
    'revision', locks.revision, 'serverSequence', locks.server_sequence
  )) order by locks.server_sequence, locks.id), '[]'::jsonb)
  into current_locks
  from public.pachanga_competition_draw_manual_locks locks
  where locks.draw_plan_id = plan_row.id and locks.status = 'active';
  if revision_row.pot_checksum <> private.pachanga_tournament_json_checksum_v1(current_pots)
     or revision_row.constraint_checksum <> private.pachanga_tournament_json_checksum_v1(current_constraints)
     or revision_row.manual_lock_checksum <> private.pachanga_tournament_json_checksum_v1(current_locks)
     or revision_row.participant_checksum is distinct from (
       select freezes.checksum
       from public.pachanga_competition_participant_freezes freezes
       where freezes.id = plan_row.participant_freeze_id
     ) then
    raise exception 'DRAW_INPUT_STALE' using errcode = 'PT409';
  end if;
end;
$$;

revoke all on function private.pachanga_tournament_assert_revision_current_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_solve_v1(
  target_draw_plan_id uuid,
  target_seed text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare freeze_row public.pachanga_competition_participant_freezes%rowtype;
declare participant record;
declare lock_row record;
declare constraint_row record;
declare candidate_group integer;
declare candidate_slot integer;
declare group_capacity integer;
declare base_capacity integer;
declare remainder_capacity integer;
declare attempt integer;
declare attempt_failed boolean;
declare placed boolean;
declare blocked boolean;
declare current_entry_id uuid;
declare entry_pot integer;
declare entry_club uuid;
declare fixed_group integer;
declare fixed_slot integer;
declare related_entry uuid;
declare related_group integer;
declare target_half integer;
declare placements jsonb;
declare byes jsonb := '[]'::jsonb;
declare quality jsonb;
declare best_placements jsonb;
declare best_byes jsonb := '[]'::jsonb;
declare best_quality jsonb;
declare best_score numeric := -1;
declare bracket_size integer;
declare next_slot integer;
declare bye_slot integer;
begin
  select * into plan_row
  from public.pachanga_competition_draw_plans plans
  where plans.id = target_draw_plan_id;
  if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'DRAW_PLAN_NOT_EDITABLE' using errcode = '22023';
  end if;
  if length(coalesce(target_seed, '')) not between 8 and 256 then
    raise exception 'DRAW_SEED_INVALID' using errcode = '22023';
  end if;
  select * into freeze_row
  from public.pachanga_competition_participant_freezes freezes
  where freezes.id = plan_row.participant_freeze_id;
  if not found then raise exception 'PARTICIPANT_FREEZE_REQUIRED' using errcode = '22023'; end if;

  if plan_row.target_type = 'KNOCKOUT_INITIAL_SEEDING' then
    bracket_size := coalesce(plan_row.slot_count, 0);
    if bracket_size < freeze_row.participant_count
       or bracket_size > 128
       or (bracket_size & (bracket_size - 1)) <> 0 then
      raise exception 'KNOCKOUT_SLOT_COUNT_INVALID' using errcode = '22023';
    end if;
    placements := '[]'::jsonb;
    for lock_row in
      select locks.*
      from public.pachanga_competition_draw_manual_locks locks
      where locks.draw_plan_id = plan_row.id and locks.status = 'active'
        and locks.entry_id is not null
        and locks.lock_type in ('ENTRY_TO_SLOT', 'BRACKET_HALF')
      order by locks.server_sequence, locks.id
    loop
      if not exists (
        select 1 from jsonb_array_elements(freeze_row.entry_snapshot) item
        where item ->> 'entryId' = lock_row.entry_id::text
      ) then
        raise exception 'DRAW_UNSATISFIABLE' using errcode = 'PT422',
          detail = jsonb_build_object(
            'code', 'LOCKED_ENTRY_NOT_FROZEN', 'lockId', lock_row.id,
            'suggestions', jsonb_build_array('Retira el lock o vuelve a congelar participantes.')
          )::text;
      end if;
      if lock_row.lock_type = 'ENTRY_TO_SLOT' then
        candidate_slot := lock_row.target_slot;
      else
        candidate_slot := null;
      end if;
      if candidate_slot is null then continue; end if;
      if candidate_slot not between 1 and bracket_size
         or exists (
           select 1 from jsonb_array_elements(placements) value
           where (value ->> 'seedNumber')::integer = candidate_slot
         ) then
        raise exception 'DRAW_UNSATISFIABLE' using errcode = 'PT422',
          detail = jsonb_build_object(
            'code', 'LOCKED_SLOT_CONFLICT', 'lockId', lock_row.id,
            'targetSlot', candidate_slot,
            'suggestions', jsonb_build_array('Desbloquea una de las posiciones incompatibles.')
          )::text;
      end if;
      select pots.pot_number into entry_pot
      from public.pachanga_competition_draw_pots pots
      where pots.draw_plan_id = plan_row.id and pots.status = 'active'
        and lock_row.entry_id = any(pots.entry_ids)
      order by pots.pot_number, pots.id limit 1;
      placements := placements || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'entryId', lock_row.entry_id,
        'seedNumber', candidate_slot,
        'slotNumber', candidate_slot,
        'potNumber', entry_pot,
        'placementSource', 'LOCKED',
        'manualLockId', lock_row.id
      )));
    end loop;

    for participant in
      select item
      from jsonb_array_elements(freeze_row.entry_snapshot) item
      order by encode(extensions.digest(convert_to(
        target_seed || '|knockout|' || (item ->> 'entryId'), 'UTF8'
      ), 'sha256'), 'hex'), item ->> 'entryId'
    loop
      current_entry_id := (participant.item ->> 'entryId')::uuid;
      if exists (
        select 1 from jsonb_array_elements(placements) value
        where value ->> 'entryId' = current_entry_id::text
      ) then continue; end if;
      select pots.pot_number into entry_pot
      from public.pachanga_competition_draw_pots pots
      where pots.draw_plan_id = plan_row.id and pots.status = 'active'
        and current_entry_id = any(pots.entry_ids)
      order by pots.pot_number, pots.id limit 1;
      select locks.target_half into target_half
      from public.pachanga_competition_draw_manual_locks locks
      where locks.draw_plan_id = plan_row.id and locks.status = 'active'
        and locks.entry_id = current_entry_id and locks.lock_type = 'BRACKET_HALF'
      order by locks.server_sequence desc, locks.id desc limit 1;
      candidate_slot := null;
      for next_slot in
        select slots.slot_number
        from generate_series(1, bracket_size) slots(slot_number)
        where not exists (
          select 1 from jsonb_array_elements(placements) value
          where (value ->> 'seedNumber')::integer = slots.slot_number
        )
          and (target_half is null
            or (target_half = 1 and slots.slot_number <= bracket_size / 2)
            or (target_half = 2 and slots.slot_number > bracket_size / 2))
        order by case when entry_pot = 1 then slots.slot_number else 0 end,
          encode(extensions.digest(convert_to(
            target_seed || '|slot|' || current_entry_id::text || '|' || slots.slot_number,
            'UTF8'
          ), 'sha256'), 'hex'), slots.slot_number
      loop
        candidate_slot := next_slot;
        exit;
      end loop;
      if candidate_slot is null then
        raise exception 'DRAW_UNSATISFIABLE' using errcode = 'PT422',
          detail = jsonb_build_object(
            'code', 'NO_KNOCKOUT_SLOT', 'entryId', current_entry_id,
            'suggestions', jsonb_build_array('Revisa los locks de mitad y posiciones fijas.')
          )::text;
      end if;
      placements := placements || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'entryId', current_entry_id,
        'seedNumber', candidate_slot,
        'slotNumber', candidate_slot,
        'potNumber', entry_pot,
        'placementSource', case when plan_row.mode = 'HYBRID' then 'HYBRID_FILL' else 'ENGINE' end
      )));
    end loop;
    byes := '[]'::jsonb;
    for bye_slot in 1..bracket_size loop
      if not exists (
        select 1 from jsonb_array_elements(placements) value
        where (value ->> 'seedNumber')::integer = bye_slot
      ) then
        byes := byes || jsonb_build_array(jsonb_build_object(
          'targetSlot', bye_slot,
          'policy', case when plan_row.mode = 'SEEDED_POTS' then 'SEEDED' else 'RANDOM' end,
          'beneficiaryEntryId', null,
          'seedBasis', jsonb_build_object('seed', target_seed, 'slot', bye_slot)
        ));
      end if;
    end loop;
    quality := private.pachanga_tournament_evaluate_draw_v1(plan_row.id, placements);
    if (quality ->> 'hardViolations')::integer > 0 then
      raise exception 'DRAW_UNSATISFIABLE' using errcode = 'PT422',
        detail = jsonb_build_object(
          'code', 'KNOCKOUT_CONSTRAINTS_UNSATISFIABLE',
          'explanations', quality -> 'explanations',
          'suggestions', jsonb_build_array('Revisa las separaciones y locks del cuadro inicial.')
        )::text;
    end if;
    return jsonb_build_object('placements', placements, 'byes', byes, 'quality', quality);
  end if;

  if plan_row.group_count is null or plan_row.group_count < 1
     or plan_row.group_count > freeze_row.participant_count then
    raise exception 'DRAW_GROUP_COUNT_INVALID' using errcode = '22023';
  end if;
  base_capacity := freeze_row.participant_count / plan_row.group_count;
  remainder_capacity := freeze_row.participant_count % plan_row.group_count;

  for attempt in 0..127 loop
    placements := '[]'::jsonb;
    attempt_failed := false;

    for lock_row in
      select locks.*
      from public.pachanga_competition_draw_manual_locks locks
      where locks.draw_plan_id = plan_row.id and locks.status = 'active'
        and locks.entry_id is not null
        and locks.lock_type in ('ENTRY_TO_GROUP', 'ENTRY_TO_SLOT')
      order by locks.server_sequence, locks.id
    loop
      if lock_row.target_group_number is null then attempt_failed := true; exit; end if;
      group_capacity := base_capacity + case when lock_row.target_group_number <= remainder_capacity then 1 else 0 end;
      candidate_slot := lock_row.target_slot;
      if candidate_slot is null then
        select slots.slot_number into candidate_slot
        from generate_series(1, group_capacity) slots(slot_number)
        where not exists (
          select 1 from jsonb_array_elements(placements) value
          where (value ->> 'groupNumber')::integer = lock_row.target_group_number
            and (value ->> 'slotNumber')::integer = slots.slot_number
        )
        order by slots.slot_number limit 1;
      end if;
      if candidate_slot is null or candidate_slot > group_capacity
         or exists (
           select 1 from jsonb_array_elements(placements) value
           where value ->> 'entryId' = lock_row.entry_id::text
              or ((value ->> 'groupNumber')::integer = lock_row.target_group_number
                and (value ->> 'slotNumber')::integer = candidate_slot)
         ) then attempt_failed := true; exit; end if;
      select pots.pot_number into entry_pot
      from public.pachanga_competition_draw_pots pots
      where pots.draw_plan_id = plan_row.id and pots.status = 'active'
        and lock_row.entry_id = any(pots.entry_ids)
      order by pots.pot_number, pots.id limit 1;
      placements := placements || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'entryId', lock_row.entry_id,
        'groupNumber', lock_row.target_group_number,
        'slotNumber', candidate_slot,
        'potNumber', entry_pot,
        'placementSource', 'LOCKED',
        'manualLockId', lock_row.id
      )));
    end loop;
    if attempt_failed then continue; end if;

    for participant in
      select item
      from jsonb_array_elements(freeze_row.entry_snapshot) item
      order by encode(extensions.digest(convert_to(
        target_seed || '|' || attempt || '|entry|' || (item ->> 'entryId'), 'UTF8'
      ), 'sha256'), 'hex'), item ->> 'entryId'
    loop
      current_entry_id := (participant.item ->> 'entryId')::uuid;
      entry_club := nullif(participant.item ->> 'clubId', '')::uuid;
      if exists (
        select 1 from jsonb_array_elements(placements) value
        where value ->> 'entryId' = current_entry_id::text
      ) then continue; end if;
      select pots.pot_number into entry_pot
      from public.pachanga_competition_draw_pots pots
      where pots.draw_plan_id = plan_row.id and pots.status = 'active'
        and current_entry_id = any(pots.entry_ids)
      order by pots.pot_number, pots.id limit 1;
      select nullif(constraints.parameters ->> 'groupNumber', '')::integer,
        nullif(constraints.parameters ->> 'slotNumber', '')::integer
      into fixed_group, fixed_slot
      from public.pachanga_competition_draw_constraints constraints
      where constraints.draw_plan_id = plan_row.id and constraints.status = 'active'
        and constraints.constraint_type = 'FIXED_POSITION'
        and constraints.parameters ->> 'entryId' = current_entry_id::text
      order by constraints.server_sequence desc, constraints.id desc limit 1;
      placed := false;
      for candidate_group in
        select groups.group_number
        from generate_series(1, plan_row.group_count) groups(group_number)
        where fixed_group is null or groups.group_number = fixed_group
        order by encode(extensions.digest(convert_to(
          target_seed || '|' || attempt || '|' || current_entry_id::text || '|group|' || groups.group_number,
          'UTF8'
        ), 'sha256'), 'hex'), groups.group_number
      loop
        blocked := false;
        group_capacity := base_capacity + case when candidate_group <= remainder_capacity then 1 else 0 end;
        if (
          select count(*) from jsonb_array_elements(placements) value
          where (value ->> 'groupNumber')::integer = candidate_group
        ) >= group_capacity then continue; end if;
        if entry_pot is not null
           and (
             plan_row.mode = 'SEEDED_POTS'
             or exists (
               select 1 from public.pachanga_competition_draw_constraints constraints
               where constraints.draw_plan_id = plan_row.id and constraints.status = 'active'
                 and constraints.constraint_type = 'POT_DISTRIBUTION'
                 and constraints.strength = 'HARD'
             )
           ) and exists (
             select 1 from jsonb_array_elements(placements) value
             where (value ->> 'groupNumber')::integer = candidate_group
               and nullif(value ->> 'potNumber', '')::integer = entry_pot
           ) then continue; end if;
        if entry_club is not null and exists (
          select 1 from public.pachanga_competition_draw_constraints constraints
          where constraints.draw_plan_id = plan_row.id and constraints.status = 'active'
            and constraints.constraint_type = 'SAME_CLUB_AVOIDANCE'
            and constraints.strength = 'HARD'
        ) and exists (
          select 1
          from jsonb_array_elements(placements) value
          join lateral (
            select frozen
            from jsonb_array_elements(freeze_row.entry_snapshot) frozen
            where frozen ->> 'entryId' = value ->> 'entryId'
          ) existing on true
          where (value ->> 'groupNumber')::integer = candidate_group
            and nullif(existing.frozen ->> 'clubId', '')::uuid = entry_club
        ) then continue; end if;

        for constraint_row in
          select constraints.*
          from public.pachanga_competition_draw_constraints constraints
          where constraints.draw_plan_id = plan_row.id and constraints.status = 'active'
            and constraints.strength = 'HARD'
            and constraints.constraint_type in (
              'MANUAL_SEPARATION', 'MANUAL_TOGETHER',
              'HOST_SEPARATION', 'PREVIOUS_OPPONENT_AVOIDANCE'
            )
            and (
              constraints.parameters ->> 'entryA' = current_entry_id::text
              or constraints.parameters ->> 'entryB' = current_entry_id::text
              or constraints.parameters #>> '{entryIds,0}' = current_entry_id::text
              or constraints.parameters #>> '{entryIds,1}' = current_entry_id::text
            )
          order by constraints.server_sequence, constraints.id
        loop
          related_entry := case
            when coalesce(constraint_row.parameters ->> 'entryA', constraint_row.parameters #>> '{entryIds,0}') = current_entry_id::text
              then coalesce(nullif(constraint_row.parameters ->> 'entryB', '')::uuid,
                            nullif(constraint_row.parameters #>> '{entryIds,1}', '')::uuid)
            else coalesce(nullif(constraint_row.parameters ->> 'entryA', '')::uuid,
                          nullif(constraint_row.parameters #>> '{entryIds,0}', '')::uuid)
          end;
          select nullif(value ->> 'groupNumber', '')::integer into related_group
          from jsonb_array_elements(placements) value
          where value ->> 'entryId' = related_entry::text;
          if related_group is not null and (
            (constraint_row.constraint_type = 'MANUAL_TOGETHER' and related_group <> candidate_group)
            or (constraint_row.constraint_type <> 'MANUAL_TOGETHER' and related_group = candidate_group)
          ) then blocked := true; exit; end if;
        end loop;
        if blocked then continue; end if;
        if exists (
          select 1
          from public.pachanga_competition_draw_manual_locks locks
          join jsonb_array_elements(placements) value
            on value ->> 'entryId' = locks.related_entry_id::text
          where locks.draw_plan_id = plan_row.id and locks.status = 'active'
            and locks.lock_type = 'GROUP_SEPARATION'
            and locks.entry_id = current_entry_id
            and (value ->> 'groupNumber')::integer = candidate_group
        ) then continue; end if;
        candidate_slot := fixed_slot;
        if candidate_slot is null then
          select slots.slot_number into candidate_slot
          from generate_series(1, group_capacity) slots(slot_number)
          where not exists (
            select 1 from jsonb_array_elements(placements) value
            where (value ->> 'groupNumber')::integer = candidate_group
              and (value ->> 'slotNumber')::integer = slots.slot_number
          )
          order by slots.slot_number limit 1;
        end if;
        if candidate_slot is null or candidate_slot > group_capacity
           or exists (
             select 1 from jsonb_array_elements(placements) value
             where (value ->> 'groupNumber')::integer = candidate_group
               and (value ->> 'slotNumber')::integer = candidate_slot
           ) then continue; end if;
        placements := placements || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'entryId', current_entry_id,
          'groupNumber', candidate_group,
          'slotNumber', candidate_slot,
          'potNumber', entry_pot,
          'placementSource', case when plan_row.mode = 'HYBRID' then 'HYBRID_FILL' else 'ENGINE' end
        )));
        placed := true;
        exit;
      end loop;
      if not placed then attempt_failed := true; exit; end if;
    end loop;
    if attempt_failed then continue; end if;
    quality := private.pachanga_tournament_evaluate_draw_v1(plan_row.id, placements);
    if (quality ->> 'hardViolations')::integer = 0
       and (quality ->> 'unassignedEntries')::integer = 0
       and (quality ->> 'qualityScore')::numeric > best_score then
      best_placements := placements;
      best_quality := quality;
      best_score := (quality ->> 'qualityScore')::numeric;
    end if;
  end loop;

  if best_placements is null then
    raise exception 'DRAW_UNSATISFIABLE' using errcode = 'PT422',
      detail = jsonb_build_object(
        'code', 'GROUP_CONSTRAINTS_UNSATISFIABLE',
        'attempts', 128,
        'constraints', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', constraints.id,
            'type', constraints.constraint_type,
            'strength', constraints.strength,
            'parameters', constraints.parameters
          ) order by constraints.server_sequence, constraints.id)
          from public.pachanga_competition_draw_constraints constraints
          where constraints.draw_plan_id = plan_row.id and constraints.status = 'active'
        ), '[]'::jsonb),
        'locks', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', locks.id, 'type', locks.lock_type,
            'entryId', locks.entry_id, 'groupNumber', locks.target_group_number,
            'slot', locks.target_slot
          ) order by locks.server_sequence, locks.id)
          from public.pachanga_competition_draw_manual_locks locks
          where locks.draw_plan_id = plan_row.id and locks.status = 'active'
        ), '[]'::jsonb),
        'suggestions', jsonb_build_array(
          'Revisa locks que ocupan la misma posición.',
          'Convierte una separación HARD en SOFT.',
          'Aumenta el número de grupos o vuelve a congelar participantes.'
        )
      )::text;
  end if;
  return jsonb_build_object(
    'placements', best_placements,
    'byes', best_byes,
    'quality', best_quality
  );
end;
$$;

revoke all on function private.pachanga_tournament_solve_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_tournament_revision_placements_v1(
  target_draw_revision_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'entryId', placements.entry_id,
    'groupNumber', placements.group_number,
    'slotNumber', placements.slot_number,
    'seedNumber', placements.seed_number,
    'potNumber', placements.pot_number,
    'placementSource', placements.placement_source,
    'manualLockId', placements.manual_lock_id
  )) order by placements.entry_id), '[]'::jsonb)
  from public.pachanga_competition_draw_placements placements
  where placements.draw_revision_id = target_draw_revision_id;
$$;

create or replace function private.pachanga_tournament_revision_byes_v1(
  target_draw_revision_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'targetSlot', byes.target_slot,
    'policy', byes.policy,
    'beneficiaryEntryId', byes.beneficiary_entry_id,
    'seedBasis', byes.seed_basis
  )) order by byes.target_slot, byes.id), '[]'::jsonb)
  from public.pachanga_competition_draw_byes byes
  where byes.draw_revision_id = target_draw_revision_id;
$$;

create or replace function private.pachanga_tournament_assert_input_fresh_v1(
  target_draw_plan_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare freeze_row public.pachanga_competition_participant_freezes%rowtype;
declare current_checksum text;
begin
  select * into plan_row
  from public.pachanga_competition_draw_plans plans where plans.id = target_draw_plan_id;
  if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into freeze_row
  from public.pachanga_competition_participant_freezes freezes
  where freezes.id = plan_row.participant_freeze_id;
  if not found then raise exception 'PARTICIPANT_FREEZE_REQUIRED' using errcode = '22023'; end if;
  current_checksum := private.pachanga_tournament_current_input_checksum_v1(
    plan_row.competition_id, plan_row.edition_id, plan_row.stage_id,
    plan_row.rule_revision_id
  );
  if current_checksum <> freeze_row.checksum
     or freeze_row.rule_revision_id <> plan_row.rule_revision_id
     or not exists (
       select 1
       from public.pachanga_competition_editions editions
       join public.pachanga_competition_stages stages on stages.edition_id = editions.id
       where editions.id = plan_row.edition_id
         and stages.id = plan_row.stage_id
         and editions.rule_revision_id = plan_row.rule_revision_id
         and stages.rule_revision_id = plan_row.rule_revision_id
     ) then
    raise exception 'DRAW_INPUT_STALE' using errcode = 'PT409';
  end if;
end;
$$;

create or replace function private.pachanga_tournament_persist_revision_v1(
  target_draw_plan_id uuid,
  target_actor_id uuid,
  target_mode text,
  target_seed_mode text,
  target_seed text,
  target_placements jsonb,
  target_byes jsonb,
  target_validation_status text,
  target_supersedes_revision_id uuid default null,
  target_seed_revealed boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare freeze_row public.pachanga_competition_participant_freezes%rowtype;
declare new_revision_id uuid;
declare next_version integer;
declare normalized_placements jsonb;
declare normalized_byes jsonb;
declare pot_snapshot jsonb;
declare constraint_snapshot jsonb;
declare lock_snapshot jsonb;
declare input_snapshot jsonb;
declare quality jsonb;
declare participant_checksum text;
declare pot_checksum text;
declare constraint_checksum text;
declare lock_checksum text;
declare input_checksum text;
declare result_checksum text;
declare quality_checksum text;
declare placement jsonb;
declare bye jsonb;
begin
  if target_validation_status not in ('PENDING', 'VALID', 'INVALID', 'UNSATISFIABLE', 'STALE') then
    raise exception 'DRAW_VALIDATION_STATUS_INVALID' using errcode = '22023';
  end if;
  select * into plan_row
  from public.pachanga_competition_draw_plans plans
  where plans.id = target_draw_plan_id for update;
  if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  if plan_row.status in ('published', 'cancelled') then
    raise exception 'DRAW_PLAN_NOT_EDITABLE' using errcode = '22023';
  end if;
  select * into freeze_row
  from public.pachanga_competition_participant_freezes freezes
  where freezes.id = plan_row.participant_freeze_id;
  if not found then raise exception 'PARTICIPANT_FREEZE_REQUIRED' using errcode = '22023'; end if;
  select coalesce(jsonb_agg(value order by value ->> 'entryId'), '[]'::jsonb)
  into normalized_placements from jsonb_array_elements(coalesce(target_placements, '[]'::jsonb)) value;
  select coalesce(jsonb_agg(value order by (value ->> 'targetSlot')::integer), '[]'::jsonb)
  into normalized_byes from jsonb_array_elements(coalesce(target_byes, '[]'::jsonb)) value;
  quality := private.pachanga_tournament_evaluate_draw_v1(plan_row.id, normalized_placements);
  if target_validation_status = 'VALID' and (
    (quality ->> 'hardViolations')::integer <> 0
    or (quality ->> 'unassignedEntries')::integer <> 0
  ) then target_validation_status := 'INVALID'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', pots.id,
    'potNumber', pots.pot_number,
    'label', pots.label,
    'capacity', pots.capacity,
    'entryIds', to_jsonb(pots.entry_ids),
    'seedingPolicy', pots.seeding_policy,
    'seedingSnapshot', pots.seeding_snapshot,
    'revision', pots.revision,
    'serverSequence', pots.server_sequence
  ) order by pots.pot_number, pots.server_sequence, pots.id), '[]'::jsonb)
  into pot_snapshot
  from public.pachanga_competition_draw_pots pots
  where pots.draw_plan_id = plan_row.id and pots.status = 'active';
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', constraints.id,
    'type', constraints.constraint_type,
    'strength', constraints.strength,
    'weight', constraints.weight,
    'scope', constraints.scope,
    'parameters', constraints.parameters,
    'reason', constraints.reason,
    'publicAttribution', constraints.public_attribution,
    'revision', constraints.revision,
    'serverSequence', constraints.server_sequence
  ) order by constraints.server_sequence, constraints.id), '[]'::jsonb)
  into constraint_snapshot
  from public.pachanga_competition_draw_constraints constraints
  where constraints.draw_plan_id = plan_row.id and constraints.status = 'active';
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', locks.id,
    'type', locks.lock_type,
    'entryId', locks.entry_id,
    'relatedEntryId', locks.related_entry_id,
    'groupNumber', locks.target_group_number,
    'slot', locks.target_slot,
    'half', locks.target_half,
    'potNumber', locks.pot_number,
    'reason', locks.reason,
    'revision', locks.revision,
    'serverSequence', locks.server_sequence
  )) order by locks.server_sequence, locks.id), '[]'::jsonb)
  into lock_snapshot
  from public.pachanga_competition_draw_manual_locks locks
  where locks.draw_plan_id = plan_row.id and locks.status = 'active';
  participant_checksum := freeze_row.checksum;
  pot_checksum := private.pachanga_tournament_json_checksum_v1(pot_snapshot);
  constraint_checksum := private.pachanga_tournament_json_checksum_v1(constraint_snapshot);
  lock_checksum := private.pachanga_tournament_json_checksum_v1(lock_snapshot);
  input_snapshot := jsonb_build_object(
    'competitionId', plan_row.competition_id,
    'editionId', plan_row.edition_id,
    'stageId', plan_row.stage_id,
    'ruleRevisionId', plan_row.rule_revision_id,
    'participantFreezeId', freeze_row.id,
    'participantFreeze', freeze_row.entry_snapshot,
    'rosterReadiness', freeze_row.roster_readiness,
    'seeding', freeze_row.seeding_snapshot,
    'clubRelationships', freeze_row.club_relationship_snapshot,
    'targetType', plan_row.target_type,
    'groupCount', plan_row.group_count,
    'slotCount', plan_row.slot_count,
    'qualifiersPerGroup', plan_row.qualifiers_per_group
  );
  input_checksum := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'input', input_snapshot,
    'pots', pot_snapshot,
    'constraints', constraint_snapshot,
    'locks', lock_snapshot
  ));
  result_checksum := private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'placements', normalized_placements, 'byes', normalized_byes
  ));
  quality_checksum := private.pachanga_tournament_json_checksum_v1(quality);
  select coalesce(max(revisions.version), 0) + 1 into next_version
  from public.pachanga_competition_draw_revisions revisions
  where revisions.draw_plan_id = plan_row.id;
  new_revision_id := private.pachanga_tournament_operation_entity_id_v1(
    plan_row.id, 'draw-revision-' || next_version::text
  );
  insert into public.pachanga_competition_draw_revisions(
    id, draw_plan_id, version, mode, algorithm_version, seed_mode, seed,
    seed_revealed, input_checksum, participant_checksum, pot_checksum,
    constraint_checksum, manual_lock_checksum, result_checksum,
    validation_status, quality_score, input_snapshot, pot_snapshot,
    constraint_snapshot, manual_lock_snapshot, validation_snapshot,
    supersedes_revision_id, generated_by
  ) values (
    new_revision_id, plan_row.id, next_version, target_mode,
    'tournament-draw-v1.0.0', target_seed_mode, target_seed,
    target_seed_revealed, input_checksum, participant_checksum,
    pot_checksum, constraint_checksum, lock_checksum, result_checksum,
    target_validation_status, (quality ->> 'qualityScore')::numeric,
    input_snapshot, pot_snapshot, constraint_snapshot, lock_snapshot,
    jsonb_build_object(
      'status', target_validation_status,
      'hardViolations', quality -> 'hardViolations',
      'unassignedEntries', quality -> 'unassignedEntries',
      'explanations', quality -> 'explanations'
    ), target_supersedes_revision_id, target_actor_id
  );
  for placement in select value from jsonb_array_elements(normalized_placements)
  loop
    insert into public.pachanga_competition_draw_placements(
      draw_revision_id, entry_id, group_number, slot_number, seed_number,
      pot_number, placement_source, manual_lock_id
    ) values (
      new_revision_id, (placement ->> 'entryId')::uuid,
      nullif(placement ->> 'groupNumber', '')::smallint,
      nullif(placement ->> 'slotNumber', '')::smallint,
      nullif(placement ->> 'seedNumber', '')::smallint,
      nullif(placement ->> 'potNumber', '')::smallint,
      placement ->> 'placementSource',
      nullif(placement ->> 'manualLockId', '')::uuid
    );
  end loop;
  for bye in select value from jsonb_array_elements(normalized_byes)
  loop
    insert into public.pachanga_competition_draw_byes(
      draw_revision_id, target_slot, policy, beneficiary_entry_id, seed_basis
    ) values (
      new_revision_id, (bye ->> 'targetSlot')::smallint, bye ->> 'policy',
      nullif(bye ->> 'beneficiaryEntryId', '')::uuid,
      coalesce(bye -> 'seedBasis', '{}'::jsonb)
    );
  end loop;
  insert into public.pachanga_competition_draw_quality_snapshots(
    draw_revision_id, hard_violations, soft_score, level_balance,
    same_club_collisions, pot_distribution, seed_distribution,
    group_size_balance, manual_override_count, unassigned_entries,
    explanations, checksum
  ) values (
    new_revision_id, (quality ->> 'hardViolations')::integer,
    (quality ->> 'softScore')::numeric, (quality ->> 'levelBalance')::numeric,
    (quality ->> 'sameClubCollisions')::integer,
    (quality ->> 'potDistribution')::numeric,
    (quality ->> 'seedDistribution')::numeric,
    (quality ->> 'groupSizeBalance')::numeric,
    (quality ->> 'manualOverrideCount')::integer,
    (quality ->> 'unassignedEntries')::integer,
    quality -> 'explanations', quality_checksum
  );
  update public.pachanga_competition_draw_plans plans set
    current_revision_id = new_revision_id,
    status = case when target_validation_status = 'VALID' then 'validated' else 'generated' end,
    revision = plans.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where plans.id = plan_row.id;
  return new_revision_id;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_revision_placements_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_revision_byes_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_assert_input_fresh_v1(uuid)'::regprocedure,
    'private.pachanga_tournament_persist_revision_v1(uuid,uuid,text,text,text,jsonb,jsonb,text,uuid,boolean)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

create or replace function private.pachanga_tournament_participant_snapshot_v1(
  target_competition_id uuid,
  target_edition_id uuid,
  target_stage_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'entryId', entries.id,
    'teamId', entries.team_id,
    'teamName', teams.name,
    'teamCrest', teams.payload -> 'teamCrest',
    'entryRevision', entries.revision,
    'entryServerSequence', entries.server_sequence,
    'stageMembershipId', memberships.id,
    'stageMembershipRevision', memberships.revision,
    'clubId', club_relation.club_id,
    'clubRelationshipRevision', club_relation.revision,
    'teamLevel', levels.stable_level,
    'teamLevelRevision', levels.revision,
    'teamLevelCalculatedAt', levels.calculated_at,
    'rosterStatus', rosters.status,
    'rosterRevision', rosters.revision
  ) order by entries.id), '[]'::jsonb)
  from public.pachanga_competition_entries entries
  join public.pachanga_groups teams on teams.id = entries.team_id
  join public.pachanga_competition_stage_memberships memberships
    on memberships.entry_id = entries.id
   and memberships.stage_id = target_stage_id
   and memberships.status = 'active'
  left join public.pachanga_team_level_read_models levels on levels.group_id = entries.team_id
  left join public.pachanga_competition_rosters rosters on rosters.entry_id = entries.id
  left join lateral (
    select relationships.club_id, relationships.revision
    from public.pachanga_club_team_relationships relationships
    where relationships.group_id = entries.team_id and relationships.status = 'active'
    order by relationships.server_sequence desc, relationships.id desc
    limit 1
  ) club_relation on true
  where entries.competition_id = target_competition_id
    and entries.edition_id = target_edition_id
    and entries.status in ('accepted', 'active');
$$;

create or replace function private.pachanga_tournament_current_input_checksum_v1(
  target_competition_id uuid,
  target_edition_id uuid,
  target_stage_id uuid,
  target_rule_revision_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_tournament_json_checksum_v1(jsonb_build_object(
    'competitionId', target_competition_id,
    'editionId', target_edition_id,
    'stageId', target_stage_id,
    'ruleRevisionId', target_rule_revision_id,
    'participants', private.pachanga_tournament_participant_snapshot_v1(
      target_competition_id, target_edition_id, target_stage_id
    )
  ));
$$;

create or replace function private.pachanga_tournament_evaluate_draw_v1(
  target_draw_plan_id uuid,
  target_placements jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare plan_row public.pachanga_competition_draw_plans%rowtype;
declare freeze_row public.pachanga_competition_participant_freezes%rowtype;
declare placement_count integer;
declare distinct_count integer;
declare duplicate_count integer;
declare missing_count integer;
declare invalid_count integer;
declare group_size_gap integer := 0;
declare pot_collisions integer := 0;
declare same_club_collisions integer := 0;
declare seed_collisions integer := 0;
declare level_balance numeric := 0;
declare manual_count integer := 0;
declare lock_violations integer := 0;
declare hard_violations integer := 0;
declare constraint_row record;
declare left_entry uuid;
declare right_entry uuid;
declare left_group integer;
declare right_group integer;
declare fixed_group integer;
declare fixed_slot integer;
declare actual_group integer;
declare actual_slot integer;
declare pair_violation integer;
declare constraint_threshold numeric;
declare soft_penalty numeric := 0;
declare explanations jsonb := '[]'::jsonb;
declare soft_score numeric;
declare quality_score numeric;
begin
  if jsonb_typeof(coalesce(target_placements, '[]'::jsonb)) <> 'array' then
    raise exception 'DRAW_PLACEMENTS_INVALID' using errcode = '22023';
  end if;
  select * into plan_row
  from public.pachanga_competition_draw_plans plans where plans.id = target_draw_plan_id;
  if not found then raise exception 'DRAW_PLAN_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into freeze_row
  from public.pachanga_competition_participant_freezes freezes
  where freezes.id = plan_row.participant_freeze_id;
  if not found then raise exception 'PARTICIPANT_FREEZE_REQUIRED' using errcode = '22023'; end if;

  select count(*), count(distinct placement ->> 'entryId'),
    count(*) filter (
      where not exists (
        select 1 from jsonb_array_elements(freeze_row.entry_snapshot) participant
        where participant ->> 'entryId' = placement ->> 'entryId'
      )
    ),
    count(*) filter (where placement ->> 'placementSource' in ('MANUAL', 'LOCKED'))
  into placement_count, distinct_count, invalid_count, manual_count
  from jsonb_array_elements(target_placements) placement;
  duplicate_count := greatest(placement_count - distinct_count, 0);
  missing_count := greatest(freeze_row.participant_count - distinct_count, 0);

  if duplicate_count > 0 then
    explanations := explanations || jsonb_build_array(jsonb_build_object(
      'code', 'DUPLICATE_ENTRY', 'severity', 'HARD', 'count', duplicate_count,
      'message', 'Un participante aparece más de una vez.'
    ));
  end if;
  if missing_count > 0 or invalid_count > 0 then
    explanations := explanations || jsonb_build_array(jsonb_build_object(
      'code', 'PARTICIPANT_SET_MISMATCH', 'severity', 'HARD',
      'missing', missing_count, 'invalid', invalid_count,
      'message', 'Las posiciones no coinciden con el freeze de participantes.'
    ));
  end if;

  if plan_row.target_type in ('GROUP_ASSIGNMENT', 'GROUPS_THEN_KNOCKOUT') then
    select coalesce(max(group_size) - min(group_size), 0) into group_size_gap
    from (
      select groups.group_number,
        count(placement) filter (where placement is not null) as group_size
      from generate_series(1, plan_row.group_count) groups(group_number)
      left join lateral (
        select candidate
        from jsonb_array_elements(target_placements) candidate
        where nullif(candidate ->> 'groupNumber', '')::integer = groups.group_number
      ) placement on true
      group by groups.group_number
    ) sizes;
    select coalesce(sum(greatest(group_pot_count - 1, 0)), 0) into pot_collisions
    from (
      select placement ->> 'groupNumber' as group_number,
        placement ->> 'potNumber' as pot_number,
        count(*) as group_pot_count
      from jsonb_array_elements(target_placements) placement
      where nullif(placement ->> 'potNumber', '') is not null
      group by placement ->> 'groupNumber', placement ->> 'potNumber'
    ) collisions;
    select coalesce(sum(greatest(club_count - 1, 0)), 0) into same_club_collisions
    from (
      select placement ->> 'groupNumber' as group_number,
        participant.candidate ->> 'clubId' as club_id,
        count(*) as club_count
      from jsonb_array_elements(target_placements) placement
      join lateral (
        select candidate
        from jsonb_array_elements(freeze_row.entry_snapshot) candidate
        where candidate ->> 'entryId' = placement ->> 'entryId'
      ) participant on true
      where nullif(participant.candidate ->> 'clubId', '') is not null
      group by placement ->> 'groupNumber', participant.candidate ->> 'clubId'
    ) collisions;
    select coalesce(max(group_average) - min(group_average), 0) into level_balance
    from (
      select placement ->> 'groupNumber' as group_number,
        avg(coalesce(nullif(participant.candidate ->> 'teamLevel', '')::numeric, 50)) as group_average
      from jsonb_array_elements(target_placements) placement
      join lateral (
        select candidate
        from jsonb_array_elements(freeze_row.entry_snapshot) candidate
        where candidate ->> 'entryId' = placement ->> 'entryId'
      ) participant on true
      group by placement ->> 'groupNumber'
    ) averages;
    if group_size_gap > 1 then
      explanations := explanations || jsonb_build_array(jsonb_build_object(
        'code', 'GROUP_SIZE_UNBALANCED', 'severity', 'HARD', 'gap', group_size_gap,
        'message', 'La diferencia de tamaño entre grupos supera uno.'
      ));
    end if;
  else
    select greatest(count(*) - count(distinct placement ->> 'seedNumber'), 0)
    into seed_collisions
    from jsonb_array_elements(target_placements) placement;
    if seed_collisions > 0 then
      explanations := explanations || jsonb_build_array(jsonb_build_object(
        'code', 'DUPLICATE_SEED', 'severity', 'HARD', 'count', seed_collisions,
        'message', 'Dos participantes ocupan la misma cabeza de serie.'
      ));
    end if;
  end if;

  for constraint_row in
    select constraints.*
    from public.pachanga_competition_draw_constraints constraints
    where constraints.draw_plan_id = plan_row.id and constraints.status = 'active'
    order by constraints.server_sequence, constraints.id
  loop
    pair_violation := 0;
    constraint_threshold := null;
    if constraint_row.constraint_type = 'GROUP_SIZE' then
      constraint_threshold := coalesce(
        nullif(constraint_row.parameters ->> 'maxGap', '')::numeric, 1
      );
      pair_violation := ceil(greatest(group_size_gap - constraint_threshold, 0))::integer;
    elsif constraint_row.constraint_type = 'TEAM_LEVEL_BALANCE' then
      constraint_threshold := coalesce(
        nullif(constraint_row.parameters ->> 'maxGap', '')::numeric, 10
      );
      pair_violation := ceil(greatest(level_balance - constraint_threshold, 0))::integer;
    elsif constraint_row.constraint_type = 'SAME_CLUB_AVOIDANCE' then
      pair_violation := same_club_collisions;
    elsif constraint_row.constraint_type = 'POT_DISTRIBUTION' then
      pair_violation := pot_collisions;
    elsif constraint_row.constraint_type in (
      'MANUAL_SEPARATION', 'HOST_SEPARATION', 'PREVIOUS_OPPONENT_AVOIDANCE'
    ) then
      left_entry := coalesce(
        nullif(constraint_row.parameters ->> 'entryA', '')::uuid,
        nullif(constraint_row.parameters #>> '{entryIds,0}', '')::uuid
      );
      right_entry := coalesce(
        nullif(constraint_row.parameters ->> 'entryB', '')::uuid,
        nullif(constraint_row.parameters #>> '{entryIds,1}', '')::uuid
      );
      select nullif(value ->> 'groupNumber', '')::integer into left_group
      from jsonb_array_elements(target_placements) value where value ->> 'entryId' = left_entry::text;
      select nullif(value ->> 'groupNumber', '')::integer into right_group
      from jsonb_array_elements(target_placements) value where value ->> 'entryId' = right_entry::text;
      pair_violation := case when left_group is not null and left_group = right_group then 1 else 0 end;
    elsif constraint_row.constraint_type = 'MANUAL_TOGETHER' then
      left_entry := coalesce(
        nullif(constraint_row.parameters ->> 'entryA', '')::uuid,
        nullif(constraint_row.parameters #>> '{entryIds,0}', '')::uuid
      );
      right_entry := coalesce(
        nullif(constraint_row.parameters ->> 'entryB', '')::uuid,
        nullif(constraint_row.parameters #>> '{entryIds,1}', '')::uuid
      );
      select nullif(value ->> 'groupNumber', '')::integer into left_group
      from jsonb_array_elements(target_placements) value where value ->> 'entryId' = left_entry::text;
      select nullif(value ->> 'groupNumber', '')::integer into right_group
      from jsonb_array_elements(target_placements) value where value ->> 'entryId' = right_entry::text;
      pair_violation := case when left_group is null or right_group is null or left_group <> right_group then 1 else 0 end;
    elsif constraint_row.constraint_type = 'FIXED_POSITION' then
      left_entry := nullif(constraint_row.parameters ->> 'entryId', '')::uuid;
      fixed_group := nullif(constraint_row.parameters ->> 'groupNumber', '')::integer;
      fixed_slot := coalesce(
        nullif(constraint_row.parameters ->> 'slotNumber', '')::integer,
        nullif(constraint_row.parameters ->> 'seedNumber', '')::integer
      );
      select nullif(value ->> 'groupNumber', '')::integer,
        coalesce(nullif(value ->> 'slotNumber', '')::integer, nullif(value ->> 'seedNumber', '')::integer)
      into actual_group, actual_slot
      from jsonb_array_elements(target_placements) value where value ->> 'entryId' = left_entry::text;
      pair_violation := case when
        (fixed_group is not null and actual_group is distinct from fixed_group)
        or (fixed_slot is not null and actual_slot is distinct from fixed_slot)
        then 1 else 0 end;
    elsif constraint_row.constraint_type in ('SEED_SEPARATION', 'BRACKET_HALF_SEPARATION')
          and plan_row.target_type = 'KNOCKOUT_INITIAL_SEEDING' then
      left_entry := coalesce(
        nullif(constraint_row.parameters ->> 'entryA', '')::uuid,
        nullif(constraint_row.parameters #>> '{entryIds,0}', '')::uuid
      );
      right_entry := coalesce(
        nullif(constraint_row.parameters ->> 'entryB', '')::uuid,
        nullif(constraint_row.parameters #>> '{entryIds,1}', '')::uuid
      );
      select nullif(value ->> 'seedNumber', '')::integer into actual_group
      from jsonb_array_elements(target_placements) value where value ->> 'entryId' = left_entry::text;
      select nullif(value ->> 'seedNumber', '')::integer into actual_slot
      from jsonb_array_elements(target_placements) value where value ->> 'entryId' = right_entry::text;
      pair_violation := case when actual_group is null or actual_slot is null then 1
        when (actual_group <= plan_row.slot_count / 2) = (actual_slot <= plan_row.slot_count / 2) then 1
        else 0 end;
    end if;
    if pair_violation > 0 then
      explanations := explanations || jsonb_build_array(jsonb_build_object(
        'code', constraint_row.constraint_type,
        'constraintId', constraint_row.id,
        'severity', constraint_row.strength,
        'count', pair_violation,
        'message', case when constraint_row.strength = 'HARD'
          then 'La colocación incumple una restricción obligatoria.'
          else 'La colocación reduce la calidad de una preferencia.' end
      ));
      if constraint_row.strength = 'HARD' then
        hard_violations := hard_violations + pair_violation;
      else
        soft_penalty := soft_penalty + pair_violation * constraint_row.weight;
      end if;
    end if;
  end loop;

  select count(*) into lock_violations
  from public.pachanga_competition_draw_manual_locks locks
  where locks.draw_plan_id = plan_row.id and locks.status = 'active'
    and not case locks.lock_type
      when 'GROUP_SEPARATION' then exists (
        select 1
        from jsonb_array_elements(target_placements) left_placement
        join jsonb_array_elements(target_placements) right_placement
          on right_placement ->> 'entryId' = locks.related_entry_id::text
        where left_placement ->> 'entryId' = locks.entry_id::text
          and nullif(left_placement ->> 'groupNumber', '')::integer
            is distinct from nullif(right_placement ->> 'groupNumber', '')::integer
      )
      when 'BRACKET_HALF' then exists (
        select 1 from jsonb_array_elements(target_placements) placement
        where placement ->> 'entryId' = locks.entry_id::text
          and (
            (locks.target_half = 1 and nullif(placement ->> 'seedNumber', '')::integer <= plan_row.slot_count / 2)
            or (locks.target_half = 2 and nullif(placement ->> 'seedNumber', '')::integer > plan_row.slot_count / 2)
          )
      )
      when 'POT_POSITION' then exists (
        select 1 from jsonb_array_elements(target_placements) placement
        where placement ->> 'entryId' = locks.entry_id::text
          and nullif(placement ->> 'potNumber', '')::integer = locks.pot_number
      )
      else exists (
        select 1 from jsonb_array_elements(target_placements) placement
        where placement ->> 'entryId' = locks.entry_id::text
          and (locks.target_group_number is null
            or nullif(placement ->> 'groupNumber', '')::integer = locks.target_group_number)
          and (locks.target_slot is null
            or coalesce(nullif(placement ->> 'slotNumber', '')::integer,
                        nullif(placement ->> 'seedNumber', '')::integer) = locks.target_slot)
      )
    end;
  if lock_violations > 0 then
    explanations := explanations || jsonb_build_array(jsonb_build_object(
      'code', 'MANUAL_LOCK_VIOLATION', 'severity', 'HARD', 'count', lock_violations,
      'message', 'Una posición bloqueada no se ha conservado.'
    ));
  end if;
  hard_violations := hard_violations + duplicate_count + missing_count + invalid_count
    + case when group_size_gap > 1 then group_size_gap - 1 else 0 end
    + seed_collisions + lock_violations;
  if plan_row.mode = 'SEEDED_POTS' then hard_violations := hard_violations + pot_collisions; end if;
  soft_score := greatest(0,
    100 - least(100, level_balance) - same_club_collisions * 5
    - pot_collisions * 8 - least(100, soft_penalty)
  );
  quality_score := greatest(0, least(100,
    soft_score - hard_violations * 20 - missing_count * 20
  ));
  return jsonb_build_object(
    'hardViolations', hard_violations,
    'softScore', round(soft_score, 3),
    'qualityScore', round(quality_score, 3),
    'levelBalance', round(level_balance, 3),
    'sameClubCollisions', same_club_collisions,
    'potDistribution', case when pot_collisions = 0 then 100 else greatest(0, 100 - pot_collisions * 20) end,
    'seedDistribution', case when seed_collisions = 0 then 100 else 0 end,
    'groupSizeBalance', case when group_size_gap <= 1 then 100 else 0 end,
    'manualOverrideCount', manual_count,
    'unassignedEntries', missing_count,
    'explanations', explanations
  );
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_tournament_participant_snapshot_v1(uuid,uuid,uuid)'::regprocedure,
    'private.pachanga_tournament_current_input_checksum_v1(uuid,uuid,uuid,uuid)'::regprocedure,
    'private.pachanga_tournament_evaluate_draw_v1(uuid,jsonb)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;
