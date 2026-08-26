\set ON_ERROR_STOP on

create or replace function pg_temp.wave5_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then
    raise exception 'WAVE5_ASSERT:%', message;
  end if;
end;
$$;

create or replace function pg_temp.wave5_actor(actor_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'authenticated', 'sub', actor_id)::text,
    false
  );
end;
$$;

create or replace function pg_temp.wave5_command(
  actor_id uuid,
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.wave5_actor(actor_id);
  return public.command_pachanga_competition_configuration_v1(
    operation_id,
    aggregate_id,
    expected_revision,
    command_action,
    command_payload,
    '{"clientVersion":"5.1.0+wave5-db","serviceWorkerVersion":"sw-wave5-db","installedMode":"standalone","surface":"wave5_db"}'
  );
end;
$$;

create or replace function pg_temp.wave5_expect_command_error(
  actor_id uuid,
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb,
  expected_error text
)
returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    perform pg_temp.wave5_command(
      actor_id, operation_id, aggregate_id, expected_revision,
      command_action, command_payload
    );
  exception when others then
    caught := true;
    if sqlerrm !~ expected_error then
      raise exception 'WAVE5_WRONG_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then
    raise exception 'WAVE5_EXPECTED_ERROR_NOT_RAISED:%', expected_error;
  end if;
end;
$$;

create or replace function pg_temp.wave5_expect_sql_error(statement text, expected_error text)
returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    execute statement;
  exception when others then
    caught := true;
    if sqlerrm !~ expected_error then
      raise exception 'WAVE5_WRONG_SQL_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then
    raise exception 'WAVE5_EXPECTED_SQL_ERROR_NOT_RAISED:%', expected_error;
  end if;
end;
$$;

create or replace function pg_temp.wave5_table_digest(target regclass)
returns text language plpgsql as $$
declare digest_value text;
begin
  execute format(
    'select md5(coalesce(string_agg(to_jsonb(source)::text, ''|'' order by to_jsonb(source)::text), '''')) from %s source',
    target
  ) into digest_value;
  return digest_value;
end;
$$;

create temporary table wave5_responses(key text primary key, value jsonb not null);
create temporary table wave5_invariants(key text primary key, digest text not null);

insert into wave5_invariants values
  ('rating', pg_temp.wave5_table_digest('public.pachanga_player_rating_snapshots')),
  ('rewards', pg_temp.wave5_table_digest('public.pachanga_reward_grants')),
  ('conduct', pg_temp.wave5_table_digest('private.pachanga_conduct_reports')),
  ('billing', pg_temp.wave5_table_digest('public.pachanga_stripe_webhook_events'));

select pg_temp.wave5_assert(
  (select count(*) = 4
   from jsonb_array_elements(public.get_pachanga_competition_authoring_presets_v1() -> 'presets')),
  'exactly four authoring presets must be available'
);
select pg_temp.wave5_assert(
  (select array_agg(preset ->> 'key' order by preset ->> 'key') = array[
    'LEAGUE_F11','LEAGUE_F5_QUICK','LEAGUE_F7_STANDARD','LEAGUE_FUTSAL'
  ] from jsonb_array_elements(
    public.get_pachanga_competition_authoring_presets_v1() -> 'presets'
  ) preset),
  'preset keys must remain stable'
);
select pg_temp.wave5_assert(
  (select wizard_version = 2 and status = 'completed'
     and completed_steps = array[1,2,3,4,5,6,7,8,9,10,11,12]::smallint[]
   from private.pachanga_league_private_beta_wizards w
   join wave5_state state on state.wizard_id = w.id),
  'League Wizard V2 must finalize all twelve steps'
);
select pg_temp.wave5_assert(
  (select rule_document #>> '{identity,configurationSchema}' = 'competition-configuration.v1'
     and jsonb_array_length(rule_document #> '{discipline,policy,cardTypeCatalog}') = 2
     and rule_document #>> '{operations,refereePolicy,role}' = 'MAIN_REFEREE'
   from public.pachanga_competition_rule_revisions revisions
   join wave5_state state on state.source_rule_revision_id = revisions.id),
  'wizard finalization must materialize one canonical RuleRevision'
);
select pg_temp.wave5_assert(
  (select count(*) = 1
   from public.pachanga_competition_discipline_rule_catalogs catalogs
   join wave5_state state on state.source_rule_revision_id = catalogs.rule_revision_id),
  'R5 catalog must derive from the wizard RuleRevision'
);

do $$
declare response jsonb;
declare competition_id uuid;
declare competition_revision bigint;
begin
  select state.competition_id, competitions.revision
  into competition_id, competition_revision
  from wave5_state state
  join public.pachanga_competitions competitions on competitions.id = state.competition_id;

  perform pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000001');
  response := public.get_pachanga_competition_configuration_v1(competition_id);
  perform pg_temp.wave5_assert(
    (response #>> '{capabilities,edit}')::boolean,
    'competition owner must edit configuration'
  );

  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000001',
    competition_id,
    competition_revision,
    'draft.create',
    '{"authoringMode":"ADVANCED","presetKey":"LEAGUE_F11","reason":"Wave 5A advanced configuration"}'
  );
  insert into wave5_responses values ('draft_create', response);
  update wave5_state set draft_id = (response #>> '{snapshot,id}')::uuid;

  perform pg_temp.wave5_assert(
    response = pg_temp.wave5_command(
      '5a010000-0000-4000-8000-000000000001',
      '5a040000-0000-4000-8000-000000000001',
      competition_id,
      competition_revision,
      'draft.create',
      '{"authoringMode":"ADVANCED","presetKey":"LEAGUE_F11","reason":"Wave 5A advanced configuration"}'
    ),
    'idempotent create replay must return the original receipt'
  );
end;
$$;

select pg_temp.wave5_expect_command_error(
  '5a010000-0000-4000-8000-000000000001',
  '5a040000-0000-4000-8000-000000000001',
  (select competition_id from wave5_state),
  1,
  'draft.create',
  '{"authoringMode":"SIMPLE","presetKey":"LEAGUE_F5_QUICK"}',
  'IDEMPOTENCY_KEY_REUSED'
);
select pg_temp.wave5_expect_command_error(
  '5a010000-0000-4000-8000-000000000004',
  '5a040000-0000-4000-8000-000000000002',
  (select competition_id from wave5_state),
  1,
  'draft.create',
  '{"authoringMode":"SIMPLE"}',
  'COMPETITION_RULES_MANAGER_REQUIRED'
);

select pg_temp.wave5_expect_command_error(
  '5a010000-0000-4000-8000-000000000001',
  '5a040000-0000-4000-8000-000000000003',
  (select draft_id from wave5_state),
  1,
  'draft.section.save',
  jsonb_build_object(
    'step', 10,
    'data', jsonb_set(
      private.pachanga_competition_authoring_preset_v1('LEAGUE_F11') #> '{steps,10}',
      '{yellow,threshold}', '0'::jsonb, true
    )
  ),
  'DISCIPLINE_ACCUMULATION_THRESHOLD_INVALID'
);

select pg_temp.wave5_expect_command_error(
  '5a010000-0000-4000-8000-000000000001',
  '5a040000-0000-4000-8000-000000000004',
  (select draft_id from wave5_state),
  99,
  'draft.mode.set',
  '{"mode":"SIMPLE","reason":"Reject stale configuration edit"}',
  'STALE_REVISION'
);

do $$
declare response jsonb;
declare current_revision bigint := 1;
declare discipline jsonb;
declare referee jsonb;
declare visibility jsonb;
declare draft_id uuid := (select state.draft_id from wave5_state state);
begin
  discipline := private.pachanga_competition_authoring_preset_v1('LEAGUE_F11') #> '{steps,10}';
  discipline := jsonb_set(discipline, '{yellow,threshold}', '4'::jsonb, true);
  discipline := jsonb_set(discipline, '{blue,enabled}', 'true'::jsonb, true);
  discipline := jsonb_set(discipline, '{blue,durationMinutes}', '7'::jsonb, true);
  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000010',
    draft_id, current_revision, 'draft.section.save',
    jsonb_build_object('step', 10, 'data', discipline, 'reason', 'Custom discipline')
  );
  current_revision := (response ->> 'confirmedRevision')::bigint;

  referee := private.pachanga_competition_authoring_preset_v1('LEAGUE_F11') #> '{steps,11}';
  referee := jsonb_set(referee, '{fee,mode}', '"FIXED"'::jsonb, true);
  referee := jsonb_set(referee, '{fee,fixedCents}', '6500'::jsonb, true);
  referee := jsonb_set(referee, '{fee,publicConsent}', 'false'::jsonb, true);
  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000011',
    draft_id, current_revision, 'draft.section.save',
    jsonb_build_object('step', 11, 'data', referee, 'reason', 'Private fixed referee fee')
  );
  current_revision := (response ->> 'confirmedRevision')::bigint;

  visibility := private.pachanga_competition_authoring_preset_v1('LEAGUE_F11') #> '{steps,12}';
  visibility := visibility || '{"consent":true,"acknowledgeUnavailableFeatures":true,"paymentsAcknowledged":true,"tournamentsAcknowledged":true}'::jsonb;
  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000012',
    draft_id, current_revision, 'draft.section.save',
    jsonb_build_object('step', 12, 'data', visibility, 'reason', 'Publication consent')
  );
  current_revision := (response ->> 'confirmedRevision')::bigint;

  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000013',
    draft_id, current_revision, 'draft.validate',
    '{"effectiveScope":"FUTURE_ONLY","reason":"Validate advanced policy"}'
  );
  insert into wave5_responses values ('validate_advanced', response);
  current_revision := (response ->> 'confirmedRevision')::bigint;

  perform pg_temp.wave5_assert(
    (response #>> '{snapshot,health,complete}')::boolean
      and response #>> '{snapshot,impact,freezePoint}' = 'DRAFT',
    'advanced draft must validate with DRAFT impact'
  );

  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000014',
    draft_id, current_revision, 'draft.publish',
    '{"confirmImpact":true,"confirmRuleSummary":true,"reason":"Publish advanced RuleRevision"}'
  );
  insert into wave5_responses values ('publish_advanced', response);
  update wave5_state set
    published_rule_revision_id = (response #>> '{snapshot,ruleRevision,ruleRevisionId}')::uuid;
end;
$$;

select pg_temp.wave5_assert(
  (select revisions.version = 2
     and revisions.supersedes_revision_id = state.source_rule_revision_id
     and revisions.rule_document #>> '{discipline,policy,cardTypeCatalog,2,code}' = 'BLUE'
     and (revisions.rule_document #>> '{operations,refereePolicy,fee,fixedCents}')::integer = 6500
   from wave5_state state
   join public.pachanga_competition_rule_revisions revisions
     on revisions.id = state.published_rule_revision_id),
  'publication must append an immutable advanced RuleRevision'
);
select pg_temp.wave5_assert(
  (select editions.rule_revision_id = state.published_rule_revision_id
   from wave5_state state
   join public.pachanga_competition_editions editions on editions.id = state.edition_id),
  'DRAFT publication must bind the new RuleRevision to the current edition'
);
select pg_temp.wave5_assert(
  (select bool_and(categories.rule_revision_id = state.published_rule_revision_id)
   from wave5_state state
   join public.pachanga_competition_categories categories on categories.edition_id = state.edition_id
   where categories.status <> 'cancelled'),
  'DRAFT publication must keep categories aligned with the current RuleRevision'
);
select pg_temp.wave5_assert(
  (select catalogs.card_type_catalog @> '[{"code":"BLUE"}]'::jsonb
   from wave5_state state
   join public.pachanga_competition_discipline_rule_catalogs catalogs
     on catalogs.rule_revision_id = state.published_rule_revision_id),
  'R5 catalog must consume BLUE from the published RuleRevision'
);
select pg_temp.wave5_assert(
  (select private.pachanga_competition_referee_policy_v1(state.published_rule_revision_id)
     #>> '{fee,fixedCents}' = '6500'
   from wave5_state state),
  'Referee Assignments must consume the published referee policy'
);
select pg_temp.wave5_assert(
  (select document ->> 'hash' = revisions.checksum
   from wave5_state state
   join public.pachanga_competition_rule_revisions revisions
     on revisions.id = state.published_rule_revision_id
   cross join lateral private.pachanga_competition_configuration_human_document_v1(revisions.id) document),
  'human regulation hash must match the canonical RuleRevision'
);

do $$
declare response jsonb;
declare competition_id uuid := (select state.competition_id from wave5_state state);
begin
  perform pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000003');
  response := public.get_pachanga_competition_configuration_v1(competition_id);
  perform pg_temp.wave5_assert(
    not (response #>> '{capabilities,edit}')::boolean,
    'viewer must remain read-only'
  );
  perform pg_temp.wave5_assert(
    not coalesce(
      response #> '{currentRuleRevision,document,sections,referees,fee}' ? 'fixedCents',
      false
    ),
    'private fixed referee fee must not leak through the human document'
  );

  perform pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000004');
  begin
    perform public.get_pachanga_competition_configuration_v1(competition_id);
    raise exception 'WAVE5_EXPECTED_OUTSIDER_READ_DENIAL';
  exception when others then
    if sqlerrm = 'WAVE5_EXPECTED_OUTSIDER_READ_DENIAL' then raise; end if;
    if sqlerrm !~ 'COMPETITION_NOT_FOUND' then raise; end if;
  end;
end;
$$;

do $$
declare response jsonb;
declare edition_id uuid := (select state.edition_id from wave5_state state);
declare edition_revision bigint;
declare rule_revision_id uuid := (select state.published_rule_revision_id from wave5_state state);
begin
  select editions.revision into edition_revision
  from public.pachanga_competition_editions editions where editions.id = edition_id;
  perform pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000001');
  response := public.command_pachanga_league_participation_v1(
    '5a040000-0000-4000-8000-000000000020',
    edition_id,
    edition_revision,
    'registration.open',
    jsonb_build_object(
      'registrationMode', 'INVITE_ONLY',
      'ruleRevisionId', rule_revision_id,
      'closesAt', '2027-02-28T23:59:59Z',
      'reason', 'Wave 5A freeze test'
    ),
    '{"clientVersion":"5.1.0+wave5-db","surface":"wave5_db"}'
  );
  perform pg_temp.wave5_assert(
    response #>> '{snapshot,status}' = 'registration_open',
    'registration.open must establish the REGISTRATION_OPEN freeze point'
  );
end;
$$;

do $$
declare response jsonb;
declare competition_id uuid := (select state.competition_id from wave5_state state);
declare competition_revision bigint;
declare draft_id uuid;
declare current_revision bigint;
declare scoring jsonb;
declare current_bound_revision uuid;
begin
  select competitions.revision into competition_revision
  from public.pachanga_competitions competitions where competitions.id = competition_id;
  select editions.rule_revision_id into current_bound_revision
  from public.pachanga_competition_editions editions
  join wave5_state state on state.edition_id = editions.id;

  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000030',
    competition_id, competition_revision, 'draft.clone',
    jsonb_build_object(
      'sourceRuleRevisionId', current_bound_revision,
      'authoringMode', 'ADVANCED',
      'reason', 'Clone current configuration for future scoring revision'
    )
  );
  draft_id := (response #>> '{snapshot,id}')::uuid;
  current_revision := (response ->> 'confirmedRevision')::bigint;

  scoring := response #> '{snapshot,steps,6}';
  scoring := jsonb_set(scoring, '{pointsForWin}', '2'::jsonb, true);
  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000031',
    draft_id, current_revision, 'draft.section.save',
    jsonb_build_object('step', 6, 'data', scoring, 'reason', 'Future scoring policy')
  );
  current_revision := (response ->> 'confirmedRevision')::bigint;
  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000032',
    draft_id, current_revision, 'draft.validate',
    '{"effectiveFrom":"2027-03-15T00:00:00Z","effectiveScope":"FUTURE_ONLY","reason":"Validate future policy"}'
  );
  current_revision := (response ->> 'confirmedRevision')::bigint;
  perform pg_temp.wave5_assert(
    response #>> '{snapshot,impact,freezePoint}' = 'REGISTRATION_OPEN',
    'impact analysis must report REGISTRATION_OPEN'
  );

  response := pg_temp.wave5_command(
    '5a010000-0000-4000-8000-000000000001',
    '5a040000-0000-4000-8000-000000000033',
    draft_id, current_revision, 'draft.publish',
    '{"confirmImpact":true,"confirmRuleSummary":true,"reason":"Publish future scoring revision"}'
  );
  perform pg_temp.wave5_assert(
    not (response #>> '{snapshot,appliedToCurrentEdition}')::boolean
      and (response #>> '{snapshot,currentEditionPreserved}')::boolean,
    'frozen current edition must never be rebound retroactively'
  );
  perform pg_temp.wave5_assert(
    (select editions.rule_revision_id = current_bound_revision
     from public.pachanga_competition_editions editions
     join wave5_state state on state.edition_id = editions.id),
    'registration-open edition must preserve its canonical RuleRevision'
  );
end;
$$;

select pg_temp.wave5_assert(
  (select count(*) = 3 and min(version) = 1 and max(version) = 3
   from public.pachanga_competition_rule_revisions revisions
   join wave5_state state on state.competition_id = (
     select sets.competition_id from public.pachanga_competition_rule_sets sets
     where sets.id = revisions.rule_set_id
   )),
  'published changes must append versions without destructive edits'
);

select pg_temp.wave5_assert(
  not has_function_privilege(
    'authenticated',
    'private.pachanga_competition_configuration_store_v1(uuid,uuid,text,uuid,uuid,uuid,uuid,bigint,bigint,text,text,jsonb,jsonb,jsonb,timestamptz)',
    'EXECUTE'
  ),
  'authenticated clients must not execute private storage helpers'
);

set role authenticated;
select pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000001');
select pg_temp.wave5_expect_sql_error(
  $$insert into private.pachanga_competition_configuration_drafts(
    competition_id, edition_id, rule_set_id, source_rule_revision_id, created_by, step_data
  ) select competition_id, edition_id, revisions.rule_set_id, source_rule_revision_id,
      '5a010000-0000-4000-8000-000000000001', '{}'::jsonb
    from wave5_state state
    join public.pachanga_competition_rule_revisions revisions
      on revisions.id = state.source_rule_revision_id$$,
  'permission denied'
);
select pg_temp.wave5_expect_sql_error(
  $$update public.pachanga_competition_rule_revisions
    set reason = 'client mutation' where id = (
      select source_rule_revision_id from wave5_state
    )$$,
  'permission denied|RULE_REVISION_IMMUTABLE'
);
reset role;

select pg_temp.wave5_expect_sql_error(
  $$update public.pachanga_competition_rule_revisions
    set reason = 'destructive server mutation' where id = (
      select source_rule_revision_id from wave5_state
    )$$,
  'RULE_REVISION_IMMUTABLE'
);

select pg_temp.wave5_assert(
  (select count(*) > 0 and bool_and(user_id = '5a010000-0000-4000-8000-000000000001')
   from public.pachanga_competition_configuration_invalidations invalidations
   where invalidations.user_id = '5a010000-0000-4000-8000-000000000001'),
  'owner invalidations must be scoped to the owner'
);
select pg_temp.wave5_assert(
  (select count(*) > 0
   from public.pachanga_competition_configuration_invalidations invalidations
   where invalidations.user_id = '5a010000-0000-4000-8000-000000000003'),
  'authorized viewer must receive invalidation-only Realtime events'
);

do $$
declare response jsonb;
declare replay jsonb;
declare current_revision bigint;
begin
  perform pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000002');
  select settings.revision into current_revision
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;

  begin
    perform public.command_pachanga_competition_configuration_platform_v1(
      '5a040000-0000-4000-8000-000000000039',
      null,
      current_revision,
      'configuration.flags.set',
      '{"configurationCenterEnabled":true,"reason":"Reject missing aggregate"}',
      '{"clientVersion":"5.1.0+wave5-db","surface":"wave5_db"}'
    );
    raise exception 'WAVE5_EXPECTED_NULL_AGGREGATE_DENIAL';
  exception when others then
    if sqlerrm = 'WAVE5_EXPECTED_NULL_AGGREGATE_DENIAL' then raise; end if;
    if sqlstate <> '22023' or sqlerrm !~ 'INVALID_COMPETITION_CONFIGURATION_PLATFORM_COMMAND' then
      raise;
    end if;
  end;

  response := public.command_pachanga_competition_configuration_platform_v1(
    '5a040000-0000-4000-8000-000000000040',
    '00000000-0000-0000-0000-00000000c5a1',
    current_revision,
    'configuration.flags.set',
    '{"configurationCenterEnabled":true,"wizardV2Enabled":true,"reason":"Wave 5A idempotent platform readback"}',
    '{"clientVersion":"5.1.0+wave5-db","surface":"wave5_db"}'
  );
  replay := public.command_pachanga_competition_configuration_platform_v1(
    '5a040000-0000-4000-8000-000000000040',
    '00000000-0000-0000-0000-00000000c5a1',
    current_revision,
    'configuration.flags.set',
    '{"configurationCenterEnabled":true,"wizardV2Enabled":true,"reason":"Wave 5A idempotent platform readback"}',
    '{"clientVersion":"5.1.0+wave5-db","surface":"wave5_db"}'
  );
  perform pg_temp.wave5_assert(response = replay, 'platform flag replay must return one receipt');
  perform pg_temp.wave5_assert(
    (select count(*) = 1
     from private.pachanga_competition_operation_receipts receipts
     where receipts.operation_id = '5a040000-0000-4000-8000-000000000040'),
    'platform flag replay must persist exactly one receipt'
  );

  perform pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000001');
  begin
    perform public.command_pachanga_competition_configuration_platform_v1(
      '5a040000-0000-4000-8000-000000000041',
      '00000000-0000-0000-0000-00000000c5a1',
      (response ->> 'confirmedRevision')::bigint,
      'configuration.kill_switch',
      '{"reason":"Unauthorized Wave 5A shutdown"}',
      '{"clientVersion":"5.1.0+wave5-db","surface":"wave5_db"}'
    );
    raise exception 'WAVE5_EXPECTED_PLATFORM_DENIAL';
  exception when others then
    if sqlerrm = 'WAVE5_EXPECTED_PLATFORM_DENIAL' then raise; end if;
    if sqlstate <> '42501' then raise; end if;
  end;

  perform pg_temp.wave5_actor('5a010000-0000-4000-8000-000000000002');
  response := public.command_pachanga_competition_configuration_platform_v1(
    '5a040000-0000-4000-8000-000000000042',
    '00000000-0000-0000-0000-00000000c5a1',
    (response ->> 'confirmedRevision')::bigint,
    'configuration.kill_switch',
    '{"reason":"Wave 5A end-of-test shutdown"}',
    '{"clientVersion":"5.1.0+wave5-db","surface":"wave5_db"}'
  );
  perform pg_temp.wave5_assert(
    not (response #>> '{snapshot,configurationCenterEnabled}')::boolean
      and not (response #>> '{snapshot,wizardV2Enabled}')::boolean,
    'versioned kill switch must disable only Wave 5A authoring flags'
  );
end;
$$;

select pg_temp.wave5_assert(
  (select digest = pg_temp.wave5_table_digest('public.pachanga_player_rating_snapshots')
   from wave5_invariants where key = 'rating'),
  'Rating V2 must remain byte-for-byte unchanged'
);
select pg_temp.wave5_assert(
  (select digest = pg_temp.wave5_table_digest('public.pachanga_reward_grants')
   from wave5_invariants where key = 'rewards'),
  'Rewards must remain byte-for-byte unchanged'
);
select pg_temp.wave5_assert(
  (select digest = pg_temp.wave5_table_digest('private.pachanga_conduct_reports')
   from wave5_invariants where key = 'conduct'),
  'Conduct must remain byte-for-byte unchanged'
);
select pg_temp.wave5_assert(
  (select digest = pg_temp.wave5_table_digest('public.pachanga_stripe_webhook_events')
   from wave5_invariants where key = 'billing'),
  'Billing must remain byte-for-byte unchanged'
);

select 'COMPETITION_CONFIGURATION_CENTER_V1_DB_OK' as result;
