-- R4A compatibility closure: R1 rule publication must honor the R2 Club organizer adapter.
-- This is forward-only because the first three R4A units were already exercised in staging.

set lock_timeout = '5s';
set statement_timeout = '120s';

do $$
declare
  function_signature constant regprocedure :=
    'public.command_pachanga_competition_foundation_v1(uuid,uuid,bigint,text,jsonb,jsonb)'::regprocedure;
  previous_check constant text := $check$if not private.pachanga_competition_active_entitlement_v1(
      competition_row.organizer_group_id, 'competition_create'
    ) then$check$;
  organizer_aware_check constant text := $check$if not private.pachanga_competition_active_entitlement_v2(
      competition_row.organizer_kind,
      coalesce(competition_row.organizer_group_id, competition_row.organizer_club_id),
      'competition_create'
    ) then$check$;
  command_definition text;
  occurrence_count integer;
begin
  select pg_get_functiondef(function_signature) into command_definition;
  occurrence_count := (
    length(command_definition) - length(replace(command_definition, previous_check, ''))
  ) / length(previous_check);
  if occurrence_count <> 1 then
    raise exception 'CLUB_RULE_ENTITLEMENT_PATCH_BASE_MISMATCH'
      using errcode = '55000';
  end if;

  command_definition := replace(command_definition, previous_check, organizer_aware_check);
  execute command_definition;
end;
$$;

comment on function public.command_pachanga_competition_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is
  'R1 Competition command with R2 organizer-aware entitlement validation for rule publication.';
