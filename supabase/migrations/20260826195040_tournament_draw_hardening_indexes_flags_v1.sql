-- Pachangas IQ R6A: platform activation authority, dependency gates and hardening.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_tournament_gate_dependencies_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
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
  -- These capabilities belong to R6B or later and cannot be activated in R6A.
  new.tournament_public_discovery_enabled := false;
  new.tournament_match_generation_enabled := false;
  new.tournament_bracket_progression_enabled := false;
  return new;
end;
$$;

revoke all on function private.pachanga_tournament_gate_dependencies_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_tournament_dependencies_v1
  on private.pachanga_competition_foundation_settings;
create trigger guard_pachanga_tournament_dependencies_v1
before insert or update on private.pachanga_competition_foundation_settings
for each row execute function private.pachanga_tournament_gate_dependencies_v1();

create or replace function public.command_pachanga_tournament_platform_v1(
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
declare flags_aggregate_id constant uuid := '00000000-0000-0000-0000-00000000c6a1'::uuid;
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
declare reason_text text;
declare settings private.pachanga_competition_foundation_settings%rowtype;
declare next_foundation boolean;
declare next_beta boolean;
declare next_creation boolean;
declare next_draw boolean;
declare next_automatic boolean;
declare next_manual boolean;
declare next_hybrid boolean;
declare next_publish boolean;
declare normalized_kind text;
declare organizer_id uuid;
declare organizer_state public.pachanga_competition_organizer_states%rowtype;
declare state_was_missing boolean := false;
declare selected_bundle_id uuid;
declare capability_name text;
declare team_cap integer;
declare valid_from timestamptz;
declare expires_at timestamptz;
declare snapshot jsonb;
declare event_payload jsonb;
declare organizer_group_id uuid;
begin
  if operation_id is null or aggregate_id is null
     or expected_revision is null or expected_revision < 0
     or normalized_action not in (
       'tournament.flags.set','tournament.kill_switch',
       'tournament.beta_bundle.grant','tournament.beta_bundle.revoke'
     )
     or jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_TOURNAMENT_PLATFORM_COMMAND' using errcode = '22023';
  end if;
  if normalized_action in ('tournament.flags.set','tournament.kill_switch') then
    if aggregate_id <> flags_aggregate_id
       or payload - array[
         'foundationEnabled','privateBetaEnabled','creationEnabled','drawEnabled',
         'automaticEnabled','manualEnabled','hybridEnabled','publishEnabled','reason'
       ]::text[] <> '{}'::jsonb then
      raise exception 'INVALID_TOURNAMENT_FLAGS_PAYLOAD' using errcode = '22023';
    end if;
  elsif payload - array[
    'organizerKind','bundleId','maxTeams','capacityOverride',
    'validFrom','expiresAt','reason'
  ]::text[] <> '{}'::jsonb then
    raise exception 'INVALID_TOURNAMENT_BUNDLE_PAYLOAD' using errcode = '22023';
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
  reason_text := left(trim(coalesce(payload ->> 'reason', '')), 1100);
  if length(reason_text) < 3 then
    raise exception 'TOURNAMENT_PLATFORM_REASON_REQUIRED' using errcode = '22023';
  end if;
  request_hash := private.pachanga_competition_request_hash_v1(
    normalized_action, aggregate_id, expected_revision, payload
  );
  sanitized_metadata := private.pachanga_competition_client_metadata_v1(
    coalesce(client_metadata, '{}'::jsonb)
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91601));
  replay := private.pachanga_competition_replay_v1(
    operation_id, actor_id, actor_kind, normalized_action, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  sequence_value := nextval('private.pachanga_competition_sequence');

  if normalized_action in ('tournament.flags.set','tournament.kill_switch') then
    select * into settings
    from private.pachanga_competition_foundation_settings current_settings
    where current_settings.singleton for update;
    if settings.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    if normalized_action = 'tournament.kill_switch' then
      next_foundation := false;
      next_beta := false;
      next_creation := false;
      next_draw := false;
      next_automatic := false;
      next_manual := false;
      next_hybrid := false;
      next_publish := false;
    else
      if exists (
        select 1 from jsonb_each(payload) item
        where item.key <> 'reason' and jsonb_typeof(item.value) <> 'boolean'
      ) then raise exception 'INVALID_TOURNAMENT_FLAG' using errcode = '22023'; end if;
      next_foundation := coalesce((payload ->> 'foundationEnabled')::boolean, settings.tournament_foundation_enabled);
      next_beta := coalesce((payload ->> 'privateBetaEnabled')::boolean, settings.tournament_private_beta_enabled);
      next_creation := coalesce((payload ->> 'creationEnabled')::boolean, settings.tournament_creation_enabled);
      next_draw := coalesce((payload ->> 'drawEnabled')::boolean, settings.tournament_draw_enabled);
      next_automatic := coalesce((payload ->> 'automaticEnabled')::boolean, settings.tournament_automatic_draw_enabled);
      next_manual := coalesce((payload ->> 'manualEnabled')::boolean, settings.tournament_draw_manual_enabled);
      next_hybrid := coalesce((payload ->> 'hybridEnabled')::boolean, settings.tournament_draw_hybrid_enabled);
      next_publish := coalesce((payload ->> 'publishEnabled')::boolean, settings.tournament_draw_publish_enabled);
      if next_foundation and not settings.foundation_enabled then
        raise exception 'TOURNAMENT_FOUNDATION_DEPENDENCY_DISABLED' using errcode = '0A000';
      end if;
      if next_creation and not settings.creation_enabled then
        raise exception 'TOURNAMENT_CREATION_DEPENDENCY_DISABLED' using errcode = '0A000';
      end if;
      if next_beta and not next_foundation then
        raise exception 'TOURNAMENT_BETA_DEPENDENCY_DISABLED' using errcode = '0A000';
      end if;
      if next_creation and not next_beta then
        raise exception 'TOURNAMENT_CREATION_REQUIRES_BETA' using errcode = '0A000';
      end if;
      if next_draw and not next_beta then
        raise exception 'TOURNAMENT_DRAW_REQUIRES_BETA' using errcode = '0A000';
      end if;
      if (next_automatic or next_manual or next_publish) and not next_draw then
        raise exception 'TOURNAMENT_DRAW_CAPABILITY_DEPENDENCY_DISABLED' using errcode = '0A000';
      end if;
      if next_hybrid and (not next_draw or not next_manual) then
        raise exception 'TOURNAMENT_HYBRID_DEPENDENCY_DISABLED' using errcode = '0A000';
      end if;
    end if;
    update private.pachanga_competition_foundation_settings foundation_settings set
      tournament_foundation_enabled = next_foundation,
      tournament_private_beta_enabled = next_beta,
      tournament_creation_enabled = next_creation,
      tournament_draw_enabled = next_draw,
      tournament_automatic_draw_enabled = next_automatic,
      tournament_draw_manual_enabled = next_manual,
      tournament_draw_hybrid_enabled = next_hybrid,
      tournament_draw_publish_enabled = next_publish,
      tournament_public_discovery_enabled = false,
      tournament_match_generation_enabled = false,
      tournament_bracket_progression_enabled = false,
      revision = foundation_settings.revision + 1,
      server_sequence = sequence_value,
      updated_by = actor_id,
      updated_at = confirmed_at
    where foundation_settings.singleton
    returning foundation_settings.revision into confirmed_revision;
    snapshot := private.pachanga_tournament_flags_v1();
    event_payload := snapshot - array['updatedAt']::text[];
  else
    normalized_kind := upper(trim(coalesce(payload ->> 'organizerKind', '')));
    organizer_id := aggregate_id;
    if normalized_kind = 'TEAM' then
      perform 1 from public.pachanga_groups groups where groups.id = organizer_id for update;
      organizer_group_id := organizer_id;
    elsif normalized_kind = 'CLUB' then
      perform 1 from public.pachanga_clubs clubs where clubs.id = organizer_id for update;
    else
      raise exception 'INVALID_ORGANIZER_KIND' using errcode = '22023';
    end if;
    if not found then raise exception 'ORGANIZER_NOT_FOUND' using errcode = 'P0002'; end if;
    select * into organizer_state
    from public.pachanga_competition_organizer_states states
    where states.organizer_kind = normalized_kind and (
      (normalized_kind = 'TEAM' and states.organizer_group_id = organizer_id)
      or (normalized_kind = 'CLUB' and states.organizer_club_id = organizer_id)
    ) for update;
    if not found then
      state_was_missing := true;
      if expected_revision <> 0 then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
      insert into public.pachanga_competition_organizer_states(
        organizer_kind, organizer_group_id, organizer_club_id,
        revision, server_sequence, created_at, updated_at
      ) values (
        normalized_kind,
        case when normalized_kind = 'TEAM' then organizer_id else null end,
        case when normalized_kind = 'CLUB' then organizer_id else null end,
        1, sequence_value, confirmed_at, confirmed_at
      ) returning * into organizer_state;
      confirmed_revision := organizer_state.revision;
    elsif organizer_state.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;

    if normalized_action = 'tournament.beta_bundle.grant' then
      select * into settings
      from private.pachanga_competition_foundation_settings current_settings
      where current_settings.singleton;
      if not settings.tournament_foundation_enabled
         or not settings.tournament_private_beta_enabled then
        raise exception 'TOURNAMENT_PRIVATE_BETA_DISABLED' using errcode = '42501';
      end if;
      begin
        team_cap := coalesce(nullif(payload ->> 'maxTeams', '')::integer, settings.tournament_standard_team_cap);
        valid_from := coalesce(nullif(payload ->> 'validFrom', '')::timestamptz, statement_timestamp());
        expires_at := nullif(payload ->> 'expiresAt', '')::timestamptz;
      exception when others then
        raise exception 'TOURNAMENT_BETA_GRANT_INVALID' using errcode = '22023';
      end;
      if team_cap < 4 or team_cap > settings.tournament_override_team_cap
         or (team_cap > settings.tournament_standard_team_cap
             and not coalesce((payload ->> 'capacityOverride')::boolean, false)) then
        raise exception 'TOURNAMENT_CAPACITY_LIMIT' using errcode = '22023';
      end if;
      if expires_at is not null and expires_at <= greatest(valid_from, confirmed_at) then
        raise exception 'TOURNAMENT_BETA_GRANT_EXPIRY_INVALID' using errcode = '22023';
      end if;
      if exists (
        select 1 from public.pachanga_competition_entitlement_grants grants
        where grants.organizer_kind = normalized_kind
          and ((normalized_kind = 'TEAM' and grants.organizer_group_id = organizer_id)
            or (normalized_kind = 'CLUB' and grants.organizer_club_id = organizer_id))
          and grants.capability = any(private.pachanga_tournament_capabilities_v1())
          and grants.status = 'active'
          and grants.valid_from <= confirmed_at
          and (grants.expires_at is null or grants.expires_at > confirmed_at)
      ) then raise exception 'TOURNAMENT_BETA_ENTITLEMENT_CONFLICT' using errcode = 'PT409'; end if;
      selected_bundle_id := gen_random_uuid();
      foreach capability_name in array private.pachanga_tournament_capabilities_v1() loop
        insert into public.pachanga_competition_entitlement_grants(
          organizer_kind, organizer_group_id, organizer_club_id,
          capability, grant_source, status, valid_from, expires_at,
          reason, revision, server_sequence, granted_by,
          program_key, bundle_id, beta_team_cap, created_at, updated_at
        ) values (
          normalized_kind,
          case when normalized_kind = 'TEAM' then organizer_id else null end,
          case when normalized_kind = 'CLUB' then organizer_id else null end,
          capability_name, 'platform_grant', 'active', valid_from, expires_at,
          left('TOURNAMENT_PRIVATE_BETA_V1: ' || reason_text, 1200),
          1, sequence_value, actor_id,
          'TOURNAMENT_PRIVATE_BETA_V1', selected_bundle_id, team_cap,
          confirmed_at, confirmed_at
        );
      end loop;
      event_payload := jsonb_build_object(
        'bundleId', selected_bundle_id, 'teamCap', team_cap,
        'expiresAt', expires_at,
        'capabilityCount', cardinality(private.pachanga_tournament_capabilities_v1())
      );
    else
      selected_bundle_id := nullif(payload ->> 'bundleId', '')::uuid;
      if selected_bundle_id is null then
        raise exception 'TOURNAMENT_BETA_BUNDLE_REQUIRED' using errcode = '22023';
      end if;
      if not exists (
        select 1 from public.pachanga_competition_entitlement_grants grants
        where grants.bundle_id = selected_bundle_id
          and grants.program_key = 'TOURNAMENT_PRIVATE_BETA_V1'
          and grants.organizer_kind = normalized_kind
          and ((normalized_kind = 'TEAM' and grants.organizer_group_id = organizer_id)
            or (normalized_kind = 'CLUB' and grants.organizer_club_id = organizer_id))
          and grants.status = 'active'
      ) then raise exception 'TOURNAMENT_BETA_BUNDLE_NOT_ACTIVE' using errcode = 'P0002'; end if;
      update public.pachanga_competition_entitlement_grants grants set
        status = 'revoked', revision = grants.revision + 1,
        server_sequence = sequence_value, revoked_by = actor_id,
        revoked_at = confirmed_at, updated_at = confirmed_at
      where grants.bundle_id = selected_bundle_id
        and grants.program_key = 'TOURNAMENT_PRIVATE_BETA_V1'
        and grants.status = 'active';
      event_payload := jsonb_build_object('bundleId', selected_bundle_id, 'status', 'revoked');
    end if;
    if not state_was_missing then
      update public.pachanga_competition_organizer_states states set
        revision = states.revision + 1,
        server_sequence = sequence_value,
        updated_at = confirmed_at
      where states.id = organizer_state.id
      returning states.revision into confirmed_revision;
    end if;
    snapshot := private.pachanga_tournament_bundle_snapshot_v1(normalized_kind, organizer_id);
  end if;

  return private.pachanga_competition_store_command_v1(
    operation_id, actor_id, actor_kind, normalized_action,
    case when normalized_action like 'tournament.%bundle.%' then 'tournament_beta_bundle' else 'tournament_flags' end,
    aggregate_id, null, organizer_group_id,
    confirmed_revision, sequence_value, left(normalized_action, 120), request_hash,
    sanitized_metadata, coalesce(event_payload, '{}'::jsonb), snapshot, confirmed_at
  );
exception
  when serialization_failure or deadlock_detected or lock_not_available then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
end;
$$;

revoke all on function public.command_pachanga_tournament_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_tournament_platform_v1(
  uuid,uuid,bigint,text,jsonb,jsonb
) to authenticated, service_role;

create or replace function private.pachanga_tournament_reject_match_generation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if exists (
    select 1 from public.pachanga_competitions competitions
    where competitions.id = new.competition_id
      and competitions.product_key = 'TOURNAMENT_PRIVATE_BETA_V1'
  ) then
    raise exception 'TOURNAMENT_MATCH_GENERATION_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_tournament_reject_match_generation_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_tournament_match_generation_v1
  on public.pachanga_competition_match_contexts;
create trigger guard_pachanga_tournament_match_generation_v1
before insert or update of competition_id on public.pachanga_competition_match_contexts
for each row execute function private.pachanga_tournament_reject_match_generation_v1();

create index if not exists pachanga_tournament_freeze_entry_ids_gin_idx
  on public.pachanga_competition_participant_freezes using gin(entry_ids);
create index if not exists pachanga_tournament_pot_entry_ids_gin_idx
  on public.pachanga_competition_draw_pots using gin(entry_ids)
  where status = 'active';
create index if not exists pachanga_tournament_plan_current_revision_idx
  on public.pachanga_competition_draw_plans(current_revision_id)
  where current_revision_id is not null;
create index if not exists pachanga_tournament_plan_status_idx
  on public.pachanga_competition_draw_plans(status, server_sequence desc, id desc);
create index if not exists pachanga_tournament_revision_status_idx
  on public.pachanga_competition_draw_revisions(validation_status, server_sequence desc, id desc);
create index if not exists pachanga_tournament_placement_entry_idx
  on public.pachanga_competition_draw_placements(entry_id, server_sequence desc, id desc);
create index if not exists pachanga_tournament_bye_beneficiary_idx
  on public.pachanga_competition_draw_byes(beneficiary_entry_id, server_sequence desc, id desc)
  where beneficiary_entry_id is not null;

-- Cover every R6A foreign key independently. Composite product-query indexes
-- above remain useful, but a referenced column must lead an index for bounded
-- referential checks and parent lifecycle operations.
create index if not exists pachanga_tournament_freeze_edition_fk_idx
  on public.pachanga_competition_participant_freezes(edition_id);
create index if not exists pachanga_tournament_freeze_frozen_by_fk_idx
  on public.pachanga_competition_participant_freezes(frozen_by);
create index if not exists pachanga_tournament_freeze_rule_revision_fk_idx
  on public.pachanga_competition_participant_freezes(rule_revision_id);
create index if not exists pachanga_tournament_freeze_stage_fk_idx
  on public.pachanga_competition_participant_freezes(stage_id);

create index if not exists pachanga_tournament_plan_created_by_fk_idx
  on public.pachanga_competition_draw_plans(created_by);
create index if not exists pachanga_tournament_plan_edition_fk_idx
  on public.pachanga_competition_draw_plans(edition_id);
create index if not exists pachanga_tournament_plan_freeze_fk_idx
  on public.pachanga_competition_draw_plans(participant_freeze_id);
create index if not exists pachanga_tournament_plan_rule_revision_fk_idx
  on public.pachanga_competition_draw_plans(rule_revision_id);
create index if not exists pachanga_tournament_plan_stage_fk_idx
  on public.pachanga_competition_draw_plans(stage_id);

create index if not exists pachanga_tournament_revision_generated_by_fk_idx
  on public.pachanga_competition_draw_revisions(generated_by);
create index if not exists pachanga_tournament_revision_supersedes_fk_idx
  on public.pachanga_competition_draw_revisions(supersedes_revision_id);
create index if not exists pachanga_tournament_pot_created_by_fk_idx
  on public.pachanga_competition_draw_pots(created_by);
create index if not exists pachanga_tournament_constraint_created_by_fk_idx
  on public.pachanga_competition_draw_constraints(created_by);

create index if not exists pachanga_tournament_lock_created_by_fk_idx
  on public.pachanga_competition_draw_manual_locks(created_by);
create index if not exists pachanga_tournament_lock_entry_fk_idx
  on public.pachanga_competition_draw_manual_locks(entry_id);
create index if not exists pachanga_tournament_lock_related_entry_fk_idx
  on public.pachanga_competition_draw_manual_locks(related_entry_id);
create index if not exists pachanga_tournament_lock_released_by_fk_idx
  on public.pachanga_competition_draw_manual_locks(released_by);
create index if not exists pachanga_tournament_placement_manual_lock_fk_idx
  on public.pachanga_competition_draw_placements(manual_lock_id);

alter table private.pachanga_competition_foundation_settings
  drop constraint if exists pachanga_comp_foundation_tournament_phase1_off_check,
  add constraint pachanga_comp_foundation_tournament_phase1_off_check check (
    not tournament_public_discovery_enabled
    and not tournament_match_generation_enabled
    and not tournament_bracket_progression_enabled
  );

comment on function public.command_pachanga_tournament_platform_v1(uuid,uuid,bigint,text,jsonb,jsonb) is
  'Only versioned authority for R6A flags and invite-only entitlement bundles. Direct flag UPDATE is not an activation procedure.';
comment on constraint pachanga_comp_foundation_tournament_phase1_off_check
  on private.pachanga_competition_foundation_settings is
  'R6A boundary: public discovery, Tournament match generation and bracket progression remain OFF.';
