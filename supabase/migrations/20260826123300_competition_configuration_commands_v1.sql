-- Pachangas IQ Wave 5A: server-authoritative Competition Configuration Center.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_configuration_can_edit_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select coalesce(
    private.pachanga_competition_can_v1(target_competition_id, target_actor_id, 'rules'),
    false
  ) or coalesce(
    private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id)
      in ('competition_admin','competition_director','competition_owner','rules_manager','platform_admin','platform_owner','service_authority'),
    false
  );
$$;

revoke all on function private.pachanga_competition_configuration_can_edit_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_freeze_point_v1(
  target_competition_id uuid,
  target_edition_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare edition_status text;
begin
  if exists (
    select 1 from public.pachanga_competition_match_contexts contexts
    where contexts.competition_id = target_competition_id and contexts.status = 'official'
  ) then return 'FIRST_OFFICIAL_RESULT'; end if;
  if exists (
    select 1
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    join public.pachanga_competition_schedule_revisions revisions on revisions.id = rounds.schedule_revision_id
    join public.pachanga_competition_schedule_plans plans on plans.id = revisions.schedule_plan_id
    where plans.competition_id = target_competition_id and items.status = 'published'
  ) then return 'SCHEDULE_PUBLISHED'; end if;
  select editions.status into edition_status
  from public.pachanga_competition_editions editions
  where editions.id = target_edition_id and editions.competition_id = target_competition_id;
  if edition_status in ('registration_closed','scheduled','active','completed','archived') then
    return 'REGISTRATION_CLOSED';
  elsif edition_status = 'registration_open' then return 'REGISTRATION_OPEN';
  end if;
  return 'DRAFT';
end;
$$;

revoke all on function private.pachanga_competition_configuration_freeze_point_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_lock_v1(
  target_competition_id uuid
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  if target_competition_id is null then
    raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(target_competition_id::text, 91411));
end;
$$;

revoke all on function private.pachanga_competition_configuration_lock_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_engine_guard_v1(
  target_competition_id uuid,
  target_sections text[],
  target_action text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_competition_configuration_lock_v1(target_competition_id);
  if exists (
    select 1
    from private.pachanga_competition_configuration_drafts drafts
    where drafts.competition_id = target_competition_id
      and drafts.status in ('draft','validated')
      and drafts.changed_sections && coalesce(target_sections, '{}'::text[])
  ) then
    raise exception 'COMPETITION_CONFIGURATION_IN_PROGRESS:%', target_action
      using errcode = 'PT409';
  end if;
end;
$$;

revoke all on function private.pachanga_competition_configuration_engine_guard_v1(uuid, text[], text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_impact_v1(
  target_competition_id uuid,
  target_edition_id uuid,
  target_source_revision_id uuid,
  target_proposed_document jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare source_document jsonb;
declare selected_diff jsonb;
declare future_matches bigint;
declare player_count bigint;
declare counter_count bigint;
declare sanction_count bigint;
declare assignment_count bigint;
declare result_count bigint;
declare standing_count bigint;
begin
  select revisions.rule_document into source_document
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id = target_source_revision_id;
  if source_document is null then raise exception 'RULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
  selected_diff := private.pachanga_competition_configuration_diff_v1(
    source_document, target_proposed_document
  );
  select count(*) into future_matches
  from public.pachanga_competition_match_contexts contexts
  where contexts.competition_id = target_competition_id
    and contexts.status not in ('official','cancelled','retired');
  select count(distinct members.player_profile_id) into player_count
  from public.pachanga_competition_roster_members members
  join public.pachanga_competition_rosters rosters on rosters.id = members.roster_id
  join public.pachanga_competition_entries entries on entries.id = rosters.entry_id
  where entries.competition_id = target_competition_id;
  select count(*) into counter_count
  from public.pachanga_competition_disciplinary_counters counters
  where counters.competition_id = target_competition_id;
  select count(*) into sanction_count
  from public.pachanga_competition_sanctions sanctions
  where sanctions.competition_id = target_competition_id
    and sanctions.status in ('active','provisional','under_review');
  select count(*) into assignment_count
  from public.pachanga_referee_assignments assignments
  where assignments.competition_id = target_competition_id
    and assignments.status in ('proposed','accepted','confirmed');
  select count(*) into result_count
  from public.pachanga_competition_sporting_results results
  join public.pachanga_competition_match_contexts contexts
    on contexts.id = results.competition_match_context_id
  where contexts.competition_id = target_competition_id;
  select count(*) into standing_count
  from public.pachanga_competition_standing_snapshots snapshots
  where snapshots.competition_id = target_competition_id;
  return jsonb_build_object(
    'freezePoint', private.pachanga_competition_configuration_freeze_point_v1(
      target_competition_id, target_edition_id
    ),
    'futureMatches', future_matches,
    'players', player_count,
    'disciplinaryCounters', counter_count,
    'activeSanctions', sanction_count,
    'refereeAssignments', assignment_count,
    'sportingResults', result_count,
    'standingSnapshots', standing_count,
    'differences', selected_diff,
    'retroactiveApplication', false,
    'requiresExplicitRebind', private.pachanga_competition_configuration_freeze_point_v1(
      target_competition_id, target_edition_id
    ) <> 'DRAFT'
  );
end;
$$;

revoke all on function private.pachanga_competition_configuration_impact_v1(uuid, uuid, uuid, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_steps_from_rule_v1(
  target_competition_id uuid,
  target_edition_id uuid,
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare competition public.pachanga_competitions%rowtype;
declare edition public.pachanga_competition_editions%rowtype;
declare document jsonb;
declare modality_key text;
declare preset_key text;
declare steps jsonb;
declare discipline_policy jsonb;
declare yellow jsonb;
declare red jsonb;
declare blue jsonb;
declare referee jsonb;
begin
  select * into competition from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into edition from public.pachanga_competition_editions editions
  where editions.id = target_edition_id and editions.competition_id = target_competition_id;
  if not found then raise exception 'COMPETITION_EDITION_NOT_FOUND' using errcode = 'P0002'; end if;
  select revisions.rule_document into document
  from public.pachanga_competition_rule_revisions revisions
  join public.pachanga_competition_rule_sets sets on sets.id = revisions.rule_set_id
  where revisions.id = target_rule_revision_id and sets.competition_id = target_competition_id;
  if document is null then raise exception 'RULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
  modality_key := case document #>> '{format,modality}'
    when 'futbol5' then 'FUTBOL_5' when 'futbol7' then 'FUTBOL_7'
    when 'futbol11' then 'FUTBOL_11' when 'futbol_sala' then 'FUTSAL'
    else 'FUTBOL_7' end;
  preset_key := case modality_key
    when 'FUTBOL_5' then 'LEAGUE_F5_QUICK'
    when 'FUTBOL_11' then 'LEAGUE_F11'
    when 'FUTSAL' then 'LEAGUE_FUTSAL'
    else 'LEAGUE_F7_STANDARD' end;
  steps := private.pachanga_competition_authoring_preset_v1(preset_key) -> 'steps';
  steps := jsonb_set(steps, '{1}', jsonb_strip_nulls(jsonb_build_object(
    'name', competition.name, 'slug', competition.slug,
    'description', competition.description, 'generalArea', competition.general_area,
    'imageUrl', competition.image_url, 'privacy', 'PRIVATE',
    'organizerType', competition.organizer_kind
  )), true);
  steps := jsonb_set(steps, '{2}', jsonb_build_object(
    'modality', modality_key,
    'playersPerTeam', document #>> '{registration,matchSheetPolicy,starterMax}'
  ), true);
  steps := jsonb_set(steps, '{3}', jsonb_build_object(
    'editionName', edition.name, 'seasonLabel', edition.season_label,
    'startsAt', edition.starts_at, 'endsAt', edition.ends_at,
    'timezone', coalesce(document #>> '{operations,schedulePolicy,timezone}', 'Europe/Madrid')
  ), true);
  steps := jsonb_set(steps, '{4}', (steps -> '4') || jsonb_strip_nulls(jsonb_build_object(
    'teamCap', (document #>> '{registration,registrationPolicy,teamLimits,maximum}')::integer,
    'legs', (document #>> '{operations,schedulePolicy,legs}')::integer,
    'registrationMode', document #>> '{registration,registrationPolicy,mode}',
    'registrationClosesAt', edition.registration_closes_at,
    'pairingMode', 'AUTOMATIC_ROUND_ROBIN'
  )), true);
  steps := jsonb_set(steps, '{5}', jsonb_build_object(
    'minimumRosterSize', (document #>> '{registration,rosterPolicy,minimumSize}')::integer,
    'maximumRosterSize', (document #>> '{registration,rosterPolicy,maximumSize}')::integer,
    'credentialRequired', coalesce((document #>> '{registration,identityRequirements,credentialRequired}')::boolean, true),
    'jerseyRequired', coalesce((document #>> '{registration,kitPolicy,jerseyRequired}')::boolean, true),
    'closeRequiresApprovedRosters', coalesce((document #>> '{registration,rosterPolicy,closeRequiresApprovedRosters}')::boolean, true)
  ), true);
  steps := jsonb_set(steps, '{6}', (steps -> '6') || jsonb_strip_nulls(jsonb_build_object(
    'matchDurationMinutes', (document #>> '{operations,schedulePolicy,matchDurationMinutes}')::integer,
    'requiredBufferMinutes', (document #>> '{operations,schedulePolicy,requiredBufferMinutes}')::integer,
    'pointsForWin', (document #>> '{results,scoringPolicy,pointsForWin}')::integer,
    'pointsForDraw', (document #>> '{results,scoringPolicy,pointsForDraw}')::integer,
    'pointsForLoss', (document #>> '{results,scoringPolicy,pointsForLoss}')::integer,
    'responseDeadlineHours', (document #>> '{results,confirmationPolicy,responseDeadlineHours}')::integer,
    'autoOfficialAfterConfirmation', (document #>> '{results,confirmationPolicy,autoOfficialAfterConfirmation}')::boolean,
    'confirmationMode', document #>> '{results,confirmationPolicy,mode}'
  )), true);
  steps := jsonb_set(steps, '{7}', (steps -> '7') || jsonb_strip_nulls(jsonb_build_object(
    'weeklyPattern', document #> '{operations,schedulePolicy,weeklyPattern}',
    'venueRequired', (document #>> '{operations,schedulePolicy,venueRequired}')::boolean,
    'allowTbd', (document #>> '{operations,exceptionPolicy,venuePolicy,allowTbd}')::boolean,
    'minimumRestMinutes', (document #>> '{operations,schedulePolicy,minimumRestMinutes}')::integer,
    'useDivision', true
  )), true);
  steps := jsonb_set(steps, '{8}', jsonb_build_object(
    'tieBreakCriteria', document #> '{results,tieBreakCriteria}',
    'scorerDetailPolicy', document #>> '{results,scorerDetailPolicy}',
    'allowUnknownScorer', coalesce((document #>> '{results,allowUnknownScorer}')::boolean, false),
    'allowSharedPositions', coalesce((document #>> '{results,standingsPolicy,allowSharedPositions}')::boolean, true)
  ), true);
  steps := jsonb_set(steps, '{9}', (steps -> '9') || jsonb_strip_nulls(jsonb_build_object(
    'postponementResponseDeadlineHours', (document #>> '{operations,exceptionPolicy,postponementResponseDeadlineHours}')::integer,
    'postponementDeadlinePolicy', document #>> '{operations,exceptionPolicy,postponementDeadlinePolicy}',
    'gracePeriodMinutes', (document #>> '{operations,exceptionPolicy,gracePeriodMinutes}')::integer,
    'minimumRestHours', (document #>> '{operations,exceptionPolicy,minimumRestHours}')::integer,
    'maximumMatchDurationMinutes', (document #>> '{operations,exceptionPolicy,maximumMatchDurationMinutes}')::integer,
    'noShowOutcome', document #>> '{operations,exceptionPolicy,noShowOutcome}',
    'noShowWinnerScore', (document #>> '{operations,exceptionPolicy,noShowWinnerScore}')::integer,
    'noShowLoserScore', (document #>> '{operations,exceptionPolicy,noShowLoserScore}')::integer
  )), true);
  discipline_policy := coalesce(document #> '{discipline,policy}', '{}'::jsonb);
  select value into yellow from jsonb_array_elements(coalesce(discipline_policy -> 'cardTypeCatalog','[]'::jsonb))
    where value ->> 'code' = 'YELLOW' limit 1;
  select value into red from jsonb_array_elements(coalesce(discipline_policy -> 'cardTypeCatalog','[]'::jsonb))
    where value ->> 'code' = 'RED' limit 1;
  select value into blue from jsonb_array_elements(coalesce(discipline_policy -> 'cardTypeCatalog','[]'::jsonb))
    where value ->> 'code' = 'BLUE' limit 1;
  if discipline_policy <> '{}'::jsonb then
    steps := jsonb_set(steps, '{10}', jsonb_build_object(
      'enabled', coalesce((document #>> '{discipline,enabled}')::boolean, false),
      'yellow', jsonb_build_object(
        'enabled', yellow is not null,
        'accumulationEnabled', coalesce((yellow #>> '{accumulation,enabled}')::boolean, false),
        'points', coalesce((yellow #>> '{accumulation,points}')::integer, 0),
        'threshold', coalesce((yellow #>> '{accumulation,threshold}')::integer, 0),
        'outcome', coalesce(yellow #>> '{accumulation,outcome}', 'NO_SANCTION'),
        'unitType', coalesce(yellow #>> '{accumulation,unitType}', 'MATCHES'),
        'units', coalesce((yellow #>> '{accumulation,units}')::integer, 0)
      ),
      'secondYellow', coalesce(document #> '{discipline,secondYellowPolicy}',
        jsonb_build_object('enabled', yellow #>> '{dismissal,mode}' = 'SECOND_CARD',
          'dismissal', true, 'preserveYellowFacts', true,
          'countsForAccumulation', true,
          'outcome', coalesce(yellow #>> '{dismissal,outcome}','NO_SANCTION'),
          'unitType', coalesce(yellow #>> '{dismissal,unitType}','MATCHES'),
          'units', coalesce((yellow #>> '{dismissal,units}')::integer,0))),
      'red', jsonb_build_object(
        'enabled', red is not null, 'outcome', coalesce(red #>> '{dismissal,outcome}','NO_SANCTION'),
        'unitType', coalesce(red #>> '{dismissal,unitType}','MATCHES'),
        'units', coalesce((red #>> '{dismissal,units}')::integer,0),
        'provisionalUnits', coalesce((red #>> '{dismissal,provisionalUnits}')::integer,0),
        'minimumUnits', coalesce((red #>> '{dismissal,minimumUnits}')::integer,0),
        'maximumUnits', coalesce((red #>> '{dismissal,maximumUnits}')::integer,0),
        'committeeRequired', coalesce(red #>> '{dismissal,outcome}','') in ('COMMITTEE_REQUIRED','SANCTION_RANGE')
      ),
      'blue', jsonb_build_object(
        'enabled', blue is not null,
        'mode', case blue #>> '{temporaryDismissal,mode}' when 'MINUTES' then 'MINUTES'
          when 'OPPONENT_GOAL' then 'UNTIL_OPPONENT_GOAL' when 'BOTH' then 'MINUTES_AND_GOAL'
          else 'MINUTES_OR_GOAL' end,
        'durationMinutes', coalesce((blue #>> '{temporaryDismissal,durationMinutes}')::integer,5),
        'replacementPolicy', coalesce(blue #>> '{temporaryDismissal,replacementPolicy}','NO_REPLACEMENT'),
        'postMatchOutcome', coalesce(blue #>> '{dismissal,outcome}','NO_SANCTION')
      ),
      'cycle', discipline_policy -> 'cyclePolicy',
      'sanction', discipline_policy -> 'sanctionPolicy',
      'appeal', discipline_policy -> 'appealPolicy'
    ), true);
  else
    steps := jsonb_set(steps, '{10}', (steps -> '10') || jsonb_build_object('enabled',false), true);
  end if;
  referee := coalesce(document #> '{operations,refereePolicy}', '{}'::jsonb);
  if referee <> '{}'::jsonb then steps := jsonb_set(steps, '{11}', referee, true); end if;
  steps := jsonb_set(steps, '{12}', (steps -> '12') || jsonb_build_object(
    'competitionVisibility','PRIVATE','calendarVisibility','PARTICIPANTS_ONLY',
    'standingsVisibility','PARTICIPANTS_ONLY','disciplineVisibility','PRIVATE',
    'incidentVisibility','PRIVATE','consent',false,
    'acknowledgeUnavailableFeatures',false,'paymentsAcknowledged',false,
    'tournamentsAcknowledged',false
  ), true);
  return steps;
end;
$$;

revoke all on function private.pachanga_competition_configuration_steps_from_rule_v1(uuid, uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_draft_snapshot_v1(
  target_draft_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare draft private.pachanga_competition_configuration_drafts%rowtype;
declare source_document jsonb;
declare proposed_document jsonb;
begin
  select * into draft from private.pachanga_competition_configuration_drafts drafts
  where drafts.id = target_draft_id;
  if not found then return null; end if;
  select revisions.rule_document into source_document
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id = draft.source_rule_revision_id;
  proposed_document := private.pachanga_competition_configuration_rule_document_v1(
    draft.step_data, draft.authoring_mode, draft.preset_key
  );
  return jsonb_build_object(
    'id',draft.id,'competitionId',draft.competition_id,'editionId',draft.edition_id,
    'ruleSetId',draft.rule_set_id,'sourceRuleRevisionId',draft.source_rule_revision_id,
    'materializedRuleRevisionId',draft.materialized_rule_revision_id,
    'status',draft.status,'authoringMode',draft.authoring_mode,'presetKey',draft.preset_key,
    'currentStep',draft.current_step,'completedSteps',to_jsonb(draft.completed_steps),
    'steps',draft.step_data,'changedSections',to_jsonb(draft.changed_sections),
    'health',private.pachanga_competition_configuration_health_v1(draft.step_data,draft.completed_steps),
    'summary',private.pachanga_competition_configuration_summary_v1(proposed_document),
    'comparison',private.pachanga_competition_configuration_diff_v1(source_document,proposed_document),
    'impact',private.pachanga_competition_configuration_impact_v1(
      draft.competition_id,draft.edition_id,draft.source_rule_revision_id,proposed_document
    ),
    'effectiveFrom',draft.effective_from,'effectiveScope',draft.effective_scope,
    'revision',draft.revision,'serverSequence',draft.server_sequence,
    'updatedAt',draft.updated_at
  );
end;
$$;

revoke all on function private.pachanga_competition_configuration_draft_snapshot_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_competition_configuration_receipts%rowtype;
begin
  select * into receipt from private.pachanga_competition_configuration_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id is distinct from target_actor_id or receipt.action <> target_action
     or receipt.aggregate_id <> target_aggregate_id or receipt.request_hash <> target_request_hash then
    raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

revoke all on function private.pachanga_competition_configuration_replay_v1(uuid, uuid, text, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_store_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_draft_id uuid,
  target_rule_revision_id uuid,
  target_revision bigint,
  target_server_sequence bigint,
  target_reason text,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_confirmed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare response jsonb;
declare target_user uuid;
begin
  response := jsonb_build_object(
    'operationId',target_operation_id,'confirmedRevision',target_revision,
    'confirmedAt',target_confirmed_at,'serverSequence',target_server_sequence,
    'snapshot',target_snapshot,
    'invalidations',jsonb_build_array(jsonb_build_object(
      'entityType','competition_configuration','entityId',coalesce(target_draft_id,target_competition_id),
      'revision',target_revision
    ))
  );
  insert into private.pachanga_competition_configuration_events(
    operation_id,actor_id,competition_id,draft_id,rule_revision_id,action,
    aggregate_revision,server_sequence,reason_code,event_payload,confirmed_at
  ) values (
    target_operation_id,target_actor_id,target_competition_id,target_draft_id,
    target_rule_revision_id,target_action,target_revision,target_server_sequence,
    left(coalesce(nullif(trim(target_reason),''),target_action),120),
    coalesce(target_event_payload,'{}'::jsonb),target_confirmed_at
  );
  for target_user in
    select distinct users.user_id from (
      select competitions.created_by as user_id
      from public.pachanga_competitions competitions where competitions.id = target_competition_id
      union all
      select staff.user_id from public.pachanga_competition_staff_assignments staff
      where staff.competition_id = target_competition_id and staff.status = 'active'
      union all
      select groups.owner_id from public.pachanga_competition_entries entries
      join public.pachanga_groups groups on groups.id = entries.team_id
      where entries.competition_id = target_competition_id
      union all
      select delegates.user_id from public.pachanga_competition_team_delegates delegates
      join public.pachanga_competition_entries entries on entries.id = delegates.entry_id
      where entries.competition_id = target_competition_id and delegates.status = 'active'
    ) users where users.user_id is not null
  loop
    insert into public.pachanga_competition_configuration_invalidations(
      user_id,competition_id,draft_id,entity_type,entity_id,revision,server_sequence,changed_at
    ) values (
      target_user,target_competition_id,target_draft_id,
      case when target_rule_revision_id is null then 'competition_configuration'
        else 'competition_rule_revision' end,
      coalesce(target_rule_revision_id,target_draft_id,target_competition_id),target_revision,
      target_server_sequence,target_confirmed_at
    ) on conflict do nothing;
  end loop;
  insert into private.pachanga_competition_configuration_receipts(
    operation_id,actor_id,action,aggregate_id,request_hash,confirmed_revision,
    server_sequence,client_metadata,response,created_at
  ) values (
    target_operation_id,target_actor_id,target_action,target_aggregate_id,
    target_request_hash,target_revision,target_server_sequence,
    private.pachanga_competition_client_metadata_v1(coalesce(target_client_metadata,'{}'::jsonb)),
    response,target_confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_competition_configuration_store_v1(
  uuid,uuid,text,uuid,uuid,uuid,uuid,bigint,bigint,text,text,jsonb,jsonb,jsonb,timestamptz
) from public, anon, authenticated;

create or replace function public.command_pachanga_competition_configuration_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare action_name text := lower(trim(coalesce(command_action,'')));
declare payload jsonb := coalesce(command_payload,'{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare competition public.pachanga_competitions%rowtype;
declare edition public.pachanga_competition_editions%rowtype;
declare source_revision public.pachanga_competition_rule_revisions%rowtype;
declare draft private.pachanga_competition_configuration_drafts%rowtype;
declare selected_edition_id uuid;
declare selected_source_id uuid;
declare selected_rule_set_id uuid;
declare selected_mode text;
declare selected_preset text;
declare selected_step smallint;
declare steps jsonb;
declare normalized_step jsonb;
declare preset jsonb;
declare bundle jsonb;
declare proposed_document jsonb;
declare selected_checksum text;
declare health jsonb;
declare impact jsonb;
declare freeze_point text;
declare next_version integer;
declare new_revision_id uuid;
declare sequence_value bigint := nextval('private.pachanga_competition_sequence');
declare confirmed_time timestamptz := clock_timestamp();
declare reason_text text;
declare snapshot jsonb;
declare applied_to_current boolean := false;
declare changed_section text;
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if operation_id is null or aggregate_id is null or expected_revision is null or expected_revision < 0
     or action_name not in (
       'draft.create','draft.clone','draft.mode.set','draft.preset.apply',
       'draft.section.save','draft.validate','draft.publish','draft.cancel'
     ) or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata,'{}'::jsonb)) <> 'object'
     or payload ?| array['actorId','createdBy','serverSequence','confirmedRevision','ruleDocument','checksum','serviceRole'] then
    raise exception 'INVALID_COMPETITION_CONFIGURATION_COMMAND' using errcode = '22023';
  end if;
  select * into settings from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.competition_configuration_center_enabled then
    raise exception 'COMPETITION_CONFIGURATION_CENTER_DISABLED' using errcode = '42501';
  end if;
  request_hash := private.pachanga_competition_request_hash_v1(
    action_name,aggregate_id,expected_revision,payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text,91410));
  replay := private.pachanga_competition_configuration_replay_v1(
    operation_id,actor_id,action_name,aggregate_id,request_hash
  );
  if replay is not null then return replay; end if;
  reason_text := left(coalesce(nullif(trim(payload ->> 'reason'),''),action_name),120);

  if action_name in ('draft.create','draft.clone') then
    select * into competition from public.pachanga_competitions competitions
    where competitions.id = aggregate_id for update;
    if not found or competition.product_key <> 'LEAGUE_PRIVATE_BETA_V1' then
      raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002';
    end if;
    perform private.pachanga_competition_configuration_lock_v1(competition.id);
    if competition.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if not private.pachanga_competition_configuration_can_edit_v1(competition.id,actor_id) then
      raise exception 'COMPETITION_RULES_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    selected_edition_id := nullif(payload ->> 'editionId','')::uuid;
    if selected_edition_id is null then
      select editions.id into selected_edition_id
      from public.pachanga_competition_editions editions
      where editions.competition_id = competition.id and editions.status <> 'cancelled'
      order by editions.server_sequence desc,editions.id desc limit 1;
    end if;
    select * into edition from public.pachanga_competition_editions editions
    where editions.id = selected_edition_id and editions.competition_id = competition.id;
    if not found then raise exception 'COMPETITION_EDITION_NOT_FOUND' using errcode = 'P0002'; end if;
    selected_source_id := coalesce(nullif(payload ->> 'sourceRuleRevisionId','')::uuid,edition.rule_revision_id);
    select revisions.* into source_revision
    from public.pachanga_competition_rule_revisions revisions
    join public.pachanga_competition_rule_sets sets on sets.id = revisions.rule_set_id
    where revisions.id = selected_source_id and sets.competition_id = competition.id
      and revisions.status in ('published','frozen');
    if not found then raise exception 'RULE_REVISION_NOT_PUBLISHED' using errcode = '22023'; end if;
    selected_rule_set_id := source_revision.rule_set_id;
    if exists (
      select 1 from private.pachanga_competition_configuration_drafts drafts
      where drafts.competition_id = competition.id and drafts.status in ('draft','validated')
    ) then raise exception 'COMPETITION_CONFIGURATION_ACTIVE_DRAFT_EXISTS' using errcode = 'PT409'; end if;
    selected_mode := case upper(coalesce(payload ->> 'authoringMode','SIMPLE'))
      when 'ADVANCED' then 'ADVANCED' else 'SIMPLE' end;
    selected_preset := nullif(upper(payload ->> 'presetKey'),'');
    steps := private.pachanga_competition_configuration_steps_from_rule_v1(
      competition.id,edition.id,source_revision.id
    );
    if selected_preset is not null and action_name = 'draft.create' then
      preset := private.pachanga_competition_authoring_preset_v1(selected_preset);
      steps := (preset -> 'steps') || jsonb_build_object('1',steps -> '1','3',steps -> '3');
    end if;
    insert into private.pachanga_competition_configuration_drafts(
      competition_id,edition_id,rule_set_id,source_rule_revision_id,created_by,
      status,authoring_mode,preset_key,current_step,completed_steps,step_data,
      changed_sections,revision,server_sequence,created_at,updated_at
    ) values (
      competition.id,edition.id,selected_rule_set_id,source_revision.id,actor_id,
      'draft',selected_mode,selected_preset,1,
      array[1,2,3,4,5,6,7,8,9,10,11,12]::smallint[],steps,
      '{}'::text[],1,sequence_value,confirmed_time,confirmed_time
    ) returning * into draft;
    snapshot := private.pachanga_competition_configuration_draft_snapshot_v1(draft.id);
    return private.pachanga_competition_configuration_store_v1(
      operation_id,actor_id,action_name,aggregate_id,competition.id,draft.id,null,
      draft.revision,sequence_value,reason_text,request_hash,client_metadata,
      jsonb_build_object('draftId',draft.id,'sourceRuleRevisionId',source_revision.id),
      snapshot,confirmed_time
    );
  end if;

  select * into draft from private.pachanga_competition_configuration_drafts drafts
  where drafts.id = aggregate_id for update;
  if not found then raise exception 'COMPETITION_CONFIGURATION_DRAFT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into competition from public.pachanga_competitions competitions
  where competitions.id = draft.competition_id for update;
  perform private.pachanga_competition_configuration_lock_v1(competition.id);
  if not private.pachanga_competition_configuration_can_edit_v1(competition.id,actor_id) then
    raise exception 'COMPETITION_RULES_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  if draft.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
  if draft.status not in ('draft','validated') then
    raise exception 'COMPETITION_CONFIGURATION_DRAFT_NOT_EDITABLE' using errcode = '22023';
  end if;
  select * into edition from public.pachanga_competition_editions editions where editions.id = draft.edition_id;
  bundle := private.pachanga_league_private_beta_bundle_snapshot_v1(
    competition.organizer_kind,coalesce(competition.organizer_group_id,competition.organizer_club_id)
  );

  if action_name = 'draft.mode.set' then
    selected_mode := upper(coalesce(payload ->> 'mode',''));
    if selected_mode not in ('SIMPLE','ADVANCED') or payload - array['mode','reason'] <> '{}'::jsonb then
      raise exception 'COMPETITION_CONFIGURATION_MODE_INVALID' using errcode = '22023';
    end if;
    update private.pachanga_competition_configuration_drafts drafts set
      authoring_mode=selected_mode,status='draft',validation_snapshot='{}'::jsonb,
      revision=drafts.revision+1,server_sequence=sequence_value,updated_at=confirmed_time
    where drafts.id=draft.id returning * into draft;
  elsif action_name = 'draft.preset.apply' then
    selected_preset := upper(coalesce(payload ->> 'presetKey',''));
    if payload - array['presetKey','reason'] <> '{}'::jsonb then
      raise exception 'COMPETITION_CONFIGURATION_PRESET_INVALID' using errcode = '22023';
    end if;
    preset := private.pachanga_competition_authoring_preset_v1(selected_preset);
    steps := (preset -> 'steps') || jsonb_build_object('1',draft.step_data -> '1','3',draft.step_data -> '3');
    update private.pachanga_competition_configuration_drafts drafts set
      preset_key=selected_preset,step_data=steps,status='draft',current_step=1,
      changed_sections=array['format','roster','match','scoring','incidents','discipline','referees','visibility'],
      validation_snapshot='{}'::jsonb,impact_snapshot='{}'::jsonb,
      confirmed_at=null,revision=drafts.revision+1,server_sequence=sequence_value,updated_at=confirmed_time
    where drafts.id=draft.id returning * into draft;
  elsif action_name = 'draft.section.save' then
    begin selected_step := (payload ->> 'step')::smallint;
    exception when others then raise exception 'COMPETITION_CONFIGURATION_STEP_INVALID' using errcode='22023'; end;
    if selected_step not between 1 and 12 or payload - array['step','data','reason'] <> '{}'::jsonb then
      raise exception 'COMPETITION_CONFIGURATION_STEP_INVALID' using errcode='22023';
    end if;
    normalized_step := private.pachanga_league_private_beta_normalize_step_v1(
      selected_step,payload -> 'data',bundle
    );
    changed_section := case selected_step when 1 then 'identity' when 2 then 'format'
      when 3 then 'edition' when 4 then 'format' when 5 then 'roster'
      when 6 then 'scoring' when 7 then 'match' when 8 then 'scoring'
      when 9 then 'incidents' when 10 then 'discipline' when 11 then 'referees'
      else 'visibility' end;
    freeze_point := private.pachanga_competition_configuration_freeze_point_v1(
      competition.id, edition.id
    );
    if changed_section in ('identity','edition','format','roster')
       and freeze_point <> 'DRAFT' then
      raise exception 'COMPETITION_CONFIGURATION_FROZEN:%', freeze_point using errcode='PT409';
    elsif changed_section = 'match' and freeze_point in ('SCHEDULE_PUBLISHED','FIRST_OFFICIAL_RESULT') then
      raise exception 'COMPETITION_CONFIGURATION_FROZEN:%', freeze_point using errcode='PT409';
    elsif changed_section = 'scoring' and freeze_point = 'FIRST_OFFICIAL_RESULT' then
      raise exception 'COMPETITION_CONFIGURATION_FROZEN:%', freeze_point using errcode='PT409';
    elsif changed_section = 'discipline' and exists (
      select 1 from public.pachanga_competition_disciplinary_events events
      where events.competition_id = competition.id
    ) then
      raise exception 'COMPETITION_CONFIGURATION_DISCIPLINE_IN_USE' using errcode='PT409';
    elsif changed_section = 'referees' and exists (
      select 1 from public.pachanga_referee_assignments assignments
      where assignments.requester_competition_id = competition.id
        and assignments.status in ('confirmed','completed')
    ) then
      raise exception 'COMPETITION_CONFIGURATION_REFEREE_POLICY_IN_USE' using errcode='PT409';
    end if;
    update private.pachanga_competition_configuration_drafts drafts set
      step_data=jsonb_set(drafts.step_data,array[selected_step::text],normalized_step,true),
      completed_steps=array(select distinct value from unnest(drafts.completed_steps || selected_step) value order by value),
      current_step=least(12,greatest(drafts.current_step,selected_step+1)),
      changed_sections=array(select distinct value from unnest(drafts.changed_sections || changed_section) value order by value),
      status='draft',validation_snapshot='{}'::jsonb,impact_snapshot='{}'::jsonb,
      confirmed_at=null,revision=drafts.revision+1,server_sequence=sequence_value,updated_at=confirmed_time
    where drafts.id=draft.id returning * into draft;
  elsif action_name = 'draft.validate' then
    proposed_document := private.pachanga_competition_configuration_rule_document_v1(
      draft.step_data,draft.authoring_mode,draft.preset_key
    );
    selected_checksum := private.pachanga_validate_competition_rule_document_v1(
      'competition_rules.v1',proposed_document
    );
    health := private.pachanga_competition_configuration_health_v1(draft.step_data,draft.completed_steps);
    impact := private.pachanga_competition_configuration_impact_v1(
      competition.id,edition.id,draft.source_rule_revision_id,proposed_document
    );
    if not coalesce((health ->> 'complete')::boolean,false) then
      raise exception 'COMPETITION_CONFIGURATION_INVALID' using errcode='22023',detail=health::text;
    end if;
    update private.pachanga_competition_configuration_drafts drafts set
      status='validated',validation_snapshot=health || jsonb_build_object('checksum',selected_checksum),
      impact_snapshot=impact,effective_from=coalesce(nullif(payload ->> 'effectiveFrom','')::timestamptz,confirmed_time),
      effective_scope=case upper(coalesce(payload ->> 'effectiveScope','FUTURE_ONLY'))
        when 'FUTURE_STAGE' then 'future_stage' else 'future_only' end,
      confirmed_at=confirmed_time,revision=drafts.revision+1,server_sequence=sequence_value,updated_at=confirmed_time
    where drafts.id=draft.id returning * into draft;
  elsif action_name = 'draft.publish' then
    if draft.status <> 'validated' then
      raise exception 'COMPETITION_CONFIGURATION_VALIDATION_REQUIRED' using errcode='22023';
    end if;
    proposed_document := private.pachanga_competition_configuration_rule_document_v1(
      draft.step_data,draft.authoring_mode,draft.preset_key
    );
    selected_checksum := private.pachanga_validate_competition_rule_document_v1('competition_rules.v1',proposed_document);
    health := private.pachanga_competition_configuration_health_v1(draft.step_data,draft.completed_steps);
    if not coalesce((health ->> 'complete')::boolean,false)
       or draft.validation_snapshot ->> 'checksum' is distinct from selected_checksum then
      raise exception 'COMPETITION_CONFIGURATION_REVALIDATION_REQUIRED' using errcode='PT409';
    end if;
    impact := private.pachanga_competition_configuration_impact_v1(
      competition.id,edition.id,draft.source_rule_revision_id,proposed_document
    );
    freeze_point := impact ->> 'freezePoint';
    if coalesce(draft.effective_from,confirmed_time) < confirmed_time - interval '1 second' then
      raise exception 'COMPETITION_CONFIGURATION_EFFECTIVE_DATE_INVALID' using errcode='22023';
    end if;
    if not coalesce((payload ->> 'confirmImpact')::boolean,false)
       or not coalesce((payload ->> 'confirmRuleSummary')::boolean,false) then
      raise exception 'COMPETITION_CONFIGURATION_CONFIRMATION_REQUIRED' using errcode='22023';
    end if;
    perform 1
    from public.pachanga_competition_rule_sets rule_sets
    where rule_sets.id=draft.rule_set_id
    for update;
    select coalesce(max(revisions.version),0)+1 into next_version
    from public.pachanga_competition_rule_revisions revisions
    where revisions.rule_set_id=draft.rule_set_id;
    new_revision_id := gen_random_uuid();
    insert into public.pachanga_competition_rule_revisions(
      id,rule_set_id,version,schema_version,rule_document,checksum,effective_from,
      effective_scope,status,revision,supersedes_revision_id,reason,server_sequence,
      created_by,created_at,updated_at
    ) values (
      new_revision_id,draft.rule_set_id,next_version,'competition_rules.v1',proposed_document,
      selected_checksum,coalesce(draft.effective_from,confirmed_time),draft.effective_scope,
      'frozen',1,draft.source_rule_revision_id,
      left(coalesce(nullif(trim(payload ->> 'reason'),''),'Configuration Center publication'),1200),
      nextval('private.pachanga_competition_sequence'),actor_id,confirmed_time,confirmed_time
    );
    if freeze_point='DRAFT' then
      update public.pachanga_competition_editions editions set
        rule_revision_id=new_revision_id,registration_rule_revision_id=new_revision_id,
        revision=editions.revision+1,server_sequence=nextval('private.pachanga_competition_sequence'),updated_at=confirmed_time
      where editions.id=edition.id;
      update public.pachanga_competition_stages stages set
        rule_revision_id=new_revision_id,revision=stages.revision+1,
        server_sequence=nextval('private.pachanga_competition_sequence'),updated_at=confirmed_time
      where stages.edition_id=edition.id and stages.status='draft';
      applied_to_current := true;
    end if;
    update private.pachanga_competition_configuration_drafts drafts set
      status='published',materialized_rule_revision_id=new_revision_id,
      impact_snapshot=impact,confirmed_at=confirmed_time,
      revision=drafts.revision+1,server_sequence=sequence_value,updated_at=confirmed_time
    where drafts.id=draft.id returning * into draft;
  else
    update private.pachanga_competition_configuration_drafts drafts set
      status='cancelled',confirmed_at=confirmed_time,
      revision=drafts.revision+1,server_sequence=sequence_value,updated_at=confirmed_time
    where drafts.id=draft.id returning * into draft;
  end if;

  snapshot := private.pachanga_competition_configuration_draft_snapshot_v1(draft.id);
  if action_name='draft.publish' then
    snapshot := snapshot || jsonb_build_object(
      'ruleRevision',private.pachanga_competition_configuration_human_document_v1(new_revision_id),
      'appliedToCurrentEdition',applied_to_current,
      'currentEditionPreserved',not applied_to_current
    );
  end if;
  return private.pachanga_competition_configuration_store_v1(
    operation_id,actor_id,action_name,aggregate_id,competition.id,draft.id,new_revision_id,
    draft.revision,sequence_value,reason_text,request_hash,client_metadata,
    jsonb_build_object('draftId',draft.id,'ruleRevisionId',new_revision_id,'appliedToCurrentEdition',applied_to_current),
    snapshot,confirmed_time
  );
exception
  when unique_violation then raise exception 'COMPETITION_CONFIGURATION_CONFLICT' using errcode='PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode='PT409';
end;
$$;

revoke all on function public.command_pachanga_competition_configuration_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public,anon;
grant execute on function public.command_pachanga_competition_configuration_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated,service_role;

create or replace function public.get_pachanga_competition_configuration_v1(
  target_competition_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid:=auth.uid();
declare competition public.pachanga_competitions%rowtype;
declare edition public.pachanga_competition_editions%rowtype;
declare revision_row public.pachanga_competition_rule_revisions%rowtype;
declare draft_id uuid;
declare can_edit boolean;
declare current_document jsonb;
declare public_referee jsonb;
declare visible_document jsonb;
declare visible_summary jsonb;
declare human_document jsonb;
declare revisions jsonb;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into competition from public.pachanga_competitions competitions
  where competitions.id=target_competition_id;
  if not found or not private.pachanga_competition_can_v1(competition.id,actor_id,'read') then
    raise exception 'COMPETITION_NOT_FOUND' using errcode='P0002';
  end if;
  can_edit:=private.pachanga_competition_configuration_can_edit_v1(competition.id,actor_id);
  select * into edition from public.pachanga_competition_editions editions
  where editions.competition_id=competition.id and editions.status<>'cancelled'
  order by editions.server_sequence desc,editions.id desc limit 1;
  select revisions.* into revision_row from public.pachanga_competition_rule_revisions revisions
  join public.pachanga_competition_rule_sets sets on sets.id=revisions.rule_set_id
  where sets.competition_id=competition.id and revisions.id=edition.rule_revision_id;
  current_document:=revision_row.rule_document;
  public_referee:=coalesce(current_document #> '{operations,refereePolicy}','{}'::jsonb);
  if not coalesce((public_referee #>> '{fee,publicConsent}')::boolean,false) then
    public_referee:=jsonb_set(coalesce(public_referee,'{}'::jsonb),'{fee}',
      coalesce(public_referee -> 'fee','{}'::jsonb)-array['fixedCents'],true);
  end if;
  visible_document:=case when can_edit then current_document
    else jsonb_set(current_document,'{operations,refereePolicy}',public_referee,true) end;
  visible_summary:=private.pachanga_competition_configuration_summary_v1(visible_document);
  human_document:=case when can_edit then
    private.pachanga_competition_configuration_human_document_v1(revision_row.id)
  else jsonb_build_object(
    'competitionId',competition.id,
    'competitionName',competition.name,
    'ruleRevisionId',revision_row.id,
    'revision',revision_row.version,
    'effectiveFrom',revision_row.effective_from,
    'effectiveScope',revision_row.effective_scope,
    'hash',revision_row.checksum,
    'sections',visible_summary,
    'notice','Esta vista se deriva de la RuleRevision congelada; el texto no es una autoridad independiente.'
  ) end;
  select drafts.id into draft_id from private.pachanga_competition_configuration_drafts drafts
  where drafts.competition_id=competition.id and drafts.status in ('draft','validated')
  order by drafts.server_sequence desc,drafts.id desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',visible.id,'version',visible.version,'status',visible.status,
    'effectiveFrom',visible.effective_from,'effectiveScope',visible.effective_scope,
    'checksum',visible.checksum,'supersedesRuleRevisionId',visible.supersedes_revision_id,
    'serverSequence',visible.server_sequence,'createdAt',visible.created_at
  ) order by visible.version desc,visible.id desc),'[]'::jsonb) into revisions
  from (
    select rule_revisions.* from public.pachanga_competition_rule_revisions rule_revisions
    where rule_revisions.rule_set_id=revision_row.rule_set_id
    order by rule_revisions.version desc,rule_revisions.id desc limit 50
  ) visible;
  return jsonb_build_object(
    'competition',jsonb_build_object(
      'id',competition.id,'name',competition.name,'status',competition.status,
      'actorRole',private.pachanga_competition_actor_role_v1(competition.id,actor_id),
      'revision',competition.revision
    ),
    'edition',jsonb_build_object(
      'id',edition.id,'name',edition.name,'seasonLabel',edition.season_label,
      'status',edition.status,'revision',edition.revision
    ),
    'capabilities',jsonb_build_object('read',true,'edit',can_edit,'publish',can_edit),
    'freezePoint',private.pachanga_competition_configuration_freeze_point_v1(competition.id,edition.id),
    'currentRuleRevision',jsonb_build_object(
      'id',revision_row.id,'version',revision_row.version,'checksum',revision_row.checksum,
      'effectiveFrom',revision_row.effective_from,'effectiveScope',revision_row.effective_scope,
      'summary',visible_summary,
      'document',human_document
    ),
    'draft',case when can_edit and draft_id is not null
      then private.pachanga_competition_configuration_draft_snapshot_v1(draft_id) end,
    'revisions',revisions,
    'presets',public.get_pachanga_competition_authoring_presets_v1(),
    'flags',public.get_pachanga_league_private_beta_flags_v1(),
    'cache',jsonb_build_object('policy','private-no-store','realtimeMode','invalidate_then_refetch')
  );
end;
$$;

revoke all on function public.get_pachanga_competition_configuration_v1(uuid)
  from public,anon;
grant execute on function public.get_pachanga_competition_configuration_v1(uuid)
  to authenticated,service_role;

comment on function public.command_pachanga_competition_configuration_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) is 'Authoritative configuration command. It accepts intentions and can only materialize a new immutable CompetitionRuleRevision.';
