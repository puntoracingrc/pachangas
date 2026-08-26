-- Pachangas IQ Wave 5A: 12-step League Wizard V2.
-- The V1 command is retained only as a compatibility alias to this server-authoritative command.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter function public.command_pachanga_league_private_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) rename to command_pachanga_league_private_beta_legacy_v1;

revoke all on function public.command_pachanga_league_private_beta_legacy_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated;

alter function private.pachanga_league_private_beta_store_v1(
  uuid, uuid, text, text, uuid, text, uuid, uuid, uuid,
  bigint, bigint, text, text, jsonb, jsonb, jsonb, timestamptz
) rename to pachanga_league_private_beta_store_legacy_v1;

revoke all on function private.pachanga_league_private_beta_store_legacy_v1(
  uuid, uuid, text, text, uuid, text, uuid, uuid, uuid,
  bigint, bigint, text, text, jsonb, jsonb, jsonb, timestamptz
) from public, anon, authenticated;

create or replace function private.pachanga_league_private_beta_initialize_wizard_v2()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
declare selected_mode text := upper(coalesce(
  nullif(current_setting('pachangas.league_wizard_v2_mode', true), ''),
  'SIMPLE'
));
declare selected_preset text := upper(coalesce(
  nullif(current_setting('pachangas.league_wizard_v2_preset', true), ''),
  'LEAGUE_F7_STANDARD'
));
begin
  if selected_mode not in ('SIMPLE', 'ADVANCED') then selected_mode := 'SIMPLE'; end if;
  new.wizard_version := 2;
  new.authoring_mode := selected_mode;
  new.preset_key := selected_preset;
  new.current_step := 1;
  new.completed_steps := '{}'::smallint[];
  new.step_data := private.pachanga_competition_authoring_preset_v1(selected_preset) -> 'steps';
  new.consented_at := null;
  return new;
end;
$$;

revoke all on function private.pachanga_league_private_beta_initialize_wizard_v2()
  from public, anon, authenticated;

drop trigger if exists pachanga_league_private_beta_initialize_wizard_v2
  on private.pachanga_league_private_beta_wizards;
create trigger pachanga_league_private_beta_initialize_wizard_v2
before insert on private.pachanga_league_private_beta_wizards
for each row execute function private.pachanga_league_private_beta_initialize_wizard_v2();

create or replace function private.pachanga_league_private_beta_store_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_type text,
  target_aggregate_id uuid,
  target_organizer_kind text,
  target_organizer_id uuid,
  target_wizard_id uuid,
  target_competition_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_reason_code text,
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
declare patched_snapshot jsonb := coalesce(target_snapshot, '{}'::jsonb);
declare wizard private.pachanga_league_private_beta_wizards%rowtype;
begin
  if target_wizard_id is not null and target_action in ('wizard.create', 'wizard.finalize') then
    select * into wizard
    from private.pachanga_league_private_beta_wizards wizards
    where wizards.id = target_wizard_id;
    if found and wizard.wizard_version = 2 then
      patched_snapshot := jsonb_set(
        patched_snapshot,
        '{wizard}',
        private.pachanga_league_private_beta_wizard_snapshot_v1(wizard.id),
        true
      );
      if target_action = 'wizard.finalize' then
        patched_snapshot := jsonb_set(
          patched_snapshot,
          '{configurationHealth}',
          private.pachanga_competition_configuration_health_v1(
            wizard.step_data, wizard.completed_steps
          ),
          true
        );
        patched_snapshot := jsonb_set(
          patched_snapshot,
          '{unavailable}',
          jsonb_build_array(
            'payments', 'tournaments', 'manual_assisted_pairing', 'hybrid_pairing'
          ),
          true
        );
      end if;
    end if;
  end if;
  return private.pachanga_league_private_beta_store_legacy_v1(
    target_operation_id, target_actor_id, target_action, target_aggregate_type,
    target_aggregate_id, target_organizer_kind, target_organizer_id,
    target_wizard_id, target_competition_id, target_confirmed_revision,
    target_server_sequence, target_reason_code, target_request_hash,
    target_client_metadata, target_event_payload, patched_snapshot,
    target_confirmed_at
  );
end;
$$;

