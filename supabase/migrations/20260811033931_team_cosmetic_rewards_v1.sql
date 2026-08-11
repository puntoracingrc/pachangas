-- Team Cosmetic Rewards V1.
-- Canonical V3 achievement grants may unlock one team-owned shield cosmetic.
-- The policy is installed ready but remains disabled until an explicit,
-- audited activation establishes the non-retroactive server-sequence frontier.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.pachanga_team_cosmetic_reward_policies (
  policy_version integer primary key,
  policy_key text not null unique,
  state text not null default 'ready',
  effective_from timestamptz,
  effective_from_server_sequence bigint,
  activation_operation_id uuid unique,
  activated_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (policy_version >= 1),
  check (state in ('ready', 'active')),
  check (
    (state = 'ready' and effective_from is null
      and effective_from_server_sequence is null and activated_at is null)
    or (state = 'active' and effective_from is not null
      and effective_from_server_sequence is not null and activated_at is not null)
  )
);

create table if not exists private.pachanga_team_cosmetic_reward_mappings (
  policy_version integer not null references private.pachanga_team_cosmetic_reward_policies(policy_version) on delete restrict,
  mapping_key text not null,
  achievement_key text not null,
  cosmetic_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  first_occurrence_only boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  primary key (policy_version, mapping_key),
  unique (policy_version, achievement_key),
  unique (policy_version, cosmetic_key)
);

create table if not exists private.pachanga_team_cosmetic_reward_policy_events (
  operation_id uuid primary key,
  policy_version integer not null references private.pachanga_team_cosmetic_reward_policies(policy_version) on delete restrict,
  requested_enabled boolean not null,
  request_hash text not null,
  server_sequence bigint not null,
  response jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  check (server_sequence >= 1),
  check (jsonb_typeof(response) = 'object')
);

create table if not exists private.pachanga_team_cosmetic_reward_ledger (
  id uuid primary key default gen_random_uuid(),
  operation_id uuid not null unique,
  policy_version integer not null,
  mapping_key text not null,
  group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  achievement_grant_id uuid not null references public.pachanga_achievement_grants(id) on delete restrict,
  achievement_definition_id uuid not null references public.pachanga_achievement_definitions(id) on delete restrict,
  origin_match_fact_id uuid not null references public.pachanga_progression_match_facts(id) on delete restrict,
  achievement_key text not null,
  cosmetic_key text not null references public.pachanga_cosmetic_catalog(cosmetic_key) on delete restrict,
  outcome text not null,
  shield_revision bigint not null,
  server_sequence bigint not null,
  response jsonb not null,
  evidence jsonb not null default '{}'::jsonb,
  processed_at timestamptz not null default clock_timestamp(),
  foreign key (policy_version, mapping_key)
    references private.pachanga_team_cosmetic_reward_mappings(policy_version, mapping_key) on delete restrict,
  unique (policy_version, mapping_key, group_id),
  unique (policy_version, mapping_key, achievement_grant_id),
  check (outcome in ('granted', 'already_owned')),
  check (shield_revision >= 0),
  check (server_sequence >= 1),
  check (jsonb_typeof(response) = 'object'),
  check (jsonb_typeof(evidence) = 'object')
);

create index if not exists pachanga_team_cosmetic_reward_ledger_group_idx
  on private.pachanga_team_cosmetic_reward_ledger(group_id, server_sequence desc, id desc);
create index if not exists pachanga_team_cosmetic_reward_ledger_achievement_idx
  on private.pachanga_team_cosmetic_reward_ledger(achievement_grant_id, policy_version, mapping_key);

alter table private.pachanga_team_cosmetic_reward_policies enable row level security;
alter table private.pachanga_team_cosmetic_reward_mappings enable row level security;
alter table private.pachanga_team_cosmetic_reward_policy_events enable row level security;
alter table private.pachanga_team_cosmetic_reward_ledger enable row level security;

revoke all on table private.pachanga_team_cosmetic_reward_policies from public, anon, authenticated;
revoke all on table private.pachanga_team_cosmetic_reward_mappings from public, anon, authenticated;
revoke all on table private.pachanga_team_cosmetic_reward_policy_events from public, anon, authenticated;
revoke all on table private.pachanga_team_cosmetic_reward_ledger from public, anon, authenticated;

insert into private.pachanga_team_cosmetic_reward_policies(
  policy_version, policy_key, state
) values (
  1, 'team_cosmetic_rewards_v1', 'ready'
) on conflict (policy_version) do nothing;

