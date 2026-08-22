-- R4A authority closure: a team owner keeps team authority even when the same
-- user also holds an organizer role for the competition.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_league_entry_actor_scope_v1(
  target_entry_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_entry public.pachanga_competition_entries%rowtype;
declare selected_role text;
begin
  if target_actor_id is null then return null; end if;
  select * into selected_entry
  from public.pachanga_competition_entries entries
  where entries.id = target_entry_id;
  if not found then return null; end if;
  if exists (
    select 1 from public.pachanga_groups groups
    where groups.id = selected_entry.team_id and groups.owner_id = target_actor_id
  ) then return 'TEAM_OWNER'; end if;
  if private.pachanga_competition_can_v1(selected_entry.competition_id, target_actor_id, 'read') then
    return 'ORGANIZER';
  end if;
  select delegates.delegate_role into selected_role
  from public.pachanga_competition_team_delegates delegates
  where delegates.entry_id = target_entry_id
    and delegates.user_id = target_actor_id
    and delegates.status = 'active'
    and (delegates.valid_until is null or delegates.valid_until > clock_timestamp())
  order by case delegates.delegate_role
    when 'PRIMARY_DELEGATE' then 1 when 'ROSTER_MANAGER' then 2 else 3 end,
    delegates.server_sequence desc, delegates.id desc
  limit 1;
  if selected_role is not null then return selected_role; end if;
  if exists (
    select 1 from public.pachanga_group_members members
    where members.group_id = selected_entry.team_id and members.user_id = target_actor_id
  ) then return 'TEAM_PLAYER'; end if;
  return null;
end;
$$;

revoke all on function private.pachanga_league_entry_actor_scope_v1(uuid, uuid)
  from public, anon, authenticated;

comment on function private.pachanga_league_entry_actor_scope_v1(uuid, uuid) is
  'R4A Entry scope with TEAM_OWNER precedence over overlapping organizer roles.';
