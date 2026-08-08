-- Conservative, server-authoritative reward economy V1.
-- Rewards are cosmetic only and never update Rating V2, facets or assessments.

create table if not exists public.pachanga_reward_economy_versions (
  version integer primary key,
  state text not null default 'draft',
  currency_key text not null default 'player_points',
  config jsonb not null default '{}'::jsonb,
  activated_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  check (version >= 1),
  check (state in ('draft', 'active', 'retired')),
  check (currency_key = 'player_points'),
  check (jsonb_typeof(config) = 'object')
);

create unique index if not exists pachanga_reward_economy_active_idx
  on public.pachanga_reward_economy_versions(state)
  where state = 'active';

create table if not exists public.pachanga_reward_box_catalog (
  economy_version integer not null
    references public.pachanga_reward_economy_versions(version) on delete restrict,
  box_type text not null,
  display_name text not null,
  rarity text not null,
  min_points integer not null,
  max_points integer not null,
  reward_pool_key text not null,
  animation_key text not null,
  presentation_key text not null,
  possible_reward_pool jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  primary key (economy_version, box_type),
  check (char_length(box_type) between 3 and 100),
  check (rarity in ('common', 'uncommon', 'rare', 'epic', 'legendary')),
  check (min_points >= 0 and max_points >= min_points),
  check (jsonb_typeof(possible_reward_pool) = 'array')
);

create table if not exists public.pachanga_reward_pool_catalog (
  economy_version integer not null
    references public.pachanga_reward_economy_versions(version) on delete restrict,
  pool_key text not null,
  entry_key text not null,
  reward_kind text not null,
  weight integer not null,
  points_min integer not null default 0,
  points_max integer not null default 0,
  cosmetic_key text references public.pachanga_cosmetic_catalog(cosmetic_key)
    on delete restrict,
  duplicate_conversion_points integer not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  primary key (economy_version, pool_key, entry_key),
  check (reward_kind in ('points', 'player_cosmetic', 'combination')),
  check (weight > 0),
  check (points_min >= 0 and points_max >= points_min),
  check (duplicate_conversion_points >= 0),
  check (
    (reward_kind = 'points' and cosmetic_key is null and points_max > 0)
    or (reward_kind = 'player_cosmetic' and cosmetic_key is not null)
    or (reward_kind = 'combination' and cosmetic_key is not null and points_max > 0)
  ),
  check (jsonb_typeof(metadata) = 'object')
);

create index if not exists pachanga_reward_pool_lookup_idx
  on public.pachanga_reward_pool_catalog(
    economy_version, pool_key, active, entry_key
  );

create table if not exists public.pachanga_achievement_box_rules (
  economy_version integer not null
    references public.pachanga_reward_economy_versions(version) on delete restrict,
  achievement_key text not null,
  achievement_version integer not null,
  first_box_type text not null,
  repeat_box_type text not null,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  primary key (economy_version, achievement_key, achievement_version),
  foreign key (achievement_key, achievement_version)
    references public.pachanga_achievement_definitions(achievement_key, version)
    on delete restrict,
  foreign key (economy_version, first_box_type)
    references public.pachanga_reward_box_catalog(economy_version, box_type)
    on delete restrict,
  foreign key (economy_version, repeat_box_type)
    references public.pachanga_reward_box_catalog(economy_version, box_type)
    on delete restrict
);

create index if not exists pachanga_achievement_box_rules_achievement_idx
  on public.pachanga_achievement_box_rules(
    achievement_key, achievement_version, economy_version
  );

