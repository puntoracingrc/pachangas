\set ON_ERROR_STOP on

create or replace function pg_temp.w4_assert(condition boolean, message text)
returns void language plpgsql as $$
begin
  if not coalesce(condition, false) then raise exception 'WAVE4_ASSERT:%', message; end if;
end;
$$;

create or replace function pg_temp.w4_actor(actor_id uuid)
returns void language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('role', 'authenticated', 'sub', actor_id)::text,
    false
  );
end;
$$;

create or replace function pg_temp.w4_command(
  actor_id uuid, operation_id uuid, assignment_id uuid,
  expected_revision bigint, action_name text, payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql as $$
begin
  perform pg_temp.w4_actor(actor_id);
  return public.command_pachanga_referee_assignment_beta_v1(
    operation_id, assignment_id, expected_revision, action_name, payload,
    '{"clientVersion":"6.0.0+wave4-db","serviceWorkerVersion":"sw-wave4-db","installedMode":"standalone","surface":"wave4_db"}'
  );
end;
$$;

create or replace function pg_temp.w4_officiate(
  actor_id uuid, operation_id uuid, assignment_id uuid,
  expected_revision bigint, action_name text, payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql as $$
begin
  perform pg_temp.w4_actor(actor_id);
  return public.command_pachanga_referee_officiating_v1(
    operation_id, assignment_id, expected_revision, action_name, payload,
    '{"clientVersion":"6.0.0+wave4-db","serviceWorkerVersion":"sw-wave4-db","installedMode":"standalone","surface":"wave4_db"}'
  );
end;
$$;

create or replace function pg_temp.w4_expect_error(statement text, expected_error text)
returns void language plpgsql as $$
declare caught boolean := false;
begin
  begin
    execute statement;
  exception when others then
    caught := true;
    if sqlerrm !~ expected_error then
      raise exception 'WAVE4_WRONG_ERROR expected=% actual=%', expected_error, sqlerrm;
    end if;
  end;
  if not caught then raise exception 'WAVE4_EXPECTED_ERROR_NOT_RAISED:%', expected_error; end if;
end;
$$;

create or replace function pg_temp.w4_table_digest(target regclass)
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

create temporary table w4_state(key text primary key, value jsonb not null);
create temporary table w4_invariants(key text primary key, digest text not null);
create temporary table w4_constants(deadline timestamptz not null);
insert into w4_constants values (date_trunc('second', clock_timestamp() + interval '10 days'));

insert into w4_invariants values
  ('rating', pg_temp.w4_table_digest('public.pachanga_player_rating_snapshots')),
  ('rewards', pg_temp.w4_table_digest('public.pachanga_reward_grants')),
  ('player_cosmetics', pg_temp.w4_table_digest('public.pachanga_player_cosmetic_loadouts')),
  ('team_cosmetics', pg_temp.w4_table_digest('public.pachanga_team_cosmetic_inventory')),
  ('conduct', pg_temp.w4_table_digest('private.pachanga_conduct_reports')),
  ('billing', pg_temp.w4_table_digest('public.pachanga_stripe_webhook_events'));

-- W4-009: R4D must be able to invalidate an R5 match sheet after a schedule
-- change. A legacy NOT_AVAILABLE-only check used to coexist with this one.
select pg_temp.w4_assert(
  (
    select count(*) = 1
      and bool_and(pg_get_constraintdef(constraints.oid) like '%STALE%')
    from pg_constraint constraints
    where constraints.conrelid = 'public.pachanga_competition_match_sheets'::regclass
      and pg_get_constraintdef(constraints.oid) ilike '%discipline_validation_status%'
  ),
  'W4-009 match sheet must retain exactly one discipline status check with STALE'
);

-- W4-002: League Private Beta can only activate assignments after the new
-- private assignment gate is explicitly enabled.
select pg_temp.w4_expect_error(
  $$update private.pachanga_referee_foundation_settings
      set referee_assignments_enabled = true where singleton$$,
  'REFEREE_ASSIGNMENTS_NOT_AVAILABLE_IN_LEAGUE_BETA|private_beta_gate'
);

update private.pachanga_referee_foundation_settings set
  referee_assignment_private_beta_enabled = true,
  referee_assignments_enabled = true,
  revision = revision + 1
where singleton;

select pg_temp.w4_assert(
  (select referee_assignment_private_beta_enabled and referee_assignments_enabled
   from private.pachanga_referee_foundation_settings where singleton),
  'W4-002 private beta gate must coexist with League Private Beta'
);

insert into w4_state values (
  'proposal_a', pg_temp.w4_command(
    'c4010000-0000-4000-8000-000000000002',
    'd6030000-0000-4000-8000-000000000001',
    'd6040000-0000-4000-8000-000000000001', 0, 'assignment.propose',
    jsonb_build_object(
      'refereeProfileId', 'd6020000-0000-4000-8000-000000000001',
      'sourceKind', 'competition_generated',
      'sourceId', 'c4500000-0000-4000-8000-000000000005',
      'requesterKind', 'COMPETITION',
      'requesterId', 'c4200000-0000-4000-8000-000000000001',
      'assignmentRole', 'MAIN_REFEREE',
      'responseDeadline', (select deadline from w4_constants),
      'feeMode', 'FIXED', 'proposedFeeCents', 6500, 'currency', 'EUR',
      'privateTermsNote', 'Wave 4 private terms must never reach participants'
    )
  )
);

select pg_temp.w4_assert(
  (select value from w4_state where key = 'proposal_a') = pg_temp.w4_command(
    'c4010000-0000-4000-8000-000000000002',
    'd6030000-0000-4000-8000-000000000001',
    'd6040000-0000-4000-8000-000000000001', 0, 'assignment.propose',
    jsonb_build_object(
      'refereeProfileId', 'd6020000-0000-4000-8000-000000000001',
      'sourceKind', 'competition_generated',
      'sourceId', 'c4500000-0000-4000-8000-000000000005',
      'requesterKind', 'COMPETITION',
      'requesterId', 'c4200000-0000-4000-8000-000000000001',
      'assignmentRole', 'MAIN_REFEREE',
      'responseDeadline', (select deadline from w4_constants),
      'feeMode', 'FIXED', 'proposedFeeCents', 6500, 'currency', 'EUR',
      'privateTermsNote', 'Wave 4 private terms must never reach participants'
    )
  ),
  'operation replay must return the original canonical receipt'
);

-- The replay payload above contains clock_timestamp, so prove persistence
-- idempotency independently of object equality.
select pg_temp.w4_assert(
  (select count(*) = 1 from public.pachanga_referee_assignments
    where id = 'd6040000-0000-4000-8000-000000000001')
  and (select count(*) = 1 from private.pachanga_referee_operation_receipts
       where operation_id = 'd6030000-0000-4000-8000-000000000001'),
  'proposal replay must not duplicate assignment or receipt'
);

insert into w4_state values (
  'accept_a', pg_temp.w4_command(
    'd6010000-0000-4000-8000-000000000001',
    'd6030000-0000-4000-8000-000000000002',
    'd6040000-0000-4000-8000-000000000001', 1, 'assignment.accept'
  )
);
insert into w4_state values (
  'confirm_a', pg_temp.w4_command(
    'c4010000-0000-4000-8000-000000000002',
    'd6030000-0000-4000-8000-000000000003',
    'd6040000-0000-4000-8000-000000000001', 2, 'assignment.confirm'
  )
);

select pg_temp.w4_assert(
  (select status = 'confirmed' and revision = 3
   from public.pachanga_referee_assignments
   where id = 'd6040000-0000-4000-8000-000000000001'),
  'requester confirmation must create one current MAIN_REFEREE'
);

-- A second proposal may exist, but acceptance cannot create a second MAIN.
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000004',
  'd6040000-0000-4000-8000-000000000002', 0, 'assignment.propose',
  jsonb_build_object(
    'refereeProfileId', 'd6020000-0000-4000-8000-000000000002',
    'sourceKind', 'competition_generated',
    'sourceId', 'c4500000-0000-4000-8000-000000000005',
    'requesterKind', 'COMPETITION',
    'requesterId', 'c4200000-0000-4000-8000-000000000001',
    'responseDeadline', (select deadline from w4_constants),
    'feeMode', 'FREE'
  )
);
select pg_temp.w4_expect_error(
  $$select pg_temp.w4_command(
    'd6010000-0000-4000-8000-000000000002',
    'd6030000-0000-4000-8000-000000000005',
    'd6040000-0000-4000-8000-000000000002', 1, 'assignment.accept'
  )$$,
  'REFEREE_ASSIGNMENT_SLOT_TAKEN|REFEREE_ASSIGNMENT_CONFLICT'
);

-- Recurring availability is server authority, not a browser hint.
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000006',
  'd6040000-0000-4000-8000-000000000003', 0, 'assignment.propose',
  jsonb_build_object(
    'refereeProfileId', 'd6020000-0000-4000-8000-000000000004',
    'sourceKind', 'competition_generated',
    'sourceId', 'c4600000-0000-4000-8000-000000000005',
    'requesterKind', 'COMPETITION',
    'requesterId', 'c4200000-0000-4000-8000-000000000001',
    'responseDeadline', (select deadline from w4_constants),
    'feeMode', 'VOLUNTEER'
  )
);
select pg_temp.w4_expect_error(
  $$select pg_temp.w4_command(
    'd6010000-0000-4000-8000-000000000004',
    'd6030000-0000-4000-8000-000000000007',
    'd6040000-0000-4000-8000-000000000003', 1, 'assignment.accept'
  )$$,
  'REFEREE_OUTSIDE_RECURRING_AVAILABILITY'
);

