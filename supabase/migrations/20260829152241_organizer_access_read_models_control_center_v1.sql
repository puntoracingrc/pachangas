-- Wave 8A: canonical application read models, platform review and command authority.

set lock_timeout = '5s';
set statement_timeout = '5min';

create or replace function private.pachanga_organizer_access_application_snapshot_v1(
  target_application_id uuid,
  include_platform_private boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare application private.pachanga_organizer_access_applications_v1%rowtype;
declare current_revision private.pachanga_organizer_access_application_revisions_v1%rowtype;
declare organizer_id uuid;
declare plan_snapshot jsonb;
declare decision_snapshot jsonb;
declare access_snapshot jsonb;
declare onboarding_snapshot jsonb;
begin
  select * into application
  from private.pachanga_organizer_access_applications_v1 applications
  where applications.id = target_application_id;
  if not found then return null; end if;
  organizer_id := coalesce(application.organizer_group_id, application.organizer_club_id);
  select * into current_revision
  from private.pachanga_organizer_access_application_revisions_v1 revisions
  where revisions.id = application.current_revision_id;
  select jsonb_build_object(
    'code', plans.plan_code,
    'name', revisions.display_name,
    'summary', revisions.summary,
    'organizerKind', plans.organizer_kind,
    'accessModel', plans.access_model,
    'publicAvailable', plans.public_available,
    'requiresStripe', plans.requires_stripe,
    'revision', revisions.version
  ) into plan_snapshot
  from public.pachanga_organizer_plan_catalog plans
  join public.pachanga_organizer_plan_revisions revisions on revisions.plan_id = plans.id
  where plans.plan_code = application.requested_plan_code
    and revisions.status = 'active'
  order by revisions.version desc, revisions.id desc limit 1;
  select jsonb_strip_nulls(jsonb_build_object(
    'id', decisions.id,
    'type', decisions.decision_type,
    'code', decisions.decision_code,
    'message', decisions.applicant_message,
    'privateNote', case when include_platform_private then decisions.private_note end,
    'grantPlanCode', decisions.grant_plan_code,
    'grantSource', decisions.grant_source,
    'resultingAccessGrantId', decisions.resulting_access_grant_id,
    'applicationRevision', decisions.application_revision,
    'serverSequence', decisions.server_sequence,
    'decidedAt', decisions.decided_at
  )) into decision_snapshot
  from private.pachanga_organizer_access_decisions_v1 decisions
  where decisions.application_id = application.id
  order by decisions.server_sequence desc, decisions.id desc limit 1;
  select jsonb_build_object(
    'id', grants.id,
    'status', grants.status,
    'validFrom', grants.valid_from,
    'validUntil', grants.valid_until,
    'revision', grants.revision,
    'serverSequence', grants.server_sequence,
    'planCode', plans.plan_code,
    'planName', revisions.display_name
  ) into access_snapshot
  from private.pachanga_organizer_access_grants_v1 grants
  join public.pachanga_organizer_plan_revisions revisions on revisions.id = grants.plan_revision_id
  join public.pachanga_organizer_plan_catalog plans on plans.id = revisions.plan_id
  where grants.organizer_access_decision_id = (
    select decisions.id from private.pachanga_organizer_access_decisions_v1 decisions
    where decisions.application_id = application.id
    order by decisions.server_sequence desc, decisions.id desc limit 1
  )
  order by grants.server_sequence desc, grants.id desc limit 1;
  select private.pachanga_organizer_onboarding_snapshot_v1(workspaces.id)
  into onboarding_snapshot
  from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
  where workspaces.source_application_id = application.id
  order by workspaces.server_sequence desc, workspaces.id desc limit 1;
  return jsonb_strip_nulls(jsonb_build_object(
    'id', application.id,
    'organizerKind', application.organizer_kind,
    'organizerId', organizer_id,
    'organizerName', case when application.organizer_kind = 'TEAM' then (
      select coalesce(nullif(groups.payload ->> 'name', ''), nullif(groups.payload ->> 'teamName', ''), 'Equipo')
      from public.pachanga_groups groups where groups.id = organizer_id
    ) else (
      select clubs.name from public.pachanga_clubs clubs where clubs.id = organizer_id
    ) end,
    'requestedPlanCode', application.requested_plan_code,
    'requestedAccessMode', application.requested_access_mode,
    'status', application.status,
    'intent', application.intent,
    'expectedCompetitionType', application.expected_competition_type,
    'expectedTeamCount', application.expected_team_count,
    'targetStartDate', application.target_start_date,
    'municipality', application.municipality,
    'area', application.area,
    'fieldRelationship', application.field_relationship,
    'summary', application.summary,
    'revision', application.revision,
    'contentVersion', current_revision.version,
    'contentFingerprint', current_revision.content_fingerprint,
    'consentVersion', current_revision.consent_version,
    'privacyVersion', current_revision.privacy_version,
    'assignedReviewer', case when include_platform_private then application.assigned_reviewer end,
    'currentOwnerId', case when include_platform_private then private.pachanga_organizer_access_owner_id_v1(application.organizer_kind, organizer_id) end,
    'createdBy', case when include_platform_private then application.created_by end,
    'submittedBy', case when include_platform_private then application.submitted_by end,
    'otherApplicationCount', case when include_platform_private then (
      select count(*) from private.pachanga_organizer_access_applications_v1 others
      where others.id <> application.id
        and others.organizer_kind = application.organizer_kind
        and coalesce(others.organizer_group_id, others.organizer_club_id) = organizer_id
    ) end,
    'existingCompetitionCount', case when include_platform_private then (
      select count(*) from public.pachanga_competitions competitions
      where competitions.organizer_kind = application.organizer_kind
        and (
          (application.organizer_kind = 'TEAM' and competitions.organizer_group_id = organizer_id)
          or (application.organizer_kind = 'CLUB' and competitions.organizer_club_id = organizer_id)
        )
    ) end,
    'submittedAt', application.submitted_at,
    'terminalAt', application.terminal_at,
    'serverSequence', application.server_sequence,
    'updatedAt', application.updated_at,
    'reconsiderationOfId', application.reconsideration_of_id,
    'plan', plan_snapshot,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', messages.id,
        'kind', messages.message_kind,
        'authorKind', messages.author_kind,
        'visibility', messages.visibility,
        'body', messages.body,
        'serverSequence', messages.server_sequence,
        'createdAt', messages.created_at
      ) order by messages.server_sequence, messages.id)
      from private.pachanga_organizer_access_messages_v1 messages
      where messages.application_id = application.id
        and (include_platform_private or messages.visibility = 'APPLICANT_SHARED')
    ), '[]'::jsonb),
    'decision', decision_snapshot,
    'accessGrant', access_snapshot,
    'onboarding', onboarding_snapshot
  ));
end;
$$;

create or replace function private.pachanga_organizer_access_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_request_hash text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_organizer_access_operation_receipts_v1%rowtype;
begin
  select * into receipt
  from private.pachanga_organizer_access_operation_receipts_v1 receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id is distinct from target_actor_id
     or receipt.action <> target_action
     or receipt.request_hash <> target_request_hash then
    raise exception 'ORGANIZER_ACCESS_OPERATION_CONFLICT' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

