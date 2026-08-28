\set ON_ERROR_STOP on

begin;

insert into public.pachanga_groups(
  id, owner_id, name, team_code, payload, payload_revision
)
values (
  md5('wave7a-team-10')::uuid,
  md5('wave7a-user-10')::uuid,
  'Wave 7A Team 10',
  'W7A00010',
  jsonb_build_object(
    'matches', '[]'::jsonb,
    'players', '[]'::jsonb
  ),
  1
);

insert into public.pachanga_group_members(
  group_id, user_id, role, display_name
)
values (
  md5('wave7a-team-10')::uuid,
  md5('wave7a-user-10')::uuid,
  'owner',
  'Wave 7A Owner 10'
);
set local statement_timeout = '15min';
set local lock_timeout = '10s';

create or replace function pg_temp.stable_uuid(value text)
returns uuid language sql immutable as $$ select md5(value)::uuid $$;

create temporary table wave7a_scale_timings(
  metric text not null,
  elapsed_ms numeric not null
);

update private.pachanga_competition_foundation_settings settings set
  public_competition_foundation_enabled = true,
  public_competition_publication_enabled = true,
  public_competition_discovery_enabled = true,
  public_competition_registration_requests_enabled = true,
  public_competition_waitlist_enabled = true,
  public_competition_calendar_enabled = true,
  public_competition_results_enabled = true,
  public_competition_standings_enabled = true,
  public_competition_bracket_enabled = true,
  public_competition_exception_status_enabled = true,
  public_competition_referee_display_enabled = true,
  public_competition_discipline_enabled = false,
  public_competition_auto_accept_enabled = false,
  revision = settings.revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_at = clock_timestamp()
where settings.singleton;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, competition_type,
  visibility, status, created_by
)
select pg_temp.stable_uuid('wave7a-scale-competition:' || value),
  'TEAM', md5('wave7a-team-0')::uuid,
  'Wave 7A Scale Competition ' || value,
  'wave7a-scale-competition-' || value,
  case when value % 2 = 0 then 'TOURNAMENT' else 'LEAGUE' end,
  'public', 'draft', md5('wave7a-user-0')::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_rule_sets(
  id, competition_id, name, status, created_by
)
select pg_temp.stable_uuid('wave7a-scale-rule-set:' || value),
  pg_temp.stable_uuid('wave7a-scale-competition:' || value),
  'Wave 7A Scale Rules', 'active', md5('wave7a-user-0')::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, reason, created_by
)
select pg_temp.stable_uuid('wave7a-scale-rule-revision:' || value),
  pg_temp.stable_uuid('wave7a-scale-rule-set:' || value),
  1, 'competition_rules.v1', source.document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', source.document),
  clock_timestamp(), 'future_only', 'frozen', 'Wave 7A scale fixture',
  md5('wave7a-user-0')::uuid
