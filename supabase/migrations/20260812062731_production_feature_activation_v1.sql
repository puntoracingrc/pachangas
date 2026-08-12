-- Production Feature Activation V1.
-- Adds non-retroactive activation frontiers and exposes canonical readiness.

alter table private.pachanga_conduct_settings
  add column if not exists attendance_effective_from timestamptz,
  add column if not exists conduct_effective_from timestamptz;

-- A pre-existing enabled installation starts at this deployment boundary. The
-- production and staging release path keeps both flags disabled until the
-- audited platform RPC activates them.
update private.pachanga_conduct_settings
set
  attendance_effective_from = case
    when attendance_closure_enabled then coalesce(attendance_effective_from, clock_timestamp())
    else attendance_effective_from
  end,
  conduct_effective_from = case
    when conduct_reports_enabled then coalesce(conduct_effective_from, clock_timestamp())
    else conduct_effective_from
  end
where singleton;

create or replace function private.pachanga_conduct_context_occurred_at_v1(
  reporter_group_id uuid,
  target_group_id uuid,
  context_kind text,
  context_id text
)
returns timestamptz
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  context_uuid uuid;
  occurred_at timestamptz;
  source_group_id uuid;
  source_match_id text;
begin
  if context_kind = 'match' then
    select nullif(matches.value ->> 'date', '')::timestamptz
    into occurred_at
    from public.pachanga_groups groups
    cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'matches', '[]'::jsonb)) matches(value)
    where groups.id = target_group_id and matches.value ->> 'id' = context_id
    limit 1;
    return occurred_at;
  end if;

  begin
    context_uuid := context_id::uuid;
  exception when others then
    return null;
  end;

  if context_kind = 'challenge' then
    select matches.scheduled_at into occurred_at
    from public.pachanga_external_matches matches
    where matches.challenge_id = context_uuid;
    return occurred_at;
  elsif context_kind = 'open_match' then
    select matches.date into occurred_at
    from public.pachanga_open_matches matches
    where matches.id = context_uuid;
    return occurred_at;
  elsif context_kind = 'guest_participation' then
    select access.group_id, access.match_id
    into source_group_id, source_match_id
    from public.pachanga_match_guest_access access
    where access.id = context_uuid;

    select nullif(matches.value ->> 'date', '')::timestamptz
    into occurred_at
    from public.pachanga_groups groups
    cross join lateral jsonb_array_elements(coalesce(groups.payload -> 'matches', '[]'::jsonb)) matches(value)
    where groups.id = source_group_id and matches.value ->> 'id' = source_match_id
    limit 1;
    return occurred_at;
  end if;

  return null;
exception when invalid_datetime_format then
  return null;
end;
$$;

revoke all on function private.pachanga_conduct_context_occurred_at_v1(uuid, uuid, text, text)
  from public, anon, authenticated;

create or replace function private.pachanga_enforce_attendance_activation_frontier_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  settings private.pachanga_conduct_settings%rowtype;
begin
  select * into settings
  from private.pachanga_conduct_settings
  where singleton;

  if settings.attendance_closure_enabled then
    if settings.attendance_effective_from is null then
      raise exception 'Attendance activation frontier is missing';
    end if;
    if new.match_occurred_at < settings.attendance_effective_from then
      raise exception 'Match predates Attendance activation';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_enforce_attendance_activation_frontier_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_attendance_activation_frontier_v1
  on private.pachanga_attendance_closures;
create trigger pachanga_attendance_activation_frontier_v1
before insert on private.pachanga_attendance_closures
for each row execute function private.pachanga_enforce_attendance_activation_frontier_v1();

create or replace function private.pachanga_enforce_conduct_activation_frontier_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  settings private.pachanga_conduct_settings%rowtype;
  occurred_at timestamptz;
