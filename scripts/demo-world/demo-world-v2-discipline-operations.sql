\set ON_ERROR_STOP on

-- R5 is exercised against the same six-team League used by Demo World V2.
-- All identities and evidence remain inside the temporary simulation database.

insert into public.pachanga_competition_entitlement_grants(
  organizer_kind, organizer_group_id, capability, grant_source, status,
  reason, granted_by
)
select
  'TEAM', md5('r4b-team-0')::uuid, capability, 'platform_grant', 'active',
  'Demo World V2.1 discipline authority proof',
  'e4010000-0000-4000-8000-000000000001'::uuid
from unnest(array[
  'competition_discipline_manage',
  'competition_discipline_review',
  'competition_appeals_manage'
]::text[]) capability
on conflict do nothing;

update private.pachanga_competition_foundation_settings set
  competition_discipline_foundation_enabled = true,
  competition_disciplinary_events_enabled = true,
  competition_disciplinary_counters_enabled = true,
  competition_sanctions_enabled = true,
  competition_sanction_service_enabled = true,
  competition_discipline_appeals_enabled = true,
  competition_public_discipline_enabled = false
where singleton;

insert into public.pachanga_competition_discipline_rule_catalogs(
  rule_revision_id, competition_id, policy_version, card_type_catalog,
  cycle_policy, sanction_policy, appeal_policy, public_reason_categories,
  checksum, created_by
)
select
  'e4060000-0000-4000-8000-000000000001',
  'e4040000-0000-4000-8000-000000000001',
  policy ->> 'policyVersion', policy -> 'cardTypeCatalog',
  policy -> 'cyclePolicy', policy -> 'sanctionPolicy',
  policy -> 'appealPolicy', policy -> 'publicReasonCategories',
  encode(extensions.digest(convert_to(policy::text, 'UTF8'), 'sha256'), 'hex'),
  'e4010000-0000-4000-8000-000000000002'
from (select private.pachanga_competition_discipline_default_policy_v1() policy) source
on conflict (rule_revision_id) do nothing;

insert into auth.users(id, email, email_confirmed_at, raw_user_meta_data)
select
  md5('demo-world-v2-alt-user-' || value)::uuid,
  'demo-world-v2-alt-' || value || '@example.test',
  clock_timestamp(),
  jsonb_build_object('full_name', 'Demo League alternate ' || value)
from generate_series(1, 6) value;

insert into public.pachanga_group_members(group_id, user_id, role, display_name)
select
  md5('r4b-team-' || value)::uuid,
  md5('demo-world-v2-alt-user-' || value)::uuid,
  'player',
  'Demo League alternate ' || value
from generate_series(1, 6) value;

insert into public.pachanga_player_profiles(
  id, user_id, source_group_id, display_name, phone, position
)
select
  md5('demo-world-v2-profile-alt-' || value)::uuid,
  md5('demo-world-v2-alt-user-' || value)::uuid,
  md5('r4b-team-' || value)::uuid,
  'Demo League alternate ' || value,
  '',
  'Defensa'
from generate_series(1, 6) value;

insert into public.pachanga_competition_roster_members(
  id, roster_id, roster_revision_id, entry_id, player_profile_id,
  source_group_id, source_user_id, eligibility_status, public_snapshot, reason_code
)
select
  md5('demo-world-v2-roster-member-alt-' || value)::uuid,
  md5('r4b-roster-' || value)::uuid,
  md5('r4b-roster-revision-' || value)::uuid,
  md5('r4b-entry-' || value)::uuid,
  md5('demo-world-v2-profile-alt-' || value)::uuid,
  md5('r4b-team-' || value)::uuid,
  md5('demo-world-v2-alt-user-' || value)::uuid,
  'eligible',
  jsonb_build_object('displayName', 'Demo League alternate ' || value, 'position', 'DEF'),
  'eligibility.demo_world_v2_1'
from generate_series(1, 6) value;

do $$
declare value integer;
begin
  for value in 1..6 loop
    perform private.pachanga_league_finalize_roster_revision_v1(
      md5('r4b-roster-revision-' || value)::uuid
    );
  end loop;
end;
$$;

