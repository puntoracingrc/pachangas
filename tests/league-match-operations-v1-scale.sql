\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.scale_uuid(scope text, kind text, ordinal bigint)
returns uuid language sql immutable as $$
  select md5('r4c-scale:' || scope || ':' || kind || ':' || ordinal::text)::uuid;
$$;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create temporary table r4c_scale_leagues (
  scope text primary key,
  team_count integer not null,
  fixture_count integer not null,
  competition_id uuid not null,
  edition_id uuid not null,
  stage_id uuid not null,
  division_id uuid not null,
  competition_group_id uuid not null,
  rule_revision_id uuid not null,
  target_context_id uuid not null,
  target_canonical_match_id uuid not null
) on commit drop;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
values (
  'd4010000-0000-4000-8000-000000000001',
  'r4c-scale-director@example.test',
  clock_timestamp(),
  '{"full_name":"R4C Scale Director"}'
);

create or replace function pg_temp.build_scale_league(scope text, team_total integer)
returns void language plpgsql as $$
<<builder>>
declare director_id constant uuid := 'd4010000-0000-4000-8000-000000000001';
declare organizer_group_id uuid := pg_temp.scale_uuid(scope, 'organizer-group', 1);
declare competition_id uuid := pg_temp.scale_uuid(scope, 'competition', 1);
declare rule_set_id uuid := pg_temp.scale_uuid(scope, 'rule-set', 1);
declare rule_revision_id uuid := pg_temp.scale_uuid(scope, 'rule-revision', 1);
declare edition_id uuid := pg_temp.scale_uuid(scope, 'edition', 1);
declare category_id uuid := pg_temp.scale_uuid(scope, 'category', 1);
declare stage_id uuid := pg_temp.scale_uuid(scope, 'stage', 1);
declare division_id uuid := pg_temp.scale_uuid(scope, 'division', 1);
declare competition_group_id uuid := pg_temp.scale_uuid(scope, 'competition-group', 1);
declare plan_id uuid := pg_temp.scale_uuid(scope, 'schedule-plan', 1);
declare schedule_revision_id uuid := pg_temp.scale_uuid(scope, 'schedule-revision', 1);
declare team_id uuid;
declare entry_id uuid;
declare membership_id uuid;
declare entry_ids uuid[] := '{}';
declare home_entry_id uuid;
declare away_entry_id uuid;
declare round_id uuid;
declare slot_id uuid;
declare item_id uuid;
declare canonical_match_id uuid;
declare binding_id uuid;
declare context_id uuid;
declare result_id uuid;
declare result_revision_id uuid;
declare sheet_id uuid;
declare decision_id uuid;
declare first_context_id uuid;
declare first_canonical_id uuid;
declare rule_document jsonb;
declare round_total integer := 2 * (team_total - 1);
declare fixture_total integer := team_total * (team_total - 1);
declare match_no integer := 0;
declare round_no integer;
declare slot_no integer;
declare team_index integer;
declare opponent_index integer;
declare leg integer;
declare score_home integer;
declare score_away integer;
declare scheduled_start timestamptz;
begin
  if team_total not in (20, 32) then raise exception 'R4C_SCALE_TEAM_COUNT_INVALID'; end if;
  rule_document := '{
    "format":{"modality":"futbol7"},
    "registration":{
      "rosterPolicy":{"minimumSize":1,"maximumSize":40,"closeRequiresApprovedRosters":true},
      "matchSheetPolicy":{"squadMin":1,"squadMax":20,"starterMin":1,"starterMax":11,"substituteMax":9}
    },
    "structure":{"stageGraph":{"nodes":[{"id":"league-stage","root":true}],"edges":[]}},
    "operations":{"schedulePolicy":{"format":"DOUBLE_ROUND_ROBIN","legs":2,"matchDurationMinutes":70,"requiredBufferMinutes":10,"minimumRestMinutes":0,"homeAwayPolicy":"BALANCED","venueRequired":false,"maximumHomeAwayStreak":4,"hardHomeAwayStreak":false,"windowStartsAt":"2030-01-01T00:00:00Z","windowEndsAt":"2031-12-31T23:59:59Z","rosterStatuses":["approved","locked"],"softPreferenceWeights":{"day":60,"time":30,"homeAway":10}}},
    "results":{
      "scoringPolicy":{"pointsForWin":3,"pointsForDraw":1,"pointsForLoss":0},
      "tieBreakCriteria":["POINTS","GOAL_DIFFERENCE","GOALS_FOR","WINS","HEAD_TO_HEAD_POINTS","HEAD_TO_HEAD_GOAL_DIFFERENCE","HEAD_TO_HEAD_GOALS_FOR"],
      "scorerDetailPolicy":"OPTIONAL",
      "allowUnknownScorer":false,
      "confirmationPolicy":{"mode":"BILATERAL","responseDeadlineHours":48,"autoOfficialAfterConfirmation":true},
      "standingsPolicy":{"allowSharedPositions":true},
      "publicationPolicy":{"resultsPublic":true,"standingsPublic":true}
    },
    "discipline":{},"governance":{},"publication":{},"futureCapabilities":{}
  }'::jsonb;

  insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
  values (
    organizer_group_id, director_id, 'R4C Scale Organizer ' || scope,
    'S' || scope || 'ORG', '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1
  );
  insert into public.pachanga_group_members(group_id, user_id, role, display_name)
  values (organizer_group_id, director_id, 'owner', 'Scale Director');
  insert into public.pachanga_competitions(
    id, organizer_kind, organizer_group_id, name, slug, competition_type,
    visibility, status, created_by
  ) values (
    competition_id, 'TEAM', organizer_group_id, 'R4C Scale League ' || scope,
    'r4c-scale-league-' || scope, 'LEAGUE', 'public', 'draft', director_id
  );
  insert into public.pachanga_competition_entitlement_grants(
    organizer_kind, organizer_group_id, capability, grant_source, status, reason, granted_by
  ) values
    ('TEAM', organizer_group_id, 'competition_manage', 'platform_grant', 'active', 'R4C scale', director_id),
    ('TEAM', organizer_group_id, 'competition_schedule', 'platform_grant', 'active', 'R4C scale', director_id),
    ('TEAM', organizer_group_id, 'competition_results', 'platform_grant', 'active', 'R4C scale', director_id),
    ('TEAM', organizer_group_id, 'competition_standings', 'platform_grant', 'active', 'R4C scale', director_id);
  insert into public.pachanga_competition_rule_sets(id, competition_id, name, status, created_by)
  values (rule_set_id, competition_id, 'R4C Scale Rules', 'active', director_id);
  insert into public.pachanga_competition_rule_revisions(
    id, rule_set_id, version, schema_version, rule_document, checksum,
    effective_from, effective_scope, status, revision, reason, created_by
  ) values (
    rule_revision_id, rule_set_id, 1, 'competition_rules.v1', rule_document,
    private.pachanga_competition_rule_checksum_v1('competition_rules.v1', rule_document),
    clock_timestamp(), 'future_only', 'frozen', 1, 'R4C scale immutable rules', director_id
  );
  insert into public.pachanga_competition_editions(
    id, competition_id, name, season_label, starts_at, ends_at, status,
    rule_revision_id, registration_mode, registration_closed_at,
    registration_rule_revision_id, revision, created_by
  ) values (
    edition_id, competition_id, 'Scale Edition ' || scope, '2030/31',
    '2030-01-01', '2031-12-31', 'scheduled', rule_revision_id,
    'CLOSED', clock_timestamp(), rule_revision_id, 1, director_id
  );
  insert into public.pachanga_competition_categories(
    id, edition_id, name, slug, sport_format, visibility, status,
    rule_revision_id, revision, created_by
  ) values (
    category_id, edition_id, 'Senior', 'senior-' || scope, 'FOOTBALL_7',
    'public', 'active', rule_revision_id, 1, director_id
  );
  insert into public.pachanga_competition_stages(
    id, edition_id, name, stage_type, stage_order, optional_stage,
    status, rule_revision_id, revision, created_by
  ) values (
    stage_id, edition_id, 'Liga regular', 'LEAGUE_STAGE', 0, false,
    'draft', rule_revision_id, 1, director_id
  );
  insert into public.pachanga_competition_divisions(
    id, stage_id, name, division_order, level_label, status, created_by
  ) values (division_id, stage_id, 'Division 1', 0, 'Open', 'draft', director_id);
  insert into public.pachanga_competition_groups(
    id, stage_id, division_id, name, group_order, status, created_by
  ) values (competition_group_id, stage_id, division_id, 'Grupo A', 0, 'draft', director_id);
  insert into public.pachanga_competition_staff_assignments(
    competition_id, user_id, staff_role, status, assigned_by
  ) values (competition_id, director_id, 'competition_director', 'active', director_id);

  for team_index in 1..team_total loop
    team_id := pg_temp.scale_uuid(scope, 'team', team_index);
    entry_id := pg_temp.scale_uuid(scope, 'entry', team_index);
    membership_id := pg_temp.scale_uuid(scope, 'membership', team_index);
    entry_ids := array_append(entry_ids, entry_id);
    insert into public.pachanga_groups(id, owner_id, name, team_code, payload, payload_revision)
    values (
      team_id, director_id, 'Scale ' || scope || ' Team ' || lpad(team_index::text, 2, '0'),
      'S' || scope || 'T' || lpad(team_index::text, 2, '0'),
      '{"matches":[],"players":[],"siteSettings":{},"venues":[]}', 1
    );
    insert into public.pachanga_competition_entries(
      id, competition_id, edition_id, category_id, team_id, entry_source, status,
      rule_revision_id, accepted_by, accepted_at, reason_code, created_by
    ) values (
      entry_id, competition_id, edition_id, category_id, team_id,
      'ORGANIZER_INVITATION', 'accepted', rule_revision_id, director_id,
      clock_timestamp(), 'r4c.scale.accepted', director_id
    );
    insert into public.pachanga_competition_stage_memberships(
      id, entry_id, stage_id, division_id, competition_group_id, rule_revision_id,
      status, reason, assigned_by
    ) values (
      membership_id, entry_id, stage_id, division_id, competition_group_id,
      rule_revision_id, 'active', 'R4C scale membership', director_id
    );
  end loop;

  insert into public.pachanga_competition_schedule_plans(
    id, competition_id, edition_id, category_id, stage_id, division_id,
    competition_group_id, rule_revision_id, legs, entry_count, status,
    revision, created_by
  ) values (
    plan_id, competition_id, edition_id, category_id, stage_id, division_id,
    competition_group_id, rule_revision_id, 2, team_total, 'draft', 1, director_id
  );
  insert into public.pachanga_competition_schedule_revisions(
    id, schedule_plan_id, version, revision_kind, status, engine_version, seed,
    input_checksum, rule_revision_id, entry_snapshot_checksum,
    slot_snapshot_checksum, constraint_snapshot_checksum,
    preference_snapshot_checksum, entry_order, quality_score, validation_status,
    generated_by, validated_by, validated_at, published_by, published_at, revision
  ) values (
    schedule_revision_id, plan_id, 1, 'generated', 'published',
    'league-round-robin-v1', 'r4c-scale-' || scope,
    repeat('a', 64), rule_revision_id, repeat('b', 64), repeat('c', 64),
    repeat('d', 64), repeat('e', 64), to_jsonb(entry_ids), 100, 'VALID',
    director_id, director_id, clock_timestamp(), director_id, clock_timestamp(), 1
  );

  for round_no in 1..round_total loop
    round_id := pg_temp.scale_uuid(scope, 'round', round_no);
    insert into public.pachanga_competition_rounds(
      id, competition_id, edition_id, category_id, stage_id, division_id,
      competition_group_id, schedule_revision_id, round_number, leg_number,
      display_name, starts_at, ends_at, status, rule_revision_id,
      revision, created_by, published_at
    ) values (
      round_id, competition_id, edition_id, category_id, stage_id, division_id,
      competition_group_id, schedule_revision_id, round_no,
      case when round_no <= team_total - 1 then 1 else 2 end,
      'Jornada ' || round_no,
      '2030-01-01T00:00:00Z'::timestamptz + make_interval(days => round_no),
      '2030-01-02T00:00:00Z'::timestamptz + make_interval(days => round_no),
      'published', rule_revision_id, 1, director_id, clock_timestamp()
    );
  end loop;

  for team_index in 1..team_total - 1 loop
    for opponent_index in team_index + 1..team_total loop
      for leg in 1..2 loop
        match_no := match_no + 1;
        round_no := ((match_no - 1) % round_total) + 1;
        slot_no := ((match_no - 1) / round_total)::integer;
        round_id := pg_temp.scale_uuid(scope, 'round', round_no);
        slot_id := pg_temp.scale_uuid(scope, 'slot', match_no);
        item_id := pg_temp.scale_uuid(scope, 'schedule-item', match_no);
        canonical_match_id := pg_temp.scale_uuid(scope, 'canonical-match', match_no);
        binding_id := pg_temp.scale_uuid(scope, 'binding', match_no);
        context_id := pg_temp.scale_uuid(scope, 'context', match_no);
        result_id := pg_temp.scale_uuid(scope, 'sporting-result', match_no);
        result_revision_id := pg_temp.scale_uuid(scope, 'result-revision', match_no);
        sheet_id := pg_temp.scale_uuid(scope, 'match-sheet', match_no);
        decision_id := pg_temp.scale_uuid(scope, 'official-decision', match_no);
        scheduled_start := '2030-01-01T08:00:00Z'::timestamptz
          + make_interval(days => round_no, hours => slot_no * 2);
        if leg = 1 then
          home_entry_id := entry_ids[team_index];
          away_entry_id := entry_ids[opponent_index];
          score_home := 1;
          score_away := 0;
        else
          home_entry_id := entry_ids[opponent_index];
          away_entry_id := entry_ids[team_index];
          score_home := 0;
          score_away := 1;
        end if;

        insert into public.pachanga_competition_schedule_slots(
          id, competition_id, edition_id, stage_id, division_id, competition_group_id,
          starts_at, ends_at, timezone, venue_label, resource_key, status, revision, created_by
        ) values (
          slot_id, competition_id, edition_id, stage_id, division_id, competition_group_id,
          scheduled_start, scheduled_start + interval '70 minutes', 'Europe/Madrid',
          'Scale pitch ' || ((slot_no % 4) + 1), scope || '-slot-' || match_no,
          'assigned', 1, director_id
        );
        insert into public.pachanga_competition_schedule_items(
          id, schedule_revision_id, round_id, home_entry_id, away_entry_id,
          pairing_key, leg_number, slot_id, scheduled_start, scheduled_end,
          timezone, venue_label, venue_status, status, revision
        ) values (
          item_id, schedule_revision_id, round_id, home_entry_id, away_entry_id,
          encode(extensions.digest(convert_to(scope || ':' || team_index || ':' || opponent_index, 'UTF8'), 'sha256'), 'hex') || ':' || leg,
          leg, slot_id, scheduled_start, scheduled_start + interval '70 minutes',
          'Europe/Madrid', 'Scale pitch ' || ((slot_no % 4) + 1), 'CONFIRMED', 'validated', 1
        );
        insert into public.pachanga_canonical_matches(id, status, revision, created_by)
        values (canonical_match_id, 'active', 1, director_id);
        insert into public.pachanga_canonical_match_bindings(
          id, canonical_match_id, source_kind, source_id, relation_kind,
          binding_status, revision, created_by
        ) values (
          binding_id, canonical_match_id, 'competition_generated', item_id,
          'authoritative_source', 'active', 1, director_id
        );
        insert into public.pachanga_competition_match_contexts(
          id, canonical_match_id, competition_id, edition_id, category_id, stage_id,
          division_id, competition_group_id, rule_revision_id, round_id,
          schedule_item_id, home_entry_id, away_entry_id, slot_id,
          scheduled_start, scheduled_end, timezone, venue_label, venue_status,
          source_kind, status, revision, created_by
        ) values (
          context_id, canonical_match_id, competition_id, edition_id, category_id, stage_id,
          division_id, competition_group_id, rule_revision_id, round_id,
          item_id, home_entry_id, away_entry_id, slot_id,
          scheduled_start, scheduled_start + interval '70 minutes', 'Europe/Madrid',
          'Scale pitch ' || ((slot_no % 4) + 1), 'CONFIRMED',
          'COMPETITION_GENERATED', 'official', 1, director_id
        );
        update public.pachanga_competition_schedule_items items set
          canonical_match_id = builder.canonical_match_id,
          competition_match_context_id = builder.context_id,
          status = 'published',
          revision = 2
        where items.id = builder.item_id;

        insert into public.pachanga_competition_sporting_results(
          id, canonical_match_id, competition_match_context_id, rule_revision_id,
          state, proposed_by_entry_id, confirmation_policy, revision,
          created_by, confirmed_at
        ) values (
          result_id, canonical_match_id, context_id, rule_revision_id,
          'official', home_entry_id, 'BILATERAL', 1, director_id, clock_timestamp()
        );
        insert into public.pachanga_competition_sporting_result_revisions(
          id, sporting_result_id, version, revision_kind, proposed_by_entry_id,
          score_home, score_away, scorer_detail_policy,
          home_unassigned_goals, away_unassigned_goals, content_checksum,
          operation_id, created_by
        ) values (
          result_revision_id, result_id, 1, 'INITIAL', home_entry_id,
          score_home, score_away, 'OPTIONAL', score_home, score_away,
          encode(extensions.digest(convert_to(scope || ':result:' || match_no, 'UTF8'), 'sha256'), 'hex'),
          pg_temp.scale_uuid(scope, 'result-operation', match_no), director_id
        );
        update public.pachanga_competition_sporting_results
        set current_revision_id = result_revision_id
        where id = result_id;
        insert into public.pachanga_competition_match_sheets(
          id, canonical_match_id, competition_match_context_id,
          current_sporting_result_id, created_by
        ) values (sheet_id, canonical_match_id, context_id, result_id, director_id);
        insert into public.pachanga_competition_official_result_decisions(
          id, canonical_match_id, competition_match_context_id, sporting_result_id,
          sporting_result_revision_id, outcome, effective_score_home,
          effective_score_away, reason_code, operation_id, authority_role, decided_by
        ) values (
          decision_id, canonical_match_id, context_id, result_id, result_revision_id,
          'MIRROR_SPORTING_RESULT', score_home, score_away, 'r4c.scale.official',
          pg_temp.scale_uuid(scope, 'decision-operation', match_no),
          'competition_result_manager', director_id
        );
        update public.pachanga_competition_match_sheets
        set active_official_decision_id = decision_id
        where id = sheet_id;
        if first_context_id is null then
          first_context_id := context_id;
          first_canonical_id := canonical_match_id;
        end if;
      end loop;
    end loop;
  end loop;
  update public.pachanga_competition_schedule_plans set
    current_revision_id = schedule_revision_id,
    status = 'published',
    published_at = clock_timestamp(),
    revision = 2
  where id = plan_id;
  insert into pg_temp.r4c_scale_leagues(
    scope, team_count, fixture_count, competition_id, edition_id, stage_id,
    division_id, competition_group_id, rule_revision_id,
    target_context_id, target_canonical_match_id
  ) values (
    scope, team_total, fixture_total, competition_id, edition_id, stage_id,
    division_id, competition_group_id, rule_revision_id,
    first_context_id, first_canonical_id
  );
