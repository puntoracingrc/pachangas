-- R5 hotfix: an appeal reduction must preserve units already served.

create or replace function private.pachanga_competition_sanction_revision_preserve_service_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare previous_row public.pachanga_competition_sanction_revisions%rowtype;
declare served_units integer;
begin
  if new.previous_revision_id is null
     or coalesce(new.decision_factors ->> 'appealOutcome', '') <> 'modified' then
    return new;
  end if;

  select * into previous_row
  from public.pachanga_competition_sanction_revisions revisions
  where revisions.id = new.previous_revision_id;
  if not found then
    raise exception 'DISCIPLINE_PREVIOUS_SANCTION_REVISION_NOT_FOUND' using errcode = 'P0002';
  end if;

  served_units := greatest(
    coalesce(previous_row.total_units, 0) - coalesce(previous_row.remaining_units, 0),
    0
  );
  new.remaining_units := greatest(coalesce(new.total_units, 0) - served_units, 0);
  new.status := case when new.remaining_units = 0 then 'served' else 'active' end;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_sanction_revision_preserve_service_v1()
  from public, anon, authenticated;

drop trigger if exists preserve_pachanga_sanction_service_on_appeal_v1
  on public.pachanga_competition_sanction_revisions;
create trigger preserve_pachanga_sanction_service_on_appeal_v1
before insert on public.pachanga_competition_sanction_revisions
for each row execute function private.pachanga_competition_sanction_revision_preserve_service_v1();

create or replace function private.pachanga_competition_sanction_align_current_revision_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare revision_row public.pachanga_competition_sanction_revisions%rowtype;
begin
  if new.current_revision_id is null
     or new.current_revision_id is not distinct from old.current_revision_id then
    return new;
  end if;

  select * into revision_row
  from public.pachanga_competition_sanction_revisions revisions
  where revisions.id = new.current_revision_id
    and revisions.sanction_id = new.id;
  if not found then
    raise exception 'DISCIPLINE_CURRENT_SANCTION_REVISION_NOT_FOUND' using errcode = 'P0002';
  end if;

  new.status := revision_row.status;
  new.sanction_outcome := revision_row.sanction_outcome;
  new.unit_type := revision_row.unit_type;
  new.total_units := revision_row.total_units;
  new.remaining_units := revision_row.remaining_units;
  return new;
end;
$$;

revoke all on function private.pachanga_competition_sanction_align_current_revision_v1()
  from public, anon, authenticated;

drop trigger if exists align_pachanga_sanction_current_revision_v1
  on public.pachanga_competition_sanctions;
create trigger align_pachanga_sanction_current_revision_v1
before update of current_revision_id on public.pachanga_competition_sanctions
for each row execute function private.pachanga_competition_sanction_align_current_revision_v1();

comment on function private.pachanga_competition_sanction_revision_preserve_service_v1() is
  'Preserves net service when an appeal lowers total sanction units.';
comment on function private.pachanga_competition_sanction_align_current_revision_v1() is
  'Keeps the canonical sanction row aligned with its immutable current revision.';