from generate_series(1, 10000) value
cross join lateral (select '{
  "format":{"modality":"futbol7"},
  "registration":{"registrationPolicy":{"teamLimits":{"minimum":2,"maximum":16}}},
  "structure":{},"operations":{},"results":{},"discipline":{},
  "governance":{},"publication":{},"futureCapabilities":{}
}'::jsonb document) source;

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_rule_revision_id,
  registration_opens_at, registration_closes_at, created_by
)
select pg_temp.stable_uuid('wave7a-scale-edition:' || value),
  pg_temp.stable_uuid('wave7a-scale-competition:' || value),
  'Scale 2027', '2027', '2027-01-01', '2027-12-31',
  'registration_open', pg_temp.stable_uuid('wave7a-scale-rule-revision:' || value),
  'REQUEST_APPROVAL', pg_temp.stable_uuid('wave7a-scale-rule-revision:' || value),
  '2026-01-01T00:00:00Z', '2029-01-01T00:00:00Z', md5('wave7a-user-0')::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, visibility, status,
  rule_revision_id, created_by
)
select pg_temp.stable_uuid('wave7a-scale-category:' || value),
  pg_temp.stable_uuid('wave7a-scale-edition:' || value),
  'Senior', 'senior', 'FOOTBALL_7', 'public', 'active',
  pg_temp.stable_uuid('wave7a-scale-rule-revision:' || value),
  md5('wave7a-user-0')::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, created_by
)
select pg_temp.stable_uuid('wave7a-scale-stage:' || value),
  pg_temp.stable_uuid('wave7a-scale-edition:' || value),
  'Fase principal', case when value % 2 = 0 then 'KNOCKOUT' else 'LEAGUE_STAGE' end,
  0, false, 'draft', pg_temp.stable_uuid('wave7a-scale-rule-revision:' || value),
  md5('wave7a-user-0')::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_entries(
  id, competition_id, edition_id, category_id, team_id, entry_source,
  status, rule_revision_id, submitted_by, accepted_by, submitted_at,
  accepted_at, reason_code, created_by
)
select pg_temp.stable_uuid('wave7a-scale-entry:' || value),
  pg_temp.stable_uuid('wave7a-scale-competition:' || value),
  pg_temp.stable_uuid('wave7a-scale-edition:' || value),
  pg_temp.stable_uuid('wave7a-scale-category:' || value),
  md5('wave7a-team-1')::uuid, 'PUBLIC_APPLICATION', 'accepted',
  pg_temp.stable_uuid('wave7a-scale-rule-revision:' || value),
  md5('wave7a-user-1')::uuid, md5('wave7a-user-0')::uuid,
  clock_timestamp(), clock_timestamp(), 'wave7a.scale.accepted',
  md5('wave7a-user-1')::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_publications(
  id, competition_id, edition_id, category_id, slug, visibility,
  lifecycle_status, public_profile, public_sections, content_fingerprint,
  revision, created_by, updated_by
)
select pg_temp.stable_uuid('wave7a-scale-publication:' || value),
  pg_temp.stable_uuid('wave7a-scale-competition:' || value),
  pg_temp.stable_uuid('wave7a-scale-edition:' || value),
  pg_temp.stable_uuid('wave7a-scale-category:' || value),
  'wave7a-scale-competition-' || value, 'public', 'draft',
  jsonb_build_object(
    'name', 'Wave 7A Scale Competition ' || value,
    'description', 'Public scale fixture without personal data.',
    'municipality', case when value % 2 = 0 then 'Barcelona' else 'Terrassa' end,
    'generalArea', 'Barcelona', 'format', case when value % 2 = 0 then 'Eliminatoria' else 'Liga' end
  ),
  jsonb_build_object(
    'teams', true, 'calendar', true, 'results', true, 'standings', true,
    'bracket', true, 'referees', true, 'venueDetail', false, 'discipline', false
  ),
  encode(extensions.digest(convert_to('wave7a-scale-publication:' || value, 'UTF8'), 'sha256'), 'hex'),
  1, md5('wave7a-user-0')::uuid, md5('wave7a-user-0')::uuid
from generate_series(1, 10000) value;

insert into public.pachanga_competition_publication_consents(
  id, publication_id, competition_id, consent_version, consent_number,
  content_fingerprint, purpose, statements, public_sections_snapshot,
  status, actor_id, operation_id
)
select pg_temp.stable_uuid('wave7a-scale-consent:' || value),
  pg_temp.stable_uuid('wave7a-scale-publication:' || value),
  pg_temp.stable_uuid('wave7a-scale-competition:' || value),
  'public-competition-consent.v1', 1,
  encode(extensions.digest(convert_to('wave7a-scale-publication:' || value, 'UTF8'), 'sha256'), 'hex'),
  'Wave 7A representative scale consent',
  '{"authorizedRepresentative":true,"informationAccurate":true,"teamAssetsAuthorized":true,"indexingAccepted":true}'::jsonb,
  '{"teams":true,"calendar":true,"results":true,"standings":true,"bracket":true,"referees":true,"venueDetail":false,"discipline":false}'::jsonb,
  'current', md5('wave7a-user-0')::uuid,
  pg_temp.stable_uuid('wave7a-scale-consent-operation:' || value)
from generate_series(1, 10000) value;

update public.pachanga_competition_publications publications set
  current_consent_id = pg_temp.stable_uuid('wave7a-scale-consent:' || source.value),
  lifecycle_status = 'published', submitted_at = clock_timestamp(),
  approved_at = clock_timestamp(), published_at = clock_timestamp(),
  updated_at = clock_timestamp()
from generate_series(1, 10000) source(value)
where publications.id = pg_temp.stable_uuid('wave7a-scale-publication:' || source.value);

