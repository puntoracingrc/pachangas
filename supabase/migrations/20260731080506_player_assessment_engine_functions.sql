create or replace function public.pachanga_assessment_clamp(value numeric, min_value numeric, max_value numeric)
returns numeric
language sql
immutable
set search_path = public
as $$
  select least(max_value, greatest(min_value, coalesce(value, min_value)));
$$;

create or replace function public.pachanga_assessment_response_score(
  answers jsonb,
  question_id text,
  limit5 numeric default null,
  required boolean default false
)
returns numeric
language plpgsql
stable
set search_path = public
as $$
declare
  answer_value numeric;
begin
  if coalesce(answers ->> question_id, '') !~ '^[1-5]$' then
    if required then
      raise exception 'Assessment answer % is required', question_id;
    end if;
    return null;
  end if;

  answer_value := (answers ->> question_id)::numeric;
  if limit5 is not null then
    answer_value := answer_value - 0.5 * greatest(0::numeric, answer_value - limit5);
  end if;

  return 25 + 15 * (answer_value - 1);
end;
$$;

create or replace function public.pachanga_assessment_overall_weight(position_id text, attribute_id text)
returns numeric
language sql
immutable
set search_path = public
as $$
  select case position_id
    when 'centre_back' then case attribute_id when 'pace' then 0.15 when 'shooting' then 0.03 when 'passing' then 0.14 when 'dribbling' then 0.08 when 'defending' then 0.35 when 'physical' then 0.25 else 0 end
    when 'full_back' then case attribute_id when 'pace' then 0.22 when 'shooting' then 0.05 when 'passing' then 0.16 when 'dribbling' then 0.14 when 'defending' then 0.25 when 'physical' then 0.18 else 0 end
    when 'defensive_midfielder' then case attribute_id when 'pace' then 0.12 when 'shooting' then 0.05 when 'passing' then 0.24 when 'dribbling' then 0.15 when 'defending' then 0.25 when 'physical' then 0.19 else 0 end
    when 'attacking_midfielder' then case attribute_id when 'pace' then 0.15 when 'shooting' then 0.18 when 'passing' then 0.23 when 'dribbling' then 0.26 when 'defending' then 0.05 when 'physical' then 0.13 else 0 end
    when 'winger' then case attribute_id when 'pace' then 0.25 when 'shooting' then 0.18 when 'passing' then 0.16 when 'dribbling' then 0.28 when 'defending' then 0.03 when 'physical' then 0.1 else 0 end
    when 'striker' then case attribute_id when 'pace' then 0.2 when 'shooting' then 0.32 when 'passing' then 0.1 when 'dribbling' then 0.18 when 'defending' then 0.03 when 'physical' then 0.17 else 0 end
    else case attribute_id when 'pace' then 0.12 when 'shooting' then 0.1 when 'passing' then 0.28 when 'dribbling' then 0.22 when 'defending' then 0.13 when 'physical' then 0.15 else 0 end
  end;
$$;

create or replace function public.pachanga_assessment_mode_confidence(mode_shares jsonb, attribute_id text)
returns numeric
language sql
immutable
set search_path = public
as $$
  select coalesce(sum(
    share.percentage * case share.mode
      when 'futsal_5' then case attribute_id when 'pace' then 0.85 when 'shooting' then 0.9 when 'passing' then 0.95 when 'dribbling' then 0.98 when 'defending' then 0.88 when 'physical' then 0.75 else 1 end
      when 'football_11' then case attribute_id when 'pace' then 0.94 when 'shooting' then 0.92 when 'passing' then 0.94 when 'dribbling' then 0.88 when 'defending' then 0.98 when 'physical' then 0.98 else 1 end
      else case attribute_id when 'pace' then 0.93 when 'shooting' then 0.91 when 'passing' then 0.92 when 'dribbling' then 0.93 when 'defending' then 0.91 when 'physical' then 0.9 else 1 end
    end / 100
  ), 1)
  from jsonb_to_recordset(coalesce(mode_shares, '[]'::jsonb)) as share(mode text, percentage numeric);
$$;

create or replace function public.pachanga_assessment_app_position(position_id text)
returns text
language sql
immutable
set search_path = public
as $$
  select case position_id
    when 'centre_back' then 'Defensa central'
    when 'full_back' then 'Lateral derecho'
    when 'defensive_midfielder' then 'Pivote defensivo'
    when 'attacking_midfielder' then 'Mediapunta'
    when 'winger' then 'Extremo derecho'
    when 'striker' then 'Delantero / punta'
    else 'Mediocentro / pivote'
  end;
