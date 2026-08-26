\set ON_ERROR_STOP on

-- Wave 4 is exercised through the same R3 and assignment RPCs used by the
-- product. All identities, terms and receipts stay inside the temporary
-- simulation database; only a public-safe projection reaches Demo World.

create or replace function pg_temp.demo_v22_referee_command(
  target_user_id uuid,
  target_profile_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select revision into current_revision
  from public.pachanga_referee_profiles
  where id = target_profile_id;
  current_revision := coalesce(current_revision, 0);
  perform pg_temp.demo_v2_actor(target_user_id);
  return public.command_pachanga_referee_platform_v1(
    md5('demo-world-v2-2-r3:' || target_operation_key)::uuid,
    target_profile_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v22_assignment_command(
  target_user_id uuid,
  target_assignment_id uuid,
  target_operation_key text,
  target_action text,
  target_payload jsonb default '{}'::jsonb,
  target_expected_revision bigint default null
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  if target_expected_revision is null then
    select revision into current_revision
    from public.pachanga_referee_assignments
    where id = target_assignment_id;
    current_revision := coalesce(current_revision, 0);
  else
    current_revision := target_expected_revision;
  end if;
  perform pg_temp.demo_v2_actor(target_user_id);
  return public.command_pachanga_referee_assignment_beta_v1(
    md5('demo-world-v2-2-assignment:' || target_operation_key)::uuid,
    target_assignment_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v22_match_assignment_id(target_ordinal integer)
returns uuid language sql immutable as $$
  select md5('demo-world-v2-referee-assignment-' || target_ordinal)::uuid
$$;

create or replace function pg_temp.demo_v22_referee_profile_id(target_number integer)
returns uuid language sql immutable as $$
  select md5('demo-world-v2-referee-profile-' || target_number)::uuid
$$;

create or replace function pg_temp.demo_v22_referee_user_id(target_number integer)
returns uuid language sql immutable as $$
  select md5('demo-world-v2-referee-user-' || target_number)::uuid
$$;

do $demo_referees$
declare
  value integer;
  profile_id uuid;
  user_id uuid;
  response jsonb;
  profile_revision bigint;
  settings_revision bigint;
  weekday_windows jsonb;
  fee_mode text;
  fee_from integer;
begin
  perform pg_temp.demo_v2_actor('e4010000-0000-4000-8000-000000000001');
  select revision into settings_revision
  from private.pachanga_referee_foundation_settings
  where singleton;
  response := public.command_pachanga_referee_platform_admin_v1(
    md5('demo-world-v2-2-r3-flags')::uuid,
    '00000000-0000-0000-0000-00000000a3f3',
    settings_revision,
    'referee_flags.set',
    '{"foundationEnabled":true,"selfServiceEnabled":true,"publicProfilesEnabled":true,"marketplaceEnabled":true,"clubRelationshipsEnabled":true,"assignmentsEnabled":false,"reason":"Demo World V2.2 referee foundation"}'::jsonb,
    '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
  settings_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_assignment_beta_admin_v1(
    md5('demo-world-v2-2-assignment-flags')::uuid,
    settings_revision,
    'assignment_beta.flags.set',
    '{"assignmentPrivateBetaEnabled":true,"assignmentsEnabled":true,"reason":"Demo World V2.2 assignment authority"}'::jsonb,
    '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );

  select jsonb_agg(jsonb_build_object(
    'weekday', weekday,
    'startLocalTime', '00:00',
    'endLocalTime', '23:59',
    'timezone', 'Europe/Madrid',
    'publicVisible', true
  ) order by weekday)
  into weekday_windows
  from generate_series(1, 7) weekday;

  for value in 1..8 loop
    user_id := pg_temp.demo_v22_referee_user_id(value);
    profile_id := pg_temp.demo_v22_referee_profile_id(value);
    insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
    values (
      user_id,
      'demo-world-v2-referee-' || value || '@example.test',
      clock_timestamp(),
      jsonb_build_object('full_name', 'Arbitro Demo ' || value)
    );
    response := pg_temp.demo_v22_referee_command(
      user_id, profile_id, 'profile-create-' || value, 'profile.create',
      jsonb_build_object(
        'slug', 'arbitro-demo-' || value,
        'bio', 'Arbitro ficticio del mundo demostracion de Pachangas IQ.',
        'experienceSinceYear', 2014 + value,
        'experienceSummary', 'Experiencia sintetica en futbol 7 y competiciones locales.',
        'availabilityStatus', case when value in (4, 7) then 'LIMITED' else 'AVAILABLE' end,
        'reason', 'Crear perfil arbitral Demo World V2.2'
      )
    );
    response := pg_temp.demo_v22_referee_command(
      user_id, profile_id, 'modalities-' || value, 'profile.modalities.replace',
      jsonb_build_object(
        'modalities', jsonb_build_array(
          jsonb_build_object('modality', 'FOOTBALL_7', 'experienceSinceYear', 2014 + value),
          jsonb_build_object('modality', case when value % 2 = 0 then 'FUTSAL' else 'FOOTBALL_11' end, 'experienceSinceYear', 2017 + value)
        ),
        'reason', 'Modalidades Demo World V2.2'
      )
    );
    response := pg_temp.demo_v22_referee_command(
      user_id, profile_id, 'areas-' || value, 'profile.areas.replace',
      jsonb_build_object(
        'areas', jsonb_build_array(jsonb_build_object(
          'countryCode', 'ES',
          'province', 'Barcelona',
          'municipality', case when value % 3 = 0 then 'Sabadell' else 'Barcelona' end,
          'generalArea', 'Barcelona metropolitana',
          'travelRadiusKm', 60
        )),
        'reason', 'Zona Demo World V2.2'
      )
    );
    response := pg_temp.demo_v22_referee_command(
      user_id, profile_id, 'availability-' || value, 'profile.availability.replace',
      jsonb_build_object(
        'windows', weekday_windows,
        'exceptions', '[]'::jsonb,
        'reason', 'Disponibilidad recurrente Demo World V2.2'
      )
    );

    if value <= 3 then
      fee_mode := case value when 1 then 'FIXED' when 2 then 'NEGOTIABLE' else 'VOLUNTEER' end;
      fee_from := case value when 1 then 5500 when 2 then 4500 else null end;
      select revision into profile_revision from public.pachanga_referee_profiles where id = profile_id;
      perform pg_temp.demo_v2_actor(user_id);
      response := public.command_pachanga_referee_public_fee_v1(
        md5('demo-world-v2-2-public-fee-configure-' || value)::uuid,
        profile_id,
        profile_revision,
        'public_fee.configure',
        jsonb_strip_nulls(jsonb_build_object('feeMode', fee_mode, 'fromCents', fee_from, 'currency', 'EUR')),
        '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
      );
    end if;

    response := pg_temp.demo_v22_referee_command(
      user_id, profile_id, 'profile-publish-' || value, 'profile.update',
      jsonb_build_object(
        'visibility', 'public',
        'availabilityStatus', case when value in (4, 7) then 'LIMITED' else 'AVAILABLE' end,
        'availableForAssignments', true,
        'shareRecurringAvailability', true,
        'reason', 'Publicar perfil Demo World V2.2'
      )
    );
    select revision into profile_revision from public.pachanga_referee_profiles where id = profile_id;
    perform pg_temp.demo_v2_actor(user_id);
    response := public.command_pachanga_publication_consent_v1(
      md5('demo-world-v2-2-publication-consent-' || value)::uuid,
      'REFEREE_PROFILE', profile_id, profile_revision,
      '{"informationCorrect":true,"unverifiedNotCertification":true,"publicZonesAvailability":true}'::jsonb,
      '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
    );
    response := pg_temp.demo_v22_referee_command(
      user_id, profile_id, 'profile-activate-' || value, 'profile.activate',
      '{"reason":"Activar perfil Demo World V2.2"}'::jsonb
    );
    response := pg_temp.demo_v22_referee_command(
      user_id, profile_id, 'marketplace-list-' || value, 'marketplace.list',
      '{"reason":"Listar perfil Demo World V2.2"}'::jsonb
    );

    if value <= 3 then
      select revision into profile_revision from public.pachanga_referee_profiles where id = profile_id;
      perform pg_temp.demo_v2_actor(user_id);
      response := public.command_pachanga_referee_public_fee_v1(
        md5('demo-world-v2-2-public-fee-publish-' || value)::uuid,
        profile_id,
        profile_revision,
        'public_fee.publish',
        '{"informationCorrect":true,"outOfPlatformPaymentAcknowledged":true}'::jsonb,
        '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
      );
    end if;
  end loop;
end;
$demo_referees$;

do $demo_assignments$
declare
  match_row record;
  assignment_id uuid;
  replacement_id uuid := md5('demo-world-v2-referee-assignment-replacement-4')::uuid;
  conflict_id uuid := md5('demo-world-v2-referee-assignment-conflict-14')::uuid;
  referee_number integer;
  source_id text;
  match_one_start timestamptz;
  match_one_end timestamptz;
  original_fourteen_start timestamptz;
  original_fourteen_end timestamptz;
  conflict_rejected boolean := false;
begin
  for match_row in
    select
      contexts.id,
      contexts.canonical_match_id,
      contexts.scheduled_start,
      contexts.scheduled_end,
      bindings.source_id,
      row_number() over(order by rounds.round_number, items.pairing_key)::integer as ordinal
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
    join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
    join public.pachanga_canonical_match_bindings bindings
      on bindings.canonical_match_id = contexts.canonical_match_id
      and bindings.source_kind = 'competition_generated'
      and bindings.binding_status = 'active'
    where contexts.competition_id = 'e4040000-0000-4000-8000-000000000001'
    order by rounds.round_number, items.pairing_key
  loop
    if match_row.ordinal = 1 then
      match_one_start := match_row.scheduled_start;
      match_one_end := match_row.scheduled_end;
    end if;
    if match_row.ordinal = 14 then
      original_fourteen_start := match_row.scheduled_start;
      original_fourteen_end := match_row.scheduled_end;
    end if;
    if match_row.ordinal <= 13 then
      referee_number := case
        when match_row.ordinal = 4 then 4
        else 1 + ((match_row.ordinal - 1) % 8)
      end;
      assignment_id := pg_temp.demo_v22_match_assignment_id(match_row.ordinal);
      perform pg_temp.demo_v22_assignment_command(
        'e4010000-0000-4000-8000-000000000002',
        assignment_id,
        'propose-' || match_row.ordinal,
        'assignment.propose',
        jsonb_build_object(
          'refereeProfileId', pg_temp.demo_v22_referee_profile_id(referee_number),
          'sourceKind', 'competition_generated',
          'sourceId', match_row.source_id,
          'requesterKind', 'COMPETITION',
          'requesterId', 'e4040000-0000-4000-8000-000000000001',
          'assignmentRole', 'MAIN_REFEREE',
          'responseDeadline', clock_timestamp() + interval '10 days',
          'feeMode', case when referee_number = 3 then 'VOLUNTEER'
                          when referee_number = 2 then 'NEGOTIABLE'
                          else 'FIXED' end,
          'proposedFeeCents', case when referee_number in (2, 3) then null else 5500 + referee_number * 100 end,
          'currency', 'EUR',
          'privateTermsNote', 'Terminos privados Demo World V2.2 match ' || match_row.ordinal
        )
      );
      if match_row.ordinal = 13 then
        perform pg_temp.demo_v22_assignment_command(
          pg_temp.demo_v22_referee_user_id(referee_number),
          assignment_id,
          'decline-' || match_row.ordinal,
          'assignment.decline',
          '{"reason":"El arbitro no puede cubrir este encuentro"}'::jsonb
        );
      else
        perform pg_temp.demo_v22_assignment_command(
          pg_temp.demo_v22_referee_user_id(referee_number),
          assignment_id,
          'accept-' || match_row.ordinal,
          'assignment.accept'
        );
        perform pg_temp.demo_v22_assignment_command(
          'e4010000-0000-4000-8000-000000000002',
          assignment_id,
          'confirm-' || match_row.ordinal,
          'assignment.confirm'
        );
      end if;
    end if;
  end loop;

  assignment_id := pg_temp.demo_v22_match_assignment_id(4);
  perform pg_temp.demo_v22_assignment_command(
    'e4010000-0000-4000-8000-000000000002',
    assignment_id,
    'replace-4',
    'assignment.replace',
    jsonb_build_object(
      'newRefereeProfileId', pg_temp.demo_v22_referee_profile_id(8),
      'newAssignmentId', replacement_id,
      'responseDeadline', clock_timestamp() + interval '10 days',
      'feeMode', 'NEGOTIABLE',
      'proposedFeeCents', 6200,
      'currency', 'EUR',
      'privateTermsNote', 'Sustitucion privada Demo World V2.2'
    )
  );
  perform pg_temp.demo_v22_assignment_command(
    pg_temp.demo_v22_referee_user_id(8), replacement_id,
    'replacement-accept-4', 'assignment.accept'
  );
  perform pg_temp.demo_v22_assignment_command(
    'e4010000-0000-4000-8000-000000000002', replacement_id,
    'replacement-confirm-4', 'assignment.confirm'
  );

  select contexts.id, bindings.source_id
  into match_row
  from public.pachanga_competition_match_contexts contexts
  join public.pachanga_competition_schedule_items items on items.id = contexts.schedule_item_id
  join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
  join public.pachanga_canonical_match_bindings bindings
    on bindings.canonical_match_id = contexts.canonical_match_id
    and bindings.source_kind = 'competition_generated'
    and bindings.binding_status = 'active'
  where contexts.competition_id = 'e4040000-0000-4000-8000-000000000001'
  order by rounds.round_number, items.pairing_key
  offset 13 limit 1;
  -- Synthetic fixture arrangement only: R4D correctly rejects the shared
  -- physical pitch before the narrower referee guard can run. The product
  -- action below remains the real assignment RPC, and the canonical context
  -- is restored immediately after the assertion.
  update public.pachanga_competition_match_contexts contexts set
    scheduled_start = match_one_start,
    scheduled_end = match_one_end,
    revision = contexts.revision + 1,
    updated_at = clock_timestamp()
  where contexts.id = match_row.id;
  perform pg_temp.demo_v22_assignment_command(
    'e4010000-0000-4000-8000-000000000002', conflict_id,
    'conflict-propose-14', 'assignment.propose',
    jsonb_build_object(
      'refereeProfileId', pg_temp.demo_v22_referee_profile_id(1),
      'sourceKind', 'competition_generated',
      'sourceId', match_row.source_id,
      'requesterKind', 'COMPETITION',
      'requesterId', 'e4040000-0000-4000-8000-000000000001',
      'responseDeadline', clock_timestamp() + interval '10 days',
      'feeMode', 'FREE'
    )
  );
  begin
    perform pg_temp.demo_v22_assignment_command(
      pg_temp.demo_v22_referee_user_id(1), conflict_id,
      'conflict-accept-14', 'assignment.accept'
    );
  exception when others then
    if sqlerrm not like '%REFEREE_ASSIGNMENT_TIME_CONFLICT%' then raise; end if;
    conflict_rejected := true;
  end;
  if not conflict_rejected then raise exception 'DEMO_WORLD_V2_2_OVERLAP_WAS_NOT_REJECTED'; end if;
  perform pg_temp.demo_v22_assignment_command(
    'e4010000-0000-4000-8000-000000000002', conflict_id,
    'conflict-cancel-14', 'assignment.cancel',
    '{"reasonCode":"demo_conflict_rejected","reasonText":"El arbitro ya estaba confirmado en otro partido solapado."}'::jsonb
  );
  update public.pachanga_competition_match_contexts contexts set
    scheduled_start = original_fourteen_start,
    scheduled_end = original_fourteen_end,
    revision = contexts.revision + 1,
    updated_at = clock_timestamp()
  where contexts.id = match_row.id;
  assignment_id := pg_temp.demo_v22_match_assignment_id(14);
  perform pg_temp.demo_v22_assignment_command(
    'e4010000-0000-4000-8000-000000000002', assignment_id,
    'propose-14-after-conflict', 'assignment.propose',
    jsonb_build_object(
      'refereeProfileId', pg_temp.demo_v22_referee_profile_id(5),
      'sourceKind', 'competition_generated',
      'sourceId', match_row.source_id,
      'requesterKind', 'COMPETITION',
      'requesterId', 'e4040000-0000-4000-8000-000000000001',
      'responseDeadline', clock_timestamp() + interval '10 days',
      'feeMode', 'FIXED',
      'proposedFeeCents', 6000,
      'currency', 'EUR',
      'privateTermsNote', 'Propuesta privada posterior al conflicto sintetico'
    )
  );
  perform pg_temp.demo_v22_assignment_command(
    pg_temp.demo_v22_referee_user_id(5), assignment_id,
    'accept-14-after-conflict', 'assignment.accept'
  );
  perform pg_temp.demo_v22_assignment_command(
    'e4010000-0000-4000-8000-000000000002', assignment_id,
    'confirm-14-after-conflict', 'assignment.confirm'
  );
end;
$demo_assignments$;

create or replace function pg_temp.demo_v22_referee_reconfirm(target_context_id uuid)
returns void language plpgsql as $$
declare assignment public.pachanga_referee_assignments%rowtype;
declare referee_user_id uuid;
begin
  select assignments.* into assignment
  from public.pachanga_referee_assignments assignments
  where assignments.competition_match_context_id = target_context_id
    and assignments.status = 'confirmed'
    and assignments.schedule_state = 'RECONFIRMATION_REQUIRED'
  order by assignments.server_sequence desc, assignments.id desc
  limit 1;
  if not found then raise exception 'DEMO_WORLD_V2_2_RECONFIRMATION_NOT_REQUIRED'; end if;
  select profiles.user_id into referee_user_id
  from public.pachanga_referee_profiles profiles
  where profiles.id = assignment.referee_profile_id;
  perform pg_temp.demo_v22_assignment_command(
    referee_user_id,
    assignment.id,
    'reconfirm-' || target_context_id,
    'assignment.reconfirm'
  );
end;
$$;

create or replace function pg_temp.demo_v22_reconcile_assignments()
returns void language plpgsql as $$
declare assignment public.pachanga_referee_assignments%rowtype;
declare profile_id uuid;
declare stats_before text;
declare stats_revision bigint;
declare stats_after text;
begin
  perform pg_temp.demo_v2_actor('e4010000-0000-4000-8000-000000000001');
  for assignment in
    select assignments.*
    from public.pachanga_referee_assignments assignments
    where assignments.competition_id = 'e4040000-0000-4000-8000-000000000001'
      and assignments.status = 'confirmed'
    order by assignments.server_sequence, assignments.id
  loop
    perform public.reconcile_pachanga_referee_assignment_v1(
      md5('demo-world-v2-2-reconcile-' || assignment.id)::uuid,
      assignment.id,
      assignment.revision,
      '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
    );
  end loop;

  for profile_id in
    select profiles.id as referee_profile_id
    from public.pachanga_referee_profiles profiles
    where profiles.id in (select pg_temp.demo_v22_referee_profile_id(value) from generate_series(1, 8) value)
    order by profiles.id
  loop
    select checksum, revision into stats_before, stats_revision
    from public.pachanga_referee_statistics_snapshots
    where referee_profile_id = profile_id;
    perform pg_temp.demo_v2_actor('e4010000-0000-4000-8000-000000000001');
    perform public.command_pachanga_referee_platform_admin_v1(
      md5('demo-world-v2-2-stats-rebuild-' || profile_id)::uuid,
      profile_id,
      stats_revision,
      'stats.rebuild',
      '{"reason":"Verificar convergencia incremental y full rebuild Demo World V2.2"}'::jsonb,
      '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
    );
    select checksum into stats_after
    from public.pachanga_referee_statistics_snapshots
    where referee_profile_id = profile_id;
    if stats_before is distinct from stats_after then
      raise exception 'DEMO_WORLD_V2_2_REFEREE_STATS_DIVERGED:%', profile_id;
    end if;
  end loop;
end;
$$;
