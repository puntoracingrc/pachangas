\set ON_ERROR_STOP on

do $permissions$
declare target_role text;
begin
  foreach target_role in array array['authenticated', 'anon', 'service_role'] loop
    if not has_schema_privilege(target_role, 'auth', 'USAGE') then
      execute format('grant usage on schema auth to %I', target_role);
    end if;
    if not has_function_privilege(target_role, 'auth.uid()', 'EXECUTE') then
      execute format('grant execute on function auth.uid() to %I', target_role);
    end if;
    if not has_function_privilege(target_role, 'auth.jwt()', 'EXECUTE') then
      execute format('grant execute on function auth.jwt() to %I', target_role);
    end if;
  end loop;
end;
$permissions$;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.actor(target_user_id uuid, target_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', target_user_id, 'role', target_role)::text, true);
end;
$$;

create or replace function pg_temp.expect_failure(statement text, expected_pattern text)
returns text language plpgsql as $$
declare failure text;
begin
  begin
    execute statement;
    raise exception 'WAVE8B_EXPECTED_FAILURE_NOT_RAISED';
  exception when others then
    failure := sqlerrm;
    if failure = 'WAVE8B_EXPECTED_FAILURE_NOT_RAISED' then raise; end if;
    if failure !~* expected_pattern then
      raise exception 'Unexpected failure: % (expected /%/)', failure, expected_pattern;
    end if;
  end;
  return failure;
end;
$$;

create temporary table wave8b_state(
  review_response jsonb,
  review_revision bigint,
  team_c_revision bigint,
  team_d_revision bigint,
  team_e_revision bigint,
  team_f_revision bigint,
  team_f_appeal_id uuid,
  team_f_appeal_revision bigint
);
insert into wave8b_state default values;
grant all on table wave8b_state to authenticated, service_role;

select pg_temp.assert_true(
  count(*) = 7
  and bool_and(lifecycle_status = 'ACTIVE')
  and bool_and(enforcement_status = 'CLEAR')
  and bool_and(effective_status = 'ACTIVE')
  and bool_and(current_revision = 1)
  and bool_and(source = 'MIGRATION_INITIALIZATION'),
  'All seven synthetic Teams must initialize idempotently as ACTIVE + CLEAR'
) from private.pachanga_team_operational_states_v1
where group_id::text like '8b000000-0000-4000-8000-00000000010%';

insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision, billing_status)
values (
  '8b000000-0000-4000-8000-000000000108',
  '8b000000-0000-4000-8000-000000000022',
  'Synthetic Team Created After Migration',
  'W8BTH',
  '{"name":"Synthetic Team Created After Migration","matches":[],"players":[],"siteSettings":{},"venues":[]}',
  1,
  'trial'
);
select pg_temp.assert_true(
  lifecycle_status = 'ACTIVE' and enforcement_status = 'CLEAR'
    and effective_status = 'ACTIVE' and current_revision = 1
    and source = 'MIGRATION_INITIALIZATION',
  'A Team created after migration must receive one canonical ACTIVE + CLEAR state automatically'
) from private.pachanga_team_operational_states_v1
where group_id = '8b000000-0000-4000-8000-000000000108';

select pg_temp.assert_true(
  not foundation_enabled and not enforcement_enabled and not restrictions_enabled
    and not continuity_enabled and not appeals_enabled and not cross_product_guards_enabled
    and not public_projection_enabled and not demo_world_v31_enabled,
  'All Wave 8B flags must be born OFF'
) from private.pachanga_team_operational_settings_v1 where singleton;

select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_user_notifications notifications
    where notifications.kind like 'team_operational_%'
  ),
  'Migration initialization must not emit Team operational notifications'
);

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000001');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,1,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000001', '8b000000-0000-4000-8000-000000000101',
  'team.lifecycle.archive', '{"confirm":true}', '{}'
), 'TEAM_OPERATIONAL_FEATURE_DISABLED');
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000020');
select public.command_pachanga_team_operational_settings_v1(
  '8b100000-0000-4000-8000-000000000002', 1,
  '{"foundationEnabled":true,"reason":"Wave 8B synthetic foundation gate"}'
);
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,1,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000003', '8b000000-0000-4000-8000-000000000103',
  'team.restriction.apply',
  '{"confirm":true,"preset":"SOCIAL_ONLY","reasonCode":"synthetic.flag.gate"}', '{}'
), 'TEAM_OPERATIONAL_RESTRICTIONS_DISABLED');
select public.command_pachanga_team_operational_settings_v1(
  '8b100000-0000-4000-8000-000000000004', 2,
  '{
    "enforcementEnabled":true,"restrictionsEnabled":true,"continuityEnabled":true,
    "appealsEnabled":true,"crossProductGuardsEnabled":true,
    "publicProjectionEnabled":true,"demoWorldV31Enabled":true,
    "reason":"Wave 8B synthetic full activation"
  }'
);
reset role;

