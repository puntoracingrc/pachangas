\set ON_ERROR_STOP on

begin;
set local lock_timeout = '5s';
set local statement_timeout = '20min';
set local synchronous_commit = off;
set constraints all deferred;

create temporary table scale_venues (
  n integer primary key,
  id uuid not null unique,
  club_id uuid not null,
  owner_id uuid not null
) on commit drop;

create temporary table scale_pitches (
  n integer primary key,
  id uuid not null unique,
  venue_n integer not null,
  venue_id uuid not null,
  club_id uuid not null,
  owner_id uuid not null
) on commit drop;

create temporary table scale_requests (
  n integer primary key,
  id uuid not null unique,
  venue_id uuid not null,
  pitch_id uuid not null,
  local_start timestamp without time zone not null,
  local_end timestamp without time zone not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null
) on commit drop;

create temporary table scale_metrics (
  metric text not null,
  duration_ms double precision not null check (duration_ms >= 0)
) on commit drop;

-- The first Venue belongs to the deterministic Wave 9A Club. The remaining
-- 999 Clubs and owners exist only inside this rollback transaction so a Club
-- desk sees realistic bounded tenancy instead of one artificial mega-tenant.
insert into auth.users(id,email,email_confirmed_at,raw_user_meta_data)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-owner:'||series.n),
  'wave9a-scale-owner-'||series.n||'@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name','Wave 9A Scale Owner '||series.n)
from generate_series(2,1000) series(n);

insert into public.pachanga_clubs(
  id,name,slug,description,club_type,country_code,province,municipality,
  general_area,visibility,operational_status,verification_status,
  partnership_status,primary_owner_id,created_by
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-club:'||series.n),
  'Club Escala Wave 9A '||series.n,
  'club-escala-wave9a-'||series.n,
  'Entidad sintética efímera para medir el aislamiento por Club.',
  'SPORTS_CENTER','ES','Barcelona','Barcelona','Zona escala',
  'private','active','unverified','none',
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-owner:'||series.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-owner:'||series.n)
from generate_series(2,1000) series(n);

insert into public.pachanga_club_memberships(
  club_id,user_id,role,status,accepted_at,invited_by
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-club:'||series.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-owner:'||series.n),
  'club_owner','active',clock_timestamp(),
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-owner:'||series.n)
from generate_series(2,1000) series(n);

insert into scale_venues(n,id,club_id,owner_id)
select
  series.n,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-venue:'||series.n),
  case when series.n=1
    then 'e9020000-0000-4000-8000-000000000001'::uuid
    else private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-club:'||series.n)
  end,
  case when series.n=1
    then 'e9010000-0000-4000-8000-000000000001'::uuid
    else private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-owner:'||series.n)
  end
from generate_series(1,1000) series(n);

insert into public.pachanga_club_venues(
  id,club_id,name,slug,description,municipality,general_area,timezone,
  private_address,public_address,public_latitude,public_longitude,
  visibility,lifecycle,public_content_fingerprint,revision,operation_id,
  created_by,updated_by
)
select
  venues.id,venues.club_id,'Campo Escala '||venues.n,'campo-escala-'||venues.n,
  'Venue público sintético para la prueba de 1.000 instalaciones.',
  'Barcelona','Zona escala '||((venues.n-1)%20+1),'Europe/Madrid',
  'Dirección privada sintética '||venues.n,'Zona deportiva '||venues.n,
  41.300000 + (venues.n%500)::numeric/100000,
  2.100000 + (venues.n%500)::numeric/100000,
  'PUBLIC','ACTIVE',repeat('a',64),1,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-venue-op:'||venues.n),
  venues.owner_id,venues.owner_id
from scale_venues venues;

insert into private.pachanga_venue_publication_consents(
  venue_id,version,purpose,selected_fields,public_address_mode,
  public_rate_allowed,content_fingerprint,status,revision,operation_id,
  consented_by,server_sequence
)
select
  venues.id,1,'PUBLIC_VENUE_PROFILE',
  '{"description":true,"address":true,"coordinates":true}'::jsonb,
  'APPROXIMATE_COORDINATES',false,repeat('a',64),'ACTIVE',1,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-consent-op:'||venues.n),
  venues.owner_id,nextval('private.pachanga_venue_sequence')
