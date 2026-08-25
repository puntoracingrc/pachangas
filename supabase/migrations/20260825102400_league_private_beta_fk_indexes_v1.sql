-- Pachangas IQ League Private Beta V1: covering indexes for productization FKs.
-- Forward-only hardening after staging advisor readback; no flags or data change.

set lock_timeout = '5s';
set statement_timeout = '120s';

create index if not exists pachanga_league_beta_events_actor_idx
  on private.pachanga_league_private_beta_events(actor_id);
create index if not exists pachanga_league_beta_events_competition_idx
  on private.pachanga_league_private_beta_events(competition_id);
create index if not exists pachanga_league_beta_events_club_idx
  on private.pachanga_league_private_beta_events(organizer_club_id);
create index if not exists pachanga_league_beta_events_group_idx
  on private.pachanga_league_private_beta_events(organizer_group_id);

create index if not exists pachanga_league_beta_receipts_actor_idx
  on private.pachanga_league_private_beta_operation_receipts(actor_id);

create index if not exists pachanga_league_beta_invalidations_group_idx
  on public.pachanga_league_private_beta_invalidations(organizer_group_id);
create index if not exists pachanga_league_beta_invalidations_club_idx
  on public.pachanga_league_private_beta_invalidations(organizer_club_id);
create index if not exists pachanga_league_beta_invalidations_wizard_idx
  on public.pachanga_league_private_beta_invalidations(wizard_id);
