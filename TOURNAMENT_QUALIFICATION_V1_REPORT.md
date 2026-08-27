# Tournament Qualification V1

## Policies

Qualification is an explicit server-side snapshot, separate from the live
standings cache. Supported V1 policies are:

- `TOP_N_PER_GROUP`
- `TOP_N_PER_GROUP_PLUS_BEST_RUNNERS_UP`
- `TOP_N_PER_GROUP_PLUS_BEST_THIRDS`

Cross-Group comparison supports points, points per match, goal difference,
goal difference per match, goals for, goals for per match, wins, wins per match
and a persisted deterministic lot. Policies can require equal Group sizes and
must declare how unresolved cross-Group ties are decided.

## Lifecycle

1. `qualification.rebuild` creates an immutable provisional snapshot from the
   exact current Group StandingSnapshots.
2. `qualification.validate` verifies every Group is complete, all results are
   official, no blocking incident remains and every tie has canonical evidence.
3. `qualification.publish` creates a new immutable published snapshot and
   notifies the affected participants idempotently.
4. `bracket_template.create` maps published qualification slots without
   generating matches.
5. `bracket_template.publish` freezes the initial slot template.

The checksum covers sporting inputs: draw checksum, source standing checksums,
policy and qualification rows. It excludes opaque evidence identifiers so the
same sporting facts are reproducible.

## Safety

- A provisional snapshot cannot be published as final.
- Pending disputes, postponements and incomplete Groups block validation.
- A real official-result correction invalidates/supersedes stale qualification.
- Concurrent rebuilds, publication and result correction serialize through
  revision checks and database constraints.
- Bulk rows receive unique monotonic server sequences.
- Nullable eliminated slots cannot collide.
- Bracket publication never creates a `CanonicalMatch` and never advances a
  winner, loser, semifinalist, finalist or champion.

## Evidence

The canonical local scenario publishes 8 qualified slots from 4 Groups and
retains zero knockout matches. Qualification rebuild p95 is 21.845 ms and
publication p95 is 16.942 ms. The 10-race concurrency matrix covers two
rebuilds, result correction versus Group completion, qualification publication
versus correction, and bracket publication versus qualification supersession.

R6C progression is explicitly not implemented and remains feature-gated OFF.
