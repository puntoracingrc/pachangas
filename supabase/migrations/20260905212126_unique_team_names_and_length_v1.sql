-- Keep Team identity compact and globally unambiguous across every writer.

set lock_timeout = '5s';
set statement_timeout = '120s';

do $$
begin
  if exists (
    select 1
    from public.pachanga_groups groups
    where char_length(regexp_replace(btrim(groups.name), '[[:space:]]+', ' ', 'g')) not between 2 and 32
  ) then
    raise exception 'TEAM_NAME_LENGTH_MIGRATION_BLOCKED';
  end if;

  if exists (
    select 1
    from public.pachanga_groups groups
    group by translate(
      lower(regexp_replace(btrim(groups.name), '[[:space:]]+', ' ', 'g')),
      'áéíóúüñ',
      'aeiouun'
    )
    having count(*) > 1
  ) then
    raise exception 'TEAM_NAME_DUPLICATES_MIGRATION_BLOCKED';
  end if;
end;
$$;

create or replace function private.pachanga_normalize_team_name_v1()
returns trigger
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
begin
  new.name := regexp_replace(btrim(coalesce(new.name, '')), '[[:space:]]+', ' ', 'g');
  if char_length(new.name) < 2 then
    raise exception 'TEAM_NAME_REQUIRED' using errcode = '22023';
  end if;
  if char_length(new.name) > 32 then
    raise exception 'TEAM_NAME_TOO_LONG' using errcode = '22023';
  end if;
  return new;
end;
$$;

drop trigger if exists pachanga_groups_normalize_team_name_v1 on public.pachanga_groups;
create trigger pachanga_groups_normalize_team_name_v1
before insert or update of name on public.pachanga_groups
for each row execute function private.pachanga_normalize_team_name_v1();

alter table public.pachanga_groups
  drop constraint if exists pachanga_groups_name_canonical_length_check,
  add constraint pachanga_groups_name_canonical_length_check
    check (
      char_length(regexp_replace(btrim(name), '[[:space:]]+', ' ', 'g')) between 2 and 32
    );

create unique index if not exists pachanga_groups_name_unique_v1_idx
  on public.pachanga_groups (
    translate(
      lower(regexp_replace(btrim(name), '[[:space:]]+', ' ', 'g')),
      'áéíóúüñ',
      'aeiouun'
    )
  );

revoke all on function private.pachanga_normalize_team_name_v1() from public, anon, authenticated;
grant execute on function private.pachanga_normalize_team_name_v1() to service_role;

comment on function private.pachanga_normalize_team_name_v1() is
  'Canonicalizes Team names and enforces the 2-32 character product contract for every write path.';
comment on index public.pachanga_groups_name_unique_v1_idx is
  'Global Team-name uniqueness ignoring case, repeated whitespace and common Spanish accents.';
