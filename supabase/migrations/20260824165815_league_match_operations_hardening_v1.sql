-- Pachangas IQ R4C hardening: immutable ledgers, operational notifications,
-- service-only deadline processing and direct-write closure.

set lock_timeout = '5s';
set statement_timeout = '120s';

-- R4B freezes a published round because it does not yet own match operations.
-- R4C replaces that guard with the explicit sporting lifecycle while keeping
-- schedule identity and published fixture data immutable.
create or replace function private.pachanga_league_schedule_round_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare is_current boolean;
begin
  if tg_op = 'DELETE' then
    raise exception 'SCHEDULE_ROUND_IMMUTABLE' using errcode = '55000';
  end if;
  if new.competition_id is distinct from old.competition_id
     or new.edition_id is distinct from old.edition_id
     or new.category_id is distinct from old.category_id
     or new.stage_id is distinct from old.stage_id
     or new.division_id is distinct from old.division_id
     or new.competition_group_id is distinct from old.competition_group_id
     or new.schedule_revision_id is distinct from old.schedule_revision_id
     or new.round_number is distinct from old.round_number
     or new.leg_number is distinct from old.leg_number
     or new.rule_revision_id is distinct from old.rule_revision_id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'SCHEDULE_ROUND_IDENTITY_IMMUTABLE' using errcode = '55000';
  end if;
  if current_setting('pachangas.r4c_official_decision', true) = 'on'
     and new.status = old.status
     and new.revision = old.revision + 1
     and (to_jsonb(new) - array['revision', 'server_sequence', 'updated_at'])
       = (to_jsonb(old) - array['revision', 'server_sequence', 'updated_at']) then
    return new;
  end if;
  if old.status = 'published'
     and new.status = 'cancelled'
     and current_setting('pachangas.r4b_qa_archive', true) = 'on'
     and private.pachanga_competition_is_service_authority_v1() then
    if new.revision <> old.revision + 1 then
      raise exception 'SCHEDULE_ROUND_MONOTONICITY_REQUIRED' using errcode = 'PT409';
    end if;
    return new;
  end if;
  if old.status in ('locked', 'cancelled') then
    raise exception 'SCHEDULE_ROUND_TERMINAL' using errcode = '55000';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception 'SCHEDULE_ROUND_MONOTONICITY_REQUIRED' using errcode = 'PT409';
  end if;
  if old.status = 'published' and new.status <> 'in_progress'
     or old.status = 'in_progress' and new.status <> 'completed'
     or old.status = 'completed' and new.status <> 'locked' then
    raise exception 'SCHEDULE_ROUND_TRANSITION_INVALID' using errcode = '23514';
  end if;
  if old.status in ('published', 'in_progress', 'completed') and (
    new.display_name is distinct from old.display_name
    or new.starts_at is distinct from old.starts_at
    or new.ends_at is distinct from old.ends_at
    or new.published_at is distinct from old.published_at
  ) then
    raise exception 'SCHEDULE_ROUND_FIXTURE_IMMUTABLE' using errcode = '55000';
  end if;
  select exists (
    select 1
    from public.pachanga_competition_schedule_plans plans
    where plans.current_revision_id = old.schedule_revision_id
  ) into is_current;
  if old.status = 'draft' and is_current and (
    new.display_name is distinct from old.display_name
    or new.starts_at is distinct from old.starts_at
    or new.ends_at is distinct from old.ends_at
  ) then
    raise exception 'SCHEDULE_ROUND_REQUIRES_NEW_REVISION' using errcode = 'PT409';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_schedule_round_guard_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_notification_policy_v1(target_kind text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select lower(coalesce(nullif(trim(target_kind), ''), 'general')) as kind
  )
  select jsonb_build_object(
    'category', case
      when kind like '%achievement%' or kind like '%reward%' then 'achievement'
      when kind like '%challenge%' or kind like '%external_result%' then 'challenge'
      when kind like '%invitation%' or kind like '%open_match_request%'
        or kind like '%withdrawal%' or kind like '%market%'
        or kind like 'club_team_%' or kind like 'referee_club_%'
        or kind like 'club_referee_%' then 'market'
      when kind like '%attendance%' or kind like '%availability%'
        or kind like 'match_%' or kind like 'league_round_%' then 'match'
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' then 'security'
      else 'group'
    end,
    'priority', case
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' or kind like '%challenge%'
        or kind like '%external_result%' or kind like '%invitation%'
        or kind like '%open_match_request%' or kind like '%withdrawal%'
        or kind like 'match_result_%' or kind in (
          'club_team_request', 'club_team_invitation',
          'club_review_approved', 'club_review_rejected',
          'referee_club_request'
        ) then 'critical'
      when kind like '%achievement%' or kind like '%reward%'
        or kind like 'match_squad_%' or kind = 'league_round_completed'
        or kind in ('group_member_removed', 'match_attendance_cancelled') then 'high'
      else 'normal'
    end,
    'mandatoryInApp', (
      kind like '%security%' or kind like '%sanction%' or kind like '%warning%'
      or kind like '%challenge%' or kind like '%external_result%'
      or kind like '%invitation%' or kind like '%open_match_request%'
      or kind like '%withdrawal%' or kind like '%achievement%' or kind like '%reward%'
      or kind like 'match_result_%' or kind like 'match_squad_%'
      or kind = 'league_round_completed'
      or kind in (
        'group_member_removed', 'club_team_request',
        'club_review_approved', 'club_review_rejected',
        'referee_club_request'
      )
    )
  )
  from normalized;
