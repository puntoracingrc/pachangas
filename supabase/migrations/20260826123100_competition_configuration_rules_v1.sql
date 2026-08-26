-- Pachangas IQ Wave 5A: canonical authoring presets, validation and RuleRevision materialization.
-- Presets are copied into private drafts. Published competitions never retain a mutable preset dependency.

set lock_timeout = '5s';
set statement_timeout = '120s';

alter function private.pachanga_league_private_beta_normalize_step_v1(smallint, jsonb, jsonb)
  rename to pachanga_league_private_beta_normalize_step_legacy_v1;
alter function private.pachanga_league_private_beta_rule_document_v1(jsonb)
  rename to pachanga_league_private_beta_rule_document_legacy_v1;

create or replace function private.pachanga_competition_authoring_preset_v1(
  target_preset_key text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare preset_key text := upper(trim(coalesce(target_preset_key, '')));
declare label text;
declare modality text;
declare team_cap integer;
declare legs integer;
declare roster_min integer;
declare roster_max integer;
declare duration_minutes integer;
declare buffer_minutes integer;
declare rest_minutes integer;
declare starters integer;
declare referee_usage text;
declare blue_enabled boolean;
declare steps jsonb;
begin
  if preset_key = 'LEAGUE_F5_QUICK' then
    label := 'Liga F5 rápida'; modality := 'FUTBOL_5'; team_cap := 8; legs := 1;
    roster_min := 5; roster_max := 12; duration_minutes := 50; buffer_minutes := 10;
    rest_minutes := 720; starters := 5; referee_usage := 'OPTIONAL'; blue_enabled := false;
  elsif preset_key = 'LEAGUE_F7_STANDARD' then
    label := 'Liga F7 amateur estándar'; modality := 'FUTBOL_7'; team_cap := 12; legs := 2;
    roster_min := 7; roster_max := 18; duration_minutes := 70; buffer_minutes := 10;
    rest_minutes := 1440; starters := 7; referee_usage := 'OPTIONAL'; blue_enabled := false;
  elsif preset_key = 'LEAGUE_F11' then
    label := 'Liga F11'; modality := 'FUTBOL_11'; team_cap := 12; legs := 2;
    roster_min := 11; roster_max := 25; duration_minutes := 90; buffer_minutes := 15;
    rest_minutes := 2880; starters := 11; referee_usage := 'REQUIRED'; blue_enabled := false;
  elsif preset_key = 'LEAGUE_FUTSAL' then
    label := 'Liga de fútbol sala'; modality := 'FUTSAL'; team_cap := 10; legs := 2;
    roster_min := 5; roster_max := 14; duration_minutes := 40; buffer_minutes := 10;
    rest_minutes := 1440; starters := 5; referee_usage := 'REQUIRED'; blue_enabled := true;
  else
    raise exception 'COMPETITION_CONFIGURATION_PRESET_NOT_FOUND' using errcode = 'P0002';
  end if;

  steps := jsonb_build_object(
    '1', jsonb_build_object(
      'name', label, 'slug', case preset_key
        when 'LEAGUE_F5_QUICK' then 'liga-f5-rapida'
        when 'LEAGUE_F11' then 'liga-f11'
        when 'LEAGUE_FUTSAL' then 'liga-futbol-sala'
        else 'liga-f7-amateur' end,
      'description', '', 'generalArea', null, 'imageUrl', null,
      'privacy', 'PRIVATE', 'organizerType', 'CURRENT'
    ),
    '2', jsonb_build_object('modality', modality, 'playersPerTeam', starters),
    '3', jsonb_build_object(
      'editionName', 'Temporada inicial', 'seasonLabel', extract(year from current_date)::integer::text,
      'startsAt', current_date + 60, 'endsAt', current_date + 300, 'timezone', 'Europe/Madrid'
    ),
    '4', jsonb_build_object(
      'teamCap', team_cap, 'legs', legs, 'registrationMode', 'INVITE_ONLY',
      'registrationClosesAt', current_date + interval '30 days',
      'divisionMode', 'SINGLE_OPTIONAL', 'pairingMode', 'AUTOMATIC_ROUND_ROBIN'
    ),
    '5', jsonb_build_object(
      'minimumRosterSize', roster_min, 'maximumRosterSize', roster_max,
      'credentialRequired', true, 'jerseyRequired', true,
      'closeRequiresApprovedRosters', true
    ),
    '6', jsonb_build_object(
      'matchDurationMinutes', duration_minutes, 'requiredBufferMinutes', buffer_minutes,
      'pointsForWin', 3, 'pointsForDraw', 1, 'pointsForLoss', 0,
      'responseDeadlineHours', 48, 'autoOfficialAfterConfirmation', true,
      'confirmationMode', 'BILATERAL', 'maximumScore', null
    ),
    '7', jsonb_build_object(
      'weeklyPattern', jsonb_build_array(jsonb_build_object('dayOfWeek', 6, 'startTime', '18:00')),
      'venueRequired', false, 'allowTbd', true, 'minimumRestMinutes', rest_minutes,
      'useDivision', true, 'timezone', 'Europe/Madrid'
    ),
    '8', jsonb_build_object(
      'tieBreakCriteria', jsonb_build_array(
        'POINTS', 'GOAL_DIFFERENCE', 'GOALS_FOR', 'WINS', 'PERSISTED_DRAW_LOT'
      ),
      'scorerDetailPolicy', 'OPTIONAL', 'allowUnknownScorer', false,
      'allowSharedPositions', true
    ),
    '9', jsonb_build_object(
      'postponementRequestDeadlineHours', 48,
      'postponementResponseDeadlineHours', 48,
      'postponementDeadlinePolicy', 'ESCALATE_TO_ORGANIZER',
      'gracePeriodMinutes', 15, 'minimumRestHours', 24,
      'maximumMatchDurationMinutes', duration_minutes + 60,
      'noShowOutcome', 'NO_SHOW', 'noShowWinnerScore', 3, 'noShowLoserScore', 0,
      'allowAlternativeVenue', true, 'allowSuspensionAndResumption', true
    ),
    '10', jsonb_build_object(
      'enabled', true,
      'yellow', jsonb_build_object(
        'enabled', true, 'accumulationEnabled', true, 'points', 1, 'threshold', 3,
        'outcome', 'FIXED_SANCTION', 'unitType', 'MATCHES', 'units', 1
      ),
      'secondYellow', jsonb_build_object(
        'enabled', true, 'dismissal', true, 'preserveYellowFacts', true,
        'countsForAccumulation', true, 'outcome', 'FIXED_SANCTION',
        'unitType', 'MATCHES', 'units', 1
      ),
      'red', jsonb_build_object(
        'enabled', true, 'outcome', 'COMMITTEE_REQUIRED', 'unitType', 'MATCHES',
        'provisionalUnits', 1, 'minimumUnits', 1, 'maximumUnits', 3,
        'committeeRequired', true
      ),
      'blue', jsonb_build_object(
        'enabled', blue_enabled, 'mode', 'MINUTES_OR_GOAL', 'durationMinutes', 5,
        'replacementPolicy', 'NO_REPLACEMENT', 'postMatchOutcome', 'NO_SANCTION'
      ),
      'cycle', jsonb_build_object('scopeType', 'EDITION', 'carryPolicy', 'RESET'),
      'sanction', jsonb_build_object(
        'eligibleFixtureStatuses', jsonb_build_array('official', 'played'),
        'consumePostponed', false, 'consumeCancelled', false, 'consumeBye', false
      ),
      'appeal', jsonb_build_object('deadlineHours', 72, 'suspensiveEffect', false)
    ),
    '11', jsonb_build_object(
      'usage', referee_usage, 'role', 'MAIN_REFEREE',
      'proposerRoles', jsonb_build_array('competition_owner', 'competition_director', 'competition_referee_manager'),
      'acceptanceIsSufficient', false, 'organizerConfirmationRequired', true,
      'responseDeadlineHours', 72, 'reconfirmAfterScheduleChange', true,
      'modalityRequired', true, 'serviceAreaRequired', true,
      'priorClubRelationshipRequired', false, 'replacementAllowed', true,
      'requiredBeforeReady', referee_usage = 'REQUIRED',
      'authority', jsonb_build_object(
        'reportCards', true, 'reportIncidents', true, 'observeScore', true,
        'officialResult', false, 'standings', false, 'rating', false
      ),
      'fee', jsonb_build_object(
        'mode', 'NEGOTIABLE', 'fixedCents', null, 'travelIncluded', false,
        'publicConsent', false, 'currency', 'EUR', 'paymentProcessing', false
      )
    ),
    '12', jsonb_build_object(
      'competitionVisibility', 'PRIVATE', 'calendarVisibility', 'PARTICIPANTS_ONLY',
      'standingsVisibility', 'PARTICIPANTS_ONLY', 'disciplineVisibility', 'PRIVATE',
      'incidentVisibility', 'PRIVATE', 'consent', false,
      'acknowledgeUnavailableFeatures', false,
      'paymentsAcknowledged', false, 'tournamentsAcknowledged', false
    )
  );
  return jsonb_build_object(
    'key', preset_key, 'label', label, 'version', 1,
    'description', 'Valores seguros que se copian al borrador y dejan de depender del preset.',
    'steps', steps
  );
end;
$$;

revoke all on function private.pachanga_competition_authoring_preset_v1(text)
  from public, anon, authenticated;

create or replace function public.get_pachanga_competition_authoring_presets_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'presets', jsonb_build_array(
      private.pachanga_competition_authoring_preset_v1('LEAGUE_F7_STANDARD'),
      private.pachanga_competition_authoring_preset_v1('LEAGUE_F5_QUICK'),
      private.pachanga_competition_authoring_preset_v1('LEAGUE_F11'),
      private.pachanga_competition_authoring_preset_v1('LEAGUE_FUTSAL')
    ),
    'pairingModes', jsonb_build_array(
      jsonb_build_object('key', 'AUTOMATIC_ROUND_ROBIN', 'available', true),
      jsonb_build_object('key', 'MANUAL_ASSISTED', 'available', false, 'phase', 'R6A'),
      jsonb_build_object('key', 'HYBRID', 'available', false, 'phase', 'R6A')
    )
  );
