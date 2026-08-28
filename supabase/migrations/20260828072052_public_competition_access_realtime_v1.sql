-- Pachangas IQ Wave 7A: authenticated read access, canonical projection
-- refresh and scoped Realtime invalidations. WAL payloads are never authority.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_public_competition_source_refresh_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare source_row jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
declare competition_id_value uuid;
declare source_sequence bigint;
begin
  if tg_table_name in (
    'pachanga_competition_official_result_decisions',
    'pachanga_competition_match_sheets'
  ) then
    select contexts.competition_id into competition_id_value
    from public.pachanga_competition_match_contexts contexts
    where contexts.id = (source_row ->> 'competition_match_context_id')::uuid;
  elsif tg_table_name = 'pachanga_competition_rule_revisions' then
    select rule_sets.competition_id into competition_id_value
    from public.pachanga_competition_rule_sets rule_sets
    where rule_sets.id = (source_row ->> 'rule_set_id')::uuid;
  else
    competition_id_value := nullif(source_row ->> 'competition_id', '')::uuid;
  end if;
  if competition_id_value is null or not exists (
    select 1 from public.pachanga_competition_publications publications
    where publications.competition_id = competition_id_value
  ) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  source_sequence := coalesce(nullif(source_row ->> 'server_sequence', '')::bigint, 0);
  perform private.pachanga_public_competition_rebuild_v1(
    competition_id_value, source_sequence
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'pachanga_competition_entries',
    'pachanga_competition_editions',
    'pachanga_competition_rule_revisions',
    'pachanga_competition_match_contexts',
    'pachanga_competition_schedule_slots',
    'pachanga_competition_match_sheets',
    'pachanga_competition_official_result_decisions',
    'pachanga_competition_standing_states',
    'pachanga_competition_standing_snapshots',
    'pachanga_tournament_knockout_read_models'
  ] loop
    execute format(
      'drop trigger if exists refresh_public_competition_from_%I_v1 on public.%I',
      target_table, target_table
    );
    execute format(
      'create trigger refresh_public_competition_from_%I_v1 '
      || 'after insert or update or delete on public.%I for each row '
      || 'execute function private.pachanga_public_competition_source_refresh_v1()',
      target_table, target_table
    );
  end loop;
end;
$$;

create or replace function private.pachanga_public_competition_request_invalidation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = new.competition_id;
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    nextval('private.pachanga_competition_sequence'), new.competition_id,
    competition_row.organizer_group_id, competition_row.organizer_club_id,
    new.team_id, new.requested_by, 'competition_registration_request',
    new.id::text, new.revision, clock_timestamp()
  );
  return new;
end;
$$;

drop trigger if exists invalidate_public_competition_registration_request_v1
  on public.pachanga_competition_registration_requests;
create trigger invalidate_public_competition_registration_request_v1
after insert or update on public.pachanga_competition_registration_requests
for each row execute function private.pachanga_public_competition_request_invalidation_v1();

create or replace function private.pachanga_public_competition_place_available_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare publication_row public.pachanga_competition_publications%rowtype;
declare waiting_row public.pachanga_competition_registration_requests%rowtype;
declare team_row public.pachanga_groups%rowtype;
begin
  if tg_op <> 'UPDATE'
     or old.status not in ('accepted', 'active', 'completed')
     or new.status in ('accepted', 'active', 'completed') then
    return new;
  end if;
  select * into publication_row
  from public.pachanga_competition_publications publications
  where publications.competition_id = new.competition_id
    and publications.edition_id = new.edition_id
    and publications.category_id = new.category_id
    and publications.lifecycle_status = 'published';
  if not found then return new; end if;
  select * into waiting_row
  from public.pachanga_competition_registration_requests requests
  where requests.edition_id = new.edition_id
    and requests.category_id = new.category_id
    and requests.status = 'waitlisted'
  order by requests.waitlist_position, requests.server_sequence, requests.id
  limit 1;
  if not found then return new; end if;
  select * into team_row from public.pachanga_groups teams
  where teams.id = waiting_row.team_id;
  if team_row.owner_id is not null then
    perform private.pachanga_notify_v1(
      team_row.owner_id, 'competition_registration_place_available',
      'Hay una plaza disponible',
      'La organización debe confirmar el siguiente paso de la lista de espera.',
      '/competiciones/' || publication_row.slug,
      jsonb_build_object(
        'competitionId', new.competition_id,
        'requestId', waiting_row.id,
        'waitlistPosition', waiting_row.waitlist_position
      ),
      'competition-place-available:' || waiting_row.id::text || ':' || new.revision::text
    );
  end if;
  return new;