insert into private.pachanga_team_cosmetic_reward_mappings(
  policy_version, mapping_key, achievement_key, cosmetic_key, first_occurrence_only
) values
  (1, 'first_challenge_win', 'team.external.wins.001', 'team.shield.border.copper', true),
  (1, 'ten_challenges', 'team.external.matches.010', 'team.shield.ornament.banner', false),
  (1, 'twenty_five_matches', 'team.matches.025', 'team.shield.ornament.laurels', false),
  (1, 'fifty_matches', 'team.matches.050', 'team.shield.border.silver', false),
  (1, 'first_clean_sheet', 'team.external.clean_sheets.001', 'team.shield.effect.edge_glow', true)
on conflict (policy_version, mapping_key) do nothing;

-- This is a new V3 authority row. The disabled V1/V2 rows remain historical.
insert into public.pachanga_achievement_definitions(
  achievement_key, version, title, description, subject_type, match_scope,
  category, evaluator_key, parameters, threshold, rarity, repeatable,
  reward_kind, active, catalog_key, family_key, display_priority, icon_key,
  box_rarity, reward_pool_version, animation_key, presentation_key,
  activation_server_sequence, catalog_disposition, reward_components
) values (
  'team.external.matches.010', 3, 'Diez Retos',
  'Completa diez Retos canonicos contra otros equipos.',
  'team', 'external', 'matches', 'TEAM_MATCHES', '{}'::jsonb, 10,
  'uncommon', false, 'none', true, 'achievement_catalog_v3',
  'team.external.matches', 21, 'matches', 'uncommon', 1,
  'reward_box_blue', 'box.uncommon',
  (select last_value + 1 from public.pachanga_progression_sequence),
  'MIGRATE',
  '[{"key":"team_external_matches_10","label":"Diez Retos","boxRarity":"uncommon"}]'::jsonb
) on conflict (achievement_key, version) do nothing;