-- Different CanonicalMatches cannot give the same referee overlapping
-- accepted assignments. A normal cancellation remains auditable and terminal.
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000020',
  'd6040000-0000-4000-8000-000000000020', 0, 'assignment.propose',
  jsonb_build_object(
    'refereeProfileId', 'd6020000-0000-4000-8000-000000000003',
    'sourceKind', 'competition_generated',
    'sourceId', 'c4600000-0000-4000-8000-000000000005',
    'requesterKind', 'COMPETITION',
    'requesterId', 'c4200000-0000-4000-8000-000000000001',
    'responseDeadline', (select deadline from w4_constants),
    'feeMode', 'VOLUNTEER'
  )
);
select pg_temp.w4_command(
  'd6010000-0000-4000-8000-000000000003',
  'd6030000-0000-4000-8000-000000000021',
  'd6040000-0000-4000-8000-000000000020', 1, 'assignment.accept'
);
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000022',
  'd6040000-0000-4000-8000-000000000021', 0, 'assignment.propose',
  jsonb_build_object(
    'refereeProfileId', 'd6020000-0000-4000-8000-000000000003',
    'sourceKind', 'competition_generated',
    'sourceId', 'c4700000-0000-4000-8000-000000000005',
    'requesterKind', 'COMPETITION',
    'requesterId', 'c4200000-0000-4000-8000-000000000001',
    'responseDeadline', (select deadline from w4_constants),
    'feeMode', 'VOLUNTEER'
  )
);
select pg_temp.w4_expect_error(
  $$select pg_temp.w4_command(
    'd6010000-0000-4000-8000-000000000003',
    'd6030000-0000-4000-8000-000000000023',
    'd6040000-0000-4000-8000-000000000021', 1, 'assignment.accept'
  )$$,
  'REFEREE_ASSIGNMENT_TIME_CONFLICT|REFEREE_ASSIGNMENT_CONFLICT'
);
select pg_temp.w4_command(
  'd6010000-0000-4000-8000-000000000003',
  'd6030000-0000-4000-8000-000000000024',
  'd6040000-0000-4000-8000-000000000020', 2, 'assignment.cancel',
  '{"reasonCode":"referee_unavailable","reasonText":"Deterministic cancellation regression"}'
);
select pg_temp.w4_assert(
  (select status = 'cancelled' and cancelled_by = 'd6010000-0000-4000-8000-000000000003'
   from public.pachanga_referee_assignments
   where id = 'd6040000-0000-4000-8000-000000000020'),
  'referee cancellation must persist actor and terminal status'
);

