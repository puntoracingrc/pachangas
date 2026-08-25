-- Pachangas IQ R5: server-authoritative competition discipline commands.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_can_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text := private.pachanga_competition_actor_role_v1(
  target_competition_id, target_actor_id
);
declare selected_competition public.pachanga_competitions%rowtype;
declare beta_enabled boolean;
begin
  if actor_role in ('service_authority', 'platform_owner', 'platform_admin') then return true; end if;
  select * into selected_competition
  from public.pachanga_competitions competitions where competitions.id = target_competition_id;
  if selected_competition.product_key = 'LEAGUE_PRIVATE_BETA_V1'
     and target_capability <> 'read' then
    select settings.league_private_beta_enabled into beta_enabled
    from private.pachanga_competition_foundation_settings settings where settings.singleton;
    if not coalesce(beta_enabled, false)
       or private.pachanga_league_private_beta_active_bundle_id_v1(
         selected_competition.organizer_kind,
         coalesce(selected_competition.organizer_group_id, selected_competition.organizer_club_id)
       ) is null then return false; end if;
  end if;
  if actor_role = 'competition_owner' then return true; end if;
  return case actor_role
    when 'competition_director' then target_capability in (
      'read', 'manage', 'staff', 'rules', 'referees', 'entries_manage',
      'rosters_review', 'categories_manage', 'schedule_read', 'schedule_manage',
      'schedule_publish', 'results_read', 'results_manage', 'standings_read',
      'standings_manage', 'operations_read', 'operations_manage',
      'discipline_read', 'discipline_manage', 'discipline_review', 'appeals_manage'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'entries_manage', 'rosters_review', 'categories_manage',
      'schedule_read', 'schedule_manage', 'schedule_publish', 'results_read',
      'results_manage', 'standings_read', 'standings_manage',
      'operations_read', 'operations_manage', 'discipline_read',
      'discipline_manage', 'discipline_review', 'appeals_manage'
    )
    when 'competition_discipline_manager' then target_capability in (
      'read', 'results_read', 'operations_read', 'discipline_read', 'discipline_manage'
    )
    when 'competition_discipline_reviewer' then target_capability in (
      'read', 'results_read', 'operations_read', 'discipline_read', 'discipline_review'
    )
    when 'competition_appeals_manager' then target_capability in (
      'read', 'results_read', 'operations_read', 'discipline_read', 'appeals_manage'
    )
    when 'competition_operations_manager' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read',
      'operations_read', 'operations_manage', 'discipline_read'
    )
    when 'competition_schedule_manager' then target_capability in (
      'read', 'schedule_read', 'schedule_manage', 'schedule_publish', 'operations_read'
    )
    when 'competition_result_manager' then target_capability in (
      'read', 'results_read', 'results_manage', 'standings_read', 'operations_read',
      'discipline_read'
    )
    when 'competition_standings_manager' then target_capability in (
      'read', 'results_read', 'standings_read', 'standings_manage', 'operations_read'
    )
    when 'competition_registration_manager' then target_capability in ('read', 'entries_manage')
    when 'competition_roster_manager' then target_capability in ('read', 'rosters_review', 'discipline_read')
    when 'rules_manager' then target_capability in ('read', 'rules', 'discipline_read')
    when 'competition_referee_manager' then target_capability in ('read', 'referees')
    when 'viewer' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read',
      'operations_read', 'discipline_read'
    )
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.competition_discipline_foundation_enabled,
    'eventsEnabled', settings.competition_disciplinary_events_enabled,
    'countersEnabled', settings.competition_disciplinary_counters_enabled,
    'sanctionsEnabled', settings.competition_sanctions_enabled,
    'serviceEnabled', settings.competition_sanction_service_enabled,
    'appealsEnabled', settings.competition_discipline_appeals_enabled,
    'publicEnabled', settings.competition_public_discipline_enabled,
    'engineVersion', 'competition-discipline-v1',
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

revoke all on function private.pachanga_competition_discipline_flags_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_assert_flags_v1(
  require_events boolean default false,
  require_counters boolean default false,
  require_sanctions boolean default false,
  require_service boolean default false,
  require_appeals boolean default false
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.competition_discipline_foundation_enabled then
    raise exception 'COMPETITION_DISCIPLINE_DISABLED' using errcode = '42501';
  end if;
  if require_events and not settings.competition_disciplinary_events_enabled then
    raise exception 'COMPETITION_DISCIPLINARY_EVENTS_DISABLED' using errcode = '42501';
  end if;
  if require_counters and not settings.competition_disciplinary_counters_enabled then
    raise exception 'COMPETITION_DISCIPLINARY_COUNTERS_DISABLED' using errcode = '42501';
  end if;
  if require_sanctions and not settings.competition_sanctions_enabled then
    raise exception 'COMPETITION_SANCTIONS_DISABLED' using errcode = '42501';
  end if;
  if require_service and not settings.competition_sanction_service_enabled then
    raise exception 'COMPETITION_SANCTION_SERVICE_DISABLED' using errcode = '42501';
  end if;
  if require_appeals and not settings.competition_discipline_appeals_enabled then
    raise exception 'COMPETITION_DISCIPLINE_APPEALS_DISABLED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_competition_discipline_assert_flags_v1(
  boolean, boolean, boolean, boolean, boolean
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_default_policy_v1()
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'policyVersion', 'league-private-beta-r5.v1',
    'cardTypeCatalog', jsonb_build_array(
      jsonb_build_object(
        'code', 'YELLOW', 'label', 'Amarilla', 'visualType', 'yellow',
        'immediateEffect', 'WARNING',
        'accumulation', jsonb_build_object(
          'enabled', true, 'points', 1, 'threshold', 3,
          'outcome', 'FIXED_SANCTION', 'unitType', 'MATCHES', 'units', 1
        ),
        'dismissal', jsonb_build_object(
          'mode', 'SECOND_CARD', 'thresholdInMatch', 2,
          'outcome', 'FIXED_SANCTION', 'unitType', 'MATCHES', 'units', 1
        )
      ),
      jsonb_build_object(
        'code', 'RED', 'label', 'Roja', 'visualType', 'red',
        'immediateEffect', 'DIRECT_DISMISSAL',
        'accumulation', jsonb_build_object('enabled', false, 'points', 0),
        'dismissal', jsonb_build_object(
          'mode', 'DIRECT', 'outcome', 'COMMITTEE_REQUIRED',
          'unitType', 'MATCHES', 'provisionalUnits', 1,
          'minimumUnits', 1, 'maximumUnits', 3, 'ruleArticle', 'R5.RED.1'
        )
      ),
      jsonb_build_object(
        'code', 'BLUE', 'label', 'Azul', 'visualType', 'blue',
        'immediateEffect', 'TEMPORARY_DISMISSAL',
        'accumulation', jsonb_build_object('enabled', false, 'points', 0),
        'dismissal', jsonb_build_object('mode', 'TEMPORARY', 'outcome', 'NO_SANCTION'),
        'temporaryDismissal', jsonb_build_object(
          'mode', 'BOTH', 'durationMinutes', 5, 'endOnOpponentGoal', true,
          'replacementPolicy', 'NO_REPLACEMENT'
        )
      )
    ),
    'cyclePolicy', jsonb_build_object(
      'scopeType', 'EDITION', 'carryPolicy', 'RESET'
    ),
    'sanctionPolicy', jsonb_build_object(
      'eligibleFixtureStatuses', jsonb_build_array('official', 'played'),
      'consumePostponed', false, 'consumeCancelled', false, 'consumeBye', false
    ),
    'appealPolicy', jsonb_build_object(
      'deadlineHours', 72, 'suspensiveEffect', false
    ),
    'publicReasonCategories', jsonb_build_array(
      'accumulation', 'dismissal', 'temporary_dismissal', 'administrative'
    )
  );
$$;

create or replace function private.pachanga_competition_discipline_ensure_catalog_v1(
  target_competition_id uuid,
  target_rule_revision_id uuid,
  target_actor_id uuid
)
returns public.pachanga_competition_discipline_rule_catalogs
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_catalog public.pachanga_competition_discipline_rule_catalogs%rowtype;
declare selected_competition public.pachanga_competitions%rowtype;
declare default_policy jsonb := private.pachanga_competition_discipline_default_policy_v1();
declare computed_checksum text;
begin
  select * into selected_catalog
  from public.pachanga_competition_discipline_rule_catalogs catalogs
  where catalogs.rule_revision_id = target_rule_revision_id;
  if found then
    if selected_catalog.competition_id <> target_competition_id then
      raise exception 'DISCIPLINE_RULE_COMPETITION_MISMATCH' using errcode = '22023';
    end if;
    return selected_catalog;
  end if;
  select * into selected_competition
  from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;
  if selected_competition.product_key <> 'LEAGUE_PRIVATE_BETA_V1' then
    raise exception 'DISCIPLINE_RULE_CATALOG_REQUIRED' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.pachanga_competition_rule_revisions revisions
    join public.pachanga_competition_rule_sets sets on sets.id = revisions.rule_set_id
    where revisions.id = target_rule_revision_id
      and sets.competition_id = target_competition_id
      and revisions.status in ('published', 'frozen')
  ) then raise exception 'RULE_REVISION_NOT_PUBLISHED' using errcode = '22023'; end if;
  computed_checksum := encode(
    extensions.digest(convert_to(default_policy::text, 'UTF8'), 'sha256'),
    'hex'
  );
  insert into public.pachanga_competition_discipline_rule_catalogs(
    rule_revision_id, competition_id, policy_version, card_type_catalog,
    cycle_policy, sanction_policy, appeal_policy, public_reason_categories,
    checksum, created_by
  ) values (
    target_rule_revision_id, target_competition_id,
    default_policy ->> 'policyVersion', default_policy -> 'cardTypeCatalog',
    default_policy -> 'cyclePolicy', default_policy -> 'sanctionPolicy',
    default_policy -> 'appealPolicy', default_policy -> 'publicReasonCategories',
    computed_checksum, target_actor_id
  ) returning * into selected_catalog;
  return selected_catalog;
end;
$$;

