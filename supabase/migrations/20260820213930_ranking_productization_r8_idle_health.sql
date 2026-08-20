-- Ranking Productization V1 / R8.
-- An open season is stale only when its own queue still has work to process.

set lock_timeout = '5s';
set statement_timeout = '5min';

do $migration$
declare
  definition text;
  anchor text := $anchor$
    case when active_season.id is not null and active_season.status = 'open'
      and (
        active_season.last_refresh_at is null
        or active_season.last_refresh_at < current_timestamp - interval '15 minutes'
      ) then 'RANKING_REFRESH_STALE' end,
$anchor$;
  replacement text := $replacement$
    case when active_season.id is not null and active_season.status = 'open'
      and exists (
        select 1
        from private.pachanga_ranking_refresh_queue pending_queue
        where pending_queue.season_id = active_season.id
          and pending_queue.state = 'queued'
      )
      and (
        active_season.last_refresh_at is null
        or active_season.last_refresh_at < current_timestamp - interval '15 minutes'
      ) then 'RANKING_REFRESH_STALE' end,
$replacement$;
begin
  select pg_get_functiondef(
    'private.pachanga_ranking_operational_health_v1()'::regprocedure
  ) into definition;
  if strpos(definition, anchor) = 0 then
    raise exception 'Ranking idle-health anchor not found';
  end if;
  definition := replace(definition, anchor, replacement);
  execute definition;
end;
$migration$;

do $migration$
declare
  definition text;
begin
  select pg_get_functiondef(
    'private.pachanga_ranking_operational_health_v1()'::regprocedure
  ) into definition;
  if strpos(definition, 'pending_queue.season_id = active_season.id') = 0
    or strpos(definition, 'pending_queue.state = ''queued''') = 0 then
    raise exception 'Ranking idle-health protection was not installed';
  end if;
  if has_function_privilege(
    'authenticated',
    'private.pachanga_ranking_operational_health_v1()',
    'EXECUTE'
  ) then
    raise exception 'Private ranking health function became client executable';
  end if;
end;
$migration$;

comment on function private.pachanga_ranking_operational_health_v1()
  is 'Reports stale refresh only when the active open season has queued work; an idle canonical publication remains healthy.';

reset lock_timeout;
reset statement_timeout;