select pg_temp.assert_true(
  foundation_enabled and enforcement_enabled and restrictions_enabled
    and continuity_enabled and appeals_enabled and cross_product_guards_enabled
    and public_projection_enabled and demo_world_v31_enabled and revision = 3,
  'Synthetic activation must enable all eight Wave 8B gates through the platform RPC'
) from private.pachanga_team_operational_settings_v1 where singleton;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000021');
with opened as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000010',
    '8b000000-0000-4000-8000-000000000102', 1, 'team.review.open',
    '{
      "reasonCode":"synthetic.review.signal","safeMessage":"Estamos revisando la disponibilidad del equipo.",
      "privateNote":"Private synthetic evidence","evidence":{"synthetic":true}
    }',
    '{"clientVersion":"8.1.0+synthetic","serviceWorkerVersion":"sw-wave8b","installedMode":"standalone","surface":"simulation_world","secret":"discard"}'
  ) body
)
update wave8b_state set
  review_response = opened.body,
  review_revision = (opened.body ->> 'confirmedRevision')::bigint
from opened;
select pg_temp.assert_true(
  public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000010',
    '8b000000-0000-4000-8000-000000000102', 1, 'team.review.open',
    '{
      "reasonCode":"synthetic.review.signal","safeMessage":"Estamos revisando la disponibilidad del equipo.",
      "privateNote":"Private synthetic evidence","evidence":{"synthetic":true}
    }',
    '{"clientVersion":"8.1.0+synthetic","serviceWorkerVersion":"sw-wave8b","installedMode":"standalone","surface":"simulation_world","secret":"discard"}'
  ) = (select review_response from wave8b_state),
  'Exact replay must return the canonical receipt without a second decision'
);
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,%s,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000019',
  '8b000000-0000-4000-8000-000000000102',
  (select review_revision from wave8b_state),
  'team.review.close',
  '{"outcome":"NO_ACTION","reasonCode":"synthetic.review.missing_id"}',
  '{}'
), 'TEAM_REVIEW_ID_REQUIRED');
reset role;

select pg_temp.assert_true(
  enforcement_status = 'UNDER_REVIEW' and effective_status = 'UNDER_REVIEW'
    and current_revision = 2
    and private.pachanga_team_operational_scope_allowed_v1(group_id, 'MARKETPLACE'),
  'UNDER_REVIEW must remain non-blocking without an explicit restriction'
) from private.pachanga_team_operational_states_v1
where group_id = '8b000000-0000-4000-8000-000000000102';

select pg_temp.assert_true(
  count(*) = 1,
  'Idempotent replay must emit one owner notification'
) from public.pachanga_user_notifications notifications
where notifications.dedupe_key = 'team-operational:8b100000-0000-4000-8000-000000000010:8b000000-0000-4000-8000-000000000002';

