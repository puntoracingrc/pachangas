\set ON_ERROR_STOP on

\if :{?R6A_ENGINE_KEEP}
\else
begin;
\endif
set local lock_timeout = '5s';
set local statement_timeout = '180s';

create or replace function pg_temp.r6a_engine_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then
    raise exception 'R6A_ENGINE_ASSERT:%', message;
  end if;
end;
$$;

create or replace function pg_temp.r6a_actor(actor_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', actor_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create temporary table r6a_engine_cases(
  case_key text primary key,
  competition_id uuid not null,
  plan_id uuid not null,
  participant_count integer not null,
  group_count integer,
  mode text not null,
  target_type text not null,
  entry_ids uuid[] not null
);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  md5('r6a-engine-user-' || team_number)::uuid,
  'r6a-engine-' || team_number || '@example.test',
  clock_timestamp(), jsonb_build_object('full_name', 'R6A Engine ' || team_number)
from generate_series(1, 64) team_number;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('62010000-0000-4000-8000-000000000090', 'r6a-engine-platform@example.test', clock_timestamp(), '{"full_name":"R6A Engine Platform"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  md5('r6a-engine-team-' || team_number)::uuid,
  md5('r6a-engine-user-' || team_number)::uuid,
  'R6A Engine Team ' || team_number,
  'E6' || lpad(team_number::text, 4, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
from generate_series(1, 64) team_number;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  md5('r6a-engine-team-' || team_number)::uuid,
  md5('r6a-engine-user-' || team_number)::uuid,
  'owner', 'R6A Engine Owner ' || team_number
from generate_series(1, 64) team_number;

insert into public.pachanga_team_level_read_models(group_id, stable_level, revision, calculated_at)
select
  md5('r6a-engine-team-' || team_number)::uuid,
  40 + (team_number % 30), 1, '2026-08-26T18:00:00Z'
from generate_series(1, 64) team_number
on conflict (group_id) do update set
  stable_level = excluded.stable_level,
  revision = excluded.revision,
  calculated_at = excluded.calculated_at;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('62010000-0000-4000-8000-000000000090', 'platform_owner', true);

select pg_temp.r6a_actor('62010000-0000-4000-8000-000000000090');
select public.command_pachanga_competition_platform_v1(
  gen_random_uuid(), '00000000-0000-0000-0000-00000000c001',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'foundation_flags.set',
  '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":true,"reason":"R6A engine matrix"}',
  '{"clientVersion":"6.0.0+r6a-engine","surface":"sql"}'
);
select public.command_pachanga_tournament_platform_v1(
  gen_random_uuid(), '00000000-0000-0000-0000-00000000c6a1',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'tournament.flags.set',
  '{"foundationEnabled":true,"privateBetaEnabled":true,"creationEnabled":true,"drawEnabled":true,"automaticEnabled":true,"manualEnabled":true,"hybridEnabled":true,"publishEnabled":true,"reason":"R6A engine matrix"}',
  '{"clientVersion":"6.0.0+r6a-engine","surface":"sql"}'
);
select public.command_pachanga_tournament_platform_v1(
  gen_random_uuid(), md5('r6a-engine-team-1')::uuid, 0,
  'tournament.beta_bundle.grant',
  '{"organizerKind":"TEAM","maxTeams":64,"capacityOverride":true,"expiresAt":"2027-12-31T23:59:59Z","reason":"R6A engine capacity"}',
  '{"clientVersion":"6.0.0+r6a-engine","surface":"sql"}'
);

create or replace function pg_temp.r6a_command(
  actor_id uuid,
  competition_id uuid,
  action_name text,
  payload jsonb
)
returns jsonb language plpgsql as $$
declare response jsonb;
begin
  perform pg_temp.r6a_actor(actor_id);
  response := public.command_pachanga_tournament_draw_v1(
    gen_random_uuid(), competition_id,
    (select tournaments.tournament_revision
      from public.pachanga_competitions tournaments where tournaments.id = competition_id),
    action_name, payload,
    '{"clientVersion":"6.0.0+r6a-engine","serviceWorkerVersion":"r6a-engine","installedMode":"browser","surface":"sql"}'
  );
  return response;
end;
$$;

create or replace function pg_temp.r6a_expect_command_error(
  actor_id uuid,
  competition_id uuid,
  action_name text,
  payload jsonb,
  expected_error text
)
returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    perform pg_temp.r6a_command(actor_id, competition_id, action_name, payload);
  exception when others then
    caught := true;
    if sqlerrm !~* expected_error then
      raise exception 'R6A_ENGINE_WRONG_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then
    raise exception 'R6A_ENGINE_EXPECTED_ERROR_NOT_RAISED:%', expected_error;
  end if;
end;
$$;

create or replace function pg_temp.r6a_create_case(
  target_case_key text,
  target_participant_count integer,
  target_group_count integer,
  target_mode text,
  target_type text default 'GROUP_ASSIGNMENT',
  target_slot_count integer default null
)
returns uuid language plpgsql as $$
#variable_conflict use_variable
declare owner_id constant uuid := md5('r6a-engine-user-1')::uuid;
declare organizer_id constant uuid := md5('r6a-engine-team-1')::uuid;
declare organizer_revision bigint;
declare create_response jsonb;
declare competition_id uuid;
declare edition_id uuid;
declare stage_id uuid;
declare rule_revision_id uuid;
declare plan_id uuid;
declare team_number integer;
declare team_id uuid;
declare team_owner_id uuid;
declare entry_id uuid;
declare entry_ids uuid[];
begin
  perform pg_temp.r6a_actor(owner_id);
  select states.revision into organizer_revision
  from public.pachanga_competition_organizer_states states
  where states.organizer_kind = 'TEAM' and states.organizer_group_id = organizer_id;
  create_response := public.command_pachanga_tournament_draw_v1(
    gen_random_uuid(), organizer_id, organizer_revision,
    'tournament.create', jsonb_build_object(
      'organizerKind','TEAM', 'name','R6A ' || upper(target_case_key),
      'slug','r6a-' || replace(lower(target_case_key), '_', '-'),
      'description','R6A deterministic engine matrix', 'modality','FUTBOL_7',
      'participantCap',target_participant_count,
      'groupCount',coalesce(target_group_count, 1),
      'qualifiersPerGroup',2, 'drawTarget',target_type,
      'drawMode',target_mode, 'reason','R6A engine case'
    ), '{"clientVersion":"6.0.0+r6a-engine","surface":"sql"}'
  );
  competition_id := (create_response #>> '{snapshot,competition,id}')::uuid;

  for team_number in 1..target_participant_count loop
    team_id := md5('r6a-engine-team-' || team_number)::uuid;
    team_owner_id := md5('r6a-engine-user-' || team_number)::uuid;
    perform pg_temp.r6a_command(owner_id, competition_id, 'participant.invite',
      jsonb_build_object('teamId',team_id,'reason','R6A engine invitation'));
    select entries.id into entry_id
    from public.pachanga_competition_entries entries
    where entries.competition_id = competition_id and entries.team_id = team_id;
    perform pg_temp.r6a_command(team_owner_id, competition_id, 'participant.accept',
      jsonb_build_object('entryId',entry_id,'reason','R6A engine acceptance'));
  end loop;

  select editions.id, stages.id, editions.rule_revision_id
  into edition_id, stage_id, rule_revision_id
  from public.pachanga_competition_editions editions
  join public.pachanga_competition_stages stages on stages.edition_id = editions.id
  where editions.competition_id = competition_id
  order by editions.server_sequence desc, stages.stage_order, stages.id limit 1;

  perform pg_temp.r6a_command(owner_id, competition_id, 'draw_plan.create',
    jsonb_strip_nulls(jsonb_build_object(
      'editionId',edition_id, 'stageId',stage_id, 'ruleRevisionId',rule_revision_id,
      'targetType',target_type, 'mode',target_mode,
      'groupCount',target_group_count, 'slotCount',target_slot_count,
      'qualifiersPerGroup',2, 'reason','R6A engine plan'
    )));
  select plans.id into plan_id
  from public.pachanga_competition_draw_plans plans
  where plans.competition_id = competition_id
  order by plans.server_sequence desc, plans.id desc limit 1;
  perform pg_temp.r6a_command(owner_id, competition_id, 'participants.freeze',
    jsonb_build_object('planId',plan_id,'reason','R6A engine freeze'));
  select array_agg(entries.id order by entries.id) into entry_ids
  from public.pachanga_competition_entries entries
  where entries.competition_id = competition_id and entries.status in ('accepted','active');
  insert into r6a_engine_cases values (
    target_case_key, competition_id, plan_id, target_participant_count,
    target_group_count, target_mode, target_type, entry_ids
  );
  return competition_id;
end;
$$;

create or replace function pg_temp.r6a_create_pots(target_case_key text)
returns void language plpgsql as $$
declare case_row r6a_engine_cases%rowtype;
declare pot_number integer;
declare pot_count integer;
declare first_index integer;
declare last_index integer;
begin
  select * into case_row from r6a_engine_cases cases where cases.case_key = target_case_key;
  if case_row.group_count is null or case_row.participant_count % case_row.group_count <> 0 then
    raise exception 'R6A_POT_CASE_NOT_DIVISIBLE:%', target_case_key;
  end if;
  pot_count := case_row.participant_count / case_row.group_count;
  for pot_number in 1..pot_count loop
    first_index := (pot_number - 1) * case_row.group_count + 1;
    last_index := pot_number * case_row.group_count;
    perform pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid, case_row.competition_id,
      'draw_pot.create', jsonb_build_object(
        'planId',case_row.plan_id, 'potNumber',pot_number,
        'label','Bombo ' || pot_number, 'capacity',case_row.group_count,
        'entryIds',to_jsonb(case_row.entry_ids[first_index:last_index]),
        'seedingPolicy','MANUAL', 'reason','R6A exact pots'
      ));
  end loop;
end;
$$;

create or replace function pg_temp.r6a_generate(
  target_case_key text,
  public_seed text,
  regenerate boolean default false
)
returns jsonb language plpgsql as $$
declare case_row r6a_engine_cases%rowtype;
declare response jsonb;
begin
  select * into case_row from r6a_engine_cases cases where cases.case_key = target_case_key;
  response := pg_temp.r6a_command(
    md5('r6a-engine-user-1')::uuid, case_row.competition_id,
    case when regenerate then 'draw.regenerate' else 'draw.generate' end,
    jsonb_build_object(
      'planId',case_row.plan_id, 'seedMode','CUSTOM_PUBLIC_SEED',
      'publicSeed',public_seed, 'reason','R6A deterministic generation'
    )
  );
  return response;
end;
$$;

create or replace function pg_temp.r6a_assert_generated(target_case_key text)
returns void language plpgsql as $$
declare case_row r6a_engine_cases%rowtype;
declare revision_id uuid;
begin
  select * into case_row from r6a_engine_cases cases where cases.case_key = target_case_key;
  select plans.current_revision_id into revision_id
  from public.pachanga_competition_draw_plans plans where plans.id = case_row.plan_id;
  perform pg_temp.r6a_engine_assert(revision_id is not null, target_case_key || ': revision missing');
  perform pg_temp.r6a_engine_assert(
    (select count(*) = case_row.participant_count
      from public.pachanga_competition_draw_placements placements
      where placements.draw_revision_id = revision_id),
    target_case_key || ': participant count mismatch'
  );
  perform pg_temp.r6a_engine_assert(
    (select count(distinct placements.entry_id) = case_row.participant_count
      from public.pachanga_competition_draw_placements placements
      where placements.draw_revision_id = revision_id),
    target_case_key || ': duplicate or missing participant'
  );
  if case_row.target_type <> 'KNOCKOUT_INITIAL_SEEDING' then
    perform pg_temp.r6a_engine_assert(
      (select coalesce(max(group_size) - min(group_size), 0) <= 1 from (
        select placements.group_number, count(*) group_size
        from public.pachanga_competition_draw_placements placements
        where placements.draw_revision_id = revision_id
        group by placements.group_number
      ) sizes), target_case_key || ': unbalanced group sizes'
    );
  end if;
end;
$$;

-- 4 participants, even groups, PURE_RANDOM and a strict hard level balance.
select pg_temp.r6a_create_case('pure4', 4, 2, 'PURE_RANDOM');
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='pure4'),
  'draw_constraint.create', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='pure4'),
    'constraintType','TEAM_LEVEL_BALANCE','strength','HARD','weight',10,
    'scope','DRAW','parameters',jsonb_build_object('maxGap',0),
    'reason','Exact level balance required','publicAttribution',true
  ));
