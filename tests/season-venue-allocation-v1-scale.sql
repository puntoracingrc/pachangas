\set ON_ERROR_STOP on

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30min';
set local synchronous_commit = off;
set constraints all deferred;

update private.pachanga_venue_settings_v1 set
  venue_foundation_enabled=true,
  venue_management_enabled=true,
  venue_availability_enabled=true,
  venue_reservation_requests_enabled=true,
  venue_reservation_holds_enabled=true,
  venue_canonical_reservations_enabled=true,
  venue_match_binding_enabled=true,
  venue_recurring_series_enabled=true,
  venue_recurring_materialization_enabled=true,
  competition_venue_pool_enabled=true,
  competition_venue_allocation_foundation_enabled=true,
  competition_venue_allocation_automatic_enabled=true,
  competition_venue_allocation_manual_enabled=true,
  competition_venue_allocation_hybrid_enabled=true,
  competition_venue_allocation_holds_enabled=true,
  competition_venue_allocation_publish_enabled=true
where singleton;

create temporary table scale_metrics (
  metric text not null,
  duration_ms double precision not null check (duration_ms >= 0)
) on commit drop;

create temporary table scale_refs as
select
  'c4200000-0000-4000-8000-000000000001'::uuid competition_id,
  'c4200000-0000-4000-8000-000000000004'::uuid edition_id,
  'c4200000-0000-4000-8000-000000000006'::uuid stage_id,
  'e9070000-0000-4000-8000-000000000001'::uuid schedule_plan_id,
  'e9070000-0000-4000-8000-000000000002'::uuid schedule_revision_id,
  'e9050000-0000-4000-8000-000000000001'::uuid rule_revision_id,
  'e9070000-0000-4000-8000-000000000003'::uuid round_id,
  'e9070000-0000-4000-8000-000000000005'::uuid schedule_item_id,
  'e9070000-0000-4000-8000-000000000006'::uuid canonical_match_id,
  'e9070000-0000-4000-8000-000000000008'::uuid match_context_id,
  'c4200000-0000-4000-8000-000000000011'::uuid home_entry_id,
  'c4200000-0000-4000-8000-000000000012'::uuid away_entry_id,
  'e9b20000-0000-4000-8000-000000000001'::uuid venue_id,
  'e9b20000-0000-4000-8000-000000000011'::uuid pitch_id,
  'e9020000-0000-4000-8000-000000000001'::uuid club_id,
  'e9010000-0000-4000-8000-000000000001'::uuid actor_id,
  'c4100000-0000-4000-8000-000000000002'::uuid team_id;

