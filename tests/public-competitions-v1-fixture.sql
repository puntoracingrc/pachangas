\set ON_ERROR_STOP on

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select md5('wave7a-user-' || value)::uuid,
  'wave7a-user-' || value || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'Wave 7A User ' || value)
from generate_series(0, 10) value;

insert into private.pachanga_platform_admin_roles(user_id, role, active)
values (md5('wave7a-user-10')::uuid, 'platform_owner', true);

insert into public.pachanga_groups(
  id, owner_id, name, team_code, payload, payload_revision
)
select md5('wave7a-team-' || value)::uuid,
  md5('wave7a-user-' || value)::uuid,
  case when value = 0 then 'Wave 7A Organizer' else 'Wave 7A Team ' || value end,
  'W7A' || lpad(value::text, 5, '0'),
  jsonb_build_object(
    'matches', '[]'::jsonb,
    'players', '[]'::jsonb,
    'siteSettings', jsonb_build_object(
      'privatePhone', '+34 600 000 ' || lpad(value::text, 3, '0'),
      'privateEmail', 'private-' || value || '@example.test'
    ),
    'venues', '[]'::jsonb
  ),
  1
from generate_series(0, 9) value;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select md5('wave7a-team-' || value)::uuid,
  md5('wave7a-user-' || value)::uuid,
  'owner',
  case when value = 0 then 'Wave 7A Organizer' else 'Wave 7A Owner ' || value end
from generate_series(0, 9) value;

insert into public.pachanga_competitions(
  id, organizer_kind, organizer_group_id, name, slug, description,
  competition_type, visibility, status, general_area, created_by
) values (
  '7a040000-0000-4000-8000-000000000001',
  'TEAM', md5('wave7a-team-0')::uuid,
  'Liga Pública Wave 7A', 'liga-publica-wave-7a',
  'Descripción privada con SECRET_PRIVATE_DESCRIPTION',
  'LEAGUE', 'private', 'draft', 'Barcelona', md5('wave7a-user-0')::uuid
);

insert into public.pachanga_competition_rule_sets(
  id, competition_id, name, status, created_by
) values (
  '7a050000-0000-4000-8000-000000000001',
  '7a040000-0000-4000-8000-000000000001',
  'Wave 7A Rules', 'active', md5('wave7a-user-0')::uuid
);

insert into public.pachanga_competition_rule_revisions(
  id, rule_set_id, version, schema_version, rule_document, checksum,
  effective_from, effective_scope, status, revision, reason, created_by
)
select '7a060000-0000-4000-8000-000000000001',
  '7a050000-0000-4000-8000-000000000001',
  1, 'competition_rules.v1', document,
  private.pachanga_competition_rule_checksum_v1('competition_rules.v1', document),
  clock_timestamp(), 'future_only', 'frozen', 1,
  'Wave 7A deterministic rules', md5('wave7a-user-0')::uuid
from (values ('{
  "format":{"modality":"futbol7"},
  "registration":{
    "registrationPolicy":{"teamLimits":{"minimum":2,"maximum":2}},
    "rosterPolicy":{"minimumSize":0,"maximumSize":30,"closeRequiresApprovedRosters":false}
  },
  "structure":{"stageGraph":{"nodes":[{"id":"league-stage","root":true}],"edges":[]}},
  "operations":{},"results":{},"discipline":{},"governance":{},
  "publication":{},"futureCapabilities":{}
}'::jsonb)) rules(document);

insert into public.pachanga_competition_editions(
  id, competition_id, name, season_label, starts_at, ends_at, status,
  rule_revision_id, registration_mode, registration_rule_revision_id,
  revision, created_by
) values (
  '7a070000-0000-4000-8000-000000000001',
  '7a040000-0000-4000-8000-000000000001',
  'Temporada 2027', '2027', '2027-09-01', '2028-06-30',
  'draft', '7a060000-0000-4000-8000-000000000001',
  'INVITE_ONLY', '7a060000-0000-4000-8000-000000000001',
  1, md5('wave7a-user-0')::uuid
);

insert into public.pachanga_competition_categories(
  id, edition_id, name, slug, sport_format, visibility, status,
  rule_revision_id, revision, created_by
) values (
  '7a0b0000-0000-4000-8000-000000000001',
  '7a070000-0000-4000-8000-000000000001',
  'Senior', 'senior', 'FOOTBALL_7', 'public', 'active',
  '7a060000-0000-4000-8000-000000000001',
  1, md5('wave7a-user-0')::uuid
);

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, revision, created_by
) values (
  '7a080000-0000-4000-8000-000000000001',
  '7a070000-0000-4000-8000-000000000001',
  'Liga regular', 'LEAGUE_STAGE', 0, false, 'draft',
  '7a060000-0000-4000-8000-000000000001',
  1, md5('wave7a-user-0')::uuid
);

insert into public.pachanga_competition_staff_assignments(
  competition_id, user_id, staff_role, status, assigned_by
) values (
  '7a040000-0000-4000-8000-000000000001',
  md5('wave7a-user-0')::uuid,
  'competition_owner', 'active', md5('wave7a-user-0')::uuid
);
