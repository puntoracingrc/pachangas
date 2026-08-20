-- Ranking Productization V1 R6
--
-- R4 wrapped the existing platform-flag RPCs so Ranking Productization could
-- share the canonical flag surface. PostgreSQL preserves EXECUTE grants when
-- a function is renamed, so the pre-ranking implementations remained directly
-- callable by authenticated clients. The wrappers are now the only API surface.

set lock_timeout = '5s';
set statement_timeout = '5min';

revoke all on function public.get_pachanga_platform_flags_pre_ranking_v1()
  from public, anon, authenticated, service_role;
revoke all on function public.set_pachanga_platform_flag_pre_ranking_v1(
  text, boolean, bigint, uuid, text
) from public, anon, authenticated, service_role;

do $migration$
begin
  if has_function_privilege(
    'authenticated',
    'public.get_pachanga_platform_flags_pre_ranking_v1()',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticated',
    'public.set_pachanga_platform_flag_pre_ranking_v1(text,boolean,bigint,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'Legacy pre-ranking platform flag RPCs remain executable';
  end if;
end;
$migration$;

reset lock_timeout;
reset statement_timeout;
