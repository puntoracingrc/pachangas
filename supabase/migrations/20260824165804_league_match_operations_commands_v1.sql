-- Pachangas IQ R4C: server-authoritative League match commands and standings engine.

set lock_timeout = '5s';
set statement_timeout = '120s';

create or replace function private.pachanga_competition_can_v1(
  target_competition_id uuid,
  target_actor_id uuid,
  target_capability text
)
returns boolean
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
begin
  if actor_role in ('service_authority', 'platform_owner', 'platform_admin', 'competition_owner') then
    return true;
  end if;
  return case actor_role
    when 'competition_director' then target_capability in (
      'read', 'manage', 'staff', 'rules', 'referees', 'entries_manage',
      'rosters_review', 'categories_manage', 'schedule_read', 'schedule_manage',
      'schedule_publish', 'results_read', 'results_manage', 'standings_read',
      'standings_manage'
    )
    when 'competition_admin' then target_capability in (
      'read', 'manage', 'entries_manage', 'rosters_review', 'categories_manage',
      'schedule_read', 'schedule_manage', 'schedule_publish', 'results_read',
      'results_manage', 'standings_read', 'standings_manage'
    )
    when 'competition_schedule_manager' then target_capability in (
      'read', 'schedule_read', 'schedule_manage', 'schedule_publish'
    )
    when 'competition_result_manager' then target_capability in (
      'read', 'results_read', 'results_manage', 'standings_read'
    )
    when 'competition_standings_manager' then target_capability in (
      'read', 'results_read', 'standings_read', 'standings_manage'
    )
    when 'competition_registration_manager' then target_capability in ('read', 'entries_manage')
    when 'competition_roster_manager' then target_capability in ('read', 'rosters_review')
    when 'rules_manager' then target_capability in ('read', 'rules')
    when 'competition_referee_manager' then target_capability in ('read', 'referees')
    when 'viewer' then target_capability in (
      'read', 'schedule_read', 'results_read', 'standings_read'
    )
    else false
  end;
end;
$$;

revoke all on function private.pachanga_competition_can_v1(uuid, uuid, text)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_operations_flags_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select jsonb_build_object(
    'foundationEnabled', settings.league_match_operations_foundation_enabled,
    'squadsEnabled', settings.league_match_squads_enabled,
    'attendanceEnabled', settings.league_match_attendance_enabled,
    'sportingResultsEnabled', settings.league_sporting_results_enabled,
    'resultConfirmationEnabled', settings.league_result_confirmation_enabled,
    'officialResultsEnabled', settings.league_official_results_enabled,
    'standingsEnabled', settings.league_standings_enabled,
    'publicStandingsEnabled', settings.league_public_standings_enabled,
    'engineVersion', 'league-standings-v1',
    'revision', settings.revision,
    'serverSequence', settings.server_sequence,
    'updatedAt', settings.updated_at
  )
  from private.pachanga_competition_foundation_settings settings
  where settings.singleton;
$$;