revoke all on function private.pachanga_competition_discipline_ensure_catalog_v1(
  uuid, uuid, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_card_rule_v1(
  target_rule_revision_id uuid,
  target_card_type_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_rule jsonb;
begin
  select card.value into selected_rule
  from public.pachanga_competition_discipline_rule_catalogs catalogs
  cross join lateral jsonb_array_elements(catalogs.card_type_catalog) card(value)
  where catalogs.rule_revision_id = target_rule_revision_id
    and upper(card.value ->> 'code') = upper(trim(target_card_type_code));
  if selected_rule is null then
    raise exception 'DISCIPLINE_CARD_TYPE_NOT_ALLOWED' using errcode = '22023';
  end if;
  return selected_rule;
end;
$$;

revoke all on function private.pachanga_competition_discipline_card_rule_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_request_hash_v1(
  target_competition_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(concat_ws('|',
    target_competition_id::text,
    lower(trim(target_action)),
    target_aggregate_id::text,
    target_expected_revision::text,
    coalesce(target_payload, '{}'::jsonb)::text
  ), 'UTF8'), 'sha256'), 'hex');
$$;

revoke all on function private.pachanga_competition_discipline_request_hash_v1(
  uuid, text, uuid, bigint, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_replay_v1(
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
declare receipt private.pachanga_competition_operation_receipts%rowtype;
begin
  select * into receipt
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id is distinct from target_actor_id
     or receipt.actor_kind <> 'authenticated'
     or receipt.action <> target_action
     or receipt.aggregate_type <> 'competition_discipline'
     or receipt.aggregate_id <> target_aggregate_id::text
     or receipt.request_hash <> target_request_hash then
    raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

revoke all on function private.pachanga_competition_discipline_replay_v1(
  uuid, uuid, text, uuid, text
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_resolve_cycle_v1(
  target_context_id uuid,
  target_actor_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare catalog_row public.pachanga_competition_discipline_rule_catalogs%rowtype;
declare selected_cycle_id uuid;
declare selected_scope text;
declare selected_carry text;
declare effective_start timestamptz;
begin
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id;
  if not found then raise exception 'DISCIPLINE_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
  catalog_row := private.pachanga_competition_discipline_ensure_catalog_v1(
    context_row.competition_id, context_row.rule_revision_id, target_actor_id
  );
  select cycles.id into selected_cycle_id
  from public.pachanga_competition_disciplinary_cycles cycles
  where cycles.competition_id = context_row.competition_id
    and cycles.edition_id = context_row.edition_id
    and cycles.status = 'active'
    and (
      (cycles.scope_type = 'GROUP'
        and cycles.competition_group_id = context_row.competition_group_id)
      or (cycles.scope_type in ('STAGE', 'SPLIT')
        and cycles.stage_id = context_row.stage_id
        and cycles.competition_group_id is null)
      or (cycles.scope_type = 'EDITION'
        and cycles.stage_id is null and cycles.competition_group_id is null)
    )
  order by case cycles.scope_type
    when 'GROUP' then 1 when 'SPLIT' then 2 when 'STAGE' then 3 else 4 end,
    cycles.server_sequence desc, cycles.id desc
  limit 1;
  if selected_cycle_id is not null then return selected_cycle_id; end if;

  selected_scope := upper(coalesce(catalog_row.cycle_policy ->> 'scopeType', 'EDITION'));
  selected_carry := upper(coalesce(catalog_row.cycle_policy ->> 'carryPolicy', 'RESET'));
  if selected_scope not in ('EDITION', 'STAGE', 'GROUP', 'SPLIT')
     or selected_carry not in ('RESET', 'CARRY') then
    raise exception 'DISCIPLINE_CYCLE_POLICY_INVALID' using errcode = '22023';
  end if;
  select coalesce(editions.starts_at::timestamptz, clock_timestamp()) into effective_start
  from public.pachanga_competition_editions editions where editions.id = context_row.edition_id;
  insert into public.pachanga_competition_disciplinary_cycles(
    competition_id, edition_id, stage_id, competition_group_id,
    rule_revision_id, scope_type, carry_policy, effective_from, created_by
  ) values (
    context_row.competition_id, context_row.edition_id,
    case when selected_scope in ('STAGE', 'GROUP', 'SPLIT') then context_row.stage_id end,
    case when selected_scope = 'GROUP' then context_row.competition_group_id end,
    context_row.rule_revision_id, selected_scope, selected_carry,
    effective_start, target_actor_id
  ) returning id into selected_cycle_id;
  return selected_cycle_id;
exception
  when unique_violation then
    select cycles.id into selected_cycle_id
    from public.pachanga_competition_disciplinary_cycles cycles
    where cycles.competition_id = context_row.competition_id
      and cycles.edition_id = context_row.edition_id
      and cycles.status = 'active'
    order by cycles.server_sequence desc, cycles.id desc
    limit 1;
    if selected_cycle_id is null then raise; end if;
    return selected_cycle_id;
end;
$$;

revoke all on function private.pachanga_competition_discipline_resolve_cycle_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_match_entry_v1(
  target_canonical_match_id uuid,
  target_player_profile_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_entry_id uuid;
begin
  select squads.entry_id into selected_entry_id
  from public.pachanga_competition_match_squads squads
  join public.pachanga_competition_match_squad_members members
    on members.squad_revision_id = squads.current_revision_id
  where squads.canonical_match_id = target_canonical_match_id
    and members.player_profile_id = target_player_profile_id
    and squads.status in ('submitted', 'validated', 'locked')
  order by squads.server_sequence desc, squads.id desc
  limit 1;
  if selected_entry_id is null then
    raise exception 'DISCIPLINE_PLAYER_NOT_ON_MATCH_SHEET' using errcode = '22023';
  end if;
  return selected_entry_id;
end;
$$;

revoke all on function private.pachanga_competition_discipline_match_entry_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_rule_outcome_v1(
  target_rule_revision_id uuid,
  target_card_type_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare card_rule jsonb := private.pachanga_competition_discipline_card_rule_v1(
  target_rule_revision_id, target_card_type_code
);
declare accumulation jsonb := coalesce(card_rule -> 'accumulation', '{}'::jsonb);
declare dismissal jsonb := coalesce(card_rule -> 'dismissal', '{}'::jsonb);
begin
  return jsonb_build_object(
    'cardTypeCode', upper(card_rule ->> 'code'),
    'label', card_rule ->> 'label',
    'visualType', card_rule ->> 'visualType',
    'immediateEffect', card_rule ->> 'immediateEffect',
    'accumulationEnabled', coalesce((accumulation ->> 'enabled')::boolean, false),
    'accumulationPoints', coalesce((accumulation ->> 'points')::integer, 0),
    'accumulationThreshold', nullif(accumulation ->> 'threshold', '')::integer,
    'accumulationOutcome', coalesce(accumulation ->> 'outcome', 'NO_SANCTION'),
    'accumulationUnitType', accumulation ->> 'unitType',
    'accumulationUnits', nullif(accumulation ->> 'units', '')::integer,
    'dismissalMode', coalesce(dismissal ->> 'mode', 'NONE'),
    'dismissalThresholdInMatch', nullif(dismissal ->> 'thresholdInMatch', '')::integer,
    'dismissalOutcome', coalesce(dismissal ->> 'outcome', 'NO_SANCTION'),
    'dismissalUnitType', dismissal ->> 'unitType',
    'dismissalUnits', nullif(dismissal ->> 'units', '')::integer,
    'provisionalUnits', coalesce(nullif(dismissal ->> 'provisionalUnits', '')::integer, 0),
    'minimumUnits', nullif(dismissal ->> 'minimumUnits', '')::integer,
    'maximumUnits', nullif(dismissal ->> 'maximumUnits', '')::integer,
    'ruleArticle', dismissal ->> 'ruleArticle',
    'temporaryDismissal', card_rule -> 'temporaryDismissal'
  );
exception when others then
  raise exception 'DISCIPLINE_CARD_RULE_INVALID' using errcode = '22023';
end;
$$;

revoke all on function private.pachanga_competition_discipline_rule_outcome_v1(uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_rebuild_counters_v1(
  target_cycle_id uuid,
  target_player_profile_id uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition_id uuid;
declare combined_checksum text;
begin
  select cycles.competition_id into selected_competition_id
  from public.pachanga_competition_disciplinary_cycles cycles
  where cycles.id = target_cycle_id;
  if selected_competition_id is null then
    raise exception 'DISCIPLINE_CYCLE_NOT_FOUND' using errcode = 'P0002';
  end if;

  delete from public.pachanga_competition_disciplinary_counters counters
  where counters.cycle_id = target_cycle_id
    and counters.player_profile_id = target_player_profile_id
    and not exists (
      select 1
      from public.pachanga_competition_disciplinary_events events
      join public.pachanga_competition_disciplinary_event_revisions revisions
        on revisions.id = events.current_revision_id
      where events.cycle_id = target_cycle_id
        and events.player_profile_id = target_player_profile_id
        and events.status = 'active'
        and revisions.event_status = 'active'
        and revisions.card_type_code = counters.card_type_code
    )
    and counters.carried_points = 0;

  with event_facts as (
    select revisions.card_type_code,
      count(*)::integer as event_count,
      coalesce(sum((revisions.rule_outcome ->> 'accumulationPoints')::integer), 0)::integer as event_points,
      max(coalesce((revisions.rule_outcome ->> 'accumulationThreshold')::integer, 0))::integer as threshold,
      max(events.server_sequence) as last_sequence
    from public.pachanga_competition_disciplinary_events events
    join public.pachanga_competition_disciplinary_event_revisions revisions
      on revisions.id = events.current_revision_id
    where events.cycle_id = target_cycle_id
      and events.player_profile_id = target_player_profile_id
      and events.status = 'active'
      and revisions.event_status = 'active'
    group by revisions.card_type_code
  ), facts as (
    select coalesce(event_facts.card_type_code, existing.card_type_code) as card_type_code,
      coalesce(event_facts.event_count, 0) as event_count,
      coalesce(existing.carried_points, 0) as carried_points,
      coalesce(existing.carried_points, 0) + coalesce(event_facts.event_points, 0) as points,
      coalesce(event_facts.threshold, 0) as threshold,
      greatest(coalesce(event_facts.last_sequence, 0), coalesce(existing.server_sequence, 0)) as last_sequence
    from event_facts
    full join (
      select target_counters.*
      from public.pachanga_competition_disciplinary_counters target_counters
      where target_counters.cycle_id = target_cycle_id
        and target_counters.player_profile_id = target_player_profile_id
        and target_counters.carried_points > 0
    ) existing on existing.card_type_code = event_facts.card_type_code
  ), prepared as (
    select facts.*,
      case when facts.threshold > 0 then floor(facts.points::numeric / facts.threshold)::integer else 0 end as hits,
      encode(extensions.digest(convert_to(concat_ws('|',
        target_cycle_id::text, target_player_profile_id::text, facts.card_type_code,
        facts.event_count::text, facts.carried_points::text, facts.points::text,
        case when facts.threshold > 0 then floor(facts.points::numeric / facts.threshold)::integer else 0 end::text,
        facts.last_sequence::text
      ), 'UTF8'), 'sha256'), 'hex') as checksum
    from facts
  )
  insert into public.pachanga_competition_disciplinary_counters(
    competition_id, cycle_id, player_profile_id, card_type_code,
    active_event_count, carried_points, accumulation_points, threshold_hits,
    last_event_server_sequence, state_checksum
  ) select selected_competition_id, target_cycle_id, target_player_profile_id,
    prepared.card_type_code, prepared.event_count, prepared.carried_points,
    prepared.points, prepared.hits,
    prepared.last_sequence, prepared.checksum
  from prepared
  on conflict (cycle_id, player_profile_id, card_type_code) do update set
    active_event_count = excluded.active_event_count,
    carried_points = excluded.carried_points,
    accumulation_points = excluded.accumulation_points,
    threshold_hits = excluded.threshold_hits,
    last_event_server_sequence = excluded.last_event_server_sequence,
    state_checksum = excluded.state_checksum,
    revision = public.pachanga_competition_disciplinary_counters.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp();

  select encode(extensions.digest(convert_to(coalesce(string_agg(
    counters.state_checksum, '|' order by counters.card_type_code, counters.id
  ), ''), 'UTF8'), 'sha256'), 'hex') into combined_checksum
  from public.pachanga_competition_disciplinary_counters counters
  where counters.cycle_id = target_cycle_id
    and counters.player_profile_id = target_player_profile_id;
  return combined_checksum;
end;
$$;

revoke all on function private.pachanga_competition_discipline_rebuild_counters_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_reconcile_sanctions_v1(
  target_cycle_id uuid,
  target_player_profile_id uuid,
  target_actor_id uuid,
  target_reason text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare event_row record;
declare existing_sanction public.pachanga_competition_sanctions%rowtype;
declare points_by_card jsonb := '{}'::jsonb;
declare points_before integer;
declare points_after integer;
declare threshold_value integer;
declare hit_before integer;
declare hit_after integer;
declare same_match_count integer;
declare dismissal_mode text;
declare desired_outcome text;
declare desired_unit_type text;
declare desired_units integer;
declare provisional_units integer;
declare minimum_units integer;
declare maximum_units integer;
declare desired_status text;
declare internal_operation_id uuid;
declare sanction_id uuid;
declare sanction_revision_id uuid;
declare changed_count integer := 0;
declare public_category text;
declare sanction_exists boolean;
begin
  for event_row in
    select events.*, revisions.card_type_code, revisions.rule_outcome,
      revisions.public_reason_category, revisions.public_summary
    from public.pachanga_competition_disciplinary_events events
    join public.pachanga_competition_disciplinary_event_revisions revisions
      on revisions.id = events.current_revision_id
    where events.cycle_id = target_cycle_id
      and events.player_profile_id = target_player_profile_id
      and events.status = 'active'
      and revisions.event_status = 'active'
    order by events.server_sequence, events.id
  loop
    points_before := coalesce((points_by_card ->> event_row.card_type_code)::integer, 0);
    points_after := points_before
      + coalesce((event_row.rule_outcome ->> 'accumulationPoints')::integer, 0);
    points_by_card := jsonb_set(
      points_by_card, array[event_row.card_type_code], to_jsonb(points_after), true
    );
    threshold_value := coalesce(
      (event_row.rule_outcome ->> 'accumulationThreshold')::integer, 0
    );
    hit_before := case when threshold_value > 0
      then floor(points_before::numeric / threshold_value)::integer else 0 end;
    hit_after := case when threshold_value > 0
      then floor(points_after::numeric / threshold_value)::integer else 0 end;
    dismissal_mode := upper(coalesce(event_row.rule_outcome ->> 'dismissalMode', 'NONE'));
    select count(*)::integer into same_match_count
    from public.pachanga_competition_disciplinary_events prior_events
    join public.pachanga_competition_disciplinary_event_revisions prior_revisions
      on prior_revisions.id = prior_events.current_revision_id
    where prior_events.cycle_id = target_cycle_id
      and prior_events.player_profile_id = target_player_profile_id
      and prior_events.canonical_match_id = event_row.canonical_match_id
      and prior_events.status = 'active'
      and prior_revisions.event_status = 'active'
      and prior_revisions.card_type_code = event_row.card_type_code
      and (prior_events.server_sequence, prior_events.id)
        <= (event_row.server_sequence, event_row.id);

    desired_outcome := 'NO_SANCTION';
    desired_unit_type := null;
    desired_units := null;
    provisional_units := 0;
    minimum_units := null;
    maximum_units := null;
    public_category := coalesce(event_row.public_reason_category, 'dismissal');
    if dismissal_mode = 'DIRECT' then
      desired_outcome := upper(coalesce(event_row.rule_outcome ->> 'dismissalOutcome', 'NO_SANCTION'));
      desired_unit_type := upper(nullif(event_row.rule_outcome ->> 'dismissalUnitType', ''));
      desired_units := nullif(event_row.rule_outcome ->> 'dismissalUnits', '')::integer;
      provisional_units := coalesce(nullif(event_row.rule_outcome ->> 'provisionalUnits', '')::integer, 0);
      minimum_units := nullif(event_row.rule_outcome ->> 'minimumUnits', '')::integer;
      maximum_units := nullif(event_row.rule_outcome ->> 'maximumUnits', '')::integer;
    elsif dismissal_mode = 'SECOND_CARD'
      and same_match_count = coalesce(
        nullif(event_row.rule_outcome ->> 'dismissalThresholdInMatch', '')::integer, 2
      ) then
      desired_outcome := upper(coalesce(event_row.rule_outcome ->> 'dismissalOutcome', 'NO_SANCTION'));
      desired_unit_type := upper(nullif(event_row.rule_outcome ->> 'dismissalUnitType', ''));
      desired_units := nullif(event_row.rule_outcome ->> 'dismissalUnits', '')::integer;
    elsif hit_after > hit_before then
      desired_outcome := upper(coalesce(event_row.rule_outcome ->> 'accumulationOutcome', 'NO_SANCTION'));
      desired_unit_type := upper(nullif(event_row.rule_outcome ->> 'accumulationUnitType', ''));
      desired_units := nullif(event_row.rule_outcome ->> 'accumulationUnits', '')::integer;
      public_category := coalesce(event_row.public_reason_category, 'accumulation');
    end if;

    select * into existing_sanction
    from public.pachanga_competition_sanctions sanctions
    where sanctions.source_event_id = event_row.id
    for update;
    sanction_exists := found;

    if desired_outcome = 'NO_SANCTION' then
      if sanction_exists
         and existing_sanction.status not in ('cancelled', 'overturned', 'no_sanction') then
        if existing_sanction.status = 'served' or exists (
          select 1 from public.pachanga_competition_sanction_service_events service
          where service.sanction_id = existing_sanction.id
            and service.event_type = 'SERVED'
            and not exists (
              select 1 from public.pachanga_competition_sanction_service_events reversals
              where reversals.reverses_service_event_id = service.id
            )
        ) then raise exception 'DISCIPLINE_SERVICE_REVERSAL_REQUIRED' using errcode = 'PT409'; end if;
        internal_operation_id := gen_random_uuid();
        insert into public.pachanga_competition_sanction_revisions(
          sanction_id, version, previous_revision_id, status, sanction_outcome,
          unit_type, total_units, remaining_units, public_reason_category,
          public_summary, rule_article, decision_factors, decision_reason_private,
          operation_id, created_by
        ) values (
          existing_sanction.id, existing_sanction.revision + 1,
          existing_sanction.current_revision_id, 'cancelled', existing_sanction.sanction_outcome,
          existing_sanction.unit_type, existing_sanction.total_units,
          existing_sanction.remaining_units, public_category, '', null,
          jsonb_build_object('reason', 'source_event_reconciled'), left(target_reason, 4000),
          internal_operation_id, target_actor_id
        ) returning id into sanction_revision_id;
        update public.pachanga_competition_sanctions set
          status = 'cancelled', current_revision_id = sanction_revision_id,
          revision = revision + 1,
          server_sequence = nextval('private.pachanga_competition_sequence'),
          updated_at = clock_timestamp()
        where id = existing_sanction.id;
        update public.pachanga_competition_sanction_proposals proposals set
          status = 'withdrawn', revision = revision + 1,
          server_sequence = nextval('private.pachanga_competition_sequence'),
          updated_at = clock_timestamp()
        where proposals.sanction_id = existing_sanction.id
          and proposals.status in ('pending', 'under_review');
        changed_count := changed_count + 1;
      end if;
      continue;
    end if;

    if desired_outcome not in (
      'FIXED_SANCTION', 'PROVISIONAL_SANCTION', 'COMMITTEE_REQUIRED', 'SANCTION_RANGE'
    ) or desired_unit_type not in (
      'MATCHES', 'ROUNDS', 'WEEKS', 'STAGE', 'COMPETITION_EXPULSION'
    ) then raise exception 'DISCIPLINE_SANCTION_RULE_INVALID' using errcode = '22023'; end if;

    if desired_outcome in ('COMMITTEE_REQUIRED', 'SANCTION_RANGE') then
      desired_units := greatest(provisional_units, 0);
      desired_status := case when provisional_units > 0 then 'provisional' else 'under_review' end;
    elsif desired_outcome = 'PROVISIONAL_SANCTION' then
      desired_units := coalesce(desired_units, provisional_units, 1);
      desired_status := 'provisional';
    else
      desired_units := coalesce(desired_units, 1);
      desired_status := 'active';
    end if;
    if desired_units < 0 then
      raise exception 'DISCIPLINE_SANCTION_RULE_INVALID' using errcode = '22023';
    end if;

    if not sanction_exists then
      internal_operation_id := gen_random_uuid();
      insert into public.pachanga_competition_sanctions(
        competition_id, cycle_id, rule_revision_id, source_event_id,
        target_type, player_profile_id, sanction_outcome, status,
        unit_type, total_units, remaining_units, creation_operation_id, created_by
      ) values (
        event_row.competition_id, target_cycle_id, event_row.rule_revision_id, event_row.id,
        'PLAYER', target_player_profile_id, desired_outcome, desired_status,
        desired_unit_type, desired_units, desired_units, internal_operation_id, target_actor_id
      ) returning id into sanction_id;
      internal_operation_id := gen_random_uuid();
      insert into public.pachanga_competition_sanction_revisions(
        sanction_id, version, status, sanction_outcome, unit_type,
        total_units, remaining_units, public_reason_category, public_summary,
        rule_article, decision_factors, decision_reason_private,
        operation_id, created_by
      ) values (
        sanction_id, 1, desired_status, desired_outcome, desired_unit_type,
        desired_units, desired_units, public_category, event_row.public_summary,
        event_row.rule_outcome ->> 'ruleArticle',
        jsonb_build_object('source', 'rule_engine', 'eventId', event_row.id), '',
        internal_operation_id, target_actor_id
      ) returning id into sanction_revision_id;
      update public.pachanga_competition_sanctions set current_revision_id = sanction_revision_id
      where id = sanction_id;
      if desired_outcome in ('COMMITTEE_REQUIRED', 'SANCTION_RANGE') then
        insert into public.pachanga_competition_sanction_proposals(
          competition_id, sanction_id, source_event_id, status,
          minimum_units, maximum_units, unit_type, rule_article,
          proposal_reason, created_by
        ) values (
          event_row.competition_id, sanction_id, event_row.id, 'under_review',
          coalesce(minimum_units, 0), coalesce(maximum_units, minimum_units, 0),
          desired_unit_type, event_row.rule_outcome ->> 'ruleArticle',
          'Decision required by the active CompetitionRuleRevision.', target_actor_id
        );
      end if;
      changed_count := changed_count + 1;
    end if;
  end loop;

  -- An event annulled or moved away from this player may have left a sanction behind.
  for existing_sanction in
    select sanctions.*
    from public.pachanga_competition_sanctions sanctions
    left join public.pachanga_competition_disciplinary_events events
      on events.id = sanctions.source_event_id
    where sanctions.cycle_id = target_cycle_id
      and sanctions.player_profile_id = target_player_profile_id
      and sanctions.status not in ('cancelled', 'overturned', 'no_sanction')
      and (events.id is null or events.status <> 'active')
    for update of sanctions
  loop
    if existing_sanction.status = 'served' then
      raise exception 'DISCIPLINE_SERVICE_REVERSAL_REQUIRED' using errcode = 'PT409';
    end if;
    internal_operation_id := gen_random_uuid();
    insert into public.pachanga_competition_sanction_revisions(
      sanction_id, version, previous_revision_id, status, sanction_outcome,
      unit_type, total_units, remaining_units, public_reason_category,
      public_summary, decision_factors, decision_reason_private,
      operation_id, created_by
    ) values (
      existing_sanction.id, existing_sanction.revision + 1,
      existing_sanction.current_revision_id, 'cancelled', existing_sanction.sanction_outcome,
      existing_sanction.unit_type, existing_sanction.total_units,
      existing_sanction.remaining_units, 'administrative', '',
      jsonb_build_object('reason', 'source_event_inactive'), left(target_reason, 4000),
      internal_operation_id, target_actor_id
    ) returning id into sanction_revision_id;
    update public.pachanga_competition_sanctions set
      status = 'cancelled', current_revision_id = sanction_revision_id,
      revision = revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = existing_sanction.id;
    changed_count := changed_count + 1;
  end loop;
  return changed_count;
end;
$$;

revoke all on function private.pachanga_competition_discipline_reconcile_sanctions_v1(
  uuid, uuid, uuid, text
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_rebuild_player_state_v1(
  target_cycle_id uuid,
  target_player_profile_id uuid
)
returns text
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare selected_competition_id uuid;
declare cards jsonb;
declare selected_sanction public.pachanga_competition_sanctions%rowtype;
declare selected_reason text;
declare selected_name text;
declare selected_avatar text;
declare status_value text := 'AVAILABLE';
declare remaining_value integer := 0;
declare unit_value text;
declare source_sequence bigint := 0;
declare checksum_value text;
begin
  select cycles.competition_id into selected_competition_id
  from public.pachanga_competition_disciplinary_cycles cycles
  where cycles.id = target_cycle_id;
  select profiles.display_name, profiles.avatar into selected_name, selected_avatar
  from public.pachanga_player_profiles profiles where profiles.id = target_player_profile_id;
  select coalesce(jsonb_object_agg(counters.card_type_code, jsonb_build_object(
    'events', counters.active_event_count,
    'points', counters.accumulation_points,
    'thresholdHits', counters.threshold_hits
  ) order by counters.card_type_code), '{}'::jsonb) into cards
  from public.pachanga_competition_disciplinary_counters counters
  where counters.cycle_id = target_cycle_id
    and counters.player_profile_id = target_player_profile_id;
  select * into selected_sanction
  from public.pachanga_competition_sanctions sanctions
  where sanctions.cycle_id = target_cycle_id
    and sanctions.player_profile_id = target_player_profile_id
    and sanctions.status in ('active', 'provisional', 'under_review')
    and coalesce(sanctions.remaining_units, 0) > 0
  order by case sanctions.status when 'active' then 1 when 'provisional' then 2 else 3 end,
    sanctions.server_sequence desc, sanctions.id desc
  limit 1;
  if found then
    status_value := case selected_sanction.status
      when 'active' then case when selected_sanction.suspensive_hold then 'AVAILABLE' else 'SUSPENDED' end
      when 'provisional' then case when selected_sanction.suspensive_hold then 'AVAILABLE' else 'PROVISIONAL' end
      else 'UNDER_REVIEW' end;
    remaining_value := selected_sanction.remaining_units;
    unit_value := selected_sanction.unit_type;
    source_sequence := selected_sanction.server_sequence;
    select revisions.public_reason_category into selected_reason
    from public.pachanga_competition_sanction_revisions revisions
    where revisions.id = selected_sanction.current_revision_id;
  else
    select coalesce(max(counters.server_sequence), 0) into source_sequence
    from public.pachanga_competition_disciplinary_counters counters
    where counters.cycle_id = target_cycle_id
      and counters.player_profile_id = target_player_profile_id;
  end if;
  checksum_value := encode(extensions.digest(convert_to(jsonb_build_object(
    'cycleId', target_cycle_id, 'playerProfileId', target_player_profile_id,
    'cards', cards, 'status', status_value, 'remaining', remaining_value,
    'unitType', unit_value, 'reason', selected_reason, 'sourceSequence', source_sequence
  )::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.pachanga_competition_discipline_player_states(
    competition_id, cycle_id, player_profile_id, display_snapshot,
    card_summary, sanction_status, remaining_units, unit_type,
    public_reason_category, source_server_sequence, state_checksum
  ) values (
    selected_competition_id, target_cycle_id, target_player_profile_id,
    jsonb_strip_nulls(jsonb_build_object('displayName', selected_name, 'avatar', selected_avatar)),
    cards, status_value, remaining_value, unit_value,
    selected_reason, source_sequence, checksum_value
  ) on conflict (cycle_id, player_profile_id) do update set
    display_snapshot = excluded.display_snapshot,
    card_summary = excluded.card_summary,
    sanction_status = excluded.sanction_status,
    remaining_units = excluded.remaining_units,
    unit_type = excluded.unit_type,
    public_reason_category = excluded.public_reason_category,
    source_server_sequence = excluded.source_server_sequence,
    state_checksum = excluded.state_checksum,
    revision = public.pachanga_competition_discipline_player_states.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp();

  update public.pachanga_competition_match_sheets sheets set
    discipline_validation_status = case when status_value in ('SUSPENDED', 'PROVISIONAL')
      then 'BLOCKED' else 'STALE' end,
    revision = sheets.revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where exists (
      select 1
      from public.pachanga_competition_match_squads squads
      join public.pachanga_competition_match_squad_members members
        on members.squad_revision_id = squads.current_revision_id
      join public.pachanga_competition_match_contexts contexts
        on contexts.id = squads.competition_match_context_id
      where squads.canonical_match_id = sheets.canonical_match_id
        and members.player_profile_id = target_player_profile_id
        and squads.status = 'locked'
        and contexts.competition_id = selected_competition_id
        and contexts.status not in ('official', 'played', 'cancelled', 'retired')
    );
  return checksum_value;
end;
$$;

revoke all on function private.pachanga_competition_discipline_rebuild_player_state_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_snapshot_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_canonical_match_id uuid default null,
  target_player_profile_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare cycles_snapshot jsonb;
declare events_snapshot jsonb;
declare counters_snapshot jsonb;
declare sanctions_snapshot jsonb;
declare service_snapshot jsonb;
declare appeals_snapshot jsonb;
declare states_snapshot jsonb;
declare match_players_snapshot jsonb;
declare catalog_snapshot jsonb;
declare match_context_snapshot jsonb;
declare latest_sequence bigint;
begin
  select coalesce((
    select jsonb_build_object(
      'id', contexts.id,
      'canonicalMatchId', contexts.canonical_match_id,
      'status', contexts.status,
      'revision', contexts.revision,
      'serverSequence', contexts.server_sequence,
      'scheduledStart', contexts.scheduled_start,
      'timezone', contexts.timezone,
      'venueLabel', contexts.venue_label,
      'homeEntryId', contexts.home_entry_id,
      'awayEntryId', contexts.away_entry_id,
      'ruleRevisionId', contexts.rule_revision_id
    )
    from public.pachanga_competition_match_contexts contexts
    where contexts.competition_id = target_competition_id
      and contexts.canonical_match_id = target_canonical_match_id
      and contexts.status <> 'retired'
    order by contexts.server_sequence desc, contexts.id desc
    limit 1
  ), '{}'::jsonb) into match_context_snapshot;

  select coalesce((
    select jsonb_build_object(
      'ruleRevisionId', catalogs.rule_revision_id,
      'policyVersion', catalogs.policy_version,
      'cardTypes', catalogs.card_type_catalog,
      'cyclePolicy', catalogs.cycle_policy,
      'sanctionPolicy', catalogs.sanction_policy,
      'appealPolicy', catalogs.appeal_policy,
      'publicReasonCategories', catalogs.public_reason_categories,
      'checksum', catalogs.checksum,
      'serverSequence', catalogs.server_sequence
    )
    from public.pachanga_competition_discipline_rule_catalogs catalogs
    where catalogs.competition_id = target_competition_id
      and (
        target_canonical_match_id is null
        or catalogs.rule_revision_id = (
          select contexts.rule_revision_id
          from public.pachanga_competition_match_contexts contexts
          where contexts.competition_id = target_competition_id
            and contexts.canonical_match_id = target_canonical_match_id
            and contexts.status <> 'retired'
          order by contexts.server_sequence desc, contexts.id desc
          limit 1
        )
      )
    order by catalogs.server_sequence desc, catalogs.rule_revision_id desc
    limit 1
  ), '{}'::jsonb) into catalog_snapshot;

  select coalesce(jsonb_agg(jsonb_build_object(
    'playerProfileId', players.player_profile_id,
    'entryId', players.entry_id,
    'displayName', players.display_name,
    'avatar', players.avatar,
    'side', players.side,
    'squadStatus', players.squad_status
  ) order by players.side, players.display_name, players.player_profile_id), '[]'::jsonb)
  into match_players_snapshot
  from (
    select distinct on (members.player_profile_id)
      members.player_profile_id, squads.entry_id, profiles.display_name,
      profiles.avatar, squads.side, squads.status as squad_status,
      squads.server_sequence, members.id
    from public.pachanga_competition_match_squads squads
    join public.pachanga_competition_match_squad_members members
      on members.squad_revision_id = squads.current_revision_id
    join public.pachanga_player_profiles profiles on profiles.id = members.player_profile_id
    where target_canonical_match_id is not null
      and squads.canonical_match_id = target_canonical_match_id
      and squads.status in ('submitted', 'validated', 'locked')
    order by members.player_profile_id, squads.server_sequence desc, members.id desc
  ) players;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', cycles.id, 'editionId', cycles.edition_id, 'stageId', cycles.stage_id,
    'groupId', cycles.competition_group_id, 'ruleRevisionId', cycles.rule_revision_id,
    'scopeType', cycles.scope_type, 'status', cycles.status,
    'carryPolicy', cycles.carry_policy, 'effectiveFrom', cycles.effective_from,
    'effectiveUntil', cycles.effective_until, 'revision', cycles.revision,
    'serverSequence', cycles.server_sequence
  ) order by cycles.server_sequence desc, cycles.id desc), '[]'::jsonb)
  into cycles_snapshot
  from (
    select target_cycles.*
    from public.pachanga_competition_disciplinary_cycles target_cycles
    where target_cycles.competition_id = target_competition_id
    order by target_cycles.server_sequence desc, target_cycles.id desc
    limit 100
  ) cycles;

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', events.id, 'canonicalMatchId', events.canonical_match_id,
    'matchContextId', events.competition_match_context_id,
    'cycleId', events.cycle_id, 'playerProfileId', events.player_profile_id,
    'playerDisplay', jsonb_build_object(
      'displayName', profiles.display_name, 'avatar', profiles.avatar
    ),
    'entryId', events.entry_id, 'cardTypeCode', revisions.card_type_code,
    'visualType', revisions.rule_outcome ->> 'visualType',
    'label', revisions.rule_outcome ->> 'label',
    'context', revisions.event_context, 'minute', revisions.match_minute,
    'period', revisions.period_code, 'status', revisions.event_status,
    'publicReasonCategory', revisions.public_reason_category,
    'publicSummary', revisions.public_summary,
    'temporaryDismissal', revisions.rule_outcome -> 'temporaryDismissal',
    'revision', events.revision, 'revisionVersion', revisions.version,
    'serverSequence', events.server_sequence,
    'sanction', case when sanctions.id is null then null else jsonb_build_object(
      'id', sanctions.id, 'status', sanctions.status,
      'outcome', sanctions.sanction_outcome,
      'remainingUnits', sanctions.remaining_units, 'unitType', sanctions.unit_type
    ) end
  )) order by events.server_sequence desc, events.id desc), '[]'::jsonb)
  into events_snapshot
  from (
    select target_events.*
    from public.pachanga_competition_disciplinary_events target_events
    where target_events.competition_id = target_competition_id
      and (target_canonical_match_id is null
        or target_events.canonical_match_id = target_canonical_match_id)
      and (target_player_profile_id is null
        or target_events.player_profile_id = target_player_profile_id)
    order by target_events.server_sequence desc, target_events.id desc
    limit 500
  ) events
  join public.pachanga_competition_disciplinary_event_revisions revisions
    on revisions.id = events.current_revision_id
  join public.pachanga_player_profiles profiles on profiles.id = events.player_profile_id
  left join public.pachanga_competition_sanctions sanctions
    on sanctions.source_event_id = events.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', counters.id, 'cycleId', counters.cycle_id,
    'playerProfileId', counters.player_profile_id,
    'cardTypeCode', counters.card_type_code,
    'eventCount', counters.active_event_count,
    'points', counters.accumulation_points,
    'thresholdHits', counters.threshold_hits,
    'revision', counters.revision,
    'serverSequence', counters.server_sequence,
    'checksum', counters.state_checksum
  ) order by counters.server_sequence desc, counters.id desc), '[]'::jsonb)
  into counters_snapshot
  from public.pachanga_competition_disciplinary_counters counters
  where counters.competition_id = target_competition_id
    and (target_player_profile_id is null
      or counters.player_profile_id = target_player_profile_id);

  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', sanctions.id, 'cycleId', sanctions.cycle_id,
    'sourceEventId', sanctions.source_event_id,
    'targetType', sanctions.target_type,
    'playerProfileId', sanctions.player_profile_id,
    'entryId', sanctions.entry_id, 'outcome', sanctions.sanction_outcome,
    'status', sanctions.status, 'unitType', sanctions.unit_type,
    'totalUnits', sanctions.total_units, 'remainingUnits', sanctions.remaining_units,
    'suspensiveHold', sanctions.suspensive_hold,
    'publicReasonCategory', revisions.public_reason_category,
    'publicSummary', revisions.public_summary,
    'ruleArticle', revisions.rule_article,
    'canAppeal', target_actor_id is not null and exists (
      select 1 from public.pachanga_player_profiles target_profiles
      where target_profiles.id = sanctions.player_profile_id
        and target_profiles.user_id = target_actor_id
    ),
    'proposal', case when proposals.id is null then null else jsonb_build_object(
      'id', proposals.id, 'status', proposals.status,
      'minimumUnits', proposals.minimum_units,
      'maximumUnits', proposals.maximum_units,
      'unitType', proposals.unit_type
    ) end,
    'revision', sanctions.revision, 'serverSequence', sanctions.server_sequence
  )) order by sanctions.server_sequence desc, sanctions.id desc), '[]'::jsonb)
  into sanctions_snapshot
  from (
    select target_sanctions.*
    from public.pachanga_competition_sanctions target_sanctions
    where target_sanctions.competition_id = target_competition_id
      and (target_player_profile_id is null
        or target_sanctions.player_profile_id = target_player_profile_id)
      and (target_canonical_match_id is null or exists (
        select 1
        from public.pachanga_competition_disciplinary_events source_events
        where source_events.id = target_sanctions.source_event_id
          and source_events.canonical_match_id = target_canonical_match_id
      ))
    order by target_sanctions.server_sequence desc, target_sanctions.id desc
    limit 500
  ) sanctions
  join public.pachanga_competition_sanction_revisions revisions
    on revisions.id = sanctions.current_revision_id
  left join public.pachanga_competition_sanction_proposals proposals
    on proposals.sanction_id = sanctions.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', service.id, 'sanctionId', service.sanction_id,
    'canonicalMatchId', service.canonical_match_id,
    'eventType', service.event_type, 'units', service.units,
    'remainingBefore', service.remaining_before,
    'remainingAfter', service.remaining_after,
    'reversesServiceEventId', service.reverses_service_event_id,
    'serverSequence', service.server_sequence, 'createdAt', service.created_at
  ) order by service.server_sequence desc, service.id desc), '[]'::jsonb)
  into service_snapshot
  from (
    select target_service.*
    from public.pachanga_competition_sanction_service_events target_service
    where target_service.competition_id = target_competition_id
      and (target_canonical_match_id is null
        or target_service.canonical_match_id = target_canonical_match_id)
      and (target_player_profile_id is null or exists (
        select 1 from public.pachanga_competition_sanctions target_sanctions
        where target_sanctions.id = target_service.sanction_id
          and target_sanctions.player_profile_id = target_player_profile_id
      ))
    order by target_service.server_sequence desc, target_service.id desc
    limit 500
  ) service;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', appeals.id, 'sanctionId', appeals.sanction_id,
    'status', appeals.status, 'deadlineAt', appeals.deadline_at,
    'suspensiveEffect', appeals.suspensive_effect,
    'canWithdraw', target_actor_id is not null
      and appeals.appellant_user_id = target_actor_id
      and appeals.status in ('submitted', 'admissible', 'under_review'),
    'revision', appeals.revision, 'serverSequence', appeals.server_sequence
  ) order by appeals.server_sequence desc, appeals.id desc), '[]'::jsonb)
  into appeals_snapshot
  from (
    select target_appeals.*
    from public.pachanga_competition_sanction_appeals target_appeals
    join public.pachanga_competition_sanctions target_sanctions
      on target_sanctions.id = target_appeals.sanction_id
    where target_appeals.competition_id = target_competition_id
      and (target_player_profile_id is null
        or target_sanctions.player_profile_id = target_player_profile_id)
      and (
        target_appeals.appellant_user_id = target_actor_id
        or private.pachanga_competition_can_v1(
          target_competition_id, target_actor_id, 'appeals_manage'
        )
        or private.pachanga_competition_can_v1(
          target_competition_id, target_actor_id, 'discipline_review'
        )
      )
    order by target_appeals.server_sequence desc, target_appeals.id desc
    limit 200
  ) appeals;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', states.id, 'cycleId', states.cycle_id,
    'playerProfileId', states.player_profile_id,
    'display', states.display_snapshot, 'cards', states.card_summary,
    'status', states.sanction_status, 'remainingUnits', states.remaining_units,
    'unitType', states.unit_type,
    'publicReasonCategory', states.public_reason_category,
    'revision', states.revision, 'serverSequence', states.server_sequence,
    'updatedAt', states.updated_at
  ) order by states.server_sequence desc, states.id desc), '[]'::jsonb)
  into states_snapshot
  from public.pachanga_competition_discipline_player_states states
  where states.competition_id = target_competition_id
    and (target_player_profile_id is null
      or states.player_profile_id = target_player_profile_id);

  select greatest(
    coalesce((select max(server_sequence) from public.pachanga_competition_disciplinary_events
      where competition_id = target_competition_id), 0),
    coalesce((select max(server_sequence) from public.pachanga_competition_sanctions
      where competition_id = target_competition_id), 0),
    coalesce((select max(server_sequence) from public.pachanga_competition_sanction_appeals
      where competition_id = target_competition_id), 0)
  ) into latest_sequence;

  return jsonb_build_object(
    'competitionId', target_competition_id,
    'revision', coalesce((
      select competitions.discipline_revision
      from public.pachanga_competitions competitions
      where competitions.id = target_competition_id
    ), 0),
    'filters', jsonb_strip_nulls(jsonb_build_object(
      'canonicalMatchId', target_canonical_match_id,
      'playerProfileId', target_player_profile_id
    )),
    'ruleCatalog', catalog_snapshot,
    'matchContext', match_context_snapshot,
    'matchPlayers', match_players_snapshot,
    'flags', private.pachanga_competition_discipline_flags_v1(),
    'permissions', jsonb_build_object(
      'read', private.pachanga_competition_can_v1(
        target_competition_id, target_actor_id, 'discipline_read'
      ),
      'manage', private.pachanga_competition_can_v1(
        target_competition_id, target_actor_id, 'discipline_manage'
      ),
      'review', private.pachanga_competition_can_v1(
        target_competition_id, target_actor_id, 'discipline_review'
      ),
      'manageAppeals', private.pachanga_competition_can_v1(
        target_competition_id, target_actor_id, 'appeals_manage'
      )
    ),
    'cycles', cycles_snapshot, 'events', events_snapshot,
    'counters', counters_snapshot, 'sanctions', sanctions_snapshot,
    'serviceEvents', service_snapshot, 'appeals', appeals_snapshot,
    'playerStates', states_snapshot,
    'health', jsonb_build_object(
      'counterRows', jsonb_array_length(counters_snapshot),
      'activeSanctions', (
        select count(*) from public.pachanga_competition_sanctions sanctions
        where sanctions.competition_id = target_competition_id
          and sanctions.status in ('active', 'provisional', 'under_review')
      ),
      'pendingAppeals', (
        select count(*) from public.pachanga_competition_sanction_appeals appeals
        where appeals.competition_id = target_competition_id
          and appeals.status in ('submitted', 'admissible', 'under_review')
      ),
      'latestServerSequence', latest_sequence
    )
  );
