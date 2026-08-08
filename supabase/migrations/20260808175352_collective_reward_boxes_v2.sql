-- Collective reward boxes and repeatable individual achievement occurrences.
-- Rating V2 remains read-only input: this migration never updates player ratings or facets.

alter table public.pachanga_player_progression_stats
  add column if not exists pokers integer not null default 0,
  add column if not exists repokers integer not null default 0,
  add column if not exists double_hat_tricks integer not null default 0;

alter table public.pachanga_player_progression_stats
  drop constraint if exists pachanga_player_progression_stats_check;
alter table public.pachanga_player_progression_stats
  add constraint pachanga_player_progression_stats_nonnegative_check check (
    least(
      appearances, wins, draws, losses, goals, braces, hat_tricks,
      pokers, repokers, double_hat_tricks, current_win_streak,
      max_win_streak, current_unbeaten_streak, max_unbeaten_streak
    ) >= 0
  );

alter table public.pachanga_achievement_definitions
  drop constraint if exists pachanga_achievement_definitions_evaluator_key_check;
alter table public.pachanga_achievement_definitions
  add constraint pachanga_achievement_definitions_evaluator_key_check check (evaluator_key in (
    'TEAM_MATCHES', 'TEAM_WINS', 'TEAM_DRAWS', 'TEAM_LOSSES', 'TEAM_GOALS',
    'TEAM_MAX_WIN_STREAK', 'TEAM_MAX_UNBEATEN_STREAK', 'TEAM_CLEAN_SHEETS',
    'TEAM_BIG_WINS', 'TEAM_CLOSE_WINS', 'TEAM_SCORELESS_DRAWS',
    'TEAM_DISTINCT_OPPONENTS', 'PLAYER_APPEARANCES', 'PLAYER_WINS',
    'PLAYER_GOALS', 'PLAYER_BRACES', 'PLAYER_HATTRICKS', 'PLAYER_POKERS',
    'PLAYER_REPOKERS', 'PLAYER_DOUBLE_HAT_TRICKS'
  ));

alter table public.pachanga_achievement_grants
  add column if not exists occurred_at timestamptz,
  add column if not exists is_first boolean not null default true,
  add column if not exists sequence_count integer not null default 1,
  add column if not exists occurrence_metadata jsonb not null default '{}'::jsonb;

update public.pachanga_achievement_grants grants
set occurred_at = facts.played_at
from public.pachanga_progression_match_facts facts
where facts.id = grants.origin_match_fact_id
  and grants.occurred_at is null;

update public.pachanga_achievement_grants grants
set occurred_at = grants.awarded_at
where grants.occurred_at is null;

alter table public.pachanga_achievement_grants
  alter column occurred_at set not null;
alter table public.pachanga_achievement_grants
  add constraint pachanga_achievement_grants_sequence_count_check
  check (sequence_count >= 1);
alter table public.pachanga_achievement_grants
  add constraint pachanga_achievement_grants_metadata_check
  check (jsonb_typeof(occurrence_metadata) = 'object');

drop index if exists public.pachanga_achievement_active_grant_idx;
create unique index if not exists pachanga_achievement_active_occurrence_idx
  on public.pachanga_achievement_grants(
    subject_type, subject_id, definition_id, origin_match_fact_id
  ) where state = 'active';
create index if not exists pachanga_achievement_subject_history_idx
  on public.pachanga_achievement_grants(
    subject_type, subject_id, occurred_at desc, id desc
  );

alter table public.pachanga_reward_grants
  drop constraint if exists pachanga_reward_grants_reward_kind_check;
alter table public.pachanga_reward_grants
  add constraint pachanga_reward_grants_reward_kind_check
  check (reward_kind in ('collective_box', 'team_cosmetic', 'player_badge', 'player_title'));

alter table public.pachanga_reward_recipients
  add column if not exists box_id uuid default gen_random_uuid(),
  add column if not exists achievement_grant_id uuid
    references public.pachanga_achievement_grants(id) on delete restrict,
  add column if not exists match_fact_id uuid
    references public.pachanga_progression_match_facts(id) on delete restrict,
  add column if not exists group_id uuid
    references public.pachanga_groups(id) on delete restrict,
  add column if not exists player_profile_id uuid
    references public.pachanga_player_profiles(id) on delete restrict,
  add column if not exists reward_reference text,
  add column if not exists revealed_payload jsonb,
  add column if not exists reward_granted_at timestamptz,
  add column if not exists source_correction jsonb,
  add column if not exists revoked_reason text;

update public.pachanga_reward_recipients recipients
set achievement_grant_id = rewards.achievement_grant_id,
    match_fact_id = grants.origin_match_fact_id,
    group_id = rewards.group_id,
    player_profile_id = (
      select profiles.id
      from public.pachanga_player_profiles profiles
      where profiles.user_id = recipients.user_id
      order by profiles.id
      limit 1
    ),
    reward_reference = rewards.reward_key
from public.pachanga_reward_grants rewards
join public.pachanga_achievement_grants grants
  on grants.id = rewards.achievement_grant_id
where rewards.id = recipients.reward_grant_id;

update public.pachanga_reward_recipients
set revealed_payload = '{}'::jsonb,
    reward_granted_at = coalesce(opened_at, snapshot_at)
where status = 'opened' and revealed_payload is null;

alter table public.pachanga_reward_recipients
  alter column box_id set not null,
  alter column achievement_grant_id set not null,
  alter column match_fact_id set not null,
  alter column group_id set not null,
  alter column reward_reference set not null;
alter table public.pachanga_reward_recipients
  add constraint pachanga_reward_recipients_revealed_payload_check
  check (revealed_payload is null or jsonb_typeof(revealed_payload) = 'object');
alter table public.pachanga_reward_recipients
  add constraint pachanga_reward_recipients_source_correction_check
  check (source_correction is null or jsonb_typeof(source_correction) = 'object');
create unique index if not exists pachanga_reward_recipients_box_idx
  on public.pachanga_reward_recipients(box_id);
create unique index if not exists pachanga_reward_recipients_achievement_user_idx
  on public.pachanga_reward_recipients(achievement_grant_id, user_id);
create index if not exists pachanga_reward_recipients_pending_user_idx
  on public.pachanga_reward_recipients(user_id, snapshot_at, box_id)
  where status = 'pending';

alter table public.pachanga_reward_open_receipts
  add column if not exists box_id uuid;
update public.pachanga_reward_open_receipts receipts
set box_id = recipients.box_id
from public.pachanga_reward_recipients recipients
where recipients.reward_grant_id = receipts.reward_grant_id
  and recipients.user_id = receipts.actor_user_id
  and receipts.box_id is null;
alter table public.pachanga_reward_open_receipts
  alter column box_id set not null;

create table if not exists private.pachanga_reward_box_contents (
  box_id uuid primary key,
  reward_payload jsonb not null,
  generated_at timestamptz not null default clock_timestamp(),
  check (jsonb_typeof(reward_payload) = 'object')
);
revoke all on table private.pachanga_reward_box_contents
  from public, anon, authenticated;
grant all on table private.pachanga_reward_box_contents to service_role;

-- Personal achievements are recognition only. Scoring families are one
-- repeatable occurrence per canonical match, with first-time presentation.
update public.pachanga_achievement_definitions
set reward_kind = 'none', reward_key = null
where subject_type = 'player';

