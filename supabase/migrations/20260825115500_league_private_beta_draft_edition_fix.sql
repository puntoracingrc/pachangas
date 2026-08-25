-- LPB-017: finalizing the private-beta wizard must not open registration.
-- Registration is a separate canonical R4A transition with its own revision.

create or replace function private.pachanga_league_private_beta_enforce_draft_edition_v1()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.status = 'registration_open' and exists (
    select 1
    from public.pachanga_competitions competitions
    where competitions.id = new.competition_id
      and competitions.product_key = 'LEAGUE_PRIVATE_BETA_V1'
  ) then
    new.status := 'draft';
    new.registration_opens_at := null;
  end if;
  return new;
end;
$$;

revoke all on function private.pachanga_league_private_beta_enforce_draft_edition_v1()
  from public, anon, authenticated;

drop trigger if exists pachanga_league_private_beta_draft_edition_v1
  on public.pachanga_competition_editions;
create trigger pachanga_league_private_beta_draft_edition_v1
before insert on public.pachanga_competition_editions
for each row execute function private.pachanga_league_private_beta_enforce_draft_edition_v1();

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
declare normalized_kind text := nullif(upper(trim(coalesce(target_organizer_kind, ''))), '');
declare canonical_snapshot jsonb := coalesce(target_snapshot, '{}'::jsonb);
declare canonical_event_payload jsonb := coalesce(target_event_payload, '{}'::jsonb);
declare response jsonb;
begin
  if target_action = 'wizard.finalize' then
    canonical_snapshot := jsonb_set(
      canonical_snapshot,
      '{nextAction}',
      to_jsonb('open_registration'::text),
      true
    );
    canonical_snapshot := jsonb_set(
      canonical_snapshot,
      '{canonical,editionStatus}',
      to_jsonb('draft'::text),
      true
    );
    canonical_event_payload := jsonb_set(
      canonical_event_payload,
      '{editionStatus}',
      to_jsonb('draft'::text),
      true
    );
  end if;

  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', target_confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', canonical_snapshot,
    'invalidations', case when normalized_kind is null then '[]'::jsonb else jsonb_build_array(
      jsonb_build_object(
        'entityType', target_aggregate_type,
        'entityId', target_aggregate_id,
        'revision', target_confirmed_revision
      )
    ) end
  );

  insert into private.pachanga_league_private_beta_events(
    operation_id, actor_id, action, aggregate_type, aggregate_id,
    organizer_kind, organizer_group_id, organizer_club_id, competition_id,
    aggregate_revision, server_sequence, reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_action, target_aggregate_type,
    target_aggregate_id, normalized_kind,
    case when normalized_kind = 'TEAM' then target_organizer_id else null end,
    case when normalized_kind = 'CLUB' then target_organizer_id else null end,
    target_competition_id, target_confirmed_revision, target_server_sequence,
    left(coalesce(nullif(trim(target_reason_code), ''), target_action), 120),
    canonical_event_payload, target_confirmed_at
  );

  if normalized_kind is not null then
    insert into public.pachanga_league_private_beta_invalidations(
      server_sequence, wizard_id, competition_id, organizer_kind,
      organizer_group_id, organizer_club_id, target_user_id,
      entity_type, entity_id, revision, created_at
    ) values (
      target_server_sequence, target_wizard_id, target_competition_id,
      normalized_kind,
      case when normalized_kind = 'TEAM' then target_organizer_id else null end,
      case when normalized_kind = 'CLUB' then target_organizer_id else null end,
      target_actor_id, target_aggregate_type, target_aggregate_id,
      target_confirmed_revision, target_confirmed_at
    );
  end if;

  insert into private.pachanga_league_private_beta_operation_receipts(
    operation_id, actor_id, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    target_operation_id, target_actor_id, target_action, target_aggregate_type,
    target_aggregate_id, target_request_hash, target_confirmed_revision,
    target_server_sequence,
    private.pachanga_competition_client_metadata_v1(coalesce(target_client_metadata, '{}'::jsonb)),
    response, target_confirmed_at
  );
  return response;
end;
$$;

comment on function private.pachanga_league_private_beta_enforce_draft_edition_v1() is
  'Keeps new League Private Beta editions in draft until registration.open confirms the separate transition.';
