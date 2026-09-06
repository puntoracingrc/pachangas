create or replace function public.get_pachanga_social_team_home_v1(target_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := (select auth.uid());
declare team_snapshot jsonb;
declare enabled boolean;
declare actor_role text;
begin
  if actor_id is null then raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501'; end if;
  if not public.is_registered_pachanga_user() then raise exception 'REGISTERED_USER_REQUIRED' using errcode = '42501'; end if;
  select settings.social_team_home_v3f_enabled into enabled
  from private.pachanga_social_team_settings_v1 settings where settings.singleton;
  if not coalesce(enabled, false) then raise exception 'SOCIAL_TEAM_HOME_DISABLED' using errcode = '42501'; end if;
  select members.role into actor_role from public.pachanga_group_members members
  where members.group_id = target_group_id and members.user_id = actor_id;
  if actor_role is null then raise exception 'TEAM_MEMBERSHIP_REQUIRED' using errcode = '42501'; end if;
  team_snapshot := private.pachanga_social_team_snapshot_v1(target_group_id, actor_id);
  return team_snapshot || jsonb_build_object(
    'nextMatch', (
      select jsonb_build_object(
        'matchId', matches.value ->> 'id',
        'title', coalesce(nullif(matches.value ->> 'title',''), 'Próximo partido'),
        'date', matches.value ->> 'date',
        'place', coalesce(matches.value ->> 'place', ''),
        'modality', matches.value ->> 'kind',
        'targetPlayers', coalesce((matches.value ->> 'targetPlayers')::integer, 0)
      )
      from public.pachanga_groups home_group
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(home_group.payload -> 'matches') = 'array'
          then home_group.payload -> 'matches' else '[]'::jsonb end
      ) matches(value)
      where home_group.id = target_group_id
        and matches.value ->> 'date' ~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
        -- Match Inicio: an open confirmed match remains actionable until closed or scored.
        and coalesce((matches.value ->> 'configured')::boolean, false)
        and matches.value -> 'scoreA' is null
        and not coalesce((matches.value ->> 'closed')::boolean, false)
      order by (matches.value ->> 'date')::timestamptz, matches.value ->> 'id'
      limit 1
    ),
    'actions', jsonb_build_object(
      'canInvitePlayers', actor_role in ('owner','admin'),
      'canManageRoster', actor_role in ('owner','admin'),
      'canEditTeam', actor_role in ('owner','admin'),
      'canCreateMatch', actor_role in ('owner','admin')
    ),
    'activeInvitationCount', (
      select count(*) from public.pachanga_team_player_invitations_v2 invitations
      where invitations.group_id = target_group_id and invitations.state = 'ACTIVE'
        and invitations.expires_at > clock_timestamp()
    )
  );
end;
$$;

revoke all on function public.get_pachanga_social_team_home_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_social_team_home_v1(uuid) to authenticated, service_role;
