begin;

do $$
begin
  if has_table_privilege('anon', 'simulation.simulation_worlds', 'select')
    or has_table_privilege('authenticated', 'simulation.simulation_worlds', 'select')
    or has_table_privilege('authenticated', 'simulation.simulation_world_summaries', 'select') then
    raise exception 'simulation tables are readable by product clients';
  end if;
  if has_function_privilege('authenticated', 'simulation.save_world(jsonb,uuid,bigint,text,jsonb)', 'execute') then
    raise exception 'authenticated can execute simulation.save_world';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'simulation.simulation_worlds'::regclass) then
    raise exception 'simulation_worlds RLS is disabled';
  end if;
end;
$$;

grant usage on schema simulation to authenticated;
grant execute on function simulation.save_world(jsonb, uuid, bigint, text, jsonb) to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform simulation.save_world('{}'::jsonb, '00000000-0000-4000-8000-000000000099', -1, null, null);
    raise exception 'authenticated bypassed the save_world internal guard';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
revoke execute on function simulation.save_world(jsonb, uuid, bigint, text, jsonb) from authenticated;
revoke usage on schema simulation from authenticated;

select simulation.save_world(
  jsonb_build_object(
    'id', '00000000-0000-4000-8000-000000000991',
    'name', 'SIM DB contract',
    'seed', 991,
    'startDate', '2026-09-01T00:00:00.000Z',
    'currentDate', '2026-09-01T00:00:00.000Z',
    'seasonId', '2026-27',
    'status', 'paused',
    'mode', 'ephemeral',
    'sourceCommit', '4c75d52e15449528fe206e4d542715ec96d42422',
    'revision', 0,
    'config', jsonb_build_object('agentCount', 0, 'attackRate', 0, 'guestCount', 0, 'initialFreeAgentCount', 0, 'seasonEnd', '2027-06-30T00:00:00.000Z', 'teamCount', 0),
    'state', jsonb_build_object(
      'achievements', jsonb_build_array(), 'agents', jsonb_build_array(), 'boxes', jsonb_build_array(),
      'challenges', jsonb_build_array(), 'coverage', jsonb_build_array(), 'eventSequence', 0,
      'events', jsonb_build_array(), 'incidents', jsonb_build_array(), 'matches', jsonb_build_array(),
      'notifications', jsonb_build_array(), 'ratingOpinions', jsonb_build_array(), 'rankings', jsonb_build_array(),
      'teams', jsonb_build_array(), 'venues', jsonb_build_array()
    )
  ),
  '00000000-0000-4000-8000-000000000001',
  -1,
  'checkpoint',
  '{"label":"first"}'::jsonb
);

do $$
declare
  v_replay jsonb;
  v_world jsonb;
  v_order text[];
begin
  select simulation.save_world(
    jsonb_build_object(
      'id', '00000000-0000-4000-8000-000000000991', 'name', 'ignored replay', 'seed', 991,
      'startDate', '2026-09-01T00:00:00.000Z', 'currentDate', '2026-09-01T00:00:00.000Z',
      'seasonId', '2026-27', 'status', 'paused', 'mode', 'ephemeral',
      'sourceCommit', '4c75d52e15449528fe206e4d542715ec96d42422', 'revision', 0,
      'config', '{}'::jsonb,
      'state', jsonb_build_object('achievements','[]'::jsonb,'agents','[]'::jsonb,'boxes','[]'::jsonb,'challenges','[]'::jsonb,'coverage','[]'::jsonb,'eventSequence',0,'events','[]'::jsonb,'incidents','[]'::jsonb,'matches','[]'::jsonb,'notifications','[]'::jsonb,'ratingOpinions','[]'::jsonb,'rankings','[]'::jsonb,'teams','[]'::jsonb,'venues','[]'::jsonb)
    ),
    '00000000-0000-4000-8000-000000000001', -1, null, null
  ) into v_replay;
  if coalesce((v_replay->>'idempotentReplay')::boolean, false) is not true then
    raise exception 'idempotent replay was not recognized';
  end if;

  select to_jsonb(w) into v_world from (
    select
      id::text as "id", name, seed, virtual_start_date as "startDate", virtual_current_date as "currentDate",
      season_id as "seasonId", status, mode, source_commit as "sourceCommit", 1 as revision, config,
      jsonb_set(
        jsonb_set(state, '{eventSequence}', '2'::jsonb),
        '{events}',
        jsonb_build_array(
          jsonb_build_object('actorAgentId',null,'entityIds','[]'::jsonb,'eventType','first','expected','{}'::jsonb,'flow','test.order','operationId','00000000-0000-4000-8000-000000000011','payload','{}'::jsonb,'sequence',1,'status','pass','virtualDate','2026-09-02T00:00:00.000Z'),
          jsonb_build_object('actorAgentId',null,'entityIds','[]'::jsonb,'eventType','second','expected','{}'::jsonb,'flow','test.order','operationId','00000000-0000-4000-8000-000000000012','payload','{}'::jsonb,'sequence',2,'status','pass','virtualDate','2026-09-02T00:00:00.000Z')
        )
      ) as state
    from simulation.simulation_worlds where id = '00000000-0000-4000-8000-000000000991'
  ) w;
  perform simulation.save_world(v_world, '00000000-0000-4000-8000-000000000002', 0, null, null);
  select array_agg(event_type order by server_sequence desc) into v_order
  from simulation.simulation_events where world_id = '00000000-0000-4000-8000-000000000991';
  if v_order <> array['second','first'] then
    raise exception 'server sequence ordering failed: %', v_order;
  end if;

  v_world := jsonb_set(v_world, '{revision}', '2'::jsonb);
  perform simulation.save_world(
    v_world,
    '00000000-0000-4000-8000-000000000004',
    1,
    'checkpoint',
    '{"label":"same-date-retry"}'::jsonb
  );
  if (select count(*) from simulation.simulation_snapshots
      where world_id = '00000000-0000-4000-8000-000000000991'
        and snapshot_kind = 'checkpoint'
        and virtual_date = '2026-09-01T00:00:00.000Z') <> 1 then
    raise exception 'same-date snapshots are not canonical';
  end if;

  begin
    perform simulation.save_world(v_world, '00000000-0000-4000-8000-000000000003', 0, null, null);
    raise exception 'stale revision was accepted';
  exception when serialization_failure then
    null;
  end;
end;
$$;

rollback;
