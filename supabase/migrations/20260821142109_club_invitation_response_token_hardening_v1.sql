-- Forward-only hardening for the one-time Club invitation token.
-- The core command needs the submitted token to accept/decline an invitation,
-- but only membership.invite may return a token to a client.

alter function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) rename to command_pachanga_club_foundation_v1_internal_r2;

revoke all on function public.command_pachanga_club_foundation_v1_internal_r2(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;

create function public.command_pachanga_club_foundation_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  command_action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  response jsonb;
begin
  response := public.command_pachanga_club_foundation_v1_internal_r2(
    operation_id,
    aggregate_id,
    expected_revision,
    command_action,
    coalesce(command_payload, '{}'::jsonb),
    coalesce(client_metadata, '{}'::jsonb)
  );

  if command_action = 'membership.invite' then
    return response;
  end if;

  return response
    - 'oneTimeToken'
    - 'invitationId'
    - 'tokenReturnedOnce';
end;
$$;

revoke all on function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated;

comment on function public.command_pachanga_club_foundation_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) is
  'Authoritative Club command. One-time invitation tokens are returned only by membership.invite.';

comment on function public.command_pachanga_club_foundation_v1_internal_r2(
  uuid, uuid, bigint, text, jsonb, jsonb
) is
  'Internal R2 Club command implementation. Direct client execution is revoked.';