create table if not exists public.pachanga_player_point_accounts (
  player_profile_id uuid primary key
    references public.pachanga_player_profiles(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete restrict,
  balance bigint not null default 0,
  lifetime_earned bigint not null default 0,
  lifetime_spent bigint not null default 0,
  revision bigint not null default 1,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  updated_at timestamptz not null default clock_timestamp(),
  check (balance >= 0),
  check (lifetime_earned >= 0 and lifetime_spent >= 0),
  check (revision >= 1)
);

create unique index if not exists pachanga_player_point_accounts_user_idx
  on public.pachanga_player_point_accounts(user_id);

create table if not exists public.pachanga_player_points_ledger (
  id uuid primary key default gen_random_uuid(),
  player_profile_id uuid not null
    references public.pachanga_player_profiles(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  delta integer not null,
  balance_after bigint not null,
  source_type text not null,
  source_id uuid not null,
  source_box_id uuid,
  match_fact_id uuid references public.pachanga_progression_match_facts(id)
    on delete restrict,
  achievement_grant_id uuid references public.pachanga_achievement_grants(id)
    on delete restrict,
  idempotency_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  server_sequence bigint not null default nextval('public.pachanga_progression_sequence'),
  created_at timestamptz not null default clock_timestamp(),
  unique (idempotency_key),
  check (delta <> 0),
  check (balance_after >= 0),
  check (source_type in (
    'reward_box', 'box_purchase', 'cosmetic_purchase', 'admin_adjustment'
  )),
  check (jsonb_typeof(metadata) = 'object')
);

create unique index if not exists pachanga_player_points_reward_box_idx
  on public.pachanga_player_points_ledger(source_box_id)
  where source_type = 'reward_box';
create index if not exists pachanga_player_points_history_idx
  on public.pachanga_player_points_ledger(
    player_profile_id, server_sequence desc, id desc
  );
create index if not exists pachanga_player_points_user_history_idx
  on public.pachanga_player_points_ledger(
    user_id, server_sequence desc, id desc
  );
create index if not exists pachanga_player_points_match_fact_idx
  on public.pachanga_player_points_ledger(match_fact_id)
  where match_fact_id is not null;
create index if not exists pachanga_player_points_achievement_grant_idx
  on public.pachanga_player_points_ledger(achievement_grant_id)
  where achievement_grant_id is not null;

alter table public.pachanga_player_reward_inventory
  drop constraint if exists pachanga_player_reward_inventory_reward_kind_check;
alter table public.pachanga_player_reward_inventory
  add column if not exists source_box_id uuid,
  add column if not exists acquired_at timestamptz,
  add column if not exists metadata jsonb not null default '{}'::jsonb;
update public.pachanga_player_reward_inventory
set acquired_at = coalesce(acquired_at, unlocked_at);
alter table public.pachanga_player_reward_inventory
  alter column acquired_at set not null;
alter table public.pachanga_player_reward_inventory
  add constraint pachanga_player_reward_inventory_reward_kind_check
    check (reward_kind in ('player_badge', 'player_title', 'player_cosmetic')),
  add constraint pachanga_player_reward_inventory_metadata_check
    check (jsonb_typeof(metadata) = 'object');
create unique index if not exists pachanga_player_reward_inventory_source_box_idx
  on public.pachanga_player_reward_inventory(source_box_id)
  where source_box_id is not null;

alter table public.pachanga_reward_recipients
  add column if not exists economy_version integer,
  add column if not exists box_type text,
  add column if not exists box_rarity text,
  add column if not exists reward_pool_key text,
  add column if not exists animation_key text,
  add column if not exists presentation_key text;
alter table public.pachanga_reward_recipients
  add constraint pachanga_reward_recipients_economy_version_check
    check (economy_version is null or economy_version >= 0),
  add constraint pachanga_reward_recipients_box_rarity_check
    check (box_rarity is null or box_rarity in (
      'common', 'uncommon', 'rare', 'epic', 'legendary'
    )),
  add constraint pachanga_reward_recipients_box_catalog_fkey
    foreign key (economy_version, box_type)
    references public.pachanga_reward_box_catalog(economy_version, box_type)
    on delete restrict;

alter table public.pachanga_player_points_ledger
  add constraint pachanga_player_points_ledger_source_box_fkey
    foreign key (source_box_id)
    references public.pachanga_reward_recipients(box_id)
    on delete restrict;

alter table public.pachanga_player_reward_inventory
  add constraint pachanga_player_reward_inventory_source_box_fkey
    foreign key (source_box_id)
    references public.pachanga_reward_recipients(box_id)
    on delete restrict;

alter table private.pachanga_reward_box_contents
  add column if not exists catalog_version integer not null default 0,
  add column if not exists content_hash text,
  add column if not exists sealed_at timestamptz not null default clock_timestamp();
update private.pachanga_reward_box_contents
set content_hash = md5(reward_payload::text)
where content_hash is null;
alter table private.pachanga_reward_box_contents
  alter column content_hash set not null;

insert into public.pachanga_reward_economy_versions(
  version, state, currency_key, config, activated_at
) values (
  1, 'active', 'player_points',
  jsonb_build_object(
    'policy', 'conservative_v1',
    'realMoneyPurchases', false,
    'transfers', false,
    'ratingImpact', false,
    'duplicatePolicy', 'convert_to_player_points'
  ), clock_timestamp()
) on conflict (version) do update set
  state = excluded.state, config = excluded.config,
  activated_at = coalesce(
    public.pachanga_reward_economy_versions.activated_at,
    excluded.activated_at
  );

insert into public.pachanga_reward_box_catalog(
  economy_version, box_type, display_name, rarity, min_points, max_points,
  reward_pool_key, animation_key, presentation_key,
  possible_reward_pool, sort_order
) values
  (1, 'collective.common', 'Caja común', 'common', 4, 7,
    'pool.collective.common', 'reward_box_blue', 'box.common',
    '[{"kind":"points","weight":70},{"kind":"player_cosmetic","weight":20},{"kind":"combination","weight":10}]'::jsonb, 10),
  (1, 'collective.uncommon', 'Caja poco común', 'uncommon', 7, 11,
    'pool.collective.uncommon', 'reward_box_blue', 'box.uncommon',
    '[{"kind":"points","weight":65},{"kind":"player_cosmetic","weight":22},{"kind":"combination","weight":13}]'::jsonb, 20),
  (1, 'collective.rare', 'Caja rara', 'rare', 12, 18,
    'pool.collective.rare', 'reward_box_blue', 'box.rare',
    '[{"kind":"points","weight":60},{"kind":"player_cosmetic","weight":24},{"kind":"combination","weight":16}]'::jsonb, 30),
  (1, 'collective.epic', 'Caja épica', 'epic', 20, 30,
    'pool.collective.epic', 'reward_box_blue', 'box.epic',
    '[{"kind":"points","weight":55},{"kind":"player_cosmetic","weight":25},{"kind":"combination","weight":20}]'::jsonb, 40),
  (1, 'collective.legendary', 'Caja legendaria', 'legendary', 35, 50,
    'pool.collective.legendary', 'reward_box_blue', 'box.legendary',
    '[{"kind":"points","weight":50},{"kind":"player_cosmetic","weight":25},{"kind":"combination","weight":25}]'::jsonb, 50)
on conflict (economy_version, box_type) do update set
  display_name = excluded.display_name, rarity = excluded.rarity,
  min_points = excluded.min_points, max_points = excluded.max_points,
  reward_pool_key = excluded.reward_pool_key,
  animation_key = excluded.animation_key,
  presentation_key = excluded.presentation_key,
  possible_reward_pool = excluded.possible_reward_pool,
  sort_order = excluded.sort_order, active = true;

insert into public.pachanga_reward_pool_catalog(
  economy_version, pool_key, entry_key, reward_kind, weight,
  points_min, points_max, cosmetic_key, duplicate_conversion_points, metadata
) values
  (1, 'pool.collective.common', 'points', 'points', 70, 4, 7, null, 0, '{}'),
  (1, 'pool.collective.common', 'cosmetic.ball', 'player_cosmetic', 10, 0, 0, 'symbol.ball', 4, '{}'),
  (1, 'pool.collective.common', 'cosmetic.stripes', 'player_cosmetic', 10, 0, 0, 'pattern.stripes', 4, '{}'),
  (1, 'pool.collective.common', 'combo.ball', 'combination', 10, 3, 5, 'symbol.ball', 4, '{}'),

  (1, 'pool.collective.uncommon', 'points', 'points', 65, 7, 11, null, 0, '{}'),
  (1, 'pool.collective.uncommon', 'cosmetic.diagonal', 'player_cosmetic', 11, 0, 0, 'pattern.diagonal', 8, '{}'),
  (1, 'pool.collective.uncommon', 'cosmetic.double', 'player_cosmetic', 11, 0, 0, 'border.double', 8, '{}'),
  (1, 'pool.collective.uncommon', 'combo.ribbon', 'combination', 13, 5, 8, 'adornment.ribbon', 8, '{}'),

  (1, 'pool.collective.rare', 'points', 'points', 60, 12, 18, null, 0, '{}'),
  (1, 'pool.collective.rare', 'cosmetic.silver', 'player_cosmetic', 12, 0, 0, 'border.silver', 16, '{}'),
  (1, 'pool.collective.rare', 'cosmetic.laurel', 'player_cosmetic', 12, 0, 0, 'border.laurel', 16, '{}'),
  (1, 'pool.collective.rare', 'combo.star', 'combination', 16, 8, 12, 'adornment.star', 16, '{}'),

  (1, 'pool.collective.epic', 'points', 'points', 55, 20, 30, null, 0, '{}'),
  (1, 'pool.collective.epic', 'cosmetic.gold', 'player_cosmetic', 13, 0, 0, 'border.gold', 28, '{}'),
  (1, 'pool.collective.epic', 'cosmetic.crown', 'player_cosmetic', 12, 0, 0, 'symbol.crown', 28, '{}'),
  (1, 'pool.collective.epic', 'combo.palette', 'combination', 20, 14, 20, 'palette.gold', 28, '{}'),

  (1, 'pool.collective.legendary', 'points', 'points', 50, 35, 50, null, 0, '{}'),
  (1, 'pool.collective.legendary', 'cosmetic.glow', 'player_cosmetic', 25, 0, 0, 'effect.glow', 45, '{}'),
  (1, 'pool.collective.legendary', 'combo.glow', 'combination', 25, 25, 35, 'effect.glow', 45, '{}')
on conflict (economy_version, pool_key, entry_key) do update set
  reward_kind = excluded.reward_kind, weight = excluded.weight,
  points_min = excluded.points_min, points_max = excluded.points_max,
  cosmetic_key = excluded.cosmetic_key,
  duplicate_conversion_points = excluded.duplicate_conversion_points,
  metadata = excluded.metadata, active = true;

insert into public.pachanga_achievement_box_rules(
  economy_version, achievement_key, achievement_version,
  first_box_type, repeat_box_type
)
select 1, definitions.achievement_key, definitions.version,
  case definitions.rarity
    when 'common' then 'collective.uncommon'
    when 'uncommon' then 'collective.rare'
    when 'rare' then 'collective.epic'
    when 'epic' then 'collective.legendary'
    else 'collective.legendary' end,
  'collective.' || definitions.rarity
from public.pachanga_achievement_definitions definitions
where definitions.subject_type = 'team'
on conflict (economy_version, achievement_key, achievement_version) do update set
  first_box_type = excluded.first_box_type,
  repeat_box_type = excluded.repeat_box_type,
  active = true;

alter table public.pachanga_reward_economy_versions enable row level security;
alter table public.pachanga_reward_box_catalog enable row level security;
alter table public.pachanga_reward_pool_catalog enable row level security;
alter table public.pachanga_achievement_box_rules enable row level security;
alter table public.pachanga_player_point_accounts enable row level security;
alter table public.pachanga_player_points_ledger enable row level security;

revoke all on table public.pachanga_reward_economy_versions
  from public, anon, authenticated;
revoke all on table public.pachanga_reward_box_catalog
  from public, anon, authenticated;
revoke all on table public.pachanga_reward_pool_catalog
  from public, anon, authenticated;
revoke all on table public.pachanga_achievement_box_rules
  from public, anon, authenticated;
revoke all on table public.pachanga_player_point_accounts
  from public, anon, authenticated;
revoke all on table public.pachanga_player_points_ledger
  from public, anon, authenticated;

grant select on table public.pachanga_reward_economy_versions to authenticated;
grant select on table public.pachanga_reward_box_catalog to authenticated;
grant select on table public.pachanga_reward_pool_catalog to authenticated;
grant select on table public.pachanga_achievement_box_rules to authenticated;
grant select on table public.pachanga_player_point_accounts to authenticated;
grant select on table public.pachanga_player_points_ledger to authenticated;
grant all on table public.pachanga_reward_economy_versions to service_role;
grant all on table public.pachanga_reward_box_catalog to service_role;
grant all on table public.pachanga_reward_pool_catalog to service_role;
grant all on table public.pachanga_achievement_box_rules to service_role;
grant all on table public.pachanga_player_point_accounts to service_role;
grant all on table public.pachanga_player_points_ledger to service_role;

create policy "Registered users read active reward economy versions"
on public.pachanga_reward_economy_versions for select to authenticated
using (public.is_registered_pachanga_user() and state = 'active');

create policy "Registered users read active reward box catalog"
on public.pachanga_reward_box_catalog for select to authenticated
using (public.is_registered_pachanga_user() and active);

create policy "Registered users read active reward pool probabilities"
on public.pachanga_reward_pool_catalog for select to authenticated
using (public.is_registered_pachanga_user() and active);

create policy "Registered users read active achievement box rules"
on public.pachanga_achievement_box_rules for select to authenticated
using (public.is_registered_pachanga_user() and active);

create policy "Players read their point account"
on public.pachanga_player_point_accounts for select to authenticated
using (user_id = (select auth.uid()));

create policy "Players read their point ledger"
on public.pachanga_player_points_ledger for select to authenticated
using (user_id = (select auth.uid()));

create or replace function private.pachanga_apply_player_points_v1(
  target_player_profile_id uuid,
  target_user_id uuid,
  target_delta integer,
  target_source_type text,
  target_source_id uuid,
  target_source_box_id uuid,
  target_match_fact_id uuid,
  target_achievement_grant_id uuid,
  target_idempotency_key text,
  target_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  account public.pachanga_player_point_accounts%rowtype;
  existing public.pachanga_player_points_ledger%rowtype;
  saved_sequence bigint;
begin
  if target_player_profile_id is null or target_user_id is null
    or target_delta = 0 or nullif(target_idempotency_key, '') is null then
    raise exception 'Player, user, non-zero delta and idempotency key required';
  end if;
  if target_source_type not in (
    'reward_box', 'box_purchase', 'cosmetic_purchase', 'admin_adjustment'
  ) then raise exception 'Unsupported point source'; end if;
  if not exists (
    select 1 from public.pachanga_player_profiles profiles
    where profiles.id = target_player_profile_id
      and profiles.user_id = target_user_id
  ) then raise exception 'Player profile does not belong to user'; end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'player-points:' || target_player_profile_id::text, 0
  ));
  select * into existing
  from public.pachanga_player_points_ledger ledger
  where ledger.idempotency_key = target_idempotency_key;
  if found then
    if existing.player_profile_id <> target_player_profile_id
      or existing.user_id <> target_user_id
      or existing.delta <> target_delta then
      raise exception 'Point operation conflicts with existing evidence';
    end if;
    return jsonb_build_object(
      'balance', existing.balance_after,
      'delta', existing.delta,
      'ledgerEntryId', existing.id,
      'serverSequence', existing.server_sequence,
      'alreadyApplied', true
    );
  end if;

  insert into public.pachanga_player_point_accounts(
    player_profile_id, user_id
  ) values (target_player_profile_id, target_user_id)
  on conflict (player_profile_id) do nothing;

  select * into account
  from public.pachanga_player_point_accounts accounts
  where accounts.player_profile_id = target_player_profile_id
  for update;
  if account.user_id <> target_user_id then
    raise exception 'Point account belongs to another user';
  end if;
  if account.balance + target_delta < 0 then
    raise exception 'Insufficient player points' using errcode = 'PT409';
  end if;

  saved_sequence := nextval('public.pachanga_progression_sequence');
  update public.pachanga_player_point_accounts accounts
  set balance = accounts.balance + target_delta,
      lifetime_earned = accounts.lifetime_earned + greatest(target_delta, 0),
      lifetime_spent = accounts.lifetime_spent + greatest(-target_delta, 0),
      revision = accounts.revision + 1,
      server_sequence = saved_sequence,
      updated_at = clock_timestamp()
  where accounts.player_profile_id = target_player_profile_id
  returning * into account;

  insert into public.pachanga_player_points_ledger(
    player_profile_id, user_id, delta, balance_after, source_type,
    source_id, source_box_id, match_fact_id, achievement_grant_id,
    idempotency_key, metadata, server_sequence
  ) values (
    target_player_profile_id, target_user_id, target_delta, account.balance,
    target_source_type, target_source_id, target_source_box_id,
    target_match_fact_id, target_achievement_grant_id,
    target_idempotency_key,
    case when jsonb_typeof(target_metadata) = 'object'
      then target_metadata else '{}'::jsonb end,
    saved_sequence
  ) returning * into existing;

  return jsonb_build_object(
    'balance', account.balance,
    'delta', target_delta,
    'ledgerEntryId', existing.id,
    'serverSequence', saved_sequence,
    'alreadyApplied', false
  );
end;
$$;

create or replace function private.pachanga_seal_reward_box_v1(
  target_box_id uuid,
  target_achievement_grant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  source record;
  catalog public.pachanga_reward_box_catalog%rowtype;
  pool_entry public.pachanga_reward_pool_catalog%rowtype;
  active_version integer;
  selected_box_type text;
  total_weight integer;
  ticket integer;
  selected_points integer := 0;
  payload jsonb;
  entropy uuid := gen_random_uuid();
begin
  select contents.reward_payload into payload
  from private.pachanga_reward_box_contents contents
  where contents.box_id = target_box_id;
  if found then return payload; end if;

  select versions.version into active_version
  from public.pachanga_reward_economy_versions versions
  where versions.state = 'active'
  order by versions.version desc
  limit 1;
  if active_version is null then raise exception 'No active reward economy'; end if;

  select grants.id, grants.is_first, grants.origin_match_fact_id,
    grants.group_id, definitions.achievement_key,
    definitions.version as achievement_version
  into source
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where grants.id = target_achievement_grant_id
    and grants.subject_type = 'team'
    and grants.state = 'active';
  if not found then raise exception 'Active team achievement required'; end if;

  select case when source.is_first then rules.first_box_type
    else rules.repeat_box_type end
  into selected_box_type
  from public.pachanga_achievement_box_rules rules
  where rules.economy_version = active_version
    and rules.achievement_key = source.achievement_key
    and rules.achievement_version = source.achievement_version
    and rules.active;
  if selected_box_type is null then raise exception 'Achievement box rule missing'; end if;

  select * into catalog
  from public.pachanga_reward_box_catalog boxes
  where boxes.economy_version = active_version
    and boxes.box_type = selected_box_type
    and boxes.active;
  if not found then raise exception 'Reward box catalog entry missing'; end if;

  select sum(entries.weight)::integer into total_weight
  from public.pachanga_reward_pool_catalog entries
  where entries.economy_version = active_version
    and entries.pool_key = catalog.reward_pool_key
    and entries.active;
  if coalesce(total_weight, 0) <= 0 then raise exception 'Reward pool is empty'; end if;
  ticket := (hashtextextended(
    entropy::text || ':pool:' || active_version::text || ':' || catalog.reward_pool_key,
    0
  ) & 9223372036854775807) % total_weight;

  select (weighted.entry).* into pool_entry
  from (
    select entries as entry,
      sum(entries.weight) over (order by entries.entry_key) as ceiling
    from public.pachanga_reward_pool_catalog entries
    where entries.economy_version = active_version
      and entries.pool_key = catalog.reward_pool_key
      and entries.active
  ) weighted
  where ticket < weighted.ceiling
  order by weighted.ceiling
  limit 1;
  if not found then raise exception 'Reward pool selection failed'; end if;

  if pool_entry.points_max > 0 then
    selected_points := pool_entry.points_min + (
      (hashtextextended(entropy::text || ':points', 0)
        & 9223372036854775807)
      % (pool_entry.points_max - pool_entry.points_min + 1)
    );
  end if;

  payload := jsonb_strip_nulls(jsonb_build_object(
    'schemaVersion', 1,
    'catalogVersion', active_version,
    'boxType', catalog.box_type,
    'rarity', catalog.rarity,
    'poolKey', catalog.reward_pool_key,
    'poolEntryKey', pool_entry.entry_key,
    'animationKey', catalog.animation_key,
    'presentationKey', catalog.presentation_key,
    'source', 'collective_achievement',
    'reward', jsonb_strip_nulls(jsonb_build_object(
      'kind', pool_entry.reward_kind,
      'points', selected_points,
      'cosmeticKey', pool_entry.cosmetic_key,
      'duplicateConversionPoints', pool_entry.duplicate_conversion_points
    )),
    'origin', jsonb_build_object(
      'achievementKey', source.achievement_key,
      'achievementGrantId', source.id,
      'matchFactId', source.origin_match_fact_id,
      'groupId', source.group_id
    )
  ));

  update public.pachanga_reward_recipients recipients
  set economy_version = active_version,
      box_type = catalog.box_type,
      box_rarity = catalog.rarity,
      reward_pool_key = catalog.reward_pool_key,
      animation_key = catalog.animation_key,
      presentation_key = catalog.presentation_key,
      reward_reference = catalog.box_type
  where recipients.box_id = target_box_id;

  insert into private.pachanga_reward_box_contents(
    box_id, reward_payload, catalog_version, content_hash, sealed_at
  ) values (
    target_box_id, payload, active_version, md5(payload::text), clock_timestamp()
  ) on conflict (box_id) do nothing;
  return payload;
end;
$$;

create or replace function private.pachanga_keep_reward_box_contents_sealed_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  raise exception 'Sealed reward box contents are immutable';
end;
$$;

create or replace function private.pachanga_ensure_collective_boxes_v2(
  target_achievement_grant_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  source record;
  reward public.pachanga_reward_grants%rowtype;
  recipient record;
  saved_box_id uuid;
  created_count integer := 0;
begin
  select grants.*, definitions.achievement_key,
    definitions.title, definitions.description, definitions.rarity
  into source
  from public.pachanga_achievement_grants grants
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where grants.id = target_achievement_grant_id
    and grants.subject_type = 'team'
    and grants.state = 'active';
  if not found then return 0; end if;

  insert into public.pachanga_reward_grants(
    achievement_grant_id, reward_kind, reward_key, group_id,
    player_profile_id, payload
  ) values (
    source.id, 'collective_box', 'box.collective.pending', source.group_id,
    null, jsonb_build_object(
      'boxKind', 'collective_achievement',
      'achievementKey', source.achievement_key,
      'achievementRarity', source.rarity,
      'economy', 'player_reward_v1'
    )
  ) on conflict (achievement_grant_id) do update set
    payload = excluded.payload
  returning * into reward;

  for recipient in
    select distinct on (profiles.user_id)
      profiles.user_id, profiles.id as player_profile_id,
      profiles.display_name, player_facts.local_player_id
    from public.pachanga_progression_player_match_facts player_facts
    join public.pachanga_player_profiles profiles
      on profiles.id = player_facts.player_profile_id
    where player_facts.match_fact_id = source.origin_match_fact_id
      and player_facts.group_id = source.group_id
      and player_facts.state = 'active'
      and profiles.user_id is not null
    order by profiles.user_id, player_facts.local_player_id
  loop
    saved_box_id := gen_random_uuid();
    insert into public.pachanga_reward_recipients(
      reward_grant_id, user_id, member_role_snapshot, member_name_snapshot,
      box_id, achievement_grant_id, match_fact_id, group_id,
      player_profile_id, reward_reference
    ) values (
      reward.id, recipient.user_id, 'participant',
      left(coalesce(recipient.display_name, 'Jugador'), 120),
      saved_box_id, source.id, source.origin_match_fact_id, source.group_id,
      recipient.player_profile_id, 'box.collective.pending'
    ) on conflict (achievement_grant_id, user_id) do update set
      player_profile_id = excluded.player_profile_id,
      match_fact_id = excluded.match_fact_id,
      group_id = excluded.group_id,
      member_role_snapshot = 'participant',
      member_name_snapshot = excluded.member_name_snapshot
    returning box_id into saved_box_id;

    if not exists (
      select 1 from private.pachanga_reward_box_contents contents
      where contents.box_id = saved_box_id
    ) then
      perform private.pachanga_seal_reward_box_v1(saved_box_id, source.id);
      created_count := created_count + 1;
    end if;
    perform private.pachanga_progression_bump_user_v1(recipient.user_id);
  end loop;
  return created_count;
end;
$$;

create or replace function private.pachanga_reward_recipient_snapshot_v1(
  target_reward_grant_id uuid,
  target_user_id uuid
)
returns jsonb
language sql
security definer
stable
set search_path = pg_catalog
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'boxId', recipients.box_id,
    'rewardGrantId', rewards.id,
    'rewardKind', case when coalesce(recipients.economy_version, 0) >= 1
      then 'collective_box'
      when recipients.status = 'opened' then rewards.reward_kind
      else 'collective_box' end,
    'rewardKey', coalesce(recipients.box_type, recipients.reward_reference),
    'rewardPayload', case when recipients.status = 'opened'
      then recipients.revealed_payload else null end,
    'rewardState', rewards.state,
    'status', recipients.status,
    'recipientRevision', recipients.revision,
    'generatedAt', recipients.snapshot_at,
    'openedAt', recipients.opened_at,
    'rewardGrantedAt', recipients.reward_granted_at,
    'matchFactId', recipients.match_fact_id,
    'groupId', recipients.group_id,
    'economyVersion', recipients.economy_version,
    'boxType', recipients.box_type,
    'boxRarity', recipients.box_rarity,
    'rewardPoolKey', recipients.reward_pool_key,
    'animationKey', recipients.animation_key,
    'presentationKey', recipients.presentation_key,
    'sourceCorrection', recipients.source_correction,
    'achievement', jsonb_build_object(
      'grantId', grants.id,
      'key', definitions.achievement_key,
      'title', coalesce(grants.occurrence_metadata ->> 'displayTitle', definitions.title),
      'description', definitions.description,
      'scope', definitions.match_scope,
      'subjectType', definitions.subject_type,
      'rarity', definitions.rarity,
      'isFirst', grants.is_first,
      'sequenceCount', grants.sequence_count,
      'occurredAt', grants.occurred_at,
      'awardedAt', grants.awarded_at
    )
  ))
  from public.pachanga_reward_recipients recipients
  join public.pachanga_reward_grants rewards
    on rewards.id = recipients.reward_grant_id
  join public.pachanga_achievement_grants grants
    on grants.id = recipients.achievement_grant_id
  join public.pachanga_achievement_definitions definitions
    on definitions.id = grants.definition_id
  where recipients.reward_grant_id = target_reward_grant_id
    and recipients.user_id = target_user_id;
$$;

create or replace function public.open_pachanga_reward_box_v2(
  target_box_id uuid,
  operation_id uuid,
  expected_revision bigint,
  client_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  selected public.pachanga_reward_recipients%rowtype;
  reward public.pachanga_reward_grants%rowtype;
  grant_row public.pachanga_achievement_grants%rowtype;
  sealed jsonb;
  stored_actor uuid;
  stored_box_id uuid;
  stored_expected_revision bigint;
  stored_response jsonb;
  saved_sequence bigint;
  response jsonb;
  point_result jsonb;
  grant_result jsonb := '{}'::jsonb;
  cosmetic_key text;
  cosmetic_granted boolean := false;
  base_points integer := 0;
  duplicate_points integer := 0;
  total_points integer := 0;
  was_already_opened boolean := false;
begin
  if auth.uid() is null or open_pachanga_reward_box_v2.operation_id is null
    or target_box_id is null or expected_revision is null then
    raise exception 'Authentication, box, operation id and expected revision required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'reward-box-open:' || target_box_id::text, 0
  ));
  select receipts.actor_user_id, receipts.box_id,
    receipts.expected_revision, receipts.response
  into stored_actor, stored_box_id, stored_expected_revision, stored_response
  from public.pachanga_reward_open_receipts receipts
  where receipts.operation_id = open_pachanga_reward_box_v2.operation_id;
  if found then
    if stored_actor <> auth.uid() then
      raise exception 'Operation belongs to another actor';
    end if;
    if stored_box_id is distinct from target_box_id
      or stored_expected_revision is distinct from expected_revision then
      raise exception 'Operation conflicts with existing reward evidence';
    end if;
    return stored_response;
  end if;

  select * into selected
  from public.pachanga_reward_recipients recipients
  where recipients.box_id = target_box_id
    and recipients.user_id = auth.uid()
  for update;
  if not found then raise exception 'Reward box not found'; end if;
  select * into reward from public.pachanga_reward_grants rewards
  where rewards.id = selected.reward_grant_id;
  select * into grant_row from public.pachanga_achievement_grants grants
  where grants.id = selected.achievement_grant_id;
  if selected.status = 'revoked' or grant_row.state = 'revoked' then
    raise exception 'Reward box is no longer active';
  end if;

  if selected.status = 'opened' then
    was_already_opened := true;
    select states.server_sequence into saved_sequence
    from public.pachanga_progression_user_state states
    where states.user_id = auth.uid();
  else
    if reward.state <> 'active' then raise exception 'Reward box is no longer active'; end if;
    if selected.revision <> expected_revision then
      raise exception 'Reward box revision is newer. Reload the confirmed state.'
        using errcode = 'PT409';
    end if;
    select contents.reward_payload into sealed
    from private.pachanga_reward_box_contents contents
    where contents.box_id = selected.box_id
    for update;
    if sealed is null then raise exception 'Reward box content is unavailable'; end if;

    if coalesce(selected.economy_version, 0) >= 1 then
      if selected.player_profile_id is null then
        raise exception 'Reward box has no canonical player profile';
      end if;
      base_points := coalesce((sealed -> 'reward' ->> 'points')::integer, 0);
      cosmetic_key := nullif(sealed -> 'reward' ->> 'cosmeticKey', '');
      if cosmetic_key is not null then
        insert into public.pachanga_player_reward_inventory(
          player_profile_id, reward_kind, reward_key, source_grant_id,
          source_box_id, state, unlocked_at, acquired_at, metadata
        ) values (
          selected.player_profile_id, 'player_cosmetic', cosmetic_key,
          grant_row.id, selected.box_id, 'unlocked', clock_timestamp(),
          clock_timestamp(), jsonb_build_object(
            'source', 'reward_box',
            'catalogVersion', selected.economy_version,
            'boxType', selected.box_type
          )
        ) on conflict (player_profile_id, reward_kind, reward_key) do nothing
        returning true into cosmetic_granted;
        if not coalesce(cosmetic_granted, false) then
          duplicate_points := coalesce(
            (sealed -> 'reward' ->> 'duplicateConversionPoints')::integer, 0
          );
        end if;
      end if;
      total_points := base_points + duplicate_points;
      if total_points > 0 then
        point_result := private.pachanga_apply_player_points_v1(
          selected.player_profile_id, selected.user_id, total_points,
          'reward_box', selected.box_id, selected.box_id,
          selected.match_fact_id, selected.achievement_grant_id,
          'reward-box:' || selected.box_id::text,
          jsonb_build_object(
            'basePoints', base_points,
            'duplicateConversionPoints', duplicate_points,
            'originalReward', sealed -> 'reward',
            'cosmeticGranted', coalesce(cosmetic_granted, false)
          )
        );
        saved_sequence := (point_result ->> 'serverSequence')::bigint;
      end if;
      grant_result := jsonb_strip_nulls(jsonb_build_object(
        'pointsGranted', total_points,
        'basePoints', base_points,
        'duplicateConversionPoints', duplicate_points,
        'cosmeticKey', cosmetic_key,
        'cosmeticGranted', case when cosmetic_key is null then null
          else coalesce(cosmetic_granted, false) end,
        'duplicateConverted', cosmetic_key is not null
          and not coalesce(cosmetic_granted, false),
        'pointAccount', point_result
      ));
      sealed := sealed || jsonb_build_object('grant', grant_result);
    elsif reward.reward_kind = 'team_cosmetic' then
      insert into public.pachanga_team_cosmetic_inventory(
        group_id, cosmetic_key, source_grant_id
      ) values (
        reward.group_id, reward.reward_key, grant_row.id
      ) on conflict (group_id, cosmetic_key) do update set
        source_grant_id = excluded.source_grant_id,
        state = 'unlocked', unlocked_at = clock_timestamp(),
        revoked_at = null,
        revision = public.pachanga_team_cosmetic_inventory.revision + 1;
    end if;

    update public.pachanga_reward_recipients recipients
    set status = 'opened', opened_at = clock_timestamp(),
        reward_granted_at = clock_timestamp(), revealed_payload = sealed,
        revision = recipients.revision + 1
    where recipients.box_id = selected.box_id
    returning * into selected;

    saved_sequence := private.pachanga_progression_record_event_v1(
      md5('reward-box-opened:' || selected.box_id::text)::uuid,
      'reward_opened', reward.group_id, selected.player_profile_id,
      selected.match_fact_id, selected.achievement_grant_id, reward.id,
      jsonb_build_object(
        'boxId', selected.box_id,
        'rewardKind', case when coalesce(selected.economy_version, 0) >= 1
          then 'collective_box' else reward.reward_kind end,
        'rewardReference', selected.reward_reference,
        'economyVersion', selected.economy_version,
        'pointsGranted', total_points,
        'cosmeticKey', cosmetic_key,
        'duplicateConversionPoints', duplicate_points
      )
    );
  end if;

  response := private.pachanga_reward_box_snapshot_v2(
    selected.box_id, selected.user_id
  ) || jsonb_build_object(
    'operationId', open_pachanga_reward_box_v2.operation_id,
    'expectedRevision', expected_revision,
    'confirmedRevision', selected.revision,
    'serverSequence', coalesce(saved_sequence, 0),
    'confirmedAt', clock_timestamp(),
    'alreadyOpened', was_already_opened
  );
  insert into public.pachanga_reward_open_receipts(
    operation_id, reward_grant_id, actor_user_id, expected_revision,
    result_revision, server_sequence, response, client_metadata, box_id
  ) values (
    open_pachanga_reward_box_v2.operation_id,
    selected.reward_grant_id, auth.uid(), expected_revision,
    selected.revision, coalesce(saved_sequence, 0), response,
    case when jsonb_typeof(client_metadata) = 'object'
      then client_metadata else '{}'::jsonb end,
    selected.box_id
  );
  return response;