select pg_temp.r6a_generate('pure4', 'R6A-PURE-4-SEED');
select pg_temp.r6a_assert_generated('pure4');
select pg_temp.r6a_engine_assert(
  (select quality.level_balance = 0
    from r6a_engine_cases cases
    join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
    join public.pachanga_competition_draw_quality_snapshots quality
      on quality.draw_revision_id=plans.current_revision_id
    where cases.case_key='pure4'),
  'TEAM_LEVEL_BALANCE HARD maxGap=0 must be enforced'
);

-- Exact pots at 8 and 16 teams.
select pg_temp.r6a_create_case('pots8', 8, 2, 'SEEDED_POTS');
select pg_temp.r6a_create_pots('pots8');
select pg_temp.r6a_generate('pots8', 'R6A-POTS-8-SEED');
select pg_temp.r6a_assert_generated('pots8');

select pg_temp.r6a_create_case('pots16', 16, 4, 'SEEDED_POTS');
select pg_temp.r6a_create_pots('pots16');
select pg_temp.r6a_generate('pots16', 'R6A-POTS-16-SEED');
select pg_temp.r6a_assert_generated('pots16');
select pg_temp.r6a_engine_assert(not exists (
  select placements.group_number, placements.pot_number
  from r6a_engine_cases cases
  join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
  join public.pachanga_competition_draw_placements placements
    on placements.draw_revision_id=plans.current_revision_id
  where cases.case_key='pots16'
  group by placements.group_number, placements.pot_number having count(*) <> 1
), 'SEEDED_POTS must place exactly one team from every pot in each group');