revoke all on function private.pachanga_league_match_operations_flags_v1()
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_assert_flags_v1(
  require_squads boolean default false,
  require_attendance boolean default false,
  require_sporting_results boolean default false,
  require_confirmation boolean default false,
  require_official_results boolean default false,
  require_standings boolean default false
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare settings private.pachanga_competition_foundation_settings%rowtype;
begin
  select * into settings
  from private.pachanga_competition_foundation_settings current_settings
  where current_settings.singleton;
  if not settings.league_match_operations_foundation_enabled then
    raise exception 'LEAGUE_MATCH_OPERATIONS_DISABLED' using errcode = '42501';
  end if;
  if require_squads and not settings.league_match_squads_enabled then
    raise exception 'LEAGUE_MATCH_SQUADS_DISABLED' using errcode = '42501';
  end if;
  if require_attendance and not settings.league_match_attendance_enabled then
    raise exception 'LEAGUE_MATCH_ATTENDANCE_DISABLED' using errcode = '42501';
  end if;
  if require_sporting_results and not settings.league_sporting_results_enabled then
    raise exception 'LEAGUE_SPORTING_RESULTS_DISABLED' using errcode = '42501';
  end if;
  if require_confirmation and not settings.league_result_confirmation_enabled then
    raise exception 'LEAGUE_RESULT_CONFIRMATION_DISABLED' using errcode = '42501';
  end if;
  if require_official_results and not settings.league_official_results_enabled then
    raise exception 'LEAGUE_OFFICIAL_RESULTS_DISABLED' using errcode = '42501';
  end if;
  if require_standings and not settings.league_standings_enabled then
    raise exception 'LEAGUE_STANDINGS_DISABLED' using errcode = '42501';
  end if;
end;
$$;

revoke all on function private.pachanga_league_match_assert_flags_v1(
  boolean, boolean, boolean, boolean, boolean, boolean
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_policy_v1(target_rule_revision_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare document jsonb := private.pachanga_league_rule_document_v1(target_rule_revision_id);
declare scoring jsonb := coalesce(document #> '{results,scoringPolicy}', '{}'::jsonb);
declare match_sheet jsonb := coalesce(document #> '{registration,matchSheetPolicy}', '{}'::jsonb);
declare confirmation jsonb := coalesce(document #> '{results,confirmationPolicy}', '{}'::jsonb);
declare standings jsonb := coalesce(document #> '{results,standingsPolicy}', '{}'::jsonb);
declare raw_criteria jsonb := coalesce(document #> '{results,tieBreakCriteria}', '[]'::jsonb);
declare normalized_criteria jsonb := '[]'::jsonb;
declare criterion jsonb;
declare criterion_code text;
declare win_points numeric;
declare draw_points numeric;
declare loss_points numeric;
declare squad_min integer;
declare squad_max integer;
declare starter_min integer;
declare starter_max integer;
declare substitute_max integer;
declare scorer_policy text;
declare confirmation_mode text;
declare deadline_hours integer;
begin
  begin
    win_points := coalesce(
      nullif(scoring ->> 'pointsForWin', '')::numeric,
      nullif(scoring ->> 'win', '')::numeric
    );
    draw_points := coalesce(
      nullif(scoring ->> 'pointsForDraw', '')::numeric,
      nullif(scoring ->> 'draw', '')::numeric
    );
    loss_points := coalesce(
      nullif(scoring ->> 'pointsForLoss', '')::numeric,
      nullif(scoring ->> 'loss', '')::numeric
    );
    squad_min := nullif(match_sheet ->> 'squadMin', '')::integer;
    squad_max := nullif(match_sheet ->> 'squadMax', '')::integer;
    starter_min := nullif(match_sheet ->> 'starterMin', '')::integer;
    starter_max := nullif(match_sheet ->> 'starterMax', '')::integer;
    substitute_max := nullif(match_sheet ->> 'substituteMax', '')::integer;
    deadline_hours := coalesce(nullif(confirmation ->> 'responseDeadlineHours', '')::integer, 72);
  exception when others then
    raise exception 'R4C_RULE_POLICY_INVALID' using errcode = '22023';
  end;
  if win_points is null or draw_points is null or loss_points is null then
    raise exception 'R4C_SCORING_POLICY_REQUIRED' using errcode = '22023';
  end if;
  if squad_min is null or squad_max is null or starter_min is null
     or starter_max is null or substitute_max is null
     or squad_min < 1 or squad_max < squad_min or starter_min < 1
     or starter_max < starter_min or starter_max > squad_max
     or substitute_max < 0 or starter_max + substitute_max < squad_min then
    raise exception 'R4C_MATCH_SHEET_POLICY_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(raw_criteria) <> 'array' or jsonb_array_length(raw_criteria) = 0 then
    raise exception 'R4C_TIE_BREAK_POLICY_REQUIRED' using errcode = '22023';
  end if;
  for criterion in select value from jsonb_array_elements(raw_criteria)
  loop
    criterion_code := upper(trim(case
      when jsonb_typeof(criterion) = 'string' then criterion #>> '{}'
      else coalesce(criterion ->> 'code', criterion ->> 'criterion', '')
    end));
    criterion_code := case criterion_code
      when 'OVERALL_GOAL_DIFFERENCE' then 'GOAL_DIFFERENCE'
      when 'OVERALL_GOALS_FOR' then 'GOALS_FOR'
      when 'PERSISTED_DRAW' then 'PERSISTED_DRAW_LOT'
      else criterion_code
    end;
    if criterion_code in ('FAIR_PLAY', 'FAIR_PLAY_POINTS', 'CARDS', 'DISCIPLINARY_POINTS') then
      raise exception 'FEATURE_NOT_AVAILABLE_UNTIL_R5' using errcode = '0A000';
    end if;
    if criterion_code not in (
      'POINTS', 'GOAL_DIFFERENCE', 'GOALS_FOR', 'WINS',
      'HEAD_TO_HEAD_POINTS', 'HEAD_TO_HEAD_GOAL_DIFFERENCE',
      'HEAD_TO_HEAD_GOALS_FOR', 'PERSISTED_DRAW_LOT'
    ) then raise exception 'R4C_TIE_BREAK_CRITERION_NOT_SUPPORTED' using errcode = '0A000'; end if;
    if criterion_code <> 'POINTS' then
      normalized_criteria := normalized_criteria || jsonb_build_array(criterion_code);
    end if;
  end loop;
  scorer_policy := upper(coalesce(
    nullif(document #>> '{results,scorerDetailPolicy}', ''),
    nullif(match_sheet ->> 'scorerDetailPolicy', ''),
    'OPTIONAL'
  ));
  if scorer_policy not in ('REQUIRED', 'OPTIONAL', 'DISABLED') then
    raise exception 'R4C_SCORER_POLICY_INVALID' using errcode = '22023';
  end if;
  confirmation_mode := upper(coalesce(nullif(confirmation ->> 'mode', ''), 'BILATERAL'));
  if confirmation_mode not in ('BILATERAL', 'AUTO_CONFIRM_AFTER_DEADLINE') then
    raise exception 'R4C_CONFIRMATION_POLICY_INVALID' using errcode = '22023';
  end if;
  if deadline_hours < 1 or deadline_hours > 720 then
    raise exception 'R4C_CONFIRMATION_DEADLINE_INVALID' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'pointsForWin', win_points,
    'pointsForDraw', draw_points,
    'pointsForLoss', loss_points,
    'tieBreakCriteria', normalized_criteria,
    'allowSharedPositions', coalesce((standings ->> 'allowSharedPositions')::boolean, false),
    'squadMin', squad_min,
    'squadMax', squad_max,
    'starterMin', starter_min,
    'starterMax', starter_max,
    'substituteMax', substitute_max,
    'scorerDetailPolicy', scorer_policy,
    'allowUnknownScorer', coalesce((document #>> '{results,allowUnknownScorer}')::boolean, false),
    'confirmationPolicy', confirmation_mode,
    'responseDeadlineHours', deadline_hours,
    'autoOfficialAfterConfirmation', coalesce(
      (confirmation ->> 'autoOfficialAfterConfirmation')::boolean,
      false
    ),
    'publicResults', coalesce((document #>> '{results,publicationPolicy,resultsPublic}')::boolean, false),
    'publicStandings', coalesce((document #>> '{results,publicationPolicy,standingsPublic}')::boolean, false),
    'pointsAdjustments', '[]'::jsonb,
    'disciplineValidationStatus', 'NOT_AVAILABLE'
  );
end;
$$;

revoke all on function private.pachanga_league_match_policy_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_sanitize_metadata_v1(input jsonb)
returns jsonb
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'clientVersion', left(nullif(trim(coalesce(input ->> 'clientVersion', '')), ''), 80),
    'serviceWorkerVersion', left(nullif(trim(coalesce(input ->> 'serviceWorkerVersion', '')), ''), 80),
    'displayMode', case lower(coalesce(input ->> 'displayMode', input ->> 'installedMode', 'browser'))
      when 'standalone' then 'standalone'
      when 'fullscreen' then 'fullscreen'
      when 'minimal-ui' then 'minimal-ui'
      else 'browser'
    end,
    'surface', left(nullif(trim(coalesce(input ->> 'surface', '')), ''), 80),
    'session', case when nullif(trim(coalesce(input ->> 'sessionId', '')), '') is null then null
      else encode(extensions.digest(convert_to(left(input ->> 'sessionId', 160), 'UTF8'), 'sha256'), 'hex') end
  ));
$$;

revoke all on function private.pachanga_league_match_sanitize_metadata_v1(jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_request_hash_v1(
  target_action text,
  target_aggregate_id uuid,
  target_expected_revision bigint,
  target_payload jsonb
)
returns text
language sql
immutable
security definer
set search_path = pg_catalog
as $$
  select encode(extensions.digest(convert_to(
    jsonb_build_object(
      'action', target_action,
      'aggregateId', target_aggregate_id,
      'expectedRevision', target_expected_revision,
      'payload', coalesce(target_payload, '{}'::jsonb)
    )::text,
    'UTF8'
  ), 'sha256'), 'hex');
$$;

revoke all on function private.pachanga_league_match_request_hash_v1(text, uuid, bigint, jsonb)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_operation_replay_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_action text,
  target_aggregate_id uuid,
  target_request_hash text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare receipt private.pachanga_competition_operation_receipts%rowtype;
begin
  select * into receipt
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = target_operation_id;
  if not found then return null; end if;
  if receipt.actor_id is distinct from target_actor_id
     or receipt.action <> target_action
     or receipt.aggregate_type <> 'league_match_operations'
     or receipt.aggregate_id <> target_aggregate_id::text
     or receipt.request_hash <> target_request_hash then
    raise exception 'IDEMPOTENCY_KEY_REUSED' using errcode = 'PT409';
  end if;
  return receipt.response;
end;
$$;

revoke all on function private.pachanga_league_match_operation_replay_v1(
  uuid, uuid, text, uuid, text
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_context_v1(target_context_id uuid)
returns public.pachanga_competition_match_contexts
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare selected public.pachanga_competition_match_contexts%rowtype;
declare competition_type text;
declare item_status text;
declare source_kind text;
begin
  select * into selected
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id;
  if not found then raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
  select competitions.competition_type into competition_type
  from public.pachanga_competitions competitions where competitions.id = selected.competition_id;
  if competition_type <> 'LEAGUE' then
    raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
  end if;
  if selected.source_kind <> 'COMPETITION_GENERATED' or selected.schedule_item_id is null then
    raise exception 'R4C_REQUIRES_COMPETITION_GENERATED_CANONICAL_MATCH' using errcode = '22023';
  end if;
  select items.status into item_status
  from public.pachanga_competition_schedule_items items
  where items.id = selected.schedule_item_id
    and items.canonical_match_id = selected.canonical_match_id
    and items.competition_match_context_id = selected.id;
  if item_status <> 'published' then
    raise exception 'R4C_FIXTURE_NOT_PUBLISHED' using errcode = '22023';
  end if;
  select bindings.source_kind into source_kind
  from public.pachanga_canonical_match_bindings bindings
  where bindings.canonical_match_id = selected.canonical_match_id
    and bindings.binding_status = 'active'
    and bindings.source_kind = 'competition_generated'
  order by bindings.server_sequence desc, bindings.id desc
  limit 1;
  if source_kind is null then
    raise exception 'R4C_CANONICAL_BINDING_NOT_FOUND' using errcode = '22023';
  end if;
  if selected.home_entry_id is null or selected.away_entry_id is null
     or selected.rule_revision_id is null or selected.round_id is null then
    raise exception 'R4C_MATCH_CONTEXT_INCOMPLETE' using errcode = '22023';
  end if;
  return selected;
end;
$$;

revoke all on function private.pachanga_league_match_context_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_assert_entry_v1(
  target_context_id uuid,
  target_entry_id uuid
)
returns public.pachanga_competition_entries
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype := private.pachanga_league_match_context_v1(target_context_id);
declare entry_row public.pachanga_competition_entries%rowtype;
begin
  if target_entry_id not in (context_row.home_entry_id, context_row.away_entry_id) then
    raise exception 'R4C_ENTRY_NOT_IN_MATCH' using errcode = '42501';
  end if;
  select * into entry_row from public.pachanga_competition_entries entries
  where entries.id = target_entry_id
    and entries.competition_id = context_row.competition_id
    and entries.edition_id = context_row.edition_id
    and entries.status in ('accepted', 'active');
  if not found then raise exception 'R4C_ENTRY_NOT_ACTIVE' using errcode = '22023'; end if;
  if not exists (
    select 1 from public.pachanga_competition_stage_memberships memberships
    where memberships.entry_id = target_entry_id
      and memberships.stage_id = context_row.stage_id
      and memberships.status = 'active'
      and memberships.rule_revision_id = context_row.rule_revision_id
      and memberships.division_id is not distinct from context_row.division_id
      and memberships.competition_group_id is not distinct from context_row.competition_group_id
  ) then raise exception 'R4C_STAGE_MEMBERSHIP_NOT_ACTIVE' using errcode = '22023'; end if;
  return entry_row;
end;
$$;

revoke all on function private.pachanga_league_match_assert_entry_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_assert_team_actor_v1(
  target_entry_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_scope text := private.pachanga_league_entry_actor_scope_v1(target_entry_id, target_actor_id);
begin
  if coalesce(actor_scope, '') not in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER') then
    raise exception 'R4C_TEAM_MATCH_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  return actor_scope;
end;
$$;

revoke all on function private.pachanga_league_match_assert_team_actor_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_assert_result_manager_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
begin
  if not private.pachanga_competition_can_v1(target_competition_id, target_actor_id, 'results_manage') then
    raise exception 'COMPETITION_RESULT_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  return actor_role;
end;
$$;

revoke all on function private.pachanga_league_match_assert_result_manager_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_assert_standings_manager_v1(
  target_competition_id uuid,
  target_actor_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare actor_role text := private.pachanga_competition_actor_role_v1(target_competition_id, target_actor_id);
begin
  if not private.pachanga_competition_can_v1(target_competition_id, target_actor_id, 'standings_manage') then
    raise exception 'COMPETITION_STANDINGS_MANAGER_REQUIRED' using errcode = '42501';
  end if;
  return actor_role;
end;
$$;

revoke all on function private.pachanga_league_match_assert_standings_manager_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_create_squad_revision_v1(
  target_squad_id uuid,
  target_revision_action text,
  target_payload jsonb,
  target_new_status text,
  target_actor_id uuid,
  target_reason text,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare squad_row public.pachanga_competition_match_squads%rowtype;
declare source_revision public.pachanga_competition_match_squad_revisions%rowtype;
declare roster_member public.pachanga_competition_roster_members%rowtype;
declare new_revision_id uuid := gen_random_uuid();
declare new_version integer;
declare selected_roster_member_id uuid;
declare selected_role text;
declare selected_number integer;
declare selected_order integer;
declare selected_captain boolean;
declare computed_member_count integer;
declare computed_starter_count integer;
declare computed_substitute_count integer;
declare captain_id uuid;
declare computed_member_checksum text;
declare computed_lineup_checksum text;
begin
  select * into squad_row
  from public.pachanga_competition_match_squads squads
  where squads.id = target_squad_id for update;
  if not found then raise exception 'R4C_SQUAD_NOT_FOUND' using errcode = 'P0002'; end if;
  if squad_row.status = 'locked' then
    raise exception 'R4C_SQUAD_LOCKED' using errcode = 'PT409';
  end if;
  if squad_row.current_revision_id is not null then
    select * into source_revision
    from public.pachanga_competition_match_squad_revisions revisions
    where revisions.id = squad_row.current_revision_id;
  end if;
  new_version := coalesce(source_revision.version, 0) + 1;
  if target_revision_action = 'ADD' then
    selected_roster_member_id := nullif(target_payload ->> 'rosterMemberId', '')::uuid;
    selected_role := upper(coalesce(target_payload ->> 'memberRole', ''));
    selected_number := nullif(target_payload ->> 'shirtNumber', '')::integer;
    selected_order := coalesce(nullif(target_payload ->> 'positionOrder', '')::integer, 0);
    selected_captain := coalesce((target_payload ->> 'isCaptain')::boolean, false);
    if selected_roster_member_id is null or selected_role not in ('STARTER', 'SUBSTITUTE')
       or selected_order < 0 then
      raise exception 'R4C_SQUAD_MEMBER_INVALID' using errcode = '22023';
    end if;
  elsif target_revision_action = 'REMOVE' then
    selected_roster_member_id := nullif(target_payload ->> 'rosterMemberId', '')::uuid;
    if selected_roster_member_id is null or source_revision.id is null or not exists (
      select 1 from public.pachanga_competition_match_squad_members members
      where members.squad_revision_id = source_revision.id
        and members.roster_member_id = selected_roster_member_id
    ) then raise exception 'R4C_SQUAD_MEMBER_NOT_FOUND' using errcode = 'P0002'; end if;
  end if;
  insert into public.pachanga_competition_match_squad_revisions(
    id, squad_id, version, squad_status, roster_revision_id, rule_revision_id,
    member_count, starter_count, substitute_count, member_set_checksum,
    lineup_checksum, reason, created_by, server_sequence
  ) values (
    new_revision_id, squad_row.id, new_version, target_new_status,
    squad_row.roster_revision_id, squad_row.rule_revision_id,
    0, 0, 0, repeat('0', 64), repeat('0', 64),
    left(coalesce(nullif(trim(target_reason), ''), target_revision_action), 1200),
    target_actor_id, target_server_sequence
  );
  if source_revision.id is not null then
    insert into public.pachanga_competition_match_squad_members(
      squad_revision_id, roster_member_id, player_profile_id, member_role,
      shirt_number, position_order, is_captain, public_snapshot, server_sequence
    ) select
      new_revision_id, members.roster_member_id, members.player_profile_id,
      members.member_role, members.shirt_number, members.position_order,
      case when target_revision_action = 'ADD' and selected_captain then false
        else members.is_captain end,
      members.public_snapshot, target_server_sequence
    from public.pachanga_competition_match_squad_members members
    where members.squad_revision_id = source_revision.id
      and not (
        target_revision_action = 'REMOVE'
        and members.roster_member_id = nullif(target_payload ->> 'rosterMemberId', '')::uuid
      )
      and not (
        target_revision_action = 'ADD'
        and members.roster_member_id = selected_roster_member_id
      )
    order by members.position_order, members.server_sequence, members.id;
  end if;
  if target_revision_action = 'ADD' then
    select * into roster_member
    from public.pachanga_competition_roster_members members
    where members.id = selected_roster_member_id
      and members.roster_id = squad_row.roster_id
      and members.roster_revision_id = squad_row.roster_revision_id
      and members.entry_id = squad_row.entry_id
      and members.eligibility_status in ('eligible', 'waived')
      and (members.effective_until is null or members.effective_until > clock_timestamp());
    if not found then raise exception 'R4C_ROSTER_MEMBER_NOT_ELIGIBLE' using errcode = '22023'; end if;
    if exists (
      select 1
      from public.pachanga_competition_match_squads other_squads
      join public.pachanga_competition_match_squad_members other_members
        on other_members.squad_revision_id = other_squads.current_revision_id
      where other_squads.canonical_match_id = squad_row.canonical_match_id
        and other_squads.id <> squad_row.id
        and other_members.player_profile_id = roster_member.player_profile_id
    ) then raise exception 'R4C_PLAYER_ON_BOTH_TEAMS' using errcode = 'PT409'; end if;
    insert into public.pachanga_competition_match_squad_members(
      squad_revision_id, roster_member_id, player_profile_id, member_role,
      shirt_number, position_order, is_captain, public_snapshot, server_sequence
    ) values (
      new_revision_id, roster_member.id, roster_member.player_profile_id,
      selected_role, selected_number, selected_order, selected_captain,
      roster_member.public_snapshot, target_server_sequence
    );
  end if;
  select
    count(*)::integer,
    count(*) filter (where members.member_role = 'STARTER')::integer,
    count(*) filter (where members.member_role = 'SUBSTITUTE')::integer,
    (array_agg(members.player_profile_id order by members.player_profile_id)
      filter (where members.is_captain))[1]
  into computed_member_count, computed_starter_count,
    computed_substitute_count, captain_id
  from public.pachanga_competition_match_squad_members members
  where members.squad_revision_id = new_revision_id;
  select encode(extensions.digest(convert_to(coalesce(string_agg(
    members.player_profile_id::text, ',' order by members.player_profile_id
  ), ''), 'UTF8'), 'sha256'), 'hex'),
  encode(extensions.digest(convert_to(coalesce(string_agg(
    members.player_profile_id::text || ':' || members.member_role || ':'
      || coalesce(members.shirt_number::text, '') || ':' || members.position_order::text
      || ':' || members.is_captain::text,
    ',' order by members.position_order, members.player_profile_id
  ), ''), 'UTF8'), 'sha256'), 'hex')
  into computed_member_checksum, computed_lineup_checksum
  from public.pachanga_competition_match_squad_members members
  where members.squad_revision_id = new_revision_id;
  update public.pachanga_competition_match_squad_revisions revisions set
    member_count = coalesce(computed_member_count, 0),
    starter_count = coalesce(computed_starter_count, 0),
    substitute_count = coalesce(computed_substitute_count, 0),
    captain_player_profile_id = captain_id,
    member_set_checksum = computed_member_checksum,
    lineup_checksum = computed_lineup_checksum
  where revisions.id = new_revision_id;
  update public.pachanga_competition_match_squads squads set
    current_revision_id = new_revision_id,
    status = target_new_status,
    revision = squads.revision + 1,
    server_sequence = target_server_sequence,
    submitted_by = case when target_new_status = 'submitted' then target_actor_id else squads.submitted_by end,
    submitted_at = case when target_new_status = 'submitted' then clock_timestamp() else squads.submitted_at end,
    validated_by = case when target_new_status = 'validated' then target_actor_id else squads.validated_by end,
    validated_at = case when target_new_status = 'validated' then clock_timestamp() else squads.validated_at end,
    rejected_by = case when target_new_status = 'rejected' then target_actor_id else squads.rejected_by end,
    rejected_at = case when target_new_status = 'rejected' then clock_timestamp() else squads.rejected_at end,
    locked_by = case when target_new_status = 'locked' then target_actor_id else squads.locked_by end,
    locked_at = case when target_new_status = 'locked' then clock_timestamp() else squads.locked_at end,
    rejection_reason_private = case when target_new_status = 'rejected'
      then left(coalesce(target_payload ->> 'reason', target_reason), 1200)
      else case when target_new_status = 'draft' then '' else squads.rejection_reason_private end end,
    updated_at = clock_timestamp()
  where squads.id = squad_row.id;
  return new_revision_id;
end;
$$;

revoke all on function private.pachanga_league_match_create_squad_revision_v1(
  uuid, text, jsonb, text, uuid, text, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_validate_squad_v1(target_squad_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare squad_row public.pachanga_competition_match_squads%rowtype;
declare revision_row public.pachanga_competition_match_squad_revisions%rowtype;
declare policy jsonb;
begin
  select * into squad_row from public.pachanga_competition_match_squads squads
  where squads.id = target_squad_id;
  if not found or squad_row.current_revision_id is null then
    raise exception 'R4C_SQUAD_NOT_FOUND' using errcode = 'P0002';
  end if;
  select * into revision_row from public.pachanga_competition_match_squad_revisions revisions
  where revisions.id = squad_row.current_revision_id;
  policy := private.pachanga_league_match_policy_v1(squad_row.rule_revision_id);
  if revision_row.member_count < (policy ->> 'squadMin')::integer
     or revision_row.member_count > (policy ->> 'squadMax')::integer
     or revision_row.starter_count < (policy ->> 'starterMin')::integer
     or revision_row.starter_count > (policy ->> 'starterMax')::integer
     or revision_row.substitute_count > (policy ->> 'substituteMax')::integer then
    raise exception 'R4C_SQUAD_POLICY_VIOLATION' using errcode = '22023';
  end if;
  if exists (
    select 1
    from public.pachanga_competition_match_squad_members members
    left join public.pachanga_competition_roster_members roster_members
      on roster_members.id = members.roster_member_id
      and roster_members.roster_revision_id = squad_row.roster_revision_id
      and roster_members.entry_id = squad_row.entry_id
      and roster_members.player_profile_id = members.player_profile_id
      and roster_members.eligibility_status in ('eligible', 'waived')
    where members.squad_revision_id = revision_row.id
      and roster_members.id is null
  ) then raise exception 'R4C_SQUAD_CONTAINS_INELIGIBLE_PLAYER' using errcode = '22023'; end if;
end;
$$;

revoke all on function private.pachanga_league_match_validate_squad_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_create_result_revision_v1(
  target_sporting_result_id uuid,
  target_proposing_entry_id uuid,
  target_score_home integer,
  target_score_away integer,
  target_scorers jsonb,
  target_revision_kind text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare current_revision public.pachanga_competition_sporting_result_revisions%rowtype;
declare scorer_item jsonb;
declare scorer_roster_member public.pachanga_competition_roster_members%rowtype;
declare squad_row public.pachanga_competition_match_squads%rowtype;
declare new_revision_id uuid := gen_random_uuid();
declare new_version integer;
declare selected_roster_member_id uuid;
declare selected_unknown_slot integer;
declare selected_goals integer;
declare selected_name text;
declare policy jsonb;
declare scorer_policy text;
declare allow_unknown boolean;
declare home_total integer;
declare away_total integer;
declare checksum text;
begin
  if target_score_home is null or target_score_away is null
     or target_score_home < 0 or target_score_away < 0 then
    raise exception 'R4C_SCORE_INVALID' using errcode = '22023';
  end if;
  if upper(target_revision_kind) not in ('INITIAL', 'CHANGE', 'ACCEPTANCE') then
    raise exception 'R4C_RESULT_REVISION_KIND_INVALID' using errcode = '22023';
  end if;
  if target_scorers is not null and jsonb_typeof(target_scorers) <> 'array' then
    raise exception 'R4C_SCORERS_MUST_BE_ARRAY' using errcode = '22023';
  end if;
  select * into result_row
  from public.pachanga_competition_sporting_results results
  where results.id = target_sporting_result_id
  for update;
  if not found then raise exception 'R4C_SPORTING_RESULT_NOT_FOUND' using errcode = 'P0002'; end if;
  context_row := private.pachanga_league_match_context_v1(result_row.competition_match_context_id);
  if target_proposing_entry_id not in (context_row.home_entry_id, context_row.away_entry_id) then
    raise exception 'R4C_ENTRY_NOT_IN_MATCH' using errcode = '42501';
  end if;
  if result_row.current_revision_id is not null then
    select * into current_revision
    from public.pachanga_competition_sporting_result_revisions revisions
    where revisions.id = result_row.current_revision_id;
  end if;
  new_version := coalesce(current_revision.version, 0) + 1;
  policy := private.pachanga_league_match_policy_v1(result_row.rule_revision_id);
  scorer_policy := policy ->> 'scorerDetailPolicy';
  allow_unknown := coalesce((policy ->> 'allowUnknownScorer')::boolean, false);

  insert into public.pachanga_competition_sporting_result_revisions(
    id, sporting_result_id, version, previous_revision_id, revision_kind,
    proposed_by_entry_id, score_home, score_away, scorer_detail_policy,
    content_checksum, operation_id, created_by, server_sequence
  ) values (
    new_revision_id, result_row.id, new_version, current_revision.id,
    upper(target_revision_kind), target_proposing_entry_id,
    target_score_home, target_score_away, scorer_policy,
    repeat('0', 64), target_operation_id, target_actor_id, target_server_sequence
  );

  if current_revision.id is not null then
    insert into public.pachanga_competition_sporting_result_scorers(
      sporting_result_revision_id, entry_id, roster_member_id, player_profile_id,
      unknown_scorer_slot, goals, display_name_snapshot, server_sequence
    )
    select new_revision_id, scorers.entry_id, scorers.roster_member_id,
      scorers.player_profile_id, scorers.unknown_scorer_slot, scorers.goals,
      scorers.display_name_snapshot, target_server_sequence
    from public.pachanga_competition_sporting_result_scorers scorers
    where scorers.sporting_result_revision_id = current_revision.id
      and (target_scorers is null or scorers.entry_id <> target_proposing_entry_id)
    order by scorers.server_sequence, scorers.id;
  end if;

  if target_scorers is not null then
    if scorer_policy = 'DISABLED' and jsonb_array_length(target_scorers) > 0 then
      raise exception 'R4C_SCORER_DETAIL_DISABLED' using errcode = '0A000';
    end if;
    select * into squad_row
    from public.pachanga_competition_match_squads squads
    where squads.canonical_match_id = result_row.canonical_match_id
      and squads.entry_id = target_proposing_entry_id
      and squads.status = 'locked';
    if not found and jsonb_array_length(target_scorers) > 0 then
      raise exception 'R4C_LOCKED_SQUAD_REQUIRED_FOR_SCORERS' using errcode = '22023';
    end if;
    for scorer_item in select value from jsonb_array_elements(target_scorers)
    loop
      if jsonb_typeof(scorer_item) <> 'object' then
        raise exception 'R4C_SCORER_INVALID' using errcode = '22023';
      end if;
      begin
        selected_roster_member_id := nullif(scorer_item ->> 'rosterMemberId', '')::uuid;
        selected_unknown_slot := nullif(scorer_item ->> 'unknownSlot', '')::integer;
        selected_goals := nullif(scorer_item ->> 'goals', '')::integer;
      exception when others then
        raise exception 'R4C_SCORER_INVALID' using errcode = '22023';
      end;
      selected_name := nullif(left(trim(coalesce(scorer_item ->> 'displayName', '')), 120), '');
      if selected_goals is null or selected_goals < 1
         or ((selected_roster_member_id is null) = (selected_unknown_slot is null)) then
        raise exception 'R4C_SCORER_INVALID' using errcode = '22023';
      end if;
      if selected_roster_member_id is not null then
        select * into scorer_roster_member
        from public.pachanga_competition_roster_members roster_members
        where roster_members.id = selected_roster_member_id
          and roster_members.entry_id = target_proposing_entry_id
          and exists (
            select 1
            from public.pachanga_competition_match_squad_members squad_members
            where squad_members.squad_revision_id = squad_row.current_revision_id
              and squad_members.roster_member_id = roster_members.id
          );
        if not found then
          raise exception 'R4C_SCORER_NOT_IN_LOCKED_SQUAD' using errcode = '42501';
        end if;
        insert into public.pachanga_competition_sporting_result_scorers(
          sporting_result_revision_id, entry_id, roster_member_id,
          player_profile_id, goals, display_name_snapshot, server_sequence
        ) values (
          new_revision_id, target_proposing_entry_id, scorer_roster_member.id,
          scorer_roster_member.player_profile_id, selected_goals,
          coalesce(selected_name, scorer_roster_member.public_snapshot ->> 'displayName'),
          target_server_sequence
        );
      else
        if not allow_unknown or selected_unknown_slot < 1 then
          raise exception 'R4C_UNKNOWN_SCORER_NOT_ALLOWED' using errcode = '0A000';
        end if;
        insert into public.pachanga_competition_sporting_result_scorers(
          sporting_result_revision_id, entry_id, unknown_scorer_slot,
          goals, display_name_snapshot, server_sequence
        ) values (
          new_revision_id, target_proposing_entry_id, selected_unknown_slot,
          selected_goals, coalesce(selected_name, 'Goleador sin identificar'),
          target_server_sequence
        );
      end if;
    end loop;
  end if;

  select
    coalesce(sum(scorers.goals) filter (where scorers.entry_id = context_row.home_entry_id), 0)::integer,
    coalesce(sum(scorers.goals) filter (where scorers.entry_id = context_row.away_entry_id), 0)::integer
  into home_total, away_total
  from public.pachanga_competition_sporting_result_scorers scorers
  where scorers.sporting_result_revision_id = new_revision_id;
  if home_total > target_score_home or away_total > target_score_away then
    raise exception 'R4C_SCORER_TOTAL_EXCEEDS_SCORE' using errcode = '22023';
  end if;
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'scoreHome', target_score_home,
    'scoreAway', target_score_away,
    'scorers', coalesce(jsonb_agg(jsonb_build_object(
      'entryId', scorers.entry_id,
      'rosterMemberId', scorers.roster_member_id,
      'playerProfileId', scorers.player_profile_id,
      'unknownSlot', scorers.unknown_scorer_slot,
      'goals', scorers.goals
    ) order by scorers.entry_id, scorers.player_profile_id nulls last,
      scorers.unknown_scorer_slot nulls last), '[]'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex') into checksum
  from public.pachanga_competition_sporting_result_scorers scorers
  where scorers.sporting_result_revision_id = new_revision_id;
  update public.pachanga_competition_sporting_result_revisions revisions set
    home_scorer_total = home_total,
    away_scorer_total = away_total,
    home_unassigned_goals = target_score_home - home_total,
    away_unassigned_goals = target_score_away - away_total,
    content_checksum = checksum
  where revisions.id = new_revision_id;
  update public.pachanga_competition_sporting_results results set
    current_revision_id = new_revision_id,
    proposed_by_entry_id = target_proposing_entry_id,
    revision = results.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where results.id = result_row.id;
  return new_revision_id;
end;
$$;

revoke all on function private.pachanga_league_match_create_result_revision_v1(
  uuid, uuid, integer, integer, jsonb, text, uuid, uuid, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_validate_confirmable_result_v1(
  target_sporting_result_revision_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare revision_row public.pachanga_competition_sporting_result_revisions%rowtype;
begin
  select * into revision_row
  from public.pachanga_competition_sporting_result_revisions revisions
  where revisions.id = target_sporting_result_revision_id;
  if not found then raise exception 'R4C_RESULT_REVISION_NOT_FOUND' using errcode = 'P0002'; end if;
  if revision_row.scorer_detail_policy = 'REQUIRED'
     and (revision_row.home_unassigned_goals <> 0 or revision_row.away_unassigned_goals <> 0) then
    raise exception 'R4C_SCORER_DETAIL_REQUIRED' using errcode = '22023';
  end if;
end;
$$;

revoke all on function private.pachanga_league_match_validate_confirmable_result_v1(uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_standings_rebuild_v1(
  target_context_id uuid,
  target_rebuild_kind text,
  target_operation_id uuid,
  target_actor_id uuid,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare policy jsonb;
declare criteria jsonb;
declare criterion text;
declare criterion_index integer := 0;
declare allow_shared boolean;
declare state_row public.pachanga_competition_standing_states%rowtype;
declare snapshot_id uuid := gen_random_uuid();
declare previous_checksum text;
declare confirmed_checksum text;
declare source_revision bigint;
declare row_total integer;
declare group_row record;
declare candidate_checksum text;
declare tie_group_key text;
declare lot_row public.pachanga_competition_persisted_draw_lots%rowtype;
declare started_at timestamptz := clock_timestamp();
declare duration_ms integer;
begin
  if upper(target_rebuild_kind) not in ('INCREMENTAL', 'FULL_AUDIT') then
    raise exception 'R4C_REBUILD_KIND_INVALID' using errcode = '22023';
  end if;
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  policy := private.pachanga_league_match_policy_v1(context_row.rule_revision_id);
  criteria := coalesce(policy -> 'tieBreakCriteria', '[]'::jsonb);
  allow_shared := coalesce((policy ->> 'allowSharedPositions')::boolean, false);
  perform pg_advisory_xact_lock(hashtextextended(
    concat_ws(':', context_row.stage_id, context_row.division_id, context_row.competition_group_id),
    91407
  ));

  select * into state_row
  from public.pachanga_competition_standing_states states
  where states.stage_id = context_row.stage_id
    and states.division_id is not distinct from context_row.division_id
    and states.competition_group_id is not distinct from context_row.competition_group_id
  for update;
  if not found then
    insert into public.pachanga_competition_standing_states(
      competition_id, edition_id, stage_id, division_id, competition_group_id,
      rule_revision_id, health_status, server_sequence
    ) values (
      context_row.competition_id, context_row.edition_id, context_row.stage_id,
      context_row.division_id, context_row.competition_group_id,
      context_row.rule_revision_id, 'PENDING', target_server_sequence
    ) returning * into state_row;
  elsif state_row.rule_revision_id <> context_row.rule_revision_id then
    raise exception 'R4C_STANDINGS_RULE_REVISION_MISMATCH' using errcode = 'PT409';
  end if;
  if state_row.current_snapshot_id is not null then
    select snapshots.content_checksum into previous_checksum
    from public.pachanga_competition_standing_snapshots snapshots
    where snapshots.id = state_row.current_snapshot_id;
  end if;

  drop table if exists pg_temp.r4c_standings_work;
  drop table if exists pg_temp.r4c_tie_explanations;
  create temporary table pg_temp.r4c_standings_work (
    entry_id uuid primary key,
    played integer not null,
    wins integer not null,
    draws integer not null,
    losses integer not null,
    goals_for integer not null,
    goals_against integer not null,
    goal_difference integer not null,
    base_points numeric(12,3) not null,
    adjustment_points numeric(12,3) not null,
    effective_points numeric(12,3) not null,
    criterion_value numeric not null default 0,
    sort_key numeric[] not null,
    tie_break_values jsonb not null default '[]'::jsonb,
    final_position integer,
    team_snapshot jsonb not null
  ) on commit drop;
  create temporary table pg_temp.r4c_tie_explanations (
    tie_group_key text not null,
    candidate_entry_ids uuid[] not null,
    criterion text not null,
    criterion_order integer not null,
    values_by_entry jsonb not null,
    resolved boolean not null,
    public_explanation text not null
  ) on commit drop;

  insert into pg_temp.r4c_standings_work(
    entry_id, played, wins, draws, losses, goals_for, goals_against,
    goal_difference, base_points, adjustment_points, effective_points,
    sort_key, team_snapshot
  )
  with official_matches as (
    select contexts.home_entry_id, contexts.away_entry_id,
      decisions.effective_score_home as score_home,
      decisions.effective_score_away as score_away
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_match_sheets sheets
      on sheets.competition_match_context_id = contexts.id
    join public.pachanga_competition_official_result_decisions decisions
      on decisions.id = sheets.active_official_decision_id
    where contexts.stage_id = context_row.stage_id
      and contexts.division_id is not distinct from context_row.division_id
      and contexts.competition_group_id is not distinct from context_row.competition_group_id
      and contexts.rule_revision_id = context_row.rule_revision_id
      and contexts.status = 'official'
      and decisions.outcome <> 'ANNULLED'
  ), entry_stats as (
    select memberships.entry_id,
      count(matches.entry_id)::integer as played,
      count(matches.entry_id) filter (where matches.goals_for > matches.goals_against)::integer as wins,
      count(matches.entry_id) filter (where matches.goals_for = matches.goals_against)::integer as draws,
      count(matches.entry_id) filter (where matches.goals_for < matches.goals_against)::integer as losses,
      coalesce(sum(matches.goals_for), 0)::integer as goals_for,
      coalesce(sum(matches.goals_against), 0)::integer as goals_against
    from public.pachanga_competition_stage_memberships memberships
    left join lateral (
      select official.home_entry_id as entry_id,
        official.score_home as goals_for, official.score_away as goals_against
      from official_matches official where official.home_entry_id = memberships.entry_id
      union all
      select official.away_entry_id,
        official.score_away, official.score_home
      from official_matches official where official.away_entry_id = memberships.entry_id
    ) matches on true
    where memberships.stage_id = context_row.stage_id
      and memberships.division_id is not distinct from context_row.division_id
      and memberships.competition_group_id is not distinct from context_row.competition_group_id
      and memberships.rule_revision_id = context_row.rule_revision_id
      and memberships.status = 'active'
    group by memberships.entry_id
  )
  select stats.entry_id, stats.played, stats.wins, stats.draws, stats.losses,
    stats.goals_for, stats.goals_against,
    stats.goals_for - stats.goals_against,
    stats.wins * (policy ->> 'pointsForWin')::numeric
      + stats.draws * (policy ->> 'pointsForDraw')::numeric
      + stats.losses * (policy ->> 'pointsForLoss')::numeric,
    0::numeric,
    stats.wins * (policy ->> 'pointsForWin')::numeric
      + stats.draws * (policy ->> 'pointsForDraw')::numeric
      + stats.losses * (policy ->> 'pointsForLoss')::numeric,
    array[-(
      stats.wins * (policy ->> 'pointsForWin')::numeric
      + stats.draws * (policy ->> 'pointsForDraw')::numeric
      + stats.losses * (policy ->> 'pointsForLoss')::numeric
    )],
    jsonb_build_object('entryId', entries.id, 'teamId', entries.team_id, 'name', groups.name)
  from entry_stats stats
  join public.pachanga_competition_entries entries on entries.id = stats.entry_id
  join public.pachanga_groups groups on groups.id = entries.team_id;

  for criterion in select value #>> '{}' from jsonb_array_elements(criteria)
  loop
    criterion_index := criterion_index + 1;
    update pg_temp.r4c_standings_work work set criterion_value = case criterion
      when 'GOAL_DIFFERENCE' then work.goal_difference
      when 'GOALS_FOR' then work.goals_for
      when 'WINS' then work.wins
      else 0
    end
    where work.entry_id is not null;

    for group_row in
      select work.sort_key,
        array_agg(work.entry_id order by work.entry_id) as candidates
      from pg_temp.r4c_standings_work work
      group by work.sort_key
      having count(*) > 1
    loop
      candidate_checksum := encode(extensions.digest(convert_to(
        array_to_string(group_row.candidates, ','), 'UTF8'
      ), 'sha256'), 'hex');
      tie_group_key := encode(extensions.digest(convert_to(concat_ws(':',
        context_row.stage_id, coalesce(context_row.division_id::text, '-'),
        coalesce(context_row.competition_group_id::text, '-'),
        array_to_string(group_row.sort_key, ','), candidate_checksum
      ), 'UTF8'), 'sha256'), 'hex');

      if criterion in (
        'HEAD_TO_HEAD_POINTS', 'HEAD_TO_HEAD_GOAL_DIFFERENCE', 'HEAD_TO_HEAD_GOALS_FOR'
      ) then
        update pg_temp.r4c_standings_work work set criterion_value = coalesce((
          with mini_matches as (
            select contexts.home_entry_id, contexts.away_entry_id,
              decisions.effective_score_home as score_home,
              decisions.effective_score_away as score_away
            from public.pachanga_competition_match_contexts contexts
            join public.pachanga_competition_match_sheets sheets
              on sheets.competition_match_context_id = contexts.id
            join public.pachanga_competition_official_result_decisions decisions
              on decisions.id = sheets.active_official_decision_id
            where contexts.stage_id = context_row.stage_id
              and contexts.division_id is not distinct from context_row.division_id
              and contexts.competition_group_id is not distinct from context_row.competition_group_id
              and contexts.rule_revision_id = context_row.rule_revision_id
              and contexts.status = 'official'
              and decisions.outcome <> 'ANNULLED'
              and contexts.home_entry_id = any(group_row.candidates)
              and contexts.away_entry_id = any(group_row.candidates)
          ), mini_stats as (
            select sum(stats.points)::numeric as points,
              sum(stats.goals_for)::numeric as goals_for,
              sum(stats.goals_against)::numeric as goals_against
            from (
              select case when matches.score_home > matches.score_away then (policy ->> 'pointsForWin')::numeric
                     when matches.score_home = matches.score_away then (policy ->> 'pointsForDraw')::numeric
                     else (policy ->> 'pointsForLoss')::numeric end as points,
                matches.score_home as goals_for, matches.score_away as goals_against
              from mini_matches matches where matches.home_entry_id = work.entry_id
              union all
              select case when matches.score_away > matches.score_home then (policy ->> 'pointsForWin')::numeric
                     when matches.score_away = matches.score_home then (policy ->> 'pointsForDraw')::numeric
                     else (policy ->> 'pointsForLoss')::numeric end,
                matches.score_away, matches.score_home
              from mini_matches matches where matches.away_entry_id = work.entry_id
            ) stats
          ) select case criterion
            when 'HEAD_TO_HEAD_POINTS' then mini_stats.points
            when 'HEAD_TO_HEAD_GOAL_DIFFERENCE' then mini_stats.goals_for - mini_stats.goals_against
            else mini_stats.goals_for
          end from mini_stats
        ), 0)
        where work.entry_id = any(group_row.candidates);
      elsif criterion = 'PERSISTED_DRAW_LOT' then
        select * into lot_row
        from public.pachanga_competition_persisted_draw_lots lots
        where lots.stage_id = context_row.stage_id
          and lots.division_id is not distinct from context_row.division_id
          and lots.competition_group_id is not distinct from context_row.competition_group_id
          and lots.rule_revision_id = context_row.rule_revision_id
          and lots.tie_group_key = tie_group_key
          and lots.candidate_checksum = candidate_checksum;
        if not found then
          raise exception 'TIE_REQUIRES_DECISION:%', tie_group_key using errcode = 'PT409';
        end if;
        update pg_temp.r4c_standings_work work
        set criterion_value = cardinality(lot_row.result_entry_ids)
          - array_position(lot_row.result_entry_ids, work.entry_id) + 1
        where work.entry_id = any(group_row.candidates);
      end if;

      insert into pg_temp.r4c_tie_explanations(
        tie_group_key, candidate_entry_ids, criterion, criterion_order,
        values_by_entry, resolved, public_explanation
      )
      select tie_group_key, group_row.candidates, criterion, criterion_index,
        jsonb_object_agg(work.entry_id::text, work.criterion_value order by work.entry_id),
        count(distinct work.criterion_value) > 1,
        case when count(distinct work.criterion_value) > 1
          then 'El empate se separa mediante ' || criterion || '.'
          else 'El empate continúa después de aplicar ' || criterion || '.' end
      from pg_temp.r4c_standings_work work
      where work.entry_id = any(group_row.candidates);
    end loop;

    update pg_temp.r4c_standings_work work set
      sort_key = work.sort_key || (-work.criterion_value),
      tie_break_values = work.tie_break_values || jsonb_build_array(jsonb_build_object(
        'criterion', criterion, 'value', work.criterion_value
      ))
    where work.entry_id is not null;
  end loop;

  if not allow_shared and exists (
    select 1 from pg_temp.r4c_standings_work work
    group by work.sort_key having count(*) > 1
  ) then raise exception 'TIE_REQUIRES_DECISION' using errcode = 'PT409'; end if;

  update pg_temp.r4c_standings_work work set final_position = ranked.position
  from (
    select standings.entry_id,
      rank() over (order by standings.sort_key)::integer as position
    from pg_temp.r4c_standings_work standings
  ) ranked
  where ranked.entry_id = work.entry_id;

  select count(*)::integer into row_total from pg_temp.r4c_standings_work;
  select coalesce(max(decisions.server_sequence), 0) into source_revision
  from public.pachanga_competition_match_contexts contexts
  join public.pachanga_competition_match_sheets sheets
    on sheets.competition_match_context_id = contexts.id
  join public.pachanga_competition_official_result_decisions decisions
    on decisions.id = sheets.active_official_decision_id
  where contexts.stage_id = context_row.stage_id
    and contexts.division_id is not distinct from context_row.division_id
    and contexts.competition_group_id is not distinct from context_row.competition_group_id
    and contexts.rule_revision_id = context_row.rule_revision_id;

  select encode(extensions.digest(convert_to(coalesce(jsonb_agg(jsonb_build_object(
    'entryId', work.entry_id,
    'position', work.final_position,
    'played', work.played,
    'wins', work.wins,
    'draws', work.draws,
    'losses', work.losses,
    'goalsFor', work.goals_for,
    'goalsAgainst', work.goals_against,
    'goalDifference', work.goal_difference,
    'basePoints', work.base_points,
    'adjustmentPoints', work.adjustment_points,
    'effectivePoints', work.effective_points,
    'tieBreakValues', work.tie_break_values
  ) order by work.final_position, work.entry_id), '[]'::jsonb)::text, 'UTF8'), 'sha256'), 'hex')
  into confirmed_checksum
  from pg_temp.r4c_standings_work work;

  insert into public.pachanga_competition_standing_snapshots(
    id, standing_state_id, competition_id, edition_id, stage_id, division_id,
    competition_group_id, rule_revision_id, supersedes_snapshot_id, rebuild_kind,
    source_revision, row_count, tie_break_criteria, content_checksum, server_sequence
  ) values (
    snapshot_id, state_row.id, context_row.competition_id, context_row.edition_id,
    context_row.stage_id, context_row.division_id, context_row.competition_group_id,
    context_row.rule_revision_id, state_row.current_snapshot_id, upper(target_rebuild_kind),
    source_revision, row_total, jsonb_build_array('POINTS') || criteria,
    confirmed_checksum, target_server_sequence
  );
  insert into public.pachanga_competition_standing_rows(
    standing_snapshot_id, entry_id, position, played, wins, draws, losses,
    goals_for, goals_against, goal_difference, base_points, adjustment_points,
    effective_points, tie_break_values, team_snapshot, server_sequence
  )
  select snapshot_id, work.entry_id, work.final_position, work.played, work.wins,
    work.draws, work.losses, work.goals_for, work.goals_against,
    work.goal_difference, work.base_points, work.adjustment_points,
    work.effective_points, work.tie_break_values, work.team_snapshot,
    target_server_sequence
  from pg_temp.r4c_standings_work work
  order by work.final_position, work.entry_id;
  insert into public.pachanga_competition_tie_break_explanations(
    standing_snapshot_id, tie_group_key, candidate_entry_ids, criterion,
    criterion_order, values_by_entry, resolved, public_explanation, server_sequence
  )
  select snapshot_id, explanations.tie_group_key, explanations.candidate_entry_ids,
    explanations.criterion, explanations.criterion_order,
    explanations.values_by_entry, explanations.resolved,
    explanations.public_explanation, target_server_sequence
  from pg_temp.r4c_tie_explanations explanations
  order by explanations.criterion_order, explanations.tie_group_key;

  update public.pachanga_competition_standing_states states set
    current_snapshot_id = snapshot_id,
    health_status = 'CURRENT',
    revision = states.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where states.id = state_row.id;
  duration_ms := greatest(0, floor(extract(epoch from (clock_timestamp() - started_at)) * 1000)::integer);
  insert into public.pachanga_competition_standing_rebuild_receipts(
    operation_id, standing_state_id, standing_snapshot_id, rebuild_kind,
    source_revision, previous_checksum, confirmed_checksum, full_audit_checksum,
    duration_ms, server_sequence
  ) values (
    target_operation_id, state_row.id, snapshot_id, upper(target_rebuild_kind),
    source_revision, previous_checksum, confirmed_checksum,
    case when upper(target_rebuild_kind) = 'FULL_AUDIT' then confirmed_checksum else null end,
    duration_ms, target_server_sequence
  );
  return jsonb_build_object(
    'standingStateId', state_row.id,
    'standingSnapshotId', snapshot_id,
    'revision', state_row.revision + 1,
    'sourceRevision', source_revision,
    'checksum', confirmed_checksum,
    'rowCount', row_total,
    'rebuildKind', upper(target_rebuild_kind),
    'durationMs', duration_ms
  );
end;
$$;

revoke all on function private.pachanga_league_standings_rebuild_v1(
  uuid, text, uuid, uuid, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_league_official_result_decide_v1(
  target_context_id uuid,
  target_outcome text,
  target_score_home integer,
  target_score_away integer,
  target_reason_code text,
  target_public_explanation text,
  target_private_evidence jsonb,
  target_supersedes_decision_id uuid,
  target_operation_id uuid,
  target_actor_id uuid,
  target_authority_role text,
  target_server_sequence bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare sheet_row public.pachanga_competition_match_sheets%rowtype;
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare result_revision public.pachanga_competition_sporting_result_revisions%rowtype;
declare decision_id uuid := gen_random_uuid();
declare normalized_outcome text := upper(trim(coalesce(target_outcome, '')));
declare effective_home integer;
declare effective_away integer;
declare standings jsonb;
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  if normalized_outcome in (
    'NO_SHOW', 'FORFEIT', 'SUSPENDED_MATCH_DECISION',
    'DISCIPLINARY_SCORE', 'POINTS_DEDUCTION'
  ) then raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000'; end if;
  if normalized_outcome not in (
    'MIRROR_SPORTING_RESULT', 'CORRECTED_EFFECTIVE_SCORE', 'ANNULLED'
  ) then raise exception 'R4C_OFFICIAL_OUTCOME_INVALID' using errcode = '22023'; end if;
  if nullif(trim(coalesce(target_reason_code, '')), '') is null then
    raise exception 'R4C_OFFICIAL_REASON_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(target_private_evidence, '{}'::jsonb)) <> 'object' then
    raise exception 'R4C_PRIVATE_EVIDENCE_INVALID' using errcode = '22023';
  end if;
  select * into sheet_row
  from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = target_context_id
  for update;
  if not found or sheet_row.current_sporting_result_id is null then
    raise exception 'R4C_SPORTING_RESULT_REQUIRED' using errcode = '22023';
  end if;
  select * into result_row
  from public.pachanga_competition_sporting_results results
  where results.id = sheet_row.current_sporting_result_id
  for update;
  select * into result_revision
  from public.pachanga_competition_sporting_result_revisions revisions
  where revisions.id = result_row.current_revision_id;
  if target_supersedes_decision_id is null then
    if sheet_row.active_official_decision_id is not null then
      raise exception 'R4C_OFFICIAL_DECISION_ALREADY_EXISTS' using errcode = 'PT409';
    end if;
  elsif sheet_row.active_official_decision_id is distinct from target_supersedes_decision_id then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;

  if normalized_outcome = 'MIRROR_SPORTING_RESULT' then
    if result_row.state <> 'confirmed' then
      raise exception 'R4C_CONFIRMED_SPORTING_RESULT_REQUIRED' using errcode = '22023';
    end if;
    effective_home := result_revision.score_home;
    effective_away := result_revision.score_away;
  elsif normalized_outcome = 'CORRECTED_EFFECTIVE_SCORE' then
    if target_supersedes_decision_id is null and result_row.state <> 'disputed' then
      raise exception 'R4C_DISPUTED_RESULT_REQUIRED' using errcode = 'PT409';
    end if;
    if target_score_home is null or target_score_away is null
       or target_score_home < 0 or target_score_away < 0 then
      raise exception 'R4C_SCORE_INVALID' using errcode = '22023';
    end if;
    effective_home := target_score_home;
    effective_away := target_score_away;
  else
    if target_supersedes_decision_id is null then
      raise exception 'R4C_OFFICIAL_DECISION_REQUIRED_FOR_ANNULMENT' using errcode = 'PT409';
    end if;
    effective_home := null;
    effective_away := null;
  end if;

  insert into public.pachanga_competition_official_result_decisions(
    id, canonical_match_id, competition_match_context_id, sporting_result_id,
    sporting_result_revision_id, supersedes_decision_id, outcome,
    effective_score_home, effective_score_away, public_explanation,
    reason_code, points_adjustments, operation_id, authority_role,
    decided_by, server_sequence
  ) values (
    decision_id, context_row.canonical_match_id, context_row.id, result_row.id,
    result_revision.id, target_supersedes_decision_id, normalized_outcome,
    effective_home, effective_away,
    left(coalesce(target_public_explanation, ''), 500),
    left(trim(target_reason_code), 120), '[]'::jsonb,
    target_operation_id, left(target_authority_role, 80), target_actor_id,
    target_server_sequence
  );
  insert into private.pachanga_competition_official_result_evidence(
    official_result_decision_id, evidence, created_by
  ) values (
    decision_id,
    target_private_evidence || jsonb_build_object(
      'privateReason', left(coalesce(target_private_evidence ->> 'privateReason', ''), 1200)
    ),
    target_actor_id
  );
  update public.pachanga_competition_match_sheets sheets set
    active_official_decision_id = decision_id,
    revision = sheets.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where sheets.id = sheet_row.id;
  update public.pachanga_competition_sporting_results results set
    state = case when normalized_outcome = 'ANNULLED' then 'annulled' else 'official' end,
    revision = results.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where results.id = result_row.id;
  update public.pachanga_competition_match_contexts contexts set
    status = 'official',
    revision = contexts.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where contexts.id = context_row.id;

  standings := private.pachanga_league_standings_rebuild_v1(
    context_row.id, 'INCREMENTAL', target_operation_id,
    target_actor_id, target_server_sequence
  );
  perform set_config('pachangas.r4c_official_decision', 'on', true);
  update public.pachanga_competition_rounds rounds set
    revision = rounds.revision + 1,
    server_sequence = target_server_sequence,
    updated_at = clock_timestamp()
  where rounds.id = context_row.round_id;
  perform set_config('pachangas.r4c_official_decision', 'off', true);
  return jsonb_build_object(
    'decisionId', decision_id,
    'outcome', normalized_outcome,
    'effectiveScoreHome', effective_home,
    'effectiveScoreAway', effective_away,
    'standings', standings
  );
end;
$$;

revoke all on function private.pachanga_league_official_result_decide_v1(
  uuid, text, integer, integer, text, text, jsonb, uuid,
  uuid, uuid, text, bigint
) from public, anon, authenticated;

create or replace function private.pachanga_league_match_can_read_v1(
  target_context_id uuid,
  target_actor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select (target_actor_id is null and private.pachanga_competition_is_service_authority_v1())
    or (target_actor_id is not null and exists (
    select 1
    from public.pachanga_competition_match_contexts contexts
    where contexts.id = target_context_id
      and (
        private.pachanga_competition_can_v1(contexts.competition_id, target_actor_id, 'read')
        or private.pachanga_league_entry_actor_scope_v1(contexts.home_entry_id, target_actor_id)
          in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER', 'VIEWER')
        or private.pachanga_league_entry_actor_scope_v1(contexts.away_entry_id, target_actor_id)
          in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER', 'VIEWER')
        or exists (
          select 1
          from public.pachanga_competition_roster_members roster_members
          join public.pachanga_player_profiles profiles
            on profiles.id = roster_members.player_profile_id
          where roster_members.entry_id in (contexts.home_entry_id, contexts.away_entry_id)
            and profiles.user_id = target_actor_id
            and roster_members.eligibility_status in ('eligible', 'waived')
            and (roster_members.effective_until is null
              or roster_members.effective_until > clock_timestamp())
        )
      )
  ));
$$;

revoke all on function private.pachanga_league_match_can_read_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_snapshot_v1(
  target_context_id uuid,
  target_actor_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare sheet_row public.pachanga_competition_match_sheets%rowtype;
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare result_revision public.pachanga_competition_sporting_result_revisions%rowtype;
declare decision_row public.pachanga_competition_official_result_decisions%rowtype;
declare home_scope text;
declare away_scope text;
declare competition_role text;
declare profile_id uuid;
declare squads_json jsonb;
declare attendance_json jsonb;
declare scorers_json jsonb;
declare responses_json jsonb;
declare home_roster_json jsonb;
declare away_roster_json jsonb;
declare next_actions jsonb := '[]'::jsonb;
begin
  context_row := private.pachanga_league_match_context_v1(target_context_id);
  if not private.pachanga_league_match_can_read_v1(target_context_id, target_actor_id) then
    raise exception 'R4C_MATCH_ACCESS_DENIED' using errcode = '42501';
  end if;
  home_scope := private.pachanga_league_entry_actor_scope_v1(context_row.home_entry_id, target_actor_id);
  away_scope := private.pachanga_league_entry_actor_scope_v1(context_row.away_entry_id, target_actor_id);
  competition_role := private.pachanga_competition_actor_role_v1(context_row.competition_id, target_actor_id);
  select profiles.id into profile_id from public.pachanga_player_profiles profiles
  where profiles.user_id = target_actor_id;
  select * into sheet_row from public.pachanga_competition_match_sheets sheets
  where sheets.competition_match_context_id = target_context_id;
  if sheet_row.current_sporting_result_id is not null then
    select * into result_row from public.pachanga_competition_sporting_results results
    where results.id = sheet_row.current_sporting_result_id;
    select * into result_revision
    from public.pachanga_competition_sporting_result_revisions revisions
    where revisions.id = result_row.current_revision_id;
  end if;
  if sheet_row.active_official_decision_id is not null then
    select * into decision_row
    from public.pachanga_competition_official_result_decisions decisions
    where decisions.id = sheet_row.active_official_decision_id;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', squads.id,
    'entryId', squads.entry_id,
    'side', squads.side,
    'status', squads.status,
    'revision', squads.revision,
    'currentRevisionId', squads.current_revision_id,
    'members', coalesce((select jsonb_agg(jsonb_build_object(
      'rosterMemberId', members.roster_member_id,
      'playerProfileId', members.player_profile_id,
      'role', members.member_role,
      'shirtNumber', members.shirt_number,
      'positionOrder', members.position_order,
      'captain', members.is_captain,
      'player', members.public_snapshot
    ) order by members.member_role, members.position_order, members.server_sequence, members.id)
      from public.pachanga_competition_match_squad_members members
      where members.squad_revision_id = squads.current_revision_id), '[]'::jsonb)
  ) order by squads.side), '[]'::jsonb) into squads_json
  from public.pachanga_competition_match_squads squads
  where squads.competition_match_context_id = target_context_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'rosterMemberId', members.id,
    'playerProfileId', members.player_profile_id,
    'eligibilityStatus', members.eligibility_status,
    'player', members.public_snapshot
  ) order by members.public_snapshot ->> 'displayName', members.server_sequence, members.id), '[]'::jsonb)
  into home_roster_json
  from public.pachanga_competition_rosters rosters
  join public.pachanga_competition_roster_members members
    on members.roster_id = rosters.id
    and members.roster_revision_id = rosters.current_revision_id
  where rosters.entry_id = context_row.home_entry_id
    and rosters.status in ('approved', 'locked')
    and rosters.rule_revision_id = context_row.rule_revision_id
    and members.eligibility_status in ('eligible', 'waived')
    and (members.effective_until is null or members.effective_until > clock_timestamp());
  select coalesce(jsonb_agg(jsonb_build_object(
    'rosterMemberId', members.id,
    'playerProfileId', members.player_profile_id,
    'eligibilityStatus', members.eligibility_status,
    'player', members.public_snapshot
  ) order by members.public_snapshot ->> 'displayName', members.server_sequence, members.id), '[]'::jsonb)
  into away_roster_json
  from public.pachanga_competition_rosters rosters
  join public.pachanga_competition_roster_members members
    on members.roster_id = rosters.id
    and members.roster_revision_id = rosters.current_revision_id
  where rosters.entry_id = context_row.away_entry_id
    and rosters.status in ('approved', 'locked')
    and rosters.rule_revision_id = context_row.rule_revision_id
    and members.eligibility_status in ('eligible', 'waived')
    and (members.effective_until is null or members.effective_until > clock_timestamp());
  select coalesce(jsonb_agg(jsonb_build_object(
    'entryId', participants.competition_entry_id,
    'rosterMemberId', participants.roster_member_id,
    'playerProfileId', participants.player_profile_id,
    'status', case participants.status when 'voy' then 'going'
      when 'no' then 'not_going' else 'pending' end,
    'revision', participants.revision,
    'updatedAt', participants.updated_at,
    'player', roster_members.public_snapshot
  ) order by participants.competition_entry_id, participants.server_sequence, participants.id), '[]'::jsonb)
  into attendance_json
  from public.pachanga_match_participants participants
  join public.pachanga_competition_roster_members roster_members
    on roster_members.id = participants.roster_member_id
  where participants.canonical_match_id = context_row.canonical_match_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'entryId', scorers.entry_id,
    'rosterMemberId', scorers.roster_member_id,
    'playerProfileId', scorers.player_profile_id,
    'unknownSlot', scorers.unknown_scorer_slot,
    'goals', scorers.goals,
    'displayName', scorers.display_name_snapshot
  ) order by scorers.entry_id, scorers.server_sequence, scorers.id), '[]'::jsonb)
  into scorers_json
  from public.pachanga_competition_sporting_result_scorers scorers
  where scorers.sporting_result_revision_id = result_revision.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'entryId', responses.entry_id,
    'kind', responses.response_kind,
    'proposedScoreHome', responses.proposed_score_home,
    'proposedScoreAway', responses.proposed_score_away,
    'createdAt', responses.created_at
  ) order by responses.server_sequence, responses.id), '[]'::jsonb)
  into responses_json
  from public.pachanga_competition_result_responses responses
  where responses.sporting_result_id = result_row.id;

  if context_row.status = 'scheduled'
     and private.pachanga_competition_can_v1(context_row.competition_id, target_actor_id, 'results_manage') then
    next_actions := next_actions || '"match.mark_ready"'::jsonb;
  end if;
  if context_row.status = 'ready'
     and private.pachanga_competition_can_v1(context_row.competition_id, target_actor_id, 'results_manage') then
    next_actions := next_actions || '"match.start"'::jsonb;
  end if;
  if context_row.status = 'in_progress'
     and private.pachanga_competition_can_v1(context_row.competition_id, target_actor_id, 'results_manage') then
    next_actions := next_actions || '"match.mark_played"'::jsonb;
  end if;
  if context_row.status = 'played' and result_row.id is null
     and (home_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER')
       or away_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER')) then
    next_actions := next_actions || '"sporting_result.submit"'::jsonb;
  end if;
  if result_row.state in ('submitted', 'change_proposed')
     and ((result_row.pending_response_from_entry_id = context_row.home_entry_id
         and home_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER'))
       or (result_row.pending_response_from_entry_id = context_row.away_entry_id
         and away_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER'))) then
    next_actions := next_actions || '["sporting_result.accept","sporting_result.propose_change","sporting_result.dispute"]'::jsonb;
  end if;
  if result_row.state in ('confirmed', 'disputed')
     and private.pachanga_competition_can_v1(context_row.competition_id, target_actor_id, 'results_manage') then
    next_actions := next_actions || '"official_result.publish"'::jsonb;
  end if;

  return jsonb_build_object(
    'kind', 'LeagueCanonicalMatchView',
    'revision', context_row.revision,
    'serverSequence', context_row.server_sequence,
    'competition', (select jsonb_build_object(
      'id', competitions.id, 'name', competitions.name, 'slug', competitions.slug,
      'type', competitions.competition_type, 'visibility', competitions.visibility,
      'status', competitions.status
    ) from public.pachanga_competitions competitions where competitions.id = context_row.competition_id),
    'edition', (select jsonb_build_object(
      'id', editions.id, 'name', editions.name, 'seasonLabel', editions.season_label,
      'status', editions.status
    ) from public.pachanga_competition_editions editions where editions.id = context_row.edition_id),
    'stage', (select jsonb_build_object(
      'id', stages.id, 'name', stages.name, 'type', stages.stage_type,
      'status', stages.status
    ) from public.pachanga_competition_stages stages where stages.id = context_row.stage_id),
    'division', (select jsonb_build_object(
      'id', divisions.id, 'name', divisions.name, 'levelLabel', divisions.level_label,
      'status', divisions.status
    ) from public.pachanga_competition_divisions divisions where divisions.id = context_row.division_id),
    'competitionGroup', (select jsonb_build_object(
      'id', groups.id, 'name', groups.name, 'status', groups.status
    ) from public.pachanga_competition_groups groups where groups.id = context_row.competition_group_id),
    'ruleRevision', (select jsonb_build_object(
      'id', revisions.id, 'version', revisions.version, 'schemaVersion', revisions.schema_version,
      'checksum', revisions.checksum, 'status', revisions.status
    ) from public.pachanga_competition_rule_revisions revisions where revisions.id = context_row.rule_revision_id),
    'context', jsonb_build_object(
      'id', context_row.id,
      'canonicalMatchId', context_row.canonical_match_id,
      'competitionId', context_row.competition_id,
      'editionId', context_row.edition_id,
      'stageId', context_row.stage_id,
      'divisionId', context_row.division_id,
      'groupId', context_row.competition_group_id,
      'roundId', context_row.round_id,
      'ruleRevisionId', context_row.rule_revision_id,
      'status', context_row.status,
      'scheduledStart', context_row.scheduled_start,
      'scheduledEnd', context_row.scheduled_end,
      'timezone', context_row.timezone,
      'venueLabel', context_row.venue_label,
      'venueStatus', context_row.venue_status,
      'disciplineValidationStatus', 'NOT_AVAILABLE'
    ),
    'round', (select jsonb_build_object(
      'id', rounds.id, 'number', rounds.round_number, 'name', rounds.display_name,
      'status', rounds.status, 'revision', rounds.revision
    ) from public.pachanga_competition_rounds rounds where rounds.id = context_row.round_id),
    'homeEntry', (select jsonb_build_object(
      'id', entries.id, 'teamId', entries.team_id, 'name', groups.name
    ) from public.pachanga_competition_entries entries
      join public.pachanga_groups groups on groups.id = entries.team_id
      where entries.id = context_row.home_entry_id),
    'awayEntry', (select jsonb_build_object(
      'id', entries.id, 'teamId', entries.team_id, 'name', groups.name
    ) from public.pachanga_competition_entries entries
      join public.pachanga_groups groups on groups.id = entries.team_id
      where entries.id = context_row.away_entry_id),
    'squads', squads_json,
    'eligibleRoster', jsonb_build_object(
      'home', home_roster_json,
      'away', away_roster_json
    ),
    'attendance', jsonb_build_object(
      'homeClosedAt', sheet_row.home_attendance_closed_at,
      'awayClosedAt', sheet_row.away_attendance_closed_at,
      'players', attendance_json
    ),
    'sportingResult', case when result_row.id is null then null else jsonb_build_object(
      'id', result_row.id, 'state', result_row.state, 'revision', result_row.revision,
      'currentRevisionId', result_revision.id,
      'proposedByEntryId', result_row.proposed_by_entry_id,
      'pendingResponseFromEntryId', result_row.pending_response_from_entry_id,
      'confirmationPolicy', result_row.confirmation_policy,
      'scoreHome', result_revision.score_home, 'scoreAway', result_revision.score_away,
      'scorerDetailPolicy', result_revision.scorer_detail_policy,
      'scorers', scorers_json, 'responses', responses_json,
      'responseDeadline', result_row.response_deadline
    ) end,
    'officialResult', case when decision_row.id is null then null else jsonb_build_object(
      'id', decision_row.id, 'outcome', decision_row.outcome,
      'scoreHome', decision_row.effective_score_home,
      'scoreAway', decision_row.effective_score_away,
      'reasonCode', decision_row.reason_code,
      'publicExplanation', decision_row.public_explanation,
      'decidedAt', decision_row.decided_at,
      'serverSequence', decision_row.server_sequence
    ) end,
    'permissions', jsonb_build_object(
      'actorCompetitionRole', competition_role,
      'actorPlayerProfileId', profile_id,
      'manageHome', home_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER'),
      'manageAway', away_scope in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER'),
      'manageResults', private.pachanga_competition_can_v1(
        context_row.competition_id, target_actor_id, 'results_manage'
      ),
      'manageStandings', private.pachanga_competition_can_v1(
        context_row.competition_id, target_actor_id, 'standings_manage'
      )
    ),
    'nextValidActions', next_actions,
    'flags', private.pachanga_league_match_operations_flags_v1()
  );
end;
$$;

revoke all on function private.pachanga_league_match_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.pachanga_league_match_store_command_v1(
  target_operation_id uuid,
  target_actor_id uuid,
  target_actor_kind text,
  target_action text,
  target_aggregate_id uuid,
  target_competition_id uuid,
  target_confirmed_revision bigint,
  target_server_sequence bigint,
  target_request_hash text,
  target_client_metadata jsonb,
  target_event_payload jsonb,
  target_snapshot jsonb,
  target_invalidations jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare competition_row public.pachanga_competitions%rowtype;
declare invalidation jsonb;
declare invalidation_sequence bigint;
declare saved_invalidations jsonb := '[]'::jsonb;
declare confirmed_at timestamptz := clock_timestamp();
declare response jsonb;
begin
  select * into competition_row from public.pachanga_competitions competitions
  where competitions.id = target_competition_id;
  if jsonb_typeof(coalesce(target_invalidations, '[]'::jsonb)) <> 'array' then
    raise exception 'R4C_INVALIDATIONS_INVALID' using errcode = '22023';
  end if;
  for invalidation in select value from jsonb_array_elements(coalesce(target_invalidations, '[]'::jsonb))
  loop
    invalidation_sequence := case when jsonb_array_length(saved_invalidations) = 0
      then target_server_sequence else nextval('private.pachanga_competition_sequence') end;
    insert into public.pachanga_competition_invalidations(
      server_sequence, competition_id, organizer_group_id, organizer_club_id,
      entity_type, entity_id, revision, created_at
    ) values (
      invalidation_sequence, target_competition_id,
      competition_row.organizer_group_id, competition_row.organizer_club_id,
      left(coalesce(invalidation ->> 'entityType', 'league_match_operations'), 120),
      left(coalesce(invalidation ->> 'entityId', target_aggregate_id::text), 240),
      coalesce(nullif(invalidation ->> 'revision', '')::bigint, target_confirmed_revision),
      confirmed_at
    );
    saved_invalidations := saved_invalidations || jsonb_build_array(jsonb_build_object(
      'entityType', left(coalesce(invalidation ->> 'entityType', 'league_match_operations'), 120),
      'entityId', left(coalesce(invalidation ->> 'entityId', target_aggregate_id::text), 240),
      'revision', coalesce(nullif(invalidation ->> 'revision', '')::bigint, target_confirmed_revision),
      'serverSequence', invalidation_sequence
    ));
  end loop;
  response := jsonb_build_object(
    'operationId', target_operation_id,
    'confirmedRevision', target_confirmed_revision,
    'confirmedAt', confirmed_at,
    'serverSequence', target_server_sequence,
    'snapshot', target_snapshot,
    'invalidations', saved_invalidations
  );
  insert into private.pachanga_competition_events(
    operation_id, actor_id, actor_kind, aggregate_type, aggregate_id,
    competition_id, action, aggregate_revision, server_sequence,
    reason_code, event_payload, confirmed_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind,
    'league_match_operations', target_aggregate_id::text,
    target_competition_id, target_action, target_confirmed_revision,
    target_server_sequence, left(target_action, 120),
    coalesce(target_event_payload, '{}'::jsonb), confirmed_at
  );
  insert into private.pachanga_competition_operation_receipts(
    operation_id, actor_id, actor_kind, action, aggregate_type, aggregate_id,
    request_hash, confirmed_revision, server_sequence, client_metadata,
    response, created_at
  ) values (
    target_operation_id, target_actor_id, target_actor_kind, target_action,
    'league_match_operations', target_aggregate_id::text, target_request_hash,
    target_confirmed_revision, target_server_sequence,
    target_client_metadata, response, confirmed_at
  );
  return response;
end;
$$;

revoke all on function private.pachanga_league_match_store_command_v1(
  uuid, uuid, text, text, uuid, uuid, bigint, bigint, text,
  jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated;

create or replace function public.command_pachanga_league_match_operations_v1(
  operation_id uuid,
  aggregate_id uuid,
  expected_revision bigint,
  action text,
  command_payload jsonb default '{}'::jsonb,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare actor_id uuid := auth.uid();
declare actor_kind text := 'authenticated';
declare action_name text := lower(trim(coalesce(action, '')));
declare payload jsonb := coalesce(command_payload, '{}'::jsonb);
declare metadata jsonb;
declare request_hash text;
declare replay jsonb;
declare sequence_value bigint;
declare context_row public.pachanga_competition_match_contexts%rowtype;
declare entry_row public.pachanga_competition_entries%rowtype;
declare roster_row public.pachanga_competition_rosters%rowtype;
declare roster_member_row public.pachanga_competition_roster_members%rowtype;
declare squad_row public.pachanga_competition_match_squads%rowtype;
declare home_squad public.pachanga_competition_match_squads%rowtype;
declare away_squad public.pachanga_competition_match_squads%rowtype;
declare sheet_row public.pachanga_competition_match_sheets%rowtype;
declare result_row public.pachanga_competition_sporting_results%rowtype;
declare result_revision public.pachanga_competition_sporting_result_revisions%rowtype;
declare decision_row public.pachanga_competition_official_result_decisions%rowtype;
declare state_row public.pachanga_competition_standing_states%rowtype;
declare round_row public.pachanga_competition_rounds%rowtype;
declare selected_entry_id uuid;
declare selected_squad_id uuid;
declare selected_roster_member_id uuid;
declare selected_profile_id uuid;
declare selected_status text;
declare selected_side text;
declare selected_score_home integer;
declare selected_score_away integer;
declare selected_outcome text;
declare selected_supersedes uuid;
declare actor_scope text;
declare authority_role text;
declare policy jsonb;
declare result_revision_id uuid;
declare official_result jsonb;
declare standings_result jsonb;
declare snapshot jsonb;
declare event_payload jsonb := '{}'::jsonb;
declare invalidations jsonb := '[]'::jsonb;
declare confirmed_revision bigint;
declare candidates uuid[];
declare draw_result uuid[];
declare candidate_checksum text;
declare draw_tie_group_key text;
declare draw_seed text;
declare latest_official_sequence bigint;
declare coordination_round_id uuid;
declare observed_round_revision bigint;
declare locked_round_revision bigint;
begin
  if operation_id is null or aggregate_id is null or expected_revision is null
     or expected_revision < 0 or action_name = '' then
    raise exception 'INVALID_LEAGUE_MATCH_OPERATIONS_COMMAND' using errcode = '22023';
  end if;
  if jsonb_typeof(payload) <> 'object'
     or jsonb_typeof(coalesce(client_metadata, '{}'::jsonb)) <> 'object'
     or pg_column_size(payload) > 40000 then
    raise exception 'INVALID_LEAGUE_MATCH_OPERATIONS_PAYLOAD' using errcode = '22023';
  end if;
  if actor_id is null then
    if not private.pachanga_competition_is_service_authority_v1() then
      raise exception 'AUTHENTICATION_REQUIRED' using errcode = '42501';
    end if;
    actor_kind := 'service_authority';
  end if;
  if action_name in (
    'match.postpone', 'match.suspend', 'match.abandon', 'match.cancel',
    'referee.assign', 'referee.report', 'temporary_player.add',
    'discipline.apply', 'points_adjustment.apply'
  ) then raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000'; end if;
  metadata := private.pachanga_league_match_sanitize_metadata_v1(client_metadata);
  request_hash := private.pachanga_league_match_request_hash_v1(
    action_name, aggregate_id, expected_revision, payload
  );
  perform pg_advisory_xact_lock(hashtextextended(operation_id::text, 91406));
  replay := private.pachanga_league_match_operation_replay_v1(
    operation_id, actor_id, action_name, aggregate_id, request_hash
  );
  if replay is not null then return replay; end if;
  if action_name like 'round.%' then
    select rounds.id, rounds.revision
      into coordination_round_id, observed_round_revision
    from public.pachanga_competition_rounds rounds
    where rounds.id = aggregate_id;
    if coordination_round_id is null then
      raise exception 'R4C_ROUND_NOT_FOUND' using errcode = 'P0002';
    end if;
  else
    select contexts.round_id, rounds.revision
      into coordination_round_id, observed_round_revision
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
    where contexts.id = aggregate_id;
    if coordination_round_id is null then
      raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002';
    end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('r4c-round:' || coordination_round_id::text, 91407));
  select rounds.revision into locked_round_revision
  from public.pachanga_competition_rounds rounds
  where rounds.id = coordination_round_id;
  if locked_round_revision is distinct from observed_round_revision then
    raise exception 'STALE_REVISION' using errcode = 'PT409';
  end if;
  sequence_value := nextval('private.pachanga_competition_sequence');

  if action_name like 'round.%' then
    select * into round_row from public.pachanga_competition_rounds rounds
    where rounds.id = aggregate_id for update;
    if not found then raise exception 'R4C_ROUND_NOT_FOUND' using errcode = 'P0002'; end if;
    if round_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    select * into context_row
    from public.pachanga_competition_match_contexts contexts
    where contexts.round_id = round_row.id
    order by contexts.server_sequence, contexts.id limit 1;
    if not found then raise exception 'R4C_ROUND_HAS_NO_MATCHES' using errcode = '22023'; end if;
  else
    select * into context_row
    from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id for update;
    if not found then raise exception 'COMPETITION_MATCH_CONTEXT_NOT_FOUND' using errcode = 'P0002'; end if;
    perform private.pachanga_league_match_context_v1(context_row.id);
    if action_name not in ('standings.rebuild', 'standings.draw_lot.confirm')
       and context_row.revision <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
  end if;

  if action_name = 'squad.create' then
    perform private.pachanga_league_match_assert_flags_v1(true, false, false, false, false, false);
    if context_row.status <> 'scheduled' then raise exception 'R4C_SQUAD_WINDOW_CLOSED' using errcode = 'PT409'; end if;
    selected_entry_id := nullif(payload ->> 'entryId', '')::uuid;
    entry_row := private.pachanga_league_match_assert_entry_v1(context_row.id, selected_entry_id);
    actor_scope := private.pachanga_league_match_assert_team_actor_v1(selected_entry_id, actor_id);
    selected_side := case when selected_entry_id = context_row.home_entry_id then 'HOME' else 'AWAY' end;
    select * into roster_row from public.pachanga_competition_rosters rosters
    where rosters.entry_id = selected_entry_id
      and rosters.status in ('approved', 'locked')
      and rosters.current_revision_id is not null
      and rosters.rule_revision_id = context_row.rule_revision_id
    for update;
    if not found then raise exception 'R4C_APPROVED_ROSTER_REQUIRED' using errcode = '22023'; end if;
    if exists (select 1 from public.pachanga_competition_match_squads squads
      where squads.canonical_match_id = context_row.canonical_match_id
        and (squads.entry_id = selected_entry_id or squads.side = selected_side)) then
      raise exception 'R4C_SQUAD_ALREADY_EXISTS' using errcode = '23505';
    end if;
    insert into public.pachanga_competition_match_squads(
      canonical_match_id, competition_match_context_id, entry_id, roster_id,
      roster_revision_id, rule_revision_id, side, status, created_by,
      server_sequence
    ) values (
      context_row.canonical_match_id, context_row.id, selected_entry_id,
      roster_row.id, roster_row.current_revision_id, context_row.rule_revision_id,
      selected_side, 'draft', actor_id, sequence_value
    ) returning * into squad_row;
    perform private.pachanga_league_match_create_squad_revision_v1(
      squad_row.id, 'CREATE', '{}'::jsonb, 'draft', actor_id,
      coalesce(payload ->> 'reason', 'squad.created'), sequence_value
    );
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp() where contexts.id = context_row.id
      returning * into context_row;
    event_payload := jsonb_build_object('squadId', squad_row.id, 'entryId', selected_entry_id, 'side', selected_side);

  elsif action_name in ('squad.member.add', 'squad.member.remove', 'squad.submit') then
    perform private.pachanga_league_match_assert_flags_v1(true, false, false, false, false, false);
    selected_squad_id := nullif(payload ->> 'squadId', '')::uuid;
    select * into squad_row from public.pachanga_competition_match_squads squads
    where squads.id = selected_squad_id and squads.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4C_SQUAD_NOT_FOUND' using errcode = 'P0002'; end if;
    actor_scope := private.pachanga_league_match_assert_team_actor_v1(squad_row.entry_id, actor_id);
    if squad_row.status not in ('draft', 'rejected') then
      raise exception 'R4C_SQUAD_NOT_EDITABLE' using errcode = 'PT409';
    end if;
    if action_name = 'squad.member.add' then
      perform private.pachanga_league_match_create_squad_revision_v1(
        squad_row.id, 'ADD', payload, 'draft', actor_id,
        coalesce(payload ->> 'reason', 'squad.member.added'), sequence_value
      );
    elsif action_name = 'squad.member.remove' then
      perform private.pachanga_league_match_create_squad_revision_v1(
        squad_row.id, 'REMOVE', payload, 'draft', actor_id,
        coalesce(payload ->> 'reason', 'squad.member.removed'), sequence_value
      );
    else
      perform private.pachanga_league_match_create_squad_revision_v1(
        squad_row.id, 'SUBMIT', '{}'::jsonb, 'submitted', actor_id,
        coalesce(payload ->> 'reason', 'squad.submitted'), sequence_value
      );
      perform private.pachanga_league_match_validate_squad_v1(squad_row.id);
    end if;
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp() where contexts.id = context_row.id
      returning * into context_row;
    event_payload := jsonb_build_object('squadId', squad_row.id, 'entryId', squad_row.entry_id);

  elsif action_name in ('squad.validate', 'squad.reject', 'squad.lock') then
    perform private.pachanga_league_match_assert_flags_v1(true, false, false, false, false, false);
    authority_role := private.pachanga_league_match_assert_result_manager_v1(context_row.competition_id, actor_id);
    selected_squad_id := nullif(payload ->> 'squadId', '')::uuid;
    select * into squad_row from public.pachanga_competition_match_squads squads
    where squads.id = selected_squad_id and squads.competition_match_context_id = context_row.id
    for update;
    if not found then raise exception 'R4C_SQUAD_NOT_FOUND' using errcode = 'P0002'; end if;
    if action_name = 'squad.validate' then
      if squad_row.status <> 'submitted' then raise exception 'R4C_SQUAD_NOT_SUBMITTED' using errcode = 'PT409'; end if;
      perform private.pachanga_league_match_validate_squad_v1(squad_row.id);
      perform private.pachanga_league_match_create_squad_revision_v1(
        squad_row.id, 'VALIDATE', '{}'::jsonb, 'validated', actor_id,
        coalesce(payload ->> 'reason', 'squad.validated'), sequence_value
      );
    elsif action_name = 'squad.reject' then
      if squad_row.status <> 'submitted' then raise exception 'R4C_SQUAD_NOT_SUBMITTED' using errcode = 'PT409'; end if;
      if nullif(trim(coalesce(payload ->> 'reason', '')), '') is null then
        raise exception 'R4C_REJECTION_REASON_REQUIRED' using errcode = '22023';
      end if;
      perform private.pachanga_league_match_create_squad_revision_v1(
        squad_row.id, 'REJECT', payload, 'rejected', actor_id,
        payload ->> 'reason', sequence_value
      );
    else
      if squad_row.status <> 'validated' then raise exception 'R4C_SQUAD_NOT_VALIDATED' using errcode = 'PT409'; end if;
      perform private.pachanga_league_match_validate_squad_v1(squad_row.id);
      perform private.pachanga_league_match_create_squad_revision_v1(
        squad_row.id, 'LOCK', '{}'::jsonb, 'locked', actor_id,
        coalesce(payload ->> 'reason', 'squad.locked'), sequence_value
      );
    end if;
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp() where contexts.id = context_row.id
      returning * into context_row;
    event_payload := jsonb_build_object('squadId', squad_row.id, 'entryId', squad_row.entry_id);

  elsif action_name = 'attendance.set' then
    perform private.pachanga_league_match_assert_flags_v1(false, true, false, false, false, false);
    if context_row.status <> 'scheduled' then raise exception 'R4C_ATTENDANCE_CLOSED' using errcode = 'PT409'; end if;
    selected_entry_id := nullif(payload ->> 'entryId', '')::uuid;
    entry_row := private.pachanga_league_match_assert_entry_v1(context_row.id, selected_entry_id);
    actor_scope := private.pachanga_league_entry_actor_scope_v1(selected_entry_id, actor_id);
    selected_roster_member_id := nullif(payload ->> 'rosterMemberId', '')::uuid;
    select * into roster_member_row
    from public.pachanga_competition_roster_members roster_members
    join public.pachanga_competition_rosters rosters
      on rosters.id = roster_members.roster_id
      and rosters.current_revision_id = roster_members.roster_revision_id
    where roster_members.id = selected_roster_member_id
      and roster_members.entry_id = selected_entry_id
      and roster_members.eligibility_status in ('eligible', 'waived')
      and (roster_members.effective_until is null or roster_members.effective_until > clock_timestamp());
    if not found then raise exception 'R4C_ROSTER_MEMBER_NOT_ELIGIBLE' using errcode = '22023'; end if;
    if actor_scope not in ('TEAM_OWNER', 'PRIMARY_DELEGATE', 'ROSTER_MANAGER') and not exists (
      select 1 from public.pachanga_player_profiles profiles
      where profiles.id = roster_member_row.player_profile_id and profiles.user_id = actor_id
    ) then raise exception 'R4C_ATTENDANCE_ACTOR_DENIED' using errcode = '42501'; end if;
    select * into sheet_row from public.pachanga_competition_match_sheets sheets
    where sheets.competition_match_context_id = context_row.id;
    selected_side := case when selected_entry_id = context_row.home_entry_id then 'HOME' else 'AWAY' end;
    if (selected_side = 'HOME' and sheet_row.home_attendance_closed_at is not null)
       or (selected_side = 'AWAY' and sheet_row.away_attendance_closed_at is not null) then
      raise exception 'R4C_ATTENDANCE_CLOSED' using errcode = 'PT409';
    end if;
    selected_status := lower(coalesce(payload ->> 'status', ''));
    if selected_status not in ('going', 'not_going', 'pending') then
      raise exception 'R4C_ATTENDANCE_STATUS_INVALID' using errcode = '22023';
    end if;
    perform 1 from public.pachanga_match_participants participants
    where participants.canonical_match_id = context_row.canonical_match_id
      and participants.player_profile_id = roster_member_row.player_profile_id
    for update;
    if found then
      update public.pachanga_match_participants participants set
        competition_match_context_id = context_row.id,
        competition_entry_id = selected_entry_id,
        roster_member_id = roster_member_row.id,
        status = case selected_status when 'going' then 'voy' when 'not_going' then 'no' else 'duda' end,
        joined_at = case when selected_status = 'going' then coalesce(participants.joined_at, clock_timestamp()) else participants.joined_at end,
        revision = participants.revision + 1,
        server_sequence = sequence_value,
        changed_by = actor_id,
        updated_at = clock_timestamp()
      where participants.canonical_match_id = context_row.canonical_match_id
        and participants.player_profile_id = roster_member_row.player_profile_id;
    else
      insert into public.pachanga_match_participants(
        canonical_match_id, competition_match_context_id, competition_entry_id,
        roster_member_id, player_profile_id, status, seat_kind, joined_at,
        revision, server_sequence, changed_by, updated_at
      ) values (
        context_row.canonical_match_id, context_row.id, selected_entry_id,
        roster_member_row.id, roster_member_row.player_profile_id,
        case selected_status when 'going' then 'voy' when 'not_going' then 'no' else 'duda' end,
        'none', case when selected_status = 'going' then clock_timestamp() else null end,
        1, sequence_value, actor_id, clock_timestamp()
      );
    end if;
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp() where contexts.id = context_row.id
      returning * into context_row;
    event_payload := jsonb_build_object('entryId', selected_entry_id, 'status', selected_status);

  elsif action_name = 'attendance.close' then
    perform private.pachanga_league_match_assert_flags_v1(false, true, false, false, false, false);
    if context_row.status <> 'scheduled' then raise exception 'R4C_ATTENDANCE_CLOSED' using errcode = 'PT409'; end if;
    selected_entry_id := nullif(payload ->> 'entryId', '')::uuid;
    perform private.pachanga_league_match_assert_entry_v1(context_row.id, selected_entry_id);
    actor_scope := private.pachanga_league_match_assert_team_actor_v1(selected_entry_id, actor_id);
    select * into home_squad from public.pachanga_competition_match_squads squads
    where squads.competition_match_context_id = context_row.id and squads.side = 'HOME';
    select * into away_squad from public.pachanga_competition_match_squads squads
    where squads.competition_match_context_id = context_row.id and squads.side = 'AWAY';
    insert into public.pachanga_competition_match_sheets(
      canonical_match_id, competition_match_context_id, home_squad_id,
      away_squad_id, created_by, server_sequence
    ) values (
      context_row.canonical_match_id, context_row.id, home_squad.id,
      away_squad.id, actor_id, sequence_value
    ) on conflict (competition_match_context_id) do nothing;
    update public.pachanga_competition_match_sheets sheets set
      home_attendance_closed_by = case when selected_entry_id = context_row.home_entry_id then actor_id else sheets.home_attendance_closed_by end,
      home_attendance_closed_at = case when selected_entry_id = context_row.home_entry_id then clock_timestamp() else sheets.home_attendance_closed_at end,
      away_attendance_closed_by = case when selected_entry_id = context_row.away_entry_id then actor_id else sheets.away_attendance_closed_by end,
      away_attendance_closed_at = case when selected_entry_id = context_row.away_entry_id then clock_timestamp() else sheets.away_attendance_closed_at end,
      revision = sheets.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where sheets.competition_match_context_id = context_row.id;
    update public.pachanga_competition_match_contexts contexts set
      revision = contexts.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp() where contexts.id = context_row.id
      returning * into context_row;
    event_payload := jsonb_build_object('entryId', selected_entry_id, 'closed', true);

  elsif action_name in ('match.mark_ready', 'match.start', 'match.mark_played') then
    perform private.pachanga_league_match_assert_flags_v1(true, false, false, false, false, false);
    authority_role := private.pachanga_league_match_assert_result_manager_v1(context_row.competition_id, actor_id);
    if action_name = 'match.mark_ready' then
      if context_row.status <> 'scheduled' then raise exception 'R4C_MATCH_NOT_SCHEDULED' using errcode = 'PT409'; end if;
      if context_row.scheduled_start is null or context_row.scheduled_end is null then
        raise exception 'R4C_MATCH_SCHEDULE_REQUIRED' using errcode = '22023';
      end if;
      select * into home_squad from public.pachanga_competition_match_squads squads
      where squads.competition_match_context_id = context_row.id and squads.side = 'HOME' for update;
      select * into away_squad from public.pachanga_competition_match_squads squads
      where squads.competition_match_context_id = context_row.id and squads.side = 'AWAY' for update;
      if home_squad.status <> 'locked' or away_squad.status <> 'locked' then
        raise exception 'R4C_BOTH_SQUADS_MUST_BE_LOCKED' using errcode = '22023';
      end if;
      perform private.pachanga_league_match_validate_squad_v1(home_squad.id);
      perform private.pachanga_league_match_validate_squad_v1(away_squad.id);
      insert into public.pachanga_competition_match_sheets(
        canonical_match_id, competition_match_context_id, home_squad_id,
        away_squad_id, created_by, server_sequence
      ) values (
        context_row.canonical_match_id, context_row.id, home_squad.id,
        away_squad.id, actor_id, sequence_value
      ) on conflict (competition_match_context_id) do update set
        home_squad_id = excluded.home_squad_id, away_squad_id = excluded.away_squad_id,
        revision = public.pachanga_competition_match_sheets.revision + 1,
        server_sequence = excluded.server_sequence, updated_at = clock_timestamp();
      if (select settings.league_match_attendance_enabled
          from private.pachanga_competition_foundation_settings settings where settings.singleton)
         and exists (
           select 1 from public.pachanga_competition_match_sheets sheets
           where sheets.competition_match_context_id = context_row.id
             and (sheets.home_attendance_closed_at is null or sheets.away_attendance_closed_at is null)
         ) then raise exception 'R4C_ATTENDANCE_MUST_BE_CLOSED' using errcode = '22023'; end if;
      selected_status := 'ready';
    elsif action_name = 'match.start' then
      if context_row.status <> 'ready' then raise exception 'R4C_MATCH_NOT_READY' using errcode = 'PT409'; end if;
      selected_status := 'in_progress';
      update public.pachanga_competition_rounds rounds set
        status = 'in_progress',
        revision = rounds.revision + 1,
        server_sequence = sequence_value,
        updated_at = clock_timestamp()
      where rounds.id = context_row.round_id
        and rounds.status = 'published';
    else
      if context_row.status <> 'in_progress' then raise exception 'R4C_MATCH_NOT_IN_PROGRESS' using errcode = 'PT409'; end if;
      selected_status := 'played';
    end if;
    update public.pachanga_competition_match_contexts contexts set
      status = selected_status, revision = contexts.revision + 1,
      server_sequence = sequence_value, updated_at = clock_timestamp()
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object('status', selected_status);

  elsif action_name = 'sporting_result.submit' then
    perform private.pachanga_league_match_assert_flags_v1(false, false, true, false, false, false);
    if context_row.status <> 'played' then raise exception 'R4C_RESULT_REQUIRES_PLAYED_MATCH' using errcode = 'PT409'; end if;
    if payload ? 'shootoutHome' or payload ? 'shootoutAway' then
      raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    selected_entry_id := nullif(payload ->> 'entryId', '')::uuid;
    perform private.pachanga_league_match_assert_entry_v1(context_row.id, selected_entry_id);
    actor_scope := private.pachanga_league_match_assert_team_actor_v1(selected_entry_id, actor_id);
    begin
      selected_score_home := nullif(payload ->> 'scoreHome', '')::integer;
      selected_score_away := nullif(payload ->> 'scoreAway', '')::integer;
    exception when others then raise exception 'R4C_SCORE_INVALID' using errcode = '22023'; end;
    if exists (select 1 from public.pachanga_competition_sporting_results results
      where results.canonical_match_id = context_row.canonical_match_id) then
      raise exception 'R4C_SPORTING_RESULT_ALREADY_EXISTS' using errcode = '23505';
    end if;
    policy := private.pachanga_league_match_policy_v1(context_row.rule_revision_id);
    insert into public.pachanga_competition_sporting_results(
      canonical_match_id, competition_match_context_id, rule_revision_id,
      state, proposed_by_entry_id, pending_response_from_entry_id,
      response_deadline, confirmation_policy, created_by, server_sequence
    ) values (
      context_row.canonical_match_id, context_row.id, context_row.rule_revision_id,
      'submitted', selected_entry_id,
      case when selected_entry_id = context_row.home_entry_id then context_row.away_entry_id else context_row.home_entry_id end,
      clock_timestamp() + make_interval(hours => (policy ->> 'responseDeadlineHours')::integer),
      policy ->> 'confirmationPolicy', actor_id, sequence_value
    ) returning * into result_row;
    result_revision_id := private.pachanga_league_match_create_result_revision_v1(
      result_row.id, selected_entry_id, selected_score_home, selected_score_away,
      case when payload ? 'scorers' then payload -> 'scorers' else null end,
      'INITIAL', operation_id, actor_id, sequence_value
    );
    update public.pachanga_competition_match_sheets sheets set
      current_sporting_result_id = result_row.id,
      revision = sheets.revision + 1, server_sequence = sequence_value,
      updated_at = clock_timestamp()
    where sheets.competition_match_context_id = context_row.id;
    if not found then raise exception 'R4C_MATCH_SHEET_REQUIRED' using errcode = '22023'; end if;
    update public.pachanga_competition_match_contexts contexts set
      status = 'result_pending', revision = contexts.revision + 1,
      server_sequence = sequence_value, updated_at = clock_timestamp()
    where contexts.id = context_row.id returning * into context_row;
    event_payload := jsonb_build_object('sportingResultId', result_row.id, 'revisionId', result_revision_id);

  elsif action_name in (
    'sporting_result.accept', 'sporting_result.propose_change', 'sporting_result.dispute'
  ) then
    perform private.pachanga_league_match_assert_flags_v1(false, false, true, true, false, false);
    if context_row.status <> 'result_pending' then raise exception 'R4C_RESULT_NOT_PENDING' using errcode = 'PT409'; end if;
    selected_entry_id := nullif(payload ->> 'entryId', '')::uuid;
    perform private.pachanga_league_match_assert_entry_v1(context_row.id, selected_entry_id);
    actor_scope := private.pachanga_league_match_assert_team_actor_v1(selected_entry_id, actor_id);
    select * into result_row from public.pachanga_competition_sporting_results results
    where results.competition_match_context_id = context_row.id for update;
    if not found or result_row.state not in ('submitted', 'change_proposed') then
      raise exception 'R4C_RESULT_NOT_RESPONDABLE' using errcode = 'PT409';
    end if;
    if result_row.pending_response_from_entry_id <> selected_entry_id then
      raise exception 'R4C_RESULT_RESPONSE_NOT_YOURS' using errcode = '42501';
    end if;
    select * into result_revision from public.pachanga_competition_sporting_result_revisions revisions
    where revisions.id = result_row.current_revision_id;
    if action_name = 'sporting_result.accept' then
      result_revision_id := private.pachanga_league_match_create_result_revision_v1(
        result_row.id, selected_entry_id, result_revision.score_home,
        result_revision.score_away,
        case when payload ? 'scorers' then payload -> 'scorers' else null end,
        'ACCEPTANCE', operation_id, actor_id, sequence_value
      );
      perform private.pachanga_league_match_validate_confirmable_result_v1(result_revision_id);
      insert into public.pachanga_competition_result_responses(
        sporting_result_id, sporting_result_revision_id, entry_id, response_kind,
        operation_id, created_by, server_sequence
      ) values (
        result_row.id, result_revision_id, selected_entry_id, 'ACCEPT',
        operation_id, actor_id, sequence_value
      );
      update public.pachanga_competition_sporting_results results set
        state = 'confirmed', pending_response_from_entry_id = null,
        confirmed_at = clock_timestamp(), revision = results.revision + 1,
        server_sequence = sequence_value, updated_at = clock_timestamp()
      where results.id = result_row.id;
      policy := private.pachanga_league_match_policy_v1(context_row.rule_revision_id);
      if coalesce((policy ->> 'autoOfficialAfterConfirmation')::boolean, false) then
        perform private.pachanga_league_match_assert_flags_v1(false, false, true, true, true, true);
        official_result := private.pachanga_league_official_result_decide_v1(
          context_row.id, 'MIRROR_SPORTING_RESULT', null, null,
          'result.auto_official', 'Resultado confirmado por ambos equipos.',
          '{}'::jsonb, null, operation_id, actor_id, 'automatic_rule', sequence_value
        );
      else
        update public.pachanga_competition_match_contexts contexts set
          revision = contexts.revision + 1, server_sequence = sequence_value,
          updated_at = clock_timestamp() where contexts.id = context_row.id;
      end if;
    elsif action_name = 'sporting_result.propose_change' then
      begin
        selected_score_home := nullif(payload ->> 'scoreHome', '')::integer;
        selected_score_away := nullif(payload ->> 'scoreAway', '')::integer;
      exception when others then raise exception 'R4C_SCORE_INVALID' using errcode = '22023'; end;
      result_revision_id := private.pachanga_league_match_create_result_revision_v1(
        result_row.id, selected_entry_id, selected_score_home, selected_score_away,
        case when payload ? 'scorers' then payload -> 'scorers' else null end,
        'CHANGE', operation_id, actor_id, sequence_value
      );
      insert into public.pachanga_competition_result_responses(
        sporting_result_id, sporting_result_revision_id, entry_id, response_kind,
        proposed_score_home, proposed_score_away, reason_private,
        operation_id, created_by, server_sequence
      ) values (
        result_row.id, result_revision_id, selected_entry_id, 'PROPOSE_CHANGE',
        selected_score_home, selected_score_away,
        left(coalesce(payload ->> 'reason', ''), 1200),
        operation_id, actor_id, sequence_value
      );
      update public.pachanga_competition_sporting_results results set
        state = 'change_proposed',
        pending_response_from_entry_id = case when selected_entry_id = context_row.home_entry_id then context_row.away_entry_id else context_row.home_entry_id end,
        response_deadline = clock_timestamp() + make_interval(hours => (
          private.pachanga_league_match_policy_v1(context_row.rule_revision_id) ->> 'responseDeadlineHours'
        )::integer), revision = results.revision + 1,
        server_sequence = sequence_value, updated_at = clock_timestamp()
      where results.id = result_row.id;
      update public.pachanga_competition_match_contexts contexts set
        revision = contexts.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp() where contexts.id = context_row.id;
    else
      insert into public.pachanga_competition_result_responses(
        sporting_result_id, sporting_result_revision_id, entry_id, response_kind,
        proposed_score_home, proposed_score_away, reason_private,
        operation_id, created_by, server_sequence
      ) values (
        result_row.id, result_revision.id, selected_entry_id, 'DISPUTE',
        nullif(payload ->> 'scoreHome', '')::integer,
        nullif(payload ->> 'scoreAway', '')::integer,
        left(coalesce(payload ->> 'reason', ''), 1200),
        operation_id, actor_id, sequence_value
      );
      update public.pachanga_competition_sporting_results results set
        state = 'disputed', pending_response_from_entry_id = null,
        disputed_at = clock_timestamp(), revision = results.revision + 1,
        server_sequence = sequence_value, updated_at = clock_timestamp()
      where results.id = result_row.id;
      update public.pachanga_competition_match_contexts contexts set
        revision = contexts.revision + 1, server_sequence = sequence_value,
        updated_at = clock_timestamp() where contexts.id = context_row.id;
    end if;
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    if official_result is not null then
      select * into round_row from public.pachanga_competition_rounds rounds
      where rounds.id = context_row.round_id;
    end if;
    event_payload := jsonb_build_object('sportingResultId', result_row.id, 'response', action_name);

  elsif action_name in ('official_result.publish', 'official_result.supersede', 'official_result.annul') then
    perform private.pachanga_league_match_assert_flags_v1(false, false, true, true, true, true);
    authority_role := private.pachanga_league_match_assert_result_manager_v1(context_row.competition_id, actor_id);
    if payload ? 'pointsAdjustments'
       and (jsonb_typeof(payload -> 'pointsAdjustments') <> 'array'
         or jsonb_array_length(payload -> 'pointsAdjustments') <> 0) then
      raise exception 'FEATURE_NOT_AVAILABLE' using errcode = '0A000';
    end if;
    select * into sheet_row from public.pachanga_competition_match_sheets sheets
    where sheets.competition_match_context_id = context_row.id for update;
    if action_name = 'official_result.publish' then
      selected_supersedes := null;
      selected_outcome := upper(coalesce(payload ->> 'outcome', 'MIRROR_SPORTING_RESULT'));
    elsif action_name = 'official_result.supersede' then
      if sheet_row.active_official_decision_id is null then raise exception 'R4C_OFFICIAL_DECISION_NOT_FOUND' using errcode = 'P0002'; end if;
      selected_supersedes := sheet_row.active_official_decision_id;
      selected_outcome := upper(coalesce(payload ->> 'outcome', 'CORRECTED_EFFECTIVE_SCORE'));
    else
      if sheet_row.active_official_decision_id is null then raise exception 'R4C_OFFICIAL_DECISION_NOT_FOUND' using errcode = 'P0002'; end if;
      selected_supersedes := sheet_row.active_official_decision_id;
      selected_outcome := 'ANNULLED';
    end if;
    begin
      selected_score_home := nullif(payload ->> 'scoreHome', '')::integer;
      selected_score_away := nullif(payload ->> 'scoreAway', '')::integer;
    exception when others then raise exception 'R4C_SCORE_INVALID' using errcode = '22023'; end;
    official_result := private.pachanga_league_official_result_decide_v1(
      context_row.id, selected_outcome, selected_score_home, selected_score_away,
      coalesce(payload ->> 'reasonCode', action_name),
      coalesce(payload ->> 'publicExplanation', ''),
      coalesce(payload -> 'privateEvidence', '{}'::jsonb),
      selected_supersedes, operation_id, actor_id, authority_role, sequence_value
    );
    select * into context_row from public.pachanga_competition_match_contexts contexts
    where contexts.id = aggregate_id;
    select * into round_row from public.pachanga_competition_rounds rounds
    where rounds.id = context_row.round_id;
    event_payload := jsonb_build_object(
      'decisionId', official_result ->> 'decisionId',
      'outcome', official_result ->> 'outcome'
    );

  elsif action_name = 'standings.rebuild' then
    perform private.pachanga_league_match_assert_flags_v1(false, false, false, false, true, true);
    authority_role := private.pachanga_league_match_assert_standings_manager_v1(context_row.competition_id, actor_id);
    select * into state_row from public.pachanga_competition_standing_states states
    where states.stage_id = context_row.stage_id
      and states.division_id is not distinct from context_row.division_id
      and states.competition_group_id is not distinct from context_row.competition_group_id
    for update;
    if coalesce(state_row.revision, 0) <> expected_revision then
      raise exception 'STALE_REVISION' using errcode = 'PT409';
    end if;
    standings_result := private.pachanga_league_standings_rebuild_v1(
      context_row.id, upper(coalesce(payload ->> 'rebuildKind', 'FULL_AUDIT')),
      operation_id, actor_id, sequence_value
    );
    confirmed_revision := (standings_result ->> 'revision')::bigint;
    event_payload := standings_result;

  elsif action_name = 'standings.draw_lot.confirm' then
    perform private.pachanga_league_match_assert_flags_v1(false, false, false, false, true, true);
    authority_role := private.pachanga_league_match_assert_standings_manager_v1(context_row.competition_id, actor_id);
    select * into state_row from public.pachanga_competition_standing_states states
    where states.stage_id = context_row.stage_id
      and states.division_id is not distinct from context_row.division_id
      and states.competition_group_id is not distinct from context_row.competition_group_id
    for update;
    if coalesce(state_row.revision, 0) <> expected_revision then raise exception 'STALE_REVISION' using errcode = 'PT409'; end if;
    if jsonb_typeof(payload -> 'candidateEntryIds') <> 'array' then
      raise exception 'R4C_DRAW_LOT_CANDIDATES_REQUIRED' using errcode = '22023';
    end if;
    begin
      select array_agg(value::uuid order by value::uuid) into candidates
      from jsonb_array_elements_text(payload -> 'candidateEntryIds');
    exception when others then raise exception 'R4C_DRAW_LOT_CANDIDATES_INVALID' using errcode = '22023'; end;
    if cardinality(candidates) < 2 or cardinality(candidates) <> (
      select count(distinct candidate)::integer from unnest(candidates) candidate
    ) then raise exception 'R4C_DRAW_LOT_CANDIDATES_INVALID' using errcode = '22023'; end if;
    if exists (
      select candidate from unnest(candidates) candidate
      where not exists (
        select 1 from public.pachanga_competition_stage_memberships memberships
        where memberships.entry_id = candidate
          and memberships.stage_id = context_row.stage_id
          and memberships.status = 'active'
      )
    ) then raise exception 'R4C_DRAW_LOT_ENTRY_NOT_ACTIVE' using errcode = '22023'; end if;
    draw_tie_group_key := nullif(trim(coalesce(payload ->> 'tieGroupKey', '')), '');
    draw_seed := nullif(left(trim(coalesce(payload ->> 'seed', '')), 160), '');
    if draw_tie_group_key is null or length(draw_tie_group_key) <> 64 or draw_seed is null then
      raise exception 'R4C_DRAW_LOT_INPUT_INVALID' using errcode = '22023';
    end if;
    candidate_checksum := encode(extensions.digest(convert_to(array_to_string(candidates, ','), 'UTF8'), 'sha256'), 'hex');
    select array_agg(candidate order by encode(extensions.digest(convert_to(
      draw_seed || ':' || candidate::text, 'UTF8'
    ), 'sha256'), 'hex'), candidate) into draw_result from unnest(candidates) candidate;
    insert into public.pachanga_competition_persisted_draw_lots(
      competition_id, stage_id, division_id, competition_group_id,
      rule_revision_id, tie_group_key, candidate_entry_ids, candidate_checksum,
      seed, result_entry_ids, operation_id, confirmed_by, server_sequence
    ) values (
      context_row.competition_id, context_row.stage_id, context_row.division_id,
      context_row.competition_group_id, context_row.rule_revision_id,
      draw_tie_group_key, candidates, candidate_checksum, draw_seed,
      draw_result, operation_id, actor_id, sequence_value
    );
    standings_result := private.pachanga_league_standings_rebuild_v1(
      context_row.id, 'FULL_AUDIT', operation_id, actor_id, sequence_value
    );
    confirmed_revision := (standings_result ->> 'revision')::bigint;
    event_payload := jsonb_build_object('drawLot', draw_result, 'standings', standings_result);

  elsif action_name in ('round.complete', 'round.lock') then
    perform private.pachanga_league_match_assert_flags_v1(false, false, false, false, true, true);
    authority_role := private.pachanga_league_match_assert_standings_manager_v1(round_row.competition_id, actor_id);
    if action_name = 'round.complete' then
      if round_row.status <> 'in_progress' then raise exception 'R4C_ROUND_NOT_IN_PROGRESS' using errcode = 'PT409'; end if;
      if exists (
        select 1 from public.pachanga_competition_match_contexts contexts
        left join public.pachanga_competition_match_sheets sheets
          on sheets.competition_match_context_id = contexts.id
        where contexts.round_id = round_row.id
          and (contexts.status <> 'official' or sheets.active_official_decision_id is null)
      ) then raise exception 'R4C_ROUND_HAS_UNOFFICIAL_MATCHES' using errcode = '22023'; end if;
      if exists (
        select 1 from public.pachanga_competition_match_contexts contexts
        join public.pachanga_competition_sporting_results results
          on results.competition_match_context_id = contexts.id
        where contexts.round_id = round_row.id and results.state = 'disputed'
      ) then raise exception 'R4C_ROUND_HAS_DISPUTES' using errcode = '22023'; end if;
      selected_status := 'completed';
    else
      if round_row.status <> 'completed' then raise exception 'R4C_ROUND_NOT_COMPLETED' using errcode = 'PT409'; end if;
      selected_status := 'locked';
    end if;
    select coalesce(max(decisions.server_sequence), 0) into latest_official_sequence
    from public.pachanga_competition_match_contexts contexts
    join public.pachanga_competition_match_sheets sheets
      on sheets.competition_match_context_id = contexts.id
    join public.pachanga_competition_official_result_decisions decisions
      on decisions.id = sheets.active_official_decision_id
    where contexts.round_id = round_row.id;
    select * into state_row from public.pachanga_competition_standing_states states
    where states.stage_id = round_row.stage_id
      and states.division_id is not distinct from round_row.division_id
      and states.competition_group_id is not distinct from round_row.competition_group_id;
    if state_row.current_snapshot_id is null or not exists (
      select 1 from public.pachanga_competition_standing_snapshots snapshots
      where snapshots.id = state_row.current_snapshot_id
        and snapshots.source_revision >= latest_official_sequence
    ) then raise exception 'R4C_STANDINGS_NOT_CURRENT' using errcode = 'PT409'; end if;
    update public.pachanga_competition_rounds rounds set
      status = selected_status, revision = rounds.revision + 1,
      server_sequence = sequence_value, updated_at = clock_timestamp()
    where rounds.id = round_row.id returning * into round_row;
    confirmed_revision := round_row.revision;
    event_payload := jsonb_build_object('roundId', round_row.id, 'status', round_row.status);

  else
    raise exception 'R4C_ACTION_NOT_SUPPORTED' using errcode = '0A000';
  end if;

  if action_name like 'round.%' then
    snapshot := jsonb_build_object(
      'kind', 'LeagueRoundState', 'id', round_row.id, 'status', round_row.status,
      'revision', round_row.revision, 'serverSequence', round_row.server_sequence
    );
    confirmed_revision := coalesce(confirmed_revision, round_row.revision);
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'round', 'entityId', round_row.id, 'revision', confirmed_revision),
      jsonb_build_object('entityType', 'standings', 'entityId', context_row.stage_id, 'revision', coalesce(state_row.revision, 0))
    );
  else
    snapshot := private.pachanga_league_match_snapshot_v1(context_row.id, actor_id);
    confirmed_revision := coalesce(confirmed_revision, context_row.revision);
    invalidations := jsonb_build_array(
      jsonb_build_object('entityType', 'match', 'entityId', context_row.id, 'revision', context_row.revision)
    );
    if action_name like 'squad.%' then
      invalidations := invalidations || jsonb_build_array(jsonb_build_object(
        'entityType', 'squad', 'entityId', coalesce(selected_squad_id, squad_row.id),
        'revision', context_row.revision
      ));
    elsif action_name like 'sporting_result.%' or action_name like 'official_result.%' then
      invalidations := invalidations || jsonb_build_array(jsonb_build_object(
        'entityType', 'result', 'entityId', context_row.canonical_match_id,
        'revision', context_row.revision
      ));
    end if;
    if action_name like 'official_result.%'
       or action_name like 'standings.%'
       or official_result is not null then
      invalidations := invalidations || jsonb_build_array(jsonb_build_object(
        'entityType', 'standings', 'entityId', context_row.stage_id,
        'revision', confirmed_revision
      ));
    end if;
    if action_name like 'official_result.%' or official_result is not null then
      invalidations := invalidations || jsonb_build_array(jsonb_build_object(
        'entityType', 'round', 'entityId', round_row.id,
        'revision', round_row.revision
      ));
    end if;
  end if;
  return private.pachanga_league_match_store_command_v1(
    operation_id, actor_id, actor_kind, action_name, aggregate_id,
    context_row.competition_id, confirmed_revision, sequence_value,
    request_hash, metadata, event_payload, snapshot, invalidations
  );
end;
$$;

revoke all on function public.command_pachanga_league_match_operations_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) from public, anon;
grant execute on function public.command_pachanga_league_match_operations_v1(
  uuid, uuid, bigint, text, jsonb, jsonb
) to authenticated, service_role;
