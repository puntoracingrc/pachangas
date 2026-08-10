-- Static premium team shield borders only. No rewards, grants, sensors, 3D
-- runtime, feature activation, or sporting data changes.
set statement_timeout = '30s';
set lock_timeout = '5s';

insert into public.pachanga_cosmetic_catalog(
  cosmetic_key, version, family, display_name, description, rarity,
  availability, render_contract, layer_order, active,
  owner_scope, slot, collection_key, material_key, lifecycle
) values
  (
    'team.shield.border.copper', 2, 'border', 'Cobre',
    'Cobre cálido con contraste alto.', 'uncommon', 'achievement',
    '{"border":"material","material":"copper","premiumBorder":"prerender-material-v1","premiumTexture":"/team-shield-premium-v1/border-copper.9b756acb.webp"}',
    50, true, 'team', 'border', 'futbol_de_barrio', 'copper', 'active_reward'
  ),
  (
    'team.shield.border.silver', 2, 'border', 'Plata',
    'Plata satinada de alta lectura.', 'rare', 'achievement',
    '{"border":"material","material":"silver","premiumBorder":"prerender-material-v1","premiumTexture":"/team-shield-premium-v1/border-silver.dde0edf8.webp"}',
    50, true, 'team', 'border', 'retro', 'silver', 'active_reward'
  ),
  (
    'team.shield.border.gold', 2, 'border', 'Oro',
    'Oro contenido para hitos de élite.', 'legendary', 'achievement',
    '{"border":"material","material":"gold","premiumBorder":"prerender-material-v1","premiumTexture":"/team-shield-premium-v1/border-gold.96413f0c.webp"}',
    50, true, 'team', 'border', 'noche_de_partido', 'gold', 'active_reward'
  )
on conflict (cosmetic_key) do update set
  version = excluded.version,
  family = excluded.family,
  display_name = excluded.display_name,
  description = excluded.description,
  rarity = excluded.rarity,
  availability = excluded.availability,
  render_contract = excluded.render_contract,
  layer_order = excluded.layer_order,
  active = excluded.active,
  owner_scope = excluded.owner_scope,
  slot = excluded.slot,
  collection_key = excluded.collection_key,
  material_key = excluded.material_key,
  lifecycle = excluded.lifecycle;
