\set ON_ERROR_STOP on

create or replace function pg_temp.r5_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception 'R5_ASSERT:%', message; end if;
end;
$$;

create or replace function pg_temp.r5_actor(actor_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'authenticated', 'sub', actor_id)::text,
    false
  );
end;
$$;

create or replace function pg_temp.r5_command(
  actor_id uuid, operation_id uuid, aggregate_id uuid,
  expected_revision bigint, command_action text, command_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql as $$
declare effective_revision bigint;
begin
  perform pg_temp.r5_actor(actor_id);
  select receipts.confirmed_revision - 1 into effective_revision
  from private.pachanga_competition_operation_receipts receipts
  where receipts.operation_id = r5_command.operation_id
    and receipts.aggregate_type = 'competition_discipline';
  if effective_revision is null then
    select competitions.discipline_revision into effective_revision
    from public.pachanga_competitions competitions
    where competitions.id = 'c4200000-0000-4000-8000-000000000001';
  end if;
  return public.command_pachanga_competition_discipline_v1(
    operation_id,
    'c4200000-0000-4000-8000-000000000001',
    aggregate_id, effective_revision, command_action, command_payload,
    '{"clientVersion":"5.0.0+r5-db","serviceWorkerVersion":"sw-r5-db","installedMode":"standalone","surface":"r5_db"}'
  );
end;
$$;

create or replace function pg_temp.r5_expect_command_error(
  actor_id uuid, operation_id uuid, aggregate_id uuid,
  expected_revision bigint, command_action text, command_payload jsonb,
  expected_error text
) returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    perform pg_temp.r5_command(
      actor_id, operation_id, aggregate_id, expected_revision,
      command_action, command_payload
    );
  exception when others then
    caught := true;
    if sqlerrm !~ expected_error then
      raise exception 'R5_WRONG_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then raise exception 'R5_EXPECTED_ERROR_NOT_RAISED:%', expected_error; end if;
end;
$$;

create or replace function pg_temp.r5_expect_sql_error(statement text, expected_error text)
returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    execute statement;
  exception when others then
    caught := true;
    if sqlerrm !~ expected_error then
      raise exception 'R5_WRONG_SQL_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then raise exception 'R5_EXPECTED_SQL_ERROR_NOT_RAISED:%', expected_error; end if;
end;
$$;

create or replace function pg_temp.r5_table_digest(target regclass)
returns text language plpgsql as $$
declare digest_value text;
begin
  execute format(
    'select md5(coalesce(string_agg(to_jsonb(source)::text, ''|'' order by to_jsonb(source)::text), '''')) from %s source',
    target
  ) into digest_value;
  return digest_value;
end;
$$;

create temporary table r5_state(key text primary key, value jsonb not null);
create temporary table r5_invariants(key text primary key, digest text not null);

insert into r5_invariants values
  ('rating', pg_temp.r5_table_digest('public.pachanga_player_rating_snapshots')),
  ('rewards', pg_temp.r5_table_digest('public.pachanga_reward_grants')),
  ('player_cosmetics', pg_temp.r5_table_digest('public.pachanga_player_cosmetic_loadouts')),
  ('team_cosmetics', pg_temp.r5_table_digest('public.pachanga_team_cosmetic_inventory')),
  ('conduct', pg_temp.r5_table_digest('private.pachanga_conduct_reports')),
  ('billing', pg_temp.r5_table_digest('public.pachanga_stripe_webhook_events')),
  ('ranking', pg_temp.r5_table_digest('public.pachanga_provincial_ranking_entries'));

select pg_temp.r5_assert(
  (select count(*) = 3
   from jsonb_array_elements((select card_type_catalog
     from public.pachanga_competition_discipline_rule_catalogs)) cards),
  'catalog must expose YELLOW, RED and BLUE'
);
select pg_temp.r5_assert(
  (select array_agg(cards ->> 'code' order by cards ->> 'code') = array['BLUE','RED','YELLOW']
   from jsonb_array_elements((select card_type_catalog
     from public.pachanga_competition_discipline_rule_catalogs)) cards),
  'card semantics must come from RuleRevision catalog'
);

insert into r5_state values (
  'yellow_1', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006', 1, 'event.record',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":12,"period":"FIRST_HALF","publicReasonCategory":"accumulation","publicSummary":"Amarilla J1","privateNotes":"Evidence remains private","evidenceRefs":["qa://yellow-j1"]}'
  )
);
insert into r5_state values (
  'yellow_2', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000002',
    'c4500000-0000-4000-8000-000000000006', 1, 'event.record',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":27,"publicReasonCategory":"accumulation","publicSummary":"Amarilla J2"}'
  )
);
insert into r5_state values (
  'yellow_3', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000003',
    'c4600000-0000-4000-8000-000000000006', 1, 'event.record',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":51,"publicReasonCategory":"accumulation","publicSummary":"Threshold J3"}'
  )
);

select pg_temp.r5_assert(
  (select active_event_count = 3 and accumulation_points = 3 and threshold_hits = 1
   from public.pachanga_competition_disciplinary_counters
   where player_profile_id = 'c4300000-0000-4000-8000-000000000001'
     and card_type_code = 'YELLOW'),
  'three yellows must materialize one threshold hit'
);
select pg_temp.r5_assert(
  (select count(*) = 1 and bool_and(
      status = 'active' and sanction_outcome = 'FIXED_SANCTION'
      and unit_type = 'MATCHES' and total_units = 1 and remaining_units = 1
    ) from public.pachanga_competition_sanctions
    where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
  'threshold must produce exactly one active one-match sanction'
);

insert into r5_state values (
  'notification_count_before_replay',
  jsonb_build_object('count', (
    select count(*) from public.pachanga_user_notifications notifications
    where notifications.payload ->> 'operationId' = 'c5000000-0000-4000-8000-000000000003'
  ))
);

select pg_temp.r5_assert(
  pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000003',
    'c4600000-0000-4000-8000-000000000006', 1, 'event.record',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":51,"publicReasonCategory":"accumulation","publicSummary":"Threshold J3"}'
  ) = (select value from r5_state where key = 'yellow_3'),
  'idempotent replay must return the same receipt'
);
select pg_temp.r5_assert(
  (select count(*) = 3 from public.pachanga_competition_disciplinary_events),
  'idempotent replay must not duplicate events'
);
select pg_temp.r5_assert(
  (select (value ->> 'count')::integer from r5_state
    where key = 'notification_count_before_replay') = (
      select count(*) from public.pachanga_user_notifications notifications
      where notifications.payload ->> 'operationId' = 'c5000000-0000-4000-8000-000000000003'
    ),
  'idempotent replay must not duplicate notifications'
);
select pg_temp.r5_expect_command_error(
  'c4010000-0000-4000-8000-000000000002',
  'c5000000-0000-4000-8000-000000000003',
  'c4600000-0000-4000-8000-000000000006', 1, 'event.record',
  '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":52}',
  'OPERATION_ID|IDEMPOTENCY'
);

select pg_temp.r5_expect_command_error(
  'c4010000-0000-4000-8000-000000000007',
  'c5000000-0000-4000-8000-000000000010',
  'c4700000-0000-4000-8000-000000000006', 1, 'event.record',
  '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":20}',
  'MANAGER_REQUIRED'
);
select pg_temp.r5_expect_command_error(
  'c4010000-0000-4000-8000-000000000002',
  'c5000000-0000-4000-8000-000000000011',
  'c4700000-0000-4000-8000-000000000006', 1, 'event.record',
  '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"GREEN","context":"in_match","minute":20}',
  'CARD_TYPE_NOT_ALLOWED|CARD_RULE_INVALID'
);
select pg_temp.r5_expect_command_error(
  'c4010000-0000-4000-8000-000000000002',
  'c5000000-0000-4000-8000-000000000012',
  'c4700000-0000-4000-8000-000000000006', 1, 'event.record',
  '{"playerProfileId":"c4300000-0000-4000-8000-000000000003","cardTypeCode":"BLUE","context":"in_match","minute":301}',
  'PAYLOAD_INVALID'
);
select pg_temp.r5_expect_command_error(
  'c4010000-0000-4000-8000-000000000002',
  'c5000000-0000-4000-8000-000000000013',
  'c4700000-0000-4000-8000-000000000006', 1, 'event.record',
  '{"playerProfileId":"c4300000-0000-4000-8000-000000000003","cardTypeCode":"BLUE","context":"in_match","minute":15,"counter":99}',
  'SERVER_FIELDS_FORBIDDEN'
);
select pg_temp.r5_expect_command_error(
  'c4010000-0000-4000-8000-000000000002',
  'c5000000-0000-4000-8000-000000000014',
  'c4990000-0000-4000-8000-000000000099', 1, 'event.record',
  '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":15}',
  'MATCH_CONTEXT_NOT_FOUND'
);

set role authenticated;
select pg_temp.r5_expect_sql_error(
  $$insert into public.pachanga_competition_disciplinary_events(
    competition_id, canonical_match_id, competition_match_context_id,
    cycle_id, rule_revision_id, player_profile_id, entry_id,
    current_card_type_code, creation_operation_id, created_by
  ) values (
    'c4200000-0000-4000-8000-000000000001',
    'c4400000-0000-4000-8000-000000000006',
    'c4400000-0000-4000-8000-000000000008',
    (select id from public.pachanga_competition_disciplinary_cycles limit 1),
    'c4200000-0000-4000-8000-000000000003',
    'c4300000-0000-4000-8000-000000000001',
    'c4200000-0000-4000-8000-000000000011',
    'YELLOW', gen_random_uuid(), 'c4010000-0000-4000-8000-000000000002'
  )$$,
  'permission denied'
);
select pg_temp.r5_expect_sql_error(
  $$update public.pachanga_competition_disciplinary_events
    set status = 'annulled'
    where id = (select id from public.pachanga_competition_disciplinary_events limit 1)$$,
  'permission denied'
);
select pg_temp.r5_expect_sql_error(
  $$delete from public.pachanga_competition_disciplinary_events
    where id = (select id from public.pachanga_competition_disciplinary_events limit 1)$$,
  'permission denied'
);
select pg_temp.r5_expect_sql_error(
  $$select * from private.pachanga_competition_discipline_evidence limit 1$$,
  'permission denied'
);
reset role;

select pg_temp.r5_actor('c4010000-0000-4000-8000-000000000002');
insert into r5_state values (
  'snapshot', public.get_pachanga_competition_discipline_v1(
    'c4200000-0000-4000-8000-000000000001', null, null
  )
);
select pg_temp.r5_assert(
  jsonb_array_length((select value -> 'events' from r5_state where key = 'snapshot')) = 3
  and jsonb_array_length((select value -> 'sanctions' from r5_state where key = 'snapshot')) = 1
  and jsonb_array_length((select value -> 'ruleCatalog' -> 'cardTypes' from r5_state where key = 'snapshot')) = 3,
  'canonical snapshot must expose calculated read models'
);
select pg_temp.r5_assert(
  (select value::text !~* 'privateNotes|evidenceRefs|actorId|createdBy|reporterId'
   from r5_state where key = 'snapshot'),
  'canonical read model must not expose evidence or private identities'
);
select pg_temp.r5_expect_sql_error(
  $$select public.get_pachanga_public_competition_discipline_v1(
    'c4200000-0000-4000-8000-000000000001', null
  )$$,
  'PUBLIC_COMPETITION_DISCIPLINE_DISABLED'
);

update private.pachanga_competition_foundation_settings
set competition_public_discipline_enabled = true where singleton;
update public.pachanga_competitions
set visibility = 'public'
where id = 'c4200000-0000-4000-8000-000000000001';
grant insert on r5_state to anon;
set role anon;
insert into r5_state values (
  'public_snapshot', public.get_pachanga_public_competition_discipline_v1(
    'c4200000-0000-4000-8000-000000000001', null
  )
);
reset role;
revoke insert on r5_state from anon;
select pg_temp.r5_assert(
  (select value::text !~* 'proposal|appeals|appellant|private|evidence|canAppeal|ruleArticle'
   from r5_state where key = 'public_snapshot')
  and jsonb_array_length((select value -> 'events' from r5_state
    where key = 'public_snapshot')) = 3,
  'public projection must execute for anon and expose only its allowlist'
);
update private.pachanga_competition_foundation_settings
set competition_public_discipline_enabled = false where singleton;
update public.pachanga_competitions
set visibility = 'private'
where id = 'c4200000-0000-4000-8000-000000000001';

-- The sanctioned player cannot be locked into the next fixture.
select pg_temp.r5_assert(
  private.pachanga_competition_player_sanction_applies_v1(
    'c4200000-0000-4000-8000-000000000001',
    'c4300000-0000-4000-8000-000000000001',
    'c4700000-0000-4000-8000-000000000006'
  ),
  'active sanction must apply to the next published fixture'
);
select pg_temp.r5_expect_sql_error(
  $$update public.pachanga_competition_match_squads
    set status = 'locked'
    where id = 'c4800000-0000-4000-8000-000000000014'$$,
  'DISCIPLINARY_INELIGIBLE_PLAYER'
);

-- Appeal lifecycle remains player-owned and server-deadlined.
insert into r5_state values (
  'appeal_submit', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000005',
    'c5000000-0000-4000-8000-000000000020',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
    1, 'appeal.submit', '{"statement":"Solicito revisión del acta."}'
  )
);
insert into r5_state values (
  'appeal_admissible', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000021',
    (select id from public.pachanga_competition_sanction_appeals limit 1),
    1, 'appeal.transition',
    '{"status":"admissible","publicResolution":"Admitida","privateReason":"Documentación suficiente."}'
  )
);
insert into r5_state values (
  'appeal_review', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000022',
    (select id from public.pachanga_competition_sanction_appeals limit 1),
    2, 'appeal.transition',
    '{"status":"under_review","publicResolution":"En revisión","privateReason":"Mesa disciplinaria revisando."}'
  )
);
insert into r5_state values (
  'appeal_upheld', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000023',
    (select id from public.pachanga_competition_sanction_appeals limit 1),
    3, 'appeal.transition',
    '{"status":"upheld","publicResolution":"Sanción confirmada","privateReason":"El acta queda confirmada."}'
  )
);
select pg_temp.r5_assert(
  (select status = 'upheld' and revision = 4
   from public.pachanga_competition_sanction_appeals limit 1),
  'appeal must preserve append-only transitions'
);

-- Replace the J4 candidate with an eligible alternate, lock it and play it.
insert into public.pachanga_competition_match_squad_revisions(
  id, squad_id, version, squad_status, roster_revision_id, rule_revision_id,
  member_count, starter_count, substitute_count, captain_player_profile_id,
  member_set_checksum, lineup_checksum, reason, created_by
) values (
  'c4900000-0000-4000-8000-000000000024',
  'c4800000-0000-4000-8000-000000000014', 2, 'submitted',
  'c4200000-0000-4000-8000-000000000017',
  'c4200000-0000-4000-8000-000000000003', 1, 1, 0,
  'c4300000-0000-4000-8000-000000000003', repeat('5', 64), repeat('e', 64),
  'R5 J4 eligible replacement', 'c4010000-0000-4000-8000-000000000003'
);
insert into public.pachanga_competition_match_squad_members(
  id, squad_revision_id, roster_member_id, player_profile_id, member_role,
  shirt_number, position_order, is_captain, public_snapshot
) values (
  'c4a00000-0000-4000-8000-000000000024',
  'c4900000-0000-4000-8000-000000000024',
  'c4200000-0000-4000-8000-000000000021',
  'c4300000-0000-4000-8000-000000000003',
  'STARTER', 4, 1, true, '{"displayName":"Home alternate"}'
);
update public.pachanga_competition_match_squads set
  current_revision_id = 'c4900000-0000-4000-8000-000000000024', revision = 2
where id = 'c4800000-0000-4000-8000-000000000014';
update public.pachanga_competition_match_squads set status = 'locked'
where id = 'c4800000-0000-4000-8000-000000000014';
update public.pachanga_competition_match_contexts set status = 'played'
where id = 'c4700000-0000-4000-8000-000000000008';

insert into r5_state values (
  'service', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000030',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
    2, 'service.record', '{}'
  )
);
select pg_temp.r5_assert(
  (select status = 'served' and remaining_units = 0
   from public.pachanga_competition_sanctions
   where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
  'next eligible played fixture must serve the sanction'
);
select pg_temp.r5_assert(
  pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000030',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
    2, 'service.record', '{}'
  ) = (select value from r5_state where key = 'service'),
  'service replay must return the same receipt without consuming twice'
);
insert into r5_state values (
  'service_reverse', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000031',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
    3, 'service.reverse', jsonb_build_object(
      'serviceEventId', (select id from public.pachanga_competition_sanction_service_events
        where event_type = 'SERVED' limit 1),
      'privateReason', 'El partido quedó invalidado para cumplimiento.'
    )
  )
);
select pg_temp.r5_assert(
  (select status = 'active' and remaining_units = 1
   from public.pachanga_competition_sanctions
   where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
  'service reversal must restore the exact pending unit'
);

-- Re-serving after an audited reversal is a new immutable event, not a rewrite.
insert into r5_state values (
  'service_again', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000032',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
    4, 'service.record', '{}'
  )
);
select pg_temp.r5_assert(
  (select count(*) = 3 from public.pachanga_competition_sanction_service_events),
  'served, reversed and re-served evidence must all remain immutable'
);

-- Reverse again before correcting the source event, so no served evidence is hidden.
insert into r5_state values (
  'service_reverse_again', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000033',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
    5, 'service.reverse', jsonb_build_object(
      'serviceEventId', (select id from public.pachanga_competition_sanction_service_events
        where event_type = 'SERVED' order by server_sequence desc, id desc limit 1),
      'privateReason', 'Segunda reversión QA antes de corregir la fuente.'
    )
  )
);

insert into r5_state values (
  'corrected', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000040',
    (select id from public.pachanga_competition_disciplinary_events
      where creation_operation_id = 'c5000000-0000-4000-8000-000000000003'),
    1, 'event.correct',
    '{"cardTypeCode":"BLUE","context":"in_match","minute":51,"publicReasonCategory":"temporary_dismissal","publicSummary":"Corregida a azul","correctionReason":"Corrección oficial del acta."}'
  )
);
select pg_temp.r5_assert(
  (select revision = 2 and current_card_type_code = 'BLUE'
   from public.pachanga_competition_disciplinary_events
   where creation_operation_id = 'c5000000-0000-4000-8000-000000000003')
  and (select count(*) = 2 from public.pachanga_competition_disciplinary_event_revisions
    where disciplinary_event_id = (select id from public.pachanga_competition_disciplinary_events
      where creation_operation_id = 'c5000000-0000-4000-8000-000000000003')),
  'correction must append a superseding revision'
);
select pg_temp.r5_assert(
  (select status = 'cancelled' from public.pachanga_competition_sanctions
   where player_profile_id = 'c4300000-0000-4000-8000-000000000001'),
  'correction below threshold must reconcile the derived sanction'
);

select pg_temp.r5_expect_sql_error(
  $$update public.pachanga_competition_disciplinary_event_revisions
    set public_summary = 'destructive rewrite'
    where operation_id = 'c5000000-0000-4000-8000-000000000040'$$,
  'IMMUTABLE_HISTORY'
);

insert into r5_state values (
  'counter_before', jsonb_build_object('digest', (
    select md5(string_agg(concat_ws('|', card_type_code, active_event_count,
      accumulation_points, threshold_hits, state_checksum), '|' order by card_type_code, id))
    from public.pachanga_competition_disciplinary_counters
    where player_profile_id = 'c4300000-0000-4000-8000-000000000001'
  ))
);
insert into r5_state values (
  'counter_rebuild', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000041',
    (select cycle_id from public.pachanga_competition_disciplinary_events limit 1),
    1, 'counter.rebuild',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000001"}'
  )
);
select pg_temp.r5_assert(
  (select value ->> 'digest' from r5_state where key = 'counter_before') = (
    select md5(string_agg(concat_ws('|', card_type_code, active_event_count,
      accumulation_points, threshold_hits, state_checksum), '|' order by card_type_code, id))
    from public.pachanga_competition_disciplinary_counters
    where player_profile_id = 'c4300000-0000-4000-8000-000000000001'
  ),
  'full counter rebuild must equal incremental materialization'
);

insert into r5_state values (
  'cycle_reset', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000042',
    (select cycle_id from public.pachanga_competition_disciplinary_events limit 1),
    2, 'cycle.reset', '{"effectiveFrom":"2027-06-01T00:00:00Z"}'
  )
);
select pg_temp.r5_assert(
  (select count(*) = 2 and count(*) filter (where status = 'active') = 1
   from public.pachanga_competition_disciplinary_cycles),
  'cycle reset must retain historical cycle and open a new one'
);

-- RED is committee-driven and must not silently choose the minimum range.
insert into r5_state values (
  'red', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000050',
    'c4700000-0000-4000-8000-000000000006', 1, 'event.record',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000003","cardTypeCode":"RED","context":"post_match","publicReasonCategory":"dismissal","publicSummary":"Roja directa"}'
  )
);
select pg_temp.r5_assert(
  (select status = 'provisional' and sanction_outcome = 'COMMITTEE_REQUIRED'
      and total_units = 1 and remaining_units = 1
   from public.pachanga_competition_sanctions
   where player_profile_id = 'c4300000-0000-4000-8000-000000000003'),
  'direct red must remain provisional pending committee'
);
insert into r5_state values (
  'red_decision', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000051',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000003'),
    1, 'sanction.decide',
    '{"decisionOutcome":"FIXED_SANCTION","units":2,"publicReasonCategory":"dismissal","publicSummary":"Dos partidos","ruleArticle":"R5.RED.1","privateReason":"Decisión motivada de la mesa.","evidenceRefs":["qa://red-j4"]}'
  )
);
select pg_temp.r5_assert(
  (select status = 'active' and total_units = 2 and remaining_units = 2
   from public.pachanga_competition_sanctions
   where player_profile_id = 'c4300000-0000-4000-8000-000000000003'),
  'committee must explicitly choose a value inside the range'
);

insert into r5_state values (
  'red_appeal_submit', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000010',
    'c5000000-0000-4000-8000-000000000053',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000003'),
    2, 'appeal.submit', '{"statement":"Solicito reducir la sanción."}'
  )
);
insert into r5_state values (
  'red_appeal_admissible', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000054',
    (select id from public.pachanga_competition_sanction_appeals
      where creation_operation_id = 'c5000000-0000-4000-8000-000000000053'),
    1, 'appeal.transition',
    '{"status":"admissible","publicResolution":"Admitida","privateReason":"Existe base para revisión."}'
  )
);
insert into r5_state values (
  'red_appeal_review', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000055',
    (select id from public.pachanga_competition_sanction_appeals
      where creation_operation_id = 'c5000000-0000-4000-8000-000000000053'),
    2, 'appeal.transition',
    '{"status":"under_review","publicResolution":"En revisión","privateReason":"Revisión del acta en curso."}'
  )
);
insert into r5_state values (
  'red_appeal_modified', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000002',
    'c5000000-0000-4000-8000-000000000056',
    (select id from public.pachanga_competition_sanction_appeals
      where creation_operation_id = 'c5000000-0000-4000-8000-000000000053'),
    3, 'appeal.transition',
    '{"status":"modified","modifiedUnits":1,"publicResolution":"Reducida a un partido","privateReason":"La revisión reduce la sanción."}'
  )
);
select pg_temp.r5_assert(
  (select status = 'modified' and revision = 4
   from public.pachanga_competition_sanction_appeals
   where creation_operation_id = 'c5000000-0000-4000-8000-000000000053')
  and (select status = 'active' and total_units = 1 and remaining_units = 1
    from public.pachanga_competition_sanctions
    where player_profile_id = 'c4300000-0000-4000-8000-000000000003'),
  'modified appeal must append history and update the canonical sanction once'
);

insert into r5_state values (
  'red_appeal_submit_withdraw', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000010',
    'c5000000-0000-4000-8000-000000000057',
    (select id from public.pachanga_competition_sanctions
      where player_profile_id = 'c4300000-0000-4000-8000-000000000003'),
    3, 'appeal.submit', '{"statement":"Segunda apelación para retirada QA."}'
  )
);
insert into r5_state values (
  'red_appeal_withdrawn', pg_temp.r5_command(
    'c4010000-0000-4000-8000-000000000010',
    'c5000000-0000-4000-8000-000000000058',
    (select id from public.pachanga_competition_sanction_appeals
      where creation_operation_id = 'c5000000-0000-4000-8000-000000000057'),
    1, 'appeal.withdraw', '{}'
  )
);
select pg_temp.r5_assert(
  (select status = 'withdrawn' and revision = 2
   from public.pachanga_competition_sanction_appeals
   where creation_operation_id = 'c5000000-0000-4000-8000-000000000057'),
  'the appellant must be able to withdraw without changing sanction units'
);

update public.pachanga_competition_sanctions set created_at = clock_timestamp() - interval '73 hours'
where player_profile_id = 'c4300000-0000-4000-8000-000000000003';
select pg_temp.r5_expect_command_error(
  'c4010000-0000-4000-8000-000000000010',
  'c5000000-0000-4000-8000-000000000052',
  (select id from public.pachanga_competition_sanctions
    where player_profile_id = 'c4300000-0000-4000-8000-000000000003'),
  2, 'appeal.submit', '{"statement":"Fuera de plazo."}', 'DEADLINE_EXPIRED'
);

select pg_temp.r5_assert(
  not exists (
    select 1 from r5_invariants before
    where before.digest <> case before.key
      when 'rating' then pg_temp.r5_table_digest('public.pachanga_player_rating_snapshots')
      when 'rewards' then pg_temp.r5_table_digest('public.pachanga_reward_grants')
      when 'player_cosmetics' then pg_temp.r5_table_digest('public.pachanga_player_cosmetic_loadouts')
      when 'team_cosmetics' then pg_temp.r5_table_digest('public.pachanga_team_cosmetic_inventory')
      when 'conduct' then pg_temp.r5_table_digest('private.pachanga_conduct_reports')
      when 'billing' then pg_temp.r5_table_digest('public.pachanga_stripe_webhook_events')
      when 'ranking' then pg_temp.r5_table_digest('public.pachanga_provincial_ranking_entries')
    end
  ),
  'R5 must not alter Rating, Rewards, Cosmetics, Conduct, Billing or Ranking'
);

select pg_temp.r5_assert(
  exists (select 1 from public.pachanga_user_notifications
    where kind = 'competition_discipline_event')
  and exists (select 1 from public.pachanga_user_notifications
    where kind = 'competition_sanction_status' and title in ('Sanción provisional', 'Sanción confirmada'))
  and exists (select 1 from public.pachanga_user_notifications
    where kind = 'competition_sanction_pending')
  and exists (select 1 from public.pachanga_user_notifications
    where kind = 'competition_sanction_service' and title = 'Sanción cumplida')
  and exists (select 1 from public.pachanga_user_notifications
    where kind = 'competition_discipline_appeal' and title = 'Apelación resuelta'),
  'R5 must emit the required idempotent notification states'
);

select 'R5_DB_REPORT|' || jsonb_build_object(
  'events', (select count(*) from public.pachanga_competition_disciplinary_events),
  'eventRevisions', (select count(*) from public.pachanga_competition_disciplinary_event_revisions),
  'cycles', (select count(*) from public.pachanga_competition_disciplinary_cycles),
  'counters', (select count(*) from public.pachanga_competition_disciplinary_counters),
  'sanctions', (select count(*) from public.pachanga_competition_sanctions),
  'serviceEvents', (select count(*) from public.pachanga_competition_sanction_service_events),
  'appeals', (select count(*) from public.pachanga_competition_sanction_appeals),
  'publicDiscipline', false,
  'invariants', 'IDENTICAL'
)::text;
