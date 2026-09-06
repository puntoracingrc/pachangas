-- Display names are labels, not unique identifiers. Keep existing longer names
-- intact; apply the new bound when a name is first saved or actually changed.
create or replace function private.pachanga_social_display_name_limit_v1()
returns trigger language plpgsql security invoker set search_path=pg_catalog as $$
begin
  if tg_op = 'UPDATE' then
    if new.display_name is not distinct from old.display_name then return new; end if;
  end if;
  new.display_name := trim(new.display_name);
  if new.display_name is null or char_length(new.display_name) not between 1 and 32 then
    raise exception 'DISPLAY_NAME_LENGTH_INVALID' using errcode='22023';
  end if;
  return new;
end;
$$;
revoke all on function private.pachanga_social_display_name_limit_v1() from public,anon,authenticated;

create trigger pachanga_social_display_name_limit_v1
before insert or update of display_name on public.pachanga_social_player_profiles_v1
for each row execute function private.pachanga_social_display_name_limit_v1();
