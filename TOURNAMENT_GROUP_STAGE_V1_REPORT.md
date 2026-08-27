# Tournament Group Stage V1

## Scope

R6B turns one published R6A group draw into an operational group stage without
creating a parallel match engine. PostgreSQL remains the only sporting
authority. The browser sends semantic intent with `operationId` and
`expectedRevision`; every successful command returns the canonical snapshot.

## Canonical graph

| R6B concept | Existing authority reused |
| --- | --- |
| Group membership | R6A `CompetitionGroup` and `StageMembership` |
| Round-robin schedule | R4B `SchedulePlan`, `ScheduleRevision`, `Round`, `ScheduleItem` |
| Sporting identity | one `CanonicalMatch` plus one `CompetitionMatchContext` |
| Attendance and squads | R4C authorities |
| Results and standings | R4C `OfficialResultDecision` and `StandingSnapshot` |
| Operational exceptions | R4D |
| Cards and sanctions | R5 |
| Referee | Referee Assignments |

No `TournamentMatch`, `TournamentResult`, `TournamentStanding`,
`TournamentAttendance`, `TournamentReferee` or `TournamentDiscipline` table was
introduced.

## Lifecycle

The bounded command surface is:

1. `group_stage.prepare`
2. `group_schedule.create`
3. `group_schedule.generate`
4. `group_schedule.validate`
5. `group_schedule.publish`
6. `group_stage.activate`
7. `group_stage.complete`
8. `qualification.rebuild`
9. `qualification.validate`
10. `qualification.publish`
11. `bracket_template.create`
12. `bracket_template.publish`

Preparation requires a Tournament, a published DrawPlan, the exact immutable
ParticipantFreeze, accepted entries, locked R4A rosters and one current
RuleRevision. Participant membership is frozen once scheduling starts.

## Authority and security

- Commands resolve actor, roles, grants, current revision and server time in
  PostgreSQL.
- Command receipts are idempotent; replay returns the confirmed result without
  applying the operation twice.
- Advisory locks and monotonic revisions serialize concurrent writes.
- Authenticated clients have no direct table-write authority.
- Read RPCs are bounded and actor-scoped; anonymous and unrelated authenticated
  discovery are rejected while public Tournament discovery remains OFF.
- Realtime carries invalidations. Clients refetch the canonical Hub instead of
  applying WAL payloads as sporting truth.
- Local storage is a versioned read cache only. Offline sporting writes are
  rejected and never displayed as confirmed.

## Flags

The six migrations add dependent flags born OFF for Group Stage, scheduling,
group match generation, tracking, group standings, qualification and bracket
template. The dependency trigger permanently forces knockout generation and
bracket progression OFF in R6B.

## Local certification

- Canonical SQL story: 4 groups, 24 fixtures, 24 CanonicalMatches, 24
  MatchContexts, 4 StandingSnapshots, one published QualificationSnapshot and
  an 8-slot published BracketTemplate.
- Direct writes: 0.
- Knockout matches: 0.
- Negative matrix: 18/18 expected rejections or safe outcomes, twice after the
  TeamJourney checkpoint fix.
- Concurrency: 10/10 races produce one winner and one stale/conflict result.
- Focused contract tests: 13/13.
- Full suite: Node 20/20 plus TS/TSX 536/536; zero skipped, todo or cancelled.
- Typecheck and production build: PASS.
- Focused ESLint: PASS across all 26 changed TS/TSX/MJS files.
- Global ESLint: pre-existing debt only, recorded as `R6B-TEST-073`.

The permanent incident ledger is
`R6B_TOURNAMENT_GROUP_STAGE_INCIDENTS.md`; every R6B correction retains its
original scenario and regression evidence.