end;
$$;

revoke all on function private.pachanga_competition_discipline_snapshot_v1(
  uuid, uuid, uuid, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_invalidations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare invalidation jsonb;
declare invalidation_sequence bigint;
declare saved_invalidations jsonb := '[]'::jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare response jsonb;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if jsonb_typeof(coalesce(target_invalidations, '[]'::jsonb)) <> 'array' then
    raise exception 'DISCIPLINE_INVALIDATIONS_INVALID' using errcode = '22023';
  end if;
  for invalidation in select value
    from jsonb_array_elements(coalesce(target_invalidations, '[]'::jsonb))
  loop
    invalidation_sequence := case when jsonb_array_length(saved_invalidations) = 0
      then target_server_sequence else nextval('private.pachanga_competition_sequence') end;
    insert into public.pachanga_competition_invalidations(
      server_sequence, competition_id, organizer_group_id, organizer_club_id,
      entity_type, entity_id, revision, created_at
    ) values (
      invalidation_sequence, target_competition_id,
      competition_row.organizer_group_id, competition_row.organizer_club_id,
      left(coalesce(invalidation ->> 'entityType', 'competition_discipline'), 120),
      left(coalesce(invalidation ->> 'entityId', target_aggregate_id::text), 240),
      coalesce(nullif(invalidation ->> 'revision', '')::bigint, target_confirmed_revision),
      confirmed_at
    );
    saved_invalidations := saved_invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', left(coalesce(invalidation ->> 'entityType', 'competition_discipline'), 120),
      'entityId', left(coalesce(invalidation ->> 'entityId', target_aggregate_id::text), 240),
      'revision', coalesce(nullif(invalidation ->> 'revision', '')::bigint, target_confirmed_revision),
      'serverSequence', invalidation_sequence
    ));
  end loop;
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', saved_invalidations
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated',
    'competition_discipline', target_aggregate_id::text,
    target_competition_id, target_action, target_confirmed_revision,
    target_server_sequence, left(target_action, 120),
    coalesce(target_event_payload, '{}'::jsonb), confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    target_operation_id, target_actor_id, 'authenticated', target_action,
    'competition_discipline', target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence,
    coalesce(target_client_metadata, '{}'::jsonb), response, confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_competition_discipline_store_command_v1(
  uuid, uuid, text, uuid, uuid, bigint, bigint, text, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_guard_locked_squads_v1(
  target_competition_id uuid,
  target_player_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare candidate record;
begin
  if target_player_profile_id is null then return; end if;
  for candidate in
    select squads.id, squads.status, squads.canonical_match_id
    from public.pachanga_competition_match_squads squads
    join public.pachanga_competition_match_squad_members members
      on members.squad_revision_id = squads.current_revision_id
    join public.pachanga_competition_match_contexts contexts
      on contexts.id = squads.competition_match_context_id
    where contexts.competition_id = target_competition_id
      and contexts.status not in ('official', 'played', 'cancelled', 'retired')
      and members.player_profile_id = target_player_profile_id
      and squads.status in ('submitted', 'validated', 'locked')
    order by squads.id
    for update of squads
  loop
    if candidate.status = 'locked'
       and private.pachanga_competition_player_sanction_applies_v1(
         target_competition_id, target_player_profile_id,
         candidate.canonical_match_id
       ) then
      raise exception 'DISCIPLINE_SANCTION_CONFLICTS_LOCKED_SQUAD'
        using errcode = 'PT409';
    end if;
  end loop;
end;
$$;

revoke all on function private.pachanga_competition_discipline_guard_locked_squads_v1(
  uuid, uuid
) from public, anon, authenticated;

create or replace function public.command_pachanga_competition_discipline_v1(
  operation_id uuid,
  competition_id uuid,
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
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare normalized_action text := lower(trim(command_action));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare competition_row public.pachanga_competitions%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare event_row public.pachanga_competition_disciplinary_events%rowtype;
declare old_event_revision public.pachanga_competition_disciplinary_event_revisions%rowtype;
declare sanction_row public.pachanga_competition_sanctions%rowtype;
declare proposal_row public.pachanga_competition_sanction_proposals%rowtype;
declare appeal_row public.pachanga_competition_sanction_appeals%rowtype;
declare service_row public.pachanga_competition_sanction_service_events%rowtype;
declare cycle_row public.pachanga_competition_disciplinary_cycles%rowtype;
declare catalog_row public.pachanga_competition_discipline_rule_catalogs%rowtype;
declare selected_cycle_id uuid;
declare selected_player_id uuid;
declare previous_player_id uuid;
declare selected_entry_id uuid;
declare selected_card_code text;
declare selected_context text;
declare selected_minute integer;
declare selected_period text;
declare selected_public_category text;
declare selected_public_summary text;
declare selected_private_reason text;
declare selected_evidence jsonb;
declare rule_outcome jsonb;
declare event_revision_id uuid;
declare sanction_revision_id uuid;
declare appeal_revision_id uuid;
declare confirmed_revision bigint;
declare sequence_value bigint;
declare snapshot jsonb;
declare invalidations jsonb := '[]'::jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare affected_match_id uuid;
declare affected_player_id uuid;
declare counter_checksum text;
declare state_checksum text;
declare loop_player uuid;
declare changed_count integer := 0;
declare new_cycle_id uuid;
declare policy jsonb;
declare target_status text;
declare target_units integer;
declare target_unit_type text;
declare deadline_hours integer;
declare suspensive_effect boolean;
declare remaining_before integer;
declare remaining_after integer;
declare next_revision integer;
declare own_profile_id uuid;
declare source_round_number integer;
declare target_round_number integer;
declare source_entry_id uuid;
declare active_service_id uuid;
declare appeal_policy jsonb;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if operation_id is null or competition_id is null or aggregate_id is null
     or expected_revision is null or expected_revision < 0 then
    raise exception 'DISCIPLINE_COMMAND_ENVELOPE_INVALID' using errcode = '22023';
  end if;
  if normalized_action not in (
    'event.record', 'event.correct', 'event.annul', 'counter.rebuild',
    'cycle.reset', 'sanction.decide', 'service.record', 'service.reverse',
    'appeal.submit', 'appeal.transition', 'appeal.withdraw'
  ) then raise exception 'DISCIPLINE_ACTION_NOT_AVAILABLE' using errcode = '0A000'; end if;
  if jsonb_typeof(payload) <> 'object' or pg_column_size(payload) > 32768
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(coalesce(client_metadata, '{}'::jsonb)) > 8192 then
    raise exception 'DISCIPLINE_COMMAND_PAYLOAD_INVALID' using errcode = '22023';
  end if;
  if payload ?| array[
    'rating', 'ratings', 'ratingVotes', 'facets', 'grl', 'seasonScore',
    'counter', 'counterValue', 'serverSequence', 'confirmedRevision',
    'actorId', 'createdBy', 'reporterId', 'serviceRole'
  ] then raise exception 'DISCIPLINE_SERVER_FIELDS_FORBIDDEN' using errcode = '22023'; end if;

  select * into competition_row
  from public.pachanga_competitions competitions
  where competitions.id = competition_id
  for update;
  if not found then raise exception 'COMPETITION_NOT_FOUND' using errcode = 'P0002'; end if;

  request_hash := private.pachanga_competition_discipline_request_hash_v1(
    competition_id, normalized_action, aggregate_id, expected_revision, payload
  );
  replay := private.pachanga_competition_discipline_replay_v1(
    operation_id, actor_id, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  if competition_row.discipline_revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;

  if normalized_action = 'event.record' then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, false);
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_manage') then
      raise exception 'COMPETITION_DISCIPLINE_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if payload - array[
      'playerProfileId', 'cardTypeCode', 'context', 'minute', 'period',
      'publicReasonCategory', 'publicSummary', 'evidenceRefs', 'privateNotes'
    ] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_EVENT_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into context_row
    from public.pachanga_competition_match_contexts contexts
    where contexts.canonical_match_id = aggregate_id
      and contexts.competition_id = competition_id
      and contexts.status <> 'retired'
    order by contexts.server_sequence desc, contexts.id desc
    limit 1 for update;
    if not found then raise exception 'DISCIPLINE_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
    selected_player_id := nullif(payload ->> 'playerProfileId', '')::uuid;
    selected_card_code := upper(trim(coalesce(payload ->> 'cardTypeCode', '')));
    selected_context := lower(trim(coalesce(payload ->> 'context', 'in_match')));
    selected_minute := nullif(payload ->> 'minute', '')::integer;
    selected_period := nullif(trim(payload ->> 'period'), '');
    selected_public_category := nullif(trim(payload ->> 'publicReasonCategory'), '');
    selected_public_summary := left(coalesce(payload ->> 'publicSummary', ''), 500);
    selected_private_reason := left(coalesce(payload ->> 'privateNotes', ''), 4000);
    selected_evidence := coalesce(payload -> 'evidenceRefs', '[]'::jsonb);
    if selected_player_id is null or selected_card_code = ''
       or selected_context not in ('pre_match', 'in_match', 'interval', 'post_match', 'venue')
       or (selected_context = 'in_match' and selected_minute is null)
       or selected_minute is not null and selected_minute not between 0 and 300
       or jsonb_typeof(selected_evidence) <> 'array'
       or jsonb_array_length(selected_evidence) > 20
       or pg_column_size(selected_evidence) > 16000 then
      raise exception 'DISCIPLINE_EVENT_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    catalog_row := private.pachanga_competition_discipline_ensure_catalog_v1(
      competition_id, context_row.rule_revision_id, actor_id
    );
    if selected_public_category is not null and not exists (
      select 1 from jsonb_array_elements_text(catalog_row.public_reason_categories) category
      where category = selected_public_category
    ) then raise exception 'DISCIPLINE_PUBLIC_REASON_NOT_ALLOWED' using errcode = '22023'; end if;
    rule_outcome := private.pachanga_competition_discipline_rule_outcome_v1(
      context_row.rule_revision_id, selected_card_code
    );
    selected_entry_id := private.pachanga_competition_discipline_match_entry_v1(
      aggregate_id, selected_player_id
    );
    selected_cycle_id := private.pachanga_competition_discipline_resolve_cycle_v1(
      context_row.id, actor_id
    );
    perform 1 from public.pachanga_competition_disciplinary_cycles cycles
    where cycles.id = selected_cycle_id for update;
    insert into public.pachanga_competition_disciplinary_events(
      competition_id, canonical_match_id, competition_match_context_id,
      match_sheet_id, cycle_id, rule_revision_id, player_profile_id, entry_id,
      current_card_type_code, creation_operation_id, created_by
    ) values (
      competition_id, aggregate_id, context_row.id,
      (select sheets.id from public.pachanga_competition_match_sheets sheets
        where sheets.canonical_match_id = aggregate_id),
      selected_cycle_id, context_row.rule_revision_id, selected_player_id,
      selected_entry_id, selected_card_code, operation_id, actor_id
    ) returning * into event_row;
    insert into public.pachanga_competition_disciplinary_event_revisions(
      disciplinary_event_id, version, player_profile_id, entry_id,
      card_type_code, event_context, match_minute, period_code, event_status,
      public_reason_category, public_summary, rule_outcome, correction_reason,
      operation_id, created_by
    ) values (
      event_row.id, 1, selected_player_id, selected_entry_id,
      selected_card_code, selected_context, selected_minute, selected_period, 'active',
      selected_public_category, selected_public_summary, rule_outcome,
      'Initial disciplinary event', operation_id, actor_id
    ) returning id into event_revision_id;
    update public.pachanga_competition_disciplinary_events set
      current_revision_id = event_revision_id
    where id = event_row.id;
    if jsonb_array_length(selected_evidence) > 0 or selected_private_reason <> '' then
      insert into private.pachanga_competition_discipline_evidence(
        competition_id, subject_type, subject_id, evidence_refs,
        private_notes, operation_id, actor_id, server_sequence
      ) values (
        competition_id, 'DISCIPLINARY_EVENT', event_row.id, selected_evidence,
        selected_private_reason, operation_id, actor_id, event_row.server_sequence
      );
    end if;
    counter_checksum := private.pachanga_competition_discipline_rebuild_counters_v1(
      selected_cycle_id, selected_player_id
    );
    changed_count := private.pachanga_competition_discipline_reconcile_sanctions_v1(
      selected_cycle_id, selected_player_id, actor_id, 'Event recorded'
    );
    perform private.pachanga_competition_discipline_guard_locked_squads_v1(
      competition_id, selected_player_id
    );
    state_checksum := private.pachanga_competition_discipline_rebuild_player_state_v1(
      selected_cycle_id, selected_player_id
    );
    confirmed_revision := event_row.revision;
    affected_match_id := aggregate_id;
    affected_player_id := selected_player_id;
    event_payload := jsonb_build_object(
      'eventId', event_row.id, 'cycleId', selected_cycle_id,
      'canonicalMatchId', aggregate_id, 'playerProfileId', selected_player_id,
      'cardTypeCode', selected_card_code, 'counterChecksum', counter_checksum,
      'playerStateChecksum', state_checksum, 'derivedSanctionChanges', changed_count
    );
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'competition_discipline',
        'entityId', competition_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_match',
        'entityId', aggregate_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_player',
        'entityId', selected_player_id, 'revision', confirmed_revision)
    );

  elsif normalized_action in ('event.correct', 'event.annul') then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, false);
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_manage') then
      raise exception 'COMPETITION_DISCIPLINE_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if payload - array[
      'playerProfileId', 'cardTypeCode', 'context', 'minute', 'period',
      'publicReasonCategory', 'publicSummary', 'correctionReason',
      'evidenceRefs', 'privateNotes'
    ] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_EVENT_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into event_row
    from public.pachanga_competition_disciplinary_events events
    where events.id = aggregate_id and events.competition_id = competition_id
    for update;
    if not found then raise exception 'DISCIPLINARY_EVENT_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into old_event_revision
    from public.pachanga_competition_disciplinary_event_revisions revisions
    where revisions.id = event_row.current_revision_id;
    previous_player_id := event_row.player_profile_id;
    selected_cycle_id := event_row.cycle_id;
    perform 1 from public.pachanga_competition_disciplinary_cycles cycles
    where cycles.id = selected_cycle_id for update;
    selected_player_id := case when normalized_action = 'event.annul'
      then old_event_revision.player_profile_id
      else coalesce(nullif(payload ->> 'playerProfileId', '')::uuid,
        old_event_revision.player_profile_id) end;
    selected_card_code := case when normalized_action = 'event.annul'
      then old_event_revision.card_type_code
      else upper(coalesce(nullif(trim(payload ->> 'cardTypeCode'), ''),
        old_event_revision.card_type_code)) end;
    selected_context := case when normalized_action = 'event.annul'
      then old_event_revision.event_context
      else lower(coalesce(nullif(trim(payload ->> 'context'), ''),
        old_event_revision.event_context)) end;
    selected_minute := case when payload ? 'minute'
      then nullif(payload ->> 'minute', '')::integer else old_event_revision.match_minute end;
    selected_period := case when payload ? 'period'
      then nullif(trim(payload ->> 'period'), '') else old_event_revision.period_code end;
    selected_public_category := case when payload ? 'publicReasonCategory'
      then nullif(trim(payload ->> 'publicReasonCategory'), '')
      else old_event_revision.public_reason_category end;
    selected_public_summary := case when payload ? 'publicSummary'
      then left(coalesce(payload ->> 'publicSummary', ''), 500)
      else old_event_revision.public_summary end;
    selected_private_reason := left(coalesce(payload ->> 'correctionReason', ''), 1200);
    selected_evidence := coalesce(payload -> 'evidenceRefs', '[]'::jsonb);
    if length(trim(selected_private_reason)) < 3
       or selected_context not in ('pre_match', 'in_match', 'interval', 'post_match', 'venue')
       or selected_minute is not null and selected_minute not between 0 and 300
       or jsonb_typeof(selected_evidence) <> 'array'
       or jsonb_array_length(selected_evidence) > 20 then
      raise exception 'DISCIPLINE_CORRECTION_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    catalog_row := private.pachanga_competition_discipline_ensure_catalog_v1(
      competition_id, event_row.rule_revision_id, actor_id
    );
    if selected_public_category is not null and not exists (
      select 1 from jsonb_array_elements_text(catalog_row.public_reason_categories) category
      where category = selected_public_category
    ) then raise exception 'DISCIPLINE_PUBLIC_REASON_NOT_ALLOWED' using errcode = '22023'; end if;
    rule_outcome := private.pachanga_competition_discipline_rule_outcome_v1(
      event_row.rule_revision_id, selected_card_code
    );
    selected_entry_id := private.pachanga_competition_discipline_match_entry_v1(
      event_row.canonical_match_id, selected_player_id
    );
    next_revision := event_row.revision + 1;
    insert into public.pachanga_competition_disciplinary_event_revisions(
      disciplinary_event_id, version, previous_revision_id,
      player_profile_id, entry_id, card_type_code, event_context,
      match_minute, period_code, event_status, public_reason_category,
      public_summary, rule_outcome, correction_reason, operation_id, created_by
    ) values (
      event_row.id, next_revision, event_row.current_revision_id,
      selected_player_id, selected_entry_id, selected_card_code, selected_context,
      selected_minute, selected_period,
      case when normalized_action = 'event.annul' then 'annulled' else 'active' end,
      selected_public_category, selected_public_summary, rule_outcome,
      selected_private_reason, operation_id, actor_id
    ) returning id into event_revision_id;
    update public.pachanga_competition_disciplinary_events set
      player_profile_id = selected_player_id, entry_id = selected_entry_id,
      current_card_type_code = selected_card_code,
      status = case when normalized_action = 'event.annul' then 'annulled' else 'active' end,
      current_revision_id = event_revision_id,
      revision = next_revision,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = event_row.id
    returning * into event_row;
    if jsonb_array_length(selected_evidence) > 0
       or coalesce(payload ->> 'privateNotes', '') <> '' then
      insert into private.pachanga_competition_discipline_evidence(
        competition_id, subject_type, subject_id, evidence_refs,
        private_notes, operation_id, actor_id, server_sequence
      ) values (
        competition_id, 'DISCIPLINARY_EVENT', event_row.id, selected_evidence,
        left(coalesce(payload ->> 'privateNotes', ''), 4000),
        operation_id, actor_id, event_row.server_sequence
      );
    end if;
    counter_checksum := private.pachanga_competition_discipline_rebuild_counters_v1(
      selected_cycle_id, previous_player_id
    );
    changed_count := private.pachanga_competition_discipline_reconcile_sanctions_v1(
      selected_cycle_id, previous_player_id, actor_id, selected_private_reason
    );
    perform private.pachanga_competition_discipline_rebuild_player_state_v1(
      selected_cycle_id, previous_player_id
    );
    if selected_player_id <> previous_player_id then
      counter_checksum := private.pachanga_competition_discipline_rebuild_counters_v1(
        selected_cycle_id, selected_player_id
      );
      changed_count := changed_count
        + private.pachanga_competition_discipline_reconcile_sanctions_v1(
          selected_cycle_id, selected_player_id, actor_id, selected_private_reason
        );
      perform private.pachanga_competition_discipline_rebuild_player_state_v1(
        selected_cycle_id, selected_player_id
      );
    end if;
    perform private.pachanga_competition_discipline_guard_locked_squads_v1(
      competition_id, previous_player_id
    );
    if selected_player_id <> previous_player_id then
      perform private.pachanga_competition_discipline_guard_locked_squads_v1(
        competition_id, selected_player_id
      );
    end if;
    confirmed_revision := event_row.revision;
    affected_match_id := event_row.canonical_match_id;
    affected_player_id := selected_player_id;
    event_payload := jsonb_build_object(
      'eventId', event_row.id, 'cycleId', selected_cycle_id,
      'canonicalMatchId', event_row.canonical_match_id,
      'previousPlayerProfileId', previous_player_id,
      'playerProfileId', selected_player_id,
      'cardTypeCode', selected_card_code,
      'status', event_row.status, 'counterChecksum', counter_checksum,
      'derivedSanctionChanges', changed_count
    );
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'competition_discipline',
        'entityId', competition_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_match',
        'entityId', event_row.canonical_match_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_player',
        'entityId', selected_player_id, 'revision', confirmed_revision)
    );

  elsif normalized_action = 'counter.rebuild' then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, false);
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_review')
       and not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_manage') then
      raise exception 'COMPETITION_DISCIPLINE_REVIEWER_REQUIRED' using errcode = '42501';
    end if;
    if payload - array['playerProfileId'] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_REBUILD_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into cycle_row
    from public.pachanga_competition_disciplinary_cycles cycles
    where cycles.id = aggregate_id and cycles.competition_id = competition_id
    for update;
    if not found then raise exception 'DISCIPLINE_CYCLE_NOT_FOUND' using errcode = 'P0002'; end if;
    selected_player_id := nullif(payload ->> 'playerProfileId', '')::uuid;
    for loop_player in
      select distinct events.player_profile_id
      from public.pachanga_competition_disciplinary_events events
      where events.cycle_id = cycle_row.id
        and (selected_player_id is null or events.player_profile_id = selected_player_id)
      union
      select distinct counters.player_profile_id
      from public.pachanga_competition_disciplinary_counters counters
      where counters.cycle_id = cycle_row.id
        and (selected_player_id is null or counters.player_profile_id = selected_player_id)
    loop
      counter_checksum := private.pachanga_competition_discipline_rebuild_counters_v1(
        cycle_row.id, loop_player
      );
      changed_count := changed_count
        + private.pachanga_competition_discipline_reconcile_sanctions_v1(
          cycle_row.id, loop_player, actor_id, 'Authoritative counter rebuild'
        );
      perform private.pachanga_competition_discipline_rebuild_player_state_v1(
        cycle_row.id, loop_player
      );
    end loop;
    update public.pachanga_competition_disciplinary_cycles set
      revision = revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = cycle_row.id returning * into cycle_row;
    confirmed_revision := cycle_row.revision;
    affected_player_id := selected_player_id;
    event_payload := jsonb_build_object(
      'cycleId', cycle_row.id, 'playerProfileId', selected_player_id,
      'lastChecksum', counter_checksum, 'sanctionChanges', changed_count
    );
    invalidations := jsonb_build_array(jsonb_build_object(
      'entityType', 'competition_discipline', 'entityId', competition_id,
      'revision', confirmed_revision
    ));

  elsif normalized_action = 'cycle.reset' then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, false);
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_manage') then
      raise exception 'COMPETITION_DISCIPLINE_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if payload - array['effectiveFrom'] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_CYCLE_RESET_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into cycle_row
    from public.pachanga_competition_disciplinary_cycles cycles
    where cycles.id = aggregate_id and cycles.competition_id = competition_id
    for update;
    if not found then raise exception 'DISCIPLINE_CYCLE_NOT_FOUND' using errcode = 'P0002'; end if;
    if cycle_row.status <> 'active' then
      raise exception 'DISCIPLINE_CYCLE_NOT_ACTIVE' using errcode = 'PT409';
    end if;
    catalog_row := private.pachanga_competition_discipline_ensure_catalog_v1(
      competition_id, cycle_row.rule_revision_id, actor_id
    );
    update public.pachanga_competition_disciplinary_cycles set
      status = 'closed', effective_until = coalesce(
        nullif(payload ->> 'effectiveFrom', '')::timestamptz, clock_timestamp()
      ), revision = revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = cycle_row.id;
    insert into public.pachanga_competition_disciplinary_cycles(
      competition_id, edition_id, stage_id, competition_group_id,
      rule_revision_id, scope_type, carry_policy, effective_from,
      previous_cycle_id, created_by
    ) values (
      competition_id, cycle_row.edition_id, cycle_row.stage_id,
      cycle_row.competition_group_id, cycle_row.rule_revision_id,
      cycle_row.scope_type,
      upper(coalesce(catalog_row.cycle_policy ->> 'carryPolicy', 'RESET')),
      coalesce(nullif(payload ->> 'effectiveFrom', '')::timestamptz, clock_timestamp()),
      cycle_row.id, actor_id
    ) returning id into new_cycle_id;
    if upper(coalesce(catalog_row.cycle_policy ->> 'carryPolicy', 'RESET')) = 'CARRY' then
      insert into public.pachanga_competition_disciplinary_counters(
        competition_id, cycle_id, player_profile_id, card_type_code,
        carried_points, accumulation_points, threshold_hits,
        last_event_server_sequence, state_checksum
      ) select competition_id, new_cycle_id, counters.player_profile_id,
        counters.card_type_code, counters.accumulation_points,
        counters.accumulation_points, counters.threshold_hits,
        counters.last_event_server_sequence,
        encode(extensions.digest(convert_to(concat_ws('|',
          new_cycle_id::text, counters.player_profile_id::text,
          counters.card_type_code, counters.accumulation_points::text,
          counters.threshold_hits::text
        ), 'UTF8'), 'sha256'), 'hex')
      from public.pachanga_competition_disciplinary_counters counters
      where counters.cycle_id = cycle_row.id and counters.accumulation_points > 0;
      for loop_player in
        select distinct counters.player_profile_id
        from public.pachanga_competition_disciplinary_counters counters
        where counters.cycle_id = new_cycle_id
      loop
        perform private.pachanga_competition_discipline_rebuild_player_state_v1(
          new_cycle_id, loop_player
        );
      end loop;
    end if;
    confirmed_revision := 1;
    event_payload := jsonb_build_object(
      'closedCycleId', cycle_row.id, 'newCycleId', new_cycle_id,
      'carryPolicy', upper(coalesce(catalog_row.cycle_policy ->> 'carryPolicy', 'RESET'))
    );
    invalidations := jsonb_build_array(jsonb_build_object(
      'entityType', 'competition_discipline_cycle', 'entityId', new_cycle_id,
      'revision', confirmed_revision
    ));

  elsif normalized_action = 'sanction.decide' then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, false);
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_review') then
      raise exception 'COMPETITION_DISCIPLINE_REVIEWER_REQUIRED' using errcode = '42501';
    end if;
    if payload - array[
      'decisionOutcome', 'units', 'publicReasonCategory', 'publicSummary',
      'ruleArticle', 'privateReason', 'evidenceRefs'
    ] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_DECISION_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into sanction_row
    from public.pachanga_competition_sanctions sanctions
    where sanctions.id = aggregate_id and sanctions.competition_id = competition_id
    for update;
    if not found then raise exception 'COMPETITION_SANCTION_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into proposal_row
    from public.pachanga_competition_sanction_proposals proposals
    where proposals.sanction_id = sanction_row.id
      and proposals.status in ('pending', 'under_review')
    for update;
    if not found then
      raise exception 'DISCIPLINE_COMMITTEE_PROPOSAL_REQUIRED' using errcode = '22023';
    end if;
    target_status := upper(trim(coalesce(payload ->> 'decisionOutcome', '')));
    if target_status not in ('FIXED_SANCTION', 'NO_SANCTION') then
      raise exception 'DISCIPLINE_DECISION_OUTCOME_INVALID' using errcode = '22023';
    end if;
    selected_public_summary := left(coalesce(payload ->> 'publicSummary', ''), 500);
    selected_public_category := coalesce(
      nullif(trim(payload ->> 'publicReasonCategory'), ''), 'dismissal'
    );
    selected_private_reason := left(coalesce(payload ->> 'privateReason', ''), 4000);
    selected_evidence := coalesce(payload -> 'evidenceRefs', '[]'::jsonb);
    if length(trim(selected_private_reason)) < 3
       or jsonb_typeof(selected_evidence) <> 'array'
       or jsonb_array_length(selected_evidence) > 20 then
      raise exception 'DISCIPLINE_DECISION_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    if target_status = 'FIXED_SANCTION' then
      target_units := nullif(payload ->> 'units', '')::integer;
      if target_units is null
         or target_units < coalesce(proposal_row.minimum_units, 0)
         or target_units > coalesce(proposal_row.maximum_units, target_units) then
        raise exception 'DISCIPLINE_DECISION_OUTSIDE_RULE_RANGE' using errcode = '22023';
      end if;
      target_unit_type := proposal_row.unit_type;
    else
      target_units := null;
      target_unit_type := null;
    end if;
    next_revision := sanction_row.revision + 1;
    insert into public.pachanga_competition_sanction_revisions(
      sanction_id, version, previous_revision_id, status, sanction_outcome,
      unit_type, total_units, remaining_units, public_reason_category,
      public_summary, rule_article, decision_factors, decision_reason_private,
      operation_id, created_by
    ) values (
      sanction_row.id, next_revision, sanction_row.current_revision_id,
      case when target_status = 'NO_SANCTION' then 'no_sanction' else 'active' end,
      target_status, target_unit_type, target_units, target_units,
      selected_public_category, selected_public_summary,
      coalesce(nullif(trim(payload ->> 'ruleArticle'), ''), proposal_row.rule_article),
      jsonb_build_object(
        'proposalId', proposal_row.id,
        'ruleMinimumUnits', proposal_row.minimum_units,
        'ruleMaximumUnits', proposal_row.maximum_units
      ), selected_private_reason, operation_id, actor_id
    ) returning id into sanction_revision_id;
    update public.pachanga_competition_sanctions set
      sanction_outcome = target_status,
      status = case when target_status = 'NO_SANCTION' then 'no_sanction' else 'active' end,
      unit_type = target_unit_type, total_units = target_units,
      remaining_units = target_units, current_revision_id = sanction_revision_id,
      revision = next_revision,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = sanction_row.id returning * into sanction_row;
    update public.pachanga_competition_sanction_proposals set
      status = 'decided', revision = revision + 1,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = proposal_row.id;
    perform private.pachanga_competition_discipline_guard_locked_squads_v1(
      competition_id, sanction_row.player_profile_id
    );
    if jsonb_array_length(selected_evidence) > 0 or selected_private_reason <> '' then
      insert into private.pachanga_competition_discipline_evidence(
        competition_id, subject_type, subject_id, evidence_refs,
        private_notes, operation_id, actor_id, server_sequence
      ) values (
        competition_id, 'SANCTION', sanction_row.id, selected_evidence,
        selected_private_reason, operation_id, actor_id, sanction_row.server_sequence
      );
    end if;
    state_checksum := private.pachanga_competition_discipline_rebuild_player_state_v1(
      sanction_row.cycle_id, sanction_row.player_profile_id
    );
    confirmed_revision := sanction_row.revision;
    affected_player_id := sanction_row.player_profile_id;
    event_payload := jsonb_build_object(
      'sanctionId', sanction_row.id, 'proposalId', proposal_row.id,
      'decisionOutcome', target_status, 'units', target_units,
      'unitType', target_unit_type, 'playerStateChecksum', state_checksum
    );
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'competition_discipline',
        'entityId', competition_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_player',
        'entityId', sanction_row.player_profile_id, 'revision', confirmed_revision)
    );

  elsif normalized_action = 'appeal.submit' then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, true);
    if payload - array['statement'] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_APPEAL_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into sanction_row
    from public.pachanga_competition_sanctions sanctions
    where sanctions.id = aggregate_id and sanctions.competition_id = competition_id
    for update;
    if not found then raise exception 'COMPETITION_SANCTION_NOT_FOUND' using errcode = 'P0002'; end if;
    if sanction_row.target_type <> 'PLAYER'
       or sanction_row.status not in ('active', 'provisional') then
      raise exception 'DISCIPLINE_SANCTION_NOT_APPEALABLE' using errcode = '22023';
    end if;
    select profiles.id into own_profile_id
    from public.pachanga_player_profiles profiles
    where profiles.user_id = actor_id;
    if own_profile_id is distinct from sanction_row.player_profile_id then
      raise exception 'DISCIPLINE_APPEAL_TARGET_REQUIRED' using errcode = '42501';
    end if;
    catalog_row := private.pachanga_competition_discipline_ensure_catalog_v1(
      competition_id, sanction_row.rule_revision_id, actor_id
    );
    appeal_policy := catalog_row.appeal_policy;
    deadline_hours := nullif(appeal_policy ->> 'deadlineHours', '')::integer;
    suspensive_effect := coalesce((appeal_policy ->> 'suspensiveEffect')::boolean, false);
    if deadline_hours is null or deadline_hours < 1 or deadline_hours > 720 then
      raise exception 'DISCIPLINE_APPEAL_POLICY_INVALID' using errcode = '22023';
    end if;
    if clock_timestamp() > sanction_row.created_at + make_interval(hours => deadline_hours) then
      raise exception 'DISCIPLINE_APPEAL_DEADLINE_EXPIRED' using errcode = '22023';
    end if;
    selected_private_reason := left(coalesce(payload ->> 'statement', ''), 4000);
    if length(trim(selected_private_reason)) < 3 then
      raise exception 'DISCIPLINE_APPEAL_STATEMENT_REQUIRED' using errcode = '22023';
    end if;
    insert into public.pachanga_competition_sanction_appeals(
      competition_id, sanction_id, appellant_user_id, status,
      deadline_at, suspensive_effect, creation_operation_id
    ) values (
      competition_id, sanction_row.id, actor_id, 'submitted',
      sanction_row.created_at + make_interval(hours => deadline_hours),
      suspensive_effect, operation_id
    ) returning * into appeal_row;
    insert into public.pachanga_competition_sanction_appeal_revisions(
      appeal_id, version, status, statement, operation_id, created_by
    ) values (
      appeal_row.id, 1, 'submitted', selected_private_reason, operation_id, actor_id
    ) returning id into appeal_revision_id;
    update public.pachanga_competition_sanction_appeals set
      current_revision_id = appeal_revision_id
    where id = appeal_row.id;
    if suspensive_effect then
      next_revision := sanction_row.revision + 1;
      insert into public.pachanga_competition_sanction_revisions(
        sanction_id, version, previous_revision_id, status, sanction_outcome,
        unit_type, total_units, remaining_units, public_reason_category,
        public_summary, decision_factors, decision_reason_private,
        operation_id, created_by
      ) select sanction_row.id, next_revision, sanction_row.current_revision_id,
        sanction_row.status, sanction_row.sanction_outcome, sanction_row.unit_type,
        sanction_row.total_units, sanction_row.remaining_units,
        revisions.public_reason_category, revisions.public_summary,
        jsonb_build_object('appealId', appeal_row.id, 'suspensiveEffect', true),
        '', gen_random_uuid(), actor_id
      from public.pachanga_competition_sanction_revisions revisions
      where revisions.id = sanction_row.current_revision_id
      returning id into sanction_revision_id;
      update public.pachanga_competition_sanctions set
        suspensive_hold = true, current_revision_id = sanction_revision_id,
        revision = next_revision,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = clock_timestamp()
      where id = sanction_row.id returning * into sanction_row;
    end if;
    state_checksum := private.pachanga_competition_discipline_rebuild_player_state_v1(
      sanction_row.cycle_id, sanction_row.player_profile_id
    );
    confirmed_revision := appeal_row.revision;
    affected_player_id := sanction_row.player_profile_id;
    event_payload := jsonb_build_object(
      'appealId', appeal_row.id, 'sanctionId', sanction_row.id,
      'status', 'submitted', 'deadlineAt', appeal_row.deadline_at,
      'suspensiveEffect', suspensive_effect
    );
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'competition_discipline_appeal',
        'entityId', appeal_row.id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_player',
        'entityId', sanction_row.player_profile_id, 'revision', sanction_row.revision)
    );

  elsif normalized_action in ('appeal.transition', 'appeal.withdraw') then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, false, true);
    if payload - array[
      'status', 'publicResolution', 'privateReason', 'modifiedUnits'
    ] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_APPEAL_TRANSITION_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into appeal_row
    from public.pachanga_competition_sanction_appeals appeals
    where appeals.id = aggregate_id and appeals.competition_id = competition_id
    for update;
    if not found then raise exception 'DISCIPLINE_APPEAL_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into sanction_row
    from public.pachanga_competition_sanctions sanctions
    where sanctions.id = appeal_row.sanction_id for update;
    if normalized_action = 'appeal.withdraw' then
      if appeal_row.appellant_user_id <> actor_id
         or appeal_row.status not in ('submitted', 'admissible', 'under_review') then
        raise exception 'DISCIPLINE_APPEAL_WITHDRAW_NOT_ALLOWED' using errcode = '42501';
      end if;
      target_status := 'withdrawn';
    else
      if not private.pachanga_competition_can_v1(competition_id, actor_id, 'appeals_manage') then
        raise exception 'COMPETITION_APPEALS_MANAGER_REQUIRED' using errcode = '42501';
      end if;
      target_status := lower(trim(coalesce(payload ->> 'status', '')));
      if target_status not in (
        'admissible', 'under_review', 'upheld', 'modified',
        'overturned', 'inadmissible'
      ) then raise exception 'DISCIPLINE_APPEAL_STATUS_INVALID' using errcode = '22023'; end if;
      if not (
        (appeal_row.status = 'submitted' and target_status in ('admissible', 'inadmissible'))
        or (appeal_row.status = 'admissible' and target_status = 'under_review')
        or (appeal_row.status = 'under_review'
          and target_status in ('upheld', 'modified', 'overturned'))
      ) then raise exception 'DISCIPLINE_APPEAL_TRANSITION_INVALID' using errcode = 'PT409'; end if;
    end if;
    selected_public_summary := left(coalesce(payload ->> 'publicResolution', ''), 1000);
    selected_private_reason := left(coalesce(payload ->> 'privateReason', ''), 4000);
    if normalized_action = 'appeal.transition'
       and length(trim(selected_private_reason)) < 3 then
      raise exception 'DISCIPLINE_APPEAL_RESOLUTION_REASON_REQUIRED' using errcode = '22023';
    end if;
    next_revision := appeal_row.revision + 1;
    insert into public.pachanga_competition_sanction_appeal_revisions(
      appeal_id, version, previous_revision_id, status, statement,
      public_resolution, resolution_reason_private, operation_id, created_by
    ) select appeal_row.id, next_revision, appeal_row.current_revision_id,
      target_status, revisions.statement, selected_public_summary,
      selected_private_reason, operation_id, actor_id
    from public.pachanga_competition_sanction_appeal_revisions revisions
    where revisions.id = appeal_row.current_revision_id
    returning id into appeal_revision_id;
    update public.pachanga_competition_sanction_appeals set
      status = target_status, current_revision_id = appeal_revision_id,
      revision = next_revision,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = appeal_row.id returning * into appeal_row;

    if target_status in ('upheld', 'modified', 'overturned', 'inadmissible', 'withdrawn') then
      if target_status = 'modified' then
        target_units := nullif(payload ->> 'modifiedUnits', '')::integer;
        if target_units is null or target_units < 0 then
          raise exception 'DISCIPLINE_APPEAL_MODIFIED_UNITS_INVALID' using errcode = '22023';
        end if;
        remaining_after := least(target_units, coalesce(sanction_row.remaining_units, target_units));
      elsif target_status = 'overturned' then
        target_units := sanction_row.total_units;
        remaining_after := 0;
      else
        target_units := sanction_row.total_units;
        remaining_after := sanction_row.remaining_units;
      end if;
      next_revision := sanction_row.revision + 1;
      insert into public.pachanga_competition_sanction_revisions(
        sanction_id, version, previous_revision_id, status, sanction_outcome,
        unit_type, total_units, remaining_units, public_reason_category,
        public_summary, decision_factors, decision_reason_private,
        operation_id, created_by
      ) select sanction_row.id, next_revision, sanction_row.current_revision_id,
        case when target_status = 'overturned' then 'overturned'
          when remaining_after = 0 then 'served' else 'active' end,
        sanction_row.sanction_outcome, sanction_row.unit_type,
        target_units, remaining_after, revisions.public_reason_category,
        case when selected_public_summary <> '' then selected_public_summary
          else revisions.public_summary end,
        jsonb_build_object('appealId', appeal_row.id, 'appealOutcome', target_status),
        selected_private_reason, gen_random_uuid(), actor_id
      from public.pachanga_competition_sanction_revisions revisions
      where revisions.id = sanction_row.current_revision_id
      returning id into sanction_revision_id;
      update public.pachanga_competition_sanctions set
        status = case when target_status = 'overturned' then 'overturned'
          when remaining_after = 0 then 'served' else 'active' end,
        total_units = target_units, remaining_units = remaining_after,
        suspensive_hold = false, current_revision_id = sanction_revision_id,
        revision = next_revision,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = clock_timestamp()
      where id = sanction_row.id returning * into sanction_row;
    end if;
    perform private.pachanga_competition_discipline_guard_locked_squads_v1(
      competition_id, sanction_row.player_profile_id
    );
    state_checksum := private.pachanga_competition_discipline_rebuild_player_state_v1(
      sanction_row.cycle_id, sanction_row.player_profile_id
    );
    confirmed_revision := appeal_row.revision;
    affected_player_id := sanction_row.player_profile_id;
    event_payload := jsonb_build_object(
      'appealId', appeal_row.id, 'sanctionId', sanction_row.id,
      'status', target_status, 'sanctionRevision', sanction_row.revision,
      'playerStateChecksum', state_checksum
    );
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'competition_discipline_appeal',
        'entityId', appeal_row.id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_player',
        'entityId', sanction_row.player_profile_id, 'revision', sanction_row.revision)
    );
  elsif normalized_action = 'service.record' then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, true, false);
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_manage') then
      raise exception 'COMPETITION_DISCIPLINE_MANAGER_REQUIRED' using errcode = '42501';
    end if;
    if payload <> '{}'::jsonb then
      raise exception 'DISCIPLINE_SERVICE_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into sanction_row
    from public.pachanga_competition_sanctions sanctions
    where sanctions.id = aggregate_id and sanctions.competition_id = competition_id
    for update;
    if not found then raise exception 'COMPETITION_SANCTION_NOT_FOUND' using errcode = 'P0002'; end if;
    if sanction_row.status not in ('active', 'provisional')
       or coalesce(sanction_row.remaining_units, 0) <= 0
       or sanction_row.suspensive_hold then
      raise exception 'DISCIPLINE_SANCTION_NOT_SERVICEABLE' using errcode = '22023';
    end if;
    select events.entry_id into source_entry_id
    from public.pachanga_competition_disciplinary_events events
    where events.id = sanction_row.source_event_id;
    if sanction_row.unit_type = 'COMPETITION_EXPULSION' then
      raise exception 'DISCIPLINE_EXPULSION_CANNOT_BE_SERVED' using errcode = '22023';
    elsif sanction_row.unit_type = 'WEEKS' then
      if clock_timestamp() < sanction_row.created_at
        + make_interval(days => sanction_row.total_units * 7) then
        raise exception 'DISCIPLINE_WEEK_SANCTION_NOT_ELAPSED' using errcode = '22023';
      end if;
      target_units := sanction_row.remaining_units;
    else
      target_units := 1;
    end if;
    select rounds.round_number into source_round_number
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    join public.pachanga_competition_disciplinary_events events
      on events.canonical_match_id = items.canonical_match_id
    where events.id = sanction_row.source_event_id
    order by rounds.server_sequence desc, rounds.id desc limit 1;
    select contexts.* into context_row
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    join public.pachanga_competition_match_contexts contexts
      on contexts.id = items.competition_match_context_id
    where contexts.competition_id = competition_id
      and (items.home_entry_id = source_entry_id or items.away_entry_id = source_entry_id)
      and items.status = 'published'
      and contexts.status in ('official', 'played')
      and rounds.round_number > source_round_number
      and not exists (
        select 1
        from public.pachanga_competition_sanction_service_events prior_service
        where prior_service.sanction_id = sanction_row.id
          and prior_service.canonical_match_id = items.canonical_match_id
          and prior_service.event_type = 'SERVED'
          and not exists (
            select 1
            from public.pachanga_competition_sanction_service_events reversals
            where reversals.reverses_service_event_id = prior_service.id
          )
      )
    order by rounds.round_number, items.scheduled_start nulls last,
      items.server_sequence, items.id
    limit 1
    for update of contexts;
    if not found then
      raise exception 'DISCIPLINE_SERVICE_FIXTURE_NOT_ELIGIBLE' using errcode = '22023';
    end if;
    affected_match_id := context_row.canonical_match_id;
    select rounds.round_number into target_round_number
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.canonical_match_id = affected_match_id
      and items.status = 'published'
    order by rounds.server_sequence desc, rounds.id desc limit 1;
    if source_round_number is null or target_round_number is null
       or target_round_number <= source_round_number then
      raise exception 'DISCIPLINE_SERVICE_FIXTURE_NOT_ELIGIBLE' using errcode = '22023';
    end if;
    if sanction_row.unit_type in ('MATCHES', 'ROUNDS') and exists (
      select 1
      from public.pachanga_competition_schedule_items earlier_items
      join public.pachanga_competition_rounds earlier_rounds
        on earlier_rounds.id = earlier_items.round_id
      join public.pachanga_competition_match_contexts earlier_contexts
        on earlier_contexts.id = earlier_items.competition_match_context_id
      where (earlier_items.home_entry_id = source_entry_id
          or earlier_items.away_entry_id = source_entry_id)
        and earlier_items.status = 'published'
        and earlier_rounds.round_number > source_round_number
        and earlier_rounds.round_number < target_round_number
        and earlier_contexts.status in ('official', 'played')
        and not exists (
          select 1
          from public.pachanga_competition_sanction_service_events prior_service
          where prior_service.sanction_id = sanction_row.id
            and prior_service.canonical_match_id = earlier_items.canonical_match_id
            and prior_service.event_type = 'SERVED'
            and not exists (
              select 1 from public.pachanga_competition_sanction_service_events reversals
              where reversals.reverses_service_event_id = prior_service.id
            )
        )
    ) then raise exception 'DISCIPLINE_SERVICE_NOT_NEXT_ELIGIBLE_FIXTURE' using errcode = 'PT409'; end if;
    if exists (
      select 1
      from public.pachanga_competition_match_squads squads
      join public.pachanga_competition_match_squad_members members
        on members.squad_revision_id = squads.current_revision_id
      where squads.canonical_match_id = affected_match_id
        and squads.status = 'locked'
        and members.player_profile_id = sanction_row.player_profile_id
    ) then raise exception 'DISCIPLINE_SANCTIONED_PLAYER_IN_SQUAD' using errcode = '22023'; end if;
    remaining_before := sanction_row.remaining_units;
    remaining_after := greatest(remaining_before - target_units, 0);
    insert into public.pachanga_competition_sanction_service_events(
      competition_id, sanction_id, canonical_match_id,
      competition_match_context_id, event_type, units,
      remaining_before, remaining_after, rule_revision_id,
      operation_id, created_by
    ) values (
      competition_id, sanction_row.id, affected_match_id,
      context_row.id, 'SERVED', target_units,
      remaining_before, remaining_after, sanction_row.rule_revision_id,
      operation_id, actor_id
    ) returning id into active_service_id;
    next_revision := sanction_row.revision + 1;
    insert into public.pachanga_competition_sanction_revisions(
      sanction_id, version, previous_revision_id, status, sanction_outcome,
      unit_type, total_units, remaining_units, public_reason_category,
      public_summary, decision_factors, decision_reason_private,
      operation_id, created_by
    ) select sanction_row.id, next_revision, sanction_row.current_revision_id,
      case when remaining_after = 0 then 'served' else sanction_row.status end,
      sanction_row.sanction_outcome, sanction_row.unit_type,
      sanction_row.total_units, remaining_after,
      revisions.public_reason_category, revisions.public_summary,
      jsonb_build_object('serviceEventId', active_service_id,
        'canonicalMatchId', affected_match_id), '', gen_random_uuid(), actor_id
    from public.pachanga_competition_sanction_revisions revisions
    where revisions.id = sanction_row.current_revision_id
    returning id into sanction_revision_id;
    update public.pachanga_competition_sanctions set
      remaining_units = remaining_after,
      status = case when remaining_after = 0 then 'served' else status end,
      current_revision_id = sanction_revision_id,
      revision = next_revision,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = sanction_row.id returning * into sanction_row;
    state_checksum := private.pachanga_competition_discipline_rebuild_player_state_v1(
      sanction_row.cycle_id, sanction_row.player_profile_id
    );
    confirmed_revision := sanction_row.revision;
    affected_player_id := sanction_row.player_profile_id;
    event_payload := jsonb_build_object(
      'sanctionId', sanction_row.id, 'serviceEventId', active_service_id,
      'canonicalMatchId', affected_match_id,
      'remainingBefore', remaining_before, 'remainingAfter', remaining_after,
      'playerStateChecksum', state_checksum
    );
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'competition_discipline',
        'entityId', competition_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_match',
        'entityId', affected_match_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_player',
        'entityId', sanction_row.player_profile_id, 'revision', confirmed_revision)
    );

  elsif normalized_action = 'service.reverse' then
    perform private.pachanga_competition_discipline_assert_flags_v1(true, true, true, true, false);
    if not private.pachanga_competition_can_v1(competition_id, actor_id, 'discipline_review') then
      raise exception 'COMPETITION_DISCIPLINE_REVIEWER_REQUIRED' using errcode = '42501';
    end if;
    if payload - array['serviceEventId', 'privateReason'] <> '{}'::jsonb then
      raise exception 'DISCIPLINE_SERVICE_REVERSAL_PAYLOAD_INVALID' using errcode = '22023';
    end if;
    select * into sanction_row
    from public.pachanga_competition_sanctions sanctions
    where sanctions.id = aggregate_id and sanctions.competition_id = competition_id
    for update;
    if not found then raise exception 'COMPETITION_SANCTION_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into service_row
    from public.pachanga_competition_sanction_service_events service
    where service.id = nullif(payload ->> 'serviceEventId', '')::uuid
      and service.sanction_id = sanction_row.id
      and service.event_type = 'SERVED'
    for update;
    if not found or exists (
      select 1 from public.pachanga_competition_sanction_service_events reversals
      where reversals.reverses_service_event_id = service_row.id
    ) then raise exception 'DISCIPLINE_SERVICE_EVENT_NOT_REVERSIBLE' using errcode = '22023'; end if;
    selected_private_reason := left(coalesce(payload ->> 'privateReason', ''), 4000);
    if length(trim(selected_private_reason)) < 3 then
      raise exception 'DISCIPLINE_SERVICE_REVERSAL_REASON_REQUIRED' using errcode = '22023';
    end if;
    remaining_before := sanction_row.remaining_units;
    remaining_after := least(sanction_row.total_units, remaining_before + service_row.units);
    insert into public.pachanga_competition_sanction_service_events(
      competition_id, sanction_id, canonical_match_id,
      competition_match_context_id, event_type, units,
      remaining_before, remaining_after, reverses_service_event_id,
      rule_revision_id, operation_id, created_by
    ) values (
      competition_id, sanction_row.id, service_row.canonical_match_id,
      service_row.competition_match_context_id, 'REVERSED', service_row.units,
      remaining_before, remaining_after, service_row.id,
      sanction_row.rule_revision_id, operation_id, actor_id
    ) returning id into active_service_id;
    next_revision := sanction_row.revision + 1;
    insert into public.pachanga_competition_sanction_revisions(
      sanction_id, version, previous_revision_id, status, sanction_outcome,
      unit_type, total_units, remaining_units, public_reason_category,
      public_summary, decision_factors, decision_reason_private,
      operation_id, created_by
    ) select sanction_row.id, next_revision, sanction_row.current_revision_id,
      'active', sanction_row.sanction_outcome, sanction_row.unit_type,
      sanction_row.total_units, remaining_after,
      revisions.public_reason_category, revisions.public_summary,
      jsonb_build_object('reversalServiceEventId', active_service_id,
        'reversedServiceEventId', service_row.id),
      selected_private_reason, gen_random_uuid(), actor_id
    from public.pachanga_competition_sanction_revisions revisions
    where revisions.id = sanction_row.current_revision_id
    returning id into sanction_revision_id;
    update public.pachanga_competition_sanctions set
      remaining_units = remaining_after, status = 'active',
      current_revision_id = sanction_revision_id, revision = next_revision,
      server_sequence = nextval('private.pachanga_competition_sequence'),
      updated_at = clock_timestamp()
    where id = sanction_row.id returning * into sanction_row;
    state_checksum := private.pachanga_competition_discipline_rebuild_player_state_v1(
      sanction_row.cycle_id, sanction_row.player_profile_id
    );
    confirmed_revision := sanction_row.revision;
    affected_match_id := service_row.canonical_match_id;
    affected_player_id := sanction_row.player_profile_id;
    event_payload := jsonb_build_object(
      'sanctionId', sanction_row.id, 'serviceReversalId', active_service_id,
      'reversedServiceEventId', service_row.id,
      'remainingBefore', remaining_before, 'remainingAfter', remaining_after
    );
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'competition_discipline',
        'entityId', competition_id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'competition_discipline_player',
        'entityId', sanction_row.player_profile_id, 'revision', confirmed_revision)
    );
  end if;

  update public.pachanga_competitions competitions set
    discipline_revision = competitions.discipline_revision + 1
  where competitions.id = competition_id
  returning competitions.discipline_revision into confirmed_revision;
  invalidations := (
    select coalesce(jsonb_agg(
      items.value || jsonb_build_object('revision', confirmed_revision)
    ), '[]'::jsonb)
    from jsonb_array_elements(invalidations) items(value)
  );
  sequence_value := nextval('private.pachanga_competition_sequence');
  snapshot := private.pachanga_competition_discipline_snapshot_v1(
    competition_id, actor_id, affected_match_id, affected_player_id
  );
  return private.pachanga_competition_discipline_store_command_v1(
    operation_id, actor_id, normalized_action, aggregate_id, competition_id,
    confirmed_revision, sequence_value, request_hash,
    coalesce(client_metadata, '{}'::jsonb), event_payload, snapshot, invalidations
  );
exception
  when unique_violation then raise exception 'DISCIPLINE_CONFLICT' using errcode = 'PT409';
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_competition_discipline_v1(
  uuid, uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_competition_discipline_v1(
  uuid, uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;
