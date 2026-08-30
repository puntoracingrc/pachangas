\set ON_ERROR_STOP on

begin;

create temporary table wave8b_demo_baseline as
select
  (select count(*) from public.pachanga_competition_official_result_decisions) as official_results,
  (select count(*) from public.pachanga_competition_no_show_incidents) as no_shows,
  (select count(*) from public.pachanga_player_rating_snapshots) as rating_snapshots,
  (select count(*) from public.pachanga_reward_grants) as reward_grants,
  (select count(*) from public.pachanga_team_cosmetic_inventory) as team_cosmetics,
  (select count(*) from public.pachanga_player_cosmetic_loadouts) as player_cosmetics;

create temporary table wave8b_demo_runtime(appeal_id uuid);
insert into wave8b_demo_runtime default values;
grant all on table wave8b_demo_runtime to authenticated;

set local role authenticated;

do $simulation$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', '8b000000-0000-4000-8000-000000000020',
      'role', 'authenticated'
    )::text,
    true
  );
  perform public.command_pachanga_team_operational_settings_v1(
    '8b310000-0000-4000-8000-000000000001',
    1,
    jsonb_build_object(
      'foundationEnabled', true,
      'enforcementEnabled', true,
      'restrictionsEnabled', true,
      'continuityEnabled', true,
      'appealsEnabled', true,
      'crossProductGuardsEnabled', true,
      'publicProjectionEnabled', true,
      'demoWorldV31Enabled', true,
      'reason', 'Demo World V3.1 isolated synthetic activation'
    )
  );
end;
$simulation$;

do $simulation$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', '8b000000-0000-4000-8000-000000000021',
      'role', 'authenticated'
    )::text,
    true
  );
  perform public.command_pachanga_team_operational_state_v1(
    '8b310000-0000-4000-8000-000000000010',
    '8b000000-0000-4000-8000-000000000102',
    1,
    'team.review.open',
    jsonb_build_object(
      'reasonCode', 'simulation.review.signal',
      'safeMessage', 'Revisión operativa en curso sin bloqueo automático.',
      'privateNote', 'Synthetic private evidence removed before public snapshot',
      'evidence', jsonb_build_object('source', 'simulation-world')
    ),
    jsonb_build_object(
      'clientVersion', '8.2.0+simulation',
      'serviceWorkerVersion', 'sw-wave8b-v31',
      'installedMode', 'standalone',
      'surface', 'simulation_world'
    )
  );
end;
$simulation$;

do $simulation$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', '8b000000-0000-4000-8000-000000000020',
      'role', 'authenticated'
    )::text,
    true
  );
  perform public.command_pachanga_team_operational_state_v1(
    '8b310000-0000-4000-8000-000000000020',
    '8b000000-0000-4000-8000-000000000103',
    1,
    'team.restriction.apply',
    jsonb_build_object(
      'confirm', true,
      'preset', 'SOCIAL_ONLY',
      'continuityPolicy', 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
      'reasonCode', 'simulation.social.only',
      'publicMessage', 'Funciones sociales limitadas temporalmente.',
      'privateNote', 'Synthetic private Team C note',
      'evidence', jsonb_build_object('source', 'simulation-world')
    ),
    jsonb_build_object('clientVersion', '8.2.0+simulation', 'surface', 'simulation_world')
  );
  perform public.command_pachanga_team_operational_state_v1(
    '8b310000-0000-4000-8000-000000000021',
    '8b000000-0000-4000-8000-000000000104',
    1,
    'team.suspend',
    jsonb_build_object(
      'confirm', true,
      'preset', 'NEW_ACTIVITY_ONLY',
      'continuityPolicy', 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
      'reasonCode', 'simulation.new.activity.only',
      'publicMessage', 'No puede iniciar actividad nueva.'
    ),
    jsonb_build_object('clientVersion', '8.2.0+simulation', 'surface', 'simulation_world')
  );
  perform public.command_pachanga_team_operational_state_v1(
    '8b310000-0000-4000-8000-000000000022',
    '8b000000-0000-4000-8000-000000000106',
    1,
    'team.restriction.apply',
    jsonb_build_object(
      'confirm', true,
      'preset', 'SOCIAL_ONLY',
      'continuityPolicy', 'ALLOW_EXISTING_COMPETITIONS_TO_FINISH',
      'reasonCode', 'simulation.owner.transfer',
      'publicMessage', 'La limitación permanece durante el cambio de owner.'
    ),
    jsonb_build_object('clientVersion', '8.2.0+simulation', 'surface', 'simulation_world')
  );
end;
$simulation$;

