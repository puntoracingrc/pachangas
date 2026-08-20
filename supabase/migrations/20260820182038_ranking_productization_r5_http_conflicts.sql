-- Ranking Productization V1 R5
--
-- SQLSTATE 40001 represents a retryable serialization failure. Using it for
-- expected-revision conflicts makes the hosted Data API retry a request that
-- can only succeed after the client reloads canonical state. Pachangas uses
-- PT409 for this server-authoritative conflict contract everywhere else.
--
-- R1-R4 have already been exercised in staging, so this additive migration
-- patches only the exact Ranking functions that emitted application conflicts.

set lock_timeout = '5s';
set statement_timeout = '5min';

do $migration$
declare
  target_function regprocedure;
  definition text;
  patched_definition text;
begin
  foreach target_function in array array[
    'private.pachanga_build_season_ranking_candidate_v1(uuid,bigint,uuid,uuid,text)'::regprocedure,
    'private.pachanga_build_player_ranking_candidate_v1(uuid,uuid,bigint,uuid,uuid,text)'::regprocedure,
    'private.pachanga_resolve_ranking_integrity_review_v1(uuid,text,bigint,uuid,uuid,text,text)'::regprocedure,
    'private.pachanga_publish_provincial_ranking_v1(uuid,bigint,text,uuid,uuid,text)'::regprocedure,
    'public.transition_pachanga_ranking_season_v1(uuid,text,bigint,uuid,text)'::regprocedure,
    'public.map_pachanga_ranking_venue_v1(text,text,numeric,bigint,uuid,text,jsonb)'::regprocedure,
    'public.process_pachanga_ranking_refresh_queue_admin_v1(integer,bigint,uuid,text)'::regprocedure,
    'public.set_pachanga_platform_flag_pre_ranking_v1(text,boolean,bigint,uuid,text)'::regprocedure,
    'public.set_pachanga_platform_flag_v1(text,boolean,bigint,uuid,text)'::regprocedure
  ] loop
    definition := pg_get_functiondef(target_function);
    patched_definition := replace(definition, '''40001''', '''PT409''');
    if patched_definition = definition then
      raise exception 'Expected Ranking conflict marker missing from %', target_function;
    end if;
    execute patched_definition;
  end loop;

  foreach target_function in array array[
    'private.pachanga_build_season_ranking_candidate_v1(uuid,bigint,uuid,uuid,text)'::regprocedure,
    'private.pachanga_build_player_ranking_candidate_v1(uuid,uuid,bigint,uuid,uuid,text)'::regprocedure,
    'private.pachanga_resolve_ranking_integrity_review_v1(uuid,text,bigint,uuid,uuid,text,text)'::regprocedure,
    'private.pachanga_publish_provincial_ranking_v1(uuid,bigint,text,uuid,uuid,text)'::regprocedure,
    'public.transition_pachanga_ranking_season_v1(uuid,text,bigint,uuid,text)'::regprocedure,
    'public.map_pachanga_ranking_venue_v1(text,text,numeric,bigint,uuid,text,jsonb)'::regprocedure,
    'public.process_pachanga_ranking_refresh_queue_admin_v1(integer,bigint,uuid,text)'::regprocedure,
    'public.set_pachanga_platform_flag_pre_ranking_v1(text,boolean,bigint,uuid,text)'::regprocedure,
    'public.set_pachanga_platform_flag_v1(text,boolean,bigint,uuid,text)'::regprocedure
  ] loop
    if pg_get_functiondef(target_function) like '%''40001''%' then
      raise exception 'Retryable SQLSTATE remains in %', target_function;
    end if;
  end loop;
end;
$migration$;
