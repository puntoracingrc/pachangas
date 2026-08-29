-- Wave 8A: actor authority, application hashing and canonical entitlement bridge.

set lock_timeout = '5s';
set statement_timeout = '5min';

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
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'billing.write', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read',
      'organizer_access.read', 'organizer_access.review', 'organizer_access.approve', 'organizer_access.override'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'billing.write', 'system.read', 'flags.read', 'flags.write', 'audit.read',
      'competitions.read', 'competitions.manage', 'clubs.read', 'clubs.manage',
      'referees.read', 'referees.manage', 'referees.health.read',
      'organizer_access.read', 'organizer_access.review', 'organizer_access.approve'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read', 'clubs.read', 'referees.read',
      'organizer_access.read', 'organizer_access.support'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read',
      'billing.read', 'billing.write', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read', 'referees.health.read'
    )
    else '[]'::jsonb
  end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_organizer_access_request_hash_v1(
  target_action text,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'action', lower(trim(coalesce(target_action, ''))),
    'aggregateId', target_aggregate_id,
    'expectedRevision', target_expected_revision,
    'payload', coalesce(target_payload, '{}'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_organizer_access_content_fingerprint_v1(
  target_plan_code text,
  target_access_mode text,
  target_intent text,
  target_competition_type text,
  target_team_count integer,
  target_start_date date,
  target_municipality text,
  target_area text,
  target_field_relationship text,
  target_summary text,
  target_consent_version text,
  target_privacy_version text
)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'planCode', upper(trim(coalesce(target_plan_code, ''))),
    'accessMode', upper(trim(coalesce(target_access_mode, ''))),
    'intent', upper(trim(coalesce(target_intent, ''))),
    'competitionType', upper(trim(coalesce(target_competition_type, ''))),
    'teamCount', target_team_count,
    'startDate', target_start_date,
    'municipality', trim(coalesce(target_municipality, '')),
    'area', trim(coalesce(target_area, '')),
    'fieldRelationship', trim(coalesce(target_field_relationship, '')),
    'summary', trim(coalesce(target_summary, '')),
    'consentVersion', target_consent_version,
    'privacyVersion', target_privacy_version
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_organizer_access_client_metadata_v1(source jsonb)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', left(coalesce(source ->> 'clientVersion', ''), 80),
    'serviceWorkerVersion', left(coalesce(source ->> 'serviceWorkerVersion', ''), 80),
    'displayMode', left(coalesce(source ->> 'displayMode', ''), 24),
    'sessionId', left(coalesce(source ->> 'sessionId', ''), 80),
    'surface', left(coalesce(source ->> 'surface', ''), 80)
  ));
$$;

create or replace function private.pachanga_organizer_access_plan_mode_v1(target_plan_code text)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case plans.access_model
    when 'PARTNERSHIP' then 'PARTNERSHIP_REVIEW'
    when 'SUBSCRIPTION' then 'PAID_PLAN_INTEREST'
    else null
  end
  from public.pachanga_organizer_plan_catalog plans
  where plans.plan_code = upper(trim(target_plan_code))
    and plans.status = 'active';
$$;

create or replace function private.pachanga_organizer_access_owner_id_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
declare owner_id uuid;
begin
  if normalized_kind = 'TEAM' then
    select groups.owner_id into owner_id
    from public.pachanga_groups groups where groups.id = target_organizer_id;
  elsif normalized_kind = 'CLUB' then
    select clubs.primary_owner_id into owner_id
    from public.pachanga_clubs clubs where clubs.id = target_organizer_id;
  end if;
  return owner_id;
end;
$$;

create or replace function private.pachanga_organizer_access_actor_can_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
begin
  if target_actor_id is null or target_organizer_id is null then return false; end if;
  if target_capability = 'read'
     and coalesce(private.pachanga_platform_capabilities_v1(
       private.pachanga_platform_role_for_user_v1(target_actor_id)
     ) ? 'organizer_access.read', false) then return true; end if;
  if normalized_kind = 'TEAM' then
    return exists (
      select 1 from public.pachanga_groups groups
      where groups.id = target_organizer_id and groups.owner_id = target_actor_id
    );
  end if;
  if normalized_kind = 'CLUB' then
    return private.pachanga_club_can_v1(
      target_organizer_id, target_actor_id,
      case when target_capability = 'read' then 'read' else 'competition_create' end
    );
  end if;
  return false;