end;
$$;

-- Boxes generated by the immediately preceding, unreleased migration are
-- upgraded once into economy V1. Opened legacy rewards remain untouched.
do $$
declare
  pending record;
begin
  for pending in
    select recipients.box_id, recipients.achievement_grant_id
    from public.pachanga_reward_recipients recipients
    where recipients.status = 'pending'
      and recipients.economy_version is null
    order by recipients.snapshot_at, recipients.box_id
  loop
    delete from private.pachanga_reward_box_contents contents
    where contents.box_id = pending.box_id;
    perform private.pachanga_seal_reward_box_v1(
      pending.box_id, pending.achievement_grant_id
    );
  end loop;
end;
$$;

drop trigger if exists keep_pachanga_reward_box_contents_sealed_v1
  on private.pachanga_reward_box_contents;
create trigger keep_pachanga_reward_box_contents_sealed_v1
before update or delete on private.pachanga_reward_box_contents
for each row execute function private.pachanga_keep_reward_box_contents_sealed_v1();

create or replace function public.get_pachanga_progression_snapshot_v1(
  target_group_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  base_snapshot jsonb;
  current_profile_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not private.pachanga_can_read_progression_group_v1(target_group_id) then
    raise exception 'Group access denied';
  end if;
  base_snapshot := private.pachanga_progression_snapshot_base_v1(target_group_id);
  select profiles.id into current_profile_id
  from public.pachanga_player_profiles profiles
  where profiles.user_id = auth.uid();

  return base_snapshot || jsonb_build_object(
    'personalStats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scope', stats.match_scope, 'appearances', stats.appearances,
        'wins', stats.wins, 'draws', stats.draws, 'losses', stats.losses,
        'goals', stats.goals, 'braces', stats.braces,
        'hatTricks', stats.hat_tricks, 'pokers', stats.pokers,
        'repokers', stats.repokers,
        'doubleHatTricks', stats.double_hat_tricks,
        'maxWinStreak', stats.max_win_streak,
        'maxUnbeatenStreak', stats.max_unbeaten_streak,
        'revision', stats.revision, 'updatedAt', stats.updated_at
      ) order by stats.match_scope)
      from public.pachanga_player_progression_stats stats
      where stats.player_profile_id = current_profile_id
    ), '[]'::jsonb),
    'teamAchievements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantId', grants.id, 'key', definitions.achievement_key,
        'title', coalesce(grants.occurrence_metadata ->> 'displayTitle', definitions.title),
        'description', definitions.description, 'scope', definitions.match_scope,
        'category', definitions.category, 'rarity', definitions.rarity,
        'metricValue', grants.metric_value, 'threshold', definitions.threshold,
        'repeatable', definitions.repeatable, 'state', grants.state,
        'awardedAt', grants.awarded_at, 'occurredAt', grants.occurred_at,
        'isFirst', grants.is_first, 'sequenceCount', grants.sequence_count,
        'matchFactId', grants.origin_match_fact_id, 'revokedAt', grants.revoked_at
      ) order by grants.occurred_at desc, facts.server_sequence desc, grants.id desc)
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions definitions
        on definitions.id = grants.definition_id
      join public.pachanga_progression_match_facts facts
        on facts.id = grants.origin_match_fact_id
      where grants.group_id = target_group_id and grants.subject_type = 'team'
    ), '[]'::jsonb),
    'personalAchievements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'grantId', grants.id, 'key', definitions.achievement_key,
        'title', coalesce(grants.occurrence_metadata ->> 'displayTitle', definitions.title),
        'description', definitions.description, 'scope', definitions.match_scope,
        'category', definitions.category, 'rarity', definitions.rarity,
        'rewardKind', 'none', 'rewardKey', null,
        'repeatable', definitions.repeatable, 'state', grants.state,
        'awardedAt', grants.awarded_at, 'occurredAt', grants.occurred_at,
        'isFirst', grants.is_first, 'sequenceCount', grants.sequence_count,
        'matchFactId', grants.origin_match_fact_id, 'revokedAt', grants.revoked_at
      ) order by grants.occurred_at desc, facts.server_sequence desc, grants.id desc)
      from public.pachanga_achievement_grants grants
      join public.pachanga_achievement_definitions definitions
        on definitions.id = grants.definition_id
      join public.pachanga_progression_match_facts facts
        on facts.id = grants.origin_match_fact_id
      where grants.subject_type = 'player'
        and grants.subject_id = current_profile_id
    ), '[]'::jsonb),
    'personalAchievementCatalog', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', catalog.achievement_key, 'title', catalog.title,
        'description', catalog.description, 'scope', catalog.match_scope,
        'category', catalog.category, 'rarity', catalog.rarity,
        'threshold', catalog.threshold, 'currentValue', catalog.current_value,
        'occurrenceCount', catalog.occurrence_count,
        'progressPercent', least(100,
          floor(catalog.current_value * 100.0 / catalog.threshold)::integer),
        'unlocked', catalog.occurrence_count > 0,
        'repeatable', catalog.repeatable, 'grantId', catalog.grant_id,
        'awardedAt', catalog.occurred_at, 'rewardKind', 'none', 'rewardKey', null
      ) order by catalog.match_scope, catalog.category,
        catalog.threshold, catalog.achievement_key)
      from (
        select definitions.achievement_key, definitions.title,
          definitions.description, definitions.match_scope,
          definitions.category, definitions.rarity, definitions.threshold,
          definitions.repeatable,
          case when definitions.repeatable then count(grants.id)::integer
            else private.pachanga_achievement_metric_v1(
              definitions.id, current_profile_id
            ) end as current_value,
          count(grants.id)::integer as occurrence_count,
          (array_agg(grants.id order by grants.occurred_at desc, grants.id desc)
            filter (where grants.id is not null))[1] as grant_id,
          max(grants.occurred_at) as occurred_at
        from public.pachanga_achievement_definitions definitions
        left join public.pachanga_achievement_grants grants
          on grants.definition_id = definitions.id
         and grants.subject_type = 'player'
         and grants.subject_id = current_profile_id
         and grants.state = 'active'
        where definitions.active and definitions.subject_type = 'player'
        group by definitions.id, definitions.achievement_key,
          definitions.title, definitions.description, definitions.match_scope,
          definitions.category, definitions.rarity, definitions.threshold,
          definitions.repeatable
      ) catalog
    ), '[]'::jsonb),
    'rewardEconomy', jsonb_build_object(
      'currencyKey', 'player_points',
      'account', coalesce((
        select jsonb_build_object(
          'balance', accounts.balance,
          'lifetimeEarned', accounts.lifetime_earned,
          'lifetimeSpent', accounts.lifetime_spent,
          'revision', accounts.revision,
          'serverSequence', accounts.server_sequence,
          'updatedAt', accounts.updated_at
        ) from public.pachanga_player_point_accounts accounts
        where accounts.player_profile_id = current_profile_id
      ), jsonb_build_object(
        'balance', 0, 'lifetimeEarned', 0, 'lifetimeSpent', 0,
        'revision', 0, 'serverSequence', 0
      )),
      'inventory', coalesce((
        select jsonb_agg(jsonb_build_object(
          'kind', inventory.reward_kind,
          'key', inventory.reward_key,
          'state', inventory.state,
          'acquiredAt', inventory.acquired_at,
          'sourceBoxId', inventory.source_box_id,
          'metadata', inventory.metadata
        ) order by inventory.acquired_at desc, inventory.reward_key)
        from public.pachanga_player_reward_inventory inventory
        where inventory.player_profile_id = current_profile_id
          and inventory.state = 'unlocked'
      ), '[]'::jsonb),
      'ledger', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', entries.id, 'delta', entries.delta,
          'balanceAfter', entries.balance_after,
          'sourceType', entries.source_type,
          'sourceBoxId', entries.source_box_id,
          'matchFactId', entries.match_fact_id,
          'achievementGrantId', entries.achievement_grant_id,
          'metadata', entries.metadata,
          'serverSequence', entries.server_sequence,
          'createdAt', entries.created_at
        ) order by entries.server_sequence desc, entries.id desc)
        from (
          select ledger.* from public.pachanga_player_points_ledger ledger
          where ledger.player_profile_id = current_profile_id
          order by ledger.server_sequence desc, ledger.id desc limit 50
        ) entries
      ), '[]'::jsonb),
      'boxCatalog', coalesce((
        select jsonb_agg(jsonb_build_object(
          'boxType', boxes.box_type, 'name', boxes.display_name,
          'rarity', boxes.rarity, 'minPoints', boxes.min_points,
          'maxPoints', boxes.max_points,
          'animationKey', boxes.animation_key,
          'presentationKey', boxes.presentation_key,
          'possibleRewards', boxes.possible_reward_pool,
          'catalogVersion', boxes.economy_version
        ) order by boxes.sort_order, boxes.box_type)
        from public.pachanga_reward_box_catalog boxes
        join public.pachanga_reward_economy_versions versions
          on versions.version = boxes.economy_version
        where versions.state = 'active' and boxes.active
      ), '[]'::jsonb)
    ),
    'rewards', coalesce((
      select jsonb_agg(private.pachanga_reward_box_snapshot_v2(
        recipients.box_id, auth.uid()
      ) order by facts.played_at, facts.server_sequence,
        grants.sequence_count, recipients.box_id)
      from public.pachanga_reward_recipients recipients
      join public.pachanga_achievement_grants grants
        on grants.id = recipients.achievement_grant_id
      join public.pachanga_progression_match_facts facts
        on facts.id = recipients.match_fact_id
      where recipients.user_id = auth.uid()
        and recipients.group_id = target_group_id
        and recipients.status in ('pending', 'opened', 'revoked')
    ), '[]'::jsonb),
    'updatedAt', clock_timestamp()
  );