alter table public.pachanga_competition_registration_requests disable trigger user;
insert into public.pachanga_competition_registration_requests(
  id, publication_id, competition_id, edition_id, category_id, team_id,
  requested_by, status, message, team_snapshot, capacity_snapshot,
  rule_revision_id, entry_id, waitlist_position, reason_code,
  public_reason, private_reason, created_operation_id, revision,
  submitted_at, reviewed_at, accepted_at, rejected_at, waitlisted_at, updated_at
)
select pg_temp.stable_uuid('wave7a-scale-request:' || competition_number || ':' || request_number),
  pg_temp.stable_uuid('wave7a-scale-publication:' || competition_number),
  pg_temp.stable_uuid('wave7a-scale-competition:' || competition_number),
  pg_temp.stable_uuid('wave7a-scale-edition:' || competition_number),
  pg_temp.stable_uuid('wave7a-scale-category:' || competition_number),
  md5('wave7a-team-' || request_number)::uuid,
  md5('wave7a-user-' || request_number)::uuid,
  case when request_number = 1 then 'accepted'
    when request_number in (2, 3) then 'waitlisted' else 'rejected' end,
  'Representative request ' || request_number,
  jsonb_build_object('teamId', md5('wave7a-team-' || request_number)::uuid,
    'name', 'Wave 7A Team ' || request_number, 'teamCode', 'SCALE' || request_number),
  '{"capacity":16,"accepted":1,"available":15}'::jsonb,
  pg_temp.stable_uuid('wave7a-scale-rule-revision:' || competition_number),
  case when request_number = 1
    then pg_temp.stable_uuid('wave7a-scale-entry:' || competition_number) end,
  case when request_number in (2, 3) then request_number - 1 end,
  'wave7a.scale.request',
  case when request_number > 3 then 'Solicitud no seleccionada.' else '' end,
  '', pg_temp.stable_uuid('wave7a-scale-request-operation:' || competition_number || ':' || request_number),
  1, clock_timestamp(), clock_timestamp(),
  case when request_number = 1 then clock_timestamp() end,
  case when request_number > 3 then clock_timestamp() end,
  case when request_number in (2, 3) then clock_timestamp() end,
  clock_timestamp()
from generate_series(1, 10000) competition_number
cross join generate_series(1, 10) request_number;
alter table public.pachanga_competition_registration_requests enable trigger user;

with source as (
  select value,
    jsonb_build_object(
      'kind', 'PublicCompetitionView',
      'publication', jsonb_build_object(
        'id', pg_temp.stable_uuid('wave7a-scale-publication:' || value),
        'slug', 'wave7a-scale-competition-' || value,
        'visibility', 'public', 'status', 'published', 'revision', 1,
        'serverSequence', value
      ),
      'competition', jsonb_build_object(
        'id', pg_temp.stable_uuid('wave7a-scale-competition:' || value),
        'name', 'Wave 7A Scale Competition ' || value,
        'type', case when value % 2 = 0 then 'TOURNAMENT' else 'LEAGUE' end,
        'status', 'draft', 'publicState', 'REGISTRATION_OPEN',
        'municipality', case when value % 2 = 0 then 'Barcelona' else 'Terrassa' end,
        'generalArea', 'Barcelona', 'startsAt', '2027-01-01', 'endsAt', '2027-12-31',
        'format', case when value % 2 = 0 then 'Eliminatoria' else 'Liga' end
      ),
      'organizer', jsonb_build_object('kind', 'TEAM', 'name', 'Wave 7A Organizer'),
      'edition', jsonb_build_object('id', pg_temp.stable_uuid('wave7a-scale-edition:' || value), 'name', 'Scale 2027'),
      'category', jsonb_build_object('id', pg_temp.stable_uuid('wave7a-scale-category:' || value), 'name', 'Senior', 'sportFormat', 'FOOTBALL_7'),
      'registration', jsonb_build_object('mode', 'REQUEST_APPROVAL', 'state', 'OPEN', 'teamCount', 1, 'teamCapacity', 16, 'availablePlaces', 15, 'waitlistCount', 2),
      'sections', jsonb_build_object('teams', true, 'calendar', true, 'results', true, 'standings', true, 'bracket', true, 'referees', true, 'venueDetail', false, 'discipline', false),
      'teams', '[]'::jsonb,
      'standings', jsonb_build_array(jsonb_build_object('position', 1, 'team', 'Wave 7A Team 1', 'points', 3)),
      'bracket', jsonb_build_object('kind', 'PublicTournamentBracket', 'rounds', '[]'::jsonb, 'publicSafeSummary', jsonb_build_object('status', 'READY')),
      'privacy', jsonb_build_object('containsRoster', false, 'containsAttendance', false, 'containsContactData', false, 'containsEvidence', false, 'containsFees', false, 'containsPrivateLocation', false),
      'cache', jsonb_build_object('entityType', 'public_competition', 'revision', 1, 'serverSequence', value)
    ) snapshot
  from generate_series(1, 10000) value
)
insert into public.pachanga_public_competition_read_models(
  publication_id, competition_id, slug, visibility, lifecycle_status,
  competition_type, competition_status, edition_status, public_state,
  registration_state, registration_mode, sport_format, format_kind,
  municipality, general_area, organizer_kind, organizer_name, starts_at,
  ends_at, registration_opens_at, registration_closes_at,
  accepted_team_count, team_capacity, available_places, waitlist_count,
  is_indexable, search_document, revision, server_sequence, public_snapshot,
  snapshot_checksum
)
select pg_temp.stable_uuid('wave7a-scale-publication:' || source.value),
  pg_temp.stable_uuid('wave7a-scale-competition:' || source.value),
  'wave7a-scale-competition-' || source.value, 'public', 'published',
  case when source.value % 2 = 0 then 'TOURNAMENT' else 'LEAGUE' end,
  'draft', 'registration_open', 'REGISTRATION_OPEN', 'OPEN',
  'REQUEST_APPROVAL', 'FOOTBALL_7',
  case when source.value % 2 = 0 then 'Eliminatoria' else 'Liga' end,
  case when source.value % 2 = 0 then 'Barcelona' else 'Terrassa' end,
  'Barcelona', 'TEAM', 'Wave 7A Organizer', '2027-01-01', '2027-12-31',
  '2026-01-01T00:00:00Z', '2029-01-01T00:00:00Z', 1, 16, 15, 2,
  true, to_tsvector('simple', 'Wave 7A Scale Competition ' || source.value || ' Barcelona Terrassa FOOTBALL_7'),
  1, nextval('private.pachanga_competition_sequence'), source.snapshot,
  encode(extensions.digest(convert_to(source.snapshot::text, 'UTF8'), 'sha256'), 'hex')
