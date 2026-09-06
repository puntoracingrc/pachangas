-- Run only in an isolated QA database after the display-name migration.
\set ON_ERROR_STOP on
begin;
create function pg_temp.assert_name(ok boolean) returns void language plpgsql as $$
begin if not coalesce(ok,false) then raise exception 'Display name assertion failed'; end if; end;
$$;
-- Use a temporary table with the real trigger, without touching real profiles.
create temp table display_name_qa (id integer primary key, display_name text, note text);
insert into display_name_qa values (1,repeat('A',60),'legacy');
create trigger check_name before insert or update of display_name on display_name_qa
for each row execute function private.pachanga_social_display_name_limit_v1();
insert into display_name_qa values (2,'  Alberto I  ',null),(3,'Alberto I',null),(4,repeat('M',32),null);
select pg_temp.assert_name((select count(*)=2 from display_name_qa where display_name='Alberto I'));
update display_name_qa set display_name='Alberto M' where id=3;
select pg_temp.assert_name((select display_name='Alberto M' from display_name_qa where id=3));
update display_name_qa set note='unchanged name',display_name=display_name where id=1;
select pg_temp.assert_name((select length(display_name)=60 from display_name_qa where id=1));
do $$
declare invalid_name text;
begin
 foreach invalid_name in array array[repeat('X',33),'   ',null] loop
  begin
   insert into display_name_qa values (5,invalid_name,null);
   raise exception 'Invalid name unexpectedly accepted';
  exception when invalid_parameter_value then
   if sqlerrm <> 'DISPLAY_NAME_LENGTH_INVALID' then raise; end if;
  end;
 end loop;
end;
$$;
rollback;