create or replace function pg_temp.demo_v2_discipline_command(
  target_actor_id uuid,
  target_operation_key text,
  target_aggregate_id uuid,
  target_action text,
  target_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql as $$
declare current_revision bigint;
begin
  select discipline_revision into current_revision
  from public.pachanga_competitions
  where id = 'e4040000-0000-4000-8000-000000000001';
  perform pg_temp.demo_v2_actor(target_actor_id);
  return public.command_pachanga_competition_discipline_v1(
    md5('demo-world-v2-r5:' || target_operation_key)::uuid,
    'e4040000-0000-4000-8000-000000000001',
    target_aggregate_id,
    current_revision,
    target_action,
    target_payload,
    '{"clientVersion":"demo-world-v2.1","serviceWorkerVersion":"demo-world-v2.1","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
  );
end;
$$;

create or replace function pg_temp.demo_v2_entry_number(target_entry_id uuid)
returns integer language sql stable as $$
  select substring(groups.name from '([0-9]+)$')::integer
  from public.pachanga_competition_entries entries
  join public.pachanga_groups groups on groups.id = entries.team_id
  where entries.id = target_entry_id
$$;

create or replace function pg_temp.demo_v2_profile_id(
  target_entry_id uuid,
  alternate boolean default false
)
returns uuid language sql stable as $$
  select case when alternate
    then md5('demo-world-v2-profile-alt-' || pg_temp.demo_v2_entry_number(target_entry_id))::uuid
    else md5('demo-world-v2-profile-' || pg_temp.demo_v2_entry_number(target_entry_id))::uuid
  end
$$;

create or replace function pg_temp.demo_v2_roster_member_for_match(
  target_entry_id uuid,
  target_canonical_match_id uuid
)
returns uuid language plpgsql stable as $$
declare primary_profile_id uuid := pg_temp.demo_v2_profile_id(target_entry_id, false);
declare use_alternate boolean;
declare entry_number integer := pg_temp.demo_v2_entry_number(target_entry_id);
declare round_number integer;
begin
  select rounds.round_number into round_number
  from public.pachanga_competition_match_contexts contexts
  join public.pachanga_competition_rounds rounds on rounds.id = contexts.round_id
  where contexts.canonical_match_id = target_canonical_match_id;
  use_alternate := private.pachanga_competition_player_sanction_applies_v1(
    'e4040000-0000-4000-8000-000000000001',
    primary_profile_id,
    target_canonical_match_id
  ) or (entry_number <> 2 and round_number % 2 = 0);
  return case when use_alternate
    then md5('demo-world-v2-roster-member-alt-' || pg_temp.demo_v2_entry_number(target_entry_id))::uuid
    else md5('demo-world-v2-roster-member-' || pg_temp.demo_v2_entry_number(target_entry_id))::uuid
  end;
end;
$$;

create or replace function pg_temp.demo_v2_match_player(
  target_context_id uuid,
  target_entry_id uuid
)
returns uuid language sql stable as $$
  select members.player_profile_id
  from public.pachanga_competition_match_squads squads
  join public.pachanga_competition_match_squad_members members
    on members.squad_revision_id = squads.current_revision_id
  where squads.competition_match_context_id = target_context_id
    and squads.entry_id = target_entry_id
  order by members.position_order, members.server_sequence, members.id
  limit 1
$$;

create or replace function pg_temp.demo_v2_record_card(
  target_context_id uuid,
  target_operation_key text,
  target_player_profile_id uuid,
  target_card_type text,
  target_minute integer,
  target_summary text
)
returns jsonb language plpgsql as $$
declare selected_canonical_match_id uuid;
declare assignment public.pachanga_referee_assignments%rowtype;
declare referee_user_id uuid;
declare payload jsonb;
begin
  select contexts.canonical_match_id into selected_canonical_match_id
  from public.pachanga_competition_match_contexts contexts
  where contexts.id = target_context_id;
  payload := jsonb_build_object(
    'playerProfileId', target_player_profile_id,
    'cardTypeCode', target_card_type,
    'context', 'in_match',
    'minute', target_minute,
    'publicReasonCategory', case when target_card_type = 'YELLOW' then 'accumulation' else 'dismissal' end,
    'publicSummary', target_summary
  );
  select assignments.* into assignment
  from public.pachanga_referee_assignments assignments
  where assignments.canonical_match_id = selected_canonical_match_id
    and assignments.status = 'confirmed'
    and assignments.schedule_state = 'CURRENT'
  order by assignments.server_sequence desc, assignments.id desc
  limit 1;
  if found then
    select profiles.user_id into referee_user_id
    from public.pachanga_referee_profiles profiles
    where profiles.id = assignment.referee_profile_id;
    perform pg_temp.demo_v2_actor(referee_user_id);
    return public.command_pachanga_referee_officiating_v1(
      md5('demo-world-v2-r5:' || target_operation_key)::uuid,
      assignment.id,
      assignment.revision,
      'discipline.record',
      payload,
      '{"clientVersion":"demo-world-v2.2","serviceWorkerVersion":"demo-world-v2.2","installedMode":"simulation","surface":"demo_world_v2"}'::jsonb
    );
  end if;
  return pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    target_operation_key,
    selected_canonical_match_id,
    'event.record',
    payload
  );
