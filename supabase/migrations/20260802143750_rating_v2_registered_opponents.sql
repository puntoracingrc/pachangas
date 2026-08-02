-- Pachangas IQ rating system V2: explicit server-side binding for registered rivals.

create table if not exists public.pachanga_registered_match_opponents (
  host_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  match_id text not null,
  opponent_group_id uuid not null references public.pachanga_groups(id) on delete restrict,
  linked_by uuid not null references auth.users(id) on delete restrict,
  operation_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (host_group_id, match_id),
  unique (host_group_id, operation_id),
  check (host_group_id <> opponent_group_id)
);

alter table public.pachanga_registered_match_opponents enable row level security;
revoke all on table public.pachanga_registered_match_opponents from public, anon, authenticated;
grant all on table public.pachanga_registered_match_opponents to service_role;

create or replace function public.link_pachanga_registered_opponent_authoritative_v2(
  target_group_id uuid,
  target_match_id text,
  opponent_team_code text,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_group public.pachanga_groups%rowtype;
  opponent_group public.pachanga_groups%rowtype;
  replay jsonb;
begin
  if auth.uid() is null or operation_id is null or expected_revision is null then
    raise exception 'Authentication, operation id and expected revision required';
  end if;
  replay := public.pachanga_operation_replay_v2(target_group_id, operation_id, auth.uid());
  if replay is not null then return replay; end if;
  select * into current_group
  from public.pachanga_groups groups
  where groups.id = target_group_id
  for update;
  if not found then raise exception 'Group not found'; end if;
  if not public.is_pachanga_group_admin(target_group_id) then
    raise exception 'Only group admins can link a registered rival';
  end if;
  if current_group.payload_revision <> expected_revision then
    raise exception 'Server revision is newer. Reload the confirmed state.' using errcode = '40001';
  end if;
  if not current_group.ratings_enabled then raise exception 'Ratings are disabled for this group'; end if;
  if not exists (
    select 1 from public.pachanga_match_rating_snapshots snapshots
    where snapshots.group_id = target_group_id
      and snapshots.match_id = target_match_id
      and snapshots.state = 'active'
  ) then raise exception 'A finalized match snapshot is required'; end if;

  select * into opponent_group
  from public.pachanga_groups groups
  where upper(groups.team_code) = upper(trim(opponent_team_code))
    and groups.id <> target_group_id
    and groups.ratings_enabled
  limit 1;
  if not found then raise exception 'Registered rival not found or ratings unavailable'; end if;

  insert into public.pachanga_registered_match_opponents(
    host_group_id, match_id, opponent_group_id, linked_by, operation_id
  ) values (
    target_group_id, target_match_id, opponent_group.id, auth.uid(), operation_id
  )
  on conflict (host_group_id, match_id) do update set
    opponent_group_id = excluded.opponent_group_id,
    linked_by = excluded.linked_by,
    operation_id = excluded.operation_id,
    updated_at = clock_timestamp();

  update public.pachanga_groups set updated_at = clock_timestamp() where id = target_group_id;
  insert into public.pachanga_group_events(
    group_id, match_id, operation_id, actor_id, event_type, admin_action, payload
  ) values (
    target_group_id, target_match_id, operation_id, null,
    'registered_opponent_linked_v2', true,
    jsonb_build_object('opponentGroupId', opponent_group.id)
  );
  return public.pachanga_authoritative_response_v2(
    target_group_id, operation_id, 'registered_opponent_linked_v2', expected_revision,
    jsonb_build_object(
      'opponent', jsonb_build_object(
        'groupId', opponent_group.id,
        'name', opponent_group.name,
        'teamCode', opponent_group.team_code,
        'externallyCalibratedLevel', opponent_group.externally_calibrated_level
      )
    ),
    client_metadata
  );
end;
$$;

revoke all on function public.link_pachanga_registered_opponent_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.link_pachanga_registered_opponent_authoritative_v2(uuid, text, text, uuid, bigint, jsonb)
  to authenticated;
