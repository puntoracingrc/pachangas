-- Members may preview every base or unlocked team shield piece.
-- Keep existing membership checks, admin-only metadata/history, and save permissions.
CREATE OR REPLACE FUNCTION public.get_pachanga_team_shield_snapshot_v1_impl(target_group_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
declare
  selected_group public.pachanga_groups%rowtype;
  selected_state public.pachanga_team_shield_state%rowtype;
  selected_loadout public.pachanga_team_shield_loadouts%rowtype;
  selected_eligibility public.pachanga_team_cosmetic_admin_eligibility%rowtype;
  selected_config jsonb;
  equipped_keys text[];
  can_manage boolean;
  unseen_count integer := 0;
begin
  if coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
    and (auth.uid() is null or not public.is_pachanga_group_member(target_group_id)) then
    raise exception 'Group membership required';
  end if;
  select * into selected_group from public.pachanga_groups groups where groups.id = target_group_id;
  if not found then raise exception 'Group not found'; end if;
  select * into selected_state from public.pachanga_team_shield_state states where states.group_id = target_group_id;
  select * into selected_loadout from public.pachanga_team_shield_loadouts loadouts where loadouts.group_id = target_group_id;
  selected_config := coalesce(selected_loadout.config, private.pachanga_default_team_shield_config_v1(selected_group.name));
  equipped_keys := private.pachanga_team_shield_config_keys_v1(selected_config);
  can_manage := coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or public.is_pachanga_group_admin(target_group_id);

  if can_manage and auth.uid() is not null then
    select * into selected_eligibility
    from public.pachanga_team_cosmetic_admin_eligibility eligibility
    where eligibility.group_id = target_group_id and eligibility.admin_user_id = auth.uid();
    select count(*) into unseen_count
    from public.pachanga_team_cosmetic_inventory inventory
    left join public.pachanga_team_cosmetic_seen seen
      on seen.group_id = inventory.group_id
      and seen.cosmetic_key = inventory.cosmetic_key
      and seen.admin_user_id = auth.uid()
    where inventory.group_id = target_group_id
      and inventory.cosmetic_key like 'team.shield.%'
      and inventory.state = 'unlocked'
      and inventory.unlocked_at >= coalesce(selected_eligibility.eligible_since, clock_timestamp())
      and seen.cosmetic_key is null;
  end if;

  return jsonb_build_object(
    'group', jsonb_build_object('groupId', selected_group.id, 'name', selected_group.name),
    'canManage', can_manage,
    'teamCosmeticsEnabled', private.pachanga_team_cosmetics_enabled_v1(),
    'teamCosmeticRewardsEnabled', private.pachanga_team_cosmetic_rewards_enabled_v1(),
    'revision', coalesce(selected_state.revision, 0),
    'confirmedRevision', coalesce(selected_state.revision, 0),
    'seenRevision', case when auth.uid() is null then 0 else coalesce(selected_eligibility.seen_revision, 0) end,
    'serverSequence', coalesce(selected_state.server_sequence, selected_loadout.server_sequence, 0),
    'unseenCount', unseen_count,
    'config', selected_config,
    'defaultConfig', private.pachanga_default_team_shield_config_v1(selected_group.name),
    'history', case when can_manage then coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', versions.id,
        'version', versions.version_number,
        'config', versions.config,
        'serverSequence', versions.server_sequence,
        'createdAt', versions.created_at
      ) order by versions.version_number desc, versions.id desc)
      from (
        select version_rows.*
        from public.pachanga_team_shield_versions version_rows
        where version_rows.group_id = target_group_id
        order by version_rows.version_number desc, version_rows.id desc
        limit 30
      ) versions
    ), '[]'::jsonb) else '[]'::jsonb end,
    'catalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.cosmetic_key,
        'family', catalog.family,
        'slot', catalog.slot,
        'name', catalog.display_name,
        'description', catalog.description,
        'rarity', catalog.rarity,
        'availability', catalog.availability,
        'collection', catalog.collection_key,
        'material', catalog.material_key,
        'render', catalog.render_contract,
        'serverSequence', case when can_manage then coalesce(inventory.server_sequence, 0) else 0 end,
        'acquiredAt', case when can_manage then inventory.unlocked_at else null end,
        'seenAt', case
          when not can_manage then null
          when inventory.unlocked_at is null then null
          when auth.uid() is null then inventory.unlocked_at
          when inventory.unlocked_at < coalesce(selected_eligibility.eligible_since, clock_timestamp()) then inventory.unlocked_at
          else seen.seen_at
        end,
        'unlocked', catalog.availability = 'base' or inventory.state = 'unlocked'
      ) order by catalog.layer_order, catalog.slot, catalog.cosmetic_key)
      from public.pachanga_cosmetic_catalog catalog
      left join public.pachanga_team_cosmetic_inventory inventory
        on inventory.group_id = target_group_id
        and inventory.cosmetic_key = catalog.cosmetic_key
        and inventory.state = 'unlocked'
      left join public.pachanga_team_cosmetic_seen seen
        on seen.group_id = target_group_id
        and seen.cosmetic_key = catalog.cosmetic_key
        and seen.admin_user_id = auth.uid()
      where catalog.owner_scope = 'team'
        and catalog.cosmetic_key like 'team.shield.%'
        and catalog.active
        and catalog.lifecycle = 'active_reward'
        and (
          (can_manage and (catalog.availability = 'base' or inventory.state = 'unlocked'))
          or (not can_manage and (catalog.availability = 'base' or inventory.state = 'unlocked' or catalog.cosmetic_key = any(equipped_keys)))
        )
    ), '[]'::jsonb),
    'updatedAt', coalesce(selected_state.updated_at, selected_loadout.updated_at, selected_group.updated_at, clock_timestamp())
  );
end;
$function$;
