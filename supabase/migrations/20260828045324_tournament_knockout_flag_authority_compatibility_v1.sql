set lock_timeout = '5s';
set statement_timeout = '120s';

begin;

create or replace function private.pachanga_tournament_gate_dependencies_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare r6c_authority boolean := coalesce(
  current_setting('pachangas.r6c_flag_authority', true) = 'on',
  false
);
begin
  if tg_op = 'UPDATE' and not r6c_authority
     and new.tournament_foundation_enabled and new.tournament_private_beta_enabled then
    new.tournament_knockout_foundation_enabled := old.tournament_knockout_foundation_enabled;
    new.tournament_knockout_match_generation_enabled := old.tournament_knockout_match_generation_enabled;
    new.tournament_bracket_progression_enabled := old.tournament_bracket_progression_enabled;
    new.tournament_extra_time_enabled := old.tournament_extra_time_enabled;
    new.tournament_penalty_shootout_enabled := old.tournament_penalty_shootout_enabled;
    new.tournament_third_place_enabled := old.tournament_third_place_enabled;
    new.tournament_completion_enabled := old.tournament_completion_enabled;
  end if;
  if not new.foundation_enabled then
    new.tournament_foundation_enabled := false;
  end if;
  if not new.tournament_foundation_enabled then
    new.tournament_private_beta_enabled := false;
  end if;
  if not new.tournament_private_beta_enabled then
    new.tournament_creation_enabled := false;
    new.tournament_draw_enabled := false;
  end if;
  if not new.creation_enabled then
    new.tournament_creation_enabled := false;
  end if;
  if not new.tournament_draw_enabled then
    new.tournament_automatic_draw_enabled := false;
    new.tournament_draw_manual_enabled := false;
    new.tournament_draw_hybrid_enabled := false;
    new.tournament_draw_publish_enabled := false;
  end if;
  if not new.tournament_draw_manual_enabled then
    new.tournament_draw_hybrid_enabled := false;
  end if;
  if not new.tournament_draw_publish_enabled then
    new.tournament_group_stage_enabled := false;
  end if;
  if not new.tournament_group_stage_enabled then
    new.tournament_group_scheduling_enabled := false;
  end if;
  if not new.tournament_group_scheduling_enabled then
    new.tournament_group_match_generation_enabled := false;
  end if;
  if not new.tournament_group_match_generation_enabled then
    new.tournament_group_tracking_enabled := false;
  end if;
  if not new.tournament_group_tracking_enabled then
    new.tournament_group_standings_enabled := false;
  end if;
  if not new.tournament_group_standings_enabled then
    new.tournament_qualification_enabled := false;
  end if;
  if not new.tournament_qualification_enabled then
    new.tournament_bracket_template_enabled := false;
  end if;
  if not new.tournament_bracket_template_enabled then
    new.tournament_knockout_foundation_enabled := false;
  end if;
  if not new.tournament_knockout_foundation_enabled then
    new.tournament_knockout_match_generation_enabled := false;
    new.tournament_bracket_progression_enabled := false;
    new.tournament_extra_time_enabled := false;
    new.tournament_penalty_shootout_enabled := false;
    new.tournament_third_place_enabled := false;
    new.tournament_completion_enabled := false;
  end if;
  if not new.tournament_knockout_match_generation_enabled then
    new.tournament_bracket_progression_enabled := false;
  end if;
  if not new.tournament_bracket_progression_enabled then
    new.tournament_completion_enabled := false;
  end if;
  new.tournament_match_generation_enabled :=
    new.tournament_group_match_generation_enabled
    or new.tournament_knockout_match_generation_enabled;
  new.tournament_public_discovery_enabled := false;
  new.tournament_two_leg_enabled := false;
  new.tournament_double_elimination_enabled := false;
  return new;
end;
$$;

