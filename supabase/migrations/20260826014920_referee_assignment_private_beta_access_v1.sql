-- Pachangas IQ Wave 4: bounded read models, privacy gates and private-beta
-- activation. Direct tables remain closed; clients receive canonical snapshots.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_referee_flags_snapshot_v1()
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.referee_foundation_enabled,
    'selfServiceEnabled', settings.referee_self_service_enabled,
    'publicProfilesEnabled', settings.referee_public_profiles_enabled,
    'marketplaceEnabled', settings.referee_marketplace_enabled,
    'clubRelationshipsEnabled', settings.referee_club_relationships_enabled,
    'assignmentsEnabled', settings.referee_assignments_enabled,
    'assignmentPrivateBetaEnabled', settings.referee_assignment_private_beta_enabled,
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_referee_foundation_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_referee_public_snapshot_v1(target_profile_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'slug', profiles.slug,
    'displayName', profiles.public_display_name_snapshot,
    'avatar', profiles.public_avatar_snapshot,
    'bio', profiles.bio,
    'experienceSinceYear', profiles.experience_since_year,
    'experienceSummary', profiles.experience_summary,
    'operationalStatus', profiles.operational_status,
    'verificationStatus', profiles.verification_status,
    'availabilityStatus', profiles.availability_status,
    'publicFee', case
      when profiles.public_fee_visibility
        and private.pachanga_referee_public_fee_consent_valid_v1(profiles.id)
      then jsonb_build_object(
        'feeMode', profiles.public_fee_mode,
        'fromCents', profiles.public_fee_from_cents,
        'currency', profiles.public_fee_currency,
        'paymentManagedByPachangasIq', false
      )
      else null
    end,
    'modalities', coalesce((
      select jsonb_agg(jsonb_build_object(
        'modality', modalities.modality,
        'experienceSinceYear', modalities.experience_since_year,
        'note', modalities.public_note
      ) order by modalities.modality, modalities.id)
      from public.pachanga_referee_modalities modalities
      where modalities.referee_profile_id = profiles.id and modalities.active
    ), '[]'::jsonb),
    'areas', coalesce((
      select jsonb_agg(jsonb_build_object(
        'countryCode', areas.country_code,
        'province', areas.province,
        'municipality', areas.municipality,
        'generalArea', areas.general_area,
        'travelRadiusKm', areas.travel_radius_km
      ) order by areas.country_code, areas.province, areas.municipality, areas.general_area, areas.id)
      from public.pachanga_referee_service_areas areas
      where areas.referee_profile_id = profiles.id and areas.status = 'active'
    ), '[]'::jsonb),
    'availabilityWindows', case when profiles.share_recurring_availability then coalesce((
      select jsonb_agg(jsonb_build_object(
        'weekday', windows.weekday,
        'startLocalTime', windows.start_local_time,
        'endLocalTime', windows.end_local_time,
        'timezone', windows.timezone
      ) order by windows.weekday, windows.start_local_time, windows.id)
      from public.pachanga_referee_availability_windows windows
      where windows.referee_profile_id = profiles.id
        and windows.status = 'active'
        and windows.public_visible
    ), '[]'::jsonb) else '[]'::jsonb end,
    'clubs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', clubs.name,
        'slug', clubs.slug,
        'relationshipType', relationships.relationship_type,
        'verified', clubs.verification_status = 'verified'
      ) order by clubs.name, clubs.id)
      from public.pachanga_club_referee_relationships relationships
      join public.pachanga_clubs clubs on clubs.id = relationships.club_id
      where relationships.referee_profile_id = profiles.id
        and relationships.status = 'active'
        and relationships.show_on_referee_profile
        and clubs.operational_status = 'active'
        and clubs.visibility = 'public'
    ), '[]'::jsonb),
    'statistics', jsonb_build_object(
      'matchesCompleted', coalesce(stats.matches_completed, 0),
      'individualMatchesCompleted', coalesce(stats.individual_matches_completed, 0),
      'competitionMatchesCompleted', coalesce(stats.competition_matches_completed, 0),
      'leagueMatchesCompleted', coalesce(stats.league_matches_completed, 0),
      'replacements', coalesce(stats.replacements, 0),
      'cancellations', coalesce(stats.cancellations, 0),
      'disciplineStatsStatus', coalesce(stats.discipline_stats_status, 'CANONICAL_R5'),
      'yellowCardsShown', coalesce(stats.yellow_cards_shown, 0),
      'redCardsShown', coalesce(stats.red_cards_shown, 0),
      'blueCardsShown', coalesce(stats.blue_cards_shown, 0),
      'lastCompletedAt', stats.last_completed_at
    ),
    'revision', profiles.revision,
    'serverSequence', profiles.server_sequence,
    'updatedAt', profiles.updated_at
  )
  from public.pachanga_referee_profiles profiles
  left join public.pachanga_referee_statistics_snapshots stats
    on stats.referee_profile_id = profiles.id
  where profiles.id = target_profile_id;
