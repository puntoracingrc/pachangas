-- Pachangas IQ Wave 7A: feature activation authority, privacy health and final
-- hardening. Every new flag is installed OFF and can change only through RPC.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_public_competition_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundation', settings.public_competition_foundation_enabled,
    'publication', settings.public_competition_publication_enabled,
    'discovery', settings.public_competition_discovery_enabled,
    'registrationRequests', settings.public_competition_registration_requests_enabled,
    'waitlist', settings.public_competition_waitlist_enabled,
    'calendar', settings.public_competition_calendar_enabled,
    'results', settings.public_competition_results_enabled,
    'standings', settings.public_competition_standings_enabled,
    'bracket', settings.public_competition_bracket_enabled,
    'exceptionStatus', settings.public_competition_exception_status_enabled,
    'referees', settings.public_competition_referee_display_enabled,
    'discipline', false,
    'autoAccept', false,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

alter table public.pachanga_competition_invalidations
  drop constraint if exists pachanga_competition_invalidations_authority_check;
alter table public.pachanga_competition_invalidations
  add constraint pachanga_competition_invalidations_authority_check check (
    (
      organizer_group_id is not null
      and organizer_club_id is null
    ) or (
      organizer_group_id is null
      and organizer_club_id is not null
    ) or (
      organizer_group_id is null
      and organizer_club_id is null
      and competition_id is null
      and entity_type in (
        'league_participation_flags',
        'league_scheduling_flags',
        'league_match_operations_flags',
        'league_operational_exceptions_flags',
        'competition_discipline_flags',
        'public_competition_flags'
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
          'competition_discipline_flags', 'public_competition_flags'
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
        where members.group_id = target_group_id
          and members.user_id = actor_id
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

create or replace function public.get_pachanga_public_competition_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_public_competition_flags_v1();
$$;

create or replace function public.set_pachanga_public_competition_flags_v1(
  operation_id uuid,
  expected_revision bigint,
  flag_patch jsonb,
  reason text,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare operation_id_value uuid := operation_id;
declare actor_role text;
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare saved private.pachanga_platform_admin_action_ledger%rowtype;
declare sanitized_metadata jsonb;
declare request_hash text;
declare response jsonb;
declare sequence_value bigint;
declare next_foundation boolean;
declare next_publication boolean;
declare next_discovery boolean;
declare next_registration boolean;
declare next_waitlist boolean;
declare next_calendar boolean;
declare next_results boolean;
declare next_standings boolean;
declare next_bracket boolean;
declare next_exceptions boolean;
declare next_referees boolean;
declare before_state jsonb;
begin
  actor_role := private.pachanga_platform_require_v1('flags.write');
  if operation_id_value is null or expected_revision is null or expected_revision < 1
     or jsonb_typeof(coalesce(flag_patch, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or length(trim(coalesce(reason, ''))) not between 3 and 1200 then
    raise exception 'INVALID_PUBLIC_COMPETITION_FLAG_COMMAND' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_object_keys(coalesce(flag_patch, '{}'::jsonb)) keys(key)
    where keys.key not in (
      'foundation', 'publication', 'discovery', 'registrationRequests',
      'waitlist', 'calendar', 'results', 'standings', 'bracket',
      'exceptionStatus', 'referees', 'discipline', 'autoAccept'
    )
  ) then raise exception 'PUBLIC_COMPETITION_FLAG_FIELD_FORBIDDEN' using errcode = '22023'; end if;
  if coalesce((flag_patch ->> 'discipline')::boolean, false)
     or coalesce((flag_patch ->> 'autoAccept')::boolean, false) then
    raise exception 'PUBLIC_COMPETITION_UNSAFE_FLAG_DISABLED' using errcode = '42501';
  end if;
  sanitized_metadata := private.pachanga_competition_client_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_request_hash_v1(
    'public_competitions.flags.set',
    '00000000-0000-0000-0000-00000000007a'::uuid,
    expected_revision,
    jsonb_build_object('patch', flag_patch, 'reason', trim(reason))
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id_value::text, 91707));
  select * into saved from private.pachanga_platform_admin_action_ledger ledger
  where ledger.operation_id = operation_id_value;
  if found then
    if saved.action <> 'public_competitions.flags.set'
       or saved.target_type <> 'public_competition_flags'
       or saved.target_id <> 'singleton'
       or saved.after_state ->> 'requestHash' <> request_hash then
      raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
    end if;
    return saved.response;
  end if;

  select * into settings from private.pachanga_competition_foundation_settings
  where singleton for update;
  if settings.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  before_state := private.pachanga_public_competition_flags_v1();
  next_foundation := case when flag_patch ? 'foundation'
    then (flag_patch ->> 'foundation')::boolean
    else settings.public_competition_foundation_enabled end;
  next_publication := case when flag_patch ? 'publication'
    then (flag_patch ->> 'publication')::boolean
    else settings.public_competition_publication_enabled end;
  next_discovery := case when flag_patch ? 'discovery'
    then (flag_patch ->> 'discovery')::boolean
    else settings.public_competition_discovery_enabled end;
  next_registration := case when flag_patch ? 'registrationRequests'
    then (flag_patch ->> 'registrationRequests')::boolean
    else settings.public_competition_registration_requests_enabled end;
  next_waitlist := case when flag_patch ? 'waitlist'
    then (flag_patch ->> 'waitlist')::boolean
    else settings.public_competition_waitlist_enabled end;
  next_calendar := case when flag_patch ? 'calendar'
    then (flag_patch ->> 'calendar')::boolean
    else settings.public_competition_calendar_enabled end;
  next_results := case when flag_patch ? 'results'
    then (flag_patch ->> 'results')::boolean
    else settings.public_competition_results_enabled end;
  next_standings := case when flag_patch ? 'standings'
    then (flag_patch ->> 'standings')::boolean
    else settings.public_competition_standings_enabled end;
  next_bracket := case when flag_patch ? 'bracket'
    then (flag_patch ->> 'bracket')::boolean
    else settings.public_competition_bracket_enabled end;
  next_exceptions := case when flag_patch ? 'exceptionStatus'
    then (flag_patch ->> 'exceptionStatus')::boolean
    else settings.public_competition_exception_status_enabled end;
  next_referees := case when flag_patch ? 'referees'
    then (flag_patch ->> 'referees')::boolean
    else settings.public_competition_referee_display_enabled end;

  if (next_publication and not next_foundation)
     or (next_discovery and not (next_foundation and next_publication))
     or (next_registration and not (next_foundation and next_publication and next_discovery))
     or (next_waitlist and not next_registration)
     or ((next_calendar or next_results or next_standings or next_bracket
       or next_exceptions or next_referees) and not next_discovery) then
    raise exception 'PUBLIC_COMPETITION_FLAG_DEPENDENCY_INVALID' using errcode = '22023';
  end if;

  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings target set
    public_competition_foundation_enabled = next_foundation,
    public_competition_publication_enabled = next_publication,
    public_competition_discovery_enabled = next_discovery,
    public_competition_registration_requests_enabled = next_registration,
    public_competition_waitlist_enabled = next_waitlist,
    public_competition_calendar_enabled = next_calendar,
    public_competition_results_enabled = next_results,
    public_competition_standings_enabled = next_standings,
    public_competition_bracket_enabled = next_bracket,
    public_competition_exception_status_enabled = next_exceptions,
    public_competition_referee_display_enabled = next_referees,
    public_competition_discipline_enabled = false,
    public_competition_auto_accept_enabled = false,
    revision = target.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = clock_timestamp()
  where target.singleton
  returning * into settings;
  response := jsonb_build_object(
    'operationId', operation_id_value,
    'confirmedRevision', settings.revision,
    'serverSequence', sequence_value,
    'confirmedAt', settings.updated_at,
    'snapshot', private.pachanga_public_competition_flags_v1()
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    target_group_id, target_user_id, entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, null, null, null, null, null,
    'public_competition_flags', 'singleton', settings.revision, settings.updated_at
  );
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response
  ) values (
    operation_id_value, actor_id, actor_role, 'public_competitions.flags.set',
    'public_competition_flags', 'singleton', trim(reason), before_state,
    jsonb_build_object(
      'requestHash', request_hash,
      'flags', private.pachanga_public_competition_flags_v1(),
      'clientMetadata', sanitized_metadata
    ), response
  );
  return response;
exception when invalid_text_representation then
  raise exception 'INVALID_PUBLIC_COMPETITION_FLAG_COMMAND' using errcode = '22023';
end;
$$;

create or replace function public.get_pachanga_public_competition_platform_health_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  return jsonb_build_object(
    'flags', private.pachanga_public_competition_flags_v1(),
    'publications', jsonb_build_object(
      'total', (select count(*) from public.pachanga_competition_publications),
      'pendingReview', (select count(*) from public.pachanga_competition_publications
        where lifecycle_status = 'pending_review'),
      'published', (select count(*) from public.pachanga_competition_publications
        where lifecycle_status = 'published'),
      'suspended', (select count(*) from public.pachanga_competition_publications
        where lifecycle_status = 'suspended'),
      'indexable', (select count(*) from public.pachanga_public_competition_read_models
        where is_indexable)
    ),
    'registration', jsonb_build_object(
      'submitted', (select count(*) from public.pachanga_competition_registration_requests
        where status in ('submitted', 'under_review')),
      'waitlisted', (select count(*) from public.pachanga_competition_registration_requests
        where status = 'waitlisted'),
      'accepted', (select count(*) from public.pachanga_competition_registration_requests
        where status = 'accepted')
    ),
    'reports', jsonb_build_object(
      'open', (select count(*) from private.pachanga_competition_reports
        where status in ('submitted', 'under_review'))
    ),
    'readModels', jsonb_build_object(
      'stale', (select count(*)
        from public.pachanga_competition_publications publications
        left join public.pachanga_public_competition_read_models models
          on models.publication_id = publications.id
        where models.publication_id is null
          or models.revision <> publications.revision
          or models.server_sequence < publications.server_sequence),
      'privacyViolations', (select count(*)
        from public.pachanga_public_competition_read_models models
        where coalesce((models.public_snapshot #>> '{privacy,containsRoster}')::boolean, true)
          or coalesce((models.public_snapshot #>> '{privacy,containsAttendance}')::boolean, true)
          or coalesce((models.public_snapshot #>> '{privacy,containsContactData}')::boolean, true)
          or coalesce((models.public_snapshot #>> '{privacy,containsEvidence}')::boolean, true)
          or coalesce((models.public_snapshot #>> '{privacy,containsFees}')::boolean, true)
          or coalesce((models.public_snapshot #>> '{privacy,containsPrivateLocation}')::boolean, true)),
      'indexingViolations', (select count(*)
        from public.pachanga_public_competition_read_models models
        where models.is_indexable <> (
          models.visibility = 'public' and models.lifecycle_status = 'published'
        ))
    ),
    'generatedAt', clock_timestamp()
  );
end;
$$;

revoke all on function private.pachanga_public_competition_flags_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.pachanga_league_can_read_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, text, uuid
) to authenticated;
revoke all on function public.get_pachanga_public_competition_flags_v1()
  from public;
grant execute on function public.get_pachanga_public_competition_flags_v1()
  to anon, authenticated;
revoke all on function public.set_pachanga_public_competition_flags_v1(
  uuid, bigint, jsonb, text, jsonb
) from public, anon;
grant execute on function public.set_pachanga_public_competition_flags_v1(
  uuid, bigint, jsonb, text, jsonb
) to authenticated;
revoke all on function public.get_pachanga_public_competition_platform_health_v1()
  from public, anon;
grant execute on function public.get_pachanga_public_competition_platform_health_v1()
  to authenticated;

comment on function public.set_pachanga_public_competition_flags_v1(
  uuid, bigint, jsonb, text, jsonb
) is 'Only supported Wave 7A activation path. Discipline, auto-accept and payment capabilities remain impossible here.';
comment on function public.get_pachanga_public_competition_platform_health_v1() is
  'Control Center health without PII: publication, queue, privacy, indexing and canonical read-model convergence.';