select pg_temp.assert_true(
  client_metadata = '{"surface":"simulation_world","clientVersion":"8.1.0+synthetic","installedMode":"standalone","serviceWorkerVersion":"sw-wave8b"}'::jsonb,
  'Client metadata must be allowlisted and strip unknown fields'
) from private.pachanga_team_operational_operation_receipts_v1
where operation_id = '8b100000-0000-4000-8000-000000000010';

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000020');
with restricted as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000020',
    '8b000000-0000-4000-8000-000000000103', 1, 'team.restriction.apply',
    '{
      "confirm":true,"preset":"SOCIAL_ONLY",
      "continuityPolicy":"ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
      "reasonCode":"synthetic.social.restriction","publicMessage":"Funciones sociales limitadas temporalmente.",
      "privateNote":"Private Team C note","evidence":{"source":"simulation"}
    }', '{}'
  ) body
)
update wave8b_state set team_c_revision = (restricted.body ->> 'confirmedRevision')::bigint from restricted;
with suspended as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000021',
    '8b000000-0000-4000-8000-000000000104', 1, 'team.suspend',
    '{
      "confirm":true,"preset":"NEW_ACTIVITY_ONLY",
      "continuityPolicy":"ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
      "reasonCode":"synthetic.new.activity.suspension","publicMessage":"No puede iniciar actividad nueva."
    }', '{}'
  ) body
)
update wave8b_state set team_d_revision = (suspended.body ->> 'confirmedRevision')::bigint from suspended;
with restricted as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000022',
    '8b000000-0000-4000-8000-000000000106', 1, 'team.restriction.apply',
    '{
      "confirm":true,"preset":"SOCIAL_ONLY",
      "continuityPolicy":"ALLOW_EXISTING_COMPETITIONS_TO_FINISH",
      "reasonCode":"synthetic.owner.transfer","publicMessage":"Limitación conservada durante el cambio de owner."
    }', '{}'
  ) body
)
update wave8b_state set team_f_revision = (restricted.body ->> 'confirmedRevision')::bigint from restricted;
reset role;

select pg_temp.assert_true(
  not private.pachanga_team_operational_scope_allowed_v1('8b000000-0000-4000-8000-000000000103', 'MARKETPLACE')
    and not private.pachanga_team_operational_scope_allowed_v1('8b000000-0000-4000-8000-000000000103', 'SOCIAL_CHALLENGES')
    and private.pachanga_team_operational_scope_allowed_v1('8b000000-0000-4000-8000-000000000103', 'NEW_MATCH_CREATION')
    and private.pachanga_team_operational_scope_allowed_v1('8b000000-0000-4000-8000-000000000103', 'EXISTING_COMPETITION_OPERATIONS'),
  'SOCIAL_ONLY must block only Marketplace and Challenges'
);

select pg_temp.assert_true(
  enforcement_status = 'SUSPENDED' and effective_status = 'SUSPENDED'
    and not private.pachanga_team_operational_scope_allowed_v1(group_id, 'NEW_MATCH_CREATION')
    and not private.pachanga_team_operational_scope_allowed_v1(group_id, 'COMPETITION_REGISTRATION')
    and not private.pachanga_team_operational_scope_allowed_v1(group_id, 'COMPETITION_ORGANIZER')
    and private.pachanga_team_operational_scope_allowed_v1(group_id, 'EXISTING_COMPETITION_OPERATIONS'),
  'NEW_ACTIVITY_ONLY suspension must preserve explicitly allowed existing Competition operations'
) from private.pachanga_team_operational_states_v1
where group_id = '8b000000-0000-4000-8000-000000000104';

select pg_temp.expect_failure($sql$
  insert into public.pachanga_open_matches(source_group_id, source_match_id, date, active, created_by)
  values ('8b000000-0000-4000-8000-000000000103', 'synthetic-market-blocked', clock_timestamp() + interval '1 day', true,
    '8b000000-0000-4000-8000-000000000003')
$sql$, 'TEAM_OPERATIONALLY_RESTRICTED');

select pg_temp.expect_failure($sql$
  insert into public.pachanga_team_challenges(
    sender_group_id, receiver_group_id, status, scheduled_at, modality,
    field_name, field_address, last_proposed_by_group_id, created_by, updated_by
  ) values (
    '8b000000-0000-4000-8000-000000000103', '8b000000-0000-4000-8000-000000000101', 'proposed',
    clock_timestamp() + interval '2 days', 'futbol7', 'Synthetic Field', 'Synthetic Address',
    '8b000000-0000-4000-8000-000000000103', '8b000000-0000-4000-8000-000000000003',
    '8b000000-0000-4000-8000-000000000003'
  )
$sql$, 'TEAM_OPERATIONALLY_RESTRICTED');

select pg_temp.expect_failure($sql$
  insert into public.pachanga_competitions(
    organizer_kind, organizer_group_id, name, slug, competition_type, status, created_by
  ) values (
    'TEAM', '8b000000-0000-4000-8000-000000000104', 'Synthetic Blocked Competition',
    'synthetic-blocked-competition', 'league', 'draft', '8b000000-0000-4000-8000-000000000004'
  )
$sql$, 'TEAM_OPERATIONALLY_RESTRICTED');