end;
$$;

drop trigger if exists notify_public_competition_place_available_v1
  on public.pachanga_competition_entries;
create trigger notify_public_competition_place_available_v1
after update of status on public.pachanga_competition_entries
for each row execute function private.pachanga_public_competition_place_available_v1();

create or replace function public.get_my_pachanga_competition_publication_v1(
  target_competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare publication_row public.pachanga_competition_publications%rowtype;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(target_competition_id, actor_id, 'manage') then
    raise exception 'COMPETITION_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  select * into publication_row
  from public.pachanga_competition_publications publications
  where publications.competition_id = target_competition_id;
  if not found then return null; end if;
  return jsonb_build_object(
    'snapshot', private.pachanga_public_competition_publication_snapshot_v1(publication_row.id),
    'reviews', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', reviews.review_action,
        'fromStatus', reviews.from_status,
        'toStatus', reviews.to_status,
        'publicReason', reviews.public_reason,
        'serverSequence', reviews.server_sequence,
        'createdAt', reviews.created_at
      ) order by reviews.server_sequence desc, reviews.id desc)
      from public.pachanga_competition_publication_reviews reviews
      where reviews.publication_id = publication_row.id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_my_pachanga_competition_registration_requests_v1(
  target_team_id uuid default null,
  page_size integer default 50,
  page_offset integer default 0
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
  if page_size < 1 or page_size > 100 or page_offset < 0 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  if target_team_id is not null then
    perform private.pachanga_league_assert_team_owner_v1(target_team_id, actor_id);
  end if;
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        private.pachanga_public_competition_request_snapshot_v1(requests.id, false)
        order by requests.server_sequence desc, requests.id desc
      )
      from (
        select source.*
        from public.pachanga_competition_registration_requests source
        join public.pachanga_groups teams on teams.id = source.team_id
        where teams.owner_id = actor_id
          and (target_team_id is null or source.team_id = target_team_id)
        order by source.server_sequence desc, source.id desc
        limit page_size offset page_offset
      ) requests
    ), '[]'::jsonb),
    'pageSize', page_size,
    'pageOffset', page_offset
  );
end;
$$;

create or replace function public.get_pachanga_competition_registration_queue_v1(
  target_competition_id uuid,
  status_filter text default null,
  page_size integer default 100,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare normalized_status text := nullif(lower(trim(coalesce(status_filter, ''))), '');
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_competition_can_v1(
    target_competition_id, actor_id, 'entries_manage'
  ) then raise exception 'COMPETITION_REGISTRATION_MANAGER_REQUIRED' using errcode = '42501'; end if;
  if page_size < 1 or page_size > 200 or page_offset < 0 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  if normalized_status is not null and normalized_status not in (
    'draft', 'submitted', 'under_review', 'accepted', 'rejected',
    'waitlisted', 'withdrawn', 'expired', 'cancelled'
  ) then raise exception 'REGISTRATION_STATUS_FILTER_INVALID' using errcode = '22023'; end if;
  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(
        private.pachanga_public_competition_request_snapshot_v1(requests.id, true)
        order by case when requests.status = 'waitlisted' then 0 else 1 end,
          requests.waitlist_position nulls last,
          requests.server_sequence,
          requests.id
      )
      from (
        select source.*
        from public.pachanga_competition_registration_requests source
        where source.competition_id = target_competition_id
          and (normalized_status is null or source.status = normalized_status)
        order by case when source.status = 'waitlisted' then 0 else 1 end,
          source.waitlist_position nulls last,
          source.server_sequence,
          source.id
        limit page_size offset page_offset
      ) requests
    ), '[]'::jsonb),
    'pageSize', page_size,
    'pageOffset', page_offset
  );
