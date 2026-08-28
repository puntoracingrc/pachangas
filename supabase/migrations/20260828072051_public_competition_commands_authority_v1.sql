-- Pachangas IQ Wave 7A: publication and registration command authority.
-- Every mutation resolves actor, permissions, time, rules and capacity inside
-- PostgreSQL and returns a canonical confirmed snapshot.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table private.pachanga_public_competition_rate_limit_events (
  id bigint generated always as identity primary key,
  actor_id uuid not null references auth.users(id) on delete cascade,
  operation_id uuid not null unique,
  action text not null,
  scope_key text not null,
  server_sequence bigint not null unique
    default nextval('private.pachanga_competition_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  check (length(action) between 3 and 120),
  check (length(scope_key) between 1 and 180)
);

create index pachanga_public_competition_rate_limit_actor_idx
  on private.pachanga_public_competition_rate_limit_events(
    actor_id, action, created_at desc, id desc
  );

alter table private.pachanga_public_competition_rate_limit_events enable row level security;
revoke all on table private.pachanga_public_competition_rate_limit_events
  from public, anon, authenticated;
grant all on table private.pachanga_public_competition_rate_limit_events to service_role;

create or replace function private.pachanga_public_competition_assert_feature_v1(
  target_feature text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare enabled boolean;
begin
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  enabled := case target_feature
    when 'foundation' then settings.public_competition_foundation_enabled
    when 'publication' then settings.public_competition_publication_enabled
    when 'discovery' then settings.public_competition_discovery_enabled
    when 'registration' then settings.public_competition_registration_requests_enabled
    when 'waitlist' then settings.public_competition_waitlist_enabled
    when 'calendar' then settings.public_competition_calendar_enabled
    when 'results' then settings.public_competition_results_enabled
    when 'standings' then settings.public_competition_standings_enabled
    when 'bracket' then settings.public_competition_bracket_enabled
    when 'exceptions' then settings.public_competition_exception_status_enabled
    when 'referees' then settings.public_competition_referee_display_enabled
    else false end;
  if not coalesce(enabled, false) then
    raise exception 'PUBLIC_COMPETITION_FEATURE_DISABLED:%', target_feature using errcode = '42501';
  end if;
end;
$$;

create or replace function private.pachanga_public_competition_is_organizer_actor_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select target_actor_id is not null and exists (
    select 1
    from public.pachanga_competitions competitions
    where competitions.id = target_competition_id
      and (
        (
          competitions.organizer_kind = 'TEAM'
          and exists (
            select 1 from public.pachanga_groups teams
            where teams.id = competitions.organizer_group_id
              and teams.owner_id = target_actor_id
          )
        )
        or (
          competitions.organizer_kind = 'CLUB'
          and (
            exists (
              select 1 from public.pachanga_clubs clubs
              where clubs.id = competitions.organizer_club_id
                and clubs.primary_owner_id = target_actor_id
            )
            or exists (
              select 1 from public.pachanga_club_memberships memberships
              where memberships.club_id = competitions.organizer_club_id
                and memberships.user_id = target_actor_id
                and memberships.status = 'active'
                and memberships.role in (
                  'club_owner', 'club_admin', 'club_competition_manager'
                )
            )
          )
        )
        or exists (
          select 1 from public.pachanga_competition_staff_assignments assignments
          where assignments.competition_id = competitions.id
            and assignments.user_id = target_actor_id
            and assignments.status = 'active'
            and assignments.staff_role in (
              'competition_owner', 'competition_director', 'competition_admin'
            )
        )
      )
  );
$$;

create or replace function public.command_pachanga_public_competition_moderation_v1(
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
declare actor_role text;
declare actor_kind text := 'authenticated';
declare action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare metadata jsonb;
declare request_hash text;
declare replay jsonb;
declare response jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare reason_code_value text;
declare public_reason_value text;
declare private_reason_value text;
declare next_status text;
declare review_action_value text;
declare previous_status text;
declare before_state jsonb;
declare after_state jsonb;
declare snapshot jsonb;
declare competition_row public.pachanga_competitions%rowtype;
declare publication_row public.pachanga_competition_publications%rowtype;
declare consent_row public.pachanga_competition_publication_consents%rowtype;
declare report_row private.pachanga_competition_reports%rowtype;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 1 or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_PUBLIC_COMPETITION_MODERATION_COMMAND' using errcode = '22023';
  end if;
  if action not in (
    'publication.approve', 'publication.reject', 'publication.request_changes',
    'publication.publish', 'publication.suspend', 'publication.restore',
    'publication.archive', 'publication.organizer.verify',
    'report.review', 'report.resolve', 'report.dismiss'
  ) then raise exception 'PUBLIC_COMPETITION_MODERATION_ACTION_INVALID' using errcode = '22023'; end if;
  if exists (
    select 1 from jsonb_object_keys(payload) keys(key)
    where keys.key not in ('reason', 'publicReason', 'privateReason')
  ) then raise exception 'PUBLIC_COMPETITION_MODERATION_FIELD_FORBIDDEN' using errcode = '22023'; end if;

  actor_role := case when action like 'report.%'
    then private.pachanga_platform_require_v1('moderation.write')
    else private.pachanga_platform_require_v1('competitions.manage') end;
  perform private.pachanga_public_competition_assert_feature_v1('foundation');
  metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91703));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;

  reason_code_value := left(coalesce(nullif(trim(payload ->> 'reason'), ''), action), 120);
  public_reason_value := left(trim(coalesce(payload ->> 'publicReason', '')), 500);
  private_reason_value := left(trim(coalesce(payload ->> 'privateReason', '')), 1200);

  if action like 'report.%' then
    select * into report_row
    from private.pachanga_competition_reports reports
    where reports.id = aggregate_id
    for update;
    if not found then raise exception 'COMPETITION_REPORT_NOT_FOUND' using errcode = 'P0002'; end if;
    if report_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if report_row.reporter_user_id = actor_id then
      raise exception 'COMPETITION_REPORT_SELF_REVIEW_FORBIDDEN' using errcode = '42501';
    end if;
    select * into competition_row from public.pachanga_competitions competitions
    where competitions.id = report_row.competition_id for update;
    select * into publication_row from public.pachanga_competition_publications publications
    where publications.id = report_row.publication_id;
    before_state := jsonb_build_object(
      'opaqueReference', report_row.opaque_reference,
      'status', report_row.status,
      'revision', report_row.revision
    );
    next_status := case action
      when 'report.review' then 'under_review'
      when 'report.resolve' then 'resolved'
      else 'dismissed' end;
    if action = 'report.review' and report_row.status <> 'submitted' then
      raise exception 'COMPETITION_REPORT_REVIEW_STATE_INVALID' using errcode = 'PT409';
    end if;
    if action in ('report.resolve', 'report.dismiss')
       and report_row.status not in ('submitted', 'under_review') then
      raise exception 'COMPETITION_REPORT_RESOLUTION_STATE_INVALID' using errcode = 'PT409';
    end if;
    if action in ('report.resolve', 'report.dismiss')
       and length(public_reason_value) < 3 then
      raise exception 'COMPETITION_REPORT_PUBLIC_RESOLUTION_REQUIRED' using errcode = '22023';
    end if;
    sequence_value := nextval('private.pachanga_competition_sequence');
    update private.pachanga_competition_reports reports set
      status = next_status,
      resolution_code = reason_code_value,
      public_resolution = public_reason_value,
      private_resolution = private_reason_value,
      reviewed_by = actor_id,
      reviewed_at = confirmed_at,
      revision = reports.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where reports.id = report_row.id
    returning * into report_row;
    after_state := jsonb_build_object(
      'opaqueReference', report_row.opaque_reference,
      'status', report_row.status,
      'revision', report_row.revision,
      'publicResolution', report_row.public_resolution,
      'privateResolution', report_row.private_resolution
    );
    snapshot := jsonb_build_object(
      'kind', 'CompetitionReportModeration',
      'opaqueReference', report_row.opaque_reference,
      'competitionId', report_row.competition_id,
      'publicationId', report_row.publication_id,
      'category', report_row.category,
      'summary', report_row.summary,
      'status', report_row.status,
      'resolutionCode', report_row.resolution_code,
      'publicResolution', report_row.public_resolution,
      'privateResolution', report_row.private_resolution,
      'revision', report_row.revision,
      'serverSequence', report_row.server_sequence,
      'reviewedAt', report_row.reviewed_at
    );
    response := private.pachanga_competition_store_command_v1(
      operation_id, actor_id, actor_kind, action, 'competition_report',
      report_row.id, competition_row.id, competition_row.organizer_group_id,
      report_row.revision, report_row.server_sequence, reason_code_value,
      request_hash, metadata,
      jsonb_build_object(
        'opaqueReference', report_row.opaque_reference,
        'status', report_row.status,
        'publicResolution', report_row.public_resolution
      ), snapshot, confirmed_at
    );
  else
    perform private.pachanga_public_competition_assert_feature_v1('publication');
    select * into publication_row
    from public.pachanga_competition_publications publications
    where publications.id = aggregate_id
    for update;
    if not found then raise exception 'PUBLICATION_NOT_FOUND' using errcode = 'P0002'; end if;
    if publication_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    select * into competition_row from public.pachanga_competitions competitions
    where competitions.id = publication_row.competition_id for update;
    if private.pachanga_public_competition_is_organizer_actor_v1(
      competition_row.id, actor_id
    ) then raise exception 'PUBLICATION_SELF_REVIEW_FORBIDDEN' using errcode = '42501'; end if;
    if publication_row.lifecycle_status = 'archived' then
      raise exception 'PUBLICATION_ARCHIVED' using errcode = 'PT409';
    end if;
    previous_status := publication_row.lifecycle_status;
    before_state := jsonb_build_object(
      'status', previous_status,
      'organizerVerified', publication_row.organizer_verified,
      'revision', publication_row.revision,
      'contentFingerprint', publication_row.content_fingerprint
    );

    if action in ('publication.approve', 'publication.publish', 'publication.restore') then
      select * into consent_row
      from public.pachanga_competition_publication_consents consents
      where consents.id = publication_row.current_consent_id
        and consents.status = 'current';
      if consent_row.id is null
         or consent_row.content_fingerprint <> publication_row.content_fingerprint then
        raise exception 'PUBLICATION_CURRENT_CONSENT_REQUIRED' using errcode = '42501';
      end if;
    end if;

    next_status := previous_status;
    review_action_value := case action
      when 'publication.approve' then 'APPROVE'
      when 'publication.reject' then 'REJECT'
      when 'publication.request_changes' then 'REQUEST_CHANGES'
      when 'publication.publish' then 'PUBLISH'
      when 'publication.suspend' then 'SUSPEND'
      when 'publication.restore' then 'RESTORE'
      when 'publication.archive' then 'ARCHIVE'
      else 'VERIFY_ORGANIZER' end;

    if action = 'publication.approve' then
      if previous_status <> 'pending_review' then
        raise exception 'PUBLICATION_APPROVE_STATE_INVALID' using errcode = 'PT409';
      end if;
      next_status := 'approved';
    elsif action = 'publication.reject' then
      if previous_status <> 'pending_review' then
        raise exception 'PUBLICATION_REJECT_STATE_INVALID' using errcode = 'PT409';
      end if;
      next_status := 'rejected';
    elsif action = 'publication.request_changes' then
      if previous_status <> 'pending_review' then
        raise exception 'PUBLICATION_CHANGES_STATE_INVALID' using errcode = 'PT409';
      end if;
      next_status := 'changes_requested';
    elsif action = 'publication.publish' then
      if previous_status <> 'approved' then
        raise exception 'PUBLICATION_PUBLISH_STATE_INVALID' using errcode = 'PT409';
      end if;
      if publication_row.visibility not in ('public', 'unlisted') then
        raise exception 'PUBLICATION_PUBLIC_VISIBILITY_REQUIRED' using errcode = '22023';
      end if;
      next_status := 'published';
    elsif action = 'publication.suspend' then
      if previous_status <> 'published' then
        raise exception 'PUBLICATION_SUSPEND_STATE_INVALID' using errcode = 'PT409';
      end if;
      next_status := 'suspended';
    elsif action = 'publication.restore' then
      if previous_status <> 'suspended' then
        raise exception 'PUBLICATION_RESTORE_STATE_INVALID' using errcode = 'PT409';
      end if;
      next_status := 'published';
    elsif action = 'publication.archive' then
      if exists (
        select 1
        from public.pachanga_competition_registration_requests requests
        where requests.publication_id = publication_row.id
          and requests.status in ('submitted', 'under_review', 'waitlisted')
      ) then
        raise exception 'PUBLICATION_ACTIVE_REGISTRATION_REQUESTS'
          using errcode = 'PT409';
      end if;
      next_status := 'archived';
    elsif publication_row.organizer_verified then
      raise exception 'PUBLICATION_ORGANIZER_ALREADY_VERIFIED' using errcode = 'PT409';
    end if;

    if action in (
      'publication.reject', 'publication.request_changes',
      'publication.suspend', 'publication.archive'
    ) and length(public_reason_value) < 3 then
      raise exception 'PUBLICATION_PUBLIC_REASON_REQUIRED' using errcode = '22023';
    end if;
    if public_reason_value = '' then
      public_reason_value := case action
        when 'publication.approve' then 'Publicación aprobada.'
        when 'publication.publish' then 'Competición publicada.'
        when 'publication.restore' then 'Publicación restaurada.'
        when 'publication.organizer.verify' then 'Organizador verificado por la plataforma.'
        else public_reason_value end;
    end if;

    sequence_value := nextval('private.pachanga_competition_sequence');
    update public.pachanga_competition_publications publications set
      lifecycle_status = next_status,
      organizer_verified = case when action = 'publication.organizer.verify'
        then true else publications.organizer_verified end,
      approved_at = case when action = 'publication.approve'
        then confirmed_at when action in ('publication.reject', 'publication.request_changes')
        then null else publications.approved_at end,
      published_at = case when action in ('publication.publish', 'publication.restore')
        then confirmed_at when action in (
          'publication.reject', 'publication.request_changes',
          'publication.suspend', 'publication.archive'
        ) then null else publications.published_at end,
      suspended_at = case when action = 'publication.suspend'
        then confirmed_at when action = 'publication.restore' then null
        else publications.suspended_at end,
      archived_at = case when action = 'publication.archive'
        then confirmed_at else publications.archived_at end,
      revision = publications.revision + 1,
      server_sequence = sequence_value,
      updated_by = actor_id,
      updated_at = confirmed_at
    where publications.id = publication_row.id
    returning * into publication_row;

    insert into public.pachanga_competition_publication_reviews(
      publication_id, competition_id, review_action, from_status, to_status,
      public_reason, private_reason, actor_id, operation_id,
      server_sequence, created_at
    ) values (
      publication_row.id, competition_row.id, review_action_value,
      previous_status, publication_row.lifecycle_status, public_reason_value,
      private_reason_value, actor_id, operation_id, sequence_value, confirmed_at
    );
    perform private.pachanga_public_competition_rebuild_v1(
      competition_row.id, publication_row.server_sequence
    );
    snapshot := private.pachanga_public_competition_publication_snapshot_v1(
      publication_row.id
    );
    after_state := jsonb_build_object(
      'status', publication_row.lifecycle_status,
      'organizerVerified', publication_row.organizer_verified,
      'revision', publication_row.revision,
      'contentFingerprint', publication_row.content_fingerprint
    );
    response := private.pachanga_competition_store_command_v1(
      operation_id, actor_id, actor_kind, action, 'competition_publication',
      publication_row.id, competition_row.id, competition_row.organizer_group_id,
      publication_row.revision, publication_row.server_sequence,
      reason_code_value, request_hash, metadata,
      jsonb_build_object(
        'publicationId', publication_row.id,
        'status', publication_row.lifecycle_status,
        'organizerVerified', publication_row.organizer_verified,
        'publicReason', public_reason_value
      ), snapshot, confirmed_at
    );
    perform private.pachanga_public_competition_notify_organizer_v1(
      competition_row.id,
      case action
        when 'publication.approve' then 'competition_publication_approved'
        when 'publication.reject' then 'competition_publication_rejected'
        when 'publication.request_changes' then 'competition_publication_changes_requested'
        when 'publication.publish' then 'competition_published'
        when 'publication.suspend' then 'competition_publication_suspended'
        when 'publication.restore' then 'competition_publication_restored'
        when 'publication.archive' then 'competition_publication_archived'
        else 'competition_organizer_verified' end,
      case action
        when 'publication.publish' then 'Competición publicada'
        when 'publication.suspend' then 'Publicación suspendida'
        when 'publication.request_changes' then 'Cambios solicitados'
        else 'Revisión de competición actualizada' end,
      public_reason_value,
      '/competiciones/' || publication_row.slug,
      jsonb_build_object(
        'competitionId', competition_row.id,
        'publicationId', publication_row.id,
        'status', publication_row.lifecycle_status
      ),
      'competition-publication:' || publication_row.id::text || ':'
        || publication_row.revision::text
    );
  end if;

  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response
  ) values (
    operation_id, actor_id, actor_role, action,
    case when action like 'report.%' then 'competition_report'
      else 'competition_publication' end,
    aggregate_id::text, reason_code_value, coalesce(before_state, '{}'::jsonb),
    coalesce(after_state, '{}'::jsonb), response
  );
  return response;