from source;

insert into public.pachanga_canonical_matches(id, status, created_by)
select pg_temp.stable_uuid('wave7a-scale-match:' || competition_number || ':' || fixture_number),
  'active', md5('wave7a-user-0')::uuid
from generate_series(1, 10000) competition_number
cross join generate_series(1, 10) fixture_number;

alter table public.pachanga_competition_match_contexts disable trigger user;
insert into public.pachanga_competition_match_contexts(
  id, canonical_match_id, competition_id, edition_id, stage_id, category_id,
  rule_revision_id, status, scheduled_start, scheduled_end, timezone,
  source_kind, created_by
)
select pg_temp.stable_uuid('wave7a-scale-context:' || competition_number || ':' || fixture_number),
  pg_temp.stable_uuid('wave7a-scale-match:' || competition_number || ':' || fixture_number),
  pg_temp.stable_uuid('wave7a-scale-competition:' || competition_number),
  pg_temp.stable_uuid('wave7a-scale-edition:' || competition_number),
  pg_temp.stable_uuid('wave7a-scale-stage:' || competition_number),
  pg_temp.stable_uuid('wave7a-scale-category:' || competition_number),
  pg_temp.stable_uuid('wave7a-scale-rule-revision:' || competition_number),
  'official',
  '2027-02-01T18:00:00Z'::timestamptz + (fixture_number || ' days')::interval,
  '2027-02-01T19:15:00Z'::timestamptz + (fixture_number || ' days')::interval,
  'Europe/Madrid', 'LEGACY_LAB', md5('wave7a-user-0')::uuid
from generate_series(1, 10000) competition_number
cross join generate_series(1, 10) fixture_number;
alter table public.pachanga_competition_match_contexts enable trigger user;