end;
$$;

update private.pachanga_competition_foundation_settings set
  foundation_enabled = true,
  creation_enabled = true,
  context_binding_enabled = true,
  league_participation_foundation_enabled = true,
  league_registration_enabled = true,
  league_delegates_enabled = true,
  league_rosters_enabled = true,
  league_schedule_preferences_enabled = true,
  league_scheduling_foundation_enabled = true,
  league_schedule_generation_enabled = true,
  league_schedule_editing_enabled = true,
  league_schedule_publication_enabled = true,
  league_public_calendar_enabled = true,
  league_canonical_fixture_creation_enabled = true,
  league_match_operations_foundation_enabled = true,
  league_match_squads_enabled = true,
  league_match_attendance_enabled = true,
  league_sporting_results_enabled = true,
  league_result_confirmation_enabled = true,
  league_official_results_enabled = true,
  league_standings_enabled = true,
  league_public_standings_enabled = true
where singleton;

select pg_temp.build_scale_league('20', 20);
select pg_temp.build_scale_league('32', 32);

do $body$
declare league record;
declare full_result jsonb;
declare incremental_result jsonb;
begin
  for league in select * from pg_temp.r4c_scale_leagues order by team_count loop
    full_result := private.pachanga_league_standings_rebuild_v1(
      league.target_context_id, 'FULL_AUDIT',
      pg_temp.scale_uuid(league.scope, 'full-rebuild', 1),
      'd4010000-0000-4000-8000-000000000001',
      nextval('private.pachanga_competition_sequence')
    );
    incremental_result := private.pachanga_league_standings_rebuild_v1(
      league.target_context_id, 'INCREMENTAL',
      pg_temp.scale_uuid(league.scope, 'incremental-rebuild', 1),
      'd4010000-0000-4000-8000-000000000001',
      nextval('private.pachanga_competition_sequence')
    );
    perform pg_temp.assert_true(
      full_result ->> 'checksum' = incremental_result ->> 'checksum',
      'Scale full/incremental checksum mismatch for ' || league.team_count || ' teams'
    );
    perform pg_temp.assert_true(
      (full_result ->> 'rowCount')::integer = league.team_count,
      'Scale standings row count mismatch for ' || league.team_count || ' teams'
    );
  end loop;