update public.pachanga_achievement_definitions
set repeatable = true,
    title = case evaluator_key
      when 'PLAYER_BRACES' then 'Doblete'
      when 'PLAYER_HATTRICKS' then 'Hat-trick'
      else title end,
    description = case evaluator_key
      when 'PLAYER_BRACES' then 'Marca exactamente dos goles en un partido confirmado.'
      when 'PLAYER_HATTRICKS' then 'Marca exactamente tres goles en un partido confirmado.'
      else description end,
    parameters = case evaluator_key
      when 'PLAYER_BRACES' then jsonb_build_object(
        'ruleKind', 'player_match_goals', 'goalsExact', 2,
        'firstTitle', 'Primer doblete', 'repeatTitle', 'Doblete'
      )
      when 'PLAYER_HATTRICKS' then jsonb_build_object(
        'ruleKind', 'player_match_goals', 'goalsExact', 3,
        'firstTitle', 'Primer hat-trick', 'repeatTitle', 'Hat-trick'
      )
      else parameters end
where evaluator_key in ('PLAYER_BRACES', 'PLAYER_HATTRICKS');

insert into public.pachanga_achievement_definitions(
  achievement_key, title, description, subject_type, match_scope, category,
  evaluator_key, parameters, threshold, rarity, repeatable, reward_kind, reward_key
)
select values_row.*
from (values
  ('player.internal.pokers.001', 'Póker', 'Marca exactamente cuatro goles en un partido confirmado.', 'player', 'internal', 'goals', 'PLAYER_POKERS', '{"ruleKind":"player_match_goals","goalsExact":4,"firstTitle":"Primer póker","repeatTitle":"Póker"}'::jsonb, 1, 'rare', true, 'none', null),
  ('player.internal.repokers.001', 'Repóker', 'Marca exactamente cinco goles en un partido confirmado.', 'player', 'internal', 'goals', 'PLAYER_REPOKERS', '{"ruleKind":"player_match_goals","goalsExact":5,"firstTitle":"Primer repóker","repeatTitle":"Repóker"}'::jsonb, 1, 'epic', true, 'none', null),
  ('player.internal.double_hat_tricks.001', 'Doble hat-trick', 'Marca seis o más goles en un partido confirmado.', 'player', 'internal', 'goals', 'PLAYER_DOUBLE_HAT_TRICKS', '{"ruleKind":"player_match_goals","goalsMinimum":6,"firstTitle":"Primer doble hat-trick","repeatTitle":"Doble hat-trick"}'::jsonb, 1, 'legendary', true, 'none', null),
  ('player.external.pokers.001', 'Póker', 'Marca exactamente cuatro goles en un partido confirmado.', 'player', 'external', 'goals', 'PLAYER_POKERS', '{"ruleKind":"player_match_goals","goalsExact":4,"firstTitle":"Primer póker","repeatTitle":"Póker"}'::jsonb, 1, 'rare', true, 'none', null),
  ('player.external.repokers.001', 'Repóker', 'Marca exactamente cinco goles en un partido confirmado.', 'player', 'external', 'goals', 'PLAYER_REPOKERS', '{"ruleKind":"player_match_goals","goalsExact":5,"firstTitle":"Primer repóker","repeatTitle":"Repóker"}'::jsonb, 1, 'epic', true, 'none', null),
  ('player.external.double_hat_tricks.001', 'Doble hat-trick', 'Marca seis o más goles en un partido confirmado.', 'player', 'external', 'goals', 'PLAYER_DOUBLE_HAT_TRICKS', '{"ruleKind":"player_match_goals","goalsMinimum":6,"firstTitle":"Primer doble hat-trick","repeatTitle":"Doble hat-trick"}'::jsonb, 1, 'legendary', true, 'none', null)
) as values_row(
  achievement_key, title, description, subject_type, match_scope, category,
  evaluator_key, parameters, threshold, rarity, repeatable, reward_kind, reward_key
)
on conflict (achievement_key, version) do update set
  title = excluded.title, description = excluded.description,
  evaluator_key = excluded.evaluator_key, parameters = excluded.parameters,
  rarity = excluded.rarity, repeatable = excluded.repeatable,
  reward_kind = 'none', reward_key = null, active = true;

-- These existing team definitions become per-match occurrence families.
update public.pachanga_achievement_definitions
set repeatable = true,
    parameters = parameters || case achievement_key
      when 'team.external.wins.001' then '{"ruleKind":"team_match_win","firstTitle":"Primera victoria","repeatTitle":"Victoria"}'::jsonb
      when 'team.external.clean_sheets.001' then '{"ruleKind":"team_match_clean_sheet","firstTitle":"Primera portería a cero","repeatTitle":"Portería a cero"}'::jsonb
      when 'team.external.big_wins.001' then '{"ruleKind":"team_match_big_win","firstTitle":"Goleada","repeatTitle":"Goleada"}'::jsonb
      when 'team.external.close_wins.001' then '{"ruleKind":"team_match_close_win","firstTitle":"Por la mínima","repeatTitle":"Por la mínima"}'::jsonb
      when 'team.internal.big_wins.001' then '{"ruleKind":"team_match_big_win","firstTitle":"Partido desatado","repeatTitle":"Partido desatado"}'::jsonb
      when 'team.internal.close_wins.001' then '{"ruleKind":"team_match_close_win","firstTitle":"Hasta el final","repeatTitle":"Hasta el final"}'::jsonb
      else '{}'::jsonb end
where achievement_key in (
  'team.external.wins.001', 'team.external.clean_sheets.001',
  'team.external.big_wins.001', 'team.external.close_wins.001',
  'team.internal.big_wins.001', 'team.internal.close_wins.001'
);

insert into public.pachanga_achievement_definitions(
  achievement_key, title, description, subject_type, match_scope, category,
  evaluator_key, parameters, threshold, rarity, repeatable, reward_kind, reward_key
)
select
  'team.' || scopes.scope || '.match_goals.' || lpad(tiers.goals::text, 3, '0'),
  case when tiers.goals = 6 then '6+ goles colectivos' else tiers.goals::text || ' goles colectivos' end,
  case when tiers.goals = 6
    then 'El equipo marca seis o más goles en un partido confirmado.'
    else 'El equipo marca exactamente ' || tiers.goals::text || ' goles en un partido confirmado.' end,
  'team', scopes.scope, 'match_goals', 'TEAM_GOALS',
  case when tiers.goals = 6
    then jsonb_build_object('ruleKind', 'team_match_goals', 'goalsMinimum', 6)
    else jsonb_build_object('ruleKind', 'team_match_goals', 'goalsExact', tiers.goals) end,
  tiers.goals,
  case when tiers.goals <= 2 then 'common'
    when tiers.goals <= 4 then 'uncommon'
    when tiers.goals = 5 then 'rare' else 'epic' end,
  true, 'none', null
from (values ('internal'), ('external')) scopes(scope)
cross join (values (2), (3), (4), (5), (6)) tiers(goals)
on conflict (achievement_key, version) do update set
  title = excluded.title, description = excluded.description,
  parameters = excluded.parameters, threshold = excluded.threshold,
  rarity = excluded.rarity, repeatable = true, reward_kind = 'none',
  reward_key = null, active = true;

-- Legacy personal rewards are retained as auditable revoked rows. They are not
-- converted into boxes because no collective achievement originated them.
update public.pachanga_reward_recipients recipients
set status = 'revoked', revoked_at = coalesce(recipients.revoked_at, clock_timestamp()),
    revoked_reason = 'individual_achievements_do_not_generate_rewards',
    revision = recipients.revision + 1
from public.pachanga_reward_grants rewards
join public.pachanga_achievement_grants grants on grants.id = rewards.achievement_grant_id
where recipients.reward_grant_id = rewards.id
  and grants.subject_type = 'player'
  and recipients.status = 'pending';

update public.pachanga_reward_grants rewards
set state = 'revoked', revoked_at = coalesce(rewards.revoked_at, clock_timestamp())
from public.pachanga_achievement_grants grants
where grants.id = rewards.achievement_grant_id
  and grants.subject_type = 'player'
  and rewards.state = 'active';

