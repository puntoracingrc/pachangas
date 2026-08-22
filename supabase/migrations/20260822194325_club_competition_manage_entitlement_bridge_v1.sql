-- R4A compatibility closure: R2 Club platform grants must expose the
-- competition_manage entitlement required by League registration commands.

set lock_timeout = '5s';
set statement_timeout = '120s';

do $$
declare
  function_signature constant regprocedure :=
    'public.command_pachanga_club_platform_v1(uuid,uuid,bigint,text,jsonb,jsonb)'::regprocedure;
  create_only_check constant text := $check$if trim(coalesce(command_payload ->> 'capability', '')) <> 'competition_create' then
        raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
      end if;$check$;
  management_check constant text := $check$if trim(coalesce(command_payload ->> 'capability', '')) not in (
        'competition_create', 'competition_manage'
      ) then
        raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
      end if;$check$;
  create_only_revoke constant text := $check$and grants.capability = 'competition_create'
        and grants.status = 'active';$check$;
  capability_revoke constant text := $check$and grants.capability = trim(command_payload ->> 'capability')
        and grants.status = 'active';$check$;
  create_only_insert constant text :=
    $check$entitlement_id, 'CLUB', null, aggregate_id, 'competition_create',$check$;
  capability_insert constant text :=
    $check$entitlement_id, 'CLUB', null, aggregate_id, trim(command_payload ->> 'capability'),$check$;
  command_definition text;
begin
  select pg_get_functiondef(function_signature) into command_definition;
  if command_definition not like '%' || create_only_check || '%'
     or command_definition not like '%' || create_only_revoke || '%'
     or command_definition not like '%' || create_only_insert || '%' then
    raise exception 'CLUB_MANAGE_ENTITLEMENT_PATCH_BASE_MISMATCH'
      using errcode = '55000';
  end if;

  command_definition := replace(command_definition, create_only_check, management_check);
  command_definition := replace(command_definition, create_only_revoke, capability_revoke);
  command_definition := replace(command_definition, create_only_insert, capability_insert);
  execute command_definition;
end;
$$;

comment on function public.command_pachanga_club_platform_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is
  'R2 Club platform command with R4A competition_create and competition_manage entitlement grants.';
