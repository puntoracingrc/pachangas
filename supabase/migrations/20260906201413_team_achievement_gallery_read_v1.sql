-- Read-only team collection. Only current registered members may read their team.
-- Do not expose the private policy helpers or relax table policies.
create or replace function public.get_pachanga_team_achievement_gallery_v1(target_group_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
begin
  if auth.uid() is null or not public.is_registered_pachanga_user()
    or target_group_id is null or not public.is_pachanga_group_member(target_group_id) then
    raise exception 'Team membership required' using errcode = '42501';
  end if;


  return jsonb_build_object(
    'groupId', target_group_id,
    'definitions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'achievement_key', achievement_key, 'title', title,
        'description', description, 'rarity', rarity, 'match_scope', match_scope,
        'evaluator_key', evaluator_key, 'threshold', threshold, 'repeatable', repeatable
      ) order by display_priority, threshold, achievement_key)
      from public.pachanga_achievement_definitions
      where active and subject_type = 'team'
    ), '[]'::jsonb),
    'stats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'match_scope', match_scope, 'matches_played', matches_played, 'wins', wins,
        'draws', draws, 'losses', losses, 'goals_for', goals_for, 'clean_sheets', clean_sheets,
        'big_wins', big_wins, 'close_wins', close_wins, 'scoreless_draws', scoreless_draws,
        'max_win_streak', max_win_streak, 'max_unbeaten_streak', max_unbeaten_streak,
        'distinct_opponents', distinct_opponents, 'distinct_opponents_won', distinct_opponents_won
      ) order by match_scope)
      from public.pachanga_team_progression_stats where group_id = target_group_id
    ), '[]'::jsonb),
    'grants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'definition_id', definition_id, 'state', 'active', 'occurrences', occurrences
      ) order by definition_id)
      from (
        select definition_id, count(*) as occurrences
        from public.pachanga_achievement_grants
        where subject_type = 'team' and subject_id = target_group_id and state = 'active'
        group by definition_id
      ) own_grants
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_team_achievement_gallery_v1(uuid) from public, anon;
grant execute on function public.get_pachanga_team_achievement_gallery_v1(uuid) to authenticated;
comment on function public.get_pachanga_team_achievement_gallery_v1(uuid) is
  'Read-only team achievement catalogue, canonical team statistics and active grants; current registered membership required.';