exception
  when unique_violation then
    raise exception 'PUBLIC_COMPETITION_MODERATION_CONFLICT' using errcode = 'PT409';
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'INVALID_PUBLIC_COMPETITION_MODERATION_COMMAND' using errcode = '22023';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function private.pachanga_public_competition_rate_limit_v1(
  target_actor_id uuid,
  target_operation_id uuid,
  target_action text,
  target_scope_key text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare maximum_events integer;
declare window_length interval;
declare event_count integer;
begin
  maximum_events := case target_action
    when 'registration.submit' then 10
    when 'registration.withdraw' then 20
    when 'registration.message.update' then 20
    when 'publication.slug.update' then 5
    when 'publication.submit' then 10
    when 'publication.unpublish' then 10
    when 'competition.report' then 10
    else 60 end;
  window_length := case when target_action in ('registration.submit', 'competition.report')
    then interval '1 day' else interval '1 hour' end;
  perform pg_advisory_xact_lock(hashtextextended(
    target_actor_id::text || ':' || target_action || ':' || target_scope_key, 91701
  ));
  select count(*)::integer into event_count
  from private.pachanga_public_competition_rate_limit_events events
  where events.actor_id = target_actor_id
    and events.action = target_action
    and events.scope_key = target_scope_key
    and events.created_at >= clock_timestamp() - window_length;
  if event_count >= maximum_events then
    raise exception 'PUBLIC_COMPETITION_RATE_LIMITED' using errcode = 'PT429';
  end if;
  insert into private.pachanga_public_competition_rate_limit_events(
    actor_id, operation_id, action, scope_key
  ) values (
    target_actor_id, target_operation_id, target_action, left(target_scope_key, 180)
  );
end;
$$;

create or replace function private.pachanga_public_competition_slug_v1(target_value text)
returns text
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare normalized text;
begin
  normalized := lower(trim(coalesce(target_value, '')));
  if normalized !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
     or length(normalized) not between 3 and 80 then
    raise exception 'PUBLIC_COMPETITION_SLUG_INVALID' using errcode = '22023';
  end if;
  if normalized = any(array[
    'admin', 'api', 'avisos', 'clubes', 'competicion', 'competiciones',
    'demo', 'equipo', 'login', 'mercado', 'partido', 'perfil', 'privacidad',
    'public', 'registro', 'robots', 'sitemap', 'soporte', 'supabase'
  ]) then raise exception 'PUBLIC_COMPETITION_SLUG_RESERVED' using errcode = '22023'; end if;
  return normalized;
end;
$$;

create or replace function private.pachanga_public_competition_profile_v1(target_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare source jsonb := coalesce(target_value, '{}'::jsonb);
declare result jsonb;
begin
  if jsonb_typeof(source) <> 'object' then
    raise exception 'PUBLIC_COMPETITION_PROFILE_INVALID' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(source) keys(key)
    where keys.key not in (
      'name', 'description', 'imageUrl', 'municipality', 'generalArea',
      'format', 'badge', 'rulesSummary', 'publicVenue'
    )) then raise exception 'PUBLIC_COMPETITION_PROFILE_FIELD_FORBIDDEN' using errcode = '22023'; end if;
  result := jsonb_strip_nulls(jsonb_build_object(
    'name', nullif(left(trim(coalesce(source ->> 'name', '')), 120), ''),
    'description', nullif(left(trim(coalesce(source ->> 'description', '')), 2400), ''),
    'imageUrl', nullif(left(trim(coalesce(source ->> 'imageUrl', '')), 2048), ''),
    'municipality', nullif(left(trim(coalesce(source ->> 'municipality', '')), 120), ''),
    'generalArea', nullif(left(trim(coalesce(source ->> 'generalArea', '')), 160), ''),
    'format', nullif(left(trim(coalesce(source ->> 'format', '')), 120), ''),
    'badge', case when upper(trim(coalesce(source ->> 'badge', ''))) in ('BETA', 'OFFICIAL')
      then upper(trim(source ->> 'badge')) else null end,
    'rulesSummary', nullif(left(trim(coalesce(source ->> 'rulesSummary', '')), 1000), ''),
    'publicVenue', nullif(left(trim(coalesce(source ->> 'publicVenue', '')), 240), '')
  ));
  if result ? 'imageUrl' and result ->> 'imageUrl' !~ '^https://[^[:space:]]+$' then
    raise exception 'PUBLIC_COMPETITION_IMAGE_URL_INVALID' using errcode = '22023';
  end if;
  return result;
end;
$$;

create or replace function private.pachanga_public_competition_sections_v1(target_value jsonb)
returns jsonb
language plpgsql
immutable
set search_path = pg_catalog
as $$
declare source jsonb := coalesce(target_value, '{}'::jsonb);
begin
  if jsonb_typeof(source) <> 'object' then
    raise exception 'PUBLIC_COMPETITION_SECTIONS_INVALID' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(source) keys(key)
    where keys.key not in (
      'teams', 'calendar', 'results', 'standings', 'bracket',
      'referees', 'venueDetail', 'discipline'
    )) then raise exception 'PUBLIC_COMPETITION_SECTION_FORBIDDEN' using errcode = '22023'; end if;
  if source ? 'discipline' and coalesce((source ->> 'discipline')::boolean, false) then
    raise exception 'PUBLIC_COMPETITION_DISCIPLINE_DISABLED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'teams', coalesce((source ->> 'teams')::boolean, true),
    'calendar', coalesce((source ->> 'calendar')::boolean, true),
    'results', coalesce((source ->> 'results')::boolean, true),
    'standings', coalesce((source ->> 'standings')::boolean, true),
    'bracket', coalesce((source ->> 'bracket')::boolean, true),
    'referees', coalesce((source ->> 'referees')::boolean, false),
    'venueDetail', coalesce((source ->> 'venueDetail')::boolean, false),
    'discipline', false
  );
