\set ON_ERROR_STOP on

do $$
declare sanction_row public.pachanga_competition_sanctions%rowtype;
declare previous_row public.pachanga_competition_sanction_revisions%rowtype;
declare served_revision_id uuid;
declare modified_revision_id uuid;
begin
  select * into sanction_row
  from public.pachanga_competition_sanctions sanctions
  where sanctions.player_profile_id = 'c4300000-0000-4000-8000-000000000003'
  order by sanctions.server_sequence desc, sanctions.id desc
  limit 1;
  if not found then raise exception 'R5_APPEAL_SERVICE_FIXTURE_SANCTION_MISSING'; end if;

  select * into previous_row
  from public.pachanga_competition_sanction_revisions revisions
  where revisions.id = sanction_row.current_revision_id;

  insert into public.pachanga_competition_sanction_revisions(
    sanction_id, version, previous_revision_id, status, sanction_outcome,
    unit_type, total_units, remaining_units, public_reason_category,
    public_summary, rule_article, decision_factors,
    decision_reason_private, operation_id, created_by
  ) values (
    sanction_row.id, sanction_row.revision + 1, previous_row.id,
    'active', 'FIXED_SANCTION', 'MATCHES', 2, 1, 'dismissal',
    'Dos partidos, uno ya cumplido', 'R5.REGRESSION.SERVICE',
    '{"regression":"served_before_appeal"}'::jsonb,
    'Estado previo determinista para la regresión.',
    'c5000000-0000-4000-8000-000000000091',
    'c4010000-0000-4000-8000-000000000002'
  ) returning id into served_revision_id;

  update public.pachanga_competition_sanctions set
    current_revision_id = served_revision_id,
    revision = sanction_row.revision + 1
  where id = sanction_row.id;

  insert into public.pachanga_competition_sanction_revisions(
    sanction_id, version, previous_revision_id, status, sanction_outcome,
    unit_type, total_units, remaining_units, public_reason_category,
    public_summary, rule_article, decision_factors,
    decision_reason_private, operation_id, created_by
  ) values (
    sanction_row.id, sanction_row.revision + 2, served_revision_id,
    'active', 'FIXED_SANCTION', 'MATCHES', 1, 1, 'dismissal',
    'Reducida a un partido', 'R5.REGRESSION.APPEAL',
    '{"appealOutcome":"modified"}'::jsonb,
    'La apelación reduce el total al ya cumplido.',
    'c5000000-0000-4000-8000-000000000092',
    'c4010000-0000-4000-8000-000000000002'
  ) returning id into modified_revision_id;

  update public.pachanga_competition_sanctions set
    current_revision_id = modified_revision_id,
    revision = sanction_row.revision + 2
  where id = sanction_row.id;

  if not exists (
    select 1
    from public.pachanga_competition_sanction_revisions revisions
    where revisions.id = modified_revision_id
      and revisions.status = 'served'
      and revisions.total_units = 1
      and revisions.remaining_units = 0
  ) then raise exception 'R5_APPEAL_SERVICE_REVISION_REGRESSION'; end if;
  if not exists (
    select 1
    from public.pachanga_competition_sanctions sanctions
    where sanctions.id = sanction_row.id
      and sanctions.status = 'served'
      and sanctions.total_units = 1
      and sanctions.remaining_units = 0
      and sanctions.current_revision_id = modified_revision_id
  ) then raise exception 'R5_APPEAL_SERVICE_CANONICAL_REGRESSION'; end if;
end;
$$;

select 'R5_APPEAL_SERVICE_REGRESSION|PASS';