end;
$body$;

do $body$
declare league record;
declare target_result_id uuid;
declare target_context_id uuid;
declare target_sheet_id uuid;
declare previous_revision_id uuid;
declare new_revision_id uuid;
declare previous_decision_id uuid;
declare new_decision_id uuid;
declare state_row public.pachanga_competition_standing_states%rowtype;
declare previous_snapshot_id uuid;
declare new_snapshot_id uuid;
declare counter integer;
begin
  select * into league from pg_temp.r4c_scale_leagues where scope = '32';
  target_context_id := league.target_context_id;
  select results.id, results.current_revision_id
    into target_result_id, previous_revision_id
  from public.pachanga_competition_sporting_results results
  where results.competition_match_context_id = target_context_id;
  select sheets.id, sheets.active_official_decision_id
    into target_sheet_id, previous_decision_id
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = target_context_id;

  for counter in 1..10000 loop
    new_revision_id := pg_temp.scale_uuid('32-history', 'result-revision', counter);
    insert into public.pachanga_competition_sporting_result_revisions(
      id, sporting_result_id, version, previous_revision_id, revision_kind,
      proposed_by_entry_id, score_home, score_away, scorer_detail_policy,
      home_unassigned_goals, away_unassigned_goals, content_checksum,
      operation_id, created_by
    )
    select new_revision_id, target_result_id, counter + 1, previous_revision_id,
      'CHANGE', results.proposed_by_entry_id, 1, 0, 'OPTIONAL', 1, 0,
      encode(extensions.digest(convert_to('r4c-history-revision:' || counter, 'UTF8'), 'sha256'), 'hex'),
      pg_temp.scale_uuid('32-history', 'result-operation', counter),
      'd4010000-0000-4000-8000-000000000001'
    from public.pachanga_competition_sporting_results results
    where results.id = target_result_id;
    previous_revision_id := new_revision_id;
  end loop;
  update public.pachanga_competition_sporting_results
  set current_revision_id = previous_revision_id,
      revision = revision + 10000
  where id = target_result_id;

  for counter in 1..10000 loop
    new_decision_id := pg_temp.scale_uuid('32-history', 'official-decision', counter);
    insert into public.pachanga_competition_official_result_decisions(
      id, canonical_match_id, competition_match_context_id, sporting_result_id,
      sporting_result_revision_id, supersedes_decision_id, outcome,
      effective_score_home, effective_score_away, reason_code, operation_id,
      authority_role, decided_by
    )
    select new_decision_id, contexts.canonical_match_id, contexts.id,
      target_result_id, previous_revision_id, previous_decision_id,
      'CORRECTED_EFFECTIVE_SCORE', 1, 0, 'r4c.scale.history',
      pg_temp.scale_uuid('32-history', 'decision-operation', counter),
      'competition_result_manager', 'd4010000-0000-4000-8000-000000000001'
    from public.pachanga_competition_match_contexts contexts
    where contexts.id = target_context_id;
    previous_decision_id := new_decision_id;
  end loop;
  update public.pachanga_competition_match_sheets
  set active_official_decision_id = previous_decision_id,
      revision = revision + 10000
  where id = target_sheet_id;

  select * into state_row
  from public.pachanga_competition_standing_states states
  where states.stage_id = league.stage_id;
  previous_snapshot_id := state_row.current_snapshot_id;
  for counter in 1..1000 loop
    new_snapshot_id := pg_temp.scale_uuid('32-history', 'standing-snapshot', counter);
    insert into public.pachanga_competition_standing_snapshots(
      id, standing_state_id, competition_id, edition_id, stage_id, division_id,
      competition_group_id, rule_revision_id, supersedes_snapshot_id,
      rebuild_kind, source_revision, row_count, tie_break_criteria,
      content_checksum
    ) values (
      new_snapshot_id, state_row.id, league.competition_id, league.edition_id,
      league.stage_id, league.division_id, league.competition_group_id,
      league.rule_revision_id, previous_snapshot_id, 'INCREMENTAL', counter,
      league.team_count, '["POINTS"]'::jsonb,
      encode(extensions.digest(convert_to('r4c-history-snapshot:' || counter, 'UTF8'), 'sha256'), 'hex')
    );
    insert into public.pachanga_competition_standing_rows(
      standing_snapshot_id, entry_id, position, played, wins, draws, losses,
      goals_for, goals_against, goal_difference, base_points,
      adjustment_points, effective_points, tie_break_values, team_snapshot
    )
    select new_snapshot_id, rows.entry_id, rows.position, rows.played,
      rows.wins, rows.draws, rows.losses, rows.goals_for, rows.goals_against,
      rows.goal_difference, rows.base_points, rows.adjustment_points,
      rows.effective_points, rows.tie_break_values, rows.team_snapshot
    from public.pachanga_competition_standing_rows rows
    where rows.standing_snapshot_id = state_row.current_snapshot_id;
    insert into public.pachanga_competition_standing_rebuild_receipts(
      operation_id, standing_state_id, standing_snapshot_id, rebuild_kind,
      source_revision, previous_checksum, confirmed_checksum, duration_ms
    ) values (
      pg_temp.scale_uuid('32-history', 'rebuild-operation', counter),
      state_row.id, new_snapshot_id, 'INCREMENTAL', counter,
      case when counter = 1 then null else encode(extensions.digest(convert_to('r4c-history-snapshot:' || counter - 1, 'UTF8'), 'sha256'), 'hex') end,
      encode(extensions.digest(convert_to('r4c-history-snapshot:' || counter, 'UTF8'), 'sha256'), 'hex'),
      counter % 25
    );
    previous_snapshot_id := new_snapshot_id;
  end loop;