exception when invalid_text_representation then
  raise exception 'PUBLIC_COMPETITION_SECTIONS_INVALID' using errcode = '22023';
end;
$$;

create or replace function private.pachanga_public_competition_fingerprint_v1(
  target_competition_id uuid,
  target_edition_id uuid,
  target_category_id uuid,
  target_slug text,
  target_visibility text,
  target_profile jsonb,
  target_sections jsonb
)
returns text
language sql
immutable
strict
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'competitionId', target_competition_id,
    'editionId', target_edition_id,
    'categoryId', target_category_id,
    'slug', target_slug,
    'visibility', target_visibility,
    'profile', target_profile,
    'sections', target_sections
  )::text, 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function private.pachanga_public_competition_team_snapshot_v1(target_team_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'teamId', teams.id,
    'name', teams.name,
    'teamCode', teams.team_code,
    'shield', case when versions.id is null then null else jsonb_build_object(
      'shape', versions.shape_key,
      'primaryColor', versions.primary_color_key,
      'secondaryColor', versions.secondary_color_key,
      'pattern', versions.pattern_key,
      'border', versions.border_key,
      'symbol', versions.symbol_key,
      'adornment', versions.adornment_key,
      'palette', versions.palette_key,
      'effect', versions.effect_key,
      'initials', versions.initials,
      'version', versions.version_number
    ) end
  ))
  from public.pachanga_groups teams
  left join public.pachanga_team_crest_state state on state.group_id = teams.id
  left join public.pachanga_team_crest_versions versions on versions.id = state.published_version_id
  where teams.id = target_team_id;
$$;

create or replace function private.pachanga_public_competition_capacity_v1(
  target_edition_id uuid,
  target_category_id uuid,
  lock_scope boolean default false
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare edition_row public.pachanga_competition_editions%rowtype;
declare category_row public.pachanga_competition_categories%rowtype;
declare rule_row public.pachanga_competition_rule_revisions%rowtype;
declare capacity_value integer;
declare accepted_value integer;
begin
  if lock_scope then
    perform pg_advisory_xact_lock(hashtextextended(
      target_edition_id::text || ':' || target_category_id::text, 91702
    ));
  end if;
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = target_edition_id;
  select * into category_row from public.pachanga_competition_categories categories
  where categories.id = target_category_id and categories.edition_id = target_edition_id;
  if edition_row.id is null or category_row.id is null then
    raise exception 'COMPETITION_REGISTRATION_SCOPE_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into rule_row from public.pachanga_competition_rule_revisions revisions
  where revisions.id = coalesce(edition_row.registration_rule_revision_id,
    edition_row.rule_revision_id, category_row.rule_revision_id);
  capacity_value := nullif(rule_row.rule_document #>>
    '{registration,registrationPolicy,teamLimits,maximum}', '')::integer;
  select count(*)::integer into accepted_value
  from public.pachanga_competition_entries entries
  where entries.edition_id = target_edition_id
    and entries.category_id = target_category_id
    and entries.status in ('accepted', 'active', 'completed');
  return jsonb_build_object(
    'capacity', capacity_value,
    'accepted', accepted_value,
    'available', case when capacity_value is null then null
      else greatest(capacity_value - accepted_value, 0) end,
    'ruleRevisionId', rule_row.id,
    'editionRevision', edition_row.revision,
    'categoryRevision', category_row.revision,
    'calculatedAt', clock_timestamp()
  );
end;
$$;

create or replace function private.pachanga_public_competition_publication_snapshot_v1(
  target_publication_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kind', 'CompetitionPublicationAuthority',
    'publication', jsonb_build_object(
      'id', publications.id,
      'competitionId', publications.competition_id,
      'editionId', publications.edition_id,
      'categoryId', publications.category_id,
      'slug', publications.slug,
      'visibility', publications.visibility,
      'status', publications.lifecycle_status,
      'publicProfile', publications.public_profile,
      'publicSections', publications.public_sections,
      'contentFingerprint', publications.content_fingerprint,
      'hasCurrentConsent', publications.current_consent_id is not null,
      'organizerVerified', publications.organizer_verified,
      'revision', publications.revision,
      'serverSequence', publications.server_sequence,
      'submittedAt', publications.submitted_at,
      'approvedAt', publications.approved_at,
      'publishedAt', publications.published_at,
      'suspendedAt', publications.suspended_at,
      'archivedAt', publications.archived_at,
      'updatedAt', publications.updated_at
    ),
    'competition', private.pachanga_competition_snapshot_v1(publications.competition_id),
    'publicReadModel', models.public_snapshot,
    'flags', private.pachanga_public_competition_flags_v1()
  ))
  from public.pachanga_competition_publications publications
  left join public.pachanga_public_competition_read_models models
    on models.publication_id = publications.id
  where publications.id = target_publication_id;