-- W4-001: proposing and accepting a replacement keeps the original assignment
-- confirmed. Only the requester confirmation performs the atomic handover.
insert into w4_state values (
  'replace_proposal', pg_temp.w4_command(
    'c4010000-0000-4000-8000-000000000002',
    'd6030000-0000-4000-8000-000000000008',
    'd6040000-0000-4000-8000-000000000001', 3, 'assignment.replace',
    jsonb_build_object(
      'newRefereeProfileId', 'd6020000-0000-4000-8000-000000000002',
      'newAssignmentId', 'd6040000-0000-4000-8000-000000000004',
      'responseDeadline', (select deadline from w4_constants),
      'feeMode', 'NEGOTIABLE', 'proposedFeeCents', 7000,
      'privateTermsNote', 'Replacement terms'
    )
  )
);
select pg_temp.w4_command(
  'd6010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000009',
  'd6040000-0000-4000-8000-000000000004', 1, 'assignment.accept'
);
select pg_temp.w4_assert(
  (select status = 'confirmed' and replacement_pending_assignment_id = 'd6040000-0000-4000-8000-000000000004'
   from public.pachanga_referee_assignments where id = 'd6040000-0000-4000-8000-000000000001')
  and (select status = 'accepted'
       from public.pachanga_referee_assignments where id = 'd6040000-0000-4000-8000-000000000004'),
  'W4-001 replacement acceptance must not displace the confirmed referee'
);
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000010',
  'd6040000-0000-4000-8000-000000000004', 2, 'assignment.confirm'
);
select pg_temp.w4_assert(
  (select status = 'replaced' and replaced_by_assignment_id = 'd6040000-0000-4000-8000-000000000004'
   from public.pachanga_referee_assignments where id = 'd6040000-0000-4000-8000-000000000001')
  and (select status = 'confirmed'
       from public.pachanga_referee_assignments where id = 'd6040000-0000-4000-8000-000000000004')
  and (select count(*) = 1 from public.pachanga_referee_assignments
       where canonical_match_id = 'c4500000-0000-4000-8000-000000000006'
         and assignment_role = 'MAIN_REFEREE' and status = 'confirmed'),
  'replacement confirmation must atomically preserve one MAIN_REFEREE'
);