with source as (
  select competition_number, fixture_number,
    jsonb_build_object(
      'kind', 'PublicCompetitionFixture',
      'competitionId', pg_temp.stable_uuid('wave7a-scale-competition:' || competition_number),
      'contextId', pg_temp.stable_uuid('wave7a-scale-context:' || competition_number || ':' || fixture_number),
      'canonicalMatchId', pg_temp.stable_uuid('wave7a-scale-match:' || competition_number || ':' || fixture_number),
      'scheduledStart', '2027-02-01T18:00:00Z'::timestamptz + (fixture_number || ' days')::interval,
      'status', 'official',
      'result', jsonb_build_object('status', 'OFFICIAL', 'scoreHome', fixture_number % 5, 'scoreAway', (fixture_number + 2) % 5),
      'revision', 1,
      'serverSequence', fixture_number,
      'privacy', jsonb_build_object('containsEvidence', false)
    ) snapshot
  from generate_series(1, 10000) competition_number
  cross join generate_series(1, 10) fixture_number
)
insert into public.pachanga_public_competition_fixture_read_models(
  id, publication_id, competition_id, competition_match_context_id,
  canonical_match_id, edition_id, stage_id, scheduled_start, fixture_status,
  has_official_result, revision, server_sequence, public_snapshot,
  snapshot_checksum
)
select pg_temp.stable_uuid('wave7a-scale-fixture-read:' || source.competition_number || ':' || source.fixture_number),
  pg_temp.stable_uuid('wave7a-scale-publication:' || source.competition_number),
  pg_temp.stable_uuid('wave7a-scale-competition:' || source.competition_number),
  pg_temp.stable_uuid('wave7a-scale-context:' || source.competition_number || ':' || source.fixture_number),
  pg_temp.stable_uuid('wave7a-scale-match:' || source.competition_number || ':' || source.fixture_number),
  pg_temp.stable_uuid('wave7a-scale-edition:' || source.competition_number),
  pg_temp.stable_uuid('wave7a-scale-stage:' || source.competition_number),
  '2027-02-01T18:00:00Z'::timestamptz + (source.fixture_number || ' days')::interval,
  'official', true, 1, nextval('private.pachanga_competition_sequence'),
  source.snapshot,
  encode(extensions.digest(convert_to(source.snapshot::text, 'UTF8'), 'sha256'), 'hex')
from source;

alter table public.pachanga_competition_match_sheets disable trigger user;
insert into public.pachanga_competition_match_sheets(
  id, canonical_match_id, competition_match_context_id, created_by
)
select pg_temp.stable_uuid('wave7a-scale-match-sheet:' || competition_number || ':' || fixture_number),
  pg_temp.stable_uuid('wave7a-scale-match:' || competition_number || ':' || fixture_number),
  pg_temp.stable_uuid('wave7a-scale-context:' || competition_number || ':' || fixture_number),
  md5('wave7a-user-0')::uuid
from unnest(array[9999, 10000]) competition_number
cross join generate_series(1, 10) fixture_number;
alter table public.pachanga_competition_match_sheets enable trigger user;

alter table public.pachanga_competition_official_result_decisions disable trigger user;
insert into public.pachanga_competition_official_result_decisions(
  id, canonical_match_id, competition_match_context_id, outcome,
  effective_score_home, effective_score_away, public_explanation,
  reason_code, operation_id, authority_role, decided_by
)
select pg_temp.stable_uuid('wave7a-scale-decision:' || competition_number || ':' || fixture_number),
  pg_temp.stable_uuid('wave7a-scale-match:' || competition_number || ':' || fixture_number),
  pg_temp.stable_uuid('wave7a-scale-context:' || competition_number || ':' || fixture_number),
  'CORRECTED_EFFECTIVE_SCORE', fixture_number % 5, (fixture_number + 2) % 5,
  'Resultado oficial sintético para prueba de volumen.',
  'wave7a.scale.official_result',
  pg_temp.stable_uuid('wave7a-scale-decision-operation:' || competition_number || ':' || fixture_number),
  'competition_director', md5('wave7a-user-0')::uuid
from unnest(array[9999, 10000]) competition_number
cross join generate_series(1, 10) fixture_number;
alter table public.pachanga_competition_official_result_decisions enable trigger user;

alter table public.pachanga_competition_match_sheets disable trigger user;
update public.pachanga_competition_match_sheets sheets set
  active_official_decision_id = decisions.id,
  revision = sheets.revision + 1,
  updated_at = clock_timestamp()
from public.pachanga_competition_official_result_decisions decisions
where sheets.competition_match_context_id = decisions.competition_match_context_id
  and sheets.id in (
    select pg_temp.stable_uuid('wave7a-scale-match-sheet:' || competition_number || ':' || fixture_number)
    from unnest(array[9999, 10000]) competition_number
    cross join generate_series(1, 10) fixture_number
  );
alter table public.pachanga_competition_match_sheets enable trigger user;