$$;

create or replace function private.pachanga_public_competition_request_snapshot_v1(
  target_request_id uuid,
  include_private_reason boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'kind', 'CompetitionRegistrationRequest',
    'id', requests.id,
    'publicationId', requests.publication_id,
    'competitionId', requests.competition_id,
    'editionId', requests.edition_id,
    'categoryId', requests.category_id,
    'teamId', requests.team_id,
    'team', requests.team_snapshot,
    'status', requests.status,
    'message', requests.message,
    'capacityAtRequest', requests.capacity_snapshot,
    'ruleRevisionId', requests.rule_revision_id,
    'entryId', requests.entry_id,
    'waitlistPosition', requests.waitlist_position,
    'reasonCode', requests.reason_code,
    'publicReason', requests.public_reason,
    'privateReason', case when include_private_reason then requests.private_reason else null end,
    'revision', requests.revision,
    'serverSequence', requests.server_sequence,
    'submittedAt', requests.submitted_at,
    'reviewedAt', requests.reviewed_at,
    'acceptedAt', requests.accepted_at,
    'rejectedAt', requests.rejected_at,
    'waitlistedAt', requests.waitlisted_at,
    'withdrawnAt', requests.withdrawn_at,
    'updatedAt', requests.updated_at
  ))
  from public.pachanga_competition_registration_requests requests
  where requests.id = target_request_id;
$$;