-- Reproducible checksum, then a different valid public seed.
create temporary table r6a_seed_checks(first_checksum text, second_checksum text, third_checksum text);
insert into r6a_seed_checks(first_checksum)
select revisions.result_checksum
from r6a_engine_cases cases
join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
join public.pachanga_competition_draw_revisions revisions on revisions.id=plans.current_revision_id
where cases.case_key='pots16';
select pg_temp.r6a_generate('pots16', 'R6A-POTS-16-SEED', true);
update r6a_seed_checks set second_checksum=(
  select revisions.result_checksum
  from r6a_engine_cases cases
  join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
  join public.pachanga_competition_draw_revisions revisions on revisions.id=plans.current_revision_id
  where cases.case_key='pots16'
);
select pg_temp.r6a_engine_assert(
  (select first_checksum=second_checksum from r6a_seed_checks),
  'Same seed and inputs must reproduce the exact checksum'
);
select pg_temp.r6a_generate('pots16', 'R6A-POTS-16-DIFFERENT', true);
update r6a_seed_checks set third_checksum=(
  select revisions.result_checksum
  from r6a_engine_cases cases
  join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
  join public.pachanga_competition_draw_revisions revisions on revisions.id=plans.current_revision_id
  where cases.case_key='pots16'
);
select pg_temp.r6a_engine_assert(
  (select first_checksum<>third_checksum from r6a_seed_checks),
  'A different public seed must produce a different valid draw for this fixture'
);