select private.pachanga_public_competition_rebuild_v1(
  pg_temp.stable_uuid('wave7a-scale-competition:9999'), null
);
select private.pachanga_public_competition_rebuild_v1(
  pg_temp.stable_uuid('wave7a-scale-competition:10000'), null
);

analyze public.pachanga_public_competition_read_models;
analyze public.pachanga_public_competition_fixture_read_models;
analyze public.pachanga_competition_registration_requests;
analyze public.pachanga_competition_entries;

do $$
declare started_at timestamptz;
declare payload jsonb;
declare iteration integer;
declare publication_id_value uuid;
declare request_id_value uuid;
declare request_revision bigint;
begin
  for iteration in 1..30 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_public_competition_directory_v1(
      'Scale Competition', case when iteration % 2 = 0 then 'LEAGUE' else 'TOURNAMENT' end,
      'FOOTBALL_7', 'REGISTRATION_OPEN', 'Barcelona', 'OPEN', 24, 0
    );
    insert into wave7a_scale_timings values (
      'directory', extract(epoch from clock_timestamp() - started_at) * 1000
    );
  end loop;
  for iteration in 1..30 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_public_competition_v1('wave7a-scale-competition-1');
    insert into wave7a_scale_timings values (
      'hub', extract(epoch from clock_timestamp() - started_at) * 1000
    );
  end loop;
  for iteration in 1..30 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_public_competition_calendar_v1('wave7a-scale-competition-1', 50, 0);
    insert into wave7a_scale_timings values (
      'calendar', extract(epoch from clock_timestamp() - started_at) * 1000
    );
  end loop;
  for iteration in 1..30 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_public_competition_standings_v1('wave7a-scale-competition-1');
    insert into wave7a_scale_timings values (
      'standings', extract(epoch from clock_timestamp() - started_at) * 1000
    );
  end loop;
  for iteration in 1..30 loop
    started_at := clock_timestamp();
    payload := public.get_pachanga_public_competition_bracket_v1('wave7a-scale-competition-2');
    insert into wave7a_scale_timings values (
      'bracket', extract(epoch from clock_timestamp() - started_at) * 1000
    );
  end loop;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', md5('wave7a-user-4')::uuid, 'role', 'authenticated'
  )::text, true);
  select id into publication_id_value from public.pachanga_competition_publications
  where slug = 'wave7a-scale-competition-10000';
  started_at := clock_timestamp();
  payload := public.command_pachanga_competition_registration_request_v1(
    pg_temp.stable_uuid('wave7a-scale-measure-submit'), publication_id_value, 1,
    'registration.submit',
    jsonb_build_object('teamId', md5('wave7a-team-4')::uuid,
      'message', 'Measured request', 'reason', 'Wave 7A measured submit'),
    '{"clientVersion":"7.0.0+scale","surface":"wave7a_scale"}'::jsonb
  );
  insert into wave7a_scale_timings values (
    'request_submit', extract(epoch from clock_timestamp() - started_at) * 1000
  );
  request_id_value := (payload #>> '{snapshot,id}')::uuid;
  request_revision := (payload ->> 'confirmedRevision')::bigint;

  perform set_config('request.jwt.claims', jsonb_build_object(
    'sub', md5('wave7a-user-0')::uuid, 'role', 'authenticated'
  )::text, true);
  started_at := clock_timestamp();
  payload := public.command_pachanga_competition_registration_request_v1(
    pg_temp.stable_uuid('wave7a-scale-measure-accept'), request_id_value,
    request_revision, 'registration.accept',
    '{"reason":"Wave 7A measured accept"}'::jsonb,
    '{"clientVersion":"7.0.0+scale","surface":"wave7a_scale"}'::jsonb
  );
  insert into wave7a_scale_timings values (
    'request_accept', extract(epoch from clock_timestamp() - started_at) * 1000
  );

  select requests.id, requests.revision into request_id_value, request_revision
  from public.pachanga_competition_registration_requests requests
  where requests.competition_id = pg_temp.stable_uuid('wave7a-scale-competition:9999')
    and requests.team_id = md5('wave7a-team-3')::uuid
    and requests.status = 'waitlisted';
  started_at := clock_timestamp();
  payload := public.command_pachanga_competition_registration_request_v1(
    pg_temp.stable_uuid('wave7a-scale-measure-reorder'), request_id_value,
    request_revision, 'waitlist.reorder',
    '{"position":1,"reason":"Wave 7A measured reorder","privateReason":"Scale timing"}'::jsonb,
    '{"clientVersion":"7.0.0+scale","surface":"wave7a_scale"}'::jsonb
  );
  insert into wave7a_scale_timings values (
    'waitlist_reorder', extract(epoch from clock_timestamp() - started_at) * 1000
  );
end;
$$;

do $$
declare metric_row record;
begin
  if (select count(*) from public.pachanga_public_competition_read_models
      where slug like 'wave7a-scale-competition-%') <> 10000 then
    raise exception 'WAVE7A_SCALE_COMPETITION_COUNT';
  end if;
  if (select count(*) from public.pachanga_competition_registration_requests requests
      join public.pachanga_competitions competitions on competitions.id=requests.competition_id
      where competitions.slug like 'wave7a-scale-competition-%') < 100000 then
    raise exception 'WAVE7A_SCALE_REQUEST_COUNT';
  end if;
  if (select count(*) from public.pachanga_competition_registration_requests requests
      join public.pachanga_competitions competitions on competitions.id=requests.competition_id
      where competitions.slug like 'wave7a-scale-competition-%'
        and requests.status='waitlisted') <> 20000 then
    raise exception 'WAVE7A_SCALE_WAITLIST_COUNT';
  end if;
  if (select count(*) from public.pachanga_competition_entries entries
      join public.pachanga_competitions competitions on competitions.id=entries.competition_id
      where competitions.slug like 'wave7a-scale-competition-%') < 10000 then
    raise exception 'WAVE7A_SCALE_ENTRY_COUNT';
  end if;
  if (select count(*) from public.pachanga_public_competition_fixture_read_models models
      join public.pachanga_competitions competitions on competitions.id=models.competition_id
      where competitions.slug like 'wave7a-scale-competition-%') <> 100000 then
    raise exception 'WAVE7A_SCALE_FIXTURE_COUNT';
  end if;
  if (select count(*) from public.pachanga_public_competition_fixture_read_models models
      join public.pachanga_competitions competitions on competitions.id=models.competition_id
      where competitions.slug like 'wave7a-scale-competition-%'
        and models.has_official_result) <> 100000 then
    raise exception 'WAVE7A_SCALE_PUBLIC_RESULT_COUNT';
  end if;
  for metric_row in
    select metric, percentile_cont(0.95) within group (order by elapsed_ms) p95
    from wave7a_scale_timings group by metric
  loop
    if metric_row.p95 > (case metric_row.metric
      when 'directory' then 500
      when 'hub' then 100
      when 'calendar' then 150
      when 'standings' then 100
      when 'bracket' then 100
      when 'request_submit' then 750
      when 'request_accept' then 1000
      when 'waitlist_reorder' then 750
      else 1000 end) then
      raise exception 'WAVE7A_SCALE_THRESHOLD:%:%', metric_row.metric, metric_row.p95;
    end if;
  end loop;
end;
$$;

select jsonb_build_object(
  'counts', jsonb_build_object(
    'publicCompetitions', 10000,
    'registrationRequests', (select count(*) from public.pachanga_competition_registration_requests requests
      join public.pachanga_competitions competitions on competitions.id=requests.competition_id
      where competitions.slug like 'wave7a-scale-competition-%'),
    'waitlisted', 20000,
    'acceptedEntries', (select count(*) from public.pachanga_competition_entries entries
      join public.pachanga_competitions competitions on competitions.id=entries.competition_id
      where competitions.slug like 'wave7a-scale-competition-%'),
    'publicFixtures', 100000,
    'publicOfficialResults', 100000
  ),
  'timingsMs', (
    select jsonb_object_agg(metric, jsonb_build_object(
      'samples', samples,
      'p50', round(p50::numeric, 3),
      'p95', round(p95::numeric, 3),
      'max', round(maximum::numeric, 3)
    ))
    from (
      select metric, count(*) samples,
        percentile_cont(0.50) within group (order by elapsed_ms) p50,
        percentile_cont(0.95) within group (order by elapsed_ms) p95,
        max(elapsed_ms) maximum
      from wave7a_scale_timings group by metric
    ) timing
  ),
  'indexBytes', jsonb_build_object(
    'directory', pg_indexes_size('public.pachanga_public_competition_read_models'),
    'fixtures', pg_indexes_size('public.pachanga_public_competition_fixture_read_models'),
    'requests', pg_indexes_size('public.pachanga_competition_registration_requests')
  ),
  'rollback', true
)::text;

rollback;