end;
$$;

revoke all on function private.pachanga_apply_player_points_v1(
  uuid, uuid, integer, text, uuid, uuid, uuid, uuid, text, jsonb
) from public, anon, authenticated;
revoke all on function private.pachanga_seal_reward_box_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_keep_reward_box_contents_sealed_v1()
  from public, anon, authenticated;
revoke all on function private.pachanga_ensure_collective_boxes_v2(uuid)
  from public, anon, authenticated;
revoke all on function private.pachanga_reward_recipient_snapshot_v1(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.open_pachanga_reward_box_v2(uuid, uuid, bigint, jsonb)
  from public, anon;
grant execute on function public.open_pachanga_reward_box_v2(uuid, uuid, bigint, jsonb)
  to authenticated;
revoke all on function public.get_pachanga_progression_snapshot_v1(uuid)
  from public, anon;
grant execute on function public.get_pachanga_progression_snapshot_v1(uuid)
  to authenticated;

comment on table public.pachanga_player_points_ledger is
  'Immutable audit ledger for player_points. Direct client writes are forbidden.';
comment on table public.pachanga_reward_pool_catalog is
  'Versioned, auditable reward probabilities. Content is selected and sealed server-side when a box is created.';
comment on function private.pachanga_apply_player_points_v1(
  uuid, uuid, integer, text, uuid, uuid, uuid, uuid, text, jsonb
) is 'Internal point mutation primitive for canonical grants and future authorized cosmetic purchases; never exposed to clients.';
comment on function public.open_pachanga_reward_box_v2(uuid, uuid, bigint, jsonb) is
  'Atomically reveals a sealed box, grants personal points/cosmetics, converts duplicates and records idempotent evidence.';