-- Constraint optimized, including an odd group count.
select pg_temp.r6a_create_case('optimized12', 12, 3, 'CONSTRAINT_OPTIMIZED');
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='optimized12'),
  'draw_constraint.create', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='optimized12'),
    'constraintType','TEAM_LEVEL_BALANCE','strength','SOFT','weight',2,
    'scope','DRAW','parameters',jsonb_build_object('maxGap',3),
    'reason','Prefer balanced groups','publicAttribution',true
  ));
select pg_temp.r6a_generate('optimized12', 'R6A-OPTIMIZED-12');
select pg_temp.r6a_assert_generated('optimized12');

-- HYBRID with an odd number of groups and two immutable positions.
select pg_temp.r6a_create_case('hybrid24', 24, 5, 'HYBRID');
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='hybrid24'),
  'draw.lock.create', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='hybrid24'),
    'lockType','ENTRY_TO_GROUP','entryId',(select entry_ids[1] from r6a_engine_cases where case_key='hybrid24'),
    'groupNumber',1,'slotNumber',1,'reason','Hybrid lock one'
  ));
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='hybrid24'),
  'draw.lock.create', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='hybrid24'),
    'lockType','ENTRY_TO_GROUP','entryId',(select entry_ids[2] from r6a_engine_cases where case_key='hybrid24'),
    'groupNumber',2,'slotNumber',1,'reason','Hybrid lock two'
  ));
