-- Cover every Team Cosmetic Rewards V1 foreign key reported by the Supabase
-- performance advisor. These indexes are additive and contain no policy or
-- reward behavior changes.

create index if not exists pachanga_team_cosmetic_reward_ledger_definition_idx
  on private.pachanga_team_cosmetic_reward_ledger(achievement_definition_id);

create index if not exists pachanga_team_cosmetic_reward_ledger_cosmetic_idx
  on private.pachanga_team_cosmetic_reward_ledger(cosmetic_key);

create index if not exists pachanga_team_cosmetic_reward_ledger_fact_idx
  on private.pachanga_team_cosmetic_reward_ledger(origin_match_fact_id);

create index if not exists pachanga_team_cosmetic_reward_mappings_cosmetic_idx
  on private.pachanga_team_cosmetic_reward_mappings(cosmetic_key);

create index if not exists pachanga_team_cosmetic_reward_policy_events_version_idx
  on private.pachanga_team_cosmetic_reward_policy_events(policy_version);
