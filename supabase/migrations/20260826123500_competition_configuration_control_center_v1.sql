-- Pachangas IQ Wave 5A: platform health and safe dependency shutdown.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_configuration_gate_dependencies_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if not new.foundation_enabled or not new.league_private_beta_enabled then
    new.competition_configuration_center_enabled := false;
    new.league_wizard_v2_enabled := false;
  elsif not new.league_private_beta_creation_enabled then
    new.league_wizard_v2_enabled := false;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_configuration_gate_dependencies_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_competition_configuration_dependencies_v1
  on private.pachanga_competition_foundation_settings;
create trigger guard_pachanga_competition_configuration_dependencies_v1
before insert or update on private.pachanga_competition_foundation_settings
for each row execute function private.pachanga_competition_configuration_gate_dependencies_v1();

create or replace function public.command_pachanga_competition_configuration_platform_v1(
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
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c5a1'::uuid;
declare actor_id uuid := (select auth.uid());
declare actor_kind text;
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare sanitized_metadata jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare sequence_value bigint;
declare confirmed_revision bigint;
declare reason_code text;
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare next_configuration boolean;
declare next_wizard boolean;
declare snapshot jsonb;
begin
  if operation_id is null or aggregate_id is distinct from flags_aggregate_id
     or expected_revision is null or expected_revision < 0
     or normalized_action not in ('configuration.flags.set', 'configuration.kill_switch')
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_COMPETITION_CONFIGURATION_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if payload - array['configurationCenterEnabled','wizardV2Enabled','reason']::text[] <> '{}'::jsonb then
    raise exception 'INVALID_COMPETITION_CONFIGURATION_PLATFORM_PAYLOAD' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'Authentication required' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  else
    perform private.pachanga_platform_require_v1('competitions.manage');
    perform private.pachanga_platform_require_v1('flags.write');
    actor_kind := 'authenticated';
  end if;
  if (payload ? 'configurationCenterEnabled'
      and jsonb_typeof(payload -> 'configurationCenterEnabled') <> 'boolean')
     or (payload ? 'wizardV2Enabled'
      and jsonb_typeof(payload -> 'wizardV2Enabled') <> 'boolean') then
    raise exception 'INVALID_COMPETITION_CONFIGURATION_FLAG' using errcode = '22023';
  end if;
  reason_code := left(trim(coalesce(payload ->> 'reason', '')), 120);
  if length(reason_code) < 3 then
    raise exception 'COMPETITION_CONFIGURATION_REASON_REQUIRED' using errcode = '22023';
  end if;

  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  sanitized_metadata := private.pachanga_competition_client_metadata_v1(
    coalesce(client_metadata, '{}'::jsonb)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91412));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;

  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton
  for update;
  if settings.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;

  if normalized_action = 'configuration.kill_switch' then
    next_configuration := false;
    next_wizard := false;
  else
    next_configuration := coalesce(
      (payload ->> 'configurationCenterEnabled')::boolean,
      settings.competition_configuration_center_enabled
    );
    next_wizard := coalesce(
      (payload ->> 'wizardV2Enabled')::boolean,
      settings.league_wizard_v2_enabled
    );
    if next_configuration and (
      not settings.foundation_enabled or not settings.league_private_beta_enabled
    ) then
      raise exception 'COMPETITION_CONFIGURATION_DEPENDENCIES_DISABLED' using errcode = '0A000';
    end if;
    if next_wizard and (
      not next_configuration or not settings.league_private_beta_creation_enabled
    ) then
      raise exception 'LEAGUE_WIZARD_V2_DEPENDENCIES_DISABLED' using errcode = '0A000';
    end if;
    if not next_configuration then next_wizard := false; end if;
  end if;

  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings foundation_settings set
    competition_configuration_center_enabled = next_configuration,
    league_wizard_v2_enabled = next_wizard,
    revision = foundation_settings.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = confirmed_at
  where foundation_settings.singleton
  returning foundation_settings.revision into confirmed_revision;

  snapshot := jsonb_build_object(
    'configurationCenterEnabled',next_configuration,
    'wizardV2Enabled',next_wizard,
    'leaguePrivateBetaEnabled',settings.league_private_beta_enabled,
    'leagueCreationEnabled',settings.league_private_beta_creation_enabled,
    'publicSurfacesOff',not (
      settings.league_private_beta_public_discovery_enabled
      or settings.league_public_registration_enabled
      or settings.league_public_calendar_enabled
      or settings.league_public_standings_enabled
      or settings.league_public_exception_status_enabled
      or settings.competition_public_discipline_enabled
    ),
    'revision',confirmed_revision,
    'serverSequence',sequence_value,
    'updatedAt',confirmed_at
  );

  return private.pachanga_competition_store_command_v1(
    operation_id,actor_id,actor_kind,normalized_action,
    'competition_configuration_flags',aggregate_id,null,null,
    confirmed_revision,sequence_value,reason_code,request_hash,
    sanitized_metadata,snapshot - 'updatedAt',snapshot,confirmed_at
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_competition_configuration_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_competition_configuration_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated, service_role;

create or replace function public.get_pachanga_platform_competition_configuration_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare drafts jsonb;
declare revisions jsonb;
declare events jsonb;
declare metrics jsonb;
begin
  perform private.pachanga_platform_require_v1('competitions.read');
  select * into settings from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;

  select jsonb_build_object(
    'drafts',count(*) filter (where configuration_drafts.status='draft'),
    'validated',count(*) filter (where configuration_drafts.status='validated'),
    'published',count(*) filter (where configuration_drafts.status='published'),
    'cancelled',count(*) filter (where configuration_drafts.status='cancelled'),
    'blockingErrors',coalesce(sum(jsonb_array_length(
      private.pachanga_competition_configuration_health_v1(
        configuration_drafts.step_data,configuration_drafts.completed_steps
      ) -> 'errors'
    )) filter (where configuration_drafts.status in ('draft','validated')),0),
    'warnings',coalesce(sum(jsonb_array_length(
      private.pachanga_competition_configuration_health_v1(
        configuration_drafts.step_data,configuration_drafts.completed_steps
      ) -> 'warnings'
    )) filter (where configuration_drafts.status in ('draft','validated')),0)
  ) into metrics
  from private.pachanga_competition_configuration_drafts configuration_drafts;

  metrics := metrics || jsonb_build_object(
    'configurationRuleRevisions',(
      select count(*) from public.pachanga_competition_rule_revisions rule_revisions
      where rule_revisions.rule_document #>> '{identity,configurationSchema}'='competition-configuration.v1'
    ),
    'presets',4,
    'legacyBackfillCount',0
  );

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',visible.id,'competitionId',visible.competition_id,'competitionName',visible.competition_name,
    'status',visible.status,'authoringMode',visible.authoring_mode,'presetKey',visible.preset_key,
    'revision',visible.revision,'serverSequence',visible.server_sequence,
    'health',private.pachanga_competition_configuration_health_v1(visible.step_data,visible.completed_steps),
    'impact',visible.impact_snapshot,'updatedAt',visible.updated_at
  ) order by visible.server_sequence desc,visible.id desc),'[]'::jsonb) into drafts
  from (
    select configuration_drafts.*,competitions.name competition_name
    from private.pachanga_competition_configuration_drafts configuration_drafts
    join public.pachanga_competitions competitions on competitions.id=configuration_drafts.competition_id
    order by configuration_drafts.server_sequence desc,configuration_drafts.id desc limit 50
  ) visible;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',visible.id,'competitionId',visible.competition_id,'competitionName',visible.competition_name,
    'version',visible.version,'status',visible.status,'effectiveFrom',visible.effective_from,
    'effectiveScope',visible.effective_scope,'checksum',visible.checksum,
    'serverSequence',visible.server_sequence,'createdAt',visible.created_at
  ) order by visible.server_sequence desc,visible.id desc),'[]'::jsonb) into revisions
  from (
    select rule_revisions.*,rule_sets.competition_id,competitions.name competition_name
    from public.pachanga_competition_rule_revisions rule_revisions
    join public.pachanga_competition_rule_sets rule_sets on rule_sets.id=rule_revisions.rule_set_id
    join public.pachanga_competitions competitions on competitions.id=rule_sets.competition_id
    where rule_revisions.rule_document #>> '{identity,configurationSchema}'='competition-configuration.v1'
    order by rule_revisions.server_sequence desc,rule_revisions.id desc limit 50
  ) visible;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',visible.id,'competitionId',visible.competition_id,'competitionName',visible.competition_name,
    'draftId',visible.draft_id,'ruleRevisionId',visible.rule_revision_id,'action',visible.action,
    'aggregateRevision',visible.aggregate_revision,'serverSequence',visible.server_sequence,
    'reasonCode',visible.reason_code,'confirmedAt',visible.confirmed_at
  ) order by visible.server_sequence desc,visible.id desc),'[]'::jsonb) into events
  from (
    select configuration_events.*,competitions.name competition_name
    from private.pachanga_competition_configuration_events configuration_events
    join public.pachanga_competitions competitions on competitions.id=configuration_events.competition_id
    order by configuration_events.server_sequence desc,configuration_events.id desc limit 50
  ) visible;

  return jsonb_build_object(
    'flags',jsonb_build_object(
      'configurationCenterEnabled',settings.competition_configuration_center_enabled,
      'wizardV2Enabled',settings.league_wizard_v2_enabled,
      'leaguePrivateBetaEnabled',settings.league_private_beta_enabled,
      'leagueCreationEnabled',settings.league_private_beta_creation_enabled,
      'publicSurfacesOff',not (
        settings.league_private_beta_public_discovery_enabled
        or settings.league_public_registration_enabled
        or settings.league_public_calendar_enabled
        or settings.league_public_standings_enabled
        or settings.league_public_exception_status_enabled
        or settings.competition_public_discipline_enabled
      ),
      'revision',settings.revision,'serverSequence',settings.server_sequence,'updatedAt',settings.updated_at
    ),
    'metrics',metrics,'drafts',drafts,'revisions',revisions,'events',events,
    'rollbackPolicy','publish_new_revision_never_down_migration',
    'unavailable',jsonb_build_array('payments','tournaments','manual_assisted_pairing','hybrid_pairing','public_surfaces')
  );
end;
$$;

revoke all on function public.get_pachanga_platform_competition_configuration_v1()
  from public, anon;
grant execute on function public.get_pachanga_platform_competition_configuration_v1()
  to authenticated, service_role;

comment on function public.get_pachanga_platform_competition_configuration_v1() is
  'Platform-only Wave 5A health. It exposes no private referee fee or browser-authored authority.';
