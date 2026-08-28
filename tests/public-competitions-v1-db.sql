\set ON_ERROR_STOP on

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', target_role)::text,
    true
  );
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'WAVE7A_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'WAVE7A_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create temporary table wave7a_state(
  publication_id uuid,
  publication_revision bigint,
  request_1 uuid,
  request_2 uuid,
  request_3 uuid,
  request_4 uuid,
  request_5 uuid,
  request_6 uuid,
  report_id uuid,
  report_revision bigint
);
insert into wave7a_state default values;

do $$
declare response jsonb;
declare replay jsonb;
declare settings_revision bigint;
begin
  perform pg_temp.assert_true(
    not (select public_competition_foundation_enabled
      from private.pachanga_competition_foundation_settings where singleton),
    'Wave 7A flags must install OFF'
  );
  perform pg_temp.actor(md5('wave7a-user-10')::uuid);
  select revision into settings_revision
  from private.pachanga_competition_foundation_settings where singleton;
  response := public.set_pachanga_public_competition_flags_v1(
    '7a100000-0000-4000-8000-000000000001', settings_revision,
    '{
      "foundation":true,"publication":true,"discovery":true,
      "registrationRequests":true,"waitlist":true,"calendar":true,
      "results":true,"standings":true,"bracket":true,
      "exceptionStatus":true,"referees":true,
      "discipline":false,"autoAccept":false
    }'::jsonb,
    'Wave 7A isolated activation',
    '{"clientVersion":"7.0.0+db","serviceWorkerVersion":"sw-wave7a","installedMode":"standalone","surface":"wave7a_db"}'
  );
  replay := public.set_pachanga_public_competition_flags_v1(
    '7a100000-0000-4000-8000-000000000001', settings_revision,
    '{
      "foundation":true,"publication":true,"discovery":true,
      "registrationRequests":true,"waitlist":true,"calendar":true,
      "results":true,"standings":true,"bracket":true,
      "exceptionStatus":true,"referees":true,
      "discipline":false,"autoAccept":false
    }'::jsonb,
    'Wave 7A isolated activation',
    '{"clientVersion":"7.0.0+db","serviceWorkerVersion":"sw-wave7a","installedMode":"standalone","surface":"wave7a_db"}'
  );
  perform pg_temp.assert_true(response = replay, 'flag operation replay must be exact');
  perform pg_temp.assert_true(
    not (response #>> '{snapshot,discipline}')::boolean
      and not (response #>> '{snapshot,autoAccept}')::boolean,
    'unsafe flags must remain OFF'
  );
  perform pg_temp.expect_failure(
    format(
      'select public.set_pachanga_public_competition_flags_v1(%L,%s,%L::jsonb,%L,%L::jsonb)',
      '7a100000-0000-4000-8000-000000000002',
      response ->> 'confirmedRevision',
      '{"discipline":true}', 'Unsafe activation rejected', '{}'
    ),
    'UNSAFE_FLAG_DISABLED'
  );
end;
$$;

do $$
declare response jsonb;
declare revision_value bigint;
declare publication_id_value uuid;
begin
  perform pg_temp.actor(md5('wave7a-user-0')::uuid);
  response := public.command_pachanga_competition_publication_v1(
    '7a110000-0000-4000-8000-000000000001',
    '7a040000-0000-4000-8000-000000000001', 0,
    'publication.prepare',
    '{
      "editionId":"7a070000-0000-4000-8000-000000000001",
      "categoryId":"7a0b0000-0000-4000-8000-000000000001",
      "slug":"liga-publica-wave-7a",
      "visibility":"public",
      "publicProfile":{
        "name":"Liga Pública Wave 7A",
        "description":"Liga abierta de fútbol 7 para equipos de Barcelona.",
        "municipality":"Barcelona","generalArea":"Barcelona",
        "format":"Liga","badge":"BETA",
        "rulesSummary":"Dos equipos, una vuelta y resultados oficiales.",
        "publicVenue":"Sede pública consentida"
      },
      "publicSections":{
        "teams":true,"calendar":true,"results":true,"standings":true,
        "bracket":false,"referees":true,"venueDetail":false,"discipline":false
      },
      "reason":"Prepare public projection"
    }'::jsonb,
    '{"clientVersion":"7.0.0+db","surface":"wave7a_db"}'
  );
  publication_id_value := (response #>> '{snapshot,publication,id}')::uuid;
  revision_value := (response ->> 'confirmedRevision')::bigint;

  response := public.command_pachanga_competition_publication_v1(
    '7a110000-0000-4000-8000-000000000002',
    '7a040000-0000-4000-8000-000000000001', revision_value,
    'registration.configure',
    '{"mode":"REQUEST_APPROVAL","opensAt":"2026-01-01T00:00:00Z","closesAt":"2029-01-01T00:00:00Z","reason":"Open registration"}'::jsonb,
    '{"clientVersion":"7.0.0+db","surface":"wave7a_db"}'
  );
  revision_value := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.assert_true(exists(
    select 1 from public.pachanga_competition_editions editions
    where editions.id = '7a070000-0000-4000-8000-000000000001'
      and editions.status = 'registration_open'
      and editions.registration_mode = 'REQUEST_APPROVAL'
  ), 'registration.configure must open the canonical edition');

  response := public.command_pachanga_competition_publication_v1(
    '7a110000-0000-4000-8000-000000000003',
    '7a040000-0000-4000-8000-000000000001', revision_value,
    'publication.consent',
    '{
      "statements":{
        "authorizedRepresentative":true,"informationAccurate":true,
        "teamAssetsAuthorized":true,"indexingAccepted":true
      },
      "purpose":"Publicar la liga y admitir solicitudes de equipos.",
      "reason":"Explicit consent"
    }'::jsonb,
    '{"clientVersion":"7.0.0+db","surface":"wave7a_db"}'
  );
  revision_value := (response ->> 'confirmedRevision')::bigint;

  response := public.command_pachanga_competition_publication_v1(
    '7a110000-0000-4000-8000-000000000004',
    '7a040000-0000-4000-8000-000000000001', revision_value,
    'publication.submit', '{"reason":"Submit for independent review"}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_db"}'
  );
  revision_value := (response ->> 'confirmedRevision')::bigint;
  update wave7a_state set publication_id = publication_id_value,
    publication_revision = revision_value;
end;
$$;

do $$
declare publication_id_value uuid;
declare revision_value bigint;
declare response jsonb;
begin
  select publication_id, publication_revision
  into publication_id_value, revision_value from wave7a_state;
  insert into private.pachanga_platform_admin_roles(user_id, role, active)
  values (md5('wave7a-user-0')::uuid, 'platform_admin', true);
  perform pg_temp.actor(md5('wave7a-user-0')::uuid);
  perform pg_temp.expect_failure(
    format(
      'select public.command_pachanga_public_competition_moderation_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
      '7a120000-0000-4000-8000-000000000001', publication_id_value,
      revision_value, 'publication.approve',
      '{"reason":"Forbidden self approval"}', '{}'
    ),
    'SELF_REVIEW_FORBIDDEN'
  );
  delete from private.pachanga_platform_admin_roles
  where user_id = md5('wave7a-user-0')::uuid;

  perform pg_temp.actor(md5('wave7a-user-10')::uuid);
  response := public.command_pachanga_public_competition_moderation_v1(
    '7a120000-0000-4000-8000-000000000002', publication_id_value,
    revision_value, 'publication.approve',
    '{"reason":"Independent review passed","publicReason":"Publicación aprobada."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_control_center"}'
  );
  revision_value := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_public_competition_moderation_v1(
    '7a120000-0000-4000-8000-000000000003', publication_id_value,
    revision_value, 'publication.publish',
    '{"reason":"Publish approved competition","publicReason":"Competición publicada."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_control_center"}'
  );
  update wave7a_state set publication_revision = (response ->> 'confirmedRevision')::bigint;
end;
$$;

do $$
declare directory jsonb;
declare hub jsonb;
declare sitemap jsonb;
declare snapshot_text text;
begin
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  directory := public.get_pachanga_public_competition_directory_v1();
  hub := public.get_pachanga_public_competition_v1('liga-publica-wave-7a');
  select coalesce(jsonb_agg(to_jsonb(items)), '[]'::jsonb)
  into sitemap
  from public.get_pachanga_public_competition_sitemap_v1() items;
  snapshot_text := hub::text;
  perform pg_temp.assert_true(jsonb_array_length(directory -> 'items') = 1,
    'public directory must expose the approved publication');
  perform pg_temp.assert_true(exists(
    select 1 from public.pachanga_public_competition_read_models models
    where models.slug = 'liga-publica-wave-7a' and models.is_indexable
  ), 'public approved publication must be indexable');
  perform pg_temp.assert_true(sitemap::text like '%liga-publica-wave-7a%',
    'public sitemap must include the canonical slug');
  perform pg_temp.assert_true(snapshot_text not like '%SECRET_PRIVATE_DESCRIPTION%'
      and snapshot_text not like '%private-%@example.test%'
      and snapshot_text not like '%+34 600 000%',
    'public hub must not expose private description, email or phone');
  perform pg_temp.assert_true(
    (hub #>> '{privacy,containsRoster}')::boolean = false
      and (hub #>> '{privacy,containsAttendance}')::boolean = false
      and (hub #>> '{privacy,containsContactData}')::boolean = false
      and (hub #>> '{privacy,containsEvidence}')::boolean = false
      and (hub #>> '{privacy,containsFees}')::boolean = false,
    'public privacy contract must be explicit and false for forbidden data'
  );
end;
$$;

do $$
declare response jsonb;
declare replay jsonb;
declare publication_id_value uuid;
declare publication_revision_value bigint;
declare request_id_value uuid;
begin
  select publication_id, publication_revision
  into publication_id_value, publication_revision_value from wave7a_state;
  perform pg_temp.actor(md5('wave7a-user-1')::uuid);
  response := public.command_pachanga_competition_registration_request_v1(
    '7a130000-0000-4000-8000-000000000001', publication_id_value,
    publication_revision_value, 'registration.submit',
    jsonb_build_object(
      'teamId', md5('wave7a-team-1')::uuid,
      'message', 'Queremos participar con nuestro equipo.',
      'reason', 'Initial team request'
    ), '{"clientVersion":"7.0.0+db","surface":"wave7a_registration"}'
  );
  replay := public.command_pachanga_competition_registration_request_v1(
    '7a130000-0000-4000-8000-000000000001', publication_id_value,
    publication_revision_value, 'registration.submit',
    jsonb_build_object(
      'teamId', md5('wave7a-team-1')::uuid,
      'message', 'Queremos participar con nuestro equipo.',
      'reason', 'Initial team request'
    ), '{"clientVersion":"7.0.0+db","surface":"wave7a_registration"}'
  );
  perform pg_temp.assert_true(response = replay, 'registration replay must be exact');
  request_id_value := (response #>> '{snapshot,id}')::uuid;
  update wave7a_state set request_1 = request_id_value;
  perform pg_temp.expect_failure(
    format(
      'select public.command_pachanga_competition_registration_request_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
      '7a130000-0000-4000-8000-000000000002', publication_id_value,
      publication_revision_value, 'registration.submit',
      jsonb_build_object('teamId', md5('wave7a-team-1')::uuid, 'message', 'Duplicate')::text,
      '{}'
    ),
    'ALREADY_EXISTS'
  );
end;
$$;

do $$
declare response jsonb;
declare publication_id_value uuid;
declare publication_revision_value bigint;
declare request_id_value uuid;
declare request_index integer;
declare operation_value uuid;
begin
  select publication_id, publication_revision
  into publication_id_value, publication_revision_value from wave7a_state;

  perform pg_temp.actor(md5('wave7a-user-0')::uuid);
  select request_1 into request_id_value from wave7a_state;
  response := public.command_pachanga_competition_registration_request_v1(
    '7a140000-0000-4000-8000-000000000001', request_id_value, 1,
    'registration.accept',
    '{"reason":"First place accepted","publicReason":"Equipo aceptado."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_queue"}'
  );
  perform pg_temp.assert_true((response #>> '{snapshot,entryId}')::uuid is not null,
    'acceptance must create an Entry atomically');

  for request_index in 2..6 loop
    perform pg_temp.actor(md5('wave7a-user-' || request_index)::uuid);
    operation_value := ('7a130000-0000-4000-8000-'
      || lpad((100 + request_index)::text, 12, '0'))::uuid;
    response := public.command_pachanga_competition_registration_request_v1(
      operation_value, publication_id_value, publication_revision_value,
      'registration.submit',
      jsonb_build_object(
        'teamId', md5('wave7a-team-' || request_index)::uuid,
        'message', 'Solicitud del equipo ' || request_index,
        'reason', 'Team request ' || request_index
      ), '{"clientVersion":"7.0.0+db","surface":"wave7a_registration"}'
    );
    execute format(
      'update wave7a_state set request_%s = %L::uuid',
      request_index, response #>> '{snapshot,id}'
    );
  end loop;

  perform pg_temp.actor(md5('wave7a-user-0')::uuid);
  select request_2 into request_id_value from wave7a_state;
  response := public.command_pachanga_competition_registration_request_v1(
    '7a140000-0000-4000-8000-000000000002', request_id_value, 1,
    'registration.accept',
    '{"reason":"Last available place","publicReason":"Equipo aceptado."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_queue"}'
  );

  select request_3 into request_id_value from wave7a_state;
  perform pg_temp.expect_failure(
    format(
      'select public.command_pachanga_competition_registration_request_v1(%L,%L,1,%L,%L::jsonb,%L::jsonb)',
      '7a140000-0000-4000-8000-000000000003', request_id_value,
      'registration.accept',
      '{"reason":"Capacity race loser","publicReason":"No place."}', '{}'
    ),
    'CAPACITY_REACHED'
  );

  for request_index in 3..6 loop
    execute format('select request_%s from wave7a_state', request_index)
      into request_id_value;
    operation_value := ('7a140000-0000-4000-8000-'
      || lpad((100 + request_index)::text, 12, '0'))::uuid;
    response := public.command_pachanga_competition_registration_request_v1(
      operation_value, request_id_value, 1, 'registration.waitlist',
      jsonb_build_object(
        'reason', 'Waitlist team ' || request_index,
        'publicReason', 'Equipo en lista de espera.',
        'privateReason', 'Orden automático inicial.'
      ), '{"clientVersion":"7.0.0+db","surface":"wave7a_queue"}'
    );
  end loop;
end;
$$;

do $$
declare moved_request uuid;
declare response jsonb;
declare replay jsonb;
declare positions bigint[];
begin
  select request_6 into moved_request from wave7a_state;
  perform pg_temp.actor(md5('wave7a-user-0')::uuid);
  response := public.command_pachanga_competition_registration_request_v1(
    '7a150000-0000-4000-8000-000000000001', moved_request, 2,
    'waitlist.reorder',
    '{"position":1,"reason":"Manual priority correction","privateReason":"Audited reorder"}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_waitlist"}'
  );
  replay := public.command_pachanga_competition_registration_request_v1(
    '7a150000-0000-4000-8000-000000000001', moved_request, 2,
    'waitlist.reorder',
    '{"position":1,"reason":"Manual priority correction","privateReason":"Audited reorder"}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_waitlist"}'
  );
  perform pg_temp.assert_true(response = replay, 'waitlist reorder replay must be exact');
  select array_agg(waitlist_position order by waitlist_position)
  into positions
  from public.pachanga_competition_registration_requests
  where status = 'waitlisted';
  perform pg_temp.assert_true(positions = array[1,2,3,4]::bigint[],
    'waitlist positions must remain stable and gap-free');
  perform pg_temp.assert_true((
    select count(*) from public.pachanga_competition_registration_request_revisions
    where operation_id = '7a150000-0000-4000-8000-000000000001'
  ) = 4, 'one reorder must audit every affected request');
  perform pg_temp.assert_true((
    select waitlist_position from public.pachanga_competition_registration_requests
    where id = moved_request
  ) = 1, 'requested Team must move to the selected position');
end;
$$;

do $$
declare publication_id_value uuid;
declare publication_revision_value bigint;
declare response jsonb;
declare report_reference uuid;
declare report_id_value uuid;
begin
  select publication_id, publication_revision
  into publication_id_value, publication_revision_value from wave7a_state;

  perform pg_temp.actor(md5('wave7a-user-7')::uuid);
  response := public.command_pachanga_competition_registration_request_v1(
    '7a160000-0000-4000-8000-000000000001', publication_id_value,
    publication_revision_value, 'registration.submit',
    jsonb_build_object('teamId', md5('wave7a-team-7')::uuid,
      'message', 'Solicitud que será rechazada.', 'reason', 'Reject fixture'),
    '{"clientVersion":"7.0.0+db","surface":"wave7a_registration"}'
  );
  perform pg_temp.actor(md5('wave7a-user-0')::uuid);
  response := public.command_pachanga_competition_registration_request_v1(
    '7a160000-0000-4000-8000-000000000002',
    (response #>> '{snapshot,id}')::uuid, 1, 'registration.reject',
    '{"reason":"Format mismatch","publicReason":"La solicitud no encaja en esta edición.","privateReason":"Private review stays private."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_queue"}'
  );

  perform pg_temp.actor(md5('wave7a-user-8')::uuid);
  response := public.command_pachanga_competition_registration_request_v1(
    '7a160000-0000-4000-8000-000000000003', publication_id_value,
    publication_revision_value, 'registration.submit',
    jsonb_build_object('teamId', md5('wave7a-team-8')::uuid,
      'message', 'Solicitud que será retirada.', 'reason', 'Withdraw fixture'),
    '{"clientVersion":"7.0.0+db","surface":"wave7a_registration"}'
  );
  response := public.command_pachanga_competition_registration_request_v1(
    '7a160000-0000-4000-8000-000000000004',
    (response #>> '{snapshot,id}')::uuid, 1, 'registration.withdraw',
    '{"reason":"Team withdrew before acceptance"}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_registration"}'
  );

  perform pg_temp.actor(md5('wave7a-user-9')::uuid);
  response := public.command_pachanga_competition_registration_request_v1(
    '7a160000-0000-4000-8000-000000000005', publication_id_value,
    publication_revision_value, 'competition.report',
    '{"category":"MISLEADING","summary":"La información pública necesita una revisión de la plataforma.","reason":"Competition report"}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_public_hub"}'
  );
  report_reference := (response #>> '{snapshot,opaqueReference}')::uuid;
  select id into report_id_value from private.pachanga_competition_reports
  where opaque_reference = report_reference;

  perform pg_temp.actor(md5('wave7a-user-10')::uuid);
  response := public.command_pachanga_public_competition_moderation_v1(
    '7a160000-0000-4000-8000-000000000006', report_id_value, 1,
    'report.review', '{"reason":"Open report review"}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_control_center"}'
  );
  response := public.command_pachanga_public_competition_moderation_v1(
    '7a160000-0000-4000-8000-000000000007', report_id_value, 2,
    'report.resolve',
    '{"reason":"Report corrected","publicReason":"La información ha sido revisada.","privateReason":"Internal moderation detail."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_control_center"}'
  );
  update wave7a_state set report_id = report_id_value,
    report_revision = (response ->> 'confirmedRevision')::bigint;
end;
$$;

insert into public.pachanga_competition_schedule_plans(
  id, competition_id, edition_id, category_id, stage_id, rule_revision_id,
  engine_version, legs, entry_count, status, created_by
) values (
  '7a220000-0000-4000-8000-000000000001',
  '7a040000-0000-4000-8000-000000000001',
  '7a070000-0000-4000-8000-000000000001',
  '7a0b0000-0000-4000-8000-000000000001',
  '7a080000-0000-4000-8000-000000000001',
  '7a060000-0000-4000-8000-000000000001',
  'league-round-robin-v1', 1, 2, 'generated', md5('wave7a-user-0')::uuid
);

insert into public.pachanga_competition_schedule_revisions(
  id, schedule_plan_id, version, revision_kind, status, engine_version,
  seed, input_checksum, rule_revision_id, entry_snapshot_checksum,
  slot_snapshot_checksum, constraint_snapshot_checksum,
  preference_snapshot_checksum, entry_order, generated_by
) values (
  '7a230000-0000-4000-8000-000000000001',
  '7a220000-0000-4000-8000-000000000001',
  1, 'generated', 'generated', 'league-round-robin-v1',
  'wave7a-public-calendar', repeat('1', 64),
  '7a060000-0000-4000-8000-000000000001', repeat('2', 64),
  repeat('3', 64), repeat('4', 64), repeat('5', 64), '[]'::jsonb,
  md5('wave7a-user-0')::uuid
);

update public.pachanga_competition_schedule_plans plans set
  current_revision_id = '7a230000-0000-4000-8000-000000000001'
where plans.id = '7a220000-0000-4000-8000-000000000001';

insert into public.pachanga_competition_schedule_slots(
  id, competition_id, edition_id, stage_id, starts_at, ends_at, timezone,
  venue_label, status, created_by
)
select ('7a240000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  '7a040000-0000-4000-8000-000000000001',
  '7a070000-0000-4000-8000-000000000001',
  '7a080000-0000-4000-8000-000000000001',
  '2027-10-01T18:00:00Z'::timestamptz + (value || ' days')::interval,
  '2027-10-01T19:10:00Z'::timestamptz + (value || ' days')::interval,
  'Europe/Madrid', 'Sede privada no consentida', 'assigned',
  md5('wave7a-user-0')::uuid
from generate_series(1, 3) value;

insert into public.pachanga_competition_rounds(
  id, competition_id, edition_id, category_id, stage_id,
  schedule_revision_id, round_number, leg_number, display_name,
  starts_at, ends_at, status, rule_revision_id, created_by
)
select ('7a250000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  '7a040000-0000-4000-8000-000000000001',
  '7a070000-0000-4000-8000-000000000001',
  '7a0b0000-0000-4000-8000-000000000001',
  '7a080000-0000-4000-8000-000000000001',
  '7a230000-0000-4000-8000-000000000001', value, 1,
  'Jornada ' || value,
  '2027-10-01T18:00:00Z'::timestamptz + (value || ' days')::interval,
  '2027-10-01T19:10:00Z'::timestamptz + (value || ' days')::interval,
  'draft', '7a060000-0000-4000-8000-000000000001',
  md5('wave7a-user-0')::uuid
from generate_series(1, 3) value;

insert into public.pachanga_canonical_matches(id, status, created_by)
select ('7a200000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'active', md5('wave7a-user-0')::uuid
from generate_series(1, 3) value;

insert into public.pachanga_competition_schedule_items(
  id, schedule_revision_id, round_id, home_entry_id, away_entry_id,
  pairing_key, leg_number, slot_id, scheduled_start, scheduled_end,
  timezone, venue_label, venue_status, status, canonical_match_id
)
select ('7a260000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  '7a230000-0000-4000-8000-000000000001',
  ('7a250000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  (select entries.id from public.pachanga_competition_entries entries
    where entries.competition_id = '7a040000-0000-4000-8000-000000000001'
      and entries.team_id = md5('wave7a-team-1')::uuid),
  (select entries.id from public.pachanga_competition_entries entries
    where entries.competition_id = '7a040000-0000-4000-8000-000000000001'
      and entries.team_id = md5('wave7a-team-2')::uuid),
  repeat(md5('wave7a-public-pair-' || value), 2) || ':' || value,
  1, ('7a240000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  '2027-10-01T18:00:00Z'::timestamptz + (value || ' days')::interval,
  '2027-10-01T19:10:00Z'::timestamptz + (value || ' days')::interval,
  'Europe/Madrid', 'Sede privada no consentida', 'CONFIRMED', 'assigned',
  ('7a200000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid
from generate_series(1, 3) value;

insert into public.pachanga_competition_match_contexts(
  id, canonical_match_id, competition_id, edition_id, stage_id,
  category_id, rule_revision_id, round_id, schedule_item_id,
  home_entry_id, away_entry_id, slot_id, status, scheduled_start, scheduled_end,
  timezone, venue_label, venue_status, source_kind, created_by
)
select ('7a210000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('7a200000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  '7a040000-0000-4000-8000-000000000001',
  '7a070000-0000-4000-8000-000000000001',
  '7a080000-0000-4000-8000-000000000001',
  '7a0b0000-0000-4000-8000-000000000001',
  '7a060000-0000-4000-8000-000000000001',
  ('7a250000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('7a260000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  (select entries.id from public.pachanga_competition_entries entries
    where entries.competition_id = '7a040000-0000-4000-8000-000000000001'
      and entries.team_id = md5('wave7a-team-1')::uuid),
  (select entries.id from public.pachanga_competition_entries entries
    where entries.competition_id = '7a040000-0000-4000-8000-000000000001'
      and entries.team_id = md5('wave7a-team-2')::uuid),
  ('7a240000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'scheduled',
  '2027-10-01T18:00:00Z'::timestamptz + (value || ' days')::interval,
  '2027-10-01T19:10:00Z'::timestamptz + (value || ' days')::interval,
  'Europe/Madrid', 'Sede privada no consentida', 'LABEL',
  'COMPETITION_GENERATED', md5('wave7a-user-0')::uuid
from generate_series(1, 3) value;

set constraints all immediate;
set constraints all deferred;

do $$
declare checksums_before text[];
declare checksums_after text[];
declare sequences_before bigint[];
declare sequences_after bigint[];
declare sanitized jsonb;
begin
  select array_agg(snapshot_checksum order by competition_match_context_id),
    array_agg(server_sequence order by competition_match_context_id)
  into checksums_before, sequences_before
  from public.pachanga_public_competition_fixture_read_models
  where competition_id = '7a040000-0000-4000-8000-000000000001';
  perform pg_temp.assert_true(cardinality(sequences_before) = 3
      and cardinality((select array_agg(distinct value) from unnest(sequences_before) value)) = 3,
    'three fixture read models must receive distinct server sequences');
  perform private.pachanga_public_competition_rebuild_v1(
    '7a040000-0000-4000-8000-000000000001',
    nextval('private.pachanga_competition_sequence')
  );
  select array_agg(snapshot_checksum order by competition_match_context_id),
    array_agg(server_sequence order by competition_match_context_id)
  into checksums_after, sequences_after
  from public.pachanga_public_competition_fixture_read_models
  where competition_id = '7a040000-0000-4000-8000-000000000001';
  perform pg_temp.assert_true(checksums_before = checksums_after,
    'convergent fixture rebuild must keep canonical snapshot hashes');
  perform pg_temp.assert_true(sequences_before <> sequences_after,
    'a second rebuild must allocate a new ordered receipt per fixture');

  sanitized := private.pachanga_public_competition_bracket_safe_v1(
    '{
      "competitionId":"7a040000-0000-4000-8000-000000000001",
      "sources":{"private":"sentinel"},
      "reservations":[{"id":"private-reservation"}],
      "health":{"admin":"sentinel"},
      "rounds":[{"id":"r1","code":"QF","order":1,"nodes":[{
        "id":"n1","nodeOrder":1,"sourceHome":{"id":"secret"},
        "reservationId":"secret","templateId":"secret",
        "home":{"entryId":"a","teamId":"b","name":"Safe Team"}
      }]}],
      "publicSafeSummary":{"status":"READY"}
    }'::jsonb,
    false
  );
  perform pg_temp.assert_true(sanitized::text not like '%private-reservation%'
      and sanitized::text not like '%sourceHome%'
      and sanitized::text not like '%reservationId%'
      and sanitized::text not like '%templateId%'
      and sanitized::text not like '%health%',
    'public bracket sanitizer must remove internal lineage and health');
end;
$$;

do $$
declare publication_id_value uuid;
declare revision_value bigint;
declare response jsonb;
declare health jsonb;
begin
  select publication_id, publication_revision
  into publication_id_value, revision_value from wave7a_state;
  perform pg_temp.actor(md5('wave7a-user-10')::uuid);
  response := public.command_pachanga_public_competition_moderation_v1(
    '7a170000-0000-4000-8000-000000000001', publication_id_value,
    revision_value, 'publication.suspend',
    '{"reason":"Temporary safety review","publicReason":"Publicación temporalmente suspendida."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_control_center"}'
  );
  perform pg_temp.expect_failure(
    'select public.get_pachanga_public_competition_v1(''liga-publica-wave-7a'')',
    'PUBLIC_COMPETITION_NOT_FOUND'
  );
  response := public.command_pachanga_public_competition_moderation_v1(
    '7a170000-0000-4000-8000-000000000002', publication_id_value,
    (response ->> 'confirmedRevision')::bigint, 'publication.restore',
    '{"reason":"Safety review complete","publicReason":"Publicación restaurada."}',
    '{"clientVersion":"7.0.0+db","surface":"wave7a_control_center"}'
  );
  health := public.get_pachanga_public_competition_platform_health_v1();
  perform pg_temp.assert_true((health #>> '{readModels,privacyViolations}')::integer = 0,
    'platform health must report zero public privacy violations');
  perform pg_temp.assert_true((health #>> '{readModels,indexingViolations}')::integer = 0,
    'platform health must report zero indexing violations');
  perform pg_temp.assert_true((health #>> '{readModels,stale}')::integer = 0,
    'platform health must report zero stale read models');
end;
$$;

do $$
begin
  perform pg_temp.assert_true(
    not has_table_privilege('anon', 'public.pachanga_competition_publications', 'SELECT')
      and not has_table_privilege('authenticated', 'public.pachanga_competition_publications', 'SELECT')
      and not has_table_privilege('anon', 'public.pachanga_competition_registration_requests', 'SELECT')
      and not has_table_privilege('authenticated', 'public.pachanga_competition_registration_requests', 'UPDATE'),
    'public authority tables must not be directly accessible to clients'
  );
  perform pg_temp.assert_true(
    has_function_privilege('anon', 'public.get_pachanga_public_competition_directory_v1(text,text,text,text,text,text,integer,integer)', 'EXECUTE')
      and has_function_privilege('authenticated', 'public.command_pachanga_competition_registration_request_v1(uuid,uuid,bigint,text,jsonb,jsonb)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.command_pachanga_competition_registration_request_v1(uuid,uuid,bigint,text,jsonb,jsonb)', 'EXECUTE')
      and not has_function_privilege('anon', 'public.command_pachanga_public_competition_moderation_v1(uuid,uuid,bigint,text,jsonb,jsonb)', 'EXECUTE'),
    'RPC execute grants must match anonymous, authenticated and platform boundaries'
  );
  perform pg_temp.assert_true((
    select count(*) from public.pachanga_competition_invalidations
    where entity_type = 'competition_registration_request'
      and target_group_id is not null
      and target_user_id is not null
  ) >= 8, 'registration changes must emit scoped Realtime invalidations');
  perform pg_temp.assert_true(not exists (
    select 1 from public.pachanga_competition_invalidations invalidations
    where to_jsonb(invalidations)::text like '%@example.test%'
      or to_jsonb(invalidations)::text like '%+34%'
  ), 'Realtime invalidations must contain no PII');
end;
$$;

select 'PUBLIC_COMPETITIONS_V1_DB_OK';