-- A real R4D revision invalidates the prior confirmation. Original scheduling
-- evidence remains immutable and only the referee can reconfirm the effective
-- schedule with the current assignment revision.
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000030',
  'd6040000-0000-4000-8000-000000000030', 0, 'assignment.propose',
  jsonb_build_object(
    'refereeProfileId', 'd6020000-0000-4000-8000-000000000001',
    'sourceKind', 'competition_generated',
    'sourceId', 'c4400000-0000-4000-8000-000000000005',
    'requesterKind', 'COMPETITION',
    'requesterId', 'c4200000-0000-4000-8000-000000000001',
    'responseDeadline', (select deadline from w4_constants),
    'feeMode', 'FREE'
  )
);
select pg_temp.w4_command(
  'd6010000-0000-4000-8000-000000000001',
  'd6030000-0000-4000-8000-000000000031',
  'd6040000-0000-4000-8000-000000000030', 1, 'assignment.accept'
);
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000032',
  'd6040000-0000-4000-8000-000000000030', 2, 'assignment.confirm'
);

insert into public.pachanga_competition_fixture_changes(
  id, competition_id, canonical_match_id, competition_match_context_id,
  schedule_item_id, rule_revision_id, change_type, status, source_type,
  original_scheduled_start, original_scheduled_end, original_timezone,
  original_venue_label, original_venue_status, creation_operation_id, created_by
) values (
  'd6070000-0000-4000-8000-000000000001',
  'c4200000-0000-4000-8000-000000000001',
  'c4400000-0000-4000-8000-000000000006',
  'c4400000-0000-4000-8000-000000000008',
  'c4400000-0000-4000-8000-000000000005',
  'c4200000-0000-4000-8000-000000000003',
  'TIME_CHANGE', 'active', 'DIRECT_OPERATION',
  '2027-03-01T19:00:00Z', '2027-03-01T20:10:00Z', 'Europe/Madrid',
  'Pista R4C', 'CONFIRMED',
  'd6070000-0000-4000-8000-000000000003',
  'c4010000-0000-4000-8000-000000000002'
);
insert into public.pachanga_competition_fixture_change_revisions(
  id, fixture_change_id, version, change_type,
  effective_scheduled_start, effective_scheduled_end, effective_timezone,
  effective_venue_label, effective_venue_status, effective_resource_key,
  public_reason_code, public_summary, operation_id, created_by
) values (
  'd6070000-0000-4000-8000-000000000002',
  'd6070000-0000-4000-8000-000000000001', 1, 'TIME_CHANGE',
  '2027-03-01T20:30:00Z', '2027-03-01T21:40:00Z', 'Europe/Madrid',
  'Pista R4C', 'SAVED', 'wave4-reconfirm-pista',
  'wave4.fixture.reconfirm', 'Cambio horario para reconfirmacion arbitral',
  'd6070000-0000-4000-8000-000000000004',
  'c4010000-0000-4000-8000-000000000002'
);
update public.pachanga_competition_fixture_changes set
  current_revision_id = 'd6070000-0000-4000-8000-000000000002'
where id = 'd6070000-0000-4000-8000-000000000001';

select pg_temp.w4_assert(
  (select status = 'confirmed' and schedule_state = 'RECONFIRMATION_REQUIRED'
      and revision = 4
      and scheduled_start = '2027-03-01T19:00:00Z'
      and effective_scheduled_start = '2027-03-01T20:30:00Z'
   from public.pachanga_referee_assignments
   where id = 'd6040000-0000-4000-8000-000000000030'),
  'R4D must preserve original schedule and require reconfirmation'
);
select pg_temp.w4_expect_error(
  $$select pg_temp.w4_command(
    'd6010000-0000-4000-8000-000000000001',
    'd6030000-0000-4000-8000-000000000033',
    'd6040000-0000-4000-8000-000000000030', 3, 'assignment.reconfirm'
  )$$,
  'STALE_REVISION'
);
select pg_temp.w4_command(
  'd6010000-0000-4000-8000-000000000001',
  'd6030000-0000-4000-8000-000000000034',
  'd6040000-0000-4000-8000-000000000030', 4, 'assignment.reconfirm'
);
select pg_temp.w4_assert(
  (select status = 'confirmed' and schedule_state = 'CURRENT'
      and revision = 5 and reconfirmed_at is not null
      and scheduled_start = '2027-03-01T19:00:00Z'
      and effective_scheduled_start = '2027-03-01T20:30:00Z'
   from public.pachanga_referee_assignments
   where id = 'd6040000-0000-4000-8000-000000000030'),
  'referee reconfirmation must adopt the canonical effective schedule only'
);

