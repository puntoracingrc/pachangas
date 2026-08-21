-- Preserve the Ranking Productization capability added before Competition R1.
-- The six original R1 migrations are immutable because staging already ran them.

create or replace function private.pachanga_platform_capabilities_v1(target_role text)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select case target_role
    when 'platform_owner' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend', 'roles.manage',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read', 'labs.read',
      'competitions.read', 'competitions.manage'
    )
    when 'platform_admin' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'users.suspend',
      'teams.read', 'matches.read', 'challenges.read', 'moderation.read', 'moderation.write',
      'rankings.read', 'rankings.write', 'rewards.read', 'notifications.read', 'notifications.send',
      'billing.read', 'system.read', 'flags.read', 'flags.write', 'audit.read',
      'competitions.read', 'competitions.manage'
    )
    when 'moderator' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'teams.read', 'matches.read',
      'challenges.read', 'moderation.read', 'moderation.write', 'audit.read'
    )
    when 'support' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'matches.read',
      'challenges.read', 'notifications.read'
    )
    when 'finance' then jsonb_build_array(
      'overview.read', 'search.read', 'users.read', 'users.pii.read', 'teams.read', 'billing.read', 'audit.read'
    )
    when 'ops' then jsonb_build_array(
      'overview.read', 'system.read', 'flags.read', 'audit.read'
    )
    else '[]'::jsonb
  end;
$$;

revoke all on function private.pachanga_platform_capabilities_v1(text)
  from public, anon, authenticated;

comment on function private.pachanga_platform_capabilities_v1(text) is
  'Platform capability matrix preserving Ranking Productization while adding Competition R1 access.';
