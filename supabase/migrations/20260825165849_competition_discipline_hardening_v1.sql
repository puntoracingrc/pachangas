-- Pachangas IQ R5: invariants, R4C eligibility, notifications and beta contract.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_discipline_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'COMPETITION_DISCIPLINE_IMMUTABLE_HISTORY' using errcode = '55000';
end;
$$;

revoke all on function private.pachanga_competition_discipline_immutable_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_discipline_rule_catalog_v1
  on public.pachanga_competition_discipline_rule_catalogs;
create trigger guard_pachanga_discipline_rule_catalog_v1
before update or delete on public.pachanga_competition_discipline_rule_catalogs
for each row execute function private.pachanga_competition_discipline_immutable_v1();

drop trigger if exists guard_pachanga_disciplinary_event_revision_v1
  on public.pachanga_competition_disciplinary_event_revisions;
create trigger guard_pachanga_disciplinary_event_revision_v1
before update or delete on public.pachanga_competition_disciplinary_event_revisions
for each row execute function private.pachanga_competition_discipline_immutable_v1();

drop trigger if exists guard_pachanga_sanction_revision_v1
  on public.pachanga_competition_sanction_revisions;
create trigger guard_pachanga_sanction_revision_v1
before update or delete on public.pachanga_competition_sanction_revisions
for each row execute function private.pachanga_competition_discipline_immutable_v1();

drop trigger if exists guard_pachanga_sanction_service_event_v1
  on public.pachanga_competition_sanction_service_events;
create trigger guard_pachanga_sanction_service_event_v1
before update or delete on public.pachanga_competition_sanction_service_events
for each row execute function private.pachanga_competition_discipline_immutable_v1();

drop trigger if exists guard_pachanga_sanction_appeal_revision_v1
  on public.pachanga_competition_sanction_appeal_revisions;
create trigger guard_pachanga_sanction_appeal_revision_v1
before update or delete on public.pachanga_competition_sanction_appeal_revisions
for each row execute function private.pachanga_competition_discipline_immutable_v1();

drop trigger if exists guard_pachanga_competition_discipline_evidence_v1
  on private.pachanga_competition_discipline_evidence;
create trigger guard_pachanga_competition_discipline_evidence_v1
before update or delete on private.pachanga_competition_discipline_evidence
for each row execute function private.pachanga_competition_discipline_immutable_v1();

