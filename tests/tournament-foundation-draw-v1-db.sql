\set ON_ERROR_STOP on

begin;

create or replace function pg_temp.r6a_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then
    raise exception 'R6A_ASSERT:%', message;
  end if;
end;
$$;

create or replace function pg_temp.r6a_expect_error(statement text, expected_error text)
returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    execute statement;
  exception when others then
    caught := true;
    if sqlerrm !~* expected_error then
      raise exception 'R6A_WRONG_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then raise exception 'R6A_EXPECTED_ERROR_NOT_RAISED:%', expected_error; end if;
end;
$$;

select pg_temp.r6a_assert(
  not (select tournament_foundation_enabled
    from private.pachanga_competition_foundation_settings where singleton),
  'Tournament flags must install OFF'
);

select pg_temp.r6a_assert(
  not exists (
    select 1
    from pg_constraint constraints
    join pg_class relations on relations.oid=constraints.conrelid
    join pg_namespace namespaces on namespaces.oid=relations.relnamespace
    where constraints.contype='f'
      and namespaces.nspname='public'
      and relations.relname in (
        'pachanga_competition_participant_freezes',
        'pachanga_competition_draw_plans',
        'pachanga_competition_draw_revisions',
        'pachanga_competition_draw_pots',
        'pachanga_competition_draw_constraints',
        'pachanga_competition_draw_manual_locks',
        'pachanga_competition_draw_placements',
        'pachanga_competition_draw_byes',
        'pachanga_competition_draw_quality_snapshots',
        'pachanga_tournament_invalidations'
      )
      and not exists (
        select 1
        from pg_index indexes
        where indexes.indrelid=constraints.conrelid
          and indexes.indisvalid
          and indexes.indisready
          and split_part(indexes.indkey::text, ' ', 1)::smallint=constraints.conkey[1]
      )
  ),
  'Every R6A foreign key must have a covering index'
);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  ('61010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'r6a-team-' || team_number || '@example.test', clock_timestamp(),
  jsonb_build_object('full_name', 'R6A Team ' || team_number)
from generate_series(1, 8) team_number;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('61010000-0000-4000-8000-000000000090', 'r6a-platform@example.test', clock_timestamp(), '{"full_name":"R6A Platform"}'),
  ('61010000-0000-4000-8000-000000000099', 'r6a-outsider@example.test', clock_timestamp(), '{"full_name":"R6A Outsider"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  ('61020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  ('61010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'R6A Barrio ' || team_number, 'R6A' || lpad(team_number::text, 3, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
from generate_series(1, 8) team_number;

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values (
  '61020000-0000-4000-8000-000000000009',
  '61010000-0000-4000-8000-000000000099',
  'R6A Barrio 9', 'R6A009',
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  ('61020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  ('61010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'owner', 'R6A Owner ' || team_number
from generate_series(1, 8) team_number;

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values (
  '61020000-0000-4000-8000-000000000009',
  '61010000-0000-4000-8000-000000000099',
  'owner', 'R6A Owner 9'
);

insert into private.pachanga_platform_admin_roles(user_id, role, active) values
  ('61010000-0000-4000-8000-000000000090', 'platform_owner', true);

select set_config(
  'request.jwt.claims',
  '{"sub":"61010000-0000-4000-8000-000000000090","role":"authenticated"}', true
);

select public.command_pachanga_competition_platform_v1(
  '61030000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-00000000c001',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'foundation_flags.set',
  '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":true,"reason":"R6A local authority test"}',
  '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'
);

create temporary table r6a_state(key text primary key, value jsonb not null);

insert into r6a_state values (
  'flags', public.command_pachanga_tournament_platform_v1(
    '61030000-0000-4000-8000-000000000002',
    '00000000-0000-0000-0000-00000000c6a1',
    (select revision from private.pachanga_competition_foundation_settings where singleton),
    'tournament.flags.set',
    '{"foundationEnabled":true,"privateBetaEnabled":true,"creationEnabled":true,"drawEnabled":true,"automaticEnabled":true,"manualEnabled":true,"hybridEnabled":true,"publishEnabled":true,"reason":"R6A local private beta"}',
    '{"clientVersion":"6.0.0+r6a-test","serviceWorkerVersion":"r6a-test","installedMode":"browser","surface":"sql"}'
  )
);

select pg_temp.r6a_assert(
  (select tournament_foundation_enabled and tournament_private_beta_enabled
      and tournament_creation_enabled and tournament_draw_enabled
      and tournament_automatic_draw_enabled and tournament_draw_manual_enabled
      and tournament_draw_hybrid_enabled and tournament_draw_publish_enabled
      and not tournament_public_discovery_enabled
      and not tournament_match_generation_enabled
      and not tournament_bracket_progression_enabled
   from private.pachanga_competition_foundation_settings where singleton),
  'Only the R6A private capabilities must be active'
);

insert into r6a_state values (
  'bundle', public.command_pachanga_tournament_platform_v1(
    '61030000-0000-4000-8000-000000000003',
    '61020000-0000-4000-8000-000000000001', 0,
    'tournament.beta_bundle.grant',
    '{"organizerKind":"TEAM","maxTeams":16,"expiresAt":"2027-12-31T23:59:59Z","reason":"R6A canonical test grant"}',
    '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'
  )
);

select pg_temp.r6a_assert(
  (select count(*) = 4 from public.pachanga_competition_entitlement_grants grants
   where grants.bundle_id = (select (value #>> '{snapshot,bundleId}')::uuid from r6a_state where key='bundle')),
  'Tournament bundle must contain exactly four capabilities'
);

-- Regression R6A-001: an active League beta must not intercept the explicit
-- Tournament product. These prerequisite flags mirror the production coexistence.
update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  creation_enabled = true,
  context_binding_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_operational_exceptions_foundation_enabled = true,
  league_postponements_enabled = true,
  league_rescheduling_enabled = true,
  league_venue_changes_enabled = true,
  league_late_arrival_enabled = true,
  league_no_show_enabled = true,
  league_match_suspensions_enabled = true,
  league_administrative_decisions_enabled = true,
  league_public_registration_enabled = false,
  league_public_calendar_enabled = false,
  league_public_standings_enabled = false,
  league_public_exception_status_enabled = false,
  league_private_beta_enabled = true,
  league_private_beta_creation_enabled = true,
  league_private_beta_public_discovery_enabled = false,
  revision = revision + 1,
  server_sequence = nextval('private.pachanga_competition_sequence'),
  updated_by = '61010000-0000-4000-8000-000000000090',
  updated_at = clock_timestamp()
where singleton;

select set_config(
  'request.jwt.claims',
  '{"sub":"61010000-0000-4000-8000-000000000001","role":"authenticated"}', true
);

insert into r6a_state values (
  'create', public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000004',
    '61020000-0000-4000-8000-000000000001', 1,
    'tournament.create',
    '{"organizerKind":"TEAM","name":"Copa Barrios R6A","slug":"copa-barrios-r6a","description":"Prueba canónica","modality":"FUTBOL_7","participantCap":16,"groupCount":2,"qualifiersPerGroup":2,"drawTarget":"GROUP_ASSIGNMENT","drawMode":"SEEDED_POTS","reason":"R6A canonical test"}',
    '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'
  )
);

insert into r6a_state values (
  'competition', jsonb_build_object(
    'id', (select (value #>> '{snapshot,competition,id}')::uuid from r6a_state where key='create')
  )
);

select pg_temp.r6a_assert(
  exists (
    select 1 from public.pachanga_competitions competitions
    where competitions.id = (select (value ->> 'id')::uuid from r6a_state where key='competition')
      and competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
      and competitions.competition_type = 'TOURNAMENT'
      and competitions.visibility = 'private'
  ),
  'R6A-001: canonical Tournament creation must coexist with active League beta'
);

select pg_temp.r6a_expect_error(
  $$insert into public.pachanga_competitions(
      id, organizer_group_id, name, slug, competition_type, visibility,
      product_key, created_by
    ) values (
      '61040000-0000-4000-8000-000000000001',
      '61020000-0000-4000-8000-000000000001',
      'Producto Tournament inválido', 'producto-tournament-invalido',
      'LEAGUE', 'private', 'TOURNAMENT_PRIVATE_BETA_V1',
      '61010000-0000-4000-8000-000000000001'
    )$$,
  'TOURNAMENT_PRIVATE_BETA_TYPE_REQUIRED'
);

select pg_temp.r6a_expect_error(
  $$insert into public.pachanga_competitions(
      id, organizer_group_id, name, slug, competition_type, visibility,
      product_key, created_by
    ) values (
      '61040000-0000-4000-8000-000000000002',
      '61020000-0000-4000-8000-000000000001',
      'Tournament interno inválido', 'tournament-interno-invalido',
      'TOURNAMENT', 'internal', 'TOURNAMENT_PRIVATE_BETA_V1',
      '61010000-0000-4000-8000-000000000001'
    )$$,
  'TOURNAMENT_PRIVATE_BETA_VISIBILITY_REQUIRED'
);

select pg_temp.r6a_assert(
  (select value from r6a_state where key='create') = public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000004',
    '61020000-0000-4000-8000-000000000001', 1,
    'tournament.create',
    '{"organizerKind":"TEAM","name":"Copa Barrios R6A","slug":"copa-barrios-r6a","description":"Prueba canónica","modality":"FUTBOL_7","participantCap":16,"groupCount":2,"qualifiersPerGroup":2,"drawTarget":"GROUP_ASSIGNMENT","drawMode":"SEEDED_POTS","reason":"R6A canonical test"}',
    '{"clientVersion":"different-replay-metadata"}'
  ),
  'Tournament creation must replay the canonical receipt'
);

do $$
declare team_number integer;
declare target_competition_id uuid := (select (value ->> 'id')::uuid from r6a_state where key='competition');
declare target_entry_id uuid;
declare target_owner_id uuid;
declare target_team_id uuid;
declare target_operation_id uuid;
begin
  for team_number in 1..8 loop
    target_owner_id := ('61010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid;
    target_team_id := ('61020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid;
    target_operation_id := ('61031000-0000-4000-8000-' || lpad((team_number * 2 - 1)::text, 12, '0'))::uuid;
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub','61010000-0000-4000-8000-000000000001','role','authenticated'
    )::text, true);
    perform public.command_pachanga_tournament_draw_v1(
      target_operation_id, target_competition_id,
      (select tournaments.tournament_revision from public.pachanga_competitions tournaments
       where tournaments.id=target_competition_id),
      'participant.invite', jsonb_build_object('teamId',target_team_id,'reason','R6A invite'),
      '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'::jsonb
    );
    select entries.id into target_entry_id from public.pachanga_competition_entries entries
    where entries.competition_id=target_competition_id and entries.team_id=target_team_id;
    target_operation_id := ('61031000-0000-4000-8000-' || lpad((team_number * 2)::text, 12, '0'))::uuid;
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub',target_owner_id,'role','authenticated'
    )::text, true);
    perform public.command_pachanga_tournament_draw_v1(
      target_operation_id, target_competition_id,
      (select tournaments.tournament_revision from public.pachanga_competitions tournaments
       where tournaments.id=target_competition_id),
      'participant.accept', jsonb_build_object('entryId',target_entry_id,'reason','R6A accept'),
      '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'::jsonb
    );
  end loop;
end;
$$;

-- Regression R6A-006: participant command responses must not expose pending
-- invitations belonging to another team. Withdraw and re-invite Team 1 so the
-- canonical draw still freezes the original eight accepted participants.
do $$
declare target_competition_id uuid := (select (value ->> 'id')::uuid from r6a_state where key='competition');
declare first_entry_id uuid;
declare replacement_entry_id uuid;
declare response jsonb;
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"61010000-0000-4000-8000-000000000001","role":"authenticated"}', true
  );
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000030', target_competition_id,
    (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
    'participant.invite',
    '{"teamId":"61020000-0000-4000-8000-000000000009","reason":"R6A privacy regression"}',
    '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'
  );

  select entries.id into first_entry_id
  from public.pachanga_competition_entries entries
  where entries.competition_id=target_competition_id
    and entries.team_id='61020000-0000-4000-8000-000000000002'
    and entries.status='accepted';

  perform set_config(
    'request.jwt.claims',
    '{"sub":"61010000-0000-4000-8000-000000000002","role":"authenticated"}', true
  );
  response := public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000031', target_competition_id,
    (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
    'participant.withdraw', jsonb_build_object(
      'entryId', first_entry_id, 'reason', 'R6A privacy response regression'
    ), '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'
  );
  perform pg_temp.r6a_assert(
    not exists (
      select 1 from jsonb_array_elements(response #> '{snapshot,entries}') item
      where item ->> 'teamId' = '61020000-0000-4000-8000-000000000009'
    ),
    'Participant command response must hide another team pending invitation'
  );

  perform set_config(
    'request.jwt.claims',
    '{"sub":"61010000-0000-4000-8000-000000000001","role":"authenticated"}', true
  );
  response := public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000032', target_competition_id,
    (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
    'participant.invite',
    '{"teamId":"61020000-0000-4000-8000-000000000002","reason":"R6A restore participant"}',
    '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'
  );
  select (item ->> 'id')::uuid into replacement_entry_id
  from jsonb_array_elements(response #> '{snapshot,entries}') item
  where item ->> 'teamId' = '61020000-0000-4000-8000-000000000002'
    and item ->> 'status' = 'invited';

  perform set_config(
    'request.jwt.claims',
    '{"sub":"61010000-0000-4000-8000-000000000002","role":"authenticated"}', true
  );
  response := public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000033', target_competition_id,
    (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
    'participant.accept', jsonb_build_object(
      'entryId', replacement_entry_id, 'reason', 'R6A restore accepted participant'
    ), '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'
  );
  perform pg_temp.r6a_assert(
    not exists (
      select 1 from jsonb_array_elements(response #> '{snapshot,entries}') item
      where item ->> 'teamId' = '61020000-0000-4000-8000-000000000009'
    ),
    'Accepted participant response must remain actor-filtered'
  );
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"61010000-0000-4000-8000-000000000001","role":"authenticated"}', true
);

do $$
#variable_conflict use_variable
declare competition_id uuid := (select (value ->> 'id')::uuid from r6a_state where key='competition');
declare edition_id uuid;
declare stage_id uuid;
declare rule_revision_id uuid;
declare plan_response jsonb;
declare plan_id uuid;
declare pot_number integer;
declare pot_entries jsonb;
declare first_checksum text;
declare second_checksum text;
declare constraint_id uuid;
declare first_revision_id uuid;
declare second_revision_id uuid;
begin
  select editions.id, stages.id, editions.rule_revision_id
  into edition_id, stage_id, rule_revision_id
  from public.pachanga_competition_editions editions
  join public.pachanga_competition_stages stages on stages.edition_id=editions.id
  where editions.competition_id=competition_id;
  plan_response := public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000020', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw_plan.create', jsonb_build_object(
      'editionId',edition_id,'stageId',stage_id,'ruleRevisionId',rule_revision_id,
      'targetType','GROUP_ASSIGNMENT','mode','SEEDED_POTS',
      'groupCount',2,'qualifiersPerGroup',2,'reason','R6A plan'
    ), '{"clientVersion":"6.0.0+r6a-test","surface":"sql"}'::jsonb
  );
  select plans.id into plan_id from public.pachanga_competition_draw_plans plans
  where plans.competition_id=competition_id;
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000021', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'participants.freeze', jsonb_build_object('planId',plan_id,'reason','R6A freeze'), '{}'
  );
  perform pg_temp.r6a_assert(
    (select not (freezes.roster_readiness ? 'capturedAt')
      from public.pachanga_competition_participant_freezes freezes
      where freezes.id = (
        select plans.participant_freeze_id
        from public.pachanga_competition_draw_plans plans
        where plans.id = plan_id
      )),
    'Participant freeze checksum input must not contain wall-clock capturedAt'
  );
  for pot_number in 1..4 loop
    select jsonb_agg(entry_id order by entry_id) into pot_entries
    from (
      select entries.id as entry_id,
        row_number() over(order by entries.id) as row_number
      from public.pachanga_competition_entries entries
      where entries.competition_id=competition_id and entries.status='accepted'
    ) ranked
    where ((row_number - 1) % 4) + 1 = pot_number;
    perform public.command_pachanga_tournament_draw_v1(
      ('61032000-0000-4000-8000-' || lpad(pot_number::text,12,'0'))::uuid,
      competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'draw_pot.create', jsonb_build_object(
        'planId',plan_id,'potNumber',pot_number,'label','Bombo '||pot_number,
        'capacity',2,'entryIds',pot_entries,'seedingPolicy','MANUAL','reason','R6A pots'
      ), '{}'
    );
  end loop;
  perform pg_temp.r6a_assert(
    (select count(*) = 0
      from public.pachanga_competition_draw_pots pots
      where pots.draw_plan_id = plan_id
        and pots.status = 'active'
        and pots.seeding_snapshot ? 'capturedAt'),
    'Draw pot checksum inputs must not contain wall-clock capturedAt'
  );
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000022', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.generate', jsonb_build_object(
      'planId',plan_id,'seedMode','CUSTOM_PUBLIC_SEED','publicSeed','COPA-BARRIOS-R6A-2027','reason','R6A deterministic'
    ), '{}'
  );
  select revisions.result_checksum into first_checksum
  from public.pachanga_competition_draw_plans plans
  join public.pachanga_competition_draw_revisions revisions on revisions.id=plans.current_revision_id
  where plans.id=plan_id;
  select plans.current_revision_id into first_revision_id
  from public.pachanga_competition_draw_plans plans where plans.id=plan_id;
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000026', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw_constraint.create', jsonb_build_object(
      'planId',plan_id,'constraintType','SAME_CLUB_AVOIDANCE','strength','SOFT',
      'weight',5,'scope','DRAW','parameters','{}'::jsonb,
      'publicAttribution',true,'reason','R6A freshness regression'
    ), '{}'
  );
  select constraints.id into constraint_id
  from public.pachanga_competition_draw_constraints constraints
  where constraints.draw_plan_id=plan_id and constraints.status='active'
  order by constraints.server_sequence desc, constraints.id desc limit 1;
  perform pg_temp.r6a_assert(
    not private.pachanga_tournament_plan_input_fresh_v1(plan_id),
    'Changing active constraints must mark the current draw input stale'
  );
  perform pg_temp.r6a_assert(
    not (public.get_pachanga_tournament_draw_desk_v1(competition_id, plan_id)
      -> 'plan' ->> 'inputFresh')::boolean,
    'Draw Desk read model must expose stale current input'
  );
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000027', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw_constraint.remove', jsonb_build_object(
      'planId',plan_id,'constraintId',constraint_id,'reason','Restore canonical input'
    ), '{}'
  );
  perform pg_temp.r6a_assert(
    private.pachanga_tournament_plan_input_fresh_v1(plan_id),
    'Removing the transient constraint must restore the matching input checksum'
  );
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000028', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'participants.freeze', jsonb_build_object(
      'planId',plan_id,'reason','R6A replacement freeze lineage regression'
    ), '{}'
  );
  perform pg_temp.r6a_assert(
    (select plans.current_revision_id = first_revision_id
      from public.pachanga_competition_draw_plans plans where plans.id=plan_id),
    'Replacing a freeze must preserve the previous immutable revision for lineage'
  );
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000023', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.regenerate', jsonb_build_object(
      'planId',plan_id,'seedMode','CUSTOM_PUBLIC_SEED','publicSeed','COPA-BARRIOS-R6A-2027','reason','R6A repeat'
    ), '{}'
  );
  select revisions.result_checksum into second_checksum
  from public.pachanga_competition_draw_plans plans
  join public.pachanga_competition_draw_revisions revisions on revisions.id=plans.current_revision_id
  where plans.id=plan_id;
  select plans.current_revision_id into second_revision_id
  from public.pachanga_competition_draw_plans plans where plans.id=plan_id;
  perform pg_temp.r6a_assert(first_checksum=second_checksum, 'Same seed and inputs must reproduce the result');
  perform pg_temp.r6a_assert(
    (select revisions.supersedes_revision_id = first_revision_id
      from public.pachanga_competition_draw_revisions revisions
      where revisions.id=second_revision_id),
    'Regeneration after a replacement freeze must retain revision ancestry'
  );
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000024', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.validate', jsonb_build_object('planId',plan_id,'reason','R6A validate'), '{}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000025', competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.publish', jsonb_build_object('planId',plan_id,'reason','R6A publish'), '{}'
  );