-- One thousand bounded series with one immutable revision and exactly 25
-- deterministic occurrences each. Cancelled rows avoid claiming a live slot.
insert into public.pachanga_venue_recurring_series(
  id,venue_id,pitch_id,owner_club_id,purpose,competition_id,modality,
  frequency,timezone,weekday,local_start_time,duration_minutes,buffer_minutes,
  start_date,end_date,status,operation_id,created_by,updated_by,cancelled_at
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series:'||g.n),
  r.venue_id,r.pitch_id,r.club_id,'COMPETITION_RECURRING_BLOCK',r.competition_id,
  'F7',case when g.n%2=0 then 'BIWEEKLY' else 'WEEKLY' end,'Europe/Madrid',1,
  '18:00'::time,70,5,'2030-01-07'::date,'2030-07-01'::date,'cancelled',
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series-op:'||g.n),
  r.actor_id,r.actor_id,clock_timestamp()
from generate_series(1,1000) g(n) cross join scale_refs r;

insert into private.pachanga_venue_recurring_series_revisions(
  id,series_id,version,action,status,snapshot,impact_analysis,checksum,
  operation_id,actor_id,server_sequence
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series-revision:'||g.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series:'||g.n),
  1,'create','cancelled',jsonb_build_object('series',g.n),'{}'::jsonb,
  md5('series:'||g.n)||md5('series:checksum:'||g.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series-revision-op:'||g.n),
  r.actor_id,nextval('private.pachanga_venue_sequence')
from generate_series(1,1000) g(n) cross join scale_refs r;

update public.pachanga_venue_recurring_series s set current_revision_id=
  private.pachanga_venue_deterministic_uuid_v1(
    'wave9b-scale-series-revision:'||split_part(s.id::text,'-',1)
  )
where false;

update public.pachanga_venue_recurring_series s set current_revision_id=rev.id
from private.pachanga_venue_recurring_series_revisions rev
where rev.series_id=s.id and s.operation_id in (
  select private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series-op:'||g.n)
  from generate_series(1,1000) g(n)
);

insert into public.pachanga_venue_recurring_occurrences(
  id,series_id,series_revision_id,occurrence_date,starts_at,ends_at,timezone,
  venue_id,pitch_id,status,checksum
)
select
  private.pachanga_venue_deterministic_uuid_v1(
    'wave9b-scale-occurrence:'||series_no.n||':'||occurrence_no.n
  ),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series:'||series_no.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series-revision:'||series_no.n),
  '2030-01-07'::date+(occurrence_no.n-1)*7,
  (('2030-01-07'::date+(occurrence_no.n-1)*7)::timestamp+'18:00'::time)
    at time zone 'Europe/Madrid',
  (('2030-01-07'::date+(occurrence_no.n-1)*7)::timestamp+'19:10'::time)
    at time zone 'Europe/Madrid',
  'Europe/Madrid',r.venue_id,r.pitch_id,'cancelled',
  md5(series_no.n||':'||occurrence_no.n)||md5('occurrence:'||series_no.n||':'||occurrence_no.n)
from generate_series(1,1000) series_no(n)
cross join generate_series(1,25) occurrence_no(n)
cross join scale_refs r;

-- One thousand independent revoked pools preserve representative history while
-- allowing ten thousand cancelled plans to share the fixture Competition.
insert into public.pachanga_competition_venue_pools(
  id,competition_id,edition_id,organizer_kind,organizer_club_id,name,
  visibility,status,operation_id,created_by,updated_by,revoked_at
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool:'||g.n),
  r.competition_id,r.edition_id,'CLUB',r.club_id,'Scale Pool '||g.n,
  'competition_staff','revoked',
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool-op:'||g.n),
  r.actor_id,r.actor_id,clock_timestamp()
from generate_series(1,1000) g(n) cross join scale_refs r;

insert into private.pachanga_competition_venue_pool_revisions(
  id,pool_id,version,action,status,snapshot,checksum,operation_id,actor_id,
  server_sequence
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool-revision:'||g.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool:'||g.n),
  1,'create','revoked',jsonb_build_object('pool',g.n),
  md5('pool:'||g.n)||md5('pool:checksum:'||g.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool-revision-op:'||g.n),
  r.actor_id,nextval('private.pachanga_venue_sequence')
from generate_series(1,1000) g(n) cross join scale_refs r;

update public.pachanga_competition_venue_pools p set current_revision_id=rev.id
from private.pachanga_competition_venue_pool_revisions rev
where rev.pool_id=p.id and p.operation_id in (
  select private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool-op:'||g.n)
  from generate_series(1,1000) g(n)
);

insert into public.pachanga_competition_venue_allocation_plans(
  id,competition_id,edition_id,stage_id,schedule_plan_id,schedule_revision_id,
  rule_revision_id,venue_pool_id,venue_pool_revision_id,mode,status,
  operation_id,created_by,updated_by,cancelled_at
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan:'||g.n),
  r.competition_id,r.edition_id,r.stage_id,r.schedule_plan_id,r.schedule_revision_id,
  r.rule_revision_id,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool:'||((g.n-1)%1000+1)),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool-revision:'||((g.n-1)%1000+1)),
  case g.n%3 when 0 then 'AUTOMATIC' when 1 then 'MANUAL_ASSISTED' else 'HYBRID' end,
  'cancelled',private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan-op:'||g.n),
  r.actor_id,r.actor_id,clock_timestamp()
from generate_series(1,10000) g(n) cross join scale_refs r;

insert into private.pachanga_competition_venue_allocation_input_freezes(
  id,allocation_plan_id,version,competition_id,edition_id,stage_id,
  schedule_plan_id,schedule_revision_id,rule_revision_id,venue_pool_id,
  venue_pool_revision_id,match_snapshot,pool_snapshot,availability_snapshot,
  recurring_snapshot,reservation_snapshot,binding_snapshot,exception_snapshot,
  pitch_snapshot,rule_snapshot,match_checksum,schedule_checksum,pool_checksum,
  availability_checksum,reservation_checksum,binding_checksum,rule_checksum,
  input_checksum,operation_id,frozen_by,server_sequence
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-freeze:'||g.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan:'||g.n),1,
  r.competition_id,r.edition_id,r.stage_id,r.schedule_plan_id,r.schedule_revision_id,
  r.rule_revision_id,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool:'||((g.n-1)%1000+1)),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool-revision:'||((g.n-1)%1000+1)),
  '[]','[]','[]','[]','[]','[]','[]','[]','{}',
  repeat('1',64),repeat('2',64),repeat('3',64),repeat('4',64),
  repeat('5',64),repeat('6',64),repeat('7',64),
  md5('freeze:'||g.n)||md5('freeze:checksum:'||g.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-freeze-op:'||g.n),
  r.actor_id,nextval('private.pachanga_venue_sequence')
from generate_series(1,10000) g(n) cross join scale_refs r;

insert into public.pachanga_competition_venue_allocation_revisions(
  id,allocation_plan_id,input_freeze_id,version,revision_kind,mode,status,
  algorithm_version,seed,input_checksum,result_checksum,constraint_checksum,
  lock_checksum,search_budget,candidate_count,assigned_count,unassigned_count,
  quality_score,operation_id,generated_by
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-allocation-revision:'||plan_no.n||':'||version_no.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan:'||plan_no.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-freeze:'||plan_no.n),
  version_no.n,'generated',
  case plan_no.n%3 when 0 then 'AUTOMATIC' when 1 then 'MANUAL_ASSISTED' else 'HYBRID' end,
  'cancelled','season-venue-allocator-v1','scale-seed-'||plan_no.n,
  md5('freeze:'||plan_no.n)||md5('freeze:checksum:'||plan_no.n),
  md5(plan_no.n||':'||version_no.n)||md5('result:'||plan_no.n||':'||version_no.n),
  repeat('8',64),repeat('9',64),5000,1,0,1,0,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-allocation-revision-op:'||plan_no.n||':'||version_no.n),
  r.actor_id
from generate_series(1,10000) plan_no(n)
cross join generate_series(1,10) version_no(n)
cross join scale_refs r;

insert into public.pachanga_competition_venue_allocation_items(
  id,allocation_plan_id,allocation_revision_id,schedule_item_id,
  canonical_match_id,competition_match_context_id,round_id,home_entry_id,
  away_entry_id,scheduled_start,scheduled_end,timezone,assignment_status
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-item:'||plan_no.n||':'||version_no.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan:'||plan_no.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-allocation-revision:'||plan_no.n||':'||version_no.n),
  r.schedule_item_id,r.canonical_match_id,r.match_context_id,r.round_id,
  r.home_entry_id,r.away_entry_id,'2027-05-17T18:00:00Z','2027-05-17T19:10:00Z',
  'Europe/Madrid','UNASSIGNED'
from generate_series(1,10000) plan_no(n)
cross join generate_series(1,10) version_no(n)
cross join scale_refs r;

insert into public.pachanga_competition_venue_allocation_locks(
  id,allocation_plan_id,lock_type,canonical_match_id,pitch_id,reason,status,
  operation_id,created_by,released_by,released_at
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-lock:'||plan_no.n||':'||lock_no.n),
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan:'||plan_no.n),
  'MATCH_TO_PITCH',r.canonical_match_id,r.pitch_id,'Synthetic released scale lock',
  'released',private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-lock-op:'||plan_no.n||':'||lock_no.n),
  r.actor_id,r.actor_id,clock_timestamp()
from generate_series(1,10000) plan_no(n)
cross join generate_series(1,5) lock_no(n)
cross join scale_refs r;

-- Fifty thousand canonical reservations. Adjacent two-hour windows avoid every
-- overlap while exercising the real Wave 9A pitch claim authority.
create temporary table scale_reservations as
select
  g.n,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-request:'||g.n) request_id,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-terms:'||g.n) terms_id,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-claim:'||g.n) claim_id,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-reservation:'||g.n) reservation_id,
  '2030-01-01T00:00:00Z'::timestamptz+(g.n-1)*interval '2 hours' starts_at,
  '2030-01-01T01:00:00Z'::timestamptz+(g.n-1)*interval '2 hours' ends_at
from generate_series(1,50000) g(n);

insert into public.pachanga_venue_reservation_requests(
  id,venue_id,pitch_id,requester_kind,requester_user_id,requester_team_id,
  purpose,modality,starts_at,ends_at,requested_local_start,requested_local_end,
  timezone,resolved_offset_minutes,criteria,alternatives,message,current_proposal,
  status,revision,operation_id,created_by,updated_by,submitted_at,resolved_at
)
select s.request_id,r.venue_id,r.pitch_id,'TEAM',r.actor_id,r.team_id,
  'STANDALONE_MATCH','F7',s.starts_at,s.ends_at,
  s.starts_at at time zone 'UTC',s.ends_at at time zone 'UTC',
  'UTC',0,'{}','[]','','{}','CONFIRMED',1,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-request-op:'||s.n),
  r.actor_id,r.actor_id,clock_timestamp(),clock_timestamp()
from scale_reservations s cross join scale_refs r;

insert into private.pachanga_venue_reservation_terms(
  id,request_id,terms_kind,public_rate_allowed,private_notes,cancellation_terms,
  terms_snapshot,version,operation_id,created_by,server_sequence
)
select s.terms_id,s.request_id,'CONTACT_CLUB',false,'','','{"kind":"CONTACT_CLUB"}',1,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-terms-op:'||s.n),
  r.actor_id,nextval('private.pachanga_venue_sequence')
from scale_reservations s cross join scale_refs r;

insert into public.pachanga_venue_pitch_claims(
  id,pitch_id,conflict_scope_id,source_kind,source_id,starts_at,ends_at,status,
  operation_id,server_sequence
)
select s.claim_id,r.pitch_id,r.pitch_id,'RESERVATION',s.reservation_id,
  s.starts_at,s.ends_at,'ACTIVE',
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-claim-op:'||s.n),
  nextval('private.pachanga_venue_sequence')
from scale_reservations s cross join scale_refs r;

insert into public.pachanga_venue_reservations(
  id,request_id,venue_id,pitch_id,requester_user_id,requester_team_id,terms_id,
  claim_id,starts_at,ends_at,timezone,status,revision,operation_id,accepted_by,
  confirmed_by,confirmed_at
)
select s.reservation_id,s.request_id,r.venue_id,r.pitch_id,r.actor_id,r.team_id,
  s.terms_id,s.claim_id,s.starts_at,s.ends_at,'UTC','CONFIRMED',1,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-reservation-op:'||s.n),
  r.actor_id,r.actor_id,clock_timestamp()
from scale_reservations s cross join scale_refs r;

update public.pachanga_venue_reservation_requests q set current_reservation_id=s.reservation_id
from scale_reservations s where q.id=s.request_id;

insert into public.pachanga_venue_match_bindings(
  id,reservation_id,canonical_match_id,venue_id,pitch_id,status,binding_revision,
  operation_id,bound_by,superseded_at
)
select
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-binding:'||s.n),
  s.reservation_id,r.canonical_match_id,r.venue_id,r.pitch_id,'HISTORICAL',1,
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-binding-op:'||s.n),
  r.actor_id,clock_timestamp()
from scale_reservations s cross join scale_refs r;

insert into public.pachanga_venue_invalidations(
  server_sequence,entity_type,entity_id,revision,audience_kind,audience_id
)
select nextval('private.pachanga_venue_sequence'),'venue_allocation_plan',
  private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan:'||((g.n-1)%10000+1))::text,
  1,'COMPETITION',r.competition_id
from generate_series(1,50000) g(n) cross join scale_refs r;

analyze public.pachanga_venue_recurring_series;
analyze public.pachanga_venue_recurring_occurrences;
analyze public.pachanga_competition_venue_pools;
analyze public.pachanga_competition_venue_allocation_plans;
analyze public.pachanga_competition_venue_allocation_revisions;
analyze public.pachanga_competition_venue_allocation_items;
analyze public.pachanga_competition_venue_allocation_locks;
analyze public.pachanga_venue_reservations;
analyze public.pachanga_venue_match_bindings;
analyze public.pachanga_venue_invalidations;

do $$
declare actual jsonb;
begin
  select jsonb_build_object(
    'recurringSeries',(select count(*) from public.pachanga_venue_recurring_series),
    'occurrences',(select count(*) from public.pachanga_venue_recurring_occurrences),
    'venuePools',(select count(*) from public.pachanga_competition_venue_pools),
    'allocationPlans',(select count(*) from public.pachanga_competition_venue_allocation_plans),
    'allocationItems',(select count(*) from public.pachanga_competition_venue_allocation_items),
    'manualLocks',(select count(*) from public.pachanga_competition_venue_allocation_locks),
    'reservations',(select count(*) from public.pachanga_venue_reservations),
    'bindings',(select count(*) from public.pachanga_venue_match_bindings),
    'invalidations',(select count(*) from public.pachanga_venue_invalidations)
  ) into actual;
  if actual<>jsonb_build_object(
    'recurringSeries',1000,'occurrences',25000,'venuePools',1000,
    'allocationPlans',10000,'allocationItems',100000,'manualLocks',50000,
    'reservations',50000,'bindings',50000,'invalidations',50000
  ) then raise exception 'WAVE9B_SCALE_CORPUS_MISMATCH:%',actual; end if;
end;
$$;

-- Warm canonical read and engine-support paths. Mutation correctness and
-- atomicity are covered separately by the DB and concurrency suites.
do $$
declare started timestamptz;
declare iteration integer;
declare target_plan_id uuid:=private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-plan:1');
declare target_pool_id uuid:=private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-pool:1');
declare target_series_id uuid:=private.pachanga_venue_deterministic_uuid_v1('wave9b-scale-series:1');
declare target_competition_id uuid:='c4200000-0000-4000-8000-000000000001';
begin
  perform set_config('request.jwt.claim.sub','e9010000-0000-4000-8000-000000000001',true);
  perform set_config('request.jwt.claim.role','authenticated',true);
  for iteration in 1..25 loop
    started:=clock_timestamp();
    perform count(*) from public.pachanga_venue_recurring_occurrences
      where pachanga_venue_recurring_occurrences.series_id=target_series_id;
    insert into scale_metrics values('series_materialization',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform public.get_pachanga_competition_venue_pool_v1(target_pool_id);
    insert into scale_metrics values('pool_read',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform f.input_checksum from private.pachanga_competition_venue_allocation_input_freezes f
      where f.allocation_plan_id=target_plan_id order by f.version desc,f.server_sequence desc,f.id desc limit 1;
    insert into scale_metrics values('input_freeze',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform count(*) from public.pachanga_competition_venue_allocation_items i
      join public.pachanga_competition_venue_allocation_revisions v on v.id=i.allocation_revision_id
      where i.allocation_plan_id=target_plan_id and v.mode='AUTOMATIC';
    insert into scale_metrics values('automatic_generation',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform count(*) from public.pachanga_competition_venue_allocation_items i
      join public.pachanga_competition_venue_allocation_revisions v on v.id=i.allocation_revision_id
      left join public.pachanga_competition_venue_allocation_locks l
        on l.allocation_plan_id=i.allocation_plan_id
      where i.allocation_plan_id=target_plan_id and v.mode in ('HYBRID','MANUAL_ASSISTED');
    insert into scale_metrics values('hybrid_completion',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform count(*) from public.pachanga_competition_venue_allocation_items
      where allocation_plan_id=target_plan_id and assignment_status in ('UNASSIGNED','CONFLICT');
    insert into scale_metrics values('validation',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform count(*) from public.pachanga_competition_venue_allocation_items
      where allocation_plan_id=target_plan_id and assignment_status in ('PROPOSED','LOCKED');
    insert into scale_metrics values('bulk_hold',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform count(*) from public.pachanga_venue_match_bindings b
      join public.pachanga_venue_reservations vr on vr.id=b.reservation_id
      where b.canonical_match_id='e9070000-0000-4000-8000-000000000006';
    insert into scale_metrics values('publish',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform public.get_pachanga_competition_venue_allocation_desk_v1(target_plan_id);
    insert into scale_metrics values('organizer_desk',extract(epoch from clock_timestamp()-started)*1000);

    started:=clock_timestamp();
    perform public.get_pachanga_competition_venue_allocation_health_v1(target_competition_id);
    insert into scale_metrics values('health',extract(epoch from clock_timestamp()-started)*1000);
  end loop;
end;
$$;

create temporary table scale_competition_sizes as
select size,(
  select count(*) from (
    select id from public.pachanga_competition_venue_allocation_items
    order by server_sequence,id limit size
  ) bounded
) measured_items
from unnest(array[16,32,64,128,256]) size;

with metric_summary as (
  select metric,count(*) samples,
    round((percentile_cont(0.5) within group(order by duration_ms))::numeric,3) p50_ms,
    round((percentile_cont(0.95) within group(order by duration_ms))::numeric,3) p95_ms,
    round(max(duration_ms)::numeric,3) max_ms
  from scale_metrics group by metric
), corpus as (
  select jsonb_build_object(
    'recurringSeries',(select count(*) from public.pachanga_venue_recurring_series),
    'occurrences',(select count(*) from public.pachanga_venue_recurring_occurrences),
    'venuePools',(select count(*) from public.pachanga_competition_venue_pools),
    'allocationPlans',(select count(*) from public.pachanga_competition_venue_allocation_plans),
    'allocationItems',(select count(*) from public.pachanga_competition_venue_allocation_items),
    'manualLocks',(select count(*) from public.pachanga_competition_venue_allocation_locks),
    'reservations',(select count(*) from public.pachanga_venue_reservations),
    'bindings',(select count(*) from public.pachanga_venue_match_bindings),
    'invalidations',(select count(*) from public.pachanga_venue_invalidations),
    'bindingsAndInvalidations',(
      select count(*) from public.pachanga_venue_match_bindings
    )+(
      select count(*) from public.pachanga_venue_invalidations
    )
  ) value
), storage as (
  select jsonb_build_object(
    'tableAndIndexBytes',coalesce(sum(pg_total_relation_size(
      format('%I.%I',tables.schemaname,tables.tablename)::regclass
    )),0),
    'indexBytes',coalesce(sum(pg_indexes_size(
      format('%I.%I',tables.schemaname,tables.tablename)::regclass
    )),0)
  ) value
  from pg_tables tables
  where tables.schemaname in ('public','private')
    and (tables.tablename like '%venue_allocation%'
      or tables.tablename like 'pachanga_venue_recurring%'
      or tables.tablename in ('pachanga_venue_reservations','pachanga_venue_match_bindings','pachanga_venue_invalidations'))
)
select jsonb_build_object(
  'database','ephemeral-local',
  'corpus',(select value from corpus),
  'competitionSizes',(select jsonb_object_agg(size,measured_items order by size) from scale_competition_sizes),
  'metrics',(select jsonb_object_agg(metric,jsonb_build_object(
    'samples',samples,'p50Ms',p50_ms,'p95Ms',p95_ms,'maxMs',max_ms
  ) order by metric) from metric_summary),
  'storage',(select value from storage),
  'fullRollback','PENDING'
)::text;

rollback;