select pg_temp.expect_failure($sql$
  update public.pachanga_groups groups set payload = jsonb_set(
    groups.payload, '{matches}', '[{"id":"synthetic-new-match"}]'::jsonb
  ) where groups.id = '8b000000-0000-4000-8000-000000000104'
$sql$, 'TEAM_OPERATIONALLY_RESTRICTED');

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000009');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,1,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000030', '8b000000-0000-4000-8000-000000000101',
  'team.lifecycle.archive', '{"confirm":true}', '{}'
), 'TEAM_OWNER_REQUIRED');
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000003');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,2,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000031', '8b000000-0000-4000-8000-000000000103',
  'team.restriction.lift', '{"confirm":true}', '{}'
), 'Platform access required|PLATFORM_ROLE_REQUIRED|PLATFORM_CAPABILITY_REQUIRED');
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000005');
with archived as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000040',
    '8b000000-0000-4000-8000-000000000105', 1, 'team.lifecycle.archive',
    '{"confirm":true,"continuityPolicy":"HISTORY_ONLY","reasonCode":"owner.voluntary.archive"}', '{}'
  ) body
)
update wave8b_state set team_e_revision = (archived.body ->> 'confirmedRevision')::bigint from archived;
select pg_temp.assert_true(
  (public.get_pachanga_team_operational_state_v1('8b000000-0000-4000-8000-000000000105') ->> 'effectiveStatus') = 'ARCHIVED',
  'Owner must see the canonical archived state'
);
with restored as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000041',
    '8b000000-0000-4000-8000-000000000105', 2, 'team.lifecycle.restore',
    '{"confirm":true,"reasonCode":"owner.voluntary.restore"}', '{}'
  ) body
)
update wave8b_state set team_e_revision = (restored.body ->> 'confirmedRevision')::bigint from restored;
reset role;

select pg_temp.assert_true(
  lifecycle_status = 'ACTIVE' and enforcement_status = 'CLEAR' and current_revision = 3,
  'Lifecycle restoration must not manufacture or remove platform enforcement'
) from private.pachanga_team_operational_states_v1
where group_id = '8b000000-0000-4000-8000-000000000105';

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000006');
select public.transfer_pachanga_group_ownership_authoritative_v1(
  '8b000000-0000-4000-8000-000000000106',
  '8b000000-0000-4000-8000-000000000008',
  '8b100000-0000-4000-8000-000000000050',
  (select payload_revision from public.pachanga_groups where id = '8b000000-0000-4000-8000-000000000106'),
  '{"clientVersion":"8.1.0+synthetic","surface":"simulation_world"}'
);
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,2,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000051', '8b000000-0000-4000-8000-000000000106',
  'team.appeal.create', '{"requestedOutcome":"LIFT","message":"Old owner must fail"}', '{}'
), 'TEAM_OWNER_REQUIRED');
reset role;

select pg_temp.assert_true(
  current_revision = 2 and enforcement_status = 'LIMITED'
    and (select owner_id = '8b000000-0000-4000-8000-000000000008'
      from public.pachanga_groups where id = states.group_id),
  'Owner transfer must preserve the Team restriction without adding a Team state revision'
) from private.pachanga_team_operational_states_v1 states
where group_id = '8b000000-0000-4000-8000-000000000106';

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000008');
with created as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000052',
    '8b000000-0000-4000-8000-000000000106', 2, 'team.appeal.create',
    '{"requestedOutcome":"LIFT","message":"Synthetic owner appeal","reasonCode":"owner.appeal.create"}', '{}'
  ) body
)
update wave8b_state set
  team_f_revision = (created.body ->> 'confirmedRevision')::bigint,
  team_f_appeal_id = (created.body -> 'snapshot' -> 'appeal' ->> 'id')::uuid