from scale_venues venues;

insert into scale_pitches(n,id,venue_n,venue_id,club_id,owner_id)
select
  (venues.n-1)*5+pitch_no.n,
  private.pachanga_venue_deterministic_uuid_v1(
    'wave9a-scale-pitch:'||((venues.n-1)*5+pitch_no.n)
  ),
  venues.n,venues.id,venues.club_id,venues.owner_id
from scale_venues venues
cross join generate_series(1,5) pitch_no(n);

insert into public.pachanga_venue_pitches(
  id,venue_id,conflict_scope_id,name,slug,modalities,surface,environment,
  has_lighting,has_changing_rooms,has_showers,is_accessible,has_parking,
  public_rate_kind,status,visibility,minimum_slot_minutes,buffer_minutes,
  revision,operation_id,created_by,updated_by
)
select
  pitches.id,pitches.venue_id,pitches.id,'Pista '||pitches.n,
  'pista-'||((pitches.n-1)%5+1),array['F7']::text[],
  'ARTIFICIAL_GRASS','OUTDOOR',true,true,true,(pitches.n%3=0),(pitches.n%2=0),
  'CONTACT_CLUB','ACTIVE','PUBLIC',60,0,1,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-pitch-op:'||pitches.n),
  pitches.owner_id,pitches.owner_id
from scale_pitches pitches;

-- 40.000 recurring templates plus 10.000 exceptions = exactly 50.000
-- availability records in the requested corpus.
insert into public.pachanga_venue_availability_templates(
  id,venue_id,pitch_id,weekday,start_local_time,end_local_time,slot_minutes,
  buffer_minutes,valid_from,valid_until,timezone,modalities,capacity,
  visibility,status,revision,operation_id,created_by,updated_by
)
select
  private.pachanga_venue_deterministic_uuid_v1(
    'wave9a-scale-template:'||pitches.n||':'||template_no.n
  ),
  pitches.venue_id,pitches.id,
  case when template_no.n=8 then 1 else template_no.n end,
  '18:00'::time,'23:00'::time,60,0,'2027-01-01'::date,'2045-12-31'::date,
  'Europe/Madrid',array['F7']::text[],1,'PUBLIC','ACTIVE',1,
  private.pachanga_venue_deterministic_uuid_v1(
    'wave9a-scale-template-op:'||pitches.n||':'||template_no.n
  ),
  pitches.owner_id,pitches.owner_id
from scale_pitches pitches
cross join generate_series(1,8) template_no(n);

insert into public.pachanga_venue_availability_exceptions(
  id,venue_id,pitch_id,exception_kind,starts_at,ends_at,public_reason,
  private_reason,visibility,priority,status,revision,operation_id,
  created_by,updated_by
)
select
  private.pachanga_venue_deterministic_uuid_v1(
    'wave9a-scale-exception:'||pitches.n||':'||exception_no.n
  ),
  pitches.venue_id,pitches.id,'MAINTENANCE',
  ('2046-01-01 08:00:00+00'::timestamptz
    + make_interval(days=>((pitches.n-1)%365)+exception_no.n))::timestamptz,
  ('2046-01-01 10:00:00+00'::timestamptz
    + make_interval(days=>((pitches.n-1)%365)+exception_no.n))::timestamptz,
  'Mantenimiento sintético','Detalle privado sintético','PRIVATE',100,
  'ACTIVE',1,
  private.pachanga_venue_deterministic_uuid_v1(
    'wave9a-scale-exception-op:'||pitches.n||':'||exception_no.n
  ),
  pitches.owner_id,pitches.owner_id
from scale_pitches pitches
cross join generate_series(1,2) exception_no(n);