create or replace function private.pachanga_set_team_cosmetic_rewards_enabled_v1(
  target_enabled boolean,
  target_operation_id uuid,
  target_policy_version integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_policy private.pachanga_team_cosmetic_reward_policies%rowtype;
  selected_event private.pachanga_team_cosmetic_reward_policy_events%rowtype;
  request_hash text;
  activation_frontier bigint;
  event_sequence bigint;
  response jsonb;
begin
  if target_operation_id is null or target_policy_version is null then
    raise exception 'Policy version and operation id required';
  end if;
  request_hash := md5(jsonb_build_object(
    'policyVersion', target_policy_version,
    'enabled', target_enabled
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(
    'team-cosmetic-reward-policy:' || target_policy_version::text, 0
  ));
  select * into selected_event
  from private.pachanga_team_cosmetic_reward_policy_events events
  where events.operation_id = target_operation_id;
  if found then
    if selected_event.request_hash <> request_hash then
      raise exception 'Operation id belongs to another reward policy action';
    end if;
    return selected_event.response;
  end if;

  select * into selected_policy
  from private.pachanga_team_cosmetic_reward_policies policies
  where policies.policy_version = target_policy_version
  for update;
  if not found then raise exception 'Team cosmetic reward policy not found'; end if;

  if target_enabled then
    if exists (
      select 1
      from private.pachanga_team_cosmetic_reward_mappings mappings
      left join public.pachanga_cosmetic_catalog catalog
        on catalog.cosmetic_key = mappings.cosmetic_key
       and catalog.active and catalog.lifecycle = 'active_reward'
       and catalog.availability = 'achievement'
      left join public.pachanga_achievement_definitions definitions
        on definitions.achievement_key = mappings.achievement_key
       and definitions.version = 3 and definitions.active
      where mappings.policy_version = target_policy_version
        and mappings.active
        and (catalog.cosmetic_key is null or definitions.id is null)
    ) then
      raise exception 'Team cosmetic reward policy has unavailable mappings';
    end if;
    if selected_policy.state = 'ready' then
      activation_frontier := nextval('public.pachanga_progression_sequence');
      update private.pachanga_team_cosmetic_reward_policies policies
      set state = 'active',
          effective_from = clock_timestamp(),
          effective_from_server_sequence = activation_frontier,
          activation_operation_id = target_operation_id,
          activated_at = clock_timestamp(),
          updated_at = clock_timestamp()
      where policies.policy_version = target_policy_version
      returning * into selected_policy;
    end if;
  end if;

  update private.pachanga_team_cosmetic_settings settings
  set team_cosmetic_rewards_enabled = target_enabled,
      updated_at = clock_timestamp()
  where settings.singleton;

  event_sequence := nextval('public.pachanga_team_crest_sequence');
  response := jsonb_build_object(
    'policyVersion', target_policy_version,
    'enabled', target_enabled,
    'state', selected_policy.state,
    'effectiveFrom', selected_policy.effective_from,
    'effectiveFromServerSequence', selected_policy.effective_from_server_sequence,
    'serverSequence', event_sequence,
    'operationId', target_operation_id,
    'confirmedAt', clock_timestamp()
  );
  insert into private.pachanga_team_cosmetic_reward_policy_events(
    operation_id, policy_version, requested_enabled, request_hash,
    server_sequence, response
  ) values (
    target_operation_id, target_policy_version, target_enabled, request_hash,
    event_sequence, response
  );
  return response;
end;
$$;

create or replace function private.pachanga_apply_team_cosmetic_reward_v1(
  target_achievement_grant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected_grant public.pachanga_achievement_grants%rowtype;
  selected_definition public.pachanga_achievement_definitions%rowtype;
  selected_fact public.pachanga_progression_match_facts%rowtype;
  selected_policy private.pachanga_team_cosmetic_reward_policies%rowtype;
  selected_mapping private.pachanga_team_cosmetic_reward_mappings%rowtype;
  selected_ledger private.pachanga_team_cosmetic_reward_ledger%rowtype;
  selected_catalog public.pachanga_cosmetic_catalog%rowtype;
  selected_group public.pachanga_groups%rowtype;
  selected_state public.pachanga_team_shield_state%rowtype;
  selected_inventory public.pachanga_team_cosmetic_inventory%rowtype;
  selected_loadout public.pachanga_team_shield_loadouts%rowtype;
  selected_config jsonb;
  operation_id uuid;
  request_hash text;
  next_sequence bigint;
  changed boolean;
  confirmed_revision bigint;
  response jsonb;
  recipient record;
begin
  if target_achievement_grant_id is null then return null; end if;
  select * into selected_grant
  from public.pachanga_achievement_grants grants
  where grants.id = target_achievement_grant_id and grants.state = 'active';
  if not found or selected_grant.subject_type <> 'team' then return null; end if;

  select * into selected_definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = selected_grant.definition_id
    and definitions.version = 3;
  if not found then return null; end if;
  select * into selected_fact
  from public.pachanga_progression_match_facts facts
  where facts.id = selected_grant.origin_match_fact_id and facts.state = 'active';
  if not found then return null; end if;

  select policies.* into selected_policy
  from private.pachanga_team_cosmetic_reward_policies policies
  where policies.state = 'active'
  order by policies.policy_version desc
  limit 1;
  if not found
    or selected_fact.server_sequence <= selected_policy.effective_from_server_sequence
    or not private.pachanga_team_cosmetic_rewards_enabled_v1() then
    return null;
  end if;

  select mappings.* into selected_mapping
  from private.pachanga_team_cosmetic_reward_mappings mappings
  where mappings.policy_version = selected_policy.policy_version
    and mappings.achievement_key = selected_definition.achievement_key
    and mappings.active;
  if not found then return null; end if;
  if selected_mapping.first_occurrence_only and not selected_grant.is_first then
    return null;
  end if;
  if not selected_definition.repeatable
    and selected_grant.metric_value is distinct from selected_definition.threshold then
    return null;
  end if;

  operation_id := md5(
    'team-cosmetic-reward:' || selected_policy.policy_version::text || ':'
      || selected_mapping.mapping_key || ':' || selected_grant.group_id::text
  )::uuid;
  request_hash := md5(jsonb_build_object(
    'policyVersion', selected_policy.policy_version,
    'mappingKey', selected_mapping.mapping_key,
    'groupId', selected_grant.group_id,
    'achievementGrantId', selected_grant.id,
    'cosmeticKey', selected_mapping.cosmetic_key
  )::text);

  perform pg_advisory_xact_lock(hashtextextended(
    'team-cosmetic-reward:' || selected_policy.policy_version::text || ':'
      || selected_mapping.mapping_key || ':' || selected_grant.group_id::text, 0
  ));
  select * into selected_ledger
  from private.pachanga_team_cosmetic_reward_ledger ledger
  where ledger.policy_version = selected_policy.policy_version
    and ledger.mapping_key = selected_mapping.mapping_key
    and ledger.group_id = selected_grant.group_id;
  if found then return selected_ledger.response; end if;

  select * into selected_catalog
  from public.pachanga_cosmetic_catalog catalog
  where catalog.cosmetic_key = selected_mapping.cosmetic_key
    and catalog.owner_scope = 'team'
    and catalog.active
    and catalog.lifecycle = 'active_reward'
    and catalog.availability = 'achievement';
  if not found then raise exception 'Mapped team cosmetic is unavailable'; end if;
  select * into selected_group
  from public.pachanga_groups groups
  where groups.id = selected_grant.group_id;
  if not found then raise exception 'Mapped team not found'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'team-shield-group:' || selected_grant.group_id::text, 0
  ));
  insert into public.pachanga_team_shield_state(group_id)
  values (selected_grant.group_id)
  on conflict (group_id) do nothing;
  select * into selected_state
  from public.pachanga_team_shield_state states
  where states.group_id = selected_grant.group_id
  for update;
  select * into selected_inventory
  from public.pachanga_team_cosmetic_inventory inventory
  where inventory.group_id = selected_grant.group_id
    and inventory.cosmetic_key = selected_mapping.cosmetic_key
  for update;
  changed := not found or selected_inventory.state <> 'unlocked';
  next_sequence := nextval('public.pachanga_team_crest_sequence');

  if changed then
    insert into public.pachanga_team_cosmetic_inventory(
      group_id, cosmetic_key, source_grant_id, state, unlocked_at, revoked_at,
      revision, operation_id, source_kind, server_sequence, metadata
    ) values (
      selected_grant.group_id, selected_mapping.cosmetic_key, selected_grant.id,
      'unlocked', clock_timestamp(), null, 1, operation_id, 'achievement',
      next_sequence, jsonb_build_object(
        'policyVersion', selected_policy.policy_version,
        'mappingKey', selected_mapping.mapping_key,
        'achievementKey', selected_definition.achievement_key,
        'achievementGrantId', selected_grant.id,
        'originMatchFactId', selected_grant.origin_match_fact_id
      )
    ) on conflict (group_id, cosmetic_key) do update set
      source_grant_id = excluded.source_grant_id,
      state = 'unlocked',
      unlocked_at = clock_timestamp(),
      revoked_at = null,
      revision = public.pachanga_team_cosmetic_inventory.revision + 1,
      operation_id = excluded.operation_id,
      source_kind = excluded.source_kind,
      server_sequence = excluded.server_sequence,
      metadata = excluded.metadata;
    update public.pachanga_team_shield_state states
    set revision = states.revision + 1,
        server_sequence = next_sequence,
        updated_at = clock_timestamp()
    where states.group_id = selected_grant.group_id;
    select * into selected_loadout
    from public.pachanga_team_shield_loadouts loadouts
    where loadouts.group_id = selected_grant.group_id;
    selected_config := coalesce(
      selected_loadout.config,
      private.pachanga_default_team_shield_config_v1(selected_group.name)
    );
    perform private.pachanga_upsert_team_shield_public_v1(
      selected_grant.group_id, selected_state.revision + 1,
      next_sequence, selected_config
    );
  end if;
  confirmed_revision := selected_state.revision + case when changed then 1 else 0 end;

  response := jsonb_build_object(
    'operationId', operation_id,
    'policyVersion', selected_policy.policy_version,
    'mappingKey', selected_mapping.mapping_key,
    'achievementKey', selected_definition.achievement_key,
    'achievementGrantId', selected_grant.id,
    'groupId', selected_grant.group_id,
    'cosmeticKey', selected_mapping.cosmetic_key,
    'granted', changed,
    'alreadyOwned', not changed,
    'currencyGranted', 0,
    'confirmedRevision', confirmed_revision,
    'serverSequence', next_sequence,
    'confirmedAt', clock_timestamp()
  );

  insert into public.pachanga_team_shield_events(
    operation_id, event_type, group_id, cosmetic_key, actor_user_id,
    confirmed_revision, server_sequence, payload
  ) values (
    operation_id,
    case when changed then 'team_cosmetic_granted' else 'team_cosmetic_already_owned' end,
    selected_grant.group_id, selected_mapping.cosmetic_key, null,
    confirmed_revision, next_sequence,
    jsonb_build_object(
      'sourceKind', 'achievement',
      'policyVersion', selected_policy.policy_version,
      'mappingKey', selected_mapping.mapping_key,
      'achievementKey', selected_definition.achievement_key,
      'achievementGrantId', selected_grant.id,
      'duplicate', not changed
    )
  );
  insert into public.pachanga_team_shield_operation_receipts(
    operation_id, operation_kind, group_id, actor_user_id, request_hash,
    expected_revision, confirmed_revision, server_sequence, response,
    client_metadata
  ) values (
    operation_id, 'grant', selected_grant.group_id, null, request_hash,
    selected_state.revision, confirmed_revision, next_sequence, response,
    jsonb_build_object('surface', 'achievement-v3-bridge', 'policyVersion', selected_policy.policy_version)
  );
  insert into private.pachanga_team_cosmetic_reward_ledger(
    operation_id, policy_version, mapping_key, group_id,
    achievement_grant_id, achievement_definition_id, origin_match_fact_id,
    achievement_key, cosmetic_key, outcome, shield_revision,
    server_sequence, response, evidence
  ) values (
    operation_id, selected_policy.policy_version, selected_mapping.mapping_key,
    selected_grant.group_id, selected_grant.id, selected_definition.id,
    selected_grant.origin_match_fact_id, selected_definition.achievement_key,
    selected_mapping.cosmetic_key,
    case when changed then 'granted' else 'already_owned' end,
    confirmed_revision, next_sequence, response,
    jsonb_build_object(
      'achievementIsFirst', selected_grant.is_first,
      'achievementSequenceCount', selected_grant.sequence_count,
      'achievementMetricValue', selected_grant.metric_value,
      'factServerSequence', selected_fact.server_sequence,
      'policyEffectiveFrom', selected_policy.effective_from,
      'policyEffectiveFromServerSequence', selected_policy.effective_from_server_sequence
    )
  );

  if changed then
    for recipient in
      select eligibility.admin_user_id
      from public.pachanga_team_cosmetic_admin_eligibility eligibility
      where eligibility.group_id = selected_grant.group_id
        and eligibility.role in ('owner', 'admin')
      order by eligibility.admin_user_id
    loop
      perform private.pachanga_notify_v1(
        recipient.admin_user_id,
        'team_cosmetic_reward',
        'Nuevo cosmetico de equipo',
        selected_group.name || ' ha desbloqueado ' || selected_catalog.display_name || '.',
        '/equipo/identidad?grupo=' || selected_grant.group_id::text
          || '&cosmetic=' || selected_mapping.cosmetic_key,
        jsonb_build_object(
          'groupId', selected_grant.group_id,
          'cosmeticKey', selected_mapping.cosmetic_key,
          'slot', selected_catalog.slot,
          'policyVersion', selected_policy.policy_version
        ),
        'team-cosmetic-reward:' || operation_id::text || ':' || recipient.admin_user_id::text
      );
    end loop;
  end if;
  return response;
end;
$$;

create or replace function private.pachanga_team_cosmetic_reward_bridge_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform private.pachanga_apply_team_cosmetic_reward_v1(new.id);
  return new;
end;
$$;

drop trigger if exists apply_team_cosmetic_reward_v1 on public.pachanga_achievement_grants;
create trigger apply_team_cosmetic_reward_v1
after insert on public.pachanga_achievement_grants
for each row execute function private.pachanga_team_cosmetic_reward_bridge_v1();

revoke all on function private.pachanga_set_team_cosmetic_rewards_enabled_v1(boolean, uuid, integer)
  from public, anon, authenticated;
revoke all on function private.pachanga_apply_team_cosmetic_reward_v1(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_team_cosmetic_reward_bridge_v1()
  from public, anon, authenticated;

alter function private.pachanga_set_team_cosmetic_rewards_enabled_v1(boolean, uuid, integer)
  set lock_timeout = '1s';
alter function private.pachanga_apply_team_cosmetic_reward_v1(uuid)
  set lock_timeout = '1s';

comment on table private.pachanga_team_cosmetic_reward_mappings is
  'Versioned policy mapping canonical V3 team achievements to direct team-owned shield cosmetics.';
comment on table private.pachanga_team_cosmetic_reward_ledger is
  'Private immutable evidence for every granted or already-owned Team Cosmetic Reward V1 mapping.';
comment on function private.pachanga_apply_team_cosmetic_reward_v1(uuid) is
  'Internal idempotent V3 achievement consumer. It never recalculates sporting facts and never grants team currency.';