create or replace function private.pachanga_public_competition_append_request_revision_v1(
  target_request_id uuid,
  target_actor_id uuid,
  target_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare request_row public.pachanga_competition_registration_requests%rowtype;
begin
  select * into request_row from public.pachanga_competition_registration_requests requests
  where requests.id = target_request_id;
  if not found then raise exception 'REGISTRATION_REQUEST_NOT_FOUND' using errcode = 'P0002'; end if;
  insert into public.pachanga_competition_registration_request_revisions(
    request_id, request_revision, status, message_snapshot, waitlist_position,
    reason_code, public_reason, private_reason, actor_id, operation_id,
    server_sequence, effective_at, created_at
  ) values (
    request_row.id, request_row.revision, request_row.status,
    request_row.message, request_row.waitlist_position, request_row.reason_code,
    request_row.public_reason, request_row.private_reason, target_actor_id,
    target_operation_id, request_row.server_sequence, clock_timestamp(), clock_timestamp()
  );
end;
$$;

create or replace function private.pachanga_public_competition_notify_organizer_v1(
  target_competition_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_dedupe_key text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare recipient record;
declare delivered integer := 0;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  for recipient in
    select distinct source.user_id from (
      select groups.owner_id as user_id
      from public.pachanga_groups groups
      where competition_row.organizer_kind = 'TEAM'
        and groups.id = competition_row.organizer_group_id
      union all
      select clubs.primary_owner_id
      from public.pachanga_clubs clubs
      where competition_row.organizer_kind = 'CLUB'
        and clubs.id = competition_row.organizer_club_id
      union all
      select memberships.user_id
      from public.pachanga_club_memberships memberships
      where competition_row.organizer_kind = 'CLUB'
        and memberships.club_id = competition_row.organizer_club_id
        and memberships.status = 'active'
        and memberships.role in ('club_owner', 'club_admin', 'club_competition_manager')
      union all
      select assignments.user_id
      from public.pachanga_competition_staff_assignments assignments
      where assignments.competition_id = target_competition_id
        and assignments.status = 'active'
        and assignments.staff_role in (
          'competition_owner', 'competition_director', 'competition_admin',
          'competition_registration_manager'
        )
    ) source where source.user_id is not null
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, target_kind, target_title, target_body,
      target_action_url, target_payload,
      target_dedupe_key || ':' || recipient.user_id::text
    );
    delivered := delivered + 1;
  end loop;
  return delivered;
end;
$$;

create or replace function public.command_pachanga_competition_publication_v1(
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
declare actor_kind text := 'authenticated';
declare action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare metadata jsonb;
declare request_hash text;
declare replay jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare competition_row public.pachanga_competitions%rowtype;
declare publication_row public.pachanga_competition_publications%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare category_row public.pachanga_competition_categories%rowtype;
declare consent_row public.pachanga_competition_publication_consents%rowtype;
declare selected_edition_id uuid;
declare selected_category_id uuid;
declare selected_slug text;
declare selected_visibility text;
declare selected_profile jsonb;
declare selected_sections jsonb;
declare fingerprint_value text;
declare reason_code_value text;
declare previous_status text;
declare next_status text;
declare next_revision bigint;
declare consent_number_value integer;
declare statements_value jsonb;
declare snapshot jsonb;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_PUBLICATION_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if action not in (
    'publication.prepare', 'publication.update', 'publication.consent',
    'publication.submit', 'publication.withdraw', 'publication.unpublish',
    'registration.configure'
  ) then raise exception 'PUBLICATION_ACTION_INVALID' using errcode = '22023'; end if;
  perform private.pachanga_public_competition_assert_feature_v1('foundation');
  perform private.pachanga_public_competition_assert_feature_v1('publication');

  metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91703));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;

  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = aggregate_id for update;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  if not private.pachanga_competition_can_v1(competition_row.id, actor_id, 'manage') then
    raise exception 'COMPETITION_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  reason_code_value := left(coalesce(nullif(trim(payload ->> 'reason'), ''), action), 120);

  select * into publication_row
  from public.pachanga_competition_publications publications
  where publications.competition_id = competition_row.id for update;

  if action = 'publication.prepare' then
    if publication_row.id is not null then
      raise exception 'PUBLICATION_ALREADY_EXISTS' using errcode = 'PT409';
    end if;
    if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if exists (select 1 from jsonb_object_keys(payload) keys(key) where keys.key not in (
      'editionId', 'categoryId', 'slug', 'visibility', 'publicProfile',
      'publicSections', 'reason'
    )) then raise exception 'PUBLICATION_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023'; end if;
    selected_edition_id := (payload ->> 'editionId')::uuid;
    selected_category_id := (payload ->> 'categoryId')::uuid;
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = selected_edition_id and editions.competition_id = competition_row.id;
    select * into category_row from public.pachanga_competition_categories categories
    where categories.id = selected_category_id and categories.edition_id = selected_edition_id;
    if edition_row.id is null or category_row.id is null then
      raise exception 'PUBLICATION_SCOPE_NOT_FOUND' using errcode = 'P0002';
    end if;
    selected_slug := private.pachanga_public_competition_slug_v1(payload ->> 'slug');
    selected_visibility := lower(trim(coalesce(payload ->> 'visibility', 'private')));
    if selected_visibility not in ('private', 'unlisted', 'public') then
      raise exception 'PUBLICATION_VISIBILITY_INVALID' using errcode = '22023';
    end if;
    selected_profile := private.pachanga_public_competition_profile_v1(payload -> 'publicProfile');
    selected_sections := private.pachanga_public_competition_sections_v1(payload -> 'publicSections');
    fingerprint_value := private.pachanga_public_competition_fingerprint_v1(
      competition_row.id, edition_row.id, category_row.id, selected_slug,
      selected_visibility, selected_profile, selected_sections
    );
    sequence_value := nextval('private.pachanga_competition_sequence');
    insert into public.pachanga_competition_publications(
      competition_id, edition_id, category_id, slug, visibility,
      lifecycle_status, public_profile, public_sections, content_fingerprint,
      revision, server_sequence, created_by, updated_by, created_at, updated_at
    ) values (
      competition_row.id, edition_row.id, category_row.id, selected_slug,
      selected_visibility, 'draft', selected_profile, selected_sections,
      fingerprint_value, 1, sequence_value, actor_id, actor_id,
      confirmed_at, confirmed_at
    ) returning * into publication_row;
    update public.pachanga_competitions competitions set
      visibility = case when selected_visibility = 'private' then 'private' else selected_visibility end,
      revision = competitions.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where competitions.id = competition_row.id;
  else
    if publication_row.id is null then raise exception 'PUBLICATION_NOT_FOUND' using errcode = 'P0002'; end if;
    if publication_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if publication_row.lifecycle_status = 'archived' then
      raise exception 'PUBLICATION_ARCHIVED' using errcode = 'PT409';
    end if;

    if action = 'publication.update' then
      if publication_row.lifecycle_status = 'suspended' then
        raise exception 'PUBLICATION_SUSPENDED' using errcode = '42501';
      end if;
      if exists (select 1 from jsonb_object_keys(payload) keys(key) where keys.key not in (
        'editionId', 'categoryId', 'slug', 'visibility', 'publicProfile',
        'publicSections', 'reason'
      )) then raise exception 'PUBLICATION_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023'; end if;
      selected_edition_id := coalesce(nullif(payload ->> 'editionId', '')::uuid, publication_row.edition_id);
      selected_category_id := coalesce(nullif(payload ->> 'categoryId', '')::uuid, publication_row.category_id);
      select * into edition_row from public.pachanga_competition_editions editions
      where editions.id = selected_edition_id and editions.competition_id = competition_row.id;
      select * into category_row from public.pachanga_competition_categories categories
      where categories.id = selected_category_id and categories.edition_id = selected_edition_id;
      if edition_row.id is null or category_row.id is null then
        raise exception 'PUBLICATION_SCOPE_NOT_FOUND' using errcode = 'P0002';
      end if;
      selected_slug := case when payload ? 'slug'
        then private.pachanga_public_competition_slug_v1(payload ->> 'slug')
        else publication_row.slug end;
      if selected_slug <> publication_row.slug then
        perform private.pachanga_public_competition_rate_limit_v1(
          actor_id, operation_id, 'publication.slug.update', competition_row.id::text
        );
      end if;
      selected_visibility := case when payload ? 'visibility'
        then lower(trim(payload ->> 'visibility')) else publication_row.visibility end;
      if selected_visibility not in ('private', 'unlisted', 'public') then
        raise exception 'PUBLICATION_VISIBILITY_INVALID' using errcode = '22023';
      end if;
      selected_profile := case when payload ? 'publicProfile'
        then private.pachanga_public_competition_profile_v1(payload -> 'publicProfile')
        else publication_row.public_profile end;
      selected_sections := case when payload ? 'publicSections'
        then private.pachanga_public_competition_sections_v1(payload -> 'publicSections')
        else publication_row.public_sections end;
      fingerprint_value := private.pachanga_public_competition_fingerprint_v1(
        competition_row.id, edition_row.id, category_row.id, selected_slug,
        selected_visibility, selected_profile, selected_sections
      );
      if fingerprint_value = publication_row.content_fingerprint then
        raise exception 'PUBLICATION_NOT_CHANGED' using errcode = 'PT409';
      end if;
      previous_status := publication_row.lifecycle_status;
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_publication_consents consents set status = 'obsolete'
      where consents.id = publication_row.current_consent_id and consents.status = 'current';
      update public.pachanga_competition_publications publications set
        edition_id = edition_row.id,
        category_id = category_row.id,
        slug = selected_slug,
        visibility = selected_visibility,
        lifecycle_status = 'draft',
        public_profile = selected_profile,
        public_sections = selected_sections,
        content_fingerprint = fingerprint_value,
        current_consent_id = null,
        revision = publications.revision + 1,
        server_sequence = sequence_value,
        submitted_at = null,
        approved_at = null,
        published_at = null,
        updated_by = actor_id,
        updated_at = confirmed_at
      where publications.id = publication_row.id
      returning * into publication_row;
      update public.pachanga_competitions competitions set
        visibility = case when selected_visibility = 'private' then 'private' else selected_visibility end,
        revision = competitions.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where competitions.id = competition_row.id;
      if previous_status in ('pending_review', 'approved', 'published') then
        insert into public.pachanga_competition_publication_reviews(
          publication_id, competition_id, review_action, from_status, to_status,
          public_reason, actor_id, operation_id, server_sequence, created_at
        ) values (
          publication_row.id, competition_row.id,
          case when previous_status = 'published' then 'UNPUBLISH' else 'WITHDRAW' end,
          previous_status, 'draft', 'El contenido público ha cambiado y requiere nueva revisión.',
          actor_id, operation_id, sequence_value, confirmed_at
        );
      end if;

    elsif action = 'publication.consent' then
      if publication_row.lifecycle_status not in ('draft', 'rejected', 'changes_requested') then
        raise exception 'PUBLICATION_CONSENT_STATE_INVALID' using errcode = 'PT409';
      end if;
      if exists (select 1 from jsonb_object_keys(payload) keys(key)
        where keys.key not in ('statements', 'purpose', 'reason')) then
        raise exception 'PUBLICATION_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023';
      end if;
      statements_value := coalesce(payload -> 'statements', '{}'::jsonb);
      if jsonb_typeof(statements_value) <> 'object'
         or exists (select 1 from jsonb_object_keys(statements_value) keys(key)
           where keys.key not in (
             'authorizedRepresentative', 'informationAccurate',
             'teamAssetsAuthorized', 'indexingAccepted'
           ))
         or not coalesce((statements_value ->> 'authorizedRepresentative')::boolean, false)
         or not coalesce((statements_value ->> 'informationAccurate')::boolean, false)
         or not coalesce((statements_value ->> 'teamAssetsAuthorized')::boolean, false)
         or not coalesce((statements_value ->> 'indexingAccepted')::boolean, false) then
        raise exception 'PUBLICATION_CONSENT_INCOMPLETE' using errcode = '22023';
      end if;
      select coalesce(max(consents.consent_number), 0) + 1 into consent_number_value
      from public.pachanga_competition_publication_consents consents
      where consents.publication_id = publication_row.id;
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_publication_consents consents set status = 'obsolete'
      where consents.publication_id = publication_row.id and consents.status = 'current';
      insert into public.pachanga_competition_publication_consents(
        publication_id, competition_id, consent_version, consent_number,
        content_fingerprint, purpose, statements, public_sections_snapshot,
        status, actor_id, operation_id, revision, server_sequence,
        confirmed_at, created_at
      ) values (
        publication_row.id, competition_row.id, 'public-competition-consent.v1',
        consent_number_value, publication_row.content_fingerprint,
        left(coalesce(nullif(trim(payload ->> 'purpose'), ''),
          'Publicar la competición y sus secciones consentidas.'), 500),
        statements_value, publication_row.public_sections, 'current', actor_id,
        operation_id, 1, sequence_value, confirmed_at, confirmed_at
      ) returning * into consent_row;
      update public.pachanga_competition_publications publications set
        current_consent_id = consent_row.id,
        revision = publications.revision + 1,
        server_sequence = sequence_value,
        updated_by = actor_id,
        updated_at = confirmed_at
      where publications.id = publication_row.id
      returning * into publication_row;

    elsif action = 'publication.submit' then
      if exists (select 1 from jsonb_object_keys(payload) keys(key)
        where keys.key not in ('reason')) then
        raise exception 'PUBLICATION_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023';
      end if;
      if publication_row.lifecycle_status not in ('draft', 'rejected', 'changes_requested') then
        raise exception 'PUBLICATION_SUBMIT_STATE_INVALID' using errcode = 'PT409';
      end if;
      select * into consent_row
      from public.pachanga_competition_publication_consents consents
      where consents.id = publication_row.current_consent_id
        and consents.status = 'current';
      if consent_row.id is null
         or consent_row.content_fingerprint <> publication_row.content_fingerprint then
        raise exception 'PUBLICATION_CURRENT_CONSENT_REQUIRED' using errcode = '42501';
      end if;
      perform private.pachanga_public_competition_rate_limit_v1(
        actor_id, operation_id, action, competition_row.id::text
      );
      previous_status := publication_row.lifecycle_status;
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_publications publications set
        lifecycle_status = 'pending_review',
        revision = publications.revision + 1,
        server_sequence = sequence_value,
        submitted_at = confirmed_at,
        approved_at = null,
        updated_by = actor_id,
        updated_at = confirmed_at
      where publications.id = publication_row.id
      returning * into publication_row;
      insert into public.pachanga_competition_publication_reviews(
        publication_id, competition_id, review_action, from_status, to_status,
        public_reason, actor_id, operation_id, server_sequence, created_at
      ) values (
        publication_row.id, competition_row.id, 'SUBMIT', previous_status,
        'pending_review', 'Publicación enviada a revisión.', actor_id,
        operation_id, sequence_value, confirmed_at
      );

    elsif action = 'publication.withdraw' then
      if publication_row.lifecycle_status <> 'pending_review' then
        raise exception 'PUBLICATION_WITHDRAW_STATE_INVALID' using errcode = 'PT409';
      end if;
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_publications publications set
        lifecycle_status = 'draft',
        revision = publications.revision + 1,
        server_sequence = sequence_value,
        submitted_at = null,
        updated_by = actor_id,
        updated_at = confirmed_at
      where publications.id = publication_row.id
      returning * into publication_row;
      insert into public.pachanga_competition_publication_reviews(
        publication_id, competition_id, review_action, from_status, to_status,
        public_reason, actor_id, operation_id, server_sequence, created_at
      ) values (
        publication_row.id, competition_row.id, 'WITHDRAW', 'pending_review',
        'draft', 'Revisión retirada por el organizador.', actor_id,
        operation_id, sequence_value, confirmed_at
      );

    elsif action = 'publication.unpublish' then
      if publication_row.lifecycle_status <> 'published' then
        raise exception 'PUBLICATION_UNPUBLISH_STATE_INVALID' using errcode = 'PT409';
      end if;
      perform private.pachanga_public_competition_rate_limit_v1(
        actor_id, operation_id, action, competition_row.id::text
      );
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_publications publications set
        lifecycle_status = 'approved',
        revision = publications.revision + 1,
        server_sequence = sequence_value,
        published_at = null,
        updated_by = actor_id,
        updated_at = confirmed_at
      where publications.id = publication_row.id
      returning * into publication_row;
      insert into public.pachanga_competition_publication_reviews(
        publication_id, competition_id, review_action, from_status, to_status,
        public_reason, actor_id, operation_id, server_sequence, created_at
      ) values (
        publication_row.id, competition_row.id, 'UNPUBLISH', 'published',
        'approved', 'Publicación retirada por el organizador.', actor_id,
        operation_id, sequence_value, confirmed_at
      );

    elsif action = 'registration.configure' then
      if exists (select 1 from jsonb_object_keys(payload) keys(key) where keys.key not in (
        'mode', 'opensAt', 'closesAt', 'reason'
      )) then raise exception 'PUBLICATION_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023'; end if;
      select * into edition_row from public.pachanga_competition_editions editions
      where editions.id = publication_row.edition_id for update;
      selected_visibility := upper(trim(coalesce(payload ->> 'mode', '')));
      if selected_visibility not in ('INVITE_ONLY', 'REQUEST_APPROVAL', 'CLOSED') then
        raise exception 'REGISTRATION_MODE_INVALID' using errcode = '22023';
      end if;
      if selected_visibility = 'REQUEST_APPROVAL' then
        perform private.pachanga_public_competition_assert_feature_v1('registration');
        if publication_row.visibility <> 'public' then
          raise exception 'PUBLIC_REGISTRATION_REQUIRES_PUBLIC_VISIBILITY' using errcode = '22023';
        end if;
      end if;
      if selected_visibility = 'REQUEST_APPROVAL'
         and edition_row.status not in ('draft', 'registration_open', 'registration_closed') then
        raise exception 'PUBLIC_REGISTRATION_STATE_INVALID' using errcode = 'PT409';
      end if;
      if nullif(payload ->> 'opensAt', '') is not null
         and nullif(payload ->> 'closesAt', '') is not null
         and (payload ->> 'closesAt')::timestamptz <= (payload ->> 'opensAt')::timestamptz then
        raise exception 'REGISTRATION_WINDOW_INVALID' using errcode = '22023';
      end if;
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_editions editions set
        status = case
          when selected_visibility = 'REQUEST_APPROVAL' then 'registration_open'
          when selected_visibility = 'CLOSED'
            and editions.status in ('draft', 'registration_open', 'registration_closed')
            then 'registration_closed'
          else editions.status
        end,
        registration_mode = selected_visibility,
        registration_opens_at = case when payload ? 'opensAt'
          then nullif(payload ->> 'opensAt', '')::timestamptz else editions.registration_opens_at end,
        registration_closes_at = case when payload ? 'closesAt'
          then nullif(payload ->> 'closesAt', '')::timestamptz else editions.registration_closes_at end,
        registration_closed_at = case when selected_visibility = 'CLOSED'
          then confirmed_at else null end,
        revision = editions.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where editions.id = edition_row.id;
      update public.pachanga_competition_publications publications set
        revision = publications.revision + 1,
        server_sequence = sequence_value,
        updated_by = actor_id,
        updated_at = confirmed_at
      where publications.id = publication_row.id
      returning * into publication_row;
    end if;
  end if;

  perform private.pachanga_public_competition_rebuild_v1(
    competition_row.id, publication_row.server_sequence
  );
  snapshot := private.pachanga_public_competition_publication_snapshot_v1(publication_row.id);
  next_revision := publication_row.revision;
  return private.pachanga_competition_store_command_v1(
    operation_id, actor_id, actor_kind, action, 'competition_publication',
    aggregate_id, competition_row.id, competition_row.organizer_group_id,
    next_revision, publication_row.server_sequence, reason_code_value, request_hash,
    metadata, jsonb_build_object(
      'publicationId', publication_row.id,
      'status', publication_row.lifecycle_status,
      'visibility', publication_row.visibility,
      'contentFingerprint', publication_row.content_fingerprint
    ), snapshot, confirmed_at
  );