$$;

revoke all on function public.get_pachanga_competition_authoring_presets_v1()
  from public, anon;
grant execute on function public.get_pachanga_competition_authoring_presets_v1()
  to authenticated, service_role;

create or replace function private.pachanga_league_private_beta_normalize_step_v1(
  target_step smallint,
  target_data jsonb,
  target_bundle jsonb
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog
as $$
declare data jsonb := coalesce(target_data, '{}'::jsonb);
declare yellow jsonb;
declare second_yellow jsonb;
declare red jsonb;
declare blue jsonb;
declare cycle_policy jsonb;
declare sanction_policy jsonb;
declare appeal_policy jsonb;
declare authority_policy jsonb;
declare fee_policy jsonb;
declare selected_usage text;
declare selected_mode text;
declare selected_outcome text;
declare selected_unit text;
declare selected_integer integer;
begin
  if target_step between 1 and 9 then
    return private.pachanga_league_private_beta_normalize_step_legacy_v1(
      target_step, data, target_bundle
    );
  end if;
  if jsonb_typeof(data) <> 'object' then
    raise exception 'LEAGUE_BETA_STEP_DATA_INVALID' using errcode = '22023';
  end if;

  if target_step = 10 then
    if data - array['enabled','yellow','secondYellow','red','blue','cycle','sanction','appeal','consent'] <> '{}'::jsonb then
      raise exception 'LEAGUE_BETA_DISCIPLINE_POLICY_INVALID' using errcode = '22023';
    end if;
    yellow := coalesce(data -> 'yellow', '{}'::jsonb);
    second_yellow := coalesce(data -> 'secondYellow', '{}'::jsonb);
    red := coalesce(data -> 'red', '{}'::jsonb);
    blue := coalesce(data -> 'blue', '{}'::jsonb);
    cycle_policy := coalesce(data -> 'cycle', '{}'::jsonb);
    sanction_policy := coalesce(data -> 'sanction', '{}'::jsonb);
    appeal_policy := coalesce(data -> 'appeal', '{}'::jsonb);
    if jsonb_typeof(yellow) <> 'object' or jsonb_typeof(second_yellow) <> 'object'
       or jsonb_typeof(red) <> 'object' or jsonb_typeof(blue) <> 'object'
       or jsonb_typeof(cycle_policy) <> 'object' or jsonb_typeof(sanction_policy) <> 'object'
       or jsonb_typeof(appeal_policy) <> 'object' then
      raise exception 'LEAGUE_BETA_DISCIPLINE_POLICY_INVALID' using errcode = '22023';
    end if;
    selected_integer := coalesce(nullif(yellow ->> 'threshold', '')::integer, 0);
    if coalesce((yellow ->> 'accumulationEnabled')::boolean, false) and selected_integer < 1 then
      raise exception 'DISCIPLINE_ACCUMULATION_THRESHOLD_INVALID' using errcode = '22023';
    end if;
    selected_unit := upper(coalesce(yellow ->> 'unitType', 'MATCHES'));
    if selected_unit not in ('MATCHES','ROUNDS','WEEKS') then
      raise exception 'DISCIPLINE_SANCTION_UNIT_UNSUPPORTED' using errcode = '22023';
    end if;
    selected_outcome := upper(coalesce(red ->> 'outcome', 'COMMITTEE_REQUIRED'));
    if selected_outcome not in ('NO_SANCTION','FIXED_SANCTION','PROVISIONAL_SANCTION','COMMITTEE_REQUIRED','SANCTION_RANGE') then
      raise exception 'DISCIPLINE_RED_OUTCOME_INVALID' using errcode = '22023';
    end if;
    selected_mode := upper(coalesce(blue ->> 'mode', 'MINUTES_OR_GOAL'));
    if coalesce((blue ->> 'enabled')::boolean, false)
       and (selected_mode not in ('MINUTES','UNTIL_OPPONENT_GOAL','MINUTES_OR_GOAL','MINUTES_AND_GOAL')
         or coalesce(nullif(blue ->> 'durationMinutes', '')::integer, 0) < 1) then
      raise exception 'DISCIPLINE_BLUE_POLICY_INVALID' using errcode = '22023';
    end if;
    if upper(coalesce(cycle_policy ->> 'scopeType', 'EDITION')) not in ('EDITION','STAGE')
       or upper(coalesce(cycle_policy ->> 'carryPolicy', 'RESET')) not in ('RESET','CARRY')
       or coalesce(nullif(appeal_policy ->> 'deadlineHours', '')::integer, 0) not between 1 and 720 then
      raise exception 'DISCIPLINE_CYCLE_OR_APPEAL_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'enabled', coalesce((data ->> 'enabled')::boolean, true),
      'yellow', jsonb_build_object(
        'enabled', coalesce((yellow ->> 'enabled')::boolean, true),
        'accumulationEnabled', coalesce((yellow ->> 'accumulationEnabled')::boolean, true),
        'points', greatest(coalesce(nullif(yellow ->> 'points', '')::integer, 1), 0),
        'threshold', selected_integer,
        'outcome', upper(coalesce(yellow ->> 'outcome', 'FIXED_SANCTION')),
        'unitType', selected_unit,
        'units', greatest(coalesce(nullif(yellow ->> 'units', '')::integer, 1), 0)
      ),
      'secondYellow', jsonb_build_object(
        'enabled', coalesce((second_yellow ->> 'enabled')::boolean, true),
        'dismissal', coalesce((second_yellow ->> 'dismissal')::boolean, true),
        'preserveYellowFacts', true,
        'countsForAccumulation', coalesce((second_yellow ->> 'countsForAccumulation')::boolean, true),
        'outcome', upper(coalesce(second_yellow ->> 'outcome', 'FIXED_SANCTION')),
        'unitType', upper(coalesce(second_yellow ->> 'unitType', 'MATCHES')),
        'units', greatest(coalesce(nullif(second_yellow ->> 'units', '')::integer, 1), 0)
      ),
      'red', jsonb_build_object(
        'enabled', coalesce((red ->> 'enabled')::boolean, true),
        'outcome', selected_outcome,
        'unitType', upper(coalesce(red ->> 'unitType', 'MATCHES')),
        'units', greatest(coalesce(nullif(red ->> 'units', '')::integer, 1), 0),
        'provisionalUnits', greatest(coalesce(nullif(red ->> 'provisionalUnits', '')::integer, 0), 0),
        'minimumUnits', greatest(coalesce(nullif(red ->> 'minimumUnits', '')::integer, 1), 0),
        'maximumUnits', greatest(coalesce(nullif(red ->> 'maximumUnits', '')::integer, 3), 0),
        'committeeRequired', coalesce((red ->> 'committeeRequired')::boolean, selected_outcome in ('COMMITTEE_REQUIRED','SANCTION_RANGE'))
      ),
      'blue', jsonb_build_object(
        'enabled', coalesce((blue ->> 'enabled')::boolean, false),
        'mode', selected_mode,
        'durationMinutes', greatest(coalesce(nullif(blue ->> 'durationMinutes', '')::integer, 5), 1),
        'replacementPolicy', case upper(coalesce(blue ->> 'replacementPolicy', 'NO_REPLACEMENT'))
          when 'REPLACEMENT_ALLOWED' then 'REPLACEMENT_ALLOWED' else 'NO_REPLACEMENT' end,
        'postMatchOutcome', upper(coalesce(blue ->> 'postMatchOutcome', 'NO_SANCTION'))
      ),
      'cycle', jsonb_build_object(
        'scopeType', upper(coalesce(cycle_policy ->> 'scopeType', 'EDITION')),
        'carryPolicy', upper(coalesce(cycle_policy ->> 'carryPolicy', 'RESET'))
      ),
      'sanction', jsonb_build_object(
        'eligibleFixtureStatuses', coalesce(sanction_policy -> 'eligibleFixtureStatuses', jsonb_build_array('official','played')),
        'consumePostponed', coalesce((sanction_policy ->> 'consumePostponed')::boolean, false),
        'consumeCancelled', false, 'consumeBye', false
      ),
      'appeal', jsonb_build_object(
        'deadlineHours', (appeal_policy ->> 'deadlineHours')::integer,
        'suspensiveEffect', coalesce((appeal_policy ->> 'suspensiveEffect')::boolean, false)
      ),
      'consent', coalesce((data ->> 'consent')::boolean, false)
    );
  elsif target_step = 11 then
    if data - array[
      'usage','role','proposerRoles','acceptanceIsSufficient','organizerConfirmationRequired',
      'responseDeadlineHours','reconfirmAfterScheduleChange','modalityRequired',
      'serviceAreaRequired','priorClubRelationshipRequired','replacementAllowed',
      'requiredBeforeReady','authority','fee'
    ] <> '{}'::jsonb then
      raise exception 'LEAGUE_BETA_REFEREE_POLICY_INVALID' using errcode = '22023';
    end if;
    selected_usage := upper(coalesce(data ->> 'usage', 'NONE'));
    authority_policy := coalesce(data -> 'authority', '{}'::jsonb);
    fee_policy := coalesce(data -> 'fee', '{}'::jsonb);
    if selected_usage not in ('NONE','OPTIONAL','REQUIRED')
       or upper(coalesce(data ->> 'role', 'MAIN_REFEREE')) <> 'MAIN_REFEREE'
       or coalesce(nullif(data ->> 'responseDeadlineHours', '')::integer, 0) not between 1 and 720
       or jsonb_typeof(coalesce(data -> 'proposerRoles', '[]'::jsonb)) <> 'array'
       or jsonb_typeof(authority_policy) <> 'object' or jsonb_typeof(fee_policy) <> 'object' then
      raise exception 'LEAGUE_BETA_REFEREE_POLICY_INVALID' using errcode = '22023';
    end if;
    selected_mode := upper(coalesce(fee_policy ->> 'mode', 'NEGOTIABLE'));
    if selected_mode not in ('FREE','FIXED','NEGOTIABLE','VOLUNTEER')
       or (selected_mode = 'FIXED' and coalesce(nullif(fee_policy ->> 'fixedCents', '')::integer, -1) < 0)
       or (selected_mode in ('FREE','VOLUNTEER') and nullif(fee_policy ->> 'fixedCents', '') is not null) then
      raise exception 'LEAGUE_BETA_REFEREE_FEE_POLICY_INVALID' using errcode = '22023';
    end if;
    return jsonb_build_object(
      'usage', selected_usage, 'role', 'MAIN_REFEREE',
      'proposerRoles', coalesce(data -> 'proposerRoles', '[]'::jsonb),
      'acceptanceIsSufficient', coalesce((data ->> 'acceptanceIsSufficient')::boolean, false),
      'organizerConfirmationRequired', coalesce((data ->> 'organizerConfirmationRequired')::boolean, true),
      'responseDeadlineHours', (data ->> 'responseDeadlineHours')::integer,
      'reconfirmAfterScheduleChange', coalesce((data ->> 'reconfirmAfterScheduleChange')::boolean, true),
      'modalityRequired', coalesce((data ->> 'modalityRequired')::boolean, true),
      'serviceAreaRequired', coalesce((data ->> 'serviceAreaRequired')::boolean, true),
      'priorClubRelationshipRequired', coalesce((data ->> 'priorClubRelationshipRequired')::boolean, false),
      'replacementAllowed', coalesce((data ->> 'replacementAllowed')::boolean, true),
      'requiredBeforeReady', coalesce((data ->> 'requiredBeforeReady')::boolean, selected_usage = 'REQUIRED'),
      'authority', jsonb_build_object(
        'reportCards', coalesce((authority_policy ->> 'reportCards')::boolean, true),
        'reportIncidents', coalesce((authority_policy ->> 'reportIncidents')::boolean, true),
        'observeScore', coalesce((authority_policy ->> 'observeScore')::boolean, true),
        'officialResult', false, 'standings', false, 'rating', false
      ),
      'fee', jsonb_build_object(
        'mode', selected_mode,
        'fixedCents', case when selected_mode = 'FIXED' then (fee_policy ->> 'fixedCents')::integer end,
        'travelIncluded', coalesce((fee_policy ->> 'travelIncluded')::boolean, false),
        'publicConsent', coalesce((fee_policy ->> 'publicConsent')::boolean, false),
        'currency', 'EUR', 'paymentProcessing', false
      )
    );
  elsif target_step = 12 then
    if data - array[
      'competitionVisibility','calendarVisibility','standingsVisibility',
      'disciplineVisibility','incidentVisibility','consent',
      'acknowledgeUnavailableFeatures','paymentsAcknowledged','tournamentsAcknowledged',
      'authoringMode','sourcePresetKey','sourcePresetVersion'
    ] <> '{}'::jsonb then
      raise exception 'LEAGUE_BETA_VISIBILITY_POLICY_INVALID' using errcode = '22023';
    end if;
    if upper(coalesce(data ->> 'competitionVisibility', 'PRIVATE')) <> 'PRIVATE'
       or upper(coalesce(data ->> 'calendarVisibility', 'PARTICIPANTS_ONLY')) <> 'PARTICIPANTS_ONLY'
       or upper(coalesce(data ->> 'standingsVisibility', 'PARTICIPANTS_ONLY')) <> 'PARTICIPANTS_ONLY'
       or upper(coalesce(data ->> 'disciplineVisibility', 'PRIVATE')) <> 'PRIVATE'
       or upper(coalesce(data ->> 'incidentVisibility', 'PRIVATE')) <> 'PRIVATE' then
      raise exception 'LEAGUE_BETA_PUBLIC_SURFACES_DISABLED' using errcode = '0A000';
    end if;
    return jsonb_strip_nulls(jsonb_build_object(
      'competitionVisibility', 'PRIVATE', 'calendarVisibility', 'PARTICIPANTS_ONLY',
      'standingsVisibility', 'PARTICIPANTS_ONLY', 'disciplineVisibility', 'PRIVATE',
      'incidentVisibility', 'PRIVATE',
      'consent', coalesce((data ->> 'consent')::boolean, false),
      'acknowledgeUnavailableFeatures', coalesce((data ->> 'acknowledgeUnavailableFeatures')::boolean, false),
      'paymentsAcknowledged', coalesce((data ->> 'paymentsAcknowledged')::boolean, false),
      'tournamentsAcknowledged', coalesce((data ->> 'tournamentsAcknowledged')::boolean, false),
      'authoringMode', nullif(upper(data ->> 'authoringMode'), ''),
      'sourcePresetKey', nullif(upper(data ->> 'sourcePresetKey'), ''),
      'sourcePresetVersion', nullif(data ->> 'sourcePresetVersion', '')::integer
    ));
  end if;
  raise exception 'LEAGUE_BETA_STEP_INVALID' using errcode = '22023';
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'LEAGUE_BETA_STEP_DATA_INVALID' using errcode = '22023';
end;
$$;

