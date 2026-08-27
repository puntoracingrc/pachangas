\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '180s';

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  ('63010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'r6a-fixture-' || team_number || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'R6A Fixture ' || team_number)
from generate_series(1, 16) team_number;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('63010000-0000-4000-8000-000000000090', 'r6a-fixture-platform@example.test', clock_timestamp(), '{"full_name":"R6A Fixture Platform"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  ('63020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  ('63010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'R6A Fixture Team ' || team_number,
  'F6' || lpad(team_number::text, 4, '0'),
  '{"matches":[],"players":[],"siteSettings":{},"venues":[]}'::jsonb
from generate_series(1, 16) team_number;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  ('63020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  ('63010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'owner',
  'R6A Fixture Owner ' || team_number
from generate_series(1, 16) team_number;

insert into public.pachanga_team_level_read_models(group_id, stable_level, revision, calculated_at)
select
  ('63020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  48 + team_number,
  1,
  '2026-08-26T18:00:00Z'
from generate_series(1, 16) team_number
on conflict (group_id) do update set
  stable_level = excluded.stable_level,
  revision = excluded.revision,
  calculated_at = excluded.calculated_at;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('63010000-0000-4000-8000-000000000090', 'platform_owner', true);

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000090","role":"authenticated"}',
  false
);

select public.command_pachanga_competition_platform_v1(
  '63030000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-00000000c001',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'foundation_flags.set',
  '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":true,"reason":"R6A temporary fixture"}',
  '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
);

select public.command_pachanga_tournament_platform_v1(
  '63030000-0000-4000-8000-000000000002',
  '00000000-0000-0000-0000-00000000c6a1',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'tournament.flags.set',
  '{"foundationEnabled":true,"privateBetaEnabled":true,"creationEnabled":true,"drawEnabled":true,"automaticEnabled":true,"manualEnabled":true,"hybridEnabled":true,"publishEnabled":true,"reason":"R6A temporary fixture"}',
  '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
);

select public.command_pachanga_tournament_platform_v1(
  '63030000-0000-4000-8000-000000000003',
  '63020000-0000-4000-8000-000000000001',
  0,
  'tournament.beta_bundle.grant',
  '{"organizerKind":"TEAM","maxTeams":32,"expiresAt":"2027-12-31T23:59:59Z","reason":"R6A temporary fixture grant"}',
  '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

select public.command_pachanga_tournament_draw_v1(
  '63030000-0000-4000-8000-000000000004',
  '63020000-0000-4000-8000-000000000001',
  (select revision from public.pachanga_competition_organizer_states
    where organizer_kind='TEAM'
      and organizer_group_id='63020000-0000-4000-8000-000000000001'),
  'tournament.create',
  '{"organizerKind":"TEAM","name":"R6A Concurrency Fixture","slug":"r6a-concurrency-fixture","description":"Temporary canonical fixture","modality":"FUTBOL_7","participantCap":16,"groupCount":4,"qualifiersPerGroup":2,"drawTarget":"GROUP_ASSIGNMENT","drawMode":"HYBRID","reason":"R6A temporary fixture"}',
  '{"clientVersion":"6.0.0+r6a-fixture","serviceWorkerVersion":"r6a-fixture","installedMode":"browser","surface":"sql"}'
);

do $$
declare
  target_competition_id uuid := (
    select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'
  );
declare
  team_number integer;
declare
  entry_id uuid;
begin
  for team_number in 1..16 loop
    perform set_config(
      'request.jwt.claims',
      '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
      true
    );
    perform public.command_pachanga_tournament_draw_v1(
      gen_random_uuid(), target_competition_id,
      (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
      'participant.invite',
      jsonb_build_object(
        'teamId', ('63020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
        'reason', 'R6A fixture invitation'
      ),
      '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
    );
    select entries.id into entry_id
    from public.pachanga_competition_entries entries
    where entries.competition_id=target_competition_id
      and entries.team_id=('63020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid;
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', ('63010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
        'role', 'authenticated'
      )::text,
      true
    );
    perform public.command_pachanga_tournament_draw_v1(
      gen_random_uuid(), target_competition_id,
      (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
      'participant.accept',
      jsonb_build_object('entryId', entry_id, 'reason', 'R6A fixture acceptance'),
      '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
    );
  end loop;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"63010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

select public.command_pachanga_tournament_draw_v1(
  gen_random_uuid(),
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'draw_plan.create',
  jsonb_build_object(
    'editionId', (select editions.id from public.pachanga_competition_editions editions
      join public.pachanga_competitions competitions on competitions.id=editions.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'stageId', (select stages.id from public.pachanga_competition_stages stages
      join public.pachanga_competition_editions editions on editions.id=stages.edition_id
      join public.pachanga_competitions competitions on competitions.id=editions.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'ruleRevisionId', (select editions.rule_revision_id from public.pachanga_competition_editions editions
      join public.pachanga_competitions competitions on competitions.id=editions.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'targetType', 'GROUP_ASSIGNMENT',
    'mode', 'HYBRID',
    'groupCount', 4,
    'qualifiersPerGroup', 2,
    'reason', 'R6A fixture draw plan'
  ),
  '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
);

select public.command_pachanga_tournament_draw_v1(
  gen_random_uuid(),
  (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  (select tournament_revision from public.pachanga_competitions where slug='r6a-concurrency-fixture'),
  'participants.freeze',
  jsonb_build_object(
    'planId', (select plans.id from public.pachanga_competition_draw_plans plans
      join public.pachanga_competitions competitions on competitions.id=plans.competition_id
      where competitions.slug='r6a-concurrency-fixture'),
    'reason', 'R6A fixture participant freeze'
  ),
  '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
);

do $$
declare
  target_competition_id uuid := (select id from public.pachanga_competitions where slug='r6a-concurrency-fixture');
declare
  plan_id uuid := (select plans.id from public.pachanga_competition_draw_plans plans
    where plans.competition_id=target_competition_id);
declare
  pot_number integer;
declare
  pot_entries jsonb;
begin
  for pot_number in 1..4 loop
    select jsonb_agg(entry_id order by entry_id) into pot_entries
    from (
      select entries.id entry_id,
        row_number() over(order by entries.team_id) row_number
      from public.pachanga_competition_entries entries
      where entries.competition_id=target_competition_id and entries.status='accepted'
    ) ranked
    where ((row_number - 1) / 4)::integer + 1 = pot_number;
    perform public.command_pachanga_tournament_draw_v1(
      gen_random_uuid(), target_competition_id,
      (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
      'draw_pot.create',
      jsonb_build_object(
        'planId', plan_id,
        'potNumber', pot_number,
        'label', 'Bombo ' || pot_number,
        'capacity', 4,
        'entryIds', pot_entries,
        'seedingPolicy', 'TEAM_LEVEL_SNAPSHOT',
        'reason', 'R6A fixture seeded pot'
      ),
      '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
    );
  end loop;

  perform public.command_pachanga_tournament_draw_v1(
    gen_random_uuid(), target_competition_id,
    (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
    'draw_constraint.create',
    jsonb_build_object(
      'planId', plan_id,
      'constraintType', 'POT_DISTRIBUTION',
      'strength', 'HARD',
      'weight', 100,
      'scope', 'DRAW',
      'parameters', '{}'::jsonb,
      'reason', 'One participant from each pot per group',
      'publicAttribution', true
    ),
    '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    gen_random_uuid(), target_competition_id,
    (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
    'draw_constraint.create',
    jsonb_build_object(
      'planId', plan_id,
      'constraintType', 'TEAM_LEVEL_BALANCE',
      'strength', 'SOFT',
      'weight', 2,
      'scope', 'DRAW',
      'parameters', jsonb_build_object('maxGap', 12),
      'reason', 'Prefer balanced groups',
      'publicAttribution', true
    ),
    '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    gen_random_uuid(), target_competition_id,
    (select tournament_revision from public.pachanga_competitions where id=target_competition_id),
    'draw.generate',
    jsonb_build_object(
      'planId', plan_id,
      'seedMode', 'CUSTOM_PUBLIC_SEED',
      'publicSeed', 'R6A-CONCURRENCY-FIXTURE',
      'reason', 'R6A fixture deterministic generation'
    ),
    '{"clientVersion":"6.0.0+r6a-fixture","surface":"sql"}'
  );
end;
$$;

select case when
  (select count(*) from public.pachanga_competition_entries entries
    join public.pachanga_competitions competitions on competitions.id=entries.competition_id
    where competitions.slug='r6a-concurrency-fixture' and entries.status='accepted') = 16
  and (select count(*) from public.pachanga_competition_draw_placements placements
    join public.pachanga_competition_draw_revisions revisions on revisions.id=placements.draw_revision_id
    join public.pachanga_competition_draw_plans plans on plans.id=revisions.draw_plan_id
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='r6a-concurrency-fixture'
      and revisions.id=plans.current_revision_id) = 16
  and (select count(*) from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='r6a-concurrency-fixture') = 0
then 'R6A_FIXTURE_OK' else 'R6A_FIXTURE_FAILED' end;
