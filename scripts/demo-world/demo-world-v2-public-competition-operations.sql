\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '180s';

begin;

select set_config('pachangas.league_private_beta_authorized', 'on', true);

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, description,
  competition_type, product_key, visibility, status, general_area, created_by
)
select
  ('7a040000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'TEAM', md5('wave7a-team-' || case when value = 2 then 8 else 9 end)::uuid,
  case value
    when 2 then 'Copa Enlace Demo'
    else 'Liga Privada Organizador Demo'
  end,
  case value
    when 2 then 'copa-enlace-demo'
    else 'liga-privada-organizador-demo'
  end,
  'Competition canónica creada para la paridad pública de Demo World V2.7.',
  case when value = 2 then 'TOURNAMENT' else 'LEAGUE' end,
  case when value = 2 then 'TOURNAMENT_PRIVATE_BETA_V1' else 'LEAGUE_PRIVATE_BETA_V1' end,
  'private', 'draft', 'Barcelona',
  md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid
from generate_series(2, 3) value;

insert into public.pachanga_competition_rule_sets(
  id, competition_id, name, status, created_by
)
select
  ('7a050000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('7a040000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'Demo World V2.7 Rules ' || value, 'active',
  md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid
from generate_series(2, 3) value;

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select
  ('7a060000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('7a050000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  1, 'competition_rules.v1', rules.document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', rules.document),
  clock_timestamp(), 'future_only', 'frozen', 1,
  'Demo World V2.7 deterministic rules',
  md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid
from generate_series(2, 3) value
cross join lateral (values (jsonb_build_object(
  'format', jsonb_build_object('modality', 'futbol7'),
  'registration', jsonb_build_object(
    'registrationPolicy', jsonb_build_object(
      'teamLimits', jsonb_build_object('minimum', 2, 'maximum', 8)
    ),
    'rosterPolicy', jsonb_build_object(
      'minimumSize', 0, 'maximumSize', 30,
      'closeRequiresApprovedRosters', false
    )
  ),
  'structure', jsonb_build_object(
    'stageGraph', jsonb_build_object(
      'nodes', jsonb_build_array(jsonb_build_object('id', 'stage', 'root', true)),
      'edges', jsonb_build_array()
    )
  ),
  'operations', jsonb_build_object(),
  'results', jsonb_build_object(),
  'discipline', jsonb_build_object(),
  'governance', jsonb_build_object(),
  'publication', jsonb_build_object(),
  'futureCapabilities', jsonb_build_object()
))) rules(document);

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_rule_revision_id,
  revision, created_by
)
select
  ('7a070000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('7a040000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  case value when 2 then 'Edición por enlace 2027' else 'Temporada privada 2027' end,
  '2027', '2027-09-01', '2028-06-30',
  case when value = 2 then 'registration_open' else 'draft' end,
  ('7a060000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'INVITE_ONLY',
  ('7a060000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  1, md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid
from generate_series(2, 3) value;

insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, visibility, status,
  rule_revision_id, revision, created_by
)
select
  ('7a0b0000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('7a070000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'Senior', 'senior-' || value, 'FOOTBALL_7', 'private', 'active',
  ('7a060000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  1, md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid
from generate_series(2, 3) value;

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, revision, created_by
)
select
  ('7a080000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  ('7a070000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  'Fase principal',
  case when value = 2 then 'KNOCKOUT' else 'LEAGUE_STAGE' end,
  0, false, 'draft',
  ('7a060000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  1, md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid
from generate_series(2, 3) value;

insert into public.pachanga_competition_staff_assignments(
  competition_id, user_id, staff_role, status, assigned_by
)
select
  ('7a040000-0000-4000-8000-' || lpad(value::text, 12, '0'))::uuid,
  md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid,
  'competition_owner', 'active',
  md5('wave7a-user-' || case when value = 2 then 8 else 9 end)::uuid
from generate_series(2, 3) value;

do $demo_public_competitions$
declare response jsonb;
declare publication_id uuid;
declare revision_value bigint;
declare tournament_id uuid;
declare tournament_edition_id uuid;
declare tournament_category_id uuid;
declare tournament_status text;
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', md5('wave7a-user-10')::uuid, 'role', 'authenticated')::text,
    true
  );
  response := public.command_pachanga_league_private_beta_platform_v1(
    md5('demo-world-v2-7-private-league-beta-grant')::uuid,
    md5('wave7a-team-9')::uuid,
    0,
    'beta.bundle.grant',
    '{"organizerKind":"TEAM","maxTeams":12,"expiresAt":"2028-12-31T23:59:59Z","reason":"Demo World V2.7 private organizer perspective"}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","serviceWorkerVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  if response #>> '{snapshot,bundle,status}' <> 'active' then
    raise exception 'DEMO_WORLD_V2_7_PRIVATE_LEAGUE_BUNDLE_NOT_ACTIVE';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', md5('wave7a-user-8')::uuid, 'role', 'authenticated')::text,
    true
  );

  response := public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-unlisted-prepare')::uuid,
    '7a040000-0000-4000-8000-000000000002', 0,
    'publication.prepare',
    '{
      "editionId":"7a070000-0000-4000-8000-000000000002",
      "categoryId":"7a0b0000-0000-4000-8000-000000000002",
      "slug":"copa-enlace-demo","visibility":"unlisted",
      "publicProfile":{
        "name":"Copa Enlace Demo","description":"Torneo no listado accesible únicamente mediante enlace.",
        "municipality":"Barcelona","generalArea":"Barcelona","format":"Eliminatoria",
        "badge":"BETA","rulesSummary":"Cuadro privado compartido por enlace."
      },
      "publicSections":{"teams":true,"calendar":true,"results":true,"standings":false,"bracket":true,"referees":false,"venueDetail":false,"discipline":false},
      "reason":"Prepare unlisted Demo World competition"
    }'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  publication_id := (response #>> '{snapshot,publication,id}')::uuid;
  revision_value := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-unlisted-consent')::uuid,
    '7a040000-0000-4000-8000-000000000002', revision_value,
    'publication.consent',
    '{"statements":{"authorizedRepresentative":true,"informationAccurate":true,"teamAssetsAuthorized":true,"indexingAccepted":true},"purpose":"Compartir la competición mediante enlace no indexable.","reason":"Explicit unlisted consent"}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-unlisted-submit')::uuid,
    '7a040000-0000-4000-8000-000000000002',
    (response ->> 'confirmedRevision')::bigint,
    'publication.submit', '{"reason":"Submit unlisted competition"}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  revision_value := (response ->> 'confirmedRevision')::bigint;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', md5('wave7a-user-10')::uuid, 'role', 'authenticated')::text,
    true
  );
  response := public.command_pachanga_public_competition_moderation_v1(
    md5('demo-world-v2-7-unlisted-approve')::uuid,
    publication_id, revision_value, 'publication.approve',
    '{"reason":"Independent demo review","publicReason":"Publicación aprobada."}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_control_center"}'::jsonb
  );
  response := public.command_pachanga_public_competition_moderation_v1(
    md5('demo-world-v2-7-unlisted-publish')::uuid,
    publication_id, (response ->> 'confirmedRevision')::bigint,
    'publication.publish',
    '{"reason":"Publish unlisted demo competition","publicReason":"Competición disponible por enlace."}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_control_center"}'::jsonb
  );

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', md5('wave7a-user-9')::uuid, 'role', 'authenticated')::text,
    true
  );
  perform public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-private-prepare')::uuid,
    '7a040000-0000-4000-8000-000000000003', 0,
    'publication.prepare',
    '{
      "editionId":"7a070000-0000-4000-8000-000000000003",
      "categoryId":"7a0b0000-0000-4000-8000-000000000003",
      "slug":"liga-privada-organizador-demo","visibility":"private",
      "publicProfile":{
        "name":"Liga Privada Organizador Demo","description":"Borrador visible únicamente para la perspectiva organizadora.",
        "municipality":"Barcelona","generalArea":"Barcelona","format":"Liga","badge":"PRIVADA",
        "rulesSummary":"Configuración privada pendiente de revisión."
      },
      "publicSections":{"teams":true,"calendar":false,"results":false,"standings":false,"bracket":false,"referees":false,"venueDetail":false,"discipline":false},
      "reason":"Prepare private organizer-only Demo World competition"
    }'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );

  select competitions.id, editions.id, categories.id, editions.status
  into tournament_id, tournament_edition_id, tournament_category_id, tournament_status
  from public.pachanga_competitions competitions
  join public.pachanga_competition_editions editions on editions.competition_id = competitions.id
  join public.pachanga_competition_categories categories on categories.edition_id = editions.id
  where competitions.slug = 'copa-barrios-iq-2027'
  order by editions.revision desc, categories.revision desc, categories.id
  limit 1;

  perform set_config(
    'request.jwt.claims',
    '{"sub":"64010000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-tournament-prepare')::uuid,
    tournament_id, 0, 'publication.prepare',
    jsonb_build_object(
      'editionId', tournament_edition_id,
      'categoryId', tournament_category_id,
      'slug', 'copa-barrios-iq-2027',
      'visibility', 'public',
      'publicProfile', jsonb_build_object(
        'name', 'COPA BARRIOS IQ 2027',
        'description', 'Torneo público completado con fase de grupos y cuadro eliminatorio.',
        'municipality', 'Barcelona', 'generalArea', 'Barcelona',
        'format', 'Grupos + eliminatoria', 'badge', 'BETA',
        'rulesSummary', 'Dieciséis equipos, cuatro grupos y eliminatoria a partido único.'
      ),
      'publicSections', jsonb_build_object(
        'teams', true, 'calendar', true, 'results', true, 'standings', true,
        'bracket', true, 'referees', true, 'venueDetail', false, 'discipline', false
      ),
      'reason', 'Prepare canonical tournament public projection'
    ),
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  publication_id := (response #>> '{snapshot,publication,id}')::uuid;
  revision_value := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-tournament-registration')::uuid,
    tournament_id, revision_value, 'registration.configure',
    '{"mode":"CLOSED","reason":"Tournament already in progress"}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  if (select editions.status from public.pachanga_competition_editions editions
      where editions.id = tournament_edition_id) is distinct from tournament_status then
    raise exception 'DEMO_WORLD_V2_7_TOURNAMENT_STATUS_CHANGED_BY_REGISTRATION_CLOSE';
  end if;
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-tournament-consent')::uuid,
    tournament_id, (response ->> 'confirmedRevision')::bigint,
    'publication.consent',
    '{"statements":{"authorizedRepresentative":true,"informationAccurate":true,"teamAssetsAuthorized":true,"indexingAccepted":true},"purpose":"Publicar calendario, resultados y cuadro canónicos.","reason":"Explicit tournament consent"}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  response := public.command_pachanga_competition_publication_v1(
    md5('demo-world-v2-7-tournament-submit')::uuid,
    tournament_id, (response ->> 'confirmedRevision')::bigint,
    'publication.submit', '{"reason":"Submit canonical tournament"}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_public"}'::jsonb
  );
  revision_value := (response ->> 'confirmedRevision')::bigint;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', md5('wave7a-user-10')::uuid, 'role', 'authenticated')::text,
    true
  );
  response := public.command_pachanga_public_competition_moderation_v1(
    md5('demo-world-v2-7-tournament-approve')::uuid,
    publication_id, revision_value, 'publication.approve',
    '{"reason":"Independent tournament review","publicReason":"Publicación aprobada."}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_control_center"}'::jsonb
  );
  perform public.command_pachanga_public_competition_moderation_v1(
    md5('demo-world-v2-7-tournament-publish')::uuid,
    publication_id, (response ->> 'confirmedRevision')::bigint,
    'publication.publish',
    '{"reason":"Publish canonical tournament","publicReason":"Torneo publicado."}'::jsonb,
    '{"clientVersion":"demo-world-v2.7","installedMode":"simulation","surface":"demo_world_v2_control_center"}'::jsonb
  );
end;
$demo_public_competitions$;

commit;