$$;

create or replace function private.pachanga_referee_assignment_requester_can_v1(
  target_assignment_id uuid,
  target_actor_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare assignment public.pachanga_referee_assignments%rowtype;
begin
  if target_actor_id is null then return false; end if;
  if private.pachanga_referee_platform_can_v1(target_actor_id, 'referees.manage') then return true; end if;
  select * into assignment
  from public.pachanga_referee_assignments assignments
  where assignments.id = target_assignment_id;
  if not found then return false; end if;
  if assignment.requester_kind = 'TEAM' then
    return exists (
      select 1 from public.pachanga_groups groups
      where groups.id = assignment.requester_team_id and groups.owner_id = target_actor_id
    ) or exists (
      select 1 from public.pachanga_group_members members
      where members.group_id = assignment.requester_team_id
        and members.user_id = target_actor_id
        and members.role in ('owner', 'admin')
    );
  elsif assignment.requester_kind = 'CLUB' then
    return private.pachanga_club_can_v1(
      assignment.requester_club_id, target_actor_id, 'referee_manage'
    );
  elsif assignment.requester_kind = 'COMPETITION' then
    return private.pachanga_competition_can_v1(
      assignment.requester_competition_id, target_actor_id, 'referees'
    );
  end if;
  return false;
end;
$$;

create or replace function private.pachanga_referee_match_participant_can_v1(
  target_canonical_match_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select target_actor_id is not null and (
    exists (
      select 1
      from public.pachanga_canonical_match_bindings bindings
      join public.pachanga_group_members members
        on members.group_id = bindings.source_group_id
      where bindings.canonical_match_id = target_canonical_match_id
        and bindings.binding_status = 'active'
        and members.user_id = target_actor_id
    )
    or exists (
      select 1
      from public.pachanga_competition_match_contexts contexts
      where contexts.canonical_match_id = target_canonical_match_id
        and contexts.status not in ('retired', 'cancelled')
        and private.pachanga_competition_can_v1(contexts.competition_id, target_actor_id, 'read')
    )
    or exists (
      select 1
      from public.pachanga_competition_match_contexts contexts
      join public.pachanga_competition_entries entries
        on entries.id in (contexts.home_entry_id, contexts.away_entry_id)
      join public.pachanga_group_members members on members.group_id = entries.team_id
      where contexts.canonical_match_id = target_canonical_match_id
        and contexts.status not in ('retired', 'cancelled')
        and members.user_id = target_actor_id
    )
  );
$$;

create or replace function private.pachanga_referee_assignment_can_read_v1(
  target_assignment_id uuid,
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
    from public.pachanga_referee_assignments assignments
    join public.pachanga_referee_profiles profiles
      on profiles.id = assignments.referee_profile_id
    where assignments.id = target_assignment_id
      and (
        profiles.user_id = target_actor_id
        or private.pachanga_referee_assignment_requester_can_v1(assignments.id, target_actor_id)
        or private.pachanga_referee_platform_can_v1(target_actor_id, 'referees.read')
        or private.pachanga_referee_match_participant_can_v1(
          assignments.canonical_match_id, target_actor_id
        )
      )
  );
$$;

create or replace function private.pachanga_referee_assignment_can_view_terms_v1(
  target_assignment_id uuid,
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
    from public.pachanga_referee_assignments assignments
    join public.pachanga_referee_profiles profiles
      on profiles.id = assignments.referee_profile_id
    where assignments.id = target_assignment_id
      and (
        profiles.user_id = target_actor_id
        or private.pachanga_referee_assignment_requester_can_v1(assignments.id, target_actor_id)
        or private.pachanga_referee_platform_can_v1(target_actor_id, 'referees.manage')
      )
  );
$$;

create or replace function private.pachanga_referee_assignment_product_document_v1(
  target_assignment_id uuid,
  include_private_terms boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_referee_assignment_document_v1(
    assignments.id, include_private_terms
  ) || jsonb_build_object(
    'referee', private.pachanga_referee_public_snapshot_v1(assignments.referee_profile_id),
    'competitionName', competitions.name,
    'requesterName', case assignments.requester_kind
      when 'TEAM' then teams.name
      when 'CLUB' then clubs.name
      when 'COMPETITION' then competitions.name
      else null
    end,
    'paymentManagedByPachangasIq', false
  )
  from public.pachanga_referee_assignments assignments
  left join public.pachanga_groups teams on teams.id = assignments.requester_team_id
  left join public.pachanga_clubs clubs on clubs.id = assignments.requester_club_id
  left join public.pachanga_competitions competitions
    on competitions.id = coalesce(assignments.requester_competition_id, assignments.competition_id)
  where assignments.id = target_assignment_id;
$$;

create or replace function public.get_my_pachanga_referee_assignments_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  profile_id uuid;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  perform private.pachanga_referee_assert_assignment_beta_v1();
  profile_id := private.pachanga_referee_profile_for_user_v1(actor_id);
  return jsonb_build_object(
    'flags', private.pachanga_referee_flags_snapshot_v1(),
    'refereeProfileId', profile_id,
    'summary', jsonb_build_object(
      'pending', (select count(*) from public.pachanga_referee_assignments a
                  where a.referee_profile_id = profile_id and a.status = 'proposed'),
      'accepted', (select count(*) from public.pachanga_referee_assignments a
                   where a.referee_profile_id = profile_id and a.status = 'accepted'),
      'confirmed', (select count(*) from public.pachanga_referee_assignments a
                    where a.referee_profile_id = profile_id and a.status = 'confirmed'),
      'reconfirmationRequired', (select count(*) from public.pachanga_referee_assignments a
                    where a.referee_profile_id = profile_id
                      and a.schedule_state in ('RECONFIRMATION_REQUIRED', 'STALE_SCHEDULE')),
      'completed', (select count(*) from public.pachanga_referee_assignments a
                    where a.referee_profile_id = profile_id and a.status = 'completed')
    ),
    'items', coalesce((
      select jsonb_agg(
        private.pachanga_referee_assignment_product_document_v1(assignments.id, true)
        order by
          (assignments.status in ('proposed', 'accepted', 'confirmed')) desc,
          assignments.effective_scheduled_start,
          assignments.server_sequence desc,
          assignments.id
      )
      from public.pachanga_referee_assignments assignments
      where assignments.referee_profile_id = profile_id
    ), '[]'::jsonb),
    'generatedAt', clock_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_referee_assignment_beta_v1(
  target_assignment_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  assignment public.pachanga_referee_assignments%rowtype;
  can_view_terms boolean;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  select * into assignment
  from public.pachanga_referee_assignments assignments
  where assignments.id = target_assignment_id;
  if not found then raise exception 'REFEREE_ASSIGNMENT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not private.pachanga_referee_assignment_can_read_v1(assignment.id, actor_id) then
    raise exception 'REFEREE_ASSIGNMENT_READ_REQUIRED' using errcode = '42501';
  end if;
  can_view_terms := private.pachanga_referee_assignment_can_view_terms_v1(assignment.id, actor_id);
  if not can_view_terms and assignment.status not in ('confirmed', 'replaced', 'completed') then
    raise exception 'REFEREE_ASSIGNMENT_READ_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'assignment', private.pachanga_referee_assignment_product_document_v1(
      assignment.id, can_view_terms
    ),
    'capabilities', jsonb_build_object(
      'viewPrivateTerms', can_view_terms,
      'requesterManage', private.pachanga_referee_assignment_requester_can_v1(
        assignment.id, actor_id
      ),
      'refereeOwner', exists (
        select 1 from public.pachanga_referee_profiles profiles
        where profiles.id = assignment.referee_profile_id and profiles.user_id = actor_id
      )
    )
  );
end;
$$;

create or replace function public.get_pachanga_referee_match_assignment_v1(
  target_canonical_match_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  manager_access boolean;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not private.pachanga_referee_match_participant_can_v1(target_canonical_match_id, actor_id)
     and not private.pachanga_referee_platform_can_v1(actor_id, 'referees.read')
     and not exists (
       select 1
       from public.pachanga_referee_assignments assignments
       join public.pachanga_referee_profiles profiles on profiles.id = assignments.referee_profile_id
       where assignments.canonical_match_id = target_canonical_match_id
         and profiles.user_id = actor_id
     ) then raise exception 'REFEREE_MATCH_READ_REQUIRED' using errcode = '42501'; end if;
  manager_access := private.pachanga_referee_platform_can_v1(actor_id, 'referees.manage')
    or exists (
      select 1 from public.pachanga_referee_assignments assignments
      where assignments.canonical_match_id = target_canonical_match_id
        and private.pachanga_referee_assignment_requester_can_v1(assignments.id, actor_id)
    );
  return jsonb_build_object(
    'canonicalMatchId', target_canonical_match_id,
    'items', coalesce((
      select jsonb_agg(
        private.pachanga_referee_assignment_product_document_v1(
          assignments.id,
          private.pachanga_referee_assignment_can_view_terms_v1(assignments.id, actor_id)
        ) order by assignments.server_sequence desc, assignments.id desc
      )
      from public.pachanga_referee_assignments assignments
      where assignments.canonical_match_id = target_canonical_match_id
        and (manager_access or assignments.status in ('confirmed', 'replaced', 'completed'))
    ), '[]'::jsonb),
    'capabilities', jsonb_build_object('manage', manager_access)
  );
end;
$$;

create or replace function public.get_pachanga_referee_competition_desk_v1(
  target_competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  perform private.pachanga_referee_assert_assignment_beta_v1();
  if not private.pachanga_competition_can_v1(target_competition_id, actor_id, 'referees') then
    raise exception 'REFEREE_COMPETITION_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'competitionId', target_competition_id,
    'summary', jsonb_build_object(
      'withoutReferee', (
        select count(*)
        from public.pachanga_competition_match_contexts contexts
        where contexts.competition_id = target_competition_id
          and contexts.status not in ('retired', 'cancelled')
          and not exists (
            select 1 from public.pachanga_referee_assignments assignments
            where assignments.canonical_match_id = contexts.canonical_match_id
              and assignments.assignment_role = 'MAIN_REFEREE'
              and assignments.status in ('accepted', 'confirmed', 'completed')
          )
      ),
      'proposed', (select count(*) from public.pachanga_referee_assignments a
                   where a.competition_id = target_competition_id and a.status = 'proposed'),
      'accepted', (select count(*) from public.pachanga_referee_assignments a
                   where a.competition_id = target_competition_id and a.status = 'accepted'),
      'confirmed', (select count(*) from public.pachanga_referee_assignments a
                    where a.competition_id = target_competition_id and a.status = 'confirmed'),
      'reconfirmationRequired', (select count(*) from public.pachanga_referee_assignments a
                    where a.competition_id = target_competition_id
                      and a.schedule_state in ('RECONFIRMATION_REQUIRED', 'STALE_SCHEDULE')),
      'completed', (select count(*) from public.pachanga_referee_assignments a
                    where a.competition_id = target_competition_id and a.status = 'completed')
    ),
    'matches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'competitionMatchContextId', contexts.id,
        'canonicalMatchId', contexts.canonical_match_id,
        'status', contexts.status,
        'scheduledStart', contexts.scheduled_start,
        'scheduledEnd', contexts.scheduled_end,
        'timezone', contexts.timezone,
        'venueLabel', contexts.venue_label,
        'venueStatus', contexts.venue_status,
        'assignments', coalesce((
          select jsonb_agg(
            private.pachanga_referee_assignment_product_document_v1(assignments.id, true)
            order by assignments.server_sequence desc, assignments.id desc
          )
          from public.pachanga_referee_assignments assignments
          where assignments.canonical_match_id = contexts.canonical_match_id
        ), '[]'::jsonb)
      ) order by contexts.scheduled_start nulls last, contexts.server_sequence, contexts.id)
      from public.pachanga_competition_match_contexts contexts
      where contexts.competition_id = target_competition_id
        and contexts.status not in ('retired', 'cancelled')
    ), '[]'::jsonb),
    'generatedAt', clock_timestamp()
  );