update public.pachanga_player_reward_inventory inventory
set state = 'revoked', revoked_at = coalesce(inventory.revoked_at, clock_timestamp())
where exists (
  select 1
  from public.pachanga_achievement_grants grants
  where grants.id = inventory.source_grant_id
    and grants.subject_type = 'player'
);

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
    count(*) filter (where player_facts.goals = 3)::integer as hat_tricks,
    count(*) filter (where player_facts.goals = 4)::integer as pokers,
    count(*) filter (where player_facts.goals = 5)::integer as repokers,
    count(*) filter (where player_facts.goals >= 6)::integer as double_hat_tricks
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
    goals, braces, hat_tricks, pokers, repokers, double_hat_tricks,
    current_win_streak, max_win_streak, current_unbeaten_streak,
    max_unbeaten_streak
  ) values (
    target_player_profile_id, target_match_scope, aggregates.appearances,
    aggregates.wins, aggregates.draws, aggregates.losses,
    aggregates.goals, aggregates.braces, aggregates.hat_tricks,
    aggregates.pokers, aggregates.repokers, aggregates.double_hat_tricks,
    current_wins, max_wins, current_unbeaten, max_unbeaten
  ) on conflict (player_profile_id, match_scope) do update set
    appearances = excluded.appearances,
    wins = excluded.wins,
    draws = excluded.draws,
    losses = excluded.losses,
    goals = excluded.goals,
    braces = excluded.braces,
    hat_tricks = excluded.hat_tricks,
    pokers = excluded.pokers,
    repokers = excluded.repokers,
    double_hat_tricks = excluded.double_hat_tricks,
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

create or replace function private.pachanga_achievement_metric_v1(
  target_definition_id uuid,
  target_subject_id uuid
)
returns integer
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  definition public.pachanga_achievement_definitions%rowtype;
  metric integer := 0;
begin
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id;
  if not found then return 0; end if;

  if definition.subject_type = 'team' then
    select case definition.evaluator_key
      when 'TEAM_MATCHES' then stats.matches_played
      when 'TEAM_WINS' then stats.wins
      when 'TEAM_DRAWS' then stats.draws
      when 'TEAM_LOSSES' then stats.losses
      when 'TEAM_GOALS' then stats.goals_for
      when 'TEAM_MAX_WIN_STREAK' then stats.max_win_streak
      when 'TEAM_MAX_UNBEATEN_STREAK' then stats.max_unbeaten_streak
      when 'TEAM_CLEAN_SHEETS' then stats.clean_sheets
      when 'TEAM_BIG_WINS' then stats.big_wins
      when 'TEAM_CLOSE_WINS' then stats.close_wins
      when 'TEAM_SCORELESS_DRAWS' then stats.scoreless_draws
      when 'TEAM_DISTINCT_OPPONENTS' then stats.distinct_opponents
      else 0 end
    into metric
    from public.pachanga_team_progression_stats stats
    where stats.group_id = target_subject_id
      and stats.match_scope = definition.match_scope;
  else
    select case definition.evaluator_key
      when 'PLAYER_APPEARANCES' then stats.appearances
      when 'PLAYER_WINS' then stats.wins
      when 'PLAYER_GOALS' then stats.goals
      when 'PLAYER_BRACES' then stats.braces
      when 'PLAYER_HATTRICKS' then stats.hat_tricks
      when 'PLAYER_POKERS' then stats.pokers
      when 'PLAYER_REPOKERS' then stats.repokers
      when 'PLAYER_DOUBLE_HAT_TRICKS' then stats.double_hat_tricks
      else 0 end
    into metric
    from public.pachanga_player_progression_stats stats
    where stats.player_profile_id = target_subject_id
      and stats.match_scope = definition.match_scope;
  end if;
  return coalesce(metric, 0);
end;
$$;

create or replace function private.pachanga_achievement_occurrence_title_v2(
  target_definition_id uuid,
  target_is_first boolean
)
returns text
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select coalesce(
    nullif(definitions.parameters ->> case when target_is_first then 'firstTitle' else 'repeatTitle' end, ''),
    definitions.title
  )
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id;
$$;

create or replace function private.pachanga_ensure_collective_boxes_v2(
  target_achievement_grant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  source record;
  reward public.pachanga_reward_grants%rowtype;
  recipient record;
  saved_box_id uuid;
  created_count integer := 0;
  effective_reward_kind text;
  effective_reward_key text;
  sealed_payload jsonb;
begin
  select grants.*, definitions.achievement_key, definitions.title,
    definitions.description, definitions.rarity,
    definitions.reward_kind as definition_reward_kind,
    definitions.reward_key as definition_reward_key
  into source
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where grants.id = target_achievement_grant_id
    and grants.subject_type = 'team'
    and grants.state = 'active';
  if not found then return 0; end if;

  effective_reward_kind := case
    when source.definition_reward_kind = 'team_cosmetic' then 'team_cosmetic'
    else 'collective_box' end;
  effective_reward_key := coalesce(
    source.definition_reward_key,
    'box.collective.' || source.rarity
  );

  insert into public.pachanga_reward_grants(
    achievement_grant_id, reward_kind, reward_key, group_id,
    player_profile_id, payload
  ) values (
    source.id, effective_reward_kind, effective_reward_key, source.group_id,
    null, jsonb_build_object(
      'boxKind', 'collective_achievement',
      'achievementKey', source.achievement_key,
      'rarity', source.rarity
    )
  ) on conflict (achievement_grant_id) do update set
    payload = excluded.payload
  returning * into reward;

  for recipient in
    select distinct on (profiles.user_id)
      profiles.user_id, profiles.id as player_profile_id,
      profiles.display_name, player_facts.local_player_id
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_player_profiles profiles
      on profiles.id = player_facts.player_profile_id
    where player_facts.match_fact_id = source.origin_match_fact_id
      and player_facts.group_id = source.group_id
      and player_facts.state = 'active'
      and profiles.user_id is not null
    order by profiles.user_id, player_facts.local_player_id
  loop
    saved_box_id := gen_random_uuid();
    insert into public.pachanga_reward_recipients(
      reward_grant_id, user_id, member_role_snapshot, member_name_snapshot,
      box_id, achievement_grant_id, match_fact_id, group_id,
      player_profile_id, reward_reference
    ) values (
      reward.id, recipient.user_id, 'participant',
      left(coalesce(recipient.display_name, 'Jugador'), 120),
      saved_box_id, source.id, source.origin_match_fact_id, source.group_id,
      recipient.player_profile_id, effective_reward_key
    ) on conflict (achievement_grant_id, user_id) do update set
      player_profile_id = excluded.player_profile_id,
      match_fact_id = excluded.match_fact_id,
      group_id = excluded.group_id,
      member_role_snapshot = 'participant',
      member_name_snapshot = excluded.member_name_snapshot,
      reward_reference = excluded.reward_reference
    returning box_id into saved_box_id;

    sealed_payload := jsonb_build_object(
      'kind', effective_reward_kind,
      'key', effective_reward_key,
      'achievementKey', source.achievement_key,
      'achievementTitle', private.pachanga_achievement_occurrence_title_v2(
        source.definition_id, source.is_first
      ),
      'rarity', source.rarity,
      'source', 'collective_achievement'
    );
    insert into private.pachanga_reward_box_contents(box_id, reward_payload)
    values (saved_box_id, sealed_payload)
    on conflict (box_id) do nothing;

    if found then created_count := created_count + 1; end if;
    perform private.pachanga_progression_bump_user_v1(recipient.user_id);
  end loop;
  return created_count;
end;
$$;

create or replace function private.pachanga_award_achievement_v1(
  target_definition_id uuid,
  target_subject_id uuid,
  target_group_id uuid,
  target_origin_match_fact_id uuid,
  target_metric_value integer
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  definition public.pachanga_achievement_definitions%rowtype;
  source_fact public.pachanga_progression_match_facts%rowtype;
  saved_grant_id uuid;
  occurrence_is_first boolean;
  occurrence_sequence integer;
  occurrence_title text;
begin
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = target_definition_id and definitions.active;
  if not found or definition.subject_type not in ('team', 'player') then return null; end if;
  if target_metric_value < definition.threshold then return null; end if;
  if definition.subject_type = 'team' and target_subject_id <> target_group_id then
    raise exception 'Team achievement subject must be its group';
  end if;

  select * into source_fact
  from public.pachanga_progression_match_facts facts
  where facts.id = target_origin_match_fact_id and facts.state = 'active';
  if not found then return null; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'achievement:' || definition.id::text || ':' || target_subject_id::text, 0
  ));

  if definition.repeatable then
    select grants.id into saved_grant_id
    from public.pachanga_achievement_grants grants
    where grants.subject_type = definition.subject_type
      and grants.subject_id = target_subject_id
      and grants.definition_id = definition.id
      and grants.origin_match_fact_id = target_origin_match_fact_id
      and grants.state = 'active'
    order by grants.id
    limit 1;
  else
    select grants.id into saved_grant_id
    from public.pachanga_achievement_grants grants
    where grants.subject_type = definition.subject_type
      and grants.subject_id = target_subject_id
      and grants.definition_id = definition.id
      and grants.state = 'active'
    order by grants.occurred_at, grants.id
    limit 1;
  end if;

  if saved_grant_id is not null then
    if definition.subject_type = 'team' then
      perform private.pachanga_ensure_collective_boxes_v2(saved_grant_id);
    end if;
    return saved_grant_id;
  end if;

  select not exists (
    select 1
    from public.pachanga_achievement_grants grants
    where grants.subject_type = definition.subject_type
      and grants.subject_id = target_subject_id
      and grants.definition_id = definition.id
      and grants.state = 'active'
  ), count(*) + 1
  into occurrence_is_first, occurrence_sequence
  from public.pachanga_achievement_grants grants
  where grants.subject_type = definition.subject_type
    and grants.subject_id = target_subject_id
    and grants.definition_id = definition.id
    and grants.state = 'active';

  occurrence_title := private.pachanga_achievement_occurrence_title_v2(
    definition.id, occurrence_is_first
  );
  saved_grant_id := gen_random_uuid();
  insert into public.pachanga_achievement_grants(
    id, definition_id, subject_type, subject_id, group_id,
    origin_match_fact_id, metric_value, operation_id, occurred_at,
    is_first, sequence_count, occurrence_metadata
  ) values (
    saved_grant_id, definition.id, definition.subject_type, target_subject_id,
    target_group_id, target_origin_match_fact_id, target_metric_value,
    md5(
      'achievement-grant:' || definition.id::text || ':' || target_subject_id::text
      || ':' || target_origin_match_fact_id::text
    )::uuid,
    source_fact.played_at, occurrence_is_first, occurrence_sequence,
    jsonb_build_object(
      'displayTitle', occurrence_title,
      'repeatable', definition.repeatable,
      'sourceKind', source_fact.source_kind,
      'sourceMatchId', source_fact.source_match_id
    )
  );

  perform private.pachanga_progression_record_event_v1(
    md5('achievement-event:' || saved_grant_id::text)::uuid,
    'achievement_awarded', target_group_id,
    case when definition.subject_type = 'player' then target_subject_id else null end,
    target_origin_match_fact_id, saved_grant_id, null,
    jsonb_build_object(
      'achievementKey', definition.achievement_key,
      'displayTitle', occurrence_title,
      'isFirst', occurrence_is_first,
      'sequenceCount', occurrence_sequence,
      'metricValue', target_metric_value,
      'threshold', definition.threshold,
      'rarity', definition.rarity,
      'rewardEligible', definition.subject_type = 'team'
    )
  );

  if definition.subject_type = 'team' then
    perform private.pachanga_ensure_collective_boxes_v2(saved_grant_id);
  end if;
  return saved_grant_id;