revoke all on function private.pachanga_league_private_beta_store_v1(
  uuid, uuid, text, text, uuid, text, uuid, uuid, uuid,
  bigint, bigint, text, text, jsonb, jsonb, jsonb, timestamptz
) from public, anon, authenticated;

create or replace function private.pachanga_league_private_beta_authoring_command_v2(
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
declare action_name text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare wizard private.pachanga_league_private_beta_wizards%rowtype;
declare organizer jsonb;
declare organizer_id uuid;
declare bundle jsonb;
declare selected_step smallint;
declare normalized_step jsonb;
declare selected_mode text;
declare selected_preset text;
declare preset jsonb;
declare next_steps jsonb;
declare next_completed smallint[];
declare sequence_value bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare snapshot jsonb;
declare event_payload jsonb;
declare response jsonb;
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  if actor_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or action_name not in (
       'wizard.mode.set','wizard.preset.apply','wizard.step.save'
     ) or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_LEAGUE_BETA_COMMAND' using errcode = '22023';
  end if;
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.league_private_beta_enabled
     or not settings.competition_configuration_center_enabled
     or not settings.league_wizard_v2_enabled then
    raise exception 'LEAGUE_WIZARD_V2_DISABLED' using errcode = '42501';
  end if;
  request_hash := private.pachanga_competition_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91409));
  replay := private.pachanga_league_private_beta_replay_v1(
    operation_id, actor_id, action_name, 'league_private_beta_wizard',
    aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  perform private.pachanga_league_private_beta_rate_limit_v1(
    actor_id, action_name, 240, interval '1 hour'
  );
  select * into wizard
  from private.pachanga_league_private_beta_wizards wizards
  where wizards.id = aggregate_id for update;
  if not found then raise exception 'LEAGUE_BETA_WIZARD_NOT_FOUND' using errcode = 'P0002'; end if;
  organizer_id := coalesce(wizard.organizer_group_id, wizard.organizer_club_id);
  organizer := private.pachanga_league_private_beta_authorize_organizer_v1(
    wizard.organizer_kind, organizer_id, actor_id, true
  );
  bundle := organizer -> 'bundle';
  if wizard.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if wizard.status <> 'draft' or wizard.wizard_version <> 2 then
    raise exception 'LEAGUE_BETA_WIZARD_NOT_EDITABLE' using errcode = '22023';
  end if;
  sequence_value := nextval('private.pachanga_competition_sequence');

  if action_name = 'wizard.mode.set' then
    selected_mode := upper(trim(coalesce(payload ->> 'mode', '')));
    if selected_mode not in ('SIMPLE','ADVANCED')
       or payload - array['mode','reason'] <> '{}'::jsonb then
      raise exception 'LEAGUE_BETA_AUTHORING_MODE_INVALID' using errcode = '22023';
    end if;
    update private.pachanga_league_private_beta_wizards wizards set
      authoring_mode = selected_mode,
      revision = wizards.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where wizards.id = wizard.id returning * into wizard;
    event_payload := jsonb_build_object('wizardId',wizard.id,'authoringMode',selected_mode);
  elsif action_name = 'wizard.preset.apply' then
    selected_preset := upper(trim(coalesce(payload ->> 'presetKey', '')));
    if payload - array['presetKey','reason'] <> '{}'::jsonb then
      raise exception 'COMPETITION_CONFIGURATION_PRESET_INVALID' using errcode = '22023';
    end if;
    preset := private.pachanga_competition_authoring_preset_v1(selected_preset);
    next_steps := preset -> 'steps';
    if wizard.step_data ? '1' then
      next_steps := jsonb_set(next_steps, '{1}', wizard.step_data -> '1', true);
    end if;
    if wizard.step_data ? '3' then
      next_steps := jsonb_set(next_steps, '{3}', wizard.step_data -> '3', true);
    end if;
    select coalesce(array_agg(completed order by completed), '{}'::smallint[])
      into next_completed
    from unnest(wizard.completed_steps) completed where completed in (1,3);
    update private.pachanga_league_private_beta_wizards wizards set
      preset_key = selected_preset,
      step_data = next_steps,
      completed_steps = next_completed,
      current_step = case when 1 = any(next_completed) then 2 else 1 end,
      consented_at = null,
      revision = wizards.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where wizards.id = wizard.id returning * into wizard;
    event_payload := jsonb_build_object(
      'wizardId',wizard.id,'presetKey',selected_preset,'presetVersion',preset -> 'version'
    );
  else
    begin selected_step := (payload ->> 'step')::smallint;
    exception when others then
      raise exception 'LEAGUE_BETA_STEP_INVALID' using errcode = '22023';
    end;
    if selected_step not between 10 and 12
       or payload - array['step','data','reason'] <> '{}'::jsonb then
      raise exception 'LEAGUE_BETA_STEP_INVALID' using errcode = '22023';
    end if;
    if exists (
      select 1 from generate_series(1, selected_step - 1) required_step
      where not (required_step::smallint = any(wizard.completed_steps))
    ) then raise exception 'LEAGUE_BETA_STEP_ORDER_REQUIRED' using errcode = 'PT409'; end if;
    normalized_step := private.pachanga_league_private_beta_normalize_step_v1(
      selected_step, payload -> 'data', bundle
    );
    update private.pachanga_league_private_beta_wizards wizards set
      step_data = jsonb_set(wizards.step_data, array[selected_step::text], normalized_step, true),
      completed_steps = array(
        select distinct completed
        from unnest(wizards.completed_steps || selected_step) completed
        order by completed
      ),
      current_step = least(12, greatest(wizards.current_step, selected_step + 1)),
      consented_at = case when selected_step = 12
        and coalesce((normalized_step ->> 'consent')::boolean, false)
        then confirmed_at else null end,
      revision = wizards.revision + 1,
      server_sequence = sequence_value,
      updated_at = confirmed_at
    where wizards.id = wizard.id returning * into wizard;
    event_payload := jsonb_build_object(
      'wizardId',wizard.id,'step',selected_step,'completedSteps',to_jsonb(wizard.completed_steps)
    );
  end if;

  snapshot := private.pachanga_league_private_beta_wizard_snapshot_v1(wizard.id);
  response := private.pachanga_league_private_beta_store_v1(
    operation_id, actor_id, action_name, 'league_private_beta_wizard', wizard.id,
    wizard.organizer_kind, organizer_id, wizard.id, wizard.competition_id,
    wizard.revision, sequence_value,
    left(coalesce(nullif(trim(payload ->> 'reason'), ''), action_name), 120),
    request_hash, client_metadata, event_payload, snapshot, confirmed_at
  );
  return response;
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function private.pachanga_league_private_beta_authoring_command_v2(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated;

create or replace function public.command_pachanga_league_private_beta_v2(
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
declare action_name text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare actor_id uuid := auth.uid();
declare response jsonb;
declare wizard private.pachanga_league_private_beta_wizards%rowtype;
declare selected_preset_key text;
declare selected_mode text;
declare health jsonb;
declare step_twelve jsonb;
declare request_hash text;
declare replay jsonb;
begin
  if action_name in ('wizard.mode.set','wizard.preset.apply')
     or (action_name = 'wizard.step.save'
       and coalesce(nullif(payload ->> 'step', '')::integer, 0) between 10 and 12) then
    return private.pachanga_league_private_beta_authoring_command_v2(
      operation_id, aggregate_id, expected_revision, action_name, payload, client_metadata
    );
  end if;

  if action_name = 'wizard.create' then
    selected_preset_key := upper(coalesce(
      nullif(payload ->> 'presetKey', ''), 'LEAGUE_F7_STANDARD'
    ));
    selected_mode := case upper(coalesce(payload ->> 'authoringMode', 'SIMPLE'))
      when 'ADVANCED' then 'ADVANCED' else 'SIMPLE' end;
    if payload - array['organizerKind','authoringMode','presetKey','reason'] <> '{}'::jsonb then
      raise exception 'INVALID_LEAGUE_BETA_COMMAND' using errcode = '22023';
    end if;
    perform private.pachanga_competition_authoring_preset_v1(selected_preset_key);
    perform set_config('pachangas.league_wizard_v2_mode', selected_mode, true);
    perform set_config('pachangas.league_wizard_v2_preset', selected_preset_key, true);
    response := public.command_pachanga_league_private_beta_legacy_v1(
      operation_id, aggregate_id, expected_revision, action_name,
      payload, client_metadata
    );
    return response;
  end if;

  if action_name in ('wizard.step.save','wizard.cancel') then
    response := public.command_pachanga_league_private_beta_legacy_v1(
      operation_id, aggregate_id, expected_revision, action_name, payload, client_metadata
    );
    return response;
  end if;

  if action_name = 'wizard.finalize' then
    request_hash := private.pachanga_competition_request_hash_v1(
      action_name, aggregate_id, expected_revision, payload
    );
    replay := private.pachanga_league_private_beta_replay_v1(
      operation_id, actor_id, action_name, 'league_private_beta_wizard',
      aggregate_id, request_hash
    );
    if replay is not null then return replay; end if;
    select * into wizard from private.pachanga_league_private_beta_wizards wizards
    where wizards.id = aggregate_id for update;
    if not found then raise exception 'LEAGUE_BETA_WIZARD_NOT_FOUND' using errcode = 'P0002'; end if;
    if wizard.revision <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if wizard.status <> 'draft' or wizard.wizard_version <> 2
       or not (array[1,2,3,4,5,6,7,8,9,10,11,12]::smallint[] <@ wizard.completed_steps) then
      raise exception 'LEAGUE_BETA_WIZARD_INCOMPLETE' using errcode = '22023';
    end if;
    health := private.pachanga_competition_configuration_health_v1(
      wizard.step_data, wizard.completed_steps
    );
    if not coalesce((health ->> 'complete')::boolean, false) then
      raise exception 'LEAGUE_BETA_CONFIGURATION_INVALID' using errcode = '22023', detail = health::text;
    end if;
    step_twelve := wizard.step_data -> '12';
    if not coalesce((step_twelve ->> 'consent')::boolean, false)
       or not coalesce((step_twelve ->> 'acknowledgeUnavailableFeatures')::boolean, false)
       or not coalesce((step_twelve ->> 'paymentsAcknowledged')::boolean, false)
       or not coalesce((step_twelve ->> 'tournamentsAcknowledged')::boolean, false) then
      raise exception 'LEAGUE_BETA_CONSENT_REQUIRED' using errcode = '22023';
    end if;
    update private.pachanga_league_private_beta_wizards wizards set
      step_data = jsonb_set(
        jsonb_set(
          jsonb_set(wizards.step_data, '{10,consent}', 'true'::jsonb, true),
          '{12,authoringMode}', to_jsonb(wizards.authoring_mode), true
        ),
        '{12,sourcePresetKey}', to_jsonb(wizards.preset_key), true
      ) || jsonb_build_object(),
      consented_at = coalesce(wizards.consented_at, clock_timestamp())
    where wizards.id = wizard.id returning * into wizard;
    update private.pachanga_league_private_beta_wizards wizards set
      step_data = jsonb_set(wizards.step_data, '{12,sourcePresetVersion}', '1'::jsonb, true)
    where wizards.id = wizard.id returning * into wizard;
    response := public.command_pachanga_league_private_beta_legacy_v1(
      operation_id, aggregate_id, expected_revision, action_name, payload, client_metadata
    );
    return response;
  end if;
  raise exception 'LEAGUE_BETA_ACTION_NOT_AVAILABLE' using errcode = '0A000';
exception when invalid_text_representation then
  raise exception 'LEAGUE_BETA_STEP_INVALID' using errcode = '22023';
end;
$$;

-- Installed V1 clients converge through the same authority. They cannot complete the old
-- ten-step consent because V2 requires explicit discipline, referee and publication review.
create or replace function public.command_pachanga_league_private_beta_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language sql
security definer
set search_path = pg_catalog
as $$
  select public.command_pachanga_league_private_beta_v2(
    operation_id, aggregate_id, expected_revision, command_action,
    command_payload, client_metadata
  );
$$;

revoke all on function public.command_pachanga_league_private_beta_v2(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_league_private_beta_v2(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;

revoke all on function public.command_pachanga_league_private_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_league_private_beta_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;

comment on function public.command_pachanga_league_private_beta_v2(
  uuid, uuid, bigint, text, jsonb, jsonb
) is 'League Wizard V2 authority. Browser sends intention only; PostgreSQL normalizes all 12 steps and freezes the RuleRevision.';