end;
$$;

create or replace function pg_temp.demo_v2_discipline_after_match(
  target_context_id uuid,
  target_canonical_match_id uuid,
  target_round_number integer,
  target_ordinal integer,
  target_home_entry_id uuid,
  target_away_entry_id uuid
)
returns void language plpgsql as $$
declare generic_profile_id uuid;
declare target_entry_id uuid := md5('r4b-entry-2')::uuid;
declare target_player_id uuid := md5('demo-world-v2-profile-2')::uuid;
declare red_player_id uuid;
declare red_event_id uuid;
declare red_sanction_id uuid;
declare threshold_sanction_id uuid;
begin
  generic_profile_id := pg_temp.demo_v2_match_player(
    target_context_id,
    case when target_entry_id = target_home_entry_id
      then target_away_entry_id else target_home_entry_id end
  );
  perform pg_temp.demo_v2_record_card(
    target_context_id,
    'yellow-generic-' || target_ordinal,
    generic_profile_id,
    'YELLOW',
    8 + target_ordinal * 2,
    'Amarilla de Liga · J' || target_round_number
  );

  if target_round_number <= 3 and target_entry_id in (target_home_entry_id, target_away_entry_id) then
    perform pg_temp.demo_v2_record_card(
      target_context_id,
      'yellow-threshold-team-2-round-' || target_round_number,
      target_player_id,
      'YELLOW',
      54 + target_round_number,
      case when target_round_number = 3 then 'Umbral de acumulación alcanzado' else 'Amarilla acumulada' end
    );
  end if;

  if target_ordinal = 6 then
    perform pg_temp.demo_v2_record_card(
      target_context_id,
      'blue-temporary-dismissal',
      pg_temp.demo_v2_match_player(target_context_id, target_away_entry_id),
      'BLUE', 33,
      'Exclusión temporal reglamentaria'
    );
  end if;

  if target_ordinal in (8, 14) then
    red_player_id := pg_temp.demo_v2_match_player(target_context_id, target_away_entry_id);
    perform pg_temp.demo_v2_record_card(
      target_context_id,
      'red-direct-' || target_ordinal,
      red_player_id,
      'RED',
      case when target_ordinal = 8 then 67 else 73 end,
      'Expulsión directa pendiente de comité'
    );
    select events.id into red_event_id
    from public.pachanga_competition_disciplinary_events events
    where events.creation_operation_id = md5('demo-world-v2-r5:red-direct-' || target_ordinal)::uuid;
    select sanctions.id into red_sanction_id
    from public.pachanga_competition_sanctions sanctions
    where sanctions.source_event_id = red_event_id;
    perform pg_temp.demo_v2_discipline_command(
      'e4010000-0000-4000-8000-000000000002',
      'red-decision-' || target_ordinal,
      red_sanction_id,
      'sanction.decide',
      jsonb_build_object(
        'decisionOutcome', 'FIXED_SANCTION',
        'units', case when target_ordinal = 8 then 2 else 1 end,
        'publicReasonCategory', 'dismissal',
        'publicSummary', case when target_ordinal = 8 then 'Dos partidos de sanción' else 'Un partido de sanción' end,
        'ruleArticle', 'R5.DEMO.RED',
        'privateReason', 'Decisión motivada en la simulación determinista.',
        'evidenceRefs', jsonb_build_array('demo://discipline/red-' || target_ordinal)
      )
    );
  end if;

  if target_round_number = 4 and target_entry_id in (target_home_entry_id, target_away_entry_id) then
    select sanctions.id into threshold_sanction_id
    from public.pachanga_competition_sanctions sanctions
    where sanctions.player_profile_id = target_player_id
      and sanctions.status = 'active'
    order by sanctions.server_sequence desc, sanctions.id desc
    limit 1;
    if threshold_sanction_id is not null then
      perform pg_temp.demo_v2_discipline_command(
        'e4010000-0000-4000-8000-000000000002',
        'threshold-service-round-4',
        threshold_sanction_id,
        'service.record',
        '{}'::jsonb
      );
    end if;
  end if;