end;
$$;

create or replace function private.pachanga_organizer_access_require_actor_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if not private.pachanga_organizer_access_actor_can_v1(
    target_organizer_kind, target_organizer_id, target_actor_id, target_capability
  ) then
    raise exception 'ORGANIZER_ACCESS_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
end;
$$;

create or replace function private.pachanga_organizer_access_require_actor_locked_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare normalized_kind text := upper(trim(coalesce(target_organizer_kind, '')));
declare locked_owner_id uuid;
begin
  if normalized_kind = 'TEAM' then
    select groups.owner_id into locked_owner_id
    from public.pachanga_groups groups
    where groups.id = target_organizer_id
    for update;
    if not found or locked_owner_id <> target_actor_id then
      raise exception 'ORGANIZER_ACCESS_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    return;
  elsif normalized_kind = 'CLUB' then
    perform 1 from public.pachanga_clubs clubs
    where clubs.id = target_organizer_id
    for update;
    if not found then
      raise exception 'ORGANIZER_ACCESS_AUTHORITY_REQUIRED' using errcode = '42501';
    end if;
    perform private.pachanga_organizer_access_require_actor_v1(
      normalized_kind, target_organizer_id, target_actor_id, target_capability
    );
    return;
  end if;
  raise exception 'ORGANIZER_ACCESS_AUTHORITY_REQUIRED' using errcode = '42501';
end;
$$;

create or replace function private.pachanga_organizer_access_existing_plan_grant_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  target_plan_code text
)
returns uuid
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  with authority_time as materialized (select clock_timestamp() as checked_at)
  select access.id
  from private.pachanga_organizer_access_grants_v1 access
  join public.pachanga_organizer_plan_revisions revisions on revisions.id = access.plan_revision_id
  join public.pachanga_organizer_plan_catalog plans on plans.id = revisions.plan_id
  cross join authority_time
  where access.organizer_kind = upper(target_organizer_kind)
    and (
      (access.organizer_kind = 'TEAM' and access.organizer_group_id = target_organizer_id)
      or (access.organizer_kind = 'CLUB' and access.organizer_club_id = target_organizer_id)
    )
    and plans.plan_code = upper(target_plan_code)
    and access.status in ('active', 'grace', 'continuity')
    and access.valid_from <= authority_time.checked_at
    and (access.valid_until is null or access.valid_until > authority_time.checked_at)
  order by access.server_sequence desc, access.id desc
  limit 1;
$$;

