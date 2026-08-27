# Demo World V2.5 Tournament Group Stage Parity

## Identity

- Version: 2.5
- Seed: `pachangas-iq-demo-world-v2-5-2026-27`
- Manifest hash:
  `675d2992138de4253a0e9e09eab77d09682cecc708fc06a4f87ed0e6d15e57f8`
- PostgreSQL authority hash:
  `3d51909498c47762ee6256f6a71e5ab642fbd2a2f2fc953178d537ca54dd06af`
- Migration ledger used by the proof: 169
- Remote writes: 0
- Exported from temporary local PostgreSQL: no
- Temporary database destroyed after verification: yes

## Tournament story

Demo V2.5 preserves immutable V2.3 and V2.4 snapshots and adds one complete
R6A/R6B Tournament story:

- published 16-team, 4-Group draw;
- frozen participants and locked rosters;
- 3 rounds and 6 fixtures per Group;
- 24 Group fixtures with exact CanonicalMatch/MatchContext identity;
- future, completed, disputed/corrected and operational-exception states;
- attendance and squad context;
- R5 cards/sanctions and referee assignments;
- four Group standings;
- provisional and published qualification;
- published 8-slot bracket template;
- zero knockout matches and zero progression.

The world-wide manifest reports 30 teams, 331 players, 128 matches, 12 stories,
39 canonical matches and 12 notifications. R6B facts
come from the same deterministic PostgreSQL operation proof as the existing
R1-R6A authorities.

## UI parity

The public read-only Demo uses the production Tournament Hub component and its
ten tabs. It exposes Summary, Rounds, Matches, Standings, Team Journey,
Organizer Desk, Qualification and Bracket states without enabling product
writes. Desktop, portrait and Mobile Game Landscape styles are shared with the
product surface.

## Privacy and PWA

- Demo bundles contain no personal email, phone, token, secret, service-role
  key or remote mutation path.
- Historical chunks are immutable and hash-addressed.
- The Service Worker precaches the V2 entry and caches versioned Demo chunks.
- Offline Demo remains read-only and never reports a sporting write as success.

## Verification

`npm run demo-world:v2:verify` returns `snapshotIdentical=true`, migration
count 169, zero remote writes and the exact hashes above. The focused Demo,
R6A and R6B suite passes 44/44; the complete suite passes 556/556 across its
two runners.
