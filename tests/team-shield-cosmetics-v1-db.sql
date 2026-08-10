\set ON_ERROR_STOP on
\set VERBOSITY verbose

begin;

grant usage on schema auth to authenticated, service_role;
grant execute on function auth.uid() to authenticated, service_role;
grant execute on function auth.jwt() to authenticated, service_role;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if not coalesce(condition, false) then raise exception '%', message; end if;
end;
$$;

create or replace function pg_temp.shield_config(target_border text)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'schemaVersion', 1,
    'shapeKey', 'team.shield.shape.hex_iq',
    'backgroundKey', 'team.shield.background.duotone',
    'patternKey', 'team.shield.pattern.diagonal',
    'primaryColorKey', 'team.shield.color.midnight',
    'secondaryColorKey', 'team.shield.color.cyan',
    'primarySymbolKey', 'team.shield.symbol.ball_iq',
    'secondarySymbolKey', null,
    'borderKey', target_border,
    'topOrnamentKey', null,
    'sideOrnamentKey', null,
    'bottomOrnamentKey', null,
    'initials', 'TSV1',
    'foundationYear', '2026',
    'effectKey', null,
    'primarySymbolScale', 1,
    'primarySymbolRotation', 0
  );
$$;

select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_cosmetic_catalog
   where cosmetic_key in (
     'team.shield.symbol.ball_premium',
     'team.shield.border.copper',
     'team.shield.border.silver',
     'team.shield.border.gold'
   )
     and active
     and owner_scope = 'team') = 4,
  'The Premium RC promotes exactly the ball and Copper Silver Gold team cosmetics'
);
select pg_temp.assert_true(
  (select slot = 'primary_symbol'
          and render_contract ->> 'premiumPipeline' = 'multiview-8-v1'
   from public.pachanga_cosmetic_catalog
   where cosmetic_key = 'team.shield.symbol.ball_premium'),
  'The Premium Ball uses the canonical primary symbol slot and multiview contract'
);
select pg_temp.assert_true(
  (select count(*)
   from public.pachanga_cosmetic_catalog
   where cosmetic_key in (
     'team.shield.border.copper',
     'team.shield.border.silver',
     'team.shield.border.gold'
   )
     and slot = 'border'
     and render_contract ->> 'premiumBorder' = 'prerender-material-v1') = 3,
  'Copper Silver and Gold use the canonical premium border contract'
);
select pg_temp.assert_true(
  not exists (
    select 1
    from public.pachanga_reward_pool_catalog
    where cosmetic_key in (
      'team.shield.symbol.ball_premium',
      'team.shield.border.copper',
      'team.shield.border.silver',
      'team.shield.border.gold'
    )
  ),
  'The Premium RC does not activate any reward mapping'
);

insert into auth.users(id, email) values
  ('e5100000-0000-0000-0000-000000000001', 'shield-owner@example.test'),
  ('e5100000-0000-0000-0000-000000000002', 'shield-admin@example.test'),
  ('e5100000-0000-0000-0000-000000000003', 'shield-player@example.test'),
  ('e5100000-0000-0000-0000-000000000004', 'shield-late-admin@example.test'),
  ('e5100000-0000-0000-0000-000000000005', 'shield-outsider@example.test');

insert into public.pachanga_groups(id, owner_id, name, team_code, payload) values (
  'e5200000-0000-0000-0000-000000000001',
  'e5100000-0000-0000-0000-000000000001',
  'Team Shield V1', 'SHIELDV1', '{"players":[],"matches":[],"sportingMarker":"unchanged"}'
);

insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('e5200000-0000-0000-0000-000000000001', 'e5100000-0000-0000-0000-000000000001', 'owner', 'Shield Owner'),
  ('e5200000-0000-0000-0000-000000000001', 'e5100000-0000-0000-0000-000000000002', 'admin', 'Shield Admin'),
  ('e5200000-0000-0000-0000-000000000001', 'e5100000-0000-0000-0000-000000000003', 'player', 'Shield Player');

update private.pachanga_team_cosmetic_settings
set team_cosmetics_enabled = true,
    team_cosmetic_rewards_enabled = false,
    updated_at = clock_timestamp()
where singleton;