end;
$$;

create or replace function public.get_pachanga_referee_club_assignments_v1(
  target_club_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  can_manage boolean;
begin
  if actor_id is null or not private.pachanga_club_can_v1(target_club_id, actor_id, 'read') then
    raise exception 'CLUB_REFEREE_READ_REQUIRED' using errcode = '42501';
  end if;
  can_manage := private.pachanga_club_can_v1(target_club_id, actor_id, 'referee_manage')
    or private.pachanga_referee_platform_can_v1(actor_id, 'referees.manage');
  return jsonb_build_object(
    'clubId', target_club_id,
    'items', coalesce((
      select jsonb_agg(
        private.pachanga_referee_assignment_product_document_v1(assignments.id, can_manage)
        order by assignments.effective_scheduled_start, assignments.server_sequence desc, assignments.id
      )
      from public.pachanga_referee_assignments assignments
      where assignments.requester_club_id = target_club_id
         or assignments.competition_id in (
           select competitions.id from public.pachanga_competitions competitions
           where competitions.organizer_kind = 'CLUB'
             and competitions.organizer_club_id = target_club_id
         )
    ), '[]'::jsonb),
    'capabilities', jsonb_build_object('manage', can_manage)
  );
end;
$$;

create or replace function public.get_my_pachanga_referee_beta_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := auth.uid();
  base jsonb;
  profile_id uuid;
  fee_document jsonb;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  base := public.get_my_pachanga_referee_platform_v1();
  profile_id := nullif(base -> 'profile' -> 'profile' ->> 'id', '')::uuid;
  if profile_id is null then return base; end if;
  select jsonb_build_object(
    'visible', profiles.public_fee_visibility,
    'feeMode', profiles.public_fee_mode,
    'fromCents', profiles.public_fee_from_cents,
    'currency', profiles.public_fee_currency,
    'paymentManagedByPachangasIq', false,
    'consent', private.pachanga_referee_public_fee_consent_snapshot_v1(profiles.id)
  ) into fee_document
  from public.pachanga_referee_profiles profiles where profiles.id = profile_id;
  base := jsonb_set(base, '{profile,profile,publicFee}', fee_document, true);
  base := jsonb_set(
    base,
    '{profile,assignments}',
    coalesce(public.get_my_pachanga_referee_assignments_v1() -> 'items', '[]'::jsonb),
    true
  );
  return jsonb_set(
    base,
    '{profile,publicationConsent}',
    private.pachanga_publication_consent_snapshot_v1('REFEREE_PROFILE', profile_id, actor_id),
    true
  );
end;
$$;

create or replace function public.get_pachanga_platform_referee_health_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
begin
  if not private.pachanga_referee_platform_can_health_v1(actor_id) then
    raise exception 'REFEREE_HEALTH_CAPABILITY_REQUIRED' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'flags', private.pachanga_referee_flags_snapshot_v1(),
    'profiles', jsonb_build_object(
      'total', (select count(*) from public.pachanga_referee_profiles),
      'active', (select count(*) from public.pachanga_referee_profiles where operational_status = 'active'),
      'suspended', (select count(*) from public.pachanga_referee_profiles where operational_status = 'suspended'),
      'listed', (select count(*) from public.pachanga_referee_profiles where marketplace_status = 'listed'),
      'publicFeeVisible', (select count(*) from public.pachanga_referee_profiles
                           where public_fee_visibility
                             and private.pachanga_referee_public_fee_consent_valid_v1(id))
    ),
    'assignments', jsonb_build_object(
      'proposed', (select count(*) from public.pachanga_referee_assignments where status = 'proposed'),
      'accepted', (select count(*) from public.pachanga_referee_assignments where status = 'accepted'),
      'confirmed', (select count(*) from public.pachanga_referee_assignments where status = 'confirmed'),
      'declined', (select count(*) from public.pachanga_referee_assignments where status = 'declined'),
      'cancelled', (select count(*) from public.pachanga_referee_assignments where status = 'cancelled'),
      'expired', (select count(*) from public.pachanga_referee_assignments where status = 'expired'),
      'replaced', (select count(*) from public.pachanga_referee_assignments where status = 'replaced'),
      'completed', (select count(*) from public.pachanga_referee_assignments where status = 'completed'),
      'staleSchedule', (select count(*) from public.pachanga_referee_assignments
                        where schedule_state in ('RECONFIRMATION_REQUIRED', 'STALE_SCHEDULE')),
      'activeSlotConflicts', (
        select count(*) from (
          select canonical_match_id, assignment_role
          from public.pachanga_referee_assignments
          where status in ('confirmed', 'completed')
          group by canonical_match_id, assignment_role having count(*) > 1
        ) conflicts
      ),
      'timeOverlapConflicts', (
        select count(*) from public.pachanga_referee_assignments left_assignment
        join public.pachanga_referee_assignments right_assignment
          on right_assignment.referee_profile_id = left_assignment.referee_profile_id
         and right_assignment.id > left_assignment.id
         and right_assignment.status in ('accepted', 'confirmed')
         and right_assignment.schedule_state = 'CURRENT'
         and tstzrange(right_assignment.effective_scheduled_start,
                       right_assignment.effective_scheduled_end, '[)')
             && tstzrange(left_assignment.effective_scheduled_start,
                          left_assignment.effective_scheduled_end, '[)')
        where left_assignment.status in ('accepted', 'confirmed')
          and left_assignment.schedule_state = 'CURRENT'
      )
    ),
    'evidence', jsonb_build_object(
      'assignmentRevisions', (select count(*) from public.pachanga_referee_assignment_revisions),
      'termRevisions', (select count(*) from private.pachanga_referee_assignment_term_revisions),
      'resultObservations', (select count(*) from private.pachanga_referee_result_observations),
      'disciplinaryEvents', (select count(*) from public.pachanga_competition_disciplinary_events
                             where referee_assignment_id is not null)
    ),
    'statistics', jsonb_build_object(
      'snapshots', (select count(*) from public.pachanga_referee_statistics_snapshots),
      'canonicalR5', (select count(*) from public.pachanga_referee_statistics_snapshots
                      where discipline_stats_status = 'CANONICAL_R5')
    ),
    'ledger', jsonb_build_object(
      'events', (select count(*) from private.pachanga_referee_events),
      'receipts', (select count(*) from private.pachanga_referee_operation_receipts),
      'lastServerSequence', (select coalesce(max(server_sequence), 0)
                             from private.pachanga_referee_events)
    ),
    'generatedAt', clock_timestamp()
  );
