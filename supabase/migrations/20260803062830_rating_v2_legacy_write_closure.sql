-- Pachangas IQ rating system V2: final legacy write closure.
--
-- The V2 frontend and the 24 additive migrations must be live and verified
-- before this migration is applied.

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
