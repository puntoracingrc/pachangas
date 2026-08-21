-- Supabase Realtime evaluates table policies as the authenticated subscriber.
-- The policy helper stays in the unexposed private schema and remains unavailable
-- to anon, but authenticated needs EXECUTE for WAL rows to pass through RLS.

revoke all on function private.pachanga_competition_can_read_invalidation_v1(uuid, uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.pachanga_competition_can_read_invalidation_v1(uuid, uuid, uuid)
  to authenticated;

comment on function private.pachanga_competition_can_read_invalidation_v1(uuid, uuid, uuid) is
  'RLS helper for competition invalidations. Executable by authenticated so Realtime can apply subscriber policies.';