end;
$$;

create or replace function public.command_pachanga_referee_assignment_beta_admin_v1(
  operation_id uuid,
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
declare
  actor_id uuid := auth.uid();
  action_name text := lower(trim(coalesce(command_action, '')));
  payload jsonb := coalesce(command_payload, '{}'::jsonb);
  aggregate_id constant uuid := '00000000-0000-0000-0000-00000000a4f4'::uuid;
  settings private.pachanga_referee_foundation_settings%rowtype;
  request_hash text;
  replay jsonb;
  next_beta boolean;
  next_assignments boolean;
  snapshot jsonb;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if operation_id is null or expected_revision is null or expected_revision < 1
     or action_name <> 'assignment_beta.flags.set'
     or jsonb_typeof(payload) <> 'object' then
    raise exception 'INVALID_REFEREE_ASSIGNMENT_ADMIN_COMMAND' using errcode = '22023';
  end if;
  perform private.pachanga_platform_require_v1('flags.write');
  request_hash := private.pachanga_referee_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended('referee-operation:' || operation_id::text, 0));
  replay := private.pachanga_referee_replay_v1(operation_id, actor_id, request_hash);
  if replay is not null then return replay; end if;
  select * into settings
  from private.pachanga_referee_foundation_settings current_settings
  where current_settings.singleton for update;
  if settings.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  if (payload ? 'assignmentPrivateBetaEnabled'
        and jsonb_typeof(payload -> 'assignmentPrivateBetaEnabled') <> 'boolean')
     or (payload ? 'assignmentsEnabled'
        and jsonb_typeof(payload -> 'assignmentsEnabled') <> 'boolean') then
    raise exception 'INVALID_REFEREE_FLAG' using errcode = '22023';
  end if;
  next_beta := coalesce(
    (payload ->> 'assignmentPrivateBetaEnabled')::boolean,
    settings.referee_assignment_private_beta_enabled
  );
  next_assignments := coalesce(
    (payload ->> 'assignmentsEnabled')::boolean,
    settings.referee_assignments_enabled
  );
  if next_assignments and (not settings.referee_foundation_enabled or not next_beta) then
    raise exception 'REFEREE_ASSIGNMENT_FLAG_DEPENDENCY' using errcode = '22023';
  end if;
  if not next_beta then next_assignments := false; end if;
  update private.pachanga_referee_foundation_settings current_settings set
    referee_assignment_private_beta_enabled = next_beta,
    referee_assignments_enabled = next_assignments,
    revision = current_settings.revision + 1,
    server_sequence = nextval('private.pachanga_referee_sequence'),
    updated_by = actor_id,
    updated_at = clock_timestamp()
  where current_settings.singleton returning * into settings;
  snapshot := private.pachanga_referee_flags_snapshot_v1();
  return private.pachanga_referee_store_command_v1(
    operation_id, actor_id, 'authenticated', action_name,
    'referee_foundation_flags', aggregate_id::text, request_hash,
    settings.revision, left(coalesce(payload ->> 'reason', action_name), 120),
    snapshot - 'updatedAt', snapshot, null, null, null, actor_id, null,
    'private', client_metadata
  );
