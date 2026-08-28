-- Pachangas IQ Wave 7A: canonical public Competition read models.
-- These tables are derived caches. Competition, Entry, StandingSnapshot,
-- OfficialResultDecision and TournamentBracket remain the sporting authority.

set lock_timeout = '5s';
set statement_timeout = '120s';

create table public.pachanga_public_competition_read_models (
  publication_id uuid primary key
    references public.pachanga_competition_publications(id) on delete cascade,
  competition_id uuid not null unique
    references public.pachanga_competitions(id) on delete cascade,
  slug text not null unique,
  visibility text not null,
  lifecycle_status text not null,
  competition_type text not null,
  competition_status text not null,
  edition_status text,
  public_state text not null,
  registration_state text not null,
  registration_mode text not null,
  sport_format text,
  format_kind text,
  municipality text,
  general_area text,
  organizer_kind text not null,
  organizer_name text not null,
  starts_at date,
  ends_at date,
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,
  accepted_team_count integer not null default 0,
  team_capacity integer,
  available_places integer,
  waitlist_count integer not null default 0,
  is_indexable boolean not null default false,
  search_document tsvector not null,
  revision bigint not null,
  server_sequence bigint not null unique,
  public_snapshot jsonb not null,
  snapshot_checksum text not null,
  rebuilt_at timestamptz not null default clock_timestamp(),
  check (visibility in ('private', 'unlisted', 'public')),
  check (lifecycle_status in (
    'draft', 'pending_review', 'approved', 'published', 'rejected',
    'changes_requested', 'suspended', 'archived'
  )),
  check (competition_type in ('LEAGUE', 'TOURNAMENT')),
  check (public_state in ('UPCOMING', 'REGISTRATION_OPEN', 'IN_PROGRESS', 'FINISHED')),
  check (registration_state in ('OPEN', 'WAITLIST', 'CLOSED')),
  check (registration_mode in ('INVITE_ONLY', 'REQUEST_APPROVAL', 'CLOSED')),
  check (accepted_team_count >= 0 and waitlist_count >= 0),
  check (team_capacity is null or team_capacity >= 0),
  check (available_places is null or available_places >= 0),
  check (revision >= 1),
  check (jsonb_typeof(public_snapshot) = 'object'),
  check (length(snapshot_checksum) = 64)
);

create index pachanga_public_competition_directory_idx
  on public.pachanga_public_competition_read_models(
    is_indexable, public_state, starts_at, server_sequence desc, publication_id
  ) where is_indexable;
create index pachanga_public_competition_type_format_idx
  on public.pachanga_public_competition_read_models(
    competition_type, sport_format, registration_state, starts_at, publication_id
  ) where is_indexable;
create index pachanga_public_competition_area_idx
  on public.pachanga_public_competition_read_models(
    municipality, general_area, starts_at, publication_id
  ) where is_indexable;
create index pachanga_public_competition_search_idx
  on public.pachanga_public_competition_read_models using gin(search_document);

create table public.pachanga_public_competition_fixture_read_models (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null
    references public.pachanga_competition_publications(id) on delete cascade,
  competition_id uuid not null
    references public.pachanga_competitions(id) on delete cascade,
  competition_match_context_id uuid not null unique
    references public.pachanga_competition_match_contexts(id) on delete cascade,
  canonical_match_id uuid not null,
  edition_id uuid not null,
  stage_id uuid not null,
  round_id uuid,
  scheduled_start timestamptz,
  fixture_status text not null,
  has_official_result boolean not null default false,
  revision bigint not null,
  server_sequence bigint not null unique,
  public_snapshot jsonb not null,
  snapshot_checksum text not null,
  rebuilt_at timestamptz not null default clock_timestamp(),
  check (revision >= 1),
  check (jsonb_typeof(public_snapshot) = 'object'),
  check (length(snapshot_checksum) = 64)
);

create index pachanga_public_competition_fixture_calendar_idx
  on public.pachanga_public_competition_fixture_read_models(
    competition_id, scheduled_start, server_sequence, id
  );
create index pachanga_public_competition_fixture_round_idx
  on public.pachanga_public_competition_fixture_read_models(
    competition_id, round_id, scheduled_start, id
  );

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'pachanga_public_competition_read_models',
    'pachanga_public_competition_fixture_read_models'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from public, anon, authenticated', table_name);
    execute format('grant all on table public.%I to service_role', table_name);
  end loop;
end;
$$;

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
    'autoAccept', false
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

