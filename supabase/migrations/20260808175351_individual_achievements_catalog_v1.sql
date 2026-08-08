-- Pachangas IQ individual achievement catalog v1.
-- Extends the existing server-authoritative progression engine without changing Rating V2.

update public.pachanga_achievement_definitions
set title = case achievement_key
      when 'player.internal.matches.001' then 'Primeros minutos'
      when 'player.internal.wins.001' then 'Primera alegría'
      when 'player.internal.goals.001' then 'Abre la cuenta'
      when 'player.internal.braces.001' then 'Por partida doble'
      when 'player.internal.hat_tricks.001' then 'Hat-trick'
      when 'player.external.matches.001' then 'Debut competitivo'
      when 'player.external.wins.001' then 'Primera conquista'
      when 'player.external.goals.010' then 'Goleador de retos'
      else title
    end,
    description = case achievement_key
      when 'player.internal.matches.001' then 'Participa en su primer partido interno finalizado.'
      when 'player.internal.wins.001' then 'Disputa y gana su primer partido interno.'
      when 'player.internal.goals.001' then 'Marca su primer gol interno confirmado.'
      when 'player.internal.braces.001' then 'Marca exactamente dos goles en un partido interno.'
      when 'player.internal.hat_tricks.001' then 'Marca tres o más goles en un partido interno.'
      when 'player.external.matches.001' then 'Participa en su primer partido confirmado contra otro equipo.'
      when 'player.external.wins.001' then 'Disputa y gana su primer partido confirmado contra otro equipo.'
      when 'player.external.goals.010' then 'Acumula diez goles confirmados contra equipos rivales.'
      else description
    end,
    rarity = case achievement_key
      when 'player.external.matches.001' then 'uncommon'
      when 'player.external.wins.001' then 'rare'
      when 'player.external.goals.010' then 'epic'
      else rarity
    end
where version = 1
  and achievement_key in (
    'player.internal.matches.001',
    'player.internal.wins.001',
    'player.internal.goals.001',
    'player.internal.braces.001',
    'player.internal.hat_tricks.001',
    'player.external.matches.001',
    'player.external.wins.001',
    'player.external.goals.010'
  );

insert into public.pachanga_achievement_definitions(
  achievement_key, title, description, subject_type, match_scope, category,
  evaluator_key, threshold, rarity, reward_kind, reward_key
) values
  (
    'player.internal.matches.005', 'Uno de los nuestros',
    'Participa en cinco partidos internos finalizados.',
    'player', 'internal', 'matches', 'PLAYER_APPEARANCES', 5, 'common',
    'player_badge', 'badge.internal.five_matches'
  ),
  (
    'player.internal.matches.025', 'Habitual',
    'Participa en veinticinco partidos internos finalizados.',
    'player', 'internal', 'matches', 'PLAYER_APPEARANCES', 25, 'uncommon',
    'player_badge', 'badge.internal.twenty_five_matches'
  )
on conflict (achievement_key, version) do update set
  title = excluded.title,
  description = excluded.description,
  subject_type = excluded.subject_type,
  match_scope = excluded.match_scope,
  category = excluded.category,
  evaluator_key = excluded.evaluator_key,
  threshold = excluded.threshold,
  rarity = excluded.rarity,
  repeatable = false,
  reward_kind = excluded.reward_kind,
  reward_key = excluded.reward_key,
  active = true;

