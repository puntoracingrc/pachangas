-- Preserve immutable rating evidence while allowing the declared Auth cascade.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_player_assessment_self_evidence_immutable_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if tg_op = 'DELETE'
    and pg_catalog.pg_trigger_depth() > 1
    and old.user_id is not null
    and not exists (
      select 1
      from auth.users users
      where users.id = old.user_id
    ) then
    return old;
  end if;

  raise exception 'PLAYER_ASSESSMENT_EVIDENCE_IMMUTABLE' using errcode = '55000';
end;
$$;

revoke all on function private.pachanga_player_assessment_self_evidence_immutable_v1()
  from public, anon, authenticated, service_role;
