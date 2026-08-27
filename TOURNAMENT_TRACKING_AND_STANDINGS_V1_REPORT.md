# Tournament Tracking And Standings V1

## Match operations

Every Group fixture is operated through the existing canonical match graph.
R6B does not calculate results or standings in the browser and does not persist
a second Tournament result model.

- R4C owns attendance, squads, proposals, bilateral confirmations, official
  decisions and StandingSnapshots.
- R4D owns postponements, venue changes, late arrival, no-show, suspension and
  administrative decisions.
- R5 owns disciplinary events, counters, sanctions, service and appeals.
- Referee Assignments owns referee lifecycle and schedule conflicts.

Only official R4C decisions enter Group standings. Pending, disputed,
postponed or unofficial evidence cannot close the Group or publish final
qualification.

## Tournament Hub

The actor-scoped Hub returns one prepared read model with ten tabs:

`summary`, `rounds`, `matches`, `standings`, `teams`, `discipline`, `referees`,
`incidents`, `rules`, and `bracket`.

The Organizer Desk exposes only actions allowed by the server permissions. The
participant TeamJourney includes Group, current standing, recent results,
future matches, attendance counts, squad state, active sanctions, confirmed
referee and public incident state. Evidence, internal actors, private decision
reasons and fee data are not exposed.

Missing optional operational records use stable sentinels such as
`NOT_SUBMITTED` and `UNASSIGNED`, so cache consumers do not infer schema shape
from omitted keys.

## Standings

R6B consumes R4C StandingSnapshots per Group. Rebuild occurs when official
sporting evidence changes, not on every read. Snapshot selection uses revision,
server sequence and stable identifiers rather than timestamp alone.

The full local story creates 4 Group StandingSnapshots from 24 official
matches. The independent gates prove that an unofficial result is excluded,
an unresolved dispute blocks final qualification, a postponed match blocks
closure, and a corrected official decision serializes against qualification.

## Client convergence

- API reads and commands return `Cache-Control: no-store` for authority
  boundaries.
- The PWA keeps only derived, actor-scoped snapshots.
- Realtime invalidates the affected Tournament cache after real PostgreSQL
  changes; `SUBSCRIBED` alone does not cause a read loop.
- Reconnect and online events refetch the canonical snapshot.
- No optimistic sporting state or offline mutation queue exists.

Hub read p95 in the populated local fixture is 10.568 ms; Round read p95 is
0.897 ms and Group Standings read p95 is 0.978 ms.
