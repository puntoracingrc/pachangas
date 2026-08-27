\set ON_ERROR_STOP on

set lock_timeout = '5s';
set statement_timeout = '180s';

create temporary table r6a_scale_timing(
  started_at timestamptz not null,
  inserted_at timestamptz,
  plan_lookup_ms numeric,
  revision_lookup_ms numeric,
  placement_lookup_ms numeric,
  audit_lookup_ms numeric
);
insert into r6a_scale_timing(started_at) values (clock_timestamp());

begin;

insert into public.pachanga_competition_stages(
  id, edition_id, name, stage_type, stage_order, optional_stage,
  status, rule_revision_id, revision, created_by
)
select
  md5('r6a-scale-stage-' || item)::uuid,
  editions.id,
  'R6A Scale Stage ' || item,
  'GROUP_STAGE',
  1000 + item,
  false,
  'draft',
  editions.rule_revision_id,
  1,
  '63010000-0000-4000-8000-000000000001'::uuid
from generate_series(1, 10000) item
cross join lateral (
  select editions.id, editions.rule_revision_id
  from public.pachanga_competition_editions editions
  join public.pachanga_competitions competitions on competitions.id=editions.competition_id
  where competitions.slug='r6a-concurrency-fixture'
) editions;

insert into public.pachanga_competition_draw_plans(
  id, competition_id, edition_id, stage_id, target_type, mode, status,
  participant_freeze_id, rule_revision_id, group_count, qualifiers_per_group,
  revision, created_by
)
select
  md5('r6a-scale-plan-' || item)::uuid,
  competitions.id,
  editions.id,
  md5('r6a-scale-stage-' || item)::uuid,
  'GROUP_ASSIGNMENT',
  case item % 5
    when 0 then 'PURE_RANDOM'
    when 1 then 'SEEDED_POTS'
    when 2 then 'CONSTRAINT_OPTIMIZED'
    when 3 then 'MANUAL_ASSISTED'
    else 'HYBRID'
  end,
  'generated',
  freezes.id,
  editions.rule_revision_id,
  4,
  2,
  1,
  '63010000-0000-4000-8000-000000000001'::uuid
from generate_series(1, 10000) item
cross join lateral (
  select competitions.id
  from public.pachanga_competitions competitions
  where competitions.slug='r6a-concurrency-fixture'
) competitions
cross join lateral (
  select editions.id, editions.rule_revision_id
  from public.pachanga_competition_editions editions
  where editions.competition_id=competitions.id
) editions
cross join lateral (
  select freezes.id
  from public.pachanga_competition_participant_freezes freezes
  where freezes.competition_id=competitions.id
  order by freezes.server_sequence desc, freezes.id desc limit 1
) freezes;

insert into public.pachanga_competition_draw_revisions(
  id, draw_plan_id, version, mode, algorithm_version, seed_mode, seed,
  seed_revealed, input_checksum, participant_checksum, pot_checksum,
  constraint_checksum, manual_lock_checksum, result_checksum,
  validation_status, quality_score, input_snapshot, pot_snapshot,
  constraint_snapshot, manual_lock_snapshot, validation_snapshot,
  supersedes_revision_id, generated_by
)
select
  md5('r6a-scale-revision-' || item || '-' || version)::uuid,
  md5('r6a-scale-plan-' || item)::uuid,
  version,
  case item % 5
    when 0 then 'PURE_RANDOM'
    when 1 then 'SEEDED_POTS'
    when 2 then 'CONSTRAINT_OPTIMIZED'
    when 3 then 'MANUAL_ASSISTED'
    else 'HYBRID'
  end,
  'tournament-draw-v1',
  'CUSTOM_PUBLIC_SEED',
  'R6A-SCALE-' || item || '-' || version,
  false,
  encode(digest('input-' || item || '-' || version, 'sha256'), 'hex'),
  encode(digest('participants-' || item, 'sha256'), 'hex'),
  encode(digest('pots-' || item, 'sha256'), 'hex'),
  encode(digest('constraints-' || item, 'sha256'), 'hex'),
  encode(digest('locks-' || item, 'sha256'), 'hex'),
  encode(digest('result-' || item || '-' || version, 'sha256'), 'hex'),
  case when version=2 then 'VALID' else 'PENDING' end,
  90,
  jsonb_build_object('scalePlan', item, 'version', version),
  '[]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  jsonb_build_object('scale', true),
  case when version=2 then md5('r6a-scale-revision-' || item || '-1')::uuid end,
  '63010000-0000-4000-8000-000000000001'::uuid