$$;

create or replace function public.pachanga_assessment_facets_from_attributes(attribute_ratings jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_build_object(
    'ritmo', public.pachanga_assessment_clamp((attribute_ratings ->> 'pace')::numeric / 10, 1, 10),
    'tiro', public.pachanga_assessment_clamp((attribute_ratings ->> 'shooting')::numeric / 10, 1, 10),
    'pase', public.pachanga_assessment_clamp((attribute_ratings ->> 'passing')::numeric / 10, 1, 10),
    'regate', public.pachanga_assessment_clamp((attribute_ratings ->> 'dribbling')::numeric / 10, 1, 10),
    'defensa', public.pachanga_assessment_clamp((attribute_ratings ->> 'defending')::numeric / 10, 1, 10),
    'fisico', public.pachanga_assessment_clamp((attribute_ratings ->> 'physical')::numeric / 10, 1, 10)
  );
$$;

create or replace function public.calculate_pachanga_initial_assessment(assessment_input jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  answers jsonb := coalesce(assessment_input -> 'answers', '{}'::jsonb);
  mode_shares jsonb := coalesce(assessment_input -> 'modeShares', '[]'::jsonb);
  calculated_at text := coalesce(assessment_input ->> 'calculatedAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  primary_position text := coalesce(nullif(assessment_input ->> 'primaryPosition', ''), 'central_midfielder');
  experience_level text := coalesce(nullif(assessment_input ->> 'experienceLevel', ''), 'regular_pachangas');
  frequency_id text := coalesce(nullif(assessment_input ->> 'frequency', ''), 'weekly');
  years_since_level numeric := greatest(0::numeric, coalesce(nullif(assessment_input ->> 'yearsSinceLevel', '')::numeric, 0));
  mode_total numeric;
  regular_mode_count integer;
  experience_score numeric;
  experience5 numeric;
  frequency5 numeric;
  frequency_adjustment numeric;
  experience_effective numeric;
  limit5 numeric;
  control_score numeric;
  carry_score numeric;
  pass_score numeric;
  decision_score numeric;
  finish_score numeric;
  movement_score numeric;
  defense_score numeric;
  duel_score numeric;
  pace_score numeric;
  physical_score numeric;
  c numeric;
  p numeric;
  a numeric;
  d numeric;
  v numeric;
  h numeric;
  raw_pace numeric;
  raw_shooting numeric;
  raw_passing numeric;
  raw_dribbling numeric;
  raw_defending numeric;
  raw_physical numeric;
  base_ratings jsonb;
  current_ratings jsonb;
  base_overall numeric;
  current_overall numeric;
  reliability numeric;
begin
  if primary_position not in ('centre_back', 'full_back', 'defensive_midfielder', 'central_midfielder', 'attacking_midfielder', 'winger', 'striker') then
    raise exception 'Invalid assessment position';
  end if;

  select coalesce(sum(share.percentage), 0), count(*) filter (where share.percentage > 0)
  into mode_total, regular_mode_count
  from jsonb_to_recordset(mode_shares) as share(mode text, percentage numeric)
  where share.mode in ('futsal_5', 'football_7', 'football_11')
    and share.percentage >= 0
    and share.percentage <= 100;

  if round(mode_total * 100) / 100 <> 100 then
    raise exception 'Assessment modalities must add up to 100';
  end if;

  experience_score := case experience_level
    when 'barely_played' then 25
    when 'occasional_pachangas' then 35
    when 'regular_pachangas' then 45
    when 'social_league' then 55
    when 'amateur_club' then 65
    when 'federated_club' then 75
    when 'national_semipro' then 85
    when 'professional' then 92
    else 45
  end;
  experience5 := case experience_level
    when 'barely_played' then 1
    when 'occasional_pachangas' then 1.5
    when 'regular_pachangas' then 2
    when 'social_league' then 2.75
    when 'amateur_club' then 3.5
    when 'federated_club' then 4.2
    when 'national_semipro' then 4.7
    when 'professional' then 5
    else 2
  end;
  frequency5 := case frequency_id
    when 'less_monthly' then 1
    when 'monthly_twice' then 2
    when 'weekly' then 3
    when 'two_three_weekly' then 4
    when 'four_plus_weekly' then 5
    else 3
  end;
  frequency_adjustment := case frequency_id
    when 'less_monthly' then -6
    when 'monthly_twice' then -3
    when 'weekly' then 0
    when 'two_three_weekly' then 2
    when 'four_plus_weekly' then 3
    else 0
  end;
  experience_effective := case
    when years_since_level <= 0 then experience_score
    else 50 + (experience_score - 50) * exp(-0.12 * years_since_level)
  end;
  limit5 := least(5::numeric, 1.2 + 0.55 * experience5 + 0.25 * frequency5);

  control_score := public.pachanga_assessment_response_score(answers, 'controlUnderPressure', limit5, true);
  carry_score := public.pachanga_assessment_response_score(answers, 'ballCarrying', limit5, true);
  pass_score := public.pachanga_assessment_response_score(answers, 'passingExecution', limit5, true);
  decision_score := public.pachanga_assessment_response_score(answers, 'decisionMaking', limit5, true);
  finish_score := public.pachanga_assessment_response_score(answers, 'finishing', limit5, true);
  movement_score := public.pachanga_assessment_response_score(answers, 'attackingMovement', limit5, true);
  defense_score := public.pachanga_assessment_response_score(answers, 'defensivePositioning', limit5, true);
  duel_score := public.pachanga_assessment_response_score(answers, 'defensiveDuels', limit5, true);
  pace_score := public.pachanga_assessment_response_score(answers, 'paceComparison', limit5, true);
  physical_score := public.pachanga_assessment_response_score(answers, 'physicalIntensity', limit5, true);

  c := 0.6 * control_score + 0.4 * carry_score;
  p := 0.6 * pass_score + 0.4 * decision_score;
  a := 0.7 * finish_score + 0.3 * movement_score;
  d := 0.6 * defense_score + 0.4 * duel_score;
  v := pace_score;
  h := physical_score;

  raw_pace := 0.7 * v + 0.15 * c + 0.1 * a + 0.05 * d;
  raw_shooting := 0.75 * a + 0.1 * c + 0.1 * p + 0.05 * v;
  raw_passing := 0.7 * p + 0.15 * c + 0.1 * d + 0.05 * a;
  raw_dribbling := 0.7 * c + 0.15 * v + 0.1 * p + 0.05 * a;
  raw_defending := 0.7 * d + 0.1 * h + 0.1 * p + 0.05 * v + 0.05 * c;
  raw_physical := 0.7 * h + 0.15 * v + 0.1 * d + 0.05 * a;

  base_ratings := jsonb_build_object(
    'pace', public.pachanga_assessment_clamp(0.82 * raw_pace + 0.18 * experience_effective, 20, 90),
    'shooting', public.pachanga_assessment_clamp(0.82 * raw_shooting + 0.18 * experience_effective, 20, 90),
    'passing', public.pachanga_assessment_clamp(0.82 * raw_passing + 0.18 * experience_effective, 20, 90),
    'dribbling', public.pachanga_assessment_clamp(0.82 * raw_dribbling + 0.18 * experience_effective, 20, 90),
    'defending', public.pachanga_assessment_clamp(0.82 * raw_defending + 0.18 * experience_effective, 20, 90),
    'physical', public.pachanga_assessment_clamp(0.82 * raw_physical + 0.18 * experience_effective, 20, 90)
  );
  current_ratings := jsonb_build_object(
    'pace', public.pachanga_assessment_clamp((base_ratings ->> 'pace')::numeric + frequency_adjustment, 0, 92),
    'shooting', public.pachanga_assessment_clamp((base_ratings ->> 'shooting')::numeric + 0.4 * frequency_adjustment, 0, 92),
    'passing', public.pachanga_assessment_clamp((base_ratings ->> 'passing')::numeric + 0.3 * frequency_adjustment, 0, 92),
    'dribbling', public.pachanga_assessment_clamp((base_ratings ->> 'dribbling')::numeric + 0.4 * frequency_adjustment, 0, 92),
    'defending', public.pachanga_assessment_clamp((base_ratings ->> 'defending')::numeric + 0.5 * frequency_adjustment, 0, 92),
    'physical', public.pachanga_assessment_clamp((base_ratings ->> 'physical')::numeric + frequency_adjustment, 0, 92)
  );

  base_overall := (base_ratings ->> 'pace')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'pace')
    + (base_ratings ->> 'shooting')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'shooting')
    + (base_ratings ->> 'passing')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'passing')
    + (base_ratings ->> 'dribbling')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'dribbling')
    + (base_ratings ->> 'defending')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'defending')
    + (base_ratings ->> 'physical')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'physical');
  current_overall := (current_ratings ->> 'pace')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'pace')
    + (current_ratings ->> 'shooting')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'shooting')
    + (current_ratings ->> 'passing')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'passing')
    + (current_ratings ->> 'dribbling')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'dribbling')
    + (current_ratings ->> 'defending')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'defending')
    + (current_ratings ->> 'physical')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'physical');
  reliability := public.pachanga_assessment_clamp(20 + 15 * ((experience5 - 1) / 4) + 10 * ((frequency5 - 1) / 4) + 5 * least(2, greatest(0, regular_mode_count - 1)), 20, 55);

  return jsonb_build_object(
    'kind', 'initial',
    'engineVersion', 'football-rating-v1',
    'questionnaireVersion', 'initial-test-v1',
    'calculatedAt', calculated_at,
    'primaryPosition', primary_position,
    'position', public.pachanga_assessment_app_position(primary_position),
    'modeShares', mode_shares,
    'baseRatings', base_ratings,
    'currentRatings', current_ratings,
    'baseOverall', base_overall,
    'currentOverall', current_overall,
    'rating', public.pachanga_assessment_clamp(base_overall / 10, 1, 10),
    'facets', public.pachanga_assessment_facets_from_attributes(base_ratings),
    'reliability', reliability,
    'technicalComposites', jsonb_build_object('C', c, 'P', p, 'A', a, 'D', d, 'V', v, 'H', h)
  );