insert into scale_requests(
  n,id,venue_id,pitch_id,local_start,local_end,starts_at,ends_at,status
)
with request_plan as (
  select
    series.n,
    case
      when series.n between 1 and 20
        or series.n between 50061 and 50140 then 1
      else ((series.n-21)%4999)+2
    end pitch_n,
    case
      when series.n between 1 and 20
        then '2030-01-07'::date + (series.n-1)*7
      when series.n between 50061 and 50080
        then '2035-01-01'::date + (series.n-50061)*7
      when series.n between 50081 and 50100
        then '2035-01-01'::date + (series.n-50081+30)*7
      when series.n between 50101 and 50120
        then '2035-01-01'::date + (series.n-50101+60)*7
      when series.n between 50121 and 50140
        then '2030-01-07'::date + (series.n-50121)*7
      else '2032-01-05'::date + floor((series.n-21)::numeric/4999)::integer*7
    end local_day,
    case
      when series.n<=50000 then 'CONFIRMED'
      when series.n between 50101 and 50120 then 'DRAFT'
      else 'SUBMITTED'
    end status
  from generate_series(1,100000) series(n)
), local_values as (
  select request_plan.*,
    request_plan.local_day::timestamp+'20:00'::time local_start,
    request_plan.local_day::timestamp+'21:00'::time local_end
  from request_plan
)
select
  local_values.n,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-request:'||local_values.n),
  pitches.venue_id,pitches.id,local_values.local_start,local_values.local_end,
  local_values.local_start at time zone 'Europe/Madrid',
  local_values.local_end at time zone 'Europe/Madrid',
  local_values.status
from local_values
join scale_pitches pitches on pitches.n=local_values.pitch_n;

insert into public.pachanga_venue_reservation_requests(
  id,venue_id,pitch_id,requester_kind,requester_user_id,requester_team_id,
  purpose,modality,starts_at,ends_at,requested_local_start,requested_local_end,
  timezone,resolved_offset_minutes,criteria,alternatives,message,
  current_proposal,status,revision,operation_id,created_by,updated_by,
  submitted_at,resolved_at
)
select
  requests.id,requests.venue_id,requests.pitch_id,'TEAM',
  'c4010000-0000-4000-8000-000000000003',
  'c4100000-0000-4000-8000-000000000002',
  'STANDALONE_MATCH','F7',requests.starts_at,requests.ends_at,
  requests.local_start,requests.local_end,'Europe/Madrid',
  private.pachanga_venue_offset_minutes_v1(requests.starts_at,'Europe/Madrid'),
  '{}'::jsonb,'[]'::jsonb,'','{}'::jsonb,requests.status,1,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-request-op:'||requests.n),
  'c4010000-0000-4000-8000-000000000003',
  'c4010000-0000-4000-8000-000000000003',
  case when requests.status='DRAFT' then null else clock_timestamp() end,
  case when requests.status='CONFIRMED' then clock_timestamp() else null end
from scale_requests requests;

