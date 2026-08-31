\set ON_ERROR_STOP on

grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
grant execute on function auth.jwt() to authenticated, anon;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition,false) then raise exception '%',message; end if;
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'WAVE9B_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure:=sqlerrm;
    if failure='WAVE9B_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)',failure,expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid,target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub',target_user_id,'role',target_role
  )::text,true);
end;
$$;

do $$
#variable_conflict use_variable
declare
  response jsonb;
  replay jsonb;
  series_id uuid;
  series_revision bigint;
  pool_id uuid;
  pool_revision bigint;
  authorization_id uuid;
  plan_id uuid;
  plan_revision bigint;
  second_plan_id uuid;
  second_plan_revision bigint;
  first_validation_sequence bigint;
  first_validation_at timestamptz;
  first_result_checksum text;
  generated_revision_snapshot jsonb;
  desk jsonb;
  catalog jsonb;
begin
  perform pg_temp.assert_true(
    (select count(*) from private.pachanga_venue_settings_v1 settings
      where settings.singleton
        and not settings.venue_recurring_series_enabled
        and not settings.competition_venue_pool_enabled
        and not settings.competition_venue_allocation_foundation_enabled
        and not settings.demo_world_v35_enabled)=1,
    'Wave 9B flags were not born OFF'
  );

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_competition_venue_allocation_v1(
      'e9b10000-0000-4000-8000-000000000001',null,0,'recurring_series.create',
      '{"pitchId":"e9b20000-0000-4000-8000-000000000011","purpose":"COMPETITION_RECURRING_BLOCK","competitionId":"c4200000-0000-4000-8000-000000000001","modality":"F7","frequency":"WEEKLY","timezone":"Europe/Madrid","weekday":1,"localStartTime":"18:00","durationMinutes":70,"startDate":"2027-05-17","endDate":"2027-06-28"}',
      '{}'
    )
  $sql$,'VENUE_.*DISABLED');

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000001');
  perform pg_temp.expect_failure($sql$
    select public.set_pachanga_venue_flags_v1(
      'e9b10000-0000-4000-8000-000000000002',1,
      '{"venuePublicRecurringSalesEnabled":true}','{}'
    )
  $sql$,'VENUE_FUTURE_CAPABILITY_NOT_IMPLEMENTED');

  response:=public.set_pachanga_venue_flags_v1(
    'e9b10000-0000-4000-8000-000000000003',1,
    '{
      "venueFoundationEnabled":true,
      "venueManagementEnabled":true,
      "venuePublicProfilesEnabled":true,
      "venueAvailabilityEnabled":true,
      "venueReservationRequestsEnabled":true,
      "venueReservationHoldsEnabled":true,
      "venueCanonicalReservationsEnabled":true,
      "venueMatchBindingEnabled":true,
      "venueR4dIntegrationEnabled":true,
      "demoWorldV34Enabled":true,
      "venueRecurringSeriesEnabled":true,
      "venueRecurringMaterializationEnabled":true,
      "competitionVenuePoolEnabled":true,
      "competitionVenueAllocationFoundationEnabled":true,
      "competitionVenueAllocationAutomaticEnabled":true,
      "competitionVenueAllocationManualEnabled":true,
      "competitionVenueAllocationHybridEnabled":true,
      "competitionVenueAllocationHoldsEnabled":true,
      "competitionVenueAllocationPublishEnabled":true,
      "demoWorldV35Enabled":true
    }',
    '{"clientVersion":"9.1.0+dbtest","serviceWorkerVersion":"sw-wave9b","installedMode":"standalone","surface":"db"}'
  );
  perform pg_temp.assert_true((response->>'confirmedRevision')::bigint=2,
    'Wave 9B flags did not advance atomically');
  perform pg_temp.assert_true(
    not (public.get_pachanga_venue_flags_v1()->>'jointScheduleVenueOptimizationEnabled')::boolean
      and not (public.get_pachanga_venue_flags_v1()->>'venuePaymentsEnabled')::boolean
      and not (public.get_pachanga_venue_flags_v1()->>'venueExternalCalendarEnabled')::boolean
      and not (public.get_pachanga_venue_flags_v1()->>'venueExternalIntegrationsEnabled')::boolean
      and not (public.get_pachanga_venue_flags_v1()->>'venuePublicRecurringSalesEnabled')::boolean,
    'A Wave 9B future capability was enabled'
  );

  -- Regression W9B-100: a short unique Venue label uses canonical geography,
  -- while an ambiguous duplicate name must remain incompatible.
  perform private.pachanga_referee_assert_available_v1(
    'd6020000-0000-4000-8000-000000000001',
    '2027-05-17 18:00:00+00','2027-05-17 19:10:00+00','Europe/Madrid',
    'FOOTBALL_7','Season Allocation Centre','SAVED'
  );
  insert into public.pachanga_clubs(
    id,name,slug,description,club_type,country_code,province,municipality,
    general_area,visibility,operational_status,verification_status,
    partnership_status,primary_owner_id,created_by
  ) values (
    'e9020000-0000-4000-8000-000000000002','Wave 9B Ambiguity Club',
    'wave-9b-ambiguity-club','Temporary cross-Club Venue ambiguity fixture.',
    'SPORTS_CENTER','ES','Girona','Girona','Zona Synthetic','private','active',
    'unverified','none','e9010000-0000-4000-8000-000000000005',
    'e9010000-0000-4000-8000-000000000005'
  );
  insert into public.pachanga_club_venues(
    id,club_id,name,slug,description,municipality,general_area,timezone,
    private_address,visibility,lifecycle,operation_id,created_by,updated_by
  ) select
    'e9b20000-0000-4000-8000-000000000002',
    'e9020000-0000-4000-8000-000000000002',name,
    'season-allocation-centre-duplicate',description,'Girona',general_area,timezone,
    private_address,visibility,lifecycle,'e9b00000-0000-4000-8000-000000000002',
    created_by,updated_by
  from public.pachanga_club_venues
  where id='e9b20000-0000-4000-8000-000000000001';
  perform pg_temp.expect_failure($sql$
    select private.pachanga_referee_assert_available_v1(
      'd6020000-0000-4000-8000-000000000001',
      '2027-05-17 18:00:00+00','2027-05-17 19:10:00+00','Europe/Madrid',
      'FOOTBALL_7','Season Allocation Centre','SAVED'
    )
  $sql$,'REFEREE_SERVICE_AREA_INCOMPATIBLE');
  delete from public.pachanga_club_venues
  where id='e9b20000-0000-4000-8000-000000000002';
  delete from public.pachanga_clubs
  where id='e9020000-0000-4000-8000-000000000002';

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  perform pg_temp.expect_failure($sql$
    select public.command_pachanga_competition_venue_allocation_v1(
      'e9b10000-0000-4000-8000-000000000004',null,0,'recurring_series.create',
      '{"pitchId":"e9b20000-0000-4000-8000-000000000011","purpose":"COMPETITION_RECURRING_BLOCK","competitionId":"c4200000-0000-4000-8000-000000000001","modality":"F7","frequency":"WEEKLY","timezone":"Europe/Madrid","weekday":1,"localStartTime":"18:00","durationMinutes":70,"startDate":"2027-01-04","endDate":"2028-01-10"}',
      '{}'
    )
  $sql$,'VENUE_RECURRING_HORIZON_INVALID');

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000010',null,0,'recurring_series.create',
    '{"pitchId":"e9b20000-0000-4000-8000-000000000011","purpose":"COMPETITION_RECURRING_BLOCK","competitionId":"c4200000-0000-4000-8000-000000000001","modality":"F7","frequency":"WEEKLY","timezone":"Europe/Madrid","weekday":1,"localStartTime":"20:00","durationMinutes":70,"bufferMinutes":5,"startDate":"2027-05-17","endDate":"2027-06-28"}',
    '{"clientVersion":"9.1.0+dbtest","surface":"recurring-create"}'
  );
  replay:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000010',null,0,'recurring_series.create',
    '{"pitchId":"e9b20000-0000-4000-8000-000000000011","purpose":"COMPETITION_RECURRING_BLOCK","competitionId":"c4200000-0000-4000-8000-000000000001","modality":"F7","frequency":"WEEKLY","timezone":"Europe/Madrid","weekday":1,"localStartTime":"20:00","durationMinutes":70,"bufferMinutes":5,"startDate":"2027-05-17","endDate":"2027-06-28"}',
    '{"clientVersion":"9.1.0+dbtest","surface":"recurring-create"}'
  );
  perform pg_temp.assert_true(response=replay,'Recurring create replay diverged');
  series_id:=(response->>'aggregateId')::uuid;
  series_revision:=(response->>'confirmedRevision')::bigint;

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000011',series_id,series_revision,
    'recurring_series.validate','{}','{}');
  series_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000012',series_id,series_revision,
    'recurring_series.offer','{}','{}');
  series_revision:=(response->>'confirmedRevision')::bigint;

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000013',series_id,series_revision,
    'recurring_series.accept','{}','{}');
  series_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000014',series_id,series_revision,
    'recurring_series.publish','{}','{}');
  series_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000015',series_id,series_revision,
    'recurring_series.materialize','{}','{}');
  series_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000016',series_id,series_revision,
    'recurring_series.materialize','{}','{}');
  series_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_venue_recurring_occurrences rows
      where rows.series_id=series_id)=7,
    'Repeated materialization did not preserve seven deterministic occurrences'
  );
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_venue_recurring_occurrences rows
      where rows.series_id=series_id
        and rows.occurrence_date='2027-05-17'
        and rows.starts_at='2027-05-17T18:00:00Z')=1,
    'Recurring materialization did not preserve Europe/Madrid local time'
  );
  perform pg_temp.assert_true(
    (select count(*)=7 and min(version)=1 and max(version)=7
      from private.pachanga_venue_recurring_series_revisions rows
      where rows.series_id=series_id),
    'Recurring lifecycle did not append every ordered revision'
  );

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000020',null,0,'venue_pool.create',
    '{"competitionId":"c4200000-0000-4000-8000-000000000001","editionId":"c4200000-0000-4000-8000-000000000004","name":"Wave 9B Season Pool","visibility":"competition_staff"}',
    '{}'
  );
  pool_id:=(response->>'aggregateId')::uuid;
  pool_revision:=(response->>'confirmedRevision')::bigint;

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000021',pool_id,pool_revision,'venue_pool.offer',
    jsonb_build_object(
      'ownerClubId','e9020000-0000-4000-8000-000000000001',
      'venueId','e9b20000-0000-4000-8000-000000000001',
      'pitchIds',jsonb_build_array('e9b20000-0000-4000-8000-000000000011','e9b20000-0000-4000-8000-000000000012'),
      'modalities',jsonb_build_array('F7'),'validFrom','2027-01-01','validUntil','2027-12-31',
      'allowedWeekdays',jsonb_build_array(1),'localStartTime','17:00','localEndTime','23:00',
      'capacityPerSlot',1,'priority',10,'visibility','competition_staff',
      'sourceKind','RECURRING_SERIES','recurringSeriesId',series_id
    ),'{}'
  );
  pool_revision:=(response->>'confirmedRevision')::bigint;
  select rows.id into authorization_id
  from public.pachanga_competition_venue_authorizations rows
  where rows.pool_id=pool_id and rows.status='offered';

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000022',authorization_id,1,'venue_pool.accept','{}','{}'
  );
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000023',pool_id,pool_revision,'venue_pool.activate','{}','{}'
  );
  pool_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_competition_venue_pool_memberships rows
      where rows.pool_id=pool_id and rows.status='active')=2,
    'Pool activation did not materialize two authorized Pitch memberships'
  );

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000003');
  catalog:=public.get_pachanga_season_venue_catalog_v1(
    'e9020000-0000-4000-8000-000000000001',null
  );
  perform pg_temp.assert_true(
    jsonb_array_length(catalog->'recurringSeries')=1
      and jsonb_array_length(catalog->'venuePools')=1
      and catalog::text !~* 'private_address|latitude|longitude|contact|created_by|accepted_by',
    'Authorized catalog discovery is incomplete or leaks private fields'
  );
  perform pg_temp.actor('ffffffff-ffff-4fff-8fff-ffffffffffff');
  perform pg_temp.expect_failure($sql$
    select public.get_pachanga_season_venue_catalog_v1(
      'e9020000-0000-4000-8000-000000000001',null
    )
  $sql$,'VENUE_.*READ_FORBIDDEN|AUTHORITY_REQUIRED');
  perform pg_temp.expect_failure($sql$
    select public.get_pachanga_platform_venue_allocation_health_v1()
  $sql$,'VENUE_PLATFORM_AUTHORITY_REQUIRED');

  perform pg_temp.actor('c4010000-0000-4000-8000-000000000002');
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000030',null,0,'allocation_plan.create',
    jsonb_build_object(
      'competitionId','c4200000-0000-4000-8000-000000000001',
      'editionId','c4200000-0000-4000-8000-000000000004',
      'stageId','c4200000-0000-4000-8000-000000000006',
      'schedulePlanId','e9070000-0000-4000-8000-000000000001',
      'scheduleRevisionId','e9070000-0000-4000-8000-000000000002',
      'ruleRevisionId','e9050000-0000-4000-8000-000000000001',
      'venuePoolId',pool_id,'mode','AUTOMATIC','venueRequired',true
    ),'{}'
  );
  plan_id:=(response->>'aggregateId')::uuid;
  plan_revision:=(response->>'confirmedRevision')::bigint;

  perform pg_temp.expect_failure(format($sql$
    select public.command_pachanga_competition_venue_allocation_v1(
      'e9b10000-0000-4000-8000-000000000031','%s',%s,
      'allocation_constraint.create',
      '{"constraintKind":"SOFT","constraintCode":"PREFERRED_PITCH","scopeKind":"PLAN","weight":2,"parameters":{"nested":{"privateAddress":"forbidden"}},"reason":"Sensitive payload rejection"}','{}'
    )
  $sql$,plan_id,plan_revision),'VENUE_ALLOCATION_CONSTRAINT_PARAMETERS_INVALID');

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000032',plan_id,plan_revision,
    'allocation_inputs.freeze','{}','{}');
  plan_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000033',plan_id,plan_revision,
    'allocation.generate','{"seed":"wave9b-deterministic","searchBudget":100}','{}');
  plan_revision:=(response->>'confirmedRevision')::bigint;
  select rows.result_checksum into first_result_checksum
  from public.pachanga_competition_venue_allocation_revisions rows
  where rows.id=(select plans.current_revision_id
    from public.pachanga_competition_venue_allocation_plans plans where plans.id=plan_id);
  perform pg_temp.assert_true(
    (select count(*)=1 and bool_and(rows.pitch_id is not null)
      from public.pachanga_competition_venue_allocation_items rows
      where rows.allocation_revision_id=(select plans.current_revision_id
        from public.pachanga_competition_venue_allocation_plans plans where plans.id=plan_id)),
    'Automatic allocation did not assign the canonical Match'
  );
  perform pg_temp.assert_true(
    (select source_kind='RECURRING_OCCURRENCE'
      from public.pachanga_competition_venue_allocation_items rows
      where rows.allocation_revision_id=(select plans.current_revision_id
        from public.pachanga_competition_venue_allocation_plans plans where plans.id=plan_id)),
    'Automatic allocation did not prefer the exact recurring occurrence'
  );

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000038',plan_id,plan_revision,
    'allocation.regenerate','{"seed":"wave9b-deterministic","searchBudget":100}','{}');
  plan_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select rows.result_checksum=first_result_checksum
      from public.pachanga_competition_venue_allocation_revisions rows
      where rows.id=(select plans.current_revision_id
        from public.pachanga_competition_venue_allocation_plans plans where plans.id=plan_id)),
    'Equivalent generation changed the deterministic result checksum'
  );
  select to_jsonb(rows) into generated_revision_snapshot
  from public.pachanga_competition_venue_allocation_revisions rows
  where rows.id=(select plans.current_revision_id
    from public.pachanga_competition_venue_allocation_plans plans where plans.id=plan_id);

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000034',plan_id,plan_revision,
    'allocation.hold','{"expiresInMinutes":60}','{}');
  plan_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true((response#>>'{snapshot,result,heldCount}')::integer=1,
    'Bulk hold did not create one Wave 9A hold');

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000035',plan_id,plan_revision,
    'allocation.validate','{}','{}');
  plan_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(response#>>'{snapshot,result,status}'='VALID',
    'Unchanged held plan did not validate');
  select rows.server_sequence,rows.validated_at
    into first_validation_sequence,first_validation_at
  from private.pachanga_competition_venue_allocation_validations rows
  where rows.allocation_plan_id=plan_id;

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000036',plan_id,plan_revision,
    'allocation.validate','{}','{}');
  plan_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select count(*)=1 and min(rows.server_sequence)=first_validation_sequence
      and min(rows.validated_at)=first_validation_at
      from private.pachanga_competition_venue_allocation_validations rows
      where rows.allocation_plan_id=plan_id),
    'Equivalent revalidation rewrote immutable validation evidence'
  );

  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000037',plan_id,plan_revision,
    'allocation.publish','{}','{}');
  plan_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_venue_reservations rows
      where rows.competition_id='c4200000-0000-4000-8000-000000000001'
        and rows.status='CONFIRMED')=1
      and (select count(*) from public.pachanga_venue_match_bindings rows
        where rows.canonical_match_id='e9070000-0000-4000-8000-000000000006'
          and rows.status='ACTIVE')=1,
    'Atomic publication did not create one reservation and canonical Venue binding'
  );
  perform pg_temp.assert_true(
    (select to_jsonb(rows)=generated_revision_snapshot
      from public.pachanga_competition_venue_allocation_revisions rows
      where rows.id=(select plans.current_revision_id
        from public.pachanga_competition_venue_allocation_plans plans where plans.id=plan_id)),
    'Validation or publication mutated the immutable AllocationRevision'
  );
  perform pg_temp.expect_failure(format(
    'update public.pachanga_competition_venue_allocation_revisions set status=''cancelled'' where id=%L',
    (select plans.current_revision_id
      from public.pachanga_competition_venue_allocation_plans plans where plans.id=plan_id)
  ),'VENUE_IMMUTABLE_HISTORY');

  desk:=public.get_pachanga_competition_venue_allocation_desk_v1(plan_id);
  perform pg_temp.assert_true(
    desk#>>'{plan,status}'='published'
      and desk::text !~* 'private_address|privateLatitude|contactPhone|created_by|generated_by',
    'Planner read model is not canonical or leaks private authority fields'
  );

  -- Regression W9B-006: an existing canonical binding needs zero new holds.
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000040',null,0,'allocation_plan.create',
    jsonb_build_object(
      'competitionId','c4200000-0000-4000-8000-000000000001',
      'editionId','c4200000-0000-4000-8000-000000000004',
      'stageId','c4200000-0000-4000-8000-000000000006',
      'schedulePlanId','e9070000-0000-4000-8000-000000000001',
      'scheduleRevisionId','e9070000-0000-4000-8000-000000000002',
      'ruleRevisionId','e9050000-0000-4000-8000-000000000001',
      'venuePoolId',pool_id,'mode','AUTOMATIC','venueRequired',true
    ),'{}'
  );
  second_plan_id:=(response->>'aggregateId')::uuid;
  second_plan_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000041',second_plan_id,second_plan_revision,
    'allocation_inputs.freeze','{}','{}');
  second_plan_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000042',second_plan_id,second_plan_revision,
    'allocation.generate','{"seed":"existing-binding","searchBudget":10}','{}');
  second_plan_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000043',second_plan_id,second_plan_revision,
    'allocation.hold','{"expiresInMinutes":30}','{}');
  second_plan_revision:=(response->>'confirmedRevision')::bigint;
  perform pg_temp.assert_true((response#>>'{snapshot,result,heldCount}')::integer=0,
    'Existing-binding-only revision manufactured a hold');
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000044',second_plan_id,second_plan_revision,
    'allocation.validate','{}','{}');
  second_plan_revision:=(response->>'confirmedRevision')::bigint;
  response:=public.command_pachanga_competition_venue_allocation_v1(
    'e9b10000-0000-4000-8000-000000000045',second_plan_id,second_plan_revision,
    'allocation.publish','{}','{}');
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_venue_reservations rows
      where rows.competition_id='c4200000-0000-4000-8000-000000000001')=1,
    'Existing-binding publication duplicated the canonical reservation'
  );

  perform pg_temp.actor('e9010000-0000-4000-8000-000000000005');
  perform pg_temp.expect_failure(format(
    'select public.get_pachanga_competition_venue_allocation_desk_v1(%L)',plan_id
  ),'VENUE_ALLOCATION_READ_FORBIDDEN|AUTHORITY_REQUIRED|READ_REQUIRED');

  begin
    execute 'set local role authenticated';
    perform count(*) from public.pachanga_competition_venue_allocation_plans;
    raise exception 'WAVE9B_DIRECT_TABLE_READ_NOT_BLOCKED';
  exception when insufficient_privilege then
    null;
  end;
  execute 'reset role';

  perform pg_temp.assert_true(
    (select count(*) from private.pachanga_venue_operation_receipts rows
      where rows.operation_id='e9b10000-0000-4000-8000-000000000010')=1,
    'Idempotent recurring receipt count is not one'
  );
  perform pg_temp.assert_true(
    (select count(*) from private.pachanga_venue_events rows
      where rows.action like 'recurring_series.%')>=7,
    'Recurring lifecycle event history is incomplete'
  );
  perform pg_temp.assert_true(
    (select count(*) from public.pachanga_venue_invalidations rows
      where rows.entity_type in ('recurring_series','venue_pool','venue_allocation_plan'))>=10,
    'Scoped Realtime invalidations were not emitted'
  );
end;
$$;

select 'SEASON_VENUE_ALLOCATION_V1_DB_PASS' as result;