create or replace function private.pachanga_competition_player_sanction_applies_v1(
  target_competition_id uuid,
  target_player_profile_id uuid,
  target_canonical_match_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with target_fixture as (
    select items.canonical_match_id, items.scheduled_start, rounds.round_number,
      rounds.stage_id
    from public.pachanga_competition_schedule_items items
    join public.pachanga_competition_rounds rounds on rounds.id = items.round_id
    where items.canonical_match_id = target_canonical_match_id
      and items.status = 'published'
    order by items.server_sequence desc, items.id desc
    limit 1
  )
  select exists (
    select 1
    from public.pachanga_competition_sanctions sanctions
    left join public.pachanga_competition_disciplinary_events source_events
      on source_events.id = sanctions.source_event_id
    left join public.pachanga_competition_schedule_items source_items
      on source_items.canonical_match_id = source_events.canonical_match_id
    left join public.pachanga_competition_rounds source_rounds
      on source_rounds.id = source_items.round_id
    cross join target_fixture target
    where sanctions.competition_id = target_competition_id
      and sanctions.target_type = 'PLAYER'
      and sanctions.player_profile_id = target_player_profile_id
      and sanctions.status in ('active', 'provisional')
      and coalesce(sanctions.remaining_units, 0) > 0
      and not sanctions.suspensive_hold
      and source_events.canonical_match_id <> target_canonical_match_id
      and (
        sanctions.unit_type = 'COMPETITION_EXPULSION'
        or (sanctions.unit_type = 'STAGE' and source_rounds.stage_id = target.stage_id)
        or coalesce(target.round_number > source_rounds.round_number, false)
        or coalesce(target.scheduled_start > source_items.scheduled_start, false)
      )
  );
$$;

revoke all on function private.pachanga_competition_player_sanction_applies_v1(
  uuid, uuid, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_validate_squad_v1(target_squad_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare squad_row public.pachanga_competition_match_squads%rowtype;
declare revision_row public.pachanga_competition_match_squad_revisions%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare policy jsonb;
declare discipline_enabled boolean;
begin
  select * into squad_row from public.pachanga_competition_match_squads squads
  where squads.id = target_squad_id;
  if not found or squad_row.current_revision_id is null then
    raise exception 'R4C_SQUAD_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into revision_row from public.pachanga_competition_match_squad_revisions revisions
  where revisions.id = squad_row.current_revision_id;
  select * into context_row from public.pachanga_competition_match_contexts contexts
  where contexts.id = squad_row.competition_match_context_id;
  policy := private.pachanga_league_match_policy_v1(squad_row.rule_revision_id);
  if revision_row.member_count < (policy ->> 'squadMin')::integer
     or revision_row.member_count > (policy ->> 'squadMax')::integer
     or revision_row.starter_count < (policy ->> 'starterMin')::integer
     or revision_row.starter_count > (policy ->> 'starterMax')::integer
     or revision_row.substitute_count > (policy ->> 'substituteMax')::integer then
    raise exception 'R4C_SQUAD_POLICY_VIOLATION' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.pachanga_competition_match_squad_members members
    left join public.pachanga_competition_roster_members roster_members
      on roster_members.id = members.roster_member_id
      and roster_members.roster_revision_id = squad_row.roster_revision_id
      and roster_members.entry_id = squad_row.entry_id
      and roster_members.player_profile_id = members.player_profile_id
      and roster_members.eligibility_status in ('eligible', 'waived')
    where members.squad_revision_id = revision_row.id
      and roster_members.id is null
  ) then raise exception 'R4C_SQUAD_CONTAINS_INELIGIBLE_PLAYER' using errcode = '22023'; end if;
  select settings.competition_discipline_foundation_enabled
      and settings.competition_sanctions_enabled into discipline_enabled
  from private.pachanga_competition_foundation_settings settings where settings.singleton;
  if coalesce(discipline_enabled, false) and exists (
    select 1
    from public.pachanga_competition_match_squad_members members
    where members.squad_revision_id = revision_row.id
      and private.pachanga_competition_player_sanction_applies_v1(
        context_row.competition_id, members.player_profile_id,
        squad_row.canonical_match_id
      )
  ) then
    raise exception 'R4C_SQUAD_CONTAINS_DISCIPLINARY_INELIGIBLE_PLAYER'
      using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.pachanga_league_match_validate_squad_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_discipline_squad_status_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare sheet_row public.pachanga_competition_match_sheets%rowtype;
declare enabled boolean;
declare all_locked boolean;
begin
  if new.status not in ('validated', 'locked') then return new; end if;
  select * into sheet_row from public.pachanga_competition_match_sheets sheets
  where sheets.canonical_match_id = new.canonical_match_id for update;
  select settings.competition_discipline_foundation_enabled
      and settings.competition_sanctions_enabled into enabled
  from private.pachanga_competition_foundation_settings settings where settings.singleton;
  if not coalesce(enabled, false) then
    if sheet_row.id is not null then
      update public.pachanga_competition_match_sheets set
        discipline_validation_status = 'NOT_AVAILABLE',
        revision = revision + 1,
        server_sequence = nextval('private.pachanga_competition_sequence'),
        updated_at = clock_timestamp()
      where id = sheet_row.id;
    end if;
    return new;
  end if;
  perform private.pachanga_league_match_validate_squad_v1(new.id);
  if sheet_row.id is null then return new; end if;
  select count(*) = 2 and bool_and(squads.status = 'locked') into all_locked
  from public.pachanga_competition_match_squads squads
  where squads.canonical_match_id = new.canonical_match_id;
  update public.pachanga_competition_match_sheets set
    discipline_validation_status = case when all_locked then 'VALIDATED' else 'PENDING' end,
    revision = revision + 1,
    server_sequence = nextval('private.pachanga_competition_sequence'),
    updated_at = clock_timestamp()
  where id = sheet_row.id;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_discipline_squad_status_v1()
  from public, anon, authenticated;

drop trigger if exists apply_pachanga_competition_discipline_squad_status_v1
  on public.pachanga_competition_match_squads;
create trigger apply_pachanga_competition_discipline_squad_status_v1
after update of status on public.pachanga_competition_match_squads
for each row when (new.status in ('validated', 'locked'))
execute function private.pachanga_competition_discipline_squad_status_v1();

create or replace function private.pachanga_competition_discipline_notify_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare player_id uuid;
declare recipient_id uuid;
declare sanction_id uuid;
declare appeal_id uuid;
declare event_id uuid;
declare sanction_status text;
declare sanction_remaining integer;
declare action_url text;
declare title_value text;
declare body_value text;
declare kind_value text;
declare payload jsonb;
begin
  if new.aggregate_type <> 'competition_discipline'
     or new.competition_id is null then return new; end if;
  player_id := nullif(new.event_payload ->> 'playerProfileId', '')::uuid;
  sanction_id := nullif(new.event_payload ->> 'sanctionId', '')::uuid;
  appeal_id := nullif(new.event_payload ->> 'appealId', '')::uuid;
  event_id := nullif(new.event_payload ->> 'eventId', '')::uuid;
  if sanction_id is null and event_id is not null and coalesce(
    (new.event_payload ->> 'derivedSanctionChanges')::integer, 0
  ) > 0 then
    select sanctions.id, sanctions.player_profile_id,
      sanctions.status, sanctions.remaining_units
    into sanction_id, player_id, sanction_status, sanction_remaining
    from public.pachanga_competition_sanctions sanctions
    where sanctions.source_event_id = event_id
    order by sanctions.server_sequence desc, sanctions.id desc
    limit 1;
  end if;
  if sanction_id is not null and sanction_status is null then
    select sanctions.player_profile_id, sanctions.status, sanctions.remaining_units
    into player_id, sanction_status, sanction_remaining
    from public.pachanga_competition_sanctions sanctions
    where sanctions.id = sanction_id;
  end if;
  if player_id is null and appeal_id is not null then
    select appeals.sanction_id, sanctions.player_profile_id,
      sanctions.status, sanctions.remaining_units
    into sanction_id, player_id, sanction_status, sanction_remaining
    from public.pachanga_competition_sanction_appeals appeals
    join public.pachanga_competition_sanctions sanctions on sanctions.id = appeals.sanction_id
    where appeals.id = appeal_id;
  end if;
  if player_id is not null then
    select profiles.user_id into recipient_id
    from public.pachanga_player_profiles profiles where profiles.id = player_id;
  end if;
  action_url := '/competiciones/' || new.competition_id::text || '/gestion/disciplina';
  payload := jsonb_strip_nulls(jsonb_build_object(
    'operationId', new.operation_id, 'competitionId', new.competition_id,
    'action', new.action, 'playerProfileId', player_id,
    'sanctionId', sanction_id, 'appealId', appeal_id,
    'canonicalMatchId', nullif(new.event_payload ->> 'canonicalMatchId', '')::uuid
  ));

  if new.action in ('event.record', 'event.correct', 'event.annul') then
    kind_value := 'competition_discipline_event';
    title_value := case new.action
      when 'event.record' then 'Incidencia disciplinaria registrada'
      when 'event.correct' then 'Incidencia disciplinaria corregida'
      else 'Incidencia disciplinaria anulada' end;
    body_value := 'Consulta el estado oficial dentro de la competición.';
  elsif new.action = 'sanction.decide' then
    kind_value := 'competition_sanction_decision';
    title_value := case when sanction_status = 'active'
      then 'Sanción confirmada' else 'Resolución disciplinaria' end;
    body_value := 'La autoridad de la competición ha publicado una resolución.';
  elsif new.action = 'service.record' then
    kind_value := 'competition_sanction_service';
    title_value := case when coalesce((new.event_payload ->> 'remainingAfter')::integer, 0) = 0
      then 'Sanción cumplida' else 'Partido de sanción registrado' end;
    body_value := 'Tu estado de elegibilidad se ha actualizado.';
  elsif new.action = 'service.reverse' then
    kind_value := 'competition_sanction_service';
    title_value := 'Cumplimiento de sanción corregido';
    body_value := 'La autoridad ha corregido el historial de cumplimiento.';
  elsif new.action = 'appeal.submit' then
    perform private.pachanga_league_operational_notify_organizer_v1(
      new.competition_id, 'competition_discipline_appeal',
      'Apelación recibida',
      'Hay una apelación pendiente de revisión.', action_url, payload, new.operation_id
    );
    return new;
  elsif new.action in ('appeal.transition', 'appeal.withdraw') then
    kind_value := 'competition_discipline_appeal';
    title_value := case when new.event_payload ->> 'status' in (
      'upheld', 'modified', 'overturned', 'inadmissible', 'withdrawn'
    ) then 'Apelación resuelta' else 'Apelación actualizada' end;
    body_value := 'La apelación tiene una nueva resolución o estado.';
  else
    return new;
  end if;
  if recipient_id is not null then
    perform private.pachanga_notify_v1(
      recipient_id, kind_value, title_value, body_value,
      action_url, payload,
      'competition-discipline:' || new.operation_id::text || ':' || recipient_id::text
    );
    if new.action in ('event.record', 'event.correct', 'event.annul')
       and coalesce((new.event_payload ->> 'derivedSanctionChanges')::integer, 0) > 0
       and sanction_id is not null then
      perform private.pachanga_notify_v1(
        recipient_id, 'competition_sanction_status',
        case sanction_status
          when 'provisional' then 'Sanción provisional'
          when 'active' then 'Sanción confirmada'
          else 'Sanción actualizada' end,
        'El estado disciplinario oficial se ha actualizado.', action_url, payload,
        'competition-discipline:' || new.operation_id::text || ':status:' || recipient_id::text
      );
    end if;
    if sanction_remaining > 0 and sanction_status in ('active', 'provisional')
       and (
         new.action in ('sanction.decide', 'service.record', 'service.reverse')
         or (new.action in ('event.record', 'event.correct', 'event.annul')
           and coalesce((new.event_payload ->> 'derivedSanctionChanges')::integer, 0) > 0)
       ) then
      perform private.pachanga_notify_v1(
        recipient_id, 'competition_sanction_pending',
        'Partido de sanción pendiente',
        sanction_remaining::text || case when sanction_remaining = 1
          then ' unidad pendiente.' else ' unidades pendientes.' end,
        action_url, payload,
        'competition-discipline:' || new.operation_id::text || ':pending:' || recipient_id::text
      );
    end if;
  end if;
  if new.action in ('event.record', 'event.correct', 'event.annul') and coalesce(
    (new.event_payload ->> 'derivedSanctionChanges')::integer, 0
  ) > 0 then
    perform private.pachanga_league_operational_notify_organizer_v1(
      new.competition_id, 'competition_sanction_review',
      'Estado disciplinario actualizado',
      'El motor ha generado o actualizado una sanción.', action_url,
      payload, new.operation_id
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_discipline_notify_v1()
  from public, anon, authenticated;

drop trigger if exists notify_pachanga_competition_discipline_v1
  on private.pachanga_competition_events;
create trigger notify_pachanga_competition_discipline_v1
after insert on private.pachanga_competition_events
for each row execute function private.pachanga_competition_discipline_notify_v1();

create or replace function private.pachanga_competition_discipline_catalog_from_rule_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare target_competition_id uuid;
declare target_product_key text;
declare policy jsonb;
begin
  if new.status not in ('published', 'frozen') then return new; end if;
  select sets.competition_id, competitions.product_key
    into target_competition_id, target_product_key
  from public.pachanga_competition_rule_sets sets
  join public.pachanga_competitions competitions on competitions.id = sets.competition_id
  where sets.id = new.rule_set_id;
  if target_product_key <> 'LEAGUE_PRIVATE_BETA_V1' then return new; end if;
  policy := private.pachanga_competition_discipline_default_policy_v1();
  insert into public.pachanga_competition_discipline_rule_catalogs(
    rule_revision_id, competition_id, policy_version, card_type_catalog,
    cycle_policy, sanction_policy, appeal_policy, public_reason_categories,
    checksum, created_by
  ) values (
    new.id, target_competition_id, policy ->> 'policyVersion',
    policy -> 'cardTypeCatalog', policy -> 'cyclePolicy',
    policy -> 'sanctionPolicy', policy -> 'appealPolicy',
    policy -> 'publicReasonCategories',
    encode(extensions.digest(convert_to(policy::text, 'UTF8'), 'sha256'), 'hex'),
    new.created_by
  ) on conflict (rule_revision_id) do nothing;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_discipline_catalog_from_rule_v1()
  from public, anon, authenticated;

drop trigger if exists create_pachanga_competition_discipline_catalog_v1
  on public.pachanga_competition_rule_revisions;
create trigger create_pachanga_competition_discipline_catalog_v1
after insert or update of status on public.pachanga_competition_rule_revisions
for each row execute function private.pachanga_competition_discipline_catalog_from_rule_v1();

insert into public.pachanga_competition_discipline_rule_catalogs(
  rule_revision_id, competition_id, policy_version, card_type_catalog,
  cycle_policy, sanction_policy, appeal_policy, public_reason_categories,
  checksum, created_by
)
select revisions.id, competitions.id, policy.value ->> 'policyVersion',
  policy.value -> 'cardTypeCatalog', policy.value -> 'cyclePolicy',
  policy.value -> 'sanctionPolicy', policy.value -> 'appealPolicy',
  policy.value -> 'publicReasonCategories',
  encode(extensions.digest(convert_to(policy.value::text, 'UTF8'), 'sha256'), 'hex'),
  revisions.created_by
from public.pachanga_competition_rule_revisions revisions
join public.pachanga_competition_rule_sets sets on sets.id = revisions.rule_set_id
join public.pachanga_competitions competitions on competitions.id = sets.competition_id
cross join lateral (select private.pachanga_competition_discipline_default_policy_v1()) policy(value)
where competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
  and revisions.status in ('published', 'frozen')
on conflict (rule_revision_id) do nothing;

create or replace function private.pachanga_league_private_beta_capabilities_v1()
returns text[]
language sql
stable
set search_path = pg_catalog
as $$
  select array[
      'competition_create', 'competition_manage', 'competition_staff',
      'competition_rules', 'competition_categories_manage',
      'competition_entries_manage', 'competition_rosters_review',
      'competition_schedule', 'competition_results', 'competition_standings',
      'competition_operations'
    ]::text[]
    || case when settings.competition_discipline_foundation_enabled then array[
      'competition_discipline_manage',
      'competition_discipline_review',
      'competition_appeals_manage'
    ]::text[] else array[]::text[] end
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

comment on function private.pachanga_league_private_beta_capabilities_v1() is
  'R5 bundle contract. Existing bundles require the explicit R5 upgrade RPC before flags are enabled.';

create or replace function public.command_pachanga_league_private_beta_r5_bundle_upgrade_v1(
  operation_id uuid,
  bundle_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
#variable_conflict use_variable
declare actor_id uuid := (select auth.uid());
declare action_name constant text := 'league_private_beta.bundle.upgrade_r5';
declare template_grant public.pachanga_competition_entitlement_grants%rowtype;
declare organizer_state public.pachanga_competition_organizer_states%rowtype;
declare capability_name text;
declare request_hash text;
declare replay jsonb;
declare sequence_value bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare response jsonb;
declare metadata jsonb;
declare inserted_count integer := 0;
begin
  if operation_id is null or bundle_id is null
     or expected_revision is null or expected_revision < 0 then
    raise exception 'INVALID_R5_BUNDLE_UPGRADE_COMMAND' using errcode = '22023';
  end if;
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  perform private.pachanga_platform_require_v1('competitions.manage');
  perform private.pachanga_platform_require_v1('flags.write');
  metadata := private.pachanga_league_match_sanitize_metadata_v1(client_metadata);
  request_hash := private.pachanga_competition_discipline_request_hash_v1(
    bundle_id, action_name, bundle_id, expected_revision, '{}'::jsonb
  );
  replay := private.pachanga_competition_discipline_replay_v1(
    operation_id, actor_id, action_name, bundle_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into template_grant
  from public.pachanga_competition_entitlement_grants grants
  where grants.bundle_id = bundle_id
    and grants.program_key = 'LEAGUE_PRIVATE_BETA_V1'
    and grants.status = 'active'
    and grants.valid_from <= confirmed_at
    and (grants.expires_at is null or grants.expires_at > confirmed_at)
  order by grants.server_sequence desc, grants.id desc
  limit 1 for update;
  if not found then raise exception 'LEAGUE_BETA_BUNDLE_NOT_ACTIVE' using errcode = 'P0002'; end if;
  select * into organizer_state
  from public.pachanga_competition_organizer_states states
  where states.organizer_kind = template_grant.organizer_kind
    and (
      (states.organizer_kind = 'TEAM'
        and states.organizer_group_id = template_grant.organizer_group_id)
      or (states.organizer_kind = 'CLUB'
        and states.organizer_club_id = template_grant.organizer_club_id)
    ) for update;
  if not found or organizer_state.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  foreach capability_name in array array[
    'competition_discipline_manage',
    'competition_discipline_review',
    'competition_appeals_manage'
  ]::text[] loop
    if not exists (
      select 1 from public.pachanga_competition_entitlement_grants grants
      where grants.bundle_id = bundle_id
        and grants.capability = capability_name
        and grants.status = 'active'
    ) then
      insert into public.pachanga_competition_entitlement_grants(
        organizer_kind, organizer_group_id, organizer_club_id,
        capability, grant_source, status, valid_from, expires_at,
        reason, revision, server_sequence, granted_by,
        program_key, bundle_id, beta_team_cap, created_at, updated_at
      ) values (
        template_grant.organizer_kind, template_grant.organizer_group_id,
        template_grant.organizer_club_id, capability_name,
        template_grant.grant_source, 'active', template_grant.valid_from,
        template_grant.expires_at,
        left('LEAGUE_PRIVATE_BETA_V1 R5 explicit upgrade: ' || template_grant.reason, 1200),
        1, nextval('private.pachanga_competition_sequence'), actor_id,
        'LEAGUE_PRIVATE_BETA_V1', bundle_id, template_grant.beta_team_cap,
        confirmed_at, confirmed_at
      );
      inserted_count := inserted_count + 1;
    end if;
  end loop;
  sequence_value := nextval('private.pachanga_competition_sequence');
  update public.pachanga_competition_organizer_states states set
    revision = states.revision + 1, server_sequence = sequence_value,
    updated_at = confirmed_at
  where states.id = organizer_state.id
  returning * into organizer_state;
  response := jsonb_build_object(
    'operationId', operation_id, 'confirmedRevision', organizer_state.revision,
    'confirmedAt', confirmed_at, 'serverSequence', sequence_value,
    'snapshot', jsonb_build_object(
      'bundleId', bundle_id, 'programKey', 'LEAGUE_PRIVATE_BETA_V1',
      'r5CapabilityCount', 3, 'insertedCapabilities', inserted_count,
      'status', case when private.pachanga_league_private_beta_active_bundle_id_v1(
        template_grant.organizer_kind,
        coalesce(template_grant.organizer_group_id, template_grant.organizer_club_id)
      ) = bundle_id then 'active' else 'incomplete' end
    ),
    'invalidations', jsonb_build_array(jsonb_build_object(
      'entityType', 'league_private_beta_bundle', 'entityId', bundle_id,
      'revision', organizer_state.revision, 'serverSequence', sequence_value
    ))
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, actor_id, 'authenticated', 'competition_discipline',
    bundle_id::text, null, action_name, organizer_state.revision,
    sequence_value, action_name,
    jsonb_build_object('bundleId', bundle_id, 'insertedCapabilities', inserted_count),
    confirmed_at
  );
  insert into public.pachanga_competition_invalidations(
    server_sequence, competition_id, organizer_group_id, organizer_club_id,
    entity_type, entity_id, revision, created_at
  ) values (
    sequence_value, null, template_grant.organizer_group_id,
    template_grant.organizer_club_id, 'league_private_beta_bundle',
    bundle_id::text, organizer_state.revision, confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    operation_id, actor_id, 'authenticated', action_name,
    'competition_discipline', bundle_id::text, request_hash,
    organizer_state.revision, sequence_value, metadata, response, confirmed_at
  );
  return response;
exception
  when unique_violation then raise exception 'R5_BUNDLE_UPGRADE_CONFLICT' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_league_private_beta_r5_bundle_upgrade_v1(
  uuid, uuid, bigint, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_league_private_beta_r5_bundle_upgrade_v1(
  uuid, uuid, bigint, jsonb
) to authenticated;