create or replace function private.pachanga_public_competition_team_v1(
  target_entry_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select case when entries.id is null then null else jsonb_strip_nulls(jsonb_build_object(
    'entryId', entries.id,
    'teamId', entries.team_id,
    'name', teams.name,
    'teamCode', teams.team_code,
    'status', entries.status,
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
  )) end
  from (select target_entry_id as id) target
  left join public.pachanga_competition_entries entries on entries.id = target.id
  left join public.pachanga_groups teams on teams.id = entries.team_id
  left join public.pachanga_team_crest_state crest_state on crest_state.group_id = entries.team_id
  left join public.pachanga_team_crest_versions versions on versions.id = crest_state.published_version_id;
$$;

create or replace function private.pachanga_public_competition_standings_v1(
  target_competition_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'stateId', source.state_id,
    'stageId', source.stage_id,
    'divisionId', source.division_id,
    'groupId', source.competition_group_id,
    'health', source.health_status,
    'snapshotId', source.snapshot_id,
    'sourceRevision', source.source_revision,
    'serverSequence', source.server_sequence,
    'generatedAt', source.generated_at,
    'tieBreakCriteria', source.tie_break_criteria,
    'rows', source.rows
  ) order by source.server_sequence desc, source.snapshot_id desc), '[]'::jsonb)
  from (
    select states.id as state_id, states.stage_id, states.division_id,
      states.competition_group_id, states.health_status,
      snapshots.id as snapshot_id, snapshots.source_revision,
      snapshots.server_sequence, snapshots.generated_at,
      snapshots.tie_break_criteria,
      coalesce((select jsonb_agg(jsonb_build_object(
        'entryId', rows.entry_id,
        'position', rows.position,
        'played', rows.played,
        'wins', rows.wins,
        'draws', rows.draws,
        'losses', rows.losses,
        'goalsFor', rows.goals_for,
        'goalsAgainst', rows.goals_against,
        'goalDifference', rows.goal_difference,
        'points', rows.effective_points,
        'tieBreakValues', rows.tie_break_values,
        'team', rows.team_snapshot
      ) order by rows.position, rows.server_sequence, rows.id)
      from public.pachanga_competition_standing_rows rows
      where rows.standing_snapshot_id = snapshots.id), '[]'::jsonb) as rows
    from public.pachanga_competition_standing_states states
    join public.pachanga_competition_standing_snapshots snapshots
      on snapshots.id = states.current_snapshot_id
    where states.competition_id = target_competition_id
  ) source;
$$;

create or replace function private.pachanga_public_competition_bracket_safe_v1(
  target_snapshot jsonb,
  allow_venue_detail boolean default false
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case when jsonb_typeof(target_snapshot) <> 'object' then null else
    jsonb_strip_nulls(jsonb_build_object(
      'kind', 'PublicCompetitionBracket',
      'competition', target_snapshot -> 'competition',
      'bracket', jsonb_strip_nulls(jsonb_build_object(
        'status', target_snapshot #>> '{bracket,status}',
        'format', target_snapshot #>> '{bracket,format}',
        'size', target_snapshot #> '{bracket,size}',
        'roundCount', target_snapshot #> '{bracket,roundCount}',
        'thirdPlaceEnabled', target_snapshot #> '{bracket,thirdPlaceEnabled}',
        'revision', target_snapshot #> '{bracket,revision}',
        'serverSequence', target_snapshot #> '{bracket,serverSequence}'
      )),
      'rounds', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'code', round_value ->> 'code',
        'order', round_value -> 'order',
        'label', round_value ->> 'label',
        'status', round_value ->> 'status',
        'nodes', coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', node_value ->> 'id',
          'roundCode', node_value ->> 'roundCode',
          'roundOrder', node_value -> 'roundOrder',
          'nodeOrder', node_value -> 'nodeOrder',
          'nodeKind', node_value ->> 'nodeKind',
          'status', node_value ->> 'status',
          'home', node_value -> 'home',
          'away', node_value -> 'away',
          'winner', node_value -> 'winner',
          'loser', node_value -> 'loser',
          'schedule', case when node_value -> 'reservation' is null then null else
            jsonb_strip_nulls(jsonb_build_object(
              'startsAt', node_value #> '{reservation,startsAt}',
              'endsAt', node_value #> '{reservation,endsAt}',
              'timezone', node_value #>> '{reservation,timezone}',
              'venueLabel', case when allow_venue_detail
                then node_value #>> '{reservation,venueLabel}' else null end
            )) end,
          'match', case when node_value -> 'match' is null then null else
            jsonb_strip_nulls(jsonb_build_object(
              'canonicalMatchId', node_value #>> '{match,canonicalMatchId}',
              'status', node_value #>> '{match,status}',
              'scheduledStart', node_value #> '{match,scheduledStart}',
              'scheduledEnd', node_value #> '{match,scheduledEnd}',
              'timezone', node_value #>> '{match,timezone}',
              'venueLabel', case when allow_venue_detail
                then node_value #>> '{match,venueLabel}' else null end,
              'outcome', node_value #>> '{match,outcome}',
              'scoreHome', node_value #> '{match,scoreHome}',
              'scoreAway', node_value #> '{match,scoreAway}',
              'extraTimePlayed', node_value #> '{match,extraTimePlayed}',
              'scoreAfterExtraTimeHome', node_value #> '{match,scoreAfterExtraTimeHome}',
              'scoreAfterExtraTimeAway', node_value #> '{match,scoreAfterExtraTimeAway}',
              'shootoutHome', node_value #> '{match,shootoutHome}',
              'shootoutAway', node_value #> '{match,shootoutAway}',
              'resolutionKind', node_value #>> '{match,resolutionKind}'
            )) end,
          'referee', node_value -> 'referee',
          'advance', case when node_value -> 'advance' is null then null else
            jsonb_strip_nulls(jsonb_build_object(
              'winnerEntryId', node_value #>> '{advance,winnerEntryId}',
              'loserEntryId', node_value #>> '{advance,loserEntryId}',
              'decidedAt', node_value #> '{advance,decidedAt}'
            )) end
        )) order by coalesce((node_value ->> 'nodeOrder')::integer, 0), node_value ->> 'id')
          from jsonb_array_elements(coalesce(round_value -> 'nodes', '[]'::jsonb)) node_value), '[]'::jsonb)
      )) order by coalesce((round_value ->> 'order')::integer, 0), round_value ->> 'code')
        from jsonb_array_elements(coalesce(target_snapshot -> 'rounds', '[]'::jsonb)) round_value), '[]'::jsonb),
      'summary', target_snapshot -> 'publicSafeSummary'
    )) end;