from generate_series(1, 10000) item
cross join generate_series(1, 2) version
order by version, item;

update public.pachanga_competition_draw_plans plans set
  current_revision_id=md5('r6a-scale-revision-' || item || '-2')::uuid
from generate_series(1, 10000) item
where plans.id=md5('r6a-scale-plan-' || item)::uuid;

insert into public.pachanga_competition_draw_placements(
  draw_revision_id, entry_id, group_number, slot_number, pot_number, placement_source
)
select
  md5('r6a-scale-revision-' || item || '-' || version)::uuid,
  entries.entry_id,
  entry_number,
  1,
  entry_number,
  case when version=1 then 'ENGINE' else 'HYBRID_FILL' end
from generate_series(1, 10000) item
cross join generate_series(1, 2) version
cross join lateral (
  select entries.id entry_id,
    row_number() over(order by entries.team_id)::smallint entry_number
  from public.pachanga_competition_entries entries
  join public.pachanga_competitions competitions on competitions.id=entries.competition_id
  where competitions.slug='r6a-concurrency-fixture' and entries.status='accepted'
  order by entries.team_id
  limit 5
) entries;

insert into public.pachanga_competition_draw_constraints(
  draw_plan_id, constraint_type, strength, weight, scope, parameters,
  reason, public_attribution, status, revision, created_by
)
select
  md5('r6a-scale-plan-' || item)::uuid,
  case constraint_number when 1 then 'GROUP_SIZE' else 'TEAM_LEVEL_BALANCE' end,
  case constraint_number when 1 then 'HARD' else 'SOFT' end,
  case constraint_number when 1 then 100 else 2 end,
  'DRAW',
  jsonb_build_object('maxGap', case constraint_number when 1 then 1 else 12 end),
  'R6A scale constraint ' || constraint_number,
  true,
  'active',
  1,
  '63010000-0000-4000-8000-000000000001'::uuid
from generate_series(1, 10000) item
cross join generate_series(1, 2) constraint_number;

insert into public.pachanga_competition_draw_manual_locks(
  draw_plan_id, lock_type, entry_id, target_group_number, target_slot,
  status, reason, revision, created_by
)
select
  md5('r6a-scale-plan-' || item)::uuid,
  'ENTRY_TO_GROUP',
  entries.entry_id,
  lock_number,
  1,
  'active',
  'R6A scale manual lock ' || lock_number,
  1,
  '63010000-0000-4000-8000-000000000001'::uuid
from generate_series(1, 10000) item
cross join generate_series(1, 2) lock_number
cross join lateral (
  select entries.id entry_id
  from public.pachanga_competition_entries entries
  join public.pachanga_competitions competitions on competitions.id=entries.competition_id
  where competitions.slug='r6a-concurrency-fixture' and entries.status='accepted'
  order by entries.team_id
  offset lock_number - 1 limit 1
) entries;

update r6a_scale_timing set inserted_at=clock_timestamp();

