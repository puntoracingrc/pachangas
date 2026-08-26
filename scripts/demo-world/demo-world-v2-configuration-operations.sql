\set ON_ERROR_STOP on

do $demo_configuration$
declare response jsonb;
declare target_competition_id uuid;
declare competition_revision bigint;
declare draft_id uuid;
declare draft_revision bigint;
declare step_data jsonb;
declare published_rule_revision_id uuid;
begin
  select competitions.id, competitions.revision
  into target_competition_id, competition_revision
  from public.pachanga_competitions competitions
  where competitions.name = 'Liga Wave 5A'
  order by competitions.server_sequence desc, competitions.id desc
  limit 1;
  if target_competition_id is null then
    raise exception 'DEMO_WORLD_V2_3_CONFIGURATION_COMPETITION_MISSING';
  end if;

  perform set_config(
    'request.jwt.claims',
    '{"sub":"5a010000-0000-4000-8000-000000000001","role":"authenticated"}',
    false
  );

  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-create')::uuid,
    target_competition_id,
    competition_revision,
    'draft.create',
    '{"authoringMode":"ADVANCED","reason":"Demo World V2.3 custom configuration"}',
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  draft_id := (response #>> '{snapshot,id}')::uuid;
  draft_revision := (response ->> 'confirmedRevision')::bigint;

  step_data := jsonb_set(response #> '{snapshot,steps,6}', '{pointsForWin}', '2'::jsonb, true);
  step_data := jsonb_set(step_data, '{matchDurationMinutes}', '80'::jsonb, true);
  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-scoring')::uuid,
    draft_id, draft_revision, 'draft.section.save',
    jsonb_build_object('step',6,'data',step_data,'reason','Custom scoring'),
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  draft_revision := (response ->> 'confirmedRevision')::bigint;

  step_data := response #> '{snapshot,steps,9}';
  step_data := jsonb_set(step_data, '{noShowWinnerScore}', '4'::jsonb, true);
  step_data := jsonb_set(step_data, '{postponementResponseDeadlineHours}', '36'::jsonb, true);
  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-incidents')::uuid,
    draft_id, draft_revision, 'draft.section.save',
    jsonb_build_object('step',9,'data',step_data,'reason','Custom no-show and deadlines'),
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  draft_revision := (response ->> 'confirmedRevision')::bigint;

  step_data := response #> '{snapshot,steps,10}';
  step_data := jsonb_set(step_data, '{yellow,threshold}', '4'::jsonb, true);
  step_data := jsonb_set(step_data, '{blue,enabled}', 'true'::jsonb, true);
  step_data := jsonb_set(step_data, '{blue,durationMinutes}', '7'::jsonb, true);
  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-discipline')::uuid,
    draft_id, draft_revision, 'draft.section.save',
    jsonb_build_object('step',10,'data',step_data,'reason','Custom R5 catalog'),
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  draft_revision := (response ->> 'confirmedRevision')::bigint;

  step_data := response #> '{snapshot,steps,11}';
  step_data := jsonb_set(step_data, '{usage}', '"REQUIRED"'::jsonb, true);
  step_data := jsonb_set(step_data, '{requiredBeforeReady}', 'true'::jsonb, true);
  step_data := jsonb_set(step_data, '{fee,mode}', '"FIXED"'::jsonb, true);
  step_data := jsonb_set(step_data, '{fee,fixedCents}', '6500'::jsonb, true);
  step_data := jsonb_set(step_data, '{fee,publicConsent}', 'false'::jsonb, true);
  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-referees')::uuid,
    draft_id, draft_revision, 'draft.section.save',
    jsonb_build_object('step',11,'data',step_data,'reason','Custom private referee policy'),
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  draft_revision := (response ->> 'confirmedRevision')::bigint;

  step_data := response #> '{snapshot,steps,12}';
  step_data := step_data || '{"consent":true,"acknowledgeUnavailableFeatures":true,"paymentsAcknowledged":true,"tournamentsAcknowledged":true}'::jsonb;
  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-visibility')::uuid,
    draft_id, draft_revision, 'draft.section.save',
    jsonb_build_object('step',12,'data',step_data,'reason','Private publication consent'),
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  draft_revision := (response ->> 'confirmedRevision')::bigint;

  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-validate')::uuid,
    draft_id, draft_revision, 'draft.validate',
    '{"effectiveScope":"FUTURE_ONLY","reason":"Validate Demo World V2.3 custom policy"}',
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  draft_revision := (response ->> 'confirmedRevision')::bigint;
  if not (response #>> '{snapshot,health,complete}')::boolean then
    raise exception 'DEMO_WORLD_V2_3_CONFIGURATION_HEALTH_INVALID';
  end if;

  response := public.command_pachanga_competition_configuration_v1(
    md5('demo-world-v2-3-configuration-publish')::uuid,
    draft_id, draft_revision, 'draft.publish',
    '{"confirmImpact":true,"confirmRuleSummary":true,"reason":"Publish Demo World V2.3 custom RuleRevision"}',
    '{"clientVersion":"demo-world-v2-3","serviceWorkerVersion":"demo-world-v2-3","installedMode":"simulation","surface":"demo_world_v2_configuration"}'
  );
  published_rule_revision_id := (response #>> '{snapshot,ruleRevision,ruleRevisionId}')::uuid;
  if published_rule_revision_id is null or not (response #>> '{snapshot,appliedToCurrentEdition}')::boolean then
    raise exception 'DEMO_WORLD_V2_3_CONFIGURATION_PUBLICATION_INVALID';
  end if;
  if (
    select count(*)
    from public.pachanga_competition_rule_revisions revisions
    join public.pachanga_competition_rule_sets sets on sets.id = revisions.rule_set_id
    where sets.competition_id = target_competition_id
  ) <> 2 then
    raise exception 'DEMO_WORLD_V2_3_RULE_REVISION_COUNT_INVALID';
  end if;
end;
$demo_configuration$;