create or replace function private.pachanga_competition_configuration_rule_document_v1(
  target_steps jsonb,
  target_authoring_mode text default 'SIMPLE',
  target_preset_key text default null
)
returns jsonb
language plpgsql
stable
set search_path = pg_catalog
as $$
declare base_document jsonb;
declare discipline_step jsonb := target_steps -> '10';
declare referee_step jsonb := target_steps -> '11';
declare visibility_step jsonb := target_steps -> '12';
declare yellow jsonb := discipline_step -> 'yellow';
declare second_yellow jsonb := discipline_step -> 'secondYellow';
declare red jsonb := discipline_step -> 'red';
declare blue jsonb := discipline_step -> 'blue';
declare card_catalog jsonb := '[]'::jsonb;
declare discipline_policy jsonb;
declare normalized_mode text := upper(coalesce(target_authoring_mode, 'SIMPLE'));
declare normalized_preset text := nullif(upper(trim(coalesce(target_preset_key, ''))), '');
begin
  base_document := private.pachanga_league_private_beta_rule_document_legacy_v1(target_steps);
  if coalesce((discipline_step ->> 'enabled')::boolean, false)
     and coalesce((yellow ->> 'enabled')::boolean, false) then
    card_catalog := card_catalog || jsonb_build_array(jsonb_build_object(
      'code', 'YELLOW', 'label', 'Amarilla', 'visualType', 'yellow',
      'immediateEffect', 'WARNING',
      'accumulation', jsonb_build_object(
        'enabled', coalesce((yellow ->> 'accumulationEnabled')::boolean, false),
        'points', (yellow ->> 'points')::integer,
        'threshold', (yellow ->> 'threshold')::integer,
        'outcome', yellow ->> 'outcome', 'unitType', yellow ->> 'unitType',
        'units', (yellow ->> 'units')::integer
      ),
      'dismissal', case when coalesce((second_yellow ->> 'enabled')::boolean, false)
        then jsonb_build_object(
          'mode', 'SECOND_CARD', 'thresholdInMatch', 2,
          'outcome', second_yellow ->> 'outcome',
          'unitType', second_yellow ->> 'unitType',
          'units', (second_yellow ->> 'units')::integer,
          'preserveYellowFacts', true,
          'countsForAccumulation', (second_yellow ->> 'countsForAccumulation')::boolean
        ) else jsonb_build_object('mode', 'NONE', 'outcome', 'NO_SANCTION') end
    ));
  end if;
  if coalesce((discipline_step ->> 'enabled')::boolean, false)
     and coalesce((red ->> 'enabled')::boolean, false) then
    card_catalog := card_catalog || jsonb_build_array(jsonb_build_object(
      'code', 'RED', 'label', 'Roja directa', 'visualType', 'red',
      'immediateEffect', 'DIRECT_DISMISSAL',
      'accumulation', jsonb_build_object('enabled', false, 'points', 0),
      'dismissal', jsonb_strip_nulls(jsonb_build_object(
        'mode', 'DIRECT', 'outcome', red ->> 'outcome',
        'unitType', red ->> 'unitType', 'units', (red ->> 'units')::integer,
        'provisionalUnits', (red ->> 'provisionalUnits')::integer,
        'minimumUnits', (red ->> 'minimumUnits')::integer,
        'maximumUnits', (red ->> 'maximumUnits')::integer,
        'ruleArticle', 'R5.RED.CONFIGURED'
      ))
    ));
  end if;
  if coalesce((discipline_step ->> 'enabled')::boolean, false)
     and coalesce((blue ->> 'enabled')::boolean, false) then
    card_catalog := card_catalog || jsonb_build_array(jsonb_build_object(
      'code', 'BLUE', 'label', 'Azul', 'visualType', 'blue',
      'immediateEffect', 'TEMPORARY_DISMISSAL',
      'accumulation', jsonb_build_object('enabled', false, 'points', 0),
      'dismissal', jsonb_build_object(
        'mode', 'TEMPORARY', 'outcome', blue ->> 'postMatchOutcome'
      ),
      'temporaryDismissal', jsonb_build_object(
        'mode', case blue ->> 'mode'
          when 'MINUTES' then 'MINUTES'
          when 'UNTIL_OPPONENT_GOAL' then 'OPPONENT_GOAL'
          when 'MINUTES_AND_GOAL' then 'BOTH'
          else 'EITHER' end,
        'durationMinutes', (blue ->> 'durationMinutes')::integer,
        'endOnOpponentGoal', blue ->> 'mode' in ('UNTIL_OPPONENT_GOAL','MINUTES_OR_GOAL','MINUTES_AND_GOAL'),
        'replacementPolicy', blue ->> 'replacementPolicy'
      )
    ));
  end if;
  discipline_policy := jsonb_build_object(
    'policyVersion', 'competition-configuration-v1',
    'cardTypeCatalog', card_catalog,
    'cyclePolicy', jsonb_build_object(
      'scopeType', discipline_step #>> '{cycle,scopeType}',
      'carryPolicy', discipline_step #>> '{cycle,carryPolicy}'
    ),
    'sanctionPolicy', discipline_step -> 'sanction',
    'appealPolicy', discipline_step -> 'appeal',
    'publicReasonCategories', jsonb_build_array(
      'accumulation','dismissal','temporary_dismissal','administrative'
    )
  );
  base_document := jsonb_set(base_document, '{identity}',
    (base_document -> 'identity') || jsonb_strip_nulls(jsonb_build_object(
      'authoringMode', normalized_mode,
      'sourcePresetId', normalized_preset,
      'sourcePresetVersion', case when normalized_preset is not null then 1 end,
      'configurationSchema', 'competition-configuration.v1'
    )), true);
  base_document := jsonb_set(base_document, '{discipline}', jsonb_build_object(
    'enabled', coalesce((discipline_step ->> 'enabled')::boolean, false),
    'policy', discipline_policy,
    'secondYellowPolicy', discipline_step -> 'secondYellow'
  ), true);
  base_document := jsonb_set(base_document, '{operations,refereePolicy}', referee_step, true);
  base_document := jsonb_set(base_document, '{publication}', jsonb_build_object(
    'visibility', 'private', 'calendarVisibility', 'participants_only',
    'standingsVisibility', 'participants_only', 'disciplineVisibility', 'private',
    'exceptionVisibility', 'private'
  ), true);
  base_document := jsonb_set(base_document, '{futureCapabilities}', jsonb_build_object(
    'refereeAssignments', referee_step ->> 'usage' <> 'NONE',
    'discipline', coalesce((discipline_step ->> 'enabled')::boolean, false),
    'payments', false, 'tournaments', false,
    'manualAssistedPairing', false, 'hybridPairing', false
  ), true);
  base_document := jsonb_set(base_document, '{governance}',
    (base_document -> 'governance') || jsonb_build_object(
      'organizerConsentRequired', true,
      'consentRecorded', coalesce((visibility_step ->> 'consent')::boolean, false),
      'paymentProcessing', false,
      'pairingMode', 'AUTOMATIC_ROUND_ROBIN'
    ), true);
  return base_document;
