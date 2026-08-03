-- Pachangas IQ rating system V2: deterministic canonical reads.

create index if not exists pachanga_individual_rating_emitted_order_idx
  on public.pachanga_individual_rating_evidence(
    evaluator_profile_id,
    target_profile_id,
    opinion_created_at desc,
    created_at desc,
    id desc
  );

create index if not exists pachanga_player_rating_snapshots_canonical_idx
  on public.pachanga_player_rating_snapshots(player_profile_id, created_at desc, id desc);

create index if not exists pachanga_rating_state_events_canonical_idx
  on public.pachanga_rating_evidence_state_events(evidence_id, created_at desc, id desc);

create index if not exists pachanga_operation_receipts_canonical_idx
  on public.pachanga_operation_receipts(user_id, created_at desc, id desc)
  where user_id is not null;

create index if not exists pachanga_group_events_canonical_idx
  on public.pachanga_group_events(group_id, server_sequence desc)
  where server_sequence is not null;

create or replace function public.get_latest_pachanga_player_rating_snapshot_v2(
  target_profile_id uuid
)
returns jsonb
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  profile_user_id uuid;
  result jsonb;
begin
  if current_user_id is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered user required';
  end if;

  select profiles.user_id
  into profile_user_id
  from public.pachanga_player_profiles profiles
  where profiles.id = target_profile_id;

  if profile_user_id is null then
    raise exception 'Player profile not found';
  end if;
  if profile_user_id <> current_user_id then
    raise exception 'Only the player can read the canonical snapshot';
  end if;

  select jsonb_build_object(
    'id', snapshots.id,
    'playerProfileId', snapshots.player_profile_id,
    'groupId', snapshots.group_id,
    'matchId', snapshots.match_id,
    'snapshotKind', snapshots.snapshot_kind,
    'baseFacets', snapshots.base_facets,
    'calibratedFacets', snapshots.calibrated_facets,
    'currentFacets', snapshots.current_facets,
    'currentFacetModifiers', snapshots.current_facet_modifiers,
    'baseOverall', snapshots.base_overall,
    'calibratedOverall', snapshots.calibrated_overall,
    'currentOverall', snapshots.current_overall,
    'reliability', snapshots.reliability,
    'evaluatorCount', snapshots.evaluator_count,
    'activeEvidenceIds', snapshots.active_evidence_ids,
    'engineVersion', snapshots.engine_version,
    'createdAt', snapshots.created_at
  )
  into result
  from public.pachanga_player_rating_snapshots snapshots
  where snapshots.player_profile_id = target_profile_id
  order by snapshots.created_at desc, snapshots.id desc
  limit 1;

  return result;
end;
$$;

revoke all on function public.get_latest_pachanga_player_rating_snapshot_v2(uuid)
  from public, anon;
grant execute on function public.get_latest_pachanga_player_rating_snapshot_v2(uuid)
  to authenticated;

-- A second device must fail quickly and reload the canonical revision instead
-- of waiting behind a row lock until the HTTP gateway times out.
alter function public.create_pachanga_guest_identity_authoritative_v2(uuid, text, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.ensure_pachanga_external_team_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.finalize_pachanga_match_authoritative_v2(uuid, text, integer, integer, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.issue_pachanga_guest_rating_token_authoritative_v2(uuid, text, uuid, uuid, bigint, integer, jsonb) set lock_timeout = '750ms';
alter function public.link_pachanga_guest_identity_authoritative_v2(uuid, uuid, uuid, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.link_pachanga_registered_opponent_authoritative_v2(uuid, text, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.patch_pachanga_match_lineup_authoritative_v2(uuid, text, boolean, text[], text[], text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.patch_pachanga_match_player_paid_authoritative_v2(uuid, text, text, boolean, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.patch_pachanga_match_player_status_authoritative_v2(uuid, text, text, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.patch_pachanga_match_scorers_authoritative_v2(uuid, text, integer, integer, jsonb, text[], text[], uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.patch_pachanga_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.persist_pachanga_player_assessment_authoritative_v2(uuid, uuid, text, text, jsonb, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.record_pachanga_global_rating_authoritative_v2(uuid, text, text, text, uuid, uuid, uuid, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.record_pachanga_guest_team_rating_token_v2(text, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.record_pachanga_individual_rating_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.request_pachanga_open_match_authoritative_v2(uuid, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.reverse_pachanga_guest_link_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.review_pachanga_open_match_request_authoritative_v2(uuid, uuid, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.revoke_pachanga_guest_rating_token_authoritative_v2(uuid, uuid, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.save_pachanga_payload_authoritative_v2(uuid, bigint, jsonb, uuid, jsonb) set lock_timeout = '750ms';
alter function public.set_pachanga_group_ratings_enabled_authoritative_v2(uuid, boolean, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.sync_pachanga_market_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.sync_pachanga_open_match_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.upsert_pachanga_own_player_profile_authoritative_v2(uuid, text, jsonb, uuid, bigint, jsonb) set lock_timeout = '750ms';
alter function public.void_my_pachanga_individual_rating_v2(uuid, text, uuid, bigint, jsonb) set lock_timeout = '750ms';