end;
$$;

create or replace function public.calculate_pachanga_advanced_assessment(assessment_input jsonb, initial_result jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  answers jsonb := coalesce(assessment_input -> 'answers', '{}'::jsonb);
  calculated_at text := coalesce(assessment_input ->> 'calculatedAt', to_char(now() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  primary_position text := coalesce(initial_result ->> 'primaryPosition', 'central_midfielder');
  initial_ratings jsonb := coalesce(initial_result -> 'baseRatings', '{}'::jsonb);
  initial_reliability numeric := coalesce(nullif(initial_result ->> 'reliability', '')::numeric, 35);
  entry record;
  score numeric;
  weights jsonb;
  total_weight jsonb := '{"pace":4,"shooting":4,"passing":4,"dribbling":4,"defending":4,"physical":4}'::jsonb;
  weighted_score jsonb;
  final_ratings jsonb := '{}'::jsonb;
  attribute_id text;
  weight numeric;
  calculated_value numeric;
  coverage numeric;
  max_delta numeric;
  initial_value numeric;
  completed_count integer := 0;
  base_overall numeric;
  reliability numeric;
begin
  weighted_score := jsonb_build_object(
    'pace', 4 * coalesce(nullif(initial_ratings ->> 'pace', '')::numeric, 50),
    'shooting', 4 * coalesce(nullif(initial_ratings ->> 'shooting', '')::numeric, 50),
    'passing', 4 * coalesce(nullif(initial_ratings ->> 'passing', '')::numeric, 50),
    'dribbling', 4 * coalesce(nullif(initial_ratings ->> 'dribbling', '')::numeric, 50),
    'defending', 4 * coalesce(nullif(initial_ratings ->> 'defending', '')::numeric, 50),
    'physical', 4 * coalesce(nullif(initial_ratings ->> 'physical', '')::numeric, 50)
  );

  for entry in
    select key, value
    from jsonb_each(answers)
  loop
    if coalesce(entry.value #>> '{}', '') !~ '^[1-5]$' then
      continue;
    end if;

    completed_count := completed_count + 1;
    score := 25 + 15 * ((entry.value #>> '{}')::numeric - 1);
    weights := case
      when entry.key like 'TEC-%' then '{"dribbling":1,"passing":0.25}'::jsonb
      when entry.key like 'PAS-%' then '{"passing":1,"dribbling":0.15}'::jsonb
      when entry.key like 'TIR-%' then '{"shooting":1,"pace":0.15,"dribbling":0.1}'::jsonb
      when entry.key like 'DEF-%' then '{"defending":1,"physical":0.15}'::jsonb
      when entry.key like 'RIT-%' then '{"pace":1,"physical":0.2}'::jsonb
      when entry.key like 'FIS-%' then '{"physical":1,"pace":0.2}'::jsonb
      when entry.key like 'INT-%' then '{"passing":0.55,"defending":0.35,"dribbling":0.2}'::jsonb
      when entry.key like 'MOD-F5-%' then '{"dribbling":0.45,"passing":0.35,"pace":0.25,"shooting":0.2}'::jsonb
      when entry.key like 'MOD-F7-%' then '{"passing":0.35,"pace":0.3,"defending":0.3,"physical":0.25,"shooting":0.15}'::jsonb
      when entry.key like 'MOD-F11-%' then '{"passing":0.35,"defending":0.35,"physical":0.3,"shooting":0.15}'::jsonb
      when entry.key like 'POS-CB-%' then '{"defending":0.85,"physical":0.35,"passing":0.2}'::jsonb
      when entry.key like 'POS-FB-%' then '{"pace":0.45,"defending":0.45,"passing":0.25,"physical":0.25}'::jsonb
      when entry.key like 'POS-DM-%' then '{"defending":0.45,"passing":0.45,"physical":0.25,"dribbling":0.2}'::jsonb
      when entry.key like 'POS-CM-%' then '{"passing":0.45,"dribbling":0.4,"shooting":0.2,"defending":0.2}'::jsonb
      when entry.key like 'POS-W-%' then '{"pace":0.55,"dribbling":0.55,"shooting":0.25,"passing":0.2}'::jsonb
      when entry.key like 'POS-ST-%' then '{"shooting":0.6,"pace":0.35,"physical":0.25,"dribbling":0.2}'::jsonb
      else '{}'::jsonb
    end;

    for attribute_id, weight in
      select key, (value #>> '{}')::numeric
      from jsonb_each(weights)
    loop
      weighted_score := jsonb_set(
        weighted_score,
        array[attribute_id],
        to_jsonb(coalesce((weighted_score ->> attribute_id)::numeric, 0) + score * weight)
      );
      total_weight := jsonb_set(
        total_weight,
        array[attribute_id],
        to_jsonb(coalesce((total_weight ->> attribute_id)::numeric, 0) + weight)
      );
    end loop;
  end loop;

  foreach attribute_id in array array['pace', 'shooting', 'passing', 'dribbling', 'defending', 'physical']
  loop
    initial_value := coalesce(nullif(initial_ratings ->> attribute_id, '')::numeric, 50);
    calculated_value := coalesce((weighted_score ->> attribute_id)::numeric, initial_value * 4) / greatest(4, coalesce((total_weight ->> attribute_id)::numeric, 4));
    coverage := least(1::numeric, greatest(0::numeric, coalesce((total_weight ->> attribute_id)::numeric, 4) - 4) / 8);
    max_delta := 5 + 13 * coverage;
    final_ratings := jsonb_set(
      final_ratings,
      array[attribute_id],
      to_jsonb(public.pachanga_assessment_clamp(calculated_value, initial_value - max_delta, least(92::numeric, initial_value + max_delta)))
    );
  end loop;

  base_overall := (final_ratings ->> 'pace')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'pace')
    + (final_ratings ->> 'shooting')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'shooting')
    + (final_ratings ->> 'passing')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'passing')
    + (final_ratings ->> 'dribbling')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'dribbling')
    + (final_ratings ->> 'defending')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'defending')
    + (final_ratings ->> 'physical')::numeric * public.pachanga_assessment_overall_weight(primary_position, 'physical');
  reliability := public.pachanga_assessment_clamp(initial_reliability + least(26::numeric, completed_count * 0.65), initial_reliability, 65);

  return jsonb_build_object(
    'kind', 'advanced',
    'engineVersion', 'football-rating-v1',
    'questionnaireVersion', 'advanced-test-v1',
    'calculatedAt', calculated_at,
    'primaryPosition', primary_position,
    'baseRatings', final_ratings,
    'baseOverall', base_overall,
    'rating', public.pachanga_assessment_clamp(base_overall / 10, 1, 10),
    'facets', public.pachanga_assessment_facets_from_attributes(final_ratings),
    'reliability', reliability,
    'answeredCount', completed_count
  );
end;
$$;
