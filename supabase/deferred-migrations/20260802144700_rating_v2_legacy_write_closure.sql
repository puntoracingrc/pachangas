-- Pachangas IQ rating system V2: deferred activation.
--
-- Do not place this file in supabase/migrations until the V2 frontend is live
-- and verified. See docs/rating-system-v2-deployment-runbook.md.

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

revoke update on table public.pachanga_groups from authenticated;
