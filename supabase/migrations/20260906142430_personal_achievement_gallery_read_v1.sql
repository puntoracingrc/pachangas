-- A read-only view of the caller's collection, independent of team membership.
-- Do not expose the private policy helpers or relax table policies.
create or replace function public.get_my_pachanga_achievement_gallery_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  own_profile_id uuid;
begin
  if auth.uid() is null or not public.is_registered_pachanga_user() then
    raise exception 'Registered player required' using errcode = '42501';
  end if;
  select id into own_profile_id
    from public.pachanga_player_profiles where user_id = auth.uid();
  if own_profile_id is null then
    raise exception 'Player profile required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'profileId', own_profile_id,
    'definitions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', id, 'achievement_key', achievement_key, 'title', title,
        'description', description, 'rarity', rarity, 'match_scope', match_scope,
        'evaluator_key', evaluator_key, 'threshold', threshold, 'repeatable', repeatable
      ) order by display_priority, threshold, achievement_key)
      from public.pachanga_achievement_definitions
      where active and subject_type = 'player'
    ), '[]'::jsonb),
    'stats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'match_scope', match_scope, 'appearances', appearances, 'wins', wins,
        'goals', goals, 'braces', braces, 'hat_tricks', hat_tricks,
        'pokers', pokers, 'repokers', repokers, 'double_hat_tricks', double_hat_tricks,
        'max_win_streak', max_win_streak, 'max_unbeaten_streak', max_unbeaten_streak,
        'distinct_opponents', distinct_opponents, 'distinct_opponents_won', distinct_opponents_won
      ) order by match_scope)
      from public.pachanga_player_progression_stats where player_profile_id = own_profile_id
    ), '[]'::jsonb),
    'grants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'definition_id', definition_id, 'state', 'active', 'occurrences', occurrences
      ) order by definition_id)
      from (
        select definition_id, count(*) as occurrences
        from public.pachanga_achievement_grants
        where subject_type = 'player' and subject_id = own_profile_id and state = 'active'
        group by definition_id
      ) own_grants
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_my_pachanga_achievement_gallery_v1() from public, anon;
grant execute on function public.get_my_pachanga_achievement_gallery_v1() to authenticated;
comment on function public.get_my_pachanga_achievement_gallery_v1() is
  'Read-only personal achievement catalogue, own canonical statistics and active grants; no team required.';
