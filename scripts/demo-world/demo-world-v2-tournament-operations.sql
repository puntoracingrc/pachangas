\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '180s';

begin;

create schema if not exists simulation;
create table simulation.demo_world_tournament_conflict_evidence (
  plan_id uuid primary key,
  error_code text not null,
  error_detail jsonb not null,
  captured_at timestamptz not null default clock_timestamp()
);

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  ('64010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'demo-tournament-team-' || team_number || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'Demo Tournament Owner ' || team_number)
from generate_series(1, 16) team_number;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data) values
  ('64010000-0000-4000-8000-000000000090', 'demo-tournament-platform@example.test', clock_timestamp(), '{"full_name":"Demo Tournament Platform"}');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload)
select
  ('64020000-0000-4000-8000-' || lpad(teams.team_number::text, 12, '0'))::uuid,
  ('64010000-0000-4000-8000-' || lpad(teams.team_number::text, 12, '0'))::uuid,
  teams.team_name,
  'DW' || lpad(teams.team_number::text, 5, '0'),
  jsonb_build_object('matches', '[]'::jsonb, 'players', '[]'::jsonb, 'siteSettings', '{}'::jsonb, 'venues', '[]'::jsonb)
from (values
  (1, 'Cobalto Raval'),
  (2, 'Circuit Poblenou'),
  (3, 'Brúixola Sants'),
  (4, 'Onze del Clot'),
  (5, 'Marina Fosca'),
  (6, 'Ferro Sant Andreu'),
  (7, 'Diagonal 26'),
  (8, 'Vértice Gràcia'),
  (9, 'Pols Sabadell'),
  (10, 'Carboni Terrassa'),
  (11, 'Metro Rubí'),
  (12, 'Nexe Granollers'),
  (13, 'Línia Cerdanyola'),
  (14, 'Vector Sant Cugat'),
  (15, 'Ronda Mollet'),
  (16, 'Taller Barberà')
) teams(team_number, team_name);

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  ('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  ('64010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'owner',
  'Demo Owner ' || team_number
from generate_series(1, 16) team_number;

insert into public.pachanga_team_level_read_models(group_id, stable_level, revision, calculated_at)
select
  ('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  80 - team_number,
  1,
  '2026-08-26T18:00:00Z'
from generate_series(1, 16) team_number
on conflict (group_id) do update set
  stable_level = excluded.stable_level,
  revision = excluded.revision,
  calculated_at = excluded.calculated_at;

insert into public.pachanga_clubs(
  id, name, slug, club_type, country_code, province, municipality,
  general_area, visibility, operational_status, primary_owner_id, created_by
)
select
  ('64040000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid,
  'Club Demo ' || club_number,
  'club-demo-tournament-' || club_number,
  'FOOTBALL_CLUB', 'ES', 'Barcelona', 'Barcelona', 'Barcelona',
  'private', 'active',
  ('64010000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid,
  ('64010000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid
from generate_series(1, 4) club_number;

insert into public.pachanga_club_memberships(
  club_id, user_id, role, status, accepted_at, invited_by
)
select
  ('64040000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid,
  ('64010000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid,
  'club_owner', 'active', '2026-08-26T18:00:00Z',
  ('64010000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid
from generate_series(1, 4) club_number;

insert into public.pachanga_club_team_relationships(
  club_id, group_id, relationship_type, initiated_by, status,
  show_on_club_profile, created_by, started_at
)
select
  ('64040000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid,
  ('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
  'AFFILIATED', 'CLUB', 'active', false,
  ('64010000-0000-4000-8000-' || lpad(club_number::text, 12, '0'))::uuid,
  '2026-08-26T18:00:00Z'
from generate_series(1, 4) club_number
cross join lateral unnest(array[club_number, club_number + 4]) team_number;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values ('64010000-0000-4000-8000-000000000090', 'platform_owner', true);

select set_config(
  'request.jwt.claims',
  '{"sub":"64010000-0000-4000-8000-000000000090","role":"authenticated"}',
  false
);

select public.command_pachanga_competition_platform_v1(
  md5('demo-world-v2-4-foundation-flags')::uuid,
  '00000000-0000-0000-0000-00000000c001',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'foundation_flags.set',
  '{"foundationEnabled":true,"creationEnabled":true,"contextBindingEnabled":true,"reason":"Demo World V2.5 Tournament foundation"}',
  '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
);

select public.command_pachanga_tournament_platform_v1(
  md5('demo-world-v2-4-tournament-flags')::uuid,
  '00000000-0000-0000-0000-00000000c6a1',
  (select revision from private.pachanga_competition_foundation_settings where singleton),
  'tournament.flags.set',
  '{"foundationEnabled":true,"privateBetaEnabled":true,"creationEnabled":true,"drawEnabled":true,"automaticEnabled":true,"manualEnabled":true,"hybridEnabled":true,"publishEnabled":true,"reason":"Demo World V2.5 Tournament authority"}',
  '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
);

select public.command_pachanga_tournament_platform_v1(
  md5('demo-world-v2-4-tournament-grant')::uuid,
  '64020000-0000-4000-8000-000000000001',
  0,
  'tournament.beta_bundle.grant',
  '{"organizerKind":"TEAM","maxTeams":32,"expiresAt":"2027-12-31T23:59:59Z","reason":"Demo World V2.5 private beta grant"}',
  '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"64010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

select public.command_pachanga_tournament_draw_v1(
  md5('demo-world-v2-4-tournament-create')::uuid,
  '64020000-0000-4000-8000-000000000001',
  (select revision from public.pachanga_competition_organizer_states
    where organizer_kind='TEAM' and organizer_group_id='64020000-0000-4000-8000-000000000001'),
  'tournament.create',
  '{"organizerKind":"TEAM","name":"COPA BARRIOS IQ 2027","slug":"copa-barrios-iq-2027","description":"Torneo sintético con sorteo reproducible","generalArea":"Barcelona","modality":"FUTBOL_7","editionName":"Copa Barrios IQ 2027","seasonLabel":"2026/27","startsAt":"2027-05-01","endsAt":"2027-06-30","participantCap":16,"groupCount":4,"qualifiersPerGroup":2,"drawTarget":"GROUPS_THEN_KNOCKOUT","drawMode":"SEEDED_POTS","registrationClosesAt":"2027-04-20T20:00:00Z","authoringMode":"ADVANCED","discipline":{"enabled":true},"referees":{"usage":"OPTIONAL"},"reason":"Demo World V2.5 Tournament creation"}',
  '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
);

do $demo_tournament$
#variable_conflict use_variable
declare competition_id uuid := (
  select competitions.id from public.pachanga_competitions competitions
  where competitions.slug='copa-barrios-iq-2027'
);
declare team_number integer;
declare entry_id uuid;
begin
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-authoring-seeded')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'tournament.authoring.save',
    '{"name":"COPA BARRIOS IQ 2027","slug":"copa-barrios-iq-2027","description":"Torneo sintético con sorteo reproducible","generalArea":"Barcelona","modality":"FUTBOL_7","editionName":"Copa Barrios IQ 2027","seasonLabel":"2026/27","startsAt":"2027-05-01","endsAt":"2027-06-30","participantCap":16,"groupCount":4,"qualifiersPerGroup":2,"drawTarget":"GROUPS_THEN_KNOCKOUT","drawMode":"SEEDED_POTS","registrationClosesAt":"2027-04-20T20:00:00Z","authoringMode":"ADVANCED","discipline":{"enabled":true},"referees":{"usage":"OPTIONAL"},"reason":"Demo World V2.5 canonical Configuration Center revision"}',
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );

  for team_number in 1..16 loop
    perform set_config(
      'request.jwt.claims',
      '{"sub":"64010000-0000-4000-8000-000000000001","role":"authenticated"}',
      true
    );
    perform public.command_pachanga_tournament_draw_v1(
      md5('demo-world-v2-4-invite-' || team_number)::uuid, competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'participant.invite',
      jsonb_build_object(
        'teamId', ('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
        'reason', 'Demo World V2.5 invitation'
      ),
      '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
    );
    select entries.id into entry_id
    from public.pachanga_competition_entries entries
    where entries.competition_id=competition_id
      and entries.team_id=('64020000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid;
    perform set_config(
      'request.jwt.claims',
      jsonb_build_object(
        'sub', ('64010000-0000-4000-8000-' || lpad(team_number::text, 12, '0'))::uuid,
        'role', 'authenticated'
      )::text,
      true
    );
    perform public.command_pachanga_tournament_draw_v1(
      md5('demo-world-v2-4-accept-' || team_number)::uuid, competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'participant.accept',
      jsonb_build_object('entryId', entry_id, 'reason', 'Demo World V2.5 acceptance'),
      '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
    );
  end loop;
end;
$demo_tournament$;

select set_config(
  'request.jwt.claims',
  '{"sub":"64010000-0000-4000-8000-000000000001","role":"authenticated"}',
  false
);

do $demo_tournament_draw$
#variable_conflict use_variable
declare competition_id uuid := (
  select competitions.id from public.pachanga_competitions competitions
  where competitions.slug='copa-barrios-iq-2027'
);
declare plan_id uuid;
declare pot_number integer;
declare pot_entries jsonb;
declare baseline_revision_id uuid;
declare placement record;
begin
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-plan')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw_plan.create', jsonb_build_object(
      'editionId', (select editions.id from public.pachanga_competition_editions editions where editions.competition_id=competition_id),
      'stageId', (select stages.id from public.pachanga_competition_stages stages
        join public.pachanga_competition_editions editions on editions.id=stages.edition_id
        where editions.competition_id=competition_id),
      'ruleRevisionId', (select editions.rule_revision_id from public.pachanga_competition_editions editions where editions.competition_id=competition_id),
      'targetType','GROUPS_THEN_KNOCKOUT','mode','SEEDED_POTS','groupCount',4,
      'qualifiersPerGroup',2,'reason','Demo World V2.5 automatic draw plan'
    ),
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  select plans.id into plan_id from public.pachanga_competition_draw_plans plans
  where plans.competition_id=competition_id order by plans.server_sequence desc, plans.id desc limit 1;
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-freeze-automatic')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'participants.freeze', jsonb_build_object('planId',plan_id,'reason','Demo World V2.5 automatic participant freeze'),
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  for pot_number in 1..4 loop
    select jsonb_agg(ranked.entry_id order by ranked.team_level desc, ranked.entry_id) into pot_entries
    from (
      select entries.id entry_id, levels.stable_level team_level,
        row_number() over(order by levels.stable_level desc, entries.id) row_number
      from public.pachanga_competition_entries entries
      join public.pachanga_team_level_read_models levels on levels.group_id=entries.team_id
      where entries.competition_id=competition_id and entries.status='accepted'
    ) ranked
    where ((ranked.row_number - 1) / 4)::integer + 1 = pot_number;
    perform public.command_pachanga_tournament_draw_v1(
      md5('demo-world-v2-4-pot-' || pot_number)::uuid, competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'draw_pot.create', jsonb_build_object(
        'planId',plan_id,'potNumber',pot_number,'label','Bombo ' || pot_number,
        'capacity',4,'entryIds',pot_entries,'seedingPolicy','TEAM_LEVEL_SNAPSHOT',
        'reason','Demo World V2.5 seeded pot'
      ),
      '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
    );
  end loop;
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-constraint-pots')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw_constraint.create', jsonb_build_object(
      'planId',plan_id,'constraintType','POT_DISTRIBUTION','strength','HARD','weight',100,
      'scope','DRAW','parameters','{}'::jsonb,'reason','Un equipo de cada bombo por grupo','publicAttribution',true
    ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-constraint-club')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw_constraint.create', jsonb_build_object(
      'planId',plan_id,'constraintType','SAME_CLUB_AVOIDANCE','strength','SOFT','weight',20,
      'scope','DRAW','parameters','{}'::jsonb,'reason','Separar equipos afiliados al mismo Club','publicAttribution',true
    ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-constraint-level')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw_constraint.create', jsonb_build_object(
      'planId',plan_id,'constraintType','TEAM_LEVEL_BALANCE','strength','SOFT','weight',2,
      'scope','DRAW','parameters',jsonb_build_object('maxGap',12),
      'reason','Preferir grupos equilibrados','publicAttribution',true
    ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-generate-automatic')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.generate', jsonb_build_object(
      'planId',plan_id,'seedMode','CUSTOM_PUBLIC_SEED','publicSeed','COPA-BARRIOS-IQ-2027-AUTO',
      'reason','Demo World V2.5 deterministic automatic draw'
    ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  select plans.current_revision_id into baseline_revision_id
  from public.pachanga_competition_draw_plans plans where plans.id=plan_id;

  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-authoring-hybrid')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'tournament.authoring.save',
    '{"name":"COPA BARRIOS IQ 2027","slug":"copa-barrios-iq-2027","description":"Torneo sintético con sorteo reproducible","generalArea":"Barcelona","modality":"FUTBOL_7","editionName":"Copa Barrios IQ 2027","seasonLabel":"2026/27","startsAt":"2027-05-01","endsAt":"2027-06-30","participantCap":16,"groupCount":4,"qualifiersPerGroup":2,"drawTarget":"GROUPS_THEN_KNOCKOUT","drawMode":"HYBRID","registrationClosesAt":"2027-04-20T20:00:00Z","authoringMode":"ADVANCED","discipline":{"enabled":true},"referees":{"usage":"OPTIONAL"},"reason":"Demo World V2.5 hybrid RuleRevision"}',
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-freeze-hybrid')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'participants.freeze', jsonb_build_object('planId',plan_id,'reason','Demo World V2.5 hybrid participant freeze'),
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  for placement in
    select placements.entry_id, placements.group_number, placements.slot_number
    from public.pachanga_competition_draw_placements placements
    where placements.draw_revision_id=baseline_revision_id
    order by placements.group_number, placements.slot_number, placements.id
    limit 2
  loop
    perform public.command_pachanga_tournament_draw_v1(
      md5('demo-world-v2-4-lock-' || placement.entry_id::text)::uuid, competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'draw.lock.create', jsonb_build_object(
        'planId',plan_id,'lockType','ENTRY_TO_SLOT','entryId',placement.entry_id,
        'groupNumber',placement.group_number,'slotNumber',placement.slot_number,
        'reason','Posición fijada por el organizador en Demo World V2.5'
      ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
    );
  end loop;
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-generate-hybrid')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.regenerate', jsonb_build_object(
      'planId',plan_id,'seedMode','CUSTOM_PUBLIC_SEED','publicSeed','COPA-BARRIOS-IQ-2027-HYBRID',
      'reason','Demo World V2.5 hybrid completion'
    ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-validate-hybrid')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.validate', jsonb_build_object('planId',plan_id,'reason','Demo World V2.5 hybrid validation'),
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
end;
$demo_tournament_draw$;

do $demo_tournament_conflict$
#variable_conflict use_variable
declare competition_id uuid := (
  select competitions.id from public.pachanga_competitions competitions
  where competitions.slug='copa-barrios-iq-2027'
);
declare plan_id uuid;
declare entry_ids uuid[];
declare entry_id uuid;
declare constraint_ids uuid[] := '{}'::uuid[];
declare constraint_id uuid;
declare detail text;
begin
  select plans.id into plan_id from public.pachanga_competition_draw_plans plans
  where plans.competition_id=competition_id
  order by plans.server_sequence desc, plans.id desc limit 1;
  select array_agg(entries.id order by entries.team_id) into entry_ids
  from public.pachanga_competition_entries entries
  where entries.competition_id=competition_id and entries.status='accepted';
  foreach entry_id in array entry_ids[1:2] loop
    perform public.command_pachanga_tournament_draw_v1(
      md5('demo-world-v2-4-conflict-fixed-' || entry_id::text)::uuid, competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'draw_constraint.create', jsonb_build_object(
        'planId',plan_id,'constraintType','FIXED_POSITION','strength','HARD','weight',1000,
        'scope','ENTRY_PAIR','parameters',jsonb_build_object('entryId',entry_id,'groupNumber',1,'slotNumber',1),
        'reason','Dos equipos no pueden ocupar el mismo slot','publicAttribution',true
      ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
    );
    select constraints.id into constraint_id
    from public.pachanga_competition_draw_constraints constraints
    where constraints.draw_plan_id=plan_id
      and constraints.constraint_type='FIXED_POSITION'
      and constraints.status='active'
      and constraints.parameters ->> 'entryId'=entry_id::text
    order by constraints.server_sequence desc, constraints.id desc limit 1;
    constraint_ids := array_append(constraint_ids, constraint_id);
  end loop;
  begin
    perform public.command_pachanga_tournament_draw_v1(
      md5('demo-world-v2-4-conflict-generate')::uuid, competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'draw.generate', jsonb_build_object(
        'planId',plan_id,'seedMode','CUSTOM_PUBLIC_SEED','publicSeed','COPA-BARRIOS-IQ-2027-CONFLICT',
        'reason','Demo World V2.5 expected unsatisfiable draw'
      ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
    );
    raise exception 'DEMO_WORLD_TOURNAMENT_EXPECTED_UNSATISFIABLE';
  exception when others then
    if sqlerrm = 'DEMO_WORLD_TOURNAMENT_EXPECTED_UNSATISFIABLE' then raise; end if;
    if sqlerrm <> 'DRAW_UNSATISFIABLE' then raise; end if;
    get stacked diagnostics detail = pg_exception_detail;
    insert into simulation.demo_world_tournament_conflict_evidence(plan_id, error_code, error_detail)
    values (plan_id, sqlerrm, coalesce(nullif(detail, '')::jsonb, '{}'::jsonb));
  end;
  foreach constraint_id in array constraint_ids loop
    perform public.command_pachanga_tournament_draw_v1(
      md5('demo-world-v2-4-conflict-remove-' || constraint_id::text)::uuid, competition_id,
      (select tournament_revision from public.pachanga_competitions where id=competition_id),
      'draw_constraint.remove', jsonb_build_object(
        'planId',plan_id,'constraintId',constraint_id,
        'reason','Retirar escenario imposible después de demostrar DRAW_UNSATISFIABLE'
      ), '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
    );
  end loop;
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-revalidate-hybrid')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.validate', jsonb_build_object('planId',plan_id,'reason','Demo World V2.5 hybrid revalidation'),
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
  perform public.command_pachanga_tournament_draw_v1(
    md5('demo-world-v2-4-publish-hybrid')::uuid, competition_id,
    (select tournament_revision from public.pachanga_competitions where id=competition_id),
    'draw.publish', jsonb_build_object('planId',plan_id,'reason','Demo World V2.5 hybrid publication'),
    '{"clientVersion":"demo-world-v2.5","serviceWorkerVersion":"demo-world-v2.5","installedMode":"simulation","surface":"demo_world_v2_tournament"}'
  );
end;
$demo_tournament_conflict$;

with report as (
  select
  (select count(*) from public.pachanga_competition_entries entries
    join public.pachanga_competitions competitions on competitions.id=entries.competition_id
    where competitions.slug='copa-barrios-iq-2027' and entries.status in ('accepted','active')) accepted_participants,
  (select count(*) from public.pachanga_competition_draw_revisions revisions
    join public.pachanga_competition_draw_plans plans on plans.id=revisions.draw_plan_id
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='copa-barrios-iq-2027') total_revisions,
  (select count(*) from public.pachanga_competition_draw_revisions revisions
    join public.pachanga_competition_draw_plans plans on plans.id=revisions.draw_plan_id
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='copa-barrios-iq-2027'
      and revisions.validation_status='PENDING') generated_outcomes,
  (select count(*) from public.pachanga_competition_draw_plans plans
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='copa-barrios-iq-2027'
      and plans.status='published' and plans.current_revision_id is not null) published_plans,
  (select count(*) from simulation.demo_world_tournament_conflict_evidence) conflict_evidence,
  (select count(*) from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='copa-barrios-iq-2027') tournament_matches
)
select 'DEMO_WORLD_V2_4_TOURNAMENT_REPORT|' || to_jsonb(report)::text from report;

with report as (
  select
  (select count(*) from public.pachanga_competition_entries entries
    join public.pachanga_competitions competitions on competitions.id=entries.competition_id
    where competitions.slug='copa-barrios-iq-2027' and entries.status in ('accepted','active')) accepted_participants,
  (select count(*) from public.pachanga_competition_draw_revisions revisions
    join public.pachanga_competition_draw_plans plans on plans.id=revisions.draw_plan_id
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='copa-barrios-iq-2027') total_revisions,
  (select count(*) from public.pachanga_competition_draw_revisions revisions
    join public.pachanga_competition_draw_plans plans on plans.id=revisions.draw_plan_id
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='copa-barrios-iq-2027'
      and revisions.validation_status='PENDING') generated_outcomes,
  (select count(*) from public.pachanga_competition_draw_plans plans
    join public.pachanga_competitions competitions on competitions.id=plans.competition_id
    where competitions.slug='copa-barrios-iq-2027'
      and plans.status='published' and plans.current_revision_id is not null) published_plans,
  (select count(*) from simulation.demo_world_tournament_conflict_evidence) conflict_evidence,
  (select count(*) from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competitions competitions on competitions.id=contexts.competition_id
    where competitions.slug='copa-barrios-iq-2027') tournament_matches
)
select case when accepted_participants=16 and total_revisions=5
  and generated_outcomes=2 and published_plans=1
  and conflict_evidence=1 and tournament_matches=0
then 'DEMO_WORLD_V2_4_TOURNAMENT_OK' else 'DEMO_WORLD_V2_4_TOURNAMENT_FAILED' end
from report;

\if :{?DEMO_WORLD_V2_PERSIST}
commit;
\else
rollback;
\endif
