-- Sporting players and accounts permitted to access a group are separate concepts.
-- Keep the membership APIs intact; expose only the active playing roster here.
create or replace function public.get_pachanga_team_players_v1(target_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501'; end if;
  if not exists (
    select 1 from public.pachanga_group_members own
    where own.group_id = target_group_id and own.user_id = actor_id
  ) then raise exception 'TEAM_MEMBERSHIP_REQUIRED' using errcode = '42501'; end if;

  return coalesce((
    select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
      'memberKey', left(encode(extensions.digest(convert_to(
        target_group_id::text || ':player:' || (player.value ->> 'id'), 'UTF8'
      ), 'sha256'), 'hex'), 24),
      'displayName', coalesce(nullif(btrim(player.value ->> 'name'), ''), 'Jugador'),
      'avatarRef', nullif(player.value ->> 'avatar', ''),
      'primaryPosition', case when player.value ->> 'goalkeeperOnly' = 'true' then 'Portero'
        else coalesce(nullif(player.value ->> 'outfieldPosition', ''), nullif(player.value ->> 'position', '')) end,
      'preferredModality', groups.social_modality,
      'role', coalesce(member.role, 'player'),
      'joinedAt', member.created_at,
      'isCurrentUser', coalesce(member.user_id = actor_id, false)
    )) order by player.ordinality)
    from public.pachanga_groups groups
    cross join lateral jsonb_array_elements(case
      when jsonb_typeof(groups.payload -> 'players') = 'array' then groups.payload -> 'players'
      else '[]'::jsonb end) with ordinality as player(value, ordinality)
    left join public.pachanga_group_members member
      on member.group_id = groups.id and member.user_id::text = player.value ->> 'ownerUserId'
    where groups.id = target_group_id
      and nullif(player.value ->> 'id', '') is not null
      and coalesce(player.value ->> 'inactive', 'false') <> 'true'
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.get_pachanga_team_players_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_team_players_v1(uuid) to authenticated, service_role;