end;
$$;

create or replace function pg_temp.demo_v2_discipline_finalize()
returns void language plpgsql as $$
declare corrected_event_id uuid;
declare sanction_player_3 uuid;
declare sanction_player_4 uuid;
declare appeal_player_3 uuid;
declare appeal_player_4 uuid;
begin
  select events.id into corrected_event_id
  from public.pachanga_competition_disciplinary_events events
  where events.creation_operation_id = md5('demo-world-v2-r5:yellow-generic-15')::uuid;
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'correct-yellow-15-to-blue',
    corrected_event_id,
    'event.correct',
    jsonb_build_object(
      'playerProfileId', md5('demo-world-v2-profile-6')::uuid,
      'cardTypeCode', 'BLUE',
      'context', 'in_match',
      'minute', 38,
      'publicReasonCategory', 'dismissal',
      'publicSummary', 'Corregida a exclusión temporal',
      'correctionReason', 'El acta oficial confirmó tarjeta azul.'
    )
  );

  select sanctions.id into sanction_player_4
  from public.pachanga_competition_sanctions sanctions
  where sanctions.player_profile_id = md5('demo-world-v2-profile-4')::uuid
  order by sanctions.server_sequence desc, sanctions.id desc limit 1;
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'red-player-4-service', sanction_player_4, 'service.record', '{}'::jsonb
  );
  perform pg_temp.demo_v2_discipline_command(
    md5('r4b-owner-4')::uuid,
    'appeal-player-4-submit', sanction_player_4, 'appeal.submit',
    '{"statement":"Solicito revisar la extensión de la sanción."}'::jsonb
  );
  select appeals.id into appeal_player_4
  from public.pachanga_competition_sanction_appeals appeals
  where appeals.creation_operation_id = md5('demo-world-v2-r5:appeal-player-4-submit')::uuid;
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'appeal-player-4-admissible', appeal_player_4, 'appeal.transition',
    '{"status":"admissible","publicResolution":"Apelación admitida","privateReason":"Cumple los requisitos formales."}'::jsonb
  );
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'appeal-player-4-review', appeal_player_4, 'appeal.transition',
    '{"status":"under_review","publicResolution":"En revisión","privateReason":"La mesa revisa el acta."}'::jsonb
  );
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'appeal-player-4-modified', appeal_player_4, 'appeal.transition',
    '{"status":"modified","modifiedUnits":1,"publicResolution":"Sanción reducida a un partido","privateReason":"La revisión reduce la extensión."}'::jsonb
  );

  select sanctions.id into sanction_player_3
  from public.pachanga_competition_sanctions sanctions
  where sanctions.player_profile_id = md5('demo-world-v2-profile-3')::uuid
  order by sanctions.server_sequence desc, sanctions.id desc limit 1;
  perform pg_temp.demo_v2_discipline_command(
    md5('r4b-owner-3')::uuid,
    'appeal-player-3-submit', sanction_player_3, 'appeal.submit',
    '{"statement":"Solicito confirmar la resolución con el acta completa."}'::jsonb
  );
  select appeals.id into appeal_player_3
  from public.pachanga_competition_sanction_appeals appeals
  where appeals.creation_operation_id = md5('demo-world-v2-r5:appeal-player-3-submit')::uuid;
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'appeal-player-3-admissible', appeal_player_3, 'appeal.transition',
    '{"status":"admissible","publicResolution":"Apelación admitida","privateReason":"Admisión formal."}'::jsonb
  );
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'appeal-player-3-review', appeal_player_3, 'appeal.transition',
    '{"status":"under_review","publicResolution":"En revisión","privateReason":"Revisión del acta."}'::jsonb
  );
  perform pg_temp.demo_v2_discipline_command(
    'e4010000-0000-4000-8000-000000000002',
    'appeal-player-3-upheld', appeal_player_3, 'appeal.transition',
    '{"status":"upheld","publicResolution":"Sanción confirmada","privateReason":"El acta confirma la resolución."}'::jsonb
  );
end;
$$;