insert into private.pachanga_venue_reservation_terms(
  id,request_id,terms_kind,public_rate_allowed,private_notes,
  cancellation_terms,terms_snapshot,version,operation_id,created_by,
  server_sequence
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-terms:'||requests.n),
  requests.id,'CONTACT_CLUB',false,'','','{"kind":"CONTACT_CLUB"}'::jsonb,1,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-terms-op:'||requests.n),
  'e9010000-0000-4000-8000-000000000003',
  nextval('private.pachanga_venue_sequence')
from scale_requests requests where requests.n<=50000;

insert into public.pachanga_venue_pitch_claims(
  id,pitch_id,conflict_scope_id,source_kind,source_id,starts_at,ends_at,
  status,operation_id,server_sequence
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-claim:'||requests.n),
  requests.pitch_id,pitches.conflict_scope_id,'RESERVATION',
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-reservation:'||requests.n),
  requests.starts_at,requests.ends_at,'ACTIVE',
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-claim-op:'||requests.n),
  nextval('private.pachanga_venue_sequence')
from scale_requests requests
join public.pachanga_venue_pitches pitches on pitches.id=requests.pitch_id
where requests.n<=50000;

insert into public.pachanga_venue_reservations(
  id,request_id,venue_id,pitch_id,requester_user_id,requester_team_id,
  terms_id,claim_id,starts_at,ends_at,timezone,status,revision,
  operation_id,accepted_by,confirmed_by,confirmed_at
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-reservation:'||requests.n),
  requests.id,requests.venue_id,requests.pitch_id,
  'c4010000-0000-4000-8000-000000000003',
  'c4100000-0000-4000-8000-000000000002',
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-terms:'||requests.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-claim:'||requests.n),
  requests.starts_at,requests.ends_at,'Europe/Madrid','CONFIRMED',1,
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-reservation-op:'||requests.n),
  'e9010000-0000-4000-8000-000000000003',
  'c4010000-0000-4000-8000-000000000003',clock_timestamp()
from scale_requests requests where requests.n<=50000;

update public.pachanga_venue_reservation_requests requests set
  current_reservation_id=private.pachanga_venue_deterministic_uuid_v1(
    'wave9a-scale-reservation:'||scale_requests.n
  )
from scale_requests
where requests.id=scale_requests.id and scale_requests.n<=50000;

insert into public.pachanga_canonical_matches(id,status,revision,created_by)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-match:'||series.n),
  'active',1,'c4010000-0000-4000-8000-000000000003'
from generate_series(1,20) series(n);

insert into public.pachanga_venue_invalidations(
  server_sequence,entity_type,entity_id,revision,audience_kind
)
select
  nextval('private.pachanga_venue_sequence'),'venue',venues.id::text,1,'PUBLIC'
from generate_series(1,100000) series(n)
join scale_venues venues on venues.n=((series.n-1)%1000)+1;

analyze public.pachanga_club_venues;
analyze public.pachanga_venue_pitches;
analyze public.pachanga_venue_availability_templates;
analyze public.pachanga_venue_availability_exceptions;
analyze public.pachanga_venue_reservation_requests;
analyze public.pachanga_venue_pitch_claims;
analyze public.pachanga_venue_reservations;
analyze public.pachanga_venue_invalidations;

do $$
declare actual jsonb;
begin
  select jsonb_build_object(
    'venues',(select count(*) from public.pachanga_club_venues),
    'pitches',(select count(*) from public.pachanga_venue_pitches),
    'templates',(select count(*) from public.pachanga_venue_availability_templates),
    'exceptions',(select count(*) from public.pachanga_venue_availability_exceptions),
    'availabilityTotal',(
      select count(*) from public.pachanga_venue_availability_templates
    )+(
      select count(*) from public.pachanga_venue_availability_exceptions
    ),
    'requests',(select count(*) from public.pachanga_venue_reservation_requests),
    'reservations',(select count(*) from public.pachanga_venue_reservations),
    'invalidations',(select count(*) from public.pachanga_venue_invalidations)
  ) into actual;
  if actual<>jsonb_build_object(
    'venues',1000,'pitches',5000,'templates',40000,'exceptions',10000,
    'availabilityTotal',50000,'requests',100000,'reservations',50000,
    'invalidations',100000
  ) then raise exception 'WAVE9A_SCALE_CORPUS_MISMATCH:%',actual; end if;
end;
$$;

-- Canonical read-model latency: 25 warm samples per operation.
do $$
declare started timestamptz;
declare iteration integer;
declare pitch_id uuid:=private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-pitch:1');
begin
  for iteration in 1..25 loop
    started:=clock_timestamp();
    perform public.get_pachanga_public_venues_v1('{"municipality":"Barcelona","modality":"F7"}',1,24);
    insert into scale_metrics values('directory',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform public.get_pachanga_venue_availability_v1(
      pitch_id,'2035-01-01 00:00:00+01','2035-01-15 00:00:00+01','F7'
    );
    insert into scale_metrics values('availability_query',extract(epoch from clock_timestamp()-started)*1000);
  end loop;

  perform set_config('request.jwt.claims','{"sub":"e9010000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  for iteration in 1..25 loop
    started:=clock_timestamp();
    perform public.get_pachanga_club_venue_desk_v1(
      'e9020000-0000-4000-8000-000000000001'
    );
    insert into scale_metrics values('reservation_desk',extract(epoch from clock_timestamp()-started)*1000);
  end loop;

  for iteration in 1..25 loop
    started:=clock_timestamp();
    perform private.pachanga_venue_health_v1();
    insert into scale_metrics values('health',extract(epoch from clock_timestamp()-started)*1000);
  end loop;

  for iteration in 1..25 loop
    started:=clock_timestamp();
    perform public.get_pachanga_venue_control_center_v1();
    insert into scale_metrics values('control_center',extract(epoch from clock_timestamp()-started)*1000);
  end loop;
end;
$$;

-- Canonical write latency: each command executes fully, then the surrounding
-- PL/pgSQL subtransaction is intentionally rolled back so corpus cardinality
-- remains exact for every sample.
do $$
declare started timestamptz;
declare iteration integer;
declare request_id uuid;
declare reservation_id uuid;
declare canonical_match_id uuid;
declare error_text text;
begin
  perform set_config('request.jwt.claims','{"sub":"c4010000-0000-4000-8000-000000000003","role":"authenticated"}',true);
  for iteration in 1..20 loop
    request_id:=private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-request:'||(50100+iteration));
    started:=clock_timestamp();
    begin
      perform public.command_pachanga_venue_reservation_v1(
        private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-submit-op:'||iteration),
        request_id,1,'reservation.request.submit','{}','{"clientVersion":"9.0.0+scale","surface":"scale"}'
      );
      raise exception 'WAVE9A_SCALE_SAMPLE_ROLLBACK';
    exception when others then
      if sqlerrm<>'WAVE9A_SCALE_SAMPLE_ROLLBACK' then raise; end if;
    end;
    insert into scale_metrics values('request_submit',extract(epoch from clock_timestamp()-started)*1000);
  end loop;

  perform set_config('request.jwt.claims','{"sub":"e9010000-0000-4000-8000-000000000003","role":"authenticated"}',true);
  for iteration in 1..20 loop
    request_id:=private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-request:'||(50080+iteration));
    started:=clock_timestamp();
    begin
      perform public.command_pachanga_venue_reservation_v1(
        private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-hold-op:'||iteration),
        request_id,1,'reservation.hold','{"expiresInMinutes":15}',
        '{"clientVersion":"9.0.0+scale","surface":"scale"}'
      );
      raise exception 'WAVE9A_SCALE_SAMPLE_ROLLBACK';
    exception when others then
      if sqlerrm<>'WAVE9A_SCALE_SAMPLE_ROLLBACK' then raise; end if;
    end;
    insert into scale_metrics values('hold',extract(epoch from clock_timestamp()-started)*1000);
  end loop;

  for iteration in 1..20 loop
    request_id:=private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-request:'||(50060+iteration));
    started:=clock_timestamp();
    begin
      perform public.command_pachanga_venue_reservation_v1(
        private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-accept-op:'||iteration),
        request_id,1,'reservation.accept','{"terms":{"kind":"CONTACT_CLUB"}}',
        '{"clientVersion":"9.0.0+scale","surface":"scale"}'
      );
      raise exception 'WAVE9A_SCALE_SAMPLE_ROLLBACK';
    exception when others then
      if sqlerrm<>'WAVE9A_SCALE_SAMPLE_ROLLBACK' then raise; end if;
    end;
    insert into scale_metrics values('accept',extract(epoch from clock_timestamp()-started)*1000);
  end loop;

  for iteration in 1..20 loop
    request_id:=private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-request:'||(50120+iteration));
    started:=clock_timestamp();
    error_text:=null;
    begin
      perform public.command_pachanga_venue_reservation_v1(
        private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-conflict-op:'||iteration),
        request_id,1,'reservation.accept','{"terms":{"kind":"CONTACT_CLUB"}}',
        '{"clientVersion":"9.0.0+scale","surface":"scale"}'
      );
      raise exception 'WAVE9A_EXPECTED_CONFLICT_NOT_RAISED';
    exception when others then
      error_text:=sqlerrm;
      if error_text !~ 'VENUE_SLOT_CONFLICT' then raise; end if;
    end;
    insert into scale_metrics values('conflict_detection',extract(epoch from clock_timestamp()-started)*1000);
  end loop;

  perform set_config('request.jwt.claims','{"sub":"c4010000-0000-4000-8000-000000000003","role":"authenticated"}',true);
  for iteration in 1..20 loop
    reservation_id:=private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-reservation:'||iteration);
    canonical_match_id:=private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-match:'||iteration);
    started:=clock_timestamp();
    begin
      perform public.command_pachanga_venue_reservation_v1(
        private.pachanga_venue_deterministic_uuid_v1('wave9a-scale-bind-op:'||iteration),
        reservation_id,1,'reservation.bind_match',
        jsonb_build_object('canonicalMatchId',canonical_match_id),
        '{"clientVersion":"9.0.0+scale","surface":"scale"}'
      );
      raise exception 'WAVE9A_SCALE_SAMPLE_ROLLBACK';
    exception when others then
      if sqlerrm<>'WAVE9A_SCALE_SAMPLE_ROLLBACK' then raise; end if;
    end;
    insert into scale_metrics values('match_binding',extract(epoch from clock_timestamp()-started)*1000);
  end loop;
end;
$$;

do $$
declare actual jsonb;
begin
  select jsonb_build_object(
    'requests',(select count(*) from public.pachanga_venue_reservation_requests),
    'reservations',(select count(*) from public.pachanga_venue_reservations),
    'holds',(select count(*) from public.pachanga_venue_reservation_holds),
    'bindings',(select count(*) from public.pachanga_venue_match_bindings),
    'invalidations',(select count(*) from public.pachanga_venue_invalidations)
  ) into actual;
  if actual<>jsonb_build_object(
    'requests',100000,'reservations',50000,'holds',0,'bindings',0,
    'invalidations',100000
  ) then raise exception 'WAVE9A_SCALE_WRITE_ROLLBACK_MISMATCH:%',actual; end if;
end;
$$;

with metric_summary as (
  select metric,count(*) samples,
    round((percentile_cont(0.5) within group(order by duration_ms))::numeric,3) p50_ms,
    round((percentile_cont(0.95) within group(order by duration_ms))::numeric,3) p95_ms,
    round(max(duration_ms)::numeric,3) max_ms
  from scale_metrics group by metric
), corpus as (
  select jsonb_build_object(
    'venues',(select count(*) from public.pachanga_club_venues),
    'pitches',(select count(*) from public.pachanga_venue_pitches),
    'availabilityTemplates',(select count(*) from public.pachanga_venue_availability_templates),
    'availabilityExceptions',(select count(*) from public.pachanga_venue_availability_exceptions),
    'availabilityTotal',(
      select count(*) from public.pachanga_venue_availability_templates
    )+(
      select count(*) from public.pachanga_venue_availability_exceptions
    ),
    'reservationRequests',(select count(*) from public.pachanga_venue_reservation_requests),
    'reservations',(select count(*) from public.pachanga_venue_reservations),
    'invalidations',(select count(*) from public.pachanga_venue_invalidations)
  ) value
), storage as (
  select jsonb_build_object(
    'venueTableAndIndexBytes',coalesce(sum(pg_total_relation_size(format('%I.%I',tables.schemaname,tables.tablename)::regclass)),0),
    'venueIndexBytes',coalesce((
      select sum(pg_relation_size(indexes.indexrelid))
      from pg_stat_user_indexes indexes
      where indexes.relname like 'pachanga_venue%'
         or indexes.relname='pachanga_club_venues'
    ),0)
  ) value
  from pg_tables tables
  where tables.schemaname in ('public','private')
    and (tables.tablename like 'pachanga_venue%' or tables.tablename='pachanga_club_venues')
)
select jsonb_build_object(
  'database','ephemeral-local',
  'corpus',(select value from corpus),
  'metrics',(
    select jsonb_object_agg(metric,jsonb_build_object(
      'samples',samples,'p50Ms',p50_ms,'p95Ms',p95_ms,'maxMs',max_ms
    ) order by metric) from metric_summary
  ),
  'storage',(select value from storage),
  'writeSamplesRolledBack',true,
  'fullRollback','PENDING'
)::text;

rollback;