end;
$$;

select pg_temp.r6a_assert(
  (select count(*)=8 from public.pachanga_competition_draw_placements placements
   join public.pachanga_competition_draw_plans plans on plans.current_revision_id=placements.draw_revision_id
   where plans.competition_id=(select (value ->> 'id')::uuid from r6a_state where key='competition')),
  'Published revision must place all eight participants exactly once'
);

select pg_temp.r6a_assert(
  not exists (
    select placements.group_number, placements.pot_number
    from public.pachanga_competition_draw_placements placements
    join public.pachanga_competition_draw_plans plans on plans.current_revision_id=placements.draw_revision_id
    where plans.competition_id=(select (value ->> 'id')::uuid from r6a_state where key='competition')
    group by placements.group_number, placements.pot_number having count(*) <> 1
  ),
  'Each published group must contain exactly one team from every pot'
);

select pg_temp.r6a_assert(
  (select count(*)=0 from public.pachanga_competition_match_contexts contexts
   where contexts.competition_id=(select (value ->> 'id')::uuid from r6a_state where key='competition')),
  'R6A must create zero Tournament matches'
);

select pg_temp.r6a_expect_error(format(
  $$select public.command_pachanga_tournament_draw_v1(
    '61030000-0000-4000-8000-000000000090', %L::uuid, %s,
    'draw.regenerate', '{"planId":"00000000-0000-0000-0000-000000000001","placements":[]}', '{}'
  )$$,
  (select value ->> 'id' from r6a_state where key='competition'),
  (select tournament_revision from public.pachanga_competitions
   where id=(select (value ->> 'id')::uuid from r6a_state where key='competition'))
), 'TOURNAMENT_SERVER_FIELDS_FORBIDDEN');