do $$
declare started timestamptz;
declare sample integer;
declare sink jsonb;
begin
  started := clock_timestamp();
  for sample in 1..25 loop
    select to_jsonb(plans) into sink
    from public.pachanga_competition_draw_plans plans
    where plans.competition_id=(select id from public.pachanga_competitions where slug='r6a-concurrency-fixture')
    order by plans.server_sequence desc, plans.id desc limit 1;
  end loop;
  update r6a_scale_timing set plan_lookup_ms=extract(epoch from (clock_timestamp()-started))*1000/25;

  started := clock_timestamp();
  for sample in 1..25 loop
    select jsonb_agg(to_jsonb(revisions) order by revisions.server_sequence desc, revisions.id desc) into sink
    from public.pachanga_competition_draw_revisions revisions
    where revisions.draw_plan_id=md5('r6a-scale-plan-5000')::uuid;
  end loop;
  update r6a_scale_timing set revision_lookup_ms=extract(epoch from (clock_timestamp()-started))*1000/25;

  started := clock_timestamp();
  for sample in 1..25 loop
    select jsonb_agg(to_jsonb(placements)) into sink
    from public.pachanga_competition_draw_placements placements
    where placements.draw_revision_id=md5('r6a-scale-revision-5000-2')::uuid;
  end loop;
  update r6a_scale_timing set placement_lookup_ms=extract(epoch from (clock_timestamp()-started))*1000/25;

  started := clock_timestamp();
  for sample in 1..25 loop
    select jsonb_build_object(
      'plan', to_jsonb(plans),
      'revision', to_jsonb(revisions),
      'placements', (select jsonb_agg(to_jsonb(placements))
        from public.pachanga_competition_draw_placements placements
        where placements.draw_revision_id=revisions.id),
      'constraints', (select jsonb_agg(to_jsonb(constraints))
        from public.pachanga_competition_draw_constraints constraints
        where constraints.draw_plan_id=plans.id and constraints.status='active'),
      'locks', (select jsonb_agg(to_jsonb(locks))
        from public.pachanga_competition_draw_manual_locks locks
        where locks.draw_plan_id=plans.id and locks.status='active')
    ) into sink
    from public.pachanga_competition_draw_plans plans
    join public.pachanga_competition_draw_revisions revisions on revisions.id=plans.current_revision_id
    where plans.id=md5('r6a-scale-plan-5000')::uuid;
  end loop;
  update r6a_scale_timing set audit_lookup_ms=extract(epoch from (clock_timestamp()-started))*1000/25;
end;
$$;

select 'R6A_SCALE_REPORT|' || jsonb_build_object(
  'plans', (select count(*) from public.pachanga_competition_draw_plans
    where id in (select md5('r6a-scale-plan-' || item)::uuid from generate_series(1,10000) item)),
  'revisions', (select count(*) from public.pachanga_competition_draw_revisions
    where draw_plan_id in (select md5('r6a-scale-plan-' || item)::uuid from generate_series(1,10000) item)),
  'placements', (select count(*) from public.pachanga_competition_draw_placements
    where draw_revision_id in (
      select md5('r6a-scale-revision-' || item || '-' || version)::uuid
      from generate_series(1,10000) item cross join generate_series(1,2) version
    )),
  'constraints', (select count(*) from public.pachanga_competition_draw_constraints
    where draw_plan_id in (select md5('r6a-scale-plan-' || item)::uuid from generate_series(1,10000) item)),
  'manualLocks', (select count(*) from public.pachanga_competition_draw_manual_locks
    where draw_plan_id in (select md5('r6a-scale-plan-' || item)::uuid from generate_series(1,10000) item)),
  'durationMs', (select round(extract(epoch from (inserted_at-started_at))*1000,3) from r6a_scale_timing),
  'planLookupMs', (select round(plan_lookup_ms,3) from r6a_scale_timing),
  'revisionLookupMs', (select round(revision_lookup_ms,3) from r6a_scale_timing),
  'placementLookupMs', (select round(placement_lookup_ms,3) from r6a_scale_timing),
  'auditLookupMs', (select round(audit_lookup_ms,3) from r6a_scale_timing),
  'indexBytes', (
    select sum(pg_indexes_size(table_name::regclass))
    from unnest(array[
      'public.pachanga_competition_draw_plans',
      'public.pachanga_competition_draw_revisions',
      'public.pachanga_competition_draw_placements',
      'public.pachanga_competition_draw_constraints',
      'public.pachanga_competition_draw_manual_locks'
    ]) as table_names(table_name)
  )
)::text;

rollback;

select 'R6A_SCALE_ROLLBACK|' || jsonb_build_object(
  'plans', (select count(*) from public.pachanga_competition_draw_plans
    where id in (select md5('r6a-scale-plan-' || item)::uuid from generate_series(1,10000) item)),
  'revisions', (select count(*) from public.pachanga_competition_draw_revisions
    where id in (
      select md5('r6a-scale-revision-' || item || '-' || version)::uuid
      from generate_series(1,10000) item cross join generate_series(1,2) version
    )),
  'stages', (select count(*) from public.pachanga_competition_stages
    where id in (select md5('r6a-scale-stage-' || item)::uuid from generate_series(1,10000) item))
)::text;