-- A double is exactly two goals. A hat-trick remains three or more, so one match
-- cannot inflate both counters.
create or replace function private.pachanga_rebuild_player_progression_stats_v1(
  target_player_profile_id uuid,
  target_match_scope text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  aggregates record;
  fact record;
  current_wins integer := 0;
  max_wins integer := 0;
  current_unbeaten integer := 0;
  max_unbeaten integer := 0;
  saved public.pachanga_player_progression_stats%rowtype;
  target_user_id uuid;
begin
  if target_match_scope not in ('internal', 'external') then
    raise exception 'Invalid progression scope';
  end if;

  select
    count(*)::integer as appearances,
    count(*) filter (where player_facts.outcome = 'win')::integer as wins,
    count(*) filter (where player_facts.outcome = 'draw')::integer as draws,
    count(*) filter (where player_facts.outcome = 'loss')::integer as losses,
    coalesce(sum(player_facts.goals), 0)::integer as goals,
    count(*) filter (where player_facts.goals = 2)::integer as braces,
    count(*) filter (where player_facts.goals >= 3)::integer as hat_tricks
  into aggregates
  from public.pachanga_progression_player_match_facts player_facts
  join public.pachanga_progression_match_facts match_facts
    on match_facts.id = player_facts.match_fact_id
  where player_facts.player_profile_id = target_player_profile_id
    and player_facts.state = 'active'
    and match_facts.state = 'active'
    and match_facts.match_scope = target_match_scope;

  for fact in
    select player_facts.outcome
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_progression_match_facts match_facts
      on match_facts.id = player_facts.match_fact_id
    where player_facts.player_profile_id = target_player_profile_id
      and player_facts.state = 'active'
      and match_facts.state = 'active'
      and match_facts.match_scope = target_match_scope
    order by match_facts.played_at, match_facts.server_sequence, match_facts.id
  loop
    if fact.outcome = 'win' then
      current_wins := current_wins + 1;
      current_unbeaten := current_unbeaten + 1;
    elsif fact.outcome = 'draw' then
      current_wins := 0;
      current_unbeaten := current_unbeaten + 1;
    else
      current_wins := 0;
      current_unbeaten := 0;
    end if;
    max_wins := greatest(max_wins, current_wins);
    max_unbeaten := greatest(max_unbeaten, current_unbeaten);
  end loop;

  insert into public.pachanga_player_progression_stats(
    player_profile_id, match_scope, appearances, wins, draws, losses,
    goals, braces, hat_tricks, current_win_streak, max_win_streak,
    current_unbeaten_streak, max_unbeaten_streak
  ) values (
    target_player_profile_id, target_match_scope, aggregates.appearances,
    aggregates.wins, aggregates.draws, aggregates.losses,
    aggregates.goals, aggregates.braces, aggregates.hat_tricks,
    current_wins, max_wins, current_unbeaten, max_unbeaten
  ) on conflict (player_profile_id, match_scope) do update set
    appearances = excluded.appearances,
    wins = excluded.wins,
    draws = excluded.draws,
    losses = excluded.losses,
    goals = excluded.goals,
    braces = excluded.braces,
    hat_tricks = excluded.hat_tricks,
    current_win_streak = excluded.current_win_streak,
    max_win_streak = excluded.max_win_streak,
    current_unbeaten_streak = excluded.current_unbeaten_streak,
    max_unbeaten_streak = excluded.max_unbeaten_streak,
    revision = public.pachanga_player_progression_stats.revision + 1,
    server_sequence = nextval('public.pachanga_progression_sequence'),
    updated_at = clock_timestamp()
  returning * into saved;

  select profiles.user_id into target_user_id
  from public.pachanga_player_profiles profiles
  where profiles.id = target_player_profile_id;
  perform private.pachanga_progression_bump_user_v1(target_user_id, saved.server_sequence);
  return to_jsonb(saved);
end;
$$;

revoke all on function private.pachanga_rebuild_player_progression_stats_v1(uuid, text)
  from public, anon, authenticated;

-- Keep the original snapshot implementation as an internal compatibility base
-- and expose an additive canonical catalog to new clients.
alter function public.get_pachanga_progression_snapshot_v1(uuid)
  rename to pachanga_progression_snapshot_base_v1;
alter function public.pachanga_progression_snapshot_base_v1(uuid)
  set schema private;
revoke all on function private.pachanga_progression_snapshot_base_v1(uuid)
  from public, anon, authenticated;

create or replace function public.get_pachanga_progression_snapshot_v1(target_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  base_snapshot jsonb;
  current_profile_id uuid;
begin
  base_snapshot := private.pachanga_progression_snapshot_base_v1(target_group_id);

  select profiles.id into current_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = auth.uid();

  return base_snapshot || jsonb_build_object(
    'personalAchievementCatalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.achievement_key,
        'title', catalog.title,
        'description', catalog.description,
        'scope', catalog.match_scope,
        'category', catalog.category,
        'rarity', catalog.rarity,
        'threshold', catalog.threshold,
        'currentValue', catalog.current_value,
        'progressPercent', least(100, floor(catalog.current_value * 100.0 / catalog.threshold)::integer),
        'unlocked', catalog.grant_id is not null,
        'grantId', catalog.grant_id,
        'awardedAt', catalog.awarded_at,
        'rewardKind', catalog.reward_kind,
        'rewardKey', catalog.reward_key
      ) order by catalog.match_scope, catalog.category, catalog.threshold, catalog.achievement_key)
      from (
        select
          definitions.achievement_key,
          definitions.title,
          definitions.description,
          definitions.match_scope,
          definitions.category,
          definitions.rarity,
          definitions.threshold,
          definitions.reward_kind,
          definitions.reward_key,
          case definitions.evaluator_key
            when 'PLAYER_APPEARANCES' then coalesce(stats.appearances, 0)
            when 'PLAYER_WINS' then coalesce(stats.wins, 0)
            when 'PLAYER_GOALS' then coalesce(stats.goals, 0)
            when 'PLAYER_BRACES' then coalesce(stats.braces, 0)
            when 'PLAYER_HATTRICKS' then coalesce(stats.hat_tricks, 0)
            else 0
          end as current_value,
          grants.id as grant_id,
          grants.awarded_at
        from public.pachanga_achievement_definitions definitions
        left join public.pachanga_player_progression_stats stats
          on stats.player_profile_id = current_profile_id
          and stats.match_scope = definitions.match_scope
        left join lateral (
          select achievement_grants.id, achievement_grants.awarded_at
          from public.pachanga_achievement_grants achievement_grants
          where achievement_grants.definition_id = definitions.id
            and achievement_grants.subject_type = 'player'
            and achievement_grants.subject_id = current_profile_id
            and achievement_grants.state = 'active'
          order by achievement_grants.awarded_at desc, achievement_grants.id desc
          limit 1
        ) grants on true
        where definitions.active
          and definitions.subject_type = 'player'
      ) catalog
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.get_pachanga_progression_snapshot_v1(uuid)
  from public, anon;
grant execute on function public.get_pachanga_progression_snapshot_v1(uuid)
  to authenticated;

-- Rebuild exact brace counters, revoke grants that no longer satisfy the exact
-- rule, and grant the two new cumulative milestones from canonical facts.
do $$
declare
  player_stats record;
  milestone record;
  origin record;
begin
  for player_stats in
    select stats.player_profile_id, stats.match_scope
    from public.pachanga_player_progression_stats stats
    order by stats.player_profile_id, stats.match_scope
  loop
    perform private.pachanga_rebuild_player_progression_stats_v1(
      player_stats.player_profile_id,
      player_stats.match_scope
    );
    perform private.pachanga_reconcile_subject_achievements_v1(
      'player',
      player_stats.player_profile_id,
      player_stats.match_scope,
      'individual_achievement_rule_v1'
    );
  end loop;

  for player_stats in
    select stats.player_profile_id, stats.appearances
    from public.pachanga_player_progression_stats stats
    where stats.match_scope = 'internal'
      and stats.appearances >= 5
    order by stats.player_profile_id
  loop
    select match_facts.id, match_facts.group_id
    into origin
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_progression_match_facts match_facts
      on match_facts.id = player_facts.match_fact_id
    where player_facts.player_profile_id = player_stats.player_profile_id
      and player_facts.state = 'active'
      and match_facts.state = 'active'
      and match_facts.match_scope = 'internal'
    order by match_facts.played_at desc, match_facts.server_sequence desc, match_facts.id desc
    limit 1;

    if origin.id is not null then
      for milestone in
        select definitions.id, definitions.threshold
        from public.pachanga_achievement_definitions definitions
        where definitions.active
          and definitions.achievement_key in (
            'player.internal.matches.005',
            'player.internal.matches.025'
          )
        order by definitions.threshold
      loop
        if player_stats.appearances >= milestone.threshold then
          perform private.pachanga_award_achievement_v1(
            milestone.id,
            player_stats.player_profile_id,
            origin.group_id,
            origin.id,
            player_stats.appearances
          );
        end if;
      end loop;
    end if;
  end loop;
end;
$$;

comment on function public.get_pachanga_progression_snapshot_v1(uuid) is
  'Canonical progression snapshot including server-calculated individual achievement progress.';
