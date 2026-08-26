set local lock_timeout = '3s';
set local statement_timeout = '90s';

create index if not exists pachanga_referee_public_fee_consents_actor_idx
  on private.pachanga_referee_public_fee_consents(actor_id)
  where actor_id is not null;

create index if not exists pachanga_referee_result_observations_match_idx
  on private.pachanga_referee_result_observations(canonical_match_id);

create index if not exists pachanga_referee_result_observations_creator_idx
  on private.pachanga_referee_result_observations(created_by)
  where created_by is not null;

create index if not exists pachanga_referee_result_observations_profile_idx
  on private.pachanga_referee_result_observations(referee_profile_id);

create index if not exists pachanga_referee_assignments_cancelled_by_idx
  on public.pachanga_referee_assignments(cancelled_by)
  where cancelled_by is not null;

create index if not exists pachanga_referee_assignments_competition_idx
  on public.pachanga_referee_assignments(competition_id)
  where competition_id is not null;

create index if not exists pachanga_referee_assignments_proposed_by_idx
  on public.pachanga_referee_assignments(proposed_by)
  where proposed_by is not null;

create index if not exists pachanga_referee_assignments_replaced_by_idx
  on public.pachanga_referee_assignments(replaced_by_assignment_id)
  where replaced_by_assignment_id is not null;

create index if not exists pachanga_referee_assignments_replacement_pending_idx
  on public.pachanga_referee_assignments(replacement_pending_assignment_id)
  where replacement_pending_assignment_id is not null;

create index if not exists pachanga_referee_assignments_replaces_idx
  on public.pachanga_referee_assignments(replaces_assignment_id)
  where replaces_assignment_id is not null;

create index if not exists pachanga_referee_assignments_requester_club_idx
  on public.pachanga_referee_assignments(requester_club_id)
  where requester_club_id is not null;

create index if not exists pachanga_referee_assignments_requester_team_idx
  on public.pachanga_referee_assignments(requester_team_id)
  where requester_team_id is not null;

create index if not exists pachanga_referee_assignments_source_group_idx
  on public.pachanga_referee_assignments(source_group_id)
  where source_group_id is not null;