end;
$body$;

select set_config(
  'request.jwt.claims',
  '{"sub":"d4010000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

create temporary table r4c_scale_timings (
  metric text not null,
  duration_ms numeric not null
) on commit drop;

create temporary table r4c_query_plans (
  metric text primary key,
  plan jsonb not null
) on commit drop;

create or replace function pg_temp.measure(statement text, metric_name text, samples integer)
returns void language plpgsql as $$
declare started_at timestamptz;
declare counter integer;
begin
  for counter in 1..samples loop
    started_at := clock_timestamp();
    execute statement;
    insert into pg_temp.r4c_scale_timings(metric, duration_ms)
    values (metric_name, extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$$;

create or replace function pg_temp.capture_plan(statement text, metric_name text)
returns void language plpgsql as $$
declare captured jsonb;
begin
  execute 'explain (analyze, buffers, format json) ' || statement into captured;
  insert into pg_temp.r4c_query_plans(metric, plan) values (metric_name, captured);
end;
$$;

do $body$
declare league record;
declare state_id uuid;
declare started_at timestamptz;
declare counter integer;
begin
  select * into league from pg_temp.r4c_scale_leagues where scope = '32';
  select states.id into state_id
  from public.pachanga_competition_standing_states states
  where states.stage_id = league.stage_id;
  perform pg_temp.measure(
    format('select private.pachanga_league_match_snapshot_v1(%L::uuid,%L::uuid)', league.target_context_id, 'd4010000-0000-4000-8000-000000000001'),
    'match_view_32', 40
  );
  perform pg_temp.measure(
    format('select private.pachanga_league_standings_snapshot_v1(%L::uuid,false)', state_id),
    'standings_view_32', 40
  );
  perform pg_temp.measure(
    format('select public.get_pachanga_public_league_standings_v1(%L::uuid,%L::uuid,%L::uuid,%L::uuid)', league.competition_id, league.stage_id, league.division_id, league.competition_group_id),
    'public_standings_32', 40
  );
  perform pg_temp.measure(
    format('select public.get_pachanga_league_result_desk_v1(%L::uuid,null,200,0)', league.competition_id),
    'result_desk_32', 40
  );
  for counter in 1..20 loop
    started_at := clock_timestamp();
    perform private.pachanga_league_standings_rebuild_v1(
      league.target_context_id, 'FULL_AUDIT',
      pg_temp.scale_uuid('32-performance', 'full-rebuild', counter),
      'd4010000-0000-4000-8000-000000000001',
      nextval('private.pachanga_competition_sequence')
    );
    insert into pg_temp.r4c_scale_timings(metric, duration_ms)
    values ('full_standings_rebuild_32', extract(epoch from (clock_timestamp() - started_at)) * 1000);

    started_at := clock_timestamp();
    perform private.pachanga_league_standings_rebuild_v1(
      league.target_context_id, 'INCREMENTAL',
      pg_temp.scale_uuid('32-performance', 'incremental-rebuild', counter),
      'd4010000-0000-4000-8000-000000000001',
      nextval('private.pachanga_competition_sequence')
    );
    insert into pg_temp.r4c_scale_timings(metric, duration_ms)
    values ('incremental_standings_rebuild_32', extract(epoch from (clock_timestamp() - started_at)) * 1000);
  end loop;
end;
$body$;

do $body$
declare league record;
declare state_id uuid;
declare current_snapshot_id uuid;
declare current_result_revision_id uuid;
declare first_entry_id uuid;
declare second_entry_id uuid;
declare first_round_id uuid;
begin
  select * into league from pg_temp.r4c_scale_leagues where scope = '32';
  select states.id, states.current_snapshot_id into state_id, current_snapshot_id
  from public.pachanga_competition_standing_states states
  where states.stage_id = league.stage_id;
  select results.current_revision_id into current_result_revision_id
  from public.pachanga_competition_sporting_results results
  where results.competition_match_context_id = league.target_context_id;
  select memberships.entry_id into first_entry_id
  from public.pachanga_competition_stage_memberships memberships
  where memberships.stage_id = league.stage_id
  order by memberships.entry_id limit 1;
  select memberships.entry_id into second_entry_id
  from public.pachanga_competition_stage_memberships memberships
  where memberships.stage_id = league.stage_id and memberships.entry_id <> first_entry_id
  order by memberships.entry_id limit 1;
  select contexts.round_id into first_round_id
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = league.target_context_id;

  perform pg_temp.capture_plan(format(
    'select decisions.id from public.pachanga_competition_match_contexts contexts join public.pachanga_competition_match_sheets sheets on sheets.competition_match_context_id=contexts.id join public.pachanga_competition_official_result_decisions decisions on decisions.id=sheets.active_official_decision_id where contexts.stage_id=%L::uuid and contexts.status=''official''',
    league.stage_id
  ), 'active_official_results');
  perform pg_temp.capture_plan(format(
    'select results.id, revisions.score_home, revisions.score_away from public.pachanga_competition_match_contexts contexts join public.pachanga_competition_sporting_results results on results.competition_match_context_id=contexts.id join public.pachanga_competition_sporting_result_revisions revisions on revisions.id=results.current_revision_id where contexts.stage_id=%L::uuid',
    league.stage_id
  ), 'results_by_stage');
  perform pg_temp.capture_plan(format(
    'select decisions.effective_score_home, decisions.effective_score_away from public.pachanga_competition_match_contexts contexts join public.pachanga_competition_match_sheets sheets on sheets.competition_match_context_id=contexts.id join public.pachanga_competition_official_result_decisions decisions on decisions.id=sheets.active_official_decision_id where contexts.stage_id=%L::uuid and contexts.home_entry_id in (%L::uuid,%L::uuid) and contexts.away_entry_id in (%L::uuid,%L::uuid)',
    league.stage_id, first_entry_id, second_entry_id, first_entry_id, second_entry_id
  ), 'head_to_head');
  perform pg_temp.capture_plan(format(
    'select scorers.* from public.pachanga_competition_sporting_result_scorers scorers where scorers.sporting_result_revision_id=%L::uuid order by scorers.server_sequence, scorers.id',
    current_result_revision_id
  ), 'scorer_lookup');
  perform pg_temp.capture_plan(
    'select members.* from public.pachanga_competition_match_squad_members members where members.squad_revision_id=''00000000-0000-0000-0000-000000000001''::uuid order by members.position_order, members.server_sequence',
    'squad_members'
  );
  perform pg_temp.capture_plan(format(
    'select rows.* from public.pachanga_competition_standing_rows rows where rows.standing_snapshot_id=%L::uuid order by rows.position, rows.entry_id',
    current_snapshot_id
  ), 'current_standing_snapshot');
  perform pg_temp.capture_plan(format(
    'select count(*) filter (where contexts.status=''official'') as official, count(*) filter (where contexts.status<>''official'') as pending from public.pachanga_competition_match_contexts contexts where contexts.round_id=%L::uuid',
    first_round_id
  ), 'round_completion');
end;
$body$;

do $body$
declare league record;
declare full_result jsonb;
declare incremental_result jsonb;
begin
  select * into league from pg_temp.r4c_scale_leagues where scope = '32';
  full_result := private.pachanga_league_standings_rebuild_v1(
    league.target_context_id, 'FULL_AUDIT',
    pg_temp.scale_uuid('32', 'post-history-full', 1),
    'd4010000-0000-4000-8000-000000000001',
    nextval('private.pachanga_competition_sequence')
  );
  incremental_result := private.pachanga_league_standings_rebuild_v1(
    league.target_context_id, 'INCREMENTAL',
    pg_temp.scale_uuid('32', 'post-history-incremental', 1),
    'd4010000-0000-4000-8000-000000000001',
    nextval('private.pachanga_competition_sequence')
  );
  perform pg_temp.assert_true(
    full_result ->> 'checksum' = incremental_result ->> 'checksum',
    'Post-history full/incremental checksum mismatch'
  );
end;
$body$;

select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_match_contexts contexts
    join pg_temp.r4c_scale_leagues leagues on leagues.competition_id = contexts.competition_id
    where leagues.scope = '20') = 380,
  '20-team fixture count mismatch'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_match_contexts contexts
    join pg_temp.r4c_scale_leagues leagues on leagues.competition_id = contexts.competition_id
    where leagues.scope = '32') = 992,
  '32-team fixture count mismatch'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_sporting_result_revisions revisions
    join public.pachanga_competition_sporting_results results on results.id = revisions.sporting_result_id
    join pg_temp.r4c_scale_leagues leagues on leagues.competition_id = (
      select contexts.competition_id from public.pachanga_competition_match_contexts contexts where contexts.id = results.competition_match_context_id
    ) where leagues.scope = '32') >= 10992,
  '10,000 result revisions were not loaded'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_official_result_decisions decisions
    join public.pachanga_competition_match_contexts contexts on contexts.id = decisions.competition_match_context_id
    join pg_temp.r4c_scale_leagues leagues on leagues.competition_id = contexts.competition_id
    where leagues.scope = '32') >= 10992,
  '10,000 official decisions were not loaded'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_competition_standing_rebuild_receipts receipts
    join public.pachanga_competition_standing_states states on states.id = receipts.standing_state_id
    join pg_temp.r4c_scale_leagues leagues on leagues.stage_id = states.stage_id
    where leagues.scope = '32') >= 1004,
  '1,000 historical rebuilds were not loaded'
);