-- Negotiated terms remain private, versioned and requester-confirmed.
select pg_temp.w4_command(
  'd6010000-0000-4000-8000-000000000003',
  'd6030000-0000-4000-8000-000000000040',
  'd6040000-0000-4000-8000-000000000021', 1, 'assignment.cancel',
  '{"reasonCode":"superseded_test_proposal","reasonText":"Replace fixture proposal with negotiated terms"}'
);
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000041',
  'd6040000-0000-4000-8000-000000000040', 0, 'assignment.propose',
  jsonb_build_object(
    'refereeProfileId', 'd6020000-0000-4000-8000-000000000003',
    'sourceKind', 'competition_generated',
    'sourceId', 'c4700000-0000-4000-8000-000000000005',
    'requesterKind', 'COMPETITION',
    'requesterId', 'c4200000-0000-4000-8000-000000000001',
    'responseDeadline', (select deadline from w4_constants),
    'feeMode', 'NEGOTIABLE', 'proposedFeeCents', 5500,
    'privateTermsNote', 'Oferta privada inicial'
  )
);
select pg_temp.w4_command(
  'd6010000-0000-4000-8000-000000000003',
  'd6030000-0000-4000-8000-000000000042',
  'd6040000-0000-4000-8000-000000000040', 1, 'terms.counter',
  '{"counterFeeCents":6200,"privateTermsNote":"Contraoferta privada"}'
);
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000043',
  'd6040000-0000-4000-8000-000000000040', 2, 'terms.accept'
);
select pg_temp.w4_command(
  'c4010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000044',
  'd6040000-0000-4000-8000-000000000040', 3, 'assignment.confirm'
);
select pg_temp.w4_assert(
  (select terms_status = 'ACCEPTED' and proposed_fee_cents = 5500
      and counter_fee_cents = 6200 and agreed_fee_cents = 6200
      and terms_revision = 3
   from private.pachanga_referee_assignment_terms
   where assignment_id = 'd6040000-0000-4000-8000-000000000040')
  and (select count(*) = 3
       from private.pachanga_referee_assignment_term_revisions
       where assignment_id = 'd6040000-0000-4000-8000-000000000040'),
  'counterproposal must preserve immutable private term history'
);