select pg_temp.r6a_generate('hybrid24', 'R6A-HYBRID-24');
select pg_temp.r6a_assert_generated('hybrid24');
select pg_temp.r6a_engine_assert(
  (select count(*)=2
    from r6a_engine_cases cases
    join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
    join public.pachanga_competition_draw_placements placements
      on placements.draw_revision_id=plans.current_revision_id
    where cases.case_key='hybrid24' and placements.placement_source='LOCKED'),
  'HYBRID must preserve both locked placements'
);

-- MANUAL_ASSISTED: duplicate target is rejected, then a swap creates one revision.
select pg_temp.r6a_create_case('manual32', 32, 8, 'MANUAL_ASSISTED');
select pg_temp.r6a_generate('manual32', 'R6A-MANUAL-32');
select pg_temp.r6a_assert_generated('manual32');
select pg_temp.r6a_expect_command_error(
  md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='manual32'),
  'draw.entry.move', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='manual32'),
    'entryId',(select entry_ids[2] from r6a_engine_cases where case_key='manual32'),
    'groupNumber',(select placements.group_number
      from r6a_engine_cases cases join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
      join public.pachanga_competition_draw_placements placements on placements.draw_revision_id=plans.current_revision_id
      where cases.case_key='manual32' and placements.entry_id=cases.entry_ids[1]),
    'slotNumber',(select placements.slot_number
      from r6a_engine_cases cases join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
      join public.pachanga_competition_draw_placements placements on placements.draw_revision_id=plans.current_revision_id
      where cases.case_key='manual32' and placements.entry_id=cases.entry_ids[1]),
    'reason','Attempt occupied manual position'
  ), 'DRAW_POSITION_OCCUPIED'
);
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='manual32'),
  'draw.entry.swap', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='manual32'),
    'entryId',(select entry_ids[1] from r6a_engine_cases where case_key='manual32'),
    'otherEntryId',(select entry_ids[2] from r6a_engine_cases where case_key='manual32'),
    'reason','Canonical manual swap'
  ));
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='manual32'),
  'draw.validate', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='manual32'),
    'reason','Validate manual draw'
  ));

-- Knockout seeds with two explicit BYEs and no matches.
select pg_temp.r6a_create_case('knockout14', 14, null, 'PURE_RANDOM', 'KNOCKOUT_INITIAL_SEEDING', 16);
select pg_temp.r6a_generate('knockout14', 'R6A-KNOCKOUT-14');
select pg_temp.r6a_assert_generated('knockout14');
select pg_temp.r6a_engine_assert(
  (select count(*)=2
    from r6a_engine_cases cases
    join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
    join public.pachanga_competition_draw_byes byes on byes.draw_revision_id=plans.current_revision_id
    where cases.case_key='knockout14'),
  '14 participants in a 16-slot initial seeding must persist two BYEs'
);