begin
  select * into settings
  from private.pachanga_conduct_settings
  where singleton;

  if settings.conduct_reports_enabled then
    if settings.conduct_effective_from is null then
      raise exception 'Conduct activation frontier is missing';
    end if;
    occurred_at := private.pachanga_conduct_context_occurred_at_v1(
      new.reporter_group_id,
      new.target_group_id,
      new.context_kind,
      new.context_id
    );
    if occurred_at is null then
      raise exception 'Canonical conduct context occurrence time required';
    end if;
    if occurred_at < settings.conduct_effective_from then
      raise exception 'Sporting context predates Conduct activation';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_enforce_conduct_activation_frontier_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_conduct_activation_frontier_v1
  on private.pachanga_conduct_reports;
create trigger pachanga_conduct_activation_frontier_v1
before insert on private.pachanga_conduct_reports
for each row execute function private.pachanga_enforce_conduct_activation_frontier_v1();

-- Conduct Triage V1.1 narrowed the original open-case index to report intake.
-- Attendance keeps independent open cases and therefore needs matching partial
-- indexes for each server-generated source type.
create unique index if not exists pachanga_moderation_cases_open_attendance_reliability_idx
  on private.pachanga_moderation_cases(target_profile_id, source_type, category)
  where source_type = 'attendance_reliability'
    and state not in ('dismissed', 'corrected', 'closed');

create unique index if not exists pachanga_moderation_cases_open_attendance_dispute_idx
  on private.pachanga_moderation_cases(target_profile_id, source_type, category)
  where source_type = 'attendance_dispute'
    and state not in ('dismissed', 'corrected', 'closed');