create or replace function private.pachanga_organizer_access_store_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id text,
  target_application_id uuid,
  target_organizer_kind text,
  target_organizer_id uuid,
  target_revision bigint,
  target_request_hash text,
  target_client_metadata jsonb,
  target_reason_code text,
  target_event_payload jsonb,
  target_snapshot jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare sequence_value bigint := nextval('private.pachanga_organizer_access_sequence');
declare confirmed_at timestamptz := clock_timestamp();
declare response jsonb;
begin
  response := jsonb_build_object(
    'ok', true,
    'operationId', target_operation_id,
    'action', target_action,
    'aggregateType', target_aggregate_type,
    'aggregateId', target_aggregate_id,
    'confirmedRevision', target_revision,
    'serverSequence', sequence_value,
    'confirmedAt', confirmed_at,
    'snapshot', coalesce(target_snapshot, '{}'::jsonb)
  );
  insert into private.pachanga_organizer_access_events_v1(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    application_id, organizer_kind, organizer_group_id, organizer_club_id,
    aggregate_revision, reason_code, event_payload, server_sequence, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id, target_application_id,
    target_organizer_kind,
    case when target_organizer_kind = 'TEAM' then target_organizer_id end,
    case when target_organizer_kind = 'CLUB' then target_organizer_id end,
    target_revision, left(target_reason_code, 120), coalesce(target_event_payload, '{}'::jsonb),
    sequence_value, confirmed_at
  );
  insert into private.pachanga_organizer_access_operation_receipts_v1(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata, response, created_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    target_aggregate_type, target_aggregate_id, target_request_hash,
    target_revision, sequence_value,
    private.pachanga_organizer_access_client_metadata_v1(target_client_metadata),
    response, confirmed_at
  );
  return response;
end;
$$;