create temporary table sporting_before as
select md5(payload::text) as payload_hash
from public.pachanga_groups
where id = 'e5200000-0000-0000-0000-000000000001';

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.pachanga_team_shield_loadouts', 'INSERT')
  and not has_table_privilege('authenticated', 'public.pachanga_team_shield_loadouts', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.pachanga_team_cosmetic_inventory', 'INSERT')
  and not has_table_privilege('authenticated', 'public.pachanga_team_cosmetic_seen', 'INSERT'),
  'Authenticated clients must not write shield or inventory tables directly'
);
select pg_temp.assert_true(
  has_function_privilege('authenticated', 'public.save_pachanga_team_shield_loadout_v1(uuid,jsonb,uuid,bigint,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.mark_pachanga_team_cosmetics_seen_v1(uuid,text[],uuid,bigint,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.grant_pachanga_team_cosmetic_v1(uuid,text,uuid,bigint,text,jsonb,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.save_pachanga_team_crest_draft_v1(uuid,jsonb,uuid,bigint,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.publish_pachanga_team_crest_v1(uuid,uuid,bigint,jsonb)', 'EXECUTE'),
  'Clients may send only final V1 shield intentions and legacy visual writes stay closed'
);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select pg_temp.assert_true(
  (public.grant_pachanga_team_cosmetic_v1(
    'e5200000-0000-0000-0000-000000000001',
    'team.shield.border.copper',
    'e5300000-0000-0000-0000-000000000001', 0,
    'staging_fixture', '{"fixture":"sql"}', '{"surface":"db-test","email":"must-not-persist"}'
  ) ->> 'confirmedRevision') = '1',
  'The first controlled grant increments the authoritative team revision'
);
select pg_temp.assert_true(
  public.grant_pachanga_team_cosmetic_v1(
    'e5200000-0000-0000-0000-000000000001',
    'team.shield.border.copper',
    'e5300000-0000-0000-0000-000000000001', 0,
    'staging_fixture', '{"fixture":"sql"}', '{"surface":"db-test","email":"must-not-persist"}'
  ) = (select response from public.pachanga_team_shield_operation_receipts
       where operation_id = 'e5300000-0000-0000-0000-000000000001'),
  'Replaying one grant returns its exact original receipt'
);
select pg_temp.assert_true(
  (public.grant_pachanga_team_cosmetic_v1(
    'e5200000-0000-0000-0000-000000000001',
    'team.shield.border.copper',
    'e5300000-0000-0000-0000-000000000002', 1,
    'staging_fixture', '{}', '{}'
  ) ->> 'alreadyOwned')::boolean
  and (select revision from public.pachanga_team_shield_state
       where group_id = 'e5200000-0000-0000-0000-000000000001') = 1,
  'A duplicate controlled grant creates no currency and no extra team revision'
);

reset role;