create or replace function private.pachanga_evaluate_attendance_reliability_v1(
  target_user_id uuid,
  target_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  evaluated_user_id uuid := target_user_id;
  settings private.pachanga_conduct_settings%rowtype;
  target_profile public.pachanga_player_profiles%rowtype;
  no_shows_90 integer;
  no_shows_180 integer;
  late_90 integer;
  saved_case private.pachanga_moderation_cases%rowtype;
begin
  if evaluated_user_id is null then return; end if;
  select * into settings from private.pachanga_conduct_settings where singleton;
  select * into target_profile from public.pachanga_player_profiles profiles
  where profiles.user_id = evaluated_user_id;
  if not found then return; end if;

  select
    count(*) filter (where attendance.updated_at >= clock_timestamp() - make_interval(days => settings.no_show_reminder_window_days)),
    count(*) filter (where attendance.updated_at >= clock_timestamp() - make_interval(days => settings.no_show_review_window_days))
  into no_shows_90, no_shows_180
  from private.pachanga_post_match_attendance attendance
  where attendance.target_user_id = evaluated_user_id
    and attendance.current_outcome = 'unexcused_no_show'
    and attendance.response_state in ('agreed', 'confirmed_uncontested', 'maintained');

  select count(*) into late_90
  from private.pachanga_post_match_attendance attendance
  where attendance.target_user_id = evaluated_user_id
    and attendance.current_outcome = 'late_cancellation'
    and attendance.response_state in ('agreed', 'confirmed_uncontested', 'maintained')
    and attendance.updated_at >= clock_timestamp() - make_interval(days => settings.late_cancellation_window_days);

  if no_shows_90 >= settings.no_show_reminder_count then
    perform private.pachanga_notify_v1(
      evaluated_user_id,
      'attendance_warning_reminder',
      'Recordatorio de asistencia',
      'Confirma solo cuando esperes poder acudir y avisa en cuanto cambie tu disponibilidad.',
      '/perfil/conducta',
      jsonb_build_object('confirmedNoShows', no_shows_90, 'affectsSportRating', false),
      'attendance-no-show-reminder:' || evaluated_user_id::text || ':' || settings.policy_version
    );
  end if;

  if late_90 >= settings.late_cancellation_reminder_count then
    perform private.pachanga_notify_v1(
      evaluated_user_id,
      'attendance_warning_late_cancellation',
      'Recordatorio de fiabilidad',
      'Tus ultimas bajas se comunicaron muy cerca del partido. Avisar antes ayuda a cubrir la plaza.',
      '/perfil/conducta',
      jsonb_build_object('lateCancellations', late_90, 'automaticRestriction', false, 'affectsSportRating', false),
      'attendance-late-reminder:' || evaluated_user_id::text || ':' || settings.policy_version
    );
  end if;

  if no_shows_180 >= settings.no_show_review_count then
    insert into private.pachanga_moderation_cases(
      target_profile_id, target_user_id, source_type, category, state, priority,
      restriction_recommended, decision_summary, report_count, source_cluster_count,
      independent_source_count, correlated_source_count
    ) values (
      target_profile.id, evaluated_user_id, 'attendance_reliability', 'attendance_reliability',
      'triaged', 'high', true,
      'Revision social recomendada por no-shows confirmados; no existe sancion automatica.',
      0, 0, 0, 0
    )
    on conflict (target_profile_id, source_type, category)
      where source_type = 'attendance_reliability'
        and state not in ('dismissed', 'corrected', 'closed')
    do update set
      restriction_recommended = true,
      priority = case when private.pachanga_moderation_cases.priority = 'urgent_review'
        then 'urgent_review' else 'high' end,
      revision = private.pachanga_moderation_cases.revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    returning * into saved_case;

    insert into private.pachanga_moderation_events(
      case_id, operation_id, actor_user_id, event_type, from_state, to_state,
      case_revision, payload
    ) values (
      saved_case.id, target_operation_id, null, 'attendance_review_recommended',
      saved_case.state, saved_case.state, saved_case.revision,
      jsonb_build_object('confirmedNoShows', no_shows_180, 'automaticRestrictionApplied', false, 'affectsSportRating', false)
    ) on conflict do nothing;

    perform private.pachanga_conduct_notify_moderators_v1(
      'conduct_warning_review', 'Revision social recomendada',
      'Un historial objetivo de asistencia requiere revision humana.',
      '/admin/conduct?case=' || saved_case.opaque_reference::text,
      jsonb_build_object('caseReference', saved_case.opaque_reference, 'priority', saved_case.priority),
      'conduct-attendance-review:' || saved_case.id::text
    );
  end if;
end;
$$;

revoke all on function private.pachanga_evaluate_attendance_reliability_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function public.resolve_pachanga_attendance_review_v1(
  target_review_id uuid,
  next_resolution text,
  corrected_outcome text,
  resolution_note text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  replay jsonb;
  review private.pachanga_attendance_reviews%rowtype;
  attendance private.pachanga_post_match_attendance%rowtype;
  old_outcome text;
  old_response text;
  event_sequence bigint;
  response jsonb;
  target_profile public.pachanga_player_profiles%rowtype;
  saved_case private.pachanga_moderation_cases%rowtype;
begin
  if current_user_id is null or operation_id is null or expected_revision is null
    or next_resolution not in ('maintain', 'correct', 'escalate') then
    raise exception 'Authentication, operation id, revision and valid resolution required';
  end if;
  if char_length(coalesce(resolution_note, '')) > 500 then raise exception 'Resolution note is too long'; end if;
  if next_resolution = 'correct' and corrected_outcome not in ('played', 'excused_absence', 'late_cancellation', 'unexcused_no_show') then
    raise exception 'Corrected outcome required';
  end if;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.resolve', current_user_id);
  if replay is not null then return replay; end if;
  select * into review from private.pachanga_attendance_reviews reviews
  where reviews.id = target_review_id for update;
  if not found then raise exception 'Attendance review not found'; end if;
  select * into attendance from private.pachanga_post_match_attendance facts
  where facts.id = review.attendance_id for update;
  replay := private.pachanga_conduct_replay_v1(operation_id, 'attendance.resolve', current_user_id);
  if replay is not null then return replay; end if;
  if not public.is_pachanga_group_admin(attendance.group_id) then
    raise exception 'Only the certifying team admins can resolve attendance';
  end if;
  if review.revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the attendance review.' using errcode = 'PT409';
  end if;
  if review.state not in ('submitted', 'under_review') then raise exception 'Attendance review already resolved'; end if;
  old_outcome := attendance.current_outcome;
  old_response := attendance.response_state;
  event_sequence := nextval('public.pachanga_conduct_sequence');

  if next_resolution = 'correct' then
    update private.pachanga_post_match_attendance set
      current_outcome = corrected_outcome, response_state = 'corrected',
      revision = revision + 1, server_sequence = event_sequence, updated_at = clock_timestamp()
    where id = attendance.id returning * into attendance;
    update private.pachanga_attendance_reviews set
      state = 'corrected', admin_note = nullif(trim(resolution_note), ''),
      resolved_by = current_user_id, resolved_at = clock_timestamp(),
      revision = revision + 1, server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    where id = review.id returning * into review;
  elsif next_resolution = 'maintain' then
    update private.pachanga_post_match_attendance set
      response_state = 'maintained', revision = revision + 1,
      server_sequence = event_sequence, updated_at = clock_timestamp()
    where id = attendance.id returning * into attendance;
    update private.pachanga_attendance_reviews set
      state = 'maintained', admin_note = nullif(trim(resolution_note), ''),
      resolved_by = current_user_id, resolved_at = clock_timestamp(),
      revision = revision + 1, server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    where id = review.id returning * into review;
    perform private.pachanga_evaluate_attendance_reliability_v1(attendance.target_user_id, operation_id);
  else
    select * into target_profile from public.pachanga_player_profiles profiles
    where profiles.id = attendance.target_profile_id;
    if target_profile.id is null then raise exception 'Registered target profile required for escalation'; end if;
    insert into private.pachanga_moderation_cases(
      target_profile_id, target_user_id, source_type, category, state, priority,
      decision_summary, restriction_recommended
    ) values (
      target_profile.id, attendance.target_user_id, 'attendance_dispute',
      'attendance_reliability', 'under_review', 'high',
      'Disputed attendance escalated for internal moderation.', false
    )
    on conflict (target_profile_id, source_type, category)
      where source_type = 'attendance_dispute'
        and state not in ('dismissed', 'corrected', 'closed')
    do update set
      state = 'under_review', priority = 'high',
      revision = private.pachanga_moderation_cases.revision + 1,
      server_sequence = nextval('public.pachanga_conduct_sequence'), updated_at = clock_timestamp()
    returning * into saved_case;
    update private.pachanga_attendance_reviews set
      state = 'escalated', admin_note = nullif(trim(resolution_note), ''),
      resolved_by = current_user_id, resolved_at = clock_timestamp(),
      revision = revision + 1, server_sequence = nextval('public.pachanga_conduct_sequence'),
      updated_at = clock_timestamp()
    where id = review.id returning * into review;
    perform private.pachanga_conduct_notify_moderators_v1(
      'conduct_warning_review', 'Conflicto de asistencia escalado',
      'Una asistencia disputada requiere revision interna.',
      '/admin/conduct?case=' || saved_case.opaque_reference::text,
      jsonb_build_object('caseReference', saved_case.opaque_reference),
      'attendance-escalated:' || saved_case.id::text
    );
  end if;

  insert into private.pachanga_attendance_events(
    attendance_id, operation_id, actor_user_id, event_type,
    from_outcome, to_outcome, from_response_state, to_response_state,
    reason, attendance_revision, payload
  ) values (
    attendance.id, operation_id, current_user_id, 'attendance_review_resolved',
    old_outcome, attendance.current_outcome, old_response, attendance.response_state,
    nullif(trim(resolution_note), ''), attendance.revision,
    jsonb_build_object('resolution', next_resolution, 'affectsSportRating', false, 'automaticSanctionApplied', false)
  );
  perform private.pachanga_bump_conduct_subject_v1(attendance.target_user_id);
  perform private.pachanga_bump_attendance_group_v1(attendance.group_id, attendance.match_id);
  perform private.pachanga_notify_v1(
    attendance.target_user_id,
    case when next_resolution = 'correct' then 'attendance_warning_corrected' else 'attendance_warning_resolved' end,
    case when next_resolution = 'correct' then 'Asistencia corregida' else 'Revision de asistencia resuelta' end,
    case when next_resolution = 'correct' then 'La asistencia se ha corregido y conserva su historial de auditoria.'
      when next_resolution = 'maintain' then 'La asistencia original se mantiene tras la revision.'
      else 'La revision continua con el equipo de moderacion.' end,
    '/perfil/conducta?attendance=' || attendance.id::text,
    jsonb_build_object('attendanceId', attendance.id, 'attendanceRevision', attendance.revision,
      'attendanceOutcome', attendance.current_outcome, 'attendanceResponseState', attendance.response_state),
    'attendance-resolution:' || review.id::text || ':' || review.revision::text
  );
  response := jsonb_build_object(
    'operationId', operation_id, 'confirmedRevision', review.revision,
    'serverSequence', review.server_sequence,
    'attendance', private.pachanga_attendance_snapshot_v1(attendance.id),
    'reviewState', review.state
  );
  return private.pachanga_conduct_save_receipt_v1(
    operation_id, current_user_id, 'attendance.resolve', expected_revision,
    review.revision, review.server_sequence, response, client_metadata
  );
end;
$$;

revoke all on function public.resolve_pachanga_attendance_review_v1(uuid, text, text, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
grant execute on function public.resolve_pachanga_attendance_review_v1(uuid, text, text, text, uuid, bigint, jsonb)
  to authenticated;

create or replace function public.get_pachanga_conduct_capabilities_v1()
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'policyVersion', settings.policy_version,
    'attendanceClosureEnabled', settings.attendance_closure_enabled,
    'attendanceEffectiveFrom', settings.attendance_effective_from,
    'conductReportsEnabled', settings.conduct_reports_enabled,
    'conductEffectiveFrom', settings.conduct_effective_from,
    'socialRestrictionsEnabled', settings.social_restrictions_enabled,
    'attendanceClosureWindowHours', settings.attendance_closure_window_hours,
    'attendanceDisputeWindowHours', settings.attendance_dispute_window_hours
  )
  from private.pachanga_conduct_settings settings
  where settings.singleton;
$$;

revoke all on function public.get_pachanga_conduct_capabilities_v1()
  from public, anon, authenticated;
grant execute on function public.get_pachanga_conduct_capabilities_v1() to authenticated;

create or replace function public.get_pachanga_platform_flags_v1()
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  result jsonb;
begin
  perform private.pachanga_platform_require_v1('flags.read');
  select jsonb_build_array(
    jsonb_build_object(
      'key', 'attendance', 'label', 'Asistencia', 'enabled', conduct.attendance_closure_enabled,
      'state', case when conduct.attendance_closure_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when conduct.attendance_closure_enabled then 'ACTIVE_PRODUCT' else 'READY_FOR_ACTIVATION' end,
      'readiness', 'READY',
      'readinessReason', case when conduct.attendance_closure_enabled
        then 'Cierre postpartido activo desde una frontera no retroactiva.'
        else 'Contrato completo; pendiente de activación controlada.' end,
      'dependency', 'Frontera temporal y moderación humana disponibles.',
      'effectiveFrom', conduct.attendance_effective_from,
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision,
      'source', 'pachanga_conduct_settings'
    ),
    jsonb_build_object(
      'key', 'conduct', 'label', 'Conducta', 'enabled', conduct.conduct_reports_enabled,
      'state', case when conduct.conduct_reports_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when conduct.conduct_reports_enabled then 'ACTIVE_PRODUCT' else 'READY_WITH_GUARDS' end,
      'readiness', 'GUARDED',
      'readinessReason', case when conduct.conduct_reports_enabled
        then 'Recepción privada activa; toda decisión sigue siendo humana.'
        else 'Lista con guardas de privacidad, correlación y revisión humana.' end,
      'dependency', 'Capacidad operativa de moderación; sin sanción automática.',
      'effectiveFrom', conduct.conduct_effective_from,
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision,
      'source', 'pachanga_conduct_settings'
    ),
    jsonb_build_object(
      'key', 'social_restrictions', 'label', 'Restricciones sociales',
      'enabled', conduct.social_restrictions_enabled,
      'state', case when conduct.social_restrictions_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when conduct.social_restrictions_enabled then 'ACTIVE_PRODUCT' else 'READY_WITH_GUARDS' end,
      'readiness', 'DEFERRED',
      'readinessReason', 'Preparada técnicamente; activación productiva aplazada de forma deliberada.',
      'dependency', 'Datos reales de asistencia, reportes y moderación.',
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision,
      'source', 'pachanga_conduct_settings'
    ),
    jsonb_build_object(
      'key', 'triage', 'label', 'Triage de conducta', 'enabled', conduct.conduct_triage_enabled,
      'state', case when conduct.conduct_triage_enabled and not conduct.conduct_triage_shadow_mode then 'PRODUCT'
                    when conduct.conduct_triage_enabled or conduct.conduct_triage_shadow_mode then 'LAB' else 'OFF' end,
      'classification', 'SHADOW_ONLY', 'readiness', 'SHADOW',
      'readinessReason', 'Solo prioriza y propone; no sanciona, cierra casos ni restringe.',
      'dependency', 'Validación humana continua.',
      'shadowMode', conduct.conduct_triage_shadow_mode,
      'mutable', true, 'sensitive', true, 'revision', conduct.platform_revision,
      'source', 'pachanga_conduct_settings'
    ),
    jsonb_build_object(
      'key', 'player_cosmetics', 'label', 'Cosméticos de jugador',
      'enabled', player.player_cosmetics_enabled,
      'state', case when player.player_cosmetics_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when player.player_cosmetics_enabled then 'ACTIVE_PRODUCT' else 'READY_FOR_ACTIVATION' end,
      'readiness', 'READY', 'readinessReason', 'Catálogo, inventario y equipamiento productivos.',
      'dependency', null, 'mutable', true, 'sensitive', true,
      'revision', player.platform_revision, 'source', 'pachanga_player_cosmetic_settings'
    ),
    jsonb_build_object(
      'key', 'team_cosmetics', 'label', 'Cosméticos de equipo',
      'enabled', team.team_cosmetics_enabled,
      'state', case when team.team_cosmetics_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when team.team_cosmetics_enabled then 'ACTIVE_PRODUCT' else 'READY_FOR_ACTIVATION' end,
      'readiness', 'READY', 'readinessReason', 'Catálogo y equipamiento de escudos productivos.',
      'dependency', null, 'mutable', true, 'sensitive', true,
      'revision', team.platform_revision, 'source', 'pachanga_team_cosmetic_settings'
    ),
    jsonb_build_object(
      'key', 'team_cosmetic_rewards', 'label', 'Team Cosmetic Rewards',
      'enabled', team.team_cosmetic_rewards_enabled,
      'state', case when team.team_cosmetic_rewards_enabled then 'PRODUCT' else 'OFF' end,
      'classification', case when team.team_cosmetic_rewards_enabled then 'ACTIVE_PRODUCT' else 'READY_FOR_ACTIVATION' end,
      'readiness', 'READY', 'readinessReason', 'Cinco mappings autoritativos activos; economía aislada.',
      'dependency', 'Team Cosmetics.', 'mutable', true, 'sensitive', true,
      'revision', team.platform_revision, 'source', 'pachanga_team_cosmetic_settings'
    ),
    jsonb_build_object(
      'key', 'season_score_v3', 'label', 'Season Score V3', 'enabled', false,
      'state', 'LAB', 'classification', 'NEEDS_PRODUCTIZATION', 'readiness', 'DEPENDENCY',
      'readinessReason', 'Motor validado en laboratorio; falta read model PostgreSQL productivo.',
      'dependency', 'Persistencia, refresh, season lifecycle y API pública.',
      'mutable', false, 'sensitive', true, 'revision', 0, 'source', 'season-ranking-lab'
    ),
    jsonb_build_object(
      'key', 'provincial_rankings', 'label', 'Rankings provinciales', 'enabled', false,
      'state', 'LAB', 'classification', 'NEEDS_PRODUCTIZATION', 'readiness', 'DEPENDENCY',
      'readinessReason', 'Algoritmo validado; no existe ranking territorial productivo autoritativo.',
      'dependency', 'Season Score productivo, territorio, integridad y elegibilidad.',
      'mutable', false, 'sensitive', true, 'revision', 0, 'source', 'season-ranking-lab'
    ),
    jsonb_build_object(
      'key', 'provincial_awards', 'label', 'Premios provinciales', 'enabled', false,
      'state', 'OFF', 'classification', 'BLOCKED', 'readiness', 'BLOCKED',
      'readinessReason', 'No se conceden trofeos sin ranking y cierre de temporada productivos.',
      'dependency', 'Ranking productivo, integrity, eligibility y award readiness.',
      'mutable', false, 'sensitive', true, 'revision', 0,
      'source', 'territory-award-readiness'
    ),
    jsonb_build_object(
      'key', 'premium_ball', 'label', 'Premium Ball', 'enabled', false,
      'state', 'OFF', 'classification', 'BLOCKED', 'readiness', 'DEPENDENCY',
      'operationalStatus', 'READY_PENDING_PHYSICAL_QA',
      'readinessReason', 'Fuera de catálogo productivo hasta completar QA física.',
      'dependency', 'Validación física en dispositivo real.',
      'mutable', false, 'sensitive', true, 'revision', 0,
      'source', 'team-shield-premium-3d-lab'
    )
  ) into result
  from private.pachanga_conduct_settings conduct
  cross join private.pachanga_player_cosmetic_settings player
  cross join private.pachanga_team_cosmetic_settings team
  where conduct.singleton and player.singleton and team.singleton;
  return coalesce(result, '[]'::jsonb);
end;
$$;

revoke all on function public.get_pachanga_platform_flags_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.get_pachanga_platform_flags_v1() to authenticated;

create or replace function public.set_pachanga_platform_flag_v1(
  flag_key text,
  next_enabled boolean,
  expected_revision bigint,
  operation_id uuid,
  reason text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  actor_id uuid := (select auth.uid());
  actor_role text;
  current_enabled boolean;
  current_revision bigint;
  current_effective_from timestamptz;
  next_effective_from timestamptz;
  next_revision bigint;
  response jsonb;
  sequence_value bigint;
begin
  actor_role := private.pachanga_platform_require_v1('flags.write');
  if flag_key not in (
    'attendance', 'conduct', 'social_restrictions', 'triage',
    'player_cosmetics', 'team_cosmetics', 'team_cosmetic_rewards'
  ) then raise exception 'Flag is read-only or unknown'; end if;
  if operation_id is null or char_length(trim(coalesce(reason, ''))) < 3 then
    raise exception 'operationId and reason required';
  end if;
  response := private.pachanga_platform_admin_replay_v1(
    operation_id, 'platform_flag.set', 'feature_flag', flag_key
  );
  if response is not null then return response; end if;

  if flag_key in ('attendance', 'conduct', 'social_restrictions', 'triage') then
    select case flag_key
      when 'attendance' then settings.attendance_closure_enabled
      when 'conduct' then settings.conduct_reports_enabled
      when 'social_restrictions' then settings.social_restrictions_enabled
      else settings.conduct_triage_enabled
    end,
    settings.platform_revision,
    case flag_key
      when 'attendance' then settings.attendance_effective_from
      when 'conduct' then settings.conduct_effective_from
      else null
    end
    into current_enabled, current_revision, current_effective_from
    from private.pachanga_conduct_settings settings
    where settings.singleton
    for update;
  elsif flag_key = 'player_cosmetics' then
    select settings.player_cosmetics_enabled, settings.platform_revision, null::timestamptz
    into current_enabled, current_revision, current_effective_from
    from private.pachanga_player_cosmetic_settings settings
    where settings.singleton
    for update;
  else
    select case flag_key when 'team_cosmetics' then settings.team_cosmetics_enabled
                         else settings.team_cosmetic_rewards_enabled end,
           settings.platform_revision, null::timestamptz
    into current_enabled, current_revision, current_effective_from
    from private.pachanga_team_cosmetic_settings settings
    where settings.singleton
    for update;
  end if;
  if expected_revision is null or current_revision <> expected_revision then
    raise exception 'Feature flag changed before saving' using errcode = '40001';
  end if;

  next_revision := current_revision + 1;
  next_effective_from := case
    when flag_key in ('attendance', 'conduct') and next_enabled and not current_enabled
      then clock_timestamp()
    else current_effective_from
  end;

  if flag_key = 'attendance' then
    update private.pachanga_conduct_settings
    set attendance_closure_enabled = next_enabled,
        attendance_effective_from = next_effective_from,
        platform_revision = next_revision,
        updated_at = clock_timestamp()
    where singleton;
  elsif flag_key = 'conduct' then
    update private.pachanga_conduct_settings
    set conduct_reports_enabled = next_enabled,
        conduct_effective_from = next_effective_from,
        platform_revision = next_revision,
        updated_at = clock_timestamp()
    where singleton;
  elsif flag_key = 'social_restrictions' then
    update private.pachanga_conduct_settings
    set social_restrictions_enabled = next_enabled,
        platform_revision = next_revision,
        updated_at = clock_timestamp()
    where singleton;
  elsif flag_key = 'triage' then
    update private.pachanga_conduct_settings
    set conduct_triage_enabled = next_enabled,
        platform_revision = next_revision,
        updated_at = clock_timestamp()
    where singleton;
  elsif flag_key = 'player_cosmetics' then
    update private.pachanga_player_cosmetic_settings
    set player_cosmetics_enabled = next_enabled,
        platform_revision = next_revision,
        updated_at = clock_timestamp()
    where singleton;
  elsif flag_key = 'team_cosmetics' then
    update private.pachanga_team_cosmetic_settings
    set team_cosmetics_enabled = next_enabled,
        platform_revision = next_revision,
        updated_at = clock_timestamp()
    where singleton;
  else
    perform private.pachanga_set_team_cosmetic_rewards_enabled_v1(next_enabled, operation_id, 1);
    update private.pachanga_team_cosmetic_settings
    set platform_revision = next_revision, updated_at = clock_timestamp()
    where singleton;
  end if;

  sequence_value := nextval('private.pachanga_platform_admin_sequence');
  response := jsonb_strip_nulls(jsonb_build_object(
    'key', flag_key,
    'enabled', next_enabled,
    'effectiveFrom', next_effective_from,
    'revision', next_revision,
    'serverSequence', sequence_value
  ));
  insert into private.pachanga_platform_admin_action_ledger(
    operation_id, actor_user_id, actor_role, action, target_type, target_id,
    reason, before_state, after_state, response, server_sequence
  ) values (
    operation_id, actor_id, actor_role, 'platform_flag.set', 'feature_flag', flag_key,
    trim(reason),
    jsonb_strip_nulls(jsonb_build_object(
      'enabled', current_enabled,
      'effectiveFrom', current_effective_from,
      'revision', current_revision
    )),
    response, response, sequence_value
  );
  return response;
end;
$$;

revoke all on function public.set_pachanga_platform_flag_v1(text, boolean, bigint, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.set_pachanga_platform_flag_v1(text, boolean, bigint, uuid, text)
  to authenticated;