create or replace function private.pachanga_organizer_access_append_revision_v1(
  target_application_id uuid,
  target_actor_id uuid,
  target_payload jsonb,
  target_with_consent boolean
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare application private.pachanga_organizer_access_applications_v1%rowtype;
declare settings private.pachanga_organizer_access_settings_v1%rowtype;
declare revision_id uuid;
declare next_version integer;
declare plan_code text;
declare access_mode text;
declare selected_intent text;
declare competition_type text;
declare team_count integer;
declare start_date date;
declare municipality_value text;
declare area_value text;
declare field_value text;
declare summary_value text;
declare consent_value text;
declare privacy_value text;
begin
  select * into application from private.pachanga_organizer_access_applications_v1 applications
  where applications.id = target_application_id for update;
  if not found then raise exception 'ORGANIZER_ACCESS_APPLICATION_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into settings from private.pachanga_organizer_access_settings_v1 where singleton;
  next_version := coalesce((
    select max(revisions.version) from private.pachanga_organizer_access_application_revisions_v1 revisions
    where revisions.application_id = application.id
  ), 0) + 1;
  plan_code := upper(coalesce(nullif(trim(target_payload ->> 'planCode'), ''), application.requested_plan_code));
  access_mode := upper(coalesce(nullif(trim(target_payload ->> 'accessMode'), ''), application.requested_access_mode));
  selected_intent := upper(coalesce(nullif(trim(target_payload ->> 'intent'), ''), application.intent));
  competition_type := upper(coalesce(nullif(trim(target_payload ->> 'competitionType'), ''), application.expected_competition_type));
  team_count := case when target_payload ? 'teamCount' then nullif(target_payload ->> 'teamCount', '')::integer else application.expected_team_count end;
  start_date := case when target_payload ? 'targetStartDate' then nullif(target_payload ->> 'targetStartDate', '')::date else application.target_start_date end;
  municipality_value := left(trim(coalesce(target_payload ->> 'municipality', application.municipality)), 120);
  area_value := left(trim(coalesce(target_payload ->> 'area', application.area)), 160);
  field_value := left(trim(coalesce(target_payload ->> 'fieldRelationship', application.field_relationship)), 500);
  summary_value := left(trim(coalesce(target_payload ->> 'summary', application.summary)), 2000);
  if target_with_consent then
    if not coalesce((target_payload ->> 'consent')::boolean, false) then
      raise exception 'ORGANIZER_ACCESS_CONSENT_REQUIRED' using errcode = '22023';
    end if;
    consent_value := settings.consent_version;
    privacy_value := settings.privacy_version;
  end if;
  insert into private.pachanga_organizer_access_application_revisions_v1(
    application_id, version, requested_plan_code, requested_access_mode,
    intent, expected_competition_type, expected_team_count, target_start_date,
    municipality, area, field_relationship, summary,
    consent_version, privacy_version, consented_by, consented_at,
    content_fingerprint, created_by
  ) values (
    application.id, next_version, plan_code, access_mode, selected_intent,
    competition_type, team_count, start_date, municipality_value, area_value,
    field_value, summary_value, consent_value, privacy_value,
    case when target_with_consent then target_actor_id end,
    case when target_with_consent then clock_timestamp() end,
    private.pachanga_organizer_access_content_fingerprint_v1(
      plan_code, access_mode, selected_intent, competition_type, team_count,
      start_date, municipality_value, area_value, field_value, summary_value,
      consent_value, privacy_value
    ), target_actor_id
  ) returning id into revision_id;
  update private.pachanga_organizer_access_applications_v1 applications set
    requested_plan_code = plan_code,
    requested_access_mode = access_mode,
    intent = selected_intent,
    expected_competition_type = competition_type,
    expected_team_count = team_count,
    target_start_date = start_date,
    municipality = municipality_value,
    area = area_value,
    field_relationship = field_value,
    summary = summary_value,
    current_revision_id = revision_id,
    updated_at = clock_timestamp()
  where applications.id = application.id;
  return revision_id;
exception when invalid_text_representation then
  raise exception 'ORGANIZER_ACCESS_APPLICATION_FIELDS_INVALID' using errcode = '22023';
end;
$$;

revoke all on function private.pachanga_organizer_access_application_snapshot_v1(uuid, boolean) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_replay_v1(uuid, uuid, text, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_store_v1(uuid, uuid, text, text, text, text, uuid, text, uuid, bigint, text, jsonb, text, jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_append_revision_v1(uuid, uuid, jsonb, boolean) from public, anon, authenticated;

create or replace function public.command_pachanga_organizer_access_application_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := auth.uid();
declare actor_kind text := 'authenticated';
declare action_name text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare settings private.pachanga_organizer_access_settings_v1%rowtype;
declare application private.pachanga_organizer_access_applications_v1%rowtype;
declare existing_application private.pachanga_organizer_access_applications_v1%rowtype;
declare workspace private.pachanga_organizer_onboarding_workspaces_v1%rowtype;
declare plan public.pachanga_organizer_plan_catalog%rowtype;
declare decision private.pachanga_organizer_access_decisions_v1%rowtype;
declare organizer_kind text;
declare organizer_id uuid;
declare plan_code text;
declare access_mode text;
declare sequence_value bigint;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare reason_code text;
declare message_body text;
declare grant_plan_code text;
declare grant_source text;
declare access_grant_id uuid;
declare onboarding_id uuid;
declare platform_role text;
declare launcher_kind text;
declare launcher_payload jsonb;
declare launcher_response jsonb;
declare launcher_operation_id uuid;
declare launcher_expected_revision bigint;
declare launcher_aggregate_id uuid;
declare application_id uuid;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or action_name = ''
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'ORGANIZER_ACCESS_COMMAND_INVALID' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if payload ?| array[
    'actorId','createdBy','submittedBy','assignedReviewer','decidedBy','grantedBy',
    'serverSequence','confirmedRevision','confirmedAt','contentFingerprint',
    'resultingAccessGrantId','accessGrantId','onboardingId','privateNoteVisible'
  ] then raise exception 'ORGANIZER_ACCESS_SERVER_FIELDS_FORBIDDEN' using errcode = '22023'; end if;
  request_hash := private.pachanga_organizer_access_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 80840));
  replay := private.pachanga_organizer_access_replay_v1(operation_id, actor_id, action_name, request_hash);
  if replay is not null then return replay; end if;
  select * into settings from private.pachanga_organizer_access_settings_v1 where singleton for share;

  if action_name = 'application.create' then
    if payload - array[
      'organizerKind','planCode','intent','competitionType','teamCount','targetStartDate',
      'municipality','area','fieldRelationship','summary','reason'
    ] <> '{}'::jsonb then raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
    if not settings.applications_enabled then raise exception 'ORGANIZER_ACCESS_APPLICATIONS_DISABLED' using errcode = '42501'; end if;
    if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    organizer_kind := upper(trim(coalesce(payload ->> 'organizerKind', '')));
    organizer_id := aggregate_id;
    plan_code := upper(trim(coalesce(payload ->> 'planCode', '')));
    perform private.pachanga_organizer_access_require_actor_locked_v1(organizer_kind, organizer_id, actor_id, 'write');
    perform pg_advisory_xact_lock(hashtextextended(organizer_kind || ':' || organizer_id::text || ':' || plan_code, 80841));
    select * into plan from public.pachanga_organizer_plan_catalog plans
    where plans.plan_code = plan_code and plans.status = 'active'
      and plans.public_available and plans.plan_family = 'ORGANIZER'
      and (plans.organizer_kind = organizer_kind or plans.organizer_kind = 'ANY');
    if not found then raise exception 'ORGANIZER_ACCESS_PLAN_NOT_AVAILABLE' using errcode = '22023'; end if;
    access_mode := private.pachanga_organizer_access_plan_mode_v1(plan.plan_code);
    if access_mode is null then raise exception 'ORGANIZER_ACCESS_PLAN_NOT_APPLICABLE' using errcode = '22023'; end if;
    if private.pachanga_organizer_access_existing_plan_grant_v1(organizer_kind, organizer_id, plan.plan_code) is not null then
      raise exception 'ORGANIZER_ACCESS_ALREADY_GRANTED' using errcode = 'PT409';
    end if;
    perform private.pachanga_organizer_access_rate_limit_v1(actor_id, action_name, organizer_kind, organizer_id);
    select * into existing_application
    from private.pachanga_organizer_access_applications_v1 applications
    where applications.organizer_kind = organizer_kind
      and coalesce(applications.organizer_group_id, applications.organizer_club_id) = organizer_id
      and applications.requested_plan_code = plan_code
      and applications.status in ('draft','submitted','under_review','needs_information')
    order by applications.server_sequence desc, applications.id desc limit 1;
    if found then
      snapshot := private.pachanga_organizer_access_application_snapshot_v1(existing_application.id, false);
      return private.pachanga_organizer_access_store_v1(
        operation_id, actor_id, actor_kind, action_name, 'organizer_access_application',
        existing_application.id::text, existing_application.id, organizer_kind, organizer_id,
        existing_application.revision, request_hash, client_metadata,
        'application.already_active', jsonb_build_object('reused', true), snapshot
      );
    end if;
    insert into private.pachanga_organizer_access_applications_v1(
      organizer_kind, organizer_group_id, organizer_club_id, requested_plan_code,
      requested_access_mode, intent, expected_competition_type, expected_team_count,
      target_start_date, municipality, area, field_relationship, summary, created_by
    ) values (
      organizer_kind,
      case when organizer_kind = 'TEAM' then organizer_id end,
      case when organizer_kind = 'CLUB' then organizer_id end,
      plan_code, access_mode,
      upper(coalesce(nullif(trim(payload ->> 'intent'), ''), 'BOTH')),
      upper(coalesce(nullif(trim(payload ->> 'competitionType'), ''), 'BOTH')),
      nullif(payload ->> 'teamCount', '')::integer,
      nullif(payload ->> 'targetStartDate', '')::date,
      left(trim(coalesce(payload ->> 'municipality', '')), 120),
      left(trim(coalesce(payload ->> 'area', '')), 160),
      left(trim(coalesce(payload ->> 'fieldRelationship', '')), 500),
      left(trim(coalesce(payload ->> 'summary', '')), 2000), actor_id
    ) returning * into application;
    perform private.pachanga_organizer_access_append_revision_v1(application.id, actor_id, payload, false);
    select * into application from private.pachanga_organizer_access_applications_v1 applications where applications.id = application.id;
    snapshot := private.pachanga_organizer_access_application_snapshot_v1(application.id, false);
    return private.pachanga_organizer_access_store_v1(
      operation_id, actor_id, actor_kind, action_name, 'organizer_access_application',
      application.id::text, application.id, organizer_kind, organizer_id,
      application.revision, request_hash, client_metadata,
      left(coalesce(nullif(payload ->> 'reason',''), 'application.created'), 120),
      jsonb_build_object('status', application.status, 'planCode', plan_code), snapshot
    );
  end if;

  if action_name in ('settings.flags','rate_limit.override') then
    actor_kind := 'platform';
    platform_role := private.pachanga_platform_require_v1('organizer_access.override');
    if action_name = 'settings.flags' then
      if payload - array[
        'applicationsEnabled','submissionEnabled','reviewEnabled','partnershipApprovalEnabled',
        'onboardingEnabled','firstCompetitionLauncherEnabled','demoWorldV30Enabled','reason'
      ] <> '{}'::jsonb then raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
      if expected_revision <> settings.revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_settings_v1 access_settings set
        applications_enabled = coalesce((payload ->> 'applicationsEnabled')::boolean, access_settings.applications_enabled),
        submission_enabled = coalesce((payload ->> 'submissionEnabled')::boolean, access_settings.submission_enabled),
        review_enabled = coalesce((payload ->> 'reviewEnabled')::boolean, access_settings.review_enabled),
        partnership_approval_enabled = coalesce((payload ->> 'partnershipApprovalEnabled')::boolean, access_settings.partnership_approval_enabled),
        onboarding_enabled = coalesce((payload ->> 'onboardingEnabled')::boolean, access_settings.onboarding_enabled),
        first_competition_launcher_enabled = coalesce((payload ->> 'firstCompetitionLauncherEnabled')::boolean, access_settings.first_competition_launcher_enabled),
        demo_world_v30_enabled = coalesce((payload ->> 'demoWorldV30Enabled')::boolean, access_settings.demo_world_v30_enabled),
        revision = access_settings.revision + 1, server_sequence = sequence_value,
        updated_by = actor_id, updated_at = clock_timestamp()
      where singleton returning * into settings;
      snapshot := jsonb_build_object(
        'applicationsEnabled', settings.applications_enabled,
        'submissionEnabled', settings.submission_enabled,
        'reviewEnabled', settings.review_enabled,
        'partnershipApprovalEnabled', settings.partnership_approval_enabled,
        'onboardingEnabled', settings.onboarding_enabled,
        'firstCompetitionLauncherEnabled', settings.first_competition_launcher_enabled,
        'demoWorldV30Enabled', settings.demo_world_v30_enabled,
        'revision', settings.revision, 'serverSequence', settings.server_sequence
      );
      return private.pachanga_organizer_access_store_v1(
        operation_id, actor_id, actor_kind, action_name, 'organizer_access_settings',
        aggregate_id::text, null, null, null, settings.revision, request_hash,
        client_metadata, left(coalesce(nullif(payload ->> 'reason',''), 'settings.flags'),120),
        snapshot, snapshot
      );
    end if;
    if payload - array['organizerKind','organizerId','actionPattern','validUntil','reason'] <> '{}'::jsonb then
      raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    organizer_kind := upper(trim(coalesce(payload ->> 'organizerKind','')));
    organizer_id := (payload ->> 'organizerId')::uuid;
    insert into private.pachanga_organizer_access_rate_limit_overrides_v1(
      organizer_kind, organizer_group_id, organizer_club_id, action_pattern,
      valid_until, reason, granted_by
    ) values (
      organizer_kind, case when organizer_kind = 'TEAM' then organizer_id end,
      case when organizer_kind = 'CLUB' then organizer_id end,
      lower(trim(payload ->> 'actionPattern')), (payload ->> 'validUntil')::timestamptz,
      left(trim(payload ->> 'reason'), 1200), actor_id
    );
    return private.pachanga_organizer_access_store_v1(
      operation_id, actor_id, actor_kind, action_name, 'organizer_access_rate_limit',
      aggregate_id::text, null, organizer_kind, organizer_id, 1, request_hash,
      client_metadata, 'rate_limit.override', '{}'::jsonb,
      jsonb_build_object('organizerKind', organizer_kind, 'organizerId', organizer_id)
    );
  end if;

  if action_name in ('onboarding.refresh','competition.launch') then
    select * into workspace from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
    where workspaces.id = aggregate_id for update;
    if not found then raise exception 'ORGANIZER_ONBOARDING_NOT_FOUND' using errcode = 'P0002'; end if;
    organizer_kind := workspace.organizer_kind;
    organizer_id := coalesce(workspace.organizer_group_id, workspace.organizer_club_id);
    application_id := workspace.source_application_id;
    perform private.pachanga_organizer_access_require_actor_locked_v1(organizer_kind, organizer_id, actor_id, 'write');
    if workspace.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if not settings.onboarding_enabled then raise exception 'ORGANIZER_ONBOARDING_DISABLED' using errcode = '42501'; end if;
    if action_name = 'onboarding.refresh' then
      if payload - array['reason'] <> '{}'::jsonb then raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
      snapshot := private.pachanga_refresh_organizer_onboarding_v1(workspace.id, actor_id, 'onboarding.refresh');
      return private.pachanga_organizer_access_store_v1(
        operation_id, actor_id, actor_kind, action_name, 'organizer_onboarding',
        workspace.id::text, application_id, organizer_kind, organizer_id,
        (snapshot ->> 'revision')::bigint, request_hash, client_metadata,
        'onboarding.refreshed', '{}'::jsonb, snapshot
      );
    end if;
    if payload - array['launcherKind','launcherPayload','reason'] <> '{}'::jsonb then
      raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
    end if;
    if not settings.first_competition_launcher_enabled then raise exception 'FIRST_COMPETITION_LAUNCHER_DISABLED' using errcode = '42501'; end if;
    if workspace.first_launcher_aggregate_id is not null then raise exception 'FIRST_COMPETITION_ALREADY_LAUNCHED' using errcode = 'PT409'; end if;
    if not private.pachanga_organizer_billing_creation_allowed_v1(organizer_kind, organizer_id) then
      raise exception 'ORGANIZER_ACCESS_ENTITLEMENT_REQUIRED' using errcode = '42501';
    end if;
    launcher_kind := upper(trim(coalesce(payload ->> 'launcherKind','')));
    launcher_payload := coalesce(payload -> 'launcherPayload', '{}'::jsonb);
    if jsonb_typeof(launcher_payload) <> 'object' then raise exception 'FIRST_COMPETITION_PAYLOAD_INVALID' using errcode = '22023'; end if;
    select states.revision into launcher_expected_revision
    from public.pachanga_competition_organizer_states states
    where states.organizer_kind = organizer_kind and (
      (organizer_kind = 'TEAM' and states.organizer_group_id = organizer_id)
      or (organizer_kind = 'CLUB' and states.organizer_club_id = organizer_id)
    );
    launcher_expected_revision := coalesce(launcher_expected_revision, 0);
    launcher_operation_id := (md5(operation_id::text || ':' || launcher_kind || ':launch'))::uuid;
    if launcher_kind = 'LEAGUE' then
      launcher_response := public.command_pachanga_league_private_beta_v2(
        launcher_operation_id, organizer_id, launcher_expected_revision, 'wizard.create',
        jsonb_build_object(
          'organizerKind', organizer_kind,
          'authoringMode', coalesce(launcher_payload ->> 'authoringMode', 'SIMPLE'),
          'presetKey', coalesce(launcher_payload ->> 'presetKey', 'LEAGUE_F7_STANDARD'),
          'reason', 'FIRST_COMPETITION_LAUNCHER_V1'
        ), client_metadata
      );
      launcher_aggregate_id := (launcher_response #>> '{snapshot,wizard,id}')::uuid;
      update private.pachanga_organizer_onboarding_workspaces_v1 workspaces set
        first_launcher_kind = 'LEAGUE_WIZARD', first_launcher_aggregate_id = launcher_aggregate_id,
        revision = workspaces.revision + 1,
        server_sequence = nextval('private.pachanga_organizer_access_sequence'),
        updated_at = clock_timestamp()
      where workspaces.id = workspace.id returning * into workspace;
    elsif launcher_kind = 'TOURNAMENT' then
      launcher_response := public.command_pachanga_tournament_draw_v1(
        launcher_operation_id, organizer_id, launcher_expected_revision, 'tournament.create',
        launcher_payload || jsonb_build_object('organizerKind', organizer_kind, 'reason', 'FIRST_COMPETITION_LAUNCHER_V1'),
        client_metadata
      );
      launcher_aggregate_id := (launcher_response #>> '{snapshot,competition,id}')::uuid;
      if launcher_aggregate_id is null then
        launcher_aggregate_id := (launcher_response #>> '{snapshot,competitionId}')::uuid;
      end if;
      update private.pachanga_organizer_onboarding_workspaces_v1 workspaces set
        first_launcher_kind = 'TOURNAMENT', first_launcher_aggregate_id = launcher_aggregate_id,
        first_competition_id = launcher_aggregate_id,
        revision = workspaces.revision + 1,
        server_sequence = nextval('private.pachanga_organizer_access_sequence'),
        updated_at = clock_timestamp()
      where workspaces.id = workspace.id returning * into workspace;
    else
      raise exception 'FIRST_COMPETITION_LAUNCHER_KIND_INVALID' using errcode = '22023';
    end if;
    if launcher_aggregate_id is null then raise exception 'FIRST_COMPETITION_LAUNCHER_RESULT_INVALID' using errcode = 'P0001'; end if;
    snapshot := private.pachanga_refresh_organizer_onboarding_v1(workspace.id, actor_id, 'competition.launch');
    return private.pachanga_organizer_access_store_v1(
      operation_id, actor_id, actor_kind, action_name, 'organizer_onboarding',
      workspace.id::text, application_id, organizer_kind, organizer_id,
      (snapshot ->> 'revision')::bigint, request_hash, client_metadata,
      'competition.launch', jsonb_build_object('launcherKind', launcher_kind, 'launcherAggregateId', launcher_aggregate_id), snapshot
    );
  end if;

  select * into application from private.pachanga_organizer_access_applications_v1 applications
  where applications.id = aggregate_id for update;
  if not found then raise exception 'ORGANIZER_ACCESS_APPLICATION_NOT_FOUND' using errcode = 'P0002'; end if;
  organizer_kind := application.organizer_kind;
  organizer_id := coalesce(application.organizer_group_id, application.organizer_club_id);
  if application.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;

  if action_name in ('application.update','application.submit','application.withdraw','application.respond_information','application.reconsider') then
    perform private.pachanga_organizer_access_require_actor_locked_v1(organizer_kind, organizer_id, actor_id, 'write');
    perform private.pachanga_organizer_access_rate_limit_v1(actor_id, action_name, organizer_kind, organizer_id);
    if action_name = 'application.update' then
      if payload - array['intent','competitionType','teamCount','targetStartDate','municipality','area','fieldRelationship','summary','reason'] <> '{}'::jsonb then
        raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
      end if;
      if application.status <> 'draft' then raise exception 'ORGANIZER_ACCESS_APPLICATION_NOT_EDITABLE' using errcode = '22023'; end if;
      perform private.pachanga_organizer_access_append_revision_v1(application.id, actor_id, payload, false);
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        revision = applications.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      reason_code := 'application.updated';
    elsif action_name = 'application.submit' then
      if payload - array['consent','intent','competitionType','teamCount','targetStartDate','municipality','area','fieldRelationship','summary','reason'] <> '{}'::jsonb then
        raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
      end if;
      if not settings.submission_enabled then raise exception 'ORGANIZER_ACCESS_SUBMISSION_DISABLED' using errcode = '42501'; end if;
      if application.status <> 'draft' then raise exception 'ORGANIZER_ACCESS_APPLICATION_NOT_SUBMITTABLE' using errcode = '22023'; end if;
      if organizer_kind = 'CLUB' and not exists (
        select 1 from public.pachanga_clubs clubs where clubs.id = organizer_id and clubs.operational_status = 'active'
      ) then raise exception 'ORGANIZER_ACCESS_CLUB_MUST_BE_ACTIVE' using errcode = '22023'; end if;
      perform private.pachanga_organizer_access_append_revision_v1(application.id, actor_id, payload, true);
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        status = 'submitted', submitted_by = actor_id, submitted_at = clock_timestamp(),
        revision = applications.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      reason_code := 'application.submitted';
    elsif action_name = 'application.withdraw' then
      if payload - array['reason'] <> '{}'::jsonb then raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
      if application.status not in ('draft','submitted','under_review','needs_information') then
        raise exception 'ORGANIZER_ACCESS_APPLICATION_NOT_WITHDRAWABLE' using errcode = '22023';
      end if;
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        status = 'withdrawn', terminal_at = clock_timestamp(),
        revision = applications.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      reason_code := 'application.withdrawn';
    elsif action_name = 'application.respond_information' then
      if payload - array['message','consent','intent','competitionType','teamCount','targetStartDate','municipality','area','fieldRelationship','summary','reason'] <> '{}'::jsonb then
        raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
      end if;
      if application.status <> 'needs_information' then raise exception 'ORGANIZER_ACCESS_INFORMATION_NOT_REQUESTED' using errcode = '22023'; end if;
      message_body := trim(coalesce(payload ->> 'message',''));
      if length(message_body) < 1 then raise exception 'ORGANIZER_ACCESS_MESSAGE_REQUIRED' using errcode = '22023'; end if;
      perform private.pachanga_organizer_access_append_revision_v1(application.id, actor_id, payload, true);
      insert into private.pachanga_organizer_access_messages_v1(
        application_id, application_revision, author_id, author_kind, message_kind,
        visibility, body, content_fingerprint
      ) values (
        application.id, application.revision + 1, actor_id, 'applicant', 'information_response',
        'APPLICANT_SHARED', left(message_body,4000),
        encode(extensions.digest(convert_to(message_body,'UTF8'),'sha256'),'hex')
      );
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        status = 'under_review', revision = applications.revision + 1,
        server_sequence = sequence_value, updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      reason_code := 'application.information_provided';
    else
      if payload - array['reason'] <> '{}'::jsonb then raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
      if application.status not in ('rejected','withdrawn','expired') then raise exception 'ORGANIZER_ACCESS_RECONSIDERATION_NOT_ALLOWED' using errcode = '22023'; end if;
      perform pg_advisory_xact_lock(hashtextextended(organizer_kind || ':' || organizer_id::text || ':' || application.requested_plan_code, 80841));
      insert into private.pachanga_organizer_access_applications_v1(
        organizer_kind, organizer_group_id, organizer_club_id, requested_plan_code,
        requested_access_mode, status, intent, expected_competition_type,
        expected_team_count, target_start_date, municipality, area, field_relationship,
        summary, reconsideration_of_id, created_by
      ) values (
        organizer_kind, application.organizer_group_id, application.organizer_club_id,
        application.requested_plan_code, application.requested_access_mode, 'draft',
        application.intent, application.expected_competition_type, application.expected_team_count,
        application.target_start_date, application.municipality, application.area,
        application.field_relationship, application.summary, application.id, actor_id
      ) returning * into existing_application;
      perform private.pachanga_organizer_access_append_revision_v1(existing_application.id, actor_id, '{}'::jsonb, false);
      insert into private.pachanga_organizer_access_decisions_v1(
        application_id, application_revision, decision_type, decision_code,
        applicant_message, private_note, supersedes_decision_id, decided_by
      ) values (
        existing_application.id, 1, 'RECONSIDERED', 'RECONSIDERATION_OPENED',
        'La solicitud se ha reabierto para una nueva revisión.', '',
        (select decisions.id from private.pachanga_organizer_access_decisions_v1 decisions
          where decisions.application_id = application.id order by decisions.server_sequence desc, decisions.id desc limit 1),
        actor_id
      );
      application := existing_application;
      reason_code := 'application.reconsidered';
    end if;
    snapshot := private.pachanga_organizer_access_application_snapshot_v1(application.id, false);
    return private.pachanga_organizer_access_store_v1(
      operation_id, actor_id, actor_kind, action_name, 'organizer_access_application',
      application.id::text, application.id, organizer_kind, organizer_id,
      application.revision, request_hash, client_metadata, reason_code,
      jsonb_build_object('status', application.status), snapshot
    );
  end if;

  if action_name in ('review.start','review.request_information','review.approve','review.reject','review.expire') then
    actor_kind := 'platform';
    if action_name = 'review.request_information' then
      platform_role := private.pachanga_platform_role_for_user_v1(actor_id);
      if platform_role is null or not (
        private.pachanga_platform_capabilities_v1(platform_role)
          ?| array['organizer_access.review', 'organizer_access.support']
      ) then
        raise exception 'Platform capability required: organizer_access.review or organizer_access.support'
          using errcode = '42501';
      end if;
    else
      platform_role := private.pachanga_platform_require_v1(
        case when action_name = 'review.approve' then 'organizer_access.approve' else 'organizer_access.review' end
      );
    end if;
    if not settings.review_enabled then raise exception 'ORGANIZER_ACCESS_REVIEW_DISABLED' using errcode = '42501'; end if;
    if action_name = 'review.start' then
      if payload - array['reason'] <> '{}'::jsonb then raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
      if application.status <> 'submitted' then raise exception 'ORGANIZER_ACCESS_REVIEW_NOT_STARTABLE' using errcode = '22023'; end if;
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        status = 'under_review', assigned_reviewer = actor_id,
        revision = applications.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      reason_code := 'review.started';
    elsif action_name = 'review.request_information' then
      if payload - array['message','privateNote','reason'] <> '{}'::jsonb then raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023'; end if;
      if application.status <> 'under_review' then raise exception 'ORGANIZER_ACCESS_REVIEW_STATE_INVALID' using errcode = '22023'; end if;
      message_body := trim(coalesce(payload ->> 'message',''));
      if length(message_body) < 1 then raise exception 'ORGANIZER_ACCESS_MESSAGE_REQUIRED' using errcode = '22023'; end if;
      insert into private.pachanga_organizer_access_messages_v1(
        application_id, application_revision, author_id, author_kind, message_kind,
        visibility, body, content_fingerprint
      ) values (
        application.id, application.revision, actor_id, 'platform', 'information_request',
        'APPLICANT_SHARED', left(message_body,4000),
        encode(extensions.digest(convert_to(message_body,'UTF8'),'sha256'),'hex')
      );
      if nullif(trim(payload ->> 'privateNote'),'') is not null then
        insert into private.pachanga_organizer_access_messages_v1(
          application_id, application_revision, author_id, author_kind, message_kind,
          visibility, body, content_fingerprint
        ) values (
          application.id, application.revision, actor_id, 'platform', 'review_note',
          'PLATFORM_PRIVATE', left(trim(payload ->> 'privateNote'),4000),
          encode(extensions.digest(convert_to(trim(payload ->> 'privateNote'),'UTF8'),'sha256'),'hex')
        );
      end if;
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        status = 'needs_information', assigned_reviewer = actor_id,
        revision = applications.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      reason_code := 'review.information_requested';
    elsif action_name = 'review.approve' then
      if payload - array['decisionCode','message','privateNote','grantPlanCode','grantSource','validFrom','validUntil','reason'] <> '{}'::jsonb then
        raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
      end if;
      if application.status <> 'under_review' then raise exception 'ORGANIZER_ACCESS_REVIEW_STATE_INVALID' using errcode = '22023'; end if;
      grant_plan_code := upper(nullif(trim(payload ->> 'grantPlanCode'),''));
      grant_source := upper(nullif(trim(payload ->> 'grantSource'),''));
      if application.requested_access_mode = 'PARTNERSHIP_REVIEW' then
        if not settings.partnership_approval_enabled then raise exception 'ORGANIZER_ACCESS_PARTNERSHIP_APPROVAL_DISABLED' using errcode = '42501'; end if;
        grant_plan_code := coalesce(grant_plan_code, application.requested_plan_code);
        grant_source := coalesce(grant_source, 'PARTNERSHIP');
      elsif grant_plan_code is null or grant_source is null then
        insert into private.pachanga_organizer_access_decisions_v1(
          application_id, application_revision, decision_type, decision_code,
          applicant_message, private_note, decided_by
        ) values (
          application.id, application.revision, 'APPROVED_INTEREST',
          upper(coalesce(nullif(trim(payload ->> 'decisionCode'),''),'PAID_PLAN_INTEREST_APPROVED')),
          left(coalesce(payload ->> 'message','Hemos registrado tu interés.'),2000),
          left(coalesce(payload ->> 'privateNote',''),4000), actor_id
        ) returning * into decision;
        sequence_value := nextval('private.pachanga_organizer_access_sequence');
        update private.pachanga_organizer_access_applications_v1 applications set
          status = 'approved_interest', terminal_at = clock_timestamp(), assigned_reviewer = actor_id,
          revision = applications.revision + 1, server_sequence = sequence_value,
          updated_at = clock_timestamp()
        where applications.id = application.id returning * into application;
        reason_code := 'review.approved_interest';
        snapshot := private.pachanga_organizer_access_application_snapshot_v1(application.id, true);
        return private.pachanga_organizer_access_store_v1(
          operation_id, actor_id, actor_kind, action_name, 'organizer_access_application',
          application.id::text, application.id, organizer_kind, organizer_id,
          application.revision, request_hash, client_metadata, reason_code,
          jsonb_build_object('status', application.status, 'grantCreated', false), snapshot
        );
      end if;
      if grant_source not in ('PARTNERSHIP','PROMOTION','PRIVATE_BETA','PLATFORM_GRANT') then
        raise exception 'ORGANIZER_ACCESS_GRANT_SOURCE_INVALID' using errcode = '22023';
      end if;
      if not exists (
        select 1 from public.pachanga_organizer_plan_catalog plans
        where plans.plan_code = grant_plan_code and plans.status = 'active'
          and plans.access_model = grant_source and not plans.requires_stripe
          and (plans.organizer_kind = organizer_kind or plans.organizer_kind = 'ANY')
      ) then raise exception 'ORGANIZER_ACCESS_GRANT_PLAN_INVALID' using errcode = '22023'; end if;
      insert into private.pachanga_organizer_access_decisions_v1(
        application_id, application_revision, decision_type, decision_code,
        applicant_message, private_note, grant_plan_code, grant_source,
        grant_valid_from, grant_valid_until, decided_by
      ) values (
        application.id, application.revision, 'APPROVED',
        upper(coalesce(nullif(trim(payload ->> 'decisionCode'),''),'ACCESS_APPROVED')),
        left(coalesce(payload ->> 'message','Acceso de organización aprobado.'),2000),
        left(coalesce(payload ->> 'privateNote',''),4000), grant_plan_code, grant_source,
        coalesce(nullif(payload ->> 'validFrom','')::timestamptz, clock_timestamp()),
        nullif(payload ->> 'validUntil','')::timestamptz, actor_id
      ) returning * into decision;
      access_grant_id := private.pachanga_organizer_access_create_grant_v1(
        application.id, decision.id, grant_plan_code, actor_id,
        decision.grant_valid_from, decision.grant_valid_until,
        left(coalesce(nullif(payload ->> 'reason',''),'Wave 8A approved application'),1200)
      );
      update private.pachanga_organizer_access_decisions_v1 decisions
      set resulting_access_grant_id = access_grant_id where decisions.id = decision.id;
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        status = 'approved', terminal_at = clock_timestamp(), assigned_reviewer = actor_id,
        revision = applications.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      if settings.onboarding_enabled then
        onboarding_id := private.pachanga_ensure_organizer_onboarding_v1(
          application.id, decision.id, access_grant_id, actor_id
        );
      end if;
      reason_code := 'review.approved';
    else
      if payload - array['decisionCode','message','privateNote','reason'] <> '{}'::jsonb then
        raise exception 'ORGANIZER_ACCESS_PAYLOAD_FIELD_NOT_ALLOWED' using errcode = '22023';
      end if;
      if application.status not in ('submitted','under_review','needs_information') then
        raise exception 'ORGANIZER_ACCESS_REVIEW_STATE_INVALID' using errcode = '22023';
      end if;
      insert into private.pachanga_organizer_access_decisions_v1(
        application_id, application_revision, decision_type, decision_code,
        applicant_message, private_note, decided_by
      ) values (
        application.id, application.revision,
        case when action_name = 'review.reject' then 'REJECTED' else 'EXPIRED' end,
        upper(coalesce(nullif(trim(payload ->> 'decisionCode'),''),
          case when action_name = 'review.reject' then 'APPLICATION_REJECTED' else 'APPLICATION_EXPIRED' end)),
        left(coalesce(payload ->> 'message',''),2000),
        left(coalesce(payload ->> 'privateNote',''),4000), actor_id
      ) returning * into decision;
      sequence_value := nextval('private.pachanga_organizer_access_sequence');
      update private.pachanga_organizer_access_applications_v1 applications set
        status = case when action_name = 'review.reject' then 'rejected' else 'expired' end,
        terminal_at = clock_timestamp(), assigned_reviewer = actor_id,
        revision = applications.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where applications.id = application.id returning * into application;
      reason_code := case when action_name = 'review.reject' then 'review.rejected' else 'review.expired' end;
    end if;
    snapshot := private.pachanga_organizer_access_application_snapshot_v1(application.id, true);
    return private.pachanga_organizer_access_store_v1(
      operation_id, actor_id, actor_kind, action_name, 'organizer_access_application',
      application.id::text, application.id, organizer_kind, organizer_id,
      application.revision, request_hash, client_metadata, reason_code,
      jsonb_build_object('status', application.status, 'accessGrantId', access_grant_id, 'onboardingId', onboarding_id), snapshot
    );
  end if;
  raise exception 'ORGANIZER_ACCESS_ACTION_NOT_AVAILABLE' using errcode = '0A000';
exception
  when invalid_text_representation or numeric_value_out_of_range or check_violation then
    raise exception 'ORGANIZER_ACCESS_COMMAND_FIELDS_INVALID' using errcode = '22023';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_organizer_access_application_v1(uuid, uuid, bigint, text, jsonb, jsonb) from public, anon;
grant execute on function public.command_pachanga_organizer_access_application_v1(uuid, uuid, bigint, text, jsonb, jsonb) to authenticated, service_role;

create or replace function public.get_pachanga_organizer_access_flags_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_organizer_access_settings_v1%rowtype;
begin
  select * into settings from private.pachanga_organizer_access_settings_v1 where singleton;
  return jsonb_build_object(
    'applicationsEnabled', settings.applications_enabled,
    'submissionEnabled', settings.submission_enabled,
    'reviewEnabled', settings.review_enabled,
    'partnershipApprovalEnabled', settings.partnership_approval_enabled,
    'onboardingEnabled', settings.onboarding_enabled,
    'firstCompetitionLauncherEnabled', settings.first_competition_launcher_enabled,
    'demoWorldV30Enabled', settings.demo_world_v30_enabled,
    'consentVersion', settings.consent_version,
    'privacyVersion', settings.privacy_version,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  );
end;
$$;

create or replace function public.get_my_pachanga_organizer_access_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'flags', public.get_pachanga_organizer_access_flags_v1(),
    'organizers', coalesce((
      select jsonb_agg(organizers.snapshot order by organizers.kind, organizers.name, organizers.id)
      from (
        select groups.id, 'TEAM'::text as kind,
          coalesce(nullif(groups.payload ->> 'name',''), nullif(groups.payload ->> 'teamName',''), 'Equipo') as name,
          true as active,
          jsonb_build_object(
            'id', groups.id, 'kind', 'TEAM',
            'name', coalesce(nullif(groups.payload ->> 'name',''), nullif(groups.payload ->> 'teamName',''), 'Equipo'),
            'active', true, 'actorRole', 'owner',
            'hasCompetitionAccess', private.pachanga_organizer_billing_creation_allowed_v1('TEAM', groups.id),
            'onboarding', (
              select private.pachanga_organizer_onboarding_snapshot_v1(workspaces.id)
              from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
              where workspaces.organizer_kind = 'TEAM' and workspaces.organizer_group_id = groups.id
                and workspaces.status in ('active','completed')
              order by workspaces.server_sequence desc, workspaces.id desc limit 1
            )
          ) as snapshot
        from public.pachanga_groups groups where groups.owner_id = actor_id
        union all
        select clubs.id, 'CLUB', clubs.name, clubs.operational_status = 'active',
          jsonb_build_object(
            'id', clubs.id, 'kind', 'CLUB', 'name', clubs.name,
            'active', clubs.operational_status = 'active',
            'actorRole', case when clubs.primary_owner_id = actor_id then 'owner' else 'club_competition_manager' end,
            'hasCompetitionAccess', private.pachanga_organizer_billing_creation_allowed_v1('CLUB', clubs.id),
            'onboarding', (
              select private.pachanga_organizer_onboarding_snapshot_v1(workspaces.id)
              from private.pachanga_organizer_onboarding_workspaces_v1 workspaces
              where workspaces.organizer_kind = 'CLUB' and workspaces.organizer_club_id = clubs.id
                and workspaces.status in ('active','completed')
              order by workspaces.server_sequence desc, workspaces.id desc limit 1
            )
          )
        from public.pachanga_clubs clubs
        where private.pachanga_club_can_v1(clubs.id, actor_id, 'competition_create')
      ) organizers
    ), '[]'::jsonb),
    'plans', coalesce((
      select jsonb_agg(jsonb_build_object(
        'code', plans.plan_code,
        'organizerKind', plans.organizer_kind,
        'accessModel', plans.access_model,
        'requiresStripe', plans.requires_stripe,
        'name', revisions.display_name,
        'summary', revisions.summary,
        'revision', revisions.version
      ) order by plans.server_sequence, plans.id)
      from public.pachanga_organizer_plan_catalog plans
      join lateral (
        select selected.* from public.pachanga_organizer_plan_revisions selected
        where selected.plan_id = plans.id and selected.status = 'active'
        order by selected.version desc, selected.id desc limit 1
      ) revisions on true
      where plans.status = 'active' and plans.public_available and plans.plan_family = 'ORGANIZER'
    ), '[]'::jsonb),
    'applications', coalesce((
      select jsonb_agg(private.pachanga_organizer_access_application_snapshot_v1(applications.id, false)
        order by applications.server_sequence desc, applications.id)
      from private.pachanga_organizer_access_applications_v1 applications
      where private.pachanga_organizer_access_actor_can_v1(
        applications.organizer_kind,
        coalesce(applications.organizer_group_id, applications.organizer_club_id),
        actor_id, 'read'
      )
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pachanga_organizer_access_application_v1(target_application_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare application private.pachanga_organizer_access_applications_v1%rowtype;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  select * into application from private.pachanga_organizer_access_applications_v1 applications
  where applications.id = target_application_id;
  if not found then raise exception 'ORGANIZER_ACCESS_APPLICATION_NOT_FOUND' using errcode = 'P0002'; end if;
  perform private.pachanga_organizer_access_require_actor_v1(
    application.organizer_kind,
    coalesce(application.organizer_group_id, application.organizer_club_id),
    actor_id, 'read'
  );
  return private.pachanga_organizer_access_application_snapshot_v1(application.id, false);
end;
$$;

create or replace function public.get_pachanga_platform_organizer_access_v1(
  target_status text default null,
  target_search text default null,
  target_limit integer default 50
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_role text;
declare normalized_status text := lower(nullif(trim(target_status),''));
declare normalized_search text := lower(nullif(trim(target_search),''));
declare selected_limit integer := least(greatest(coalesce(target_limit,50),1),200);
begin
  actor_role := private.pachanga_platform_require_v1('organizer_access.read');
  return jsonb_build_object(
    'actorRole', actor_role,
    'capabilities', private.pachanga_platform_capabilities_v1(actor_role),
    'flags', public.get_pachanga_organizer_access_flags_v1(),
    'counts', jsonb_build_object(
      'draft', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'draft'),
      'submitted', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'submitted'),
      'underReview', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'under_review'),
      'needsInformation', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'needs_information'),
      'approved', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'approved'),
      'approvedInterest', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'approved_interest'),
      'rejected', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'rejected'),
      'expired', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'expired'),
      'withdrawn', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'withdrawn')
    ),
    'applications', coalesce((
      select jsonb_agg(private.pachanga_organizer_access_application_snapshot_v1(filtered.id, true)
        order by filtered.server_sequence desc, filtered.id)
      from (
        select applications.*
        from private.pachanga_organizer_access_applications_v1 applications
        where (normalized_status is null or applications.status = normalized_status)
          and (normalized_search is null or lower(concat_ws(' ',
            applications.requested_plan_code, applications.municipality,
            applications.area, applications.summary
          )) like '%' || normalized_search || '%')
        order by applications.server_sequence desc, applications.id
        limit selected_limit
      ) filtered
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pachanga_organizer_access_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text;
begin
  actor_role := private.pachanga_platform_require_v1('organizer_access.read');
  return jsonb_build_object(
    'actorRole', actor_role,
    'flags', public.get_pachanga_organizer_access_flags_v1(),
    'applications', jsonb_build_object(
      'total', (select count(*) from private.pachanga_organizer_access_applications_v1),
      'active', (select count(*) from private.pachanga_organizer_access_applications_v1 where status in ('draft','submitted','under_review','needs_information')),
      'pendingReview', (select count(*) from private.pachanga_organizer_access_applications_v1 where status in ('submitted','under_review','needs_information')),
      'withoutReviewer', (select count(*) from private.pachanga_organizer_access_applications_v1 where status in ('submitted','under_review','needs_information') and assigned_reviewer is null),
      'needsInformation', (select count(*) from private.pachanga_organizer_access_applications_v1 where status = 'needs_information'),
      'terminal', (select count(*) from private.pachanga_organizer_access_applications_v1 where status in ('approved','approved_interest','rejected','withdrawn','expired')),
      'oldestPendingSeconds', coalesce((select extract(epoch from clock_timestamp() - min(updated_at))::bigint from private.pachanga_organizer_access_applications_v1 where status in ('submitted','under_review','needs_information')), 0)
    ),
    'orphanApprovedApplications', (
      select count(*) from private.pachanga_organizer_access_applications_v1 applications
      where applications.status = 'approved' and not exists (
        select 1 from private.pachanga_organizer_access_decisions_v1 decisions
        where decisions.application_id = applications.id and decisions.resulting_access_grant_id is not null
      )
    ),
    'interestWithGrant', (
      select count(*) from private.pachanga_organizer_access_applications_v1 applications
      where applications.status = 'approved_interest' and exists (
        select 1 from private.pachanga_organizer_access_decisions_v1 decisions
        where decisions.application_id = applications.id and decisions.resulting_access_grant_id is not null
      )
    ),
    'activeWorkspaces', (select count(*) from private.pachanga_organizer_onboarding_workspaces_v1 where status = 'active'),
    'grantsCreated', (select count(*) from private.pachanga_organizer_access_decisions_v1 where resulting_access_grant_id is not null),
    'decisionsMissingExpectedGrant', (
      select count(*) from private.pachanga_organizer_access_decisions_v1 decisions
      where decisions.decision_type = 'APPROVED' and decisions.resulting_access_grant_id is null
    ),
    'applicationGrantsWithoutDecision', (
      select count(*) from private.pachanga_organizer_access_grants_v1 grants
      where grants.source_reference like 'application:%' and grants.organizer_access_decision_id is null
    ),
    'duplicateApplicationsReused', (
      select count(*) from private.pachanga_organizer_access_events_v1 events
      where events.reason_code = 'application.already_active'
    ),
    'operationReceipts', (select count(*) from private.pachanga_organizer_access_operation_receipts_v1),
    'events', (select count(*) from private.pachanga_organizer_access_events_v1),
    'checkedAt', clock_timestamp()
  );
end;
$$;

revoke all on function public.get_pachanga_organizer_access_flags_v1() from public, anon;
revoke all on function public.get_my_pachanga_organizer_access_v1() from public, anon;
revoke all on function public.get_pachanga_organizer_access_application_v1(uuid) from public, anon;
revoke all on function public.get_pachanga_platform_organizer_access_v1(text, text, integer) from public, anon;
revoke all on function public.get_pachanga_organizer_access_health_v1() from public, anon;
grant execute on function public.get_pachanga_organizer_access_flags_v1() to authenticated, service_role;
grant execute on function public.get_my_pachanga_organizer_access_v1() to authenticated, service_role;
grant execute on function public.get_pachanga_organizer_access_application_v1(uuid) to authenticated, service_role;
grant execute on function public.get_pachanga_platform_organizer_access_v1(text, text, integer) to authenticated, service_role;
grant execute on function public.get_pachanga_organizer_access_health_v1() to authenticated, service_role;