end;
$$;

create or replace function private.pachanga_referee_can_read_wave4_invalidation_v1(
  target_profile_id uuid,
  target_club_id uuid,
  target_user_id uuid,
  target_group_id uuid,
  target_canonical_match_id uuid,
  target_competition_id uuid,
  target_audience text,
  actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select private.pachanga_referee_can_read_invalidation_v1(
    target_profile_id, target_club_id, target_user_id, target_group_id,
    target_audience, actor_id
  )
  or (
    target_competition_id is not null
    and private.pachanga_competition_can_v1(target_competition_id, actor_id, 'read')
  )
  or (
    target_canonical_match_id is not null
    and private.pachanga_referee_match_participant_can_v1(target_canonical_match_id, actor_id)
  );
$$;

revoke all on function private.pachanga_referee_can_read_wave4_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, uuid, text, uuid
) from public, anon, authenticated;
grant execute on function private.pachanga_referee_can_read_wave4_invalidation_v1(
  uuid, uuid, uuid, uuid, uuid, uuid, text, uuid
) to authenticated;

drop policy if exists pachanga_referee_invalidations_select_v1
  on public.pachanga_referee_invalidations;
create policy pachanga_referee_invalidations_select_v1
on public.pachanga_referee_invalidations
for select to authenticated
using (private.pachanga_referee_can_read_wave4_invalidation_v1(
  referee_profile_id, club_id, target_user_id, target_group_id,
  canonical_match_id, competition_id, audience, (select auth.uid())
));