create unique index pachanga_organizer_access_one_active_plan_idx
  on private.pachanga_organizer_access_grants_v1(
    organizer_kind,
    coalesce(organizer_group_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(organizer_club_id, '00000000-0000-0000-0000-000000000000'::uuid),
    plan_revision_id
  )
  where status in ('active', 'grace', 'continuity');

create or replace function private.pachanga_organizer_access_rate_limit_v1(
  target_actor_id uuid,
  target_action text,
  target_organizer_kind text,
  target_organizer_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare action_limit integer;
declare action_window interval;
declare event_count integer;
begin
  if exists (
    select 1
    from private.pachanga_organizer_access_rate_limit_overrides_v1 overrides
    where overrides.organizer_kind = upper(target_organizer_kind)
      and (
        (overrides.organizer_kind = 'TEAM' and overrides.organizer_group_id = target_organizer_id)
        or (overrides.organizer_kind = 'CLUB' and overrides.organizer_club_id = target_organizer_id)
      )
      and (overrides.action_pattern = target_action or overrides.action_pattern = 'application.*')
      and overrides.valid_until > clock_timestamp()
  ) then return; end if;
  action_limit := case
    when target_action = 'application.create' then 10
    when target_action = 'application.submit' then 5
    when target_action in ('application.update', 'application.respond_information') then 30
    when target_action = 'application.withdraw' then 10
    else 60
  end;
  action_window := case when target_action in ('application.create', 'application.submit')
    then interval '1 day' else interval '1 hour' end;
  select count(*) into event_count
  from private.pachanga_organizer_access_events_v1 events
  where events.actor_id = target_actor_id
    and events.action = target_action
    and events.confirmed_at >= clock_timestamp() - action_window;
  if event_count >= action_limit then
    raise exception 'ORGANIZER_ACCESS_RATE_LIMITED' using errcode = 'PT429';
  end if;
end;
$$;

create or replace function private.pachanga_organizer_access_create_grant_v1(
  target_application_id uuid,
  target_decision_id uuid,
  target_plan_code text,
  target_actor_id uuid,
  target_valid_from timestamptz,
  target_valid_until timestamptz,
  target_reason text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare application private.pachanga_organizer_access_applications_v1%rowtype;
declare selected_plan public.pachanga_organizer_plan_catalog%rowtype;
declare selected_revision public.pachanga_organizer_plan_revisions%rowtype;
declare access private.pachanga_organizer_access_grants_v1%rowtype;
declare capability_row record;
declare organizer_id uuid;
declare sequence_value bigint;
declare grant_source text;
declare effective_from timestamptz := coalesce(target_valid_from, clock_timestamp());
begin
  select * into application
  from private.pachanga_organizer_access_applications_v1 applications
  where applications.id = target_application_id for update;
  if not found then raise exception 'ORGANIZER_ACCESS_APPLICATION_NOT_FOUND' using errcode = 'P0002'; end if;
  organizer_id := coalesce(application.organizer_group_id, application.organizer_club_id);
  if application.organizer_kind = 'TEAM' then
    perform 1 from public.pachanga_groups groups
    where groups.id = organizer_id for update;
  else
    perform 1 from public.pachanga_clubs clubs
    where clubs.id = organizer_id for update;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(application.organizer_kind || ':' || organizer_id::text, 80831));
  if target_valid_until is not null and target_valid_until <= greatest(effective_from, clock_timestamp()) then
    raise exception 'ORGANIZER_ACCESS_GRANT_EXPIRY_INVALID' using errcode = '22023';
  end if;
  select * into selected_plan
  from public.pachanga_organizer_plan_catalog plans
  where plans.plan_code = upper(trim(target_plan_code))
    and plans.status = 'active'
    and not plans.requires_stripe
    and plans.access_model in ('PARTNERSHIP', 'PROMOTION', 'PRIVATE_BETA', 'PLATFORM_GRANT')
    and (plans.organizer_kind = application.organizer_kind or plans.organizer_kind = 'ANY');
  if not found then raise exception 'ORGANIZER_ACCESS_GRANT_PLAN_INVALID' using errcode = '22023'; end if;
  select * into selected_revision
  from public.pachanga_organizer_plan_revisions revisions
  where revisions.plan_id = selected_plan.id and revisions.status = 'active'
  order by revisions.version desc, revisions.id desc limit 1;
  if not found then
    raise exception 'ORGANIZER_ACCESS_GRANT_PLAN_REVISION_MISSING' using errcode = '22023';
  end if;
  select grants.* into access
  from private.pachanga_organizer_access_grants_v1 grants
  where grants.organizer_access_decision_id = target_decision_id;
  if found then return access.id; end if;
  select grants.* into access
  from private.pachanga_organizer_access_grants_v1 grants
  where grants.organizer_kind = application.organizer_kind
    and (
      (application.organizer_kind = 'TEAM' and grants.organizer_group_id = organizer_id)
      or (application.organizer_kind = 'CLUB' and grants.organizer_club_id = organizer_id)
    )
    and grants.plan_revision_id = selected_revision.id
    and grants.status in ('active', 'grace', 'continuity')
    and grants.valid_from <= clock_timestamp()
    and (grants.valid_until is null or grants.valid_until > clock_timestamp())
  order by grants.server_sequence desc, grants.id desc limit 1;
  if found and access.organizer_access_decision_id = target_decision_id then
    return access.id;
  elsif found then
    raise exception 'ORGANIZER_ACCESS_GRANT_CONFLICT' using errcode = 'PT409';
  end if;
  if exists (
    select 1
    from public.pachanga_competition_entitlement_grants grants
    join public.pachanga_organizer_plan_features features
      on features.plan_revision_id = selected_revision.id
     and features.enabled
     and features.entitlement_capability
     and features.feature_key = grants.capability
    where grants.organizer_kind = application.organizer_kind
      and (
        (application.organizer_kind = 'TEAM' and grants.organizer_group_id = organizer_id)
        or (application.organizer_kind = 'CLUB' and grants.organizer_club_id = organizer_id)
      )
      and grants.billing_access_grant_id is null
      and grants.status = 'active'
      and grants.valid_from <= clock_timestamp()
      and (grants.expires_at is null or grants.expires_at > clock_timestamp())
  ) then
    raise exception 'ORGANIZER_ACCESS_LEGACY_ENTITLEMENT_CONFLICT' using errcode = 'PT409';
  end if;
  sequence_value := nextval('private.pachanga_organizer_billing_sequence');
  grant_source := case selected_plan.access_model
    when 'PARTNERSHIP' then 'partnership'
    when 'PROMOTION' then 'promotion'
    else 'platform_grant'
  end;
  insert into private.pachanga_organizer_access_grants_v1(
    organizer_kind, organizer_group_id, organizer_club_id, plan_revision_id,
    access_source, source_reference, status, valid_from, valid_until, reason,
    granted_by, revision, server_sequence, organizer_access_decision_id
  ) values (
    application.organizer_kind,
    case when application.organizer_kind = 'TEAM' then organizer_id end,
    case when application.organizer_kind = 'CLUB' then organizer_id end,
    selected_revision.id, selected_plan.access_model,
    'application:' || target_application_id::text || ':decision:' || target_decision_id::text,
    'active', effective_from, target_valid_until, left(target_reason, 1200),
    target_actor_id, 1, sequence_value, target_decision_id
  ) returning * into access;
  for capability_row in
    select features.feature_key
    from public.pachanga_organizer_plan_features features
    where features.plan_revision_id = selected_revision.id
      and features.enabled and features.entitlement_capability
    order by features.display_order, features.feature_key
  loop
    insert into public.pachanga_competition_entitlement_grants(
      organizer_kind, organizer_group_id, organizer_club_id, capability, grant_source,
      status, valid_from, expires_at, reason, revision, server_sequence, granted_by,
      billing_access_grant_id, billing_plan_revision_id, created_at, updated_at
    ) values (
      application.organizer_kind,
      case when application.organizer_kind = 'TEAM' then organizer_id end,
      case when application.organizer_kind = 'CLUB' then organizer_id end,
      capability_row.feature_key, grant_source, 'active', effective_from,
      target_valid_until, left('WAVE8A ' || selected_plan.access_model || ': ' || target_reason, 1200),
      1, nextval('private.pachanga_competition_sequence'), target_actor_id,
      access.id, selected_revision.id,
      clock_timestamp(), clock_timestamp()
    );
  end loop;
  return access.id;
exception
  when unique_violation then
    select grants.* into access
    from private.pachanga_organizer_access_grants_v1 grants
    where grants.organizer_kind = application.organizer_kind
      and (
        (application.organizer_kind = 'TEAM' and grants.organizer_group_id = organizer_id)
        or (application.organizer_kind = 'CLUB' and grants.organizer_club_id = organizer_id)
      )
      and grants.plan_revision_id = selected_revision.id
      and grants.status in ('active', 'grace', 'continuity')
    order by grants.server_sequence desc, grants.id desc limit 1;
    if found and access.organizer_access_decision_id = target_decision_id then
      return access.id;
    elsif found then
      raise exception 'ORGANIZER_ACCESS_GRANT_CONFLICT' using errcode = 'PT409';
    end if;
    raise;
end;
$$;

create or replace function private.pachanga_organizer_access_engine_bundle_v1(
  target_organizer_kind text,
  target_organizer_id uuid,
  required_capabilities text[],
  legacy_program_key text,
  default_team_cap integer,
  maximum_team_cap integer
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with eligible as (
    select grants.*,
      coalesce(grants.bundle_id, grants.billing_access_grant_id) as authority_bundle_id,
      case
        when grants.program_key = legacy_program_key then legacy_program_key
        else 'ORGANIZER_ACCESS_V1'
      end as authority_program_key,
      coalesce(
        grants.beta_team_cap::integer,
        least(
          greatest(coalesce(applications.expected_team_count, default_team_cap), 4),
          maximum_team_cap
        )
      ) as authority_team_cap
    from public.pachanga_competition_entitlement_grants grants
    left join private.pachanga_organizer_access_grants_v1 access_grants
      on access_grants.id = grants.billing_access_grant_id
    left join private.pachanga_organizer_access_decisions_v1 decisions
      on decisions.id = access_grants.organizer_access_decision_id
    left join private.pachanga_organizer_access_applications_v1 applications
      on applications.id = decisions.application_id
    where grants.organizer_kind = upper(trim(target_organizer_kind))
      and (
        (grants.organizer_kind = 'TEAM' and grants.organizer_group_id = target_organizer_id)
        or (grants.organizer_kind = 'CLUB' and grants.organizer_club_id = target_organizer_id)
      )
      and grants.capability = any(required_capabilities)
      and (
        grants.program_key = legacy_program_key
        or grants.billing_access_grant_id is not null
      )
      and coalesce(grants.bundle_id, grants.billing_access_grant_id) is not null
  ), bundles as (
    select eligible.authority_bundle_id as bundle_id,
      eligible.authority_program_key as program_key,
      max(eligible.authority_team_cap) as team_cap,
      min(eligible.valid_from) as valid_from,
      max(eligible.expires_at) as expires_at,
      max(eligible.server_sequence) as latest_sequence,
      min(eligible.created_at) as granted_at,
      max(eligible.updated_at) as updated_at,
      count(distinct eligible.capability) filter (
        where eligible.status = 'active'
          and eligible.valid_from <= statement_timestamp()
          and (eligible.expires_at is null or eligible.expires_at > statement_timestamp())
      ) as active_capabilities,
      bool_or(eligible.status = 'revoked') as has_revoked,
      jsonb_agg(jsonb_build_object(
        'id', eligible.id,
        'capability', eligible.capability,
        'status', case
          when eligible.status = 'revoked' then 'revoked'
          when eligible.valid_from > statement_timestamp() then 'scheduled'
          when eligible.expires_at is not null and eligible.expires_at <= statement_timestamp() then 'expired'
          else 'active'
        end,
        'revision', eligible.revision,
        'serverSequence', eligible.server_sequence
      ) order by eligible.capability, eligible.server_sequence, eligible.id) as grants
    from eligible
    group by eligible.authority_bundle_id, eligible.authority_program_key
  ), selected as (
    select bundles.*
    from bundles
    order by bundles.latest_sequence desc, bundles.bundle_id desc
    limit 1
  )
  select coalesce((
    select jsonb_build_object(
      'bundleId', selected.bundle_id,
      'programKey', selected.program_key,
      'status', case
        when selected.active_capabilities = cardinality(required_capabilities) then 'active'
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
    'programKey', legacy_program_key,
    'status', 'not_granted',
    'capabilities', '[]'::jsonb
  ));
$$;

create or replace function private.pachanga_league_private_beta_bundle_snapshot_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_organizer_access_engine_bundle_v1(
    target_organizer_kind,
    target_organizer_id,
    private.pachanga_league_private_beta_capabilities_v1(),
    'LEAGUE_PRIVATE_BETA_V1',
    12,
    20
  );
$$;

create or replace function private.pachanga_league_private_beta_active_bundle_id_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case
    when snapshot ->> 'status' = 'active' then nullif(snapshot ->> 'bundleId', '')::uuid
    else null
  end
  from (
    select private.pachanga_league_private_beta_bundle_snapshot_v1(
      target_organizer_kind,
      target_organizer_id
    ) as snapshot
  ) resolved;
$$;

create or replace function private.pachanga_tournament_bundle_snapshot_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_organizer_access_engine_bundle_v1(
    target_organizer_kind,
    target_organizer_id,
    private.pachanga_tournament_capabilities_v1(),
    'TOURNAMENT_PRIVATE_BETA_V1',
    16,
    64
  );
$$;

create or replace function private.pachanga_tournament_active_bundle_id_v1(
  target_organizer_kind text,
  target_organizer_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case
    when snapshot ->> 'status' = 'active' then nullif(snapshot ->> 'bundleId', '')::uuid
    else null
  end
  from (
    select private.pachanga_tournament_bundle_snapshot_v1(
      target_organizer_kind,
      target_organizer_id
    ) as snapshot
  ) resolved;
$$;

revoke all on function private.pachanga_organizer_access_request_hash_v1(text, uuid, bigint, jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_content_fingerprint_v1(text, text, text, text, integer, date, text, text, text, text, text, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_client_metadata_v1(jsonb) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_plan_mode_v1(text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_owner_id_v1(text, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_actor_can_v1(text, uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_require_actor_v1(text, uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_existing_plan_grant_v1(text, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_rate_limit_v1(uuid, text, text, uuid) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_create_grant_v1(uuid, uuid, text, uuid, timestamptz, timestamptz, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_require_actor_locked_v1(text, uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.pachanga_organizer_access_engine_bundle_v1(text, uuid, text[], text, integer, integer) from public, anon, authenticated;