from created;
with submitted as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000053',
    '8b000000-0000-4000-8000-000000000106', team_f_revision, 'team.appeal.submit',
    jsonb_build_object('appealId', team_f_appeal_id, 'message', 'Synthetic appeal submitted', 'reasonCode', 'owner.appeal.submit'), '{}'
  ) body from wave8b_state
)
update wave8b_state set team_f_revision = (submitted.body ->> 'confirmedRevision')::bigint from submitted;
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000021');
with reviewed as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000054',
    '8b000000-0000-4000-8000-000000000106', team_f_revision, 'team.appeal.review',
    jsonb_build_object(
      'appealId', team_f_appeal_id,
      'safeMessage', 'La revisión está en curso.',
      'privateNote', 'Private moderator appeal note',
      'reasonCode', 'platform.appeal.review'
    ), '{}'
  ) body from wave8b_state
)
update wave8b_state set team_f_revision = (reviewed.body ->> 'confirmedRevision')::bigint from reviewed;
with resolved as (
  select public.command_pachanga_team_operational_state_v1(
    '8b100000-0000-4000-8000-000000000055',
    '8b000000-0000-4000-8000-000000000106', team_f_revision, 'team.appeal.resolve',
    jsonb_build_object(
      'appealId', team_f_appeal_id,
      'resolution', 'OVERTURNED',
      'safeMessage', 'La limitación se ha retirado.',
      'privateNote', 'Private overturned rationale',
      'reasonCode', 'platform.appeal.overturned'
    ), '{}'
  ) body from wave8b_state
)
update wave8b_state set team_f_revision = (resolved.body ->> 'confirmedRevision')::bigint from resolved;
reset role;

select pg_temp.assert_true(
  enforcement_status = 'CLEAR' and current_revision = 6
    and not exists (
      select 1 from private.pachanga_team_operational_restrictions_v1 restrictions
      where restrictions.group_id = states.group_id and restrictions.status = 'ACTIVE'
    ),
  'Overturned appeal must lift the active Team restriction without deleting its history'
) from private.pachanga_team_operational_states_v1 states
where group_id = '8b000000-0000-4000-8000-000000000106';

select pg_temp.assert_true(
  count(*) = 6
    and count(*) filter (where visibility = 'OWNER_SAFE') = 4
    and count(*) filter (where visibility = 'PLATFORM_PRIVATE') = 2,
  'Appeal messages must preserve owner-safe and platform-private history separately'
) from private.pachanga_team_operational_appeal_messages_v1 messages
where messages.appeal_id = (select team_f_appeal_id from wave8b_state);

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000008');
select pg_temp.assert_true(
  position('Private moderator appeal note' in public.get_pachanga_team_operational_state_v1(
    '8b000000-0000-4000-8000-000000000106'
  )::text) = 0
  and position('Private overturned rationale' in public.get_pachanga_team_operational_state_v1(
    '8b000000-0000-4000-8000-000000000106'
  )::text) = 0,
  'Owner projection must never expose platform-private appeal messages'
);
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000001');
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_team_operational_states_v1() -> 'items') = 1
    and (public.get_my_pachanga_team_operational_states_v1() -> 'items' -> 0 ->> 'isOwner')::boolean
    and jsonb_typeof(public.get_my_pachanga_team_operational_states_v1() -> 'items' -> 0 -> 'impact') = 'object',
  'Owner read model must expose exactly the owned Team with owner-safe impact'
);
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000009');
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_team_operational_states_v1() -> 'items') = 1
    and not (public.get_my_pachanga_team_operational_states_v1() -> 'items' -> 0 ->> 'isOwner')::boolean
    and public.get_my_pachanga_team_operational_states_v1() -> 'items' -> 0 -> 'impact' = 'null'::jsonb,
  'Team admin read model must remain read-only and omit owner impact details'
);
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000024');
select pg_temp.assert_true(
  jsonb_array_length(public.get_my_pachanga_team_operational_states_v1() -> 'items') = 0,
  'A user with no Team membership must receive an empty canonical Team list'
);
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000023');
select pg_temp.assert_true(
  (public.list_pachanga_platform_team_operational_states_v1('{"status":"UNDER_REVIEW"}', 50, 0) ->> 'total')::integer = 1
    and (public.list_pachanga_platform_team_operational_states_v1('{"status":"SUSPENDED"}', 50, 0) ->> 'total')::integer = 1,
  'Control Center filters must select canonical under-review and suspended Teams'
);
select pg_temp.assert_true(
  position('Private synthetic evidence' in public.get_pachanga_platform_team_operational_detail_v1(
    '8b000000-0000-4000-8000-000000000102'
  )::text) = 0,
  'Support read access must not expose private review notes or evidence'
);
reset role;