end;
$$;

create or replace function public.get_pachanga_public_competition_control_center_v1(
  publication_status text default null,
  report_status text default null,
  page_size integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare normalized_publication_status text := nullif(lower(trim(coalesce(publication_status, ''))), '');
declare normalized_report_status text := nullif(lower(trim(coalesce(report_status, ''))), '');
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  if page_size < 1 or page_size > 250 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'publications', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', publications.id,
        'competitionId', publications.competition_id,
        'slug', publications.slug,
        'visibility', publications.visibility,
        'status', publications.lifecycle_status,
        'organizerVerified', publications.organizer_verified,
        'contentFingerprint', publications.content_fingerprint,
        'hasCurrentConsent', publications.current_consent_id is not null,
        'revision', publications.revision,
        'serverSequence', publications.server_sequence,
        'submittedAt', publications.submitted_at,
        'updatedAt', publications.updated_at,
        'privacy', jsonb_build_object(
          'containsRoster', false,
          'containsAttendance', false,
          'containsContactData', false,
          'containsEvidence', false,
          'containsFees', false
        )
      ) order by publications.server_sequence desc, publications.id desc)
      from (
        select source.*
        from public.pachanga_competition_publications source
        where normalized_publication_status is null
          or source.lifecycle_status = normalized_publication_status
        order by source.server_sequence desc, source.id desc
        limit page_size
      ) publications
    ), '[]'::jsonb),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', reports.id,
        'opaqueReference', reports.opaque_reference,
        'publicationId', reports.publication_id,
        'competitionId', reports.competition_id,
        'category', reports.category,
        'summary', reports.summary,
        'status', reports.status,
        'resolutionCode', reports.resolution_code,
        'publicResolution', reports.public_resolution,
        'privateResolution', reports.private_resolution,
        'revision', reports.revision,
        'serverSequence', reports.server_sequence,
        'createdAt', reports.created_at,
        'reviewedAt', reports.reviewed_at
      ) order by reports.server_sequence, reports.id)
      from (
        select source.*
        from private.pachanga_competition_reports source
        where normalized_report_status is null or source.status = normalized_report_status
        order by source.server_sequence, source.id
        limit page_size
      ) reports
    ), '[]'::jsonb)
  );
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_publication_tables publication_tables
    where publication_tables.pubname = 'supabase_realtime'
      and publication_tables.schemaname = 'public'
      and publication_tables.tablename = 'pachanga_competition_invalidations'
  ) then
    alter publication supabase_realtime
      add table public.pachanga_competition_invalidations;
  end if;
end;
$$;

revoke all on function private.pachanga_public_competition_source_refresh_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_request_invalidation_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_public_competition_place_available_v1()
  from public, anon, authenticated;
revoke all on function public.get_my_pachanga_competition_publication_v1(uuid)
  from public, anon;
revoke all on function public.get_my_pachanga_competition_registration_requests_v1(uuid, integer, integer)
  from public, anon;
revoke all on function public.get_pachanga_competition_registration_queue_v1(uuid, text, integer, integer)
  from public, anon;
revoke all on function public.get_pachanga_public_competition_control_center_v1(text, text, integer)
  from public, anon;
grant execute on function public.get_my_pachanga_competition_publication_v1(uuid)
  to authenticated;
grant execute on function public.get_my_pachanga_competition_registration_requests_v1(uuid, integer, integer)
  to authenticated;
grant execute on function public.get_pachanga_competition_registration_queue_v1(uuid, text, integer, integer)
  to authenticated;
grant execute on function public.get_pachanga_public_competition_control_center_v1(text, text, integer)
  to authenticated;

comment on function private.pachanga_public_competition_source_refresh_v1() is
  'Refreshes canonical public read models in the sports mutation transaction; clients still refetch instead of trusting WAL.';
comment on trigger invalidate_public_competition_registration_request_v1
  on public.pachanga_competition_registration_requests is
  'Targets safe Competition invalidations to organizer and requesting Team. No request message or private reason enters WAL.';
