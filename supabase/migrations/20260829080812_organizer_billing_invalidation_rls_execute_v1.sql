-- Organizer billing invalidations are read-only Realtime signals. PostgreSQL
-- evaluates their RLS policy as the subscriber, so the subscriber roles need
-- EXECUTE on this single security-definer predicate. Underlying billing tables
-- and every mutation helper remain private and service-only.

set lock_timeout = '5s';
set statement_timeout = '5min';

revoke all on function private.pachanga_billing_invalidation_can_read_v1(text, uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.pachanga_billing_invalidation_can_read_v1(text, uuid, uuid)
  to anon, authenticated;

comment on function private.pachanga_billing_invalidation_can_read_v1(text, uuid, uuid) is
  'RLS-only predicate for billing invalidations. Executable by anon/authenticated so Realtime can evaluate subscriber policies; it grants no mutation authority.';