alter table public.pachanga_referee_assignment_revisions enable row level security;
revoke all on table public.pachanga_referee_assignment_revisions
  from public, anon, authenticated;
grant all on table public.pachanga_referee_assignment_revisions to service_role;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'public.get_my_pachanga_referee_assignments_v1()'::regprocedure,
    'public.get_pachanga_referee_assignment_beta_v1(uuid)'::regprocedure,
    'public.get_pachanga_referee_match_assignment_v1(uuid)'::regprocedure,
    'public.get_pachanga_referee_competition_desk_v1(uuid)'::regprocedure,
    'public.get_pachanga_referee_club_assignments_v1(uuid)'::regprocedure,
    'public.get_my_pachanga_referee_beta_v1()'::regprocedure,
    'public.get_pachanga_platform_referee_health_v1()'::regprocedure,
    'public.command_pachanga_referee_assignment_beta_admin_v1(uuid,bigint,text,jsonb,jsonb)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', signature);
    execute format('grant execute on function %s to authenticated', signature);
  end loop;
end;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_referee_flags_snapshot_v1()'::regprocedure,
    'private.pachanga_referee_public_snapshot_v1(uuid)'::regprocedure,
    'private.pachanga_referee_assignment_requester_can_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_referee_match_participant_can_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_referee_assignment_can_read_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_referee_assignment_can_view_terms_v1(uuid,uuid)'::regprocedure,
    'private.pachanga_referee_assignment_product_document_v1(uuid,boolean)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

comment on function public.get_my_pachanga_referee_assignments_v1() is
  'Private canonical assignment inbox. Offline clients may cache this response but never mutate it.';
comment on function public.get_pachanga_referee_match_assignment_v1(uuid) is
  'Match referee read model. Ordinary participants never receive proposal or fee details.';
comment on function public.get_pachanga_referee_competition_desk_v1(uuid) is
  'Competition referee desk for exact organizer/referee-manager authority.';