select set_config(
  'request.jwt.claims',
  '{"sub":"61010000-0000-4000-8000-000000000099","role":"authenticated"}', true
);
select pg_temp.r6a_expect_error(format(
  $$select public.get_pachanga_tournament_snapshot_v1(%L::uuid)$$,
  (select value ->> 'id' from r6a_state where key='competition')
), 'TOURNAMENT_READ_FORBIDDEN');

select set_config(
  'r6a.competition_id',
  (select value ->> 'id' from r6a_state where key='competition'), true
);
set local role authenticated;
select pg_temp.r6a_assert(
  (select count(*) = 0
   from public.pachanga_tournament_invalidations invalidations
   where invalidations.competition_id=current_setting('r6a.competition_id')::uuid),
  'R6A-019: Realtime RLS must hide invalidations from an outsider without permission errors'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"61010000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
set local role authenticated;
select pg_temp.r6a_assert(
  (select count(*) > 0
   from public.pachanga_tournament_invalidations invalidations
   where invalidations.competition_id=current_setting('r6a.competition_id')::uuid),
  'R6A-019: Realtime RLS must expose invalidations to the authorized organizer'
);
reset role;

set local role authenticated;
select pg_temp.r6a_expect_error(
  $$insert into public.pachanga_competition_draw_placements(
    draw_revision_id,entry_id,group_number,slot_number,placement_source
  ) values (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002',1,1,'ENGINE'
  )$$,
  'permission denied|row-level security'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"61010000-0000-4000-8000-000000000001","role":"authenticated"}', true
);
select pg_temp.r6a_assert(
  public.get_pachanga_tournament_draw_audit_v1(
    (select (value ->> 'id')::uuid from r6a_state where key='competition'),
    (select id from public.pachanga_competition_draw_plans
      where competition_id=(select (value ->> 'id')::uuid from r6a_state where key='competition'))
  ) ->> 'seed' = 'COPA-BARRIOS-R6A-2027',
  'Published audit must expose the reproducible seed'
);