end;
$$;

revoke all on function private.pachanga_competition_configuration_rule_document_v1(jsonb, text, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_private_beta_rule_document_v1(
  target_steps jsonb
)
returns jsonb
language sql
stable
set search_path = pg_catalog
as $$
  select private.pachanga_competition_configuration_rule_document_v1(
    target_steps,
    coalesce(target_steps #>> '{12,authoringMode}', 'SIMPLE'),
    target_steps #>> '{12,sourcePresetKey}'
  );
$$;

create or replace function private.pachanga_competition_configuration_health_v1(
  target_steps jsonb,
  target_completed_steps smallint[] default array[]::smallint[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare errors jsonb := '[]'::jsonb;
declare warnings jsonb := '[]'::jsonb;
declare global_off jsonb := '[]'::jsonb;
declare missing jsonb := '[]'::jsonb;
declare discipline jsonb := coalesce(target_steps -> '10', '{}'::jsonb);
declare referee jsonb := coalesce(target_steps -> '11', '{}'::jsonb);
declare assignment_enabled boolean := coalesce((
  select settings.referee_assignments_enabled
  from private.pachanga_referee_foundation_settings settings where settings.singleton
), false);
declare discipline_enabled boolean := coalesce((
  select settings.competition_discipline_foundation_enabled
  from private.pachanga_competition_foundation_settings settings where settings.singleton
), false);
begin
  for step_number in 1..12 loop
    if not (step_number::smallint = any(coalesce(target_completed_steps, '{}'::smallint[])))
       or jsonb_typeof(target_steps -> step_number::text) <> 'object' then
      missing := missing || to_jsonb(step_number);
    end if;
  end loop;
  if coalesce((target_steps #>> '{5,minimumRosterSize}')::integer, 0)
       > coalesce((target_steps #>> '{5,maximumRosterSize}')::integer, 0) then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','ROSTER_MIN_EXCEEDS_MAX','section','roster','message','El mínimo de plantilla supera el máximo.'
    ));
  end if;
  if coalesce((target_steps #>> '{7,venueRequired}')::boolean, false)
     and not coalesce((target_steps #>> '{7,allowTbd}')::boolean, false)
     and coalesce(jsonb_array_length(coalesce(target_steps #> '{7,venues}', '[]'::jsonb)), 0) = 0 then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','VENUE_REQUIRED_WITHOUT_VENUE','section','schedule','message','La sede es obligatoria, TBD está desactivado y no hay sede configurada.'
    ));
  end if;
  if upper(coalesce(referee ->> 'usage','NONE')) = 'REQUIRED' and not assignment_enabled then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','REFEREE_ASSIGNMENTS_GLOBALLY_OFF','section','referees','message','No se puede exigir árbitro mientras Assignments está apagado.'
    ));
  end if;
  if coalesce((discipline #>> '{blue,enabled}')::boolean, false)
     and coalesce((discipline #>> '{blue,durationMinutes}')::integer, 0) < 1 then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','BLUE_WITHOUT_TEMPORARY_POLICY','section','discipline','message','La tarjeta azul requiere una política temporal válida.'
    ));
  end if;
  if coalesce((discipline #>> '{yellow,accumulationEnabled}')::boolean, false)
     and coalesce((discipline #>> '{yellow,threshold}')::integer, 0) < 1 then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','YELLOW_THRESHOLD_ZERO','section','discipline','message','La acumulación amarilla requiere threshold mayor que cero.'
    ));
  end if;
  if coalesce((target_steps #>> '{9,noShowWinnerScore}')::integer, -1) < 0
     or coalesce((target_steps #>> '{9,noShowLoserScore}')::integer, -1) < 0 then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','NO_SHOW_SCORE_REQUIRED','section','incidents','message','El no-show necesita outcome y marcador.'
    ));
  end if;
  if coalesce((target_steps #>> '{8,scorerDetailPolicy}'),'OPTIONAL') = 'REQUIRED'
     and coalesce((target_steps #>> '{8,scorerDetailPolicy}'),'') = 'DISABLED' then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','SCORER_POLICY_CONTRADICTION','section','results','message','Los goleadores no pueden ser obligatorios y estar desactivados.'
    ));
  end if;
  if coalesce((target_steps #>> '{6,autoOfficialAfterConfirmation}')::boolean, false)
     and coalesce(target_steps #>> '{6,confirmationMode}', 'BILATERAL') <> 'BILATERAL' then
    errors := errors || jsonb_build_array(jsonb_build_object(
      'code','AUTO_OFFICIAL_REQUIRES_BILATERAL','section','results','message','El resultado automático requiere confirmación bilateral.'
    ));
  end if;
  if not discipline_enabled and coalesce((discipline ->> 'enabled')::boolean, false) then
    global_off := global_off || jsonb_build_array('discipline');
  end if;
  if not assignment_enabled and upper(coalesce(referee ->> 'usage','NONE')) <> 'NONE' then
    global_off := global_off || jsonb_build_array('referee_assignments');
  end if;
  global_off := global_off || jsonb_build_array('public_surfaces','payments','tournaments','manual_hybrid_pairing');
  if jsonb_array_length(missing) > 0 then
    warnings := warnings || jsonb_build_array(jsonb_build_object(
      'code','INCOMPLETE_STEPS','section','wizard','message','Quedan pasos por revisar.','steps',missing
    ));
  end if;
  return jsonb_build_object(
    'status', case when jsonb_array_length(errors) > 0 then 'invalid'
      when jsonb_array_length(missing) > 0 then 'incomplete' else 'complete' end,
    'complete', jsonb_array_length(errors) = 0 and jsonb_array_length(missing) = 0,
    'errors', errors, 'warnings', warnings, 'missingSteps', missing,
    'globallyDisabled', global_off,
    'nextAction', case when jsonb_array_length(errors) > 0 then 'resolve_errors'
      when jsonb_array_length(missing) > 0 then 'complete_steps' else 'publish_rule_revision' end
  );
exception when others then
  return jsonb_build_object(
    'status','invalid','complete',false,
    'errors',jsonb_build_array(jsonb_build_object(
      'code','CONFIGURATION_VALUE_INVALID','section','configuration','message',sqlerrm
    )),
    'warnings','[]'::jsonb,'missingSteps',missing,'globallyDisabled',global_off,
    'nextAction','resolve_errors'
  );
end;
$$;

revoke all on function private.pachanga_competition_configuration_health_v1(jsonb, smallint[])
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_summary_v1(
  target_document jsonb
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'format', jsonb_build_object(
      'modality', target_document #>> '{format,modality}',
      'teamsMaximum', target_document #>> '{registration,registrationPolicy,teamLimits,maximum}',
      'registrationMode', target_document #>> '{registration,registrationPolicy,mode}'
    ),
    'matches', target_document #> '{operations,schedulePolicy}',
    'scoring', target_document #> '{results,scoringPolicy}',
    'tieBreaks', target_document #> '{results,tieBreakCriteria}',
    'results', target_document #> '{results,confirmationPolicy}',
    'incidents', target_document #> '{operations,exceptionPolicy}',
    'discipline', jsonb_build_object(
      'enabled', target_document #> '{discipline,enabled}',
      'cards', coalesce(target_document #> '{discipline,policy,cardTypeCatalog}', '[]'::jsonb),
      'cycle', target_document #> '{discipline,policy,cyclePolicy}',
      'appeal', target_document #> '{discipline,policy,appealPolicy}'
    ),
    'referees', target_document #> '{operations,refereePolicy}',
    'visibility', target_document -> 'publication',
    'unavailable', jsonb_build_array('payments','tournaments','manual_assisted_pairing','hybrid_pairing')
  );
$$;

revoke all on function private.pachanga_competition_configuration_summary_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_human_document_v1(
  target_rule_revision_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected_revision public.pachanga_competition_rule_revisions%rowtype;
declare selected_competition public.pachanga_competitions%rowtype;
begin
  select revisions.* into selected_revision
  from public.pachanga_competition_rule_revisions revisions
  where revisions.id = target_rule_revision_id;
  if not found then raise exception 'RULE_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
  select competitions.* into selected_competition
  from public.pachanga_competition_rule_sets sets
  join public.pachanga_competitions competitions on competitions.id = sets.competition_id
  where sets.id = selected_revision.rule_set_id;
  return jsonb_build_object(
    'competitionId', selected_competition.id,
    'competitionName', selected_competition.name,
    'ruleRevisionId', selected_revision.id,
    'revision', selected_revision.version,
    'effectiveFrom', selected_revision.effective_from,
    'effectiveScope', selected_revision.effective_scope,
    'hash', selected_revision.checksum,
    'sections', private.pachanga_competition_configuration_summary_v1(selected_revision.rule_document),
    'notice', 'Esta vista se deriva de la RuleRevision congelada; el texto no es una autoridad independiente.'
  );
end;
$$;

revoke all on function private.pachanga_competition_configuration_human_document_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_competition_configuration_diff_v1(
  source_document jsonb,
  proposed_document jsonb
)
returns jsonb
language sql
immutable
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'format', jsonb_build_object('changed', source_document #> '{format}' is distinct from proposed_document #> '{format}', 'before', source_document #> '{format}', 'after', proposed_document #> '{format}'),
    'roster', jsonb_build_object('changed', source_document #> '{registration}' is distinct from proposed_document #> '{registration}', 'before', source_document #> '{registration}', 'after', proposed_document #> '{registration}'),
    'match', jsonb_build_object('changed', source_document #> '{operations,schedulePolicy}' is distinct from proposed_document #> '{operations,schedulePolicy}', 'before', source_document #> '{operations,schedulePolicy}', 'after', proposed_document #> '{operations,schedulePolicy}'),
    'scoring', jsonb_build_object('changed', source_document #> '{results}' is distinct from proposed_document #> '{results}', 'before', source_document #> '{results}', 'after', proposed_document #> '{results}'),
    'incidents', jsonb_build_object('changed', source_document #> '{operations,exceptionPolicy}' is distinct from proposed_document #> '{operations,exceptionPolicy}', 'before', source_document #> '{operations,exceptionPolicy}', 'after', proposed_document #> '{operations,exceptionPolicy}'),
    'discipline', jsonb_build_object('changed', source_document #> '{discipline}' is distinct from proposed_document #> '{discipline}', 'before', source_document #> '{discipline}', 'after', proposed_document #> '{discipline}'),
    'referees', jsonb_build_object('changed', source_document #> '{operations,refereePolicy}' is distinct from proposed_document #> '{operations,refereePolicy}', 'before', source_document #> '{operations,refereePolicy}', 'after', proposed_document #> '{operations,refereePolicy}'),
    'visibility', jsonb_build_object('changed', source_document #> '{publication}' is distinct from proposed_document #> '{publication}', 'before', source_document #> '{publication}', 'after', proposed_document #> '{publication}')
  );
$$;

revoke all on function private.pachanga_competition_configuration_diff_v1(jsonb, jsonb)
  from public, anon, authenticated;

-- Wizard snapshots now expose authoring metadata and real feature health.
create or replace function private.pachanga_league_private_beta_wizard_snapshot_v1(
  target_wizard_id uuid
)
returns jsonb
language sql
volatile
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'id', wizards.id,
    'wizardVersion', wizards.wizard_version,
    'authoringMode', wizards.authoring_mode,
    'presetKey', wizards.preset_key,
    'organizerKind', wizards.organizer_kind,
    'organizerId', coalesce(wizards.organizer_group_id, wizards.organizer_club_id),
    'status', wizards.status,
    'currentStep', wizards.current_step,
    'completedSteps', to_jsonb(wizards.completed_steps),
    'steps', wizards.step_data,
    'health', private.pachanga_competition_configuration_health_v1(wizards.step_data, wizards.completed_steps),
    'competitionId', wizards.competition_id,
    'consentedAt', wizards.consented_at,
    'revision', wizards.revision,
    'serverSequence', wizards.server_sequence,
    'updatedAt', wizards.updated_at
  )
  from private.pachanga_league_private_beta_wizards wizards
  where wizards.id = target_wizard_id;
$$;

create or replace function public.get_pachanga_league_private_beta_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'productKey', 'LEAGUE_PRIVATE_BETA_V1',
    'wizardVersion', 2,
    'enabled', settings.league_private_beta_enabled,
    'creationEnabled', settings.league_private_beta_creation_enabled,
    'configurationCenterEnabled', settings.competition_configuration_center_enabled,
    'wizardV2Enabled', settings.league_wizard_v2_enabled,
    'publicDiscoveryEnabled', false,
    'inviteOnly', true,
    'defaultTeamCap', settings.league_private_beta_default_team_cap,
    'standardMaximumTeams', 12,
    'absoluteMaximumTeams', 20,
    'maxActiveEditionsPerOrganizer', settings.league_private_beta_max_active_editions_per_organizer,
    'disciplineEnabled', settings.competition_discipline_foundation_enabled,
    'refereeAssignmentsEnabled', coalesce((
      select referee_settings.referee_assignments_enabled
      from private.pachanga_referee_foundation_settings referee_settings
      where referee_settings.singleton
    ), false),
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at,
    'unavailable', jsonb_build_array('payments','tournaments','manual_assisted_pairing','hybrid_pairing')
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

revoke all on function public.get_pachanga_league_private_beta_flags_v1()
  from public, anon;
grant execute on function public.get_pachanga_league_private_beta_flags_v1()
  to authenticated, service_role;
