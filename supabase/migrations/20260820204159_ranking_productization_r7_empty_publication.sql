-- Ranking Productization V1 / R7.
-- A published pilot remains canonical even before its first eligible player.

set lock_timeout = '5s';
set statement_timeout = '5min';

do $migration$
declare
  definition text;
  anchor text := $anchor$
  group by entries.season_id, entries.province_code;

  select private.pachanga_ranking_json_checksum_v1(coalesce(jsonb_agg(jsonb_build_object(
$anchor$;
  replacement text := $replacement$
  group by entries.season_id, entries.province_code;

  insert into public.pachanga_provincial_ranking_publications(
    season_id, province_code, published_revision, rebuild_id,
    publication_checksum, entry_count, ranked_count
  )
  select selected_rebuild.season_id,
    territories.province_code,
    selected_rebuild.rebuild_revision,
    target_rebuild_id,
    private.pachanga_ranking_json_checksum_v1('[]'::jsonb),
    0,
    0
  from private.pachanga_ranking_season_territories territories
  where territories.season_id = selected_rebuild.season_id
    and territories.product_enabled
    and not exists (
      select 1
      from public.pachanga_provincial_ranking_publications publications
      where publications.season_id = selected_rebuild.season_id
        and publications.province_code = territories.province_code
    )
  order by territories.province_code;

  select private.pachanga_ranking_json_checksum_v1(coalesce(jsonb_agg(jsonb_build_object(
$replacement$;
begin
  select pg_get_functiondef(
    'private.pachanga_publish_provincial_ranking_v1(uuid,bigint,text,uuid,uuid,text)'::regprocedure
  ) into definition;
  if strpos(definition, anchor) = 0 then
    raise exception 'Canonical ranking publication anchor not found';
  end if;
  definition := replace(definition, anchor, replacement);
  execute definition;
end;
$migration$;

do $migration$
begin
  if strpos(pg_get_functiondef(
    'private.pachanga_publish_provincial_ranking_v1(uuid,bigint,text,uuid,uuid,text)'::regprocedure
  ), 'pachanga_ranking_season_territories territories') = 0 then
    raise exception 'Empty territorial ranking publication support was not installed';
  end if;
  if has_function_privilege(
    'authenticated',
    'private.pachanga_publish_provincial_ranking_v1(uuid,bigint,text,uuid,uuid,text)',
    'EXECUTE'
  ) then
    raise exception 'Private ranking publisher became client executable';
  end if;
end;
$migration$;

comment on function private.pachanga_publish_provincial_ranking_v1(
  uuid, bigint, text, uuid, uuid, text
) is 'Publishes one canonical row per enabled province, including an empty but valid pilot.';

reset lock_timeout;
reset statement_timeout;
