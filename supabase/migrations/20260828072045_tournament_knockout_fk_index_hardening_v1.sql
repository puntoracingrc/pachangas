-- Pachangas IQ Wave 7A: measured R6C foreign-key hardening.
--
-- Supabase Advisors reported 71 unindexed foreign keys across the 13 R6C
-- tables. The production tables are currently empty, so the selection below
-- is based on the shipped query paths and the R6C scale fixture rather than
-- current row counts. Actor, immutable lineage and direct-current-pointer
-- foreign keys remain deliberately unindexed because no production lookup
-- starts from those columns.

set lock_timeout = '5s';
set statement_timeout = '120s';

-- Canonical-match validation enters reservations from a schedule slot and
-- then confirms the owning node/revision.
create index if not exists pachanga_tournament_reservation_schedule_slot_idx
  on public.pachanga_tournament_bracket_fixture_reservations(
    schedule_slot_id, bracket_node_id, reservation_revision desc,
    server_sequence desc, id desc
  )
  where status = 'ACTIVE';

-- Tournament journeys and public bracket snapshots resolve a Team entry in
-- each possible node role. Separate partial indexes let PostgreSQL use a
-- BitmapOr for the existing IN/OR predicates without widening the hot
-- bracket-round index.
create index if not exists pachanga_tournament_node_home_entry_idx
  on public.pachanga_tournament_bracket_nodes(
    home_entry_id, bracket_id, round_order desc, node_order, id
  )
  where home_entry_id is not null;

create index if not exists pachanga_tournament_node_away_entry_idx
  on public.pachanga_tournament_bracket_nodes(
    away_entry_id, bracket_id, round_order desc, node_order, id
  )
  where away_entry_id is not null;

create index if not exists pachanga_tournament_node_winner_entry_idx
  on public.pachanga_tournament_bracket_nodes(
    winner_entry_id, bracket_id, round_order desc, node_order, id
  )
  where winner_entry_id is not null;

create index if not exists pachanga_tournament_node_loser_entry_idx
  on public.pachanga_tournament_bracket_nodes(
    loser_entry_id, bracket_id, round_order desc, node_order, id
  )
  where loser_entry_id is not null;

-- Slot ownership is read from entry -> bracket while rebuilding the canonical
-- public journey/read model.
create index if not exists pachanga_tournament_slot_resolved_entry_idx
  on public.pachanga_tournament_bracket_node_slots(
    resolved_entry_id, bracket_id, server_sequence desc, id desc
  )
  where resolved_entry_id is not null;

-- Operational impact review enters from the canonical match when a fixture is
-- replaced or invalidated.
create index if not exists pachanga_tournament_dependency_match_idx
  on public.pachanga_tournament_bracket_dependency_impacts(
    canonical_match_id, bracket_invalidation_id, server_sequence desc, id desc
  )
  where canonical_match_id is not null;

comment on index public.pachanga_tournament_reservation_schedule_slot_idx is
  'Wave 7A measured R6C index: active reservation lookup by canonical schedule slot.';
comment on index public.pachanga_tournament_dependency_match_idx is
  'Wave 7A measured R6C index: operational impact lookup by canonical match.';