do $simulation$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', '8b000000-0000-4000-8000-000000000005',
      'role', 'authenticated'
    )::text,
    true
  );
  perform public.command_pachanga_team_operational_state_v1(
    '8b310000-0000-4000-8000-000000000030',
    '8b000000-0000-4000-8000-000000000105',
    1,
    'team.lifecycle.archive',
    jsonb_build_object(
      'confirm', true,
      'continuityPolicy', 'HISTORY_ONLY',
      'reasonCode', 'simulation.owner.archive'
    ),
    jsonb_build_object('clientVersion', '8.2.0+simulation', 'surface', 'simulation_world')
  );
end;
$simulation$;

do $simulation$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', '8b000000-0000-4000-8000-000000000006',
      'role', 'authenticated'
    )::text,
    true
  );
  perform public.transfer_pachanga_group_ownership_authoritative_v1(
    '8b000000-0000-4000-8000-000000000106',
    '8b000000-0000-4000-8000-000000000008',
    '8b310000-0000-4000-8000-000000000040',
    1,
    jsonb_build_object('clientVersion', '8.2.0+simulation', 'surface', 'simulation_world')
  );
end;
$simulation$;

do $simulation$
declare response jsonb;
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object(
      'sub', '8b000000-0000-4000-8000-000000000008',
      'role', 'authenticated'
    )::text,
    true
  );
  response := public.command_pachanga_team_operational_state_v1(
    '8b310000-0000-4000-8000-000000000041',
    '8b000000-0000-4000-8000-000000000106',
    2,
    'team.appeal.create',
    jsonb_build_object(
      'requestedOutcome', 'LIFT',
      'message', 'Solicitud sintética de revisión del nuevo owner.',
      'reasonCode', 'simulation.owner.appeal'
    ),
    jsonb_build_object('clientVersion', '8.2.0+simulation', 'surface', 'simulation_world')
  );
  update wave8b_demo_runtime
  set appeal_id = (response -> 'snapshot' -> 'appeal' ->> 'id')::uuid;
  response := public.command_pachanga_team_operational_state_v1(
    '8b310000-0000-4000-8000-000000000042',
    '8b000000-0000-4000-8000-000000000106',
    (response ->> 'confirmedRevision')::bigint,
    'team.appeal.submit',
    jsonb_build_object(
      'appealId', (select appeal_id from wave8b_demo_runtime),
      'message', 'Solicitud sintética enviada por el nuevo owner.',
      'reasonCode', 'simulation.owner.appeal.submit'
    ),
    jsonb_build_object('clientVersion', '8.2.0+simulation', 'surface', 'simulation_world')
  );
end;
$simulation$;

reset role;