select pg_temp.assert_true(
  (select count(*) from public.pachanga_user_notifications
   where kind = 'team_cosmetic_reward'
     and recipient_user_id in (
       'e5100000-0000-0000-0000-000000000001',
       'e5100000-0000-0000-0000-000000000002'
     )) = 2,
  'A new team cosmetic notifies every currently eligible owner/admin exactly once'
);
select pg_temp.assert_true(
  (select client_metadata ? 'email' from public.pachanga_team_shield_operation_receipts
   where operation_id = 'e5300000-0000-0000-0000-000000000001') = false,
  'Receipt metadata keeps the no-PII allowlist'
);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e5100000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select pg_temp.assert_true(
  (public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001') ->> 'canManage')::boolean
  and (public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001') ->> 'unseenCount')::integer = 1,
  'The owner sees the private inventory NEW state'
);

create temporary table saved_team_shield as
select public.save_pachanga_team_shield_loadout_v1(
  'e5200000-0000-0000-0000-000000000001',
  pg_temp.shield_config('team.shield.border.copper'),
  'e5300000-0000-0000-0000-000000000003', 1,
  '{"clientVersion":"2.0.0+sql","displayMode":"browser","surface":"team-identity"}'
) as response;

select pg_temp.assert_true(
  (select response ->> 'confirmedRevision' from saved_team_shield) = '2'
  and (select count(*) from public.pachanga_team_shield_versions
       where group_id = 'e5200000-0000-0000-0000-000000000001') = 1,
  'Saving confirms one immutable version and increments the revision once'
);
select pg_temp.assert_true(
  public.save_pachanga_team_shield_loadout_v1(
    'e5200000-0000-0000-0000-000000000001',
    pg_temp.shield_config('team.shield.border.copper'),
    'e5300000-0000-0000-0000-000000000003', 1, '{}'
  ) = (select response from saved_team_shield),
  'A save replay converges to the exact canonical response'
);

do $$
begin
  perform public.save_pachanga_team_shield_loadout_v1(
    'e5200000-0000-0000-0000-000000000001',
    pg_temp.shield_config('team.shield.border.clean'),
    'e5300000-0000-0000-0000-000000000004', 1, '{}'
  );
  raise exception 'A stale shield revision unexpectedly succeeded';
exception when sqlstate 'PT409' then null;
end;
$$;

select pg_temp.assert_true(
  (public.mark_pachanga_team_cosmetics_seen_v1(
    'e5200000-0000-0000-0000-000000000001',
    array['team.shield.border.copper'],
    'e5300000-0000-0000-0000-000000000005', 0, '{}'
  ) ->> 'markedSeen')::integer = 1,
  'NEW acknowledgement is stored per admin'
);
select pg_temp.assert_true(
  (public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001') ->> 'unseenCount')::integer = 0,
  'The owner no longer sees NEW after acknowledgement'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e5100000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001') ->> 'unseenCount')::integer = 1,
  'One admin acknowledgement must not mark a cosmetic seen for another admin'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e5100000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select pg_temp.assert_true(
  not (public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001') ->> 'canManage')::boolean
  and not exists (
    select 1
    from jsonb_array_elements(public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001') -> 'catalog') item
    where item ->> 'acquiredAt' is not null or (item ->> 'serverSequence')::bigint <> 0
  ),
  'A normal member sees renderable pieces but no private inventory metadata'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_cosmetic_inventory
   where group_id = 'e5200000-0000-0000-0000-000000000001') = 0,
  'A normal member cannot read the team inventory table'
);
do $$
begin
  update public.pachanga_team_shield_loadouts set revision = revision + 1
  where group_id = 'e5200000-0000-0000-0000-000000000001';
  raise exception 'Direct loadout update unexpectedly succeeded';
exception when insufficient_privilege then null;
end;
$$;
do $$
begin
  perform public.save_pachanga_team_shield_loadout_v1(
    'e5200000-0000-0000-0000-000000000001',
    pg_temp.shield_config('team.shield.border.clean'),
    'e5300000-0000-0000-0000-000000000006', 2, '{}'
  );
  raise exception 'A normal member saved the official shield';
exception when raise_exception then
  if sqlerrm = 'A normal member saved the official shield' then raise; end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e5100000-0000-0000-0000-000000000005","role":"authenticated"}', true);
do $$
begin
  perform public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001');
  raise exception 'An outsider read the private team shield snapshot';
exception when raise_exception then
  if sqlerrm = 'An outsider read the private team shield snapshot' then raise; end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e5100000-0000-0000-0000-000000000003","role":"authenticated","is_anonymous":true}', true);
do $$
begin
  perform public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001');
  raise exception 'An anonymous session read the private team shield snapshot';
exception when raise_exception then
  if sqlerrm = 'An anonymous session read the private team shield snapshot' then raise; end if;
end;
$$;
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_shield_state
   where group_id = 'e5200000-0000-0000-0000-000000000001') = 0,
  'Realtime policies reject anonymous authenticated sessions even with a matching user id'
);

reset role;
select pg_sleep(0.01);
insert into public.pachanga_group_members(group_id, user_id, role, display_name) values
  ('e5200000-0000-0000-0000-000000000001', 'e5100000-0000-0000-0000-000000000004', 'admin', 'Late Admin');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"e5100000-0000-0000-0000-000000000004","role":"authenticated"}', true);
select pg_temp.assert_true(
  (public.get_pachanga_team_shield_snapshot_v1('e5200000-0000-0000-0000-000000000001') ->> 'unseenCount')::integer = 0,
  'A newly promoted admin must not inherit historical NEW badges'
);

reset role;
delete from public.pachanga_group_members
where group_id = 'e5200000-0000-0000-0000-000000000001'
  and user_id = 'e5100000-0000-0000-0000-000000000002';
update public.pachanga_groups
set owner_id = 'e5100000-0000-0000-0000-000000000004', name = 'Team Shield Renamed'
where id = 'e5200000-0000-0000-0000-000000000001';

select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_cosmetic_inventory
   where group_id = 'e5200000-0000-0000-0000-000000000001') = 1
  and (select config ->> 'initials' from public.pachanga_team_shield_loadouts
       where group_id = 'e5200000-0000-0000-0000-000000000001') = 'TSV1',
  'Admin removal, owner transfer and group rename preserve team-owned inventory and saved identity'
);
select pg_temp.assert_true(
  not exists (
    select 1 from public.pachanga_team_cosmetic_admin_eligibility
    where group_id = 'e5200000-0000-0000-0000-000000000001'
      and admin_user_id = 'e5100000-0000-0000-0000-000000000002'
  ),
  'Removed admins lose private inventory eligibility'
);

do $$
begin
  update public.pachanga_team_shield_versions set config = config
  where group_id = 'e5200000-0000-0000-0000-000000000001';
  raise exception 'An immutable shield version was updated';
exception when raise_exception then
  if sqlerrm = 'An immutable shield version was updated' then raise; end if;
end;
$$;

select pg_temp.assert_true(
  (select md5(groups.payload::text) = before.payload_hash
   from public.pachanga_groups groups cross join sporting_before before
   where groups.id = 'e5200000-0000-0000-0000-000000000001'),
  'Shield operations must not mutate team sporting payloads'
);
select pg_temp.assert_true(
  (select count(*) from public.pachanga_team_shield_operation_receipts
   where group_id = 'e5200000-0000-0000-0000-000000000001') = 4,
  'Two grants, one save and one seen action retain one receipt each'
);

rollback;