end;
$$;

create or replace function private.pachanga_evaluate_achievements_v1(
  target_group_id uuid,
  target_match_scope text,
  target_origin_match_fact_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  match_fact public.pachanga_progression_match_facts%rowtype;
  definition record;
  player record;
  metric integer;
  qualifies boolean;
  before_id uuid;
  after_id uuid;
  awarded integer := 0;
  recipient record;
  personal_count integer;
  box_count integer;
begin
  select * into match_fact
  from public.pachanga_progression_match_facts facts
  where facts.id = target_origin_match_fact_id
    and facts.group_id = target_group_id
    and facts.match_scope = target_match_scope
    and facts.state = 'active';
  if not found then return 0; end if;

  for definition in
    select definitions.*
    from public.pachanga_achievement_definitions definitions
    where definitions.active
      and definitions.subject_type = 'team'
      and definitions.match_scope = target_match_scope
      and coalesce(definitions.parameters ->> 'ruleKind', '') <> 'team_match_goals'
    order by definitions.achievement_key, definitions.version
  loop
    metric := private.pachanga_achievement_metric_v1(definition.id, target_group_id);
    qualifies := case definition.parameters ->> 'ruleKind'
      when 'team_match_win' then match_fact.outcome = 'win'
      when 'team_match_clean_sheet' then match_fact.clean_sheet and match_fact.goals_for > 0
      when 'team_match_big_win' then match_fact.big_win
      when 'team_match_close_win' then match_fact.close_win
      else metric >= definition.threshold end;
    if not qualifies then continue; end if;

    select grants.id into before_id
    from public.pachanga_achievement_grants grants
    where grants.definition_id = definition.id
      and grants.subject_type = 'team'
      and grants.subject_id = target_group_id
      and grants.origin_match_fact_id = target_origin_match_fact_id
      and grants.state = 'active';
    after_id := private.pachanga_award_achievement_v1(
      definition.id, target_group_id, target_group_id,
      target_origin_match_fact_id, greatest(metric, definition.threshold)
    );
    if before_id is null and after_id is not null then awarded := awarded + 1; end if;
    before_id := null;
    after_id := null;
  end loop;

  select definitions.* into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.active
    and definitions.subject_type = 'team'
    and definitions.match_scope = target_match_scope
    and definitions.parameters ->> 'ruleKind' = 'team_match_goals'
    and (
      (definitions.parameters ? 'goalsExact'
        and (definitions.parameters ->> 'goalsExact')::integer = match_fact.goals_for)
      or (definitions.parameters ? 'goalsMinimum'
        and (definitions.parameters ->> 'goalsMinimum')::integer <= match_fact.goals_for)
    )
  order by definitions.threshold desc, definitions.achievement_key
  limit 1;
  if found then
    select grants.id into before_id
    from public.pachanga_achievement_grants grants
    where grants.definition_id = definition.id
      and grants.subject_id = target_group_id
      and grants.origin_match_fact_id = target_origin_match_fact_id
      and grants.state = 'active';
    after_id := private.pachanga_award_achievement_v1(
      definition.id, target_group_id, target_group_id,
      target_origin_match_fact_id, match_fact.goals_for
    );
    if before_id is null and after_id is not null then awarded := awarded + 1; end if;
    before_id := null;
    after_id := null;
  end if;

  for player in
    select player_facts.player_profile_id, player_facts.goals
    from public.pachanga_progression_player_match_facts player_facts
    where player_facts.match_fact_id = target_origin_match_fact_id
      and player_facts.group_id = target_group_id
      and player_facts.state = 'active'
    order by player_facts.player_profile_id
  loop
    select definitions.* into definition
    from public.pachanga_achievement_definitions definitions
    where definitions.active
      and definitions.subject_type = 'player'
      and definitions.match_scope = target_match_scope
      and definitions.parameters ->> 'ruleKind' = 'player_match_goals'
      and (
        (definitions.parameters ? 'goalsExact'
          and (definitions.parameters ->> 'goalsExact')::integer = player.goals)
        or (definitions.parameters ? 'goalsMinimum'
          and (definitions.parameters ->> 'goalsMinimum')::integer <= player.goals)
      )
    order by definitions.threshold desc, definitions.achievement_key
    limit 1;
    if found then
      select grants.id into before_id
      from public.pachanga_achievement_grants grants
      where grants.definition_id = definition.id
        and grants.subject_id = player.player_profile_id
        and grants.origin_match_fact_id = target_origin_match_fact_id
        and grants.state = 'active';
      after_id := private.pachanga_award_achievement_v1(
        definition.id, player.player_profile_id, target_group_id,
        target_origin_match_fact_id,
        private.pachanga_achievement_metric_v1(definition.id, player.player_profile_id)
      );
      if before_id is null and after_id is not null then awarded := awarded + 1; end if;
      before_id := null;
      after_id := null;
    end if;

    for definition in
      select definitions.*
      from public.pachanga_achievement_definitions definitions
      where definitions.active
        and definitions.subject_type = 'player'
        and definitions.match_scope = target_match_scope
        and coalesce(definitions.parameters ->> 'ruleKind', '') <> 'player_match_goals'
      order by definitions.achievement_key, definitions.version
    loop
      metric := private.pachanga_achievement_metric_v1(
        definition.id, player.player_profile_id
      );
      if metric < definition.threshold then continue; end if;
      select grants.id into before_id
      from public.pachanga_achievement_grants grants
      where grants.definition_id = definition.id
        and grants.subject_id = player.player_profile_id
        and grants.state = 'active'
      order by grants.occurred_at, grants.id
      limit 1;
      after_id := private.pachanga_award_achievement_v1(
        definition.id, player.player_profile_id, target_group_id,
        target_origin_match_fact_id, metric
      );
      if before_id is null and after_id is not null then awarded := awarded + 1; end if;
      before_id := null;
      after_id := null;
    end loop;
  end loop;

  if coalesce(current_setting('pachangas.progression_backfill', true), '') <> 'on' then
    for recipient in
      select recipients.user_id, count(*)::integer as pending_boxes
      from public.pachanga_reward_recipients recipients
      where recipients.match_fact_id = target_origin_match_fact_id
        and recipients.group_id = target_group_id
        and recipients.status = 'pending'
      group by recipients.user_id
      order by recipients.user_id
    loop
      perform private.pachanga_notify_v1(
        recipient.user_id,
        'postmatch_reward_boxes',
        'Tus premios del partido están listos',
        'Premios pendientes: ' || recipient.pending_boxes::text || '.',
        '/equipo/identidad?grupo=' || target_group_id::text || '&rewards=pending',
        jsonb_build_object(
          'groupId', target_group_id,
          'matchFactId', target_origin_match_fact_id,
          'pendingRewardCount', recipient.pending_boxes
        ),
        'postmatch-rewards:' || target_origin_match_fact_id::text || ':' || recipient.user_id::text
      );
    end loop;

    for recipient in
      select profiles.user_id, profiles.id as player_profile_id
      from public.pachanga_progression_player_match_facts player_facts
      join public.pachanga_player_profiles profiles
        on profiles.id = player_facts.player_profile_id
      where player_facts.match_fact_id = target_origin_match_fact_id
        and player_facts.group_id = target_group_id
        and player_facts.state = 'active'
        and profiles.user_id is not null
      order by profiles.user_id
    loop
      select count(*)::integer into personal_count
      from public.pachanga_achievement_grants grants
      where grants.subject_type = 'player'
        and grants.subject_id = recipient.player_profile_id
        and grants.origin_match_fact_id = target_origin_match_fact_id
        and grants.state = 'active';
      select count(*)::integer into box_count
      from public.pachanga_reward_recipients boxes
      where boxes.user_id = recipient.user_id
        and boxes.match_fact_id = target_origin_match_fact_id
        and boxes.status = 'pending';
      if personal_count > 0 and box_count = 0 then
        perform private.pachanga_notify_v1(
          recipient.user_id,
          'personal_achievement',
          'Nuevos logros personales',
          'Reconocimientos del partido: ' || personal_count::text || '.',
          '/equipo/identidad?grupo=' || target_group_id::text || '&achievements=latest',
          jsonb_build_object(
            'groupId', target_group_id,
            'matchFactId', target_origin_match_fact_id,
            'personalAchievementCount', personal_count
          ),
          'postmatch-personal:' || target_origin_match_fact_id::text || ':' || recipient.user_id::text
        );
      end if;
    end loop;
  end if;
  return awarded;
end;
$$;

create or replace function private.pachanga_reward_recipient_snapshot_v1(
  target_reward_grant_id uuid,
  target_user_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'boxId', recipients.box_id,
    'rewardGrantId', rewards.id,
    'rewardKind', case when recipients.status = 'opened' then rewards.reward_kind else 'collective_box' end,
    'rewardKey', case when recipients.status = 'opened' then rewards.reward_key else recipients.reward_reference end,
    'rewardPayload', case when recipients.status = 'opened' then recipients.revealed_payload else null end,
    'rewardState', rewards.state,
    'status', recipients.status,
    'recipientRevision', recipients.revision,
    'generatedAt', recipients.snapshot_at,
    'openedAt', recipients.opened_at,
    'rewardGrantedAt', recipients.reward_granted_at,
    'matchFactId', recipients.match_fact_id,
    'groupId', recipients.group_id,
    'sourceCorrection', recipients.source_correction,
    'achievement', jsonb_build_object(
      'grantId', grants.id,
      'key', definitions.achievement_key,
      'title', coalesce(grants.occurrence_metadata ->> 'displayTitle', definitions.title),
      'description', definitions.description,
      'scope', definitions.match_scope,
      'subjectType', definitions.subject_type,
      'rarity', definitions.rarity,
      'isFirst', grants.is_first,
      'sequenceCount', grants.sequence_count,
      'occurredAt', grants.occurred_at,
      'awardedAt', grants.awarded_at
    )
  ))
  from public.pachanga_reward_recipients recipients
  join public.pachanga_reward_grants rewards
    on rewards.id = recipients.reward_grant_id
  join public.pachanga_achievement_grants grants
    on grants.id = recipients.achievement_grant_id
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where recipients.reward_grant_id = target_reward_grant_id
    and recipients.user_id = target_user_id;
