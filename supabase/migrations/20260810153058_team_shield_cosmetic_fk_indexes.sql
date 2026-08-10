-- Cover reverse foreign-key lookups used by deletes, ownership changes,
-- moderation and audit queries for Team Shield Cosmetics V1.

create index if not exists pachanga_team_cosmetic_eligibility_admin_idx
  on public.pachanga_team_cosmetic_admin_eligibility(admin_user_id, group_id);

create index if not exists pachanga_team_cosmetic_inventory_key_idx
  on public.pachanga_team_cosmetic_inventory(cosmetic_key, group_id);
create index if not exists pachanga_team_cosmetic_inventory_grant_idx
  on public.pachanga_team_cosmetic_inventory(source_grant_id, group_id)
  where source_grant_id is not null;

create index if not exists pachanga_team_shield_events_actor_idx
  on public.pachanga_team_shield_events(actor_user_id, server_sequence desc, id)
  where actor_user_id is not null;
create index if not exists pachanga_team_shield_events_cosmetic_idx
  on public.pachanga_team_shield_events(cosmetic_key, server_sequence desc, id)
  where cosmetic_key is not null;

create index if not exists pachanga_team_shield_loadouts_updated_by_idx
  on public.pachanga_team_shield_loadouts(updated_by, group_id)
  where updated_by is not null;

create index if not exists pachanga_team_shield_receipts_actor_idx
  on public.pachanga_team_shield_operation_receipts(actor_user_id, server_sequence desc, operation_id)
  where actor_user_id is not null;
create index if not exists pachanga_team_shield_receipts_group_idx
  on public.pachanga_team_shield_operation_receipts(group_id, server_sequence desc, operation_id);

create index if not exists pachanga_team_shield_versions_previous_idx
  on public.pachanga_team_shield_versions(previous_version_id)
  where previous_version_id is not null;
create index if not exists pachanga_team_shield_versions_saved_by_idx
  on public.pachanga_team_shield_versions(saved_by, group_id, version_number desc)
  where saved_by is not null;