select jsonb_build_object(
  'scale', jsonb_build_object(
    '20Teams', jsonb_build_object('fixtures', 380, 'officialResults', 380),
    '32Teams', jsonb_build_object('fixtures', 992, 'officialResults', 992),
    'resultRevisions', 10000,
    'officialDecisions', 10000,
    'historicalRebuilds', 1000
  ),
  'timings', (
    select jsonb_object_agg(metric, jsonb_build_object(
      'samples', samples,
      'p50Ms', p50,
      'p95Ms', p95,
      'maxMs', maximum
    ) order by metric)
    from (
      select metric, count(*) as samples,
        round(percentile_cont(0.50) within group (order by duration_ms)::numeric, 3) as p50,
        round(percentile_cont(0.95) within group (order by duration_ms)::numeric, 3) as p95,
        round(max(duration_ms), 3) as maximum
      from pg_temp.r4c_scale_timings
      group by metric
    ) statistics
  ),
  'queryPlans', (
    select jsonb_object_agg(plans.metric, jsonb_build_object(
      'topNode', plans.plan #>> '{0,Plan,Node Type}',
      'planningMs', round((plans.plan #>> '{0,Planning Time}')::numeric, 3),
      'executionMs', round((plans.plan #>> '{0,Execution Time}')::numeric, 3),
      'indexes', coalesce((
        select jsonb_agg(distinct matches.name order by matches.name)
        from regexp_matches(plans.plan::text, '"Index Name": "([^"]+)"', 'g') matches(name)
      ), '[]'::jsonb)
    ) order by plans.metric)
    from pg_temp.r4c_query_plans plans
  ),
  'historySelectionStable', (
    select ordered.id = maximum.id
    from lateral (
      select snapshots.id
      from public.pachanga_competition_standing_snapshots snapshots
      join public.pachanga_competition_standing_states states on states.id = snapshots.standing_state_id
      join pg_temp.r4c_scale_leagues leagues on leagues.stage_id = states.stage_id and leagues.scope = '32'
      order by snapshots.server_sequence desc, snapshots.id desc
      limit 1
    ) ordered
    cross join lateral (
      select snapshots.id
      from public.pachanga_competition_standing_snapshots snapshots
      join public.pachanga_competition_standing_states states on states.id = snapshots.standing_state_id
      join pg_temp.r4c_scale_leagues leagues on leagues.stage_id = states.stage_id and leagues.scope = '32'
      where snapshots.server_sequence = (
        select max(candidate.server_sequence)
        from public.pachanga_competition_standing_snapshots candidate
        where candidate.standing_state_id = states.id
      )
      order by snapshots.id desc
      limit 1
    ) maximum
  )
)::text;

rollback;
