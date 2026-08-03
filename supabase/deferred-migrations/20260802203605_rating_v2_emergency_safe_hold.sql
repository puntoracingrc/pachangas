-- Pachangas IQ rating system V2: deferred emergency continuity guard.
--
-- Keep this file outside supabase/migrations. It is not migration 26 and must
-- never be included in a normal db push. Apply it only after rehearsal in
-- staging, incident approval, and verification of the exact project ref.
--
-- This safe-hold deliberately does not restore any V1 write RPC or direct
-- UPDATE on pachanga_groups. A temporary maintenance frontend may continue
-- attendance through the V2 authoritative RPC while the team rolls forward.

set lock_timeout = '3s';
set statement_timeout = '30s';

revoke update on table public.pachanga_groups from public, anon, authenticated;

revoke execute on function public.save_pachanga_payload_if_current(uuid, bigint, jsonb)
  from public, anon, authenticated;
revoke execute on function public.patch_pachanga_match_player_status(uuid, text, text, text, uuid)
  from public, anon, authenticated;
revoke execute on function public.patch_pachanga_match_lineup_state(uuid, text, boolean, text[], text[], text, uuid)
  from public, anon, authenticated;
revoke execute on function public.patch_pachanga_match_player_paid(uuid, text, text, boolean, uuid)
  from public, anon, authenticated;
revoke execute on function public.patch_pachanga_match_scorers(uuid, text, integer, integer, jsonb, text[], text[], uuid)
  from public, anon, authenticated;
revoke execute on function public.finalize_pachanga_match_if_current(uuid, bigint, text, jsonb, uuid)
  from public, anon, authenticated;
revoke execute on function public.sync_pachanga_market_profile(uuid, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.sync_pachanga_open_match(uuid, text, jsonb, uuid)
  from public, anon, authenticated;
revoke execute on function public.review_pachanga_open_match_request(uuid, text, uuid)
  from public, anon, authenticated;
revoke execute on function public.request_pachanga_open_match(uuid, uuid)
  from public, anon, authenticated;

revoke execute on function public.patch_pachanga_match_player_status_authoritative_v2(
  uuid,
  text,
  text,
  text,
  uuid,
  bigint,
  jsonb
) from public, anon;
grant execute on function public.patch_pachanga_match_player_status_authoritative_v2(
  uuid,
  text,
  text,
  text,
  uuid,
  bigint,
  jsonb
) to authenticated;