select pg_temp.r6a_assert(
  coalesce(public.get_pachanga_tournament_draw_audit_v1(
    (select (value ->> 'id')::uuid from r6a_state where key='competition'),
    (select id from public.pachanga_competition_draw_plans
      where competition_id=(select (value ->> 'id')::uuid from r6a_state where key='competition'))
  ) -> 'placements' -> 0 ->> 'teamName', '') <> '',
  'Published audit must expose the immutable frozen team name'
);

select pg_temp.r6a_assert(
  position('61010000-0000-4000-8000-000000000001' in public.get_pachanga_tournament_draw_audit_v1(
    (select (value ->> 'id')::uuid from r6a_state where key='competition'),
    (select id from public.pachanga_competition_draw_plans
      where competition_id=(select (value ->> 'id')::uuid from r6a_state where key='competition'))
  )::text) = 0,
  'Published audit must not expose the organizer Auth identity'
);

select 'R6A_DB_REPORT|' || jsonb_build_object(
  'acceptedParticipants', 8,
  'idempotency', true,
  'published', true,
  'rlsDirectWriteBlocked', true,
  'tournamentMatches', (
    select count(*) from public.pachanga_competition_match_contexts contexts
    where contexts.competition_id=(
      select (value ->> 'id')::uuid from r6a_state where key='competition'
    )
  )
)::text;

rollback;
