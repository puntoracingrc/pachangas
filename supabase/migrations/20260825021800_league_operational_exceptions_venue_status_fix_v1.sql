-- R4D corrective hardening: R4B label-only venues are operationally LABEL,
-- even though the scheduling layer keeps them as TBD until a saved venue exists.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_league_operational_create_fixture_change_v1(
  target_context_id uuid,
  target_change_type text,
  target_context_status text,
  target_scheduled_start timestamptz,
  target_scheduled_end timestamptz,
  target_timezone text,
  target_venue_id uuid,
  target_venue_label text,
  target_venue_status text,
  target_resource_key text,
  target_reason_code text,
  target_public_summary text,
  target_source_type text,
  target_source_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint,
  target_policy jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare item_row public.pachanga_competition_schedule_items%rowtype;
declare change_row public.pachanga_competition_fixture_changes%rowtype;
declare revision_row public.pachanga_competition_fixture_change_revisions%rowtype;
declare revision_id uuid := gen_random_uuid();
declare revision_version integer;
declare normalized_change_type text := upper(trim(coalesce(target_change_type, '')));
declare normalized_venue_status text := upper(trim(coalesce(target_venue_status, 'TBD')));
declare soft_impact jsonb := '{}'::jsonb;
declare venue_policy jsonb := target_policy -> 'venuePolicy';
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  select * into item_row
  from public.pachanga_competition_schedule_items items
  where items.id = context_row.schedule_item_id and items.status = 'published';
  if not found then raise exception 'R4D_PUBLISHED_FIXTURE_REQUIRED' using errcode = '22023'; end if;
  if normalized_change_type not in (
    'RESCHEDULE', 'TIME_CHANGE', 'VENUE_CHANGE', 'POSTPONEMENT',
    'CANCELLATION', 'RESUMPTION', 'REPLAY'
  ) then raise exception 'R4D_FIXTURE_CHANGE_TYPE_INVALID' using errcode = '22023'; end if;

  -- Direct rescheduling inherits the canonical R4B venue. R4B deliberately
  -- represents label-only slots as TBD, while R4D distinguishes LABEL from
  -- a genuinely unknown venue. Normalize that inherited state server-side.
  if normalized_change_type = 'RESCHEDULE' then
    normalized_venue_status := case
      when target_venue_id is not null then 'SAVED'
      when nullif(trim(coalesce(target_venue_label, '')), '') is not null then 'LABEL'
      else 'TBD'
    end;
  end if;

  if normalized_venue_status not in ('SAVED', 'LABEL', 'TBD') then
    raise exception 'R4D_VENUE_STATUS_INVALID' using errcode = '22023';
  end if;
  if normalized_venue_status = 'SAVED' and not coalesce((venue_policy ->> 'allowSavedVenue')::boolean, false)
     or normalized_venue_status = 'LABEL' and not coalesce((venue_policy ->> 'allowVenueLabel')::boolean, false)
     or normalized_venue_status = 'TBD' and not coalesce((venue_policy ->> 'allowTbd')::boolean, false) then
    raise exception 'R4D_VENUE_POLICY_FORBIDS_SELECTION' using errcode = '22023';
  end if;
  if normalized_venue_status = 'SAVED' and target_venue_id is null
     or normalized_venue_status = 'LABEL' and nullif(trim(coalesce(target_venue_label, '')), '') is null
     or normalized_venue_status = 'TBD' and (target_venue_id is not null or target_venue_label is not null) then
    raise exception 'R4D_VENUE_SELECTION_INVALID' using errcode = '22023';
  end if;
  if normalized_change_type in ('RESCHEDULE', 'TIME_CHANGE', 'RESUMPTION', 'REPLAY') then
    soft_impact := private.pachanga_league_operational_validate_fixture_v1(
      context_row.id, target_scheduled_start, target_scheduled_end,
      target_timezone, target_resource_key, target_policy
    );
  elsif normalized_change_type = 'VENUE_CHANGE'
        and context_row.scheduled_start is not null and context_row.scheduled_end is not null then
    soft_impact := private.pachanga_league_operational_validate_fixture_v1(
      context_row.id, context_row.scheduled_start, context_row.scheduled_end,
      context_row.timezone, target_resource_key, target_policy
    );
  end if;

  select * into change_row
  from public.pachanga_competition_fixture_changes changes
  where changes.competition_match_context_id = context_row.id
    and changes.status = 'active'
  for update;
  if found then
    revision_version := change_row.revision::integer + 1;
    update public.pachanga_competition_fixture_changes changes set
      change_type = normalized_change_type,
      source_type = target_source_type,
      source_id = target_source_id,
      revision = changes.revision + 1,
      server_sequence = target_server_sequence,
      updated_at = clock_timestamp()
    where changes.id = change_row.id
    returning * into change_row;
  else
    revision_version := 1;
    insert into public.pachanga_competition_fixture_changes(
      competition_id, canonical_match_id, competition_match_context_id,
      schedule_item_id, rule_revision_id, change_type, status, source_type,
      source_id, original_scheduled_start, original_scheduled_end,
      original_timezone, original_venue_id, original_venue_label,
      original_venue_status, creation_operation_id, revision,
      server_sequence, created_by
    ) values (
      context_row.competition_id, context_row.canonical_match_id, context_row.id,
      context_row.schedule_item_id, context_row.rule_revision_id,
      normalized_change_type, 'active', target_source_type, target_source_id,
      item_row.scheduled_start, item_row.scheduled_end, item_row.timezone,
      item_row.venue_id, item_row.venue_label,
      case when item_row.venue_status = 'CONFIRMED' and item_row.venue_id is null
        then 'LABEL' else item_row.venue_status end,
      target_operation_id, 1, target_server_sequence, target_actor_id
    ) returning * into change_row;
  end if;

  insert into public.pachanga_competition_fixture_change_revisions(
    id, fixture_change_id, version, previous_revision_id, change_type,
    effective_scheduled_start, effective_scheduled_end, effective_timezone,
    effective_venue_id, effective_venue_label, effective_venue_status,
    effective_resource_key, public_reason_code, public_summary,
    soft_constraint_impact, operation_id, created_by, server_sequence
  ) values (
    revision_id, change_row.id, revision_version, change_row.current_revision_id,
    normalized_change_type, target_scheduled_start, target_scheduled_end,
    target_timezone, target_venue_id, target_venue_label, normalized_venue_status,
    nullif(left(trim(coalesce(target_resource_key, '')), 160), ''),
    left(trim(target_reason_code), 120), left(coalesce(target_public_summary, ''), 500),
    soft_impact, target_operation_id, target_actor_id, target_server_sequence
  ) returning * into revision_row;
  update public.pachanga_competition_fixture_changes changes set
    current_revision_id = revision_id,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where changes.id = change_row.id;

  update public.pachanga_competition_match_contexts contexts set
    scheduled_start = coalesce(target_scheduled_start, contexts.scheduled_start),
    scheduled_end = coalesce(target_scheduled_end, contexts.scheduled_end),
    timezone = coalesce(target_timezone, contexts.timezone),
    venue_id = case when target_venue_status is null then contexts.venue_id else target_venue_id end,
    venue_label = case when target_venue_status is null then contexts.venue_label else target_venue_label end,
    venue_status = case normalized_venue_status
      when 'SAVED' then 'CONFIRMED' when 'LABEL' then 'LABEL' else 'TBD' end,
    status = target_context_status,
    revision = contexts.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where contexts.id = context_row.id
  returning * into context_row;
  return jsonb_build_object(
    'fixtureChangeId', change_row.id,
    'fixtureChangeRevisionId', revision_id,
    'changeType', normalized_change_type,
    'contextStatus', context_row.status,
    'contextRevision', context_row.revision,
    'softConstraintImpact', soft_impact
  );
end;
$$;

revoke all on function private.pachanga_league_operational_create_fixture_change_v1(
  uuid, text, text, timestamptz, timestamptz, text, uuid, text, text, text,
  text, text, text, uuid, uuid, uuid, bigint, jsonb
) from public, anon, authenticated;