exception
  when unique_violation then raise exception 'PUBLICATION_CONFLICT' using errcode = 'PT409';
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'INVALID_PUBLICATION_COMMAND' using errcode = '22023';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

create or replace function public.command_pachanga_competition_registration_request_v1(
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
declare actor_kind text := 'authenticated';
declare action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare metadata jsonb;
declare request_hash text;
declare replay jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare target_sequence bigint;
declare competition_row public.pachanga_competitions%rowtype;
declare publication_row public.pachanga_competition_publications%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare category_row public.pachanga_competition_categories%rowtype;
declare request_row public.pachanga_competition_registration_requests%rowtype;
declare affected_row public.pachanga_competition_registration_requests%rowtype;
declare team_row public.pachanga_groups%rowtype;
declare entry_id_value uuid;
declare roster_id_value uuid;
declare report_reference uuid;
declare capacity_value jsonb;
declare capacity_limit integer;
declare accepted_count integer;
declare selected_team_id uuid;
declare selected_position bigint;
declare current_position bigint;
declare waitlist_count bigint;
declare new_position bigint;
declare reason_code_value text;
declare public_reason_value text;
declare private_reason_value text;
declare snapshot jsonb;
declare include_private boolean := false;
declare notification_title text;
declare notification_body text;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_REGISTRATION_REQUEST_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if action not in (
    'registration.submit', 'registration.message.update', 'registration.withdraw',
    'registration.under_review', 'registration.waitlist', 'registration.accept',
    'registration.reject', 'waitlist.reorder', 'competition.report'
  ) then raise exception 'REGISTRATION_REQUEST_ACTION_INVALID' using errcode = '22023'; end if;
  perform private.pachanga_public_competition_assert_feature_v1('foundation');
  if action <> 'competition.report' then
    perform private.pachanga_public_competition_assert_feature_v1('registration');
  end if;
  metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91704));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  reason_code_value := left(coalesce(nullif(trim(payload ->> 'reason'), ''), action), 120);
  public_reason_value := left(trim(coalesce(payload ->> 'publicReason', '')), 500);
  private_reason_value := left(trim(coalesce(payload ->> 'privateReason', '')), 1200);

  if action in ('registration.submit', 'competition.report') then
    select * into publication_row
    from public.pachanga_competition_publications publications
    where publications.id = aggregate_id for update;
    if not found then raise exception 'PUBLICATION_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into competition_row from public.pachanga_competitions competitions
    where competitions.id = publication_row.competition_id for update;
    if publication_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
  else
    select * into request_row
    from public.pachanga_competition_registration_requests requests
    where requests.id = aggregate_id for update;
    if not found then raise exception 'REGISTRATION_REQUEST_NOT_FOUND' using errcode = 'P0002'; end if;
    if request_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    select * into publication_row
    from public.pachanga_competition_publications publications
    where publications.id = request_row.publication_id for update;
    select * into competition_row from public.pachanga_competitions competitions
    where competitions.id = request_row.competition_id for update;
  end if;

  if action = 'competition.report' then
    if exists (select 1 from jsonb_object_keys(payload) keys(key)
      where keys.key not in ('category', 'summary', 'reason')) then
      raise exception 'REGISTRATION_REQUEST_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023';
    end if;
    if publication_row.visibility not in ('public', 'unlisted')
       or publication_row.lifecycle_status <> 'published' then
      raise exception 'PUBLICATION_NOT_FOUND' using errcode = 'P0002';
    end if;
    perform private.pachanga_public_competition_rate_limit_v1(
      actor_id, operation_id, action, publication_row.id::text
    );
    sequence_value := nextval('private.pachanga_competition_sequence');
    insert into private.pachanga_competition_reports(
      publication_id, competition_id, reporter_user_id, category, summary,
      status, operation_id, revision, server_sequence, created_at, updated_at
    ) values (
      publication_row.id, competition_row.id, actor_id,
      upper(trim(coalesce(payload ->> 'category', 'OTHER'))),
      left(trim(coalesce(payload ->> 'summary', '')), 1000),
      'submitted', operation_id, 1, sequence_value, confirmed_at, confirmed_at
    ) returning opaque_reference into report_reference;
    snapshot := jsonb_build_object(
      'kind', 'CompetitionReportReceipt',
      'opaqueReference', report_reference,
      'status', 'submitted',
      'confirmedAt', confirmed_at
    );
    return private.pachanga_competition_store_command_v1(
      operation_id, actor_id, actor_kind, action, 'competition_report',
      aggregate_id, competition_row.id, competition_row.organizer_group_id,
      1, sequence_value, reason_code_value, request_hash, metadata,
      jsonb_build_object('opaqueReference', report_reference), snapshot, confirmed_at
    );
  end if;

  if action = 'registration.submit' then
    if exists (select 1 from jsonb_object_keys(payload) keys(key)
      where keys.key not in ('teamId', 'message', 'reason')) then
      raise exception 'REGISTRATION_REQUEST_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023';
    end if;
    if publication_row.visibility <> 'public'
       or publication_row.lifecycle_status <> 'published' then
      raise exception 'PUBLIC_REGISTRATION_NOT_AVAILABLE' using errcode = '42501';
    end if;
    select * into edition_row from public.pachanga_competition_editions editions
    where editions.id = publication_row.edition_id for update;
    select * into category_row from public.pachanga_competition_categories categories
    where categories.id = publication_row.category_id for update;
    if edition_row.id is null or category_row.id is null then
      raise exception 'REGISTRATION_SCOPE_NOT_FOUND' using errcode = 'P0002';
    end if;
    if edition_row.registration_mode <> 'REQUEST_APPROVAL'
       or edition_row.status <> 'registration_open'
       or (edition_row.registration_opens_at is not null and confirmed_at < edition_row.registration_opens_at)
       or (edition_row.registration_closes_at is not null and confirmed_at >= edition_row.registration_closes_at) then
      raise exception 'PUBLIC_REGISTRATION_NOT_OPEN' using errcode = '42501';
    end if;
    selected_team_id := (payload ->> 'teamId')::uuid;
    perform private.pachanga_league_assert_team_owner_v1(selected_team_id, actor_id);
    select * into team_row from public.pachanga_groups teams
    where teams.id = selected_team_id for update;
    if not found then raise exception 'TEAM_NOT_FOUND' using errcode = 'P0002'; end if;
    perform pg_advisory_xact_lock(hashtextextended(
      edition_row.id::text || ':' || category_row.id::text || ':' || selected_team_id::text, 91705
    ));
    if exists (
      select 1 from public.pachanga_competition_entries entries
      where entries.edition_id = edition_row.id and entries.category_id = category_row.id
        and entries.team_id = selected_team_id
        and entries.status in ('draft', 'submitted', 'invited', 'accepted', 'active')
    ) then raise exception 'COMPETITION_ENTRY_ALREADY_EXISTS' using errcode = 'PT409'; end if;
    if exists (
      select 1 from public.pachanga_competition_registration_requests requests
      where requests.edition_id = edition_row.id and requests.category_id = category_row.id
        and requests.team_id = selected_team_id
        and requests.status in ('draft', 'submitted', 'under_review', 'waitlisted', 'accepted')
    ) then raise exception 'REGISTRATION_REQUEST_ALREADY_EXISTS' using errcode = 'PT409'; end if;
    perform private.pachanga_public_competition_rate_limit_v1(
      actor_id, operation_id, action, publication_row.id::text
    );
    capacity_value := private.pachanga_public_competition_capacity_v1(
      edition_row.id, category_row.id, false
    );
    sequence_value := nextval('private.pachanga_competition_sequence');
    insert into public.pachanga_competition_registration_requests(
      publication_id, competition_id, edition_id, category_id, team_id,
      requested_by, status, message, team_snapshot, capacity_snapshot,
      rule_revision_id, reason_code, created_operation_id, revision,
      server_sequence, submitted_at, updated_at
    ) values (
      publication_row.id, competition_row.id, edition_row.id, category_row.id,
      selected_team_id, actor_id, 'submitted',
      left(trim(coalesce(payload ->> 'message', '')), 1000),
      private.pachanga_public_competition_team_snapshot_v1(selected_team_id),
      capacity_value,
      coalesce(edition_row.registration_rule_revision_id,
        edition_row.rule_revision_id, category_row.rule_revision_id),
      reason_code_value, operation_id, 1, sequence_value, confirmed_at, confirmed_at
    ) returning * into request_row;
    perform private.pachanga_public_competition_append_request_revision_v1(
      request_row.id, actor_id, operation_id
    );
    perform private.pachanga_public_competition_notify_organizer_v1(
      competition_row.id, 'competition_registration_request',
      'Nueva solicitud de inscripción', team_row.name || ' quiere participar.',
      '/competiciones/' || competition_row.id::text || '/gestion/inscripciones',
      jsonb_build_object('competitionId', competition_row.id, 'requestId', request_row.id),
      'competition-registration-request:' || request_row.id::text
    );
  else
    select * into team_row from public.pachanga_groups teams
    where teams.id = request_row.team_id;
    include_private := private.pachanga_competition_can_v1(
      competition_row.id, actor_id, 'entries_manage'
    );

    if action in ('registration.message.update', 'registration.withdraw') then
      perform private.pachanga_league_assert_team_owner_v1(request_row.team_id, actor_id);
    else
      if not include_private then
        raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501';
      end if;
    end if;

    if action = 'registration.message.update' then
      if exists (select 1 from jsonb_object_keys(payload) keys(key)
        where keys.key not in ('message', 'reason')) then
        raise exception 'REGISTRATION_REQUEST_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023';
      end if;
      if request_row.status not in ('submitted', 'under_review', 'waitlisted') then
        raise exception 'REGISTRATION_REQUEST_MESSAGE_LOCKED' using errcode = 'PT409';
      end if;
      perform private.pachanga_public_competition_rate_limit_v1(
        actor_id, operation_id, action, request_row.id::text
      );
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_registration_requests requests set
        message = left(trim(coalesce(payload ->> 'message', '')), 1000),
        reason_code = reason_code_value,
        revision = requests.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where requests.id = request_row.id returning * into request_row;
      perform private.pachanga_public_competition_append_request_revision_v1(
        request_row.id, actor_id, operation_id
      );

    elsif action = 'registration.withdraw' then
      if request_row.status = 'accepted' then
        raise exception 'COMPETITION_ENTRY_WITHDRAWAL_REQUIRED' using errcode = '0A000';
      end if;
      if request_row.status not in ('submitted', 'under_review', 'waitlisted') then
        raise exception 'REGISTRATION_REQUEST_WITHDRAW_STATE_INVALID' using errcode = 'PT409';
      end if;
      perform private.pachanga_public_competition_rate_limit_v1(
        actor_id, operation_id, action, request_row.id::text
      );
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_registration_requests requests set
        status = 'withdrawn', waitlist_position = null,
        reason_code = reason_code_value, withdrawn_at = confirmed_at,
        revision = requests.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where requests.id = request_row.id returning * into request_row;
      perform private.pachanga_public_competition_append_request_revision_v1(
        request_row.id, actor_id, operation_id
      );
      perform private.pachanga_public_competition_notify_organizer_v1(
        competition_row.id, 'competition_registration_withdrawn',
        'Solicitud retirada', team_row.name || ' ha retirado su solicitud.',
        '/competiciones/' || competition_row.id::text || '/gestion/inscripciones',
        jsonb_build_object('competitionId', competition_row.id, 'requestId', request_row.id),
        'competition-registration-withdrawn:' || request_row.id::text || ':' || request_row.revision::text
      );

    elsif action = 'registration.under_review' then
      if request_row.status <> 'submitted' then
        raise exception 'REGISTRATION_REVIEW_STATE_INVALID' using errcode = 'PT409';
      end if;
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_registration_requests requests set
        status = 'under_review', reason_code = reason_code_value, reviewed_at = confirmed_at,
        revision = requests.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where requests.id = request_row.id returning * into request_row;
      perform private.pachanga_public_competition_append_request_revision_v1(
        request_row.id, actor_id, operation_id
      );

    elsif action = 'registration.waitlist' then
      perform private.pachanga_public_competition_assert_feature_v1('waitlist');
      if request_row.status not in ('submitted', 'under_review') then
        raise exception 'REGISTRATION_WAITLIST_STATE_INVALID' using errcode = 'PT409';
      end if;
      perform pg_advisory_xact_lock(hashtextextended(
        request_row.edition_id::text || ':' || request_row.category_id::text, 91706
      ));
      select coalesce(max(requests.waitlist_position), 0) + 1 into selected_position
      from public.pachanga_competition_registration_requests requests
      where requests.edition_id = request_row.edition_id
        and requests.category_id = request_row.category_id
        and requests.status = 'waitlisted';
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_registration_requests requests set
        status = 'waitlisted', waitlist_position = selected_position,
        reason_code = reason_code_value, public_reason = public_reason_value,
        private_reason = private_reason_value, reviewed_at = confirmed_at,
        waitlisted_at = confirmed_at, revision = requests.revision + 1,
        server_sequence = sequence_value, updated_at = confirmed_at
      where requests.id = request_row.id returning * into request_row;
      perform private.pachanga_public_competition_append_request_revision_v1(
        request_row.id, actor_id, operation_id
      );
      perform private.pachanga_notify_v1(
        team_row.owner_id, 'competition_registration_waitlisted',
        'Solicitud en lista de espera', 'Tu equipo está en la lista de espera.',
        '/competiciones/' || publication_row.slug,
        jsonb_build_object('competitionId', competition_row.id, 'requestId', request_row.id),
        'competition-registration-waitlisted:' || request_row.id::text || ':' || request_row.revision::text
      );

    elsif action = 'waitlist.reorder' then
      perform private.pachanga_public_competition_assert_feature_v1('waitlist');
      if request_row.status <> 'waitlisted' then
        raise exception 'REGISTRATION_WAITLIST_STATE_INVALID' using errcode = 'PT409';
      end if;
      if exists (select 1 from jsonb_object_keys(payload) keys(key)
        where keys.key not in ('position', 'reason', 'privateReason')) then
        raise exception 'REGISTRATION_REQUEST_PAYLOAD_FIELD_FORBIDDEN' using errcode = '22023';
      end if;
      perform pg_advisory_xact_lock(hashtextextended(
        request_row.edition_id::text || ':' || request_row.category_id::text, 91706
      ));
      select count(*)::bigint into waitlist_count
      from public.pachanga_competition_registration_requests requests
      where requests.edition_id = request_row.edition_id
        and requests.category_id = request_row.category_id
        and requests.status = 'waitlisted';
      selected_position := (payload ->> 'position')::bigint;
      current_position := request_row.waitlist_position;
      if selected_position < 1 or selected_position > waitlist_count then
        raise exception 'WAITLIST_POSITION_INVALID' using errcode = '22023';
      end if;
      if selected_position = current_position then
        raise exception 'WAITLIST_POSITION_UNCHANGED' using errcode = 'PT409';
      end if;
      perform 1 from public.pachanga_competition_registration_requests requests
      where requests.edition_id = request_row.edition_id
        and requests.category_id = request_row.category_id
        and requests.status = 'waitlisted' for update;
      update public.pachanga_competition_registration_requests requests
      set waitlist_position = requests.waitlist_position + 1000000
      where requests.edition_id = request_row.edition_id
        and requests.category_id = request_row.category_id
        and requests.status = 'waitlisted';
      for affected_row in
        select requests.*
        from public.pachanga_competition_registration_requests requests
        where requests.edition_id = request_row.edition_id
          and requests.category_id = request_row.category_id
          and requests.status = 'waitlisted'
        order by requests.waitlist_position, requests.id
      loop
        current_position := affected_row.waitlist_position - 1000000;
        new_position := case
          when affected_row.id = request_row.id then selected_position
          when selected_position < request_row.waitlist_position
            and current_position >= selected_position
            and current_position < request_row.waitlist_position then current_position + 1
          when selected_position > request_row.waitlist_position
            and current_position > request_row.waitlist_position
            and current_position <= selected_position then current_position - 1
          else current_position end;
        target_sequence := nextval('private.pachanga_competition_sequence');
        update public.pachanga_competition_registration_requests requests set
          waitlist_position = new_position,
          reason_code = case when requests.id = request_row.id then reason_code_value else requests.reason_code end,
          private_reason = case when requests.id = request_row.id
            then private_reason_value else requests.private_reason end,
          revision = requests.revision + 1,
          server_sequence = target_sequence,
          updated_at = confirmed_at
        where requests.id = affected_row.id returning * into affected_row;
        perform private.pachanga_public_competition_append_request_revision_v1(
          affected_row.id, actor_id, operation_id
        );
        if affected_row.id = request_row.id then request_row := affected_row; end if;
      end loop;
      sequence_value := request_row.server_sequence;

    elsif action = 'registration.accept' then
      if request_row.status not in ('submitted', 'under_review', 'waitlisted') then
        raise exception 'REGISTRATION_ACCEPT_STATE_INVALID' using errcode = 'PT409';
      end if;
      select * into edition_row from public.pachanga_competition_editions editions
      where editions.id = request_row.edition_id for update;
      select * into category_row from public.pachanga_competition_categories categories
      where categories.id = request_row.category_id for update;
      if edition_row.registration_mode <> 'REQUEST_APPROVAL'
         or edition_row.status <> 'registration_open'
         or publication_row.lifecycle_status <> 'published'
         or publication_row.visibility <> 'public'
         or (edition_row.registration_closes_at is not null and confirmed_at >= edition_row.registration_closes_at) then
        raise exception 'PUBLIC_REGISTRATION_NOT_OPEN' using errcode = 'PT409';
      end if;
      capacity_value := private.pachanga_public_competition_capacity_v1(
        request_row.edition_id, request_row.category_id, true
      );
      capacity_limit := nullif(capacity_value ->> 'capacity', '')::integer;
      accepted_count := coalesce((capacity_value ->> 'accepted')::integer, 0);
      if capacity_limit is not null and accepted_count >= capacity_limit then
        raise exception 'COMPETITION_CAPACITY_REACHED' using errcode = 'PT409';
      end if;
      if exists (
        select 1 from public.pachanga_competition_entries entries
        where entries.edition_id = request_row.edition_id
          and entries.category_id = request_row.category_id
          and entries.team_id = request_row.team_id
          and entries.status in ('draft', 'submitted', 'invited', 'accepted', 'active')
      ) then raise exception 'COMPETITION_ENTRY_ALREADY_EXISTS' using errcode = 'PT409'; end if;
      sequence_value := nextval('private.pachanga_competition_sequence');
      entry_id_value := gen_random_uuid();
      insert into public.pachanga_competition_entries(
        id, competition_id, edition_id, category_id, team_id, entry_source,
        status, rule_revision_id, submitted_by, accepted_by, submitted_at,
        accepted_at, reason_code, revision, server_sequence, created_by,
        created_at, updated_at
      ) values (
        entry_id_value, request_row.competition_id, request_row.edition_id,
        request_row.category_id, request_row.team_id, 'PUBLIC_APPLICATION',
        'accepted', request_row.rule_revision_id, request_row.requested_by,
        actor_id, request_row.submitted_at, confirmed_at, reason_code_value, 1,
        sequence_value, coalesce(request_row.requested_by, actor_id),
        confirmed_at, confirmed_at
      );
      if coalesce((select settings.league_rosters_enabled
        from private.pachanga_competition_foundation_settings settings where settings.singleton), false) then
        roster_id_value := private.pachanga_league_create_empty_roster_v1(
          entry_id_value, actor_id, sequence_value, reason_code_value
        );
      end if;
      update public.pachanga_competition_registration_requests requests set
        status = 'accepted', entry_id = entry_id_value, waitlist_position = null,
        reason_code = reason_code_value, public_reason = public_reason_value,
        private_reason = private_reason_value, reviewed_at = confirmed_at,
        accepted_at = confirmed_at, revision = requests.revision + 1,
        server_sequence = sequence_value, updated_at = confirmed_at
      where requests.id = request_row.id returning * into request_row;
      perform private.pachanga_public_competition_append_request_revision_v1(
        request_row.id, actor_id, operation_id
      );
      perform private.pachanga_notify_v1(
        team_row.owner_id, 'competition_registration_accepted',
        'Inscripción aceptada', 'Tu equipo ya forma parte de la competición.',
        '/competiciones/' || publication_row.slug,
        jsonb_build_object(
          'competitionId', competition_row.id, 'requestId', request_row.id,
          'entryId', entry_id_value
        ),
        'competition-registration-accepted:' || request_row.id::text
      );

    elsif action = 'registration.reject' then
      if request_row.status not in ('submitted', 'under_review', 'waitlisted') then
        raise exception 'REGISTRATION_REJECT_STATE_INVALID' using errcode = 'PT409';
      end if;
      if length(public_reason_value) < 3 then
        raise exception 'REGISTRATION_PUBLIC_REASON_REQUIRED' using errcode = '22023';
      end if;
      sequence_value := nextval('private.pachanga_competition_sequence');
      update public.pachanga_competition_registration_requests requests set
        status = 'rejected', waitlist_position = null, reason_code = reason_code_value,
        public_reason = public_reason_value, private_reason = private_reason_value,
        reviewed_at = confirmed_at, rejected_at = confirmed_at,
        revision = requests.revision + 1, server_sequence = sequence_value,
        updated_at = confirmed_at
      where requests.id = request_row.id returning * into request_row;
      perform private.pachanga_public_competition_append_request_revision_v1(
        request_row.id, actor_id, operation_id
      );
      perform private.pachanga_notify_v1(
        team_row.owner_id, 'competition_registration_rejected',
        'Solicitud no aceptada', public_reason_value,
        '/competiciones/' || publication_row.slug,
        jsonb_build_object('competitionId', competition_row.id, 'requestId', request_row.id),
        'competition-registration-rejected:' || request_row.id::text
      );
    end if;
  end if;

  perform private.pachanga_public_competition_rebuild_v1(
    competition_row.id, request_row.server_sequence
  );
  snapshot := private.pachanga_public_competition_request_snapshot_v1(
    request_row.id, include_private
  );
  return private.pachanga_competition_store_command_v1(
    operation_id, actor_id, actor_kind, action, 'competition_registration_request',
    aggregate_id, competition_row.id, competition_row.organizer_group_id,
    request_row.revision, request_row.server_sequence, reason_code_value, request_hash,
    metadata, jsonb_strip_nulls(jsonb_build_object(
      'requestId', request_row.id, 'status', request_row.status,
      'entryId', request_row.entry_id, 'rosterId', roster_id_value,
      'waitlistPosition', request_row.waitlist_position
    )), snapshot, confirmed_at
  );