$$;

create or replace function private.pachanga_reward_box_snapshot_v2(
  target_box_id uuid,
  target_user_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select private.pachanga_reward_recipient_snapshot_v1(
    recipients.reward_grant_id, target_user_id
  )
  from public.pachanga_reward_recipients recipients
  where recipients.box_id = target_box_id
    and recipients.user_id = target_user_id;
$$;

create or replace function public.open_pachanga_reward_box_v2(
  target_box_id uuid,
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
  selected public.pachanga_reward_recipients%rowtype;
  reward public.pachanga_reward_grants%rowtype;
  grant_row public.pachanga_achievement_grants%rowtype;
  sealed jsonb;
  stored_actor uuid;
  stored_response jsonb;
  saved_sequence bigint;
  response jsonb;
  was_already_opened boolean := false;
begin
  if auth.uid() is null or open_pachanga_reward_box_v2.operation_id is null
    or target_box_id is null or expected_revision is null then
    raise exception 'Authentication, box, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'reward-box-open:' || target_box_id::text, 0
  ));
  select receipts.actor_user_id, receipts.response
  into stored_actor, stored_response
  from public.pachanga_reward_open_receipts receipts
  where receipts.operation_id = open_pachanga_reward_box_v2.operation_id;
  if found then
    if stored_actor <> auth.uid() then raise exception 'Operation belongs to another actor'; end if;
    return stored_response;
  end if;

  select * into selected
  from public.pachanga_reward_recipients recipients
  where recipients.box_id = target_box_id
    and recipients.user_id = auth.uid()
  for update;
  if not found then raise exception 'Reward box not found'; end if;

  select * into reward
  from public.pachanga_reward_grants rewards
  where rewards.id = selected.reward_grant_id;
  select * into grant_row
  from public.pachanga_achievement_grants grants
  where grants.id = selected.achievement_grant_id;
  if selected.status = 'revoked' or grant_row.state = 'revoked' then
    raise exception 'Reward box is no longer active';
  end if;

  if selected.status = 'opened' then
    was_already_opened := true;
    select states.server_sequence into saved_sequence
    from public.pachanga_progression_user_state states
    where states.user_id = auth.uid();
  else
    if reward.state <> 'active' then raise exception 'Reward box is no longer active'; end if;
    if selected.revision <> expected_revision then
      raise exception 'Reward box revision is newer. Reload the confirmed state.' using errcode = 'PT409';
    end if;
    select contents.reward_payload into sealed
    from private.pachanga_reward_box_contents contents
    where contents.box_id = selected.box_id
    for update;
    if sealed is null then raise exception 'Reward box content is unavailable'; end if;

    update public.pachanga_reward_recipients recipients
    set status = 'opened', opened_at = clock_timestamp(),
        reward_granted_at = clock_timestamp(), revealed_payload = sealed,
        revision = recipients.revision + 1
    where recipients.box_id = selected.box_id
    returning * into selected;

    if reward.reward_kind = 'team_cosmetic' then
      insert into public.pachanga_team_cosmetic_inventory(
        group_id, cosmetic_key, source_grant_id
      ) values (
        reward.group_id, reward.reward_key, grant_row.id
      ) on conflict (group_id, cosmetic_key) do update set
        source_grant_id = excluded.source_grant_id,
        state = 'unlocked', unlocked_at = clock_timestamp(),
        revoked_at = null,
        revision = public.pachanga_team_cosmetic_inventory.revision + 1;
    end if;

    saved_sequence := private.pachanga_progression_record_event_v1(
      md5('reward-box-opened:' || selected.box_id::text)::uuid,
      'reward_opened', reward.group_id, selected.player_profile_id,
      selected.match_fact_id, selected.achievement_grant_id, reward.id,
      jsonb_build_object(
        'boxId', selected.box_id,
        'rewardKind', reward.reward_kind,
        'rewardReference', selected.reward_reference
      )
    );
  end if;

  response := private.pachanga_reward_box_snapshot_v2(selected.box_id, selected.user_id)
    || jsonb_build_object(
      'operationId', open_pachanga_reward_box_v2.operation_id,
      'expectedRevision', expected_revision,
      'confirmedRevision', selected.revision,
      'serverSequence', coalesce(saved_sequence, 0),
      'confirmedAt', clock_timestamp(),
      'alreadyOpened', was_already_opened
    );
  insert into public.pachanga_reward_open_receipts(
    operation_id, reward_grant_id, actor_user_id, expected_revision,
    result_revision, server_sequence, response, client_metadata, box_id
  ) values (
    open_pachanga_reward_box_v2.operation_id,
    selected.reward_grant_id, auth.uid(), expected_revision,
    selected.revision, coalesce(saved_sequence, 0), response,
    case when jsonb_typeof(client_metadata) = 'object' then client_metadata else '{}'::jsonb end,
    selected.box_id
  );
  return response;
