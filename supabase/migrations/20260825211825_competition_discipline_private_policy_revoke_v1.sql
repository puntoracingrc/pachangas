-- Close the only inherited PUBLIC execute grant left on the private R5 policy
-- helper. The private schema already denies client USAGE; this adds the
-- required defense-in-depth boundary without changing policy data or flags.

set lock_timeout = '3s';
set statement_timeout = '30s';

revoke all on function private.pachanga_competition_discipline_default_policy_v1()
from public, anon, authenticated;