exception
  when unique_violation then raise exception 'REGISTRATION_REQUEST_CONFLICT' using errcode = 'PT409';
  when check_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'INVALID_REGISTRATION_REQUEST_COMMAND' using errcode = '22023';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function private.pachanga_public_competition_assert_feature_v1(text)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_rate_limit_v1(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_slug_v1(text)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_profile_v1(jsonb)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_sections_v1(jsonb)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_fingerprint_v1(
  uuid, uuid, uuid, text, text, jsonb, jsonb
) from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_team_snapshot_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_capacity_v1(uuid, uuid, boolean)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_publication_snapshot_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_request_snapshot_v1(uuid, boolean)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_append_request_revision_v1(uuid, uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_notify_organizer_v1(
  uuid, text, text, text, text, jsonb, text
) from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_is_organizer_actor_v1(uuid, uuid)
  from public, anon, authenticated;

revoke all on function public.command_pachanga_competition_publication_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
revoke all on function public.command_pachanga_competition_registration_request_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
revoke all on function public.command_pachanga_public_competition_moderation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_competition_publication_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;
grant execute on function public.command_pachanga_competition_registration_request_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;
grant execute on function public.command_pachanga_public_competition_moderation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

comment on function public.command_pachanga_competition_publication_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is 'Organizer publication and registration configuration authority; server decides every confirmed transition.';
comment on function public.command_pachanga_competition_registration_request_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is 'Team registration request, waitlist and atomic Entry authority; no offline or client-side confirmation.';
comment on function public.command_pachanga_public_competition_moderation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is 'Platform-only publication and report moderation authority with self-review prevention and dual audit ledgers.';