$$;

revoke all on function private.pachanga_notification_policy_v1(text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_notify_entry_v1(
  target_entry_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare recipient record;
begin
  if target_entry_id is null then return; end if;
  for recipient in
    select groups.owner_id as user_id
    from public.pachanga_competition_entries entries
    join public.pachanga_groups groups on groups.id = entries.team_id
    where entries.id = target_entry_id
    union
    select delegates.user_id
    from public.pachanga_competition_team_delegates delegates
    where delegates.entry_id = target_entry_id
      and delegates.status = 'active'
      and delegates.delegate_role in ('PRIMARY_DELEGATE', 'ROSTER_MANAGER')
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, target_kind, target_title, target_body,
      target_action_url,
      jsonb_strip_nulls(coalesce(target_payload, '{}'::jsonb)
        || jsonb_build_object('entryId', target_entry_id)),
      'r4c:' || target_operation_id::text || ':' || target_kind || ':' || recipient.user_id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_league_match_notify_entry_v1(
  uuid, text, text, text, text, jsonb, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_notify_organizer_v1(
  target_competition_id uuid,
  target_kind text,
  target_title text,
  target_body text,
  target_action_url text,
  target_payload jsonb,
  target_operation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare recipient record;
begin
  for recipient in
    with competition as (
      select * from public.pachanga_competitions where id = target_competition_id
    )
    select groups.owner_id as user_id
    from competition
    join public.pachanga_groups groups on groups.id = competition.organizer_group_id
    union
    select memberships.user_id
    from competition
    join public.pachanga_club_memberships memberships
      on memberships.club_id = competition.organizer_club_id
    where memberships.status = 'active'
      and memberships.role in ('club_owner', 'club_competition_manager')
    union
    select assignments.user_id
    from public.pachanga_competition_staff_assignments assignments
    where assignments.competition_id = target_competition_id
      and assignments.status = 'active'
      and assignments.staff_role in (
        'competition_owner', 'competition_director', 'competition_admin',
        'competition_result_manager', 'competition_standings_manager'
      )
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, target_kind, target_title, target_body,
      target_action_url,
      jsonb_strip_nulls(coalesce(target_payload, '{}'::jsonb)
        || jsonb_build_object('competitionId', target_competition_id)),
      'r4c:' || target_operation_id::text || ':' || target_kind || ':' || recipient.user_id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_league_match_notify_organizer_v1(
  uuid, text, text, text, text, jsonb, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_event_notifications_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare round_row public.pachanga_competition_rounds%rowtype;
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare target_entry_id uuid;
declare action_url text;
declare payload jsonb;
declare recipient_entry_id uuid;
begin
  if new.aggregate_type <> 'league_match_operations' then return new; end if;
  payload := jsonb_build_object('operationId', new.operation_id, 'action', new.action);

  if new.action like 'round.%' then
    select * into round_row from public.pachanga_competition_rounds rounds
    where rounds.id = new.aggregate_id::uuid;
    if not found then return new; end if;
    action_url := '/competiciones/' || round_row.competition_id::text
      || '/jornadas/' || round_row.id::text;
    if new.action = 'round.complete' then
      for recipient_entry_id in
        select distinct entry_id
        from (
          select contexts.home_entry_id as entry_id
          from public.pachanga_competition_match_contexts contexts
          where contexts.round_id = round_row.id
          union
          select contexts.away_entry_id
          from public.pachanga_competition_match_contexts contexts
          where contexts.round_id = round_row.id
        ) entries
      loop
        perform private.pachanga_league_match_notify_entry_v1(
          recipient_entry_id, 'league_round_completed', 'Jornada completada',
          'Todos los resultados de la jornada ya son oficiales.', action_url,
          payload || jsonb_build_object('roundId', round_row.id), new.operation_id
        );
      end loop;
      perform private.pachanga_league_match_notify_organizer_v1(
        round_row.competition_id, 'league_round_completed', 'Jornada completada',
        'La jornada ya puede revisarse y bloquearse.', action_url,
        payload || jsonb_build_object('roundId', round_row.id), new.operation_id
      );
    end if;
    return new;
  end if;

  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = new.aggregate_id::uuid;
  if not found then return new; end if;
  action_url := '/competiciones/' || context_row.competition_id::text
    || '/partidos/' || context_row.id::text;
  payload := payload || jsonb_build_object(
    'competitionId', context_row.competition_id,
    'matchContextId', context_row.id,
    'canonicalMatchId', context_row.canonical_match_id
  );

  if new.action = 'squad.submit' then
    target_entry_id := nullif(new.event_payload ->> 'entryId', '')::uuid;
    perform private.pachanga_league_match_notify_organizer_v1(
      context_row.competition_id, 'match_squad_submitted', 'Convocatoria enviada',
      'Un equipo ha enviado su convocatoria para validación.', action_url,
      payload || jsonb_build_object('entryId', target_entry_id), new.operation_id
    );
  elsif new.action in ('squad.validate', 'squad.reject') then
    target_entry_id := nullif(new.event_payload ->> 'entryId', '')::uuid;
    perform private.pachanga_league_match_notify_entry_v1(
      target_entry_id,
      case when new.action = 'squad.validate' then 'match_squad_validated'
        else 'match_squad_rejected' end,
      case when new.action = 'squad.validate' then 'Convocatoria validada'
        else 'Convocatoria rechazada' end,
      case when new.action = 'squad.validate'
        then 'La convocatoria del partido ha sido validada.'
        else 'La convocatoria necesita cambios antes de poder validarse.' end,
      action_url, payload, new.operation_id
    );
  elsif new.action = 'sporting_result.submit' then
    select * into result_row from public.pachanga_competition_sporting_results results
    where results.id = nullif(new.event_payload ->> 'sportingResultId', '')::uuid;
    recipient_entry_id := result_row.pending_response_from_entry_id;
    perform private.pachanga_league_match_notify_entry_v1(
      recipient_entry_id, 'match_result_received', 'Resultado recibido',
      'El rival ha enviado el resultado. Revísalo antes de responder.',
      action_url, payload, new.operation_id
    );
  elsif new.action = 'sporting_result.propose_change' then
    select * into result_row from public.pachanga_competition_sporting_results results
    where results.id = nullif(new.event_payload ->> 'sportingResultId', '')::uuid;
    perform private.pachanga_league_match_notify_entry_v1(
      result_row.pending_response_from_entry_id, 'match_result_change_proposed',
      'Cambio de resultado propuesto',
      'El rival ha propuesto una corrección del marcador.',
      action_url, payload, new.operation_id
    );
  elsif new.action = 'sporting_result.dispute' then
    perform private.pachanga_league_match_notify_entry_v1(
      context_row.home_entry_id, 'match_result_disputed', 'Resultado disputado',
      'El resultado necesita revisión del organizador.', action_url, payload, new.operation_id
    );
    perform private.pachanga_league_match_notify_entry_v1(
      context_row.away_entry_id, 'match_result_disputed', 'Resultado disputado',
      'El resultado necesita revisión del organizador.', action_url, payload, new.operation_id
    );
    perform private.pachanga_league_match_notify_organizer_v1(
      context_row.competition_id, 'match_result_disputed', 'Resultado disputado',
      'Hay una disputa que requiere una decisión oficial.', action_url, payload, new.operation_id
    );
  elsif new.action in (
    'sporting_result.accept', 'sporting_result.deadline_auto_confirm'
  ) then
    perform private.pachanga_league_match_notify_entry_v1(
      context_row.home_entry_id, 'match_result_confirmed', 'Resultado confirmado',
      'Ambos equipos han confirmado el marcador.', action_url, payload, new.operation_id
    );
    perform private.pachanga_league_match_notify_entry_v1(
      context_row.away_entry_id, 'match_result_confirmed', 'Resultado confirmado',
      'Ambos equipos han confirmado el marcador.', action_url, payload, new.operation_id
    );
    if context_row.status = 'official' then
      perform private.pachanga_league_match_notify_organizer_v1(
        context_row.competition_id, 'match_result_official', 'Resultado oficial',
        'El resultado confirmado se ha oficializado automáticamente.', action_url,
        payload, new.operation_id
      );
    end if;
  elsif new.action in (
    'official_result.publish', 'official_result.supersede', 'official_result.annul'
  ) then
    perform private.pachanga_league_match_notify_entry_v1(
      context_row.home_entry_id,
      case when new.action = 'official_result.publish' then 'match_result_official'
        else 'match_result_official_corrected' end,
      case when new.action = 'official_result.publish' then 'Resultado oficial'
        else 'Resultado oficial actualizado' end,
      'La autoridad de la competición ha publicado una decisión oficial.',
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_match_notify_entry_v1(
      context_row.away_entry_id,
      case when new.action = 'official_result.publish' then 'match_result_official'
        else 'match_result_official_corrected' end,
      case when new.action = 'official_result.publish' then 'Resultado oficial'
        else 'Resultado oficial actualizado' end,
      'La autoridad de la competición ha publicado una decisión oficial.',
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_match_notify_organizer_v1(
      context_row.competition_id,
      case when new.action = 'official_result.publish' then 'match_result_official'
        else 'match_result_official_corrected' end,
      case when new.action = 'official_result.publish' then 'Resultado oficial'
        else 'Resultado oficial actualizado' end,
      'La decisión oficial y la clasificación han quedado actualizadas.',
      action_url, payload, new.operation_id
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_match_event_notifications_v1()
  from public, anon, authenticated;

drop trigger if exists notify_pachanga_league_match_event_v1
  on private.pachanga_competition_events;
create trigger notify_pachanga_league_match_event_v1
after insert on private.pachanga_competition_events
for each row execute function private.pachanga_league_match_event_notifications_v1();

create or replace function private.pachanga_league_squad_revision_seal_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'R4C_SQUAD_REVISION_IMMUTABLE' using errcode = '55000';
  end if;
  if old.member_set_checksum <> repeat('0', 64)
     or old.lineup_checksum <> repeat('0', 64)
     or new.id is distinct from old.id
     or new.squad_id is distinct from old.squad_id
     or new.version is distinct from old.version
     or new.squad_status is distinct from old.squad_status
     or new.roster_revision_id is distinct from old.roster_revision_id
     or new.rule_revision_id is distinct from old.rule_revision_id
     or new.reason is distinct from old.reason
     or new.effective_at is distinct from old.effective_at
     or new.created_by is distinct from old.created_by
     or new.server_sequence is distinct from old.server_sequence
     or new.created_at is distinct from old.created_at
     or new.member_set_checksum = repeat('0', 64)
     or new.lineup_checksum = repeat('0', 64) then
    raise exception 'R4C_SQUAD_REVISION_IMMUTABLE' using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_squad_revision_seal_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_league_squad_revision_v1
  on public.pachanga_competition_match_squad_revisions;
create trigger guard_pachanga_league_squad_revision_v1
before update or delete on public.pachanga_competition_match_squad_revisions
for each row execute function private.pachanga_league_squad_revision_seal_v1();

create or replace function private.pachanga_league_result_revision_seal_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'R4C_RESULT_REVISION_IMMUTABLE' using errcode = '55000';
  end if;
  if old.content_checksum <> repeat('0', 64)
     or new.id is distinct from old.id
     or new.sporting_result_id is distinct from old.sporting_result_id
     or new.version is distinct from old.version
     or new.previous_revision_id is distinct from old.previous_revision_id
     or new.revision_kind is distinct from old.revision_kind
     or new.proposed_by_entry_id is distinct from old.proposed_by_entry_id
     or new.score_home is distinct from old.score_home
     or new.score_away is distinct from old.score_away
     or new.scorer_detail_policy is distinct from old.scorer_detail_policy
     or new.operation_id is distinct from old.operation_id
     or new.created_by is distinct from old.created_by
     or new.server_sequence is distinct from old.server_sequence
     or new.created_at is distinct from old.created_at
     or new.content_checksum = repeat('0', 64) then
    raise exception 'R4C_RESULT_REVISION_IMMUTABLE' using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_result_revision_seal_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_league_result_revision_v1
  on public.pachanga_competition_sporting_result_revisions;
create trigger guard_pachanga_league_result_revision_v1
before update or delete on public.pachanga_competition_sporting_result_revisions
for each row execute function private.pachanga_league_result_revision_seal_v1();

do $$
declare target_table regclass;
begin
  foreach target_table in array array[
    'public.pachanga_competition_match_squad_members'::regclass,
    'public.pachanga_competition_sporting_result_scorers'::regclass,
    'public.pachanga_competition_result_responses'::regclass,
    'public.pachanga_competition_official_result_decisions'::regclass,
    'private.pachanga_competition_official_result_evidence'::regclass,
    'public.pachanga_competition_standing_snapshots'::regclass,
    'public.pachanga_competition_standing_rows'::regclass,
    'public.pachanga_competition_tie_break_explanations'::regclass,
    'public.pachanga_competition_persisted_draw_lots'::regclass,
    'public.pachanga_competition_standing_rebuild_receipts'::regclass
  ] loop
    execute format('drop trigger if exists guard_r4c_append_only_v1 on %s', target_table);
    execute format(
      'create trigger guard_r4c_append_only_v1 before update or delete on %s for each row execute function private.pachanga_competition_immutable_ledger_v1()',
      target_table
    );
  end loop;
end;
$$;

create or replace function private.pachanga_league_process_expired_result_v1(
  target_sporting_result_id uuid,
  target_operation_id uuid,
  target_now timestamptz,
  target_client_metadata jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare action_name constant text := 'sporting_result.deadline_auto_confirm';
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare result_revision public.pachanga_competition_sporting_result_revisions%rowtype;
declare policy jsonb;
declare request_hash text;
declare replay jsonb;
declare sequence_value bigint;
declare coordination_round_id uuid;
declare observed_round_revision bigint;
declare locked_round_revision bigint;
declare current_round_revision bigint;
declare official_result jsonb;
declare snapshot jsonb;
declare invalidations jsonb;
begin
  if not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'SERVICE_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  select contexts.round_id, rounds.revision
    into coordination_round_id, observed_round_revision
  from public.pachanga_competition_sporting_results results
  join public.pachanga_competition_match_contexts contexts
    on contexts.id = results.competition_match_context_id
  join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
  where results.id = target_sporting_result_id;
  if coordination_round_id is null then
    raise exception 'R4C_SPORTING_RESULT_NOT_FOUND' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('r4c-round:' || coordination_round_id::text, 91407)
  );
  select rounds.revision into locked_round_revision
  from public.pachanga_competition_rounds rounds
  where rounds.id = coordination_round_id;
  if locked_round_revision is distinct from observed_round_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  select contexts.* into context_row
  from public.pachanga_competition_sporting_results results
  join public.pachanga_competition_match_contexts contexts
    on contexts.id = results.competition_match_context_id
  where results.id = target_sporting_result_id
  for update of contexts;
  if not found then raise exception 'R4C_SPORTING_RESULT_NOT_FOUND' using errcode = 'P0002'; end if;
  select * into result_row
  from public.pachanga_competition_sporting_results results
  where results.id = target_sporting_result_id
  for update;
  request_hash := private.pachanga_league_match_request_hash_v1(
    action_name, context_row.id, context_row.revision,
    jsonb_build_object('sportingResultId', result_row.id, 'targetNow', target_now)
  );
  replay := private.pachanga_league_match_operation_replay_v1(
    target_operation_id, null, action_name, context_row.id, request_hash
  );
  if replay is not null then return replay; end if;
  if context_row.status <> 'result_pending'
     or result_row.state not in ('submitted', 'change_proposed')
     or result_row.response_deadline is null
     or result_row.response_deadline > target_now then
    raise exception 'R4C_RESULT_DEADLINE_NOT_DUE' using errcode = 'PT409';
  end if;
  policy := private.pachanga_league_match_policy_v1(context_row.rule_revision_id);
  if result_row.confirmation_policy <> 'AUTO_CONFIRM_AFTER_DEADLINE'
     or policy ->> 'confirmationPolicy' <> 'AUTO_CONFIRM_AFTER_DEADLINE' then
    raise exception 'R4C_RESULT_AUTO_CONFIRM_NOT_ALLOWED' using errcode = '42501';
  end if;
  select * into result_revision
  from public.pachanga_competition_sporting_result_revisions revisions
  where revisions.id = result_row.current_revision_id;
  perform private.pachanga_league_match_validate_confirmable_result_v1(result_revision.id);
  sequence_value := nextval('private.pachanga_competition_sequence');
  update public.pachanga_competition_sporting_results results set
    state = 'confirmed', pending_response_from_entry_id = null,
    confirmed_at = target_now, revision = results.revision + 1,
    server_sequence = sequence_value, updated_at = clock_timestamp()
  where results.id = result_row.id;
  if coalesce((policy ->> 'autoOfficialAfterConfirmation')::boolean, false) then
    perform private.pachanga_league_match_assert_flags_v1(false, false, true, true, true, true);
    official_result := private.pachanga_league_official_result_decide_v1(
      context_row.id, 'MIRROR_SPORTING_RESULT', null, null,
      'result.deadline_auto_official',
      'Resultado confirmado al vencer el plazo reglamentario.',
      '{}'::jsonb, null, target_operation_id, null,
      'automatic_rule', sequence_value
    );
  else
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where contexts.id = context_row.id;
  end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = context_row.id;
  snapshot := private.pachanga_league_match_snapshot_v1(context_row.id, null);
  invalidations := jsonb_build_array(
    jsonb_build_object('entityType', 'match', 'entityId', context_row.id,
      'revision', context_row.revision),
    jsonb_build_object('entityType', 'result', 'entityId', context_row.canonical_match_id,
      'revision', context_row.revision)
  );
  if official_result is not null then
    select rounds.revision into current_round_revision
    from public.pachanga_competition_rounds rounds
    where rounds.id = coordination_round_id;
    invalidations := invalidations || jsonb_build_array(
      jsonb_build_object(
        'entityType', 'standings', 'entityId', context_row.stage_id,
        'revision', context_row.revision
      ),
      jsonb_build_object(
        'entityType', 'round', 'entityId', coordination_round_id,
        'revision', current_round_revision
      )
    );
  end if;
  return private.pachanga_league_match_store_command_v1(
    target_operation_id, null, 'service_authority', action_name,
    context_row.id, context_row.competition_id, context_row.revision,
    sequence_value, request_hash,
    private.pachanga_league_match_sanitize_metadata_v1(target_client_metadata),
    jsonb_build_object(
      'sportingResultId', result_row.id,
      'responseDeadline', result_row.response_deadline,
      'autoOfficial', official_result is not null
    ),
    snapshot, invalidations
  );
end;
$$;

revoke all on function private.pachanga_league_process_expired_result_v1(
  uuid, uuid, timestamptz, jsonb
) from public, anon, authenticated;

create or replace function public.process_pachanga_league_result_deadlines_v1(
  operation_id uuid,
  target_now timestamptz default clock_timestamp(),
  batch_size integer default 100,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare action_name constant text := 'league_result_deadlines.process';
declare aggregate_key constant text := 'r4c-result-deadlines';
declare receipt private.pachanga_competition_operation_receipts%rowtype;
declare selected_result record;
declare child_operation_id uuid;
declare request_hash text;
declare metadata jsonb;
declare results jsonb := '[]'::jsonb;
declare skipped jsonb := '[]'::jsonb;
declare response jsonb;
declare child_response jsonb;
declare sequence_value bigint;
declare confirmed_at timestamptz := clock_timestamp();
begin
  if not private.pachanga_competition_is_service_authority_v1() then
    raise exception 'SERVICE_AUTHORITY_REQUIRED' using errcode = '42501';
  end if;
  if operation_id is null or target_now is null or batch_size < 1 or batch_size > 100
     or target_now > clock_timestamp() + interval '5 minutes'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_R4C_DEADLINE_BATCH' using errcode = '22023';
  end if;
  metadata := private.pachanga_league_match_sanitize_metadata_v1(client_metadata);
  request_hash := encode(extensions.digest(convert_to(jsonb_build_object(
    'action', action_name, 'targetNow', target_now, 'batchSize', batch_size
  )::text, 'UTF8'), 'sha256'), 'hex');
  perform pg_advisory_xact_lock(hashtextextended('r4c-result-deadlines:' || operation_id::text, 0));
  select * into receipt
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = $1;
  if found then
    if receipt.actor_id is not null or receipt.actor_kind <> 'service_authority'
       or receipt.action <> action_name
       or receipt.aggregate_type <> 'league_result_deadline_batch'
       or receipt.aggregate_id <> aggregate_key
       or receipt.request_hash <> request_hash then
      raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
    end if;
    return receipt.response;
  end if;
  for selected_result in
    select results_table.id, results_table.revision
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_sporting_results results_table
      on results_table.competition_match_context_id = contexts.id
    where results_table.state in ('submitted', 'change_proposed')
      and results_table.confirmation_policy = 'AUTO_CONFIRM_AFTER_DEADLINE'
      and results_table.response_deadline <= target_now
    order by results_table.response_deadline, results_table.server_sequence, results_table.id
    limit batch_size
  loop
    child_operation_id := md5(
      'r4c-deadline:' || operation_id::text || ':' || selected_result.id::text
      || ':' || selected_result.revision::text
    )::uuid;
    begin
      child_response := private.pachanga_league_process_expired_result_v1(
        selected_result.id, child_operation_id, target_now, metadata
      );
      results := results || jsonb_build_array(child_response);
    exception
      when sqlstate 'PT409' then
        skipped := skipped || jsonb_build_array(jsonb_build_object(
          'sportingResultId', selected_result.id,
          'reason', sqlerrm
        ));
    end;
  end loop;
  sequence_value := nextval('private.pachanga_competition_sequence');
  response := jsonb_build_object(
    'operationId', operation_id,
    'confirmedRevision', jsonb_array_length(results),
    'confirmedAt', confirmed_at,
    'serverSequence', sequence_value,
    'processedCount', jsonb_array_length(results),
    'skippedCount', jsonb_array_length(skipped),
    'skipped', skipped,
    'results', results
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    operation_id, null, 'service_authority', 'league_result_deadline_batch',
    aggregate_key, null, action_name, jsonb_array_length(results),
    sequence_value, action_name,
    jsonb_build_object(
      'processedCount', jsonb_array_length(results),
      'skippedCount', jsonb_array_length(skipped)
    ), confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    operation_id, null, 'service_authority', action_name,
    'league_result_deadline_batch', aggregate_key, request_hash,
    jsonb_array_length(results), sequence_value, metadata, response, confirmed_at
  );
  return response;
end;
$$;

revoke all on function public.process_pachanga_league_result_deadlines_v1(
  uuid, timestamptz, integer, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.process_pachanga_league_result_deadlines_v1(
  uuid, timestamptz, integer, jsonb
) to service_role;

comment on function public.process_pachanga_league_result_deadlines_v1(
  uuid, timestamptz, integer, jsonb
) is
  'Service-only idempotent R4C deadline processor. It is intentionally not scheduled by this release.';

revoke insert, update, delete on table public.pachanga_match_participants
  from public, anon, authenticated;

do $$
declare target_table regclass;
begin
  foreach target_table in array array[
    'public.pachanga_competition_match_squads'::regclass,
    'public.pachanga_competition_match_squad_revisions'::regclass,
    'public.pachanga_competition_match_squad_members'::regclass,
    'public.pachanga_competition_match_sheets'::regclass,
    'public.pachanga_competition_sporting_results'::regclass,
    'public.pachanga_competition_sporting_result_revisions'::regclass,
    'public.pachanga_competition_sporting_result_scorers'::regclass,
    'public.pachanga_competition_result_responses'::regclass,
    'public.pachanga_competition_official_result_decisions'::regclass,
    'public.pachanga_competition_standing_states'::regclass,
    'public.pachanga_competition_standing_snapshots'::regclass,
    'public.pachanga_competition_standing_rows'::regclass,
    'public.pachanga_competition_tie_break_explanations'::regclass,
    'public.pachanga_competition_persisted_draw_lots'::regclass,
    'public.pachanga_competition_standing_rebuild_receipts'::regclass
  ] loop
    execute format('revoke insert, update, delete on table %s from public, anon, authenticated', target_table);
  end loop;
end;
$$;