$$;

create or replace function private.pachanga_public_competition_fixture_snapshot_v1(
  target_context_id uuid,
  target_publication_id uuid,
  target_public_sections jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare round_row public.pachanga_competition_rounds%rowtype;
declare decision_row public.pachanga_competition_official_result_decisions%rowtype;
declare referee_value jsonb;
declare home_value jsonb;
declare away_value jsonb;
declare result_value jsonb;
begin
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id and contexts.status <> 'retired';
  if not found then return null; end if;

  if context_row.round_id is not null then
    select * into round_row from public.pachanga_competition_rounds rounds
    where rounds.id = context_row.round_id;
  end if;
  home_value := private.pachanga_public_competition_team_v1(context_row.home_entry_id);
  away_value := private.pachanga_public_competition_team_v1(context_row.away_entry_id);

  select decisions.* into decision_row
  from public.pachanga_competition_match_sheets sheets
  join public.pachanga_competition_official_result_decisions decisions
    on decisions.id = sheets.active_official_decision_id
  where sheets.competition_match_context_id = context_row.id;
  if decision_row.id is not null and coalesce((target_public_sections ->> 'results')::boolean, false) then
    result_value := jsonb_strip_nulls(jsonb_build_object(
      'status', 'OFFICIAL',
      'decisionId', decision_row.id,
      'outcome', decision_row.outcome,
      'scoreHome', decision_row.effective_score_home,
      'scoreAway', decision_row.effective_score_away,
      'explanation', nullif(decision_row.public_explanation, ''),
      'serverSequence', decision_row.server_sequence,
      'decidedAt', decision_row.decided_at
    ));
  else
    result_value := jsonb_build_object('status', 'PENDING');
  end if;

  if coalesce((target_public_sections ->> 'referees')::boolean, false) then
    select jsonb_strip_nulls(jsonb_build_object(
      'assignmentId', assignments.id,
      'status', upper(assignments.status),
      'role', assignments.assignment_role,
      'slug', profiles.slug,
      'displayName', profiles.public_display_name_snapshot,
      'avatar', profiles.public_avatar_snapshot,
      'verificationStatus', profiles.verification_status
    )) into referee_value
    from public.pachanga_referee_assignments assignments
    join public.pachanga_referee_profiles profiles
      on profiles.id = assignments.referee_profile_id
    where assignments.canonical_match_id = context_row.canonical_match_id
      and assignments.status in ('confirmed', 'completed')
      and profiles.visibility = 'public'
    order by assignments.revision desc, assignments.server_sequence desc, assignments.id desc
    limit 1;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'kind', 'PublicCompetitionFixture',
    'publicationId', target_publication_id,
    'competitionId', context_row.competition_id,
    'contextId', context_row.id,
    'canonicalMatchId', context_row.canonical_match_id,
    'editionId', context_row.edition_id,
    'stageId', context_row.stage_id,
    'round', case when round_row.id is null then null else jsonb_build_object(
      'id', round_row.id,
      'number', round_row.round_number,
      'name', round_row.display_name,
      'status', round_row.status
    ) end,
    'home', home_value,
    'away', away_value,
    'scheduledStart', context_row.scheduled_start,
    'scheduledEnd', context_row.scheduled_end,
    'timezone', context_row.timezone,
    'venue', case when coalesce((target_public_sections ->> 'venueDetail')::boolean, false)
      then jsonb_strip_nulls(jsonb_build_object(
        'label', context_row.venue_label,
        'status', context_row.venue_status
      )) else null end,
    'status', context_row.status,
    'result', result_value,
    'referee', referee_value,
    'revision', context_row.revision,
    'serverSequence', greatest(context_row.server_sequence, coalesce(decision_row.server_sequence, 0))
  ));
end;
$$;

