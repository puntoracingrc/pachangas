-- Pachangas IQ R4D: immutable history, scoped notifications and safety guards.

set lock_timeout = '5s';
set statement_timeout = '120s';

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
        or kind like 'match_%' or kind like 'league_round_%'
        or kind like 'league_postponement_%' or kind like 'league_fixture_%'
        or kind like 'league_venue_%' or kind like 'league_late_arrival_%'
        or kind like 'league_no_show_%' or kind like 'league_match_suspension%'
        or kind like 'league_match_resum%' or kind like 'league_match_replay%'
        or kind like 'league_administrative_decision%' then 'match'
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' then 'security'
      else 'group'
    end,
    'priority', case
      when kind like '%security%' or kind like '%sanction%'
        or kind like '%warning%' or kind like '%challenge%'
        or kind like '%external_result%' or kind like '%invitation%'
        or kind like '%open_match_request%' or kind like '%withdrawal%'
        or kind like 'match_result_%' or kind like 'league_postponement_%'
        or kind like 'league_fixture_%' or kind like 'league_venue_%'
        or kind like 'league_late_arrival_%' or kind like 'league_no_show_%'
        or kind like 'league_match_suspension%'
        or kind like 'league_match_resum%' or kind like 'league_match_replay%'
        or kind like 'league_administrative_decision%'
        or kind in (
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
      or kind like 'league_postponement_%' or kind like 'league_fixture_%'
      or kind like 'league_venue_%' or kind like 'league_late_arrival_%'
      or kind like 'league_no_show_%' or kind like 'league_match_suspension%'
      or kind like 'league_match_resum%' or kind like 'league_match_replay%'
      or kind like 'league_administrative_decision%'
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

create or replace function private.pachanga_league_operational_notify_entry_v1(
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
      and delegates.delegate_role = 'PRIMARY_DELEGATE'
      and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, target_kind, target_title, target_body,
      target_action_url,
      jsonb_strip_nulls(coalesce(target_payload, '{}'::jsonb)
        || jsonb_build_object('entryId', target_entry_id)),
      'r4d:' || target_operation_id::text || ':' || target_kind || ':' || recipient.user_id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_league_operational_notify_entry_v1(
  uuid, text, text, text, text, jsonb, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_notify_organizer_v1(
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
        'competition_operations_manager'
      )
  loop
    perform private.pachanga_notify_v1(
      recipient.user_id, target_kind, target_title, target_body,
      target_action_url,
      jsonb_strip_nulls(coalesce(target_payload, '{}'::jsonb)
        || jsonb_build_object('competitionId', target_competition_id)),
      'r4d:' || target_operation_id::text || ':' || target_kind || ':' || recipient.user_id::text
    );
  end loop;
end;
$$;

revoke all on function private.pachanga_league_operational_notify_organizer_v1(
  uuid, text, text, text, text, jsonb, uuid
) from public, anon, authenticated;

create or replace function private.pachanga_league_operational_event_notifications_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare request_row public.pachanga_competition_postponement_requests%rowtype;
declare late_row public.pachanga_competition_late_arrival_incidents%rowtype;
declare no_show_row public.pachanga_competition_no_show_incidents%rowtype;
declare suspension_row public.pachanga_competition_match_suspensions%rowtype;
declare action_url text;
declare payload jsonb;
declare target_kind text;
declare target_title text;
declare target_body text;
begin
  if new.aggregate_type <> 'league_operational_exceptions'
     or new.competition_id is null then return new; end if;
  select * into context_row
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = new.aggregate_id::uuid;
  if not found then return new; end if;
  action_url := '/competiciones/' || context_row.competition_id::text
    || '/partidos/' || context_row.canonical_match_id::text || '/operaciones';
  payload := jsonb_build_object(
    'operationId', new.operation_id,
    'action', new.action,
    'competitionId', context_row.competition_id,
    'matchContextId', context_row.id,
    'canonicalMatchId', context_row.canonical_match_id
  );

  if new.action = 'postponement.request' then
    select * into request_row
    from public.pachanga_competition_postponement_requests requests
    where requests.id = nullif(new.event_payload ->> 'requestId', '')::uuid;
    perform private.pachanga_league_operational_notify_entry_v1(
      request_row.responding_entry_id, 'league_postponement_received',
      'Solicitud de aplazamiento',
      'El rival ha propuesto un cambio para este partido.', action_url,
      payload || jsonb_build_object('requestId', request_row.id), new.operation_id
    );
  elsif new.action = 'postponement.respond' then
    select * into request_row
    from public.pachanga_competition_postponement_requests requests
    where requests.id = nullif(new.event_payload ->> 'requestId', '')::uuid;
    if request_row.status = 'approved' then
      target_kind := 'league_postponement_approved';
      target_title := 'Aplazamiento aprobado';
      target_body := 'La nueva programación del partido ya es oficial.';
      perform private.pachanga_league_operational_notify_entry_v1(
        request_row.requesting_entry_id, target_kind, target_title, target_body,
        action_url, payload || jsonb_build_object('requestId', request_row.id), new.operation_id
      );
      perform private.pachanga_league_operational_notify_entry_v1(
        request_row.responding_entry_id, target_kind, target_title, target_body,
        action_url, payload || jsonb_build_object('requestId', request_row.id), new.operation_id
      );
      perform private.pachanga_league_operational_notify_organizer_v1(
        context_row.competition_id, target_kind, target_title, target_body,
        action_url, payload || jsonb_build_object('requestId', request_row.id), new.operation_id
      );
    elsif request_row.status = 'denied' then
      perform private.pachanga_league_operational_notify_entry_v1(
        request_row.requesting_entry_id, 'league_postponement_rejected',
        'Aplazamiento rechazado', 'La fecha original continúa vigente.',
        action_url, payload || jsonb_build_object('requestId', request_row.id), new.operation_id
      );
    else
      perform private.pachanga_league_operational_notify_entry_v1(
        request_row.requesting_entry_id, 'league_postponement_response',
        'Respuesta al aplazamiento', 'El rival ha respondido a la solicitud.',
        action_url, payload || jsonb_build_object('requestId', request_row.id), new.operation_id
      );
      if request_row.team_response = 'ACCEPTED'
         or request_row.organizer_response = 'ESCALATED' then
        perform private.pachanga_league_operational_notify_organizer_v1(
          context_row.competition_id, 'league_postponement_response',
          'Aplazamiento pendiente de decisión',
          'La solicitud requiere revisión de la organización.', action_url,
          payload || jsonb_build_object('requestId', request_row.id), new.operation_id
        );
      end if;
    end if;
  elsif new.action in ('postponement.withdraw', 'postponement.expire') then
    select * into request_row
    from public.pachanga_competition_postponement_requests requests
    where requests.id = nullif(new.event_payload ->> 'requestId', '')::uuid;
    perform private.pachanga_league_operational_notify_entry_v1(
      request_row.responding_entry_id, 'league_postponement_response',
      case when new.action = 'postponement.withdraw'
        then 'Solicitud retirada' else 'Solicitud vencida' end,
      'La solicitud de aplazamiento ya no está pendiente.', action_url,
      payload || jsonb_build_object('requestId', request_row.id), new.operation_id
    );
    if request_row.organizer_response = 'ESCALATED' then
      perform private.pachanga_league_operational_notify_organizer_v1(
        context_row.competition_id, 'league_postponement_response',
        'Deadline de aplazamiento vencido',
        'La solicitud necesita una decisión de la organización.', action_url,
        payload || jsonb_build_object('requestId', request_row.id), new.operation_id
      );
    end if;
  elsif new.action in ('fixture.reschedule', 'fixture.change_venue', 'fixture.cancel') then
    target_kind := case new.action
      when 'fixture.reschedule' then 'league_fixture_rescheduled'
      when 'fixture.change_venue' then 'league_venue_changed'
      else 'league_fixture_cancelled' end;
    target_title := case new.action
      when 'fixture.reschedule' then 'Nueva fecha de partido'
      when 'fixture.change_venue' then 'Cambio de campo'
      else 'Partido cancelado' end;
    target_body := 'La autoridad de la competición ha actualizado el partido.';
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.home_entry_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.away_entry_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
  elsif new.action like 'late_arrival.%' then
    select * into late_row
    from public.pachanga_competition_late_arrival_incidents incidents
    where incidents.id = coalesce(
      nullif(new.event_payload ->> 'incidentId', '')::uuid,
      nullif(new.event_payload ->> 'lateArrivalIncidentId', '')::uuid
    );
    perform private.pachanga_league_operational_notify_entry_v1(
      late_row.responsible_entry_id, 'league_late_arrival_reported',
      case when new.action = 'late_arrival.confirm_arrival'
        then 'Llegada registrada' else 'Retraso registrado' end,
      case when new.action = 'late_arrival.confirm_arrival'
        then 'La llegada del equipo ha quedado registrada.'
        else 'Se ha abierto una incidencia operativa por retraso.' end,
      action_url, payload, new.operation_id
    );
    if new.action <> 'late_arrival.confirm_arrival' then
      perform private.pachanga_league_operational_notify_organizer_v1(
        context_row.competition_id, 'league_late_arrival_reported',
        'Incidencia de retraso', 'Hay una incidencia operativa que revisar.',
        action_url, payload, new.operation_id
      );
    end if;
  elsif new.action like 'no_show.%' then
    select * into no_show_row
    from public.pachanga_competition_no_show_incidents incidents
    where incidents.id = coalesce(
      nullif(new.event_payload ->> 'incidentId', '')::uuid,
      nullif(new.event_payload ->> 'noShowIncidentId', '')::uuid
    );
    target_kind := 'league_no_show_review';
    target_title := case no_show_row.status
      when 'confirmed' then 'Incomparecencia confirmada'
      when 'rejected' then 'Incomparecencia descartada'
      else 'Incomparecencia en revisión' end;
    target_body := 'La autoridad ha actualizado la incidencia de este partido.';
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.home_entry_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.away_entry_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_operational_notify_organizer_v1(
      context_row.competition_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
  elsif new.action like 'suspension.%' then
    select * into suspension_row
    from public.pachanga_competition_match_suspensions suspensions
    where suspensions.id = nullif(new.event_payload ->> 'suspensionId', '')::uuid;
    target_kind := case new.action
      when 'suspension.schedule_resume' then 'league_match_resumption_scheduled'
      when 'suspension.resume' then 'league_match_resumed'
      when 'suspension.order_replay' then 'league_match_replay_ordered'
      else 'league_match_suspension' end;
    target_title := case new.action
      when 'suspension.schedule_resume' then 'Reanudación programada'
      when 'suspension.resume' then 'Partido reanudado'
      when 'suspension.order_replay' then 'Repetición ordenada'
      else 'Partido suspendido' end;
    target_body := 'La situación operativa del partido ha cambiado.';
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.home_entry_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.away_entry_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_operational_notify_organizer_v1(
      context_row.competition_id, target_kind, target_title, target_body,
      action_url, payload, new.operation_id
    );
  elsif new.action like 'administrative_decision.%' then
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.home_entry_id, 'league_administrative_decision',
      'Decisión administrativa',
      'La autoridad ha publicado una decisión sobre el partido.',
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_operational_notify_entry_v1(
      context_row.away_entry_id, 'league_administrative_decision',
      'Decisión administrativa',
      'La autoridad ha publicado una decisión sobre el partido.',
      action_url, payload, new.operation_id
    );
    perform private.pachanga_league_operational_notify_organizer_v1(
      context_row.competition_id, 'league_administrative_decision',
      'Decisión administrativa publicada',
      'La decisión y sus efectos tipados ya son efectivos.',
      action_url, payload, new.operation_id
    );
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_operational_event_notifications_v1()
  from public, anon, authenticated;

drop trigger if exists notify_pachanga_league_operational_event_v1
  on private.pachanga_competition_events;
create trigger notify_pachanga_league_operational_event_v1
after insert on private.pachanga_competition_events
for each row execute function private.pachanga_league_operational_event_notifications_v1();

create or replace function private.pachanga_league_operational_immutable_row_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'R4D_IMMUTABLE_HISTORY' using errcode = '55000';
end;
$$;

revoke all on function private.pachanga_league_operational_immutable_row_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_fixture_change_revision_v1
  on public.pachanga_competition_fixture_change_revisions;
create trigger guard_pachanga_fixture_change_revision_v1
before update or delete on public.pachanga_competition_fixture_change_revisions
for each row execute function private.pachanga_league_operational_immutable_row_v1();

drop trigger if exists guard_pachanga_postponement_response_v1
  on public.pachanga_competition_postponement_responses;
create trigger guard_pachanga_postponement_response_v1
before update or delete on public.pachanga_competition_postponement_responses
for each row execute function private.pachanga_league_operational_immutable_row_v1();

drop trigger if exists guard_pachanga_venue_condition_decision_v1
  on public.pachanga_competition_venue_condition_decisions;
create trigger guard_pachanga_venue_condition_decision_v1
before update or delete on public.pachanga_competition_venue_condition_decisions
for each row execute function private.pachanga_league_operational_immutable_row_v1();

drop trigger if exists guard_pachanga_administrative_effect_v1
  on public.pachanga_competition_administrative_effects;
create trigger guard_pachanga_administrative_effect_v1
before update or delete on public.pachanga_competition_administrative_effects
for each row execute function private.pachanga_league_operational_immutable_row_v1();

drop trigger if exists guard_pachanga_operational_evidence_v1
  on private.pachanga_competition_operational_evidence;
create trigger guard_pachanga_operational_evidence_v1
before update or delete on private.pachanga_competition_operational_evidence
for each row execute function private.pachanga_league_operational_immutable_row_v1();

create or replace function private.pachanga_league_resumption_decision_guard_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'R4D_RESUMPTION_DECISION_IMMUTABLE' using errcode = '55000';
  end if;
  if new.id is distinct from old.id
     or new.match_suspension_id is distinct from old.match_suspension_id
     or new.decision_type is distinct from old.decision_type
     or new.resume_minute is distinct from old.resume_minute
     or new.initial_score_home is distinct from old.initial_score_home
     or new.initial_score_away is distinct from old.initial_score_away
     or new.effective_scheduled_start is distinct from old.effective_scheduled_start
     or new.effective_scheduled_end is distinct from old.effective_scheduled_end
     or new.effective_timezone is distinct from old.effective_timezone
     or new.effective_venue_id is distinct from old.effective_venue_id
     or new.effective_venue_label is distinct from old.effective_venue_label
     or new.effective_venue_status is distinct from old.effective_venue_status
     or new.effective_resource_key is distinct from old.effective_resource_key
     or new.reuse_canonical_match is distinct from old.reuse_canonical_match
     or new.eligibility_policy_snapshot is distinct from old.eligibility_policy_snapshot
     or new.public_summary is distinct from old.public_summary
     or new.supersedes_decision_id is distinct from old.supersedes_decision_id
     or new.operation_id is distinct from old.operation_id
     or new.authority_role is distinct from old.authority_role
     or new.decided_by is distinct from old.decided_by
     or new.server_sequence is distinct from old.server_sequence
     or new.decided_at is distinct from old.decided_at
     or old.status <> 'published'
     or new.status not in ('superseded', 'annulled') then
    raise exception 'R4D_RESUMPTION_DECISION_IMMUTABLE' using errcode = '55000';
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_resumption_decision_guard_v1()
  from public, anon, authenticated;

drop trigger if exists guard_pachanga_resumption_decision_v1
  on public.pachanga_competition_match_resumption_decisions;
create trigger guard_pachanga_resumption_decision_v1
before update or delete on public.pachanga_competition_match_resumption_decisions
for each row execute function private.pachanga_league_resumption_decision_guard_v1();