-- A confirmed current referee may add private score evidence and a narrow R5
-- card event. Neither command may alter the R4C sporting-result authority.
insert into w4_state values (
  'r4c_before_officiating', jsonb_build_object(
    'results', pg_temp.w4_table_digest('public.pachanga_competition_sporting_results'),
    'revisions', pg_temp.w4_table_digest('public.pachanga_competition_sporting_result_revisions')
  )
);
update public.pachanga_competition_match_contexts
set status = 'ready', revision = revision + 1
where id = 'c4500000-0000-4000-8000-000000000008';
select pg_temp.w4_officiate(
  'd6010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000050',
  'd6040000-0000-4000-8000-000000000004', 3, 'result.observe',
  '{"homeScore":2,"awayScore":1,"privateNote":"Observacion privada Wave 4"}'
);
select pg_temp.w4_assert(
  (select revision = 4 from public.pachanga_referee_assignments
   where id = 'd6040000-0000-4000-8000-000000000004')
  and (select count(*) = 1 and min(home_score) = 2 and min(away_score) = 1
       from private.pachanga_referee_result_observations
       where assignment_id = 'd6040000-0000-4000-8000-000000000004')
  and (select value ->> 'results' from w4_state where key = 'r4c_before_officiating')
      = pg_temp.w4_table_digest('public.pachanga_competition_sporting_results')
  and (select value ->> 'revisions' from w4_state where key = 'r4c_before_officiating')
      = pg_temp.w4_table_digest('public.pachanga_competition_sporting_result_revisions'),
  'result observation must remain private evidence outside R4C authority'
);
select pg_temp.w4_expect_error(
  $$select pg_temp.w4_officiate(
    'd6010000-0000-4000-8000-000000000001',
    'd6030000-0000-4000-8000-000000000051',
    'd6040000-0000-4000-8000-000000000001', 5, 'discipline.record',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":18}'
  )$$,
  'REFEREE_CURRENT_CONFIRMED_ASSIGNMENT_REQUIRED'
);
select pg_temp.w4_expect_error(
  $$select pg_temp.w4_officiate(
    'd6010000-0000-4000-8000-000000000002',
    'd6030000-0000-4000-8000-000000000052',
    'd6040000-0000-4000-8000-000000000004', 4, 'discipline.record',
    '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":18,"sanction":{"units":3}}'
  )$$,
  'REFEREE_OFFICIATING_SERVER_FIELDS_FORBIDDEN'
);
select pg_temp.w4_officiate(
  'd6010000-0000-4000-8000-000000000002',
  'd6030000-0000-4000-8000-000000000053',
  'd6040000-0000-4000-8000-000000000004', 4, 'discipline.record',
  '{"playerProfileId":"c4300000-0000-4000-8000-000000000001","cardTypeCode":"YELLOW","context":"in_match","minute":18,"period":"FIRST_HALF","publicSummary":"Amonestacion registrada por el arbitro confirmado"}'
);
select pg_temp.w4_assert(
  (select revision = 5 from public.pachanga_referee_assignments
   where id = 'd6040000-0000-4000-8000-000000000004')
  and (select count(*) = 1
       from public.pachanga_competition_disciplinary_events
       where referee_assignment_id = 'd6040000-0000-4000-8000-000000000004'
         and reporting_referee_profile_id = 'd6020000-0000-4000-8000-000000000002'
         and current_card_type_code = 'YELLOW')
  and (select yellow_cards_shown = 1 and discipline_stats_status = 'CANONICAL_R5'
       from public.pachanga_referee_statistics_snapshots
       where referee_profile_id = 'd6020000-0000-4000-8000-000000000002')
  and (select value ->> 'results' from w4_state where key = 'r4c_before_officiating')
      = pg_temp.w4_table_digest('public.pachanga_competition_sporting_results'),
  'R5 event must reference the current assignment without changing R4C'
);

insert into w4_state values (
  'stats_before_rebuild', jsonb_build_object(
    'checksum', (select checksum from public.pachanga_referee_statistics_snapshots
                 where referee_profile_id = 'd6020000-0000-4000-8000-000000000002')
  )
);
select private.pachanga_referee_refresh_statistics_v1(
  'd6020000-0000-4000-8000-000000000002', 'full_rebuild'
);
select pg_temp.w4_assert(
  (select value ->> 'checksum' from w4_state where key = 'stats_before_rebuild')
    = (select checksum from public.pachanga_referee_statistics_snapshots
       where referee_profile_id = 'd6020000-0000-4000-8000-000000000002'),
  'incremental and full referee statistics rebuilds must converge'
);

update public.pachanga_competition_match_contexts
set status = 'official', revision = revision + 1
where id = 'c4500000-0000-4000-8000-000000000008';
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000001');
insert into w4_state values (
  'completion', public.reconcile_pachanga_referee_assignment_v1(
    'd6030000-0000-4000-8000-000000000054',
    'd6040000-0000-4000-8000-000000000004', 5,
    '{"clientVersion":"6.0.0+wave4-db","surface":"wave4_db"}'
  )
);
select pg_temp.w4_assert(
  (select value from w4_state where key = 'completion')
    = public.reconcile_pachanga_referee_assignment_v1(
      'd6030000-0000-4000-8000-000000000054',
      'd6040000-0000-4000-8000-000000000004', 5,
      '{"clientVersion":"6.0.0+wave4-db","surface":"wave4_db"}'
    )
  and (select status = 'completed' and revision = 6 and completed_at is not null
       from public.pachanga_referee_assignments
       where id = 'd6040000-0000-4000-8000-000000000004')
  and (select count(*) = 1 from private.pachanga_referee_operation_receipts
       where operation_id = 'd6030000-0000-4000-8000-000000000054'),
  'completion must reconcile once and replay the canonical receipt'
);