create or replace function private.pachanga_public_competition_rebuild_fixtures_v1(
  target_competition_id uuid,
  target_server_sequence bigint
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare publication_row public.pachanga_competition_publications%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare snapshot_value jsonb;
declare checksum_value text;
declare source_sequence bigint;
declare rebuilt_count integer := 0;
begin
  select * into publication_row
  from public.pachanga_competition_publications publications
  where publications.competition_id = target_competition_id;
  if not found then return 0; end if;

  delete from public.pachanga_public_competition_fixture_read_models models
  where models.competition_id = target_competition_id
    and not exists (
      select 1 from public.pachanga_competition_match_contexts contexts
      where contexts.id = models.competition_match_context_id
        and contexts.status <> 'retired'
    );

  for context_row in
    select contexts.*
    from public.pachanga_competition_match_contexts contexts
    where contexts.competition_id = target_competition_id
      and contexts.status <> 'retired'
    order by contexts.server_sequence, contexts.id
  loop
    snapshot_value := private.pachanga_public_competition_fixture_snapshot_v1(
      context_row.id, publication_row.id, publication_row.public_sections
    );
    if snapshot_value is null then continue; end if;
    source_sequence := nextval('private.pachanga_competition_sequence');
    checksum_value := encode(extensions.digest(convert_to(snapshot_value::text, 'UTF8'), 'sha256'), 'hex');
    insert into public.pachanga_public_competition_fixture_read_models(
      publication_id, competition_id, competition_match_context_id,
      canonical_match_id, edition_id, stage_id, round_id, scheduled_start,
      fixture_status, has_official_result, revision, server_sequence,
      public_snapshot, snapshot_checksum, rebuilt_at
    ) values (
      publication_row.id, context_row.competition_id, context_row.id,
      context_row.canonical_match_id, context_row.edition_id, context_row.stage_id,
      context_row.round_id, context_row.scheduled_start, context_row.status,
      snapshot_value #>> '{result,status}' = 'OFFICIAL', context_row.revision,
      source_sequence, snapshot_value, checksum_value, clock_timestamp()
    )
    on conflict (competition_match_context_id) do update set
      publication_id = excluded.publication_id,
      canonical_match_id = excluded.canonical_match_id,
      edition_id = excluded.edition_id,
      stage_id = excluded.stage_id,
      round_id = excluded.round_id,
      scheduled_start = excluded.scheduled_start,
      fixture_status = excluded.fixture_status,
      has_official_result = excluded.has_official_result,
      revision = excluded.revision,
      server_sequence = excluded.server_sequence,
      public_snapshot = excluded.public_snapshot,
      snapshot_checksum = excluded.snapshot_checksum,
      rebuilt_at = excluded.rebuilt_at;
    rebuilt_count := rebuilt_count + 1;
  end loop;
  return rebuilt_count;
end;
$$;

create or replace function private.pachanga_public_competition_rebuild_v1(
  target_competition_id uuid,
  target_server_sequence bigint default 0
)
returns public.pachanga_public_competition_read_models
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare publication_row public.pachanga_competition_publications%rowtype;
declare competition_row public.pachanga_competitions%rowtype;
declare edition_row public.pachanga_competition_editions%rowtype;
declare category_row public.pachanga_competition_categories%rowtype;
declare rule_revision public.pachanga_competition_rule_revisions%rowtype;
declare model_row public.pachanga_public_competition_read_models%rowtype;
declare organizer_name_value text;
declare organizer_value jsonb;
declare teams_value jsonb;
declare standings_value jsonb;
declare bracket_value jsonb;
declare champion_value jsonb;
declare snapshot_value jsonb;
declare checksum_value text;
declare team_count_value integer;
declare capacity_value integer;
declare waitlist_value integer;
declare available_value integer;
declare state_value text;
declare registration_value text;
declare sequence_value bigint;
declare municipality_value text;
declare area_value text;
declare format_value text;
declare search_value text;
begin
  select * into publication_row
  from public.pachanga_competition_publications publications
  where publications.competition_id = target_competition_id;
  if not found then
    delete from public.pachanga_public_competition_read_models models
    where models.competition_id = target_competition_id;
    return null;
  end if;
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = publication_row.competition_id;
  select * into edition_row from public.pachanga_competition_editions editions
  where editions.id = publication_row.edition_id;
  select * into category_row from public.pachanga_competition_categories categories
  where categories.id = publication_row.category_id;
  if edition_row.rule_revision_id is not null then
    select * into rule_revision from public.pachanga_competition_rule_revisions revisions
    where revisions.id = edition_row.rule_revision_id;
  end if;

  select count(*)::integer into team_count_value
  from public.pachanga_competition_entries entries
  where entries.edition_id = publication_row.edition_id
    and entries.category_id = publication_row.category_id
    and entries.status in ('accepted', 'active', 'completed');
  select count(*)::integer into waitlist_value
  from public.pachanga_competition_registration_requests requests
  where requests.edition_id = publication_row.edition_id
    and requests.category_id = publication_row.category_id
    and requests.status = 'waitlisted';
  capacity_value := nullif(rule_revision.rule_document #>>
    '{registration,registrationPolicy,teamLimits,maximum}', '')::integer;
  available_value := case when capacity_value is null then null
    else greatest(capacity_value - team_count_value, 0) end;

  state_value := case
    when edition_row.status in ('completed', 'archived') then 'FINISHED'
    when edition_row.status = 'active' then 'IN_PROGRESS'
    when edition_row.status = 'registration_open' then 'REGISTRATION_OPEN'
    else 'UPCOMING' end;
  registration_value := case
    when edition_row.registration_mode = 'REQUEST_APPROVAL'
      and edition_row.status = 'registration_open'
      and (edition_row.registration_opens_at is null or edition_row.registration_opens_at <= clock_timestamp())
      and (edition_row.registration_closes_at is null or edition_row.registration_closes_at > clock_timestamp())
      and (available_value is null or available_value > 0) then 'OPEN'
    when edition_row.registration_mode = 'REQUEST_APPROVAL'
      and edition_row.status = 'registration_open'
      and publication_row.public_sections ? 'teams'
      and (available_value = 0 or waitlist_value > 0) then 'WAITLIST'
    else 'CLOSED' end;

  municipality_value := nullif(trim(publication_row.public_profile ->> 'municipality'), '');
  area_value := coalesce(nullif(trim(publication_row.public_profile ->> 'generalArea'), ''), competition_row.general_area);
  format_value := nullif(trim(publication_row.public_profile ->> 'format'), '');

  if competition_row.organizer_kind = 'CLUB' then
    select clubs.name,
      jsonb_strip_nulls(jsonb_build_object(
        'kind', 'CLUB', 'id', clubs.id, 'name', clubs.name, 'slug', clubs.slug,
        'logo', clubs.logo_asset, 'verificationStatus', clubs.verification_status,
        'municipality', clubs.municipality, 'generalArea', clubs.general_area
      )) into organizer_name_value, organizer_value
    from public.pachanga_clubs clubs where clubs.id = competition_row.organizer_club_id;
  else
    select teams.name,
      jsonb_build_object('kind', 'TEAM', 'id', teams.id, 'name', teams.name, 'teamCode', teams.team_code)
      into organizer_name_value, organizer_value
    from public.pachanga_groups teams where teams.id = competition_row.organizer_group_id;
  end if;

  select coalesce(jsonb_agg(private.pachanga_public_competition_team_v1(entries.id)
    order by teams.name, entries.server_sequence, entries.id), '[]'::jsonb)
  into teams_value
  from public.pachanga_competition_entries entries
  join public.pachanga_groups teams on teams.id = entries.team_id
  where entries.edition_id = publication_row.edition_id
    and entries.category_id = publication_row.category_id
    and entries.status in ('accepted', 'active', 'completed');

  standings_value := case
    when coalesce((publication_row.public_sections ->> 'standings')::boolean, false)
      then private.pachanga_public_competition_standings_v1(competition_row.id)
    else '[]'::jsonb end;
  select case when models.competition_id is null then null else
    private.pachanga_public_competition_bracket_safe_v1(
      models.public_snapshot,
      coalesce((publication_row.public_sections ->> 'venueDetail')::boolean, false)
    ) end
  into bracket_value
  from public.pachanga_tournament_knockout_read_models models
  where models.competition_id = competition_row.id;
  if not coalesce((publication_row.public_sections ->> 'bracket')::boolean, false) then
    bracket_value := null;
  end if;
  champion_value := case when bracket_value is null then null
    else bracket_value #> '{publicSafeSummary,champion}' end;

  sequence_value := greatest(target_server_sequence, publication_row.server_sequence,
    competition_row.server_sequence, coalesce(edition_row.server_sequence, 0),
    coalesce(category_row.server_sequence, 0));
  snapshot_value := jsonb_strip_nulls(jsonb_build_object(
    'kind', 'PublicCompetitionView',
    'publication', jsonb_build_object(
      'id', publication_row.id,
      'slug', publication_row.slug,
      'visibility', publication_row.visibility,
      'status', publication_row.lifecycle_status,
      'organizerVerified', publication_row.organizer_verified,
      'revision', publication_row.revision,
      'serverSequence', publication_row.server_sequence,
      'publishedAt', publication_row.published_at
    ),
    'competition', jsonb_strip_nulls(jsonb_build_object(
      'id', competition_row.id,
      'name', coalesce(nullif(publication_row.public_profile ->> 'name', ''), competition_row.name),
      'description', coalesce(nullif(publication_row.public_profile ->> 'description', ''), competition_row.description),
      'image', coalesce(nullif(publication_row.public_profile ->> 'imageUrl', ''), competition_row.image_url),
      'type', competition_row.competition_type,
      'status', competition_row.status,
      'publicState', state_value,
      'municipality', municipality_value,
      'generalArea', area_value,
      'startsAt', edition_row.starts_at,
      'endsAt', edition_row.ends_at,
      'format', format_value,
      'badge', nullif(publication_row.public_profile ->> 'badge', ''),
      'rulesSummary', nullif(publication_row.public_profile ->> 'rulesSummary', ''),
      'champion', champion_value
    )),
    'organizer', organizer_value,
    'edition', jsonb_strip_nulls(jsonb_build_object(
      'id', edition_row.id, 'name', edition_row.name,
      'seasonLabel', edition_row.season_label, 'status', edition_row.status,
      'startsAt', edition_row.starts_at, 'endsAt', edition_row.ends_at,
      'revision', edition_row.revision
    )),
    'category', jsonb_strip_nulls(jsonb_build_object(
      'id', category_row.id, 'name', category_row.name,
      'description', category_row.description, 'sportFormat', category_row.sport_format,
      'levelLabel', category_row.level_label, 'revision', category_row.revision
    )),
    'registration', jsonb_strip_nulls(jsonb_build_object(
      'mode', case when edition_row.registration_mode = 'REQUEST_APPROVAL'
        then 'REQUEST_APPROVAL' when edition_row.registration_mode = 'INVITE_ONLY'
        then 'INVITE_ONLY' else 'CLOSED' end,
      'state', registration_value,
      'opensAt', edition_row.registration_opens_at,
      'closesAt', edition_row.registration_closes_at,
      'teamCount', team_count_value,
      'teamCapacity', capacity_value,
      'availablePlaces', available_value,
      'waitlistCount', waitlist_value
    )),
    'sections', publication_row.public_sections || jsonb_build_object('discipline', false),
    'teams', case when coalesce((publication_row.public_sections ->> 'teams')::boolean, false)
      then teams_value else '[]'::jsonb end,
    'standings', standings_value,
    'bracket', bracket_value,
    'flags', private.pachanga_public_competition_flags_v1(),
    'privacy', jsonb_build_object(
      'containsRoster', false, 'containsAttendance', false, 'containsContactData', false,
      'containsEvidence', false, 'containsFees', false, 'containsPrivateLocation', false
    ),
    'cache', jsonb_build_object(
      'entityType', 'public_competition', 'entityId', publication_row.id,
      'revision', publication_row.revision, 'serverSequence', sequence_value,
      'updatedAt', greatest(publication_row.updated_at, competition_row.updated_at,
        edition_row.updated_at, category_row.updated_at)
    )
  ));
  checksum_value := encode(extensions.digest(convert_to(snapshot_value::text, 'UTF8'), 'sha256'), 'hex');
  search_value := concat_ws(' ', competition_row.name, organizer_name_value,
    municipality_value, area_value, category_row.sport_format, category_row.name,
    publication_row.public_profile ->> 'description');

  insert into public.pachanga_public_competition_read_models(
    publication_id, competition_id, slug, visibility, lifecycle_status,
    competition_type, competition_status, edition_status, public_state,
    registration_state, registration_mode, sport_format, format_kind,
    municipality, general_area, organizer_kind, organizer_name, starts_at, ends_at,
    registration_opens_at, registration_closes_at, accepted_team_count,
    team_capacity, available_places, waitlist_count, is_indexable,
    search_document, revision, server_sequence, public_snapshot,
    snapshot_checksum, rebuilt_at
  ) values (
    publication_row.id, competition_row.id, publication_row.slug,
    publication_row.visibility, publication_row.lifecycle_status,
    competition_row.competition_type, competition_row.status, edition_row.status,
    state_value, registration_value,
    case when edition_row.registration_mode = 'REQUEST_APPROVAL' then 'REQUEST_APPROVAL'
      when edition_row.registration_mode = 'INVITE_ONLY' then 'INVITE_ONLY' else 'CLOSED' end,
    category_row.sport_format, format_value, municipality_value, area_value,
    competition_row.organizer_kind, organizer_name_value, edition_row.starts_at,
    edition_row.ends_at, edition_row.registration_opens_at,
    edition_row.registration_closes_at, team_count_value, capacity_value,
    available_value, waitlist_value,
    publication_row.visibility = 'public' and publication_row.lifecycle_status = 'published',
    to_tsvector('simple', coalesce(search_value, '')), publication_row.revision,
    sequence_value, snapshot_value, checksum_value, clock_timestamp()
  )
  on conflict (publication_id) do update set
    competition_id = excluded.competition_id,
    slug = excluded.slug,
    visibility = excluded.visibility,
    lifecycle_status = excluded.lifecycle_status,
    competition_type = excluded.competition_type,
    competition_status = excluded.competition_status,
    edition_status = excluded.edition_status,
    public_state = excluded.public_state,
    registration_state = excluded.registration_state,
    registration_mode = excluded.registration_mode,
    sport_format = excluded.sport_format,
    format_kind = excluded.format_kind,
    municipality = excluded.municipality,
    general_area = excluded.general_area,
    organizer_kind = excluded.organizer_kind,
    organizer_name = excluded.organizer_name,
    starts_at = excluded.starts_at,
    ends_at = excluded.ends_at,
    registration_opens_at = excluded.registration_opens_at,
    registration_closes_at = excluded.registration_closes_at,
    accepted_team_count = excluded.accepted_team_count,
    team_capacity = excluded.team_capacity,
    available_places = excluded.available_places,
    waitlist_count = excluded.waitlist_count,
    is_indexable = excluded.is_indexable,
    search_document = excluded.search_document,
    revision = excluded.revision,
    server_sequence = excluded.server_sequence,
    public_snapshot = excluded.public_snapshot,
    snapshot_checksum = excluded.snapshot_checksum,
    rebuilt_at = excluded.rebuilt_at
  returning * into model_row;
  perform private.pachanga_public_competition_rebuild_fixtures_v1(
    competition_row.id, sequence_value
  );
  return model_row;
end;
$$;

create or replace function public.get_pachanga_public_competition_directory_v1(
  search_text text default null,
  competition_type_filter text default null,
  sport_format_filter text default null,
  state_filter text default null,
  area_filter text default null,
  registration_filter text default null,
  page_size integer default 24,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare normalized_search text := nullif(trim(coalesce(search_text, '')), '');
declare normalized_type text := nullif(upper(trim(coalesce(competition_type_filter, ''))), '');
declare normalized_format text := nullif(upper(trim(coalesce(sport_format_filter, ''))), '');
declare normalized_state text := nullif(upper(trim(coalesce(state_filter, ''))), '');
declare normalized_area text := nullif(trim(coalesce(area_filter, '')), '');
declare normalized_registration text := nullif(upper(trim(coalesce(registration_filter, ''))), '');
begin
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  if not settings.public_competition_foundation_enabled
     or not settings.public_competition_discovery_enabled then
    raise exception 'PUBLIC_COMPETITION_DISCOVERY_DISABLED' using errcode = '42501';
  end if;
  if page_size < 1 or page_size > 60 or page_offset < 0 or page_offset > 100000 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  if normalized_type is not null and normalized_type not in ('LEAGUE', 'TOURNAMENT') then
    raise exception 'INVALID_COMPETITION_TYPE_FILTER' using errcode = '22023';
  end if;
  if normalized_state is not null and normalized_state not in
    ('UPCOMING', 'REGISTRATION_OPEN', 'IN_PROGRESS', 'FINISHED') then
    raise exception 'INVALID_COMPETITION_STATE_FILTER' using errcode = '22023';
  end if;
  if normalized_registration is not null and normalized_registration not in ('OPEN', 'WAITLIST', 'CLOSED') then
    raise exception 'INVALID_REGISTRATION_FILTER' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'kind', 'PublicCompetitionDirectory',
    'items', coalesce((select jsonb_agg(source.public_snapshot order by source.starts_at nulls last,
      source.server_sequence desc, source.publication_id)
      from (
        select models.*
        from public.pachanga_public_competition_read_models models
        where models.is_indexable
          and (normalized_search is null or models.search_document @@ plainto_tsquery('simple', normalized_search))
          and (normalized_type is null or models.competition_type = normalized_type)
          and (normalized_format is null or upper(models.sport_format) = normalized_format)
          and (normalized_state is null or models.public_state = normalized_state)
          and (normalized_area is null or models.municipality ilike '%' || normalized_area || '%'
            or models.general_area ilike '%' || normalized_area || '%')
          and (normalized_registration is null or models.registration_state = normalized_registration)
        order by models.starts_at nulls last, models.server_sequence desc, models.publication_id
        limit page_size offset page_offset
      ) source), '[]'::jsonb),
    'total', (select count(*) from public.pachanga_public_competition_read_models models
      where models.is_indexable
        and (normalized_search is null or models.search_document @@ plainto_tsquery('simple', normalized_search))
        and (normalized_type is null or models.competition_type = normalized_type)
        and (normalized_format is null or upper(models.sport_format) = normalized_format)
        and (normalized_state is null or models.public_state = normalized_state)
        and (normalized_area is null or models.municipality ilike '%' || normalized_area || '%'
          or models.general_area ilike '%' || normalized_area || '%')
        and (normalized_registration is null or models.registration_state = normalized_registration)),
    'pageSize', page_size,
    'pageOffset', page_offset,
    'filters', jsonb_strip_nulls(jsonb_build_object(
      'search', normalized_search, 'type', normalized_type,
      'sportFormat', normalized_format, 'state', normalized_state,
      'area', normalized_area, 'registration', normalized_registration
    )),
    'cache', jsonb_build_object(
      'maxServerSequence', coalesce((select max(models.server_sequence)
        from public.pachanga_public_competition_read_models models where models.is_indexable), 0),
      'generatedAt', statement_timestamp()
    )
  );
end;
$$;

create or replace function public.get_pachanga_public_competition_v1(target_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare selected public.pachanga_public_competition_read_models%rowtype;
begin
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  if not settings.public_competition_foundation_enabled
     or not settings.public_competition_publication_enabled then
    raise exception 'PUBLIC_COMPETITION_DISABLED' using errcode = '42501';
  end if;
  select * into selected
  from public.pachanga_public_competition_read_models models
  where models.slug = lower(trim(coalesce(target_slug, '')))
    and models.visibility in ('public', 'unlisted')
    and models.lifecycle_status = 'published';
  if not found then raise exception 'PUBLIC_COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  return selected.public_snapshot;
end;
$$;

create or replace function public.get_pachanga_public_competition_calendar_v1(
  target_slug text,
  page_size integer default 50,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare selected public.pachanga_public_competition_read_models%rowtype;
begin
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  if not settings.public_competition_foundation_enabled
     or not settings.public_competition_calendar_enabled then
    raise exception 'PUBLIC_COMPETITION_CALENDAR_DISABLED' using errcode = '42501';
  end if;
  if page_size < 1 or page_size > 100 or page_offset < 0 then
    raise exception 'INVALID_PAGINATION' using errcode = '22023';
  end if;
  select * into selected from public.pachanga_public_competition_read_models models
  where models.slug = lower(trim(coalesce(target_slug, '')))
    and models.visibility in ('public', 'unlisted')
    and models.lifecycle_status = 'published'
    and coalesce((models.public_snapshot #>> '{sections,calendar}')::boolean, false);
  if not found then raise exception 'PUBLIC_CALENDAR_NOT_FOUND' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'kind', 'PublicCompetitionCalendar',
    'competitionId', selected.competition_id,
    'slug', selected.slug,
    'items', coalesce((select jsonb_agg(source.public_snapshot order by
      source.scheduled_start nulls last, source.server_sequence, source.id)
      from (
        select fixtures.*
        from public.pachanga_public_competition_fixture_read_models fixtures
        where fixtures.competition_id = selected.competition_id
        order by fixtures.scheduled_start nulls last, fixtures.server_sequence, fixtures.id
        limit page_size offset page_offset
      ) source), '[]'::jsonb),
    'total', (select count(*) from public.pachanga_public_competition_fixture_read_models fixtures
      where fixtures.competition_id = selected.competition_id),
    'pageSize', page_size,
    'pageOffset', page_offset,
    'revision', selected.revision,
    'serverSequence', selected.server_sequence
  );
end;
$$;

create or replace function public.get_pachanga_public_competition_standings_v1(target_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare selected public.pachanga_public_competition_read_models%rowtype;
begin
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  if not settings.public_competition_standings_enabled then
    raise exception 'PUBLIC_COMPETITION_STANDINGS_DISABLED' using errcode = '42501';
  end if;
  select * into selected from public.pachanga_public_competition_read_models models
  where models.slug = lower(trim(coalesce(target_slug, '')))
    and models.visibility in ('public', 'unlisted')
    and models.lifecycle_status = 'published'
    and coalesce((models.public_snapshot #>> '{sections,standings}')::boolean, false);
  if not found then raise exception 'PUBLIC_STANDINGS_NOT_FOUND' using errcode = 'P0002'; end if;
  return jsonb_build_object(
    'kind', 'PublicCompetitionStandings', 'competitionId', selected.competition_id,
    'slug', selected.slug, 'items', selected.public_snapshot -> 'standings',
    'revision', selected.revision, 'serverSequence', selected.server_sequence
  );
end;
$$;

create or replace function public.get_pachanga_public_competition_bracket_v1(target_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare selected public.pachanga_public_competition_read_models%rowtype;
begin
  select * into settings from private.pachanga_competition_foundation_settings where singleton;
  if not settings.public_competition_bracket_enabled then
    raise exception 'PUBLIC_COMPETITION_BRACKET_DISABLED' using errcode = '42501';
  end if;
  select * into selected from public.pachanga_public_competition_read_models models
  where models.slug = lower(trim(coalesce(target_slug, '')))
    and models.visibility in ('public', 'unlisted')
    and models.lifecycle_status = 'published'
    and coalesce((models.public_snapshot #>> '{sections,bracket}')::boolean, false);
  if not found or selected.public_snapshot -> 'bracket' is null then
    raise exception 'PUBLIC_BRACKET_NOT_FOUND' using errcode = 'P0002';
  end if;
  return selected.public_snapshot -> 'bracket';
end;
$$;

create or replace function public.get_pachanga_public_competition_sitemap_v1()
returns table(slug text, updated_at timestamptz)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select models.slug, models.rebuilt_at
  from public.pachanga_public_competition_read_models models
  join private.pachanga_competition_foundation_settings settings on settings.singleton
  where settings.public_competition_foundation_enabled
    and settings.public_competition_discovery_enabled
    and models.is_indexable
  order by models.rebuilt_at desc, models.publication_id;
$$;

do $$
declare signature regprocedure;
begin
  foreach signature in array array[
    'private.pachanga_public_competition_flags_v1()'::regprocedure,
    'private.pachanga_public_competition_team_v1(uuid)'::regprocedure,
    'private.pachanga_public_competition_standings_v1(uuid)'::regprocedure,
    'private.pachanga_public_competition_bracket_safe_v1(jsonb,boolean)'::regprocedure,
    'private.pachanga_public_competition_fixture_snapshot_v1(uuid,uuid,jsonb)'::regprocedure,
    'private.pachanga_public_competition_rebuild_fixtures_v1(uuid,bigint)'::regprocedure,
    'private.pachanga_public_competition_rebuild_v1(uuid,bigint)'::regprocedure
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', signature);
  end loop;
end;
$$;

revoke all on function public.get_pachanga_public_competition_directory_v1(
  text, text, text, text, text, text, integer, integer
) from public;
revoke all on function public.get_pachanga_public_competition_v1(text) from public;
revoke all on function public.get_pachanga_public_competition_calendar_v1(text, integer, integer) from public;
revoke all on function public.get_pachanga_public_competition_standings_v1(text) from public;
revoke all on function public.get_pachanga_public_competition_bracket_v1(text) from public;
revoke all on function public.get_pachanga_public_competition_sitemap_v1() from public;

grant execute on function public.get_pachanga_public_competition_directory_v1(
  text, text, text, text, text, text, integer, integer
) to anon, authenticated, service_role;
grant execute on function public.get_pachanga_public_competition_v1(text)
  to anon, authenticated, service_role;
grant execute on function public.get_pachanga_public_competition_calendar_v1(text, integer, integer)
  to anon, authenticated, service_role;
grant execute on function public.get_pachanga_public_competition_standings_v1(text)
  to anon, authenticated, service_role;
grant execute on function public.get_pachanga_public_competition_bracket_v1(text)
  to anon, authenticated, service_role;
grant execute on function public.get_pachanga_public_competition_sitemap_v1()
  to anon, authenticated, service_role;

comment on table public.pachanga_public_competition_read_models is
  'Wave 7A public directory/hub cache. It is rebuilt from canonical authority and contains no roster, Attendance, contact, evidence or fee data.';
comment on table public.pachanga_public_competition_fixture_read_models is
  'Wave 7A safe fixture cache. Only the active OfficialResultDecision can appear as an official result.';