-- Capacity boundary: 64 participants and 16 groups, measured and bounded.
select pg_temp.r6a_create_case('optimized64', 64, 16, 'CONSTRAINT_OPTIMIZED');
create temporary table r6a_engine_timing(started_at timestamptz, duration_ms numeric);
insert into r6a_engine_timing(started_at) values (clock_timestamp());
select pg_temp.r6a_generate('optimized64', 'R6A-OPTIMIZED-64');
update r6a_engine_timing set duration_ms=
  extract(epoch from (clock_timestamp()-started_at))*1000;
select pg_temp.r6a_assert_generated('optimized64');
select pg_temp.r6a_engine_assert(
  (select duration_ms < 120000 from r6a_engine_timing),
  '64-participant bounded solver exceeded 120 seconds'
);

-- Contradictory fixed positions are explicit DRAW_UNSATISFIABLE, never partial output.
select pg_temp.r6a_create_case('unsat4', 4, 2, 'CONSTRAINT_OPTIMIZED');
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='unsat4'),
  'draw_constraint.create', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='unsat4'),
    'constraintType','FIXED_POSITION','strength','HARD','weight',100,
    'scope','DRAW','parameters',jsonb_build_object(
      'entryId',(select entry_ids[1] from r6a_engine_cases where case_key='unsat4'),
      'groupNumber',1,'slotNumber',1
    ),'reason','Fixed collision A','publicAttribution',true
  ));
select pg_temp.r6a_command(md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='unsat4'),
  'draw_constraint.create', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='unsat4'),
    'constraintType','FIXED_POSITION','strength','HARD','weight',100,
    'scope','DRAW','parameters',jsonb_build_object(
      'entryId',(select entry_ids[2] from r6a_engine_cases where case_key='unsat4'),
      'groupNumber',1,'slotNumber',1
    ),'reason','Fixed collision B','publicAttribution',true
  ));
select pg_temp.r6a_expect_command_error(
  md5('r6a-engine-user-1')::uuid,
  (select competition_id from r6a_engine_cases where case_key='unsat4'),
  'draw.generate', jsonb_build_object(
    'planId',(select plan_id from r6a_engine_cases where case_key='unsat4'),
    'seedMode','CUSTOM_PUBLIC_SEED','publicSeed','R6A-UNSAT-4',
    'reason','Expected impossible draw'
  ), 'DRAW_UNSATISFIABLE'
);
select pg_temp.r6a_engine_assert(
  (select plans.current_revision_id is null
    from r6a_engine_cases cases join public.pachanga_competition_draw_plans plans on plans.id=cases.plan_id
    where cases.case_key='unsat4'),
  'Unsatisfiable generation must persist zero partial revision'
);

select pg_temp.r6a_engine_assert(
  (select count(*)=0 from public.pachanga_competition_match_contexts contexts
    join r6a_engine_cases cases on cases.competition_id=contexts.competition_id),
  'R6A engine matrix must create zero Tournament matches'
);

select 'R6A_ENGINE_REPORT|' || jsonb_build_object(
  'cases', (select count(*) from r6a_engine_cases),
  'participants', (select jsonb_agg(participant_count order by participant_count) from r6a_engine_cases),
  'modes', (select jsonb_agg(distinct mode) from r6a_engine_cases),
  'knockoutByes', 2,
  'manualDuplicateRejected', true,
  'sameSeedReproduced', (select first_checksum=second_checksum from r6a_seed_checks),
  'differentSeedChanged', (select first_checksum<>third_checksum from r6a_seed_checks),
  'unsatisfiableExplained', true,
  'max64DurationMs', (select round(duration_ms, 3) from r6a_engine_timing),
  'tournamentMatches', 0
)::text;

\if :{?R6A_ENGINE_KEEP}
\else
rollback;
\endif

select 'R6A_ENGINE_ROLLBACK|' || jsonb_build_object(
  'tournaments', (select count(*) from public.pachanga_competitions where product_key='TOURNAMENT_PRIVATE_BETA_V1'),
  'plans', (select count(*) from public.pachanga_competition_draw_plans),
  'placements', (select count(*) from public.pachanga_competition_draw_placements)
)::text;