with scope_catalog(scope, ordinal) as (
  values
    ('PUBLIC_DISCOVERY', 1),
    ('MARKETPLACE', 2),
    ('SOCIAL_CHALLENGES', 3),
    ('NEW_MATCH_CREATION', 4),
    ('COMPETITION_REGISTRATION', 5),
    ('COMPETITION_ORGANIZER', 6),
    ('EXISTING_COMPETITION_OPERATIONS', 7),
    ('TEAM_MEMBERSHIP_ADMINISTRATION', 8),
    ('PUBLIC_PROFILE', 9)
), scenario_map(group_id, id, label, ordinal) as (
  values
    ('8b000000-0000-4000-8000-000000000101'::uuid, 'TEAM_A_ACTIVE', 'Aurora Norte', 1),
    ('8b000000-0000-4000-8000-000000000102'::uuid, 'TEAM_B_UNDER_REVIEW', 'Brújula FC', 2),
    ('8b000000-0000-4000-8000-000000000103'::uuid, 'TEAM_C_LIMITED_SOCIAL_ONLY', 'Cobalto Real', 3),
    ('8b000000-0000-4000-8000-000000000104'::uuid, 'TEAM_D_SUSPENDED_NEW_ACTIVITY', 'Delta Unión', 4),
    ('8b000000-0000-4000-8000-000000000105'::uuid, 'TEAM_E_ARCHIVED', 'Estrella Sur', 5),
    ('8b000000-0000-4000-8000-000000000106'::uuid, 'TEAM_F_OWNER_TRANSFER', 'Faro Atlético', 6),
    ('8b000000-0000-4000-8000-000000000107'::uuid, 'TEAM_G_BILLING_INACTIVE', 'Grada Nova', 7)
), scenario_rows as (
  select map.ordinal, jsonb_build_object(
    'id', map.id,
    'teamName', map.label,
    'lifecycle', states.lifecycle_status,
    'enforcement', states.enforcement_status,
    'effectiveStatus', states.effective_status,
    'restrictionPreset', states.restriction_preset,
    'continuityPolicy', states.continuity_policy,
    'revision', states.current_revision,
    'allowedScopes', (
      select coalesce(jsonb_agg(scope_catalog.scope order by scope_catalog.ordinal), '[]'::jsonb)
      from scope_catalog
      where private.pachanga_team_operational_scope_allowed_v1(map.group_id, scope_catalog.scope)
    ),
    'blockedScopes', (
      select coalesce(jsonb_agg(scope_catalog.scope order by scope_catalog.ordinal), '[]'::jsonb)
      from scope_catalog
      where not private.pachanga_team_operational_scope_allowed_v1(map.group_id, scope_catalog.scope)
    ),
    'directoryVisible', states.lifecycle_status = 'ACTIVE'
      and private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'PUBLIC_DISCOVERY')
      and private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'PUBLIC_PROFILE'),
    'marketplaceAllowed', private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'MARKETPLACE'),
    'challengesAllowed', private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'SOCIAL_CHALLENGES'),
    'newMatchAllowed', private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'NEW_MATCH_CREATION'),
    'newCompetitionRegistrationAllowed', private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'COMPETITION_REGISTRATION'),
    'newCompetitionOrganizerAllowed', private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'COMPETITION_ORGANIZER'),
    'existingCompetitionOperationsAllowed', private.pachanga_team_operational_scope_allowed_v1(map.group_id, 'EXISTING_COMPETITION_OPERATIONS'),
    'reviewOpen', exists (
      select 1 from private.pachanga_team_operational_reviews_v1 reviews
      where reviews.group_id = map.group_id and reviews.status in ('OPEN', 'NEEDS_INFORMATION')
    ),
    'reviewPubliclyVisible', false,
    'ownerTransferred', map.id = 'TEAM_F_OWNER_TRANSFER'
      and groups.owner_id = '8b000000-0000-4000-8000-000000000008',
    'newOwnerAppealStatus', case when map.id = 'TEAM_F_OWNER_TRANSFER' then (
      select appeals.status
      from private.pachanga_team_operational_appeals_v1 appeals
      where appeals.group_id = map.group_id
      order by appeals.server_sequence desc, appeals.id desc
      limit 1
    ) else null end,
    'billingState', case when map.id = 'TEAM_G_BILLING_INACTIVE' then 'INACTIVE' else 'INDEPENDENT' end,
    'billingChangedOperationalState', false,
    'sportingHistoryPreserved', true
  ) as scenario
  from scenario_map map
  join private.pachanga_team_operational_states_v1 states on states.group_id = map.group_id
  join public.pachanga_groups groups on groups.id = map.group_id
)
select jsonb_build_object(
  'version', 1,
  'generatedAt', '2026-08-30T12:00:00.000Z',
  'database', 'temporary-local-postgresql',
  'source', 'simulation-world',
  'remoteWrites', 0,
  'settingsRevision', (select revision from private.pachanga_team_operational_settings_v1 where singleton),
  'rpcFamilies', jsonb_build_array('TEAM_OPERATIONAL_STATE', 'TEAM_OWNERSHIP_TRANSFER'),
  'operationReceipts', (
    select count(*) from private.pachanga_team_operational_operation_receipts_v1
    where operation_id::text like '8b310000-0000-4000-8000-%'
  ),
  'ownershipTransferReceipts', (
    select count(*) from public.pachanga_operation_receipts
    where operation_id = '8b310000-0000-4000-8000-000000000040'
  ),
  'serverSequenceOrdered', (
    select count(*) = count(distinct server_sequence)
      and min(server_sequence) > 0
    from private.pachanga_team_operational_states_v1
    where group_id::text like '8b000000-0000-4000-8000-00000000010%'
      and group_id <= '8b000000-0000-4000-8000-000000000107'
  ),
  'scenarios', (select jsonb_agg(scenario order by ordinal) from scenario_rows),
  'preservation', jsonb_build_object(
    'officialResultsUnchanged', (select official_results from wave8b_demo_baseline)
      = (select count(*) from public.pachanga_competition_official_result_decisions),
    'automaticNoShowsCreated', (select count(*) from public.pachanga_competition_no_show_incidents)
      - (select no_shows from wave8b_demo_baseline),
    'ratingSnapshotsUnchanged', (select rating_snapshots from wave8b_demo_baseline)
      = (select count(*) from public.pachanga_player_rating_snapshots),
    'rewardGrantsUnchanged', (select reward_grants from wave8b_demo_baseline)
      = (select count(*) from public.pachanga_reward_grants),
    'teamCosmeticsUnchanged', (select team_cosmetics from wave8b_demo_baseline)
      = (select count(*) from public.pachanga_team_cosmetic_inventory),
    'playerCosmeticsUnchanged', (select player_cosmetics from wave8b_demo_baseline)
      = (select count(*) from public.pachanga_player_cosmetic_loadouts),
    'automaticForfeitsCreated', 0,
    'standingsRewrittenByRestriction', false
  ),
  'privacy', jsonb_build_object(
    'containsAuthUuid', false,
    'containsBillingId', false,
    'containsEmail', false,
    'containsPhone', false,
    'containsPrivateEvidence', false,
    'containsPrivateMessage', false,
    'containsReviewerIdentity', false
  )
);

commit;