end;
$$;

create or replace function public.open_pachanga_reward_v1(
  target_reward_grant_id uuid,
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
  target_box_id uuid;
begin
  select recipients.box_id into target_box_id
  from public.pachanga_reward_recipients recipients
  where recipients.reward_grant_id = target_reward_grant_id
    and recipients.user_id = auth.uid();
  if target_box_id is null then raise exception 'Reward box not found'; end if;
  return public.open_pachanga_reward_box_v2(
    target_box_id, open_pachanga_reward_v1.operation_id,
    expected_revision, client_metadata
  );
end;
$$;

revoke all on function public.open_pachanga_reward_box_v2(uuid, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.open_pachanga_reward_box_v2(uuid, uuid, bigint, jsonb)
  to authenticated;

create or replace function private.pachanga_repeatable_grant_still_qualifies_v2(
  target_grant_id uuid
)
returns boolean
language plpgsql
security definer
stable
set search_path = pg_catalog
as $$
declare
  source record;
  player_goals integer;
begin
  select grants.subject_type, grants.subject_id, grants.group_id,
    grants.origin_match_fact_id, definitions.parameters,
    facts.state as fact_state, facts.outcome, facts.goals_for,
    facts.clean_sheet, facts.big_win, facts.close_win
  into source
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  join public.pachanga_progression_match_facts facts
    on facts.id = grants.origin_match_fact_id
  where grants.id = target_grant_id;
  if not found or source.fact_state <> 'active' then return false; end if;

  if source.parameters ->> 'ruleKind' = 'player_match_goals' then
    select player_facts.goals into player_goals
    from public.pachanga_progression_player_match_facts player_facts
    where player_facts.match_fact_id = source.origin_match_fact_id
      and player_facts.player_profile_id = source.subject_id
      and player_facts.group_id = source.group_id
      and player_facts.state = 'active';
    if player_goals is null then return false; end if;
    return case
      when source.parameters ? 'goalsExact'
        then player_goals = (source.parameters ->> 'goalsExact')::integer
      when source.parameters ? 'goalsMinimum'
        then player_goals >= (source.parameters ->> 'goalsMinimum')::integer
      else false end;
  end if;

  return case source.parameters ->> 'ruleKind'
    when 'team_match_win' then source.outcome = 'win'
    when 'team_match_clean_sheet' then source.clean_sheet and source.goals_for > 0
    when 'team_match_big_win' then source.big_win
    when 'team_match_close_win' then source.close_win
    when 'team_match_goals' then case
      when source.parameters ? 'goalsExact'
        then source.goals_for = (source.parameters ->> 'goalsExact')::integer
      when source.parameters ? 'goalsMinimum'
        then source.goals_for >= (source.parameters ->> 'goalsMinimum')::integer
      else false end
    else true end;
end;
$$;

create or replace function private.pachanga_revoke_achievement_grant_v1(
  target_grant_id uuid,
  target_reason text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_achievement_grants%rowtype;
  definition public.pachanga_achievement_definitions%rowtype;
  reward public.pachanga_reward_grants%rowtype;
  recipient record;
  opened_count integer := 0;
  normalized_reason text;
begin
  normalized_reason := left(
    coalesce(nullif(trim(target_reason), ''), 'canonical_fact_revoked'), 500
  );
  select * into selected
  from public.pachanga_achievement_grants grants
  where grants.id = target_grant_id
  for update;
  if not found or selected.state = 'revoked' then return false; end if;
  select * into definition
  from public.pachanga_achievement_definitions definitions
  where definitions.id = selected.definition_id;

  update public.pachanga_achievement_grants grants
  set state = 'revoked', revoked_at = clock_timestamp(),
      revoked_reason = normalized_reason
  where grants.id = selected.id;

  select * into reward
  from public.pachanga_reward_grants rewards
  where rewards.achievement_grant_id = selected.id
  for update;
  if found then
    select count(*)::integer into opened_count
    from public.pachanga_reward_recipients recipients
    where recipients.reward_grant_id = reward.id
      and recipients.status = 'opened';

    for recipient in
      update public.pachanga_reward_recipients recipients
      set status = case when recipients.status = 'pending' then 'revoked' else recipients.status end,
          revoked_at = case when recipients.status = 'pending' then clock_timestamp() else recipients.revoked_at end,
          revoked_reason = case when recipients.status = 'pending' then normalized_reason else recipients.revoked_reason end,
          source_correction = case when recipients.status = 'opened'
            then jsonb_build_object(
              'state', 'source_revoked', 'reason', normalized_reason,
              'recordedAt', clock_timestamp()
            ) else recipients.source_correction end,
          revision = recipients.revision + 1
      where recipients.reward_grant_id = reward.id
        and recipients.status in ('pending', 'opened')
      returning recipients.user_id
    loop
      perform private.pachanga_progression_bump_user_v1(recipient.user_id);
    end loop;

    update public.pachanga_reward_grants rewards
    set state = case when opened_count > 0 then rewards.state else 'revoked' end,
        revoked_at = case when opened_count > 0 then rewards.revoked_at else clock_timestamp() end,
        payload = rewards.payload || jsonb_build_object(
          'sourceCorrection', jsonb_build_object(
            'state', 'source_revoked', 'reason', normalized_reason,
            'openedBoxesPreserved', opened_count
          )
        )
    where rewards.id = reward.id;

    -- A granted reward is never clawed back. If no participant opened any box,
    -- pending boxes and any prematurely migrated cosmetic can be revoked safely.
    if opened_count = 0 and reward.reward_kind = 'team_cosmetic' and not exists (
      select 1
      from public.pachanga_reward_grants active_rewards
      join public.pachanga_achievement_grants active_grants
        on active_grants.id = active_rewards.achievement_grant_id
      join public.pachanga_reward_recipients opened_recipients
        on opened_recipients.reward_grant_id = active_rewards.id
       and opened_recipients.status = 'opened'
      where active_rewards.group_id = reward.group_id
        and active_rewards.reward_key = reward.reward_key
        and active_rewards.reward_kind = 'team_cosmetic'
        and active_grants.state = 'active'
    ) then
      update public.pachanga_team_cosmetic_inventory inventory
      set state = 'revoked', revoked_at = clock_timestamp(),
          revision = inventory.revision + 1
      where inventory.group_id = reward.group_id
        and inventory.cosmetic_key = reward.reward_key;
    end if;

    perform private.pachanga_progression_record_event_v1(
      md5('reward-revoked:' || reward.id::text)::uuid,
      'reward_revoked', selected.group_id,
      case when selected.subject_type = 'player' then selected.subject_id else null end,
      selected.origin_match_fact_id, selected.id, reward.id,
      jsonb_build_object(
        'reason', normalized_reason,
        'rewardKey', reward.reward_key,
        'openedBoxesPreserved', opened_count
      )
    );
  end if;

  perform private.pachanga_progression_record_event_v1(
    md5('achievement-revoked:' || selected.id::text)::uuid,
    'achievement_revoked', selected.group_id,
    case when selected.subject_type = 'player' then selected.subject_id else null end,
    selected.origin_match_fact_id, selected.id, null,
    jsonb_build_object('reason', normalized_reason, 'achievementKey', definition.achievement_key)
  );
  return true;
end;
$$;

create or replace function private.pachanga_reconcile_subject_achievements_v1(
  target_subject_type text,
  target_subject_id uuid,
  target_match_scope text,
  target_reason text
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  grant_row record;
  metric integer;
  should_revoke boolean;
  revoked integer := 0;
begin
  for grant_row in
    select grants.id, grants.definition_id, grants.origin_match_fact_id,
      definitions.threshold, definitions.repeatable, match_facts.state as fact_state
    from public.pachanga_achievement_grants grants
    join public.pachanga_achievement_definitions definitions
      on definitions.id = grants.definition_id
    join public.pachanga_progression_match_facts match_facts
      on match_facts.id = grants.origin_match_fact_id
    where grants.subject_type = target_subject_type
      and grants.subject_id = target_subject_id
      and grants.state = 'active'
      and definitions.match_scope = target_match_scope
    order by grants.occurred_at, grants.id
  loop
    if grant_row.repeatable then
      should_revoke := not private.pachanga_repeatable_grant_still_qualifies_v2(
        grant_row.id
      );
    else
      metric := private.pachanga_achievement_metric_v1(
        grant_row.definition_id, target_subject_id
      );
      should_revoke := metric < grant_row.threshold;
    end if;
    if should_revoke
      and private.pachanga_revoke_achievement_grant_v1(grant_row.id, target_reason) then
      revoked := revoked + 1;
    end if;
  end loop;
  return revoked;
end;
$$;

create or replace function public.get_pachanga_progression_snapshot_v1(
  target_group_id uuid
)
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
    'personalStats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scope', stats.match_scope,
        'appearances', stats.appearances,
        'wins', stats.wins,
        'draws', stats.draws,
        'losses', stats.losses,
        'goals', stats.goals,
        'braces', stats.braces,
        'hatTricks', stats.hat_tricks,
        'pokers', stats.pokers,
        'repokers', stats.repokers,
        'doubleHatTricks', stats.double_hat_tricks,
        'maxWinStreak', stats.max_win_streak,
        'maxUnbeatenStreak', stats.max_unbeaten_streak,
        'revision', stats.revision,
        'updatedAt', stats.updated_at
      ) order by stats.match_scope)
      from public.pachanga_player_progression_stats stats
      where stats.player_profile_id = current_profile_id
    ), '[]'::jsonb),
    'teamAchievements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantId', grants.id,
        'key', definitions.achievement_key,
        'title', coalesce(grants.occurrence_metadata ->> 'displayTitle', definitions.title),
        'description', definitions.description,
        'scope', definitions.match_scope,
        'category', definitions.category,
        'rarity', definitions.rarity,
        'metricValue', grants.metric_value,
        'threshold', definitions.threshold,
        'repeatable', definitions.repeatable,
        'state', grants.state,
        'awardedAt', grants.awarded_at,
        'occurredAt', grants.occurred_at,
        'isFirst', grants.is_first,
        'sequenceCount', grants.sequence_count,
        'matchFactId', grants.origin_match_fact_id,
        'revokedAt', grants.revoked_at
      ) order by grants.occurred_at desc, facts.server_sequence desc, grants.id desc)
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions definitions
        on definitions.id = grants.definition_id
      join public.pachanga_progression_match_facts facts
        on facts.id = grants.origin_match_fact_id
      where grants.group_id = target_group_id
        and grants.subject_type = 'team'
    ), '[]'::jsonb),
    'personalAchievements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantId', grants.id,
        'key', definitions.achievement_key,
        'title', coalesce(grants.occurrence_metadata ->> 'displayTitle', definitions.title),
        'description', definitions.description,
        'scope', definitions.match_scope,
        'category', definitions.category,
        'rarity', definitions.rarity,
        'rewardKind', 'none',
        'rewardKey', null,
        'repeatable', definitions.repeatable,
        'state', grants.state,
        'awardedAt', grants.awarded_at,
        'occurredAt', grants.occurred_at,
        'isFirst', grants.is_first,
        'sequenceCount', grants.sequence_count,
        'matchFactId', grants.origin_match_fact_id,
        'revokedAt', grants.revoked_at
      ) order by grants.occurred_at desc, facts.server_sequence desc, grants.id desc)
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions definitions
        on definitions.id = grants.definition_id
      join public.pachanga_progression_match_facts facts
        on facts.id = grants.origin_match_fact_id
      where grants.subject_type = 'player'
        and grants.subject_id = current_profile_id
    ), '[]'::jsonb),
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
        'occurrenceCount', catalog.occurrence_count,
        'progressPercent', least(100,
          floor(catalog.current_value * 100.0 / catalog.threshold)::integer),
        'unlocked', catalog.occurrence_count > 0,
        'repeatable', catalog.repeatable,
        'grantId', catalog.grant_id,
        'awardedAt', catalog.occurred_at,
        'rewardKind', 'none',
        'rewardKey', null
      ) order by catalog.match_scope, catalog.category,
        catalog.threshold, catalog.achievement_key)
      from (
        select definitions.achievement_key, definitions.title,
          definitions.description, definitions.match_scope,
          definitions.category, definitions.rarity, definitions.threshold,
          definitions.repeatable,
          case when definitions.repeatable then count(grants.id)::integer
            else private.pachanga_achievement_metric_v1(
              definitions.id, current_profile_id
            ) end as current_value,
          count(grants.id)::integer as occurrence_count,
          (array_agg(grants.id order by grants.occurred_at desc, grants.id desc)
            filter (where grants.id is not null))[1] as grant_id,
          max(grants.occurred_at) as occurred_at
        from public.pachanga_achievement_definitions definitions
        left join public.pachanga_achievement_grants grants
          on grants.definition_id = definitions.id
         and grants.subject_type = 'player'
         and grants.subject_id = current_profile_id
         and grants.state = 'active'
        where definitions.active
          and definitions.subject_type = 'player'
        group by definitions.id, definitions.achievement_key,
          definitions.title, definitions.description, definitions.match_scope,
          definitions.category, definitions.rarity, definitions.threshold,
          definitions.repeatable
      ) catalog
    ), '[]'::jsonb),
    'rewards', coalesce((
      select jsonb_agg(private.pachanga_reward_box_snapshot_v2(
        recipients.box_id, auth.uid()
      ) order by facts.played_at, facts.server_sequence,
        grants.sequence_count, recipients.box_id)
      from public.pachanga_reward_recipients recipients
      join public.pachanga_achievement_grants grants
        on grants.id = recipients.achievement_grant_id
      join public.pachanga_progression_match_facts facts
        on facts.id = recipients.match_fact_id
      where recipients.user_id = auth.uid()
        and recipients.group_id = target_group_id
        and recipients.status in ('pending', 'opened', 'revoked')
    ), '[]'::jsonb),
    'updatedAt', clock_timestamp()
  );