-- W4-011: completion is terminal except for the narrow, audited platform
-- correction that voids it and rebuilds the referee statistics.
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000001');
insert into w4_state values (
  'completion_void', public.command_pachanga_referee_platform_admin_v1(
    'd6030000-0000-4000-8000-000000000055',
    'd6040000-0000-4000-8000-000000000004', 6,
    'assignment.completion.void',
    '{"reason":"Wave 4 audited completion correction"}',
    '{"clientVersion":"6.0.0+wave4-db","surface":"wave4_db"}'
  )
);
select pg_temp.w4_assert(
  (select status = 'cancelled'
          and revision = 7
          and completed_at is null
          and cancel_reason_code = 'completion_voided'
          and cancelled_by = 'c4010000-0000-4000-8000-000000000001'
   from public.pachanga_referee_assignments
   where id = 'd6040000-0000-4000-8000-000000000004')
  and (select value #>> '{snapshot,assignment,status}' = 'cancelled'
       from w4_state where key = 'completion_void'),
  'platform completion void must be the only audited escape from completed'
);
select set_config('pachangas.referee_reason', 'assignment.cancel', false);
select pg_temp.w4_expect_error(
  $$update public.pachanga_referee_assignments
      set status = 'confirmed'
      where id = 'd6040000-0000-4000-8000-000000000004'$$,
  'REFEREE_ASSIGNMENT_TERMINAL'
);
select set_config('pachangas.referee_reason', '', false);

-- Public fee disclosure requires both the generic profile publication consent
-- and a separate, content-bound acknowledgement that payments stay external.
do $$
declare response jsonb; profile_revision bigint := 1;
begin
  perform pg_temp.w4_actor('d6010000-0000-4000-8000-000000000002');
  response := public.command_pachanga_referee_public_fee_v1(
    'd6030000-0000-4000-8000-000000000060',
    'd6020000-0000-4000-8000-000000000002', profile_revision,
    'public_fee.configure',
    '{"feeMode":"FIXED","fromCents":7500,"currency":"EUR"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_publication_consent_v1(
    'd6030000-0000-4000-8000-000000000061',
    'REFEREE_PROFILE', 'd6020000-0000-4000-8000-000000000002', profile_revision,
    '{"informationCorrect":true,"unverifiedNotCertification":true,"publicZonesAvailability":true}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'd6030000-0000-4000-8000-000000000062',
    'd6020000-0000-4000-8000-000000000002', profile_revision,
    'profile.update',
    '{"visibility":"public","availabilityStatus":"AVAILABLE","availableForAssignments":true,"shareRecurringAvailability":true,"reason":"Wave 4 public profile"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_platform_v1(
    'd6030000-0000-4000-8000-000000000063',
    'd6020000-0000-4000-8000-000000000002', profile_revision,
    'marketplace.list', '{"reason":"Wave 4 marketplace listing"}', '{}'
  );
  profile_revision := (response ->> 'confirmedRevision')::bigint;
  response := public.command_pachanga_referee_public_fee_v1(
    'd6030000-0000-4000-8000-000000000064',
    'd6020000-0000-4000-8000-000000000002', profile_revision,
    'public_fee.publish',
    '{"informationCorrect":true,"outOfPlatformPaymentAcknowledged":true}', '{}'
  );
  perform pg_temp.w4_assert(
    response #>> '{snapshot,publicFee,visible}' = 'true'
      and response #>> '{snapshot,publicFee,paymentManagedByPachangasIq}' = 'false',
    'public fee consent must explicitly preserve out-of-platform payment authority'
  );
end;
$$;
select pg_temp.w4_assert(
  public.get_pachanga_public_referee_v1('wave4-referee-b') #>> '{publicFee,feeMode}' = 'FIXED'
  and public.get_pachanga_public_referee_v1('wave4-referee-b') #>> '{publicFee,fromCents}' = '7500'
  and public.get_pachanga_public_referee_v1('wave4-referee-b') #>> '{publicFee,paymentManagedByPachangasIq}' = 'false',
  'public profile must expose only the separately consented fee summary'
);

-- W4-003: the legacy command can no longer write assignments once Wave 4 is on.
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000003');
select pg_temp.w4_expect_error(
  $$select public.command_pachanga_referee_platform_v1(
    'd6030000-0000-4000-8000-000000000011',
    'd6040000-0000-4000-8000-000000000005', 0,
    'assignment.propose',
    '{"refereeProfileId":"d6020000-0000-4000-8000-000000000003","requesterKind":"TEAM","requesterId":"c4100000-0000-4000-8000-000000000002","sourceKind":"group_match","sourceGroupId":"c4100000-0000-4000-8000-000000000002","sourceId":"wave4-legacy-match","reason":"legacy bypass"}',
    '{}'
  )$$,
  'REFEREE_LEGACY_ASSIGNMENT_WRITE_DISABLED'
);