set local role anon;
select pg_temp.actor(null, 'anon');
select pg_temp.assert_true(
  position('private' in lower(public.get_public_pachanga_team_operational_state_v1(
    '8b000000-0000-4000-8000-000000000103'
  )::text)) = 0
  and not (public.get_public_pachanga_team_operational_state_v1(
    '8b000000-0000-4000-8000-000000000103'
  ) ? 'restrictions'),
  'Public projection must not contain private evidence, notes, scopes or appeals'
);
reset role;

select set_config('pachanga.team_operational_authority', 'off', true);
select pg_temp.expect_failure($sql$
  update private.pachanga_team_operational_states_v1
  set public_message = public_message
  where group_id = '8b000000-0000-4000-8000-000000000103'
$sql$, 'TEAM_OPERATIONAL_COMMAND_AUTHORITY_REQUIRED');

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000022');
select pg_temp.expect_failure($sql$
  select public.get_pachanga_team_operational_state_v1('8b000000-0000-4000-8000-000000000103')
$sql$, 'TEAM_MEMBERSHIP_REQUIRED');
select pg_temp.assert_true(
  count(*) = 0,
  'RLS must hide Team operational invalidations from unrelated users'
) from public.pachanga_team_operational_invalidations_v1;
reset role;

insert into private.pachanga_platform_user_states(
  user_id, status, reason, expires_at, updated_by
) values (
  '8b000000-0000-4000-8000-000000000001', 'suspended', 'Synthetic personal suspension',
  clock_timestamp() + interval '1 day', '8b000000-0000-4000-8000-000000000020'
);
insert into public.pachanga_conduct_subject_state(user_id)
values ('8b000000-0000-4000-8000-000000000001')
on conflict (user_id) do update set revision = public.pachanga_conduct_subject_state.revision + 1;

select pg_temp.assert_true(
  states.lifecycle_status = 'ACTIVE' and states.enforcement_status = 'CLEAR'
    and groups.billing_status = 'trial',
  'Owner suspension and Conduct state must not alter the Team operational state'
) from private.pachanga_team_operational_states_v1 states
join public.pachanga_groups groups on groups.id = states.group_id
where states.group_id = '8b000000-0000-4000-8000-000000000101';

select pg_temp.assert_true(
  states.lifecycle_status = 'ACTIVE' and states.enforcement_status = 'CLEAR'
    and states.effective_status = 'ACTIVE' and groups.billing_status = 'past_due',
  'Inactive Billing must remain independent from the Team operational state'
) from private.pachanga_team_operational_states_v1 states
join public.pachanga_groups groups on groups.id = states.group_id
where states.group_id = '8b000000-0000-4000-8000-000000000107';

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000001');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,1,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000060', '8b000000-0000-4000-8000-000000000101',
  'team.lifecycle.archive', '{"confirm":true}', '{}'
), 'ACTOR_OPERATIONALLY_SUSPENDED');
reset role;

set local role authenticated;
select pg_temp.actor('8b000000-0000-4000-8000-000000000020');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,1,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000061', '8b000000-0000-4000-8000-000000000103',
  'team.restriction.apply',
  '{"confirm":true,"preset":"SOCIAL_ONLY","reasonCode":"synthetic.stale"}', '{}'
), 'STALE_REVISION');
select pg_temp.expect_failure(format(
  'select public.command_pachanga_team_operational_state_v1(%L,%L,2,%L,%L::jsonb,%L::jsonb)',
  '8b100000-0000-4000-8000-000000000062', '8b000000-0000-4000-8000-000000000103',
  'team.restriction.modify',
  '{"confirm":true,"preset":"SOCIAL_ONLY","reasonCode":"synthetic.inject","effectiveStatus":"CLEAR","serverSequence":999}', '{}'
), 'TEAM_OPERATIONAL_PAYLOAD_FIELD_NOT_ALLOWED');
reset role;

select pg_temp.assert_true(
  (select count(*) from private.pachanga_team_operational_states_v1
    where group_id::text like '8b000000-0000-4000-8000-00000000010%') = 8
  and (select count(*) from private.pachanga_team_operational_state_revisions_v1 revisions
    where revisions.group_id = '8b000000-0000-4000-8000-000000000103') = 2
  and (select count(*) from private.pachanga_team_operational_operation_receipts_v1 receipts
    where receipts.operation_id = '8b100000-0000-4000-8000-000000000010') = 1,
  'Synthetic decisions must retain one current state, append-only revisions and one receipt per operation'
);

select 'TEAM_OPERATIONAL_STATE_V1_DB_PASS';