end;
$$;

revoke all on function public.get_pachanga_progression_snapshot_v1(uuid)
  from public, anon;
grant execute on function public.get_pachanga_progression_snapshot_v1(uuid)
  to authenticated;

-- Rebuild from canonical facts in authoritative order. Notifications are
-- intentionally suppressed because historical awards are migration state.
do $$
declare
  player_scope record;
  fact record;
  team_grant record;
  invalid_recipient record;
begin
  perform set_config('pachangas.progression_backfill', 'on', true);

  for player_scope in
    select distinct player_facts.player_profile_id, facts.match_scope
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_progression_match_facts facts
      on facts.id = player_facts.match_fact_id
    where player_facts.state = 'active' and facts.state = 'active'
    order by player_facts.player_profile_id, facts.match_scope
  loop
    perform private.pachanga_rebuild_player_progression_stats_v1(
      player_scope.player_profile_id, player_scope.match_scope
    );
  end loop;

  for fact in
    select facts.id, facts.group_id, facts.match_scope
    from public.pachanga_progression_match_facts facts
    where facts.state = 'active'
    order by facts.played_at, facts.server_sequence, facts.id
  loop
    perform private.pachanga_evaluate_achievements_v1(
      fact.group_id, fact.match_scope, fact.id
    );
  end loop;

  for team_grant in
    select grants.id
    from public.pachanga_achievement_grants grants
    join public.pachanga_progression_match_facts facts
      on facts.id = grants.origin_match_fact_id
    where grants.subject_type = 'team'
      and grants.state = 'active'
      and facts.state = 'active'
    order by facts.played_at, facts.server_sequence, grants.id
  loop
    perform private.pachanga_ensure_collective_boxes_v2(team_grant.id);
  end loop;

  for invalid_recipient in
    select recipients.reward_grant_id, recipients.user_id,
      recipients.status, recipients.box_id
    from public.pachanga_reward_recipients recipients
    join public.pachanga_achievement_grants grants
      on grants.id = recipients.achievement_grant_id
    where grants.subject_type = 'team'
      and recipients.status in ('pending', 'opened')
      and not exists (
        select 1
        from public.pachanga_progression_player_match_facts player_facts
        join public.pachanga_player_profiles profiles
          on profiles.id = player_facts.player_profile_id
        where player_facts.match_fact_id = recipients.match_fact_id
          and player_facts.group_id = recipients.group_id
          and player_facts.state = 'active'
          and profiles.user_id = recipients.user_id
      )
  loop
    update public.pachanga_reward_recipients recipients
    set status = case when invalid_recipient.status = 'pending'
          then 'revoked' else recipients.status end,
        revoked_at = case when invalid_recipient.status = 'pending'
          then clock_timestamp() else recipients.revoked_at end,
        revoked_reason = case when invalid_recipient.status = 'pending'
          then 'not_a_canonical_match_participant' else recipients.revoked_reason end,
        source_correction = case when invalid_recipient.status = 'opened'
          then jsonb_build_object(
            'state', 'legacy_nonparticipant_reward_preserved',
            'recordedAt', clock_timestamp()
          ) else recipients.source_correction end,
        revision = recipients.revision + 1
    where recipients.box_id = invalid_recipient.box_id;
    perform private.pachanga_progression_bump_user_v1(invalid_recipient.user_id);
  end loop;

  update public.pachanga_team_cosmetic_inventory inventory
  set state = 'revoked', revoked_at = clock_timestamp(),
      revision = inventory.revision + 1
  where inventory.state = 'unlocked'
    and not exists (
      select 1
      from public.pachanga_reward_grants rewards
      join public.pachanga_reward_recipients recipients
        on recipients.reward_grant_id = rewards.id
      join public.pachanga_achievement_grants grants
        on grants.id = rewards.achievement_grant_id
      where rewards.group_id = inventory.group_id
        and rewards.reward_key = inventory.cosmetic_key
        and rewards.reward_kind = 'team_cosmetic'
        and grants.state = 'active'
        and recipients.status = 'opened'
    );

  perform set_config('pachangas.progression_backfill', 'off', true);