-- Participants can read the current confirmed referee, never private terms.
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000005');
insert into w4_state values (
  'participant_read', public.get_pachanga_referee_match_assignment_v1(
    'c4500000-0000-4000-8000-000000000006'
  )
);
select pg_temp.w4_assert(
  jsonb_array_length((select value -> 'items' from w4_state where key = 'participant_read')) >= 1
  and not jsonb_path_exists(
    (select value from w4_state where key = 'participant_read'),
    '$.**.privateTerms'
  ),
  'match participant must see confirmed referee without private terms'
);
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000007');
select pg_temp.w4_expect_error(
  $$select public.get_pachanga_referee_match_assignment_v1(
    'c4500000-0000-4000-8000-000000000006'
  )$$,
  'REFEREE_MATCH_READ_REQUIRED'
);

-- W4-006: Realtime remains a refetch signal, but every legitimate reader of a
-- competition Assignment must be able to receive that signal through RLS.
select pg_temp.w4_assert(
  exists (
    select 1 from public.pachanga_referee_invalidations invalidations
    where invalidations.entity_type = 'referee_assignment'
      and invalidations.competition_id = 'c4200000-0000-4000-8000-000000000001'
      and invalidations.canonical_match_id is not null
  ),
  'assignment invalidations must derive canonical match and competition scope'
);
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000005');
set role authenticated;
select pg_temp.w4_assert(
  exists (
    select 1 from public.pachanga_referee_invalidations invalidations
    where invalidations.entity_type = 'referee_assignment'
      and invalidations.canonical_match_id = 'c4500000-0000-4000-8000-000000000006'
  ),
  'match participant must receive the canonical assignment invalidation'
);
reset role;
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000009');
set role authenticated;
select pg_temp.w4_assert(
  exists (
    select 1 from public.pachanga_referee_invalidations invalidations
    where invalidations.entity_type = 'referee_assignment'
      and invalidations.competition_id = 'c4200000-0000-4000-8000-000000000001'
  ),
  'coorganizer must receive competition assignment invalidations'
);
reset role;
select pg_temp.w4_actor('c4010000-0000-4000-8000-000000000007');
set role authenticated;
select pg_temp.w4_assert(
  not exists (
    select 1 from public.pachanga_referee_invalidations invalidations
    where invalidations.entity_type = 'referee_assignment'
      and invalidations.competition_id = 'c4200000-0000-4000-8000-000000000001'
  ),
  'unrelated user must not receive competition assignment invalidations'
);
reset role;

-- Direct client table writes and immutable evidence mutations stay closed.
select pg_temp.w4_assert(
  not has_table_privilege('authenticated', 'private.pachanga_referee_assignment_terms', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.pachanga_referee_assignment_revisions', 'SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('authenticated', 'public.pachanga_referee_assignments', 'INSERT,UPDATE,DELETE'),
  'clients must not receive direct authority over assignments or terms'
);
select pg_temp.w4_expect_error(
  $$update public.pachanga_referee_assignment_revisions
      set status = 'cancelled'
      where assignment_id = 'd6040000-0000-4000-8000-000000000001'$$,
  'REFEREE_WAVE4_EVIDENCE_IMMUTABLE|REFEREE_IMMUTABLE_HISTORY'
);

-- Existing sport, social and economy authorities must be byte-for-byte intact.
select pg_temp.w4_assert(
  not exists (
    select 1 from w4_invariants before
    where before.digest <> case before.key
      when 'rating' then pg_temp.w4_table_digest('public.pachanga_player_rating_snapshots')
      when 'rewards' then pg_temp.w4_table_digest('public.pachanga_reward_grants')
      when 'player_cosmetics' then pg_temp.w4_table_digest('public.pachanga_player_cosmetic_loadouts')
      when 'team_cosmetics' then pg_temp.w4_table_digest('public.pachanga_team_cosmetic_inventory')
      when 'conduct' then pg_temp.w4_table_digest('private.pachanga_conduct_reports')
      when 'billing' then pg_temp.w4_table_digest('public.pachanga_stripe_webhook_events')
    end
  ),
  'Wave 4 must not modify Rating, Rewards, Cosmetics, Conduct or Billing'
);

select 'WAVE4_DB_REPORT|' || jsonb_build_object(
  'assignmentPrivateBeta', true,
  'competitionGenerated', true,
  'completionIdempotent', true,
  'feeConsentSeparated', true,
  'idempotency', true,
  'invalidationScope', true,
  'legacyWriteClosed', true,
  'oneMainReferee', true,
  'participantTermsPrivate', true,
  'r4cAuthorityIntact', true,
  'r4dReconfirmation', true,
  'r5AssignmentEvidence', true,
  'recurringAvailabilityEnforced', true,
  'replacementSafe', true,
  'statisticsRebuildable', true,
  'termsNegotiationPrivate', true,
  'invariants', 'IDENTICAL'
)::text;