create or replace function public.command_pachanga_tournament_knockout_platform_v1(
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
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c6c1'::uuid;
declare actor_id uuid := (select auth.uid());
declare actor_kind text;
declare normalized_action text := lower(trim(coalesce(command_action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare request_hash text;
declare replay jsonb;
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare sequence_value bigint;
declare confirmed_revision bigint;
declare confirmed_at timestamptz := clock_timestamp();
declare reason_text text;
declare snapshot jsonb;
declare previous_r6c_authority text := current_setting(
  'pachangas.r6c_flag_authority', true
);
begin
  if operation_id is null or aggregate_id <> flags_aggregate_id
     or expected_revision is null or expected_revision < 0
     or normalized_action <> 'tournament.knockout.flags.set'
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or payload - array[
       'knockoutFoundationEnabled','knockoutMatchGenerationEnabled',
       'bracketProgressionEnabled','extraTimeEnabled',
       'penaltyShootoutEnabled','thirdPlaceEnabled','completionEnabled','reason'
     ]::text[] <> '{}'::jsonb then
    raise exception 'INVALID_TOURNAMENT_KNOCKOUT_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_each(payload) item
    where item.key <> 'reason' and jsonb_typeof(item.value) <> 'boolean'
  ) then
    raise exception 'INVALID_TOURNAMENT_KNOCKOUT_FLAG' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  else
    perform private.pachanga_platform_require_v1('competitions.manage');
    perform private.pachanga_platform_require_v1('flags.write');
    actor_kind := 'authenticated';
  end if;
  reason_text := left(trim(coalesce(payload ->> 'reason', '')), 1100);
  if length(reason_text) < 3 then
    raise exception 'TOURNAMENT_PLATFORM_REASON_REQUIRED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 92603));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton for update;
  if settings.revision <> expected_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  if coalesce(
       (payload ->> 'knockoutFoundationEnabled')::boolean,
       settings.tournament_knockout_foundation_enabled
     ) and (
       not settings.tournament_foundation_enabled
       or not settings.tournament_private_beta_enabled
       or not settings.tournament_bracket_template_enabled
     ) then
    raise exception 'TOURNAMENT_KNOCKOUT_DEPENDENCY_DISABLED' using errcode = '0A000';
  end if;
  perform set_config('pachangas.r6c_flag_authority', 'on', true);
  sequence_value := nextval('private.pachanga_competition_sequence');
  update private.pachanga_competition_foundation_settings foundation_settings set
    tournament_knockout_foundation_enabled = coalesce(
      (payload ->> 'knockoutFoundationEnabled')::boolean,
      foundation_settings.tournament_knockout_foundation_enabled
    ),
    tournament_knockout_match_generation_enabled = coalesce(
      (payload ->> 'knockoutMatchGenerationEnabled')::boolean,
      foundation_settings.tournament_knockout_match_generation_enabled
    ),
    tournament_bracket_progression_enabled = coalesce(
      (payload ->> 'bracketProgressionEnabled')::boolean,
      foundation_settings.tournament_bracket_progression_enabled
    ),
    tournament_extra_time_enabled = coalesce(
      (payload ->> 'extraTimeEnabled')::boolean,
      foundation_settings.tournament_extra_time_enabled
    ),
    tournament_penalty_shootout_enabled = coalesce(
      (payload ->> 'penaltyShootoutEnabled')::boolean,
      foundation_settings.tournament_penalty_shootout_enabled
    ),
    tournament_third_place_enabled = coalesce(
      (payload ->> 'thirdPlaceEnabled')::boolean,
      foundation_settings.tournament_third_place_enabled
    ),
    tournament_completion_enabled = coalesce(
      (payload ->> 'completionEnabled')::boolean,
      foundation_settings.tournament_completion_enabled
    ),
    tournament_match_generation_enabled = foundation_settings.tournament_group_match_generation_enabled
      or coalesce(
        (payload ->> 'knockoutMatchGenerationEnabled')::boolean,
        foundation_settings.tournament_knockout_match_generation_enabled
      ),
    tournament_two_leg_enabled = false,
    tournament_double_elimination_enabled = false,
    tournament_public_discovery_enabled = false,
    revision = foundation_settings.revision + 1,
    server_sequence = sequence_value,
    updated_by = actor_id,
    updated_at = confirmed_at
  where foundation_settings.singleton
  returning foundation_settings.revision into confirmed_revision;
  perform set_config(
    'pachangas.r6c_flag_authority',
    coalesce(previous_r6c_authority, 'off'),
    true
  );
  snapshot := private.pachanga_tournament_flags_v1();
  if (payload ->> 'knockoutFoundationEnabled')::boolean is true
       and not (snapshot ->> 'knockoutFoundationEnabled')::boolean
     or (payload ->> 'knockoutMatchGenerationEnabled')::boolean is true
       and not (snapshot ->> 'knockoutMatchGenerationEnabled')::boolean
     or (payload ->> 'bracketProgressionEnabled')::boolean is true
       and not (snapshot ->> 'bracketProgressionEnabled')::boolean
     or (payload ->> 'extraTimeEnabled')::boolean is true
       and not (snapshot ->> 'extraTimeEnabled')::boolean
     or (payload ->> 'penaltyShootoutEnabled')::boolean is true
       and not (snapshot ->> 'penaltyShootoutEnabled')::boolean
     or (payload ->> 'thirdPlaceEnabled')::boolean is true
       and not (snapshot ->> 'thirdPlaceEnabled')::boolean
     or (payload ->> 'completionEnabled')::boolean is true
       and not (snapshot ->> 'completionEnabled')::boolean then
    raise exception 'TOURNAMENT_KNOCKOUT_FLAG_DEPENDENCY_DISABLED' using errcode = '0A000';
  end if;
  return private.pachanga_competition_store_command_v1(
    operation_id, actor_id, actor_kind, normalized_action,
    'tournament_knockout_flags', aggregate_id, null, null,
    confirmed_revision, sequence_value, 'tournament_knockout_flags',
    request_hash,
    private.pachanga_competition_client_metadata_v1(coalesce(client_metadata, '{}'::jsonb)),
    snapshot - array['updatedAt']::text[], snapshot, confirmed_at
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

comment on function private.pachanga_tournament_gate_dependencies_v1()
  is 'Fail-closed tournament dependency gate. R6A/R6B writers preserve R6C-owned flags unless the dedicated R6C authority is active.';

comment on function public.command_pachanga_tournament_knockout_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
)
  is 'Server-authoritative R6C flag command. Its transaction-local authority marker is restored before returning so legacy tournament commands cannot inherit R6C write authority.';

commit;