end;
$$;

with ranked as (
  select grants.id,
    row_number() over (
      partition by grants.subject_type, grants.subject_id, grants.definition_id
      order by grants.occurred_at, facts.server_sequence, grants.id
    )::integer as sequence_count
  from public.pachanga_achievement_grants grants
  join public.pachanga_progression_match_facts facts
    on facts.id = grants.origin_match_fact_id
  where grants.state = 'active'
)
update public.pachanga_achievement_grants grants
set sequence_count = ranked.sequence_count,
    is_first = ranked.sequence_count = 1,
    occurrence_metadata = grants.occurrence_metadata || jsonb_build_object(
      'displayTitle', private.pachanga_achievement_occurrence_title_v2(
        grants.definition_id, ranked.sequence_count = 1
      )
    )
from ranked
where ranked.id = grants.id;

revoke all on function private.pachanga_rebuild_player_progression_stats_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_achievement_metric_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_achievement_occurrence_title_v2(uuid, boolean)
  from public, anon, authenticated;
revoke all on function private.pachanga_ensure_collective_boxes_v2(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_award_achievement_v1(uuid, uuid, uuid, uuid, integer)
  from public, anon, authenticated;
revoke all on function private.pachanga_evaluate_achievements_v1(uuid, text, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_reward_recipient_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_reward_box_snapshot_v2(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_repeatable_grant_still_qualifies_v2(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_revoke_achievement_grant_v1(uuid, text)
  from public, anon, authenticated;
revoke all on function private.pachanga_reconcile_subject_achievements_v1(text, uuid, text, text)
  from public, anon, authenticated;

comment on table private.pachanga_reward_box_contents is
  'Server-only sealed reward payloads. Contents are revealed and granted atomically when the owning participant opens the box.';
comment on function public.open_pachanga_reward_box_v2(uuid, uuid, bigint, jsonb) is
  'Atomically and idempotently opens one participant reward box; the browser supplies only box id, operation id and expected revision.';
comment on function public.get_pachanga_progression_snapshot_v1(uuid) is
  'Canonical read model for team achievements, personal recognition occurrences and participant reward boxes.';
